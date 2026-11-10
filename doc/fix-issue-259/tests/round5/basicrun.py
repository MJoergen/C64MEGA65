#!/usr/bin/env python3
"""Headless run of a C64 BASIC (or BASIC + machine code) program against a model of the REU
(issue #259, round 5).

usage: basicrun.py <prg> [--rec ok|dead|flaky:<percent>|swapff:<n>|stall] [--keys TEXT]
                         [--patch OLD=NEW ...] [--max-cycles N] [--quiet]

A py65 6502 runs the BASIC and KERNAL ROMs of the local VICE installation (they are read at run
time, nothing is copied). The program is put at $0801 and started with RUN; everything it prints
goes to stdout. Around the CPU: RAM, the $01 banking, a raster counter derived from the cycle count,
timer A of CIA 2, the jiffy clock TI, and a functional MOS 8726: registers with their shadow registers, autoload, the
four transfers and the status bits as in VICE's reu.c. A transfer takes one cycle per access.

--rec ok          the REC as described (default)
--rec dead        every register write is ignored (what an unresponsive REU looks like)
--rec flaky:P     P percent of the register writes are ignored (fixed random seed)
--rec swapff:N    every N-th byte of a swap is stored as $FF in the REU
--rec stall       PAL badlines stall the REC as on WIP-V6-A24X1: a verify is clean, a swap stores
                  $FF in the REU for the byte it reads in the first BA-low cycle after a write
--patch OLD=NEW   replace the byte string OLD by NEW in the program before it runs (for example
                  to shorten a loop); both must have the same length
--keys TEXT       key presses for GET/INPUT, handed over one by one when the program waits

This checks the control flow, the arithmetic and the texts of the test programs. It is not a
cycle-exact C64: no VIC-II, no interrupts."""
import argparse, os, random, sys
from py65.devices.mpu6502 import MPU

VICE_ROMS = os.environ.get("VICE_ROMS", "/Applications/Vice/VICE.app/Contents/Resources/share/vice/C64")
CYCLES_PER_LINE, LINES = 63, 312
JIFFY = 985248 // 60


