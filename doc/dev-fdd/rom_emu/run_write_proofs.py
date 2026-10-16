# Genuine-ROM WRITE proofs and fixtures for the physical 1581 (issue #244, M2).
# Grown from the planning probes of 2026-10-15 (write_probes/probe_flush2.py,
# probe_format.py, probe_errors.py, probe_wp.py of the controller session).
#
# Runs the genuine 318045-02 DOS ROM on the cycle-exact 6502 of
# wd_write_model.py against the M2 WD write front end (FIFO-room DRQ, first-byte
# rule, sticky LOST DATA, write-protect pre-check, minimum BUSY, status purity)
# and proves:
#   W-FLUSH   the idle side flush of a dirty cache: Read Address, ten Write
#             Sectors R+1..10,1..R, verify (Read Address + ten Read Sectors),
#             disk byte-exact against the cache, no LOST DATA, no drops, no
#             first-byte abort; the inter-command gaps and DRQ-to-data
#             latencies are recorded
#   W-PBIT    the P bit per cylinder: set on 0 and 44..79, clear on 1..43
#   W-FORMAT  N0: (job $C0 + job $F0 on cylinders 0..1): one Write Track per
#             side, token stream 32 x 4E + ten records + 4E fill, F5 x 60 and
#             F7 x 20 per side, every ID field C,H,R,2, the verify pass reads
#             zeros back, job OK
#   W-WP      the tab closed after login: every flush attempt is Read Address,
#             Read Address, Write Sector -> status bit 6 ALONE (BUSY held for
#             the 1.5 ms minimum), three attempts, then DOS error 26 (the
#             error channel reads "26, WRITE PROTECT ON")
#   W-RNF     a sector whose ID is never found: RNF alone, three attempts,
#             then DOS error 20
#   W-LOST    a Write Sector completing with LOST DATA (status bit 2): the
#             $CD3F epilogue takes BCS $CD53, skips the PLP that balances its
#             PHP and its RTS MISRETURNS -- the shipped-ROM defect of P-D1, here
#             on the write path. Run last (it derails the DOS).
# and writes the fixtures for the controller testbenches:
#   fixtures/write_back_order.json   per flush: commands, sector order, gaps,
#                                    latencies, P bit, verify pass
#   fixtures/format_tokens.bin       the token stream of cylinder 0 side 0 as
#                                    the DOS wrote it, first DRQ to ending index
#   fixtures/format_tokens.json      sidecar: per-token DRQ latency and fate,
#                                    F7 positions, counts, ID fields
#
# Usage: python3 -I run_write_proofs.py   (any CWD; ROM found automatically)
# Must end with: RESULT: ALL WRITE PROOFS PASS
import sys, os, copy, json, hashlib
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import machine as machmod
from wd_write_model import (WriteMachine, BT, REV, T1MIN, FIFO_DEPTH, GAP_BT, PRE_BT,
                            post_job, jobs_idle, run_until_idle, boot, fmt_cmd)

FIX = os.path.join(HERE, 'fixtures')
FAIL = []
def check(name, cond, detail=''):
    tag = 'PASS' if cond else 'FAIL'
    if not cond: FAIL.append(name)
    print('%s  %s%s' % (tag, name, ('  [' + detail + ']') if detail else ''))

def in_idle_loop(m):
    return 0xB0F0 <= m.cpu.pc <= 0xB17B

def dirty_side(m, T, S, seed):
    # a write job on a cache miss fills the side (ten Read Sectors) and marks it dirty
    for i in range(256): m.ram[0x300 + i] = (i * 7 + seed) & 0xFF
    m.ram[0x9C] = 0xFF; m.ram[0x95] = 0x80; m.ram[0x87] = 0
    post_job(m, 0x90, T, S)
    ok = run_until_idle(m, 6_000_000, 'write job T%d S%d' % (T, S))
    return ok and m.ram[0x87] == 0x80

def idle_flush(m, maxchunks=1500):
    m.ram[0x9C] = 0
    for _ in range(maxchunks):
        m.run(10000)
        if m.ram[0x87] == 0 and jobs_idle(m) and in_idle_loop(m):
            return True
    return False

def dos_error(m, code):
    # the DOS error channel buffer: "<code>,<message>,<track>,<sector>" (the WP
    # message token expands with a leading space: "26, WRITE PROTECT ON")
    b = bytes(m.ram)
    i = b.find(b'%02d,' % code)
    while i >= 0:
        j = i + 3
        msg = b[j:j + 24].split(b',')[0]
        if msg.strip() and all(32 <= c < 127 for c in msg):
            return (b'%02d,' % code + msg).decode()
        i = b.find(b'%02d,' % code, i + 1)
    return None

