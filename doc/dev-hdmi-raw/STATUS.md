# HDMI output at the C64's native frame rate (issues #184 and #148): status record

This file is the running memory of the work: the order, the decisions, the numbers, the verification and the open points. A session that takes over reads this file first.

## 0. State

**Phase: IMPLEMENTATION (since 2026-11-20, 00:10).** Branch `mh_implement_184` (from `develop` = `669e75d`). Version to become `WIP-V6-A27`. The research is done (`research/R1` to `R4`), the design is decided (section 4) and specified (`SPEC.md`).

| Item | State |
|---|---|
| Issues #148 and #184 read, links followed | done (section 2; the Discord link of #148 needs a login and was not readable) |
| Research R1 to R4 | done, notes in `research/` |
| Number search: which pixel clocks and totals are possible | done (section 3, scripts in `tools/`) |
| Design decision, specification `SPEC.md` | done |
| R5: generator for the tables of the HDMI clock (`tools/mmcm_tables.py`, `research/R5-mmcm-tables.md`) | running |
| Work package "menu": menu, `mega65.vhd`, golden model, firmware tests, version | running |
| Work package "genlock": `hdmi_genlock.vhd` and its unit bench | running |
| Work package "rtl": mode package, clock tables, pipeline wiring, CTS, constraints, project files | running |
| Work package "bench": bench with the real scaler | running |
| Integration of the four work packages on the branch | open |
| Independent reviews (one per work package), fixes | open |
| Documents (`VERSIONS.md`, `doc/inofficial.md`, `tests/README.md`, `AGENTS.md`, `FAQ.md`, `doc/hdmi.md`) | open |
| Vivado build, hardware test | the user |

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

Rejected: totals far from the standard for 720p (1872 x 756 at 70.94 MHz would be exact); an H total that alternates on lines with picture; a new core clock; continuous phase shifting of the MMCM (not possible with a fractional multiplier); slips every few minutes without a genlock.

Found on the way (not part of this work, to be told to the user): in the standard NTSC 480p modes the HDMI side sweeps the picture faster than the core writes it, so flicker-free's distance of 7 to 14 lines at the top may not be enough at the bottom (`research/R3`, last section): a tear in the lower part of the picture is possible there, worst in 5:4. Not verified on hardware.

## 5. How to resume

Read section 0, then `SPEC.md`. The controller session keeps its live checkpoint also in the memory file `project_active_task_state.md` (clone paths, agents). Work packages run in private clones under the scratchpad of the controller session (`.../scratchpad/w/menu`, `w/genlock`, `w/rtl`, `w/bench`, each on a local branch of the same name that starts at the branch tip); their commits are fetched into the main folder and integrated there. Helper scripts in the scratchpad: `mkclone.sh <name> [toolchain]`, `toolchain.sh`, the clipboard shim `shim/`.
