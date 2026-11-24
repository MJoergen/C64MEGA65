#!/bin/bash
# run_scenarios.sh: exp10_scenarios.py for every scenario with the READY rule and the pace of
# WIP-V6-A25 (old, rtl), the rule of A25 at the pace of part E (old, rate) and both of part E
# (new, rate); hold 18 ms, first index pulse 620 ms after motor-on. Run it in a directory without
# c1581.rom for the stock ROM (scenarios_stock.log) or in one with the JiffyDOS ROM as c1581.rom
# (scenarios_jd.log); the output goes to stdout.
T="$(cd "$(dirname "$0")" && pwd)"
for s in power uj bump seekw pull; do
  for c in "old rtl" "old rate" "new rate"; do
    python3 -I -B "$T/exp10_scenarios.py" $s $c 18 620
  done
done
echo "EXIT $?"
