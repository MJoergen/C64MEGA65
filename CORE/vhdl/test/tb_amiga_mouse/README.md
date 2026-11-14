# Amiga mouse benches (issue #190)

`M2M/vhdl/amiga_mouse.vhd` turns the Amiga mouse of one joystick socket into a Commodore 1351 in proportional mode: a synchronizer and a glitch filter per line, a quadrature decoder per axis, a backlog with a rate limiter, the position as POT values with full units only, and the right and middle button derived from the measured paddle values. `M2M/vhdl/debouncer.vhd` conditions the two joystick ports: debouncing, two Amiga mice, the port switcher and the on/off switches of the Shell. The specification is `doc/dev-input/SPEC.md`, sections 4 and 5.

## How to run

```
CORE/vhdl/test/tb_amiga_mouse/run.sh [decoder|buttons|ports|synth|all] [--keep] [--jobs N] [--no-mutants]
```

* `decoder`: `amiga_mouse` alone (`tb_amiga_mouse.vhd`), the parts `dir`, `double`, `pulse`, `model`, `rate_follow`, `rate_sat`, `rate_tick`, `driver`, `enable` and `times` below, plus the mutants of the decoder.
* `buttons`: the parts `buttons` and `defaults`, plus the mutants of the button logic.
* `ports`: `debouncer` (`tb_amiga_ports.vhd`), the parts `identity` and `modes`; the differential analysis of `framework.vhd`; plus the mutants of the port conditioning.
* `synth`: `ghdl synth` of `amiga_mouse` and of `debouncer`.
* `all` (default): everything.
* `--keep`: keeps the build directory (with one log per simulation) and prints its path. `--jobs N`: number of parallel simulations (default 4, or the variable `JOBS`). `--no-mutants`: skips the mutants.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 9 minutes with 4 processes (20 minutes of processor time); every simulation has a timeout of 25 minutes.

## The decoder and the buttons (`tb_amiga_mouse.vhd`)

The bench sees the DUT only through its ports (GHDL 5.1.1 does not resolve external names to signals of the DUT). The main checks of the decoder and the driver run at the real clock frequency, 31,527,778 Hz, and the times also at 32,727,273 Hz (the NTSC core clock) with `G_CLK_FREQ` at the PAL value. With `G_STEP_US = 1` the rate limiter ticks every 31 clock cycles and makes every count of the decoder visible within a microsecond; the parts that check the decoder itself use it, all other parts run with the default generics. The parts of the buttons use small time generics (`G_STEP_US = 10`, `G_CONFIRM_US = 100`, `G_STUCK_MS = 5`, which keep the ratios of 10 ticks to confirm a change), and the part `defaults` checks the default times at a slow clock.

The POT value carries full units only (two counts), so the bench tracks the position that it expects in counts and checks the POT value against `64 + position` with bit 0 cleared.

* Mouse model, one per axis: a phase in counts that a piecewise constant speed profile moves, asynchronous to the clock; the four transitions of a cycle lie at 0, `phase / 90`, 2 and `2 + phase / 90`, so the phase between the two lines is 60 to 120 degrees as the generics say, and the counts per second are exact on average. The lines show the sequences of SPEC.md section 4.2, written into `tb_amiga_mouse_pkg.vhd` from the table of the specification.
* Line drivers: with chatter every edge is a burst that ends at the new level, either the new level followed by 1 to 4 pulses of 50 to 500 ns back to the old level, or a slow edge with 3 to 7 toggles of 10 to 200 ns.
* Checker per axis, at every falling clock edge: every change of the POT value is one unit (mod 128) and never comes faster than one per tick; the value always has the format `pot(7) = position(6)`, `pot(6) = not position(6)`, `pot(5 downto 1) = position(5 downto 1)`, `pot(0) = '0'`; optionally the output lies within the true positions of a time window (follow check), and optionally every count that crosses a unit boundary reaches the output in order and within a bound (delay check).

