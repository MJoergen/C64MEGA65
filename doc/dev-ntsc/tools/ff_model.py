#!/usr/bin/env python3
"""Model of the HDMI flicker-free loop (M2M/vhdl/hdmi_flicker_free.vhd + CORE/vhdl/mega65.vhd).

Hardware being modeled
----------------------
* ascal writes the visible input picture line by line into one HyperRAM frame
  buffer at byte address  line * stride  (stride = visible width * 3 bytes,
  rounded up to N_BURST = 128 bytes). avm_decrease turns this into 16-bit
  HyperRAM word addresses, so hr_address = byte address / 2.
* hdmi_flicker_free keeps the last write address (CORE) and the last read
  address (HDMI). While the last HDMI read address is 0 (start of an output
  frame) it latches last_diff = last CORE write address. Then, as levels:
  low_o = last_diff < G_THRESHOLD_LOW (0x1000), high_o = last_diff >
  G_THRESHOLD_HIGH (0x2000). So there is one effective sample per output frame.
* mega65.vhd: hr_low_i -> hr_core_speed "00" (original clock),
  hr_high_i -> "01" (second clock). For PAL the original clock is the FAST one
  (50.124 Hz) and the second one the SLOW one (49.999 Hz).
  This model generalizes: low -> the faster clock, high -> the slower clock.
  For NTSC the native 6567R8 clock (59.826 Hz) is BELOW 59.94 Hz, so the
  second clock must be faster than the native one, and the low/high to clock
  mapping in mega65.vhd has to be the other way round than for PAL.

Model
-----
Time advances in output frames. phase = position of the CORE in its own frame,
in input frames, measured from the start of the first visible line. Per output
frame phase += f_frame_core / f_hdmi. At each output frame start the latched
write address is that of the last completed visible line (the write of a line
happens after the line has been received): D = (lines_done * stride - burst)/2
words, lines_done = min(floor(phase_in_lines), visible_lines); D is the end
of the previous frame (lines_done = visible_lines) right after the frame wraps.

Run without arguments for the built-in PAL validation plus NTSC candidates
(prints RESULT: PASS/FAIL). Run with --clocks etc. for one case.
"""

import argparse
import math
import sys

N_BURST = 128


def frame_rate(f_clk, cycles, lines):
    return f_clk / (cycles * lines * 32)


def stride_bytes(width_px):
    return int(math.ceil(width_px * 3 / N_BURST) * N_BURST)


def write_addr_words(phase, lines_total, vis_lines, stride):
    """Latched CORE write address (16-bit words) at an output frame start."""
    pos = (phase % 1.0) * lines_total          # input line position since first visible line
    done = min(int(math.floor(pos)), vis_lines)
    if done == 0:
        done = vis_lines                       # nothing written yet in this frame: last write was the old frame end
    return (done * stride - N_BURST) // 2


