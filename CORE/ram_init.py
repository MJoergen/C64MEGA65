#! /usr/bin/env python

#
# Generate a 64 kB binary file containing the initial (power-on) value of
# all RAM cells.
#
# Previously, all RAM cells were cleared, which caused the game Q-Bert to fail.
#
# See discussion here : https://csdb.dk/forums/?roomid=11&topicid=116800&showallposts=1
#
# The actual pattern chosen here is the default pattern from VICE.
#
# Running this script (over)writes the file ram_init, which is used in
# CORE/vhdl/mega65.vhd
#

def write_pattern(f, b, l):
    assert l % len(b) == 0
    for i in range(0, l, len(b)):
        f.write(bytearray(b))

ram_file = open("ram_init.bin", "wb")
write_pattern(ram_file, [0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00], 0x4000)
write_pattern(ram_file, [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF], 0x4000)
write_pattern(ram_file, [0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00], 0x4000)
write_pattern(ram_file, [0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF], 0x4000)
ram_file.close()


