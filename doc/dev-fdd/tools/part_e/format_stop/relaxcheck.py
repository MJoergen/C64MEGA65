#!/usr/bin/env python3
"""Feasibility check of one fix idea on the decoder model (NOT the RTL):
accept an address mark after TWO qualified A1 candidates at exact spacing
(sync_cnt = 2) when the byte that follows is FE/FB/F8, i.e. one A1 of the
train was lost. Counts, per capture, how many extra ID/DAM marks the relaxed
rule recognizes, how many extra IDs have a good CRC, and how many of them
are new CRC-bad IDs (would-be false syncs).
Usage: relaxcheck.py <scp>... [--cyl a-b]"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs
import decmodel
from decmodel import Model, run_side

class Relaxed(Model):
    def byte(self, v, cyc):
        if self.sync_cnt == 2 and v in (0xFE, 0xFB, 0xF8):
            self.events.append(('RELAX', cyc, v))
            self.sync_cnt = 3
        Model.byte(self, v, cyc)

def count(data, hdr, offs, cyl, head, cls):
    decmodel.Model = cls
    res = run_side(data, hdr, offs, cyl, head)
    decmodel.Model = Model
    ev = res[0][3]
    ids_ok = sum(1 for e in ev if e[0] == 'ID' and e[6])
    ids_bad = sum(1 for e in ev if e[0] == 'ID' and not e[6])
    dend_ok = sum(1 for e in ev if e[0] == 'DEND' and e[2])
    relax = sum(1 for e in ev if e[0] == 'RELAX')
    return ids_ok, ids_bad, dend_ok, relax

args = sys.argv[1:]
cr = (0, 79)
if '--cyl' in args:
    i = args.index('--cyl'); a, b = args[i + 1].split('-'); cr = (int(a), int(b)); del args[i:i + 2]
for path in args:
    data, hdr, offs = read_scp(path)
    tot = [0, 0, 0, 0, 0, 0, 0]
    for cyl in range(cr[0], cr[1] + 1):
        for head in (0, 1):
            if not offs[cyl * 2 + head]: continue
            a = count(data, hdr, offs, cyl, head, Model)
            b = count(data, hdr, offs, cyl, head, Relaxed)
            tot[0] += a[0]; tot[1] += b[0]; tot[2] += a[1]; tot[3] += b[1]
            tot[4] += a[2]; tot[5] += b[2]; tot[6] += b[3]
            if b[0] != a[0] or b[1] != a[1] or b[2] != a[2]:
                print('   cyl %d head %d: IDs ok %d -> %d, IDs bad %d -> %d, data ok %d -> %d, relaxed marks %d' % (
                    cyl, head, a[0], b[0], a[1], b[1], a[2], b[2], b[3]))
    print('%s: rev 0, IDs ok %d -> %d, IDs CRC-bad %d -> %d, data fields ok %d -> %d, relaxed marks %d' % (
        os.path.basename(path)[:30], tot[0], tot[1], tot[2], tot[3], tot[4], tot[5], tot[6]))
