#!/usr/bin/env python3
"""Mutants of physical_1581_diag.vhd (map v10 and the words around it) against tb_physical_1581_diag.

Each mutant breaks one sentence of the definitions of map v10 (doc/dev-fdd/ISSUE257-PART-E-FIXES.md,
section 4; doc/1581_dd_debug_device.md, section 2.4) or disturbs an older word through the new code,
in a copy of the entity (the worktree is not touched). It is analyzed into its own library under
<scratch>/<name> and run with the unit bench. The unchanged entity runs first (M00_original) and must
pass.

  mutants_diag.py <repository checkout> <scratch directory> [mutant name ...]

SIM=nvc (the default when nvc is installed) or SIM=ghdl selects the simulator; a run takes about
10 s with nvc and about 75 s with GHDL, all 59 mutants about 10 minutes with nvc. One line per
mutant, in the form of the runners of the regression (reg_check.py judges the job mut_diag_runner
by them):
"mutant '<name>' rejected" with the number of red checks and the first of them, or "FAIL: mutant
'<name>' not detected". A mutant marked equivalent cannot change any value the device shows in the
core, because of how the controller, main.vhd and mega65.vhd drive its inputs; its line names the
reason, and it does not count toward the verdict. Ends with "RESULT: PASS" (exit status 0) when the
original passes and every other mutant is rejected, "RESULT: FAIL" (exit status 1) otherwise.
"""
import os, re, shutil, subprocess, sys
if len(sys.argv) < 3:
    sys.exit(__doc__)
REPO, SCR = (os.path.abspath(a) for a in sys.argv[1:3])   # repository checkout, scratch directory
SRC = REPO + "/CORE/vhdl/physical_1581/physical_1581_diag.vhd"
PKG = REPO + "/CORE/vhdl/physical_1581/physical_1581_pkg.vhd"
TB  = REPO + "/CORE/vhdl/test/tb_physical_1581_diag/tb_physical_1581_diag.vhd"
SIM = os.environ.get("SIM", "nvc" if shutil.which("nvc") else "ghdl")
src = open(SRC).read()

M = []
def mut(name, what, *pairs, eq=None):
    M.append((name, what, pairs, eq))

M.append(("M00_original", "the unchanged entity (must pass)", (), None))

# ---- IDX_GAP_MAX_MS (0xA2) ---------------------------------------------------------------------
GAP_MOTOR = "        if st_motor_on_i = '0' then\n          idx_gap_run <= '0';\n        elsif diag_index_qual_i = '1' then\n"
GAP_REC   = "          if idx_gap_run = '1' and idx_gap_ms > idx_gap_max then\n            idx_gap_max <= idx_gap_ms;\n          end if;\n"
GAP_START = "          idx_gap_run <= '1';\n          idx_gap_pre <= 0;\n          idx_gap_ms  <= (others => '0');\n"
mut("G01_motor_ignored", "the motor-on level does not end a measurement",
    (GAP_MOTOR, "        if false then\n          idx_gap_run <= '0';\n        elsif diag_index_qual_i = '1' then\n"))
mut("G02_last_not_largest", "the word shows the last result, not the largest",
    (GAP_REC, "          if idx_gap_run = '1' then\n            idx_gap_max <= idx_gap_ms;\n          end if;\n"))
mut("G03_no_run_flag", "the first edge after a motor-off clock ends a measurement with the frozen count",
    (GAP_REC, GAP_REC.replace("idx_gap_run = '1' and ", "")))
mut("G04_result_at_motor_off", "a motor-off clock ends the measurement with a result",
    (GAP_MOTOR, "        if st_motor_on_i = '0' then\n" + GAP_REC.replace("          ", "        ", 1) + "          idx_gap_run <= '0';\n        elsif diag_index_qual_i = '1' then\n"))
mut("G05_unqualified_edge", "the raw index edge (diag_index_edge_i) starts and ends measurements",
    (GAP_MOTOR, GAP_MOTOR.replace("elsif diag_index_qual_i", "elsif diag_index_edge_i")))
mut("G06_ms_not_restarted", "the end edge does not restart the milliseconds (time since the first edge)",
    (GAP_START, "          idx_gap_run <= '1';\n          idx_gap_pre <= 0;\n"))
mut("G07_pre_not_restarted", "the end edge does not restart the prescaler",
    (GAP_START, "          idx_gap_run <= '1';\n          idx_gap_ms  <= (others => '0');\n"))
