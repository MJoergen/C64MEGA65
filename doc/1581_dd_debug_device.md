# Physical Internal 1581 — QNICE Diagnostic Device

**Device:** `C_DEV_C64_PHYS1581 = 0x0108` (defined in `CORE/vhdl/globals.vhd`)
**Module:** `CORE/vhdl/physical_1581/physical_1581_diag.vhd`
**Access:** observational, with one writable word (`WR_CTRL`, `0x9A`, map v8). Issue #90 (internal 3.5" DD floppy as a physical 1581, read path) and issue #244 (write path, map v8).

The MEGA65 has no oscilloscope or logic analyzer on the internal floppy bus, so this
register bank is the only on-hardware window into the physical-1581 read and write
paths. It surfaces the live pin levels, the controller state machine, the last decoded
sector result, the CRCs, the index/flux timing, a set of saturating event counters and
(map v8) the write instruments.

It is **observational**: it cannot move the head, spin the motor, open the write gate or
change any mechanism output. The one exception is `WR_CTRL` (`0x9A`, section 2.2), which
overrides the write precompensation for experiments; a QNICE write to any other word is
silently ignored. Reads never stall the QNICE bus.

The whole bank runs on the QNICE 50 MHz clock (`c64_clk_sd_i`), which is the *same*
clock as the `physical_1581_controller`, so every value below is a coherent snapshot with
no clock-domain-crossing artifacts. (The one exception is the single-bit `IMG_DRIVE`
word, which originates in the core clock domain and is 2-FF-synchronized on its way in —
being one bit, it cannot tear.)

---

## 1. How QNICE reads a core-specific device

Core devices are reached through the M2M "RAMROM" memory-mapped window (see
`M2M/rom/sysdef.asm`). Three QNICE MMIO registers select and read a device:

| QNICE address | Name              | Meaning                                            |
| ------------- | ----------------- | -------------------------------------------------- |
| `0xFFF4`      | `M2M$RAMROM_DEV`  | 16-bit device id — write `0x0108` to select this device |
| `0xFFF5`      | `M2M$RAMROM_4KWIN`| 4K window selector — write `0x0000` (this device fits in window 0) |
| `0x7000`      | `M2M$RAMROM_DATA` | base of the 4K MMIO window; word offset `N` is read at `0x7000 + N` |

So a register at **word offset `N`** in the map below is read at QNICE address
`0x7000 + N`, after `0xFFF4` has been set to `0x0108` and `0xFFF5` to `0x0000`. Each
offset is one 16-bit word (the device is word-addressed, not byte-addressed).

This mirrors how the Shell reads other core devices (e.g. `M2M/rom/coreinfo.asm` reads the
core name from the config device the same way).

---

## 2. Register map

64 words at offsets `0x00`–`0x3F`, the 64-word WD-dialogue trace ring at
`0x40`–`0x7F` (section 2.1) and the 30 write words at `0x80`–`0x9D` (map v8,
section 2.2). Any other offset reads `0x0000`. All multi-bit fields are
right-aligned unless a bit layout is given.

