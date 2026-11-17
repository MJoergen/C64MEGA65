#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Amiga mouse benches (GitHub issue #190), see README.md
#
#   CORE/vhdl/test/tb_amiga_mouse/run.sh [decoder|buttons|ports|keyb|wiring|synth|all] [--keep]
#                                        [--jobs N] [--no-mutants]
#
#   decoder  M2M/vhdl/amiga_mouse.vhd alone (tb_amiga_mouse.vhd): transitions, double transitions,
#            pulses shorter and longer than the filter, a model of the mouse with chatter, the rate
#            limiter, the movement routine of the 1351 manual at PAL and NTSC call rates, enable_i,
#            the times at the PAL and at the NTSC clock; plus the mutants of the decoder
#   buttons  the right and the middle button on the paddle pins, the default times at a slow clock;
#            plus the mutants of the button logic
#   ports    M2M/vhdl/debouncer.vhd (tb_amiga_ports.vhd) against the entity of commit 6845596 and
#            in all combinations of the port switcher, the Amiga settings and the on/off switches;
#            the right click with the MEGA key against the entity of commit 756677a, against a model
#            of SPEC.md section 5.1 under random stimulus around the edges of the debounced fire
#            line, and in directed cases, with its two properties checked at every event and edge;
#            plus the mutants of the port conditioning
#   keyb     the MEGA key output of M2M/vhdl/m2m_keyb.vhd with the keyboard model of tb_capslock
#            (tb_amiga_keyb.vhd): the delay, no other key, independent of enable_core_i, all other
#            outputs identical to the entity of commit 756677a; the real m2m_keyb and debouncer
#            connected as in framework.vhd; plus the mutants of m2m_keyb.vhd
#   wiring   the settings from MEGA65_Core through the four board files, framework.vhd and
#            qnice_wrapper.vhd (wiring.py: GHDL analysis and elaboration against the real entity
#            declarations, differential analysis against 6845596, static check of the clock domain
#            crossings), the crossing of the paddle values in simulation (tb_amiga_cdc.vhd), the
#            port switcher of the paddle values copied out of qnice_wrapper.vhd (tb_amiga_flip.vhd.in);
#            plus the mutants of the wiring
#   synth    ghdl synth of amiga_mouse, of debouncer and of m2m_keyb (with stubs of its two
#            sub-entities): no error, no latch, number of flip-flops, compared with 756677a
#   all      everything (default)
#
# Every simulation runs with a timeout of 25 minutes; the runs are spread over --jobs processes
# (default 4, or $JOBS). A mutant is an exact text replacement in a copy of a source; the bench
# runs it with G_STOP (end at the first error) and must not report "TB: RESULT PASS".
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime of "all" about
# 32 minutes with 2 processes (--jobs 2).
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=6845596        # WIP-V6-A25: the last commit before the Amiga mice
PREV=756677a        # the last commit before the right click with the MEGA key

WHAT=all
KEEP=0
MUTANTS=1
JOBS=${JOBS:-4}
while [ $# -gt 0 ]; do
   case "$1" in
      decoder|buttons|ports|keyb|wiring|synth|all) WHAT=$1 ;;
      --keep) KEEP=1 ;;
      --no-mutants) MUTANTS=0 ;;
      --jobs) shift; JOBS=$1 ;;
      *) echo "usage: $0 [decoder|buttons|ports|keyb|wiring|synth|all] [--keep] [--jobs N] [--no-mutants]"; exit 2 ;;
   esac
   shift
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_amiga_mouse.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
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

# elaborate <lib> <unit>...
elaborate() {
   local lib=$1; shift
   for u in "$@"; do
      ( cd "$lib" && "$GHDL" -e $GF --workdir=. "$u" ) >> "$lib/elab.log" 2>&1 || { sed 's/^/    /' "$lib/elab.log" | head -20; return 1; }
   done
}

