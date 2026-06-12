# WIP thoughts on NTSC HDMI modes

This is a working note, not an implementation plan. It summarizes the current
research around adding NTSC C64 HDMI modes to C64MEGA65.

## Short recommendation

The PAL menu currently offers three user-facing choices:

```text
16:9 720p 50 Hz
4:3  576p 50 Hz
5:4  576p 50 Hz
```

The closest NTSC-facing equivalent should be:

```text
16:9 720p 59.94 Hz
4:3  480p 59.94 Hz
5:4  480p 59.94 Hz
```

The two 480p entries should use the same HDMI container timing:
`720x480p59.94`, with different scaler/framing behavior, just as the PAL
`4:3` and `5:4` entries both use the same `720x576p50` HDMI container today.

`640x480` should not be one of the three primary NTSC menu entries. It is a
valid and useful VGA compatibility mode, but it is not the best SDTV
counterpart to PAL `720x576p50`, and it currently runs against a 720-pixel-wide
assumption in the OSM overlay path.

## What the PAL entries really mean

The current PAL labels are user-facing, not a direct description of three
different pixel grids.

From `CORE/vhdl/mega65.vhd`, the code comment says that `4:3` means "meant to
be run on a 4:3 monitor" and `5:4` means "meant to be run on a 5:4 monitor".
It also says the technical reality is odd: the `5:4` mode applies a 4:3
adjustment, while the `4:3` mode outputs a 5:4-ish image.

The current PAL mode mapping is:

| User label | HDMI container | Container ratio | HDMI infoframe aspect |
| --- | --- | ---: | --- |
| `16:9 720p 50 Hz` | `1280x720p50` | `16:9` | 16:9 |
| `4:3 576p 50 Hz` | `720x576p50` | `5:4` | 4:3 |
| `5:4 576p 50 Hz` | `720x576p50` | `5:4` | 4:3 |

The important point: `720x576` is not square-pixel 4:3. It is an SDTV
container that can be signaled as 4:3 through the HDMI/CTA video mode and
aspect metadata. Therefore the NTSC equivalent should prefer the matching SDTV
container, `720x480`, over square-pixel VGA `640x480`.

## C64 NTSC aspect ratio

The C64 was designed for a 4:3 television display, but the VIC-II pixel grid is
not square-pixel 4:3.

For the newer NTSC VIC-II model, the core and common VIC-II documentation agree
on:

| VIC-II mode | Lines | Cycles per line | Approx visible raster |
| --- | ---: | ---: | ---: |
| PAL 6569 | 312 | 63 | `403x284` |
| NTSC 6567R8 | 263 | 65 | `418x235` |
| old NTSC 6567R56A | 262 | 64 | `411x234` |

The NTSC visible raster ratio `418/235` is about `1.779:1`, which is almost
16:9 by raw pixel count. That does not mean the C64 is widescreen. It means the
NTSC VIC pixels are narrow when shown on the intended 4:3 TV display.

If the `418x235` visible raster is displayed as 4:3, the approximate pixel
aspect ratio is:

```text
(4/3) / (418/235) = 470/627 = 0.7496
```

So the practical statement is:

> NTSC C64 is a 4:3 television image with strongly non-square pixels.

This is why `640x480` is not inherently "more correct" just because it is
square-pixel 4:3. It is a useful output container, not the native C64 aspect
model.

## Offered resolution ratios

| HDMI container | Pixel grid ratio | Intended use |
| --- | ---: | --- |
| `1280x720` | `16:9` | HD 16:9 container; C64 should be pillarboxed/framed inside it |
| `720x480` | `3:2` | NTSC SDTV container; can be signaled as 4:3 |
| `640x480` | `4:3` | VGA square-pixel 4:3 compatibility mode |
| `720x576` | `5:4` | PAL SDTV container; can be signaled as 4:3 |

The current PAL behavior already depends on the distinction between pixel-grid
ratio and intended display aspect. NTSC should follow the same model.

## 59.94 Hz versus 60.00 Hz

`59.94 Hz` is not an odd unofficial frequency. It is the NTSC-family rate:

