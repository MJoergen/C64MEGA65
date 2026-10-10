#!/usr/bin/env bash
# Build the C64MEGA65 bitstreams of all four boards (R3, R4, R5, R6) one after
# another in Vivado batch mode, straight from the CORE-R?.xpr projects - made
# for overnight runs.
#
# Usage: ./build_all.sh [--no-reroll] [--help] [board ...]
#
#   cd CORE
#   source /tools/Xilinx/Vivado/2025.1/settings64.sh   # or wherever Vivado is
#   nohup ./build_all.sh > build_all.out 2>&1 &
#
# The .xpr projects are the single source of truth (see build_bitstream.tcl);
# nothing here restates the file list, part or build strategy, and the outputs
# land where make_release.py / load_bitstream.sh expect them
# (CORE-R?.runs/impl_1/mega65_r?.bit).
#
# Boards: optionally a subset, e.g. "./build_all.sh R4 R6"; the names are
# case-insensitive. Without boards, all four are built.
#
# Re-roll: once all boards are built, every board that only missed timing is
# implemented again with other placer and router directives (see
# reroll_bitstream.tcl and doc/timing_closure.md), starting from the
# checkpoints of its own build, until an attempt meets timing. The winner
# replaces the failed CORE-<board>.runs/impl_1/mega65_<board>.bit, so every
# tool that expects the bitstream there keeps working, and the summary lists
# all attempts. A re-rolled bitstream is the one exception to "identical to
# what the Vivado IDE produces": its placement and routing come from the
# winning directives, which CORE-<board>.runs/impl_1/mega65_<board>_reroll.txt
# records.
#
# Options:
#   --no-reroll  skip the re-roll pass, a board that missed timing stays failed
#   --help       print this text
#
# Environment:
#   JOBS=<n>              parallel Vivado jobs per run (default 4)
#   DEBUG=1               insert ILA cores (mark_debug nets) via debug.tcl
#                         -- a debug build ignores the .xpr impl strategy and
#                            is never re-rolled, so use it for bring-up, never
#                            for a release
#   REROLL_MAX_MISS=<ns>  largest setup or hold miss that gets re-rolled
#                         (default 0.3); a bigger miss is a real timing problem

set -u
cd "$(dirname "$0")"

# --help prints the comment block at the top of this file.
usage() { sed -n '2,/^[^#]/ s/^# \{0,1\}//p' "$(basename "$0")"; }

boards=()
reroll=1
for arg in "$@"; do
    case "${arg}" in
        -h|--help)   usage; exit 0 ;;
        --no-reroll) reroll=0 ;;
        -*)          echo "ERROR: unknown option '${arg}' - see $0 --help." >&2; exit 1 ;;
        *)           boards+=("${arg}") ;;
    esac
done
[ "${#boards[@]}" -gt 0 ] || boards=(R3 R4 R5 R6)

if ! command -v vivado >/dev/null 2>&1; then
    echo "ERROR: vivado is not on the PATH - source settings64.sh first." >&2
    exit 1
fi

# Board names are case-insensitive on the command line ("R4" and "r4" both
# work), but build_bitstream.tcl only recognizes the upper-case R3|R4|R5|R6
# and the CORE-R?.xpr project files are upper-case on case-sensitive
# filesystems, so we normalize them here. Unknown boards are rejected up front
# (checked against the actual .xpr files) instead of failing deep inside
# Vivado.
for i in "${!boards[@]}"; do
    boards[$i]=$(printf '%s' "${boards[$i]}" | tr '[:lower:]' '[:upper:]')
    if [ ! -f "CORE-${boards[$i]}.xpr" ]; then
        echo "ERROR: unknown board '${boards[$i]}' - no CORE-${boards[$i]}.xpr in $(pwd)." >&2
        echo "       Available: $(ls CORE-R*.xpr 2>/dev/null | sed 's/^CORE-\(.*\)\.xpr$/\1/' | tr '\n' ' ')" >&2
        exit 1
    fi
done

# The QNICE assembler binaries live in a folder shared between macOS and the
# Ubuntu build VM, so whichever OS compiled them last wins. Rebuild them for
# this OS and assemble the firmware once, up front: a firmware problem aborts
# the run here, before the first multi-hour synthesis (synth_pre.tcl re-runs
# make_rom.sh during synthesis anyway).
./make_qasm.sh || exit 1
( cd m2m-rom && ./make_rom.sh ) || exit 1

