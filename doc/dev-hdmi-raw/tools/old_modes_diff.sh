#!/usr/bin/env bash
# The ten video modes that existed before the raw modes: old tree versus working tree
# (issue #184, doc/dev-hdmi-raw/SPEC.md section 8).
#
#   doc/dev-hdmi-raw/tools/old_modes_diff.sh
#
# Exports the tree at BASE_REV (default 669e75d, the last revision without the raw
# modes; the submodules are taken from the working tree, they do not change), runs
# CORE/vhdl/test/tb_ntsc/run_w2.sh window in both trees and lets old_modes_diff.py
# compare the mode records, the framework decode and the two VCD files (see there).
#
# Environment: BASE_REV, GHDL (passed to run_w2.sh), KEEP (keep the build directory).
# Prints a final "RESULT: PASS" or "RESULT: FAIL ..." line; exit status 0 only on PASS.
# About 30 s.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../.." && pwd -P)"
BASE_REV="${BASE_REV:-669e75d}"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/old_modes_diff.XXXXXX")"
[ -n "${KEEP:-}" ] && echo "build dir: $BUILD" || trap 'rm -rf "$BUILD"' EXIT
fail() { echo "RESULT: FAIL $*"; exit 1; }

mkdir -p "$BUILD/old" "$BUILD/tmp"
git -C "$REPO" archive "$BASE_REV" | tar -x -C "$BUILD/old" || fail "git archive $BASE_REV"
for sub in M2M/QNICE CORE/C64_MiSTerMEGA65; do
   rmdir "$BUILD/old/$sub" 2>/dev/null
   ln -s "$REPO/$sub" "$BUILD/old/$sub" || fail "submodule link $sub"
done

for side in old new; do
   tree="$REPO"; [ "$side" = old ] && tree="$BUILD/old"
   ( cd "$tree" && TMPDIR="$BUILD/tmp" KEEP=1 JOBS="${JOBS:-2}" bash CORE/vhdl/test/tb_ntsc/run_w2.sh window ) \
      > "$BUILD/$side.log" 2>&1
   grep -q '^RESULT: PASS' "$BUILD/$side.log" || { cat "$BUILD/$side.log"; fail "run_w2.sh window ($side tree)"; }
   dir="$(sed -n 's/^build dir: //p' "$BUILD/$side.log")"
   [ -f "$dir/window.vcd" ] || fail "no VCD of the $side tree"
   cp "$dir/window.vcd" "$BUILD/$side.vcd"
done

python3 "$HERE/old_modes_diff.py" "$BUILD/old" "$REPO" "$BUILD/old.vcd" "$BUILD/new.vcd"
