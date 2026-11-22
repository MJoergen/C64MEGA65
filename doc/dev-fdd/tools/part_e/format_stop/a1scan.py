#!/usr/bin/env python3
"""Margins of every A1 sync train of a track side (issue #257, part E).

For every run of >= 16 short gaps followed by the A1 train, take the 15 gaps
of the three A1 bytes (expected M L M L M  S L M L M  S L M L M) and compute,
with the local half cell h = median(short gaps of the run) / 2, the worst
distance of any of these gaps to the classifier midpoints (2.5 h, 3.5 h) in
units of h, i.e. how far the gap is from being misclassified (negative =
misclassified at est = h).

Usage: a1scan.py <scp> <cyl> <head> [--rev N] [--all] [--worst K] [--at ms]
  --at ms : print the gaps of the train nearest that position
"""
import sys, os, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs

EXP = [3, 4, 3, 4, 3, 2, 4, 3, 4, 3, 2, 4, 3, 4, 3]

def trains(flux_ns):
    gaps = flux_ns
    t = 0.0
    pos = []
    for g in gaps:
        pos.append(t)
        t += g
    out = []
    i = 0
    n = len(gaps)
    run = 0
    while i < n:
        g = gaps[i]
        if 3200 <= g <= 4800:
            run += 1
            i += 1
            continue
        if run >= 16 and i + 15 <= n:
            shorts = gaps[i - 16:i]
            h = statistics.median(shorts) / 2.0
            seg = gaps[i:i + 15]
            margins = []
            for k, (gv, ex) in enumerate(zip(seg, EXP)):
                x = gv / h
                # distance to nearest wrong-side midpoint
                if ex == 2:
                    m = 2.5 - x
                elif ex == 3:
                    m = min(x - 2.5, 3.5 - x)
                else:
                    m = x - 3.5
                margins.append(m)
            out.append((pos[i] / 1e6, h, seg, margins))
        run = 0
        i += 1
    return out

def main():
    path, cyl, head = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    a = sys.argv[4:]
    rev = int(a[a.index('--rev') + 1]) if '--rev' in a else 0
    data, hdr, offs = read_scp(path)
    revs = track_revs(data, hdr, offs, cyl * 2 + head)
    it, flux = revs[rev]
    fns = [f * hdr['tick_ns'] for f in flux]
    tr = trains(fns)
    if '--at' in a:
        at = float(a[a.index('--at') + 1])
        best = min(tr, key=lambda x: abs(x[0] - at))
        t0, h, seg, m = best
        print('train at %.3f ms, h=%.3f us' % (t0, h / 1000))
        print('  gaps us :', ' '.join('%.2f' % (g / 1000) for g in seg))
        print('  in h    :', ' '.join('%.2f' % (g / h) for g in seg))
        print('  margin h:', ' '.join('%+.2f' % x for x in m))
        return
    rows = sorted(tr, key=lambda x: min(x[3]))
    k = int(a[a.index('--worst') + 1]) if '--worst' in a else 5
    print('%d trains; worst %d:' % (len(tr), k))
    for t0, h, seg, m in rows[:k]:
        j = min(range(15), key=lambda q: m[q])
        print('  %8.3f ms  h=%.3f  worst margin %+.3f h at gap %d (%.2f us, exp %d h)' % (
            t0, h / 1000, m[j], j, seg[j] / 1000, EXP[j]))

main()
