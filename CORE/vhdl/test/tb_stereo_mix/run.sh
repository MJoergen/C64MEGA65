#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Stereo Mix benches (GitHub issue #247), see README.md
#
#   CORE/vhdl/test/tb_stereo_mix/run.sh [mix|decode|wiring|all] [--keep]
#
#   mix     the audio path of CORE/vhdl/main.vhd (crossfeed + master volume), copied verbatim into
#           tb_stereo_mix.vhd, against golden.py (MiSTer's aud_mix_top), plus mutants that must fail
#   decode  the Stereo Mix decoder of CORE/vhdl/mega65.vhd (a register that holds its value while
#           no item is selected), copied verbatim into tb_stereo_mix_decode.vhd: power-up value,
#           every item, hold, every transition torn both ways; plus mutants that must fail
#   wiring  differential GHDL analysis (base commit versus working tree) of main.vhd and of
#           mega65.vhd (against the entity declaration of main of the same tree); mutants that
#           must be caught
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
BASE=1470473        # WIP-V6-A22X2: the last commit before the Stereo Mix

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      mix|decode|wiring|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [mix|decode|wiring|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_stereo_mix.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
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

# mutate <src> <dst> <old> <new> [<old> <new> ...]: copy src to dst with each old (which must occur
# exactly once in src) replaced by its new; the pairs are applied simultaneously, so two of them can
# swap texts
mutate() {
   python3 - "$@" <<'PYEOF'
import sys
src, dst, pairs = sys.argv[1], sys.argv[2], sys.argv[3:]
s = open(src).read()
subs = list(zip(pairs[0::2], pairs[1::2]))
for old, _ in subs:
    if s.count(old) != 1:
        print(f"    mutant pattern found {s.count(old)} times (expected once): {old!r}")
        sys.exit(1)
marks = []
for k, (old, new) in enumerate(subs):
    mark = f"\x00MUTANT{k}\x00"
    s = s.replace(old, mark)
    marks.append((mark, new))
for mark, new in marks:
    s = s.replace(mark, new)
open(dst, "w").write(s)
PYEOF
}

# --------------------------------------------------------------------------------------------------
# gen_mix <main.vhd> <bench.vhd>: fill the template with the current audio path of main.vhd
gen_mix() {
   python3 - "$1" "$HERE/tb_stereo_mix.vhd.in" "$2" <<'PYEOF'
import re, sys
main, tmpl, out = sys.argv[1:4]
src = open(main).read().splitlines()

def block(start_re, end_re, what):
    s = [i for i, l in enumerate(src) if re.match(start_re, l)]
    if len(s) != 1:
        print(f"    main.vhd: found {len(s)} starts of {what} (expected 1)")
        sys.exit(1)
    for j in range(s[0], min(s[0] + 120, len(src))):
        if re.match(end_re, src[j]):
            return src[s[0]:j + 1]
    print(f"    main.vhd: end of {what} not found")
    sys.exit(1)

decls = block(r"\s*type\s+vol_lut_t\s+is\b", r".*\);\s*(--.*)?$", "the volume LUT type")
decls += block(r"\s*constant\s+C_VOL_LUT\s*:", r".*\);\s*(--.*)?$", "the volume LUT")
mixp = block(r"\s*audio_stereo_mix_proc\s*:\s*process\b", r"\s*end\s+process\s+audio_stereo_mix_proc\s*;", "audio_stereo_mix_proc")
volp = block(r"\s*audio_volume_proc\s*:\s*process\b", r"\s*end\s+process\s+audio_volume_proc\s*;", "audio_volume_proc")
t = open(tmpl).read()
t = t.replace("-- @MAIN_DECLS@", "\n".join(decls))
t = t.replace("-- @MAIN_PROCS@", "\n".join(mixp + [""] + volp))
open(out, "w").write(t)
print(f"    copied the volume LUT ({len(decls)} lines), audio_stereo_mix_proc ({len(mixp)} lines) "
      f"and audio_volume_proc ({len(volp)} lines) from main.vhd")
PYEOF
}

if want mix; then
   echo "=== audio path of main.vhd (tb_stereo_mix)"
   L="$BUILD/mix"
   mkdir -p "$L"
   python3 "$HERE/golden.py" lut "$REPO/CORE/vhdl/main.vhd" || note_fail mix_lut
   if python3 "$HERE/golden.py" vectors "$L/vectors.txt" &&
      python3 "$HERE/golden.py" stream "$L/stream.txt" &&
      gen_mix "$REPO/CORE/vhdl/main.vhd" "$L/tb_stereo_mix.vhd" &&
      analyze "$L" "$L/tb_stereo_mix.vhd"; then
      run_tb "$L" tb_stereo_mix "$L/run.log" -gG_VECTORS="$L/vectors.txt" -gG_STREAM="$L/stream.txt" || note_fail mix
   else
      note_fail mix_build
   fi

   # mutants the bench must reject
   for m in wide narrow mono bypass swap comb; do
      M="$BUILD/mix_mut_$m"
      mkdir -p "$M"
      case $m in
         wide)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "lm := l - shift_right(l, 3) + shift_right(r, 3);" "lm := l - shift_right(l, 3) + shift_right(r, 2);" ;;
         narrow) mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "rm := r - shift_right(r, 2) + shift_right(l, 2);" "rm := r - shift_right(r, 2) + shift_right(r, 2);" ;;
         mono)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "rm := lm;" "rm := shift_right(r, 1) + shift_right(r, 1);" ;;
         bypass) mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "prod_r        := mix_r * gain;" "prod_r        := signed(aro) * gain;" ;;
         swap)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    'when "01" =>                                            -- Wide Stereo' \
                    'when "10" =>                                            -- Wide Stereo' \
                    'when "10" =>                                            -- Narrow Stereo' \
                    'when "01" =>                                            -- Narrow Stereo' ;;
         comb)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "audio_stereo_mix_proc : process (clk_main_i)" "audio_stereo_mix_proc : process (all)" \
                    $'    if rising_edge(clk_main_i) then\n      l := resize(signed(alo), 17);' \
                    $'    if true then\n      l := resize(signed(alo), 17);' ;;
      esac || { note_fail "mix_mutant_${m}_pattern"; continue; }
      # a mutant must be valid VHDL and run; only a bench that runs and reports mismatches counts
      if ! { gen_mix "$M/main.vhd" "$M/tb_stereo_mix.vhd" > /dev/null &&
             analyze "$M" "$M/tb_stereo_mix.vhd" > /dev/null; }; then
         note_fail "mix_mutant_${m}_does_not_build"
      elif run_tb "$M" tb_stereo_mix "$M/run.log" -gG_VECTORS="$L/vectors.txt" -gG_STREAM="$L/stream.txt" > "$M/tb.txt"; then
         note_fail "mix_mutant_${m}_not_detected"
      elif grep -q 'mismatches' "$M/tb.txt"; then
         echo "  mutant '$m' rejected: $(grep 'mismatches' "$M/tb.txt" | sed -E 's/^ *TB: //; s/ \(Full.*\)//' | tr '\n' ';' | sed 's/;$//; s/;/; /')"
      else
         note_fail "mix_mutant_${m}_did_not_run"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
