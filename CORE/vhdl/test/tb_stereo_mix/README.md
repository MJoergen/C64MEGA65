# Stereo Mix benches (issue #247)

The `Volume` submenu contains a nested `Stereo: %s` submenu with `Full Stereo` (default), `Wide Stereo`, `Narrow Stereo` and `Mono`. It blends the two channels of a stereo SID setup, which play hard left and hard right and can be tiring on headphones. The blends are those of MiSTer's `aud_mix_top` (`sys/audio_out.sv`), which MiSTer's C64 core offers as "Stereo Mix" None / 25% / 50% / 100%:

| Setting | MiSTer | Own side | Opposite side |
|---|---|---|---|
| `Full Stereo` | None | 100% | 0% |
| `Wide Stereo` | 25% | 87.5% | 12.5% |
| `Narrow Stereo` | 50% | 75% | 25% |
| `Mono` | 100% | 50% | 50% |

`CORE/vhdl/mega65.vhd` decodes the radio group into `main_stereo_mix` (MiSTer's `AUDIO_MIX` encoding) and passes it to `main.vhd`, where `audio_stereo_mix_proc` applies it to the SID mix (`alo`/`aro`), one register in front of the master volume (`audio_volume_proc`). That is the single point that feeds HDMI and the 3.5 mm jack, so both outputs behave the same, whatever "Audio improvements" is set to. M2M's own copy of MiSTer's mixer (`audio_out.v` in the AV pipeline, `audio_mix` in `globals.vhd`) is not used for this, because the AV pipeline bypasses it while "Audio improvements" is off; `audio_mix` stays `"00"`.

The decoder `stereo_mix_decode_proc` is a register that starts at `Full Stereo` and holds its value while no item of the group is set, built like the decoder of the master volume (`volume_decode_proc`) and for the same reason: the Shell writes the menu bits one at a time and the framework moves every bit of the menu vector into the main clock domain on its own, so while the selection moves from one item to another, the main clock domain can briefly see no bit or two bits set. Holding the value on "no bit" means that only the old and the new mix are ever applied; with two bits set, the fixed order of the checks in the decoder picks one of the two.

The blends are weighted averages, so they cannot clip (the saturating `clamp16` mirrors MiSTer's output clamp and never acts; removing it is an equivalent change the bench cannot see). A mono SID setup drives both channels with the same signal: then `Full`, `Wide` and `Narrow` return it unchanged and `Mono` changes it by one LSB at most, so the setting is only audible with a stereo SID. That is also why the main-menu line shows the Stereo Mix only while a stereo SID is selected (`Volume: 80% Wide`; `SUBMENU_SUMMARY` in `CORE/m2m-rom/m2m-rom.asm`, tested by `M2M/rom/tests/summary_test.py`).

## How to run

```
CORE/vhdl/test/tb_stereo_mix/run.sh [mix|decode|wiring|all] [--keep]
```

* `mix`: the audio path of `main.vhd`, copied verbatim into `tb_stereo_mix.vhd.in` (the volume LUT, `audio_stereo_mix_proc` and `audio_volume_proc`), against the golden model `golden.py`, in two phases. Phase 1, the arithmetic: 9192 vectors (every pair of 27 corner samples in all four modes, identical channels as from a mono SID, 6000 random samples with random modes and volumes, every volume step at full scale), each held for two clock cycles and compared bit by bit. Phase 2, the latency: 768 random samples streamed at one sample per clock cycle, in blocks with a constant mode and volume; each must appear at the output exactly two clock cycles later (crossfeed register, then volume register), so a shallower or deeper pipeline fails. `golden.py` is an independent transcription of `aud_mix_top` with Verilog bit-slice semantics, plus the master volume; it also checks that `C_VOL_LUT` of `main.vhd` matches its definition. Six mutants must fail: wrong shift in `Wide`, wrong channel in `Narrow`, `Mono` not mixing both channels, the volume stage bypassing the crossfeed, `Wide`/`Narrow` swapped, and a combinational (unregistered) crossfeed.
* `decode`: the decoder of `mega65.vhd` (the four `C_MENU_STEREO_MIX_*` constants, the declaration of `main_stereo_mix` with its power-up value, and `stereo_mix_decode_proc`), copied verbatim into `tb_stereo_mix_decode.vhd.in`; the runner fails if it cannot find them, and a lint makes it fail if the identifier `main_stereo_mix` occurs in `mega65.vhd` (outside of comments) anywhere else than in its declaration, inside `stereo_mix_decode_proc` and in exactly one port association `audio_stereo_mix_i => main_stereo_mix`, so that the process is its only driver. The bench checks the power-up value (`Full Stereo` in every clock cycle while no item has ever been selected), each of the four items alone, the hold (the empty selection keeps each of the four values for 100 clock cycles) and all 12 transitions between two items, each torn both ways (first no bit set, then the new bit; first both bits set, then only the new bit), with a monitor that allows only the old and the new value in every clock cycle of a transition, and the new value at its end; all of it with all other bits of the 512-bit menu vector at `'0'` and at `'1'`. These checks change the selection on the falling edge of the clock and sample on the next falling edge, so a timing check pins the decoder to exactly one register on the rising edge of `main_clk_o`: the selection changes 1 ns after a rising edge, the output is sampled every 1 ns and must keep the old value up to 1 ns before the next rising edge (so also 1 ns after the change and 1 ns after the falling edge in between), and 1 ns after that rising edge it must have the new value; this for the step from the power-up state to the first item ever selected and for all 12 transitions, with the other menu bits at `'0'` and at `'1'`. Eleven mutants must fail in the bench: the combinational decoder that decodes the empty selection to `Full Stereo`, a register that falls back to `Full Stereo` when no bit is set, `Wide` decoded from the `Narrow` bit, `Mono` missing, the `Full Stereo` bit ignored, no power-up value, `Mono` as the power-up value, `Wide` plus `Narrow` decoded to `Mono` (a third value that only the phase with both bits set can show), and three that only the timing check can see: the decoder without the clock (a transparent latch), the register on the falling edge, and two registers in a row. A twelfth mutant tests the lint: one more assignment `main_stereo_mix(1) <= '0';` behind the process must be refused at the extraction.
* `wiring`: differential GHDL analysis of the complete `main.vhd` and `mega65.vhd` against the base commit `1470473` (`WIP-V6-A22X2`), each `mega65.vhd` against the entity declaration of `main` of the same tree, so the new port and its association are checked; neither may show a single new diagnostic. Two mutants must be caught: an unconnected `audio_stereo_mix_i` and an undeclared signal in the volume stage.
* `all` (default): everything.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 30 seconds.

MiSTer takes the opposite channel from its previous sample (a one-cycle skew of its register pipeline at the audio clock); `main.vhd` mixes both channels of the same sample, and so does the model. The arithmetic is identical.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, runs, mutants, differential analysis |
| `golden.py` | Golden model (MiSTer `aud_mix_top` plus master volume) and vector generator |
| `tb_stereo_mix.vhd.in` | Template of the audio-path bench; `run.sh` copies the code out of `main.vhd` into it |
| `tb_stereo_mix_decode.vhd.in` | Template of the decode bench; `run.sh` copies the decoder out of `mega65.vhd` into it |
