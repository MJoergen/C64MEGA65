#!/usr/bin/env python3
"""Summarize tb_flux_dec events per revolution.
Usage: evsum.py <events.txt> <rev_cycles> [--list]
rev_cycles: cycles per revolution (index period), offset 100."""
import sys
path, per = sys.argv[1], float(sys.argv[2])
lst = '--list' in sys.argv
ev = []
for ln in open(path):
    p = ln.split()
    ev.append(p)
from collections import defaultdict
cnt = defaultdict(lambda: defaultdict(int))
ids = defaultdict(list)
for p in ev:
    k = p[0]; c = int(p[1]); r = int((c - 100) // per); ms = ((c - 100) % per) / 50000.0
    key = k
    if k == 'DAM' and p[2] == "unarmed='1'":
        key = 'DAM_UNARMED'
        cnt[r]['DAM'] += 1
    cnt[r][key] += 1
    if k == 'ID':
        ids[r].append('%d%s' % (int(p[4]), '' if p[6] == "'1'" else '!'))
    if lst and k not in ('C',):
        print('rev %d %8.3f ms %s' % (r, ms, ' '.join(p[2:]) if k != 'ID' else ' '.join([k] + p[2:])) if k != 'ID' else 'rev %d %8.3f ms ID C=%s H=%s R=%s N=%s ok=%s %s' % (r, ms, p[2], p[3], p[4], p[5], p[6], p[7]))
for r in sorted(cnt):
    d = cnt[r]
    print('rev %d: cand=%d train=%d FE=%d ID=%d DAM=%d unarmed=%d DEND=%d GE=%d RUNT=%d REJ=%d  IDs: %s' % (
        r, d['C'], d['T'], d['FE'], d['ID'], d['DAM'], d['DAM_UNARMED'], d['DEND'], d['GE'], d['RUNT'], d['REJ'], ' '.join(ids[r])))