| Off  | Name              | Contents                                                        |
| ---- | ----------------- | --------------------------------------------------------------- |
| `0x00` | `SIGNATURE`     | constant `0x1581` — confirms you are talking to this device     |
| `0x01` | `VERSION`       | map version (high byte) / capability flags (low byte) — `0x08FE` (bit 0, "read-only", cleared since map v8) |
| `0x02` | `LIVE_IN`       | raw + conditioned input pin levels (bit layout below)           |
| `0x03` | `LIVE_OUT`      | driven mechanism output levels + enable (bit layout below)      |
| `0x04` | `CTRL_STATE`    | controller state flags + read/write/step FSM phase (bit layout below) |
| `0x05` | `HEAD`          | head cylinder estimate + valid + last direction (bit layout below) |
| `0x06` | `LAST_RESULT`   | last completed read result (bit layout below)                   |
| `0x07` | `CHRN_CR`       | found C (high byte) / found R (low byte) of the last read       |
| `0x08` | `CHRN_HN`       | found H (high byte) / found N (low byte) of the last read       |
| `0x09` | `ID_STORED_CRC` | stored CRC of the last decoded ID field (as read off the disk)  |
| `0x0A` | `ID_CALC_CRC`   | CRC residue after the last decoded ID field — `0x0000` = good  |
| `0x0B` | `DATA_CALC_CRC` | CRC residue after the last decoded data field — `0x0000` = good |
| `0x0C` | `CRC_FLAGS`     | bit0 = last ID CRC ok, bit1 = last data CRC ok                  |
| `0x0D` | `IDX_PERIOD_LO` | last index period (low 16 bits), in 50 MHz cycles               |
| `0x0E` | `IDX_PERIOD_HI` | last index period (high 16 bits) — one revolution is about 200 ms, i.e. `0x00989680` cycles |
| `0x0F` | `IDX_WIDTH_LO`  | last index low-pulse width (low 16 bits), in 50 MHz cycles      |
| `0x10` | `IDX_WIDTH_HI`  | last index low-pulse width (high 16 bits)                       |
| `0x11` | `GAP_LAST`      | most recent RDATA flux gap, in 50 MHz cycles (DD nominal `0x00C8`/`0x012C`/`0x0190` = 200/300/400) |
| `0x12` | `GAP_MIN`       | smallest non-zero flux gap seen since reset                     |
| `0x13` | `GAP_MAX`       | largest flux gap seen since reset                               |
| `0x14` / `0x15` | `CNT_IDX_RAW`   | counter: filtered index leading edges (low / high 16 bits) |
| `0x16` / `0x17` | `CNT_IDX_QUAL`  | counter: index leading edges while the motor is on         |
| `0x18` / `0x19` | `CNT_STEP`      | counter: completed Type-I steps                            |
| `0x1A` / `0x1B` | `CNT_READOP`    | counter: completed read operations                         |
| `0x1C` / `0x1D` | `CNT_RNF`       | counter: read ops ending "record not found"                |
| `0x1E` / `0x1F` | `CNT_CRCERR`    | counter: read ops ending in a CRC error                    |
| `0x20` / `0x21` | `CNT_CANCEL`    | counter: read ops cancelled (Force Interrupt)              |
| `0x22` / `0x23` | `CNT_CHANGE`    | counter: disk-change latch events                          |
| `0x24` / `0x25` | `CNT_IDDEC`     | counter: decoded ID fields (any CRC)                       |
| `0x26` / `0x27` | `CNT_GAPERR`    | counter: out-of-spec flux gaps (loss of lock)              |
| `0x28` | `IMG_DRIVE`     | bit0 = the simulated (disk image) drive 8 is busy or holds unsaved data |
| `0x29` | `TRC_CNT`       | total WD-dialogue trace events since reset (ring holds the last 32) |
| `0x2A` | `FIFO_LEVEL`    | live read-FIFO occupancy in bytes (write-side view, 0–512)      |
| `0x2B` | `LAST_PRESENT`  | bytes the WD presented during the last finalized operation (512 for a clean sector read, 6 for Read Address, 0 for Verify) |
| `0x2C` / `0x2D` | `CNT_LOST`      | counter: LOST DATA events (a paced byte overwrote an unconsumed one) |
| `0x2E` / `0x2F` | `CNT_DRAIN`     | counter: between-ops FIFO drain episodes (residue discarded)  |
| `0x30` / `0x31` | `CNT_STALEDONE` | counter: completion edges ignored — sequence-tag mismatch, or the completion of an already-cancelled operation (one benign event per Force Interrupt that lands mid-operation) |
| `0x32` / `0x33` | `CNT_BUSYCMD`   | counter: WD command writes ignored because the WD was busy executing a command |
| `0x34` / `0x35` | `CNT_RUNT`      | counter: merged RDATA runt gaps (flux glitches absorbed by the decoder input filter) |
| `0x36` | `EST`           | live half-cell estimate of the adaptive gap quantiser, Q8.4 fixed point: bits 11:4 = integer 50 MHz cycles (nominal `0x64` = 100), bits 3:0 = sixteenths |
| `0x37` | `RNF_CTX`       | last-RNF context: requested track (high byte) / requested sector (low byte), latched whenever a read operation completes with RNF set |
| `0x38` | `CNT_A1_CAND`   | 16-bit saturating counter: coarse L-M-L-M A1 candidates |
| `0x39` | `CNT_A1_REJECT` | 16-bit saturating counter: candidates rejected because the complete raw-word span is inconsistent with 14 estimated half-cells |
| `0x3A` | `CNT_A1_TRAIN`  | 16-bit saturating counter: complete qualified three-A1 trains |
| `0x3B` | `CNT_MARK_FE`    | 16-bit saturating counter: qualified A1 train followed by an ID mark (`FE`) |
| `0x3C` | `CNT_MARK_DAM`   | 16-bit saturating counter: qualified A1 train followed by a data mark (`FB`/`F8`) |
| `0x3D` | `CNT_DAM_UNARMED` | 16-bit saturating counter: data marks ignored because no CRC-valid ID or data lock-up armed them |
| `0x3E` | `CNT_MATCH_ID`   | 16-bit saturating counter: CRC-valid IDs matching the requested track/sector |
| `0x3F` | `CNT_DAM_MISS`   | 16-bit saturating counter: matching IDs after which the controller saw another ID or timed out before a DAM |
| `0x40`–`0x7F` | `TRC[0..31]` | WD-dialogue trace ring, two words per entry (section 2.1) |
| `0x80`–`0x9D` | write instruments | map v8, section 2.2 |

