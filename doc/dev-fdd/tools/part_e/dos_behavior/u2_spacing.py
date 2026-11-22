#!/usr/bin/env python3
# How many Write Sector commands does the genuine 1581 ROM issue for a series of
# U2 block writes, as a function of the ATN-free gap between them?
#
# Runs a ROM (argv[1], *.rom) on the cycle-exact 6502 + rotating WD write model
# of doc/dev-fdd/rom_emu. Each "U2" is the job a U2 posts:
# a logical write job $90 for track T sector s with a 256-byte buffer at $0300.
# Between two U2s the C64 bus is modelled as DraCopy's block copy does it:
#   1. a TALK phase of drive 9 (the source block, 256 bytes) of length GAP ms,
#      during which drive 8 sees NO ATN and sits in its DOS idle loop;
#   2. an ATN (UNTALK / LISTEN 8): emulated by $9C := $9D, which is exactly what
#      the ATN service does first in both ROMs ($ABD0 LDA $9D / STA $9C);
#   3. a LISTEN phase (256 bytes to drive 8 + the U2 command) of length LIS ms,
#      during which drive 8 is busy receiving; emulated by reloading $9C every
#      10 ms (the real drive is not in its idle loop then, so it cannot flush).
# Usage: python3 -I u2_spacing.py <rom.rom> <track> <first_sector> <count> <gap_ms> <lis_ms>
import sys, os, copy, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', '..', 'rom_emu'))
from wd_write_model import post_job, jobs_idle, run_until_idle, boot  # noqa: E402
import machine as machmod  # noqa: E402

CYC_MS = 2000  # 2 MHz

def run_for(m, cycles, reload_every=None):
    end = m.cpu.cycles + cycles
    nxt = m.cpu.cycles + reload_every if reload_every else None
    while m.cpu.cycles < end:
        m.run(200)
        if nxt is not None and m.cpu.cycles >= nxt:
            m.ram[0x9C] = m.ram[0x9D]
            nxt += reload_every

def ws_count(m):
    return sum(1 for o in m.ops if o['kind'] == 'ws')

def main():
    rom, T, S0, n, gap_ms, lis_ms = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), \
        int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
    t0 = time.time()
    m = boot()
    print('ROM %s  $9D=%02X (idle reload, 10 ms ticks)  boot pc=$%04X' % (os.path.basename(rom), m.ram[0x9D], m.cpu.pc))
    m.ram[0x9C] = m.ram[0x9D]
    per = []
    flush_starts = 0
    for k in range(n):
        s = S0 + k
        for i in range(256):
            m.ram[0x300 + i] = (i * 13 + s) & 0xFF
        w0 = ws_count(m); r0 = sum(1 for c in m.cmd_log if (c[1] >> 4) in (8, 9))
        m.ram[0x9C] = m.ram[0x9D]          # the U2 command itself ended with an ATN (UNLISTEN)
        post_job(m, 0x90, T, s)
        ok = run_until_idle(m, 20_000_000, 'U2 T%d S%d' % (T, s))
        w1 = ws_count(m)
        dirty_after_job = m.ram[0x87]
        # 1. TALK phase of drive 9: no ATN for gap_ms
        run_for(m, int(gap_ms * CYC_MS))
        # 2. ATN
        m.ram[0x9C] = m.ram[0x9D]
        w2 = ws_count(m)
        # 3. LISTEN phase of drive 8: busy, frequent reload
        run_for(m, int(lis_ms * CYC_MS), reload_every=10 * CYC_MS)
        w3 = ws_count(m)
        r3 = sum(1 for c in m.cmd_log if (c[1] >> 4) in (8, 9))
        per.append((s, w1 - w0, w2 - w1, w3 - w2, r3 - r0))
        print('U2 T%d S%-2d ok=%s dirty=%02X  WS during job %d, during talk gap %d, during listen %d; Read Sectors %d'
              % (T, s, ok, dirty_after_job, w1 - w0, w2 - w1, w3 - w2, r3 - r0), flush=True)
    # final: let the drive go idle for 2 s with no ATN (end of the copy)
    w4 = ws_count(m)
    run_for(m, 2000 * CYC_MS)
    w5 = ws_count(m)
    tot = ws_count(m)
    print('final idle: %d WS' % (w5 - w4))
    print('RESULT rom=%s gap=%gms listen=%gms U2s=%d  Write Sectors total=%d  (%.2f per U2)  wall %.0fs'
          % (os.path.basename(rom), gap_ms, lis_ms, n, tot, tot / n, time.time() - t0))

if __name__ == '__main__':
    main()