def simulate(f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi,
             th_low=0x1000, th_high=0x2000, seconds=3600.0, phase0=0.0, start_fast=True,
             max_acq_frames=None):
    f_fast, f_slow = max(f_a, f_b), min(f_a, f_b)
    r_fast = frame_rate(f_fast, cycles, lines)
    r_slow = frame_rate(f_slow, cycles, lines)
    stride = stride_bytes(width_px)
    res = {"f_fast": f_fast, "f_slow": f_slow, "r_fast": r_fast, "r_slow": r_slow,
           "stride": stride, "th_low_lines": th_low * 2 / stride, "th_high_lines": th_high * 2 / stride}
    if not (r_slow < f_hdmi < r_fast):
        res["lock"] = False
        res["reason"] = "HDMI rate is not between the two core frame rates"
        return res
    n_frames = int(seconds * f_hdmi)
    if max_acq_frames is not None:
        n_frames = max_acq_frames
    phase = phase0
    fast = start_fast
    locked_at = None
    t_fast = 0
    t_slow = 0
    in_frames = 0.0
    switches_to_fast = []
    dmin, dmax = None, None
    for k in range(n_frames):
        d = write_addr_words(phase, lines, vis_lines, stride)
        # the levels hr_low / hr_high, as mega65.vhd evaluates them
        if d < th_low:
            if not fast and locked_at is not None:
                switches_to_fast.append(k)
            fast = True
        elif d > th_high:
            fast = False
        if locked_at is None and th_low <= d <= th_high:
            locked_at = k
            if max_acq_frames is not None:
                break
        if locked_at is not None:
            dmin = d if dmin is None else min(dmin, d)
            dmax = d if dmax is None else max(dmax, d)
            if fast:
                t_fast += 1
            else:
                t_slow += 1
            in_frames += (r_fast if fast else r_slow) / f_hdmi
        phase += (r_fast if fast else r_slow) / f_hdmi
    res["lock"] = locked_at is not None
    res["locked_at_s"] = None if locked_at is None else locked_at / f_hdmi
    if max_acq_frames is not None or locked_at is None:
        return res
    n = t_fast + t_slow
    res["avg_rate"] = in_frames / n * f_hdmi
    res["duty_fast"] = t_fast / n
    res["avg_clk"] = res["duty_fast"] * f_fast + (1 - res["duty_fast"]) * f_slow
    if len(switches_to_fast) >= 2:
        gaps = [b - a for a, b in zip(switches_to_fast, switches_to_fast[1:])]
        res["period_s"] = sum(gaps) / len(gaps) / f_hdmi
        res["switches"] = len(switches_to_fast)
    else:
        res["period_s"] = None
        res["switches"] = len(switches_to_fast)
    res["dmin_lines"] = dmin * 2 / stride
    res["dmax_lines"] = dmax * 2 / stride
    # analytic cross-check: drift per output frame in input lines
    res["drift_fast_lines"] = (r_fast / f_hdmi - 1) * lines
    res["drift_slow_lines"] = (r_slow / f_hdmi - 1) * lines
    band = (th_high - th_low) * 2 / stride
    res["period_analytic_s"] = (band / res["drift_fast_lines"] - band / res["drift_slow_lines"]) / f_hdmi
    res["duty_analytic"] = -res["drift_slow_lines"] / (res["drift_fast_lines"] - res["drift_slow_lines"])
    return res


def worst_acquisition(f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi, steps=48, **kw):
    worst = 0.0
    for start_fast in (True, False):
        for i in range(steps):
            r = simulate(f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi, phase0=i / steps,
                         start_fast=start_fast, max_acq_frames=int(3600 * f_hdmi), **kw)
            if not r["lock"]:
                return None
            worst = max(worst, r["locked_at_s"])
    return worst


def report(name, f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi, seconds, acq=True, **kw):
    r = simulate(f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi, seconds=seconds, **kw)
    print(f"--- {name}")
    print(f"  geometry {cycles} x {lines}, visible {width_px} x {vis_lines}, stride {r['stride']} bytes; "
          f"thresholds {r['th_low_lines']:.2f} .. {r['th_high_lines']:.2f} input lines")
    print(f"  fast clock {r['f_fast']:>12,.0f} Hz -> {r['r_fast']:.6f} Hz   "
          f"slow clock {r['f_slow']:>12,.0f} Hz -> {r['r_slow']:.6f} Hz   HDMI {f_hdmi:.6f} Hz")
    if not r["lock"]:
        print(f"  NO LOCK: {r.get('reason', 'never entered the threshold band')}")
        return r
    err_ppm = (r["avg_rate"] - f_hdmi) / f_hdmi * 1e6
    print(f"  long-run average core frame rate {r['avg_rate']:.6f} Hz (error {err_ppm:+.3f} ppm)")
    per = "n/a" if r["period_s"] is None else f"{r['period_s']:.2f} s"
    print(f"  switching period {per} (analytic {r['period_analytic_s']:.2f} s), "
          f"time on fast clock {100 * r['duty_fast']:.3f} % (analytic {100 * r['duty_analytic']:.3f} %)")
    print(f"  drift per output frame: fast {r['drift_fast_lines']:+.4f} lines, slow {r['drift_slow_lines']:+.5f} lines")
    print(f"  write lead at output frame start stays within {r['dmin_lines']:.2f} .. {r['dmax_lines']:.2f} input lines")
    print(f"  average core clock {r['avg_clk']:,.1f} Hz -> C64 CPU {r['avg_clk'] / 32:,.2f} Hz")
    if acq:
        w = worst_acquisition(f_a, f_b, cycles, lines, vis_lines, width_px, f_hdmi, **kw)
        r["worst_acq_s"] = w
        print("  worst-case lock acquisition over 96 start phases/states: " +
              ("no lock within 1 h" if w is None else f"{w:.1f} s"))
    return r


