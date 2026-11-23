# The READY rule against the genuine 1581 ROM (stock, or c1581.rom of the current directory):
# MFCWT's check, "UI" and then "$" 15 ms after the end of UI (the JiffyDOS bus), on a mechanism
# that withholds its index pulses while the head steps and for a hold time after the last step.
# Every exam of READY, inside UI and at the "$", is checked.
#
# usage: exp8_matrix.py <rule> <pace> <hold_ms> <head> <motor> <t_first_ms list> [lose] [dollar_ms]
#   rule     old | new                      (h257.py: the RTL before / after part E)
#   pace     rtl | rate | <ms>              (h257.py: 3.03 ms per step | the rate bits, 6 ms | fixed)
#   hold     the hold time of the mechanism after the BUSY time of a Type-I command (ms)
#   head     the cylinder of the head before UI
#   motor    stopped | run<n>               stopped: the motor stops before UI; run<n>: the motor runs
#                                           (a job on the next cylinder started it, as in exp5_sweep.py:
#                                           the head is then one cylinder further in, on 40 for 39), and
#                                           UI comes at n phases k/n of a revolution after an index edge
#   t_first  comma list or from:to:step     the time of the first index edge after motor-on (ms)
#   lose     inward steps a long Seek loses (default 2, the R6 of the record)
#   dollar   the time between the end of UI and the "$" (default 15 ms)
#
# One line per case: the exams of READY (motor age in ms, "!" = failed), the job errors 3 (74),
# and the verdict: "pass" (no exam failed) or "FAIL". The last line counts the failures.
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off

def tlist(a):
    if ':' in a:
        x, y, z = (int(v) for v in a.split(':'))
        return list(range(x, y + 1, z))
    return [int(v) for v in a.split(',')]

rule, pace_a, hold, head, motor = sys.argv[1], sys.argv[2], float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
tfs = tlist(sys.argv[6])
lose = int(sys.argv[7]) if len(sys.argv) > 7 else 2
dollar = float(sys.argv[8]) if len(sys.argv) > 8 else 15.0
pace = None if pace_a == 'rtl' else ('rate' if pace_a == 'rate' else float(pace_a))
rom = 'stock' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory'
WP = {0xCDA8: 'E3-readiness', 0xCD39: 'E3-CD08', 0xAFE6: 'UI-done', 0xA7AE: 'ERROR', 0x98F7: 'DIR'}

def setup(m, tf):
    m.t_first = int(tf * MS); m.suppress_steps = True; m.suppress_hold = int(hold * MS)
    m.lose_in_steps = lose; m.lose_min = 10; m.ready_rule = rule; m.pace = pace

# the machine before UI: booted, idle, motor stopped, head on its cylinder
base = boot()
base.watch_pc = WP
idle_until_motor_off(base)
base.head = head; base.wd_track = head; base.ram[0x27] = head

def run_case(tf, k, n):
    m = copy.deepcopy(base)
    setup(m, tf)
    m.logging = True; m.log.clear()
    if n:
        # the motor runs: a job on the next cylinder starts it (a job on the head's own track can
        # be served from the track cache without the disk), UI comes at phase k/n
        post_job(m, 0x80, head + 2 if head < 79 else head, 0, bufpage=3, slot=0)
        run_until_idle(m, 20_000_000, 'pre-job')
        e = m.last_edge(m.cyc)
        if e is None:
            return None, 'no index edge before UI'
        t = e + m.rev_cyc + (k * m.rev_cyc) // n
        while m.cyc < t: m.run(200)
        m.log.clear()
    t_ui = m.cyc
    inject(m, 'UI', sa=15)
    while m.cyc - t_ui < 4 * CPS:
        m.run(2000)
        if any(k2 == 'PC' and x == 'UI-done' for c, k2, x in m.log[-30:]): break
    n_ui = len(m.log)
    run_for(m, dollar / 1000.0)
    t_d = m.cyc
    inject(m, '$')
    # a "$" that needs the disk starts a job with the motor running, and its exam comes at
    # once; stop at the first read command after it, at a job error 3, or after 200 ms (a "$"
    # served from the track cache of the drive does not touch the disk)
    while m.cyc - t_d < 0.2 * CPS:
        m.run(2000)
        tail = m.log[n_ui:]
        if any(k2 == 'PC' and x.startswith('E3') for c, k2, x in tail if c >= t_d): break
        if any(k2 == 'WD' and ('RDSEC' in x or 'RDADDR' in x) for c, k2, x in tail if c >= t_d): break
    return m, (t_ui, t_d, n_ui)

nph = int(motor[3:]) if motor.startswith('run') else 0
cases = [(tf, k) for tf in tfs for k in (range(nph) if nph else [0])]
fails = 0
print('# rule=%s pace=%s hold=%.0fms head=%d motor=%s lose=%d "$"=%.0fms after UI ROM=%s'
      % (rule, pace_a, hold, head, motor, lose, dollar, rom), flush=True)
for tf, k in cases:
    tag = 't_first %4d ms' % tf + (' phase %d/%d' % (k, nph) if nph else '')
    m, info = run_case(tf, k, nph)
    if m is None:
        print('%s: %s' % (tag, info), flush=True); fails += 1; continue
    t_ui, t_d, n_ui = info
    ons = [c for c, k, x in m.log if k == 'MOTOR' and x == 'ON']
    offs = [c for c, k, x in m.log if k == 'MOTOR' and x == 'OFF']
    # times: motor age with the motor stopped before UI, time after UI with the motor running
    tm = (ons[-1] if ons else m.motor_on_at) if not nph else t_ui
    exams = [(c, x) for c, k, x in m.log if k == 'EXAM']
    e3 = [(c, x) for c, k, x in m.log if k == 'PC' and x.startswith('E3')]
    bad = [x for c, x in exams if x[5]]
    ex_s = ' '.join('%.0f%s' % ((c - tm) / MS, '!' if x[5] else '') for c, x in exams)
    e3_s = ' '.join('%s@%.0f%s' % (x[3:], (c - tm) / MS, '($)' if c >= t_d else '') for c, x in e3)
    steps = ' '.join(x.split()[0] + x.split(', ')[1].split()[0] for c, k, x in m.log
                     if k == 'WD' and ', ' in x and 'steps' in x and int(x.split(', ')[1].split()[0]) > 0)
    # what each rule says at the instants of the exams: the old rule the age of the last index edge,
    # the new one the settled time since then (READY falls at 500 ms)
    cnt = {r: [m.rule_state(c, r)[1] for c, x in exams] for r in ('old', 'new')}
    mx = {r: max([v for v in cnt[r] if v is not None] or [0]) / MS for r in cnt}
    v = 'FAIL' if bad or e3 else 'pass'
    fails += v == 'FAIL'
    print('%s: %s | trains: %s | exams (%s, ! failed): %s | 74: %s | at the exams, largest count of the old rule %.0f ms, of the new rule %.0f ms%s'
          % (tag, v, steps, 'ms after UI' if nph else 'motor age ms', ex_s, e3_s or '-', mx['old'], mx['new'],
             ' | the motor stopped and started again inside UI' if nph and offs else ''), flush=True)
print('# %d of %d cases with a failed exam' % (fails, len(cases)), flush=True)
