#!/bin/bash
T="$(cd "$(dirname "$0")" && pwd)"
for h in 39 79 10; do python3 -I "$T/exp5_sweep.py" 0 2 $h 480 690 15 1; done
echo "EXIT $?"
