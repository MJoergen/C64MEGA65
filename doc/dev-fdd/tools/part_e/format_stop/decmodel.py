#!/usr/bin/env python3
"""Python model of the production read front end (physical_1581_mfm_gaps,
_quantise, _gaps_to_bits, _bits_to_bytes and the field FSM of
physical_1581_mfm_decoder), gap-event level, for surveys of SCP captures.
Validated against the RTL (tb_flux_dec.vhd) event for event.

Model(tol=None) is the decoder with its tolerance switched off (tol_off_i
high), which is the decoder of the commits before the tolerance. Model(tol=...)
adds one of the tolerance variants that were evaluated for a weak sync byte
(tolsurvey.py compares them on whole captures):

  tol = {'v': 'A', ...}   accept a mark after a train of two candidates at the
                          exact spacing (the production rule, see TOL_PROD)
      'reanchor2': True   a train of two followed by FE also re-anchors an
                          open field (production: False)
      'dam2_max': k       a DAM on a train of two needs the zero run to have
                          ended at most k gaps before the first candidate of
                          the pair (production: SYNC_LAT + SPACING)
      'dam2_min': k       ... and more than k gaps before it (production:
                          SYNC_LAT; a pair right after the zero run is the
                          weak third byte of a train, never a mark)
      'quiet_bad': True   an ID opened on a train of two whose CRC fails is
                          not reported, and neither the arm of the data mark
                          nor N of the last ID changes (production: True)
  tol = {'v': 'B', 'c': f, 'w': q}
                          decide a gap whose length lies within q/16 cycles
                          of a midpoint by its phase: the gap plus f times the
                          residual of the previous gap against its class

Usage:
  decmodel.py survey <scp> [--scale S] [--cyl a-b]   per side: missing IDs per rev
  decmodel.py side <scp> <cyl> <head> [--scale S] [--list] [--tol]
"""
import sys, os, zlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs, crc16

EST_NOM = 1600; EST_MIN = 1440; EST_MAX = 1760; STEP = 2
SYNC_RUN = 16; SYNC_LAT = 6; SPACING = 5; A1_CELLS = 14
SYNC_PAT = (2, 1, 2, 1)

# the rule as built in physical_1581_mfm_decoder.vhd
TOL_PROD = {'v': 'A', 'reanchor2': False, 'dam2_max': SYNC_LAT + SPACING,
            'dam2_min': SYNC_LAT, 'quiet_bad': True}

def edge_gaps(edges):
    """edge cycles -> (gap, edge cycle) as physical_1581_mfm_gaps measures
    them: its counter restarts at 0 in the cycle of an edge, so a gap is the
    distance of two edges minus one (the 2-stage edge pipeline adds a
    constant delay that cancels); a gap below C_GAP_GLITCH = 16 is a runt and
    merges into the following one."""
    last = None
    out = []
    for c in edges:
        if last is None:
            last = c
            continue
        g = c - last - 1
        if g < 16:            # runt: merge into the following gap
            continue
        out.append((g, c))
        last = c
    return out

def gaps_from_flux(flux_ticks, tick_ns, scale=1.0):
    """flux intervals -> (gap, edge cycle) in 50 MHz cycles, edges rounded
    to cycles as mkflux.py writes them"""
    t = 0.0
    edges = []
    for f in flux_ticks:
        t += f * tick_ns * scale
        edges.append(int(round(t / 20.0)))
    return edge_gaps(edges)

