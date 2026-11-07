#!/usr/bin/env bash
# Runner for the VIC-II + hardware-DMA bench (issue #259).
#
#   CORE/vhdl/test/tb_vicdma/run.sh
#
# gen_tb.py builds the benches from the real RTL: the whole fpga64_sid_iec.vhd (CPU, SID, CIAs and the
# RGB LUT replaced by stubs), the real video_vicii_656x, fpga64_buslogic, spram (color RAM) and
# dualport_2clk_ram/tdp_ram (C64 RAM), and the Expansion Port processes of main.vhd spliced verbatim.
# A behavioral MOS 8726 REC performs verifies and fetches while badlines and sprites stall the bus.
#
#   ref    no DMA (reference trace)                         C_CART_DMA_GRACE_RD_CYCLES = 3
#   fix    REC transfers, data pattern 0..255               = 3 (main.vhd as written)
#   fixff  REC transfers, uniform $FF                       = 3
#   a24    REC transfers, data pattern 0..255               = 1 (A24 behavior, text substitution)
#   a24ff  REC transfers, uniform $FF                       = 1
#   neg    negative control, one grace cycle too many       = 4 (must change the display)
#   late   informational: REC resumes one cycle late        = 3
#
# eval.py checks C1..C6 (see its output). Environment: GHDL (default /usr/local/bin/ghdl), JOBS
# (parallel simulations, default 4). Prints "RESULT: PASS" or "RESULT: FAIL ..."; exit status 0 only
# on PASS. Build products are temporary; KEEP=1 keeps them and prints the directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
JOBS="${JOBS:-4}"
# -fsynopsys: the MiSTer files use ieee.std_logic_unsigned
FLAGS=(--std=08 -frelaxed -fsynopsys)
RUNOPTS=(--max-stack-alloc=0 --ieee-asserts=disable)
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_vicdma.XXXXXX")"
if [ "${KEEP:-0}" = 1 ]; then echo "build directory: $BUILD"; else trap 'rm -rf "$BUILD"' EXIT; fi
fail() { echo "RESULT: FAIL $*"; exit 1; }
RTL="$REPO/CORE/C64_MiSTerMEGA65/rtl"
python3 -I "$HERE/gen_tb.py" "$REPO/CORE/vhdl/main.vhd" "$RTL/fpga64_sid_iec.vhd" "$BUILD" || fail "bench generation"
cd "$BUILD" || exit 2
for f in "$RTL/spram.vhd" "$RTL/dprom.vhd" "$REPO/M2M/vhdl/tdp_ram.vhd" "$REPO/M2M/vhdl/2port2clk_ram.vhd" \
         "$RTL/fpga64_buslogic.vhd" "$RTL/video_vicII_656x.vhd" tb_vicdma_pkg.vhd fpga64_sid_iec_tb.vhd \
         tb_vicdma_g3.vhd tb_vicdma_g1.vhd tb_vicdma_g4.vhd; do
  "$GHDL" -a "${FLAGS[@]}" "$f" > analysis.log 2>&1 || { cat analysis.log; fail "ghdl analysis $(basename "$f")"; }
done
for g in 3 1 4; do
  "$GHDL" -e "${FLAGS[@]}" "tb_vicdma_g$g" > elab.log 2>&1 || { cat elab.log; fail "elaboration tb_vicdma_g$g"; }
done
run() { # tag entity generics...
  local tag="$1" ent="$2"; shift 2
  "./$ent" "${RUNOPTS[@]}" "-gTAG=$tag" "$@" > "$tag.log" 2>&1
  echo "  simulated $tag ($ent $*)"
}
echo "simulating (JOBS=$JOBS, about 45 s per run) ..."
RUNS=(
  "ref tb_vicdma_g3 -gDMA_ON=false"
  "fix tb_vicdma_g3 -gDMA_ON=true"
  "fixff tb_vicdma_g3 -gDMA_ON=true -gRAM_FILE=ram_ff.hex -gFF_DATA=true"
  "a24 tb_vicdma_g1 -gDMA_ON=true"
  "a24ff tb_vicdma_g1 -gDMA_ON=true -gRAM_FILE=ram_ff.hex -gFF_DATA=true"
  "neg tb_vicdma_g4 -gDMA_ON=true"
  "late tb_vicdma_g3 -gDMA_ON=true -gLATE_RESUME=true"
)
i=0
for r in "${RUNS[@]}"; do
  # shellcheck disable=SC2086
  run $r &
  i=$((i + 1)); if [ $((i % JOBS)) -eq 0 ]; then wait; fi
done
wait
grep -h -E "C2VIOL|UNSERVED|RAMDIFF|MIS " ./*.log | sed -E 's/^[^:]*:[0-9]+:[0-9]+:@[0-9a-z.]+:\(report (note|error)\): //' | head -40
python3 -I "$HERE/eval.py" "$BUILD"
