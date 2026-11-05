#!/usr/bin/env bash
# Runner for the turbo-mode benches (issue #87, doc/dev-turbo/TURBO-SPEC.md section 6,
# doc/dev-turbo/TEST-PLAN.md section 2).
#
#   CORE/vhdl/test/tb_turbo/run.sh [baseline|d6048db|new|smart|static|all] [--keep]
#
#   baseline  core bench (tb_turbo_core) on the baseline sources (git show of 55918e6 and of the
#             submodule at 650c6b5), plus the latency mutants: S1-S5, S7, I5, I6, data integrity of
#             every source at its real latency, and F2 must be REPRODUCED (real-cartridge accesses
#             directly after turbo accesses, short pin time, wrong data with a 150 ns cartridge)
#   d6048db   baseline versus baseline + upstream d6048db (S8): per-clock traces must be identical
#   new       core bench on the working tree; same checks, but F2 must be GONE; I1: the per-clock
#             trace with turbo Off equals the baseline trace; latency mutants on the new sources
#   smart     tb_turbo_smart: the Smart detector process of CORE/vhdl/main.vhd (the copy in the
#             bench must equal the text between the marker lines), two clock speeds, two mutants
#   static    GHDL analysis of main.vhd, mega65.vhd and the core files, working tree versus
#             baseline: no new errors or warnings
#   all       everything above (default)
#   --keep    keep the build directory (logs, traces) and print its path
#
# Environment: NVC (default /usr/local/bin/nvc, 1.21; the core bench uses VHDL-2008 external
# names, which GHDL 5.1.1 cannot elaborate), GHDL (default /usr/local/bin/ghdl, static target),
# JOBS (parallel simulations, default 2, max 2).
# Prints every bench result and a final "RESULT: PASS" or "RESULT: FAIL ..." line; exit status 0
# only on PASS. Build products go to a temporary directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
SUB="$REPO/CORE/C64_MiSTerMEGA65"
MAIN_REV=55918e6
SUB_REV=650c6b5
NVC="${NVC:-/usr/local/bin/nvc}"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
JOBS="${JOBS:-2}"; [ "$JOBS" -gt 2 ] && JOBS=2
WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      baseline|d6048db|new|smart|static|all) WHAT="$a" ;;
      *) echo "RESULT: FAIL unknown argument '$a' (use baseline, d6048db, new, smart, static, all, --keep)"; exit 2 ;;
   esac
done

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_turbo.XXXXXX")"
if [ $KEEP -eq 1 ]; then echo "build directory: $BUILD"; else trap 'rm -rf "$BUILD"' EXIT; fi
T0=$(date +%s)
status=0
failed=""
note_fail() { status=1; failed="$failed $1"; echo "FAIL: $1"; }
want() { [ "$WHAT" = "all" ] || [ "$WHAT" = "$1" ]; }

CORE_FILES="t65/T65_Pack.vhd t65/T65_ALU.vhd t65/T65_MCode.vhd t65/T65.vhd cpu_6510.vhd dprom.vhd spram.vhd
            fpga64_rgbcolor.vhd video_vicII_656x.vhd fpga64_buslogic.vhd fpga64_sid_iec.vhd"
ROMS="chargen chargenj std_C64GS std_C64 jap_C64"

# --------------------------------------------------------------------------------------------------
# export_sources <dir> <base|new>: core files, ROM images and the two M2M RAM files
export_sources() {
   local D="$1" SRC="$2" f r
   mkdir -p "$D/src/t65" "$D/src/roms"
   for f in $CORE_FILES; do
      if [ "$SRC" = base ]; then git -C "$SUB" show "$SUB_REV:rtl/$f" > "$D/src/$f" || return 1
      else cp "$SUB/rtl/$f" "$D/src/$f" || return 1; fi
   done
   for r in $ROMS; do
      if [ "$SRC" = base ]; then git -C "$SUB" show "$SUB_REV:rtl/roms/$r.mif.hex" > "$D/src/roms/$r.mif.hex" || return 1
      else cp "$SUB/rtl/roms/$r.mif.hex" "$D/src/roms/" || return 1; fi
   done
   for f in tdp_ram.vhd 2port2clk_ram.vhd; do
      if [ "$SRC" = base ]; then git -C "$REPO" show "$MAIN_REV:M2M/vhdl/$f" > "$D/src/$f" || return 1
      else cp "$REPO/M2M/vhdl/$f" "$D/src/" || return 1; fi
   done
   if [ "$SRC" = base ]; then git -C "$REPO" show "$MAIN_REV:CORE/vhdl/cartridge_heuristics.vhd" > "$D/src/cartridge_heuristics.vhd" || return 1
   else cp "$REPO/CORE/vhdl/cartridge_heuristics.vhd" "$D/src/" || return 1; fi
}

