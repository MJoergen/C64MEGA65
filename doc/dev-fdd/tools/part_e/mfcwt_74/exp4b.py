import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off, QUIET
base = boot(); base.logging = True
cands = [0x84E0,0x96DB,0xA7EA,0xB265,0xB383,0xB42F,0xB7FD,0xBCCB,0xBEEA,0x8F03,0x8EDC,0xB0A9,0xAFE6,0xB0F0,0xB137,0xB13B,0x926E,0x8EC5]
base.watch_pc = {a: 'pc $%04X' % a for a in cands}
m = copy.deepcopy(base); idle_until_motor_off(m)
m.log.clear(); t0 = m.cyc
inject(m, 'UI', sa=15)
run_for(m, 2.0)
last = None
for c, k, x in m.log:
    if k == 'PC' and x == last: continue
    if k in ('PC', 'JOB', 'MOTOR'): print('%9.2f ms %s %s' % ((c - t0) / MS, k, x)); last = x
