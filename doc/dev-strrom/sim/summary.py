#!/usr/bin/env python3
"""
Compares every complete pair of runs (old against new firmware) below RUNS and
prints the result lines; the full comparison of a pair is written to
RUNS/<scenario>/compare_OLD_NEW_<sim>.txt.

    summary.py [--sim nvc|ghdl]
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim          # noqa: E402
import compare      # noqa: E402


def complete(run):
    ev = os.path.join(run, "events.log")
    return os.path.exists(os.path.join(run, "run_info.txt")) and os.path.exists(ev) and \
        "end of script" in open(ev).read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", default="nvc")
    args = ap.parse_args()
    for scen in sorted(os.listdir(sim.RUNS)):
        a = os.path.join(sim.RUNS, scen, "OLD_" + args.sim)
        b = os.path.join(sim.RUNS, scen, "NEW_" + args.sim)
        if not (os.path.isdir(a) or os.path.isdir(b)):
            continue
        if not (complete(a) and complete(b)):
            print("== %s: not complete (OLD %s, NEW %s)" % (scen, complete(a), complete(b)))
            continue
        rep = compare.compare_runs(a, b)
        with open(os.path.join(sim.RUNS, scen, "compare_OLD_NEW_%s.txt" % args.sim), "w") as f:
            f.write("\n".join(rep.lines) + "\n")
        print("== %s: %s" % (scen, rep.lines[-1]))
        for line in rep.lines:
            if line.startswith(("DIFFERENCE", "   ", "UART: accepted", "checkpoint", "simulated time", "CPU spy",
                                "UART: ", "4k window: read accesses of the string", "VRAM")):
                if line.startswith("VRAM") and "identical" in line:
                    continue
                print("   " + line[:260])
        nv = sum(1 for l in rep.lines if l.startswith("VRAM") and "identical" in l)
        print("   %d video RAM dumps identical" % nv)


if __name__ == "__main__":
    main()
