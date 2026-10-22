#!/usr/bin/env bash
# Differential ghdl analysis of VHDL files: base revision (default HEAD) versus
# working tree. See analyze.py for the method and the PASS/FAIL rules.
#
#   doc/dev-ntsc/tools/analyze.sh [--base REV] [-j N] [--selftest] [-v] file.vhd ...
#   doc/dev-ntsc/tools/analyze.sh --ntsc-set      # all files the NTSC work touches
#
# Prints one PASS/FAIL line per file with its runtime and a final
# "RESULT: PASS" or "RESULT: FAIL ..." line; exit status 0 only on PASS.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../.." && pwd -P)"
NTSC_SET=(
   CORE/vhdl/clk.vhd
   CORE/vhdl/mega65.vhd
   CORE/vhdl/main.vhd
   CORE/vhdl/globals.vhd
   CORE/vhdl/config.vhd
   M2M/vhdl/framework.vhd
   M2M/vhdl/av_pipeline/video_modes_pkg.vhd
   M2M/vhdl/av_pipeline/digital_pipeline.vhd
   M2M/vhdl/av_pipeline/video_overlay.vhd
   M2M/vhdl/av_pipeline/vga_osm.vhd
   M2M/vhdl/av_pipeline/crop.vhd
   M2M/vhdl/av_pipeline/analog_pipeline.vhd
   M2M/vhdl/controllers/HDMI/video_out_clock.vhd
   M2M/vhdl/hdmi_flicker_free.vhd
   CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd
)
args=()
for a in "$@"; do
   if [ "$a" = "--ntsc-set" ]; then
      for f in "${NTSC_SET[@]}"; do args+=("$REPO/$f"); done
   elif [ -e "$a" ] && [ "${a#/}" = "$a" ]; then
      args+=("$PWD/$a")          # relative to the caller, made absolute before the cd below
   else
      args+=("$a")               # options, absolute paths, or repo-relative paths
   fi
done
if [ ${#args[@]} -eq 0 ]; then
   sed -n '2,10p' "$0"
   exit 2
fi
cd "$REPO" || exit 2
exec python3 "$HERE/analyze.py" "${args[@]}"
