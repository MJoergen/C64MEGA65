# HDMI at the C64's frame rate: bench with the real scaler (issue #184)

Simulation bench for the "Raw" HDMI modes of `doc/dev-hdmi-raw/SPEC.md`: the scaler `M2M/vhdl/av_pipeline/ascal.vhd` in direct mode (one frame buffer, as in the core), the zoom-in `M2M/vhdl/av_pipeline/crop.vhd`, the genlock `M2M/vhdl/av_pipeline/hdmi_genlock.vhd` with the wiring of SPEC section 5.1, a memory model on the scaler's Avalon port and a model of the core's picture. It checks that every HDMI frame shows exactly one core frame, in order and without a tear, measures the distance between the core writing a line into the frame buffer and the scaler fetching it, and proves that a standard mode is not affected.

## How to run

```
CORE/vhdl/test/tb_hdmi_raw/run.sh [quick|full|extra] [--keep]
```

The runner builds in a temporary directory, prints one result line per simulation, the measured distances and the cross-checks between simulations, and ends with `RESULT: PASS` or `RESULT: FAIL ...`; the exit status is 0 only on PASS. `--keep` keeps the build directory (logs) and prints its path. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl` or `GHDL`), python3. `JOBS` (default 3) sets the number of parallel simulations, `GENLOCK` another file for the genlock entity.

Runtimes on this machine (one simulation per core): `quick` 2 simulations, about 14 minutes with `JOBS=2`; `full` and `extra`: see the results below. A 480p or 576p frame costs 9 to 12 minutes of simulation, a 720p frame about 25 (the scaler's HDMI clock domain dominates).

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: makes the GHDL copy of `ascal.vhd`, builds, generates the list of simulations with all mode and clock parameters, runs them, evaluates |
| `tb_hdmi_raw.vhd` | The bench: clocks, core picture, `crop`, reference of the genlock, `hdmi_genlock`, multiplexer, `ascal`, memory model and Avalon monitor, checker |

## What is simulated

### Clocks

Every clock is derived from the 100 MHz oscillator in the design, so its period is a fraction of 10 ns. The bench places edge `n` of a clock at `floor(n * P / 2)` after its start, where `P` is the exact fractional period: the edges have less than 1 fs of rounding, and the long-term frequency is exact, without drift. Core clock 31.527778 MHz (PAL, 100 MHz x 56.75 / 180) or 32.727273 MHz (NTSC, 100 MHz x 36 / 110); HDMI pixel clocks of SPEC section 4: 74.444444 MHz (100 MHz x 67 / 90), 27.023810 MHz (x 227 / 840), 74.0625 MHz (x 237 / 320), 27.000 MHz; the Avalon clock 100 MHz. In the raw modes with 576p and 480p the core frame and the HDMI frame are therefore exactly equally long, in 720p the HDMI frame is 196.97 (PAL) or 462.92 (NTSC) pixel clocks shorter.

### Core picture

The picture as `CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd` delivers it to the scaler: pixel enable = core clock / 4, PAL 504 dots x 312 lines with the visible area dots 107 to 488 and lines 28 to 297 (382 x 270), vsync from dot 10 of line 307 to dot 10 of line 311; NTSC 520 x 263 with dots 112 to 515 and lines 13 to 262 (404 x 250), vsync from dot 16 of line 0 to dot 16 of line 4; hsync and blanking as in `video_sync.vhd`. Every pixel carries its frame number (red), its visible line (green) and its visible column (blue), each modulo 256; the code is present in the blanking too. The picture passes the real `crop.vhd` (zoom-in off or on) and then goes to the scaler exactly as in `digital_pipeline.vhd` (`i_de = not (hblank or vblank)`, `i_ce` = pixel enable).

### Scaler

The real `M2M/vhdl/av_pipeline/ascal.vhd`, configured as in `digital_pipeline.vhd`: `MASK x"ff"`, `RAMBASE 0`, `RAMSIZE` 2 MB, `INTER`, `HEADER`, `DOWNSCALE` false, `DOWNSCALE_NN` true, `BYTESWAP`, `ADAPTIVE` true, no palettes, `FRAC 6`, `OHRES 2048`, `IHRES 1024`, 128-bit Avalon with 19 address bits, 128-byte bursts, `iauto '1'`, `run '1'`, `freeze '0'`, 24 bpp, `mode "00000"` (nearest neighbor, no triple buffering), the output timing and window (`hmin` to `vmax`) of the mode as `digital_pipeline.vhd` computes them. Nearest neighbor passes the input pixels unchanged, so every output pixel tells which core frame, line and column it comes from. The other interpolators read the frame buffer at the same moments (the fetch of a line depends only on the vertical position).

GHDL needs one change of the scaler: two expressions are negative for a short time after the start, because they are computed from values that are still 0 before the scaler has seen its first input picture (`o_pshift <= o_off(0) - 1` with `o_pshift` of range 0 to 15, `o_ihsizem <= o_ihsize + o_off(0) - 2` with range 0 to 4095). GHDL stops there with a bound check failure; the hardware simply wraps (4 and 12 bits). `run.sh` writes a copy of `ascal.vhd` into the build directory in which exactly these two expressions are written with that wrap (`(o_off(0) + 15) MOD 16`, `(o_ihsize + o_off(0) + 4094) MOD 4096`), and stops if the original text is not found exactly once. The results are identical whenever the original expressions are in range; nothing else of the file changes, and the bench adds no ports.

### Startup

A real system runs long before anything is looked at; a simulation starts from nothing, and the scaler needs some conditions to show a correct first picture. The bench establishes them, so that the very first HDMI picture can be checked (a full frame costs about 7 minutes of simulation in 576p and 17 in 720p):

* The core picture starts a few lines before its vsync (PAL in raster line 300, NTSC in line 0 with the vsync at its beginning): the scaler counts its input lines from the first visible line after a vsync. Without a vsync in front of the first picture it counts one line too many in that picture, takes 271 lines as the input height and, because its horizontal pixel counter wraps at 4096 (`MOD 4096`), writes a 271st line of blanking 8 lines after the picture; the last two output lines would show it.
* The HDMI clock runs for 16 periods from the start, through the reset of the scaler (its output side takes the reset with this clock), pauses, and resumes 50 µs before the vsync that ends the core's first complete picture: the scaler notices the end of an input picture only with a running output clock, and only then takes over the size of the input picture, at the next falling edge of its output vsync.
* The first pass of the HDMI timing is short (40 to 190 lines, computed by `run.sh`), without data enable, with a vsync that ends three lines before the first picture's preload, and with the vertical window out of reach (`vmin` 4000): the scaler fetches nothing before it knows the size of its input picture. The bench applies the real window in the horizontal blanking one line before the scaler's lead counter wraps, and the real `vtotal`, `vsstart`, `vsend`, `vdisp` in the horizontal blanking of the last line before the first picture (the scaler takes these inputs over in every clock).
* The resume time is chosen so that the first HDMI picture begins the wanted distance after a core picture (2.0 ms unless stated otherwise), so the genlock starts in its steady state.

From the first picture on, all inputs of the scaler are constant except `htotal` from the genlock.

### Genlock and its wiring

The real `M2M/vhdl/av_pipeline/hdmi_genlock.vhd` of the repository, wired as in `M2M/vhdl/av_pipeline/digital_pipeline.vhd` (SPEC section 5.1): a register in the core clock domain is cleared by the rising edge of `video_vs_i` and set by the first visible pixel after it (the first rising edge of the scaler's input data enable); two flip-flops in the HDMI clock domain (in place of `xpm_cdc_single` with `DEST_SYNC_FF = 2`) bring the level over, and the pulse `ref_i` is the synchronized level and not its value one clock earlier. `hdmi_genlock` gets the scaler's `o_hs`, `o_vs`, `o_de`, `htotal_i` and `target_i` = 2 x `CLK_KHZ` of the mode, `enable_i = '1'` in the raw modes and `rst_i` for the first 16 HDMI clocks; a multiplexer gives the scaler `htotal_o` in the raw modes and the mode's `htotal` otherwise. For the comparison of check 5 the bench can also be built without genlock and multiplexer (`G_NO_GENLOCK`). The mutant `G_REF_OLD` takes the reference from the falling edge of the cropped vblank instead, the first wiring of SPEC 5.1.

### Memory model

On the scaler's 128-bit Avalon port, in order (a read sees every write accepted before it), with the latencies of the R3 path (HyperRAM behind `avm_decrease` and the arbiter, 100 MHz, 16 bits per clock): a burst is accepted 12 clocks after it is requested and after the previous burst has left the memory; a write burst takes one 128-bit beat every 8 clocks (eight 16-bit words); a read delivers its first beat 28 clocks after acceptance and then one every 8 clocks. A 128-byte burst therefore takes about 0.8 µs (write) or 1.0 µs (read). On R4 to R6 the scaler has an SDRAM of its own, which is faster.

* "Pessimistic" (`slowmem`, other users of the R3 HyperRAM: REU, cartridge, drives, QNICE): in addition every burst waits a random 0 to 0.5 µs, and one burst in 20 another 2 µs.
* "Heavy" (`heavymem`, information only): 0 to 1.4 µs before every burst (one burst of another master) and 4.2 µs before one in 20 (one burst of each of the three others).

The scaler fetches an input line (9 or 10 bursts) between the start of the hsync of an output line and the display of the output line two lines later: about 36 µs in 480p and 576p, about 26 µs in 720p. With the heavy model a fetch takes up to 50 µs, and the scaler shows stale data in some lines, in every mode with or without genlock (`heavymem_std_ntsc480_54` shows it in the standard mode); this is a limit of the scaler and the memory, not of the raw modes. The Avalon monitor reports the longest fetch of a line per frame (`fetch_max`).

### Measurements

* **Avalon monitor** (100 MHz domain): for every line of the frame buffer the time its last write burst is accepted (the line is in memory) and the time its first read burst of the current HDMI frame is accepted (the scaler fetches it). Per HDMI frame: the distance fetch minus written at the top line, at the bottom line, the smallest and the largest distance over all lines, and the margin from the last fetch of a line to the first write burst of the next core frame into it. Also the core's last write address (16-bit words) at the scaler's read of address 0, which is what `hdmi_flicker_free.vhd` latches.
* **Checker** (HDMI domain), every pixel of every HDMI frame (a frame begins at the rising edge of `o_vs`): the picture pixels (`o_de = '1'` and `o_brd = '0'`) of a frame all come from the same core frame (otherwise: tear, with the first picture line that differs); the core frame number grows by exactly 1 per HDMI frame (otherwise: repeated or skipped frame); geometry: `vmax - vmin + 1` picture lines of `hmax - hmin + 1` pixels, the first line shows the first input line, the last line the last, every line shows one input line and the input line grows by 0 or 1 from line to line, the first and the last pixel of a line show the first and the last input column, the column grows by 0 or 1 from pixel to pixel; a signature over all picture pixels (line and column codes), which must be the same in every frame and equal to the one of the standard mode; every line is at least `htotal` and at most `htotal + 256` clocks long; `d` = HDMI clocks from the reference pulse to the first data enable of the HDMI picture (the genlock's measurement, here independent of it) within the genlock's lock window `target - 1024` to `target + band` (`band = target + target / 4`, SPEC 5.3); once settled, `d` changes by at most 600 clocks from frame to frame (the 720p surplus plus margin; not in the three frames after a toggle of zoom-in); a hash over `o_hs`, `o_vs`, `o_de`, `o_r`, `o_g`, `o_b` in every clock.
* **Tear-free range of `d`**: a change of `d` moves every fetch by the same time, so from one run at the target the runner computes the range of `d` without a tear: down to `d` minus the smallest distance (a line is fetched before the core has written it) and up to `d` plus the smallest margin (the next core frame overwrites a line before it is fetched). The margin of a fetch is computed from the core's strictly periodic timing: the start of the current write of the line plus one core frame, minus the time of the fetch.

## Simulations

All simulations run at full size: the real totals of the modes and the real clock ratios. A scaled-down picture is not an option: an HDMI window narrower than the 382 or 404 input columns makes the scaler downscale horizontally, which is a different data path. The cost is dominated by the scaler's HDMI clock domain (all its interpolators compute in every clock), see the runtimes below.

Every run starts the HDMI picture 2.0 ms after a core picture (the target of SPEC section 5.4) unless stated otherwise, so that the genlock starts in its steady state; "frames" counts the HDMI frames that are checked. In PAL and with zoom-in one more frame runs before them, unchecked: there a line of the input picture takes 9 bursts of 128 bytes (382 or 348 columns of 3 bytes), and the scaler shows a wrong first picture after its start (pixels from the wrong place of its read buffer); the second and every later picture are right. NTSC without zoom-in (404 columns, 10 bursts) is right from the first picture on. This is a property of the scaler's start, independent of the genlock (it shows with the stand-in, before any stretch, and with `d` at the target).

| Simulation | Set | Mode, checked frames | Purpose | Expected |
|---|---|---|---|---|
| `raw_pal720` | full | PAL 720p raw, 1 (after a first, unchecked one) | check 1 and 2; the genlock adds the surplus in every frame | pass |
| `raw_ntsc720` | full | NTSC 720p raw, 2 | check 1 and 2; the genlock adds the surplus in every frame | pass |
| `raw_pal576`, `raw_pal576_54` | full | PAL 576p raw 4:3 and 5:4, 1 | check 1 and 2 | pass |
| `raw_ntsc480` | quick (1), full (2) | NTSC 480p raw 4:3 | check 1 and 2; its geometry signature is compared with `std_ntsc480_genlock` | pass |
| `raw_ntsc480_54_slowmem` | full | NTSC 480p raw 5:4, 2, pessimistic memory | check 1 and 2 in the mode with the smallest distance at the bottom | pass |
| `zoom_pal576_slowmem`, `zoom_ntsc480_slowmem` | full | 576p and 480p raw with zoom-in, 1, pessimistic memory | check 3 | pass |
| `zoomtoggle_ntsc480` | full | NTSC 480p raw, zoom-in switched off after frame 1 and on again after frame 4, 6 | check 3: no tear and no repeated or skipped frame at any time; geometry with zoom-in in frame 1, without in frame 4, `d` inside the band (no stretch) while zoom-in is off, back at the target after it is on again | pass |
| `inband_ntsc480`, `inband_zoom_ntsc480` | full | NTSC 480p raw without and with zoom-in, 1, start 2.4 ms above the target (inside the band) | check 2: no stretch, the reader 2.4 ms further behind, no tear also at the bottom | pass |
| `pullin_ntsc480` | full | NTSC 480p raw, 3; start 1.5 x 4080 clocks below the target | check 4: frames 0 and 1 are stretched (4080, 2040), from frame 2 on `d` is at the target | pass |
| `pullin_from_tear_ntsc480` | full | NTSC 480p raw, 2; start 0.05 ms after the core's picture | check 4: tears are allowed, the geometry and the line lengths are checked in every frame; the evaluation requires a tear in frame 0 and none in the last frame | pass |
| `std_ntsc480_genlock`, `std_ntsc480_nogenlock` | full | standard NTSC 480p (525 lines, 27.000 MHz), 1; genlock disabled by the multiplexer, and a build without genlock and multiplexer | check 5: the hash over all outputs of the scaler in every clock must be equal | pass, equal hash |
| `heavymem_std_ntsc480_54` | full | standard NTSC 480p 5:4, 1, heavy memory, no genlock | the memory latency the scaler tolerates (information) | information |
| `mutant_target_0.1ms_ntsc480` | quick, full | NTSC 480p raw, 1; target 0.1 ms | check 6: the reader overtakes the writer at the top | fail (tear) |
| `mutant_clock_10pct_fast_ntsc480` | full | NTSC 480p raw, 1; pixel clock 10 % above the one of the totals | check 6: more surplus than the genlock can add, the reader catches up within the frame | fail (tear) |
| `mutant_old_reference_zoom_ntsc480` | full | NTSC 480p raw with zoom-in, 1, start 1000 clocks above the target; reference from the falling edge of the cropped vblank (the first wiring of SPEC 5.1) | check 6: with zoom-in that edge comes in every line, the genlock measures a tiny `d` and stretches by 4080 in every frame | fail (`d` changes by 4080 per frame) |
| `ff_ntsc480std_low`, `ff_ntsc480std_high`, `ff_ntsc480std_54_low`, `ff_ntsc480std_54_high` | extra | standard NTSC 480p 4:3 and 5:4, 2; no genlock, the core clock at the HDMI frame rate, the phase at the lower and the upper threshold of `hdmi_flicker_free` | today's behavior with flicker-free (the runner reports tears) | information |

## Not covered

* `digital_pipeline.vhd` itself is not instantiated (it needs the Xilinx library and the HDMI encoder); the bench repeats its reference register, the synchronizer, the pulse and the multiplexer in front of `htotal` (compared with the file at 3f2e96a). The OSM overlay and the HDMI encoder behind the scaler are not part of the bench.
* The memory is a model of the R3 path, not the HyperRAM controller and the arbiter themselves.
* Only nearest neighbor is checked pixel by pixel; the other interpolators fetch the same lines at the same moments.
* Few frames per run: the long-term behavior of the control law, the pull-in from above the band (up to 8 seconds), a missing reference and a paused core are the subject of the genlock bench `CORE/vhdl/test/tb_hdmi_genlock/`, which uses a model of the scaler's output counters.

## Results

Quick set with `hdmi_genlock.vhd` at 3f2e96a: `raw_ntsc480` passes (core frame 1 in HDMI frame 0, no tear, geometry exact, `d` = 54008 clocks for a target of 54000; distance at the top 1.881 ms, at the bottom 1.214 ms; smallest margin to the next overwrite 14.77 ms, so the mode is tear-free for `d` from 0.79 ms up to one frame; longest line fetch 24.2 µs; 828 s); `mutant_target_0.1ms_ntsc480` fails as required (tear in picture line 2; 563 s).
