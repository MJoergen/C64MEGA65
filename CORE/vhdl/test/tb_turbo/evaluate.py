#!/usr/bin/env python3
"""Turbo-mode core bench (issue #87): verdicts for the scenario logs written by run.sh.

Usage: evaluate.py <build_dir> <set> [<set> ...]      evaluate the logs
       evaluate.py --jobs <set> [<set> ...]            print the job list "set name scenario-line"
  set = baseline | d6048db | new | mutants

Each scenario log is <build_dir>/<set>/<scenario>/log.txt with "TB: key=value" lines.
Prints one summary line per scenario and one PASS/FAIL line per check; exit status 0 only if
every check passes. The expectations differ per source set: on the baseline sources the
cartridge timing gap F2 must be reproduced, on the new sources it must be gone.
"""
import gzip
import os
import sys

BUILD = sys.argv[1]
SETS = sys.argv[2:]
JOBS_ONLY = BUILD == "--jobs"

# name: mode speed simcrt tacc_ps trace maxcycles bios ram_lat crt_lat board
# (board 3 = MEGA65_R3: EF3 detection and its turbo pause active in hardware-cartridge mode)
SCEN = {
    "off_hw":        "0 0 0 150000 1 15000 0 1 1 3",
    "off_sim":       "0 0 1 0 1 15000 1 1 1 3",
    "c128_2x_hw":    "1 0 0 150000 1 15000 0 1 1 3",
    "c128_3x_hw":    "1 1 0 150000 1 15000 0 1 1 3",
    "c128_4x_hw":    "1 2 0 150000 1 15000 0 1 1 3",
    "c128_2x_hw250": "1 0 0 250000 0 15000 0 1 1 3",
    "smart_2x_hw":   "2 0 0 150000 1 15000 0 1 1 3",
    "smart_4x_hw":   "2 2 0 150000 1 15000 0 1 1 3",
    "c128_4x_hw_r6": "1 2 0 150000 0 15000 0 1 1 6",
    "c128_4x_sim":   "1 2 1 0 1 15000 1 1 1 3",
    "smart_3x_sim":  "2 1 1 0 1 15000 1 1 1 3",
}
MUTANTS = {
    "mut_ram3": "1 2 0 0 0 15000 0 3 1 6",   # RAM data 3 clocks after the address: still in budget
    "mut_ram4": "1 2 0 0 0 15000 0 4 1 6",   # 4 clocks: stale data in turbo, must be detected
    "mut_crt4": "1 2 1 0 0 15000 1 1 4 6",   # SIMCRT cache 4 clocks: must be detected
}
TURBO_SETS = ("baseline", "d6048db", "new")


def scenarios(s):
    return MUTANTS if s == "mutants" else SCEN


def load(s, name):
    p = os.path.join(BUILD, s, name, "log.txt")
    d = {}
    if os.path.exists(p):
        for line in open(p, errors="replace"):
            if line.startswith("TB: ") and "=" in line:
                k, v = line[4:].strip().split("=", 1)
                d[k] = v
    return d


def num(d, k, default=-1):
    try:
        return int(d.get(k, default))
    except ValueError:
        return default


if JOBS_ONLY:
    for s in SETS:
        for name, cfg in (MUTANTS if s == "mutants" else SCEN).items():
            print(s, name, cfg)
    sys.exit(0)

results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail else ""))


