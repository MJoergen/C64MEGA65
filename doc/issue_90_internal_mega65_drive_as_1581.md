# Issue #90: Internal MEGA65 Drive as a Physical Commodore 1581

Implementation specification

- Research and specification date: 2026-07-11–12
- Target issue: [MJoergen/C64MEGA65 #90](https://github.com/MJoergen/C64MEGA65/issues/90)
- Prerequisite feature: simulated D81/1581 support from issue #91

> This document is normative for the implementation. `MUST`, `MUST NOT`,
> `SHOULD`, `SHOULD NOT`, and `MAY` have their usual requirements-language
> meanings.
>
> This is a specification, not an implementation. It intentionally contains no
> patch for the RTL.

## 0. Executive decision

The internal MEGA65 floppy mechanism will be offered as a selectable physical
media source for the existing simulated Commodore 1581 on IEC device 8.

The C64-facing half of the drive remains unchanged in concept:

- the existing 1581 6502 CPU;
- the stock or JiffyDOS 1581 ROM;
- the 8520, VIA, IEC, and fast-serial behavior already present in
  `c1581_drv.sv`;
- the WD1772 register interface seen by the 1581 CPU.

The media-facing half changes in physical mode:

- the real motor, head, side, index, write-protect, and disk-change state
  replace the virtual mechanics in `floppy.v`;
- a new 50 MHz physical controller conditions the real pins, decodes and
  encodes DD MFM, checks and generates CRCs, and enforces mechanical timing;
- `fdc1772.v` receives explicit physical results, status, cancellation, and
  mechanics acknowledgements instead of treating the mechanism as a perfect
  disk image;
- the existing image path remains the active path when “Image” is selected.

A live mux at the existing `sd_*` interface is explicitly rejected as the final
architecture. That boundary has no error or cancellation channel and leaves
virtual motor, index, track, sector, and byte timing active. It would add a
second rotational wait, fail to move the real head for Type-I commands, hide
write protection and CRC failures, and continue to report fake success for
Read Track and Write Track.

The implementation will be staged, but the production support claim is:

> A standard 3.5-inch DD disk formatted for a Commodore 1581 is readable,
> writable, and formattable through the existing IEC-visible drive 8, with real
> media status and bounded failure behavior, while D64 and D81 image operation
> remains unchanged.

An experimental read-only milestone is useful, but it is not by itself the
definition of “physical 1581 support.”

## 1. Scope

### 1.1 Required production behavior

The completed feature MUST:

1. Present the existing simulated drive computer as Commodore 1581 device 8.
2. Let the user choose `Image` or `Internal 1581` as the media source for drive
   8; `Image` remains the power-on and configuration default.
3. Keep the 1581 computer alive in physical mode even when the mechanism is
   empty, so IEC requests receive a bounded “not ready/no disk” result instead
   of “device not present.”
4. Support standard 1581 DD geometry: 80 cylinders, two sides, ten 512-byte
   physical sectors per side, sectors 1–10, 1,600 sectors total.
5. Implement real Type-I head movement, Type-II sector read/write, Read
   Address, Read Track, Write Track, and Force Interrupt behavior needed for
   standard 1581 DOS and direct-FDC diagnostics.
6. Support normal and deleted MFM data address marks.
7. Honor live write protect in the WD-visible status path and in an independent
   pin-level write safety interlock.
8. Propagate disk change, no index, record-not-found, ID CRC, data CRC, lost
   data, cancellation, and controller faults without stale-buffer delivery.
9. Format blank DD media using the normal WD Write Track token stream and stop
    magnetically at the ending index or the conservative pre-index tail-close
    deadline, never after the physical index boundary.
10. Preserve the existing D64/D81 image behavior bit-for-bit when image mode is
    active.
11. Build on all R3, R4, R5, and R6 targets. A board/build profile MUST permit
    physical activation only after that revision and mechanism configuration
    pass this document’s hardware qualification; the shared line may remain
    visibly disabled/rejected as section 15.1 specifies.
12. Leave all physical outputs inactive while the feature is disabled, while a
    board is unqualified, and during FPGA configuration/hard reset. After an
    ordinary controller fault during write, close WGATE/WDATA/STEP immediately,
    hold required mechanics controls for the 700 us guard, then make every
    output inactive as sections 11–12 require.

### 1.2 Explicit non-goals

The first production version MUST NOT claim support for:

- CMD FD-2000 or FD-4000 media;
- HD, ED, RLL, variable-rate, or MEGA65 Track Information Block formats;
- 1,024-byte FD-2000 sectors;
- FM/single-density operation;
- a second internal physical mechanism;
- a physical drive 9;
- arbitrary flux-level archival or reproduction;
- guaranteed reproduction of copy-protected or deliberately malformed media;
- USB floppy mechanisms;
- automatic detection of an external IEC device-number collision;
- taped-hole HD media as a supported substitute for genuine DD media.

The low-level design should not make those extensions impossible, but no
resource, schedule, or safety trade-off may be justified by an uncommitted
future format.

### 1.3 Definition of done for issue #90

Issue #90 may be closed only after:

- the read-only, write, and standard-format hardware gates have passed;
- the feature is enabled on both production R3/R3A and R6 qualified build/
  mechanism profiles; R4/R5 may remain safely inactive and documented without
  blocking closure;
- a disk formatted by this core is readable by a genuine 1581, and a disk
  formatted by a genuine 1581 is read in full by this core;
- all 1,600 sectors of a side-asymmetric golden disk compare byte-for-byte;
- write-protected media has been observed on a logic analyzer with no active
  write-gate pulse;
- the image-drive regression suite has passed;
- every claimed target meets the timing, CDC, and safety criteria in section
  20.

If maintainers intentionally ship only preformatted-media sector access, the
UI and release notes MUST say “experimental preformatted DD media support,”
Write Track MUST fail rather than report success, and issue #90 remains open
for formatting.

## 2. Source snapshot and authority

This specification incorporates and supersedes the implementation
recommendations and unresolved questions in
`doc/how-MEGA65-uses-the-physical-disk-drive.md`. That earlier document remains
research provenance only. All normative geometry, magnetic timing, electrical,
architecture, repository, safety, verification, and acceptance information
needed for issue #90 is restated here.

### 2.1 Local implementation snapshot

This specification was checked against:

| Source | Revision |
| --- | --- |
| C64MEGA65 | `895078f1f8abe68ee9e5595926fdfb2ba57f44a4` |
| C64MEGA65 branch | `mh_implement_90`, identical to `develop` at review time |
| MiSTer-derived C64 subtree | `1377b8d` |
| Current MEGA65 development core | `a9158930665763c592d004c895d52eff4a9eefc3` |
| Earlier MEGA65 snapshot in the research note | `4006aaa0b6c4734aefae4ace80fee60cba09ad77` |

The current MEGA65 revision was rechecked because
`doc/how-MEGA65-uses-the-physical-disk-drive.md` was written against the
earlier snapshot. The relevant physical read/write and codec structure remains
materially the same.

### 2.2 Primary technical sources

- [Commodore 1581 Service Manual, June 1987](https://www.historybit.it/wp-content/uploads/2024/03/1581_Service_Manual_1987_Jun.pdf),
  especially printed pages 1–2 and 9–12.
- [Commodore 1581 User’s Guide](https://s3.amazonaws.com/com.c64os.resources/weblog/sd2iecdocumentation/manuals/1581_Users_Guide.pdf),
  especially the burst-command and internal-operation chapters.
- [Western Digital 1986 Storage Management Products Handbook](https://www.bitsavers.org/components/westernDigital/_dataBooks/1986_Storage_Management_Products_Handbook.pdf),
  WD1770/WD1772 and WD1772-02 sections.
- [TEAC FD-235HF-A5xx mechanism specification, revision B](https://ftpmirror.your.org/pub/misc/bitsavers/pdf/teac/FD-235HFA5XX_Specification_Rev_B.pdf).
  This is a representative PC-style 3.5-inch mechanism specification, not a
  claim that every MEGA65 contains that exact model.
- [MEGA65 Chipset Reference](https://files.mega65.org/files/m/mega65-chipset-reference_4hh2eE.pdf),
  F011/physical-floppy chapter.
- [Commodore 1581 DOS source archive](https://www.zimmers.net/anonftp/pub/cbm/firmware/drives/new/1581/),
  specifically the archived `1581-source.zip`, used to trace the resident track
  cache, dirty byte, idle flush, error, disk-change, and timer paths. The source
  is implementation evidence for the bundled Commodore ROM, not a license to
  redistribute third-party replacement ROMs.
- Paul Gardner-Stephen’s
  [physical connector bring-up](https://c65gs.blogspot.com/2018/01/hooking-up-35-internal-floppy-drive.html),
  [MFM capture analysis](https://c65gs.blogspot.com/2018/01/bringing-internal-35-floppy-drive-to.html),
  [decoder bring-up](https://c65gs.blogspot.com/2018/01/bringing-internal-35-floppy-drive-to_15.html),
  and [write/format work](https://c65gs.blogspot.com/2021/08/write-and-format-support-for-internal.html).

When these sources conflict, section 5 records the binding decision.

### 2.3 Bundled ROM identity and cache-analysis anchor

The 32,768 bytes represented by both
`CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1581_rom.mif.hex` and
`c1581_rom.mif` are mutually byte-identical and have these identities:

| Digest | Value |
| --- | --- |
| SHA-256 | `8f689277f36be357f5f105e6e606c35c42e73c581cdeec14b58f31850dfbcfcb` |
| SHA-1 | `01228eae6f066bd9b7b2b6a7fa3f667e41dad393` |
| MD5 | `6a82f92aea2a3afa190fe32d565f39e7` |
| CRC32 | `a9011b84` |

They byte-match Commodore 1581 ROM 318045-02. All exact cache addresses and ROM
program counters in section 15.3 apply only to that effective byte sequence.
They MUST NOT be inferred from a ROM filename, slot, nominal 32 KiB size, menu
selection, or a successful upload. A replacement is a separate profile only
after its effective bytes have an exact digest and equivalent cache-state traces.

The profile check is made against the ROM actually read by the T65 after overlay/
upload selection. The implementation need not hash it continuously in hardware:
a build-time identity for the bundled ROM and an authenticated loader result for
an allowed replacement are sufficient, provided reset and ROM-bank changes
invalidate the profile until the newly effective image is proven. Tests MUST
reconstruct the byte stream from the MIF and fail if its digest drifts without a
corresponding profile review.

The archived master source names an earlier 318045-01 source lineage; this
specification claims source-line correlation and independently verified binary
identity with 318045-02, not that every archived source header was relabelled for
the later mask ROM.

## 3. Verified repository baseline

### 3.1 Existing drive stack

Issue #91 already provides the upper half needed by this feature:

```text
C64 IEC bus
  -> iec_drive.sv
     -> c1581_multi.sv
        -> c1581_drv.sv
           -> 1581 CPU + ROM + CIA + VIA
           -> fdc1772.v
              -> virtual floppy.v mechanics
              -> 512-byte dual-clock FIFO
              -> sd_* request
  -> M2M/vhdl/vdrives.vhd
     -> HyperRAM-cached D81 image
```

Relevant current anchors:

- drive reset and instances:
  `CORE/vhdl/main.vhd:1572-1716`;
- image-type and D81 LBA adaptation:
  `CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv:79-110`;
- 1581 CPU, CIA/VIA, image-derived status, and FDC instance:
  `CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1581_drv.sv:82-265`;
- virtual mechanics and WD command engine:
  `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v:237-709`;
- current image-request CDC and FIFO:
  `fdc1772.v:740-862`;
- current WD status construction:
  `fdc1772.v:971-979`.

### 3.2 Existing physical pins

All four top-levels expose the same named 15-signal floppy interface:

- R3: `M2M/vhdl/top_mega65-r3.vhd:170-185`;
- R4: `M2M/vhdl/top_mega65-r4.vhd:182-197`;
- R5/R6: `M2M/vhdl/top_mega65-r{5,6}.vhd:190-205`.

All physical outputs are currently tied high/inactive:

- R3: `top_mega65-r3.vhd:464-473`;
- R4: `top_mega65-r4.vhd:496-505`;
- R5/R6: `top_mega65-r{5,6}.vhd:535-544`.

Commit `78767048c1be7ba29e1279bb08f740679ad0dbcc` changed those defaults
from low to high after the internal drive kept spinning. High-safe defaults
are therefore a regression requirement.

The XDC files map the same signal names to the same package pins:

- `M2M/MEGA65-R3.xdc:228-242`;
- `M2M/MEGA65-R4.xdc:248-262`;
- `M2M/MEGA65-R5.xdc:255-269`;
- `M2M/MEGA65-R6.xdc:255-269`.

That establishes package routing only. It does not establish identical board
buffering, pull-ups, connector population, drive straps, or mechanism behavior.

### 3.3 Defects that block a naive backend mux

| Current behavior | Evidence | Physical consequence |
| --- | --- | --- |
| `sd_*` has request/data/ack but no result or cancel | `fdc1772.v:27-64,761-862` | no disk or CRC failure can hang or look successful |
| mechanics remain virtual | `fdc1772.v:237-361` | real motor, head, index, and track zero are ignored |
| sector DRQ waits for a virtual header | `fdc1772.v:585-600` | physical read plus virtual wait can add a revolution |
| write protect only affects status | `fdc1772.v:311,971-979` | the current write FSM does not prevent a write |
| CRC status is hardwired clear | `fdc1772.v:971-979` | damaged media cannot be represented |
| Read Track and Write Track fake success | `fdc1772.v:652-670` | formatting can report success without touching media |
| Read Address is synthesized | `fdc1772.v:672-681,938-947` | on-disk CHRN and ID CRC are invisible |
| drive reset depends on image mount | `main.vhd:1572-1580` | an empty physical drive would disappear from IEC |
| WP and disk change are image events | `c1581_drv.sv:82-87,228-231` | live media swaps are invisible |
| native decoder does not enforce side/size | MEGA65 `mfm_decoder.vhdl` | wrong surface or non-512 record can be accepted |
| native real-drive policy auto-tunes track | MEGA65 `sdcardio.vhdl` | it would hide WD seek/track-register errors |

## 4. Terminology and physical model

The internal mechanism is not an IEC Commodore drive and is not itself a 1565
or 1581. It is a PC-style 3.5-inch mechanism connected through a 34-pin
interface. The FPGA supplies the floppy controller; the existing emulated 1581
computer supplies DOS and IEC identity.

This specification uses:

- **1581 computer**: the emulated 6502, ROM, CIA, VIA, and WD-visible logic;
- **WD frontend**: the register, command, status, DRQ, and IRQ behavior in
  `fdc1772.v`;
- **physical controller**: the new 50 MHz mechanism/MFM engine;
- **mechanism**: the actual spindle, head carriage, heads, sensors, and analog
  read/write electronics;
- **image mode**: current D64/D81 operation through `vdrives`;
- **physical mode**: media operations through the internal mechanism;
- **track**: a cylinder number 0–79 unless explicitly called a DOS logical
  track;
- **side**: normalized logical side 0 or 1; electrical polarity is kept at the
  pin adapter only.

The UI MUST call the source “Internal 1581,” not “1565.” The unreleased 1565
name is not the software identity expected by DraCopy, GEOS, or normal
Commodore software.

## 5. Source conflicts and binding decisions

### 5.1 Gap byte typo and gap counts

The 1581 service manual prints a gap byte as hexadecimal `22` in one place.
Real captures, the rest of the manual, WD format guidance, and the MEGA65
implementation show that the intended filler is `4E`.

Binding decision:

- the reader ignores exact gap length;
- normal gaps are `4E`;
- three missing-clock `A1` bytes are required for standard MFM marks;
- the track formatter writes the compatible ten-record layout, consumes `4E`
  filler at real time until the real ending index, but suppresses magnetic
  filler after section 13.3's conservative pre-index tail close;
- no decoder may depend on the manual’s 22-versus-23 or 38-versus-24 gap
  count discrepancy.

### 5.2 One host STEP pulse per cylinder

An early blog post describes two steps per track. The representative mechanism
specification says one interface STEP pulse moves one track; its separate
“two steps per track” statement describes the internal stepper motor geometry.
The working MEGA65 and MiSTer-derived RTL also use one interface pulse.

Binding decision: one active-low host STEP pulse moves one cylinder. Hardware
qualification MUST verify this by observing both pulse count and physical head
movement. No “double-step” constant is permitted.

### 5.3 WD1770 versus WD1772

Original 1581 units may contain a WD1770 or WD1772. The current core selects
`MODEL=2` and already models WD1772 step-rate codes.

Binding decision: this feature preserves the current WD1772 identity:

| Rate code | WD1772 nominal |
| --- | ---: |
| `00` | 6 ms |
| `01` | 12 ms |
| `10` | 2 ms |
| `11` | 3 ms |

The physical sequencer clamps a requested rate to the qualified mechanism
minimum. It does not pretend the mechanism can accept 2 ms just because the
WD1772 code can request it. Type-II/III `E` delay is 15 ms.

For the WD1772-02 write commands, P=0 enables the model-specific nominal
plus/minus 187 ns write precompensation and P=1 disables it. At 50 MHz the
initial binding is the nearest value, 180 ns/nine cycles; a qualified profile
may select 200 ns/ten cycles only with documented inner-track read-back
evidence. The generic WD177x 125 ns figure is not used for this MODEL=2 path.

The WD1772 flow and the existing model use a six-index-pulse spin-up sequence.
Count six qualified leading edges; the first establishes rotational phase and
the following five inter-edge intervals are complete revolutions. Six edges is
the binding implementation count and must not be confused with the separate
five-index-hole record-search limit.

### 5.4 Record search timeout

WD documentation uses wording that can be read as four revolutions in one
place, while its examples/flow and existing emulation count five index
opportunities.

Binding decision: use two independent wall-clock limits. Readiness has a
1.10-second deadline beginning at physical motor assertion (or command start if
the motor was already requested but not ready). Record search has a five-index
limit plus an absolute `5*P_read_max + W_index_max + filter/CDC margin` deadline,
initially 1.300 seconds, beginning when search starts. Neither
wall-clock timer is conditional on seeing index or becoming ready. Missing or
malformed index therefore cannot leave BUSY asserted forever.

### 5.5 Sector matching, side byte, and size code

The WD1770/1772 lacks the WD1773 side-compare command option. For a Type-II
command it matches a valid ID CRC, C equal to the Track register, and R equal
to the Sector register. The electrical side-select output chooses the surface;
the ID H byte is not part of the WD1772 comparison. Type-I Verify compares C
and a valid ID CRC only.

Binding decision:

- reproduce that WD matching behavior; do not reject a sector or Verify solely
  because H differs from the selected side;
- retain actual H for Read Address, Read Track, diagnostics, and the side-
  asymmetric hardware qualification test;
- specialize the issue-#90 data path to standard 1581 `N = 02`/512-byte
  sectors, consistent with the existing `c1581_drv.sv` instantiation of
  `fdc1772.v` with `SECTOR_SIZE_CODE(2)`;
- if a matching C/R record has another N, report `RES_UNSUPPORTED_SIZE` and RNF
  rather than overrunning a 512-byte buffer or pretending success.

The N restriction is a documented implementation specialization, not claimed
as generic WD1772 behavior: a real WD1772 derives 128/256/512/1,024-byte field
length from N. Supporting nonstandard N values later requires an end-to-end
buffer/DRQ review and is not part of standard D81 issue #90. Wrong-side wiring
is caught with known side-asymmetric media, never by adding a non-WD H compare.

### 5.6 Density and pin 34

PC mechanisms can strap pin 2 and pin 34 differently. Pin 2 can be input,
output, disk-change, or open; pin 34 can be READY or DISK CHANGE.

Binding decision:

- only the MEGA65-supported configuration with pin 34 as DISK CHANGE is
  qualified;
- DD mode holds `f_density_o` at the board/drive-qualified DD-safe level,
  initially the current safe high value;
- genuine DD media is the supported medium;
- READY is synthesized from motor time, index, and settle state rather than
  assumed to exist on pin 34;
- each mechanism model and strap configuration is recorded during
  qualification.

### 5.7 F011 policy versus WD policy

MEGA65’s native F011 path auto-seeks on mismatching headers, retries data CRC
until timeout, hardcodes real-media presence, and uses F011 status semantics.

Binding decision: reuse codec and physical-state-machine ideas, not F011
policy. In physical 1581 mode:

- no implicit auto-seek occurs during a WD sector command;
- Type-I commands are the only normal source of head movement;
- a data-field CRC error terminates the WD command rather than silently
  retrying;
- live index, write protect, disk change, and bounded presence inference are
  authoritative;
- WD status, IRQ, DRQ, and Force Interrupt remain owned by the WD frontend.

## 6. Standard 1581 media contract

### 6.1 Geometry

| Property | Required value |
| --- | ---: |
| Medium | 3.5-inch DD MFM |
| Rotation | nominal 300 RPM |
| Cylinders | 80, numbered 0–79 |
| Sides | 2, numbered 0–1 |
| Sectors per side/cylinder | 10 |
| Physical sector numbers | 1–10 |
| Physical payload | 512 bytes |
| ID size code | `02` |
| Total sectors | 1,600 |
| Payload/image size | 819,200 bytes |
| Data rate | 250 kbit/s |

The service manual’s 808,960-byte figure is DOS-available formatted capacity,
not the byte length of a D81 sector image.

### 6.2 LBA mapping

The normalized 512-byte mapping is:

```text
lba512 = track * 20 + side * 10 + sector - 1

track  = lba512 / 20
within = lba512 mod 20
side   = within / 10
sector = (within mod 10) + 1
```

Required boundary vectors:

| LBA512 | Track | Side | Sector |
| ---: | ---: | ---: | ---: |
| 0 | 0 | 0 | 1 |
| 9 | 0 | 0 | 10 |
| 10 | 0 | 1 | 1 |
| 19 | 0 | 1 | 10 |
| 20 | 1 | 0 | 1 |
| 1,599 | 79 | 1 | 10 |

The current `iec_drive.sv` shifts a 1581 LBA left once because `vdrives` is
configured for 256-byte host blocks. Any prototype attached after that shift
MUST require an even host LBA and `sd_blk_cnt=1`, then use
`lba512 = sd_lba >> 1`. The final WD-aware physical interface SHOULD carry
track/side/sector directly and avoid a round trip through shifted image units.

Out-of-range values MUST return an invalid-geometry result; they MUST NOT wrap,
truncate, or move the head.

### 6.3 Logical DOS blocks

The 1581 DOS presents 80 logical tracks numbered 1–80 and 40 logical
256-byte blocks per track. Two logical blocks occupy each physical sector:

```text
physical_track  = logical_track - 1
physical_side   = 0 when logical_sector < 20, else 1
physical_sector = ((logical_sector mod 20) / 2) + 1
half            = logical_sector mod 2
```

This translation remains the responsibility of the 1581 ROM and its existing
track cache. The new physical controller operates on physical records.

### 6.4 Sector record

A standard record contains:

```text
12 x 00
 3 x missing-clock A1
 1 x FE
 1 x cylinder C
 1 x side H
 1 x sector R
 1 x size N = 02
 2 x ID CRC, high byte first
gap of 4E bytes
12 x 00
 3 x missing-clock A1
 1 x FB (normal) or F8 (deleted)
512 data bytes
 2 x data CRC, high byte first
gap of 4E bytes
```

Readers MUST be gap tolerant. They MUST recognize FE, FB, and F8 only after a
valid missing-clock sync sequence. A coincidental data byte with the same value
is not an address mark.

### 6.5 CRC

The CRC is CRC-16 with polynomial `0x1021` and initial value `0xFFFF`:

- ID CRC covers `A1 A1 A1 FE C H R N`;
- data CRC covers `A1 A1 A1 FB` or `F8` followed by all payload bytes;
- high byte is stored first;
- consuming the two stored CRC bytes through the same generator yields zero.

ID CRC and data CRC MUST remain distinguishable. If RNF is set together with
CRC, the CRC error refers to an ID field. CRC without RNF refers to the data
field.

## 7. Magnetic and timing model

### 7.1 Rotation and data timing

At 300 RPM:

- nominal revolution: 200 ms;
- representative allowed period: 197–203 ms;
- average rotational latency: approximately 100 ms;
- one MFM data bit: 4 µs;
- one clock/data channel interval: 2 µs;
- valid nominal flux-transition gaps: 4, 6, and 8 µs;
- one decoded byte: 32 µs;
- nominal decoded byte-times per revolution: 6,250.

The mechanism is nominally 135 tracks per inch: adjacent cylinder centers are
about 187.5 µm apart, track 0 is at the outer radius, and track 79 is at the
inner radius. A representative effective recorded width is about 0.115 mm.
These physical dimensions are why a step must settle before reading and why a
misdirected or doubled STEP pulse cannot be repaired in a logical LBA layer.

The fixed-rate format has less linear distance per transition on inner tracks.
Those tracks also produce weaker readback because their linear velocity is
lower. Qualification therefore MUST exercise cylinders 78 and 79 repeatedly,
not only easy outer tracks.

### 7.2 Controller clock

The physical controller MUST run from the stable 50 MHz QNICE-side clock
already supplied as `c64_clk_sd_i`. It MUST NOT derive magnetic timing from the
PAL/NTSC/flicker-adjusted C64 main clock.

All constants MUST derive from a single `G_FDC_HZ = 50_000_000` generic or
package constant. The MEGA65 value `0x51` is a 40.5 MHz-specific divisor and
MUST NOT be copied.

Nominal 50 MHz counts:

| Interval | Time | Cycles |
| --- | ---: | ---: |
| controller tick | 20 ns | 1 |
| MFM channel interval | 2 µs | 100 |
| short flux gap | 4 µs | 200 |
| medium flux gap | 6 µs | 300 |
| long flux gap | 8 µs | 400 |
| decoded byte | 32 µs | 1,600 |
| nominal revolution | 200 ms | 10,000,000 |

No raw pulse crosses out of this clock domain. RDATA edge timing, MFM
quantization, index measurement, WDATA pulses, and WGATE are all generated or
captured here.

### 7.3 Qualified mechanism timing

The initial conservative timing contract is:

| Requirement | Bound used by RTL |
| --- | ---: |
| drive-select validity | wait at least 1 µs |
| motor reaches speed | do not declare ready before 505 ms |
| motor/index hard timeout | 1,100 ms |
| DIRECTION setup before STEP | 24 µs |
| STEP active-low width | 4 µs |
| same-direction STEP interval | at least 3 ms |
| direction-reversal STEP interval | at least 4 ms |
| final head settle | at least 18 ms from effective connector STEP trailing edge; implement as final-IOB trailing + profiled `D_step_trailing_max` +18 ms |
| side-change settle | at least 100 µs |
| post-WGATE control guard | at least 700 µs |
| destructive Write Track index-start low filter | 32 µs initial profile; frozen by Q-04 and included in `L_start` |
| index pulse width accepted | 1.5–5 ms nominal range |
| index period qualification target | 197–203 ms for the representative mechanism |
| index period operational plausibility | 150–250 ms; warn outside 180–220 ms |
| RDATA pulse accepted | 0.15–0.8 µs |
| WDATA pulse target | 0.5 µs nominal, always within 0.1–1.1 µs |
| WGATE-to-first-WDATA | nominal first eligible half-cell at 2 µs; an actual transition pulse no later than 8 µs |
| last-WDATA-to-WGATE-off | nominal 2 µs; no later than 8 µs, with the complete pulse inside WGATE |
| qualifying raw WP/change-to-write-clamped | `D_raw_kill_clamp_max <= 2 µs` connector input to both connector WDATA/WGATE inactive, with WDATA no later than WGATE |

The WD 2 ms step-rate code is clamped to the 3 ms mechanism minimum. BUSY
remains set until the real sequencer acknowledges the step and required settle.

### 7.4 Read-data capture

`f_rdata_i` is asynchronous and may be only 150 ns low. The input conditioner
MUST:

1. use a two-stage metastability synchronizer marked `ASYNC_REG`;
2. detect the active-low pulse in the 50 MHz domain;
3. qualify a default of three consecutive low samples before accepting an edge;
4. require a return-high qualification before accepting the next pulse;
5. measure leading-edge-to-leading-edge intervals;
6. prove by randomized phase simulation that every 150–800 ns valid pulse is
   observed exactly once;
7. reject runt/glitch injections without suppressing valid minimum pulses.

The three-sample value is a reviewed default, not a magical invariant. It may
change only with scope evidence and the pulse-phase regression rerun.

INDEX and TRACK0 use two-stage synchronizers plus signal-specific
qualification. Disk change becomes sticky as specified in section 13.
Write-protect/change assertion uses section 13.6's direct asynchronous outer
write-clamp path. Its separate synchronized functional copy is accepted without
an eight-sample delay and stays inhibiting for the operation; only deassertion
is deliberately filtered.

### 7.5 Flux quantization

The decoder MUST accept the representative DD tolerance around nominal 4, 6,
and 8 µs gaps, including ±700 ns read-data timing error and ±2% instantaneous
speed variation. Quantization thresholds MUST be derived and documented in
time units before conversion to cycles.

The decoder MUST:

- reject physically implausible short intervals as noise;
- identify overlong intervals as loss-of-lock rather than invent unlimited
  zero bits;
- reacquire on missing-clock A1 sync;
- expose minimum, maximum, and last measured gap for diagnostics;
- invalidate its partial state on side change, completed step, disk change,
  motor loss, reset, or write activity.

## 8. Target architecture

```text
M2M top_mega65-r*.vhd
  physical f_* pins
        |
        v
CORE/vhdl/mega65.vhd
  direct core-specific pin plumbing
        |
        v
CORE/vhdl/main.vhd
  desired/active source transition manager
  image/physical ownership
  50 MHz physical controller instance
        |
        +---------------- image mode --------------------+
        |                                                |
        v                                                v
existing iec_drive -> c1581 -> fdc1772 -> sd_* -> existing vdrives
        |
        +--------------- physical mode ------------------+
        v
extended fdc1772 WD frontend
  real mechanics/status/result/cancel contract
        |
        v
physical_1581_controller (50 MHz)
  input conditioning
  motor/step/side sequencer
  MFM decoder + CRC
  MFM writer + precomp
  second-pass sector-write buffer / small live CDC queues
  watchdogs and diagnostics
  pin safety firewall
        |
        v
PC-style 3.5-inch mechanism
```

### 8.1 Layer ownership

The WD frontend owns:

- command-register decoding;
- Track, Sector, and Data registers;
- command-specific status bits;
- DRQ/IRQ lifecycle and Lost Data;
- multi-sector sequencing;
- motor-on/spin-up command semantics;
- Type-I update/no-update and verify policy;
- Force Interrupt;
- selection between virtual/image behavior and physical behavior.

The physical controller owns:

- safe physical pin sequencing;
- asynchronous input capture and filtering;
- real index timing and ready inference;
- DIRECTION/STEP timing and acknowledgement;
- side and head-settle guards;
- raw flux interval measurement;
- MFM mark/byte recovery and physical CRC calculation;
- MFM serialization, write pulse generation, and write precompensation;
- physical operation watchdogs;
- immediate WGATE safety clamping;
- diagnostics about the actual medium.

The existing 1581 CPU/ROM owns:

- IEC identity and protocol;
- DOS file system and partitions;
- logical-to-physical block translation;
- its 5,120-byte RAM track cache;
- normal DOS error-channel reporting.

### 8.2 Image and physical mechanics are mutually exclusive

In image mode, `floppy.v` and the current `sd_*` path remain authoritative.

In physical mode:

- `floppy.v` MUST NOT supply ready, index, track zero, sector-header, or
  mechanical timing to the active WD command;
- no `sd_rd` or `sd_wr` request may reach `vdrives`;
- image metadata MUST NOT supply write protect, disk change, or presence;
- a physical completion MUST NOT be accepted by an image transaction and vice
  versa;
- backend/source selection is latched at command start and held until command
  completion, cancellation acknowledgement, and all buffer ownership is
  released.

### 8.3 Selective MEGA65 reuse

Do not instantiate `sdcardio.vhdl` and do not use `internal1581.vhdl`.

The latter filename is misleading for this task. At current MEGA65 revision
`a915893`, `internal1581.vhdl` decodes `$600x` as a WDC FDC near its line 295,
but its FDC read-data path is commented out and returns all ones near lines
333–336. The active native MEGA65 path is board top -> `machine.vhdl` ->
`iomapper.vhdl` -> `sdcardio.vhdl`. Therefore no implementation session should
chase `internal1581.vhdl` as a finished physical-controller shortcut.

Review and adapt the following from
`MEGA65/mega65-core@a9158930665763c592d004c895d52eff4a9eefc3`:

- `mfm_gaps.vhdl`;
- `mfm_quantise_gaps.vhdl`;
- `mfm_gaps_to_bits.vhdl`;
- `mfm_bits_to_bytes.vhdl`;
- `crc1581.vhdl`;
- an MFM-only fork of `mfm_decoder.vhdl`;
- the MFM bit-generation logic of `mfm_bits_to_gaps.vhdl`;
- physical read/write sequencing ideas from
  `sdcardio.vhdl:4023-4305`.

Every adapted helper MUST:

- have an explicit synchronous reset/invalidate input;
- remove unrelated RLL, Amiga, TIB, raw-DMA, F011, debugtools, and report
  dependencies;
- use `G_FDC_HZ`-derived timing;
- recognize F8 deleted data marks;
- expose actual C/H/R/N and distinguish ID/data CRC;
- drive the selected physical side from the latched request, retain observed H
  diagnostically without an H compare for WD1772 Type II/Verify, and reject
  unsupported N without overrunning storage;
- preserve the original LGPLv3 provenance notice.

The project’s GPLv3 and MEGA65’s LGPLv3 are compatible, but copied files remain
identified as adapted LGPL work. Add a provenance table containing upstream
SHA, original path, local path, and substantive changes.

### 8.4 Proposed new local modules

Place core-specific physical-drive RTL under:

```text
CORE/vhdl/physical_1581/
```

Recommended split:

| Module | Responsibility |
| --- | --- |
| `physical_1581_pkg.vhd` | types, result codes, timing conversion helpers |
| `physical_1581_controller.vhd` | top-level operation/mechanics FSM |
| `physical_1581_inputs.vhd` | synchronizers, deglitching, pulse/gap measurement |
| `physical_1581_mfm_decoder.vhd` | DD MFM sync, ID/DAM/data parsing |
| `physical_1581_mfm_encoder.vhd` | MFM bits, missing clocks, fixed WDATA pulses |
| `physical_1581_crc.vhd` | resettable CRC-16 primitive |
| `physical_1581_buffer.vhd` | 512-byte second-pass Write Sector buffer/ownership |
| `physical_1581_sector_fifo.vhd` | byte-slot/data CDC for WD-timed sector writes |
| `physical_1581_track_fifo.vhd` | <=4-entry live Read/Write Track CDC with timestamps |
| `physical_1581_diag_capture.vhd` | optional isolated 8 KiB full-track observation only |
| `physical_1581_safety.vhd` | 50 MHz functional output authorization, writer guard, and first-layer clamps |
| `physical_1581_outer_safety.vhd` | raw-100-MHz QNICE-heartbeat monitor, direct raw-WP/change `outer_write_kill`, and dedicated final IOB/OE asynchronous-safe clamps in `mega65.vhd` |
| `physical_1581_diag.vhd` | read-only counters/status/ILA bundle |

The split may be adjusted during implementation, but input capture, safety,
and diagnostics MUST remain independently testable.

## 9. Clock domains and backend transaction contract

### 9.1 Clock-domain ownership

The physical controller, input filters, flux quantizer, MFM codec, mechanical
timers, safety interlock, and physical diagnostics MUST run continuously from
the stable 50 MHz clock currently presented as `c64_clk_sd_i`. This clock is
called `fdc_clk` below. It MUST NOT be derived from the C64 speed setting,
paused while the on-screen menu is open, or stopped by the 1581 CPU clock
enable.

The WD1772 register model and its DRQ/IRQ interaction with the drive CPU remain
in the existing drive clock domain. Every crossing between that domain and
`fdc_clk` MUST use one of these reviewed mechanisms:

- a toggle or Gray-coded handshake for a stable multi-bit request/result;
- a dual-port RAM with explicit ownership for 512-byte sector data;
- an asynchronous FIFO with Gray-coded pointers for track streaming;
- a two-flop synchronizer followed by qualification for a static control;
- a toggle/counter crossing for an event that may be shorter than the
  destination clock period.

No pulse crossing may rely on coincident clocks. No multi-bit bus may be sampled
merely because a separate `valid` bit was synchronized. CDC attributes and
constraints MUST name the actual synchronizer instances; broad false paths or
wildcards over the complete drive hierarchy are forbidden.

### 9.2 Command ownership

Exactly one media operation may be active. A request is accepted only when the
physical backend reports `idle`, no previous completion is pending, and the
sector buffer or track FIFO has the ownership required by the operation. The
acceptance event latches all request fields. Subsequent WD register writes MUST
NOT mutate an accepted request.

Each request carries:

| Field | Required meaning |
| --- | --- |
| `source_epoch` | 16-bit generation changed on active-source commit or controlled endpoint reset |
| `media_generation` | retained nonzero 16-bit physical-media identity advanced on Physical entry and accepted disk change; zero only in image mode |
| `request_id` | 16-bit monotonic identity for one accepted backend operation; every Restore/Seek step and every Multiple-sector iteration gets a fresh value |
| `operation` | Mechanical Type-I action, read/write sector, read address, or read/write track; cancellation is the separate tagged channel |
| `command_flags` | WD flags including V/E/U/h, multiple, deleted mark, and P precompensation with the exact map below |
| `track` | WD track-register value used for an ID comparison; never an instruction to auto-seek |
| `side` | Selected physical side; observed ID H is diagnostic and is not compared by WD1772 Type II/Verify |
| `sector` | WD sector-register value |
| `size_code` | Expected `N`; standard DOS requests use 2 |
| `direction` | Derived exactly from `OP_STEP_OUT`/`OP_STEP_IN`; no separate flat direction field crosses the ABI |
| `step_rate` | WD-selected delay, subject to the physical minimum in section 7.3 |
| `buffer_generation` | 16-bit ownership identity for collected write data |

`command_flags[15:0]` has this semantic map independent of raw WD opcode
placement: bit 0 V/Verify, bit 1 E/15-ms settle delay, bit 2 U/update Track
register, bit 3 h/disable spin-up, bit 4 M/multiple sector, bit 5 A0/deleted
DAM on write, bit 6 P/disable precompensation, and bits 7–15 reserved zero.
The physical backend consumes only flags relevant to its operation; the WD
front end retains register-update/multiple policy.

The WD frontend retains a parent command context (`wd_command_id`, Busy,
Multiple, current R, accumulated host Lost Data) that never crosses as a
substitute for `request_id`. Restore/Seek issue one uniquely tagged step request
at a time; Multiple sector commands issue one uniquely tagged sector request at
a time and a new buffer generation for each write. Force cancels only the
currently live child request, if any, then terminates the parent. A delayed
prior-child result is stale and cannot mutate the next iteration.

The backend acknowledges acceptance separately from its result event. That event
contains the same source epoch, media generation, and request ID, a result, observed CHRN and
data-mark type where applicable, CRC classifications, byte count, and
diagnostic flags. It is sticky until acknowledged. For writes, it is distinct
from `write_closed` and `guard_done` and may occur at the WD-defined time before
those physical-retirement events. The WD front end MUST ignore an event with any
mismatch against the still-live parent/child's latched source epoch, media
generation, or request ID and count it as stale; it MUST NOT compare retirement
against a newer idle control-generation broadcast or expose a mismatched buffer
to the CPU. In particular, `RES_DISK_CHANGED` from an interrupted request keeps
that request's old media generation.

### 9.3 Operation classes

The four-bit request operation encoding is:

| Code | Operation | Physical effect and completion point |
| ---: | --- | --- |
| `0x0` | `OP_STEP_IN` | one legal inward/higher-cylinder pulse; acknowledge after the effective inter-step recovery, not the final head settle |
| `0x1` | `OP_STEP_OUT` | one legal outward/track-zero pulse; acknowledge after the effective inter-step recovery, not the final head settle |
| `0x2` | `OP_VERIFY_ID` | search valid ID CRC with C equal to Track register; no H compare |
| `0x3` | `OP_READ_SECTOR` | matching C/R, DAM, 512 live bytes, final data CRC |
| `0x4` | `OP_WRITE_SECTOR` | first ID/DRQ collection, second ID, fixed complete write |
| `0x5` | `OP_READ_ADDRESS` | next complete C/H/R/N/CRC record, even when its ID CRC is bad |
| `0x6` | `OP_READ_TRACK` | live bytes from one fast index edge to the next |
| `0x7` | `OP_WRITE_TRACK` | live tokens from one locked, minimum-width-qualified start candidate to fast ending edge/cutoff |
| `0x8..0xF` | reserved | reject as `RES_INVALID_REQUEST` |

CIA motor and side are independent maintained request/ack sidebands, not queued
operations. Motor-off and any side change defer while write/guard is active;
an allowed side change waits 100 us and invalidates read/parser state. WD
Restore repeats `OP_STEP_OUT` and owns its 255-pulse bound. Cancellation uses
only the separate tagged cancel channel; there is no `OP_CANCEL` alias.

Head settling is a maintained timer/state, not an 18 ms delay hidden inside
every one-cylinder operation. Step-request acceptance clears `head_settled`
immediately so no read can race DIR/setup, but the 18 ms timer is loaded/restarted
from the final STEP IOB trailing timestamp plus the board-profile worst
IOB/buffer/cable deassert propagation `D_step_trailing_max`; only after that
conservative connector-edge bound does the 18 ms interval run. No connector
loopback is assumed. A suppressed or
clamped pulse produces no movement acknowledgement and cannot start a false
settle interval. The corresponding `OP_STEP_*` response occurs only after the applicable
same-direction/reversal/WD-rate interval has elapsed; at that point another
step in the same Type-I sequence may be accepted even though the independent
18 ms final-settle timer is still running. The WD frontend stops issuing pulses
at its target/Track-Zero condition and then waits for `head_settled` before
Verify, read eligibility, or Type-I completion. This yields
`distance * effective_step_interval + one final 18 ms`, not
`distance * (effective_step_interval + 18 ms)`.

Likewise, `D_dir_step_relative_max` is the worst amount by which connector DIR
can arrive later than connector STEP relative to their final-IOB events. The
programmed IOB setup is at least `24 us + D_dir_step_relative_max`, proving at
least 24 us at the mechanism. Q-06 freezes both propagation bounds and confirms
the final connector STEP width; RTL comments or package-pin timing alone do not.

At request acceptance also snapshot the prior settle state and absolute expiry.
If ordinary cancellation wins before STEP falls, restore that snapshot exactly:
previously settled returns true, while an older pulse's still-running deadline
continues from its original trailing edge. A suppressed pulse neither invents a
new 18 ms interval nor leaves `head_settled` permanently false.

Each media command latches the acknowledged side at acceptance. A later CIA
side request is held pending until that command retires, then applied/settled;
it never retargets an in-flight ID search. CIA motor-off during search/read
cancels with Not Ready and then turns off; during write it is deferred through
physical close/guard. At final-IOB WGATE assertion, latch
`writer_media_ready` and set `motor_hold_active`. A later PA2-off sets
`motor_off_pending` but cannot revoke that writer's readiness or change actual
MOTOR/SELECT until WGATE closes and the >=700 us guard completes. Then apply the
pending off and drop Ready. Hard-fail may override immediately; raw WP/change
closes the writer but retains the healthy-clock motor hold through guard.
Motor-on may be applied while idle/spinning up.

The physical backend MUST NOT accept an LBA as a substitute for a WD command.
In particular, it MUST NOT seek to `track`, silently correct a missed step, or
turn a sector request into an image-style random access. Type-I commands are
what move the real head.

### 9.4 Sector-buffer ownership

The sector path uses two distinct mechanisms.

Read Sector is streamed at physical byte cadence. Each decoded payload byte is
tagged with source epoch/media generation/request ID and ordinal and crosses through an event/FIFO
bridge to the WD front end, which updates its data register and DRQ immediately.
The following byte is not delayed waiting for CPU service. If the prior DRQ is
still asserted, WD Lost Data behavior applies. CRC arrives only after byte 511;
bytes already presented cannot be retracted, retried, or replaced.

The CRC/backend response crosses independently from the byte FIFO and may
overtake queued payload. Its `byte_count=512` and last ordinal 511 are a
watermark: the WD frontend may capture/hold the response early but cannot
finalize the parent, increment an M=1 Sector register, or issue the next child
until ordinals 0–511 have been dequeued in order and each was presented under
normal DRQ/Lost-Data rules or explicitly dropped for recorded codec overflow.
Final DRQ may remain high when terminal INTRQ asserts, but no byte may surface
after that terminal point. The two on-disk CRC byte-times provide useful margin,
not a CDC-ordering proof; a gap, duplicate, post-watermark byte, or mismatched
identity faults the child.

Read Address uses the same tagged record-byte stream with ordinals 0–5 for the
actual `C,H,R,N,CRC-high,CRC-low` bytes. It does not synthesize those bytes later
from response metadata. Its response watermark is 5 and uses the identical
overtake/drain rule, including when ID CRC is bad.

Write Sector uses a 512-byte dual-clock buffer in this deliberate safety
sequence:

1. `FREE`;
2. `WD_FILLING_AFTER_ID` after the physical controller finds the first matching
   valid ID, waits two DD byte times, and signals the WD front end to raise its
   first DRQ;
3. `READY_TO_WRITE` after exactly 512 WD-timed slots have been filled, with
   zero substitution and Lost Data for a missed later slot;
4. `PHYSICAL_WRITING` while the controller finds the next matching copy and
   serializes the complete buffer;
5. `INVALID` while cancellation/reset is retired.

Missing the first DRQ aborts before any buffer becomes write-authorized.
Ownership changes only on a completed handshake, and every fill has a new
generation. The second matching-ID search, live media generation, WP/change checks,
and buffer generation must all pass before WGATE opens.

“Next matching copy” means the same physical record on its next revolution,
not merely any duplicate C/R. On the first pass the physical controller retains
an occurrence fingerprint: full observed CHRN and stored ID CRC, ordinal of the
complete IDAM after the last qualified index, a 24-bit normalized angular phase
`q_id = elapsed_50mhz / completed_revolution_period`, and the index-sequence
number. `q_id` is finalized when that first-pass revolution ends; rounding error
is bounded to one `fdc_clk` cycle.

The buffer may become ready before that ending edge, but the second pass cannot
authorize against an unfinalized `q_id`. It waits for the first-pass ending
pulse to resolve while the next-revolution minimum epoch qualifier runs. If a
very early second-pass ID completes before full pulse resolution, retain only
its tagged timestamp/fields as a candidate under section 13.3; never delay the
disk, fabricate a period, or open WGATE until both references are valid.

The write pass accepts only the same CHRN/CRC and ordinal at
`first_index_sequence + 1`. Because that revolution's final period is not known
before writing, its permissible elapsed-time window is
`[q_id*P_write_min-E_id, q_id*P_write_max+E_id]`, not a comparison against the
unscaled prior timestamp. `E_id` is initially at most 500 us and always less
than one quarter of measured minimum adjacent-ID separation after fixed-point/
timestamp uncertainty. This admits the same angular occurrence across any
legal ordered 197/200/203-ms speed change without admitting a different ordinal. A different
duplicate is skipped; a missing, ambiguous, phase-wandering, or bad-CRC target
aborts without WGATE. The fingerprint stays local to the active tagged request
and is invalidated by index loss, disk change, reset, or cancel.

This introduces up to one extra revolution versus a discrete WD1772, but
preserves the externally important ordering and timing—ID, two byte times,
first DRQ, service check after nine more byte times, synthetic preamble delay,
then later DRQs—plus Lost Data/status semantics. It prevents a host stall or CDC delay from
opening WGATE on an incomplete sector. This bounded rotational latency is the
only accepted direct-FDC timing deviation for Write Sector; tests and release
documentation state it explicitly.

### 9.5 Record-byte and track-stream FIFOs

Read Sector/Read Address byte events and the “first matching ID found” Write Sector event
are tagged with source/media/request identities and cannot be accepted after cancellation.
The WD front end owns the 32 us DRQ cadence while filling the write buffer:

- missing byte zero aborts before WGATE;
- missing byte 1–511 stores `00`, sets host Lost Data, and continues;
- a stale byte/generation is never written;
- FIFO/CDC capacity failure is Codec Under/Overrun/Internal Fault, not host
  Lost Data.

The sector CDC queues absorb only crossing latency; they MUST NOT hide or move
the CPU’s DRQ deadlines.

Read Track and Write Track use a small elastic asynchronous queue solely for
CDC latency. The functional WD queue is at most four byte/token entries and
MUST carry physical timestamps/ordinals so occupancy cannot hide a missed
operation-specific service deadline. It MUST NOT capture a revolution and replay it or
prefill a revolution before writing.

An assertion compares successive event timestamps and WD DRQ-service time even
when two or more entries coexist: an entry older than its WD deadline sets Lost
Data/overwrite immediately rather than being replayed later as valid data.

The first special case is the first Write Track token. Its CPU service deadline is
the explicit 96 us execution-start deadline after spin-up/E; once serviced, exactly one tagged
token may reside in an `ARMED_FIRST_TOKEN` slot while waiting up to the bounded
starting-index search. Its ordinary 23.5 us consumption-age check is disabled
until `index_start_min_qualified`, when the serializer consumes it as WGATE
opens and normal per-token deadlines begin. A cancel, source/media/request mismatch,
write-lock loss, or start-index timeout invalidates it; it can never roll into a
later command/revolution. No read byte receives this exemption.

The second special case is the DRQ raised immediately after a Write Track F7
token transfers from DR to DSR. WD1772-02 sets that DRQ *before* interpreting
F7, then emits CRC high and low for two magnetic byte-times before the next DSR
transfer. That early DRQ therefore remains serviceable through the expansion:
its binding Lost Data deadline is 55.5 us from assertion (ordinary 23.5 us plus
one extra 32 us byte-time), inclusive at the boundary, and the next token is
consumed at the 64 us magnetic boundary. Queue age logic carries an explicit
`after_f7` timing class; it MUST NOT apply the ordinary 23.5 us rule or postpone
DRQ until CRC-low.

An optional 8,192-entry diagnostic capture may record a whole track out of
band. It has no path to the WD Data Register, DRQ, serializer, buffer ownership,
or command completion and is removed or disabled in resource-constrained
production builds.

For Read Track, entries contain an eight-bit decoded byte plus decoder/lock
flags. Lossless tagged start/end index markers use the separate marker
handshake in section 17.3, because an ending edge can occur after the final byte
and must not be invented as a data byte. Missing-clock
A1/C2 patterns are returned as their byte values; the physical decoder uses the
clock pattern internally to find marks. The stream begins at the fast
synchronized index edge and ends at the next such edge. `ready=0` never stops
rotating media: the byte is overwritten/dropped according to WD Lost Data
semantics while physical parsing continues. No synthetic padding may extend or
shorten the revolution.

For Write Track, entries contain the byte/token written by the 1581 CPU. Values
F5, F6, and F7 retain the WD formatting meanings specified in section 14.6;
they are not ordinary data bytes. At each consumption deadline the WD front end
detects a missed CPU DRQ, sets host Lost Data, and supplies an explicit ordinary
`00` token so writing continues. If the physical queue still underflows or
overflows despite that contract, it is Codec Under/Overrun/Internal Fault, not
host Lost Data.

Only the first token may be queued before the starting index. Subsequent DRQs
are raised when the current DR transfers to DSR. F7 consumes one host token but
emits two magnetic byte-times: the next DRQ rises as CRC-high begins, remains
serviceable while both CRC bytes are emitted, and the loaded next token does not
transfer to DSR until CRC-low completes. `phys_track_tx_last` is diagnostic host-stream metadata only; it
never terminates WGATE, which ends only at fast index or the safety cutoff.

Functional queue depth and thresholds MUST be derived from a
worst-case proof covering the current 31.527778 MHz and 31.448993 MHz main
clocks, optional future 32.727264 MHz NTSC mode, the 50 MHz physical clock, CPU
stalls, DRQ deadline, and CDC pointer latency. 40.5 MHz is a native-MEGA65
reference frequency, not a C64MEGA65 drive/CPU mode. Simulation of average
throughput is not a substitute for that proof.

### 9.6 Backend-result vocabulary and physical retirement

The five-bit backend result encoding is:

| Code | Result | Meaning |
| ---: | --- | --- |
| `0x00` | `RES_OK` | WD-visible data/CRC phase succeeded; a writer may still owe documented FF close and guard retirement |
| `0x01` | `RES_NOT_READY` | media/spindle qualification absent |
| `0x02` | `RES_NO_INDEX` | required index absent/implausible at watchdog |
| `0x03` | `RES_TRACK0_FAILED` | bounded step/Restore could not establish track zero |
| `0x04` | `RES_RECORD_NOT_FOUND` | no matching valid ID in search budget |
| `0x05` | `RES_ID_CRC_ERROR` | bad-ID outcome; Read Address may still carry its six bytes |
| `0x06` | `RES_MISSING_DAM` | matching IDs occurred but no DAM before overall expiry |
| `0x07` | `RES_DATA_CRC_ERROR` | streamed complete data field ended with bad CRC |
| `0x08` | `RES_UNSUPPORTED_SIZE` | matching record N is not supported value 2 |
| `0x09` | `RES_WRITE_PROTECTED` | WP prevented/aborted authorization |
| `0x0A` | `RES_DISK_CHANGED` | media generation changed during request |
| `0x0B` | `RES_CODEC_OVERRUN` | physical decoder/elastic queue capacity failure |
| `0x0C` | `RES_CODEC_UNDERRUN` | serializer lacked data despite fulfilled WD contract |
| `0x0D` | `RES_CANCELLED` | tagged physical request retired by cancel |
| `0x0E` | `RES_INVALID_REQUEST` | reserved op/illegal geometry/inconsistent fields |
| `0x0F` | `RES_INTERNAL_FAULT` | safety invariant, impossible state, or unclassified watchdog |
| `0x10` | `RES_UNSAFE_WRITE_TIMING` | write-rate lock absent, remaining revolution too short, or profiled start/capacity envelope cannot be met; WGATE never opened |
| `0x11..0x1F` | reserved | never generated; receiver treats as internal fault |

The 16 result-flag bits are, low to high: `saw_valid_id`, `saw_bad_id_crc`,
`saw_dam`, `deleted_dam`, `data_crc_bad`, `index_seen`, `disk_changed`,
`unsupported_size`, `codec_overrun`, `codec_underrun`, `aborted`,
`watchdog_expired`, `write_closed`, `guard_active`,
`fast_index_later_rejected`, and `internal_fault`. Actual C/H/R/N and
revolution/byte counts are separate fields. Host DRQ Lost Data and formatter
host underflow belong solely to the WD front end and are not backend results.

Every response also carries `result_detail[6:0]`, zero unless a listed result
needs a stable subcause. For `RES_UNSAFE_WRITE_TIMING`, exact values are `0x01`
rate/profile lock absent, `0x02` remaining sector revolution too short, `0x03`
Write Track start/capacity inequality failed, and `0x04` ROM format trace exceeds
`N_format_required_max`; `0x05..0x7F` are reserved/internal fault. Software must
key primary behavior from `result`; detail is diagnostic and never authorizes a
write.

### 9.7 Cancellation and bounded completion

A Force Interrupt, source transition, soft reset, or internal watchdog starts
a cancellation handshake with the active source/media/request identities. Three events are
separate: WD-visible termination (`Busy/INTRQ`), physical write closed, and
`mechanics_reusable` after guard. Cancellation MUST:

- prevent any future read buffer or stream entry from becoming CPU-visible;
- stop searching or reading at a byte-safe boundary;
- if write gate is inactive and no STEP pulse has crossed its falling edge,
  retire promptly;
- if WGATE is active for Force/source/soft reset, finish at most the current
  2 us MFM channel interval, force WDATA high, and close WGATE; do not wait a
  whole 32 us byte;
- raw WP/change kill or hard reset clamps WGATE and WDATA simultaneously without
  waiting for a bit; normal track end closes within three `fdc_clk` cycles of
  `index_edge_fast` plus I/O delay;
- acknowledge physical write-close separately, then enforce the 700 us guard
  before asserting `mechanics_reusable`;
- for Force/source/soft-reset/ordinary-fault with a healthy safety clock before
  final-IOB STEP falling, suppress the pulse and report no movement. Once STEP
  has fallen, the independent one-shot—not the cancelled FSM—finishes exactly
  the full 4 us pulse, emits no second pulse, keeps DIR stable, and records one
  physical movement. If prior position/direction state was valid, update it once
  on the effective trailing edge; otherwise invalidate it. WD-visible Force may
  retire earlier, but physical cancellation/source reset waits the trailing edge,
  required inter-step recovery, and final 18 ms settle;
- hard-fail/hard reset, asynchronous clamp, or any pulse whose measured connector
  width is outside the qualified bound may truncate STEP and MUST invalidate
  `head_position_valid`, set `restore_required`, and prevent media/destructive
  access until Restore;
- leave motor, side, direction, and step in the resulting defined states;
- produce one terminal acknowledgement even if the media disappears.

The guard is finite and connector-relative, not an unspecified delay. Let
`t_iob_close` be the raw-100-MHz timestamp at which the dedicated final IOB
register first drives WGATE inactive, `D_wgate_deassert_max` the qualified
maximum from that transition until connector WGATE is inactive, and
`D_close_ack_max` the qualified maximum for its tagged close indication to
reach `fdc_clk`. Every capable board profile MUST prove
`D_wgate_deassert_max <= 10 us` and `D_close_ack_max <= 4 fdc_clk cycles`.
After the synchronized close indication, run a non-reloadable
`ceil((D_wgate_deassert_max + 700 us) * G_FDC_HZ)`-cycle timer. Assert
`guard_done` on the first following `fdc_clk` edge. This guarantees at least
700 us after connector deassertion and, with the profile caps, retires the
ordinary guard no later than 710.10 us after `t_iob_close` (10 us propagation,
80 ns close-ack bound, and one 20 ns terminal cycle). A hard fail may clamp and
invalidate the endpoint instead; it is not ordinary guard completion. Q-09
freezes the two delay bounds, and simulation proves that raw input chatter,
Force, reset requests, pause, and repeated close indications cannot reload the
timer.

Every non-track search has both a revolution-count limit and an absolute-time
watchdog. Every track command has an ending-index watchdog. Every mechanical
wait has an absolute bound. The aggregate bounds are specified in section 11.
There is no state in which missing index or a stuck pin can leave Busy, write
gate, or a mode transition pending forever.

## 10. WD1772-visible behavior

### 10.1 General command rules

`fdc1772.v` remains the WD register-level authority, but its current virtual
mechanics and successful stubs are not authoritative in physical mode.

The physical-mode behavior MUST follow the WD1772-02 MFM command model:

- a non-Force command written while Busy is set is ignored;
- Force Interrupt may be written while Busy;
- accepting a normal command sets Busy and initializes the command-relevant
  status bits;
- reading the data register clears DRQ for a read, and writing it clears DRQ
  for a write;
- reading status clears IRQ according to existing WD semantics, not Busy;
- terminal parent-command completion clears Busy and asserts IRQ exactly once;
  an intermediate successful Multiple-sector child result does neither;
- the backend completion is not itself exposed as IRQ until the front end has
  finalized status and data ownership;
- read completion follows the physical end/CRC and never waits for CPU service
  of the final DRQ; DRQ and INTRQ may be high together;
- write WD-done, physical-close, and guard-done events follow sections 9.7 and
  10.6 rather than one overloaded completion bit;
- a new command may not consume stale result, DRQ, FIFO, or CRC state.

The existing `MODEL=2` choice remains WD1772. Do not replace it with F011
auto-seek, retry, cache, or error behavior.

The internal WD Motor-On latch obeys these rules independently of CIA PA2:

- accepting any non-Force Type-I/II/III command sets MO high;
- if that command has `h=0` and MO was previously low, wait six qualified index
  leading edges before execution;
- if `h=1`, set MO but bypass only the six-edge wait; if MO was already high,
  execute without a new spin-up sequence regardless of h;
- an absolute spin watchdog starts when that accepted command enters the
  spin-up phase; it never restarts on motor/index activity and is derived as
  `505 ms + 6*P_read_max + W_index_max + CDC/filter margin`. With
  `P_read_max=250 ms`, `W_index_max=5 ms`, and 40 ms margin, the binding initial
  value is 2.050 s. A CIA motor request arriving later does not restart it;
- after command completion, the first qualified index edge establishes the idle
  phase reference; MO clears only after nine subsequent complete qualified
  inter-index intervals with no accepted command (ten edges including the
  reference);
- if CIA PA2 turns the physical motor off first, no index arrives and literal
  MO remains set until another defined WD/reset event; it never keeps the
  physical motor running.

For Type II/III, `E=1` applies one 15 ms delay at command start before the first
search/index action. It is not repeated for Write Sector’s second-ID safety
pass. After a Type-I physical step with V, the WD 15 ms settle is raised to the
mechanism-safe 18 ms.

Programmed-I/O visibility follows WD1772-02 MFM delays: after a Command write,
Busy is safely read after 24 us, status bits 1–7 after 32 us, and reading the
same register just written waits 16 us. Tests at one cycle before/at/after these
boundaries are normative; this specification does not waive them for direct-
FDC diagnostics.

Every committed drive-local WD reset—cold, hard endpoint reset, source/ROM
transaction reset, or accepted soft-drive reset—produces this deterministic
functional state. Hard reset may reach it asynchronously; release is
synchronized. Image and Physical use the same values so source selection cannot
expose stale/X state:

| WD state | Required post-reset value |
| --- | --- |
| Command/status class | command latch `00`; Type-I status class |
| Busy, DRQ, normal INTRQ | 0, 0, 0 |
| immediate-Force latch, D8/D0 clear arm, index-IRQ arm | all 0 |
| RNF/Seek Error, CRC Error, Lost Data, deleted mark | all 0 |
| MO, six-edge counter, spin-up-complete, idle reference/count | all 0 |
| Track register | `00`, preserving the existing image-mode reset contract |
| Sector register | `00`, preserving the existing image-mode reset contract |
| Data register readback and input staging | deterministic `00` (the discrete part does not promise useful reset data; the FPGA must not expose X/stale bytes) |
| multiple/E/V/U/h/P/A0 and active command class | inactive/zero |
| source/media/request/buffer identities | invalid zero until the post-reset manager establishes nonzero generations |
| sector/track FIFO, buffer ownership, pending result/cancel | empty/invalid/no valid toggle |
| step/seek counters, target, pulse, `last_direction` | zero/outward storage value, but `last_direction_valid=0` |
| head-position estimate/contract | estimate zero diagnostic only, `head_position_valid=0`, `restore_required=1` until explicit Restore |
| head-settle and parser/CRC state | invalid/not ready until mechanics and a new operation qualify them |

Live Type-I Track Zero, Index, and Write Protect inputs are not stale reset
latches: after synchronized reset release, Status reads show their conditioned
levels with MO/spin/error/Busy fields above. Diagnostics may retain historical
counters across a soft drive reset, but no retained diagnostic bit may feed
functional status. Existing RTL omissions such as unreset `data_out` or
`step_dir` are defects to fix, not inherited behavior.

### 10.2 Status register

The status register has command-dependent meanings and MUST be latched from the
active command class:

| Bit | Type I meaning | Type II/III meaning |
| --- | --- | --- |
| 7 | Motor On output state | Motor On output state |
| 6 | Live/updated Write Protect | Write Protect on write commands; zero/not used on reads |
| 5 | Spin-up complete | Read Sector only: 0 normal FB, 1 deleted F8; forced 0 for writes, Read Address, and Read Track |
| 4 | Seek error | Record not found |
| 3 | CRC error | ID CRC if RNF is also set; otherwise data CRC |
| 2 | Track Zero input | Lost Data |
| 1 | Index input | DRQ |
| 0 | Busy | Busy |

Status bit 7 in this WD1772 model is Motor On, not Not Ready. Not-ready media
still terminates commands with the command-appropriate failure and diagnostics;
software detects the practical condition through failed operations. The CIA
ready input remains separately accurate.

With `EXT_MOTOR(1)`, this bit reflects the WD front end’s internal Motor On
latch/spin-up semantic, not the CIA PA2-driven physical motor pin. Diagnostics
expose both values; neither is substituted for the other in status.

Rules that commonly get lost in an abstraction MUST be retained:

- Type-I Track Zero and Index are live conditioned inputs when status is read.
  Status bit 2 is one when the active-low physical Track-Zero input is asserted
  (head at cylinder 0), and zero away from track 0; bit 1 is one during index.
- Spin-up-complete is set only after six qualified index leading edges (the
  first establishes phase, followed by five complete inter-index periods) when
  the command did not bypass spin-up; the implementation may also require the
  stricter ready qualification in section 13.
- Deleted-record status is derived from the actual F8 DAM on Read Sector only.
  It is forced zero on Write Sector/Track, Read Address, and Read Track; a
  deleted-write request does not set status bit 5.
- Write Protect is sampled before every write authorization and remains a hard
  safety input throughout the write.
- CRC status is never hardwired to zero.
- RNF plus CRC distinguishes unusable ID fields from a missing data CRC error.
- Lost Data remains set if a later physical operation otherwise succeeds.

The WD-visible mapping from section 9.6 is:

| Physical result | WD effect |
| --- | --- |
| `RES_OK` | No error; record-type bit reflects actual DAM only for Read Sector and is zero for other Type II/III commands |
| `RES_NOT_READY`, `RES_NO_INDEX` | Seek Error for Type I; RNF for Type II/III |
| `RES_RECORD_NOT_FOUND` | Seek Error for Type-I Verify; RNF for record commands |
| `RES_MISSING_DAM` | RNF |
| `RES_ID_CRC_ERROR` | Type-II search exhaustion: RNF + CRC; Type-I Verify exhaustion: Seek Error + CRC; Read Address: transfer encountered six bytes and set CRC without inventing RNF |
| `RES_DATA_CRC_ERROR` | CRC Error without RNF |
| `RES_TRACK0_FAILED` | Seek Error for Type I only under section 10.4’s V rule |
| `RES_WRITE_PROTECTED` | Write Protect; no write gate authorization |
| `RES_DISK_CHANGED` | Seek Error for Type I or RNF for Type II/III; never present a new stale byte |
| `RES_CANCELLED` | physical cancellation retires; Force Interrupt status follows section 10.10 |
| `RES_UNSUPPORTED_SIZE` | RNF and explicit diagnostic; never overrun storage |
| `RES_CODEC_OVERRUN`, `RES_CODEC_UNDERRUN`, `RES_INVALID_REQUEST`, `RES_INTERNAL_FAULT` | RNF/Seek Error appropriate to command plus internal diagnostic; never relabel as host Lost Data |
| `RES_UNSAFE_WRITE_TIMING` | RNF for Write Sector/Track plus explicit unsafe-write-timing diagnostic (rate/window/capacity subcause); no WGATE authorization |

The WD front end independently ORs its sticky host Lost Data into status bit 2
for Type II/III; no physical result may clear or synthesize that condition.

WD1772 has no dedicated No Index status. Mapping `RES_NO_INDEX` to command-
class Seek Error/RNF is a deliberate bounded-availability deviation, not a
native status bit. Stock/JiffyDOS error-channel tests must confirm the resulting
user-visible error is stable and does not report success.

### 10.3 DRQ deadlines

At 250 kbit/s MFM, one decoded byte occupies 32 us. The original WD timing
allows less than a full byte interval for host service; verification MUST use a
23.5 us worst-case DRQ-service deadline for read bytes and continuing write
bytes except the explicit first-Write-Track and post-F7 cases below.

- On read commands, failing to read the prior data byte before replacement sets
  Lost Data. The physical stream continues, and the newer byte is delivered as
  the WD model specifies.
- On Write Sector, wait two DD byte times after matching ID CRC, raise first
  DRQ, and check service after nine more byte times. Failure at that check
  aborts before WGATE and sets Lost Data. If serviced, reproduce the remainder
  of the 22-byte gap plus 12-zero/three-A1/DAM timing before raising the second
  DRQ; later buffer-fill slots run at 32 us cadence before the second-ID pass.
- On Write Track, the initial request follows section 10.9’s 96 us
  (three decoded byte-time) service rule and armed-start-index exception.
- For a continuing Write Track F7, transfer F7 to DSR, assert the next DRQ, then
  emit CRC high/low. Service one cycle before/at/after the inclusive 55.5 us
  special deadline; consume the next DSR token only after the 64 us expansion.
  Late service sets Lost Data and supplies ordinary `00` at that next transfer.
- After writing begins, a missed byte is replaced by `00`, Lost Data is set,
  and the operation reaches a safe ending boundary.
- Sector buffering may move the physical rotational phase of a write to the
  next matching sector, but it MUST NOT relax the WD-facing DRQ deadline.

The testbench MUST exercise service immediately before, at, and immediately
after the deadline; a test that services every DRQ promptly proves nothing
about Lost Data.

### 10.4 Type-I commands: Restore, Seek, Step, Step In, Step Out

Each physical step is an acknowledged one-cylinder action. Direction setup,
STEP width, and the inter-step response interval use section 7.3. The
conservative final-IOB trailing + `D_step_trailing_max` reference restarts the
independent 18 ms `head_settled` timer, but the per-step acknowledgement does
not wait that timer out. Only the final step of the Type-I sequence is followed
by one full settle before Verify/read or command completion.

- Restore sets outward direction and emits one host STEP pulse at a time until
  conditioned Track Zero is active. It sets the WD track register to zero on
  success. It MUST stop after 255 pulses or the derived >=3.2 s stepping
  watchdog, whichever occurs first; only that exhaustion returns backend
  `RES_TRACK0_FAILED`. Strict WD status sets Seek Error for exhaustion only
  when V=1; V=0 still records the diagnostic/result but leaves S4 clear.
- Seek compares the data register target with the WD track register, chooses a
  direction, and emits one acknowledged pulse per register increment/decrement
  until equal. It does not infer physical position from an LBA. Its absolute
  watchdog is `requested_distance * effective_step_interval + 18 ms + margin`,
  capped no lower than 3.2 s for a 255-step/12-ms case. Physical target >79 is
  rejected as section 13.4’s explicit safety deviation.
- Before **every** outward Seek child, sample conditioned Track Zero. If it is
  already asserted, issue no pulse—even when a corrupted WD Track register says
  255 more decrements are required. Unless the WD registers were already at the
  requested target, terminate with Seek Error and diagnostic
  `outward_seek_blocked_at_track0`; leave the Track register at its last
  acknowledged software value rather than silently forcing it to zero. This
  rule also stops an outward Seek immediately when Track Zero becomes active
  earlier than the register target. Only an explicitly commanded single Step
  Out may use section 13.4's one-pulse disk-change-clear exception; Seek cannot.
- Step repeats the last latched direction; Step In selects higher cylinders;
  Step Out selects track zero. The Update flag alone controls whether the WD
  track register changes. Reset clears `last_direction_valid`; a bare Step while
  it is false terminates with Seek Error and emits no pulse. Restore establishes
  outward direction even when Track Zero makes a pulse unnecessary; a
  non-zero-distance Seek establishes its chosen direction; Step In/Out establish
  their named direction. A zero-distance Seek does not invent one.
- The Verify flag waits the WD head-settle interval and searches for a valid ID
  whose C field equals the WD track register; selected side chooses the surface
  but H is not compared. Failure after the search budget sets Seek Error; if
  only matching bad-ID-CRC candidates occurred, set CRC Error as well.
- A step command with motor spin-up enabled waits for the required ready/index
  qualification before verification. A disabled spin-up flag skips the six-
  index-edge WD sequence but never bypasses pin-level safety or impossible input
  checks.

The controller maintains a diagnostic head estimate, initialized only by a
successful Restore and updated by acknowledged steps. That estimate MUST NOT
override Track Zero, auto-correct software-visible track state, or be used to
teleport the mechanism.

### 10.5 Type-II Read Sector

Read Sector performs this sequence:

1. Require `read_path_valid`, no unacknowledged disk change, and qualified
   index timing.
2. Scan ID address marks, accepting a candidate only when its ID CRC is valid,
   `C = track register`, and `R = sector register`. Do not compare H. If that
   candidate has `N != 2`, return Unsupported Size/RNF for this standard-1581
   specialization.
3. After the matching ID CRC, require an FB or F8 DAM within 43 DD byte times
   (1.376 ms). Seeing another ID or reaching that local timeout records
   `saw_missing_dam`, returns to ID search, and continues within the overall
   five-index/1.300 s budget. Only budget exhaustion becomes terminal
   Missing DAM/RNF.
4. Capture exactly 512 bytes plus the two on-disk CRC bytes, while calculating
   CRC over `A1 A1 A1`, DAM, and data. As each payload byte is decoded, present
   it immediately through the tagged CDC event and WD DRQ; do not wait for the
   rest of the sector or its CRC.
5. If a prior byte was not serviced at the next physical byte event, set Lost
   Data and continue exactly as the WD front end defines; buffering cannot
   stretch the 32 us cadence.
6. After the final data and stored CRC bytes, set CRC Error if needed and set
   bit 5 for F8 independently. Bytes already transferred remain visible once;
   never retry or replace the record.

The search ends when five qualified index leading edges have passed since
search start. A 1.300 s absolute watchdog is the secondary limit. It never
restarts on a raw, rejected, or qualified edge. If matching IDs were
seen only with bad ID CRC, return ID CRC Error; if no matching candidate was
seen, return Record Not Found.

For the Multiple flag, increment only the sector register R after each
successfully delivered child sector and repeat with a fresh backend request ID.
An intermediate child `RES_OK` leaves parent Busy set and INTRQ clear; final DRQ
may remain pending under normal Lost-Data rules while the next ID search starts.
The first CRC/RNF/other error or Force is terminal and produces the one parent
completion/INTRQ. R does not wrap side or cylinder. After sector 10 on a
standard track, the subsequent R child fails with Record Not Found unless
software uses Force Interrupt first.

### 10.6 Type-II Write Sector

Write Sector MUST NOT modify media until all of these are true:

- live and conditioned write protect both indicate writable;
- no disk-change event is pending;
- `media_ready`, qualified index health, and settled head/selected side;
- `head_position_valid` with no `restore_required`/position fault;
- current-generation `index_write_locked`; broad read-plausible RPM never
  authorizes a fixed-rate sector write;
- an initial valid matching ID/CRC was found before the first DRQ;
- the first DRQ was serviced by the check nine DD byte times after it asserted;
- exactly 512 WD-timed slots produced a complete current-generation buffer;
- a second valid matching ID/CRC was found after the buffer became complete;
- the second ID's remaining-revolution proof shows the complete splice can
  close before `P_write_min`; and
- the independent safety interlock authorizes the exact request.

After required spin-up/E and before the first backend ID search or DRQ,
Write Sector requires current-generation `index_write_locked` and snapshots the
three-period/profile generation for this child; broad-readable but unlocked
speed returns `RES_UNSAFE_WRITE_TIMING/detail=0x01` without DRQ/search. It also
samples live and conditioned WP plus pending disk change. Protected
media terminates with Write Protect; pending change terminates Disk Changed/RNF.
Neither case emits DRQ or a physical search request. Every later authorization
point repeats those checks, and the asynchronous clamp remains authoritative
after WGATE.

The complete sequence is:

1. Search for the first matching valid ID within the normal budget.
2. Wait two DD byte times after that ID CRC, raise first DRQ, then check it nine
   byte times later. If not serviced, abort with Lost Data and never open
   WGATE.
3. If serviced, reproduce the rest of the 22-byte post-ID gap and the timing of
   12 zero bytes, three A1 bytes, and the DAM. At the point a real WD transfers
   byte zero from DR to DSR, raise the second DRQ. Collect bytes 1–511 at 32 us
   cadence; a missed later DRQ stores `00` and leaves Lost Data set.
   Cancellation invalidates the buffer.
4. Search for the fingerprinted same occurrence on exactly its next revolution,
   with a fresh five-index-edge/1.300 s physical-search bound. Check CHRN, stored
   ID CRC, ordinal and scaled angular-phase window, source/media/buffer identities, WP,
   change, side, and readiness. Ignore a different C/R duplicate and abort on
   absence or ambiguity. The current revolution origin must first be established
   by `index_sector_epoch_min_qualified` as section 13.3 defines; a raw fast edge
   alone can never rebase this calculation or authorize the ID.
5. Before WGATE, let `T_idcrc2` be elapsed time from that immutable minimum-
   qualified original edge timestamp to second-pass ID-CRC completion and prove:

   ```text
   T_idcrc2 + 22*32 us + L_sector_open + L_data_start_max
     + 531*32 us + L_sector_close_max + M_sector_index <= P_write_min
   ```

   `L_sector_open` is worst scheduled-open to connector-WGATE-active latency and
   `L_data_start_max` is the profiled <=8 us gate-to-byte-origin envelope.
   `L_sector_close_max` includes the planned last-WDATA trailing envelope and
   connector deassertion propagation (distinct emergency `L_close` may be
   shorter). Initial `M_sector_index >= 100 us`. Failure returns
   `RES_UNSAFE_WRITE_TIMING/detail=0x02`/RNF before WGATE and leaves the complete
   track unchanged. This check is required even for a valid matching late-track ID.
6. Count 22 DD byte times from that ID CRC, assert WGATE, and write 12 `00`,
   three missing-clock A1, FB for normal or F8 for deleted, all 512 buffered
   bytes, and generated CRC high then low. The serializer arms its first
   half-cell at WGATE +2 us and an actual WDATA transition must occur by +8 us;
   otherwise the independent writer watchdog closes/faults. Let `T` be
   completion of CRC-low.
7. From `T`, serialize exactly one ordinary MFM `FF` through approximately
   `T + 32 us`, then close WGATE. For a terminal single-sector success,
   independently clear WD Busy/assert INTRQ at `T + 24 us`; INTRQ may therefore
   coexist briefly with final-FF serialization and active WGATE. For an
   intermediate successful M=1 child, accept its unique tagged `RES_OK` at the
   same time but keep parent Busy set and INTRQ clear.
8. From WGATE close, keep `phys_write_critical` asserted and refuse motor/select/side/step/density
   changes or another physical operation until at least 700 us after WGATE is
   high.

WD-visible completion, physical write-close, and mechanics reuse are three
distinct handshakes/timestamps in the ABI. A newly accepted WD command may wait
only for the remainder of the finite guard described in section 9.7 before
issuing any physical action; no command, pin input, or CDC retry reloads that
guard.

After Write Sector WGATE opens, every distinct `index_edge_fast` immediately
forces WDATA inactive no later than WGATE, faults the splice, and starts guard;
it is never ignored until retrospective period qualification. Normally the
remaining-revolution proof makes this impossible. A false edge may truncate a
sector, but ignoring a real edge could overwrite the next revolution and is the
less safe failure.

The eight-microsecond interval from WD-done at `T+24 us` to planned FF end/
WGATE close at about `T+32 us` has explicit arbitration:

1. Before the backend-result event commits, raw WP/change or an unexpected
   distinct fast index wins and closes the writer. WP/change returns its
   applicable error; fast index returns one `RES_INTERNAL_FAULT` child response
   with index/tail-violation diagnostic. Hard-fail closes and invalidates the
   endpoint without promising a response. An exactly coincident Force wins over
   normal completion and follows section 10.10.
2. Once the child result has committed, its payload and one-response count are
   immutable even while `phys_write_critical` remains. Parent status
   finalization is immutable only when that child is terminal; M=1 intermediate
   success leaves the parent active.
3. A later raw WP/change/unexpected-fast-index/hard-fail still clamps the old tagged writer and records
   `late_write_safety_fault`, old identities, phase, and possible media damage;
   it produces no second child response and cannot rewrite the committed child.
   For terminal M=0, the separate late-fault event is diagnostic/live-status
   only and cannot create another parent IRQ. For intermediate M=1, the same
   lossless event terminally fails the still-Busy parent, prevents allocation of
   the next child, sets the applicable WP/change/internal status, clears Busy,
   and asserts the parent's one INTRQ. Hard-fail may instead invalidate the
   endpoint without an IRQ guarantee. Live WP/change inputs remain live as
   section 10.2 requires.
4. Any D0/D4/D8/DC Force during the tail targets the lingering old physical writer
   for close/guard and never retracts/duplicates the child result. After terminal
   M=0 it uses idle Force semantics. During intermediate M=1 it uses active-
   command semantics: terminates the Busy parent, preserves active status per
   section 10.10, D0 creates no new IRQ, D4 arms qualified-index IRQ, D8 creates
   immediate IRQ, DC creates immediate and arms index IRQ, and no next child is
   allocated.
5. After a terminal M=0 result, a normal new Command write clears normal INTRQ
   and may latch new WD state, but it does not cancel the old final FF; its
   physical request waits for old `phys_write_closed`/`phys_guard_done`. During
   an intermediate M=1 tail, parent Busy remains set and the new non-Force
   command is ignored.

At each `fdc_clk` boundary the priority is hard/raw/fast-index safety, Force, scheduled
WD-done, ordinary new-command admission, then serializer progress. Tests sweep
every clock and sub-clock input phase from `T+23 us` through `T+33 us` and hold
`phys_rsp_ready` low to prove the committed response payload cannot mutate.

The second-ID pass is the deliberate safety latency documented in section 9.4.
It MUST NOT raise another set of CPU DRQs or accidentally select a different
sector occurrence, copy, or generation.

Write Sector command bit 1 is P: `P=0` enables WD write precompensation and
`P=1` disables it. The latched request carries this bit through both ID passes;
the second pass cannot change its setting.

Each physical search pass has five index leading edges plus the 1.300 s
watchdog. A transition to
write-protected, disk changed, reset, or fault before write-gate assertion
aborts without writing. If raw write protect asserts during a write, the safety
interlock deasserts write gate immediately; the command reports Write Protect
and Internal Fault diagnostics because the sector may be damaged. A read-back
verify is not implicit unless the WD command defines it; qualification tests
perform an independent read-back.

Multiple-sector write repeats the WD-facing buffer/DRQ and physical search for
each sector. On each intermediate child success, increment parent Sector R
exactly once, wait for that child's final FF, `phys_write_closed`, and
`phys_guard_done`, allocate a fresh request ID and buffer generation, then begin
the next first-ID/DRQ collection. Busy stays set and INTRQ stays clear. The first
failure/RNF/CRC/WP/Force/error is terminal and finalizes parent status/INTRQ;
M=1 has no intermediate success IRQ. Buffer/request generations MUST make it
impossible for sector N data or delayed result to affect sector N+1.

### 10.7 Read Address

Read Address waits for the next complete ID address mark and transfers exactly
six bytes through DRQ:

```text
C, H, R, N, CRC-high, CRC-low
```

The CRC bytes are the actual bytes read from disk. The command does not filter
for the track or sector registers. On completion it writes returned cylinder C
into the WD Sector register, as specified by the WD1772. If that encountered ID
has a bad CRC, its six actual bytes are still transferred and CRC Error is set;
Read Address does not silently skip it for a later clean ID. If no complete ID
is encountered within the search budget, report RNF (plus the retained ID-CRC
diagnostic only if malformed/bad candidates were observed).

All six bytes use `phys_record_rx_*` at physical byte cadence with ordinals 0–5;
the terminal response carries watermark 5 and cannot synthesize, reorder, or
overtake their WD presentation as section 9.4 specifies.

### 10.8 Read Track

Read Track begins on `index_edge_fast` and ends on the next such edge; completed
pulse qualification determines status retrospectively. It transfers every decoded byte in physical order: gaps, sync
bytes, ID marks and fields, data marks and fields, and CRC bytes. It does not
perform sector matching and does not silently repair, retry, or substitute a
cached logical track. WD Read Track does not CRC-check this stream; a diagnostic
parser may observe patterns out of band but MUST NOT change WD CRC status or
suppress transferred bytes.

If the CPU misses DRQ, set Lost Data as in section 10.3. An internal FIFO
overflow is a Codec Overrun/Internal Fault, not ordinary host Lost Data.
Missing the starting or ending index produces RNF/No Index: the 300 ms start
and 260 ms end wall bounds in section 11.2 terminate the respective wait. The
current `fdc1772.v` behavior that merely delays and reports success MUST be
removed for physical mode.

The ending fast edge stops capture and emits the tagged end marker. Busy/INTRQ
wait only for the marker watermark and bounded retrospective index-pulse
qualification, never for CPU service of the final DRQ; final DRQ and INTRQ may
therefore coexist. A rejected fast edge returns No Index/RNF rather than false
Read Track success.

### 10.9 Write Track and formatting

Write Track is the formatting primitive. Command acceptance sets Busy/MO but
does not yet raise its first DRQ when h=0 spin-up or the Type-III E delay is
pending. Define `write_track_execution_start` as the first cycle after the
required six-edge spin-up (or h/MO bypass), media/readiness checks, the one
15 ms E delay, and a current-generation `index_write_locked` snapshot. A
broad-readable but write-unlocked RPM terminates
`RES_UNSAFE_WRITE_TIMING/detail=0x01` without first DRQ. Before declaring
execution start, also require live/conditioned WP writable, no pending disk
change, and valid restored head position. A failure terminates Write Protect or
Disk Changed/RNF without first DRQ, index arm, or backend write request. At execution
start raise the first DRQ, start the 96 us first-token
deadline, and start the separate 300 ms index-search watchdog. Neither timer
runs during spin-up; the 2.050 s spin watchdog already bounds that phase. If the
first token arrives within 96 us, the controller arms
the next eligible profile-window index candidate. It never retroactively joins
an INDEX pulse whose falling edge occurred before arm eligibility. The candidate's synchronized falling edge
timestamps the revolution, but it opens WGATE only after
`index_start_min_qualified` proves that INDEX remained continuously active for
the profiled minimum and `index_write_locked` is still current. It interprets
the CPU stream magnetically until the earlier ending fast edge or conservative
`T_tail_close` from section 13.3:

- ordinary values write the corresponding MFM byte;
- F5 writes A1 with the missing clock transition and initializes/presets the
  CRC sequence required for an address mark;
- F6 writes C2 with the missing clock transition;
- F7 writes the current CRC high byte followed by low byte;
- an F7 does not itself appear as byte F7 on the disk.

No later token is requested before the starting index. Subsequent DRQs follow
actual token consumption. Underflow before magnetic close writes zero bytes and
sets Lost Data. After the conservative tail close, the frontend continues the
same token-consumption/DRQ cadence but the serializer/firewall emits no WDATA;
excess input cannot cross the physical index. It MUST NOT use a preconstructed
image track whose length is unrelated to the measured revolution.

At an ending `index_edge_fast` that precedes tail close, close WGATE within
three `fdc_clk` cycles. At `T_tail_close`, close unconditionally before the
earliest plausible index. Normal WD Busy/INTRQ completion still occurs only on
the ending fast edge after its bounded retrospective pulse qualification and
does not wait for the 700 us guard. A rejected/runt edge faults the already-
closed format and never reopens; if no edge comes, the 260 ms absolute end watchdog
reports No Index/fault. Neither case reports normal format success.
`phys_write_critical` spans magnetic close and
the 700 us guard. Even if that guard ends first, operation ownership keeps
`mechanics_reusable` false and MOTOR/SELECT/SIDE/DIR/DENSITY stable until the
ending-index event or no-index result retires.

Write Track command bit 1 has the same P meaning: zero enables WD
precompensation and one disables it.

Section 14.7 gives both the service-manual layout and the exact bundled-ROM
stream. The decoder remains tolerant of legal gap variation; the formatter
serializes the actual WD token stream.
The existing fake-success Write Track path is unacceptable even if normal DOS
format appears to complete at a higher layer.

### 10.10 Force Interrupt

Force Interrupt is accepted while Busy and names the current request for
cancellation. The WD low four command bits retain these meanings for the
WD1772-02 model used here:

- immediate interrupt;
- interrupt on each subsequent index pulse;
- unused ready-transition conditions are not invented;
- all zeroes terminate without generating a new interrupt.

Exact bit encoding is `I3=bit3` immediate, `I2=bit2` each subsequent qualified
index, and `I1/I0=bits1/0` unused for WD1770/WD1772. Command `D0` has all four
zero and terminates without a new interrupt.

Immediate Force resets Busy and asserts INTRQ at the WD internal-
microinstruction boundary; it does not wait for WGATE close or the 700 us
guard. The tagged physical cancellation continues independently and closes a
writer within section 9.7’s bound. Status bits other than Busy are preserved
when interrupting an active command. If Force Interrupt is issued while idle,
status is refreshed as Type-I status.

Normal INTRQ clears on Status read or a new Command write. An I3-bearing
immediate `D8` or `DC` is special: Status read/new Command does not by itself
enable normal clearing. Software must issue `D0` after the immediate Force; D0
arms the subsequent Status read or Command write to clear the immediate
interrupt and disarms any D4/DC index condition. D0 itself creates no new IRQ.
A command issued sooner than the WD-specified 16 us MFM Force recovery
nullifies the Force sequence as documented. At or after 16 us the WD front end
accepts a new command; if that command needs mechanics still in close/guard, it
waits boundedly for `mechanics_reusable` rather than being rejected.

Index-conditioned interrupt uses the qualified index event, never the raw pin.
It follows the D8/DC/D0 and normal-clear rules above. A stuck
index input cannot create an interrupt storm because only qualified edges count.

## 11. Physical operation state machine and watchdogs

### 11.1 Required top-level states

Names may differ, but the controller MUST have observably equivalent states:

```text
SAFE_RESET -> IDLE -> MOTOR_WAIT -> SIDE_SETTLE
                    -> SEARCH_ID -> SEARCH_DAM -> READ_DATA -> CHECK_DATA_CRC
                    -> PREPARE_WRITE -> WRITE_PREAMBLE -> WRITE_DATA
                    -> WRITE_CRC_GAP -> POST_WRITE_GUARD
                    -> WAIT_INDEX -> TRACK_READ / TRACK_WRITE
                    -> STEP_SETUP -> STEP_ASSERT -> STEP_RECOVER
                       -> (next STEP_SETUP or final HEAD_SETTLE) -> COMPLETE
any non-writing state -> CANCEL -> COMPLETE
STEP_SETUP + ordinary cancel -> CANCEL (no pulse)
STEP_ASSERT + ordinary cancel -> STEP_FINISH_4US -> STEP_RECOVER -> HEAD_SETTLE -> COMPLETE
any writing state -> WRITE_ABORT_CLOSE -> POST_WRITE_GUARD -> COMPLETE
non-writing state -> FAULT_SAFE
writing state -> FAULT_WRITE_CLOSE -> FAULT_GUARD -> FAULT_SAFE
any state + hard_fail -> HARD_FAIL_SAFE (all outputs immediately clamped)
```

State transitions are driven by acknowledged events and qualified inputs, not
unbounded counters waiting for a pin level. On entry to each operation, the
decoder, CRC, byte counter, observed-CHRN record, error accumulators, and
operation-specific watchdog are explicitly initialized. Resetting only the
outer FSM while retaining stale decoder sync is forbidden.

`STEP_RECOVER` is the per-pulse effective interval and may hand the WD frontend
one step acknowledgement while the independent head-settle timer remains false.
`HEAD_SETTLE` is entered only after the WD frontend declares the sequence's
last pulse; subsequent read/Verify and Type-I completion wait until final-IOB
trailing + `D_step_trailing_max` +18 ms. The controller remains single-operation: the response retires one
step before another step request is accepted; only the settle timer overlaps.

### 11.2 Normative time and revolution limits

Convert physical time to cycles in the conservative direction *after* applying
profile uncertainty and margin. At `G_FDC_HZ = 50,000,000` (and 100 MHz for the
outer counters):

- a minimum hold/setup/settle/filter or “not before” time uses `ceil`;
- a destructive maximum, tail-close, force-close, or “no later than” deadline
  uses `floor` (or an explicitly earlier tick), never `ceil`;
- an accepted closed time window rounds its lower edge up and upper edge down;
- a counter whose limit is `N` initializes elapsed intervals to zero at the
  named origin and fires when the `N`th complete destination-clock interval has
  elapsed; the requirement-specific same-edge priority still applies; and
- if inward rounding empties a write-safety window or removes its required
  margin, that operation/profile is disabled rather than widening the window.

The timing package exposes direction-named helpers such as
`cycles_min_ceil()` and `cycles_max_floor()`; a generic `time_to_cycles()` with
an implicit rounding mode is prohibited on a safety or acceptance boundary.

Availability watchdogs whose tables deliberately accept an event at the stated
inclusive boundary specify that event priority explicitly in their tests; all
current fixed millisecond values are integral destination-clock counts. Generics
may support simulation acceleration, but production values MUST satisfy:

| Event | Minimum or maximum production requirement |
| --- | --- |
| Motor-to-media-ready qualification | never before 505 ms and only after two qualified index edges establish one plausible period; WD command spin-up separately counts six leading edges |
| Mechanism-ready deadline | 1.10 s from motor assertion, independent of index and ready state |
| Plausible runtime index period | 150–250 ms; record exact period and warn outside 180–220 ms |
| Missing index after previously locked operation | not-ready after 300 ms, while the independent command watchdog continues |
| WD six-edge Motor-On spin-up | six qualified leading edges; independent `505 ms + 6*P_read_max + W_index_max + margin` watchdog, initially 2.050 s from command spin-up entry |
| Side-select settle | at least 100 us |
| Status-only Drive-A probe | first sample after `D_select_assert_max + 1 us` rounded up; final-IOB deselect by 16 us unless converted to a named operation |
| Direction setup before STEP | 24 us (exceeds mechanism minimum 0.8 us) |
| STEP active-low width | 4 us (exceeds mechanism minimum 0.8 us) |
| Same-direction step interval | at least max(WD rate, 3 ms) |
| Reversal step interval | at least max(WD rate, 4 ms) |
| Final head settle before verify/read | at least 18 ms; WD E flag’s 15 ms never reduces this |
| DAM after matching ID | at most 43 decoded DD byte times = 1.376 ms |
| Sector/ID search | five qualified index leading edges; secondary `5*P_read_max + W_index_max + margin` watchdog, initially 1.300 s from search entry |
| Restore | 255 step pulses and a secondary 3.2 s watchdog after stepping begins; covers 255 x 12 ms plus pulse/settle margin |
| Seek | requested distance x effective rate + 18 ms + margin; >=3.2 s capability for 255 x 12 ms |
| Read Track start/end | fast next index; 300 ms start and 260 ms end wall bounds for broad read-plausible media |
| Write Track start | after spin-up/E reaches `write_track_execution_start`, raise first DRQ and run an absolute 300 ms; profile-window fast edge timestamps candidate only with `index_write_locked`, including an in-flight pulse skipped to the next revolution; WGATE waits the inclusive 32-us/profiled minimum-low qualifier; no WGATE on runt or timeout |
| Write Track magnetic end | fast ending index if it arrives first; otherwise conservative tail close completes before the earliest plausible next index; WD command waits only until the next row's 260 ms absolute command-end bound |
| Write Track command end | absolute 260 ms from the accepted start candidate's original fast timestamp; never reset by raw/rejected index, DRQ, FIFO, or tail close |
| Write Sector WGATE absolute maximum | <=17.100 ms at connector; raw-100-MHz outer-IOB counter forces at `floor((17.100 ms - D_sector_connector_delta_max)*100 MHz)` intervals, covering the exact 531 x 32 us = 16.992 ms stream plus close margin |
| Raw WP/change destructive clamp | `D_raw_kill_clamp_max <=2 us` from qualifying connector assertion to both connector WDATA and WGATE inactive; WDATA no later than WGATE; failure disables physical write/format |
| Post-write control guard | non-reloadable connector-relative >=700 us; ordinary `guard_done` <=710.10 us after final-IOB WGATE inactive under the section 9.7 profile caps |
| Force Interrupt internal WD recovery | at least 16 us before accepting a new WD command |
| Source-switch admission quiet | at least 500 ms with released/inactive IEC and no drive-work event; race barrier only, never cache-clean proof |

The representative mechanism must meet its 197–203 ms qualification target,
but that narrow data-sheet range is not used as a runtime on/off gate. The
wider 150–250 ms edge window prevents modestly aged but readable mechanisms
from being rejected solely by index timing. Codec lock and magnetic-data tests
still determine whether such a mechanism is usable; implausible periods cannot
reset either absolute watchdog.

### 11.3 Search accounting

The record-search counter increments on each qualified index leading edge after
search starts and expires when the fifth such edge passes. Do not add a sixth
edge or five full post-reference intervals; that six-edge convention belongs
only to motor spin-up. Bad IDs are classified while scanning:

- an A1/FE pattern with incomplete CHRN is malformed, counted diagnostically,
  and ignored;
- a complete matching CHRN with bad ID CRC sets `saw_bad_id_crc` and scanning
  continues;
- a valid nonmatching ID proves media activity but not success;
- a matching valid ID followed by no legal DAM records Missing DAM and resumes
  ID search; a later matching copy may succeed before the overall budget;
- disk change invalidates the entire search immediately.

The absolute watchdog is independent of index and wins if index chatters,
stalls, or the revolution counter cannot progress.

### 11.4 Fault containment

An illegal FSM encoding, impossible ownership transition, out-of-range buffer
address, conflicting output owner, watchdog expiry in a state that lacks a
defined media error, or CDC protocol violation sets a sticky internal fault.
Outside write/guard, the safety block clamps outputs to section 12’s inactive
policy, except that an already-fallen STEP under a healthy trusted clock is
completed by the independent 4 us one-shot before clamp/settle as section 9.7
requires. A fault that compromises that one-shot or an asynchronous hard clamp
instead invalidates head position. During write with a healthy safety clock it enters
`FAULT_WRITE_CLOSE`, immediately makes WGATE/WDATA/STEP inactive, latches
MOTOR/SELECT/SIDE/DIR/DENSITY, then enters `FAULT_GUARD` for 700 us before
inactivating those mechanics controls. Hard reset, reconfiguration, or genuine
safety-clock failure overrides the timed guard and clamps everything because
the guard can no longer be trusted. The active command receives
`RES_INTERNAL_FAULT`; subsequent physical commands fail until controlled backend
reset/source re-entry. Diagnostics retain first cause and state.

Fault recovery MUST NOT clear a pending raw write-protect assertion, disk-change
latch, or post-write guard.

## 12. Physical pin and electrical contract

### 12.1 Logical signals and inactive levels

The FPGA-facing top level already exposes two mechanism groups. Only drive A is
used. The normalized logical contract is:

| Signal | Direction | Active meaning | Required inactive/fail-safe value |
| --- | --- | --- | --- |
| `f_motora_o` | output | low: spindle motor requested on | high |
| `f_selecta_o` | output | low: drive A selected | high |
| `f_side1_o` | output | reference mechanism high=side 0, low=side 1; verify board wrapper | board-qualified side 0 while deselected |
| `f_stepdir_o` | output | high toward track 0, low toward higher cylinders at mechanism connector | retain safe value; never change in write guard |
| `f_step_o` | output | low pulse advances one cylinder in selected direction | high |
| `f_wgate_o` | output | low enables writing | high, asynchronously clamped where the device technology permits |
| `f_wdata_o` | output | low pulse encodes a magnetic transition while writing | high |
| `f_density_o` | output | board/mechanism-dependent DD selection | qualified DD inactive/selection value; never toggle during command |
| `f_motorb_o` | output | low would start drive B | high permanently |
| `f_selectb_o` | output | low would select drive B | high permanently |
| `f_index_i` | input | active-low index pulse | synchronized, filtered |
| `f_track0_i` | input | active-low head at cylinder 0 | synchronized, filtered |
| `f_writeprotect_i` | input | active-low write protected | raw path plus synchronized copy |
| `f_diskchanged_i` | input | pin-34 disk-change indication, polarity confirmed per board | direct raw outer-write-kill path plus synchronized sticky event |
| `f_rdata_i` | input | active-low transition pulse | edge captured and gap measured |

Signal names above are the existing M2M top-level port names; the implementation MUST
verify polarity at the actual board buffer and connector. Internal APIs use
positive semantics (`motor_on`, `selected`, `write_protected`, `index_event`)
so active-low conventions do not propagate through control logic.

The existing top-level constants that keep outputs high are a safety regression
fix from commit `78767048c1be7ba29e1279bb08f740679ad0dbcc`
(issue #110, internal drive kept spinning). Replacing them with live signals
MUST preserve high levels from configuration start until all authorization
conditions are true.

### 12.2 Output safety firewall

All requested outputs pass through two named safety layers with no alternate or
debug writer. `physical_1581_safety` is the 50 MHz functional firewall and owns
write authorization, the functional sticky kill/retirement state, writer
deadlines, and the guard; it does not own the final raw-media clamp.
`physical_1581_outer_safety`, instantiated in `CORE/vhdl/mega65.vhd`, is the
last logic before the `MEGA65_Core` physical output ports and owns the dedicated
final IOB/OE registers, direct asynchronous raw-WP/change `outer_write_kill`,
and all-output hard-fail path. Only the outer layer drives those ports. Its independent
100 MHz clock/async-fault contract is in section 16.2. Together they enforce:

1. Hard reset, FPGA initialization/reconfiguration, or independently detected
   invalid safety clock (`hard_fail`) forces every output inactive immediately.
   Unqualified/mode-inactive/controller-fault outside write/guard does likewise,
   except a healthy-clock ordinary cancel/fault after STEP has fallen is handed
   to the independent exact-4-us one-shot before inactivity. Hard-fail never
   waits and therefore invalidates position if it truncates STEP.
   If an ordinary fault or unexpected mode loss occurs during write with a
   healthy clock, WGATE/WDATA/STEP become inactive immediately but MOTOR/
   SELECT/SIDE/DIR/DENSITY retain their pre-fault values through the 700 us
   guard; the sticky fault cannot bypass that guard on its next cycle.
2. Write gate may assert only in a designated writer state with selected drive
   A, `media_ready`, settled head/side, current-generation
   `index_write_locked`, current write authorization, no disk change,
   `head_position_valid` and no `restore_required`,
   raw/conditioned disk-change inhibit clear, both raw and conditioned
   write-protect deasserted, and a live watchdog.
3. Write data is high unless write gate is authorized. Every low WDATA pulse is
   counted; a pulse outside authorized write gate is a fatal assertion.
4. STEP is high except for the bounded pulse state. No STEP, DIR, SIDE, SELECT,
   DENSITY, or MOTOR transition is allowed while write gate is active or during
   the 700 us post-write guard, except that `hard_fail` may override media-
   integrity timing.
5. Drive B outputs are constants, not software-controlled registers.
6. Debug and QNICE diagnostics are read-only with respect to mechanism outputs.

Polarity-qualified raw write protect/change goes directly to the asynchronously
set `outer_write_kill` inputs of the final WGATE/WDATA IOB/OE safety primitives;
it does not detour through `main`, the 50 MHz functional request path, or a
multi-cycle backend handshake. Hard reset/fault has its separate all-output
`hard_fail_outer` path. Only synchronized/sticky copies feed ordinary state
retirement. The chosen primitive and output ordering MUST meet section 13.6's
`G_RAW_KILL_MIN_NS` capture and `D_raw_kill_clamp_max <=2 us` connector bounds;
qualification cannot replace those ceilings with a slower measured value. No
asynchronous signal may feed the ordinary FSM without synchronization.

### 12.3 Board electrical qualification

The 34-pin mechanism convention uses open-collector drive outputs and host
pull-ups, but the MEGA65 board’s level shifters/buffers are the FPGA’s actual
electrical boundary. Before enabling a target, record from schematic review and
bench measurement:

- connector pin mapping, polarity, I/O voltage, buffer direction, and output-
  enable defaults;
- pull-up presence and value for INDEX, TRACK0, WPROT, CHANGE, and RDATA;
- FPGA configuration-time level of MOTOR, SELECT, WGATE, WDATA, STEP, SIDE,
  DENSITY, and DIR;
- whether WGATE and WDATA fail high if the 50 MHz clock stops;
- pin 34 strap as Disk Change rather than Ready;
- pin 2/density strap and the level that selects 250 kbit/s DD operation;
- mechanism model, cable orientation, and power-up behavior;
- raw WP/change connector-to-connector clamp latency and WDATA-before/equal-
  WGATE inactive ordering, proving `D_raw_kill_clamp_max <=2 us`;
- signal integrity and pulse widths at both FPGA-side buffer and drive
  connector under a logic analyzer/oscilloscope.

Do not infer those facts from a PC floppy pinout. A target’s activation gate remains
off until its qualification record is checked into `doc/` or linked from the
release evidence.

### 12.4 Board-revision policy

All R3, R4, R5, and R6 builds contain the RTL and compile-time port plumbing so
there is one maintained design. Explicit release/build generic
`G_PHYS1581_CAPABLE` is ANDed with the known `G_BOARD` family in `main.vhd` and
the final safety firewall; default is false. `G_BOARD` alone cannot prove the
attached mechanism model, cable, pin-2/pin-34 straps, or replacement drive.
Documentation states that an unqualified replacement cannot be auto-detected
and must not use a capability-enabled build profile.

Initial qualification effort MUST cover production R3/R3A and R6. R4 and R5
are not declared electrically unsupported merely because they are development
revisions, but they remain forced to Image until their schematic and bench
checklist passes. Unknown or custom targets default to image-only. The current
menu is a shared static structure, so `G_BOARD` alone cannot hide one line; the
implementable UI choices are bound in section 15.1. No menu or configuration
bit may override the hardware safety capability.

### 12.5 Conventional connector reference

This table is a qualification aid, not a substitute for the MEGA65 schematic.
Odd-numbered pins are grounds in the conventional 34-pin interface.

| Pin | Conventional signal | Direction at mechanism | Convention |
| ---: | --- | --- | --- |
| 2 | Density Select / option | input or model-dependent | strap/model dependent; qualify before driving |
| 8 | Index | output | active-low, normally open collector |
| 10 | Motor A | input | active-low |
| 12 | Select B | input | active-low; unused and inactive here |
| 14 | Select A | input | active-low |
| 16 | Motor B | input | active-low; unused and inactive here |
| 18 | Direction | input | low inward/higher cylinder; high outward/track 0 |
| 20 | Step | input | active-low pulse; one host pulse per cylinder |
| 22 | Write Data | input | active-low magnetic-transition pulse |
| 24 | Write Gate | input | active-low |
| 26 | Track 0 | output | active-low, normally open collector |
| 28 | Write Protect | output | active-low, normally open collector |
| 30 | Read Data | output | active-low transition pulse, normally open collector |
| 32 | Side Select | input | high selects side 0; low selects side 1 on the reference mechanism |
| 34 | Disk Change / Ready | output | model/strap dependent; issue #90 requires Disk Change |

PC-drive inputs are normally pulled-up TTL-style inputs, while mechanism
outputs are normally open collector. Side, selection, and motor gating affect
when some mechanisms drive their outputs. Allow at least 1 us after selection
(the reference mechanism specifies output validity within roughly 0.5 us)
before trusting newly enabled status. The board wrapper MUST explicitly map
these conventions to the existing `f_*`/`FLOPPY_*` ports; matching a signal
name is not proof that the same connector pin, voltage, or polarity reaches the
FPGA.

## 13. Mechanics, presence, and media-state model

### 13.1 CIA control is the real mechanism control

The existing 1581 model uses `EXT_MOTOR(1)`. Preserve that architecture:

- 8520 CIA PA2 is the mechanism motor request (`motor_n` in
  `c1581_drv.sv`); it is the sole normal source of drive-A motor control;
- CIA PA0 selects the physical side through the normalized side interface;
- CIA PA1 receives synthesized Ready with the existing polarity;
- CIA PA7 receives the disk-change indication with the existing polarity;
- CIA PB6 receives live write-protect with the existing polarity.

The binding for the existing inversion is explicit: CIA PA0 `0` selects
physical side 0 and drives reference-mechanism `f_side1_o` high; CIA PA0 `1`
selects physical side 1 and drives `f_side1_o` low. The side-asymmetric golden
disk verifies this at the connector and through CHRN/payload; do not add or
remove another inversion opportunistically in a wrapper.

CIA PA2 is already named `motor_n`: PA2 `0` requests motor on and therefore
drives qualified `f_motora_o` low; PA2 `1` requests motor off/high. Safety and
post-write guard may delay an off transition, but may never manufacture an on
request. `motor_hold_active` is not a second request source: it is a latched
completion of the already-active CIA request, valid only from authorized WGATE
through close/guard. It also meets the reference mechanism's >=650 us
motor-after-WGATE requirement through the stronger 700 us guard.

At the CIA input boundary, physical Ready true is PA1 low, disk-change pending
is PA7 low, and write-protected is PB6 low. Internal normalized booleans remain
positive-semantic; these inversions occur once at the boundary and are covered
by direct CIA-register tests.

The WD1772’s Motor On status/spin-up bookkeeping is a controller semantic and
is distinct from the CIA pin that actually starts the motor. A WD command may
wait for motor readiness and count index pulses, but it MUST NOT silently turn
on, override, or fight the CIA-controlled motor. Do not OR WD and CIA requests
without an explicit future compatibility decision. If ROM or direct-FDC
software issues a command without requesting the motor, the absolute readiness
deadline returns Not Ready rather than waiting forever.

Drive A selection is asserted only while physical mode is active. Within that
mode it MUST remain asserted for the complete CIA motor-request interval and
through any deferred motor-off/write guard, so synthesized Ready and index do
not disappear between commands. With the motor off it is also asserted for a
pre-command status probe, step/disk-change-clear operation, or other named
access. Let `D_select_assert_max` be the qualified maximum from the final-IOB
SELECT-active transition to active SELECT at the connector; every capable
profile MUST prove it <=1 us. A status-only probe takes its first sample after
`ceil((D_select_assert_max + 1 us) * G_FDC_HZ)` cycles from that final-IOB
transition, guaranteeing >=1 us at the connector, and, unless it converts into
a named operation, drives the final IOB inactive no later than 16 us after
assertion. Q-06 freezes the delay. That probe may discover an asserted
WP/change level, but it never proves a deasserted level safe for writing: the
independent >=100-us release filter in sections 13.5–13.6 must still complete.
A named step, spin-up, or media command retains selection for its own longer
bound.
Deselect is forbidden during an operation, write, or post-write guard. Drive B
is never selected. A profile whose disk-change output is not visible while
deselected must retain the standard latched indication until the next selected
probe; no write is authorized before that probe.

### 13.2 Media Ready, read safety, and mechanics reuse

Pin 34 is Disk Change, so the controller synthesizes three distinct states:

```text
media_ready:
  steady state: selected + CIA motor requested + actual motor on + >=505 ms
    + two qualified index edges establishing one plausible period
    + no disk change/index-health failure
  active writer/guard: latched writer_media_ready + motor_hold_active
    + actual motor/select held, unless hard/raw media-safety fault invalidates it

read_path_valid:
  media_ready + selected side settled + head/seek settled + not writing
  + >=700 us read recovery complete

mechanics_reusable:
  media_ready + no step/seek/write/cancel/guard in progress
```

Only `media_ready` drives CIA PA1. It normally remains asserted across a
commanded step sequence, side settling, writing, and post-write recovery; those
events suppress `read_path_valid` or `mechanics_reusable`, not media presence.
`write_authorized` separately requires media_ready, head/side settled,
current-generation write lock for every WGATE operation, WP/change clear,
current identities, safety state, and
watchdog. WGATE therefore cannot revoke its own readiness condition.

The firewall tests live steady-state readiness, CIA PA2, and actual MOTOR/SELECT
at WGATE assertion, then uses the immutable `writer_media_ready` snapshot for
that writer. A normal PA2-off cannot make the implication false mid-pulse; it is
pending state. Disk change, mechanism power/reset, hard-fail, or another raw
safety cause still closes/invalidates immediately as specified.

A selected, motor-requested Type-I Restore/Step needed to clear Disk Change is
allowed while media_ready is false solely because change is latched; read,
Verify, sector, and write operations remain blocked. This exception cannot
authorize WGATE.

Startup uses two qualified edges/one measured period, not two complete periods.
Index capture starts with motor assertion, but Ready is clamped false until 505
ms. If no usable edge history exists at that point, even two later edges at the
broad 250 ms limit fit within the independent 1.10 s deadline with filter margin.
The six-edge WD Motor-On spin-up sequence remains separate.

The narrow 197–203 ms range is a mechanism/write qualification. Ordinary read
plausibility accepts 150–250 ms and warns outside 180–220 ms. A blank indexed
disk may become media_ready and later yields RNF; RNF is not “no disk.” No index
cannot distinguish absent media from a stopped spindle, so diagnostics retain
the exact observed state.

Some mechanisms suppress INDEX while seeking. Missing-index ageing pauses only
from the first controller-authorized STEP through final bounded head settle;
the Seek/Restore watchdog still runs. After settle, a qualified index must
reappear within 300 ms or media_ready drops with No Index. Index fast capture
remains active during Write Track even though RDATA is ignored. RDATA remains
ignored until at least 700 us after WGATE close.

### 13.3 Index qualification

Index is active low and normally 1.5–5 ms wide. Qualification MUST:

1. synchronize both levels;
2. require a minimum low width that rejects narrow electrical glitches but
   remains below 1.5 ms;
3. require return high before another edge;
4. timestamp the active-going leading edge;
5. measure pulse width and leading-edge period;
6. count only periods in the broad operational window for readiness/search;
7. retain raw-edge and rejected-edge counters for diagnostics.

A search wall timer never resets merely because an edge was rejected or
because index chatters.

There are five explicitly separate index products:

- `index_edge_fast`: the earliest active-going edge after two-flop
  synchronization. It may timestamp non-destructive Read Track boundaries and
  is the destructive **close** input after the accepted start pulse has returned
  high. Every subsequent distinct fast falling edge closes, regardless of
  measured period. By itself it MUST NEVER open WGATE;
- `index_start_min_qualified`: a one-shot destructive-start authorization for an
  armed candidate whose original fast-edge timestamp was in the profile
  window and whose synchronized INDEX level then remained continuously active
  for `G_INDEX_START_MIN_US`. The initial value is 32 us/1,600 `fdc_clk` cycles;
  a board/mechanism profile must put it above the measured false/runt-pulse floor
  with PVT margin and well below the 1.5 ms valid-pulse minimum;
- `index_sector_epoch_min_qualified`: the same inclusive minimum-low filter,
  but used only to establish an immutable second-pass Write Sector revolution
  origin. Its candidate must fall inside the next full
  `[P_write_min,P_write_max]` window derived from the preceding fully qualified
  edge and carry the writer generation. It never opens WGATE by itself;
- `index_pulse_qualified`: retrospective width/return-high/period validation
  used by Ready, record-search counts, RPM, command success, and diagnostics;
- `index_write_locked`: at least three recent complete periods and widths within
  the qualified write profile (initially 197–203 ms and 1.5–5 ms), with
  consecutive-period jitter inside the measured profile.

This lock authorizes the fixed 250 kbit/s angular write rate for both Write
Sector and Write Track. Read operations may use the broad 150–250 ms range;
*no* WGATE operation may do so, because a sector splice written at the wrong RPM
can consume the following gap/ID even when the incoming field still decodes.

The lock/profile state carries `source_epoch`, `physical_media_generation`, motor-
session generation, and `index_lock_generation`. Clear it, its period history,
and every fast-edge arm on source/media change, raw or conditioned disk change,
motor/select loss, reset/hard-fail/controller fault, an implausible/rejected
period, or an aborted/failed Write Track. A side change or STEP invalidates the
read codec/head-settle state but not healthy spindle-period history. Do not
snapshot a writer at raw WD Command acceptance: a cold command may still be
acquiring spin/lock. Write Track copies the three-period history and conservative
profile bounds at `write_track_execution_start`; Write Sector copies them at
post-spin-up/E child execution before its first search. Both recheck the same
lock generation at every candidate/search and immediately before WGATE, without
consuming the global lock. A successfully qualified ending
index updates/retains that history, permitting normal back-to-back side/track
formatting; a later-rejected ending edge clears it before another writer.

The qualified profile freezes `P_write_min` and `P_write_max` as conservative
connector-leading-edge period bounds after measurement uncertainty, clock
quantization, unit spread, temperature/voltage margin, and permitted
one-revolution change. Initial values are 197 ms and 203 ms. A median or average
of the last three periods may be reported diagnostically, but it MUST NOT
tighten these safety bounds or authorize a later magnetic close. Thus an abrupt
legal 203 ms -> 197 ms revolution remains covered.

The timestamp comparator uses
`N_write_min=ceil(P_write_min*G_FDC_HZ)` and
`N_write_max=floor(P_write_max*G_FDC_HZ)`; the endpoints are inclusive only
after this inward conversion. Non-integral profiled bounds never round outward.

The destructive start window is exactly the intersection of the broad >=150 ms
plausibility bound and `[last_qualified + P_write_min,
last_qualified + P_write_max]`. If command acceptance occurs inside that window,
arm eligibility still waits for the first token and the missed/in-flight rule
below. If eligibility occurs after the upper bound with no unresolved pulse, do
not reuse stale history: fail this command No Index without WGATE and let the
background index monitor requalify for a later command. After start, the
ending-edge close arm becomes permanent for that writer as soon as the accepted
start pulse returns high; it is not delayed to 150 ms. Every arm and edge carries the writer's
lock generation; a mismatch closes/rejects rather than authorizing output.

Arm eligibility is a registered state that must be true for a complete
`fdc_clk` cycle before it may consume a fast edge. If the first token/eligibility
arrives in the same cycle as the edge, the edge wins as already missed. If INDEX
is already low, or a raw-edge sequence newer than `last_qualified` is still
awaiting width/period classification, set `start_missed_inflight`: never join
that pulse and never open WGATE from it. Let it return high and resolve. If it
qualifies, update the reference/history, clear the missed state, and arm the
*following* full `[P_write_min,P_write_max]` window. If it is rejected, clear the
write lock and fail the current command without WGATE; reacquisition is for a
later command.

An armed Write Track falling edge in the window latches its *original* fast
timestamp and starts the consecutive-active counter. Return-high before
`G_INDEX_START_MIN_US` rejects only that candidate, records it, and leaves WGATE
high; another candidate may be considered only while the same tagged arm/window
remains valid. At the threshold, recheck source/media/motor/lock generations,
WP/change, side/head settle, first-token ownership, and every ordinary write
authorization before pulsing `index_start_min_qualified`. WGATE may then open.
The filter delay does not move the revolution timestamp or profile window. A
300 ms absolute start watchdog begins at `write_track_execution_start` and never
restarts on raw/rejected/in-flight edges. It covers the worst legal remainder of
an in-flight 5 ms pulse, one 203 ms revolution, the start filter, and margin;
expiry invalidates the first token and returns No Index with WGATE never opened.

If a start pulse passes the minimum-start filter but later fails full 1.5–5 ms
width/return-high/period qualification, immediately close any opened writer,
enter guard, report the index fault, and never reopen on that revolution. Such a
failure may have damaged the current track; production qualification must show
that electrical false/runt pulses cannot reach `G_INDEX_START_MIN_US`. Waiting
the full 1.5 ms before opening is not substituted silently because it would
invalidate the fastest-revolution capacity proof below.

Write Sector uses the parallel epoch qualifier before accepting its second-pass
ID. A raw/runt edge below the minimum cannot rebase `T_idcrc2`; an out-of-window,
rejected, or generation-mismatched edge aborts the write intent and may only
close, never authorize. If an unusually early ID CRC completes before the 32 us
filter, retain its tagged timestamp/CHRN as a candidate until the qualifier
resolves, then measure from the original edge; do not delay disk time or open
WGATE early. A pulse that passes the minimum but later fails full qualification
aborts before WGATE or immediately closes/faults after it, exactly like the
Write Track start-pulse rule.

Read Track may align to `index_edge_fast`; Write Track aligns its profile window and
tail timer to the candidate's fast timestamp but opens only on
`index_start_min_qualified`. Full pulse qualification MUST NOT delay an active
writer's fast WGATE closure. After the start pulse returns high, *every* distinct
fast falling edge closes immediately, including an implausibly early one. A
later-rejected ending fast edge may truncate and
fault a format but can never reopen or extend WGATE. Formatting is refused
without `index_write_locked`; the broad 150–250 ms read-plausibility range is not
write authorization.

Write Track never deliberately writes past an expected index. Use frozen
`P_write_min` as the lower-confidence next-revolution bound, never an optimistic
recent-period estimate. Define `L_start` as the worst original-candidate-edge to connector-WGATE-
active latency (synchronizer, minimum-start filter, authorization, and output),
`L_data_start_max` as the worst connector-WGATE-active to first magnetic-byte
serialization origin (initial bound 8 us, including the leading envelope),
`L_close` as worst synchronizer/firewall/connector close latency, and `M_guard`
as a positive safety margin. Schedule all terms from the original candidate
timestamp:

```text
T_tail_close = P_write_min - L_close - M_guard
N_tail_close = floor(T_tail_close * G_FDC_HZ)
T_required_format_end = N_format_required_max * 32 us
                      = 6122 * 32 us = 195.904 ms (stock profile)

require T_tail_close >= L_start + L_data_start_max
                        + T_required_format_end + M_tail

equivalently, for the initial minima:
L_start + L_data_start_max + L_close
  <= 197 ms - 100 us - 195.904 ms - 250 us = 746 us
```

The firewall fires on elapsed count `N_tail_close` from the original candidate
timestamp; it never rounds that destructive deadline up. Timestamp
quantization and the final destination-clock interval are included in
`L_close`/profile uncertainty, and qualification proves connector WGATE is high
by the time-domain `T_tail_close` bound.

The initial profile uses `G_INDEX_START_MIN_US = 32 us`, `M_guard >= 100 us`,
and `M_tail >= 250 us`; the frozen lower-confidence period and measured
open/close latency must leave both the pre-index close margin and the canonical-
completion inequality true at its shortest qualified 197 ms period. Increasing
the start filter requires rerunning that arithmetic
and the canonical-write proof; failure disables physical Write Track for the
profile. The 32 us start filter and 8 us `L_data_start_max` leave about 706 us of
that initial 746 us for all remaining open/close path latency; qualification replaces that arithmetic
allowance with measured worst-case values. WGATE closes at `T_tail_close` even during an
otherwise healthy format, sacrificing only trailing filler; the WD frontend
continues its real-time token/DRQ consumption without magnetic output until the
ending index. The ending `index_edge_fast`, if earlier, closes immediately.
That fast close is armed continuously from return-high of the accepted start
pulse through command retirement, not only inside the next profile window; an
early/late glitch may truncate/fault but never extend writing or be ignored
across a real index.

`T_tail_close` is owned by the continuously running functional safety firewall,
not the Write Track serializer/FSM. At the accepted original start timestamp it
latches the writer identity, `P_write_min`, margins, and an absolute expiry on a
free-running `fdc_clk` timebase. No valid/ready, token, DRQ, FIFO, CRC, parser,
FSM state, pause, or raw/rejected index can stop, reload, or move that expiry.
At expiry the firewall requests the final close regardless of writer state; the
latched `L_close` bound includes crossing/output latency. If `fdc_clk` itself
stops, section 16.2's independent 100 MHz heartbeat path closes instead.

The ending qualified/fast index still determines normal WD completion. If it is
missing, WGATE is already safe before the earliest plausible boundary and the
260 ms absolute end-index watchdog, measured from the original accepted start
fast timestamp, returns No Index/fault and retires Busy/ownership. The watchdog
does not restart on raw/rejected edges, token/DRQ activity, or tail close. This is a deliberate
physical-mode safety specialization: arbitrary nonstandard Write Track content
whose meaningful bytes extend beyond `T_tail_close` is unsupported, while the
standard ten-record 1581 recipe is proved complete before close. If a mechanism
profile cannot establish a conservative `P_write_min`, canonical completion, and connector-close
margin, physical Write Track is disabled. Index-conditioned Force Interrupt
uses one retrospectively qualified event per pulse; destructive close uses the
fast edge or earlier conservative tail close.

### 13.4 Track zero and head position

Physical head position is invalid after FPGA hard reset or any ambiguous
mechanism-only reset/movement event. Live conditioned Track Zero still appears
in Type-I status, but it does not by itself clear `restore_required`; a
successful explicit Restore establishes `head_position_valid` at cylinder zero.
Thereafter the estimate updates only after an actual, acknowledged STEP pulse:

- inward pulse increments up to diagnostic 79/unknown-overrange;
- outward pulse decrements toward zero;
- Restore stops without a pulse when Track Zero is already active;
- an explicitly commanded Step Out may still emit one legal outward pulse at
  Track Zero (the head stays at zero), allowing a real selected-step disk-
  change clear; it is recorded diagnostically and is never injected invisibly;
- disk change conservatively invalidates the estimate because the same mechanism
  indication can accompany drive power-on/reset on qualified PC mechanisms;
- decoded C fields never correct the estimate, because malformed or foreign
  media can contain arbitrary values.

Track Zero is a live physical input for Type-I status. After the final 18 ms
head settle and at least the mechanism-qualified Track-Zero validity window
(initially 2.8 ms), either `estimate>0 && track0_asserted` or
`estimate==0 && track0_deasserted` is a position-contract fault, not a warning.
Latch the cause, clear `head_position_valid`, set `restore_required`, and prohibit
further media/destructive access. Do not auto-correct the estimate or WD Track
register; only an explicit successful Restore recovers it.

After a successful Restore, the estimate is safety-authoritative only for
preventing end-stop abuse: a Seek target above 79 or Step In at estimated 79 is
rejected before another pulse and mapped to Seek Error as an explicit physical-
mechanism safety deviation. While position is invalid, every Type-II/Type-III
command—including Read/Write Track—and every inward Seek/Step is rejected until
Restore with `RES_INVALID_REQUEST` plus command-class Seek Error/RNF and an
explicit restore-required diagnostic; no writer can format an unknown physical cylinder. Restore and the
single explicit outward Step-Out disk-change-clear action remain allowed. The
controller never emits an unbounded exploratory inward sequence. Cold-start
qualification covers disk change asserted with the head already at track 0 for
both stock and supported JiffyDOS ROM sequences.

The board/mechanism profile MUST record the mechanism 5 V/reset topology and
REN/auto-recalibration strap. Some mechanisms may autonomously recalibrate to
Track Zero for up to roughly 400 ms after their own reset. Production write/
format is allowed only when either (a) mechanism power/reset cannot occur
without the FPGA hard-reset path that already clamps writers and invalidates
position, or (b) a qualified raw power-good/reset monitor feeds both the one-way
`raw_write_kill` and `hard_fail_outer` asynchronous final-IOB clamp. Its assertion
immediately makes WDATA inactive no later than WGATE even during an active write,
invalidates writer/position identities, and also creates synchronized
`mechanism_power_or_reset_event` for diagnostics/recovery. A merely synchronous
“check before next command” is insufficient: recovering mechanism voltage could
otherwise make a still-low WGATE effective during autonomous recalibration.

After such an event, outer release requires power/reset/change stable for the
profiled maximum internal reset/recalibration interval (at least 400 ms for a
REN-enabled reference profile, or its separately proved REN-off bound), then the
section 16.2 SAFE_RESET-style clock/output handshake. `restore_required` remains
set until explicit Restore after release. If autonomous motion or brownout can
neither be excluded nor asynchronously detected/clamped, physical write/format
capability remains off.

### 13.5 Disk change

Pin-34 behavior is mechanism dependent; the qualified profile for issue #90
uses a sticky change indication that is commonly cleared only after a selected
STEP with media inserted. The controller therefore keeps two values:

- conditioned current pin level;
- `disk_change_latched`, which sets on a qualified change event even if the
  pulse occurs between WD/CPU clocks.

Setting the latch MUST:

- raise one lossless media-change event carrying the current source epoch and
  old physical-media generation;
- make Ready false;
- inhibit all new writes immediately;
- invalidate sector-buffer generations, decoder lock, pending write intent,
  track-stream data, and `head_position_valid`; set `restore_required`;
- terminate the active command as Disk Changed unless the safety writer must
  first close;
- remain visible to CIA PA7 until the mechanism’s clear sequence succeeds.

The source manager is the sole owner of `physical_media_generation`; the
physical input/controller block never increments or predicts it. The detector
holds `phys_media_change_valid`, `phys_media_change_source_epoch`, and
`phys_media_change_old_generation` stable until the source manager accepts the
event. On that one acceptance the manager blocks new request admission,
increments the generation exactly once (or executes section 15.2's no-alias
wrap protocol), and broadcasts the new source/media tuple through the
acknowledged control-generation handshake in section 17.3. The disk-change
latch coalesces further raw/conditioned activity until it is legitimately
cleared; a later assertion after clear is a new event and increment.

An operation interrupted by the change remains named by the tuple it latched
at acceptance. Its sole terminal `RES_DISK_CHANGED`, close, guard, and late-
fault state therefore carry the *old* media generation even if the control
broadcast has already advanced. The WD frontend compares such retirement
against that live parent/child tuple, not the newly published idle tuple. No
new operation is admitted until both the WD bridge and physical controller
have acknowledged the new broadcast.

Once board polarity is qualified, raw disk-change assertion also enters the
one-way write-inhibit/clamp path so ejection cannot wait for the ordinary
deglitch filter. A transient may sacrifice the current sector by closing early,
but it may never permit queued write pulses to continue on changed media.

The latch may clear only after all of these are observed: media is present
enough to produce the qualified non-change level, drive A is selected, one
logical WD-requested physical STEP has been acknowledged, the raw change input
remains deasserted for the filter interval, and the fresh
`physical_media_generation` broadcast has been acknowledged by both consumers
and become usable.
Do not inject an invisible step merely to clear change; a WD-requested Step/
Seek supplies it, including explicit Step Out at track zero. If a mechanism has different documented semantics, its
board/mechanism profile supplies a separately verified clear policy.

### 13.6 Write protect

Write protect/change safety has five representations:

1. raw board inputs with one dedicated final-safety fanout and a separate
   synchronized observation fanout;
2. `outer_write_kill`, asynchronously set directly from polarity-qualified raw
   WP/change at the final WGATE/WDATA IOB/OE safety primitives and affecting no
   mechanics output;
3. functional `raw_write_kill`, set by the same raw causes (plus qualified
   mechanism-power/reset loss, hard fault, or hard reset) and returned
   synchronously/stickily for controller retirement and diagnostics;
4. synchronized assertion-fast/deassertion-filtered status states;
5. command-sticky `write_inhibit` that remains set until the command and
   post-write guard retire.

`outer_write_kill` is the authoritative destructive clamp. It makes final WDATA
inactive no later than final WGATE and is never asynchronously cleared. Once
set, neither the active writer nor a new request can reauthorize itself. It may
clear only on the raw-100-MHz clock after all raw WP/change inputs have remained
inactive for their complete release filter (at least 100 us for WP), the named
writer, if any, is closed, its 700-us guard is complete, the controller reports idle,
and an acknowledged safe-release handshake has reached the outer block. The
functional `raw_write_kill` follows the same no-reopen lifetime for state
retirement; its latency is not relied on to protect the connector. Thus a sub-
clock pulse can close but cannot close-then-reopen WGATE before the ordinary
synchronizer sees it. Raw WP/change is deliberately *not* folded into
`hard_fail_outer`, because MOTOR/SELECT/SIDE/DIR/DENSITY must remain stable
through the healthy-clock post-write guard.

The release handshake is named
`outer_write_kill_release_valid/outer_write_kill_release_ack`. The inner/source
arbiter holds valid after its closed/guard/idle proof; the outer block independently
requires the raw-input filter and holds ack until valid drops. It clears the
latch only on a safe 100-MHz edge, asserts ack only after the cleared state is
captured, and gives a same-edge raw assertion priority over release. A missing,
duplicate, or stale release handshake leaves the kill set; it never fails open.

“Sub-clock” is bounded by real hardware, not zero width. Each board profile
freezes `G_RAW_KILL_MIN_NS` from pad/buffer propagation, the FPGA asynchronous-
set primitive's documented minimum pulse width, PVT margin, and scope tests.
Every assertion at least that wide at the connector must set the latch at every
phase; the initial value cannot be assumed until Q-07 measures it. Pulses below
that bound are swept and reported but are outside the capture guarantee—no
digital design may claim detection of an arbitrarily narrow analog glitch. A
captured pulse of any width still obeys the no-asynchronous-clear/no-reopen rule.
Qualified mechanisms produce WP/change assertions vastly longer than this
electrical minimum.

Define `D_raw_kill_clamp_max` from the first qualifying asserted crossing of WP
or CHANGE at the drive connector to the instant both WDATA and WGATE are
inactive at that same connector. It includes cable, input buffer, asynchronous
set primitive, final IOB/OE, output buffer, voltage, and PVT delay. WDATA MUST
be inactive no later than WGATE, and every production write-capable profile
MUST prove `D_raw_kill_clamp_max <= 2 us` at every relative phase and electrical
corner. This is a pass/fail ceiling, not a value that measurement may expand.
If polarity, pulse capture, ordering, or the 2-us ceiling cannot be proved,
physical sector write and format remain disabled on that profile.

Protection assertion wins over every write state. Deassertion MUST be stable
for at least 100 us before a new write can be authorized; it never re-enables a
write already inhibited. At command acceptance a protected disk terminates the
write without asserting WGATE. If protection appears after WGATE opens, the
outer firewall closes WDATA/WGATE within `D_raw_kill_clamp_max`, records a
safety event, and the sector is considered potentially corrupt.

The CIA input is live/conditioned. WD status uses the command-specific rule in
section 10.2. Image write-protect metadata is completely disconnected in
physical mode.

## 14. DD MFM codec and magnetic-write contract

### 14.1 Encoding rule

At 250 kbit/s, each data bit occupies 4 us and is preceded by an MFM clock bit,
so each clock/data half-cell is 2 us. For ordinary data, the clock bit is one
exactly when both the previous data bit and the current data bit are zero:

```text
clock[i] = NOT(previous_data OR data[i])
```

The encoder MUST preserve `previous_data` across ordinary byte boundaries.
Reset, a deliberate sync/mark sequence, or explicit formatter token controls
that history; it is not silently reset for each byte. Legal MFM transitions
therefore occur after nominal 4, 6, or 8 us gaps.

Two address-mark encodings deliberately violate the ordinary clock rule:

| Decoded byte | Raw 16-bit clock/data word | Use |
| --- | --- | --- |
| A1 | `0x4489` | three-word sync before FE, FB, or F8 |
| C2 | `0x5224` | index/format synchronization when supplied by Write Track |

Only the missing-clock raw form establishes sync. Ordinary payload A1/C2 bytes
must never be mistaken for marks.

After a special raw word, ordinary-encoder history takes the decoded byte’s
last data bit: missing-clock A1 leaves `previous_data=1`, and C2 leaves
`previous_data=0`. The following ordinary byte is encoded from that state.

### 14.2 Read pipeline

The read pipeline is explicitly staged:

```text
asynchronous RDATA pulse
 -> synchronizer/edge timestamp
 -> gap classifier (4/6/8 us)
 -> clock/data bit reconstruction
 -> 16-bit MFM word and decoded byte
 -> missing-clock sync detector
 -> ID/DAM/data parser
 -> CRC and operation FSM
```

Every stage has valid/error signaling and an explicit invalidate input. Loss of
gap lock invalidates partial word, sync count, field parser, and CRC together.
Reacquisition requires a legal missing-clock sequence; stale A1 count cannot
survive a side change, step, write, motor loss, disk change, request boundary,
or reset.

Continuous separator state and command parser state are distinct. While
`read_path_valid`, the gap/DPLL/clock-data/byte-framing stages run before and
between commands so Read Track can enter an index boundary with established
phase. A request boundary resets ID/DAM/CRC/A1 command state, not a healthy
separator phase. Missing-clock A1 reacquires address-mark/parser sync after a
loss; it is not an excuse to omit all initial gap bytes. Read Track requires
separator lock before arming its starting index. Failure to lock before the
non-reloadable 300 ms start watchdog expires reports Lost Data/RNF rather than
claiming bytes it could not frame; a raw or rejected index never restarts that
watchdog.

### 14.3 Gap classification

Classification starts from physical time, then converts to rounded cycle
bounds. It MUST cover the mechanism’s DD read-window error (approximately
600–700 ns) plus measured speed variation without allowing adjacent 4/6/8 us
classes to overlap. Lower/upper accepted edges use section 11.2's inward
ceil/floor rule. Initial characterization targets are approximately:

| Class | Nominal | Characterization window before measured tuning |
| --- | ---: | ---: |
| short | 4 us | 3.2–4.8 us |
| medium | 6 us | 5.16–6.84 us (258–342 cycles) |
| long | 8 us | 7.1–8.9 us |

Intervals in the separation bands are ambiguous and cause loss of lock rather
than being rounded optimistically. Intervals below the qualified noise floor
are glitches; overlong intervals are missing data/loss of lock. Production
bounds MUST be frozen from captures at outer, middle, and inner cylinders on
every supported mechanism profile and tested with randomized phase/jitter.

### 14.4 Address-mark parser

The parser recognizes only:

- exactly three consecutive missing-clock A1 words followed by FE for an ID;
- exactly three consecutive missing-clock A1 words followed by FB for a normal
  data field;
- exactly three consecutive missing-clock A1 words followed by F8 for a
  deleted data field.

After FE it collects C, H, R, N and the two stored CRC bytes. After FB/F8 it
collects the N-derived field length for generic parsing, but the issue-#90 WD
request accepts only N=2 and protects the 512-byte buffer from all other sizes.
Parser counters are range checked. An FE/FB/F8 value in data or a gap cannot
start a record without the missing-clock sync.

### 14.5 CRC sequencing

The CRC-16 polynomial, initialization, and byte order are in section 6.5. The
implementation MUST reset CRC once before the first sync A1, then feed all
three decoded A1 bytes and the following mark/field. It MUST NOT reset CRC on
each A1. CRC consumes decoded bytes, never the raw 16-bit MFM words.

The parser retains actual stored CRC high/low bytes for Read Address and
diagnostics. Separate CRC contexts or explicit phase resets prevent an ID CRC
from leaking into the data CRC. Unit tests use both known vectors and the
zero-residue property after consuming stored CRC.

For generated CRC fields, snapshot the complete 16-bit remainder before the
first CRC byte, emit that snapshot high byte then low byte, and do not feed the
emitted high byte back into the live generator before choosing the low byte.
F7 makes this snapshot atomically when its host token is consumed and occupies
two full magnetic byte times. Sector-write ID/data CRC generation follows the
same snapshot rule.

### 14.6 Write-byte and Write-Track token handling

The normal encoder accepts a byte plus an explicit encoding mode. F5/F6/F7 are
special only when the active WD command is Write Track:

| Write Track input | Magnetic action |
| --- | --- |
| F5 | emit missing-clock A1 (`0x4489`) and apply the WD MFM address-mark CRC preset |
| F6 | emit missing-clock C2 (`0x5224`) |
| F7 | emit current generated CRC high byte and then low byte |
| any other byte | emit ordinary MFM byte and include it in CRC when the current formatting phase requires |

During Write Sector, user payload bytes F5, F6, and F7 are ordinary data. A
shared encoder that interprets them globally would silently corrupt files and
is prohibited. Read Track returns decoded A1/C2 byte values; it never translates
them back into F5/F6 tokens.

The WD F5 preset MUST yield the same CRC state as initializing to `0xFFFF` and
feeding `A1 A1 A1`, namely `0xCDB4`, before FE/FB/F8 is consumed. Do not naively
reset to `0xFFFF` for each of three F5 tokens and retain only one A1. Exact ID
and data CRC vectors in the formatter tests are the binding observable result.

### 14.7 Service-manual layout and exact stock-ROM format stream

The decoder accepts legal gap variation. The service-manual conformance recipe
for each of ten standard physical records is:

```text
12 x 00
 3 x missing-clock A1
 1 x FE
 1 x C
 1 x H
 1 x R (`0x01` through `0x0A`)
 1 x 02
 2 x generated ID CRC, high then low
22 x 4E
12 x 00
 3 x missing-clock A1
 1 x FB
512 x data
 2 x generated data CRC, high then low
38 x 4E
```

The service manual text “22 bytes hex 22” is a typographical error; physical
captures and the MFM convention establish 22 bytes of `4E`. Each record is 612
decoded byte times; ten records consume 6,120. A nominal 200 ms revolution has
6,250 byte times, leaving about 130 for index/track filler. Across a 197–203 ms
qualified period, the measured budget is approximately 6,156–6,344 byte times.

That 6,120-byte template is **not** the exact token trace emitted by the bundled
318045-02 ROM. The verified binary has an initial 32-decimal-byte `4E` loop
(`LDX #32`, binary offset `0x43EC`, archived `MROUT` path) and initializes the
per-record trailing `gap3` to 35 decimal (`0x23`, binary offset `0x30E7`,
archived `DSKINT` path). Its standard format is therefore:

```text
32 x 4E initial gap

repeat for R = 01 through 0A:
  12 x 00
   3 x missing-clock A1 (three F5 host tokens)
   1 x FE
   1 x C, 1 x H, 1 x R, 1 x 02
   2 x generated ID CRC (one F7 host token, two magnetic byte-times)
  22 x 4E
  12 x 00
   3 x missing-clock A1
   1 x FB
 512 x data
   2 x generated data CRC (one F7 host token, two magnetic byte-times)
  35 x 4E
```

Each stock-ROM record consumes 609 magnetic byte-times, so the complete defined
stock stream consumes `32 + 10 * 609 = 6,122` magnetic byte-times or 195.904 ms.
The last required data-CRC byte ends at magnetic byte-time 6,087; the remaining
35 are trailing filler. Keep host-token count separate from magnetic byte-time
count because each F7 consumes one host byte but emits two CRC bytes.

Define `N_format_required_max` as the maximum magnetic byte-time through the
last required token of every advertised 1581 ROM formatter. Its initial stock
value is 6,122. An approved replacement/Jiffy profile must supply a captured
token trace and its own value; if that value cannot meet section 13.3's capacity
inequality, physical Write Track is disabled for that ROM rather than silently
truncating meaningful content.

Write Track reproduces the ROM-supplied token stream rather than overriding it
with either template. It writes ordinary `4E` filler as commanded only until the
conservative tail close in section 13.3; later host tokens are consumed for WD
timing but magnetically suppressed while the command waits for the real ending
index. Suppression MUST NOT begin before `N_format_required_max` has completed;
additional post-profile filler may be cut before the boundary. It MUST NOT
write a fixed 6,250 bytes or run across index on a fast/missing-index revolution.

### 14.8 Sector-write splice

Write Sector preserves the existing ID field. After a matching valid ID and ID
CRC, it counts the WD double-density post-ID interval (22 byte times), then
writes:

```text
12 x 00, 3 x missing-clock A1, FB or F8,
512 payload bytes, generated CRC high/low, 1 x ordinary MFM FF
```

WGATE asserts at the WD-defined point after the 22-byte count and deasserts
after that one FF. There is no configurable trailing-4E count in Write Sector.
Scope capture validates the fixed sequence, splice placement, and following-ID
preservation; it does not tune the stream away from WD behavior. The writer
closes at its planned boundary even if read-data pulses continue; RDATA is
ignored during writing and recovery.

The magnetic stream after WGATE assertion is exactly 531 decoded byte-times:
12 + 3 + 1 + 512 + 2 + 1 = 531, or 16.992 ms. A separate Write-Sector duration
counter lives in `physical_1581_outer_safety` on raw 100 MHz, not in the writer
FSM that it protects. It starts on the exact edge where the dedicated final IOB
register drives WGATE active with the stable `writer_class=SECTOR` tag. It is not
paused or reloaded by `fdc_clk`, serializer, FIFO, CRC, request, result, or CPU
activity.

Let `D_sector_connector_delta_max` be the board-profile worst positive
difference between connector deassertion propagation and assertion propagation,
including IOB, buffer, cable, voltage, and PVT uncertainty. Program the outer
deadline as:

```text
T_sector_iob_force = 17.100 ms - D_sector_connector_delta_max
N_sector_iob_force = floor(T_sector_iob_force * 100,000,000)
```

The raw counter starts at zero on the final-IOB WGATE-active edge and forces on
the `N_sector_iob_force`th complete 100-MHz interval; it never rounds up. The
normal planned close MUST occur earlier and is not allowed to consume this
damage-limiter margin. If the expression is nonpositive or inward rounding
invalidates the normal-close proof, sector writing is disabled.

At that no-later-than IOB duration the outer block makes WDATA inactive no later than WGATE
and forces WGATE inactive. Therefore the measured connector WGATE-low duration
is at most 17.100 ms; no loopback or late synchronized “connector observed”
event is assumed. If the delta cannot be bounded positively with measurement,
sector write stays disabled. Expiry records Internal Fault and possible media
damage and runs the 700 us guard. If WD-done already committed, use the tagged
late-fault channel rather than creating a second result/INTRQ. The deadline is a
damage limiter, never permission to extend the normal 16.992 ms stream.

The outer/functional firewalls also receive the distinct fast-index close
request for a sector writer. That path has the same immediate-close priority as
raw change/WP and is independent of the 17.100-ms duration counter.

### 14.9 WDATA pulse generation and precompensation

Every encoded magnetic transition produces one active-low WDATA pulse. Target
pulse width is 0.5 us (25 cycles at 50 MHz), always within the reference
mechanism’s 0.1–1.1 us accepted width. The next transition time, not pulse
width, carries the MFM information.

WGATE and WDATA have an explicit envelope. The serializer begins the first
eligible channel half-cell nominally 2 us after connector WGATE assertion. MFM
content can defer the first actual transition, but its 8 us maximum legal gap
means the first WDATA active edge must occur no later than the qualified 8 us
WGATE-to-WDATA limit. Absence of that first pulse by the limit closes/faults
instead of erasing silently. After the last intended transition pulse has
returned high, WGATE remains active nominally 2 us and becomes inactive no later
than 8 us. Every *normally completed* WDATA pulse, including its 0.5 us low
width, lies wholly inside the connector WGATE-low interval. The 8-us first-pulse
watchdog applies to every writer. The 17.100-ms duration deadline applies only
to Write Sector; `T_tail_close` and the ending-index watchdog apply only to
Write Track.

Emergency close has higher priority than pulse completion. Raw WP/change,
hard-fail/reset, a distinct fast index, tail deadline, or writer fault forces
WDATA inactive no later than WGATE and may truncate the current 0.5 us pulse.
The event/fault is recorded as its command semantics require; it never delays
close merely to satisfy the normal trailing envelope. Exact leading/
trailing and emergency-skew values are checked at both FPGA buffer and mechanism connector and may
be tightened, never relaxed beyond the mechanism-qualified 8 us maximum.

Pattern-dependent WD write precompensation MUST be retained from or validated
against the MEGA65 encoder design. When command P is zero, the local raw-MFM
transition context `X110` or `0001` moves the target transition approximately
187 ns early, `X011` or `1000` moves it approximately 187 ns late, and other
contexts remain nominal. When P is one, every transition remains nominal.

The profile realizes this as 180 ns/nine 50 MHz cycles by default (or a
separately qualified 200 ns/ten-cycle profile) while
leaving WDATA width legal. Production constants are compile-time/profile
constants established by read-back tests, not writable debug registers.
Qualification tests both P states at cylinders 0, 40, 78, and 79. The encoder
must prove monotonically increasing transition times; precompensation can never
reorder or merge pulses.

### 14.10 Magnetic-write safety assertions

Simulation, formal checks where practical, and an on-chip capture MUST prove:

- WGATE low implies current source/media/request identities, drive A selected, media_ready,
  side settled, writable media, authorized writer state, and live watchdog;
- every normally completed WDATA low pulse occurs wholly inside authorized
  WGATE; an emergency clamp may truncate it but makes WDATA inactive no later
  than WGATE;
- no STEP/DIR/SIDE/SELECT/MOTOR/DENSITY change occurs from WGATE assertion
  through 700 us after deassertion;
- missing clock, reset, source change, disk change, or write protect cannot
  leave WGATE low;
- only one writer drives each output;
- after a formatter underflow or Force Interrupt, the drive reaches inactive
  WGATE before acknowledging safe completion.

## 15. User-visible media source and transition protocol

### 15.1 Menu contract

Use the minimal saved toggle immediately after the existing drive-8 mount line:

```text
Use internal 1581: Off / On
```

Off means Image and is the default after a new configuration, missing/old
configuration, factory reset, unsupported board, or capability failure. The
existing `8:%s` mount item remains present: an image may stay mounted while
disconnected, and its filename remains visible. The menu help text MUST explain:

- Internal 1581 uses the real DD mechanism as IEC device 8;
- a mounted image is preserved and becomes active again when switched off;
- external IEC device 8 conflicts with the internal simulated 1581;
- genuine DD media is supported; HD/ED/USB media are not;
- a pending switch waits for safe drive/cache quiescence.

The selected OSM bit is `desired_source`, not the live mechanics mux. The UI
shows `switch pending` until `active_source` changes. No raw
`qnice_osm_control_i`/`main_osm_control_i` bit may directly select pins,
responses, buffer ownership, or `sd_*` requests.

The current OSM is a shared static `config.vhd` menu; `G_BOARD` cannot by
itself remove one line. Therefore bind this behavior: the line remains visible
on an unqualified target, but On is rejected through a new nonfatal menu path,
the saved bit is forced back Off, active source remains Image, and the user sees
“Internal 1581 unsupported on this board.” Do not reuse the existing callback
error return that enters `FATAL`; implement an explicit nonfatal rejection
message/state. A later per-board dynamic menu may hide the line, but is not
required for issue #90.

The `G_BOARD`-derived capability in `main.vhd` and the final firewall always
forces unqualified hardware inactive even if UI or saved state is corrupted.

### 15.2 Desired versus active source

Identity ownership is singular. The source manager owns source/engine state and
the two global generations:

- `desired_source`: synchronized saved menu choice;
- `active_source`: latched backend used by the complete current command;
- `active_image_engine`: latched `ENGINE_1541_D64` or `ENGINE_1581_D81` while
  Image is active, and the staged engine to release when returning from Physical;
- `old_drive_engine`: transaction-local
  `(active_source == Physical) ? ENGINE_1581_PHYSICAL : active_image_engine`;
  only this value selects the upper-cache drain, so a staged D64 cannot bypass
  the running physical 1581 cache;
- `source_epoch[15:0]`: changes on active-source commit or controlled endpoint
  reset;
- `physical_media_generation[15:0]`: a retained nonzero physical-medium tag;
  it advances on every entry from Image to Physical and once when each new
  disk-change event from section 13.5 is accepted. Image publishes zero but
  does not erase the retained physical counter.

The WD frontend is the sole allocator of per-command/per-operation identities:

- `wd_command_id[15:0]`: one Busy parent command;
- `request_id[15:0]`: increments per accepted backend child operation within
  the source epoch, including every Type-I step and Multiple-sector iteration;
- `buffer_generation[15:0]`: changes per collected Write Sector buffer.

The WD frontend requests the endpoint/source-epoch rollover before one of its
allocators would enter a reserved range; it never increments `source_epoch` or
`physical_media_generation` itself. The physical controller only latches and
echoes supplied identities. No second block may maintain a shadow counter and
infer that it is current.

Before the first control-generation broadcast of every newly committed
Physical epoch, the source manager allocates the physical tag. Cold/first entry
establishes `0x0001`; every later Image-to-Physical entry advances the retained
nonzero value even if no change pulse was observed, because media may have been
replaced while the physical input/controller was inactive. If that advance
would pass `0xFFFF`, the already-held source transition performs the full
endpoint/FIFO/buffer clear and establishes `0x0001`; zero is never published in
Physical. A disk-change latch already pending at entry waits until this initial
tuple is acknowledged, then emits an event naming that nonzero old generation
and causes its own single additional advance. A source-epoch rollover that
stays in Physical may retain the same nonzero media tag because the changed
source epoch already prevents aliasing.

It also owns `switch_pending`, `source_switch_reset`, and acknowledgements from
the WD front end, physical backend, image/vdrive path, and IEC-drive reset
tree. It publishes each new `(source_epoch, physical_media_generation)` tuple
through the stable broadcast/dual-ack handshake in section 17.3. Every physical
request, byte/token, buffer, and response carries source
epoch, physical-media generation, and request ID as applicable. Image requests
use media generation zero. Response muxing uses these latched identities, never
the current menu bit.

A normal source commit cannot advance source epoch with an unretired request.
Hard reset is the explicit exception: it asynchronously clears valid/toggle
state at both handshake endpoints, invalidates buffers/FIFOs, and only then
establishes a new epoch after synchronized reset release. Sixteen-bit wrap is
never ordinary modulo arithmetic:

- `0x0000` is reserved as invalid for source epoch, physical-media generation,
  WD command ID, request ID, and buffer generation; image mode's fixed “no
  physical medium” tag is the sole media-generation zero and is distinguished
  by source;
- before source epoch `0xFFFF` would advance, hold admission, drain/retire, reset
  and acknowledge both endpoints/FIFOs/buffers, then establish epoch `0x0001`;
- after request `0xFFFF` retires, accept no new request until the same endpoint
  clear advances source epoch and restarts request IDs at `0x0001`;
- before allocating buffer generation after `0xFFFF`, retire/invalidate every
  buffer owner, perform the endpoint clear, and restart at `0x0001`;
- if disk change arrives while physical-media generation is `0xFFFF`,
  the physical raw path immediately kills/inhibits a writer and emits its
  lossless old-generation event; accepting that event sets source-manager
  `media_wrap_pending`, invalidates/cancels the active request, but never
  publishes generation zero. After safe close/guard, hold physical admission,
  clear both endpoints, then establish physical generation `0x0001` with disk
  change still latched; and
- no equality comparator may treat a wrapped value as current until that full
  clear acknowledgement. Hard reset uses the same invalid-then-establish rule.

A parent command is never stranded at the boundary. Bind
`MAX_CHILD_REQUESTS_PER_WD_COMMAND = 257`: up to 255 Restore/Seek pulses, one
final Verify/search, and one margin request. Multiple mode is separately capped
at 256 child sectors and terminates before R or its iteration counter wraps; a
standard 1581 reaches RNF after sector 10 much earlier. While WD is idle, if the
next request ID is greater than `0xFEFF`, or a Multiple write lacks the same
buffer-generation reserve, perform the endpoint/source-epoch rollover *before*
issuing its first child. The preflight normally happens immediately after the
prior command retires and completes within 8 us.
`endpoint_preflight_in_progress` is a complete WD command-admission state from
the first endpoint-clear request through the last clear/new-epoch
acknowledgement. A one-entry `parent_command_pending` latch observes every WD
Command-write cycle in that entire state. The first non-Force Command write
latches all parent fields, becomes the Busy parent, and meets the normal 24 us
Busy-visibility rule measured from that actual CPU write; no child may issue
until clear/new-epoch acknowledgement. Every later non-Force Command write is
ignored because that parent is Busy.

D0/D4/D8/DC has normal Force priority in every preflight cycle. With a pending
parent, apply section 10.10's active-command Force semantics, discard the parent
without ever issuing a child, and retire its reserved ownership exactly once.
With no pending parent, apply the idle Force semantics. An index-conditioned
request remains armed/tagged only as section 10.10 permits and cannot resurrect
the retired epoch. Track/Sector/Data register access continues under the normal
16-us same-register rule. A non-reloadable 1.000-ms preflight watchdog starts
with the first endpoint-clear request. Expiry terminally faults a latched parent
rather than leaving Busy; with no parent it latches the controller fault and
rejects the next normal command until the specified fault recovery/reset.
Acknowledgements, Command writes, Force, pause, and stale endpoint traffic do
not restart that watchdog. The normal <=8-us path is a performance requirement;
1.000 ms is only the fault-containment ceiling.
An invariant proves the reserved range cannot be
exhausted by the accepted parent; an unexpected extra child is Internal Fault,
not modulo wrap. Apply the same no-alias preflight to internal `wd_command_id`.

Assertions and accelerated long-run tests force every counter through
`0xFFFE`, `0xFFFF`, wrap-pending, endpoint clear, and `0x0001`, including disk
change in every request/write phase. Wider profile/content counters follow the
same no-alias rule at their own overflow.

### 15.3 Upper drive-computer caches and durability proof

#### 15.3.1 Resident 1581 side cache: exact stock-ROM behavior

The source switch cannot be made safe by observing only WD Busy, IEC inactivity,
or the lower `vdrives.cache_dirty` flag. The 1581 DOS owns a separate write-back
cache in its own RAM. It can acknowledge a file/block write while the modified
physical side is still only in that RAM.

For the bundled 318045-02 profile, the following facts are binding:

| Item | Stock-ROM fact |
| --- | --- |
| Cache storage | `$0C00-$1FFF`, 20 pages = 5,120 bytes |
| Cached unit | one physical side: ten N=2 records x 512 bytes |
| Dirty byte | zero-page `$0087`; normal dirty value `$80`, clean `$00` |
| Cached track | `$0095` |
| translated/current side | `$0096` / `$0097` |
| live idle counter / reload | `$009C` / `$009D` |
| timer-B latch | `$4E20` 2 MHz phi2 counts = 10 ms per controller tick |
| default reload | `$20`, loaded on each IEC ATN |
| normal dirty set examples | ROM `$CF92` and `$BF20` paths |
| successful whole-side clear | `ASL $87` in the `$C9E1-$C9ED` completion path, after all ten Write Sector operations and optional verify |
| idle flush call | `$B151-$B16F`, including the public `jdumptrk` path through vector `$FF6C` |
| replacement flush | dirty old track/side path around `$C11D-$C12E` |

The default idle trigger is phase-dependent approximately 310–320 ms after the
last ATN, not 250 ms and not a durable completion promise. DOS command `U0>I`
writes an arbitrary byte directly to `$009D`, with no range check: values 0, 1,
32, and 255 correspond to markedly different behavior, with 255 reaching about
2.54–2.55 seconds before the idle dump is merely *started*. `U0>R` can also
raise the retry count. Media rotation, retry, verify, write guard, and error
recovery make final retirement longer and data dependent. The present pause
path freezes the c1581 divider and therefore freezes the ROM timer. No fixed
500 ms, 640 ms, or hash-derived wall delay proves this cache clean.

Nor does `$0087 == 0` alone prove that data reached the old medium. Besides the
successful path, the stock program clears or invalidates dirty state on:

- controller error around `$CDCC-$CDDB`;
- disk change around `$CE39-$CE48`;
- drive reset around `$C2F1-$C2F8`;
- burst fast-write failure around `$BC27-$BC2D`;
- a deliberate BUFMOVE mark-clear path around `$CEA4-$CEAD`;
- a user memory-write (`M-W`) to zero page; and
- other future code in an unrecognized replacement ROM.

Consequently, the implementation MUST snoop T65 writes to `$0087` and classify
them using the effective-ROM profile and execution context; it MUST NOT consume
the second port of the drive RAM merely to poll this byte. The stock profile
exposes at least these state signals in the drive clock domain and transfers a
coherent snapshot to the source manager:

- `rom_profile_known`: the effective 32 KiB bytes match an allowed digest;
- `rom_cache_state_valid`: every dirty-byte transition since profile/reset
  establishment was recognized and no direct/ambiguous mutation occurred;
- `rom_cache_dirty`: the shadow of the classified `$0087` state;
- `rom_cache_discard_or_fault`: sticky in the current drain generation after
  reset, disk change, controller error, burst failure, unexpected clear, or
  profile loss;
- `rom_flush_success`: a generation-tagged successful completion, backed by
  the stock success path *and* error-free retirement of the corresponding WD/
  backend writes; and
- `rom_media_work_seen`: sticky after the drive has accepted media-modifying
  work in the current drive generation.

Use the T65's existing `sync` output to latch `cpu_a[15:0]` on each qualified
opcode fetch, then correlate that `last_opcode_pc` with the existing
`ph2_f & ~cpu_rw & ram_cs` RAM-write strobe and data. For example, the bundled
binary's successful clear instruction is the `ASL $87` opcode fetched at
`$C9EB`; the destination bus address by itself is only `$0087` and cannot
distinguish success from error, reset, `M-W`, or deliberate discard. The profile
monitor is a side-effect-free observer: it must not stall the T65, alter RAM
data, or assume an unconnected/default T65 debug signal. Simulation locks the
fetch/write phasing before hardware use.

The low-level backend must therefore export terminal success/error retirement;
the absence of Busy is not success. `c1581_cache_clean` means the conjunction
of a known, valid profile; classified clean shadow; no active cache transfer,
WD request, DRQ, or owned result; no drain-generation discard/fault; and, when
the generation began dirty, a matching `rom_flush_success`. A clean state seen
at fresh, recognized reset is valid only before media-modifying work is
accepted. A reset or disk-change clear during a pending switch aborts that
switch; it never masquerades as a flush.

At the time of this specification, only the bundled digest in section 2.3 is
qualified for a data-preserving *live* source switch. The repository contains
no licensed `jd-c1581.bin`; JiffyDOS is a user-supplied commercial replacement.
It remains usable for normal drive operation, but live source switching while
it is effective MUST be rejected until that exact digest has a separately
reviewed dirty-state/flush profile and black-box trace tests. A 32 KiB length,
Jiffy menu selection, upload success, or stock-ROM fallback filename is not a
profile. If no replacement load occurred and the effective bytes are the stock
digest, the stock profile applies.

The existing ROM storage makes this distinction especially important.
`c1581_multi.sv` contains an immutable `romstd` BRAM and a writable custom
`rom` BRAM; both power-up from the stock MIF, and the Jiffy setting selects the
custom slot. The current loader does not provide content identity: an empty
load can leave the stock initialization, a short load makes a custom-prefix/
stock-tail hybrid, an interrupted/error load can leave partial changes, and a
file longer than 32 KiB can wrap the 15-bit address. “Loaded” and the selected
slot therefore say nothing reliable about executed bytes.

The implementation MUST add this state, with names or a bit-exact equivalent:

- `requested_rom_slot`, `active_rom_slot`, and `rom_slot_switch_pending`;
- custom-content state `INIT_STOCK`, `MUTATING`, `COMPLETE`, or
  `PARTIAL_ERROR`;
- monotonically changing `rom_content_generation`, exact accepted byte count,
  and a post-write full-range readback SHA-256;
- effective profile `STOCK_318045_02`, individually approved
  `JIFFY_<digest>`, `UNKNOWN`, or `MUTATING`; and
- `profile_epoch`, tied to the selected content generation and that profile's
  cache contract.

Any custom-BRAM write invalidates its digest/profile *before* the write becomes
visible and advances its content generation. A write to the active custom slot
is rejected until the old cache has completed the section 15.4 drain and the
drive is held reset; an implementation MUST NOT mutate code under a running T65.
After exactly 32,768 intended bytes, read back all addresses and compute the
digest; no filename-supplied digest substitutes for readback. Empty, short,
oversized, wrapped, interrupted, and readback-mismatched loads end in
`PARTIAL_ERROR`/`UNKNOWN`. The custom slot is recognized as stock only when its
readback bytes have the stock SHA-256. A normal drive reset does not restore the
writable BRAM; only FPGA configuration/reinitialization does.

#### 15.3.2 Resident 1541 GCR track cache in D64 image mode

Image mode is not synonymous with the 1581 engine. A mounted D64 selects the
`c1541_drv.sv` engine, whose live GCR track buffer is another upper cache above
`vdrives`. In the reviewed RTL, `c1541_gcr.we` sets local `track_modified`;
`save_track` toggles on a head move or when activity stops; and
`c1541_track.sv` converts that toggle into a variable-length `sd_wr`. The
current code clears `track_modified` when it merely *requests* that save, before
the `sd_ack` transfer and before lower-cache persistence. Reset or a new image
can also clear/cancel state. Therefore neither `act=0`, `busy=0`, the current
`track_modified=0`, nor lower `cache_dirty=0` alone is a durability proof.

The implementation MUST replace that early-clear heuristic with a
ROM-independent, generation-tagged contract:

- `active_image_engine` is latched as `ENGINE_1541_D64` or `ENGINE_1581_D81`;
  a mount/menu bit cannot change it under a running drive;
- `c1541_cache_generation[15:0]` advances for each newly loaded GCR track and
  follows the no-alias wrap rule in section 15.2;
- `c1541_track_dirty` sets on every committed GCR-buffer write (`we`), remains
  set across motor/activity changes, and clears only on matching successful
  upper-track save retirement;
- `c1541_flush_req/ack` carries source epoch, cache generation, physical D64
  track/half-track identity, block count, and a new drain generation;
- `c1541_flush_success` asserts only after the complete `c1541_track` SD write
  handshake retires without reset, mount/change, stale generation, range error,
  or lower-transfer error; request issuance and `sd_ack` assertion alone are not
  success;
- `c1541_flush_fault` is sticky per drain generation on reset, image change,
  track identity change, partial/duplicate ACK, timeout, or unexpected dirty
  clear; and
- `c1541_cache_clean` means clean generation plus no GCR write, save toggle,
  `c1541_track.busy`, `sd_rd/sd_wr`, buffer ownership, or unretired success/
  error response. If the drain began dirty, matching `c1541_flush_success` is
  additionally required.

An explicit drain request must cause the current dirty track to be saved even
if `act` never produces the expected edge. Do not reset the 1541 CPU, change
track, replace the image, or close its clock until the flush response retires.
Admission/quiet arbitration prevents a new IEC/GCR write from racing the clean
snapshot. Once the upper track save succeeds, the lower `vdrives` cache may
still be dirty and is drained separately in section 15.4. Direct GCR mode is
currently disabled; enabling it later requires the same dirty/save proof and
does not inherit qualification automatically.

Unlike the 1581 `$0087` monitor, this dirty signal observes the actual GCR
buffer write strobe and is independent of stock/Jiffy 1541 ROM contents. A
custom 1541 ROM is therefore live-switch eligible only insofar as every path to
the shared GCR buffer still passes through the observed write strobe; tests
mutate that assumption.

### 15.4 Data-preserving source, ROM, and soft-drive-reset transaction

On a desired/active mismatch, live 1581 ROM-bank/replacement request, active
Image mount/unmount/replacement/dtype change, or any non-hard request that would
reset the 1581/1541 drive computer, execute the following transaction. Changing
source/engine/image/ROM first or pulsing drive reset first is forbidden. While
Physical, a clean disconnected image change may update only staged image state;
it cannot select an engine until the return transaction. A C64 soft reset may reset the C64 CPU immediately, but its drive-
reset branch is held off until this transaction commits; on drain failure the
drive remains running on the old source/profile and the user receives a warning.

1. Snapshot transaction cause, optional `pending_target`, `active_source`,
   source/media generations, `active_image_engine`, derived `old_drive_engine`,
   effective ROM profile, and a new `drain_generation`; set
   `switch_pending`/`reset_pending` as applicable. Leave the old source, running
   engine, staged image engine, and ROM active.
2. Branch on `old_drive_engine`. Once a running `ENGINE_1581_D81` or
   `ENGINE_1581_PHYSICAL` has been
   released from cold reset, an unknown/invalid effective profile rejects the
   live change with “Restart required to change 1581 source with this drive
   ROM.” `ENGINE_1541_D64` instead uses its ROM-independent GCR-write monitor;
   an invalid/missing monitor rejects with “1541 track cache cannot be drained.”
   Never silently substitute reset-and-discard for either proof.
3. Continue the old engine and backend. For 1581, allow the ROM to dump its dirty
   side and do not close WD intake while `rom_cache_dirty` is set. For 1541,
   allow any current IEC/GCR activity to retire, then issue the explicit tagged
   `c1541_flush_req` if dirty. Keep the selected drive divider and cache engine
   running even if the rest of the core/menu is paused; pending drain overrides
   ordinary drive pause.
4. Independently require a race-avoidance quiet window of at least 500 ms during
   which IEC ATN/CLK/DATA are released/inactive and no drive work event occurs.
   This window prevents a new host operation from crossing the handoff; it is
   expressly not cache-clean evidence. Reset it on any raw or synchronized IEC
   activity; accepted WD register access/request; DRQ/INTRQ assertion or owned
   result; classified dirty-byte, `$0C00-$1FFF` cache write, 1541 GCR-buffer
   write/save/track-change, upper-cache success/fault event; command-owned
   backend byte/result; or lower-cache write/storage request. Ambient index,
   RDATA transitions while no read is active, stable
   motor rotation, and read-only RAM fetches do not reset the window; doing so
   would make an idle spinning physical drive impossible to switch.
5. At one arbitration boundary, require the quiet window and the selected
   engine's exact upper proof (`c1581_cache_clean` or `c1541_cache_clean`), plus
   its drive-computer/controller frontend idle, no owned DRQ/INTRQ/GCR-save
   result, and no active IEC transfer. Atomically assert only the held drive/IEC
   admission block. A same-boundary IEC/WD/cache event wins and restarts the
   quiet window; admission block must not win a race against newly accepted
   work. Keep the old drive clock, backend, writer close logic, and safety island
   alive. In particular, do **not** assert `source_switch_reset` at this point:
   WD-visible completion and upper-cache success can precede a final formatter
   byte, physical write-close, or guard retirement.
6. With admission blocked but the old drive and backend still running, retire
   the old lower/physical backend:

   - Any transaction whose old source is Image requires lower
     `cache_dirty = 0`, no `sd_rd/sd_wr`,
     `vdrives` idle, no owned image buffer/result, and a successful storage
     flush if the lower cache entered the transaction dirty.
   - Any transaction whose old source is Physical requires no physical request/response or stream
     ownership, WGATE/WDATA inactive, `raw_write_kill` settled as specified,
     and the 700 us post-write guard complete.

   Here `backend retired` is exact: for Physical it includes the distinct
   `write_closed` and `guard_done` acknowledgements even if WD Busy and the ROM
   dirty byte cleared earlier. For Image it includes the complete generation-
   matching lower storage flush, not merely absence of a new request. A failure
   result aborts while the old drive is still alive; mere idleness does not turn
   it into success. Rollback releases admission only after old ownership is
   coherent.
7. Only after steps 5 and 6 have acknowledged success, assert and hold
   `source_switch_reset`. The old backend is now retired, so reset cannot
   truncate an acknowledged final FF, cancel an unretired result, or evade the
   700 us guard.
8. Ask both request/response endpoints to clear, wait for their reset/idle
   acknowledgements, increment `source_epoch`, and invalidate decoder/FIFO/
   buffer/result state. A source transaction now latches the new source and its
   present/WP/change state and, when entering Image, the staged image engine; a
   ROM transaction latches the new verified slot/profile; a soft-drive reset
   retains both old selections. No stale toggle or buffer can survive this
   commit. When entering Physical, allocate/advance the retained nonzero media
   generation exactly as section 15.2 requires before publishing the new tuple.
9. Transfer `active_source` and epoch through the explicit drive/FDC-domain
   request/ack handshakes while reset remains asserted. Keep physical pins
   inactive for the reset/selection qualification interval.
10. Release reset synchronously in each domain only after its acknowledgement;
   release IEC admission last, then clear the applicable pending state.

A 120-second watchdog covers the complete pending/drain/reset transaction. On
expiry or any classified discard/error, restore `desired_source=active_source`,
keep the old source/ROM selected, clear pending after safely releasing any held
drive reset, and display a nonfatal reason. A soft-drive reset request is
rejected rather than discarding acknowledged drive-cache data. Do not force
through dirty data. A user selecting the already active source cancels a source
request by the same safe rollback.

Cold boot/hard reset is distinct: while both media backends and the drive have remained in
reset and the selected engine's `upper_media_work_seen=0`, the saved source may be selected before the
first reset release without a live cache drain, including with an unknown ROM.
A genuine hard reset may likewise discard volatile cache by definition, but
must record/report possible acknowledged-data loss and must never be presented
as a data-preserving live switch or ordinary soft reset. The UI tells an
unknown-ROM user to save the desired source and perform that explicit restart.

Test and document the current ROM-loading path as part of this transaction. A
finite reset after changing `rom_std_i` is insufficient: the present
`prevent_reset` logic observes only lower `vdrives.cache_dirty`, not `$0087`.
Effective-ROM selection must be latched until the old profile has drained and
the drive is held reset; the new profile starts unknown until its effective
bytes are identified.

### 15.5 Image-mode isolation

While active source is Image:

- existing image present, write-protect, mount, D64/D81, `sd_*`, and
  `vdrives` behavior is unchanged;
- every physical output is inactive;
- physical input activity cannot alter WD/CIA state;
- physical backend state is reset/inactive and no completion is accepted.

While active source is Internal 1581:

- `c1581_drv.sv` remains instantiated/present even with an empty mechanism;
- geometry is fixed to 80 x 2 x 10 x 512 for supported operations;
- no request reaches `vdrives` and no image acknowledgment reaches the FDC;
- the mounted image stays mounted and clean but disconnected;
- physical present/change/write-protect/ready are authoritative.

Image and physical acknowledgements MUST be assertion-checked as mutually
exclusive for every source/media/request identity.

### 15.6 IEC device-number and serial behavior

The feature is still the one internal simulated 1581 at IEC device 8;
`G_VDNUM`/`C_VDNUM` remains one and no second virtual-drive buffer is added.
Existing drive 9 behavior must continue to coexist. An external real IEC drive
configured as device 8 creates a protocol/double-responder conflict; the
current internal response combination is not assumed to create literal
connector electrical contention. Automatic detection is out of scope, so the
FAQ/menu help MUST warn users to renumber or disconnect it.

Retain the existing IEC and fast-serial wiring without claiming C128 burst
support. The current C64 core lacks the C128 fast-serial input clock and
`iec_drive.sv` ties that input inactive; JiffyDOS over normal CLK/DATA is the
available acceleration path.

## 16. Reset, pause, reconfiguration, and clock-loss behavior

### 16.1 Reset classes

Treat these as distinct events:

| Event | Required behavior |
| --- | --- |
| FPGA configuration / PLL unlock / hard reset | immediately clamp outputs inactive; WGATE safety wins over media integrity; invalidate all identities/endpoints |
| Normal user/core soft reset | reset the C64 side as requested, but route the drive-reset branch through section 15.4 admission, upper-drive-cache drain, lower flush, held reset, and bounded reject; an active writer is not the only dirty state |
| Drive-local source/ROM/reset transaction | section 15.4 data-preserving protocol; reset only after the old drive engine/cache and backend have retired successfully |
| Direct 1581/1541 CPU reset request | treat as the same non-hard data-preserving drive transaction; no stale WD/result survives after commit, and failure leaves the old drive running rather than discarding acknowledged cache |
| Menu open / core pause | physical 50 MHz timers always continue; while Physical is active the selected 1581 CPU/WD/CIA divider never pauses, including idle motor-off retirement; a transition to Image drains first; no pin, maintained motor/select request, or token producer may freeze active |
| Loss of 50 MHz safety clock | independently generated `hard_fail` asynchronously presets or disables output IOB/OE to inactive; release is synchronized only after clocks/reset are proven stable and never relies on the stopped clock detecting itself |
| Bitstream reconfiguration | same as hard reset from the first configuration-time interval |

A hard reset during magnetic writing can corrupt the current sector and can
discard upper/lower drive cache, but it must minimize the affected span by
deasserting WGATE immediately and record the durability-loss cause. A soft
reset must drain acknowledged cache and use controlled close while the trusted
physical clock is running; it is rejected if those conditions cannot complete.
No reset path waits indefinitely for index, CPU firmware, or a backend
acknowledgement.

### 16.2 Continuously running safety island

The safety block, raw write-protect clamp, WGATE/WDATA serializer close logic,
post-write timer, and reset classifier form a continuously running island on
`fdc_clk`. C64 turbo changes, VIC timing, IEC clock stretching, QNICE menu
activity, and drive-CPU clock enable do not pause it. Any enable that could
stop this island while SELECT or WGATE is active is a design error.

Pause arbitration also protects the producer and maintained CIA outputs.
`active_source=Physical` by itself asserts `physical_drive_must_run` for the
entire selected-source epoch: ordinary UI/core pause never gates the 1581 CPU/
WD/CIA divider in Physical mode. This lets ROM motor/selection timers run to
release the real mechanism even while no WD command is active and prevents the
issue-#110 “motor frozen on” failure class. The signal also covers any old
physical parent/child/request/result/cancel, record/track FIFO or buffer owner,
DRQ/INTRQ, `ARMED_FIRST_TOKEN`, writer/tail/guard/late-fault state, or source/ROM/
cache drain while a source transition is leaving Physical.

While it is set, ordinary OSM/core pause is acknowledged to the C64/display side
as existing behavior permits but is overridden for the selected 1581 CPU clock-
enable, WD frontend, CIA, CDC bridges, and relevant cache engine. No synthetic
Force is injected. There is no drive-pause acknowledgement during an active
Physical epoch. It becomes eligible only after a source transaction has retired
the old physical parent, close, guard, motor/selection ownership, and endpoint
state, committed Image, and reached an instruction-safe drive boundary. Every
underlying watchdog continues. Image mode retains existing pause behavior except
for the already-required drain override.

In particular, pausing during Write Track cannot freeze the ROM while the
serializer continues: DRQ/F7 service and token production run through magnetic
close and parent retirement. A zero substituted solely because the user opened
the menu is a test failure and possible media-integrity fault.

Clock-loss protection is outside that island and has a concrete integration:

1. A free-running heartbeat bit, implemented outside every physical-drive FSM,
   toggles once per 16 `fdc_clk` cycles (nominally every 320 ns). It is not gated
   by pause, mode, capability, reset of the drive CPU, or writer state.
2. `physical_1581_outer_safety` is instantiated in
   `CORE/vhdl/mega65.vhd`, where the existing raw board `clk_i` is explicitly
   documented as 100 MHz and remains independent of the QNICE/50 MHz state
   machine. It two-flop synchronizes the heartbeat and asserts
   `heartbeat_missing` after 128 consecutive `clk_i` cycles without a change.
   Including a just-missed heartbeat and synchronizer latency, the nominal
   worst-case detection is below 1.7 us and the binding connector-safe target is
   2 us plus the separately measured final clamp latency.
3. The framework clock generator MUST export its QNICE MMCM/PLL lock-valid
   indication to `MEGA65_Core`; the board wrapper MUST also pass the asynchronous
   board/global reset classification used during configuration. Existing
   `qnice_rst_i` is retained but is not accepted as the only clock-loss input,
   because it may itself depend on the stopped domain.
4. `heartbeat_missing`, loss of exported QNICE lock, asynchronous board/global
   reset, qualified mechanism-power/reset loss, FPGA GSR/configuration, or the inner hard-fault request forms
   `hard_fail_outer`. Assertion drives the asynchronous preset/clear or output-
   enable input of dedicated final IOB registers. Active-low MOTOR/SELECT/STEP/
   WGATE/WDATA become high; drive-B outputs remain high; SIDE/DIR/DENSITY take
   their board-profile safe values. No combinational/debug path bypasses these
   registers.
5. The polarity-qualified raw connector WP and CHANGE inputs independently
   feed asynchronously set `outer_write_kill` pins on the dedicated final
   WGATE/WDATA IOB/OE primitives. This path remains live even if `fdc_clk`, its
   heartbeat, or the inner functional FSM is stalled; it makes WDATA inactive
   no later than WGATE within `D_raw_kill_clamp_max`. It does not clamp MOTOR,
   SELECT, SIDE, DIR, DENSITY, or STEP and is not ORed into `hard_fail_outer`,
   so the normal mechanics guard remains possible. Deassertion follows only
   section 13.6's raw-100-MHz filtered release/ack protocol.
6. The outer block receives requested outputs from `main.vhd`; only its clamped
   outputs drive the `MEGA65_Core` physical ports. A synchronized copy of
   `hard_fail_outer` and sticky `outer_write_kill` return to the 50 MHz
   controller for state retirement and diagnostics, but that feedback is not
   the safety path.
7. WGATE has a separate 50->100 MHz arm handshake. The inner block holds
   `outer_writer_arm_valid`, class (`SECTOR`/`TRACK`), source/media/request
   identities, and the profiled duration/tail class stable until
   `outer_writer_arm_ack`. The outer block synchronizes the toggle, latches the
   complete payload while stable, and acknowledges before WGATE request can
   become active. At the exact final-IOB WGATE falling edge it requires a valid
   matching arm and latches that class/identity immutably through close. Unarmed,
   metastable, duplicate, changed, or mismatched class blocks/closes WGATE and
   asserts Internal Fault; it can never default to TRACK and thereby omit the
   sector duration limiter. Arm release uses a second acknowledgement only after
   final WGATE high and the close state is captured.

If raw 100 MHz `clk_i` also disappears, the exported MMCM/PLL lock or board reset
must still asynchronously force the same IOB/OE state. FPGA configuration-time
IO defaults and external pull-ups cover the interval before user logic exists.
If a board/framework revision cannot expose and prove such an independent
asynchronous indication, `G_PHYS1581_CAPABLE` remains false for that revision;
the specification does not pretend a stopped clock can diagnose itself.

Assertion of `hard_fail_outer` is asynchronous to obtain the fail-safe bound.
Deassertion is never asynchronous. The 100 MHz block first requires QNICE lock,
board reset release, and a changing heartbeat continuously for at least 1 ms,
then handshakes a release request into restored `fdc_clk`. The inner controller
must acknowledge `SAFE_RESET`, inactive requests, and cleared destructive
authorization before the outer block releases its IOB/OE registers on a 100 MHz
edge. Normal source/mechanism qualification starts only afterward.

Each board qualification identifies the raw 100 MHz clock, exported lock/reset,
heartbeat divider/timeout, asynchronous IOB/OE primitive, reset
polarity, IOB/OE implementation, external pull-ups, and measured connector
latency. If a revision cannot demonstrate this path during clock removal,
brownout, and FPGA reconfiguration while drive power remains present, physical
write/format capability stays compile-time disabled on that revision; read-only
experiments do not relax the output clamp.

### 16.3 Power-up invariants

Before reset release and until board capability, clock validity, source epoch,
and synchronized controls are known:

- active source is Image;
- published media generation is zero; no Physical tuple/event is legal until
  the source manager establishes a nonzero retained tag on Physical entry;
- drive A/B select and motors are inactive;
- WGATE, WDATA, and STEP are high;
- side/density/direction have qualified safe values;
- buffer/FIFO ownership is Invalid/Free;
- Ready is false and disk change is conservatively pending for physical media;
- `head_position_valid=0` and `restore_required=1`;
- no physical IRQ/completion can cross to the WD front end.

These properties must hold in post-configuration gate-level simulation where
practical and be checked at the connector during configuration on hardware.

## 17. Repository integration plan

### 17.1 Files to add

Add the reviewed modules from section 8.4 under
`CORE/vhdl/physical_1581/`. Add self-checking unit and integration benches at:

```text
CORE/vhdl/test/tb_physical_1581_inputs/
CORE/vhdl/test/tb_physical_1581_codec/
CORE/vhdl/test/tb_physical_1581_controller/
CORE/vhdl/test/tb_physical_1581_safety/
CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_physical.sv
tests/physical1581/
```

The pure-VHDL benches should follow the repository’s existing GHDL/Makefile
pattern. The standalone FDC bench drives WD registers and a mock physical
backend directly so it does not require a T65, 1581 ROM, or real mechanism.
Do not commit proprietary ROMs or copyrighted full-disk contents; generate
synthetic tracks, sectors, and corruptions reproducibly.

Add a board/mechanism qualification record under `doc/` with board revision,
mechanism model and straps, cable, instruments, bitstream SHA, measured
polarities/timings, destructive-media identifier, and pass/fail evidence.

### 17.2 Core-facing physical port set

Add these existing M2M top-level signal names unchanged to the `MEGA65_Core`
entity near its core-specific IEC ports, to `main` near its existing clock/IEC
ports, and through every board wrapper:

```text
f_density_o
f_diskchanged_i
f_index_i
f_motora_o
f_motorb_o
f_rdata_i
f_selecta_o
f_selectb_o
f_side1_o
f_stepdir_o
f_step_o
f_track0_i
f_wdata_o
f_wgate_o
f_writeprotect_i
```

Map physical inputs top -> `MEGA65_Core` -> `main` directly beside the existing
C64-specific IEC bypass. Map physical *output requests* from `main` to
`physical_1581_outer_safety` in `mega65.vhd`, and only that block's final IOB/OE
outputs to the top-level ports. Apply this structure in:

- `M2M/vhdl/top_mega65-r3.vhd`;
- `M2M/vhdl/top_mega65-r4.vhd`;
- `M2M/vhdl/top_mega65-r5.vhd`;
- `M2M/vhdl/top_mega65-r6.vhd`.

Remove the current static inactive top assignments only after the safety-block
outputs are connected. `f_motorb_o` and `f_selectb_o` remain hard-high constants
in that final safety block. `main` currently receives `c64_clk_sd_i` but not its
reset; add `c64_rst_sd_i`/equivalent and map the QNICE-domain reset explicitly.

The clock-fail path is also mandatory repository plumbing, not a future board
task:

- keep existing raw 100 MHz `clk_i` at `MEGA65_Core` and feed it to
  `physical_1581_outer_safety`;
- export `qnice_clk_locked_o` (or an exactly equivalent raw clock-generator
  lock-valid signal) from the framework through every board wrapper to
  `MEGA65_Core`; do not synthesize it from QNICE-domain activity;
- pass the asynchronous board/global reset classification needed by the final
  IOB/OE primitive; `qnice_rst_i` remains a separate functional reset;
- where common FPGA/mechanism reset cannot be proven, route the qualified raw
  mechanism-power-good/reset monitor directly to outer async clamp and inner
  one-way kill, plus a synchronized diagnostic copy; never route it only through
  `main` clocked logic;
- route polarity-qualified raw `f_writeprotect_i` and `f_diskchanged_i` in
  `mega65.vhd` directly to the final WGATE/WDATA `outer_write_kill` asynchronous
  safety pins as well as to their ordinary synchronized input paths; no
  `main.vhd` request, heartbeat, or functional-clock state lies in the clamp
  path, and these two media signals do not enter the all-output hard-fail net;
- export the free-running divide-16 QNICE heartbeat from `main`, and return only
  a synchronized diagnostic/retirement copy of `hard_fail_outer` to `main`;
- add the explicit outer writer-arm toggle handshake:
  `outer_writer_arm_valid/ack/release_ack`, `outer_writer_class`, source/media/
  request identity, and stable profile/deadline selector. WGATE request is held
  high until arm acknowledgement; payload is immutable through final close;
- add `outer_write_kill_release_valid/ack`; assertion of the kill is the direct
  asynchronous pin path and never waits for this release-only handshake;
- return lossless, sequence-tagged `outer_step_fell`/`outer_step_rose` events
  from the actual 100 MHz final-IOB register to the 50 MHz mechanics block. The
  synchronized trailing event plus `D_step_trailing_max` (and any added CDC
  latency) is the conservative settle reference; a requested pulse without both
  matching events faults/invalidate position;
- instantiate the final registers in `mega65.vhd`, mark/verify their IOB
  placement, and prohibit further output logic in the M2M top wrappers; and
- add named timing/CDC constraints for raw 100 MHz, QNICE heartbeat and writer-
  arm/STEP-event synchronizers and stable-payload handshakes, asynchronous preset/clear
  recovery/removal, and the exact final registers. Only paths into named asynchronous safety pins may receive a
  reviewed exception; no hierarchy wildcard is allowed.

Each R3/R4/R5/R6 project must elaborate this identical path. Capability may be
true only on profiles whose lock/reset source, IOB/OE primitive, external buffer,
and connector behavior pass SAFE-08 and Q-03.

### 17.3 Flat mixed-language physical ABI

VHDL records may be used inside the physical block, but the SystemVerilog/VHDL
boundary is a flat, versioned port ABI. All ports listed here are in the
50 MHz `clk_sys`/`fdc_clk` domain; `fdc1772.v` owns its WD/CPU-domain CDC.
Equivalent names are allowed, but width and semantics must be documented in
`physical_1581_pkg.vhd` and the SystemVerilog wrapper.

Direction/ownership is fixed:

| Group | Producer -> consumer |
| --- | --- |
| mode/capability/epoch policy | `main.vhd` source manager -> WD and physical blocks |
| request and cancel | `fdc1772.v` 50 MHz bridge -> physical controller |
| response and cancel acknowledgement | physical controller -> `fdc1772.v` bridge |
| media-change generation event | physical input/controller block -> `main.vhd` source manager |
| record-byte RX | physical decoder -> WD front end for Read Sector payload (ordinals 0–511) or Read Address C/H/R/N/CRC (0–5), at physical byte cadence |
| write-collection start | physical controller -> WD front end after first matching ID |
| exposed write-sector buffer port | `fdc1772.v` bridge -> dual-port RAM for address/write; RAM -> bridge for read; controller owns the serializer port after `READY_TO_WRITE` |
| track TX | WD front end -> physical writer (Write Track tokens) |
| track RX | physical reader -> WD front end (Read Track bytes/flags) |
| live normalized state | physical controller -> WD front end and source manager |

Configuration and request:

```text
phys_active_50, phys_capable
phys_control_generation_valid
phys_control_source_epoch[15:0], phys_control_media_generation[15:0]
phys_control_wd_generation_ack, phys_control_backend_generation_ack
phys_motor_req, phys_motor_ack
phys_side_req, phys_side_value, phys_side_ack
phys_req_valid, phys_req_ready
phys_req_source_epoch[15:0], phys_req_media_generation[15:0]
phys_req_id[15:0]
phys_req_op[3:0], phys_req_flags[15:0]
phys_req_track[7:0], phys_req_side, phys_req_sector[7:0]
phys_req_size[7:0], phys_req_step_rate[1:0]
phys_req_buffer_generation[15:0]
```

`phys_control_generation_valid` is a level handshake, not a pulse. The source
manager holds both generation values stable while it is high. The WD bridge and
physical controller each latch the complete pair only when locally idle or
after the old named operation has entered terminal retirement, then assert
their respective acknowledgement and hold it until valid drops. The manager
blocks new command/backend admission from the start of an update until both
acknowledgements are observed, drops valid, and waits for both acknowledgements
to drop before another update. A consumer may retain an older tuple solely to
retire the already-live operation; it uses the newly acknowledged tuple for
every later request. Reset initializes the handshake to invalid/no-ack and uses
section 15.2's invalid-then-establish rule.

`phys_req_op` is exactly the table in section 9.3 and `phys_req_flags` is exactly
the bit map in section 9.2; reserved values/bits are rejected or zero as those
sections require. No raw WD opcode crosses this ABI.

Response and cancellation:

```text
phys_rsp_valid, phys_rsp_ready
phys_rsp_source_epoch[15:0], phys_rsp_media_generation[15:0]
phys_rsp_id[15:0]
phys_rsp_result[4:0], phys_rsp_detail[6:0], phys_rsp_flags[15:0]
phys_rsp_cylinder[7:0], phys_rsp_head[7:0], phys_rsp_sector[7:0]
phys_rsp_size[7:0], phys_rsp_deleted, phys_rsp_byte_count[12:0],
phys_rsp_stored_crc[15:0], phys_rsp_calculated_crc[15:0]
phys_cancel_valid, phys_cancel_source_epoch[15:0],
phys_cancel_media_generation[15:0], phys_cancel_id[15:0]
phys_cancel_ack, phys_cancel_ack_source_epoch[15:0],
phys_cancel_ack_media_generation[15:0], phys_cancel_ack_id[15:0]
phys_write_closed, phys_guard_done, phys_write_state_ack
phys_write_state_source_epoch[15:0],
phys_write_state_media_generation[15:0], phys_write_state_id[15:0]
phys_late_fault_valid, phys_late_fault_ack, phys_late_fault_cause[3:0],
phys_late_fault_source_epoch[15:0],
phys_late_fault_media_generation[15:0], phys_late_fault_id[15:0]
phys_media_change_valid, phys_media_change_ack,
phys_media_change_source_epoch[15:0],
phys_media_change_old_generation[15:0]
```

`phys_rsp_result`, `phys_rsp_detail`, and `phys_rsp_flags` are exactly the encodings in section 9.6.
`phys_rsp_valid` is one child backend-result event, not necessarily parent WD
command completion and not an assertion of
`phys_guard_done`. The four observed ID fields remain full bytes: in particular,
`phys_rsp_head[7:0]` is the actual on-disk H value, not the one-bit selected side.
The media-change event follows section 13.5: the physical block holds valid and
both old-tuple fields until the source manager asserts ack, the manager never
acks a tuple that is not its current physical tuple, and the same latched disk-
change episode cannot emit a second event. Ack records event capture, not
permission for new requests; the dual-ack control broadcast provides that
permission.

Record and track data:

```text
phys_record_rx_valid, phys_record_rx_data[7:0],
phys_record_rx_ordinal[8:0], phys_record_rx_last,
phys_record_rx_source_epoch[15:0], phys_record_rx_media_generation[15:0],
phys_record_rx_id[15:0]
phys_write_collect_valid, phys_write_collect_ready,
phys_write_collect_source_epoch[15:0],
phys_write_collect_media_generation[15:0], phys_write_collect_id[15:0],
phys_write_collect_buffer_generation[15:0]
phys_buf_addr[8:0], phys_buf_wdata[7:0], phys_buf_we,
phys_buf_rdata[7:0], phys_buf_generation[15:0], phys_buf_ready
phys_track_tx_valid, phys_track_tx_ready, phys_track_tx_token[8:0],
phys_track_tx_last, phys_track_tx_source_epoch[15:0],
phys_track_tx_media_generation[15:0], phys_track_tx_id[15:0]
phys_track_rx_valid, phys_track_rx_data[7:0],
phys_track_rx_flags[7:0], phys_track_rx_ordinal[12:0],
phys_track_rx_source_epoch[15:0],
phys_track_rx_media_generation[15:0], phys_track_rx_id[15:0]
phys_track_marker_valid, phys_track_marker_ack,
phys_track_marker_kind,  // 0=start, 1=end
phys_track_marker_last_ordinal[12:0],
phys_track_marker_source_epoch[15:0],
phys_track_marker_media_generation[15:0], phys_track_marker_id[15:0]
```

Live normalized state:

```text
phys_media_ready, phys_read_path_valid, phys_mechanics_reusable,
phys_step_recovered, phys_head_settled,
phys_index_fast, phys_index_start_min_qualified,
phys_index_sector_epoch_min_qualified,
phys_index_qualified, phys_index_write_locked,
phys_track0, phys_write_protected, phys_disk_changed, phys_motor_on,
phys_motor_hold_active, phys_motor_off_pending,
phys_head_position_valid, phys_restore_required, phys_mechanism_power_good,
phys_controller_idle, phys_write_critical, phys_fault
```

`phys_step_recovered` authorizes only the next tagged step in the same Type-I
sequence. It does not assert general `phys_mechanics_reusable` or
`phys_read_path_valid`; those require `phys_head_settled` after the last pulse.

The extra track-transmit token bit distinguishes an ordinary literal from a
formatter token, avoiding an accidental F5/F6/F7 interpretation outside Write
Track: bit 8 zero means literal low byte; bit 8 one permits only low-byte F5,
F6, or F7 with section 14.6 meaning, and any other value is invalid. The WD
Write Track front end marks CPU F5/F6/F7 special; sector data never uses this
port. `phys_track_rx_flags[7:0]` is exactly: bit 0 separator-locked, bit 1
address-mark sync, bit 2 decoder error, bit 3 fast-index-later-rejected, bit 4
physical overrun, and bits 5–7 reserved zero.

The marker handshake is lossless control, not FIFO data and not CPU DRQ. A
start marker is acknowledged before ordinal 0 may be accepted. Byte ordinals
then increase without gaps modulo no wrap within one revolution. An end marker
captures the last produced ordinal (`0x1FFF` means no byte) after the producer
has committed that byte, but the independent CDC path may arrive first. The WD
frontend therefore holds end completion until every ordinal through the
watermark has been dequeued and either presented under normal DRQ/Lost-Data
rules or explicitly dropped for a recorded codec overflow. It may then assert
INTRQ while the final DRQ remains high; no byte may surface after completion.
The marker remains valid until acknowledged, carries exact identities, and
cannot be blocked by a full byte queue. A mismatch, gap, duplicate, wrap, or
post-watermark byte faults the request. Index flags MUST NOT be smuggled onto
the previous/next data byte.

`0x1FFF` cannot be a valid operational ordinal. At the inclusive 250 ms maximum
read-plausible revolution and 32 us decoded-byte cadence, no more than 7,813
bytes can be produced (valid ordinals `0x0000` through `0x1E84`). The producer
hard-faults before accepting a larger ordinal, so the no-byte sentinel cannot
alias a legal stream even if a malformed decoder attempts to overrun it.

Sector/track RX valid is an event, not a backpressure promise: the receiver
must accept each event into its proven elastic queue; full means physical codec
overrun while disk time continues. Track TX ready controls only acceptance of
the presented token and cannot pause the serializer. `phys_track_tx_last` is
diagnostic metadata and never ends WGATE.

The write-buffer port is synchronous to `fdc_clk`: address/write data/WE are
sampled on a rising edge and read data returns exactly one rising edge after
address. The WD bridge owns it only in `WD_FILLING_AFTER_ID`; the physical local
port owns it only in `PHYSICAL_WRITING`; ownership/generation changes through a
handshake and simultaneous writes are asserted impossible.

For a normal Write Sector, `phys_rsp_valid`/WD-done may occur at CRC-low +
24 us while `phys_write_closed=0` and `phys_write_critical=1`. Final FF, WGATE
close, and guard then advance `phys_write_closed` and `phys_guard_done`/
`phys_mechanics_reusable`. Source/reset/mechanics arbitration uses the latter
signals, never WD Busy alone. A late hard safety event remains sticky even if
the WD-visible command already completed.

The requester holds `phys_cancel_valid` and its tuple stable until a matching
acknowledgement. The backend holds `phys_cancel_ack` and its echoed tuple until
valid drops; a mismatched/duplicate old acknowledgement is counted stale and
cannot retire a current request. A matching `phys_cancel_ack` means the named
search/read is stopped or the named writer’s WGATE is closed and no more stream
data can appear; it does not imply guard completion. `phys_guard_done` is the
later source-switch/reset permission.
For every accepted write child, `phys_write_closed` and `phys_guard_done` are
monotonic sticky levels carrying the `phys_write_state_*` identity: close rises
first, guard may rise later, and both plus their payload remain stable until
`phys_write_state_ack`. A write that was rejected before WGATE opened may assert
both with its result. The combined arbiter raises the acknowledgement only after
the WD parent and source/mechanics manager have retired all need for that state;
the physical controller cannot reuse the writer slot before it. Hard-fail/reset
may instead invalidate the entire endpoint under section 15.2's clear protocol.
`phys_late_fault_*` is a separate sticky, lossless safety event, never a second
`phys_rsp`: causes are 0 WP, 1 disk change, 2 ordinary controller fault, 3
hard-fail observed before endpoint loss, 4 unexpected distinct fast index
during sector write/tail, and 5–15 reserved/internal fault. A post-commit cause 4
leaves an M=0 child/parent result immutable and creates no second IRQ; for an
intermediate M=1 child it terminally fails the still-Busy parent exactly once
and prevents the next child, using the same rule as other late safety faults.

### 17.4 `fdc1772.v`

In
`CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v`:

- retain SystemVerilog compilation despite the `.v` suffix;
- split WD register/command/DRQ/IRQ policy from image-only virtual mechanics;
- add the flat physical ABI, sector-buffer ownership, and track-stream logic;
- keep fixed image geometry and `floppy.v` strictly in the image branch;
- keep the current image path behavior unchanged behind the latched source;
- replace physical-mode fake Read Track/Write Track success;
- implement real Verify, CRC status, write-protect refusal, result mapping,
  command cancellation, and physical step acknowledgements;
- preserve `MODEL=2`, `SECTOR_SIZE_CODE(2)`, `SECTOR_BASE(1)`, and
  `EXT_MOTOR(1)` for the 1581 specialization;
- export an explicit idle/busy control signal; do not infer idleness from the
  activity LED;
- ensure multiple-sector mode increments R only and terminates on RNF, CRC,
  Force Interrupt, or another terminal error.

The current image geometry/presence logic around the image-mount block and the
`floppy.v` instantiation remain active only for Image. The current Type-III
delay/success stubs must remain untouched for Image unless separately covered
by regression, but are bypassed by real operations for Physical.

### 17.5 1581 and IEC hierarchy

In `CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv`:

- add the drive-domain-latched `physical_mode_drive` and flat physical ports;
- latch `active_image_engine` independently of live mount `dtype` and export
  selected-engine drain/admission/reset state;
- select the 1581 engine with the drive-domain-latched expression
  `physical_mode_drive OR (image_mode_drive AND
  active_image_engine_drive==ENGINE_1581_D81)`; live `dtype` is only a staged
  mount input and never selects a running/reset-released engine;
- force exported image `sd_rd`/`sd_wr` inactive in physical mode;
- retain existing D64, D81, IEC, and drive-9 selection behavior.

Thread the contract through `c1581_multi.sv` for drive 0 without changing
generic image instances. Replace its live standard/custom ROM select with the
latched requested/active slot handshake in section 15.3; export custom-BRAM
mutation, byte-count, readback-digest/profile, and content-generation state to
the source manager. In `c1581_drv.sv`:

- image-mount write protect remains authoritative only for Image;
- live normalized physical write protect is authoritative only for Physical;
- expose CIA PA2 motor request and retain PA0 side convention;
- separate image-derived disk-change pulses from sticky physical disk change;
- retain PA1/PA7/PB6 polarity at the CIA boundary;
- connect the T65 `sync` opcode-fetch indication and add the profile-specific,
  side-effect-free `$0087` RAM-write classifier from section 15.3;
- expose the complete ROM-profile/cache state bundle, generation-tagged flush
  success/fault retirement, drive admission/reset handshake, and explicit
  `fdc_busy`/idle status; and
- keep the drive computer IEC-visible with empty physical media.

In `c1541_drv.sv`/`c1541_track.sv`:

- retain `track_modified` as exported `c1541_track_dirty` until a tagged save
  actually retires; remove clear-on-toggle/request as durability evidence;
- add explicit flush request, cache/track/drain generations, success/fault
  response, and upper-cache-clean signals from section 15.3.2;
- treat reset, image mount/change, track move, partial ACK, and timeout during a
  pending save as fault/discard, never clean success; and
- hold the GCR buffer/track identity stable from flush acceptance through the
  complete SD transfer while IEC admission is blocked.

These files live in the `CORE/C64_MiSTerMEGA65` submodule. Their implementation
requires a focused submodule commit followed by a deliberate parent-repository
pointer update; do not bury unrelated upstream changes in that pointer.

`physical_mode_drive` is never an unsynchronized OSM/50 MHz bit. The source
manager asserts drive-local reset, holds active source/epoch stable, transfers
them with a request/ack handshake into both `fdc_clk` and drive domains, waits
for both acknowledgements, and releases reset synchronously in each domain.
Live physical Ready/change/WP and maintained motor/side acknowledgements cross
through their specified synchronizers/handshakes before CIA/WD use.

### 17.6 `main.vhd` source and reset manager

`CORE/vhdl/main.vhd` owns:

- physical-controller instantiation on the stable clock/reset;
- desired/active source, split identities, switch-pending state, and default-
  false `G_PHYS1581_CAPABLE AND known G_BOARD` capability;
- drive-local `source_switch_reset` integration with `iec_drives_reset`;
- latched image engine; coherent 1581 ROM profile/dirty/valid/flush/discard and
  1541 track-dirty/generation/flush-success/fault bundles; lower `cache_dirty`,
  image request/idle, WD idle, physical idle, post-write, and cancellation
  acknowledgements;
- >=500 ms admission-race quiet detection, the section 15.4 drain transaction,
  and 120 s reject watchdog;
- strict `sd_*` gating in physical mode and physical-result gating in image
  mode;
- physical diagnostics and top-pin plumbing.

IEC quiet is a 50 MHz counter reset by a synchronized transition or active bus
condition on the combined IEC ATN, CLK, or DATA path and by drive request/IRQ
activity. Define the exact sampled signals in the implementation note and prove
that a bus held active never qualifies as quiet. Do not include unowned ambient
index/RDATA edges or a stable spinning motor in the reset set. The interval is not merely
“time since the last byte” inferred inside the 1581 ROM, and it is not a cache
flush timer. A pending drain keeps the selected c1541/c1581 drive clock enable
and upper-cache engine running even when the ordinary menu/core pause request
is asserted.

Do not reuse finite `RESET_CORE` for switching or ordinary drive reset. The
existing cache protection ignores a reset pulse while lower `cache_dirty` is
high, does not queue it, and cannot see the 1581 `$0087` or 1541 track cache.
Split the C64 reset from the drive-local reset request and hold the latter until
section 15.4’s engine-specific upper-cache drain and lower retirement are true.
`phys_write_critical` remains a separate magnetic-safety hold from before WGATE
authorization through the post-write guard; it is necessary but not evidence
that an idle upper cache is durable. Raw hard reset still reaches the safety
clamp immediately and explicitly takes the possible-data-loss path.

Conceptually, physical active keeps the 1581 out of mount-dependent reset,
whereas image active retains existing “no image mounted” behavior. A clean
mounted image remains staged during Physical and receives no `sd_*` request.

### 17.7 Menu and configuration migration

For the minimal toggle in section 15.1, the concrete current-layout delta is:

```text
8:<mounted image name>
Use internal 1581
PRG:<mounted PRG name>
```

In `CORE/vhdl/config.vhd`:

- add `OPTM_G_DRIVE8_SOURCE = 31` using a single-select group with no standard-
  selected/default-on flag;
- increase `OPTM_SIZE` from 159 to 160;
- insert the matching `OPTM_ITEMS` and `OPTM_GROUPS` entries at flat index 3;
- increase main-view `OPTM_DY` from 27 to 28 because the new flat-index-3 row is
  visible in the main menu;
- update help text.

In `CORE/vhdl/mega65.vhd`, add `C_MENU_INTERNAL_1581 = 3` and increment all
subsequent flat indices. Update `M2M/rom/tests/menu_test.py` group, V6 menu,
constant, and navigation expectations; run its `run`, `verify`, `mutate`, and
`ghdl` modes. Regenerate `osm_const.asm` through the core menu-ROM build.

Also revise the `M2M/rom/crts-and-roms.asm` c1581 replacement loader and its
`tests/jiffy_test.*` coverage so custom-ROM mutation state, exact byte count,
full readback digest, and partial/error cases reach the source manager. The ROM
menu bit requests a slot; it cannot switch the live c1581 ROM mux. The manager
commits that slot only under the section 15.4 held-reset transaction.

Configuration loading requires exactly `OPTM_SIZE` bytes. An old 159-byte file
will be rejected and defaults loaded, which safely leaves the physical toggle
off but also resets other saved choices. Release notes MUST disclose this, and
the release process MUST regenerate and ship a 160-byte configuration with the
project’s `M2M/tools/make_config.sh ... auto` workflow.

Current pre/post menu callbacks treat nonzero callback results as fatal, so the
specified unsupported-board behavior requires an explicit nonfatal path that
forces the selection off and displays the message. It MUST be completed before
the shared menu is released on any unqualified target.

### 17.8 Project manifests, constraints, and builds

The four `.xpr` files are the project masters; Tcl files mirror/assist them.
Add new VHDL in dependency order (package, primitives, buffer/FIFO, inputs,
codec, safety/diagnostics, controller) before `main.vhd` in:

```text
CORE/CORE-R3.xpr       CORE/CORE-R3.tcl
CORE/CORE-R4.xpr       CORE/CORE-R4.tcl
CORE/CORE-R5.xpr       CORE/CORE-R5.tcl
CORE/CORE-R6.xpr       CORE/CORE-R6.tcl
```

Keep `fdc1772.v` marked `SVerilog` in each XPR and loaded with
`read_verilog -sv` in each Tcl. Rebuild the menu ROM before synthesis.

`M2M/common.xdc` already defines the QNICE clock; do not create a duplicate.
In `CORE/CORE.xdc` add only:

- false paths from each asynchronous physical input to its first synchronizer
  D pin;
- `ASYNC_REG` properties on actual synchronizer cells;
- named exceptions for reviewed request/result handshake synchronizers;
- deliberate external asynchronous-I/O endpoint waivers;
- IOB placement for final STEP, WGATE, WDATA, MOTOR, SELECT, SIDE, DIR, and
  DENSITY output registers where supported.

Do not false-path request payloads, wildcard the physical hierarchy, or reuse a
generic `busy` pattern. Run `report_cdc -details`, `report_methodology`,
`report_timing_summary`, and `check_timing` for all R3–R6 builds.

### 17.9 Documentation, release, and provenance

Implementation completion updates at least:

- `tests/README.md`, including the issue-#91 image baseline and physical tests;
- `VERSIONS.md`, `ROADMAP.md`, and the README missing-feature list;
- `FAQ.md` for external device-8 conflict, DD media, unsupported HD/USB media,
  and safe source switching;
- `doc/models.md` for board/mechanism qualification;
- menu help and user instructions for insertion, change, write protect,
  formatting, reset, motor/LED behavior, and error recovery;
- module provenance and board/mechanism qualification records.

The present specification incorporates and supersedes the implementation
recommendations and open questions in
`doc/how-MEGA65-uses-the-physical-disk-drive.md`. That document remains useful
research provenance, but no implementation or review session needs it to
recover a requirement, timing constant, interface decision, test, or acceptance
criterion.

New project-authored work follows the repository’s GPLv3 licensing. Files
adapted from MEGA65’s LGPLv3 source retain LGPLv3 headers and attribution,
record upstream commit/path, and identify substantive local changes.

## 18. Diagnostics and observability

### 18.1 QNICE diagnostic device

At the reviewed source snapshot, reserve the next free QNICE device ID
`C_DEV_C64_PHYS1581 = 0x0108` in `CORE/vhdl/globals.vhd`, decode it in
`mega65.vhd`, and pass chip-enable/address/read-data to the 50 MHz controller.
Recheck that the ID is still free when implementation begins.

The device is observational. All writes are ignored; it has no register that
can start motor, step, select, write, alter timing, clear write protect, inject
data, or open WGATE. Sticky diagnostics clear only on the controlled backend
reset documented in section 16, while the first safety-fault record survives a
mere WD command reset until source re-entry or hard reset.

### 18.2 Register ABI

The ABI is 16-bit, word addressed, read-only, and version `1.0`. All bit numbers
below are inclusive; every reserved bit reads zero. Reading word `00` atomically
copies *all* scalar values, the SHA-256, and all 32-bit counters into one shadow
bank, increments the snapshot sequence, and returns the signature. Every later
word read comes from that bank until `00` is read again. Thus low/high counter
words cannot tear. All writes and all undefined word offsets return no effect;
undefined reads return zero. Any incompatible packing change increments ABI
major; an additive reserved-bit/counter change increments minor.

#### 18.2.1 Fixed scalar words

| Word | Exact `[15:0]` definition |
| ---: | --- |
| `00` | `0x1581`; reading captures snapshot |
| `01` | `[15:8]` ABI major=`1`, `[7:0]` minor=`0` |
| `02` | capability bits: 0 read, 1 sector-write-qualified, 2 format-qualified, 3 precomp, 4 board capable, 5 independent clock-fail-safe qualified, 6 stock live-switch profile, 7 diagnostic track capture; 8–15 zero |
| `03` | 0 desired Physical, 1 active Physical, 2 switch pending, 3 reset pending, 4 board capable, 5 clock valid, 6 hard-fail, 7 admission blocked, 8 drive reset held, 9 lower cache dirty, 10 physical write-critical, 11 physical fault, 12 active engine bit 0, 13 active engine bit 1, 14 staged image engine bit 0, 15 staged image engine bit 1 |
| `04` | full `source_epoch` |
| `05` | full `physical_media_generation` (zero in Image) |
| `06` | full active/last `request_id` |
| `07` | full `buffer_generation` |
| `08` | `[3:0]` operation, `[8:4]` result, 9 request-valid, 10 response-valid, 11 cancel-valid, 12 write-closed, 13 guard-done, 14 stale-response seen, 15 watchdog-expired |
| `09` | exact 16 result flags from section 9.6, same bit order |
| `0A` | exact 16 command flags from section 9.2 |
| `0B` | `[7:0]` requested C/Track, 8 requested side, `[15:9]` last result detail from section 9.6 |
| `0C` | `[7:0]` requested R, `[15:8]` requested N |
| `0D` | `[7:0]` last observed C, `[15:8]` observed H |
| `0E` | `[7:0]` last observed R, `[15:8]` observed N |
| `0F` | `[12:0]` response byte count, 13 deleted DAM, 14 observed-ID valid, 15 CRC fields valid |
| `10` | calculated CRC16 |
| `11` | received/stored CRC16 |
| `12` | `[3:0]` abstract physical phase, `[7:4]` WD phase, `[9:8]` running engine, `[12:10]` sector-buffer owner; 13 head settled, 14 step recovered, 15 controller idle |
| `13` | safely synchronized positive samples: 0 index, 1 track0, 2 WP, 3 disk change, 4 RDATA-low; conditioned/state: 5 qualified index, 6 conditioned track0, 7 conditioned WP, 8 conditioned change, 9 separator lock, 10 media ready, 11 read-path valid, 12 mechanics reusable, 13 index write-locked, 14 synchronized sticky `outer_write_kill OR raw_write_kill`, 15 write-inhibit |
| `14` | requested logical outputs/state: 0 motor A active, 1 select A active, 2 side 1 selected, 3 inward direction, 4 STEP active, 5 WGATE active, 6 WDATA active, 7 DD-density-selected state, 8 motor/select B request fault, 9 write authorization, 10 motor-hold active, 11 motor-off pending; 12–15 zero. These are positive semantics, not connector voltages |
| `15` | final-IOB connector-intended logical-active values in bits 0–7 using word `14` order (not physical loopback); 8 hard clamp active, 9 ordinary fault guard, 10 output-enable released, 11 physical mode active, 12 outer writer armed, 13 outer writer class (`1` Track), 14 mechanism power good, 15 heartbeat valid |
| `16` | `[6:0]` head estimate, 7 `head_position_valid`, 8 overrange/unknown, 9 last direction (`1` inward), 10 last-direction-valid, 11 position-contract-fault/`restore_required`, 12 side settled, 13 select settled, 14 motor requested, 15 motor actual |
| `17` | `[2:0]` buffer owner, 3 buffer ready, `[7:4]` live track-FIFO fill, `[11:8]` FIFO high-water, 12 codec overrun, 13 codec underrun, 14 track marker pending, 15 buffer identity valid |
| `18` | full revolution/search-edge count for last operation, saturating |
| `19` | last index period 50 MHz cycles `[15:0]` |
| `1A` | last index period cycles `[31:16]` |
| `1B` | last qualified index pulse width in whole microseconds, rounded up and saturating |
| `1C` | last RDATA leading-edge gap in 50 MHz cycles, saturating |
| `1D` | minimum RDATA gap in cycles, `FFFF` if none |
| `1E` | maximum RDATA gap in cycles, zero if none |
| `1F` | last WGATE-low duration cycles `[15:0]` |
| `20` | last WGATE-low duration cycles `[31:16]` |
| `21` | `[7:0]` first-fault code, `[11:8]` physical phase at fault, 12 during write, 13 hard-fail, 14 media damage possible, 15 valid |
| `22` | `[7:0]` last transaction/cancel/reset cause, `[11:8]` transaction phase, 12 upper-drain ack, 13 lower-drain ack, 14 endpoint-clear ack, 15 rollback |
| `23` | effective-profile state: `[3:0]` profile class, 4 known, 5 1581 state-valid, 6 1581 dirty, 7 1581 flush-success, 8 1581 discard/fault, 9 upper-media-work-seen, 10 custom slot active, `[12:11]` custom-content state, 13 1541 dirty, 14 1541 flush-success, 15 1541 flush-fault |
| `24` | full `drain_generation` |
| `25` | full `profile_epoch` |
| `26` | `[7:0]` last `$0087` write value, `[15:8]` dirty-transition cause |
| `27` | full last T65 opcode-fetch PC used by classifier |
| `28` | `[7:0]` last quiet-reset cause, 8 quiet-qualified, 9 quiet-counting, 10 admission-held, 11 source-reset-held, 12 c1581 clock pause overridden, 13 IEC bus released, 14 upper clean, 15 lower clean |
| `29` | custom-ROM exact accepted byte count, `0000`–`8000`; saturates at `FFFF` on oversize |
| `2A` | low 16 bits of ROM-content generation; overflow policy is section 15.2 |
| `2B` | effective profile ID: `0000` unknown, `0001` stock 318045-02, `0002`–`7FFF` reviewed replacement registry, `FFFE` mutating, `FFFF` partial/error |
| `2C` | full c1541 cache generation |
| `2D` | `[6:0]` c1541 half-track, 7 track-valid, 8 flush-request, 9 flush-active, 10 flush-response-valid, 11 SD write active, 12 GCR write seen, 13 generation-match, 14 save error, 15 direct-GCR mode |
| `2E` | qualified `G_RAW_KILL_MIN_NS`, saturating |
| `2F` | snapshot sequence, wrapping only as an observational value |
| `30`–`3F` | effective-ROM SHA-256: word `30+n` contains digest byte `2n` in `[15:8]` and byte `2n+1` in `[7:0]`; all zero while unknown/mutating/error |

Engine encoding is `0` none/reset, `1` 1541-D64, `2` 1581-D81 image, `3`
1581-Physical. Buffer owner is `0` FREE, `1` WD_FILLING_AFTER_ID, `2`
READY_TO_WRITE, `3` PHYSICAL_WRITING, `4` INVALID, and `5`–`7` fault/reserved.

Abstract physical phases are `0` reset, `1` idle, `2` motor/select wait, `3`
side/head settle, `4` step, `5` ID search, `6` DAM search, `7` read, `8` write
collect, `9` magnetic write, `A` track start/wait, `B` write close, `C` guard,
`D` cancel, `E` complete, `F` fault. WD phases are `0` reset/idle, `1` spin-up,
`2` Type I, `3` Read Sector, `4` Write Sector collect, `5` Write Sector
physical, `6` Read Address, `7` Read Track, `8` Write Track, `9` Force, `A`
wait-mechanics, `B` result-held, and `C`–`F` reserved/fault. These are diagnostic
abstractions; an internal FSM may use different encoding but must map exactly.

Profile class is `0` UNKNOWN, `1` STOCK_318045_02, `2` APPROVED_REPLACEMENT,
`E` MUTATING, `F` ERROR; custom-content state is `0` INIT_STOCK, `1` MUTATING,
`2` COMPLETE, `3` PARTIAL_ERROR. Dirty-transition causes are `00` none, `01`
stock set at `$CF92`, `02` stock set at `$BF20`, `03` success `$C9EB`, `04`
controller error, `05` disk change, `06` reset, `07` burst failure, `08`
BUFMOVE clear, `09` M-W/direct mutation, and `FF` unexpected.

First-fault codes are `00` none, `01` illegal FSM, `02` ownership, `03` buffer
range, `04` conflicting output owner, `05` watchdog, `06` CDC protocol, `07`
codec overrun, `08` codec underrun, `09` stale identity, `0A` WP during write,
`0B` change during write, `0C` write index/tail violation, `0D` clock hard-fail,
`0E` reset during write, `0F` 1581 cache discard, `10` 1541 cache discard,
`11` lower flush failure, `12` position contract/Restore required, `13` outer
writer-arm mismatch, `14` mechanism power/reset, `15` truncated/invalid STEP,
and `FF` unclassified. Transaction causes are `00`
none, `01` source request, `02` ROM request, `03` soft-drive reset, `04` hard
reset, `05` D8 Force, `06` D0 Force, `07` watchdog, `08` IEC activity, `09` WD/
GCR activity, `0A` upper-cache event, `0B` lower-cache event, `0C` disk change,
`0D` WP, `0E` clock fault, `0F` profile loss, `10` upper flush failure, `11`
lower flush failure, `12` user rollback, `13` D4 Force, `14` DC Force, `15`
active image mount/type change, `16` mechanism power/reset, and `17` pause
arbitration.
Transaction phases are `0` idle,
`1` pending, `2` upper drain, `3` quiet, `4` admission capture, `5` drive reset
held, `6` lower drain, `7` endpoint clear, `8` commit, `9` release, `A`
rollback, and `F` fault. Unlisted codes read `FF`/fault, never alias a known
cause.

#### 18.2.2 Fixed 32-bit saturating counters

Every counter occupies an even base word (low 16 bits) and base+1 (high 16
bits), both from the word-`00` snapshot. Counters saturate at `FFFFFFFF`.

| Base | Counter |
| ---: | --- |
| `40` | accepted requests |
| `42` | rejected requests |
| `44 + 2*n` | result code `n`, for every `n=0x00..0x10`; bases `44`–`64` |
| `66` | raw index edges |
| `68` | qualified index edges |
| `6A` | rejected index edges |
| `6C` | steps inward |
| `6E` | steps outward |
| `70` | Restore failures |
| `72` | decoder locks |
| `74` | decoder lock losses |
| `76` | complete ID fields |
| `78` | DAM fields |
| `7A` | complete data fields |
| `7C` | ID CRC errors |
| `7E` | data CRC errors |
| `80` | read sectors |
| `82` | written sectors |
| `84` | format revolutions |
| `86` | host Lost Data events |
| `88` | codec overruns |
| `8A` | codec underruns |
| `8C` | stale responses/markers |
| `8E` | cancellations |
| `90` | disk changes |
| `92` | safety clamps |
| `94` | watchdog expiries |
| `96` | recognized 1581 dirty sets |
| `98` | recognized 1581 success clears |
| `9A` | 1581 discard/error clears |
| `9C` | unknown dirty-byte writes |
| `9E` | effective profile changes |
| `A0` | live source/ROM/reset rejections |
| `A2` | drain rollbacks |
| `A4` | upper/lower flush failures |

The checked-in register-map package, RTL decode, firmware symbols, and ABI test
vectors MUST be generated from one source or compared exhaustively. Software
must check signature and major before interpreting any later word.

Never fan out a metastability synchronizer’s first stage into the diagnostic
snapshot/decode. Literal pad visibility, if needed, uses a separate ILA sampler
with no functional fanout; software sees only the safe second-stage level,
conditioned state, and input-domain edge counters.

### 18.3 LED policy

The existing 1581 activity LED may remain green for WD/physical activity; its
current WD Busy contribution is useful. Image-cache dirty remains the existing
yellow indication. A physical write is not image-cache dirty and MUST NOT turn
yellow for that reason. Fault, switch-pending, physical idle, and write-critical
are explicit controls/diagnostics and are never inferred from LED color.

### 18.4 Integrated logic analyzer bundle

Provide a synthesis-guarded ILA bundle without any control path. Required
probes include raw/conditioned inputs, requested/actual outputs, FSM state,
source/epoch/ID, request/result handshakes, buffer owner, FIFO level, index and
gap timers, CHRN, CRC, write authorization, watchdog, cancellation, and first
fault. Source-switch captures additionally include effective profile ID,
opcode-fetch PC, `$0087` write/data/classification, cache-valid/dirty/success/
discard, c1541 GCR write/track/cache generation/save request/retirement,
selected old engine, drain generation, quiet reset cause, admission block, and
held-reset acknowledgements.

Standard triggers are:

- WGATE falling or rising;
- WDATA low while WGATE is not authorized;
- raw or synchronized write protect during write;
- disk change during a command;
- STEP/DIR/SIDE/MOTOR/SELECT transition during write guard;
- stale/mismatched response;
- no-index/search/restore watchdog;
- Force Interrupt during each writer phase;
- hard/soft reset while WGATE is active.

Debug builds may increase capture depth but MUST use the same safety logic and
output path as production.

## 19. Verification specification

### 19.1 Verification layers and evidence

Completion requires all five layers:

1. pure codec/CRC/timer unit tests;
2. WD-register tests against a mock backend;
3. end-to-end RTL with a flux/mechanism behavioral model and CDC jitter;
4. image-mode and menu/config regressions;
5. destructive real-hardware qualification and genuine-1581 interoperability.

Every automated test is deterministic from a recorded seed. Random tests print
the seed and retain the smallest failing transition stream. CI artifacts include
assertion logs, coverage summary, generated-media manifest, and test SHA. Real-
hardware evidence records bitstream and repository SHAs, board/mechanism/media
IDs, instrument setup, and raw captures, not just “passed.”

### 19.2 Behavioral mechanism model

Build a model below the MFM decoder, not merely a sector-return mock. It models:

- 300 RPM nominal rotation with configurable start delay, phase, drift, wow,
  and jitter;
- real index pulse width/period and absent/stuck/chattering index;
- 80 cylinders, two selected surfaces, Track Zero, one-cylinder STEP movement,
  direction setup, pulse rejection, settle time, and end stops;
- selected/motor-gated open-collector-like input visibility;
- DD flux transition lists for each cylinder/side;
- write gate erasure/splice and WDATA-created transitions so written data is
  read back through the same decoder;
- write protect and disk change at arbitrary clock phase;
- insertion/ejection, blank indexed media, no media, and media replacement;
- configurable pulse widths, missing/extra transitions, weak/noisy inner
  tracks, CRC corruption, deleted marks, wrong H, and unsupported N.

The model checks pin-level timing itself and fails on illegal STEP, DIR, SIDE,
WGATE, WDATA, MOTOR, SELECT, or density behavior. A separate high-level mock
backend is allowed for exhaustive WD register semantics, but it does not count
as codec or mechanics coverage.

### 19.3 Generated media fixtures

Generate and check in the generator plus manifest for:

1. A canonical standard disk: all 1,600 sectors, normal FB marks, correct
   C/H/R/N and CRC, legal but varied gaps.
2. A side-asymmetric golden disk whose payload encodes cylinder, side, sector,
   byte offset, and a seeded PRBS; every sector has a SHA-256 in the manifest.
3. A mark/error track with an F8 deleted record, ordinary A1/C2/F5/F6/F7 data,
   one bad ID CRC, one bad data CRC, one missing DAM, one wrong H, one N=1, and
   one N=3 record at nonconflicting locations.
4. A boundary track with minimum/maximum legal gaps, jitter phases, index near
   a byte boundary, and 203 ms capacity.
5. Both the 6,120-byte service-manual Write Track layout and a cycle-accurate
   bundled-318045-02 trace whose initial gap/per-record gap produces 6,122
   magnetic byte-times, with host F7/token ordinals, expected raw 16-bit MFM
   words, flux intervals, CRCs, and tail suppression.

Also resolve the existing `tests/README.md` reference to the absent
`tests/Disk-Write-Test.d81`: add a reproducibly generated, redistributable
fixture or update the test to use the new generator. Do not leave a mandatory
image regression dependent on an untracked local file.

The standard interoperability disk contains no deliberate error. Error cases
use sacrificial/generated fixtures so a recovery behavior cannot accidentally
be accepted as standard formatting.

### 19.4 Input, timer, and mechanics unit tests

| ID | Stimulus | Required result |
| --- | --- | --- |
| `IN-01` | every RDATA pulse width 150–800 ns at every 20 ns phase | exactly one timestamped transition |
| `IN-02` | runt pulses below qualified floor, double edges, slow return high | rejected/count recorded; next legal pulse retained |
| `IN-03` | index widths below, at, within, and above 1.5–5 ms range | only qualified leading edges count; raw diagnostics accurate |
| `IN-04` | periods 149/150/180/200/220/250/251 ms | boundary behavior and warning/rejection exactly as specified |
| `IN-05` | asynchronous WP/change/track0 toggles at all clock phases | no metastable bus use; assertion/change never lost |
| `IN-06` | valid/runt/chattering/missing distinct end edge at every 20 ns phase and every 1 ms point after start-pulse return-high, including before 150 ms | every subsequent fast edge closes immediately even when implausibly early; otherwise tail close is connector-high before earliest plausible index; later qualification never reopens; no-index completes boundedly |
| `IN-07` | 196–204 ms stable/jittering histories | read plausibility and `index_write_locked` are distinct at exact profile bounds |
| `IN-08` | source/media/motor/select/reset/fault/outlier/failed-write after lock; separately side/step/successful write | first group clears history/arms/generation and requires three fresh periods; second preserves spindle history but invalidates its own codec/head state |
| `IN-09` | start edge at `P_write_min-1/at`, `P_write_max/ +1`; every ordered three-period history drawn from 197/200/203 ms; abrupt next 203->197 ms; command accepted inside/after window | exact fixed-bound arm/requalify behavior; no recent-period estimator narrows the window or delays tail close; out-of-window edge cannot start; ending close arm is permanent from accepted start-pulse return-high |
| `IN-10` | format side 0/1 and step through all 80 cylinders without motor-off | every next Write Track starts on the next valid index without a three-revolution reacquire; no stale source/media history survives |
| `IN-11` | armed Write Track candidate low for `G_INDEX_START_MIN_US-1/at/+1`, 1.5-ms-minus-one-cycle, and legal widths at every phase | below threshold never opens WGATE; threshold is inclusive and uses original-edge timestamp; a post-open pulse later rejected by full qualification closes/faults without reopen; legal pulse meets measured `L_start` and capacity proof |
| `IN-12` | Command/first token becomes eligible on every cycle and sub-cycle phase from just before fast falling edge through 1.5–5-ms low pulse, return-high, and qualification | eligibility must pre-exist the edge; coincident/already-low/in-flight pulse is never joined, valid pulse becomes the reference for the following full window, rejected pulse fails without WGATE, and the unreset 300-ms wall timer bounds all cases |
| `IN-13` | during second-pass sector search inject out-of-window and in-window index pulses at `G_INDEX_START_MIN_US-1/at/+1`, then an early valid ID before a 5-ms index pulse fully qualifies | raw/runt/rejected edge never rebases `T_idcrc2`; minimum-qualified original timestamp is immutable, early ID candidate waits without delaying disk/opening gate, and later rejection aborts/closes rather than authorizes |
| `MECH-01` | each WD step-rate code, same direction | exactly one 4 us pulse/cylinder, 24 us DIR setup, >=3 ms effective interval |
| `MECH-02` | direction reversal | 24 us setup and >=4 ms reversal interval |
| `MECH-03` | Restore from 0/1/40/79, stuck Track Zero, V=0/1 | correct pulses/estimate; exhaustion backend fault and conditional S4 |
| `MECH-04` | side change immediately before command | >=100 us wait, decoder invalidated, no stale side data |
| `MECH-05` | 505 ms plus two edges/one period, 150/250-ms edge phases, slow startup, no index | media_ready only on full qualification and never after the 1.10-s bound; exact boundary/deadline expiry |
| `MECH-06` | disk change requiring selected step to clear | sticky event, invalidation, no invisible step, correct clear |
| `MECH-07` | blank indexed disk | Ready then RNF, never “no disk” |
| `MECH-08` | Restore and explicit Step Out at Track Zero with change latched | Restore no pulse; explicit step emits one, estimate remains zero, change can clear |
| `MECH-09` | motor-off status-only SELECT probe with `D_select_assert_max` swept to 1 us; seek/side/write recovery; CIA PA2-off at every WGATE half-cell/guard cycle; sweep `D_wgate_deassert_max`/`D_close_ack_max` at their caps | first status sample follows `ceil((D_select_assert_max+1 us)*G_FDC_HZ)` and status-only final-IOB deselect is by 16 us without treating a deasserted sample as write-safe; CIA media_ready states distinguish steady/latched writer readiness; normal off becomes pending, actual MOTOR/SELECT stay stable through the complete stream and >=700 us connector-relative guard, ordinary guard retires <=710.10 us after final-IOB close, then pending off applies; read_path_valid/mechanics_reusable change correctly |
| `MECH-10` | 255-step 12-ms Seek, target >79, index suppressed during seek | derived >=3.2-s bound, no false no-index, no inner-end hammering |
| `MECH-11` | request/final-IOB/connector DIR and STEP propagation swept through profile/PVT extrema, then read/Verify at `IOB trailing+D_step_trailing_max+18 ms` -1/at/+1 cycle | connector DIR setup remains >=24 us; `head_settled` clears by acceptance and asserts only after >=18 ms from actual connector trailing edge; clamped/nonexistent pulse never acknowledges or starts it |
| `MECH-12` | FPGA alive while mechanism 5 V/reset/brownout cycles with REN auto-recal off/on during idle, every STEP phase, and every WGATE/WDATA phase; change asserted/not asserted per topology; settled estimate/T0 contradictions | common hard reset or raw monitor clamps before voltage recovery can make WGATE effective, position invalidates/Restore required, release waits profiled >=400-ms recalibration + SAFE_RESET handshake; contradiction faults and no media/destructive action precedes Restore |

Counter tests use production values and accelerated generics. At least one
non-accelerated simulation proves conversion/rounding and counter widths at
50 MHz without overflow.

### 19.5 MFM and CRC unit tests

| ID | Stimulus | Required result |
| --- | --- | --- |
| `MFM-R01` | all 256 bytes with previous data bit 0 and 1 | exact ordinary clock/data decoding across byte boundaries |
| `MFM-R02` | raw `4489`/`5224`, ordinary A1/C2, shifted/random occurrences | only true missing-clock words establish sync |
| `MFM-R03` | canonical sector and whole track | exact CHRN, FB, 512 bytes, stored/calculated CRC, ten records |
| `MFM-R04` | F8 record | payload accepted and deleted status independent of CRC |
| `MFM-R05` | gap-class windows and every threshold +/- one 50 MHz cycle | specified class or explicit lock loss; no adjacent ambiguity |
| `MFM-R06` | speed/jitter/wow/random clock phase at qualified extremes | no byte error for legal stream; after error, reacquire only at the next legal missing-clock sequence or terminate on the operation's stated absolute watchdog, with no stale partial word/parser state |
| `MFM-R07` | dropped/extra transition in ID, gap, data, CRC | correct malformed/ID CRC/data CRC classification; no buffer overrun |
| `MFM-R08` | FE/FB/F8 and A1 byte values inside payload | no false record start |
| `CRC-01` | published/generator known vectors | exact `0x1021`/`0xFFFF` values and high/low order |
| `CRC-02` | consume generated stored CRC | zero residue for ID and data phases |
| `CRC-03` | reset/invalidate at every field byte | no prior request/field state leaks |
| `MFM-W01` | all bytes and both previous-bit states | exact ordinary raw MFM words and 4/6/8 us transition gaps |
| `MFM-W02` | F5/F6/F7 in Write Sector payload | literal data, never formatter tokens |
| `MFM-W03` | F5/F6/F7 in Write Track; next host write before/at/after 55.5 us and DSR transfer at 64 us | exact missing-clock marks/generated CRC bytes; F7's next DRQ asserts at CRC-high start, remains serviceable across both CRC bytes, and next token cannot serialize before CRC-low ends |
| `MFM-W04` | service-manual 6,120-byte and exact stock-ROM 6,122-byte formats for every ordered 197/200/203-ms lock history/next period, especially 203->197 ms; `L_data_start` at nominal/maximum; integral and fractional profile-delay extrema | after measured `L_start+L_data_start_max`, every `N_format_required_max` byte finishes at least `M_tail` before floor-rounded `N_tail_close`; stock trace/CRC/gaps are exact, only later filler is suppressed, WD completes on real index, and no rounding or next-revolution write consumes the reserved margin |
| `MFM-W05` | four WD1772-02 patterns with P=0/1 at 180 ns profile | exact early/late/nominal shift; pulse legal; transitions monotonic |
| `MFM-W06` | missing-clock A1/C2 followed by every ordinary byte | previous_data becomes 1/0 respectively; exact following raw word |
| `MFM-W07` | every possible first/last MFM transition phase and byte pattern | first active WDATA edge nominally follows WGATE by 2 us and never exceeds 8 us; last pulse is wholly inside WGATE and WGATE closes nominally 2 us/no later than 8 us after it |

Read Track tests verify that missing-clock A1/C2 return decoded A1/C2, all gap
and CRC bytes are present, and WD CRC status is not synthesized from the
diagnostic parser.

### 19.6 WD1772 register and command tests

The standalone SystemVerilog bench checks register reads/writes at every legal
and one-cycle-late/early boundary. Minimum matrix:

| ID | Stimulus | Required WD-visible result |
| --- | --- | --- |
| `WD-01` | every reset class, each prior register/Force/FIFO/direction state, idle access, normal command | every field in section 10.1 reset table; Busy/IRQ/DRQ sequence; no X/stale completion |
| `WD-02` | non-Force command while Busy | ignored; active latched request unchanged |
| `WD-03` | Type-I commands with each rate/update/verify flag | one acknowledged physical step per cylinder; register update only with U; real Verify |
| `WD-04` | Restore with Track Zero normal/stuck | Track=0 success or bounded Seek Error, no 256th pulse |
| `WD-05` | Type-I status at live index/track0/WP/motor phases | bits 7–0 exactly match section 10.2 |
| `WD-06` | Read Sector valid FB | matching C/R, ignores H, 512 physical-cadence DRQs; final DRQ and INTRQ may coexist without waiting for CPU service |
| `WD-07` | Read Sector valid F8 | same bytes; bit 5 set independently of CRC |
| `WD-08` | candidate with wrong H but selected physical side | accepted and observed H reported diagnostically |
| `WD-09` | matching C/R with N=1 or N=3 | bounded RNF + Unsupported Size, no buffer overrun/data exposure |
| `WD-10` | bad matching ID CRC followed by good copy | skips bad ID and accepts good; diagnostic retained |
| `WD-11` | only bad matching ID CRC | RNF + CRC Error after search budget |
| `WD-12` | matching ID then no/late DAM, with and without a later valid copy | local 43-byte miss resumes search; later copy succeeds, otherwise RNF/Missing DAM only at overall expiry |
| `WD-13` | bad data CRC | all bytes already streamed once at physical cadence; CRC Error without RNF; no retry/replacement |
| `WD-14` | Read DRQ serviced before/at/after 23.5 us | no error at legal boundary; Lost Data when late; stream continues |
| `WD-15` | Write Sector valid normal/deleted | first ID, 2-byte DRQ delay, 9-byte service check, synthetic preamble/second-DRQ timing, 512 slots, second matching ID before WGATE, correct DAM, status bit 5 zero, fixed CRC/FF close, IRQ independent of guard |
| `WD-16` | first Write DRQ missed | Lost Data; no WGATE authorization/request |
| `WD-17` | later Write DRQ missed | zero substituted, Lost Data sticky, bounded safe completion |
| `WD-18` | Write Sector/Track protected or change-pending at post-spin-up/E execution eligibility; then assertion during search/DRQ/authorization/active write | pre-execution failure produces WP or Disk Changed/RNF with no first DRQ/backend search/index arm; later checks prevent WGATE, and mid-write raw assertion immediately clamps/faults |
| `WD-19` | Read Address good/bad ID CRC with response overtaking 0–6 queued bytes | actual streamed ordinals 0–5 are C/H/R/N/CRC high/low, watermark drains before completion, bad ID sets CRC, Sector register becomes returned C |
| `WD-20` | multi-read/write through R=10, delayed prior-child results, Force between children, write guard boundary | fresh request/buffer ID each child; R increments once; intermediate Busy stays/INTRQ clear; no side/cylinder wrap; only terminal RNF/error/Force exits |
| `WD-21` | Read Track one revolution, no bytes, byte FIFO full at end, and marker CDC overtaking 0–4 queued bytes | start-before-ordinal-0 and end-watermark ordering; all through last ordinal retire before INTRQ, final DRQ may coexist, no post-completion/synthetic byte or CRC checking |
| `WD-22` | Write Track first token at 96-us boundary; Command/token eligibility before/coincident/through an in-flight 1.5–5-ms start pulse; candidate widths around `G_INDEX_START_MIN_US`; F7 next-DRQ service before/at/after 55.5 us and 64-us expansion | sole armed token may age until bounded start without false Lost Data; current in-flight pulse is never joined and a valid one references the following revolution; raw fast edge alone never opens WGATE; minimum-qualified start consumes first token; F7 asserts next DRQ at CRC-high start, accepts boundary service, and delays only DSR consumption through CRC-low; safe magnetic close |
| `WD-23` | Force Interrupt in every search/read state and every cycle of STEP setup/4-us assertion/recovery/settle, with prior settle true/running | named cancellation and specified IRQ/status; pre-fall emits no STEP and restores the exact prior settle state/deadline, post-fall finishes exactly one full pulse/updates once/settles physically even if WD Force retires earlier; next command after >=16 us and mechanics readiness |
| `WD-24` | Force Interrupt in every write state | WGATE safe close and guard before physical reuse; no stale result |
| `WD-25` | D4, D8, DC, D8/DC->D0, D0, status/new-command clears | exact Busy/immediate/index INTRQ, special clear/disarm, 16-us nullification/recovery, no level storm |
| `WD-26` | motor off/no index/blank media | bounded Not Ready/No Index/RNF distinctions |
| `WD-27` | source/media/request/buffer generation mismatch or duplicate response/cancel ACK; advance the idle control tuple while an old Disk-Changed result retires | only the exact live parent/child tuple is accepted, including its old generation after change; unrelated traffic is ignored/count recorded; no DRQ/IRQ/data mutation or false cancellation retirement |
| `WD-28` | reset/source cancel at every command cycle | buffer/FIFO invalidation and exactly one terminal retirement |
| `WD-29` | h=0/MO low, h=1/MO low, and MO already high; 505-ms Ready-gated index with first edge one 250-ms period later and 5-ms-wide sixth pulse; one cycle before/at/after 2.050-s bound | every accepted non-Force command sets MO; only h=0 with prior MO low waits exactly six qualified edges; all inclusive legal slow/late phases complete, missing edge times out once, and neither activity nor delayed CIA motor restarts the wall timer |
| `WD-30` | first idle reference edge plus nine complete intervals; new command at every boundary; CIA motor off before timeout | MO clears only after nine full idle revolutions; a command resets the idle count; without index MO remains logically set without driving motor |
| `WD-31` | Type-II/III E=0/1 including second-ID write | exactly one 15-ms delay only when E=1 |
| `WD-32` | Restore exhaustion V=0/V=1; Verify bad IDs | backend failure both; S4 only V=1 for Restore; Verify S4+CRC as specified |
| `WD-33` | 255-distance 12-ms Seek and target >79 | derived watchdog permits legal case; physical limit rejects unsafe target |
| `WD-34` | Command/Status/same-register visibility | exact 24/32/16-us MFM programmed-I/O boundaries |
| `WD-35` | final Write Sector CRC/FF timeline with `phys_write_state_ack` held low through close/guard/new-command attempts | INTRQ at CRC+24 us while FF/WGATE may remain; tagged close then independent 700-us guard remain sticky/immutable until acknowledgement; writer slot is not reused early |
| `WD-36` | two identical C/R IDs at different ordinals; every ordered first/second 197/200/203-ms period pair; normalized-phase `E_id` -1/at/+1 | 24-bit `q_id` scaling accepts the same ordinal across legal RPM change, never redirects to the duplicate, and ambiguity/out-of-window aborts before WGATE |
| `WD-37` | M=0 and intermediate M=1: raw WP/change, unexpected fast index, D0/D4/D8/DC, new command, reset, and `phys_rsp_ready` held at every clock/sub-clock phase from CRC+23 through +33 us | fixed priority; precommit fast index yields one fault response, postcommit uses sticky late-fault cause 4; one immutable child result; exact idle/active Force+index IRQ semantics; M1 late fault terminates parent once, M0 creates no second IRQ; normal command waits/ignores as Busy dictates; safe close/guard |
| `WD-38` | Write Sector and Write Track at stable 196/197/203/204 ms and broad-readable 180/220 ms | WGATE only at inclusive 197–203-ms profile bounds; outside returns `RES_UNSAFE_WRITE_TIMING` with rate subcause -> RNF/diagnostic and leaves complete track unchanged |
| `WD-39` | bare Step immediately after every reset; then Restore-at-track0, nonzero Seek, zero-distance Seek, Step In/Out | invalid direction emits no pulse/Seek Error; only named direction-establishing cases set validity; deterministic across reset boundaries |
| `WD-40` | next request/buffer/parent ID at FEFE/FEFF/FF00/FFFE/FFFF; Command and D0/D4/D8/DC at every cycle of <=8-us normal preflight; withhold/duplicate/stale clear ACK through 1.000 ms; 255-step Restore/256-child Multiple | one parent latch + Force priority, Busy timing preserved, reserved unique children never wrap mid-parent, stale old-epoch results ignored, and the non-reloadable ceiling terminally faults once without leaving Busy |
| `WD-41` | Read Sector CRC/result CDC overtakes 0–queue-depth payload bytes, final DRQ held, M=0/M=1/error | ordinal-511 watermark drains exactly once before terminal/next child; final DRQ may coexist with INTRQ; no post-result byte or stale-child mutation |
| `WD-42` | freeze serializer/state/CRC/queue at every half-cell after Write Sector WGATE; repeat before/after WD-done and at measured connector propagation extrema, including a non-integral `D_sector_connector_delta_max` | raw-100-MHz final-IOB deadline forces on `N_sector_iob_force=floor((17.100 ms-D_sector_connector_delta_max)*100 MHz)` and normal close is earlier; connector duration never exceeds 17.100 ms, guard runs, Internal Fault/possible damage records, and normal result or one late-fault event occurs without duplicate INTRQ |
| `WD-43` | start every record search just after an index, then use 250-ms periods and 5-ms pulse widths with fifth edge qualification before/at/after the derived 1.300-s wall bound | the fifth inclusive legal edge can qualify and complete; only the beyond-bound case times out; raw/rejected/qualified activity never restarts the wall timer |
| `WD-44` | cold h=0 Write Track with worst-phase 2.050-s spin-up and E=0/1; then first DRQ/96-us service and 300-ms start search | first DRQ and both Write Track timers remain inactive during spin-up/E; execution-start raises DRQ and starts them exactly once; spin activity never consumes the 300-ms budget |
| `WD-45` | suppress/chatter/reject ending index with tail close already complete; ending event one cycle before/at/after 260 ms from original start timestamp | Busy/ownership cannot hang; only a valid in-bound ending pulse completes normally, otherwise one No Index/fault retires at the absolute bound; no event reloads it |
| `WD-46` | place valid matching second-pass ID CRC so remaining-revolution equation is -1/at/+1 cycle; sweep runt/false/5-ms epoch edges before early/late ID; inject a distinct fast index at every sector-WGATE and committed-tail phase | only the immutable minimum-qualified epoch and inclusive safe-fit cases open WGATE; false edges never rebase; late ID returns timing/phase failure unchanged; unexpected index immediately truncates/faults and follows exact pre/post-result late-fault semantics without next-revolution pulses |
| `WD-47` | after Restore/T0, write Track=255 and Data=0 then Seek; also assert T0 early during every outward child | Seek emits no pulse while live T0 is asserted, returns Seek Error, preserves last acknowledged Track-register value, and never uses the explicit one-Step-Out change-clear exception |
| `WD-48` | disk change, mechanism reset/power event, or settled Track0 contradiction before each Type-II/III and writer phase | `head_position_valid` clears/`restore_required` sets; all media/destructive commands reject with no WGATE until explicit Restore, while live Type-I Track0 remains truthful |
| `WD-49` | CIA PA2 changes off at every Write Sector/Track WDATA half-cell, CRC/result/tail, and guard phase | pre-WGATE off cancels Not Ready; post-WGATE off latches pending and the normal writer/WD result completes without readiness self-revocation or pause-induced zeros; motor/select release only after guard, except hard-fail |

Status is checked after command acceptance, during Busy/DRQ, on completion,
after data/status reads, and after Force Interrupt. A final-state-only test is
insufficient.

### 19.7 Safety and fault-injection tests

Safety tests run with assertions always enabled and, where tractable, formal
proof over arbitrary input timing:

| ID | Injection | Required pin/result behavior |
| --- | --- | --- |
| `SAFE-01` | every reset class in every FSM state | WGATE/WDATA/STEP/SELECT safe under the reset-specific policy; bounded retirement |
| `SAFE-02` | raw WP/change widths at `G_RAW_KILL_MIN_NS-1/at/+1`, wider sub-clock/whole-clock values, and every phase around WGATE, with `fdc_clk`/functional request path running and stalled | every at/above-bound pulse directly sets outer async kill, connector WDATA becomes inactive no later than WGATE and both within 2 us, neither reopens; MOTOR/SELECT/SIDE remain latched through guard; below-bound behavior recorded without false guarantee |
| `SAFE-03` | disk change/eject before ID, during streamed read, during collected write, during WGATE | no new stale byte is delivered after event retirement (already serviced bytes remain); queued write inhibited; active writer safely closed |
| `SAFE-04` | motor/side/select request during write/guard | output held stable until guard finishes |
| `SAFE-05` | missing start/end index and index chatter | wall watchdog expires; WGATE cannot remain active indefinitely |
| `SAFE-06` | FIFO/pointer/buffer owner fault | no memory overrun or plausible media result; outputs clamp as specified |
| `SAFE-07` | illegal FSM/conflicting writer outside and during write | first fault retained; WG/WDATA close; mechanics hold through guard then inactive |
| `SAFE-08` | stop/toggle-stall 50 MHz heartbeat at every divide-16 phase with 100 MHz alive and lock low/stuck-high; remove raw 100 MHz while its qualified lock/reset indication deasserts; reconfiguration; release races | 100 MHz 128-cycle monitor plus async lock/reset IOB/OE path gives connector-safe levels within 2 us + measured clamp, no top-level bypass, and release occurs only after 1-ms stability + SAFE_RESET handshake |
| `SAFE-09` | physical mode false/capability false while controls request action | all outputs inactive, request rejected, no debug bypass |
| `SAFE-10` | WDATA generator bug request outside WGATE | final firewall blocks/counts it and asserts fatal diagnostic |
| `SAFE-11` | freeze every legal writer/serializer/CRC/FIFO state with missing index; separately stop 50 MHz after WGATE while raw 100 MHz remains | all-writer first-WDATA check, Write-Sector outer duration, and Write-Track absolute tail/end timers remain independent/nonreloadable; sector connector stays <=17.100 ms, track closes at frozen tail, and stopped-clock case uses outer hard-fail |
| `SAFE-12` | raw WP/change, hard-fail/reset, fast index, tail close, and writer fault at each of the 25 cycles of every 0.5-us WDATA pulse, sweeping input/output buffer delay and PVT | emergency priority may truncate pulse; raw WP/change uses the direct outer path; WDATA becomes inactive no later than WGATE at FPGA and connector within the applicable 2-us ceiling, writer never reopens, and the proper fault/guard path runs |
| `SAFE-13` | ordinary cancel/fault, hard reset, clock hard-fail, and async clamp at every 20-ns phase of DIR setup and 4-us STEP low, with prior settle true/running | ordinary pre-fall suppresses and restores prior absolute settle state, ordinary post-fall one-shot finishes exactly 4 us then updates/settles once; hard/truncated/out-of-range pulse invalidates position and blocks media/writers until Restore |
| `SAFE-14` | writer-arm valid/class/identity toggle and WGATE request at every relative 50/100-MHz phase; corrupt/change payload before/after ack and during close | no unacknowledged WGATE; outer latches one immutable matching class, sector deadline cannot be omitted/reclassified, any mismatch closes/faults, and arm release waits final WGATE-high capture |
| `SAFE-15` | qualified mechanism-power/reset monitor asserts/deasserts at every phase of STEP and WDATA/WGATE; voltage recovers before/after 100/400-ms internal reset model | async outer/inner kill makes WDATA inactive no later than WGATE and cannot reopen on recovery; position/writer identities invalidate; only stable-power/recalibration/SAFE_RESET handshake then explicit Restore permits access |
| `SAFE-16` | CIA motor request deasserts at every cycle from writer-arm through final WDATA and 700-us guard, with raw/hard fault controls | ordinary deassert only sets `motor_off_pending`; actual MOTOR/SELECT and writer readiness stay latched, stream completes, and release occurs after guard; hard/raw close policy retains priority |

Required invariants include:

```text
WGATE_active -> physical_active AND capable AND selected_A AND media_ready
                AND head_side_settled AND index_write_locked_current_generation
                AND write_authorized
                AND NOT outer_write_kill AND NOT raw_write_kill
                AND NOT write_protected
                AND writer_media_ready AND motor_hold_active
                AND actual_motor_on AND actual_select_A
final_IOB_WGATE_falling -> index_start_min_qualified
                             OR authorized_sector_splice_start
authorized_sector_splice_start -> index_sector_epoch_min_qualified
                                  AND remaining_revolution_equation_true
WDATA_active -> WGATE_active
sector_WGATE_active AND distinct_index_fast -> immediate_emergency_close
WGATE_or_guard AND CIA_motor_off -> motor_off_pending
                                    AND stable(actual_MOTOR, actual_SELECT)
(WGATE_or_guard) AND NOT hard_fail -> STEP_inactive
                                      AND stable(MOTOR, SELECT, SIDE, DIR, DENSITY)
ordinary_fault_during_write -> NOT WGATE AND NOT WDATA
                                AND mechanics_latched_until_guard_done
hard_fail -> all_outputs_inactive
fault_outside_write_guard -> all_outputs_inactive
outer_write_kill -> NOT final_IOB_WGATE_active
                     AND NOT final_IOB_WDATA_active
                     AND outer_kill_sticky_until_acknowledged_safe_clear
raw_write_kill -> NOT WGATE_request AND NOT WDATA_request
                   AND kill_sticky_until_safe_clear
response_accepted -> all_generations_and_id_match
                     AND exactly_one_request_outstanding
write_buffer_consumed -> owner_is_PHYSICAL_WRITING AND generation_matches
read_byte_accepted -> source_media_id_match AND ordinal_is_current
record_result_finalized -> all_record_ordinals_through_watermark_retired
track_end_completed -> marker_identity_matches AND all_ordinals_through_watermark_retired
upper_cache_clean -> selected_old_engine_success_proof AND NOT upper_flush_fault
source_switch_reset -> admission_blocked AND upper_cache_clean
                       AND old_backend_retired
                       AND (NOT old_physical_writer_owned OR guard_done)
```

No assertion is waived merely because the test uses sacrificial media.

### 19.8 CDC and reset verification

Run asynchronous clocks with relatively prime periods and randomized phase,
including current main-clock values and the future NTSC value. Randomly assert
resets in source and destination domains during every handshake phase. Prove:

- every accepted request produces at most one matching terminal result;
- a held result cannot be sampled twice;
- no payload changes between request toggle/valid and acknowledgement;
- source/media control tuple remains stable while broadcast valid; neither WD
  nor backend may admit a new request until both generation ACKs match, while a
  live old request may retire only against its latched tuple;
- one latched disk-change episode emits exactly one stable old-generation event
  and exactly one source-manager increment, including delayed event/control ACKs;
- cancel acknowledgement carries and matches the complete cancel tuple;
- normal source epoch cannot advance with an unretired response/cancel; hard
  reset instead clears both endpoints/valids before establishing a new epoch;
- buffer ownership and generation cross coherently;
- write-close/guard identity and monotonic state remain stable until the combined
  write-state acknowledgement, including reset of either consumer;
- outer writer-arm class/identity/deadline payload is stable across its 50->100
  MHz toggle handshake, acknowledged before WGATE, latched immutably at final-
  IOB assertion, and cannot default/reclassify on reset or metastable phase;
- each outer final-IOB STEP falling/rising sequence produces exactly one matching
  tagged return event; settle never starts from a request or unmatched edge;
- FIFO order, full/empty, and flags remain correct across pointer wrap;
- no narrow raw event is assumed to cross into the WD domain;
- reset cannot manufacture request, response, DRQ, IRQ, STEP, or WDATA pulse;
- post-reset stale RAM contents remain inaccessible.

Vivado `report_cdc` must classify intended crossings without Critical findings.
Waivers name a reviewed instance, synchronizer type, and justification. CDC
simulation does not replace static CDC analysis, and static analysis does not
replace randomized reset simulation.

### 19.9 Source-switch and menu/config tests

| ID | Scenario | Required result |
| --- | --- | --- |
| `SRC-01` | clean cold/default Image -> first Physical entry | pending, dual-domain reset/ack, source epoch change, source manager establishes media generation `0001` before dual-ack broadcast, pins safe, physical 1581 present, and no Physical tuple/event uses zero |
| `SRC-02` | dirty stock-ROM side cache, lower image cache, active SD | stock success clear and all ten old-medium writes retire, admission blocks, lower cache flushes, only then drive reset is held; image hash is preserved |
| `SRC-03` | continuous IEC activity/bus held low | quiet never qualifies; at 120 s switch rejected, desired restored, nonfatal message |
| `SRC-04` | active physical read/step | finish or named cancel; stale response ignored; then switch |
| `SRC-05` | active physical write/format | writer closes and 700 us guard completes before switch |
| `SRC-06` | rapid desired toggles | active source changes only at commit point; pending may cancel; no mixed epoch |
| `SRC-07` | mounted image retained through Physical | no `sd_*` while physical; same clean image resumes on Image |
| `SRC-08` | no image mounted on return to Image | existing image-mode no-media/reset behavior; no accidental physical presence |
| `SRC-09` | unsupported board and corrupted saved On bit | nonfatal message, bit forced Off, pins remain clamped |
| `SRC-10` | old 159-byte configuration | rejected by size, safe defaults, documented migration behavior |
| `SRC-11` | hard/soft reset while pending | deterministic default/retirement, no dirty loss or active output |
| `SRC-12` | image/physical ACK with mismatched source/media/request IDs | only exact active identities mutate FDC |
| `SRC-13` | dirty records 1–10 and every cache offset; final success clear one cycle before/on/after quiet boundary | event wins races, quiet restarts, one old-medium ten-record dump retires, no acknowledged byte is lost |
| `SRC-14` | disk change during each stream/buffer state; duplicate raw activity while the latch is set; independently delay WD/backend control-generation ACKs; source/media/request/buffer IDs and the retained entry generation forced through FFFE/FFFF/wrap | one lossless old-generation event causes exactly one source-manager increment; old request retires with its old tuple; zero never becomes live, either missing ACK blocks admission, and event/entry wrap-pending forces safe close/full endpoint clear before new value 0001 with no stale alias |
| `SRC-15` | stock `U0>I` values 0, 1, 32, 255; maximum `U0>R`; verify on/off | switch waits for observed success, not 500 ms or a calculated ROM timeout; 120 s bound remains |
| `SRC-16` | menu/core pause while stock cache dirty and switch pending | drive divider continues; flush/retirement progresses; safety clock never pauses |
| `SRC-17` | `$0087` clears via success, controller error, disk change, reset, burst failure, BUFMOVE, and `M-W` | only classified success can satisfy drain; every discard/ambiguous path rejects and identifies reason |
| `SRC-18` | bundled MIFs reconstructed; custom load empty, short, exact, oversized/wrapping, interrupted, one-byte-mutated, or readback-corrupt | only exact full readback digest selects a profile; partial/error state persists; both bundled MIFs match stock |
| `SRC-19` | unknown/Jiffy profile after media work versus cold held-reset boot | live change rejects with restart guidance; initial pre-release source selection is allowed and never called data preserving |
| `SRC-20` | `rom_std_i`/replacement request with dirty stock cache | effective old ROM remains latched through drain; new bytes become effective only under held drive reset |
| `SRC-21` | lower image flush or physical write returns failure after ROM cache becomes clean | no commit; old source resumes safely, error remains visible, no false success from idle |
| `SRC-22` | IEC ATN/data/clock or WD access at every cycle around admission/reset arbitration | work wins the boundary, no command is half-admitted, no drive bus output freezes asserted |
| `SRC-23` | custom BRAM write while custom slot active; slot request during every drain phase | code never mutates under running T65; old profile drains first, reset holds, generation/profile commit atomically |
| `SRC-24` | D64 GCR track dirty at every byte; activity-stop save, head-move save, explicit drain; source change and soft reset | old track generation writes completely, matching success precedes dirty clear/reset, then lower cache drains; D64 hash survives |
| `SRC-25` | c1541 save request/ACK partial, duplicate, timeout, mount/change, reset, track change, generation wrap | fault/reject, never false clean; old engine/source remains active and acknowledged GCR data is not silently discarded |
| `SRC-26` | Image engine changes D64<->D81 while pending/Physical; staged D64 while physical 1581 cache dirty; dirty cache in each old engine | derived old running engine selects exactly one upper drain; physical always drains c1581; staged target commits only under held reset; irrelevant 1581 profile never vetoes a running D64 drain |
| `SRC-27` | soft C64/drive reset with dirty 1581 side, dirty 1541 track, dirty lower cache, unknown ROM, and injected flush error | C64 may reset, drive reset waits for selected upper+lower success or is rejected; only explicit hard reset takes recorded discard path |
| `SRC-28` | source/ROM/soft-reset request in every cycle from terminal Write Sector CRC through WD done, final FF, WGATE close, and 700-us guard | admission may block after exact upper proof, but old writer/safety logic remains alive; final FF closes normally, guard retires, and only then may held drive reset assert; no acknowledged write is truncated |
| `SRC-29` | assert/release menu/core pause in physical idle-with-CIA-motor-on and every spin/search/step/read/write/DRQ/F7/tail/guard/late-fault phase | C64/UI pause may proceed, but 1581 CPU/WD/CIA/CDC/cache clocks run for the entire Physical epoch; ROM can turn motor/select off, commands/tokens retire normally, no pause-induced zero/fault occurs, and drive pause becomes eligible only after a safe committed transition to Image |
| `SRC-30` | Physical -> Image -> Physical with no observed pin event, with media changed while the physical controller is inactive, and with a change latch already pending at re-entry | every return advances the retained nonzero entry generation before broadcast; a pending latch then emits one event naming that tag and advances once more; both consumers ACK in order, no new request crosses the update, and Image continues to publish zero without erasing the retained counter |

Run all four `menu_test.py` modes, menu-ROM rebuild, and a settings save/load
round trip for the new 160-byte layout. Verify every named flat index against
the generated structure.

### 19.10 Image and IEC regression

Before physical work, execute and record the existing issue-#91 D64/D81
hardware checklist in `tests/README.md`; otherwise physical failures are
confounded with an unvalidated simulated-1581 baseline.

With source fixed to Image, compare pre-feature and post-feature traces/hashes
for:

- D64 directory/read/write, write protect, change, and drive 8/9 selection;
- D81 mount, all-sector read, file copy, scratch, validate, format/write-back,
  cache dirty/flush, reset prevention, unmount/remount, and write protection;
- stock 1581 ROM and supported JiffyDOS ROM;
- IEC ATN/CLK/DATA behavior, activity/power LED, PRG mount, cartridge, REU,
  and menu operations affected by shifted indices;
- empty/no-mounted image behavior;
- rapid reset and source toggle with no dirty cache.

No physical input may perturb an Image trace. No new physical logic may issue
an SD request in Physical mode. Drive 9 must work while drive 8 uses the
internal mechanism. C128 burst fast serial is not an acceptance claim.

### 19.11 Hardware bring-up gates

Hardware enablement is monotonic and destructive output is introduced only
after the preceding evidence is reviewed:

| Gate | Enabled functions | Exit evidence |
| --- | --- | --- |
| H0 | all outputs still constants; raw input capture only | schematic map, configuration levels, pull-ups, polarity, pulse widths, index/RDATA captures |
| H1 | select, CIA motor, side; no STEP or write | motor startup/ready/no-index measurements; outputs return inactive on reset |
| H2 | STEP/DIR and read pipeline; WGATE/WDATA still hard high | Restore/seek geometry, track0, disk-change clear, all-sector golden read |
| H3 | WD Read Sector/Address/Track through IEC/direct diagnostics | CRC/deleted/error/status tests and genuine-1581 disk read |
| H4 | Write Sector on labelled sacrificial DD media | WP clamp capture, splice/pulse/precomp measurements, read-back on core and genuine 1581 |
| H5 | Write Track/format on labelled sacrificial DD media | blank-disk format, index termination, 1,600-sector verify both directions |
| H6 | user menu capability enabled | image regression, reset/source faults, all builds/timing, documentation and release evidence |

At H0, measure raw RDATA on outer, middle, and inner tracks. At H4/H5, scope
both FPGA-side buffer and drive connector for WGATE, WDATA, INDEX, SIDE,
SELECT, MOTOR, STEP, DIR, WP, and reset. Do not enable H4 merely because an ILA
looks correct; the external buffers and magnetic mechanism are part of the
system.

### 19.12 Real-media and interoperability matrix

Use genuine 3.5-inch DD media. Taped-hole HD media, USB mechanisms, and image-
only emulators do not satisfy a hardware row. For each qualified mechanism
profile, use at least two mechanism units and five labelled disks spanning at
least two manufacturers/lots where available, including one used/aged but
error-free disk. Use at least one physical board of every advertised revision.

Required tests:

1. Format a disk in a genuine Commodore 1581; on this core read all 1,600
   sectors of the side-asymmetric payload and compare its manifest.
2. Format blank DD media through the core’s IEC-visible 1581; read every sector
   on a genuine 1581 and perform DIRECTORY, file copy, scratch, rename, and
   VALIDATE.
3. Write files/selected sectors alternately on genuine 1581 and core, power
   cycle between stages, and verify full-disk hashes/content each time.
4. Exercise cylinders 0, 1, 39, 40, 78, and 79 on both sides, all sectors, with
   alternating `00`, `FF`, `AA`, `55`, walking-bit, PRBS, and payload values
   F5/F6/F7/A1/C2.
5. Read and direct-FDC-write a deleted-data-mark sector; verify F8 status and
   data independent of CRC.
6. Present write-protected media for sector and format commands; capture that
   WGATE never asserts. Toggle protection during a sacrificial write and verify
   the fastest clamp/fault behavior.
7. Eject/insert during spin-up, ID search, read capture, DRQ drain, queued
   write, active sector write, and format; verify epochs, safe close, change
   latch, and recovery.
8. Remove media, stall spindle if safely possible in a test fixture, disconnect
   index in a breakout fixture, and use blank media; distinguish bounded
   Not Ready/No Index/RNF.
9. Run at least ten complete format/read/verify cycles and 1,000 rewrite/read-
   verify cycles distributed across inner and outer test sectors; no silent
   corruption or accumulating position error is allowed.
10. Run cold-start and at least one-hour warm tests, repeated reset/menu open,
    C64 mode changes, and IEC traffic during motor operation.
11. Write exactly one sector, then compare all 1,600 sectors and prove the other
    1,599 unchanged. Use Read Track/raw-transition captures to prove adjacent
    ID/gap/sector fields and both neighbouring cylinders also survived.
12. Disconnect/suppress the ending index during active format. The predictive
    tail close makes WGATE connector-high before the earliest plausible next
    index; the later no-index watchdog completes without any following-
    revolution magnetic pulse.
13. At preamble, payload, CRC, trailing FF, ending index, and post-write guard,
    inject hard reset, PLL unlock, FPGA reconfiguration, source-switch request,
    and controlled FPGA brownout/power loss while drive power remains. Capture
    both FPGA-side and connector pins and inspect the complete sacrificial disk.
14. Inject raw WP and disk-change pulses at
    `G_RAW_KILL_MIN_NS-1/at/+1`, wider sub-50-MHz widths, and swept phases;
    verify the profiled capture guarantee. Any captured assertion closes once
    and cannot reopen.
15. Exercise RPM immediately inside and outside `index_write_locked`; reads may
    proceed within broad plausibility, but Write Sector and Write Track are both
    refused outside the qualified write-rate profile.
16. With a qualified index-breakout/pulse fixture and sacrificial media, inject
    armed-window start candidates at `G_INDEX_START_MIN_US-1/at/+1` and swept
    clock phases. Confirm connector WGATE never asserts below the inclusive
    threshold, the original-edge-to-WGATE `L_start` bound holds at/above it, and
    a subsequently rejected pulse closes/faults without a second opening.
17. Use a generated track with a valid matching ID deliberately too late for a
    complete 531-byte sector splice before `P_write_min`. Confirm the
    preauthorization equation refuses WGATE and full-track readback is unchanged;
    then move the ID to the exact safe boundary and verify normal write. Inject a
    distinct fast index during each active sector phase and prove immediate
    close/no following-revolution pulses.

Every destructive test starts with expendable media, an explicit operator
warning, verified write-protect expectations, and a capture trigger armed.
“Directory looked right” is never a data-integrity pass; compare all bytes and
expected CRC/error status.

### 19.13 Application and DOS compatibility

Run the issue-motivating workflows on qualified hardware, not only synthetic
FDC benches:

- DraCopy identifies the internal source as a 1581 and completes verified
  whole-disk physical-to-image and image-to-physical copies;
- GEOS opens directories, reads/writes files, validates media, and completes
  disk-copy workflows in both source directions;
- direct-FDC identification/probe utilities observe the WD1772 command/status,
  DRQ, programmed-I/O delays, and documented Write Sector extra-revolution
  deviation;
- stock DOS error-channel responses are checked for no disk/no index, write
  protect, RNF, bad ID CRC, bad data CRC, disk change, and unsupported format;
- an external real IEC device 9 coexists during physical drive-8 traffic;
- an external device 8 double-responder case shows the documented warning and
  is never presented as supported simultaneous operation.

All copy workflows end with complete 1,600-sector hash comparison, not only
file-directory success.

### 19.14 Coverage closure

Functional coverage crosses:

- operation x terminal result x source;
- WD command flags x DRQ early/on-time/late;
- cylinder class (outer/middle/inner) x side x sector;
- FB/F8 x good/bad ID CRC x good/bad data CRC;
- motor/ready/index/change/WP state x command phase;
- Force/reset/source change x every FSM state;
- each gap class and threshold x asynchronous phase;
- buffer/FIFO owner x cancellation/reset;
- each advertised board/mechanism profile x H0–H6 gate.

All reachable FSM states and transitions must be covered. Unreachable bins are
justified by an assertion/proof, not deleted to improve the percentage. Safety
assertions have mutation tests showing that each would fail if its guarded
condition were removed.

## 20. Build, resource, timing, and CDC acceptance

### 20.1 Recorded pre-feature baseline

At C64MEGA65 `895078f1f8abe68ee9e5595926fdfb2ba57f44a4`, the recorded implementation
baseline is:

| Target | LUT | BRAM | IOB | WNS | WHS | Known exception |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| R3 | 26,966 | 168.5 | 179 | +0.376 ns | -0.057 ns | one pre-existing hold endpoint |
| R4 | 24,713 | 204 | 215 | +0.274 ns | +0.049 ns | none |
| R5 | 24,629 | 204 | 225 | +0.411 ns | +0.053 ns | none |
| R6 | 26,943 | 168.5 | 243 | +0.322 ns | +0.050 ns | none |

These values are comparison anchors, not permanent device limits. Before
implementation, rerun baseline and feature builds with the same Vivado version,
host settings, constraints, and seeds; retain both reports. Placement variation
must not be mistaken for a feature regression or used to dismiss one.

### 20.2 Mandatory build results

R3, R4, R5, and R6 must all complete synthesis, implementation, bitstream, and
release packaging. Acceptance requires:

- nonnegative setup WNS on every target;
- nonnegative hold WNS/WHS on R4–R6;
- no new failing hold endpoint on R3; if the single known R3 endpoint remains,
  prove it is the same path and no worse than the same-run baseline. Fixing it
  is preferred but unrelated closure is not charged to issue #90;
- no new unconstrained internal path, generated-clock error, clock interaction
  critical, latch, multiple driver, combinational loop, or methodology Critical;
- no CDC Critical and no unreviewed waiver;
- no broadening of existing drive exceptions or wildcard collision with
  generic names such as `busy`;
- all physical output registers and external asynchronous inputs reported in
  their intended I/O/CDC categories;
- resource use within the target device and at least 10% remaining headroom in
  LUT, FF, and BRAM after debug ILA removal;
- identical functional physical-feature source lists and ABI widths in all four
  projects;
- menu/config tests and generated ROM/config artifacts built from the same
  commit as the bitstream.

Report LUT/FF/BRAM/IOB/BUFG deltas by new module. A result that fits only after
removing required safety diagnostics, weakening the proven functional elastic
queues, or merging the independent write-protect firewall is rejected. The
optional out-of-band 8 KiB diagnostic track capture may be omitted without
altering WD behavior.

### 20.3 Timing outside synchronous STA

FPGA STA alone does not prove external floppy timing. The qualification report
must correlate cycles, post-route simulation where useful, ILA timestamps, and
connector measurements for:

- configuration/reset inactive levels;
- RDATA minimum pulse capture;
- WDATA pulse width and transition displacement;
- WGATE lead, duration, close, and raw-WP clamp latency;
- direction setup, STEP width/interval, and head settle;
- side/select validity;
- index pulse/period and motor-ready delay;
- 700 us post-write guard;
- safe clock-loss/reset behavior.

Measured extrema must remain inside section 7/11/12 limits with at least one
50 MHz cycle of digital margin and the external mechanism’s specified analog
margin. If they do not, update the qualified profile and rerun every dependent
test; do not edit a comment to match the waveform.

## 21. Implementation sequence and review gates

### Phase 0: freeze evidence and image baseline

- Reproduce source/build hashes and all four timing/resource reports.
- Run issue-#91 D64/D81 regressions and record media hashes.
- Complete schematic/top/XDC pin matrix and H0 input-only captures.
- Freeze the flat ABI, result enum, timing package, and test plan in review.

Exit: no unresolved port polarity/voltage/configuration-safe-state question for
the first advertised boards; automated baseline is reproducible.

### Phase 1: codec, timers, and safety in simulation

- Implement resettable CRC, RDATA/index inputs, gap/bit/byte decoder, MFM
  encoder, small live track CDC queues, optional out-of-band capture, sector buffer, timers, safety firewall, and
  diagnostics with outputs disconnected.
- Pass sections 19.4, 19.5, safety invariants, and CDC primitive tests.
- Compare adapted MEGA65 helpers against upstream vectors and provenance.

Exit: tolerated jittered flux -> decode -> re-encode preserves semantic bytes,
marks, CHRN, and CRC. Exact raw-word/transition equivalence is required only
for canonical fixed-phase encoder vectors with a fixed P/precomp state; analog
jitter/phase is intentionally normalized. Fault injection cannot create a
dangerous output request.

### Phase 2: physical mechanics without write

- Connect only capability-gated select, CIA motor, side, direction, and step;
  WGATE/WDATA remain independent hard-high constants.
- Complete H1/H2 readiness, Restore/Seek, track-zero, disk-change, RPM, and
  whole-disk raw decode tests.

Exit: two sides and all 80 cylinders are reached exactly, all 1,600 golden
sectors decode, and reset/menu activity leaves mechanics safe.

### Phase 3: WD physical read path

- Add requests/results, real Type-I Verify, Read Sector, Read Address, Read
  Track, DRQ/IRQ/error behavior, and Force Interrupt.
- Add source manager in a developer-disabled capability build.
- Pass WD-01 through WD-14, WD-19/21/23/25–34/39–41/43/47–48 as applicable to the
  read-only build, plus CDC and H3. Tests that exercise a write command in this
  phase must keep the final WGATE/WDATA firewall hard-disabled and verify the
  bounded write-protect/unsafe-backend result rather than emit a pin pulse.

Exit: genuine-1581 media reads completely through the IEC-visible drive and
all injected media errors map correctly; Image remains identical.

### Phase 4: source UI and reset/cache integration

- Add desired/active/pending source, drive-local reset, IEC quiet detector,
  latched D64/D81 engine, stock-1581 cache/profile classifier, generation-tagged
  1541 GCR-track drain, successful-write retirement ledger, saved
  menu/config migration, nonfatal unsupported/unknown-ROM UI, and diagnostics.
- Pass all source/menu/image tests before enabling any write output.

Exit: rapid switches, every dirty/cache-discard path, runtime-modified ROM
timeouts, pause, live ROM changes, resets, empty media, and unsupported boards
cannot mix backends or silently lose acknowledged old-medium data.

### Phase 5: sector write

- Enable WDATA generation behind still-disabled WGATE and validate scope timing.
- Enable WGATE only on a dedicated destructive build after WP clamp review.
- Implement normal/deleted Write Sector, host Lost Data, splice, post-write
  guard, two-pass occurrence fingerprinting, all-write RPM authorization,
  multiple-sector child retirement, late-fault arbitration, and Force Interrupt
  safe close.
- Pass WD-15–20, WD-23–25, WD-27–28, WD-31, the Write-Sector portions of
  WD-35–43 plus WD-46/48/49, IN-13, every sector-write safety test, H4, and
  bidirectional sector interoperability.

Exit: every written pattern reads identically on core and genuine 1581, and
write-protected media shows no WGATE pulse at the connector.

### Phase 6: track write and format

- Implement Write Track tokens, armed index-anchored start, conservative
  pre-index magnetic tail close, retrospective ending-index qualification,
  stream underflow, real CRC insertion, filler suppression, and precomp profile.
- Pass the Write Track cases in WD-22/24/25/27–28/35/37/38/44–45/48–49, MFM-W03–07,
  IN-06–12, every track-write safety test, H5, blank-disk format, whole-disk
  interoperability, error injection, and endurance tests.

Exit: core-formatted and genuine-1581-formatted media pass both machines and
all 1,600 sectors; WGATE closes before the earliest credible next index and
never reopens while the actual ending edge is qualified retrospectively.

### Phase 7: closure and release

- Run all automated/hardware matrices, all targets, CDC/methodology reports,
  menu/config generation, packaging, and documentation.
- Check in qualification/provenance evidence and advertise only passing
  board/mechanism profiles.
- Enable the production capability/menu behavior only in this phase.

Exit: every item in section 22 is checked with an artifact or explicit
reviewer sign-off.

Phases may be developed in parallel behind hard-disabled outputs, but no
destructive hardware gate or user-visible support claim may be skipped.

## 22. Release acceptance checklist

### 22.1 Functional and compatibility

- [ ] Internal 1581 is selectable as drive-8 media; Image is safe default.
- [ ] Empty physical drive remains IEC-visible and fails commands boundedly.
- [ ] Standard geometry and LBA/logical mapping match section 6.
- [ ] Restore/Seek/Step/Verify move and report the real mechanism.
- [ ] Read/Write Sector, Read Address, Read/Write Track, multiple R increment,
      deleted marks, Force Interrupt, DRQ, IRQ, and status pass the WD matrix.
- [ ] All 1,600 side-asymmetric golden sectors compare byte for byte.
- [ ] Bad ID CRC, missing DAM, bad data CRC, wrong H, unsupported N, no index,
      disk change, write protect, Lost Data, and internal faults remain distinct
      where specified.
- [ ] Bad-data-CRC payload is delivered once and reported, not retried/replaced.
- [ ] Standard blank DD media can be formatted through the IEC-visible 1581.
- [ ] Core- and genuine-1581-formatted disks work bidirectionally.
- [ ] DraCopy physical/image copies, GEOS workflows, direct-FDC probes, DOS
      error channel, and external device-9 coexistence pass section 19.13.
- [ ] Stock 1581 ROM and supported JiffyDOS drive operation pass; only exact
      cache-qualified effective-ROM digests permit a data-preserving live source
      switch, and no C128 burst claim is made.

### 22.2 Safety and physical behavior

- [ ] Configuration, reset, unqualified board, Image mode, and clock loss put
      every physical output in its documented safe state.
- [ ] Drive B motor/select are permanently inactive.
- [ ] CIA PA2 alone owns normal physical motor request; PA0 side and CIA status
      polarities are verified.
- [ ] One host STEP pulse moves one cylinder; direction, pulse, interval,
      settle, side, and motor timings meet measured bounds.
- [ ] Hard/truncated STEP, mechanism power/reset, disk change, or settled
      Track-Zero contradiction invalidates position; every Type-II/III command
      requires explicit successful Restore, and outward Seek never pulses at T0.
- [ ] WGATE requires independent authorization and WDATA never occurs outside
      it.
- [ ] Current-generation `index_write_locked` gates every sector/track WGATE;
      broad read-only RPM plausibility never authorizes fixed-rate writing.
- [ ] Raw/synchronized WP assertion prevents or clamps writing; protected-media
      scope capture contains no WGATE pulse for an accepted command.
- [ ] Every connector WP/change pulse at or above the Q-07-qualified
      `G_RAW_KILL_MIN_NS`, including sub-clock widths, directly sets
      `outer_write_kill`; connector WDATA becomes inactive no later than WGATE,
      both within `D_raw_kill_clamp_max <=2 us`, while mechanics remain latched
      through guard; WGATE/WDATA cannot reopen until idle, guard complete, and
      filtered acknowledged release.
- [ ] No mechanics/control change occurs during WGATE or 700 us guard.
- [ ] CIA motor-off during WGATE becomes pending; actual MOTOR/SELECT and latched
      writer readiness remain stable through close/guard, then Ready drops.
- [ ] Ordinary fault closes write then holds mechanics through guard; hard_fail
      uses the independently clocked/asynchronous connector-safe path.
- [ ] A raw fast index edge alone never starts Write Track; the armed,
      current-generation candidate must pass the profiled inclusive minimum-low
      filter, while full pulse qualification remains retrospective.
- [ ] Write Track timestamps that original candidate, closes on an earlier
      ending fast edge or conservative pre-index tail deadline, completes
      canonical records including measured `L_start`, and never waits for
      retrospective width before magnetic close.
- [ ] Every write/reset/Force/source-change path reaches a bounded safe close.
- [ ] Outer writer class/identity is acknowledged before WGATE and immutable;
      sector duration, track tail/end, first-WDATA, heartbeat, and mechanism-
      power clamps are independent of writer/drive pause and meet connector bounds.
- [ ] Index/start/search/restore watchdogs expire without depending on Ready or
      an index edge.
- [ ] Disk change is sticky, invalidates all data/intent, and clears only by the
      qualified visible-step procedure.

### 22.3 Integration and state ownership

- [ ] Image and physical mechanics/results are mutually exclusive per source/media/request identity.
- [ ] No physical command is translated to an LBA or auto-seek.
- [ ] Mounted image remains clean/staged in Physical and resumes unchanged.
- [ ] Dirty image/source switching uses held drive-local quiesce/reset, not a
      dropped finite `RESET_CORE` pulse.
- [ ] D81/Physical uses the qualified 1581 side-cache proof; D64 uses the
      generation-tagged 1541 GCR-track flush proof; admission then blocks while
      Image drains lower `vdrives` or Physical reaches write-close/guard-done;
      only afterward may held drive reset assert, and soft drive reset follows
      the same selected-engine branch.
- [ ] The bundled ROM digest, `$0087` classifier, opcode-fetch context, all
      success/discard paths, and generation-tagged backend retirement satisfy
      section 15.3; dirty-byte zero or WD idle alone never means clean.
- [ ] Unknown/unqualified ROM and the 120-s timeout reject a live switch without
      pretending reset/discard is data preserving; cold held-reset selection is
      tested separately.
- [ ] The 500 ms IEC quiet detector uses explicit bus/activity signals as an
      admission race barrier, not as a ROM-cache flush delay.
- [ ] Live ROM selection/upload and media-source selection share the held-reset
      drain transaction; pending drain continues while ordinary pause is active.
- [ ] Rapid menu/reset/source changes cannot expose stale data or acknowledgments.
- [ ] Source epoch, physical-media generation, request ID, and buffer generation
      are distinct and match on every accepted event; the source manager alone
      owns global generations, the WD frontend alone allocates command/request/
      buffer identities, and dual-ack publication blocks new admission while an
      interrupted old-generation request retires under its latched tuple. Image
      publishes media zero; first/return Physical entry establishes/advances a
      retained nonzero tag before any Physical tuple or event is legal.
- [ ] Unqualified boards reject On nonfatally and remain electrically clamped.
- [ ] `G_VDNUM`/`C_VDNUM` remains one; drive 9 and external IEC behavior regress.
- [ ] Physical busy/write-critical are explicit controls, not inferred from LED.

### 22.4 Verification, build, and release artifacts

- [ ] All deterministic/random unit, WD, fault, CDC, source, image, and menu
      tests pass with seeds/artifacts retained.
- [ ] Safety assertions/formal properties and mutation tests pass.
- [ ] H0–H6 hardware gates have signed evidence.
- [ ] Required disk/mechanism/board sample matrix and endurance tests pass.
- [ ] R3–R6 synthesize, implement, generate bitstreams, and package.
- [ ] Setup/hold, unconstrained paths, CDC, methodology, resources, I/O timing,
      and exceptions meet section 20.
- [ ] The 160-byte config migration and regenerated menu ROM/settings ship.
- [ ] Submodule commit and parent pointer contain only intended changes.
- [ ] MEGA65-derived files carry correct LGPL provenance; new files carry
      project licensing.
- [ ] FAQ, README, versions/roadmap, tests, menu help, user guide, board matrix,
      qualification record, and release notes are updated.
- [ ] Release wording lists only the board/mechanism profiles actually passed.

## 23. Prohibited shortcuts

The following are explicit review failures:

- live-muxing the physical mechanism onto `sd_lba/sd_rd/sd_wr` as the final
  architecture;
- using virtual `floppy.v` index/head/sector timing in physical mode;
- auto-seeking to decoded CHRN or requested LBA during Type-II/III commands;
- instantiating all of `sdcardio.vhdl` or copying its F011 policy;
- using MEGA65 `internal1581.vhdl` as though it were an active physical FDC;
- returning delayed success for Read Track, Write Track, CRC, write protect, or
  any unsupported command;
- waiting for Ready before starting the only no-index watchdog;
- comparing H as a WD1772 Type-II match or using it to mask side wiring errors;
- discarding bad-data-CRC bytes, silently retrying them, or reporting a later
  good copy;
- treating F5/F6/F7 as tokens outside Write Track;
- writing a fixed 6,250-byte track without the real ending index;
- waiting for retrospective index pulse-width validation before closing WGATE;
- using a whole-track functional FIFO to replay/prefill WD DRQs;
- allowing CPU/FIFO buffering to remove WD DRQ deadlines;
- reporting internal codec overflow as ordinary host Lost Data;
- relying on synchronized status alone instead of a final raw-WP write clamp;
- allowing a transient raw kill to clear/reopen within the current writer;
- conflating CIA `media_ready`, `read_path_valid`, and `mechanics_reusable`;
- conflating WD Busy/INTRQ, physical write-close, and guard completion;
- letting a menu bit, diagnostic register, LED, or firmware directly drive
  MOTOR/STEP/WGATE/WDATA;
- switching sources while image cache is dirty, a request/result is live, or
  physical write/guard is active;
- resetting only the outer FSM while retaining decoder/CRC/FIFO state;
- using a pulse CDC for multi-bit payload, a guessed coincident clock, broad
  false paths, or wildcard timing exceptions;
- enabling unknown/custom boards by default or assuming connector conventions
  prove board electrical behavior;
- claiming generic WD1772, FD-2000, HD, USB, flux-archive, or full burst-mode
  support from this standard-1581 implementation;
- closing issue #90 for read-only/preformatted support while format/write
  remains a fake success.

## 24. Measurements that must be frozen before production enablement

The architecture and safety policy above are binding. These remaining values
are deliberately resolved by measurement into board/mechanism profiles rather
than guessed in RTL:

| ID | Measurement | Required artifact / decision |
| --- | --- | --- |
| `Q-01` | each advertised board/build profile’s schematic-to-connector map | pin, voltage, buffer direction/OE, pull-up, polarity, safe configuration level |
| `Q-02` | shipped mechanism models, cable/strap population, 5-V/reset/REN topology | qualified profile; pin 2 DD level; pin 34 Disk Change semantics; autonomous recalibration duration; proof mechanism reset is common with FPGA or a raw monitor asynchronously clamps writers, invalidates position, and holds release through stable-power/recalibration/Restore |
| `Q-03` | power-up/reset/QNICE-clock/raw-100-MHz/PLL-loss outputs | proof and schematic/RTL trace of heartbeat, exported lock/reset, final IOB/OE primitive, pull-ups/buffer; inactive MOTOR/SELECT/STEP/WGATE/WDATA and defined side/dir/density at connector |
| `Q-04` | motor/index across units/media/PVT, ordered-period changes, plus false/runt pulse injection | startup deadline, pulse width, operational period/warning bands; conservative `P_write_min/max` after uncertainty and worst one-revolution change; proof no estimator tightens them; false-pulse floor, frozen `G_INDEX_START_MIN_US`, original-edge `L_start`, and proof it remains below full 1.5-ms qualification |
| `Q-05` | RDATA across cylinders 0/40/78/79 and both sides | pulse width, jitter, 4/6/8 us classifier windows, glitch floor |
| `Q-06` | STEP/DIR/side/select at final IOB and connector across PVT | polarity, pulse, intervals, frozen `D_dir_step_relative_max`/`D_step_trailing_max`/`D_select_assert_max`, `D_select_assert_max <=1 us`, >=24-us connector DIR setup, >=18-ms connector-trailing-to-access settle, change-clear behavior |
| `Q-07` | qualifying raw WP/change assertion at connector to WGATE/WDATA inactive at connector, with every clock/WDATA phase and PVT corner | direct-outer-path schematic/RTL proof; pad/buffer/primitive minimum pulse and margin; frozen `G_RAW_KILL_MIN_NS`; every-phase capture at/above it; WDATA inactive no later than WGATE; frozen `D_raw_kill_clamp_max <=2 us` or write/format capability remains off |
| `Q-08` | sector-write splice, connector propagation extrema including non-integral bounds, and forced serializer stall | fixed WGATE timing, 22-byte post-ID count, one trailing FF, 2-us nominal/8-us maximum first/last-WDATA envelope, frozen `D_sector_connector_delta_max`, inward/floor-rounded outer force threshold, normal close earlier, <=17.100-ms connector duration, following-ID preservation |
| `Q-09` | WDATA/WGATE and read-back with patterns/inner tracks, final-IOB-to-connector deassertion, and tagged close-ACK CDC at PVT extrema | pulse width, precomp off/on/magnitude, frozen normal first/last envelope and `L_data_start_max`, `D_wgate_deassert_max <=10 us`, `D_close_ack_max <=4 fdc_clk` cycles, >=700-us connector-relative and <=710.10-us IOB-relative ordinary guard, production profile constants, stock `N_format_required_max` capacity proof |
| `Q-10` | source/menu behavior on unqualified target | nonfatal forced-Off UX and corrupted-config safety |

Codec and non-destructive development may proceed before every profile is
complete, but WGATE stays hard-inactive until Q-01 through Q-07 pass for that
target. User-visible write/format capability stays off until all Q items,
H0–H6, and section 22 pass. A measurement may tune only the profiled constant
identified here; changing architecture, error semantics, or a safety invariant
requires specification review.

“All Q items” applies per advertised target/profile: R3/R3A and R6 each require
Q-01 through Q-10 and H0–H6. Unadvertised R4/R5/custom builds require proof of
configuration/runtime inactive outputs and successful compilation, but their
unfinished mechanism qualification does not block release of the two required
production profiles.