def flush_record(m, mark_cmd, mark_ops, label, T, S):
    cmds = m.cmd_log[mark_cmd:]
    ops = [o for o in m.ops[mark_ops:] if o['kind'] == 'ws']
    t0 = cmds[0][0]
    out_cmds = []
    for c in cmds:
        out_cmds.append(dict(t=c[0] - t0, cmd='%02X' % c[1], name=fmt_cmd(c[1]),
                             track=c[2], sector=c[3], data=c[4], head=c[5], side=c[6],
                             pc='$%04X' % c[7]))
    ws_idx = [i for i, c in enumerate(cmds) if (c[1] >> 4) in (0xA, 0xB)]
    # BUSY drop of each Write Sector -> the next command write
    ws_gaps = []
    for o in ops:
        nxt = [c for c in cmds if c[0] > o['end']]
        if nxt: ws_gaps.append(nxt[0][0] - o['end'])
    order = [o['sector'] for o in ops]
    first = [o['first_lat'] for o in ops]
    data_lat = [x for o in ops for x in o['lat']]
    after = cmds[ws_idx[-1] + 1:] if ws_idx else []
    ver_ra = [c for c in after if (c[1] >> 4) == 0xC]
    ver_rs = [c[3] for c in after if (c[1] >> 4) in (0x8, 0x9)]
    cyl = ops[0]['cyl'] if ops else None
    side = ops[0]['side'] if ops else None
    rec = dict(label=label, logical_track=T, logical_sector=S, cylinder=cyl, side=side,
               commands=out_cmds,
               write_sector_order=order,
               write_command_bytes=sorted(set('%02X' % o['cmd'] for o in ops)),
               p_bit=sorted(set((o['cmd'] >> 1) & 1 for o in ops)),
               busy_drop_to_next_command_cycles=ws_gaps,
               first_byte_latency_cycles=dict(per_sector=first, min=min(first), max=max(first)) if first else None,
               data_latency_cycles=dict(min=min(data_lat), max=max(data_lat), n=len(data_lat)) if data_lat else None,
               write_sector_busy_cycles=[o['end'] - o['start'] for o in ops],
               verify=dict(read_address=len(ver_ra), read_sector_order=ver_rs),
               first_command_to_last_write_busy_drop_cycles=(ops[-1]['end'] - t0) if ops else None,
               lost=sum(o['lost'] for o in ops), drops=sum(o['drops'] for o in ops),
               drained=sum(o['drained'] for o in ops))
    return rec, ops

print('booting the genuine 318045-02 ROM on the M2 write model ...')
base = boot()
rom = bytes(machmod.ROM)
print('ROM sha256 %s  cmd bytes $01DF..$01E4: %s' % (hashlib.sha256(rom).hexdigest(),
      ' '.join('%02X' % base.ram[0x1DF + i] for i in range(6))))
check('W-BOOT boot reaches the idle loop', in_idle_loop(base) or jobs_idle(base),
      'pc=$%04X' % base.cpu.pc)

fixture = dict(generator='doc/dev-fdd/rom_emu/run_write_proofs.py (issue #244, M2)',
               rom_sha256=hashlib.sha256(rom).hexdigest(),
               model='wd_write_model.py: M2 FIFO-room DRQ (depth %d), first-byte rule %d byte-times '
                     'after the ID CRC, sticky LOST DATA, WP pre-check, minimum BUSY %d cycles'
                     % (FIFO_DEPTH, GAP_BT, T1MIN),
               cycle_ns=500, byte_time_cycles=BT, revolution_byte_times=REV,
               layout='stock 318045-02: ID CRC end of record R at byte-time 32 + 609 (R-1) + 22',
               flushes=[], p_bit_per_cylinder={})

# ================= W-FLUSH: the idle side flush =================
m = copy.deepcopy(base)
ok = dirty_side(m, 1, 0, 3)
check('W-FLUSH-PRE write job on T1 S0 dirtied the side cache', ok, '$87=%02X' % m.ram[0x87])
mark_c = len(m.cmd_log); mark_o = len(m.ops)
ok = idle_flush(m)
rec, ops = flush_record(m, mark_c, mark_o, 'idle flush cylinder 0 side 0 (T1 S0)', 1, 0)
fixture['flushes'].append(rec)
cache = bytes(m.ram[0x0C00:0x2000])
exact = all(bytes(m.disk[(0, 0, r)]) == cache[(r - 1) * 512:r * 512] for r in range(1, 11))
names = [c['name'] for c in rec['commands']]
first_ws = names.index('WRSEC') if 'WRSEC' in names else -1
R0 = rec['commands'][first_ws - 1]['sector'] if first_ws > 0 else None
exp_order = None
if ops:
    r1 = ops[0]['sector']
    exp_order = [((r1 - 1 + k) % 10) + 1 for k in range(10)]
