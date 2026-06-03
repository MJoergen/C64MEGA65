# vim: ts=4 sw=4 expandtab

# THIS IS GENERATED PYTHON CODE.
# https://bues.ch/h/crcgen
# 
# This code is Public Domain.
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted.
# 
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
# SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
# RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
# NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE
# USE OR PERFORMANCE OF THIS SOFTWARE.

# CRC polynomial coefficients: x^16 + x^12 + x^5 + 1
#                              0x1021 (hex)
# CRC width:                   16 bits
# CRC shift direction:         left (big endian)
# Input word width:            8 bits

def crc(crcIn, data):
    class bitwrapper:
        def __init__(self, x):
            self.x = x
        def __getitem__(self, i):
            return (self.x >> i) & 1
        def __setitem__(self, i, x):
            self.x = (self.x | (1 << i)) if x else (self.x & ~(1 << i))
    crcIn = bitwrapper(crcIn)
    data = bitwrapper(data)
    ret = bitwrapper(0)
    ret[0] = crcIn[8] ^ crcIn[12] ^ data[0] ^ data[4]
    ret[1] = crcIn[9] ^ crcIn[13] ^ data[1] ^ data[5]
    ret[2] = crcIn[10] ^ crcIn[14] ^ data[2] ^ data[6]
    ret[3] = crcIn[11] ^ crcIn[15] ^ data[3] ^ data[7]
    ret[4] = crcIn[12] ^ data[4]
    ret[5] = crcIn[8] ^ crcIn[12] ^ crcIn[13] ^ data[0] ^ data[4] ^ data[5]
    ret[6] = crcIn[9] ^ crcIn[13] ^ crcIn[14] ^ data[1] ^ data[5] ^ data[6]
    ret[7] = crcIn[10] ^ crcIn[14] ^ crcIn[15] ^ data[2] ^ data[6] ^ data[7]
    ret[8] = crcIn[0] ^ crcIn[11] ^ crcIn[15] ^ data[3] ^ data[7]
    ret[9] = crcIn[1] ^ crcIn[12] ^ data[4]
    ret[10] = crcIn[2] ^ crcIn[13] ^ data[5]
    ret[11] = crcIn[3] ^ crcIn[14] ^ data[6]
    ret[12] = crcIn[4] ^ crcIn[8] ^ crcIn[12] ^ crcIn[15] ^ data[0] ^ data[4] ^ data[7]
    ret[13] = crcIn[5] ^ crcIn[9] ^ crcIn[13] ^ data[1] ^ data[5]
    ret[14] = crcIn[6] ^ crcIn[10] ^ crcIn[14] ^ data[2] ^ data[6]
    ret[15] = crcIn[7] ^ crcIn[11] ^ crcIn[15] ^ data[3] ^ data[7]
    return ret.x

