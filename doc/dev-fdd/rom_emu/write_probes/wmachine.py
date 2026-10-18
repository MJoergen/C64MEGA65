# Writable WD1772 model + accurate-cycle 6502 for probing the 1581 DOS write paths.
# Scratchpad-only tool (not part of the repo). Builds on doc/dev-fdd/rom_emu/machine.py.
import sys, os
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import machine as machmod
from cpu6502 import CPU

# ---------- accurate NMOS 6502 cycle table (documented opcodes) ----------
BASE = {}
def _set(ops, n):
    for o in ops: BASE[o] = n
# loads/stores/alu by addressing mode
IMM=2; ZP=3; ZPX=4; ABS=4; ABX=4; ABY=4; IZX=6; IZY=5
for grp in [(0xA9,0xA5,0xB5,0xAD,0xBD,0xB9,0xA1,0xB1),   # LDA
            (0x69,0x65,0x75,0x6D,0x7D,0x79,0x61,0x71),   # ADC
            (0xE9,0xE5,0xF5,0xED,0xFD,0xF9,0xE1,0xF1),   # SBC
            (0xC9,0xC5,0xD5,0xCD,0xDD,0xD9,0xC1,0xD1),   # CMP
            (0x29,0x25,0x35,0x2D,0x3D,0x39,0x21,0x31),   # AND
            (0x09,0x05,0x15,0x0D,0x1D,0x19,0x01,0x11),   # ORA
            (0x49,0x45,0x55,0x4D,0x5D,0x59,0x41,0x51)]:  # EOR
    for o, n in zip(grp, (IMM,ZP,ZPX,ABS,ABX,ABY,IZX,IZY)): BASE[o] = n
_set((0xA2,0xA0,0xE0,0xC0), 2); _set((0xA6,0xA4,0xE4,0xC4,0x24), 3)
_set((0xB6,0xB4), 4); _set((0xAE,0xAC,0xEC,0xCC,0x2C), 4); _set((0xBE,0xBC), 4)
_set((0x85,0x86,0x84), 3); _set((0x95,0x96,0x94), 4); _set((0x8D,0x8E,0x8C), 4)
_set((0x9D,0x99), 5); _set((0x81,), 6); _set((0x91,), 6)
_set((0xAA,0xA8,0x8A,0x98,0xBA,0x9A,0xE8,0xC8,0xCA,0x88,0x18,0x38,0x58,0x78,0xB8,0xD8,0xF8,0xEA), 2)
_set((0x0A,0x4A,0x2A,0x6A), 2)
_set((0x06,0x46,0x26,0x66,0xE6,0xC6), 5); _set((0x16,0x56,0x36,0x76,0xF6,0xD6), 6)
_set((0x0E,0x4E,0x2E,0x6E,0xEE,0xCE), 6); _set((0x1E,0x5E,0x3E,0x7E,0xFE,0xDE), 7)
_set((0x4C,), 3); _set((0x6C,), 5); _set((0x20,0x60,0x40), 6); _set((0x00,), 7)
_set((0x10,0x30,0x50,0x70,0x90,0xB0,0xD0,0xF0), 2)
_set((0x48,0x08), 3); _set((0x68,0x28), 4)
BRANCH = {0x10,0x30,0x50,0x70,0x90,0xB0,0xD0,0xF0}
ABX_RD = {0xBD,0x7D,0xFD,0xDD,0x3D,0x1D,0x5D,0xBC}
ABY_RD = {0xB9,0x79,0xF9,0xD9,0x39,0x19,0x59,0xBE}
IZY_RD = {0xB1,0x71,0xF1,0xD1,0x31,0x11,0x51}

