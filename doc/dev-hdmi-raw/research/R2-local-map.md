# HDMI raw mode: map of the existing clocking and video path

This map describes the state of branch `mh_implement_184` (commit `669e75d`) as far as it concerns a third HDMI timing choice "Raw" (issues #148 and #184): the C64 runs at its original speed and the HDMI output runs at the C64's own frame rate. Every statement carries a `file:line` reference. Clock and frame-rate fractions are exact (computed with rational arithmetic from the MMCM parameters in the source). Resource counts come from the routed Vivado reports of 2026-11-19 in `CORE/CORE-R3.runs/impl_1/` and `CORE/CORE-R6.runs/impl_1/`.

## 0. Key facts

| Item | Value |
|---|---|
| Core frame, PAL 6569 | 63 x 312 x 32 = 628 992 `clk_main` cycles |
| Core frame, NTSC 6567R8 | 65 x 263 x 32 = 547 040 `clk_main` cycles |
| PAL original clock | 283 750 000 / 9 Hz = 31.527 778 MHz, frame rate 17 734 375 / 353 808 Hz = 50.124 290 576 Hz |
| PAL flicker-free clock | 48 400 000 000 / 1539 Hz = 31.448 993 MHz, 189 062 500 / 3 781 323 Hz = 49.999 034 729 Hz |
| NTSC original clock | 360 000 000 / 11 Hz = 32.727 273 MHz, 2 250 000 / 37 609 Hz = 59.826 105 453 Hz |
| NTSC flicker-free clock | 7 640 000 000 / 233 Hz = 32.789 700 MHz, 47 750 000 / 796 627 Hz = 59.940 222 965 Hz |
| HDMI frame rates today | 576p50 and 720p50: 50 Hz exactly; 480p59.94: 60000/1001 Hz; 720p59.94: 17800/297 Hz = 59.932 660 Hz |
| Clock resources (R3 and R6) | MMCM 6 of 10, PLL 1 of 10, BUFGCTRL 13 of 32 |
| HDMI pixel clock tables | 8 slots (`CLK_SEL` 3 bits), all 8 occupied |
| HDMI audio clock regeneration | `N` = 6144 fixed, `CTS` = `CLK_KHZ` of the mode record |
| STA of the HDMI domain | `hdmi_clk` at 13.468 ns (74.25 MHz), `tmds_clk` at 2.694 ns, from the MMCM's static attributes |
| ascal buffering | single frame buffer (MODE bit 3 = 0): a rate mismatch shows as a tear line that crosses the picture |

## 1. Core clocks (`CORE/vhdl/clk.vhd`)

### 1.1 The four MMCMs

All four are `MMCME2_ADV`, `CLKIN1_PERIOD => 10.0`, `BANDWIDTH => "OPTIMIZED"`, `COMPENSATION => "ZHOLD"`, feedback `CLKFBOUT` wired straight to `CLKFBIN` (no BUFG), DRP and phase shift tied off, `RST => '0'`, only `CLKOUT0` used.

| Instance | Lines | `DIVCLK_DIVIDE` | `CLKFBOUT_MULT_F` | `CLKOUT0_DIVIDE_F` | VCO | Output (exact) | Period |
|---|---|---|---|---|---|---|---|
| `i_clk_c64_orig` | 136-182 | 6 | 56.750 | 30.000 | 945.833 MHz | 100 MHz x 227/720 = 283 750 000/9 Hz | 31.718 ns |
| `i_clk_c64_slow` | 190-236 | 9 | 60.500 | 21.375 | 672.222 MHz | 100 MHz x 484/1539 | 31.798 ns |
| `i_clk_c64_ntsc` | 244-290 | 5 | 36.000 | 22.000 | 720.000 MHz | 100 MHz x 36/110 = 360 000 000/11 Hz | 30.556 ns |
| `i_clk_c64_ntsc_ff` | 300-346 | 5 | 47.750 | 29.125 | 955.000 MHz | 100 MHz x 382/1165 = 7 640 000 000/233 Hz | 30.497 ns |

The parameter sets are the output of `python3 doc/dev-ntsc/tools/ntsc_clocks.py --final` (`clk.vhd:21`); that script enforces VCO 600 to 1200 MHz although the -2 part allows 1440 MHz (`ntsc_clocks.py:13-17`).

### 1.2 Mux tree and selection

Three glitch-free `bufgmux_ctrl` (BUFGCTRL) multiplexers, `clk.vhd:357-379`:

```
bufgmux_pal_inst  : i0 => main_clk_mmcm_orig, i1 => main_clk_mmcm_slow,    s => core_speed_i(0)
bufgmux_ntsc_inst : i0 => main_clk_mmcm_ntsc, i1 => main_clk_mmcm_ntsc_ff, s => core_speed_i(0)
bufgmux_mode_inst : i0 => main_clk_pal,       i1 => main_clk_ntsc,         s => core_speed_i(1)
```

`core_speed_i` (`clk.vhd:96`, declared "asynchronous"): `00` PAL original, `01` PAL flicker-free, `10` NTSC original, `11` NTSC flicker-free. A trailing `main_clk_bufg : BUFG` (`clk.vhd:385-389`) is removed by `opt_design` as a cascaded buffer: in the routed R6 report the global clock `g0` (main_clk, 13 681 loads) is driven by `CORE/clk_gen/bufgmux_mode_inst/O`. All four MMCMs run permanently, because a BUFGCTRL switches glitch-free only between two running clocks (`clk.vhd:31-35`).

### 1.3 Lock and reset

`main_rst_o` comes from `xpm_cdc_async_rst` (`clk.vhd:395-406`, `DEST_SYNC_FF => 6`) with `src_arst => not (main_locked_orig and main_locked_slow and main_locked_ntsc and main_locked_ntsc_ff)`. No MMCM is ever reset or reconfigured at run time. `mega65.vhd:647-648` makes the video clock the core clock: `video_clk_o <= main_clk_o; video_rst_o <= main_rst_o;`.

### 1.4 All clock primitives of the design

| Primitive | Instance | File:line | Use |
|---|---|---|---|
| MMCME2_ADV x4 | `i_clk_c64_orig`, `_slow`, `_ntsc`, `_ntsc_ff` | `CORE/vhdl/clk.vhd:136,190,244,300` | core clocks |
| BUFGCTRL x3 | `bufgmux_pal_inst`, `bufgmux_ntsc_inst`, `bufgmux_mode_inst` | `clk.vhd:357,365,373` | core clock mux |
| BUFG (removed) | `main_clk_bufg` | `clk.vhd:385` | redundant cascade |
| PLLE2_BASE | `i_clk_qnice` | `M2M/vhdl/clk_m2m.vhd:77-118` | VCO 1000 MHz: qnice 50, hr 100, hr_delay_refclk 200, hr_clk_del 100 at 90 degrees, sr 166.7 (unused, `framework.vhd:507`), eth 50 |
| MMCME2_BASE | `i_clk_audio` | `clk_m2m.vhd:120-141` | M 48, D 5, O 78.125: 12.288 MHz exactly |
| BUFG x7 | `qnice_clk_bufg` ... `audio_clk_bufg` | `clk_m2m.vhd:147-187` | six of them present after synthesis (`sr_clk` is unused) |
| MMCME2_ADV | `MMCM` | `M2M/vhdl/controllers/HDMI/video_out_clock.vhd:492-577` | HDMI pixel and 5x clock, DRP-reconfigured |
| BUFG | `U_BUFG_0` | `video_out_clock.vhd:579-583` | `tmds_clk` (5x) |
| BUFGCTRL | `U_BUFG_1` | `video_out_clock.vhd:594-600` | `hdmi_clk`: MMCM `CLKOUT1` or the 50 MHz backup `clki_div` |
| BUFG | `U_BUFG_F` | `video_out_clock.vhd:602-606` | HDMI MMCM feedback |
| BUFG (inferred) | `clk_i_IBUF_BUFG_inst` | routed report, global clock `g6` | 100 MHz board clock (fabric loads: `video_out_clock` FSM, `sys_pps`) |

`CORE/C64_MiSTerMEGA65/rtl/pll.vhd` (one more MMCM) is not part of any `CORE-R?.xpr`.

Routed report (`mega65_r6_clock_utilization_routed.rpt`, identical counts in R3):

```
| BUFGCTRL |   13 |        32 |
| MMCM     |    6 |        10 |
| PLL      |    1 |        10 |
```

Left: 4 MMCMs, 9 PLLs, 19 BUFGCTRL sites. A tree of 2:1 BUFGCTRL multiplexers with n leaves needs n - 1 of them, so each additional core clock in the tree costs one more BUFGCTRL (and one more MMCM, unless it is a second output of an existing MMCM with the same VCO).

## 2. Frame length of the core

### 2.1 Core clock cycles per C64 cycle

`fpga64_sid_iec.vhd:211-219` declares 32 states (`CYCLE_EXT0` .. `CYCLE_CPUF`). The state counter `preCycle` advances on every `clk32` edge and wraps unconditionally (`fpga64_sid_iec.vhd:393-402`):

```vhdl
preCycle <= sysCycleDef'succ(preCycle);
if preCycle = sysCycleDef'high then
   preCycle <= sysCycleDef'low;
```

So one C64 cycle is exactly 32 `clk_main` cycles. The VIC gets `enaData` (`enableVic`) at `CYCLE_VIC2` (phi 0) and `CYCLE_CPUE` (phi 1) (`fpga64_sid_iec.vhd:446-450`), and `enablePixel` 8 times per C64 cycle (`fpga64_sid_iec.vhd:716-725`).

### 2.2 Cycles per line and lines per frame

* `video_vicii_656x.vhd:41-44`: `mode6569` "PAL 63 cycles and 312 lines", `mode6567R8` "new NTSC 65 cycles and 263 line".
* Line length: after `cycleChar` ends at `rasterX(9 downto 3) = "0101000"`, PAL goes straight to `cycleCalcSprites`, 6567R8 inserts `cycleIdle1` and `cycleIdle2` ("2 extra idle cycles (65 cycles/line)", `video_vicii_656x.vhd:380-395`).
* Frame length: `lastLineFlag` at `rasterY = 311` (PAL) or `262` (6567R8) (`video_vicii_656x.vhd:352-360`).
* The VIC state machine is gated by `baSync = '0'`, and `baSync` is tied to `'0'` (`fpga64_sid_iec.vhd:635`).

Result: PAL 63 x 312 x 32 = 628 992, NTSC 65 x 263 x 32 = 547 040 `clk_main` cycles per frame (also stated in `clk.vhd:10-18` and measured by `CORE/vhdl/test/tb_ntsc/run.sh video`).

### 2.3 What can change the frame length

* **Turbo modes cannot.** Turbo only adds CPU slots (`cpu_cyc`, the turbo decision around `fpga64_sid_iec.vhd:570-600`); `preCycle` and the VIC enables do not depend on it.
* **DMA (`dma`, REU, cartridge bank fills) cannot.** It only holds the CPU (`fpga64_sid_iec.vhd:890`, `enable => enableCpu and not dma_active`).
* **`pause` can.** `sysCycle <= preCycle when sysEnable = '1' else CYCLE_EXT4;` (`fpga64_sid_iec.vhd:390`) and `sysEnable <= not pause;` (`fpga64_sid_iec.vhd:406`): while paused, no `enableVic` is generated and the VIC stops. `pause` is `main_pause_core_i` (`mega65.vhd:935`, `main.vhd:1297`), which is `main_qnice_pause_o` of the framework, the QNICE CSR bit `M2M$CSR_PAUSE` (`M2M/rom/sysdef.asm:36`, set in `M2M/rom/gencfg.asm:133`, crossed in `framework.vhd:823,833`). While the core is paused the input of the scaler stops, so a frame-locked HDMI output has no reference during a pause.
* `video_sync` runs its own counters from the VIC's sync edges (`main.vhd:2054-2066`, `pause => '0'`); see 7.4.

## 3. Flicker-free

### 3.1 Menu bit to the clock select

| Step | Domain | Where |
|---|---|---|
| Menu bits `C_MENU_HDMI_FF` (64), `C_MENU_HDMI_FF_NTSC` (65), `C_MENU_MACHINE_NTSC` (39) | QNICE | `mega65.vhd:449,466,467` |
| `qnice_osm_control_m_o` to `main_osm_control_m_o` | QNICE to main | `framework.vhd:815-839`, `xpm_cdc_array_single`, 839 bits |
| `c64_ntsc <= main_osm_control_i(C_MENU_MACHINE_NTSC);` | main | `mega65.vhd:746` |
| `main_hdmi_ff <= main_osm_control_i(C_MENU_HDMI_FF_NTSC) when c64_ntsc = '1' else main_osm_control_i(C_MENU_HDMI_FF);` | main | `mega65.vhd:786-787` |
| `i_cdc_main2hr` (`cdc_stable`, 2 bits, `G_REGISTER_SRC => true`) gives `hr_hdmi_ff`, `hr_ntsc` | main to hr | `mega65.vhd:1414-1426` |
| `hr_core_speed` process | hr (100 MHz) | `mega65.vhd:658-672` |
| `core_speed_i => hr_core_speed` | hr to BUFGCTRL `S` pins | `mega65.vhd:640` |

```vhdl
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
```

`hr_core_speed` has no reset and no initial value (`mega65.vhd:348`); it carries `attribute dont_touch ... "true"` (`mega65.vhd:352-353`) because `CORE.xdc:17-18` sets case analysis on `hr_core_speed_reg[0]/Q` and `hr_core_speed_reg[1]/Q` and `signoff_gates.tcl:22-26` checks that both pins exist.

**Flicker-free off:** `hr_core_speed = "00"` in PAL (31.527 778 MHz, 50.124 291 Hz) and `"10"` in NTSC (32.727 273 MHz, 59.826 105 Hz), whatever `hr_low_i` and `hr_high_i` do. That is already the core clock that "Raw" needs; only the HDMI side differs. The C64's notion of its own clock (`c64_clock_speed`, `mega65.vhd:783`) is always the nominal value of the standard (`CORE_CLK_SPEED_PAL = 31_527_778`, `CORE_CLK_SPEED_NTSC = 32_727_273`, `globals.vhd:60-61`), used by the CIA TOD and the drive chip enable.

### 3.2 The phase detector (`M2M/vhdl/hdmi_flicker_free.vhd`)

Instantiated in `av_pipeline.vhd:637-649` with `G_THRESHOLD_LOW => X"0000_1000"` and `G_THRESHOLD_HIGH => X"0000_2000"`, clocked by `hr_clk`, watching the 16-bit Avalon master of the scaler (`hr_dig_*`, after `avm_decrease`; word addresses):

* `p_last_address` (`hdmi_flicker_free.vhd:65-76`): `last_core_address` = address of the last write (scaler input, the core), `last_hdmi_address` = address of the last read (scaler output, HDMI).
* `p_last_diff` (`hdmi_flicker_free.vhd:78-86`): `if last_hdmi_address = 0 then last_diff <= last_core_address;` = the write position at the start of an output frame.
* `p_output` (`hdmi_flicker_free.vhd:88-102`): `low_o` while `last_diff < 0x1000`, `high_o` while `last_diff > 0x2000` (levels, not pulses).

With the PAL input stride of 1152 bytes (382 pixels x 3, rounded to 128) the window 0x1000 to 0x2000 words is about 7 to 14 visible input lines; in NTSC (404 pixels, 1280-byte stride) about 6.4 to 12.8 lines (`doc/dev-ntsc/tools/ff_model.py:5-13` models exactly this). The module works on all boards: on R4/R5/R6 the scaler's bus goes to the SDRAM controller, which also runs on `hr_clk` (`framework.vhd:1061-1130`, `clk_i => hr_clk`).

### 3.3 Must stay bit-identical when "Raw" is not selected

* `clk.vhd` MMCM parameters and the mux tree; `hr_core_speed` encoding and the process above (a verbatim copy lives between `BEGIN COPY` and `END COPY` in `CORE/vhdl/test/tb_ntsc/tb_core_speed.vhd:55-71`; `run_w1.sh:63-77` fails when the copy and `mega65.vhd` differ).
* `hdmi_flicker_free.vhd` and its thresholds.
* `qnice_video_mode_o` (`mega65.vhd:1216-1222`) for every existing menu state, the codes of `video_mode_to_slv`, and the eight DRP tables.
* `CLK_KHZ`, `CEA_CTA_VIC`, `ASPECT`, polarities and totals of the six used mode records.
* `CORE.xdc:17-20` (case analysis, `main_clk` on `i_clk_c64_ntsc_ff/CLKOUT0`) and `signoff_gates.tcl:28-41` (period 30.497 ns plus or minus 0.03 ns).

## 4. HDMI video modes

### 4.1 Record and modes (`M2M/vhdl/av_pipeline/video_modes_pkg.vhd`)

Record `video_modes_t` (`video_modes_pkg.vhd:6-30`): `CLK_KHZ`, `CLK_SEL(2 downto 0)`, `CEA_CTA_VIC`, `ASPECT(1 downto 0)` (`01` 4:3, `10` 16:9), `PIXEL_REP`, `H_PIXELS`, `V_PIXELS`, `H_PULSE`, `H_BP`, `H_FP`, `V_PULSE`, `V_BP`, `V_FP`, `H_POL`, `V_POL`.

| Constant | Lines | CLK_KHZ | CLK_SEL | VIC | Aspect | H: vis/FP/sync/BP = total | V: vis/FP/sync/BP = total | Pol H/V | Frame rate |
|---|---|---|---|---|---|---|---|---|---|
| `C_PAL_720_576_50` | 41-57 | 27000 | 001 | 17 | 4:3 | 720/17/64/63 = 864 | 576/5/5/39 = 625 | 0/0 | 50 (unused) |
| `C_HDMI_576p_50` | 61-77 | 27000 | 001 | 17 | 4:3 | 720/12/64/68 = 864 | 576/5/5/39 = 625 | 1/1 | 50 |
| `C_HDMI_720p_50` | 81-97 | 74250 | 010 | 19 | 16:9 | 1280/440/40/220 = 1980 | 720/5/5/20 = 750 | 1/1 | 50 |
| `C_HDMI_720x480p_5994` | 105-121 | 27000 | 001 | 2 | 4:3 | 720/16/62/60 = 858 | 480/9/6/30 = 525 | 0/0 | 60000/1001 |
| `C_HDMI_720p_5994` | 131-147 | 74167 | 110 | 4 | 16:9 | 1280/110/40/220 = 1650 | 720/5/5/20 = 750 | 1/1 | 17800/297 = 59.9327 |
| `C_HDMI_640x480p_60` | 155-171 | 25200 | 000 | 1 | 4:3 | 640/16/96/48 = 800 | 480/10/2/33 = 525 | 0/0 | 60 (not used by the C64 menu) |
| `C_HDMI_720p_60` | 175-191 | 74250 | 010 | 4 | 16:9 | 1650 | 750 | 0/0 | 60 (not used by the C64 menu) |
| `C_SVGA_800_600_60` | 196-212 | 40000 | 111 | 65 | 4:3 | 800/40/128/88 = 1056 | 600/1/4/23 = 628 | 1/1 | 60.3 (not used) |

`video_mode_type` (`video_modes_pkg.vhd:216-228`) and its 4-bit codes (`video_modes_pkg.vhd:241-272`):

| Member | Code | Used by the C64 menu |
|---|---|---|
| `C_VIDEO_HDMI_16_9_50` | `0000` | PAL 720p |
| `C_VIDEO_HDMI_16_9_60` | `0001` | no |
| `C_VIDEO_HDMI_4_3_50` | `0010` | PAL 4:3 576p |
| `C_VIDEO_HDMI_5_4_50` | `0011` | PAL 5:4 576p |
| `C_VIDEO_HDMI_640_60` | `0100` | no |
| `C_VIDEO_HDMI_720_5994` | `0101` | no |
| `C_VIDEO_SVGA_800_60` | `0110` | no |
| `C_VIDEO_HDMI_16_9_5994` | `0111` | NTSC 720p |
| `C_VIDEO_HDMI_4_3_5994` | `1000` | NTSC 4:3 480p |
| `C_VIDEO_HDMI_5_4_5994` | `1001` | NTSC 5:4 480p |

Codes `1010` to `1111` are free; `slv_to_video_mode` maps them to `C_VIDEO_HDMI_16_9_50` (`video_modes_pkg.vhd:270`), and `tb_video_modes.vhd:89` checks that fallback for "the six unused codes". `video_mode_is_ntsc` (`video_modes_pkg.vhd:274-278`) is true for exactly the three `*_5994` members.

### 4.2 Path of the mode selection and every clock domain crossing

1. **QNICE domain, `mega65.vhd:1216-1222`.** `qnice_video_mode_o` is decoded from `qnice_osm_control_i`. Invariant (comment `mega65.vhd:1214-1215`): one of the `*_5994` members if and only if the machine mode is NTSC.
2. **`framework.vhd:514-523`** maps the member to a record with its own `when ... else` chain (a second enumeration, independent of the vector below), and `qnice_clk_sel <= video_mode.CLK_SEL;` (`framework.vhd:525`) feeds `sel` of `i_video_out_clock` (`framework.vhd:528-539`). `sel` crosses from `qnice_clk` into the 100 MHz `clki` domain **without** synchronizer: `video_out_clock.vhd` builds `sel_s` in `SYNC1` (lines 462-476) but the state machine compares and indexes with the raw `sel` (lines 390, 406-407).
3. **`framework.vhd:956`**: `qnice_video_mode_i => video_mode_to_slv(qnice_video_mode_i)` into `av_pipeline` as 4 bits.
4. **`av_pipeline.vhd:293`**: `qnice_ntsc <= '1' when video_mode_is_ntsc(slv_to_video_mode(qnice_video_mode_i))`; crosses into the video (core) domain as `video_ntsc` in `i_qnice2video` (`av_pipeline.vhd:296-322`, `xpm_cdc_array_single`, bit 46). Consumers: `crop.vhd` (`video_ntsc_i`, `av_pipeline.vhd:553`) and the VGA OSM scaling (`av_pipeline.vhd:465`).
5. **`av_pipeline.vhd:512-532`**: the 4 mode bits cross into `hdmi_clk` in `i_qnice2hdmi` (`xpm_cdc_array_single`, bits 36 downto 33; no Gray coding: a multi-bit change can show an intermediate code for one `hdmi_clk` cycle). The constraint `set_false_path -from [get_clocks qnice_clk] -to [get_clocks hdmi_clk]` (`common.xdc:123`) covers it.
6. **`av_pipeline.vhd:535-537`**: `hdmi_osm_ntsc480` for the two 480p NTSC members (OSM scaling at least 89 %, `av_pipeline.vhd:606`).
7. **`digital_pipeline.vhd:182-191`**: `hdmi_video_mode` from `G_VIDEO_MODE_VECTOR` (the vector `VIDEO_MODE_VECTOR(0 to 9)` of `framework.vhd:282-292`, index = position in `video_mode_type`), then totals, sync positions, window, OSM shift and vshift, CTS, VIC, aspect, polarities, all in `hdmi_clk`.

### 4.3 What a mode change triggers

* **HDMI pixel clock**, only if `CLK_SEL` changes: `video_out_clock` switches `hdmi_clk` to the 50 MHz backup `clki_div` (`clk_mux <= '0'`, line 393), waits 4 cycles, resets the MMCM, writes the 23 DRP registers of the new table, waits for lock and switches back (`clk_mux <= '1'`, line 439). `rsto` (`hdmi_rst`) is high during the whole reconfiguration (`SYNC2`, lines 478-486) and resets only `vga_to_hdmi` and the four serializers (`digital_pipeline.vhd:538,571,582`); ascal and the OSM overlay keep running on the 50 MHz backup clock. A change between modes with the same `CLK_SEL` (576p 4:3 versus 5:4, 480p 4:3 versus 5:4) changes only the window.
* **Core:** only a change of the machine mode resets the C64 (`mode_change_reset_proc` in `main.vhd`, see `doc/ntsc.md:199-236`). A change of the HDMI display mode alone does not touch the core.
* **ascal:** reset only by `video_rst_i or hr_rst_i` (`digital_pipeline.vhd:328`); the output timing inputs are taken over every `o_clk` cycle (`ascal.vhd:1878-1890`, marked `<ASYNC>`), so new totals act immediately.

### 4.4 Every place that enumerates the modes

| Place | What it enumerates |
|---|---|
| `video_modes_pkg.vhd:216-228, 241-272, 274-278` | enum, codes, NTSC predicate |
| `framework.vhd:282-292` | `VIDEO_MODE_VECTOR(0 to 9)`, index must equal enum position (checked by `w2_checks.py` `parse_framework`) |
| `framework.vhd:514-523` | member to record for `CLK_SEL` (parsed by `w2_checks.py:83-90` in exactly this `C_x when qnice_video_mode_i = C_VIDEO_y else` form) |
| `mega65.vhd:1216-1222` | menu bits to member |
| `av_pipeline.vhd:293, 535-537` | NTSC predicate, 480p OSM flag |
| `digital_pipeline.vhd:182-191` | member to vector index |
| `digital_pipeline.vhd:202-212` | assertions: 16:9 modes `H >= V*4/3`, 4:3 modes `H <= V*4/3`, indices 5, 8, 9 must be 720 x 480 |
| `digital_pipeline.vhd:222-272` | `hdmi_hmin`, `hdmi_hmax`, `hdmi_vmin`, `hdmi_vmax` per member: pillarbox for 16:9 (`(H - V*4/3)/2`), 5:4 letterbox `(V - H*3/4)/2` for 576p and `(V - V*15/16)/2` for 480p, zoom (`hdmi_crop_mode_i`) = full frame |
| `digital_pipeline.vhd:278` | `hdmi_shift <= H_PIXELS - G_VGA_DX` (OSM x offset; needs `H_PIXELS >= 720`) |
| `digital_pipeline.vhd:285-287` | `hdmi_osm_vshift <= 24` for the two 480p NTSC members |
| `crop.vhd:55-58, 121-124` | PAL or NTSC crop window, chosen by `video_ntsc_i`, i.e. by `video_mode_is_ntsc` |
| `CORE/vhdl/test/tb_ntsc/tb_video_modes.vhd` | codes, fallback of the six free codes, NTSC predicate, the 720p59.94 record |
| `doc/dev-ntsc/tools/w2_checks.py` | records, framework decode, DRP tables of 010, 001, 110 |

## 5. HDMI pixel clock (`M2M/vhdl/controllers/HDMI/video_out_clock.vhd`)

### 5.1 The MMCM and its static attributes

`MMCM: component mmcme2_adv`, `video_out_clock.vhd:492-577`. The comment at lines 490-491: "For Static Timing Analysis it is necessary that the default configuration corresponds to the fastest clock speed."

```vhdl
clkfbout_mult_f      => 37.125, -- f_VCO = (100 MHz / 5) x 37.125 = 742.5 MHz
clkout0_divide_f     => 2.0,    -- TMDS @ 371.25 MHz
clkout1_divide       => 10,     -- HDMI @ 74.25 MHz
divclk_divide        => 5,
```

`CLKOUT0` = 5x serializer clock `clko_u_x5` through `U_BUFG_0`; `CLKOUT1` = pixel clock `clko_u` into `U_BUFG_1` (`bufgmux_ctrl`, `s => clk_mux`, `i0 => clki_div` = 100 MHz / 2, `i1 => clko_u`); feedback through `U_BUFG_F`. `dclk => clki` (100 MHz board clock).

### 5.2 DRP state machine (`video_out_clock.vhd:378-458`)

States `IDLE`, `RESET_WAIT`, `RESET`, `TBL`, `RD`, `RD_WAIT`, `WR`, `WR_WAIT`, `LOCK_WAIT`. `IDLE` restarts on `'0' & sel /= sel_prev` or `locked_s = '0'`. `RESET` latches `sel_prev <= '0' & sel` and `cfg_tbl_addr <= sel & "00000"`. Every entry is a read-modify-write: `cfg_di <= (cfg_do and mask) or (data and not mask)` (line 417). The entry whose DRP address byte has bit 7 set (bit 39 of the entry) is the last one (line 426). `rsti` (`not reset_m2m_n`) forces a full reconfiguration. `mmcm_rst <= cfg_rst or rsti` (line 488).

### 5.3 Table format

`cfg_tbl` (`video_out_clock.vhd:122-376`): 40 bits per entry = DRP address (8 bits, MSB = last entry) & write data (16) & keep mask (16). Slot base = `sel x 0x20`; each slot has 23 entries in this fixed order: CLKOUT5 reg 1/2 (`06`, `07`), CLKOUT0 reg 1/2 (`08`, `09`), CLKOUT1 reg 1/2 (`0A`, `0B`), CLKOUT2 to CLKOUT4 reg 1/2 (`0C`-`11`), CLKOUT6 reg 1/2 (`12`, `13`), CLKFBOUT reg 1/2 (`14`, `15`), DIVCLK (`16`), Lock 1-3 (`18`-`1A`), Power (`28`), Filter 1 (`4E`), Filter 2 (`CF` = `4F` with the last-entry bit). Reg 1 holds HIGH_TIME (bits 11-6) and LOW_TIME (bits 5-0); reg 2 holds FRAC (14-12), FRAC_EN (11), FRAC_WF_R (10), EDGE (7), NO_COUNT (6). For fractional counters XAPP888 stores the falling-edge fraction bits of CLKOUT0 in CLKOUT5 reg 2 and those of CLKFBOUT in CLKOUT6 reg 2.

### 5.4 Existing tables (decoded per XAPP888 with `w2_checks.py` `counter()` / `mmcm_freq()`)

| CLK_SEL | Slot | Lines | M | D | O0 (5x) | O1 (pixel) | VCO | Pixel clock (exact) | Users |
|---|---|---|---|---|---|---|---|---|---|
| 000 | 0x00 | 132-160 | 31.5 | 5 | 5 | 25 | 630.0 MHz | 25.200 000 MHz | 640x480p60 (unused) |
| 001 | 0x20 | 162-190 | 47.25 | 5 | 7 | 35 | 945.0 MHz | 27.000 000 MHz | 576p50, 480p59.94 |
| 010 | 0x40 | 192-220 | 37.125 | 5 | 2 | 10 | 742.5 MHz | 74.250 000 MHz | 720p50 |
| 011 | 0x60 | 222-250 | 37.125 | 5 | 1 | 5 | 742.5 MHz | 148.500 MHz | unused |
| 100 | 0x80 | 252-280 | 17.625 | 2 | 7 | 35 | 881.25 MHz | 176 250 000/7 Hz = 25.178 571 MHz | unused |
| 101 | 0xA0 | 282-310 | 21.625 | 2 | 8 | 40 | 1081.25 MHz | 27.031 250 MHz | unused |
| 110 | 0xC0 | 312-340 | 22.25 | 3 | 2 | 10 | 741.667 MHz | 222 500 000/3 Hz = 74.166 667 MHz | 720p59.94 |
| 111 | 0xE0 | 342-370 | 10 | 1 | 5 | 25 | 1000.0 MHz | 40.000 000 MHz | SVGA (unused) |

The comment of the 27.000 MHz table says "Actual frequency = 74.250 MHz" (line 167); the registers give 27.000 MHz. The port comment (line 61) and the record comment (`video_modes_pkg.vhd:16`) call `111` "undefined", but the slot holds the 40 MHz table. `doc/dev-ntsc/NTSC-SPEC.md:446-450` records the fix of the `110` table (wrong NO_COUNT/EDGE words, commit `b810c59`).

### 5.5 Adding a table

* **No free slot.** `sel` is 3 bits and all 8 slots are filled. Options: widen `sel` to 4 bits (`sel_prev` is already 4 bits, `'0' & sel`; `cfg_tbl_addr` is 8 bits = `sel & "00000"`, would become 9 bits; the record field `CLK_SEL`, `framework.vhd:525` and `w2_checks.py:99` (`base = int(sel, 2) * 0x20`) follow), or overwrite an unused slot (000, 011, 100, 101, 111 are not used by the C64 menu).
* **Constraint on the 5:1 ratio.** `CLKOUT1` is an integer divider and `CLKOUT0` = `CLKOUT1` / 5 must be a legal divider, so `O1` is a multiple of 5 and `O0 = O1/5` is an integer; the only fine-grained parameters are `M` (steps of 1/8) and `D`. Pixel clock = 100 MHz x `M` / (`D` x `O1`).
* **Derivation**, as documented in the file header (`video_out_clock.vhd:26-34`): Clocking Wizard for M/D/O0/O1, XAPP888 `MMCME2_DRP/top_mmcme2.tcl` in Vivado, the spreadsheet `video_out_clock.xls` of the tyto2 project, then a TCL command prints the words.
* **Offline verification.** `w2_checks.py` (`drp_table`, `counter`, `divclk`, `mmcm_freq`, lines 97-146) decodes CLKOUT0, CLKOUT1, CLKFBOUT and DIVCLK of any slot; its check 3 only covers `CLK_SEL` 110, 010 and 001, so a new slot needs a new check. Not covered by the decoder: the falling-edge fraction words (CLKOUT5 reg 2 for CLKOUT0, CLKOUT6 reg 2 for CLKFBOUT, entries `07` and `13`), the lock words (`18`-`1A`) and the filter words (`4E`, `4F`). They depend on M and bandwidth through the XAPP888 lookup tables; `NTSC-SPEC.md:450` notes that they "cannot be checked ... without Vivado". Existing tables with the same integer part of M give reference values (for example CLKOUT6 reg 2 is `3000` for M 31.5, 17.625 and 21.625, `2800` for 47.25, `2400` for 37.125, `0C00` for 22.25, `0000` for 10).
* **On hardware**, the pixel clock is measured: `i_clock_counter` (`framework.vhd:750-756`) counts `hdmi_clk` per second and the QNICE reads it at `C_SYS_HDMI` offsets 3 and 4 (`qnice_wrapper.vhd:417-418`, `M2M$SYS_HDMI = 0x0011`).

## 6. HDMI encoder and audio

### 6.1 N and CTS

`digital_pipeline.vhd:100-109, 293-322`:

```vhdl
audio_pcm_n   <= std_logic_vector(to_unsigned((HDMI_PCM_SAMPLING * 128) / 1000, audio_pcm_n'length)); -- 6144 is correct according to HDMI spec.
audio_pcm_cts <= std_logic_vector(to_unsigned(hdmi_video_mode.CLK_KHZ, audio_pcm_cts'length));
```

`N` = 6144 (48 kHz), `CTS` = `CLK_KHZ` of the record, i.e. CTS = pixel clock / 1000, which is exact for N = 6144 because 128 x 48 000 / 6144 = 1000. Nothing is measured. The ACR packet strobe `audio_pcm_acr` is 1 kHz from the 12.288 MHz audio clock (`p_pcm_acr`, lines 308-322); the 48 kHz sample enable comes from `clk_synthetic_enable` (lines 294-300). `pcm_n` and `pcm_cts` cross into `hdmi_clk` through `SYNC4` (`vga_to_hdmi.vhd:451-475`) and are sent in every ACR packet (`vga_to_hdmi.vhd:653-665`). The audio channel status says 48 kHz (`vga_to_hdmi.vhd:322-325`, `select_44100 => '0'`). `CLK_KHZ` has no other user in the C64 build (the only other one is `democore.vhd:123`). Today's residual error: 720p59.94 uses 74167 for 74 166.67 kHz (+4.5 ppm).

### 6.2 Other mode-dependent fields

* AVI InfoFrame: VIC (`pb(3)(4) <= unsigned(vic_s)`), aspect (`pb(3)(2)(5 downto 4)`), pixel repetition (`vga_to_hdmi.vhd:673-690`), sent "once per frame" when the vsync edge coincides with an hsync edge (line 673). Inputs from `digital_pipeline.vhd:532-536`.
* Sync polarities `hs_pol`, `vs_pol` (`vga_to_hdmi.vhd:479` and following).
* DVI switch `dvi` (`digital_pipeline.vhd:531`, `qnice_dvi_i`, synchronized in `SYNC4`).
* Nothing in `vga_to_hdmi.vhd` or the serializers depends on the absolute pixel frequency.

### 6.3 A pixel clock 0.25 % above the record's `CLK_KHZ`

* The sink regenerates 128 fs = f_TMDS x N / CTS = 1.0025 x 6.144 MHz, i.e. it plays 48 120 samples per second while the source delivers 48 000 (the samples are paced by `audio_clk`, not by the pixel clock): its buffer runs empty, about 120 missing samples per second, audible as periodic dropouts unless the sink measures the clock itself. `NTSC-SPEC.md:395` states the same for the 720p59.94 case. The fix is a `CLK_KHZ` equal to the true pixel clock in kHz (20-bit field, residual error at most 0.5 kHz, below 20 ppm at 27 MHz).
* The AVI InfoFrame would still announce the CTA VIC (17, 19, 2 or 4) for a timing that is not that format. With unchanged totals the line and frame rates are 0.25 % off the format; with changed totals (one line more or less) the timing is no CTA format at all. CTA-861 uses VIC 0 for formats without a code.
* Timing analysis: see 8.3.
* The 5x serializer clock rises to about 372 MHz at 720p; nothing else in the HDMI path is frequency-specific.

## 7. Scaler wiring

### 7.1 ascal instance (`digital_pipeline.vhd:330-461`)

Generics: `MASK => x"ff"`, `RAMBASE => 0`, `RAMSIZE => 2**f_log2(G_VGA_DX * G_VGA_DY * 3)` = 2^21 = 2 MB for the 720 x 540 canvas (`globals.vhd:85-86`), `INTER => false`, `HEADER => false`, `DOWNSCALE => false`, `DOWNSCALE_NN => true`, `BYTESWAP => true`, `ADAPTIVE => true`, `PALETTE`/`PALETTE2 => false`, `FRAC => 6`, `OHRES => 2048`, `IHRES => 1024`, `N_DW => 128`, `N_AW => 19`, `N_BURST => 128`.

| Port | Connection |
|---|---|
| `i_r/g/b`, `i_hs`, `i_vs`, `i_de`, `i_ce`, `i_clk` | cropped core video, `i_de => not (video_hblank_i or video_vblank_i)`, `i_clk => video_clk_i` (= `main_clk`) |
| `o_r/g/b`, `o_hs`, `o_vs`, `o_de` | to `video_overlay` (OSM) and then `vga_to_hdmi` |
| `o_vbl` | open |
| `o_ce => '1'`, `o_clk => hdmi_clk_i` | |
| `o_lltune` | open (line 403) |
| `iauto => '1'`, `himin..vimax => 0` | input window auto-detected; `i_hdmax`/`i_vdmax` go to QNICE |
| `run => '1'`, `freeze => '0'`, `mode => qnice_ascal_mode_i` | lines 417-419 |
| `htotal`, `hsstart`, `hsend`, `hdisp`, `vtotal`, `vsstart`, `vsend`, `vdisp` | from the mode record (`digital_pipeline.vhd:193-200`) |
| `hmin`, `hmax`, `vmin`, `vmax` | output window (`digital_pipeline.vhd:222-272`) |
| `format => "01"` | 24 bpp |
| `poly_*` | QNICE polyphase coefficients |
| `avl_*`, `avl_clk => hr_clk_i` | 128-bit Avalon, narrowed to 16 bits by `avm_decrease` (lines 463-491, 22-bit word address) |
| `reset_na => not (video_rst_i or hr_rst_i)` | line 328 |

### 7.2 Mode bits

`ascal.vhd:78-92`: `MODE[2:0]` interpolation (000 nearest, 001 bilinear, 010 sharp bilinear, 011 bicubic, 100 polyphase), `MODE[3]` triple buffering, `MODE[4]` reserved. `config.vhd:286` sets `ASCAL_USAGE := 1`, so the firmware owns the register: `LOAD_HDMI_FILTER` (`m2m-rom.asm:1523`) writes `M2M$ASCAL_MODE` (`sysdef.asm:115`) from `HDMI_FLT_TABLE` (`m2m-rom.asm:1644-1664`), only the values `M2M$ASCAL_NEAREST`, `SBILINEAR`, `BICUBIC` and `POLYPHASE` (0 to 4). `M2M$ASCAL_TRIPLEBUF = 0x0008` exists (`sysdef.asm:130`) but is never set. With `MODE(3) = '0'` all buffer indices are forced to 0 (`ascal.vhd:1946-1952`): input and output share one frame buffer. A frame rate mismatch therefore appears as a tear line that crosses the picture once per beat period (PAL 8.0 s, NTSC 480p 8.8 s, NTSC 720p 9.4 s with flicker-free off), not as a dropped or repeated frame. Triple buffering needs 3 x `RAMSIZE` = 6 MB; on R3 the frame buffer lives in the M2M HyperRAM region of 3 MB (`C_HMAP_CRT = x"0180"`, `globals.vhd:142-143`; guard `mega65.vhd:681-683`), so triple buffering does not fit there.

### 7.3 Frame buffer RAM

* R3/R3A: `sdram_gen : if G_BOARD = "MEGA65_R3" generate` (`framework.vhd:1021-1059`): the scaler (`hr_dig_*`) is slave 2 of a 3-way `avm_arbit_general` on the HyperRAM, together with the core (REU, CRT, mount buffers) and QNICE.
* R4/R5/R6: `else generate` (`framework.vhd:1061-1130`): the scaler alone on the SDRAM controller (`G_CLOCK_SPEED_MHZ => 100`, `clk_i => hr_clk`), the HyperRAM shared by core and QNICE.

### 7.4 Frame markers

| Domain | Signal | Where |
|---|---|---|
| core (`main_clk`) | `vsync_out` of `video_sync` = `video_vs_o`: PAL rises at line 307 (`video_sync.vhd:93`), NTSC at line 0 (`video_sync.vhd:76`); lines are counted from the VIC's hsync, reset by its vsync | `main.vhd:2054-2066` |
| core | `vblank` falling = first visible line: PAL line 28 (`video_sync.vhd:98`), NTSC line 13 (`video_sync.vhd:81`) | |
| core | inside ascal: `i_vs` (frame end for buffer switching, `i_endframe0`), `i_vss` = "inside the input window" (`ascal.vhd:1224`), exported as `o_lltune(0)` | `ascal.vhd:2904-2912` |
| HDMI (`hdmi_clk`) | ascal `o_vs` (`hdmi_vs`), `o_vss` (`ascal.vhd:2702`), exported as `o_lltune(4)`; `o_vbl` | |
| `hr_clk` | first read at word address 0 = start of an output frame; the latched write address = core position at that moment (`hdmi_flicker_free.vhd:82-84`) | |

`o_lltune` is MiSTer's low-lag interface (`ascal.vhd:2903-2912`: bit 0 `i_vss`, 1 `i_pde`, 2 `i_inter`, 3 `i_flm`, 4 `o_vss`, 5 `i_pce`, 6 `i_clk`, 7 `o_clk`); it is left open here.

The core's video CE is `clk_main / 4` (`main.vhd:2071-2082`); PAL lines have 504 dots, NTSC lines 520 dots, the visible windows are 382 x 270 and 404 x 250 (`main.vhd:2043-2048`).

## 8. Timing constraints

### 8.1 Clocks

* `common.xdc:12`: `create_clock -period 10.000 -name clk [get_ports {clk_i}]`.
* `common.xdc:15-23`: generated clocks `qnice_clk`, `hr_clk`, `hr_delay_refclk`, `hr_clk_del`, `sr_clk`, `eth_clk`, `audio_clk`, `tmds_clk` (`i_video_out_clock/MMCM/CLKOUT0`), `hdmi_clk` (`i_video_out_clock/MMCM/CLKOUT1`).
* `common.xdc:26-27`: `div_clk` on `clki_div_reg/Q` (divide by 2) and `set_case_analysis 1 [get_pins i_framework/i_video_out_clock/clk_mux_reg/Q]`, so only the MMCM leg of `U_BUFG_1` is timed as `hdmi_clk`.
* `CORE.xdc:17-20`: case analysis 1 on both `hr_core_speed` bits and `create_generated_clock -name main_clk [get_pins CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0]`; the three slower core clocks are timed through the faster one (`CORE.xdc:5-16`).
* `signoff_gates.tcl:15-73`: both case-analysis pins exist, `main_clk` exists with period 30.497 ns plus or minus 0.03 ns and its source pin exists, `qnice_clk` exists, IEC false-path targets resolve, the paddle bus-skew cells resolve. Nothing checks `hdmi_clk` or `tmds_clk`.

### 8.2 Crossings

* No `set_clock_groups` anywhere. All clocks derive from `clk`, so Vivado treats every pair as related unless an exception exists.
* `main_clk` and `hdmi_clk`: only the regex false paths on ascal's `i_*`, `o_*`, `avl_*` registers (`common.xdc:115-119`). The R6 inter-clock table has no `main_clk`/`hdmi_clk` pair at all.
* `hdmi_clk` and `audio_clk`: false paths both ways (`common.xdc:121-122`); `qnice_clk` to `hdmi_clk`: false path (`common.xdc:123`); ascal `reset_na`: false path (`common.xdc:124`).
* `cdc_stable`: `set_max_delay 8 -datapath_only` from any generated clock or `clk` (`common.xdc:34-35`).
* `qnice_clk` and `main_clk`: false paths both ways (`CORE.xdc:63-64`), plus `set_bus_skew 10.000` for the paddle bus (`CORE.xdc:73`).

### 8.3 How the HDMI domain is timed

The HDMI MMCM is reconfigured at run time, so STA uses its static attributes: `hdmi_clk` 13.468 ns (74.25 MHz) and `tmds_clk` 2.694 ns (371.25 MHz), as the routed reports show (`g2` 13.468, `g7` 2.694). Post-route intra-clock slack of `hdmi_clk`: WNS 1.594 ns (R3), 1.387 ns (R6); WHS 0.066 and 0.075 ns; `tmds_clk` has only pulse-width checks (slack 1.101 ns). A new table that is faster than 74.25 MHz (for example 74.4346 MHz for raw PAL at 720p totals, 13.435 ns) is outside the analyzed corner: on today's builds 34 ps of the 1.4 ns margin would be consumed, but nothing would prove it. Making the static attributes equal to the fastest table keeps the "default = fastest" rule of `video_out_clock.vhd:490-491`; `common.xdc:22-23` refer to the pins, not to the frequency, so they keep working. The 148.5 MHz table (`011`) is already faster than the static configuration and is unused.

## 9. Menu and firmware

### 9.1 The HDMI submenu (`CORE/vhdl/config.vhd`)

| Flat | `OPTM_ITEMS` (line) | `OPTM_GROUPS` (line) |
|---|---|---|
| 54 | `" HDMI: %s"` (477) | `OPTM_G_SUBMENU` (903) |
| 55 | `" HDMI Display Mode"` (478) | `OPTM_G_HEADLINE` (904) |
| 56 | empty (479) | `OPTM_G_LINE` (905) |
| 57 | `" 16:9 720p 50 Hz"` (480) | `OPTM_G_HDMI_MODES_PAL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)` (906) |
| 58 | `" 16:9 720p 59.94 Hz"` (481) | `OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)` (907) |
| 59 | `" 4:3  576p 50 Hz"` (482) | `OPTM_G_HDMI_MODES_PAL + OPTM_DEP(..., 0)` (908) |
| 60 | `" 4:3  480p 59.94 Hz"` (483) | `OPTM_G_HDMI_MODES_NTSC + OPTM_DEP(..., 1)` (909) |
| 61 | `" 5:4  576p 50 Hz"` (484) | `OPTM_G_HDMI_MODES_PAL + OPTM_DEP(..., 0)` (910) |
| 62 | `" 5:4  480p 59.94 Hz"` (485) | `OPTM_G_HDMI_MODES_NTSC + OPTM_DEP(..., 1)` (911) |
| 63 | empty (486) | `OPTM_G_LINE` (912) |
| 64 | `" HDMI: Flicker-free"` (487) | `OPTM_G_HDMI_FF + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(..., 0)` (913) |
| 65 | `" HDMI: Flicker-free"` (488) | `OPTM_G_HDMI_FF_NTSC + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(..., 1)` (914) |
| 66 | `" HDMI: DVI (no sound)"` (489) | `OPTM_G_HDMI_DVI + OPTM_G_SINGLESEL` (915) |
| 67-79 | nested `" HDMI: %s"` filter submenu (491-503) | 917-929 |
| 80 | `" HDMI: Zoom-in"` (505) | `OPTM_G_HDMI_ZOOM + OPTM_G_SINGLESEL` (931) |
| 81 | `" HDMI: Raw 50.1 Hz"` (506, "not yet wired in mega65.vhd") | `OPTM_G_HDMI_RAW50 + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)` (932, "PAL only") |
| 82 | empty (507) | `OPTM_G_LINE` (933) |
| 83 | `" Back"` (508) | `OPTM_G_CLOSE + OPTM_G_SUBMENU` (934) |

Group IDs: `OPTM_G_HDMI_MODES_PAL = 13`, `OPTM_G_HDMI_FF = 14`, `OPTM_G_HDMI_DVI = 15`, `OPTM_G_HDMI_FILTER = 16`, `OPTM_G_HDMI_ZOOM = 17`, `OPTM_G_MACHINE_MODE = 22`, `OPTM_G_HDMI_MODES_NTSC = 25`, `OPTM_G_HDMI_FF_NTSC = 26`, `OPTM_G_HDMI_RAW50 = 27` (`config.vhd:779-793`). `OPTM_DEP(mother, item)` and `OPTM_DEP2` (`config.vhd:823-830`) set bit 29 (`OPTM_G_DEPENDENT`), a 4-bit item mask in bits 28-25 and the mother group in bits 24-17; items 0 to 3 only. `OPTM_SIZE = 325` (`config.vhd:397`, max 512), `OPTM_DX = 25`, `OPTM_DY = 29` (`config.vhd:410-411`). Every line added before index 87 shifts all later `C_MENU_*` indices.

### 9.2 A submenu with more than one headline

The `Model` submenu (`config.vhd:456-473`, groups `879-899`, flat 35-52) has three headlines, each preceded by a separator line, and a dependent block:

```vhdl
OPTM_G_SUBMENU,                          -- open "Model: %s"
OPTM_G_HEADLINE,                         -- Model
OPTM_G_LINE,
OPTM_G_MACHINE_MODE  + OPTM_G_STDSEL,    -- PAL
OPTM_G_MACHINE_MODE,                     -- NTSC
OPTM_G_LINE,
OPTM_G_HEADLINE,                         -- Turbo mode
OPTM_G_LINE,
OPTM_G_TURBO_MODE    + OPTM_G_STDSEL,    -- Off
OPTM_G_TURBO_MODE,                       -- C128
OPTM_G_TURBO_MODE,                       -- Smart
OPTM_G_LINE                            + OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2),
OPTM_G_HEADLINE                        + OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2), -- Turbo speed
OPTM_G_TURBO_SPEED   + OPTM_G_STDSEL   + OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2), -- 2x
OPTM_G_TURBO_SPEED                     + OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2), -- 3x
OPTM_G_TURBO_SPEED                     + OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2), -- 4x
OPTM_G_LINE,
OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Model: %s"
```

The matching text (`config.vhd:456-473`) is `" Model: %s"`, `" Model"`, empty, `" PAL"`, `" NTSC"`, empty, `" Turbo mode"`, empty, `" Off"`, `" C128"`, `" Smart"`, empty, `" Turbo speed"`, `" 2x"`, `" 3x"`, `" 4x"`, empty, `" Back"`. Note the pattern: separator (`OPTM_G_LINE`, empty text) + headline + separator before the first two groups, but no separator between the third headline and its items. A dependent line can depend on a mother in the same submenu (`menu_test.py:1204-1211`).

### 9.3 `C_MENU_HDMI_*` in `mega65.vhd`

Constants `mega65.vhd:457-484` (the comment at 457-459 says "raw 50.1 Hz is not yet wired"). Uses:

| Constant | Use |
|---|---|
| `C_MENU_MACHINE_NTSC` | `mega65.vhd:746` (`c64_ntsc`), `1217-1219` |
| `C_MENU_HDMI_FF`, `C_MENU_HDMI_FF_NTSC` | `mega65.vhd:786-787` |
| `C_MENU_HDMI_16_9_50` ... `C_MENU_HDMI_5_4_5994` | `mega65.vhd:1217-1222` (16_9 members only as the default of each chain) |
| `C_MENU_HDMI_DVI` | `mega65.vhd:1226` |
| `C_MENU_HDMI_ZOOM` | `mega65.vhd:1234` |
| `C_MENU_HDMI_FLT_*` | VHDL: none (firmware only) |
| `C_MENU_HDMI_RAW50` | none |

### 9.4 Firmware

* `CORE/m2m-rom/osm_const.asm` is generated by `make_rom.sh:24-50` with `awk` from every `constant C_MENU_` line of `mega65.vhd` (to `C64_OSM_*`) and every `constant OPTM_G_` line of `config.vhd` (to `C64_OPTM_G_*`); it contains `C64_OSM_HDMI_FF .EQU 64`, `C64_OSM_HDMI_FF_NTSC .EQU 65`, `C64_OSM_HDMI_RAW50 .EQU 81`, `C64_OPTM_G_HDMI_RAW50 .EQU 27` (`osm_const.asm:35-53, 111-125`).
* No firmware code reads the HDMI display mode, flicker-free or raw bits. The only HDMI logic in the firmware is the filter: `OSM_SEL_POST` (`m2m-rom.asm:1004-1046`) calls `LOAD_HDMI_FILTER` when `C64_OPTM_G_HDMI_FILTER` changes; boot applies it at `m2m-rom.asm:681-693`.
* `SUBMENU_SUMMARY` (`m2m-rom.asm:46-95` contract) has custom branches for Model, Kernal and Volume only. `"HDMI: %s"` uses the standard semantics of `OPTM_CB_SHOW` (`M2M/rom/options.asm:1565-1572`): the selected item of the first menu group of the submenu (dependency-aware, so PAL shows the PAL mode and NTSC the NTSC mode).
* `OSM_SEL_PRE` (`m2m-rom.asm:1172-1340`) handles drives and the CRT line; nothing HDMI-related.
* Radio groups are written by the Shell one bank of 16 menu bits at a time; the VHDL decoders that must survive intermediate states hold their value or decode only one bit (see the comments at `mega65.vhd:763-765`, `1249-1251`). `qnice_video_mode_o` is purely combinational, so an intermediate state passes through the chain default and can start an extra pixel clock reconfiguration.

### 9.5 Golden model `M2M/rom/tests/menu_test.py`

* Group IDs `menu_test.py:77-80` (`HDMI_RAW50=27`).
* `V6_MENU` HDMI part `menu_test.py:148-175`, including `(" HDMI: Raw 50.1 Hz", "HDMI_RAW50", ["SINGLESEL"])` at line 175.
* Hardcoded dependent flat indices `V6_DEPS` (`menu_test.py:443-459`): `57`, `59`, `61`, `64`, `81` depend on `MACHINE_MODE` item 0 (mask `0b0001`), `58`, `60`, `62`, `65` on item 1 (`0b0010`); also `2`-`5`, `46`-`50`, `302`, `306`.
* Fixtures with hardcoded indices: "v6 HDMI level PAL" (`menu_test.py:1202-1203`), turbo fixtures with `s[43]`, `s[44]`, `s[45]` (1207-1211).
* Constant table for `verify` and `vhdl` (`menu_test.py:2855-2875`): `("C_MENU_HDMI_RAW50", "HDMI_RAW50", 0)` etc.
* An older menu layout (`menu_test.py:621-646`) is kept as a fixture (`16:9 720p 60 Hz`).

## 10. Documentation that mentions flicker-free or the HDMI frame rate

| File:line | Content |
|---|---|
| `README.md:95-103` | HDMI outputs 720p / 576p "at 50 Hz" |
| `README.md:105-109` | VGA "50.125 Hz in PAL mode" (the core gives 50.124 Hz) |
| `README.md:117-119` | switch flicker-free off for VGA |
| `README.md:126-127` | NTSC HDMI modes, flicker-free nudges PAL to 50.00 Hz |
| `FAQ.md:94-121` | VGA flicker, flicker-free links |
| `FAQ.md:263-282` | "Switch-off HDMI: Flicker-free": HDMI "slightly jerky" when off |
| `FAQ.md:412-413` | NTSC modes and flicker-free |
| `VERSIONS.md:28-33` | V6 (unreleased section starting at line 1): NTSC entry with flicker-free |
| `VERSIONS.md:487, 511, 597` | released versions (historical, not to be edited) |
| `doc/hdmi.md:8-9, 55-57, 62-71` | menu contents, frame rates table |
| `doc/ntsc.md:24-28, 64-135, 137-151, 254, 258-286` | clocks, flicker-free in NTSC, modes, "Not supported: no HDMI: Raw 50.1 Hz" (263), "why these HDMI modes", `vsync_adjust` |
| `doc/speed.md:14, 23, 25-35` | flicker-free clocks and what they do |
| `doc/clock_reset.md:40-55` | `core_speed_i` table, flicker-free feedback, STA at the fastest clock |
| `doc/developer.md:96` | sign-off gates (main_clk at 30.497 ns) |
| `doc/developer.md:564-615` | "Visual artifacts and dynamic HDMI flicker-fix" |
| `doc/graphics.md:42` | PAL frame rate 50.1246 Hz |
| `doc/retrotubes.md:14, 43` | disable flicker-free with analog gear |
| `doc/vic_ii_variants.md:53, 71-72, 100` | frame rates of the variants, flicker-free |
| `doc/inofficial.md:89, 101` | released alpha rows (historical) |
| `doc/dev-ntsc/NTSC-SPEC.md:34-35, 61, 395, 446-450, 791` | non-goals (no raw mode, no `vsync_adjust`), CTS, `110` table fix, 720p risk |
| `tests/README.md:262-278` (`Version WIP-V6-A22`, TBD) | NTSC tests with flicker-free |
| `tests/README.md:627-635` (`Version 6.0 - TBD`) | menu dependency test that expects the "Raw 50.1 Hz" line in PAL and not in NTSC |
| `CORE/vhdl/config.vhd:128-133` | help page 1: "disable HDMI: Flicker-free" for VGA, "enable HDMI: Flicker-free for PAL (50 Hz) and NTSC (59.94 Hz)" for HDMI |
| `CORE/vhdl/clk.vhd:6-60`, `mega65.vhd:633-635, 654-657`, `CORE.xdc:5-16` | source comments on the clocks |

## 11. Exact frame-rate matches that the existing hardware can produce

Both clock trees run from the same 100 MHz oscillator, so an exact match needs pixel clock / (H total x V total) = core frame rate as rational numbers. PAL: 17 734 375 / 353 808 = 5^7 x 227 / (2^4 x 3^5 x 7 x 13). NTSC: 2 250 000 / 37 609 = 2^4 x 3^2 x 5^6 / (11 x 13 x 263). Because of the prime 227, an exact PAL match needs `CLKFBOUT_MULT_F` 28.375 or 56.75 in the HDMI MMCM (the PAL core MMCM uses 56.75); because of 263, an exact NTSC match needs 263 (or a multiple) in H total or V total. Search over all single-MMCM settings with the 5:1 ratio (VCO 600 to 1200 MHz, `D` 1 to 10):

| Raw target | Pixel clock | M / D / O0 / O1 | Totals | Change against the existing mode |
|---|---|---|---|---|
| PAL, 576p container | 27.023 810 MHz (VCO 945.833 MHz) | 28.375 / 3 / 7 / 35 (or 56.75 / 6) | 864 x 624 | +882 ppm pixel clock, one line less |
| NTSC, 480p container | 27.000 000 MHz (table `001` as it is) | 47.25 / 5 / 7 / 35 | 858 x 526 | one line more, no new table |
| NTSC, 720p container | 74.250 000 MHz (table `010` as it is) | 37.125 / 5 / 2 / 10 | 1573 x 789 | H total 1650 to 1573 (front porch 110 to 33), V total 750 to 789, line rate 47.2 kHz |
| PAL, 720p container | 70.937 500 MHz (VCO 709.375 MHz) | 28.375 / 4 / 2 / 10 | 1872 x 756 | -4.5 % pixel clock, nonstandard totals |

With the standard totals unchanged, the closest single-MMCM pixel clocks are 132.6 ppm off for PAL 720p (M 33.5, D 3, O1 15), 159.3 ppm for PAL 576p, -156.8 ppm for NTSC 480p and +374 ppm for NTSC 720p; such a mode is not exact and slips one frame every 107 s (NTSC 480p), 125 s (PAL 576p), 150 s (PAL 720p) or 45 s (NTSC 720p). Whether a display accepts the changed totals has to be tested on displays; CTA-861 has no VIC for any of them.

## 12. Traps

1. **Single frame buffer.** Equal frame rates without a defined phase leave a permanent tear line at a random height. Raw mode needs phase acquisition (for example the existing `hdmi_flicker_free` window as phase detector) or a different buffering scheme; triple buffering does not fit into the 3 MB M2M region on R3.
2. **Phase acquisition with one clock direction works**, because the phase is cyclic: in PAL only the slower clock exists, in NTSC only the faster one, and a 0.25 % or 0.19 % offset walks through a whole frame in at most about 8 to 9 s. The current `hr_core_speed` logic does not do this: with the HDMI rate equal to the original rate, "too slow" in PAL and "too fast" in NTSC select the original clock, and the phase then stays where it is.
3. **`CLK_KHZ` is the audio CTS.** Every new record needs its true pixel clock in kHz, or HDMI audio drops out.
4. **VIC code.** Nonstandard timing with a CTA VIC in the AVI InfoFrame; VIC 0 is the CTA value for formats without a code.
5. **No free `CLK_SEL` slot** and `sel` is not synchronized into the 100 MHz domain; a combinational, glitchy `sel` can start extra reconfigurations.
6. **STA corner.** A table faster than 74.25 MHz needs the MMCM's static attributes moved to it, or the HDMI domain is not signed off.
7. **Lock, filter and falling-edge fraction words** of a new DRP table cannot be verified by `w2_checks.py`.
8. **`video_mode_is_ntsc`** drives the crop window (`crop.vhd`) and the VGA OSM scaling; an NTSC raw member must be added there, a PAL raw member must not. `hdmi_osm_ntsc480` and `hdmi_osm_vshift` list the 480p members by name; the assertions at `digital_pipeline.vhd:202-212` and the window chains at 222-272 list every member.
9. **Two separate enumerations** of member to record (`framework.vhd:514-523` and `digital_pipeline.vhd:182-191` through `VIDEO_MODE_VECTOR`) must stay consistent; `w2_checks.py` checks it only in its fixed regex form.
10. **Raw and flicker-free are both single-select bits** today; their combination needs a defined meaning (the core must sit on the original clock in raw mode, with `hr_hdmi_ff` effectively off), and both bits reach the hardware through different paths (core clock: QNICE to main to `hr_clk`; HDMI mode: QNICE domain).
11. **The menu placeholder is PAL-only** (`OPTM_DEP(OPTM_G_MACHINE_MODE, 0)`); an NTSC raw choice needs a twin line or a different dependency, and any added line shifts every later `C_MENU_*` index, `V6_DEPS` in `menu_test.py`, `osm_const.asm` and the fixtures with hardcoded indices.
12. **`tb_core_speed.vhd` holds a verbatim copy** of the `hr_core_speed` process; `tb_video_modes.vhd` checks that exactly six codes are free.
13. **`pause`** (QNICE CSR) stops the VIC and with it the input frames; a genlock must tolerate a missing reference.
14. **`hr_core_speed` has no reset value**; the case-analysis and `dont_touch` contract with `CORE.xdc` and `signoff_gates.tcl` must survive any change of the process.
