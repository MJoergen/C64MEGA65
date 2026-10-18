import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *
base = boot()
def dirty(m):
    for i in range(256): m.ram[0x300+i] = (i*5+1) & 0xFF
    m.ram[0x9C] = 0xFF; m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, 0x90, 1, 0); run_until_idle(m, 3_000_000, 'w'); assert m.ram[0x87] == 0x80
def flush(m, label, maxchunks=800):
    m.ram[0x9C] = 0; mark = len(m.cmd_log); nops = len(m.ops); t0 = m.cyc
    for _ in range(maxchunks):
        m.run(10000)
        if m.ram[0x87] == 0 and all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy() and 0xB0F0 <= m.cpu.pc <= 0xB17B: break
    from itertools import groupby
    cmds = [fmt_cmd(c[1]) for c in m.cmd_log[mark:]]
    print('== %s: $87=%02X $95=%02X took %.0f ms pc=$%04X' % (label, m.ram[0x87], m.ram[0x95], (m.cyc-t0)/2000.0, m.cpu.pc))
    print('   cmds:', [(k, len(list(g))) for k, g in groupby(cmds)])
    print('   write ops:', [(o['sector'], o['note'], o['nbytes']) for o in m.ops[nops:]])
m1 = copy.deepcopy(base); dirty(m1); m1.wp = True
flush(m1, 'E1 WP (WD status bit 6) during flush, busy held 40 cycles')
print('   $02A8=%02X  error-status string area $02D5..: %s' % (m1.ram[0x2A8], bytes(m1.ram[0x2D5:0x2E8])))
m2 = copy.deepcopy(base); dirty(m2); m2.wp = True; m2.wp_busy_cycles = 4
m2.ram[0x9C] = 0; t0 = m2.cyc
for _ in range(300):
    m2.run(10000)
print('== E1b WP termination with BUSY visible only 4 cycles: pc=$%04X after %.0f ms  (DOS stuck in $CBFA busy-wait? %s)' % (m2.cpu.pc, (m2.cyc-t0)/2000.0, 0xCBF8 <= m2.cpu.pc <= 0xCBFF))
# format on a WP disk
m3 = copy.deepcopy(base); m3.wp = True; m3.ram[0x8F] = 0
post_job(m3, 0xC0, 1, 0); run_until_idle(m3, 2_000_000, 'restore')
m3.ram[0x9B] = 0; mark = len(m3.cmd_log)
post_job(m3, 0xF0, 1, 0); run_until_idle(m3, 4_000_000, 'format wp')
print('== E5 format on WP disk: job result=%02X cmds=%s ops=%s' % (m3.ram[2], [fmt_cmd(c[1]) for c in m3.cmd_log[mark:]], [(o['kind'], o['note']) for o in m3.ops]))