mut("G08_prescaler_short", "a millisecond of G_MS_CYC - 1 clocks",
    ("          if idx_gap_pre = G_MS_CYC - 1 then\n            idx_gap_pre <= 0;\n            if idx_gap_ms",
     "          if idx_gap_pre = G_MS_CYC - 2 then\n            idx_gap_pre <= 0;\n            if idx_gap_ms"))
mut("G09_no_saturation", "the milliseconds wrap at 0x10000",
    ("            if idx_gap_ms /= x\"FFFF\" then\n              idx_gap_ms <= idx_gap_ms + 1;\n            end if;\n",
     "            idx_gap_ms <= idx_gap_ms + 1;\n"))
mut("G10_saturate_FFFE", "the milliseconds saturate at 0xFFFE",
    ("            if idx_gap_ms /= x\"FFFF\" then", "            if idx_gap_ms /= x\"FFFE\" then"))
mut("G11_max_not_reset", "a reset does not clear the maximum",
    ("        idx_gap_max       <= (others => '0');\n", ""))
mut("G12_rounded", "the result is rounded instead of truncated",
    ("            idx_gap_max <= idx_gap_ms;\n",
     "            if idx_gap_pre >= G_MS_CYC / 2 then idx_gap_max <= idx_gap_ms + 1; else idx_gap_max <= idx_gap_ms; end if;\n"))
mut("G13_n_clocks", "D clocks between the edges count D clocks, not D - 1 (the definition read literally)",
    (GAP_START, GAP_START.replace("idx_gap_pre <= 0;", "idx_gap_pre <= 1;")))
mut("G14_ready_fall_ends", "a fall of READY ends the measurement without a result (the word depends on READY)",
    (GAP_MOTOR, "        if st_motor_on_i = '0' or (prev_ready = '1' and st_media_ready_i = '0') then\n          idx_gap_run <= '0';\n        elsif diag_index_qual_i = '1' then\n"))
mut("G15_ready_gates", "the measurement runs only while READY is high",
    (GAP_MOTOR, "        if st_motor_on_i = '0' or st_media_ready_i = '0' then\n          idx_gap_run <= '0';\n        elsif diag_index_qual_i = '1' then\n"))
mut("G16_edge_wins_over_motor", "an index edge in a motor-off clock ends a running measurement with a result",
    (GAP_MOTOR, "        if st_motor_on_i = '0' and diag_index_qual_i = '1' then\n" + GAP_REC.replace("          ", "        ", 1)
     + "          idx_gap_run <= '0';\n" + GAP_MOTOR.replace("        if st_motor_on_i", "        elsif st_motor_on_i", 1)),
    eq="diag_index_qual_o = index_edge and motor_on_act, and st_motor_on_o = motor_on_act: no qualified edge in a motor-off clock")
mut("G17_end_edge_no_start", "the end edge does not start the next measurement",
    (GAP_START, GAP_START.replace("idx_gap_run <= '1';", "idx_gap_run <= not idx_gap_run;")))
mut("G18_start_at_motor_on", "the rise of the motor-on level starts a measurement (spin-up counted)",
    (GAP_MOTOR, "        if st_motor_on_i = '0' then\n          idx_gap_run <= '0';\n        elsif prev_motor = '0' and diag_index_qual_i = '0' then\n"
     "          idx_gap_run <= '1';\n          idx_gap_pre <= 0;\n          idx_gap_ms  <= (others => '0');\n        elsif diag_index_qual_i = '1' then\n"))
mut("G19_reads_running", "0xA2 shows the running count instead of the maximum",
    ("      when RM_IDX_GAP_MAX_MS  => qnice_data_o <= std_logic_vector(idx_gap_max);",
     "      when RM_IDX_GAP_MAX_MS  => qnice_data_o <= std_logic_vector(idx_gap_ms);"))

# ---- CNT_RDY_STALE (0xA3) ----------------------------------------------------------------------
STALE = "        cnt_rdy_stale <= sat_inc16(cnt_rdy_stale, prev_ready and not st_media_ready_i and st_motor_on_i);\n"
mut("S01_motor_ignored", "every fall of READY counts", (STALE, STALE.replace(" and st_motor_on_i", "")))
mut("S02_counts_rises", "rises of READY count", (STALE, STALE.replace("prev_ready and not st_media_ready_i", "not prev_ready and st_media_ready_i")))
mut("S03_level", "every clock with READY low and the motor on counts", (STALE, STALE.replace("prev_ready and not st_media_ready_i", "not st_media_ready_i")))
mut("S04_no_saturation", "the counter wraps",
    (STALE, "        if (prev_ready and not st_media_ready_i and st_motor_on_i) = '1' then cnt_rdy_stale <= cnt_rdy_stale + 1; end if;\n"))
