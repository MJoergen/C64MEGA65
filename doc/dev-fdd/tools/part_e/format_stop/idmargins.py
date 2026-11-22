#!/usr/bin/env python3
"""ID-train (not DAM-train) worst margins per sector for one side, per capture.
Usage: idmargins.py <cyl> <head> <scp>..."""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
EXP = [3, 4, 3, 4, 3, 2, 4, 3, 4, 3, 2, 4, 3, 4, 3]
cyl, head = int(sys.argv[1]), int(sys.argv[2])
for path in sys.argv[3:]:
    data, hdr, offs = read_scp(path)
    rows = []
    for r, (it, flux) in enumerate(track_revs(data, hdr, offs, cyl * 2 + head)):
        g = [f * hdr['tick_ns'] for f in flux]
        t = 0.0; pos = []
        for x in g: pos.append(t / 1e6); t += x
        res = {}
        run = 0
        for i, x in enumerate(g):
            if 3200 <= x <= 4800: run += 1; continue
            if run >= 16 and i + 15 <= len(g):
                h = statistics.median(g[i - 16:i]) / 2
                seg = [v / h for v in g[i:i + 15]]
                if all(abs(y - e) <= 0.75 for y, e in zip(seg, EXP)):
                    s = round((pos[i] - 1.43) / 19.488) + 1
                    off = pos[i] - (1.43 + (s - 1) * 19.488)
                    if abs(off) < 0.5:   # ID train (DAM trains sit 1.41 ms later)
                        m = min((2.5 - y) if e == 2 else (min(y - 2.5, 3.5 - y) if e == 3 else y - 3.5) for y, e in zip(seg, EXP))
                        res[s] = m
            run = 0
        rows.append(' '.join('%d:%+.2f' % (s, res[s]) if s in res else '%d:--' % s for s in range(1, 11)))
    print(os.path.basename(path)[:28], '|', rows[0])
