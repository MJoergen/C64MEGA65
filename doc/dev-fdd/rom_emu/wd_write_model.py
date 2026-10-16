# WD1772 WRITE model of the C64MEGA65 physical 1581 (issue #244, milestone M2),
# grown from the planning probes of 2026-10-15 (write_probes/wmachine.py of the
# controller session: cycle table, rotational layout, Write Track record parser).
#
# The genuine 318045-02 DOS ROM runs on the cycle-exact 6502 below against a WD
# front end that mirrors WRITE-SPEC.md section 5.1 / 5.4 as implemented in
# fdc1772.v (M2), not the real chip's one-byte data register:
#
#   * Write Sector: write-protect pre-check (BUSY held >= 1.5 ms, status bit 6
#     ALONE, no DRQ); otherwise the controller searches the ID; at the ID CRC
#     it raises FEED; DRQ = feed and FIFO room (4 bytes) and fewer than 512
#     accepted; every data-register write while the op accepts bytes is one
#     FIFO push (a write into a full FIFO, after the 512th byte or after the
#     feed fell is dropped and counted). 22 byte-times after the ID CRC the
#     first-byte rule decides: FIFO empty -> RES_LOST_DATA, WGATE never opens;
#     else WGATE, 12x00 3xA1 DAM (16 byte-times), 512 slots of one FIFO pop per
#     byte-time (an empty FIFO writes 00 and sets the sticky LOST level; the
#     late byte goes into the next slot), CRC CRC FF, writer tail; then feed
#     off, the FIFO is drained, done; BUSY drops at the done (>= 1.5 ms after
#     the issue in every case).
#   * Write Track: pre-check as above; feed at once; at the next qualified
#     index (leading edge + 200 us filter) the FIFO must hold the first token
#     (else RES_LOST_DATA, no gate); then one token per byte-time, F7 = two
#     byte-times (CRC hi + lo), F5 = A1 sync, F6 = C2 sync, until the next
#     qualified index; then the tail, drain, done.
#   * Status of a write command: b6 WP (alone), b4 RNF (never with b3),
#     b3 CRC, b2 LOST DATA (the sticky level or RES_LOST_DATA), b1 DRQ,
#     b0 BUSY; bit 5 always 0. Force Interrupt cancels at once.
#   * Read Sector / Read Address use the rotational stock layout (ID CRC end
#     of record R at byte-time 32 + 609 (R-1) + 22 of a 6250 byte-time
#     revolution) and the delivery-v2 presentation of machine.py.
#
# Time unit: 2 MHz CPU cycles (0.5 us); one DD byte-time BT = 64 cycles.
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import machine as machmod
from cpu6502 import CPU

# ---------- exact NMOS 6502 cycle table (documented opcodes) ----------
# (machine.py's CPU charges a flat 3 cycles per instruction; the write paths
#  are cycle-critical, so every opcode is charged its datasheet count here,
#  plus the page-cross and branch-taken extras)
BASE = {}
def _set(ops, n):
    for o in ops: BASE[o] = n
IMM = 2; ZP = 3; ZPX = 4; ABS = 4; ABX = 4; ABY = 4; IZX = 6; IZY = 5
for grp in [(0xA9, 0xA5, 0xB5, 0xAD, 0xBD, 0xB9, 0xA1, 0xB1),   # LDA
            (0x69, 0x65, 0x75, 0x6D, 0x7D, 0x79, 0x61, 0x71),   # ADC
            (0xE9, 0xE5, 0xF5, 0xED, 0xFD, 0xF9, 0xE1, 0xF1),   # SBC
            (0xC9, 0xC5, 0xD5, 0xCD, 0xDD, 0xD9, 0xC1, 0xD1),   # CMP
            (0x29, 0x25, 0x35, 0x2D, 0x3D, 0x39, 0x21, 0x31),   # AND
            (0x09, 0x05, 0x15, 0x0D, 0x1D, 0x19, 0x01, 0x11),   # ORA
            (0x49, 0x45, 0x55, 0x4D, 0x5D, 0x59, 0x41, 0x51)]:  # EOR
    for o, n in zip(grp, (IMM, ZP, ZPX, ABS, ABX, ABY, IZX, IZY)): BASE[o] = n
