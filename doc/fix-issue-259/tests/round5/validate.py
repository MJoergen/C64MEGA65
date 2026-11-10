#!/usr/bin/env python3
"""Headless check of the round-5 programs (issue #259): runs every PRG with basicrun.py against a
REC that works, one that does not answer and (where it matters) one that is stalled by badlines
like on WIP-V6-A24X1, and compares what the program prints with what it must print.

usage: validate.py [jobs]      (parallel runs, default 3; build the PRGs with build.sh first)

About six minutes with three jobs. Prints one line per run and RESULT: PASS or FAIL."""
import os, re, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
JOBS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
SOAK = ["--patch", r"Q\xb230=Q\xb203"]          # q=30 minutes -> q=03


def n(pat, text):
    return len(re.findall(pat, text, re.M))


# (program, REC mode, extra arguments, check(text) -> bool, what is checked).
# The text has every run of blanks reduced to one blank; a printed number ends with a blank.
RUNS = [
    ("15-health", "ok", [], lambda t: "RESULT: REU AWAKE" in t and n(r"^ \d+ 0 0 $", t) == 9
        and "STASH STATUS 80 ADR 16640 LEN 1" in t and "FETCH STATUS 80 WRONG BYTES 0" in t
        and "VERIFY STATUS 80" in t and "CHANGED: 48 BYTE 100" in t, "registers, transfers and the planted fault"),
    ("15-health", "dead", [], lambda t: "RESULT: REU DOES NOT ANSWER CORRECTLY" in t and n(r"^ \d+ 40 ", t) == 9, "40 of 40 writes wrong"),
    ("15-health", "flaky:50", [], lambda t: "RESULT: REU DOES NOT ANSWER CORRECTLY" in t, "reported"),
    ("16-soak", "ok", SOAK, lambda t: n(r"^ 3 \d+ 0 0 $", t) == 1 and n(r"^DONE: 0 WRONG OF \d+", t) == 1, "one line per three minutes, nothing wrong"),
    ("16-soak", "flaky:2", SOAK, lambda t: n(r"^DONE: [1-9]\d* WRONG OF \d+", t) == 1, "lost writes counted"),
    ("3-verify", "ok", [], lambda t: n("^REU CHECK OK", t) == 2 and n(r": 0 FAULTS IN \d+ $", t) == 5 and "NOT RUN" not in t, "five lines without faults"),
    ("3-verify", "stall", [], lambda t: n("^REU CHECK OK", t) == 2 and n(r": 0 FAULTS IN \d+ $", t) == 5 and "NOT RUN" not in t, "the same with stalled transfers"),
    ("3-verify", "dead", [], lambda t: n("^REU CHECK FAILED", t) == 2 and n("NOT RUN!", t) == 5, "every command reported as not run"),
    ("9-values", "ok", [], lambda t: n("^REU CHECK OK", t) == 2 and n(r"^VALUE \d+ : 0 FAULTS IN 50$", t) == 8 and "NOT RUN" not in t, "eight lines without faults"),
    ("9-values", "dead", [], lambda t: n("^REU CHECK FAILED", t) == 2 and n("NOT RUN!", t) == 8, "every command reported as not run"),
    ("12-position", "ok", ["--keys", " "], lambda t: n(r"^ 80 255 1 276 5\d $", t) == 20 and n("OFF-STATUS 80", t) == 2, "20 runs to the end, 276 cycles"),
    ("12-position", "stall", ["--keys", " "], lambda t: n(r"^ 80 255 1 319 55 $", t) == 10 and n(r"^ 80 255 1 276 56 $", t) == 10, "line 50: 43 cycles longer, ends in line 55"),
    ("12-position", "dead", ["--keys", " "], lambda t: n(r"^ 16 ?-16385 65535 20 5\d $", t) == 20 and n("OFF-STATUS 16", t) == 2, "no transfer, reset values"),
    ("13-swapchk", "ok", [], lambda t: n("^REU CHECK OK", t) == 2 and "RUNS OK: 20 OF 20, WRONG C64: 0 REU: 0 " in t, "no wrong byte in 20 swaps of 4 KB"),
    ("13-swapchk", "stall", [], lambda t: n("^REU CHECK OK", t) == 2 and n(r"^RUNS OK: \d+ OF 20, WRONG C64: 0 REU: [1-9]\d* $", t) == 1
        and n(r"^RUN \d+ REU: \d+ WRONG, POS \d+ GOT 255 $", t) >= 1 and n(r"^RUN \d+ C64:", t) == 0, "A24X1 picture: REU bytes 255, C64 side right"),
    ("13-swapchk", "dead", [], lambda t: n("^REU CHECK FAILED", t) == 2 and "RUNS OK: 0 OF 20" in t
        and n(r"^RUN \d+ STATUS 16 CHECKS ?-1 ?-1", t) == 12, "every swap and every check reported as not run"),
    ("1-fetch", "ok", [], lambda t: n("^REU CHECK OK", t) == 2 and "RUNS OK: 20 OF 20, BAD BYTES: 0 " in t, "20 clean fetches of 4 KB"),
    ("1-fetch", "stall", [], lambda t: n("^REU CHECK OK", t) == 2 and "RUNS OK: 20 OF 20, BAD BYTES: 0 " in t, "the same with stalled transfers"),
    ("1-fetch", "dead", [], lambda t: n("^REU CHECK FAILED", t) == 2 and "RUNS OK: 0 OF 20" in t and n(r"^RUN \d+ STATUS 16 CHECK ?-1", t) == 12, "reported"),
    ("2-stash", "ok", [], lambda t: n("^REU CHECK OK", t) == 2 and "RUNS OK: 20 OF 20, BAD BYTES: 0 " in t, "20 clean stashes of 4 KB"),
    ("2-stash", "stall", [], lambda t: n("^REU CHECK OK", t) == 2 and "RUNS OK: 20 OF 20, BAD BYTES: 0 " in t, "the same with stalled transfers"),
    ("2-stash", "dead", [], lambda t: n("^REU CHECK FAILED", t) == 2 and "RUNS OK: 0 OF 20" in t and n(r"^RUN \d+ STATUS 16 CHECK ?-1", t) == 12, "reported"),
]


def run(job):
    prog, mode, extra, check, what = job
    r = subprocess.run([sys.executable, os.path.join(HERE, "basicrun.py"), os.path.join(HERE, prog + ".prg"), "--rec", mode,
                        "--quiet", "--max-cycles", "1500000000"] + extra, capture_output=True, text=True)
    text = "\n".join(re.sub(" +", " ", line) for line in r.stdout.splitlines())
    secs = re.search(r"([\d.]+) s of C64 time", r.stdout)
    return prog, mode, r.returncode == 0 and bool(check(text)), f"{what} ({secs.group(1) if secs else '?'} s on a C64)", text + r.stderr


if __name__ == "__main__":
    fails = 0
    with ThreadPoolExecutor(JOBS) as ex:
        for prog, mode, ok, what, out in ex.map(run, RUNS):
            print(f"  {'ok  ' if ok else 'FAIL'} {prog:12s} REC {mode:9s} {what}", flush=True)
            if not ok:
                fails += 1
                print("    | " + "\n    | ".join(l for l in out.splitlines() if l.strip()), flush=True)
    print("RESULT: " + ("PASS" if not fails else f"FAIL ({fails})"))
    sys.exit(1 if fails else 0)
