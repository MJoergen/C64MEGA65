#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Genlock bench (GitHub issue #184): hdmi_genlock in the four raw modes, see README.md
#
#   CORE/vhdl/test/tb_hdmi_genlock/run.sh [pal720|pal576|ntsc720|ntsc480|modes|quick|xcheck|synth|mutants|all] [--keep]
#
#   pal720 ... ntsc480  the complete simulation of the mode: 20 starts (phases over the whole frame,
#                       among them the worst case; one of them, in 576p and 480p two, locked for 311
#                       frames) and 13 lists of disturbances
#   modes               the four complete simulations
#   quick               the four modes with a reduced set of starts and disturbances and 31 locked
#                       frames (see README.md), and synth: a smoke test for work on the entity
#   xcheck              the stepped scaler models against models stepped at every edge (NTSC 480p,
#                       45 frames, all instances; PAL 720p, 7 frames)
#   synth               ghdl --synth of hdmi_genlock: no error, no latch, flip-flop count; a mutant
#                       with a latch must fail
#   mutants             mutants of hdmi_genlock.vhd that the bench must reject
#   all                 modes, xcheck, synth and mutants (default): the complete verification
#
# At most two simulations run at the same time. Ends with "RESULT: PASS" (exit status 0) or
# "RESULT: FAIL ..." (exit status 1). Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL),
# python3. Runtime: see README.md.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08"
SRC="$REPO/M2M/vhdl/av_pipeline/hdmi_genlock.vhd"
BENCH="$HERE/tb_ascal_timing_pkg.vhd $HERE/tb_hdmi_genlock_pkg.vhd $HERE/tb_hdmi_genlock.vhd"

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      pal720|pal576|ntsc720|ntsc480|modes|quick|xcheck|synth|mutants|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [pal720|pal576|ntsc720|ntsc480|modes|quick|xcheck|synth|mutants|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_hdmi_genlock.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }
# want <part>: the part runs; the complete simulations of the modes are pal720 ... ntsc480, the quick
# ones pal720q ... ntsc480q
want() {
   case $WHAT:$1 in
      all:*q) false ;;
      all:*) true ;;
      modes:pal???|modes:ntsc???) true ;;
      quick:*q|quick:synth) true ;;
      xcheck:x???) true ;;
      *) [ "$WHAT" = "$1" ] ;;
   esac
}

# mutate <src> <dst> <old> <new> [<old> <new> ...]: copy src to dst with each old replaced by its
# new, one after the other; each old has to occur exactly once
mutate() {
   python3 - "$@" <<'PYEOF'
import sys
src, dst = sys.argv[1:3]
pairs = sys.argv[3:]
s = open(src).read()
for old, new in zip(pairs[0::2], pairs[1::2]):
    if s.count(old) != 1:
        print(f"    mutant pattern found {s.count(old)} times (expected once): {old!r}")
        sys.exit(1)
    s = s.replace(old, new)
open(dst, "w").write(s)
PYEOF
}

# build <lib> <hdmi_genlock source>: analyze the DUT and the bench, elaborate
build() {
   local lib=$1 dut=$2
   mkdir -p "$lib"
   ( cd "$lib" && "$GHDL" -a $GF -O3 --workdir=. "$dut" $BENCH && "$GHDL" -e $GF -O3 --workdir=. tb_hdmi_genlock ) \
      > "$lib/build.log" 2>&1 || { grep -v -i "warning\|^ *\^" "$lib/build.log" | sed 's/^/    /' | head -10; return 1; }
}

