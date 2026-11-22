#!/usr/bin/env python3
"""
Headless test of the keyboard controller M2M/rom/keyboard.asm and of the
typematic repeat of its cursor keys:

  * A key is reported once when it is pressed (KEYB$SCAN notes it as new,
    KEYB$GETKEY returns the new keys one by one, the lowest bit first) and
    only again after it was released.
  * A cursor key that is held repeats: the first repeat comes when
    M2M$TYPEMATIC_DLY ticks of the cycle counter (IO$CYC_MID, 763 Hz) have
    passed since the scan that saw the key pressed, then one every
    M2M$TYPEMATIC_SPD ticks, counted from the scan of the last repeat. A
    repeat marks the key as not pressed, so the next scan reports it as new.
    Only the time counts, not the number of scans: the loops of the Shell
    that call KEYB$SCAN differ a lot in how much they do per scan.
  * The other keys never repeat. KEYB$INIT starts the cycle counter and
    counts every key as pressed, so a key that is held during the start is
    only reported after it was released.

The script copies keyboard.asm and keyboard_vars.asm and rewires the keyboard
register (M2M$KEYBOARD), IO$CYC_MID and IO$CYC_STATE to variables of the
testbed. A script of segments (keys, number of scans, ticks per scan) drives
KEYB$SCAN and KEYB$GETKEY, one of each per scan like the loops of the Shell,
and the testbed prints every key that KEYB$GETKEY returns with its time. An
independent Python model, written from the rules above, gives the expected
keys. The segments: random combinations of the four cursor keys, Return,
Space and F1, scans that come several times per tick or hundreds of ticks
apart (a long redraw), a time that wraps around at 65536 ticks, and a long
hold of each cursor key. Then the script applies mutants to the copy of
keyboard.asm, each of which has to be caught, and counts the instructions
of KEYB$SCAN plus KEYB$GETKEY per scan (the real cycle counter of the
emulator counts instructions).

Run it from anywhere:
    python3 typematic_test.py
    python3 typematic_test.py --perf-only <keyboard.asm> <keyboard_vars.asm>
The second form only counts the instructions per scan of other versions of
the files, for example of the version that counted the delays in scans.

Needs the QNICE assembler, emulator and monitor.out, see README.md.

Licensed under GPL v3
"""
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
QNICE = os.path.join(REPO, "M2M", "QNICE")
ASM = os.path.join(QNICE, "assembler", "asm")
EMU = os.path.join(QNICE, "emulator", "qnice")
MON = os.path.join(QNICE, "monitor", "monitor.out")
KEYBOARD = os.path.join(REPO, "M2M", "rom", "keyboard.asm")
KEYBOARD_VARS = os.path.join(REPO, "M2M", "rom", "keyboard_vars.asm")
M2MSYSDEF = os.path.join(REPO, "M2M", "rom", "sysdef.asm")
QSYSDEF = os.path.join(QNICE, "dist_kit", "sysdef.asm")
MONDEF = os.path.join(QNICE, "dist_kit", "monitor.def")


def equ(path, name):
    for line in open(path, errors="replace"):
        m = re.match(r"^%s\s+\.EQU\s+(0x[0-9A-Fa-f]+|\d+)" % re.escape(name), line)
        if m:
            return int(m.group(1), 0)
    sys.exit("cannot find %s in %s" % (name, path))


KEY = {k: equ(M2MSYSDEF, "M2M$KEY_" + k) for k in ("UP", "DOWN", "LEFT", "RIGHT", "RETURN",
                                                     "SPACE", "F1")}
CURSOR = [KEY["DOWN"], KEY["UP"], KEY["LEFT"], KEY["RIGHT"]]
DLY = equ(M2MSYSDEF, "M2M$TYPEMATIC_DLY")
SPD = equ(M2MSYSDEF, "M2M$TYPEMATIC_SPD")
CYC_RUN = equ(QSYSDEF, "CYC$RUN")
TICK_MS = 65536 / 50e6 * 1000                   # one tick of IO$CYC_MID

REWIRE = [(r"M2M\$KEYBOARD", "TB_KEYB"), (r"IO\$CYC_MID", "TB_CYC"),
          (r"IO\$CYC_STATE", "TB_CYCST")]


def rewired(path):
    s = open(path).read()
    for a, b in REWIRE:
        s = re.sub(a, b, s)
    return s


