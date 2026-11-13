#!/usr/bin/env python3
"""
Runs simulation jobs one after the other (never two at the same time) and
appends one line per finished job to the log file given as the first argument.

    runq.py LOGFILE JOB [JOB ...]

    JOB = scenario:variant:sim[:cfg[:sdcard]]     for example main:NEW:ghdl
                                                  fatal:OLD:nvc:fatal_size
                                                  sdcard:NEW:nvc:default:card_files
    BUILD:sim:cfg builds a configuration first    for example BUILD:ghdl:fatal_sub
"""
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim      # noqa: E402


def main():
    log = sys.argv[1]
    for job in sys.argv[2:]:
        p = job.split(":")
        t0 = time.time()
        if p[0] == "BUILD":
            sim.build(p[2] if len(p) > 2 else "default", p[1])
            rc = 0
        else:
            scenario, variant, simulator = p[0], p[1], p[2]
            cfg = p[3] if len(p) > 3 else "default"
            sd = os.path.join(HERE, "sd", p[4] + ".blk") if len(p) > 4 else None
            rc = sim.simulate(scenario, variant, cfg=cfg, sim=simulator, sd=sd,
                              tag=None if cfg == "default" else cfg, timeout=4 * 3600)
        with open(log, "a") as f:
            f.write("%s %s: exit code %s, %.0f s\n" % (time.strftime("%H:%M:%S"), job, rc, time.time() - t0))


if __name__ == "__main__":
    main()
