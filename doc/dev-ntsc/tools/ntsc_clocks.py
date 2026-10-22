#!/usr/bin/env python3
"""
ntsc_clocks.py -- MMCM parameter search for the C64MEGA65 PAL/NTSC core clocks.

Standalone Python 3, no third-party modules. Exact rational arithmetic
(fractions.Fraction) is used throughout, so every printed frequency is the
true MMCM output for the given parameters, not a rounded approximation.

Usage:
    python3 doc/dev-ntsc/tools/ntsc_clocks.py            # full report
    python3 doc/dev-ntsc/tools/ntsc_clocks.py --final    # only the final table

Target device: xc7a200tfbg484-2 (all four CORE-R?.xpr). MMCME2_ADV limits
used here (Artix-7, DS181): VCO 600..1200 MHz is enforced although the -2
speed grade allows 1440 MHz, so every chosen set also works on a -1 part;
PFD 10..450 MHz; CLKFBOUT_MULT_F 2..64 in 0.125 steps; DIVCLK_DIVIDE 1..106;
CLKOUT0_DIVIDE_F 2..128 in 0.125 steps (or 1).

The C64 core clock is 32 x the CPU clock. One video frame of the MiSTer
C64 core takes  cycles_per_line * lines * 32  core clock periods:
    PAL  6569   : 63 x 312 x 32 = 628 992
    NTSC 6567R8 : 65 x 263 x 32 = 547 040
"""

import sys
from fractions import Fraction as F

F_IN = F(100_000_000)           # MEGA65 board oscillator

VCO_MIN, VCO_MAX = F(600_000_000), F(1_200_000_000)
PFD_MIN, PFD_MAX = F(10_000_000), F(450_000_000)

CLK_PER_FRAME_PAL  = 63 * 312 * 32
CLK_PER_FRAME_NTSC = 65 * 263 * 32

# Ideal NTSC C64: 14.31818 MHz crystal (= 315/22 MHz = 4 x color burst);
# VIC-II dot clock = crystal * 4 / 7, CPU = dot / 8, core clock = 32 x CPU.
NTSC_XTAL       = F(315_000_000, 22)
NTSC_IDEAL_CORE = NTSC_XTAL * 16 / 7               # 32.727272... MHz
# Ideal PAL C64: 17.734475 MHz crystal; dot = xtal * 4 / 9; core = 32 x dot / 8
PAL_XTAL        = F(17_734_475)
PAL_IDEAL_CORE  = PAL_XTAL * 16 / 9                # 31.527955... MHz
MISTER_NTSC     = F(32_727_264)                    # msum constant in c64.sv
MISTER_PAL      = F(31_527_954)


def mmcm_out(m, d, o):
    """Return (vco, pfd, fout) for CLKFBOUT_MULT_F=m, DIVCLK_DIVIDE=d, CLKOUT0_DIVIDE_F=o."""
    pfd = F_IN / d
    vco = pfd * m
    return vco, pfd, vco / o


def legal(m, d, o):
    vco, pfd, _ = mmcm_out(m, d, o)
    return PFD_MIN <= pfd <= PFD_MAX and VCO_MIN <= vco <= VCO_MAX


def eighths(lo, hi):
    """All multiples of 0.125 in [lo, hi]."""
    return [F(k, 8) for k in range(int(lo * 8), int(hi * 8) + 1)]


M_RANGE = eighths(2, 64)
O_RANGE = [F(1)] + eighths(2, 128)
D_RANGE = range(1, 11)          # PFD >= 10 MHz with a 100 MHz input -> D <= 10


def search(f_lo, f_hi):
    """Every legal (m, d, o) whose output lies in [f_lo, f_hi], deduplicated by frequency."""
    best = {}
    for d in D_RANGE:
        pfd = F_IN / d
        for m in M_RANGE:
            vco = pfd * m
            if not (VCO_MIN <= vco <= VCO_MAX):
                continue
            # o window for the requested output band
            o_lo, o_hi = vco / f_hi, vco / f_lo
            for o in O_RANGE:
                if o < o_lo or o > o_hi:
                    continue
                f = vco / o
                # keep the variant with the lowest D, then lowest M (= fewest bits, lowest jitter path)
                key = f
                if key not in best or (d, m) < (best[key][1], best[key][0]):
                    best[key] = (m, d, o)
    return sorted((f, p) for f, p in best.items())


