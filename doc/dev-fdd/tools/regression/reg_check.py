#!/usr/bin/env python3
"""reg_check.py <regression directory> [--quiet] : verdict of every job of the queue in <dir>/queue.

A job passes only if
  bench      : its log has 'ALL TESTS PASSED', a 'simulation finished' line, no error or failure report,
               and the runner recorded 'RUN_SIM rc=0'
  runner     : (name ends with _runner) its log has 'RESULT: PASS', no 'RESULT: FAIL', no line with
               'mutant' and without 'rejected' (lines with '===' aside), and 'RUN_SIM rc=0'
               (mut_decoder_runner: also 'MUTANTS RESULT: PASS')
  units      : its log has 'UNITS RESULT: PASS', a line 'tb_...: rc=0 errors=0' for each of the eight
               benches, and 'RUN_SIM rc=0'
  mut_rdahead: 35 mutants of the engine KILLED, none SURVIVED, 'RUN_SIM rc=0'
  write group: the line 'group G latency L us: rc=0 | ... ALL TESTS PASSED ... | ... simulation finished',
               'run_tb_write: twin rc=0', no error report in the simulation log, and 'RUN_SIM rc=0'
               (the exit status of run_tb_write.sh alone says nothing about the simulation)
Logs of running jobs are scanned for failure reports too, so that a failure shows up early.
Exit status: 0 all jobs passed, 1 at least one failed, 2 none failed but some are running or pending.
"""
import os, re, sys
D = sys.argv[1]
quiet = "--quiet" in sys.argv
BAD = re.compile(r"\((assertion|report) (error|failure)\)|TESTS FAILED|ANALYZE FAILED|ELABORATE FAILED|BUILD FAILED|Terminated|Killed|Segmentation|Traceback")
def read(p):
    try:
        # script(1) starts its log with the echo of the end-of-file character: "^D" and two backspaces
        return open(p, errors="replace").read().replace("\r", "").replace("\x04", "").replace("^D\x08\x08", "")
    except OSError:
        return ""
jobs = []
for l in open(D + "/queue"):
    l = l.rstrip("\n")
    if not l.strip() or l.startswith("#") or l.strip() == "END":
        continue
    name, weight, wd, log, cmd = l.split("|", 4)
    jobs.append((name, log, cmd))
start, end = {}, {}
runner_up = runner_exit = False
for l in read(D + "/status.txt").split("\n"):
    m = re.match(r"(\d\d:\d\d:\d\d) START (\S+)", l)
    if m: start[m.group(2)] = m.group(1)
    m = re.match(r"(\d\d:\d\d:\d\d) END +(\S+) +rc=(-?\d+) wall=(\d+)s", l)
    if m: end[m.group(2)] = (m.group(1), int(m.group(3)), int(m.group(4)))
    runner_up |= "RUNNER up" in l
    runner_exit |= "RUNNER exit" in l
def simend(text):
    m = re.findall(r"simulation finished @(\d+)(fs|ps|ns|us|ms)", text)
    if not m: return ""
    v, u = m[-1]
    ns = int(v) * {"fs": 1e-6, "ps": 1e-3, "ns": 1, "us": 1e3, "ms": 1e6}[u]
    return "%.6f ms" % (ns / 1e6)
rows = []; nfail = npass = nopen = 0
for name, log, cmd in jobs:
    text = read(log)
    simlog = ""
    m = re.match(r"write_g(\d+)_l(\d+)$", name)
    if m:
        simlog = read("%s/w/g%s_l%s/write_g%s_l%s.log" % (D, m.group(1), m.group(2), m.group(1), m.group(2)))
    is_runner = name.endswith("_runner")
    bad = [] if (is_runner or name == "mut_rdahead") else [x.strip()[-160:] for x in (text + "\n" + simlog).split("\n") if BAD.search(x)]
    note = ""
    if name not in start:
        state, verdict = "pending", "-"
        nopen += 1
    elif name not in end:
        state = "running"
        verdict = "FAIL (so far)" if bad else "-"
        if bad: nfail += 1; note = bad[0]
        else: nopen += 1
    else:
        t, rc, wall = end[name]
        state = "ended %s, %d s" % (t, wall)
        ok = rc == 0 and "RUN_SIM rc=0" in text and not bad
        if is_runner:
            ok = ok and "RESULT: PASS" in text and "RESULT: FAIL" not in text
            rej = len(re.findall(r"mutant '[^']*' rejected", text)); note = "%d mutants rejected" % rej
            surv = [x.strip() for x in text.split("\n") if "mutant" in x and "rejected" not in x and "===" not in x]
            if surv: ok = False; note += "; NOT rejected: " + surv[0][:100]
            if name == "flux_runner":
                note = "%d checks OK" % len(re.findall(r": OK$", text, re.M))
            if name == "mut_decoder_runner":
                # mutants_mfm_decoder.py: one line per mutant with KILLED or SURVIVED, and its own verdict line
                ok = ok and "MUTANTS RESULT: PASS" in text
                note = "%d decoder mutants killed, %d survive as expected" % (
                    len(re.findall(r"^\S+ +KILLED ", text, re.M)), len(re.findall(r"^\S+ +SURVIVED .*\[(?:equivalent|control)\]", text, re.M)))
        elif name == "mut_rdahead":
            k = len(re.findall(r"-> KILLED", text)); bad2 = len(re.findall(r"SURVIVED|ANALYZE FAILED|rc=timeout", text))
            ok = rc == 0 and "RUN_SIM rc=0" in text and k == 35 and bad2 == 0
            note = "%d of 35 engine mutants killed, %d survived or broken" % (k, bad2)
        elif name == "units":
            ok = ok and "UNITS RESULT: PASS" in text
            note = "%d of 8 benches rc=0" % len(re.findall(r"^tb_\S+: rc=0 errors=0", text, re.M))
            ok = ok and note.startswith("8 ")
        elif m:
            g = re.search(r"group %s latency %s us: rc=(-?\d+) \|([^|]*)\|(.*)" % (m.group(1), m.group(2)), text)
            twin = re.search(r"run_tb_write: twin rc=(\d+)", text)
            ok = ok and bool(g) and g.group(1) == "0" and "ALL TESTS PASSED" in g.group(2) and "simulation finished" in g.group(3)
            ok = ok and bool(twin) and twin.group(1) == "0"
            streams = len([f for f in os.listdir("%s/w/g%s_l%s" % (D, m.group(1), m.group(2))) if re.match(r"wr_g.*_stream_.*\.txt$", f)]) if os.path.isdir("%s/w/g%s_l%s" % (D, m.group(1), m.group(2))) else 0
            note = "sim rc=%s, end %s, twin rc=%s, %d stream file(s)" % (g.group(1) if g else "?", simend(simlog), twin.group(1) if twin else "?", streams)
        else:
            ok = ok and "ALL TESTS PASSED" in text and "simulation finished" in text
            note = "end " + simend(text)
        if not ok and bad: note += "; " + bad[0]
        if not ok and rc != 0: note += "; rc=%d" % rc
        verdict = "PASS" if ok else "FAIL"
        if ok: npass += 1
        else: nfail += 1
    rows.append((name, state, verdict, note))
if not quiet:
    for r in rows:
        print("%-26s %-22s %-14s %s" % r)
print("SUMMARY: %d jobs, %d passed, %d failed, %d running or pending; runner %s" % (
    len(jobs), npass, nfail, nopen, "exited" if runner_exit else ("up" if runner_up else "not started")))
sys.exit(1 if nfail else (2 if nopen else 0))
