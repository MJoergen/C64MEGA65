#!/usr/bin/env python3
"""Mutants of the decoder's tolerance for a weak first sync byte (issue #257
part E) that tb_physical_1581_mfm_decoder has to reject.

Each mutant is a textual patch of physical_1581_mfm_decoder.vhd (every
pattern must occur exactly once). The script first runs the bench on the
unmodified decoder (it must pass), then on every mutant (it must fail), with
nvc, and prints one line per run and "MUTANTS RESULT: PASS" when every mutant
was rejected.

Usage: mutants_mfm_decoder.py <repo checkout> <absolute scratch dir> [name ...]
"""
import os, re, shutil, subprocess, sys, time

MUTANTS = [
    ('tol_ignores_tol_off', 'the tolerance acts with tol_off_i high',
     [("elsif C_TOL and tol_off_i = '0' and sync_cnt = 2 and",
       "elsif C_TOL and sync_cnt = 2 and")]),
    ('train_of_one', 'a mark accepted after one candidate',
     [("elsif C_TOL and tol_off_i = '0' and sync_cnt = 2 and",
       "elsif C_TOL and tol_off_i = '0' and sync_cnt >= 1 and")]),
    ('restart_counts_as_pair', 'a candidate at a wrong spacing continues a pair',
     [("""              -- Overlap or wrong spacing: restart at this candidate.
              crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
              sync_cnt <= 1;""",
       """              -- Overlap or wrong spacing: restart at this candidate.
              crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
              if sync_cnt = 1 and tol_off_i = '0' then sync_cnt <= 2; else sync_cnt <= 1; end if;""")]),
    ('spacing_le', 'any spacing up to five continues a train',
     [("elsif sync_gap_age = C_QUANT_A1_SPACING then",
       "elsif sync_gap_age <= C_QUANT_A1_SPACING then")]),
    ('crc_no_standin', 'the CRC of a pair gets no stand-in A1',
     [("""                crc_byte      <= MARK_A1;
                crc_mark_pend <= 2;""",
       """                crc_byte      <= byte_d;
                crc_mark_pend <= 0;""")]),
    ('crc_a1_for_mark', 'the CRC of a pair gets a second A1 instead of the mark',
     [("""                crc_mark_pend <= 2;
                crc_mark_byte <= byte_d;""",
       """                crc_mark_pend <= 2;
                crc_mark_byte <= MARK_A1;""")]),
    ('crc_mark_next_clock', 'the mark follows its stand-in A1 one clock later (the engine drops it)',
     [("                crc_mark_pend <= 2;", "                crc_mark_pend <= 1;")]),
    ('dam_no_arm', 'a DAM on a pair without a CRC-valid ID before it',
     [("                      data_armed = '1' and data_preamble2_ok = '1')) then",
       "                      data_preamble2_ok = '1')) then")]),
    ('dam_no_preamble', 'a DAM on a pair without the zero run',
     [("                      data_armed = '1' and data_preamble2_ok = '1')) then",
       "                      data_armed = '1')) then")]),
    ('preamble2_no_lower', 'the preamble window of a pair without its lower bound',
     [("""              if run_age > C_QUANT_SYNC_LAT and
                 run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING then
                data_preamble2_ok <= '1';
              else
                data_preamble2_ok <= '0';
              end if;
            elsif sync_gap_age""",
       """              if run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING then
                data_preamble2_ok <= '1';
              else
                data_preamble2_ok <= '0';
              end if;
            elsif sync_gap_age""")]),
    ('preamble2_no_upper', 'the preamble window of a pair without its upper bound',
     [("""              if run_age > C_QUANT_SYNC_LAT and
                 run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING then
                data_preamble2_ok <= '1';
              else
                data_preamble2_ok <= '0';
              end if;
            elsif sync_gap_age""",
       """              if run_age > C_QUANT_SYNC_LAT then
                data_preamble2_ok <= '1';
              else
                data_preamble2_ok <= '0';
              end if;
            elsif sync_gap_age""")]),
    ('hit_stuck_low', 'tol_hit_o never pulses',
     [("                tol_hit_o     <= '1';\n", "")]),
    ('hit_doubled', 'tol_hit_o pulses twice per use',
     [("""          if crc_mark_pend = 1 then
            crc_feed <= '1'; crc_byte <= crc_mark_byte;""",
       """          if crc_mark_pend = 1 then
            tol_hit_o <= '1';
            crc_feed <= '1'; crc_byte <= crc_mark_byte;""")]),
    ('hit_stuck_high', 'tol_hit_o stuck high',
     [("      tol_hit_o         <= '0';\n", "      tol_hit_o         <= '1';\n")]),
    ('bad_pair_id_reported', 'an ID on a pair with a bad CRC is reported and disarms',
     [("            if tol_id = '1' and crc_value /= x\"0000\" then",
       "            if false then")]),
    ('pair_id_sets_n_early', 'an ID on a pair sets N before its CRC verdict',
     [("""              if tol_id = '0' then
                last_n <= byte_d;
              end if;""",
       """              last_n <= byte_d;""")]),
    ('pair_reanchors', 'a pair followed by FE re-anchors an open field',
     [("if G_RECORD_SEQUENCE_GATE and sync_cnt = 3 and byte_d = MARK_FE and state /= S_IDLE then",
       "if G_RECORD_SEQUENCE_GATE and (sync_cnt = 3 or (tol_off_i = '0' and sync_cnt = 2)) and byte_d = MARK_FE and state /= S_IDLE then")]),
]

