#!/usr/bin/env bash
# --------------------------------------------------------------------------------------------------
# Keyboard shortcuts benches (GitHub issue #142), see README.md
#
#   CORE/vhdl/test/tb_shortcuts/run.sh [keyb|qnice|decode|wiring|all] [--keep]
#
#   keyb    CORE/vhdl/keyboard.vhd (tb_shortcuts_keyb.vhd): freezer key resolution F9 .. F14,
#           Shift mask, autostart; plus two mutants of keyboard.vhd that must fail
#   qnice   the QNICE key bits 10 .. 13 of M2M/vhdl/m2m_keyb.vhd with a behavioral MEGA65 keyboard
#           (tb_shortcuts_qnice.vhd); plus a mutant that must fail
#   decode  the volume decoder and the freezer key bits of CORE/vhdl/mega65.vhd and the freezer
#           cartridge gate of CORE/vhdl/main.vhd, copied verbatim into tb_shortcuts_decode.vhd;
#           plus five mutants that must fail
#   wiring  differential GHDL analysis (base commit versus working tree) of main.vhd, mega65.vhd,
#           keyboard.vhd and m2m_keyb.vhd, once in identical libraries and once with the entity
#           declarations of the instantiated sub-entities (so the port maps are checked); plus two
#           mutants (unconnected freezer key ports) that must be caught
#   all     everything (default)
#
# Ends with "RESULT: PASS" (exit status 0) or "RESULT: FAIL ..." (exit status 1).
# Requirements: GHDL 5.1.1 (/usr/local/bin/ghdl or $GHDL), python3, git. Runtime about 1 minute.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../.." && pwd)
GHDL=${GHDL:-/usr/local/bin/ghdl}
GF="--std=08 -frelaxed"
BASE=1470473        # WIP-V6-A22X2: the last commit before the keyboard shortcuts

WHAT=all
KEEP=0
for a in "$@"; do
   case "$a" in
      keyb|qnice|decode|wiring|all) WHAT=$a ;;
      --keep) KEEP=1 ;;
      *) echo "usage: $0 [keyb|qnice|decode|wiring|all] [--keep]"; exit 2 ;;
   esac
done

BUILD=$(mktemp -d "${TMPDIR:-/tmp}/tb_shortcuts.XXXXXX") && [ -n "$BUILD" ] && [ -d "$BUILD" ] ||
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

# run_tb <lib> <unit> <log> [args]: elaborate and run a bench (10 min timeout); prints its TB lines
# (without the per-check OK lines); returns 0 only if the bench reported "TB: RESULT PASS"
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
oks = 0
for l in out.splitlines():
    for tag in ("(report note): ", "(report error): "):
        if tag in l:
            l = l.split(tag, 1)[1]
    if l.startswith("TB:") and (l.endswith(" OK") or l.endswith("matrix checked")):
        oks += 1
    elif l.startswith("TB") or "error" in l.lower() or l.startswith("TIMEOUT"):
        print("    " + l)
print(f"    ({oks} individual checks OK, full log: {log})")
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
   echo "=== keyboard.vhd (tb_shortcuts_keyb)"
   L="$BUILD/keyb"
   if analyze "$L" "$REPO/CORE/vhdl/keyboard.vhd" "$HERE/tb_shortcuts_keyb.vhd"; then
      run_tb "$L" tb_shortcuts_keyb "$BUILD/keyb.log" || note_fail keyb
   else
      note_fail keyb_analyze
   fi

   for m in latch mask; do
      M="$BUILD/keyb_mut_$m"
      mkdir -p "$M"
      case $m in
         latch) mutate "$REPO/CORE/vhdl/keyboard.vhd" "$M/keyboard.vhd" \
                   "if sc_down(i) = '0' then" "if true then" ;;
         mask)  mutate "$REPO/CORE/vhdl/keyboard.vhd" "$M/keyboard.vhd" \
                   "left_shift_n  <= key_pressed_n(m65_left_shift)  or sc_held;" "left_shift_n  <= key_pressed_n(m65_left_shift);" ;;
      esac || { note_fail "keyb_mutant_${m}_pattern"; continue; }
      if analyze "$M" "$M/keyboard.vhd" "$HERE/tb_shortcuts_keyb.vhd" &&
         run_tb "$M" tb_shortcuts_keyb "$M/run.log" > "$M/tb.txt"; then
         note_fail "keyb_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -m1 TB_ERROR "$M/tb.txt" | sed 's/^ *//')"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
