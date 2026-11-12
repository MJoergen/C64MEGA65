# Stereo Mix benches (issue #247)

The `Volume` submenu contains a nested `Stereo: %s` submenu with `Full Stereo` (default), `Wide Stereo`, `Narrow Stereo` and `Mono`. It blends the two channels of a stereo SID setup, which play hard left and hard right and can be tiring on headphones. The blends are those of MiSTer's `aud_mix_top` (`sys/audio_out.sv`), which MiSTer's C64 core offers as "Stereo Mix" None / 25% / 50% / 100%:

| Setting | MiSTer | Own side | Opposite side |
|---|---|---|---|
| `Full Stereo` | None | 100% | 0% |
| `Wide Stereo` | 25% | 87.5% | 12.5% |
| `Narrow Stereo` | 50% | 75% | 25% |
| `Mono` | 100% | 50% | 50% |

`CORE/vhdl/mega65.vhd` decodes the radio group into `main_stereo_mix` (MiSTer's `AUDIO_MIX` encoding) and passes it to `main.vhd`, where `audio_stereo_mix_proc` applies it to the SID mix (`alo`/`aro`), one register in front of the master volume (`audio_volume_proc`). That is the single point that feeds HDMI and the 3.5 mm jack, so both outputs behave the same, whatever "Audio improvements" is set to. M2M's own copy of MiSTer's mixer (`audio_out.v` in the AV pipeline, `audio_mix` in `globals.vhd`) is not used for this, because the AV pipeline bypasses it while "Audio improvements" is off; `audio_mix` stays `"00"`.

The blends are weighted averages, so they cannot clip (the saturating `clamp16` mirrors MiSTer's output clamp and never acts; removing it is an equivalent change the bench cannot see). A mono SID setup drives both channels with the same signal: then `Full`, `Wide` and `Narrow` return it unchanged and `Mono` changes it by one LSB at most, so the setting is only audible with a stereo SID. That is also why the main-menu line shows the Stereo Mix only while a stereo SID is selected (`Volume: 80% Wide`; `SUBMENU_SUMMARY` in `CORE/m2m-rom/m2m-rom.asm`, tested by `M2M/rom/tests/summary_test.py`).

## How to run

```
CORE/vhdl/test/tb_stereo_mix/run.sh [mix|decode|wiring|all] [--keep]
```

* `mix`: the audio path of `main.vhd`, copied verbatim into `tb_stereo_mix.vhd.in` (the volume LUT, `audio_stereo_mix_proc` and `audio_volume_proc`), against the golden model `golden.py`, in two phases. Phase 1, the arithmetic: 9192 vectors (every pair of 27 corner samples in all four modes, identical channels as from a mono SID, 6000 random samples with random modes and volumes, every volume step at full scale), each held for two clock cycles and compared bit by bit. Phase 2, the latency: 768 random samples streamed at one sample per clock cycle, in blocks with a constant mode and volume; each must appear at the output exactly two clock cycles later (crossfeed register, then volume register), so a shallower or deeper pipeline fails. `golden.py` is an independent transcription of `aud_mix_top` with Verilog bit-slice semantics, plus the master volume; it also checks that `C_VOL_LUT` of `main.vhd` matches its definition. Six mutants must fail: wrong shift in `Wide`, wrong channel in `Narrow`, `Mono` not mixing both channels, the volume stage bypassing the crossfeed, `Wide`/`Narrow` swapped, and a combinational (unregistered) crossfeed.
* `decode`: the decode of `mega65.vhd`, copied verbatim into `tb_stereo_mix_decode.vhd.in`: each of the four items alone and the empty selection (must decode to `Full Stereo`), with all other menu bits at `'0'` and at `'1'`. Two mutants must fail: `Wide` decoded from the `Narrow` bit, and `Mono` missing.
* `wiring`: differential GHDL analysis of the complete `main.vhd` and `mega65.vhd` against the base commit `1470473` (`WIP-V6-A22X2`), each `mega65.vhd` against the entity declaration of `main` of the same tree, so the new port and its association are checked; neither may show a single new diagnostic. Two mutants must be caught: an unconnected `audio_stereo_mix_i` and an undeclared signal in the volume stage.
* `all` (default): everything.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 10 seconds.

MiSTer takes the opposite channel from its previous sample (a one-cycle skew of its register pipeline at the audio clock); `main.vhd` mixes both channels of the same sample, and so does the model. The arithmetic is identical.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, runs, mutants, differential analysis |
| `golden.py` | Golden model (MiSTer `aud_mix_top` plus master volume) and vector generator |
| `tb_stereo_mix.vhd.in` | Template of the audio-path bench; `run.sh` copies the code out of `main.vhd` into it |
| `tb_stereo_mix_decode.vhd.in` | Template of the decode bench; `run.sh` copies the decode out of `mega65.vhd` into it |
