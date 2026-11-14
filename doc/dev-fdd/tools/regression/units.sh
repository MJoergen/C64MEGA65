#!/bin/bash
# units.sh <repo checkout> <absolute scratch dir>
# Runs the unit benches of the physical_1581 tree that have no runner of their own, one after the
# other, each with the recipe of its header comment: crc, mfm_decoder, mfm_encoder, quantise_ab,
# inputs, rdfifo, wfifo, writer. Prints one line per bench and "UNITS RESULT: PASS" or
# "UNITS RESULT: FAIL" (exit status 0 / 1).
set -u
R=${1:?repo}; B=${2:?scratch}
P=$R/CORE/vhdl/physical_1581; T=$R/CORE/vhdl/test
CO=$T/tb_physical_1581_codec; IN=$T/tb_physical_1581_inputs; WR=$T/tb_physical_1581_writer
GOLD=$T/tb_physical_1581_controller/golden_1581_pkg.vhd
STAGES="$P/physical_1581_mfm_gaps.vhd $P/physical_1581_mfm_quantise.vhd $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd"
fail=0
run() {  # run <bench> <files...>
  tb=$1; shift
  d=$B/$tb; rm -rf "$d"; mkdir -p "$d/lib"; cd "$d" || exit 1
  t0=$(date +%s)
  if ! ghdl -a --std=08 --workdir=lib "$@" > build.log 2>&1; then echo "$tb: BUILD FAILED"; head -5 build.log; fail=1; return; fi
  ghdl --elab-run --std=08 --workdir=lib $tb --assert-level=error > run.log 2>&1; rc=$?
  verdict "$tb" $rc $t0
}
verdict() {
  tb=$1; rc=$2; t0=$3
  last=$(grep -E "report (note|warning|error|failure)" run.log | tail -1 | sed -E 's/^.*\(report [a-z]+\): //' | cut -c1-110)
  fin=$(grep -E "simulation (finished|stopped)" run.log | tail -1 | sed -E 's/^.*simulation/simulation/')
  bad=$(grep -cE "\((assertion|report) (error|failure)\)" run.log)
  [ $rc -eq 0 ] && [ "$bad" = 0 ] || fail=1
  echo "$tb: rc=$rc errors=$bad wall=$(( $(date +%s) - t0 ))s | $last | $fin"
}
run tb_physical_1581_crc         $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $CO/tb_physical_1581_crc.vhd
run tb_physical_1581_mfm_decoder $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $STAGES $P/physical_1581_mfm_decoder.vhd \
                                 $CO/mfm_flux_gen_pkg.vhd $CO/tb_physical_1581_mfm_decoder.vhd
run tb_physical_1581_mfm_encoder $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $P/physical_1581_mfm_encoder.vhd \
                                 $CO/mfm_flux_gen_pkg.vhd $GOLD $CO/tb_physical_1581_mfm_encoder.vhd
# quantise_ab: three libraries in separate work directories
tb=tb_physical_1581_quantise_ab; d=$B/$tb; rm -rf "$d"; mkdir -p "$d/new" "$d/old" "$d/top"; cd "$d" || exit 1; t0=$(date +%s)
if ghdl -a --std=08 --work=q_new --workdir=new $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $STAGES $P/physical_1581_mfm_decoder.vhd > build.log 2>&1 &&
   ghdl -a --std=08 --work=q_old --workdir=old $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $P/physical_1581_mfm_gaps.vhd \
        $CO/ref_mfm_quantise_fixed.vhd $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd $P/physical_1581_mfm_decoder.vhd >> build.log 2>&1 &&
   ghdl -a --std=08 --workdir=top -Pnew -Pold $CO/mfm_flux_gen_pkg.vhd $CO/$tb.vhd >> build.log 2>&1; then
  ghdl --elab-run --std=08 --workdir=top -Pnew -Pold $tb --assert-level=error > run.log 2>&1; verdict $tb $? $t0
else echo "$tb: BUILD FAILED"; head -5 build.log; fail=1; fi
run tb_physical_1581_inputs      $P/physical_1581_pkg.vhd $P/physical_1581_inputs.vhd $IN/tb_physical_1581_inputs.vhd
run tb_physical_1581_rdfifo      $P/physical_1581_rdfifo.vhd $IN/tb_physical_1581_rdfifo.vhd
run tb_physical_1581_wfifo       $P/physical_1581_wfifo.vhd $IN/tb_physical_1581_wfifo.vhd
run tb_physical_1581_writer      $P/physical_1581_pkg.vhd $P/physical_1581_writer.vhd $WR/tb_physical_1581_writer.vhd
[ $fail -eq 0 ] && echo "UNITS RESULT: PASS" || echo "UNITS RESULT: FAIL"
exit $fail
