#!/usr/bin/env python3
"""For every STEP run in every ring: d before (last OK ID read before the run) and d after
(first OK ID read after the run), d = estimate - C, and whether the run starts with a reversal.
Usage: python3 -I deltas.py decoded...txt"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steps import parse, runs, desc_run
from offsets import est_track

def main():
    for d in parse(sys.argv[1:]):
        ring = d["ring"]
        est, hcyl, hv = est_track(d)
        for i, j in runs(ring):
            # d before
            db = None
            for x in range(i - 1, -1, -1):
                e = ring[x]
                if e[0] == "RES" and e[6] == "OK" and est[x] is not None:
                    db = est[x] - e[1]; break
            da = None
            for x in range(j + 1, len(ring)):
                e = ring[x]
                if e[0] == "RES" and e[6] == "OK":
                    da = est[x] - e[1]; break
                if e[0] == "STEP":
                    break
            prevdir = None
            for x in range(i - 1, -1, -1):
                if ring[x][0] == "STEP":
                    prevdir = ring[x][1]; break
            rev = "?" if prevdir is None else ("REV" if prevdir != ring[i][1] else "same")
            nrev = sum(1 for k in range(i + 1, j + 1) if ring[k][1] != ring[k - 1][1])
            print(f"c{d['c']:>2} {d['name']:<14} [{i:2d}..{j:2d}] {desc_run(ring, i, j):<60} first={rev:<4} innerrev={nrev} d_before={db} d_after={da}"
                  + ("" if db is None or da is None else f" delta={da-db:+d}"))
main()