if want qnice; then
   echo "=== QNICE key bits of m2m_keyb.vhd (tb_shortcuts_qnice)"
   L="$BUILD/qnice"
   if analyze "$L" $KEYB_SRC "$REPO/M2M/vhdl/m2m_keyb.vhd" "$HERE/tb_shortcuts_qnice.vhd"; then
      run_tb "$L" tb_shortcuts_qnice "$BUILD/qnice.log" || note_fail qnice
   else
      note_fail qnice_analyze
   fi

   M="$BUILD/qnice_mut_shift"
   mkdir -p "$M"
   if mutate "$REPO/M2M/vhdl/m2m_keyb.vhd" "$M/m2m_keyb.vhd" \
         "keys_n(13) <= shift_left_n and shift_right_n;" "keys_n(13) <= shift_left_n;"; then
      if analyze "$M" $KEYB_SRC "$M/m2m_keyb.vhd" "$HERE/tb_shortcuts_qnice.vhd" &&
         run_tb "$M" tb_shortcuts_qnice "$M/run.log" > "$M/tb.txt"; then
         note_fail qnice_mutant_shift_not_detected
      else
         echo "  mutant 'shift' rejected: $(grep -m1 TB_ERROR "$M/tb.txt" | sed 's/^ *//')"
      fi
   else
      note_fail qnice_mutant_shift_pattern
   fi
fi

# --------------------------------------------------------------------------------------------------
# gen_decode <mega65.vhd> <main.vhd> <bench.vhd>: fill the template with the current code
gen_decode() {
   python3 - "$1" "$2" "$HERE/tb_shortcuts_decode.vhd.in" "$3" <<'PYEOF'
import re, sys
m65, mainf, tmpl, out = sys.argv[1:5]
src = open(m65).read().splitlines()
main = open(mainf).read().splitlines()

def fail(msg):
    print("    " + msg)
    sys.exit(1)

def statement(lines, i):
    # the lines from i up to the one whose code (without comment) ends with ";"
    res = []
    while i < len(lines):
        res.append(lines[i])
        if lines[i].split("--")[0].rstrip().endswith(";"):
            return res
        i += 1
    fail("unterminated statement")

consts = [l for l in src if re.match(r"\s*subtype C_MENU_VOLUME\s+is\b", l) or
          re.match(r"\s*constant (C_MENU_VOLUME_100|C_MENU_SC_F\d+|C_SC_FREEZE)\s*:", l)]
if len(consts) != 9:
    fail(f"mega65.vhd: found {len(consts)} of the 9 constants")
sigs = [l for l in src if re.match(r"\s*signal (main_volume|main_sc_freeze)\s*:", l)]
if len(sigs) != 2:
    fail(f"mega65.vhd: found {len(sigs)} of the 2 signal declarations")

decode = []
start = [i for i, l in enumerate(src) if re.match(r"\s*volume_decode_proc\s*:\s*process\b", l)]
if len(start) != 1:
    fail(f"mega65.vhd: found {len(start)} volume_decode_proc")
i = start[0]
while i < len(src):
    decode.append(src[i])
    if re.match(r"\s*end process volume_decode_proc\s*;", src[i]):
        break
    i += 1
else:
    fail("mega65.vhd: end of volume_decode_proc not found")
asrt = [i for i, l in enumerate(src) if re.match(r"\s*assert C_MENU_VOLUME_100\b", l)]
if len(asrt) != 1:
    fail(f"mega65.vhd: found {len(asrt)} assertions on C_MENU_VOLUME_100")
decode += [""] + statement(src, asrt[0])
sc = [i for i, l in enumerate(src) if re.match(r"\s*main_sc_freeze\(\d\)\s*<=", l)]
if len(sc) != 6:
    fail(f"mega65.vhd: found {len(sc)} of the 6 main_sc_freeze assignments")
decode.append("")
for i in sc:
    decode += statement(src, i)

gate = [i for i, l in enumerate(main) if re.match(r"\s*crt_is_freezer\s*<=", l)]
fk = [l for l in main if re.match(r"\s*freeze_key_i\s*=>", l)]
if len(gate) != 1 or len(fk) != 1:
    fail(f"main.vhd: found {len(gate)} crt_is_freezer assignments and {len(fk)} freeze_key_i associations")
expr = fk[0].split("=>", 1)[1].split("--")[0].strip().rstrip(",").strip()
cart = statement(main, gate[0]) + ["   freeze_key <= " + expr + ";"]

t = open(tmpl).read()
t = t.replace("-- @MEGA65_CONSTANTS@", "\n".join(consts))
t = t.replace("-- @MEGA65_SIGNALS@", "\n".join(sigs))
t = t.replace("-- @MEGA65_DECODE@", "\n".join(decode))
t = t.replace("-- @MAIN_CART_GATE@", "\n".join(cart))
open(out, "w").write(t)
print(f"    copied {len(consts)} constants, {len(sigs)} signals, {len(decode)} decode lines from mega65.vhd "
      f"and {len(cart)} lines from main.vhd")
PYEOF
}

