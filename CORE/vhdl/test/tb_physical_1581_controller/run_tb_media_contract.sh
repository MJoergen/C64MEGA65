#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# run_tb_media_contract.sh -- media state of the physical 1581 controller (issues #90 and #257)
#
#   CORE/vhdl/test/tb_physical_1581_controller/run_tb_media_contract.sh [--keep]
#
# Runs tb_physical_1581_media_contract.vhd against physical_1581_controller.vhd (READY with the
# first index edge of a motor-on interval, independent of the disk-change latch, falling after
# 500 ms of settled time without an index edge; the latch itself; Read Address without sector 11),
# then against 25 mutants of the controller, each of which the bench has to reject:
#
#   READY   gated by the change latch; only after two edges; from an edge that arrived while the
#           motor was off; at motor-on without an edge (unchanged medium); kept at motor-off (the
#           flag, the level); kept on disable; dropped by a step; dropped by a raw change while the
#           motor runs; dropped for one clock at every edge
#   stale   no drop when the edges stop; a drop for one clock only; an edge that does not restart
#           the interval; an interval that is 3 percent too long
#   latch   following the raw line; cleared by the release of the raw line; cleared by an index
#           edge
#   moving  the time of a step and of the settle time after it counted (no suspension); the
#           interval held during a step but not started anew after it; a suspension that ends
#           only with the next index edge; a suspension while the step engine works but not in
#           the settle time; one in the settle time but not while the step engine works; an index
#           edge ignored during a step; READY that cannot rise while the head moves; the drop held
#           back until the head rests, with the moving time counted
#
# The reference runs with nvc and, for comparison, with GHDL (both have to pass, at the same end
# time); the mutants run with nvc. SIM=ghdl runs everything with GHDL; without nvc that is the
# default. JOBS (default 1) is the number of simulations at the same time.
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), nvc 1.21 (or $NVC) if present, python3.
# Runtime with JOBS=1: 52 minutes, 18 of them for the GHDL reference (measured on a busy machine).
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
NVC=${NVC:-$(command -v nvc || true)}
SIM=${SIM:-auto}
JOBS=${JOBS:-1}
if [ "$SIM" = auto ]; then
   if [ -n "$NVC" ]; then SIM=nvc; else SIM=ghdl; fi
fi
case "$SIM" in
   ghdl) ;;
   nvc) [ -n "$NVC" ] && [ -x "$NVC" ] || { echo "SIM=nvc, but nvc is not found"; exit 2; } ;;
   *) echo "SIM must be ghdl or nvc"; exit 2 ;;
esac

KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_media_contract.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }

python3 - "$REPO" "$HERE" "$BUILD" "$SIM" "$GHDL" "${NVC:-none}" "$JOBS" <<'PYEOF'
import os, re, shutil, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor
REPO, HERE, BUILD, SIM, GHDL, NVC, JOBS = sys.argv[1:8]
JOBS = max(1, int(JOBS))
P = REPO + "/CORE/vhdl/physical_1581"
T = REPO + "/CORE/vhdl/test"
CTL = P + "/physical_1581_controller.vhd"
TB = HERE + "/tb_physical_1581_media_contract.vhd"
TOP = "tb_physical_1581_media_contract"
BASE = [P + "/physical_1581_%s.vhd" % f for f in
        ("pkg crc mfm_gaps mfm_quantise mfm_gaps_to_bits mfm_bits_to_bytes mfm_decoder inputs "
         "rdfifo wfifo mfm_encoder writer rdahead").split()]
BASE += [T + "/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd", HERE + "/golden_1581_pkg.vhd",
         HERE + "/mech_model_1581.vhd"]
FAILS = []

def sh(cmd, cwd, log):
    with open(log, "a") as f:
        return subprocess.run(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT).returncode

# the library of everything but the controller and the bench, once per simulator
def base(sim):
    d = "%s/base_%s" % (BUILD, sim)
    os.makedirs(d, exist_ok=True)
    log = d + "/build.log"
    if sim == "ghdl":
        os.makedirs(d + "/lib", exist_ok=True)
        rc = sh([GHDL, "-a", "--std=08", "--workdir=lib"] + BASE, d, log)
    else:
        rc = sh([NVC, "--std=2008", "-a"] + BASE, d, log)
    if rc:
        print(open(log).read()[-2000:]); sys.exit("RESULT: FAIL: the base library does not build (%s)" % sim)
    return d

# build and run the bench on one controller file: ("pass", end ns) / ("fail", message) / ("build", log)
def build_run(name, ctl, sim, bdir):
    d = "%s/%s_%s" % (BUILD, name, sim)
    if os.path.exists(d): shutil.rmtree(d)
    log = d + "/build.log"
    if sim == "ghdl":
        shutil.copytree(bdir, d)
        os.remove(d + "/build.log")
        ok = (sh([GHDL, "-a", "--std=08", "--workdir=lib", ctl, TB], d, log) == 0 and
              sh([GHDL, "-e", "--std=08", "--workdir=lib", TOP], d, log) == 0)
        run = ["./" + TOP, "--assert-level=error"]
    else:
        shutil.copytree(bdir, d)
        os.remove(d + "/build.log")
        ok = (sh([NVC, "--std=2008", "-a", ctl, TB], d, log) == 0 and
              sh([NVC, "--std=2008", "-e", TOP], d, log) == 0)
        run = [NVC, "--std=2008", "-r", "--ieee-warnings=off", TOP]
    if not ok:
        return ("build", "".join(open(log).readlines()[-10:]))
    t0 = time.time()
    with open(d + "/run.log", "w") as f:
        rc = subprocess.run(run, cwd=d, stdout=f, stderr=subprocess.STDOUT).returncode
    secs = time.time() - t0
    txt = open(d + "/run.log").read()
    m = re.search(r"@?(\d+)ns[+:].*ALL TESTS PASSED", txt)
    if rc == 0 and m:
        parts = re.findall(r"@?(\d+)ns[+:].*(part [12] done)", txt)
        return ("pass", "end %s ns (%s), %.0f s" % (m.group(1), ", ".join("%s at %s ns" % (p, t) for t, p in parts), secs))
    w = re.search(r"(?:\((?:assertion|report) (?:failure|error)\): |\*\* (?:Failure|Error): [^:]*: )(.*)", txt)
    return ("fail", (w.group(1).strip() if w else "exit %d, no message" % rc) + " (%.0f s)" % secs)