def summary(s, name, d):
    cfg = scenarios(s)[name].split()
    mode = ["Off", "C128", "Smart"][int(cfg[0])]
    speed = ["2x", "3x", "4x"][int(cfg[1])]
    hist = d.get("s1_hist", "?")
    mins = " ".join(f"{lbl}:{d.get(f'cart_min{i}_ns', '-')}ns/{d.get(f'cart_acc{i}', '0')}"
                    for i, lbl in enumerate(("none", "CPU0", "CPU4", "CPU8")))
    print(f"  [{s}/{name}] R{cfg[9]} {mode} {speed if mode != 'Off' else ''} {'SIMCRT' if cfg[2] == '1' else 'hw cart ' + str(int(cfg[3]) // 1000) + ' ns'}"
          f": completed={d.get('completed')} S1 hist={hist} turbo cycles={d.get('turbo_cycles')}"
          f" | cart pin time by previous access (min/count) {mins} | cart read errors={d.get('cart_rd_err')}"
          f" write setup viol={d.get('cart_wr_setup_viol')} not-clean={d.get('cart_viol')}"
          f" | SIMCRT reads in turbo states={d.get('sim_rd_turbo')} errors={d.get('sim_rd_err')}"
          f" | reads in turbo RAM/ROM/char={d.get('rd_turbo1')}/{d.get('rd_turbo2')}/{d.get('rd_turbo3')}"
          f" | /ROML,/ROMH pulses without a CPU read={d.get('strobe_unsampled')} unmapped without a CPU access={d.get('umax_unsampled')}"
          f" phantom cart writes={d.get('cart_phantom_wr')} | $FF00 lost={d.get('ff00_invisible')}/{d.get('ff00_wr')}"
          f" EF3={d.get('ef3_detected')} EF3-pause clocks={d.get('ef3_pause_clocks')}")


