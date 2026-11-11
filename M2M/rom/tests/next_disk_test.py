#!/usr/bin/env python3
"""
Headless test of the selection logic of the Next disk feature (VD_NEXT_DISK).

VD_NEXT_DISK (../vdrives.asm) mounts the disk image that follows the mounted
one in its folder, in exactly the order and with exactly the filter of the
file browser. Its building blocks are DIRBROWSE_READ, which now also stores
the start cluster of every entry in the list, and DIRBROWSE_NEXT, which walks
the ring of files in that list (../dirbrowse.asm).

This script

    * builds an MBR plus FAT32 image with long file names (VFAT), hidden
      files, number-like names, directories that look like disk images, a
      directory that spans several clusters and lower case 8.3 names,
    * runs next_disk_test.asm in the QNICE emulator with the image attached
      as the SD card, and
    * compares the output with an independent Python model of the file
      browser: the C64 file filter (.D64 and .D81, directories always), the
      case insensitive sort order with directories first and the special
      rule for names that are numbers, the start cluster stored in each list
      element and the next image with wrap-around.

Run it from anywhere:

    python3 next_disk_test.py

Requires the QNICE toolchain and the monitor to be built for the host
platform, see AGENTS.md section 7.
"""

import functools
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
QNICE = os.path.join(REPO, "M2M", "QNICE")
ASM = os.path.join(QNICE, "assembler", "asm")
EMU = os.path.join(QNICE, "emulator", "qnice")
MONITOR = os.path.join(QNICE, "monitor", "monitor.out")
TESTBED = "next_disk_test"

SECTOR = 512
PART_START = 2048
SEC_PER_CLUS = 2
CLUS_BYTES = SECTOR * SEC_PER_CLUS
RSVD = 32
NUM_FATS = 2
TOTAL_SEC = 140000          # keeps the cluster count above the FAT32 floor

ATTR_HIDDEN = 0x02
ATTR_DIR = 0x10
ATTR_ARCHIVE = 0x20

LONG_STEM = ("The Very Long Adventure Game With A Name That Goes On And On "
             "Beyond Everything A File Browser Can Show On One Line - Side ")


def F(name, attr=ATTR_ARCHIVE):
    return {"name": name, "dir": False, "attr": attr}


def D(name, children):
    return {"name": name, "dir": True, "attr": ATTR_DIR, "children": children}


# The directory entries are deliberately not in sorted order.
TREE = [
    F("ROOT1.D64"),
    F("root2.d64"),                     # 8.3 with the lower case flags
    F("README.TXT"),
    D("DISKS", [
        F("Zork.d64"),
        F("readme.txt"),
        F("Game Disk 10.d64"),
        D("Extras", []),
        F("Game Disk 2.d64"),
        F("hidden.d64", ATTR_HIDDEN | ATTR_ARCHIVE),
        D("B.D64", []),                 # a folder named like an image
        F("intro.prg"),
        F("Game Disk 1.d64"),
        F("a.D81"),
    ]),
    D("NUMS", [
        F("2.d64"), D("10", []), F("100.d64"), F("10.d64"), D("2", []),
        F("9.txt"), F("3.D81"), D("1", []), F("1.d64"),
    ]),
    D("SINGLE", [F("notes.txt"), D("sub", []), F("only.d64")]),
    D("EMPTY", [F("readme.txt"), D("dir1", [])]),
    D("LONG", [
        F(LONG_STEM + "C.d64"),
        F(LONG_STEM + "A.d64"),
        F("short.d64"),
        F(LONG_STEM + "B.d64"),
        F(LONG_STEM + "B.txt"),
    ]),
    D("OTHER", [F("elsewhere.d64")]),
]

# (folder, mounted file) in the order of CASES in next_disk_test.asm
CASES = [
    ("/DISKS", "/DISKS/Zork.d64"),
    ("/DISKS", "/DISKS/Game Disk 1.d64"),
    ("/DISKS", "/OTHER/elsewhere.d64"),
    ("/NUMS", "/NUMS/10.d64"),
    ("/SINGLE", "/SINGLE/only.d64"),
    ("/EMPTY", "/OTHER/elsewhere.d64"),
    ("/LONG", "/LONG/" + LONG_STEM + "A.d64"),
    ("/", "/ROOT1.D64"),
]


# ----------------------------------------------------------------------------
# FAT32 image with long file names
# ----------------------------------------------------------------------------

