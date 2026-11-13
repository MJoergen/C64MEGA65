#!/usr/bin/env python3
"""
Maps the peaks of the CPU spy (spy_peaks.log of qsys_tb.vhd) to the firmware listing.

    mapstack.py RUN_DIR [--lis LISTING] [--all] [--min-bank N]

For every new highest register bank level (lines "BANK n pc=... sp=...") it prints
the routine that contains the program counter and the call chain that is visible
on the stack: every stack word that equals the address right behind an RSUB or
ASUB instruction of the listing is taken as a return address (saved registers can
look like return addresses by chance; such entries are marked with '?', when the
caller does not contain a call instruction at that place it is not listed at all).
--all also maps the "SP" lines (new lowest stack pointer).
"""
import argparse
import bisect
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LIS = os.environ.get("QSYS_LIS") or os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))),
                           "wtA", "CORE", "m2m-rom", "m2m-rom.lis")

LINE = re.compile(r"^(\d{6})  ([0-9A-F]{4})  ([0-9A-F]{4})?(?:  ([0-9A-F]{4}))?")


def load_listing(path):
    labels = []                       # (address, name)
    calls = {}                        # address behind a call instruction -> (address, text)
    for line in open(path, errors="replace"):
        if line.startswith("Label-list"):
            break
        m = LINE.match(line)
        if not m:
            continue
        addr = int(m.group(2), 16)
        nwords = (1 if m.group(3) else 0) + (1 if m.group(4) else 0)
        src = line[26:].rstrip("\n")
        code = src.split(";")[0]
        if code and not code[0].isspace():
            name = code.split()[0]
            if not name.startswith("."):
                labels.append((addr, name))
        toks = code.split()
        if toks and not code[0].isspace():
            toks = toks[1:]
        if toks and toks[0] in ("RSUB", "ASUB") and nwords:
            calls[addr + nwords] = (addr, " ".join(toks))
    labels.sort()
    return labels, calls


def routine(labels, addr, glob=True):
    keys = [a for a, _ in labels]
    i = bisect.bisect_right(keys, addr) - 1
    while i >= 0:
        a, n = labels[i]
        if not glob or not n.startswith("_"):
            return "%s+%d" % (n, addr - a)
        i -= 1
    return "?"


def describe(labels, calls, pc, stack):
    out = ["   pc %04X in %s (%s)" % (pc, routine(labels, pc), routine(labels, pc, False))]
    for k, w in enumerate(stack):
        if w in calls:
            a, txt = calls[w]
            out.append("   [sp+%d] ret %04X <- %04X %-28s in %s" % (k, w, a, txt[:28], routine(labels, a)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("--lis", default=DEFAULT_LIS)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--min-bank", type=int, default=0)
    args = ap.parse_args()
    labels, calls = load_listing(args.lis)
    lines = open(os.path.join(args.run, "spy_peaks.log")).read().split("\n")
    i = 0
    while i < len(lines):
        l = lines[i]
        m = re.match(r"\s*([\d.]+) (BANK|SP) (\S+) pc=([0-9A-F]+)(?: sp=([0-9A-F]+))?(?: bank=(\d+))?", l)
        if m and (m.group(2) == "BANK" or args.all):
            stack = []
            if i + 1 < len(lines) and lines[i + 1].strip().startswith("stack"):
                stack = [int(x, 16) for x in lines[i + 1].split()[1:]]
            # file browser stack: the main stack follows (line "mainstack <sp> words")
            if i + 2 < len(lines) and lines[i + 2].strip().startswith("mainstack"):
                stack += [int(x, 16) for x in lines[i + 2].split()[2:]]
            if m.group(2) == "BANK" and int(m.group(3)) < args.min_bank:
                i += 1
                continue
            print("%s us  %s %s  sp=%s" % (m.group(1), m.group(2), m.group(3), m.group(5) or m.group(3)))
            print("\n".join(describe(labels, calls, int(m.group(4), 16), stack)))
        i += 1


if __name__ == "__main__":
    main()
