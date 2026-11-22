# Full timeline of MFCWT's "UI" + "$" on the 1581 ROM (stock, or c1581.rom of the current directory):
# usage: exp7_timeline.py <t_first_ms> <delay_of_dollar_ms> [hold_ms] [lose] [head]
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off
tf = int(sys.argv[1]); dly = int(sys.argv[2])
hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0
lose = int(sys.argv[4]) if len(sys.argv) > 4 else 2
head = int(sys.argv[5]) if len(sys.argv) > 5 else 39
m = boot(); idle_until_motor_off(m)
m.head = head; m.wd_track = head; m.ram[0x27] = head
m.t_first = int(tf * MS); m.suppress_steps = True; m.suppress_hold = int(hold * MS); m.lose_in_steps = lose
m.watch_pc = {0xCDA8: 'job error 3 (readiness stage $CDA8)', 0xCD39: 'job error 3 ($CD08 exam before Read Address)',
              0xAFE6: 'UI finished: 73 message, back to idle', 0xCB0F: 'BUMP handler: Restore', 0xCE78: 'seek stage $CE78',
              0x98F7: '"$" load directory', 0xA7AE: 'DOS ERROR routine', 0xAFCA: 'UI: warm reset (JNMI $AFCA)'}
m.logging = True; m.log.clear()
print('# ROM=%s t_first=%d ms hold=%.0f lose=%d head=%d, "$" %d ms after UI' % (('stock' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory'), tf, hold, lose, head, dly))
inject(m, 'UI', sa=15)
t0 = m.cyc
while m.cyc - t0 < 3 * CPS:
    m.run(2000)
    if any(k == 'PC' and 'UI finished' in x for c, k, x in m.log[-10:]): break
run_for(m, dly / 1000.0)
inject(m, '$')
run_for(m, 1.0)
ons = [c for c, k, x in m.log if k == 'MOTOR' and x == 'ON']; tm = ons[0] if ons else t0
edges = [tm + m.t_first + k * m.rev_cyc for k in range(12)]
for c, k, x in m.log:
    if k == 'PC' and 'stage' in x and 'seek' not in x: continue
    if k == 'JOB' and 'job $8' in x and 'T=0' in x: continue
    if k == 'EXAM':
        x = 'PA1 READY exam pc=$CDBC.. %d reads, %d not ready -> %s' % (x[4], x[5], 'FAIL' if x[5] else 'pass')
    print('%8.1f  %8.1f  %-5s %s' % ((c - t0) / MS, (c - tm) / MS, k, x))
print('index edges (motor age ms):', ' '.join('%.0f%s' % ((e - tm) / MS, '(lost)' if m.suppressed(e) else '') for e in edges if e - tm < 2.5 * CPS))
