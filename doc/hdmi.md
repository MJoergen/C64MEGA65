# Description of the various HDMI screen resolution modes

## Config menu
The `HDMI: <mode>` submenu of the on-screen menu contains:

* HDMI Display Mode: three display modes for PAL and three for NTSC. The menu only shows the
  three modes of the machine mode that is active in `Model` (PAL or NTSC), and each machine mode
  remembers its own choice.
* HDMI: Flicker-free (one switch per machine mode, both on by default; only the one of the
  active machine mode is shown)
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

In NTSC the C64 produces 59.826 frames per second, so "HDMI: Flicker-free" lets
the core run 0.19 % faster to match the 59.94 Hz of the HDMI output (in PAL the
core runs 0.25 % slower to match 50 Hz). See [ntsc.md](ntsc.md) for the details.

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
