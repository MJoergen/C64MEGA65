#!/usr/bin/env bash
# Runner of tb_hdmi_raw_wiring: the genlock wiring of digital_pipeline.vhd
# (issue #184, doc/dev-hdmi-raw/SPEC.md section 5.1; README.md in this folder).
#
#   CORE/vhdl/test/tb_hdmi_raw_wiring/run.sh [all|SCENARIO ...|mutants]
#
#   all       (default) the scenarios A to G with the real genlock and H with the
#             hostile one, each checked by check_wiring.py
#   A ... H   only these scenarios
#   mutants   every mutant of the table MUTANTS below on a copy of
#             digital_pipeline.vhd, with the scenarios listed for it; a mutant is
#             killed when at least one of them fails (M02 is expected to survive)
#
# Environment: GHDL (default /usr/local/bin/ghdl), JOBS (parallel simulations,
# default 2), KEEP (keep the build directory). Prints the checker output and a
# final "RESULT: PASS" or "RESULT: FAIL ..." line; exit status 0 only on PASS.
# About 10 minutes for "all" with two jobs.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
JOBS="${JOBS:-2}"
FLAGS=(--std=08 -frelaxed -fsynopsys)
TOOLS="$REPO/doc/dev-ntsc/tools"
AV="$REPO/M2M/vhdl/av_pipeline"
HDMI="$REPO/M2M/vhdl/controllers/HDMI"
FONT="$REPO/M2M/font/Anikki-16x16-m2m.rom"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_hdmi_raw_wiring.XXXXXX")"
[ -n "${KEEP:-}" ] && echo "build dir: $BUILD" || trap 'rm -rf "$BUILD"' EXIT
T0=$(date +%s)
fail() { echo "RESULT: FAIL $*"; exit 1; }

# Mutants of digital_pipeline.vhd: name|text|replacement|scenarios
MUTANTS=(
   "M01 the scaler always gets the genlock's htotal|hdmi_ascal_htotal <= hdmi_htotal when hdmi_raw = '0' else|hdmi_ascal_htotal <= hdmi_genlock_htotal when hdmi_raw = '0' else|H"
   "M02 enable_i of the genlock always '1'|enable_i  => hdmi_raw,|enable_i  => '1',|G H"
   "M03 the reference ignores video_hblank_i|elsif video_hblank_i = '0' and video_vblank_i = '0' then|elsif video_vblank_i = '0' then|C"
   "M04 hdmi_ref is the level, not a pulse|hdmi_ref            <= hdmi_ref_s and not hdmi_ref_d;|hdmi_ref            <= hdmi_ref_s;|C"
   "M05 target 1.0 ms instead of 2.0 ms|hdmi_genlock_target <= 2 * hdmi_video_mode.CLK_KHZ;|hdmi_genlock_target <= hdmi_video_mode.CLK_KHZ;|C"
   "M06 genlock de_i connected to the hsync|de_i      => hdmi_de,|de_i      => hdmi_hs,|C"
   "M07 the reference register is cleared by vblank instead of the vsync edge|if video_vs_i = '1' and video_ref_vs_d = '0' then|if video_vblank_i = '1' then|B"
   "M08 hdmi_raw inverted|hdmi_raw            <= '1' when video_mode_is_raw(hdmi_video_mode_i) else '0';|hdmi_raw            <= '0' when video_mode_is_raw(hdmi_video_mode_i) else '1';|C H"
   "M10 genlock vs_i connected to the hsync|vs_i      => hdmi_vs,|vs_i      => hdmi_hs,|C"
   "M14 genlock hs_i connected to the vsync|hs_i      => hdmi_hs,|hs_i      => hdmi_vs,|D"
   "M15 genlock rst_i tied to '0'|rst_i     => hdmi_rst_i,|rst_i     => '0',|A"
   "M18 the reference register is cleared by the falling edge of video_vs_i|if video_vs_i = '1' and video_ref_vs_d = '0' then|if video_vs_i = '0' and video_ref_vs_d = '1' then|C"
   "M19 the scaler never gets the genlock's htotal|hdmi_ascal_htotal <= hdmi_htotal when hdmi_raw = '0' else|hdmi_ascal_htotal <= hdmi_htotal when hdmi_raw = '0' or true else|H"
)

