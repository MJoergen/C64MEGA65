import sys
sys.path.insert(0,'.')
from machine import Machine
m = Machine()
m.cpu.reset()
print("reset vector: $%04X" % m.cpu.pc)
try:
    m.run(3_000_000)
except Exception as e:
    print("STOP:", e, "at pc=$%04X"%m.cpu.pc)
print("after boot: pc=$%04X cyc=%d" % (m.cpu.pc, m.cyc))
print("WD trace (%d events):" % len(m.trace))
for t in m.trace[:40]: print("  ", t)
print("...")
for t in m.trace[-10:]: print("  ", t)
print("zp: $26=%02X $27=%02X $2A=%02X $7D=%02X $83=%02X $87=%02X $88=%02X $95=%02X" % tuple(m.ram[i] for i in (0x26,0x27,0x2A,0x7D,0x83,0x87,0x88,0x95)))
print("jobq $0002-$0011:", ' '.join('%02X'%m.ram[i] for i in range(2,0x12)))
print("hdrs $01BC-$01CB:", ' '.join('%02X'%m.ram[i] for i in range(0x1BC,0x1CC)))
print("cmd templates $01DA-$01E4:", ' '.join('%02X'%m.ram[i] for i in range(0x1DA,0x1E5)))