mut("S05_not_reset", "a reset does not clear the counter", ("        cnt_rdy_stale     <= (others => '0');\n", ""))
mut("S06_motor_of_last_clock", "the motor-on level of the clock before the fall decides (a fall with the motor counts)",
    (STALE, STALE.replace("and st_motor_on_i);", "and prev_motor);")))
mut("S07_motor_both_clocks", "the motor-on level must be high in the clock before the fall as well",
    (STALE, STALE.replace("and st_motor_on_i);", "and st_motor_on_i and prev_motor);")),
    eq="the controller cannot raise motor_on_act in the clock in which media_ready falls (READY needs idx_seen, cleared while the motor request is low)")
mut("S08_history_frozen", "the READY history is not updated", ("        prev_ready    <= st_media_ready_i;\n", ""))
mut("S09_write_clears", "a QNICE write to 0xA3 clears the counter",
    ("        if qnice_ce_i = '1' and qnice_we_i = '1' and\n           to_integer(unsigned(qnice_addr_i)) = RM_RD_CTRL then\n",
     "        if qnice_ce_i = '1' and qnice_we_i = '1' and\n           to_integer(unsigned(qnice_addr_i)) = RM_CNT_RDY_STALE then\n          cnt_rdy_stale <= (others => '0');\n        end if;\n"
     "        if qnice_ce_i = '1' and qnice_we_i = '1' and\n           to_integer(unsigned(qnice_addr_i)) = RM_RD_CTRL then\n"))

# ---- CNT_TOL_HIT (0xA4) ------------------------------------------------------------------------
TOL = "        cnt_tol_hit   <= sat_inc16(cnt_tol_hit, tol_hit_i);\n"
mut("T01_not_counted", "tol_hit_i is not counted", (TOL, TOL.replace("tol_hit_i)", "'0')")))
mut("T02_no_saturation", "the counter wraps", (TOL, "        if tol_hit_i = '1' then cnt_tol_hit <= cnt_tol_hit + 1; end if;\n"))
mut("T03_not_reset", "a reset does not clear the counter", ("        cnt_tol_hit       <= (others => '0');\n", ""))
mut("T04_wrong_source", "the counter counts mark_fe_i", (TOL, TOL.replace("tol_hit_i)", "mark_fe_i)")))
mut("T05_extra_source", "the counter also counts mark_fe_i", (TOL, TOL.replace("tol_hit_i)", "tol_hit_i or mark_fe_i)")))
mut("T06_edge_not_pulse", "the counter counts rising edges of tol_hit_i",
    ("  signal rd_ctrl        : std_logic := '0';\n", "  signal rd_ctrl        : std_logic := '0';\n  signal prev_tol       : std_logic := '0';\n"),
    (TOL, "        prev_tol <= tol_hit_i;\n" + TOL.replace("tol_hit_i)", "tol_hit_i and not prev_tol)")))
mut("T07_into_mark_fe", "old word: tol_hit_i is also counted in CNT_MARK_FE (0x3B)",
    ("        cnt_mark_fe     <= sat_inc16(cnt_mark_fe,     mark_fe_i);", "        cnt_mark_fe     <= sat_inc16(cnt_mark_fe,     mark_fe_i or tol_hit_i);"))
mut("T08_into_iddec", "old word: tol_hit_i is also counted in CNT_IDDEC (0x24)",
    ("        cnt_iddec    <= sat_inc(cnt_iddec,    diag_id_valid_i);", "        cnt_iddec    <= sat_inc(cnt_iddec,    diag_id_valid_i or tol_hit_i);"))
mut("T09_into_a1_train", "old word: tol_hit_i is also counted in CNT_A1_TRAIN (0x3A)",
    ("        cnt_a1_train  <= sat_inc16(cnt_a1_train,  a1_train_i);", "        cnt_a1_train  <= sat_inc16(cnt_a1_train,  a1_train_i or tol_hit_i);"))