The original fifteen counters are 32-bit and **saturate** at `0xFFFFFFFF` (they never
wrap). Read the low word first, then the high word (`0x0000` in the high word while
values stay small). The eight counters at `0x38`–`0x3F` are single-word 16-bit
saturating counters.

Reads and writes share one request/done channel between the WD front end and the
controller. Since map v8 the read words `LAST_RESULT`, `CHRN_CR`, `CHRN_HN`
(`0x06`–`0x08`), `CNT_READOP`, `CNT_RNF`, `CNT_CRCERR`, `CNT_CANCEL` (`0x1A`–`0x21`) and
`RNF_CTX` (`0x37`) count and latch **read operations only**; write operations are counted
in the write words of section 2.2. The trace ring records both.

### Delivery v2 (map v4, words `0x2A`–`0x35`)

Since map v4 the WD front end delivers read data **disk-paced**, like the real WD1772:
every DD byte-time (32 us) the next byte from the read FIFO is presented on the data
register and DRQ is raised, whether or not the drive CPU consumed the previous byte. The
current physical path first uses the 512-byte FIFO as a CRC quarantine: a clean completed
sector is released at that pace only after the controller result arrives, while a CRC/RNF
failure is drained without being presented. Once a clean sector is released, an unconsumed
byte is still overwritten at the following byte time, the WD status shows LOST DATA (bit
2), and `CNT_LOST` increments. Busy is released one full byte-time after the last
presentation.
CRC-flagged error completions **never also set RNF**: the genuine 1581 DOS
ROM (318045-02) job epilogue at `$CD3F` indexes the table at `$CD5A` with
`(status >> 3) AND 0x0B`, and the CRC+RNF combination hits a `0x00` hole in that table —
the DOS would treat the corrupt sector as job SUCCESS and silently accept it. CRC-only
maps to job error 5 (DOS error 23, "read error"), which the DOS retries as intended.
`LAST_PRESENT`, `FIFO_LEVEL` and the five counters make every abnormal delivery event
(lost byte, discarded residue, stale completion, ignored command write, flux runt)
visible from QNICE. Capability bit 5 in `VERSION` announces that these words exist.

### Adaptive gap quantiser (map v5, words `0x36`–`0x37`)

Since map v5 the MFM gap classifier is adaptive: instead of fixed acceptance
windows with dead-bands between the gap classes, it tracks the live half-cell
length as an estimate (nominal 100 cycles), classifies every gap to the nearest
class in {2, 3, 4} half-cells via the midpoints at 2.5 and 3.5 times the
estimate, and accepts anything within half an estimate of a class center — so
every gap between 1.5 and 4.5 estimated half-cells decodes, with no dead-bands.
The estimate adapts by a fixed 1/8-cycle step per accepted gap toward the
observed value (median-seeking, robust against the systematic gap smearing that
peak shift causes on inner cylinders), is clamped to 90–110 cycles, and is
re-seeded to nominal on reset, at every operation start and on any loss of lock.

How to read the two words:

- **`EST` (`0x36`)** shows the estimate the classifier is using *right now*.
  `0x0640` is exactly 100.0 cycles (the value after reset, re-seed or on a
  perfectly nominal disk). A value pinned near `0x05A0` (90) or `0x06E0` (110)
  means the adaptation hit its clamp — the medium is far off nominal speed, or
  decodes are failing and the estimate keeps re-seeding mid-adaptation. Watch it
  during a long load: on healthy media it hovers within a few sixteenths of the
  disk's true speed for the cylinder being read.
- **`RNF_CTX` (`0x37`)** answers "*which* sector did the last RNF hit?" without
  catching the trace ring in time: high byte = requested track, low byte =
  requested sector, updated at every completion with the RNF flag (including
  not-ready and disk-changed completions, which also carry RNF). Compare it
  against `CNT_RNF` (`0x1C`): if `CNT_RNF` climbs while `RNF_CTX` stays on one
  track/sector pair, one specific sector is persistently unreadable; if
  `RNF_CTX` wanders, the misses are scattered (speed/media problem, not a
  single bad sector).

### Complete-A1 timing qualification (map v6, words `0x38`–`0x3A`)

The adaptive field classifier deliberately retains wide, no-dead-band gap windows.
Sync acquisition adds a format-independent invariant: each coarse L-M-L-M candidate
must span 14 estimated half-cells end to end, within half an estimated half-cell over
the complete word. This preserves peak-shifted stock-1581 and F011 address marks while
rejecting coherent splice residue whose individual gaps are class-valid but whose
errors all lean in the same direction.

