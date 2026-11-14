#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Drive LED benches: error blink of the 1581 (GitHub issue #257), see README.md
#
#   CORE/vhdl/test/tb_drive_led/run.sh [detect|wiring|all] [--keep]
#
#   detect  CORE/vhdl/c1581_error_led.vhd (tb_c1581_error_led.vhd), plus six mutants of the
#           detector that must fail
#   wiring  the LED and busy equations of CORE/vhdl/main.vhd, copied verbatim into
#           tb_drive_led_wiring.vhd, all combinations of two drives, plus three mutants that must
#           fail; the detector instances of main.vhd, copied verbatim into tb_drive_led_inst.vhd
#           and run in real time, plus four mutants that must fail; the association of pwr_led in
#           the port map of iec_drive, plus one mutant; differential GHDL analysis of the complete
#           main.vhd (base commit versus working tree) with the real c1581_error_led in the
#           library, plus one mutant that must be caught
#   all     everything (default)
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime about 1 min.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=f9f3ca1        # WIP-V6-A22X3: the last commit before the error blink

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      detect|wiring|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [detect|wiring|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_drive_led.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }
want() { [ "$WHAT" = all ] || [ "$WHAT" = "$1" ]; }

# analyze files into a library directory; prints the diagnostics on failure
analyze() {
   local lib=$1; shift
   mkdir -p "$lib"
   "$GHDL" -a $GF --workdir="$lib" "$@" > "$lib/analyze.log" 2>&1 || { sed 's/^/    /' "$lib/analyze.log" | head -20; return 1; }
}

# run_tb <lib> <unit> <log>: elaborate and run a bench (2 min timeout); prints its TB lines;
# returns 0 only if the bench ran to the end and reported "TB: RESULT PASS"
run_tb() {
   local lib=$1 unit=$2 log=$3
   ( cd "$lib" && "$GHDL" -e $GF --workdir=. "$unit" ) > "$log.elab" 2>&1 || { sed 's/^/    /' "$log.elab" | head -20; return 1; }
   python3 - "$GHDL" "$lib" "$unit" "$log" <<'PYEOF'
import subprocess, sys
ghdl, lib, unit, log = sys.argv[1:5]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", unit],
                       cwd=lib, capture_output=True, text=True, timeout=120)
    out, rc = r.stdout + r.stderr, r.returncode
except subprocess.TimeoutExpired:
    out, rc = "TIMEOUT\n", 1
open(log, "w").write(out)
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
        print("    " + l)
sys.exit(0 if rc == 0 and "TB: RESULT PASS" in out else 1)
PYEOF
}

# mutate <src> <dst> <old> <new>: copy src to dst with exactly one occurrence of old replaced
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

DET="$REPO/CORE/vhdl/c1581_error_led.vhd"

# --------------------------------------------------------------------------------------------------
if want detect; then
   echo "=== blink detector (tb_c1581_error_led)"
   L="$BUILD/detect"
   if analyze "$L" "$DET" "$HERE/tb_c1581_error_led.vhd"; then
      run_tb "$L" tb_c1581_error_led "$BUILD/detect.log" || note_fail detect
   else
      note_fail detect_analyze
   fi

   # mutants the bench must reject
   for m in two_toggles four_toggles level expiry reload phase; do
      M="$BUILD/detect_mut_$m"
      mkdir -p "$M"
      case $m in
         two_toggles) mutate "$DET" "$M/det.vhd" \
                         "constant C_BLINK_TOGGLES : natural := 3;" "constant C_BLINK_TOGGLES : natural := 2;" ;;
         four_toggles) mutate "$DET" "$M/det.vhd" \
                         "constant C_BLINK_TOGGLES : natural := 3;" "constant C_BLINK_TOGGLES : natural := 4;" ;;
         level)       mutate "$DET" "$M/det.vhd" \
                         "blink_o <= pwr_led_i when toggles = C_BLINK_TOGGLES else" "blink_o <= '1' when toggles = C_BLINK_TOGGLES else" ;;
         expiry)      mutate "$DET" "$M/det.vhd" \
                         "            toggles <= 0;" "            null;" ;;
         reload)      mutate "$DET" "$M/det.vhd" \
                         "            window <= G_WINDOW_CYC;" "            if window = 0 then window <= G_WINDOW_CYC; end if;" ;;
         phase)       mutate "$DET" "$M/det.vhd" \
                         "blink_o <= pwr_led_i when toggles = C_BLINK_TOGGLES else" "blink_o <= not pwr_led_i when toggles = C_BLINK_TOGGLES else" ;;
      esac || { note_fail "detect_mutant_${m}_pattern"; continue; }
      if analyze "$M" "$M/det.vhd" "$HERE/tb_c1581_error_led.vhd" &&
         run_tb "$M" tb_c1581_error_led "$M/run.log" > "$M/tb.txt"; then
         note_fail "detect_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -m1 TB_ERROR "$M/tb.txt" | sed 's/^ *//')"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
