#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Bench for the "Raw" HDMI modes (issue #184) with the real scaler, see README.md
#
#   CORE/vhdl/test/tb_hdmi_raw/run.sh [quick|full|extra] [--keep]
#
# Builds tb_hdmi_raw.vhd with the real M2M/vhdl/av_pipeline/ascal.vhd (two start-up expressions
# rewritten for GHDL, see README.md), M2M/vhdl/av_pipeline/crop.vhd and
# M2M/vhdl/av_pipeline/hdmi_genlock.vhd, runs the simulations of the chosen set and evaluates them.
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3; nvc 1.21 (or $NVC) if present:
# SIM=nvc (the default when nvc is found) runs the simulations with nvc, about ten times faster,
# and the full set also runs a reference configuration with both simulators, whose results
# (a hash over every output of the scaler in every clock) must be equal; SIM=ghdl runs everything
# with GHDL. JOBS (default 3) sets the number of parallel simulations. Runtimes: see README.md.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
JOBS=${JOBS:-3}
GENLOCK=${GENLOCK:-$REPO/M2M/vhdl/av_pipeline/hdmi_genlock.vhd}
NVC=${NVC:-$(command -v nvc || true)}
SIM=${SIM:-auto}
if [ "$SIM" = auto ]; then
   if [ -n "$NVC" ]; then SIM=nvc; else SIM=ghdl; fi
fi
case "$SIM" in
   ghdl) ;;
   nvc) [ -n "$NVC" ] && [ -x "$NVC" ] || { echo "SIM=nvc, but nvc is not found"; exit 2; } ;;
   *) echo "SIM must be ghdl or nvc"; exit 2 ;;
esac

SET=quick
KEEP=0
for a in "$@"; do
   case "$a" in
      quick|full|extra) SET=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [quick|full|extra] [--keep]"; exit 2 ;;
   esac
done

[ -f "$GENLOCK" ] || { echo "missing $GENLOCK"; exit 1; }
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_hdmi_raw.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
START=$(date +%s)

# --------------------------------------------------------------------------------------------------
# GHDL copy of ascal.vhd: two expressions that are negative for a moment after the start (while the
# scaler has not yet seen an input picture) are written with the modulo wrap that the hardware
# performs anyway. GHDL would otherwise stop with a bound check failure. Nothing else changes.
# --------------------------------------------------------------------------------------------------
python3 - "$REPO/M2M/vhdl/av_pipeline/ascal.vhd" "$BUILD/ascal_ghdl.vhd" <<'PYEOF' || { echo "RESULT: FAIL: the GHDL patch of ascal.vhd does not apply"; exit 1; }
import sys
src = open(sys.argv[1], encoding="utf-8").read()
patches = [
    # o_pshift is natural range 0 to 15, o_off(0) is 0 before the first line: 4-bit wrap
    ("          o_pshift<=o_off(0) -1;",
     "          o_pshift<=(o_off(0) + 15) MOD 16;"),
    # o_ihsizem is natural range 0 to 4095, o_ihsize is 0 before the first input picture: 12-bit wrap
    ("            o_ihsizem<=o_ihsize + o_off(0) - 2;",
     "            o_ihsizem<=(o_ihsize + o_off(0) + 4094) MOD 4096;"),
]
for old, new in patches:
    if src.count(old) != 1:
        sys.exit("pattern not found exactly once: " + old.strip())
    src = src.replace(old, new)
open(sys.argv[2], "w", encoding="utf-8").write(src)
PYEOF

echo "building (GHDL $("$GHDL" --version | head -1 | awk '{print $2}'))"
( cd "$BUILD" &&
  "$GHDL" -a $GF --workdir=. ascal_ghdl.vhd "$REPO/M2M/vhdl/av_pipeline/crop.vhd" "$GENLOCK" \
                             "$HERE/tb_hdmi_raw.vhd" &&
  "$GHDL" -e $GF --workdir=. tb_hdmi_raw ) > "$BUILD/build.log" 2>&1 ||
   { grep -v warning "$BUILD/build.log" | head -30; echo "RESULT: FAIL: build"; exit 1; }