# patch_sources <dir> <d6048db 0|1>: the two simulator patches (identical for every source set)
# and optionally upstream d6048db
patch_sources() {
   python3 - "$1/src/fpga64_sid_iec.vhd" "$2" <<'EOF'
import sys
p, d6 = sys.argv[1], sys.argv[2] == "1"
s = open(p).read()
def rep(a, b, what):
    global s
    if s.count(a) != 1:
        print(f"  patch '{what}' does not apply to {p} (found {s.count(a)} times)")
        sys.exit(1)
    s = s.replace(a, b)
# nvc evaluates sysCycleDef'succ(CYCLE_CPUF) before the following if overrides it (range error)
rep("\t\tpreCycle <= sysCycleDef'succ(preCycle);\n",
    "\t\tif preCycle /= sysCycleDef'high then preCycle <= sysCycleDef'succ(preCycle); end if; -- tb_turbo: simulator patch\n",
    "preCycle succ")
# the FPGA powers up with rfsh_cycle = 0; without it the state machine never starts in simulation
rep("signal rfsh_cycle   : unsigned(1 downto 0);",
    'signal rfsh_cycle   : unsigned(1 downto 0) := "00"; -- tb_turbo: simulator patch (FPGA power-up value)',
    "rfsh_cycle init")
if d6:
    rep("signal cs_vic       : std_logic;", "signal cs_io        : std_logic;\nsignal cs_vic       : std_logic;", "d6048db decl")
    rep("IOE <= ioe_i;\nIOF <= iof_i;\n", "IOE <= ioe_i;\nIOF <= iof_i;\ncs_io <= cs_vic or cs_sid or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i;\n", "d6048db cs_io")
    rep("if dma_req = '0' and ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then",
        "if cs_io = '0' and dma_req = '0' and ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then", "d6048db decision")
open(p, "w").write(s)
EOF
}

# build_set <set> <base|new> <d6048db 0|1>
build_set() {
   local SET="$1" D="$BUILD/$1" f files=""
   echo "--- building source set '$SET' (sources: $2$( [ "$3" = 1 ] && echo ' + upstream d6048db'))"
   export_sources "$D" "$2" || { echo "  export failed"; return 1; }
   patch_sources "$D" "$3" || return 1
   for f in $CORE_FILES; do
      case "$f" in
         fpga64_sid_iec.vhd) files="$files $HERE/tb_turbo_stubs.vhd $D/src/$f" ;;
         dprom.vhd)          files="$files $D/src/$f $D/src/tdp_ram.vhd $D/src/2port2clk_ram.vhd" ;;
         *)                  files="$files $D/src/$f" ;;
      esac
   done
   # the bench connects cpu_deferred (core) and busy_o (cartridge_heuristics) only where they exist
   python3 - "$HERE/tb_turbo_core.vhd" "$D/src/tb_turbo_core.vhd" "$D/src/fpga64_sid_iec.vhd" \
             "$D/src/cartridge_heuristics.vhd" <<'PYEOF'
import re, sys
src, dst, core, heur = sys.argv[1:5]
s = open(src).read()
has_def = re.search(r"\bcpu_deferred\s*:\s*out\b", open(core).read()) is not None
has_busy = re.search(r"\bbusy_o\s*:\s*out\b", open(heur).read()) is not None
if has_def: s = s.replace("--@if_deferred ", "")
if has_busy: s = s.replace("--@if_busy ", "")
open(dst, "w").write(s)
print(f"  core port cpu_deferred: {'connected' if has_def else 'absent (0)'}, "
      f"cartridge_heuristics busy_o: {'connected' if has_busy else 'absent (0)'}")
PYEOF
   ( cd "$D" && "$NVC" --std=2008 --work=work:"$D/work" -a --relaxed $files "$D/src/cartridge_heuristics.vhd" \
        "$D/src/tb_turbo_core.vhd" ) > "$D/analyze.log" 2>&1
   if grep -q "Error" "$D/analyze.log" || [ ! -d "$D/work" ]; then
      grep -A4 "Error" "$D/analyze.log" | head -30
      return 1
   fi
}

