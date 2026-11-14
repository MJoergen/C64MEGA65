#!/usr/bin/env python3
"""Mutants of physical_1581_rdahead.vhd against tb_physical_1581_rdahead.

Each mutant breaks one rule of the engine in a copy of the entity (the worktree
is not touched), is analyzed into its own library under <scratch>/<name>
and run with the unit bench.

  mutants_rdahead.py <repository checkout> <scratch directory> [mutant name ...] The script prints, per mutant, the tags of the
checks that went red. A mutant that passes the bench is reported as SURVIVED.
"""
import os, re, subprocess, sys
REPO, SCR = sys.argv[1:3]          # repository checkout, scratch directory
SRC = REPO + "/CORE/vhdl/physical_1581/physical_1581_rdahead.vhd"
PKG = REPO + "/CORE/vhdl/physical_1581/physical_1581_pkg.vhd"
TB  = REPO + "/CORE/vhdl/test/tb_physical_1581_controller/tb_physical_1581_rdahead.vhd"
src = open(SRC).read()

M = []
def mut(name, what, *pairs):
    M.append((name, what, pairs))

mut("M01_arm_any_state", "arm_i restarts the hunt from every state (rule 3)",
    ("        if consume_i = '1' then\n          hold_v <= '0';\n        end if;\n",
     "        if arm_i = '1' then\n          st <= S_HUNT;\n        end if;\n        if consume_i = '1' then\n          hold_v <= '0';\n        end if;\n"))
mut("M02_id_crc_ignored", "an ID with a bad CRC becomes the candidate (rule 4)",
    ("v_id_cand := id_crc_ok_i = '1' and id_n_i = C_SIZECODE_512;", "v_id_cand := id_n_i = C_SIZECODE_512;"))
mut("M03_id_n_ignored", "an ID with N /= 2 becomes the candidate (rule 4)",
    ("v_id_cand := id_crc_ok_i = '1' and id_n_i = C_SIZECODE_512;", "v_id_cand := id_crc_ok_i = '1';"))
mut("M04_no_dam_timeout", "no DAM timeout (rule 5)",
    ("            elsif dam_cnt = 0 then\n              st <= S_HUNT;\n            end if;\n\n          when S_DATA =>",
     "            end if;\n\n          when S_DATA =>"))
mut("M05_dam_timeout_short", "DAM timeout one clock short (rule 5)",
    ("        dam_cnt <= G_DAM_TIMEOUT_CYC;", "        dam_cnt <= G_DAM_TIMEOUT_CYC - 1;"))
mut("M06_busy_ignored", "a data mark while busy_i is high starts a capture (rule 5)",
    ("              if busy_i = '1' then", "              if false then"))
mut("M07_hold_cleared_at_id", "the held sector falls with the candidate ID already (rule 5: not earlier)",
    ("        dam_cnt <= G_DAM_TIMEOUT_CYC;\n        st      <= S_DAM;",
     "        dam_cnt <= G_DAM_TIMEOUT_CYC;\n        st      <= S_DAM;\n        hold_v  <= '0';"))
mut("M08_hold_kept_at_data_start", "the held sector survives the data mark that overwrites the buffer (rule 5)",
    ("                hold_v <= '0';                 -- the buffer is about to be overwritten\n", ""))
mut("M09_count_not_checked", "a field that is not 512 bytes long is held (rule 6)",
    ("              if data_crc_ok_i = '1' and cnt = C_SECTOR_BYTES then", "              if data_crc_ok_i = '1' then"))
mut("M10_513th_byte_ignored", "a 513th byte does not end the capture (rule 6)",
    ("                st <= S_HUNT;                  -- a 513th byte", "                null;"))
mut("M11_data_crc_ignored", "a field with a bad data CRC is held (rule 6)",
    ("              if data_crc_ok_i = '1' and cnt = C_SECTOR_BYTES then", "              if cnt = C_SECTOR_BYTES then"))