# sim <lib> <log> [generics]: run the bench (30 min timeout); writes its TB lines to <log>.tb;
# returns 0 only if the bench ran to the end and reported "TB: RESULT PASS"
sim() {
   local lib=$1 log=$2; shift 2
   python3 - "$GHDL" "$lib" "$log" "$@" <<'PYEOF'
import re, signal, subprocess, sys, time
ghdl, lib, log = sys.argv[1:4]
args = sys.argv[4:]
t0 = time.time()
p = subprocess.Popen([ghdl, "-r", "--std=08", "--workdir=.", "tb_hdmi_genlock"] + args,
                     cwd=lib, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
def stop(signum, frame):            # do not leave the simulation running
    p.kill()
    sys.exit(1)
signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
try:
    out, _ = p.communicate(timeout=1800)
    rc = p.returncode
except subprocess.TimeoutExpired:
    p.kill()
    out, rc = "TIMEOUT\n", 1
out += f"TB: runtime {time.time() - t0:.0f} s\n"
open(log, "w").write(out)
tb = []
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
        tb.append(re.sub(r"(?:(?<=\s)|^)/(?:[^\s/]+/)+", "", l))
open(log + ".tb", "w").write("\n".join(tb) + "\n")
sys.exit(0 if rc == 0 and "TB: RESULT PASS" in out else 1)
PYEOF
}

args_of() {
   local m
   case $1 in
      x480) echo "-gG_MODE=3 -gG_XCHECK=true -gG_FRAMES=45"; return ;;
      x720) echo "-gG_MODE=0 -gG_XCHECK=true -gG_FRAMES=7"; return ;;
   esac
   case ${1%q} in
      pal720) m=0 ;; pal576) m=1 ;; ntsc720) m=2 ;; ntsc480) m=3 ;;
   esac
   case $1 in
      *q) echo "-gG_MODE=$m -gG_SET=near -gG_LOCKED=31" ;;
      *)  echo "-gG_MODE=$m" ;;
   esac
}
title_of() {
   local q=""
   case $1 in
      x480) echo "cross-check of the stepped scaler models, NTSC 480p, 45 frames"; return ;;
      x720) echo "cross-check of the stepped scaler models, PAL 720p, 7 frames"; return ;;
      *q) q=", quick" ;;
   esac
   case ${1%q} in
      pal720) echo "PAL 720p (1980 x 750, 74.444444 MHz)$q" ;;
      pal576) echo "PAL 576p (864 x 624, 27.023810 MHz)$q" ;;
      ntsc720) echo "NTSC 720p (1650 x 750, 74.062500 MHz)$q" ;;
      ntsc480) echo "NTSC 480p (858 x 526, 27.000000 MHz)$q" ;;
   esac
}

# lane <run>...: the runs one after the other; prints the TB lines of each run when it is done
lane() {
   local r
   for r in "$@"; do
      sim "$BUILD/lib" "$BUILD/$r.log" $(args_of "$r")
      echo $? > "$BUILD/$r.rc"
      { echo "=== $(title_of "$r")"; sed 's/^/    /' "$BUILD/$r.log.tb"; } > "$BUILD/$r.txt"
      cat "$BUILD/$r.txt"
   done
}

# --------------------------------------------------------------------------------------------------
LANE_A=""
LANE_B=""
for p in pal720 ntsc480 pal720q ntsc480q x720; do want $p && LANE_A="$LANE_A $p"; done
for p in ntsc720 pal576 ntsc720q pal576q x480; do want $p && LANE_B="$LANE_B $p"; done

if [ -n "$LANE_A$LANE_B" ]; then
   echo "=== build"
   if build "$BUILD/lib" "$SRC"; then
      PIDS=""
      [ -n "$LANE_A" ] && { lane $LANE_A & PIDS="$PIDS $!"; }
      [ -n "$LANE_B" ] && { lane $LANE_B & PIDS="$PIDS $!"; }
      for pid in $PIDS; do wait "$pid"; done
      for r in $LANE_A $LANE_B; do
         [ "$(cat "$BUILD/$r.rc" 2>/dev/null)" = 0 ] || note_fail "$r"
      done
   else
      note_fail build
   fi
fi

