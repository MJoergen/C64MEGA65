#!/usr/bin/env python3
"""The ten video modes that existed before the raw modes, old tree versus new tree
(issue #184, doc/dev-hdmi-raw/SPEC.md section 8). Called by old_modes_diff.sh.

    old_modes_diff.py OLD_TREE NEW_TREE OLD_VCD NEW_VCD

1. Static (parsed with doc/dev-ntsc/tools/w2_checks.py of NEW_TREE): every mode record
   of the old tree is unchanged in the new tree except CLK_SEL (a leading '0') and the
   new fields CTS_FRAC_N / CTS_FRAC_D (0 / 1); the members 0 to 9 and VIDEO_MODE_VECTOR(0
   to 9) are the same; the framework decode maps each old member to the same record,
   and so to the same clock selector.
2. tb_window_av (CORE/vhdl/test/tb_ntsc, run_w2.sh window) of both trees: for every
   signal that both VCD files contain, the values at the end of all 100 steps of the
   modes 0 to 9 and the complete change history from 100 ns to the end of mode 9.
   Values are compared as numbers (hdmi_htotal is "natural range 0 to 4095" in the new
   tree, "integer" in the old one). The bench's xpm stub starts its outputs at all
   ones, so before the first HDMI clock edges (20 ns) the mode code is "1111": in the
   old tree the fallback 16:9 50 Hz, in the new tree the NTSC 5:4 raw member. On the
   hardware the synchronizer registers start at 0. That is why the histories start at
   100 ns, with the value at 100 ns.

Prints "RESULT: PASS" or "RESULT: FAIL ...".
"""
import os
import sys

sys.dont_write_bytecode = True
old_tree, new_tree, old_vcd, new_vcd = sys.argv[1:5]
sys.path.insert(0, os.path.join(new_tree, "doc", "dev-ntsc", "tools"))
import w2_checks as w   # noqa: E402

fails = 0

# ---------------------------------------------------------------------------- static
ro = w.parse_records(w.read(old_tree, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd"))
rn = w.parse_records(w.read(new_tree, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd"))
mo = w.parse_members(w.read(old_tree, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd"))
mn = w.parse_members(w.read(new_tree, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd"))
for name, r in ro.items():
    n = rn.get(name)
    exp = dict(r, CLK_SEL="0" + r["CLK_SEL"], CTS_FRAC_N=0, CTS_FRAC_D=1)
    ok = n == exp
    fails += not ok
    print("record %-22s %s" % (name, "same (CLK_SEL 0%s, CTS_FRAC 0/1)" % r["CLK_SEL"] if ok else "DIFFERS %s" % n))
ok = mn[:10] == mo
fails += not ok
print("members 0..9: %s" % ("same" if ok else "DIFFER"))
so, vo, do, dfo = w.parse_framework(w.read(old_tree, "M2M/vhdl/framework.vhd"))
sn, vn, dn, dfn = w.parse_framework(w.read(new_tree, "M2M/vhdl/framework.vhd"))
ok = vn[:10] == vo
fails += not ok
print("VIDEO_MODE_VECTOR(0 to 9): %s" % ("same" if ok else "DIFFER"))
for m in mo:
    reco, recn = do.get(m, dfo), dn.get(m, dfn)
    ok = reco == recn and rn[recn]["CLK_SEL"] == "0" + ro[reco]["CLK_SEL"]
    fails += not ok
    print("framework %-24s -> %-22s CLK_SEL %s -> %s %s" % (m, recn, ro[reco]["CLK_SEL"], rn[recn]["CLK_SEL"],
                                                           "ok" if ok else "DIFFERS"))

# ---------------------------------------------------------------------------- tb_window_av
def num(v):
    if set(v) - set("01"):
        return v
    n = int(v, 2)
    return n - (1 << 32) if len(v) == 32 and v[0] == "1" else n


def load(path):
    ch = w.parse_vcd(path)
    names = {n for _, n, _ in ch}
    return ch, names


old, on = load(old_vcd)
new, nn = load(new_vcd)
common = sorted(on & nn)
print("signals: old %d, new %d, common %d; only new: %s" % (len(on), len(nn), len(common), sorted(nn - on)))
# end of the old modes: first change of tb_phase to a value >= 2000 in the new VCD
t_end = min(t for t, n, v in new if n == "tb_phase" and int(v, 2) >= 2000)
print("old modes end at t = %d (VCD time units)" % t_end)


def samples(ch):
    st, out, ph = {}, {}, None
    for t, n, v in ch:
        if n == "tb_phase":
            if ph is not None:
                out[ph] = dict(st)
            ph = int(v, 2)
        st[n] = v
    return out


so, sn = samples(old), samples(new)
keys = sorted(k for k in so if 1000 <= k < 2000)
bad = 0
for k in keys:
    for n in common:
        if num(so[k].get(n, "?")) != num(sn.get(k, {}).get(n, "?")):
            bad += 1
            if bad <= 20:
                print("  step %d %s: old %s new %s" % (k, n, so[k].get(n), sn.get(k, {}).get(n)))
print("end-of-step values: %d steps x %d signals compared, %d differences" % (len(keys), len(common), bad))


# see the header for the reason of T_START
T_START = 100000000     # 100 ns in VCD units (fs)


def hist(ch, n):
    out = []
    cur = None
    for t, nm, v in ch:
        if nm != n or t >= t_end:
            continue
        v = num(v)
        if t <= T_START:
            cur = v
            continue
        if not out:
            out.append((T_START, cur))
        if out[-1][1] != v:
            out.append((t, v))
    if not out:
        out.append((T_START, cur))
    return out


hbad = 0
total = 0
for n in common:
    ho, hn = hist(old, n), hist(new, n)
    total += len(ho)
    if ho != hn:
        hbad += 1
        print("  history of %s differs: old %d changes, new %d changes; first old %s new %s" % (
            n, len(ho), len(hn), ho[:3], hn[:3]))
print("change histories from 100 ns to the end of mode 9: %d signals, %d value changes, %d signals differ" % (
    len(common), total, hbad))
fails += not (bad == 0 and hbad == 0 and len(keys) == 100)
print("RESULT: %s" % ("PASS" if fails == 0 else "FAIL %d" % fails))
sys.exit(0 if fails == 0 else 1)
