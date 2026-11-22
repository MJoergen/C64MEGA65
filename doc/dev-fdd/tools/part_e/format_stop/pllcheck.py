#!/usr/bin/env python3
"""Decode a track side with a phase-tracking PLL of the kind Greaseweazle uses
(period adjust 5 %, phase adjust 60 %, clock clamp +/-10 %), as a stand-in
for a PLL data separator, and list the IDs found per revolution. Also prints
the transition position errors against the PLL grid near a given time.
Usage: pllcheck.py <scp> <cyl> <head> [--near ms] [--phase f] [--period f]"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs, crc16
a = sys.argv[1:]
path, cyl, head = a[0], int(a[1]), int(a[2])
near = float(a[a.index('--near') + 1]) if '--near' in a else None
ph = float(a[a.index('--phase') + 1]) if '--phase' in a else 0.60
pe = float(a[a.index('--period') + 1]) if '--period' in a else 0.05
data, hdr, offs = read_scp(path)
for r, (it, flux) in enumerate(track_revs(data, hdr, offs, cyl * 2 + head)):
    clock = 2000.0; centre = 2000.0; cmin, cmax = 1800.0, 2200.0
    ticks = 0.0; bits = []; t = 0.0; errs = []
    for f in flux:
        x = f * hdr['tick_ns']; t += x
        ticks += x
        if ticks < clock / 2:
            continue
        zeros = 0
        while True:
            ticks -= clock
            if ticks >= clock / 2:
                zeros += 1; bits.append(0)
            else:
                break
        bits.append(1)
        if near is not None and abs(t / 1e6 - near) < 0.03:
            errs.append((t / 1e6, ticks))
        if zeros <= 3:
            clock += ticks * pe
        else:
            clock += (centre - clock) * pe
        clock = min(max(clock, cmin), cmax)
        ticks = ticks * (1 - ph)
    s = ''.join('1' if b else '0' for b in bits)
    SYNC = '0100010010001001' * 3
    i = 0; ids = []
    while True:
        j = s.find(SYNC, i)
        if j < 0: break
        p = j + 48
        def byte(q):
            w = s[q:q + 16]
            v = 0
            for k in range(8): v = (v << 1) | (w[2 * k + 1] == '1')
            return v
        m = byte(p)
        if m == 0xFE:
            by = [byte(p + 16 * k) for k in range(1, 7)]
            ok = crc16([0xA1] * 3 + [0xFE] + by) == 0
            ids.append('%d%s' % (by[2], '' if ok else '!'))
        i = p + 16
    print('rev %d (phase %.2f period %.2f): IDs %s' % (r, ph, pe, ' '.join(ids)))
    if errs and r == 0:
        print('   transition errors vs PLL grid (ns) near %.3f ms:' % near)
        print('   ' + ' '.join('%+.0f' % e for tm, e in errs))