`CNT_A1_CAND` counts every coarse candidate, `CNT_A1_REJECT` counts candidates rejected
by the aggregate span check, and `CNT_A1_TRAIN` counts completed three-A1 trains. On a
healthy ten-sector track there are normally ten ID and ten data address-mark trains.
Some physical write splices can themselves produce timing-valid trains, so a zero reject
count is not proof that every train is a real record. Capability bit 6 in `VERSION`
announces that these words exist.

### Record sequencing and DAM acquisition (map v7, words `0x3B`–`0x3F`)

Timing alone cannot distinguish a splice that happens to reproduce a complete A1 train.
Production therefore also enforces the IBM/WD record grammar: a data mark is accepted
only after a CRC-valid ID field and the data-field zero lock-up, and a qualified ID mark
re-anchors the parser if junk had started a bogus data parse. The data-only qualifier is
dual-format: stock WD1772 and MEGA65/F011 both write twelve zero bytes before a DAM, while
F011 ID fields can omit that preamble and therefore remain preamble-independent.

`CNT_MARK_FE + CNT_MARK_DAM` classifies the qualified trains whose following byte was a
supported mark; subtracting those from `CNT_A1_TRAIN` gives trains followed by some other
byte. `CNT_DAM_UNARMED` is direct evidence that an unsolicited or post-ID preamble-less
splice DAM was safely ignored. During a failed sector read, `CNT_MATCH_ID` and `CNT_DAM_MISS` distinguish
"target ID never found" from "target ID found, but its data mark was missed." Capability
bit 7 announces these counters.

### Media-ready restart and physical Read Address compatibility

Cold, changed, or newly enabled media still needs two motor-qualified index
edges before synthesized `media ready` asserts. Once that same medium has
completed a two-index qualification, an ordinary motor-off interval preserves
the proof: if `/DSKCHG` stayed clear, the next motor start reasserts ready after
the first fresh index. Reset/disable, raw disk change, or index staleness clears
the history and restores the two-edge rule. This matches the finite PA1 window
of the genuine 1581 ROM without weakening eject/reinsert detection.

Physical Read Address presents only sector IDs `1..10`. MEGA65 F011 formatting
can finish a CRC-valid sector-11 ID before index truncates its following record;
the stock ROM can mis-handle that out-of-range reply during rotational login.
The decoder and diagnostic counters still observe sector 11, and ordinary Read
Sector already matches only the requested sector; normalization is confined to
the physical Read Address result.

### 2.1 WD-dialogue trace ring (`0x29`, `0x40`–`0x7F`)

The ring records the last 32 operations the WD front end sent to the physical
controller — the exact "dialogue" the 1581 DOS conducts. `TRC_CNT` (`0x29`) counts
all events since reset; entry `k` (0–31) lives at `0x40 + 2k` (word `w0`) and
`0x41 + 2k` (word `w1`), and the newest entry is `(TRC_CNT - 1) mod 32`. Once more
than 32 events happened, the ring wraps and the oldest entries are overwritten.

Entry types (by `w0` bits 15:12):

| Type | `w0` | `w1` |
| ---- | ---- | ---- |
| `1` = STEP completed | `0x1000` \| dir`<<8` (`1` = toward track 0) \| head-cylinder estimate | bit0 = track0 after the step |
| `2` = op REQUESTED | `0x2000` \| op`<<9` (`0` sector, `1` address, `2` verify, `4` write sector, `5` write track) \| side`<<8` \| requested track | requested sector `<<8` |
| `3` = op RESULT | `0x3000` \| rnf`<<11` \| crc`<<10` \| deleted`<<9` \| found-H LSB`<<8` \| found C | found R `<<8` \| result code |

Write operations (map v8) are recorded like reads: a Write Sector REQUEST reads
`0x28xx`/`0x29xx` (op `4`, side bit 8), a Write Track `0x2Axx`/`0x2Bxx`, and the RESULT
carries the write result code (`0x00` OK, `0x09` write protected, `0x0B` lost data, …).
A dump after a `SAVE` shows the DOS's write-back order: the sector under the head first,
then the following ones, wrapping at the end of the track.

To capture a failure: reset/power-on, reproduce the failing access once, then dump
`MD 7000 703F` and `MD 7040 707F`. Every REQUEST is normally followed by its RESULT
entry; STEP entries in between show the seek pattern (direction + the controller's
head-position estimate at each step). This reconstructs where the DOS was heading,
what it asked to read, and what it got — without any scope.

The rare coincidence of two events in the same 50 MHz cycle records only the
higher-priority one (RESULT over REQUEST over STEP); `TRC_CNT` then undercounts by
one. Irrelevant in practice, noted for completeness.

