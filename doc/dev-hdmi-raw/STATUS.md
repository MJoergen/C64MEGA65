# HDMI output at the C64's native frame rate (issues #184 and #148): status record

This file is the running memory of the work: the order, the decisions, the numbers, the verification and the open points. A session that takes over reads this file first.

## 0. State

**Phase: REVIEW AND FOLLOW-UP (since 2026-11-20, 02:00).** Branch `mh_implement_184` (from `develop` = `669e75d`), pushed. Version `WIP-V6-A27`. The implementation of all parts is on the branch and passes its own tests; three independent reviews are done or running and their findings are being closed.

| Item | State |
|---|---|
| Research R1 to R5, design, specification `SPEC.md` | done |
| HDMI hardware: mode package, clock tables, pipeline wiring, CTS, constraint, project files, benches | on the branch; reviewed (no defect, section 7); follow-up running |
| Menu, `mega65.vhd`, golden model, version, bench `tb_hdmi_raw_menu` | on the branch; reviewed (no defect, section 7); follow-up running |
| Genlock entity `hdmi_genlock.vhd` | on the branch; its unit bench `tb_hdmi_genlock` is being finished; review running |
| Bench with the real scaler `tb_hdmi_raw` | running (full-size frames are slow) |
| Stack depth of the firmware with 333 menu lines | computed (717 of 768 words); the measurement in the full-system simulation is running |
| Documents (`VERSIONS.md`, `doc/inofficial.md`, `tests/README.md`, `FAQ.md`, `README.md`, `doc/hdmi.md`, `doc/speed.md`, `doc/ntsc.md`, `doc/developer.md`, `AGENTS.md`) | on the branch |
| Vivado build, hardware test | the user (`tests/README.md`, section `Version WIP-V6-A27`) |

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
| D8 | The static attributes of the HDMI MMCM stay; `set_clock_uncertainty -setup 0.050` on `hdmi_clk` covers the 0.26 % faster clock in the timing analysis. | The clock tables are written read-modify-write, so changed static attributes could change bits of the existing modes. |
| D9 | Menu: headline `HDMI Frame Sync` with `Off`, `Flicker-free` (default), `Raw 50.1 Hz` / `Raw 59.8 Hz`; second headline `HDMI Options`; a line below each headline as below `HDMI Display Mode`; the order of the remaining items as before (DVI, filter, zoom-in). PAL and NTSC keep separate groups. | The user's layout; the names are a proposal and easy to change. |
| D10 | No triple buffering. | It does not fit into the HyperRAM region of R3, and direct mode has the lower latency. |
| D11 | No stretch while the HDMI picture start is up to 2.5 ms later than the target (`band = target + target / 4`). | The range without a tear is much wider than the target (about 1.2 ms below to 12 ms above it). With a narrow band every jump of the core's phase above it costs a roll through the whole frame; switching zoom-in off is such a jump (2.0 ms PAL, 1.4 ms NTSC). |
| D12 | While locked, a measurement without a new reference keeps the stretch of the previous frame. | In 720p a frame without stretch is shorter than the core's frame, so a missing reference or a paused core would move a locked picture. |
| D13 | The largest stretch stays 255 pixel clocks per line in every mode (not scaled with the line length). | A faster pull-in is worth more than a gentler one: a display that minds the longer lines minds them at 13 % as well as at 30 %. |

Rejected: totals far from the standard for 720p (1872 x 756 at 70.94 MHz would be exact); an H total that alternates on lines with picture; a new core clock; continuous phase shifting of the MMCM (not possible with a fractional multiplier); slips every few minutes without a genlock.

Found on the way (not part of this work, to be told to the user): in the standard NTSC 480p modes the HDMI side sweeps the picture faster than the core writes it, so flicker-free's distance of 7 to 14 lines at the top may not be enough at the bottom (`research/R3`, last section): a tear in the lower part of the picture is possible there, worst in 5:4. Not verified on hardware.

## 6. Verification record

State of 2026-11-20, 02:00, on the integrated tree (commit `17d61be` plus documents):