TESTBED = r"""
#include "@QSYSDEF@"
#include "@MONDEF@"
#include "@M2MSYSDEF@"
@PERF@
                .ORG    0x8000

                MOVE    TB_CYCST, R0            ; KEYB$INIT has to start the
                MOVE    0, @R0                  ; cycle counter
                MOVE    TB_KEYB, R0
                MOVE    0xFFFF, @R0             ; low active: no key
                MOVE    TB_CYC, R0
                MOVE    @START@, @R0
                RSUB    KEYB$INIT, 1
                MOVE    TB_R_STR, R8            ; "R state-of-the-counter"
                SYSCALL(puts, 1)
                MOVE    TB_CYCST, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)

#ifndef TB_PERF
; segments: keys (low active), scans, ticks per scan; 0 scans end the list
                MOVE    TB_SEGS, R0
_TB_SEG         MOVE    @R0++, R1               ; R1: keys
                MOVE    @R0++, R2               ; R2: scans
                RBRA    _TB_END, Z
                MOVE    @R0++, R3               ; R3: ticks per scan
                MOVE    TB_KEYB, R4
                MOVE    R1, @R4
_TB_SCAN        MOVE    TB_CYC, R4
                ADD     R3, @R4
                RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                CMP     0, R8
                RBRA    _TB_NOKEY, Z
                MOVE    R8, R5                  ; "E time key"
                MOVE    TB_E_STR, R8
                SYSCALL(puts, 1)
                MOVE    TB_CYC, R8
                MOVE    @R8, R8
                SYSCALL(puthex, 1)
                MOVE    0x0020, R8
                SYSCALL(putc, 1)
                MOVE    R5, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
_TB_NOKEY       SUB     1, R2
                RBRA    _TB_SCAN, !Z
                RBRA    _TB_SEG, 1
#else
; instructions of 1000 scans with KEYB$SCAN and KEYB$GETKEY for each entry
; of TB_PKEYS (keys, low active), minus the empty loop: "P keys low middle"
                MOVE    TB_PKEYS, R0
_TB_PNEXT       MOVE    @R0++, R1
                RBRA    _TB_END, Z
                MOVE    TB_KEYB, R4
                MOVE    R1, @R4
                RSUB    KEYB$SCAN, 1            ; held since a while: the
                RSUB    KEYB$GETKEY, 1          ; cursor keys wait for the..
                MOVE    TB_CYC, R4              ; ..delay (state 1)
                ADD     1, @R4
                RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                MOVE    IO$CYC_STATE, R4
                MOVE    CYC$RESET, @R4
                MOVE    1000, R2
_TB_PSCAN       RSUB    KEYB$SCAN, 1
                RSUB    KEYB$GETKEY, 1
                SUB     1, R2
                RBRA    _TB_PSCAN, !Z
                MOVE    IO$CYC_LO, R4
                MOVE    @R4, R5
                MOVE    IO$CYC_MID, R4
                MOVE    @R4, R6
                MOVE    TB_P_STR, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                SYSCALL(puthex, 1)
                MOVE    0x0020, R8
                SYSCALL(putc, 1)
                MOVE    R5, R8
                SYSCALL(puthex, 1)
                MOVE    0x0020, R8
                SYSCALL(putc, 1)
                MOVE    R6, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                RBRA    _TB_PNEXT, 1
#endif

_TB_END         MOVE    TB_DONE_STR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; keyboard.asm and keyboard_vars.asm with the registers rewired
; ----------------------------------------------------------------------------

@KEYBOARD@

@KEYBOARD_VARS@

TB_KEYB         .BLOCK  1
TB_CYC          .BLOCK  1
TB_CYCST        .BLOCK  1
TB_R_STR        .ASCII_W "R "
TB_E_STR        .ASCII_W "E "
TB_P_STR        .ASCII_W "P "
TB_DONE_STR     .ASCII_W "DONE"

TB_PKEYS        .DW     0xFFFF, @PKEYS@, 0
TB_SEGS         @SEGS@
                .DW     0xFFFF, 0, 0
"""


def fill(template, values):
    for k, v in values.items():
        template = template.replace("@%s@" % k, str(v))
    return template


