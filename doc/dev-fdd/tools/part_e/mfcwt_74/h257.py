# Harness for issue #257 part E: the genuine 1581 ROM (the stock ROM of the repo, or
# the file c1581.rom of the current directory, e.g. a JiffyDOS ROM) on the cycle-exact
# 6502 of wd_write_model.py, with
#   * READY as the RTL derives it (physical_1581_controller.vhd, block "motor /
#     readiness"), by one of two rules (ready_rule):
#       'old': true while the motor is on and the last index edge since motor-on
#              is less than 500 ms old (the RTL before the fix of part E);
#       'new': true while the motor is on, an index edge arrived since motor-on,
#              and the settled time since then is less than 500 ms: the time
#              from the start of a Type-I command with steps until 18 ms after
#              the trailing edge of its last step pulse (the RTL's step engine
#              busy or head_settled low) does not count, and the 500 ms start
#              anew at its end (the RTL of part E); an index edge counts also
#              during a step. The correspondence with the RTL is listed below.
#   * index edges from a mechanism model: first edge t_first after motor-on,
#     then every rev_cyc; optional suppression of edges during stepping and
#     for a hold time after the last step (hypothesis H1): an edge is lost
#     from the start of a Type-I command with steps until suppress_hold after
#     the end of its BUSY time;
#   * Type-I timing by one of three paces (pace):
#       None:   as the RTL of A25 does it: one step per controller acknowledge,
#               3.03 ms, 4.03 ms after a reversal (the WD step-rate bits are
#               ignored in phys_mode);
#       'rate': as the WD1772 and the RTL of part E (change 2) do it: the rate
#               bits of the command (00 6 ms, 01 12 ms, 10 2 ms, 11 3 ms), at
#               least the acknowledge time of the controller (3.03 ms, 4.03 ms
#               after a reversal); the 1581 ROM asks for 6 ms;
#       a number of milliseconds: every step takes that time, at least the
#               acknowledge time (for 12 ms: the pace the ROM asks for when its
#               probe of the CIA clock fails);
#     minimum busy 1.5 ms; optional lost inward steps (head short);
#   * injection of a DOS request ("$" on secondary address 0, or a command on
#     channel 15) at the DOS level: command buffer $0200, length $CD, $53/$52,
#     $7B = command waiting (the idle loop $B0F7 executes it through $8004);
#   * an event log: motor, every WD command with PC, every PA read of the
#     controller code with PC / motor age / READY / PA7, job posts and results.
#
# Correspondence of the 'new' rule with physical_1581_controller.vhd (2 MHz cycles
# here, 50 MHz there):
#   media_ready                  ready()
#   index_edge                   an edge of last_edge(): motor_on_at + t_first + k * rev_cyc,
#                                not suppressed (the 200 us filter of the RTL is part of t_first)
#   motor_s = '0' clears all     motor() false: READY false, motor_on_at restarts the edges
#   step_st /= SI_IDLE or        susp_windows: (start of the Type-I command, trailing edge of
#   head_settled = '0'           its last step pulse + G_SETTLE_CYC); the trailing edge is
#                                G_DIR_SETUP_CYC + G_STEP_LOW_CYC = 28 us after the request of
#                                its step, G_SETTLE_CYC = 18 ms; one window per command, since
#                                head_settled stays low between steps that follow each other
#                                within 18 ms (every pace here)
#   idx_gap_cnt held at 0        the count starts anew at the end of a window
#   2 * G_PERIOD_MAX_CYC         ready_timeout = 500 ms
#   idx_seen                     an edge since motor-on (last_edge not None), and no drop since
#                                that edge
# The RTL acts one 50 MHz clock after each event; the harness at the event itself.
import sys, os, copy
EMU = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'rom_emu')
sys.path.insert(0, EMU)
import machine as machmod
from wd_write_model import WriteMachine, BT, REV, post_job, run_until_idle, fmt_cmd

CPS = 2_000_000
MS = CPS // 1000