```text
60 * 1000 / 1001 = 59.94005994...
```

HDMI/CTA and common display stacks treat the familiar NTSC-family modes as
normal video modes. In Linux DRM, for example, the CEA table contains the 480p
and 720p modes and explicitly checks both the 60.00 and 59.94 alternate clocks
when matching CEA modes.

The relevant modes are:

| Mode | Pixel clock | Notes |
| --- | ---: | --- |
| `640x480p59.94` | `25.175 MHz` | CTA VIC 1 / VGA-family baseline, often labeled 60 Hz |
| `720x480p59.94` | `27.000 MHz` | CTA VIC 2/3, 4:3/16:9 SDTV |
| `1280x720p60.00` | `74.250 MHz` | CTA VIC 4 |
| `1280x720p59.94` | `74.25 / 1.001 = 74.176 MHz` | NTSC-family alternate of 720p60 |

For C64MEGA65 menu labels, `59.94 Hz` is technically more honest for NTSC TV
modes than `60 Hz`. It is also closer to real NTSC C64 cadence than exact
60.00 Hz, although neither is exact.

## Real NTSC C64 cadence

MiSTer C64 uses an NTSC main clock value of `32_727_264`. With new NTSC VIC-II
geometry:

```text
65 cycles/line * 263 lines/frame * 32 main clocks/cycle = 547040 main clocks/frame
32727264 / 547040 = 59.8260895 Hz
```

So a truly authentic NTSC C64 frame rate is about `59.826 Hz`, not `59.94 Hz`
and not `60.00 Hz`.

If the core clock is deliberately shifted so that C64 frames exactly match a
fixed HDMI output rate:

| Target output | Required average main clock | Speed error versus MiSTer NTSC clock |
| --- | ---: | ---: |
| `59.94 Hz` | `32_789_610.39 Hz` | `+0.1905%` |
| `60.00 Hz` | `32_822_400.00 Hz` | `+0.2907%` |

Therefore `59.94 Hz` is the better fixed-rate compromise. Exact native cadence
would need MiSTer-style variable pixel-clock adjustment or VRR-like behavior,
and that is a display compatibility question.

## What MiSTer does

MiSTer separates two concerns:

1. The C64 core exposes `Video Standard: PAL, NTSC`.
2. HDMI output mode is selected by the framework/configuration, not by the C64
   core itself.

The MiSTer C64 core wires the PAL/NTSC menu bit into `ntscmode`, and the
MiSTer framework offers global modes such as `1280x720@60`, `720x480@60`,
`640x480@60`, and `1280x720@50`.

MiSTer also has `vsync_adjust`. The MiSTer.ini comment says this adjusts the
HDMI VSync rate to match the original system by changing the pixel clock, and
warns that not every display supports variable pixel clocks. It recommends
using a 60 Hz HDMI mode as the base even for 50 Hz systems to reduce the pixel
clock adjustment range.

This is an important distinction for C64MEGA65:

- fixed `59.94 Hz` HDMI timings are normal and broadly supported;
- truly native `59.826 Hz` C64 output is the nonstandard/compatibility-sensitive
  case.

## Current C64MEGA65/M2M state

Relevant existing M2M video mode records:

| Constant | Meaning |
| --- | --- |
| `C_HDMI_720x480p_5994` | `720x480p59.94`, VIC 2, 4:3 |
| `C_HDMI_640x480p_60` | `640x480p60.00`, VIC 1 |
| `C_HDMI_720p_60` | `1280x720p60.00`, VIC 4 |
| `C_HDMI_576p_50` | `720x576p50`, VIC 17, 4:3 |
| `C_HDMI_720p_50` | `1280x720p50`, VIC 19, 16:9 |

The HDMI output clock generator already contains useful NTSC-family selectors:

| `CLK_SEL` | Clock | Comment in code |
| --- | ---: | --- |
| `"000"` | `25.200 MHz` | `640x480 @ 60.00 Hz` |
| `"001"` | `27.000 MHz` | `720x480 @ 59.94 Hz` |
| `"010"` | `74.250 MHz` | `1280x720 @ 60.00 Hz` |
| `"100"` | `25.175 MHz` | `640x480 @ 59.94 Hz` |
| `"101"` | `27.027 MHz` | `720x480 @ 60.00 Hz` |
| `"110"` | `74.176 MHz` | `1280x720 @ 59.94 Hz` |

So the clocking side is already close. Missing pieces include mode records and
menu/wiring for `1280x720p59.94` if we choose to label the HD NTSC mode
accurately.

## Why not make 640x480 one of the three main modes

`640x480` is valid, but it is not the best primary NTSC SD mode here:

1. It is a VGA square-pixel container, not the NTSC SDTV counterpart to
   `720x576p50`.
2. The current core-side rendered size is `VGA_DX = 720`, `VGA_DY = 540`.
3. `digital_pipeline.vhd` computes the OSM shift as:

   ```vhdl
   hdmi_shift <= hdmi_video_mode.H_PIXELS - integer(G_VGA_DX);
   ```

   For `640x480`, this becomes `640 - 720 = -80`.
4. That shift is connected to `video_overlay.vhd`, where `vga_cfg_shift_i` is a
   `natural`. Even if the current synthesis flow tolerates this path, the math
   is conceptually wrong for a 640-wide output.
5. `720x480` gives shift `0` and fits the current 720-wide assumptions.

Conclusion: keep `640x480` as a possible advanced/compatibility mode, but do
not use it for the main NTSC trio unless the OSM/overlay path is fixed and
tested.

## Implementation readiness

The HDMI modes are only one part of NTSC support. Current blockers and TODOs:

- `CORE/vhdl/mega65.vhd` still hardcodes `c64_ntsc <= '0'`.
- `CORE/vhdl/main.vhd` still instantiates `video_sync` with `ntsc => '0'`.
- `CORE/vhdl/globals.vhd` defines `CORE_CLK_SPEED_NTSC`, but the active
  `CORE_CLK_SPEED` remains PAL.
- The flicker-free clock switching logic currently only embraces PAL 50 Hz
  behavior, with comments about `50.124 Hz` and `49.999 Hz`.
- The current HDMI menu already contains NTSC-looking entries, but
  `mega65.vhd` deliberately does not wire them yet.

These are separate from whether `720x480p59.94` or `1280x720p59.94` are valid
HDMI modes. They are valid; the C64MEGA65 NTSC core/video/clock path still
needs to be completed.

## Proposed path

For the main user-facing NTSC menu:

1. Use `1280x720p59.94` for `16:9 720p 59.94 Hz`.
2. Use `720x480p59.94` for `4:3 480p 59.94 Hz`.
3. Use `720x480p59.94` again for `5:4 480p 59.94 Hz`, with different scaler
   framing.

If compatibility feedback shows that exact 60.00 Hz is needed by some displays,
add it as a compatibility option or fallback, but do not make it the default
technical description for NTSC-family TV modes.

## Source pointers

Local code:

- `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`
- `M2M/vhdl/controllers/HDMI/video_out_clock.vhd`
- `M2M/vhdl/av_pipeline/digital_pipeline.vhd`
- `M2M/vhdl/av_pipeline/video_overlay.vhd`
- `CORE/vhdl/globals.vhd`
- `CORE/vhdl/mega65.vhd`
- `CORE/vhdl/main.vhd`
- `CORE/C64_MiSTerMEGA65/c64.sv`
- `CORE/C64_MiSTerMEGA65/rtl/video_vicII_656x.vhd`

External references used during research:

- MiSTer C64 core: <https://github.com/MiSTer-devel/C64_MiSTer>
- MiSTer default configuration comments: <https://github.com/MiSTer-devel/Main_MiSTer/blob/master/MiSTer.ini>
- Cebix VIC-II article: <https://www.cebix.net/VIC-Article.txt>
- VICE VIC-II timing files: <https://github.com/VICE-Team/svn-mirror/tree/main/vice/src/viciisc>
- Linux DRM EDID/CEA mode handling: <https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/drm_edid.c>
