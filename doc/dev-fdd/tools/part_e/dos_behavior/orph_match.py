#!/usr/bin/env python3
# For each file whose last block holds 254 data bytes: is there an orphan block
# right after it in allocation order (same track, sector + 1)? Lists the rest.
# Usage: python3 -I orph_match.py image.d81 ...
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from d81orph import analyze
for p in sys.argv[1:]:
    img, files, free, orphans, fbu = analyze(p)
    files = [f for f in files if f['typ'] & 7 != 0]
    full = [f for f in files if f['fill'] == 254]
    orph = set(orphans); matched = {}
    unmatched_files = []
    for f in full:
        t, s = f['chain'][-1]
        if (t, s + 1) in orph: matched[(t, s + 1)] = f
        else: unmatched_files.append(f)
    rest = sorted(orph - set(matched))
    fills = {}
    for f in files:
        fills[f['fill'] == 254] = fills.get(f['fill'] == 254, 0) + 1
    print(os.path.basename(p), 'files', len(files), 'full-last', len(full), 'orphans', len(orphans),
          'matched t,s+1', len(matched), 'unmatched full files', [(x['chain'][-1]) for x in unmatched_files],
          'unmatched orphans', rest)
