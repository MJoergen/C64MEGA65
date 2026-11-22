#!/usr/bin/env python3
"""Per-sector outlier count in the fixed-pattern window around each ID record
(1.0 ms before the ID train to 1.55 ms after it: gap3 tail, 12 x 00, A1 x 3,
ID, 22 x 4E, 12 x 00, A1 x 3 of the data mark), for one side, all revs.
Usage: recwin.py <scp> <cyl> <head> [thr]"""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
path, cyl, head = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
thr = float(sys.argv[4]) if len(sys.argv) > 4 else 0.25
data, hdr, offs = read_scp(path)
ID0, PITCH = 1.47, 19.488        # ms of the first ID train, record pitch
out = []
for r, (it, flux) in enumerate(track_revs(data, hdr, offs, cyl * 2 + head)):
    g = [f * hdr['tick_ns'] for f in flux]
    t = 0.0; pos = []
    for x in g: t += x; pos.append(t / 1e6)
    shorts = sorted(x for x in g if 3500 < x < 4500)
    h = shorts[len(shorts) // 2] / 2
    row = []
    for s in range(10):
        c = ID0 + s * PITCH
        lo, hi = c - 1.0, c + 1.55
        n = 0; worst = 0
        for x, p in zip(g, pos):
            if lo <= p <= hi:
                y = x / h; d = abs(y - round(y))
                if d > thr: n += 1
                worst = max(worst, d)
        row.append('%d:%d/%.2f' % (s + 1, n, worst))
    out.append('rev %d: ' % r + ' '.join(row))
print('\n'.join(out))
