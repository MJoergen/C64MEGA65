#!/usr/bin/env bash
# Runner for the mode-change reset bench (issue #181).
#
#   CORE/vhdl/test/tb_ntsc/run_w3.sh
#
#   tb_mode_reset: mode_change_reset_proc, hard_reset_proc and cart_soft_reset
#                  of CORE/vhdl/main.vhd, run once with a PAL power-on (cases
#                  1 to 6) and once with c64_ntsc_i = '1' from the first cycle
#
# Before simulating, the copies of mode_change_reset_proc (with the mode_reset
# assignment), hard_reset_proc and the cart_soft_reset assignment inside
# tb_mode_reset.vhd are compared with CORE/vhdl/main.vhd (leading whitespace
# ignored); any difference fails the run.
#
# Environment: GHDL (default /usr/local/bin/ghdl).
# Prints every bench output and a final "RESULT: PASS" or "RESULT: FAIL ..."
# line; exit status 0 only on PASS. Build products go to a temporary directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
MAIN="$REPO/CORE/vhdl/main.vhd"
BENCH="$HERE/tb_mode_reset.vhd"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
FLAGS=(--std=08 -frelaxed)

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_ntsc_w3.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
T0=$(date +%s)

fail() { echo "RESULT: FAIL $*"; exit 1; }

# extract <file> <first-line-regex> <last-line-regex>: the block, leading whitespace removed
extract() {
   awk -v a="$2" -v b="$3" '$0 ~ a {p=1} p {sub(/^[ \t]+/, ""); print} p && $0 ~ b {exit}' "$1"
}

check_copy() {
   local name="$1" first="$2" last="$3"
   extract "$MAIN"  "$first" "$last" > "$BUILD/$name.main"
   extract "$BENCH" "$first" "$last" > "$BUILD/$name.bench"
   [ -s "$BUILD/$name.main" ] || fail "$name not found in main.vhd"
   if diff -u "$BUILD/$name.main" "$BUILD/$name.bench" > "$BUILD/$name.diff"; then
      echo "copy check $name: identical to main.vhd ($(wc -l < "$BUILD/$name.main" | tr -d ' ') lines)"
   else
      cat "$BUILD/$name.diff"
      fail "the copy of $name in tb_mode_reset.vhd differs from main.vhd"
   fi
}

check_copy mode_change_reset_proc '^ *-- Mode-change reset: soft-reset' "^ *mode_reset <= '1' when"
check_copy hard_reset_proc '^ *hard_reset_proc : process' '^ *end process hard_reset_proc;'
check_copy cart_soft_reset '^ *cart_soft_reset +<=' '^ *cart_soft_reset +<='

cd "$BUILD" || exit 2
"$GHDL" -a "${FLAGS[@]}" "$BENCH" || fail "ghdl analysis"
"$GHDL" -e "${FLAGS[@]}" tb_mode_reset || fail "elaboration tb_mode_reset"

status=0
failed=""
for run in "pal_power_on|-gG_POWER_ON_NTSC=false" "ntsc_power_on|-gG_POWER_ON_NTSC=true"; do
   IFS='|' read -r name gens <<< "$run"
   echo "=== $name (tb_mode_reset $gens)"
   s=$(date +%s)
   # shellcheck disable=SC2086
   ./tb_mode_reset --ieee-asserts=disable $gens > "$BUILD/$name.log" 2>&1
   cat "$BUILD/$name.log"
   echo "runtime: $(( $(date +%s) - s )) s"
   if ! grep -q '^RESULT: PASS' "$BUILD/$name.log"; then
      status=1; failed="$failed $name"
   fi
done
echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL benches failed:$failed"
fi
exit $status
