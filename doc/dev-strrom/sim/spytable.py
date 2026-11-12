#!/usr/bin/env python3
"""
Prints the CPU spy logs of two runs side by side: per checkpoint the lowest
and the highest stack pointer since the checkpoint before.

    spytable.py RUN_A RUN_B
"""
import os
import sys


def load(run):
    res = []
    for l in open(os.path.join(run, "spy.log")):
        p = l.split()
        res.append((p[1], dict(kv.split("=") for kv in p[2:])))
    return res


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    print("%-20s %-11s %-11s %-9s %-11s %-11s" % ("checkpoint", "A sp_min", "B sp_min", "A-B words", "A sp_max", "B sp_max"))
    for (tag, va), (_, vb) in zip(a, b):
        d = int(va["sp_min"], 16) - int(vb["sp_min"], 16)
        print("%-20s %-11s %-11s %-9d %-11s %-11s" % (tag, va["sp_min"], vb["sp_min"], d, va["sp_max"], vb["sp_max"]))


if __name__ == "__main__":
    main()