# run the scenarios of the given sets, at most $JOBS in parallel
run_sets() {
   python3 "$HERE/evaluate.py" --jobs "$@" > "$BUILD/jobs.txt"
   cat > "$BUILD/job.sh" <<EOF
#!/usr/bin/env bash
set=\$1; name=\$2; shift 2
R="$BUILD/\$set/\$name"; mkdir -p "\$R"; cd "\$R" || exit 1
ln -sf ../src/roms roms; cp "$BUILD/cart.hex" .; echo "\$*" > scenario.txt
t0=\$(date +%s)
"$NVC" --ieee-warnings=off --std=2008 --work=work:"$BUILD/\$set/work" -e --jit tb_turbo_core -r > log.txt 2>&1
[ -f trace.txt ] && gzip -1 -f trace.txt
echo "  ran \$set/\$name in \$(( \$(date +%s) - t0 )) s"
EOF
   chmod +x "$BUILD/job.sh"
   xargs -P "$JOBS" -L 1 "$BUILD/job.sh" < "$BUILD/jobs.txt"
   # bench outputs: all TB lines of a scenario on one line, plus the first notes and errors
   while read -r set name cfg; do
      echo "[$set/$name] scenario '$cfg':"
      grep "^TB: " "$BUILD/$set/$name/log.txt" | sed 's/^TB: //' | tr '\n' ' ' | fold -s -w 160 | sed 's/^/    /'
      echo
      grep "F2 data error\|read data error\|RAM write lost\|S2 violation\|TB_ERROR\|Fatal\|Error" "$BUILD/$set/$name/log.txt" | head -4 | sed 's/^/    /'
   done < "$BUILD/jobs.txt"
}

# --------------------------------------------------------------------------------------------------
SETS=""
want baseline && SETS="baseline"
want d6048db && SETS="baseline d6048db"
want new && SETS="baseline new"
[ "$WHAT" = all ] && SETS="baseline d6048db new"
if [ -n "$SETS" ]; then
   echo "=== core bench (tb_turbo_core)"
   # the main.vhd glue of the bench must be a copy of the current CORE/vhdl/main.vhd
   python3 - "$REPO/CORE/vhdl/main.vhd" "$HERE/tb_turbo_core.vhd" <<'PYEOF' || note_fail main_vhd_glue_copy
import sys
def norm(lines):
    out = []
    for l in lines:
        l = l.split("--", 1)[0]
        l = " ".join(l.split())
        if l:
            out.append(l)
    return out
m = norm(open(sys.argv[1]).read().splitlines())
t = open(sys.argv[2]).read().splitlines()
blocks, cur = [], None
for l in t:
    if "-- [main.vhd copy begin]" in l:
        cur = []
    elif "-- [main.vhd copy end]" in l:
        blocks.append(norm(cur)); cur = None
    elif cur is not None:
        cur.append(l)
bad = 0
for b in blocks:
    found = any(m[i:i + len(b)] == b for i in range(len(m) - len(b) + 1))
    if not found:
        bad += 1
        print(f"  main.vhd copy NOT FOUND in CORE/vhdl/main.vhd: {b[0][:100]} ...")
print(f"  main.vhd glue: {len(blocks)} copied blocks, {len(blocks) - bad} found verbatim in CORE/vhdl/main.vhd")
sys.exit(1 if bad or not blocks else 0)
PYEOF
   python3 "$HERE/gen_cart.py" "$BUILD/cart.hex" "$BUILD/cart.lst" || note_fail gen_cart
   build_ok=1
   for s in $SETS; do
      case "$s" in
         baseline) build_set baseline base 0 || { note_fail build_baseline; build_ok=0; } ;;
         d6048db)  build_set d6048db base 1  || { note_fail build_d6048db; build_ok=0; } ;;
         new)      build_set new new 0       || { note_fail build_new; build_ok=0; } ;;
      esac
   done
   # latency mutants on the newest sources of this run
   case "$SETS" in *new*) MSRC=new ;; *) MSRC=base ;; esac
   build_set mutants "$MSRC" 0 || { note_fail build_mutants; build_ok=0; }
   if [ $build_ok -eq 1 ]; then
      run_sets $SETS mutants
      python3 "$HERE/evaluate.py" "$BUILD" $SETS mutants || note_fail core_bench
   fi
fi

