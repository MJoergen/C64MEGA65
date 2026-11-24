# Physical Internal 1581 — QNICE Diagnostic Device

**Device:** `C_DEV_C64_PHYS1581 = 0x0108` (defined in `CORE/vhdl/globals.vhd`)
**Module:** `CORE/vhdl/physical_1581/physical_1581_diag.vhd`
**Access:** observational, with two writable words (`WR_CTRL`, `0x9A`, map v8; `RD_CTRL`, `0xA5`, map v10). Issue #90 (internal 3.5" DD floppy as a physical 1581, read path), issue #244 (write path, map v8), issue #257 (read-ahead and spin-up time, map v9) and part E of issue #257 (index gap, stale READY and the decoder's tolerance for a weak sync byte, map v10).

The MEGA65 has no oscilloscope or logic analyzer on the internal floppy bus, so this register bank is the only on-hardware window into the physical-1581 read and write paths. It surfaces the live pin levels, the controller state machine, the last decoded sector result, the CRCs, the index/flux timing, a set of saturating event counters, (map v8) the write instruments, (map v9) the read-ahead counters and the spin-up time and (map v10) the longest index gap, the count of stale READY and the count and switch of the decoder's tolerance.

It is **observational**: it cannot move the head, spin the motor, open the write gate or change any mechanism output. The two exceptions are switches for experiments: `WR_CTRL` (`0x9A`, section 2.2) overrides the write precompensation, and `RD_CTRL` (`0xA5`, section 2.4) switches the decoder's tolerance for a weak sync byte off. A QNICE write to any other word is silently ignored. Reads never stall the QNICE bus.

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

64 words at offsets `0x00`–`0x3F`, the 64-word WD-dialogue trace ring at `0x40`–`0x7F` (section 2.1), the 30 write words at `0x80`–`0x9D` (map v8, section 2.2), the four words at `0x9E`–`0xA1` (map v9, section 2.3) and the four words at `0xA2`–`0xA5` (map v10, section 2.4). Any other offset reads `0x0000`. All multi-bit fields are right-aligned unless a bit layout is given.

| Off  | Name              | Contents                                                        |
| ---- | ----------------- | --------------------------------------------------------------- |
| `0x00` | `SIGNATURE`     | constant `0x1581` — confirms you are talking to this device     |
| `0x01` | `VERSION`       | map version (high byte) / capability flags (low byte) — `0x0AFE` (bit 0, "read-only", cleared since map v8) |
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
| `0x3E` | `CNT_MATCH_ID`   | 16-bit saturating counter: CRC-valid IDs matching the requested track/sector, and (map v9) Read Sectors served from the read-ahead buffer |
| `0x3F` | `CNT_DAM_MISS`   | 16-bit saturating counter: matching IDs after which the controller saw another ID or timed out before a DAM |
| `0x40`–`0x7F` | `TRC[0..31]` | WD-dialogue trace ring, two words per entry (section 2.1) |
| `0x80`–`0x9D` | write instruments | map v8, section 2.2 |
| `0x9E`–`0xA1` | read-ahead counters, spin-up time | map v9, section 2.3 |
| `0xA2`–`0xA5` | index gap, stale READY, decoder tolerance | map v10, section 2.4 |

The original fifteen counters are 32-bit and **saturate** at `0xFFFFFFFF` (they never wrap). Read the low word first, then the high word (`0x0000` in the high word while values stay small). The eight counters at `0x38`–`0x3F`, the two at `0x9E`/`0x9F` and the two at `0xA3`/`0xA4` are single-word 16-bit saturating counters.

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

### Media ready and physical Read Address compatibility

Synthesized `media ready` (`CTRL_STATE` bit 0, the READY line that the 1581 DOS reads on CIA PA1) asserts with the first motor-qualified index edge of a motor-on interval, for every medium: cold, changed, restarted or newly enabled. It falls with the motor request, on reset, on disable, and when no index edge arrived for 500 ms of settled time while the motor is on (the disk was removed or has stopped; the next edge brings READY back). Settled time is the time in which the step engine is idle and the head has settled: from the acceptance of a step until 18 ms after its pulse the 500 ms do not run, and they start anew when the head has settled, because a mechanism may withhold its index pulses while it steps (map v10, section 2.4, measures whether it does). An index edge counts whenever it arrives, during a step as well. It does not depend on the disk-change latch. The first edge has to be enough because of the finite PA1 window of the genuine 1581 ROM: the DOS examines READY exactly once, 0.800 s after it switched the motor on (0.830 s after a disk change), and the first index pulse of the mechanism can come 0.63 s or later after motor-on, so that a second edge, 200 ms after the first, can arrive after the exam. Eject and reinsert detection does not rest on READY: that is the job of the disk-change latch (`CTRL_STATE` bit 4), which is set by the raw change line, by reset and by disable and is cleared only by a completed step with the line released.

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