print('W-FLUSH: cmds %s' % ' '.join('%s/%d' % (c['name'], c['sector']) for c in rec['commands']))
print('         order %s, gaps %s cycles, first-byte latency %s, data latency %s cycles, verify %s'
      % (rec['write_sector_order'], rec['busy_drop_to_next_command_cycles'],
         rec['first_byte_latency_cycles'], rec['data_latency_cycles'], rec['verify']))
check('W-FLUSH flush completed, cache clean', ok and m.ram[0x87] == 0, '$87=%02X' % m.ram[0x87])
check('W-FLUSH ten Write Sectors R+1..10,1..R in one burst', len(ops) == 10 and rec['write_sector_order'] == exp_order,
      'order=%s' % rec['write_sector_order'])
check('W-FLUSH all ten completed clean (no LOST, no first-byte abort, no drop)',
      all(o['result'] == 'OK' and not o['lost'] for o in ops) and rec['drops'] == 0,
      'results=%s drops=%d' % ([o['result'] for o in ops], rec['drops']))
check('W-FLUSH disk byte-exact against the cache', exact)
check('W-FLUSH verify pass: Read Address + ten Read Sectors',
      rec['verify']['read_address'] >= 1 and len(rec['verify']['read_sector_order']) == 10,
      str(rec['verify']))
check('W-FLUSH DRQ-to-data latencies within one byte-time (FIFO never ran dry)',
      rec['data_latency_cycles'] is not None and rec['data_latency_cycles']['max'] < BT,
      str(rec['data_latency_cycles']))

# ================= W-PBIT: P bit per cylinder =================
pbit = {}
for T, label in ((1, 'cyl0'), (2, 'cyl1'), (44, 'cyl43'), (45, 'cyl44'), (80, 'cyl79')):
    mp = copy.deepcopy(base)
    if not dirty_side(mp, T, 0, T):
        pbit[T - 1] = None; continue
    mc = len(mp.cmd_log); mo = len(mp.ops)
    okp = idle_flush(mp)
    r, o = flush_record(mp, mc, mo, 'idle flush %s side 0 (T%d S0)' % (label, T), T, 0)
    if T in (2, 80): fixture['flushes'].append(r)
    pbit[T - 1] = r['p_bit'][0] if (okp and len(r['p_bit']) == 1) else None
    print('W-PBIT %s: Write Sector bytes %s -> P = %s, flush ok=%s' % (label, r['write_command_bytes'], r['p_bit'], okp))
fixture['p_bit_per_cylinder'] = {str(k): v for k, v in pbit.items()}
check('W-PBIT P = 1 on cylinder 0 and 44..79, P = 0 on 1..43 (A8 vs AA)',
      pbit == {0: 1, 1: 0, 43: 0, 44: 1, 79: 1}, str(pbit))

os.makedirs(FIX, exist_ok=True)
with open(os.path.join(FIX, 'write_back_order.json'), 'w') as f:
    json.dump(fixture, f, indent=1, sort_keys=True)
    f.write('\n')
print('wrote fixtures/write_back_order.json (%d flushes)' % len(fixture['flushes']))

# ================= W-FORMAT: N0: on cylinders 0..1 =================
mf = copy.deepcopy(base)
mf.head = 3; mf.wd_track = 3
mf.ram[0x8F] = 1                    # last cylinder := 1 -> format cylinders 0..1
mf.ram[0x95] = 0x80; mf.ram[0x87] = 0
markf = len(mf.cmd_log)
post_job(mf, 0xC0, 1, 0)            # NEW: restore job
okr = run_until_idle(mf, 2_000_000, 'restore job')
saved_9b = mf.ram[0x9B]; mf.ram[0x9B] = 0
post_job(mf, 0xF0, 1, 0)            # NEW: format all
okf = run_until_idle(mf, 16_000_000, 'format job')
res_f = mf.ram[2]
mf.ram[0x9B] = saved_9b
wts = [o for o in mf.ops if o['kind'] == 'wt']
print('W-FORMAT: restore ok=%s, format ok=%s job result=%02X, Write Tracks %s'
      % (okr, okf, res_f, [(o['cyl'], o['side'], o['result'], '%02X' % o['cmd']) for o in wts]))
