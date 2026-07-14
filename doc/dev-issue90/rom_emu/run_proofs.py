# Genuine-ROM proofs for the round-10 DELIVERY v2 CONTRACT (issue #90).
#
# Runs the genuine 318045-02 DOS ROM against the v2 machine model and proves:
#   P-A   $C343 register-init self-test passes; boot reaches the idle loop
#   P-B   full boot + $C900 directory-track fill succeeds end-to-end with
#         paced delivery (32 us/byte); cache is byte-exact; zero LOST DATA
#   P-C   truncated sector completing CRC-only -> job error 5, cache
#         invalidated, retry succeeds (the $CD5A hole is closed)
#   P-D2  corrupted Read Address reply (clean status) -> software CRC check
#         at $DA63 -> job error 9, retry succeeds
#   P-E   regression demonstrator: the PRE-v2 crc+rnf status pair makes the
#         same truncated fill a SILENT SUCCESS with a valid-marked stale cache
#   P-T   transfer-loop timing margin under 32 us pacing (never loses a byte)
#   P-U   unit semantics: busy-command ignore, DRQ+presentation, overrun ->
#         LOST, FI cancel, CRC-suppresses-RNF belt
#   P-D1  ROM DEFECT (unit): the $CD3F LOST-DATA branch (status bit2) latches
#         job error 9 into $7D but skips the PLP that balances the PHP at
#         $CD42, so its RTS pops the flags byte as PCL and MISRETURNS (bytes:
#         08=PHP, B0 08=BCS $CD53, 28=PLP only on the not-taken path,
#         2C A9 09=BIT skip-trick hiding LDA #$09). Latent on real hardware
#         because the transfer loop always keeps up (see P-T), i.e. bit2
#         never fires there.
#   P-D3  ROM DEFECT (end-to-end): a Read Sector completing with LOST DATA
#         set sends the DOS into wild execution (the P-D1 misreturn),
#         corrupting drive RAM -- NOT the documented error-9-and-retry.
#         Run LAST: it leaves the machine unusable.
#
# Usage: python3 run_proofs.py   (any CWD; ROM is found automatically)
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import machine as machmod

FAIL = []
def check(name, cond, detail=''):
    tag = 'PASS' if cond else 'FAIL'
    if not cond: FAIL.append(name)
    print('%s  %s%s' % (tag, name, ('  [' + detail + ']') if detail else ''))

class TestMachine(machmod.Machine):
    def __init__(self):
        self.trunc_inject = {}   # key -> (nbytes, crc, rnf): one-shot injection
        self.pace_inject = set() # key: present THIS op faster than the CPU polls
        self.ra_shift = 0        # >0: corrupt the next N Read Address replies
        self.fin_tail = None     # cycles between last presentation and finalize
        super().__init__()
    def stage_read(self, key, data, crc_err=False, rnf=False):
        if key in self.trunc_inject:
            n, crc_err, rnf = self.trunc_inject.pop(key)
            data = data[:n]
            self.trace.append(('INJECT-TRUNC', key, n, crc_err, rnf))
        if key in self.pace_inject:
            self.pace_inject.discard(key)
            self.PACE = 6        # 3 us/byte: faster than the ROM poll loop
            self.trace.append(('INJECT-FASTPACE', key))
        super().stage_read(key, data, crc_err=crc_err, rnf=rnf)
    def wd_command(self, v):
        super().wd_command(v)
        if (v >> 4) == 0xC and self.ra_shift and self.staged is not None:
            # one-byte-shifted reply, status stays CLEAN: only the ROM's own
            # software CRC over the reply ($DA63) can catch this
            self.ra_shift -= 1
            t, data = self.staged
            self.staged = (t, [0xEE] + data[:5])
            self.trace.append(('INJECT-RA-SHIFT',))
    def wd_finalize(self):
        if self.last_present_at is not None:
            self.fin_tail = self.cyc - self.last_present_at
        super().wd_finalize()
        self.PACE = 64           # restore normal pacing after every op

