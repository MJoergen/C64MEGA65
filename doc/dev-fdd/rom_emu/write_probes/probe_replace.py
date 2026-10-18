import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *

m = boot()
for i in range(256): m.ram[0x300+i] = (i*3+9) & 0xFF
m.ram[0x95] = 0x80; m.ram[0x87] = 0
post_job(m, 0x90, 1, 0)
run_until_idle(m, 3_000_000, 'write job')
print('after write: $87=%02X $95=%02X $97=%02X head=%d' % (m.ram[0x87], m.ram[0x95], m.ram[0x97], m.head))
m.ram[0x9C] = 0xFF    # keep idle flush away (re-arm)
mark = len(m.cmd_log); t0 = m.cyc
post_job(m, 0x80, 2, 25)   # read logical T2 S25 -> cyl 1 side 1 -> replacement flush of cyl0/side0 first
run_until_idle(m, 6_000_000, 'read other track')
print('read job result=%02X $87=%02X $95=%02X $97=%02X head=%d took %.1f ms' % (m.ram[2], m.ram[0x87], m.ram[0x95], m.ram[0x97], m.head, (m.cyc-t0)/2000.0))
for c in m.cmd_log[mark:]:
    print('   cyc=%9d %-8s cmd=%02X trk=%02X sec=%02X dr=%02X head=%d side=%d pc=$%04X' % (c[0], fmt_cmd(c[1]), c[1], c[2], c[3], c[4], c[5], c[6], c[7]))
ok = all(bytes(m.disk[(0,0,r)]) is not None for r in range(1,11))
print('sector1 first half == pattern:', bytes(m.disk[(0,0,1)][:256]) == bytes((i*3+9)&0xFF for i in range(256)))
print('write ops:', [(o['sector'], o['note'], o['max_lat']) for o in m.ops])
print('gaps:', [(fmt_cmd(g[0]), g[1]) for g in m.gaps])
