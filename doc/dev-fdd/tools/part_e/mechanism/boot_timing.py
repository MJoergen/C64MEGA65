#!/usr/bin/env python3
"""Run the genuine 1581 ROM boot in doc/dev-fdd/rom_emu (or a copy of it that holds another ROM as c1581.rom) and print every WD command with
its CPU cycle (2 MHz), the cycle at which the previous command's busy ended, and the gap.
Usage: python3 -I boot_timing.py <emu dir> [steps] [head0]"""
import sys
emu = sys.argv[1]
steps = int(sys.argv[2]) if len(sys.argv) > 2 else 3_000_000
sys.path.insert(0, emu)
import os
os.chdir(emu)
from machine import Machine
m = Machine()
if len(sys.argv) > 3:
    m.head = int(sys.argv[3])
log = []
orig = m.wd_command
def hooked(v):
    prev_busy_end = m.busy_until if hasattr(m, 'busy_until') else None
    t = m.cyc
    head_before = m.head
    orig(v)
    log.append((t, v, prev_busy_end, head_before, m.head, getattr(m, 'busy_until', None), m.wd_track, m.wd_data_in))
m.wd_command = hooked
m.cpu.reset()
try:
    m.run(steps)
except Exception as e:
    print("STOP:", e)
names = {0:'RESTORE',1:'SEEK',2:'STEP',3:'STEP',4:'STEPIN',5:'STEPIN',6:'STEPOUT',7:'STEPOUT',8:'RDSEC',9:'RDSEC',0xA:'WRSEC',0xB:'WRSEC',0xC:'RDADDR',0xD:'FORCEINT',0xE:'RDTRK',0xF:'WRTRK'}
prev_end = None
for (t, v, pbe, hb, ha, be, trk, dat) in log:
    gap = (t - pbe) / 2000.0 if pbe is not None else float('nan')
    print(f"t={t/2000.0:10.3f} ms cmd=${v:02X} {names[v>>4]:<8} head {hb:2d}->{ha:2d} wdtrk={trk:3d} data={dat:3d} "
          f"since_prev_busy_end={gap:8.3f} ms")
print("cycles run:", m.cyc)
