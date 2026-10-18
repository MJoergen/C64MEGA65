import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *

base = boot()
def dirty_cache(m):
    for i in range(256): m.ram[0x300+i] = (i*5+1) & 0xFF
    m.ram[0x9C] = 0xFF; m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, 0x90, 1, 0)
    run_until_idle(m, 3_000_000, 'write job')
    assert m.ram[0x87] == 0x80, 'cache not dirty?'

def flush(m, label, maxchunks=600):
    m.ram[0x9C] = 0
    mark = len(m.cmd_log); nops = len(m.ops); t0 = m.cyc
    for _ in range(maxchunks):
        m.run(10000)
        if m.ram[0x87] == 0 and all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy() and m.cpu.pc >= 0xB000 and m.cpu.pc < 0xB200:
            break
    m.run(20000)
    cmds = [(fmt_cmd(c[1]), c[1], c[3], c[7]) for c in m.cmd_log[mark:]]
    print('\n== %s: $87=%02X slots=%s $95=%02X took %.1f ms; pc=$%04X' % (label, m.ram[0x87], ['%02X'%m.ram[2+i] for i in range(9)], m.ram[0x95], (m.cyc-t0)/2000.0, m.cpu.pc))
    from itertools import groupby
    comp = [(k, len(list(g))) for k, g in groupby(cmds, key=lambda c: c[0])]
    print('   cmd summary:', comp)
    print('   write ops:', [(o['sector'], o['note']) for o in m.ops[nops:]])
    print('   job results seen (slot7 history):', m.job_hist if hasattr(m, 'job_hist') else '-')
    return cmds

# ---- E1: write protect asserted (CIA PB6) AFTER login -> WD status bit 6 path
m1 = copy.deepcopy(base)
dirty_cache(m1)
m1.wp = True
flush(m1, 'E1 WP via WD status during flush')
print('   $01FA=%02X (login WP flag, unchanged), DOS error channel code at $02A8=%02X' % (m1.ram[0x1FA], m1.ram[0x2A8]))

# ---- E2: RNF on sector 3 of the side (ID never found) during the flush
m2 = copy.deepcopy(base)
dirty_cache(m2)
m2.ws_rnf_inject.add((0, 0, 3))
flush(m2, 'E2 RNF on sector 3 (write)', maxchunks=1200)
m2.ws_rnf_inject.clear()

# ---- E3: verify mismatch: corrupt the disk copy of sector 5 right after it is written
class M3(WMachine):
    def ev_ws_done(self, t, a):
        super().ev_ws_done(t, a)
        if self.op_sector == 5 and not getattr(self, 'corrupted', False):
            self.disk[(0,0,5)][100] ^= 0xFF; self.corrupted = True
m3 = M3(); m3.cpu.reset(); m3.run(3_000_000)
dirty_cache(m3)
cmds = flush(m3, 'E3 verify mismatch on sector 5', maxchunks=1200)
print('   Force Interrupt issued:', [c for c in cmds if c[0] == 'FORCEINT'])
print('   trace FI entries:', [t for t in m3.trace if t[0] == 'FI-DURING-WRITE-OP'][:3])

# ---- E4: write protect at login -> $01FA, then a write job
m4 = copy.deepcopy(base)
m4.wp = True
m4.ram[0x95] = 0x80; m4.ram[0x87] = 0
mark = len(m4.cmd_log)
post_job(m4, 0xB6, 1, 0)
run_until_idle(m4, 1_000_000, 'B6')
print('\n== E4 job $B6 (CIA WP check) result=%02X  (stored to $01FA by the DOS level normally)' % m4.ram[2])
m4.ram[0x1FA] = m4.ram[2]
for i in range(256): m4.ram[0x300+i] = i
post_job(m4, 0x90, 1, 0)
run_until_idle(m4, 3_000_000, 'write with 01FA')
print('   write job result=%02X with $01FA=%02X ; WD cmds issued: %s' % (m4.ram[2], m4.ram[0x1FA], [fmt_cmd(c[1]) for c in m4.cmd_log[mark:]]))
