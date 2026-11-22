#!/usr/bin/env python3
"""Worst A1-train margin per track side for a whole capture, and the region
quality (outliers in the 0.5 ms of 4E gap + 00 preamble before each train).
Real trains: >=16 shorts followed by 15 gaps summing to 49 +/- 1.5 h.
margin = distance (in h) of the worst train gap to the classifier midpoints
(2.5 h / 3.5 h), h = median of the 16 preamble shorts / 2.
Usage: a1margins.py <scp> [c0 c1] [--rev r]"""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
EXP = [3, 4, 3, 4, 3, 2, 4, 3, 4, 3, 2, 4, 3, 4, 3]
a = sys.argv[1:]
path = a[0]
c0, c1 = (int(a[1]), int(a[2])) if len(a) > 2 and a[1].isdigit() else (0, 79)
rev = int(a[a.index('--rev') + 1]) if '--rev' in a else 0
data, hdr, offs = read_scp(path)
allm = []
for cyl in range(c0, c1 + 1):
    for head in (1, 0):
        r = track_revs(data, hdr, offs, cyl * 2 + head)
        if not r: continue
        it, flux = r[rev]
        g = [f * hdr['tick_ns'] for f in flux]
        t = 0.0; pos = []
        for x in g: pos.append(t); t += x
        run = 0; trains = []
        for i, x in enumerate(g):
            if 3200 <= x <= 4800:
                run += 1; continue
            if run >= 16 and i + 15 <= len(g):
                h = statistics.median(g[i - 16:i]) / 2
                seg = g[i:i + 15]
                if abs(sum(seg) / h - 49) <= 1.5:
                    m = []
                    for gv, ex in zip(seg, EXP):
                        y = gv / h
                        m.append(2.5 - y if ex == 2 else (min(y - 2.5, 3.5 - y) if ex == 3 else y - 3.5))
                    trains.append((pos[i] / 1e6, min(m), m.index(min(m))))
            run = 0
        trains.sort(key=lambda x: x[1])
        w = trains[0] if trains else (0, 9, 0)
        allm.append((w[1], cyl, head, w[0], w[2], len(trains)))
        print('cyl %2d head %d (H=%d): %2d trains, worst margin %+.3f h at %.3f ms (gap %d)' % (cyl, head, 1 - head, len(trains), w[1], w[0], w[2]))
allm.sort()
print('WORST 8:', ['c%d h%d %+.3f @%.2fms g%d' % (x[1], x[2], x[0], x[3], x[4]) for x in allm[:8]])
