#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Paddle bench (GitHub issue #193): the paddle measurement of mouse_input.vhdl, see README.md
#
#   CORE/vhdl/test/tb_paddles/run.sh [identity|atari|mixed|modes|powerup|synth|mutants|all] [--keep]
#
#   identity  both mode inputs '0' at every latch tick: every output of the DUT equal to that of the
#             file of the base commit (the reference, its comparator inputs through two flip-flops)
#             at all times, 2000 measuring cycles with random and non-monotonic comparator signals,
#             random joystick inputs and mode pulses, then 100 cycles with random Amiga inputs
#   (the reference is the file of the base commit in all parts; the synchronizer of the DUT
#   corresponds to the two flip-flops in front of it)
#   atari     both sockets in Atari mode: charge times from 0 to 600 us against the formula, the
#             observer and half the C64 result of the reference; every result from 0 to 255
#   mixed     socket a C64 and b Atari, and the other way round: the C64 socket equal to the
#             reference cycle by cycle (charge times, a 1351 for every p, random signals)
#   modes     2000 cycles with random changes of the modes at random clock cycles
#   powerup   the first cycles after power-up with the modes 00, 11, 01, 10 and random changes
#   synth     ghdl --synth of mouse_input: no error and no latch, flip-flop count; a mutant with
#             a latch must fail
#   mutants   mutants of mouse_input.vhdl that the bench must reject
#   all       everything (default)
#
# At most two simulations run at the same time. Ends with "RESULT: PASS" (exit status 0) or
# "RESULT: FAIL ..." (exit status 1). Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL),
# python3, git. Runtime of "all" about 9 minutes.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=6845596        # WIP-V6-A25: mouse_input.vhdl without the Atari mode
SRC="$REPO/M2M/vhdl/controllers/M65/mouse_input.vhdl"
BENCH="$HERE/tb_paddles_pkg.vhd $HERE/tb_paddles_board.vhd $HERE/tb_paddles.vhd"

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      identity|atari|mixed|modes|powerup|synth|mutants|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [identity|atari|mixed|modes|powerup|synth|mutants|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_paddles.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }
want() { [ "$WHAT" = all ] || [ "$WHAT" = "$1" ]; }

# mutate <src> <dst> <old> <new>: copy src to dst with exactly one occurrence of old replaced
mutate() {
   python3 - "$@" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    print(f"    mutant pattern found {s.count(old)} times (expected once): {old!r}")
    sys.exit(1)
open(dst, "w").write(s.replace(old, new))
PYEOF
}

# the reference: mouse_input.vhdl of the base commit with the entity renamed to mouse_input_ref
REF="$BUILD/mouse_input_ref.vhdl"
git -C "$REPO" show "$BASE:M2M/vhdl/controllers/M65/mouse_input.vhdl" > "$BUILD/base.vhdl" 2>/dev/null &&
python3 - "$BUILD/base.vhdl" "$REF" <<'PYEOF' || { echo "cannot create the reference from $BASE"; exit 1; }
import sys
s = open(sys.argv[1]).read()
for old, new in (("entity mouse_input is", "entity mouse_input_ref is"),
                 ("end mouse_input;", "end mouse_input_ref;"),
                 ("architecture behavioural of mouse_input is", "architecture behavioural of mouse_input_ref is")):
    if s.count(old) != 1:
        print(f"    reference: {old!r} found {s.count(old)} times")
        sys.exit(1)
    s = s.replace(old, new)
open(sys.argv[2], "w").write(s)
PYEOF

# build <lib> <mouse_input source>: analyze the DUT, the reference and the bench, elaborate
build() {
   local lib=$1 dut=$2
   mkdir -p "$lib"
   ( cd "$lib" && "$GHDL" -a $GF --workdir=. "$dut" "$REF" $BENCH && "$GHDL" -e $GF --workdir=. tb_paddles ) \
      > "$lib/build.log" 2>&1 || { grep -v -i "warning\|^use\|^ *\^" "$lib/build.log" | sed 's/^/    /' | head -10; return 1; }
}

# sim <lib> <log> [generics]: run the bench (15 min timeout); writes its TB lines to <log>.tb;
# returns 0 only if the bench ran to the end and reported "TB: RESULT PASS"
sim() {
   local lib=$1 log=$2; shift 2
   python3 - "$GHDL" "$lib" "$log" "$@" <<'PYEOF'
import re, subprocess, sys
ghdl, lib, log = sys.argv[1:4]
args = sys.argv[4:]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", "tb_paddles"] + args,
                       cwd=lib, capture_output=True, text=True, timeout=900)
    out, rc = r.stdout + r.stderr, r.returncode
