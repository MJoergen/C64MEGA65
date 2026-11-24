#!/bin/bash
# run_flux_benches.sh <repository> <absolute scratch dir>
#
# The two flux benches of this folder on the flux of cylinder 77, side H=1, of
# the failed format (f77h0.txt.gz), with the decoder's tolerance for a weak
# first sync byte on and off (issue #257, part E, change 3), built with nvc:
#   tb_flux_dec  on f77h0.txt: with the tolerance every revolution decodes the
#                headers 1 to 10 with a good CRC and the tolerance is used 3
#                times; without it every revolution decodes 1 to 6 and 8 to 10
#                and never 7; the model (decmodel.py) agrees with the RTL event
#                for event in both runs (rtlcmp.py);
#   tb_flux_ctl  on f77h0.txt looped four times (loopflux.py), with the index
#                period of the stored logs (G_REV_CYC = 9954565): with the
#                tolerance sector 7 is read with result 00 and its report
#                lines are those of ctl_run_tol.log; without it the report
#                lines are those of ctl_run.log (sector 7: record not found).
# JOBS (environment, default 1): 2 runs the two decoders of each bench at the
# same time. About 25 minutes with JOBS=1 on an idle machine.
# Prints one line per check and "RESULT: PASS" or "RESULT: FAIL" (exit 0 / 1).
set -u
R=$(cd "${1:?repository}" && pwd); B=${2:?scratch dir}
JOBS=${JOBS:-1}
T=$R/doc/dev-fdd/tools/part_e/format_stop; P=$R/CORE/vhdl/physical_1581
mkdir -p "$B" && cd "$B" || exit 1
rm -rf dec ctl; mkdir -p dec ctl
fail=0
check() {  # check <name> <0 = ok>
  if [ "$2" -eq 0 ]; then echo "$1: OK"; else echo "$1: FAILED"; fail=1; fi
}
gunzip -c $T/f77h0.txt.gz > f77h0.txt || exit 1
python3 -I -B $T/loopflux.py f77h0.txt 4 f77h0_x4.txt > /dev/null || exit 1
STAGES="$P/physical_1581_mfm_gaps.vhd $P/physical_1581_mfm_quantise.vhd $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd"
if ! nvc --std=2008 --work=work:$B/dec/work -a $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $STAGES \
     $P/physical_1581_mfm_decoder.vhd $T/tb_flux_dec.vhd > dec/build.log 2>&1; then
  echo "tb_flux_dec: BUILD FAILED"; echo "RESULT: FAIL"; exit 1
fi
if ! nvc --std=2008 --work=work:$B/ctl/work -a $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd \
     $P/physical_1581_inputs.vhd $STAGES $P/physical_1581_mfm_decoder.vhd $P/physical_1581_mfm_encoder.vhd \
     $P/physical_1581_writer.vhd $P/physical_1581_rdahead.vhd $P/physical_1581_rdfifo.vhd \
     $P/physical_1581_controller.vhd $T/tb_flux_ctl.vhd > ctl/build.log 2>&1; then
  echo "tb_flux_ctl: BUILD FAILED"; echo "RESULT: FAIL"; exit 1
fi

run_dec() {  # run_dec <tol_off>
  ( cd dec && nvc --std=2008 --work=work:$B/dec/work -e -gG_IN=$B/f77h0.txt -gG_OUT=$B/dec/ev_$1.txt \
      -gG_TOL_OFF=$1 tb_flux_dec -r > run_$1.log 2>&1 )
}
run_ctl() {  # run_ctl <tol_off>
  ( cd ctl && nvc --std=2008 --work=work:$B/ctl/work -e -gG_IN=$B/f77h0_x4.txt -gG_REV_CYC=9954565 \
      -gG_TOL_OFF=$1 tb_flux_ctl -r > run_$1.log 2>&1 )
}
t0=$(date +%s)
if [ "$JOBS" -ge 2 ]; then run_dec 0 & run_dec 1 & wait; else run_dec 0; run_dec 1; fi
if [ "$JOBS" -ge 2 ]; then run_ctl 0 & run_ctl 1 & wait; else run_ctl 0; run_ctl 1; fi
t1=$(date +%s)

# tb_flux_dec: the headers of every revolution
python3 -I -B $T/evsum.py dec/ev_0.txt 9954550 > dec/sum_0.txt
python3 -I -B $T/evsum.py dec/ev_1.txt 9954550 > dec/sum_1.txt
n_on=$(grep -c 'IDs: 1 2 3 4 5 6 7 8 9 10$' dec/sum_0.txt); r_on=$(wc -l < dec/sum_0.txt | tr -d " ")
n_off=$(grep -c 'IDs: 1 2 3 4 5 6 8 9 10$' dec/sum_1.txt); r_off=$(wc -l < dec/sum_1.txt | tr -d " ")
tol_on=$(grep -c '^TOL' dec/ev_0.txt); tol_off=$(grep -c '^TOL' dec/ev_1.txt)
rc=1; [ "$n_on" -eq 3 ] && [ "$r_on" -eq 3 ] && [ "$tol_on" -eq 3 ] && rc=0
check "tb_flux_dec with the tolerance: headers 1 to 10 in $n_on of $r_on revolutions, $tol_on uses" $rc
rc=1; [ "$n_off" -eq 3 ] && [ "$r_off" -eq 3 ] && [ "$tol_off" -eq 0 ] && rc=0
check "tb_flux_dec without the tolerance: headers 1 to 6 and 8 to 10 in $n_off of $r_off revolutions, $tol_off uses" $rc
python3 -I -B $T/rtlcmp.py f77h0.txt dec/ev_0.txt on > dec/cmp_0.txt; rc=$?
check "model and RTL with the tolerance: $(tail -1 dec/cmp_0.txt)" $rc
python3 -I -B $T/rtlcmp.py f77h0.txt dec/ev_1.txt off > dec/cmp_1.txt; rc=$?
check "model and RTL without the tolerance: $(tail -1 dec/cmp_1.txt)" $rc

# tb_flux_ctl: the report lines against the stored logs
notes() { grep '^\*\* Note: ' "$1" | sed -e 's/^\*\* Note: //' -e 's/ tol=[0-9]*$//'; }
grep -q "RS 7: result 00 rnf='0' crc='0' CHR=77/1/7" ctl/run_0.log; rc=$?
check "tb_flux_ctl with the tolerance: sector 7 read with result 00" $rc
notes ctl/run_0.log > ctl/notes_0.txt; notes $T/ctl_run_tol.log > ctl/stored_0.txt
cmp -s ctl/notes_0.txt ctl/stored_0.txt; rc=$?
check "tb_flux_ctl with the tolerance: report lines as ctl_run_tol.log ($(wc -l < ctl/notes_0.txt | tr -d " ") lines)" $rc
grep -q "RS 7: result 04 rnf='1'" ctl/run_1.log; rc=$?
check "tb_flux_ctl without the tolerance: sector 7 not found (result 04)" $rc
notes ctl/run_1.log > ctl/notes_1.txt; notes $T/ctl_run.log > ctl/stored_1.txt
cmp -s ctl/notes_1.txt ctl/stored_1.txt; rc=$?
check "tb_flux_ctl without the tolerance: report lines as ctl_run.log ($(wc -l < ctl/notes_1.txt | tr -d " ") lines)" $rc

echo "simulation wall time $((t1 - t0)) s"
[ $fail -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit $fail