# old_entity <commit> <file> <entity> <new name> <out>: the entity of an older commit, renamed
old_entity() {
   git -C "$REPO" show "$1:$2" > "$5.orig" 2>/dev/null || { echo "    $1:$2 not found"; return 1; }
   python3 - "$5.orig" "$5" "$3" "$4" <<'PYEOF'
import re, sys
src, out, ent, new = sys.argv[1:5]
s = open(src).read()
pats = [(rf"\bentity {ent} is\b", f"entity {new} is"), (rf"\bend {ent};", f"end {new};"),
        (rf"\bof {ent} is\b", f"of {new} is")]
for p, r in pats:
    if len(re.findall(p, s)) != 1:
        print(f"    {p}: not found exactly once in the old version")
        sys.exit(1)
    s = re.sub(p, r, s)
open(out, "w").write(s)
PYEOF
}

# the sources are copied first, so that a run is not disturbed by edits while it runs
SRC_M2M="$BUILD/src/m2m"
SRC_TB="$BUILD/src/tb"
mkdir -p "$SRC_M2M" "$SRC_TB"
cp "$REPO/M2M/vhdl/debounce.vhd" "$REPO/M2M/vhdl/amiga_mouse.vhd" "$REPO/M2M/vhdl/debouncer.vhd" \
   "$REPO/M2M/vhdl/cdc_stable.vhd" "$REPO/M2M/vhdl/qnice_wrapper.vhd" "$REPO/M2M/vhdl/m2m_keyb.vhd" \
   "$REPO/M2M/vhdl/controllers/M65/kb_matrix_ram.vhdl" "$REPO/M2M/vhdl/controllers/M65/mega65kbd_to_matrix.vhdl" \
   "$REPO/M2M/vhdl/controllers/M65/matrix_to_keynum.vhdl" "$SRC_M2M/" &&
