#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Caps Lock benches (GitHub issue #261), see README.md
#
#   CORE/vhdl/test/tb_capslock/run.sh [keyb|decode|wiring|all] [--keep]
#
#   keyb    the M2M keyboard chain with a behavioral MEGA65 keyboard (tb_capslock_keyb.vhd),
#           Caps Lock off and on at power-on, plus two mutants of m2m_keyb.vhd that must fail
#   decode  the turbo decode of CORE/vhdl/mega65.vhd, copied verbatim into tb_capslock_decode.vhd,
#           all combinations, plus two mutants that must fail
#   wiring  GHDL analysis and elaboration of the four board top files against the real entity
#           declarations of framework and MEGA65_Core; differential analysis (base commit versus
#           working tree) of framework.vhd and mega65.vhd; mutants that must be caught
#   all     everything (default)
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime about 30 s.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=522e5fc        # WIP-V6-A22X1: the last commit before the Caps Lock turbo

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      keyb|decode|wiring|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [keyb|decode|wiring|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_capslock.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
   { echo "cannot create a build directory"; exit 1; }
FAILS=""
note_fail() { FAILS="$FAILS $1"; echo "  FAIL: $1"; }
want() { [ "$WHAT" = all ] || [ "$WHAT" = "$1" ]; }

# analyze files into a library directory; prints the diagnostics on failure
analyze() {
   local lib=$1; shift
   mkdir -p "$lib"
   "$GHDL" -a $GF --workdir="$lib" "$@" > "$lib/analyze.log" 2>&1 || { sed 's/^/    /' "$lib/analyze.log" | head -20; return 1; }
}

# run_tb <lib> <unit> <log> [args]: elaborate and run a bench (10 min timeout); prints its TB lines;
# returns 0 only if the bench ran to the end and reported "TB: RESULT PASS"
run_tb() {
   local lib=$1 unit=$2 log=$3; shift 3
   ( cd "$lib" && "$GHDL" -e $GF --workdir=. "$unit" ) > "$log.elab" 2>&1 || { sed 's/^/    /' "$log.elab" | head -20; return 1; }
   python3 - "$GHDL" "$lib" "$unit" "$log" "$@" <<'PYEOF'
import subprocess, sys
ghdl, lib, unit, log = sys.argv[1:5]
args = sys.argv[5:]
try:
    r = subprocess.run([ghdl, "-r", "--std=08", "-frelaxed", "--workdir=.", unit] + args,
                       cwd=lib, capture_output=True, text=True, timeout=600)
    out, rc = r.stdout + r.stderr, r.returncode
except subprocess.TimeoutExpired:
    out, rc = "TIMEOUT\n", 1
open(log, "w").write(out)
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
        print("    " + l)
sys.exit(0 if rc == 0 and "TB: RESULT PASS" in out else 1)
PYEOF
}

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

KEYB_SRC="$REPO/M2M/vhdl/controllers/M65/kb_matrix_ram.vhdl
          $REPO/M2M/vhdl/controllers/M65/mega65kbd_to_matrix.vhdl
          $REPO/M2M/vhdl/controllers/M65/matrix_to_keynum.vhdl"

# --------------------------------------------------------------------------------------------------
if want keyb; then
   echo "=== keyboard chain (tb_capslock_keyb)"
   L="$BUILD/keyb"
   if analyze "$L" $KEYB_SRC "$REPO/M2M/vhdl/m2m_keyb.vhd" "$HERE/tb_capslock_keyb.vhd"; then
      echo "  Caps Lock off at power-on:"
      run_tb "$L" tb_capslock_keyb "$BUILD/keyb_off.log" -gG_START_ON=false || note_fail keyb_start_off
      echo "  Caps Lock on at power-on (the LED is the truth):"
      run_tb "$L" tb_capslock_keyb "$BUILD/keyb_on.log" -gG_START_ON=true || note_fail keyb_start_on
   else
      note_fail keyb_analyze
   fi

   # mutants the bench must reject
   for m in gate filter; do
      M="$BUILD/keyb_mut_$m"
      mkdir -p "$M"
      case $m in
         gate)   mutate "$REPO/M2M/vhdl/m2m_keyb.vhd" "$M/m2m_keyb.vhd" \
                    "capslock_n_o      <= capslock_n;" "capslock_n_o      <= capslock_n when enable_core_i else '1';" ;;
         filter) mutate "$REPO/M2M/vhdl/m2m_keyb.vhd" "$M/m2m_keyb.vhd" \
                    "elsif capslock_cnt >= clk_main_speed_i / 250 then" "elsif true then" ;;
      esac || { note_fail "keyb_mutant_${m}_pattern"; continue; }
      if analyze "$M" $KEYB_SRC "$M/m2m_keyb.vhd" "$HERE/tb_capslock_keyb.vhd" &&
         run_tb "$M" tb_capslock_keyb "$M/run.log" -gG_START_ON=false > "$M/tb.txt"; then
         note_fail "keyb_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -m1 TB_ERROR "$M/tb.txt" | sed 's/^ *//')"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