def builtin():
    ok = True
    print("Flicker-free loop model (see the docstring for the modeled policy)\n")
    pal = report("PAL validation: 31,527,778 / 31,448,993 Hz at 50.000 Hz",
                 31527778, 31448993, 63, 312, 270, 382, 50.0, seconds=3600)
    if not pal["lock"] or abs(pal["avg_rate"] - 50.0) / 50.0 > 1e-6 or pal["dmin_lines"] <= 0:
        ok = False
        print("  ** PAL validation failed")
    print("\nNTSC frame rates (6567R8, 65 x 263, frame = clk / 547,040):")
    for f in (32727273, 32727264, 32789968, 32795000, 32800000, 32822400):
        print(f"  {f:>12,} Hz -> {frame_rate(f, 65, 263):.6f} Hz")
    f5994 = 60 / 1.001
    print(f"  clock for exactly 59.940060 Hz: {f5994 * 547040:,.1f} Hz;"
          f" for 60.000000 Hz: {60 * 547040:,.1f} Hz\n")
    for f2 in (32795000, 32800000):
        r = report(f"NTSC: 32,727,273 / {f2:,} Hz at 59.940060 Hz (720p59.94)",
                   32727273, f2, 65, 263, 250, 404, f5994, seconds=3600)
        if not r["lock"] or abs(r["avg_rate"] - f5994) / f5994 > 1e-6 or r["dmin_lines"] <= 0:
            ok = False
            print("  ** NTSC case failed")
        print()
    report("NTSC: 32,727,273 / 32,800,000 Hz at 60.000 Hz (720p60) - expected NO LOCK",
           32727273, 32800000, 65, 263, 250, 404, 60.0, seconds=60, acq=False)
    print("\nRESULT: PASS" if ok else "\nRESULT: FAIL see '**' lines above")
    return 0 if ok else 1


def main():
    if len(sys.argv) == 1:
        return builtin()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--clocks", nargs=2, type=float, required=True, metavar=("F1", "F2"))
    ap.add_argument("--geom", default="63x312", help="C64 cycles x lines per frame (PAL 63x312, NTSC 65x263)")
    ap.add_argument("--visible", default="382x270", help="visible width x lines seen by ascal")
    ap.add_argument("--hdmi", type=float, default=50.0, help="HDMI frame rate in Hz")
    ap.add_argument("--th-low", type=lambda x: int(x, 0), default=0x1000)
    ap.add_argument("--th-high", type=lambda x: int(x, 0), default=0x2000)
    ap.add_argument("--seconds", type=float, default=3600.0)
    a = ap.parse_args()
    c, l = (int(x) for x in a.geom.split("x"))
    w, v = (int(x) for x in a.visible.split("x"))
    r = report("custom", a.clocks[0], a.clocks[1], c, l, v, w, a.hdmi, a.seconds,
               th_low=a.th_low, th_high=a.th_high)
    print("RESULT: PASS" if r["lock"] else "RESULT: FAIL no lock")
    return 0 if r["lock"] else 1


if __name__ == "__main__":
    sys.exit(main())