| What | Result |
|---|---|
| `CORE/vhdl/test/tb_hdmi_raw_clock/run.sh all` | PASS: the eight old clock codes give the DRP sequences of the unchanged file (448 events identical), the three new codes decode to the settings of `SPEC.md` 4.2, the unused codes load the table of "0010"; CTS average exact for the three new clocks, constant for every other record |
| `doc/dev-hdmi-raw/tools/old_modes_diff.sh` | PASS: the ten existing modes give the same 23 derived signals as before |
| `doc/dev-hdmi-raw/tools/mmcm_tables.py check` | PASS: 11 tables |
| `CORE/vhdl/test/tb_ntsc`: `run.sh all`, `run_w1.sh`, `run_w2.sh all`, `run_w3.sh` | PASS |
| Differential GHDL analysis of the seven changed design files against `669e75d` | PASS, no new diagnostics |
| `CORE/vhdl/test/tb_hdmi_raw_menu/run.sh all` | PASS: 16384 menu states; without a Raw bit both decoders equal the previous version |
| `M2M/rom/tests/menu_test.py verify`, `run`, `mutate` | VERIFY OK, ALL TESTS PASSED, 122 mutants killed |
| Firmware suites (`doc/dev-a22x3/tools/suites.py`, 16 suites) | all green on the menu branch; `tb_capslock` reports a false alarm on the integrated tree (its pinned base of `framework.vhd`), being fixed |
| Firmware ROM | 20284 words, 47 words differ from before (17 heap sizes, 30 menu indices); string ROM identical |
| Genlock, frame-level model (`tools/loop_model.py`) and the reviewer's independent cycle model | lock from every phase: at most 389 frames (PAL 720p), 348 (NTSC 720p), 138 (576p), 117 (480p); static timing after lock in 576p and 480p |
| Real scaler, first full-size run (480p raw) | no tear; reader behind writer 1.883 ms at the top, 1.213 ms at the bottom (`SPEC.md` 5.4 estimated 1.84 and 1.20) |

Numbers of the menu change: `OPTM_SIZE` 325 to 333; the six Frame Sync items are the menu lines 66 to 71; every constant behind them moved by 8 (DVI and the filters by 9). Menu heap 4851 + 702 = 5553 words of `MENU_HEAP_SIZE` 5760 (was 5696); the heap of the file browser is 64 words smaller (24448 words in the release build). Stack: 717 of 768 words on the deepest chain (computed: 701 + 2 x 8).

## 7. Reviews

Three independent reviewers, each on a fresh clone with the specification and the commits only.

**HDMI hardware** (modes, clock, pipeline, CTS, constraint, project files): no defect; no path that changes an existing mode. 11 of 18 reviewer mutants caught; the 7 survivors are all in the wiring of the genlock, which no bench exercised with the real entity. Follow-up: a wiring bench with the real `digital_pipeline` and the real genlock, the benches switched to the real entity, a change of the clock selector during a table load in the DRP bench, the clock uncertainty raised to 0.100 ns, two comments. A raw code that is visible for one clock cycle during a change between two standard modes is harmless (`SPEC.md` 5.1) and gets a test in the genlock bench.

**Menu** (menu, decoders, golden model, heap, version): no defect; all 90 constants and subtypes confirmed with an independent parser; the firmware differs in exactly the explained words. 19 of 22 reviewer mutants caught; the 3 survivors are clock-domain mix-ups that the truth table bench could not see. Follow-up: a lint for the domains, the base commit of the bench moved to `669e75d`, mutants for the new groups in `menu_test.py`, the NTSC view in the firmware fixture, the wording of the help text and of a comment.

**Genlock entity**: no defect. The reviewer's own cycle model (compared with the entity in GHDL: identical in every measurement, stretch and line length) confirms: lock from every start phase (1500 to 3000 phases per mode; worst case 389 frames in PAL 720p, 348 in NTSC 720p, 138 in 576p, 117 in 480p), in 720p the sum of the frame lengths within 0.54 pixel clocks of the core's frames over 5400 frames, static timing in 576p and 480p, no line ever shorter than nominal or more than 255 longer under 1000 random enable and reset toggles, and the distances of `SPEC.md` 5.4 (0.77 ms at the bottom of NTSC 480p 5:4 is the smallest). Two improvements of the control law adopted (D11, D12). Its two risks are properties of the design, not of the code, and are the first things the hardware test has to show: the 16 back porch lines of 720p are 12 or 29 pixel clocks longer than standard in every frame, and during a pull-in the stretch lines are 255 pixel clocks longer for up to 8 seconds.

## 5. How to resume

Read section 0, then `SPEC.md`. The controller session keeps its live checkpoint also in the memory file `project_active_task_state.md` (clone paths, agents). Work packages run in private clones under the scratchpad of the controller session (`.../scratchpad/w/menu`, `w/genlock`, `w/rtl`, `w/bench`, each on a local branch of the same name that starts at the branch tip); their commits are fetched into the main folder and integrated there. Helper scripts in the scratchpad: `mkclone.sh <name> [toolchain]`, `toolchain.sh`, the clipboard shim `shim/`.
