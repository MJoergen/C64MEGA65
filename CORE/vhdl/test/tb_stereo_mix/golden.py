#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# Stereo Mix bench (GitHub issue #247): golden model and test vectors
#
#   golden.py vectors <out.txt> [seed]   write the stimulus/expectation file read by the bench
#   golden.py stream <out.txt> [seed]    write the sample stream of the latency phase of the bench
#   golden.py lut <main.vhd>             check C_VOL_LUT of main.vhd against its definition
#
# The model is an independent transcription of aud_mix_top in MiSTer's sys/audio_out.sv (the module
# behind the "Stereo Mix" option of MiSTer's C64 core), written with Verilog bit-slice semantics on
# 17-bit two's complement words instead of the shifts of main.vhd, followed by the master volume of
# main.vhd: gain = round((step/20) ** (log2(10)/2) * 2**15), product >> 15.
#
#   reg signed [16:0] a1, a2, a3, a4;
#   a1 <= {core_audio[15],core_audio};  a2 <= a1 + {linux_audio[15],linux_audio};  // linux = 0
#   pre_out <= a2[16:1];                                  // the other channel's pre_in
#   case(mix)
#      0: a3 <= a2;
#      1: a3 <= $signed(a2) - $signed(a2[16:3]) + $signed(pre_in[15:2]);
#      2: a3 <= $signed(a2) - $signed(a2[16:2]) + $signed(pre_in[15:1]);
#      3: a3 <= {a2[16],a2[16:1]} + {pre_in[15],pre_in};
#   endcase
#   a4 <= a3 >>> att[3:0];                                // att = 0
#   out <= ^a4[16:15] ? {a4[16],{15{a4[15]}}} : a4[15:0];
#
# MiSTer takes pre_in from the other channel's previous sample (a one-cycle skew of a register
# pipeline); main.vhd mixes the two channels of the same sample, so the model does too.
#
# Each vector line: mode volume left right expected_left expected_right (decimal). The stream file
# has the same format: blocks of 64 samples with a constant mode and volume, one sample per clock.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

import math
import random
import re
import sys


def bits(v, hi, lo):
    """Verilog part select v[hi:lo] of a two's complement word, as an unsigned field."""
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


def sx(field, width):
    """Interpret an unsigned bit field of the given width as two's complement ($signed)."""
    return field - (1 << width) if field & (1 << (width - 1)) else field


def wrap(v, width):
    """Truncate to a signed register of the given width (Verilog assignment semantics)."""
    return sx(v & ((1 << width) - 1), width)


def aud_mix_a4(mix, own, other):
    """One channel of aud_mix_top up to a4 (before the output clamp)."""
    a2 = wrap(own, 17)                                   # {core[15],core} + 0
    a2o = wrap(other, 17)
    pre_in = sx(bits(a2o, 16, 1), 16)                    # other channel: a2[16:1]
    if mix == 0:
        a3 = a2
    elif mix == 1:
        a3 = a2 - sx(bits(a2, 16, 3), 14) + sx(bits(pre_in, 15, 2), 14)
    elif mix == 2:
        a3 = a2 - sx(bits(a2, 16, 2), 15) + sx(bits(pre_in, 15, 1), 15)
    else:
        a3 = sx(bits(a2, 16, 16) << 16 | bits(a2, 16, 1), 17) + sx(bits(pre_in, 15, 15) << 16 | bits(pre_in, 15, 0), 17)
    a3 = wrap(a3, 17)
    return a3                                            # a4 = a3 >>> 0 (att = 0)


def aud_mix(mix, own, other):
    """One channel of aud_mix_top: own/other are the signed 16-bit core samples."""
    a4 = aud_mix_a4(mix, own, other)
    if bits(a4, 16, 16) != bits(a4, 15, 15):             # ^a4[16:15]: saturate
        return 32767 if bits(a4, 16, 16) == 0 else -32768
    return sx(bits(a4, 15, 0), 16)


def vol_lut():
    e = math.log2(10) / 2                                # perceived loudness halves every -10 dB
    return [round((i / 20) ** e * 32768) for i in range(21)]


def volume(v, step):
    return wrap((v * vol_lut()[step]) >> 15, 16)        # prod(30 downto 15), arithmetic shift


def expect(mode, step, l, r):
    return volume(aud_mix(mode, l, r), step), volume(aud_mix(mode, r, l), step)


