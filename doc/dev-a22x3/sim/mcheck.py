#!/usr/bin/env python3
"""
Checks of the 06cda88 validation runs (m2, m3, control):
    mcheck.py RUN_DIR

* memdump.log: FAT32 file handles (12 words): size (+5/+6) and start cluster (+9/+10)
* win.log, per segment between two '# dump' markers: writes to the vdrives device 0x0101
  (address 0 = img_mounted strobe), writes to the mount buffer 0x0102, writes to the
  cartridge device 0x0103 window 0xFFFF (CSR)
* menu lines "8:" and "CRT:" of every video RAM dump
"""
import glob
import os
import re
import sys

run = sys.argv[1]

print("== file handles (memdump.log)")
for l in open(os.path.join(run, "memdump.log")):
    p = l.split()
    ts, tag, addr = p[0], p[1], p[2].rstrip(":")
    w = [int(x, 16) for x in p[3:]]
    if len(w) >= 11:
        print("%12s %-12s @%s size=0x%04X%04X start_cluster=0x%04X%04X  words=%s" %
              (ts, tag, addr, w[6], w[5], w[10], w[9], " ".join(p[3:])))

print("== win.log writes per segment (segment = from the named dump to the next one)")
seg = "start"
cnt = {}
order = ["start"]
for l in open(os.path.join(run, "win.log")):
    if l.startswith("# dump"):
        seg = l.split()[2]
        order.append(seg)
        continue
    if not l.startswith("W "):
        continue
    _, dev, a, d = l.split()
    c = cnt.setdefault(seg, {"strobe": 0, "vd_other": 0, "mountbuf": 0, "crt_csr": [], "crt_data": 0})
    if dev == "0101":
        if int(a, 16) == 0:
            c["strobe"] += 1
        else:
            c["vd_other"] += 1
    elif dev == "0102":
        c["mountbuf"] += 1
    elif dev == "0103":
        if a.startswith("FFFF"):
            c["crt_csr"].append(a[-3:] + "=" + d)
        else:
            c["crt_data"] += 1
for s in order:
    c = cnt.get(s)
    if c:
        csr = []
        for x in c["crt_csr"]:                       # collapse repeated cycles of one write
            if not csr or csr[-1] != x:
                csr.append(x)
        print("  after %-18s img_mounted writes=%d other vdrive writes=%d mount buffer writes=%d "
              "crt CSR writes=%s crt data writes=%d" %
              (s, c["strobe"], c["vd_other"], c["mountbuf"], csr or "-", c["crt_data"]))
    else:
        print("  after %-18s no writes" % s)

print("== menu lines in the video RAM dumps")
for f in sorted(glob.glob(os.path.join(run, "vram_*.txt")), key=os.path.getmtime):
    lines = open(f).read().split("\n")
    w = [int(x, 16) for l in lines[1:] for x in l.split()]
    found = []
    for y in range(33):
        t = "".join(chr(v & 0xFF) if 32 <= (v & 0xFF) < 127 else ("#" if v & 0xFF else " ") for v in w[y * 45:(y + 1) * 45])
        m = re.search(r"#.(8:|CRT:)(.*?)\s*#\s*$", t)
        if m and "Internal" not in t:
            found.append((m.group(1) + m.group(2)).strip())
    head = re.search(r"osm='(.)'", lines[0])
    print("  %-26s osm=%s %s" % (os.path.basename(f), head.group(1) if head else "?", found or ""))
