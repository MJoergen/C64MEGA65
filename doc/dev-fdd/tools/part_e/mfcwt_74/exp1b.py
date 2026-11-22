import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
m = boot()
W2 = dict(WATCH); W2.update({0x8004:'cmd exec $8004', 0xB0FB:'idle sees $7B', 0x96B0:'$96B0', 0x82A2:'$82A2', 0x8627:'$8627',0x82ED:'$82ED',0xB17C:'$B17C',0x9071:'$9071', 0x959D:'post+wait $959D', 0xFF2D:'ERROR', 0x807C:'cmd error $807C'})
m.watch_pc = W2; m.logging = True
t0 = m.cyc
inject(m, '$')
run_for(m, 1.0)
dump(m, t0)
print('ram 0200:', bytes(m.ram[0x200:0x210]))
print('$7B=%02X $53=%02X $CD=%02X $50=%02X $02AB=%02X' % (m.ram[0x7B], m.ram[0x53], m.ram[0xCD], m.ram[0x50], m.ram[0x2AB]))
