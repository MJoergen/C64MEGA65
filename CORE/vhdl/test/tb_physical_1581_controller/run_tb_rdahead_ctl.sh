#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# run_tb_rdahead_ctl.sh -- read-ahead integration of the physical 1581 controller (issue #257)
#
#   CORE/vhdl/test/tb_physical_1581_controller/run_tb_rdahead_ctl.sh [--keep]
#
# Runs tb_physical_1581_rdahead_ctl.vhd (the controller, the read-ahead engine and the read FIFO
# on a synthetic record stream, decoder_stub_1581.vhd in place of the MFM decoder) against
# physical_1581_controller.vhd, then against 18 mutants of the controller, each of which the bench
# has to reject:
#
#   kill     the engine survives a step; a Force Interrupt; a write operation that resets nothing
#            (the read FSM term alone); a Read Address or Verify (the read FSM term and the decoder
#            reset); a side change (the side terms and the decoder reset); a disk change
#   adopt    a held sector of another cylinder is taken; RD_ADOPT copies the buffer while the
#            capture is still under way; the buffer belongs to the copy only from RD_COPY on (a
#            data mark in the commit clock starts a capture into it)
#   copy     a served sector is not released; no done gap after a copy; a Force Interrupt does not
#            end the copy; one push per clock (the registered buffer read lags the address); a
#            dropped push does not fail the copy
#   arm      no arm after a clean Read Sector
#   deleted  the copy does not report the flag of the held sector; a live read reports the flag
#            that the decoder shows at the data mark (the one of the field before)
#   age      the engine holds a sector far longer than 24 ms
#
# Not run, because no bench can tell them from the controller (each line: the change, the reason):
#   kill without the side terms        a side change also resets the decoder, one clock later
#   kill without the decoder reset     every decoder reset comes with a live search, a write
#                                      session or a side change, each of which has its own term
#   kill without the motor term        a motor stop drops READY in the next clock
#   kill without the READY term        READY falls with a motor stop, or 500 ms after the index
#                                      pulses stopped, long after the engine released its sector
#                                      by age (and a removed disk sets the disk-change line)
#   arm after a Read Address as well   safe (the medium has not changed) and without effect: the
#                                      Read Address returns the ID that has just passed
#   commit without the kill check      the only window is the one clock between acceptance and
#                                      commit, and the sector was captured before it
#   RD_ADOPT without its 40 ms bound   the engine ends every capture first (DAM timeout, 24 ms)
#   no clocks between copy and done    the 512 pushes before the done already keep it behind the
#                                      bytes; the gap is margin
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3. Runtime about 12 minutes
# (19 simulations of up to 80 seconds each, one after the other).
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
P=$REPO/CORE/vhdl/physical_1581
CTL=$P/physical_1581_controller.vhd

KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_rdahead_ctl.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }

# the sources in analysis order; $1 = the controller file to use. The library gets the decoder
# stub and never physical_1581_mfm_decoder.vhd (both declare the same entity).
sources() {
   local f
   for f in pkg crc inputs; do echo "$P/physical_1581_$f.vhd"; done
   echo "$HERE/decoder_stub_1581.vhd"
   for f in rdfifo mfm_encoder writer rdahead; do echo "$P/physical_1581_$f.vhd"; done
   echo "$1"
   echo "$HERE/tb_physical_1581_rdahead_ctl.vhd"
}

# build_and_run <dir> <controller file>: 0 only if the bench ran to its last line
build_and_run() {
   local dir=$1 ctl=$2
   mkdir -p "$dir/lib"
   ( cd "$dir" && "$GHDL" -a --std=08 --workdir=lib $(sources "$ctl") &&
     "$GHDL" -e --std=08 --workdir=lib tb_physical_1581_rdahead_ctl ) > "$dir/build.log" 2>&1 ||
      { sed 's/^/    /' "$dir/build.log" | head -10; return 2; }
   ( cd "$dir" && ./tb_physical_1581_rdahead_ctl --assert-level=error ) > "$dir/run.log" 2>&1
   local rc=$?
   [ $rc -eq 0 ] && grep -q "ALL TESTS PASSED" "$dir/run.log"
}

# first failure message of a run
why() { grep -m1 -E "\((assertion|report) (failure|error)\)" "$1/run.log" | sed -E 's/^.*\): //'; }