# --------------------------------------------------------------------------------------------------
# synth <lib> <hdmi_genlock source>: GHDL synthesis; returns 0 if it succeeds without a latch
synth() {
   local lib=$1 dut=$2
   mkdir -p "$lib"
   ( cd "$lib" && "$GHDL" -a $GF --workdir=. "$dut" && "$GHDL" --synth $GF --workdir=. hdmi_genlock ) \
      > "$lib/synth.vhd" 2> "$lib/synth.log" && ! grep -q -i latch "$lib/synth.log"
}

# ffcount <netlist>: flip-flops in the VHDL netlist of ghdl --synth (bits assigned under rising_edge)
ffcount() {
   python3 - "$1" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
width = {}
for m in re.finditer(r"(\w+)\s*:\s*(?:out\s+|buffer\s+)?(?:std_logic_vector|unsigned)\s*\((\d+)\s+downto\s+(\d+)\)", s):
    width.setdefault(m.group(1), int(m.group(2)) - int(m.group(3)) + 1)
for m in re.finditer(r"(\w+)\s*:\s*(?:out\s+|buffer\s+)?std_logic\b(?!_)", s):
    width.setdefault(m.group(1), 1)
bits = regs = 0
for m in re.finditer(r"if rising_edge \(\w+\) then\s*(.*?)\s*end if;", s, re.S):
    for t in re.findall(r"^\s*(\w+)\s*<=", m.group(1), re.M):
        bits += width.get(t, 0)
        regs += 1
print(f"{bits} flip-flops in {regs} registers (GHDL netlist before optimization)")
PYEOF
}

if want synth; then
   echo "=== synthesis of hdmi_genlock (ghdl --synth)"
   if synth "$BUILD/synth" "$SRC"; then
      echo "    no error, no latch"
      echo "    $(ffcount "$BUILD/synth/synth.vhd")"
   else
      sed 's/^/    /' "$BUILD/synth/synth.log" | head -5
      note_fail synth
   fi
   M="$BUILD/synth_mut_latch"
   mkdir -p "$M"
   if mutate "$SRC" "$M/hdmi_genlock.vhd" $'\nbegin\n\n   htotal_o' \
         $'\n   signal latch_q : std_logic;\nbegin\n\n   latch_q <= hs_i when vs_i = \'1\';\n\n   htotal_o'; then
      if ! synth "$M" "$M/hdmi_genlock.vhd"; then
         echo "    mutant 'latch' rejected: $(grep -m1 -i 'latch\|error' "$M/synth.log" | sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//')"
      else
         note_fail "synth_mutant_latch_not_detected"
      fi
   else
      note_fail "synth_mutant_latch_pattern"
   fi
fi

# --------------------------------------------------------------------------------------------------
# mutants: name, run (generics), exact text and its replacement; a mutant runs in NTSC 480p (the
# fastest mode, M_MODE 3) unless it says otherwise, with the start or the disturbance instances,
# and stops at its first error
MUTANTS="band_edge no_pullin late_first_line distribution index_stuck no_saturation lock_early
         stale_ref same_cycle_ref rst_keeps_extra no_bypass count_from_0 k_max_4095 window_low
         every_de armed_kept band_4096 band_no_quarter no_hold gap_clears_lock hold_unlocked"

