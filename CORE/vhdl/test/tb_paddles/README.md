# Paddle measurement benches (issue #193)

`M2M/vhdl/controllers/M65/mouse_input.vhdl` measures the four paddle pins of the two joystick sockets in the QNICE clock domain (50 MHz, one tick of 1 µs). The four comparator outputs are asynchronous to that clock and pass a two-stage synchronizer, so the edge of a tick sees a pin as it was two clock cycles (40 ns) before. A socket in C64 mode counts the ticks 258 to 512 in which its comparator output reads '0'; a socket in Atari mode (1 MOhm potentiometers of the Atari CX30, inputs `atari_paddles_a` and `atari_paddles_b`) counts the ticks 258 to 767 and delivers half the count, rounded down. While at least one socket is in Atari mode, a measuring cycle has 769 instead of 514 ticks; the modes of a cycle are the inputs at the latch tick of the previous cycle, C64 after power-up. The discharge (`pot_drain`) is on for the ticks 0 to 255 in both kinds of cycle. The mode inputs are read only at the latch tick: whenever both are '0' at every latch tick, every output is, clock cycle by clock cycle, that of the file of the base commit fed with the comparator signals two clock cycles later. Section 6 of `doc/dev-input/SPEC.md` is the specification.

## How to run

```
CORE/vhdl/test/tb_paddles/run.sh [identity|atari|mixed|modes|powerup|synth|mutants|all] [--keep]
```

* `identity`: both sockets in C64 mode against the reference, which is `mouse_input.vhdl` of the base commit `6845596` (`WIP-V6-A25`) with its entity renamed to `mouse_input_ref`; its four comparator inputs pass two flip-flops on the same clock, the synchronizer of the DUT. Every output (`pot_drain`, the four results, the eight joystick outputs, `mouse_debug`) is compared at every change of any of them, over 2000 measuring cycles with random comparator signals of every kind (below), random joystick inputs and random pulses of the mode inputs that are '0' at every latch tick (some of them back to '0' at the clock edge before the latch tick, some starting at the latch tick itself), then 100 further cycles in which the four Amiga inputs change at random as well.
* `atari`: both sockets in Atari mode. The first 40 cycles after power-up put non-monotonic signals on all four pins (chatter around the crossing, signals that fall back to '0' and possibly rise again, before and after tick 512, and noise); then come charge times from 0 to 600 µs in steps of 0.5 µs (the sampling points, whole microseconds minus 40 ns, alternately 1 ns early, exact and 1 ns late), never charging, charge time 0, a pin connected to +5 V, the saturation of both modes to the nanosecond, random charge times and the 1351. Every result from 0 to 255 has to appear on both sockets.
* `mixed`: socket a in C64 mode and socket b in Atari mode, and the other way round. The socket in Atari mode gets non-monotonic signals as in `atari` in every other cycle and charge times from 0 to 600 µs in the others. The socket in C64 mode gets charge times from 0 to 259 µs, a 1351 with every position p from 0 to 63 on both pins, and random signals of every kind; it has to deliver in each cycle exactly what the reference (with the two flip-flops in front of it) delivers in its cycle with the same number, although the cycles of the reference are short and those of the DUT long.
* `modes`: 2000 cycles (with a seed of their own, so the stimuli differ from those of `identity`) in which the two mode inputs change at random clock cycles (gaps from 1 to 60,000 clock cycles), a part of the changes aimed at the clock edges from 3 cycles before to 3 cycles after tick 513 and tick 768 of the running cycle.
* `powerup`: the first cycles after power-up with the modes ab = 00, 11, 01 and 10 from the first clock cycle on, and with modes that change at random from the start.
* `synth`: `ghdl --synth` of `mouse_input` must run without error, and the netlist that GHDL writes must carry the attribute `async_reg` on both stages of the synchronizer (`pot_pins_d`, `pot_pins_dd`). GHDL stops with an error for every inferred latch. Two mutants prove both checks: one with a latch and one without the attributes. The runner also prints the flip-flops of the GHDL netlist (before any optimization): 277 in 46 registers, against 381 in 42 registers for the file of the base commit, whose tick counter and pin counters are unconstrained integers.
* `mutants`: the mutants below, each built and run against the parts listed for it; a mutant is rejected only if every one of its runs fails.
* `all` (default): everything; at most two simulations run at the same time.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. The runtime of `all` is about 9 minutes; one short measuring cycle is 25,700 clock cycles, and GHDL needs 3 to 4 µs per clock cycle and instance.

## The model of the board

`tb_paddles_board.vhd` models the circuit of the board for each pin: the comparator output is '0' while `pot_drain` is '1' and until the charge time after the end of the discharge has passed, then '1' until the next discharge. A 1351 sees the start of the discharge and drives its line high 320 + 2 x p µs later. Random signals also come as chatter (random toggles from 2 µs before to 2 µs after the crossing), as a signal that falls back to '0' and possibly rises again, and as noise that toggles at random also during the discharge. The stimulus of a pin in measuring cycle n is a pure function of the part, the seed, the pin and n (`get_stim` in `tb_paddles_pkg.vhd`), so the two board models in front of the DUT and of the reference deliver the same stimulus per cycle, each relative to its own discharge.

## What the checker proves

