#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Benches for the bank cache of simulated cartridges (GitHub issue #255), see README.md
#
#   CORE/vhdl/test/tb_crt_cacher/run.sh [--keep]
#
# 1. Elaborates the real CORE/vhdl/sw_cartridge_wrapper.vhd, whose vector widths all derive from
#    the cache size C_CACHE_SIZE, and runs it briefly (tb_wrapper_elab.vhd).
# 2. Runs CORE/vhdl/crt_cacher.vhd with the cache size that the wrapper ships and with the former
#    size 3 against a reference model and checks the contents of every selected cache slot
#    (tb_crt_cacher.vhd). Two mutants of crt_cacher.vhd must fail.
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3. Runtime about 4 minutes;
# JOBS (default 2) sets the number of parallel simulations.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
JOBS=${JOBS:-2}

KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_crt_cacher.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }

CACHER=$REPO/CORE/vhdl/crt_cacher.vhd
WRAPPER=$REPO/CORE/vhdl/sw_cartridge_wrapper.vhd
CTRL=$REPO/M2M/vhdl/controllers/hyperram/hyperram_ctrl.vhd

# The cache size that the core ships
SIZE=$(sed -n 's/^ *constant  *C_CACHE_SIZE *: *natural *:= *\([0-9][0-9]*\) *;.*$/\1/p' "$WRAPPER")
case "$SIZE" in
   [1-6]) echo "sw_cartridge_wrapper.vhd: C_CACHE_SIZE = $SIZE ($((1 << SIZE)) ROML and $((1 << SIZE)) ROMH banks)" ;;
   *) echo "cannot read C_CACHE_SIZE from $WRAPPER"; rm -rf "$BUILD"; exit 1 ;;
esac

# analyze <lib> <files>: prints the diagnostics on failure
analyze() {
   local lib=$1; shift
   mkdir -p "$lib"
   "$GHDL" -a $GF --workdir="$lib" "$@" > "$lib/analyze.log" 2>&1 || { sed 's/^/    /' "$lib/analyze.log" | head -20; return 1; }
}

# elaborate <lib> <unit>
elaborate() {
   ( cd "$1" && "$GHDL" -e $GF --workdir=. "$2" ) > "$1/elab.log" 2>&1 || { sed 's/^/    /' "$1/elab.log" | head -20; return 1; }
}

# sim <lib> <unit> <log> [arguments]: run one simulation (15 min timeout)
sim() {
   python3 - "$GHDL" "$@" <<'PYEOF'
import subprocess, sys
ghdl, lib, unit, log = sys.argv[1:5]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", unit] + sys.argv[5:],
                       cwd=lib, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=900)
    out = r.stdout + r.stderr
except subprocess.TimeoutExpired:
    out = "TIMEOUT\n"
open(log, "w").write(out)
PYEOF
}

# verdict <log> <name> pass|fail: prints the result line; a run passes if it ran to the end without errors
verdict() {
   local log=$1 name=$2 want=$3 line
   line=$(sed -n 's/^.*(report note): \(RESULT .*\)$/\1/p' "$log" | tail -1)
   grep -E 'MISMATCH|error|TIMEOUT' "$log" | sed 's/^.*(report warning): //' | head -3 | sed 's/^/      /'
   if [ -z "$line" ]; then
      echo "  $name: did not finish"
      [ "$want" = fail ] || note_fail "$name"
      return
   fi
   echo "  $name: $line"
   case "$line" in
      *" ERRORS=0") [ "$want" = pass ] || note_fail "$name (mutant not detected)" ;;
      *)            [ "$want" = fail ] || note_fail "$name" ;;
   esac
}

# --------------------------------------------------------------------------------------------------
# 1. The real wrapper elaborates and runs with the cache size it ships
# --------------------------------------------------------------------------------------------------
echo "elaborating sw_cartridge_wrapper.vhd"
W=$BUILD/wrapper
if analyze "$W" "$HERE/avm_fifo_stand_in.vhd" \
      "$REPO/M2M/vhdl/cdc_stable.vhd" "$REPO/M2M/vhdl/cdc_slow.vhd" "$REPO/M2M/vhdl/tdp_ram.vhd" \
      "$REPO/M2M/vhdl/memory/avm_arbit.vhd" "$REPO/M2M/vhdl/qnice_csr.vhd" "$REPO/M2M/vhdl/qnice2hyperram.vhd" \
      "$REPO/CORE/vhdl/crt_parser.vhd" "$CACHER" "$REPO/CORE/vhdl/crt_loader.vhd" \
      "$REPO/CORE/vhdl/sw_cartridge_csr.vhd" "$WRAPPER" "$HERE/tb_wrapper_elab.vhd" &&
   elaborate "$W" tb_wrapper_elab; then
   # --max-stack-alloc=0: tdp_ram builds the initial value of a cache BRAM in one local variable
   sim "$W" tb_wrapper_elab "$W/wrapper.log" --max-stack-alloc=0
   verdict "$W/wrapper.log" wrapper pass
