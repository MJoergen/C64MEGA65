#!/usr/bin/env bash
# Runner of the benches of the HDMI pixel clock and of the audio clock
# regeneration of the raw modes (issue #184, doc/dev-hdmi-raw/SPEC.md 4.2 and 6).
#
#   CORE/vhdl/test/tb_hdmi_raw_clock/run.sh [drp|cts|packet|all]
#
#   drp  tb_hdmi_raw_clock: the DRP loader of video_out_clock.vhd with the 4-bit
#        selector against the same file before the selector was widened. The
#        bench is built twice with the models of models.vhd: once with
#        M2M/vhdl/controllers/HDMI/video_out_clock.vhd of the working tree and once
#        with the file at BASE_REV (default 669e75d, the last revision with the
#        3-bit selector); check_drp.py compares the logs (see there). About 5 s.
#   cts  tb_hdmi_raw_cts: the real digital_pipeline.vhd, 1.5 s of audio time
#        through all 16 modes; check_cts.py checks the CTS of every packet (see
#        there). About 1 to 2 minutes.
#   packet tb_hdmi_raw_cts with G_PACKET: the HDMI clock runs, the scaler is the output
#        timing generator of tb_hdmi_raw_wiring/ascal_timing.vhd and video_overlay passes
#        the syncs through (video_overlay_passthrough.vhd), so the real vga_to_hdmi sends
#        its packets; check_cts.py --packet checks the CTS of 68 ACR packets as
#        vga_to_hdmi sends them. About 2 minutes.
#
# Environment: GHDL (default /usr/local/bin/ghdl), BASE_REV, KEEP (keep the
# build directory). Prints the checker output and a final "RESULT: PASS" or
# "RESULT: FAIL ..." line; exit status 0 only on PASS.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
BASE_REV="${BASE_REV:-669e75d}"
FLAGS=(--std=08 -frelaxed -fsynopsys)
VOC=M2M/vhdl/controllers/HDMI/video_out_clock.vhd
WHAT="${1:-all}"
TOOLS="$REPO/doc/dev-ntsc/tools"
AV="$REPO/M2M/vhdl/av_pipeline"

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_hdmi_raw_clock.XXXXXX")"
[ -n "${KEEP:-}" ] && echo "build dir: $BUILD" || trap 'rm -rf "$BUILD"' EXIT
T0=$(date +%s)

fail() { echo "RESULT: FAIL $*"; exit 1; }
want() { [ "$WHAT" = "$1" ] || [ "$WHAT" = "all" ]; }

case "$WHAT" in drp|cts|packet|all) ;; *) fail "unknown target '$WHAT'";; esac
status=0

if want drp; then
   echo "=== drp (tb_hdmi_raw_clock)"
   git -C "$REPO" show "$BASE_REV:$VOC" > "$BUILD/video_out_clock_old.vhd" || fail "git show $BASE_REV:$VOC"
   grep -q 'sel *: *in *std_logic_vector(2 downto 0)' "$BUILD/video_out_clock_old.vhd" \
      || fail "$VOC at $BASE_REV does not have the 3-bit selector"
   cp "$REPO/$VOC" "$BUILD/video_out_clock_new.vhd"

   # one library per version; the models go into unisim, where the component declarations of
   # the analysis stub are, so that the instances of video_out_clock bind to them by default
   for v in old new; do
      mkdir -p "$BUILD/$v" && cd "$BUILD/$v" || exit 2
      w=4; [ "$v" = old ] && w=3
      "$GHDL" -a "${FLAGS[@]}" --work=unisim "$REPO/doc/dev-ntsc/tools/stubs/unisim_vcomponents.vhd" \
         "$HERE/models.vhd" || fail "analysis of the models ($v)"
      "$GHDL" -a "${FLAGS[@]}" "$REPO/M2M/vhdl/cdc_stable.vhd" "$BUILD/video_out_clock_$v.vhd" \
         "$HERE/tb_hdmi_raw_clock.vhd" || fail "analysis ($v)"
      "$GHDL" -e "${FLAGS[@]}" tb_hdmi_raw_clock || fail "elaboration ($v)"
      ./tb_hdmi_raw_clock --ieee-asserts=disable -gG_SEL_WIDTH=$w > "$BUILD/$v.log" 2>&1 \
         || { tail -20 "$BUILD/$v.log"; fail "simulation ($v)"; }
   done

   python3 "$HERE/check_drp.py" "$BUILD/old.log" "$BUILD/video_out_clock_old.vhd" \
      "$BUILD/new.log" "$BUILD/video_out_clock_new.vhd" "$REPO" > "$BUILD/check.log" 2>&1
   cat "$BUILD/check.log"
   grep -q '^RESULT: PASS' "$BUILD/check.log" || status=1
