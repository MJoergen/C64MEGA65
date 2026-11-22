#!/usr/bin/env python3
"""Compare the stock 1581 ROM (mif.hex, $8000-$FFFF) with another 32 KB ROM
image and list differing address ranges; with --ranges a-b,... report only
those ranges. Prints addresses and counts, no ROM bytes.
Usage: romdiff.py <mif.hex> <rom.bin> [--ranges C3BB-C545,CA00-CAE1,...]"""
import sys
mif, rom = sys.argv[1], sys.argv[2]
a = [int(l.strip(), 16) for l in open(mif) if l.strip()]
b = open(rom, 'rb').read()
assert len(a) == 32768 and len(b) == 32768, (len(a), len(b))
diff = [i for i in range(32768) if a[i] != b[i]]
runs = []
for i in diff:
    if runs and i <= runs[-1][1] + 8:
        runs[-1][1] = i
    else:
        runs.append([i, i])
print('differing bytes: %d in %d runs (gap<=8 merged)' % (len(diff), len(runs)))
if '--ranges' in sys.argv:
    rs = sys.argv[sys.argv.index('--ranges') + 1].split(',')
    for r in rs:
        lo, hi = [int(x, 16) for x in r.split('-')]
        n = sum(1 for i in diff if lo <= i + 0x8000 <= hi)
        print('  $%04X-$%04X: %d differing bytes' % (lo, hi, n))
else:
    for lo, hi in runs:
        print('  $%04X-$%04X (%d bytes differ)' % (lo + 0x8000, hi + 0x8000, sum(1 for i in diff if lo <= i <= hi)))