mut("M12_id_in_data_ignored", "an ID inside the data field does not end the capture (rule 6)",
    ("            if id_valid_i = '1' then\n              take_id;                         -- the field was cut short by an ID\n            elsif data_end_i = '1' then",
     "            if data_end_i = '1' then"))
mut("M13_second_dam_ignored", "a second data mark does not end the capture (rule 6)",
    ("            elsif data_start_i = '1' then\n              st <= S_HUNT;\n            elsif wd_cnt = 0 then",
     "            elsif wd_cnt = 0 then"))
mut("M14_no_data_watchdog", "no data watchdog (rule 6)",
    ("            elsif wd_cnt = 0 then\n              st <= S_HUNT;\n            end if;\n        end case;",
     "            end if;\n        end case;"))
mut("M15_data_watchdog_short", "data watchdog one clock short (rule 6)",
    ("                wd_cnt <= G_DATA_WD_CYC;", "                wd_cnt <= G_DATA_WD_CYC - 1;"))
mut("M16_consume_ignored", "consume_i does not release the held sector (rule 2)",
    ("        if consume_i = '1' then\n          hold_v <= '0';\n        end if;\n", ""))
mut("M17_consume_loses", "a capture that completes in the clock of consume_i stays held (rule 2 before rule 6)",
    ("        case st is\n          when S_OFF =>", "        if consume_i = '1' then\n          hold_v <= '0';\n        end if;\n        case st is\n          when S_OFF =>"),
    ("        end if;\n\n        if consume_i = '1' then\n          hold_v <= '0';\n        end if;\n      end if;\n", "        end if;\n      end if;\n"))
mut("M18_kill_keeps_hold", "kill_i switches the engine off but leaves the sector held (rule 1)",
    ("        st     <= S_OFF;\n        hold_v <= '0';\n      else", "        st     <= S_OFF;\n      else"))
mut("M19_kill_loses_to_arm", "arm_i wins over kill_i in the same clock (rule 1)",
    ("      if rst_i = '1' or kill_i = '1' then", "      if rst_i = '1' or (kill_i = '1' and arm_i = '0') then"))
mut("M20_kill_loses_to_data_end", "a capture that completes in the clock of kill_i is held (rule 1)",
    ("      if rst_i = '1' or kill_i = '1' then", "      if rst_i = '1' or (kill_i = '1' and data_end_i = '0') then"))
mut("M21_deleted_at_data_start", "the deleted flag is sampled at the data mark (rule 6)",
    ("                hold_deleted <= data_deleted_i;\n", ""),
    ("                wd_cnt <= G_DATA_WD_CYC;", "                wd_cnt <= G_DATA_WD_CYC;\n                hold_deleted <= data_deleted_i;"))
mut("M22_cap_follows_bus", "cap_r_o shows the ID bus instead of the latched candidate (rule 7)",
    ("  cap_r_o  <= cand_r;", "  cap_r_o  <= id_r_i;"))
mut("M23_hold_id_from_bus", "the held ID is taken from the ID bus at data_end_i (rule 6)",
    ("                hold_r       <= cand_r;", "                hold_r       <= id_r_i;"))
mut("M24_rst_ignored", "rst_i does not switch the engine off (rule 1)",
    ("      if rst_i = '1' or kill_i = '1' then", "      if kill_i = '1' then"))
mut("M25_cap_v_only_in_data", "cap_v_o is low while waiting for the data mark (rule 7)",
    ("  cap_v_o  <= '1' when st = S_DAM or st = S_DATA else '0';", "  cap_v_o  <= '1' when st = S_DATA else '0';"))
mut("M26_kill_wipes_nothing_but_arms", "kill_i returns to the hunt instead of off (rule 1)",
    ("        st     <= S_OFF;\n        hold_v <= '0';\n      else", "        st     <= S_HUNT;\n        hold_v <= '0';\n      else"))