# --------------------------------------------------------------------------------------------------
if want smart; then
   echo "=== Smart detector bench (tb_turbo_smart)"
   mkdir -p "$BUILD/smart"
   python3 - "$REPO/CORE/vhdl/main.vhd" "$HERE/tb_turbo_smart.vhd" <<'EOF'
import sys
m = open(sys.argv[1]).read().splitlines()
t = open(sys.argv[2]).read().splitlines()
B, E = "-- [turbo_smart_iec_detector begin]", "-- [turbo_smart_iec_detector end]"
mb = [n for n, l in enumerate(m) if l.strip() == B]
me = [n for n, l in enumerate(m) if l.strip() == E]
if len(mb) != 1 or len(me) != 1 or me[0] < mb[0]:
    print("  smart: not yet implemented (marker lines missing in CORE/vhdl/main.vhd)")
    sys.exit(2)
s = next(n for n, l in enumerate(t) if "-- BEGIN COPY" in l) + 1
e = next(n for n, l in enumerate(t) if "-- END COPY" in l)
norm = lambda ls: [" ".join(l.split()) for l in ls if l.strip()]
same = norm(m[mb[0]:me[0] + 1]) == norm(t[s:e])
print(f"  main.vhd lines {mb[0] + 1}-{me[0] + 1} versus tb_turbo_smart.vhd lines {s + 1}-{e}: "
      f"{'identical' if same else 'DIFFERENT'}")
sys.exit(0 if same else 1)
EOF
   rc=$?
   if [ $rc -eq 2 ]; then
      note_fail smart_not_yet_implemented
   else
      [ $rc -ne 0 ] && note_fail smart_copy_differs
      ( cd "$BUILD/smart" && "$NVC" --std=2008 --work=work:"$BUILD/smart/work" -a "$HERE/tb_turbo_smart.vhd" ) > "$BUILD/smart/analyze.log" 2>&1 ||
         { cat "$BUILD/smart/analyze.log"; note_fail smart_analysis; }
      for sp in 1000 777; do
         ( cd "$BUILD/smart" && "$NVC" --std=2008 --work=work:"$BUILD/smart/work" -e --jit -gG_SPEED=$sp tb_turbo_smart -r ) \
            > "$BUILD/smart/run_$sp.log" 2>&1
         grep -v "^ *Process\|^ *Procedure\|STOP called" "$BUILD/smart/run_$sp.log" | sed 's/^\*\* Note: [^:]*: /  /'
         grep -q "RESULT: PASS" "$BUILD/smart/run_$sp.log" || note_fail "smart_speed_$sp"
      done
      # mutants the bench must reject: wrong timeout, hardware IEC clock not watched
      for mut in timeout hwclk; do
         mkdir -p "$BUILD/smart_$mut"
         python3 - "$mut" "$HERE/tb_turbo_smart.vhd" "$BUILD/smart_$mut/tb_turbo_smart.vhd" <<'EOF'
import sys
mut, src, dst = sys.argv[1:4]
s = open(src).read()
if mut == "timeout":
    t = s.replace("timer := clk_main_speed_i / 2;", "timer := clk_main_speed_i / 4;")
else:
    t = s.replace(" or hw_iec_clk_n_sync /= hw_clk_prev then", " then")
open(dst, "w").write(t)
sys.exit(0 if t != s else 1)
EOF
         if [ $? -ne 0 ]; then note_fail "smart_mutant_${mut}_not_applied"; continue; fi
         ( cd "$BUILD/smart_$mut" && "$NVC" --std=2008 --work=work:"$BUILD/smart_$mut/work" -a tb_turbo_smart.vhd &&
           "$NVC" --std=2008 --work=work:"$BUILD/smart_$mut/work" -e --jit tb_turbo_smart -r ) > "$BUILD/smart_$mut.log" 2>&1
         if grep -q "RESULT: FAIL" "$BUILD/smart_$mut.log"; then
            echo "  mutant $mut: rejected as expected ($(grep -c 'FAIL:' "$BUILD/smart_$mut.log") findings)"
         else
            note_fail "smart_mutant_${mut}_not_detected"
         fi
      done
   fi
fi

