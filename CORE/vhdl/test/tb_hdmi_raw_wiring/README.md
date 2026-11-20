# tb_hdmi_raw_wiring

Bench of the genlock wiring in `M2M/vhdl/av_pipeline/digital_pipeline.vhd` (issue #184, `doc/dev-hdmi-raw/SPEC.md` section 5.1): the reference pulse, the instance of the genlock and the multiplexer in front of the scaler's `htotal` port.

```
CORE/vhdl/test/tb_hdmi_raw_wiring/run.sh            # all scenarios, about 10 minutes with JOBS=2
CORE/vhdl/test/tb_hdmi_raw_wiring/run.sh C E        # some of them
CORE/vhdl/test/tb_hdmi_raw_wiring/run.sh mutants    # the mutant table below, about 20 minutes
```

## What runs

- The real `digital_pipeline.vhd` with the real `hdmi_genlock.vhd`, fed through the real `crop.vhd` as `av_pipeline.vhd` wires it.
- The scaler is `ascal_timing.vhd`: the entity declaration of the real `ascal.vhd` with an architecture that contains only its output timing generator, cycle exact (the timing inputs registered in every clock cycle, process `OSWEEP`, the output registers of `VSCAL`, 11 clock cycles behind the counters).
- The core is a model of the syncs and the blanking of `CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd`, one dot per four core clocks: PAL 504 x 312, NTSC 520 x 263. Its vblank changes at dot 0 of a line, inside the horizontal blanking, as in `video_sync.vhd`.
- `video_overlay`, `vga_to_hdmi` and the serializers are empty stand-ins (not under test).
- The clock periods are chosen in femtoseconds so that a core frame has exactly as many pixel clocks of the raw mode as in the hardware (only the time scale differs slightly), so the genlock sees the real ratio and the static modes do not drift.
- The hostile build (scenario H) replaces the genlock with `genlock_hostile.vhd`: its `htotal_o` is `htotal_i + 7` in every clock cycle, also with `enable_i = '0'`.

## Scenarios

| | Core | Zoom-in | Segments |
|---|---|---|---|
| A | PAL | off | raw 16:9 50 until locked; to raw 4:3 50 with a change of the clock (`hdmi_rst_i` pulsed); to 4:3 50 (pulse); back to raw 4:3 50 (pulse) |
| B | PAL | on | raw 4:3 50 until locked |
| C | PAL | off | raw 5:4 50 until locked |
| D | NTSC | off | raw 16:9 59.94 until locked |
| E | NTSC | on | 4:3 59.94 without the core; to raw 4:3 59.94 without a change of the clock (no pulse) until locked; back to 4:3 59.94 without a pulse |
| F | NTSC | on | raw 5:4 59.94 until locked |
| G | PAL | off | the ten standard modes, two frames each, with a pulse where the clock changes, and two one-cycle raw codes between two standard modes (`1010` between `0111` and `1000`, `1101` between `1001` and `0000`) |
| H | PAL | off | hostile genlock: the ten standard modes, then raw 16:9 50 for a few lines |

For a lock the bench starts the core model at a moment that puts the first valid measurement of the genlock 600 pixel clocks below the target, so the lock comes after 8 measurements instead of the pull-in of up to 8 seconds that an arbitrary phase can take (that pull-in is the subject of the genlock's own bench).

## Checks (`check_wiring.py`)

- **Reference**, in every scenario: one core clock after every rising edge of the cropped vsync the reference register falls (if it was set); it rises one core clock after the first moment with both cropped blanking signals low, and at no other time. Every rise gives exactly one `hdmi_ref` pulse of exactly one HDMI clock, 1 to 3 HDMI clocks later, and there is no other pulse. With zoom-in the cropped vblank falls in every visible line (194 times per frame in PAL), the reference once per frame.
- **Standard modes** (all ten, in G and in the hostile H): the scaler's `htotal` is the line length of the record in every clock cycle, and so is `hdmi_htotal`; in H the genlock's output differs from it in every clock cycle, so the multiplexer is what keeps the scaler right.
- **Raw modes** (all six): the scaler gets the genlock's `htotal_o` in every clock cycle; the target is 2 x `CLK_KHZ`; the distance of every HDMI picture start from the last reference, measured from the VCD, agrees with the stretch that the genlock takes (checked at or below the target and up to 4096 pixel clocks above it, where every version of the control law of SPEC 5.3 gives the same stretch); `locked_o` rises once and stays; after the lock every distance lies within `target - surplus - 2` to `target + 2` (surplus of SPEC 4.2: 197 and 463 pixel clocks in 720p, 0 in 576p and 480p, where the distance is the target exactly).
- **Mode changes**: into a raw mode with a change of the clock (A, segment 4) and without one (E), out of a raw mode with (A, segment 3) and without one (E, segment 3); raw to raw with a pulse (A, segment 2): the genlock was locked before the pulse, is not locked at its end and not before its first valid measurement after it.
- **One-cycle raw codes** (G): in that clock cycle the scaler gets the `htotal` of the record of that code (`doc/dev-hdmi-raw/SPEC.md` 5.1, the comment at `hdmi_raw` in `digital_pipeline.vhd`).
- The vector of the bench must be `VIDEO_MODE_VECTOR` of `framework.vhd`, and every scenario must contain exactly its expected segments.

## Mutants (`run.sh mutants`)

Each mutant is applied to a copy of `digital_pipeline.vhd`; it is killed when at least one of the scenarios listed for it fails.

| Mutant | Scenarios | Result |
|---|---|---|
| M01 the scaler always gets the genlock's `htotal` | H | killed |
| M02 `enable_i` of the genlock always `'1'` | G H | survives (see below) |
| M03 the reference ignores `video_hblank_i` | C | killed |
| M04 `hdmi_ref` is the level, not a one-cycle pulse | C | killed |
| M05 target 1.0 ms instead of 2.0 ms | C | killed |
| M06 genlock `de_i` connected to the hsync | C | killed |
| M07 the reference register is cleared by vblank instead of the vsync edge | B | killed |
| M08 `hdmi_raw` inverted | C H | killed |
| M10 genlock `vs_i` connected to the hsync | C | killed |
| M14 genlock `hs_i` connected to the vsync | D | killed |
| M15 genlock `rst_i` tied to `'0'` | A | killed |
| M18 the reference register is cleared by the falling edge of `video_vs_i` | C | killed |
| M19 the scaler never gets the genlock's `htotal` | H | killed |

**M02** is harmless by design: with `enable_i` always `'1'` the genlock also measures and stretches in the standard modes, but the multiplexer gives the scaler `hdmi_htotal` in every mode that is not a raw mode, so nothing reaches the picture. The bench does not force a check for it.

**M18** clears the reference register at the end instead of the start of the core's vsync. For the C64's rasters this gives the same reference pulses (the vsync ends long before the first visible line), so the pulses alone cannot tell it; the bench kills it because it checks the moment at which the register is cleared, which `SPEC.md` 5.1 specifies.

## Files

| File | Purpose |
|---|---|
| `tb_hdmi_raw_wiring.vhd` | bench: clocks, core model, crop, `digital_pipeline`, scenarios, VCD markers |
| `tb_hdmi_raw_wiring_pkg.vhd` | two signals through which the scaler stand-in shows its syncs to the bench |
| `ascal_timing.vhd` | architecture of the scaler: its output timing generator |
| `genlock_hostile.vhd` | architecture of a genlock whose line length is always wrong |
| `check_wiring.py` | the checks, from the VCD |
| `run.sh` | builds, runs the scenarios in parallel, the mutants |
