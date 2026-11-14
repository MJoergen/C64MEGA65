# Genuine-ROM proofs for issue #257 (hardware test of the physical 1581):
#   I  the first access after inserting a disk fails with 74,DRIVE NOT READY
#   R  ten Read Sectors of a track side cost ten revolutions (format: 6 min 43 s)
#   L  what the DOS does with its two LED lines (error blink)
#
# The genuine 318045-02 DOS ROM runs on the cycle-exact 6502 of
# wd_write_model.py. This file adds two things that the older models leave
# out because they did not matter for their questions:
#
#   * READY from index pulses. The controller derives READY (CIA PA1) from
#     the index pulses that arrive while the motor is on. The model takes the
#     time of the first index pulse after motor-on as a parameter (a property
#     of the mechanism) and the number of pulses that READY waits for as the
#     rule under test: 2 = the controller up to WIP-V6-A22X3 for a cold or
#     changed disk, 1 = the controller since the fix (and, before it, for an
#     unchanged disk). Type-I commands take the time they take in the RTL.
#
#   * The delivery of a Read Sector as the RTL does it. "live" is a real
#     WD1772 (and the model of wd_write_model.py): bytes are presented as they
#     come off the disk, BUSY drops after the data CRC. "quarantine" is
#     delivery v2 of fdc1772.v: nothing is presented before the controller's
#     verdict on the data CRC; then the sector is presented at disk pace
#     (512 x 32 us). "readahead" adds the controller's read-ahead buffer
#     (physical_1581_rdahead.vhd): after a clean Read Sector the sectors that
#     pass are captured; a Read Sector whose sector is in the buffer or on its
#     way into it is served from there.
#
# Usage: python3 -I run_257_proofs.py   (any CWD; ROM found automatically;
#        about 6 minutes). Must end with: RESULT: ALL 257 PROOFS PASS
import sys, os, copy
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import machine as machmod
from wd_write_model import WriteMachine, BT, REV, post_job, run_until_idle, fmt_cmd

CPS = 2_000_000                 # drive CPU cycles per second
FAIL = []
def check(name, cond, detail=''):
    tag = 'PASS' if cond else 'FAIL'
    if not cond: FAIL.append(name)
    print('%s  %s%s' % (tag, name, ('  [' + detail + ']') if detail else ''), flush=True)

SECTOR_BT = 609                 # stock layout: byte-times from one record to the next
DATA0_BT = 39                   # ID CRC end -> first data byte (22 gap + 12 x 00 + 3 x A1 + mark + 1)
FIELD_BT = 514                  # 512 data bytes + CRC
COPY_CYC = 334                  # read-ahead buffer -> read FIFO: 512 bytes at 16 clocks of 20 ns, + done gap

