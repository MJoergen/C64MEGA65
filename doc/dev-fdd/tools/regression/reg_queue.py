#!/usr/bin/env python3
"""reg_queue.py <regression directory> [set ...] : prints the queue lines (name|weight|workdir|log|command)
of the regression on the tree in <dir>/src for jobq.py.

Sets (default: all but "sweep", in this order):
  short    unit bench of the read-ahead engine, diagnostic device, mechanism model, FIFO overflow
  units    the eight small unit benches without a runner of their own (units.sh)
  mutants  the 35 mutants of the read-ahead engine (mutants_rdahead.py) and the 59 of the diagnostic
           device (mutants_diag.py, job mut_diag_runner)
  decoder  the 35 mutants of the decoder's tolerance for a weak first sync byte
           (mutants_mfm_decoder.py, job mut_decoder_runner; nvc)
  flux     the production decoder and controller on recorded flux, with and without the tolerance
           (run_flux_benches.sh, job flux_runner; nvc)
  accept   ten sectors of a track side within 260 ms (tb_physical_1581_rdseq)
  write67  write groups 6 and 7 (the read-ahead next to the write engine)
  loop     tb_physical_1581_rdahead_loop, groups 1 to 5
  generic  tb_physical_1581_controller
  sweep3   three points of the phase sweep of tb_physical_1581_rdseq (gaps 0, 3200 and 10000 us)
  media    run_tb_media_contract.sh (31 mutants)
  write15  write groups 1 to 5 (seven runs)
  ctl      run_tb_rdahead_ctl.sh (18 mutants)
  sweep    all 14 points of the phase sweep
"""
import os, sys
D = sys.argv[1]
sets = sys.argv[2:] or ["short", "units", "mutants", "decoder", "flux", "accept", "write67", "loop", "generic", "sweep3", "media", "write15", "ctl"]
HERE = os.path.dirname(os.path.abspath(__file__))
B = D + "/b"; L = B + "/logs"
C = D + "/src/CORE/vhdl/test/tb_physical_1581_controller"
SWEEP = ((0, 10), (500, 10), (1000, 10), (1500, 10), (2000, 10), (2400, 10), (2800, 10), (3000, 10), (3200, 10),
         (3600, 6), (5000, 6), (10000, 4), (19000, 4), (21000, 4))
def sim(name, exe, *args):
    print("%s|1|%s|%s/%s.log|./%s %s--assert-level=error" % (name, B, L, name, exe, "".join(a + " " for a in args)))
def job(name, cmd):
    print("%s|1|%s|%s/%s.log|%s" % (name, D, L, name, cmd))
def write(g, lat):
    job("write_g%d_l%d" % (g, lat), "bash %s/run_tb_write.sh %s/w/g%d_l%d %d:%d" % (C, D, g, lat, g, lat))
def sweep(points):
    for gap, n in SWEEP:
        if points is None or gap in points:
            sim("sweep_gap%d" % gap, "tb_physical_1581_rdseq", "-gG_NSEC=%d" % n, "-gG_GAP_US=%d" % gap)
for s in sets:
    if s == "short":
        sim("unit_rdahead", "tb_physical_1581_rdahead"); sim("diag", "tb_physical_1581_diag")
        sim("mech_model", "tb_mech_model_1581"); sim("ovf", "tb_physical_1581_ovf")
    elif s == "units":
        job("units", "bash %s/units.sh %s/src %s/units" % (HERE, D, D))
    elif s == "mutants":
        job("mut_rdahead", "python3 -I %s/mutants_rdahead.py %s/src %s/mut_rdahead" % (HERE, D, D))
        job("mut_diag_runner", "python3 -I %s/mutants_diag.py %s/src %s/mut_diag" % (HERE, D, D))
    elif s == "decoder":
        job("mut_decoder_runner", "python3 -I -B %s/src/CORE/vhdl/test/tb_physical_1581_codec/mutants_mfm_decoder.py %s/src %s/mut_decoder" % (D, D, D))
    elif s == "flux":
        job("flux_runner", "bash %s/src/doc/dev-fdd/tools/part_e/format_stop/run_flux_benches.sh %s/src %s/flux" % (D, D, D))
    elif s == "accept":
        sim("rdseq_accept_n10_max260", "tb_physical_1581_rdseq", "-gG_NSEC=10", "-gG_MAX_MS=260")
    elif s == "loop":
        for g in (1, 2, 3, 4, 5): sim("loop_g%d" % g, "tb_physical_1581_rdahead_loop", "-gG_GROUP=%d" % g)
    elif s == "write67":
        write(6, 15); write(7, 15)
    elif s == "generic":
        sim("controller", "tb_physical_1581_controller")
    elif s == "media":
        job("media_contract_runner", "bash %s/run_tb_media_contract.sh" % C)
    elif s == "ctl":
        job("rdahead_ctl_runner", "bash %s/run_tb_rdahead_ctl.sh" % C)
    elif s == "write15":
        for g, lat in ((1, 15), (2, 0), (2, 15), (2, 30), (3, 15), (4, 15), (5, 15)): write(g, lat)
    elif s == "sweep3":
        sweep((0, 3200, 10000))
    elif s == "sweep":
        sweep(None)
    else:
        sys.exit("unknown set " + s)
