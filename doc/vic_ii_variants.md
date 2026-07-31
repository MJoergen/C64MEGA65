# VIC-II variants and machine timing modes

Background for issue [#120](https://github.com/MJoergen/C64MEGA65/issues/120)
(Advanced C64 Compatibility Settings) and issue
[#181](https://github.com/MJoergen/C64MEGA65/issues/181) (NTSC): what the
VIC-II implementation in our `CORE/C64_MiSTerMEGA65` submodule can emulate,
what the chip numbers mean, and how the two configuration axes relate to the
OSM.

## Two orthogonal configuration axes

`CORE/C64_MiSTerMEGA65/rtl/video_vicII_656x.vhd` exposes two independent
groups of configuration inputs:

1. **Machine/region timing** — four mutually exclusive mode inputs that
   select the line/frame geometry of a regional chip version: `mode6569`
   (PAL-B), `mode6567R8` (new NTSC), `mode6567old` (old NTSC), `mode6572`
   (PAL-N).
2. **Fabrication variant** — a 2-bit `variant` input that selects behavioral
   quirks of the silicon generation: `00` NMOS, `01` HMOS, `10` old HMOS.

Any combination of the two axes is technically possible in the RTL. The
wrapper `fpga64_sid_iec.vhd` currently reduces axis 1 to the single
`ntscMode` bit (`mode6569 <= not ntscMode`, `mode6567R8 <= ntscMode`, the
other two hardcoded to `'0'`) and hardcodes axis 2 to `variant => "10"`
(old HMOS). Both places carry `@TODO sy2002` tags pointing at issue #120;
that issue has since been closed with the decision to keep both hardcoded,
so the tags no longer describe pending work.
Note that even the submodule top `c64.sv` (the MiSTer OSD we do not use)
exposes only the PAL/NTSC toggle — old NTSC, PAL-N and the variant selection
are RTL-only capabilities.

## The chip family

The VIC-II was manufactured in two silicon generations. The original
chips — the 656x family — were built in NMOS and sat in the classic
"bread-bin" C64 (1982-1986). For the C64C with the short board (about 1986
onwards), Commodore re-implemented the chip in the newer HMOS-II process as
the 856x family. Architecturally identical, but with slightly different
electrical and timing behavior at the register interface.

| Chip     | Process | Region       | Cycles x lines | Machine                  | RTL mode input |
| -------- | ------- | ------------ | -------------- | ------------------------ | -------------- |
| 6569     | NMOS    | PAL-B        | 63 x 312       | European C64             | `mode6569`     |
| 6567R8   | NMOS    | NTSC (new)   | 65 x 263       | Common North-American C64| `mode6567R8`   |
| 6567R56A | NMOS    | NTSC (old)   | 64 x 262       | Earliest NTSC C64s (1982-83) | `mode6567old` |
| 6572     | NMOS    | PAL-N        | 65 x 312       | "Drean" C64 (Argentina)  | `mode6572`     |
| 8565     | HMOS-II | PAL-B        | 63 x 312       | European C64C            | `mode6569`     |
| 8562     | HMOS-II | NTSC (new)   | 65 x 263       | North-American C64C      | `mode6567R8`   |

CPU clocks per region (crystal divided down): PAL 0.985248 MHz, NTSC
1.022727 MHz, PAL-N 1.023440 MHz. Dividing the CPU clock by cycles-per-frame
gives the frame rates: PAL about 50.12 Hz, new NTSC about 59.83 Hz, old NTSC
about 61.0 Hz, PAL-N about 50.5 Hz.

## Machine/region timing modes

### `mode6567old` — old NTSC

The very first NTSC C64s shipped with the 6567R56A, which has one cycle less
per line and one line less per frame than the later 6567R8. Raster-effect
code — stable rasters, sprite multiplexers, split-screen tricks — counts CPU
cycles per scanline, so software written and tuned on those early machines
glitches or breaks on the later chip, and vice versa. The mode exists so
timing-sensitive early-NTSC software (and developers testing across VIC
revisions) can run authentically. VICE offers the same choice as "NTSC
(old)".

The old-NTSC machines used the same 14.318 MHz crystal as the later ones, so
in the core this mode only changes the VIC geometry — no separate clock is
needed. The catch is on the output side: 64 x 262 yields a frame rate near
61 Hz, which is off-spec for HDMI displays and would stress the flicker-free
scheme.

### `mode6572` — PAL-N (Drean)

Commodore's Argentine licensee Drean built C64s for the PAL-N TV standard
(Argentina, Paraguay, Uruguay). PAL-N is a hybrid: 50 Hz / 312-line frame
like PAL, but a color subcarrier close to NTSC's — so the 6572 runs 65
cycles per line like NTSC at a 50 Hz-class frame like PAL, and the CPU clock
(about 1.023 MHz) is near NTSC speed rather than PAL's 0.985 MHz.

Two use cases follow: locally produced software and the active Argentine
demoscene target exactly that geometry, and PAL-N machines are known for
running many NTSC-tuned games at nearly correct speed while still outputting
50 Hz. VICE supports the Drean as its own machine model for the same reason.

Unlike old NTSC, a faithful PAL-N machine needs its own master clock
(about 14.33 MHz dot clock). Driving `mode6572` from the PAL clock alone
would give a VICE-style approximation, not a cycle-exact Drean.

### Relation to the OSM "Model" setting (issue #181)

The planned PAL/NTSC switch in the OSM Model submenu drives `ntscMode`, so
it is literally selecting among these mode inputs — old NTSC and PAL-N would
simply be entries three and four of the same submenu, if we ever wanted
them. All the hard infrastructure NTSC needs is the same infrastructure the
exotic modes would need: a second core clock in `clk.vhd`, the matching
`clk32_speed` value for the CIA TOD, NTSC entries in the video pipeline, the
59.94 Hz HDMI display modes and the flicker-free NTSC twin that already sit
unwired in `config.vhd` (see `doc/wip-thoughts-on-ntsc.md` for the HDMI
side).

Design consequence: if the #181 wiring is designed as "machine mode selects
a bundle of VIC mode bits, core clock, `clk32_speed` and video pipeline
profile" rather than as a single PAL/NTSC boolean threaded through
everything, adding a third or fourth machine later stays cheap. Old NTSC
then comes almost for free (same clock, different geometry, but the 61 Hz
output problem remains), while PAL-N costs one more MMCM frequency.

## Fabrication variant: the `variant` input

The `variant` input changes exactly one thing: how color-register writes
(`$D020`-`$D02E`) latch within a cycle. This is the mechanism behind the
famous "grey dot bug" of HMOS VIC-IIs (see MiSTer issue
[#160](https://github.com/MiSTer-devel/C64_MiSTer/issues/160)). From
`video_vicII_656x.vhd` (the color-register write process):

* **NMOS (`"00"`)**: clean behavior — a write to a color register latches at
  the pixel-enable tick, nothing visible happens.
* **HMOS (`"01"`)**: a write landing at a specific sub-cycle phase
  momentarily forces the register to `$F` (light grey) before the real value
  latches. On a real C64C this shows as a single stray grey pixel at the
  raster position where the write occurred — visible "dirt" in any demo or
  game that changes border/background colors mid-frame.
* **Old HMOS (`"10"`)**: the register latches the real value during the
  entire PHI-high phase instead of only at the pixel tick — mid-line color
  changes take effect a pixel earlier than on NMOS, without the grey flash.

For the user the choice would essentially be: pixel-clean bread-bin look
(NMOS) versus authentic C64C artifacts (HMOS variants). Our port hardcodes
old HMOS because the large regression-testing session by paich64
([MiSTer issue #160
comment](https://github.com/MiSTer-devel/C64_MiSTer/issues/160#issuecomment-1873249673))
ran with that setting, so it is the tested baseline.

Wiring `variant` to the OSM would be nearly free — three menu bits reduced
into a 2-bit signal, no clock or video pipeline work at all — but issue
[#120](https://github.com/MJoergen/C64MEGA65/issues/120) was closed with the
decision not to offer the choice at all: the differences are too subtle to
be worth the extra menu surface, and deviating from the tested baseline
mostly buys confusion. There is therefore deliberately no "VIC-II model"
submenu in the OSM, and `mode6567old` and `mode6572` stay hardcoded to `'0'`
for the same reason.

## Orthogonal, but historically correlated

The two axes are independent inputs in the RTL, but real machines came as
coherent chip sets:

| Machine        | VIC-II            | CIA  | SID  |
| -------------- | ----------------- | ---- | ---- |
| Bread-bin C64  | 656x NMOS         | 6526 | 6581 |
| C64C           | 8565/8562 HMOS-II | 8521 | 8580 |

Some combinations never existed in silicon: old NTSC predates HMOS entirely,
and the Drean's 6572 was NMOS. The OSM's independent switches (CIA 8521,
SID 6581/8580, and eventually PAL/NTSC) let users mix freely, but
the compatibility personas people actually want are clusters — bread-bin
PAL, C64C PAL, NTSC machines — which is an argument for eventually offering
machine presets on top of the individual toggles, the way VICE names whole
machine models rather than individual chips.

## Where this stands in the code today

| Item | Location | State |
| ---- | -------- | ----- |
| PAL/NTSC (`ntscMode`) | `mega65.vhd` drives `c64_ntsc_i`, hardcoded to PAL | OSM Model submenu exists, not wired (#181) |
| Old NTSC (`mode6567old`) | `fpga64_sid_iec.vhd`, hardcoded `'0'` | Not in the OSM |
| PAL-N (`mode6572`) | `fpga64_sid_iec.vhd`, hardcoded `'0'` | Not in the OSM |
| VIC variant (`variant`) | `fpga64_sid_iec.vhd`, hardcoded `"10"` (old HMOS) | Deliberately not in the OSM (#120) |
