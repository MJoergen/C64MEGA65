#!/usr/bin/env bash
# Runner for the NTSC clock benches (issue #181, doc/dev-ntsc/NTSC-SPEC.md 10.1).
#
#   CORE/vhdl/test/tb_ntsc/run_w1.sh [generics|speed|clk|all]
#
#   generics  the MMCM generics in CORE/vhdl/clk.vhd equal the table printed by
#             doc/dev-ntsc/tools/ntsc_clocks.py --final
#   speed     tb_core_speed: the hr_core_speed process of CORE/vhdl/mega65.vhd
#             (the copy in the bench must equal the process in mega65.vhd), plus
#             a mutant with the PAL polarity in NTSC that the bench must reject
#   clk       tb_clk: CORE/vhdl/clk.vhd with the behavioral models of
#             tb_clk_models.vhd (four MMCMs, two-level mux tree, reset)
#
# Environment: GHDL (default /usr/local/bin/ghdl).
# Prints every bench output and a final "RESULT: PASS" or "RESULT: FAIL ..."
# line; exit status 0 only on PASS. Build products go to a temporary directory.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/../../../.." && pwd -P)"
STUBS="$REPO/doc/dev-ntsc/tools/stubs"
GHDL="${GHDL:-/usr/local/bin/ghdl}"
WHAT="${1:-all}"
FLAGS=(--std=08 -frelaxed)

case "$WHAT" in generics|speed|clk|all) ;; *) echo "RESULT: FAIL unknown target '$WHAT' (use generics, speed, clk or all)"; exit 2;; esac

BUILD="$(mktemp -d "${TMPDIR:-/tmp}/tb_ntsc_w1.XXXXXX")"
trap 'rm -rf "$BUILD"' EXIT
cd "$BUILD" || exit 2
T0=$(date +%s)
status=0
failed=""
note_fail() { status=1; failed="$failed $1"; echo "FAIL: $1"; }

# --------------------------------------------------------------------------------------
if [ "$WHAT" = "generics" ] || [ "$WHAT" = "all" ]; then
   echo "=== generics (clk.vhd versus ntsc_clocks.py --final)"
   python3 - "$REPO" <<'EOF' || note_fail generics
import re, subprocess, sys
repo = sys.argv[1]
tbl = subprocess.run([sys.executable, repo + "/doc/dev-ntsc/tools/ntsc_clocks.py", "--final"],
                     capture_output=True, text=True, check=True).stdout
want = {m.group(1): (m.group(2), m.group(3), m.group(4))
        for m in re.finditer(r"\((i_clk_c64_\w+)\)\s+([\d.]+)\s+(\d+)\s+([\d.]+)", tbl)}
src = open(repo + "/CORE/vhdl/clk.vhd").read()
got = {}
for m in re.finditer(r"(i_clk_c64_\w+) : MMCME2_ADV(.*?)\); -- \1", src, re.S):
    g = lambda k: re.search(k + r"\s*=>\s*([\d.]+)", m.group(2)).group(1)
    got[m.group(1)] = (g("CLKFBOUT_MULT_F"), g("DIVCLK_DIVIDE"), g("CLKOUT0_DIVIDE_F"))
ok = len(want) == 4 and set(want) == set(got)
for k in sorted(want):
    same = want[k] == got.get(k)
    ok &= same
    print(f"  {k:18s} ntsc_clocks.py M/D/O0 = {'/'.join(want[k]):18s} clk.vhd = "
          f"{'/'.join(got.get(k, ('?',))):18s} {'OK' if same else 'MISMATCH'}")
print("RESULT: PASS" if ok else "RESULT: FAIL generics differ")
sys.exit(0 if ok else 1)
EOF
fi

# --------------------------------------------------------------------------------------
if [ "$WHAT" = "speed" ] || [ "$WHAT" = "all" ]; then
   echo "=== speed (tb_core_speed)"
   # 1) the copy in the bench must be the process of mega65.vhd
   python3 - "$REPO/CORE/vhdl/mega65.vhd" "$HERE/tb_core_speed.vhd" <<'EOF' || note_fail speed_copy
import sys
def norm(lines):
    return [l.strip() for l in lines if l.strip()]
m = open(sys.argv[1]).read().splitlines()
t = open(sys.argv[2]).read().splitlines()
i = next(n for n, l in enumerate(m) if "hr_core_speed(1) <= hr_ntsc;" in l)
a = max(n for n in range(i) if m[n].strip() == "process (hr_clk_i)")
b = next(n for n in range(i, len(m)) if m[n].strip() == "end process;")
s = next(n for n, l in enumerate(t) if "-- BEGIN COPY" in l) + 1
e = next(n for n, l in enumerate(t) if "-- END COPY" in l)
same = norm(m[a:b + 1]) == norm(t[s:e])
print(f"  mega65.vhd lines {a + 1}-{b + 1} versus tb_core_speed.vhd lines {s + 1}-{e}: "
      f"{'identical' if same else 'DIFFERENT'}")
