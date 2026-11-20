# HDMI output at the C64's native frame rate (issues #184 and #148): status record

This file is the running memory of the work: the order, the decisions, the numbers, the verification and the open points. A session that takes over reads this file first.

## 0. State

**Implemented, reviewed and verified in simulation; not yet built with Vivado, not yet on hardware.** Branch `mh_implement_184` (from `develop` = `669e75d`), pushed. Version `WIP-V6-A27`.

| Item | State |
|---|---|
| Research R1 to R5, design, specification `SPEC.md` | done |
| HDMI hardware: mode package, three new clock tables, pipeline wiring, CTS, constraint, project files | done, reviewed, follow-ups closed |
| Genlock `M2M/vhdl/av_pipeline/hdmi_genlock.vhd` | done, reviewed twice, follow-ups closed |
| Menu, `mega65.vhd`, golden model, version | done, reviewed, follow-ups closed |
| Benches `tb_hdmi_genlock`, `tb_hdmi_raw`, `tb_hdmi_raw_wiring`, `tb_hdmi_raw_clock`, `tb_hdmi_raw_menu` | done (section 6) |
| Stack depth of the firmware with 333 menu lines | measured: 717 of 768 words, as computed |
| Documents (`VERSIONS.md`, `doc/inofficial.md`, `tests/README.md`, `FAQ.md`, `README.md`, `doc/hdmi.md`, `doc/speed.md`, `doc/ntsc.md`, `doc/developer.md`, `AGENTS.md`) | done |
| Vivado build of R3 and R6, hardware test on displays | the user (section 8) |

## 1. The order (the user, 2026-11-19, 23:15)

- Implement a mode that passes the C64's own frame rate through to HDMI (PAL about 50.12 Hz, NTSC about 59.83 Hz), for displays that accept it, so that no flicker-free is needed there.
- Research first: issue #148 with its links, issue #184, MiSTer (which offers this), own research. If the research succeeds and there is a plan: implement. If things are unclear: stop and ask.
- Menu (submenu `HDMI: %s`): below the display modes a yellow headline with a radio group of three: off (name to be found), `Flicker-free`, the raw mode (today the unwired single-select `HDMI: Raw 50.1 Hz`). Then a line, a second yellow headline (name to be found) with the remaining items (the filter submenu, DVI, zoom-in), a line, `Back`.
- No regression: whoever selects flicker-free or "off" gets exactly what he has today.
- Branch `mh_implement_184`, commit and push at will, GitHub account `sy2002`.
- Bump the version to `WIP-V6-A27`.
- Records go into this folder. Up to 8 CPU cores until 10:00 on 2026-11-20; a short, easy summary at the end or at 10:00.

## 2. What the issues say

- #148 (Kugelblitz360, 2024): wish for a mode like BMC64's 50.125 Hz HDMI modes; "not compatible with all monitors but with some". WebbedQuasar (2026): with flicker-free off the HDMI signal stays at 50 Hz (only VGA carries 50.125 Hz), which makes the picture jump; his older LCD TV shows the MiSTer's 50.125 Hz signal without problems.
- #184 (MJoergen, 2026, labels research, V6, decision needed): the question whether such a mode costs us the scaler (it does not: MiSTer uses the same scaler for it). MJoergen's idea: "invent" a new resolution mode in `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`.

## 3. Numbers (scripts in `tools/`)

Core clocks (`CORE/vhdl/clk.vhd`): PAL 100 MHz x 56.75 / (6 x 30) = 31.527778 MHz, NTSC 100 MHz x 36 / (5 x 22) = 32.727273 MHz. A frame has 312 x 63 x 32 = 628992 (PAL) or 263 x 65 x 32 = 547040 (NTSC) core clock cycles: 50.124291 Hz and 59.826105 Hz.

Pixel clock that would give the core's frame rate with the standard totals:

