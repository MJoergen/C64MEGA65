#!/usr/bin/env bash
# Runner for the NTSC video benches (issue #181, doc/dev-ntsc/NTSC-SPEC.md 10.2).
#
#   CORE/vhdl/test/tb_ntsc/run_w2.sh [modes|window|crop|osm|py|all]
#
#   modes   tb_video_modes: video_modes_pkg round trip, codes, video_mode_is_ntsc,
#           C_HDMI_720p_5994 (htotal x vtotal, CLK_KHZ)
#   window  tb_window_av: the real av_pipeline with the 10-entry mode vector, one
#           run per mode: digital_pipeline window, mode record, OSM shift and
#           scaling force, standard bit and crop window
#   crop    tb_crop_ntsc: real VIC-II + video_sync + crop, PAL and NTSC, all four
#           phases of the core video clock enable
#   osm     tb_osm_place: the real video_overlay (vga_osm, font ROM) on the NTSC
#           outputs, OSM scaling 0 .. 8, options menu and main screen
#   py      doc/dev-ntsc/tools/w2_checks.py: framework clock select, MMCM table of
#           CLK_SEL "110", OSM table of spec 7.3 (integer transcription)
#
# Environment: GHDL (default /usr/local/bin/ghdl), JOBS (default 2, max 3).
# Prints every bench output and a final "RESULT: PASS" or "RESULT: FAIL ..."
# line; exit status 0 only on PASS. Build products go to a temporary directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
RTL="$REPO/CORE/C64_MiSTerMEGA65/rtl"
TOOLS="$REPO/doc/dev-ntsc/tools"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
JOBS="${JOBS:-2}"; [ "$JOBS" -gt 3 ] && JOBS=3
WHAT="${1:-all}"
FLAGS=(--std=08 -frelaxed -fsynopsys)
AV="$REPO/M2M/vhdl/av_pipeline"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_w2.XXXXXX")"
[ -n "${KEEP:-}" ] && echo "build dir: $BUILD" || trap 'rm -rf "$BUILD"' EXIT
cd "$BUILD" || exit 2
T0=$(date +%s)

fail() { echo "RESULT: FAIL $*"; exit 1; }
want() { [ "$WHAT" = "$1" ] || [ "$WHAT" = "all" ]; }

case "$WHAT" in modes|window|crop|osm|py|all) ;; *) fail "unknown target '$WHAT'";; esac

# shared libraries: stubs and packages
"$GHDL" -a "${FLAGS[@]}" --work=unisim "$TOOLS/stubs/unisim_vcomponents.vhd" || fail "unisim stub"
"$GHDL" -a "${FLAGS[@]}" --work=xpm "$TOOLS/stubs/xpm_vcomponents.vhd" || fail "xpm stub"
PKGS=("$REPO/M2M/QNICE/vhdl/tools.vhd" "$AV/video_modes_pkg.vhd"
      "$REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd" "$REPO/CORE/vhdl/globals.vhd")

JOBFILE="$BUILD/jobs.txt"
: > "$JOBFILE"

if want modes; then
   "$GHDL" -a "${FLAGS[@]}" "$AV/video_modes_pkg.vhd" "$HERE/tb_video_modes.vhd" || fail "analysis tb_video_modes"
   "$GHDL" -e "${FLAGS[@]}" tb_video_modes || fail "elaboration tb_video_modes"
   echo "modes|tb_video_modes|" >> "$JOBFILE"
fi

if want window; then
   # av_pipeline and everything below it, with stand-ins for the parts that ghdl cannot
   # elaborate and that are not under test (see doc/dev-ntsc/tools/w2_standin.py)
   python3 "$TOOLS/w2_standin.py" "$AV/ascal.vhd" ascal "$BUILD/ascal_standin.vhd" --retype-in-ranged || fail "stand-in ascal"
   python3 "$TOOLS/w2_standin.py" "$AV/video_overlay.vhd" video_overlay "$BUILD/video_overlay_standin.vhd" \
      --retype vga_cfg_shift_i=integer || fail "stand-in video_overlay"
   python3 "$TOOLS/w2_standin.py" "$REPO/M2M/vhdl/controllers/HDMI/serialiser_10to1_selectio.vhd" \
      serialiser_10to1_selectio "$BUILD/serialiser_standin.vhd" || fail "stand-in serialiser"
   cat > "$BUILD/csync_standin.vhd" <<'EOF2'
-- stand-in for M2M/vhdl/controllers/MiSTer/csync.sv (SystemVerilog)
library ieee;
use ieee.std_logic_1164.all;
entity csync is
   port (clk : in std_logic; hsync : in std_logic; vsync : in std_logic; csync : out std_logic);