REL = "        if hold_v = '1' and wd_cnt = 0 then\n          hold_v <= '0';\n        end if;\n"
DEC = "        if wd_cnt /= 0 then\n          wd_cnt <= wd_cnt - 1;\n        end if;\n\n        case st is\n"
mut("M27_no_release", "a held sector is never released by its age",
    (REL, ""))
mut("M28_release_one_clock_early", "the held sector is released one clock early",
    (REL, REL.replace("wd_cnt = 0", "wd_cnt <= 1")))
mut("M29_release_one_clock_late", "the held sector is released one clock late (the time stands still in the clock of the data end)",
    (DEC, DEC.replace("if wd_cnt /= 0 then", "if wd_cnt /= 0 and not (st = S_DATA and data_end_i = '1') then")))
mut("M30_time_only_while_capturing", "the time of the buffer runs only while a capture takes data",
    (DEC, DEC.replace("if wd_cnt /= 0 then", "if wd_cnt /= 0 and st = S_DATA then")))
mut("M31_skipped_mark_restarts", "a data mark that is skipped (busy_i) starts the time of the held sector anew",
    ("                st <= S_HUNT;                  -- the buffer is being read out: skip this record\n",
     "                st <= S_HUNT;                  -- the buffer is being read out: skip this record\n                wd_cnt <= G_DATA_WD_CYC;\n"))
mut("M32_release_drops_candidate", "the release of the held sector drops the candidate",
    (REL, REL.replace("          hold_v <= '0';\n", "          hold_v <= '0';\n          if st = S_DAM then st <= S_HUNT; end if;\n")))
mut("M33_release_switches_off", "the release of the held sector switches the engine off",
    (REL, REL.replace("          hold_v <= '0';\n", "          hold_v <= '0';\n          st <= S_OFF;\n")))
mut("M34_candidate_restarts", "a candidate ID starts the time of the held sector anew",
    ("        dam_cnt <= G_DAM_TIMEOUT_CYC;\n        st      <= S_DAM;", "        dam_cnt <= G_DAM_TIMEOUT_CYC;\n        wd_cnt  <= G_DATA_WD_CYC;\n        st      <= S_DAM;"))
mut("M35_release_wipes_buffer_claim", "the release of the held sector lets a skipped data mark write the buffer (busy_i ignored once nothing is held)",
    ("              if busy_i = '1' then", "              if busy_i = '1' and hold_v = '1' then"))

only = sys.argv[3:]
res = []
for name, what, pairs in M:
    if only and name not in only: continue
    s = src
    for a, b in pairs:
        assert s.count(a) == 1, (name, a, s.count(a))
        s = s.replace(a, b)
    d = SCR + "/" + name
    os.makedirs(d + "/lib", exist_ok=True)
    open(d + "/physical_1581_rdahead.vhd", "w").write(s)
    r = subprocess.run(["ghdl", "-a", "--std=08", "--workdir=lib", PKG, d + "/physical_1581_rdahead.vhd", TB],
                       cwd=d, capture_output=True, text=True)
    if r.returncode != 0:
        res.append((name, what, "ANALYZE FAILED: " + r.stderr[:300])); continue
    try:
        r = subprocess.run(["ghdl", "--elab-run", "--std=08", "--workdir=lib", "tb_physical_1581_rdahead"],
                           cwd=d, capture_output=True, text=True, timeout=600)
        out = r.stdout + r.stderr
        rc = r.returncode
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        rc = "timeout"
    open(d + "/run.log", "w").write(out)
    tags = re.findall(r"\(report error\): FAIL (\S+)", out)
    extra = ""
    if "busy_i while a capture" in out: extra += " +engine assertion(busy_i)"
    if "bound check" in out or "out of bounds" in out: extra += " +bound check failure"
    verdict = "KILLED" if (tags or rc != 0) else "SURVIVED"
    res.append((name, what, "%s rc=%s red checks: %s%s" % (verdict, rc, " ".join(tags) if tags else "-", extra)))
for name, what, r in res:
    print("%-30s %s\n%30s   -> %s" % (name, what, "", r))
