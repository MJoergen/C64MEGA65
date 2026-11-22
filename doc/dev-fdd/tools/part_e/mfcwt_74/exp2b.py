import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
m = M(); m.cpu.reset()
while m.cpu.pc != 0xB091: m.run(1)
m.logging = True
m.watch_pc = {0xC0EE: lambda s: 'C0EE A=%02X X=%02X' % (s.cpu.a, s.cpu.x), 0xC0F0: lambda s: 'mask $85=%02X idx $84=%02X' % (s.ram[0x85], s.ram[0x84]), 0xC104: lambda s: 'C104 $85=%02X' % s.ram[0x85]}
m.run(1200000)
seen=set()
for c,k,x in m.log:
    if k=='PC' and x not in seen: seen.add(x); print('%.2f'%((c)/MS), x)