The checker of an instance sees only its ports. A cycle starts with the rising edge of `pot_drain`; the discharge has to last exactly 256 ticks and the cycle exactly 514 or 769 ticks, according to the modes that the DUT saw at the latch tick of the previous cycle; the results may change only in the clock cycle after the latch tick. An observer samples every pin at the clock edge two cycles before the edge of each tick, the edge at which the synchronizer of the DUT takes the sample that the tick uses, and counts the '0' samples of the C64 window (ticks 258 to 512) and of the Atari window (258 to 767). The result of a socket in C64 mode has to be the C64 count, that of a socket in Atari mode half the Atari count, rounded down, for every kind of signal. For a monotonic signal the result also has to follow the relation below, and in the parts `atari` and `mixed` a socket in Atari mode has to deliver half the C64 result of the reference (rounded down) wherever that is below 255. In the parts `atari` and `mixed` the reference gets the signals of its own board model through two flip-flops, as in `identity`. The part `identity` validates the observer against the reference over all 2000 cycles.

The range of the tick counter (0 to 768) and of the four pin counters (0 to 510) is their declared range, which GHDL checks at every assignment: a violation stops the simulation without `RESULT PASS` (the mutant `latch_late` shows it). GHDL 5.1.1 cannot read a signal of the DUT through a VHDL-2008 external name (the simulation stops with "NULL access dereferenced"), so the bench does not look at the counter directly.

## The relation between charge time and result

Let t be the time from the end of the discharge (the clock edge of tick 256, after which `pot_drain` is '0') to the change of the comparator output to '1' at the pin of the FPGA; a change exactly at a clock edge is seen at the next edge. The edge of tick k sees the pin as it was at the edge 40 ns before, (k - 256) µs - 40 ns after the end of the discharge. Then, as checked by the bench for every monotonic signal:

* C64 mode: `min(255, max(0, floor((t + 40 ns) / 1 us) - 1))`
* Atari mode: `floor(min(510, max(0, floor((t + 40 ns) / 1 us) - 1)) / 2)`
* a capacitor that never charges reads 255 in both modes

The first counted tick is tick 258, whose sample is taken 1.960 µs after the end of the discharge: a pin that charges within 1.960 µs reads 0, which includes a pin connected to +5 V (0.3 to 0.8 µs through the 1 kOhm series resistor). The steps of the C64 result lie at t = k µs - 40 ns; it saturates from t = 255.960 µs on, and the Atari result from t = 510.960 µs on. For the same signal the Atari result is the C64 result divided by two and rounded down, as long as the C64 result is below 255. A 1351 at position p (t = 64 + 2 x p µs) reads 63 + 2 x p in C64 mode.

## Mutants

Each mutant is an exact text replacement in a copy of `mouse_input.vhdl`, or three of them for `atari_first_one`, which needs a signal of its own; every text to be replaced has to occur exactly once. `run.sh mutants` prints each mutant with the first error of each of its runs. A mutant whose text no longer occurs, or that does not analyze or elaborate, is a failure of the suite and not a rejection, so that a stale replacement cannot pass for a rejected mutant.

| Mutant | Change | Rejected by |
|---|---|---|
| `no_sync` | no synchronizer: the measurement samples the pins directly | `identity` |
| `one_stage` | synchronizer with one stage | `identity` |
| `three_stages` | synchronizer with three stages | `identity` |
| `atari_first_one` | an Atari pin (pin 9 of socket a) counts only until its first '1' after tick 512 | `atari`, `mixed` 10 and `modes` |
| `atari_after_one` | an Atari pin counts after tick 512 only if it read '0' in every tick since tick 258 | `atari`, `mixed` 10 and `modes` |
| `halve` | Atari result of pin 9 of socket a not halved | `atari` |
| `round_up` | Atari result rounded up | `atari` |
| `window_short_a`, `window_short_b` | Atari window of a socket as short as the C64 window | `powerup` 10, 01 |
| `c64_beyond_a`, `c64_beyond_b` | a socket in C64 mode counted up to tick 767 in a long cycle | `powerup` 01, 10 |
| `no_extend` | cycle never long | `powerup` 11 |
| `always_long` | cycle always long | `powerup` 00 |
| `extend_a_only` | only socket a in Atari mode makes the cycle long | `powerup` 01 |
| `latch_late` | long cycle of 770 ticks | `powerup` 11 (range of the tick counter, 0 to 768) |
| `unlatched` | modes taken over from the inputs in every clock cycle | `modes` |
| `relatch_256` | the mode of socket a also taken over at the end of the discharge | `modes` |
| `latch_plus1` | the modes taken over one clock cycle after the latch tick | `modes` |
| `swap` | the modes of the sockets a and b exchanged | `mixed` 10 |
| `drain_long` | discharge of 257 ticks in a long cycle | `powerup` 11 |
| `guard_255` | the counter of an Atari pin saturates at 255 | `powerup` 01 |
| `powerup_long` | socket b in Atari mode at power-up | `powerup` 00 |
| `c64_halved` | C64 result of pin 9 of socket b halved | `identity` |
| `latch` (part `synth`) | a latch on an unused signal | `ghdl --synth` |
| `no_async_reg` (part `synth`) | the synchronizer without the attribute `async_reg` | the check of the netlist |

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: reference, builds, runs, synthesis check, mutants |
| `tb_paddles.vhd` | Bench: DUT, reference, mode stimulus, checkers, identity comparison |
| `tb_paddles_board.vhd` | Model of the board circuit and of the devices on the paddle pins |
| `tb_paddles_pkg.vhd` | Stimuli per part and cycle, expected results, random numbers |
