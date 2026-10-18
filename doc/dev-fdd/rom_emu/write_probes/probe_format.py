import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wmachine import *

m = boot()
m.head = 3; m.wd_track = 3
print('boot ok pc=$%04X  $8F(last cyl)=%02X $9A(gap3)=%02X $9B(fill)=%02X $92/$93=%02X/%02X $94=%02X $91=%02X'
      % (m.cpu.pc, m.ram[0x8F], m.ram[0x9A], m.ram[0x9B], m.ram[0x92], m.ram[0x93], m.ram[0x94], m.ram[0x91]))
# emulate the NEW command's controller-level part ($8746): T=$90(=1)/S=0, job $C0 (restore), $9B=0, job $F0
m.ram[0x8F] = 1          # last cylinder := 1  -> format cylinders 0..1 only
m.ram[0x95] = 0x80; m.ram[0x87] = 0
mark = len(m.cmd_log)
post_job(m, 0xC0, 1, 0)
run_until_idle(m, 2_000_000, 'restore job')
print('restore result=%02X head=%d trkreg=%02X' % (m.ram[2], m.head, m.wd_track))
saved_9b = m.ram[0x9B]; m.ram[0x9B] = 0
t0 = m.cyc
post_job(m, 0xF0, 1, 0)
ok = run_until_idle(m, 12_000_000, 'format job')
m.ram[0x9B] = saved_9b
print('format job result=%02X  idle=%s  took %.1f ms emulated  head=%d' % (m.ram[2], ok, (m.cyc-t0)/2000.0, m.head))
print('\nWD command sequence (cyc, cmd, regs, gap):')
for c in m.cmd_log[mark:]:
    print('   cyc=%9d %-8s cmd=%02X trk=%02X sec=%02X dr=%02X head=%d side=%d pc=$%04X' % (c[0], fmt_cmd(c[1]), c[1], c[2], c[3], c[4], c[5], c[6], c[7]))
print('\ngaps busy-drop -> next cmd:')
for g in m.gaps:
    print('   %-8s %02X %6d cyc = %7.1f us pc=$%04X' % (fmt_cmd(g[0]), g[0], g[1], g[1]/2.0, g[2]))
print('\nWrite Track ops:')
for op in m.ops:
    if op['kind'] != 'wt': continue
    toks = op['tokens']
    r = rle(toks)
    print('  WRTRK cmd=%02X cyl=%d side=%d trkreg=%d note=%s first_lat=%s cyc max_tok_lat=%d cyc (%.1f us) lost=%d tokens=%d dur=%.1f ms'
          % (op['cmd'], op['cyl'], op['side'], op['track_reg'], op['note'], op['first_lat'], op['max_lat'], op['max_lat']/2.0, op['lost'], len(toks), (op['end']-op['start'])/2000.0))
    # describe first record and trailing filler
    def show(rl, n):
        return ' '.join(('%02X' % v) + ('x%d' % c if c > 1 else '') for v, c in rl[:n])
    print('     head of stream:', show(r, 14))
    # locate records
    nf7 = toks.count(0xF7); nf5 = toks.count(0xF5)
    # trailing 4E run
    trail = r[-1] if r else None
    # magnetic byte-times: F7 counts 2
    mag = sum(2 if t == 0xF7 else 1 for t in toks)
    last_f7 = len(toks) - 1 - toks[::-1].index(0xF7) if nf7 else -1
    mag_to_last_crc = sum(2 if t == 0xF7 else 1 for t in toks[:last_f7+1])
    print('     F5 count=%d (expect 60) F7 count=%d (expect 20) trailing run=%s  host tokens=%d  magnetic byte-times=%d  magnetic bt through last data CRC=%d'
          % (nf5, nf7, ('%02X x%d' % trail) if trail else None, len(toks), mag, mag_to_last_crc))
    recs = getattr(m, 'wt_records', None)
# per-record structure of the first write track
op = next(o for o in m.ops if o['kind'] == 'wt')
toks = op['tokens']; r = rle(toks)
print('\nfull RLE of first Write Track stream (first 40 runs):')
print('  ' + ' '.join(('%02X' % v) + ('x%d' % c if c > 1 else '') for v, c in r[:40]))
# ID fields written
ids = []
i = 0
while i < len(toks)-8:
    if toks[i:i+4] == [0xF5,0xF5,0xF5,0xFE]:
        ids.append(tuple(toks[i+4:i+8])); i += 8
    else: i += 1
print('ID fields (C,H,R,N):', ids)
# token service latency histogram summary for the data phase
print('\nverify pass after each side: Read Sector orders:')
seq = []
for c in m.cmd_log[mark:]:
    seq.append((fmt_cmd(c[1]), c[3]))
print([s for s in seq if s[0] in ('RDSEC','RDADDR','WRTRK','SEEK','RESTORE','STEPIN','STEPOUT')][:80])
print('unexpected DR writes=%d FI during write=%d' % (m.unexpected_dr, m.fi_during_write))
