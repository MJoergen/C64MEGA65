#!/usr/bin/env python3
"""Slip detector independent of the controller estimate: for every STEP run in every ring, the
first read REQUEST after the run carries the WD track register (= the DOS's target) and its RESULT
the cylinder found. m = C_found - WD_trk. Also says whether the DOS's belief was confirmed by an
OK read with C == trk right before the run (then m measures what happened in this run).
Usage: python3 -I mismatch.py decoded...txt"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steps import parse, runs, desc_run

def main():
    rows = []
    for d in parse(sys.argv[1:]):
        ring = d["ring"]
        for i, j in runs(ring):
            if j + 2 >= len(ring) or ring[j+1][0] != "REQ" or ring[j+2][0] != "RES":
                continue
            req, res = ring[j+1], ring[j+2]
            if res[6] != "OK":
                m = None
            else:
                m = res[1] - req[3]
            # belief before: last OK RES before the run with C == its REQ trk
            belief = "?"
            for x in range(i-1, 0, -1):
                if ring[x][0] == "RES":
                    if ring[x][6] == "OK" and ring[x-1][0] == "REQ":
                        belief = "ok" if ring[x][1] == ring[x-1][3] else f"off({ring[x][1]-ring[x-1][3]:+d})"
                    else:
                        belief = "notOK"
                    break
            n = j - i + 1
            dirs = "".join("i" if ring[k][1] == "in" else "o" for k in range(i, j+1))
            print(f"c{d['c']:>2} {d['name']:<14} n={n:2d} {dirs[:8]+('..' if n>8 else ''):<10} start_in_ring={'yes' if i>0 else 'NO'} "
                  f"belief_before={belief:<8} next={req[1]:<12} trk={req[3]:2d} C={res[1]:2d} {res[6]:<4} m={m}")
main()
