# R4: Display compatibility of an HDMI mode at the native C64 frame rate

Subject: which way of building an HDMI signal at 50.1246 Hz (PAL) and 59.8261 Hz (NTSC) has the best chance of being accepted, and shown smoothly, by the largest number of HDMI sinks (issues #148 and #184). The options compared:

- **(a)** standard CTA-861 totals, pixel clock shifted (MiSTer `vsync_adjust`);
- **(b)** standard pixel clock, totals changed (H total, or one line more or less);
- **(c)** another pixel clock and other totals;
- **(d)** a genlock that keeps the totals on average but modulates them: some lines one pixel longer, or one blanking line stretched or lines added or removed per frame.

Legend: **[std]** text of a standard, quoted; **[src]** source code read (file given); **[doc]** official documentation of the project or vendor; **[field]** forum post, GitHub issue or user report (anecdotal); **[sum]** only a search-engine summary of the page was available (the site refused automated reading), so the wording is not verified; **[calc]** computed here; **[inf]** inference, not stated by any source.

## 0. Target numbers [calc]

| Machine | Clock | Frame | Rate | Deviation | One frame slip at the standard rate every |
| --- | --- | --- | --- | --- | --- |
| PAL C64 (6569) | 17.734475 MHz / 18 = 985 248.6 Hz | 63 cycles x 312 lines | 50.12457 Hz | +0.2491 % vs 50.000 Hz | 8.03 s |
| NTSC C64 (6567R8) | 14.318182 MHz / 14 = 1 022 727 Hz | 65 cycles x 263 lines | 59.82611 Hz | -0.1901 % vs 59.940 Hz, -0.2898 % vs 60.000 Hz | 8.78 s (vs 59.94) |

Option (a), pixel clock for the native rate with the CTA totals:

| Format (H x V total) | CTA clock | Native-rate clock | Deviation |
| --- | --- | --- | --- |
| 720p50 (1980 x 750) | 74.25 MHz | 74.4350 MHz | +0.249 % |
| 576p50 (864 x 625) | 27.000 MHz | 27.0673 MHz | +0.249 % |
| 1080p50 (2640 x 1125) | 148.5 MHz | 148.8700 MHz | +0.249 % |
| 720p59.94 (1650 x 750) | 74.1758 MHz | 74.0348 MHz | -0.190 % (-0.290 % vs the 60 Hz clock 74.25) |
| 480p59.94 (858 x 525) | 27.000 MHz | 26.9487 MHz | -0.190 % (-0.290 % vs 27.027) |
| 1080p59.94 (2200 x 1125) | 148.3516 MHz | 148.0696 MHz | -0.190 % |

Option (b), nearest integer totals at the unchanged CTA clock:

| Format | Change | Rate | Error vs C64 |
| --- | --- | --- | --- |
| 720p50 | H total 1975 instead of 1980 | 50.1266 Hz | +40 ppm |
| 720p50 | V total 748 instead of 750 | 50.1337 Hz | +182 ppm |
| 576p50 | H total 862 instead of 864 | 50.1160 Hz | -171 ppm |
| 576p50 | V total 624 instead of 625 | 50.0801 Hz | -887 ppm |
| 720p59.94 | H total 1653 instead of 1650 | 59.8313 Hz | +86 ppm |
| 480p59.94 | V total 526 instead of 525 (H 858) | 59.82611 Hz | 0 ppm (exact) |

The 480p case is exact because the line rate of the NTSC C64 (1 022 727 Hz / 65 = 15 734.27 Hz) equals the NTSC TV line rate, so 27 MHz / 858 is exactly twice it; 2 x 263 = 526 lines then give exactly the C64 frame. No other format has such a relation; everywhere else (b) leaves an error of tens to hundreds of ppm that a genlock must still absorb.

Option (c), examples: 1280x720 active in 1872 x 756 at 70.94 MHz = 50.1261 Hz; 720x576 active in 864 x 624 at 27.0240 MHz = 50.1246 Hz (this is the original Ultimate 64, section 3.2).

## 1. What the standards say

### 1.1 CEA-861-B (2002) [std]

Source: <https://archive.org/download/CEA-861-B/CEA-861-B.pdf>, section 4 (page 18) and notes to Table 4.

- "The mandatory and optional formats defined in this standard shall comply with the timing parameters in Table 4 and the timing diagrams that follow. DTV Monitors shall be able to accept video whose pixel clock is accurate to within 0.5% of the clock frequency shown in Table 4."
- Footnote 5 to Table 4: "The 25.2 MHz pixel frequency value is within the +/-0.5% (allowed in the VESA MTS [10]) of 25.175 MHz."
- "For 60 Hz systems, the DTV Monitor shall be capable of displaying either 59.94 or 60 Hz ... Therefore, the 59.94 Hz and 60 Hz versions of a video format timing shall be considered the same video format with slightly different pixel clocks." Sinks therefore already handle two rates 0.1 % apart in the 60 Hz family. There is no such pair in the 50 Hz family.
- Low-resolution formats: "These frame formats differ only by one or two scan lines in the vertical blanking interval. For that reason, they are treated as the same video format with a slight variation in the parameters ... if a DTV Monitor declares support of one of these video formats ... then it shall support all variations of that video format." Table 4 lists 1440x240p with 262 lines (60.054 Hz) and with 263 lines (**59.826 Hz**, 27.000 MHz, H total 1716), and 1440x288p with 312, 313 and 314 lines (50.080, 49.920, 49.761 Hz). This is the only place where the standard itself allows a line count to vary, and only for the 15 kHz formats that few modern sinks accept.

Reading for option (a): a 720p50 signal with the Table 4 totals and a pixel clock 0.25 % high is inside the range that 861-B obliges a sink to accept.

### 1.2 CTA-861-G (2016, revised 2017) [std]

Source: <https://web.archive.org/web/20171201033424/https://standards.cta.tech/kwspub/published_docs/CTA-861-G_FINAL_revised_2017.pdf>

- The explicit sink obligation of 861-B ("shall be able to accept ... within 0.5%") no longer appears. What remains is note 3 to the timing tables: "The VESA DMT standard [86] specifies a ± 0.5% pixel clock frequency tolerance. Therefore, the nominally 25.175 MHz pixel clock frequency value given for Video Identification Code 1 may be adjusted to 25.2 MHz to obtain an exact 60 Hz vertical frequency." The 0.5 % rule is thus still cited as the accepted tolerance, now by reference to VESA DMT.
- The 59.94/60 identity is generalized to all 1000/1001 pairs, and "a DTV that declares it is capable of displaying a Video Timing with a vertical frequency that is either an integer multiple of 6 Hz or an integer multiple of 6 Hz adjusted by a factor of 1000/1001 shall be capable of displaying both versions of the Video Timing."
- The 240p/288p line-count variants are kept (Table 1 rows 59.8263 Hz for 263 lines, 50.080 Hz for 312 lines).
- "The mandatory and optional formats defined in CTA-861 shall comply with the timing parameters in Table 1 and Table 2."
- Note 4: "To avoid fractional frame rate conversions in Source and Sinks, Sources should use the exact vertical frequencies of 25.000 Hz, 50.000 Hz, 100.000 Hz ...". A "should" against any 50.12 Hz output. All four options violate it equally, because the rate is the point; it does not discriminate between them.
- Definitions: "CE Video Format—Any Video Format listed in Table 1 except the 640x480p Video Format." "IT Video Format—Any Video Format that is not a CE Video Format." Defaults differ: "When transmitting IT Video Format Timings, the default color space shall be RGB using Full Range quantization levels", and a sink "should overscan CE Video Formats and underscan IT Video Formats by default". A timing with changed totals is an IT format; sinks may route it through their PC path (different scaling, overscan and range defaults).

### 1.3 HDMI 1.4 [std]

Source: <https://web.archive.org/web/20190101000000/https://glenwing.github.io/docs/HDMI-1.4.pdf>

- 6.1: "HDMI allows any video format timing to be transmitted and displayed. To maximize interoperability between products, common DTV formats have been defined."
- 6.3: "All specified video line pixel counts and video field line counts (both active and total) and HSYNC and VSYNC positions, polarities, and durations shall be adhered to when transmitting a specified video format timing." The pixel clock is not in this list; its tolerance is the one of CEA-861.
- "All HDMI devices are required to comply with the requirements specified in CEA-861-D".

### 1.4 Reading [inf]

- (a) is a CTA format (CE Video Format) whose only deviation is the pixel clock, inside the 0.5 % that 861-B demands from sinks and that 861-G cites from VESA DMT. Totals, porches and sync widths are exactly what HDMI 6.3 requires. The source can and should keep sending the CTA VIC in the AVI InfoFrame.
- (b), (c) and (d) are not "a specified video format timing". They are legal HDMI ("any video format timing"), but they are IT formats with VIC 0, and no standard obliges a sink to display them unless the sink lists them in its EDID.
- Neither standard states a tolerance for the vertical frequency as such; it follows from the clock tolerance and the fixed counts.

## 2. How sinks identify the format and lock to it

### 2.1 What open receiver code does

**Analog Devices ADV7604/ADV7611 (Linux driver)** [src] <https://github.com/torvalds/linux/blob/master/drivers/media/i2c/adv7604.c>

- HDMI input: the driver reads the VIC from the AVI InfoFrame; `if (vic && v4l2_find_dv_timings_cea861_vic(timings, vic) && bt->width == w && bt->height == h) goto found;` so a VIC whose active size matches the measured one is taken as that CTA timing. Otherwise the timing is built from the measured porches, sync widths and the measured TMDS clock (ADV7611: resolution 1/128 MHz, `adv7611_read_hdmi_pixelclock`).
- Matching against its preset list uses `v4l2_match_dv_timings` (<https://github.com/torvalds/linux/blob/master/drivers/media/v4l2-core/v4l2-dv-timings.c>): width, height, front porch, sync width, back porch (H and V) and polarities must be **equal**; the pixel clock may differ by `pclock_delta`, which the driver sets to 250 kHz for digital inputs and 1 MHz for analog. 250 kHz is 0.34 % of 74.25 MHz; the +0.25 % of option (a) is 186 kHz and passes. A changed total or porch (b, c) does not match any preset and is reported as a custom timing.
- Analog input (STDI): the block length in crystal clocks (28.63636 MHz) gives the line frequency; a preset matches only if `vtotal(bt) == stdi->lcf + 1` (exact line count), the vsync width matches, and line frequency x preset H total is within 1 MHz of the preset clock.

**AMD/Xilinx HDMI RX subsystem driver** [src] <https://github.com/Xilinx/embeddedsw/blob/master/XilinxProcessorIPLib/drivers/v_hdmirx/src/xv_hdmirx.c> and `xv_hdmirx_intr.c`

- `XV_HdmiRx_GetVideoTiming` compares H total, H active, H sync width, H front and back porch, V total and the V porches with the values of the previous read; only if all are identical (`Match`) is the stream declared up. In the stream-up state a failed comparison drops the state back to "lock".
- The frame rate is computed as pixel clock / (H total x V total) as an integer, and the timing is looked up in the mode table; if it is not found the stream is tagged custom.
- If the VIC of the AVI InfoFrame decodes to another mode than the measured one, a `VicErrorCallback` is raised. A source that keeps a CTA VIC while sending changed totals (b, c) triggers exactly this case.

**Realtek RTD2662 (small LCD monitor controller; leaked vendor firmware on GitHub)** [src] <https://github.com/avtehnik/RTD2662> (`Core/header/ModeTable.h`, `Core/code/Mode.c`, `Core/code/FrameSync.c`)

- Measures the line period with the crystal (`IHFreq`) and counts lines (`IVTotal`), then `IVFreq`. A preset matches if the V frequency is within `_VFREQ_TOLERANCE` (1.2 Hz), the H frequency within `_HFREQ_TOLERANCE` (1.0 kHz) and the V total within 4 lines. Outside the panel H/V range the result is `_MODE_NOSUPPORT`. A change of the line count by more than 2 or of the H count by more than 1 is treated as a mode change.
- Frame sync: `CFrameSyncDo` searches a panel DCLK setting with no buffer underflow or overflow, i.e. the panel is clocked so that its frame period equals the input frame period.

**MStar (leaked firmware)** [src] <https://github.com/csurf/mstar> (`msFunc/mode.c`): `HFreq_tolerance 10 // 1 KHz`, `VFreq_tolerance 30 // 3 Hz`.

### 2.2 Two families of detection [inf]

1. Table matching on measured frequencies with generous tolerances (about 1 Hz and 1 kHz), plus a near-equal line count. 50.12 Hz is 0.12 Hz from 50 Hz; options (a), (b) and (c) all pass as long as the active size and the line count are close to the preset.
2. Exact-count matching, often combined with the AVI VIC (the Linux and Xilinx receivers above). Option (a) is recognized as the CTA format. (b) and (c) become custom/IT timings: they are shown only if the sink's custom path handles them, and with a CTA VIC they cause a VIC/timing mismatch.

Option (a) passes both families; (b) and (c) pass only the first.

### 2.3 Accepted versus smooth

Acceptance and smoothness are different questions. The frame rate is the same in (a), (b) and (c), so whether the sink then shows every frame depends on its panel path, not on how the signal was built:

- Panel locked to the input: the RTD2662 frame sync above; monitors with a panel range that includes 50.12 Hz.
- Panel free-running with frame-rate conversion: such sinks accept the signal but drop or repeat a frame every 8 s, exactly as with today's 50.00 Hz output.
  - [field] MiSTer issue #644 <https://github.com/MiSTer-devel/Main_MiSTer/issues/644>: "My TV supports 60hz and 50hz and their close variations just fine, but nothing in-between ... when I run any Arcade core that has a weird-ass refresh rate like 57hz, my TV throws a "resolution not supported" error."
  - [field] MiSTer forum, Samsung QLED: frame skipping and tearing with `vsync_adjust`, cleared by toggling Game Mode <https://mail.misterfpga.org/viewtopic.php?p=33079> [sum].
  - [sum] Blur Busters: TVs that accept a higher rate but skip refresh cycles; their TestUFO frame-skipping check detects this <https://www.blurbusters.com/overclock/120hz-pc-to-tv/>.
- A change of frame rate is itself a re-sync event for most sinks: HDMI.org describes "a 1-3 second blackout" because "the entire system must change its clocking and re-sync when the frame rate changes" <https://hdmi.org/spec2sub/quickmediaswitching> [doc]. Synopsys: a sink without QMS "changes its clocking and re-syncs to the new frame rate resulting in an A/V blackout" <https://www.synopsys.com/blogs/chip-design/hdmi-quick-media-switching.html> [doc].

## 3. Field experience

### 3.1 Overview

| Project | Construction | Option | Compatibility statement | Kind |
| --- | --- | --- | --- | --- |
| MiSTer `vsync_adjust` | base mode totals kept, pixel clock = totals / measured frame time | (a); with a 60 Hz base for 50 Hz cores a non-CTA timing | "Not every display supports variable pixel clock" | [src] [doc] [field] |
| Ultimate 64 (original) | 576p: 864 x 624 at 27.024 MHz; 480p: 858 x 526 at 27.000 MHz; no frame buffer | (c) PAL, (b) NTSC | "I have not come across screens that do not accept the generated HDMI signal" | [src] [doc] |
| Ultimate 64 Elite II | CTA totals, pixel clock detuned in every CTA mode (480p to 1080p) | (a) | none published; default HDMI mode of a current product | [src] |
| BMC64 custom modes | 768x544 in 960 x 563 at 27.092 MHz; 768x525 in 960 x 547 at 31.416 MHz | (c), non-standard active size | "may not be compatible with all monitors" | [doc] |
| BMC64 Pi 4/5 (Oct 2026) | CTA 720p/1080p, clock scaled, rejected outside 0.5 % | (a) | too new for reports | [src] [doc] |
| VIC-II Kawari (DVI) | 782x576 in about 945 x 624 at 29.557 MHz; alternative 720x576 in about 882 x 624 at 27.586 MHz | (c) | wide variant: "Some monitors won't display it"; 720x576 variant: "More compatible" | [doc] |
| MEGA65 core | 576p with 624 lines at 27 MHz; 480p 858 x 526 at 27 MHz | (b) | community list: 9 of 10 displays fine with PAL (core and mode of the test not stated) | [src] [doc] |
| OSSC Pro framelock | standard output preset, pixel clock from the input clock (Si5351) | (a) | forum: jitter can make displays reject the regenerated clock | [src] [sum] |
| RetroTINK 5X/4K frame lock | console as base clock | not documented | "may not work with some TVs" | [sum] |
| RGBtoHDMI genlock | Pi HDMI clock trimmed at 333 to 2000 ppm speed | (a) dynamic | "If your monitor blanks briefly during genlocking ... try reducing the genlock speed" | [doc] |
| gbs-control frame time lock | V total +2 lines while phase lags, or clock trim with a Si5351 | (d) / (a) dynamic | "disable if display unstable or stays blank!"; Dell U2312HM loses sync on 0.1 % steps | [src] |
| Analogue Super Nt, Hi-Def NES | console slowed to exactly 60.00 Hz for HDMI | none (avoids the problem) | n/a | [sum] |

### 3.2 Ultimate 64 / Ultimate 64 Elite II (Gideon's Logic)

[doc] <https://1541u-documentation.readthedocs.io/en/latest/hardware/hdmi.html>: "The output resolution is 720 x 576 at 50 Hz (for the PAL version), also noted as 576p50. This is a standard resolution that all HDMI capable screens are supposed to support, according to the CEA-861 standard. However, to meet the exact timing of a C64, the timing parameters of this video mode are slightly modified." "I have not come across screens that do not accept the generated HDMI signal." "There is no frame buffer, so there is no need to worry ... scrollers and such are perfectly smooth." On latency: "I observed this with a 4K screen that actually resampled the output to just 30Hz."

[src] <https://github.com/GideonZ/1541ultimate/blob/master/software/u64/hdmi_scan.cc> (fields: VIC, pixel clock, H active, H front porch, H sync, H back porch, H polarity, V active, V front porch, V sync, V back porch, ...):

- Original U64 (`SetVideoMode`):
  - `{ 17, 27023962, 720, 12, 64, 68, 0, 576, 4, 5, 39, ... }` with the comment "VIC 17/18 720x576 @ 50.12Hz (624 lines) (!) // detuned + one line less" = 864 x 624 at 27.024 MHz = 50.1246 Hz, sent with VIC 17. Option (c).
  - NTSC `{ 03, 27000000, 720, 16, 62, 60, 0, 480, 9, 6, 31, ... }` = 858 x 526 at 27.000 MHz = 59.8261 Hz (the comment says "@ 60Hz"), VIC 3. Option (b).
- U64 Elite II (`SetVideoMode1080p`, scaler):
  - `sm_576p50` 864 x 625 at 27.067270 MHz;
  - `sm_480p60` 800 x 525 at 25.126964 MHz (VIC 1);
  - `sm_720p50` 1980 x 750 at 74.434928 MHz;
  - `sm_720p60` 1650 x 750 at 74.034804 MHz;
  - `sm_1080p50` 2640 x 1125 at 148.869856 MHz;
  - `sm_1080p60` 2200 x 1125 at 148.069608 MHz.

  [calc] These are exactly 50.1245 Hz and 59.8261 Hz with the CTA totals and CTA VICs: option (a) throughout. The PC modes (800x600, 1024x768, 1280x1024, VIC 0) have non-CTA totals; their listed clocks compute to exactly 50 or 60 Hz and are probably nominal values.
- The HDMI PLL is referenced to the C64 clock: "Set the primary C64 clock, which is also the reference for the HDMI pll" (<https://github.com/GideonZ/1541ultimate/blob/master/software/u64/u64_config.cc>). Input and output frame are thus locked by construction, with no modulation of totals.
- A commented-out list of earlier scan modes in `u64_config.cc` shows the alternatives that were tried: "720x576@50Hz (625)", "720x576@50.12Hz (625)", "720x576@50Hz (624)", "720x576@50.12Hz (624)", "1440x288 @ 50Hz (312)", "1440x288 @ 50Hz (313)", "Commodore, Extd Blnk", "Commodore, Detuned", "Commodore, Wide brd", "720(1440)x480 54MHz". The shipping menu now offers "SD (480p/576p)", "HD (720p)", "FullHD (1080p)", "PC 800 x 600", "PC 1024 x 768", "PC 1280 x 1024".
- Commit "1080p50 compliance" (2025-11-01, <https://github.com/GideonZ/1541ultimate/commit/dac1bbcadfab7bb7bcc0906b91f5fdd742cd2287>) changed the 1080p50 H front porch / sync from 510 / 62 to the CTA values 528 / 44, with the same H total. A total-preserving porch deviation was evidently worth fixing for "compliance"; the commit does not say which display or test failed.
- [field] Issue #297 (Gideon, <https://github.com/GideonZ/1541ultimate/issues/297>): the U64 has no frame buffer, "so any resolution that it could make should be in sync with the VIC"; about a custom 1080i variant: "it will surely be highly non-standard and questionable if your screen will support it. Most European screens would, tho."
- [field] Issue #542 (<https://github.com/GideonZ/1541ultimate/issues/542>): compact 5:4 screens used at retro parties worked with the original U64E but "no longer work on U64E2"; the PC 1280x1024 modes were added afterwards. The cause (rate, resolution or aspect) is not stated.

### 3.3 MiSTer

- [src] `video.cpp` (<https://github.com/MiSTer-devel/Main_MiSTer/blob/master/video.cpp>): `Fpix = 100 * (h totals) * (v totals) / vtime` with the totals of the base mode; adjustment is cancelled outside `refresh_min` / `refresh_max`. With `vsync_adjust=2`, if the PLL lands on an integer multiplier, up to 8 front-porch lines are added and the clock recomputed (issue #1343, <https://github.com/MiSTer-devel/Main_MiSTer/issues/1343>: "Tested with Frogger/Scramble at 1080p60, maintaining ~60.606 Hz and restoring stable video on a handful of displays I have.").
- [doc] `MiSTer.ini` (<https://github.com/MiSTer-devel/Main_MiSTer/blob/master/MiSTer.ini>): "Adjusting is done by changing pixel clock. Not every display supports variable pixel clock. For proper adjusting and to reduce possible out of range pixel clock, use 60Hz HDMI video modes as a base even for 50Hz systems." And: "If your monitor doesn't support either very low (NTSC monitors may not support PAL) or very high (PAL monitors may not support NTSC) then you can set refresh_min and/or refresh_max". [calc] With the default 720p60 base, a 50.12 Hz core is sent as 1280x720 in 1650 x 750 at 62.03 MHz (-16.5 %): no CTA timing at all. This is widely used, so many sinks evidently accept a 720p raster with 60 Hz totals at 50 Hz.
- [doc] Wiki "HDMI Smooth output" (<https://github.com/MiSTer-devel/Wiki_MiSTer/wiki/HDMI-Smooth-output>):
  - "I found that some (not all!) TVs and Monitors can accept arbitrary pixel clock. For example FullHD pixel clock is 148.5MHz, but many TVs/Monitor may accept some range of clocks. Thus picture parameters are remained the same so digital parts of TV/Monitor will get their standard amount of pixels and lines, but they will work on slightly different frequency."
  - "There still can be one frame repeat or drop but it will happen once per couple hours which is acceptable."
  - "Some TVs when get video from analogue source may change their screen frame rate according to source ... the same TV usually don't accept the same non-standard frame rate from digital source as internal processing goes through different routes."
- [field] Issue #307 (<https://github.com/MiSTer-devel/Main_MiSTer/issues/307>): a Sony laser projector rejected 1280x720 at 60 and 50 Hz ("No Signal") from MiSTer even with `vsync_adjust=0`, while a laptop's 720p worked; an example of a sink that rejects a nominally standard MiSTer mode for reasons unrelated to the rate.
- [field] [sum] misterfpga.org threads (the site refuses automated reading): a Samsung flat panel showed "signal not recognised" for some arcade cores unless `vsync_adjust=0` <https://www.misterfpga.org/viewtopic.php?p=34255>; Samsung QLED frame skipping and tearing <https://mail.misterfpga.org/viewtopic.php?p=33079>.
- No C64-core-specific compatibility statistics were found.

### 3.4 BMC64 (Raspberry Pi)

- [doc] FAQ (<https://github.com/randyrossi/bmc64/blob/master/docs/FAQ.md>), "Hey, isn't the real thing running at 50.125Hz?", recommends these custom modes. The fields are `h_active h_pol h_fp h_sync h_bp v_active v_pol v_fp v_sync v_bp offset_a offset_b pixel_rep frame_rate interlaced pixel_freq aspect`:

  ```
  [C64/PAL/HDMI/768x544@50.125Hz]
  hdmi_timings=768 0 24 72 96 544 1 3 2 14 0 0 0 50 0 27092000 1
  machine_timing=pal-custom
  cycles_per_second=985257

  [C64/NTSC/HDMI/VICE 768x525@59.825Hz]
  hdmi_timings=768 0 24 72 96 525 1 3 10 9 0 0 0 60 0 31415829 1
  machine_timing=ntsc-custom
  cycles_per_second=1022708
  ```

  [calc] PAL: H total 960, V total 563, 27.092 MHz, 50.1258 Hz. NTSC: H total 960, V total 547, 31.415829 MHz, 59.8260 Hz. Both have a non-standard active size, so option (c).
- Statements: "This mode will match the timing of the original machine (for the purists) but may not be compatible with all monitors", and for NTSC "since it's not a standard resolution, it may not work on all monitors". User guide (<https://github.com/randyrossi/bmc64/blob/master/docs/USER_GUIDE.md>): "The default config provided uses 720p PAL 50hz on HDMI. This is a 'safe' mode that should work on all monitors. A 50.125hz custom mode is provided ... However, this mode may not work on all monitors."
- [src] Pi 4/5 port (commit of 2026-10-21), <https://github.com/randyrossi/bmc64/blob/master/src/kms/common/modes.cpp>:
  - `ChooseMode` takes the CTA 720p/1080p mode of the right family, computes `clock = HTotal * VTotal * fps`, and refuses it if it is not within the base clock x 0.995 to x 1.005 ("CTA-861 allows the pixel clock to be 0.5 % off.").
  - It sends the CTA VIC in the AVI InfoFrame and uses the mode only if the EDID lists that VIC.
  - `AudioCts(tmds_hz, n, fs)` computes CTS from the actual TMDS clock.

  Option (a), implemented strictly by the standard. [doc] <https://github.com/randyrossi/bmc64/blob/master/docs/LIMITATIONS_PI4_PI5.md>: "at 50 Hz (PAL) or 60 Hz (NTSC), run at the machine's own frame rate (within CTA-861's 0.5 % pixel clock tolerance)". No user reports yet.

### 3.5 VIC-II Kawari

[doc] <https://github.com/randyrossi/vicii-kawari/blob/main/README.md> (DVI output, no HDMI InfoFrames; totals derived [calc] from the stated clock and line rate):

| Firmware | PAL visible | PAL clock | PAL totals (about) | Rate | Statement |
| --- | --- | --- | --- | --- | --- |
| Default (DVI) | 782 x 576 | 29.557 MHz | 945 x 624 | 50.125 Hz | "Less compatible PAL mode. Some monitors won't display it."; "Non-standard resolution may confuse some monitors." |
| Scaled (DVS) | 720 x 576 | 27.586 MHz | 882 x 624 | 50.125 Hz | "More compatible PAL mode"; "a mode closer to the 720x576 standard. This is more likely to work for older TVs/monitors." |

NTSC: 740x500 (default) and 720x480 (scaled), both at 26.590 MHz, about 845 x 526, 59.82 Hz. Lesson: the non-standard active size hurt more than the changed totals and clock; moving the active area to 720x576 helped.

### 3.6 The MEGA65's own core

[src] <https://github.com/MEGA65/mega65-core/blob/development/src/vhdl/pixel_driver.vhdl> and `frame_generator.vhdl`: "They also use a common 27MHz pixel clock"; PAL 576p with `frame_height => 625`, but in the default "fake progressive" mode the frame has 624 lines. The comment says the lines stay 864 wide (27 MHz / (864 x 624) = 50.080 Hz), while the code in `frame_generator.vhdl` also shortens each line by one pixel when the frame height is odd (863 x 624 = 50.138 Hz) [calc]. NTSC 480p uses `frame_width => 858` and `frame_height => 526` (59.8261 Hz), with sync positions adjusted for "HDMI test 7-25". This is option (b) at the standard 27 MHz.

[doc] MEGA65 wiki monitor list (<https://mega65.atlassian.net/wiki/spaces/MEGA65/pages/4292609/Monitors>): 10 displays; PAL fails only on an Acer Nitro VG280K ("Audio didn't work. PAL flickers."), NTSC fails on a 9.7" 2K monitor ("PAL w/ audio. No NTSC."); a Samsung QN85A passes both but is noted "C64 core not working". The table does not say which core or HDMI mode was tested.

[doc] MEGA65 developer blog, 2019 (<https://c65gs.blogspot.com/2019/11/improving-raster-timing-accuracy.html>): with standard 27 MHz 576p/480p modelines, "the 7511 even reports that it detects the mode correctly as the EDTV 576p or 480p video mode", and the monitor "shows the mode correctly as 720x576 @ 50Hz". A later post (<https://c65gs.blogspot.com/2019/11/just-about-cycle-perfect-pal-50hz-hdmi.html>) mentions "Adjusting the frames to have exactly the right number of raster lines (it was out by one before)".

### 3.7 Scalers with a frame-lock mode

**OSSC Pro** [src] <https://github.com/marqs85/ossc_pro> (`software/sys_controller/src/video_modes.c`, `av_controller.c`, `src/menu.c`):

- Menu "Framelock": "On", "Off (source Hz)", "Off (preset Hz)", "Off (50Hz)", "Off (60Hz)", ...
- With framelock on, the standard output preset is chosen, its refresh is set to the input refresh, and `calculate_pclk` computes the pixel clock from the preset's H total x V total x refresh.
- The Si5351 is then clocked from the input clock (`SI_CLKIN`) with the ratio (output H total x V total) / (input H total x V total).
- The output totals stay standard and the pixel clock follows the source: option (a), phase-locked by construction. A watchdog prints "Restarting CVO due to framelock timeout".
- [sum] Forum: framelock "is designed to operate with constant number of VCLKs per frame" (<https://videogameperfection.com/forums/topic/snes-stutter-in-adaptive-line-mode/>); "no guarantee the regenerated pixel clock is accepted by your display due to jitter" (<https://videogameperfection.com/forums/topic/ossc-loses-sync-when-receiving-13-75-khz-h-sync/>).

**RetroTINK 5X Pro / 4K** [sum] Manual (<https://consolemods.org/wiki/AV:RetroTINK-5X_Pro/manual>): frame lock uses the console as its base clock, the output frame rate follows the console with a fixed lag of about 0.25 frames, and frame lock "may not work with some TVs and capture cards, depending on the console's frame rate"; triple buffer holds a constant 60 Hz. [doc] 4K firmware 1.9.6 (<https://retrotink-llc.github.io/firmware/4k.html>) adds a "TBC" sync option ("similar to Gen-Lock but with additional filtering and slower convergence") and an "Adaptive Triple Buffer" that "switches to a buffered 50 Hz mode when the source switches from ~60 Hz to ~50 Hz". How the output timing is changed (clock or totals) is not documented publicly.

**RGBtoHDMI** [doc] <https://github.com/IanSB/RGBtoHDMI/wiki/Reference-Guide>, <https://github.com/hoglet67/RGBtoHDMI/wiki/Quick-Start-Guide>:

- Genlock locks the Pi's HDMI output to the source by adjusting its clock. "Genlock Speed: Slow (333PPM) / Medium (1000PPM) / Fast (2000PPM) ... If your monitor blanks briefly during genlocking (when the led is flashing) then try reducing the genlock speed."
- "Genlock Adjust: -5% to +5% / Full Range"; Full Range "is not normally recommended as it can result in very non-standard video outputs that the monitor will be unable to display."
- "Periodically the Pi will need to re-lock to the source".
- "Many monitors will actually support 50Hz even though their EDID indicates otherwise".

**gbs-control** [src] <https://github.com/ramapcsx2/gbs-control/blob/master/framesync.h>, `gbs-control.ino`:

- Without an external clock generator, "Active FrameTime Lock" adjusts "the frame size (and thus the output vsync frequency)": while the phase lags, V total (and, in method 0, the VSYNC position) is increased by `syncCorrection = 2` scan lines. The log message: "Active FrameTime Lock enabled, disable if display unstable or stays blank!"
- With an external Si5351 the output clock is trimmed instead, with the comment: "Some LCD displays (eg. Dell U2312HM) lose sync when changing frequency by 0.1% (switching between 59.94 and 60 FPS). To ensure long-term FPS stability, clamp the maximum deviation from input FPS to 0.06%." Per-frame changes are also clamped to 0.06 %.

### 3.8 Others

- **ZX Spectrum Next** [field] (manual author, <https://spectrumcomputing.co.uk/forums/viewtopic.php?p=35212>): "ALL HDMI displays will do 60Hz but only some will do 50Hz", "almost all TVs in Europe can do 50Hz HDMI", and "HDMI timings are "bent" regardless of 50 or 60Hz".
- **Analogue Super Nt / Nt mini, Hi-Def NES** [sum]: in the default zero-delay mode the console is slowed from 60.09 Hz to 60 Hz to match flat panels (<https://www.nintendolife.com/reviews/the-analogue-super-nt-is-the-ultimate-way-to-play-snes-games-in-2018>); Nt mini over HDMI displays 60 fps (<https://www.speedrun.com/ngnes/forums/55nx9>); Hi-Def NES underclocked to keep 60 Hz (<https://forum.speeddemosarchive.com/post/hdmi_nes.html>, forum claim). The commercial FPGA consoles avoid an off-standard HDMI rate in their default mode.
- **TheC64 Mini/Maxi** [field] [sum]: a user reports that the related THE400 Mini switches between 720p 50 Hz and 720p 60 Hz depending on the setup choice (<https://forums.atariage.com/topic/364684-hdmi-video-tearing-on-the-mini/>). Nothing found about a native-rate HDMI output.
- **Turbo Chameleon 64, C64 Reloaded MK2**: no native HDMI output, so no HDMI experience to report; nothing relevant found.
- **Stutter tests**: the C64MEGA65 user documentation names the title scroller of "The Great Giana Sisters" as the test and describes the jump every few seconds at 50.00 Hz (<https://kugelblitz360.github.io/C64MEGA65DOCS/hdmi-and-analog-output>). No published study of sink tolerances based on such a test was found. A sink that accepts the mode but free-runs will show the same jump every 8.03 s (PAL) or 8.78 s (NTSC) [calc]; TestUFO's frame-skipping check (section 2.3) is a method to tell the two cases apart.

## 4. Option (d): modulating the totals

- **VRR is the standardized form of "stretching the vertical blanking frame by frame", and it is opt-in on the sink side.**
  - [sum] A Linux patch reads the VRR range of HDMI 2.1 sinks from the HF-VSDB of the EDID ("The information is fetched from additional HFVSDB blocks defined for HDMI 2.1"; <https://lists.openwall.net/linux-kernel/2026/01/19/25>).
  - [sum] Intel's HDMI IP guide: "since VRR involves runtime varying video vertical blanking, HDMI sink locked and vid_lock remains asserted when receiving video with VRR transport" (<https://www.intel.com/content/www/us/en/docs/programmable/683798/21-3-19-6-1/variable-refresh-rate-vrr-and-auto-low-81928.html>). This implies that outside VRR transport a varying blanking is not expected to keep the receiver locked.
  - MiSTer only enables its VRR mode with `vsync_adjust=0` and VRR InfoFrames (`MiSTer.ini`, "4 - Force Enable MiSTer VRR (vsync_adjust must be 0)").
- **Receivers that require identical consecutive timing reads** (Xilinx `XV_HdmiRx_GetVideoTiming`, section 2.1) [src] would see a different H total or V total on successive reads if the totals alternate. The stream would then not come up, or drop back to "lock". A one-pixel H-total alternation within the frame defeats any receiver that measures H total on an arbitrary line [inf].
- **Line-count modulation in practice**: gbs-control's V total +2 method comes with "disable if display unstable or stays blank!" [src]. MiSTer's `vsync_adjust=2` padding of the front porch is a one-time static change per mode, not a per-frame modulation [src].
- **Clock-trim genlock in practice**: RGBtoHDMI (blanking at fast genlock speeds) and gbs-control (Dell U2312HM loses sync on 0.1 % steps; clamp to 0.06 %) [doc] [src] show that even a dynamic clock trim must be gentle. OSSC Pro and the Ultimate 64 avoid dynamic trimming by deriving the output clock from the input clock with a fixed ratio [src].
- No documented experience was found with a source that alternates H total by one pixel between lines, or that stretches a single blanking line every frame, on non-VRR HDMI sinks.

## 5. HDMI audio (N/CTS)

[std] HDMI 1.4, section 7.2 (<https://web.archive.org/web/20190101000000/https://glenwing.github.io/docs/HDMI-1.4.pdf>):

- "The Source shall determine the fractional relationship between the TMDS clock and an audio reference clock (128 · audio sample rate [fs]) and shall pass the numerator and denominator of that fraction to the Sink". The relationship: "128·fS = fTMDS_clock · N / CTS."
- "CTS shall be an integer number that satisfies the following: (Average CTS value) = (fTMDS_clock · N ) / (128 · fS)". For coherent clocks the tables apply; "For non-coherent Sources or Sources where coherency is not known, the equations above should be used." For 48 kHz the table row "Other" TMDS clock gives N = 6144 and CTS "Measured". "If the clocks are asynchronous, or there is some amount of jitter between the two clocks, then the CTS value will typically alternate between two or three different values."
- "On average, the Source shall transmit CTS values at this rate precisely" (128·fs/N, 1 kHz for 48 kHz and N = 6144).
- "Transmitted audio shall have an audio sample rate (fS) within ±1000 ppm of the sample rate indicated in Channel Status bits 24 through 27"; "A Sink shall support the reception of an audio stream with correct sample rate indication ... and with a sample rate (fS) within ±1000 ppm of any supported sample rate."
- The sink model (Figure 7-2) regenerates 128·fs with a PLL from the TMDS clock divided by CTS and multiplied by N. "it is permitted and possible to devise an audio clock regeneration function that does not take advantage of the N or CTS values".

Consequences [calc] [inf]:

- With the pixel clock moved (option a), the 48 kHz sample strobe must not be derived by dividing the TMDS clock with the divider of the standard mode: fs would move by +2491 ppm (PAL) or -1901 ppm (NTSC vs 59.94), outside the ±1000 ppm the spec allows. Keep fs at 48 kHz from an accurate clock and send the average CTS for the actual TMDS frequency. With N = 6144: CTS average = f_TMDS / 1000, i.e. 74434.93 (720p50, alternate 74434 and 74435), 74034.80 (720p59.94), 27067.27 (576p50). BMC64's Pi 4/5 code does exactly this (`AudioCts`) [src].
- If the transmitted CTS average is off by e ppm, the sink's regenerated clock runs e ppm off the real sample arrival rate. The sample FIFO then drifts by 48000 x e x 10^-6 samples per second: 0.48 samples/s at 10 ppm, i.e. 32 samples in 67 s; 32 samples in 13 s at 50 ppm. The spec only bounds packet jitter ("shall not exceed one horizontal line period plus a single audio sample period"), not drift, so a constant CTS error shows up as a periodic click or a mute-and-resync on sinks that rely on N/CTS. No published tolerance figure of real sinks was found.
- [doc] AMD's ACR unit (<https://docs.amd.com/r/en-US/pg335-acr-unit/General-Design-Guidelines>) distinguishes "fixed" recovery from N and CTS ("This is good for HDMI as the TMDS clock is available at the receiver") from a "loop control mode" adjusted "based on the FIFO occupancy level" (meant for DisplayPort): sinks of the first kind depend on CTS being right on average.
- [field] [sum] Analog Devices forum: crackling audio from an FPGA source into an ADV7513 traced to N/CTS settings (<https://ez.analog.com/video/f/q-a/565983/adv7513-i2s-no-audio>).

## 6. NTSC side

- 59.826 Hz is -0.19 % from 59.94 Hz and -0.29 % from 60 Hz; sinks already must accept both 59.94 and 60 (0.1 % apart). CTA-861 itself lists 59.826 Hz as the 263-line variant of 240p [std]. The 480p case is special: 858 x 526 at the standard 27.000 MHz gives exactly 59.8261 Hz (section 0). The MEGA65 core and the original Ultimate 64 use it [src].
- The Ultimate 64 Elite II ships 480p, 720p and 1080p at 59.826 Hz with CTA totals and a detuned clock (option a) [src].
- NES and SNES (60.10 Hz, +0.16 % vs 60.00):
  - [sum] The commercial FPGA consoles slow the console to 60.00 Hz in their zero-delay HDMI modes (section 3.8).
  - [field] MiSTer users output 60.10 Hz through `vsync_adjust` with the mixed results of section 3.3; issue #1343 reports Scramble at 60.606 Hz on 1080p60 stable on "a handful of displays" once the PLL issue was fixed.
- No NTSC-specific display statistics were found. MiSTer's own note warns in both directions ("NTSC monitors may not support PAL", "PAL monitors may not support NTSC").

## 7. Assessment of (a) to (d)

**(a) Standard totals, pixel clock moved: best chance.**

- It is the only option that remains the CTA format: totals, porches, sync widths and VIC unchanged, clock inside the 0.5 % that 861-B obliges sinks to accept and that 861-G cites.
- Both receiver families of section 2.2 accept it: frequency-tolerance tables (0.12 Hz, 0.09 kHz off) and exact-count/VIC matchers (Linux ADV76xx: clock within 250 kHz; Xilinx: totals identical, VIC consistent).
- It is what the newest designs converged on: Ultimate 64 Elite II (all CTA modes), BMC64 Pi 4/5 (with a hard 0.5 % guard), OSSC Pro framelock, MiSTer `vsync_adjust`.
- Caveats: MiSTer's "Not every display supports variable pixel clock", RetroTINK's "may not work with some TVs". The rejections reported for MiSTer mostly involve rates far from 50/60 Hz (57 Hz arcade cores, 60.6 Hz) or the 60 Hz-base timings, not a 0.25 % shift of a CTA mode.

**(b) Standard clock, changed totals: second.**

- Exact only for NTSC 480p (858 x 526 at 27 MHz). The MEGA65 core and the original U64 used it on many displays without reported trouble.
- Elsewhere it leaves 40 to 900 ppm of error that still needs a genlock.
- It turns the format into an IT timing (VIC 0 needed, PC-path defaults such as underscan and full-range RGB), and it fails exact-count matchers.
- It has no advantage over (a) on frequency-tolerance sinks.

**(c) Other clock and other totals: third.**

- The small variant (original U64: 864 x 624 at 27.024 MHz, VIC 17; MiSTer's 60 Hz-base 720p at 50 Hz) is evidently accepted by many displays.
- But it has the IT-format drawbacks of (b), and the variants with a non-standard active size are the ones whose authors warn of incompatibility (BMC64, Kawari wide).

**(d) Modulated totals: worst.**

- Per-line H-total alternation conflicts with receivers that require identical consecutive timing measurements.
- Per-frame V-blank stretching is VRR, which only sinks that declare VRR are meant to follow; gbs-control's line-modulation lock warns "disable if display unstable or stays blank".
- Residual drift should instead be handled by deriving the HDMI clock coherently from the core clock (as the U64 and OSSC Pro do), by a very slow ppm-level clock trim (far below the 0.06 % steps gbs-control found safe), or by accepting a frame slip every few hours (MiSTer).

**Remaining uncertainty.**

- No systematic statistics exist; all compatibility statements are per-project anecdotes.
- TV SoC (MediaTek, Realtek TV) mode detection is not public; the open receiver code (ADV76xx, Xilinx, RTD2662, MStar) is a proxy.
- "Accepted" does not mean "smooth": a sink that free-runs its panel at 50.00 Hz still drops a frame every 8 s, whichever option is used.
- The 50 Hz family has no 1000/1001 sibling, so +0.25 % at 50 Hz is further from what sinks routinely see than -0.19 % from 59.94 Hz.
- Switching between the standard and the native-rate mode is a frame-rate change and costs a 1 to 3 s re-sync on most sinks.
- Every project that offers a native-rate mode keeps a standard 50.00/60.00 Hz mode as the safe default (BMC64, Kawari, MiSTer, RetroTINK triple buffer).
