#!/usr/bin/env python3
"""Mean / min of each of the 15 A1-train gaps (in local half cells) over all
real trains of a capture, split by head and cylinder band; plus the count of
trains whose worst margin is below given levels. Real train: >=16 shorts,
then 15 gaps each within 0.75 h of the expected M L M L M S L M L M S L M L M.
Usage: a1profile.py <scp> [--rev r] [--angle]"""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
EXP = [3, 4, 3, 4, 3, 2, 4, 3, 4, 3, 2, 4, 3, 4, 3]
a = sys.argv[1:]
path = a[0]
rev = int(a[a.index('--rev') + 1]) if '--rev' in a else 0
data, hdr, offs = read_scp(path)
groups = {}
lows = {}
angle = {}
for cyl in range(0, 80):
    for head in (0, 1):
        r = track_revs(data, hdr, offs, cyl * 2 + head)
        if not r: continue
        it, flux = r[rev]
        g = [f * hdr['tick_ns'] for f in flux]
        t = 0.0; pos = []
        for x in g: pos.append(t); t += x
        run = 0
        for i, x in enumerate(g):
            if 3200 <= x <= 4800:
                run += 1; continue
            if run >= 16 and i + 15 <= len(g):
                h = statistics.median(g[i - 16:i]) / 2
                seg = [v / h for v in g[i:i + 15]]
                if all(abs(y - e) <= 0.75 for y, e in zip(seg, EXP)):
                    band = (head, cyl // 20)
                    groups.setdefault(band, []).append(seg)
                    m = min((2.5 - y) if e == 2 else (min(y - 2.5, 3.5 - y) if e == 3 else y - 3.5) for y, e in zip(seg, EXP))
                    lows.setdefault(head, []).append((m, cyl, pos[i] / 1e6))
                    sec = int((pos[i] / 1e6 + 9.0) // 19.488)
                    angle.setdefault((head, sec), []).append(m)
            run = 0
for k in sorted(groups):
    s = groups[k]
    mean = [sum(x[j] for x in s) / len(s) for j in range(15)]
    mn = [min(x[j] for x in s) for j in range(15)]
    print('head %d cyl %2d-%2d n=%4d mean: %s' % (k[0], k[1] * 20, k[1] * 20 + 19, len(s), ' '.join('%.2f' % v for v in mean)))
    print('                      min : %s' % ' '.join('%.2f' % v for v in mn))
for hd in sorted(lows):
    L = sorted(lows[hd])
    print('head %d: %d trains; worst margin <0: %d, <0.1: %d, <0.2: %d, <0.3: %d; worst 5: %s' % (
        hd, len(L), sum(1 for x in L if x[0] < 0), sum(1 for x in L if x[0] < 0.1), sum(1 for x in L if x[0] < 0.2),
        sum(1 for x in L if x[0] < 0.3), ['%+.3f c%d %.1fms' % x for x in L[:5]]))
if '--angle' in a:
    for hd in (0, 1):
        print('head %d mean worst margin by angular slot (half-sector slots of 9.74 ms, ID and DAM trains):' % hd)
        print('   ' + ' '.join('%d:%.2f/%d' % (s, sum(angle[(hd, s)]) / len(angle[(hd, s)]), len(angle[(hd, s)])) for s in range(0, 11) if (hd, s) in angle))
