#!/usr/bin/env python3
"""Checker of tb_hdmi_raw_wiring (issue #184, doc/dev-hdmi-raw/SPEC.md section 5.1).

    check_wiring.py VCD REPO SCENARIO BUILD

BUILD is "real" (the real hdmi_genlock) or "hostile" (a genlock whose line length
is always wrong). All times are in femtoseconds; every signal is registered or
follows registers combinationally, so a value seen in the VCD at a time is the
value of the clock cycle that begins at that time.

Checks (see README.md):
  reference  for every rising edge of the core's vsync after the crop (crop_vs):
             video_ref falls one core clock later (if it was set) and rises one
             core clock after the first moment with crop_hblank = crop_vblank = '0';
             it changes at no other time. Every rising edge of video_ref gives
             exactly one hdmi_ref pulse of exactly one HDMI clock, 1 to 3 HDMI
             clocks later, and hdmi_ref has no other pulse. With zoom-in the
             cropped vblank falls in every visible line, the reference does not.
  kind 1     standard mode: the scaler's htotal (hdmi_ascal_htotal) and hdmi_htotal
             are the record's line length in every clock cycle, hdmi_raw = '0'; in
             the hostile build the genlock's htotal_o differs in every cycle
  kind 2     raw mode: hdmi_raw = '1', the scaler gets the genlock's htotal_o in
             every cycle, target 2 x CLK_KHZ; the distance d of every picture start
             (pixel clocks from the last hdmi_ref to the first rising edge of de
             after a falling edge of vs) agrees with the stretch the genlock takes
             where its control law is fixed (d at most 4096 above the target);
             locked_o rises and stays; after the lock every d lies in
             [target - surplus - 2, target + 2] (surplus of SPEC 4.2, 0 in 576p/480p)
  kind 3     raw mode after a change: as kind 2 up to the lock; the genlock measures
             again (at least two valid measurements) and takes the stretch of the rule
  kind 4     one-cycle raw code between two standard modes: the scaler gets the
             htotal of that code's record (the genlock comes out of its cleared state)
  kind 5     raw mode right after a pulse of hdmi_rst_i: the genlock was locked
             before, is not locked at the end of the pulse and not before its first
             valid measurement after it
  kind 6     raw mode in the hostile build: the scaler gets the genlock's htotal_o,
             which differs from hdmi_htotal

Prints "RESULT: PASS" or "RESULT: FAIL ...".
"""

import bisect
import importlib.util
import math
import os
import re
import sys
from fractions import Fraction

FAILS = []
NFAIL_PRINT = 30


def check(cond, what):
    if not cond:
        FAILS.append(what)
        if len(FAILS) <= NFAIL_PRINT:
            print("  MISMATCH: " + what)


# what each scenario must contain: (kind, mode) of its checked segments in order
EXPECT = {
    "A": [(2, 10), (5, 11), (1, 2), (3, 11)],
    "B": [(2, 11)],
    "C": [(2, 12)],
    "D": [(2, 13)],
    "E": [(1, 8), (2, 14), (1, 8)],
    "F": [(2, 15)],
    "G": [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (4, 10), (1, 8), (1, 9), (4, 13), (1, 0)],
    "H": [(1, 0), (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9), (6, 10)],
}
ZOOM = {"B", "E", "F"}
# surplus of a core frame over the HDMI frame in pixel clocks (SPEC 4.2), rounded up
SURPLUS = {10: 197, 11: 0, 12: 0, 13: 463, 14: 0, 15: 0}


class Sig:
    def __init__(self):
        self.t = []
        self.v = []

    def add(self, t, v):
        if self.t and self.t[-1] == t:
            self.v[-1] = v
        else:
            self.t.append(t)
            self.v.append(v)

    def at(self, t):
        """Value after all changes at time t."""
        i = bisect.bisect_right(self.t, t) - 1
        return self.v[i] if i >= 0 else None

    def changes(self, a, b):
        """(time, value) of the changes in [a, b)."""
        i = bisect.bisect_left(self.t, a)
        j = bisect.bisect_left(self.t, b)
        return list(zip(self.t[i:j], self.v[i:j]))

    def edges(self, rising=True):
        out = []
        prev = None
        for t, v in zip(self.t, self.v):
            if prev is not None and ((prev == "0" and v == "1") if rising else (prev == "1" and v == "0")):
                out.append(t)
            prev = v
        return out