check('W-FORMAT job $F0 completes OK over 2 cylinders x 2 sides', okf and res_f == 0x01 and len(wts) == 4
      and all(o['result'] == 'OK' and not o['lost'] for o in wts),
      'result=%02X wts=%d' % (res_f, len(wts)))
def tok_structure(slots):
    nf5 = slots.count(0xF5); nf7 = slots.count(0xF7)
    ids = []
    i = 0
    while i < len(slots) - 8:
        if slots[i:i + 4] == bytes([0xF5, 0xF5, 0xF5, 0xFE]):
            ids.append(tuple(slots[i + 4:i + 8])); i += 8
        else: i += 1
    return nf5, nf7, ids
okstruct = True
for o in wts:
    nf5, nf7, ids = tok_structure(o['slots'])
    exp_ids = [(o['cyl'], o['side'], r, 2) for r in range(1, 11)]
    good = (nf5 == 60 and nf7 == 20 and ids == exp_ids and o['slots'][:32] == bytes([0x4E] * 32))
    okstruct &= good
    print('   cyl %d side %d: disk tokens %d, F5 %d, F7 %d, IDs %s ... drained %d dropped %d first-token lat %s'
          % (o['cyl'], o['side'], len(o['slots']), nf5, nf7, ids[:2], o['drained'], o['drops'], o['first_lat']))
check('W-FORMAT token streams: 32 x 4E, F5 x 60, F7 x 20, ID fields C,H,1..10,2 in order', okstruct)
blank = all(bytes(mf.disk[(c, h, r)]) == bytes(512) for c in (0, 1) for h in (0, 1) for r in range(1, 11))
check('W-FORMAT every sector reads back as the fill byte 00 (the verify passes did)', blank)
# the fixture: cylinder 0 side 0, every token the DOS wrote from the first DRQ to the ending index
o0 = next(o for o in wts if o['cyl'] == 0 and o['side'] == 0)
toks = [e for e in o0['tok_log'] if e[2] in ('disk', 'drained')]
stream = bytes(e[0] for e in toks)
lat = [e[1] for e in toks]
f7_pos = [i for i, e in enumerate(toks) if e[0] == 0xF7]
disk_n = sum(1 for e in toks if e[2] == 'disk')
mag = sum(2 if b == 0xF7 else 1 for b in o0['slots'])
mag_last_crc = sum(2 if b == 0xF7 else 1 for b in o0['slots'][:max(i for i, b in enumerate(o0['slots']) if b == 0xF7) + 1])
side = dict(generator='doc/dev-fdd/rom_emu/run_write_proofs.py (issue #244, M2)',
            rom_sha256=hashlib.sha256(rom).hexdigest(),
            what='the tokens the genuine DOS wrote into the WD data register for N0: on cylinder 0 '
                 'side 0, from the first DRQ to the ending index, under the M2 FIFO-room DRQ model',
            command='%02X' % o0['cmd'], cylinder=0, side=0,
            tokens=len(stream), tokens_written_to_disk=disk_n,
            tokens_drained_at_the_cut=len(stream) - disk_n,
            tokens_dropped_after_the_index=o0['drops'],
            magnetic_byte_times_written=mag, magnetic_byte_times_through_last_crc=mag_last_crc,
            revolution_byte_times=REV,
            f7_positions=f7_pos, f5_count=stream.count(0xF5), f7_count=len(f7_pos),
            first_token_latency_cycles=o0['first_lat'],
            token_latency_cycles=lat,
            token_latency_min=min(x for x in lat[1:] if x is not None),
            token_latency_max=max(x for x in lat[1:] if x is not None),
            token_fate=[e[2] for e in toks],
            id_fields=[list(x) for x in tok_structure(o0['slots'])[2]],
            first_drq_to_starting_index_cycles=(o0['t_idx'] - o0['start']) if o0['t_idx'] else None)
with open(os.path.join(FIX, 'format_tokens.bin'), 'wb') as f:
    f.write(stream)
with open(os.path.join(FIX, 'format_tokens.json'), 'w') as f:
    json.dump(side, f, indent=1, sort_keys=True)
    f.write('\n')
print('wrote fixtures/format_tokens.bin (%d tokens, %d on disk, %d magnetic byte-times through the last CRC) + .json'
      % (len(stream), disk_n, mag_last_crc))
check('W-FORMAT stock stream 32 + 10 x 609 = 6122 magnetic byte-times through the last data CRC',
      mag_last_crc == 6122 - 35, 'through last CRC=%d (6122 incl. the final 35 x 4E gap3)' % mag_last_crc)