fi

if want cts; then
   echo "=== cts (tb_hdmi_raw_cts)"
   s=$(date +%s)
   # digital_pipeline and everything below it, with stand-ins for the parts that ghdl cannot
   # elaborate and that are not under test (see doc/dev-ntsc/tools/w2_standin.py)
   mkdir -p "$BUILD/cts" && cd "$BUILD/cts" || exit 2
   python3 "$TOOLS/w2_standin.py" "$AV/ascal.vhd" ascal "$BUILD/cts/ascal_standin.vhd" --retype-in-ranged \
      > /dev/null || fail "stand-in ascal"
   python3 "$TOOLS/w2_standin.py" "$AV/video_overlay.vhd" video_overlay "$BUILD/cts/video_overlay_standin.vhd" \
      --retype vga_cfg_shift_i=integer > /dev/null || fail "stand-in video_overlay"
   python3 "$TOOLS/w2_standin.py" "$REPO/M2M/vhdl/controllers/HDMI/serialiser_10to1_selectio.vhd" \
      serialiser_10to1_selectio "$BUILD/cts/serialiser_standin.vhd" > /dev/null || fail "stand-in serialiser"
   "$GHDL" -a "${FLAGS[@]}" --work=unisim "$TOOLS/stubs/unisim_vcomponents.vhd" || fail "unisim stub"
   "$GHDL" -a "${FLAGS[@]}" --work=xpm "$TOOLS/stubs/xpm_vcomponents.vhd" || fail "xpm stub"
   "$GHDL" -i "${FLAGS[@]}" "$REPO/M2M/QNICE/vhdl/tools.vhd" "$AV/video_modes_pkg.vhd" \
      "$REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd" "$REPO/M2M/vhdl/controllers/HDMI/sync_reg.vhd" \
      "$REPO/M2M/vhdl/controllers/HDMI/hdmi_tx_encoder.vhd" "$REPO/M2M/vhdl/controllers/HDMI/vga_to_hdmi.vhd" \
      "$REPO/M2M/vhdl/memory/avm_decrease.vhd" "$AV/clk_synthetic_enable.vhd" "$AV/digital_pipeline.vhd" \
      "$BUILD/cts/ascal_standin.vhd" "$BUILD/cts/video_overlay_standin.vhd" "$BUILD/cts/serialiser_standin.vhd" \
      "$AV/hdmi_genlock.vhd" "$HERE/tb_hdmi_raw_cts.vhd" || fail "import tb_hdmi_raw_cts"
   "$GHDL" -m "${FLAGS[@]}" -Wno-binding -Wno-hide tb_hdmi_raw_cts > "$BUILD/cts_make.log" 2>&1 \
      || { cat "$BUILD/cts_make.log"; fail "make tb_hdmi_raw_cts"; }
   printf '%s\n' '$ version 1.1' /tb_hdmi_raw_cts/tb_phase /tb_hdmi_raw_cts/i_dp/audio_pcm_acr \
      /tb_hdmi_raw_cts/i_dp/audio_pcm_cts > "$BUILD/cts.opt"
   ./tb_hdmi_raw_cts --ieee-asserts=disable -gG_FONT_FILE="$REPO/M2M/font/Anikki-16x16-m2m.rom" \
      --read-wave-opt="$BUILD/cts.opt" --vcd="$BUILD/cts.vcd" > "$BUILD/cts_sim.log" 2>&1
   cat "$BUILD/cts_sim.log"
   if ! grep -q '^SIMULATION DONE' "$BUILD/cts_sim.log" || grep -qi 'assertion\|error' "$BUILD/cts_sim.log"; then
      status=1
   fi
   python3 "$HERE/check_cts.py" "$BUILD/cts.vcd" "$REPO" > "$BUILD/cts_check.log" 2>&1
   cat "$BUILD/cts_check.log"
   grep -q '^RESULT: PASS' "$BUILD/cts_check.log" || status=1
   echo "runtime: $(( $(date +%s) - s )) s"
fi

if want packet; then
   echo "=== packet (tb_hdmi_raw_cts, G_PACKET)"
   s=$(date +%s)
   P="$BUILD/packet"
   mkdir -p "$P" && cd "$P" || exit 2
   WIRING="$REPO/CORE/vhdl/test/tb_hdmi_raw_wiring"
   python3 "$TOOLS/w2_standin.py" "$AV/ascal.vhd" ascal "$P/ascal_ent.vhd" --retype-in-ranged > /dev/null \
      || fail "stand-in ascal"
   # the entity declaration of the real ascal with the output timing generator as architecture
   python3 - "$P/ascal_ent.vhd" "$WIRING/ascal_timing.vhd" "$P/ascal_standin.vhd" <<'EOF2' || fail "ascal stand-in"