class REC:
    """MOS 8726, functional (after VICE reu.c); 512 KB like the unit of issue #259"""
    SIZE = 512 * 1024

    def __init__(self, mem, mode):
        self.mem, self.mode = mem, mode
        self.ram = bytearray(b"\xff" * self.SIZE)
        self.rng = random.Random(259)
        self.swap_n = 0
        self.reset()

    def reset(self):
        self.status = 0x10                      # 256 Kbit chips
        self.command = 0x10
        self.c64 = self.c64_sh = 0
        self.reu = self.reu_sh = 0
        self.bank = self.bank_sh = 0
        self.length = self.length_sh = 0xFFFF
        self.imask = 0
        self.actrl = 0

    def read(self, r):
        if r == 0:
            v = self.status
            self.status &= 0x1F
            return v
        if r == 1: return self.command
        if r == 2: return self.c64 & 0xFF
        if r == 3: return self.c64 >> 8
        if r == 4: return self.reu & 0xFF
        if r == 5: return self.reu >> 8
        if r == 6: return self.bank | 0xF8
        if r == 7: return self.length & 0xFF
        if r == 8: return self.length >> 8
        if r == 9: return self.imask | 0x1F
        if r == 10: return self.actrl | 0x3F
        return 0xFF

    def write(self, r, v):
        if self.mode == "dead":
            return
        if self.mode.startswith("flaky:") and self.rng.random() * 100 < float(self.mode[6:]):
            return
        if r == 1:
            self.command = v
            if v & 0x80 and v & 0x10:
                self.execute()
        elif r == 2: self.c64 = self.c64_sh = (self.c64_sh & 0xFF00) | v
        elif r == 3: self.c64 = self.c64_sh = (self.c64_sh & 0x00FF) | (v << 8)
        elif r == 4: self.reu = self.reu_sh = (self.reu_sh & 0xFF00) | v
        elif r == 5: self.reu = self.reu_sh = (self.reu_sh & 0x00FF) | (v << 8)
        elif r == 6: self.bank = self.bank_sh = v & 0x07
        elif r == 7: self.length = self.length_sh = (self.length_sh & 0xFF00) | v
        elif r == 8: self.length = self.length_sh = (self.length_sh & 0x00FF) | (v << 8)
        elif r == 9: self.imask = v & 0xE0
        elif r == 10: self.actrl = v & 0xC0

    def ff00(self):
        if self.command & 0x80 and not self.command & 0x10:
            self.execute()

    def ba_low(self):
        """PAL badline stall of the cycle that is about to run (display on, YSCROLL = 3)"""
        if self.mode != "stall" or not self.mem.io[0x11] & 0x10:
            return False
        c = self.mem.now()
        line, x = (c // CYCLES_PER_LINE) % LINES, c % CYCLES_PER_LINE
        return 51 <= line <= 250 and (line & 7) == 3 and 12 <= x <= 54

    def tick(self):
        self.mem.stolen += 1

    def wait_ba(self):
        while self.ba_low():
            self.tick()

    def execute(self):
        m = self.mem
        host, reu = self.c64, self.reu | (self.bank << 16)
        n = self.length or 0x10000
        hs, rs = (0 if self.actrl & 0x80 else 1), (0 if self.actrl & 0x40 else 1)
        kind = self.command & 3
        mask = 0
        self.wait_ba()
        if kind in (0, 1):                      # stash, fetch
            while n:
                if kind == 0:
                    self.ram[reu % self.SIZE] = m[host]
                else:
                    m[host] = self.ram[reu % self.SIZE]
                self.tick()
                host, reu, n = (host + hs) & 0xFFFF, reu + rs, n - 1
                if kind == 0 or n == 0:
                    self.wait_ba()              # (a fetch's extra write in the first BA-low cycle is not modelled)
                else:
                    self.wait_ba()
            mask, n = 0x40, 1
        elif kind == 2:                         # swap
            after_write = False
            while n:
                first_low = self.ba_low()       # case 1: the read sits in the first BA-low cycle after a write
                if first_low and not after_write:
                    self.wait_ba(); first_low = False
                c = m[host]
                self.tick()
                if first_low:
                    c = 0xFF                    # A24X1: the held read latches the released data bus
                    self.wait_ba()
                elif self.ba_low():
                    self.wait_ba()              # case 2: BA fell after the read, the write waits
                self.swap_n += 1
                if self.mode.startswith("swapff:") and self.swap_n % int(self.mode[7:]) == 0:
                    c = 0xFF
                r = self.ram[reu % self.SIZE]
                self.ram[reu % self.SIZE] = c
                m[host] = r
                self.tick()
                after_write = True
                host, reu, n = (host + hs) & 0xFFFF, reu + rs, n - 1
            mask, n = 0x40, 1
        else:                                   # verify
            while n:
                a, b = self.ram[reu % self.SIZE], m[host]
                self.tick(); self.wait_ba()
                host, reu, n = (host + hs) & 0xFFFF, reu + rs, n - 1
                if a != b:
                    mask |= 0x20
                    if n >= 1:
                        self.tick()
                    break
            if n == 0:
                n, mask = 1, mask | 0x40
            elif n == 1 and self.ram[reu % self.SIZE] == m[host]:
                mask |= 0x40
        self.status |= mask
        if self.command & 0x20:
            self.c64, self.reu, self.bank, self.length = self.c64_sh, self.reu_sh, self.bank_sh, self.length_sh
        else:
            if hs: self.c64 = host
            if rs: self.reu, self.bank = reu & 0xFFFF, (reu >> 16) & 0x07
            self.length = n & 0xFFFF
        self.command = (self.command & 0x7F) | 0x10


class Mem:
    def __init__(self, rec_mode):
        self.ram = bytearray(65536)
        self.basic = open(os.path.join(VICE_ROMS, "basic-901226-01.bin"), "rb").read()
        self.kernal = open(os.path.join(VICE_ROMS, "kernal-901227-03.bin"), "rb").read()
        self.io = bytearray(0x1000)
        self.mpu = None
        self.stolen = 0
        self.rec = REC(self, rec_mode)
        self.ta_start, self.ta_run, self.ta_val = 0, False, 0xFFFF

    def now(self):
        return self.mpu.processorCycles + self.stolen

    def __len__(self):
        return 65536

    def __getitem__(self, a):
        if isinstance(a, slice):
            return [self[i] for i in range(*a.indices(65536))]
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
        if isinstance(a, slice):
            for i, x in zip(range(*a.indices(65536)), v):
                self[i] = x
            return
        v &= 0xFF
        if 0xD000 <= a < 0xE000 and self.ram[1] & 3 and self.ram[1] & 4:
            self.io_write(a, v)
            return
        self.ram[a] = v
        if a == 0xFF00:
            self.rec.ff00()

    def io_read(self, a):
        if 0xDF00 <= a <= 0xDFFF:
            return self.rec.read(a & 0x1F)
        line = (self.now() // CYCLES_PER_LINE) % LINES
        if a == 0xD012: return line & 0xFF
        if a == 0xD011: return (self.io[0x11] & 0x7F) | ((line >> 8) << 7)
        if a == 0xD019: return 0x01                 # the raster compare of the KERNAL's PAL test
        if a in (0xDC00, 0xDC01): return 0xFF       # no key, no joystick
        if a in (0xDD04, 0xDD05):
            t = (0xFFFF - (self.now() - self.ta_start)) & 0xFFFF if self.ta_run else self.ta_val
            return t & 0xFF if a == 0xDD04 else t >> 8
        return self.io[a - 0xD000]

    def io_write(self, a, v):
        if 0xDF00 <= a <= 0xDFFF:
            self.rec.write(a & 0x1F, v)
            return
        if a == 0xDD0E:
            if v & 1:
                self.ta_start, self.ta_run = self.now(), True
            elif self.ta_run:
                self.ta_val, self.ta_run = (0xFFFF - (self.now() - self.ta_start)) & 0xFFFF, False
        self.io[a - 0xD000] = v


def petscii(c):
    if c == 13: return "\n"
    if c == 147: return "\n[clear screen]\n"
    if c == 29: return " "                           # cursor right: what BASIC prints after a number
    if 32 <= c <= 95: return chr(c)
    if 193 <= c <= 218: return chr(c - 128)
    return ""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("prg"); ap.add_argument("--rec", default="ok"); ap.add_argument("--keys", default="")
    ap.add_argument("--patch", action="append", default=[]); ap.add_argument("--max-cycles", type=int, default=2_000_000_000)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    prg = open(a.prg, "rb").read()
    for p in a.patch:
        old, new = (x.encode("latin-1").decode("unicode_escape").encode("latin-1") for x in p.split("=", 1))
        assert len(old) == len(new) and prg.count(old) >= 1, f"--patch {p}: not found or different lengths"
        prg = prg.replace(old, new)
    mem = Mem(a.rec)
    mpu = MPU(memory=mem)
    mem.mpu = mpu
    mem.ram[1] = 0x37
    mpu.pc = mem.kernal[0x1FFC] | (mem.kernal[0x1FFD] << 8)
    out, keys, state, steps = [], list(a.keys), "boot", 0
    while mpu.processorCycles < a.max_cycles:
        pc = mpu.pc
        steps += 1
        if not steps & 0xFF:                        # the jiffy clock TI (there are no interrupts here)
            j = (mem.now() // JIFFY) & 0xFFFFFF
            mem.ram[0xA0], mem.ram[0xA1], mem.ram[0xA2] = j >> 16, (j >> 8) & 0xFF, j & 0xFF
        if pc == 0xE716:                            # screen output of CHROUT
            if state == "run":
                ch = petscii(mpu.a)
                out.append(ch)
                if not a.quiet:
                    sys.stdout.write(ch); sys.stdout.flush()
        elif pc == 0xE5CD and mem.ram[0xC6] == 0:   # the editor waits for a key
            if state == "boot":
                load = prg[0] | (prg[1] << 8)
                assert load == 0x0801
                mem.ram[load:load + len(prg) - 2] = prg[2:]
                end = load + len(prg) - 2
                mem.ram[0x2D], mem.ram[0x2E] = end & 0xFF, end >> 8
                for i, c in enumerate(b"RUN\r"):
                    mem.ram[0x0277 + i] = c
                mem.ram[0xC6] = 4
                state = "run"
            elif state == "run":
                break                               # back at READY.
        elif pc == 0xF13E and mem.ram[0xC6] == 0 and keys and state == "run":   # GETIN, keyboard queue empty
            mem.ram[0x0277], mem.ram[0xC6] = ord(keys.pop(0)), 1
        mpu.step()
    else:
        print("\nbasicrun.py: cycle limit reached", file=sys.stderr)
        sys.exit(2)
    if a.quiet:
        sys.stdout.write("".join(out))
    print(f"\n[{mpu.processorCycles + mem.stolen} cycles, {(mpu.processorCycles + mem.stolen) / 985248:.1f} s of C64 time]")


if __name__ == "__main__":
    main()