def eval_scenario(s, name, d):
    cfg = [int(x) for x in scenarios(s)[name].split()]
    mode, speed, simcrt, tacc, board = cfg[0], cfg[1], cfg[2], cfg[3], cfg[9]
    tag = f"{s}/{name}"
    if d.get("bench_done") != "yes":
        check(f"{tag}: bench ran to the end", False, "no bench_done line, see log.txt")
        return
    exp_n = 1 if mode == 0 else speed + 2
    hist = [int(x) for x in d.get("s1_hist", "0,0,0,0,0,0").split(",")]
    hw_turbo = simcrt == 0 and mode != 0
    f2_expected = s in ("baseline", "d6048db") and hw_turbo

    # S1
    check(f"{tag}: S1 RAM-only loop runs {exp_n} access(es) per 1 MHz cycle in the expected states",
          num(d, "s1_bad") == 0 and num(d, "s1_ok") > 100 and hist[exp_n] == num(d, "s1_ok"),
          f"histogram {hist}, cycles ok {d.get('s1_ok')}, bad {d.get('s1_bad')}")
    # S2
    check(f"{tag}: S2 VIC/SID/CIA/color RAM/IO1/IO2 accesses only at CPUC of a clean cycle",
          num(d, "io_viol") == 0 and num(d, "io_acc") > 50 and d.get("io_results_ok") == "yes",
          f"{d.get('io_acc')} I/O accesses, {d.get('io_viol')} violations, read-back {d.get('io_results_ok')}")
    # S3
    ok = num(d, "dma_cyc") == 19 and num(d, "dma_cpu") == 0 and num(d, "dma_turbo") == 0
    if mode != 0:
        ok = ok and num(d, "dma_after_turbo") > 0
    check(f"{tag}: S3 no CPU and no turbo access while DMA is requested, turbo resumes afterwards", ok,
          f"DMA cycles {d.get('dma_cyc')}, CPU accesses {d.get('dma_cpu')}, turbo {d.get('dma_turbo')}, "
          f"turbo cycles after DMA {d.get('dma_after_turbo')}")
    # S4
    if mode == 1:
        ok = (d.get("d030_reads") == "FF,FE,FF" and d.get("d030_on") == "2/2" and d.get("d030_off") == "1/1"
              and d.get("turbo_state_before_reset") == "1" and d.get("turbo_state_in_reset") == "0"
              and d.get("reboot_completed") == "yes" and num(d, "d030_after_reset") == 254)
        check(f"{tag}: S4 $D030 switches turbo from the next cycle, reads FF/FE/FF, a reset clears the bit", ok,
              f"reads {d.get('d030_reads')}, on {d.get('d030_on')}, off {d.get('d030_off')}, "
              f"after reset {d.get('d030_after_reset')}")
    else:
        check(f"{tag}: S4 $D030 reads $FF without C128 mode",
              d.get("d030_reads") == "FF,FF,FF" and (mode == 2 or d.get("d030_on") == "2/2"),
              f"reads {d.get('d030_reads')}, no turbo after writes of 1: {d.get('d030_on')}")
    # I6 / S5 at the core input
    if mode == 2:
        check(f"{tag}: S5/I6 turbo_mode(1) changes take effect within one 1 MHz cycle",
              num(d, "turbo_switch_n") == 5 and 0 <= num(d, "turbo_switch_max_latency") <= 1,
              f"{d.get('turbo_switch_n')} switches, max latency {d.get('turbo_switch_max_latency')} cycle(s)")
    # I5
    check(f"{tag}: I5 VIC/CIA/SID enables unchanged", num(d, "en_pattern_err") == 0, d.get("en_pattern_err"))
    # data integrity of the internal memories (real BRAM latencies)
    check(f"{tag}: RAM/BASIC/KERNAL/char ROM reads and RAM writes correct (stale data detection)",
          num(d, "rd_err1") == 0 and num(d, "rd_err2") == 0 and num(d, "rd_err3") == 0 and num(d, "wr_err") == 0
          and d.get("rom_sums_ok") == "yes",
          f"reads checked {d.get('rd_chk1')}/{d.get('rd_chk2')}/{d.get('rd_chk3')}, in turbo states "
          f"{d.get('rd_turbo1')}/{d.get('rd_turbo2')}/{d.get('rd_turbo3')}, writes {d.get('wr_chk')} "
          f"({d.get('wr_turbo')} in turbo states), errors {d.get('rd_err1')}/{d.get('rd_err2')}/{d.get('rd_err3')}/{d.get('wr_err')}")
    if mode != 0:
        check(f"{tag}: RAM, ROM and char ROM reads and RAM writes ran in turbo states",
              num(d, "rd_turbo1") > 0 and num(d, "rd_turbo2") > 0 and num(d, "rd_turbo3") > 0 and num(d, "wr_turbo") > 0)
    else:
        check(f"{tag}: no turbo access with turbo Off", num(d, "turbo_cycles") == 0)
    # S8 / d6048db
    check(f"{tag}: S8 cs_io is never 1 at the EXT1/EXT5 turbo decision (cpuHasBus is 0 there)",
          num(d, "csio_at_decision") == 0 and num(d, "cpuhasbus_at_decision") == 0,
          f"cs_io {d.get('csio_at_decision')}, cpuHasBus {d.get('cpuhasbus_at_decision')}")
    # the EF3 pause exists only in hardware-cartridge mode on R3/R4
    if simcrt == 1 or board not in (3, 4):
        check(f"{tag}: EF3 turbo pause inactive ({'SIMCRT' if simcrt else 'R' + str(board)})",
              num(d, "ef3_pause_clocks") == 0, f"{d.get('ef3_pause_clocks')} clocks with turbo_ef3_pause")
    # S7
    if simcrt == 1:
        ok = num(d, "sim_rd_err") == 0 and num(d, "rd_err5") == 0 and d.get("cart_sums_ok") == "yes" \
             and d.get("cartcode_ok") == "yes" and d.get("completed") == "yes"
        if mode != 0:
            ok = ok and num(d, "sim_rd_turbo") > 0
        check(f"{tag}: S7 SIMCRT ROM reads {'run in turbo states and ' if mode else ''}return correct data", ok,
              f"{d.get('sim_rd')} reads, {d.get('sim_rd_turbo')} in turbo states, {d.get('sim_rd_err')} errors")
        return
    # hardware cartridge: F2 / I2 / S6
    if not hw_turbo:
        check(f"{tag}: hardware cartridge at 1 MHz: every access in a clean cycle, pins stable 14 clocks, data correct",
              num(d, "cart_viol") == 0 and num(d, "cart_min0_clk") == 14 and num(d, "cart_rd_err") == 0
              and num(d, "cart_wr_setup_viol") == 0 and d.get("completed") == "yes"
              and d.get("cart_sums_ok") == "yes" and d.get("cartcode_ok") == "yes",
              f"min {d.get('cart_min0_ns')} ns")
    elif f2_expected:
        short = [num(d, f"cart_acc{i}") for i in (1, 2, 3)]
        ok = num(d, "cart_viol") > 0 and num(d, "cart_addr_late") > 0 and sum(short) > 0
        if speed > 0 or tacc > 190000:
            ok = ok and num(d, "cart_rd_err") > 0
        check(f"{tag}: S6/F2 reproduced: real-cartridge accesses directly after a turbo access, short pin time",
              ok, f"{d.get('cart_viol')} accesses not in a clean cycle, after CPU0/CPU4/CPU8: {short}, "
                  f"min {d.get('cart_min1_ns', '-')}/{d.get('cart_min2_ns', '-')}/{d.get('cart_min3_ns', '-')} ns, "
                  f"{d.get('cart_rd_err')} wrong reads, {d.get('cart_wr_setup_viol')} short writes, completed {d.get('completed')}")
    else:
        ok = (num(d, "cart_viol") == 0 and num(d, "cart_addr_late") == 0
              and all(num(d, f"cart_acc{i}", 0) == 0 for i in (1, 2, 3))
              and num(d, "cart_min0_clk") == 14 and num(d, "cart_rd_err") == 0 and num(d, "cart_wr_setup_viol") == 0
              and d.get("completed") == "yes" and d.get("cart_sums_ok") == "yes" and d.get("cartcode_ok") == "yes")
        check(f"{tag}: S6/F2 fixed: every real-cartridge access at CPUC of a clean cycle, address from the "
              f"previous cycle, pins stable 14 clocks as at 1 MHz, data correct", ok,
              f"{d.get('cart_viol')} not clean, {d.get('cart_addr_late')} late addresses, min {d.get('cart_min0_ns')} ns, "
              f"{d.get('cart_rd_err')} wrong reads, {d.get('cart_wr_setup_viol')} short writes, "
              f"{d.get('strobe_unsampled')} /ROML,/ROMH pulses without a CPU sample (RESEARCH 5.3)")
    # (a) every CPU write to the cartridge (Ultimax ROML, ROMH, unmapped area, IO1, IO2) reaches the
    # pins exactly once: one write cycle (R/W low at PHI2 fall, decoded) per CPU write, none without
    # a CPU write (phantom), with the CPU data driven by the FPGA before and after PHI2 falls
    check(f"{tag}: (a)/I2 every CPU write to the cartridge reaches the pins exactly once, data driven around PHI2 fall",
          num(d, "cart_phantom_wr") == 0 and num(d, "cart_missing_wr") == 0 and num(d, "cart_wr_data_err") == 0
          and num(d, "cart_wr_window_viol") == 0,
          f"{d.get('cart_phantom_wr')} phantom, {d.get('cart_missing_wr')} missing, {d.get('cart_wr_data_err')} wrong data, "
          f"{d.get('cart_wr_window_viol')} drive-window violations")
    check(f"{tag}: no /ROML or /ROMH pulse at the pins without a CPU read",
          num(d, "strobe_unsampled") == 0,
          f"{d.get('strobe_unsampled')} pulses; Ultimax unmapped addresses without a CPU access (no strobe, "
          f"informational): {d.get('umax_unsampled')}")
    # (b) hardware REU trigger and (c) EF3 detection of the R3/R3A/R4 boards
    ff = f"{d.get('ff00_wr')} CPU writes to $FF00, {d.get('ff00_invisible')} not on the pins when PHI2 fell"
    ef = f"is_an_ef3 {d.get('ef3_detected')}"
    if f2_expected:
        check(f"{tag}: (b) reproduced: a CPU write to $FF00 in turbo is not on the pins when PHI2 falls",
              num(d, "ff00_wr") > 0 and num(d, "ff00_invisible") > 0, ff)
        check(f"{tag}: (c) reproduced: the EF3 fingerprint (cartridge_heuristics.vhd) is not detected in turbo",
              d.get("ef3_detected") == "no", ef)
    else:
        check(f"{tag}: (b) every CPU write to $FF00 is on the pins (address, R/W low) when PHI2 falls (hardware REU trigger)",
              num(d, "ff00_wr") > 0 and num(d, "ff00_invisible") == 0, ff)
        if board in (3, 4) or mode == 0:
            check(f"{tag}: (c) the EF3 fingerprint of cartridge_heuristics.vhd is detected", d.get("ef3_detected") == "yes", ef)
        else:
            print(f"  note  {tag}: (c) not required on R{board} (no EF3 pause there): {ef}")
    if d.get("completed") != "yes" and f2_expected:
        print(f"  note  {tag}: program did not complete (last phase {d.get('last_phase')}): F2 corrupted "
              f"code fetched from cartridge ROM")


