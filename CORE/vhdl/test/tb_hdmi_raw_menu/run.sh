#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Truth table of the "HDMI Frame Sync" decoders of CORE/vhdl/mega65.vhd (issue #184), see README.md
#
#   CORE/vhdl/test/tb_hdmi_raw_menu/run.sh [table|mutants|all] [--keep]
#
#   table    main_hdmi_ff and qnice_video_mode_o of the working tree and of the base commit, copied
#            verbatim into tb_hdmi_raw_menu.vhd, for every combination of the machine mode, the six
#            display modes and the six Frame Sync items, with the other menu bits at '0' and '1'
#   mutants  defects of the two decoders and of the constants that the table must reject
#   all      everything (default)
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime about 20 s.
# VIDEO_MODES_PKG can name another file of the package video_modes_pkg (default: the one of the
# working tree).
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=8a0e3ab        # the last commit before the Frame Sync radio groups (WIP-V6-A26 menu)
PKG=${VIDEO_MODES_PKG:-$REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd}

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      table|mutants|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [table|mutants|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_hdmi_raw_menu.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }
want() { [ "$WHAT" = all ] || [ "$WHAT" = "$1" ]; }

git -C "$REPO" show "$BASE:CORE/vhdl/mega65.vhd" > "$BUILD/base_mega65.vhd" 2> /dev/null ||
   { echo "cannot read CORE/vhdl/mega65.vhd of the base commit $BASE"; echo "RESULT: FAIL base"; exit 1; }

# gen <mega65.vhd> <bench.vhd>: fill the template with the decoders of the given mega65.vhd (b_new)
# and of the base commit (b_base), and with the flat indices of the golden model
gen() {
   python3 - "$1" "$BUILD/base_mega65.vhd" "$HERE/tb_hdmi_raw_menu.vhd.in" "$2" "$REPO" <<'PYEOF'
import re, sys
new, base, tmpl, out, repo = sys.argv[1:6]
sys.path.insert(0, repo + "/M2M/rom/tests")
import menu_test

def fail(msg):
    print("    " + msg)
    sys.exit(1)

def code(l):
    return l.split("--")[0]

def extract(path, what):
    src = open(path).read().splitlines()
    consts = [l for l in src if re.match(r"\s*constant C_MENU_(MACHINE_NTSC|HDMI_\w+)\s*:\s*natural\s*:=\s*\d+;", l)]
    stmts = []
    for name in ("c64_ntsc", "main_hdmi_ff", "qnice_video_mode_o"):
        start = [i for i, l in enumerate(src) if re.match(r"\s*%s\s*<=" % name, code(l))]
        # lint: the decoder is the only assignment to its target
        drivers = [i + 1 for i, l in enumerate(src) if re.search(r"\b%s\s*(\([^)]*\))?\s*<=" % name, code(l))]
        if len(start) != 1 or len(drivers) != 1:
            fail(f"{what}: {len(drivers)} assignment(s) to {name} (line(s) {drivers}), expected exactly one")
        end = next((j for j in range(start[0], min(start[0] + 40, len(src)))
                    if code(src[j]).rstrip().endswith(";")), None)
        if end is None:
            fail(f"{what}: end of the assignment to {name} not found")
        stmts += src[start[0]:end + 1] + [""]
    return consts, stmts

nc, ns = extract(new, "mega65.vhd")
bc, bs = extract(base, "mega65.vhd of the base commit")
bvals = {}
for l in bc:
    m = re.match(r"\s*constant (C_MENU_\w+)\s*:\s*natural\s*:=\s*(\d+);", l)
    bvals[m.group(1)] = int(m.group(2))
vals = menu_test.c_menu_values()
names = ["MACHINE_NTSC", "HDMI_16_9_50", "HDMI_4_3_50", "HDMI_5_4_50", "HDMI_16_9_5994",
         "HDMI_4_3_5994", "HDMI_5_4_5994", "HDMI_FF", "HDMI_FF_NTSC"]
tc, bstim = [], []
for n in names + ["HDMI_SYNC_OFF", "HDMI_SYNC_OFF_NTSC", "HDMI_RAW", "HDMI_RAW_NTSC"]:
    if "C_MENU_" + n not in vals:
        fail(f"golden model: no line for C_MENU_{n}")
    tc.append("constant T_MENU_%-20s : natural := %d;" % (n, vals["C_MENU_" + n]))
for n in names:
    if "C_MENU_" + n not in bvals:
        fail(f"mega65.vhd of the base commit: no constant C_MENU_{n}")
    bstim.append("constant B_MENU_%-20s : natural := %d;" % (n, bvals["C_MENU_" + n]))
t = open(tmpl).read()
for key, lines in (("STIMULUS_CONSTANTS", tc), ("BASE_STIMULUS_CONSTANTS", bstim),
                   ("NEW_CONSTANTS", nc), ("NEW_DECODE", ns),
                   ("BASE_CONSTANTS", bc), ("BASE_DECODE", bs)):
    if t.count("-- @%s@" % key) != 1:
        fail(f"template: placeholder {key} not found once")
    t = t.replace("-- @%s@" % key, "\n".join(lines))
open(out, "w").write(t)
print(f"    copied {len(nc)} constants and {len(ns)} lines of decoders from mega65.vhd, "
      f"{len(bc)} and {len(bs)} from {sys.argv[2].split('/')[-1]} of the base commit")
PYEOF
}

