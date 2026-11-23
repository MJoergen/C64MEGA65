#!/usr/bin/env python3
"""The tolerance variants for a weak sync byte against the decoder without
tolerance, on whole Greaseweazle captures (issue #257, part E, change 3).

For every track side (all revolutions as one stream, as the drive sees them):
  * the fields the model of the production decoder (decmodel.py) decodes
    without tolerance and with each variant (A: the production rule TOL_PROD;
    A_wide: A that also re-anchors on a pair, has no lower bound of the zero
    run window and reports a pair ID with a bad CRC; B70: variant B with the
    phase factor 0.7 within 25 cycles of a midpoint): IDs (C, H, R, N, CRC verdict) and
    data fields (CRC verdict, deleted flag, CRC-32 of the payload), each at the
    clock cycle of its event; fields gained, fields lost or changed;
  * every gained field checked against an independent decoder, the PLL of
    pllcheck.py (period adjust 5 %, phase adjust 60, 45 or 30 %; the last two
    run on the sides where a variant used its tolerance or saw a train of
    two): same content within 200 us, found by the PLL after three sync bytes;
  * how often each variant used its tolerance;
  * variant A: every train of two followed by a byte, with the byte, the
    parser state, the arm and the preamble gate, and whether the PLL sees a
    real three-byte train there (the near misses);
  * the margins of every real sync train (a run of at least 16 shorts, then
    15 gaps of 49 half cells, each within 0.75 half cells of its nominal
    length) against the decoder's midpoints, with the decoder's own
    estimate, per byte of the train;
  * rewritten sectors: a data field written in the same pass as its ID
    (Write Track) starts a whole number of bytes after the ID, and every byte
    between the ID's CRC and the data field's sync bytes is a clean MFM 4E or
    00 at the ID's byte framing; a data field that a Write Sector rewrote has
    a splice there and fails the test. The histogram of the distance from the
    first sync byte of an ID to that of its data field (PLL half cells: 704
    for the 1581 ROM's format, 720 for an 11-sector format) is printed too.

Usage: tolsurvey.py <out.txt> <scp> [--cyl a-b] [--quick]
--quick runs the production variant only (no B)."""
import sys, os, zlib, statistics
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, crc16
import decmodel
from decmodel import gaps_from_flux, run_model, side_flux, TOL_PROD, SYNC_LAT, SPACING

VARIANTS = [
    ('A', TOL_PROD),
    ('A_wide', {'v': 'A', 'reanchor2': True, 'dam2_max': SYNC_LAT + SPACING, 'dam2_min': -1}),
    ('B70', {'v': 'B', 'c': 0.7, 'w': 400}),
]
PLL_PHASES = (0.60, 0.45, 0.30)
SYNC = '0100010010001001'
EXP = [3, 4, 3, 4, 3, 2, 4, 3, 4, 3, 2, 4, 3, 4, 3]

def fields(m):
    out = []
    for e in m.events:
        if e[0] == 'ID':
            out.append(('ID', e[1], (e[2], e[3], e[4], e[5], e[6])))
        elif e[0] == 'DEND':
            out.append(('DATA', e[1], (e[2], e[3], e[4])))
    return out

def pll_bits(flux_ns, ph=0.60, pe=0.05):
    clock = 2000.0; centre = 2000.0; cmin, cmax = 1800.0, 2200.0
    ticks = 0.0; bits = []; times = []; t = 0.0
    for x in flux_ns:
        t += x
        ticks += x
        if ticks < clock / 2:
            continue
        zeros = 0
        while True:
            ticks -= clock
            if ticks >= clock / 2:
                zeros += 1; bits.append('0'); times.append(t)
            else:
                break
        bits.append('1'); times.append(t)
        if zeros <= 3:
            clock += ticks * pe
        else:
            clock += (centre - clock) * pe
        clock = min(max(clock, cmin), cmax)
        ticks = ticks * (1 - ph)
    return ''.join(bits), times