except subprocess.TimeoutExpired:
    out, rc = "TIMEOUT\n", 1
open(log, "w").write(out)
tb = []
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
        tb.append(re.sub(r"(?:(?<=\s)|^)/(?:[^\s/]+/)+", "", l))
open(log + ".tb", "w").write("\n".join(tb) + "\n")
sys.exit(0 if rc == 0 and "TB: RESULT PASS" in out else 1)
PYEOF
}

# the runs of the parts: name and generics
runs_of() {
   case $1 in
      identity) echo "identity" ;;
      atari)    echo "atari" ;;
      mixed)    echo "mixed_01 mixed_10" ;;
      modes)    echo "modes" ;;
      powerup)  echo "powerup_00 powerup_11 powerup_01 powerup_10 powerup_rn" ;;
   esac
}
args_of() {
   case $1 in
      identity)   echo "-gG_PART=identity -gG_CYCLES=2000 -gG_AMIGA=100" ;;
      atari)      echo "-gG_PART=atari -gG_MODES=11 -gG_CYCLES=337" ;;
      mixed_01)   echo "-gG_PART=mixed -gG_MODES=01 -gG_CYCLES=235" ;;
      mixed_10)   echo "-gG_PART=mixed -gG_MODES=10 -gG_CYCLES=235" ;;
      modes)      echo "-gG_PART=modes -gG_CYCLES=2000 -gG_SEED=2" ;;
      powerup_*)  echo "-gG_PART=powerup -gG_MODES=${1#powerup_} -gG_CYCLES=6" ;;
   esac
}
title_of() {
   case $1 in
      identity)   echo "identity with the reference in C64 mode (2000 + 100 cycles)" ;;
      atari)      echo "Atari mode on both sockets, charge times 0 to 600 us" ;;
      mixed_01)   echo "mixed: socket a C64, socket b Atari" ;;
      mixed_10)   echo "mixed: socket a Atari, socket b C64" ;;
      modes)      echo "modes changing at random clock cycles (2000 cycles)" ;;
      powerup_rn) echo "power-up, modes changing at random from the start" ;;
      powerup_*)  echo "power-up with the modes ab = ${1#powerup_} from the start" ;;
   esac
}

# lane <run>...: the runs one after the other; prints the TB lines of each run when it is done
lane() {
   local r
   for r in "$@"; do
      sim "$BUILD/lib" "$BUILD/$r.log" $(args_of "$r")
      echo $? > "$BUILD/$r.rc"
      { echo "=== $(title_of "$r")"; sed 's/^/    /' "$BUILD/$r.log.tb"; } > "$BUILD/$r.txt"
      cat "$BUILD/$r.txt"
   done
}

# --------------------------------------------------------------------------------------------------
LANE_A=""
LANE_B=""
for p in identity powerup; do want $p && LANE_A="$LANE_A $(runs_of $p)"; done
for p in atari mixed modes; do want $p && LANE_B="$LANE_B $(runs_of $p)"; done

if [ -n "$LANE_A$LANE_B" ]; then
   echo "=== build (DUT: working tree, reference: $BASE)"
   if build "$BUILD/lib" "$SRC"; then
      PIDS=""
      [ -n "$LANE_A" ] && { lane $LANE_A & PIDS="$PIDS $!"; }
      [ -n "$LANE_B" ] && { lane $LANE_B & PIDS="$PIDS $!"; }
      for pid in $PIDS; do wait "$pid"; done
      for r in $LANE_A $LANE_B; do
         [ "$(cat "$BUILD/$r.rc" 2>/dev/null)" = 0 ] || note_fail "$r"
      done
   else
      note_fail build
   fi
fi

# --------------------------------------------------------------------------------------------------
# synth <lib> <mouse_input source>: GHDL synthesis; returns 0 if it succeeds without a latch
synth() {
   local lib=$1 dut=$2
   mkdir -p "$lib"
   ( cd "$lib" && "$GHDL" -a $GF --workdir=. "$dut" && "$GHDL" --synth $GF --workdir=. mouse_input ) \
      > "$lib/synth.vhd" 2> "$lib/synth.log" && ! grep -q -i latch "$lib/synth.log"
}