class M257(WriteMachine):
    def __init__(self, **kw):
        super().__init__(**kw)
        # ---- READY from index pulses ----
        self.t_first = int(0.30 * CPS)   # first index pulse after motor-on (cycles)
        self.rev_cyc = 398_660           # 199.33 ms: index period of the tester's drive (dump 10-pre)
        self.need = 1                    # index pulses READY waits for
        self.motor_log = []              # (cycle, 'on' | 'off')
        self._motor_prev = False
        self.pa1_samples = []            # (cycles since motor-on, ready) at the ROM's $CDBC exam
        self.step_busy = (6060, 8060)    # RTL: 3.03 ms same direction, 4.03 ms after a reversal
        self._last_out = None
        self.led_log = []                # (cycle, PA5, PA6)
        self._led_prev = None
        # ---- delivery ----
        self.delivery = 'live'
        self.ra_alive = False            # read-ahead engine armed
        self.ra_from = 0                 # ... since this cycle
        self.rs_log = []                 # (sector, 'live' | 'ahead', request cycle, done cycle)
    # ---------- motor, READY, LEDs ----------
    def cia_write(self, r, v):
        side0 = self.side()
        super().cia_write(r, v)
        m = self.motor()
        if m != self._motor_prev:
            self.motor_log.append((self.cyc, 'on' if m else 'off'))
            self._motor_prev = m
            self.motor_on_at = self.cyc if m else None
            if not m: self.ra_alive = False
        if self.side() != side0: self.ra_alive = False
        if r in (0, 2):
            pra = self.cia_pra_eff(); led = ((pra >> 5) & 1, (pra >> 6) & 1)
            if led != self._led_prev:
                self.led_log.append((self.cyc, led[0], led[1])); self._led_prev = led
    def index_pulses(self):
        if not self.motor() or self.motor_on_at is None or not self.disk_in: return 0
        age = self.cyc - self.motor_on_at
        return 0 if age < self.t_first else 1 + (age - self.t_first) // self.rev_cyc
    def ready(self):
        if self.force_ready is not None: return bool(self.force_ready)
        return self.index_pulses() >= self.need
    def cia_read(self, r):
        v = super().cia_read(r)
        if r == 0 and 0xCDBC <= self.cpu.pc <= 0xCDC6 and self.motor_on_at is not None:
            self.pa1_samples.append((self.cyc - self.motor_on_at, self.ready()))
        return v
    # ---------- commands ----------
    def wd_command(self, v):
        top = v >> 4
        if self.wd_busy() and top != 0xD:
            return super().wd_command(v)                 # ignored, as in the RTL
        if top in (0x8, 0x9) and self.delivery != 'live':
            return self.read_sector(v)
        self.ra_alive = False                            # every other command ends the read-ahead
        super().wd_command(v)
        if top in (0x4, 0x5, 0x6, 0x7):
            out = top in (0x6, 0x7)
            rev = self._last_out is not None and out != self._last_out
            self._last_out = out
            self.busy_until = self.cyc + (self.step_busy[1] if rev else self.step_busy[0])
        if top in (0x8, 0x9) and self.ctrl_done_at is not None and not self.ctrl_rnf:
            self.rs_log.append((self.wd_sector, 'live', self.cyc, self.ctrl_done_at))
    def read_sector(self, v):
        if self.busy_drop_at is not None:
            self.gaps.append((v, self.cyc - self.busy_drop_at, self.cpu.pc))
        self.cmd_log.append((self.cyc, v, self.wd_track, self.wd_sector, self.wd_data_in,
                             self.head, self.pa0_to_physside(), self.cpu.pc))
        self.cmd = v
        self.trace.append(('CMD', v, self.wd_track, self.wd_sector, self.wd_data_in, self.head, 'pc=%04X' % self.cpu.pc))
        self.drq = 0; self.lost = 0; self.rnf = 0; self.crc = 0; self.deleted = 0; self.dbg['presented'] = 0
        self.start_phys_op('rs')
        if self.ctrl_done_at is not None:                # not ready: the controller's bounded result
            self.ra_alive = False; return
        key = (self.head, self.pa0_to_physside(), self.wd_sector)
        if self.wd_track != self.head or key not in self.disk:
            self.ctrl_rnf = 1; self.ctrl_crc = 0
            self.ctrl_done_at = self.cyc + 5 * REV * BT
            self.ra_alive = False; return
        now = self.cyc
        t_id = self.next_id(self.wd_sector, now + 2 * BT)        # the live search needs a whole ID
        done = t_id + (DATA0_BT + FIELD_BT) * BT
        how = 'live'
        if self.delivery == 'readahead' and self.ra_alive:
            t_prev = t_id - REV * BT                               # the pass before that one
            overwritten = t_prev + (SECTOR_BT + DATA0_BT) * BT     # the next record's data starts
            if self.ra_from <= t_prev <= now < overwritten:
                done = max(now, t_prev + (DATA0_BT + FIELD_BT) * BT) + COPY_CYC
                how = 'ahead'
        if how == 'live':
            self.ra_from = done                                    # a clean live read arms the engine
        self.ra_alive = (self.delivery == 'readahead')
        self.staged = (done, list(self.disk[key]))                 # quarantine: nothing before the verdict
        self.ctrl_rnf = 0; self.ctrl_crc = 0
        self.ctrl_done_at = done
        self.rs_log.append((self.wd_sector, how, now, done))

def run_job_until_motor_off(m, job, trk, sec, limit_s=14):
    mark_c = len(m.cmd_log); mark_t = len(m.trace)
    m.motor_log.clear(); m.pa1_samples.clear()
    m.ram[0x95] = 0x80; m.ram[0x87] = 0                 # cold cache
    post_job(m, job, trk, sec)
    res = None; t0 = m.cyc
    while m.cyc - t0 < limit_s * CPS:
        m.run(10000)
        if res is None and m.ram[2] < 0x80: res = m.ram[2]
        if res is not None and not m.motor(): break
    return res, mark_c, mark_t