# build NAME DIGITAL_PIPELINE GENLOCK(real|hostile): a library in $BUILD/NAME with the bench
build() {
   local dir="$BUILD/$1" dp="$2" gl="$3"
   mkdir -p "$dir" && cd "$dir" || exit 2
   python3 "$TOOLS/w2_standin.py" "$AV/ascal.vhd" ascal "$dir/ascal_ent.vhd" --retype-in-ranged > /dev/null \
      || fail "stand-in ascal"
   # the entity declaration of the real ascal with the architecture "timing" instead of the empty one
   python3 - "$dir/ascal_ent.vhd" "$HERE/ascal_timing.vhd" "$dir/ascal_standin.vhd" <<'EOF2' || fail "ascal stand-in"
import sys
ent = open(sys.argv[1]).read()
ent = ent[:ent.index("architecture standin of ascal is")]
open(sys.argv[3], "w").write(ent + "\n" + open(sys.argv[2]).read())
EOF2
   python3 "$TOOLS/w2_standin.py" "$AV/video_overlay.vhd" video_overlay "$dir/video_overlay_standin.vhd" \
      --retype vga_cfg_shift_i=integer > /dev/null || fail "stand-in video_overlay"
   python3 "$TOOLS/w2_standin.py" "$HDMI/vga_to_hdmi.vhd" vga_to_hdmi "$dir/vga_to_hdmi_standin.vhd" > /dev/null \
      || fail "stand-in vga_to_hdmi"
   python3 "$TOOLS/w2_standin.py" "$HDMI/serialiser_10to1_selectio.vhd" serialiser_10to1_selectio \
      "$dir/serialiser_standin.vhd" > /dev/null || fail "stand-in serialiser"
   local glfiles=("$AV/hdmi_genlock.vhd")
   if [ "$gl" = hostile ]; then
      python3 "$TOOLS/w2_standin.py" "$AV/hdmi_genlock.vhd" hdmi_genlock "$dir/genlock_ent.vhd" > /dev/null \
         || fail "genlock entity"
      python3 - "$dir/genlock_ent.vhd" "$HERE/genlock_hostile.vhd" "$dir/genlock_hostile.vhd" <<'EOF2' || fail "hostile genlock"
import sys
ent = open(sys.argv[1]).read()
ent = ent[:ent.index("architecture standin of hdmi_genlock is")]
open(sys.argv[3], "w").write(ent + "\n" + open(sys.argv[2]).read())
EOF2
      glfiles=("$dir/genlock_hostile.vhd")
   fi
   "$GHDL" -a "${FLAGS[@]}" --work=unisim "$TOOLS/stubs/unisim_vcomponents.vhd" || fail "unisim stub"
   "$GHDL" -a "${FLAGS[@]}" --work=xpm "$TOOLS/stubs/xpm_vcomponents.vhd" || fail "xpm stub"
   "$GHDL" -i "${FLAGS[@]}" "$REPO/M2M/QNICE/vhdl/tools.vhd" "$AV/video_modes_pkg.vhd" "$HDMI/types_pkg.vhd" \
      "$HDMI/sync_reg.vhd" "$HDMI/hdmi_tx_encoder.vhd" "$REPO/M2M/vhdl/memory/avm_decrease.vhd" \
      "$AV/clk_synthetic_enable.vhd" "$AV/crop.vhd" "$dp" "${glfiles[@]}" \
      "$HERE/tb_hdmi_raw_wiring_pkg.vhd" "$dir/ascal_standin.vhd" "$dir/video_overlay_standin.vhd" \
      "$dir/vga_to_hdmi_standin.vhd" "$dir/serialiser_standin.vhd" "$HERE/tb_hdmi_raw_wiring.vhd" \
      || fail "import ($1)"
   "$GHDL" -m "${FLAGS[@]}" -Wno-binding -Wno-hide tb_hdmi_raw_wiring > "$dir/make.log" 2>&1 \
      || { cat "$dir/make.log"; fail "make ($1)"; }
   {
      echo '$ version 1.1'
      for sig in tb_seg tb_kind tb_mode tb_period tb_tcore hdmi_rst crop_vs crop_hblank crop_vblank; do
         echo "/tb_hdmi_raw_wiring/$sig"
      done
      for sig in video_ref hdmi_ref hdmi_raw hdmi_htotal hdmi_ascal_htotal hdmi_genlock_target hdmi_vs hdmi_de; do
         echo "/tb_hdmi_raw_wiring/i_dp/$sig"
      done
      for sig in htotal_o locked_o stretch_o; do
         echo "/tb_hdmi_raw_wiring/i_dp/i_hdmi_genlock/$sig"
      done
   } > "$dir/wave.opt"
}

