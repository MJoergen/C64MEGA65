# Moving the C64-only polyphase filters into a BRAM ROM

Working document for the refactoring that takes the core-specific HDMI filter
coefficient blobs out of the QNICE Shell ROM and puts them into a dedicated
block RAM, addressed by QNICE as a normal M2M device.

Status marker is kept at the bottom; update it after every milestone so a fresh
session can resume without re-deriving anything.

---

## 1. Why

The Shell ROM budget is `0x0000`-`0x6FFF` = 28,672 words (`0x7000`+ is QNICE
MMIO). After the string dedupe of 2026-08-02 the firmware sits at 27,645 words,
so roughly 1,000 words of headroom remain.

Text and coefficient tables dominate what is left to win: `.ASCII_W`/`.ASCII_P`
store one character per 16-bit word, and the five polyphase filter blobs are
5 x 256 = 1,280 words of pure data that the CPU never executes. Data that is
only ever *copied* to another device does not need to live in instruction ROM.

## 2. What moves, and what does not

`HDMI_FLT_TABLE` in `CORE/m2m-rom/m2m-rom.asm` references five blobs, but only
three of them are included by the core:

```
#include "../../M2M/video_filters/GS_Sharpness_050.asm"
#include "../../M2M/video_filters/CRT_Sim_Composite_H.asm"
#include "../../M2M/video_filters/CRT_Sim_SVideo_H.asm"
```

`LANCZOS2_12` and `SCAN_BR_110_80` arrive through `M2M/rom/filters.asm`, which
`M2M/rom/shell.asm` includes, and `M2M/rom/gencfg.asm` calls `LOAD_ASCAL_FLT`
which needs both of them at boot. Removing those two from the ROM would mean
editing the framework and would change behavior for every other M2M core
(AExp, GameBoy). Out of scope here.

| blob | source | after this change |
| --- | --- | --- |
| `GS_SHARPNESS_050` | core include | BRAM slot 0 |
| `CRT_SIM_COMPOSITE_H` | core include | BRAM slot 1 |
| `CRT_SIM_SVIDEO_H` | core include | BRAM slot 2 |
| `LANCZOS2_12` | `M2M/rom/filters.asm` | stays in Shell ROM |
| `SCAN_BR_110_80` | `M2M/rom/filters.asm` | stays in Shell ROM |

**Saving: 768 words gross**, minus the copy loop and the widened dispatcher
table: **684 words net**, taking the Shell ROM to 26,961 and the headroom to
1,711 words.

**The M2M framework is not modified by this change.**

## 3. The constraint that shapes the design

`M2M$LOAD_POLYPHASE` (in `M2M/rom/tools.asm`) is the framework routine that
writes a filter pair into the ascal polyphase RAM:

```
Input:  R8 = pointer to a 256-word horizontal coefficient table
        R9 = pointer to a 256-word vertical   coefficient table
```

It selects the ascal polyphase device in `M2M$RAMROM_DEV`, points
`M2M$RAMROM_4KWIN` at window 0 and then does two `memcpy` calls into
`M2M$RAMROM_DATA`. Both source pointers are therefore read as **ordinary QNICE
memory**, while the 4K window is already claimed by ascal.

Consequence: a blob living in another QNICE device cannot be handed to
`M2M$LOAD_POLYPHASE` directly - the window can only select one device at a
time.

The core therefore copies the blob **straight from the BRAM into the ascal
polyphase RAM, one word at a time**, flipping the device select between the two
windows (`_LHF_STREAM`). This runs once per filter selection and is not
performance critical, so there is nothing to gain from buffering a whole blob
in QNICE RAM first - and a 256-word buffer would cost real headroom:

> RAM here is as tight as ROM. The QNICE variables sit directly below the
> Shell heap, so any variable added pushes `HEAP` up by the same amount and
> comes straight out of the margin between the heap ceiling and
> `VAR$STACK_START`. That margin is 163 words. Spend more than that and heap
> plus declared stack no longer fit, and the framework self-check in
> `coreinfo.asm` reports its "Free QNICE memory" figure as a large number
> (an unsigned-rendered negative). Nothing enforces `STACK_SIZE` at runtime,
> so that diagnostic is the only thing that flags it.

Streaming adds no RAM variables at all, so the RAM layout is byte-for-byte what
it was before this change. `M2M$RAMROM_4KWIN` is a single global register
rather than one per device, so it is set once outside the loop and only the
device select alternates.