end entity csync;
architecture standin of csync is
begin
   csync <= hsync xor vsync;
end architecture standin;
EOF2
   AVFILES=("${PKGS[@]}" "$BUILD/csync_standin.vhd"
      "$REPO/M2M/vhdl/2port2clk_ram_byteenable.vhd" "$REPO/M2M/vhdl/2port2clk_ram.vhd" "$REPO/M2M/vhdl/tdp_ram.vhd"
      "$REPO/M2M/vhdl/hdmi_flicker_free.vhd" "$REPO/M2M/vhdl/cdc_pulse.vhd" "$REPO/M2M/vhdl/cdc_stable.vhd"
      "$REPO/M2M/vhdl/controllers/HDMI/sync_reg.vhd" "$REPO/M2M/vhdl/controllers/HDMI/hdmi_tx_encoder.vhd"
      "$REPO/M2M/vhdl/controllers/HDMI/vga_to_hdmi.vhd" "$REPO/M2M/vhdl/memory/avm_decrease.vhd"
      "$AV/clk_synthetic_enable.vhd" "$AV/video_counters.vhd" "$AV/crop.vhd"
      "$AV/digital_pipeline.vhd" "$AV/analog_pipeline.vhd" "$AV/av_pipeline.vhd"
      "$BUILD/ascal_standin.vhd" "$BUILD/video_overlay_standin.vhd" "$BUILD/serialiser_standin.vhd"
      "$HERE/tb_window_av.vhd")
   # Local copy of the xpm stub whose array synchronizer output starts at all ones instead
   # of 'U' / all zeros: an OSM scaling vector without a '1' makes first_nonzero_bit return 9,
   # outside the natural range 0 to 8 of the OSM ports (spec section 11, risk 13, kept as it
   # is). The QNICE side always drives one-hot values, so only the time-0 value is affected.
   python3 - "$TOOLS/stubs/xpm_vcomponents.vhd" "$BUILD/xpm_ones.vhd" <<'EOF2' || fail "xpm copy"
import sys
s = open(sys.argv[1]).read()
a = s.index("architecture behav of xpm_cdc_array_single is")
old = "signal chain : chain_t := (others => (others => '0'));"
b = s.index(old, a)
s = s[:b] + "signal chain : chain_t := (others => (others => '1'));" + s[b + len(old):]
e = s.index("entity xpm_cdc_array_single is")
old = "dest_out : out std_logic_vector(WIDTH-1 downto 0)"
b = s.index(old, e)
s = s[:b] + old + " := (others => '1')" + s[b + len(old):]
open(sys.argv[2], "w").write(s)
EOF2
   mkdir -p "$BUILD/av" && cd "$BUILD/av" || exit 2
   "$GHDL" -a "${FLAGS[@]}" --work=unisim "$TOOLS/stubs/unisim_vcomponents.vhd" || fail "unisim stub"
   "$GHDL" -a "${FLAGS[@]}" --work=xpm "$BUILD/xpm_ones.vhd" || fail "xpm stub"
   "$GHDL" -i "${FLAGS[@]}" "${AVFILES[@]}" || fail "import av_pipeline"
   "$GHDL" -m "${FLAGS[@]}" -Wno-binding -Wno-hide tb_window_av > "$BUILD/av_make.log" 2>&1 \
      || { cat "$BUILD/av_make.log"; fail "make tb_window_av"; }
   cd "$BUILD" || exit 2
   AVSIG="/tb_window_av/i_av"
   DPSIG="$AVSIG/i_digital_pipeline"
   {
      echo '$ version 1.1'
      echo "/tb_window_av/tb_phase"
      for sig in video_ntsc qnice_ntsc hdmi_osm_ntsc480 i_crop/x_min i_crop/x_max i_crop/y_min i_crop/y_max \
                 i_analog_pipeline/video_osm_cfg_scaling_i; do echo "$AVSIG/$sig"; done
      for sig in hdmi_hmin hdmi_hmax hdmi_vmin hdmi_vmax hdmi_htotal hdmi_vtotal hdmi_shift hdmi_osm_vshift \
                 audio_pcm_cts hdmi_osm_cfg_scaling_i i_vga_to_hdmi/vic i_vga_to_hdmi/aspect \
                 i_vga_to_hdmi/hs_pol i_vga_to_hdmi/vs_pol; do echo "$DPSIG/$sig"; done
   } > "$BUILD/window.opt"
fi

