#!/usr/bin/env python3
"""Print raw flux intervals (us) and the PLL raw-cell string around a time window.
Usage: window.py <scp> <cyl> <head> <rev> <t0_ms> <t1_ms>"""
import sys
sys.path.insert(0, __import__('os').path.dirname(__file__))
from scp import read_scp, track_revs
def main():
    path, cyl, head, rev, t0, t1 = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
    data, hdr, offs = read_scp(path)
    revs = track_revs(data, hdr, offs, cyl * 2 + head)
    it, flux = revs[rev]
    tick = hdr['tick_ns']
    t = 0.0
    out = []
    for f in flux:
        t += f * tick
        if t0 * 1e6 <= t <= t1 * 1e6:
            out.append((t / 1e6, f * tick / 1000.0))
    line = []
    for tm, us in out:
        line.append('%.2f' % us)
    print('first flux at %.4f ms, %d flux in window' % (out[0][0], len(out)))
    # classify by 2us cells
    cls = ''.join({2: 'S', 3: 'M', 4: 'L'}.get(int(round(us / 2.0)), 'X') for tm, us in out)
    for k in range(0, len(out), 16):
        print('%.4f  %s   %s' % (out[k][0], ' '.join(line[k:k+16]), cls[k:k+16]))
main()