CORNERS = [-32768, -32767, -32766, -16385, -16384, -9, -8, -7, -5, -4, -3, -2, -1,
           0, 1, 2, 3, 4, 5, 7, 8, 9, 16383, 16384, 32765, 32766, 32767]


def vectors(seed):
    rnd = random.Random(seed)
    vecs = []
    for mode in range(4):                                # every corner pair, bit-transparent volume
        for l in CORNERS:
            for r in CORNERS:
                vecs.append((mode, 20, l, r))
    for mode in range(4):                                # mono SID: both channels identical
        for v in CORNERS:
            vecs.append((mode, 20, v, v))
    for _ in range(6000):                                # random samples, modes and volumes
        mode = rnd.randrange(4)
        step = rnd.randrange(21)
        l = rnd.randrange(-32768, 32768)
        r = l if rnd.random() < 0.1 else rnd.randrange(-32768, 32768)
        vecs.append((mode, step, l, r))
    for step in range(21):                               # every volume step with full-scale input
        for mode in range(4):
            vecs.append((mode, step, 32767, -32768))
            vecs.append((mode, step, -32768, 32767))
    return vecs


def stream(seed):
    rnd = random.Random(seed + 1)
    out = []
    for mode in range(4):
        for step in (20, 13, 3):
            for _ in range(64):
                out.append((mode, step, rnd.randrange(-32768, 32768), rnd.randrange(-32768, 32768)))
    return out


def self_check():
    """Properties that must hold for MiSTer's blends; they guard the model itself."""
    for mode in range(4):
        for l in CORNERS:
            for r in CORNERS:
                ol, orr = aud_mix(mode, l, r), aud_mix(mode, r, l)
                # a weighted average: within one LSB (the floor of the shifts) of the input range,
                # and the clamp never acts (the blends cannot clip)
                assert min(l, r) - 1 <= ol <= max(l, r) + 1, (mode, l, r)
                assert min(l, r) - 1 <= orr <= max(l, r) + 1, (mode, l, r)
                assert -32768 <= aud_mix_a4(mode, l, r) <= 32767, (mode, l, r)
                if mode == 0:
                    assert (ol, orr) == (l, r)
                if mode == 3:
                    assert ol == orr == (l >> 1) + (r >> 1)
                if l == r and mode in (0, 1, 2):
                    assert ol == orr == l                # mono SID: Full/Wide/Narrow transparent
                if l == r and mode == 3:
                    assert ol == orr and abs(ol - l) <= 1
    # the blend weights: Wide = 7/8 + 1/8, Narrow = 3/4 + 1/4 (up to the floor of two shifts)
    assert aud_mix(1, 32000, 0) in (28000,) and aud_mix(1, 0, 32000) == 4000
    assert aud_mix(2, 32000, 0) == 24000 and aud_mix(2, 0, 32000) == 8000
    assert vol_lut()[20] == 0x8000 and vol_lut()[0] == 0


def main():
    self_check()
    if len(sys.argv) >= 3 and sys.argv[1] in ("vectors", "stream"):
        seed = int(sys.argv[3]) if len(sys.argv) > 3 else 247
        vecs = vectors(seed) if sys.argv[1] == "vectors" else stream(seed)
        with open(sys.argv[2], "w") as f:
            for mode, step, l, r in vecs:
                el, er = expect(mode, step, l, r)
                f.write(f"{mode} {step} {l} {r} {el} {er}\n")
        print(f"    {len(vecs)} {'vectors' if sys.argv[1] == 'vectors' else 'stream samples'} written (seed {seed})")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "lut":
        src = open(sys.argv[2]).read()
        m = re.search(r"constant\s+C_VOL_LUT\s*:\s*vol_lut_t\s*:=\s*\((.*?)\);", src, re.S)
        if not m:
            print("    C_VOL_LUT not found in main.vhd")
            return 1
        lut = [int(x, 16) for x in re.findall(r'x"([0-9A-Fa-f]{4})"', m.group(1))]
        if lut != vol_lut():
            print("    C_VOL_LUT of main.vhd differs from round((i/20)**(log2(10)/2) * 2**15)")
            return 1
        print("    C_VOL_LUT of main.vhd matches its definition (21 steps)")
        return 0
    print(__doc__ or "usage: golden.py vectors <out> [seed] | golden.py lut <main.vhd>")
    return 2


if __name__ == "__main__":
    sys.exit(main())