# gen_decode <mega65.vhd> <bench.vhd>: fill the template with the current decode of mega65.vhd
gen_decode() {
   python3 - "$1" "$HERE/tb_stereo_mix_decode.vhd.in" "$2" <<'PYEOF'
import re, sys
m65, tmpl, out = sys.argv[1:4]
src = open(m65).read().splitlines()

def fail(msg):
    print("    mega65.vhd: " + msg)
    sys.exit(1)

consts = [l for l in src if re.match(r"\s*constant C_MENU_STEREO_MIX_\w+\s*:\s*natural\s*:=\s*\d+;", l)]
if len(consts) != 4:
    fail(f"found {len(consts)} C_MENU_STEREO_MIX_* constants (expected 4)")
sigs = [l for l in src if re.match(r"\s*signal main_stereo_mix\s*:", l)]
if len(sigs) != 1:
    fail(f"found {len(sigs)} declarations of main_stereo_mix (expected 1)")
start = [i for i, l in enumerate(src) if re.match(r"\s*stereo_mix_decode_proc\s*:\s*process\b", l)]
if len(start) != 1:
    fail(f"found {len(start)} stereo_mix_decode_proc (expected 1)")
end = [i for i in range(start[0], len(src)) if re.match(r"\s*end process stereo_mix_decode_proc\s*;", src[i])]
if not end:
    fail("end of stereo_mix_decode_proc not found")
decode = src[start[0]:end[0] + 1]
# the process must be the only driver of main_stereo_mix
outside = [i + 1 for i, l in enumerate(src)
           if re.search(r"\bmain_stereo_mix\s*<=", l.split("--")[0]) and not start[0] <= i <= end[0]]
if outside:
    fail(f"main_stereo_mix is also assigned outside of stereo_mix_decode_proc, line(s) {outside}")
t = open(tmpl).read()
t = t.replace("-- @MEGA65_CONSTANTS@", "\n".join(consts))
t = t.replace("-- @MEGA65_SIGNALS@", "\n".join(sigs))
t = t.replace("-- @MEGA65_DECODE@", "\n".join(decode))
open(out, "w").write(t)
print(f"    copied {len(consts)} constants, the declaration of main_stereo_mix and stereo_mix_decode_proc "
      f"({len(decode)} lines) from mega65.vhd")
PYEOF
}

