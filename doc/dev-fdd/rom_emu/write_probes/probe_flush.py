import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *

m = boot()
print('boot pc=$%04X cyc=%d  $30=%02X $8D=%02X $9A=%02X $9B=%02X $9D=%02X $9C=%02X $01FA=%02X'
      % (m.cpu.pc, m.cyc, m.ram[0x30], m.ram[0x8D], m.ram[0x9A], m.ram[0x9B], m.ram[0x9D], m.ram[0x9C], m.ram[0x1FA]))
print('cmd bytes 01DF..01E4:', ' '.join('%02X' % m.ram[0x1DF+i] for i in range(6)))
# known pattern into buffer $0300
for i in range(256): m.ram[0x300+i] = (i*7+3) & 0xFF
m.ram[0x95] = 0x80; m.ram[0x87] = 0
mark = len(m.cmd_log)
post_job(m, 0x90, 1, 0)             # write logical T1 S0 -> cyl 0 side 0 phys sector 1 first half
run_until_idle(m, 3_000_000, 'write job')
print('write job result=%02X  dirty $87=%02X  $95=%02X $97=%02X  WD cmds so far:' % (m.ram[2], m.ram[0x87], m.ram[0x95], m.ram[0x97]))
for c in m.cmd_log[mark:]:
    print('   cyc=%9d %-8s cmd=%02X trk=%02X sec=%02X dr=%02X head=%d side=%d pc=$%04X' % (c[0], fmt_cmd(c[1]), c[1], c[2], c[3], c[4], c[5], c[6], c[7]))
# now the idle flush: force idle counter to 0 so $B151 calls $B15B
m.ram[0x9C] = 0
mark = len(m.cmd_log); nops = len(m.ops); t0 = m.cyc
for _ in range(400):
    m.run(10000)
    if m.ram[0x87] == 0 and all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy():
        break
m.run(20000)
print('\nIDLE FLUSH: $87=%02X  job slots=%s  took %d cycles (%.1f ms)' % (m.ram[0x87], ['%02X'%m.ram[2+i] for i in range(9)], m.cyc-t0, (m.cyc-t0)/2000.0))
print('WD command sequence during flush (cyc, cmd, regs, gap from previous busy drop):')
prev_end = None
for c in m.cmd_log[mark:]:
    gap = ''
    for g in m.gaps:
        pass
    print('   cyc=%9d %-8s cmd=%02X trk=%02X sec=%02X dr=%02X head=%d side=%d pc=$%04X pos_bt=%d' % (c[0], fmt_cmd(c[1]), c[1], c[2], c[3], c[4], c[5], c[6], c[7], m.pos_bt(c[0])))
print('\nbusy-drop -> next command gaps (cmd, cycles, us, pc):')
for g in m.gaps[-30:]:
    print('   %-8s %02X  %5d cyc = %6.1f us  pc=$%04X' % (fmt_cmd(g[0]), g[0], g[1], g[1]/2.0, g[2]))
print('\nWrite Sector ops:')
for op in m.ops[nops:]:
    print('   %s cmd=%02X cyl=%d side=%d R=%2d trkreg=%d note=%s first_lat=%s cyc  max_data_lat=%d cyc (%.1f us) lost=%d nbytes=%d dur=%d cyc (%.2f ms) data[0:4]=%s'
          % (op['kind'], op['cmd'], op['cyl'], op['side'], op['sector'], op['track_reg'], op['note'], op['first_lat'], op['max_lat'], op['max_lat']/2.0, op['lost'], op['nbytes'], op['end']-op['start'], (op['end']-op['start'])/2000.0, op['data'][:4].hex()))
# data check: cache vs disk
cache = bytes(m.ram[0x0C00:0x2000])
ok = all(bytes(m.disk[(0,0,r)]) == cache[(r-1)*512:r*512] for r in range(1,11))
print('\ndisk side (cyl0/side0) == cache (10x512): %s ; sector1 first half == pattern: %s' % (ok, bytes(m.disk[(0,0,1)][:256]) == bytes((i*7+3)&0xFF for i in range(256))))
print('unexpected DR writes=%d  FI during write=%d  lost events=%d  max consume lat (reads)=%d cyc' % (m.unexpected_dr, m.fi_during_write, sum(o['lost'] for o in m.ops), m.dbg['max_consume_lat']))
# verify-pass read sector order
rs = [c for c in m.cmd_log[mark:] if (c[1]>>4) in (8,9)]
print('verify Read Sector order:', [c[3] for c in rs], ' Read Address count:', len([c for c in m.cmd_log[mark:] if (c[1]>>4)==0xC]))