# ---- RD_CTRL (0xA5) ----------------------------------------------------------------------------
RDW = "        if qnice_ce_i = '1' and qnice_we_i = '1' and\n           to_integer(unsigned(qnice_addr_i)) = RM_RD_CTRL then\n          rd_ctrl <= qnice_data_i(0);\n        end if;\n"
WRW = "           to_integer(unsigned(qnice_addr_i)) = RM_WR_CTRL then\n          wr_ctrl <= qnice_data_i(1 downto 0);\n"
mut("R01_not_writable", "RD_CTRL cannot be written", (RDW, ""))
mut("R02_wrong_bit", "data bit 1 is stored", (RDW, RDW.replace("qnice_data_i(0)", "qnice_data_i(1)")))
mut("R03_written_by_wr_ctrl", "a write to WR_CTRL also writes RD_CTRL", (WRW, WRW + "          rd_ctrl <= qnice_data_i(0);\n"))
mut("R04_output_inverted", "dec_tol_off_o is inverted", ("  dec_tol_off_o     <= rd_ctrl;", "  dec_tol_off_o     <= not rd_ctrl;"))
mut("R05_output_zero", "dec_tol_off_o is tied low", ("  dec_tol_off_o     <= rd_ctrl;", "  dec_tol_off_o     <= '0';"))
mut("R06_not_reset", "a reset does not clear RD_CTRL", ("        rd_ctrl           <= '0';\n", ""))
mut("R07_reset_to_one", "a reset sets RD_CTRL (tolerance off)", ("        rd_ctrl           <= '0';\n", "        rd_ctrl           <= '1';\n"))
mut("R08_addr_bit0_ignored", "the write decode ignores address bit 0 (a write to 0xA4 writes RD_CTRL)",
    (RDW, RDW.replace("to_integer(unsigned(qnice_addr_i)) = RM_RD_CTRL", "to_integer(unsigned(qnice_addr_i(7 downto 1))) = RM_RD_CTRL / 2")))
mut("R09_addr_bit7_ignored", "the write decode ignores address bit 7 (a write to 0x25 writes RD_CTRL)",
    (RDW, RDW.replace("to_integer(unsigned(qnice_addr_i)) = RM_RD_CTRL", "to_integer(unsigned(qnice_addr_i(6 downto 0))) = RM_RD_CTRL mod 128")))
mut("R10_ce_ignored", "the write decode ignores the chip enable", (RDW, RDW.replace("qnice_ce_i = '1' and qnice_we_i = '1'", "qnice_we_i = '1'")),
    eq="mega65.vhd drives phys_diag_we only while the device is selected, and qnice.vhd: ramrom_we = ramrom_en and dir and valid, so we implies ce")
mut("R11_we_ignored", "the write decode ignores the write strobe (a read of 0xA5 loads the data bus)",
    (RDW, RDW.replace("qnice_ce_i = '1' and qnice_we_i = '1'", "qnice_ce_i = '1'")))
mut("R12_bit1_reads_bit0", "RD_CTRL reads bit 0 also in bit 1",
    ("      when RM_RD_CTRL         => qnice_data_o <= x\"000\" & \"000\" & rd_ctrl;", "      when RM_RD_CTRL         => qnice_data_o <= x\"000\" & \"00\" & rd_ctrl & rd_ctrl;"))
mut("R13_reads_zero", "RD_CTRL reads 0",
    ("      when RM_RD_CTRL         => qnice_data_o <= x\"000\" & \"000\" & rd_ctrl;", "      when RM_RD_CTRL         => qnice_data_o <= x\"0000\";"))
mut("R14_writes_wr_ctrl", "old word: a write to RD_CTRL also writes WR_CTRL", (RDW, RDW.replace("          rd_ctrl <= qnice_data_i(0);\n", "          rd_ctrl <= qnice_data_i(0);\n          wr_ctrl <= qnice_data_i(1 downto 0);\n")))
mut("R15_wr_ctrl_bit0_only", "old word: WR_CTRL keeps bit 0 only (the decode of RD_CTRL copied)",
    (WRW, WRW.replace("wr_ctrl <= qnice_data_i(1 downto 0);", "wr_ctrl <= '0' & qnice_data_i(0);")))
mut("R16_decodes_wr_ctrl", "RD_CTRL is written by a write to WR_CTRL and not by one to 0xA5",
    (RDW, RDW.replace("= RM_RD_CTRL then", "= RM_WR_CTRL then")))
mut("R17_output_open", "dec_tol_off_o is not driven", ("  dec_tol_off_o     <= rd_ctrl;\n", ""))

# ---- read path, version, aliases ---------------------------------------------------------------
mut("P01_A3_A4_swapped", "0xA3 and 0xA4 swapped",
    ("      when RM_CNT_RDY_STALE   => qnice_data_o <= std_logic_vector(cnt_rdy_stale);\n      when RM_CNT_TOL_HIT     => qnice_data_o <= std_logic_vector(cnt_tol_hit);",
     "      when RM_CNT_RDY_STALE   => qnice_data_o <= std_logic_vector(cnt_tol_hit);\n      when RM_CNT_TOL_HIT     => qnice_data_o <= std_logic_vector(cnt_rdy_stale);"))
