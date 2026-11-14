#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# run_tb_media_contract.sh -- media state of the physical 1581 controller (issues #90 and #257)
#
#   CORE/vhdl/test/tb_physical_1581_controller/run_tb_media_contract.sh [--keep]
#
# Runs tb_physical_1581_media_contract.vhd against physical_1581_controller.vhd (READY with the
# first index edge of a motor-on interval, independent of the disk-change latch; the latch itself;
# Read Address without sector 11), then against 17 mutants of the controller, each of which the
# bench has to reject:
#
#   READY   gated by the change latch; only after two edges; from an edge that arrived while the
#           motor was off; at motor-on without an edge (unchanged medium); kept at motor-off (the
#           flag, the level); kept on disable; dropped by a step; dropped by a raw change while the
#           motor runs; dropped for one clock at every edge
#   stale   no drop when the edges stop; a drop for one clock only; an edge that does not restart
#           the interval; an interval that is 3 percent too long
#   latch   following the raw line; cleared by the release of the raw line; cleared by an index
#           edge
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3. Runtime about half an hour
# (18 simulations of one to three minutes each, one after the other).
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
P=$REPO/CORE/vhdl/physical_1581
T=$REPO/CORE/vhdl/test
CTL=$P/physical_1581_controller.vhd

KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_media_contract.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }

# the sources of the controller in analysis order; $1 = the controller file to use
sources() {
   local f
   for f in pkg crc mfm_gaps mfm_quantise mfm_gaps_to_bits mfm_bits_to_bytes mfm_decoder inputs \
            rdfifo wfifo mfm_encoder writer rdahead; do
      [ -f "$P/physical_1581_$f.vhd" ] && echo "$P/physical_1581_$f.vhd"
   done
   echo "$1"
   echo "$T/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd"
   echo "$HERE/tb_physical_1581_media_contract.vhd"
}

# build_and_run <dir> <controller file>: 0 only if the bench ran to its last line
build_and_run() {
   local dir=$1 ctl=$2
   mkdir -p "$dir/lib"
   ( cd "$dir" && "$GHDL" -a --std=08 --workdir=lib $(sources "$ctl") &&
     "$GHDL" -e --std=08 --workdir=lib tb_physical_1581_media_contract ) > "$dir/build.log" 2>&1 ||
      { sed 's/^/    /' "$dir/build.log" | head -10; return 2; }
   ( cd "$dir" && ./tb_physical_1581_media_contract --assert-level=error ) > "$dir/run.log" 2>&1
   local rc=$?
   [ $rc -eq 0 ] && grep -q "ALL TESTS PASSED" "$dir/run.log"
}

# first failure message of a run
why() { grep -m1 -E "\((assertion|report) (failure|error)\)" "$1/run.log" | sed -E 's/^.*\): //'; }

echo "=== media contract (tb_physical_1581_media_contract)"
if build_and_run "$BUILD/ref" "$CTL"; then
   echo "    $(grep -m1 'ALL TESTS PASSED' "$BUILD/ref/run.log" | sed -E 's/^.*\): //')"
else
   echo "    $(why "$BUILD/ref")"
   note_fail bench
fi

echo "=== mutants of the controller"
python3 - "$CTL" "$BUILD/mut" <<'PYEOF' || note_fail mutant_patterns
import os, sys
src, out = sys.argv[1:3]
os.makedirs(out, exist_ok=True)
base = open(src).read()

A_READY = "        if motor_s = '1' and idx_seen = '1' then\n          media_ready <= '1';\n        end if;\n"
EDGE    = "          if index_edge = '1' then\n            idx_gap_cnt <= (others => '0');\n            idx_seen    <= '1';\n"
MOFF    = "        if motor_s = '0' then\n          idx_seen    <= '0';\n          media_ready <= '0';\n          idx_gap_cnt <= (others => '0');\n"
STALE   = "            media_ready <= '0';\n            idx_seen    <= '0';\n            idx_gap_cnt <= (others => '0');\n          end if;\n        end if;\n"
RSTB    = "        idx_seen      <= '0';\n        idx_gap_cnt   <= (others => '0');\n        media_ready   <= '0';\n"
DECL    = "  signal idx_seen      : std_logic := '0';"
LATCH   = "        if change_c = '1' then\n          change_latched <= '1';\n        end if;\n"
SETTLE  = "        ------------------------------------------------------------------\n        -- head-settle timer"
ACK     = "              step_ack_tgl_o <= not step_ack_tgl_o;   -- acknowledge (recovery done)\n"
BOUND   = "elsif idx_gap_cnt < to_unsigned(2 * G_PERIOD_MAX_CYC, 32) then"

