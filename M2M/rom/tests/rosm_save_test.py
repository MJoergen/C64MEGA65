#!/usr/bin/env python3
"""
Headless regression test for the write-cache check of ROSM_SAVE (options.asm).

Background: VD_DRV_READ takes the virtual drive number in R8 and returns its
result in that very register. The loop in ROSM_SAVE that walks all virtual
drives before saving the on-screen-menu settings therefore must not use R8 as
its loop counter, otherwise it never terminates as soon as there are two or
more virtual drives whose write cache is clean, and QNICE freezes the moment
the user closes the menu (upstream M2M issue #58).

This script assembles two variants of the same testbed against a stub of
VD_DRV_READ that reproduces the destructive R8 behavior, runs both in the
QNICE emulator and checks that

    * the current loop terminates for every drive count from 1 to 15 and
      still detects a dirty write cache, and
    * the old loop hangs for two clean drives while it terminates for one,
      which is why the bug stayed unnoticed in cores with a single vdrive.

Run it from anywhere:

    python3 rosm_save_test.py

Requires the QNICE toolchain to be built for the host platform, see
AGENTS.md section 7.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
QNICE = os.path.join(REPO, "M2M", "QNICE")
ASM = os.path.join(QNICE, "assembler", "asm")
EMU = os.path.join(QNICE, "emulator", "qnice")
MONITOR = os.path.join(QNICE, "monitor", "monitor.out")

HANG_TIMEOUT = 10.0


def assemble(name):
    src = os.path.join(HERE, name + ".asm")
    res = subprocess.run([ASM, src], cwd=HERE, capture_output=True, text=True)
    out = os.path.join(HERE, name + ".out")
    if res.returncode != 0 or not os.path.exists(out):
        print(res.stdout)
        print(res.stderr, file=sys.stderr)
        sys.exit("FAIL: could not assemble " + name)
    return out


def run(out, timeout):
    """Returns (stdout, timed_out)."""
    try:
        res = subprocess.run(
            [EMU, "-b", "0x8000", MONITOR, out],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return res.stdout, False
    except subprocess.TimeoutExpired as exc:
        return (exc.stdout or b"").decode("utf-8", "replace"), True


def expected_clean_lines():
    return ["A clean drives=0x%04X -> SAVE" % n for n in range(1, 16)]


def main():
    for tool in (ASM, EMU, MONITOR):
        if not os.path.exists(tool):
            sys.exit("FAIL: missing %s -- build the QNICE toolchain first" % tool)

    # ---- the loop as it is today: must terminate in every case ------------
    out = assemble("rosm_save_fixed_test")
    stdout, timed_out = run(out, HANG_TIMEOUT)
    if timed_out:
        sys.exit("FAIL: the current ROSM_SAVE loop did not terminate\n" + stdout)

    lines = [l.strip() for l in stdout.splitlines() if l.strip()]
    for want in expected_clean_lines():
        if want not in lines:
            sys.exit("FAIL: missing line %r in:\n%s" % (want, stdout))
    for want in ("B drives=0x2 drive 1 dirty -> NOSAVE",
                 "C drives=0x2 drive 0 dirty -> NOSAVE",
                 "DONE"):
        if want not in lines:
            sys.exit("FAIL: missing line %r in:\n%s" % (want, stdout))
    print("PASS: current loop terminates for 1..15 clean drives "
          "and still detects a dirty write cache")

    # ---- the loop before the fix: must hang for two clean drives ----------
    out = assemble("rosm_save_old_test")
    stdout, timed_out = run(out, HANG_TIMEOUT)
    if not timed_out:
        sys.exit("FAIL: the old ROSM_SAVE loop was expected to hang but "
                 "terminated:\n" + stdout)
    lines = [l.strip() for l in stdout.splitlines() if l.strip()]
    if "A clean drives=0x0001 -> SAVE" not in lines:
        sys.exit("FAIL: the old loop did not even survive a single vdrive, "
                 "so the testbed does not reproduce the bug:\n" + stdout)
    if "A clean drives=0x0002 -> SAVE" in lines:
        sys.exit("FAIL: the old loop terminated for two clean drives, "
                 "so the testbed does not reproduce the bug:\n" + stdout)
    print("PASS: old loop terminates for 1 clean drive and hangs for 2, "
          "reproducing upstream M2M issue #58")

    print("ROSM_SAVE TEST OK")


if __name__ == "__main__":
    main()