if want decode; then
   echo "=== decodes of mega65.vhd and the cartridge gate of main.vhd (tb_shortcuts_decode)"
   L="$BUILD/decode"
   mkdir -p "$L"
   if gen_decode "$REPO/CORE/vhdl/mega65.vhd" "$REPO/CORE/vhdl/main.vhd" "$L/tb_shortcuts_decode.vhd" &&
      analyze "$L" "$L/tb_shortcuts_decode.vhd"; then
      run_tb "$L" tb_shortcuts_decode "$L/run.log" || note_fail decode
   else
      note_fail decode_build
   fi

   for m in nohold freeze gate latch falling; do
      M="$BUILD/decode_mut_$m"
      mkdir -p "$M"
      cp "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd"
      cp "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd"
      case $m in
         nohold) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                    "         for b in C_MENU_VOLUME'low to C_MENU_VOLUME'high loop" \
                    "         main_volume <= 20;
         for b in C_MENU_VOLUME'low to C_MENU_VOLUME'high loop" ;;
         freeze) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                    "main_sc_freeze(3) <= main_osm_control_i(C_MENU_SC_F12 + C_SC_FREEZE);" \
                    "main_sc_freeze(3) <= main_osm_control_i(C_MENU_SC_F11 + C_SC_FREEZE);" ;;
         gate)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" \
                    "((not freeze_key_n) and crt_is_freezer)" "(not freeze_key_n)" ;;
         latch)  mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                    $'volume_decode_proc : process (main_clk_o)\n   begin\n      if rising_edge(main_clk_o) then' \
                    $'volume_decode_proc : process (all)\n   begin\n      if true then' ;;
         falling) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" \
                    $'      if rising_edge(main_clk_o) then\n         for b in C_MENU_VOLUME\'low' \
                    $'      if falling_edge(main_clk_o) then\n         for b in C_MENU_VOLUME\'low' ;;
      esac || { note_fail "decode_mutant_${m}_pattern"; continue; }
      if gen_decode "$M/mega65.vhd" "$M/main.vhd" "$M/tb_shortcuts_decode.vhd" > /dev/null &&
         analyze "$M" "$M/tb_shortcuts_decode.vhd" &&
         run_tb "$M" tb_shortcuts_decode "$M/run.log" > "$M/tb.txt"; then
         note_fail "decode_mutant_${m}_not_detected"
      else
         echo "  mutant '$m' rejected: $(grep -c TB_ERROR "$M/run.log") wrong cases"
      fi
   done