import sys
ent = open(sys.argv[1]).read()
ent = ent[:ent.index("architecture standin of ascal is")]
open(sys.argv[3], "w").write(ent + "\n" + open(sys.argv[2]).read())
EOF2
   python3 "$TOOLS/w2_standin.py" "$REPO/M2M/vhdl/controllers/HDMI/serialiser_10to1_selectio.vhd" \
      serialiser_10to1_selectio "$P/serialiser_standin.vhd" > /dev/null || fail "stand-in serialiser"
   python3 "$TOOLS/w2_standin.py" "$AV/video_overlay.vhd" video_overlay "$P/video_overlay_ent.vhd" \
      --retype vga_cfg_shift_i=integer > /dev/null || fail "stand-in video_overlay"
   python3 - "$P/video_overlay_ent.vhd" "$HERE/video_overlay_passthrough.vhd" "$P/video_overlay_standin.vhd" <<'EOF2' \
      || fail "video_overlay stand-in"
import sys
ent = open(sys.argv[1]).read()
ent = ent[:ent.index("architecture standin of video_overlay is")]
open(sys.argv[3], "w").write(ent + "\n" + open(sys.argv[2]).read())
EOF2
   "$GHDL" -a "${FLAGS[@]}" --work=unisim "$TOOLS/stubs/unisim_vcomponents.vhd" || fail "unisim stub"
   "$GHDL" -a "${FLAGS[@]}" --work=xpm "$TOOLS/stubs/xpm_vcomponents.vhd" || fail "xpm stub"
   "$GHDL" -i "${FLAGS[@]}" "$REPO/M2M/QNICE/vhdl/tools.vhd" "$AV/video_modes_pkg.vhd" \
      "$REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd" "$REPO/M2M/vhdl/controllers/HDMI/sync_reg.vhd" \
      "$REPO/M2M/vhdl/controllers/HDMI/hdmi_tx_encoder.vhd" "$REPO/M2M/vhdl/controllers/HDMI/vga_to_hdmi.vhd" \
      "$REPO/M2M/vhdl/memory/avm_decrease.vhd" "$AV/clk_synthetic_enable.vhd" "$AV/digital_pipeline.vhd" \
      "$P/video_overlay_standin.vhd" "$WIRING/tb_hdmi_raw_wiring_pkg.vhd" "$P/ascal_standin.vhd" "$P/serialiser_standin.vhd" \
      "$AV/hdmi_genlock.vhd" "$HERE/tb_hdmi_raw_cts.vhd" || fail "import tb_hdmi_raw_cts (packet)"
   "$GHDL" -m "${FLAGS[@]}" -Wno-binding -Wno-hide tb_hdmi_raw_cts > "$BUILD/packet_make.log" 2>&1 \
      || { cat "$BUILD/packet_make.log"; fail "make tb_hdmi_raw_cts (packet)"; }
   printf '%s\n' '$ version 1.1' /tb_hdmi_raw_cts/tb_phase /tb_hdmi_raw_cts/i_dp/audio_pcm_cts \
      /tb_hdmi_raw_cts/i_dp/i_vga_to_hdmi/vga_acr /tb_hdmi_raw_cts/i_dp/i_vga_to_hdmi/data_ack \
      /tb_hdmi_raw_cts/i_dp/i_vga_to_hdmi/pcm_cts_s > "$BUILD/packet.opt"
   ./tb_hdmi_raw_cts --ieee-asserts=disable -gG_PACKET=true -gG_FONT_FILE="$REPO/M2M/font/Anikki-16x16-m2m.rom" \
      --read-wave-opt="$BUILD/packet.opt" --vcd="$BUILD/packet.vcd" > "$BUILD/packet_sim.log" 2>&1
   cat "$BUILD/packet_sim.log"
   if ! grep -q '^SIMULATION DONE' "$BUILD/packet_sim.log" || grep -qi 'assertion\|error' "$BUILD/packet_sim.log"; then
      status=1
   fi
   python3 "$HERE/check_cts.py" --packet "$BUILD/packet.vcd" "$REPO" > "$BUILD/packet_check.log" 2>&1
   cat "$BUILD/packet_check.log"
   grep -q '^RESULT: PASS' "$BUILD/packet_check.log" || status=1
   echo "runtime: $(( $(date +%s) - s )) s"
fi

echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL"
fi
exit $status
