#!/usr/bin/env python3
"""Python model of the production read front end (physical_1581_mfm_gaps,
_quantise, _gaps_to_bits, _bits_to_bytes and the field FSM of
physical_1581_mfm_decoder), gap-event level, for surveys of SCP captures.
Validated against the RTL (sim/tb_flux_dec.vhd) on cylinder 77 side H=1.

Usage:
  decmodel.py survey <scp> [--scale S] [--cyl a-b]   per side: missing IDs per rev
  decmodel.py side <scp> <cyl> <head> [--scale S] [--list]
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from scp import read_scp, track_revs, crc16

EST_NOM = 1600; EST_MIN = 1440; EST_MAX = 1760; STEP = 2
SYNC_RUN = 16; SYNC_LAT = 6; SPACING = 5; A1_CELLS = 14
SYNC_PAT = (2, 1, 2, 1)

def gaps_from_flux(flux_ticks, tick_ns, scale=1.0):
    """absolute edge cycles -> gap lengths in 50 MHz cycles (gaps stage:
    the 2-stage edge pipeline adds a constant delay that cancels)."""
    t = 0.0
    last = None
    out = []   # (gap_cycles, edge_cycle)
    acc_start = None
    for f in flux_ticks:
        t += f * tick_ns * scale
        c = int(round(t / 20.0))
        if last is None:
            last = c
            continue
        g = c - last
        if g < 16:            # runt: merge into the following gap
            continue
        out.append((g, c))
        last = c
    return out

class Model:
    def __init__(self):
        self.reset()
    def reset(self):
        self.est = EST_NOM
        self.recent = []
        self.last_bit = 0
        self.short_run = 0; self.run_age = 15; self.sync_gap_age = 15
        self.a1g = [0, 0, 0, 0]
        self.sync_cnt = 0
        self.state = 'IDLE'
        self.data_armed = 0; self.preamble_ok = 0
        self.bits = []      # partial byte bits
        self.bitcount = 0
        self.field = []
        self.last_n = 2
        self.events = []
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
        if abs(e) <= tol:
            cls = n
            if e > 0: est += STEP
            elif e < 0: est -= STEP
            est = min(max(est, EST_MIN), EST_MAX)
            self.est = est
        else:
            cls = 0      # invalid
            self.est = EST_NOM
        est_after = self.est
        # ---------------- decoder bookkeeping on q_valid
        self.a1g = [g] + self.a1g[:3]
        if self.sync_gap_age < 15: self.sync_gap_age += 1
        if cls == 0:
            self.events.append(('GE', cyc, g))
            self.state = 'IDLE'; self.sync_cnt = 0; self.short_run = 0
            self.run_age = 15; self.sync_gap_age = 15; self.preamble_ok = 0
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

    def sync(self, cyc, est):
        self.events.append(('C', cyc, est))
        # b2b: sync resets the bit counter
        self.bitcount = 0; self.bits = []
        actual = sum(self.a1g)
        expected = (est * A1_CELLS + 8) // 16
        tolv = (est + 32 - 1) // 32
        if abs(actual - expected) > tolv:
            self.sync_cnt = 0; self.sync_gap_age = 15; self.preamble_ok = 0
            self.events.append(('REJ', cyc))
        elif self.sync_cnt == 0:
            self.sync_cnt = 1; self.sync_gap_age = 0
            self.crc_pre = 1
            self.preamble_ok = 1 if self.run_age <= SYNC_LAT else 0
        elif self.sync_gap_age == SPACING:
            if self.sync_cnt < 3:
                self.sync_cnt += 1
                if self.sync_cnt == 3:
                    self.events.append(('T', cyc))
            self.sync_gap_age = 0
        else:
            self.sync_cnt = 1; self.sync_gap_age = 0
            self.preamble_ok = 1 if self.run_age <= SYNC_LAT else 0

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
        if self.sync_cnt == 3 and v == 0xFE:
            self.events.append(('FE', cyc))
        elif self.sync_cnt == 3 and v in (0xFB, 0xF8):
            unarmed = (st != 'IDLE' or self.data_armed == 0 or self.preamble_ok == 0)
            self.events.append(('DAM', cyc, unarmed))
        if self.sync_cnt == 3 and v == 0xFE and st != 'IDLE':
            self.state = 'ID'; self.field = [0xA1, 0xA1, 0xA1, 0xFE]; self.sync_cnt = 0
            self.data_armed = 0; self.preamble_ok = 0
            return
        if st == 'IDLE':
            if self.sync_cnt == 3:
                if v == 0xFE:
                    self.state = 'ID'; self.field = [0xA1, 0xA1, 0xA1, 0xFE]
                    self.data_armed = 0; self.preamble_ok = 0
                elif v in (0xFB, 0xF8):
                    if self.data_armed and self.preamble_ok:
                        self.state = 'DATA'; self.field = [0xA1, 0xA1, 0xA1, v]
                        self.dlen = {0: 128, 1: 256, 2: 512, 3: 1024, 4: 2048}.get(self.last_n, 512)
                        self.data_armed = 0
                        self.events.append(('DSTART', cyc))
                    self.preamble_ok = 0
                else:
                    self.preamble_ok = 0
            self.sync_cnt = 0
        elif st == 'ID':
            self.field.append(v); self.sync_cnt = 0
            if len(self.field) == 4 + 4:
                self.last_n = v
            if len(self.field) == 4 + 6:
                ok = crc16(self.field) == 0
                c, h, r, n = self.field[4:8]
                self.events.append(('ID', cyc, c, h, r, n, ok, self.est))
                self.data_armed = 1 if ok else 0
                self.state = 'IDLE'
        elif st == 'DATA':
            self.field.append(v); self.sync_cnt = 0
            if len(self.field) == 4 + self.dlen + 2:
                ok = crc16(self.field) == 0
                self.events.append(('DEND', cyc, ok))
                self.state = 'IDLE'

def run_side(data, hdr, offs, cyl, head, scale=1.0):
    revs = track_revs(data, hdr, offs, cyl * 2 + head)
    if revs is None:
        return None
    flux = []
    idx = [0]
    tot = 0
    for it, fl in revs:
        flux += fl
        tot += it
        idx.append(tot)
    gaps = gaps_from_flux(flux, hdr['tick_ns'], scale)
    m = Model()
    for g, c in gaps:
        m.gap(g, c)
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
    data, hdr, offs = read_scp(path)
    if cmd == 'side':
        cyl, head = int(args[0]), int(args[1])
        res = run_side(data, hdr, offs, cyl, head, scale)
        for r, (d, ids, dams, ev, lo) in enumerate(res):
            print('rev %d: cand=%d train=%d FE=%d DAM=%d unarmed=%d GE=%d REJ=%d IDs=%s' % (
                r, d.get('C', 0), d.get('T', 0), d.get('FE', 0), d.get('DAM', 0), d.get('UNARMED', 0),
                d.get('GE', 0), d.get('REJ', 0), ' '.join('%d%s' % (i[0], '' if i[1] else '!') for i in ids)))
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
                res = run_side(data, hdr, offs, cyl, head, scale)
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