# --------------------------------------------------------------------------------------------------
if want static; then
   echo "=== static analysis (GHDL, working tree versus baseline)"
   G="$GHDL"; F="--std=08 -frelaxed -fsynopsys"
   for v in base new; do
      L="$BUILD/static/$v"; mkdir -p "$L/lib" "$L/xpm"
      export_sources "$L" "$v" || note_fail "static_export_$v"
      { printf 'library ieee;\nuse ieee.std_logic_1164.all;\nuse ieee.numeric_std.all;\n'
        sed -n '/^package vdrives_pkg/,/^end package/p' "$REPO/M2M/vhdl/vdrives.vhd"; } > "$L/vdrives_pkg.vhd"
      for f in main mega65; do
         if [ $v = base ]; then git -C "$REPO" show "$MAIN_REV:CORE/vhdl/$f.vhd" > "$L/$f.vhd"
         else cp "$REPO/CORE/vhdl/$f.vhd" "$L/$f.vhd"; fi
      done
      "$G" -a $F --work=xpm --workdir="$L/xpm" "$REPO/doc/dev-ntsc/tools/stubs/xpm_vcomponents.vhd" > /dev/null 2>&1
      "$G" -a $F --workdir="$L/lib" -P"$L/xpm" "$REPO/M2M/QNICE/vhdl/tools.vhd" "$REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd" \
         "$REPO/CORE/vhdl/globals.vhd" "$L/vdrives_pkg.vhd" "$REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd" > /dev/null 2>&1
      # GHDL rejects case statements on std_logic_vector without "others" (Vivado accepts them):
      # fpga64_rgbcolor is analyzed as entity only, the turbo_speed case of fpga64_sid_iec gets
      # "others" instead of "11" (same patch on both sides).
      # main.vhd cannot be stored (sub-entities missing), so mega65.vhd is checked against main's entity.
      python3 - "$L" <<'PYEOF'
import re, sys
L = sys.argv[1]
s = open(L + "/src/fpga64_rgbcolor.vhd").read()
open(L + "/src/fpga64_rgbcolor.vhd", "w").write(s[:s.lower().index("architecture")] +
     "architecture stub of fpga64_rgbcolor is\nbegin\nend architecture;\n")
c = open(L + "/src/fpga64_sid_iec.vhd").read()
assert c.count('when "11" => turbo_m <= "111";') == 1, "fpga64_sid_iec: turbo_speed case not found"
open(L + "/src/fpga64_sid_iec.vhd", "w").write(c.replace('when "11" => turbo_m <= "111";', 'when others => turbo_m <= "111";'))
m = open(L + "/main.vhd").read()
e = re.search(r"end\s+entity\s+main\s*;", m, re.I)
open(L + "/main_entity.vhd", "w").write(m[:e.end()] + "\n")
PYEOF
      : > "$L/diag.txt"
      for f in $CORE_FILES; do
         [ "$f" = dprom.vhd ] && "$G" -a $F --workdir="$L/lib" "$L/src/tdp_ram.vhd" "$L/src/2port2clk_ram.vhd" >> "$L/diag.txt" 2>&1
         "$G" -a $F --workdir="$L/lib" "$L/src/$f" >> "$L/diag.txt" 2>&1
      done
      "$G" -a $F --workdir="$L/lib" -P"$L/xpm" "$L/main.vhd" >> "$L/diag.txt" 2>&1
      "$G" -a $F --workdir="$L/lib" -P"$L/xpm" "$L/main_entity.vhd" >> "$L/diag.txt" 2>&1
      "$G" -a $F --workdir="$L/lib" -P"$L/xpm" "$L/mega65.vhd" >> "$L/diag.txt" 2>&1
      grep "error\|warning" "$L/diag.txt" | grep -v "compilation error" | sed 's/^[^:]*:[0-9]*:[0-9]*: *//' | sort > "$L/diag.norm"
   done
   echo "  baseline: $(wc -l < "$BUILD/static/base/diag.norm" | tr -d ' ') diagnostics, working tree: $(wc -l < "$BUILD/static/new/diag.norm" | tr -d ' ')"
   sed 's/^/    /' "$BUILD/static/new/diag.norm" | uniq -c | head -30
   if diff "$BUILD/static/base/diag.norm" "$BUILD/static/new/diag.norm" > "$BUILD/static/diff.txt"; then
      echo "  identical diagnostic sets: no new errors or warnings (main.vhd, mega65.vhd, core files incl. the port maps)"
   else
      sed 's/^/  /' "$BUILD/static/diff.txt" | head -20
      note_fail static_new_diagnostics
   fi
fi

echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL benches failed:$failed"
fi
exit $status