sys.exit(0 if same else 1)
EOF
   "$GHDL" -a "${FLAGS[@]}" --workdir="$BUILD" "$HERE/tb_core_speed.vhd" &&
   "$GHDL" -e "${FLAGS[@]}" --workdir="$BUILD" -o "$BUILD/tb_core_speed" tb_core_speed &&
   "$BUILD/tb_core_speed" | tee "$BUILD/speed.log"
   grep -q '^RESULT: PASS' "$BUILD/speed.log" 2>/dev/null || note_fail speed

   # 2) mutant: the PAL rule applied in NTSC as well; the bench must reject it
   mkdir -p "$BUILD/mutant"
   sed -e 's/hr_core_speed(0) <= hr_ntsc; /hr_core_speed(0) <= '"'"'0'"'"';     /' \
       -e 's/hr_core_speed(0) <= not hr_ntsc;/hr_core_speed(0) <= '"'"'1'"'"';     /' \
       "$HERE/tb_core_speed.vhd" > "$BUILD/mutant/tb_core_speed.vhd"
   if cmp -s "$HERE/tb_core_speed.vhd" "$BUILD/mutant/tb_core_speed.vhd"; then
      note_fail speed_mutant_not_applied
   else
      "$GHDL" -a "${FLAGS[@]}" --workdir="$BUILD/mutant" "$BUILD/mutant/tb_core_speed.vhd" &&
      "$GHDL" -e "${FLAGS[@]}" --workdir="$BUILD/mutant" -o "$BUILD/mutant/tb_core_speed" tb_core_speed &&
      "$BUILD/mutant/tb_core_speed" > "$BUILD/mutant.log" 2>&1
      if grep -q '^RESULT: FAIL' "$BUILD/mutant.log"; then
         echo "  mutant (PAL polarity in NTSC): rejected as expected ($(grep -c MISMATCH "$BUILD/mutant.log") mismatches)"
      else
         note_fail speed_mutant_not_detected
      fi
   fi
fi

# --------------------------------------------------------------------------------------
if [ "$WHAT" = "clk" ] || [ "$WHAT" = "all" ]; then
   echo "=== clk (tb_clk)"
   mkdir -p "$BUILD/clk"
   if "$GHDL" -a "${FLAGS[@]}" --work=unisim --workdir="$BUILD/clk" \
         "$STUBS/unisim_vcomponents.vhd" "$HERE/tb_clk_models.vhd" &&
      "$GHDL" -a "${FLAGS[@]}" --work=xpm --workdir="$BUILD/clk" "$STUBS/xpm_vcomponents.vhd" &&
      "$GHDL" -a "${FLAGS[@]}" --workdir="$BUILD/clk" -P"$BUILD/clk" \
         "$REPO/CORE/vhdl/clk.vhd" "$HERE/tb_clk.vhd" &&
      "$GHDL" -e "${FLAGS[@]}" --workdir="$BUILD/clk" -P"$BUILD/clk" -o "$BUILD/clk/tb_clk" tb_clk; then
      "$BUILD/clk/tb_clk" --stop-time=10ms | tee "$BUILD/clk.log"
   fi
   grep -q '^RESULT: PASS' "$BUILD/clk.log" 2>/dev/null || note_fail clk

   # mutants of clk.vhd that the bench must reject:
   #   reset2  the reset waits for the two PAL locks only
   #   swap    the inputs of bufgmux_ntsc_inst are swapped
   for mut in reset2 swap; do
      mkdir -p "$BUILD/clk_$mut"
      python3 - "$mut" "$REPO/CORE/vhdl/clk.vhd" "$BUILD/clk_$mut/clk.vhd" <<'PYEOF'
import sys
mut, src, dst = sys.argv[1:4]
s = open(src).read()
if mut == "reset2":
    t = s.replace("main_locked_ntsc and main_locked_ntsc_ff", "'1' and '1'")
else:
    t = (s.replace("i0 => main_clk_mmcm_ntsc,     ", "@A@")
          .replace("i1 => main_clk_mmcm_ntsc_ff,  ", "i0 => main_clk_mmcm_ntsc_ff,  ")
          .replace("@A@", "i1 => main_clk_mmcm_ntsc,     "))
open(dst, "w").write(t)
PYEOF
      if cmp -s "$REPO/CORE/vhdl/clk.vhd" "$BUILD/clk_$mut/clk.vhd"; then
         note_fail "clk_mutant_${mut}_not_applied"; continue
      fi
      "$GHDL" -a "${FLAGS[@]}" --work=unisim --workdir="$BUILD/clk_$mut" \
         "$STUBS/unisim_vcomponents.vhd" "$HERE/tb_clk_models.vhd" &&
      "$GHDL" -a "${FLAGS[@]}" --work=xpm --workdir="$BUILD/clk_$mut" "$STUBS/xpm_vcomponents.vhd" &&
      "$GHDL" -a "${FLAGS[@]}" --workdir="$BUILD/clk_$mut" -P"$BUILD/clk_$mut" \
         "$BUILD/clk_$mut/clk.vhd" "$HERE/tb_clk.vhd" &&
      "$GHDL" -e "${FLAGS[@]}" --workdir="$BUILD/clk_$mut" -P"$BUILD/clk_$mut" -o "$BUILD/clk_$mut/tb_clk" tb_clk &&
      "$BUILD/clk_$mut/tb_clk" --stop-time=10ms > "$BUILD/clk_$mut.log" 2>&1
      if grep -q '^RESULT: FAIL' "$BUILD/clk_$mut.log"; then
         echo "  mutant $mut of clk.vhd: rejected as expected ($(grep -c 'ERROR\|MISMATCH' "$BUILD/clk_$mut.log") findings)"
      else
         note_fail "clk_mutant_${mut}_not_detected"
      fi
   done
fi

echo "total runtime: $(( $(date +%s) - T0 )) s"
if [ $status -eq 0 ]; then
   echo "RESULT: PASS"
else
   echo "RESULT: FAIL benches failed:$failed"
fi
exit $status