| Part | Generics | What it proves |
|---|---|---|
| `dir` | `G_STEP_US = 1`, and the defaults | start value `0x40`; all four transitions of both sequences in both directions count exactly +1 or -1 on their own axis; the POT value changes on every second count (upwards from an odd to an even position, downwards from an even to an odd one) and is exact after every count; +200 and -260 counts wrap within `0x40` to `0xBE` |
| `double` | `G_STEP_US = 1` | a change of both lines of a pair counts nothing, from every state and at both parities, and the next transitions count as the new state says; 600 random moves of both axes at the same instants (+1, -1, double) |
| `pulse` | `G_STEP_US = 1`, PAL and NTSC clock | 300 pulses per line state (16 states) of 5 ns to 62.7 clock periods, single and overlapping on two lines, at least two clock periods apart: no output changes in any clock cycle; 128 pulses of 64.3 clock periods always pass as a count and its reverse (visible when the first count crosses a unit boundary): the filter time in clock periods, 1.989 to 2.040 us at the PAL clock, 1.916 to 1.965 us at the NTSC clock |
| `model` | `G_STEP_US = 1`, phases 60/120, 90/75, 120/100 | both axes at the same time with independent random profiles from 3 to 20,000 counts per second, both directions, pauses and single steps, chatter on every edge: in every clock cycle the output lies within the true positions of the last 10 us, and after each run it is exactly the true position |
| `rate_follow` | defaults, phases 90/90 and 60/120, two parities | constant speeds of 100, 500, 1000, 2000 and 2400 counts per second: every count reaches the output within one step time plus the latency of the pin (90 degrees), or within two step times minus the shortest edge spacing at 2400 counts per second (60 to 120 degrees, 530 us); a last run with clean edges measures the wait in the backlog and from it the largest backlog; parity 1 makes one count while `enable_i` is '0', so that the other half of the counts crosses the unit boundaries |
| `rate_sat` | defaults | 4000, 8000 and 20,000 counts per second for 100 ms, then stop: never against the direction of the mouse, one count per tick without a gap (one unit every second tick), 63 or 64 units after the stop, and the number of counts that reached the output is what the bound implies |
| `rate_tick` | defaults | a count of the decoder in the clock cycle of a step of the rate limiter (17 offsets around the predicted cycle, both axes, both parities): both take effect |
| `driver` | defaults, PAL clock and frame, NTSC clock and frame | the movement routine of the 1351 manual, called once per frame (19.950 ms or 16.715 ms) with a jitter of plus or minus 1 ms; up to 2400 counts per second, both directions, the sum of its results is in every call `floor(n / 2)` of a true position `n` of the last two step times and equals the movement of the output in units, so no unit is lost or invented; from 2500 to 20,000 counts per second it never returns a movement against the direction of the mouse and stays exact |
| `enable` | defaults | while `enable_i` is '0' a moving mouse changes nothing and no button is reported; enabling in each of the 16 line states counts nothing (followed by a walk of two counts up and down with exact POT values); disabling with a full backlog keeps the position and nothing follows after enabling; while disabled during a movement exactly the counts outside of that time reach the output; `enable_i` at '0' releases the buttons within one clock cycle and clears their flags |
| `times` | defaults, PAL and NTSC clock | the step time is exactly 12,610 clock periods (399.96 us, 385.31 us at the NTSC clock); a change of a button is reported 10 to 11 ticks after it began (4.000 to 4.400 ms, 3.853 to 4.238 ms) |
| `buttons` | small time generics | per button, with the other one at a constant value: without pull-up (255 and single samples of 192 to 254) never reported over three stuck times; with pull-up 11 to 16 released and 255 pressed, reported 10 to 11 ticks after the change; values of 128 to 191 change nothing and interrupt a confirmation; changes of 0.30 to 0.98 confirmation times are ignored; a press without interruption is released after exactly the stuck time and reported again only after a value below 128; `enable_i` at '0' releases the button and clears the flag |
| `defaults` | 100 kHz clock, default time generics | one count per 400 us, a press is reported 4.0 to 4.4 ms after it began and released after exactly 30.000 s |

## The port conditioning (`tb_amiga_ports.vhd`)

Beside the DUT run `debouncer_ref`, the entity of commit `6845596` (before the Amiga mice) that `run.sh` takes from git and renames, and two instances of `amiga_mouse` with the generics of the DUT that get the raw lines and the true measured values of each socket. The paddle inputs of the DUT are what the core delivers: switched to C64 ports and inverted. The outputs are compared 1 ps after every event of an input, of an output of the DUT, of `debouncer_ref` or of a reference mouse.

