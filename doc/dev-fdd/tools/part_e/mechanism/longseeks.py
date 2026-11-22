#!/usr/bin/env python3
"""Structure only: for a D81, list the head moves a sequential read of every file needs
(directory track 40 -> first block, then along the chain), and count the long ones.
Usage: python3 -I longseeks.py image.d81 [min_cylinders]"""
import sys
img = open(sys.argv[1], 'rb').read()
lim = int(sys.argv[2]) if len(sys.argv) > 2 else 60
def blk(t, s):
    o = ((t - 1) * 40 + s) * 256
    return img[o:o + 256]
# directory chain from 40/3
ents = []
t, s = 40, 3
seen = set()
while t and (t, s) not in seen:
    seen.add((t, s))
    b = blk(t, s)
    for i in range(8):
        e = b[i * 32:i * 32 + 32]
        if e[2] & 0x07 in (1, 2, 3) and e[3]:   # SEQ, PRG, USR with a start track
            ents.append((e[3], e[4]))
    t, s = b[0], b[1]
hist = {}
long_in_chain = []
n_files = 0
for (ft, fs) in ents:
    n_files += 1
    prev = 40            # the open reads the directory first
    t, s = ft, fs
    k = 0
    seen2 = set()
    while t and (t, s) not in seen2 and k < 4000:
        seen2.add((t, s))
        d = abs(t - prev)
        if d:
            hist[d] = hist.get(d, 0) + 1
            if d >= lim:
                long_in_chain.append((n_files, k, prev, t))
        prev = t
        b = blk(t, s)
        t, s = b[0], b[1]
        k += 1
tot = sum(hist.values())
print(f'{sys.argv[1].split("/")[-1]}: {n_files} files, {tot} head moves in a sequential read of all files')
for lo, hi in ((1, 1), (2, 9), (10, 39), (40, 59), (60, 65), (66, 79)):
    print(f'  moves of {lo:2d}..{hi:2d} cylinders: {sum(v for d, v in hist.items() if lo <= d <= hi)}')
print(f'  moves of >= {lim} cylinders (file number, block index, from track, to track):', long_in_chain[:40])