mut("P02_version_9", "VERSION reads 0x09FE", ("  constant C_MAP_VERSION : std_logic_vector(7 downto 0) := x\"0A\";", "  constant C_MAP_VERSION : std_logic_vector(7 downto 0) := x\"09\";"))
mut("P03_A6_aliases_rd_ctrl", "the reserved word 0xA6 reads RD_CTRL",
    ("      when RM_RD_CTRL         =>", "      when RM_RD_CTRL | 16#A6# =>"))
mut("P04_FF_aliases_gap", "the reserved word 0xFF reads IDX_GAP_MAX_MS",
    ("      when RM_IDX_GAP_MAX_MS  =>", "      when RM_IDX_GAP_MAX_MS | 16#FF# =>"))
mut("P05_spinup_max_reads_gap", "old word: SPINUP_MAX_MS (0xA1) reads IDX_GAP_MAX_MS",
    ("      when RM_SPINUP_MAX_MS   => qnice_data_o <= std_logic_vector(spinup_max);", "      when RM_SPINUP_MAX_MS   => qnice_data_o <= std_logic_vector(idx_gap_max);"))

def run(d, vhd):
    """analyze, then elaborate and run; returns (return code, output, analysis failed)"""
    if SIM == "nvc":
        w = "--work=work:" + d + "/work"
        steps = [["nvc", "--std=2008", w, "-a", PKG, vhd, TB],
                 ["nvc", "--std=2008", w, "-e", "tb_physical_1581_diag", "-r"]]
    else:
        os.makedirs(d + "/lib", exist_ok=True)
        steps = [["ghdl", "-a", "--std=08", "--workdir=lib", PKG, vhd, TB],
                 ["ghdl", "--elab-run", "--std=08", "--workdir=lib", "tb_physical_1581_diag"]]
    out = ""
    for i, cmd in enumerate(steps):
        try:
            r = subprocess.run(cmd, cwd=d, capture_output=True, text=True, timeout=900)
        except subprocess.TimeoutExpired:
            return "timeout", out, False
        out += r.stdout + r.stderr
        if r.returncode != 0 and i == 0:
            return r.returncode, out, True
    return r.returncode, out, False

only = sys.argv[3:]
ok, n_rej, n_eq, n_bad = True, 0, 0, 0
print(f"=== mutants of physical_1581_diag ({SIM})", flush=True)
for name, what, pairs, eq in M:
    if only and name not in only: continue
    s = src
    for a, b in pairs:
        if s.count(a) != 1:
            print(f"  FAIL: mutant '{name}': pattern found {s.count(a)} times (expected once): {a[:50]!r}", flush=True)
            ok = False; n_bad += 1; break
        s = s.replace(a, b)
    else:
        d = SCR + "/" + name
        os.makedirs(d, exist_ok=True)
        open(d + "/physical_1581_diag.vhd", "w").write(s)
        rc, out, anafail = run(d, d + "/physical_1581_diag.vhd")
        open(d + "/run.log", "w").write(out)
        tags = [m.group(1).strip() for m in re.finditer(
            r"FAIL (.+?)(?: @0x[0-9A-Fa-f]+:|: dec_tol_off_o|: wr_precomp_mode_o|$)", out, re.M)]
        passed = "ALL TESTS PASSED" in out and not tags and rc == 0
        detail = f"rc={rc}"
        if tags: detail += f", {len(tags)} red check(s), first: {tags[0]}"
        elif not passed: detail += ", no red check: the run stopped (bound check or assertion, see run.log)"
        if anafail:
            print(f"  FAIL: mutant '{name}' does not build: {out.strip().splitlines()[-1][:200]}", flush=True)
            ok = False; n_bad += 1
        elif name == "M00_original":
            print(f"  original entity: {'PASSED' if passed else 'FAILED'} ({detail})", flush=True)
            ok &= passed
        elif not passed:
            note = f"; marked equivalent in the core: {eq}" if eq else ""
            print(f"  mutant '{name}' rejected: {what} ({detail}){note}", flush=True)
            n_rej += 1
        elif eq:
            print(f"  equivalent '{name}' survives, not counted: {what} ({detail}); in the core: {eq}", flush=True)
            n_eq += 1
        else:
            print(f"  FAIL: mutant '{name}' not detected: {what} ({detail})", flush=True)
            ok = False; n_bad += 1
print(f"{n_rej} rejected, {n_eq} equivalent, {n_bad} not detected or broken")
print("RESULT: PASS" if ok else "RESULT: FAIL")
sys.exit(0 if ok else 1)