# one job line: LIB|SCENARIO|GENLOCK|LOGNAME
run_one() {
   IFS='|' read -r lib scen gl name <<< "$(sed -n "${1}p" "$JOBFILE")"
   local dir="$BUILD/$lib" s
   s=$(date +%s)
   ( cd "$dir" && ./tb_hdmi_raw_wiring --ieee-asserts=disable -gG_SCENARIO="$scen" -gG_FONT_FILE="$FONT" \
        --read-wave-opt="$dir/wave.opt" --vcd="$dir/$scen.vcd" > "$BUILD/$name.sim" 2>&1 )
   {
      grep -v '^segment\|^core started' "$BUILD/$name.sim"
      if grep -q '^SIMULATION DONE' "$BUILD/$name.sim" && ! grep -qi 'error\|assertion' "$BUILD/$name.sim"; then
         python3 "$HERE/check_wiring.py" "$dir/$scen.vcd" "$REPO" "$scen" "$gl"
      else
         echo "RESULT: FAIL simulation"
      fi
      echo "runtime: $(( $(date +%s) - s )) s"
   } > "$BUILD/$name.log" 2>&1
   rm -f "$dir/$scen.vcd"
}

JOBFILE="$BUILD/jobs.txt"
export -f run_one
export BUILD HERE REPO FONT JOBFILE
: > "$JOBFILE"
WHAT=("$@"); [ ${#WHAT[@]} -eq 0 ] && WHAT=(all)

if [ "${WHAT[0]}" = mutants ]; then
   for i in "${!MUTANTS[@]}"; do
      IFS='|' read -r name old new scens <<< "${MUTANTS[$i]}"
      id="${name%% *}"
      cp "$AV/digital_pipeline.vhd" "$BUILD/dp_$id.vhd"
      python3 - "$BUILD/dp_$id.vhd" "$old" "$new" <<'EOF2' || fail "mutant $id does not apply"
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
assert s.count(old) == 1, "mutant text found %d times" % s.count(old)
open(p, "w").write(s.replace(old, new))
EOF2
      for scen in $scens; do
         gl=real; [ "$scen" = H ] && gl=hostile
         [ -d "$BUILD/${id}_$gl" ] || build "${id}_$gl" "$BUILD/dp_$id.vhd" "$gl"
         echo "${id}_$gl|$scen|$gl|${id}_$scen" >> "$JOBFILE"
      done
   done
else
   [ "${WHAT[0]}" = all ] && WHAT=(A B C D E F G H)
   for scen in "${WHAT[@]}"; do
      gl=real; [ "$scen" = H ] && gl=hostile
      [ -d "$BUILD/$gl" ] || build "$gl" "$AV/digital_pipeline.vhd" "$gl"
      echo "$gl|$scen|$gl|$scen" >> "$JOBFILE"
   done
fi
cd "$BUILD" || exit 2
seq 1 "$(wc -l < "$JOBFILE")" | xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {}

status=0
if [ "${WHAT[0]}" = mutants ]; then
   echo "mutant                                                                      scenarios  result"
   for i in "${!MUTANTS[@]}"; do
      IFS='|' read -r name old new scens <<< "${MUTANTS[$i]}"
      id="${name%% *}"
      killed=""
      for scen in $scens; do
         grep -q '^RESULT: PASS' "$BUILD/${id}_$scen.log" || killed="$killed $scen"
      done
      if [ "$id" = M02 ]; then
         # informational: the multiplexer protects the scaler, see README.md
         verdict="survives (harmless by design, see README)"
         [ -n "$killed" ] && verdict="killed by$killed (informational, see README)"
      elif [ -n "$killed" ]; then
         verdict="killed by$killed"
      else
         verdict="SURVIVES"; status=1
      fi
      printf '%-76s %-10s %s\n' "$name" "$scens" "$verdict"
   done
else
   while IFS='|' read -r lib scen gl name; do
      echo "=== scenario $scen ($gl genlock)"
      cat "$BUILD/$name.log"
      grep -q '^RESULT: PASS' "$BUILD/$name.log" || status=1
   done < "$JOBFILE"
fi
echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL"
fi
exit $status