def hz(f):
    return f"{float(f):,.3f} Hz".replace(",", "_")


def mhz(f):
    return f"{float(f) / 1e6:.6f} MHz"


def ppm(a, b):
    return float((a - b) / b * 1_000_000)


def hdmi_frame_rate(m, d, o1, htotal, vtotal):
    """Frame rate of an HDMI mode whose pixel clock is VCO / CLKOUT1_DIVIDE (video_out_clock.vhd)."""
    vco = F_IN / d * m
    pix = vco / o1
    return pix, pix / (htotal * vtotal)


def main():
    final_only = "--final" in sys.argv

    # ---------------------------------------------------------------- HDMI side
    # Values from M2M/vhdl/controllers/HDMI/video_out_clock.vhd (DRP tables)
    hdmi = {
        "1280x720p50    (CLK_SEL 010)": (F("37.125"), 5, 10, 1980, 750),
        "720x576p50     (CLK_SEL 001)": (F("47.25"), 5, 35, 864, 625),
        "720x480p59.94  (CLK_SEL 001)": (F("47.25"), 5, 35, 858, 525),
        "1280x720p59.94 (CLK_SEL 110)": (F("22.25"), 3, 10, 1650, 750),
    }
    rates = {}
    if not final_only:
        print("=" * 100)
        print("1. HDMI output frame rates as actually produced by video_out_clock.vhd")
        print("=" * 100)
    for name, (m, d, o1, ht, vt) in hdmi.items():
        pix, fr = hdmi_frame_rate(m, d, o1, ht, vt)
        rates[name] = fr
        if not final_only:
            print(f"  {name}: pixel clock {mhz(pix)}  frame rate {float(fr):.6f} Hz")
    hdmi_5994_max = max(rates["720x480p59.94  (CLK_SEL 001)"], rates["1280x720p59.94 (CLK_SEL 110)"])
    hdmi_5994_min = min(rates["720x480p59.94  (CLK_SEL 001)"], rates["1280x720p59.94 (CLK_SEL 110)"])
    if not final_only:
        nominal = F(60_000, 1001)
        print(f"  nominal 60/1.001 = {float(nominal):.6f} Hz; 720p59.94 is "
              f"{ppm(rates['1280x720p59.94 (CLK_SEL 110)'], nominal):+.1f} ppm off nominal")

        # Can a single MMCM do better for 74.1758 MHz? Pixel = VCO / (5k), 5x clock = VCO / k, k integer.
        target = F(74_250_000) / F(1001, 1000)
        best = None
        for d in D_RANGE:
            for m in M_RANGE:
                vco = F_IN / d * m
                if not (VCO_MIN <= vco <= F(1_440_000_000)) or F_IN / d < PFD_MIN:
                    continue
                for k in range(1, 26):
                    pix = vco / (5 * k)
                    e = abs(ppm(pix, target))
                    if best is None or e < best[0]:
                        best = (e, m, d, k, pix)
        e, m, d, k, pix = best
        print(f"  best single-MMCM 74.1758 MHz (VCO up to 1440): M={float(m)} D={d} CLKOUT0={k} CLKOUT1={5*k} "
              f"-> {mhz(pix)} ({ppm(pix, target):+.1f} ppm): the existing CLK_SEL 110 table is already optimal")
        print()

    # ---------------------------------------------------------------- core side
    pal_orig = (F("56.75"), 6, F(30))
    pal_slow = (F("60.5"), 9, F("21.375"))
    ntsc_orig_target = NTSC_IDEAL_CORE
    ntsc_ff_floor = hdmi_5994_max * CLK_PER_FRAME_NTSC     # core clock for exactly the faster 59.94 HDMI rate

    if not final_only:
        print("=" * 100)
        print("2. Reference values")
        print("=" * 100)
        print(f"  ideal PAL  core clock (17.734475 MHz * 16/9)   = {hz(PAL_IDEAL_CORE)}  "
              f"frame {float(PAL_IDEAL_CORE / CLK_PER_FRAME_PAL):.6f} Hz")
        print(f"  ideal NTSC core clock (14.318182 MHz * 16/7)   = {hz(NTSC_IDEAL_CORE)}  "
              f"frame {float(NTSC_IDEAL_CORE / CLK_PER_FRAME_NTSC):.6f} Hz")
        print(f"  MiSTer msum constants: PAL {hz(MISTER_PAL)}, NTSC {hz(MISTER_NTSC)}")
        print(f"  MiSTer Cyclone V fractional PLL (50 MHz * (11 + K/2^32) / 18):")
        for name, k in (("PAL ", 1503512573), ("NTSC", 3357876127)):
            f = F(50_000_000) * (11 + F(k, 2**32)) / 18
            print(f"      {name} K={k}: {hz(f)}")
        print(f"  core clock for exactly 50.000000 Hz            = {hz(50 * F(CLK_PER_FRAME_PAL))}")
        print(f"  core clock for the faster 59.94 HDMI rate      = {hz(ntsc_ff_floor)} "
              f"({float(hdmi_5994_max):.6f} Hz)")
        print()

        print("=" * 100)
        print("3. Candidates: NTSC original (as close as possible to 14.31818 MHz * 16 / 7)")
        print("=" * 100)
        cands = search(ntsc_orig_target * F(9995, 10000), ntsc_orig_target * F(10005, 10000))
        cands.sort(key=lambda t: abs(t[0] - ntsc_orig_target))
        print(f"  {'M':>7} {'D':>3} {'O0':>8} {'VCO MHz':>10} {'PFD MHz':>8} {'f_out Hz':>18} "
              f"{'frame Hz':>11} {'err ppm':>9}")
        for f, (m, d, o) in cands[:8]:
            vco, pfd, _ = mmcm_out(m, d, o)
            print(f"  {float(m):7.3f} {d:3d} {float(o):8.3f} {float(vco)/1e6:10.3f} {float(pfd)/1e6:8.3f} "
                  f"{float(f):18.3f} {float(f / CLK_PER_FRAME_NTSC):11.6f} {ppm(f, ntsc_orig_target):+9.3f}")
        print()

        print("=" * 100)
        print("4. Candidates: NTSC flicker-free (frame rate just ABOVE the faster 59.94 Hz HDMI rate)")
        print("=" * 100)
        cands = search(ntsc_ff_floor, ntsc_ff_floor * F(1_000_200, 1_000_000))
        cands = [c for c in cands if c[0] > ntsc_ff_floor]
        print(f"  {'M':>7} {'D':>3} {'O0':>8} {'VCO MHz':>10} {'PFD MHz':>8} {'f_out Hz':>18} "
              f"{'frame Hz':>11} {'ppm>480p':>9} {'ppm>720p':>9} {'vs orig %':>9}")
        for f, (m, d, o) in cands[:12]:
            vco, pfd, _ = mmcm_out(m, d, o)
            fr = f / CLK_PER_FRAME_NTSC
            print(f"  {float(m):7.3f} {d:3d} {float(o):8.3f} {float(vco)/1e6:10.3f} {float(pfd)/1e6:8.3f} "
                  f"{float(f):18.3f} {float(fr):11.6f} {ppm(fr, hdmi_5994_max):+9.2f} "
                  f"{ppm(fr, hdmi_5994_min):+9.2f} {float((f / NTSC_IDEAL_CORE - 1) * 100):+9.4f}")
        print()

    # ---------------------------------------------------------------- final table
    ntsc_orig = (F(36), 5, F(22))
    ntsc_fast = (F("47.75"), 5, F("29.125"))   # closest legal set above 59.940060 Hz
    final = [
        ("PAL original      (i_clk_c64_orig)",  pal_orig,  CLK_PER_FRAME_PAL,  F(50), PAL_IDEAL_CORE),
        ("PAL flicker-free  (i_clk_c64_slow)",  pal_slow,  CLK_PER_FRAME_PAL,  F(50), PAL_IDEAL_CORE),
        ("NTSC original     (i_clk_c64_ntsc)",  ntsc_orig, CLK_PER_FRAME_NTSC, hdmi_5994_max, NTSC_IDEAL_CORE),
        ("NTSC flicker-free (i_clk_c64_ntsc_ff)", ntsc_fast, CLK_PER_FRAME_NTSC, hdmi_5994_max, NTSC_IDEAL_CORE),
    ]
    print("=" * 100)
    print("FINAL TABLE (used in doc/dev-ntsc/NTSC-SPEC.md section 3)")
    print("=" * 100)
    print(f"  {'clock':37} {'M':>6} {'D':>2} {'O0':>7} {'VCO MHz':>9} {'PFD MHz':>8} "
          f"{'f_out Hz':>16} {'integer Hz':>11} {'frame Hz':>10} {'vs ideal ppm':>12}")
    for name, (m, d, o), cpf, _, ideal in final:
        assert legal(m, d, o), name
        vco, pfd, f = mmcm_out(m, d, o)
        print(f"  {name:37} {float(m):6.3f} {d:2d} {float(o):7.3f} {float(vco)/1e6:9.3f} {float(pfd)/1e6:8.3f} "
              f"{float(f):16.3f} {round(f):11d} {float(f / cpf):10.6f} {ppm(f, ideal):+12.1f}")
    print()

    # duty cycle and drift for the flicker-free pairs
    print("  Flicker-free duty cycle (share of time on the flicker-free clock) and frame drift:")
    pairs = [
        ("PAL  50 Hz modes   ", pal_orig, pal_slow, CLK_PER_FRAME_PAL, F(50)),
        ("NTSC 480p59.94     ", ntsc_orig, ntsc_fast, CLK_PER_FRAME_NTSC, rates["720x480p59.94  (CLK_SEL 001)"]),
        ("NTSC 720p59.94     ", ntsc_orig, ntsc_fast, CLK_PER_FRAME_NTSC, rates["1280x720p59.94 (CLK_SEL 110)"]),
    ]
    for name, a, b, cpf, target in pairs:
        fa = mmcm_out(*a)[2] / cpf
        fb = mmcm_out(*b)[2] / cpf
        share_b = (target - fa) / (fb - fa)
        lines = 312 if cpf == CLK_PER_FRAME_PAL else 263
        print(f"    {name}: HDMI {float(target):.6f} Hz | orig {float(fa):.6f} Hz "
              f"({float((fa - target) * lines):+7.2f} lines/s) | ff {float(fb):.6f} Hz "
              f"({float((fb - target) * lines):+7.3f} lines/s) | time on ff clock {float(share_b) * 100:6.2f} %")
        # Hysteresis window: G_THRESHOLD_HIGH - G_THRESHOLD_LOW = 0x1000 16-bit HyperRAM words = 8192 bytes;
        # ascal stores one input line per stride = width * 3 bytes rounded up to N_BURST = 128 bytes.
        width = 382 if cpf == CLK_PER_FRAME_PAL else 404
        stride = -(-width * 3 // 128) * 128
        w = F(8192, stride)
        print(f"{'':25}window {float(w):.2f} lines (stride {stride} bytes): one hysteresis cycle "
              f"{float(w / abs((fb - target) * lines)):7.2f} s on ff + {float(w / abs((fa - target) * lines)):5.3f} s on orig")
    print()
    print("  CORE_CLK_SPEED_PAL  =", round(mmcm_out(*pal_orig)[2]))
    print("  CORE_CLK_SPEED_NTSC =", round(mmcm_out(*ntsc_orig)[2]))


if __name__ == "__main__":
    main()