def run(keyboard, keyboard_vars, segs, perf, start, work):
    rows = []
    for j in range(0, len(segs), 6):
        rows.append(".DW     " + ", ".join("0x%04X, %d, %d" % (0xFFFF & ~k, n, dt)
                                           for k, n, dt in segs[j:j + 6]))
    src = fill(TESTBED, dict(QSYSDEF=QSYSDEF, MONDEF=MONDEF, M2MSYSDEF=M2MSYSDEF,
                             PERF="#define TB_PERF" if perf else "", START=start,
                             KEYBOARD=keyboard, KEYBOARD_VARS=keyboard_vars,
                             SEGS="\n                ".join(rows) if rows else "",
                             PKEYS=", ".join("0x%04X" % (0xFFFF & ~k) for k in PERF_KEYS)))
    open(os.path.join(work, "typematic_tb.asm"), "w").write(src)
    out = os.path.join(work, "typematic_tb.out")
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([ASM, "typematic_tb.asm"], cwd=work, capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, "assembly failed: " + (r.stdout + r.stderr)[-3000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return None, "emulator timeout"
    lines = [l.strip() for l in r.stdout.replace("\r", "").split("\n") if l.strip()]
    if "DONE" not in lines:
        return None, "the testbed did not finish: " + "\n".join(lines[-10:])
    first = next((i for i, l in enumerate(lines) if l.startswith("R ")), 0)
    return lines[first:lines.index("DONE")], ""


# ---------------------------------------------------------------------------
# Model, written from the rules in the description
# ---------------------------------------------------------------------------
def model(segs, start):
    """Expected (time, key) events"""
    # KEYB$INIT counts every key as pressed, so a key that is held from the
    # start is only reported after it was released (or repeated)
    t, registered, newkeys, events = start, 0xFFFF, 0, []
    since, waiting, repeating = {}, set(), set()
    for keys, n, dt in segs:
        for _ in range(n):
            t = (t + dt) & 0xFFFF
            newkeys |= keys & ~registered       # pressed and not registered
            registered = keys
            for k in CURSOR:
                if not keys & k:
                    waiting.discard(k)
                    repeating.discard(k)
                    continue
                if k not in waiting and k not in repeating:
                    since[k] = t                # the scan that saw the press
                    waiting.add(k)
                    continue
                limit = DLY if k in waiting else SPD
                if (t - since[k]) & 0xFFFF >= limit:
                    registered &= ~k            # reported again next scan
                    since[k] = t
                    waiting.discard(k)
                    repeating.add(k)
            if newkeys:
                k = newkeys & -newkeys          # lowest bit first
                newkeys &= ~k
                events.append((t, k))
    return events


def segments(seed):
    rnd = random.Random(seed)
    keys = CURSOR + [KEY["RETURN"], KEY["SPACE"], KEY["F1"]]
    segs = []
    for _ in range(900):
        combo = 0
        for k in rnd.sample(keys, rnd.choice((0, 1, 1, 1, 2, 2, 3))):
            combo |= k
        kind = rnd.random()
        if kind < 0.5:                          # several scans per tick
            segs.append((combo, rnd.randint(1, 200), rnd.choice((0, 0, 0, 1))))
        elif kind < 0.9:                        # a scan every few ticks
            segs.append((combo, rnd.randint(1, 120), rnd.randint(1, 12)))
        else:                                   # long pauses between scans
            segs.append((combo, rnd.randint(1, 6), rnd.randint(50, 900)))
    for k in CURSOR:                            # each cursor key held for 3 s
        segs.append((0, 3, 1))
        segs.append((k, 2289, 1))
    return segs


def check(lines, segs, start):
    if not lines or lines[0] != "R %04X" % CYC_RUN:
        return ["KEYB$INIT did not start the cycle counter: %r" % (lines[:1],)]
    got = []
    for l in lines[1:]:
        p = l.split()
        if p[0] != "E" or len(p) != 3:
            return ["unexpected line: " + l]
        got.append((int(p[1], 16), int(p[2], 16)))
    want = model(segs, start)
    if got == want:
        return []
    k = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]),
             min(len(got), len(want)))
    return ["%d keys, model %d; first difference at key %d: %s, model %s"
            % (len(got), len(want), k, got[k] if k < len(got) else "-",
               want[k] if k < len(want) else "-")]


def hold_timing(events, k):
    """Times (ms) from the press to the first repeat and between repeats of
    a cursor key that is held, from the events of its long hold"""
    t = [e[0] for e in events if e[1] == k]
    return (t[1] - t[0]) * TICK_MS, [(b - a) * TICK_MS for a, b in zip(t[1:], t[2:])], len(t)


PERF_KEYS = [KEY["DOWN"], KEY["DOWN"] | KEY["RIGHT"]]