To capture a failure: power the MEGA65 on (or hold the reset button for more than 1.5 s; a short press clears neither the ring nor the counters, section 4), reproduce the failing access once, then enter the console, select the device (section 3.1) and dump `MD 7000 703F` and `MD 7040 707F`. Every REQUEST is normally followed by its RESULT entry; STEP entries in between show the seek pattern (direction + the controller's head-position estimate at each step). This reconstructs where the DOS was heading, what it asked to read, and what it got — without any scope.

The rare coincidence of two events in the same 50 MHz cycle records only the
higher-priority one (RESULT over REQUEST over STEP); `TRC_CNT` then undercounts by
one. Irrelevant in practice, noted for completeness.

`IMG_DRIVE` bit 0 is the mirror image of the `CTRL_STATE` busy bits for the *other* media source: it is set while the image-backed drive 8 shows activity (the activity part of the drive LED, covering both the 1541 and the 1581 image engines including WD1772 command-busy) or while a dirty write-back cache has not been flushed to the SD card yet. The error blink that a 1581 shows on the drive LED after a failed command is not part of this bit: a drive that only reports an error is idle. The Shell consults the bit before it allows switching drive 8 from disk image to the internal 1581 (the image drive can write, so switching away mid-access or with unsaved data would lose data); `CTRL_STATE` gates the opposite direction. Capability bit 3 in `VERSION` announces that this word exists.

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

### 2.3 Read-ahead and spin-up time (map v9, words `0x9E`–`0xA1`)

| Off  | Name                | Contents |
| ---- | ------------------- | -------- |
| `0x9E` | `CNT_RD_AHEAD`      | 16-bit saturating counter: Read Sector operations served from the controller's read-ahead buffer |
| `0x9F` | `CNT_RD_AHEAD_DROP` | 16-bit saturating counter: adoptions given up; the request went to the live read path instead |
| `0xA0` | `SPINUP_LAST_MS`    | milliseconds from the last rising edge of the motor-on level (`CTRL_STATE` bit 3) to the first index edge after it; saturates at `0xFFFE`; `0xFFFF` = no measurement since reset. While a measurement is running, the previous value stays visible |
| `0xA1` | `SPINUP_MAX_MS`     | the largest value `SPINUP_LAST_MS` has taken since reset (`0x0000` until the first measurement) |

**Read-ahead.** The WD front end presents a sector at disk pace, and only after its CRC has been checked. The DOS's request for the next sector of a track therefore arrives one sector time late: the ID of that sector has passed and its data field is under the head. After a clean Read Sector the controller keeps listening and captures the sector that passes into a 512-byte buffer of its own, with the checks of a live read (a CRC-valid ID with N = 2, the data mark in time, exactly 512 bytes, a good data CRC). A Read Sector that asks for the sector in that buffer, or on its way into it, is served from the buffer (read phases `6` and `7` in `CTRL_STATE`) and counts in `CNT_RD_AHEAD`. A sector stays in the buffer until the data mark of the next capture replaces it (on a well-formed track about 3 ms after the sector ended), and for 24 ms after its own data mark at the most, so no byte that is served from the buffer left the disk more than 24 ms before its request was accepted. Every step, side change, motor stop, loss of the index pulses, disk change, write, Read Address, Verify and Force Interrupt invalidates the buffer, so the first Read Sector after any of them is always read live; the WD front end still never sees a byte of a sector whose CRC was not checked. `CNT_MATCH_ID` (`0x3E`) counts the sectors served from the buffer as well.

`CNT_RD_AHEAD_DROP` counts the requests that were accepted for the buffer and then handed to the live read path after all, which waits for the sector to come round again. That happens when the capture of the sector fails (a bad data CRC, a missing data mark) or is abandoned, when the sector leaves the buffer in the very clock in which its request is accepted, when a step, a side change, a motor stop, the loss of the index pulses or a decoder reset falls into the wait, and when the wait reaches its bound of 40 ms. (A Force Interrupt and a disk change end such a request like every read; they do not count here.)

**A healthy read session.** The DOS reads a track side with a Read Address and ten Read Sectors. The first of the ten is read live and arms the read-ahead; the other nine come from the buffer. After a `LOAD` of a file that spans a track, `CNT_RD_AHEAD` is therefore about nine tenths of the Read Sectors (their REQUEST entries in the trace ring read `0x20xx`/`0x21xx`), and `CNT_RD_AHEAD_DROP` stays small. A `CNT_RD_AHEAD_DROP` that climbs while `CNT_CRCERR` (`0x1E`) stays where it is points at sectors that read badly on one pass and well on the next: the capture failed, and the live read one revolution later succeeded. If `CNT_CRCERR` climbs with it, the live read failed too: those sectors are bad on every pass. A `CNT_RD_AHEAD` that stays at 0 while sectors are read in sequence means that every request arrives after its sector has left the buffer; each of those reads costs a revolution.

**Spin-up time.** The stock 1581 ROM switches the motor on, waits 800 ms and then examines READY exactly once: 0.800 s after the motor start for an unchanged disk, 0.830 s after a disk change (the DOS first answers the change with a step in and a step out, 6 ms each, and waits 18 ms). "Not ready" at that exam ends the job with `74,DRIVE NOT READY`. READY needs the first index pulse of the motor-on interval, so `SPINUP_LAST_MS` is the time the mechanism took to deliver it and `SPINUP_MAX_MS` the worst case since reset; a first index pulse that comes later than the exam fails the job. As a rule of thumb, both words have to stay below 800 (`0x0320`); the difference is the margin. A value near or above 800 explains a first access that fails right after the motor started.

What the two words show in the cases a tester will meet:

- **The motor is switched on again while the disk still turns** (an access shortly after the motor stopped): the first index pulse comes within the revolution that is under way, so `SPINUP_LAST_MS` is small. Such a value says nothing about a start from standstill.
- **The motor was switched on without a disk in the drive.** No index pulse arrives, so the measurement does not end. If a disk is inserted while the motor is still on, the measurement ends with the first index pulse of that disk: the value is then the time until the insert, not a spin-up time, and it can raise `SPINUP_MAX_MS` far above 800 without any fault. The measurement saturates at `0xFFFE` (about 65.5 s). If the motor is switched off and on again before an index pulse came, the measurement starts anew with the new motor start.
- **`0xFFFF` in `SPINUP_LAST_MS`** means that no measurement has ended since reset: the motor was not on yet, or no index pulse has arrived with the motor on. `SPINUP_MAX_MS` reads `0x0000` until then.
- **While a measurement runs**, `SPINUP_LAST_MS` still shows the previous result.

### 2.4 Index gap, stale READY and the decoder's tolerance (map v10, words `0xA2`–`0xA5`)

| Off  | Name                | Contents |
| ---- | ------------------- | -------- |
| `0xA2` | `IDX_GAP_MAX_MS`  | the longest time between two index edges in a row with the motor on in every clock between them, since reset: the clocks strictly between the two edges, in whole milliseconds (truncated), counted as for `SPINUP_LAST_MS`; saturates at `0xFFFF`; `0x0000` = no measurement since reset |
| `0xA3` | `CNT_RDY_STALE`   | 16-bit saturating counter: READY fell while the motor request stayed on (the rule of 500 ms of settled time without an index edge) |
| `0xA4` | `CNT_TOL_HIT`     | 16-bit saturating counter: uses of the decoder's tolerance for a weak sync byte |
| `0xA5` | `RD_CTRL`         | readable and writable: bit 0 = 1 switches the decoder's tolerance for a weak sync byte off, from the next mark the decoder decides on; `0x0000` after reset (tolerance on); bits 15..1 read 0 |

**Index gap.** A measurement starts with an index edge while the motor-on level (`CTRL_STATE` bit 3) is high and ends with the next index edge; that edge starts the next measurement at once. If the motor-on level is low in any clock between the two edges (the motor request fell, the drive was disabled or reset), the measurement ends without a result, and the next index edge with the motor on starts a new one. The measurement counts real time: it does not depend on READY or on the rule of the controller. `IDX_GAP_MAX_MS` keeps the largest result since reset. Read it in revolutions: one revolution takes about 200 ms at 300 rpm (`IDX_PERIOD`, `0x0D`/`0x0E`, has the exact value), and a disk that turns while its index pulses do not reach the controller gives a whole multiple of it. What the value means:

- **About 200** (`0x00C7` or `0x00C8`, one revolution): every index pulse arrived while the motor ran, also while the head stepped.
- **A whole multiple of a revolution from 2 to 5, about 400, 600, 800 or 1000** (`0x0190`, `0x0258`, `0x0320`, `0x03E8` at exactly 300 rpm): one to four index pulses in a row did not arrive while the motor ran and the disk turned. That is what a mechanism that withholds its index pulses while the head steps shows after a recalibration (the power-on initialization of the DOS, `UI`, `UJ`, the bump after two failed reads) or after a long seek. At the 6 ms per step of the DOS, the Seek of 39 steps of a recalibration alone withholds the pulses for 228 ms plus the hold time, more than a revolution, so on such a mechanism a recalibration never leaves the value at 200: from the directory cylinder 39 it reads 400, 600 or 800, depending on where the index is when the steps begin, from cylinder 47 or further in up to 1000, and a seek across the disk reads 600 or 800. Compare it with `CNT_STEP` (`0x18`): without steps since the reset, the value stays near 200 on such a mechanism.
- **Longer, or not near a whole number of revolutions:** not index pulses that a turning disk withheld. A disk that was taken out and put back while the motor ran gives the time without a disk, from the last index pulse of the old disk to the first of the new one, which can be anything from a few hundred milliseconds on; a disk that stopped gives the time until it turned again.

The numbers of the second case come from a model: the disk turns at a constant speed; the mechanism delivers no index pulse from the first step pulse of a train until its hold time after the last one (18 ms; the TEAC FD-235HF, for example, gates INDEX until 15.8 to 17.9 ms after the last step pulse); a recalibration is a Restore of as many steps as the head is away from cylinder 0 and, 78 ms after its last step pulse, a Seek of 39 steps, both at 6 ms per step, as the genuine ROM issues them (`doc/dev-fdd/ISSUE257-PART-E-FIXES.md`, section 7). `doc/dev-fdd/tools/idx_gap_model.py` computes the readings for every index phase. A hold time of more than about 23 ms adds a sixth revolution, about 1200, in a few index phases of a Restore from cylinder 79.

**Withheld pulses or a disk change?** A disk change can give any value, also one in the range of withheld pulses. Two counters of the same dump tell them apart: `CNT_RDY_STALE` (`0xA3`) counts a disk that was out for more than half a second with the motor on (READY falls by the rule of 500 ms of settled time) and does not count withheld index pulses, because the time in which the head steps and settles does not count toward the 500 ms; `CNT_CHANGE` (`0x22`) counts every rise of the disk-change latch: a disk taken out, with the motor on or off, and a switch of drive 8 from the internal drive to a disk image (the controller sets the latch when it is disabled). With both at 0, a value of 400 to 1000 is withheld index pulses. A large value covers the smaller ones until the next reset of the device (section 4), and a short press of the reset button does not clear it. The clean reading is therefore a dump after a power cycle with the disk in the drive, before any disk change: the DOS recalibrates once at power-on, and a mechanism that withholds its index pulses while the head steps then shows 400, 600 or 800 (up to about 1000 if the head was on cylinder 47 or further in), one that delivers them about 200.

**Stale READY.** `CNT_RDY_STALE` counts every fall of READY (`CTRL_STATE` bit 0) while the motor-on level stays high. The controller lowers READY together with the motor-on level when the motor request falls, on reset and on disable; those falls do not count. What remains is the rule of the controller: no index edge for 500 ms of settled time with the motor on. With a disk in the drive and the motor running the counter stays at 0; every count is a disk taken out with the motor on, a disk that stopped turning, or index pulses that stayed away for half a second while the head rested.

**Decoder tolerance.** The decoder needs three sync bytes (`A1`) at the exact spacing in front of a mark. When the first of them was recorded weakly, its candidate is lost, and the decoder, while it is idle, accepts the byte after the two remaining candidates as the mark (`doc/dev-fdd/ISSUE257-PART-E-FIXES.md`, section 3). `CNT_TOL_HIT` counts every such mark, one decoder pulse (`tol_hit_o`) per use: every `FE` accepted on a pair, also one whose ID then has a bad CRC (such an ID is not reported: it counts here and not in `CNT_IDDEC`), and every `FB` or `F8` on a pair that opened a data field (only after a CRC-valid ID and with the zero run 7 to 11 gaps before the pair). A pair followed by any other byte, or by a data mark that no ID armed, does not count. The counters of maps v6 and v7 keep their meaning with the tolerance: `CNT_A1_CAND`, `CNT_A1_REJECT`, `CNT_A1_TRAIN`, `CNT_MARK_FE` and `CNT_MARK_DAM` count candidates and trains of three as without it, and `CNT_DAM_UNARMED` differs only where the state of the parser differs (an ID recovered on a pair arms its data mark, or an ID accepted on a pair is still open when a data mark after a train of three arrives; that data field is then lost in this revolution, a limit that needs a false pair inside a data field's zero run, `doc/dev-fdd/ISSUE257-PART-E-FIXES.md`, section 3). Read together: `CNT_A1_CAND - 3 * CNT_A1_TRAIN` still counts lost sync bytes, two per record and revolution, whether the tolerance recovered the record or not; `CNT_TOL_HIT` tells how many were recovered; `CNT_IDDEC - CNT_MARK_FE` is about the number of IDs recovered. On a disk that was written well `CNT_TOL_HIT` stays at or near 0; a count that grows on one track points at a weak recording there. `RD_CTRL` bit 0 switches the tolerance off for a comparison (section 3.6); the reset of the device (section 4) switches it on again, a short press of the reset button does not.

All four words are cleared only by the reset of the device (section 4); there is no clear-on-read, and a write does not clear them.

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
`3` waiting for data-address-mark, `4` streaming data, `5` reading address, `6` waiting
for the read-ahead capture of the requested sector, `7` copying the sector from the
read-ahead buffer (map v9, section 2.3).

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

### 3.1 Select the device (at every visit of the console)

The selection does not survive leaving the console. The Shell uses the same two registers (`0xFFF4` and `0xFFF5`) for its own devices and overwrites them as soon as it runs again. So select the device again every time you enter the console, before the first read: a read without the selection shows the window of whatever device the Shell selected last, not this bank.

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

This check is worth the two keystrokes at every visit: anything other than `1581` means that the selection of section 3.1 is missing (or was made in an earlier visit and is gone).

### 3.3 Dump the whole bank

```text
MD            (Memory/Dump) -> prompt "DUMP START ADDRESS="
7000          start
703F          -> prompt " END ADDRESS=" ; end (0x7000 + 0x3F = last scalar diagnostic word)
```

This prints all 64 scalar diagnostic words in one block. To watch a value live, re-issue the `MD 7000 703F` (or `ME 70xx`) command repeatedly — the registers update continuously while the C64 accesses the drive. The write instruments and the words of maps v9 and v10 are `MD 7080 70A5`. The selection of section 3.1 holds for as long as you stay in the console; after leaving it and coming back, select the device again before the next dump.

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
- **Drive never becomes ready?** `CTRL_STATE` bit0 stays `0`: check the motor bit (bit3), that `CNT_IDX_QUAL` (`0x16`) is counting (index edges only count toward readiness while the motor is on), and that `IDX_PERIOD` (`0x0D`/`0x0E`) is plausible (one revolution, about `0x00989680` cycles at 300 RPM). Readiness models the RDY line of the real mechanism: the motor is on and at least one index edge of the current motor-on interval has arrived. It falls with the motor request, and when no index edge arrived for 500 ms of settled time: the time in which the head steps or settles (18 ms after the last step) does not count. `CNT_RDY_STALE` (`0xA3`) counts the falls by that rule; with a disk in the drive it stays at 0. `IDX_GAP_MAX_MS` (`0xA2`) shows whether the mechanism withholds index pulses while the head steps (about 200 if not; after a recalibration two to five revolutions, about 400 to 1000, if it does), see section 2.4. The disk-change latch (bit4) does NOT gate readiness -- it drives the DOS-visible /DSKCHG (CIA PA7) and aborts in-flight reads; the DOS clears it by stepping. `SPINUP_LAST_MS` (`0xA0`) shows how long the first index pulse took after the last motor start, `SPINUP_MAX_MS` (`0xA1`) the worst case since reset: the DOS examines READY once, 800 ms after it switched the motor on (830 ms after a disk change), see section 2.3.
- **Does the head arrive where the DOS wants it?** After a recalibration (`UI`, the power-on initialization: a run of STEP entries outward to track 0, then inward) the next Read Address REQUEST in the trace ring names the track and its RESULT the cylinder found; the two must agree. The drive steps at the 6 ms that the DOS asks for (the WD1772 model paces every Type I command by its rate bits). A RESULT two cylinders short, followed by two more STEP entries and a second Read Address, is the signature of a mechanism that loses steps in a long train (`doc/dev-fdd/ISSUE257-PART-E.md`, section 3).
- **Loads are slow?** After reading a few tracks, compare `CNT_RD_AHEAD` (`0x9E`) with the
  number of Read Sectors: nine of the ten sectors of a track side should come from the
  read-ahead buffer. `CNT_RD_AHEAD_DROP` (`0x9F`) counts the requests that were accepted for
  the buffer but had to wait for the next revolution after all (section 2.3 lists the reasons).
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
for testing media that read back badly. With the device selected in this visit of the console (section 3.1):

```text
MC            (Memory/Change)
709A          address of WR_CTRL (0x7000 + 0x9A)
0001          0 = follow the DOS (default), 1 = precomp off, 2 = precomp always on
```

`ME 709A` reads the setting back. It applies from the next write operation on. The reset of
the device (section 4) returns it to `0`; a short press of the reset button does not, so set
it back with `MC` `709A` `0000` when the test is done. `WR_PRECOMP_CNT` (`0x95`) shows the
effect: about 1,800 shifted pulses per sector with precomp, 0 without.

### 3.6 Switch the decoder's tolerance off (`RD_CTRL`)

The decoder tolerates one weak sync byte in front of a mark (section 2.4). `RD_CTRL` switches that tolerance off without a rebuild, to compare a disk with and without it. With the device selected in this visit of the console (section 3.1):

```text
MC            (Memory/Change)
70A5          address of RD_CTRL (0x7000 + 0xA5)
0001          1 = tolerance off, 0 = tolerance on (default)
```

`ME 70A5` reads the setting back. It applies from the next mark the decoder decides on: a field that the decoder opened before the change ends under the rule that opened it. The reset of the device (section 4) returns it to `0`; a short press of the reset button does not, so switch the tolerance on again with `MC` `70A5` `0000` when the comparison is done. `CNT_TOL_HIT` (`0xA4`) shows the effect: it does not grow while the tolerance is off.

---

## 4. Notes and caveats

- **Observational.** Apart from `WR_CTRL` and `RD_CTRL`, this device cannot change anything the drive does.
  It observes the `physical_1581_controller`, its decoder and its writer; the mechanism is
  driven entirely by the C64/DOS through the WD1772 model, not by QNICE. In particular it
  cannot open the write gate.
- **What resets the device.** Its reset is `c64_rst_sd_i`, the QNICE reset of the framework.
  It comes with a power cycle and when the reset button is held for more than 1.5 s. A short
  press of the reset button resets the C64 core (the C64 and the CPUs of its drives), not the
  QNICE and not this device: the counters, the maxima and minima, the trace ring and the
  last-result words keep their values, and `WR_CTRL` and `RD_CTRL` keep their settings.
- **`GAP_MIN`/`GAP_MAX` and the counters are cumulative since the last reset of the device.**
  There is no clear-on-read; the reset zeroes them (and re-seeds `GAP_MIN` to `0xFFFF`).
- **`change_o` polarity assumption.** The conditioned disk-change bit (`LIVE_IN` bit 9,
  `CTRL_STATE` bit 4) assumes the board presents disk-change active-low; if the R3 wiring turns
  out inverted, this is the register to watch while inserting/ejecting to confirm it (see the
  NOTE in `physical_1581_inputs.vhd`).
- **All timing figures are in 50 MHz controller cycles** (one cycle = 20 ns); divide by 50 for
  microseconds. DD half-cell is about 100 cycles, nominal flux gaps 200/300/400 cycles.
