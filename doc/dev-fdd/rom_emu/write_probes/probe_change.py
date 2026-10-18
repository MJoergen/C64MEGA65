import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *
# PA7 disk-change asserted right after the 2nd Write Sector of a flush begins; DOS never looks mid-loop
class Chg(WMachine):
    def start_write_sector(self, v):
        super().start_write_sector(v)
        n = len([o for o in self.ops if o['kind']=='ws'])
        if n == 1 and not getattr(self, 'fired', False):
            self.force_change = True; self.fired = True; self.change_at = self.cyc
m = Chg(); m.cpu.reset(); m.run(3_000_000); m.ram[0x9C] = 0xFF
for i in range(256): m.ram[0x300+i] = i
m.ram[0x95] = 0x80; m.ram[0x87] = 0
post_job(m, 0x90, 1, 0); run_until_idle(m, 3_000_000, 'w')
m.ram[0x9C] = 0; mark = len(m.cmd_log)
for _ in range(900):
    m.run(10000)
    if all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy() and 0xB0F0 <= m.cpu.pc <= 0xB17B and m.cyc > getattr(m,'change_at',0) + 2_000_000: break
print('PA7 change mid-flush: $87=%02X $95=%02X $25=%02X slot7=%02X  write ops=%s' % (m.ram[0x87], m.ram[0x95], m.ram[0x25], m.ram[9], [(o['sector'], o['note']) for o in m.ops]))
print('   cmds after change:', [(fmt_cmd(c[1]), c[3]) for c in m.cmd_log[mark:] if c[0] >= m.change_at][:40])
print('   steps after change:', [t for t in m.trace if t[0]=='STEP'][-6:])
