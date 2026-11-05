#!/usr/bin/env python3
"""Turbo-mode core bench (issue #87): builds the 16 KB Ultimax test cartridge.

Usage: gen_cart.py <out_hex> [<out_listing>]

The cartridge boots the C64 core without KERNAL (Ultimax: /GAME low, /EXROM high):
ROML = $8000-$9FFF (data pattern), ROMH = $E000-$FFFF (boot code, the RAM program image at $E200
and a subroutine that runs from cartridge ROM). The output file has 16384 lines of two hex
digits: lines 0-8191 are ROML, lines 8192-16383 are ROMH. A tiny two-pass assembler for the
handful of 6502 instructions used is included, so no external tool is needed.

Cartridge registers (IO1): $DE00 bit 7 = cartridge off (normal C64 memory map), $DE02 bit 0 =
16K mode (/GAME and /EXROM low) instead of Ultimax; a reset clears both.

Protocol with the bench (tb_turbo_core.vhd): the program writes a phase number to $0FF0
(plain RAM); the bench watches the RAM write port. Results land in $0F00-$0F7F.
  1  booted, running from RAM (bench applies the turbo settings now)
  2  RAM-only loop (S1)
  3  I/O accesses: VIC, SID, CIA1, CIA2, color RAM, IO1, IO2 (S2)
  4  $D030 on/off and mirror $D070 (S4)
  5  RAM loop while the bench requests DMA (S3)
  6  internal ROMs: cartridge switched off through IO1 ($DE00 bit 7), BASIC, KERNAL and
     character ROM read directly after RAM accesses
  7  cartridge ROM / Ultimax unmapped reads directly after RAM accesses, absolute writes to ROML
     and to the cartridge RAM directly after RAM accesses (F2 data path, S6, S7)
  8  EasyFlash 3 menu tail in 16K mode, from RAM at $0100: STA $DE00, LDA #, STA $DE0E, LDA $13
     (the fingerprint of CORE/vhdl/cartridge_heuristics.vhd)
  9  code executing from cartridge ROMH that accesses zero page (F2 opcode fetches)
  $FF done
"""
import sys

OPC = {
    ("LDA", "imm"): 0xA9, ("LDA", "zp"): 0xA5, ("LDA", "abs"): 0xAD, ("LDA", "absx"): 0xBD,
    ("LDA", "absy"): 0xB9, ("LDA", "indy"): 0xB1,
    ("STA", "zp"): 0x85, ("STA", "abs"): 0x8D, ("STA", "absx"): 0x9D, ("STA", "absy"): 0x99,
    ("LDX", "imm"): 0xA2, ("LDX", "abs"): 0xAE, ("LDY", "imm"): 0xA0,
    ("STX", "zp"): 0x86, ("STX", "abs"): 0x8E,
    ("INC", "zp"): 0xE6, ("INC", "abs"): 0xEE,
    ("INX", ""): 0xE8, ("INY", ""): 0xC8, ("DEX", ""): 0xCA, ("DEY", ""): 0x88,
    ("TXA", ""): 0x8A, ("TYA", ""): 0x98, ("TXS", ""): 0x9A,
    ("CLC", ""): 0x18, ("SEI", ""): 0x78, ("CLD", ""): 0xD8, ("NOP", ""): 0xEA,
    ("ADC", "imm"): 0x69, ("ADC", "zp"): 0x65,
    ("AND", "imm"): 0x29, ("EOR", "imm"): 0x49,
    ("BNE", "rel"): 0xD0, ("BEQ", "rel"): 0xF0,
    ("JMP", "abs"): 0x4C, ("JSR", "abs"): 0x20, ("RTS", ""): 0x60,
}
SIZE = {"": 1, "imm": 2, "zp": 2, "rel": 2, "indy": 2, "abs": 3, "absx": 3, "absy": 3}


