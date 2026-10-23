# NTSC support for C64MEGA65: design specification

Issue: [#181](https://github.com/MJoergen/C64MEGA65/issues/181) (Provide NTSC mode).
Branch: `ntsc`, version string `WIP-V6-A22`.
Status: binding design for the implementation workers W1 (clocks and switching), W2 (video) and W3 (core and docs).

Companion files:

- `doc/dev-ntsc/recon_map.md`: every file and line range the implementation touches, grouped by worker.
- `doc/dev-ntsc/tools/ntsc_clocks.py`: MMCM parameter search that produced every clock number in this document (`python3 doc/dev-ntsc/tools/ntsc_clocks.py`).
- `doc/ntsc.md`: the developer description of the implemented NTSC support, including the background on the choice of HDMI modes.

Line numbers refer to the tip of branch `ntsc` (commit `91f8164`) and to the submodule `CORE/C64_MiSTerMEGA65` at `650c6b5`. They are orientation aids; the names are authoritative.

---

## 1. Scope and non-goals

### 1.1 In scope

1. A run-time selectable machine mode PAL or NTSC through the existing OSM items `Model > PAL` / `Model > NTSC` (`C_MENU_MACHINE_PAL = 38`, `C_MENU_MACHINE_NTSC = 39`). PAL stays the default. The selection is saved in the config file like every other OSM item.
2. NTSC means the VIC-II **6567R8** only: 65 cycles per line, 263 lines per frame. The MiSTer core input `mode6567R8` is driven, `mode6567old` and `mode6572` stay `'0'`.
3. A core clock in NTSC that is exactly the ideal NTSC C64 clock (`14.31818 MHz x 16 / 7 = 32.7272727 MHz`), produced by a dedicated MMCM.
4. HDMI in NTSC at 59.94 Hz with the three items that already exist in the menu (`16:9 720p 59.94 Hz`, `4:3 480p 59.94 Hz`, `5:4 480p 59.94 Hz`), plus the NTSC twin of `HDMI: Flicker-free`.
5. HDMI flicker-free in NTSC with the same mechanism as in PAL: the core alternates between two nearby clocks under the control of `hdmi_flicker_free.vhd`.
6. Analog VGA in NTSC: the 15.7 kHz retro modes (HS/VS and CSYNC) and the 31.5 kHz scandoubled "Standard" mode. No new menu items.
7. An automatic soft reset of the C64 whenever the machine mode changes, so that the KERNAL re-detects the region (`$02A6`), including the change that happens when the Shell restores a saved NTSC setting after power-on.
8. All consumers of the core clock frequency are made correct for NTSC or are documented as tolerant (section 5.5).
9. The whole options menu stays visible in NTSC on HDMI and on VGA (section 7).

### 1.2 Non-goals for this alpha

- No PAL-N (6572) and no old NTSC (6567R56A, 64 cycles x 262 lines).
- No exact 60.00 Hz HDMI modes and no 640x480 mode. No variable-refresh or "vsync_adjust" style pixel-clock bending.
- No "HDMI: Raw 50.1 Hz" and no NTSC raw mode (`C_MENU_HDMI_RAW50` stays unwired).
- No turbo mode wiring (the `Model` submenu turbo items stay unwired; nothing in this spec depends on them).
- No change of the OSM font, of `VGA_DX` / `VGA_DY`, or of the menu structure (`OPTM_SIZE`, `OPTM_DY` and every `C_MENU_*` index stay as they are, so the config file format does not change).
- No change inside the submodule `CORE/C64_MiSTerMEGA65`. Section 2 shows that none is needed.
- No run-time reconfiguration (DRP) of the core MMCMs.

---

## 2. MiSTer parity table

Reference: `CORE/C64_MiSTerMEGA65/c64.sv` and `CORE/C64_MiSTerMEGA65/rtl/*`. Every NTSC-dependent item found with `grep -n -i ntsc` plus every consumer of the core clock frequency.

| # | MiSTer (`c64.sv` / RTL) | C64MEGA65 equivalent | Parity | Reason for any deviation |
|---|---|---|---|---|
| 1 | `"P1O2,Video Standard,PAL,NTSC;"`, `wire ntsc = status[2];` (line 210, 927) | OSM `Model > PAL / NTSC`, group `OPTM_G_MACHINE_MODE`; `c64_ntsc <= main_osm_control_i(C_MENU_MACHINE_NTSC)` in `mega65.vhd` | match | Menu location differs (Model submenu); semantics identical, default PAL in both. |
| 2 | PLL reconfiguration: `pll_cfg` writes the fractional `K` word at address 7 (`NTSC 3357876127`, `PAL 1503512573`; the M-counter write at address 4 is commented out), lines 311 to 346. Result: `clk_sys = 50 MHz x (11 + K / 2^32) / 18` = 31 527 955 Hz (PAL) / 32 727 268 Hz (NTSC) | Four permanently running MMCMs (PAL original, PAL flicker-free, NTSC original, NTSC flicker-free) and a glitch-free 4:1 BUFGCTRL tree in `clk.vhd` (section 3) | deviate | Flicker-free needs two clocks running at the same time per mode, and a BUFGCTRL only switches glitch-free between running clocks. DRP reconfiguration would stop the core clock, needs XAPP888 tables and gains nothing because the MMCM budget allows four fixed MMCMs. |
| 3 | `ntscd` / `ntscd2` two-stage sampling of `ntsc` with a stability check before reconfiguring (lines 315 to 322) | `main_osm_control_i` is already synchronized into the main clock domain by the framework; the mode bit reaches `hr_clk` through the existing `cdc_stable` instance `i_cdc_main2hr` (extended to 2 bits) | match | Same purpose: only a stable mode bit switches the clock. |
| 4 | Reset while `!pll_locked`: `reset_counter <= 100000`, i.e. about 3 ms of reset at `clk_sys`; during that reset `force_erase` clears the C64 RAM unless "Clear RAM on Reset" is set to No (`status[24]`, default Yes) (lines 349 to 381) | Mode-change soft reset generated in `main.vhd` (`mode_change_reset_proc`, section 8): a pulse of `C_MODE_RST_LEN = 1024` main clock cycles that joins the soft-reset path, deferred while `prevent_reset = '1'` | deviate | Maintainer decision: a soft reset (like the reset button) is enough for the KERNAL to re-detect the region. C64MEGA65 has no "clear RAM on reset" concept for soft resets. The reset is deferred, never dropped, while a virtual drive writes back (MiSTer has no such interlock). |
| 5 | `.ntscmode(ntsc)` into `fpga64_sid_iec` (line 949): VIC-II `mode6569 => not ntscMode`, `mode6567R8 => ntscMode` (`fpga64_sid_iec.vhd:618-620`); CIA TOD reference `add_value := 120 when ntscMode = '1' else 100` (`fpga64_sid_iec.vhd:845`) | `ntscmode => c64_ntsc_i` is already wired in `main.vhd:1194`; only the source `c64_ntsc` in `mega65.vhd` changes from the constant `'0'` | match | none |
| 6 | Upstream TOD divider uses the hardcoded MiSTer clock | Our port feeds `clk32_speed => clk_main_speed_i` (`main.vhd:1158`, MEGA65 delta in the submodule header) | match | `clk_main_speed_i` becomes mode-dependent (`CORE_CLK_SPEED_PAL` / `CORE_CLK_SPEED_NTSC`), so TOD runs at exactly 50 / 60 Hz. |
| 7 | `drive_ce`: `msum <= ntsc ? 32727264 : 31527954; sum += 16000000` (lines 1122 to 1134) | `iec_drive_ce_proc` (`main.vhd:2656`) with `msum := clk_main_speed_i` | match | Same algorithm, free-running without a reset like MiSTer's; our `msum` is our MMCM-exact value (32 727 273 / 31 527 778) instead of MiSTer's. In flicker-free mode the vanilla value is kept on purpose (issue #2, comment above `iec_drive_ce_proc`). |
| 8 | `video_sync` with `.ntsc(ntsc)` and `.wide(wide)` (lines 1177 to 1189) | `video_sync_inst` in `main.vhd:1881` with `ntsc => '0'` becomes `ntsc => c64_ntsc_i`; `wide => '0'` stays | match | MiSTer sets `wide` only for 600- and 800-line HDMI heights with vertical crop enabled; we have no such modes, so `wide = '0'` is what MiSTer does for every mode we offer. |
| 9 | `vcrop` per `HDMI_HEIGHT` (480 and 720 give 240; comment "NTSC mode has 250 visible lines only!") and `video_freak` `CROP_SIZE` (lines 1215 to 1240) | No vertical-crop option. The M2M feature "HDMI: Zoom-in" (`crop.vhd`) gets NTSC-specific border constants (section 6.7) | deviate | The M2M video path has its own zoom feature and no integer-scale crop; porting `video_freak` is out of scope. |
| 10 | `video_freak` `ARX/ARY` "Original" = 400:300 (4:3) for PAL and NTSC | 720p: the image is framed 4:3 (`hdmi_hmin/hmax`); 480p and 576p: the container is signaled as 4:3 | match | Same intent: the visible C64 area is shown 4:3 in both standards. |
| 11 | `rtcF83 #(16000000, 0)` with `.ce(drive_ce)` (line 1560) | `rtcf83_inst` (`main.vhd:2815`) today `CLOCK_RATE => CORE_CLK_SPEED`, `ce => '1'` becomes `CLOCK_RATE => 16_000_000`, `ce => iec_drive_ce` | match after change | MiSTer's way, decision 9. The RTC is then correct in both modes without a mode-dependent generic. |
| 12 | `CLK_VIDEO = clk64`, `ce_pix` = `clk_sys / 4` in both modes | `video_ce` divider `clk_main / 4` in `main.vhd` | match | none |
| 13 | HDMI timing chosen by the MiSTer framework (`MiSTer.ini`), optionally bent with `vsync_adjust` | NTSC HDMI items fixed at 59.94 Hz plus flicker-free core-clock switching (sections 3, 4, 6) | deviate | M2M has a fixed set of HDMI modes and flicker-free switching instead of a variable pixel clock. |
| 14 | `opl3 #(.OPLCLK(47291931))`, `c1530` tape, `ltc2308_tape #(.CLK_RATE(32000000))`, `to <= 16000000 // 0.5s` | not present in C64MEGA65 | n/a | No OPL, no tape in this port. (MiSTer itself does not adjust `OPLCLK` for NTSC.) |
| 15 | Scandoubler / analog output (`forced_scandoubler`, `video_mixer`) | `analog_pipeline.vhd` uses MiSTer's `video_mixer`; line rate is derived from the core clock | match | NTSC gives 15.734 kHz / 31.469 kHz at 59.826 Hz with no code change in the analog pipeline (section 6.9). |

Conclusion: no file in `CORE/C64_MiSTerMEGA65` changes. Everything NTSC-specific in the MiSTer RTL is already reachable through ports (`ntscMode`, `clk32_speed`, `video_sync.ntsc`).

---

## 3. Clocking (`CORE/vhdl/clk.vhd`, `CORE/CORE.xdc`)

### 3.1 Device and MMCM limits

All four projects (`CORE/CORE-R{3,4,5,6}.xpr`) target `xc7a200tfbg484-2`. `ntsc_clocks.py` enforces the Artix-7 MMCME2_ADV limits with the VCO range of the slower `-1` speed grade so that every set is also valid on a `-1` part: VCO 600 to 1200 MHz, PFD 10 to 450 MHz, `CLKFBOUT_MULT_F` 2 to 64 in 0.125 steps, `DIVCLK_DIVIDE` 1 to 106 (at most 10 with a 100 MHz input because of the PFD minimum), `CLKOUT0_DIVIDE_F` 2 to 128 in 0.125 steps.

### 3.2 Frame lengths and targets

One frame of the MiSTer C64 core is `cycles_per_line x lines x 32` core clock periods: PAL 6569 `63 x 312 x 32 = 628 992`, NTSC 6567R8 `65 x 263 x 32 = 547 040`.

The HDMI frame rates that the existing `video_out_clock.vhd` DRP tables really produce (computed from the tables, not from the labels):

| HDMI mode | `CLK_SEL` | MMCM (M / D / CLKOUT1) | Pixel clock | Frame rate |
|---|---|---|---|---|
| 1280x720p50 | `"010"` | 37.125 / 5 / 10 | 74.250000 MHz | 50.000000 Hz |
| 720x576p50 | `"001"` | 47.25 / 5 / 35 | 27.000000 MHz | 50.000000 Hz |
| 720x480p59.94 | `"001"` | 47.25 / 5 / 35 | 27.000000 MHz | 59.940060 Hz |
| 1280x720p59.94 | `"110"` | 22.25 / 3 / 10 | 74.166667 MHz | 59.932660 Hz |

`CLK_SEL "110"` is labeled 74.176 MHz but produces 74.166667 MHz (-123.5 ppm, well inside the HDMI tolerance). `ntsc_clocks.py` shows that no single-MMCM configuration with a 5:1 serializer ratio does better, so the table stays as it is. Consequence: the two NTSC HDMI containers do not have the same frame rate (59.940060 Hz versus 59.932660 Hz), and the NTSC flicker-free clock must lie above the higher of the two.

### 3.3 Final MMCM parameter sets

Output of `python3 doc/dev-ntsc/tools/ntsc_clocks.py --final`:

```text
====================================================================================================
FINAL TABLE (used in doc/dev-ntsc/NTSC-SPEC.md section 3)
====================================================================================================
  clock                                      M  D      O0   VCO MHz  PFD MHz         f_out Hz  integer Hz   frame Hz vs ideal ppm
  PAL original      (i_clk_c64_orig)    56.750  6  30.000   945.833   16.667     31527777.778    31527778  50.124291         -5.6
  PAL flicker-free  (i_clk_c64_slow)    60.500  9  21.375   672.222   11.111     31448992.853    31448993  49.999035      -2504.5
  NTSC original     (i_clk_c64_ntsc)    36.000  5  22.000   720.000   20.000     32727272.727    32727273  59.826105         +0.0
  NTSC flicker-free (i_clk_c64_ntsc_ff) 47.750  5  29.125   955.000   20.000     32789699.571    32789700  59.940223      +1907.5

  Flicker-free duty cycle (share of time on the flicker-free clock) and frame drift:
    PAL  50 Hz modes   : HDMI 50.000000 Hz | orig 50.124291 Hz ( +38.78 lines/s) | ff 49.999035 Hz ( -0.301 lines/s) | time on ff clock  99.23 %
                         window 7.11 lines (stride 1152 bytes): one hysteresis cycle   23.61 s on ff + 0.183 s on orig
    NTSC 480p59.94     : HDMI 59.940060 Hz | orig 59.826105 Hz ( -29.97 lines/s) | ff 59.940223 Hz ( +0.043 lines/s) | time on ff clock  99.86 %
                         window 6.40 lines (stride 1280 bytes): one hysteresis cycle  149.27 s on ff + 0.214 s on orig
    NTSC 720p59.94     : HDMI 59.932660 Hz | orig 59.826105 Hz ( -28.02 lines/s) | ff 59.940223 Hz ( +1.989 lines/s) | time on ff clock  93.37 %
                         window 6.40 lines (stride 1280 bytes): one hysteresis cycle    3.22 s on ff + 0.228 s on orig

  CORE_CLK_SPEED_PAL  = 31527778
  CORE_CLK_SPEED_NTSC = 32727273
```

The "vs ideal" column compares with the real crystal-derived clock of the respective standard (PAL `17.734475 MHz x 16 / 9`, NTSC `14.31818 MHz x 16 / 7`); for the flicker-free legs it is the intended speed shift. The hysteresis window is the distance between `G_THRESHOLD_LOW = x"0000_1000"` and `G_THRESHOLD_HIGH = x"0000_2000"` (`av_pipeline.vhd:604-605`). These are 16-bit HyperRAM word addresses, i.e. 8192 bytes, and ascal stores one input line per stride of `width x 3` bytes rounded up to 128 bytes (PAL 1152, NTSC 1280), so the window is 7.11 input lines in PAL and 6.40 in NTSC. The cycle times agree with the closed-loop model `doc/dev-ntsc/tools/ff_model.py` (analytic switching period PAL 23.8 s, NTSC 480p 149.5 s, NTSC 720p 3.45 s; simulated 26.0 s, 151.4 s, 3.27 s).

**NTSC original** (`i_clk_c64_ntsc`): `CLKFBOUT_MULT_F = 36.000`, `DIVCLK_DIVIDE = 5`, `CLKOUT0_DIVIDE_F = 22.000`; VCO 720 MHz, PFD 20 MHz, 32 727 272.727 Hz, error versus the ideal NTSC clock 0 ppm, frame rate 59.826105 Hz. The alternative exact set 6.75 / 1 / 20.625 exists, but 36 / 5 / 22 uses integer dividers only (no fractional-divider jitter) and is preferred.

**NTSC flicker-free** (`i_clk_c64_ntsc_ff`): `CLKFBOUT_MULT_F = 47.750`, `DIVCLK_DIVIDE = 5`, `CLKOUT0_DIVIDE_F = 29.125`; VCO 955 MHz, PFD 20 MHz, 32 789 699.571 Hz, frame rate 59.940223 Hz. This is the legal MMCM output closest above 720x480p59.94 (59.940060 Hz, +2.72 ppm); it is +126.2 ppm above the real 1280x720p59.94 rate (59.932660 Hz). While the core is on this clock the C64 runs 0.191 % faster than an original NTSC machine.

Justification of the second frequency:

- It must be above 59.940060 Hz, otherwise the 480p modes can never catch up. The 720p rate is lower, so one clock serves both containers.
- Closest above the target is best: the core sits on the flicker-free leg 99.86 % of the time in 480p and 93.4 % in 720p and drops to the original clock (59.826 Hz) for about 0.2 s per correction. The closer the leg is to the HDMI rate, the rarer the corrections.
- Mirror of PAL: in PAL the flicker-free leg is the one the core sits on 99.2 % of the time (19.3 ppm below 50 Hz) and the original clock only gives short corrections. The NTSC leg plays the same role with the sign flipped.
- Audio pitch: the steady-state pitch is the flicker-free leg (+0.191 %, about 3.3 cents above an original NTSC C64, compared with -0.25 %, about 4.3 cents, in PAL). Each correction is a 0.2 s dip of 3.3 cents, once every 150 s in 480p and once every 3.4 s in 720p (the 720p interval is dominated by the -123.5 ppm offset of the HDMI pixel clock, not by the choice of the flicker-free clock).
- Margin: core clock and HDMI pixel clock are both derived from the same 100 MHz oscillator, so their ratio is exact and oscillator tolerance cannot push the core below the HDMI rate; 2.72 ppm is enough. The only cost of a small margin is a slow lock acquisition when the write position starts below the low threshold: the model gives at most 35.5 s in 480p (8.9 s in 720p), compared with up to 986 s for today's PAL pair, which is field-proven.
- The model also locks with faster legs such as 32 795 000 Hz (59.9499 Hz, 2.7 s switching period in 480p, 92 % on the fast clock) and 32 800 000 Hz (59.9591 Hz, 1.5 s, 86 %), so the choice is about correction rate, not about stability. The next legal sets above the chosen one are +7.46 ppm (`22.625 / 2 / 34.5`, VCO 1131.25 MHz) and +12.8 ppm (`42.75 / 7 / 18.625`, VCO at the 600 MHz minimum).

`CORE_CLK_SPEED_NTSC` in `globals.vhd` becomes `32_727_273` (the MMCM-exact integer of `i_clk_c64_ntsc`), in the same way as `CORE_CLK_SPEED_PAL = 31_527_778` is the integer of `i_clk_c64_orig` and not MiSTer's value. The dividers bench (`CORE/vhdl/test/tb_ntsc/run.sh dividers`) shows that TOD and the 1541 chip enable are exact (within 0.02 ppm) at 50 / 60 Hz and 16 MHz only when `clk32_speed` equals the real clock, so this value is binding. The flicker-free legs never get a constant of their own: every counter keeps using the vanilla value of the active standard (comment above `iec_drive_ce_proc`, issue #2).

### 3.4 Resources

Today R6 uses 4 of 10 MMCMs (`i_clk_audio` in `clk_m2m.vhd`, the HDMI `video_out_clock` MMCM, `i_clk_c64_orig`, `i_clk_c64_slow`; `i_clk_qnice` is a PLLE2) and 11 of 32 BUFGCTRL. After the change: 6 of 10 MMCMs (+2) and 13 of 32 BUFGCTRL (+2). The xc7a200t has 10 CMTs, each with one MMCM and one PLL, so this fits on every board revision.

### 3.5 Clock-select encoding (`core_speed_i`)

`core_speed_i` stays 2 bits wide. It no longer grows; the meaning of the bits is fixed as:

| `core_speed_i` | Clock | Frame rate |
|---|---|---|
| `"00"` | PAL original (`i_clk_c64_orig`) | 50.124291 Hz |
| `"01"` | PAL flicker-free (`i_clk_c64_slow`) | 49.999035 Hz |
| `"10"` | NTSC original (`i_clk_c64_ntsc`) | 59.826105 Hz |
| `"11"` | NTSC flicker-free (`i_clk_c64_ntsc_ff`) | 59.940223 Hz |

Bit 1 is the standard (0 = PAL, 1 = NTSC), bit 0 selects the flicker-free leg of that standard. Note that "flicker-free leg" means *slower* than the original in PAL and *faster* than the original in NTSC; section 4.2 handles the inverted polarity.

### 3.6 Glitch-free mux tree

`clk.vhd` keeps its architecture and adds two MMCMs and two `bufgmux_ctrl` instances:

```text
i_clk_c64_orig    --I0--+
                        +-- bufgmux_pal_inst  (s => core_speed_i(0)) --I0--+
i_clk_c64_slow    --I1--+                                                  |
                                                                           +-- bufgmux_mode_inst (s => core_speed_i(1)) -- BUFG main_clk_bufg -- main_clk_o
i_clk_c64_ntsc    --I0--+                                                  |
                        +-- bufgmux_ntsc_inst (s => core_speed_i(0)) --I1--+
i_clk_c64_ntsc_ff --I1--+
```

- `bufgmux_ctrl_inst` is renamed to `bufgmux_pal_inst` (same ports). New instances `bufgmux_ntsc_inst` and `bufgmux_mode_inst`. Signal names: `main_clk_mmcm_ntsc`, `main_clk_mmcm_ntsc_ff`, `main_fb_mmcm_ntsc`, `main_fb_mmcm_ntsc_ff`, `main_locked_ntsc`, `main_locked_ntsc_ff`, `main_clk_pal`, `main_clk_ntsc` (outputs of the first level), `main_clk_mmcm` (output of `bufgmux_mode_inst`, input of the existing `main_clk_bufg`).
- All four MMCMs run continuously, so every BUFGCTRL always switches between two running clocks, which is the precondition for glitch-free switching. Cascading BUFGCTRLs is supported by the 7-series clock routing.
- The two new MMCMs are copies of `i_clk_c64_orig` with the generics of section 3.3; everything else (`BANDWIDTH "OPTIMIZED"`, `COMPENSATION "ZHOLD"`, `CLKIN1_PERIOD 10.0`, DRP and PS ports tied off) is identical.
- Both selects are asynchronous to all four clocks, exactly like today's single select.

### 3.7 Reset generation

`i_xpm_cdc_async_rst_main` keeps its structure; its source becomes the AND of all four locks:

```vhdl
src_arst => not (main_locked_orig and main_locked_slow and main_locked_ntsc and main_locked_ntsc_ff),
```

No MMCM is ever reset or reconfigured at run time, so after power-on lock `main_rst_o` never asserts again. The mode-change reset is a logic reset (section 8), not a clock reset; this is a deliberate deviation from MiSTer's "reset while the PLL relocks" (parity row 4).

### 3.8 Timing constraints (`CORE/CORE.xdc`)

The fastest of the four clocks is now NTSC flicker-free (30.497 ns, exactly 30.4974 ns) instead of PAL original (31.718 ns), i.e. 3.85 % tighter. All four clocks drive the same logic through the same post-mux clock tree, so the design is timed once, at the fastest clock, with the same "case analysis" technique that CORE.xdc already uses:

```text
## Time the core at its fastest clock (NTSC flicker-free, 32.789700 MHz). All four core
## clocks share the post-mux clock tree, so this covers the three slower ones as well.
set_case_analysis 1 [get_pins CORE/hr_core_speed_reg[0]/Q]
set_case_analysis 1 [get_pins CORE/hr_core_speed_reg[1]/Q]

create_generated_clock -name main_clk [get_pins CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0]
```

These three lines replace CORE.xdc lines 5 to 9. With both selects forced to `'1'`, Vivado propagates only `i_clk_c64_ntsc_ff` through `bufgmux_ntsc_inst` and `bufgmux_mode_inst`; the other three MMCM outputs reach no sequential element, so no `set_clock_groups -physically_exclusive` and no additional false paths are needed. Keeping the name `main_clk` keeps every other constraint that refers to it valid (CORE.xdc lines 52 and 53, the `[get_generated_clocks]` max-delay rules in `M2M/common.xdc`).

`M2M/common.xdc` needs no change: `hdmi_clk` / `tmds_clk` are timed from the static generics of the `video_out_clock` MMCM, and 74.166667 MHz is below the 74.25 MHz modes that already exist.

Companion change in `CORE/signoff_gates.tcl` (owned by W1, it mirrors CORE.xdc and must change in the same commit): check both `CORE/hr_core_speed_reg[0]/Q` and `CORE/hr_core_speed_reg[1]/Q`, check the source pin `CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0`, and expect the `main_clk` period `30.497 ns` (tolerance 0.05 ns; the next slower leg, NTSC original, has 30.556 ns, so the tolerance must be tightened to 0.03 ns to catch a wrong leg).

Naming requirement for W1: `hr_core_speed` stays one 2-bit signal assigned in one clocked process in `mega65.vhd`, so that synthesis names the flops `hr_core_speed_reg[0]` and `hr_core_speed_reg[1]`. Add `attribute dont_touch : string; attribute dont_touch of hr_core_speed : signal is "true";` so neither flop is merged or renamed.

---

## 4. Core speed and flicker-free switching (`CORE/vhdl/mega65.vhd`)

### 4.1 Machine mode and clock speed (main clock domain)

`main_osm_control_i` is already in the main clock domain (the framework synchronizes it), so the machine mode is a plain decode:

```vhdl
-- replaces "c64_ntsc <= '0'" (mega65.vhd:674)
c64_ntsc        <= main_osm_control_i(C_MENU_MACHINE_NTSC);   -- 0 = PAL (default), 1 = NTSC

-- replaces "c64_clock_speed <= CORE_CLK_SPEED" (mega65.vhd:683)
c64_clock_speed <= CORE_CLK_SPEED_NTSC when c64_ntsc = '1' else CORE_CLK_SPEED_PAL;

-- flicker-free switch of the active standard (new signal main_hdmi_ff)
main_hdmi_ff    <= main_osm_control_i(C_MENU_HDMI_FF_NTSC) when c64_ntsc = '1' else
                   main_osm_control_i(C_MENU_HDMI_FF);
```

`c64_clock_speed` stays of type `natural` and feeds `clk_main_speed_i` of `i_main` (unchanged port map line). It always carries the vanilla value of the active standard, also while the flicker-free leg runs.

The constant `CORE_CLK_SPEED` in `globals.vhd` stays and keeps the value `CORE_CLK_SPEED_PAL`. Its remaining users are the generic and constant consumers listed in section 5.5, which are deliberately PAL-based.

### 4.2 Clock-domain crossing into `hr_clk` and the `hr_core_speed` process

`i_cdc_main2hr` (`mega65.vhd:1225`) grows from 1 to 2 bits:

```vhdl
i_cdc_main2hr : entity work.cdc_stable
   generic map (
      G_REGISTER_SRC => true,
      G_DATA_SIZE    => 2
   )
   port map (
      src_clk_i     => main_clk_o,
      src_data_i(0) => main_hdmi_ff,
      src_data_i(1) => c64_ntsc,
      dst_clk_i     => hr_clk_i,
      dst_data_o(0) => hr_hdmi_ff,
      dst_data_o(1) => hr_ntsc
   ); -- i_cdc_main2hr
```

The `hr_core_speed` process (`mega65.vhd:589`) becomes:

```vhdl
-- Switch between the original clock and the flicker-free clock of the active standard so that
-- the core frame rate "embraces" the HDMI frame rate. PAL: the original clock (50.124 Hz) is the
-- faster one, the flicker-free clock (49.999 Hz) the slower one. NTSC: the original clock
-- (59.826 Hz) is the slower one, the flicker-free clock (59.9402 Hz) the faster one.
process (hr_clk_i)
begin
   if rising_edge(hr_clk_i) then
      hr_core_speed(1) <= hr_ntsc;                 -- 0 = PAL clocks, 1 = NTSC clocks
      if hr_low_i = '1' then                       -- the core is too slow ...
         hr_core_speed(0) <= hr_ntsc;              -- ... PAL: original (00), NTSC: flicker-free (11)
      end if;
      if hr_high_i = '1' then                      -- the core is too fast ...
         hr_core_speed(0) <= not hr_ntsc;          -- ... PAL: flicker-free (01), NTSC: original (10)
      end if;
      if hr_hdmi_ff = '0' then
         hr_core_speed(0) <= '0';                  -- flicker-free off: original clock of the standard
      end if;
   end if;
end process;
```

Polarity is the key difference to PAL: in NTSC, "too slow" selects the flicker-free leg, "too fast" selects the original clock. Getting this wrong makes the core run away from the HDMI rate instead of locking to it.

Crossings involved:

| Signal | From | To | Mechanism |
|---|---|---|---|
| `main_osm_control_i` | QNICE | main | existing framework CDC |
| `c64_ntsc`, `main_hdmi_ff` | main | `hr_clk` | `i_cdc_main2hr` (`cdc_stable`, now 2 bits); both bits are quasi-static |
| `hr_low_i`, `hr_high_i` | `hr_clk` | `hr_clk` | already in `hr_clk` (`hdmi_flicker_free.vhd`) |
| `hr_core_speed(1 downto 0)` | `hr_clk` | BUFGCTRL `S` pins | asynchronous by design; the BUFGCTRL resynchronizes internally to both of its input clocks |

The mux select changes a few `hr_clk` cycles after the OSM bit (well below 1 us). Section 8 makes sure the C64 reset covers that window.

### 4.3 HDMI mode selection (QNICE clock domain)

`qnice_video_mode_o` (`mega65.vhd:1039`) is decoded from the machine mode and from the PAL or NTSC display-mode group. The machine bit is taken from `qnice_osm_control_i`, which is already in the QNICE domain:

```vhdl
qnice_video_mode_o <=
   C_VIDEO_HDMI_5_4_5994  when qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '1' and qnice_osm_control_i(C_MENU_HDMI_5_4_5994) = '1' else
   C_VIDEO_HDMI_4_3_5994  when qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '1' and qnice_osm_control_i(C_MENU_HDMI_4_3_5994) = '1' else
   C_VIDEO_HDMI_16_9_5994 when qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '1' else      -- C_MENU_HDMI_16_9_5994 (group default)
   C_VIDEO_HDMI_5_4_50    when qnice_osm_control_i(C_MENU_HDMI_5_4_50)  = '1' else
   C_VIDEO_HDMI_4_3_50    when qnice_osm_control_i(C_MENU_HDMI_4_3_50)  = '1' else
   C_VIDEO_HDMI_16_9_50;                                                                  -- C_MENU_HDMI_16_9_50
```

Invariant (relied upon by W2, section 6.2): `qnice_video_mode_o` is one of the three `*_5994` members introduced in section 6.1 if and only if `qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '1'`. The PAL and NTSC display-mode groups are separate OSM groups (`OPTM_G_HDMI_MODES_PAL = 13`, `OPTM_G_HDMI_MODES_NTSC = 25`), each with its own default, so each standard remembers its own HDMI choice and switching the machine mode switches to that choice.

Remove the stale comments that say the NTSC items are "deliberately not wired up yet" (`mega65.vhd:1036-1038`, the comments above `C_MENU_MACHINE_PAL` and `C_MENU_HDMI_16_9_50`) and the `@TODO`s in `clk.vhd` and `globals.vhd`.

### 4.4 Summary of `mega65.vhd` changes

1. `c64_ntsc`, `c64_clock_speed`, new `main_hdmi_ff` (4.1).
2. `i_cdc_main2hr` with 2 bits, new `hr_ntsc`, the new `hr_core_speed` process and the `dont_touch` attribute (4.2, 3.8).
3. `qnice_video_mode_o` decode (4.3).
4. Comment of `clk_gen`: "0=PAL original, 1=PAL flicker-free, 2=NTSC original, 3=NTSC flicker-free".
5. No new port on `MEGA65_Core`, so none of the four `M2M/vhdl/top_mega65-r?.vhd` files changes.

---

## 5. C64 core wiring (`CORE/vhdl/main.vhd`)

### 5.1 `video_sync`

`video_sync_inst` (`main.vhd:1881`): `ntsc => c64_ntsc_i` (was `'0'`), `wide => '0'` stays. Update the comment above it: PAL crops to 382 x 270, NTSC to 404 x 250 (section 6.6).

### 5.2 `clk32_speed` and `ntscmode`

Unchanged port map lines (`main.vhd:1158`, `main.vhd:1194`). They become live because `mega65.vhd` now drives `c64_ntsc_i` and a mode-dependent `clk_main_speed_i`. Update the stale comment at `main.vhd:1191-1192` (it describes PAL only).

### 5.3 `iec_drive_ce_proc`

`msum := clk_main_speed_i` is the vanilla value of the active standard, which keeps the 1541/1581 at 1 MHz in both standards (16 000 000 / 32 727 273 x 32 727 272.7 Hz = 15 999 999.9 Hz chip enable). The flicker-free legs shift the drive speed together with the C64 speed (+0.191 % NTSC, -0.25 % PAL), which keeps the C64-to-drive ratio constant (issue #2).

The process has no reset, like MiSTer's `drive_ce` (`c64.sv:1122-1135`): the chip enable runs freely. The drives have their own reset input, and the RTC of section 5.4 counts these pulses, so a reset branch would stop the GEOS clock whenever `reset_core_n = '0'`: at power-on and after a long press of the reset button for at least the Shell's SD card wait (`SD_WAIT` = 2 s) plus the config load and `CRTROM_AUTOLOAD`, on every short press for the hold time plus `RST_DURATION` = 50 ms, and for a few microseconds on every mode change, `M2M$CSR_RESET` pulse and PRG load. `iec_dce_sum` stays below `msum` by construction, also when `msum` drops at a switch from NTSC to PAL: the sum is below 32 727 273, `nextsum` below 48 727 273, and one subtraction of 31 527 778 leaves less than 17 200 000, which is below `msum` again. The left-over phase of the other standard is a fraction of one chip-enable period and harmless.

### 5.4 `rtcf83_inst`

MiSTer's way (parity row 11):

```vhdl
rtcf83_inst : component rtcf83
  generic map (
    CLOCK_RATE => 16_000_000,      -- counts iec_drive_ce pulses (16 MHz in PAL and NTSC), like MiSTer
    HAS_RAM    => 0
  )
  port map (
    clk   => clk_main_i,
    ce    => iec_drive_ce,
    ...                            -- rest unchanged
```

`rtcF83.sv` counts `seccnt` only when `ce = '1'` and compares with `CLOCK_RATE / 100`, so the PCF8583 seconds stay exact in both standards. Because `iec_drive_ce` runs freely (section 5.3), the RTC keeps counting while the C64 is held in reset; it only loads the time from the MEGA65 RTC (`RTC[64]` toggle) and is reset by `reset_hard_i`. The I2C sampling of `scl_i` / `sda_i` is also qualified by `ce`; at 16 MHz this is far faster than the GEOS bit-banging, exactly as on MiSTer.

### 5.5 Inventory of clock-speed consumers

`grep -rn CORE_CLK_SPEED CORE/vhdl M2M/vhdl` plus every MiSTer consumer of the clock rate:

| # | Consumer | Location | Kind | Decision | Effect in NTSC |
|---|---|---|---|---|---|
| 1 | CIA TOD divider `clk32_speed` | `main.vhd:1158` to `fpga64_sid_iec.vhd:844` | port | mode-dependent (`clk_main_speed_i`) | TOD exactly 60 Hz (`add_value 120`) |
| 2 | 1541/1581 chip enable `msum` | `main.vhd:2659` | port | mode-dependent (`clk_main_speed_i`) | drives exactly 1 MHz |
| 3 | `rtcf83_inst` `CLOCK_RATE` | `main.vhd:2817` | generic | MiSTer's way: `16_000_000` with `ce => iec_drive_ce` | exact |
| 4 | Joystick debouncer `i_joy_debouncer` `CLK_FREQ => CORE_CLK_SPEED` | `framework.vhd:550` | generic | keep the PAL constant (tolerant) | 1 ms stable time becomes 0.963 ms |
| 5 | Keyboard `i_m2m_keyb` `clk_main_speed_i => CORE_CLK_SPEED` (used as `clock_frequency` of `mega65kbd_to_matrix` and `matrix_to_keynum`) | `framework.vhd:602`, `m2m_keyb.vhd:75,104` | port fed by a constant | keep the PAL constant (tolerant) | keyboard serial clock and scan rate 3.8 % faster; the FPGA drives the keyboard clock, so the protocol is unaffected |
| 6 | `C_RESET_DELAY := 4 * CORE_CLK_SPEED` | `prg_loader.vhd:55` | constant | keep | counts `qnice_clk` (50 MHz), so it does not depend on the C64 standard at all (2.5 s) |
| 7 | `C_HARD_RST_DELAY = 100_000` main cycles | `main.vhd:768` | constant | keep | 3.06 ms instead of 3.17 ms |
| 8 | EF3 heuristics windows (about 200 main cycles), `C_EF3_RESET_LEN` in PHI2 cycles | `cartridge_heuristics.vhd`, `main.vhd` | constants | keep | windows 3.8 % shorter; PHI2-based lengths unaffected |
| 9 | Audio path main clock to `audio_clk` | `framework.vhd` (`cdc_stable` around line 775) | level sampling | none | no resampler depends on the core clock; SID pitch follows the CPU clock like real hardware |
| 10 | `iec_drive`, `c1541_*`, `c1581_*`, `fdc1772` | submodule | chip-enable based | none | follow `iec_drive_ce` |
| 11 | Physical 1581 controller and MFM path | `CORE/vhdl/physical_1581/*` | runs on the 50 MHz QNICE clock | none | independent of the C64 clock |

Making consumers 4 and 5 mode-dependent would need a new port from `MEGA65_Core` through all four top-level files for no functional gain; MiSTer has no equivalent (PS/2 keyboard, no debouncer).

### 5.6 Mode-change reset

Specified in section 8; it is the only new process in `main.vhd`.

---

## 6. HDMI modes and the video pipeline

### 6.1 `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`

New mode record (a copy of `C_HDMI_720p_60` with the NTSC-family clock and the field-proven sync polarity of `C_HDMI_720p_50`):

```vhdl
constant C_HDMI_720p_5994 : video_modes_t := (
   CLK_KHZ     => 74167,      -- 74.1667 MHz: what CLK_SEL "110" really produces (74.25 MHz / 1.001 = 74.176 MHz nominal)
   CLK_SEL     => "110",
   CEA_CTA_VIC => 4,          -- CEA/CTA VIC 4: 1280x720p, 59.94/60 Hz, 16:9
   ASPECT      => "10",       -- 16:9
   PIXEL_REP   => '0',
   H_PIXELS    => 1280,
   V_PIXELS    => 720,
   H_FP        => 110,
   H_PULSE     => 40,
   H_BP        => 220,
   V_FP        => 5,
   V_PULSE     => 5,
   V_BP        => 20,
   H_POL       => '1',
   V_POL       => '1'
);
```

`CLK_KHZ` must be the true pixel clock because `digital_pipeline.vhd:268` uses it as the HDMI audio clock regeneration value (`CTS = CLK_KHZ` with `N = 6144`); 74176 would make the sink regenerate 47.994 kHz instead of 48 kHz and slowly overrun its audio buffer. With 74167 the residual error is 4.5 ppm.

New enum members, appended at the end of `video_mode_type` so that the existing encodings do not move:

| Member | `video_mode_to_slv` | `VIDEO_MODE_VECTOR` index | Record | OSM item |
|---|---|---|---|---|
| `C_VIDEO_HDMI_16_9_5994` | `"0111"` | 7 | `C_HDMI_720p_5994` | `16:9 720p 59.94 Hz` (`C_MENU_HDMI_16_9_5994 = 58`) |
| `C_VIDEO_HDMI_4_3_5994` | `"1000"` | 8 | `C_HDMI_720x480p_5994` | `4:3  480p 59.94 Hz` (`C_MENU_HDMI_4_3_5994 = 60`) |
| `C_VIDEO_HDMI_5_4_5994` | `"1001"` | 9 | `C_HDMI_720x480p_5994` | `5:4  480p 59.94 Hz` (`C_MENU_HDMI_5_4_5994 = 62`) |

`slv_to_video_mode` gets the three reverse entries. The encoding stays 4 bits wide (10 of 16 codes used). The existing members `C_VIDEO_HDMI_16_9_60`, `C_VIDEO_HDMI_640_60`, `C_VIDEO_HDMI_720_5994` and `C_VIDEO_SVGA_800_60` stay untouched and unused by this core.

New helper function in the package (declaration and body):

```vhdl
-- true for the video modes that the C64 core uses while the machine runs in NTSC
pure function video_mode_is_ntsc(video_mode : video_mode_type) return boolean;
-- body: return video_mode = C_VIDEO_HDMI_16_9_5994 or video_mode = C_VIDEO_HDMI_4_3_5994 or
--               video_mode = C_VIDEO_HDMI_5_4_5994;
```

### 6.2 `M2M/vhdl/framework.vhd`

- `VIDEO_MODE_VECTOR` (line 277) becomes `video_modes_vector(0 to 9)`, appending `C_HDMI_720p_5994`, `C_HDMI_720x480p_5994`, `C_HDMI_720x480p_5994` (indices 7, 8, 9, with comments).
- The clock-select decode `video_mode <= ...` (line 499) gets three lines in front of the default: `C_HDMI_720p_5994 when qnice_video_mode_i = C_VIDEO_HDMI_16_9_5994`, `C_HDMI_720x480p_5994 when ... = C_VIDEO_HDMI_4_3_5994`, `C_HDMI_720x480p_5994 when ... = C_VIDEO_HDMI_5_4_5994`.
- Nothing else in `framework.vhd` changes (the debouncer and keyboard consumers stay on the PAL constant, section 5.5).

The machine standard reaches the framework only through `qnice_video_mode_i`, using the invariant of section 4.3. No new port on `framework`, `MEGA65_Core` or the top-level files.

### 6.3 `M2M/vhdl/av_pipeline/digital_pipeline.vhd`

Mode record selection (line 179): three new lines `G_VIDEO_MODE_VECTOR(7/8/9) when hdmi_video_mode_i = C_VIDEO_HDMI_16_9_5994 / _4_3_5994 / _5_4_5994`.

Assertions (lines 196 to 202): add `assert G_VIDEO_MODE_VECTOR(7).H_PIXELS >= G_VIDEO_MODE_VECTOR(7).V_PIXELS*4/3;`. For indices 8 and 9 (a 3:2 container signaled as 4:3) the 4:3 assertion does not apply; assert instead `G_VIDEO_MODE_VECTOR(8).H_PIXELS = 720 and G_VIDEO_MODE_VECTOR(8).V_PIXELS = 480` (same for 9).

Output window of the scaler (the `when hdmi_crop_mode_i = '1'` branch, i.e. zoom-in, keeps filling the whole frame in every mode, exactly like PAL):

| Mode | `hdmi_hmin` | `hdmi_hmax` | `hdmi_vmin` | `hdmi_vmax` | Result |
|---|---|---|---|---|---|
| `C_VIDEO_HDMI_16_9_5994` | `(H - V*4/3)/2` = 160 | `(H + V*4/3)/2 - 1` = 1119 | 0 | `V - 1` = 719 | 960 x 720 window, 4:3 pillarbox (as `16_9_50`) |
| `C_VIDEO_HDMI_4_3_5994` | 0 | `H - 1` = 719 | 0 | `V - 1` = 479 | full container, the sink stretches it to 4:3 (as `4_3_50`) |
| `C_VIDEO_HDMI_5_4_5994` | 0 | `H - 1` = 719 | `(V - V*15/16)/2` = 15 | `(V + V*15/16)/2` = 465 | 720 x 451 letterbox |

Derivation of the 5:4 row: the PAL item letterboxes `720 x 576` to `720 x 540` so that a 5:4 display, which shows the 720 x 576 container as 5:4, shows a 4:3 picture. A 5:4 display shows any container as 5:4, so the 4:3 picture needs `V x 15/16` of the container height. For PAL that is `576 x 15/16 = 540`, the same value the current expression `(V + H*3/4)/2` produces; for 480p it is 450. The new expression uses `V*15/16`; do not reuse `H*3/4` (it gives 540 > 480 for 720 x 480). The inclusive upper bound (`465` instead of `464`) mirrors the existing PAL convention (`558`).

`hdmi_shift` (line 250) needs no change: `1280 - 720 = 560` for 720p and `720 - 720 = 0` for 480p.

OSM scaling force for 480p: section 7.4.

Zoom-in needs the standard in the video clock domain: section 6.7.

### 6.4 `video_out_clock.vhd`

No functional change; `CLK_SEL "110"` already exists. Correct the comment of `sel` value `110` to "74.176 MHz nominal, 74.1667 MHz actual (CLKFBOUT_MULT_F 22.25, DIVCLK_DIVIDE 3)" so that the next reader does not trust the label.

### 6.5 HDMI infoframe and audio

| Item | VIC | Aspect (`ASPECT`) | Pixel repetition | ACR CTS (`CLK_KHZ`) |
|---|---|---|---|---|
| `16:9 720p 59.94 Hz` | 4 | `"10"` 16:9 | no | 74167 |
| `4:3 480p 59.94 Hz` | 2 | `"01"` 4:3 | no | 27000 |
| `5:4 480p 59.94 Hz` | 2 | `"01"` 4:3 | no | 27000 |

This mirrors PAL, where both 576p items send VIC 17 with 4:3 aspect. CTA-861 uses the same VIC for the 60 Hz and the 59.94 Hz variant of a format.

### 6.6 Ascal input geometry

`video_sync.vhd` counts dots at `clk32 / 4` (one dot per `clk_cnt = "00"`) and lines from the VIC-II sync:

| | PAL (`ntsc = '0'`) | NTSC (`ntsc = '1'`) |
|---|---|---|
| Dots per line | 63 x 8 = 504 | 65 x 8 = 520 |
| `hblank` | 1 at dot 489, 0 at dot 107: visible dots 107..488 | 1 at dot 516, 0 at dot 112: visible dots 112..515 |
| Visible width | **382** | **404** |
| Lines per frame | 312 | 263 |
| `vblank` | 1 at line 298, 0 at line 28: visible lines 28..297 | 1 at line 0, 0 at line 13: visible lines 13..262 |
| Visible height | **270** | **250** |
| `vsync_out` | lines 307..310 | lines 0..3 |
| Line rate / frame rate (original clock) | 15.640 kHz / 50.124 Hz | 15.734 kHz / 59.826 Hz |

`CORE/vhdl/test/tb_ntsc/run.sh video` (the real VIC-II through `rtl/video_sync.vhd` in ghdl) confirms every row: PAL 63 x 312, 50.124291 Hz, 382 x 270 visible (VIC `rasterY 17..286`), `hsync_out` 4.821 us; NTSC 65 x 263, 59.826106 Hz at 32 727 273 Hz, 404 x 250 visible (VIC `rasterY 26..262` then `0..12`), `hsync_out` 4.644 us.

Decision: the NTSC blanking constants of MiSTer's `video_sync.vhd` stay as they are. The picture is the 250 visible lines MiSTer shows (`c64.sv`: "NTSC mode has 250 visible lines only!"); there is no additional crop to the roughly 235-line window of a real 6567R8 on a TV.

Ascal measures its input from `i_de = not (hblank or vblank)` and needs no configuration: `IHRES = 1024` covers 404 pixels, and the frame buffer allocation `2**f_log2(G_VGA_DX * G_VGA_DY * 3)` (2 MiB) covers `404 x 250 x 3` bytes. The guard assertion in `mega65.vhd` about the HyperRAM map is unaffected because the allocation does not depend on the input size.

Scale factors, for the record (no code depends on them): 720p window 960 x 720 gives 2.376 x 2.880 in NTSC (PAL 2.513 x 2.667); 480p 4:3 gives 1.782 x 1.920; 480p 5:4 gives 1.782 x 1.804.

Pixel aspect, for the record: a real NTSC TV shows the C64 with a pixel aspect ratio of 0.75; framing 404 x 250 as 4:3 gives 0.825 (PAL: real 0.936, framed 0.942). This is exactly what MiSTer's "Original" aspect (400:300) does in NTSC, so it is the parity choice.

### 6.7 HDMI: Zoom-in in NTSC (`crop.vhd`)

`crop.vhd` hardcodes the PAL position of the 320 x 200 display window inside the 382 x 270 input (`LEFT_BORDER_IN = 33`, `TOP_BORDER_IN = 35`) and keeps 14 / 14 / 4 / 4 border pixels, i.e. it outputs 348 x 208. In NTSC the same 348 x 208 output is kept; only the input position changes.

Derivation of the NTSC position: the VIC-II raises `hBlanking` (our `hsync`) at `rasterX = 396` in both standards, and `rasterX` restarts at 0 in `cycleRefresh3`. The NTSC line is 16 dots longer (`rasterX` runs to 519 instead of 503), so there are 124 instead of 108 dots from `hsync` to the next `rasterX = 0`. The 40-column display window opens at `rasterX = 31`; the pixel pipeline delay (`PIX_DELAY`) is the same in both standards. The window therefore starts 16 dots later after `hsync` in NTSC than in PAL, while `hblank` ends 5 dots later (dot 112 instead of 107). Calibrated against the PAL value: `LEFT_BORDER_IN = 33 + 16 - 5 =` **44** (right border 40). Vertically, `video_sync` restarts its line count at the VIC-II `vSync` line (`rasterY = 300` PAL, `12` NTSC); the 25-row window covers `rasterY 51..250`, i.e. line counts 63..262 in PAL (35 below the first visible line 28, matching `TOP_BORDER_IN = 35`) and 39..238 in NTSC (26 below the first visible line 13), i.e. **`TOP_BORDER_IN = 26`** (bottom border 24). Sum check: 44 + 320 + 40 = 404, 26 + 200 + 24 = 250.

Cross-check with `CORE/vhdl/test/tb_ntsc/run.sh video` (real VIC-II plus `video_sync`): the visible raster box is `rasterY 17..286` in PAL and `rasterY 26..12` (wrapping) in NTSC, and the first visible pixel lies 6 dots before the line wrap in PAL (`rasterX` 498 of 504) and 17 dots before it in NTSC (503 of 520). The window therefore starts 11 dots later in NTSC (33 + 11 = 44) and the 25-row window, which opens at `rasterY 51`, has 34 lines above it in PAL and 25 in NTSC; `crop.vhd` counts `y_count` from 1 on the first visible line (the `vblank` edge clears it at dot 0 and the `hblank` edge of the same line increments it), hence 35 and 26. W2 still confirms both values with a crop bench (10.2 item 5) on a frame with a known border colour.

Interface: `crop` gets a new input `video_ntsc_i : in std_logic` (video clock domain) and selects `X_MIN / X_MAX / Y_MIN / Y_MAX` from two constant sets with it. `crop` is instantiated in `av_pipeline.vhd` (`i_crop`, line 506), which drives the new input with `video_ntsc` (section 6.8); `digital_pipeline` is not involved.

### 6.8 Where the video pipeline learns the standard (`av_pipeline.vhd`)

In the QNICE clock domain of `av_pipeline`:

```vhdl
qnice_ntsc <= '1' when video_mode_is_ntsc(slv_to_video_mode(qnice_video_mode_i)) else '0';
```

`qnice_ntsc` is added as one more bit to the existing QNICE-to-video crossing `i_qnice2video` (`av_pipeline.vhd:269`), giving `video_ntsc` in the video (core) clock domain. `video_ntsc` drives `i_crop.video_ntsc_i` and the VGA OSM scaling force (section 7.4), both inside `av_pipeline.vhd`. In the HDMI domain the standard is already known through `hdmi_video_mode` (crossed by `i_qnice2hdmi`, `av_pipeline.vhd:493`), so no extra bit is needed there.

The bit is quasi-static and changes only together with the mode-change reset, so the existing `xpm_cdc_array_single` (no handshake) is adequate.

### 6.9 Analog path (VGA) in NTSC

Checked files: `analog_pipeline.vhd` (MiSTer `video_mixer` with scandoubler, `csync`), `vga_recover_counters.vhd` (11-bit counters started by DE and sync edges), `vga_osm.vhd`, `video_overlay.vhd` (`vga_row = pix_y` at 31 kHz, `pix_y * 2` at 15 kHz).

- None of them contains a PAL constant; all geometry is recovered from DE / HS / VS. NTSC needs no change in the analog path other than the OSM scaling force of section 7.4.
- Output timings in NTSC: retro 15 kHz modes 15.734 kHz / 59.826 Hz, 404 x 250 visible; "Standard" (scandoubled) 31.469 kHz / 59.826 Hz, 808 x 500 visible. The 31 kHz NTSC mode is within the range of every VGA monitor that accepts 640 x 480 at 60 Hz, which is the use case named in the issue (old 60 Hz-only VGA monitors).
- MiSTer's NTSC `video_sync` starts `vsync_out` on the first line of `vblank` (no vertical front porch, 9 lines back porch). We keep that for parity; it is a hardware test item for 15 kHz CRTs (section 10.4).

---

## 7. OSM geometry in NTSC

### 7.1 Where the OSM is drawn today

- Canvas: `VGA_DX x VGA_DY = 720 x 540` pixels (`globals.vhd`), font 16 x 16, i.e. 45 x 33 character cells (`CHARS_DY = 540 / 16 = 33`).
- Options menu (the "main menu" the user navigates): `OPTM_DX = 25`, `OPTM_DY = 29` net; `getDXDY` (`config.vhd:914`) adds the 2-character frame, so the box is **27 x 31 characters = 432 x 496 pixels**. `SCR$INIT` (`M2M/rom/screen.asm:53-72`) places it top-right: `x = 45 - 27 = 18` characters (pixels 288..719), `y = 0` (pixel rows 0..495).
- Main OSM screen (help pages, file browser, messages): `SHELL_M_DXDY = 45 x 33` characters = 720 x 528 pixels at `(0, 0)`. Help page text ends on character row 30; the file browser lists files on rows 1..31; row 32 is the bottom frame.
- Overlay row computation: `video_overlay.vhd` uses `vga_row = pix_y` at 31 kHz / HDMI and `vga_row = pix_y * 2` in the 15 kHz retro modes; `pix_y = 0` is the first line with DE (`vga_recover_counters.vhd`). HDMI shifts columns by `hdmi_shift = H_PIXELS - 720` (`digital_pipeline.vhd:250`).
- Existing OSM scaling feature (`Advanced Settings > OSM`, `C_MENU_OSM_SCALING`, decoded by `first_nonzero_bit` in `av_pipeline.vhd:436,571`): scaling index `s` in 0..8 renders the box at `8 / (8 + s)` of its size (100 %, 89 %, 80 %, ...) by `row' = row + s * (row - DY * 8) / 8` in `vga_osm.vhd:126-127`, i.e. it shrinks around row `DY * 8` measured from the canvas origin.

### 7.2 Visible OSM rows per output

| Output | OSM rows that reach the screen |
|---|---|
| PAL VGA 31 kHz / 15 kHz | 540 (270 x 2) |
| PAL HDMI 720p / 576p | 720 / 576 |
| NTSC VGA 31 kHz | 500 (250 x 2) |
| NTSC VGA 15 kHz | 250 lines showing the even rows 0..498 |
| NTSC HDMI 720p59.94 | 720 |
| NTSC HDMI 480p59.94 (4:3 and 5:4 items) | 480 |

### 7.3 What would be clipped without a change

Computed with the exact integer arithmetic of `vga_osm.vhd` for every scaling index (`s0` = 100 %):

| Output | Options box 27 x 31 | Main screen 45 x 33 |
|---|---|---|
| NTSC VGA (500 rows), 100 % | fully visible (rows 0..495) | character rows 31 and 32 lost (last file-browser line, bottom frame) |
| NTSC VGA, 89 % or smaller | fully visible | fully visible (rows 29..498 at 89 %) |
| NTSC HDMI 480p, 100 % | character row 30 lost (bottom frame) | character rows 30..32 lost (help text "Press Space ...", last browser line, frame) |
| NTSC HDMI 480p, 89 % | fully visible (rows 27..468) | character rows 31 and 32 lost: shrinking centers on row 264, which is below the screen center 240 |
| NTSC HDMI 480p, 89 % and 24 rows up | fully visible (rows 3..444) | fully visible (rows 5..474) |

The 24-row upward shift together with a minimum of 89 % keeps both boxes fully visible for every user scaling index from 1 to 8.

### 7.4 Specified change (W2 only, no Shell and no `config.vhd` change)

1. **VGA in NTSC:** the effective scaling index of the analog pipeline is `max(s_user, 1)`. In `av_pipeline.vhd` replace `video_osm_cfg_scaling_i => first_nonzero_bit(video_osm_cfg_scaling)` by `video_osm_cfg_scaling_i => osm_scaling(video_osm_cfg_scaling, video_ntsc)`, with the new local function

   ```vhdl
   -- OSM scaling index; force at least index 1 (89 %) when the output has fewer than 540 OSM rows
   pure function osm_scaling(arg : std_logic_vector; force_min : std_logic) return natural is
      variable s : natural := first_nonzero_bit(arg);
   begin
      if force_min = '1' and s = 0 then
         return 1;
      end if;
      return s;
   end function osm_scaling;
   ```

2. **HDMI 480p in NTSC:** `hdmi_osm_ntsc480 <= '1' when slv_to_video_mode(hdmi_video_mode) = C_VIDEO_HDMI_4_3_5994 or slv_to_video_mode(hdmi_video_mode) = C_VIDEO_HDMI_5_4_5994 else '0';` (HDMI clock domain, `av_pipeline.vhd`), then `hdmi_osm_cfg_scaling_i => osm_scaling(hdmi_osm_cfg_scaling, hdmi_osm_ntsc480)`.
3. **Vertical shift for HDMI 480p in NTSC:** `video_overlay.vhd` gets a new input `vga_cfg_vshift_i : in natural := 0` and computes `stage1.vga_row <= to_integer(stage1.vga_pix_y) + vga_cfg_vshift_i` (31 kHz / HDMI) and `to_integer(stage1.vga_pix_y) * 2 + vga_cfg_vshift_i` (15 kHz). `digital_pipeline.vhd` drives it with `24 when hdmi_video_mode_i = C_VIDEO_HDMI_4_3_5994 or hdmi_video_mode_i = C_VIDEO_HDMI_5_4_5994 else 0`; the analog instance keeps the default `0`.
4. 720p59.94 and all PAL modes are unchanged (no force, no shift).

The font and the canvas stay as they are; the glyphs are rendered by the same scaler a user gets with "OSM: 89%". Known cosmetic effect: in NTSC on VGA and on 480p the OSM appears at 89 % while the OSM submenu still shows the user's setting (100 %). The Shell does not need to know the standard.

---

## 8. Reset on mode change

### 8.1 Requirements

- Every change of `c64_ntsc_i` (PAL to NTSC or back), whatever its cause (user selection, config-file restore after power-on), soft-resets the C64 exactly once, so that the KERNAL re-runs its PAL/NTSC detection (`$02A6`) under the new VIC-II and the new clock.
- The pulse is at least 32 main clock cycles long (RESET SEMANTICS, `main.vhd:717`).
- The reset must never be lost. A soft reset that arrives while `prevent_reset = '1'` (a virtual drive has a dirty write cache, `main.vhd:970`) is silently ignored by `hard_reset_proc` today; for the mode change that would leave the KERNAL in the wrong region. The mode-change reset is therefore **deferred** until `prevent_reset = '0'`. For the same reason a pulse that is already running when `prevent_reset` rises is **aborted and re-armed**: `hard_reset_proc` releases `reset_core_int_n` as soon as `prevent_reset = '1'`, so the C64 would otherwise see only a few cycles of reset (fewer than the 32 cycles of one 1 MHz CPU enable period) and keep the old region flag.
- It behaves like the other OSM-driven soft resets (kernal swap, expansion-port toggle via `RESET_CORE` / `M2M$CSR_RESET`): it resets the C64 through `reset_core_n`, it starts cartridges (soft-reset semantics), and it re-initializes the simulated-cartridge cache through `cart_soft_reset_o`.

### 8.2 Mechanism (all in `main.vhd`, main clock domain, owner W3)

New declarations:

```vhdl
-- Mode-change reset (issue #181): PAL <-> NTSC switches re-run the KERNAL's region detection.
-- C_MODE_RST_LEN must be >= 32 (RESET SEMANTICS) and long enough to cover the clock switch in
-- clk.vhd (a few hr_clk cycles, below 1 us); 1024 cycles = 31 us.
constant C_MODE_RST_LEN    : natural := 1024;
signal   ntsc_d            : std_logic := '0';   -- power-on standard is PAL
signal   mode_rst_pending  : std_logic := '0';
signal   mode_rst_counter  : natural range 0 to C_MODE_RST_LEN := 0;
signal   mode_reset        : std_logic;
```

New process:

```vhdl
mode_change_reset_proc : process (clk_main_i)
begin
  if rising_edge(clk_main_i) then
    ntsc_d <= c64_ntsc_i;
    if ntsc_d /= c64_ntsc_i then
      mode_rst_pending <= '1';
    end if;

    if mode_rst_counter /= 0 then
      if prevent_reset = '1' then
        -- a write-back started inside the pulse: abort it and retry afterwards
        mode_rst_counter <= 0;
        mode_rst_pending <= '1';
      else
        mode_rst_counter <= mode_rst_counter - 1;
      end if;
    elsif mode_rst_pending = '1' and prevent_reset = '0' then
      mode_rst_counter <= C_MODE_RST_LEN;
      mode_rst_pending <= '0';
    end if;
  end if;
end process mode_change_reset_proc;

mode_reset <= '1' when mode_rst_counter /= 0 else '0';
```

The re-arm covers a narrow but real window: a drive asserts `sd_wr`, the Shell has not acknowledged it yet (`cache_dirty = 0`, so `prevent_reset = 0`), the user switches the standard and the pulse starts; the Shell's `HANDLE_IO` then acknowledges the write inside the 31 us of the pulse and `prevent_reset` rises. The short reset that `hard_reset_proc` has already passed on before the abort is the same as for every other soft reset that meets a rising `prevent_reset`; the complete pulse follows when the write-back is done. `tb_mode_reset.vhd` case 6 checks exactly this sequence.

Joins the existing reset paths:

1. `hard_reset_proc` (`main.vhd:1046`): the condition `if reset_soft_i = '1' or reset_hard_i = '1' or cart_reset_counter /= 0 then` gets `or mode_reset = '1'`. Inside that branch nothing changes: `reset_core_int_n <= prevent_reset and (not reset_hard_i)` drives `reset_core_n` low, and `hard_reset_n` is untouched (a mode change is not a hard reset). Add `hard_reset_proc` to the list of processes that "know what they are doing" only in the sense that it now also reads `mode_reset`; `mode_change_reset_proc` itself reads `prevent_reset`, not `reset_soft_i` / `reset_hard_i`, so the RESET SEMANTICS rule is respected.
2. `cart_soft_reset` (`main.vhd:971`): `cart_soft_reset <= (cart_soft_reset_i or mode_reset) and not prevent_reset;` so that `sw_cartridge_wrapper` re-initializes the cacher like after any OSM-driven soft reset.
3. Hardware cartridges see the reset on `/RESET` automatically, because `cart_reset_o` follows `reset_core_int_n` (`main.vhd:1467`).
4. `reset_core_n` also resets the simulated drives, the same consumers as the reset button. The drive chip enable `iec_drive_ce_proc` runs freely and is not reset (section 5.3).
5. Extend the RESET SEMANTICS comment block: "a fourth source of soft resets is the mode-change reset (`mode_change_reset_proc`, 1024 cycles, deferred while `prevent_reset = '1'`, aborted and re-armed when `prevent_reset` rises during the pulse)".

`mega65.vhd` needs nothing for the reset: the change of `main_osm_control_i(C_MENU_MACHINE_NTSC)` reaches `main.vhd` through `c64_ntsc_i`. `qnice_reset_for_prgloader` is not extended: a mode change while a PRG is being injected is not a supported combination, and the PRG loader keeps its own hard reset.

### 8.3 Timing of a mode change

1. The Shell writes the new OSM state; the framework crosses it into the main clock domain.
2. Same main clock cycle: `c64_ntsc` changes, the VIC-II switches to 6567R8 (or back), `c64_clock_speed` changes.
3. One cycle later: `mode_rst_pending = '1'`; next cycle (if no write-back is pending) `mode_reset` rises for 1024 cycles.
4. In parallel, a few `hr_clk` cycles later, `hr_core_speed(1)` flips and the BUFGCTRL tree switches to the clock of the new standard, glitch-free, well inside the reset window.
5. In parallel, in the QNICE domain, `qnice_video_mode_o` switches to the HDMI mode of the new standard; `video_out_clock` reprograms its MMCM and the display resynchronizes (a short blank screen, as with any HDMI mode change in the menu).
6. After the reset, the KERNAL boots, measures the raster line count and sets `$02A6` (0 = NTSC, 1 = PAL).

If a write-back is pending, or starts while the pulse of step 3 runs (the pulse is then aborted and re-armed), steps 3 and 6 happen after the write-back finished; during that window the C64 keeps running with the new VIC-II and the new clock and the old region flag. That is harmless (the next step is the reset); a disk write in progress continues correctly because the drives keep their exact 1 MHz.

### 8.4 Power-on with a saved NTSC setting

The Shell restores the config file while the C64 is still held in reset:

- `CSR_DEFAULT = x"0839"` (`M2M/vhdl/QNICE/qnice.vhd`) has bit 0 (`csr_reset_o`) set, so the core is in reset when the Shell starts.
- `shell.asm` calls `HELP_MENU_INIT` before `RP_SYSTEM_START`. `HELP_MENU_INIT` (`options.asm`) waits for the SD card (`WAIT_FOR_SD`, at least `SD_WAIT` = 2 s), loads the config file and writes `M2M$CFM_DATA`.
- Only then does `RP_SYSTEM_START` release the reset (`gencfg.asm`, `AND M2M$CSR_UN_RESET`).

So `c64_ntsc_i` goes to `'1'` while the C64 is still in reset. Because `ntsc_d` starts as `'0'`, this is an ordinary mode change for `mode_change_reset_proc`: steps 2 to 5 happen, and the 1024-cycle pulse falls inside the reset that the Shell holds anyway, where it is harmless. The first KERNAL boot (step 6) is already NTSC; no PAL boot screen and no second reset are visible. The same holds after a long press of the reset button, which restarts the Shell with `CSR_DEFAULT`.

---

## 9. Interface contract for the implementation workers

### 9.1 Ownership

| Worker | Owns (writes) | Must not touch |
|---|---|---|
| W1 clocks and switching | `CORE/vhdl/clk.vhd`, `CORE/CORE.xdc`, `CORE/vhdl/globals.vhd`, `CORE/vhdl/mega65.vhd`, and `CORE/signoff_gates.tcl` (the sign-off gates mirror CORE.xdc and must change in the same commit, section 3.8) | everything else |
| W2 video | `M2M/vhdl/av_pipeline/*`, `M2M/vhdl/controllers/HDMI/*`, `M2M/vhdl/framework.vhd`, `M2M/vhdl/hdmi_flicker_free.vhd`, `M2M/common.xdc` (no change expected) | everything else, in particular the four `M2M/vhdl/top_mega65-r?.vhd` |
| W3 core and docs | `CORE/vhdl/main.vhd`, `CORE/vhdl/config.vhd` (comments and help text only), `CORE/m2m-rom/*.asm` and `M2M/rom/*.asm` (no change expected), all documentation, `tests/README.md` | everything else |

Nobody changes the submodule `CORE/C64_MiSTerMEGA65`, the top-level files, `OPTM_ITEMS` / `OPTM_GROUPS` structure, `OPTM_SIZE`, `OPTM_DX` / `OPTM_DY`, or any `C_MENU_*` index.

### 9.2 Items that cross an ownership boundary

| # | Name | Type | Direction / use | Clock domain | Owner | Consumer | Value / semantics |
|---|---|---|---|---|---|---|---|
| 1 | `CORE_CLK_SPEED_NTSC` | `constant natural` in `globals.vhd` | read | n/a | W1 | W1 (`mega65.vhd`) | `32_727_273` (was `32_727_264`) |
| 2 | `CORE_CLK_SPEED_PAL` | `constant natural` | read | n/a | W1 | W1 | `31_527_778`, unchanged |
| 3 | `CORE_CLK_SPEED` | `constant natural` | read | n/a | W1 | W2 (`framework.vhd:550,602`), `prg_loader.vhd` | stays `CORE_CLK_SPEED_PAL` |
| 4 | `main.c64_ntsc_i` | existing port `std_logic` | in to `main` | main clock | W1 drives, W3 consumes | `main.vhd` | `main_osm_control_i(C_MENU_MACHINE_NTSC)`: 0 = PAL, 1 = NTSC |
| 5 | `main.clk_main_speed_i` | existing port `natural` | in to `main` | main clock | W1 drives, W3 consumes | `main.vhd` | `CORE_CLK_SPEED_NTSC` when NTSC else `CORE_CLK_SPEED_PAL`, never a flicker-free value |
| 6 | `main.cart_soft_reset_o` | existing port `std_logic` | out of `main` | main clock | W3 | W1 (`mega65.vhd` to `sw_cartridge_wrapper`, unchanged wiring) | now also pulses with `mode_reset` |
| 7 | `video_mode_type` members `C_VIDEO_HDMI_16_9_5994`, `C_VIDEO_HDMI_4_3_5994`, `C_VIDEO_HDMI_5_4_5994` | enum literals in `video_modes_pkg.vhd`, appended at the end | W1 assigns them to `qnice_video_mode_o` | QNICE | W2 | W1 | section 6.1 |
| 8 | `video_mode_to_slv` / `slv_to_video_mode` codes | 4-bit | | | W2 | W2 | `"0111"`, `"1000"`, `"1001"` for the three members; existing codes unchanged |
| 9 | `video_mode_is_ntsc` | `pure function (video_mode_type) return boolean` in `video_modes_pkg.vhd` | | | W2 | W2 (W1 may use it) | true for the three members of item 7 only |
| 10 | `C_HDMI_720p_5994` | `constant video_modes_t` in `video_modes_pkg.vhd` | | | W2 | W2 | section 6.1 |
| 11 | `MEGA65_Core.qnice_video_mode_o` | existing port `video_mode_type` | out of `MEGA65_Core` | QNICE | W1 | W2 (via unchanged top-level wiring) | Invariant: a `*_5994` member of item 7 if and only if `qnice_osm_control_i(C_MENU_MACHINE_NTSC) = '1'` (section 4.3) |
| 12 | `MEGA65_Core.hr_low_i` / `hr_high_i` | existing ports `std_logic` | in to `MEGA65_Core` | `hr_clk` | W2 (`hdmi_flicker_free.vhd`) | W1 | Unchanged: `hr_low_i = '1'` = core too slow, `hr_high_i = '1'` = core too fast. W2 keeps `hdmi_flicker_free.vhd` and its thresholds as they are. |
| 13 | `C_MENU_MACHINE_NTSC = 39`, `C_MENU_HDMI_FF = 64`, `C_MENU_HDMI_FF_NTSC = 65`, `C_MENU_HDMI_16_9_5994 = 58`, `C_MENU_HDMI_4_3_5994 = 60`, `C_MENU_HDMI_5_4_5994 = 62` | constants in `mega65.vhd` | | | W1 | W1 | values fixed by `config.vhd` (W3), which must not move any menu item |

Items that stay inside one worker and need no coordination, listed so that the names are fixed:

- W1, `clk.vhd`: port list unchanged (`sys_clk_i`, `core_speed_i : unsigned(1 downto 0)`, `main_clk_o`, `main_rst_o`); new instances `i_clk_c64_ntsc`, `i_clk_c64_ntsc_ff`, `bufgmux_ntsc_inst`, `bufgmux_mode_inst`; `bufgmux_ctrl_inst` renamed `bufgmux_pal_inst`; encoding of section 3.5.
- W1, `mega65.vhd`: `c64_ntsc`, `c64_clock_speed`, `main_hdmi_ff`, `hr_ntsc`, `hr_hdmi_ff`, `hr_core_speed` (with `dont_touch`), `i_cdc_main2hr` with `G_DATA_SIZE => 2`.
- W2, `crop.vhd`: new port `video_ntsc_i : in std_logic` (video clock domain); NTSC constants `LEFT_BORDER_IN = 44`, `TOP_BORDER_IN = 26`, to be confirmed in simulation (section 6.7).
- W2, `digital_pipeline.vhd`: new mode rows and assertions (6.3); `vga_cfg_vshift_i` of its `i_video_overlay` driven for the 480p NTSC modes (7.4). No new port.
- W2, `video_overlay.vhd`: new port `vga_cfg_vshift_i : in natural := 0`.
- W2, `av_pipeline.vhd`: `qnice_ntsc`, `video_ntsc` (`i_qnice2video` grows from `WIDTH => 46` to `47`, new bit 46), `hdmi_osm_ntsc480`, function `osm_scaling` (7.4).
- W2, `framework.vhd`: `VIDEO_MODE_VECTOR(0 to 9)` and the clock-select decode (6.2).
- W3, `main.vhd`: `C_MODE_RST_LEN`, `ntsc_d`, `mode_rst_pending`, `mode_rst_counter`, `mode_reset`, `mode_change_reset_proc` (section 8); `video_sync_inst.ntsc => c64_ntsc_i`; `rtcf83_inst` with `CLOCK_RATE => 16_000_000`, `ce => iec_drive_ce`.

### 9.3 Things each worker can rely on without talking to the others

- W1 can code `qnice_video_mode_o` against the three new literal names before W2 has added them; the build only links once both are in.
- W2 can rely on item 11: whenever it sees a `*_5994` mode, the C64 runs NTSC; whenever it sees a `*_50` mode, PAL.
- W3 can rely on `c64_ntsc_i` changing only through the OSM (no glitches; it is a registered OSM bit) and on `clk_main_speed_i` always matching the standard on `c64_ntsc_i` in the same clock cycle.
- Nobody needs a Shell change: `SUBMENU_SUMMARY` already handles PAL/NTSC, and the OSM dependency feature (`OPTM_DEP(OPTM_G_MACHINE_MODE, …)`) already shows only the HDMI items of the active standard.

---

## 10. Verification plan

Tools: ghdl 5.1.1 (`ghdl -a --std=08 -frelaxed`, add `-fsynopsys` for the MiSTer RTL), iverilog for SystemVerilog-free Verilog only, Python 3. Vendor primitives (`MMCME2_ADV`, `BUFGCTRL`, `xpm_*`) come from the stub packages in `doc/dev-ntsc/tools/stubs/`. The differential analyzer `doc/dev-ntsc/tools/analyze.sh` (HEAD versus working tree, `--ntsc-set` for all files of this spec) and the benches in `CORE/vhdl/test/tb_ntsc/` (`run.sh video`, `run.sh dividers`) are the shared harness. Use at most the `JOBS` value given in the worker brief.

### 10.1 W1 (clocks and switching) must prove before reporting

1. `python3 doc/dev-ntsc/tools/ntsc_clocks.py --final` reproduces the table of section 3.3, and the generics in `clk.vhd` are character-for-character the values of that table.
2. `analyze.sh CORE/vhdl/globals.vhd CORE/vhdl/clk.vhd CORE/vhdl/mega65.vhd` passes.
3. A ghdl bench of the `hr_core_speed` process (copy the process into a small bench entity, drive `hr_ntsc`, `hr_hdmi_ff`, `hr_low_i`, `hr_high_i`) shows: PAL `low -> "00"`, `high -> "01"`; NTSC `low -> "11"`, `high -> "10"`; flicker-free off gives `"00"` / `"10"`; holding neither input keeps the value.
4. A closed-loop model (`doc/dev-ntsc/tools/ff_model.py` or equivalent): core frame phase versus HDMI frame phase with the thresholds `0x1000` / `0x2000`, the four frequencies of section 3.3 and the switching rule of item 3, for 720p50, 576p50, 720p59.94 and 480p59.94, from several start phases. It must lock (no phase run-away) and reproduce the duty cycles of section 3.3 (99.2 % PAL, 99.86 % 480p, 93.4 % 720p on the flicker-free leg). Commands: `python3 doc/dev-ntsc/tools/ff_model.py` (built-in PAL validation plus NTSC candidates) and `python3 doc/dev-ntsc/tools/ff_model.py --clocks 32727272.727 32789699.571 --geom 65x263 --visible 404x250 --hdmi 59.940060` (and `--hdmi 59.932660`).
5. A ghdl run of `clk.vhd` with behavioral stubs: switching `core_speed_i` through all four codes produces a clock of the expected period at `main_clk_o` (stub-level check of the mux wiring, not of glitch freedom).

### 10.2 W2 (video) must prove before reporting

1. `analyze.sh --ntsc-set` passes for every W2 file.
2. Package bench: `slv_to_video_mode(video_mode_to_slv(m)) = m` for every member; the three new codes are `"0111"`, `"1000"`, `"1001"`; `video_mode_is_ntsc` is true for exactly the three new members.
3. Elaboration of `framework` (or at least `av_pipeline` with a 10-entry `G_VIDEO_MODE_VECTOR`) without assertion failures.
4. A bench of the `digital_pipeline` window expressions (or a Python transcription of them) prints `hmin/hmax/vmin/vmax` for all ten modes with and without zoom and matches section 6.3 (160/1119/0/719, 0/719/0/479, 0/719/15/465).
5. Crop: a ghdl bench that feeds `crop` with the NTSC `video_sync` output of `tb_video_sync_geometry` (real VIC-II, a screen with a known border colour) confirms `LEFT_BORDER_IN = 44` and `TOP_BORDER_IN = 26` (the 320 x 200 window starts at visible pixel 44 and line 26) and an output of 348 x 208 in both standards; PAL must still give 33 / 35.
6. OSM: a bench (or Python transcription of `vga_osm.vhd:120-127` plus the new `vga_cfg_vshift_i`) reproduces the table of section 7.3 for `s = 0..8`.
7. `C_HDMI_720p_5994`: `htotal x vtotal = 1650 x 750` and `CLK_KHZ = 74167`.

### 10.3 W3 (core and docs) must prove before reporting

1. `analyze.sh CORE/vhdl/main.vhd CORE/vhdl/config.vhd` passes.
2. `CORE/vhdl/test/tb_ntsc/run.sh video`: with `ntsc = '1'` the `video_sync` output has 404 x 250 visible pixels, 520 dots per line, 263 lines, and the PAL figures (382 x 270) are unchanged.
3. `CORE/vhdl/test/tb_ntsc/run.sh dividers`: TOD exactly 60 Hz and drive CE exactly 16 MHz at `CORE_CLK_SPEED_NTSC = 32_727_273`, 50 Hz / 16 MHz in PAL, and the documented drift in the flicker-free legs.
4. A ghdl bench of `mode_change_reset_proc` (copied into a bench entity with `c64_ntsc_i`, `prevent_reset`): one toggle gives exactly one `mode_reset` pulse of 1024 cycles; a toggle while `prevent_reset = '1'` gives the pulse after `prevent_reset` falls; two toggles during one `prevent_reset` window give one pulse; `prevent_reset` rising during a running pulse stops it, and one complete 1024-cycle pulse (on `mode_reset` and on `reset_core_int_n`) follows after `prevent_reset` falls; no pulse at power-on with `c64_ntsc_i = '0'`.
5. `rtcF83.sv` with `CLOCK_RATE 16000000` and `ce` at 16 MHz advances one second per 16 000 000 `ce` pulses (iverilog or a Python transcription of `rtcF83.sv:142-146`).
6. `python3 M2M/rom/tests/menu_test.py verify` still passes (proves that no menu index moved).
7. Markdown files pass the Marked 2 / MathJax rules (no bare `$` pairs, no bare `==`).

### 10.4 Only Vivado can check (W1 runs it if a Vivado installation is available, otherwise the maintainer)

- `build_all.sh` for R3 and R6 at least: WNS and WHS at or above 0 with `main_clk` at 30.497 ns; `signoff_gates.tcl` passes; `report_clocks` lists `main_clk` with period 30.497 ns sourced from `i_clk_c64_ntsc_ff/CLKOUT0`.
- `report_clock_interaction`: no new "Timed (unsafe)" or "Partial False Path (unsafe)" entry involving `main_clk`.
- `report_utilization`: 6 MMCME2_ADV, 13 BUFGCTRL (R6), no new DRC warnings about cascaded BUFGCTRL placement.
- `report_clock_utilization` on R3 and R6: the BUFGCTRL tree (`bufgmux_pal_inst`, `bufgmux_ntsc_inst`, `bufgmux_mode_inst`) is placed without warnings, the four core MMCMs sit in the half of the device that holds these BUFGCTRLs, and no clock is routed through general interconnect. `clk.vhd` cascades three buffer levels (the two standard muxes, `bufgmux_mode_inst`, `main_clk_bufg`); `opt_design` removes `main_clk_bufg` as a redundant cascaded buffer (`[Opt 31-274]`, as in the PAL-only R6 build, where `main_clk` is driven directly from the mux), which leaves two levels on the dedicated paths between adjacent BUFGCTRLs. If the placer complains about the cascade anyway, the expected remedy is to delete `main_clk_bufg` and drive `main_clk_o` from `bufgmux_mode_inst`; `CORE.xdc` and the sign-off gates reference the MMCM pin, not the buffer. The same report shows whether a spare CMT is left in that half for the fifth MMCM of risk 7.
- The four MMCMs lock (ILA or the existing power-on behavior).
- The HyperRAM RWDS hold knife-edge (issue #224) is unaffected or handled by the re-roll.

### 10.5 Only hardware can check (`tests/README.md`)

W3 prepends a section `Version WIP-V6-A22 - TBD` above `Version WIP-V6-A21 - TBD` with these `@TODO` items (R3 and R6 at least):

1. PAL regression: power-on in PAL, all three PAL HDMI modes, flicker-free on and off, VGA Standard and both 15 kHz modes, the usual demo set; nothing may differ from WIP-V6-A21.
2. Switch to NTSC in `Model`: automatic reset, `PRINT PEEK(678)` (`$02A6`) prints 0; back to PAL prints 1; the HDMI submenu shows only the items of the active standard.
3. NTSC on HDMI: `16:9 720p 59.94 Hz`, `4:3 480p 59.94 Hz`, `5:4 480p 59.94 Hz`; the display reports 59.94 Hz (720p shows as 59.93 Hz on displays that print two decimals); HDMI audio has no periodic dropouts over 10 minutes in each mode.
4. NTSC on VGA: Standard (31.47 kHz, 59.83 Hz) on a 60 Hz-only VGA monitor; 15 kHz HS/VS and CSYNC on a CRT or a 15 kHz-capable display (watch vertical sync stability, MiSTer's NTSC sync has no vertical front porch).
5. OSM in NTSC: the whole options menu, a help page and the file browser fully visible on VGA (31 kHz and 15 kHz), on 720p59.94 and on both 480p items, at OSM scaling 100 % and 50 %.
6. Flicker-free toggle in NTSC (`HDMI: Flicker-free` NTSC twin): with it on, smooth horizontal scrolling (for example the Ballblazer or Skate or Die intro) has no periodic stutter; with it off, a stutter about every 9 s is expected (59.826 Hz content on 59.94 Hz output).
7. The Discord programs in NTSC: Ballblazer (60 Hz motion), M.U.L.E. (music tempo), Impossible Mission (speech pitch and speed), Maniac Mansion (aspect, music), Skate or Die (sampled intro), Beachhead (score-line raster glitch reported by KeithHenrickson-Retro in PAL: check that the score line is stable in NTSC). Plus the PAL re-check of issue #2 and of the programs from issue #2 in PAL, as requested in the issue.
8. 1541 loading in NTSC: a D64 with the standard loader, a fastloader game, and `SAVE` to a D64 (also with flicker-free on); the same with a D81 on the simulated 1581.
9. TOD accuracy in NTSC: with `HDMI: Flicker-free` off for the standard under test, set the TOD clock (CIA1 `$DC08-$DC0B`, 60 Hz bit in `$DC0E` as the program expects), let it run 10 minutes against a stopwatch: deviation below 1 s. Repeat in PAL. With flicker-free on (the default) the expected drift is about +1.1 s per 10 minutes in NTSC (+0.1907 % on the fast leg for 99.86 % of the time at 480p, 93.4 % at 720p) and about -1.5 s per 10 minutes in PAL (-0.2499 % for 99.23 % of the time), by design, because flicker-free shifts the whole machine and TOD divides by the nominal `clk32_speed`.
10. JiffyDOS in NTSC: JiffyDOS KERNAL (`Kernal > JiffyDOS`) with JiffyDOS 1541 ROM; `@$` and a JiffyDOS load.
11. Config-file persistence: select NTSC, save settings, power cycle: the core starts directly in NTSC, without a PAL boot screen (`PRINT PEEK(678)` prints 0); the HDMI mode and the NTSC flicker-free setting are restored.
12. GEOS real-time clock in NTSC (`RTC` on): GEOS shows the correct time after 10 minutes.
13. Mode change while a D64 write-back is pending (`<Saving>` shown): the reset happens after the write-back and the image on the SD card is intact.
14. Hardware cartridge in NTSC (an EF3 menu, a 1541 Ultimate II+ or similar): the cartridge starts after the automatic reset.
15. HyperRAM bandwidth on R3/R3A (risk 4 of section 11): NTSC, `16:9 720p 59.94 Hz`, flicker-free on, simulated REU on; a REU-heavy demo for 10 minutes, a bank-switching EasyFlash `.crt` from the SD card for 10 minutes, and the Final Cartridge III freezer with simulated REU (`doc/issue_214_simreu_hyperram.md`): no picture tearing, no REU errors, no cartridge hangs, flicker-free stays locked. The same with `4:3 480p 59.94 Hz`.

---

## 11. Risks and mitigations

Ordered by rating (highest first).

| # | Risk | Rating | Mitigation |
|---|---|---|---|
| 1 | **Flicker-free polarity in NTSC.** The original clock is the slow one in NTSC; reusing the PAL rule makes the core drift away from the HDMI rate and the frame buffer tear permanently. | high impact, easy to get wrong | Section 4.2 gives the exact process; W1 proves it with the bench and the closed-loop model of 10.1 items 3 and 4. |
| 2 | **Lost mode-change reset.** A soft reset during `prevent_reset = '1'` is silently ignored today; a lost mode-change reset leaves the KERNAL with the wrong region flag. | medium | Deferred and re-armed reset of section 8; W3 bench 10.3 item 4; hardware test 10.5 item 13. |
| 3 | **Crop constants for NTSC zoom-in** are derived from the RTL and from the visible raster box of the video bench, not yet from a crop bench. | low (cosmetic if wrong: a shifted zoom window) | W2 confirms them in simulation (10.2 item 5) before reporting. |
| 4 | **HyperRAM bandwidth on R3/R3A.** The ascal input grows from 382 x 270 x 50.12 Hz (5.17 Mpixel/s) to 404 x 250 x 59.83 Hz (6.04 Mpixel/s), +17 % for writes and about the same for reads at 59.94 Hz output, on top of SIMCRT bank fills and SIMREU DMA (+3.8 % with the faster C64). | medium | No design change; hardware test on R3 with SIMREU (a REU-heavy demo) and a bank-switching `.crt`, plus 720p59.94 and 480p59.94 with flicker-free on (10.5 item 15). R4 and later keep the ascal frame buffer in SDRAM (`framework.vhd:973`, `sdram_gen` is HyperRAM only for `MEGA65_R3`), so there the contention does not grow; `hdmi_flicker_free.vhd` taps the same `hr_dig_*` bus on every board, so flicker-free works on both paths. |
| 5 | **Timing closure at 32.79 MHz** (period 30.497 ns instead of 31.718 ns, -1.221 ns). | low | The current routed reports show main_clk intra-clock WNS of 9.001 ns (R6) and 10.704 ns (R3), and every main_clk crossing is a `-datapath_only` max-delay (8 ns / 2 ns) or a false path, which does not depend on the period. Section 3.8 times the fastest clock, so there is no hidden slower-clock path. The HyperRAM RWDS hold knife-edge (issue #224) is unrelated to main_clk and stays with the re-roll flow. |
| 6 | **XDC case-analysis pins renamed by synthesis.** If `hr_core_speed_reg[1]` disappears, Vivado silently times all four clocks against each other or none at all. | low | `dont_touch` on `hr_core_speed` (3.8), and the extended `signoff_gates.tcl` refuses the bitstream if a pin or the 30.497 ns period is missing. |
| 7 | **720p59.94 pixel clock is 74.1667 MHz** (-123.5 ppm). With flicker-free on, 720p switches between the clocks every 3.4 s (0.2 s at 3.3 cents lower pitch); with the wrong `CLK_KHZ` the HDMI audio would drift. | low | `CLK_KHZ = 74167` (6.1). The pitch dip is below audibility; if hardware tests disagree, a fifth MMCM between 59.9327 and 59.9401 Hz for 720p only is the follow-up, not part of this alpha. |
| 8 | **480p display compatibility.** `C_HDMI_720x480p_5994` has never been used by this core in the field. | low to medium | Hardware test 10.5 item 3 on more than one display. The record follows CTA-861 (VIC 2, 858 x 525, negative syncs). |
| 9 | **Cascaded BUFGCTRL.** Two levels of glitch-free muxes plus the existing BUFG. | low | All four inputs run continuously; the 7-series clock architecture supports BUFGCTRL cascades. Vivado DRC and placement (10.4) must be clean. |
| 10 | **MMCM and BRAM budget.** | low | +2 MMCM (6 of 10), +2 BUFGCTRL (13 of 32), no BRAM. |
| 11 | **Audio resampling tied to the core clock.** | none found | Audio crosses into `audio_clk` by level sampling (`framework.vhd`), HDMI audio runs from `audio_clk` (12.288 MHz); no consumer depends on the core clock (5.5 row 9). |
| 12 | **OSM looks smaller in NTSC on VGA and 480p** (89 %). | cosmetic | Documented in 7.4; the alternative would be a smaller font or a shorter menu, both excluded by the scope. |
| 13 | **`first_nonzero_bit` returns 9 for an all-zero scaling vector**, outside `natural range 0 to 8`. Pre-existing. | low | `osm_scaling` keeps the existing behavior; not to be fixed in this alpha. |

---

## 12. Open questions for the maintainer

None of the decisions in this specification depends on an open question; the implementation can proceed as written. The following points are design choices the maintainer may want to revisit after the first hardware round, without making the work wrong:

1. NTSC flicker-free leg at +2.72 ppm above 59.94 Hz (section 3.3). Alternatives with more margin: +7.46 ppm (`22.625 / 2 / 34.5`) or +27.9 ppm (`55.375 / 7 / 24.125`); only the `clk.vhd` generics and the period expected by `signoff_gates.tcl` would change.
2. OSM forced to at least 89 % (and 24 rows up on 480p) in NTSC (section 7.4) versus accepting a clipped bottom frame line.

