#!/usr/bin/env python3
"""Rebuilds the OSM video RAM from the writes in win.log (devices 0x0000 = characters,
0x0001 = attributes, wired as in qsys_tb.vhd) and writes it in the format of the
vram_*.txt dumps, so that showvram.py / menuview.py can render it.
    vramreplay.py RUN_DIR OUT_FILE [LAST_N_WRITES_TO_SKIP]"""
import os
import sys
run, out = sys.argv[1], sys.argv[2]
skip = int(sys.argv[3]) if len(sys.argv) > 3 else 0
vram = [0] * 4096
writes = []
for l in open(os.path.join(run, "win.log")):
    if l.startswith("W 0000 ") or l.startswith("W 0001 "):
        _, dev, a, d = l.split()
        writes.append((dev, int(a, 16) & 0xFFF, int(d, 16) & 0xFF))
for dev, a, d in writes[:len(writes) - skip]:
    vram[a] = (vram[a] & 0xFF00) | d if dev == "0000" else (vram[a] & 0x00FF) | (d << 8)
with open(out, "w") as f:
    f.write("rebuilt from win.log (%d video RAM writes)\n" % (len(writes) - skip))
    for y in range(0, 4096, 45):
        f.write(" ".join("%04X" % v for v in vram[y:y + 45]) + "\n")