if [ "$SIM" = nvc ]; then
   echo "building ($("$NVC" --version | head -1))"
   mkdir -p "$BUILD/nvc" &&
   ( cd "$BUILD/nvc" &&
     "$NVC" --std=2008 -a "$BUILD/ascal_ghdl.vhd" "$REPO/M2M/vhdl/av_pipeline/crop.vhd" "$GENLOCK" \
                           "$HERE/tb_hdmi_raw.vhd" ) > "$BUILD/build_nvc.log" 2>&1 ||
      { grep -v Warning "$BUILD/build_nvc.log" | head -30; echo "RESULT: FAIL: build (nvc)"; exit 1; }
fi

# --------------------------------------------------------------------------------------------------
# The list of simulations: name, expectation (pass/fail), generics
# --------------------------------------------------------------------------------------------------
python3 - "$SET" "$SIM" > "$BUILD/runs.txt" <<'PYEOF'
import sys, math
from fractions import Fraction as Fr
SET, SIM = sys.argv[1], sys.argv[2]

# core clocks (CORE/vhdl/clk.vhd): half periods in ps as fractions
CORE = {"PAL": Fr(10_000 * 6 * 30, 2) / Fr(5675, 100), "NTSC": Fr(10_000 * 5 * 22, 2) / 36}
# core geometry (video_sync.vhd): dots per line, lines, first visible line, first visible dot
GEO = {"PAL": (504, 312, 28, 107), "NTSC": (520, 263, 13, 112)}
# crop.vhd with zoom-in: offset of the scaler's first line and column inside the visible area
CROP = {"PAL": (30, 19), "NTSC": (21, 30)}

def half(mhz_num, mhz_den):           # half period in ps of 100 MHz x num / den
    return Fr(10_000, 2) * mhz_den / mhz_num

# HDMI modes: timing as ascal gets it (digital_pipeline.vhd), pixel clock as 100 MHz x num/den,
# CLK_KHZ of the record (target_i = 2 x CLK_KHZ)
def m(std, ht, hss, hse, hd, vt, vss, vse, vd, hmin, hmax, vmin, vmax, clk, khz):
    return dict(std=std, ht=ht, hss=hss, hse=hse, hd=hd, vt=vt, vss=vss, vse=vse, vd=vd,
                hmin=hmin, hmax=hmax, vmin=vmin, vmax=vmax, half=half(*clk), khz=khz)
MODES = {
    # raw modes (SPEC.md section 4)
    "pal720":    m("PAL", 1980, 1720, 1760, 1280, 750, 725, 730, 720, 160, 1119, 0, 719, (67, 90), 74444),
    "pal576":    m("PAL", 864, 732, 796, 720, 624, 580, 585, 576, 0, 719, 0, 575, (227, 840), 27023),
    "pal576_54": m("PAL", 864, 732, 796, 720, 624, 580, 585, 576, 0, 719, 18, 558, (227, 840), 27023),
    "ntsc720":   m("NTSC", 1650, 1390, 1430, 1280, 750, 725, 730, 720, 160, 1119, 0, 719, (237, 320), 74062),
    "ntsc480":   m("NTSC", 858, 736, 798, 720, 526, 489, 495, 480, 0, 719, 0, 479, (27, 100), 27000),
    "ntsc480_54":m("NTSC", 858, 736, 798, 720, 526, 489, 495, 480, 0, 719, 15, 465, (27, 100), 27000),
    # standard modes (video_modes_pkg.vhd)
    "pal576std": m("PAL", 864, 732, 796, 720, 625, 581, 586, 576, 0, 719, 0, 575, (27, 100), 27000),
    "ntsc480std":m("NTSC", 858, 736, 798, 720, 525, 489, 495, 480, 0, 719, 0, 479, (27, 100), 27000),
    "ntsc480std_54":m("NTSC", 858, 736, 798, 720, 525, 489, 495, 480, 0, 719, 15, 465, (27, 100), 27000),
}