class Model:
    def __init__(self, tol=None, trace=False):
        self.tol = tol
        self.tv = tol['v'] if tol else None
        self.do_trace = trace
        self.reset()
    def reset(self):
        self.est = EST_NOM
        self.recent = []
        self.last_bit = 0
        self.short_run = 0; self.run_age = 15; self.sync_gap_age = 15
        self.a1g = [0, 0, 0, 0]
        self.sync_cnt = 0
        self.state = 'IDLE'
        self.data_armed = 0; self.preamble_ok = 0; self.preamble2_ok = 0
        self.first_age = 15
        self.bits = []      # partial byte bits
        self.bitcount = 0
        self.field = []
        self.last_n = 2
        self.events = []
        self.trace = []
        self.resid = 0      # variant B: residual of the previous gap (Q4)
        self.tol_id = 0     # variant A: the open ID was accepted on a train of two
        self.ngap = 0
    def field_active(self):
        return self.state != 'IDLE' or self.sync_cnt == 3

    def gap(self, g, cyc):
        # ---------------- quantiser
        est = self.est
        gq = g * 16
        c2, c3, c4 = 2 * est, 3 * est, 4 * est
        half = est >> 1
        if gq < c2 + half: n, center = 2, c2
        elif gq < c3 + half: n, center = 3, c3
        else: n, center = 4, c4
        e = gq - center
        tol = est >> 1
        if self.do_trace:
            self.trace.append((g, cyc, est))
        self.ngap += 1
        if abs(e) <= tol:
            if self.tv == 'B':
                n, center, e = self.phase_decide(gq, n, center, e, est, cyc)
            cls = n
            if e > 0: est += STEP
            elif e < 0: est -= STEP
            est = min(max(est, EST_MIN), EST_MAX)
            self.est = est
        else:
            cls = 0      # invalid
            self.est = EST_NOM
            self.resid = 0
        est_after = self.est
        # ---------------- decoder bookkeeping on q_valid
        self.a1g = [g] + self.a1g[:3]
        if self.sync_gap_age < 15: self.sync_gap_age += 1
        if cls == 0:
            self.events.append(('GE', cyc, g))
            self.state = 'IDLE'; self.sync_cnt = 0; self.short_run = 0
            self.run_age = 15; self.sync_gap_age = 15; self.preamble_ok = 0
            self.preamble2_ok = 0; self.tol_id = 0
            self.recent = []; self.bitcount = 0
            return
        if cls == 2:
            if self.short_run >= SYNC_RUN - 1: self.run_age = 0
            elif self.run_age < 15: self.run_age += 1
            if self.short_run < 255: self.short_run += 1
        else:
            self.short_run = 0
            if self.run_age < 15: self.run_age += 1
        # ---------------- gaps_to_bits
        self.recent = (self.recent + [cls - 2 + 0])[-4:]   # store class codes 0/1/2
        rc = tuple(x for x in self.recent)
        if rc == (2, 1, 2, 1):
            self.sync(cyc, est_after)
            self.last_bit = 1
            return
        lb = self.last_bit
        c = cls - 2
        if c == 0: q = [lb]
        elif c == 1: q = [1] if lb == 0 else [0, 0]
        else: q = [0, 1]
        for b in q:
            self.last_bit = b
            self.bit(b, cyc)

    def phase_decide(self, gq, n, center, e, est, cyc):
        """variant B: a gap within w of a midpoint takes the class of the gap
        corrected by c times the residual of the previous gap."""
        c = self.tol['c']; w = self.tol['w']
        corr = gq + int(round(c * self.resid))
        half = est >> 1
        mids = ((2, 3, 2 * est + half), (3, 4, 3 * est + half))
        nn = n
        for lo, hi, mid in mids:
            if abs(gq - mid) <= w:
                nn = lo if corr < mid else hi
        if nn != n:
            self.events.append(('TOLB', cyc, gq - (2 * est + half if min(n, nn) == 2 else 3 * est + half), n, nn))
            n = nn; center = n * est; e = gq - center
        r = corr - center
        lim = est >> 1
        self.resid = max(-lim, min(lim, r))
        return n, center, e

    def sync(self, cyc, est):
        self.events.append(('C', cyc, est))
        # b2b: sync resets the bit counter
        self.bitcount = 0; self.bits = []
        actual = sum(self.a1g)
        expected = (est * A1_CELLS + 8) // 16
        tolv = (est + 32 - 1) // 32
        if abs(actual - expected) > tolv:
            self.sync_cnt = 0; self.sync_gap_age = 15; self.preamble_ok = 0
            self.preamble2_ok = 0
            self.events.append(('REJ', cyc, actual - expected, tolv))
        elif self.sync_cnt == 0:
            self.start_train()
        elif self.sync_gap_age == SPACING:
            if self.sync_cnt < 3:
                self.sync_cnt += 1
                if self.sync_cnt == 3:
                    self.events.append(('T', cyc))
            self.sync_gap_age = 0
        else:
            self.start_train()

    def start_train(self):
        self.sync_cnt = 1; self.sync_gap_age = 0
        self.preamble_ok = 1 if self.run_age <= SYNC_LAT else 0
        self.first_age = self.run_age
        if self.tv == 'A':
            lo = self.tol.get('dam2_min', -1)
            hi = self.tol.get('dam2_max', SYNC_LAT + SPACING)
            self.preamble2_ok = 1 if lo < self.run_age <= hi else 0

    def bit(self, b, cyc):
        self.bits.append(b)
        self.bitcount += 1
        if self.bitcount == 8:
            v = 0
            for x in self.bits: v = (v << 1) | x
            self.bits = []; self.bitcount = 0
            self.byte(v, cyc)

    def byte(self, v, cyc):
        st = self.state
        if self.tv == 'A' and self.sync_cnt == 2:
            # a train of two: record every byte that follows one, for the
            # margin analysis, then decide whether it is a mark
            self.events.append(('P2', cyc, v, st, self.data_armed, self.preamble2_ok, self.first_age))
            if v in (0xFE, 0xFB, 0xF8):
                if st == 'IDLE' or (v == 0xFE and self.tol.get('reanchor2')):
                    if v == 0xFE:
                        self.events.append(('TOL', cyc, v, st))
                        self.state = 'ID'; self.field = [0xA1, 0xA1, 0xA1, 0xFE]; self.sync_cnt = 0
                        if self.tol.get('quiet_bad'):
                            self.tol_id = 1
                        else:
                            self.data_armed = 0
                        self.preamble_ok = 0; self.preamble2_ok = 0
                        return
                    if self.data_armed and self.preamble2_ok:
                        self.events.append(('TOL', cyc, v, st))
                        self.state = 'DATA'; self.field = [0xA1, 0xA1, 0xA1, v]
                        self.dlen = {0: 128, 1: 256, 2: 512, 3: 1024, 4: 2048}.get(self.last_n, 512)
                        self.data_armed = 0
                        self.events.append(('DSTART', cyc))
                        self.preamble_ok = 0; self.preamble2_ok = 0
                        self.sync_cnt = 0
                        return
                    self.events.append(('TOLX', cyc, v, st))
        if self.sync_cnt == 3 and v == 0xFE:
            self.events.append(('FE', cyc))
        elif self.sync_cnt == 3 and v in (0xFB, 0xF8):
            unarmed = (st != 'IDLE' or self.data_armed == 0 or self.preamble_ok == 0)
            self.events.append(('DAM', cyc, unarmed))
        if self.sync_cnt == 3 and v == 0xFE and st != 'IDLE':
            self.state = 'ID'; self.field = [0xA1, 0xA1, 0xA1, 0xFE]; self.sync_cnt = 0
            self.data_armed = 0; self.preamble_ok = 0; self.preamble2_ok = 0
            self.tol_id = 0
            return
        if st == 'IDLE':
            if self.sync_cnt == 3:
                if v == 0xFE:
                    self.state = 'ID'; self.field = [0xA1, 0xA1, 0xA1, 0xFE]
                    self.data_armed = 0; self.preamble_ok = 0; self.preamble2_ok = 0
                    self.tol_id = 0
                elif v in (0xFB, 0xF8):
                    if self.data_armed and self.preamble_ok:
                        self.state = 'DATA'; self.field = [0xA1, 0xA1, 0xA1, v]
                        self.dlen = {0: 128, 1: 256, 2: 512, 3: 1024, 4: 2048}.get(self.last_n, 512)
                        self.data_armed = 0
                        self.events.append(('DSTART', cyc))
                    self.preamble_ok = 0; self.preamble2_ok = 0
                else:
                    self.preamble_ok = 0; self.preamble2_ok = 0
            self.sync_cnt = 0
        elif st == 'ID':
            self.field.append(v); self.sync_cnt = 0
            if len(self.field) == 4 + 4 and not self.tol_id:
                self.last_n = v
            if len(self.field) == 4 + 6:
                ok = crc16(self.field) == 0
                c, h, r, n = self.field[4:8]
                if self.tol_id and not ok:
                    self.events.append(('TOLQ', cyc, c, h, r, n))
                else:
                    self.events.append(('ID', cyc, c, h, r, n, ok, self.est))
                    self.data_armed = 1 if ok else 0
                    if self.tol_id:
                        self.last_n = n
                self.tol_id = 0
                self.state = 'IDLE'
        elif st == 'DATA':
            self.field.append(v); self.sync_cnt = 0
            if len(self.field) == 4 + self.dlen + 2:
                ok = crc16(self.field) == 0
                self.events.append(('DEND', cyc, ok, self.field[3] == 0xF8,
                                    zlib.crc32(bytes(self.field[4:4 + self.dlen]))))
                self.state = 'IDLE'

