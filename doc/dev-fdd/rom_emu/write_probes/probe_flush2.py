import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *
m = boot()
print('boot: $30=%02X $8D=%02X $9A=%02X $9B=%02X $9D=%02X $01FA=%02X $98=%02X $8F=%02X; cmd bytes 01DF..01E4: %s'
      % (m.ram[0x30], m.ram[0x8D], m.ram[0x9A], m.ram[0x9B], m.ram[0x9D], m.ram[0x1FA], m.ram[0x98], m.ram[0x8F], ' '.join('%02X' % m.ram[0x1DF+i] for i in range(6))))
for i in range(256): m.ram[0x300+i] = (i*7+3) & 0xFF
m.ram[0x95] = 0x80; m.ram[0x87] = 0
mark = len(m.cmd_log)
post_job(m, 0x90, 1, 0)
run_until_idle(m, 3_000_000, 'write job')
print('\nPHASE 1 write job T1/S0: result=%02X  $87=%02X $95=%02X $97=%02X  WD cmds: %s'
      % (m.ram[2], m.ram[0x87], m.ram[0x95], m.ram[0x97], [(fmt_cmd(c[1]), c[3]) for c in m.cmd_log[mark:]]))
assert m.ram[0x87] == 0x80
# PHASE 2 idle flush
m.ram[0x9C] = 0
mark = len(m.cmd_log); nops = len(m.ops); t0 = m.cyc
for _ in range(400):
    m.run(10000)
    if m.ram[0x87] == 0 and all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy() and 0xB0F0 <= m.cpu.pc <= 0xB17B:
        break
print('\nPHASE 2 idle flush: $87=%02X slots=%s' % (m.ram[0x87], ['%02X'%m.ram[2+i] for i in range(9)]))
first = m.cmd_log[mark][0]; last_end = max(o['end'] for o in m.ops[nops:])
print('   WD cmds: %s' % [(fmt_cmd(c[1]), '%02X'%c[1], c[3]) for c in m.cmd_log[mark:]])
print('   time first WD cmd -> last WRSEC busy drop: %.1f ms; -> idle: %.1f ms' % ((last_end-first)/2000.0, (m.cyc-first)/2000.0))
print('   gaps (busy drop -> next cmd):', [(fmt_cmd(g[0]), g[1]) for g in m.gaps if g[1] < 10000][-25:])
for op in m.ops[nops:]:
    print('   WRSEC cmd=%02X cyl=%d side=%d R=%2d trkreg=%d %s first_lat=%d cyc max_data_lat=%d cyc (%.1f us) lost=%d dur=%.2f ms data[0:3]=%s'
          % (op['cmd'], op['cyl'], op['side'], op['sector'], op['track_reg'], op['note'], op['first_lat'], op['max_lat'], op['max_lat']/2.0, op['lost'], (op['end']-op['start'])/2000.0, op['data'][:3].hex()))
cache = bytes(m.ram[0x0C00:0x2000])
print('   disk cyl0/side0 == cache: %s  lat hist (write loop) min/max: %d/%d cyc' % (all(bytes(m.disk[(0,0,r)]) == cache[(r-1)*512:r*512] for r in range(1,11)), min(min(o['max_lat'] for o in m.ops[nops:]), 99), max(o['max_lat'] for o in m.ops[nops:])))
# PHASE 3: P bit per cylinder: write to T2 (cyl1), T44 (cyl43), T45 (cyl44), T80 (cyl79)
for T, label in ((2,'cyl1'), (44,'cyl43'), (45,'cyl44'), (80,'cyl79')):
    m.ram[0x9C] = 0xFF
    post_job(m, 0x90, T, 0); run_until_idle(m, 6_000_000, 'write '+label)
    m.ram[0x9C] = 0; mark = len(m.cmd_log); nops = len(m.ops)
    for _ in range(600):
        m.run(10000)
        if m.ram[0x87] == 0 and all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy() and 0xB0F0 <= m.cpu.pc <= 0xB17B: break
    ws = [c for c in m.cmd_log[mark:] if (c[1]>>4) in (0xA,0xB)]
    print('PHASE 3 %s: WRSEC cmd bytes=%s  (P bit=%s) head=%d result slot7=%02X ops=%d' % (label, sorted(set('%02X'%c[1] for c in ws)), sorted(set((c[1]>>1)&1 for c in ws)), m.head, m.ram[9], len(m.ops)-nops))
# PHASE 4: extra revolution tolerance: delay sector 4's ID by one revolution
class Slow(WMachine):
    def next_id(self, r, not_before):
        t = super().next_id(r, not_before)
        if r == 4 and self.wop == 'ws': t += REV*BT
        return t
m2 = Slow(); m2.cpu.reset(); m2.run(3_000_000); m2.ram[0x9C] = 0xFF
for i in range(256): m2.ram[0x300+i] = i
m2.ram[0x95] = 0x80; m2.ram[0x87] = 0
post_job(m2, 0x90, 1, 0); run_until_idle(m2, 3_000_000, 'w')
m2.ram[0x9C] = 0; mark = len(m2.cmd_log); t0 = m2.cyc
for _ in range(600):
    m2.run(10000)
    if m2.ram[0x87] == 0 and all(m2.ram[2+i] < 0x80 for i in range(9)) and not m2.wd_busy() and 0xB0F0 <= m2.cpu.pc <= 0xB17B: break
print('\nPHASE 4 sector 4 write takes +1 revolution: $87=%02X ops=%s flush time %.0f ms (no DOS timeout)' % (m2.ram[0x87], [(o['sector'], o['note'], round((o['end']-o['start'])/2000.0)) for o in m2.ops], (m2.cyc-t0)/2000.0))
