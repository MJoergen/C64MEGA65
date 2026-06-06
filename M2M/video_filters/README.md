## MiSTer2MEGA65 Version 2.1.0

Starting with M2M V2.1.0, this folder ships a small **library of pre-converted
polyphase coefficient tables** that any M2M-based core can pull into ASCAL's
4-tap / 64-phase polyphase scaler. The framework's default boot behavior is
unchanged from V2.0.1: at system start it loads the classic
`LANCZOS2_12` (horizontal) + `SCAN_BR_110_80` (vertical) pair (see
`M2M/rom/filters.asm`). Cores that want more control can override this — see
below.

### Background

ASCAL's polyphase mode multiplies four source pixels by four signed 10-bit
coefficients per output pixel, picking the coefficient set from one of 64
"phases" based on the sub-pixel fractional position. The H pass and the V
pass each have their own independent 64×4 coefficient bank, so a "filter"
in this folder is really a 256-word table (64 phases × 4 taps) destined for
either the H bank, the V bank, or both. A "look" — sharp upscale, scanlines,
CRT — is the combination of one H file and one V file.

The MiSTer Filters_MiSTer project (https://github.com/MiSTer-devel/Filters_MiSTer)
is the upstream authoring tool: its `.txt` files express the same 64-phase
4-tap layout in plain text. `convert.py` in this folder rewrites a chosen
selection of those files into QNICE-assembler `.DW` blocks (the `.asm`
flavor, consumed at build time via `#include`) and into QNICE-monitor
M-load streams (the `.out` flavor, for live debugging over the JTAG
serial console).

### What ships in this folder

The shipped tables fall into three families. Sharp / smooth pixel scaling
without any CRT effect, scanline emulation that pairs a sharp H with a
darkened V, and authentic composite/S-Video CRT simulation. Each row below
is one filter file. To assemble a complete look you pick one H file and one
V file; the C64MEGA65 reference core uses the combinations shown further
down.

| File                          | Source (MiSTer)                               | Typical role | Per-row sum | Outer taps | Character |
|-------------------------------|-----------------------------------------------|--------------|-------------|------------|-----------|
| `SharpBilinear_080.asm`       | `Upscaling - SharpBilinear/SharpBilinear_080` | H or V       | 128         | zero       | Pixel-perfect for 48/64 phases, soft 16-phase blend zone in the middle. No ringing, no scanlines. |
| `GS_Sharpness_050.asm`        | `Upscaling - Recommended/GS_Sharpness_050`    | H or V       | 128         | small +    | Gaussian σ=0.5. Crisper than bilinear, no ringing. |
| `lanczos2_12.asm`             | `Upscaling - Lanczos Bicubic etc/lanczos2_12` | H or V       | 256 (10-bit) | -24       | Classic Lanczos-2 with mild ringing halo on hard edges. |
| `Scanlines_80.asm`            | `Scanlines - Standard/Scanlines_80`           | V            | 102..129    | tiny +     | ~80%-strength bilinear, mild row darkening. |
| `Scan_Br_105_80.asm`          | `Scanlines - Brighter/105pct/Scan_Br_105_80`  | V            | 107..135    | tiny +     | +5% brightness-compensated scanlines. |
| `Scan_Br_110_80.asm`          | `Scanlines - Brighter/110pct/Scan_Br_110_80`  | V            | 112..141    | tiny +     | +10% brightness-compensated. **M2M default V.** |
| `Scan_Br_115_80.asm`          | `Scanlines - Brighter/115pct/Scan_Br_115_80`  | V            | 118..147    | tiny +     | +15% brightness-compensated. |
| `Scan_Br_120_80.asm`          | `Scanlines - Brighter/120pct/Scan_Br_120_80`  | V            | 122..154    | tiny +     | +20% brightness-compensated; KiDra's original V choice (see V1 section). |
| `CRT_Sim_Composite_H.asm`     | `CRT - Simulation/CRT Simulation (Composite)_H` | H          | 126..129    | small +    | Composite-bandwidth horizontal blur; helps dither blend into colors. |
| `CRT_Sim_Composite_V.asm`     | `CRT - Simulation/CRT Simulation (Composite)_V` | V          | **51..128** | ~0         | Strong scanline darkening — pairs with the composite H file. |
| `CRT_Sim_SVideo_H.asm`        | `CRT - Simulation/CRT Simulation (S-Video)_H`   | H          | 127..130    | small +    | Mild S-Video-style horizontal softening. |
| `CRT_Sim_SVideo_V.asm`        | `CRT - Simulation/CRT Simulation (S-Video)_V`   | V          | **51..128** | ~0         | Scanline darkening — pairs with the S-Video H file. |

**Row sum = full brightness at 128.** Sums below 128 darken that phase, which
is how scanlines are realised in the V file. A V file whose sums dip well
below 128 will produce a visible scanline effect; one that stays flat at 128
will not.

The three text files `CRT_Simulation.txt`, `VGA_Squished_BGR_1987.txt`, and
`Commodore_1084_BGR_1987.txt` are kept as reference material for a future
release that adds gamma correction and shadow-mask support. They are not
currently `#include`d anywhere, and `convert.py` does not process them.

### `convert.py` — how to add or regenerate a filter

`convert.py` reads one MiSTer-format `.txt` and emits two artifacts:

- `.asm` — a single `.DW`-row block prefixed by a label derived from the
  filename (uppercased, with the `.txt` stripped). `#include` from
  QNICE-asm and `MOVE LABEL, R8` to use it.
- `.out` — a list of `<addr> <value>` pairs in QNICE-monitor M-load format.
  Useful for live-loading a single filter into ASCAL's polyphase RAM
  (`M2M$ASCAL_PPHASE`, device `0x0003`) from the monitor over JTAG.

The conversion is configured per file at the bottom of `convert.py`:

```
convert_file(MODE_OUT, '<source.txt>', '<dest.out>', <addr>, <bits>,
             <skip_header_lines>, <skip_lines>, <shift_right>, <shift_left>)
convert_file(MODE_ASM, '<source.txt>', '<dest.asm>', <addr>, <bits>,
             <skip_header_lines>, <skip_lines>, <shift_right>, <shift_left>)
```

Parameter meanings:

| Parameter           | Meaning |
|---------------------|---------|
| `addr`              | Only used by `MODE_OUT`. Absolute address inside the polyphase device window (`0x7000` = H slot start, `0x7100` = V slot start). `MODE_ASM` ignores it. |
| `bits`              | Width of the emitted hex value. Always `10` for ASCAL (`poly_dw` is `unsigned(9 downto 0)`; negative values are stored as 10-bit two's complement). |
| `skip_header_lines` | Number of leading lines in the `.txt` to copy out verbatim as `;` comments (`.asm`) or discard (`.out`) before parsing coefficients. The standard MiSTer 64-phase preamble is 7 lines; the Gaussian-sharpness family adds a 4-line kernel-formula block for 11 total. |
| `skip_lines`        | Take every Nth coefficient row. `1` for natively 64-phase files; `4` for the 256-phase Lanczos files (decimates 256 → 64). |
| `shift_right`       | Right-shift each coefficient before packing. Effectively zero across the shipped set. |
| `shift_left`        | Left-shift each coefficient before packing. Used to scale 7/8/9-bit source coefficients into the 10-bit `poly_dw` range. Must keep the result inside signed-10-bit `-512..+511`. |

**File-by-file recipe (already in `convert.py`):**

| File family                   | skip_header | skip_lines | shift_left | Notes |
|-------------------------------|------------:|-----------:|-----------:|-------|
| `lanczos2_12.txt`             | 6           | 4          | 0          | 256-phase native, decimated to 64. |
| `Scanlines_*` / `Scan_Br_*_80`| 7           | 1          | 1          | Peak ~129 × 2 = 258 → fits signed-10. |
| `SharpBilinear_*`             | 7           | 1          | 1          | Peak source coeff is 128. `shift_left=2` would scale to 512 and silently wrap to signed `-512` (10-bit max is `+511`); use `shift_left=1` for `+256` peak. |
| `GS_Sharpness_*`              | 11          | 1          | 2          | Extra 4-line Gaussian kernel block in the header. Peak ~101 × 4 = 404, fits. |
| `CRT Simulation (*)`          | 7           | 1          | 2          | Peak ~108 × 4 = 432, comfortably fits. |

**Footgun.** `convert.py` silently drops any `.txt` line that doesn't split
into exactly four comma-separated integers. So if `skip_header_lines` is
too low, leftover comment lines slip past as "non-conforming data" and the
output is short by a few phases — no error. Always sanity-check that a
freshly generated `.asm` has exactly **64 `.DW` lines** before checking
it in.

### How a core uses these files

The bridge between the assembled-in coefficient tables and ASCAL's
polyphase RAM is the framework helper `M2M$LOAD_POLYPHASE` in
`M2M/rom/tools.asm` (V2.1+):

```
; M2M$LOAD_POLYPHASE  R8 = horizontal table label, R9 = vertical table label
;                     Writes both 256-word tables into ASCAL's polyphase RAM
;                     via QNICE device M2M$ASCAL_PPHASE (= 0x0003), at
;                     offsets M2M$ASCAL_PP_HORIZ (0x0000) and
;                     M2M$ASCAL_PP_VERT (0x0100).
```

A core that's happy with the default behavior doesn't need to do
anything — `M2M/rom/filters.asm:LOAD_ASCAL_FLT` is a thin wrapper around
`M2M$LOAD_POLYPHASE` that selects `LANCZOS2_12` + `SCAN_BR_110_80` at
system start, identical to V2.0. The OSM bit driving
`qnice_ascal_polyphase_o` then toggles ASCAL between this polyphase set
and plain nearest-neighbour scaling, exactly as before.

A core that wants more — multiple selectable filter pairs, runtime
swapping, a custom default — implements it entirely inside its own
`CORE/m2m-rom/m2m-rom.asm` using the existing framework callbacks. No
framework changes required. The C64MEGA65 V6 reference implementation
does:

1. **Boot-time override.** The `PREP_START` callback (called from
   `M2M/rom/shell.asm` after the saved-config file has been read but
   before the core is un-reset) inspects the saved filter selection in
   `M2M$CFM_DATA` and re-invokes `M2M$LOAD_POLYPHASE` with the chosen
   `(H, V)` label pair. This overwrites the framework's earlier default
   load before any pixel reaches HDMI.
2. **Runtime swap on menu change.** The `OSM_SEL_POST` callback (called
   from `OPTM_CB_SEL` after the framework writes the new OSM bit) checks
   whether the changed menu group is the filter-selection group; if yes,
   it calls `M2M$LOAD_POLYPHASE` again with the newly-selected pair. The
   user sees the new filter from the next frame.

Because the OSM bit driving polyphase enable is held high in the core's
`mega65.vhd`, ASCAL is in polyphase mode the entire time and the only
thing that ever changes is the coefficient RAM. There is no NN fallback
to glitch through.

### Filter combinations used by C64MEGA65 V6

The reference combinations chosen for the C64MEGA65 V6 "HDMI: %s" submenu:

| Menu label               | Horizontal              | Vertical               | What you see |
|--------------------------|-------------------------|------------------------|--------------|
| Sharp                    | `SHARPBILINEAR_080`     | `SHARPBILINEAR_080`    | Crisp pixels, no scanlines, no halos. |
| Smooth                   | `GS_SHARPNESS_050`      | `GS_SHARPNESS_050`     | Gently anti-aliased pixels, no scanlines. |
| Lanczos                  | `LANCZOS2_12`           | `LANCZOS2_12`          | Sharp scaler with classic Lanczos ringing. |
| Scanlines                | `LANCZOS2_12`           | `SCAN_BR_110_80`       | M2M V2.0's "CRT emulation", preserved bit-identically. |
| CRT (S-Video)            | `CRT_SIM_SVIDEO_H`      | `CRT_SIM_SVIDEO_V`     | RGB-monitor / 1084 feel with mild scanlines. |
| CRT (Composite)          | `CRT_SIM_COMPOSITE_H`   | `CRT_SIM_COMPOSITE_V`  | 1980s living-room TV: bandwidth-limited horizontals, strong scanlines. |

The single-blob entries (Sharp / Smooth / Lanczos) load the same table
into both slots. ASCAL applies it once horizontally and once vertically.

## MiSTer2MEGA65 Version 1.0.0

M2M V1.0.0 up to M2M V2.0.1 only offered one option of video filters that are
loadable into ASCAL's polyphase filter: A CRT scanline emulation that in
parallel beautifies the scaling.

This very design choice was made when we did the very first version of the
C64MEGA65 core. The choice of optimal filters for our CRT emulation was done
by KiDra in March 2022.

### Compromise solution for C64MEGA65 V1

Version 1 of C64MEGA65 only supports horizontal and vertical filters for
performing the CRT emulation. There is no gamma correction and no shadow mask.

This leads to `Scan_Br_120_80.txt` being a bit too bright but the "pure"
version `Scanline_80.txt` being a bit too dark. We found `Scan_Br_110_80.txt`
being optimal for our purposes - at least as long we are not supporting
gamma correction and shadhow mask: The +10% in brightness compensates the
perceived -10% in brightness due to the emulated scan lines.

### KiDRa's optimal filter choice

#### Horizontal filter: lanczos2_12.txt

"It is the option where you set what upscaling method to use.
I use lanczos2_12.txt, because it adds a bit of blur and imperfection around
edges, without going too blurry (it does not replicate composite blending)."

https://github.com/MiSTer-devel/Filters_MiSTer/blob/master/Filters/Upscaling%20-%20Lanczos%20Bicubic%20etc/lanczos2_12.txt

#### Vertical filter: Scan_Br_120_80.txt

"This one adds the scanlines. Br_120 increases the brightness and thus
counterbalances the darkening of the image caused by the Shadow Mask filter.
80 is rather mild in scanlines, because I do not like these overblown dark
scanlines some folks use."

https://github.com/MiSTer-devel/Filters_MiSTer/blob/master/Filters/Scanlines%20-%20Brighter/120pct%20Brightness/Scan_Br_120_80.txt

#### Gamma Correction: CRT_Simulation.txt

"It corrects the gamma curve, because CRTs and LCDs have different gamma
curves and without correction dark parts of the screen would be too bright.
The `CRT Simulation` version creates nice, crisp colors."

https://github.com/MiSTer-devel/Filters_MiSTer/blob/master/Gamma/CRT%20Simulation.txt

#### Shadow Mask: VGA_Squished_BGR_1987.txt

"The shadow mask adds the aperture grill / slot look. VGA squished is one of
the most finely granular shadow masks and to me adds the delicate look of a
classic crt screen."

https://github.com/MiSTer-devel/ShadowMasks_MiSTer/blob/main/Shadow_Masks/Complex%20(Multichromatic)/CRT%20Styles/Subpixel%20BGR%20(Common)/VGA%20%5BSquished%5D%20%5BBGR%5D%20(1987).txt

##### Non recommended alternative: Commodore_1084_BGR_1987.txt

"Commodore 1084 - I would not use that setting, but here the file so you can
experiment with it ... pattern is too prominent ..."

https://github.com/MiSTer-devel/ShadowMasks_MiSTer/blob/main/Shadow_Masks/Complex%20(Multichromatic)/CRT%20Styles/Subpixel%20BGR%20(Common)/Commodore%201084%20%5BBGR%5D%20(1987).txt

