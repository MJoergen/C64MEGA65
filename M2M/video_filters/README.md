## MiSTer2MEGA65 Version 2.1.0

Starting with M2M V2.1.0, this folder ships a small **library of pre-converted
polyphase coefficient tables** that any M2M-based core can pull into ASCAL's
4-tap / 64-phase polyphase scaler. The framework's default boot behavior is
unchanged from V2.0.1: at system start it loads the classic
`LANCZOS2_12` (horizontal) + `SCAN_BR_110_80` (vertical) pair (see
`M2M/rom/filters.asm`). Cores that want more control can override this.

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

| File                          | Source (MiSTer)                               | Typical role | Raw row sum (MiSTer) | Outer taps | Character |
|-------------------------------|-----------------------------------------------|--------------|---------------------|------------|-----------|
| `SharpBilinear_080.asm`       | `Upscaling - SharpBilinear/SharpBilinear_080` | H or V       | 128         | zero       | Pixel-perfect for 48/64 phases, soft 16-phase blend zone in the middle. No ringing, no scanlines. |
| `GS_Sharpness_050.asm`        | `Upscaling - Recommended/GS_Sharpness_050`    | H or V       | 128         | small +    | Gaussian σ=0.5. Crisper than bilinear, no ringing. |
| `lanczos2_12.asm`             | `Upscaling - Lanczos Bicubic etc/lanczos2_12` | H or V       | 256 (10-bit) | -24       | Classic Lanczos-2 with mild ringing halo on hard edges. |
| `Scanlines_80.asm`            | `Scanlines - Standard/Scanlines_80`           | V            | 102..129    | tiny +     | ~80%-strength bilinear, mild row darkening. |
| `Scan_Br_105_80.asm`          | `Scanlines - Brighter/105pct/Scan_Br_105_80`  | V            | 107..135    | tiny +     | +5% brightness-compensated scanlines. |
| `Scan_Br_110_80.asm`          | `Scanlines - Brighter/110pct/Scan_Br_110_80`  | V            | 112..141    | tiny +     | +10% brightness-compensated. **M2M default V.** |
| `Scan_Br_115_80.asm`          | `Scanlines - Brighter/115pct/Scan_Br_115_80`  | V            | 118..147    | tiny +     | +15% brightness-compensated. |
| `Scan_Br_120_80.asm`          | `Scanlines - Brighter/120pct/Scan_Br_120_80`  | V            | 122..154    | tiny +     | +20% brightness-compensated; KiDra's original V choice (see V1 section). |
| `CRT_Sim_Composite_H.asm`     | `CRT - Simulation/CRT Simulation (Composite)_H` | H          | 126..129    | small +    | Composite-bandwidth horizontal blur; helps dither blend into colors. |
| `CRT_Sim_Composite_V.asm`     | `CRT - Simulation/CRT Simulation (Composite)_V` | V          | **51..128** | ~0         | Strong scanline darkening — pairs with the composite H file *in the original MiSTer pipeline (with gamma + shadow mask)*; **not paired with anything in C64MEGA65 V6** — see the V6 reference table below. |
| `CRT_Sim_SVideo_H.asm`        | `CRT - Simulation/CRT Simulation (S-Video)_H`   | H          | 127..130    | small +    | Mild S-Video-style horizontal softening. |
| `CRT_Sim_SVideo_V.asm`        | `CRT - Simulation/CRT Simulation (S-Video)_V`   | V          | **51..128** | ~0         | Scanline darkening — pairs with the S-Video H file *in the original MiSTer pipeline*; **not paired with anything in C64MEGA65 V6** — see the V6 reference table below. |

The **Per-row sum** column above is the raw MiSTer-side row sum, *before*
any `shift_left` is applied. MiSTer's 64-phase 8-bit files treat raw row
sum `128` as unity (full brightness). MiSTer's 256-phase 10-bit Lanczos
files (`lanczos2_12`, …) treat raw row sum `256` as unity. The post-shift
value is what ASCAL actually sees — see "Polyphase unity" below for the
math.

