import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off, QUIET
base = boot()
base.watch_pc = dict(WATCH); base.watch_pc.update({0xAFCA:'JNMI $AFCA', 0xAD3C:'NMI $AD3C', 0xAF24:'RESET $AF24', 0xB0F0:'JIDLE $B0F0'})
base.logging = True
m = copy.deepcopy(base)
idle_until_motor_off(m)
m.log.clear(); t0 = m.cyc
inject(m, 'UI', sa=15)
run_for(m, 4)
dump(m, t0, kinds=QUIET)
print('err text area:', bytes(m.ram[0x2D0:0x2F0]))
print('head', m.head, '$27', m.ram[0x27], '$95', m.ram[0x95])
