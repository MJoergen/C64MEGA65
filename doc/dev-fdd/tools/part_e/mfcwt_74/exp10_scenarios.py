# The READY rule in other sequences of the 1581 DOS (stock ROM, or c1581.rom of the current
# directory), on a mechanism that withholds its index pulses from the start of a Type-I command
# until the hold time after its end:
#   power   the power-on initialization (the mechanism runs from the reset on)
#   uj      "UJ" (cold reset of the DOS) with the motor stopped, "$" 3 s later
#   bump    "$" with every sector of cylinder 39 giving a data CRC error: two retries, the bump
#           of the DOS (a Restore and a Seek), two more retries, error 20
#   seekw   motor running (a job on the next cylinder started it, so the head is on cylinder 1),
#           a write job on track 80 (a seek of 78 cylinders)
#   pull    as seekw with a read job, the disk taken out 200 ms after the job was posted, while
#           the head steps
# usage: exp10_scenarios.py <scenario> <rule> <pace> <hold_ms> <t_first_ms> [head]
#   rule old | new, pace rtl | rate | <ms> (h257.py), head default 39 (power, uj, bump) or 0
# One line: every exam of READY (ms after the start, ! = failed), the job errors 3, the marks
# (bump, the end of an initialization, the DOS error routine, the pull), and the largest count of
# either rule at the exams.
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off

scen, rule, pace_a, hold, tf = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), float(sys.argv[5])
head = int(sys.argv[6]) if len(sys.argv) > 6 else (0 if scen in ('seekw', 'pull') else 39)
pace = None if pace_a == 'rtl' else ('rate' if pace_a == 'rate' else float(pace_a))
rom = 'stock' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory'
WP = {0xCDA8: 'E3-readiness', 0xCD39: 'E3-CD08', 0xAFE6: 'init-done', 0xA7AE: 'ERROR',
      0xCB0F: 'BUMP'}

class MB(M):
    bad_cyl = None             # every Read Sector on this cylinder ends with a data CRC error
    def wd_command(s, v):
        super().wd_command(v)
        if (v >> 4) in (8, 9) and s.bad_cyl is not None and s.head == s.bad_cyl \
           and s.ctrl_done_at is not None and s.ctrl_rnf == 0:
            s.ctrl_crc = 1

def setup(m):
    m.t_first = int(tf * MS); m.suppress_steps = True; m.suppress_hold = int(hold * MS)
    m.lose_in_steps = 0; m.ready_rule = rule; m.pace = pace

def report(m, t0, label):
    exams = [(c, x) for c, k, x in m.log if k == 'EXAM']
    e3 = [(c, x) for c, k, x in m.log if k == 'PC' and x.startswith('E3')]
    marks = [(c, x) for c, k, x in m.log if (k == 'PC' and not x.startswith('E3')) or k == 'DISK']
    bad = [x for c, x in exams if x[5]]
    steps = ' '.join(x.split()[0] + x.split(', ')[1].split()[0] for c, k, x in m.log
                     if k == 'WD' and ', ' in x and 'steps' in x and int(x.split(', ')[1].split()[0]) > 0)
    cnt = {r: [m.rule_state(c, r)[1] for c, x in exams] for r in ('old', 'new')}
    mx = {r: max([v for v in cnt[r] if v is not None] or [0]) / MS for r in cnt}
    print('%s: %s | trains: %s | exams (ms after the start, ! failed): %s | 74: %s | marks: %s | largest count at an exam, old rule %.0f ms, new rule %.0f ms'
          % (label, 'FAIL' if bad or e3 else 'pass', steps or '-',
             ' '.join('%.0f%s' % ((c - t0) / MS, '!' if x[5] else '') for c, x in exams) or '-',
             ' '.join('%s@%.0f' % (x[3:], (c - t0) / MS) for c, x in e3) or '-',
             ' '.join('%s@%.0f' % (x.replace(' ', '-'), (c - t0) / MS) for c, x in marks) or '-',
             mx['old'], mx['new']), flush=True)

print('# scenario=%s rule=%s pace=%s hold=%.0fms t_first=%.0fms head=%d ROM=%s'
      % (scen, rule, pace_a, hold, tf, head, rom), flush=True)
if scen == 'power':
    m = MB(); setup(m); m.watch_pc = WP; m.logging = True
    m.head = head
    m.cpu.reset()
    t0 = m.cyc
    run_for(m, 6.0)
    report(m, t0, 'power-on, head on %d' % head)
    sys.exit(0)

base = boot()
base.watch_pc = WP
idle_until_motor_off(base)
base.head = head; base.wd_track = head; base.ram[0x27] = head
m = copy.deepcopy(base)
m.__class__ = MB
setup(m)
m.logging = True; m.log.clear()
if scen == 'uj':
    t0 = m.cyc
    inject(m, 'UJ', sa=15)
    run_for(m, 3.0)
    inject(m, '$')
    run_for(m, 0.4)
    report(m, t0, 'UJ, then "$" 3 s later')
elif scen == 'bump':
    # the track cache has to hold another track: a job on track 20 first (as exp3.py B)
    m.logging = False
    post_job(m, 0x80, 20, 0, bufpage=3, slot=0)
    run_until_idle(m, 20_000_000, 'T20')
    idle_until_motor_off(m)
    m.logging = True; m.log.clear()
    m.bad_cyl = 39
    t0 = m.cyc
    inject(m, '$')
    run_for(m, 12.0, stop=lambda mm: any(k == 'PC' and x == 'ERROR' for c, k, x in mm.log[-20:]))
    report(m, t0, '"$" with data CRC errors on cylinder 39')
elif scen in ('seekw', 'pull'):
    # the motor runs: a job on the next cylinder started it
    post_job(m, 0x80, head + 2, 0, bufpage=3, slot=0)
    run_until_idle(m, 20_000_000, 'pre-job')
    m.log.clear()
    t0 = m.cyc
    h0 = m.head
    if scen == 'seekw':
        post_job(m, 0x90, 80, 0, bufpage=3, slot=0)
        run_until_idle(m, 40_000_000, 'write job')
        run_for(m, 1.0)
        report(m, t0, 'write job on track 80, head on %d before it' % h0)
    else:
        post_job(m, 0x80, 80, 0, bufpage=3, slot=0)
        while m.cyc - t0 < int(200 * MS): m.run(200)
        m.disk_in = False
        run_until_idle(m, 40_000_000, 'job after the pull')
        run_for(m, 1.0)
        print('job result $%02X, change line %d, READY %d' % (m.ram[2], int(m.chg_latch), int(m.ready())), flush=True)
        report(m, t0, 'read job on track 80, head on %d before it, disk taken out 200 ms after the job was posted' % h0)
