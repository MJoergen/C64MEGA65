# Physical Internal 1581 — QNICE Diagnostic Device

**Device:** `C_DEV_C64_PHYS1581 = 0x0108` (defined in `CORE/vhdl/globals.vhd`)
**Module:** `CORE/vhdl/physical_1581/physical_1581_diag.vhd`
**Access:** READ-ONLY, observational. Issue #90 (internal 3.5" DD floppy as physical drive 8, read-only milestone).

The MEGA65 has no oscilloscope or logic analyzer on the internal floppy bus, so this
register bank is the only on-hardware window into the physical-1581 read path. It
surfaces the live pin levels, the controller state machine, the last decoded sector
result, the CRCs, the index/flux timing and a set of saturating event counters.

It is **strictly observational**: it drives nothing back into the read path, it cannot
move the head, spin the motor or change any mechanism output, and it has no write side
(any QNICE write to the device is silently ignored). Reads never stall the QNICE bus.

The whole bank runs on the QNICE 50 MHz clock (`c64_clk_sd_i`), which is the *same*
clock as the `physical_1581_controller`, so every value below is a coherent snapshot with
no clock-domain-crossing artifacts.

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

40 words, offsets `0x00`–`0x27`. Any offset not listed (including `0x28` and above) reads
`0x0000`. All multi-bit fields are right-aligned unless a bit layout is given.

| Off  | Name              | Contents                                                        |
| ---- | ----------------- | --------------------------------------------------------------- |
| `0x00` | `SIGNATURE`     | constant `0x1581` — confirms you are talking to this device     |
| `0x01` | `VERSION`       | map version (high byte) / capability flags (low byte) — `0x0107` |
| `0x02` | `LIVE_IN`       | raw + conditioned input pin levels (bit layout below)           |
| `0x03` | `LIVE_OUT`      | driven mechanism output levels + enable (bit layout below)      |
| `0x04` | `CTRL_STATE`    | controller state flags + read/step FSM phase (bit layout below) |
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

All ten counters are 32-bit and **saturate** at `0xFFFFFFFF` (they never wrap). Read the
low word first, then the high word (`0x0000` in the high word while values stay small).

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
| 4    | disk-change latched      | 15:12  | read FSM phase (see codes below)     |
| 5    | head estimate valid      |        |                                      |
| 6    | physical mode active (enable) |   |                                      |

Read FSM phase (bits 15:12): `0` idle, `1` waiting for ready, `2` searching for ID,
`3` waiting for data-address-mark, `4` streaming data, `5` reading address.
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
`0x09` write protected, `0x0A` disk changed, `0x0D` cancelled, `0x0E` invalid request,
`0x0F` internal fault.

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
7027          -> prompt " END ADDRESS=" ; end (0x7000 + 0x27 = last counter word)
```

This prints all 40 diagnostic words in one block. To watch a value live, re-issue the
`MD 7000 7027` (or `ME 70xx`) command repeatedly — the registers update continuously while
the C64 accesses drive 8.

### 3.4 Typical checks

- **Is the motor spinning and is the disk turning?** Dump and watch `IDX_PERIOD` (`0x0D`/`0x0E`)
  settle near one revolution (about 200 ms, i.e. `0x00989680` cycles) and `CNT_IDX_RAW`
  (`0x14`) increment about 5 times per second while the motor is on.
- **Did a `LOAD` actually reach the medium?** Watch `CNT_READOP` (`0x1A`) climb, and read
  `LAST_RESULT` (`0x06`): `0x0000` means the last sector read cleanly.
- **Sector present but garbled?** A rising `CNT_CRCERR` (`0x1E`) with `ID_CALC_CRC`/`DATA_CALC_CRC`
  (`0x0A`/`0x0B`) non-zero points at MFM decode/CRC trouble; compare `GAP_MIN`/`GAP_MAX`
  (`0x12`/`0x13`) against the DD nominals (200/300/400 cycles) and watch `CNT_GAPERR` (`0x26`).
- **Head never finds the track?** A climbing `CNT_RNF` (`0x1C`) with `HEAD` (`0x05`) not
  matching the wanted cylinder, or `CTRL_STATE` (`0x04`) stuck in read phase `2` (ID search),
  means the ID field was never matched.
- **Drive never becomes ready?** `CTRL_STATE` bit0 stays `0`: check the motor bit (bit3), the
  disk-change latch (bit4, needs a Type-I step to clear), and that `CNT_IDX_QUAL` (`0x16`) is
  counting (index edges are only counted toward spin-up while the motor is on).

---

## 4. Notes and caveats

- **Read-only.** This device cannot change anything the drive does. It observes the
  `physical_1581_controller` and its decoder; the mechanism is driven entirely by the C64/DOS
  through the WD1772 model, not by QNICE.
- **`GAP_MIN`/`GAP_MAX` and the counters are cumulative since the last reset** (`c64_rst_sd_i`,
  which follows the QNICE-domain reset). There is no clear-on-read; power-cycle or a core reset
  zeroes them (and re-seeds `GAP_MIN` to `0xFFFF`).
- **`change_o` polarity assumption.** The conditioned disk-change bit (`LIVE_IN` bit 9,
  `CTRL_STATE` bit 4) assumes the board presents disk-change active-low; if the R3 wiring turns
  out inverted, this is the register to watch while inserting/ejecting to confirm it (see the
  NOTE in `physical_1581_inputs.vhd`).
- **All timing figures are in 50 MHz controller cycles** (one cycle = 20 ns); divide by 50 for
  microseconds. DD half-cell is about 100 cycles, nominal flux gaps 200/300/400 cycles.