MUTANTS = [
    ("delay and repeat speed swapped",
     "MOVE    M2M$TYPEMATIC_DLY, R3", "MOVE    M2M$TYPEMATIC_SPD, R3"),
    ("the repeat does not restart the time",
     "                MOVE    R12, @R10               ; remember the time and..\n"
     "                MOVE    2, @R0", "                MOVE    2, @R0"),
    ("the repeat keeps waiting for the delay",
     "                MOVE    2, @R0                  ; ..repeat from now on\n", ""),
    ("the press does not note the time",
     "                MOVE    R12, @R10               ; yes: remember the time and..\n", ""),
    ("a released cursor down keeps its state",
     "_KEYB_SCAN_DN0  MOVE    KEYB_CDN_STATE, R4      ; not pressed: clear state\n"
     "                MOVE    0, @R4\n",
     "_KEYB_SCAN_DN0  MOVE    KEYB_CDN_STATE, R4      ; not pressed: clear state\n"),
    ("cursor right never repeats",
     "                MOVE    KEYB_CRT_TIME, R10\n                RSUB    _KEYB_TYPEMATIC, 1\n",
     "                MOVE    KEYB_CRT_TIME, R10\n"),
    ("the repeat comes one tick late",
     "_KEYB_TYPEM_C   CMP     R3, R2", "_KEYB_TYPEM_C   ADD     1, R3\n                CMP     R3, R2"),
    ("KEYB$INIT does not start the cycle counter",
     "                OR      CYC$RUN, @R0", "                MOVE    R0, R0"),
]


def perf(keyboard, keyboard_vars, work):
    lines, err = run(keyboard, keyboard_vars, [], True, 0, work)
    if lines is None:
        sys.exit("FAIL: perf run: " + err)
    res = {}
    for l in lines[1:]:
        p = l.split()
        keys, lo, mid = int(p[1], 16), int(p[2], 16), int(p[3], 16)
        res[0xFFFF & ~keys] = (lo + (mid << 16)) / 1000.0
    names = {0: "no key", KEY["DOWN"]: "Down held",
             KEY["DOWN"] | KEY["RIGHT"]: "Down and Right held"}
    return "\n".join("  %-22s %6.1f instructions per scan (KEYB$SCAN, KEYB$GETKEY and the loop)"
                     % (names[k], v) for k, v in sorted(res.items()))


def main():
    for f in (ASM, EMU, MON):
        if not os.path.exists(f):
            sys.exit("missing %s, see README.md" % f)
    work = tempfile.mkdtemp(prefix="typematic_test_")
    try:
        if len(sys.argv) == 4 and sys.argv[1] == "--perf-only":
            print("Instructions per scan of %s:" % sys.argv[2])
            print(perf(rewired(sys.argv[2]), rewired(sys.argv[3]), work))
            return 0

        keyboard, keyboard_vars = rewired(KEYBOARD), rewired(KEYBOARD_VARS)
        cases = [(segments(1), 0x0000), (segments(2), 0xFE00), (segments(3), 0x7F00)]
        total = 0
        for segs, start in cases:
            lines, err = run(keyboard, keyboard_vars, segs, False, start, work)
            if lines is None:
                print("FAIL: " + err)
                return 1
            errors = check(lines, segs, start)
            if errors:
                print("FAIL: start time 0x%04X: %s" % (start, errors[0]))
                return 1
            total += len(lines) - 1
        print("OK: %d scans in 3 runs, %d keys, all as in the model"
              % (sum(n for segs, s in cases for k, n, dt in segs), total))

        hold = [(0, 3, 1), (KEY["DOWN"], 2289, 1)]
        lines, err = run(keyboard, keyboard_vars, hold, False, 0, work)
        if lines is None or check(lines, hold, 0):
            print("FAIL: hold of cursor down: " + (err or check(lines, hold, 0)[0]))
            return 1
        events = [(int(l.split()[1], 16), int(l.split()[2], 16)) for l in lines[1:]]
        first, gaps, n = hold_timing(events, KEY["DOWN"])
        print("Cursor down held for 3 s, a scan every tick: %d keys, the first repeat %.0f ms "
              "after the press, then every %.0f to %.0f ms" % (n, first, min(gaps), max(gaps)))

        caught = 0
        for name, old, new in MUTANTS:
            if keyboard.count(old) != 1:
                print("FAIL: the mutant %r does not apply" % name)
                return 1
            mk = keyboard.replace(old, new)
            for segs, start in cases:
                lines, err = run(mk, keyboard_vars, segs, False, start, work)
                if lines is None or check(lines, segs, start):
                    break
            else:
                print("FAIL: mutant not caught: " + name)
                return 1
            caught += 1
        print("OK: %d of %d mutants caught" % (caught, len(MUTANTS)))

        print("Instructions per scan:")
        print(perf(keyboard, keyboard_vars, work))
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