# gen_wiring <main.vhd> <bench.vhd>: fill the template with the three assignments of main.vhd
gen_wiring() {
   python3 - "$1" "$HERE/tb_drive_led_wiring.vhd.in" "$2" <<'PYEOF'
import re, sys
main, tmpl, out = sys.argv[1:4]
src = open(main).read().splitlines()
blocks = []
for name in ("drive_led_col_o", "drive_led_o", "img_drive_busy"):
    start = [i for i, l in enumerate(src) if re.match(rf"\s*{name}\s*<=", l)]
    if len(start) != 1:
        print(f"    main.vhd: {len(start)} assignments to {name} (expected 1)")
        sys.exit(1)
    i, blk = start[0], []
    while i < len(src) and len(blk) < 8:
        blk.append(src[i])
        if src[i].split("--")[0].rstrip().endswith(";"):
            break
        i += 1
    else:
        print(f"    main.vhd: end of the assignment to {name} not found")
        sys.exit(1)
    blocks += blk
t = open(tmpl).read()
open(out, "w").write(t.replace("-- @MAIN_ASSIGNMENTS@", "\n".join(blocks)))
print(f"    copied {len(blocks)} lines (3 assignments) from main.vhd")
PYEOF
}

# gen_inst <main.vhd> <bench.vhd>: fill the template with the generate block drive_err_led_gen
gen_inst() {
   python3 - "$1" "$HERE/tb_drive_led_inst.vhd.in" "$2" <<'PYEOF'
import re, sys
main, tmpl, out = sys.argv[1:4]
src = open(main).read().splitlines()
s = [i for i, l in enumerate(src) if re.match(r"\s*drive_err_led_gen\s*:\s*for\b", l)]
e = [i for i, l in enumerate(src) if re.match(r"\s*end\s+generate\s+drive_err_led_gen\s*;", l)]
if len(s) != 1 or len(e) != 1 or not 0 < e[0] - s[0] < 20:
    print(f"    main.vhd: generate block drive_err_led_gen not found ({len(s)} starts, {len(e)} ends)")
    sys.exit(1)
blk = src[s[0]:e[0] + 1]
t = open(tmpl).read()
open(out, "w").write(t.replace("-- @MAIN_GENERATE@", "\n".join(blk)))
print(f"    copied {len(blk)} lines (the generate block) from main.vhd")
PYEOF
}

# check_iec <main.vhd>: the port map of iec_drive_inst associates led and pwr_led with the two
# signals of the drive LED logic, each exactly once
check_iec() {
   python3 - "$1" <<'PYEOF'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r"iec_drive_inst\s*:\s*entity\s+work\.iec_drive\b(.*?)\);\s*-- iec_drive_inst", src, re.S)
if not m:
    print("    main.vhd: instance iec_drive_inst not found"); sys.exit(1)
pm = re.sub(r"--[^\n]*", "", m.group(1))
ok = True
for formal, actual in (("led", "c64_drive_led"), ("pwr_led", "c64_drive_pwr_led")):
    a = re.findall(rf"(?<![A-Za-z0-9_]){formal}\s*=>\s*([A-Za-z0-9_]+)", pm)
    if a != [actual]:
        print(f"    iec_drive_inst: {formal} is associated with {a} (expected ['{actual}'])"); ok = False
if ok:
    print("  iec_drive_inst: led => c64_drive_led, pwr_led => c64_drive_pwr_led")