_set((0xA2, 0xA0, 0xE0, 0xC0), 2); _set((0xA6, 0xA4, 0xE4, 0xC4, 0x24), 3)
_set((0xB6, 0xB4), 4); _set((0xAE, 0xAC, 0xEC, 0xCC, 0x2C), 4); _set((0xBE, 0xBC), 4)
_set((0x85, 0x86, 0x84), 3); _set((0x95, 0x96, 0x94), 4); _set((0x8D, 0x8E, 0x8C), 4)
_set((0x9D, 0x99), 5); _set((0x81,), 6); _set((0x91,), 6)
_set((0xAA, 0xA8, 0x8A, 0x98, 0xBA, 0x9A, 0xE8, 0xC8, 0xCA, 0x88, 0x18, 0x38, 0x58, 0x78,
      0xB8, 0xD8, 0xF8, 0xEA), 2)
_set((0x0A, 0x4A, 0x2A, 0x6A), 2)
_set((0x06, 0x46, 0x26, 0x66, 0xE6, 0xC6), 5); _set((0x16, 0x56, 0x36, 0x76, 0xF6, 0xD6), 6)
_set((0x0E, 0x4E, 0x2E, 0x6E, 0xEE, 0xCE), 6); _set((0x1E, 0x5E, 0x3E, 0x7E, 0xFE, 0xDE), 7)
_set((0x4C,), 3); _set((0x6C,), 5); _set((0x20, 0x60, 0x40), 6); _set((0x00,), 7)
_set((0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0), 2)
_set((0x48, 0x08), 3); _set((0x68, 0x28), 4)
BRANCH = {0x10, 0x30, 0x50, 0x70, 0x90, 0xB0, 0xD0, 0xF0}
ABX_RD = {0xBD, 0x7D, 0xFD, 0xDD, 0x3D, 0x1D, 0x5D, 0xBC}
ABY_RD = {0xB9, 0x79, 0xF9, 0xD9, 0x39, 0x19, 0x59, 0xBE}
IZY_RD = {0xB1, 0x71, 0xF1, 0xD1, 0x31, 0x11, 0x51}

class ACPU(CPU):
    def step(self):
        irq_taken = self.irq_line and not self.i
        pc0 = self.pc; r = self.read
        op = r(pc0); x0 = self.x; y0 = self.y
        extra = 0
        if op in ABX_RD or op in ABY_RD:
            base = r((pc0 + 1) & 0xFFFF) | (r((pc0 + 2) & 0xFFFF) << 8)
            idx = x0 if op in ABX_RD else y0
            if ((base + idx) & 0xFF00) != (base & 0xFF00): extra = 1
        elif op in IZY_RD:
            z = r((pc0 + 1) & 0xFFFF); base = r(z) | (r((z + 1) & 0xFF) << 8)
            if ((base + y0) & 0xFF00) != (base & 0xFF00): extra = 1
        c0 = self.cycles
        super().step()
        n = BASE.get(op, 2) + extra
        if op in BRANCH and not irq_taken:
            if self.pc != ((pc0 + 2) & 0xFFFF):
                n += 1
                if (self.pc & 0xFF00) != ((pc0 + 2) & 0xFF00): n += 1
        if irq_taken: n += 7
        self.cycles = c0 + n
        self.last_n = n

BT = 64                     # one DD MFM byte-time = 32 us = 64 cycles at 2 MHz
REV = 6250                  # byte-times per 200 ms revolution (300 rpm)
def id_end_bt(r):           # stock 318045-02 layout: end of the ID CRC of record R
    return 32 + 609 * (r - 1) + 22

FIFO_DEPTH = 4              # physical_1581_wfifo G_AW = 2
T1MIN = 3000                # PHYS_T1_MIN_TICKS: 1.5 ms minimum BUSY of every write termination
GAP_BT = 22                 # first-byte decision / WGATE, byte-times after the ID CRC
PRE_BT = 16                 # 12 x 00, 3 x A1, DAM
TAIL_CYC = 16               # writer tail (~3 cells) + feed-off guard + drain + done CDC, ~8 us
INDEX_FILTER = 400          # 200 us index qualification (opens and closes the track late alike)
CDC = 2                     # feed / done synchronizer latency at CPU granularity


