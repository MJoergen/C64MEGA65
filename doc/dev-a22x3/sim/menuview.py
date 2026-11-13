#!/usr/bin/env python3
"""Compact view of OSM video RAM dumps: menu window lines with '>' on the cursor line.
   menuview.py FILE [FILE ...] [--full]"""
import sys
for path in [a for a in sys.argv[1:] if not a.startswith("--")]:
    lines = open(path).read().split("\n")
    w = [int(x, 16) for l in lines[1:] for x in l.split()]
    print("==", path.split("/")[-1], lines[0][:70])
    for y in range(33):
        row = w[y * 45:(y + 1) * 45]
        t = "".join(chr(v & 0xFF) if 32 <= (v & 0xFF) < 127 else ("#" if v & 0xFF else " ") for v in row).rstrip()
        if not t.strip() or (set(t.strip()) <= {"#", " "} and "--full" not in sys.argv):
            continue
        hl = any((v >> 8) & 0xF0 for v in row[1:44])
        print("%2d %s %s" % (y, ">" if hl else " ", t))