def build_and_run(repo, work, dec_path, tag):
    P = os.path.join(repo, 'CORE/vhdl/physical_1581')
    CO = os.path.join(repo, 'CORE/vhdl/test/tb_physical_1581_codec')
    d = os.path.join(work, tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    files = [os.path.join(P, f) for f in ('physical_1581_pkg.vhd', 'physical_1581_crc.vhd',
             'physical_1581_mfm_gaps.vhd', 'physical_1581_mfm_quantise.vhd',
             'physical_1581_mfm_gaps_to_bits.vhd', 'physical_1581_mfm_bits_to_bytes.vhd')]
    files += [dec_path, os.path.join(CO, 'mfm_flux_gen_pkg.vhd'),
              os.path.join(CO, 'tb_physical_1581_mfm_decoder.vhd')]
    lib = 'work:' + os.path.join(d, 'work')
    t0 = time.time()
    with open(os.path.join(d, 'run.log'), 'w') as log:
        r = subprocess.run(['nvc', '--std=2008', '--work=' + lib, '-a'] + files +
                           ['-e', 'tb_physical_1581_mfm_decoder', '-r'],
                           cwd=d, stdout=log, stderr=subprocess.STDOUT)
    txt = open(os.path.join(d, 'run.log')).read()
    passed = r.returncode == 0 and 'ALL TESTS PASSED' in txt and 'FAIL' not in txt
    fails = [l.split('FAIL: ', 1)[1].strip()[:150] for l in txt.splitlines() if 'FAIL: ' in l]
    return passed, fails, time.time() - t0, r.returncode

def main():
    repo, work = sys.argv[1], sys.argv[2]
    only = sys.argv[3:]
    src = open(os.path.join(repo, 'CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd')).read()
    os.makedirs(work, exist_ok=True)
    ok_all = True
    if not only:
        passed, fails, dt, rc = build_and_run(repo, work, os.path.join(repo, 'CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd'), 'unmodified')
        print('unmodified: %s (%.0f s)%s' % ('PASS' if passed else 'FAIL', dt, '' if passed else ' ' + '; '.join(fails[:3])))
        ok_all &= passed
    for name, what, patches in MUTANTS:
        if only and name not in only:
            continue
        s = src
        for old, new in patches:
            n = s.count(old)
            if n != 1:
                print('%s: PATCH DOES NOT APPLY (%d matches)' % (name, n)); ok_all = False; break
            s = s.replace(old, new)
        else:
            mp = os.path.join(work, 'mut_' + name + '.vhd')
            open(mp, 'w').write(s)
            passed, fails, dt, rc = build_and_run(repo, work, mp, 'm_' + name)
            killed = not passed
            ok_all &= killed
            print('%-24s %-8s (%.0f s) %s; %s' % (name, 'KILLED' if killed else 'SURVIVED', dt, what,
                  ('first failure: ' + fails[0]) if fails else ('exit %d' % rc)))
    print('MUTANTS RESULT: %s' % ('PASS' if ok_all else 'FAIL'))
    sys.exit(0 if ok_all else 1)

if __name__ == '__main__':
    main()
