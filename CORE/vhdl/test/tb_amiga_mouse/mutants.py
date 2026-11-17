#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# Amiga mouse benches (GitHub issue #190): the mutants, used by run.sh
#
#   mutants.py list <part>           name|kind|file|unit|bench arguments for the mutants of a part
#                                    (decoder, buttons, ports, keyb or all); kind is "mutant" (must be
#                                    rejected) or "survivor" (expected to survive, reported only)
#   mutants.py make <name> <src> <dst>   copy src to dst with the text of the mutant replaced;
#                                    the old text must occur exactly once
#
# Each mutant is one exact text replacement in M2M/vhdl/amiga_mouse.vhd, M2M/vhdl/debouncer.vhd,
# M2M/vhdl/cdc_stable.vhd, M2M/vhdl/qnice_wrapper.vhd or M2M/vhdl/m2m_keyb.vhd, and names the bench
# run that has to reject it.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

import sys

FAST = "-gG_STEP_US=1"
SMALL = "-gG_STEP_US=10 -gG_CONFIRM_US=100 -gG_STUCK_MS=5"
TENTH = "-gG_FREQ=3152778"
TB = "tb_amiga_mouse"
TP = "tb_amiga_ports"
TK = "tb_amiga_keyb"
RULE = "-gG_PART=rule " + TENTH
DIRECTED = "-gG_PART=directed " + TENTH
ONLY_PROPERTIES = " -gG_MODEL=false -gG_IDENT=false"

RQ0 = "rclick_q(0) <= amiga_i(0) and amiga_rclick_i(0) and not mega_key_n_i;"
R0 = "rclick(0)     <= rclick_q(0) and amiga_i(0) and amiga_rclick_i(0);"
R1 = "rclick(1)     <= rclick_q(1) and amiga_i(1) and amiga_rclick_i(1);"
# r registered: every decision takes effect one clock cycle late; "now = 0 fs" gives the register the
# start value '0', so that only the delay can be caught
LATE = "rclick(0)     <= rclick_q(0) and amiga_i(0) and amiga_rclick_i(0) when rising_edge(clk) or now = 0 fs;"
UP0 = "mouse_up_n(0) <= mouse_right_n(0) and (j1_f or not rclick(0));"

X_LINE = "count := quad_count(lines_old(C_RIGHT), lines_old(C_DOWN), lines_flt(C_RIGHT), lines_flt(C_DOWN));"
Y_LINE = "count := quad_count(lines_old(C_UP), lines_old(C_LEFT), lines_flt(C_UP), lines_flt(C_LEFT));"

