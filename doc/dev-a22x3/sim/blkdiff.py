#!/usr/bin/env python3
"""
Compares two sparse SD card images (sd/*.blk, as written by make_sd.py and make_sd2.py)
block by block.

    blkdiff.py OLD.blk NEW.blk

Prints the blocks that only one image has and, for every block that differs, the byte
offsets with the old and the new value (the first 30). After the images were built again
for a changed menu, only the directory entry of the config file (its size) and the blocks
of the config file itself should differ; fatdir.py shows which block holds which entry.
"""
import sys


def load(path):
    blocks = {}
    for line in open(path):
        lba, hx = line.split()
        blocks[int(lba)] = bytes.fromhex(hx)
    return blocks


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    print("blocks: old %d, new %d; only old: %s; only new: %s" %
          (len(a), len(b), sorted(set(a) - set(b)), sorted(set(b) - set(a))))
    for lba in sorted(set(a) & set(b)):
        if a[lba] != b[lba]:
            offs = [i for i in range(512) if a[lba][i] != b[lba][i]]
            print("block %d differs in %d bytes: %s" %
                  (lba, len(offs), " ".join("%d:%02X>%02X" % (i, a[lba][i], b[lba][i]) for i in offs[:30])))


if __name__ == "__main__":
    main()
