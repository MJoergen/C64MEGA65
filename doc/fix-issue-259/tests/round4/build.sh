#!/usr/bin/env bash
# Builds reu-tests4.d64 (issue #259, round 4): tokenizes the BASIC programs with
# petcat, assembles the machine-code program with ca65/ld65 at $0C00 and
# appends them to their BASIC drivers (one PRG each, no LOAD inside a program).
# Tools: VICE petcat + c1541 (/Applications/Vice/bin), cc65 (ca65, ld65), python3.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$HERE"
VICE="${VICE:-/Applications/Vice/bin}"
PETCAT="$VICE/petcat"
C1541="$VICE/c1541"
ML_ADDR=3072   # $0C00

prg_from_bas() {   # <name>
  "$PETCAT" -w2 -o "$1.prg" -- "$1.bas"
}
ml_bin() {         # <name>  -> <name>.bin (raw, starts at $0C00)
  ca65 -t none -o "$1.o" "$1.s"
  ld65 -t none -o "$1.bin" "$1.o"
  rm -f "$1.o"
}
glue() {           # <name>: <name>.prg (BASIC) + zero padding + <name>.bin -> <name>.prg
  python3 - "$1" "$ML_ADDR" <<'PY'
import sys
name, ml_addr = sys.argv[1], int(sys.argv[2])
bas = open(name + ".prg", "rb").read()
ml  = open(name + ".bin", "rb").read()
load = bas[0] | (bas[1] << 8)
end  = load + len(bas) - 2            # first free address behind the BASIC text
assert load == 0x0801, hex(load)
assert end <= ml_addr, f"{name}: BASIC text ends at {end:#x}, beyond {ml_addr:#x}"
out = bas + bytes(ml_addr - end) + ml
open(name + ".prg", "wb").write(out)
print(f"{name}.prg: BASIC {len(bas)-2} bytes, ML {len(ml)} bytes at {ml_addr:#x}, PRG ends at {ml_addr+len(ml):#x}")
PY
  rm -f "$1.bin"
}

for n in 13-swapchk 14-ffff; do prg_from_bas "$n"; done
for n in 14-ffff; do ml_bin "$n"; glue "$n"; done

rm -f reu-tests4.d64
"$C1541" -format "reu tests 4,r4" d64 reu-tests4.d64 >/dev/null
for n in 13-swapchk 14-ffff; do
  "$C1541" -attach reu-tests4.d64 -write "$n.prg" "$n" >/dev/null
done
"$C1541" -attach reu-tests4.d64 -list
rm -f reu-tests4.zip && zip -q reu-tests4.zip reu-tests4.d64 && ls -la reu-tests4.d64 reu-tests4.zip