mutant_def() {
   M_MODE=3
   case $1 in
      band_edge)       M_ARGS="-gG_SET=starts"
                       M_OLD="            elsif d < target_i + band then"
                       M_NEW="            elsif d <= target_i + band then"
                       M_TXT="d = target_i + band counts as inside the band" ;;
      no_pullin)       M_ARGS="-gG_SET=starts"
                       M_OLD=$'            else\n               stretch <= C_K_MAX;'
                       M_NEW=$'            else\n               stretch <= 0;'
                       M_TXT="no stretch above the band (no pull-in from behind)" ;;
      late_first_line) M_ARGS="-gG_SET=starts"
                       M_OLD="               idx := 0;"
                       M_NEW="               idx := 1;"
                       M_TXT="the stretch lines begin with index 1 (15 lines)" ;;
      distribution)    M_ARGS="-gG_SET=starts"
                       M_OLD="            elsif idx < stretch mod C_LINES then"
                       M_NEW="            elsif idx <= stretch mod C_LINES then"
                       M_TXT="one stretch line too many gets the extra clock cycle" ;;
      index_stuck)     M_ARGS="-gG_SET=starts"
                       M_OLD="               idx := line_idx + 1;"
                       M_NEW="               idx := line_idx;"
                       M_TXT="the line index does not advance: every line after vsync is stretched" ;;
      no_saturation)   M_ARGS="-gG_SET=disturb"
                       M_OLD="                C_HTOTAL_MAX             when htotal_i + extra > C_HTOTAL_MAX else"
                       M_NEW=""
                       M_TXT="htotal_o not limited to 4095" ;;
      lock_early)      M_ARGS="-gG_SET=starts"
                       M_OLD="   locked_o  <= '1' when enable_i = '1' and good = C_LOCK_FRAMES else '0';"
                       M_NEW="   locked_o  <= '1' when enable_i = '1' and good >= C_LOCK_FRAMES - 1 else '0';"
                       M_TXT="locked_o after 7 frames" ;;
      stale_ref)       M_ARGS="-gG_SET=disturb"
                       M_OLD="            valid   := ref_new = '1' and d /= C_CNT_MAX;"
                       M_NEW="            valid   := d /= C_CNT_MAX;"
                       M_TXT="a measurement without a new reference is used" ;;
      same_cycle_ref)  M_ARGS="-gG_SET=starts"
                       M_OLD="            ref_new <= ref_i;               -- a ref_i in this cycle belongs to the next measurement"
                       M_NEW="            ref_new <= '0';"
                       M_TXT="a ref_i in the clock cycle of the measurement is lost" ;;
      rst_keeps_extra) M_ARGS="-gG_SET=disturb"
                       M_OLD=$'            line_idx <= C_LINES;\n            extra    <= 0;'
                       M_NEW=$'            line_idx <= C_LINES;'
                       M_TXT="rst_i does not clear the extra length of the current line" ;;
      no_bypass)       M_ARGS="-gG_SET=disturb"
                       M_OLD="   htotal_o  <= htotal_i                 when enable_i = '0' else"
                       M_NEW="   htotal_o  <="
                       M_TXT="htotal_o follows enable_i = '0' one clock cycle late" ;;
      count_from_0)    M_ARGS="-gG_SET=starts"
                       M_OLD="            cnt     <= 1;"
                       M_NEW="            cnt     <= 0;"
                       M_TXT="d one clock cycle short" ;;
      k_max_4095)      M_ARGS="-gG_SET=starts"
                       M_OLD="   constant C_K_MAX       : natural := 4080;"
                       M_NEW="   constant C_K_MAX       : natural := 4095;"
                       M_TXT="largest stretch 4095" ;;
      window_low)      M_ARGS="-gG_SET=starts"
                       M_OLD="   constant C_LOCK_BELOW  : natural := 1024;"
                       M_NEW="   constant C_LOCK_BELOW  : natural := 1023;"
                       M_TXT="lock window starts at target_i - 1023" ;;
      armed_kept)      M_ARGS="-gG_SET=disturb"
                       M_OLD=$'            ref_new  <= \'0\';\n            armed    <= \'0\';'
                       M_NEW=$'            ref_new  <= \'0\';\n            if rst_i = \'1\' then\n               armed <= \'0\';\n            end if;'
                       M_TXT="enable_i = '0' does not clear the armed measurement (a one-cycle pulse leaves it behind)" ;;
      band_4096)       M_ARGS="-gG_SET=starts"
                       M_OLD="            band    := target_i + target_i / 4;"
                       M_NEW="            band    := 4096;"
                       M_TXT="the band of the first draft (4096 pixel clocks)" ;;
      band_no_quarter) M_ARGS="-gG_SET=starts"
                       M_OLD="            band    := target_i + target_i / 4;"
                       M_NEW="            band    := target_i;"
                       M_TXT="band = target_i (without the quarter)" ;;
      no_hold)         M_ARGS="-gG_SET=disturb"; M_MODE=2
                       M_OLD=$'               if good /= C_LOCK_FRAMES then\n                  stretch <= 0;             -- while locked the stretch of the last frame stays\n               end if;'
                       M_NEW=$'               stretch <= 0;'
                       M_TXT="no flywheel: stretch 0 without a new reference also while locked (NTSC 720p)" ;;
      gap_clears_lock) M_ARGS="-gG_SET=disturb"
                       M_OLD=$'            if valid then\n               if d + C_LOCK_BELOW >= target_i'
                       M_NEW=$'            if not valid then\n               good <= 0;\n            else\n               if d + C_LOCK_BELOW >= target_i'
                       M_TXT="a measurement without a new reference clears the lock counter" ;;
      hold_unlocked)   M_ARGS="-gG_SET=disturb"
                       M_OLD=$'               if good /= C_LOCK_FRAMES then\n                  stretch <= 0;'
                       M_NEW=$'               if false then\n                  stretch <= 0;'
                       M_TXT="the stretch is held without a new reference also while not locked" ;;
      every_de)        M_ARGS="-gG_SET=starts"
                       M_OLD=$'            armed   <= \'0\';\n'
                       M_NEW=""
                       M_TXT="a measurement at every rising edge of de_i after the first falling edge of vs_i" ;;
   esac
}

