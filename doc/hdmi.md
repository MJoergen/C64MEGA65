# Description of the various HDMI screen resolution modes

## Config menu
The `HDMI: <mode>` submenu of the on-screen menu contains:

* HDMI Display Mode: three display modes for PAL and three for NTSC. The menu only shows the
  three modes of the machine mode that is active in `Model` (PAL or NTSC), and each machine mode
  remembers its own choice.
* HDMI Frame Sync: `Off`, `Flicker-free` (default) and `Raw 50.1 Hz` (PAL) or `Raw 59.8 Hz`
  (NTSC). One radio group per machine mode; the menu only shows the one of the active machine
  mode, and each machine mode remembers its own choice. See
  [Frame rates: Off, Flicker-free and Raw](#frame-rates-off-flicker-free-and-raw).
* HDMI Options:
  * HDMI: DVI (no sound)
  * HDMI: \<filter\> (HDMI Filter submenu: No Filter / Sharp Bilinear / Bicubic / Smooth / Lanczos / Scanlines / CRT (S-Video) / CRT (Composite); default is "Scanlines", which is bit-identical to V5's "CRT emulation" look)
  * HDMI: Zoom-in

The display mode and "Zoom-in" decide the actual HDMI screen resolution and the framing of the
picture. The HDMI Filter submenu picks one of the polyphase coefficient pairs that are loaded
into ASCAL's polyphase scaler; see [`M2M/video_filters/README.md`](../M2M/video_filters/README.md)
for the per-filter character and the underlying mechanism.


## Possible resolutions

The names of the display modes describe the monitor they are meant for, not the pixel grid:
"4:3" is meant for a 4:3 monitor and "5:4" for a 5:4 monitor. In all modes the C64 picture is
shown with a 4:3 aspect ratio.

### PAL (machine mode PAL, the default)

* 16:9 720p 50 Hz: This is the default resolution with 1280x720 (16:9) image,
  but with a 160 pixel black border on the left and right sides, yielding an
  effective resolution of 960x720 matching the C64 cores 4:3 aspect ratio.

* 4:3 576p 50 Hz: This is the screen resolution 720x576 (5:4), matching the
  default MEGA65 output. There is no black border. The HDMI signal tells the
  display that the picture is 4:3, so the display stretches it to 4:3.

* 5:4 576p 50 Hz: The same 720x576 signal, but the picture is letterboxed to
  720x541 (rows 18 to 558), so that a 5:4 display, which shows the signal as
  5:4, shows the C64 picture as 4:3.

### NTSC (machine mode NTSC)

* 16:9 720p 59.94 Hz: 1280x720 with the same 960x720 4:3 window as in PAL. The
  pixel clock of this mode is 74.1667 MHz instead of the nominal 74.176 MHz
  (-124 ppm, well inside the HDMI tolerance), so the frame rate is 59.933 Hz;
  displays that print two decimals report 59.93 Hz.

* 4:3 480p 59.94 Hz: The NTSC TV resolution 720x480 (3:2), the counterpart of
  720x576 in PAL. There is no black border, the HDMI signal tells the display
  that the picture is 4:3.

* 5:4 480p 59.94 Hz: The same 720x480 signal, letterboxed to 720x451 (rows 15
  to 465) so that a 5:4 display shows the C64 picture as 4:3.

In NTSC the C64 produces 59.826 frames per second, so `Flicker-free` lets
the core run 0.19 % faster to match the 59.94 Hz of the HDMI output (in PAL the
core runs 0.25 % slower to match 50 Hz). See [ntsc.md](ntsc.md) for the details.
`Raw 59.8 Hz` instead runs the HDMI output at 59.826 Hz, see
[below](#frame-rates-off-flicker-free-and-raw).

On the 480p modes the on-screen menu is shown at 89 % of its size and moved up a
little, so that the whole menu fits into the 480 lines.

## Matching config menu with screen resolution

 Machine | Display mode        | HDMI signal (CTA VIC)      | Pixel clock  | Frame rate   | Picture without zoom          | Picture with "Zoom-in"
-------- | ------------------- | -------------------------- | ------------ | ------------ | ----------------------------- | ------
 PAL     | 16:9 720p 50 Hz     | 1280x720p50 (19), 16:9     | 74.250 MHz   | 50.000 Hz    | 960x720, black border         | full screen
 PAL     | 4:3 576p 50 Hz      | 720x576p50 (17), 4:3       | 27.000 MHz   | 50.000 Hz    | 720x576, no border            | full screen
 PAL     | 5:4 576p 50 Hz      | 720x576p50 (17), 4:3       | 27.000 MHz   | 50.000 Hz    | 720x541, black border         | full screen
 NTSC    | 16:9 720p 59.94 Hz  | 1280x720p59.94 (4), 16:9   | 74.1667 MHz  | 59.933 Hz    | 960x720, black border         | full screen
 NTSC    | 4:3 480p 59.94 Hz   | 720x480p59.94 (2), 4:3     | 27.000 MHz   | 59.940 Hz    | 720x480, no border            | full screen
 NTSC    | 5:4 480p 59.94 Hz   | 720x480p59.94 (2), 4:3     | 27.000 MHz   | 59.940 Hz    | 720x451, black border         | full screen

"Zoom-in" crops the picture to the 320x200 C64 screen plus a small part of the
border and scales that to the whole HDMI frame, in PAL and in NTSC.

Pixel clock and frame rate in this table are the ones of `Off` and `Flicker-free`; `Raw` changes
them, see the next section.


## Frame rates: Off, Flicker-free and Raw

A C64 does not produce 50 Hz or 59.94 Hz. `HDMI Frame Sync` decides how the core deals with that:

| `HDMI Frame Sync` | C64 speed | HDMI frame rate | Picture |
|---|---|---|---|
| `Off` | original (50.124 Hz PAL, 59.826 Hz NTSC) | 50.000 Hz (PAL), 59.94 Hz (NTSC) | a tear line crosses the picture every 8 to 9 seconds; scrollers jump |
| `Flicker-free` (default) | 0.25 % slower (PAL), 0.19 % faster (NTSC) | 50.000 Hz, 59.94 Hz | smooth |
| `Raw 50.1 Hz` (PAL), `Raw 59.8 Hz` (NTSC) | original | 50.124 Hz, 59.826 Hz | smooth, on displays that accept this rate |

The HDMI timing of the six display modes (totals = H total x V total in pixel clocks):

| Machine | Display mode | `Off`, `Flicker-free`: totals | Pixel clock | Frame rate | `Raw`: totals | Pixel clock | Frame rate |
|---|---|---|---|---|---|---|---|
| PAL | 16:9 720p 50 Hz | 1980 x 750 | 74.250 MHz | 50.000 Hz | 1980 x 750, plus 197 per frame (genlock) | 74.444 MHz | 50.124 Hz |
| PAL | 4:3 576p 50 Hz | 864 x 625 | 27.000 MHz | 50.000 Hz | 864 x 624 | 27.024 MHz | 50.124 Hz |
| PAL | 5:4 576p 50 Hz | 864 x 625 | 27.000 MHz | 50.000 Hz | 864 x 624 | 27.024 MHz | 50.124 Hz |
| NTSC | 16:9 720p 59.94 Hz | 1650 x 750 | 74.1667 MHz | 59.933 Hz | 1650 x 750, plus 463 per frame (genlock) | 74.0625 MHz | 59.826 Hz |
| NTSC | 4:3 480p 59.94 Hz | 858 x 525 | 27.000 MHz | 59.940 Hz | 858 x 526 | 27.000 MHz | 59.826 Hz |
| NTSC | 5:4 480p 59.94 Hz | 858 x 525 | 27.000 MHz | 59.940 Hz | 858 x 526 | 27.000 MHz | 59.826 Hz |

With `Raw` the core stays on its original clock, as with `Off`, and the HDMI output uses the raw
twin of the selected display mode. In 576p and 480p it is the timing of the Ultimate 64 (the
MEGA65's own core uses the same line counts): 576 + 4 + 5 + 39 = 624 lines (one line less in the
vertical front porch) and 480 + 9 + 6 + 31 = 526 lines (one line more in the vertical back
porch), so that an HDMI frame lasts exactly as long as a C64 frame. In 720p the standard totals
stay, with a pixel clock that makes the HDMI frame a little shorter than the C64 frame. The
scaler has one frame buffer, so the HDMI side has to read the picture at a fixed distance behind
the core: the genlock (`M2M/vhdl/av_pipeline/hdmi_genlock.vhd`) lengthens 16 lines of the vertical
back porch until the HDMI picture starts 2.0 ms after the C64's picture, and in 720p it adds the
missing pixel clocks in every frame. Lines with picture always keep their standard length, and
every raw mode keeps the sync positions and the CTA VIC of its standard mode.

After a change to a raw mode, a reset of the C64, a pause of the C64 (the file browser) or a
change between PAL and NTSC, the genlock needs at most 6.9 seconds (PAL 720p; 5.0 in NTSC 720p,
2.5 in 576p, 1.7 in 480p) to bring the HDMI picture to that distance; a tear line wanders through
the picture during a part of that time (less than a second). While the HDMI picture starts up to
2.5 ms later than the target, the genlock does not stretch at all. Switching zoom-in off moves
the C64's picture start 2.0 ms (PAL) or 1.4 ms (NTSC) earlier, into that range: in 720p the
distance glides back to the target within 15 s (PAL) or 4 s (NTSC) without a tear, in 576p and
480p the picture stays up to 2.5 ms later. Switching zoom-in on moves it back by the same amount,
and the genlock returns to the target within a second. Neither needs a new search; apart from the
moment of the switch itself (the scaler needs up to three frames for a new input size, in every
mode) the picture stays steady. While the C64 is paused, the genlock keeps the frame length of
the HDMI output. Which displays accept these frame rates is not known yet. Details:
[`dev-hdmi-raw/SPEC.md`](dev-hdmi-raw/SPEC.md).
