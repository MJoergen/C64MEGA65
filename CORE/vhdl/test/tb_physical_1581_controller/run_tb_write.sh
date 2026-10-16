#!/bin/bash
# run_tb_write.sh -- closed-loop write tests of the physical 1581 (issue #244)
#
# usage: run_tb_write.sh <absolute scratch dir> [group:latency ...]
#   default groups: 1:15 2:0 2:15 2:30 3:15 4:15 5:15 (all in parallel)
#
# Analyzes the physical_1581 tree and the test packages into <dir>/lib,
# elaborates tb_physical_1581_write, runs every group from <dir> (GHDL drops
# its executables and the bench its dump files into the working directory,
# so never run this from the repository), then checks the written flux with
# the independent twin: wr_twin.py --selftest, W1 / W2 / W10 (and W3 when
# group 5 ran) edge for edge plus the independent decode, and the precomp red
# control (W10 with the precomp flags flipped must fail). One group takes
# 25-60 minutes of wall time (the controller is simulated at 50 MHz).
set -u
B=${1:?scratch dir}; shift
SCEN=${*:-"1:15 2:0 2:15 2:30 3:15 4:15 5:15"}
R=$(cd "$(dirname "$0")/../../../.." && pwd)
P=$R/CORE/vhdl/physical_1581; T=$R/CORE/vhdl/test
TWIN=$T/tb_physical_1581_controller/wr_twin.py
mkdir -p $B/lib && cd $B || exit 1
ghdl -a --std=08 --workdir=$B/lib \
  $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd \
  $P/physical_1581_mfm_gaps.vhd $P/physical_1581_mfm_quantise.vhd \
  $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd \
  $P/physical_1581_mfm_decoder.vhd $P/physical_1581_inputs.vhd \
  $P/physical_1581_rdfifo.vhd $P/physical_1581_wfifo.vhd \
  $P/physical_1581_mfm_encoder.vhd $P/physical_1581_writer.vhd \
  $P/physical_1581_controller.vhd \
  $T/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd \
  $T/tb_physical_1581_controller/golden_1581_pkg.vhd \
  $T/tb_physical_1581_controller/mech_model_1581.vhd \
  $T/tb_physical_1581_controller/tb_physical_1581_write.vhd || { echo "ANALYZE FAILED"; exit 1; }
ghdl -e --std=08 --workdir=$B/lib tb_physical_1581_write || { echo "ELABORATE FAILED"; exit 1; }
for gl in $SCEN; do
  g=${gl%%:*}; l=${gl##*:}
  ( ./tb_physical_1581_write -gG_GROUP=$g -gG_LAT_US=$l --assert-level=error > $B/write_g${g}_l${l}.log 2>&1
    echo "group $g latency $l us: rc=$? | $(grep -h 'ALL TESTS PASSED\|FAIL' $B/write_g${g}_l${l}.log | head -1 | sed 's/.*(report [a-z]*): //') | $(grep -h 'simulation finished' $B/write_g${g}_l${l}.log)" ) &
done
wait
rc=0
python3 $TWIN --selftest || rc=1
for f in $B/wr_g*_stream_*.txt; do
  d=${f/_stream_/_flux_}
  python3 $TWIN --stream $f --dump $d --quiet || rc=1
done
for f in $B/wr_g1_l*_stream_2.txt; do
  if python3 $TWIN --stream $f --dump ${f/_stream_/_flux_} --flip-precomp --quiet > /dev/null; then
    echo "twin red control: W10 with flipped precomp PASSED -- the check is blind"; rc=1
  else
    echo "twin red control: W10 with flipped precomp fails, as it must"
  fi
done
echo "run_tb_write: twin rc=$rc"
exit $rc