class WriteMachine(machmod.Machine):
    def __init__(self, **kw):
        super().__init__(**kw)
        self.cpu = ACPU(self.read, self.write)
        self.origin = 0                 # cycle of the index reference
        self.wp = False                 # the tab: CIA PB6 and the WD pre-check
        self.ev = []                    # (cycle, seq, kind, arg) scheduled write events
        self.ev_seq = 0
        self.wop = None                 # 'ws' | 'wt' while a write op runs
        self.feed = False; self.fed = False
        self.wfifo = []                 # bytes pushed, not yet popped
        self.acc = 0                    # data-register bytes accepted by the op
        self.wlost = 0                  # sticky lost level of the op
        self.wres = None                # 'OK' | 'LOST' | 'WP' | 'RNF' | 'NOIDX'
        self.w_wp = 0                   # status bit 6 of the last write command
        self.issue_at = 0
        self.slots = []                 # bytes written to the disk by the op
        self.tok_log = []               # per accepted byte: [value, latency, fate]
        self.drq_rise = None            # cycle the current DRQ-high period began
        self.drq_prev = False
        self.first_lat = None; self.lat_hist = []
        self.drops = 0; self.drained = 0
        self.ops = []                   # completed write op summaries
        self.cmd_log = []               # (cycle, cmd, track, sector, data, head, side, pc)
        self.busy_drop_at = None
        self.gaps = []                  # (cmd, cycles from the previous BUSY drop, pc)
        self.rnf_inject = set()         # (cyl, side, r): Write Sector never finds the ID
        self.lost_inject = set()        # (cyl, side, r): the op reports the lost level
        self.noidx_inject = False       # next Write Track: no index
    # ---------------- rotation ----------------
    def next_time_at_bt(self, target_bt, not_before):
        base = not_before - ((not_before - self.origin) % (REV * BT))
        t = base + target_bt * BT
        while t < not_before: t += REV * BT
        return t
    def next_id(self, r, not_before):
        return self.next_time_at_bt(id_end_bt(r), not_before)
    def next_any_id(self, not_before):
        best = None
        for r in range(1, 11):
            t = self.next_id(r, not_before)
            if best is None or t < best[0]: best = (t, r)
        return best
    # ---------------- run ----------------
    def run(self, steps):
        for _ in range(steps):
            c0 = self.cpu.cycles
            self.cpu.step()
            self.tick_devices(self.cpu.cycles - c0)
    def tick_devices(self, n):
        super().tick_devices(n)
        self.w_tick()
    def cia_read(self, r):
        v = super().cia_read(r)
        if r == 1 and self.wp: v &= ~0x40          # PB6 /WPRT low = protected
        return v
    # ---------------- the write FIFO / DRQ ----------------
    def accepting(self):
        if self.wop is None: return False
        if self.wop == 'ws' and self.acc >= 512: return False
        return not (self.fed and not self.feed)
    def drq_level(self):
        return (self.wop is not None and self.feed and self.accepting()
                and len(self.wfifo) < FIFO_DEPTH)
    def drq_update(self, t):
        lvl = self.drq_level()
        if lvl and not self.drq_prev: self.drq_rise = t
        self.drq_prev = lvl
    # ---------------- WD registers ----------------
    def wd_busy(self):
        return 1 if self.wop is not None else super().wd_busy()
    def is_write_cmd(self):
        return (self.cmd >> 4) in (0xA, 0xB, 0xF)
    def wd_read(self, r):
        if r == 0 and (self.wop is not None or self.is_write_cmd()):
            b7 = 0x80 if self.motor() else 0
            b6 = 0x40 if self.w_wp else 0
            b4 = 0x10 if (self.rnf and not self.crc and not self.w_wp) else 0
            b3 = 0x08 if (self.crc and not self.w_wp) else 0
            b2 = 0x04 if (self.lost and not self.w_wp) else 0
            b1 = 0x02 if self.drq_level() else 0
            b0 = 1 if self.wop is not None else 0
            return b7 | b6 | b4 | b3 | b2 | b1 | b0
        return super().wd_read(r)
    def wd_write(self, r, v):
        if r == 3 and self.wop is not None:
            self.wd_data_in = v; self.wd_data_out = v
            if self.accepting() and len(self.wfifo) < FIFO_DEPTH:
                lat = (self.cyc - self.drq_rise) if (self.drq_prev and self.drq_rise is not None) else None
                if lat is not None:
                    if self.first_lat is None: self.first_lat = lat
                    else: self.lat_hist.append(lat)
                self.wfifo.append(v); self.acc += 1
                self.tok_log.append([v, lat, 'fifo'])
                # the data-register write clears DRQ; it re-rises at once if room remains
                self.drq_prev = False
                self.drq_update(self.cyc)
            else:
                self.drops += 1
                self.tok_log.append([v, None, 'dropped'])
                self.trace.append(('WR-DROP', v, self.wop, self.acc, len(self.wfifo)))
            return
        super().wd_write(r, v)
    def wd_command(self, v):
        top = v >> 4
        if self.wd_busy() and top != 0xD:
            self.dbg['busycmd'] += 1
            self.trace.append(('CMD-IGNORED', v, 'pc=%04X' % self.cpu.pc)); return
        if self.busy_drop_at is not None:
            self.gaps.append((v, self.cyc - self.busy_drop_at, self.cpu.pc))
        self.cmd_log.append((self.cyc, v, self.wd_track, self.wd_sector, self.wd_data_in,
                             self.head, self.pa0_to_physside(), self.cpu.pc))
        if top in (0xA, 0xB):
            self.start_write(v, 'ws'); return
        if top == 0xF:
            self.start_write(v, 'wt'); return
        if top == 0xD and self.wop is not None:
            self.trace.append(('FI-DURING-WRITE-OP', self.wop, self.cpu.pc))
            self.cmd = v
            self.ev = []; self.wop = None; self.feed = False; self.wfifo = []
            self.drq_prev = False
            self.busy_until = self.cyc; self.busy_drop_at = self.cyc; return
        if top in (0x8, 0x9):
            self.cmd = v
            self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
            self.drq = 0; self.lost = 0; self.rnf = 0; self.crc = 0; self.deleted = 0; self.dbg['presented'] = 0
            self.start_phys_op('rs')
            if self.ctrl_done_at is not None: return
            key = (self.head, self.pa0_to_physside(), self.wd_sector)
            if self.wd_track == self.head and key in self.disk:
                t_id = self.next_id(self.wd_sector, self.cyc + 2 * BT)
                lat = (t_id + 39 * BT) - self.cyc
                self.staged = (self.cyc + lat, list(self.disk[key]))
                self.ctrl_rnf = 0; self.ctrl_crc = 0
                self.ctrl_done_at = self.cyc + lat + (512 + 2) * BT
            else:
                self.ctrl_rnf = 1; self.ctrl_crc = 0
                self.ctrl_done_at = self.cyc + 5 * REV * BT
            return
        if top == 0xC:
            self.cmd = v
            self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
            self.drq = 0; self.lost = 0; self.rnf = 0; self.crc = 0; self.deleted = 0; self.dbg['presented'] = 0
            self.start_phys_op('ra')
            if self.ctrl_done_at is not None: return
            t_id, rr = self.next_any_id(self.cyc + 2 * BT)
            c = self.head; h = self.pa0_to_physside(); n = 2
            crc = machmod.crc16_ccitt([0xA1, 0xA1, 0xA1, 0xFE, c, h, rr, n])
            self.ra_found_c = c
            lat = (t_id - 6 * BT) - self.cyc
            if lat < BT: lat = BT
            self.staged = (self.cyc + lat, [c, h, rr, n, crc >> 8, crc & 0xFF])
            self.ctrl_rnf = 0; self.ctrl_crc = 0
            self.ctrl_done_at = self.cyc + lat + 7 * BT
            self.trace.append(('RA', c, h, rr, 'lat=%d' % lat))
            return
        super().wd_command(v)
    def wd_finalize(self):
        super().wd_finalize()
        self.busy_drop_at = self.cyc
    # ---------------- write ops ----------------
    def sched(self, t, kind, arg=None):
        self.ev_seq += 1
        self.ev.append((t, self.ev_seq, kind, arg)); self.ev.sort()
    def start_write(self, v, kind):
        self.cmd = v; self.wop = kind
        self.drq = 0; self.lost = 0; self.rnf = 0; self.crc = 0; self.w_wp = 0
        self.feed = False; self.fed = False; self.wfifo = []; self.acc = 0
        self.wlost = 0; self.wres = None; self.slots = []; self.tok_log = []
        self.drq_prev = False; self.drq_rise = None
        self.first_lat = None; self.lat_hist = []
        self.issue_at = self.cyc
        self.op_cyl = self.head; self.op_side = self.pa0_to_physside()
        self.op_sector = self.wd_sector; self.op_track_reg = self.wd_track
        self.op_drops0 = self.drops; self.op_drained0 = self.drained
        self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
        if self.wp:
            # WD-side write-protect pre-check: no request, no DRQ; bit 6 alone
            self.w_wp = 1
            self.wres = 'WP'
            self.sched(self.cyc + T1MIN, 'finish'); return
        if kind == 'ws':
            key = (self.head, self.op_side, self.wd_sector)
            if (self.wd_track != self.head or not (1 <= self.wd_sector <= 10)
                    or key in self.rnf_inject):
                # controller search budget: 5 index edges -> RNF (+rnf flag)
                self.sched(self.cyc + 5 * REV * BT, 'term', ('RNF', 1, 0)); return
            t_id = self.next_id(self.wd_sector, self.cyc + 2 * BT)
            self.t_id = t_id
            self.sched(t_id + CDC, 'feed_on')
            self.sched(t_id + GAP_BT * BT, 'ws_gap')
        else:
            self.sched(self.cyc + CDC, 'feed_on')
            if self.noidx_inject:
                self.noidx_inject = False
                self.sched(self.cyc + 600000, 'term', ('NOIDX', 1, 0)); return  # 300 ms watchdog
            t_idx = self.next_time_at_bt(0, self.cyc) + INDEX_FILTER
            self.t_idx = t_idx
            self.sched(t_idx, 'wt_start')
    def w_tick(self):
        while self.ev and self.ev[0][0] <= self.cyc:
            t, _, kind, arg = self.ev.pop(0)
            getattr(self, 'ev_' + kind)(t, arg)
            self.drq_update(t)
    def pop_slot(self, t):
        if self.wfifo:
            b = self.wfifo.pop(0)
            for e in self.tok_log:
                if e[2] == 'fifo': e[2] = 'disk'; break
        else:
            b = 0x00; self.wlost = 1
        self.slots.append(b)
        return b
    # Write Sector
    def ev_feed_on(self, t, a):
        if self.wop is None: return
        self.feed = True; self.fed = True
    def ev_ws_gap(self, t, a):
        if self.wop != 'ws': return
        if not self.wfifo:
            self.feed = False                      # first-byte rule: no gate
            self.ev_term(t, ('LOST', 0, 0)); return
        self.wgate_on_at = t
        self.sched(t + PRE_BT * BT, 'ws_slot', 0)
    def ev_ws_slot(self, t, k):
        if self.wop != 'ws': return
        self.pop_slot(t)
        if k < 511: self.sched(t + BT, 'ws_slot', k + 1)
        else:       self.sched(t + 4 * BT, 'ws_post')      # last slot, CRC, CRC, FF
    def ev_ws_post(self, t, a):
        key = (self.op_cyl, self.op_side, self.op_sector)
        self.disk[key] = bytearray(self.slots)
        if key in self.lost_inject:
            self.lost_inject.discard(key); self.wlost = 1
            self.trace.append(('INJECT-LOST', key))
        self.feed = False
        self.ev_term(t, ('OK', 0, 0), tail=TAIL_CYC)
    # Write Track
    def ev_wt_start(self, t, a):
        if self.wop != 'wt': return
        if not self.wfifo:
            self.feed = False
            self.ev_term(t, ('LOST', 0, 0)); return
        self.wgate_on_at = t
        self.wt_end_at = t + REV * BT               # the next qualified index (same filter delay)
        self.sched(t, 'wt_slot')
    def ev_wt_slot(self, t, a):
        if self.wop != 'wt': return
        b = self.pop_slot(t)
        nxt = t + (2 * BT if b == 0xF7 else BT)
        if nxt < self.wt_end_at: self.sched(nxt, 'wt_slot')
        else:                     self.sched(self.wt_end_at, 'wt_end')
    def ev_wt_end(self, t, a):
        self.feed = False
        self.parse_track()
        self.ev_term(t, ('OK', 0, 0), tail=TAIL_CYC)
    # termination: feed off, guard, drain, done; BUSY >= T1MIN after the issue
    def ev_term(self, t, res, tail=CDC):
        self.feed = False
        self.wres, self.rnf, self.crc = res
        self.wres_flags = res
        self.sched(max(t + tail, self.issue_at + T1MIN), 'finish')
    def ev_finish(self, t, a):
        for e in self.tok_log:
            if e[2] == 'fifo': e[2] = 'drained'
        self.drained += len(self.wfifo); self.wfifo = []
        self.lost = 1 if (self.wlost or self.wres == 'LOST') else 0
        if self.wres == 'WP': self.w_wp = 1
        op = dict(kind=self.wop, cmd=self.cmd, start=self.issue_at, end=t,
                  cyl=self.op_cyl, side=self.op_side, sector=self.op_sector,
                  track_reg=self.op_track_reg, result=self.wres, lost=self.lost,
                  first_lat=self.first_lat, lat=list(self.lat_hist),
                  accepted=self.acc, slots=bytes(self.slots), tok_log=[list(e) for e in self.tok_log],
                  drops=self.drops - self.op_drops0, drained=self.drained - self.op_drained0,
                  t_id=getattr(self, 't_id', None) if self.wop == 'ws' else None,
                  t_idx=getattr(self, 't_idx', None) if self.wop == 'wt' else None)
        self.ops.append(op)
        self.wop = None; self.feed = False; self.ev = []
        self.drq_prev = False
        self.busy_drop_at = t
        self.trace.append(('FIN-W', op['kind'], self.wres, 'lost=%d' % self.lost))
    def parse_track(self):
        toks = self.slots; i = 0; recs = []
        while i < len(toks) - 4:
            if toks[i] == 0xF5 and toks[i + 1] == 0xF5 and toks[i + 2] == 0xF5:
                if toks[i + 3] == 0xFE:
                    c, h, r, n = toks[i + 4:i + 8]
                    recs.append(['ID', c, h, r, n, i]); i += 8; continue
                if toks[i + 3] == 0xFB:
                    data = bytes(toks[i + 4:i + 4 + 512])
                    if recs and recs[-1][0] == 'ID' and len(data) == 512:
                        c, h, r, n = recs[-1][1:5]
                        self.disk[(c, h, r)] = bytearray(data)
                        recs[-1] = ['REC', c, h, r, n, recs[-1][5], i]
                    i += 4 + 512; continue
            i += 1
        self.wt_records = recs


