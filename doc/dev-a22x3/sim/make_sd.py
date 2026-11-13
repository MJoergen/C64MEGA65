#!/usr/bin/env python3
"""
Builds the SD card images of the simulation scenarios (sparse block files for
tb/sdcard_model_arch.vhd) into the directory sd/ next to this script.

    card_files.blk   card of the scenario "sdcard":

        /c64/c64mega65-<version>.cfg   config file: factory defaults, but the
                                       Kernal is JiffyDOS instead of Standard
        /c64/jd-c64.bin                64 bytes; the Shell does not check the
                                       content of an auto-load ROM
        /c64/WRONG.D64                 1000 bytes: not a valid image size
        /c64/BROKEN.CRT                128 bytes without the signature
        /c64/GOOD.CRT                  valid cartridge file: header and one
                                       CHIP packet with 8192 bytes
        /c64/TOOBIG.CRT                4 MB: larger than the cartridge pool
        /c64/demos/ONE.D64             a file in a sub-directory

    card_empty.blk   card of the scenario "emptycard": no directory and no
                     file that the core can use (only /README.TXT)

The version in the name of the config file is read from CORE/vhdl/config.vhd
and the factory defaults are the lines with OPTM_G_STDSEL in OPTM_GROUPS.
"""

import os
import re
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mkfat32 import Fat32          # noqa: E402

SCR = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
REPO = os.path.join(SCR, "wtA")


def config_vhd():
    return open(os.path.join(REPO, "CORE", "vhdl", "config.vhd")).read()


def core_version(text):
    return re.search(r'constant CORE_VERSION\s*:\s*string\s*:=\s*"([^"]+)"', text).group(1)


def menu_defaults(text):
    """Returns (size, set of the indexes of the lines that are selected by default)."""
    size = int(re.search(r"constant OPTM_SIZE\s*:\s*natural\s*:=\s*(\d+)", text).group(1))
    body = text[text.index("constant OPTM_GROUPS"):]
    body = body[body.index("(") + 1:]
    # one aggregate element per menu line; elements are separated by commas at
    # nesting depth 0 (OPTM_DEP(...) has commas inside of parentheses)
    elems, depth, cur = [], 0, ""
    for line in body.split("\n"):
        line = line.split("--")[0]
        for ch in line:
            if ch == "(":
                depth += 1
            elif ch == ")":
                if depth == 0:
                    elems.append(cur)
                    cur = None
                    break
                depth -= 1
            if ch == "," and depth == 0:
                elems.append(cur)
                cur = ""
            else:
                cur += ch
        if cur is None:
            break
    elems = [e.strip() for e in elems if e is not None and e.strip()]
    if len(elems) != size:
        sys.exit("FAIL: OPTM_GROUPS has %d elements, OPTM_SIZE is %d" % (len(elems), size))
    return size, {i for i, e in enumerate(elems) if re.search(r"\bOPTM_G_STDSEL\b", e)}


def osm_const(name):
    path = os.path.join(REPO, "CORE", "m2m-rom", "osm_const.asm")
    m = re.search(r"^%s\s+\.EQU\s+(\d+)" % re.escape(name), open(path).read(), re.M)
    return int(m.group(1))


def good_crt():
    header = (b"C64 CARTRIDGE   " + struct.pack(">I", 0x40) + struct.pack(">H", 0x0100) +
              struct.pack(">H", 0) + bytes([0, 1]) + bytes(6) + b"QSYSTB TEST CART".ljust(32, b"\x00"))
    assert len(header) == 0x40
    rom = bytearray(0x2000)
    rom[0:9] = bytes([0x09, 0x80, 0x09, 0x80, 0xC3, 0xC2, 0xCD, 0x38, 0x30])   # vectors and CBM80
    chip = (b"CHIP" + struct.pack(">I", 0x2010) + struct.pack(">HHHH", 0, 0, 0x8000, 0x2000) + bytes(rom))
    return header + chip


def main():
    text = config_vhd()
    version = core_version(text)
    size, defaults = menu_defaults(text)
    std, jiffy = osm_const("C64_OSM_KERNAL_STD"), osm_const("C64_OSM_KERNAL_JIFFY")
    assert std in defaults and jiffy not in defaults
    sel = (defaults - {std}) | {jiffy}
    cfg = bytes(1 if i in sel else 0 for i in range(size))
    out = os.path.join(HERE, "sd")
    os.makedirs(out, exist_ok=True)

    img = Fat32()
    img.add_dir("/c64")
    img.add_file("/c64/c64mega65-%s.cfg" % version, cfg)
    img.add_file("/c64/jd-c64.bin", bytes(range(64)))
    img.add_file("/c64/WRONG.D64", bytes(i & 0xFF for i in range(1000)))
    img.add_file("/c64/BROKEN.CRT", b"NOT A CARTRIDGE " * 8)
    img.add_file("/c64/GOOD.CRT", good_crt())
    img.add_file("/c64/TOOBIG.CRT", size=4 * 1024 * 1024)
    img.add_file("/c64/demos/ONE.D64", b"1" * 300)
    n = img.write_blk(os.path.join(out, "card_files.blk"))
    img.write_raw(os.path.join(out, "card_files.img"))
    print("card_files.blk: %d blocks; config file c64mega65-%s.cfg, %d bytes, selected lines %s" %
          (n, version, size, sorted(sel)))

    img = Fat32()
    img.add_file("/README.TXT", b"This card has nothing for the core.\n")
    n = img.write_blk(os.path.join(out, "card_empty.blk"))
    img.write_raw(os.path.join(out, "card_empty.img"))
    print("card_empty.blk: %d blocks" % n)


if __name__ == "__main__":
    main()
