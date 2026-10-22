# NTSC implementation: file and line map

Every file and line range that the NTSC implementation (issue #181) touches, grouped by worker. Line numbers refer to branch `ntsc` at commit `91f8164` and the submodule `CORE/C64_MiSTerMEGA65` at `650c6b5`; the names are authoritative, the numbers are orientation aids. Section numbers refer to `doc/dev-ntsc/NTSC-SPEC.md`.

## W1: clocks and switching

| File | Lines | Change | Spec |
|---|---|---|---|
| `CORE/vhdl/clk.vhd` | 1-41 | Header: replace the `NTSC: @TODO` lines with the four clocks and their frequencies | 3.3 |
| `CORE/vhdl/clk.vhd` | 57-66 | Comment of `core_speed_i`: encoding `00` PAL original, `01` PAL flicker-free, `10` NTSC original, `11` NTSC flicker-free (port unchanged) | 3.5 |
| `CORE/vhdl/clk.vhd` | 75-84 | New signals `main_fb_mmcm_ntsc`, `main_clk_mmcm_ntsc`, `main_locked_ntsc`, `main_fb_mmcm_ntsc_ff`, `main_clk_mmcm_ntsc_ff`, `main_locked_ntsc_ff`, `main_clk_pal`, `main_clk_ntsc` | 3.6 |
| `CORE/vhdl/clk.vhd` | after 193 | New MMCMs `i_clk_c64_ntsc` (36 / 5 / 22) and `i_clk_c64_ntsc_ff` (47.75 / 5 / 29.125), copies of `i_clk_c64_orig` otherwise | 3.3, 3.6 |
| `CORE/vhdl/clk.vhd` | 195-203 | `bufgmux_ctrl_inst` becomes `bufgmux_pal_inst`; new `bufgmux_ntsc_inst` and `bufgmux_mode_inst` (2-level tree) | 3.6 |
| `CORE/vhdl/clk.vhd` | 219-229 | `src_arst` from all four `LOCKED` outputs | 3.7 |
| `CORE/vhdl/globals.vhd` | 48-51 | `CORE_CLK_SPEED_NTSC := 32_727_273`, remove the `@TODO`; `CORE_CLK_SPEED` stays PAL | 3.3, 5.5 |
| `CORE/CORE.xdc` | 5-9 | Case analysis `1` on `hr_core_speed_reg[0]` and `[1]`; `main_clk` on `i_clk_c64_ntsc_ff/CLKOUT0` | 3.8 |
| `CORE/signoff_gates.tcl` | 14-31 | Gates for both case-analysis pins, the new source pin and the 30.497 ns period (tolerance 0.03 ns) | 3.8 |
| `CORE/vhdl/mega65.vhd` | 262-263 | `c64_ntsc`, `c64_clock_speed` (existing declarations, now driven) | 4.1 |
| `CORE/vhdl/mega65.vhd` | 329 | `hr_core_speed` plus `dont_touch` attribute | 3.8 |
| `CORE/vhdl/mega65.vhd` | 385 | Next to `hr_hdmi_ff`: new `hr_ntsc`, new `main_hdmi_ff` | 4.1, 4.2 |
| `CORE/vhdl/mega65.vhd` | 419, 432-434 | Remove the "not yet wired" comments of the machine mode and NTSC HDMI constants (values unchanged; turbo and raw 50.1 Hz stay unwired) | 4.3 |
| `CORE/vhdl/mega65.vhd` | 565-577 | `clk_gen` comment (four clocks) | 4.4 |
| `CORE/vhdl/mega65.vhd` | 585-601 | New `hr_core_speed` process with the NTSC polarity | 4.2 |
| `CORE/vhdl/mega65.vhd` | 674 | `c64_ntsc <= main_osm_control_i(C_MENU_MACHINE_NTSC)` | 4.1 |
| `CORE/vhdl/mega65.vhd` | 682-683 | `c64_clock_speed` mode-dependent; new `main_hdmi_ff` decode | 4.1 |
| `CORE/vhdl/mega65.vhd` | 1036-1041 | `qnice_video_mode_o` decode with the three `*_5994` members | 4.3 |
| `CORE/vhdl/mega65.vhd` | 1222-1236 | `i_cdc_main2hr` with `G_DATA_SIZE => 2` (`main_hdmi_ff`, `c64_ntsc`) | 4.2 |

## W2: video

| File | Lines | Change | Spec |
|---|---|---|---|
| `M2M/vhdl/av_pipeline/video_modes_pkg.vhd` | after 168 (behind `C_HDMI_720p_60`) | New record `C_HDMI_720p_5994` (`CLK_KHZ 74167`, `CLK_SEL "110"`, VIC 4) | 6.1 |
| `M2M/vhdl/av_pipeline/video_modes_pkg.vhd` | 190-198 | Append `C_VIDEO_HDMI_16_9_5994`, `C_VIDEO_HDMI_4_3_5994`, `C_VIDEO_HDMI_5_4_5994` to `video_mode_type` | 6.1 |
| `M2M/vhdl/av_pipeline/video_modes_pkg.vhd` | 200-204, 208-233 | Codes `"0111"`, `"1000"`, `"1001"` in both conversion functions; new `video_mode_is_ntsc` (declaration and body) | 6.1 |
| `M2M/vhdl/framework.vhd` | 277-284 | `VIDEO_MODE_VECTOR(0 to 9)` with indices 7, 8, 9 | 6.2 |
| `M2M/vhdl/framework.vhd` | 499-505 | Clock-select decode `video_mode <= ...` for the three new members | 6.2 |
| `M2M/vhdl/av_pipeline/digital_pipeline.vhd` | 179-185 | `hdmi_video_mode` selection for indices 7, 8, 9 | 6.3 |
| `M2M/vhdl/av_pipeline/digital_pipeline.vhd` | 196-202 | Assertions for indices 7, 8, 9 | 6.3 |
| `M2M/vhdl/av_pipeline/digital_pipeline.vhd` | 204-245 | `hdmi_hmin/hmax/vmin/vmax` rows for the three new members (5:4 480p: 15 .. 465) | 6.3 |
| `M2M/vhdl/av_pipeline/digital_pipeline.vhd` | 456-488 | `i_video_overlay`: drive `vga_cfg_vshift_i` with 24 for the two 480p NTSC modes, else 0 | 7.4 |
| `M2M/vhdl/av_pipeline/video_overlay.vhd` | 26-30, 103-105 | New port `vga_cfg_vshift_i : in natural := 0`, added to `stage1.vga_row` | 7.4 |
| `M2M/vhdl/av_pipeline/crop.vhd` | 13-39, 41-58, 96 | New port `video_ntsc_i`; NTSC constant set (`LEFT_BORDER_IN 44`, `TOP_BORDER_IN 26`), `X_MIN..Y_MAX` selected by it | 6.7 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 159-170 | New signals `qnice_ntsc`, `video_ntsc`, `hdmi_osm_ntsc480` | 6.8, 7.4 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 250-260 | New function `osm_scaling` behind `first_nonzero_bit` | 7.4 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 268-295 | `i_qnice2video`: `WIDTH => 47`, bit 46 = `qnice_ntsc` to `video_ntsc` | 6.8 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 436 | `video_osm_cfg_scaling_i => osm_scaling(video_osm_cfg_scaling, video_ntsc)` | 7.4 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 506-527 | `i_crop`: `video_ntsc_i => video_ntsc` | 6.7 |
| `M2M/vhdl/av_pipeline/av_pipeline.vhd` | 571 | `hdmi_osm_cfg_scaling_i => osm_scaling(hdmi_osm_cfg_scaling, hdmi_osm_ntsc480)` | 7.4 |
| `M2M/vhdl/controllers/HDMI/video_out_clock.vhd` | 58 | Comment only: `110` is 74.176 MHz nominal, 74.1667 MHz actual | 6.4 |
| `M2M/vhdl/hdmi_flicker_free.vhd` | none | No change (thresholds and polarity of `high_o` / `low_o` stay) | 9.2 row 12 |
| `M2M/common.xdc` | none | No change | 3.8 |

## W3: core and docs

| File | Lines | Change | Spec |
|---|---|---|---|
| `CORE/vhdl/main.vhd` | 54-58 | Port comments of `c64_ntsc_i` / `clk_main_speed_i` (ports unchanged) | 5.2 |
| `CORE/vhdl/main.vhd` | 717-770 | RESET SEMANTICS: document the mode-change reset as a fourth soft-reset source; new declarations `C_MODE_RST_LEN`, `ntsc_d`, `mode_rst_pending`, `mode_rst_counter`, `mode_reset` | 8.2 |
| `CORE/vhdl/main.vhd` | 970-972 | `cart_soft_reset <= (cart_soft_reset_i or mode_reset) and not prevent_reset` | 8.2 |
| `CORE/vhdl/main.vhd` | 1043-1071 | `hard_reset_proc` condition gets `or mode_reset = '1'`; new `mode_change_reset_proc` next to it | 8.2 |
| `CORE/vhdl/main.vhd` | 1190-1194 | Comment of the VGA/SCART block (PAL and NTSC line rates) | 5.2 |
| `CORE/vhdl/main.vhd` | 1874-1893 | `video_sync_inst`: `ntsc => c64_ntsc_i`; comment 382 x 270 / 404 x 250 | 5.1 |
| `CORE/vhdl/main.vhd` | 2646-2655 | Comment above `iec_drive_ce_proc`: vanilla value of the active standard (process unchanged) | 5.3 |
| `CORE/vhdl/main.vhd` | 2815-2828 | `rtcf83_inst`: `CLOCK_RATE => 16_000_000`, `ce => iec_drive_ce` | 5.4 |
| `CORE/vhdl/config.vhd` | 133 | Help text "run the core at 50 Hz": mention 59.94 Hz for NTSC (string only, no menu change) | 9.1 |
| `CORE/vhdl/config.vhd` | 456, 476-484 | Remove the "not yet wired" comments of the NTSC Model / HDMI items (the turbo and Raw 50.1 Hz comments at 460 and 502 stay true; strings unchanged) | 9.1 |
| `CORE/vhdl/config.vhd` | 643, 646, 647 | Group-ID comments of `OPTM_G_MACHINE_MODE`, `OPTM_G_HDMI_MODES_NTSC`, `OPTM_G_HDMI_FF_NTSC` | 9.1 |
| `CORE/m2m-rom/*.asm`, `M2M/rom/*.asm` | none | No change expected (`SUBMENU_SUMMARY` already handles PAL / NTSC) | 9.3 |
| `tests/README.md` | before line 8 | New section `Version WIP-V6-A22 - TBD` with the hardware tests of spec 10.5 | 10.5 |
| `doc/wip-thoughts-on-ntsc.md` | top | Pointer to `doc/dev-ntsc/NTSC-SPEC.md` as the implemented design | 9.1 |
| `ROADMAP.md` | 12 | NTSC entry: in progress in WIP-V6-A22 | 9.1 |
| `doc/hdmi.md`, `doc/speed.md`, `doc/clock_reset.md`, `doc/models.md` | sections on clocks and HDMI modes | NTSC clocks, flicker-free polarity, mode-change reset | 3, 4, 8 |

## Not touched by anyone

- `CORE/C64_MiSTerMEGA65/**` (submodule): no change needed (spec section 2).
- `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd`: no new port on `MEGA65_Core` or `framework`.
- `CORE/vhdl/config.vhd` menu structure (`OPTM_ITEMS` lines, `OPTM_GROUPS`, `OPTM_SIZE`, `OPTM_DX`, `OPTM_DY`) and every `C_MENU_*` index: the config-file format stays.
- `doc/dev-ntsc/tools/analyze.sh`, `doc/dev-ntsc/tools/ff_model.py`, `CORE/vhdl/test/tb_ntsc/*`: shared verification harness.
