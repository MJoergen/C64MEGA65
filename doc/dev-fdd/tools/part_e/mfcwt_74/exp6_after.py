# UI with a failing init (H1), then the "$" of MFCWT after a delay d ms: does it fail again?
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off, QUIET
tf = int(sys.argv[1]); delays = [int(x) for x in sys.argv[2].split(',')]
hold = float(sys.argv[3]) if len(sys.argv) > 3 else 0
base = boot(); idle_until_motor_off(base)
base.head = 39; base.wd_track = 39; base.ram[0x27] = 39
base.t_first = int(tf * MS); base.suppress_steps = True; base.suppress_hold = int(hold * MS); base.lose_in_steps = 2
base.watch_pc = {0xCDA8: 'E3-readiness', 0xCD39: 'E3-CD08', 0xAFE6: 'UI-done', 0xA7AE: 'ERROR', 0xB0F0: 'IDLE'}
base.logging = True
inject(base, 'UI', sa=15)
t0 = base.cyc
while base.cyc - t0 < 3 * CPS:
    base.run(2000)
    if any(k == 'PC' and x == 'IDLE' for c, k, x in base.log[-20:]): break
ons = [c for c, k, x in base.log if k == 'MOTOR' and x == 'ON']; tm = ons[-1]
print('UI done at motor age %.1f ms; error buffer: %r' % ((base.cyc - tm) / MS, bytes(base.ram[0x2D0:0x2F0]).split(b'\r')[0]))
for c, k, x in base.log:
    if k == 'PC' and x in ('E3-readiness', 'E3-CD08', 'ERROR', 'UI-done'): print('   %8.1f ms (age) %s' % ((c - tm) / MS, x))
edges = [tm + base.t_first + k * base.rev_cyc for k in range(12)]
print('   nominal index edges (age ms):', ' '.join('%.0f%s' % ((e - tm) / MS, '(lost)' if base.suppressed(e) else '') for e in edges if e - tm < 2.5 * CPS))
for d in delays:
    m = copy.deepcopy(base); m.log.clear()
    run_for(m, d / 1000.0)
    ta = m.cyc
    inject(m, '$')
    run_for(m, 1.5)
    f = [x for c, k, x in m.log if k == 'PC' and x.startswith('E3')]
    ex = [(c, x) for c, k, x in m.log if k == 'EXAM']
    print('"$" %4d ms after the end of UI (motor age %.0f): %s; first exam at age %.0f ms' % (d, (ta - tm) / MS, ('74 (' + f[0] + ')') if f else 'OK', (ex[0][1][2] / MS) if ex else -1))
