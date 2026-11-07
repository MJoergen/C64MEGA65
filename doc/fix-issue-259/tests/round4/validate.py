#!/usr/bin/env python3
"""py65 smoke test of 14-ffff (issue #259, round 4). The REC and the VIC are
stubbed: $DF00 returns a chosen status, $D012 cycles through raster lines.
Checks termination, the fault counter, and that $01, $FFFF and the display
bit are left as intended."""
import sys
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

def load_prg(mem, path):
    data = open(path, "rb").read()
    load = data[0] | (data[1] << 8)
    for i, b in enumerate(data[2:]):
        mem[load + i] = b

def make_mpu(prg, status):
    raw = bytearray(0x10000)
    mem = ObservableMemory(subject=raw)
    state = {"reads": 0}
    def rd_d012(addr):
        state["reads"] += 1
        return ((state["reads"] // 2) % 312) & 0xFF
    mem.subscribe_to_read([0xDF00], lambda a: status)
    mem.subscribe_to_read([0xD012], rd_d012)
    mpu = MPU(memory=mem)
    load_prg(mem, prg)
    return mpu, mem

def run(mpu, mem, entry, limit=2_000_000):
    mem[0xFFF0] = 0x00
    ret = 0xFFF0 - 1
    mem[0x1FF] = ret >> 8; mem[0x1FE] = ret & 0xFF
    mpu.sp = 0xFD
    mpu.pc = entry
    for _ in range(limit):
        if mpu.pc == 0xFFF0:
            return True
        if mpu.pc < 0x0800:
            return False
        mpu.step()
    return False

ok = True
for status, exp_faults in ((0x60, 50), (0x40, 0), (0x20, 50)):
    for d, f in ((255, 0), (0, 0), (0, 255), (255, 255)):
        mpu, mem = make_mpu("14-ffff.prg", status)
        mem[0x01] = 0x37; mem[0xD011] = 0x1B
        mem[0x0C03], mem[0x0C04], mem[0x0C05] = d, f, 50
        done = run(mpu, mem, 0x0C00)
        faults, chk = mem[0x0C06], mem[0x0C07]
        good = done and faults == exp_faults and chk == status and mem[0x01] == 0x37 and mem[0xFFFF] == f
        good &= all(mem[0x4000 + i] == d for i in range(256)) and (mem[0xD011] & 0x10) == 0x10
        good &= mem[0xDF03] == 0x40 and mem[0xDF08] == 1 and mem[0xDF0A] == 0
        print(f"14-ffff status ${status:02X} d={d} f={f}: done={done} faults={faults} chk={chk:#x} $01={mem[0x01]:#x} $FFFF={mem[0xFFFF]} -> {'ok' if good else 'FAIL'}")
        ok &= good
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