jobs="${JOBS:-4}"
dbg="${DEBUG:+debug}"      # non-empty DEBUG -> pass "debug" to build_bitstream.tcl
max_miss="${REROLL_MAX_MISS:-0.3}"

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# The last "RESULT <board> ..." line of a Vivado log, empty if there is none.
result_of() { grep -h "^RESULT $1 " "$2" 2>/dev/null | tail -n 1; }

for board in "${boards[@]}"; do
    # Re-roll files from an earlier run describe an older bitstream.
    rm -f "CORE-${board}.runs/impl_1/mega65_$(lower "${board}")_reroll"*
    echo "=== ${board}: build started $(date) ==="
    vivado -mode batch -notrace -source build_bitstream.tcl \
           -log "build_${board}.log" -journal "build_${board}.jou" \
           -tclargs "${board}" "${jobs}" ${dbg}
done

# Second pass: re-roll the boards that only missed timing.
note=()
rerolled=()
for i in "${!boards[@]}"; do
    board=${boards[$i]}
    result=$(result_of "${board}" "build_${board}.log")
    case "${result}" in
        "RESULT ${board} TIMING-FAILED "*) ;;
        *) continue ;;
    esac
    if [ "${reroll}" = "0" ]; then
        note[$i]="not re-rolled: --no-reroll"
        continue
    fi
    wns=$(sed -n 's/.* WNS=\([^ ]*\).*/\1/p' <<< "${result}")
    whs=$(sed -n 's/.* WHS=\([^ ]*\).*/\1/p' <<< "${result}")
    if ! awk -v w="${wns}" -v h="${whs}" -v m="${max_miss}" \
            'BEGIN { exit !(w != "" && h != "" && w + 0 >= -m && h + 0 >= -m) }'; then
        note[$i]="not re-rolled: the miss is larger than REROLL_MAX_MISS=${max_miss} ns"
        continue
    fi
    # The re-roll continues from the checkpoints of this very build, so they
    # must be newer than the journal that its Vivado session started with.
    run="CORE-${board}.runs/impl_1"
    b=$(lower "${board}")
    stale=""
    for f in "${run}/mega65_${b}_opt.dcp" "${run}/mega65_${b}_physopt.dcp" \
             "${run}/mega65_${b}_postroute_physopt.dcp"; do
        [ "${f}" -nt "build_${board}.jou" ] || stale="${f}"
    done
    if [ -n "${stale}" ]; then
        note[$i]="not re-rolled: ${stale} is missing or older than this build"
        continue
    fi
    echo "=== ${board}: re-roll started $(date) ==="
    vivado -mode batch -notrace -source reroll_bitstream.tcl \
           -log "build_${board}_reroll.log" -journal "build_${board}_reroll.jou" \
           -tclargs "${board}" "${jobs}" "${wns}" "${whs}"
    rerolled[$i]=1
done

echo
echo "=== Summary $(date) ==="
failed=0
for i in "${!boards[@]}"; do
    board=${boards[$i]}
    first=$(result_of "${board}" "build_${board}.log")
    [ -n "${first}" ] || first="RESULT ${board} FAILED - see build_${board}.log"
    final="${first}"
    if [ -n "${rerolled[$i]:-}" ]; then
        final=$(result_of "${board}" "build_${board}_reroll.log")
        [ -n "${final}" ] || final="RESULT ${board} REROLL-FAILED - see build_${board}_reroll.log"
    fi
    echo "${final}"
    if [ -n "${rerolled[$i]:-}" ]; then
        echo "    first pass: ${first#"RESULT ${board} "}"
        grep -h -e "^REROLL ${board} " -e "^GATE ${board}:" "build_${board}_reroll.log" 2>/dev/null \
            | sed 's/^/    /'
    fi
    if [ -n "${note[$i]:-}" ]; then echo "    ${note[$i]}"; fi
    case "${final}" in
        "RESULT ${board} OK "*|"RESULT ${board} OK-DEBUG "*) ;;
        *) failed=1 ;;
    esac
done
exit "${failed}"
