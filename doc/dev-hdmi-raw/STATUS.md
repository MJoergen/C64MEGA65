# HDMI output at the C64's native frame rate (issues #184 and #148): status record

This file is the running memory of the work: the order, the decisions, the numbers, the verification and the open points. A session that takes over reads this file first.

## 0. State

**Phase: RESEARCH (started 2026-11-19, 23:20).** Branch `mh_implement_184` (from `develop` = `669e75d`). Version to become `WIP-V6-A27`. Nothing is implemented yet.

| Item | State |
|---|---|
| Issues #148 and #184 read, links followed | done (section 2) |
| Research R1: how MiSTer does it | running, notes go to `research/R1-mister.md` |
| Research R2: map of our clocks, video pipeline, menu | running, `research/R2-local-map.md` |
| Research R3: the scaler (ascal) at equal frame rates | running, `research/R3-ascal.md` |
| Research R4: what displays accept | running, `research/R4-display-compat.md` |
| Number search: which pixel clocks and totals are possible | done (section 3, scripts in `tools/`) |
| Design decision | open |
| Specification `SPEC.md` | open |
| Implementation, benches, reviews | open |
| Version bump to `WIP-V6-A27`, docs | open |

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

None yet.

## 5. How to resume

Read section 0, then the research notes in `research/`. The controller session keeps its live checkpoint also in the memory file `project_active_task_state.md`.