# gen_decode <mega65.vhd> <bench.vhd>: fill the template with the current decode of mega65.vhd
gen_decode() {
   python3 - "$1" "$HERE/tb_capslock_decode.vhd.in" "$2" <<'PYEOF'
import re, sys
m65, tmpl, out = sys.argv[1:4]
src = open(m65).read().splitlines()
consts = [l for l in src if re.match(r"\s*constant C_MENU_TURBO_\w+\s*:\s*natural\s*:=\s*\d+;", l)]
start = [i for i, l in enumerate(src) if re.match(r"\s*c64_turbo_mode\(0\)\s*<=", l)]
if len(consts) != 6 or len(start) != 1:
    print(f"    mega65.vhd: found {len(consts)} C_MENU_TURBO_* constants (expected 6) and "
          f"{len(start)} decode starts (expected 1)")
    sys.exit(1)
# copy from "c64_turbo_mode(0) <=" up to the ";" that ends the c64_turbo_speed assignment
i, decode, in_speed = start[0], [], False
while i < len(src) and len(decode) <= 12:
    decode.append(src[i])
    if re.match(r"\s*c64_turbo_speed\s*<=", src[i]):
        in_speed = True
    if in_speed and src[i].split("--")[0].rstrip().endswith(";"):
        break
    i += 1
else:
    print("    mega65.vhd: end of the c64_turbo_speed assignment not found")
    sys.exit(1)
t = open(tmpl).read()
t = t.replace("-- @MEGA65_CONSTANTS@", "\n".join(consts))
t = t.replace("-- @MEGA65_DECODE@", "\n".join(decode))
open(out, "w").write(t)
print(f"    copied {len(consts)} constants and {len(decode)} decode lines from mega65.vhd")
PYEOF
}

if want decode; then
   echo "=== turbo decode of mega65.vhd (tb_capslock_decode)"
   L="$BUILD/decode"
   mkdir -p "$L"
   if gen_decode "$REPO/CORE/vhdl/mega65.vhd" "$L/tb_capslock_decode.vhd" &&
      analyze "$L" "$L/tb_capslock_decode.vhd"; then
      run_tb "$L" tb_capslock_decode "$L/run.log" || note_fail decode
   else
      note_fail decode_build
   fi

   for m in c128 speed; do
      M="$BUILD/decode_mut_$m"
      mkdir -p "$M"
      case $m in
         c128)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                   "main_osm_control_i(C_MENU_TURBO_C128) and main_kb_capslock_n_i;" "main_osm_control_i(C_MENU_TURBO_C128);" ;;
         speed) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                   "when main_kb_capslock_n_i = '0' or main_osm_control_i(C_MENU_TURBO_4X)" "when main_osm_control_i(C_MENU_TURBO_4X)" ;;
      esac || { note_fail "decode_mutant_${m}_pattern"; continue; }
      if gen_decode "$M/mega65.vhd" "$M/tb_capslock_decode.vhd" > /dev/null &&
         analyze "$M" "$M/tb_capslock_decode.vhd" &&
         run_tb "$M" tb_capslock_decode "$M/run.log" > "$M/tb.txt"; then
         note_fail "decode_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -c TB_ERROR "$M/tb.txt") wrong cases"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
PKGS="$REPO/M2M/QNICE/vhdl/tools.vhd
      $REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd
      $REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd
      $REPO/CORE/vhdl/globals.vhd"

# shell <file> <entity> <out>: the entity declaration of <file> (with its context clause, without
# the Xilinx libraries) plus an empty architecture
shell() {
   python3 - "$@" <<'PYEOF'
import re, sys
src, ent, out = sys.argv[1:4]
lines = open(src).read().splitlines()
s = next(i for i, l in enumerate(lines) if re.match(rf"\s*entity\s+{ent}\s+is\b", l, re.I))
e = next(i for i in range(s, len(lines)) if re.match(rf"\s*end(\s+entity)?(\s+{ent})?\s*;", lines[i], re.I))
ctx = [l for l in lines[:s] if re.match(r"\s*(library|use)\b", l, re.I) and not re.search(r"\b(xpm|unisim)\b", l, re.I)]
open(out, "w").write("\n".join(ctx + lines[s:e + 1] + [f"architecture shell of {ent} is begin end architecture shell;", ""]))
PYEOF
}

# diags <lib> <file>: analyze file (Xilinx library clauses removed) and print its normalized
# diagnostics (file names and positions stripped), one per line, sorted
diags() {
   local lib=$1 f=$2
   grep -v -i -E "^\s*(library|use)\s+(xpm|unisim)\b" "$f" > "$lib/$(basename "$f").nox.vhd"
   "$GHDL" -a $GF --workdir="$lib" "$lib/$(basename "$f").nox.vhd" 2>&1 |
      sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//' | sort
}

