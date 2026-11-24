#!/usr/bin/env python3
"""Mutants of the decoder's tolerance for a weak first sync byte (issue #257
part E) that the benches have to reject.

Each mutant is a textual patch of physical_1581_mfm_decoder.vhd; every
pattern must occur as often as the entry says (once unless stated). A mutant
runs against tb_physical_1581_mfm_decoder, or, where it changes only the
historical columns of the generics, against tb_physical_1581_quantise_ab
(bench 'ab'). The script first runs the bench on the unmodified decoder (it
must pass), then every mutant, with nvc. A mutant has to be killed, except:
  equivalent  a mutant whose equivalence is proved in its entry: it must
              survive (if a bench kills it, the proof is wrong)
  control     a patch that changes a comment only: it must survive
It prints one line per run and "MUTANTS RESULT: PASS" when every mutant had
its expected outcome.

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
    # ---- the mutants of the independent review (tb_rc_extra of SP/rc_work), all
    # ---- killed by tb_physical_1581_mfm_decoder unless marked otherwise
    ('tol_id_kept_on_fe', 'an ordinary FE does not clear the mark of a pair ID',
     [("""                    state <= S_ID_C;
                    data_armed <= '0';
                    data_preamble_ok <= '0';
                    tol_id <= '0';""",
       """                    state <= S_ID_C;
                    data_armed <= '0';
                    data_preamble_ok <= '0';""")]),
    ('tol_id_kept_on_reanchor', 'the re-anchor does not clear the mark of a pair ID',
     [("""            data_armed <= '0';
            data_preamble_ok <= '0';
            tol_id <= '0';
          else""",
       """            data_armed <= '0';
            data_preamble_ok <= '0';
          else""")]),
    ('fe_needs_preamble2', 'an ID on a pair needs the zero run (the MEGA65 layout has none)',
     [("                    (byte_d = MARK_FE or\n",
       "                    ((byte_d = MARK_FE and data_preamble2_ok = '1') or\n")]),
    ('tol_fe_disarms', 'an ID on a pair disarms the data mark at once',
     [("""                  state  <= S_ID_C;
                  tol_id <= '1';""",
       """                  state  <= S_ID_C;
                  data_armed <= '0';
                  tol_id <= '1';""")]),
    ('tol_good_no_last_n', 'a good ID on a pair does not set N',
     [("""              if tol_id = '1' then
                last_n <= id_n_r;
              end if;""", "")]),
    ('locked_not_set', 'locked_o not raised by a mark on a pair',
     [("                locked_o      <= '1';\n", "")]),
    ('pre2_upper_plus1', 'the zero-run window of a pair one gap wider at the top',
     [("                 run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING then\n                data_preamble2_ok <= '1';",
       "                 run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING + 1 then\n                data_preamble2_ok <= '1';")],
     {'count': 2}),
    ('pre2_lower_minus1', 'the zero-run window of a pair one gap wider at the bottom',
     [("              if run_age > C_QUANT_SYNC_LAT and\n",
       "              if run_age > C_QUANT_SYNC_LAT - 1 and\n")],
     {'count': 2}),
    ('pre2_not_on_first', 'the window of a pair taken only at a restart, not at a first candidate',
     [("""              sync_gap_age <= 0;
              if run_age <= C_QUANT_SYNC_LAT then
                data_preamble_ok <= '1';
              else
                data_preamble_ok <= '0';
              end if;
              if run_age > C_QUANT_SYNC_LAT and
                 run_age <= C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING then
                data_preamble2_ok <= '1';
              else
                data_preamble2_ok <= '0';
              end if;
            elsif sync_gap_age = C_QUANT_A1_SPACING then""",
       """              sync_gap_age <= 0;
              if run_age <= C_QUANT_SYNC_LAT then
                data_preamble_ok <= '1';
              else
                data_preamble_ok <= '0';
              end if;
            elsif sync_gap_age = C_QUANT_A1_SPACING then""")]),
    # Equivalent: rst_i leaves crc_mark_pend, so a reset in the two clocks
    # after a mark on a pair lets the pending mark byte reach the CRC engine
    # after the reset. The engine is not reset by rst_i, and its value before
    # the next train is not defined by the decoder's contract: every field
    # starts with crc_reset at the first candidate of its train, which clears
    # the value and the buffered byte, and that candidate comes at least four
    # gaps (more than 500 clocks) after the reset, long after the 1 + 8
    # clocks of the stray feed. id_crc_ok_o and data_crc_ok_o are therefore
    # those of the unmodified decoder in every field; only crc_value_o, a
    # diagnostic tap that is defined at id_valid_o and data_end_o, differs
    # between the reset and the next first candidate.
    ('pend_kept_by_reset', 'decoder reset does not clear the pending mark feed',
     [("        crc_mark_pend <= 0;\n        tol_id <= '0';\n      else",
       "        tol_id <= '0';\n      else")],
     {'expect': 'equivalent'}),
    ('dam_pair_uses_preamble_ok', 'a DAM on a pair checks the window of a train of three',
     [("                      data_armed = '1' and data_preamble2_ok = '1')) then",
       "                      data_armed = '1' and data_preamble_ok = '1')) then")]),
    ('mark_feed_fe_only', 'the mark of a DAM on a pair is not fed to the CRC',
     [("                crc_mark_pend <= 2;\n",
       "                if byte_d = MARK_FE then crc_mark_pend <= 2; end if;\n")]),
    ('tol_id_cleared_at_n', 'the mark of a pair ID cleared at N, so a bad pair ID is reported',
     [("""              if tol_id = '0' then
                last_n <= byte_d;
              end if;""",
       """              if tol_id = '0' then
                last_n <= byte_d;
              end if;
              tol_id <= '0';""")]),
    ('hit_only_good', 'tol_hit_o only for an ID on a pair that ends with a good CRC',
     [("                tol_hit_o     <= '1';\n",
       "                if byte_d /= MARK_FE then tol_hit_o <= '1'; end if;\n"),
      ("            if tol_id = '1' and crc_value /= x\"0000\" then\n              null;",
       "            if tol_id = '1' and crc_value = x\"0000\" then tol_hit_o <= '1'; end if;\n            if tol_id = '1' and crc_value /= x\"0000\" then\n              null;")]),
    ('tol_deleted_always0', 'a deleted data mark on a pair reads as normal',
     [("""                  if byte_d = MARK_F8 then
                    deleted_r <= '1';
                  else
                    deleted_r <= '0';
                  end if;""", "                  deleted_r <= '0';")]),
    ('ctol_ignores_seq_gates', 'the tolerance also in the historical columns spanoff and seqoff',
     [("""  constant C_TOL : boolean := G_SYNC_GATE and not G_SYNC_PREAMBLE_GATE and
                              G_SYNC_SPAN_GATE and G_RECORD_SEQUENCE_GATE;""",
       """  constant C_TOL : boolean := G_SYNC_GATE and not G_SYNC_PREAMBLE_GATE;""")],
     {'bench': 'ab'}),
    ('pair_id_late', 'an ID on a pair reported one clock later than after three sync bytes',
     [("state <= S_ID_CHECK; chk_cnt <= 12;",
       "state <= S_ID_CHECK; if tol_id = '1' then chk_cnt <= 13; else chk_cnt <= 12; end if;")]),
    ('bad_tol_keeps_parser', 'the comment of the bad-CRC pair ID removed (no change of the logic)',
     [("              null;                         -- train of two, bad CRC: not reported",
       "              null;")],
     {'expect': 'control'}),
]

FILES_DEC = ('physical_1581_pkg.vhd', 'physical_1581_crc.vhd', 'physical_1581_mfm_gaps.vhd',
             'physical_1581_mfm_quantise.vhd', 'physical_1581_mfm_gaps_to_bits.vhd',
             'physical_1581_mfm_bits_to_bytes.vhd')

def nvc(args, cwd, log):
    return subprocess.run(['nvc', '--std=2008'] + args, cwd=cwd, stdout=log, stderr=subprocess.STDOUT).returncode

def build_and_run(repo, work, dec_path, tag, bench='unit'):
    P = os.path.join(repo, 'CORE/vhdl/physical_1581')
    CO = os.path.join(repo, 'CORE/vhdl/test/tb_physical_1581_codec')
    d = os.path.join(work, tag)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    t0 = time.time()
    with open(os.path.join(d, 'run.log'), 'w') as log:
        if bench == 'unit':
            files = [os.path.join(P, f) for f in FILES_DEC]
            files += [dec_path, os.path.join(CO, 'mfm_flux_gen_pkg.vhd'),
                      os.path.join(CO, 'tb_physical_1581_mfm_decoder.vhd')]
            rc = nvc(['--work=work:' + os.path.join(d, 'work'), '-a'] + files +
                     ['-e', 'tb_physical_1581_mfm_decoder', '-r'], d, log)
            good = 'ALL TESTS PASSED'
        else:
            # the A/B harness: production sources (with the mutant) in q_new, the
            # fixed-window reference in q_old, the harness in work
            new = [os.path.join(P, f) for f in FILES_DEC] + [dec_path]
            old = [os.path.join(P, f) for f in FILES_DEC]
            old[3] = os.path.join(CO, 'ref_mfm_quantise_fixed.vhd')
            old += [dec_path]
            rc = nvc(['--work=q_new:' + os.path.join(d, 'q_new'), '-a'] + new, d, log)
            if rc == 0:
                rc = nvc(['--work=q_old:' + os.path.join(d, 'q_old'), '-a'] + old, d, log)
            if rc == 0:
                rc = nvc(['-L', d, '--work=work:' + os.path.join(d, 'work'), '-a',
                          os.path.join(CO, 'mfm_flux_gen_pkg.vhd'),
                          os.path.join(CO, 'tb_physical_1581_quantise_ab.vhd'),
                          '-e', 'tb_physical_1581_quantise_ab', '-r'], d, log)
            good = 'ALL ACCEPTANCE CRITERIA MET'
    txt = open(os.path.join(d, 'run.log')).read()
    passed = rc == 0 and good in txt and 'FAIL' not in txt
    fails = [l.split('FAIL', 1)[1].strip(' :')[:150] for l in txt.splitlines() if 'FAIL' in l]
    return passed, fails, time.time() - t0, rc

def main():
    repo, work = sys.argv[1], sys.argv[2]
    only = sys.argv[3:]
    dec = os.path.join(repo, 'CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd')
    src = open(dec).read()
    os.makedirs(work, exist_ok=True)
    ok_all = True
    sel = [m for m in MUTANTS if not only or m[0] in only]
    benches = sorted(set((m[3] if len(m) > 3 else {}).get('bench', 'unit') for m in sel))
    for b in benches:
        passed, fails, dt, rc = build_and_run(repo, work, dec, 'unmodified_' + b, b)
        print('unmodified (%s bench): %s (%.0f s)%s' % (b, 'PASS' if passed else 'FAIL', dt,
              '' if passed else ' ' + '; '.join(fails[:3])), flush=True)
        ok_all &= passed
    for m in sel:
        name, what, patches = m[0], m[1], m[2]
        opt = m[3] if len(m) > 3 else {}
        count, expect, bench = opt.get('count', 1), opt.get('expect', 'kill'), opt.get('bench', 'unit')
        s = src
        for old, new in patches:
            n = s.count(old)
            if n != count:
                print('%s: PATCH DOES NOT APPLY (%d matches)' % (name, n), flush=True); ok_all = False; break
            s = s.replace(old, new)
        else:
            mp = os.path.join(work, 'mut_' + name + '.vhd')
            open(mp, 'w').write(s)
            passed, fails, dt, rc = build_and_run(repo, work, mp, 'm_' + name, bench)
            killed = not passed
            as_expected = killed if expect == 'kill' else not killed
            ok_all &= as_expected
            verdict = ('KILLED' if killed else 'SURVIVED') + ('' if as_expected else ' (UNEXPECTED)')
            tag = '' if expect == 'kill' else ' [%s]' % expect
            print('%-26s %-20s (%s, %.0f s) %s%s; %s' % (name, verdict, bench, dt, what, tag,
                  ('first failure: ' + fails[0]) if fails else ('exit %d' % rc)), flush=True)
    print('MUTANTS RESULT: %s' % ('PASS' if ok_all else 'FAIL'))
    sys.exit(0 if ok_all else 1)

if __name__ == '__main__':
    main()
