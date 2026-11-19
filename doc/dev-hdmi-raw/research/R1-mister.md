# R1: How MiSTer outputs the native frame rate of a core on HDMI

Subject: the `vsync_adjust` option of `MiSTer.ini` (and its neighbor, VRR), end to end, and what it means for an HDMI mode with the native C64 frame rate on the MEGA65 (issues #148 and #184).

Legend used below: **[src]** = verified in source code (file and line given), **[calc]** = computed from the sources, **[doc]** = official MiSTer documentation, **[field]** = forum post or GitHub issue (anecdotal).

## 0. Sources and versions

| Source | Version | Notes |
| --- | --- | --- |
| `CORE/C64_MiSTerMEGA65/sys/` (local) | last touched by commit `c70ca67` "Update sys." of 2021-06-18 (later commits only fixed Vivado errors, July 2021) | `ascal.vhd` 2564 lines ("TEMLIB 2018 - 2020"), `pll_hdmi_adj.vhd`, `hps_io.sv`, `hdmi_config.sv` (the FPGA still configured the ADV7513 itself then) |
| `M2M/vhdl/av_pipeline/ascal.vhd` (the copy we synthesize) | imported 2023-05-23 (`15cec30`) | 2915 lines, newer than the `sys/` copy, no VRR |
| `MiSTer-devel/Template_MiSTer` `sys/` | master, 2026-10 (`sys_top.v` `afd78087` 2026-10-16, `ascal.vhd` `baaeff60` 2026-08-22) | `pll_hdmi_adj.vhd` unchanged since the initial commit of 2020-04-28 and byte-identical to our local copy; `hdmi_config.sv` no longer exists (the HPS configures the ADV7513) |
| `MiSTer-devel/Main_MiSTer` | master, `video.cpp` `2bc93a9b` 2026-10-27 | `video.cpp` 4615 lines, `MiSTer.ini` |
| `MiSTer-devel/C64_MiSTer` | master | `c64.sv` 1779 lines |
| MkDocs_MiSTer | main | `docs/basics/video.md`, `docs/advanced/lag.md`, `docs/advanced/ini.md` |

All line numbers below refer to these versions. Upstream files were read from raw.githubusercontent.com.

## 1. The mechanism in one paragraph

MiSTer never touches the clock of the core. The FPGA counts the length of one core frame with a 100 MHz counter; the ARM side (Linux program `MiSTer`, file `video.cpp`) reads that count whenever the core reports a new resolution, takes the HDMI mode that is configured as base mode, keeps **all its totals, porches and sync widths**, and computes the pixel clock that makes this mode's frame period equal to the measured core frame period: `Fpix[MHz] = 100 * htotal * vtotal / vtime`. It then programs the Cyclone V fractional PLL of the HDMI clock (`Fvco = 50 MHz * (M + K/2^32)`, `Fpix = Fvco / C`) through the PLL reconfiguration IP. That is `vsync_adjust=1`: the HDMI frame rate equals the core frame rate to well below 1 ppm in theory (the wiki says a frame is repeated or dropped "once per couple hours"), the phase between input and output frames is arbitrary, and ascal keeps triple buffering. `vsync_adjust=2` additionally switches ascal to a single buffer and enables `pll_hdmi_adj.vhd`, a hardware control loop that keeps rewriting the fractional part `K` every 8 input frames so that the output image is phase-locked about 4 input lines behind the input image.

## 2. Measuring the core frame period

**[src]** `hps_io.sv`, module `video_calc` (local copy lines 802-935; upstream line 911 ff., unchanged in substance):

- `vid_vtime`: process on `clk_100` (local `hps_io.sv:884-917`) counts clock cycles between two rising edges of the core VSYNC (`vs`, which is `hvs_fix`, the core video before the scaler, see `sys_top.v:1511-1513`). It is one frame (one field for interlaced cores), not an average.
- `clk_100` is `clk_100m`, the HPS user clock `h2f_user0_clk` (`sysmem.sv:191`, `sys_top.v:518-525`). Resolution 10 ns: one tick is 0.50 ppm of a 50 Hz frame and 0.60 ppm of a 59.8 Hz frame **[calc]**. Whether this HPS clock and the 50 MHz FPGA clocks of the DE10-Nano come from the same oscillator is not documented anywhere I could find (one Si5350 is likely).
- `vid_vtime_hdmi`: the same count for the HDMI VSYNC (`HDMI_TX_VS`), used only for the info display and VRR.
- New-resolution detection (`hps_io.sv:844-878`): on the core clock, `hcnt`/`vcnt` are counted per frame; when they or the core input `new_vmode` change, a 4-bit timeout `resto` starts, and after about 14 further frames `vid_nres` is incremented. Main polls `UIO_GET_VRES` (`video.cpp:2867-2927`) and acts only when `vid_nres` changed (`res_changed`), then reads `vtime` once (`video.cpp:2884`).

Consequence: the pixel clock is computed **once per resolution change** from **one frame period sampled at that moment**. There is no continuous re-measurement in modes 0 and 1.

## 3. `vsync_adjust` 0, 1 and 2 end to end

### 3.1 Settings (MiSTer.ini, lines 116-144) **[src]**

```text
; Set to 1 for automatic HDMI VSync rate adjust to match original VSync.
; Set to 2 for low latency mode (single buffer).
; This option makes video butter smooth like on original emulated system.
; Adjusting is done by changing pixel clock. Not every display supports variable pixel clock.
; For proper adjusting and to reduce possible out of range pixel clock, use 60Hz HDMI video
; modes as a base even for 50Hz systems.
vsync_adjust=0
...
; ... then you can set refresh_min and/or refresh_max
; parameters, so neither vsync_adjust nor VRR will be applied for refreshes outside specified.
refresh_min=0
refresh_max=0
; You need to supply both PAL and NTSC modes if you want vsync_adjust to switch between
; predefined modes as a base. This will reduce the range of pixel clock.
;video_mode_ntsc=0
;video_mode_pal=7
```

`video_vsync_adjust()` returns 0 when `direct_video` is on (`video.cpp:97-100`).

### 3.2 Mode 0

Main does nothing beyond the configured `video_mode` at its standard pixel clock. `video_mode_pal` / `video_mode_ntsc` are ignored (`video_mode_select`, `video.cpp:3145-3149`, "using default mode"). ascal runs with triple buffering (`mode(3) = 1`, see 4.6) and drops or repeats a frame whenever the free-running input and output drift past each other: for the C64 PAL core on a 50.000 Hz output every `1 / 0.124 Hz` = about 8 s **[calc]**; on a 60 Hz output about every fifth output frame is a repeat.

### 3.3 Modes 1 and 2: Main side (`video_mode_adjust`, `video.cpp:3417-3559`)

Triggered when the core reports a new resolution and the menu core is not running (`video.cpp:3445`, `3467`):

1. **Base mode** (`video_mode_select`, `video.cpp:3138-3188`): if `video_mode_pal` or `video_mode_ntsc` is configured, `vtime > 1800000` (frame longer than 18 ms, i.e. below 55.6 Hz) picks the PAL mode, otherwise the NTSC mode. If only one of the two is configured and the core belongs to the other standard, that one mode is used **without adjustment** (`adjustable = false`). If neither is configured, the default `video_mode` is adjusted.
2. **Pixel clock** (`video.cpp:3482-3483`):

    ```cpp
    Fpix = 100 * (v->item[1] + v->item[2] + v->item[3] + v->item[4]) * (v->item[5] + v->item[6] + v->item[7] + v->item[8]);
    Fpix /= vtime;
    ```

    `item[1..4]` are hact, hfp, hs, hbp, `item[5..8]` vact, vfp, vs, vbp of the base mode: the totals stay those of the standard mode, only the pixel clock moves. (Exception in mode 2, see step 4.)
3. **Limits** (`video.cpp:3484-3501`): `Fpix` outside 2 to 300 MHz, or the frame rate `1e8 / vtime` below `refresh_min` or above `refresh_max`, sets `Fpix = 0` ("Canceling auto-adjust"). There is no other limit on the deviation from the nominal rate in Main.
4. **Mode 2 only, integer guard** (`video.cpp:3504-3522`, `pll_request_on_integer` at `278-295`, `PLL_INT_GUARD_PPM 10.0`): if the requested clock would put the PLL into integer mode (K equal to 0, or within 10 ppm of an integer M), up to 8 lines are added to the vertical front porch until a fractional solution exists. Reason: `pll_hdmi_adj` can only tune via K.
5. `video_set_mode(v, Fpix)` (`video.cpp:2242-2343`): `if (Fpix) setPLL(Fpix, &v_cur);` then the 8 timing words and the 6 PLL (address, data) pairs go to the FPGA with `UIO_SET_VIDEO` (command `0x20`). The first PLL address word carries bit 15 = low latency (`i == 9 && Fpix && video_vsync_adjust() == 2 && !is_menu()`) and bit 14 = "HPS configured the HDMI chip" (`video.cpp:2327`). Then `hdmi_config_set_mode` writes the AVI InfoFrame over I2C with the **VIC of the base mode** (register `0x3C`, `video.cpp:1730-1751`).

**What happens when the rate is refused:** `Fpix = 0`, so `setPLL` is skipped and the base mode keeps the PLL parameters computed for its nominal clock when it was loaded (`setPLL(vmodes[mode].Fpix, v)`, `video.cpp:2447`); the low-latency bit is not set either (it requires `Fpix` non-zero). The result is mode 0 behavior: nominal rate, triple buffering. Nothing is shown to the user except the log line.

### 3.4 PLL parameters (`findPLLpar` and `setPLL`, `video.cpp:240-350`) **[src]**

- `C` starts at the smallest integer with `Fout * C >= 400` MHz (VCO minimum). `M = floor(Fvco / 50)`, `K = Fvco/50 - M`. If K is in `(0, 0.05]` or `[0.95, 1)`, C is incremented (Cyclone V fractional PLL restriction), up to `Fvco <= 1500` MHz.
- If no C works, the fallback rounds K to 0 (or M up), i.e. integer mode with a frequency error of up to `0.05 * 50 MHz / 400 MHz` = 0.625 % **[calc]**, printed only to the log.
- K is written as `(uint32_t)(ko * 4294967296)` (32-bit fraction): the frequency granularity is `50 MHz / 2^32 / C`, about `1e-11` relative, i.e. exact for all practical purposes. The total error of mode 1 is therefore set by the measurement (0.5 ppm quantization plus any offset between the HPS clock and the PLL reference), not by the PLL.
- Register pairs (`item[9..20]`): `(4, M counter)`, `(3, N = 0x10000 bypass)`, `(5, C counter)`, `(9, charge pump 2)`, `(8, bandwidth 7)`, `(7, K)`. M and C are written as high/low counts by `getPLLdiv` (odd values set bit 17).

### 3.5 FPGA side (`sys_top.v`) **[src]**

- Command `0x20` decoder: local `sys_top.v:371-403`, upstream `sys_top.v:419-450`. Words 0..7 are WIDTH (upstream: plus bit 15 pixel repetition, bit 14 `vrr_mode`), HFP, HS (bit 15 polarity), HBP, HEIGHT, VFP, VS (bit 15 polarity), VBP. Then the PLL pairs; the first address word sets `{lowlat, cfg_dis}` (local, `sys_top.v:400`) or `{lowlat, cfg_done}` (upstream `447`).
- ascal gets the totals directly: `htotal = WIDTH + HFP + HBP + HS`, `vtotal = HEIGHT + VFP + VBP + VS`, etc. (local `sys_top.v:671-682`).
- The PLL pairs are passed **through** `pll_hdmi_adj` (its `Comb` process forwards `i_write`/`i_address`/`i_writedata` to `pll_cfg`, `pll_hdmi_adj.vhd:240-252`), which snoops addresses 4 and 7 to learn the base M and K (`pll_hdmi_adj.vhd:269-285`).
- The reconfiguration "start" write (address 2) is issued on the rising edge of `cfg_got`, and once the system has been configured `cfg_got` only follows `cfg_set` on a rising edge of `HDMI_TX_VS` (local `sys_top.v:977-1015`, upstream `1086-1110`): mode changes take effect at an output VSYNC.
- The HDMI PLL is compiled for 148.5 MHz (`sys/pll_hdmi/pll_hdmi_0002.v:30`, fractional VCO, 32-bit `pll_fractional_cout`), from `FPGA_CLK1_50`. Timing analysis uses this compiled frequency (`sys_top.sdc` `derive_pll_clocks`, exclusive clock group for `pll_hdmi`).

### 3.6 Numbers for the C64 **[calc]**

Our clocks (`CORE/vhdl/globals.vhd:60-61`, `clk.vhd:133`, `240`): PAL `31.527778 MHz / 32 / (63 * 312)` = **50.124291 Hz** (period 19.950407 ms, `vtime` about 1995041), NTSC `32.727273 MHz / 32 / (65 * 263)` = **59.826105 Hz** (16.715111 ms, `vtime` about 1671511). The MiSTer core: PAL 50.124571 Hz (`clk_sys` 31.527954 MHz), NTSC 59.826089 Hz; the difference to ours is 5.6 ppm (PAL).

Pixel clock MiSTer would set (MiSTer's `vtime`, same totals as the base mode):

| Base mode (totals) | PAL core (50.1243 Hz) | NTSC core (59.8261 Hz) |
| --- | --- | --- |
| 720p50, 1980 x 750, nominal 74.25 MHz | 74.4346 MHz (+0.249 %) | 88.8418 MHz (+19.65 %) |
| 720p60, 1650 x 750, nominal 74.25 MHz | 62.0288 MHz (-16.46 %) | 74.0348 MHz (-0.290 %) |
| 1080p50, 2640 x 1125, nominal 148.5 MHz | 148.8691 MHz (+0.249 %) | 177.6835 MHz (+19.65 %) |
| 1080p60, 2200 x 1125, nominal 148.5 MHz | 124.0576 MHz (-16.46 %) | 148.0696 MHz (-0.290 %) |
| 576p50, 864 x 625, nominal 27 MHz | 27.0671 MHz (+0.249 %) | 32.3061 MHz (+19.65 %) |
| 480p, 858 x 525, nominal 27 MHz | 22.5785 MHz (-16.38 %) | 26.9487 MHz (-0.190 %) |

With the "right" base mode the deviation is +0.249 % (PAL from 50 Hz) or -0.290 % (NTSC from 60 Hz), -0.190 % from 59.94 Hz. The `MiSTer.ini` advice ("use 60Hz HDMI video modes as a base even for 50Hz systems") produces the -16.5 % rows: a 1650 x 750 (or 2200 x 1125) frame at 50.12 Hz, announced with VIC 4 (or 16) = 720p60 (1080p60). The reason for the advice: with a 50 Hz base, 60 Hz cores push the clock up by about 20 % (1080p to 177.7 MHz, above the 165 MHz of the ADV7513).

## 4. Low latency (`vsync_adjust=2`): `pll_hdmi_adj.vhd` in detail

File identical locally and upstream (433 lines). Instantiated at local `sys_top.v:888-905` (upstream `998-1015`), clock `FPGA_CLK1_50` (50 MHz), `llena = lowlat`, `lltune` masked to zero until the HDMI chip is configured (`{16{hdmi_config_done | cfg_dis}}` locally, `{16{cfg_done}}` upstream).

### 4.1 Inputs: `o_lltune` of ascal **[src]**

`M2M/vhdl/av_pipeline/ascal.vhd:2904-2912` (identical mapping in the `sys/` copy line 2553 and upstream line 3038):

| Bit | Signal | Meaning |
| --- | --- | --- |
| 0 | `i_vss` | input image window: `i_vcpt` between `i_vmin` and `i_vmax` (`ascal.vhd:1224`), i.e. the active lines of the input |
| 1 | `i_pde` | input display enable |
| 2 | `i_inter` | input is interlaced |
| 3 | `i_flm` | input field |
| 4 | `o_vss` | output image window: `o_vcpt_pre2` between `o_vmin` and `o_vmax` (`ascal.vhd:2702`), i.e. the lines where the scaled picture sits inside the output frame (two lines ahead of the output counter) |
| 5 | `i_pce` | input pixel clock enable |
| 6 | `i_clk` | input clock |
| 7 | `o_clk` | output clock |

The header comment of `pll_hdmi_adj.vhd` (lines 7-15) swaps bits 0 and 1 and calls bit 5 unused; the code (`pll_hdmi_adj.vhd:86-89`) matches the ascal mapping above, so the header comment is stale.

### 4.2 What it measures **[src]**

- `Delay` process (`pll_hdmi_adj.vhd:91-118`, input clock domain): `i_line` = length of one input line in `i_ce` cycles (DE edge to DE edge, sampled inside the image); `i_vss_delay` is `i_vss` delayed by `4 * i_line` cycles = **4 input lines**.
- `Sampler` process (`122-233`, 50 MHz), after a two-flop synchronizer of `i_vss_delay` and `o_vss`:
  - `icpt` / `osizep`: 50 MHz ticks between **every second** rising edge of the input / output image window (`itog`, `otog` toggles), i.e. the length of two frames (two fields for interlaced cores). For PAL that is about 1,995,040 ticks.
  - `udiff = osizep - icpt` (signed): output minus input two-frame period, resolution 1 tick = 0.5 ppm **[calc]**.
  - `ifsize`, `ofsize`: duration of the input and output image windows. `expand = (ofsize >= ifsize)` (output picture takes longer than the input picture, the normal upscaling case).
  - `offset`: if `expand`, the time from the start of the output image to the start of the (delayed) input image; otherwise from the end of the output image to the end of the input image. Measured modulo the two-frame period `osize`.
  - Log2 quantization (`198-230`): `ssh` starts at `osize` and is halved 24 times; `tune_freq = (sign, k)` with k the first step where `osize / 2^k < |udiff|` (sign 0 when the output is slower), `tune_phase` likewise for `offset` (sign 0 when `offset < osize/2`) or for `osize - offset` (sign 1). `pulse` fires after the 24 steps, once per two input frames. If `|udiff|` is below `osize / 2^23`, `tune_freq` is not updated and keeps its old value.

### 4.3 Control law (`Schmurtz`, `257-428`) **[src]**, gains **[calc]**

- `mfrac` (41 bits) is `M.K`: bits 40..32 the integer M (sum of high and low count), bits 31..0 the fraction K. `mfrac_mem` holds the value Main wrote, `mfrac_ref` the current frequency reference.
- Every **fourth** `pulse`, i.e. every **8 input frames** (160 ms at 50 Hz), one step is taken (`cpt`, line 304). The clamped exponents are `off_v = max(4, tune_freq)` and `ofp_v = max(4, tune_phase)`.
- **Frequency mode** (`phm = 0`, lines 316-330): `mfrac_ref := mfrac_ref +/- (mfrac_ref >> n)` with `n = off_v + 1`, or `off_v + 4` when `off_v + 1 > 17`. Since `off_v` is about `log2(osize / |udiff|)`, the relative step is between 1/4 and 1/2 of the measured relative frequency error, at most `2^-5` = 3.1 %. Both `mfrac` and `mfrac_ref` take the new value (a permanent correction). The loop stays in this mode for at least 10 steps and until `off_v >= 16` (frequency error at most `2^-15` = 30 ppm), then switches to phase mode.
- **Phase mode** (`phm = 1`, lines 332-354): `mfrac := mfrac_ref +/- (mfrac_ref >> n)` with `n = ofp_v + 1`, plus 1 if `ofp_v > 7`, plus 2 more if `ofp_v > 14`, plus 3 more if `ofp_v > 17`; `mfrac_ref` is not changed. This is a temporary frequency offset held for 8 frames that slides the output phase. Per step it removes roughly 1 to 2 times the measured phase error while `ofp_v <= 7`, 1/2 to 1 times up to 14, 1/8 to 1/4 up to 17 and 1/64 to 1/32 above (my reading of the code). After 10 phase steps it returns to `mfrac_ref` (`off_v := 31`, negligible) and to frequency mode. So the loop alternates: at least 10 frequency steps (1.6 s), 10 phase steps (1.6 s), and so on.
- Phase target: `offset` towards 0 (modulo two output frames): the delayed input image start coincides with the output image start (`expand`), or the input image end with the output image end (not `expand`). Effective latency: 4 input lines plus pipeline; the docs say "about 4 scanlines" and "4 to 30 lines of lag when using vscale_mode=1" (`docs/advanced/lag.md`) **[doc]**.
- **Lock** (`296-300`): `locked = llena` when `off_v >= 18` and `ofp_v >= 18`: frequency error at most `2^-17` (7.6 ppm, about 15 ticks) and phase error at most `osize / 2^17` (about 0.3 µs). It only drives `led_locked`; nothing else depends on it.
- **PLL writes** (`374-425`): on `up`, if the integer part changed write the M counter (address 4, high count `M/2`, low count `M/2 + (M mod 2)`), then K (address 7), then start (address 2). Three Avalon writes per step, i.e. about 6 reconfigurations per second at 50 Hz, issued shortly after the delayed input image start, **not** aligned to the output blanking. This relies on the Cyclone V fractional PLL accepting a new K without losing lock.
- Leaving low latency (`llena = 0`, lines 305-314): `mfrac` returns to `mfrac_mem`, the value Main wrote.

### 4.4 Buffering mode **[src]**

`sys_top.v:684` (local) / `791` (upstream): `.mode({~lowlat, filter, 2'b00})`. ascal `MODE[3]`: `0` = "Direct. Single framebuffer", `1` = "Triple buffering" (`ascal.vhd:88-90`). In ascal (`M2M/vhdl/av_pipeline/ascal.vhd:1946-1952`) `o_mode(3) = '0'` forces all input and output buffer indices to 0, so the output reads the buffer the input is writing. Modes 0 and 1 therefore run triple-buffered, mode 2 single-buffered.

Triple buffering (`ascal.vhd:1895-1944`): the input switches to the next free buffer at its end of frame (`buf_next`), the output switches to the last completed buffer at the falling edge of its VSYNC. With equal rates and an arbitrary phase (mode 1), the latency is constant somewhere between about one and two frames, fixed at the moment the mode was set; a slip (repeat or drop) happens only when the slow residual drift carries the input end of frame across the output buffer switch.

### 4.5 What can go wrong in mode 2

- **Tearing** whenever the loop is not locked: the output read pointer can pass the input write pointer in the single buffer. Times: acquisition after every mode change, cores whose frame period jumps (interlace changes, menu, reset), or a mis-measured starting point. Issue Main_MiSTer #484 **[field]**: tearing every 4-5 s after a cold boot until the scaler settings were cycled, attributed to a wrong initial refresh calculation; a maintainer replied that the loop keeps adjusting regardless.
- **Pixel clock swings of up to 3 %** during acquisition (steps up to `2^-5`), which strict sinks may answer with a loss of sync.
- With `expand = 0` (output picture shorter than the input picture, e.g. downscaling) the ends are aligned instead of the starts; the loop then depends on the output catching up exactly at the end.
- Phase lock is modulo two frames (even output frame to even input frame), so the first lock may pull by up to one extra frame.
- Issue #1274 **[field]**: in mode 2 the live retuning when a core starts made an Elgato capture device drop HPD; while a core is held in reset the frame time counter "reads garbage".

## 5. ascal: our copy, the `sys/` copy, upstream, VRR

- `CORE/C64_MiSTerMEGA65/sys/ascal.vhd` (2564 lines) and `M2M/vhdl/av_pipeline/ascal.vhd` (2915 lines) are **different versions**: `diff -w` shows about 880 changed lines. The M2M copy is newer: generics `ADAPTIVE`, `DOWNSCALE_NN`, `FRAC` up to 8; port `o_brd` (border); 10-bit polyphase coefficients with four sets (`[Horizontal] [Vertical] [Horizontal2] [Vertical2]`, adaptive filtering); reworked horizontal/vertical output pipeline. The parts relevant here are functionally the same in both: `o_lltune` mapping, `i_vss`/`o_vss`, `MODE[3]`, triple-buffer logic. Neither copy has VRR.
- Upstream `ascal.vhd` (3049 lines) adds `vrr : IN std_logic` and `vrrmax : IN natural` (lines 224-225), plus `bob_deint`, a gray-code output handshake (2026-08) and a reset of `o_state` at VSYNC.
- **VRR in upstream ascal** (`ascal.vhd:1911-1937`, `2784-2843`): at every input end of frame `o_isync` resets `o_vcpt_sync`, a count of output lines since the last input frame end. During the vertical front porch of the output (`o_vcpt2` between `o_vdisp` and `o_vsstart`), if `vrr = '1'` and an input frame has ended (`o_sync`) or the input is faster than the shortest allowed output frame (`o_sync_max`), the output line counter jumps straight to `o_vsstart` (start of VSYNC). Otherwise the output runs to its full `vtotal`. The **vertical front porch is the stretched total**; the output frame starts one output line after the input frame ends (quantized to output lines).
- How Main sets it up (`video_set_mode`, `video.cpp:2266-2305`): the pixel clock is chosen so that the unstretched frame gives `vrr_max_fr` (`Fpix = horz * vert * vrr_max_fr`), and the VFP is extended by `vfp_vrr = Fpix / (vrr_min_fr * horz) - vert + 1` lines so that the fully stretched frame gives `vrr_min_fr`. `sys_top` passes `vrrmax = HEIGHT + VBP + VS + 1` (upstream `sys_top.v:787-788`). Defaults 47 to 62 Hz when the EDID gives nothing (`video.cpp:2176-2177`); "MiSTer VRR" (`vrr_mode=4`) uses the measured rate minus 1 Hz to plus 1.9 Hz (`video.cpp:3528-3535`).
- Signaling: AMD FreeSync as an SPD InfoFrame with the AMD OUI `0x00001A` and min/max rate (`video.cpp:2189-2202`), "Vesa Forum VRR" as a spare packet with VFP and base rate (`2209-2221`), "MiSTer VRR" sends nothing. VRR and `vsync_adjust` exclude each other (`video.cpp:2231`; MiSTer.ini: "vsync_adjust must be 0").

## 6. HDMI audio when the pixel clock moves

- **[src]** MiSTer feeds audio as I2S into the ADV7513, and both the old FPGA configuration (`sys/hdmi_config.sv:210-231`) and today's HPS configuration (`video.cpp:1464-1487`) write register `0x0A` = `0x00` and a fixed N of 6144 (12288 for 96 kHz) into `0x01..0x03`. The value "CTS 74250" in `0x07..0x09` is a manual value. Per the ADV7513 programming guide, bit 7 of `0x0A` selects automatic CTS when 0 (not re-checked in the datasheet here): the **transmitter chip measures CTS itself** against the actual TMDS clock, so MiSTer never has to compute N/CTS when the pixel clock moves, not even in mode 2 with K changing six times per second. The audio clock comes from a separate PLL (`pll_audio`, 24.576 MHz).
- **Our design is different** **[src]**: `M2M/vhdl/av_pipeline/digital_pipeline.vhd:304-305` sends N = 6144 and `CTS = hdmi_video_mode.CLK_KHZ`, a constant from the mode table, in Audio Clock Regeneration packets at 1 kHz from the audio clock. HDMI requires `CTS = f_TMDS * N / (128 * fs)`, which for N = 6144 and 48 kHz is the pixel clock in kHz. With a moved pixel clock the sink otherwise regenerates the wrong sample rate: 720p at 50.124 Hz is 74434.6 kHz; leaving CTS at 74250 makes the sink run its audio clock 0.25 % fast (48.119 kHz instead of 48 kHz), so its buffer runs dry periodically unless it has a sample rate converter **[calc]**. A native-rate mode needs its own CTS; since audio and video clocks come from the same crystal here, a constant (or a two-value dither for an exact long-term average, the spec allows CTS to vary) is exact; a hardware CTS counter like the ADV7513's (TMDS clocks per `N / (128 * fs)` audio periods) would also follow any live tuning.

## 7. The MiSTer C64 core itself

- **[src]** Nothing in `c64.sv` (local or upstream) concerns the HDMI frame rate. The only video options are "Video Standard PAL/NTSC" (upstream `c64.sv:93`) and the vertical crop for HDMI heights (`vcrop`, local `c64.sv:1217-1243`). `VGA_SCALER = 0`, `HDMI_BLACKOUT = 0`, `HDMI_BOB_DEINT = 0`; `HDMI_FREEZE` follows the core freeze (upstream `c64.sv:52-55`, `1296`).
- The core has its own fractional PLL and reprograms K when PAL/NTSC changes (local `c64.sv:278-349`; K = 1503512573 PAL, 3357876127 NTSC; the upstream version also rewrites the M counter, `'h404` / `'h20504`). `msum` = 31527954 / 32727264 is the clock speed for the RTC (upstream `c64.sv:1159-1166`). The PAL/NTSC switch resets the core (upstream `c64.sv:291`).
- The core does not drive `new_vmode`. A PAL/NTSC switch changes the number of lines per frame (312 versus 263), `video_calc` reports a new resolution after its timeout, and Main re-runs the adjustment (and picks `video_mode_pal` or `video_mode_ntsc` as base) on its own. No comment about 50.12 Hz exists in the core.

## 8. Field experience

- **[doc]** MiSTer wiki "HDMI Smooth output": "MiSTer measure the frame rate of emulated system and re-calculates the pixel clock on HDMI output"; "some (not all!) TVs and Monitors can accept arbitrary pixel clock"; "There still can be one frame repeat or drop but it will happen once per couple hours which is acceptable." (One slip per two hours at 50 Hz corresponds to a residual of about 2.8 ppm **[calc]**.)
- **[doc]** `docs/basics/video.md`: mode 1 "has 1 frame of lag, but it is less compatible with modern televisions"; mode 2 "is the least compatible mode and it may result in unplayable behavior on some televisions". FAQ: "Try setting vsync_adjust to 0 as your display may not support all refresh rates."
- **[field]** Main_MiSTer #644: a TV that "supports 60hz and 50hz and their close variations just fine, but nothing in-between"; with `refresh_min=49` / `refresh_max=61`, an arcade core at about 57 Hz gave "resolution not supported". The user asked for separate PAL/NTSC limits (49-51, 59-61); not implemented.
- **[field]** Main_MiSTer #753 (Samsung Q80R): with mode 1 a periodic stutter about every 10 s, which turned out to start only after switching TV inputs; maintainer: "Refresh rate is not the thing can be sent as a data. TV just measure it itself and tries to sync if possible." In mode 2 the same TV showed constant tearing near the bottom.
- **[field]** misterfpga.org (mail. mirror), Samsung Q80T and Q70: after a TV firmware update, modes 1 and 2 gave "frame skipping and weird tearing/ripples at the bottom of the screen"; toggling Game Mode off and on resynchronized the TV, needed again after each input change. The Q70 showed "Mode Not Supported" in mode 2 only with FreeSync on and content below 59.94 Hz (PAL games).
- **[field]** misterfpga.org, Samsung S95B OLED: judder "after a little while" with black frame insertion in all modes; one poster: on Samsung "it will judder periodically, as it can't sync" with modes 1 or 2; fixed by "Game Mode (Auto)". Another poster switched to a Vizio "that handles custom refresh rates".
- **[field]** misterfpga.org, Samsung flat panel: arcade cores at odd rates (Irem M62, about 56 Hz) "signal not recognised" / "This resolution is not supported" in modes 1 and 2.
- **[field]** misterfpga.org, Gigabyte G27Q monitor, Minimig: mode 1 produced an output rate that did not match the core (46.9 Hz for 59.4 Hz, 48.3 Hz for 49.9 Hz) until `video_mode_ntsc` / `video_mode_pal` were removed; no explanation given (a fallback to integer PLL mode or a wrong base mode would explain it).
- **[field]** LG CX reports are contradictory (some report correct native rates in mode 2, some needed a 60 Hz lock).
- Accepted deviation: no source states a sink tolerance. A ±0.5 % pixel clock tolerance attributed to CEA-861 is quoted by secondary sources only; the normative text could not be retrieved (unverified). The C64 needs +0.249 % (PAL from 50 Hz) and -0.290 % (NTSC from 60 Hz), -0.190 % from 59.94 Hz. The field picture is: many monitors and some TVs follow; Samsung TVs are the most frequent source of complaints (judder, tearing, "not supported"), often depending on Game Mode, FreeSync and input switching; TVs that do internal frame rate conversion stutter even though the signal is smooth.

## 9. Traps for a port

1. **One-shot, single-frame measurement.** Main computes the clock once per resolution change from one `vtime` sample taken about 14 frames after the change. A wrong sample (core in reset, loading, mode switching) stays in effect until the next change (#484, #1274). For us the C64 frame period is a compile-time constant of our own MMCM: no measurement is needed at all.
2. **Base-mode family.** The deviation is +0.25 % only if a 50 Hz base is used for PAL and a 60 Hz base for NTSC; otherwise it is -16 % or +20 %, an unusual timing, while the AVI InfoFrame keeps the VIC of the base mode. `video_mode_pal`/`video_mode_ntsc` are ignored in mode 0, and with only one of them configured the other standard is not adjusted.
3. **Silent fallbacks.** A refused rate (`refresh_min`/`refresh_max`, 2 to 300 MHz) falls back to the nominal clock; an unreachable PLL setting falls back to integer mode with up to 0.6 % error. Neither is visible to the user.
4. **Timing constraints.** Quartus analyzes the HDMI clock at its compiled 148.5 MHz while Main may move it above (1080p50 at 50.12 Hz is 148.87 MHz). In Vivado the HDMI clock must be constrained for the highest frequency of any table entry.
5. **Glitch-free retuning is a property of the Intel fractional PLL.** MiSTer aligns mode changes to an output VSYNC, but the low-latency loop rewrites K mid-frame six times per second and relies on the PLL staying locked. A Xilinx 7-series MMCM reconfigured through DRP must be reset and relocks (the header of `M2M/vhdl/controllers/HDMI/video_out_clock.vhd` says so): the TMDS clock stops and the sink loses sync. A live control loop in the style of `pll_hdmi_adj` therefore cannot be built with DRP on our FPGA. The only glitch-free fine knob of the MMCM is the dynamic phase shift (`PSINCDEC`), which MiSTer does not use (inference).
6. **Equal rate, arbitrary phase.** With triple buffering and equal rates the latency is constant but random between about one and two frames, fixed at mode set; residual drift moves the phase very slowly, and a slip happens when it crosses the buffer switch point. If the residual is not tiny, the phase sits near the switch point for a while and slips can come in bursts.
7. **Single buffer needs a lock.** Mode 2 tears whenever the loop is not locked; it also swings the pixel clock by up to 3 % during acquisition.
8. **Audio.** MiSTer gets CTS for free from the ADV7513; our encoder sends a constant CTS from the mode table, which must match the moved clock (section 6).
9. **The HPS measures, the FPGA generates.** `vtime` is counted with the HPS 100 MHz clock while the PLL uses the 50 MHz FPGA reference; any offset between them is a residual error of mode 1 (not documented whether they share an oscillator).

## 10. What this means for C64MEGA65

- The C64 frame rate is known exactly in advance (50.124291 Hz and 59.826105 Hz). A native-rate mode is a static mode-table entry: base totals of a standard 50 Hz (PAL) or 60 Hz (NTSC) mode, pixel clock moved by +0.249 % / -0.290 %, CTS adjusted, VIC kept (as MiSTer does) or a decision to be made.
- How precisely a 7-series MMCM from the 100 MHz board clock reaches those clocks **[calc]**, VCO 600 to 1440 MHz, PFD at least 10 MHz, M in 1/8 steps:

    | Target pixel clock | Pixel clock on fractional CLKOUT0 | Our structure: 5x clock on CLKOUT0, pixel clock on integer CLKOUT1 = 5 x CLKOUT0 |
    | --- | --- | --- |
    | 720p50 totals at PAL, 74.434572 MHz | D 5, M 53.5, O 14.375: +2.8 ppm (slip every 2 h) | D 3, M 33.5, O 15: +133 ppm (slip every 2.5 min) |
    | 576p50 totals at PAL, 27.067117 MHz | +0.8 ppm (7 h) | +159 ppm (2.1 min) |
    | 720p60 totals at NTSC, 74.034805 MHz | +3.8 ppm (73 min) | +374 ppm (45 s) |
    | 480p totals at NTSC, 26.948669 MHz | -1.1 ppm (4.3 h) | -157 ppm (1.8 min) |

    Both clocks come from the same 100 MHz crystal as the C64 clock, so these are the complete residuals (no crystal drift). With the current HDMI clock structure a single MMCM gives a slip every one to three minutes, much worse than MiSTer; ppm-level accuracy needs a fractional pixel divider (and another source for the 5x clock, e.g. a cascaded MMCM) or another trick.
- Ways to close the remaining gap, in the order of how much MiSTer evidence exists for them: (a) as MiSTer mode 1, accept a slip every hour or more once the clock is within a few ppm; (b) as MiSTer VRR, absorb the residual in the vertical front porch (frame length quantized to output lines; a non-VRR sink sees `vtotal` change by one line now and then); (c) the reverse of MiSTer: keep the HDMI clock fixed near the native rate and let the existing flicker-free machinery lock the C64 to it with a second core clock that brackets the HDMI rate (the C64 would then run a few hundred ppm off on average); (d) exact by construction: choose totals so that the HDMI frame is a whole number of pixels of a clock derived from the C64 MMCM, for example `1920 x 756` total at `945.833 MHz / 13 = 72.756 MHz` is exactly one PAL C64 frame (`1451520 * 13 = 18869760 = 30 * 628992`), but the 5x serializer clock would be `VCO / 2.6`, which needs a second MMCM.
- A live phase-locking loop like `pll_hdmi_adj` (MiSTer mode 2) is not portable as is: it depends on glitch-free fractional retuning. Low latency on our side would have to come from making the C64 and HDMI clocks frame-locked by construction and then switching ascal to `MODE[3] = 0` with a fixed, designed phase.
- Display compatibility will be the same as MiSTer's mode 1: monitors mostly fine, TVs mixed (Samsung most problematic, Game Mode settings matter). The mode must be an option, never the default, with the standard 50/60 Hz mode as fallback.