class Asm:
    def __init__(self):
        self.items = []          # (run_addr, load_addr, kind, payload)
        self.labels = {}
        self.pc = 0
        self.load = 0

    def org(self, run, load=None):
        self.pc = run
        self.load = run if load is None else load

    def label(self, name):
        self.labels[name] = self.pc

    def op(self, mnem, mode="", arg=None):
        assert (mnem, mode) in OPC, (mnem, mode)
        self.items.append((self.pc, self.load, mnem, mode, arg))
        self.pc += SIZE[mode]
        self.load += SIZE[mode]

    def byte(self, *vals):
        for v in vals:
            self.items.append((self.pc, self.load, "BYTE", "", v))
            self.pc += 1
            self.load += 1

    def word(self, v):
        self.items.append((self.pc, self.load, "WORD", "", v))
        self.pc += 2
        self.load += 2

    def val(self, a):
        return self.labels[a] if isinstance(a, str) else a

    def emit(self):
        mem = {}
        lst = []
        for pc, load, mnem, mode, arg in self.items:
            if mnem == "BYTE":
                b = [self.val(arg) & 0xFF]
            elif mnem == "WORD":
                v = self.val(arg)
                b = [v & 0xFF, v >> 8]
            else:
                b = [OPC[(mnem, mode)]]
                if mode == "rel":
                    d = self.val(arg) - (pc + 2)
                    assert -128 <= d <= 127, (mnem, arg, d)
                    b.append(d & 0xFF)
                elif mode in ("imm", "zp", "indy"):
                    v = self.val(arg)
                    assert 0 <= v <= 255
                    b.append(v)
                elif mode in ("abs", "absx", "absy"):
                    v = self.val(arg)
                    b += [v & 0xFF, v >> 8]
            for i, x in enumerate(b):
                assert load + i not in mem, hex(load + i)
                mem[load + i] = x
            lst.append(f"{pc:04X} [{load:04X}]  {' '.join(f'{x:02X}' for x in b):10s} {mnem} {mode} "
                       f"{'' if arg is None else (arg if isinstance(arg, str) else hex(arg))}")
        return mem, lst


def roml_byte(i):
    """ROML pattern, i = 0..8191 (also used by the bench as reference)."""
    return (i * 37 + (i >> 8) * 11 + 5) & 0xFF


