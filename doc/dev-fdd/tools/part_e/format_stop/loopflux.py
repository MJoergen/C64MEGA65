#!/usr/bin/env python3
"""Loop an edge file of mkflux.py K times, exactly as mkflux.py --loops K
would have written it from the capture (issue #257, part E).

mkflux.py writes every edge as 100 + round(1.25 * n) with n the number of
25 ns ticks since the start of the stream (round half to even). That map is
strictly increasing in steps of at least one cycle, so n is recovered from
the cycle without ambiguity, and loop k of the stream has the edges of loop 0
shifted by k times the tick count of the last edge. f77h0.txt looped four
times gives the file the tb_flux_ctl runs of this folder were made with.

Usage: loopflux.py <edges.txt> <loops> <out.txt>"""
import sys

def ticks(c):
    m = c - 100
    n0 = int(round(m / 1.25))
    sol = [n for n in (n0 - 1, n0, n0 + 1) if int(round(1.25 * n)) == m]
    if len(sol) != 1:
        raise SystemExit('cycle %d was not written by mkflux.py' % c)
    return sol[0]

def main():
    src, loops, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    edges = []
    for ln in open(src):
        ln = ln.strip()
        if not ln:
            continue
        if ln[0] == 'R':
            raise SystemExit('reset lines are not supported')
        edges.append(int(ln))
    n = [ticks(c) for c in edges]
    total = n[-1]
    with open(out, 'w') as fo:
        for k in range(loops):
            for x in n:
                fo.write('%d\n' % (100 + int(round(1.25 * (x + k * total)))))
    print('edges', len(edges) * loops)

main()
