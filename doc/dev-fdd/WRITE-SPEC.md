# Internal 1581 — WRITE and FORMAT support (issue #244) — Specification

Status: v0.6, 2026-10-17 (M1a, M1b, M2 and M3 folded in: the whole write path as implemented and integrated
on branch `write-support`, core version `WIP-V6-A21X1`), written by the controller session for sy2002.
Nothing has been synthesized or run on hardware yet; the next step is the maintainer's Vivado build and
bench round 1 (plan section 5.1). It is the pragmatic successor of the write-related sections of the
normative read-milestone spec (`doc/issue_90_internal_mega65_drive_as_1581.md`, sections 10.6,
10.9, 12.2, 13.3, 13.6, 14.6–14.10, 16.2), and it deliberately replaces their ceremony with the
discipline that the Amiga core (AExp) proved on the same mechanism in the field. Companion plan:
`doc/dev-fdd/WRITE-PLAN.md`.

Audience: a coding session that implements the feature, and the maintainer who tests it on
hardware. Read `doc/dev-fdd/HANDOVER.md` and `doc/dev-fdd/DESIGN.md` first (the read milestone
this builds on), and `doc/the_1581_book.md` chapters 4, 7, 8, 15, 16, 18 for the vocabulary.

---

## 0. TL;DR

* **What:** the MEGA65's internal 3.5" drive, already usable as a read-only Commodore 1581 (IEC
  device 8 or 9, menu "Internal 1581"), learns to **write sectors** and to **format** disks. Writing
  means: `SAVE`, scratch, copy, validate, GEOS, JiffyDOS, copy programs — everything the stock 1581
  DOS does through the WD1772 commands *Write Sector* and *Write Track*.
* **How:** the real WD1772 model is completed in physical mode (the drive CPU feeds bytes through
  DRQ at disk pace, exactly as on the real chip), a small byte FIFO carries them into the existing
  50 MHz controller, which extends its read engine by a write engine (ID search → 22-byte gap →
  sync/DAM/512 bytes/CRC/FF; or index-to-index token stream for formatting), a tiny MFM encoder
  produces 16-bit channel-bit words, and a write front end adapted 1:1 from AExp's field-proven
  `physical_fdd_writer.vhd` turns them into WDATA pulses under a hardware-gated WGATE.
* **Single-pass, real time.** Write Sector writes in the same revolution in which the ID field is
  found — like the real chip, like the MEGA65's own F011 — so the 1581 DOS's side write-back (ten
  sectors in a row) runs at native speed. The normative spec's two-pass "fingerprint" design is
  rejected (section 2.3): it would have made every write 5–10× slower than a real 1581 for no
  safety that the DOS's own verify-after-write does not already provide.
* **Safety = AExp's WGATE discipline, in hardware:** WGATE is the conjunction of enable, motor on,
  media ready, a qualified write-protect reading, an active write phase and no latched abort;
  WDATA is a registered single-driver output and is gated by WGATE; the read decode chain is held
  in reset for the whole write; every abort reason is counted in the diagnostic device. No
  100 MHz "outer safety island", no async IOB clamps, no epoch/generation identity system.
* **The write-protect tab is the only user-facing guard** (same decision as AExp; section 2.6).
  There is no OSM write switch. DD media only.
* **Verification before any hardware write:** the existing GHDL closed loop gets a *writable*
  flux model (the AExp live-disk model), a write→read-back byte-exact gate, the genuine 318045-02
  ROM's own command sequences as fixtures, an independent Python twin for the written flux, and a
  pre-registered mutant matrix. Then sacrificial NOS DD blanks on R3, then the community.

---

## 1. Scope

### 1.1 In scope

| # | Capability | Notes |
|---|---|---|
| S1 | WD1772 **Write Sector** in physical mode (commands `A0`–`BF`, m=0) | 512-byte sectors (N=2) only; deleted DAM (`F8`) supported via a0; P bit honored (section 5.6) |
| S2 | WD1772 **Write Track** in physical mode (`F0`–`F7`), index to index, `F5`/`F6`/`F7` tokens | any token stream, not only the stock format; this is how `N0:` formats |
| S3 | Write Sector m=1 (multi-sector) | implemented in the WD front end (M2) as re-issue like the read path's multi-sector reads; the stock DOS does not use it (section 4) |
| S4 | Real **write-protect** semantics: WD status bit 6 and CIA PB6 from the real pin, no WGATE while protected | the pin is already sensed by the read milestone |
| S5 | Live OSM status `Writing` / `Format` on the `n:Internal 1581` line; idle-gate covers writes | section 9 |
| S6 | Diagnostic device map extension (write instruments) | section 8 |
| S7 | Both drive assignments (Internal 1581 on drive 8 or on drive 9) | nothing drive-specific in the write path |
| S8 | Stock 318045-02 DOS and the user-supplied JiffyDOS 1581 ROM | JiffyDOS is a community test gate, not a design input |

### 1.2 Out of scope (explicitly)

* HD media (f_density stays at the DD level; an HD disk in the drive is a user error, documented).
* Read Track (stays unimplemented in both modes; no DOS uses it).
* Sector sizes other than 512 bytes (N≠2 → Record Not Found + unsupported-size, as in the read path).
* An OSM "write enable" switch (section 2.6).
* The normative spec's data-preserving live source switch (ROM `$0087` cache snooping, drain
  generations). The symmetric idle gate plus a motor-on proxy covers it (section 9.2).
* Write precompensation calibration by instrument: the magnitude is a constant proven on this
  mechanism by AExp's flux measurements (section 5.6).
* Anything the real WD1772 does not do either: no verify-after-write in hardware (the DOS does
  it), no retry, no bad-sector management.

### 1.3 Definition of done

1. A genuine DD disk formatted by the core (`OPEN 15,8,15,"N0:TEST,TS"`) shows an empty directory,
   `VALIDATE` passes, and the disk reads on an independent reader (the MEGA65's native core with
   its F011 decoder, a real 1581, or a Greaseweazle `commodore.1581` decode — any one of them).
2. Programs and sequential files `SAVE`d by the stock DOS and by JiffyDOS load back byte-exactly;
   paich64's `SAV-WRITE` stress tool (the issue #248 instrument) runs clean against the physical
   drive on drive 9 with a D81 on drive 8, and with the physical drive on 8.
3. A D81 image copied to a real disk with a C64 copy program (drive 8 = image, drive 9 = Internal
   1581) and copied back to a fresh D81 compares byte-exact on the PC.
4. The read-only behavior is unchanged (the complete existing GHDL/iverilog/menu suites stay green
   with the writer idle; image mode `fdc1772.v` stays byte-identical).
5. Write protect: a protected disk is never written (WGATE never opens; the DOS reports
   `26, WRITE PROTECT ON`), proven in simulation and on hardware.
6. Every diag counter of section 8 balances in a healthy session (bytes = 531 per sector,
   WGATE window = 531 × 16 × 100 cycles ± one cell, lost = 0, overflow = 0, abort = 0).

---

## 2. Decisions and their grounds

### 2.1 Pragmatic over normative (continuation of the read milestone's approach "B")

The read milestone implemented the functional core of the normative spec and omitted its identity
and ceremony machinery; that decision is locked (`HANDOVER.md` 2.1/2.2) and this milestone follows
it. The AExp write milestone — same mechanism, same pins, same 50 MHz front-end clock, same author —
shipped without an outer safety island, without index-locked RPM proofs and without a two-pass
write, and real Amigas read its disks (`../AExp/.research/HANDOVER-hardware-floppy-write.md`). What
AExp *did* need, after bench and flux measurements, is the short list in section 6, and that list
is adopted in full.

### 2.2 Single-pass real-time Write Sector (not the spec's two-pass fingerprint)

The normative spec (10.6) collects the 512 bytes in one revolution and writes them on the *next*
revolution after re-finding the same ID. For the stock DOS's side write-back (ten single-sector
Write Sector commands issued back to back, starting at the sector under the head +1; see section 4)
that costs about one revolution *per sector*: ≈ 2.2 s per side instead of ≈ 0.3 s, so every SAVE,
scratch and copy becomes 5–10× slower than a real 1581. The real WD1772 and the MEGA65's own F011
write in the revolution in which the ID is found; the pipeline below has deterministic latency
(section 5.3), the 1581 DOS was written for exactly this timing, and the DOS verifies every
written side by reading it back (section 4). Single pass it is.

### 2.3 The DOS feeds bytes at disk pace, through a shallow FIFO; DRQ is derived from FIFO room

The real chip has a one-byte data register and raises DRQ when it is empty; a late byte is replaced
by `00` and flagged LOST DATA. The physical path keeps that contract (section 5.4) but crosses the
clock boundary with a 4-byte Gray-pointer FIFO (the read-path FIFO entity, instantiated in the
other direction). DRQ = "FIFO not full", so the drive CPU may run up to four bytes (the FIFO depth) ahead of the
disk — strictly more slack than the real chip gives, never less. Underrun at a byte slot writes
`00` and sets a sticky LOST DATA; it never tears WGATE (AExp lesson: an erased hole mid-track is
worse than a wrong byte that the DOS will catch).

### 2.4 Write Track is index to index, like the real chip and like the F011

WGATE opens at the first qualified index leading edge after the first token is available and
closes at the next one. No "conservative tail close" computed from RPM profiles: the mechanism was
measured at 300.3 RPM by AExp's flux dumps, the stock format stream (6,122 byte-times = 195.9 ms)
fits a 199.8 ms revolution with 3.9 ms to spare, and a disk that spins too fast for the DOS's
stream is a format error the DOS's verify reports, as on a real 1581. The existing 200 µs index
glitch filter (`physical_1581_inputs.vhd`, `G_INDEX_MIN_LOW_CYC`) delays open and close by the same
amount, which merely rotates the written track by 6 byte-times; no new index logic is built.

### 2.5 The writer front end is AExp's, reused

