#!/usr/bin/env python3
"""Event-for-event comparison of the RTL decoder (tb_flux_dec.vhd log) with
the model (decmodel.py) on the same edge file (mkflux.py output).

Every event type is compared on its own as a sequence: the payloads must be
identical (ID: C H R N CRC verdict and estimate; C: estimate; DAM: unarmed;
DEND: CRC verdict; GE: gap length; TOL), and the cycle of each RTL event
minus that of its model event must be the same constant for all events of
the type (the pipeline latency), within +/-2 cycles.

Usage: rtlcmp.py <edges.txt> <events.txt> on|off
  on  = model with the production tolerance (tb_flux_dec G_TOL_OFF = 0)
  off = model without it (G_TOL_OFF = 1, or the decoder before the tolerance)
Exit status 0 when everything agrees."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from decmodel import Model, TOL_PROD, edge_gaps

TYPES = ('ID', 'FE', 'DAM', 'DEND', 'C', 'REJ', 'T', 'GE', 'TOL')

def model_events(edge_path, tol):
    edges = []
    for ln in open(edge_path):
        ln = ln.strip()
        if not ln:
            continue
        if ln[0] == 'R':
            raise SystemExit('reset lines are not supported')
        edges.append(int(ln))
    gaps = edge_gaps(edges)
    runts = len(edges) - 1 - len(gaps)
    m = Model(tol)
    for g, c in gaps:
        m.gap(g, c)
    out = {k: [] for k in TYPES}
    for e in m.events:
        k = e[0]
        if k == 'ID': out[k].append((e[1], (e[2], e[3], e[4], e[5], int(e[6]), e[7])))
        elif k == 'DAM': out[k].append((e[1], (int(e[2]),)))
        elif k == 'DEND': out[k].append((e[1], (int(e[2]),)))
        elif k == 'C': out[k].append((e[1], (e[2],)))
        elif k == 'GE': out[k].append((e[1], (e[2],)))
        elif k in ('FE', 'REJ', 'T', 'TOL'): out[k].append((e[1], ()))
    return out, runts

def rtl_events(path):
    out = {k: [] for k in TYPES}
    runts = 0
    bit = lambda x: 1 if x.endswith("'1'") else 0
    for ln in open(path):
        p = ln.split()
        if not p: continue
        k, c = p[0], int(p[1])
        if k == 'ID':
            out[k].append((c, (int(p[2]), int(p[3]), int(p[4]), int(p[5]), bit(p[6]), int(p[7].split('=')[1]))))
        elif k == 'DAM': out[k].append((c, (bit(p[2]),)))
        elif k == 'DEND': out[k].append((c, (bit(p[2]),)))
        elif k == 'C': out[k].append((c, (int(p[2].split('=')[1]),)))
        elif k == 'GE': out[k].append((c, (int(p[2].split('=')[1]),)))
        elif k == 'RUNT': runts += 1
        elif k in out: out[k].append((c, ()))
    return out, runts

def main():
    edges, evp, mode = sys.argv[1], sys.argv[2], sys.argv[3]
    tol = TOL_PROD if mode == 'on' else None
    me, mr = model_events(edges, tol)
    re_, rr = rtl_events(evp)
    ok = True
    summary = []
    for k in TYPES:
        a, b = me[k], re_[k]
        if len(a) != len(b):
            ok = False
            summary.append('%s: model %d, RTL %d  MISMATCH' % (k, len(a), len(b)))
            n = min(len(a), len(b))
            for i in range(n):
                if a[i][1] != b[i][1] or abs((b[i][0] - a[i][0]) - (b[0][0] - a[0][0])) > 2:
                    summary.append('   first difference at #%d: model %s, RTL %s' % (i, a[i], b[i]))
                    break
            continue
        if not a:
            summary.append('%s: 0' % k); continue
        d = [y[0] - x[0] for x, y in zip(a, b)]
        bad = [i for i in range(len(a)) if a[i][1] != b[i][1]]
        spread = max(d) - min(d)
        if bad or spread > 4:
            ok = False
            i = bad[0] if bad else d.index(max(d))
            summary.append('%s: %d, payload differences %d, latency %d..%d  MISMATCH (first: model %s, RTL %s)' % (
                k, len(a), len(bad), min(d), max(d), a[i], b[i]))
        else:
            summary.append('%s: %d, identical, latency %d..%d cycles' % (k, len(a), min(d), max(d)))
    summary.append('RUNT: model %d, RTL %d%s' % (mr, rr, '' if mr == rr else '  MISMATCH'))
    if mr != rr: ok = False
    print('; '.join(summary))
    print('RESULT: %s' % ('AGREE' if ok else 'DIFFER'))
    sys.exit(0 if ok else 1)

if __name__ == '__main__':
    main()
