# 1581 machine model mirroring the C64MEGA65 phys-mode RTL semantics.
#
# WD1772 front end implements the round-10 DELIVERY v2 CONTRACT:
#   - disk-paced presentation (one byte per DD MFM byte-time = 32 us) from a
#     FIFO fed by the controller model; presentation never waits for
#     consumption; a missed byte is OVERWRITTEN and latches LOST DATA (bit2)
#   - DRQ and the error/LOST flags are cleared at command acceptance
#   - completion = controller done AND FIFO empty AND at least one full
#     byte-time after the last presentation (busy outlives the last DRQ)
#   - status never carries CRC(bit3) and RNF(bit4) together: CRC suppresses
#     RNF (the $CD5A table hole fix; see doc/dev-issue90/PLAN.md round 10)
#   - non-Force-Interrupt command writes while busy are IGNORED
#   - no unilateral not-ready completions: an op issued while the medium is
#     not ready completes via the controller's own bounded RNF-class result
# Type-I (seek/step) commands keep the simple timed model (unchanged by v2).
import sys, os
from cpu6502 import CPU

def _load_rom():
    # 1) explicit path on the command line, 2) c1581.rom in the CWD,
    # 3) convert the submodule's mif.hex (one hex byte per line) on the fly.
    cand = []
    if len(sys.argv) > 1 and sys.argv[1].lower().endswith('.rom'):
        cand.append(sys.argv[1])
    cand.append('c1581.rom')
    for p in cand:
        if os.path.exists(p):
            return open(p, 'rb').read()
    here = os.path.dirname(os.path.abspath(__file__))
    mif = os.path.join(here, '..', '..', '..', 'CORE', 'C64_MiSTerMEGA65',
                       'rtl', 'iec_drive', 'c1581_rom.mif.hex')
    with open(mif) as f:
        return bytes(int(line, 16) for line in f if line.strip())

ROM = _load_rom()

def crc16_ccitt(data, crc=0xFFFF):
    # true CCITT CRC; the ROM software-checks Read Address replies at $DA63
    # over A1 A1 A1 FE C H R N with this polynomial (preset $B230 after the
    # three A1 sync bytes and the FE mark) -- a fake CRC gives job error $09
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc

class Machine:
    def __init__(self, log_io=False):
        self.ram = bytearray(0x2000)
        self.log_io = log_io
        self.trace = []            # (what, detail) tuples
        self.cyc = 0
        # ---- physical drive model (mirrors controller + mechanism) ----
        self.head = 3              # real head cylinder at power-on
        self.disk_in = True
        self.chg_latch = True      # mechanism DSKCHG latch: set until step w/ disk
        self.motor_on_at = None
        self.ids_per_rev = 11      # 10 sectors + the truncated F011 R=11 ID
        self.rot = 0               # rotation position (ID index)
        # Media-state experiment controls.  Defaults preserve the historical
        # proof model.  Tests can lengthen cold readiness, enable the proposed
        # same-medium one-index shortcut, or force PA1/PA7 independently.
        self.ready_after_cycles = 60000
        self.ready_resume_after_cycles = None
        self.rotation_confirmed = False
        self.force_ready = None
        self.force_change = None
        self.media_log = False
        self.media_samples = []    # (cycle, PC, motor age, ready, change)
        # Rotational Read-Address model.  "simple" retains the old one-ID-per-
        # command behavior.  "f011" uses the source-derived auto-format byte
        # schedule: 6250 DD bytes/rev, first ID at byte 30, 587 bytes/record,
        # ten complete sectors plus the complete ID of sector 11 before index
        # truncates its data field.  Event positions are ID-end byte offsets.
        self.ra_layout = 'simple'
        self.f011_rev_bytes = 6250
        self.f011_id_end_bytes = tuple(40 + 587*i for i in range(11))
        self.f011_phase_origin = 0
        # ---- WD registers + delivery v2 engine (mirror fdc1772) ----
        # CPU runs at 2 MHz: one DD byte-time (32 us) = 64 CPU cycles.
        self.PACE = 64             # cycles per presented byte (contract A1/A2)
        self.T_LATENCY = 2000      # op accept -> first byte in the FIFO (scaled
                                   # rotational/decode latency; shape only)
        self.T_RNF = 100_000       # scaled stand-in: controller 5-index-edge
                                   # search bound -> RNF, zero bytes pushed
        self.T_NOTREADY = 150_000  # scaled stand-in: controller 1.1 s
                                   # not-ready bound -> RNF-class, zero bytes
        self.wd_track = 0; self.wd_sector = 0; self.wd_data_in = 0; self.wd_data_out = 0
        self.cmd = 0
        self.busy_until = 0        # Type-I timed model only
        self.phys_op = None        # 'rs' | 'ra' while a read op is in flight
        self.fifo = []             # controller->WD read FIFO (bytes pushed)
        self.staged = None         # (ready_at, [bytes]) not yet in the FIFO
        self.ctrl_done_at = None   # controller done (cycle time), None = no op
        self.ctrl_rnf = 0; self.ctrl_crc = 0
        self.drq = 0; self.lost = 0
        self.rnf = 0; self.crc = 0; self.deleted = 0
        self.ra_found_c = None     # Read Address: found C -> sector reg at finalize
        self.legacy_crc_rnf = False  # regression knob: emit the PRE-v2 crc+rnf pair
        self.next_present_at = 0   # pace counter (starts expired at op start)
        self.last_present_at = None
        # observability mirror (diag-counter shaped)
        self.dbg = dict(lost=0, busycmd=0, presented=0, fins=0,
                        max_consume_lat=0, present_gaps_min=None)
        # ---- CIA ----
        self.cia = bytearray(16)
        self.cia_pra_out = 0xFF; self.cia_prb_out = 0xFF
        self.cia_ddra = 0; self.cia_ddrb = 0
        self.cia_tod = 0
        self.cia_ta = 0xFFFF; self.cia_ta_latch=0xFFFF; self.cia_ta_run=0
        self.cia_tb = 0xFFFF; self.cia_tb_latch=0xFFFF; self.cia_tb_run=0
        self.cia_icr_mask = 0; self.cia_icr = 0
        # ---- VIA ----
        self.via = bytearray(16)
        self.via_t1 = 0xFFFF; self.via_t1_latch = 0xFFFF
        self.via_ifr = 0; self.via_ier = 0
        self.cpu = CPU(self.read, self.write)
        # disk image: minimal valid 1581 filesystem
        self.disk = {}
        self.build_disk()
    # ------------- disk content -------------
    def logical(self, t, s):  # logical T/S -> 256 bytes
        b = bytearray(256)
        if t==40 and s==0:
            b[0]=40; b[1]=3; b[2]=0x44; b[3]=0
            name=b'EMU DISK'
            for i in range(16): b[4+i]=0xA0
            b[4:4+len(name)]=name
            b[0x14]=0xA0; b[0x15]=0xA0
            b[0x16]=ord('4'); b[0x17]=ord('2'); b[0x18]=0xA0
            b[0x19]=ord('3'); b[0x1A]=ord('D'); b[0x1B]=0xA0; b[0x1C]=0xA0
        elif t==40 and s==1:
            b[0]=40; b[1]=2; b[2]=0x44; b[3]=0xBB; b[4]=ord('4'); b[5]=ord('2'); b[6]=0xC0
            for i in range(7,256): b[i]=0xFF   # all free-ish
        elif t==40 and s==2:
            b[0]=0; b[1]=0xFF; b[2]=0x44; b[3]=0xBB; b[4]=ord('4'); b[5]=ord('2'); b[6]=0xC0
            for i in range(7,256): b[i]=0xFF
        elif t==40 and s==3:
            b[0]=0; b[1]=0xFF                  # empty directory block
        return b
    def build_disk(self):
        for t in range(1,81):
            for s in range(40):
                cyl=t-1; side=0 if s<20 else 1
                pr=1+(s%20)//2; half=s&1
                key=(cyl,side,pr)
                if key not in self.disk: self.disk[key]=bytearray(512)
                self.disk[key][half*256:(half+1)*256]=self.logical(t,s)
    # ------------- helpers -------------
    def motor(self):  # CIA PA2 low = on
        return (self.cia_pra_eff()>>2)&1 == 0
    def side(self):   # CIA PA0
        return (self.cia_pra_eff())&1
    def cia_pra_eff(self):
        # output pins: driven where ddra=1, else pulled 1
        return (self.cia_pra_out | ~self.cia_ddra) & 0xFF
    def ready(self):
        # Abstract the controller's index qualification as a motor-age delay.
        # The default 60k stand-in is historical.  The optional shorter resume
        # delay models the proposed invariant: after a previously confirmed
        # rotation, and with no intervening disk change, one fresh index is
        # sufficient when the same motor is restarted.
        age = self.motor_on_time()
        change = self.change_asserted()
        if change:
            self.rotation_confirmed = False
        if self.force_ready is not None:
            value = bool(self.force_ready)
        else:
            delay = self.ready_after_cycles
            if (self.ready_resume_after_cycles is not None and
                self.rotation_confirmed and not change):
                delay = self.ready_resume_after_cycles
            value = age > delay
        if value and self.disk_in and not change:
            self.rotation_confirmed = True
        return value
    def change_asserted(self):
        return self.chg_latch if self.force_change is None else bool(self.force_change)
    def motor_on_time(self):
        if not self.motor(): self.motor_on_at=None; return 0
        if self.motor_on_at is None: self.motor_on_at=self.cyc
        return self.cyc - self.motor_on_at
    def do_step(self, outward):
        if outward: self.head=max(0,self.head-1)
        else: self.head=min(84,self.head+1)
        if self.disk_in: self.chg_latch=False
        self.trace.append(('STEP','out' if outward else 'in', self.head))
    # ------------- WD model (delivery v2) -------------
    def wd_busy(self):
        return 1 if (self.phys_op is not None or self.cyc < self.busy_until) else 0
    def wd_tick(self):
        # controller model: staged bytes become FIFO content at ready_at
        if self.staged is not None and self.cyc >= self.staged[0]:
            self.fifo.extend(self.staged[1]); self.staged = None
        if self.phys_op is None:
            return
        # presentation engine (contract A2/A3): runs on disk time only
        if self.cyc >= self.next_present_at:
            if self.fifo:
                if self.drq:
                    # previous byte never consumed: overwrite + LOST DATA
                    self.lost = 1; self.dbg['lost'] += 1
                self.wd_data_out = self.fifo.pop(0)
                self.drq = 1
                self.dbg['presented'] += 1
                self.last_present_at = self.cyc
                self.next_present_at = self.cyc + self.PACE
            elif (self.ctrl_done_at is not None and self.cyc >= self.ctrl_done_at):
                # done && FIFO empty && >= one byte-time after last presentation
                self.wd_finalize()
    def wd_finalize(self):
        if self.legacy_crc_rnf:
            self.rnf = self.ctrl_rnf; self.crc = self.ctrl_crc  # pre-v2 pair
        else:
            self.crc = self.ctrl_crc
            self.rnf = 1 if (self.ctrl_rnf and not self.ctrl_crc) else 0  # D2 belt
        if self.phys_op == 'ra' and self.ra_found_c is not None:
            self.wd_sector = self.ra_found_c   # Read Address epilogue
        self.dbg['fins'] += 1
        self.trace.append(('FIN', self.phys_op, self.dbg['presented'],
                           'rnf=%d crc=%d lost=%d' % (self.rnf, self.crc, self.lost)))
        if not self.rnf and not self.crc and self.disk_in and not self.change_asserted():
            self.rotation_confirmed = True
        self.phys_op = None; self.ctrl_done_at = None; self.ra_found_c = None
    def wd_read(self, r):
        if r==0:
            t1 = (self.cmd & 0x80)==0
            b7 = 0x80 if self.motor() else 0
            b6 = 0
            b5 = 0x20 if t1 and self.motor_on_time()>200000 else (0x20 if self.deleted and (self.cmd&0xE0)==0x80 else 0)
            b4 = 0x10 if self.rnf else 0
            b3 = 0x08 if self.crc else 0
            b2 = (0x04 if self.head==0 else 0) if t1 else (0x04 if self.lost else 0)
            b1 = (0x02 if True else 0) if t1 else (0x02 if self.drq else 0)
            b0 = self.wd_busy()
            return b7|b6|b5|b4|b3|b2|b1|b0
        if r==1: return self.wd_track
        if r==2: return self.wd_sector
        if r==3:
            if self.drq:
                self.drq = 0   # consumption clears DRQ; never drives completion
                if self.last_present_at is not None:
                    lat = self.cyc - self.last_present_at
                    if lat > self.dbg['max_consume_lat']:
                        self.dbg['max_consume_lat'] = lat
            return self.wd_data_out
        return 0xFF
    def wd_write(self, r, v):
        if r==0: self.wd_command(v)
        elif r==1: self.wd_track=v
        elif r==2: self.wd_sector=v
        elif r==3: self.wd_data_in=v; self.wd_data_out=v   # our readback fix
    def wd_command(self, v):
        top=v>>4
        if self.wd_busy() and top != 0xD:
            # contract B2: the real WD1772 ignores non-FI commands while busy
            self.dbg['busycmd'] += 1
            self.trace.append(('CMD-IGNORED', v, 'pc=%04X'%self.cpu.pc))
            return
        self.cmd=v
        self.trace.append(('CMD',v,self.wd_track,self.wd_sector,self.wd_data_in,self.head,'pc=%04X'%self.cpu.pc))
        # contract A6: command acceptance clears DRQ + status flags
        self.drq=0; self.lost=0; self.rnf=0; self.crc=0; self.deleted=0
        self.dbg['presented']=0
        if top==0x0:      # RESTORE
            self.wd_track=0xFF
            n=self.head
            for _ in range(n): self.do_step(True)
            self.wd_track=0
            self.busy_until=self.cyc+ max(1,n)*3000
        elif top==0x1:    # SEEK
            step_to=self.wd_data_in
            n=abs(self.wd_track-step_to)
            outward = step_to < self.wd_track
            for _ in range(n): self.do_step(outward)
            self.wd_track=step_to
            self.busy_until=self.cyc+max(1,n)*3000
        elif top in (0x2,0x3): # STEP (repeat last dir): model as inward
            self.do_step(False); self.busy_until=self.cyc+3000
            if v&0x10: self.wd_track=(self.wd_track+1)&0xFF
        elif top in (0x4,0x5): # STEP-IN
            self.do_step(False); self.busy_until=self.cyc+3000
            if v&0x10: self.wd_track=(self.wd_track+1)&0xFF
        elif top in (0x6,0x7): # STEP-OUT
            self.do_step(True); self.busy_until=self.cyc+3000
            if v&0x10: self.wd_track=(self.wd_track-1)&0xFF
        elif top in (0x8,0x9): # READ SECTOR
            self.start_phys_op('rs')
            if self.ctrl_done_at is not None: return   # not-ready path armed
            key=(self.head, self.pa0_to_physside(), self.wd_sector)
            if self.wd_track==self.head and key in self.disk:
                self.stage_read(key, list(self.disk[key]))
            else:
                # record not found: controller searches its index budget,
                # pushes nothing, completes rnf-only (contract D1)
                self.ctrl_rnf=1; self.ctrl_crc=0
                self.ctrl_done_at=self.cyc+self.T_RNF
        elif top==0xC:    # READ ADDRESS
            self.start_phys_op('ra')
            if self.ctrl_done_at is not None: return   # not-ready path armed
            if self.ra_layout == 'f011':
                rev_cycles = self.f011_rev_bytes * self.PACE
                phase = (self.cyc - self.f011_phase_origin) % rev_cycles
                next_pos = None
                rr = None
                for idx, byte_pos in enumerate(self.f011_id_end_bytes):
                    pos = byte_pos * self.PACE
                    if pos > phase:
                        next_pos = pos
                        rr = idx + 1
                        break
                if next_pos is None:
                    next_pos = self.f011_id_end_bytes[0] * self.PACE + rev_cycles
                    rr = 1
                latency = next_pos - phase
            else:
                self.rot=(self.rot+1)%self.ids_per_rev
                rr=self.rot+1
                latency = self.T_LATENCY
            c=self.head; h=self.pa0_to_physside(); n=2
            crc = crc16_ccitt([0xA1,0xA1,0xA1,0xFE,c,h,rr,n])
            self.ra_found_c=c
            self.staged=(self.cyc+latency, [c,h,rr,n,crc>>8,crc&0xFF])
            self.ctrl_rnf=0; self.ctrl_crc=0
            self.ctrl_done_at=self.cyc+latency+7*self.PACE
            self.trace.append(('RA',c,h,rr,'lat=%d'%latency))
        elif top==0xD:    # FORCE INTERRUPT: cancel path (kept by contract B2)
            self.fifo=[]; self.staged=None
            self.phys_op=None; self.ctrl_done_at=None
            self.busy_until=self.cyc
        elif top in (0xA,0xB): # WRITE SECTOR (blocked, read-only milestone)
            self.busy_until=self.cyc+2000
        elif top in (0xE,0xF): # READ/WRITE TRACK: finish
            self.busy_until=self.cyc+2000
    def start_phys_op(self, op):
        # contract A2: the pace counter starts EXPIRED at op start
        self.phys_op=op
        self.next_present_at=self.cyc
        self.last_present_at=None
        self.ctrl_done_at=None
        if not self.ready():
            # contract B1: no unilateral WD-side bailout -- the CONTROLLER
            # bounds not-ready and completes rnf-only with zero bytes pushed
            self.ctrl_rnf=1; self.ctrl_crc=0
            self.ctrl_done_at=self.cyc+self.T_NOTREADY
    def stage_read(self, key, data, crc_err=False, rnf=False):
        # test hook: override to inject truncation / error-flag scenarios;
        # the controller pushes `data` and completes with the given flags
        self.staged=(self.cyc+self.T_LATENCY, data)
        self.ctrl_rnf=1 if rnf else 0
        self.ctrl_crc=1 if crc_err else 0
        # done trails the payload by the two CRC byte-times (disk pace)
        self.ctrl_done_at=self.cyc+self.T_LATENCY+(len(data)+2)*self.PACE
    def pa0_to_physside(self):
        # PA0=0 (DOS logical side 0) -> f_side1 high -> head 0 (our FIXED mapping)
        return 0 if self.side()==0 else 1
    # ------------- CIA -------------
    def cia_read(self, r):
        if r==0:
            pa_in = 0xFF
            change = self.change_asserted()
            ready = self.ready()
            if change: pa_in &= ~0x80
            if ready:  pa_in &= ~0x02
            if self.media_log:
                self.media_samples.append((self.cyc, self.cpu.pc,
                                           self.motor_on_time(), ready, change))
            pa_in &= ~0x18     # drive number 00 -> bits 3,4 low
            return pa_in & self.cia_pra_eff()
        if r==1:
            prb_in = 0xFF & ~0x80  # ~ATN: ATN idle -> bit7=0
            prb_in &= ~0x04        # ~CLK idle
            prb_in &= ~0x01        # ~DATA idle
            # bit6 wps_n: not protected -> 1
            return prb_in & ((self.cia_prb_out | ~self.cia_ddrb)&0xFF)
        if r==2: return self.cia_ddra
        if r==3: return self.cia_ddrb
        if r==4: return self.cia_ta & 0xFF
        if r==5: return (self.cia_ta>>8)&0xFF
        if r==6: return self.cia_tb & 0xFF
        if r==7: return (self.cia_tb>>8)&0xFF
        if r==8: return self.cia_tod & 0xFF
        if r==9: return (self.cia_tod>>8)&0xFF
        if r==10: return (self.cia_tod>>16)&0xFF
        if r==13:
            v=self.cia_icr; self.cia_icr=0; return v
        return self.cia[r]
    def cia_write(self, r, v):
        if r==0: self.cia_pra_out=v
        elif r==1: self.cia_prb_out=v
        elif r==2: self.cia_ddra=v
        elif r==3: self.cia_ddrb=v
        elif r==4: self.cia_ta_latch=(self.cia_ta_latch&0xFF00)|v
        elif r==5: self.cia_ta_latch=(self.cia_ta_latch&0xFF)|(v<<8)
        elif r==6: self.cia_tb_latch=(self.cia_tb_latch&0xFF00)|v
        elif r==7: self.cia_tb_latch=(self.cia_tb_latch&0xFF)|(v<<8)
        elif r==8: self.cia_tod=(self.cia_tod&0xFFFF00)|v
        elif r==13:
            if v&0x80: self.cia_icr_mask|= v&0x7F
            else: self.cia_icr_mask &= ~(v&0x7F)
        elif r==14:
            self.cia[14]=v
            if v&0x10: self.cia_ta=self.cia_ta_latch
            self.cia_ta_run=v&1
        elif r==15:
            self.cia[15]=v
            if v&0x10: self.cia_tb=self.cia_tb_latch
            self.cia_tb_run=v&1
        else: self.cia[r]=v
    # ------------- VIA -------------
    def via_read(self, r):
        if r==4:
            self.via_ifr &= ~0x40
            return self.via_t1 & 0xFF
        if r==5: return (self.via_t1>>8)&0xFF
        if r==13: return self.via_ifr | (0x80 if (self.via_ifr & self.via_ier & 0x7F) else 0)
        if r==14: return self.via_ier|0x80
        if r in (0,15): return 0xFF
        if r==1: return 0xFF
        return self.via[r]
    def via_write(self, r, v):
        if r==4 or r==6: self.via_t1_latch=(self.via_t1_latch&0xFF00)|v
        elif r==5:
            self.via_t1_latch=(self.via_t1_latch&0xFF)|(v<<8)
            self.via_t1=self.via_t1_latch; self.via_ifr&=~0x40
        elif r==7: self.via_t1_latch=(self.via_t1_latch&0xFF)|(v<<8)
        elif r==13: self.via_ifr &= ~(v&0x7F)
        elif r==14:
            if v&0x80: self.via_ier |= v&0x7F
            else: self.via_ier &= ~(v&0x7F)
        else: self.via[r]=v
    # ------------- bus -------------
    def read(self, a):
        a&=0xFFFF
        if a<0x2000: return self.ram[a]
        if a<0x4000: return self.via_read(a&15)
        if a<0x6000: return self.cia_read(a&15)
        if a<0x8000: return self.wd_read(a&3)
        return ROM[a-0x8000]
    def write(self, a, v):
        a&=0xFFFF; v&=0xFF
        if a<0x2000: self.ram[a]=v; return
        if a<0x4000: self.via_write(a&15, v); return
        if a<0x6000: self.cia_write(a&15, v); return
        if a<0x8000: self.wd_write(a&3, v); return
    # ------------- run -------------
    def tick_devices(self, n):
        self.cyc += n
        self.wd_tick()
        self.cia_tod += n
        if self.cia_ta_run:
            self.cia_ta -= n
            if self.cia_ta <= 0:
                self.cia_ta += self.cia_ta_latch or 0x10000
                self.cia_icr |= 1
        if self.cia_tb_run:
            self.cia_tb -= n
            if self.cia_tb <= 0:
                self.cia_tb += self.cia_tb_latch or 0x10000
                self.cia_icr |= 2
        self.via_t1 -= n
        if self.via_t1 <= 0:
            self.via_t1 += (self.via_t1_latch or 0x10000)
            self.via_ifr |= 0x40
        irq = False
        if (self.cia_icr & self.cia_icr_mask): irq=True
        if (self.via_ifr & self.via_ier & 0x7F): irq=True
        self.cpu.irq_line = irq
    def run(self, steps):
        for _ in range(steps):
            self.cpu.step()
            self.tick_devices(3)