| Mode | Standard totals | Standard clock | Needed clock | Deviation |
|---|---|---|---|---|
| PAL 720p | 1980 x 750 | 74.25 MHz | 74.434572 MHz | +0.2486 % |
| PAL 576p | 864 x 625 | 27.0 MHz | 27.067117 MHz | +0.2486 % |
| NTSC 720p | 1650 x 750 | 74.1758 MHz | 74.034805 MHz | -0.1901 % |
| NTSC 480p | 858 x 525 | 27.0 MHz | 26.948669 MHz | -0.1901 % |

What the HDMI MMCM can do (multiplier in steps of 1/8, the 5x clock needs an integer divider):

- Nearest clocks with standard totals: PAL 720p 74.444444 MHz (+133 ppm, a frame slip every 150 s), PAL 576p 27.071429 MHz (+159 ppm), NTSC 720p 74.0625 MHz (+374 ppm), NTSC 480p 26.944444 MHz (-157 ppm). None is exact.
- Exactly equal frame rates exist only with changed totals: PAL 576p 864 x 624 at 27.023810 MHz, NTSC 480p 858 x 526 at the standard 27.0 MHz, PAL 720p 1872 x 756 at 70.9375 MHz, NTSC 720p 1573 x 789 at 74.25 MHz. The two 720p solutions are far from the standard.
- A new core clock within 150 ppm of a real C64 together with an HDMI clock that gives exactly equal rates at standard totals does not exist.

Consequence: standard totals and an exact match need a mechanism that absorbs the rest: the HDMI timing has to follow the core's frame (a genlock that makes some lines one pixel longer or shorter).

## 4. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | The core side of "Raw" is flicker-free off: the original clock, nothing new in `clk.vhd` or `hr_core_speed`. | A new core clock that would give exact rates with standard totals does not exist (section 3), and the existing clock tree stays untouched. |
| D2 | 720p raw modes keep the standard totals; only the pixel clock moves (74.444444 MHz PAL, 74.0625 MHz NTSC). | This is the signal of MiSTer and of the Ultimate 64 Elite II; within the 0.5 % clock tolerance of CTA-861; the VIC stays valid (`research/R4`). |
| D3 | 576p and 480p raw modes use 624 and 526 lines (two HDMI lines per C64 raster line) with 27.023810 MHz (PAL, new table) and 27.000 MHz (NTSC, existing table). | Exactly the core's frame rate with a static signal; the MEGA65's own core and the Ultimate 64 output these line counts, so the displays of MEGA65 owners know them. |
| D4 | A genlock in the HDMI clock domain stretches 16 lines of the vertical back porch through the scaler's `htotal` input. | The scaler runs with one frame buffer (`research/R3`): equal rates are not enough, the reader has to stay behind the writer. The same mechanism supplies the pixel clocks that the 720p frames are too short. Lines with picture keep the standard length. |
| D5 | Target: the HDMI picture starts 2.0 ms after the core's picture. | At least 11 core lines between writer and reader in every mode (`SPEC.md` 5.4); flicker-free works with 7 to 14. |
| D6 | The raw modes are six new members of `video_mode_type`; no new port of `MEGA65_Core`. | Least wiring; the mode already crosses into the HDMI domain. All 16 codes are used afterwards. |
| D7 | CTS of the audio clock regeneration alternates between two integers so that its average is exact. | A constant CTS would be up to 16 ppm off for the new clocks. Existing modes keep their constant value. |
| D8 | The static attributes of the HDMI MMCM stay; `set_clock_uncertainty -setup 0.100` on `hdmi_clk` covers the 0.26 % faster clock in the timing analysis (35 ps for the shorter period, the rest for the jitter of the other MMCM settings). | The clock tables are written read-modify-write, so changed static attributes could change bits of the existing modes. |
| D9 | Menu: headline `HDMI Frame Sync` with `Off`, `Flicker-free` (default), `Raw 50.1 Hz` / `Raw 59.8 Hz`; second headline `HDMI Options`; a line below each headline as below `HDMI Display Mode`; the order of the remaining items as before (DVI, filter, zoom-in). PAL and NTSC keep separate groups. | The user's layout; the names are a proposal and easy to change. |
| D10 | No triple buffering. | It does not fit into the HyperRAM region of R3, and direct mode has the lower latency. |
| D11 | No stretch while the HDMI picture start is up to 2.5 ms later than the target (`band = target + target / 4`). | The range without a tear is much wider than the target (about 1.2 ms below to 12 ms above it). With a narrow band every jump of the core's phase above it costs a roll through the whole frame; switching zoom-in off is such a jump (2.0 ms PAL, 1.4 ms NTSC). |
| D12 | While locked, a measurement without a new reference keeps the stretch of the previous frame. | In 720p a frame without stretch is shorter than the core's frame, so a missing reference would move a locked picture. |
| D13 | The largest stretch stays 255 pixel clocks per line in every mode (not scaled with the line length). | A faster pull-in is worth more than a gentler one: a display that minds the longer lines minds them at 13 % as well as at 30 %. |