# ================= W-WP: tab closed after login =================
mw = copy.deepcopy(base)
okd = dirty_side(mw, 1, 0, 5)
mw.wp = True
mc = len(mw.cmd_log); mo = len(mw.ops)
okw = idle_flush(mw, maxchunks=2000)
wops = [o for o in mw.ops[mo:] if o['kind'] == 'ws']
seq = [fmt_cmd(c[1]) for c in mw.cmd_log[mc:]]
first_wr = seq.index('WRSEC') if 'WRSEC' in seq else len(seq)
print('W-WP: cmds %s' % seq[:12])
print('      write ops %s, BUSY %s cycles' % ([(o['sector'], o['result']) for o in wops], [o['end'] - o['start'] for o in wops]))
check('W-WP three attempts, each refused WP with BUSY >= the 1.5 ms minimum, no DRQ',
      okd and len(wops) == 3 and all(o['result'] == 'WP' and o['accepted'] == 0 and o['end'] - o['start'] >= T1MIN for o in wops),
      '%d attempts' % len(wops))
check('W-WP every attempt: Read Address, Read Address, Write Sector',
      seq[:9] == ['RDADDR', 'RDADDR', 'WRSEC'] * 3, str(seq[:9]))
e26 = dos_error(mw, 26)
check('W-WP DOS error 26 WRITE PROTECT ON', e26 is not None and 'WRITE PROTECT ON' in e26, 'error channel: %r' % e26)

# ================= W-RNF: a sector whose ID never comes =================
mr = copy.deepcopy(base)
okd = dirty_side(mr, 1, 0, 9)
mr.rnf_inject.add((0, 0, 3))
mc = len(mr.cmd_log); mo = len(mr.ops)
okn = idle_flush(mr, maxchunks=4000)
rops = [o for o in mr.ops[mo:] if o['kind'] == 'ws']
rnf_ops = [o for o in rops if o['result'] == 'RNF']
print('W-RNF: write ops %s' % [(o['sector'], o['result']) for o in rops])
check('W-RNF three attempts end on the missing sector with RNF alone',
      okd and len(rnf_ops) == 3 and all(o['sector'] == 3 and not o['lost'] for o in rnf_ops), '%d RNF attempts' % len(rnf_ops))
e20 = dos_error(mr, 20)
check('W-RNF DOS error 20 READ ERROR', e20 is not None and 'READ ERROR' in e20, 'error channel: %r' % e20)

# ================= W-LOST: LOST DATA on a Write Sector (run last) =================
ml = copy.deepcopy(base)
okd = dirty_side(ml, 1, 0, 11)
mo = len(ml.ops)
ml.ram[0x9C] = 0
inj = None
for _ in range(400):                 # run to the first Write Sector of the flush
    ml.run(1000)
    if ml.wop == 'ws':
        inj = (ml.op_cyl, ml.op_side, ml.op_sector); ml.lost_inject.add(inj); break
hit_cd53 = False; rts_target = None; crashed = False; steps = 0
try:
    while steps < 3_000_000 and rts_target is None:
        pc = ml.cpu.pc
        if pc == 0xCD53: hit_cd53 = True
        if hit_cd53 and ml.read(pc) == 0x60:      # the RTS of the $CD53 path
            ml.run(1); rts_target = ml.cpu.pc; break
        ml.run(1); steps += 1
except Exception as e:
    crashed = True
lops = [o for o in ml.ops[mo:] if o['kind'] == 'ws']
print('W-LOST: injected lost level on %s; op results %s; $CD53 reached=%s; its RTS returned to %s '
      '(the JSR $CD3F at $C685 returns to $C688); $7D=%02X'
      % (inj, [(o['sector'], o['result'], o['lost']) for o in lops], hit_cd53,
         ('$%04X' % rts_target) if rts_target is not None else None, ml.ram[0x7D]))
wild = False
try:
    for _ in range(200):
        ml.run(10000)
except Exception:
    wild = True
check('W-LOST status bit 2 sends the write epilogue through $CD53 and its RTS misreturns',
      okd and hit_cd53 and rts_target is not None and rts_target != 0xC688,
      'RTS -> $%04X != $C688; DOS afterwards: %s' % (rts_target or 0, 'crashed' if (crashed or wild) else 'runs on wild'))

print()
if FAIL:
    print('RESULT: %d FAILED: %s' % (len(FAIL), FAIL)); sys.exit(1)
print('RESULT: ALL WRITE PROOFS PASS')
