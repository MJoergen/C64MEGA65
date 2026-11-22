import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
m = M()
m.head = int(sys.argv[1]) if len(sys.argv) > 1 else 39; m.wd_track = 0
m.cpu.reset()
while m.cpu.pc != 0xB091: m.run(1)
m.watch_pc = WATCH; m.logging = True
t0 = m.cyc
for _ in range(1500):
    m.run(10000)
    if not m.motor() and not m.wd_busy() and m.cyc - t0 > 6 * CPS: break
dump(m, t0, kinds=('MOTOR','WD','JOB','EXAM','PC'))
print('end: head', m.head, '$27', m.ram[0x27], '$95', m.ram[0x95], 'cache side $96', m.ram[0x96], '$25', m.ram[0x25])
