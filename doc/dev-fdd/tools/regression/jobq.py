#!/usr/bin/env python3
"""jobq.py - a tiny job queue for the long simulations (at most N CPU slots at a time).

  jobq.py <queue file> <slots file> <status file>

queue file : one job per line, appended to while the runner is alive:
               name|weight|workdir|log|command with arguments
             weight = CPU slots the job occupies (a run_tb_write.sh batch of 3 groups = 3).
             A line 'END' lets the runner exit once everything has finished.
slots file : one integer, re-read every few seconds: the slot limit (so external jobs can be accounted for).
status file: START / END lines with wall time and exit code.
Jobs start in file order; a job that does not fit waits (no overtaking, to keep the order predictable).
The command runs through script(1) so that the log is line buffered.
"""
import os, subprocess, sys, time
qf, sf, stf = sys.argv[1:4]
started = 0
running = []   # (proc, name, weight, t0, log)
def status(msg):
    with open(stf, "a") as f:
        f.write(time.strftime("%H:%M:%S ") + msg + "\n")
status("RUNNER up pid=%d" % os.getpid())
while True:
    try:
        lines = [l.rstrip("\n") for l in open(qf) if l.strip() and not l.startswith("#")]
    except FileNotFoundError:
        lines = []
    try:
        slots = int(open(sf).read().strip())
    except Exception:
        slots = 0
    for r in running[:]:
        rc = r[0].poll()
        if rc is not None:
            running.remove(r)
            with open(r[4], "a") as f:
                f.write("RUN_SIM rc=%d wall=%ds job=%s\n" % (rc, time.time() - r[3], r[1]))
            status("END   %-28s rc=%d wall=%ds" % (r[1], rc, time.time() - r[3]))
    used = sum(r[2] for r in running)
    end = False
    while started < len(lines):
        l = lines[started]
        if l.strip() == "END":
            end = True
            break
        name, weight, wd, log, cmd = l.split("|", 4)
        weight = int(weight)
        if used + weight > slots:
            break
        os.makedirs(os.path.dirname(log), exist_ok=True)
        p = subprocess.Popen(["script", "-q", log] + cmd.split(), cwd=wd,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        running.append((p, name, weight, time.time(), log))
        used += weight
        started += 1
        status("START %-28s weight=%d" % (name, weight))
    if end and not running:
        status("RUNNER exit")
        break
    time.sleep(5)