def pll_records(s, times):
    """records found after three sync bytes: (kind, bitpos, time_ns_end, content)"""
    def byte(q):
        w = s[q:q + 16]
        if len(w) < 16: return None
        v = 0
        for k in range(8): v = (v << 1) | (w[2 * k + 1] == '1')
        return v
    recs = []; trains = []
    i = 0
    S3 = SYNC * 3
    while True:
        j = s.find(S3, i)
        if j < 0: break
        trains.append(j)
        p = j + 48
        m = byte(p)
        if m == 0xFE:
            by = [byte(p + 16 * k) for k in range(1, 7)]
            if None in by: break
            ok = crc16([0xA1] * 3 + [0xFE] + by) == 0
            recs.append(('ID', j, times[min(p + 16 * 7, len(times) - 1)], (by[0], by[1], by[2], by[3], ok)))
            i = p + 16
        elif m in (0xFB, 0xF8):
            by = [byte(p + 16 * k) for k in range(1, 515)]
            if None in by: break
            ok = crc16([0xA1] * 3 + [m] + by) == 0
            recs.append(('DATA', j, times[min(p + 16 * 515, len(times) - 1)], (ok, m == 0xF8, zlib.crc32(bytes(by[:512])))))
            i = p + 16
        else:
            i = p
    return recs, trains

def mfm_word(b, prev):
    w = ''
    for i in range(7, -1, -1):
        d = (b >> i) & 1
        w += ('1' if not (prev or d) else '0') + ('1' if d else '0')
        prev = d
    return w, prev

def one_pass(s, j_id, j_dam):
    """True when the data field at j_dam was written in the same pass as the
    ID at j_id: a whole number of bytes after it, and every byte between the
    ID's CRC and the data field's sync is a clean MFM 4E or 00."""
    d = j_dam - j_id
    if d % 16:
        return False
    q = j_id + 16 * 10
    prev = int(s[q - 1])
    while q < j_dam:
        w = s[q:q + 16]
        ok = False
        for b in (0x4E, 0x00):
            mw, np = mfm_word(b, prev)
            if w == mw:
                ok = True; prev = np; break
        if not ok:
            return False
        q += 16
    return True

def train_margins(trace):
    """margins (half cells) of every real train against the decoder midpoints,
    per byte: list of (cycle, [m1, m2, m3])"""
    out = []
    n = len(trace)
    run = 0
    for i in range(n):
        g = trace[i][0]
        if 160 <= g <= 240:
            run += 1; continue
        if run >= 16 and i + 15 <= n:
            h = statistics.median(t[0] for t in trace[i - 16:i]) / 2.0
            seg = trace[i:i + 15]
            if abs(sum(t[0] for t in seg) / h - 49) <= 1.5 and \
               all(abs(t[0] / h - ex) <= 0.75 for t, ex in zip(seg, EXP)):
                mb = []
                for b in range(3):
                    mm = 9.0
                    for k in range(5 * b, 5 * b + 5):
                        g, cyc, est = seg[k]
                        y = g * 16.0 / est
                        ex = EXP[k]
                        if ex == 2: v = 2.5 - y
                        elif ex == 3: v = min(y - 2.5, 3.5 - y)
                        else: v = y - 3.5
                        mm = min(mm, v)
                    mb.append(mm)
                out.append((trace[i][1], mb))
        run = 0
    return out

def hd(a, b):
    return bin(a ^ b).count('1')

