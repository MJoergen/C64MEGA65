#!/usr/bin/env python3
"""Compares the SD card command sequences (sd.log) of two runs up to a time limit of each.
   sddiff.py RUN_A RUN_B [LIMIT_A_US LIMIT_B_US]"""
import difflib, sys
def load(run, limit):
    out = []
    for l in open(run + "/sd.log"):
        p = l.split(None, 1)
        if len(p) < 2 or not p[0].isdigit():
            continue
        if limit and int(p[0]) > limit:
            break
        out.append((int(p[0]), p[1].strip()))
    return out
a = load(sys.argv[1], int(sys.argv[3]) if len(sys.argv) > 3 else 0)
b = load(sys.argv[2], int(sys.argv[4]) if len(sys.argv) > 4 else 0)
print("A: %d commands, B: %d commands" % (len(a), len(b)))
sm = difflib.SequenceMatcher(a=[x[1] for x in a], b=[x[1] for x in b], autojunk=False)
for op, i1, i2, j1, j2 in sm.get_opcodes():
    if op == "equal":
        continue
    print("%s A[%d:%d] (%s) B[%d:%d] (%s)" % (op, i1, i2, ", ".join(x[1] for x in a[i1:i2]) or "-",
                                            j1, j2, ", ".join("%s @%d" % (x[1], x[0]) for x in b[j1:j2]) or "-"))