echo "=== read-ahead integration (tb_physical_1581_rdahead_ctl)"
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

K       = "                   or "
T_STEP  = K + "head_settled = '0'\n"
T_SIDE  = K + "side_s /= side_prev or side_settle /= 0\n"
T_DRST  = K + "dec_rst = '1'\n"
T_FI    = K + "cnq_s /= cnq_d\n"
T_RDST  = K + "not (rd_st = RD_IDLE or rd_st = RD_ADOPT or rd_st = RD_COPY)\n"
T_CHG   = K + "change_c = '1'\n"
HIT     = "return v = '1' and c = trk and r = sec;"
COMMIT  = "              if ra_kill = '0' and ra_hold_hit = '1' then\n"
BUSY    = ("  ra_busy <= '1' when rd_st = RD_COPY or\n"
           "                      (rd_st = RD_ADOPT and ra_kill = '0' and ra_hold_hit = '1')\n"
           "             else '0';\n")
CONSUME = "                ra_consume    <= '1';        -- the engine forgets the delivered sector\n"
GAP     = "                done_gap_cnt  <= C_DONE_GAP;\n" + CONSUME
CANCEL  = "if rd_st /= RD_IDLE and not is_wr(op_r) and (cancel_edge or change_c = '1') then"
DIV     = "constant C_RA_COPY_DIV     : natural := 16;"
OVF     = ("                if ovf_l = '1' or (byte_wr_o = '1' and byte_ovf_i = '1') then\n"
           "                  -- a push was dropped by a full FIFO")
ARM     = "                  if op_r = RDOP_READ_SECTOR then\n                    ra_arm <= '1';\n                  end if;\n"
DEL_CP  = "                deleted_l  <= ra_hold_del;\n"
DEL_DAM = "              if data_start = '1' then\n                rd_st     <= RD_STREAM;\n"
DEL_END = "                rd_deleted_o <= data_deleted;      -- the decoder shows the mark of this field with data_end\n"
AGE     = "      G_DAM_TIMEOUT_CYC => G_DAM_TIMEOUT_CYC\n    )"

M = [
 ("kill_ignores_step",               [(T_STEP, "")]),
 ("kill_ignores_force_interrupt",    [(T_FI, "")]),
 ("kill_ignores_write_operation",    [(T_RDST, "")]),
 ("kill_ignores_read_address",       [(T_RDST, ""), (T_DRST, "")]),
 ("kill_ignores_side_change",        [(T_SIDE, ""), (T_DRST, "")]),
 ("kill_ignores_disk_change",        [(T_CHG, "")]),
 ("adopt_ignores_track",             [(HIT, "return v = '1' and r = sec;")]),
 ("adopt_copies_capture_in_flight",  [(COMMIT, "              if ra_kill = '0' and (ra_hold_hit = '1' or ra_cap_hit = '1') then\n")]),
 ("buffer_busy_from_copy_only",      [(BUSY, "  ra_busy <= '1' when rd_st = RD_COPY else '0';\n")]),
 ("served_sector_not_released",      [(CONSUME, "")]),
 ("no_done_gap_after_copy",          [(GAP, CONSUME)]),
 ("copy_not_cancellable",            [(CANCEL, "if rd_st /= RD_IDLE and rd_st /= RD_COPY and not is_wr(op_r) and (cancel_edge or change_c = '1') then")]),
 ("copy_one_push_per_clock",         [(DIV, "constant C_RA_COPY_DIV     : natural := 1;")]),
 ("copy_ignores_dropped_push",       [(OVF, OVF.replace("if ovf_l = '1' or (byte_wr_o = '1' and byte_ovf_i = '1') then", "if false then"))]),
 ("no_arm_after_clean_read",         [(ARM, "")]),
 ("copy_deleted_flag_not_from_hold", [(DEL_CP, "")]),
 ("live_deleted_flag_at_data_mark",  [(DEL_DAM, DEL_DAM + "                deleted_l <= data_deleted;\n"),
                                      (DEL_END, "                rd_deleted_o <= deleted_l;\n")]),
 ("engine_holds_far_too_long",       [(AGE, "      G_DAM_TIMEOUT_CYC => G_DAM_TIMEOUT_CYC,\n      G_DATA_WD_CYC     => 100_000_000\n    )")]),
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
[ $N -eq 18 ] || note_fail "only_${N}_of_18_mutants_ran"

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