# ---------------------------------------------------------------------------------------------
# mutants of the controller
# ---------------------------------------------------------------------------------------------
src = open(CTL).read()
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
SUSP_C  = "          elsif step_st /= SI_IDLE or head_settled = '0' then\n"
SUSP    = SUSP_C + "            -- the head moves or settles: this time does not count\n            idx_gap_cnt <= (others => '0');\n"

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
 # the rule for a moving head (issue #257, part E)
 ("moving_no_suspension", [(SUSP, "")]),
 ("moving_suspension_without_restart", [(SUSP, SUSP.replace("            idx_gap_cnt <= (others => '0');\n", "            null;\n"))]),
 ("moving_suspension_until_index", [
    (DECL, DECL + "\n  signal susp_l : std_logic := '0';"),
    (EDGE, EDGE + "            susp_l      <= '0';\n"),
    (SUSP, "          elsif step_st /= SI_IDLE or head_settled = '0' or susp_l = '1' then\n            susp_l <= '1';\n            idx_gap_cnt <= (others => '0');\n")]),
 ("moving_suspension_steps_only", [(SUSP_C, "          elsif step_st /= SI_IDLE then\n")]),
 ("moving_suspension_settle_only", [(SUSP_C, "          elsif head_settled = '0' then\n")]),
 ("moving_index_ignored_during_step", [(EDGE + SUSP, SUSP.replace("          elsif", "          if", 1) + EDGE.replace("          if", "          elsif", 1))]),
 ("moving_rise_blocked", [(A_READY, A_READY.replace("idx_seen = '1' then", "idx_seen = '1' and step_st = SI_IDLE and head_settled = '1' then"))]),
 ("moving_drop_deferred", [(SUSP, "          elsif (step_st /= SI_IDLE or head_settled = '0') and idx_gap_cnt >= to_unsigned(2 * G_PERIOD_MAX_CYC, 32) then\n            null;\n")]),
]
os.makedirs(BUILD + "/mut", exist_ok=True)
muts = []
for name, reps in M:
    txt = src
    for old, new in reps:
        if txt.count(old) != 1:
            print("    mutant %s: pattern found %d times (expected once): %r" % (name, txt.count(old), old[:50]))
            FAILS.append("mutant_pattern_" + name)
            break
        txt = txt.replace(old, new)
    else:
        f = "%s/mut/%s.vhd" % (BUILD, name)
        open(f, "w").write(txt)
        muts.append((name, f))

# ---------------------------------------------------------------------------------------------
t_start = time.time()
sims = [SIM] if SIM == "ghdl" else ["nvc", "ghdl"]
bases = {s: base(s) for s in sims}
jobs = [("ref_" + s, CTL, s) for s in sims] + [(n, f, SIM) for n, f in muts]
with ThreadPoolExecutor(max_workers=JOBS) as ex:
    res = list(ex.map(lambda j: (j, build_run(j[0], j[1], j[2], bases[j[2]])), jobs))

print("=== media contract (%s)" % TOP)
ends = {}
for (name, ctl, sim), (st, msg) in res:
    if not name.startswith("ref_"): continue
    print("    %s: %s %s" % (sim, st, msg if st != "build" else "\n" + msg))
    if st != "pass": FAILS.append("bench_" + sim)
    else: ends[sim] = msg.split(" ns")[0]
if len(set(ends.values())) > 1:
    FAILS.append("end_times_differ_between_simulators")
print("=== mutants of the controller (%s)" % SIM)
n = 0
for (name, ctl, sim), (st, msg) in res:
    if name.startswith("ref_"): continue
    n += 1
    if st == "pass":
        print("  FAIL: mutant '%s' not detected" % name); FAILS.append("mutant_%s_not_detected" % name)
    elif st == "build":
        print("  FAIL: mutant '%s' does not build:\n%s" % (name, msg)); FAILS.append("mutant_%s_does_not_build" % name)
    else:
        print("  mutant '%s' rejected: %s" % (name, msg))
if n != len(M):
    FAILS.append("only_%d_of_%d_mutants_ran" % (n, len(M)))
print("wall time %.0f s (JOBS=%d)" % (time.time() - t_start, JOBS))
open(BUILD + "/fails.txt", "w").write(" ".join(FAILS))
PYEOF
PYRC=$?
FAILS=$(cat "$BUILD/fails.txt" 2>/dev/null || echo "runner")
[ $PYRC -eq 0 ] || FAILS="$FAILS runner_exit_$PYRC"

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