if want decode; then
   echo "=== Stereo Mix decode of mega65.vhd (tb_stereo_mix_decode)"
   L="$BUILD/decode"
   mkdir -p "$L"
   if gen_decode "$REPO/CORE/vhdl/mega65.vhd" "$L/tb_stereo_mix_decode.vhd" &&
      analyze "$L" "$L/tb_stereo_mix_decode.vhd"; then
      run_tb "$L" tb_stereo_mix_decode "$L/run.log" || note_fail decode
   else
      note_fail decode_build
   fi

   # comb: the combinational decoder that decodes the empty selection to Full Stereo (no register,
   #       no power-up value); nohold: a register that falls back to Full Stereo when no bit is set;
   #       swap: Wide decoded from the Narrow bit; nomono: Mono missing; nofull: the Full Stereo bit
   #       ignored; noinit: no power-up value; badinit: Mono as the power-up value; third: Wide and
   #       Narrow set together decode to Mono (only the "both bits set" phase can see it)
   for m in comb nohold swap nomono nofull noinit badinit third; do
      M="$BUILD/decode_mut_$m"
      mkdir -p "$M"
      case $m in
         comb)    mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     "stereo_mix_decode_proc : process (main_clk_o)" "stereo_mix_decode_proc : process (all)" \
                     $'      if rising_edge(main_clk_o) then\n         if main_osm_control_i(C_MENU_STEREO_MIX_WIDE) = \'1\' then' \
                     $'      if true then\n         main_stereo_mix <= "00";\n         if main_osm_control_i(C_MENU_STEREO_MIX_WIDE) = \'1\' then' \
                     'std_logic_vector(1 downto 0) := "00";  -- OSM "Stereo Mix"' 'std_logic_vector(1 downto 0);  -- OSM "Stereo Mix"' ;;
         nohold)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     "elsif main_osm_control_i(C_MENU_STEREO_MIX_FULL) = '1' then" "else" ;;
         swap)    mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     "main_osm_control_i(C_MENU_STEREO_MIX_WIDE)" "main_osm_control_i(C_MENU_STEREO_MIX_NARROW)" ;;
         nomono)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     $'         elsif main_osm_control_i(C_MENU_STEREO_MIX_MONO) = \'1\' then\n            main_stereo_mix <= "11";\n' "" ;;
         nofull)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     $'         elsif main_osm_control_i(C_MENU_STEREO_MIX_FULL) = \'1\' then\n            main_stereo_mix <= "00";\n' "" ;;
         noinit)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     'std_logic_vector(1 downto 0) := "00";  -- OSM "Stereo Mix"' 'std_logic_vector(1 downto 0);  -- OSM "Stereo Mix"' ;;
         badinit) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     'std_logic_vector(1 downto 0) := "00";  -- OSM "Stereo Mix"' 'std_logic_vector(1 downto 0) := "11";  -- OSM "Stereo Mix"' ;;
         third)   mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                     'main_stereo_mix <= "01";' 'main_stereo_mix <= "01" or (main_osm_control_i(C_MENU_STEREO_MIX_NARROW) & '\''0'\'');' ;;
      esac || { note_fail "decode_mutant_${m}_pattern"; continue; }
      # a mutant must be valid VHDL and run; only a bench that runs and reports errors counts
      if ! { gen_decode "$M/mega65.vhd" "$M/tb_stereo_mix_decode.vhd" > /dev/null &&
             analyze "$M" "$M/tb_stereo_mix_decode.vhd" > /dev/null; }; then
         note_fail "decode_mutant_${m}_does_not_build"
      elif run_tb "$M" tb_stereo_mix_decode "$M/run.log" > "$M/tb.txt"; then
         note_fail "decode_mutant_${m}_not_detected"
      elif grep -q TB_ERROR "$M/tb.txt"; then
         echo "  mutant '$m' rejected: $(grep -m1 'TB: [0-9]* checks' "$M/tb.txt" | sed -E 's/^ *TB: //')"
         echo "     first error: $(grep -m1 TB_ERROR "$M/tb.txt" | sed -E 's/^ *TB_ERROR: //')"
      else
         note_fail "decode_mutant_${m}_did_not_run"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
