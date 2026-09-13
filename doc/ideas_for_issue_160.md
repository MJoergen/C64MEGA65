# Ideas for issue #160, Step 2 — zoom, scaling and aspect ratio on HDMI

Research notes for [MJoergen/C64MEGA65#160](https://github.com/MJoergen/C64MEGA65/issues/160)
("More sophisticated scalers and scandoublers"). Research only — no code was
changed. All numbers below are either read from the sources cited or derived
arithmetically in this document.

**Scope.** Step 1 of the issue (offer more than nearest-neighbor) shipped in V6
through issue #223: `CORE/vhdl/config.vhd:487-497` defines the eight-entry
"HDMI Filter" submenu and `CORE/m2m-rom/m2m-rom.asm:1290` / `:1334`
(`LOAD_HDMI_FILTER` / `HDMI_FLT_TABLE`) dispatches it to ascal's native
`NEAREST` / `SBILINEAR` / `BICUBIC` modes plus five polyphase coefficient sets.
This document therefore covers only **Step 2**: Viper's request about zoom and
aspect ratio.

The **scandoubler** half of the issue title is covered separately by the
research for [#250](https://github.com/MJoergen/C64MEGA65/issues/250) (analog 31
kHz, HQ2X, scanlines); nothing here overlaps with it. Everything in this
document concerns the digital HDMI path through `ascal.vhd`.

---

## 1. What Viper asked for

### 1.1 His message

Viper posted on Discord on 28.09.2024, with five screenshots. The substance:

> The current slightly horizontally stretched zoomed-in image looks incredibly
> good with hi-res char mode games like Nixy The Glade Sprite. However, I don't
> like the look in some games that use multi-colour mode. […] The zoom-in
> scaling with 216 lines maintains the 320x200 aspect ratio. […] As an
> additional scaling option to the integer scaling with 240 lines, also add the
> one with 216 lines and correct aspect ratio. I suggest to name it (C)AR Zoom
> in or Integer Zoom in (although it isn't integer at 720p, but at 1080p). […]
> Btw, the scalings with 270 and 216 lines are integers of 1080p, so it's a
> shame that 1080p support won't come anytime soon. […] I usually play in
> zoom-in mode, but for some games, I have to switch to my MiSTer to get the
> correct aspect ratio of the image.

### 1.2 Decoding the screenshots

The screenshots are **not** from the C64MEGA65. They are from **BMC64**, Randy
Rossi's bare-metal VICE build for the Raspberry Pi, which Viper used as a
measuring instrument because it exposes its scaler geometry on screen. Its
readout fields mean:

| Field | Meaning |
| --- | --- |
| `Display:` | the physical output mode (1280x720 in all his shots) |
| `FB:` | the source framebuffer he feeds the scaler — VICE's 384-pixel-wide PAL canvas, **vertically cropped** |
| `SFB:` | the scaled rectangle actually drawn on the 1280x720 screen |
| `H Stretch Factor` | `SFB_width / SFB_height`, i.e. the displayed aspect of that rectangle |
| green `x3,x3` | both scale factors came out as integers |

That last identification is confirmed by his own two data points:
`1026 / 720 = 1.425` and `1280 / 720 = 1.7778`, exactly the values his status
bar shows.

So his three candidates are:

| Shot | Source crop | Output rect | V scale | H scale | Comment |
| --- | --- | --- | --- | --- | --- |
| B | 384x270 | 1026x720 | 2.667 | 2.672 | "standard", uncropped |
| A | 384x240 | 1152x720 | **3.000** | **3.000** | "integer", his `x3,x3` shot |
| C | 384x216 | 1280x720 | 3.333 | 3.333 | his "(C)AR Zoom in" proposal |

**In all three, the horizontal and vertical scale factors are the same** —
exactly so for A and C, and to within rounding for B, whose 1.425 readout is a
three-decimal rendering of `384/270 = 1.4222`. That is the single most important
observation in this whole document: what Viper means by "maintains the 320x200
aspect ratio" is **square source pixels** — every C64 pixel drawn as a square
block, so the 320x200 screen appears as an 8:5 rectangle.

### 1.3 Where 240 and 216 come from

They are not his invention. They are literally MiSTer's own vertical-crop
presets, and we ship the file that contains them:

```
CORE/C64_MiSTerMEGA65/c64.sv:1223-1229
    if(HDMI_HEIGHT == 480)  vcrop <= 240;
    if(HDMI_HEIGHT == 600)  begin vcrop <= 200; wide <= vcrop_en; end
    if(HDMI_HEIGHT == 720)  vcrop <= 240;
    if(HDMI_HEIGHT == 768)  vcrop <= 256;
    if(HDMI_HEIGHT == 800)  begin vcrop <= 200; wide <= vcrop_en; end
    if(HDMI_HEIGHT == 1080) vcrop <= 10'd216;
    if(HDMI_HEIGHT == 1200) vcrop <= 240;
```

240 is MiSTer's preset for a 720-line display (720 / 240 = 3) and 216 is its
preset for a 1080-line display (1080 / 216 = 5). Viper is asking us to adopt
MiSTer's vertical-crop philosophy, and he applies the 1080p preset to a 720p
screen because at 720p it happens to fill the width exactly (384 x 720/216 =
1280).

The relevant MiSTer menu entries, in the same file:

```
CORE/C64_MiSTerMEGA65/c64.sv:211  "P1O45,Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];"
CORE/C64_MiSTerMEGA65/c64.sv:213  "d1P1o0,Vertical Crop,No,Yes;"
CORE/C64_MiSTerMEGA65/c64.sv:214  "P1OUV,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;"
```

### 1.4 What he is actually complaining about

Stripped of the BMC64 apparatus, the complaint is one sentence:

> **"HDMI: Zoom-in" does not preserve the aspect ratio — it stretches the
> cropped picture to fill the whole 16:9 frame.**

Section 2.4 shows that this is exactly right, and quantifies it.

### 1.5 An ambiguity that has to be resolved before implementing

Viper uses "correct aspect ratio" for two different things in the same message,
and they differ by 6.1 %:

- In his screenshots, "correct" means **square pixels** (`H scale = V scale`).
- When he says he switches to his MiSTer "to get the correct aspect ratio", he
  gets MiSTer's `Aspect Ratio: Original`, which for the C64 core is
  `ARX/ARY = 400/300 = 4:3` (`CORE/C64_MiSTerMEGA65/c64.sv:1241-1242`) — a
  **non-square** pixel aspect of `0.9424`.

Section 2.3 shows that 4:3 is also what the C64MEGA65 already uses for the
unzoomed picture, and that it is within 0.6 % of the true PAL geometry. Square
pixels are 6.1 % wider than that. Both looks have a legitimate constituency, so
the recommendation in section 5 offers both rather than picking one.

---

## 2. What the C64MEGA65 does today

### 2.1 The source picture

`CORE/vhdl/main.vhd:1652-1665` hands the framework the core's video through
`video_sync` (the copy in `CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd`, not the
M2M one — see the comment at `main.vhd:1649-1651`), with `ntsc => '0'` and
`wide => '0'`. Its PAL branch defines the active window:

```
CORE/C64_MiSTerMEGA65/rtl/video_sync.vhd:97-102
    if line_count = 298 then vblank <= '1'; end if;
    if line_count = 028 then vblank <= '0'; end if;
    if dot_count  = 489 then hblank <= '1'; end if;
    if dot_count  = 107 then hblank <= '0'; end if;
```

- Horizontal active: dots 107..488 → **382 pixels**
- Vertical active: lines 28..297 → **270 lines**

The pixel clock is the main clock divided by four
(`CORE/vhdl/main.vhd:1673-1680`), i.e. 31 527 778 / 4 = **7.881944 MHz**
(`CORE/vhdl/globals.vhd:47`).

NTSC is not wired yet: `CORE/vhdl/mega65.vhd:646` hardcodes `c64_ntsc <= '0'`
(issue #181), and the `ntsc` input of `video_sync` is tied to `'0'` as well.

### 2.2 The crop ("HDMI: Zoom-in")

`M2M/vhdl/av_pipeline/crop.vhd:44-58`:

```vhdl
constant LEFT_BORDER_IN    : natural := 33;
constant TOP_BORDER_IN     : natural := 35;
constant IMAGE_SIZE_X      : natural := 320;
constant IMAGE_SIZE_Y      : natural := 200;
constant LEFT_BORDER_NEW   : natural := 14;
constant RIGHT_BORDER_NEW  : natural := 14;
constant TOP_BORDER_NEW    : natural := 4;
constant BOTTOM_BORDER_NEW : natural := 4;
```

giving `X_MIN = 19`, `X_MAX = 366`, `Y_MIN = 31`, `Y_MAX = 238`, i.e. a crop of
**348 x 208**. The module does nothing but widen `hblank`/`vblank`; because
ascal runs with `iauto => '1'` (`M2M/vhdl/av_pipeline/digital_pipeline.vhd:369`)
and derives its input rectangle from `i_de`, extending the blanking *is* the
source crop.

Two facts worth noting:

- `crop.vhd` lives in `M2M/` but its constants are pure C64 geometry. It is
  byte-identical to the file in the M2M `develop` tree, so this is M2M's stock
  content rather than a local C64MEGA65 change — but it does mean the crop
  window is a synthesis-time constant with no runtime selection.
- The crop feeds **only** the digital pipeline. `i_crop` (`M2M/vhdl/av_pipeline/av_pipeline.vhd:506`)
  feeds `i_digital_pipeline` (`:529`) with `video_crop_*`, while `i_analog_pipeline`
  (`:390`) receives the raw `video_*_i`. Zoom-in is an HDMI-only feature, as its menu
  label says.

### 2.3 The output rectangle

`M2M/vhdl/av_pipeline/digital_pipeline.vhd:205-243` computes
`hdmi_hmin/hmax/vmin/vmax`, which become ascal's `hmin/hmax/vmin/vmax`
(`digital_pipeline.vhd:396-399`). Outside that rectangle ascal emits
`o_border`, wired to `X"000000"` (`digital_pipeline.vhd:341`,
`ascal.vhd:2891-2893`) — clean black bars at no cost.

| Condition | Rectangle |
| --- | --- |
| 16:9 modes, zoom off | centered `V_PIXELS*4/3` → **960x720** (bars 160/160) |
| 5:4 576p, zoom off | centered `H_PIXELS*3/4` → **720x541** at `vmin=18`, `vmax=558` |
| all other modes, zoom off | the full frame |
| **any mode, zoom on** | **the full frame** |

That last row is the bug Viper is describing: when zoom is on, the aspect ratio
computation is bypassed entirely.

The 5:4 row also exposes a **latent off-by-one**. Line 240 is the only branch in
the whole `hmin`/`hmax`/`vmin`/`vmax` network that does not end in `-1`:

```vhdl
-- digital_pipeline.vhd:240
(G_VIDEO_MODE_VECTOR(3).V_PIXELS+G_VIDEO_MODE_VECTOR(3).H_PIXELS*3/4)/2   when ...
--                                                                    ^ no "-1"
```

compare `:217`, `:218`, `:236-239` and `:241-244`, which all have it. Since ascal
computes the size as `o_vmax - o_vmin + 1` (`ascal.vhd:1893`), the 5:4 rectangle
is 541 lines with an asymmetric letterbox (18 lines above, 17 below) instead of
540 lines centered 18/18. See idea D in section 5.

**The pixel aspect ratio this implies.** Displaying a 382x270 source as 4:3
fixes the pixel aspect ratio at

    PAR = (4/3) / (382/270) = 1080/1146 = 180/191 = 0.942408

and, conveniently, `382 x 180/191 = 360` **exactly**. In other words the core's
active area is a 360x270 canvas in aspect-corrected units — a clean 4:3. Every
crop of `W x H` source pixels therefore has the correct display aspect

    AR = (W x 180/191) / H

which is the formula used throughout the rest of this document.

Is 0.942408 right? From first principles, the PAL VIC-II dot clock is 7.881984
MHz, PAL active video is 52 µs (409.86 dots) over 288 visible lines on a 4:3
tube, so the true PAL C64 pixel aspect is `(4/3) x (288/409.86) = 0.93690`
(VICE uses 0.9365). The core's 0.942408 is 0.6 % wider — negligible, and
identical to what MiSTer's C64 core uses. **The unzoomed picture is
geometrically correct.**

### 2.4 The measured error

| HDMI mode | Zoom | Output rect | Displayed AR | Correct AR | Error |
| --- | --- | --- | ---: | ---: | ---: |
| 16:9 720p 50/60 | off | 960x720 | 1.3333 | 1.3333 | 0.0 % |
| 16:9 720p 50/60 | **on** | 1280x720 | 1.7778 | 1.5767 | **+12.8 %** |
| 4:3 576p / 480p / 800x600 | off | full frame | 1.3333 | 1.3333 | 0.0 % |
| 4:3 576p / 480p / 800x600 | **on** | full frame | 1.3333 | 1.5767 | **−15.4 %** |
| 5:4 576p | off | 720x541 | 1.3308 | 1.3333 | −0.2 % |
| 5:4 576p | **on** | 720x576 | 1.2500 | 1.5767 | **−20.7 %** |

(The 5:4 rows assume the intended 5:4 display; the mode exists to pre-compensate
a 1280x1024-class monitor. The −0.2 % in the unzoomed 5:4 row is the off-by-one
described above, not a design decision.)

So zoom-in is 12.8 % too wide at 720p and 15–21 % too *narrow* in the 4:3 and
5:4 modes. Viper only ever mentions the 720p case because that is what he uses,
but the 4:3 modes are worse.

---

## 3. Is this the same thing gbc4mega65 does? — Yes

The Game Boy core's "Aspect Ratio" menu (`gbc4mega65/doc/video_modes.md`) offers
three borderless Handheld LCD sizes at a true 10:9 plus a TV-style 4:3, with
per-HDMI-mode rectangles such as 800x720 (exact 5x), 640x576 (exact 4x) and
514x463. That is structurally the identical problem: *crop the border away, then
place the result in a rectangle whose physical aspect is right and whose scale
factor is integer where possible.*

The mechanism is **already upstream in M2M `develop` (V2.1.0 staging)**:

```
627446d  Add core-configurable HDMI output fitting
ff1f248  Add selectable HDMI cropped-view sizes
```

`M2M/vhdl/av_pipeline/video_modes_pkg.vhd` in that tree adds:

- `hdmi_fit_mode_t` = `HDMI_FIT_MODE_LEGACY` / `_FULL_FRAME` / `_ASPECT`
- `hdmi_fit_t` = a physical aspect (`ASPECT_WIDTH`/`ASPECT_HEIGHT`, each 1..255),
  with presets `C_HDMI_FIT_4_3`, `C_HDMI_FIT_5_4`, `C_HDMI_FIT_10_9`, …
- `hdmi_scale_t` = a rational fraction, and `hdmi_view_sizes_t` = **four** of
  them, runtime-selectable
- `hdmi_view_cfg_t` = `UNCROPPED` fit + `CROPPED` fit + `CROPPED_SIZES`
- `make_hdmi_output_rect(video_mode, video_mode_id, fit, scale)` — a
  `pure function` that returns ascal's `H_MIN/H_MAX/V_MIN/V_MAX`, computed at
  elaboration time

The core-specific part is a single constant in `CORE/vhdl/globals.vhd` plus a
two-bit `qnice_hdmi_view_size_o` in `mega65.vhd`. Backward compatibility is
exact: `C_HDMI_VIEW_LEGACY` is a literal transcription of today's equations, and
when all four size slots are full-size the selector CDC and mux are omitted at
elaboration (`M2M/vhdl/av_pipeline/digital_pipeline.vhd:266` / `:274` and
`av_pipeline.vhd:514` / `:527` in the `develop` tree).

> **Trap worth knowing before you build on this.** That elaboration guard tests
> `G_HDMI_VIEW.CROPPED_SIZES /= C_HDMI_VIEW_SIZES_FULL`. If a core supplies
> distinct *fits* but leaves all four **sizes** at full, the guard is false, the
> `gen_legacy_view_size` fallback drives `hdmi_view_size <= (others => '0')`,
> and **all four slots silently collapse onto slot 0** — no assertion, no
> warning, no synthesis error, just a selector that does nothing. Any per-slot
> generalization (below) must move the guard onto the new field as well.

Three properties make it a good fit for the C64:

1. The `ASPECT` branch derives the frame's own pixel aspect from
   `video_mode.ASPECT`, so the CEA modes with non-square encoded pixels
   (720x480, 720x576) come out right without special-casing.
2. Everything is elaboration-time constant arithmetic — no multipliers, no
   dividers, no BRAM.
3. C64MEGA65's `M2M/` copy has diverged only modestly from `develop`
   (`crop.vhd` is identical; the local additions are the SDRAM ports in
   `framework.vhd` and a csync tweak in `analog_pipeline.vhd`), so this is a
   merge rather than a backport.

**Where it is not yet enough for the C64.** All four runtime slots share a
*single* `CROPPED` fit and differ only by a rational size fraction. That is
sufficient for the Game Boy, whose LCD is 10:9 no matter how big you draw it.
It is not sufficient here, because the interesting C64 presets use **different
crop heights**, and a different crop height means a different correct aspect.
Section 5.2 proposes the small generalization that fixes this.

---

## 4. The geometry

### 4.1 The candidate crops and their exact aspects

With `PAR = 180/191`, the aspect-correct display ratios come out as exact small
integers for the MiSTer-style crops:

| Crop | Aspect-correct AR | as a ratio | Square-pixel AR | as a ratio |
| --- | ---: | --- | ---: | --- |
| 382x270 (no crop) | 1.3333 | **4:3** | 1.4148 | 191:135 |
| 348x208 (today's zoom) | 1.5767 | 3915:2483 → 216:137 (+0.005 %) | 1.6731 | 87:52 |
| 382x240 | 1.5000 | **3:2** | 1.5917 | 191:120 |
| 382x216 | 1.6667 | **5:3** | 1.7685 | 191:108 |

`hdmi_fit_t` restricts both aspect components to 1..255
(`subtype hdmi_aspect_value_t is positive range 1 to 255`), so the exact
3915:2483 of today's crop is not representable; 216:137 is the closest pair and
is 0.005 % off, i.e. invisible. The 240- and 216-line crops, by contrast, land
on **3:2** and **5:3** exactly. That is a real argument for adopting them over
the existing 348x208 window.

### 4.2 The master table

Rectangles below were computed with M2M `develop`'s own
`make_hdmi_output_rect` algorithm (rounding included), so they are the literal
values the hardware would produce.

**16:9 720p (1280x720)** — source 382x270:

| Preset | Source crop | Fit | Output rect | V scale | H scale | Bars L/R |
| --- | --- | --- | --- | ---: | ---: | ---: |
| Full picture (zoom off, today) | 382x270 | 4:3 | 960x720 | 2.667 | 2.513 | 160/160 |
| Zoom, today | 348x208 | — | 1280x720 | 3.462 | 3.678 | 0/0 |
| Zoom, today's crop made aspect-correct | 348x208 | 216:137 | 1135x720 | 3.462 | 3.261 | 72/73 |
| **Zoom 240, aspect-correct** | 382x240 | 3:2 | **1080x720** | **3.000** | 2.827 | 100/100 |
| **Zoom 240, square pixels** | 382x240 | 191:120 | **1146x720** | **3.000** | **3.000** | 67/67 |
| Zoom 216, aspect-correct | 382x216 | 5:3 | 1200x720 | 3.333 | 3.141 | 40/40 |
| Zoom 216, square pixels (Viper's shot C) | 382x216 | 191:108 | 1273x720 | 3.333 | 3.332 | 3/4 |

**All other HDMI modes**, same presets:

| Fit | 576p 4:3 | 576p 5:4 | 720x480 | 640x480 | 800x600 | *(1080p)* |
| --- | --- | --- | --- | --- | --- | --- |
| Full 4:3 | 720x576 | 720x540 | 720x480 | 640x480 | 800x600 | *1440x1080* |
| Zoom 208, AR 216:137 | 720x487 | 720x457 | 720x406 | 640x406 | 800x507 | *1703x1080* |
| Zoom 240, AR 3:2 | 720x512 | 720x480 | 720x427 | 640x427 | 800x533 | *1620x1080* |
| Zoom 240, square 191:120 | 720x483 | 720x452 | 720x402 | 640x402 | 800x503 | *1719x1080* |
| Zoom 216, AR 5:3 | 720x461 | 720x432 | 720x384 | 640x384 | 800x480 | *1800x1080* |
| Zoom 216, square 191:108 | 720x434 | 720x407 | 720x362 | 640x362 | 800x452 | *1910x1080* |

The 5:4 column is what the V2.1.0 `ASPECT` fit produces — 720x540, symmetric —
so adopting the new machinery also removes the off-by-one from section 2.3 as a
side effect.

Note what the 4:3 columns say: **on a 4:3 output, an aspect-correct zoom makes
the picture smaller, not bigger.** The full picture already fills a 4:3 frame
exactly, so cropping vertically produces a wider-than-4:3 shape that has to be
letterboxed, and the on-screen width of the 320-pixel screen area is unchanged
either way (720 x 320/382 = 603 px in both cases). Zoom is only a meaningful
feature on a 16:9 output. This is worth acting on in the menu (section 5.4).

### 4.3 The trilemma

You can have any two of {**integer scale**, **correct aspect ratio**, **fill the
screen**}, never all three.

*Integer in both axes plus correct aspect* would require
`k_h / k_v = PAR = 180/191`, whose smallest integer solution is
`k_h = 180, k_v = 191`. Impossible.

*Filling the full 1280-pixel width with correct aspect and an integer vertical
scale `k`* requires a source width of `1280 x 191 / (180 k)`:

| k | required source width | required crop height |
| --- | ---: | ---: |
| 3 | 452.7 px | 240 |
| 4 | 339.6 px | 180 |

`k = 3` needs 453 source pixels but only 382 exist; `k = 4` needs a 180-line
crop, which is *less than the 200-line screen* and would cut into the picture.
The same holds at 1080p (`k = 5` → 407.5 px, `k = 6` → 180 lines). Impossible
too.

So the three honest positions are:

- **Correct aspect + fills the height**: 1080x720 (240-line crop) or 1200x720
  (216-line crop). Vertical scale is exactly 3.000 in the first case.
- **Integer in both axes + fills the height**: 1146x720 (240-line crop, exact
  3x3). Costs 6.1 % horizontal error. This is Viper's screenshot A.
- **Fills the whole screen**: what we do today, at 12.8 % horizontal error.

The **1080x720 / 240-line** option is the strongest single answer, because the
vertical axis is where scaling artifacts are visible (uneven line duplication is
what makes scanline and CRT filters look wrong) while a fractional 2.827x
horizontal upscale through a polyphase filter is essentially invisible. It is
also precisely MiSTer's `Vertical Crop: Yes` + `Scale: V-Integer` at 720p, which
means "same as MiSTer" becomes literally true — the thing Viper says he leaves
the MEGA65 for.

### 4.4 About 1080p

Viper's closing remark ("the scalings with 270 and 216 lines are integers of
1080p") is arithmetically correct: 1080/270 = 4 and 1080/216 = 5. But note that
this is only integer for **square pixels**. With the correct 180/191 aspect,
1080p gives 1800x1080 for the 216-line crop — vertical scale exactly 5, but
horizontal 4.712. The trilemma survives the resolution bump.

And 1080p is out of reach on this hardware regardless. The MEGA65 generates TMDS
directly from the FPGA: `M2M/vhdl/controllers/HDMI/video_out_clock.vhd:498-505`
runs a 742.5 MHz VCO producing a 371.25 MHz TMDS clock (DDR → 742.5 Mbit/s per
lane) and a 74.25 MHz pixel clock, feeding the 10:1 `OSERDESE2` in
`serialiser_10to1_selectio.vhd`. 1080p50/60 needs a 148.5 MHz pixel clock →
1485 Mbit/s per lane → a 742.5 MHz DDR serial clock, which the Artix-7
(`xc7a200tfbg484-2`, per `CORE/CORE-R3.xpr` and `CORE-R6.xpr`) HR-bank SelectIO
outputs cannot deliver. This is a hard I/O limit, independent of HyperRAM
bandwidth or of issue #141 (SDRAM on R6). **1080p should be treated as
permanently unavailable on current MEGA65 hardware**, and the ideas below are
built for 720p.

---

## 5. Ideas

Ranked by value per unit of effort and risk. A and B are alternatives — A is the
subset of B you would ship if you wanted the smallest possible change.

### Idea A — make zoom-in aspect-correct, and nothing else

**What the user sees.** "HDMI: Zoom-in" keeps working exactly as before, but the
picture is no longer stretched: at 720p it becomes 1135x720 with 72/73-pixel
black bars instead of 1280x720. In the 4:3 and 5:4 modes it becomes correctly
letterboxed instead of vertically stretched.

**How.** After merging M2M V2.1.0 (section 5.2), this is a single constant in
`CORE/vhdl/globals.vhd`:

```vhdl
constant HDMI_VIEW : hdmi_view_cfg_t :=
   make_hdmi_view_cfg(C_HDMI_FIT_LEGACY, make_hdmi_fit(216, 137));
```

Without the merge, the same result comes from editing the four
`when hdmi_crop_mode_i = '1'` branches in
`M2M/vhdl/av_pipeline/digital_pipeline.vhd:206-244` — about four lines, but
hand-rolled per HDMI mode, which is exactly the duplication V2.1.0 exists to
remove.

**Effort.** Hours. **Risk.** Near zero: elaboration-time constants into ascal's
`hmin/hmax/vmin/vmax`; ascal already black-fills outside the rectangle
(`ascal.vhd:2891-2893`). No LUT, BRAM, DSP or timing impact.

**What it does not solve.** No integer scaling — vertical stays at 3.462x, so
the scanline filters still show the uneven line pattern Viper dislikes. And it
silently changes the appearance of a setting existing users already like: Viper
himself says the stretched look "looks incredibly good with hi-res char mode
games". Shipping A alone without a way back to the old look would be a
regression for those users.

### Idea B — the recommended package: an "HDMI Picture" preset submenu

**What the user sees.** The single "HDMI: Zoom-in" checkbox becomes a nested
submenu, exactly like the "HDMI Filter" submenu that shipped with #223:

```
 HDMI: %s                       <- nested inside the HDMI submenu
 HDMI Picture

 Full picture
 Zoom: pixel-perfect 3x
 Zoom: aspect-correct
 Zoom: maximum
 Zoom: V5 classic

 Back
```

Behavior at 720p (see section 4.2 for the other HDMI modes):

| Menu item | Crop | Fit | Rect | V scale | H scale | Character |
| --- | --- | --- | --- | ---: | ---: | --- |
| Full picture | none (382x270) | 4:3 | 960x720 | 2.667 | 2.513 | today's default, unchanged |
| Zoom: pixel-perfect 3x | 382x240 | 191:120 | 1146x720 | **3.000** | **3.000** | every C64 pixel is an exact 3x3 block; 6.1 % wider than a PAL TV |
| Zoom: aspect-correct | 382x240 | 3:2 | 1080x720 | **3.000** | 2.827 | exact 3x vertical **and** true geometry — the MiSTer "V-Integer" look |
| Zoom: maximum | 382x216 | 5:3 | 1200x720 | 3.333 | 3.141 | biggest correct-geometry picture |
| Zoom: V5 classic | 348x208 | full frame | 1280x720 | 3.462 | 3.678 | bit-identical to V5/V6, for those who like it |

Set "Zoom: aspect-correct" as the `OPTM_G_STDSEL` default if you want to answer
Viper directly, or keep "Full picture" as the default and let people opt in.

**Why these five.** They span the trilemma without redundancy: one for people
who want the whole picture, one for pixel purists, one that is both vertically
pixel-perfect and geometrically right, one for maximum size, and one for
backward compatibility. The 240- and 216-line crops are MiSTer's own presets
(`CORE/C64_MiSTerMEGA65/c64.sv:1225,1228`), so "looks like my MiSTer" becomes
literally true.

**On naming.** Viper's own suggestions do not survive contact with the menu.
"(C)AR Zoom in" is jargon that means nothing to a user, and "Integer Zoom in" is
actively misleading — he concedes himself that it is not integer at 720p, which
is the only resolution the core has. Name presets by what the user gets. Also
note the 25-column width limit that already forced "Jiffy" instead of
"JiffyDOS" elsewhere in the menu.

**What has to change.**

*In M2M (targeting V2.1.0 / post-V6, consistent with the issue's own
"post V6" note):*

1. Merge `627446d` ("Add core-configurable HDMI output fitting") and `ff1f248`
   ("Add selectable HDMI cropped-view sizes") from `MiSTer2MEGA65/develop` into
   `C64MEGA65/M2M/`. The divergence is modest — `crop.vhd` is byte-identical,
   and the local C64 additions are the SDRAM ports in `framework.vhd` plus a
   csync tweak in `analog_pipeline.vhd`.
2. **Generalize `hdmi_view_cfg_t` with a per-slot fit.** Today the four runtime
   slots share one `CROPPED` fit and differ only by a rational size fraction.
   The C64 needs a different aspect per slot because each preset crops a
   different number of lines. Suggested shape, backward compatible by
   defaulting every slot to `CROPPED`:

   ```vhdl
   type hdmi_view_fits_t is array(0 to 3) of hdmi_fit_t;

   type hdmi_view_cfg_t is record
      UNCROPPED     : hdmi_fit_t;
      CROPPED       : hdmi_fit_t;
      CROPPED_FITS  : hdmi_view_fits_t;   -- NEW
      CROPPED_SIZES : hdmi_view_sizes_t;
   end record hdmi_view_cfg_t;
   ```

   `digital_pipeline.vhd` already builds one elaboration-time rectangle table
   per slot, so this is a change of *which* fit each table is built from, not a
   change of structure. Remember to widen the elaboration guard (see the trap in
   section 3) to `CROPPED_SIZES /= FULL **or** CROPPED_FITS /= all-CROPPED`,
   otherwise a C64 config that varies only the fits silently loses its
   selector.
3. **Give `crop.vhd` a runtime window selector.** Add
   `video_crop_sel_i : std_logic_vector(1 downto 0)` and a generic table of four
   `(X_MIN, X_MAX, Y_MIN, Y_MAX)` windows supplied by the core, defaulting to
   today's single window in all four slots. The module currently compares
   `x_count`/`y_count` against four constants; this becomes four constants
   selected by a 2-bit mux — a few dozen LUTs. This *also* removes the
   long-standing wart that a framework file carries C64 geometry.
4. Widen the two existing CDC vectors in `av_pipeline.vhd` by two bits each (the
   video-clock one for the crop selector, the HDMI-clock one for the view-size
   selector); the `qnice_hdmi_view_size_o` CDC already exists in `develop`.

*In `CORE/`:*

5. `globals.vhd`: the `HDMI_VIEW` constant and the crop-window table.
6. `mega65.vhd`: five new `C_MENU_*` constants, plus decoding them into
   `qnice_hdmi_view_size_o` and the new crop-select output — the same shape as
   `gbc4mega65/CORE/vhdl/mega65.vhd:623`.
7. `config.vhd`: the new submenu in `OPTM_ITEMS` / `OPTM_GROUPS`.

*Nothing in QNICE assembly* — these are plain OSM bits, unlike the filter
submenu which needed a dispatcher.

**Effort.** A few days, dominated by the M2M merge and by re-validating the
menu. **Risk.** Low but not zero, and concentrated in the menu plumbing rather
than the video path:

- Adding menu lines shifts every later `C_MENU_*` bit index. Drive the change
  from `M2M/rom/tests/menu_test.py` — note it holds **two** golden models,
  `V6_MENU` (`:88`) and `CUR_MENU` (`:411`), and both carry the
  `" HDMI: Zoom-in"` line (`:169` and `:492`). `menu_test.py verify` passes on
  HEAD today, so any post-change failure is attributable. Then regenerate
  `osm_const.asm` via `make_rom.sh` — it is gitignored and currently stale
  (`C64_OSM_HDMI_ZOOM .EQU 60` against `mega65.vhd`'s 80).
- `OPTM_SIZE` (`CORE/vhdl/config.vhd:394`, currently 190) grows, so a fresh
  config file must be generated. V6 already versions it as
  `c64mega65-V6.cfg` (issue #239), so this is a documented step rather than a
  compatibility break. The Shell's hard cap is **254**, not 255 — the range
  check at `M2M/rom/options.asm:301-305` is `1 <= size < 255`. OSM bits are not
  a concern either: the highest in use is 181 of 256.
- `MENU_HEAP_SIZE` (`CORE/m2m-rom/m2m-rom.asm:1414`, currently 3456) must be
  re-checked, and note that **both** budgets move. Budget 1 grows with the item
  count and label characters; budget 2 is
  `(VDRIVES_NUM + submenus + CRTROM_MAN_NUM + 1) x 27`, so a **new submenu costs
  another 27 words** — the comment at `m2m-rom.asm:1407-1409` is easy to
  misread as "budget 2 never moves". Today's peak is 3136 with about 320 words
  spare, and the proposal above spends roughly a third of that. It fits, but
  not with room to spare, and every word here is one less for the sorted file
  browser.
- Menu width: `OPTM_DX` is 25 (`CORE/vhdl/config.vhd:405`). The `%s` opener
  line renders as `" Picture: " + <selected label>`, and whether the label's
  leading space survives the substitution is not documented in
  `M2M/rom/options.asm`. Validate the longest label by rendering rather than by
  counting — this project already hit that wall once, when a 25-column summary
  forced "Jiffy" instead of "JiffyDOS".
- **Runtime geometry switching needs a guard.** Changing the crop re-triggers
  ascal's input auto-detect (`iauto => '1'`, `digital_pipeline.vhd:369`), and
  ascal samples `hmin`/`hmax`/`vmin`/`vmax` in the *output* clock domain with no
  internal CDC — `ascal.vhd:1882-1890` carries bare `-- <ASYNC> ?` comments and
  `:1892-1893` immediately computes `o_hsize <= o_hmax - o_hmin + 1`. A
  transient in which `hmin > hmax` is therefore representable. Register the
  selected rectangle on the falling edge of vblank in `digital_pipeline.vhd`,
  and document up to two frames of visual glitch when the user changes preset.

Resource impact is negligible: the current builds sit at 18–25 % LUT, 7–10 % FF,
48–56 % BRAM and ~10 % DSP across R3/R4/R5/R6.

### Idea C — hide the zoom presets on 4:3 and 5:4 outputs

Section 4.2 shows that on a 4:3 output an aspect-correct zoom can only make the
picture *smaller* — the 320-pixel screen area is 603 output pixels wide either
way. The zoom presets are therefore meaningful only on the 16:9 modes.

The V6 dependency feature looks like the obvious tool: `OPTM_DEP(mother, item)` /
`OPTM_DEP2` (`CORE/vhdl/config.vhd:662-669`) already hides the NTSC display
modes based on the machine mode. **Do not reach for it here without checking
first**, for two reasons:

1. `OPTM_DEP` supports mother items 0..3 only, while the HDMI display-mode group
   has six entries.
2. More seriously, the dependency mechanism is a **visibility filter only**.
   `M2M/rom/menu_struct.asm` computes a per-line visible bit; nothing in that
   path clears the *selected-state* array. On a checkbox that is harmless, but
   the zoom presets are a single-select radio group: if a user picks
   "Zoom: pixel-perfect 3x" at 720p and then switches to 576p, the line
   disappears while its bit stays set, so the geometry silently keeps applying
   with no visible menu item explaining it.

The safe form is to gate the preset **in VHDL** — AND the decode in
`mega65.vhd` against the 16:9 mode bits — and to remember that such a gate must
list the NTSC twins (`C_MENU_HDMI_4_3_5994`, `C_MENU_HDMI_5_4_5994`) as well as
the PAL ones, even though they are not wired yet. Using `OPTM_DEP` on a radio
member is only acceptable after proving that the Shell re-selects the `STDSEL`
member when the current selection becomes hidden.

Note also that the C64's own "greyed-out items" issue (#240) was closed as
`wontfix`, so hiding rather than greying is the established pattern here.

### Idea D — fix the 5:4 off-by-one

`digital_pipeline.vhd:240` is missing the `-1` that all seven sibling branches
have (section 2.3). The 5:4 rectangle is 541 lines with an 18/17 letterbox
instead of 540 with 18/18.

Two things follow. First, it is a one-character fix worth making on its own.
Second — and more important for M2M — the `HDMI_FIT_MODE_LEGACY` branch of
`make_hdmi_output_rect` in `MiSTer2MEGA65/develop` writes
`(video_mode.V_PIXELS + target_height) / 2 - 1`, i.e. it **silently corrects**
the off-by-one. The commit message for `627446d` claims the legacy profile is
"pixel-for-pixel compatible", and for the 5:4 mode it is not. That is almost
certainly the *desired* behavior, but the M2M VERSIONS.md entry should say so
rather than claim exact equivalence.

### Idea E — decide the NTSC story before, not after

NTSC is not wired yet (`CORE/vhdl/mega65.vhd:646` hardcodes `c64_ntsc <= '0'`,
issue #181), and `CORE/vhdl/main.vhd:1658` passes a hardcoded `ntsc => '0'` into
`video_sync`. When NTSC arrives, the geometry in this document changes wholesale:
`video_sync.vhd`'s NTSC branch produces a different active window, the 320x200
screen sits at a different offset, and the true NTSC pixel aspect is roughly
0.75 rather than 0.94.

Since MiSTer keeps `ARX/ARY = 400/300` for both systems, the cheap answer is to
keep one fit and accept the NTSC error; the correct answer is to make
`HDMI_VIEW` and the crop table selectable by machine mode. Whichever you pick,
picking it *while* designing the preset table is much cheaper than retrofitting
it, because the crop-window table introduced in idea B is exactly the place the
NTSC variant would live.

### Idea F — what not to do: 1080p

Section 4.4: the Artix-7 `xc7a200tfbg484-2` HR-bank SelectIO outputs cannot
serialize the 1485 Mbit/s per lane that 1080p50/60 needs. This is worth stating
publicly, because Viper's "it's a shame that 1080p support won't come anytime
soon" implies it is a scheduling decision. It is not — it is a hard I/O limit,
and it will not change on current MEGA65 hardware, independent of issue #141
(SDRAM on R6). Even if it could be done, section 4.4 shows the trilemma survives
the resolution bump.

---

## 6. Open questions for sy2002

1. **Which reading of "correct aspect ratio" is the default?** Idea B ships
   both, but only one can carry `OPTM_G_STDSEL`. Recommendation:
   "Zoom: aspect-correct" (1080x720), because it matches the unzoomed picture,
   matches MiSTer's `Original` aspect, and is the only preset that is both
   geometrically right and vertically pixel-perfect.
2. **Keep "Zoom: V5 classic"?** It preserves an existing look several users like
   and costs one menu line, but it is the only preset that is geometrically
   wrong. Dropping it makes the menu cleaner at the price of a visible
   regression for existing users.
3. **Five presets, or two axes?** The alternative to a flat preset list is two
   groups — "Border" (Full / Trim / Max) and "Geometry" (Aspect-correct /
   Pixel-perfect) — which expresses more combinations from fewer items but needs
   more than the two `hdmi_view_size` bits and reads less clearly in a menu.
4. **Does the per-slot-fit generalization belong in M2M V2.1.0 or V2.2.0?**
   It is small and backward compatible, but V2.1.0 is already staged with the
   current shape, and other cores would have to re-verify.
5. **Scope discipline against #250.** #160's title also says "scandoublers",
   which the #250 research covers for the analog path. Consider re-titling #160
   to the HDMI/ascal scope and letting #250 own the analog side, so the two do
   not overlap.
6. **Should the 5:4 fix ship in V6?** It is a one-character change with a
   visible (if tiny) effect on an existing mode, so it may be better as part of
   the V2.1.0 package than as a late V6 patch.
