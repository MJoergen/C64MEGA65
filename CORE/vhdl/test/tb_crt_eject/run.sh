#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Bench for unloading ("ejecting") a simulated cartridge (GitHub issue #153), see README.md
#
#   CORE/vhdl/test/tb_crt_eject/run.sh [--keep]
#
# 1. Runs tb_crt_eject.vhd (the real sw_cartridge_wrapper.vhd and cartridge.vhd) with four seeds of
#    the random HyperRAM wait states.
# 2. Runs it against mutants of the eject path that the bench must catch.
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3. Runtime about 1 minute.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"

KEEP=0
for a in "$@"; do
   case "$a" in
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_crt_eject.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }

# the files of the device under test, in analysis order; the mutants replace some of them
SRC_FIFO=$HERE/avm_fifo_stand_in.vhd
SRC_LIB="$REPO/M2M/vhdl/cdc_stable.vhd $REPO/M2M/vhdl/cdc_slow.vhd $REPO/M2M/vhdl/tdp_ram.vhd
         $REPO/M2M/vhdl/memory/avm_arbit.vhd $REPO/M2M/vhdl/qnice_csr.vhd $REPO/M2M/vhdl/qnice2hyperram.vhd"
PARSER=$REPO/CORE/vhdl/crt_parser.vhd
CACHER=$REPO/CORE/vhdl/crt_cacher.vhd
LOADER=$REPO/CORE/vhdl/crt_loader.vhd
CSR=$REPO/CORE/vhdl/sw_cartridge_csr.vhd
WRAPPER=$REPO/CORE/vhdl/sw_cartridge_wrapper.vhd
CART=$REPO/CORE/vhdl/cartridge.vhd
TB=$HERE/tb_crt_eject.vhd

# build <dir> <parser> <csr> <wrapper> <cartridge>: analyze and elaborate one variant
build() {
   local dir=$1
   mkdir -p "$dir"
   # shellcheck disable=SC2086
   "$GHDL" -a $GF --workdir="$dir" "$SRC_FIFO" $SRC_LIB "$2" "$CACHER" "$LOADER" "$3" "$4" "$5" "$TB" \
      > "$dir/build.log" 2>&1 &&
   ( cd "$dir" && "$GHDL" -e $GF --workdir=. tb_crt_eject ) >> "$dir/build.log" 2>&1 ||
      { sed 's/^/    /' "$dir/build.log" | head -20; return 1; }
}

# sim <dir> <seed>: run one simulation (5 min timeout); prints the RESULT line or "did not finish"
sim() {
   python3 - "$GHDL" "$1" "$2" <<'PYEOF'
import re, subprocess, sys
ghdl, d, seed = sys.argv[1:4]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", "tb_crt_eject",
                        "--max-stack-alloc=0", "-gG_SEED=" + seed],
                       cwd=d, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=300)
    out = r.stdout + r.stderr
except subprocess.TimeoutExpired:
    out = "TIMEOUT\n"
open(d + "/sim_" + seed + ".log", "w").write(out)
m = re.findall(r"RESULT ERRORS=(\d+)", out)
first = [l.split("): ", 1)[-1] for l in out.splitlines() if "  ERROR " in l][:2]
print((("ERRORS=" + m[-1]) if m else "did not finish") + ("  [" + " | ".join(first) + "]" if first else ""))
PYEOF
}

# --------------------------------------------------------------------------------------------------
# 1. The real RTL
# --------------------------------------------------------------------------------------------------
echo "tb_crt_eject: real RTL"
if build "$BUILD/real" "$PARSER" "$CSR" "$WRAPPER" "$CART"; then
   for seed in 44257 1 777 31337; do
      res=$(sim "$BUILD/real" $seed)
      echo "  seed $seed: $res"
      case "$res" in
         "ERRORS=0") ;;
         *) note_fail "real RTL, seed $seed" ;;
      esac
   done
else
   note_fail "build of the real RTL"
fi

# --------------------------------------------------------------------------------------------------
# 2. Mutants: each one must make the bench fail
# --------------------------------------------------------------------------------------------------
# mutant <name> <file to mutate: cart|parser|csr|wrapper> <python expression old> <new>
mutant() {
   local name=$1 which=$2 old=$3 new=$4 dir=$BUILD/m_$1 p=$PARSER c=$CSR w=$WRAPPER k=$CART src
   mkdir -p "$dir"
   case "$which" in
      cart)    src=$CART;    k=$dir/cartridge.vhd ;;
      parser)  src=$PARSER;  p=$dir/crt_parser.vhd ;;
      csr)     src=$CSR;     c=$dir/sw_cartridge_csr.vhd ;;
      wrapper) src=$WRAPPER; w=$dir/sw_cartridge_wrapper.vhd ;;
   esac
   python3 - "$src" "$dir/$(basename "$src")" "$old" "$new" <<'PYEOF' || { note_fail "mutant $name (not applicable)"; return; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit("pattern found %d times" % s.count(old))
open(dst, "w").write(s.replace(old, new))
PYEOF
   if ! build "$dir" "$p" "$c" "$w" "$k"; then
      note_fail "mutant $name (does not build)"
      return
   fi
   res=$(sim "$dir" 44257)
   echo "  mutant $name: $res"
   case "$res" in
      "ERRORS=0") note_fail "mutant $name not detected" ;;
   esac
}

echo "tb_crt_eject: mutants"
mutant no_clear    parser  "if req_eject_i = '1' and req_start_i = '0' and"   "if false and"
mutant keep_id     parser  "            cart_id_o    <= (others => '0');"      ""
mutant keep_game   parser  "            cart_game_o  <= (others => '1');"      ""
mutant keep_size   parser  "            cart_size_o  <= (others => '0');"      ""
mutant eject_ldng  csr     "qnice_req_eject_o <= '1' when qnice_req_status = C_CSR_REQ_IDLE else '0';" \
                           "qnice_req_eject_o <= '1' when qnice_req_status /= C_CSR_REQ_OK else '0';"
mutant roml_we_kept cart   "        roml_we_o    <= '0'; -- only Action Replay and Super Snapshot V5 write to ROML" ""
mutant unwired     wrapper "         src_data_i(24)           => qnice_req_eject," \
                           "         src_data_i(24)           => '0',"

if [ $KEEP = 1 ]; then echo "build directory kept: $BUILD"; else rm -rf "$BUILD"; fi
if [ -z "$FAILS" ]; then
   echo "RESULT: PASS"
   exit 0
fi
echo "RESULT: FAIL$FAILS"
exit 1
