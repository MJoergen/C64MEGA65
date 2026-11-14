#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Amiga mouse benches (GitHub issue #190), see README.md
#
#   CORE/vhdl/test/tb_amiga_mouse/run.sh [decoder|buttons|ports|synth|all] [--keep] [--jobs N]
#                                        [--no-mutants]
#
#   decoder  M2M/vhdl/amiga_mouse.vhd alone (tb_amiga_mouse.vhd): transitions, double transitions,
#            pulses shorter and longer than the filter, a model of the mouse with chatter, the rate
#            limiter, the movement routine of the 1351 manual at PAL and NTSC call rates, enable_i,
#            the times at the PAL and at the NTSC clock; plus the mutants of the decoder
#   buttons  the right and the middle button on the paddle pins, the default times at a slow clock;
#            plus the mutants of the button logic
#   ports    M2M/vhdl/debouncer.vhd (tb_amiga_ports.vhd) against the entity of commit 6845596 and
#            in all combinations of the port switcher, the Amiga settings and the on/off switches;
#            differential analysis of framework.vhd with the old and the new debouncer; plus the
#            mutants of the port conditioning
#   synth    ghdl synth of amiga_mouse and of debouncer: no error, no latch, number of flip-flops
#   all      everything (default)
#
# Every simulation runs with a timeout of 25 minutes; the runs are spread over --jobs processes
# (default 4, or $JOBS). A mutant is an exact text replacement in a copy of a source; the bench
# runs it with G_STOP (end at the first error) and must not report "TB: RESULT PASS".
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime about 9 minutes
# with 4 processes (20 minutes of processor time).
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=6845596        # WIP-V6-A25: the last commit before the Amiga mice

WHAT=all
KEEP=0
MUTANTS=1
JOBS=${JOBS:-4}
while [ $# -gt 0 ]; do
   case "$1" in
      decoder|buttons|ports|synth|all) WHAT=$1 ;;
      --keep) KEEP=1 ;;
      --no-mutants) MUTANTS=0 ;;
      --jobs) shift; JOBS=$1 ;;
      *) echo "usage: $0 [decoder|buttons|ports|synth|all] [--keep] [--jobs N] [--no-mutants]"; exit 2 ;;
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

# the entity before the Amiga mice, renamed to debouncer_ref
ref_entity() {
   git -C "$REPO" show "$BASE:M2M/vhdl/debouncer.vhd" > "$BUILD/debouncer_base.vhd" 2>/dev/null || return 1
   python3 - "$BUILD/debouncer_base.vhd" "$1" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
pats = [(r"\bentity debouncer is\b", "entity debouncer_ref is"), (r"\bend debouncer;", "end debouncer_ref;"),
        (r"\bof debouncer is\b", "of debouncer_ref is")]
for p, r in pats:
    if len(re.findall(p, s)) != 1:
        print(f"    {p}: not found exactly once in the base version")
        sys.exit(1)
    s = re.sub(p, r, s)
open(sys.argv[2], "w").write(s)
PYEOF
}

# the sources are copied first, so that a run is not disturbed by edits while it runs
SRC_M2M="$BUILD/src/m2m"
SRC_TB="$BUILD/src/tb"
mkdir -p "$SRC_M2M" "$SRC_TB"
cp "$REPO/M2M/vhdl/debounce.vhd" "$REPO/M2M/vhdl/amiga_mouse.vhd" "$REPO/M2M/vhdl/debouncer.vhd" \
   "$REPO/M2M/vhdl/framework.vhd" "$SRC_M2M/" &&