class M(WriteMachine):
    def __init__(s, **kw):
        super().__init__(**kw)
        s.t_first = int(0.635 * CPS)
        s.rev_cyc = 398_600
        s.ready_timeout = int(0.500 * CPS)
        s.suppress_steps = False
        s.suppress_hold = 0
        s.step_cyc = 6060; s.rev_step_cyc = 8060; s.t1_min = 3000
        s.lose_in_steps = 0        # inward steps lost by a Seek/Step-in train of >= lose_min steps
        s.lose_min = 10
        s.motor_on_at = None; s._motor_prev = False
        s.step_windows = []        # (start, end) cycles of Type-I activity
        s.last_out = None
        s.ev = s.ev if hasattr(s, 'ev') else []
        s.log = []                 # (cyc, kind, text)
        s.watch_pc = {}
        s.logging = False
        s.pa_burst = None
        s.settle_cyc = 18 * MS     # RTL head-settle: 18 ms from the trailing edge of the last step pulse
        s.pulse_cyc = 56           # RTL: request of a step to the trailing edge of its pulse (28 us)
        s.settle_until = 0
        s.ready_rule = 'old'       # 'old' or 'new' (see the header)
        s.pace = None              # None (RTL of A25), 'rate' (WD1772 rate bits) or milliseconds
        s.susp_windows = []        # (start, end) cycles: step engine busy or head not settled
    def L(s, kind, text):
        if s.logging: s.log.append((s.cyc, kind, text))
    # ---------------- motor / index / READY ----------------
    def cia_write(s, r, v):
        super().cia_write(r, v)
        m = s.motor()
        if m != s._motor_prev:
            s._motor_prev = m
            s.motor_on_at = s.cyc if m else None
            s.L('MOTOR', 'ON' if m else 'OFF')
    def suppressed(s, t):
        if not s.suppress_steps: return False
        for a, b in s.step_windows[-50:]:
            if a <= t <= b + s.suppress_hold: return True
        return False
    def last_edge(s, t):
        if s.motor_on_at is None or not s.disk_in: return None
        t0 = s.motor_on_at + s.t_first
        if t < t0: return None
        k = (t - t0) // s.rev_cyc
        while k >= 0:
            e = t0 + k * s.rev_cyc
            if not s.suppressed(e): return e
            k -= 1
            if t - (t0 + k * s.rev_cyc) > 4 * CPS: return None
        return None
    def rule_state(s, t, rule):
        """(READY, count in cycles) at time t of the current motor-on interval by a rule: 'old'
        counts the time since the last index edge, 'new' the settled time since then"""
        e = s.last_edge(t)
        if e is None: return False, None
        if rule == 'old':
            return (t - e) < s.ready_timeout, t - e
        # 'new': settled time since the last edge; a window holds the count at 0
        start = e
        for a, b in s.susp_windows[-50:]:
            if a > t: break
            if b <= start: continue
            if a - start >= s.ready_timeout: return False, a - start   # dropped before this window began
            if t < b: return True, 0                                   # inside a window: the count is held
            start = b                                                  # the count starts anew at its end
        return (t - start) < s.ready_timeout, t - start
    def ready(s):
        if s.force_ready is not None: return bool(s.force_ready)
        if not s.motor(): return False
        return s.rule_state(s.cyc, s.ready_rule)[0]
    def cia_read(s, r):
        v = super().cia_read(r)
        if r == 0 and s.logging and 0xC000 <= s.cpu.pc < 0xD000:
            pc = s.cpu.pc
            age = (s.cyc - s.motor_on_at) if s.motor_on_at is not None else -1
            rdy = int(not (v & 0x02)); chg = int(not (v & 0x80))
            if 0xCDBC <= pc <= 0xCDC8:          # the 30-read exam: one line per burst
                if s.pa_burst is None or s.cyc - s.pa_burst[0] > 2000:
                    s.pa_burst = [s.cyc, pc, age, rdy, 0, 0]
                    s.log.append((s.cyc, 'EXAM', s.pa_burst))
                s.pa_burst[4] += 1
                if not rdy: s.pa_burst[5] += 1
            elif pc not in (0xCE22, 0xCE27, 0xCE32, 0xCE35, 0xCE3C, 0xCE3F, 0xCFC9, 0xCFCD, 0xCBB4, 0xCBBD, 0xCBC6, 0xCBCF):
                s.log.append((s.cyc, 'PA', 'pc=$%04X age=%.1fms READY=%d PA7changed=%d'
                              % (pc, age / MS, rdy, chg)))
        return v
    # ---------------- Type I as the RTL does it ----------------
    RATE_MS = (6, 12, 2, 3)        # WD1772 step rates of the rate bits r1 r0
    def step_times(s, cmd):
        """cycles of a step and of the first step after a reversal for a Type-I command"""
        if s.pace is None:
            return s.step_cyc, s.rev_step_cyc
        ms = s.RATE_MS[cmd & 3] if s.pace == 'rate' else s.pace
        p = int(round(ms * MS))
        return max(s.step_cyc, p), max(s.rev_step_cyc, p)
    def do_steps(s, n, outward, cmd=0):
        t = s.cyc; first = True
        lost = 0
        step_cyc, rev_step_cyc = s.step_times(cmd)
        s.last_req = None
        if not outward and n >= s.lose_min: lost = min(s.lose_in_steps, n)
        for i in range(n):
            rev = s.last_out is not None and outward != s.last_out
            s.last_req = t
            t += rev_step_cyc if (first and rev) else step_cyc
            first = False
            s.last_out = outward
            if outward: s.head = max(0, s.head - 1)
            elif i < n - lost: s.head = min(84, s.head + 1)
            if s.disk_in: s.chg_latch = False
        return t
    def wd_command(s, v):
        top = v >> 4
        if top <= 7 and not s.wd_busy():
            s.cmd = v
            s.cmd_log.append((s.cyc, v, s.wd_track, s.wd_sector, s.wd_data_in, s.head, s.pa0_to_physside(), s.cpu.pc))
            s.drq = 0; s.lost = 0; s.rnf = 0; s.crc = 0; s.deleted = 0
            h0 = s.head; t0 = s.cyc
            if top == 0:
                n = s.head; end = s.do_steps(n, True, v); s.wd_track = 0
            elif top == 1:
                tgt = s.wd_data_in; n = abs(s.wd_track - tgt); out = tgt < s.wd_track
                end = s.do_steps(n, out, v); s.wd_track = tgt
            elif top in (2, 3):
                out = bool(s.last_out); n = 1; end = s.do_steps(1, out, v)
                if v & 0x10: s.wd_track = (s.wd_track + (-1 if out else 1)) & 0xFF
            elif top in (4, 5):
                n = 1; end = s.do_steps(1, False, v)
                if v & 0x10: s.wd_track = (s.wd_track + 1) & 0xFF
            else:
                n = 1; end = s.do_steps(1, True, v)
                if v & 0x10: s.wd_track = (s.wd_track - 1) & 0xFF
            end = max(end, t0 + s.t1_min)
            s.busy_until = end
            if n:
                s.step_windows.append((t0, end))
                s.settle_until = s.last_req + s.pulse_cyc + s.settle_cyc
                s.susp_windows.append((t0, s.settle_until))
            s.L('WD', '%-8s $%02X pc=$%04X TR=%d DR=%d head %d->%d, %d steps, busy %.2f ms'
                % (fmt_cmd(v), v, s.cpu.pc, s.cmd_log[-1][2], s.cmd_log[-1][4], h0, s.head, n, (end - t0) / MS))
            return
        if top >= 8:
            s.L('WD', '%-8s $%02X pc=$%04X TR=%d SR=%d head %d READY=%d'
                % (fmt_cmd(v), v, s.cpu.pc, s.wd_track, s.wd_sector, s.head, int(s.ready())))
        return super().wd_command(v)
    def next_id(s, r, not_before):
        return super().next_id(r, max(not_before, s.settle_until))
    def next_any_id(s, not_before):
        return super().next_any_id(max(not_before, s.settle_until))
    def wd_finalize(s):
        ph = s.phys_op
        super().wd_finalize()
        if ph == 'ra':
            s.L('WD', '  RA done: C=%d (status rnf=%d crc=%d)' % (s.wd_sector, s.rnf, s.crc))
    # ---------------- job queue and PC watch ----------------
    def write(s, a, v):
        a &= 0xFFFF
        if s.logging and 0x02 <= a <= 0x0A:
            slot = a - 2
            if v & 0x80:
                s.log.append((s.cyc, 'JOB', 'post slot %d job $%02X T=%d S=%d pc=$%04X' % (slot, v, s.ram[0x0B + 2 * slot], s.ram[0x0C + 2 * slot], s.cpu.pc)))
            elif s.ram[a] & 0x80:
                s.log.append((s.cyc, 'JOB', 'done slot %d result $%02X pc=$%04X' % (slot, v, s.cpu.pc)))
        super().write(a, v)
    def run(s, steps):
        cpu = s.cpu; wp = s.watch_pc
        for _ in range(steps):
            c0 = cpu.cycles
            cpu.step()
            s.tick_devices(cpu.cycles - c0)
            if wp and cpu.pc in wp and s.logging:
                s.log.append((s.cyc, 'PC', wp[cpu.pc](s) if callable(wp[cpu.pc]) else wp[cpu.pc]))