# ffcount <netlist>: flip-flops in the VHDL netlist of ghdl --synth (bits assigned under rising_edge)
ffcount() {
   python3 - "$1" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
width = {}
for m in re.finditer(r"(\w+)\s*:\s*(?:out\s+|buffer\s+)?(?:std_logic_vector|unsigned)\s*\((\d+)\s+downto\s+(\d+)\)", s):
    width.setdefault(m.group(1), int(m.group(2)) - int(m.group(3)) + 1)
for m in re.finditer(r"(\w+)\s*:\s*(?:out\s+|buffer\s+)?std_logic\b(?!_)", s):
    width.setdefault(m.group(1), 1)
bits = regs = 0
for m in re.finditer(r"if rising_edge \(\w+\) then\s*(.*?)\s*end if;", s, re.S):
    for t in re.findall(r"^\s*(\w+)\s*<=", m.group(1), re.M):
        bits += width.get(t, 0)
        regs += 1
print(f"{bits} flip-flops in {regs} registers (GHDL netlist before optimization)")
PYEOF
}

if want synth; then
   echo "=== synthesis of mouse_input (ghdl --synth)"
   if synth "$BUILD/synth" "$SRC"; then
      W=$(grep -E "signal (pot_counter|pota_x_counter) :" "$BUILD/synth/synth.vhd" | sed -E 's/^ *signal ([a-z_]+) : std_logic_vector \(([0-9]+) downto 0\);/\1 \2/' |
          awk '{ printf "%s%s %d bits", sep, $1, $2 + 1; sep = ", " }')
      echo "    no error, no latch ($W); $(ffcount "$BUILD/synth/synth.vhd")"
      if synth "$BUILD/synth_base" "$BUILD/base.vhdl"; then
         echo "    the file of $BASE: $(ffcount "$BUILD/synth_base/synth.vhd")"
      fi
   else
      sed 's/^/    /' "$BUILD/synth/synth.log" | head -5
      note_fail synth
   fi
   M="$BUILD/synth_mut"
   mkdir -p "$M"
   if mutate "$SRC" "$M/mouse_input.vhdl" $'\nbegin\n' \
         $'\n  signal latch_q : std_logic;\nbegin\n\n  latch_q <= fa_potx when fb_potx = \'1\';\n'; then
      if synth "$M" "$M/mouse_input.vhdl"; then
         note_fail synth_mutant_not_detected
      else
         echo "    mutant 'latch' rejected: $(grep -m1 -i latch "$M/synth.log" | sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//')"
      fi
   else
      note_fail synth_mutant_pattern
   fi
fi

# --------------------------------------------------------------------------------------------------
# mutants: name, run (part and generics), exact text and its replacement
MUTANTS="no_sync one_stage three_stages halve round_up window_short_a window_short_b c64_beyond_a c64_beyond_b no_extend always_long
         extend_a_only latch_late unlatched relatch_256 latch_plus1 swap drain_long guard_255 powerup_long
         c64_halved"