cp "$HERE"/*.vhd "$HERE/mutants.py" "$SRC_TB/" || { echo "cannot copy the sources"; exit 1; }
# sources of a library: debounce, amiga_mouse, debouncer, debouncer_ref, package, benches
lib_sources() {        # lib_sources <amiga_mouse.vhd> <debouncer.vhd>
   echo "$SRC_M2M/debounce.vhd $1 $2 $BUILD/debouncer_ref.vhd $SRC_TB/tb_amiga_mouse_pkg.vhd $SRC_TB/tb_amiga_mouse.vhd $SRC_TB/tb_amiga_ports.vhd"
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
if want decoder || want buttons || want ports; then
   echo "=== build"
   if ref_entity "$BUILD/debouncer_ref.vhd" &&
      analyze "$M" $(lib_sources "$SRC_M2M/amiga_mouse.vhd" "$SRC_M2M/debouncer.vhd") &&
      elaborate "$M" tb_amiga_mouse tb_amiga_ports; then
      echo "  amiga_mouse, debouncer, debouncer_ref ($BASE) and the two benches analyzed and elaborated"
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
   job times_pal       run "$M" $T "-gG_PART=times"
   job times_ntsc      run "$M" $T "-gG_PART=times $NTSC"
fi
SMALL="-gG_STEP_US=10 -gG_CONFIRM_US=100 -gG_STUCK_MS=5"
if want buttons; then
   job buttons         run "$M" $T "-gG_PART=buttons $SMALL"
   job defaults        run "$M" $T "-gG_PART=defaults -gG_CLK_HZ=100000 -gG_FREQ=100000"
fi
if want ports; then
   job ports_identity  run "$M" tb_amiga_ports "-gG_PART=identity"
   job ports_modes     run "$M" tb_amiga_ports "-gG_PART=modes"
fi

# --------------------------------------------------------------------------------------------------
# mutants: name|part|file|bench run (args); the old and the new text are in mutants.py
if [ $MUTANTS -eq 1 ] && [ $BUILT -eq 1 ]; then
   echo "=== build mutants"
   python3 "$SRC_TB/mutants.py" list "$WHAT" > "$BUILD/mutants.txt" || note_fail mutant_table
   while IFS='|' read -r name kind file unit args; do
      D="$BUILD/mut_$name"
      mkdir -p "$D"
      AM="$SRC_M2M/amiga_mouse.vhd"
      DB="$SRC_M2M/debouncer.vhd"
      case $file in
         amiga_mouse) AM="$D/amiga_mouse.vhd" ;;
         debouncer)   DB="$D/debouncer.vhd" ;;
      esac
      if python3 "$SRC_TB/mutants.py" make "$name" "$SRC_M2M/$file.vhd" "$D/$file.vhd" &&
         analyze "$D" $(lib_sources "$AM" "$DB") && elaborate "$D" "$unit"; then
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
cost = {"driver": 9, "ports_modes": 8, "model": 7, "rate_follow": 6, "ports_identity": 6, "dir": 4,
        "enable": 4, "rate_sat": 3}
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
PKGS="$REPO/M2M/QNICE/vhdl/tools.vhd
      $REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd
      $REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd
      $REPO/CORE/vhdl/globals.vhd"

# diags <lib> <file>: analyze file (Xilinx library clauses removed) and print its normalized
# diagnostics (file names and positions stripped), one per line, sorted
diags() {
   local lib=$1 f=$2
   grep -v -i -E "^\s*(library|use)\s+(xpm|unisim)\b" "$f" > "$lib/$(basename "$f").nox.vhd"
   "$GHDL" -a $GF --workdir="$lib" "$lib/$(basename "$f").nox.vhd" 2>&1 |
      sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//' | sort
}

if want ports; then
   echo "=== framework.vhd with the old and with the new debouncer"
   D="$BUILD/frame"
   if [ ! -f "$BUILD/debouncer_base.vhd" ]; then
      git -C "$REPO" show "$BASE:M2M/vhdl/debouncer.vhd" > "$BUILD/debouncer_base.vhd"
   fi
   if analyze "$D/base" $PKGS "$SRC_M2M/debounce.vhd" "$BUILD/debouncer_base.vhd" &&
      analyze "$D/new" $PKGS "$SRC_M2M/debounce.vhd" "$SRC_M2M/amiga_mouse.vhd" "$SRC_M2M/debouncer.vhd"; then
      diags "$D/base" "$SRC_M2M/framework.vhd" > "$D/base.txt"
      diags "$D/new" "$SRC_M2M/framework.vhd" > "$D/new.txt"
      if diff "$D/base.txt" "$D/new.txt" > "$D/diff.txt"; then
         echo "  framework.vhd: $(wc -l < "$D/new.txt" | tr -d ' ') diagnostics (entities outside this bench), identical with the old and the new debouncer"
      else
         sed 's/^/    /' "$D/diff.txt" | head -10
         note_fail framework_diff
      fi
      if [ $MUTANTS -eq 1 ]; then
         # mutant: a new input without a default value must show up in the instantiation of framework.vhd
         Q="$D/mut"
         if python3 "$SRC_TB/mutants.py" make amiga_i_no_default "$SRC_M2M/debouncer.vhd" "$Q.vhd" &&
            analyze "$D/mut" $PKGS "$SRC_M2M/debounce.vhd" "$SRC_M2M/amiga_mouse.vhd" "$Q.vhd"; then
            diags "$D/mut" "$SRC_M2M/framework.vhd" > "$D/mut.txt"
            if diff "$D/base.txt" "$D/mut.txt" > /dev/null; then
               note_fail framework_mutant_not_detected
            else
               echo "  mutant amiga_i_no_default: rejected: $(diff "$D/base.txt" "$D/mut.txt" | grep -m1 '^> .*error' | cut -c3-)"
            fi
         else
            note_fail framework_mutant_build
         fi
      fi
   else
      note_fail framework_libs
   fi
fi

# --------------------------------------------------------------------------------------------------
# synth <lib> <unit> <generic>: ghdl synth; no error, no latch; number of flip-flops of the netlist
synth() {
   local lib=$1 unit=$2 gen=$3
   if ! "$GHDL" --synth --std=08 --workdir="$lib" "$gen" "$unit" > "$lib/$unit.net.vhd" 2> "$lib/$unit.synth.log"; then
      sed 's/^/    /' "$lib/$unit.synth.log" | grep -v async_reg | head -10
      return 1
   fi
   if grep -i -q latch "$lib/$unit.synth.log" "$lib/$unit.net.vhd"; then
      echo "    $unit: a latch was inferred"
      return 1
   fi
   python3 - "$lib/$unit.net.vhd" "$unit" "$lib/$unit.synth.log" <<'PYEOF'
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
PYEOF
}

if want synth; then
   echo "=== synthesis (ghdl synth)"
   S="$BUILD/synth"
   mkdir -p "$S"
   if "$GHDL" -a --std=08 --workdir="$S" "$SRC_M2M/debounce.vhd" "$SRC_M2M/amiga_mouse.vhd" "$SRC_M2M/debouncer.vhd" > "$S/analyze.log" 2>&1; then
      synth "$S" amiga_mouse -gG_CLK_FREQ=31527778 || note_fail synth_amiga_mouse
      synth "$S" debouncer -gCLK_FREQ=31527778 || note_fail synth_debouncer
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