class ACPU(CPU):
    def step(self):
        irq_taken = self.irq_line and not self.i
        pc0 = self.pc; r = self.read
        op = r(pc0); x0 = self.x; y0 = self.y
        extra = 0
        if op in ABX_RD or op in ABY_RD:
            base = r((pc0+1)&0xFFFF) | (r((pc0+2)&0xFFFF) << 8)
            idx = x0 if op in ABX_RD else y0
            if ((base + idx) & 0xFF00) != (base & 0xFF00): extra = 1
        elif op in IZY_RD:
            z = r((pc0+1)&0xFFFF); base = r(z) | (r((z+1)&0xFF) << 8)
            if ((base + y0) & 0xFF00) != (base & 0xFF00): extra = 1
        c0 = self.cycles
        super().step()          # adds 3
        n = BASE.get(op, 2) + extra
        if op in BRANCH and not irq_taken:
            if self.pc != ((pc0 + 2) & 0xFFFF):
                n += 1
                if (self.pc & 0xFF00) != ((pc0 + 2) & 0xFF00): n += 1
        if irq_taken: n += 7
        self.cycles = c0 + n
        self.last_n = n

BT = 64                  # one DD MFM byte-time = 32 us = 64 cycles @ 2 MHz
REV = 6250               # byte-times per 200 ms revolution
def id_end_bt(r):        # stock 318045-02 layout: ID CRC complete, byte-time in rev
    return 32 + 609*(r-1) + 22