`IMG_DRIVE` bit 0 is the mirror image of the `CTRL_STATE` busy bits for the *other* media
source: it is set while the image-backed drive 8 shows activity (drive LED, covering both
the 1541 and the 1581 image engines including WD1772 command-busy) or while a dirty
write-back cache has not been flushed to the SD card yet. The Shell consults it before it
allows switching drive 8 from disk image to the internal 1581 (the image drive can write,
so switching away mid-access or with unsaved data would lose data); `CTRL_STATE` gates the
opposite direction. Capability bit 3 in `VERSION` announces that this word exists.

### 2.2 Write instruments (map v8, words `0x80`–`0x9D`)

All counters are cumulative since the QNICE reset (there is no per-episode reset); the
"last op" words describe the most recent write operation that the controller completed
and are latched when it reports done. The writer's own counters (`CNT_WR_UNDERRUN`,
`WR_REASON_ACC`, `WR_PUSHFULL`, `WR_DISCARD`) are read live from the writer and reset
with it.

| Off  | Name               | Contents |
| ---- | ------------------ | -------- |
| `0x80` | `WR_STATE`        | live write state (bit layout below) |
| `0x81` | `WR_LAST`         | last write op: flags (high byte, below) / abort reason bitmask (low byte; `0` when the op ended before the writer session started) |
| `0x82` | `WR_LAST_CHR`     | last Write Sector: requested R (high byte) / requested C (low byte); H is `WR_STATE` bit 13 |
| `0x83` / `0x84` | `WR_GATE_CYC` | WGATE window of the last op in 50 MHz cycles (`0` if the gate did not open); a sector is exactly 849,600 = `0x000CF6C0` |
| `0x85` | `WR_BYTES_LAST`   | bytes (sector) or tokens (track) the controller took from the write FIFO in the current/last op: 512 for a sector |
| `0x86` / `0x87` | `CNT_WR_SECT`  | counter: Write Sector operations |
| `0x88` / `0x89` | `CNT_WR_TRACK` | counter: Write Track operations |
| `0x8A` / `0x8B` | `CNT_WR_GATE`  | counter: write operations in which WGATE opened |
| `0x8C` / `0x8D` | `CNT_WR_LOST`  | counter: write operations with LOST DATA (first-byte aborts and mid-op underruns) |
| `0x8E` / `0x8F` | `CNT_WR_WP`    | counter: write-protect refusals: the WD pre-check (no operation reaches the controller), the controller's own check and the live tab abort |
| `0x90` / `0x91` | `CNT_WR_ABORT` | counter: aborted write operations (all reasons) |
| `0x92` | `WR_REASON_ACC`   | OR of every writer abort reason since reset (reason bits below) |
| `0x93` | `CNT_WR_FIFO_OVF` | 16-bit: data-register writes the WD dropped (write FIFO full, more than 512 bytes, or after the feed fell) |
| `0x94` | `CNT_WR_UNDERRUN` | 16-bit: writer word underruns (structurally unreachable; must stay 0) |
| `0x95` | `WR_PRECOMP_CNT`  | precompensated WDATA pulses in the last op (about 1,800 for a sector on cylinders 1–43, 0 without precomp) |
| `0x96` | `WR_FIRST_MARGIN` | smallest first-byte margin seen since reset: byte-times of the 22-byte gap still left when the first data byte arrived (`0x00FF` = none yet) |
| `0x97` | `WR_DRQ_MARGIN`   | smallest write-FIFO level seen at a data pop in the last op (`1` = the FIFO held only the byte taken, `0` = a byte was lost, `0x00FF` = no pop) |
| `0x98` / `0x99` | `WR_TRK_CYC` | index-to-index cycles of the last Write Track (about 10,000,000 at 300 RPM) |
| `0x9A` | `WR_CTRL`         | **writable**: bits 1:0 = precomp mode, `0` follow the WD P bit (default), `1` off, `2` on, `3` = follow; reset `0` (section 3.5) |
| `0x9B` | `CNT_WR_FIN`      | 16-bit: write operations the WD front end finalized (it consumed the controller's done) |
| `0x9C` | `WR_PUSHFULL`     | 16-bit: MFM words refused by a full writer FIFO (must stay 0) |
| `0x9D` | `WR_DISCARD`      | 16-bit: writer sessions discarded at ARM because the tab was not qualified writable |

`0x80` **`WR_STATE`**

| Bit  | Meaning | Bit | Meaning |
| ---- | ------- | --- | ------- |
| 3:0  | write FSM phase: `0` idle, `1` wait for ready, `2` ID search, `3` 22-byte gap, `4` sector stream, `5` tail, `6` abort, `7` track: wait for index, `8` track stream | 10 | precomp active (current/last op) |
| 6:4  | writer state, derived from its taps: `0` idle, `1` armed or draining with WGATE shut, `2` streaming with WGATE open, `3` discarding, `4` aborted | 11 | `f_wgate` pin level (`0` = writing) |
| 7    | `wr_ok`: write-protect tab qualified writable (10 ms of writable readings, cleared by a protected reading or a disk change) | 12 | `f_wdata` pin level |
| 8    | writer session | 13 | H (found ID) of the last Write Sector |
| 9    | feed (the controller asks the WD for bytes) | 14 | abort level to the writer |
|      |  | 15 | 0 |

`0x81` **`WR_LAST`** flags (high byte): bit 8 completed (`RES_OK`), 9 LOST DATA, 10 aborted,
11 write-protect refusal, 12 first-byte abort, 13 Write Track, 14 deleted data mark, 15
precomp. Abort reasons (low byte and `WR_REASON_ACC`): `0x02` enable, motor or media-ready
lost, `0x04` tab protected, `0x08` disk change, `0x20` side change, `0x40` writer underrun,
`0x80` the controller's abort (Force Interrupt, index loss in a Write Track).

**A healthy write session.** After a run of `SAVE`s, scratches and `VALIDATE`s on a
writable disk, with no protected disk, no eject and no Force Interrupt in between:

- `CNT_WR_GATE = CNT_WR_SECT + CNT_WR_TRACK` (every operation opened the gate);
- `CNT_WR_FIN = CNT_WR_SECT + CNT_WR_TRACK` (the WD consumed every completion);
- `CNT_WR_LOST`, `CNT_WR_WP`, `CNT_WR_ABORT`, `CNT_WR_UNDERRUN` and `WR_PUSHFULL` are 0;
- `CNT_WR_FIFO_OVF` is 0 after sector writes. A format leaves a count here: the DOS keeps
  writing gap bytes after the ending index until BUSY drops, and those are dropped by
  design;
- `WR_GATE_CYC` reads 849,600 (`0x000CF6C0`) after a sector, `WR_BYTES_LAST` 512;
- `WR_FIRST_MARGIN` is 18 or more, `WR_DRQ_MARGIN` 1 or more.

Every write-protect refusal, every Write Sector that does not find its ID (RNF) and every
operation aborted before its gap expired is one operation without a gate, so in general
`CNT_WR_GATE` is `CNT_WR_SECT + CNT_WR_TRACK` minus those; the trace ring shows which.

### Bit layouts

`0x02` **`LIVE_IN`** — pin levels. Raw bits are the async connector pins as sampled
(active-low at the pin: `0` = asserted). Conditioned bits are the internal
positive-sense levels (`1` = asserted) after the input synchronizer/filter.

| Bit | Meaning                    | Bit | Meaning                                  |
| --- | -------------------------- | --- | ---------------------------------------- |
| 0   | raw `f_rdata` (flux)       | 5   | conditioned RDATA (2FF-synced, active-low) |
| 1   | raw `f_index`              | 6   | conditioned INDEX level (filtered)       |
| 2   | raw `f_track0`             | 7   | conditioned TRACK0 (`1` = at track 0)    |
| 3   | raw `f_writeprotect`       | 8   | conditioned WRITE-PROTECT (`1` = protected) |
| 4   | raw `f_diskchanged`        | 9   | conditioned DISK-CHANGE (momentary, `1` = change) |
|     |                            | 15:10 | 0                                      |

`0x03` **`LIVE_OUT`** — driven mechanism outputs (active-low at the pin, so `0` = the line
is asserted / active).

| Bit | Meaning              | Bit | Meaning                        |
| --- | -------------------- | --- | ------------------------------ |
| 0   | `f_motora` (motor)   | 4   | `f_step` (step pulse)          |
| 1   | `f_selecta` (select) | 5   | `f_density`                    |
| 2   | `f_side1` (side)     | 6   | enable (physical mode active AND capable) |
| 3   | `f_stepdir` (dir)    | 15:7 | 0                             |

`0x04` **`CTRL_STATE`** — controller live state.

| Bit  | Meaning                  | Bit    | Meaning                              |
| ---- | ------------------------ | ------ | ------------------------------------ |
| 0    | media ready              | 7      | index level (filtered)               |
| 1    | head settled             | 8      | track0                               |
| 2    | separator locked         | 9      | write-protected                      |
| 3    | motor on                 | 11:10  | step FSM phase (see codes below)     |
| 4    | disk-change latched      | 15:12  | read FSM phase, or a write code (see below) |
| 5    | head estimate valid      |        |                                      |
| 6    | physical mode active (enable) |   |                                      |

Read FSM phase (bits 15:12): `0` idle, `1` waiting for ready, `2` searching for ID,
`3` waiting for data-address-mark, `4` streaming data, `5` reading address.

Write codes (bits 15:12, map v8): while a write operation is active or the writer is
still busy, bit 15 is set, bit 14 says which command (`0` = Write Sector, `1` = Write
Track, i.e. format) and bits 13:12 give the coarse phase: `0` waiting for ready, `1`
positioning (ID search and the 22-byte gap of a Write Sector, waiting for the index
of a Write Track), `2` streaming (WGATE open), `3` ending (tail, abort, writer still
draining). So `0x8`–`0xB` = Write Sector, `0xC`–`0xF` = Write Track. A Write Sector
searching for its ID therefore reads `0x9`, never the read code `2`. The Shell's
status line (Writing / Format / Reading / Head / Motor) and its idle gate use this
word alone; the full write phase is in `WR_STATE` (`0x80`).
Step FSM phase (bits 11:10): `0` idle, `1` direction setup, `2` step pulse low, `3` recovery/settle.

`0x05` **`HEAD`** — head position estimate.

| Bit  | Meaning                                       |
| ---- | --------------------------------------------- |
| 7:0  | head cylinder estimate (0–79 for a 1581)      |
| 8    | estimate valid (anchored after a track0 seek) |
| 9    | last step direction (`1` = outward / toward track 0) |
| 10   | track0 sensor level                           |
| 15:11| 0                                             |

The cylinder is an *estimate* derived from counting steps; it is anchored to 0 whenever the
head reaches the track-0 sensor. It is diagnostic only and does not affect decoding.

`0x06` **`LAST_RESULT`** — latched at the completion of the last read operation.

| Bit  | Meaning                                       |
| ---- | --------------------------------------------- |
| 4:0  | result code (see `RES_*` in `physical_1581_pkg.vhd`; `0` = OK) |
| 5    | CRC error                                     |
| 6    | record not found (RNF)                         |
| 7    | deleted data mark (F8) seen                     |
| 15:8 | 0                                             |

Result codes (5-bit, from `physical_1581_pkg.vhd`): `0x00` OK, `0x01` not ready,
`0x02` no index, `0x03` track0 failed, `0x04` record not found, `0x05` ID CRC error,
`0x06` missing data-address-mark, `0x07` data CRC error, `0x08` unsupported sector size,
`0x09` write protected, `0x0A` disk changed, `0x0B` lost data (write: the first byte
was missing when the gate was due, or a Write Track token underrun), `0x0D` cancelled,
`0x0E` invalid request, `0x0F` internal fault.

---

## 3. Reading the device from the QNICE monitor

Enter the QNICE debug console on real hardware by holding
<kbd>Run/Stop</kbd> + <kbd>Cursor&nbsp;Up</kbd> + <kbd>Help</kbd> (requires the JTAG serial
console; see `AGENTS.md` / `doc/developer.md`). At the monitor prompt, all commands are two
keystrokes: a group letter then a subcommand letter. You need `M`emory/`C`hange to set the
two selector registers, then `M`emory/`D`ump or `M`emory/`E`xamine to read the window. All
values are entered in **hex, without a `0x` prefix**.

### 3.1 Select the device (once)

```text
MC            (Memory/Change) -> prompt "CHANGE ADDRESS="
FFF4          enter the address of M2M$RAMROM_DEV
              -> it prints " CURRENT VALUE=xxxx NEW VALUE="
0108          set the device id = C_DEV_C64_PHYS1581

MC
FFF5          address of M2M$RAMROM_4KWIN
0000          select 4K window 0
```

### 3.2 Confirm you are talking to the device

```text
ME            (Memory/Examine) -> prompt "EXAMINE ADDRESS="
7000          word offset 0x00 = SIGNATURE
              -> prints "7000 1581"   (if you do not see 1581, re-check 0xFFF4/0xFFF5)
```

### 3.3 Dump the whole bank

```text
MD            (Memory/Dump) -> prompt "DUMP START ADDRESS="
7000          start
703F          -> prompt " END ADDRESS=" ; end (0x7000 + 0x3F = last scalar diagnostic word)
```

This prints all 64 scalar diagnostic words in one block. To watch a value live, re-issue the
`MD 7000 703F` (or `ME 70xx`) command repeatedly — the registers update continuously while
the C64 accesses the drive. The write instruments are `MD 7080 709D`.

### 3.4 Typical checks

- **Is the motor spinning and is the disk turning?** Dump and watch `IDX_PERIOD` (`0x0D`/`0x0E`)
  settle near one revolution (about 200 ms, i.e. `0x00989680` cycles) and `CNT_IDX_RAW`
  (`0x14`) increment about 5 times per second while the motor is on.
- **Did a `LOAD` actually reach the medium?** Watch `CNT_READOP` (`0x1A`) climb, and read
  `LAST_RESULT` (`0x06`): `0x0000` means the last sector read cleanly.
- **Sector present but garbled?** A rising `CNT_CRCERR` (`0x1E`) with `ID_CALC_CRC`/`DATA_CALC_CRC`
  (`0x0A`/`0x0B`) non-zero points at MFM decode/CRC trouble; compare `GAP_MIN`/`GAP_MAX`
  (`0x12`/`0x13`) against the DD nominals (200/300/400 cycles), watch `CNT_GAPERR` (`0x26`),
  and check `EST` (`0x36`) — an estimate pinned at a clamp (90/110 cycles) means the flux
  timing is far off what the quantiser can track.
- **Head never finds the track?** A climbing `CNT_RNF` (`0x1C`) with `HEAD` (`0x05`) not
  matching the wanted cylinder, or `CTRL_STATE` (`0x04`) stuck in read phase `2` (ID search),
  means the ID field was never matched. `RNF_CTX` (`0x37`) names the requested track/sector
  of the last RNF — one repeating pair is a persistently unreadable sector, a wandering pair
  is a scattered media/speed problem.
- **Drive never becomes ready?** `CTRL_STATE` bit0 stays `0`: check the motor bit (bit3), that
  `CNT_IDX_QUAL` (`0x16`) is counting (index edges only count toward readiness while the motor
  is on), and that `IDX_PERIOD` (`0x0D`/`0x0E`) is plausible (one revolution, about `0x00989680`
  cycles at 300 RPM). Readiness models the real mechanism RDY line: motor at speed plus live
  index pulses. The disk-change latch (bit4) does NOT gate readiness -- it drives the DOS-visible
  /DSKCHG (CIA PA7) and aborts in-flight reads; the DOS clears it by stepping.
- **Loads work but data looks shifted or truncated?** Check `LAST_PRESENT` (`0x2B`) after a
  sector read — anything other than `0x0200` (512) means the operation did not present a full
  sector. A climbing `CNT_LOST` (`0x2C`) means the drive CPU was too slow to fetch paced bytes
  (each event also sets LOST DATA in the WD status the DOS saw); `CNT_STALEDONE` (`0x30`) and
  `CNT_BUSYCMD` (`0x32`) flag protocol races that would previously have been invisible. Note that
  `CNT_STALEDONE` also increments once per Force-Interrupt-cancelled in-flight operation (the
  cancelled operation completes on its own and that completion is consumed and ignored) — a small
  count after aborts is normal and correlates with `CNT_CANCEL`; only a count that grows during
  error-free operation indicates a real race.

- **Did a `SAVE` reach the disk?** `CNT_WR_SECT` (`0x86`) and `CNT_WR_GATE` (`0x8A`) climb
  together, `WR_LAST` (`0x81`) reads `0x01xx` or `0x81xx` (completed, with or without
  precomp) and `WR_GATE_CYC` (`0x83`/`0x84`) reads `F6C0`/`000C`. A rising `CNT_WR_WP`
  means the tab is set to protected; a rising `CNT_WR_LOST` means the drive CPU did not
  deliver the bytes in time (the DOS then reports `25, WRITE ERROR`).

### 3.5 Change the precompensation (`WR_CTRL`)

The physical drive precompensates like a real 1581: it follows the P bit of the DOS's
write command (precomp on cylinders 1–43). `WR_CTRL` overrides that without a rebuild,
for testing media that read back badly. With the device selected (section 3.1):

```text
MC            (Memory/Change)
709A          address of WR_CTRL (0x7000 + 0x9A)
0001          0 = follow the DOS (default), 1 = precomp off, 2 = precomp always on
```

`ME 709A` reads the setting back. It applies from the next write operation on, and a core
or QNICE reset returns it to `0`. `WR_PRECOMP_CNT` (`0x95`) shows the effect: about 1,800
shifted pulses per sector with precomp, 0 without.

---

## 4. Notes and caveats

- **Observational.** Apart from `WR_CTRL`, this device cannot change anything the drive does.
  It observes the `physical_1581_controller`, its decoder and its writer; the mechanism is
  driven entirely by the C64/DOS through the WD1772 model, not by QNICE. In particular it
  cannot open the write gate.
- **`GAP_MIN`/`GAP_MAX` and the counters are cumulative since the last reset** (`c64_rst_sd_i`,
  which follows the QNICE-domain reset). There is no clear-on-read; power-cycle or a core reset
  zeroes them (and re-seeds `GAP_MIN` to `0xFFFF`).
- **`change_o` polarity assumption.** The conditioned disk-change bit (`LIVE_IN` bit 9,
  `CTRL_STATE` bit 4) assumes the board presents disk-change active-low; if the R3 wiring turns
  out inverted, this is the register to watch while inserting/ejecting to confirm it (see the
  NOTE in `physical_1581_inputs.vhd`).
- **All timing figures are in 50 MHz controller cycles** (one cycle = 20 ns); divide by 50 for
  microseconds. DD half-cell is about 100 cycles, nominal flux gaps 200/300/400 cycles.
