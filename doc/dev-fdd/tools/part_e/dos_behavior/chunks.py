#!/usr/bin/env python3
# Structure only: number of 1016-byte chunks DraCopy's file copy needs per file,
# and the number of track sides each file's chain touches.
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from d81orph import analyze
img, files, free, orph, fbu = analyze(sys.argv[1])
files = [f for f in files if f['typ'] & 7 != 0]
ch = sum(max(1, math.ceil(f['nbytes'] / 1016)) for f in files)
sides = sum(len({(t, s // 20) for t, s in f['chain']}) for f in files)
byt = sum(f['nbytes'] for f in files)
print('files', len(files), 'bytes', byt, 'chunks of 1016', ch, 'track sides touched (sum over files)', sides)