# run_mutant <name>: builds the mutant and runs it; writes its report to $BUILD/mut_<name>.txt, first
# word REJECTED (the run failed), SURVIVED (the run passed), NOBUILD (the mutant does not analyze or
# elaborate: a stale replacement) or PATTERN
run_mutant() {
   local m=$1 dir="$BUILD/mut_$1"
   mutant_def "$m"
   mkdir -p "$dir"
   if ! mutate "$SRC" "$dir/hdmi_genlock.vhd" "$M_OLD" "$M_NEW" > "$dir/pattern.txt"; then
      echo "PATTERN  $m: $(cat "$dir/pattern.txt")" > "$BUILD/mut_$m.txt"
   elif ! build "$dir" "$dir/hdmi_genlock.vhd" > "$dir/build.txt"; then
      echo "NOBUILD  $m ($M_TXT): $(head -1 "$dir/build.txt" | sed 's/^ *//')" > "$BUILD/mut_$m.txt"
   elif sim "$dir" "$dir/run.log" -gG_MODE=$M_MODE -gG_FAILFAST=true $M_ARGS; then
      echo "SURVIVED $m ($M_TXT)" > "$BUILD/mut_$m.txt"
   else
      echo "REJECTED $m ($M_TXT)"$'\n'"      $(grep -m1 -E 'TB_ERROR|error|TIMEOUT' "$dir/run.log.tb" | sed 's/^ *//' | cut -c1-170)" > "$BUILD/mut_$m.txt"
   fi
}

if want mutants; then
   echo "=== mutants of hdmi_genlock.vhd (each must be rejected)"
   set -- $MUTANTS
   while [ $# -gt 0 ]; do
      run_mutant "$1" & P1=$!
      P2=""
      if [ $# -gt 1 ]; then run_mutant "$2" & P2=$!; fi
      wait $P1; [ -n "$P2" ] && wait $P2
      cat "$BUILD/mut_$1.txt"; [ -n "$P2" ] && cat "$BUILD/mut_$2.txt"
      shift; [ $# -gt 0 ] && shift
   done | sed 's/^/    /'
   for m in $MUTANTS; do
      case "$(head -1 "$BUILD/mut_$m.txt" 2>/dev/null | cut -c1-8)" in
         REJECTED) ;;
         SURVIVED) note_fail "mutant_${m}_not_detected" ;;
         NOBUILD*) note_fail "mutant_${m}_does_not_build" ;;
         *)        note_fail "mutant_${m}_pattern" ;;
      esac
   done
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