Looking at the five polyphase rows of `HDMI_FLT_TABLE`, the BRAM blobs only
ever appear in the **H** position, so the V half is either the same slot
(streamed a second time) or an ordinary Shell-ROM pointer (copied with the
framework's own `memcpy` into the V slot):

| menu row | H | V |
| --- | --- | --- |
| Smooth | `GS_SHARPNESS_050` (BRAM) | `GS_SHARPNESS_050` (BRAM, same blob) |
| Lanczos | `LANCZOS2_12` (ROM) | `LANCZOS2_12` (ROM) |
| Scanlines | `LANCZOS2_12` (ROM) | `SCAN_BR_110_80` (ROM) |
| CRT S-Video | `CRT_SIM_SVIDEO_H` (BRAM) | `SCAN_BR_110_80` (ROM) |
| CRT Composite | `CRT_SIM_COMPOSITE_H` (BRAM) | `SCAN_BR_110_80` (ROM) |

So the loader touches at most one BRAM slot per selection, and the Smooth row
simply streams that slot into both the H and the V half.

## 4. Design

### 4.1 New QNICE device

`CORE/vhdl/globals.vhd`:

```vhdl
constant C_DEV_C64_VFILTERS : std_logic_vector(15 downto 0) := x"010A";
```

(`0x0100`-`0x0109` are taken; `0x0109` is `C_DEV_C64_MOUNT2`.)

### 4.2 `CORE/vhdl/video_filters.vhd`

A read-only block RAM initialised from `CORE/vhdl/video_filters.rom`, wired
into the QNICE clock domain exactly like the other core devices in
`mega65.vhd`. 768 words of 16 bit, so a single 4K window covers all of it:

| slot | window offset | blob |
| --- | --- | --- |
| 0 | `0x000` | `GS_SHARPNESS_050` |
| 1 | `0x100` | `CRT_SIM_COMPOSITE_H` |
| 2 | `0x200` | `CRT_SIM_SVIDEO_H` |

Read-only: QNICE never writes it, so no write port is needed.

Precedent to copy for the plumbing: `C_DEV_C64_PHYS1581` = `0x0108` and
`CORE/vhdl/physical_1581_diag.vhd`, which is the most recently added
core-specific read-only QNICE device.

### 4.3 `CORE/m2m-rom/make_rom.sh` generates the `.rom`

The blob sources stay where they are, at framework level. `make_rom.sh` parses
the `.DW` rows out of the three `M2M/video_filters/*.asm` files and emits
`CORE/vhdl/video_filters.rom` in the same 16-binary-digits-per-line format that
`qasm2rom` produces and that `M2M/QNICE/vhdl/block_rom.vhd` reads.

Portability rules that already apply to the ROM-trim block in the same script:
no `strtonum()` and no `0x` literals in `awk` (both are gawk extensions; POSIX
awk silently evaluates `0x0100` as 0), no `/dev/stderr`, tolerate CRLF.

Validation, all fail-closed:

- exactly 256 words per blob, 768 total
- every value fits in 16 bit, and no value exceeds `0x03FF` (the blobs are
  4 signed 10-bit coefficients per line, 64 lines)
- the blob order matches the slot table above

### 4.4 `CORE/m2m-rom/m2m-rom.asm`

- drop the three `#include` lines
- `HDMI_FLT_TABLE` gains a fifth column: 0 means "H is a ROM pointer", 1..3
  means "H is BRAM slot n-1". The V column stays a ROM pointer throughout
- new `_LHF_STREAM` helper: R8 = slot, R9 = ascal offset. Sets window 0 once,
  then loops 256 times: select `C_DEV_C64_VFILTERS`, read one word, select
  `M2M$ASCAL_PPHASE`, write it. No RAM buffer
- `LOAD_HDMI_FILTER` checks the new column **before** the native-mode
  `0` sentinel, because on a BRAM row the H column is unused and holds `0`,
  which would otherwise look like "native mode, skip the polyphase write"
- for a BRAM row the V half is either the same slot (streamed again into
  `M2M$ASCAL_PP_VERT`) or a Shell-ROM pointer, copied there with `memcpy`
- no new RAM variables at all, so the RAM layout is unchanged

Register discipline: the `enter` / `leave` syscalls save and restore R8..R12
via the register-bank file (`MISC$ENTER` / `MISC$LEAVE`), so a framed helper
preserves them for its caller and nothing needs stashing across the call. Note
that `LOAD_HDMI_FILTER` keeps its table pointer in R0, so the ROM-V path uses
R6 for the device register.

## 5. Verification plan

The claim to prove is narrow and checkable: **the 256 words that reach the
ascal polyphase RAM for every one of the five polyphase menu rows are
bit-identical to what the pre-refactor build delivered.**

1. **Golden data.** Extract all five blobs from the pre-refactor
   `m2m-rom.out` by address, straight from the assembled image.
2. **Post-refactor data.** Extract `LANCZOS2_12` and `SCAN_BR_110_80` from the
   new `m2m-rom.out`, and the three moved blobs from `video_filters.rom`.
   Compare word by word against the golden data.
3. **Generator independence.** Re-derive the three blobs a second time by
   parsing the `M2M/video_filters/*.asm` sources with an implementation that
   shares no code with the `make_rom.sh` generator, and compare.
4. **Table integrity.** Confirm every `HDMI_FLT_TABLE` row still resolves to
   the same (mode, H blob, V blob) triple as before, including the two rows
   that keep ROM pointers and the three that switch to BRAM slots.
5. **No collateral damage.** All other strings and data byte-identical, the
   exported `m2m-rom.def` ABI addresses unchanged, dead-code set unchanged,
   `menu_test.py run` plus `verify`, `jiffy_test.py`, emulator boot output
   identical.
6. **Adversarial pass.** Independent agents try to *refute* the equivalence:
   off-by-one at blob boundaries, slot/index mismatch, endianness or
   nibble-order error in the `.rom` writer, window arithmetic, device-select
   leakage, `.BLOCK` overlapping another variable, ROM file length mismatch
   against `block_rom.vhd`'s line-count sizing.

Hardware remains the final gate: the VHDL side cannot be simulated end to end
here, so the first bitstream needs a visual check of the three affected menu
rows (Smooth, CRT S-Video, CRT Composite).

## 6. Files touched

```
CORE/vhdl/globals.vhd            new device id
CORE/vhdl/video_filters.vhd      new: BRAM ROM + QNICE read port
CORE/vhdl/video_filters.rom      new: generated, 768 lines
CORE/vhdl/mega65.vhd             device decode / read mux
CORE/m2m-rom/make_rom.sh         .rom generator + validation
CORE/m2m-rom/m2m-rom.asm         includes, HDMI_FLT_TABLE, LOAD_HDMI_FILTER, _LHF_STREAM
CORE/CORE-R*.xpr                 add video_filters.vhd to the file list
```

Not touched: anything under `M2M/`.

## 7. Relative ROM-file paths in VHDL

Worth recording, because three different depths coexist in this project and
they all work: Vivado resolves a relative `file_open` path against the
directory of the **VHDL source file that contains the string**, not against the
synthesis working directory.

| source file | literal | resolves to |
| --- | --- | --- |
| `M2M/vhdl/ram_init.vhd` | `../font/Anikki-16x16-m2m.rom` | `M2M/font/...` |
| `M2M/vhdl/QNICE/qnice.vhd` | `../../../CORE/m2m-rom/m2m-rom.rom` | `CORE/m2m-rom/...` |
| `CORE/vhdl/mega65.vhd` | `../../CORE/ram_init.hex` | `CORE/ram_init.hex` |

`video_filters.vhd` lives in `CORE/vhdl/` next to `mega65.vhd`, so it uses the
same `../../CORE/` prefix. Note that `file_open` here has no status parameter,
so a wrong path is a fatal elaboration error, not a silent zero-fill.

## 8. Progress

- [x] device id + `video_filters.vhd`
- [x] `make_rom.sh` generator + validation (output proven bit-identical to the
      blobs the assembler used to emit)
- [x] `m2m-rom.asm` loader + table
- [x] `.xpr` file lists (all four board revisions)
- [x] equivalence verification: all 8 menu rows deliver identical coefficients;
      regression suites, emulator boot and dead-code set unchanged
- [x] adversarial multi-agent audit (22 agents, 6 findings survived refutation)
- [x] ghdl unit test: all 768 words read back out of the preloaded BRAM are
      bit-identical to the coefficients the assembler used to emit
      (`CORE/vhdl/test/tb_video_filters/`)
- [x] hardware check on R3, 03-Aug-2026: all eight filter rows look correct,
      the polyphase ones and the native ascal ones alike

Result: Shell ROM 27,645 -> 26,961 words, **684 words saved**, headroom 1,711
words, and the RAM layout byte-for-byte unchanged.

The R3 synthesis log also settles the two things that could not be checked
without a build: `video_filters` elaborates as
`dualport_2clk_ram -> tdp_ram` with `ADDR_WIDTH=10, DATA_WIDTH=16,
ROM_PRELOAD=1, ROM_FILE_HEX=0, FALLING_B=1`, and `ROM_FILE` binds to
`../../CORE/vhdl/video_filters.rom` without a file error - `file_open` has no
status parameter, so a path that did not resolve would have aborted
elaboration. `write_bitstream completed successfully`, 0 errors, 0 critical
warnings, block RAM at 175 of 365 tiles.

## 9. Invariants to keep

Anyone touching this later should preserve these, because nothing enforces them
automatically:

- **No new QNICE RAM variables for the filter path.** See the RAM-margin note
  in section 3; the boot diagnostic in `coreinfo.asm` is the only warning.
- **The slot order is a three-way contract** between the generator in
  `make_rom.sh`, the layout comment in `video_filters.vhd` and the
  `C64_FLT_*` constants in `m2m-rom.asm`. Reordering one silently swaps
  filters.
- **`HSRC` is tested before the native-mode `0` sentinel** in
  `LOAD_HDMI_FILTER`. On a BRAM row the H column is unused and holds `0`;
  testing the sentinel first would skip the polyphase write and silently drop
  the filter.
- **The generator must fail closed.** Its diagnostics go to stdout, so they are
  captured to a temp file and printed on failure rather than being appended to
  the ROM image; `synth_pre.tcl` uses Tcl `exec`, which turns the non-zero exit
  into an aborted synthesis.
- `CORE/vhdl/video_filters.rom` is generated and is listed in `.gitignore`
  alongside the other generated ROM files.