def num(v):
    if v is None or set(v) - set("01"):
        return None
    n = int(v, 2)
    return n - (1 << 32) if len(v) == 32 and v[0] == "1" else n


def parse_vcd(path):
    ids, sigs = {}, {}
    t = 0
    with open(path) as f:
        defs = True
        for line in f:
            line = line.strip()
            if defs:
                m = re.match(r"\$var\s+\S+\s+\d+\s+(\S+)\s+(\S+)", line)
                if m:
                    name = re.sub(r"\[.*\]", "", m.group(2))
                    ids.setdefault(m.group(1), []).append(name)
                    sigs.setdefault(name, Sig())
                if line.startswith("$enddefinitions"):
                    defs = False
                continue
            if line.startswith("#"):
                t = int(line[1:])
            elif line.startswith("b"):
                v, i = line[1:].split()
                for n in ids.get(i, []):
                    sigs[n].add(t, v)
            elif line and line[0] in "01UXZWLH-" and line[1:] in ids:
                for n in ids[line[1:]]:
                    sigs[n].add(t, line[0])
    return sigs


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    vcd, repo, scen, build = sys.argv[1:5]
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("w2_checks", os.path.join(repo, "doc", "dev-ntsc", "tools", "w2_checks.py"))
    w2 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w2)
    recs = w2.parse_records(w2.read(repo, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd"))
    _, vector, _, _ = w2.parse_framework(w2.read(repo, "M2M/vhdl/framework.vhd"))
    tb = w2.strip_comments(w2.read(repo, "CORE/vhdl/test/tb_hdmi_raw_wiring/tb_hdmi_raw_wiring.vhd"))
    tbvec = re.findall(r"\b(C_\w+)", re.search(r"VIDEO_MODE_VECTOR\s*:.*?:=\s*\((.*?)\);", tb, re.S).group(1))
    check(tbvec == vector, "the vector of the bench is not VIDEO_MODE_VECTOR of framework.vhd")

    s = parse_vcd(vcd)
    need = ["tb_seg", "tb_kind", "tb_mode", "tb_period", "tb_tcore", "hdmi_rst", "crop_vs", "crop_hblank",
            "crop_vblank", "video_ref", "hdmi_ref", "hdmi_raw", "hdmi_htotal", "hdmi_ascal_htotal",
            "hdmi_genlock_target", "hdmi_vs", "hdmi_de", "htotal_o", "locked_o", "stretch_o"]
    missing = [n for n in need if n not in s]
    check(not missing, "signals missing in the VCD: %s" % missing)
    if missing:
        print("RESULT: FAIL")
        return 1
    t_end = max(sig.t[-1] for sig in s.values() if sig.t)
    period = lambda t: num(s["tb_period"].at(t))
    tcore = lambda t: num(s["tb_tcore"].at(t))

    # ------------------------------------------------------------------ reference
    vs_rise = s["crop_vs"].edges(True)
    hb, vb = s["crop_hblank"], s["crop_vblank"]
    vis_times = sorted(set(hb.t) | set(vb.t))
    exp_rise, exp_fall = [], []
    for tv in vs_rise:
        tc = tcore(tv)
        if s["video_ref"].at(tv + tc - 1) == "1":
            exp_fall.append(tv + tc)
        i = bisect.bisect_right(vis_times, tv)
        while i < len(vis_times):
            t = vis_times[i]
            if hb.at(t) == "0" and vb.at(t) == "0":
                exp_rise.append(t + tcore(t))
                break
            i += 1
    got_rise = s["video_ref"].edges(True)
    got_fall = s["video_ref"].edges(False)
    check(got_rise == [t for t in exp_rise if t < t_end],
          "video_ref rises at %s, expected %s" % (got_rise[:5], exp_rise[:5]))
    check(got_fall == [t for t in exp_fall if t < t_end],
          "video_ref falls at %s, expected %s" % (got_fall[:5], exp_fall[:5]))
    pr, pf = s["hdmi_ref"].edges(True), s["hdmi_ref"].edges(False)
    check(len(pr) == len(got_rise), "%d hdmi_ref pulses for %d rising edges of video_ref" % (len(pr), len(got_rise)))
    for k, (r, f) in enumerate(zip(pr, pf + [None] * (len(pr) - len(pf)))):
        p = period(r)
        check(f is not None and (f - r == p or f - r == period(f - 1)),
              "hdmi_ref pulse %d: %s fs wide, HDMI clock %s fs" % (k, None if f is None else f - r, p))
        if k < len(got_rise):
            lag = r - got_rise[k]
            check(0 < lag <= 3 * max(p, period(got_rise[k])),
                  "hdmi_ref pulse %d comes %s fs after video_ref (clock %s fs)" % (k, lag, p))
    frames = len(vs_rise)
    vb_falls = len(vb.edges(False))
    print("reference: %d core frames (rising edges of crop_vs), %d falling edges of crop_vblank, "
          "%d rises of video_ref, %d hdmi_ref pulses of one HDMI clock" % (frames, vb_falls, len(got_rise), len(pr)))
    if scen in ZOOM:
        check(vb_falls > 100 * max(1, frames), "zoom-in: crop_vblank falls only %d times" % vb_falls)
        print("zoom-in: crop_vblank falls %.0f times per core frame, the reference once" % (vb_falls / max(1, frames)))
    if scen not in ("G", "H"):
        check(len(pr) >= 8, "fewer than 8 reference pulses")

    # ------------------------------------------------------------------ segments
    marks = sorted(set(s["tb_kind"].t) | set(s["tb_mode"].t) | set(s["tb_seg"].t))
    segs = []
    for i, t in enumerate(marks):
        kind, mode, seg = num(s["tb_kind"].at(t)), num(s["tb_mode"].at(t)), num(s["tb_seg"].at(t))
        b = marks[i + 1] if i + 1 < len(marks) else t_end
        if kind and b > t:
            if segs and segs[-1][2:] == (kind, mode, seg):
                segs[-1] = (segs[-1][0], b, kind, mode, seg)
            else:
                segs.append((t, b, kind, mode, seg))
    got = [(k, m) for _, _, k, m, _ in segs]
    check(got == EXPECT[scen], "segments %s, expected %s" % (got, EXPECT[scen]))

    def all_values(name, a, b):
        return [s[name].at(a)] + [v for _, v in s[name].changes(a + 1, b)]

    def same_in(n1, n2, a, b):
        ts = sorted(set([a] + [t for t, _ in s[n1].changes(a, b)] + [t for t, _ in s[n2].changes(a, b)]))
        return [t for t in ts if s[n1].at(t) != s[n2].at(t)]

    # picture starts as the genlock sees them
    vsS, deS = s["hdmi_vs"], s["hdmi_de"]
    ev = sorted([(t, "v") for t in vsS.edges(False)] + [(t, "d") for t in deS.edges(True)])
    pics, armed = [], False
    for t, e in ev:
        if e == "v":
            armed = True
        elif armed:
            pics.append(t)
            armed = False

    print("%-4s %-4s %-26s %-14s %s" % ("seg", "kind", "mode", "fs", "result"))
    for a, b, kind, mode, seg in segs:
        rec = recs[vector[mode]]
        ht = rec["H_PIXELS"] + rec["H_FP"] + rec["H_PULSE"] + rec["H_BP"]
        p = period(a)
        notes = []
        if kind in (1, 4):
            vals = all_values("hdmi_ascal_htotal", a, b)
            check(all(num(v) == ht for v in vals), "seg %d mode %d: scaler htotal %s, record %d" % (
                seg, mode, sorted(set(num(v) for v in vals)), ht))
            if kind == 1:
                check(all(num(v) == ht for v in all_values("hdmi_htotal", a, b)), "seg %d: hdmi_htotal" % seg)
                check(all(v == "0" for v in all_values("hdmi_raw", a, b)), "seg %d: hdmi_raw" % seg)
                n_cyc = (b - a) // p
                notes.append("scaler htotal %d in all %d clock cycles" % (ht, n_cyc))
                if build == "hostile":
                    gv = all_values("htotal_o", a, b)
                    check(all(num(v) != ht for v in gv), "seg %d: the hostile genlock is not hostile" % seg)
                    notes.append("genlock says %s" % sorted(set(num(v) for v in gv)))
            else:
                check(all(v == "1" for v in all_values("hdmi_raw", a, b)), "seg %d: hdmi_raw in the glitch" % seg)
                check(b - a == p, "seg %d: the raw code lasts %d fs, the clock period is %d fs" % (seg, b - a, p))
                notes.append("one cycle of %s fs, scaler htotal %d" % (b - a, ht))
        if kind in (2, 3, 5, 6):
            check(all(v == "1" for v in all_values("hdmi_raw", a, b)), "seg %d: hdmi_raw" % seg)
            diff = same_in("hdmi_ascal_htotal", "htotal_o", a, b)
            check(not diff, "seg %d: the scaler does not get the genlock's htotal at %s" % (seg, diff[:3]))
            target = 2 * rec["CLK_KHZ"]
            check(all(num(v) == target for v in all_values("hdmi_genlock_target", a, b)), "seg %d: target" % seg)
        if kind == 6:
            hv = all_values("htotal_o", a, b)
            check(all(num(v) != ht for v in hv), "seg %d: the hostile genlock is not visible" % seg)
            notes.append("scaler gets the genlock's %s" % sorted(set(num(v) for v in hv)))
        if kind in (2, 3, 5):
            refs = [t for t in pr if a <= t < b]
            meas = []
            last_pic = a
            for tp in [t for t in pics if a < t < b]:
                rs = [t for t in pr if t < tp]
                valid = bool(rs) and rs[-1] >= last_pic
                d = None
                if rs:
                    q = Fraction(tp - rs[-1], p)
                    check(q.denominator == 1, "seg %d: picture start %d not on the clock grid" % (seg, tp))
                    d = int(q)
                meas.append((tp, valid, d))
                last_pic = tp
            # the genlock's stretch agrees with the measured distance; only where every version of
            # its control law gives the same stretch (SPEC 5.3): at or below the target, and in
            # the first 4096 pixel clocks above it (the no-stretch band is at least that wide)
            for tp, valid, d in meas:
                k = num(s["stretch_o"].at(tp + p))
                if not valid or d >= target + 4096:
                    continue
                exp = min(target - d, 4080) if d <= target else 0
                check(k == exp, "seg %d: picture start at %d: d %s, stretch %s, expected %s" % (seg, tp, d, k, exp))
            lk = s["locked_o"]
            l_rise = [t for t in lk.edges(True) if a <= t < b]
            ds = [d for _, v, d in meas if v]
            if kind == 2:
                check(len(l_rise) == 1, "seg %d: locked_o rises %d times" % (seg, len(l_rise)))
                if l_rise:
                    tl = l_rise[0]
                    check(all(v == "1" for v in all_values("locked_o", tl, b)), "seg %d: lock lost" % seg)
                    hold = [d for tp, v, d in meas if v and tp > tl]
                    lo, hi = target - SURPLUS[mode] - 2, target + 2
                    check(len(hold) >= 3 and all(lo <= d <= hi for d in hold),
                          "seg %d: distances after the lock %s, allowed %d to %d" % (seg, hold, lo, hi))
                    notes.append("locked after %d measurements; d after the lock %s (target %d)" % (
                        sum(1 for tp, v, d in meas if tp <= tl), sorted(set(hold)), target))
            if kind == 3:
                # the genlock measures again after the change; its stretch follows the rule (above)
                check(len(ds) >= 2, "seg %d: %d valid measurements after the change" % (seg, len(ds)))
                notes.append("valid measurements %d with d %s, stretch %s as the rule says" % (
                    len(ds), sorted(set(ds))[:3], sorted(set(num(v) for v in all_values("stretch_o", a, b)))[:4]))
            if kind == 5:
                rst_r = [t for t in s["hdmi_rst"].edges(True) if t < a]
                rst_f = [t for t in s["hdmi_rst"].edges(False) if t <= a]
                check(rst_r and lk.at(rst_r[-1] - 1) == "1", "seg %d: the genlock was not locked before the pulse" % seg)
                check(rst_f and lk.at(rst_f[-1]) == "0", "seg %d: locked_o at the end of the pulse" % seg)
                first_valid = next((tp for tp, v, d in meas if v), b)
                check(all(v == "0" for v in all_values("locked_o", a, first_valid)),
                      "seg %d: locked_o before the first valid measurement after the pulse" % seg)
                notes.append("locked before the pulse, not after it; first valid measurement %s" % (
                    "found" if first_valid < b else "none"))
        print("%-4d %-4d %-26s %-14d %s" % (seg, kind, vector[mode], p, "; ".join(notes)))

    if FAILS:
        print("RESULT: FAIL %d mismatch(es)" % len(FAILS))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
