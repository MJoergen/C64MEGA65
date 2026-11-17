#!/usr/bin/env python3
"""
Menu bits and config file writes of a run, attributed to the steps of its scenario.

    evalsteps.py RUN_DIR [--card FILE]

RUN_DIR is a run folder of sim.py (runs/SCENARIO/VARIANT_SIM, or its subfolder
M2M/QNICE/vhdl while the run is still going). Prints:

  * every change of the 512 menu bits (regs.log) with the bits switched on and
    off, their names from CORE/vhdl/config.vhd, and the last "mark" of the
    scenario before it (events.log), so that each change belongs to a step;
  * every block that was written to the SD card (sdwrites.log, times from
    sd.log), compared with the config file on the card and with the previous
    write of the same block: the positions that differ, and whether the bytes
    behind the config file are zero.

--card is the config file that the card image holds (default
sd/card_full.cfg.bin next to this script; make_sd2.py writes it). The names of
the menu lines come from the repository of the work folder, as in runtext.py.
"""
import bisect
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import runtext          # noqa: E402


def main():
    args = sys.argv[1:]
    card = os.path.join(HERE, "sd", "card_full.cfg.bin")
    if "--card" in args:
        i = args.index("--card")
        card = args[i + 1]
        del args[i:i + 2]
    run = args[0]
    names = runtext.menu_items()
    name = lambda i: "%d(%s)" % (i, names[i].strip()) if i < len(names) else str(i)

    marks = []
    for l in open(os.path.join(run, "events.log")):
        m = re.match(r"([\d.]+) mark (.*)", l)
        if m:
            marks.append((float(m.group(1)), m.group(2)))
    times = [t for t, _ in marks]

    def step(t):
        i = bisect.bisect_right(times, t) - 1
        return marks[i][1] if i >= 0 else "(before the first mark)"

    print("== menu bit changes")
    prev = None
    for l in open(os.path.join(run, "regs.log")):
        m = re.match(r"\s*([\d.]+) control_m=([0-9A-F]+)", l)
        if not m:
            continue
        t, v = float(m.group(1)), int(m.group(2), 16)
        if prev is not None and v != prev:
            on = [i for i in range(512) if (v >> i) & 1 and not (prev >> i) & 1]
            off = [i for i in range(512) if (prev >> i) & 1 and not (v >> i) & 1]
            print("%12.3f  on: %s   off: %s   [%s]" % (t, ", ".join(map(name, on)) or "-",
                                                     ", ".join(map(name, off)) or "-", step(t)))
        prev = v
    if prev is not None:
        print("%12s  set at the end: %s" % ("", [i for i in range(512) if (prev >> i) & 1]))

    print("== SD card writes")
    ref = open(card, "rb").read()
    n = len(ref)
    wtimes = [l.split()[0] for l in open(os.path.join(run, "sd.log")) if re.match(r"\d+ write ", l)]
    path = os.path.join(run, "sdwrites.log")
    last = {}
    for k, l in enumerate(open(path) if os.path.exists(path) else []):
        lba, hx = l.split()
        data = bytes.fromhex(hx)
        t = wtimes[k] if k < len(wtimes) else "?"
        before = last.get(lba, ref)
        fmt = lambda old: ", ".join("%s %d>%d" % (name(i), old[i], data[i]) for i in range(n) if data[i] != old[i]) or "-"
        print("%s us  write block %s   [%s]" % (t, lba, step(float(t)) if t != "?" else "?"))
        print("    against the config file on the card: %s" % fmt(ref))
        print("    against the previous write of this block: %s" % fmt(before))
        print("    bytes %d..511 all zero: %s" % (n, not any(data[n:])))
        last[lba] = data


if __name__ == "__main__":
    main()
