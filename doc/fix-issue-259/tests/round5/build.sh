#!/usr/bin/env bash
# Builds reu-tests5.d64 (issue #259, round 5): every program of the round on one disk.
# The BASIC programs get reucheck.bas appended (the "reu check" subroutine at line 900, which
# they call at their start and at their end; 15-health is the stand-alone long form, 16-soak
# writes registers only, and 12-position needs none: it prints status, length and cycle count
# of every transfer). They
# are tokenized with petcat; the machine code of 12-position is assembled with ca65/ld65 at
# $0C00 and appended to its BASIC driver (one PRG, no LOAD inside a program).
# Tools: VICE petcat + c1541 (/Applications/Vice/bin), cc65 (ca65, ld65), python3.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$HERE"
VICE="${VICE:-/Applications/Vice/bin}"
PETCAT="$VICE/petcat"
C1541="$VICE/c1541"
ML_ADDR=3072   # $0C00
WITH_CHECK="3-verify 9-values 13-swapchk 1-fetch 2-stash"
ALL="15-health 16-soak 3-verify 9-values 12-position 13-swapchk 1-fetch 2-stash"

prg_from_bas() {   # <name> [<appended source>]
  cat "$1.bas" ${2:+"$2"} > "$1.tmp.bas"
  "$PETCAT" -w2 -o "$1.prg" -- "$1.tmp.bas"
  rm -f "$1.tmp.bas"
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

prg_from_bas 15-health
prg_from_bas 16-soak          # register writes only: must not issue a transfer
prg_from_bas 12-position      # prints status, length and cycle count of every run itself
for n in $WITH_CHECK; do prg_from_bas "$n" reucheck.bas; done
ml_bin 12-position; glue 12-position

rm -f reu-tests5.d64
"$C1541" -format "reu tests 5,r5" d64 reu-tests5.d64 >/dev/null
for n in $ALL; do
  "$C1541" -attach reu-tests5.d64 -write "$n.prg" "$n" >/dev/null
done
"$C1541" -attach reu-tests5.d64 -list
rm -f reu-tests5.zip && zip -q reu-tests5.zip reu-tests5.d64 && ls -la reu-tests5.d64 reu-tests5.zip
