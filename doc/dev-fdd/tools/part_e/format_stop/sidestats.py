#!/usr/bin/env python3
"""Per-side flux quality of a capture: count of gaps off a whole half cell by
more than thr (0.3 h / 0.25 h), RMS residual, over revolution 0.
Usage: sidestats.py <scp> [c0 c1]"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
path = sys.argv[1]
c0, c1 = (int(sys.argv[2]), int(sys.argv[3])) if len(sys.argv) > 3 else (0, 79)
data, hdr, offs = read_scp(path)
rows = []
for cyl in range(c0, c1 + 1):
    for head in (1, 0):
        r = track_revs(data, hdr, offs, cyl * 2 + head)
        if not r: continue
        it, flux = r[0]
        tot = sum(flux) * hdr['tick_ns']
        h = tot / (len(flux) * 1.0)  # placeholder
        # half cell from revolution length: 6250 bytes*16 cells nominal ~ 200 ms -> estimate h by median of shorts
        shorts = sorted(f * hdr['tick_ns'] for f in flux if 3500 < f * hdr['tick_ns'] < 4500)
        h = shorts[len(shorts) // 2] / 2 if shorts else 2000.0
        n3 = n25 = 0; ss = 0.0; n = 0
        for f in flux:
            x = f * hdr['tick_ns'] / h
            k = round(x)
            if 2 <= k <= 4:
                d = x - k; ss += d * d; n += 1
                if abs(d) > 0.3: n3 += 1
                if abs(d) > 0.25: n25 += 1
        rows.append((cyl, head, n3, n25, math.sqrt(ss / max(n, 1)), h))
for cyl, head, n3, n25, rms, h in rows:
    print('cyl %2d head %d (H=%d): >0.30h %4d  >0.25h %5d  rms %.4f h  h=%.3f us' % (cyl, head, 1 - head, n3, n25, rms, h / 1000))