cp "$HERE"/*.vhd "$HERE/tb_amiga_flip.vhd.in" "$HERE/mutants.py" "$HERE/wiring.py" "$SRC_TB/" ||
   { echo "cannot copy the sources"; exit 1; }
# the entities before the Amiga mice (debouncer_ref) and before the right click (debouncer_prev,
# m2m_keyb_prev)
old_entity "$BASE" M2M/vhdl/debouncer.vhd debouncer debouncer_ref "$BUILD/debouncer_ref.vhd" &&
old_entity "$PREV" M2M/vhdl/debouncer.vhd debouncer debouncer_prev "$BUILD/debouncer_prev.vhd" &&
old_entity "$PREV" M2M/vhdl/m2m_keyb.vhd m2m_keyb m2m_keyb_prev "$BUILD/m2m_keyb_prev.vhd" ||
   { echo "cannot extract the entities of $BASE and $PREV"; exit 1; }

# gen_flip <qnice_wrapper.vhd> <bench.vhd>: the bench of the port switcher with the process
# correct_and_flip_paddles copied verbatim out of qnice_wrapper.vhd
gen_flip() {
   python3 - "$1" "$SRC_TB/tb_amiga_flip.vhd.in" "$2" <<'PYEOF'
import re, sys
src, tmpl, out = sys.argv[1:4]
s = open(src).read()
m = re.findall(r"^[ \t]*correct_and_flip_paddles\s*:\s*process.*?^[ \t]*end process correct_and_flip_paddles;", s,
               re.S | re.M)
if len(m) != 1:
    print(f"    qnice_wrapper.vhd: process correct_and_flip_paddles found {len(m)} times (expected once)")
    sys.exit(1)
t = open(tmpl).read()
if t.count("-- @CORRECT_AND_FLIP_PADDLES@") != 1:
    print("    tb_amiga_flip.vhd.in: marker not found")
    sys.exit(1)
open(out, "w").write(t.replace("-- @CORRECT_AND_FLIP_PADDLES@", m[0].strip()))
PYEOF
}
# sources of a library: debounce, amiga_mouse, debouncer, the old entities, cdc_stable, the keyboard
# chain, package, benches
lib_sources() {        # lib_sources <amiga_mouse.vhd> <debouncer.vhd> <cdc_stable.vhd> <tb_amiga_flip.vhd> <m2m_keyb.vhd>
   echo "$SRC_M2M/debounce.vhd $1 $2 $BUILD/debouncer_ref.vhd $BUILD/debouncer_prev.vhd $3" \
        "$SRC_M2M/kb_matrix_ram.vhdl $SRC_M2M/mega65kbd_to_matrix.vhdl $SRC_M2M/matrix_to_keynum.vhdl $5" \
        "$BUILD/m2m_keyb_prev.vhd $SRC_TB/tb_amiga_mouse_pkg.vhd $SRC_TB/tb_amiga_mouse.vhd" \
        "$SRC_TB/tb_amiga_ports.vhd $SRC_TB/tb_amiga_keyb.vhd $SRC_TB/tb_amiga_cdc.vhd $4"
}

# --------------------------------------------------------------------------------------------------
# simulation runs: one line per run in $BUILD/jobs.txt: name|kind|lib|unit|args
#   kind "run": must end with TB: RESULT PASS; kind "mutant": must not; kind "survivor": a mutant
#   that is expected to survive (reported, not judged)
JOBFILE="$BUILD/jobs.txt"
: > "$JOBFILE"
job() { echo "$1|$2|$3|$4|$5" >> "$JOBFILE"; }

M="$BUILD/main"
BUILT=0
if want decoder || want buttons || want ports || want keyb || want wiring; then
   echo "=== build"
   if gen_flip "$SRC_M2M/qnice_wrapper.vhd" "$BUILD/tb_amiga_flip.vhd" &&
      analyze "$M" $(lib_sources "$SRC_M2M/amiga_mouse.vhd" "$SRC_M2M/debouncer.vhd" "$SRC_M2M/cdc_stable.vhd" "$BUILD/tb_amiga_flip.vhd" "$SRC_M2M/m2m_keyb.vhd") &&
      elaborate "$M" tb_amiga_mouse tb_amiga_ports tb_amiga_keyb tb_amiga_cdc tb_amiga_flip; then
      echo "  amiga_mouse, debouncer, debouncer_ref ($BASE), debouncer_prev ($PREV), cdc_stable, the keyboard chain,"
      echo "  m2m_keyb_prev ($PREV) and the five benches analyzed and elaborated"
      echo "  (tb_amiga_flip with the process correct_and_flip_paddles copied out of qnice_wrapper.vhd)"
      BUILT=1
   else
      note_fail build
   fi
fi

T="tb_amiga_mouse"
FAST="-gG_STEP_US=1"            # rate limiter transparent: a tick every 31 clock cycles
NTSC="-gG_CLK_HZ=32727273"      # the core clock in NTSC mode, G_CLK_FREQ stays PAL
if want decoder; then
   job dir_fast        run "$M" $T "-gG_PART=dir $FAST"
   job dir             run "$M" $T "-gG_PART=dir"
   job double          run "$M" $T "-gG_PART=double $FAST"
   job pulse_pal       run "$M" $T "-gG_PART=pulse $FAST"
   job pulse_ntsc      run "$M" $T "-gG_PART=pulse $FAST $NTSC"
   job model_60_120    run "$M" $T "-gG_PART=model $FAST -gG_PHASE_X=60 -gG_PHASE_Y=120 -gG_SEED=1"
   job model_90_75     run "$M" $T "-gG_PART=model $FAST -gG_PHASE_X=90 -gG_PHASE_Y=75 -gG_SEED=2"
   job model_120_100   run "$M" $T "-gG_PART=model $FAST -gG_PHASE_X=120 -gG_PHASE_Y=100 -gG_SEED=3"
   job rate_follow_90   run "$M" $T "-gG_PART=rate_follow"
   job rate_follow_90p  run "$M" $T "-gG_PART=rate_follow -gG_PARITY=1"
   job rate_follow_60   run "$M" $T "-gG_PART=rate_follow -gG_PHASE_X=60 -gG_PHASE_Y=120"
   job rate_follow_60p  run "$M" $T "-gG_PART=rate_follow -gG_PHASE_X=60 -gG_PHASE_Y=120 -gG_PARITY=1"
   job rate_sat        run "$M" $T "-gG_PART=rate_sat"
   job rate_tick       run "$M" $T "-gG_PART=rate_tick"
   job driver_pal      run "$M" $T "-gG_PART=driver -gG_PHASE_X=70 -gG_PHASE_Y=110 -gG_SEED=4"
   job driver_ntsc     run "$M" $T "-gG_PART=driver -gG_PHASE_X=110 -gG_PHASE_Y=70 -gG_SEED=5 -gG_FRAME_NS=16715000 $NTSC"
   job enable          run "$M" $T "-gG_PART=enable"
   job powerup_enabled  run "$M" $T "-gG_PART=powerup -gG_ENABLED=true"
   job powerup_disabled run "$M" $T "-gG_PART=powerup -gG_ENABLED=false"
   job times_pal       run "$M" $T "-gG_PART=times"
   job times_ntsc      run "$M" $T "-gG_PART=times $NTSC"
fi
SMALL="-gG_STEP_US=10 -gG_CONFIRM_US=100 -gG_STUCK_MS=5"
if want buttons; then
   job buttons         run "$M" $T "-gG_PART=buttons $SMALL"
   job defaults        run "$M" $T "-gG_PART=defaults -gG_CLK_HZ=100000 -gG_FREQ=100000"
fi
TENTH="-gG_FREQ=3152778"        # the instances count a tenth of the clock cycles: all times / 10
if want ports; then
   job ports_identity  run "$M" tb_amiga_ports "-gG_PART=identity"
   job ports_modes     run "$M" tb_amiga_ports "-gG_PART=modes"
   job ports_rule_1    run "$M" tb_amiga_ports "-gG_PART=rule $TENTH -gG_SEED=1"
   job ports_rule_2    run "$M" tb_amiga_ports "-gG_PART=rule $TENTH -gG_SEED=2"
   job ports_rule_pal  run "$M" tb_amiga_ports "-gG_PART=rule -gG_SEED=3 -gG_EPISODES=50"
   job ports_directed  run "$M" tb_amiga_ports "-gG_PART=directed $TENTH"
   job ports_directed_pal run "$M" tb_amiga_ports "-gG_PART=directed"
fi
if want keyb; then
   job keyb            run "$M" tb_amiga_keyb  "-gG_PART=keyb"
   job keyb_start      run "$M" tb_amiga_keyb  "-gG_PART=keyb -gG_START=true -gG_SEED=2"
   job keyb_e2e        run "$M" tb_amiga_keyb  "-gG_PART=e2e"
fi
if want wiring; then
   job cdc             run "$M" tb_amiga_cdc   "-gG_CHANGES=100000"
   job flip            run "$M" tb_amiga_flip  ""
fi

# --------------------------------------------------------------------------------------------------
# mutants: name|part|file|bench run (args); the old and the new text are in mutants.py
if [ $MUTANTS -eq 1 ] && [ $BUILT -eq 1 ] && [ "$WHAT" != synth ]; then
   echo "=== build mutants"
   python3 "$SRC_TB/mutants.py" list "$WHAT" > "$BUILD/mutants.txt" || note_fail mutant_table
   while IFS='|' read -r name kind file unit args; do
      D="$BUILD/mut_$name"
      mkdir -p "$D"
      AM="$SRC_M2M/amiga_mouse.vhd"
      DB="$SRC_M2M/debouncer.vhd"
      CS="$SRC_M2M/cdc_stable.vhd"
      QW="$SRC_M2M/qnice_wrapper.vhd"
      KB="$SRC_M2M/m2m_keyb.vhd"
      case $file in
         amiga_mouse)   AM="$D/amiga_mouse.vhd" ;;
         debouncer)     DB="$D/debouncer.vhd" ;;
         cdc_stable)    CS="$D/cdc_stable.vhd" ;;
         qnice_wrapper) QW="$D/qnice_wrapper.vhd" ;;
         m2m_keyb)      KB="$D/m2m_keyb.vhd" ;;
      esac
      if python3 "$SRC_TB/mutants.py" make "$name" "$SRC_M2M/$file.vhd" "$D/$file.vhd" &&
         gen_flip "$QW" "$D/tb_amiga_flip.vhd" &&
         analyze "$D" $(lib_sources "$AM" "$DB" "$CS" "$D/tb_amiga_flip.vhd" "$KB") && elaborate "$D" "$unit"; then
         job "mutant_$name" "$kind" "$D" "$unit" "$args -gG_STOP=true"
      else
         note_fail "mutant_${name}_build"
      fi
   done < "$BUILD/mutants.txt"
   echo "  $(wc -l < "$BUILD/mutants.txt" | tr -d ' ') mutants built"
fi

if [ -s "$JOBFILE" ] && [ $BUILT -eq 1 ]; then
   echo "=== simulations ($(wc -l < "$JOBFILE" | tr -d ' ') runs on $JOBS processes)"
   python3 - "$GHDL" "$JOBFILE" "$JOBS" "$BUILD/sim_fails.txt" <<'PYEOF'
import subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor, as_completed
ghdl, jobfile, njobs, failfile = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
jobs = [l.rstrip("\n").split("|", 4) for l in open(jobfile) if l.strip()]
# the long runs first
cost = {"driver": 9, "ports_modes": 8, "model": 7, "rate_follow": 6, "ports_identity": 6, "keyb": 5, "dir": 4,
        "enable": 4, "ports_rule_pal": 4, "rate_sat": 3}
def weight(j):
    if j[1] != "run":
        return 0
    return max([v for k, v in cost.items() if j[0].startswith(k)] + [1])
order = sorted(range(len(jobs)), key=lambda i: -weight(jobs[i]))
def run(i):
    name, kind, lib, unit, args = jobs[i]
    t = time.time()
    try:
        r = subprocess.run(["./" + unit] + args.split(), cwd=lib, capture_output=True, text=True, timeout=1500)
        out, rc = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired:
        out, rc = "TIMEOUT\n", 1
    open(f"{lib}/{name}.log", "w").write(out)
    lines = []
    for l in out.splitlines():
        for tag in ("(report note): ", "(report error): "):
            if tag in l:
                l = l.split(tag, 1)[1]
        if l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
            lines.append(l)
    passed = rc == 0 and "TB: RESULT PASS" in out
    return i, time.time() - t, passed, lines
fails = []
with ThreadPoolExecutor(njobs) as ex:
    futs = [ex.submit(run, i) for i in order]
    for f in as_completed(futs):
        i, dt, passed, lines = f.result()
        name, kind = jobs[i][0], jobs[i][1]
        if kind == "run":
            print(f"  --- {name} ({dt:.0f} s)")
            for l in lines:
                if not l.startswith("TB: part "):
                    print("    " + l)
            if not passed:
                fails.append(name)
        else:
            first = next((l for l in lines if "TB_ERROR" in l or "error" in l.lower() or "TIMEOUT" in l),
                         "no error reported")
            first = first.replace("TB_ERROR: ", "")
            if kind == "survivor":
                state = "survives as expected" if passed else "rejected (expected to survive): " + first[:150]
                print(f"  mutant {name[7:]}: {state}")
            elif passed:
                print(f"  mutant {name[7:]}: SURVIVED ({dt:.0f} s)")
                fails.append(name + "_survived")
            else:
                print(f"  mutant {name[7:]}: rejected: {first[:200]}")
        sys.stdout.flush()
open(failfile, "w").write(" ".join(fails))
PYEOF
   for f in $(cat "$BUILD/sim_fails.txt" 2>/dev/null); do
      note_fail "$f"
   done
fi

# --------------------------------------------------------------------------------------------------
if want wiring; then
   echo "=== wiring (wiring.py)"
   python3 "$SRC_TB/wiring.py" check "$REPO" "$BUILD/wiring" "$GHDL" "$BASE" || note_fail wiring
   if [ $MUTANTS -eq 1 ]; then
      python3 "$SRC_TB/wiring.py" mutants "$REPO" "$BUILD/wiring_mut" "$GHDL" "$BASE" "$JOBS" || note_fail wiring_mutants
   fi
fi

# --------------------------------------------------------------------------------------------------
# synth <lib> <unit> [<generic>]: ghdl synth; no error, no latch; number of flip-flops of the netlist
# (written to <lib>/<unit>.ff as "<total> <own>")
synth() {
   local lib=$1 unit=$2 gen=${3:-}
   if ! "$GHDL" --synth --std=08 --workdir="$lib" $gen "$unit" > "$lib/$unit.net.vhd" 2> "$lib/$unit.synth.log"; then
      sed 's/^/    /' "$lib/$unit.synth.log" | grep -v async_reg | head -10
      return 1
   fi
   if grep -i -q latch "$lib/$unit.synth.log" "$lib/$unit.net.vhd"; then
      echo "    $unit: a latch was inferred"
      return 1
   fi
   python3 - "$lib/$unit.net.vhd" "$unit" "$lib/$unit.synth.log" "$lib/$unit.ff" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
# the netlist defines every entity once; count the flip-flops per architecture and multiply them up
# through the instantiations
parts = re.split(r"^architecture rtl of (\w+) is", s, flags=re.M)
own, inst = {}, {}
for name, body in zip(parts[1::2], parts[2::2]):
    decl = {m.group(1): (int(m.group(3)) - int(m.group(4)) + 1 if m.group(3) else 1)
            for m in re.finditer(r"signal (\w+) : (std_logic_vector \((\d+) downto (\d+)\)|std_logic)", body)}
    own[name] = sum(decl.get(r, 0) for r in re.findall(r"if rising_edge \(\w+\) then\s+(\w+) <=", body))
    inst[name] = re.findall(r":\s*entity work\.(\w+)", body)
def total(n):
    return own.get(n, 0) + sum(total(c) for c in inst.get(n, []))
top = sys.argv[2]
subs = ", ".join(f"{len([c for c in inst[top] if c == k])} x {k.split('_')[0]}{'_' + k.split('_')[1] if k.startswith('amiga') else ''} "
                 f"({total(k)})" for k in sorted(set(inst[top])))
warn = [l for l in open(sys.argv[3]) if "warning" in l and "async_reg" not in l]
print(f"  {top}: ghdl synth without error and without a latch, {total(top)} flip-flops"
      + (f" ({own[top]} own; {subs})" if inst[top] else "") + (f", {len(warn)} warnings" if warn else ""))
open(sys.argv[4], "w").write(f"{total(top)} {own[top]}\n")
PYEOF
}

# ff_delta <lib> <new unit> <old unit> <field: 1 total, 2 own> <expected difference> <what>
ff_delta() {
   local a b
   a=$(cut -d' ' -f"$4" "$1/$2.ff" 2>/dev/null) && b=$(cut -d' ' -f"$4" "$1/$3.ff" 2>/dev/null) || return 1
   if [ "$((a - b))" -ne "$5" ]; then
      echo "    $6: $a flip-flops, $3 ($PREV) $b: expected a difference of $5"
      return 1
   fi
   echo "  $6: $a flip-flops, $b in $PREV ($5 more)"
}

if want synth; then
   echo "=== synthesis (ghdl synth)"
   S="$BUILD/synth"
   mkdir -p "$S"
   if "$GHDL" -a --std=08 --workdir="$S" "$SRC_M2M/debounce.vhd" "$SRC_M2M/amiga_mouse.vhd" "$SRC_M2M/debouncer.vhd" \
         "$BUILD/debouncer_prev.vhd" "$SRC_TB/keyb_synth_stubs.vhd" "$SRC_M2M/m2m_keyb.vhd" "$BUILD/m2m_keyb_prev.vhd" \
         > "$S/analyze.log" 2>&1; then
      synth "$S" amiga_mouse -gG_CLK_FREQ=31527778 || note_fail synth_amiga_mouse
      synth "$S" debouncer -gCLK_FREQ=31527778 || note_fail synth_debouncer
      synth "$S" debouncer_prev -gCLK_FREQ=31527778 || note_fail synth_debouncer_prev
      ff_delta "$S" debouncer debouncer_prev 1 2 "debouncer (two flip-flops for the right click)" ||
         note_fail synth_debouncer_ff
      # the real sub-entities of m2m_keyb do not pass ghdl synth; keyb_synth_stubs.vhd stands in for them
      synth "$S" m2m_keyb || note_fail synth_m2m_keyb
      synth "$S" m2m_keyb_prev || note_fail synth_m2m_keyb_prev
      ff_delta "$S" m2m_keyb m2m_keyb_prev 2 1 "m2m_keyb, its own flip-flops (one for the MEGA key)" ||
         note_fail synth_m2m_keyb_ff
      grep -q 'attribute async_reg of lines_d  : signal is "true";' "$SRC_M2M/amiga_mouse.vhd" &&
      grep -q 'attribute async_reg of lines_dd : signal is "true";' "$SRC_M2M/amiga_mouse.vhd" &&
         echo "  amiga_mouse: both synchronizer stages carry async_reg (GHDL ignores the attribute, Vivado uses it)" ||
         note_fail async_reg
   else
      sed 's/^/    /' "$S/analyze.log" | head -10
      note_fail synth_analyze
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