PKGS="$REPO/M2M/QNICE/vhdl/tools.vhd
      $REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd
      $REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd
      $REPO/CORE/vhdl/globals.vhd"

# vdrives_pkg <vdrives.vhd> <out>: the package vdrives_pkg only (the entity needs Xilinx libraries)
vdrives_pkg() {
   python3 - "$@" <<'PYEOF'
import re, sys
src, out = sys.argv[1:3]
lines = open(src).read().splitlines()
s = next(i for i, l in enumerate(lines) if re.match(r"\s*package\s+vdrives_pkg\s+is\b", l, re.I))
e = next(i for i in range(s, len(lines)) if re.match(r"\s*end(\s+package)?(\s+vdrives_pkg)?\s*;", lines[i], re.I))
open(out, "w").write("\n".join(["library ieee;", "use ieee.std_logic_1164.all;",
                                "use ieee.numeric_std.all;", ""] + lines[s:e + 1] + [""]))
PYEOF
}

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
   echo "=== wiring: differential analysis of main.vhd and mega65.vhd against $BASE"
   D="$BUILD/diff"
   mkdir -p "$D"
   if vdrives_pkg "$REPO/M2M/vhdl/vdrives.vhd" "$D/vdrives_pkg.vhd" &&
      analyze "$D/lib" $PKGS "$D/vdrives_pkg.vhd"; then
      # main.vhd: base versus working tree in identical libraries; its sub-entities are not in the
      # library and produce the same "not found" diagnostics in both, everything else (signals,
      # types, the new port and the crossfeed process) is checked
      mkdir -p "$D/base_main" "$D/new_main"
      cp -R "$D/lib/." "$D/base_main/"
      cp -R "$D/lib/." "$D/new_main/"
      if git -C "$REPO" show "$BASE:CORE/vhdl/main.vhd" > "$D/base_main/main.vhd" 2>/dev/null; then
         diags "$D/base_main" "$D/base_main/main.vhd" > "$D/main.base.txt"
         diags "$D/new_main" "$REPO/CORE/vhdl/main.vhd" > "$D/main.new.txt"
         if diff "$D/main.base.txt" "$D/main.new.txt" > "$D/main.diff"; then
            echo "  CORE/vhdl/main.vhd: $(wc -l < "$D/main.new.txt" | tr -d ' ') diagnostics, identical to $BASE (no new ones)"
         else
            sed 's/^/    /' "$D/main.diff" | head -10
            note_fail diff_main
         fi
      else
         note_fail diff_main_base_missing
      fi

      # mega65.vhd: each tree against the entity declaration of main of the same tree, so the
      # port map of i_main is checked against the real ports (a missing or misspelled
      # association of audio_stereo_mix_i shows up as a new diagnostic)
      for t in base new; do
         mkdir -p "$D/${t}_m65"
         cp -R "$D/lib/." "$D/${t}_m65/"
         if [ $t = base ]; then
            git -C "$REPO" show "$BASE:CORE/vhdl/main.vhd" > "$D/${t}_m65/main_src.vhd" &&
            git -C "$REPO" show "$BASE:CORE/vhdl/mega65.vhd" > "$D/${t}_m65/mega65.vhd" || note_fail diff_m65_base_missing
         else
            cp "$REPO/CORE/vhdl/main.vhd" "$D/${t}_m65/main_src.vhd"
            cp "$REPO/CORE/vhdl/mega65.vhd" "$D/${t}_m65/mega65.vhd"
         fi
         shell "$D/${t}_m65/main_src.vhd" main "$D/${t}_m65/main_shell.vhd" &&
         analyze "$D/${t}_m65" "$D/${t}_m65/main_shell.vhd" || note_fail "diff_m65_${t}_shell"
      done
      diags "$D/base_m65" "$D/base_m65/mega65.vhd" > "$D/m65.base.txt"
      diags "$D/new_m65" "$D/new_m65/mega65.vhd" > "$D/m65.new.txt"
      if diff "$D/m65.base.txt" "$D/m65.new.txt" > "$D/m65.diff"; then
         echo "  CORE/vhdl/mega65.vhd: $(wc -l < "$D/m65.new.txt" | tr -d ' ') diagnostics, identical to $BASE (no new ones)"
      else
         sed 's/^/    /' "$D/m65.diff" | head -10
         note_fail diff_mega65
      fi

      # mutants: an unconnected Stereo Mix port in mega65.vhd and an undeclared signal in the
      # volume stage of main.vhd must both show up as new diagnostics
      M="$BUILD/diff_mut_port"
      mkdir -p "$M"
      cp -R "$D/new_m65/." "$M/"
      if mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65_mut.vhd" \
            "         audio_stereo_mix_i     => main_stereo_mix," ""; then
         diags "$M" "$M/mega65_mut.vhd" > "$M/m65.txt"
         if diff "$D/m65.new.txt" "$M/m65.txt" > /dev/null; then
            note_fail diff_mutant_port_not_detected
         else
            echo "  mutant 'unconnected audio_stereo_mix_i' rejected: $(diff "$D/m65.new.txt" "$M/m65.txt" | grep -m1 '^> .*error' | cut -c3-)"
         fi
      else
         note_fail diff_mutant_port_pattern
      fi
      M="$BUILD/diff_mut_sig"
      mkdir -p "$M"
      cp -R "$D/lib/." "$M/"
      if mutate "$REPO/CORE/vhdl/main.vhd" "$M/main_mut.vhd" \
            "prod_l        := mix_l * gain;" "prod_l        := mixx_l * gain;"; then
         diags "$M" "$M/main_mut.vhd" > "$M/main.txt"
         if diff "$D/main.new.txt" "$M/main.txt" > /dev/null; then
            note_fail diff_mutant_sig_not_detected
         else
            echo "  mutant 'undeclared signal in main.vhd' rejected: $(diff "$D/main.new.txt" "$M/main.txt" | grep -m1 '^> .*error' | cut -c3-)"
         fi
      else
         note_fail diff_mutant_sig_pattern
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