The three text files `CRT_Simulation.txt`, `VGA_Squished_BGR_1987.txt`, and
`Commodore_1084_BGR_1987.txt` are kept as reference material for a future
release that adds gamma correction and shadow-mask support. They are not
currently `#include`d anywhere, and `convert.py` does not process them.

### Polyphase unity — the critical math

**ASCAL's polyphase unity is 256, not 128.** Every other piece of this
folder's machinery — `shift_left` values, perceptual character notes,
brightness checks — derives from this single fact.

**Proof.** ASCAL's built-in nearest-neighbour mode is implemented by the
polyphase datapath running with synthetic NN coefficients generated by
`poly_nn()` in `ascal.vhd:1070`:

```vhdl
poly_nn(0).t1 := to_signed(256, 10);   -- the single non-zero tap
```

NN must preserve brightness (output = input), so the single non-zero tap
must equal unity. Therefore in ASCAL's signed-10-bit coefficient space
**`256` is `1.0`**. The full datapath confirms this: `poly_cvt` does +7
left-shift, `poly_final` does -8 right-shift, `bound` does -7 right-shift
— net normalisation by 256.

**Per-row-sum brightness:** at any sub-pixel phase, the four taps are
multiplied by four adjacent source pixels and summed. If the four taps
sum to `S`, the output is approximately `S/256 × average_input`. So:

- **`S = 256` → output brightness = input brightness** (unity gain).
- **`S < 256` → that phase darkens the output** (sub-unity, used for
  scanlines: a V file whose mid-phase row sums dip to 102 produces a
  ~40 % brightness gap between source lines, which IS the visible
  scanline).
- **`S > 256` → that phase brightens the output** (super-unity, used for
  brightness-compensated scanlines: `Scan_Br_110_80` peaks at S=282, the
  +10 % compensation in the filename).

**`shift_left` is the unity-conversion knob.** MiSTer's 64-phase 8-bit
files use unity 128; multiplying by 2 (`shift_left=1`) lands them at
ASCAL unity 256. MiSTer's 256-phase 10-bit files (Lanczos) already use
unity 256, so they need `shift_left=0`. **Using `shift_left=2` on a
unity-128 file doubles brightness** (effective unity 512), which is
exactly the bug that produced the over-bright Smooth / CRT pictures in
the V6 beta build and was fixed by lowering the five affected files back
to `shift_left=1`.

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
| `SharpBilinear_*`             | 7           | 1          | 1          | All 64-phase 8-bit MiSTer files use unity = 128. ASCAL's polyphase unity is **256** (proven by `poly_nn` setting one tap to `to_signed(256, 10)` in `ascal.vhd:1070`), so a `shift_left=1` lands each phase exactly at ASCAL unity. |
| `GS_Sharpness_*`              | 11          | 1          | 1          | Same unity convention as SharpBilinear. Extra 4-line Gaussian kernel block in the header. `shift_left=2` would double brightness (effective sum 512 vs unity 256) — visible as washed-out picture. |
| `CRT Simulation (*)`          | 7           | 1          | 1          | Same unity convention. The `_V` files dip to row sum ~51 (post-shift ~102, = 40 % of unity) at mid-phases — that intentional sub-unity dip is the CRT vertical scanline gap. |

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
anything: `M2M/rom/filters.asm:LOAD_ASCAL_FLT` is a thin wrapper around
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

The core sets `ASCAL_USAGE = 1` (`AUSE_CUSTOM`) in `config.vhd` so
`ASCAL_INIT` clears `M2M$CSR` bit 11, leaving `M2M$ASCAL_MODE` (`0xFFE3`)
writable from QNICE. `LOAD_HDMI_FILTER` then writes the mode register
**per menu selection**: `M2M$ASCAL_NEAREST` for "No Filter",
`M2M$ASCAL_SBILINEAR` for "Sharp Bilinear", `M2M$ASCAL_BICUBIC` for
"Bicubic", and `M2M$ASCAL_POLYPHASE` for the five polyphase-based options
(Smooth, Lanczos, Scanlines, CRT (S-Video), CRT (Composite)).

### Filter combinations used by C64MEGA65 V6

The reference combinations chosen for the C64MEGA65 V6 "HDMI: %s" submenu:

