# NTSC support

The C64 for MEGA65 core can run as a PAL C64 (the default) or as an NTSC C64. This document
describes how NTSC works in the core, for developers. The binding design, with every number
derived and every file and signal named, is [`doc/dev-ntsc/NTSC-SPEC.md`](dev-ntsc/NTSC-SPEC.md);
the issue is [#181](https://github.com/MJoergen/C64MEGA65/issues/181).

NTSC support is new in WIP-V6-A22 and has not yet been tested on hardware; the hardware test
protocol is the `Version WIP-V6-A22` section of [`tests/README.md`](../tests/README.md).


## What the user gets

* `Model > PAL / NTSC` in the on-screen menu selects the machine. PAL stays the default; the
  choice is saved in the C64MEGA65 config file like every other menu setting.
* NTSC is a C64 with the newer NTSC VIC-II **6567R8**: 65 cycles per line, 263 lines per frame,
  59.826 frames per second, CPU clock 1.0227 MHz. The CIA time-of-day clocks run from a 60 Hz
  reference, the simulated 1541 and 1581 drives keep running at exactly 1 MHz.
* Every change of the machine mode resets the C64 automatically (a soft reset, like a short
  press of the reset button), so that the KERNAL detects the new region.
* HDMI: in NTSC the `HDMI Display Mode` submenu offers `16:9 720p 59.94 Hz`, `4:3 480p 59.94 Hz`
  and `5:4 480p 59.94 Hz` instead of the three 50 Hz modes, plus its own `HDMI: Flicker-free`
  switch (on by default).
* VGA: the analog output runs at 59.83 Hz in NTSC. The `Standard` mode (31.47 kHz) suits VGA
  monitors that only accept 60 Hz; the two retro 15 kHz modes produce 15.73 kHz for CRTs.
* The on-screen menu is shown at 89 % of its size on VGA and on the two 480p HDMI modes in
  NTSC, because these outputs have fewer lines than the menu canvas.


## Machine mode in the core

The OSM bit `C_MENU_MACHINE_NTSC` becomes `c64_ntsc` in `CORE/vhdl/mega65.vhd` and reaches the
MiSTer core through `main.vhd`:

| Consumer | NTSC effect | Where |
|---|---|---|
| VIC-II | `mode6567R8` instead of `mode6569` | `fpga64_sid_iec.vhd` (`ntscmode`) |
| CIA TOD | reference `add_value` 120 instead of 100, divided by the exact core clock (`clk32_speed`), giving 60 Hz | `fpga64_sid_iec.vhd` |
| Video timing | `video_sync` in NTSC: 520 dots per line, 263 lines, 404 x 250 visible | `main.vhd` `video_sync_inst` |
| 1541 / 1581 chip enable | 16 MHz from the NTSC core clock | `main.vhd` `iec_drive_ce_proc` |
| GEOS real-time clock | counts the 16 MHz drive chip enable, like MiSTer | `main.vhd` `rtcf83_inst` |
| Core clock | the two NTSC MMCMs | `clk.vhd`, `mega65.vhd` `hr_core_speed` |
| HDMI mode | the three 59.94 Hz modes | `mega65.vhd` `qnice_video_mode_o` |

`clk_main_speed_i` always carries the nominal clock of the active standard
(`CORE_CLK_SPEED_PAL = 31_527_778` or `CORE_CLK_SPEED_NTSC = 32_727_273` in `globals.vhd`),
also while the HDMI flicker-free clock is running. These two values are the integer frequencies
of the two original MMCM outputs, so TOD and the drive chip enable are exact (verified by
`CORE/vhdl/test/tb_ntsc/run.sh dividers`).

Two consumers of the clock frequency deliberately stay on the PAL constant `CORE_CLK_SPEED`: the
joystick debouncer and the MEGA65 keyboard scanner in `framework.vhd`. In NTSC their timing is
3.8 % shorter, which neither of them cares about.


## Clocks

The core clock is 32 times the C64 CPU clock. A real NTSC C64 derives it from the color burst
crystal: 14.31818 MHz x 16 / 7 = 32.727273 MHz. `CORE/vhdl/clk.vhd` runs four MMCMs from the
MEGA65's 100 MHz oscillator, all permanently:

| Clock | MMCM | M / D / O0 | VCO | Frequency | C64 frame rate | Versus the real C64 |
|---|---|---|---|---|---|---|
| PAL original | `i_clk_c64_orig` | 56.750 / 6 / 30.000 | 945.833 MHz | 31.527778 MHz | 50.124291 Hz | -5.6 ppm |
| PAL flicker-free | `i_clk_c64_slow` | 60.500 / 9 / 21.375 | 672.222 MHz | 31.448993 MHz | 49.999035 Hz | -0.25 % |
| NTSC original | `i_clk_c64_ntsc` | 36.000 / 5 / 22.000 | 720.000 MHz | 32.727273 MHz | 59.826105 Hz | 0 ppm |
| NTSC flicker-free | `i_clk_c64_ntsc_ff` | 47.750 / 5 / 29.125 | 955.000 MHz | 32.789700 MHz | 59.940223 Hz | +0.19 % |

The NTSC original clock is exact (100 MHz x 36 / 5 / 22 = 360 / 11 MHz) and uses integer
dividers only. A frame of the 6567R8 is 65 x 263 x 32 = 547 040 core clock cycles, a frame of the
PAL 6569 is 63 x 312 x 32 = 628 992. The parameter search that produced these sets is
`python3 doc/dev-ntsc/tools/ntsc_clocks.py --final`; [speed.md](speed.md) compares them with the
real machines and with MiSTer.

A two-level tree of glitch-free `BUFGCTRL` multiplexers selects the clock: `core_speed_i(0)`
chooses between the original and the flicker-free clock of a standard, `core_speed_i(1)` the
standard (`00` PAL original, `01` PAL flicker-free, `10` NTSC original, `11` NTSC flicker-free).
Glitch-free switching requires both inputs of a `BUFGCTRL` to be running, which is why all four
MMCMs run all the time instead of reprogramming one MMCM the way MiSTer does. The design is timed
once, at its fastest clock (NTSC flicker-free, 30.497 ns), see `CORE/CORE.xdc`.


## HDMI flicker-free in NTSC

A C64 never produces exactly the frame rate of an HDMI mode. With `HDMI: Flicker-free` on, the
core alternates between the original and the flicker-free clock of its standard so that the
average frame rate equals the HDMI frame rate. `M2M/vhdl/hdmi_flicker_free.vhd` watches how far
the C64 is ahead of the HDMI output in the ascal frame buffer and pulses `hr_high_i` (core too
fast) or `hr_low_i` (core too slow); the `hr_core_speed` process in `mega65.vhd` switches the
clock.

The polarity is the important difference between the standards:

| Standard | HDMI rate | Original clock | Flicker-free clock | "core too slow" selects | "core too fast" selects |
|---|---|---|---|---|---|
| PAL | 50.000 Hz | 50.124 Hz (faster) | 49.999 Hz (slower) | original (`00`) | flicker-free (`01`) |
| NTSC | 59.940 Hz (480p), 59.933 Hz (720p) | 59.826 Hz (slower) | 59.940 Hz (faster) | flicker-free (`11`) | original (`10`) |

In both standards the core spends almost all the time on the flicker-free clock (PAL 99.2 %,
NTSC 480p 99.86 %, NTSC 720p 93.4 %) and drops to the original clock for about 0.2 s per
correction. The NTSC flicker-free clock is the legal MMCM output closest above 59.94 Hz
(+2.7 ppm); it also serves 720p59.94, whose pixel clock is 74.1667 MHz instead of 74.176 MHz
(59.933 Hz), so one clock covers both NTSC HDMI containers. Core clock and HDMI pixel clock
come from the same oscillator, so their ratio is exact and the small margin is enough.
`doc/dev-ntsc/tools/ff_model.py` is a closed-loop model of this regulation.

While the flicker-free clock runs, the whole C64 including SID pitch, TOD, the drives and the
GEOS clock runs 0.19 % fast in NTSC (0.25 % slow in PAL): over 10 minutes TOD gains about 1.1 s
in NTSC and loses about 1.5 s in PAL, so TOD accuracy is measured with `HDMI: Flicker-free` off.
TOD and the drives keep the nominal clock as their reference on purpose, so the speed ratio between C64 and drive stays that of a
real machine ([issue #2](https://github.com/MJoergen/C64MEGA65/issues/2)). With flicker-free off,
a 59.826 Hz C64 on a 59.94 Hz display shows a short stutter about every 9 seconds.


## HDMI modes and framing

| Display mode | HDMI signal | CTA VIC | Pixel clock | Frame rate | Picture (no zoom) |
|---|---|---|---|---|---|
| `16:9 720p 59.94 Hz` | 1280x720p59.94, 16:9 | 4 | 74.1667 MHz | 59.932660 Hz | 960 x 720 window, 4:3 pillarbox |
| `4:3 480p 59.94 Hz` | 720x480p59.94, signaled 4:3 | 2 | 27.000 MHz | 59.940060 Hz | full 720 x 480 container |
| `5:4 480p 59.94 Hz` | 720x480p59.94, signaled 4:3 | 2 | 27.000 MHz | 59.940060 Hz | 720 x 451 letterbox |

These mirror the PAL modes: both 576p items send the same 720x576p50 signal, the `5:4` item
letterboxes it so that a 5:4 display, which shows any signal as 5:4, shows a 4:3 picture
(`V x 15/16` of the height). The new mode record is `C_HDMI_720p_5994` in
`M2M/vhdl/av_pipeline/video_modes_pkg.vhd`; its `CLK_KHZ` is the true 74167 kHz because the
HDMI audio clock regeneration uses it. The machine standard reaches the M2M video pipeline only
through the HDMI mode: `qnice_video_mode_o` is one of the three `*_5994` modes exactly when the
machine is NTSC. [hdmi.md](hdmi.md) lists all six modes.

The scaler input in NTSC is 404 x 250 pixels at 59.826 Hz (PAL: 382 x 270 at 50.124 Hz), the
same blanking that MiSTer's `video_sync.vhd` produces ("NTSC mode has 250 visible lines only").
`CORE/vhdl/test/tb_ntsc/run.sh video` measures both geometries with the real VIC-II. The picture
is framed as 4:3 in both standards. That gives NTSC pixels an aspect ratio of 0.825; on a real
NTSC TV, which shows about 418 x 235 pixels as 4:3, they are 0.75. MiSTer's "Original" aspect
(400:300) does the same.

`HDMI: Zoom-in` crops the picture to the 320 x 200 screen plus 14 / 4 border pixels (348 x 208)
in both standards. `crop.vhd` finds that window at `LEFT_BORDER_IN = 33`, `TOP_BORDER_IN = 35`
in PAL and at `44`, `26` in NTSC, because the NTSC line is 16 dots longer and the visible area
starts at a different raster line.

The ascal input bandwidth grows by 17 % in NTSC (6.04 instead of 5.17 Mpixel/s). On R3/R3A the
frame buffer shares the HyperRAM with the simulated cartridge and the simulated REU; R4 and later
keep the frame buffer in SDRAM.


## Analog VGA in NTSC

The analog pipeline recovers its geometry from the sync and blanking signals and contains no PAL
constant, so it needs no NTSC code:

| VGA mode | Line rate | Frame rate | Visible |
|---|---|---|---|
| Standard (scandoubled) | 31.469 kHz | 59.826 Hz | 808 x 500 |
| Retro 15 kHz with HS/VS or CSYNC | 15.734 kHz | 59.826 Hz | 404 x 250 |

The 31 kHz mode is within the range of any VGA monitor that accepts 640 x 480 at 60 Hz, which is
the use case of old 60 Hz-only VGA monitors. MiSTer's NTSC `video_sync` starts the vertical sync
on the first blanked line (no vertical front porch); the core keeps that for parity.
"HDMI: Flicker-free" should stay off when an analog display is used, exactly as in PAL.


## On-screen menu in NTSC

The OSM is drawn on a 720 x 540 canvas; the options menu needs 496 lines and the help pages and
the file browser 528. In NTSC some outputs have fewer lines: VGA Standard 500, VGA 15 kHz 250
(showing every second canvas line) and HDMI 480p 480. To keep everything visible without changing
the font or the menu, `M2M/vhdl/av_pipeline/av_pipeline.vhd` raises the OSM scaling to at least
89 % (`osm_scaling`) on VGA in NTSC and on both 480p modes, and `video_overlay.vhd` moves the OSM
24 lines up on the 480p modes (`vga_cfg_vshift_i`). 720p59.94 and all PAL outputs are unchanged.
The `OSM Scaling` submenu in `Advanced Settings` still shows the user's own value. The Shell does
not need to know the standard.


## Mode-change reset and power-on

The KERNAL decides between PAL and NTSC once, during its reset routine, and stores the result at
`$02A6` (1 = PAL, 0 = NTSC; `PRINT PEEK(678)` shows it). A machine-mode change therefore resets
the C64. `mode_change_reset_proc` in `CORE/vhdl/main.vhd`:

1. detects every change of `c64_ntsc_i` (`ntsc_d` starts as PAL),
2. waits until no virtual drive is writing back its cache (`prevent_reset = '0'`); a change
   during a write-back is never dropped, and several changes inside one write-back give one
   reset,
3. raises `mode_reset` for `C_MODE_RST_LEN = 1024` core clock cycles (31 us).

`mode_reset` joins `hard_reset_proc` next to the reset button and `cart_soft_reset`: the C64 gets
a soft reset through `reset_core_n` (cartridges start again, simulated cartridges are
re-initialized, the simulated drives are reset and unmount their disk image if their
`Unmount on reset` setting is on), a hardware cartridge sees `/RESET`, and the hard reset is never
asserted. The `RESET SEMANTICS` comment in `main.vhd` lists this as the fourth soft-reset source.

One change of the OSM bit causes, in parallel and within a few microseconds: the VIC-II mode and
`clk_main_speed_i` switch in the same core clock cycle; the clock tree switches to the clocks of
the new standard a few HyperRAM clock cycles later, inside the reset window; the HDMI output
switches to the HDMI mode of the new standard (a short blank screen, as with any HDMI mode
change); after the reset the KERNAL measures the raster lines and sets `$02A6`.

At power-on the C64 is held in reset while the Shell restores the config file: `CSR_DEFAULT`
(`M2M/vhdl/QNICE/qnice.vhd`) starts the Shell with the reset bit of `M2M$CSR` set,
`HELP_MENU_INIT` (`M2M/rom/options.asm`) loads the config file and writes the menu state, and only
then does `RP_SYSTEM_START` (`M2M/rom/gencfg.asm`) release the reset. If the config file says NTSC,
`c64_ntsc_i` therefore changes while the C64 is still in reset, and the first KERNAL boot is already
NTSC; there is no visible PAL phase. The mode-change reset machinery covers this case all the same:
`ntsc_d` starts as PAL, so the restore is an ordinary mode change, and its pulse falls inside the
reset that the Shell holds anyway, where it is harmless.

`CORE/vhdl/test/tb_ntsc/run_w3.sh` simulates the mode-change reset (one toggle, toggles during a
write-back, a toggle during a running reset, power-on in PAL and in NTSC) against a verbatim copy
of the processes in `main.vhd`.


## Parity with MiSTer

The core follows the MiSTer C64 core (`CORE/C64_MiSTerMEGA65/c64.sv`) wherever the MEGA65 allows
it, and the submodule needed no change:

| Topic | MiSTer | C64MEGA65 |
|---|---|---|
| Menu | `Video Standard: PAL, NTSC` | `Model > PAL / NTSC`, same semantics, default PAL |
| VIC-II, CIA TOD | `ntscmode` into `fpga64_sid_iec` | same |
| Drive chip enable | `drive_ce` accumulator with `msum = ntsc ? 32727264 : 31527954` | same algorithm with our exact clocks 32 727 273 / 31 527 778 |
| `video_sync` | `.ntsc(ntsc)`, `.wide` only for 600 / 800 line HDMI modes | `ntsc => c64_ntsc_i`, `wide => '0'` |
| GEOS RTC | `rtcF83 #(16000000, 0)` with `.ce(drive_ce)` | same |
| Pixel clock | `clk_sys / 4` | same |
| Core clock | one PLL, fractional `K` reprogrammed on a mode change | four fixed MMCMs and a glitch-free mux tree (flicker-free needs two running clocks per standard) |
| Reset on mode change | about 3 ms reset while the PLL relocks, optionally clearing RAM | 1024-cycle soft reset, deferred during a disk write-back |
| HDMI rate | chosen by `MiSTer.ini`, optionally bent with `vsync_adjust` | fixed 59.94 Hz modes plus flicker-free core clock switching |
| Vertical crop | `vcrop` / `video_freak` | not present; "HDMI: Zoom-in" has NTSC constants instead |


## Not supported

* No PAL-N (6572) and no old NTSC (6567R56A, 64 cycles x 262 lines). Both would be further
  entries of the same `Model` group with their own clocks; see [vic_ii_variants.md](vic_ii_variants.md).
* No 60.00 Hz HDMI modes, no 640x480 and no variable pixel clock (see below).
* No "HDMI: Raw 50.1 Hz" and no NTSC raw mode.
* The keyboard scanner and the joystick debouncer use the PAL clock constant in both standards
  (harmless, see above).


## Background: why these HDMI modes

### 59.94 Hz instead of 60.00 Hz

59.94 Hz is the NTSC-family rate (60 x 1000 / 1001 = 59.94006 Hz). HDMI/CTA-861 uses the same
video identification code for the 60 Hz and the 59.94 Hz variant of a format, and displays treat
both as standard modes. A real NTSC C64 produces 59.826 Hz, so neither rate is native, but
59.94 Hz is the closer one: matching it needs the C64 0.19 % faster, matching 60.00 Hz would
need 0.29 %. A truly native 59.826 Hz output would need a variable pixel clock (MiSTer's
`vsync_adjust`, which MiSTer itself marks as not supported by every display).

### 720x480 instead of 640x480

The PAL labels describe the target monitor, not the pixel grid: `720x576` is a 5:4 pixel grid
that is signaled as 4:3. The NTSC counterpart of the PAL SDTV container is `720x480` (a 3:2 grid,
also signaled as 4:3), not the square-pixel VGA mode `640x480`. The OSM path also assumes a
720 pixel wide output (`hdmi_shift = H_PIXELS - 720` in `digital_pipeline.vhd` would become
negative for 640x480), while `720x480` fits it unchanged. 640x480 remains a possible
compatibility mode for the future.

### The NTSC C64 picture is 4:3 with narrow pixels

| VIC-II | Lines | Cycles per line | Approximate visible raster on a TV |
|---|---|---|---|
| PAL 6569 | 312 | 63 | 403 x 284 |
| NTSC 6567R8 | 263 | 65 | 418 x 235 |
| old NTSC 6567R56A | 262 | 64 | 411 x 234 |

418 x 235 is almost 16:9 by pixel count, but the C64 was made for a 4:3 TV: shown as 4:3, an NTSC
C64 pixel is about 0.75 times as wide as it is high. The core shows the 404 x 250 area that MiSTer
shows, framed as 4:3.

### HDMI clocks that already existed

`M2M/vhdl/controllers/HDMI/video_out_clock.vhd` provides the NTSC-family pixel clocks through its
`CLK_SEL` values; `"001"` (27.000 MHz, 720x480p59.94) and `"110"` (labeled 74.176 MHz, 1280x720p59.94)
are the ones the NTSC modes use. `"110"` really produces 74.1667 MHz (`CLKFBOUT_MULT_F` 22.25,
`DIVCLK_DIVIDE` 3, `CLKOUT1` 10); no single-MMCM configuration with the 5:1 serializer ratio does
better, and the -124 ppm are well within the HDMI tolerance.

References:

- MiSTer C64 core: <https://github.com/MiSTer-devel/C64_MiSTer>
- MiSTer default configuration comments (`vsync_adjust`): <https://github.com/MiSTer-devel/Main_MiSTer/blob/master/MiSTer.ini>
- Christian Bauer, The MOS 6567/6569 video controller (VIC-II): <https://www.cebix.net/VIC-Article.txt>
- VICE VIC-II timing files: <https://github.com/VICE-Team/svn-mirror/tree/main/vice/src/viciisc>
- Linux DRM EDID/CEA mode handling (59.94 Hz and 60 Hz variants of the CEA modes): <https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_edid.c>
