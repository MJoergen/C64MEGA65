# HDMI output at the C64's native frame rate ("Raw"): specification

Issues [#184](https://github.com/MJoergen/C64MEGA65/issues/184) and [#148](https://github.com/MJoergen/C64MEGA65/issues/148). Version `WIP-V6-A27`. The research behind this document is in `research/`, the record of the work in `STATUS.md`.

## 1. What the user gets

The submenu `HDMI: %s` gets a radio group of three ways to deal with the fact that a C64 does not produce 50 Hz or 59.94 Hz:

| Menu item | C64 speed | HDMI frame rate | Picture |
|---|---|---|---|
| `Off` | original | 50.000 Hz (PAL), 59.94 Hz (NTSC) | a tear line crosses the picture every 8 to 9 seconds; scrollers jump |
| `Flicker-free` (default) | 0.25 % slower (PAL), 0.19 % faster (NTSC) | 50.000 Hz, 59.94 Hz | smooth |
| `Raw 50.1 Hz` (PAL), `Raw 59.8 Hz` (NTSC) | original | 50.124 Hz, 59.826 Hz | smooth, on displays that accept this rate |

`Off` and `Flicker-free` behave exactly as "HDMI: Flicker-free" off and on behave in `WIP-V6-A26`. PAL and NTSC remember their choice separately, as before.

### 1.1 The menu

The flat list of the submenu (`CORE/vhdl/config.vhd`), in this order. Lines marked P are shown in PAL only, lines marked N in NTSC only (dependency on `OPTM_G_MACHINE_MODE`, as today).

| # | Text | Group and flags |
|---|---|---|
| 1 | ` HDMI: %s` | `OPTM_G_SUBMENU` (unchanged) |
| 2 | ` HDMI Display Mode` | `OPTM_G_HEADLINE` (unchanged) |
| 3 | (line) | `OPTM_G_LINE` (unchanged) |
| 4 to 9 | the six display modes | unchanged |
| 10 | (line) | `OPTM_G_LINE` (unchanged) |
| 11 | ` HDMI Frame Sync` | `OPTM_G_HEADLINE` (new) |
| 12 | (line) | `OPTM_G_LINE` (new) |
| 13 | ` Off` | `OPTM_G_HDMI_FF`, P (new) |
| 14 | ` Off` | `OPTM_G_HDMI_FF_NTSC`, N (new) |
| 15 | ` Flicker-free` | `OPTM_G_HDMI_FF + OPTM_G_STDSEL`, P (was ` HDMI: Flicker-free`, single-select) |
| 16 | ` Flicker-free` | `OPTM_G_HDMI_FF_NTSC + OPTM_G_STDSEL`, N (was ` HDMI: Flicker-free`, single-select) |
| 17 | ` Raw 50.1 Hz` | `OPTM_G_HDMI_FF`, P (was ` HDMI: Raw 50.1 Hz`, group `OPTM_G_HDMI_RAW50`) |
| 18 | ` Raw 59.8 Hz` | `OPTM_G_HDMI_FF_NTSC`, N (new) |
| 19 | (line) | `OPTM_G_LINE` (new) |
| 20 | ` HDMI Options` | `OPTM_G_HEADLINE` (new) |
| 21 | (line) | `OPTM_G_LINE` (new) |
| 22 | ` HDMI: DVI (no sound)` | unchanged |
| 23 to 35 | ` HDMI: %s`, the filter submenu | unchanged |
| 36 | ` HDMI: Zoom-in` | unchanged |
| 37 | (line) | unchanged |
| 38 | ` Back` | unchanged |

The two groups become radio groups (no `OPTM_G_SINGLESEL`). The group constant `OPTM_G_HDMI_RAW50` (27) is removed; no other group number changes. The menu grows by 8 lines (325 to 333): every `C_MENU_*` index after the display modes moves.

Constants in `CORE/vhdl/mega65.vhd` (the values follow from the golden model `M2M/rom/tests/menu_test.py`):

| Constant | Menu line |
|---|---|
| `C_MENU_HDMI_SYNC_OFF`, `C_MENU_HDMI_SYNC_OFF_NTSC` | 13, 14 (not used by the hardware; for the firmware constants and the tests) |
| `C_MENU_HDMI_FF`, `C_MENU_HDMI_FF_NTSC` | 15, 16 |
| `C_MENU_HDMI_RAW`, `C_MENU_HDMI_RAW_NTSC` | 17, 18 |

`C_MENU_HDMI_RAW50` is removed.

### 1.2 Help and welcome texts

The welcome screen in `config.vhd` names the menu item "HDMI: Flicker-free". It is reworded to the new names without changing the number of lines of the screen.

## 2. How it works

Three facts decide the design (details in `research/`):

1. The scaler (ascal) runs with one frame buffer: the HDMI side reads the picture while the core writes it. A different frame rate on the two sides therefore shows as a tear line that wanders through the picture. Equal frame rates are not enough: the reader also has to stay behind the writer by a suitable distance. Flicker-free does both from the core's side (it switches the core clock so that the writer stays 7 to 14 lines ahead of the reader).
2. The HDMI clock generator cannot produce a pixel clock that gives exactly the C64's frame rate with the standard totals; the nearest settings are 74 to 463 pixel clocks per frame too fast (section 4). Exactly equal rates with static timing exist only with totals far from the standard (720p) or with a different number of lines.
3. MiSTer keeps the standard totals and moves only the pixel clock. That signal is the one that is known to work on displays that accept the odd rates, and with a deviation of 0.15 to 0.27 % it stays inside the 0.5 % that CTA-861 allows for the pixel clock.

So "Raw" consists of:

- **The core** on its original clock, exactly as with flicker-free off.
- **New HDMI modes** (one per existing mode) with the standard totals, sync positions, polarities and VIC, and a pixel clock that is a little faster than the ideal one.
- **A genlock** in the HDMI clock domain that makes 16 lines of the vertical back porch a few pixels longer in every frame, by exactly the amount that makes the HDMI frame as long as the core's frame and holds the start of the HDMI picture 2.0 ms behind the start of the core's picture. Every line that carries picture has the standard length.

## 3. Core side (`CORE/vhdl/mega65.vhd`)

- `main_hdmi_ff` = bit of the item `Flicker-free` of the active machine mode AND NOT the bit of the item `Raw` of the active machine mode. (The Shell writes the menu bits bank by bank, so two bits of a radio group can be set for a moment; then Raw wins on both sides.)
- The process `hr_core_speed`, `clk.vhd`, `CORE.xdc` and the copy of the process in `CORE/vhdl/test/tb_ntsc/tb_core_speed.vhd` do not change.
- `qnice_video_mode_o`: the existing chain stays; in front of it, when the `Raw` bit of the active machine mode is set, the raw member of the selected display mode is chosen:

| Machine mode | Display mode | Raw off | Raw on |
|---|---|---|---|
| PAL | 16:9 720p | `C_VIDEO_HDMI_16_9_50` | `C_VIDEO_HDMI_16_9_50_RAW` |
| PAL | 4:3 576p | `C_VIDEO_HDMI_4_3_50` | `C_VIDEO_HDMI_4_3_50_RAW` |
| PAL | 5:4 576p | `C_VIDEO_HDMI_5_4_50` | `C_VIDEO_HDMI_5_4_50_RAW` |
| NTSC | 16:9 720p | `C_VIDEO_HDMI_16_9_5994` | `C_VIDEO_HDMI_16_9_5994_RAW` |
| NTSC | 4:3 480p | `C_VIDEO_HDMI_4_3_5994` | `C_VIDEO_HDMI_4_3_5994_RAW` |
| NTSC | 5:4 480p | `C_VIDEO_HDMI_5_4_5994` | `C_VIDEO_HDMI_5_4_5994_RAW` |

  For every menu state that exists in `WIP-V6-A26` (no Raw bit set) the output is the same member as before.

## 4. HDMI modes and pixel clocks

### 4.1 `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`

- `video_mode_type` gets six members, appended in this order, with these codes: `C_VIDEO_HDMI_16_9_50_RAW` "1010", `C_VIDEO_HDMI_4_3_50_RAW` "1011", `C_VIDEO_HDMI_5_4_50_RAW` "1100", `C_VIDEO_HDMI_16_9_5994_RAW` "1101", `C_VIDEO_HDMI_4_3_5994_RAW` "1110", `C_VIDEO_HDMI_5_4_5994_RAW` "1111". The ten existing members keep position and code. All 16 codes are in use afterwards.
- `video_mode_is_ntsc` is true for the three NTSC raw members too. New function `video_mode_is_raw` (true for the six raw members).
- The record `video_modes_t`: `CLK_SEL` becomes 4 bits (existing values get a leading `'0'`). Two new fields `CTS_FRAC_N` and `CTS_FRAC_D` (integers): the fraction of a kilohertz that the true pixel clock has above `CLK_KHZ` (section 6); `0` and `1` in every existing record.
- Four new records. Everything that is not listed equals the record it is derived from.

| Record | Derived from | `CLK_SEL` | `CLK_KHZ` | `CTS_FRAC_N / CTS_FRAC_D` |
|---|---|---|---|---|
| `C_HDMI_720p_50_RAW` | `C_HDMI_720p_50` | "1000" | 74444 | 4 / 9 |
| `C_HDMI_576p_50_RAW` | `C_HDMI_576p_50` | "1001" | 27071 | 3 / 7 |
| `C_HDMI_720p_5994_RAW` | `C_HDMI_720p_5994` | "1010" | 74062 | 1 / 2 |
| `C_HDMI_720x480p_5994_RAW` | `C_HDMI_720x480p_5994` | "1011" | 26953 | 1 / 8 |

### 4.2 `M2M/vhdl/controllers/HDMI/video_out_clock.vhd`

`sel` becomes 4 bits; the eight existing tables keep their content and are selected by "0000" to "0111". Four new tables:

| `sel` | CLKFBOUT_MULT_F | DIVCLK_DIVIDE | CLKOUT0 (5x) | CLKOUT1 (pixel) | VCO | Pixel clock |
|---|---|---|---|---|---|---|
| "1000" | 33.500 | 3 | 3 | 15 | 1116.667 MHz | 74.444444 MHz (100 MHz x 67 / 90) |
| "1001" | 47.375 | 7 | 5 | 25 | 676.786 MHz | 27.071429 MHz (100 MHz x 379 / 1400) |
| "1010" | 29.625 | 4 | 2 | 10 | 740.625 MHz | 74.062500 MHz (100 MHz x 237 / 320) |
| "1011" | 43.125 | 4 | 8 | 40 | 1078.125 MHz | 26.953125 MHz (100 MHz x 69 / 256) |

The tables come from the generator `tools/mmcm_tables.py`, which is accepted only if it reproduces the existing tables bit by bit (`research/R5-mmcm-tables.md`). The static attributes of the MMCM and the state machine do not change. The four unused codes "1100" to "1111" select a copy of table "0010" (74.25 MHz).

What the numbers mean per frame (core frame length in pixel clocks minus the standard totals; the genlock supplies this number of extra pixel clocks per frame):

| Mode | Core frame in pixel clocks | Standard totals | Surplus per frame |
|---|---|---|---|
| PAL 720p | 1485196.969 | 1980 x 750 = 1485000 | 196.969 |
| PAL 576p | 540086.019 | 864 x 625 = 540000 | 86.019 |
| NTSC 720p | 1237962.917 | 1650 x 750 = 1237500 | 462.917 |
| NTSC 480p | 450524.479 | 858 x 525 = 450450 | 74.479 |

### 4.3 Every place that lists the modes

`framework.vhd` (`VIDEO_MODE_VECTOR(0 to 15)`, index = position in `video_mode_type`; the chain that gives `qnice_clk_sel`, now 4 bits), `av_pipeline.vhd` (`hdmi_osm_ntsc480` also for the two NTSC 480p raw members), `digital_pipeline.vhd` (vector index, the assertions, `hdmi_hmin`/`hdmi_hmax`/`hdmi_vmin`/`hdmi_vmax`, `hdmi_osm_vshift`): a raw member behaves in all of them exactly like the member it is derived from. `crop.vhd` needs no change (it follows `video_mode_is_ntsc`).

### 4.4 Timing analysis

Vivado times the HDMI domain with the static attributes of the MMCM (74.25 MHz). The fastest new clock is 0.26 % faster (13.433 ns instead of 13.468 ns). `M2M/common.xdc` gets `set_clock_uncertainty -setup 0.050 [get_clocks hdmi_clk]` so that the analysis covers it (the slack of this domain is about 1.4 ns today).

## 5. The genlock (`M2M/vhdl/av_pipeline/hdmi_genlock.vhd`, new)

### 5.1 Ports

```vhdl
entity hdmi_genlock is
   port (
      clk_i       : in  std_logic;                      -- HDMI pixel clock
      rst_i       : in  std_logic;
      enable_i    : in  std_logic;                      -- '1' in the raw modes
      htotal_i    : in  natural range 0 to 4095;        -- nominal number of pixel clocks per line
      target_i    : in  natural range 0 to 2**21 - 1;   -- wanted distance in pixel clocks, see 5.3
      hs_i        : in  std_logic;                      -- hsync of the scaler, high active
      vs_i        : in  std_logic;                      -- vsync of the scaler, high active
      de_i        : in  std_logic;                      -- data enable of the scaler
      ref_i       : in  std_logic;                      -- one clock cycle high: the core starts a picture (clk_i domain)
      htotal_o    : out natural range 0 to 4095;        -- line length for the scaler
      locked_o    : out std_logic;
      stretch_o   : out natural range 0 to 4095         -- extra pixel clocks of the current frame (for benches)
   );
end entity hdmi_genlock;
```

`digital_pipeline.vhd` produces `ref_i`: the vertical blanking of the core as the scaler gets it (`video_vblank_i`, after the crop) crosses into the HDMI clock domain through `xpm_cdc_single` (source register on `video_clk_i`), and its falling edge (the first visible line of the core begins) gives one pulse. The scaler gets `htotal => hdmi_htotal` in every mode that is not a raw mode (a multiplexer in `digital_pipeline.vhd`, not inside the genlock) and `htotal_o` of the genlock in the raw modes. `enable_i` is `'1'` exactly in the raw modes; with `enable_i = '0'` the genlock holds `htotal_o = htotal_i`.

### 5.2 Line stretching

The scaler takes `htotal` over in every clock cycle and uses it only to end a line; a longer line gets its extra pixels at the end of the horizontal back porch. `hs_i`, `vs_i` and `de_i` are the scaler's outputs (10 clock cycles behind its counters).

- The genlock acts at every rising edge of `hs_i` (more than 100 clock cycles before the end of the line in every mode).
- The 16 lines that begin with the line in which `vs_i` falls are the stretch lines: lines 730 to 745 in 720p, 586 to 601 in 576p, 495 to 510 in 480p. They lie in the vertical back porch and end before the scaler fetches the first lines of the next picture (three lines before the picture).
- A frame with the stretch `k` (0 to 4080 pixel clocks): the first `k mod 16` stretch lines are `htotal_i + k / 16 + 1` long, the others `htotal_i + k / 16`. All other lines are `htotal_i` long. No line is ever shorter than `htotal_i`, none longer than `htotal_i + 256`.

### 5.3 Control

- A counter (22 bits, saturating) counts the pixel clocks since the last `ref_i`.
- At the first rising edge of `de_i` after a falling edge of `vs_i` (the first line of the HDMI picture begins) its value is the distance `d`: so many pixel clocks after the core has begun its picture, the HDMI side begins its picture.
- `target_i` = 2 x `CLK_KHZ` of the mode = 2.0 ms. The stretch for the next vertical blanking:

| Condition | Stretch `k` |
|---|---|
| counter saturated (no reference for more than two frames: core paused or in reset) | 0 |
| `d <= target_i` | `min(target_i - d, 4080)` |
| `target_i < d < target_i + 4096` | 0 |
| otherwise | 4080 |

- Without stretch the HDMI frame is shorter than the core's frame by the surplus of section 4.2, so `d` falls by that amount per frame; a stretch `k` raises it by `k`. In the steady state `k` alternates between the two integers around the surplus and `d` stays within a few pixel clocks of `target_i` minus the surplus. From any other phase the genlock stretches by 4080 per frame until the HDMI picture start has fallen behind far enough to arrive at the target from below: at most about 8 seconds in PAL 720p, 6 in NTSC 720p, 3 in 576p and 2 in 480p. During that time a tear line can be visible, as it is today while flicker-free pulls in.
- `locked_o` is `'1'` after 8 frames in a row with `d <= target_i` and `k < 1024`, and `'0'` after a frame that violates this, after `rst_i` and with `enable_i = '0'`.
- `rst_i` (the reset of the HDMI domain, active while the pixel clock is reconfigured) clears all state: stretch 0.

### 5.4 Why 2.0 ms

The reader must stay behind the writer everywhere in the picture and must not fall behind by a whole frame. The distance changes from the top to the bottom of the picture by the difference between the time the HDMI side needs for the picture and the time the core needs for it. With `d` = 2.0 ms:

| Mode | Reader behind writer at the top | at the bottom |
|---|---|---|
| PAL 720p | 1.86 ms | 3.75 ms |
| PAL 576p 4:3 | 1.84 ms | 2.96 ms |
| PAL 576p 5:4 | 2.41 ms | 2.39 ms |
| NTSC 720p | 1.87 ms | 2.03 ms |
| NTSC 480p 4:3 | 1.84 ms | 1.23 ms |
| NTSC 480p 5:4 | 2.32 ms | 0.76 ms |

One line of the core takes 0.064 ms. The smallest value, 0.76 ms, is 12 lines; flicker-free works with 7 to 14 lines at the top of the picture, MiSTer with 4. With zoom-in the core's picture has fewer lines and the distance at the bottom grows; it stays far below a frame (20 ms, 16.7 ms).

## 6. Audio clock regeneration (`digital_pipeline.vhd`)

N stays 6144; the exact CTS is the pixel clock in kHz, which is not an integer for the raw clocks. In the process that produces the 1 kHz strobe of the regeneration packets (`audio_clk`), an accumulator adds `CTS_FRAC_N` at every strobe; when it reaches `CTS_FRAC_D` it is reduced by `CTS_FRAC_D` and this packet carries `CLK_KHZ + 1`, otherwise `CLK_KHZ`. The average is exact. With `CTS_FRAC_N = 0` (every existing mode) the value is `CLK_KHZ` in every packet, as today.

## 7. Verification

| What | How |
|---|---|
| Genlock alone | `CORE/vhdl/test/tb_hdmi_genlock/`: model of the scaler's output counters, the four raw modes with their exact clock ratios, start phases across the whole frame, loss and return of the reference, jump of the core's phase, `enable_i = '0'`; checks: the sum of the frame lengths equals the core's frames (equal rates), `d` within bounds, only the 16 stretch lines differ from `htotal_i`, never shorter, at most 256 longer, pull-in times; mutants |
| Genlock with the real scaler | `CORE/vhdl/test/tb_hdmi_raw/`: `ascal.vhd` with a memory model, a core picture that carries its frame number in every pixel; checks: every HDMI frame shows exactly one core frame, in order, no mixed frame, picture geometry unchanged; the same bench with a standard mode proves that the picture path is unchanged |
| Pixel clock tables | `tools/mmcm_tables.py`: all tables regenerated and compared, the new ones decoded |
| `video_out_clock` | bench with a model of the DRP port: the eight old codes write exactly the same register sequence as before the change |
| CTS | bench of the accumulator: average exact, existing modes constant |
| Menu | `M2M/rom/tests/menu_test.py verify` and `run`, `make_rom.sh`, the heap and stack budgets, `bankdepth_test.py`, the firmware suites |
| Existing benches | `CORE/vhdl/test/tb_ntsc` (all scripts), the differential GHDL analysis of every changed file |
| Not possible here | Vivado build, the picture on real displays: `tests/README.md`, section `Version WIP-V6-A27` |

## 8. What does not change

Everything of section 3.3 of `research/R2-local-map.md`: the core clocks and their selection, the flicker-free detector and its thresholds, the ten existing mode members with their codes and records, the eight existing clock tables, the scaler, the HDMI encoder. In a mode that is not a raw mode the scaler sees the same inputs as before, and the regeneration packets carry the same values.
