#!/usr/bin/env python3
"""
Negative control of the comparison old firmware against new firmware.

Three short runs of the new firmware (scenario "negctl": the first 60 ms of the
cold boot) are compared with the first part of the existing run main/OLD_<sim>
(compare.py in prefix mode):

    NEWSHORT    the new firmware as built: must compare as equal
    NEWBADSTR   the string ROM has one wrong character: the M of
                "MiSTer2MEGA65" in the boot banner (label LOG_M2M) is an X
    NEWBADTAB   two words of the handle table in the firmware ROM are swapped:
                LOG_M2M and LOG_CORE

    negctl.py [--sim ghdl|nvc]

Exit code 0 if the undamaged firmware is reported as equal and both damaged
ROM sets are reported as different.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim                  # noqa: E402
import compare              # noqa: E402
import strrom_tools         # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sim", default="nvc", choices=["ghdl", "nvc"])
    args = ap.parse_args()
    fw, strings, lis = sim.ROMSETS["NEW"]
    tab, lo, hi = strrom_tools.table()
    pos = {name: p for name, addr, p in tab}
    adr = {name: addr for name, addr, p in tab}
    tmp = os.path.join(sim.OUT, "work", "negctl")
    os.makedirs(tmp, exist_ok=True)

    # one wrong character in the string ROM
    rom = open(strings).read().split("\n")
    banner = bytes(int(x, 16) for x in rom[pos["LOG_M2M"]:pos["LOG_M2M"] + 80])
    p = pos["LOG_M2M"] + banner.index(b"MiSTer2MEGA65")
    assert rom[p].upper() == "4D", rom[p]
    rom[p] = "58"
    badstr = os.path.join(tmp, "m2m-strings-badchar.rom")
    with open(badstr, "w") as f:
        f.write("\n".join(rom))

    # two table words swapped in the firmware ROM (line n holds the word of address n)
    words = open(fw).read().split("\n")
    a, b = adr["LOG_M2M"], adr["LOG_CORE"]
    assert int(words[a], 2) == pos["LOG_M2M"] and int(words[b], 2) == pos["LOG_CORE"]
    words[a], words[b] = words[b], words[a]
    badtab = os.path.join(tmp, "m2m-rom-badtable.rom")
    with open(badtab, "w") as f:
        f.write("\n".join(words))

    ref = os.path.join(sim.RUNS, "main", "OLD_" + args.sim)
    runs = os.path.join(sim.RUNS, "negctl")
    ok = True
    for name, romset, want_equal in (("NEWSHORT", (fw, strings, lis), True),
                                     ("NEWBADSTR", (fw, badstr, lis), False),
                                     ("NEWBADTAB", (badtab, strings, lis), False)):
        sim.simulate("negctl", name, sim=args.sim, romset=romset, timeout=1200, quiet=True)
        rep = compare.compare_runs(os.path.join(runs, name + "_" + args.sim), ref, prefix=True)
        with open(os.path.join(runs, "compare_%s_%s_vs_main_OLD.txt" % (name, args.sim)), "w") as f:
            f.write("\n".join(rep.lines) + "\n")
        good = (rep.diffs == 0) == want_equal
        ok &= good
        print("%s against main/OLD: %d difference(s) -> %s" %
              (name, rep.diffs, "as expected" if good else "NOT AS EXPECTED"))
        for line in rep.lines:
            if line.startswith("DIFFERENCE") or line.startswith("   ") or line.startswith("UART"):
                print("   " + line[:230])
    print("NEGATIVE CONTROL: %s" % ("OK: the comparison accepts the undamaged firmware and detects both defects"
                                    if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