def build():
    a = Asm()
    M = 0x0FF0                          # phase marker (RAM)

    def marker(n):
        a.op("LDA", "imm", n)
        a.op("STA", "abs", M)

    # ---------------- boot, runs from ROMH ----------------
    a.org(0xE000)
    a.label("reset")
    a.op("SEI"); a.op("CLD")
    a.op("LDX", "imm", 0xFF); a.op("TXS")
    a.op("LDX", "abs", 0x0EFF)          # boot counter (RAM is all zero at power-up)
    a.op("LDA", "abs", 0xD030)          # S4: $D030 as seen right after a reset
    a.op("STA", "absx", 0x0F00)
    a.op("INC", "abs", 0x0EFF)
    a.op("LDX", "imm", 0)
    a.label("copy")
    for p in range(2):                  # ROMH $E200-$E3FF -> RAM $0200-$03FF
        a.op("LDA", "absx", 0xE200 + 0x100 * p)
        a.op("STA", "absx", 0x0200 + 0x100 * p)
    a.op("LDA", "absx", 0xE100)         # ROMH $E100-$E1FF -> RAM $0100-$01FF (EF3 tail)
    a.op("STA", "absx", 0x0100)
    a.op("INX")
    a.op("BNE", "rel", "copy")
    a.op("JMP", "abs", 0x0200)

    # ---------------- RAM program: assembled for $0200, stored at ROMH $E200 ----------------
    a.org(0x0200, 0xE200)
    marker(1)
    a.op("LDX", "imm", 12)
    a.label("w1"); a.op("DEX"); a.op("BNE", "rel", "w1")
    a.op("LDA", "imm", 1); a.op("STA", "abs", 0xD030)      # C128 mode: turbo on

    # P2 (marker 2): RAM-only loop
    marker(2)
    a.op("LDX", "imm", 40)
    a.label("p1")
    a.op("INC", "zp", 0x10)
    a.op("LDA", "zp", 0x11); a.op("CLC"); a.op("ADC", "imm", 3); a.op("STA", "zp", 0x11)
    a.op("DEX"); a.op("BNE", "rel", "p1")

    # P3 (marker 3): I/O accesses interleaved with RAM accesses
    marker(3)
    a.op("LDY", "imm", 4)
    a.label("p2")
    a.op("LDA", "abs", 0xD020); a.op("STA", "abs", 0xD021)   # VIC
    a.op("LDA", "abs", 0xD41B); a.op("STA", "abs", 0xD418)   # SID
    a.op("LDA", "abs", 0xDC02); a.op("STA", "abs", 0xDC03)   # CIA1
    a.op("LDA", "abs", 0xDD02); a.op("STA", "abs", 0xDD03)   # CIA2
    a.op("TYA"); a.op("STA", "abs", 0xD800)                  # color RAM
    a.op("LDA", "abs", 0xD800); a.op("AND", "imm", 0x0F); a.op("STA", "absy", 0x0F10)
    a.op("STA", "abs", 0xDE00)                               # IO1 (cartridge register)
    a.op("TYA"); a.op("EOR", "imm", 0xA0); a.op("STA", "absy", 0xDF10)   # IO2 (cartridge RAM)
    a.op("LDA", "absy", 0xDF10); a.op("STA", "absy", 0x0F18)
    a.op("INC", "abs", 0xD020)                               # read-modify-write on I/O
    a.op("DEY"); a.op("BNE", "rel", "p2")

    # P4 (marker 4): $D030 (S4)
    marker(4)
    a.op("LDA", "abs", 0xD030); a.op("STA", "abs", 0x0F40)   # expect $FF (C128: bit set)
    a.op("LDA", "imm", 0); a.op("STA", "abs", 0xD030)        # C128: turbo off
    a.op("LDX", "imm", 10)
    a.label("p4a"); a.op("INC", "zp", 0x12); a.op("DEX"); a.op("BNE", "rel", "p4a")
    a.op("LDA", "abs", 0xD030); a.op("STA", "abs", 0x0F41)   # expect $FE in C128 mode
    a.op("LDA", "imm", 1); a.op("STA", "abs", 0xD070)        # mirror of $D030: turbo on
    a.op("LDX", "imm", 10)
    a.label("p4b"); a.op("INC", "zp", 0x12); a.op("DEX"); a.op("BNE", "rel", "p4b")
    a.op("LDA", "abs", 0xD030); a.op("STA", "abs", 0x0F42)   # expect $FF

    # P5 (marker 5): RAM loop, the bench requests DMA meanwhile (S3)
    marker(5)
    a.op("LDX", "imm", 120)
    a.label("p5"); a.op("INC", "zp", 0x13); a.op("DEX"); a.op("BNE", "rel", "p5")

    # P6 (marker 6): internal ROMs with the cartridge switched off (normal C64 memory map)
    marker(6)
    a.op("LDA", "imm", 0x2F); a.op("STA", "zp", 0x00)       # 6510 port: DDR as the KERNAL sets it
    a.op("LDA", "imm", 0x80); a.op("STA", "abs", 0xDE00)    # cartridge off: /GAME and /EXROM high
    a.op("LDA", "imm", 0)
    for z in (0x24, 0x25, 0x26):
        a.op("STA", "zp", z)
    a.op("LDX", "imm", 64)
    a.label("r1")
    a.op("LDA", "absx", 0xA000); a.op("CLC"); a.op("ADC", "zp", 0x24); a.op("STA", "zp", 0x24)  # BASIC
    a.op("LDA", "absx", 0xE000); a.op("CLC"); a.op("ADC", "zp", 0x25); a.op("STA", "zp", 0x25)  # KERNAL
    a.op("DEX"); a.op("BNE", "rel", "r1")
    a.op("LDA", "imm", 0x33); a.op("STA", "zp", 0x01)       # CHAREN = 0: character ROM at $D000
    a.op("LDX", "imm", 64)
    a.label("r2")
    a.op("LDA", "absx", 0xD000); a.op("CLC"); a.op("ADC", "zp", 0x26); a.op("STA", "zp", 0x26)
    a.op("DEX"); a.op("BNE", "rel", "r2")
    a.op("LDA", "imm", 0x37); a.op("STA", "zp", 0x01)
    # REU trigger address, right after RAM fetches, four times with different cycle alignment
    a.op("LDA", "imm", 0x5A); a.op("STA", "abs", 0xFF00)
    a.op("NOP"); a.op("STA", "abs", 0xFF00)
    a.op("NOP"); a.op("NOP"); a.op("STA", "abs", 0xFF00)
    a.op("INC", "zp", 0x14); a.op("STA", "abs", 0xFF00)
    a.op("LDA", "imm", 0x00); a.op("STA", "abs", 0xDE00)    # cartridge on again (Ultimax)
    for k, z in enumerate((0x24, 0x25, 0x26)):
        a.op("LDA", "zp", z); a.op("STA", "abs", 0x0F70 + k)

    # P7 (marker 7): cartridge reads directly after RAM accesses (F2 data path)
    marker(7)
    a.op("LDA", "imm", 0)
    for z in (0x20, 0x21, 0x22, 0x23, 0x24):
        a.op("STA", "zp", z)
    a.op("LDX", "imm", 64)                                   # X = 64 .. 1 in all P6 loops
    a.label("p6w")                                           # Ultimax unmapped writes
    a.op("TXA"); a.op("EOR", "imm", 0x5A); a.op("STA", "absx", 0x1000)
    a.op("DEX"); a.op("BNE", "rel", "p6w")
    # absolute writes to the cartridge directly after RAM fetches (ROML = flash on real carts, and
    # the cartridge RAM), read back below
    a.op("LDA", "imm", 0x77); a.op("STA", "abs", 0x1080)
    a.op("LDA", "imm", 0x88); a.op("STA", "abs", 0x8123)
    a.op("LDA", "imm", 0x99); a.op("STA", "abs", 0xE123)     # ROMH (Ultimax)
    a.op("LDA", "imm", 0xAA); a.op("STA", "abs", 0x2345)     # unmapped area outside the cartridge RAM
    a.op("LDA", "abs", 0x1080); a.op("STA", "abs", 0x0F54)
    a.op("LDX", "imm", 64)
    a.label("p6")
    a.op("LDA", "absx", 0x8000); a.op("CLC"); a.op("ADC", "zp", 0x20); a.op("STA", "zp", 0x20)  # ROML
    a.op("LDA", "absx", 0xF000); a.op("CLC"); a.op("ADC", "zp", 0x21); a.op("STA", "zp", 0x21)  # ROMH
    a.op("LDA", "absx", 0x1000); a.op("CLC"); a.op("ADC", "zp", 0x22); a.op("STA", "zp", 0x22)  # unmapped
    a.op("DEX"); a.op("BNE", "rel", "p6")
    a.op("LDA", "imm", 0x00); a.op("STA", "zp", 0x30)
    a.op("LDA", "imm", 0x91); a.op("STA", "zp", 0x31)        # ($30) -> $9100
    a.op("LDY", "imm", 64)
    a.label("p6i")
    a.op("LDA", "indy", 0x30); a.op("CLC"); a.op("ADC", "zp", 0x23); a.op("STA", "zp", 0x23)
    a.op("DEY"); a.op("BNE", "rel", "p6i")
    for k, z in enumerate((0x20, 0x21, 0x22, 0x23)):
        a.op("LDA", "zp", z); a.op("STA", "abs", 0x0F50 + k)

    # P8 (marker 8): EasyFlash 3 menu tail (cartridge_heuristics fingerprint) in 16K mode
    marker(8)
    a.op("LDA", "imm", 0x01); a.op("STA", "abs", 0xDE02)    # 16K mode
    a.op("LDA", "imm", 0x00)
    a.op("JSR", "abs", 0x0100)
    a.op("LDA", "imm", 0x00); a.op("STA", "abs", 0xDE02)    # Ultimax again

    # P9 (marker 9): code in cartridge ROMH accessing zero page
    marker(9)
    a.op("LDA", "imm", 0); a.op("STA", "zp", 0x40); a.op("STA", "zp", 0x41)
    a.op("JSR", "abs", "cartsub")
    a.op("LDA", "zp", 0x40); a.op("STA", "abs", 0x0F60)
    a.op("LDA", "zp", 0x41); a.op("STA", "abs", 0x0F61)
    marker(0xFF)
    a.label("done"); a.op("JMP", "abs", "done")

    # ---------------- EF3 menu tail: assembled for $0100, stored at ROMH $E100 ----------------
    a.org(0x0100, 0xE100)
    a.op("STA", "abs", 0xDE00)          # $0100  EF3 bank register (A = 0)
    a.op("LDA", "imm", 0x07)            # $0103
    a.op("STA", "abs", 0xDE0E)          # $0105
    a.op("LDA", "zp", 0x13)             # $0108: opcode $0108, operand $0109, data $0013
    a.op("RTS")

    # ---------------- subroutine in ROMH ----------------
    a.org(0xE800)
    a.label("cartsub")
    a.op("LDX", "imm", 32)
    a.label("cs1")
    a.op("LDA", "zp", 0x40); a.op("CLC"); a.op("ADC", "imm", 5); a.op("STA", "zp", 0x40)
    a.op("INC", "zp", 0x41)
    a.op("DEX"); a.op("BNE", "rel", "cs1")
    a.op("RTS")

    # ---------------- vectors ----------------
    a.org(0xFFFA)
    a.word("reset"); a.word("reset"); a.word("reset")
    return a


def main():
    a = build()
    a.emit()                             # first pass resolves labels (forward refs)
    mem, lst = a.emit()
    img = [roml_byte(i) for i in range(8192)] + [roml_byte(i + 8192) ^ 0x55 for i in range(8192)]
    for addr, b in mem.items():
        assert 0xE000 <= addr <= 0xFFFF, hex(addr)
        img[8192 + addr - 0xE000] = b
    boot_end = max(load for _, load, *_ in a.items if 0xE000 <= load < 0xE100)
    assert boot_end < 0xE0F0, "boot code runs into the EF3 page at $E100"
    ram_end = max(pc for pc, load, *_ in a.items if 0xE200 <= load < 0xE800)
    assert ram_end < 0x0400, "RAM program exceeds the two copied pages"
    with open(sys.argv[1], "w") as f:
        f.write("".join(f"{b:02X}\n" for b in img))
    if len(sys.argv) > 2:
        with open(sys.argv[2], "w") as f:
            f.write("\n".join(lst) + "\n")


if __name__ == "__main__":
    main()
