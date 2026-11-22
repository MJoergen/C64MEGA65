# Scenarios around the "$" request of MFCWT's check (stock ROM, or c1581.rom of the current directory).
#   B: cache on another track (a job on track 20), motor stopped, then "$"
#   C: a "$" that fails with 74 (READY forced low), then a second "$"
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *

QUIET = ('MOTOR', 'WD', 'JOB', 'EXAM', 'PC')

def idle_until_motor_off(m, limit=20):
    t0 = m.cyc
    while m.cyc - t0 < limit * CPS:
        m.run(10000)
        if not m.motor() and not m.wd_busy() and all(m.ram[2 + i] < 0x80 for i in range(9)): return True
    return False

def request(m, text, seconds=6, label=''):
    m.log.clear(); t0 = m.cyc
    inject(m, text)
    run_for(m, seconds)
    print('---- %s: "%s"  (error byte $02AB=%02X, head %d, $27=%d, $95=%d, $25=%d)' % (label, text, m.ram[0x2AB], m.head, m.ram[0x27], m.ram[0x95], m.ram[0x25]))
    dump(m, t0, kinds=QUIET)

if __name__ == '__main__':
    which = sys.argv[1] if len(sys.argv) > 1 else 'B'
    base = boot()
    base.watch_pc = WATCH; base.logging = True
    if which == 'B':
        m = copy.deepcopy(base)
        m.log.clear(); post_job(m, 0x80, 20, 0, bufpage=3, slot=0)
        run_until_idle(m, 20_000_000, 'T20')
        print('after T20 job: head', m.head, '$95', m.ram[0x95])
        idle_until_motor_off(m)
        request(m, '$', 4, 'B cache on T20, motor off')
    if which == 'C':
        m = copy.deepcopy(base)
        m.log.clear(); post_job(m, 0x80, 20, 0, bufpage=3, slot=0)
        run_until_idle(m, 20_000_000, 'T20')
        idle_until_motor_off(m)
        m.force_ready = 0
        request(m, '$', 3, 'C1 READY forced low')
        m.force_ready = None
        idle_until_motor_off(m)
        request(m, '$', 4, 'C2 second request, READY normal')
