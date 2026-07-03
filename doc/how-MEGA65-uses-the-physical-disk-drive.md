# How the MEGA65 Uses the Physical Disk Drive

Research date: 2026-06-14

This note is a research document for a future C64MEGA65 refactor. It describes
how the MEGA65 core uses the built-in physical floppy drive, how the signals and
software-visible interfaces flow, what code looks reusable, and where a later
C64MEGA65/MiSTer 1581 integration would most likely attach.

This is not an implementation plan for the refactor yet. It deliberately keeps
the future task in view, because the important outcome of this research is not
only "how does MEGA65 do it?", but also "where would we cut the interface if we
want the C64 MiSTer 1581 to use that same physical media?"

## Source Snapshot

Primary local sources inspected:

| Source | Snapshot |
| --- | --- |
| C64MEGA65 repo | current working tree, with existing unrelated local edits left untouched |
| MEGA65 core clone | [`MEGA65/mega65-core`](https://github.com/MEGA65/mega65-core), cloned to `/private/tmp/c64mega65-drive-research/mega65-core` |
| MEGA65 branch | `development` |
| MEGA65 commit | `4006aaa0b6c4734aefae4ace80fee60cba09ad77` |
| Paul Gardner-Stephen blog archive | Blogger Atom feed, 427 posts searched for disk/FDC terms |

Important web sources from Paul Gardner-Stephen's blog:

- [Hooking up the 3.5" internal floppy drive](https://c65gs.blogspot.com/2018/01/hooking-up-35-internal-floppy-drive.html)
- [Bringing the internal 3.5" floppy drive to life - part 2](https://c65gs.blogspot.com/2018/01/bringing-internal-35-floppy-drive-to_15.html)
- [Write and format support for the internal floppy drive](https://c65gs.blogspot.com/2021/08/write-and-format-support-for-internal.html)
- [Adding transparent support for HD floppies](https://c65gs.blogspot.com/2021/09/adding-transparent-support-for-hd.html)
- [Creating a simple internal drive fast-loader for the MEGA65](https://c65gs.blogspot.com/2021/11/creating-simple-internal-drive-fast.html)
- [More work on HD floppies, RLL encoding, disk density auto-detection and other fun](https://c65gs.blogspot.com/2022/01/more-work-on-hd-floppies-rll-encoding.html)
- [Tracking down 1581 lock-up on R3 boards](https://c65gs.blogspot.com/2024/08/tracking-down-1581-lock-up-on-r3-boards.html)

The key local MEGA65 files are:

- `src/vhdl/mega65r*.vhdl`: board top-level floppy pins.
- `src/vhdl/machine.vhdl`: board-level glue, raw read/write data conditioning.
- `src/vhdl/iomapper.vhdl`: F011 and `$D680-$D6FF` decode, `sdcardio` instance.
- `src/vhdl/sdcardio.vhdl`: active physical floppy, F011, SD-image, and
  virtual-F011 implementation.
- `src/vhdl/mfm_decoder.vhdl`, `mfm_*`, `rll27_*`, `raw_bits_to_gaps.vhdl`,
  `crc1581.vhdl`: reusable physical-format helper blocks.
- `iomap.txt` and `docs/sdcard-and-floppy-drive.md`: register and architecture
  documentation.

The key local C64MEGA65 files are:

- `M2M/vhdl/top_mega65-r*.vhd`: physical floppy pins exist but are tied inactive.
- `M2M/vhdl/vdrives.vhd`: current MiSTer-style virtual drive sector service.
- `CORE/vhdl/main.vhd`: current C64 drive integration.
- `CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv`: D64/D81 engine selection.
- `CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1581_drv.sv`: emulated 1581 drive.
- `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v`: current virtual WD1772 media
  layer that requests logical sectors through the MiSTer `sd_*` interface.

## Executive Conclusions

1. The MEGA65 physical drive is a PC-style 3.5-inch floppy drive mechanism on a
   standard 34-pin interface, not a native Commodore 1581 mechanism and not an
   IEC serial device.

2. The FPGA implements the floppy controller. The physical connector exposes
   raw motor/select/step/write/read/status lines. MEGA65 software normally does
   not manipulate flux directly; it sees a C65-compatible F011/F018-style sector
   controller at `$D080-$D08A`, plus MEGA65 extension registers at
   `$D680-$D6AF`.

3. The active physical-drive implementation is `src/vhdl/sdcardio.vhdl`.
   Despite the name, this file is much more than SD-card I/O: it contains
   F011 register behavior, disk-image selection, real physical floppy control,
   MFM/RLL/raw encoders and decoders, sector-buffer RAM, status flags, timeouts,
   formatting, and virtual-F011 hypervisor trap support.

4. `src/vhdl/internal1581.vhdl` is not the active production physical-drive path.
   It looks tempting by name, but in this checkout it is test/scaffold-like: it
   has an address decode for a WDC FDC area, but reads there return all ones.

5. C64MEGA65 currently uses the MiSTer C64 drive stack. D81 images are mounted
   through QNICE and `M2M/vhdl/vdrives.vhd`, then served to MiSTer `iec_drive`
   through `sd_lba`, `sd_rd`, `sd_wr`, `sd_ack`, and `sd_buff_*`.

6. The clean future integration point is probably not "drop MEGA65 `sdcardio`
   into C64MEGA65." The realistic path is to keep the MiSTer IEC-visible 1581
   and create a narrow physical 512-byte sector service under, or next to,
   the current MiSTer `sd_*` backend.

7. The reusable MEGA65 work is most likely the low-level physical-sector
   machinery: drive pins, MFM/RLL/raw gap/byte codecs, CRC, real-sector
   read/write state machines, and perhaps the F011 sector-buffer logic after
   it is extracted behind a clean request/status interface.

8. The adversarial warning is strong: F011 is not WD1772. The MEGA65 physical
   controller is C65/F011-facing; the MiSTer 1581 has a WD1772-facing drive CPU.
   A bridge must decide whether to preserve WD1772 semantics above the backend
   or replace a much larger part of the 1581 emulation.

## Extraction Verdict

The MEGA65 does have a real HDL floppy controller. The F011/F018 registers are
the software facade, not a sign that software bit-bangs the floppy. Behind that
facade, `sdcardio.vhdl` and its helper blocks do the hard physical-controller
work: motor/select/side/step control, raw read-data pulse decoding, MFM/RLL byte
recovery, sector-header detection, CRC, sector buffering, write serialization,
write-gate timing, and format/write-track sequencing.

For C64MEGA65, the right conclusion is selective extraction, not a rewrite from
scratch and not a wholesale import.

Worth extracting or directly adapting:

- `mfm_decoder.vhdl` and its gap/bit/byte helper chain.
- `crc1581.vhdl`.
- `mfm_bits_to_gaps.vhdl` for MFM write serialization.
- `rll27_*` and `raw_bits_to_gaps.vhdl` only if we later want MEGA65 extended
  formats or raw diagnostics.
- The real-drive read-sector FSM structure: wait for a fresh target sector,
  capture 512 bytes, track CRC/RNF/LOST status, and timeout on index rotations.
- The real-drive write-sector structure: wait for the target sector, open
  write gate, write gap/sync/data/CRC/trailing gap, then close write gate.
- The proven physical-pin handling lessons: active-low select/motor/write gate,
  index and track0 polarity, disk-change latching, side caveats, and one-owner
  write-data policy.

Not worth extracting as an architectural block:

- `sdcardio.vhdl` as a complete entity.
- The `$D080-$D08A` F011 programming interface as our primary interface.
- The `$D680-$D6AF` MEGA65 extension register page.
- MEGA65 SD-card disk-image mode.
- HYPPO virtual-F011 trap machinery.
- MEGA65 firmware policy for mounting `MEGA65.D81` or choosing real drive vs
  image.
- `internal1581.vhdl`.

The reason is that we are not trying to build a C65 internal drive. We want the
C64-facing MiSTer 1581 to keep its 1581 DOS, IEC behavior, and WD1772-visible
semantics, while replacing or augmenting the media backend beneath it. The
MEGA65 physical controller is valuable because the magnetic media under a 1581
disk is still MFM 512-byte sector media on a 3.5-inch mechanism. Its C65/F011
front-end is the wrong interface for us, but its physical-media machinery is
highly relevant.

The target shape should therefore be:

```text
MiSTer c1581_drv / 1581 DOS / WD1772-facing behavior
        |
        v
fdc1772 media request: LBA or track/side/sector
        |
        v
C64MEGA65 physical_1581_sector_service
        |
        v
selectively extracted MEGA65 MFM/CRC/read/write/step logic
        |
        v
MEGA65 physical floppy pins
```

So the current recommendation is: do not redo the low-level magnetic decoding
and writing unless extraction proves impossible. Also do not make `sdcardio` the
dependency boundary. Use it as the reference implementation and carve out a
C64MEGA65-native physical sector service.

## What Drive Hardware Is In The MEGA65?

The MEGA65 documentation says the machine includes a PC-standard 34-pin floppy
drive interface for DD 720 KB, HD 1.44 MB, and ED 2.88 MB 3.5-inch drives. The
legacy C65 ROMs understand the C65 F011/F018 compatibility layer, and that layer
can choose at run time between the real drive and D81 disk images on the SD
card.

Paul's 2018 bring-up post confirms the same from the hardware side: the goal was
to use standard PC floppy drives because they were still available, and because
the FPGA can implement the required controller behavior. The 34-pin cable can
address two drives and exposes the usual PC floppy signals.

The important physical signals are:

| MEGA65 signal | Direction | PC-style meaning | Polarity / notes |
| --- | --- | --- | --- |
| `f_density` | output | Density select | active level depends on drive conventions; MEGA65 writes it directly |
| `f_motora` | output | Motor enable, drive A | active low in normal control path |
| `f_motorb` | output | Motor enable, drive B | active low |
| `f_selecta` | output | Drive select A | active low |
| `f_selectb` | output | Drive select B | active low |
| `f_stepdir` | output | Step direction | MEGA65 drives `1` for step out, `0` for step in |
| `f_step` | output | Step pulse | active low pulse |
| `f_wdata` | output | Write data pulse stream | active-low pulse source, combined from two writers in `machine.vhdl` |
| `f_wgate` | output | Write gate / write enable | active low |
| `f_side1` | output | Head/side select | MEGA65 drives inverted from F011 side bit |
| `f_index` | input | Index hole sense | treated as active low |
| `f_track0` | input | Track 0 sense | treated as active low |
| `f_writeprotect` | input | Write protect sense | mapped inverted into F011 status |
| `f_rdata` | input | Raw read-data pulse stream | conditioned in `machine.vhdl` |
| `f_diskchanged` | input | Disk change sense | treated as active low/latching |

The same signal set appears in the MEGA65 board tops (`mega65r3.vhdl` through
`mega65r6.vhdl`) and in C64MEGA65's M2M top-levels. In C64MEGA65, however, the
floppy outputs are currently tied inactive:

```text
M2M/vhdl/top_mega65-r*.vhd
  f_density_o <= '1'
  f_motora_o  <= '1'
  f_selecta_o <= '1'
  f_side1_o   <= '1'
  f_stepdir_o <= '1'
  f_wdata_o   <= '1'
  f_wgate_o   <= '1'
```

That is important for the future task: the physical connector is already a
top-level board feature in M2M, but no C64MEGA65 framework/core contract
currently carries those pins into any useful controller.

## Active MEGA65 Physical Signal Flow

The production physical-drive path in the MEGA65 core is:

```text
src/vhdl/mega65r*.vhdl
  Board-level physical floppy pins
        |
        v
src/vhdl/machine.vhdl
  Conditions f_rdata
  Combines f_wdata writers
        |
        v
src/vhdl/iomapper.vhdl
  Decodes F011 and SD/FDC extension registers
  Instantiates sdcardio
        |
        v
src/vhdl/sdcardio.vhdl
  F011 software-visible facade
  Real-drive select and virtualisation gates
  Motor/select/side/step/write-gate control
  MFM/RLL/raw physical decode and encode
  512-byte sector buffer
  SD-image and hypervisor alternatives
        |
        v
Physical PC-style 3.5-inch drive
```

`machine.vhdl` is worth calling out because it is not just a passive port map.
It combines two write-data sources:

```vhdl
f_wdata <= f_wdata_sd and f_wdata_cpu;
```

`f_wdata_sd` is the normal `sdcardio` writer. `f_wdata_cpu` is the GS4510
raw-flux DMA writer. Since the physical write-data line is active low, the
logical AND lets either source pull the output low. This is a powerful but
dangerous ownership model: higher-level control must ensure both writers are
not active in conflicting ways.

The same block can loop write-data back into read-data for debug:

```vhdl
if f_rdata_loopback='1' then
  f_rdata_switched <= f_wdata_sd and f_wdata_cpu;
else
  ...
end if;
```

The future C64MEGA65 design should probably not copy this exact two-writer
arrangement unless it also defines an explicit drive-ownership policy.

## Software-Visible Interface: F011 First, Not WD1772

MEGA65 software normally accesses the physical drive through the C65 F011
register model:

| Register | Name | Purpose |
| --- | --- | --- |
| `$D080` | F011 control | drive select, side, buffer swap, motor, LED, IRQ enable |
| `$D081` | F011 command | read sector, write sector, read track, write track/format, step, spin, cancel, clear buffer |
| `$D082` | Status A | TK0, PROT, LOST, CRC, RNF, EQ, DRQ, BUSY |
| `$D083` | Status B | DSKCHG, IRQ, INDEX, DISKIN, WGATE, RUN/RDREQ, WTREQ, RDREQ |
| `$D084` | Track | target track |
| `$D085` | Sector | target sector |
| `$D086` | Side | target side |
| `$D087` | Data | byte access to the 512-byte sector buffer |
| `$D088` | Clock | clock pattern for marks, normally `$FF` |
| `$D089` | Step | step interval in 62.5 us units |
| `$D08A` | PCODE | protection code, not implemented |

The MEGA65 extension page around `$D680-$D6AF` adds control over SD-card access,
disk-image backing, real-drive selection, physical debug pins, data rate,
encoding, track-info blocks, and virtual-F011 status injection.

High-value extension registers:

| Register | Purpose |
| --- | --- |
| `$D689` | F011 buffer pointer/status, drive swap, mapped buffer select |
| `$D68A` | virtualised-FDC and image-mode status |
| `$D68B` | F011 image enable/present/write-enable and D65/MEGA-disk flags |
| `$D68C-$D68F` | drive 0 disk-image start sector on SD |
| `$D690-$D693` | drive 1 disk-image start sector on SD |
| `$D696` | auto-tune / auto-seek for FDC sector operations |
| `$D6A0` | physical FDC debug/status and direct line control |
| `$D6A1` | use real floppy for drive 0/1, match-any-sector, silent SD behavior |
| `$D6A2` | data rate in bus cycles per magnetic interval |
| `$D6A3-$D6A5` | last found track/sector/side |
| `$D6A6-$D6A9` | MEGA65 track information block readback |
| `$D6AE` | encoding and HD/variable-rate/TIB controls |
| `$D6AF` | virtual-F011 manual status flag write, debug gap readback |

There is also a memory-mapped F011 sector buffer at `$FFD6C00-$FFD6DFF`.

The key mismatch for our future work is here: a Commodore 1581 contains a
WD1770/WD1772-family FDC visible to the 1581 drive CPU. The MEGA65 native
physical-drive path is instead F011/F018-compatible. They both describe
track/side/sector operations over 512-byte sectors, but they are not the same
register-level contract.

## `sdcardio.vhdl`: What It Actually Does

`sdcardio.vhdl` is the center of the MEGA65 physical-drive design. Its name is
misleading for our purpose: it is not only an SD-card controller. It owns all of
these concerns:

- F011 register reads and writes.
- SD direct sector access.
- F011 disk-image mode.
- real physical drive mode.
- virtualised F011 mode via hypervisor traps.
- physical drive pins.
- F011 sector buffer RAM.
- MFM/RLL/raw decode and encode.
- CRC generation/checking.
- read, write, step, spin-up, timeout, and format state machines.
- HD/DD decoder selection and MEGA65 track information blocks.
- assorted nearby MEGA65 slow-device control registers.

Important internal state includes:

- `f011_track`, `f011_sector`, `f011_side`.
- `f011_buffer_cpu_address` and `f011_buffer_disk_address`.
- `f011_busy`, `f011_drq`, `f011_lost`, `f011_rnf`, `f011_crc`.
- `f011_rsector_found`, `f011_wsector_found`.
- `use_real_floppy0`, `use_real_floppy2`.
- `virtualise_f011_drive0`, `virtualise_f011_drive1`.
- `fdc_read_request`, `fdc_sector_operation`, `target_any`.
- `cycles_per_interval`, `cycles_per_interval_actual`, `fdc_encoding_mode`.

Physical-helper instances in `sdcardio.vhdl` include:

- `crc1581` for sector CRC.
- three `mfm_decoder` instances:
  - normal DD decode,
  - HD-only decode,
  - variable-rate decode.
- `mfm_bits_to_gaps` for MFM writing.
- `rll27_bits_to_gaps` for RLL writing.
- `raw_bits_to_gaps` for raw output.

The decoder path ultimately observes `f_rdata` and emits:

- sector header match status,
- decoded track/sector/side,
- decoded data bytes,
- byte-valid strobes,
- sector-end strobes,
- CRC status.

The write path serialises bytes through the selected encoder into timed
write-data pulses while `f_wgate` is active.

## Read-Sector Flow In MEGA65

At the software-visible level, a physical-sector read looks like this:

1. Select drive, side, motor, and optional buffer swap through `$D080`.
2. Write target track, sector, and side through `$D084-$D086`.
3. Write read-sector command `$40` or `$44` to `$D081`.
4. Poll `$D082/$D083` for BUSY, DRQ, EQ, RNF, CRC, LOST, and RDREQ.
5. Read the 512-byte sector through `$D087` or the mapped sector buffer.

Inside `sdcardio.vhdl`:

1. The `$D080` handler drives active-low motor/select outputs:
   `f_motora`, `f_selecta`, `f_motorb`, `f_selectb`, and side select.
2. The `$D081` read command checks selected drive, real-drive enable,
   virtualisation bits, disk-image presence, and drive number.
3. If a real, non-virtualised drive is selected, it asserts
   `fdc_read_request`, marks the F011 busy, sets index/rotation timeouts, and
   enters `FDCReadingSectorWait`.
4. `FDCReadingSectorWait` waits until the target sector is not already under
   the head, to avoid capturing only the tail end of a sector.
5. `FDCReadingSector` watches decoder outputs. When target data bytes arrive,
   they are written into the F011 sector buffer and DRQ is asserted.
6. CRC failure sets the CRC flag but allows retry until timeout.
7. Sector-end on the target sector clears BUSY and returns to idle.
8. Timeout sets RNF and clears the in-progress request.

The key future lesson is that the MEGA65 physical read path is naturally a
request/status/512-byte-buffer service. That shape can be made compatible with a
MiSTer sector backend, but only after explicit translation.

## Write-Sector Flow In MEGA65

At the software-visible level:

1. Software fills the F011 buffer through `$D087` or `$FFD6C00-$FFD6DFF`.
2. Software writes target track/sector/side.
3. Software writes write-sector command `$80` or `$84` to `$D081`.
4. Software polls F011 status.

For a real drive, `sdcardio.vhdl` enters `F011WriteSectorRealDriveWait` and
then `F011WriteSectorRealDrive`:

1. Wait for the decoder to find a fresh target sector header.
2. Immediately open write gate by driving `f_wgate <= '0'`.
3. Reset the disk-side F011 buffer pointer.
4. Write gap bytes, sync bytes, data mark, 512 data bytes, CRC bytes, and a
   short trailing gap.
5. Close write gate by driving `f_wgate <= '1'`.
6. Clear BUSY and return to idle.

The comments are explicit that the sector buffer is not available for CPU reads
while real sector write is in progress. That matters if a future bridge tries to
make the same buffer visible to MiSTer drive logic and a physical controller at
the same time.

For SD-image backed writes, `sdcardio` copies the F011 buffer into the SD
sector path. That SD-image path is not the one we want in C64MEGA65, because
C64MEGA65 already has a QNICE/FAT32/vdrives image cache and dirty-flush policy.

## Format And Non-Sector Operations

F011 command `$A0/$A4/$A8/$AC` is write-track/format. MEGA65 accepts this only
for a selected real drive that is not virtualised.

Two modes exist:

- Buffered/automatic formatting through `FDCAutoFormatTrack*`.
- Unbuffered formatting through `FDCFormatTrack*`, matching old C65 ROM
  expectations where software feeds bytes with tight timing.

Automatic formatting writes 1581/PC-style gap and sector structures, plus
MEGA65 track information blocks for advanced formats. `$D6AE` can select MFM,
RLL2,7, raw, forced/auto 2x decoding, variable speed, and TIB use.

For the future C64MEGA65 1581 backend, format support should be treated as a
later and more dangerous milestone:

- MiSTer `fdc1772.v` currently fakes read-track/write-track commands.
- MEGA65 can physically format, but through F011 semantics.
- Real format support must define how WD1772 write-track behavior maps to the
  MEGA65 physical writer, including write-protect, disk-change, density, and
  user safety policy.

A read-only sector backend is the safer first target.

## Firmware And Policy Layer In MEGA65

MEGA65 firmware uses the hardware registers to decide whether F011 drives use
SD-card disk images or the internal real floppy.

Notable details:

- `docs/MEGA65_System_Partition.md` documents system partition byte `$004.0`:
  `0` means F011 uses disk images from SD, `1` means F011 uses the internal
  3.5-inch physical drive.
- HYPPO boot logic looks for `MEGA65.D81` unless the system is configured to
  use the real internal drive.
- `src/hyppo/dos.asm` contains attach/detach logic for images and real drives.
- `src/hyppo/virtual_f011.asm` implements hypervisor trap service for virtual
  F011 sector read/write, using `$D6AF` to stomp F011-visible completion flags.
- `src/hyppo/main.asm` maps virtual-F011 traps `$44` and `$45` to the read/write
  handlers.

This is useful design context, but it is also a warning: copying `sdcardio`
wholesale would drag in MEGA65-native policy and SD-card assumptions that do not
belong in C64MEGA65's QNICE/M2M storage architecture.

## What `internal1581.vhdl` Is Not

`src/vhdl/internal1581.vhdl` is not the active physical-drive implementation.

It contains:

- a 6502-like drive CPU setup,
- CIA/VIA-ish support,
- RAM/ROM decode,
- an IEC-facing internal drive model,
- an address decode for `$600x = WDC 1770 FDC`.

But the FDC read path is stub-like:

```vhdl
elsif cs_fdc='1' then
  rdata <= (others => '1');
```

The active MEGA65 production path is board top -> `machine.vhdl` ->
`iomapper.vhdl` -> `sdcardio.vhdl`, not `internal1581.vhdl`.

For the future C64MEGA65 task, `internal1581.vhdl` should not be treated as a
shortcut to real 1581 physical-drive support.

## Paul Blog Timeline, Condensed

The blog archive is useful because it explains why the design has the shape it
does.

2014: F011/D81 image emulation

- Early C65GS work implemented enough F011 behavior for C65 DOS to see an
  internal D81-style drive backed by SD-card sectors.
- The model already involved D81 image base sectors, disk-present status,
  write-protect status, F011 sector buffer behavior, and physical-vs-logical
  sector translation.

2018: physical drive bring-up

- Paul brought up the standard PC 3.5-inch 34-pin interface.
- He documented the physical signals and active-low conventions.
- The next work added direct physical control/debug registers and a VHDL MFM
  decoder that could find real 1581 sectors and feed the F011 path.
- Important bugs found at this stage included side polarity and
  track/sector/side matching details.

2019-2020: board and reliability fixes

- R2/R3 hardware needed pull-up and signal-behavior fixes.
- Configure gained the ability to select real drive versus disk image.
- Practical read bugs appeared around seek accuracy, timeouts, and side-byte
  reliability. Auto-tune/auto-step behavior was added so the FDC could correct
  the physical head position.

2021: write, format, HD, and fast-loader work

- The write path gained real MFM write support, CRC handling, and sector
  formatting.
- By August 2021, internal floppy read/write/format reached a clear milestone.
- HD support added a 2x read path; a 1600 KB format became possible with 20
  sectors per side, though C65 DOS remains DD-oriented.
- A direct-FDC fast-loader proved that software can bypass C65 DOS and use the
  F011 controller directly for background loading.

2022 and later: advanced formats and IEC

- RLL, raw flux, track info blocks, and higher-density formats were explored.
- External IEC support and hardware-accelerated IEC work proceeded separately.
- A 2024 R3/R3A issue with physical external 1581 drives was traced to SRQ line
  handling and output-enable polarity. That is about the external IEC port, not
  the internal PC-style floppy connector, but it is relevant if C64MEGA65 mixes
  simulated drive 8 with real IEC devices.

The important distinction is that "internal drive" in early 2014 posts often
means an SD-backed F011/D81 path. The physical 3.5-inch mechanism work begins in
earnest in 2018.

## Current C64MEGA65 Drive Architecture

C64MEGA65 currently has a separate MiSTer-style storage path:

```text
QNICE Shell selects .D64 or .D81
        |
        v
C_DEV_C64_MOUNT staging buffer
        |
        v
M2M/vhdl/vdrives.vhd
        |
        v
MiSTer sd_* sector/byte interface
        |
        v
CORE/vhdl/main.vhd
        |
        v
CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv
        |
        +--> c1541 path for D64
        |
        +--> c1581 path for D81
              |
              v
            c1581_drv.sv
              |
              v
            fdc1772.v
```

The QNICE Shell accepts exact-size D81 files of 819,200 bytes. `iec_drive.sv`
latches `img_type`; `dtype[1]` selects the 1581 path. In the 1581 path:

- `c1581_drv.sv` instantiates an emulated 1581 drive CPU, CIA, VIA, ROM, and
  `fdc1772`.
- The WD1772 register interface is internal to the emulated 1581 drive.
- `fdc1772.v` computes a logical LBA from WD1772 track/side/sector state.
- It requests one 512-byte sector through `sd_lba`, `sd_rd`, `sd_wr`,
  `sd_ack`, and `sd_buff_*`.
- `iec_drive.sv` shifts the 1581 `sd_lba` left by one because C64MEGA65
  instantiates `vdrives` with `BLKSZ => 1`, i.e. 256-byte host blocks.

`M2M/vhdl/vdrives.vhd` does not know D81 geometry. It is a generic MiSTer
sector service and byte pump. The Shell handles the actual file staging and
dirty-cache flush policy.

This architecture is good news: the C64-visible 1581 already reduces media
access to "read/write this logical 512-byte sector." That is much closer to the
shape of the MEGA65 physical F011 read/write operation than raw flux would be.

## Current C64MEGA65 Physical Floppy Pin State

C64MEGA65's M2M board top files already expose physical floppy pins for board
compatibility, but they do not use them:

- `M2M/vhdl/top_mega65-r3.vhd`
- `M2M/vhdl/top_mega65-r4.vhd`
- `M2M/vhdl/top_mega65-r5.vhd`
- `M2M/vhdl/top_mega65-r6.vhd`

All floppy outputs are tied high/inactive. Inputs are declared but not consumed.

Also, `M2M/vhdl/controllers/M65` does not contain the MEGA65 physical floppy
stack. It contains a curated set of MEGA65-origin or MEGA65-related helpers for:

- keyboard matrix,
- key number conversion,
- mouse/paddle input,
- R3 MAX10 handling,
- audio/PDM.

It does not contain:

- `sdcardio.vhdl`,
- `iomapper.vhdl`,
- `mfm_decoder.vhdl`,
- MFM/RLL/raw gap helpers,
- `crc1581.vhdl`,
- `internal1581.vhdl`.

So the future task is not "reuse what is already copied under
`M2M/vhdl/controllers/M65`." The relevant MEGA65 drive code has not been copied
into C64MEGA65 yet.

## Interface Mismatch: F011 vs MiSTer 1581

The central design question is where the future bridge should attach.

### MEGA65 physical drive side

Natural abstraction:

```text
request:
  operation = read sector | write sector | maybe format later
  drive = 0 or 1
  track
  sector
  side
  data buffer = 512 bytes

status:
  busy
  done
  rnf
  crc_error
  lost_data
  write_protect
  disk_changed
  track0
  index
  diagnostics: last found track/sector/side
```

This is F011-shaped. It is buffer/status oriented.

### MiSTer 1581 side

Natural abstraction today:

```text
request from fdc1772:
  sd_lba
  sd_rd or sd_wr
  sd_buff_addr
  sd_buff_dout for writes
  sd_ack handshake

data:
  512-byte logical sector
```

The WD1772 register behavior is already emulated above that boundary. The
physical backend does not need to expose WD1772 registers if it can satisfy
these sector requests.

### Wrong boundary to avoid

Replacing `c1581_drv.sv` with MEGA65 F011 behavior would be a large semantic
change. It would remove or bypass the MiSTer 1581 DOS/WD1772 model that the C64
expects to talk to over IEC.

Dropping MEGA65 `sdcardio.vhdl` into C64MEGA65 would also be too broad. Its
front end expects MEGA65 fast I/O, hypervisor state, SD-card ownership,
security/system-register policy, and MEGA65 firmware conventions.

## Candidate Future Attachment Points

### Option 1: external IEC only

C64MEGA65 already has a hardware IEC path for real external Commodore drives.
If the user plugs in a real 1581, this path is conceptually separate from the
MEGA65 internal physical floppy connector.

This does not solve the requested future task. It makes the real drive a peer on
the C64 IEC bus, not a backend for the simulated MiSTer 1581.

### Option 2: replace or mux the `vdrives` sector service

This is the most promising high-level cut.

Today:

```text
fdc1772 sd_* request -> vdrives -> QNICE image cache
```

Future physical mode:

```text
fdc1772 sd_* request -> physical_1581_sector_service -> MEGA65 physical FDC slice
```

The service would accept the same logical sector request that `vdrives` already
sees, translate LBA to physical 1581 track/side/sector, run a real-drive read or
write, and then drive `sd_ack` / `sd_buff_*` back to `fdc1772`.

Pros:

- Keeps the MiSTer 1581 drive CPU, DOS ROM, IEC behavior, and WD1772 frontend.
- Does not mix MEGA65 direct SD-image mode with C64MEGA65's QNICE image cache.
- Lets C64MEGA65 keep existing D81 image support unchanged.
- Provides a clear menu-level choice: image-backed 1581 or physical-drive 1581.

Cons:

- Need a new physical-sector service and CDC/buffer arbitration.
- Need to map physical errors back into `fdc1772`/WD1772 status behavior.
- Mechanical latency may interact with MiSTer virtual floppy timing.
- Format/read-track/write-track behavior is not solved by ordinary sector
  requests.

### Option 3: replace the media layer inside `fdc1772.v`

This is similar to option 2, but lower-level and maybe cleaner if `fdc1772`
needs direct knowledge of physical latency and error status.

Instead of `fdc1772` issuing generic `sd_*` requests, it could issue a more
explicit physical-sector request:

```text
track, side, sector, read/write, buffer, status
```

Pros:

- Avoids overloading `sd_*` with non-SD semantics.
- Easier to pass detailed status back into WD1772 emulation.
- Cleaner long-term if image and physical backends diverge.

Cons:

- Touches MiSTer-derived `fdc1772.v`.
- More invasive.
- Needs careful compatibility review for D81 image mode.

### Option 4: F011 wrapper pretending to be WD1772

This is the risky path.

It would mean translating the 1581 drive CPU's WD1772 register accesses into
F011 commands. That sounds attractive because the MEGA65 physical path is
F011-facing, but it creates a WD1772 compatibility project:

- WD1772 command timing,
- status bit behavior,
- DRQ/IRQ behavior,
- read-address,
- multi-sector commands,
- read-track/write-track,
- motor/ready/index behavior,
- formatting.

This is probably the wrong first refactor.

## Recommended Reuse Strategy

Do not import `sdcardio.vhdl` whole.

Extract or wrap only the physical-sector subset:

1. physical pin control:
   - motor/select,
   - side,
   - step/stepdir,
   - density,
   - read data,
   - write data/gate,
   - index/track0/write-protect/disk-change.

2. decode helpers:
   - `mfm_decoder`,
   - `mfm_gaps`,
   - `mfm_quantise_gaps`,
   - `mfm_gaps_to_bits`,
   - `mfm_bits_to_bytes`,
   - `rll27_quantise_gaps`,
   - `rll27_gaps_to_bits`,
   - `crc1581`.

3. write helpers:
   - `mfm_bits_to_gaps`,
   - `rll27_bits_to_gaps`,
   - `raw_bits_to_gaps`,
   - `crc1581`.

4. sector operation FSMs:
   - read sector wait/read,
   - write sector wait/write,
   - step/spin-up support,
   - status and timeout handling.

5. a new narrow C64MEGA65-facing interface:

```text
physical_1581_sector_service
  clk_fdc_i
  reset_i

  req_i
  wr_i
  drive_i
  track_i
  side_i
  sector_i
  cancel_i

  buffer_addr_i/o
  buffer_data_i/o
  buffer_we_i/o

  busy_o
  done_o
  rnf_o
  crc_error_o
  lost_o
  write_protect_o
  disk_present_o
  disk_changed_o
  track0_o
  index_o

  physical f_* pins
```

The service can internally borrow MEGA65 F011 logic, but it should not expose
MEGA65 `$D080-$D6AF` registers as its primary contract.

## LBA To Physical 1581 Geometry

The standard D81 size is 819,200 bytes:

```text
80 tracks * 2 sides * 10 sectors/side * 512 bytes = 819,200 bytes
```

MEGA65 F011/D81 image mapping in `sdcardio` uses C65-style track/sector/side
geometry. For image mode, the code maps side 0 and side 1 into a linear
physical sector number around a 20-sector-per-track model.

MiSTer `fdc1772.v` computes an LBA from its WD1772 state. For
`SECTOR_SIZE_CODE == 2` (512-byte sectors), it uses the current track, side,
sector, sectors-per-track, and double-side flag. In standard D81 geometry, that
becomes a 0-based 512-byte sector index.

For a physical-service backend, the bridge can choose one of two shapes:

1. Let `fdc1772` keep computing LBA, then translate LBA back to track/side/sector
   in the physical backend.
2. Add a lower-level request path from `fdc1772` that sends track/side/sector
   directly.

Option 2 is cleaner semantically. Option 1 is less invasive because it can sit
where `vdrives` sits today.

The side convention must be verified. Paul found side/track/sector matching
issues during 2018 real-drive bring-up, and `mfm_decoder.vhdl` currently has
side matching commented out in one path while still tracking side as diagnostic
state. A future read-only prototype should log requested versus found
track/sector/side before trusting all media.

## Clocking And CDC

Clocking is not a detail here.

The current C64MEGA65 1581 media path has these clock domains:

- `clkcpu` inside `fdc1772.v`: 1581 drive CPU/FDC behavior.
- `clk_sys` in the MiSTer SD path: QNICE/vdrives domain for `sd_*`.
- C64 main clock around 31.5 MHz.
- QNICE clock.

The MEGA65 physical FDC code is written around the MEGA65 CPU clock and
`cpu_frequency` timing constants. Those constants drive:

- MFM interval quantisation,
- index timeouts,
- rotation timeouts,
- step timing,
- encoder output spacing.

A future physical service needs a deliberate FDC sampling/writing clock. It
should not assume the C64 main clock is suitable just because the VHDL compiles.

CDC boundaries to design explicitly:

- request from `fdc1772` or `vdrives` domain to physical-FDC domain,
- 512-byte buffer ownership,
- completion and error status back,
- asynchronous physical input conditioning,
- reset/cancel behavior.

## Reset, Ownership, And Safety

The current C64MEGA65 vdrive image path has a dirty-cache policy: writes mark
the mounted image dirty, QNICE flushes later, and `main.vhd` prevents normal
resets from interrupting in-flight virtual disk writes.

A physical drive path is different:

- There is no image cache to flush.
- A real write in progress must not be aborted with `f_wgate` active.
- Disk change must invalidate any cached assumptions.
- Write protect must be honored before write/format commands.
- Motor/select ownership must be single-writer.

Suggested future policy:

- Physical mode and image mode are mutually exclusive per drive.
- Physical read-only mode comes first.
- Physical write mode is a separate explicit feature gate.
- Format is a later explicit feature gate.
- A hard reset must force write gate inactive and de-select the drive.
- OSM/menu actions must not steal the drive while a physical operation is busy.
- External IEC drive 8 collisions remain a user-policy problem separate from
  the internal physical backend.

## Adversarial Checks

These are the main traps found during the research.

### "Can we just use `internal1581.vhdl`?"

No. It is not the active physical backend and its FDC data path is incomplete in
this checkout.

### "Can we just use `sdcardio.vhdl`?"

Not cleanly. It is too entangled with MEGA65 fast I/O, SD-card, QSPI, I2C,
hypervisor, disk-image, sector-buffer mapping, and system policy. It is useful
as source material, not as a drop-in entity.

### "Can we keep C64MEGA65's D81 image support unchanged?"

Yes, if physical mode is implemented as an alternate backend under the MiSTer
1581 media request boundary. Do not mix MEGA65 `sdcardio` SD-image mode with
C64MEGA65 QNICE/vdrives image mode.

### "Is F011 close enough to WD1772?"

Close enough at the sector/media level for standard 512-byte sector reads and
writes, but not at the register level. Avoid pretending F011 is a WD1772.

### "Will physical-drive latency break the MiSTer 1581?"

Unknown. It might work for ordinary DOS operations if `fdc1772` can remain busy
until the backend completes. It must be verified in simulation and hardware.
Fast loaders, read-track/write-track, and formatting are higher risk.

### "Are all board revisions equivalent?"

No assumption should be made. The physical floppy pins exist in board tops, but
R3/R4/R5/R6 pinout, buffering, pull-ups, and related IEC quirks have differed in
MEGA65 history. The feature should be board-gated until tested.

### "Can we rely on side matching?"

Not blindly. MEGA65 code and blog history both show side-related caveats. The
future backend should expose diagnostics for requested and found
track/sector/side.

### "Can writes be enabled immediately?"

No. Read-only should be the first milestone. Writes and format need explicit
write-protect, disk-change, timeout, reset, and user confirmation policies.

## Suggested Future Milestones

Milestone 0: simulation-only contract

- Define a tiny physical-sector request/status interface.
- Add a fake backend that returns sectors from a known D81 image or static test
  sectors.
- Prove the MiSTer 1581 DOS still reads directory sectors through that interface.

Milestone 1: extracted MEGA65 physical read sector service

- Extract only the MEGA65 physical read-sector pieces into a standalone harness.
- Feed simulated MFM pulses first.
- Verify track/sector/side matching and CRC behavior.

Milestone 2: C64MEGA65 read-only hardware experiment

- Wire M2M floppy pins through a clearly experimental path.
- Add physical drive as an alternate backend for D81/1581 drive 8.
- Read only.
- No format.
- No writes.
- Standard DD 720 KB 1581 disks only.
- Log diagnostics or expose status via QNICE/OSM/debug.

Milestone 3: single-sector writes

- Enable only after read-only is stable.
- Honor write protect.
- Abort safely on reset.
- Test disk-change behavior.
- Test with sacrificial media.

Milestone 4: formatting and advanced formats

- Decide whether WD1772 write-track should map to MEGA65 automatic format,
  unbuffered F011 format, or remain unsupported.
- Consider HD, RLL, raw, and track information blocks only after standard DD
  behavior is reliable.

## Open Questions For The Future Refactor

- Which clock should own the physical FDC sampler/encoder in C64MEGA65?
- Can the MEGA65 MFM/RLL helpers meet timing in the C64MEGA65 Vivado projects?
- How much of `sdcardio` can be extracted before dependencies become expensive?
- Should the bridge sit below `vdrives`, inside `fdc1772`, or as a mux between
  `iec_drive` and `vdrives`?
- How should physical RNF/CRC/lost/write-protect/disk-change map into WD1772
  status bits?
- What should read-address/read-track/write-track return in physical mode?
- Should physical mode disable the simulated image mount, or appear as a special
  mount type?
- How should the menu expose image-backed D81 versus physical 1581 media?
- How should external IEC drive conflicts be handled when the internal physical
  backend is also device 8?
- Which board revisions should be supported first?
- What is the license/attribution policy for copied MEGA65 VHDL helpers?

## Practical Recommendation

Treat the MEGA65 work as a proven physical-FDC reference implementation, not as
a module to paste into C64MEGA65 unchanged.

For C64MEGA65, the lowest-risk architecture is:

```text
C64 IEC view
  stays MiSTer c1581_drv

WD1772 view
  stays MiSTer fdc1772, at least initially

Media backend
  becomes selectable:
    current QNICE/vdrives D81 image service
    or
    new physical_1581_sector_service

Physical service internals
  selectively reuse MEGA65 MFM/RLL/CRC/sector FSM logic
```

This keeps the existing C64-visible behavior stable and confines the difficult
new work to a narrow physical media service. If that boundary proves too weak,
then move the cut one level down inside `fdc1772`; do not start by replacing the
whole MiSTer 1581 drive model with F011.
