#!/usr/bin/env python3
"""
Builds sd/card_full.blk for the scenarios of the merged firmware (e46bc75):

    /c64/c64mega65-<version>.cfg  config file: factory defaults, except that the
                                  picker of F9 selects "Next disk drive 8"
                                  instead of "Freeze" (so that Next disk can be
                                  tested without a patched config.vhd)
    /c64/DISK1.D64 .. DISK3.D64   174848 bytes each (valid D64 size); the first
                                  sector holds the name of the image, the rest
                                  is zero
    /c64/TEST.PRG                 small program, load address $0801
    /c64/GOOD.CRT                 valid cartridge: header + one 8 KB CHIP packet
    /c64/TOOBIG.CRT               4 MB: larger than the cartridge pool

    python3 make_sd2.py [--no-f9] [--bad]
        --no-f9: keep the factory default of F9
        --bad:   also /c64/BAD.D64 (1000 bytes: a .d64 of the wrong size); writes
                 sd/card_bad.blk instead of sd/card_full.blk
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mkfat32 import Fat32                          # noqa: E402
import make_sd                                     # noqa: E402

D64_SIZE = 174848


def d64(name):
    data = bytearray(D64_SIZE)
    tag = ("IMAGE " + name).encode()
    data[0:len(tag)] = tag
    return bytes(data)


def main():
    text = make_sd.config_vhd()
    version = make_sd.core_version(text)
    size, defaults = make_sd.menu_defaults(text)
    sel = set(defaults)
    f9 = make_sd.osm_const("C64_OSM_SC_F9")
    if "--no-f9" not in sys.argv:
        assert f9 + 1 in sel, "F9 default is not Freeze"
        sel = (sel - {f9 + 1}) | {f9 + 4}             # Freeze -> Next disk drive 8
    cfg = bytes(1 if i in sel else 0 for i in range(size))
    img = Fat32()
    img.add_dir("/c64")
    img.add_file("/c64/c64mega65-%s.cfg" % version, cfg)
    for n in ("DISK1", "DISK2", "DISK3"):
        img.add_file("/c64/%s.D64" % n, d64(n))
    if "--bad" in sys.argv:
        img.add_file("/c64/BAD.D64", bytes((i * 7 + 3) & 0xFF for i in range(1000)))
    img.add_file("/c64/TEST.PRG", bytes([0x01, 0x08]) + bytes(range(1, 65)))
    img.add_file("/c64/GOOD.CRT", make_sd.good_crt())
    img.add_file("/c64/TOOBIG.CRT", size=4 * 1024 * 1024)
    out = os.path.join(HERE, "sd")
    name = "card_bad" if "--bad" in sys.argv else "card_full"
    n = img.write_blk(os.path.join(out, name + ".blk"))
    with open(os.path.join(out, name + ".cfg.bin"), "wb") as f:
        f.write(cfg)
    print(name + ".blk: %d blocks; config file c64mega65-%s.cfg, %d bytes, selected lines %s" %
          (n, version, size, sorted(sel)))


if __name__ == "__main__":
    main()