def _fat_size(total, rsvd, spc, num_fats):
    fatsz = 1
    while True:
        data = total - rsvd - num_fats * fatsz
        clusters = data // spc
        need = -(-(clusters + 2) * 4 // SECTOR)
        if need == fatsz:
            return fatsz, clusters
        fatsz = need


def _is_short(name):
    """Plain upper case 8.3 name that needs no long file name entries."""
    if name in (".", ".."):
        return True
    base, _, ext = name.partition(".")
    ok = set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
    return (0 < len(base) <= 8 and len(ext) <= 3 and "." not in ext and
            set(base) <= ok and set(ext) <= ok)


def _is_lower83(name):
    base, _, ext = name.partition(".")
    return (name == name.lower() and name.upper() != name and
            _is_short(name.upper()) and base == base.lower() and
            ext == ext.lower())


def _short_raw(name):
    if name in (".", ".."):
        return name.ljust(11).encode("ascii")
    base, _, ext = name.partition(".")
    return (base.ljust(8) + ext.ljust(3)).encode("ascii")


def _checksum(raw11):
    s = 0
    for b in raw11:
        s = (((s & 1) << 7) + (s >> 1) + b) & 0xFF
    return s


def _entry(raw11, attr, cluster, size, nt=0):
    return (raw11 + bytes([attr, nt, 0]) + b"\x00" * 6 +
            struct.pack("<H", (cluster >> 16) & 0xFFFF) + b"\x00" * 4 +
            struct.pack("<H", cluster & 0xFFFF) + struct.pack("<I", size))


def _lfn_entries(name, raw11):
    chk = _checksum(raw11)
    units = [ord(c) for c in name]
    if len(units) % 13:
        units.append(0)
    while len(units) % 13:
        units.append(0xFFFF)
    n = len(units) // 13
    out = []
    for seq in range(n, 0, -1):         # stored from the last part backwards
        part = units[(seq - 1) * 13: seq * 13]
        e = bytearray(32)
        e[0] = seq | (0x40 if seq == n else 0)
        for i, u in enumerate(part[0:5]):
            struct.pack_into("<H", e, 1 + 2 * i, u)
        e[11] = 0x0F
        e[13] = chk
        for i, u in enumerate(part[5:11]):
            struct.pack_into("<H", e, 14 + 2 * i, u)
        for i, u in enumerate(part[11:13]):
            struct.pack_into("<H", e, 28 + 2 * i, u)
        out.append(bytes(e))
    return b"".join(out)


class Image:
    def __init__(self):
        self.fatsz, clusters = _fat_size(TOTAL_SEC, RSVD, SEC_PER_CLUS,
                                         NUM_FATS)
        assert clusters >= 65525
        self.fat_start = PART_START + RSVD
        self.data_start = self.fat_start + NUM_FATS * self.fatsz
        self.fat = bytearray(self.fatsz * SECTOR)
        self.next_free = 2
        self.writes = []                # (lba, bytes)
        self.short_counter = 0

    def clus_lba(self, n):
        return self.data_start + (n - 2) * SEC_PER_CLUS

    def alloc(self, count):
        chain = list(range(self.next_free, self.next_free + count))
        self.next_free += count
        for a, b in zip(chain, chain[1:]):
            struct.pack_into("<I", self.fat, a * 4, b)
        struct.pack_into("<I", self.fat, chain[-1] * 4, 0x0FFFFFFF)
        return chain

    def put_chain(self, chain, data):
        data = data.ljust(len(chain) * CLUS_BYTES, b"\x00")
        for i, c in enumerate(chain):
            self.writes.append((self.clus_lba(c),
                                data[i * CLUS_BYTES:(i + 1) * CLUS_BYTES]))

    def dir_bytes(self, node, own, parent):
        """Directory entries of node; children must have clusters."""
        out = bytearray()
        if own is not None:             # not the root directory
            out += _entry(_short_raw("."), ATTR_DIR, own, 0)
            out += _entry(_short_raw(".."), ATTR_DIR, parent or 0, 0)
        for ch in node["children"]:
            size = 0 if ch["dir"] else ch["size"]
            name = ch["name"]
            if _is_short(name):
                out += _entry(_short_raw(name), ch["attr"], ch["cluster"],
                              size)
            elif _is_lower83(name):
                out += _entry(_short_raw(name.upper()), ch["attr"],
                              ch["cluster"], size, nt=0x18)
            else:
                self.short_counter += 1
                raw = ("N%05d~1" % self.short_counter + "LFN").encode()
                out += _lfn_entries(name, raw)
                out += _entry(raw, ch["attr"], ch["cluster"], size)
        return bytes(out)

    @staticmethod
    def dir_size(node, is_root):
        n = 0 if is_root else 2
        for ch in node["children"]:
            name = ch["name"]
            n += 1
            if not (_is_short(name) or _is_lower83(name)):
                n += -(-(len(name) + 1) // 13)
        return n * 32

    def layout(self, node, is_root, parent_clus):
        """Allocate clusters for a directory (already allocated) children."""
        for ch in node["children"]:
            if ch["dir"]:
                size = self.dir_size(ch, False)
                ch["chain"] = self.alloc(-(-size // CLUS_BYTES))
                ch["cluster"] = ch["chain"][0]
            else:
                ch["size"] = 100 + len(ch["name"])
                ch["chain"] = self.alloc(1)
                ch["cluster"] = ch["chain"][0]
                self.put_chain(ch["chain"], ch["name"].encode())
        own = None if is_root else node["cluster"]
        self.put_chain(node["chain"],
                       self.dir_bytes(node, own,
                                      None if is_root else parent_clus))
        for ch in node["children"]:
            if ch["dir"]:
                self.layout(ch, False, own)

    def build(self, path, tree):
        struct.pack_into("<I", self.fat, 0, 0x0FFFFFF8)
        struct.pack_into("<I", self.fat, 4, 0x0FFFFFFF)
        root = {"name": "", "dir": True, "children": tree}
        size = self.dir_size(root, True)
        root["chain"] = self.alloc(-(-size // CLUS_BYTES))
        root["cluster"] = root["chain"][0]
        self.layout(root, True, None)

        bs = bytearray(SECTOR)
        bs[0:3] = b"\xEB\x58\x90"
        bs[3:11] = b"QNICETST"
        struct.pack_into("<H", bs, 11, SECTOR)
        bs[13] = SEC_PER_CLUS
        struct.pack_into("<H", bs, 14, RSVD)
        bs[16] = NUM_FATS
        bs[21] = 0xF8
        struct.pack_into("<H", bs, 24, 63)
        struct.pack_into("<H", bs, 26, 255)
        struct.pack_into("<I", bs, 28, PART_START)
        struct.pack_into("<I", bs, 32, TOTAL_SEC)
        struct.pack_into("<I", bs, 36, self.fatsz)
        struct.pack_into("<I", bs, 44, root["cluster"])
        struct.pack_into("<H", bs, 48, 1)
        struct.pack_into("<H", bs, 50, 6)
        bs[64] = 0x80
        bs[66] = 0x29
        struct.pack_into("<I", bs, 67, 0x12345678)
        bs[71:82] = b"NEXTDISK   "
        bs[82:90] = b"FAT32   "
        struct.pack_into("<H", bs, 510, 0xAA55)

        fsinfo = bytearray(SECTOR)
        struct.pack_into("<I", fsinfo, 0, 0x41615252)
        struct.pack_into("<I", fsinfo, 484, 0x61417272)
        struct.pack_into("<I", fsinfo, 488, 0xFFFFFFFF)
        struct.pack_into("<I", fsinfo, 492, self.next_free)
        struct.pack_into("<H", fsinfo, 510, 0xAA55)

        mbr = bytearray(SECTOR)
        mbr[446:462] = (bytes([0x00, 0x01, 0x01, 0x00, 0x0C, 0xFE, 0xFF,
                               0xFF]) + struct.pack("<I", PART_START) +
                        struct.pack("<I", TOTAL_SEC))
        struct.pack_into("<H", mbr, 510, 0xAA55)

        with open(path, "wb") as f:
            f.truncate((PART_START + TOTAL_SEC) * SECTOR)

            def put(lba, data):
                f.seek(lba * SECTOR)
                f.write(data)

            put(0, mbr)
            put(PART_START, bs)
            put(PART_START + 1, fsinfo)
            put(PART_START + 6, bs)
            for i in range(NUM_FATS):
                put(self.fat_start + i * self.fatsz, self.fat)
            for lba, data in self.writes:
                put(lba, data)
        return root


# ----------------------------------------------------------------------------
# Independent model of the file browser and of DIRBROWSE_NEXT
# ----------------------------------------------------------------------------

def find(root, path):
    node = root
    for part in [p for p in path.split("/") if p]:
        node = next(c for c in node["children"]
                    if c["name"].upper() == part.upper())
    return node


def _isanum(s):
    return len(s) > 0 and all(c in "\x01\x02" or c.isdigit() for c in s)


def _compare(a, b):
    """_DIRBR_COMPARE: case insensitive, folders first, numbers by length."""
    a, b = a.upper(), b.upper()
    if a.startswith("<"):
        a = a.replace("<", "\x01").replace(">", "\x02")
    if b.startswith("<"):
        b = b.replace("<", "\x01").replace(">", "\x02")
    if _isanum(a) and _isanum(b) and len(a) != len(b):
        return -1 if len(a) < len(b) else 1
    return (a > b) - (a < b)


def _shown(ch):
    if ch["attr"] & ATTR_HIDDEN:
        return False
    if ch["dir"]:
        return True
    return ch["name"].upper().endswith((".D64", ".D81"))


def browser_list(root, folder):
    """List of (data string, is_dir, cluster) exactly as the browser has it."""
    node = find(root, folder)
    items = []
    if node is not root:
        parent = None
        stack = [(root, None)]
        while stack:                    # find the parent for ".."
            n, p = stack.pop()
            if n is node:
                parent = p
                break
            stack += [(c, n) for c in n["children"] if c["dir"]]
        pclus = 0 if parent is root else parent["cluster"]
        items.append(("<..>", True, pclus))
    for ch in node["children"]:
        if _shown(ch):
            data = "<%s>" % ch["name"] if ch["dir"] else ch["name"]
            items.append((data, ch["dir"], ch["cluster"]))
    return sorted(items, key=functools.cmp_to_key(
        lambda x, y: _compare(x[0], y[0])))


def expected(root):
    out = []
    for folder, mounted in CASES:
        lst = browser_list(root, folder)
        out.append("CASE " + folder)
        for data, is_dir, clus in lst:
            out.append("E %04X %04X %04X %s" % (int(is_dir), clus >> 16,
                                                 clus & 0xFFFF, data))
        files = [i for i, it in enumerate(lst) if not it[1]]
        mclus = find(root, mounted)["cluster"]
        cur = next((i for i in files if lst[i][2] == mclus), None)
        out.append("CUR " + (lst[cur][0] if cur is not None else "-"))
        if not files:
            out.append("NEXT -")
            out.append("RING ")
            continue
        start = files[(files.index(cur) + 1) % len(files)] \
            if cur is not None else files[0]
        out.append("NEXT %s@%04X" % (lst[start][0], start))
        k = files.index(start)
        ring = [files[(k + j) % len(files)] for j in range(len(files))]
        out.append("RING " + "|".join("%s@%04X" % (lst[i][0], i)
                                      for i in ring))
    out.append("TESTBED-DONE")
    return out


# ----------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------------

def main():
    for p in (ASM, EMU, MONITOR):
        if not os.path.exists(p):
            print("FAIL: missing " + p)
            print("      build the QNICE toolchain and the monitor first")
            return 1

    src = os.path.join(HERE, TESTBED + ".asm")
    out = os.path.join(HERE, TESTBED + ".out")
    r = subprocess.run([ASM, src], cwd=HERE, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        print(r.stdout + r.stderr)
        print("FAIL: could not assemble " + TESTBED + ".asm")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        img = os.path.join(tmp, "nextdisk.img")
        root = Image().build(img, TREE)
        try:
            r = subprocess.run([EMU, "-a", img, "-b", "0x8000", MONITOR, out],
                               capture_output=True, text=True, timeout=300,
                               stdin=subprocess.DEVNULL)
        except subprocess.TimeoutExpired:
            print("FAIL: emulator timed out")
            return 1

    # the emulator turns CR LF into two line breaks: ignore empty lines
    got = [l for l in r.stdout.splitlines() if l.strip()]
    if got and got[0].startswith("next_disk_test:"):
        got = got[1:]
    if "TESTBED-DONE" in got:           # the monitor prompt follows the exit
        got = got[:got.index("TESTBED-DONE") + 1]
    want = expected(root)

    if got != want:
        print("FAIL: emulator output differs from the model")
        for i in range(max(len(got), len(want))):
            g = got[i] if i < len(got) else "<missing>"
            w = want[i] if i < len(want) else "<missing>"
            mark = "  " if g == w else "!!"
            print("%s got:  %s" % (mark, g))
            if g != w:
                print("   want: %s" % w)
        return 1

    cases = sum(1 for l in want if l.startswith("CASE "))
    print("PASS: %d cases: list layout, filter, sort order, current image, "
          "next image with wrap-around and the complete ring" % cases)
    return 0


if __name__ == "__main__":
    sys.exit(main())
