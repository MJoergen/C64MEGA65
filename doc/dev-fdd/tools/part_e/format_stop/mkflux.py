#!/usr/bin/env python3
"""Write an edge-time file for sim/tb_flux_dec.vhd from one SCP track side.

Usage: mkflux.py <scp> <cyl> <head> <out.txt> [--scale S] [--revs N] [--loops K]
       [--reset-ms t1,t2,...] [--start-ms T]

Edge times are 50 MHz cycles from the start of revolution 0 (index), plus an
offset of 100 cycles. --scale multiplies every interval (S > 1 = slower disk).
--loops repeats the captured revolutions K times (the flux is contiguous at the
index, so a loop of the 3 captured revs is a plausible longer stream).
--reset-ms inserts a decoder reset ("R <cycle>") at those times.
Also prints the index cycle of every revolution."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs

def main():
    a = sys.argv[1:]
    path, cyl, head, out = a[0], int(a[1]), int(a[2]), a[3]
    scale, nrev, loops, resets, start = 1.0, 3, 1, [], 0.0
    i = 4
    while i < len(a):
        if a[i] == '--scale': scale = float(a[i + 1]); i += 2
        elif a[i] == '--revs': nrev = int(a[i + 1]); i += 2
        elif a[i] == '--loops': loops = int(a[i + 1]); i += 2
        elif a[i] == '--reset-ms': resets = [float(x) for x in a[i + 1].split(',')]; i += 2
        elif a[i] == '--start-ms': start = float(a[i + 1]); i += 2
        else: raise SystemExit('bad arg ' + a[i])
    data, hdr, offs = read_scp(path)
    revs = track_revs(data, hdr, offs, cyl * 2 + head)[:nrev]
    tick = hdr['tick_ns'] * scale
    t = 0.0
    off = 100
    edges = []
    idx = []
    for lp in range(loops):
        for it, flux in revs:
            idx.append(off + int(round(t / 20.0)))
            for f in flux:
                t += f * tick
                c = off + int(round(t / 20.0))
                if t >= start * 1e6:
                    edges.append(c)
    rs = [off + int(round(r * 1e6 / 20.0)) for r in resets]
    ev = [(c, 'E') for c in edges] + [(c, 'R') for c in rs]
    ev.sort()
    with open(out, 'w') as fo:
        for c, k in ev:
            fo.write(('R %d\n' % c) if k == 'R' else ('%d\n' % c))
    print('edges', len(edges), 'index cycles', idx, 'end', off + int(round(t / 20.0)))

main()