`../AExp/CORE/vhdl/physical_fdd/physical_fdd_writer.vhd` serializes 16-bit channel-bit words at a
fixed 2.000 µs cell, emits one 500 ns active-low WDATA pulse per `1` bit launched at the cell
midpoint, applies a 7-cell-window peak-shift precompensation of 140 ns, defines WGATE at the
output stage with zero lead-in/lead-out cells, qualifies the write-protect tab, latches aborts and
counts everything. All of that is byte-format agnostic. The 1581 only has to put an MFM byte encoder
with CRC and sync-word generation in front of it (section 5.5). The AExp field history (first
working disk 2026-08-31, external referee on real A500/A500+/A1200 2026-09-05, flux-level
confirmation of pulse placement, precomp and tail 2026-09-20) is the strongest evidence this
project can get without instruments.

### 2.6 No OSM write switch; the tab is the guard

Same decision as AExp (sy2002, 2026-08-21, "decision 1"): there is no software switch, no "are you
sure". The user documentation gets AExp's "Writing: the one thing to be careful about" section
adapted for the C64 (originals stay write-protected; use blanks for writing; HD media do not
work). Rationale: a switch that defaults to "read-only" is one more thing that silently makes
`SAVE` fail with `26, WRITE PROTECT ON` for a user who closed the tab on purpose; a switch that
defaults to "writable" protects nobody. The hardware tab is unambiguous and the DOS reports it.
*If the maintainer wants belt and braces for the alpha phase*, a single-select "Internal 1581
writes: Allowed / Blocked" item under Drive Settings costs one OSM bit and one gate term
(`wr_allow`) in the WGATE conjunction; it is listed as option in the plan, not in this spec.

### 2.7 No 100 MHz safety island, no async IOB clamp

The normative spec's `physical_1581_outer_safety` (16.2/12.2) protects against a stopped 50 MHz
clock while WGATE is low. In M2M the 50 MHz QNICE clock is the clock the whole Shell runs on; if
it stops, the machine is dead and the FPGA's `hr`/`main` MMCMs are gone with it. AExp ships
without it. The writer's outputs reset to `1`, WGATE is a registered conjunction re-evaluated
every cycle, and the mechanism itself ignores WGATE while its /WPROT is active (defense in depth
the drive provides for free).

### 2.8 Precompensation: 140 ns, 7-cell window, follows the WD P bit

See section 5.6. The real WD1772 applies ≈125 ns when the command's P bit is 0; AExp measured
140 ns as the magnitude a real A500 writes on this medium and verified the written shifts by flux
capture. One constant, diag-selectable OFF/ON/follow-P for experiments, default follow-P.
Note what "follow P" means on a 1581: the stock ROM clears P (precomp on) for cylinders 1–43 and
sets it (off) for 0 and 44–79 (section 4.1) — the outer cylinders are precompensated, the inner
ones not, the opposite of the usual intent. Following P reproduces a real 1581's magnetic
fingerprint exactly, which is what an external referee reads best; the physically "better"
inner-only policy is one diag setting away for experiments. Either is harmless on DD media.

---

## 3. Architecture

### 3.1 Data flow

```
   drive domain (~31.5 MHz core clock, 16 MHz / 8 MHz / 2 MHz enables)   |   50 MHz controller domain (QNICE clock)
                                                                          |
   1581 DOS (T65 @ 2 MHz) ---- STA $6003 (data reg) ---> fdc1772.v ------|---> physical_1581_wfifo (4 bytes, Gray CDC)
        ^                                                phys write      |            |
        |  DRQ = FIFO not full (section 5.4)             branch          |            v
        +------------------------------------------------- status/done <-|--- physical_1581_controller: WRITE ENGINE
                                                        (toggle + tag)   |      ID search (shared with reads) -> 22-byte gap
                                                                          |      -> 12x00 3xA1 DAM 512 CRC FF   (Write Sector)
                                                                          |      -> index -> tokens F5/F6/F7 -> index (Write Track)
                                                                          |            | bytes + mark flags, one per 32 us
                                                                          |            v
                                                                          |   physical_1581_mfm_encoder (byte -> 16 channel bits, CRC-16)
                                                                          |            | 16-bit words, same clock, 4-deep sync FIFO
                                                                          |            v
                                                                          |   physical_1581_writer (AExp writer: cell serializer,
                                                                          |      precomp, WDATA pulses, WGATE conjunction, abort latch)
                                                                          |            |
                                                                          |            v  registered, reset '1'
                                                                          |   main.vhd -> mega65.vhd -> top_mega65-r{3,4,5,6}.vhd -> f_wgate / f_wdata pins
```