def run_job(m, job, trk, sec, limit_s=6):
    mark_c = len(m.cmd_log); mark_t = len(m.trace)
    m.motor_log.clear(); m.pa1_samples.clear()
    m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, job, trk, sec)
    t0 = m.cyc
    while m.cyc - t0 < limit_s * CPS:
        m.run(10000)
        if m.ram[2] < 0x80 and not m.wd_busy():
            m.run(20000); break
    return m.ram[2], mark_c, mark_t

def rw_cmds(m, mark):
    return [c for c in m.cmd_log[mark:] if (c[1] >> 4) in (0x8, 0x9, 0xA, 0xB, 0xC, 0xF)]
def steps(m, mark):
    return [c for c in m.cmd_log[mark:] if (c[1] >> 4) in (0x4, 0x5, 0x6, 0x7)]

# ---------------------------------------------------------------------------
print('booting the genuine ROM ...', flush=True)
base = M257()
base.cpu.reset()
base.run(3_000_000)                 # fixed boot budget (README gotcha 1)
base.ram[0x9C] = 0xFF               # hold the idle flush off
for _ in range(4000):               # the power-on activity ends, the motor stops
    base.run(10000)
    if not base.motor() and not base.wd_busy(): break
check('boot: the drive is idle and the motor is off', not base.motor() and not base.wd_busy())

def changed_disk(t_first_s, need):
    m = copy.deepcopy(base)
    m.chg_latch = True               # a disk was inserted while the motor was off
    m.t_first = int(t_first_s * CPS); m.need = need
    return m

# ================= I: the first access after inserting a disk =================
print('\n--- I: first access after inserting a disk (motor stopped, disk changed) ---', flush=True)
m = changed_disk(0.40, 1)
res, mc, mt = run_job(m, 0x80, 40, 0)
t_exam = m.pa1_samples[0][0] / CPS if m.pa1_samples else None
st = [fmt_cmd(c[1]) + ' $%02X' % c[1] for c in steps(m, mc)]
check('I1 the ROM examines READY once, 0.80 to 0.86 s after it switched the motor on, after one step pair',
      res == 0 and t_exam is not None and 0.80 <= t_exam <= 0.86 and st == ['STEPIN $48', 'STEPOUT $68'],
      'first PA1 read of $CDBC %.4f s after motor-on, steps %s, job %02X' % (t_exam or -1, st, res))
T_EXAM = t_exam

def outcome(t_first_s, need):
    m = changed_disk(t_first_s, need)
    res, mc, mt = run_job(m, 0x80, 40, 0)
    return res, len(steps(m, mc)), len(rw_cmds(m, mc))

a = outcome(0.62, 2); b = outcome(0.63, 2)
check('I2 two index pulses: a first pulse at 0.62 s is in time, at 0.63 s the job ends with error 3 (DOS 74) after one step pair and without any read or write command',
      a[0] == 0 and a[2] > 0 and b == (3, 2, 0), '0.62 s: job %02X, %d read commands; 0.63 s: job %02X, %d steps, %d read/write commands' % (a[0], a[2], b[0], b[1], b[2]))

m = changed_disk(0.65, 2)
res, mc, mt = run_job_until_motor_off(m, 0x80, 40, 0)
on = [e[0] for e in m.motor_log if e[1] == 'on']; off = [e[0] for e in m.motor_log if e[1] == 'off']
dur = (off[-1] - on[0]) if on and off else 0
pulses = 1 + (dur - m.t_first) // m.rev_cyc
check('I3 the failing access as the tester saw it: error 3, two steps, no read, and 53 index pulses while the motor is on (dumps "10-pre" and "FMT-0": +0x35)',
      res == 3 and len(steps(m, mc)) == 2 and len(rw_cmds(m, mc)) == 0 and pulses == 53,
      'job %02X, motor on for %.3f s, %d pulses with the first one at 0.65 s' % (res, dur / CPS, pulses))
DUR = dur
lo = (DUR - 53 * m.rev_cyc) / CPS; hi = (DUR - 52 * m.rev_cyc) / CPS
print('     53 pulses in %.3f s mean: first pulse later than %.3f s and not later than %.3f s after motor-on;' % (DUR / CPS, lo, hi))
print('     the job fails from 0.63 s on, so both failing accesses had their first pulse 0.63 to %.3f s after motor-on' % hi)