class WMachine(machmod.Machine):
    def __init__(self, **kw):
        super().__init__(**kw)
        self.cpu = ACPU(self.read, self.write)
        self.origin = 0          # cycle of index reference
        self.wp = False          # CIA PB6 / WD write protect input
        self.ev = []             # (cycle, kind, arg) scheduled WD events
        self.wop = None          # 'ws' | 'wt'
        self.dr = 0              # data register (host->WD)
        self.wgate = False
        self.w_lat_max = 0; self.w_lat_first = None; self.w_lat_hist = []
        self.w_buf = []; self.w_lost = 0
        self.wt_tokens = []; self.wt_tokcount = 0
        self.ops = []            # completed write ops summaries
        self.busy_drop_at = None
        self.gaps = []           # (cmd byte, cycles from previous busy drop, pc)
        self.unexpected_dr = 0
        self.fi_during_write = 0
        self.cmd_log = []        # (cyc, cmd, track, sector, dr, head, side, pc)
        self.index_count = 0
        self.rnf_sectors = set() # (cyl, side, r) that never present an ID (inject)
        self.ws_rnf_inject = set()
    # ---- rotation ----
    def pos_bt(self, cyc=None):
        if cyc is None: cyc = self.cyc
        return ((cyc - self.origin) // BT) % REV
    def next_time_at_bt(self, target_bt, not_before):
        # earliest cycle >= not_before whose position (in byte-times) == target_bt
        base = not_before - ((not_before - self.origin) % (REV*BT))
        t = base + target_bt*BT
        while t < not_before: t += REV*BT
        return t
    def next_id(self, r, not_before):
        return self.next_time_at_bt(id_end_bt(r), not_before)
    def next_any_id(self, not_before):
        best = None
        for r in range(1, 11):
            t = self.next_id(r, not_before)
            if best is None or t < best[0]: best = (t, r)
        return best
    # ---- run with accurate cycles ----
    def run(self, steps):
        for _ in range(steps):
            c0 = self.cpu.cycles
            self.cpu.step()
            self.tick_devices(self.cpu.cycles - c0)
    def tick_devices(self, n):
        super().tick_devices(n)
        self.w_tick()
    # ---- CIA PB6 write protect ----
    def cia_read(self, r):
        v = super().cia_read(r)
        if r == 1 and self.wp: v &= ~0x40
        return v
    # ---- WD front end ----
    def wd_busy(self):
        return 1 if self.wop is not None else super().wd_busy()
    wp_status = 0
    wp_busy_cycles = 40
    def wd_read(self, r):
        if r == 0 and (self.wop is not None or (self.cmd >> 4) in (0xA, 0xB, 0xF)):
            b7 = 0x80 if self.motor() else 0
            b6 = 0x40 if self.wp_status else 0
            b4 = 0x10 if self.rnf else 0
            b3 = 0x08 if self.crc else 0
            b2 = 0x04 if self.lost else 0
            b1 = 0x02 if self.drq else 0
            b0 = 1 if self.wop is not None else 0
            return b7|b6|b4|b3|b2|b1|b0
        return super().wd_read(r)
    def wd_write(self, r, v):
        if r == 3 and self.wop is not None:
            self.dr = v; self.wd_data_out = v
            if self.drq:
                self.drq = 0
                lat = self.cyc - self.drq_at
                if self.w_lat_first is None: self.w_lat_first = lat
                else:
                    self.w_lat_hist.append(lat)
                    if lat > self.w_lat_max: self.w_lat_max = lat
            else:
                self.unexpected_dr += 1
            return
        super().wd_write(r, v)
    def wd_command(self, v):
        top = v >> 4
        if self.wd_busy() and top != 0xD:
            self.dbg['busycmd'] += 1
            self.trace.append(('CMD-IGNORED', v, 'pc=%04X' % self.cpu.pc)); return
        if self.busy_drop_at is not None:
            self.gaps.append((v, self.cyc - self.busy_drop_at, self.cpu.pc))
        self.wp_status = 0
        self.cmd_log.append((self.cyc, v, self.wd_track, self.wd_sector, self.wd_data_in,
                             self.head, self.pa0_to_physside(), self.cpu.pc))
        if top in (0xA, 0xB):
            self.start_write_sector(v); return
        if top in (0xE, 0xF):
            if top == 0xF: self.start_write_track(v); return
        if top == 0xD and self.wop is not None:
            if self.wgate: self.fi_during_write += 1
            self.trace.append(('FI-DURING-WRITE-OP', self.wop, self.cpu.pc))
            self.ev = []; self.wop = None; self.wgate = False
            self.busy_until = self.cyc; return
        if top in (0x8, 0x9):
            # rotational timing for Read Sector (stock layout)
            self.cmd = v
            self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
            self.drq=0; self.lost=0; self.rnf=0; self.crc=0; self.deleted=0; self.dbg['presented']=0
            self.start_phys_op('rs')
            if self.ctrl_done_at is not None: return
            key = (self.head, self.pa0_to_physside(), self.wd_sector)
            if self.wd_track == self.head and key in self.disk and key not in self.rnf_sectors:
                t_id = self.next_id(self.wd_sector, self.cyc + 2*BT)
                lat = (t_id + 39*BT) - self.cyc
                self.staged = (self.cyc + lat, list(self.disk[key]))
                self.ctrl_rnf = 0; self.ctrl_crc = 0
                self.ctrl_done_at = self.cyc + lat + (512 + 2) * BT
            else:
                self.ctrl_rnf = 1; self.ctrl_crc = 0
                self.ctrl_done_at = self.cyc + 5*REV*BT
            return
        if top == 0xC:
            self.cmd = v
            self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
            self.drq=0; self.lost=0; self.rnf=0; self.crc=0; self.deleted=0; self.dbg['presented']=0
            self.start_phys_op('ra')
            if self.ctrl_done_at is not None: return
            t_id, rr = self.next_any_id(self.cyc + 2*BT)
            c = self.head; h = self.pa0_to_physside(); n = 2
            crc = machmod.crc16_ccitt([0xA1,0xA1,0xA1,0xFE,c,h,rr,n])
            self.ra_found_c = c
            lat = (t_id - 6*BT) - self.cyc    # bytes present as they arrive, CRC last
            if lat < BT: lat = BT
            self.staged = (self.cyc + lat, [c,h,rr,n,crc>>8,crc&0xFF])
            self.ctrl_rnf = 0; self.ctrl_crc = 0
            self.ctrl_done_at = self.cyc + lat + 7*BT
            self.trace.append(('RA', c, h, rr, 'lat=%d' % lat))
            return
        super().wd_command(v)
    def wd_finalize(self):
        super().wd_finalize()
        self.busy_drop_at = self.cyc
    # ---- write ops ----
    def _begin(self, kind, v):
        self.cmd = v; self.wop = kind
        self.drq = 0; self.lost = 0; self.rnf = 0; self.crc = 0; self.wp_status = 0
        self.w_lat_max = 0; self.w_lat_first = None; self.w_lat_hist = []
        self.w_buf = []; self.w_lost = 0; self.wgate = False
        self.op_start = self.cyc; self.op_cyl = self.head; self.op_side = self.pa0_to_physside()
        self.op_sector = self.wd_sector; self.op_track_reg = self.wd_track
        self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
    def sched(self, t, kind, arg=None):
        self.ev.append((t, kind, arg)); self.ev.sort()
    def start_write_sector(self, v):
        self._begin('ws', v)
        if self.wp:
            self.sched(self.cyc + self.wp_busy_cycles, 'ws_wp'); return
        key = (self.head, self.pa0_to_physside(), self.wd_sector)
        if self.wd_track != self.head or not (1 <= self.wd_sector <= 10) or key in self.ws_rnf_inject:
            self.sched(self.cyc + 5*REV*BT, 'ws_rnf'); return
        t_id = self.next_id(self.wd_sector, self.cyc + 2*BT)
        self.t_id = t_id
        self.sched(t_id + 2*BT, 'ws_drq1')
        self.sched(t_id + 11*BT, 'ws_check1')
    def start_write_track(self, v):
        self._begin('wt', v)
        self.wt_tokens = []; self.wt_tokcount = 0
        if self.wp:
            self.sched(self.cyc + self.wp_busy_cycles, 'ws_wp'); return
        self.sched(self.cyc + 1*BT, 'wt_drq1')
        self.sched(self.cyc + 4*BT, 'wt_check1')
    def end_op(self, status_note):
        op = dict(kind=self.wop, cmd=self.cmd, start=self.op_start, end=self.cyc,
                  cyl=self.op_cyl, side=self.op_side, sector=self.op_sector,
                  track_reg=self.op_track_reg, lost=self.lost, rnf=self.rnf,
                  wp=self.wp_status, note=status_note, first_lat=self.w_lat_first,
                  max_lat=self.w_lat_max, nbytes=len(self.w_buf),
                  data=bytes(self.w_buf), tokens=list(self.wt_tokens),
                  tokcount=self.wt_tokcount)
        self.ops.append(op)
        self.wop = None; self.wgate = False; self.ev = []
        self.busy_drop_at = self.cyc
        self.trace.append(('FIN', op['kind'], status_note))
    def w_tick(self):
        while self.ev and self.ev[0][0] <= self.cyc:
            t, kind, arg = self.ev.pop(0)
            getattr(self, 'ev_' + kind)(t, arg)
    # Write Sector events
    def ev_ws_wp(self, t, a):
        self.wp_status = 1; self.end_op('WP')
    def ev_ws_rnf(self, t, a):
        self.rnf = 1; self.end_op('RNF')
    def ev_ws_drq1(self, t, a):
        self.drq = 1; self.drq_at = t
    def ev_ws_check1(self, t, a):
        if self.drq:
            self.lost = 1; self.end_op('LOST-first-byte'); return
        self.sched(self.t_id + 22*BT, 'ws_wgate')
        self.sched(self.t_id + 38*BT, 'ws_xfer', 0)
    def ev_ws_wgate(self, t, a):
        self.wgate = True; self.wgate_on_at = t
    def ev_ws_xfer(self, t, k):
        # byte k moves DR -> DSR now; DRQ for byte k+1
        if self.drq:
            self.lost = 1; self.w_buf.append(0x00)
        else:
            self.w_buf.append(self.dr)
        if k < 511:
            self.drq = 1; self.drq_at = t
            self.sched(t + BT, 'ws_xfer', k + 1)
        else:
            self.sched(t + BT*(1 + 2 + 1), 'ws_done')   # last byte + CRC CRC + FF
    def ev_ws_done(self, t, a):
        key = (self.op_cyl, self.op_side, self.op_sector)
        self.disk[key] = bytearray(self.w_buf)
        self.wgate = False
        self.end_op('OK' if not self.lost else 'OK-with-LOST')
    # Write Track events
    def ev_wt_drq1(self, t, a):
        self.drq = 1; self.drq_at = t
    def ev_wt_check1(self, t, a):
        if self.drq:
            self.lost = 1; self.end_op('LOST-first-token'); return
        t_idx = self.next_time_at_bt(0, t)
        self.wt_index_at = t_idx
        self.sched(t_idx, 'wt_cons')
        self.sched(t_idx + REV*BT, 'wt_end')
    def ev_wt_cons(self, t, a):
        if self.wop != 'wt': return
        self.wgate = True
        if self.drq:
            self.lost = 1; tok = 0x00
        else:
            tok = self.dr
        self.wt_tokens.append(tok); self.wt_tokcount += 1
        self.drq = 1; self.drq_at = t
        nxt = t + (2*BT if tok == 0xF7 else BT)
        if nxt < self.wt_index_at + REV*BT:
            self.sched(nxt, 'wt_cons')
    def ev_wt_end(self, t, a):
        self.ev = [e for e in self.ev if e[1] != 'wt_cons']
        self.wgate = False
        # parse records -> disk
        toks = self.wt_tokens; i = 0; recs = []
        while i < len(toks) - 4:
            if toks[i] == 0xF5 and toks[i+1] == 0xF5 and toks[i+2] == 0xF5:
                if toks[i+3] == 0xFE:
                    c, h, r, n = toks[i+4:i+8]
                    recs.append(['ID', c, h, r, n, i]); i += 8; continue
                if toks[i+3] == 0xFB:
                    data = bytes(toks[i+4:i+4+512])
                    if recs and recs[-1][0] == 'ID':
                        c, h, r, n = recs[-1][1:5]
                        self.disk[(c, h, r)] = bytearray(data)
                        recs[-1] = ['REC', c, h, r, n, recs[-1][5], i]
                    i += 4 + 512; continue
            i += 1
        self.wt_records = recs
        self.end_op('OK' if not self.lost else 'OK-with-LOST')

def post_job(m, job, t, s, bufpage=3, slot=0):
    m.ram[0x0B + 2*slot] = t; m.ram[0x0C + 2*slot] = s
    m.ram[0x01F1 + slot] = bufpage
    m.ram[0x0002 + slot] = job

def run_until_idle(m, maxsteps, label, extra=5000):
    for chunk in range(maxsteps // 10000):
        m.run(10000)
        if all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy():
            m.run(extra)
            return True
    print('!! %s: did not go idle; pc=$%04X jobq %s' % (label, m.cpu.pc, ['%02X' % m.ram[2+i] for i in range(9)]))
    return False

def boot():
    m = WMachine()
    m.cpu.reset()
    m.run(3_000_000)
    m.ram[0x9C] = 0xFF   # hold the idle flush off until a scenario asks for it
    return m

def fmt_cmd(c):
    top = c >> 4
    names = {0x8:'RDSEC',0x9:'RDSEC',0xA:'WRSEC',0xB:'WRSEC',0xC:'RDADDR',0xD:'FORCEINT',0xE:'RDTRK',0xF:'WRTRK',
             0x0:'RESTORE',0x1:'SEEK',0x2:'STEP',0x3:'STEP',0x4:'STEPIN',0x5:'STEPIN',0x6:'STEPOUT',0x7:'STEPOUT'}
    return names.get(top, '?')

def rle(tokens):
    out = []; prev = None; n = 0
    for t in tokens:
        if t == prev: n += 1
        else:
            if prev is not None: out.append((prev, n))
            prev = t; n = 1
    if prev is not None: out.append((prev, n))
    return out