def run(name, expect, mode, frames, d0_ms=2.0, crop=False, raw=True, target=None, mem="real",
        settle=0, dcheck=True, extra="", clk_scale=Fr(1), core_half=None, no_genlock=False, sim="default",
        skip=None):
    md = MODES[mode]
    std = md["std"]
    # The first HDMI picture is not checked where a line of the input picture takes 9 bursts
    # (382 columns in PAL, 348 with zoom-in): the scaler shows a wrong first picture there after
    # its start, the second and all later ones are right (NTSC without zoom-in: 404 columns, 10
    # bursts, right from the first picture on).
    if skip is None:
        skip = 1 if (std == "PAL" or crop) else 0
    dots, lines, vb, hb = GEO[std]
    ch = core_half if core_half is not None else CORE[std]
    oh = md["half"] / clk_scale
    tc, th = 2 * ch, 2 * oh                      # periods in ps
    T = dots * lines * 4 * tc                    # core frame
    if target is None:
        target = 2 * md["khz"]
    # The core model starts in raster line LINE0 (a few lines before its vsync), so its raster
    # frame 0 begins after o lines; the reference is the first visible pixel after the vsync
    # (crop.vhd adds one pixel enable), here of the first complete picture.
    line0 = 300 if std == "PAL" else 0
    o = (lines - line0) % lines
    y0, x0 = CROP[std] if crop else (0, 0)
    t_ref = ((o + vb + y0) * dots + hb + x0 + 1) * 4 * tc + 3 * th
    # The first HDMI picture shall begin d0 after the reference of the core's second picture. Before
    # it, the HDMI timing makes one short pass of START lines; the first HDMI picture begins after
    # those, the three lines by which the scaler's output counters follow its lead counter, and 11
    # clocks of its pipeline. The scaler sees the end of an input picture only while its output
    # clock runs: the HDMI clock has to start 50 us before the vsync that ends the core's first
    # complete picture (PAL: frame 0, line 307; NTSC: line 0 of frame 1).
    t_pic = Fr(d0_ms) * 10**9 + T + t_ref
    vs_line = o + 307 if std == "PAL" else lines
    t_vs = (vs_line * dots + (10 if std == "PAL" else 16)) * 4 * tc
    line_h = md["ht"] * th
    start = max(40, math.ceil((t_pic - 11 * th - t_vs + 50 * 10**6) / line_h) - 3)
    assert start - 8 > 0 and start < 4096
    # (the HDMI clock also runs 16 periods at the very beginning, through the reset of the scaler)
    t0 = t_pic - ((start + 3) * md["ht"] + 11 - 16) * th  # ps
    assert t0 > 0 and t0 + (start - 3) * line_h > t_vs + 20 * 10**6
    g = ["-gG_NTSC=%s" % ("true" if std == "NTSC" else "false"), "-gG_CORE_LINE0=%d" % line0,
         "-gG_CROP=%s" % ("true" if crop else "false"),
         "-gG_CORE_NUM_PS=%d" % ch.numerator, "-gG_CORE_DEN=%d" % ch.denominator,
         "-gG_HTOTAL=%d" % md["ht"], "-gG_HSSTART=%d" % md["hss"], "-gG_HSEND=%d" % md["hse"],
         "-gG_HDISP=%d" % md["hd"], "-gG_VTOTAL=%d" % md["vt"], "-gG_VSSTART=%d" % md["vss"],
         "-gG_VSEND=%d" % md["vse"], "-gG_VDISP=%d" % md["vd"], "-gG_HMIN=%d" % md["hmin"],
         "-gG_HMAX=%d" % md["hmax"], "-gG_VMIN=%d" % md["vmin"], "-gG_VMAX=%d" % md["vmax"],
         "-gG_HDMI_NUM_PS=%d" % oh.numerator, "-gG_HDMI_DEN=%d" % oh.denominator,
         "-gG_HDMI_START_NS=%d" % round(t0 / 1000),
         "-gG_RAW=%s" % ("true" if raw else "false"),
         "-gG_NO_GENLOCK=%s" % ("true" if no_genlock else "false"),
         "-gG_START_LINES=%d" % start, "-gG_TARGET=%d" % target, "-gG_TCORE=%d" % (T // 10000),
         "-gG_FRAMES=%d" % (frames + skip), "-gG_CHECK_FROM=%d" % skip, "-gG_SETTLE=%d" % (settle + skip)]
    assert oh.numerator < 2**31 and ch.numerator < 2**31
    if not raw:
        g += ["-gG_D_STEP=-1"]                    # standard mode: d drifts with the rate difference
    if dcheck and raw:
        # SPEC 5.3: locked from target - 1024; no stretch up to target + band, band = 1.25 x target
        tg = 2 * md["khz"]
        g += ["-gG_D_LO=%d" % (tg - 1024), "-gG_D_HI=%d" % (tg + tg + tg // 4 - 1)]
    if mem == "slow":
        # pessimistic (R3, HyperRAM shared with REU, cartridge and drives, and QNICE): 0 to 0.3 us
        # extra before every burst, 1 us before one burst in 20
        g += ["-gG_MEM_EXTRA=30", "-gG_MEM_PAUSE=100", "-gG_MEM_PAUSE_ONE=20"]
    if mem == "heavy":
        # more than the scaler always tolerates: 0 to 0.5 us before every burst, 2 us before one in 20
        g += ["-gG_MEM_EXTRA=50", "-gG_MEM_PAUSE=200", "-gG_MEM_PAUSE_ONE=20"]
    if extra:
        g += extra.split()
    print(name, expect, sim, " ".join(g))

if SET == "quick":
    run("raw_ntsc480", "pass", "ntsc480", 1)
    run("zoom_ntsc480", "pass", "ntsc480", 1, crop=True)
    run("mutant_target_0.1ms_ntsc480", "fail", "ntsc480", 1, d0_ms=0.1, target=2700, dcheck=False)
elif SET == "full":
    # (the longest simulations first: the runner takes them in this order)
    # 1 and 2: the six raw modes (the critical one for the bottom of the picture with the
    # pessimistic memory)
    run("raw_pal720", "pass", "pal720", 5)
    run("raw_ntsc720", "pass", "ntsc720", 5)
    if SIM == "nvc":
        # the reference: the same configuration with both simulators, the results must be equal
        run("reference_ghdl_raw_ntsc480", "pass", "ntsc480", 1, sim="ghdl")
        run("reference_nvc_raw_ntsc480", "pass", "ntsc480", 1, sim="nvc")
    run("raw_pal576", "pass", "pal576", 6)
    run("raw_pal576_54", "pass", "pal576_54", 6)
    run("raw_ntsc480", "pass", "ntsc480", 6)
    run("raw_ntsc480_54_slowmem", "pass", "ntsc480_54", 6, mem="slow")
    # 3: zoom-in switched off after HDMI frame 1 and on again after frame 5, while locked: the
    # core's picture start moves 1.33 ms earlier and back; the first jump stays inside the band (no
    # stretch), the second returns to the target. The scaler needs up to three frames for a new
    # input size (frames 2 to 4 and 6 to 8: reported, not judged)
    run("zoomtoggle_ntsc480", "pass", "ntsc480", 9, crop=True, extra="-gG_CROP_FLIP1=1 -gG_CROP_FLIP2=5")
    # 3: zoom-in, with the pessimistic memory
    run("zoom_pal576_slowmem", "pass", "pal576", 4, crop=True, mem="slow")
    run("zoom_ntsc480_slowmem", "pass", "ntsc480", 4, crop=True, mem="slow")
    # 2: start phases inside the band (no stretch): the reader 2.4 ms further behind
    run("inband_ntsc480", "pass", "ntsc480", 3, d0_ms=4.4)
    run("inband_zoom_ntsc480", "pass", "ntsc480", 3, d0_ms=4.4, crop=True)
    # 4: pull-in. From 1.5 stretches of 4080 below the target: frames 0 and 1 are stretched (4080,
    # 2040), from frame 2 on the phase is at the target. From inside the tear zone (the HDMI
    # picture begins 0.05 ms after the core's): tears are allowed in every frame, the geometry is
    # checked in every frame, the evaluation requires a tear in the first checked frame and none in
    # the last one. The bench's frame buffer holds no earlier picture before frame 0 (on hardware
    # a line fetched too early shows the previous frame): frame 0 is not checked; leaving the tear
    # zone (d below 0.79 ms in this mode) takes five stretches of 4080 from 0.05 ms.
    run("pullin_ntsc480", "pass", "ntsc480", 4, d0_ms=2.0 - 1.5 * 4080 / 27000, settle=2)
    run("pullin_from_tear_ntsc480", "pass", "ntsc480", 7, d0_ms=0.05, settle=99, dcheck=False, skip=1)
    # 5: standard mode with the genlock and the multiplexer, and without both
    run("std_ntsc480_genlock", "pass", "ntsc480std", 2, raw=False, dcheck=False)
    run("std_ntsc480_nogenlock", "pass", "ntsc480std", 2, raw=False, dcheck=False, no_genlock=True)
    # 2: the memory latency the scaler tolerates, independent of the genlock: the standard mode
    # with zoom-in and a memory slower than "slowmem" (information)
    run("heavymem_std_zoom_ntsc480", "info", "ntsc480std", 4, crop=True, raw=False, dcheck=False, mem="heavy")
    # 6: mutants of the setup that must fail
    run("mutant_target_0.1ms_ntsc480", "fail", "ntsc480", 1, d0_ms=0.1, target=2700, dcheck=False)
    run("mutant_clock_10pct_fast_ntsc480", "fail", "ntsc480", 1, clk_scale=Fr(11, 10), dcheck=False)
    run("mutant_old_reference_zoom_ntsc480", "fail", "ntsc480", 1, d0_ms=2.0 + 1000 / 27000, crop=True,
        settle=-1, extra="-gG_REF_OLD=true")
elif SET == "extra":
    # The upper end of the tear-free range of d in PAL 576p 4:3, as the full set computes it from
    # raw_pal576 (18.884 ms): static raw timing (the genlock disabled by the multiplexer, so d
    # stays where it starts), d 0.2 ms below and 0.2 ms above it.
    run("range_below_upper_end_pal576", "pass", "pal576", 1, d0_ms=18.684, raw=False, dcheck=False)
    run("range_above_upper_end_pal576", "fail", "pal576", 1, d0_ms=19.084, raw=False, dcheck=False)
    # today's standard NTSC 480p with flicker-free: on average the core runs at the HDMI frame rate
    # and the writer is 0x1000 to 0x2000 words (6.4 to 12.8 lines) ahead of the reader at the top.
    # Model: no genlock, the core clock exactly at the HDMI frame rate, the phase at both thresholds.
    for mode in ("ntsc480std", "ntsc480std_54"):
        md = MODES[mode]
        t_hdmi = 2 * md["half"] * md["ht"] * md["vt"]          # ps
        ch = t_hdmi / (520 * 263 * 4 * 2)
        for tag, d0 in (("low", 0.50), ("high", 0.91)):
            run("ff_%s_%s" % (mode, tag), "info", mode, 2, d0_ms=d0, raw=False, dcheck=False,
                no_genlock=True, core_half=ch)
PYEOF

NRUNS=$(wc -l < "$BUILD/runs.txt" | tr -d ' ')
echo "set '$SET': $NRUNS simulations, $JOBS at a time"

# all simulations, JOBS at a time, each with a timeout of 3 hours
python3 - "$GHDL" "$BUILD" "$JOBS" "$SIM" "$NVC" <<'PYEOF'
import re, shutil, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
ghdl, build, jobs, default_sim, nvc = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
runs = [l.split(None, 3) for l in open(build + "/runs.txt").read().splitlines() if l.strip()]
def sim(r):
    name, expect, simulator, generics = r
    if simulator == "default":
        simulator = default_sim
    t = time.time()
    try:
        if simulator == "ghdl":
            p = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", "tb_hdmi_raw",
                                "--ieee-asserts=disable"] + generics.split(),
                               cwd=build, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10800)
            out = p.stdout + p.stderr
        else:
            # nvc takes the generics at elaboration: every run elaborates in a copy of the library
            d = build + "/nvc_" + name
            shutil.copytree(build + "/nvc/work", d + "/work")
            p = subprocess.run([nvc, "--std=2008", "-e"] + generics.split() + ["tb_hdmi_raw"],
                               cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=1800)
            out = p.stdout + p.stderr
            p = subprocess.run([nvc, "--std=2008", "-r", "--ieee-warnings=off", "tb_hdmi_raw"],
                               cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=10800)
            # the same form as the reports of GHDL
            out += re.sub(r"(?m)^\*\* (Note|Warning): \S+: ",
                          lambda m: "(report %s): " % m.group(1).lower(), p.stdout + p.stderr)
            shutil.rmtree(d, ignore_errors=True)
    except subprocess.TimeoutExpired:
        out = "TIMEOUT\n"
    out += "SIMULATOR %s\nRUNTIME %d s\n" % (simulator, time.time() - t)
    open(build + "/" + name + ".log", "w").write(out)
with ThreadPoolExecutor(max_workers=jobs) as ex:
    list(ex.map(sim, runs))
PYEOF

# --------------------------------------------------------------------------------------------------
# Evaluation
# --------------------------------------------------------------------------------------------------
python3 - "$BUILD" "$SET" <<'PYEOF'
import re, sys
build, SET = sys.argv[1], sys.argv[2]
runs = [l.split(None, 3) for l in open(build + "/runs.txt").read().splitlines() if l.strip()]
fails = []
res = {}
for name, expect, simulator, generics in runs:
    txt = open("%s/%s.log" % (build, name)).read()
    rt = re.search(r"RUNTIME (\d+) s", txt)
    result = re.search(r"\(report note\): (RESULT .*)$", txt, re.M)
    errs = [re.sub(r"^.*\(report warning\): ", "", l) for l in txt.splitlines() if "(report warning): ERROR" in l]
    frames = re.findall(r"\(report note\): FRAME (.*)$", txt, re.M)
    mems = re.findall(r"\(report note\): MEM (.*)$", txt, re.M)
    res[name] = dict(result=result.group(1) if result else None, frames=frames, mems=mems, errs=errs)
    ok = bool(result) and result.group(1).endswith(" ERRORS=0")
    line = result.group(1) if result else "did not finish"
    sm = re.search(r"SIMULATOR (\w+)", txt)
    print("  %-36s %s (%s, %s s)" % (name, line, sm.group(1) if sm else "?", rt.group(1) if rt else "?"))
    for e in errs[:3]:
        print("      " + e)
    if "TIMEOUT" in txt or re.search(r"error", txt.replace("(report warning): ERROR", "")) and not result:
        print("      " + "\n      ".join([l for l in txt.splitlines() if "error" in l][:3]))
    if expect == "info":
        continue
    if expect == "pass" and not ok:
        fails.append(name)
    if expect == "fail" and (ok or not result):
        fails.append(name + " (mutant not detected)" if result else name + " (mutant did not finish)")

def kv(s):
    return dict(re.findall(r"(\w+)=(-?[\w.']+)", s))

gens = {name: dict(re.findall(r"-gG_(\w+)=(\S+)", generics)) for name, expect, simulator, generics in runs}

# distances between writer and reader (Avalon traffic); the monitor reports HDMI frame n as pass n + 1
print("writer/reader distances in ms (fetch of a line minus its last write burst), per run:")
for name, r in res.items():
    ms = [kv(x) for x in r["mems"][int(gens[name].get("CHECK_FROM", "0")):]]
    if not ms:
        continue
    def col(k):
        v = [int(x[k]) for x in ms if int(x[k]) >= 0 and int(x[k]) < 99999999]
        return ("%.3f..%.3f" % (min(v) / 1e5, max(v) / 1e5)) if v else "-"
    print("  %-36s top %s  bottom %s  min %s  margin to the next write %s" %
          (name, col("dist_top"), col("dist_bot"), col("dist_min"), col("margin_min")))
    # the tear-free range of d: every fetch moves with d, so d may fall by the smallest distance
    # and rise by the smallest margin
    dmin = min([int(x["dist_min"]) for x in ms if 0 <= int(x["dist_min"]) < 99999999] or [None])
    mmin = min([int(x["margin_min"]) for x in ms if 0 <= int(x["margin_min"]) < 99999999] or [None])
    fr = [kv(f) for f in r["frames"]]
    ds = [int(f["d"]) for f in fr if int(f["d"]) >= 0]
    clk_khz = 1e9 / (2 * float(gens[name]["HDMI_NUM_PS"]) / float(gens[name]["HDMI_DEN"]))
    if dmin is not None and mmin is not None and ds:
        d_ms = ds[-1] / clk_khz
        print("  %-36s d = %.3f ms; tear-free for d from %.3f to %.3f ms" %
              ("", d_ms, d_ms - dmin / 1e5, d_ms + mmin / 1e5))

# picture geometry of a raw mode equals the one of its standard mode; outputs identical with and
# without genlock in a standard mode
def result_kv(name):
    return kv(res[name]["result"]) if name in res and res[name]["result"] else None
if "reference_ghdl_raw_ntsc480" in res:
    a, b = result_kv("reference_ghdl_raw_ntsc480"), result_kv("reference_nvc_raw_ntsc480")
    same = bool(a and b) and a["hash"] == b["hash"] and a["sig"] == b["sig"]
    print("reference configuration with GHDL and with nvc, every output in every clock: %s" %
          ("identical (hash %s)" % a["hash"] if same else "DIFFERENT (%s, %s)" % (a and a.get("hash"), b and b.get("hash"))))
    if not same:
        fails.append("GHDL and nvc differ")
if SET == "full":
    a, b = result_kv("std_ntsc480_genlock"), result_kv("std_ntsc480_nogenlock")
    if a and b:
        same = a["hash"] == b["hash"]
        print("no regression: outputs of ascal with and without genlock and multiplexer, clock by clock: %s"
              % ("identical (hash %s)" % a["hash"] if same else "DIFFERENT (%s, %s)" % (a["hash"], b["hash"])))
        if not same:
            fails.append("regression hash")
        r = result_kv("raw_ntsc480")
        if r:
            same = r["sig"] == a["sig"]
            print("picture geometry of raw NTSC 480p 4:3 = standard NTSC 480p 4:3: %s" % ("yes" if same else "NO"))
            if not same:
                fails.append("geometry raw vs standard")
if "pullin_from_tear_ntsc480" in res:
    fr = res["pullin_from_tear_ntsc480"]["frames"]
    cf = int(gens["pullin_from_tear_ntsc480"].get("CHECK_FROM", "0"))
    tears = [int(kv(f)["tear_line"]) for f in fr][cf:]
    stretch = [int(kv(f)["stretch"]) for f in fr][cf:]
    ok = len(tears) >= 2 and tears[0] >= 0 and tears[-1] < 0
    print("pull-in from the tear zone: tear lines per frame %s, stretch per frame %s: %s" %
          (tears, stretch, "tear only at the start, then clean" if ok else "NOT AS EXPECTED"))
    if not ok:
        fails.append("pullin_from_tear_ntsc480 (tear pattern)")
if SET == "extra":
    print("flicker-free phase in standard NTSC 480p (information):")
    for name, r in res.items():
        ff = [int(kv(x)["ff_words"]) for x in r["mems"]]
        tl = [int(kv(f)["tear_line"]) for f in r["frames"]]
        print("  %-28s core writer at the read of address 0: %s words (%s lines); first picture line of "
              "another core frame per HDMI frame: %s" % (name, ff, ["%.1f" % (w * 2 / 1280) for w in ff], tl))
open(build + "/verdict.txt", "w").write(" ".join(fails))
PYEOF

FAILS=$(cat "$BUILD/verdict.txt")
echo "runtime $(( $(date +%s) - START )) s"
if [ $KEEP -eq 1 ]; then
   echo "build directory kept: $BUILD"
else
   rm -rf "$BUILD"
fi
if [ -z "$FAILS" ]; then
   echo "RESULT: PASS"
   exit 0
fi
echo "RESULT: FAIL: $FAILS"
exit 1