if want wiring; then
   echo "=== wiring: board top files, framework.vhd, mega65.vhd"
   L="$BUILD/wiring"
   mkdir -p "$L"
   shell "$REPO/M2M/vhdl/framework.vhd" framework "$L/framework_shell.vhd" &&
   shell "$REPO/CORE/vhdl/mega65.vhd" MEGA65_Core "$L/mega65_shell.vhd" &&
   shell "$REPO/M2M/vhdl/controllers/M65/audio.vhd" audio "$L/audio_shell.vhd" &&
   shell "$REPO/M2M/vhdl/controllers/M65/max10.vhdl" max10 "$L/max10_shell.vhd" &&
   shell "$REPO/M2M/vhdl/controllers/M65/pcm_to_pdm.vhdl" pcm_to_pdm "$L/pcm_to_pdm_shell.vhd" || note_fail wiring_shells
   if analyze "$L" $PKGS "$L/framework_shell.vhd" "$L/mega65_shell.vhd" "$L/audio_shell.vhd" \
                   "$L/max10_shell.vhd" "$L/pcm_to_pdm_shell.vhd"; then
      for r in 3 4 5 6; do
         TOP="$REPO/M2M/vhdl/top_mega65-r$r.vhd"
         ENT=$(sed -n -E 's/^entity ([A-Za-z0-9_]+) is.*/\1/p' "$TOP" | head -1)
         cp -R "$L" "$BUILD/wiring_r$r"
         if analyze "$BUILD/wiring_r$r" "$TOP" &&
            ( cd "$BUILD/wiring_r$r" && "$GHDL" -e $GF --workdir=. "$ENT" ) > "$BUILD/wiring_r$r/elab.log" 2>&1; then
            echo "  top_mega65-r$r.vhd ($ENT): analysis and elaboration OK"
         else
            sed 's/^/    /' "$BUILD/wiring_r$r/elab.log" 2>/dev/null | head -10
            note_fail "wiring_r$r"
         fi
      done
      # mutant: an unconnected Caps Lock input of MEGA65_Core must be caught
      M="$BUILD/wiring_mut_top"
      cp -R "$L" "$M"
      if mutate "$REPO/M2M/vhdl/top_mega65-r6.vhd" "$M/top.vhd" \
            "         main_kb_capslock_n_i    => main_capslock_n," ""; then
         if analyze "$M" "$M/top.vhd" > /dev/null &&
            ( cd "$M" && "$GHDL" -e $GF --workdir=. mega65_r6 ) > "$M/elab.log" 2>&1; then
            note_fail wiring_mutant_top_not_detected
         else
            echo "  mutant 'unconnected main_kb_capslock_n_i' rejected: $(grep -m1 -i error "$M/elab.log" "$M/analyze.log" 2>/dev/null | sed -E 's/^[^:]*:[^:]*:[0-9]+:[0-9]+:[ ]*//' | head -1)"
         fi
      else
         note_fail wiring_mutant_top_pattern
      fi
   else
      note_fail wiring_analyze
   fi

   # differential analysis: the full framework.vhd and mega65.vhd of the base commit and of the
   # working tree in identical libraries (packages, keyboard chain, current m2m_keyb); the sub-entities
   # that are not in the library produce the same "not found" diagnostics in both, everything else
   # (signal and port names, types, the m2m_keyb port map) is checked
   D="$BUILD/diff"
   if analyze "$D/lib" $PKGS $KEYB_SRC "$REPO/M2M/vhdl/m2m_keyb.vhd"; then
      for f in M2M/vhdl/framework.vhd CORE/vhdl/mega65.vhd; do
         n=$(basename "$f" .vhd)
         mkdir -p "$D/base_$n" "$D/new_$n"
         cp -R "$D/lib/." "$D/base_$n/"
         cp -R "$D/lib/." "$D/new_$n/"
         git -C "$REPO" show "$BASE:$f" > "$D/base_$n/$n.vhd" 2>/dev/null || { note_fail "diff_${n}_base_missing"; continue; }
         diags "$D/base_$n" "$D/base_$n/$n.vhd" > "$D/$n.base.txt"
         diags "$D/new_$n" "$REPO/$f" > "$D/$n.new.txt"
         if diff "$D/$n.base.txt" "$D/$n.new.txt" > "$D/$n.diff"; then
            echo "  $f: $(wc -l < "$D/$n.new.txt" | tr -d ' ') diagnostics, identical to $BASE (no new ones)"
         else
            sed 's/^/    /' "$D/$n.diff" | head -10
            note_fail "diff_$n"
         fi
      done
      # mutant: a wrong formal in the m2m_keyb port map of framework.vhd must show up
      M="$BUILD/diff_mut"
      mkdir -p "$M"
      cp -R "$D/lib/." "$M/"
      if mutate "$REPO/M2M/vhdl/framework.vhd" "$M/framework.vhd" \
            "capslock_n_o         => main_capslock_n_o," "capslock_nx_o        => main_capslock_n_o,"; then
         diags "$M" "$M/framework.vhd" > "$M/framework.txt"
         if diff "$D/framework.base.txt" "$M/framework.txt" > /dev/null; then
            note_fail diff_mutant_not_detected
         else
            echo "  mutant 'wrong m2m_keyb formal' rejected: $(diff "$D/framework.base.txt" "$M/framework.txt" | grep -m1 '^> error' | cut -c3-)"
         fi
      else
         note_fail diff_mutant_pattern
      fi
   else
      note_fail diff_lib
   fi
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
