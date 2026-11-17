#!/usr/bin/env python3
"""Headless check of inputmon.prg, the input monitor for both control ports.

usage: check_inputmon.py [--quick]

A py65 6502 runs the BASIC and KERNAL ROMs of the local VICE installation (read at run time from
the folder in the environment variable VICE_ROMS, nothing is copied). The KERNAL boots, the
program is put at $0801 and started with RUN. Around the CPU sits a model of the hardware that
the program touches:

* CIA 1: port A and port B with their data direction registers (a pin that is an input reads
  high unless something pulls it low), the interrupt control register (mask, flags, IR, cleared
  by a read) and timer A with latch, force load and continuous mode, which raises the IRQ of the
  CPU: the KERNAL's interrupt routine runs sixty times per second and scans the keyboard.
* The keyboard matrix (port A drives the columns, port B reads the rows, a pressed key connects
  both) and the five joystick lines of both control ports (port 1 on port B, port 2 on port A,
  low active).
* SID $D419 and $D41A: the paddle values of the port selected by bits 6 (port 1) and 7 (port 2)
  of the port A pins; neither selected reads 255, both read the AND of both ports. A change of
  the selection takes effect only after SETTLE cycles (1.6 ms at the NTSC clock, the stricter of
  the two): until then the SID returns the values of the previous selection.
* The screen memory at $0400 (what the program printed is read from there) and the raster
  counter for the PAL test of the KERNAL.

Checks: the values on the screen for many input vectors (both ports, every value at its place,
whole rows compared, so a stale digit is an error), no scrolling over many iterations, the wait
after each port switch, the STOP key at every moment of the loop (the first timer interrupt after
the press is moved across the loop in small steps, and STOP is held for a short time at moments
spread over several iterations), the CIA registers and a working keyboard after STOP, the petcat
round trip and the line length of the source. Two controls show that the checks can fail: a
variant of the program without POKE 56320,255 in line 30 must leave the keyboard dead in some
trials, and a SID that settles more slowly than the program waits must show wrong values.

Prints one line per check and RESULT: PASS or RESULT: FAIL; the exit status is 0 or 1 (2 if the
ROMs are missing). About four and a half minutes on one core; --quick uses coarser steps (about two
minutes)."""
import math, os, subprocess, sys, tempfile
from py65.devices.mpu6502 import MPU

HERE = os.path.dirname(os.path.abspath(__file__))
VICE_ROMS = os.environ.get("VICE_ROMS", "/Applications/Vice/VICE.app/Contents/Resources/share/vice/C64")
PETCAT = os.environ.get("PETCAT", "/Applications/Vice/bin/petcat")
PAL_HZ, NTSC_HZ = 985248, 1022727
SETTLE = math.ceil(0.0016 * NTSC_HZ)          # 1637 cycles: 1.6 ms at the faster (NTSC) clock
CYCLES_PER_LINE, LINES = 63, 312               # PAL raster
TIMER_PERIOD = 0x4025 + 1                      # timer A of the PAL KERNAL: 16422 cycles
KEY_STOP, KEY_A = (7, 7), (1, 2)               # (column = port A bit, row = port B bit)
NEVER = 1 << 62

# addresses in the BASIC and KERNAL ROMs
NEWSTT = 0xA7AE      # BASIC: next statement (polls STOP first)
STOP_RT = 0xF6ED     # KERNAL: STOP routine, tests $91
EDITOR_WAIT = 0xE5CD # KERNAL: the screen editor waits for a key
SCROLL = 0xE8EA      # KERNAL: scroll the screen up


def screen_char(c):
    c &= 0x7F
    if c == 0: return "@"
    if c <= 26: return chr(64 + c)
    if c < 32: return "[?]^?"[c - 27]
    if c < 64: return chr(c)
    return "?"


def ms(cycles, hz=PAL_HZ):
    return cycles / hz * 1000


