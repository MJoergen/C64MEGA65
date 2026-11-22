#!/usr/bin/env python3
"""List flux gaps whose length is far from a whole number of half cells
(|x - round(x)| > thr, x = gap / h, h from a running median of shorts).
Usage: outliers.py <scp> <cyl> <head> <rev> [thr] [t0 t1]"""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
path, cyl, head, rev = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
thr = float(sys.argv[5]) if len(sys.argv) > 5 else 0.3
t0, t1 = (float(sys.argv[6]), float(sys.argv[7])) if len(sys.argv) > 7 else (0, 1e9)
data, hdr, offs = read_scp(path)
it, flux = track_revs(data, hdr, offs, cyl * 2 + head)[rev]
t = 0.0; n = 0; hist = []
h = 2000.0
outs = []
for f in flux:
    g = f * hdr['tick_ns']
    t += g
    x = g / h
    k = round(x)
    if 3500 < g < 4500:
        hist.append(g)
        if len(hist) > 64: hist.pop(0)
        if len(hist) >= 16: h = statistics.median(hist) / 2
    if abs(x - k) > thr and t0 <= t / 1e6 <= t1:
        outs.append((t / 1e6, g / 1000, x))
print('%d outliers (thr %.2f h)' % (len(outs), thr))
for o in outs[:60]:
    print('  %9.4f ms  %.2f us  %.2f h' % o)