sys.exit(0 if ok else 1)
PYEOF
}

# diags <lib> <file>: analyze file (Xilinx library clauses removed) and print its normalized
# diagnostics (file names and positions stripped), one per line, sorted
diags() {
   local lib=$1 f=$2
   grep -v -i -E "^\s*(library|use)\s+(xpm|unisim)\b" "$f" > "$lib/$(basename "$f").nox.vhd"
   "$GHDL" -a $GF --workdir="$lib" "$lib/$(basename "$f").nox.vhd" 2>&1 |
      grep -i "error" | sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//' | sort
}

if want wiring; then
   echo "=== LED and busy equations of main.vhd (tb_drive_led_wiring)"
   L="$BUILD/wiring"
   mkdir -p "$L"
   if gen_wiring "$REPO/CORE/vhdl/main.vhd" "$L/tb_drive_led_wiring.vhd" &&
      analyze "$L" "$L/tb_drive_led_wiring.vhd"; then
      run_tb "$L" tb_drive_led_wiring "$L/run.log" || note_fail wiring
   else
      note_fail wiring_build
   fi

   for m in noblink xor busy; do
      M="$BUILD/wiring_mut_$m"
      mkdir -p "$M"
      case $m in
         noblink) mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                  "((or c64_drive_led) or (or c64_drive_err_led))" "(or c64_drive_led)" ;;
         xor)  mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                  "((or c64_drive_led) or (or c64_drive_err_led))" "((or c64_drive_led) xor (or c64_drive_err_led))" ;;
         busy) mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                  "img_drive_busy <= (c64_drive_led and not phys_1581_en) or cache_dirty;" \
                  "img_drive_busy <= ((c64_drive_led or c64_drive_err_led) and not phys_1581_en) or cache_dirty;" ;;
      esac || { note_fail "wiring_mutant_${m}_pattern"; continue; }
      if gen_wiring "$M/main.vhd" "$M/tb_drive_led_wiring.vhd" > /dev/null &&
         analyze "$M" "$M/tb_drive_led_wiring.vhd" &&
         run_tb "$M" tb_drive_led_wiring "$M/run.log" > "$M/tb.txt"; then
         note_fail "wiring_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -m1 'TB: RESULT' "$M/tb.txt" | sed 's/^ *//')"
      fi
   done

   # the detector instances of main.vhd in real time: generics, clock and per-drive wiring
   echo "=== detector instances of main.vhd (tb_drive_led_inst)"
   L="$BUILD/inst"
   mkdir -p "$L"
   if gen_inst "$REPO/CORE/vhdl/main.vhd" "$L/tb_drive_led_inst.vhd" &&
      analyze "$L" "$DET" "$L/tb_drive_led_inst.vhd"; then
      run_tb "$L" tb_drive_led_inst "$L/run.log" || note_fail inst
   else
      note_fail inst_build
   fi

   for m in drive0 activity clock window; do
      M="$BUILD/inst_mut_$m"
      mkdir -p "$M"
      cp "$DET" "$M/det.vhd"
      cp "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd"
      case $m in
         drive0)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                      "        pwr_led_i => c64_drive_pwr_led(i)," "        pwr_led_i => c64_drive_pwr_led(0)," ;;
         activity) mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                      "        pwr_led_i => c64_drive_pwr_led(i)," "        pwr_led_i => c64_drive_led(i)," ;;
         clock)    mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                      "        clk_i     => clk_main_i," "        clk_i     => c64_clk_sd_i," ;;
         window)   mutate "$DET" "$M/det.vhd" \
                      "G_WINDOW_CYC : natural := 6_400_000" "G_WINDOW_CYC : natural := 640_000" ;;
      esac || { note_fail "inst_mutant_${m}_pattern"; continue; }
      if gen_inst "$M/main.vhd" "$M/tb_drive_led_inst.vhd" > /dev/null &&
         analyze "$M" "$M/det.vhd" "$M/tb_drive_led_inst.vhd" > "$M/tb.txt" &&
         run_tb "$M" tb_drive_led_inst "$M/run.log" >> "$M/tb.txt"; then
         note_fail "inst_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -m1 -E 'TB_ERROR|error' "$M/tb.txt" | sed -E 's/^ *//; s/^[^ ]*:[0-9]+:[0-9]+:[ ]*//')"
      fi
   done

   # the port map of iec_drive (SystemVerilog, out of the reach of GHDL): activity and power LED
   # go to the two signals
   echo "=== port map of iec_drive in main.vhd"
   if check_iec "$REPO/CORE/vhdl/main.vhd"; then
      M="$BUILD/iec_mut"
      mkdir -p "$M"
      if mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
            "      pwr_led      => c64_drive_pwr_led," "      pwr_led      => open,"; then
         if check_iec "$M/main.vhd" > /dev/null; then
            note_fail iec_mutant_not_detected
         else
            echo "  mutant 'pwr_led left open' rejected"
         fi
      else
         note_fail iec_mutant_pattern
      fi
   else
      note_fail iec_portmap
   fi

   # differential analysis of the complete main.vhd: the base commit and the working tree in
   # identical libraries (packages and the real c1581_error_led). The sub-entities that are not in
   # the library produce the same "not found" diagnostics in both; everything else (signal names,
   # types, the port map of c1581_error_led) is checked.
   echo "=== main.vhd: differential analysis against $BASE"
   D="$BUILD/diff"
   mkdir -p "$D/lib"
   ( echo "library ieee;"; echo "use ieee.std_logic_1164.all;"; echo "use ieee.numeric_std.all;"
     awk '/^package vdrives_pkg is/{p=1} p{print} p&&/^end package/{exit}' "$REPO/M2M/vhdl/vdrives.vhd" ) > "$D/vdrives_pkg.vhd"
   if analyze "$D/lib" "$REPO/M2M/QNICE/vhdl/tools.vhd" "$REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd" \
                       "$REPO/CORE/vhdl/globals.vhd" "$D/vdrives_pkg.vhd" \
                       "$REPO/CORE/vhdl/physical_1581/physical_1581_pkg.vhd" "$DET"; then
      mkdir -p "$D/base" "$D/new" "$D/mut"
      cp -R "$D/lib/." "$D/base/"; cp -R "$D/lib/." "$D/new/"; cp -R "$D/lib/." "$D/mut/"
      if git -C "$REPO" show "$BASE:CORE/vhdl/main.vhd" > "$D/base/main.vhd" 2>/dev/null; then
         diags "$D/base" "$D/base/main.vhd" > "$D/main.base.txt"
         diags "$D/new" "$REPO/CORE/vhdl/main.vhd" > "$D/main.new.txt"
         if diff "$D/main.base.txt" "$D/main.new.txt" > "$D/main.diff"; then
            echo "  CORE/vhdl/main.vhd: $(wc -l < "$D/main.new.txt" | tr -d ' ') diagnostics, identical to $BASE (no new ones)"
         else
            sed 's/^/    /' "$D/main.diff" | head -10
            note_fail diff_main
         fi
         # mutant: a wrong formal in the port map of c1581_error_led must show up
         if mutate "$REPO/CORE/vhdl/main.vhd" "$D/mut/main.vhd" \
               "        pwr_led_i => c64_drive_pwr_led(i)," "        pwr_i     => c64_drive_pwr_led(i),"; then
            diags "$D/mut" "$D/mut/main.vhd" > "$D/main.mut.txt"
            if diff "$D/main.base.txt" "$D/main.mut.txt" > /dev/null; then
               note_fail diff_mutant_not_detected
            else
               echo "  mutant 'wrong c1581_error_led formal' rejected: $(diff "$D/main.base.txt" "$D/main.mut.txt" | grep -m1 '^> ' | cut -c3-)"
            fi
         else
            note_fail diff_mutant_pattern
         fi
      else
         note_fail diff_base_missing
      fi
   else
      note_fail diff_lib
   fi
fi

# --------------------------------------------------------------------------------------------------
if [ $KEEP -eq 1 ]; then
   echo "build directory kept: $BUILD"
else
   rm -rf "$BUILD"
fi
if [ -z "$FAILS" ]; then
   echo "RESULT: PASS"
   exit 0
fi
echo "RESULT: FAIL:$FAILS"
exit 1
