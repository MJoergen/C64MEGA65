#!/usr/bin/env bash
# Runner for the NTSC benches (issue #181).
#
#   CORE/vhdl/test/tb_ntsc/run.sh [video|dividers|all] [--wide]
#
#   video     tb_video_sync_geometry: real VIC-II + video_sync, PAL and NTSC
#   dividers  tb_dividers: TOD and 1541 CE dividers at PAL and NTSC moduli
#
# Environment: GHDL (default /usr/local/bin/ghdl), JOBS (default 3, max 3),
#              PAL_HZ (31527778), NTSC_HZ (32727273), NTSC_GLOBALS_HZ (value of
#              CORE_CLK_SPEED_NTSC in CORE/vhdl/globals.vhd, read automatically),
#              FF_SLOW_HZ (31448993).
# Prints every bench output and a final "RESULT: PASS" or "RESULT: FAIL ..."
# line; exit status 0 only on PASS. Build products go to a temporary directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
RTL="$REPO/CORE/C64_MiSTerMEGA65/rtl"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
JOBS="${JOBS:-3}"; [ "$JOBS" -gt 3 ] && JOBS=3
PAL_HZ="${PAL_HZ:-31527778}"
NTSC_HZ="${NTSC_HZ:-32727273}"
FF_SLOW_HZ="${FF_SLOW_HZ:-31448993}"
NTSC_GLOBALS_HZ="${NTSC_GLOBALS_HZ:-$(sed -n 's/^constant CORE_CLK_SPEED_NTSC *: *natural *:= *\([0-9_]*\).*/\1/p' "$REPO/CORE/vhdl/globals.vhd" | tr -d _)}"
WHAT="${1:-all}"
WIDE=0; for a in "$@"; do [ "$a" = "--wide" ] && WIDE=1; done
FLAGS=(--std=08 -frelaxed -fsynopsys)

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_ntsc.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
cd "$BUILD" || exit 2
T0=$(date +%s)

fail() { echo "RESULT: FAIL $*"; exit 1; }

"$GHDL" -a "${FLAGS[@]}" "$RTL/video_vicII_656x.vhd" "$RTL/video_sync.vhd" \
   "$HERE/tb_video_sync_geometry.vhd" "$HERE/tb_dividers.vhd" || fail "ghdl analysis"
"$GHDL" -e "${FLAGS[@]}" tb_video_sync_geometry || fail "elaboration tb_video_sync_geometry"
"$GHDL" -e "${FLAGS[@]}" tb_dividers || fail "elaboration tb_dividers"

# job list: name|executable|generics...
JOBFILE="$BUILD/jobs.txt"
: > "$JOBFILE"
if [ "$WHAT" = "video" ] || [ "$WHAT" = "all" ]; then
   echo "video_pal|tb_video_sync_geometry|-gG_NTSC=false -gG_CLK_HZ=$PAL_HZ -gG_FRAMES=2" >> "$JOBFILE"
   echo "video_ntsc|tb_video_sync_geometry|-gG_NTSC=true -gG_CLK_HZ=$NTSC_HZ -gG_FRAMES=2" >> "$JOBFILE"
   if [ $WIDE -eq 1 ]; then
      echo "video_pal_wide|tb_video_sync_geometry|-gG_NTSC=false -gG_WIDE=true -gG_CLK_HZ=$PAL_HZ -gG_FRAMES=2" >> "$JOBFILE"
      echo "video_ntsc_wide|tb_video_sync_geometry|-gG_NTSC=true -gG_WIDE=true -gG_CLK_HZ=$NTSC_HZ -gG_FRAMES=2" >> "$JOBFILE"
   fi
fi
if [ "$WHAT" = "dividers" ] || [ "$WHAT" = "all" ]; then
   echo "div_pal|tb_dividers|-gG_NTSC=false -gG_MODULUS=$PAL_HZ" >> "$JOBFILE"
   echo "div_ntsc|tb_dividers|-gG_NTSC=true -gG_MODULUS=$NTSC_HZ" >> "$JOBFILE"
   if [ -n "$NTSC_GLOBALS_HZ" ] && [ "$NTSC_GLOBALS_HZ" != "$NTSC_HZ" ]; then
      echo "div_ntsc_globals|tb_dividers|-gG_NTSC=true -gG_MODULUS=$NTSC_GLOBALS_HZ" >> "$JOBFILE"
   fi
   # flicker-free: the clock runs at the slow MMCM output but the modulus stays nominal,
   # so TOD and 1541 slow down with the C64 by FF_SLOW_HZ / PAL_HZ (expected, by design)
   echo "div_pal_ffslow|tb_dividers|-gG_NTSC=false -gG_MODULUS=$PAL_HZ -gG_ACTUAL_HZ=$FF_SLOW_HZ -gG_EXPECT_SCALED=true" >> "$JOBFILE"
fi
[ -s "$JOBFILE" ] || fail "unknown target '$WHAT' (use video, dividers or all)"

run_one() {
   IFS='|' read -r name exe gens <<< "$1"
   local s=$(date +%s)
   # shellcheck disable=SC2086
   ./"$exe" --ieee-asserts=disable $gens > "$BUILD/$name.log" 2>&1
   echo "runtime: $(( $(date +%s) - s )) s" >> "$BUILD/$name.log"
}
export -f run_one
export BUILD
xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} < "$JOBFILE"

status=0
failed=""
while IFS='|' read -r name exe gens; do
   echo "=== $name ($exe $gens)"
   cat "$BUILD/$name.log"
   if ! grep -q '^RESULT: PASS' "$BUILD/$name.log"; then
      status=1; failed="$failed $name"
   fi
done < "$JOBFILE"
echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL benches failed:$failed"
fi
exit $status