def same_trace(a, b):
    pa = os.path.join(BUILD, a, "trace.txt.gz")
    pb = os.path.join(BUILD, b, "trace.txt.gz")
    if not (os.path.exists(pa) and os.path.exists(pb)):
        return None, "trace missing"
    with gzip.open(pa, "rt") as fa, gzip.open(pb, "rt") as fb:
        n = 0
        for la, lb in zip(fa, fb):
            n += 1
            if la != lb:
                return False, f"first difference at clock {n}: '{la.strip()}' versus '{lb.strip()}'"
        rest_a = fa.readline()
        rest_b = fb.readline()
        if rest_a or rest_b:
            return False, f"different length after {n} clocks"
    return True, f"{n} clocks identical"


for s in SETS:
    print(f"=== evaluation: {s}")
    for name in scenarios(s):
        d = load(s, name)
        if s != "mutants":
            summary(s, name, d)
    for name in scenarios(s):
        d = load(s, name)
        if s == "mutants":
            summary(s, name, d)
            if name == "mut_ram3":
                check("mutants/mut_ram3: RAM data 3 clocks after the address still passes at 4x (latency budget)",
                      d.get("bench_done") == "yes" and num(d, "rd_err1") == 0 and num(d, "wr_err") == 0
                      and d.get("completed") == "yes")
            elif name == "mut_ram4":
                check("mutants/mut_ram4: RAM data 4 clocks after the address is detected as stale at 4x",
                      num(d, "rd_err1") > 0, f"{d.get('rd_err1')} RAM read errors")
            else:
                check("mutants/mut_crt4: SIMCRT cache data 4 clocks after the address is detected as stale at 4x",
                      num(d, "rd_err5") > 0, f"{d.get('rd_err5')} SIMCRT read errors")
        else:
            eval_scenario(s, name, d)

# I1: new versus baseline with turbo Off
if "new" in SETS and "baseline" in SETS:
    print("=== I1: cycle trace with turbo Off, baseline versus new")
    for name in ("off_hw", "off_sim"):
        ok, why = same_trace(f"baseline/{name}", f"new/{name}")
        check(f"I1 {name}: per-clock trace identical (state, CPU address/WE/enable, RAM port, core cartridge outputs, "
              f"main.vhd port address/strobes/R-W/data direction/data, exp_port_we versus c64_ram_we, PHI2, BA, EF3 flag)",
              bool(ok), why)
# S8: d6048db alone versus baseline in turbo
if "d6048db" in SETS and "baseline" in SETS:
    print("=== S8: baseline versus baseline + upstream d6048db, all scenarios")
    for name, cfg in SCEN.items():
        if cfg.split()[4] != "1":
            continue
        ok, why = same_trace(f"baseline/{name}", f"d6048db/{name}")
        check(f"S8 {name}: d6048db changes nothing (identical per-clock trace)", bool(ok), why)

n_fail = sum(1 for _, ok in results if not ok)
print(f"evaluation: {len(results) - n_fail} of {len(results)} checks passed")
sys.exit(0 if n_fail == 0 else 1)
