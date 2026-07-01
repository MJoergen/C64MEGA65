#!/usr/bin/env python3
"""Headless emulator check for the JiffyDOS gate / status report (PREP_START)
and the on-screen Kernal summary value (_SS_TRY_KERNAL) in
CORE/m2m-rom/m2m-rom.asm.

jiffy_test.asm mirrors the exact decision flow and string-assembly logic of
those two callbacks (the only divergences are the framework MMIO calls
M2M$GET/SET_SETTING, stubbed out, and the _SS_APPEND_LABEL menu lookup, which is
functionally a literal "JiffyDOS" copy). It drives every JiffyDOS-selected row of
the decision table; this script asserts the produced report text and summary
value byte-for-byte. Keep the two in sync when the strings or branching change.

Usage:  python3 jiffy_test.py        (assemble + run + assert; exit 0/1)
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ASM = os.path.join(REPO, "M2M/QNICE/assembler/asm")
QNICE = os.path.join(REPO, "M2M/QNICE/emulator/qnice")
MONITOR = os.path.join(REPO, "M2M/QNICE/monitor/monitor.out")
SRC = "jiffy_test.asm"
OUT = "jiffy_test.out"

# Golden report+summary per row, keyed by (jd-c64, jd-c1541, jd-c1581). Mirrors
# the decision table in ~/Downloads/1581-jiffy.md section 5 and the rendered
# examples in section 6.3. The summary lines verify the width-safe forms: the
# both-drives case is the compact "Jiffy 1541+1581" (24 cols incl. " Kernal: ").
ACTIVE = "  -> JiffyDOS active\n"
DIS_C64 = "  -> JiffyDOS disabled (no JiffyDOS C64 Kernal), using standard Kernal\n"
DIS_DRV = "  -> JiffyDOS disabled (no drive ROM), using standard Kernal\n"
K_JD = "  C64 Kernal: JiffyDOS\n"
K_NO = "  C64 Kernal: standard (jd-c64.bin not found)\n"
HDR = "JiffyDOS status:\n"


def report(l0, l1, l2):
    s = "== row ==\n" + HDR
    if not l0:
        return s + K_NO + DIS_C64 + " Kernal: (radio label)\n"
    s += K_JD
    s += "  1541 DOS  : " + ("JiffyDOS\n" if l1
                             else "standard (jd-c1541.bin not found)\n")
    s += "  1581 DOS  : " + ("JiffyDOS\n" if l2
                             else "standard (jd-c1581.bin not found)\n")
    if l1 and l2:
        return s + ACTIVE + " Kernal: Jiffy 1541+1581\n"
    if l1 or l2:
        tag = "JiffyDOS 1541" if l1 else "JiffyDOS 1581"
        return s + ACTIVE + " Kernal: " + tag + "\n"
    return s + DIS_DRV + " Kernal: (radio label)\n"


# Same rows, in the same order, as the ROWS table in jiffy_test.asm.
ROWS = [(0, 0, 0), (1, 1, 1), (1, 1, 0), (1, 0, 1), (1, 0, 0), (0, 1, 1)]


def main():
    a = subprocess.run([ASM, SRC], cwd=HERE, capture_output=True, text=True)
    if a.returncode != 0 or not os.path.exists(os.path.join(HERE, OUT)):
        sys.stderr.write("assembly failed:\n" + a.stdout + a.stderr)
        return 1
    try:
        r = subprocess.run([QNICE, "-b", "0x8000", MONITOR,
                            os.path.join(HERE, OUT)],
                           stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, timeout=30)
    except subprocess.TimeoutExpired:
        sys.stderr.write("emulator timed out (runaway program?)\n")
        return 1
    got = r.stdout
    # the emulator prints a trailing "\nQMON>" prompt after HALT; drop it
    got = got.split("QMON>")[0]
    expected = "".join(report(*row) for row in ROWS)
    if got.strip("\n") != expected.strip("\n"):
        sys.stderr.write("MISMATCH\n--- expected ---\n%s\n--- got ---\n%s\n"
                         % (expected, got))
        return 1
    print("JIFFY TEST OK: %d decision-table rows match (report + summary)"
          % len(ROWS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