Rejected: totals far from the standard for 720p (1872 x 756 at 70.94 MHz would be exact); an H total that alternates on lines with picture; a new core clock; continuous phase shifting of the MMCM (not possible with a fractional multiplier); slips every few minutes without a genlock.

Found on the way (not part of this work, to be told to the user): in the standard NTSC 480p modes the HDMI side sweeps the picture faster than the core writes it, so flicker-free's distance of 7 to 14 lines at the top may not be enough at the bottom (`research/R3`, last section): a tear in the lower part of the picture is possible there, worst in 5:4. Not verified on hardware.

## 5. How the work was organized, how to resume

A controller session wrote the specification and integrated; work packages ran in private clones of this repository (menu, genlock, HDMI hardware, bench with the real scaler, documents), each followed by an independent review on a fresh clone. To continue: read section 0 and section 8, then `SPEC.md`. To re-run the verification: the commands of section 6 (the READMEs of the benches give the runtimes; `tb_hdmi_raw` uses the simulator nvc if it is installed and GHDL otherwise; `tb_hdmi_genlock/run.sh all` takes about 40 minutes, `quick` about 6).

## 6. Verification record

All on the integrated tree of the branch. Nothing here replaces the Vivado build and the test on real displays.

**The existing modes are unchanged**

| What | Result |
|---|---|
| `CORE/vhdl/test/tb_hdmi_raw_clock/run.sh all` | PASS: the eight old clock codes write the DRP sequences of the unchanged file (448 events identical); the three new codes decode to the settings of `SPEC.md` 4.2; the unused codes load the table of "0010"; a selector change during a load ends with the complete table of the final code; the CTS in the packets is exact on average for the three new clocks and constant for every other record |
| `doc/dev-hdmi-raw/tools/old_modes_diff.sh` | PASS: the ten existing modes give the same 23 derived signals as before (totals, sync positions, window, OSM shift, CTS, VIC, aspect, polarities, clock code) |
| `doc/dev-hdmi-raw/tools/mmcm_tables.py check` | PASS: the generator reproduces the eight existing tables bit by bit; 11 tables checked |
| `CORE/vhdl/test/tb_hdmi_raw/` (real scaler), standard mode with and without genlock and multiplexer | identical output in every clock cycle |
| `CORE/vhdl/test/tb_hdmi_raw_wiring/run.sh all` | PASS: in the ten standard modes the scaler's `htotal` is the record's value in every clock cycle, also with a hostile stand-in for the genlock; 12 of 13 wiring mutants rejected (the 13th is harmless by design: the multiplexer protects the scaler) |
| `CORE/vhdl/test/tb_hdmi_raw_menu/run.sh all` | PASS: 16384 menu states; without a Raw bit both decoders equal the previous version; 11 mutants rejected |
| `M2M/rom/tests/menu_test.py verify`, `run`, `mutate` | VERIFY OK, ALL TESTS PASSED, all mutants killed |
| Firmware suites (`doc/dev-a22x3/tools/suites.py`) | all green |
| `CORE/vhdl/test/tb_ntsc`: `run.sh all`, `run_w1.sh`, `run_w2.sh all`, `run_w3.sh` | PASS (`hr_core_speed` identical to its copy) |
| Differential GHDL analysis of the seven changed design files against `669e75d` | PASS, no new diagnostics |
| Firmware ROM | 20284 words; 47 words differ from before (17 heap sizes, 30 menu indices); string ROM identical |