def run_until_idle(m, maxsteps, label):
    for chunk in range(maxsteps // 10000):
        m.run(10000)
        if all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy():
            m.run(5000)
            return True
    print('!! %s: did not go idle; pc=$%04X jobq %s'
          % (label, m.cpu.pc, ['%02X' % m.ram[2+i] for i in range(9)]))
    return False

def post_job(m, job, t, s, bufpage=3):
    m.ram[0x0B] = t; m.ram[0x0C] = s
    m.ram[0x01F1] = bufpage
    m.ram[0x0002] = job

def cold_cache(m):
    m.ram[0x95] = 0x80; m.ram[0x87] = 0x00

def wd_cmds(m, mark):
    return [t for t in m.trace[mark:] if t[0] == 'CMD']

def rs_cmds(m, mark):
    return [c for c in wd_cmds(m, mark) if (c[1] >> 4) in (0x8, 0x9)]

def cache_expected(m):
    # cache $0C00-$1FFF + 256*logical-in-side holds cyl39/side0 = T40 S0..S19
    return b''.join(bytes(m.logical(40, s)) for s in range(20))

# ================= boot (P-A) =================
m = TestMachine()
m.cpu.reset()
m.run(3_000_000)   # fixed budget: no RAM pokes before this (ROM RAM test!)
print('boot: pc=$%04X cyc=%d  WD cmds=%d  lost=%d busy-ignored=%d'
      % (m.cpu.pc, m.cyc, len(wd_cmds(m, 0)), m.dbg['lost'], m.dbg['busycmd']))
check('P-A register self-test + boot to idle',
      0xB0F0 <= m.cpu.pc <= 0xB135 and (m.ram[0x79] & 0x40) == 0,
      'pc=$%04X (idle loop $B0F0-$B135), $79 bit6 (blink)=%d, $02AB=%02X'
      % (m.cpu.pc, (m.ram[0x79] >> 6) & 1, m.ram[0x02AB]))

# ================= P-B: cold directory-track fill =================
cold_cache(m)
mark = len(m.trace)
m.dbg['max_consume_lat'] = 0
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-B')
res = m.ram[0x0002]
rs = rs_cmds(m, mark)
cache = bytes(m.ram[0x0C00:0x2000])
exact = cache == cache_expected(m)
print('P-B: job result=%02X  ReadSector cmds=%d  presented/op=512  lost=%d'
      % (res, len(rs), m.dbg['lost']))
print('     buffer $0300[0:8]=%s  cache byte-exact=%s  $95=%02X'
      % (bytes(m.ram[0x300:0x308]).hex(), exact, m.ram[0x95]))
check('P-B paced fill end-to-end, cache byte-exact, zero LOST',
      res < 2 and len(rs) == 10 and exact and m.dbg['lost'] == 0,
      'result=%02X rs=%d exact=%s lost=%d' % (res, len(rs), exact, m.dbg['lost']))
pb_maxlat = m.dbg['max_consume_lat']
pb_tail = m.fin_tail

# ================= P-C: truncated sector, CRC-only status =================
cold_cache(m)
m.trunc_inject[(39, 0, 4)] = (100, True, False)   # 100 bytes, crc=1, rnf=0
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-C')
res_c = m.ram[0x0002]
rs_c = len(rs_cmds(m, mark))
inval = m.ram[0x95] == 0x80
print('P-C: truncated+CRC-only: job result=%02X  RS cmds=%d  cache $95=%02X'
      % (res_c, rs_c, m.ram[0x95]))
check('P-C CRC-only -> job error 5 (DOS 23), cache invalidated',
      res_c == 0x05 and inval,
      'result=%02X (want 05), $95=%02X (want 80 = invalid)' % (res_c, m.ram[0x95]))
# the IP retry ($94F8/$9564: results >=2 retry, budget $30=2) re-posts the job:
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-C retry')
res_c2 = m.ram[0x0002]
exact2 = bytes(m.ram[0x0C00:0x2000]) == cache_expected(m)
check('P-C retry succeeds with byte-exact cache (self-healing)',
      res_c2 < 2 and exact2,
      'retry result=%02X, cache exact=%s' % (res_c2, exact2))

# ================= P-D2: corrupted RA reply -> job error 9, retry =========
cold_cache(m)
m.ra_shift = 1
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-D2')
res_d = m.ram[0x0002]
shifted = [t for t in m.trace[mark:] if t[0] == 'INJECT-RA-SHIFT']
print('P-D2: shifted RA reply (clean status): job result=%02X  injected=%d'
      % (res_d, len(shifted)))
check('P-D2 bad RA reply -> job error 9 (DOS 27) via $DA63 software CRC',
      res_d == 0x09 and len(shifted) == 1,
      'result=%02X (want 09)' % res_d)
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-D2 retry')
res_d2 = m.ram[0x0002]
exact3 = bytes(m.ram[0x0C00:0x2000]) == cache_expected(m)
check('P-D2 retry succeeds with byte-exact cache',
      res_d2 < 2 and exact3,
      'retry result=%02X, cache exact=%s' % (res_d2, exact3))

# ================= P-E: regression demonstrator (pre-v2 crc+rnf) =========
m.legacy_crc_rnf = True
cold_cache(m)
m.ram[0x0C00:0x2000] = b'\x55' * 0x1400           # make staleness visible
m.trunc_inject[(39, 0, 4)] = (100, True, True)    # OLD pair: crc=1 AND rnf=1
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
run_until_idle(m, 4_000_000, 'P-E')
res_e = m.ram[0x0002]
rs_e = len(rs_cmds(m, mark))
valid_marked = m.ram[0x95] != 0x80
stale = bytes(m.ram[0x0C00:0x2000]) != cache_expected(m)
print('P-E: LEGACY crc+rnf: job result=%02X  RS cmds=%d/10  $95=%02X  cache stale=%s'
      % (res_e, rs_e, m.ram[0x95], stale))
check('P-E legacy crc+rnf = SILENT SUCCESS w/ stale-but-valid cache ($CD5A hole)',
      res_e < 2 and rs_e < 10 and valid_marked and stale,
      'result=%02X, fill stopped at %d/10, $95=%02X' % (res_e, rs_e, m.ram[0x95]))
m.legacy_crc_rnf = False

# ================= P-T: transfer-loop timing margin =================
# Static real-6502 numbers ($C969 loop, 2 MHz):
#   poll iteration (busy, no DRQ):  LDA abs 4 + AND 2 + LSR 2 + BCC 2 + BEQ 3 = 13
#   consume path to LDA $6003:      LDA abs 4 + AND 2 + LSR 2 + BCC 2 + BEQ 2
#                                   + STY 3 + LDY 2 + LDA $6003 4        = 21
#   full consume iteration: 21 + STA (zp),Y 6 + LDY 3 + INC 5 + BNE 3    = 38
#   (page-cross variant: +9 = 47)
#   worst-case consumption latency = one just-missed poll (13) + 21 = 34 cycles
#   pace = 64 cycles -> real-hardware margin = 30 cycles (47%); never misses.
print('P-T: static 6502: poll=13cy consume=38cy(47 page-cross) worst-lat=34cy '
      'vs pace=64cy -> margin 30cy (47 percent)')
print('P-T: emulator (3cy/instr flat): max consumption latency in P-B = %dcy, '
      'pace=64cy; finalize tail after last DRQ = %dcy' % (pb_maxlat, pb_tail))
check('P-T ROM keeps up at exact 32 us pacing (no lost byte in clean runs)',
      pb_maxlat < 64 and pb_tail >= 64,
      'max_lat=%d < 64; busy tail=%d >= 64' % (pb_maxlat, pb_tail))

# ================= P-U: unit semantics (no ROM interaction) =========
u = machmod.Machine()
u.cia_ddra |= 0x04; u.cia_pra_out &= ~0x04       # motor on
u.motor_on_at = u.cyc - 100000                    # ready() true
u.head = 3; u.wd_track = 3; u.wd_sector = 1
u.wd_write(0, 0x88)                               # READ SECTOR
busy0 = u.wd_busy()
u.wd_write(0, 0x88)                               # second command while busy
ignored = u.dbg['busycmd'] == 1
for _ in range(40):                               # advance past T_LATENCY
    u.tick_devices(64)
    if u.drq: break
drq_seen = u.drq == 1
first = u.wd_read(3)                              # consume byte 0
# now let presentations continue and MISS one -> overwrite + LOST
while u.dbg['presented'] < 3:
    u.tick_devices(64)
lost_now = u.lost == 1 and u.dbg['lost'] >= 1
u.wd_write(0, 0xD0)                               # Force Interrupt cancels
fi_cancels = u.wd_busy() == 0 and u.phys_op is None
# CRC-suppresses-RNF belt: fake a completed op with both ctrl flags set
u.phys_op = 'rs'; u.ctrl_rnf = 1; u.ctrl_crc = 1; u.ctrl_done_at = u.cyc
u.wd_finalize()
belt = (u.crc, u.rnf) == (1, 0)
check('P-U busy-cmd ignored / DRQ+present / overrun LOST / FI cancel / CRC>RNF belt',
      busy0 == 1 and ignored and drq_seen and lost_now and fi_cancels and belt,
      'busy=%d ign=%s drq=%s lost=%s fi=%s belt=crc%d,rnf%d'
      % (busy0, ignored, drq_seen, lost_now, fi_cancels, u.crc, u.rnf))

# ================= P-D1: ROM DEFECT unit proof ($CD3F imbalance) =========
v = machmod.Machine()
v.cmd = 0x88; v.lost = 1                          # completed op, LOST DATA set
v.cpu.sp = 0xFD
v.cpu.push(0xCA); v.cpu.push(0xFF)                # fake JSR from $CB00 (ret-1)
v.cpu.pc = 0xCD3F
sp_before = v.cpu.sp
for _ in range(20):
    v.cpu.step()
    if v.cpu.pc == 0xCB00: break                  # balanced return (it must not)
    if v.ram[0x7D] == 0x09 and v.cpu.pc > 0xCD59: break   # past the RTS
    if v.cpu.pc < 0xC000: break                   # already returned wild
misreturn = v.cpu.pc != 0xCB00
err9 = v.ram[0x7D] == 0x09
print('P-D1: $CD3F with LOST DATA: $7D=%02X, RTS returned to $%04X '
      '(caller was $CB00), sp %02X->%02X' % (v.ram[0x7D], v.cpu.pc,
                                             sp_before, v.cpu.sp))
check('P-D1 ROM defect: LOST-DATA branch latches error 9 then MISRETURNS '
      '(PHP at $CD42 never pulled)', err9 and misreturn,
      '$7D=%02X (=09), pc=$%04X != $CB00' % (v.ram[0x7D], v.cpu.pc))

# ================= P-D3: LOST DATA end-to-end = DOS wild execution =========
# DESTRUCTIVE: run last. A Read Sector op paced faster than the poll loop
# forces a genuine overrun; the completion carries LOST DATA and the DOS
# falls over the P-D1 misreturn instead of returning job error 9.
cold_cache(m)
m.pace_inject.add((39, 0, 6))
mark = len(m.trace)
post_job(m, 0x80, 40, 3)
crashed = False
try:
    for _ in range(200):
        m.run(10000)
        if all(m.ram[2+i] < 0x80 for i in range(9)) and not m.wd_busy():
            break
except Exception as e:
    crashed = True
    crash_info = str(e)
lost_fin = [t for t in m.trace[mark:] if t[0] == 'FIN' and 'lost=1' in t[3]]
ram_corrupt = any(m.ram[3:0x0B])   # queue slots 1-8 were 00 in healthy runs
print('P-D3: forced overrun: lost FINs=%d  crashed=%s%s  low-RAM corrupted=%s'
      % (len(lost_fin), crashed,
         ' (%s)' % crash_info if crashed else '', ram_corrupt))
check('P-D3 LOST DATA completion derails the genuine ROM (wild execution), '
      'NOT error-9-and-retry', len(lost_fin) == 1 and (crashed or ram_corrupt),
      'defect fires end-to-end; see P-D1 for the mechanism')

print()
if FAIL:
    print('RESULT: %d FAILED: %s' % (len(FAIL), FAIL)); sys.exit(1)
print('RESULT: ALL PROOFS PASS')
