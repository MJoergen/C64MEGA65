#!/usr/bin/env python3
"""
Builds a FAT32 SD card image for the SD card model of the simulation
(tb/sdcard_model_arch.vhd) in pure Python.

The image is written in the sparse text format of the model: one line per
512-byte block that is not all zero, "<block number> <1024 hex digits>".

Layout: MBR with one FAT32 partition (type 0x0C) at block 2048, 2 sectors per
cluster, 32 reserved sectors, two FATs. Directory entries have long file names
(with the checksum of the 8.3 alias) whenever the name is not a plain upper
case 8.3 name.

Usage as a module:

    img = Fat32()
    img.add_dir("/c64")
    img.add_file("/c64/GAME.D64", data)               # bytes
    img.add_file("/c64/BIG.CRT", size=4 * 1024 * 1024)  # zeros of that size
    img.write_blk("sdcard.blk")
"""

import struct

SECTOR = 512


def lfn_checksum(short11):
    s = 0
    for c in short11:
        s = (((s & 1) << 7) + (s >> 1) + c) & 0xFF
    return s


class Node:
    def __init__(self, name, is_dir, data=b"", size=None):
        self.name = name
        self.is_dir = is_dir
        self.data = data
        self.size = len(data) if size is None else size
        self.children = []
        self.cluster = 0
        self.nclus = 0


