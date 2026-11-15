#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# Amiga mouse benches (GitHub issue #190): the mutants, used by run.sh
#
#   mutants.py list <part>           name|kind|file|unit|bench arguments for the mutants of a part
#                                    (decoder, buttons, ports or all); kind is "mutant" (must be
#                                    rejected) or "survivor" (expected to survive, reported only)
#   mutants.py make <name> <src> <dst>   copy src to dst with the text of the mutant replaced;
#                                    the old text must occur exactly once
#
# Each mutant is one exact text replacement in M2M/vhdl/amiga_mouse.vhd, M2M/vhdl/debouncer.vhd or
# M2M/vhdl/cdc_stable.vhd, and names the bench run that has to reject it.
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

import sys

FAST = "-gG_STEP_US=1"
SMALL = "-gG_STEP_US=10 -gG_CONFIRM_US=100 -gG_STUCK_MS=5"
TB = "tb_amiga_mouse"
TP = "tb_amiga_ports"

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
     "s1_u <= mouse_right_n(0)  when amiga_i(0) = '1' else j1_u;", "s1_u <= mouse_middle_n(0)  when amiga_i(0) = '1' else j1_u;"),
    ("fire_masked", "ports", "debouncer", TP, "-gG_PART=modes",
     "s2_f <= j2_f;", "s2_f <= '1' when amiga_i(1) = '1' else j2_f;"),
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
    # wiring: the crossing of the paddle values (the other mutants of the wiring are in wiring.py)
    ("cdc_without_stability_check", "wiring", "cdc_stable", "tb_amiga_cdc", "-gG_CHANGES=100000",
     "if dst_data_d = dst_data_dd then", "if true then"),
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