# build_run <dir> <mega65.vhd>: generate, analyze, elaborate and run the bench in dir; prints its TB
# lines; returns 0 if it reported "TB: RESULT PASS", 1 if it ran and failed, 2 if it did not build
build_run() {
   local L=$1 M=$2
   mkdir -p "$L"
   gen "$M" "$L/tb_hdmi_raw_menu.vhd" || return 2
   "$GHDL" -a $GF --workdir="$L" "$PKG" "$L/tb_hdmi_raw_menu.vhd" > "$L/analyze.log" 2>&1 ||
      { sed 's/^/    /' "$L/analyze.log" | head -20; return 2; }
   ( cd "$L" && "$GHDL" -e $GF --workdir=. tb_hdmi_raw_menu ) > "$L/elab.log" 2>&1 ||
      { sed 's/^/    /' "$L/elab.log" | head -20; return 2; }
   python3 - "$GHDL" "$L" <<'PYEOF'
import subprocess, sys
ghdl, lib = sys.argv[1:3]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", "tb_hdmi_raw_menu"],
                       cwd=lib, capture_output=True, text=True, timeout=600)
    out, rc = r.stdout + r.stderr, r.returncode
except subprocess.TimeoutExpired:
    out, rc = "TIMEOUT\n", 1
open(lib + "/run.log", "w").write(out)
shown = 0
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if (l.startswith("TB") or l.startswith("TIMEOUT")) and shown < 6:
        print("    " + l)
        shown += 1
sys.exit(0 if rc == 0 and "TB: RESULT PASS" in out else 1)
PYEOF
}

# mutate <src> <dst> <old> <new>: copy src to dst with old (which must occur exactly once) replaced
mutate() {
   python3 - "$@" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    print(f"    mutant pattern found {s.count(old)} times (expected once): {old!r}")
    sys.exit(1)
open(dst, "w").write(s.replace(old, new))
PYEOF
}

if want table; then
   echo "=== truth table of main_hdmi_ff and qnice_video_mode_o (working tree versus $BASE)"
   build_run "$BUILD/table" "$REPO/CORE/vhdl/mega65.vhd" || note_fail table
fi

