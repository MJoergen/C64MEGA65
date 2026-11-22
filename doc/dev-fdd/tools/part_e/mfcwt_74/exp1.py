import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
m = boot()
print('booted; motor', m.motor(), 'head', m.head, 'pc $%04X' % m.cpu.pc, 'job q', [hex(m.ram[2+i]) for i in range(9)])
m.watch_pc = WATCH; m.logging = True
t0 = m.cyc
inject(m, '$')
run_for(m, 4)
dump(m, t0)
print('err code $02AB=%02X  $7D=%02X  head=%d $27=%d' % (m.ram[0x2AB], m.ram[0x7D], m.head, m.ram[0x27]))
