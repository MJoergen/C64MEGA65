#!/usr/bin/env python3
"""
covmatrix.py: which string ROM strings were read completely in which run.

    covmatrix.py KEY=RUN_DIR ...

Prints one line per run (number of strings read completely, read accesses of
device 0007), the strings by window with the keys of the runs that read them,
the totals over all runs and the strings that no run has read.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import strrom_tools as st       # noqa: E402


def main():
    runs = [a.split("=", 1) for a in sys.argv[1:]]
    tab, lo, hi = st.table()
    rom = st.strrom_bytes(os.path.join(st.NEW_DIR, "m2m-strings.rom"))
    want = {}
    for name, addr, pos in tab:
        s = st.zstr(lambda a: rom[a] if a < len(rom) else None, pos)
        want[name] = set(range(pos, pos + len(s) + 1))
    read = {}
    nacc = {}
    for key, run in runs:
        got = set()
        n = 0
        with open(os.path.join(run, "win.log")) as f:
            for line in f:
                if line.startswith("R 0007 "):
                    got.add(int(line.split()[2], 16))
                    n += 1
        read[key] = got
        nacc[key] = n
    full = {key: [name for name, _, _ in tab if want[name] <= read[key]] for key, _ in runs}
    part = {key: [name for name, _, _ in tab if (want[name] & read[key]) and not want[name] <= read[key]]
            for key, _ in runs}
    for key, run in runs:
        print("%-3s %-45s %3d strings read completely, %d partly, %5d read accesses of device 0007" %
              (key, os.path.relpath(run, os.path.join(HERE, "..")), len(full[key]), len(part[key]), nacc[key]))
    union = [name for name, _, _ in tab if any(name in full[k] for k, _ in runs)]
    print("total: %d of %d strings read completely in at least one run; %d in no run" %
          (len(union), len(tab), len(tab) - len(union)))
    for w in range(4):
        names = [(name, pos) for name, _, pos in tab if pos // 4096 == w]
        if not names:
            continue
        done = [n for n, _ in names if n in union]
        print()
        print("window %d: %d strings, %d read: " % (w, len(names), len(done)) +
              " ".join("%s(%s)" % (n, ",".join(k for k, _ in runs if n in full[k])) for n in done))
        print("window %d not read: " % w + (" ".join(n for n, _ in names if n not in union) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