* `identity`: `amiga_i` at "00" and 300 ms of random activity on the ten lines (mostly long enough for the 1 ms debouncer), the port switcher, the on/off inputs, resets and the paddle values: the ten joystick outputs are identical to those of `debouncer_ref`, and the four paddle outputs equal the paddle inputs.
* `modes`: all 32 combinations of `flip_joys_i`, `amiga_i(0)`, `amiga_i(1)`, `joy_1_on` and `joy_2_on` for 12 to 16 ms each, then 30 random switches during activity. A socket in Amiga mode gets quadrature on both pairs, the left button on fire and right and middle button presses as measured values; a socket in C64 mode gets random joystick lines and paddle values. For each C64 port: switched off, all five lines are '1'; connected to a socket in Amiga mode, left and right are '1', up is the right button and down the middle button of the reference mouse of that socket, fire is the debounced fire line and the paddle outputs are the inverted position of that mouse; connected to a socket in C64 mode, everything is as in `debouncer_ref`. The quadrature of an Amiga socket therefore never reaches a direction output. The reference mice have to change their buttons and positions often enough, or the bench fails.

`run.sh ports` also analyzes the complete `framework.vhd` with the old and with the new debouncer in otherwise identical libraries: the diagnostics (entities that are not part of this bench) must be identical, so the existing instantiation still analyzes unchanged.

## Synthesis

`ghdl synth` of `amiga_mouse` (`G_CLK_FREQ = 31,527,778`) and of `debouncer` must run without an error and without a latch; the runner prints the number of flip-flops of the netlist (147 for one `amiga_mouse`; Vivado removes the constant bit 0 of the POT registers and may merge the POT bits with the position bits they copy). GHDL ignores the attribute `async_reg`; the runner checks that both synchronizer stages carry it.

## Mutants

Each mutant is one exact text replacement in a copy of a source (`mutants.py`); the named bench part runs it with `G_STOP` and must not end with `TB: RESULT PASS`.

| Mutant | Change | Rejected by |
|---|---|---|
| `x_direction_swapped`, `y_direction_swapped` | the two lines of a pair exchanged in the decoder | `dir` |
| `pairs_exchanged` | X decoded from (left, up), Y from (right, down) | `dir` |
| `pot_plus_64_wrong` | the POT value without the +64 mapping | `dir` |
| `pot_bit0_exported` | bit 0 of the position in the POT value | `driver` with the output checkers off: the exactness check of the driver |
| `double_transition_counted` | a change of both lines counts | `double` |
| `filter_removed`, `filter_half`, `filter_one_cycle_longer` | no filter, half the filter time, one clock period more | `pulse` |
| `one_synchronizer_stage` | one synchronizer stage instead of two | expected to survive: it only shortens the latency by one clock cycle, which no port shows, and removes the protection against metastability, which no simulation sees |
| `rate_limiter_removed` | every count moves the position at once | `driver` with the output checkers off: the driver returns a movement against the direction of the mouse |
| `backlog_bound_removed` | no count is dropped | `rate_sat` (the backlog leaves its range) |
| `count_lost_at_a_step` | a count in the clock cycle of a step is lost | `rate_tick` |
| `step_time_wrong` | 2.4 % shorter step time | `times` |
| `backlog_kept_while_disabled`, `counting_while_disabled`, `decoder_frozen_while_disabled` | `enable_i` at '0' keeps the backlog, keeps counting, or stops the decoder from following the lines | `enable` |
| `button_thresholds_exchanged`, `stuck_release_removed`, `stuck_release_keeps_flag`, `pullup_flag_ignored`, `confirmation_one_tick_short`, `mid_values_count`, `flag_kept_while_disabled`, `middle_button_from_pin_9` | the rules of SPEC.md section 4.5 | `buttons` |
| `stuck_time_one_tick_short` | the stuck time one tick shorter | `defaults` |
| `direction_masking_removed`, `buttons_exchanged`, `fire_masked`, `measured_values_not_unflipped`, `measured_values_not_inverted`, `paddle_output_not_inverted`, `paddle_output_wrong_socket`, `mouse_enable_wrong_socket` | the rules of SPEC.md section 5 | `modes` |
| `port_switcher_broken` | the port switcher of one line | `identity` |
| `amiga_i_no_default` | the new input `amiga_i` without a default value | the differential analysis of `framework.vhd` |

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, simulations in parallel, mutants, differential analysis, synthesis |
| `mutants.py` | The mutants |
| `tb_amiga_mouse_pkg.vhd` | Sequences of SPEC.md section 4.2, random numbers, the movement routine of the 1351 manual, helpers |
| `tb_amiga_mouse.vhd` | Bench of `amiga_mouse`: mouse model, line drivers with chatter, checkers, driver model, the parts |
| `tb_amiga_ports.vhd` | Bench of `debouncer` against `debouncer_ref` and two reference mice |