mutant_def() {
   case $1 in
      no_sync)        M_ARGS="-gG_PART=identity -gG_CYCLES=40"
                      M_OLD=$'  pot_sync_proc : process(clk) is\n  begin\n    if rising_edge(clk) then\n      pot_pins_d  <= fb_poty & fb_potx & fa_poty & fa_potx;\n      pot_pins_dd <= pot_pins_d;\n    end if;\n  end process pot_sync_proc;\n'
                      M_NEW=$'  pot_pins_dd <= fb_poty & fb_potx & fa_poty & fa_potx;\n'
                      M_TXT="no synchronizer" ;;
      one_stage)      M_ARGS="-gG_PART=identity -gG_CYCLES=40"
                      M_OLD="      pot_pins_dd <= pot_pins_d;"
                      M_NEW="      pot_pins_dd <= fb_poty & fb_potx & fa_poty & fa_potx;"
                      M_TXT="synchronizer with one stage" ;;
      three_stages)   M_ARGS="-gG_PART=identity -gG_CYCLES=40"
                      M_OLD=$'  pot_sync_proc : process(clk) is\n  begin\n    if rising_edge(clk) then\n      pot_pins_d  <= fb_poty & fb_potx & fa_poty & fa_potx;\n'
                      M_NEW=$'  pot_sync_proc : process(clk) is\n    variable pot_pins_0 : std_logic_vector(3 downto 0) := "0000";\n  begin\n    if rising_edge(clk) then\n      pot_pins_d  <= pot_pins_0;\n      pot_pins_0  := fb_poty & fb_potx & fa_poty & fa_potx;\n'
                      M_TXT="synchronizer with three stages" ;;
      halve)          M_ARGS="-gG_PART=atari -gG_MODES=11 -gG_CYCLES=6"
                      M_OLD="            pota_x_internal <= to_unsigned(pota_x_counter / 2, 8);"
                      M_NEW="            pota_x_internal <= to_unsigned(pota_x_counter, 8);"
                      M_TXT="Atari result not halved" ;;
      round_up)       M_ARGS="-gG_PART=atari -gG_MODES=11 -gG_CYCLES=8"
                      M_OLD="            pota_x_internal <= to_unsigned(pota_x_counter / 2, 8);"
                      M_NEW="            pota_x_internal <= to_unsigned((pota_x_counter + 1) / 2, 8);"
                      M_TXT="Atari result rounded up" ;;
      window_short_a) M_ARGS="-gG_PART=powerup -gG_MODES=10 -gG_CYCLES=8"
                      M_OLD="            if pot_counter < 513 or atari_mode_a = '1' then"
                      M_NEW="            if pot_counter < 513 then"
                      M_TXT="Atari window of socket a as short as the C64 window" ;;
      window_short_b) M_ARGS="-gG_PART=powerup -gG_MODES=01 -gG_CYCLES=8"
                      M_OLD="            if pot_counter < 513 or atari_mode_b = '1' then"
                      M_NEW="            if pot_counter < 513 then"
                      M_TXT="Atari window of socket b as short as the C64 window" ;;
      c64_beyond_a)   M_ARGS="-gG_PART=powerup -gG_MODES=01 -gG_CYCLES=8"
                      M_OLD="            if pot_counter < 513 or atari_mode_a = '1' then"
                      M_NEW="            if pot_counter < 768 or atari_mode_a = '1' then"
                      M_TXT="socket a in C64 mode counted beyond tick 512 in a long cycle" ;;
      c64_beyond_b)   M_ARGS="-gG_PART=powerup -gG_MODES=10 -gG_CYCLES=8"
                      M_OLD="            if pot_counter < 513 or atari_mode_b = '1' then"
                      M_NEW="            if pot_counter < 768 or atari_mode_b = '1' then"
                      M_TXT="socket b in C64 mode counted beyond tick 512 in a long cycle" ;;
      no_extend)      M_ARGS="-gG_PART=powerup -gG_MODES=11 -gG_CYCLES=6"
                      M_OLD="        if pot_counter < 513 or (pot_counter < 768 and (atari_mode_a or atari_mode_b) = '1') then"
                      M_NEW="        if pot_counter < 513 then"
                      M_TXT="cycle length not extended" ;;
      always_long)    M_ARGS="-gG_PART=powerup -gG_MODES=00 -gG_CYCLES=6"
                      M_OLD="        if pot_counter < 513 or (pot_counter < 768 and (atari_mode_a or atari_mode_b) = '1') then"
                      M_NEW="        if pot_counter < 768 then"
                      M_TXT="cycle always long" ;;
      extend_a_only)  M_ARGS="-gG_PART=powerup -gG_MODES=01 -gG_CYCLES=6"
                      M_OLD="(pot_counter < 768 and (atari_mode_a or atari_mode_b) = '1')"
                      M_NEW="(pot_counter < 768 and atari_mode_a = '1')"
                      M_TXT="only socket a in Atari mode makes the cycle long" ;;
      latch_late)     M_ARGS="-gG_PART=powerup -gG_MODES=11 -gG_CYCLES=6"
                      M_OLD="(pot_counter < 768 and"
                      M_NEW="(pot_counter < 769 and"
                      M_TXT="long cycle one tick longer" ;;
      unlatched)      M_ARGS="-gG_PART=modes -gG_CYCLES=40"
                      M_OLD=$'      -- Assumes 50MHz clock\n'
                      M_NEW=$'      atari_mode_a <= atari_paddles_a;\n      atari_mode_b <= atari_paddles_b;\n      -- Assumes 50MHz clock\n'
                      M_TXT="modes not latched (taken from the inputs in every clock cycle)" ;;
      relatch_256)    M_ARGS="-gG_PART=modes -gG_CYCLES=40"
                      M_OLD=$'            pot_drain <= \'0\';\n'
                      M_NEW=$'            pot_drain <= \'0\';\n            atari_mode_a <= atari_paddles_a;\n'
                      M_TXT="mode of socket a taken over at the end of the discharge as well" ;;
      latch_plus1)    M_ARGS="-gG_PART=modes -gG_CYCLES=60 -gG_SEED=3"
                      M_OLD=$'        phi_counter <= phi_counter + 1;\n'
                      M_NEW=$'        phi_counter <= phi_counter + 1;\n        if phi_counter = 0 and pot_counter = 0 then\n          atari_mode_a <= atari_paddles_a;\n          atari_mode_b <= atari_paddles_b;\n        end if;\n'
                      M_TXT="modes taken over one clock cycle after the latch tick" ;;
      swap)           M_ARGS="-gG_PART=mixed -gG_MODES=10 -gG_CYCLES=6"
                      M_OLD=$'          atari_mode_a <= atari_paddles_a;\n          atari_mode_b <= atari_paddles_b;'
                      M_NEW=$'          atari_mode_a <= atari_paddles_b;\n          atari_mode_b <= atari_paddles_a;'
                      M_TXT="sockets a and b exchanged" ;;
      drain_long)     M_ARGS="-gG_PART=powerup -gG_MODES=11 -gG_CYCLES=6"
                      M_OLD="          elsif pot_counter = 256  then"
                      M_NEW="          elsif (pot_counter = 256 and (atari_mode_a or atari_mode_b) = '0') or pot_counter = 257 then"
                      M_TXT="discharge one tick longer in a long cycle" ;;
      guard_255)      M_ARGS="-gG_PART=powerup -gG_MODES=01 -gG_CYCLES=8"
                      M_OLD="                if potb_y_counter /= 510 then"
                      M_NEW="                if potb_y_counter /= 255 then"
                      M_TXT="counter of an Atari pin saturates at 255" ;;
      powerup_long)   M_ARGS="-gG_PART=powerup -gG_MODES=00 -gG_CYCLES=6"
                      M_OLD="  signal atari_mode_b : std_logic := '0';"
                      M_NEW="  signal atari_mode_b : std_logic := '1';"
                      M_TXT="socket b in Atari mode at power-up" ;;
      c64_halved)     M_ARGS="-gG_PART=identity -gG_CYCLES=4"
                      M_OLD="            potb_x_internal <= to_unsigned(potb_x_counter,8);"
                      M_NEW="            potb_x_internal <= to_unsigned(potb_x_counter / 2,8);"
                      M_TXT="C64 result of socket b halved" ;;
   esac
}