fi

# --------------------------------------------------------------------------------------------------
if want wiring; then
   echo "=== wiring: differential analysis against $BASE"
   W="$BUILD/wiring"
   mkdir -p "$W/xpm" "$W/seed" "$W/base" "$W/new"

   # Xilinx XPM stub library (component declarations), so that mega65.vhd analyzes completely
   "$GHDL" -a $GF --work=xpm --workdir="$W/xpm" "$REPO/doc/dev-ntsc/tools/stubs/xpm_vcomponents.vhd" > "$W/xpm.log" 2>&1 ||
      { sed 's/^/    /' "$W/xpm.log" | head; note_fail wiring_xpm; }

   # packages (the package parts of vdrives.vhd and qnice_csr.vhd are cut out) and the keyboard chain
   python3 - "$REPO" "$W" <<'PYEOF'
import re, sys
repo, w = sys.argv[1:3]
for src, pkg in (("M2M/vhdl/vdrives.vhd", "vdrives_pkg"), ("M2M/vhdl/qnice_csr.vhd", "qnice_csr_pkg")):
    lines = open(f"{repo}/{src}").read().splitlines()
    s = next(i for i, l in enumerate(lines) if re.match(rf"\s*package\s+{pkg}\s+is\b", l, re.I))
    e = next(i for i in range(s, len(lines)) if re.match(rf"\s*end(\s+package)?(\s+{pkg})?\s*;", lines[i], re.I))
    ctx = [l for l in lines[:s] if re.match(r"\s*(library|use)\s+ieee\b", l, re.I)]
    open(f"{w}/{pkg}.vhd", "w").write("\n".join(ctx[:3] + lines[s:e + 1]) + "\n")
