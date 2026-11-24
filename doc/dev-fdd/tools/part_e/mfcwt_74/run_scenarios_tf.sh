#!/bin/bash
# run_scenarios_tf.sh: the power-on initialization and UJ of exp10_scenarios.py over the time of the
# first index pulse (400 to 790 ms in steps of 65 ms), with the READY rule and the pace of
# WIP-V6-A25 (old, rtl) and with both of part E (new, rate); hold 18 ms, head on 39. Run it in a
# directory without c1581.rom (stock ROM); scenarios_tf_stock.log is its output.
T="$(cd "$(dirname "$0")" && pwd)"
for s in power uj; do
  for c in "old rtl" "new rate"; do
    for tf in 400 465 530 595 660 725 790; do
      python3 -I -B "$T/exp10_scenarios.py" $s $c 18 $tf | grep -v '^#' | sed "s/^/$s $c t_first $tf: /"
    done
  done
done
echo "EXIT $?"
