#!/usr/bin/env python3
"""Issue #257, part E: what the genuine 1581 ROM (the stock ROM, or c1581.rom of
the current directory) does when one ID of a freshly written track cannot be found.

Uses doc/dev-fdd/rom_emu (run_257_proofs.M257 for READY from index pulses and the read-ahead
delivery). Experiments:
  F  format of cylinders 0..1 (job $C0 + $F0, verify after every Write Track),
     the ID of sector 7 of the second side of cylinder 1 unreadable after its
     Write Track: job code, commands after the failure, retries, motor time.
  L  cache fill (job $80) of a track side whose sector 7 ID is unreadable:
     job code, number of Read Sector attempts on sector 7, Restore/seek bumps.
Run: python3 -I -B exp_weak_id.py"""
import sys, os, copy, io, contextlib
HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'rom_emu')
sys.path.insert(0, HERE)

# import M257 and the booted base machine from the proofs file without running
# the proofs: execute only its definitions up to the boot.
src = open(os.path.join(HERE, 'run_257_proofs.py')).read()
cut = src.index('# ================= I: the first access')
ns = {'__name__': 'p257', '__file__': os.path.join(HERE, 'run_257_proofs.py')}
with contextlib.redirect_stdout(io.StringIO()):
    exec(compile(src[:cut], 'run_257_proofs_head', 'exec'), ns)
M257 = ns['M257']; base = ns['base']; post_job = ns['post_job']
run_until_idle = ns['run_until_idle']; fmt_cmd = ns['fmt_cmd']; CPS = ns['CPS']
import machine as machmod
print('ROM:', 'stock 318045-02' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory',
      ' $C160 =', ' '.join('%02X' % machmod.ROM[0xC160 - 0x8000 + k] for k in range(3)))

def cmds_after(m, mark):
    out = []
    for c in m.cmd_log[mark:]:
        out.append('%s t%d s%d side%d @%.3fs' % (fmt_cmd(c[1]), c[2], c[3], c[6], c[0] / CPS))
    return out

def motor_off_after(m, t0, limit_s=14):
    while m.cyc - t0 < limit_s * CPS:
        m.run(10000)
        if not m.motor():
            return (m.cyc - t0) / CPS
    return None

# ------------------------------------------------------------- F: format
m = copy.deepcopy(base); m.delivery = 'readahead'
m.head = 3; m.wd_track = 3
m.ram[0x8F] = 1                       # last cylinder := 1
m.ram[0x95] = 0x80; m.ram[0x87] = 0
post_job(m, 0xC0, 1, 0); run_until_idle(m, 2_000_000, 'restore job')
saved = m.ram[0x9B]; m.ram[0x9B] = 0
wt_count = [0]
orig_parse = m.parse_track
def parse_and_weaken():
    orig_parse()
    wt_count[0] += 1
    if wt_count[0] == 4:              # the Write Track of the second side of cylinder 1
        keys = [k for k in m.disk if k[0] == 1 and k[2] == 7]
        side_keys = [k for k in keys if k[1] == m.pa0_to_physside()]
        for k in side_keys:
            del m.disk[k]
        print('F: after Write Track #4 (cyl 1, phys side %d): removed %s' % (m.pa0_to_physside(), side_keys))
m.parse_track = parse_and_weaken
mc = len(m.cmd_log)
post_job(m, 0xF0, 1, 0)
t_job = m.cyc
res = None
while m.cyc - t_job < 60 * CPS:
    m.run(10000)
    if m.ram[2] < 0x80:
        res = m.ram[2]; break
t_res = m.cyc
print('F: format job result $%02X after %.2f s' % (res if res is not None else 0xFF, (t_res - t_job) / CPS))
cl = cmds_after(m, mc)
print('F: %d commands; last 8: %s' % (len(cl), cl[-8:]))
rs7 = [c for c in m.cmd_log[mc:] if (c[1] >> 4) in (0x8, 0x9) and c[3] == 7 and c[2] == 1]
print('F: Read Sector commands for cyl 1 sector 7: %d' % len(rs7))
mark = len(m.cmd_log)
off = motor_off_after(m, t_res)
print('F: motor switched off %.2f s after the job ended; commands in that time: %s' % (off if off is not None else -1, cmds_after(m, mark)))
m.ram[0x9B] = saved

# ------------------------------------------------------------- L: read a side
for mode in ('readahead',):
    m = copy.deepcopy(base); m.delivery = mode
    key = (40 - 1, 1, 7)
    keys = [k for k in m.disk if k[0] == 39 and k[2] == 7]
    print('L: disk keys for cyl 39 sector 7:', keys)
    side = None
    # job $80 on track 40 sector 3 (logical) as in proof R: which phys side?
    for k in keys[:1]:
        del m.disk[k]; side = k[1]
    mc = len(m.cmd_log)
    m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, 0x80, 40, 3)
    t_job = m.cyc; res = None
    while m.cyc - t_job < 120 * CPS:
        m.run(10000)
        if m.ram[2] < 0x80:
            res = m.ram[2]; break
    print('L: removed %s; job $80 result $%02X after %.2f s' % (keys[:1], res if res is not None else 0xFF, (m.cyc - t_job) / CPS))
    cl = [c for c in m.cmd_log[mc:]]
    rs7 = [c for c in cl if (c[1] >> 4) in (0x8, 0x9) and c[3] == 7]
    kinds = {}
    for c in cl:
        kinds[fmt_cmd(c[1])] = kinds.get(fmt_cmd(c[1]), 0) + 1
    print('L: commands by kind:', kinds, '; Read Sector of sector 7:', len(rs7))
    print('L: first 6 / last 6 commands:', cmds_after(m, mc)[:6], cmds_after(m, mc)[-6:])
