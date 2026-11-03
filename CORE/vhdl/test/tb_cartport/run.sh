#!/usr/bin/env bash
# Runner for the Expansion Port DMA/dot-clock benches (issue #259).
#
#   CORE/vhdl/test/tb_cartport/run.sh
#
# gen_tb.py splices the real process code out of CORE/vhdl/main.vhd
# (cart_dotclk_shape_proc, cart_dma_ba_proc, the DMA branch of
# handle_hardware_expansion_proc) and out of fpga64_sid_iec.vhd (sysCycle
# enumeration, pixel-enable and PHI2 processes, the cpuHasBus grant condition)
# into two self-checking benches:
#
#   tb_dotclk   the cartridge dot clock is a 50 % square wave and both PHI2
#               edges are one clk_main_i tick away from the nearest DOTCLK edge
#   tb_dma_ba   grace cycle and BA recharge under badline and sprite stalls,
#               reads, implausible addresses, repeated stalls, /DMA release
#
# Environment: GHDL (default /usr/local/bin/ghdl). Prints "RESULT: PASS" or
# "RESULT: FAIL ..."; exit status 0 only on PASS. Build products are temporary.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
FLAGS=(--std=08 -frelaxed)
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_cartport.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
fail() { echo "RESULT: FAIL $*"; exit 1; }
python3 -I "$HERE/gen_tb.py" "$REPO/CORE/vhdl/main.vhd" "$REPO/CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd" "$BUILD" || fail "bench generation"
cd "$BUILD" || exit 2
for tb in tb_dotclk tb_dma_ba; do
  "$GHDL" -a "${FLAGS[@]}" "$tb.vhd" || fail "ghdl analysis $tb"
  "$GHDL" -e "${FLAGS[@]}" "$tb" || fail "elaboration $tb"
  "./$tb" > "$tb.log" 2>&1
  sed -E 's/^[^:]*:[0-9]+:[0-9]+:@[0-9a-z.]+:\(report (note|error)\): //' "$tb.log"
  grep -q "ALL CHECKS PASSED" "$tb.log" || fail "$tb"
done
echo "RESULT: PASS"