WATCH = {
    0xCD63: 'stage $CD63 motor-on', 0xCD7B: 'stage $CD7B readiness', 0xCD00: 'Read Address $CD00',
    0xCB0F: 'BUMP job handler $CB0F (Restore)', 0xCE78: 'seek stage $CE78', 0xC900: 'read job $C900',
    0xCB88: 'job error 2 at $CB88', 0xCD39: 'job error 3 at $CD39 ($CD08 exam failed)',
    0xCDA8: 'job error 3 at $CDA8 (readiness stage)', 0x9543: 'DOS posts BUMP after retries ($9543)',
    0xA7AE: 'DOS ERROR routine $A7AE', 0x98F7: 'load directory $98F7', 0x9678: 'OPEN $9678',
}

def boot(rom_env=None):
    m = M()
    m.cpu.reset()
    m.run(3_000_000)
    m.ram[0x9C] = 0xFF
    for _ in range(4000):
        m.run(10000)
        if not m.motor() and not m.wd_busy(): break
    return m

def inject(m, text, sa=0):
    b = text.encode('latin-1')
    for i, c in enumerate(b): m.ram[0x200 + i] = c
    m.ram[0xCD] = len(b)
    m.ram[0x53] = 0xF0 | sa
    m.ram[0x52] = sa
    m.ram[0x7B] = 1
    # the idle loop looks at $7B only when entered at $B0F0 (JMP $FF00 at the
    # end of an ATN sequence): steer it there at its loop top $B105
    for _ in range(200000):
        if m.cpu.pc == 0xB105:
            m.cpu.pc = 0xB0F0; return True
        m.run(1)
    raise RuntimeError('idle loop not reached')

def err_text(m):
    # the error buffer of the 1581 DOS: look for the "NN," message in RAM page 2/3
    return None

def run_for(m, seconds, stop=None):
    t0 = m.cyc
    while m.cyc - t0 < seconds * CPS:
        m.run(5000)
        if stop and stop(m): break

def dump(m, t0=None, kinds=None, file=sys.stdout):
    if t0 is None: t0 = m.log[0][0] if m.log else 0
    for c, k, x in m.log:
        if kinds and k not in kinds: continue
        if k == 'EXAM':
            x = 'READY exam pc=$%04X motor age %.1f ms: %d reads, %d not-ready -> %s' % (x[1], x[2] / MS, x[4], x[5], 'FAIL' if x[5] else 'pass')
        print('%9.2f ms  %-5s %s' % ((c - t0) / MS, k, x), file=file)