def side_flux(data, hdr, offs, cyl, head):
    revs = track_revs(data, hdr, offs, cyl * 2 + head)
    if revs is None:
        return None, None
    flux = []
    idx = [0]
    tot = 0
    for it, fl in revs:
        flux += fl
        tot += it
        idx.append(tot)
    return flux, idx

def run_model(gaps, tol=None, trace=False):
    m = Model(tol, trace)
    for g, c in gaps:
        m.gap(g, c)
    return m

def run_side(data, hdr, offs, cyl, head, scale=1.0, tol=None):
    revs = track_revs(data, hdr, offs, cyl * 2 + head)
    if revs is None:
        return None
    flux, idx = side_flux(data, hdr, offs, cyl, head)
    gaps = gaps_from_flux(flux, hdr['tick_ns'], scale)
    m = run_model(gaps, tol)
    per = [x * hdr['tick_ns'] * scale / 20.0 for x in idx]
    res = []
    for r in range(len(revs)):
        lo, hi = per[r], per[r + 1]
        ev = [e for e in m.events if lo <= e[1] < hi]
        d = {}
        for e in ev:
            k = e[0]
            if k == 'DAM' and e[2]: d['UNARMED'] = d.get('UNARMED', 0) + 1
            d[k] = d.get(k, 0) + 1
        ids = [(e[4], e[6], (e[1] - lo) / 50000.0) for e in ev if e[0] == 'ID']
        dams = [((e[1] - lo) / 50000.0, e[2]) for e in ev if e[0] == 'DAM']
        res.append((d, ids, dams, ev, lo))
    return res