else
   note_fail "wrapper (analysis or elaboration)"
fi

# --------------------------------------------------------------------------------------------------
# 2. The cacher against the reference model, and two mutants that the bench must catch
# --------------------------------------------------------------------------------------------------
echo "building the cacher bench"
analyze "$BUILD/real" "$CTRL" "$CACHER" "$HERE/tb_crt_cacher.vhd" && elaborate "$BUILD/real" tb_crt_cacher ||
   note_fail "build"

python3 - "$CACHER" "$BUILD" <<'PYEOF' || note_fail "mutants"
import sys
src = open(sys.argv[1], encoding="utf-8").read()
mutants = {
    # the round-robin pointer of the ROML cache never advances
    "mut_pointer.vhd": ("<= next_cache_addr_lo + 1;", "<= next_cache_addr_lo;"),
    # a ROMH miss does not write its tag
    "mut_tag.vhd": ("cache_ram_hi(to_integer(next_cache_addr_hi)) <= bank_hi_i;", "null;"),
}
for name, (old, new) in mutants.items():
    if src.count(old) != 1:
        sys.exit("mutant %s: pattern not found exactly once in crt_cacher.vhd" % name)
    open(sys.argv[2] + "/" + name, "w", encoding="utf-8").write(src.replace(old, new))
PYEOF
for m in mut_pointer mut_tag; do
   if [ -f "$BUILD/$m.vhd" ]; then
      analyze "$BUILD/$m" "$CTRL" "$BUILD/$m.vhd" "$HERE/tb_crt_cacher.vhd" && elaborate "$BUILD/$m" tb_crt_cacher ||
         note_fail "build $m"
   fi
done

if [ -z "$FAILS" ]; then
   # <lib> <name> <generics>
   cat > "$BUILD/runs.txt" <<RUNS
real ship_easyflash_seed1 -gG_CACHE_SIZE=$SIZE -gG_EF=true -gG_SEED=1 -gG_STEPS=300
real ship_easyflash_seed2 -gG_CACHE_SIZE=$SIZE -gG_EF=true -gG_SEED=2 -gG_STEPS=300
real ship_independent_seed3 -gG_CACHE_SIZE=$SIZE -gG_EF=false -gG_SEED=3 -gG_STEPS=300
real ship_40banks_seed4 -gG_CACHE_SIZE=$SIZE -gG_EF=true -gG_SEED=4 -gG_STEPS=1500 -gG_NBANKS=40
real size3_easyflash_seed5 -gG_CACHE_SIZE=3 -gG_EF=true -gG_SEED=5 -gG_STEPS=300
real size3_independent_seed6 -gG_CACHE_SIZE=3 -gG_EF=false -gG_SEED=6 -gG_STEPS=300
mut_pointer mut_pointer -gG_CACHE_SIZE=3 -gG_EF=true -gG_SEED=1 -gG_STEPS=150
mut_tag mut_tag -gG_CACHE_SIZE=3 -gG_EF=true -gG_SEED=1 -gG_STEPS=150
RUNS
   echo "running $(wc -l < "$BUILD/runs.txt" | tr -d ' ') simulations, $JOBS at a time"
   running=0
   while read -r lib name generics; do
      # shellcheck disable=SC2086
      sim "$BUILD/$lib" tb_crt_cacher "$BUILD/$lib/$name.log" $generics &
      running=$((running + 1))
      if [ "$running" -ge "$JOBS" ]; then
         wait
         running=0
      fi
   done < "$BUILD/runs.txt"
   wait

   echo "cache size as shipped and the former size 3: all checks must pass"
   while read -r lib name generics; do
      case "$lib" in
         real) verdict "$BUILD/$lib/$name.log" "$name" pass ;;
      esac
   done < "$BUILD/runs.txt"
   echo "mutants: the bench must report errors"
   verdict "$BUILD/mut_pointer/mut_pointer.log" mut_pointer fail
   verdict "$BUILD/mut_tag/mut_tag.log" mut_tag fail
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