# name, part, file, bench unit, bench arguments, old text, new text [, "survive"]
MUTANTS = [
    # decoder
    ("x_direction_swapped", "decoder", "amiga_mouse", TB, "-gG_PART=dir " + FAST, X_LINE,
     "count := quad_count(lines_old(C_DOWN), lines_old(C_RIGHT), lines_flt(C_DOWN), lines_flt(C_RIGHT));"),
    ("y_direction_swapped", "decoder", "amiga_mouse", TB, "-gG_PART=dir " + FAST, Y_LINE,
     "count := quad_count(lines_old(C_LEFT), lines_old(C_UP), lines_flt(C_LEFT), lines_flt(C_UP));"),
    ("pairs_exchanged", "decoder", "amiga_mouse", TB, "-gG_PART=dir " + FAST,
     X_LINE + "\n            else\n               " + Y_LINE,
     Y_LINE + "\n            else\n               " + X_LINE),
    ("pot_plus_64_wrong", "decoder", "amiga_mouse", TB, "-gG_PART=dir " + FAST,
     "      r(6)          := not p(6);", "      r(6)          := p(6);"),
    ("pot_bit0_exported", "decoder", "amiga_mouse", TB,
     "-gG_PART=driver -gG_PHASE_X=70 -gG_PHASE_Y=110 -gG_SEED=4 -gG_MON_CHECK=false",
     "      r(0)          := '0';", "      r(0)          := p(0);"),
    ("double_transition_counted", "decoder", "amiga_mouse", TB, "-gG_PART=double " + FAST,
     "elsif a /= a_old and b = b_old then", "elsif a /= a_old then"),
    ("filter_removed", "decoder", "amiga_mouse", TB, "-gG_PART=pulse " + FAST,
     "elsif filter_cnt(i) = C_FILTER_CYCLES then", "elsif true then"),
    ("filter_half", "decoder", "amiga_mouse", TB, "-gG_PART=pulse " + FAST,
     "* G_FILTER_NS / 1_000_000);", "* G_FILTER_NS / 2_000_000);"),
    ("filter_one_cycle_longer", "decoder", "amiga_mouse", TB, "-gG_PART=pulse " + FAST,
     "* G_FILTER_NS / 1_000_000);", "* G_FILTER_NS / 1_000_000 + 1);"),
    # expected to survive: one synchronizer stage less only shortens the latency by one clock cycle,
    # which no port shows; it removes the protection against metastability, which no simulation sees
    ("one_synchronizer_stage", "decoder", "amiga_mouse", TB, "-gG_PART=pulse " + FAST,
     "lines_dd <= lines_d;", "lines_dd <= right_n_i & left_n_i & down_n_i & up_n_i;", "survive"),
    ("rate_limiter_removed", "decoder", "amiga_mouse", TB,
     "-gG_PART=driver -gG_PHASE_X=70 -gG_PHASE_Y=110 -gG_SEED=4 -gG_MON_CHECK=false",
     "            step := 0;\n            if tick = '1' then",
     "            step := count;\n            if false then"),
    ("backlog_bound_removed", "decoder", "amiga_mouse", TB, "-gG_PART=rate_sat",
     "if pending > G_BACKLOG or pending < -G_BACKLOG then", "if false then"),
    ("count_lost_at_a_step", "decoder", "amiga_mouse", TB, "-gG_PART=rate_tick",
     "pending := backlog(axis) - step + count;", "pending := backlog(axis) - step + count * (1 - abs(step));"),
    ("step_time_wrong", "decoder", "amiga_mouse", TB, "-gG_PART=times",
     "* G_STEP_US / 1000);", "* G_STEP_US / 1024);"),
    ("backlog_kept_while_disabled", "decoder", "amiga_mouse", TB, "-gG_PART=enable",
     "               pending := 0;\n               step    := 0;",
     "               pending := backlog(axis);\n               step    := 0;"),
    ("counting_while_disabled", "decoder", "amiga_mouse", TB, "-gG_PART=enable",
     "               pending := 0;\n               step    := 0;",
     "               pending := backlog(axis) + count;\n               step    := 0;"),
    ("decoder_frozen_while_disabled", "decoder", "amiga_mouse", TB, "-gG_PART=enable",
     "lines_old <= lines_flt;", "lines_old <= lines_flt when enable_i = '1' else lines_old;"),
    # buttons
    ("button_thresholds_exchanged", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "released := meas(i)(7) = '0';\n            open_pin := meas(i)(7 downto 6) = \"11\";",
     "released := meas(i)(7 downto 6) = \"11\";\n            open_pin := meas(i)(7) = '0';"),
    ("stuck_release_removed", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "                  btn_n(i)    <= '1';\n                  pullup_seen <= '0';\n                  confirm_cnt <= 0;\n                  stuck_cnt   <= 0;",
     "                  confirm_cnt <= 0;\n                  stuck_cnt   <= 0;"),
    ("stuck_release_keeps_flag", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "                  btn_n(i)    <= '1';\n                  pullup_seen <= '0';\n                  confirm_cnt <= 0;",
     "                  btn_n(i)    <= '1';\n                  confirm_cnt <= 0;"),
    ("pullup_flag_ignored", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "elsif pullup_seen = '1' then\n               change := open_pin;", "elsif true then\n               change := open_pin;"),
    ("flag_set_at_once", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "            else\n               change := released;                          -- no flag yet: a pull-up exists\n            end if;",
     "            else\n               change := false;\n               if released then\n                  pullup_seen <= '1';\n               end if;\n            end if;"),
    ("confirmation_one_tick_short", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "if confirm_cnt = C_CONFIRM_TICKS then", "if confirm_cnt = C_CONFIRM_TICKS - 1 then"),
    ("mid_values_count", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "            if not change then\n               confirm_cnt <= 0;",
     "            if not change and (released or open_pin) then\n               confirm_cnt <= 0;"),
    ("flag_kept_while_disabled", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "            if enable_i = '0' then\n               btn_n(i)    <= '1';\n               pullup_seen <= '0';",
     "            if enable_i = '0' then\n               btn_n(i)    <= '1';"),
    ("middle_button_from_pin_9", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "meas(1)        <= meas_y_i;", "meas(1)        <= meas_x_i;"),
    ("threshold_128_released", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "released := meas(i)(7) = '0';", "released := unsigned(meas(i)) <= 128;"),
    ("threshold_127_not_released", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "released := meas(i)(7) = '0';", "released := unsigned(meas(i)) < 127;"),
    ("threshold_192_not_open", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "open_pin := meas(i)(7 downto 6) = \"11\";", "open_pin := unsigned(meas(i)) > 192;"),
    ("threshold_191_open", "buttons", "amiga_mouse", TB, "-gG_PART=buttons " + SMALL,
     "open_pin := meas(i)(7 downto 6) = \"11\";", "open_pin := unsigned(meas(i)) >= 191;"),
    ("buttons_start_pressed", "buttons", "amiga_mouse", TB, "-gG_PART=powerup",
     "signal btn_n       : std_logic_vector(1 downto 0) := \"11\";", "signal btn_n       : std_logic_vector(1 downto 0) := \"10\";"),
    ("stuck_time_one_tick_short", "buttons", "amiga_mouse", TB, "-gG_PART=defaults -gG_CLK_HZ=100000 -gG_FREQ=100000",
     "if stuck_cnt = C_STUCK_TICKS - 1 then", "if stuck_cnt = C_STUCK_TICKS - 2 then"),
    # ports
    ("direction_masking_removed", "ports", "debouncer", TP, "-gG_PART=modes",
     "s1_l <= '1'               when amiga_i(0) = '1' else j1_l;", "s1_l <= j1_l;"),
    ("buttons_exchanged", "ports", "debouncer", TP, "-gG_PART=modes",
     UP0, "mouse_up_n(0) <= mouse_middle_n(0) and (j1_f or not rclick(0));"),
    ("fire_masked", "ports", "debouncer", TP, "-gG_PART=modes",
     "s2_f <= j2_f or rclick(1);", "s2_f <= '1' when amiga_i(1) = '1' else j2_f or rclick(1);"),
    ("measured_values_not_unflipped", "ports", "debouncer", TP, "-gG_PART=modes",
     "meas_x(0) <= not pot1_x_i when flip_joys_i = '0' else not pot2_x_i;", "meas_x(0) <= not pot1_x_i;"),
    ("measured_values_not_inverted", "ports", "debouncer", TP, "-gG_PART=modes",
     "meas_y(1) <= not pot2_y_i when flip_joys_i = '0' else not pot1_y_i;",
     "meas_y(1) <= pot2_y_i when flip_joys_i = '0' else pot1_y_i;"),
    ("paddle_output_not_inverted", "ports", "debouncer", TP, "-gG_PART=modes",
     "pot1_x_o <= not mouse_x(s1);", "pot1_x_o <= mouse_x(s1);"),
    ("paddle_output_wrong_socket", "ports", "debouncer", TP, "-gG_PART=modes",
     "pot2_x_o <= not mouse_x(s2);", "pot2_x_o <= not mouse_x(s1);"),
    ("mouse_enable_wrong_socket", "ports", "debouncer", TP, "-gG_PART=modes",
     "         enable_i       => amiga_i(1),", "         enable_i       => amiga_i(0),"),
    ("port_switcher_broken", "ports", "debouncer", TP, "-gG_PART=identity",
     "dbnce_joy1_up_n      <= s1_u when flip_joys_i = '0' else s2_u;", "dbnce_joy1_up_n      <= s1_u;"),
    # ports: the right click with the MEGA key (SPEC.md section 5.1)
    ("rc_swap_follows_key", "ports", "debouncer", TP, RULE,
     R0, "rclick(0)     <= amiga_i(0) and amiga_rclick_i(0) and not mega_key_n_i;"),
    ("rc_swap_follows_key_directed", "ports", "debouncer", TP, DIRECTED,
     R0, "rclick(0)     <= amiga_i(0) and amiga_rclick_i(0) and not mega_key_n_i;"),
    ("rc_ff_updated_while_pressed", "ports", "debouncer", TP, RULE,
     "if j2_f = '1' then\n            rclick_q(1)", "if true then\n            rclick_q(1)"),
    ("rc_decision_one_cycle_late", "ports", "debouncer", TP, RULE,
     R0, LATE),
    ("rc_decision_one_cycle_late_properties", "ports", "debouncer", TP, RULE + ONLY_PROPERTIES,
     R0, LATE),
    ("rc_decision_one_cycle_late_directed", "ports", "debouncer", TP, DIRECTED,
     R0, LATE),
    ("rc_fire_not_released", "ports", "debouncer", TP, RULE,
     "s1_f <= j1_f or rclick(0);", "s1_f <= j1_f;"),
    ("rc_fire_not_released_properties", "ports", "debouncer", TP, RULE + ONLY_PROPERTIES,
     "s1_f <= j1_f or rclick(0);", "s1_f <= j1_f;"),
    ("rc_key_ignored_properties", "ports", "debouncer", TP, RULE + ONLY_PROPERTIES,
     RQ0, "rclick_q(0) <= amiga_i(0) and amiga_rclick_i(0);"),
    ("rc_up_not_pulled", "ports", "debouncer", TP, RULE,
     UP0, "mouse_up_n(0) <= mouse_right_n(0);"),
    ("rc_device_right_lost_in_rclick", "ports", "debouncer", TP, RULE,
     UP0, "mouse_up_n(0) <= (j1_f or not rclick(0)) when rclick(0) = '1' else mouse_right_n(0);"),
    ("rc_device_right_lost_in_rclick_directed", "ports", "debouncer", TP, DIRECTED,
     UP0, "mouse_up_n(0) <= (j1_f or not rclick(0)) when rclick(0) = '1' else mouse_right_n(0);"),
    ("rc_device_right_lost_switch_on", "ports", "debouncer", TP, RULE,
     UP0, "mouse_up_n(0) <= (j1_f or not rclick(0)) when amiga_rclick_i(0) = '1' else mouse_right_n(0);"),
    ("rc_device_right_lost_switch_on_directed", "ports", "debouncer", TP, DIRECTED,
     UP0, "mouse_up_n(0) <= (j1_f or not rclick(0)) when amiga_rclick_i(0) = '1' else mouse_right_n(0);"),
    ("rc_key_polarity", "ports", "debouncer", TP, RULE,
     RQ0, "rclick_q(0) <= amiga_i(0) and amiga_rclick_i(0) and mega_key_n_i;"),
    ("rc_switch_missing_in_q", "ports", "debouncer", TP, RULE,
     RQ0, "rclick_q(0) <= amiga_i(0) and not mega_key_n_i;"),
    ("rc_switch_missing_in_q_directed", "ports", "debouncer", TP, DIRECTED,
     RQ0, "rclick_q(0) <= amiga_i(0) and not mega_key_n_i;"),
    ("rc_switch_missing_in_r", "ports", "debouncer", TP, RULE,
     R0, "rclick(0)     <= rclick_q(0) and amiga_i(0);"),
    ("rc_amiga_missing_in_q", "ports", "debouncer", TP, RULE,
     RQ0, "rclick_q(0) <= amiga_rclick_i(0) and not mega_key_n_i;"),
    ("rc_amiga_missing_in_q_directed", "ports", "debouncer", TP, DIRECTED,
     RQ0, "rclick_q(0) <= amiga_rclick_i(0) and not mega_key_n_i;"),
    ("rc_amiga_missing_in_r", "ports", "debouncer", TP, RULE,
     R0, "rclick(0)     <= rclick_q(0) and amiga_rclick_i(0);"),
    ("rc_switch_of_other_socket", "ports", "debouncer", TP, RULE,
     RQ0, "rclick_q(0) <= amiga_i(0) and amiga_rclick_i(1) and not mega_key_n_i;"),
    ("rc_flip_flops_shared", "ports", "debouncer", TP, RULE,
     R1, "rclick(1)     <= rclick_q(0) and amiga_i(1) and amiga_rclick_i(1);"),
    ("rc_flip_flops_shared_directed", "ports", "debouncer", TP, DIRECTED,
     R1, "rclick(1)     <= rclick_q(0) and amiga_i(1) and amiga_rclick_i(1);"),
    ("rc_socket_0_frozen_while_1_pressed", "ports", "debouncer", TP, RULE,
     "if j1_f = '1' then", "if j1_f = '1' and j2_f = '1' then"),
    ("rc_socket_0_frozen_while_1_pressed_pal", "ports", "debouncer", TP, "-gG_PART=rule -gG_SEED=3 -gG_EPISODES=80",
     "if j1_f = '1' then", "if j1_f = '1' and j2_f = '1' then"),
    ("rc_socket_0_frozen_while_1_pressed_directed", "ports", "debouncer", TP, DIRECTED,
     "if j1_f = '1' then", "if j1_f = '1' and j2_f = '1' then"),
    ("rc_socket_1_frozen_while_0_pressed", "ports", "debouncer", TP, RULE,
     "if j2_f = '1' then\n            rclick_q(1)", "if j2_f = '1' and j1_f = '1' then\n            rclick_q(1)"),
    ("rc_socket_1_frozen_while_0_pressed_directed", "ports", "debouncer", TP, DIRECTED,
     "if j2_f = '1' then\n            rclick_q(1)", "if j2_f = '1' and j1_f = '1' then\n            rclick_q(1)"),
    ("rc_flip_flop_starts_at_one", "ports", "debouncer", TP, DIRECTED,
     "signal rclick_q               : std_logic_vector(1 downto 0) := \"00\";",
     "signal rclick_q               : std_logic_vector(1 downto 0) := \"11\";"),
    ("rc_fire_without_amiga_setting", "ports", "debouncer", TP, "-gG_PART=identity -gG_MODEL=false",
     "s1_f <= j1_f or rclick(0);", "s1_f <= j1_f or (amiga_rclick_i(0) and not mega_key_n_i);"),
    ("rc_up_without_switch", "ports", "debouncer", TP, "-gG_PART=modes -gG_MODEL=false",
     UP0, "mouse_up_n(0) <= mouse_right_n(0) and (j1_f or mega_key_n_i);"),
    # keyb: the MEGA key output of m2m_keyb.vhd
    ("kb_key_60", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "if key_num = 61 then", "if key_num = 60 then"),
    ("kb_key_62", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "if key_num = 61 then", "if key_num = 62 then"),
    ("kb_masked_by_enable_core", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "mega_key_n_o      <= mega_key_n;", "mega_key_n_o      <= mega_key_n when enable_core_i else '1';"),
    ("kb_register_masked_by_enable_core", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "mega_key_n <= key_status_n;", "mega_key_n <= key_status_n when enable_core_i else '1';"),
    ("kb_polarity", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "mega_key_n_o      <= mega_key_n;", "mega_key_n_o      <= not mega_key_n;"),
    ("rc_fire_not_released_e2e", "keyb", "debouncer", TK, "-gG_PART=e2e",
     "s1_f <= j1_f or rclick(0);", "s1_f <= j1_f;"),
    ("kb_starts_at_zero", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "signal mega_key_n          : std_logic := '1';", "signal mega_key_n          : std_logic := '0';"),
    ("kb_core_output_touched", "keyb", "m2m_keyb", TK, "-gG_PART=keyb",
     "key_pressed_n_o   <= key_status_n when enable_core_i else '1';",
     "key_pressed_n_o   <= key_status_n and mega_key_n when enable_core_i else '1';"),
    # wiring: the crossing of the paddle values (the other mutants of the wiring are in wiring.py)
    ("cdc_without_stability_check", "wiring", "cdc_stable", "tb_amiga_cdc", "-gG_CHANGES=100000",
     "if dst_data_d = dst_data_dd then", "if true then"),
    ("flip_inversion_removed", "wiring", "qnice_wrapper", "tb_amiga_flip", "",
     "         qnice_pot1_x_n_o <= x\"FF\" - qnice_pot1_x;", "         qnice_pot1_x_n_o <= qnice_pot1_x;"),
    ("flip_xy_exchanged", "wiring", "qnice_wrapper", "tb_amiga_flip", "",
     "         qnice_pot2_x_n_o <= x\"FF\" - qnice_pot1_x;\n         qnice_pot2_y_n_o <= x\"FF\" - qnice_pot1_y;",
     "         qnice_pot2_x_n_o <= x\"FF\" - qnice_pot1_y;\n         qnice_pot2_y_n_o <= x\"FF\" - qnice_pot1_x;"),
]


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "list":
        for m in MUTANTS:
            name, part, file, unit, args = m[:5]
            kind = "survivor" if len(m) > 7 and m[7] == "survive" else "mutant"
            if part != "none" and sys.argv[2] in ("all", part):
                print(f"{name}|{kind}|{file}|{unit}|{args}")
        return 0
    if len(sys.argv) == 5 and sys.argv[1] == "make":
        m = [x for x in MUTANTS if x[0] == sys.argv[2]]
        if len(m) != 1:
            print(f"    unknown mutant {sys.argv[2]}")
            return 1
        old, new = m[0][5], m[0][6]
        s = open(sys.argv[3]).read()
        if s.count(old) != 1:
            print(f"    mutant {sys.argv[2]}: pattern found {s.count(old)} times (expected once): {old!r}")
            return 1
        open(sys.argv[4], "w").write(s.replace(old, new))
        return 0
    print(__doc__ if __doc__ else "usage: mutants.py list <part> | make <name> <src> <dst>")
    return 2


if __name__ == "__main__":
    sys.exit(main())
