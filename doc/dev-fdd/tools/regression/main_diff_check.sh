#!/bin/bash
# main_diff_check.sh <repo checkout> <base rev> <scratch dir> [tools.vhd of QNICE]
# Differential GHDL analysis of CORE/vhdl/main.vhd: base revision against the checkout's working tree.
# The last argument is only needed for a checkout without the submodule M2M/QNICE: the path of
# M2M/QNICE/vhdl/tools.vhd in a checkout that has it.
# Both seed libraries hold the entities main.vhd instantiates from CORE/vhdl/physical_1581 (their own
# version) and, if present in that version, c1581_error_led, so GHDL binds these instances and checks
# their port maps. The sets of diagnostics (line numbers removed) must be identical.
set -u
R=${1:?repo}; BASE=${2:?base rev}; D=${3:?scratch}
QTOOLS=${4:-$R/M2M/QNICE/vhdl/tools.vhd}
[ -f "$QTOOLS" ] || { echo "no $QTOOLS: pass the path of QNICE's tools.vhd as the fourth argument"; exit 1; }
mkdir -p $D/lib_base $D/lib_new $D/src_base && cd $D || exit 1
P=CORE/vhdl/physical_1581
LIST="pkg crc mfm_gaps mfm_quantise mfm_gaps_to_bits mfm_bits_to_bytes mfm_decoder inputs rdfifo wfifo mfm_encoder writer rdahead controller diag"
# the package vdrives_pkg only (with its library and use clauses), not the entity that follows it
pkg_only() { awk '/^library/ && !p { buf = "" } { buf = buf $0 "\n" } /^package vdrives_pkg/ { p = 1 } /^end package/ && p { printf "%s", buf; exit }' ; }
git -C $R show $BASE:M2M/vhdl/vdrives.vhd | pkg_only > $D/vdrives_pkg_base.vhd
pkg_only < $R/M2M/vhdl/vdrives.vhd > $D/vdrives_pkg_new.vhd
[ -s $D/vdrives_pkg_base.vhd ] && [ -s $D/vdrives_pkg_new.vhd ] || { echo "cannot extract vdrives_pkg"; exit 1; }
for f in M2M/vhdl/av_pipeline/video_modes_pkg.vhd CORE/vhdl/globals.vhd CORE/vhdl/main.vhd CORE/vhdl/c1581_error_led.vhd; do
  mkdir -p $D/src_base/$(dirname $f); git -C $R show $BASE:$f > $D/src_base/$f 2>/dev/null || rm -f $D/src_base/$f
done
for f in $LIST; do git -C $R show $BASE:$P/physical_1581_$f.vhd > $D/src_base/physical_1581_$f.vhd 2>/dev/null || rm -f $D/src_base/physical_1581_$f.vhd; done
for v in base new; do
  if [ $v = base ]; then S=$D/src_base; PP=$D/src_base; else S=$R; PP=$R/$P; fi
  ghdl -a --std=08 -frelaxed --workdir=$D/lib_$v $QTOOLS $S/M2M/vhdl/av_pipeline/video_modes_pkg.vhd \
     $S/CORE/vhdl/globals.vhd $D/vdrives_pkg_$v.vhd || { echo "SEED FAILED ($v)"; exit 1; }
  for f in $LIST; do
    [ -f $PP/physical_1581_$f.vhd ] || continue
    ghdl -a --std=08 -frelaxed --workdir=$D/lib_$v $PP/physical_1581_$f.vhd || { echo "SEED FAILED ($v $f)"; exit 1; }
  done
  [ -f $S/CORE/vhdl/c1581_error_led.vhd ] && { ghdl -a --std=08 -frelaxed --workdir=$D/lib_$v $S/CORE/vhdl/c1581_error_led.vhd || { echo "SEED FAILED ($v led)"; exit 1; }; }
  cp $S/CORE/vhdl/main.vhd $D/main_$v.vhd
  ghdl -a --std=08 -frelaxed --workdir=$D/lib_$v $D/main_$v.vhd > $D/err_$v.txt 2>&1
  echo "main_$v.vhd: ghdl rc=$? , $(grep -c 'error' $D/err_$v.txt) error lines"
  sed -E 's/^[^:]*main_(base|new)\.vhd:[0-9]+:[0-9]+://' $D/err_$v.txt | grep 'error' | sort > $D/errset_$v.txt
done
echo "--- diagnostics (new):"; cat $D/errset_new.txt
if diff $D/errset_base.txt $D/errset_new.txt > $D/errset.diff; then echo "RESULT: PASS: diagnostic sets identical ($(wc -l < $D/errset_new.txt | tr -d ' ') each)"; else echo "RESULT: FAIL: diagnostic sets differ:"; cat $D/errset.diff; fi