def main():
    a = sys.argv[1:]
    out_path, path = a[0], a[1]
    cr = (0, 81)
    if '--cyl' in a:
        x, y = a[a.index('--cyl') + 1].split('-'); cr = (int(x), int(y))
    variants = VARIANTS[:1] if '--quick' in a else VARIANTS
    data, hdr, offs = read_scp(path)
    tick = hdr['tick_ns']
    fo = open(out_path, 'w')
    name = os.path.basename(path)
    fo.write('capture %s, %d revolutions per side\n' % (name, hdr['revs']))
    keys = ['base'] + [v[0] for v in variants]
    tot = {k: [0, 0, 0, 0] for k in keys}        # IDok IDbad DATAok DATAbad
    gained = {k: 0 for k in keys}; lost = {k: 0 for k in keys}
    unconf = {k: 0 for k in keys}; uses = {k: 0 for k in keys}
    conf3 = {k: 0 for k in keys}
    p2 = {}                                     # near-miss classes of variant A
    p2_detail = []
    dist_hist = {}
    pos_lost = [0, 0, 0]; pos_m05 = [0, 0, 0]; pos_m10 = [0, 0, 0]; ntrains = 0
    worst = []
    nsides = 0
    spliced = set(); onepass = set(); n1 = 0; n2 = 0
    btally = {'C': 0, 'T': 0, 'FE': 0, 'DAM': 0, 'UNARMED': 0, 'REJ': 0, 'GE': 0}
    for cyl in range(cr[0], cr[1] + 1):
        for head in (0, 1):
            flux, idx = side_flux(data, hdr, offs, cyl, head)
            if flux is None:
                continue
            nsides += 1
            gaps = gaps_from_flux(flux, tick)
            base = run_model(gaps, None, trace=True)
            bf = fields(base)
            bset = set(bf)
            for f in bf:
                k = (0 if f[2][4] else 1) if f[0] == 'ID' else (2 if f[2][0] else 3)
                tot['base'][k] += 1
            # PLL: the first phase setting always (splice census), the others
            # only where a field or a pair needs a confirmation (pll_more)
            pcyc = []; ptrain_cyc = []
            fns = [v * tick for v in flux]
            def pll_more():
                for ph in PLL_PHASES[1:]:
                    s2, times2 = pll_bits(fns, ph)
                    precs2, ptrains2 = pll_records(s2, times2)
                    pcyc.extend((r[0], r[2] / 20.0, r[3], ph) for r in precs2)
                    ptrain_cyc.extend(times2[j + 47] / 20.0 for j in ptrains2)
            for ph in PLL_PHASES[:1]:
                s, times = pll_bits(fns, ph)
                precs, ptrains = pll_records(s, times)
                pcyc += [(r[0], r[2] / 20.0, r[3], ph) for r in precs]
                ptrain_cyc += [times[j + 47] / 20.0 for j in ptrains]
                # splice census: ID -> following DATA distance in half cells
                for k2 in range(len(precs) - 1):
                    if precs[k2][0] == 'ID' and precs[k2 + 1][0] == 'DATA':
                        d = precs[k2 + 1][1] - precs[k2][1]
                        if d < 2000:
                            dist_hist[d] = dist_hist.get(d, 0) + 1
                            key = (cyl, head, precs[k2][3][2])
                            if one_pass(s, precs[k2][1], precs[k2 + 1][1]):
                                onepass.add(key); n1 += 1
                            else:
                                spliced.add(key); n2 += 1
            for e in base.events:
                if e[0] in btally: btally[e[0]] += 1
                if e[0] == 'DAM' and e[2]: btally['UNARMED'] += 1
            # margins per byte of the real trains
            for cyc, mb in train_margins(base.trace):
                ntrains += 1
                j = mb.index(min(mb))
                if mb[j] < 0: pos_lost[j] += 1
                if mb[j] < 0.05: pos_m05[j] += 1
                if mb[j] < 0.10: pos_m10[j] += 1
                worst.append((mb[j], j + 1, cyl, head, cyc))
            lines = []
            more_done = False
            for vn, tol in variants:
                m = run_model(gaps, tol)
                if not more_done and any(e[0] in ('P2', 'TOL', 'TOLB') for e in m.events):
                    pll_more(); more_done = True
                vf = fields(m)
                vset = set(vf)
                for f in vf:
                    k = (0 if f[2][4] else 1) if f[0] == 'ID' else (2 if f[2][0] else 3)
                    tot[vn][k] += 1
                g_ = [f for f in vf if f not in bset]
                l_ = [f for f in bf if f not in vset]
                gained[vn] += len(g_); lost[vn] += len(l_)
                u = sum(1 for e in m.events if e[0] in ('TOL', 'TOLB'))
                uses[vn] += u
                for f in g_:
                    phs = sorted(set(p[3] for p in pcyc if p[0] == f[0] and p[2] == f[2] and abs(p[1] - f[1]) < 10000))
                    if phs: conf3[vn] += 1
                    else: unconf[vn] += 1
                    lines.append('   %-7s cyl %2d head %d GAINED %s %s at %.3f ms of the stream, PLL %s' % (
                        vn, cyl, head, f[0], f[2], f[1] / 50000.0,
                        ('confirms (phase adjust %s)' % '/'.join('%.2f' % x for x in phs)) if phs else 'DOES NOT CONFIRM'))
                for f in l_:
                    lines.append('   %-7s cyl %2d head %d LOST %s %s at %.3f ms' % (vn, cyl, head, f[0], f[2], f[1] / 50000.0))
                if tol['v'] == 'A':
                    for e in m.events:
                        if e[0] != 'P2': continue
                        cyc, v, st, armed, pre2, fage = e[1:]
                        real = any(abs(c - cyc) < 2500 for c in ptrain_cyc)
                        mk = min(hd(v, x) for x in (0xFE, 0xFB, 0xF8))
                        key = (vn, 'mark' if mk == 0 else 'hd%d' % min(mk, 3), st, 'pll-train' if real else 'no-pll-train')
                        p2[key] = p2.get(key, 0) + 1
                        if mk <= 1 and not real:
                            p2_detail.append('   %-7s cyl %2d head %d %.3f ms: pair then %02X (distance %d to a mark) state %s armed %d preamble2 %d first-candidate run age %d' % (
                                vn, cyl, head, cyc / 50000.0, v, mk, st, armed, pre2, fage))
                        elif mk == 0:
                            p2_detail.append('   %-7s cyl %2d head %d %.3f ms: pair then %02X state %s armed %d preamble2 %d run age %d, PLL train %s' % (
                                vn, cyl, head, cyc / 50000.0, v, st, armed, pre2, fage, 'yes' if real else 'no'))
            for ln in lines:
                fo.write(ln + '\n')
            fo.flush()
    fo.write('\nsides %d\n' % nsides)
    fo.write('%-8s %8s %8s %8s %8s %7s %7s %7s %7s %7s\n' % ('variant', 'IDok', 'IDbad', 'DATAok', 'DATAbad', 'gained', 'lost', 'PLLok', 'PLLno', 'uses'))
    for k in keys:
        fo.write('%-8s %8d %8d %8d %8d %7d %7d %7d %7d %7d\n' % ((k,) + tuple(tot[k]) + (gained[k], lost[k], conf3[k], unconf[k], uses[k])))
    fo.write('\ntrains of two (variant, following byte, parser state, PLL sees a three-byte train there): count\n')
    for key in sorted(p2):
        fo.write('   %s: %d\n' % (' '.join(key), p2[key]))
    fo.write('details (marks, and non-train pairs one bit from a mark):\n')
    for ln in p2_detail:
        fo.write(ln + '\n')
    fo.write('\nreal sync trains %d; weakest byte position (1, 2, 3): margin < 0: %s, < 0.05: %s, < 0.10: %s\n' % (
        ntrains, pos_lost, pos_m05, pos_m10))
    worst.sort()
    fo.write('weakest 12 trains (margin in half cells, byte, cyl, head, ms of the stream): %s\n' % (
        ', '.join('%+.3f b%d c%d h%d %.2f' % (w[0], w[1], w[2], w[3], w[4] / 50000.0) for w in worst[:12])))
    fo.write('\nID-to-data distance in PLL half cells: %s\n' % (
        ', '.join('%d:%d' % (d, dist_hist[d]) for d in sorted(dist_hist))))
    fo.write('data fields written in the pass of their ID: %d, rewritten (a splice between ID and data): %d (all revolutions)\n' % (n1, n2))
    fo.write('distinct sectors (cylinder, side, R): written in one pass %d, rewritten %d, both verdicts in different revolutions %d\n' % (
        len(onepass - spliced), len(spliced - onepass), len(spliced & onepass)))
    fo.write('\ndecoder without tolerance, all sides and revolutions: candidates %d, trains %d, FE %d, DAM %d (unarmed %d), trains followed by another byte %d, span rejects %d, gap errors %d\n' % (
        btally['C'], btally['T'], btally['FE'], btally['DAM'], btally['UNARMED'], btally['T'] - btally['FE'] - btally['DAM'], btally['REJ'], btally['GE']))
    fo.close()

if __name__ == '__main__':
    main()
