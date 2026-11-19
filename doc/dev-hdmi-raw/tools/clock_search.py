#!/usr/bin/env python3
# Search 1+2: HDMI MMCM settings for the EXISTING core clocks.
from fractions import Fraction as F
import math

REF = F(100_000_000)
CORE = {  # name: (f_main, main clocks per frame)
    'PAL':  (REF * F(5675, 100) / (6 * 30), 312 * 63 * 32),
    'NTSC': (REF * 36 / (5 * 22),           263 * 65 * 32),
}
MODES = {  # name: (standard, Hact, Htot, Vact, Vtot, nominal pixel clock)
    'PAL 720p':  ('PAL', 1280, 1980, 720, 750, F(74_250_000)),
    'PAL 576p':  ('PAL',  720,  864, 576, 625, F(27_000_000)),
    'NTSC 720p': ('NTSC', 1280, 1650, 720, 750, F(74_250_000) * 1000 / 1001),
    'NTSC 480p': ('NTSC',  720,  858, 480, 525, F(27_000_000)),
}
VCO_MIN, VCO_MAX = F(600_000_000), F(1_440_000_000)

def mmcm_configs():
    for m in range(16, 513):            # CLKFBOUT_MULT_F = m/8
        for d in range(1, 11):          # PFD >= 10 MHz
            vco = REF * m / (8 * d)
            if not (VCO_MIN <= vco <= VCO_MAX):
                continue
            for n in range(1, 26):      # CLKOUT0 = n (5x), CLKOUT1 = 5n (1x)
                yield m, d, n, vco, vco / (5 * n)

cfgs = list(mmcm_configs())
print("MMCM configs:", len(cfgs))
for name, (std, hact, htot, vact, vtot, fnom) in MODES.items():
    fmain, fl = CORE[std]
    frate = fmain / fl
    ideal = frate * htot * vtot
    print(f"\n=== {name}: core frame rate {float(frate):.6f} Hz, ideal pixel clock {float(ideal)/1e6:.6f} MHz "
          f"({(float(ideal/fnom)-1)*100:+.4f} % vs nominal {float(fnom)/1e6:.4f})")
    # (1) approximations with standard totals
    best = {}
    for m, d, n, vco, fpix in cfgs:
        ppm = (float(fpix / ideal) - 1) * 1e6
        if abs(ppm) < 400:
            key = (fpix)
            if key not in best or (vco < best[key][3]):
                best[key] = (m, d, n, vco, fpix, ppm)
    rows = sorted(best.values(), key=lambda r: abs(r[5]))[:8]
    print(" standard totals, nearest pixel clocks:")
    for m, d, n, vco, fpix, ppm in rows:
        npf = fpix / frate              # pixel clocks per core frame
        surplus = npf - htot * vtot
        slip = 1 / (float(frate) * abs(ppm) * 1e-6) if ppm else float('inf')
        print(f"   M={m/8:7.3f} D={d:2d} O0={n:2d} O1={5*n:3d} VCO={float(vco)/1e6:8.3f} fpix={float(fpix)/1e6:10.6f} MHz "
              f"{ppm:+8.2f} ppm  slip every {slip:7.1f} s  pixels/frame-HxV={float(surplus):+9.3f} (den {npf.denominator})")
    # (2) exact solutions with custom totals
    sols = []
    for m, d, n, vco, fpix in cfgs:
        npf = fpix / frate
        if npf.denominator != 1:
            continue
        N = npf.numerator
        for v in range(vact + 6, vact + 120):
            if N % v:
                continue
            h = N // v
            if h < hact + 60 or h > hact * 2:
                continue
            # closeness to the standard: relative deviations
            score = abs(h / htot - 1) + 3 * abs(v / vtot - 1) + abs(float(fpix / fnom) - 1)
            sols.append((score, m, d, n, vco, fpix, h, v))
    seen = set(); out = []
    for s in sorted(sols):
        key = (s[5], s[6], s[7])
        if key in seen: continue
        seen.add(key); out.append(s)
    print(" exact solutions (HDMI frame rate equals core frame rate), custom totals, best 10:")
    for score, m, d, n, vco, fpix, h, v in out[:10]:
        print(f"   M={m/8:7.3f} D={d:2d} O0={n:2d} VCO={float(vco)/1e6:8.3f} fpix={float(fpix)/1e6:10.6f} MHz "
              f"({(float(fpix/fnom)-1)*100:+6.2f} %)  totals {h} x {v}  (std {htot} x {vtot}; H {100*(h/htot-1):+.2f} %, V {v-vtot:+d} lines)  "
              f"fH={float(fpix)/h/1e3:.3f} kHz")