| Menu label               | ASCAL mode        | Horizontal              | Vertical               | What you see |
|--------------------------|-------------------|-------------------------|------------------------|--------------|
| No Filter                | native NEAREST    | *— (no coeffs loaded)*  | *— (no coeffs loaded)* | Pure nearest-neighbour. Power-user opt-in for those who want raw, untouched pixels at the cost of uneven character widths at non-integer scale ratios. Not the default. |
| Sharp Bilinear           | native SBILINEAR  | *— (no coeffs loaded)*  | *— (no coeffs loaded)* | ASCAL's built-in cubic-warped Sharp Bilinear (`ascal.vhd:783-821`). Smoother than the polyphase `SHARPBILINEAR_080` emulation: C¹-continuous curve `g(t) = 4·t³` (t<½) / `1 − 4·(1−t)³` (t≥½), no slope discontinuities, no kinks. The cleanest "modern flatscreen" look. |
| Bicubic                  | native BICUBIC    | *— (no coeffs loaded)*  | *— (no coeffs loaded)* | ASCAL's built-in bicubic kernel. Mild edge bite from small negative outer-tap lobes; perceptually sits between Sharp Bilinear (no ringing at all) and Lanczos (visible halo). Good middle ground for users who want a hint of edge enhancement without the Lanczos look. |
| Smooth                   | POLYPHASE         | `GS_SHARPNESS_050`      | `GS_SHARPNESS_050`     | Gently anti-aliased pixels, no scanlines. |
| Lanczos                  | POLYPHASE         | `LANCZOS2_12`           | `LANCZOS2_12`          | Sharp scaler with classic Lanczos ringing. |
| Scanlines                | POLYPHASE         | `LANCZOS2_12`           | `SCAN_BR_110_80`       | V5's "CRT emulation", preserved bit-identically. |
| CRT (S-Video)            | POLYPHASE         | `CRT_SIM_SVIDEO_H`      | `SCAN_BR_110_80`       | RGB-monitor / 1084 feel: mild horizontal softening + gentle scanlines, near-unity mean brightness. |
| CRT (Composite)          | POLYPHASE         | `CRT_SIM_COMPOSITE_H`   | `SCAN_BR_110_80`       | 1980s living-room TV: heavy composite-style horizontal blur + gentle scanlines, near-unity mean brightness. |

The single-blob entries (Smooth / Lanczos) load the same table into both
slots; ASCAL applies it once horizontally and once vertically.

Note: the `SharpBilinear_080.txt` / `.asm` files remain in this folder as
a polyphase emulation of the same idea — useful for cores that don't want
to use ASCAL's native Sharp Bilinear, or for A/B comparison. C64MEGA65 V6
does not `#include` it, so it costs zero ROM here.

**On the CRT V file swap.** The upstream MiSTer `CRT_Sim_*_V` files are
designed to be **one of three stages**: polyphase filter + brightness-lifting
gamma LUT (`Gamma/CRT Simulation.txt`) + shadow mask overlay. M2M V2.1
supports only the polyphase stage. Used standalone, the `CRT_Sim_*_V` file
(coefficient data is identical between Composite and S-Video — only the
label name differs; the per-format character lives entirely in the H file)
has a deep ~40 %-of-unity mid-phase basin spanning 16 of 64 phases
(post-shift row sums 102…116 across phases 24–39, with the 39.8 % floor at
the two basin minima), which on a uniformly bright C64 BASIC screen reads
as a heavy dark horizontal band rather than subtle scanlines. C64MEGA65
V6 therefore pairs the `CRT_Sim_*_H` files with `SCAN_BR_110_80` as the V
file (same V as the "Scanlines" entry), keeping the Composite-vs-S-Video
distinction in the horizontal pass while restoring near-unity mean
brightness. The `CRT_Sim_*_V` files stay in this folder for cores that do
have gamma + shadow mask support, but are not `#include`d in the C64
build. The longer-term direction is to wire ASCAL's adaptive-polyphase
modes (101/110) and pair them with the `Scanlines - Adaptive/SLA_*` files,
which apply scanline darkening per-pixel as a function of source
luminance — bright C64 content gets mild scanlines, dark content gets
full strength.

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