Everything right of the bar is new or extended VHDL under `CORE/vhdl/physical_1581/`; everything
left of it is the existing SystemVerilog drive with a completed physical branch in `fdc1772.v`.
The two domains meet exactly where the read path meets them today: toggle handshakes with 2-bit
sequence tags for requests and completions, a Gray-coded FIFO for the byte stream, 2-FF
synchronizers for levels. No third clock domain, no new PLL output, no BRAM (the FIFOs are
LUTRAM; AExp's write FIFO cost zero block RAM).

### 3.2 Module list

| File (`CORE/vhdl/physical_1581/`) | Status | Role |
|---|---|---|
| `physical_1581_pkg.vhd` | extend | write op codes `WROP_*`, result codes `RES_LOST_DATA`, `RES_WRITE_PROTECTED` (exists), `RES_NO_INDEX` (exists); write timing constants (section 5.7) |
| `physical_1581_controller.vhd` | **done (M1b)** | the write engine (section 5.3) as new `WR_*` states of the one request/done discipline, sharing `RD_WAIT`/ID search with the read engine; the encoder and the writer are instantiated inside the controller, which therefore owns `f_wgate_o`/`f_wdata_o`; mechanics guard after a write; ports in 5.2 |
| `physical_1581_wfifo.vhd` | new (port of `../AExp/CORE/vhdl/physical_fdd/physical_fdd_wfifo.vhd`, 8-bit data) | drive-domain → 50 MHz byte CDC FIFO with both-side occupancy taps |
| `physical_1581_mfm_encoder.vhd` | new | byte + mark flag → 16-bit MFM word (clock bits, `A1`/`C2` sync words), running CRC-16 with the `F5` preset rule |
| `physical_1581_writer.vhd` | new (port of `physical_fdd_writer.vhd`) | cell serializer, precomp, WDATA/WGATE, tab qualifier, abort latch, counters |
| `physical_1581_diag.vhd` | **done (M3)** | map v8: write instruments (section 8), `WR_CTRL` writable |
| `physical_1581_inputs.vhd` | unchanged | (index qualification reused as is) |
| `physical_1581_rdfifo.vhd` | unchanged | |
| MFM decoder, CRC, quantiser, gaps | unchanged | the CRC entity is instantiated a second time inside the encoder |

Outside the folder:

| File | Change |
|---|---|
| `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v` | **done (M2, branch `write-m2`)**: physical Write Sector / Write Track branch: request issue, DRQ from FIFO room, data-register writes → FIFO push, WP check, LOST DATA, status, m=1 re-issue (section 5.4). Image mode: byte-identical (the golden trace of 10.2) |
| `c1581_drv.sv`, `c1581_multi.sv`, `iec_drive.sv` | **done (M2)**: the new `phys_wr_*` ABI signals threaded (same pattern as the `phys_rd_*` ones; the push strobe is qualified with the selected drive's `phys_mode` in `c1581_multi`) |
| `CORE/vhdl/main.vhd` | **done (M3)**: the wfifo instance (write side `clk_main_i` with the QNICE reset synchronized into it, read side the 50 MHz controller clock), the iec_drive ↔ controller write wiring, `f_wgate_o`/`f_wdata_o` straight from the controller, the diag port map incl. the three synced WD toggles |
| `CORE/vhdl/mega65.vhd` | **done (M3)**: the two output ports and the diag write strobe (`qnice_dev_we_i` for `C_DEV_C64_PHYS1581`) |
| `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd` | **done (M3)**: the two pins routed from `MEGA65_Core`, the tie-offs gone, drive B still tied; the `M2M-UPSTREAM floppy-pins (C64MEGA65 issue #244, 2026-10-17)` tag; identical on the four boards |
| `CORE/vhdl/globals.vhd` | none (device id `C_DEV_C64_PHYS1581` stays) |
| `CORE/vhdl/config.vhd` | **done (M3)**: `CORE_VERSION := "WIP-V6-A21X1"` (no menu change) |
| `CORE/m2m-rom/m2m-rom.asm` | **done (M3)**: states `WRITING`/`FORMAT` and their labels (section 9); the busy mask value is unchanged because the write code lives inside it; +116 ROM words |
| `CORE/CORE-R{3,4,5,6}.xpr` | **done (M3)**: the three new VHDL files listed before the controller (VHDL-2008) |
| `doc/1581_dd_debug_device.md` | **done (M3)**: the map v8 table and the healthy-session balance |
| `README.md`, `FAQ.md`, `VERSIONS.md`, `tests/README.md`, `doc/inofficial.md`, `doc/models.md` | M3 drafted the README/FAQ "writing to real disks" text, the `tests/README.md` A21 section, the `inofficial.md` row (hash TBD) and the `models.md` line; `VERSIONS.md` is release-time |

### 3.3 Clock-domain crossings (complete list)

| Signal | Direction | Mechanism |
|---|---|---|
| `phys_rd_req_tgl` + op/track/sector/side/seq/flags (now also carrying write ops) | drive → 50 MHz | existing toggle + quasi-static payload (payload stable before the toggle) |
| `phys_rd_cancel_tgl` | drive → 50 MHz | existing |
| `phys_rd_done_tgl` + `done_seq` + result + flags | 50 MHz → drive | existing (registered on the done cycle, `C_DONE_GAP` spacing) |
| write bytes | drive → 50 MHz | `physical_1581_wfifo` (Gray pointers; both sides reset from the QNICE reset, each synchronized into its own domain — the one rule the read milestone learned the hard way) |
| `phys_wr_feed` (level: "ID found / index armed, feed me") | 50 MHz → drive | 2-FF (`iecdrv_sync`) |
| `phys_wr_lost` (level, sticky per op) | 50 MHz → drive | 2-FF; sampled at done |
| `phys_wr_busy`, `wr_ok` (levels, for the Shell busy vector and announce) | 50 MHz → diag (same domain) / drive | 2-FF where needed |
| FIFO occupancy for DRQ | drive side native | `wr_level_o` of the wfifo is computed in the write (drive) domain — no crossing (AExp's "ready never crosses" rule) |

The existing clock-pair cut in `CORE/CORE.xdc` (`set_false_path` qnice_clk ↔ main_clk, both
directions) already covers all of these; no new constraint. The two pins are asynchronous outputs
to the mechanism, unconstrained like the existing six.

---

## 4. The workload: what the 1581 DOS does when it writes

Design input for every timing decision. Source: the genuine 318045-02 ROM, disassembled and
re-executed in the project's emulator (`doc/dev-fdd/rom_emu`) extended with an exact 6502 cycle
table and a rotationally timed, writable WD1772 model; full detail with ROM addresses in
`doc/dev-fdd/write_research_dos1581.md`. Cycle counts are 2 MHz 6502 cycles (0.5 µs); one DD
byte-time is 32 µs.

### 4.1 Commands and flags the engine will actually see

* Write Sector `$A8`/`$AA`, Write Track `$F8`/`$FA`, Read Sector `$88`, Read Address `$C8`, Force
  Interrupt `$D0`, Type I `$08`/`$18`/`$48`/`$68`. **Never** m = 1, E = 1, a0 = 1 (deleted DAM),
  V or spin-up-wait; the DOS runs the motor itself through CIA PA2.
* The P bit (`$CFE3`): clear (precomp *on*) for cylinders 1–43, set (off) for cylinders 44–79 and —
  through an unsigned underflow — for cylinder 0. A real 1581 therefore precompensates the outer
  cylinders only; see decision 2.8.
* Command issue (`$CBF4`): write the command, then **spin until BUSY reads 1** (first sample 6
  cycles after the write, 7-cycle period, no timeout). Completion wait (`$CBEC`): spin until BUSY
  reads 0, no timeout. A command whose BUSY is up for only four cycles hangs the ROM forever
  (measured) — every termination, including immediate write-protect refusals, must hold BUSY
  for at least a byte-time (the Type-I minimum of the read milestone is the same idea).
* Status evaluation (`$CD3F`, table `$CD5A`): only bits 6 (WP → job 8 → DOS 26), 4 (RNF → job 2 →
  DOS 20) and 3 (CRC → job 5 → DOS 23) are decoded; bit 5 is masked; bit 2 (LOST DATA) takes the
  stack-bug path (`$CD53`) and crashes the drive; CRC + RNF together index a **success** hole;
  WP together with CRC or RNF indexes garbage job codes, one of which hangs the DOS. Hence the
  purity rules: WP alone, never CRC + RNF, LOST DATA only for a genuine real-chip miss.

### 4.2 Write Sector as the DOS drives it

* Register setup: the job first issues Read Address (`$CFA6` → `$CD00`, about 2.0–2.3 ms including
  the software CRC check of the reply), compares the cylinder with the cached one, writes the
  track register, computes the P bit, then sets **sector = R + 1 (wrapping 10 → 1)**, leaves
  ≥ 20 µs of NOPs and writes the command. No seek between the ten sectors of a side.
* The transfer loop (`$C667`) polls BUSY first, DRQ second (13-cycle poll) and writes one byte per
  DRQ. The first byte is **not preloaded**: it arrives 22–33 cycles (11–16.5 µs) after the first
  DRQ. Worst-case DRQ-to-data latency in the data phase: 35 cycles = 17.5 µs. The loop exits on the
  BUSY drop, never on a byte count; after the 512th byte `$CD3F` waits for BUSY = 0.
* Between consecutive Write Sector commands: **66–68 µs** from BUSY drop to the next command write
  (95 µs across the 10 → 1 wrap). The next ID's sync run starts 1.09 ms after the previous
  sector's trailing `FF`, its CRC ends 1.8 ms after it. Any design that needs more than about a
  millisecond to be searching again, or that writes on the *next* occurrence of the ID, costs a
  full revolution per sector.
* Measured flush of one side (stock disk, head on track): Read Address, Read Address, ten Write
  Sectors in 243 ms, 1.65 ms pause, Read Address, ten Read Sectors byte-compared against the cache
  (verify), final Read Address — 495 ms in all. The whole side is always rewritten, even for one
  changed 256-byte block. A SAVE therefore produces several such flushes (directory side, data
  side(s)), i.e. `CNT_WR_SECT` grows in multiples of 10.
* The DOS tolerates an extra revolution per sector (no timeouts; measured 691 ms instead of
  495 ms when one sector was delayed one revolution), but with jobs running under `SEI` the C64
  is held on the IEC bus for the duration — the reason for decision 2.2.

* Measured again in M2 with the WD front end's own model (`doc/dev-fdd/rom_emu/run_write_proofs.py`,
  fixture `fixtures/write_back_order.json`, cylinders 0, 1 and 79): write order k+1 … 10, 1 … k as above,
  132–138 cycles from BUSY drop to the next command (188 across the 10 → 1 wrap), the first byte 26–34
  cycles after the first DRQ (which is the controller's feed in this design), data bytes 22–37 cycles,
  38,840 cycles of BUSY per Write Sector, 243.2 ms per side flush, verify pass as above. Under FIFO-room
  DRQ the ROM's loop needs at most 37 of the 64 cycles of a byte-time.

### 4.3 The side cache, its flush triggers and retries

* Cache `$0C00`–`$1FFF` (one side), dirty byte `$87`, cached cylinder `$95`, side `$97`. Flush
  triggers: idle (320 ms after the last ATN by default, `U0>I` changes it), replacement (another
  cylinder/side needed), explicit dump. The motor stays on ≈ 10 s after the last job, so a flush
  normally finds it running; `motor on` in the idle gate therefore covers the dirty-cache window
  with a wide margin (section 9.2).
* Verify (`$8D` bit 7, default on, **stored in BAM byte 6 and reloaded from every disk** —
  foreign-formatted disks with byte 6 = 0 silently run without verify): Read Address, then ten
  Read Sectors compared byte by byte; a mismatch issues **Force Interrupt `$D0` into a running
  Read Sector** (126 µs later it polls BUSY = 0), job 7 → DOS 25 WRITE ERROR.
* Retry: any job error ≥ 2 drops the cache; the DOS re-dirties and re-posts the flush, three
  attempts in total, each a fresh Read Address + ten writes + verify. After the third failure the
  data is gone (the SAVE was acknowledged long before). Format has **no** retry at all.
* A second Write Sector issuer exists: the burst single-sector write (`$C733`, job `$A6`): Read
  Address, one Write Sector from buffer `$0300`, no verify, bypasses the cache.

### 4.4 Format as the DOS drives it

* `N:` → Restore (`$08`) + 18.3 ms settle, then job `$F0` over 80 cylinders × 2 sides: select side,
  **Write Track issued ≈ 100 µs after the side switch** (the DOS relies on the index wait for
  side settle — the engine must enforce its own), track register = cylinder, P bit per 4.1.
* The DOS does not wait for the index; it loads the first token 19 cycles after the first DRQ and
  then feeds at DRQ pace. Token stream, confirmed token for token: `32 × 4E`, then ten records of
  `12 × 00, 3 × F5, FE, C, H, R, 02, F7, 22 × 4E, 12 × 00, 3 × F5, FB, 512 × data, F7, 35 × 4E`,
  then `4E` until BUSY drops. Data bytes are the constant `$00` for a stock `N:`; 32 + 10 × 609 =
  6,122 magnetic byte-times (195.9 ms), 6,230 host tokens per 6,250-byte-time revolution. Worst
  token latency: 33 cycles (16.5 µs) in fill mode, 45 cycles (22.5 µs) in buffer mode (reachable
  through the burst format command). After an `F7` the next DRQ is two byte-times away.
* After each Write Track: status, 1.65 ms, the verify pass of 4.3 against the fill byte; then the
  other side, then seek + 18.3 ms settle. Whole disk ≈ 73–105 s, typically ≈ 90 s on a real 1581.
  One error anywhere aborts the format half done (DOS error reported).
* Burst-mode format (`U0`) can change geometry: N = 1/2/3 → 16/10/5 sectors of 256/512/1024 bytes,
  gap3 22/38/68, fill byte `$E5`, cylinder range. The token-agnostic Write Track writes any of
  them; only N = 2 disks are readable back by this project (unchanged scope).

* Fixture (M2): `fixtures/format_tokens.bin` with the `fixtures/format_tokens.json` sidecar — the 6,234
  tokens the DOS writes for one side of `N0:` (6,230 reach the disk, 4 are drained at the index cut),
  60 × `F5`, 20 × `F7`, token latency 14–32 cycles after the first (55), 25,202 cycles from the first DRQ
  to the starting index in the model. With FIFO-room DRQ the `F7` double slot is a pause in the
  controller's pops, not a DRQ gap the DOS can see.

### 4.5 Write protect and disk change as the DOS sees them

* Write protect is sampled from CIA PB6 **only at initialise** (job `$B6` → `$01FA`); later writes
  on a cache hit are refused at the DOS level without touching the WD. A tab closed after login is
  caught only by WD status bit 6 (three attempts, then `26, WRITE PROTECT ON`, cache dropped).
  Nothing samples PB6 or status during the data loop: a mid-write tab change is the hardware's
  business (section 6.3) and surfaces only when BUSY drops.
* Disk change (PA7) is checked in the readiness stage before a job (a step-in/step-out pair clears
  the mechanism latch; DOS 74 if still asserted) and in the idle tick (drops the cache). **During a
  flush PA7 is never read**: with PA7 asserted the DOS wrote all ten sectors and verified them. If
  the hardware aborts with RNF, the DOS retries, and once the readiness step pair clears the latch
  on a newly inserted disk the stale side is written onto the new disk — genuine 1581 behaviour,
  not preventable below the DOS.

### 4.6 Consequences baked into sections 5–7

1. Real-time single-pass Write Sector; the controller must be searching again within ≈ 1 ms of
   the previous done (it is: the done/request round trip is microseconds).
2. BUSY visibly high for every termination: the WD front end arms `PHYS_T1_MIN_TICKS` (1.5 ms) at the
   WP pre-check and at every write issue, so every write termination — immediate refusal, a
   controller-side refusal, an abort — holds BUSY at least that long (a real write lasts ≥ 17 ms, so
   the minimum never delays one).
3. Status purity: WP alone; never CRC + RNF; bit 5 always 0; LOST DATA only on a genuine miss of
   the real-chip deadline (the DOS's worst case is 17.5 µs per byte; the FIFO adds three bytes of
   slack to the chip's one byte-time).
4. No DRQ-count-based completion anywhere; completion is the controller's done after the writer's
   tail.
5. Write Track starts at the next qualified index after the first token is present and ends at the
   following one; the token stream length is the DOS's business.
6. Verify is not a safety net the engine may rely on (it can be off per disk).

---

## 5. Contracts

### 5.1 What the WD1772 front end (`fdc1772.v`, physical branch) does per command

Until M2 a physical-mode Write Sector or Write Track *fake-finished*: BUSY was
dropped on the first execute tick after acceptance and status bit 6 was forced to 1
(`fdc1772.v:980-984`, `:1122-1124`, `:1710-1713`). Note that CIA PB6 already reflects the real tab, so
on a writable disk the DOS does issue the WD write and sees BUSY for ~125 ns — shorter than the
ROM's wait-busy-set poll (the round-11 Type-I hang class, `fdc1772.v:262-277`). The write milestone
replaces both fake-finishes by real operations on the controller done handshake, which removes
that class structurally. (The shipped read-only builds up to A20X3 still carry that hazard; the fix ships with the
write milestone, which is why no separate interim build is planned.)

**Write Sector (`cmd[7:5] = 101`), physical mode:**

1. Acceptance (existing path): BUSY set, `phys_cmd_clear` (DRQ + LOST DATA + latched flags cleared),
   RNF cleared, motor-on request. No spin-up gate (the controller owns readiness), no E-flag delay
   (the controller owns `head_settled`).
2. Write-protect pre-check: if `phys_wprot_c = '1'` → complete with status bit 6 set (and bits 4/3
   clear — WP must appear alone, section 4.1), INTRQ, **BUSY held for `PHYS_T1_MIN_TICKS`
   (1.5 ms) before it clears**: the ROM spins until it has seen BUSY high and a four-cycle BUSY
   pulse hangs it (section 4.1). No request to the controller, no DRQ. (Real chip: samples /WPRT at
   command start.) The forced "always protected" term of the read-only milestone is removed.
3. Otherwise issue the request on the existing channel: `phys_rd_op <= WROP_WRITE_SECTOR`,
   track/side/sector from the registers, `phys_rd_seq++`, toggle `phys_rd_req_tgl`, set
   `phys_rd_pending`. New quasi-static payload bits: `phys_wr_deleted` (command a0 → DAM `F8`),
   `phys_wr_precomp` (command P bit inverted: P = 0 → precomp on). The issue also arms
   `PHYS_T1_MIN_TICKS`, so a controller-side immediate result (a write-protect race, not ready) is
   still seen by the ROM's wait-busy poll.
4. DRQ generation (section 5.4): no DRQ until the controller asserts `phys_wr_feed` (ID found);
   then DRQ = write FIFO not full, until 512 bytes have been accepted (preloaded bytes included)
   or the op completes. *Every* CPU write to the data register during the op pushes the byte into
   the write FIFO (a driver that preloads the data register before DRQ — the image path's
   `data_in_valid` case — therefore works unchanged: the FIFO is empty at command start and the
   preloaded byte is simply the first data byte) and clears DRQ for that cycle. Data-register writes are
   accepted (pushed) while the op is active, for Write Sector below 512 bytes, and — once the
   controller's feed has been seen — only while it is still up; a write outside that window, or while
   the FIFO is full, is dropped and counted (`phys_dbg_wr_drop_tgl`). That is unreachable for a
   DRQ-driven CPU inside the op and normal for the trailing `4E` tokens the DOS keeps writing after a
   Write Track's ending index until BUSY drops.
5. Completion: on the tag-matched `phys_rd_done` edge (existing 2-cycle-delayed consume), latch
   result + flags; finalize exactly as reads do but *without* the byte-drain tail: BUSY cleared and
   INTRQ raised when (a) the done was consumed, (b) `phys_wr_busy_c` (the writer's busy, synced)
   is low — "done is defined at the output stage" (AExp lesson) — and (c) the minimum busy armed at
   the issue has elapsed. Status: bit 6 (WP) = result is
   `RES_WRITE_PROTECTED` (the WD then forces bits 4 and 3 clear, whatever flags accompany the result); bit 5 = 0 (no write fault modelled); bit 4 RNF = `rd_rnf` and not CRC;
   bit 3 CRC = `rd_crc_err` (ID CRC errors only — a matching ID with bad CRC that was never
   resolved within the search budget); bit 2 LOST DATA = `phys_wr_lost_c` or the first-byte abort;
   bit 1 DRQ; bit 0 BUSY. CRC and RNF are never set together (the `$CD5A` hole rule).
6. Multi-sector (m = 1): on an intermediate success, `sector_inc_strobe`, re-issue with a fresh
   sequence tag (the `phys_reissue` pattern of multi-sector reads); any error is terminal, LOST DATA included. Implemented
   in M2 (bench group 21). The stock DOS uses m = 0 only.
7. Force Interrupt during a write: existing path — toggle `phys_rd_cancel_tgl`, clear the engine
   state; the controller aborts (section 7). Immediate FI (`D8`) clears BUSY at once, as on the
   real chip; the controller's writer closes WGATE within one cell on its own.

**Write Track (`cmd[7:4] = 1111`), physical mode:**

1. Acceptance and WP pre-check as above.
2. Request `WROP_WRITE_TRACK` (track/side for diagnostics only).
3. DRQ = FIFO not full from the moment the controller asserts `phys_wr_feed`, which it does
   immediately on acceptance of the op (real chip: first DRQ right after the command); tokens flow
   until the controller reports done (the ending index). The WD side does not count tokens.
4. Completion as for Write Sector. Status: bit 6 WP, bit 2 LOST DATA (any token slot underrun, or
   the first token missing at the starting index), bit 4 RNF = `RES_NO_INDEX`.

**Everything else** (Read Sector, Read Address, Verify, Type I, Force Interrupt, image mode) is
untouched. Image mode remains expression-for-expression the shipped code; the new logic is gated
on `phys_mode` exactly like the read branch (standing regression argument, `tb_fdc1772_physical.sv`
+ the image-mode golden trace of the plan).

### 5.2 ABI additions (drive domain ↔ controller)

| Signal | Dir | Type | Meaning |
|---|---|---|---|
| `phys_rd_op` values `WROP_WRITE_SECTOR = "100"`, `WROP_WRITE_TRACK = "101"` | drive → ctl | quasi-static with the request toggle | reuse of the existing op channel; the controller's pending-request latch, cancel edge and done-tag discipline apply unchanged |
| `phys_wr_deleted` | drive → ctl | quasi-static | DAM `F8` instead of `FB` |
| `phys_wr_precomp` | drive → ctl | quasi-static | precomp requested (P = 0) |
| `phys_wr_byte_wr` / `phys_wr_byte_data[7:0]` | drive → wfifo | strobe + data, drive clock | one push per data-register write while feeding |
| `phys_wr_fifo_full` / `phys_wr_fifo_level` | wfifo → drive | drive-domain native | DRQ source; level is conservative-high (carried for completeness, the WD uses `full` only) |
| `phys_wr_feed` | ctl → drive | level, 2-FF | "start/keep raising DRQ" — set at ID found (sector) or op start (track), cleared at op end |
| `phys_wr_lost` | ctl → drive | level, 2-FF, sticky per op | a slot was served from an empty FIFO; raised during the op and **held through the done until the next request is accepted** (the WD samples it two drive clocks after the synced done edge), cleared at acceptance |
| `phys_wr_busy` | writer → drive | level, 2-FF | writer not idle (gate open or tail draining) |
| `phys_wr_ok` | writer → diag | level | tab qualified writable (section 6.2); not an `fdc1772` port |
| `phys_dbg_wr_fin_tgl`, `phys_dbg_wr_wp_tgl`, `phys_dbg_wr_drop_tgl` | drive → diag | never-reset event toggles | a write op finalized / a write refused by the WP pre-check / a data-register write dropped (5.4) |

The port names are identical in `fdc1772.v`, `c1581_drv.sv`, `c1581_multi.sv` and `iec_drive.sv`
(M2). On the VHDL side (M1b) the controller has `wr_deleted_i`, `wr_precomp_i`, `wr_precomp_mode_i`
(the diag `WR_CTRL` override: 0/3 follow, 1 off, 2 on), the wfifo read side `wbyte_data_i` /
`wbyte_empty_i` / `wbyte_rd_o`, the levels `wr_feed_o`, `wr_lost_o`, `wr_busy_o`, `wr_ok_o`, the pins
`f_wgate_o` / `f_wdata_o` and the `diag_wr_*` taps of section 8. `main.vhd` (M3) connects
`phys_wr_byte_wr/_data` to `physical_1581_wfifo.wr_en_i/wr_data_i` on the drive clock, `wr_full_o` /
`wr_level_o` (3 bits) back to `phys_wr_fifo_full/_level`, the wfifo read side to `wbyte_*` at 50 MHz,
the three levels to `phys_wr_feed/_lost/_busy`, and the two quasi-static bits to `wr_deleted_i` /
`wr_precomp_i`; both wfifo resets come from the QNICE reset event, each synchronized into its own
domain. Cross-boundary check (plan section 4) done by the controller on 2026-10-17: every name,
width and clock domain matches.

The existing `rd_done_tgl/rd_done_seq/rd_result/rd_crc_err/rd_rnf` carry the write results; the
`RES_*` vocabulary gains `RES_LOST_DATA = "01011"` (first-byte abort or token underrun — distinct
from the sticky mid-sector `phys_wr_lost`, which is a flag on an otherwise successful op) and
reuses `RES_WRITE_PROTECTED`, `RES_RECORD_NOT_FOUND`, `RES_ID_CRC_ERROR`, `RES_DISK_CHANGED`,
`RES_CANCELLED`, `RES_NO_INDEX`, `RES_NOT_READY`, `RES_UNSUPPORTED_SIZE`.

### 5.3 The controller's write engine (50 MHz)

A second FSM next to the read engine, sharing `RD_IDLE`'s acceptance (the op code decides which
engine runs; both are never active at once), `RD_WAIT`'s preconditions and `RD_SEARCH`'s ID
matcher. States (names are the implementer's; the semantics are binding):

```
WR_IDLE   -- accepted op with WROP_* code (live edge or pending latch, C_DONE_GAP honored)
  |
WR_WAIT   -- media_ready and head_settled and side_settle = 0 and the writer idle   (RES_NOT_READY on the 1.10 s watchdog)
  |        -- wprot_c = '1'            -> RES_WRITE_PROTECTED, done (no feed, no gate)
  |        -- then wait for wr_ok (the tab qualifier, 6.2); not qualified within the readiness budget -> RES_WRITE_PROTECTED
  |        -- NOTE: the sticky change latch is deliberately NOT a refusal term (a level gate would
  |           block a DOS that rewrites without stepping after a swap; AExp lesson). The live change
  |           edge aborts (section 6.3) and the tab qualifier re-arms on every change edge (6.2).
  |
  +-- Write Sector ------------------------------------------------------------
  |   WR_SEARCH  -- dec_rst; same budget as reads: 5 index edges / 1.300 s; match C = track, R = sector,
  |   |             ID CRC ok, N = 2 (else RES_UNSUPPORTED_SIZE); CRC-only / RNF-only exhaustion exactly as reads
  |   |          -- on match: feed <= '1' (DRQ starts in the drive), gap_cnt <= 22 byte-times (section 5.7)
  |   WR_GAP     -- count down; at expiry: FIFO empty -> RES_LOST_DATA (feed <= '0', no gate: real-chip rule)
  |   |                                   else session <= '1' (writer ARM->STREAM), byte index <= 0
  |   WR_STREAM  -- one byte per word request from the writer (32 us):
  |   |             idx 0..11  : 00          (CRC preset at idx 12)
  |   |             idx 12..14 : A1 sync     (CRC over A1 A1 A1 -> 0xCDB4)
  |   |             idx 15     : DAM FB / F8 (CRC)
  |   |             idx 16..527: FIFO pop, or 00 + lost <= '1' when empty  (CRC)
  |   |             idx 528,529: CRC hi, lo
  |   |             idx 530    : FF
  |   |          -- after idx 530: session <= '0' (writer closes WGATE at the end of that word's last cell)
  |   WR_TAIL    -- feed <= '0' FIRST (in the clock of the last push), wait writer busy = '0' and at
  |                 least 16 cycles since feed fell (the drive's last push may still be in flight through
  |                 the 2-FF of feed), drain the wfifo to empty (late bytes of a lost sector), result
  |                 RES_OK (+ lost flag), done; arm the 700 us mechanics guard
  |
  +-- Write Track -----------------------------------------------------------------
      WR_TRK_ARM -- feed <= '1' at once; wait for an index_edge (filtered leading edge, 200 us floor);
      |             watchdog 300 ms -> RES_NO_INDEX + rnf (feed <= '0', no gate)
      |          -- at the edge: FIFO empty -> RES_LOST_DATA (real chip: first byte missing at index)
      |                          else session <= '1'; CRC state "idle"
      WR_TRK_STREAM -- per word request: pop a token (empty -> 00 + lost):
      |             F5 -> A1 sync word; if the previous token was not F5: CRC <= FFFF before feeding A1
      |             F6 -> C2 sync word (CRC fed)
      |             F7 -> emit CRC hi then CRC lo (two words, one token); CRC state irrelevant afterwards
      |             other -> plain MFM byte, CRC fed
      |          -- at the next index_edge: session <= '0' AND pulse the writer's cut_i in the same clock
      |             (no later than the last word push in flight, i.e. at most 3 clocks after the edge);
      |             the writer truncates at the next cell boundary (WGATE closes within one cell, the
      |             current word and the buffered words are dropped, as on the real chip) -> WR_TAIL
      |          -- watchdog 260 ms from the start edge -> close, RES_NO_INDEX
      WR_TAIL    -- as above (feed off at the cut, writer idle + 16 cycles, drain the trailing tokens, done)
```

The wfifo is also drained while the write engine is idle and at every write-op acceptance (the read
path's idle-drain rule), so no op ever starts with residue; the order inside `WR_TAIL` matters because
the DOS keeps feeding `4E` tokens after a Write Track's ending index until BUSY drops. As implemented
(M3): the feed falls with the last word strobe (sector) or in the clock of the cut (track) and on entry
to `WR_ABORT`; `WR_TAIL` and `WR_ABORT` report only once the feed has been low for 16 clocks. The three
exits that never opened the gate (the first-byte `RES_LOST_DATA` of `WR_GAP`, the first-token
`RES_LOST_DATA` and the start watchdog of `WR_TRK_ARM`) report directly; a late byte there is eaten by
the idle drain.

Abort inputs (any state after WR_WAIT, i.e. also during the search, the gap and the writer's ARM):
cancel edge (Force Interrupt), the 4-sample filtered assert **edge** of `change_c` (the mechanism
holds /DSKCHG until the next step, so a level would block a DOS that rewrites without stepping after
a swap; the read engine keeps its level rule), a 4-sample protected level, motor request falling,
`media_ready` lost, a side change, enable falling, QNICE reset, and the writer's own abort or
discard → WGATE closes in the clock that sees the term (section 6.3), `feed <= '0'`, FIFO drained,
result per section 7, done toggled with the usual spacing. Result mapping of the writer's own
outcome: discard at ARM (tab not qualified) → `RES_WRITE_PROTECTED`; reason 0x04 →
`RES_WRITE_PROTECTED`; 0x08 → `RES_DISK_CHANGED` + rnf; 0x40 → `RES_INTERNAL_FAULT`; 0x02 / 0x20 /
0x80 → `RES_CANCELLED`; the track watchdogs → `RES_NO_INDEX` + rnf.

The ID matcher is shared code, so the write search inherits the read path's qualified-A1-train
decoder, its RNF/CRC accounting and its diagnostic strobes; the write-specific diag strobes are
listed in section 8.

### 5.4 Byte flow and LOST DATA (the real-time contract)

* The write FIFO is 4 bytes deep (`G_AW = 2`), write side = drive clock, read side = 50 MHz. DRQ in
  the drive is `feed and not full and not done_512` (sector) / `feed and not full` (track). The DOS
  therefore runs at most four bytes (the FIFO depth) ahead of the disk; the real chip allows one. Any DOS loop
  that works on a real 1581 works here with more margin, never less.
* Controller pops: one per word request from the writer, i.e. one per 32.000 µs of disk time,
  derived from the 50 MHz cell engine, never from the drive's 8 MHz enable (which is 31.5 µs per
  252 ticks — close, but the flux must be paced by the writer alone; `PHYS_PACE_TICKS` stays a
  read-path constant).
* Empty at a data slot → the slot is written as `00`, `lost` becomes sticky for the op, writing
  continues to the end of the sector/track. The late byte, when it arrives, is written in the next
  slot — the shift the real chip produces too, and the shift issue #248 fought in image mode. The
  DOS sees status bit 2 and its verify pass; it retries. WGATE is never torn by an underrun.
* First-byte rule: if the FIFO is still empty when the 22-byte gap expires (sector) or at the
  starting index (track), the command fails with LOST DATA and **WGATE never opens**. The real
  WD1772 checks the data register 11 byte-times after the ID CRC; checking at 22 (the image-mode
  `WR_FIRST_GRACE` rule of issue #248) is deliberately more lenient, never stricter. The DOS loads
  the first byte 11–16.5 µs after the first DRQ (section 4.2), so neither deadline is ever near.
* The drive stops raising DRQ after 512 accepted bytes (sector) so the ROM's counted loop and the
  chip agree; leftover bytes (a lost sector's late bytes) are drained by the controller in
  `WR_TAIL` before the done — the FIFO is empty at every op boundary (AExp residue rule). Because the
  DOS feeds `4E` until BUSY drops after a Write Track, the drive accepts data-register writes only while
  the controller's feed is up (once seen); the controller drops feed before it drains (section 5.3) and
  the 2-FF latency of feed is covered by the 16-cycle guard.

### 5.5 MFM encoder and CRC (`physical_1581_mfm_encoder.vhd`)

Input: byte `d(7..0)`, flag `sync` (A1 or C2 with the missing clock), the previous data bit
`p` carried across bytes (and reset to `0` at session start). Output: the 16-bit channel word
`c7 d7 c6 d6 … c0 d0` with `c_i = not d_(i+1) and not d_i` (`d_8 = p`). Sync words are constants:
`A1` with missing clock = `0x4489`, `C2` with missing clock = `0x5224`; after a sync word `p` is the
sync byte's bit 0 (`1` for A1, `0` for C2). The word enters the writer's small same-clock FIFO
(depth 4, push when level ≤ 1, the AExp admission rule); the writer serializes MSB first.

As implemented (M1a): `mark_i` is `ENC_MARK_NONE/_A1/_C2` (code `11` reserved), `byte_i` is ignored
for a mark and the CRC is fed the mark's own value; `start_i` resets the carried bit and the CRC;
`crc_reset_i` presets the CRC *before* feeding the strobed byte; `word_valid_o` follows `valid_i`
by one cycle; `ready_o` is low for the CRC entity's 10-cycle serial window after a CRC strobe
(irrelevant at the 1600-cycle byte cadence, asserted in simulation); the CRC bytes are emitted as
two plain strobes of `crc_o(15 downto 8)` and `crc_o(7 downto 0)` with `crc_feed_i = '0'`.

CRC: a second instance of `physical_1581_crc` (CRC-16/CCITT-FALSE, init `FFFF`). Write Sector:
reset at idx 12, fed A1 A1 A1 DAM data[512]; the state after the three A1 bytes is `0xCDB4` (the
package's sanity anchor). Write Track: reset to `FFFF` on an `F5` whose predecessor was not `F5`,
fed every A1 of the run, then everything up to the `F7`; `F7` emits the high byte first.
`F5`/`F6`/`F7` are tokens only in Write Track; in Write Sector they are data. Clock bits carry
across every byte boundary (the AExp encoder lesson: a missing clock cell is fatal on media and
invisible in simulation unless the flux model is decoded independently).

### 5.6 The writer (`physical_1581_writer.vhd`, port of `physical_fdd_writer.vhd`)

Kept verbatim: 100-cycle cell at 50 MHz; MSB-first 16-bit shift register with FWFT reload from the
word FIFO; one active-low WDATA pulse of 25 cycles (500 ns, the middle of the mechanism's
0.2–1.1 µs window) launched at cycle 50 of the cell (± precomp); registered outputs, single
driver, reset `'1'`; the 7-bit precomp window (bit 3 is the written bit; short-before/long-after →
early, mirror → late, symmetric or invalid MFM → none, boundary bits unshifted); magnitude 7
cycles = 140 ns; WGATE defined at the output stage; the ARM → STREAM live re-check; the abort
latch; underrun detection at the cell boundary; the tab qualifier (section 6.2); the diag taps.

Changed: the "episode" is the controller's `session_i` level (same clock domain, no synchronizer):
it is the *episode*, not a gate term — the words pushed before it falls still reach the disk
(tail), and `busy_o` falls about three cells after WGATE rises; `abort_i` is the controller's
abort and acts in the clock that sees it; the gate terms are `en_i`, `mot_i` and `media_ready_i`
(the mechanism is permanently selected while the controller is enabled, and the 1581 DOS cannot
touch SIDE or the motor while the WD is busy — no drain hold is needed because completion is
defined after the tail); a side change mid-session aborts (side latched at the bind); AExp's
`v_hold` logic is deleted; `wprot_i`/`change_i` carry the positive polarity of
`physical_1581_inputs`; `precomp_i` is sampled at the bind; a new 1-cycle `cut_i` (Write Track end
at the index) truncates at the next cell boundary, dropping the output stage, the shifter and the
buffered words, and completes the session as "cut" (flag bit 4) rather than aborted; the word
source is a same-clock 4-deep first-word-fall-through FIFO inside the writer (`word_i`,
`word_push_i`, `word_full_o`, `word_level_o`): push only while `word_level_o <= 1` counting a push
in flight, streaming starts once two words are buffered, idle pushes and pushes while full are
refused and counted (`d_pushfull_o`, must stay 0); `session_i` may rise only while `busy_o = '0'`;
zero lead-in/lead-out stays — the controller supplies the 12 × `00` run-up and the trailing `FF`
as data, exactly as the chip does. Diag taps: `d_gate_cyc_o` (32-bit), `d_words_last_o`,
`d_underrun_o`, `d_discard_o`, `d_gateopen_o`, `d_abort_o`, `d_precnt_o`, `d_pushfull_o`,
`d_reason_o`, `d_reason_acc_o` (OR-accumulated), `d_flags_o` (completed, aborted, discarded,
underrun, cut). Generics `G_WPROT_QUAL_CYC`, `G_SEL_SETTLE_CYC` for simulation acceleration.
Flux positions: channel bit k of a session falls at G + 100k + 50 (± 7 with precomp), where G is
the gate-open cycle; the WGATE window is exactly N × 1600 cycles for N words that end normally
(849,600 for a sector); a session ended by `cut_i` is one clock short of a cell multiple (the gate
opens one clock after a cell boundary and the cut closes it in the boundary clock: 9,999,499 cycles
for the model's 10,000,000-cycle revolution).

### 5.7 Timing constants (50 MHz cycles; generics with simulation overrides)

| Constant | Value | Source |
|---|---|---|
| cell | 100 (2.000 µs) | DD MFM, AExp-measured |
| byte time | 1600 (32.000 µs) | 16 cells |
| WDATA pulse | 25 (500 ns) at cell cycle 50 | AExp, mechanism window 0.2–1.1 µs |
| precomp | 7 (140 ns) | AExp flux measurement vs real A500; WD1772 nominal ≈125 ns |
| `G_WR_GAP_CYC` = 22 × 1600 − `C_WR_GAP_CAL_CYC` (488) = 34,712 | counted from the ID match; the calibration is −27 cycles of decoder latency (the ID CRC's last cell → `id_valid`, measured in W1; negative because the decoder resolves a final `1` at its own flux edge, before the cell ends) plus 515 cycles of write pipeline (match register, session register, encoder start, two admission-paced pushes, ARM → STREAM, five cells to the output stage); result: WGATE opens exactly 22 byte-times after the ID CRC's last cell in W1 and within 35,099–35,299 cycles over 15 sector windows (the decoder latency moves by about one cell with the bits around the CRC end; ±1 byte-time is the tolerance) | WD1772 datasheet; issue #248 `WR_FIRST_GRACE`; measured in M1b |
| `G_WR_TRK_START_WD` | 15,000,000 (300 ms) | spec 11.2 |
| `G_WR_TRK_END_WD` | 13,000,000 (260 ms) from the start edge | spec 11.2 |
| `G_WR_GUARD_CYC` | 35,000 (700 µs): no STEP accepted after WGATE deassertion | spec 11.2 (cheap, keeps the head still while the write current decays) |
| tab qualifier | 10 ms cumulative selected time, 50 µs settle after a select edge, 4-sample (80 ns) revoke | AExp 3.3 |
| `PHYS_T1_MIN_TICKS` (WD side, 8 MHz ticks) | 12,000 (1.5 ms) minimum BUSY for every immediate termination (WP, not ready), reused from the Type-I rule | section 4.1: a 4-cycle BUSY hangs the ROM |
| index floor | 10,000 (200 µs), unchanged | `physical_1581_inputs.vhd` |

---

## 6. Safety discipline (what replaces the normative spec's firewall)

### 6.1 WGATE conjunction (evaluated every 50 MHz cycle, registered)

```
f_wgate_o = '0' (asserted) only while ALL of:
   en               (controller enabled: physical mode on this drive, capable, drive out of reset)
   motor_s          (CIA motor request on)
   media_ready      (index-qualified spinning medium)
   wr_ok            (tab qualified writable, section 6.2)
   writer STREAM    (entered from the session's rise after the ARM live re-check; it lasts until the
                     words pushed before the session's fall have left the output stage — the tail)
   not abort_lat, no abort term and no cut in this clock
   output-stage bit valid (the window's middle slot carries a real word bit)
```

WDATA pulses are additionally gated by WGATE (`gate_r`); outside WGATE WDATA is `'1'`. Both pins
are `'1'` after reset, while disabled, in image mode and on every board that does not route them.

### 6.2 Write-protect: five readings, one truth

1. The raw pin, 2-FF synchronized (`physical_1581_inputs`, exists).
2. `wprot_c` → CIA PB6 and WD status bit 6 for Type I (exists).
3. `wr_ok` (writer): set after 10 ms of cumulative *selected and settled* time reading writable;
   cleared by a 4-sample protected level, by a disk-change assert edge, by reset. The disk-change
   clear matters: a swapped disk starts unqualified and must prove itself again.
4. The command pre-check in the WD front end (`phys_wprot_c`) → `RES_WRITE_PROTECTED` without a
   request.
5. The controller's `WR_WAIT` check (`wprot_c`) and the live abort term (section 6.3). The disk-change
   *latch* is not a write gate (a swapped disk is caught by the qualifier reset in 3 and by the DOS's
   own PA7 handling); the live change *edge* is an abort term.

A protected disk is therefore refused four times before the gate, and a tab change *during* a write
closes the gate within 80 ns + one cell.

### 6.3 Abort terms and their effect

| Term | Effect on WGATE | Result to the WD | Counted in |
|---|---|---|---|
| Force Interrupt (cancel edge) → controller `abort_i` | immediate (the clock that sees it) | `RES_CANCELLED` | CNT_WR_ABORT, reason 0x80 |
| disk change (`change_c`, 4-sample edge in the writer) | within 4 samples | `RES_DISK_CHANGED` + rnf | reason 0x08 |
| write protect asserted (4-sample level) | within 4 samples | `RES_WRITE_PROTECTED` | reason 0x04 |
| motor request off / enable off / media_ready lost / QNICE reset / drive reset (`phys_active` falls) | immediate | `RES_CANCELLED` (or none when the WD is gone) | reason 0x02 |
| side change mid-op (latched at the bind) | immediate | `RES_CANCELLED` | reason 0x20 |
| index loss (track watchdogs in the controller) → `abort_i` | immediate | `RES_NO_INDEX` + rnf | reason 0x80 + the controller's own counter |
| word-FIFO underrun (structurally unreachable, same clock) | at the cell boundary, latched | `RES_INTERNAL_FAULT` | CNT_WR_UNDERRUN, reason 0x40 |

A torn sector/track is what a real 1581 leaves after the same event; the DOS's verify or the next
read finds it. No automatic repair.

### 6.4 Reads during and after writes

The MFM decoder is held in reset (`dec_rst`) from `session` rise until the writer's busy falls
(gate + tail), the AExp `chain_rst` rule: RDATA is meaningless while the head writes, and the
read instruments must not count it. After the tail the decoder re-syncs on the next preamble —
for the DOS's back-to-back sector writes the next ID is ~1.5 ms away, which is dozens of A1
trains' worth of margin.

### 6.5 Mechanics guard

After WGATE deasserts (however the op ended), `SI_IDLE` **defers** any step until `G_WR_GUARD_CYC`
(700 µs) has elapsed; a step toggle that arrives inside the guard is served when it expires, never
lost (a lost toggle would leave the WD waiting for its ack forever). The DOS cannot issue a Type I
command before the WD reports done anyway; the guard is insurance for the Force-Interrupt-then-Seek
sequence.

---

## 7. Reset, cancel and switch behaviour

| Event | Controller | WD front end | Media outcome |
|---|---|---|---|
| C64 soft/hard reset (drive resets, `phys_active` falls) | `en = '0'` branch: WGATE closed, write FSM idle, no done; the write FIFO is drained in every state that does not consume it, the disabled state included, so it is empty when the drive is re-enabled | `floppy_reset` clears the engine; request toggles keep their value (phantom-edge rule) | sector/track torn, as on a real 1581 reset mid-write |
| Force Interrupt while busy | the cancel toggle flips twice (`cmd_rx` spans two execute ticks, pre-existing): abort on the first edge, ignore a cancel edge with no op active | existing path | torn sector, as on a real chip |
| QNICE reset (always with a core reset in M2M) | full reset; both FIFO sides reset from the same event | same | same |
| Source switch away from Internal 1581 | blocked by the idle gate while motor on / write FSM active (section 9.2) | — | none |
| Drive steal (Internal 1581 moves 8 ↔ 9) | the 255-cycle all-zero gap in `main.vhd` passes through `en = '0'` → write aborted if any | — | none (gate blocks it while busy) |
| OSM open / core pause | the controller never pauses (50 MHz domain is free-running) | the drive CPU keeps running in physical mode (`physical_drive_must_run` semantics already in place for reads) | none |
| Eject mid-write | `change_c` abort | `RES_DISK_CHANGED` + rnf | torn sector (the disk is physically leaving anyway); the DOS retries the flush up to three times and, once its readiness step pair has cleared the latch on a newly inserted disk, writes the stale side onto that disk — genuine 1581 behaviour (section 4.5) |

---

## 8. Diagnostic device: map v8

`physical_1581_diag.vhd`: `C_MAP_VERSION` → `x"08"`, capability bit 0 (read-only) cleared, new
words from `0x80` (everything below is allocated; the trace ring `0x40–0x7F` stays). All counters
cumulative since QNICE reset (AExp trap D.1: per-episode-only registers describe the last episode
and hid a per-cylinder defect); the "last op" words are additional.

| Word | Name | Content |
|---|---|---|
| 0x80 | WR_STATE | write FSM phase code (4 bits), writer state (3 bits), `wr_ok`, `session`, `feed`, `precomp active`, gate level, wdata level |
| 0x81 | WR_LAST | {15:8 flags: completed, lost, aborted, wp-refused, first-byte-abort, track-op, deleted, precomp} {7:0 reason bitmask of the last abort} |
| 0x82 | WR_LAST_CHR | {7:0 C} {15:8 R} of the last sector op; H in WR_STATE spare bits |
| 0x83/0x84 | WR_GATE_CYC lo/hi | WGATE window of the last op in cycles (sector: 531 × 1600 = 849,600 ± 100) |
| 0x85 | WR_BYTES_LAST | bytes/tokens consumed in the last op (sector: 512; track: the DOS's token count, ≈ 6,122 − 20 F7 double-slots) |
| 0x86/0x87 | CNT_WR_SECT lo/hi | sector write ops accepted |
| 0x88/0x89 | CNT_WR_TRACK lo/hi | track write ops accepted |
| 0x8A/0x8B | CNT_WR_GATE lo/hi | ops in which WGATE opened |
| 0x8C/0x8D | CNT_WR_LOST lo/hi | ops that set LOST DATA (first-byte aborts + mid-op underruns) |
| 0x8E/0x8F | CNT_WR_WP lo/hi | write-protect refusals (pre-check + WR_WAIT + live abort) |
| 0x90/0x91 | CNT_WR_ABORT lo/hi | aborted ops (all reasons) |
| 0x92 | WR_REASON_ACC | OR-accumulated abort reasons since reset |
| 0x93 | CNT_WR_FIFO_OVF | pushes refused by a full write FIFO (must stay 0) |
| 0x94 | CNT_WR_UNDERRUN | writer word underruns (must stay 0) |
| 0x95 | WR_PRECOMP_CNT | precompensated pulses, last op |
| 0x96 | WR_FIRST_MARGIN | minimum observed first-byte margin: byte-times left of the 22 when the first byte arrived (the issue-#248 instrument, this time for the physical path) |
| 0x97 | WR_DRQ_MARGIN | minimum FIFO level seen at a pop during the last op (0 = an underrun happened, 1 = one byte of slack …) |
| 0x98/0x99 | WR_TRK_CYC lo/hi | index-to-index cycles of the last track write (≈ 9,990,000 at 300.3 RPM) |
| 0x9A | WR_CTRL | **the only writable word**: {1:0 precomp mode 0 = follow P, 1 = off, 2 = on} — the one place a tester can experiment without a rebuild |
| 0x9B | CNT_WR_FIN | (M3 extension) the WD's finalize toggle counted: one per write op the WD completed (short by one per op cut by a Force Interrupt or a drive reset) |
| 0x9C | WR_PUSHFULL | (M3 extension) the writer's refused-push counter, must stay 0 |
| 0x9D | WR_DISCARD | (M3 extension) the writer's discarded sessions, must stay 0 |

Sources as implemented (M1b): the controller exposes `diag_wr_phase_o` (0 idle, 1 wait, 2 search, 3 gap,
4 stream, 5 tail, 6 abort, 7 track-arm, 8 track-stream), `diag_wr_session_o`, `_feed_o`, `_abort_o`,
`_prec_o`, `_gate_o`, a one-cycle `diag_wr_done_o` with `diag_wr_last_o` (completed, lost, aborted, wp,
first-byte-abort, track, deleted, precomp), `diag_wr_bytes_o`, `diag_wr_first_margin_o`,
`diag_wr_trk_cyc_o`, the writer taps `diag_wr_gate_cyc_o`, `_words_last_o`, `_underrun_o`, `_discard_o`,
`_gateopen_o`, `_wabort_o`, `_precnt_o`, `_pushfull_o`, `_reason_o`, `_reason_acc_o`, `_wflags_o`, plus
`wr_ok_o`; the WD side adds the toggles `phys_dbg_wr_fin_tgl`, `_wp_tgl`, `_drop_tgl`; `WR_DRQ_MARGIN`
comes from the wfifo's `rd_level_o` sampled at each `wbyte_rd_o` in `main.vhd` or the diag; `WR_CTRL`
drives `wr_precomp_mode_i`. The counters of the table are accumulated in the diag from these strobes.

Trace ring: every accepted write op records REQUEST (op, C, R, side) and RESULT (code, flags)
entries like reads do, so the DOS's write-back order (sector under head + 1 … wrap) becomes visible
in a dump. `doc/1581_dd_debug_device.md` gains the v8 table and a "healthy write session"
balance (corrected in M3: WD pre-check refusals never become ops, and aborts after the gate opened
still count a gate): `CNT_WR_GATE = CNT_WR_FIN = CNT_WR_SECT + CNT_WR_TRACK`, `CNT_WR_LOST = 0`,
`CNT_WR_WP = 0`, `CNT_WR_ABORT = 0`, `CNT_WR_UNDERRUN = 0`, `WR_PUSHFULL = 0`, `WR_DISCARD = 0`,
`WR_GATE_CYC = 849,600 ± 100` after a sector, `WR_FIRST_MARGIN ≥ 18`. `CNT_WR_FIFO_OVF` counts every
dropped data-register write, which includes the DOS's trailing `4E` tokens after a Write Track's
index: it is not 0 after a format and is a counter, not an alarm (a real push into a full FIFO is
impossible by construction). As implemented, WR_STATE packs {3:0 write phase, 6:4 writer state
derived from busy/flags/gate, 7 wr_ok, 8 session, 9 feed, 10 precomp, 11 WGATE, 12 WDATA, 13 found H,
14 abort level}; WR_LAST_CHR carries the requested R and C; the read-path counters and latches
(READOP, RNF, CRCERR, CANCEL, LAST_RESULT, CHRN, RNF_CTX) count read ops only since v8, because
reads and writes share the done channel; the trace ring records write REQUEST/RESULT entries through
the existing taps.

---

## 9. Shell, OSM and the idle gate

### 9.1 Status line

`P1581_CLASSIFY` (`CORE/m2m-rom/m2m-rom.asm`) gains two states ahead of `READING`: `WRITING`
(sector op) and `FORMAT` (track op). As implemented (M3): `RM_CTRL_STATE` (diag word 0x04) has no
spare bits, so while a write op is active or the writer is still busy its bits 15:12 carry a write
code instead of the read phase — bit 15 set, bit 14 = Write Track, bits 13:12 = coarse phase (00
wait, 01 search/gap/track-arm, 10 stream, 11 tail/abort/busy) — so 0x8xxx–0xBxxx reads Writing and
0xCxxx–0xFxxx Format from the one word the Shell already reads; the full phase is in WR_STATE. New
23-character labels: `8:Internal 1581 Writing`, `8:Internal 1581 Format `, same for 9; +116 ROM
words. No other menu change; `OPTM_SIZE` unchanged; the config file name follows `CORE_VERSION`.

### 9.2 Idle gate

`P1581_BUSY_MASK` keeps its value (0xFC08: bits 15:10 and 3), which already covers the write code
of 9.1. Beyond that, nothing: the physical "busy" word
already includes *motor on*, and the stock DOS flushes its dirty side cache on its idle timer
(320 ms after the last ATN by default) while it keeps the motor running for ≈ 10 s after the last
job (section 4.3), so "motor off" implies "cache flushed" for the stock ROM with a margin of
seconds. (JiffyDOS 1581: to be confirmed in the community phase; worst case a
mode switch within the motor-off window after a JiffyDOS save loses the last side — the same loss a
real 1581 suffers when powered off in that window.) The normative spec's `$0087` snooping is not
built.

### 9.3 User documentation

`README.md` / `FAQ.md` / c64.mega65.org: the AExp "Writing: the one thing to be careful about"
section adapted — the tab is the only guard, originals stay protected, blanks for writing, DD
only, the drive's own controller sometimes powers up knocking (power-cycle), what `26, WRITE
PROTECT ON` and `25, WRITE ERROR` mean on the physical drive, and the recipes of the plan.
`doc/models.md` records the write qualification per board.

---

## 10. Verification (sim first; no hardware write before 10.1–10.3 are green)

### 10.1 GHDL closed loop with a writable disk (`CORE/vhdl/test/tb_physical_1581_controller/`)

* `mech_model_1581.vhd` gets `f_wgate_i`/`f_wdata_i` and a **live rotating flux store** per
  (cylinder, side): one slot per 50 cycles holding an edge timestamp, erased at cycle granularity
  while WGATE is low, written on each WDATA falling edge, played back as RDATA from whatever it
  holds (the AExp `p_disk` process, ported). Pre-seeded from `golden_1581_pkg` (today's
  procedural generator lays the track into the store once instead of regenerating it per
  revolution). Pulse-width census (min/max of every WDATA low) and an "edge outside WGATE" fatal
  assert.
* An **independent twin** (`CORE/vhdl/test/tb_physical_1581_controller/wr_twin.py`, port of
  `td_write_check.py`): from the byte stream and the serialization rules it predicts the edge list
  (with precomp direction from mega65-core's wall-clock table) and compares with the model's dump
  ± 1 cycle; and an independent quantiser/decoder over the model's flux that reconstructs bytes
  and CRCs without the DUT's decoder.
* Scenarios (each writes into a store pre-seeded with a *different* payload and asserts that the
  old flux is gone from the written span and that WGATE opened):
  * W1 one Write Sector, then Read Sector of the same sector through the real decoder: byte-exact,
    data CRC ok; WGATE window 849,600 ± 100 cycles; splice at 22 ± 1 byte-times after the ID CRC;
    following ID field intact (read it with Read Address).
  * W2 the DOS's side write-back: ten single-sector writes in order k+1 … 10, 1 … k, issued with the
    #248 cadence (next command ~70 µs after done), with a modelled drive-CPU DRQ service latency
    swept over 0 … 30 µs; then Read Sector 1 … 10: all byte-exact; CNT_WR_LOST = 0.
  * W3 Write Track with the genuine ROM's token stream (section 4 fixture, 6,122 byte-times) then
    Read Address × 10 and Read Sector 1 … 10 (both sides); CRCs ok; `WR_TRK_CYC` = one revolution.
  * W4 write protect: tab protected → `RES_WRITE_PROTECTED`, no gate, status bit 6; tab bounce
    during ARM → discard; tab asserted mid-sector → gate closes within 80 ns + one cell.
  * W5 disk change mid-sector → abort, result, the medium shows the truncated write only.
  * W6 Force Interrupt mid-sector / mid-track → closes, `RES_CANCELLED`, next op clean (FIFO empty).
  * W7 drive reset (`phys_active` low) mid-write → gate closed within one cell; re-enable →
    FIFO empty, change latch armed.
  * W8 first byte late (no byte within 22 byte-times) → `RES_LOST_DATA`, WGATE never opened,
    flux untouched.
  * W9 one byte 40 µs late mid-sector → `00` in that slot, LOST DATA set, sector completes, the
    following ID intact, no gate tear.
  * W10 precomp OFF/ON/follow-P: twin-predicted ± 140 ns shifts present/absent; boundary bits
    unshifted.
  * W11 m = 1 two-sector write (stretch).
  * W12 index loss during a track write → watchdog close, `RES_NO_INDEX`.
  * W13 read-only regression: every existing scenario unchanged with the writer instantiated and
    idle; `f_wgate` never leaves `'1'`.
* As built (M1b, `tb_physical_1581_write.vhd` + `run_tb_write.sh` + `wr_twin.py`): `mech_model_1581`
  gained `G_WRITABLE` (default false keeps the procedural generator verbatim so the four old benches end
  at their old timestamps; true = the live store, seeded 32 × `4E`, ten 604-byte records, `4E` to the
  end of the revolution), the WDATA → RDATA echo under WGATE (so an unheld decoder is observable) and
  the fatal "WDATA low while WGATE high" guard. Scenario groups: 1 = W13 on the store + W1 + W10 (four
  precomp modes), 2 = W2 at 0 / 15 / 30 µs, 3 = W4a/W4b + W5 (+ W5b: a write without a step after a
  swap succeeds) + W6, 4 = W7 + W8 + W9, 5 = W3 + W12. Not built: the W4 tab bounce inside ARM (a
  few-clock window; the discard mapping exists), W11 (m = 1 is a WD-side re-issue of ordinary ops, so
  the controller needs nothing). Measured: gate closes 7 cycles after a tab or change assert, 4 after
  a cancel, 3 after a drive reset; W3 consumes 6,232 tokens over one model revolution.
* **Mutant matrix** (pre-registered; each must turn a named scenario red). Run in M1b as HDL mutants:
  (v) 20 and 24 byte-times, (vii), (x), (xii), (xiii) (green at first because the model muted RDATA
  under WGATE — a checker defect, fixed by the echo), plus "abort_i never raised"; (viii) and (ix) are
  covered by the M1a writer mutants (15 of 16 killed, the survivor equivalent); (i)–(iv), (vi), (xi),
  (xiv) as twin-level red controls in `wr_twin.py --selftest` and the flipped-precomp red control: (i) LSB-first words,
  (ii) clock bit rule without the carried previous bit, (iii) plain `A1` instead of `0x4489`,
  (iv) CRC not preset at the sync run / `F5` resets on every token, (v) splice 20 or 24 bytes,
  (vi) WGATE one cell short / one cell long, (vii) pop one slot late (the #248 shift), (viii) WP
  gate term removed, (ix) abort latch removed, (x) index close removed (writes across the index),
  (xi) precomp sign inverted, (xii) FIFO drain at op end removed, (xiii) decoder not held in
  reset during the write, (xiv) 99/101-cycle cell. A mutant that stays green is a checker defect.

### 10.2 iverilog, `tb_fdc1772_physical.sv`

Implemented in M2 (branch `write-m2`): groups 14–24 of `tb_fdc1772_physical.sv` — Write Sector with
the ROM's polling idiom (`$CBF4` wait-busy-set, per-byte DRQ wait) at 16-clkcpu bus cycles; FIFO-room
DRQ (never more than the FIFO depth ahead, never DRQ while full); first-byte abort; LOST DATA sticky;
WP pre-check with the visible minimum busy; Force Interrupt; busy outlives the writer busy; a non-FI
command during a write ignored; m = 1 re-issue; Write Track token flow with the `F7` double slot as a
pop pause; continuous monitors (CRC and RNF never together, no DRQ without feed, no push while full,
zero idle residue). The mock backend models the controller's write engine with the `WR_TAIL` order
of 5.3. The **image-mode golden trace** `tb_fdc1772_image_golden.sv` runs the real `floppy.v` (declarations
reordered for iverilog by `tb_floppy_iverilog.py`) with D81 geometry through a SAVE-like sequence and
logs every register access, SD request and DRQ/INTRQ edge; the recorded transcript
`tb_fdc1772_image_golden.txt` must stay byte-identical, also with random activity on every new input
(`+wrnoise`); an image-path mutant (one extra DRQ) is caught. The issue-#248 `sim_fdc` bench is not
in the repository; the golden bench is the image-mode regression instrument.

### 10.3 Genuine ROM in the loop (`doc/dev-fdd/rom_emu`)

Done in M2: `doc/dev-fdd/rom_emu/wd_write_model.py` models the front end of 5.1 (4-deep FIFO-room DRQ,
the 22-byte first-byte rule, `00` slots with sticky LOST DATA, WP pre-check with the minimum busy,
completion after the writer tail, status purity) and `run_write_proofs.py` (19 proofs, must end with
`RESULT: ALL WRITE PROOFS PASS`) runs the ROM's own `SAVE` flush and `N0:` format: the transcripts are
the fixtures `fixtures/write_back_order.json` and `fixtures/format_tokens.bin` + `.json` (section 4), and
the "ROM observes LOST DATA / WP / RNF" paths are proven against the real error table (LOST DATA takes
the `$CD53` stack path whose RTS misreturns into `$87B8`; WP → three attempts then `26, WRITE PROTECT ON`;
RNF → `20,READ ERROR`). `run_proofs.py` is unchanged (16 proofs).

### 10.4 Static gates

`ghdl -s` + full suite; the differential `ghdl -a` analysis of `main.vhd`, `mega65.vhd` and the four
tops against the previous commit (zero new diagnostics; done in M3 with an `xpm` stub so that
`mega65.vhd` and the `MEGA65_Core` instances are port-checked); a mechanical cross-check of the
`iec_drive` port map against `iec_drive.sv` (86 of 86 ports; ghdl cannot see SystemVerilog);
`menu_test.py verify` (unchanged menu); Shell ROM build (27,182 of 28,672 words); Vivado synthesis
on R3 and R6 with WNS ≥ 0 — expect no BRAM change and, because the writer, encoder and write engine
were unconnected and trimmed before M3, on the order of +1,000–1,500 LUTs and +600–800 FFs in the
qnice domain (the diag alone about 600 LUTs): check R3's margin; `report_cdc` clean under the
existing clock-pair cut (the wfifo Gray pointers, the three toggle pairs and the feed/lost/busy
2-FFs carry `async_reg`; deleted/precomp are quasi-static with the request toggle).

---

## 11. Hardware and community gates

### 11.1 Bench (maintainer, R3 first, then R6)

Pre-registered in the plan (`WRITE-PLAN.md` section 5): read regression first (the A18X2 read
recipes), then on NOS DD blanks: single `SAVE`/`LOAD`, directory, `VALIDATE`; the diag balance of
section 8 after every step; paich64's `SAV-WRITE` against the physical drive; `N0:` format then
the same again; eject and tab tests on sacrificial disks; power-cycle persistence.

### 11.2 Referee (independent reader of a core-written disk — at least one)

1. The MEGA65's own core: `DIR` and `DLOAD` of the disk from the internal drive in C65 mode (an
   F011 MFM decoder and the C65 DOS, both independent of this project).
2. A real Commodore 1581 (community; the issue-#90 reporter uses real CMD/1581 hardware).
3. A Greaseweazle `commodore.1581` decode compared byte-exactly with the source D81 (community;
   the AExp tester owns one).

### 11.3 Community (Discord, with the recipes of the plan)

Stock DOS and JiffyDOS; GEOS on a real disk; D81 ↔ real-disk copies with the common C64 1581
copiers; the SAV-WRITE stress on R3/R3A and R6; "reads still fine" regression on genuine 1581
disks.

---

## 12. Open points (decisions for the maintainer; recommendations in the plan)

1. OSM write switch: none (recommended, AExp precedent) or a "writes: Allowed/Blocked" item.
2. Precomp default follow-P at 140 ns (recommended: bit-faithful to a real 1581, which precompensates
   cylinders 1–43 only) vs always on / inner-only / off.
3. m = 1 support: implemented in M2.
4. Version/bookkeeping: `WIP-V6-A21` as the write alpha (the read-only milestone was `A18X1`).
5. Interim guard for the fake-finish hazard (section 5.1): folded into M2 (every write issue and the
   WP pre-check arm the minimum busy); no separate build.