a = outcome(0.82, 1); b = outcome(0.83, 1); c = outcome(0.665, 1)
check('I4 one index pulse: a first pulse at 0.665 s (the upper bound of the two failing accesses) and even at 0.82 s is in time; 0.83 s is the limit of the ROM itself',
      c[0] == 0 and c[2] > 0 and a[0] == 0 and a[2] > 0 and b == (3, 2, 0),
      '0.665 s: job %02X; 0.82 s: job %02X; 0.83 s: job %02X' % (c[0], a[0], b[0]))

m = copy.deepcopy(base); m.t_first = int(0.40 * CPS); m.need = 1      # unchanged disk: no step pair
res, mc, mt = run_job(m, 0x80, 40, 0)
t_un = m.pa1_samples[0][0] / CPS if m.pa1_samples else None
check('I5 unchanged disk: no step pair, READY examined 0.79 to 0.82 s after motor-on',
      res == 0 and len(steps(m, mc)) == 0 and t_un is not None and 0.79 <= t_un <= 0.82,
      'first PA1 read %.4f s after motor-on' % (t_un or -1))

# ================= R: ten Read Sectors of a track side =================
print('\n--- R: reading a track side (cache fill of the DOS, job $80 on a cold cache) ---', flush=True)
fill = {}
for mode in ('live', 'quarantine', 'readahead'):
    m = copy.deepcopy(base); m.delivery = mode
    g0 = len(m.gaps)
    res, mc, mt = run_job(m, 0x80, 40, 3, limit_s=8)
    rs = [c for c in m.cmd_log[mc:] if (c[1] >> 4) in (0x8, 0x9)]
    t_first_rs = rs[0][0]; t_end = m.busy_drop_at
    ahead = sum(1 for e in m.rs_log if e[1] == 'ahead')
    exact = bytes(m.ram[0x0C00:0x2000]) == b''.join(bytes(m.logical(40, s)) for s in range(20))
    fill[mode] = dict(res=res, n=len(rs), ms=(t_end - t_first_rs) / 2000.0, ahead=ahead, exact=exact,
                      order=[c[3] for c in rs], gaps=[g for g in m.gaps[g0:]])
    print('     %-10s job %02X, %d Read Sectors %s, first command to last BUSY drop %7.1f ms = %.2f revolutions, served from the buffer: %d, cache byte-exact: %s'
          % (mode, res, len(rs), fill[mode]['order'], fill[mode]['ms'], fill[mode]['ms'] / 200.0, ahead, exact))
g = [x[1] for x in fill['quarantine']['gaps'] if (x[0] >> 4) in (0x8, 0x9)]
check('R1 the DOS issues the next Read Sector 66 to 95 us after the BUSY drop (2.2 to 2.3 ms after a Read Address)',
      len(g) == 10 and 4400 <= g[0] <= 4600 and all(130 <= x <= 190 for x in g[1:]),
      'cycles at 2 MHz: %s' % g)
check('R2 a real WD1772 ("live"): ten sectors in about one revolution', fill['live']['res'] == 0 and fill['live']['exact'] and fill['live']['ms'] < 260,
      '%.1f ms' % fill['live']['ms'])
check('R3 delivery v2 without read-ahead: every sector after the first waits for the next revolution (ten sectors: more than 9 revolutions)',
      fill['quarantine']['res'] == 0 and fill['quarantine']['exact'] and fill['quarantine']['ms'] > 9 * 200,
      '%.1f ms' % fill['quarantine']['ms'])
check('R4 with the read-ahead buffer: nine of ten sectors served from the buffer, ten sectors in about one revolution',
      fill['readahead']['res'] == 0 and fill['readahead']['exact'] and fill['readahead']['ahead'] == 9 and fill['readahead']['ms'] < 260,
      '%.1f ms' % fill['readahead']['ms'])

