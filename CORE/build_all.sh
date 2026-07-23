#!/usr/bin/env bash
# Build the C64MEGA65 bitstreams of all four boards (R3, R4, R5, R6) one after
# another in Vivado batch mode, straight from the CORE-R?.xpr projects - made
# for overnight runs:
#
#   cd CORE
#   source /tools/Xilinx/Vivado/2025.1/settings64.sh   # or wherever Vivado is
#   nohup ./build_all.sh > build_all.out 2>&1 &
#
# The .xpr projects are the single source of truth (see build_bitstream.tcl);
# nothing here restates the file list, part or build strategy, so a
# command-line build is identical to what the Vivado IDE produces and the
# outputs land where make_release.py / load_bitstream.sh expect them
# (CORE-R?.runs/impl_1/mega65_r?.bit).
#
# Options:
#   ./build_all.sh              build R3 R4 R5 R6
#   ./build_all.sh R4 R6        build only the listed boards
#   JOBS=<n> ./build_all.sh     parallel Vivado jobs per run (default 4)
#   DEBUG=1  ./build_all.sh R6  insert ILA cores (mark_debug nets) via debug.tcl
#                               -- a debug build ignores the .xpr impl strategy,
#                                  so use it for bring-up, never for a release.

set -u
cd "$(dirname "$0")"

if ! command -v vivado >/dev/null 2>&1; then
    echo "ERROR: vivado is not on the PATH - source settings64.sh first." >&2
    exit 1
fi

# The QNICE assembler binaries live in a folder shared between macOS and the
# Ubuntu build VM, so whichever OS compiled them last wins. Rebuild them for
# this OS and assemble the firmware once, up front: a firmware problem aborts
# the run here, before the first multi-hour synthesis (synth_pre.tcl re-runs
# make_rom.sh during synthesis anyway).
./make_qasm.sh || exit 1
( cd m2m-rom && ./make_rom.sh ) || exit 1

if [ "$#" -gt 0 ]; then boards=("$@"); else boards=(R3 R4 R5 R6); fi
jobs="${JOBS:-4}"
dbg="${DEBUG:+debug}"      # non-empty DEBUG -> pass "debug" to build_bitstream.tcl
failed=0

for board in "${boards[@]}"; do
    echo "=== ${board}: build started $(date) ==="
    vivado -mode batch -notrace -source build_bitstream.tcl \
           -log "build_${board}.log" -journal "build_${board}.jou" \
           -tclargs "${board}" "${jobs}" ${dbg} || failed=1
done

echo
echo "=== Summary $(date) ==="
for board in "${boards[@]}"; do
    grep -h "^RESULT ${board}" "build_${board}.log" 2>/dev/null \
        || echo "RESULT ${board} FAILED - see build_${board}.log"
done
exit "${failed}"
