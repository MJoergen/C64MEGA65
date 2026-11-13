#!/usr/bin/env python3
"""Renders video RAM dumps of qsys_tb.vhd as text: showvram.py FILE [FILE ...] [--attr]"""
import sys


def show(path, attr=False, cols=45, rows=33):
    lines = open(path).read().split("\n")
    print("== %s: %s" % (path.split("/")[-1], lines[0]))
    words = []
    for l in lines[1:]:
        words += [int(w, 16) for w in l.split()]
    for y in range(rows):
        row = words[y * cols:(y + 1) * cols]
        if not any(row):
            continue
        text = "".join(chr(w & 0xFF) if 32 <= (w & 0xFF) < 127 else ("#" if (w & 0xFF) else " ") for w in row)
        line = "%2d |%s|" % (y, text)
        if attr:
            line += " " + "".join("%X" % ((w >> 8) & 0xF) for w in row)
        print(line)
    rest = [w for w in words[cols * rows:] if w]
    if rest:
        print("   %d words that are not zero behind the screen" % len(rest))


if __name__ == "__main__":
    a = "--attr" in sys.argv
    for f in [x for x in sys.argv[1:] if x != "--attr"]:
        show(f, a)