print('\n--- R: format, two cylinders (N0: = job $C0 + job $F0), verify after every Write Track ---', flush=True)
fmt = {}
for mode in ('live', 'quarantine', 'readahead'):
    m = copy.deepcopy(base); m.delivery = mode
    m.head = 3; m.wd_track = 3
    m.ram[0x8F] = 1                     # last cylinder := 1
    m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, 0xC0, 1, 0); run_until_idle(m, 2_000_000, 'restore job')
    saved = m.ram[0x9B]; m.ram[0x9B] = 0
    mc = len(m.cmd_log)
    post_job(m, 0xF0, 1, 0)
    ok = run_until_idle(m, 40_000_000, 'format job')
    m.ram[0x9B] = saved
    wt = [c[0] for c in m.cmd_log[mc:] if (c[1] >> 4) == 0xF]
    rs = [c for c in m.cmd_log[mc:] if (c[1] >> 4) in (0x8, 0x9)]
    # one side = from its Write Track to the next Write Track (sides 0/1 of cylinder 0, side 0 of cylinder 1)
    per_side = [(wt[i + 1] - wt[i]) / 2000.0 for i in range(len(wt) - 1)]
    per_cyl = (wt[2] - wt[0]) / 2000.0 if len(wt) >= 3 else 0
    blank = all(bytes(m.disk[(c, h, r)]) == bytes(512) for c in (0, 1) for h in (0, 1) for r in range(1, 11))
    fmt[mode] = dict(ok=ok, res=m.ram[2], wt=len(wt), rs=len(rs), per_cyl=per_cyl, blank=blank)
    print('     %-10s job %02X, %d Write Tracks, %d Read Sectors, one cylinder (two sides and the step) %7.1f ms -> 80 cylinders %5.1f s = %d min %02d s'
          % (mode, m.ram[2], len(wt), len(rs), per_cyl, per_cyl * 80 / 1000.0, int(per_cyl * 80 / 60000), int(per_cyl * 80 / 1000) % 60))
check('R5 format, delivery v2 without read-ahead: 80 cylinders take 6 to 7.5 minutes (the tester measured 6 min 43 s)',
      fmt['quarantine']['res'] == 1 and fmt['quarantine']['blank'] and 360 <= fmt['quarantine']['per_cyl'] * 80 / 1000 <= 450,
      '%.1f s' % (fmt['quarantine']['per_cyl'] * 80 / 1000))
check('R6 format with the read-ahead buffer: under two minutes, like a real WD1772',
      fmt['readahead']['res'] == 1 and fmt['readahead']['blank'] and fmt['readahead']['per_cyl'] * 80 / 1000 <= 120
      and abs(fmt['readahead']['per_cyl'] - fmt['live']['per_cyl']) <= 60,
      'read-ahead %.1f s, real chip %.1f s' % (fmt['readahead']['per_cyl'] * 80 / 1000, fmt['live']['per_cyl'] * 80 / 1000))

# ================= L: the LED lines =================
print('\n--- L: the LED lines of the DOS (CIA PA5 power LED, PA6 activity LED) ---', flush=True)
m = copy.deepcopy(base)
pra = m.cia_pra_eff()
check('L1 idle drive without an error: power LED lit, activity LED dark', (pra >> 5) & 1 == 1 and (pra >> 6) & 1 == 0)
mark = len(m.led_log); m.ram[0x02AB] = 0x50          # what the error routine $81F1 stores
t0 = m.cyc
while m.cyc - t0 < int(1.25 * CPS): m.run(5000)
tog = [e for e in m.led_log[mark:]]
d = [tog[i + 1][0] - tog[i][0] for i in range(len(tog) - 1)]
check('L2 an error is pending: the power LED toggles every 100.0 ms (every tenth 10 ms tick), the activity LED stays dark',
      len(tog) >= 12 and all(abs(x - 200_000) <= 20 for x in d) and all(e[2] == 0 for e in tog),
      '%d toggles, spacing %.3f to %.3f ms' % (len(tog), min(d) / 2000.0, max(d) / 2000.0))
while (m.cia_pra_eff() >> 5) & 1 == 1: m.run(1000)   # wait for a dark phase
mark = len(m.led_log); m.ram[0x02AB] = 0
t0 = m.cyc
while m.cyc - t0 < 2 * CPS: m.run(5000)
check('L3 the error is cleared in a dark phase: the DOS stops toggling and leaves the power LED dark',
      len(m.led_log) == mark and (m.cia_pra_eff() >> 5) & 1 == 0, 'transitions in the next 2 s: %d' % (len(m.led_log) - mark))
mark = len(m.led_log)
res, mc, mt = run_job(m, 0x80, 40, 0)
pw = [e for e in m.led_log[mark:] if e[1] != 0]
ac = [e for e in m.led_log[mark:] if e[2] == 1]
check('L4 a job without an error: the activity LED lights, the power LED does not toggle',
      res == 0 and len(ac) >= 1 and len(pw) == 0, 'job %02X, activity LED lit %d time(s)' % (res, len(ac)))

print()
if FAIL:
    print('RESULT: %d PROOF(S) FAILED: %s' % (len(FAIL), ', '.join(n.split()[0] for n in FAIL)))
    sys.exit(1)
print('RESULT: ALL 257 PROOFS PASS')