if want mutants; then
   echo "=== mutants of the decoders and the constants"
   # noand: Raw does not keep the PAL core on the original clock; ffntsc: the NTSC switch reads the
   # Raw bit of PAL; ntscraw: the NTSC raw modes read the Raw bit of PAL; nomachine: the PAL raw
   # 16:9 mode also in NTSC; swap: 4:3 raw delivers the 5:4 raw mode; const: C_MENU_HDMI_RAW on the
   # line of Flicker-free; constntsc: C_MENU_HDMI_RAW_NTSC on the line of Off (NTSC); order: the
   # raw prefix behind the standard chain (never reached)
   M65="$REPO/CORE/vhdl/mega65.vhd"
   for m in noand ffntsc ntscraw nomachine swap const constntsc order; do
      D="$BUILD/mut_$m"
      mkdir -p "$D"
      case $m in
         noand)     mutate "$M65" "$D/mega65.vhd" \
                       "main_osm_control_i(C_MENU_HDMI_FF)      and not main_osm_control_i(C_MENU_HDMI_RAW);" \
                       "main_osm_control_i(C_MENU_HDMI_FF);" ;;
         ffntsc)    mutate "$M65" "$D/mega65.vhd" \
                       "and not main_osm_control_i(C_MENU_HDMI_RAW_NTSC) when" \
                       "and not main_osm_control_i(C_MENU_HDMI_RAW) when" ;;
         ntscraw)   mutate "$M65" "$D/mega65.vhd" \
                       "qnice_osm_control_i(C_MENU_HDMI_RAW_NTSC) = '1' and qnice_osm_control_i(C_MENU_HDMI_5_4_5994)" \
                       "qnice_osm_control_i(C_MENU_HDMI_RAW) = '1' and qnice_osm_control_i(C_MENU_HDMI_5_4_5994)" ;;
         nomachine) mutate "$M65" "$D/mega65.vhd" \
                       "C_VIDEO_HDMI_16_9_50_RAW   when qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '0' and " \
                       "C_VIDEO_HDMI_16_9_50_RAW   when " ;;
         swap)      mutate "$M65" "$D/mega65.vhd" \
                       "C_VIDEO_HDMI_4_3_50_RAW    when" "C_VIDEO_HDMI_5_4_50_RAW    when" ;;
         const)     mutate "$M65" "$D/mega65.vhd" \
                       "constant C_MENU_HDMI_RAW      : natural := 70;" "constant C_MENU_HDMI_RAW      : natural := 68;" ;;
         constntsc) mutate "$M65" "$D/mega65.vhd" \
                       "constant C_MENU_HDMI_RAW_NTSC : natural := 71;" "constant C_MENU_HDMI_RAW_NTSC : natural := 67;" ;;
         order)     python3 - "$M65" "$D/mega65.vhd" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
raw = re.findall(r"\n      C_VIDEO_HDMI_\w+_RAW +when [^\n]*else", s)
if len(raw) != 6:
    print(f"    mutant pattern: {len(raw)} raw lines (expected 6)")
    sys.exit(1)
for l in raw:
    s = s.replace(l, "", 1)
last = "\n      C_VIDEO_HDMI_16_9_50;"
if s.count(last) != 1:
    print("    mutant pattern: end of the chain not found once")
    sys.exit(1)
s = s.replace(last, "\n      C_VIDEO_HDMI_16_9_50 when true else" + "".join(raw) + last)
open(sys.argv[2], "w").write(s)
PYEOF
                    ;;
      esac || { note_fail "mutant_${m}_pattern"; continue; }
      build_run "$D" "$D/mega65.vhd" > "$D/out.txt" 2>&1
      rc=$?
      if [ $rc -eq 1 ]; then
         echo "  mutant '$m' rejected: $(grep -m1 'TB: FAIL' "$D/out.txt" | sed -E 's/^ *//' | cut -c1-150)"
      elif [ $rc -eq 0 ]; then
         note_fail "mutant_${m}_survived"
      else
         sed 's/^/  /' "$D/out.txt" | head -8
         note_fail "mutant_${m}_does_not_build"
      fi
   done
fi

if [ $KEEP -eq 1 ]; then
   echo "build directory: $BUILD"
else
   rm -rf "$BUILD"
fi
if [ -z "$FAILS" ]; then
   echo "RESULT: PASS"
   exit 0
fi
echo "RESULT: FAIL$FAILS"
exit 1