**The raw modes work**

| What | Result |
|---|---|
| `CORE/vhdl/test/tb_hdmi_genlock/run.sh all` (the entity against a cycle-exact model of the scaler's timing, 35 instances per mode) | PASS. Lock from every start phase; worst case 343 frames = 6.84 s (PAL 720p), 299 = 5.00 s (NTSC 720p), 124 = 2.47 s (576p), 102 = 1.70 s (480p). Steady state in 720p: stretch 196/197 (PAL) and 462/463 (NTSC) pixel clocks per frame, 300 frames within one pixel clock of 300 core frames. 576p and 480p: no stretch at all after lock, static timing. No line shorter than nominal, none more than 255 longer, only the 16 stretch lines. 24 mutants and the latch mutant rejected. 57 flip-flops |
| The reviewer's independent cycle model (C, compared with the entity in GHDL) | the same numbers; zoom-in off while locked: no roll, no stretch; 10 s without a reference: the picture moves by 15 (PAL) or 42 (NTSC) pixel clocks in 720p, not at all in 576p and 480p |
| `CORE/vhdl/test/tb_hdmi_raw/run.sh full` (the real `ascal.vhd`, `crop.vhd`, the genlock; every pixel of every frame checked) | PASS in all six raw modes: every HDMI frame shows exactly one core frame, in order, no tear. Zoom-in on and off, toggled while locked: the genlock stays locked. Three bench mutants fail as they must |
| Reader behind writer at the top / bottom of the picture, measured with the real scaler | PAL 720p 1.890 / 3.706 ms, NTSC 720p 1.894 / 1.998, 576p 4:3 1.881 / 3.000, 576p 5:4 2.457 / 2.457, 480p 4:3 1.881 / 1.214, 480p 5:4 2.357 / 0.768 (`SPEC.md` 5.4 within 0.05 ms). No tear from 0.77 ms below the target to at least 12.8 ms above it |

Numbers of the menu change: `OPTM_SIZE` 325 to 333; the six Frame Sync items are the menu lines 66 to 71; every constant behind them moved by 8 (DVI and the filters by 9). Menu heap 4851 + 702 = 5553 words of `MENU_HEAP_SIZE` 5760 (was 5696); the heap of the file browser is 64 words smaller (24448 words in the release build). Stack, measured in the full-system simulation: 717 of 768 words on the deepest chain (a CRT load in the visible menu; 49 words free), 673 on the shortcut chain; register banks 23 and 34, unchanged.

## 7. Reviews

Three independent reviewers, each on a fresh clone with the specification and the commits only, with mutants of their own.

**HDMI hardware** (modes, clock, pipeline, CTS, constraint, project files): no defect; no path that changes an existing mode. 11 of 18 reviewer mutants were caught at first; the 7 survivors were all in the wiring of the genlock, which no bench exercised with the real entity. Closed with the bench `tb_hdmi_raw_wiring`, the real entity in all benches, a selector change during a table load in the DRP bench, the CTS observed in the packet, the clock uncertainty raised to 0.100 ns, an assertion on the vertical back porch of the raw records and corrected comments. A raw code that is visible for one clock cycle during a change between two standard modes is harmless (`SPEC.md` 5.1) and tested in the genlock bench.

**Menu** (menu, decoders, golden model, heap, version): no defect; all 90 constants and subtypes confirmed with an independent parser; the firmware differs in exactly the explained words. 19 of 22 reviewer mutants were caught at first; the 3 survivors were clock-domain mix-ups in the decoders. Closed with separate vectors per clock domain in `tb_hdmi_raw_menu`, its base commit moved to `669e75d`, mutants for the new groups in `menu_test.py`, the NTSC view in the firmware fixture, and better wording of the help text and of a comment.

**Genlock entity**, two rounds: no defect. The reviewer's own cycle model (compared with the entity in GHDL: identical in every measurement, stretch and line length) confirmed lock from every start phase, the exact average frame length in 720p, the static timing in 576p and 480p and the line length bounds under 1000 random enable and reset toggles. Two improvements of the control law came from the first round (D11, D12) and were verified in the second. Three reviewer mutants that the entity's bench did not catch (all in the rule for a measurement without a new reference) led to more bench cases. One accepted limit: if the reference stops in the very frame after a small backward jump of the core's phase, the catch-up stretch of that frame is held, and the return costs a pull-in; no trigger for this is known.

The reviews name two risks that are properties of the design, not of the code, and that only displays can answer: in 720p the 16 back porch lines are 12 (PAL) or 29 (NTSC) pixel clocks longer than standard in every frame, and during a pull-in the stretch lines are 255 pixel clocks longer for up to 7 seconds. The 576p and 480p raw modes have neither in the steady state.

## 8. What is open

**For the user**

1. Vivado build of R3 and R6 (`CORE/build_all.sh`). New in the timing analysis: `set_clock_uncertainty -setup 0.100` on `hdmi_clk` in `M2M/common.xdc`; a new source file `M2M/vhdl/av_pipeline/hdmi_genlock.vhd` in the four project files. The new CDC of the reference in `digital_pipeline.vhd` is an `xpm_cdc_single` (constrained by the macro).
2. Hardware test as in `tests/README.md`, section `Version WIP-V6-A27`. The first things to look at: does the display show `Raw` at all in 720p (the modified blanking lines) and in 4:3 576p (the timing of the MEGA65 core and the Ultimate 64 with a pixel clock 0.09 % higher); is the scroller smooth for minutes; is the sound free of dropouts; does the picture come back after Cursor Up and Return if the display stays black.
3. The names in the menu are a proposal: `HDMI Frame Sync` with `Off`, `Flicker-free`, `Raw 50.1 Hz` / `Raw 59.8 Hz`, and `HDMI Options`. A line follows each headline, as below `HDMI Display Mode`.
4. Date and commit in the `WIP-V6-A27` row of `doc/inofficial.md` after the build.

**Found on the way, not part of this work**

- **Standard NTSC 480p with flicker-free tears in the lower part of the picture, in simulation.** In these modes the HDMI side sweeps the picture faster than the core writes it, and flicker-free holds the writer only 7 to 14 lines ahead at the top. The bench with the real scaler shows: `5:4 480p 59.94 Hz` tears in every frame (from line 256 or 377 of 480, depending on the phase), `4:3 480p 59.94 Hz` tears when the phase sits in the lower part of the window (from line 303) and not in the upper part. Existing behavior since NTSC was added; not verified on hardware; `tests/README.md` has a step for it. A fix would be thresholds of `hdmi_flicker_free` that depend on the mode. `Raw` in the same display modes does not have the problem.
- The scaler shows two or three wrong frames after a change of the picture size (zoom-in on or off), and in 576p and 480p its first frame after its own reset is wrong when the core's lines have 9 memory bursts (PAL, zoom-in). Both are properties of `ascal.vhd` in every mode.
- The old comment of the 27 MHz clock table in `video_out_clock.vhd` says "74.250 MHz"; the table is right.
- The Discord link of issue #148 needs a login and could not be read.

**Ideas for later**

- A pixel clock that needs no stretch in 720p: the HDMI MMCM would have to produce the pixel clock from its fractional output and a second MMCM the 5x clock (`research/R1-mister.md`): within a few ppm of the ideal clock.
- Triple buffering on the boards with SDRAM (R4 to R6) would make the phase irrelevant, at the price of one to two frames of delay.

