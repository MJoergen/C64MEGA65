#!/usr/bin/env python3
"""Runs test suites of C64MEGA65 one after the other and prints one line per
suite. Usage: suites.py <step-name> <suite> [<suite> ...]   (or "fw", "all")

Logs go to <system temp folder>/c64mega65-suites/<step-name>/<suite>.log. The clipboard tools are
replaced by no-ops (make_rom.sh and the asm wrapper of QNICE call pbcopy).
Optional environment: REPO (default: the repository of this file), JOBS (default 2).
"""
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("REPO", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..")))
JOBS = os.environ.get("JOBS", "2")

# name: (cwd relative to REPO, command, regex that the output must contain, timeout s)
SUITES = {
    "make_rom":    ("CORE/m2m-rom", ["bash", "make_rom.sh"], r"^Shell ROM: \d+/28672 words\.$", 300),
    "menu_run":    (".", ["python3", "M2M/rom/tests/menu_test.py", "run"], r"^ALL TESTS PASSED", 900),
    "menu_verify": (".", ["python3", "M2M/rom/tests/menu_test.py", "verify"], r"VHDL DECODER TB: OK", 600),
    "strrom":      (".", ["python3", "M2M/rom/tests/strrom_test.py"], None, 900),
    "strrom_tool": (".", ["python3", "M2M/rom/tests/strrom_tool_test.py"], None, 900),
    "strrom_sim":  (".", ["python3", "M2M/rom/tests/strrom_sim_test.py", "--jobs", JOBS], None, 3600),
    "rosm":        (".", ["python3", "M2M/rom/tests/rosm_save_test.py"], r"ROSM_SAVE TEST OK", 600),
    "jiffy":       (".", ["python3", "M2M/rom/tests/jiffy_test.py"], r"JIFFY TEST OK", 600),
    "summary":     (".", ["python3", "M2M/rom/tests/summary_test.py"], r"PASS: summary_test", 600),
    "crt_unload":  (".", ["python3", "M2M/rom/tests/crt_unload_test.py"], r"RESULT: PASS", 1800),
    "shortcuts":   (".", ["python3", "M2M/rom/tests/shortcuts_test.py"], r"PASS: shortcuts_test", 600),
    "next_disk":   (".", ["python3", "M2M/rom/tests/next_disk_test.py"], r"PASS: \d+ cases", 600),
    "cfm":         (".", ["python3", "M2M/rom/tests/cfm_test.py"], r"CFM TEST OK", 1800),
    "saving_text": (".", ["python3", "M2M/rom/tests/saving_text_test.py"], r"RESULT: PASS", 600),
    "hidden_redraw": (".", ["python3", "M2M/rom/tests/hidden_redraw_test.py"], r"RESULT: PASS", 600),
    "tb_capslock": (".", ["bash", "CORE/vhdl/test/tb_capslock/run.sh", "all"], r"^RESULT: PASS", 1800),
    "tb_turbo":    (".", ["bash", "CORE/vhdl/test/tb_turbo/run.sh", "all"], r"^RESULT: PASS", 3600),
    "tb_ntsc":     (".", ["bash", "CORE/vhdl/test/tb_ntsc/run.sh", "all"], r"^RESULT: PASS", 3600),
    "tb_stereo_mix": (".", ["bash", "CORE/vhdl/test/tb_stereo_mix/run.sh", "all"], r"^RESULT: PASS", 1800),
    "tb_crt_cacher": (".", ["bash", "CORE/vhdl/test/tb_crt_cacher/run.sh"], r"^RESULT: PASS", 3600),
    "tb_crt_eject":  (".", ["bash", "CORE/vhdl/test/tb_crt_eject/run.sh"], r"^RESULT: PASS", 3600),
    "tb_shortcuts":  (".", ["bash", "CORE/vhdl/test/tb_shortcuts/run.sh", "all"], r"^RESULT: PASS", 1800),
}
GROUPS = {
    "fw0": ["make_rom", "menu_run", "menu_verify", "strrom", "strrom_tool", "rosm", "jiffy"],
}


def main():
    step = sys.argv[1]
    names = []
    for a in sys.argv[2:]:
        names += GROUPS.get(a, [a])
    import tempfile
    work = os.path.join(tempfile.gettempdir(), "c64mega65-suites")
    logdir = os.path.join(work, step)
    os.makedirs(logdir, exist_ok=True)
    shim = os.path.join(work, "shim")
    os.makedirs(shim, exist_ok=True)
    for tool in ("pbcopy", "xclip"):
        p = os.path.join(shim, tool)
        if not os.path.exists(p):
            with open(p, "w") as f:
                f.write("#!/bin/sh\ncat > /dev/null\nexit 0\n")
            os.chmod(p, 0o755)
    env = dict(os.environ)
    env["PATH"] = shim + os.pathsep + env.get("PATH", "")
    env["JOBS"] = JOBS
    bad = 0
    for n in names:
        cwd, cmd, rx, tmo = SUITES[n]
        log = os.path.join(logdir, n + ".log")
        t0 = time.time()
        try:
            r = subprocess.run(cmd, cwd=os.path.join(REPO, cwd), env=env, stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=tmo)
            out = r.stdout.decode("utf-8", "replace")
            rc = r.returncode
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b"").decode("utf-8", "replace") + "\n*** TIMEOUT after %d s\n" % tmo
            rc = 999
        with open(log, "w") as f:
            f.write(out)
        dt = time.time() - t0
        lines = [l for l in out.splitlines() if l.strip()]
        last = lines[-1] if lines else ""
        ok = rc == 0 and (rx is None or re.search(rx, out, re.M) is not None)
        if not ok:
            bad += 1
        extra = ""
        if n in ("make_rom", "strrom"):
            extra = " | " + " | ".join(l.strip() for l in lines if l.strip().startswith(("String ROM:", "Shell ROM:")))
        print("%-13s %s rc=%-3d %5.0fs  last: %s%s" % (n, "PASS" if ok else "FAIL", rc, dt, last[:150], extra), flush=True)
    print("STEP %s: %s" % (step, "ALL GREEN" if bad == 0 else "%d SUITE(S) FAILED" % bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