# ---------------- harness helpers ----------------
def post_job(m, job, t, s, bufpage=3, slot=0):
    m.ram[0x0B + 2 * slot] = t; m.ram[0x0C + 2 * slot] = s
    m.ram[0x01F1 + slot] = bufpage
    m.ram[0x0002 + slot] = job

def jobs_idle(m):
    return all(m.ram[2 + i] < 0x80 for i in range(9)) and not m.wd_busy()

def run_until_idle(m, maxsteps, label, extra=5000):
    for _ in range(maxsteps // 10000):
        m.run(10000)
        if jobs_idle(m):
            m.run(extra)
            return True
    print('!! %s: did not go idle; pc=$%04X jobq %s'
          % (label, m.cpu.pc, ['%02X' % m.ram[2 + i] for i in range(9)]))
    return False

def boot():
    m = WriteMachine()
    m.cpu.reset()
    m.run(3_000_000)          # fixed boot budget (README gotcha 1)
    m.ram[0x9C] = 0xFF        # hold the idle flush off until a scenario asks for it
    return m

def fmt_cmd(c):
    top = c >> 4
    names = {0x8: 'RDSEC', 0x9: 'RDSEC', 0xA: 'WRSEC', 0xB: 'WRSEC', 0xC: 'RDADDR', 0xD: 'FORCEINT',
             0xE: 'RDTRK', 0xF: 'WRTRK', 0x0: 'RESTORE', 0x1: 'SEEK', 0x2: 'STEP', 0x3: 'STEP',
             0x4: 'STEPIN', 0x5: 'STEPIN', 0x6: 'STEPOUT', 0x7: 'STEPOUT'}
    return names.get(top, '?')