class Machine:
    """C64 with the parts of the hardware the input monitor uses (see the module docstring)"""

    def __init__(self, basic, kernal, prg, settle=SETTLE):
        self.ram = bytearray(65536)
        self.basic, self.kernal, self.prg, self.settle = basic, kernal, prg, settle
        self.io = bytearray(0x1000)
        self.mpu = MPU(memory=self)
        self.ram[1] = 0x37
        self.mpu.pc = kernal[0x1FFC] | (kernal[0x1FFD] << 8)
        # CIA 1
        self.pra, self.prb, self.ddra, self.ddrb = 0, 0, 0, 0
        self.icr_mask, self.icr_flags, self.ir = 0, 0, False
        self.ta_latch, self.ta_counter, self.ta_run, self.ta_oneshot = 0xFFFF, 0xFFFF, False, False
        self.next_uf = NEVER
        # outside world
        self.keys = set()
        self.joy = {1: 0, 2: 0}                 # active lines, bit 0 up .. bit 4 fire
        self.pots = {1: (255, 255), 2: (255, 255)}
        self.sel = self.port_select()
        self.sel_hist = [(-NEVER, self.sel)]
        # observations
        self.sid_reads = []                     # (cycle, cycles since the last selection change, axis)
        self.events = []                        # (cycle, register, value, in an interrupt) of CIA 1 writes
        self.stop_polls = []                    # (cycle, $91, interrupt mask, DDRA) of every STOP poll
        self.irq_times = []
        self.scrolls = 0
        self.curlin = 0xFFFF
        self.line_starts = {}                   # line number -> how often it began
        self.state = "boot"

    # --- memory map ---------------------------------------------------------------------------
    def __len__(self):
        return 65536

    def now(self):
        return self.mpu.processorCycles

    def __getitem__(self, a):
        if a < 0xA000:
            return self.ram[a]
        p = self.ram[1]
        if a < 0xC000:
            return self.basic[a - 0xA000] if p & 3 == 3 else self.ram[a]
        if a < 0xD000:
            return self.ram[a]
        if a < 0xE000:
            if not p & 3:
                return self.ram[a]
            return self.io_read(a) if p & 4 else 0
        return self.kernal[a - 0xE000] if p & 2 else self.ram[a]

    def __setitem__(self, a, v):
        v &= 0xFF
        if 0xD000 <= a < 0xE000 and self.ram[1] & 3 and self.ram[1] & 4:
            self.io_write(a, v)
            return
        self.ram[a] = v

    # --- CIA 1 ports, keyboard, joysticks ------------------------------------------------------
    def pa_drive(self):
        return (self.pra | (~self.ddra & 0xFF)) & ~self.joy[2] & 0xFF

    def pb_drive(self):
        return (self.prb | (~self.ddrb & 0xFF)) & ~self.joy[1] & 0xFF

    def pa_pins(self):
        v, pb = self.pa_drive(), self.pb_drive()
        for c, r in self.keys:
            if not pb >> r & 1:
                v &= ~(1 << c)
        return v

    def pb_pins(self):
        v, pa = self.pb_drive(), self.pa_drive()
        for c, r in self.keys:
            if not pa >> c & 1:
                v &= ~(1 << r)
        return v

    def port_select(self):
        """bits 6 and 7 of the port A pins: bit 0 of the result = port 1, bit 1 = port 2"""
        return ((self.pra | (~self.ddra & 0xFF)) >> 6) & 3

    def selection_changed(self):
        s = self.port_select()
        if s != self.sel:
            t = self.now()
            self.sel = s
            self.sel_hist.append((t, s))
            while len(self.sel_hist) > 2 and self.sel_hist[1][0] <= t - self.settle:
                self.sel_hist.pop(0)

    def sid_pot(self, axis):
        t = self.now()
        self.sid_reads.append((t, t - self.sel_hist[-1][0], axis))
        eff = self.sel_hist[0][1]
        for ht, hs in self.sel_hist:
            if ht <= t - self.settle:
                eff = hs
        v = 255
        for port in (1, 2):
            if eff & port:
                v &= self.pots[port][axis]
        return v

    # --- CIA 1 interrupts and timer A ----------------------------------------------------------
    def timer_underflow(self):
        while self.now() >= self.next_uf:
            self.icr_flags |= 0x01
            if self.icr_mask & 0x01:
                self.ir = True
            if self.ta_oneshot:
                self.ta_run, self.next_uf = False, NEVER
            else:
                self.next_uf += self.ta_latch + 1

    def ta_value(self):
        if not self.ta_run:
            return self.ta_counter
        return max(0, self.next_uf - self.now() - 1) & 0xFFFF

    def io_read(self, a):
        if 0xDC00 <= a < 0xDD00:
            r = a & 0xFF0F
            if r == 0xDC00: return self.pa_pins()
            if r == 0xDC01: return self.pb_pins()
            if r == 0xDC02: return self.ddra
            if r == 0xDC03: return self.ddrb
            if r == 0xDC04: return self.ta_value() & 0xFF
            if r == 0xDC05: return self.ta_value() >> 8
            if r == 0xDC0D:
                self.timer_underflow()
                v = self.icr_flags | (0x80 if self.ir else 0)
                self.icr_flags, self.ir = 0, False
                return v
            if r == 0xDC0E:
                return (self.io[0xC0E] & 0xEE) | (1 if self.ta_run else 0)
            return self.io[r - 0xD000]
        if 0xD400 <= a < 0xD800:
            s = a & 0x1F
            if s == 0x19: return self.sid_pot(0)
            if s == 0x1A: return self.sid_pot(1)
            return 0
        line = (self.now() // CYCLES_PER_LINE) % LINES
        if a == 0xD012: return line & 0xFF
        if a == 0xD011: return (self.io[0x11] & 0x7F) | ((line >> 8) << 7)
        if a == 0xD019: return 0x01                 # the raster compare of the KERNAL's PAL test
        return self.io[a - 0xD000]

    def io_write(self, a, v):
        if not 0xDC00 <= a < 0xDD00:
            self.io[a - 0xD000] = v
            return
        r = a & 0xFF0F
        self.io[r - 0xD000] = v
        if r == 0xDC00:
            self.pra = v; self.selection_changed(); self.events.append((self.now(), "PRA", v, self.mpu.p & 4))
        elif r == 0xDC01:
            self.prb = v
        elif r == 0xDC02:
            self.ddra = v; self.selection_changed(); self.events.append((self.now(), "DDRA", v, self.mpu.p & 4))
        elif r == 0xDC03:
            self.ddrb = v
        elif r == 0xDC04:
            self.ta_latch = (self.ta_latch & 0xFF00) | v
        elif r == 0xDC05:
            self.ta_latch = (self.ta_latch & 0x00FF) | (v << 8)
            if not self.ta_run:
                self.ta_counter = self.ta_latch
        elif r == 0xDC0D:                           # bit 7: 1 sets, 0 clears the selected mask bits
            self.timer_underflow()
            if v & 0x80:
                self.icr_mask |= v & 0x1F
            else:
                self.icr_mask &= ~v & 0x1F
            if self.icr_flags & self.icr_mask:
                self.ir = True
            self.events.append((self.now(), "ICR", v, self.mpu.p & 4))
        elif r == 0xDC0E:
            self.timer_underflow()
            cnt = self.ta_latch if v & 0x10 else self.ta_value()
            self.ta_oneshot = bool(v & 0x08)
            if v & 0x01:
                self.ta_run, self.next_uf = True, self.now() + cnt + 1
            else:
                self.ta_run, self.ta_counter, self.next_uf = False, cnt, NEVER

    # --- running ---------------------------------------------------------------------------------
    def load_and_run(self):
        prg = self.prg
        load = prg[0] | (prg[1] << 8)
        assert load == 0x0801, hex(load)
        self.ram[load:load + len(prg) - 2] = prg[2:]
        end = load + len(prg) - 2
        self.ram[0x2D], self.ram[0x2E] = end & 0xFF, end >> 8
        for i, c in enumerate(b"RUN\r"):
            self.ram[0x0277 + i] = c
        self.ram[0xC6] = 4
        self.state = "run"

    def run(self, cycles=NEVER, until_line=None, until_ready=False):
        """runs for <cycles> cycles, or until line <until_line> begins, or until the editor waits"""
        mpu = self.mpu
        limit = mpu.processorCycles + cycles
        hooks = (NEWSTT, STOP_RT, EDITOR_WAIT, SCROLL)
        while True:
            c = mpu.processorCycles
            if c >= self.next_uf:
                self.timer_underflow()
            if self.ir and not mpu.p & 4:
                self.irq_times.append(c)
                mpu.irq()
                continue
            if c >= limit:
                return "limit"
            pc = mpu.pc
            if pc in hooks:
                if pc == NEWSTT:
                    ln = self.ram[0x39] | (self.ram[0x3A] << 8)
                    if ln != self.curlin:
                        self.curlin = ln
                        self.line_starts[ln] = self.line_starts.get(ln, 0) + 1
                        if ln == until_line:
                            mpu.step()
                            return "line"
                elif pc == STOP_RT:
                    self.stop_polls.append((c, self.ram[0x91], self.icr_mask, self.ddra))
                elif pc == SCROLL:
                    self.scrolls += 1
                elif pc == EDITOR_WAIT and self.ram[0xC6] == 0:
                    if self.state == "boot":
                        self.load_and_run()
                    elif until_ready:
                        return "ready"
            mpu.step()

    def snapshot(self):
        skip = ("mpu", "basic", "kernal", "prg")
        d = {k: (v.copy() if hasattr(v, "copy") else v) for k, v in self.__dict__.items() if k not in skip}
        m = self.mpu
        return d, (m.pc, m.a, m.x, m.y, m.sp, m.p, m.processorCycles)

    def restore(self, snap):
        d, regs = snap
        for k, v in d.items():
            setattr(self, k, v.copy() if hasattr(v, "copy") else v)
        m = self.mpu
        m.pc, m.a, m.x, m.y, m.sp, m.p, m.processorCycles = regs

    def row(self, r):
        return "".join(screen_char(self.ram[0x0400 + 40 * r + i]) for i in range(40))

    def screen(self):
        return [self.row(r) for r in range(25)]

    def break_point(self):
        """'line:statement' of the STOP poll that ended the program (OLDLIN, OLDTXT of BASIC)"""
        ln = self.ram[0x3B] | (self.ram[0x3C] << 8)
        txt = self.ram[0x3D] | (self.ram[0x3E] << 8)
        a = 0x0801
        while True:
            nxt = self.ram[a] | (self.ram[a + 1] << 8)
            if nxt == 0:
                return f"{ln}:?"
            if (self.ram[a + 2] | (self.ram[a + 3] << 8)) == ln:
                break
            a = nxt
        if not a + 4 <= txt < nxt:
            return f"{ln}:1"                        # GOTO 30: TXTPTR already in front of line 30
        colons, quote = 0, False
        for p in range(a + 4, txt):
            if self.ram[p] == 0x22:
                quote = not quote
            elif self.ram[p] == 0x3A and not quote:
                colons += 1
        return f"{ln}:{colons + 1}"


# --- the program and what it must show -----------------------------------------------------------
ROW_P1, ROW_P2 = 3, 4


def expected_rows(p1, p2, l1, l2):
    def row(port, pot, lines):
        return f"PORT {port}  X{pot[0]:4d}  Y{pot[1]:4d}  LINES{lines:3d}".ljust(40)
    return row(1, p1, l1), row(2, p2, l2)


def boot(basic, kernal, prg, settle=SETTLE):
    m = Machine(basic, kernal, prg, settle)
    assert m.run(cycles=8_000_000, until_line=30) == "line", "the program did not reach line 30"
    return m


def to_iteration_end(m):
    """the next complete iteration: from the next start of line 30 to the start of line 140"""
    assert m.run(cycles=3_000_000, until_line=30) == "line"
    assert m.run(cycles=3_000_000, until_line=140) == "line"


def snapshot_at_loop_start(m):
    """state at the STOP poll after GOTO 30, the poll in front of the first statement of line 30"""
    assert m.run(cycles=3_000_000, until_line=140) == "line"
    while True:
        m.run(cycles=1)
        if m.mpu.pc == NEWSTT and (m.ram[0x39] | (m.ram[0x3A] << 8)) == 140:
            if m[m.ram[0x7A] | (m.ram[0x7B] << 8)] == 0:     # TXTPTR in front of line 30: GOTO done
                return m.snapshot()


def after_stop(m, res):
    """STOP is released: the CIA registers after two interrupts, then an A typed at READY"""
    m.keys = set()
    m.run(cycles=2 * TIMER_PERIOD)
    res["after"] = (m.pra, m.ddra, m.ddrb, m.icr_mask, m.ta_run)
    pos = 0x0400 + 40 * m.ram[0xD6] + m.ram[0xD3]
    m.keys = {KEY_A}
    m.run(cycles=2 * TIMER_PERIOD)
    m.keys = set()
    m.run(cycles=TIMER_PERIOD)
    res["typed"] = m.ram[pos] & 0x7F == 1
    return res


def stop_trial(m, snap, phase):
    """STOP is pressed at the start of the loop and held until READY; the first timer interrupt
    after the press comes <phase> cycles later"""
    m.restore(snap)
    m.stop_polls, m.events = [], []
    t0 = m.now()
    m.next_uf = t0 + phase
    m.keys = {KEY_STOP}
    res = {"phase": phase, "ended": m.run(cycles=2_000_000, until_ready=True) == "ready"}
    res["latency"] = m.now() - t0 - phase
    res["break"] = m.break_point()
    res["hits"] = [p[2:] for p in m.stop_polls if p[1] == 0x7F]
    return after_stop(m, res)


def hold_trial(m, snap, at, hold):
    """STOP is pressed <at> cycles after the start of the loop (timer as it runs) for <hold> cycles"""
    m.restore(snap)
    m.stop_polls = []
    m.run(cycles=at)
    m.keys = {KEY_STOP}
    r = m.run(cycles=hold, until_ready=True)
    if r != "ready":
        m.keys = set()
        r = m.run(cycles=1_000_000, until_ready=True)
    res = {"at": at, "ended": r == "ready", "break": m.break_point() if r == "ready" else None,
           "hits": [p[2:] for p in m.stop_polls if p[1] == 0x7F]}
    return after_stop(m, res)


KERNAL_STATE = (0x7F, 0xFF, 0x00, 0x01, True)    # $DC00, $DC02, $DC03, interrupt mask, timer A runs


def stop_ok(r):
    return (r["ended"] and r["hits"] and all(h == (0x01, 0xFF) for h in r["hits"])
            and r["after"] == KERNAL_STATE and r["typed"])


class Report:
    def __init__(self):
        self.fails = 0

    def __call__(self, ok, name, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'} {name}{': ' + detail if detail else ''}", flush=True)
        self.fails += 0 if ok else 1


def main():
    quick = "--quick" in sys.argv[1:]
    roms = [os.path.join(VICE_ROMS, f) for f in ("basic-901226-01.bin", "kernal-901227-03.bin")]
    missing = [f for f in roms if not os.path.isfile(f)]
    if missing:
        print(f"check_inputmon.py: missing {', '.join(missing)}: set VICE_ROMS to the C64 ROM folder of VICE")
        print("RESULT: FAIL")
        sys.exit(2)
    basic, kernal = (open(f, "rb").read() for f in roms)
    prg = open(os.path.join(HERE, "inputmon.prg"), "rb").read()
    ck = Report()

    # --- source, tokenized program ---
    src = [l for l in open(os.path.join(HERE, "inputmon.bas")).read().splitlines() if l.strip()]
    longest = max(len(l) for l in src)
    ck(longest <= 80, "source lines at most 80 characters", f"{len(src)} lines, longest {longest}")
    if os.path.isfile(PETCAT):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "list.txt")
            subprocess.run([PETCAT, "-2", "-nh", "-o", out, "--", os.path.join(HERE, "inputmon.prg")],
                           capture_output=True, text=True)
            listing = [l.strip() for l in open(out).read().splitlines() if l.strip()] if os.path.isfile(out) else []
        ck(listing == [l.strip().lower() for l in src], "petcat detokenizes inputmon.prg back to inputmon.bas",
           f"{len(listing)} lines")
    else:
        ck(False, "petcat round trip", f"petcat not found at {PETCAT} (set PETCAT)")
    ck(prg[:2] == b"\x01\x08", "load address $0801, started with RUN")

    # --- boot and first screen ---
    m = boot(basic, kernal, prg)
    to_iteration_end(m)
    scr = m.screen()
    ck(scr[0].startswith("INPUT MONITOR, STOP ENDS IT") and scr[1].startswith("TOUCH NO OTHER KEY WHILE IT RUNS"),
       "title rows", f"'{scr[0].rstrip()}' / '{scr[1].rstrip()}'")
    e1, e2 = expected_rows((255, 255), (255, 255), 0, 0)
    ck(scr[ROW_P1] == e1 and scr[ROW_P2] == e2, "nothing connected", f"'{scr[ROW_P1].rstrip()}' / '{scr[ROW_P2].rstrip()}'")

    # --- values ---
    vals = [0, 9, 64, 100, 191, 255, 1, 128, 99, 10, 5, 200]
    line_vecs = [(1, 0), (2, 0), (4, 0), (8, 0), (16, 0), (0, 1), (0, 2), (0, 4), (0, 8), (0, 16),
                 (31, 0), (0, 31), (31, 31), (5, 24), (24, 5), (17, 3), (3, 17), (12, 0), (0, 12), (0, 0),
                 (16, 1), (2, 16), (6, 9), (9, 6)]
    vectors = []
    for i, lv in enumerate(line_vecs):
        vectors.append(((vals[i % 12], vals[(i + 3) % 12], vals[(i + 6) % 12], vals[(i + 9) % 12]), lv))
    shrink = [((255, 255, 255, 255), (31, 31)), ((0, 9, 5, 1), (1, 0)), ((191, 100, 128, 255), (16, 31)),
              ((9, 0, 1, 7), (0, 1)), ((99, 64, 10, 200), (24, 12)), ((3, 3, 3, 3), (2, 4)), ((255, 0, 255, 0), (31, 0)),
              ((0, 255, 0, 255), (0, 31))]

    def show(vecs, machine):
        bad = []
        for (a, b, c, d), (l1, l2) in vecs:
            machine.pots, machine.joy = {1: (a, b), 2: (c, d)}, {1: l1, 2: l2}
            to_iteration_end(machine)
            s = machine.screen()
            e1, e2 = expected_rows((a, b), (c, d), l1, l2)
            if s[ROW_P1] != e1 or s[ROW_P2] != e2:
                bad.append(f"want '{e1.rstrip()}' / '{e2.rstrip()}', shown '{s[ROW_P1].rstrip()}' / '{s[ROW_P2].rstrip()}'")
        return bad

    bad = show(vectors, m)
    placed = {(pos, v) for (p, _) in vectors for pos, v in enumerate(p)}
    every = all((pos, v) in placed for pos in range(4) for v in (0, 9, 64, 100, 191, 255))
    ck(not bad and every, "paddle values and lines of both ports at their places",
       f"{len(vectors)} vectors, each of 0 9 64 100 191 255 in each of the four values, the five lines of each port "
       "alone and combined" + ("; " + bad[0] if bad else ""))
    bad = show(shrink, m)
    ck(not bad, "no stale characters when values get shorter",
       f"{len(shrink)} vectors, 255 to 0 and 9, 191 to 1, 31 to 0 and 1, whole rows compared" + ("; " + bad[0] if bad else ""))

    waits = [w for _, w, axis in m.sid_reads if axis == 0]
    wmin = min(waits)
    loop_tok = b":\x81 W\xb21 \xa4 2:\x82"           # :FOR W=1 TO 2:NEXT
    assert prg.count(loop_tok) == 2
    m4 = boot(basic, kernal, prg.replace(loop_tok, b" " * len(loop_tok)))
    for _ in range(3):
        to_iteration_end(m4)
    loop = wmin - min(w for _, w, axis in m4.sid_reads if axis == 0)
    ck(wmin >= SETTLE, "wait from a port switch to the first SID read",
       f"at least {wmin} cycles = {ms(wmin):.1f} ms PAL, {ms(wmin, NTSC_HZ):.1f} ms NTSC, of which FOR W=1 TO 2:NEXT "
       f"{loop} cycles = {ms(loop):.1f} ms PAL (needed: {SETTLE} cycles)")

    # --- no scrolling over many iterations ---
    m.pots, m.joy = {1: (100, 0), 2: (9, 255)}, {1: 16, 2: 1}
    to_iteration_end(m)
    iters = 30 if quick else 100
    s0, rows_before, t0, n30 = m.scrolls, m.screen(), m.now(), m.line_starts.get(30, 0)
    m.events, m.irq_times = [], []
    for _ in range(iters):
        to_iteration_end(m)
    period = (m.now() - t0) / (m.line_starts[30] - n30)
    rows_after = m.screen()
    ck(m.scrolls == s0 and rows_after == rows_before and all(r.strip() == "" for r in rows_after[5:]),
       f"{iters} more iterations without scrolling, screen unchanged", f"one iteration {period:.0f} cycles = {ms(period):.0f} ms PAL")

    # --- timing of the critical section ---
    ev = [e for e in m.events if not e[3]]       # the writes of the program, not of the interrupt routine
    win, crit = [], []
    for i, (t, what, v, _) in enumerate(ev):
        if (what, v) == ("ICR", 127) and i and ev[i - 1][1:3] == ("PRA", 255):
            win.append(t - ev[i - 1][0])
        if (what, v) == ("ICR", 127):
            nxt = next((e[0] for e in ev[i + 1:] if e[1:3] == ("ICR", 129)), None)
            if nxt:
                crit.append(nxt - t)
    gaps = [b - a for a, b in zip(m.irq_times, m.irq_times[1:])]
    ck(bool(win) and len(win) >= iters - 1 and max(win) < TIMER_PERIOD,
       "line 30: from POKE 56320,255 to POKE 56333,127 less than one timer period",
       f"at most {max(win)} cycles of {TIMER_PERIOD}: at most one interrupt in between, and it cannot see STOP")
    ck(bool(crit), "timer interrupt off from line 30 to line 80",
       f"at most {max(crit)} cycles = {ms(max(crit)):.0f} ms per iteration; longest gap between two interrupts "
       f"{max(gaps)} cycles = {ms(max(gaps)):.0f} ms")

    # --- STOP held until READY, the first interrupt after the press moved across the loop ---
    m.joy = {1: 0, 2: 0}
    to_iteration_end(m)
    snap = snapshot_at_loop_start(m)
    m.restore(snap)
    m.events = []
    m.run(cycles=40000)
    t_snap = snap[1][6]
    t_pra = next(e[0] for e in m.events if e[1:] == ("PRA", 255, 0)) - t_snap
    t_icr = next(e[0] for e in m.events if e[1:] == ("ICR", 127, 0)) - t_snap
    step = 3000 if quick else 1000
    phases = set(range(0, int(period) + TIMER_PERIOD, step))
    phases |= set(range(0, t_icr + 3000, 600 if quick else 200))
    for edge in (t_pra, t_icr):
        phases |= set(range(max(0, edge - 120), edge + 120, 12 if quick else 4))
    results = [stop_trial(m, snap, ph) for ph in sorted(phases)]
    bad = [r for r in results if not stop_ok(r)]
    points = sorted({r["break"] for r in results}, key=lambda s: [int(x) if x.isdigit() else 99999 for x in s.split(":")])
    lat = max(r["latency"] for r in results)
    ck(not bad, "STOP held: ends the program wherever the first interrupt after the press comes",
       f"{len(results)} trials, BREAK at line:statement {' '.join(points)}, at most {ms(lat):.0f} ms after that interrupt"
       + (f"; first failure {bad[0]}" if bad else ""))
    ck(all(h == (0x01, 0xFF) for r in results for h in r["hits"]),
       "every STOP poll that sees the key runs with the timer interrupt on and $DC02 = $FF",
       f"{sum(len(r['hits']) for r in results)} such polls")
    ck(all(r["after"] == KERNAL_STATE for r in results),
       "after STOP: $DC00 = $7F, $DC02 = $FF, $DC03 = $00, timer A interrupt enabled, timer running")
    ck(all(r["typed"] for r in results), "after STOP the keyboard works: an A typed at READY appears")

    # --- STOP pressed for a short time at moments spread over several iterations ---
    hold = int(0.25 * PAL_HZ)
    n = 24 if quick else 72
    holds = [hold_trial(m, snap, int(k * 3 * period / n) + 17, hold) for k in range(n)]
    bad = [r for r in holds if not stop_ok(r)]
    ck(not bad, "STOP pressed for 0.25 s at any moment ends the program",
       f"{n} presses spread over three iterations" + (f"; first failure {bad[0]}" if bad else ""))

    # --- the KERNAL does not see STOP while a line of port 1 is low ---
    m.restore(snap)
    m.joy, m.keys = {1: 16, 2: 0}, {KEY_STOP}
    held = m.run(cycles=int(0.5 * PAL_HZ), until_ready=True)
    m.joy = {1: 0, 2: 0}
    released = m.run(cycles=int(0.5 * PAL_HZ), until_ready=True)
    m.keys = set()
    ck(held == "limit" and released == "ready", "STOP while fire of port 1 is held: not seen by the KERNAL, seen after the release",
       f"{'running' if held == 'limit' else 'ended'} after 0.5 s with fire held, "
       f"{'ended' if released == 'ready' else 'still running'} after the release")

    # --- control 1: without POKE 56320,255 in line 30 the same STOP sweep must find a dead keyboard ---
    tok = b"\x97 56320,255:"
    assert prg.count(tok) == 1
    m2 = boot(basic, kernal, prg.replace(tok, b" " * len(tok)))
    for _ in range(3):
        to_iteration_end(m2)
    snap2 = snapshot_at_loop_start(m2)
    res2 = [stop_trial(m2, snap2, ph) for ph in range(0, t_icr + 3000, 600 if quick else 200)]
    dead = [r for r in res2 if not stop_ok(r)]
    ck(bool(dead) and all(r["after"][3] == 0 and not r["typed"] for r in dead),
       "control: the same program without POKE 56320,255 leaves the keyboard dead after some STOPs",
       f"{len(dead)} of {len(res2)} trials end with the timer interrupt off, e.g. BREAK at {dead[0]['break']}"
       if dead else f"0 of {len(res2)} trials")

    # --- control 2: a SID that settles more slowly than the program waits shows wrong values ---
    m3 = boot(basic, kernal, prg, settle=wmin + 500)
    to_iteration_end(m3)
    wrong = show([((10, 20, 30, 40), (0, 0)), ((200, 100, 50, 25), (0, 0))], m3)
    ck(len(wrong) == 2, f"control: with a settle time of {wmin + 500} cycles the values are wrong",
       wrong[0] if wrong else "the values are right")

    print("RESULT: " + ("PASS" if not ck.fails else f"FAIL ({ck.fails})"))
    sys.exit(1 if ck.fails else 0)


if __name__ == "__main__":
    main()
