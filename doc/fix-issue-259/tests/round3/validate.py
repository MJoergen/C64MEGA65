#!/usr/bin/env python3
"""py65 smoke test of the round-3 machine-code programs (issue #259).

The REC and the VIC are stubbed: $DF00 returns a chosen status, writes to
$DF01 do nothing, $D012 cycles through raster lines on every read, $D011
reads $1B. Checks that every variant terminates and that the bookkeeping
(fault counters, result table) is right for the stubbed status.
"""
import sys
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

def load_prg(mem, path):
    data = open(path, "rb").read()
    load = data[0] | (data[1] << 8)
    for i, b in enumerate(data[2:]):
        mem[load + i] = b
    return load, load + len(data) - 2

def make_mpu(prg, status):
    raw = bytearray(0x10000)
    mem = ObservableMemory(subject=raw)
    state = {"raster": 0, "reads": 0}
    def rd_df00(addr):
        return status
    def rd_d012(addr):
        state["reads"] += 1
        state["raster"] = (state["reads"] // 2) % 312
        return state["raster"] & 0xFF
    def rd_d011(addr):
        state["reads"] += 1
        state["raster"] = (state["reads"] // 2) % 312
        return 0x1B | (0x80 if state["raster"] >= 256 else 0)
    mem.subscribe_to_read([0xDF00], rd_df00)
    mem.subscribe_to_read([0xD012], rd_d012)
    mem.subscribe_to_read([0xD011], rd_d011)
    mpu = MPU(memory=mem)
    load_prg(mem, prg)
    return mpu, mem

def run(mpu, mem, entry, limit=5_000_000):
    # push a return address that lands on a BRK at $FFF0
    mem[0xFFF0] = 0x00
    mpu.sp = 0xFF
    ret = 0xFFF0 - 1
    mem[0x1FF] = ret >> 8; mem[0x1FE] = ret & 0xFF
    mpu.sp = 0xFD
    mpu.pc = entry
    for _ in range(limit):
        if mpu.pc == 0xFFF0:
            return True
        if mpu.pc < 0x0800:          # fell into zero page / BRK vector: broken PRG
            return False
        mpu.step()
    return False

ok = True
# ---- 11-bitfill: faults counted per verify, cpu check never fails (no DMA, $5000 keeps $AA)
for status, exp_r, exp_c, exp_first in ((0x60, [4,4,4,4,4,4,0,4,4,4], [4]*10, [1,1,1,1,1,1,2,1,1,1]), (0x40, [0]*10, [0]*10, [0]*10)):
    for v in range(10):
        mpu, mem = make_mpu("11-bitfill.prg", status)
        mem[0x0C03] = v
        done = run(mpu, mem, 0x0C00)
        fr, c, fc, first = mem[0x0C04], mem[0x0C05], mem[0x0C06], mem[0x0C07]
        buf_ok = all(mem[a] == 0xAA for a in range(0x5000, 0x9000, 0x101) if a != 0x7000)
        buf_ok &= mem[0x7000] == (0x55 if v >= 8 else 0xAA)
        buf_ok &= (mem[0xD011] & 0x10) == 0x10 or v != 9   # display restored
        good = done and fr == exp_r[v] and fc == exp_c[v] and first == exp_first[v] and c == 0 and mem[0xD015] == 0 and buf_ok
        print(f"11-bitfill variant {v} status ${status:02X}: done={done} r={fr} c={fc} first={first} cpu={c} -> {'ok' if good else 'FAIL'}")
        ok &= good
# ---- 12-position: table rows hold the register values, runs honored
for status in (0x60, 0x40):
    mpu, mem = make_mpu("12-position.prg", status)
    mem[0x0C03] = 7      # runs
    mem[0x0C04] = 50     # line
    done = run(mpu, mem, 0x0C00)
    rows = [bytes(mem[0x0E00 + 16*r: 0x0E00 + 16*r + 11]) for r in range(8)]
    good = done and mem[0x0C05] == status
    for r in range(7):
        st, lo, hi, rlo, rhi, llo, lhi, tlo, thi, d012, d011 = rows[r]
        good &= st == status and (lo, hi) == (0, 0x40) and (rlo, rhi) == (0, 0) and (llo, lhi) == (0, 1)
        good &= (tlo, thi) == (0xFF, 0xFF)   # plain RAM stub: the latch value written by the program
        good &= d012 == 50 and d011 == 0x1B
    good &= rows[7] == bytes(11)       # the 8th row stays empty
    print(f"12-position status ${status:02X}: done={done} chk={mem[0x0C05]:#x} row0={rows[0].hex()} -> {'ok' if good else 'FAIL'}")
    ok &= good
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