# run_mutant <name>: builds and runs one mutant; writes its report line to $BUILD/mut_<name>.txt
run_mutant() {
   local m=$1 dir="$BUILD/mut_$1"
   mutant_def "$m"
   mkdir -p "$dir"
   if ! mutate "$SRC" "$dir/mouse_input.vhdl" "$M_OLD" "$M_NEW" > "$dir/pattern.txt"; then
      echo "PATTERN  $m: $(cat "$dir/pattern.txt")" > "$BUILD/mut_$m.txt"
   elif ! build "$dir" "$dir/mouse_input.vhdl" > "$dir/build.txt"; then
      echo "REJECTED $m ($M_TXT): does not build: $(head -1 "$dir/build.txt" | sed 's/^ *//')" > "$BUILD/mut_$m.txt"
   elif sim "$dir" "$dir/run.log" $M_ARGS; then
      echo "SURVIVED $m ($M_TXT)" > "$BUILD/mut_$m.txt"
   else
      echo "REJECTED $m ($M_TXT; ${M_ARGS//-gG_/}): $(grep -m1 -E 'TB_ERROR|error' "$dir/run.log.tb" | sed 's/^ *//' | cut -c1-150)" > "$BUILD/mut_$m.txt"
   fi
}

if want mutants; then
   echo "=== mutants of mouse_input.vhdl (each must be rejected)"
   set -- $MUTANTS
   while [ $# -gt 0 ]; do
      run_mutant "$1" & P1=$!
      P2=""
      if [ $# -gt 1 ]; then run_mutant "$2" & P2=$!; fi
      wait $P1; [ -n "$P2" ] && wait $P2
      cat "$BUILD/mut_$1.txt"; [ -n "$P2" ] && cat "$BUILD/mut_$2.txt"
      shift; [ $# -gt 0 ] && shift
   done | sed 's/^/    /'
   for m in $MUTANTS; do
      case "$(cut -c1-8 "$BUILD/mut_$m.txt" 2>/dev/null)" in
         REJECTED) ;;
         SURVIVED) note_fail "mutant_${m}_not_detected" ;;
         *)        note_fail "mutant_${m}_pattern" ;;
      esac
   done
fi

# --------------------------------------------------------------------------------------------------
if [ $KEEP -eq 1 ]; then
   echo "build directory kept: $BUILD"
else
   rm -rf "$BUILD"
fi
if [ -z "$FAILS" ]; then
   echo "RESULT: PASS"
   exit 0
fi
echo "RESULT: FAIL:$FAILS"
exit 1