class Fat32:
    def __init__(self, total_sectors=140000, spc=2, part_start=2048, rsvd=32):
        self.total = total_sectors
        self.spc = spc
        self.part_start = part_start
        self.rsvd = rsvd
        self.root = Node("", True)

    # ---- tree ---------------------------------------------------------------

    def _find(self, path, create_dirs=False):
        node = self.root
        for part in [p for p in path.split("/") if p]:
            nxt = [c for c in node.children if c.name.lower() == part.lower()]
            if nxt:
                node = nxt[0]
            elif create_dirs:
                d = Node(part, True)
                node.children.append(d)
                node = d
            else:
                raise KeyError(path)
        return node

    def add_dir(self, path):
        return self._find(path, create_dirs=True)

    def add_file(self, path, data=b"", size=None):
        parent, _, name = path.rpartition("/")
        d = self._find(parent, create_dirs=True)
        f = Node(name, False, data, size)
        d.children.append(f)
        return f

    # ---- directory entries --------------------------------------------------

    @staticmethod
    def _is_83(name):
        if name in (".", ".."):
            return True
        base, dot, ext = name.partition(".")
        ok = lambda s: all(c.isupper() or c.isdigit() or c in "_-~!#$%&'()@^`{}" for c in s)
        return 1 <= len(base) <= 8 and len(ext) <= 3 and ok(base) and ok(ext) and "." not in ext

    @staticmethod
    def _short(name, used):
        if name == ".":
            return b".          "
        if name == "..":
            return b"..         "
        if Fat32._is_83(name):
            base, _, ext = name.partition(".")
            raw = (base.ljust(8) + ext.ljust(3)).encode("ascii")
            used.add(raw)
            return raw
        base, dot, ext = name.rpartition(".") if "." in name else (name, "", "")
        clean = lambda s: "".join(c for c in s.upper() if c.isalnum())
        n = 1
        while True:
            tail = "~%d" % n
            raw = ((clean(base)[:8 - len(tail)] + tail).ljust(8) + clean(ext)[:3].ljust(3)).encode("ascii")
            if raw not in used:
                used.add(raw)
                return raw
            n += 1

    def _entries(self, node, parent_cluster):
        out = bytearray()
        used = set()
        if node is not self.root:
            out += self._sfn(b".          ", 0x10, node.cluster, 0)
            out += self._sfn(b"..         ", 0x10, parent_cluster, 0)
        for c in node.children:
            short = self._short(c.name, used)
            if not self._is_83(c.name):
                out += self._lfn(c.name, short)
            out += self._sfn(short, 0x10 if c.is_dir else 0x20, c.cluster, 0 if c.is_dir else c.size)
        return bytes(out)

    @staticmethod
    def _sfn(short, attr, cluster, size):
        return (short + bytes([attr]) + b"\x00" * 8 +
                struct.pack("<H", (cluster >> 16) & 0xFFFF) +
                struct.pack("<HH", 0x6000, 0x5B6B) +            # 12:00:00, 2025-11-11
                struct.pack("<H", cluster & 0xFFFF) +
                struct.pack("<I", size))

    @staticmethod
    def _lfn(name, short):
        chk = lfn_checksum(short)
        u = [ord(c) for c in name] + [0]
        while len(u) % 13:
            u.append(0xFFFF)
        parts = [u[i:i + 13] for i in range(0, len(u), 13)]
        out = bytearray()
        for seq in range(len(parts), 0, -1):
            p = parts[seq - 1]
            e = bytearray(32)
            e[0] = seq | (0x40 if seq == len(parts) else 0)
            struct.pack_into("<5H", e, 1, *p[0:5])
            e[11] = 0x0F
            e[13] = chk
            struct.pack_into("<6H", e, 14, *p[5:11])
            struct.pack_into("<2H", e, 28, *p[11:13])
            out += e
        return bytes(out)

    # ---- image --------------------------------------------------------------

    def build(self):
        """Returns {block number: 512 bytes} of the blocks that are not all zero."""
        spc, rsvd = self.spc, self.rsvd
        part_sectors = self.total - self.part_start
        fatsz = 1
        while True:
            clusters = (part_sectors - rsvd - 2 * fatsz) // spc
            need = -(-(clusters + 2) * 4 // SECTOR)
            if need == fatsz:
                break
            fatsz = need
        assert clusters >= 65525, "too few clusters for FAT32"
        clus_bytes = SECTOR * spc
        fat_start = self.part_start + rsvd
        data_start = fat_start + 2 * fatsz

        # allocate clusters: directories first (their size depends on the entries only)
        nxt = 2
        order = []

        def walk(node):
            order.append(node)
            for c in node.children:
                if c.is_dir:
                    walk(c)
        walk(self.root)
        dirs = list(order)
        for d in dirs:
            for c in d.children:
                if not c.is_dir:
                    order.append(c)
        # directory sizes: 32 bytes per short entry plus the long name entries
        for n in order:
            if n.is_dir:
                used = set()
                size = 0 if n is self.root else 64
                for c in n.children:
                    short = self._short(c.name, used)
                    size += 32 + (0 if self._is_83(c.name) else len(self._lfn(c.name, short)))
                size += 32                                      # end marker
                n.nclus = max(1, -(-size // clus_bytes))
            else:
                n.nclus = -(-n.size // clus_bytes)
            n.cluster = nxt if n.nclus else 0
            nxt += n.nclus
        assert nxt - 2 <= clusters, "image too small"

        blocks = {}

        def put(lba, data):
            for i in range(0, len(data), SECTOR):
                chunk = data[i:i + SECTOR].ljust(SECTOR, b"\x00")
                if any(chunk):
                    blocks[lba + i // SECTOR] = bytes(chunk)

        # FAT
        fat = bytearray(fatsz * SECTOR)
        struct.pack_into("<I", fat, 0, 0x0FFFFFF8)
        struct.pack_into("<I", fat, 4, 0x0FFFFFFF)
        for n in order:
            for k in range(n.nclus):
                val = 0x0FFFFFFF if k == n.nclus - 1 else n.cluster + k + 1
                struct.pack_into("<I", fat, (n.cluster + k) * 4, val)
        put(fat_start, bytes(fat))
        put(fat_start + fatsz, bytes(fat))

        # data
        def clus_lba(c):
            return data_start + (c - 2) * spc

        def fill(node, parent_cluster):
            if node.is_dir:
                put(clus_lba(node.cluster), self._entries(node, parent_cluster))
                for c in node.children:
                    fill(c, 0 if node is self.root else node.cluster)
            elif node.nclus:
                put(clus_lba(node.cluster), node.data)
        fill(self.root, 0)

        # volume boot record
        bs = bytearray(SECTOR)
        bs[0:3] = b"\xEB\x58\x90"
        bs[3:11] = b"QSYSTB  "
        struct.pack_into("<H", bs, 11, SECTOR)
        bs[13] = spc
        struct.pack_into("<H", bs, 14, rsvd)
        bs[16] = 2
        bs[21] = 0xF8
        struct.pack_into("<H", bs, 24, 63)
        struct.pack_into("<H", bs, 26, 255)
        struct.pack_into("<I", bs, 28, self.part_start)
        struct.pack_into("<I", bs, 32, part_sectors)
        struct.pack_into("<I", bs, 36, fatsz)
        struct.pack_into("<I", bs, 44, self.root.cluster)
        struct.pack_into("<H", bs, 48, 1)
        struct.pack_into("<H", bs, 50, 6)
        bs[64] = 0x80
        bs[66] = 0x29
        struct.pack_into("<I", bs, 67, 0x12345678)
        bs[71:82] = b"QSYSTB     "
        bs[82:90] = b"FAT32   "
        bs[510:512] = b"\x55\xAA"
        put(self.part_start, bytes(bs))
        put(self.part_start + 6, bytes(bs))

        # MBR
        mbr = bytearray(SECTOR)
        entry = bytearray(16)
        entry[4] = 0x0C
        struct.pack_into("<I", entry, 8, self.part_start)
        struct.pack_into("<I", entry, 12, part_sectors)
        mbr[446:462] = entry
        mbr[510:512] = b"\x55\xAA"
        put(0, bytes(mbr))
        self.layout = dict(fat_start=fat_start, fatsz=fatsz, data_start=data_start, clusters=clusters)
        return blocks

    def write_blk(self, path):
        blocks = self.build()
        with open(path, "w") as f:
            for lba in sorted(blocks):
                f.write("%d %s\n" % (lba, blocks[lba].hex().upper()))
        return len(blocks)

    def write_raw(self, path):
        blocks = self.build()
        with open(path, "wb") as f:
            f.truncate(self.total * SECTOR)
            for lba, data in blocks.items():
                f.seek(lba * SECTOR)
                f.write(data)


if __name__ == "__main__":
    import sys
    img = Fat32()
    img.add_dir("/c64")
    img.add_file("/c64/TEST.D64", bytes(1000))
    n = img.write_blk(sys.argv[1] if len(sys.argv) > 1 else "sdcard.blk")
    print("wrote %d blocks" % n, img.layout)
