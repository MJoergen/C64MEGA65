#!/usr/bin/env python3
# Search 3: NEW core clock (close to the real C64) + HDMI clock with STANDARD totals and exactly equal frame rates.
from fractions import Fraction as F
REF = F(100_000_000)
VCO_MIN, VCO_MAX = F(600_000_000), F(1_440_000_000)
STD = {
  'PAL':  dict(real=F(17_734_475) * 4 / 9 * 4, fl=312*63*32, modes={'720p': 1980*750, '576p': 864*625}),
  'NTSC': dict(real=F(315_000_000, 22) * 4 / 7 * 4, fl=263*65*32, modes={'720p': 1650*750, '480p': 858*525}),
}
# HDMI ratios m2/(8*d2*5n) reachable
hd = {}
for m in range(16, 513):
    for d in range(1, 11):
        vco = REF * m / (8 * d)
        if not (VCO_MIN <= vco <= VCO_MAX): continue
        for n in range(1, 26):
            r = F(m, 40 * d * n)
            if r not in hd: hd[r] = (m, d, n)
print("distinct HDMI ratios:", len(hd))
for std, s in STD.items():
    print(f"\n=== {std}: real machine main clock {float(s['real'])/1e6:.6f} MHz")
    cands = []
    for m1 in range(16, 513):
        for d1 in range(1, 11):
            vco = REF * m1 / (8 * d1)
            if not (VCO_MIN <= vco <= VCO_MAX): continue
            # o1 in eighths
            o_center = float(vco * 8 / s['real'])
            for o1 in range(int(o_center) - 2, int(o_center) + 4):
                if o1 < 16: continue
                fmain = vco * 8 / o1
                ppm = (float(fmain / s['real']) - 1) * 1e6
                if abs(ppm) > 150: continue
                ok = {}
                for mn, hv in s['modes'].items():
                    r = (fmain / s['fl'] * hv) / REF      # needed f_pix / 100 MHz
                    if r in hd: ok[mn] = hd[r]
                if ok:
                    cands.append((abs(ppm), ppm, m1, d1, o1, vco, fmain, ok))
    cands.sort(key=lambda c: (-len(c[7]), c[0]))
    for a, ppm, m1, d1, o1, vco, fmain, ok in cands[:14]:
        print(f"  core M={m1/8:7.3f} D={d1:2d} O={o1/8:7.3f} VCO={float(vco)/1e6:8.3f} f={float(fmain)/1e6:.6f} MHz ({ppm:+7.2f} ppm vs real)  exact HDMI: "
              + "; ".join(f"{k}: M={v[0]/8:.3f} D={v[1]} O0={v[2]} ({float(REF*v[0]/(40*v[1]*v[2]))/1e6:.6f} MHz)" for k, v in ok.items()))
    print("  candidates:", len(cands))