def main():
    cmd = sys.argv[1]
    path = sys.argv[2]
    args = sys.argv[3:]
    scale = 1.0
    if '--scale' in args:
        scale = float(args[args.index('--scale') + 1])
    tol = TOL_PROD if '--tol' in args else None
    data, hdr, offs = read_scp(path)
    if cmd == 'side':
        cyl, head = int(args[0]), int(args[1])
        res = run_side(data, hdr, offs, cyl, head, scale, tol)
        for r, (d, ids, dams, ev, lo) in enumerate(res):
            print('rev %d: cand=%d train=%d FE=%d DAM=%d unarmed=%d GE=%d REJ=%d TOL=%d IDs=%s' % (
                r, d.get('C', 0), d.get('T', 0), d.get('FE', 0), d.get('DAM', 0), d.get('UNARMED', 0),
                d.get('GE', 0), d.get('REJ', 0), d.get('TOL', 0),
                ' '.join('%d%s' % (i[0], '' if i[1] else '!') for i in ids)))
            if '--list' in args:
                for e in ev:
                    if e[0] != 'C':
                        print('   %8.3f %s' % ((e[1] - lo) / 50000.0, e))
    elif cmd == 'survey':
        cr = (0, 79)
        if '--cyl' in args:
            a, b = args[args.index('--cyl') + 1].split('-'); cr = (int(a), int(b))
        tot_missing = 0
        for cyl in range(cr[0], cr[1] + 1):
            for head in (1, 0):   # head 1 = ID H=0 (first in the DOS order)
                res = run_side(data, hdr, offs, cyl, head, scale, tol)
                if res is None:
                    continue
                line = []
                bad = False
                for r, (d, ids, dams, ev, lo) in enumerate(res):
                    got = sorted(set(i[0] for i in ids if i[1] and 1 <= i[0] <= 10))
                    miss = [s for s in range(1, 11) if s not in got]
                    ex = d.get('C', 0) - 3 * d.get('T', 0)
                    if miss or ex or d.get('UNARMED', 0) or d.get('REJ', 0):
                        bad = True
                    line.append('r%d miss=%s exC=%d un=%d GE=%d' % (r, ','.join(map(str, miss)) or '-', ex, d.get('UNARMED', 0), d.get('GE', 0)))
                    tot_missing += len(miss)
                if bad:
                    print('cyl %2d head %d (ID H=%d): %s' % (cyl, head, 1 - head, ' | '.join(line)))
        print('total missing (side x rev):', tot_missing)

if __name__ == '__main__':
    main()
