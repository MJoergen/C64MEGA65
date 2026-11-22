#!/bin/bash
# Issue #266: end-to-end bench of "Flip joystick ports" with an Amiga mouse, a joystick and paddles.
#
#   ./run.sh              variants 1 to 4, up to 4 processes in parallel, about 45 s
#   ./run.sh 1 3          only these variants
#   ./run.sh control      variant 1 against a debouncer whose Amiga setting follows the C64 port
#                         instead of the socket: must FAIL (shows that the bench sees the difference)
#
# The real sources are copied from this checkout into a temporary folder; the two verbatim blocks of
# tb_issue266.vhd (qnice_wrapper.vhd, fpga64_sid_iec.vhd) are checked against the sources first.
# Uses nvc if installed, ghdl otherwise. Exit code 0: every requested run gave the expected result.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/issue266.XXXXXX")"
echo "work folder: $WORK"

CONTROL=0
if [ "$1" = "control" ]; then
   CONTROL=1
   shift
   VARIANTS="1"
else
   VARIANTS="${*:-1 2 3 4}"
fi

mkdir -p "$WORK/src"
cp "$REPO/M2M/vhdl/debouncer.vhd" "$REPO/M2M/vhdl/amiga_mouse.vhd" "$REPO/M2M/vhdl/debounce.vhd" \
   "$REPO/M2M/vhdl/cdc_stable.vhd" "$REPO/M2M/vhdl/controllers/M65/mouse_input.vhdl" \
   "$REPO/CORE/vhdl/keyboard.vhd" "$HERE/tb_issue266.vhd" "$WORK/src/"

python3 - "$REPO" "$WORK/src/tb_issue266.vhd" "$WORK/src/debouncer.vhd" "$CONTROL" <<'EOF'
import sys, re
repo, tb_file, deb_file, control = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
tb = open(tb_file).read()
blocks = re.findall(r"--VERBATIM-BEGIN (\S+)\n(.*?)\s*--VERBATIM-END", tb, re.S)
srcs = {"qnice_wrapper.vhd": "M2M/vhdl/qnice_wrapper.vhd",
        "fpga64_sid_iec.vhd": "CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd"}
norm = lambda s: re.sub(r"\s+", " ", s).strip()
ok = len(blocks) == 2
for name, body in blocks:
    good = norm(body) in norm(open(repo + "/" + srcs[name]).read())
    print(("VERBATIM OK   " if good else "VERBATIM FAIL ") + name)
    ok &= good
if control:
    # the control: every use of amiga_i in the architecture takes the setting of the C64 port
    deb = open(deb_file).read()
    head, sep, body = deb.partition("\nbegin\n")
    n = body.count("amiga_i(")
    body = body.replace("amiga_i(", "amiga_c(")
    head += "\nsignal amiga_c : std_logic_vector(1 downto 0);   -- CONTROL: setting of the C64 port\n"
    body = "   amiga_c <= amiga_i when flip_joys_i = '0' else amiga_i(0) & amiga_i(1);\n" + body
    open(deb_file, "w").write(head + sep + body)
    print(f"CONTROL: {n} uses of amiga_i in debouncer.vhd now take the setting of the C64 port")
    ok &= n >= 12
sys.exit(0 if ok else 1)
EOF

cd "$WORK"
FILES="src/debounce.vhd src/amiga_mouse.vhd src/debouncer.vhd src/cdc_stable.vhd src/mouse_input.vhdl src/keyboard.vhd src/tb_issue266.vhd"
if command -v nvc >/dev/null; then
   mkdir -p work
   nvc --std=2008 --work=work:work/work -a $FILES
   for v in $VARIANTS; do
      ( nvc --std=2008 --work=work:work/work -e -gG_VARIANT=$v tb_issue266 -r > log_v$v.txt 2>&1 || true ) &
   done
else
   mkdir -p work
   ghdl -a --std=08 --workdir=work $FILES
   ghdl -e --std=08 --workdir=work tb_issue266
   for v in $VARIANTS; do
      ( ghdl -r --std=08 --workdir=work tb_issue266 -gG_VARIANT=$v > log_v$v.txt 2>&1 || true ) &
   done
fi
wait

rc=0
for v in $VARIANTS; do
   grep -E "^RESULT" log_v$v.txt || echo "RESULT variant $v: no result line (see $WORK/log_v$v.txt)"
   if [ $CONTROL = 1 ]; then
      grep -q "RESULT variant $v: FAIL" log_v$v.txt || rc=1
   else
      grep -E "^FAIL" log_v$v.txt | head -20 || true
      grep -q "RESULT variant $v: PASS" log_v$v.txt || rc=1
   fi
done
if [ $CONTROL = 1 ]; then
   [ $rc = 0 ] && echo "CONTROL: the bench rejects a setting that follows the C64 port (expected)" \
               || echo "CONTROL: the bench did NOT reject the control (the bench is broken)"
fi
echo "logs: $WORK/log_v*.txt"
exit $rc
