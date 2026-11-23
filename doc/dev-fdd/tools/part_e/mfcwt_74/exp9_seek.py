# One long seek of the 1581 DOS (stock ROM, or c1581.rom of the current directory) with the motor
# running, on a mechanism that withholds its index pulses while the head steps: a job on a track
# far from the head, posted at n phases of a revolution. The DOS seeks, waits, runs its readiness
# stage (exam of READY) and examines READY again before its Read Address. The claim of record
# section 8.2: with the READY rule of A25 ("old") a seek that lasts longer than 500 ms fails its
# exam, at 6 ms per step a seek across the disk (474 ms) almost always.
#
# usage: exp9_seek.py <rule> <pace> <hold_ms> <from_cyl> <to_track> <phases> [lose]
#   rule old | new, pace rtl | rate | <ms> (see exp8_matrix.py), hold after the BUSY time (ms),
#   from_cyl the cylinder of the head before the job, to_track the track of the job (1..80, the
#   cylinder is track - 1), phases the number of phases of the revolution at which the job is
#   posted (k / phases after an index edge), lose the inward steps a long Seek loses (default 0)
#
# One line per phase: the trains, the exams of READY (ms after the job was posted, ! failed), the
# job errors 3 (74) and the verdict. The last line counts the failures.
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off

rule, pace_a, hold = sys.argv[1], sys.argv[2], float(sys.argv[3])
cyl0, trk, nph = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
lose = int(sys.argv[7]) if len(sys.argv) > 7 else 0
pace = None if pace_a == 'rtl' else ('rate' if pace_a == 'rate' else float(pace_a))
rom = 'stock' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory'
WP = {0xCDA8: 'E3-readiness', 0xCD39: 'E3-CD08'}

base = boot()
base.watch_pc = WP
idle_until_motor_off(base)
base.head = cyl0; base.wd_track = cyl0; base.ram[0x27] = cyl0
base.t_first = int(0.62 * CPS); base.suppress_steps = True; base.suppress_hold = int(hold * MS)
base.lose_in_steps = lose; base.lose_min = 10; base.ready_rule = rule; base.pace = pace
# the motor runs: a job on the head's own track (no seek)
post_job(base, 0x80, cyl0 + 1, 0, bufpage=3, slot=0)
run_until_idle(base, 20_000_000, 'pre-job')
assert base.motor() and base.head == cyl0, 'the pre-job did not leave the motor on at the head'
e0 = base.last_edge(base.cyc)
assert e0 is not None, 'no index edge before the seek'

print('# rule=%s pace=%s hold=%.0fms seek from cylinder %d to track %d, %d phases, lose=%d ROM=%s'
      % (rule, pace_a, hold, cyl0, trk, nph, lose, rom), flush=True)
fails = 0
for k in range(nph):
    m = copy.deepcopy(base)
    t = e0 + m.rev_cyc + (k * m.rev_cyc) // nph
    while m.cyc < t: m.run(200)
    m.logging = True; m.log.clear()
    tp = m.cyc
    post_job(m, 0x80, trk, 0, bufpage=3, slot=0)
    while m.cyc - tp < 2 * CPS:
        m.run(2000)
        if any(k2 == 'PC' and x.startswith('E3') for c, k2, x in m.log): break
        if any(k2 == 'WD' and 'RDSEC' in x for c, k2, x in m.log): break
    exams = [(c, x) for c, k2, x in m.log if k2 == 'EXAM']
    e3 = [(c, x) for c, k2, x in m.log if k2 == 'PC' and x.startswith('E3')]
    bad = [x for c, x in exams if x[5]]
    steps = ' '.join(x.split()[0] + x.split(', ')[1].split()[0] + '(%s ms)' % x.split('busy ')[1].split()[0]
                     for c, k2, x in m.log if k2 == 'WD' and ', ' in x and 'steps' in x and int(x.split(', ')[1].split()[0]) > 0)
    cnt = {r: [m.rule_state(c, r)[1] for c, x in exams] for r in ('old', 'new')}
    mx = {r: max([v for v in cnt[r] if v is not None] or [0]) / MS for r in cnt}
    v = 'FAIL' if bad or e3 else 'pass'
    fails += v == 'FAIL'
    print('phase %2d/%d: %s | trains: %s | exams (ms after the job, ! failed): %s | 74: %s | at the exams, largest count of the old rule %.0f ms, of the new rule %.0f ms'
          % (k, nph, v, steps, ' '.join('%.0f%s' % ((c - tp) / MS, '!' if x[5] else '') for c, x in exams),
             ' '.join('%s@%.0f' % (x[3:], (c - tp) / MS) for c, x in e3) or '-', mx['old'], mx['new']), flush=True)
print('# %d of %d phases with a failed exam' % (fails, nph), flush=True)
