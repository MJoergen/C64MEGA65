#!/usr/bin/env python3
"""Lists the 8.3 directory entries of a sparse SD card image (sd/*.blk): name, start cluster, size.
   fatdir.py CARD.blk"""
import struct, sys
seen = set()
for line in open(sys.argv[1]):
    lba, hx = line.split()
    b = bytes.fromhex(hx)
    for o in range(0, 512, 32):
        e = b[o:o + 32]
        name, attr = e[0:11], e[11]
        if attr == 0x0F or name[0] in (0, 0xE5) or not all(32 <= c < 127 for c in name):
            continue
        if attr & 0x08:
            continue
        hi, lo, size = struct.unpack("<H", e[20:22])[0], struct.unpack("<H", e[26:28])[0], struct.unpack("<I", e[28:32])[0]
        key = (name, hi, lo)
        if key in seen:
            continue
        seen.add(key)
        print("block %5s  %-11s attr=%02X start cluster=0x%04X%04X size=%d (0x%08X)" %
              (lba, name.decode(), attr, hi, lo, size, size))