PYEOF
   SEEDS="$REPO/M2M/QNICE/vhdl/tools.vhd $REPO/M2M/vhdl/av_pipeline/video_modes_pkg.vhd
          $REPO/M2M/vhdl/controllers/HDMI/types_pkg.vhd $REPO/CORE/vhdl/globals.vhd
          $W/vdrives_pkg.vhd $W/qnice_csr_pkg.vhd $REPO/CORE/vhdl/physical_1581/physical_1581_pkg.vhd
          $KEYB_SRC"
   "$GHDL" -a $GF -fsynopsys -P"$W/xpm" --workdir="$W/seed" $SEEDS > "$W/seed.log" 2>&1 ||
      { sed 's/^/    /' "$W/seed.log" | head; note_fail wiring_seed; }

   FILES="CORE/vhdl/main.vhd CORE/vhdl/mega65.vhd CORE/vhdl/keyboard.vhd M2M/vhdl/m2m_keyb.vhd"
   for f in $FILES; do
      git -C "$REPO" show "$BASE:$f" > "$W/base/$(basename "$f")" 2>/dev/null || note_fail "wiring_base_missing_$(basename "$f")"
      cp "$REPO/$f" "$W/new/$(basename "$f")"
   done

   # diags <lib> <file>: normalized diagnostics (file names and positions stripped), sorted
   diags() {
      "$GHDL" -a $GF -fsynopsys -P"$W/xpm" --workdir="$1" "$2" 2>&1 | sed -E 's/^[^:]*:[0-9]+:[0-9]+:[ ]*//' | sort
   }

   # shell <file> <entity> <out>: the entity declaration with its context clause (without the Xilinx
   # libraries) plus an empty architecture
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

   # A) identical libraries for both versions
   for n in main mega65 keyboard m2m_keyb; do
      for v in base new; do
         cp -R "$W/seed" "$W/A_${v}_$n"
         diags "$W/A_${v}_$n" "$W/$v/$n.vhd" > "$W/A_${v}_$n.txt"
      done
      if diff "$W/A_base_$n.txt" "$W/A_new_$n.txt" > "$W/A_$n.diff"; then
         echo "  A $n.vhd: $(wc -l < "$W/A_new_$n.txt" | tr -d ' ') diagnostic lines, identical to $BASE"
      else
         sed 's/^/    /' "$W/A_$n.diff" | head -10
         note_fail "wiring_A_$n"
      fi
   done

   # B) each version with the entity declarations of the sub-entities it instantiates; main and
   # keyboard come from the same version, all others from the working tree. Sub-entities without a
   # VHDL source (iec_drive is SystemVerilog) give the same "not found" diagnostic in both.
   # libB <version> <name> <libdir>: library for <name>.vhd of <version>
   libB() {
      local v=$1 n=$2 L=$3
      local ents e src
      cp -R "$W/seed" "$L"; mkdir -p "$L/sh"
      ents=$(grep -o -i -E "entity work\.[a-z0-9_]+" "$W/new/$n.vhd" | sed -E 's/entity work\.//' | sort -u)
      for e in $ents; do
         case "$e" in
            main|keyboard) src="$W/$v/$e.vhd" ;;
            *) src=$(grep -rl -i -E "^\s*entity\s+$e\s+is\b" "$REPO/CORE/vhdl" "$REPO/CORE/C64_MiSTerMEGA65/rtl" "$REPO/M2M/vhdl" \
                        --include=*.vhd --include=*.vhdl 2>/dev/null | grep -v -E "/test/" | head -1) ;;
         esac
         [ -n "$src" ] || continue
         shell "$src" "$e" "$L/sh/$e.vhd" 2>/dev/null &&
            "$GHDL" -a $GF -fsynopsys -P"$W/xpm" --workdir="$L" "$L/sh/$e.vhd" > /dev/null 2>&1
      done
   }
   for n in main mega65; do
      for v in base new; do
         libB "$v" "$n" "$W/B_${v}_$n"
         diags "$W/B_${v}_$n" "$W/$v/$n.vhd" > "$W/B_${v}_$n.txt"
      done
      if diff "$W/B_base_$n.txt" "$W/B_new_$n.txt" > "$W/B_$n.diff"; then
         errs=$(grep "error:" "$W/B_new_$n.txt" | grep -v "compilation error" | sed -E 's/^error: //' | paste -sd ';' -)
         echo "  B $n.vhd: errors: ${errs:-none}; identical to $BASE"
      else
         sed 's/^/    /' "$W/B_$n.diff" | head -10
         note_fail "wiring_B_$n"
      fi
   done

   # mutants: an unconnected freezer key port must show up as a new diagnostic in B
   for m in main mega65; do
      M="$W/mut_$m"
      mkdir -p "$M"
      case $m in
         main)   mutate "$REPO/CORE/vhdl/main.vhd" "$M/main.vhd" "      sc_freeze_i     => kb_sc_freeze_i," "" ;;
         mega65) mutate "$REPO/CORE/vhdl/mega65.vhd" "$M/mega65.vhd" "         kb_sc_freeze_i         => main_sc_freeze," "" ;;
      esac || { note_fail "wiring_mutant_${m}_pattern"; continue; }
      libB new "$m" "$M/lib"
      diags "$M/lib" "$M/$m.vhd" > "$M/diags.txt"
      if diff "$W/B_new_$m.txt" "$M/diags.txt" > /dev/null; then
         note_fail "wiring_mutant_${m}_not_detected"
      else
         echo "  mutant 'unconnected port in $m.vhd' rejected: $(diff "$W/B_new_$m.txt" "$M/diags.txt" | grep -m1 '^> error' | cut -c3-)"
      fi
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