M = [
 ("ready_gated_by_latch", [(A_READY, A_READY.replace("idx_seen = '1' then", "idx_seen = '1' and change_latched = '0' then"))]),
 ("ready_after_two_edges", [
    (DECL, DECL + "\n  signal idx_pre : std_logic := '0';"),
    (EDGE, "          if index_edge = '1' then\n            idx_gap_cnt <= (others => '0');\n            idx_pre <= '1';\n            if idx_pre = '1' then idx_seen <= '1'; end if;\n"),
    (MOFF, MOFF + "          idx_pre <= '0';\n"),
    (STALE, "            media_ready <= '0';\n            idx_seen    <= '0';\n            idx_pre     <= '0';\n            idx_gap_cnt <= (others => '0');\n          end if;\n        end if;\n"),
    (RSTB, RSTB + "        idx_pre <= '0';\n")]),
 ("edge_while_motor_off_counts", [(MOFF, "        if motor_s = '0' then\n          if index_edge = '1' then idx_seen <= '1'; elsif motor_on_act = '1' then idx_seen <= '0'; end if;\n          media_ready <= '0';\n          idx_gap_cnt <= (others => '0');\n")]),
 ("ready_at_motor_on_without_edge", [(A_READY, A_READY + "        if motor_s = '1' and motor_on_act = '0' and change_latched = '0' then\n          idx_seen <= '1';\n        end if;\n")]),
 ("seen_flag_kept_at_motor_off", [(MOFF, MOFF.replace("          idx_seen    <= '0';\n", "", 1))]),
 ("ready_kept_at_motor_off", [(MOFF, MOFF.replace("          media_ready <= '0';\n", "", 1))]),
 ("ready_kept_on_disable", [(RSTB, RSTB.replace("        media_ready   <= '0';\n", "", 1))]),
 ("step_drops_ready", [(ACK, ACK + "              media_ready <= '0'; idx_seen <= '0';\n")]),
 ("raw_change_drops_ready", [(SETTLE, "        if change_c = '1' and change_latched = '0' then\n          media_ready <= '0';\n          idx_seen    <= '0';\n        end if;\n\n" + SETTLE)]),
 ("ready_drops_one_clock_at_edge", [(EDGE, EDGE + "            media_ready <= '0';\n")]),
 ("stale_no_drop", [(STALE, STALE.replace("            media_ready <= '0';\n", "", 1))]),
 ("stale_drop_one_clock", [(STALE, STALE.replace("            idx_seen    <= '0';\n", "", 1))]),
 ("stale_edge_no_restart", [(EDGE, EDGE.replace("            idx_gap_cnt <= (others => '0');\n", "", 1))]),
 ("stale_3_percent_long", [(BOUND, "elsif idx_gap_cnt < to_unsigned(2 * G_PERIOD_MAX_CYC + G_PERIOD_MAX_CYC / 16, 32) then")]),
 ("latch_follows_raw_line", [(LATCH, "        if change_c = '1' then\n          change_latched <= '1';\n        else\n          change_latched <= '0';\n        end if;\n")]),
 ("latch_cleared_by_release", [
    (DECL, DECL + "\n  signal chg_prev_m : std_logic := '0';"),
    (LATCH, "        chg_prev_m <= change_c;\n        if change_c = '1' then\n          change_latched <= '1';\n        elsif chg_prev_m = '1' then\n          change_latched <= '0';\n        end if;\n")]),
 ("latch_cleared_by_index", [(EDGE, EDGE + "            if change_c = '0' then change_latched <= '0'; end if;\n")]),
]
bad = 0
for name, reps in M:
    txt = base
    for old, new in reps:
        if txt.count(old) != 1:
            print(f"    mutant {name}: pattern found {txt.count(old)} times (expected once): {old[:50]!r}")
            bad += 1
            break
        txt = txt.replace(old, new)
    else:
        os.makedirs(os.path.join(out, name), exist_ok=True)
        open(os.path.join(out, name, "controller.vhd"), "w").write(txt)
open(os.path.join(out, "names.txt"), "w").write("\n".join(n for n, _ in M) + "\n")
sys.exit(1 if bad else 0)
PYEOF

N=0
while read -r m; do
   [ -n "$m" ] || continue
   [ -f "$BUILD/mut/$m/controller.vhd" ] || continue
   N=$((N + 1))
   build_and_run "$BUILD/mut/$m" "$BUILD/mut/$m/controller.vhd"
   case $? in
      0) note_fail "mutant_${m}_not_detected" ;;
      2) note_fail "mutant_${m}_does_not_build" ;;
      *) echo "  mutant '$m' rejected: $(why "$BUILD/mut/$m")" ;;
   esac
done < "$BUILD/mut/names.txt"
[ $N -eq 17 ] || note_fail "only_${N}_of_17_mutants_ran"

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