if want crop; then
   "$GHDL" -a "${FLAGS[@]}" -Wno-hide "$RTL/video_vicII_656x.vhd" "$RTL/video_sync.vhd" "$AV/crop.vhd" \
      "$HERE/tb_crop_ntsc.vhd" || fail "analysis tb_crop_ntsc"
   "$GHDL" -e "${FLAGS[@]}" tb_crop_ntsc || fail "elaboration tb_crop_ntsc"
   # phases 0 and 3 sample the VIC-II pixel one dot earlier than 1 and 2 (tb_crop_ntsc.vhd header)
   for std in false true; do
      for ph in 0 1 2 3; do
         ofs=0; { [ $ph -eq 0 ] || [ $ph -eq 3 ]; } && ofs=1
         echo "crop_ntsc_${std}_ph$ph|tb_crop_ntsc|-gG_NTSC=$std -gG_CE_PHASE=$ph -gG_PHASE_OFS=$ofs" >> "$JOBFILE"
      done
   done
fi

if want osm; then
   "$GHDL" -a "${FLAGS[@]}" "$REPO/M2M/vhdl/ram_init.vhd" "$AV/vga_recover_counters.vhd" "$AV/vga_osm.vhd" \
      "$AV/video_overlay.vhd" "$HERE/tb_osm_place.vhd" || fail "analysis tb_osm_place"
   "$GHDL" -e "${FLAGS[@]}" tb_osm_place || fail "elaboration tb_osm_place"
   FONT="$REPO/M2M/font/Anikki-16x16-m2m.rom"
   # name|exe|generics: output rows, 15 kHz, vertical shift, NTSC force, box (0 options, 1 main)
   for out in "vga31|-gG_ROWS=500 -gG_R15KHZ=false -gG_VSHIFT=0 -gG_FORCE=true" \
              "vga15|-gG_ROWS=250 -gG_R15KHZ=true -gG_VSHIFT=0 -gG_FORCE=true" \
              "hdmi480|-gG_ROWS=480 -gG_R15KHZ=false -gG_VSHIFT=24 -gG_FORCE=true" \
              "hdmi480_nochange|-gG_ROWS=480 -gG_R15KHZ=false -gG_VSHIFT=0 -gG_FORCE=false -gG_EXPECT_CLIP=true"; do
      n="${out%%|*}"; g="${out#*|}"
      for box in 0 1; do
         echo "osm_${n}_box$box|tb_osm_place|-gG_FONT_FILE=$FONT -gG_BOX=$box $g" >> "$JOBFILE"
      done
   done
fi

run_one() {
   IFS='|' read -r name exe gens <<< "$1"
   local s=$(date +%s)
   # shellcheck disable=SC2086
   ./"$exe" --ieee-asserts=disable $gens > "$BUILD/$name.log" 2>&1
   echo "runtime: $(( $(date +%s) - s )) s" >> "$BUILD/$name.log"
}
export -f run_one
export BUILD
[ -s "$JOBFILE" ] && xargs -P "$JOBS" -I{} bash -c 'run_one "$@"' _ {} < "$JOBFILE"

status=0
failed=""
while IFS='|' read -r name exe gens; do
   echo "=== $name ($exe $gens)"
   cat "$BUILD/$name.log"
   if ! grep -q '^RESULT: PASS' "$BUILD/$name.log"; then
      status=1; failed="$failed $name"
   fi
done < "$JOBFILE"

if want window; then
   echo "=== window (av/tb_window_av, VCD checked by w2_checks.py --window-vcd)"
   s=$(date +%s)
   ./av/tb_window_av --ieee-asserts=disable -gG_FONT_FILE="$REPO/M2M/font/Anikki-16x16-m2m.rom" \
      --read-wave-opt="$BUILD/window.opt" --vcd="$BUILD/window.vcd" > "$BUILD/window_sim.log" 2>&1
   cat "$BUILD/window_sim.log"
   if ! grep -q '^SIMULATION DONE' "$BUILD/window_sim.log" || grep -qi 'assertion\|error' "$BUILD/window_sim.log"; then
      status=1; failed="$failed window_sim"
   fi
   python3 "$TOOLS/w2_checks.py" "$REPO" --window-vcd "$BUILD/window.vcd" > "$BUILD/window_py.log" 2>&1
   cat "$BUILD/window_py.log"
   grep -q '^RESULT: PASS' "$BUILD/window_py.log" || { status=1; failed="$failed window_check"; }
   echo "runtime: $(( $(date +%s) - s )) s"
fi

if want py; then
   echo "=== w2_checks.py"
   if python3 "$TOOLS/w2_checks.py" "$REPO" > "$BUILD/py.log" 2>&1; then :; fi
   cat "$BUILD/py.log"
   grep -q '^RESULT: PASS' "$BUILD/py.log" || { status=1; failed="$failed w2_checks"; }
fi

echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL benches failed:$failed"
fi
exit $status
