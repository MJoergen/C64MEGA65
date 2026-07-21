# DD-MFM Read Decoder + CRC — Adaptation Plan

Source: MEGA65 `mega65-core` @ `a9158930665763c592d004c895d52eff4a9eefc3`, all under `src/vhdl/`.
Target: `CORE/vhdl/physical_1581/` (50 MHz, read-only, DD-only, MFM-only).
All upstream files run on one rising edge of a port literally named `clock40mhz` (actual MEGA65 pixelclock ~40.5 MHz). Everything below is clocked on that single edge with clock-enable-style strobes.

---

## 1. CRC — `crc1581.vhdl` → `physical_1581_crc.vhd`

**Entity port list (verbatim):**

```
generic ( id : integer := 0 );                 -- report-message tag only; DROP
clock40mhz : in  std_logic;
crc_byte   : in  unsigned(7 downto 0);
crc_feed   : in  std_logic;
crc_reset  : in  std_logic;
crc_ready  : out std_logic        := '1';
crc_value  : out unsigned(15 downto 0) := x"FFFF";
```

**Algorithm / parameters (confirmed):** CRC-16/CCITT-FALSE.
- Polynomial `0x1021` (`x^16 + x^12 + x^5 + 1`). Taps in RTL: shift `value(15:1) <= value(14:0)`, then `value(0) <= fb`, `value(5) <= value(4) xor fb`, `value(12) <= value(11) xor fb`, where `fb = byte(7) xor value(15)`. The C65-DOS comment (`EOR #$21` low / `EOR #$10` high) = bits 0,5,12 → same poly.
- Init/preset `0xFFFF` (constant `crc_init`).
- **MSB-first** byte order: `byte(7)` is fed first; `byte` shifts left one bit/clock, 8 clocks/byte (`bits_left`), so `crc_ready` drops for 8 cycles per byte.
- No input/output reflection, no final XOR. "CRC good" is tested as `crc_value = 0x0000` (the two stored CRC bytes are themselves fed MSB-first, driving the register to zero).

**Reset/preset behavior:** `crc_reset='1'` → `value<=0xFFFF`, `ready<='1'`, and clears the buffered byte **unless** `crc_feed` is asserted the same cycle (fix #442, `byte_buffered <= crc_feed`) — lets the decoder reset-and-feed the first `A1` in one cycle.

**How it is driven for ID vs data (in the decoder):** identical engine, reset once per field. On the first of the three `A1` syncs (`sync_count=0`) `crc_reset` pulses; each `A1` sync then `crc_feed`s `0xA1`; the mark byte (`FE`/`FB`) and every field byte plus the two stored CRC bytes are fed. There is no separate ID vs data CRC instance — only one `crc0`; the distinction is purely which state fed it. For our port we should **expose header-CRC vs data-CRC as separate result flags** (see §6).

**Verified preset after `A1 A1 A1` = `0xCDB4`** (both a reference CRC-CCITT and a bit-exact emulation of the RTL taps produce `0xCDB4`; `+FE → 0xB230`, `+FB → 0xE295`). Use `0xCDB4` as the sanity constant in the testbench.

---

## 2. Read pipeline stages

Chain inside `mfm_decoder`:
`mfm_gaps → mfm_quantise_gaps → mfm_gaps_to_bits → mfm_bits_to_bytes → (state machine) → crc1581`.
All entities clock on `clock40mhz`.

**`mfm_gaps.vhdl`** — flux edges → gap interval.
Ports: `clock40mhz`; `f_rdata: in`; `packed_rdata: out slv(7:0)` (debug); `gap_valid: out`; `gap_length: out u(15:0)`; `gap_count: out u(3:0)` (rolling pulse counter, debug).
Algorithm: free-running `counter` increments each clock; on a falling edge of RDATA (`last_rdata='0' and last_last_rdata='1'` = start of a flux pulse) it emits `gap_length=counter`, pulses `gap_valid`, and clears `counter`. `packed_rdata`/`gap_count` are debug only.

**`mfm_quantise_gaps.vhdl`** — interval → 2-bit gap class.
Ports: `clock40mhz`; `cycles_per_interval: in u(7:0)`; `gap_valid_in`, `gap_length_in: in u(15:0)`; `gap_valid_out`, `gap_size_out: out u(1:0)`.
Algorithm: `cycles_per_interval` (`cpi`) is cycles per **half** bit-cell (comment: "effectively double … set to 1/2 the expected value"). Thresholds each clock: `t10_low=cpi`, `t10_high=2.5·cpi`, `t15_high=4·cpi−0.5·cpi=3.5·cpi`, `t20_high=4·cpi+cpi=5·cpi`. Classify: `<cpi → "11"` invalid-short; `≤2.5cpi → "00"` (1.0); `≤3.5cpi → "01"` (1.5); `≤5cpi → "10"` (2.0); else `"11"` invalid-long. So `1.0`=2·cpi, `1.5`=3·cpi, `2.0`=4·cpi in real cycles; boundaries are midpoints. (These are looser than the spec's characterization windows — see §4.)

**`mfm_gaps_to_bits.vhdl`** — gap class → data-bit stream + sync.
Ports: `clock40mhz`; `gap_valid`, `gap_size: in u(1:0)`; `bit_valid`, `bit_out: out`; `sync_out: out`.
Algorithm: state = `last_bit & gap_size`; emits decoded data bit(s): `{last0,1.0}→0`, `{last1,1.0}→1`, `{last0,1.5}→1`, `{last1,1.5}→00`, `{last0|1,2.0}→01`. Queues 1–2 bits per gap. Sync detection: keeps the last four quantised gaps in `recent_gaps`; a match to `sync_gaps="10011001"` (= `2.0,1.5,2.0,1.5`, i.e. the missing-clock `A1`, raw `0x4489`) pulses `sync_out`, flushes the bit queue, and forces `last_bit<='1'` (`A1` ends in a 1). Only data bits reach the output; clock bits are implicit.

**`mfm_bits_to_bytes.vhdl`** — bit stream → byte framing.
Ports: `clock40mhz`; `sync_in`, `bit_in`, `bit_valid: in`; `sync_out: out`; `byte_out: out u(7:0)`; `byte_valid: out`.
Algorithm: on `sync_in` emit `byte_out=0xA1` + `sync_out`, reset the bit counter (byte boundary re-aligns to sync). Otherwise shift `bit_in` MSB-first into `partial_byte`; on the 8th bit emit `byte_out` + `byte_valid`.

**`mfm_decoder.vhdl`** (top) — sync/mark detection + CHRN parse.
Generic `unit_id`. Instantiates the four stages above + the RLL pair + `crc1581`. State machine `MFMState`: `WaitingForSync → {FE: TrackNumber→SideNumber→SectorNumber→SizeNumber→HeaderCRC1→HeaderCRC2→CheckCRC}` for the **ID field**, or `{FB: SectorData→DataCRC1→DataCRC2→CheckCRC}` for the **data field**. Note the on-disk ID order is **Track, Side, Sector, Size** = C,H,R,N (`seen_track/seen_side/seen_sector/seen_size`). Sector length from `seen_size`: `0→128,1→256,2→512,3→1024,4→2048, else 512`. `CheckCRC` waits for `crc_wait` to drain + `crc_ready`, then `crc_value=0 → good` else `crc_error<='1'`. Read data leaves via `byte_out/byte_valid/first_byte`, end via `sector_end`.

---

## 3. Missing-clock sync detection

- **`A1` (raw `0x4489`)** is the ONLY sync recognized, in `mfm_gaps_to_bits`: the four most-recent quantised gaps equal `sync_gaps="10011001"` (`2.0,1.5,2.0,1.5`). That gap sequence is exactly the MFM encoding of `A1` with the omitted clock transition, which reads on the wire as `0x4489`. On match: `sync_out` pulse, queue flush, `last_bit='1'`.
- **`C2` (raw `0x5224`) is NOT implemented.** Upstream never detects the `C2`/IAM (`FC`) index sync because sector reads don't need the index address mark. If we ever wanted it, it would be a second `recent_gaps` constant; **for our read-only sector path we do not need `C2`** — note and skip.
- **`FE`/`FB` gated behind exactly three `A1`:** `sync_count` increments on each `sync_out` (saturating at 3) and is reset to 0 by any `byte_valid_in`. The mark byte is interpreted only in the `sync_count = 3` branch: `FE→` header, `FB→` data, `0x65→` MEGA65 TIB (drop). Thus a mark is honored only as the byte immediately following the third `A1`. **`F8` (deleted-data mark) and `F7` are NOT handled upstream** — we must add `F8` (see §6). (`sync_count=2` is the Amiga branch — drop.)

---

## 4. Timing constants

- **Upstream clock:** port `clock40mhz`, real MEGA65 ~40.5 MHz. `cycles_per_interval` at 40.5 MHz for a 2 µs half-cell = `40.5e6 × 2e-6 = 81 = 0x51`. **This `0x51` is the spec's "do NOT copy" divisor** — it is the 40.5 MHz half-cell count, not ours.
- **Our 50 MHz conversion** (`cycles = 50e6 × t`):
  | Quantity | Time | 50 MHz cycles |
  |---|---|---|
  | MFM half-cell | 2 µs | **100** (`cpi = 0x64`) |
  | 1.0 gap (short) | 4 µs | **200** |
  | 1.5 gap (medium) | 6 µs | **300** |
  | 2.0 gap (long) | 8 µs | **400** |
  So set `cycles_per_interval = 100 (0x64)` at 50 MHz.
- **Upstream midpoint windows** (with `cpi=100`): valid `≥100`; `≤250`→short; `≤350`→medium; `≤500`→long; else invalid.
- **Spec characterization windows** (tighter; use these for our quantiser) at 50 MHz:
  | Class | Spec window | 50 MHz cycles |
  |---|---|---|
  | short | 3.2–4.8 µs | 160–240 |
  | medium | 5.16–6.84 µs | 258–342 |
  | long | 7.1–8.9 µs | 355–445 |
  Recommendation: keep the upstream threshold *structure* but retune the four thresholds to the spec windows (reject gaps in the dead-bands, e.g. `241..257`, rather than snapping them to the nearest class).

---

## 5. What to DROP for a read-only, DD-only, MFM-only path

**Whole subsystems to delete:**
- **RLL** — `rll27_quantise_gaps`, `rll27_gaps_to_bits` instances; signals `rll_bit_valid/_in/_sync_in`, `rll_gap_size_valid`, `rll_gap_size`; the `encoding_mode` combinational mux (keep MFM branch only).
- **Amiga / GCR** — states `AmigaByte1/2/3`, `AmigaDecodeHeader`, `AmigaSkipBytes`, `AmigaSectorData`; signals `amiga_byte_0..3`, `amiga_skip_bytes`; the `sync_count=2` branch. (GCR proper isn't in these files.)
- **MEGA65 Track Information Block (TIB)** — the `0x65` marker path: states `TrackInfo`, `TrackInfoRate`, `TrackInfoEncoding`, `TrackInfoSectorCount`, `TrackInfoCRC1/2`, `TrackInfoCheckCRC`; outputs `track_info_valid/_track/_rate/_encoding/_sectors`.
- **Raw-DMA** — not present in these files (lives in `sdcardio`); nothing to remove here.
- **F011 policy (auto-seek / retry / status)** — the target-matching + autotune logic.
- **debugtools / report / kickstart deps** — `use work.debugtools.all;`, every `report …` statement, and `use Std.TextIO.all;` once reports are gone. (These provide `to_hstring`/`to_hexstring` for sim only.) Also drop the `id`/`unit_id` generics that exist only to tag report strings.

**Specific F011-only entity ports/generics/signals to remove from `mfm_decoder`:**
- generic `unit_id`; port `encoding_mode : in u(3:0)`.
- Debug outs: `mfm_state`, `mfm_last_gap`, `mfm_last_gap_strobe`, `mfm_last_byte`, `mfm_quantised_gap`, `packed_rdata`.
- Seek target ins: `target_track`, `target_sector`, `target_side`, `target_any`.
- TIB outs (5): `track_info_valid/_track/_rate/_encoding/_sectors`.
- Auto-seek outs: `autotune_step`, `autotune_stepdir`.
- Write-gap signaling: `sector_found`, `sector_data_gap` (and the `found_*(7)` "match" high bits that encode target hits).
- `invalidate : in` — repurpose as our synchronous reset/invalidate (see §6) rather than delete.
- **Keep:** `clock40mhz` (rename), `f_rdata`, `cycles_per_interval`, and the data-out set (`first_byte`, `byte_valid`, `byte_out`, `sector_end`, `crc_error`).

---

## 6. Recommended module breakdown — `CORE/vhdl/physical_1581/`

Keep the pipeline sub-stages as **separate entities** (own small files) — minimal diff from upstream = cleanest LGPL provenance and each is independently testable. Two "logical" deliverables per the milestone, realized as:

- **`physical_1581_crc.vhd`** ← `crc1581.vhdl`. Rename `clock40mhz→clk_i`, `crc_*` ports to `_i/_o`; drop generic `id` and all `report`. Keep the exact tap logic (bit-exact CRC-CCITT). Add nothing else — reset already exists (`crc_reset`).
- **`physical_1581_mfm_decoder.vhd`** ← `mfm_decoder.vhdl` (top, MFM-only). Instantiates:
  - `physical_1581_mfm_gaps.vhd` ← `mfm_gaps.vhdl` (drop `packed_rdata`, `gap_count`).
  - `physical_1581_mfm_quantise.vhd` ← `mfm_quantise_gaps.vhdl` (retune thresholds to §4 spec windows).
  - `physical_1581_mfm_gaps_to_bits.vhd` ← `mfm_gaps_to_bits.vhdl`.
  - `physical_1581_mfm_bits_to_bytes.vhd` ← `mfm_bits_to_bytes.vhdl`.
  (Alternatively bundle these four as extra entities inside the one decoder file — VHDL permits it — but separate files diff more cleanly.)
  - `physical_1581_mfm_bits_to_gaps.vhd` ← `mfm_bits_to_gaps.vhdl` — **write path, later milestone**; only the data+clock→`bit_queue` generation (`bit_queue(15..0)` combine block) and interval countdown are relevant. Note write-precompensation table for reuse; do not port now.

**Required additions on every module:** an explicit **synchronous reset / invalidate** input (`rst_i`) that clears all state (gap counter, sync/bit/byte counters, `state<=WaitingForSync`, `crc_reset`) on track change or seek — reuse upstream `invalidate` semantics but make it a clean sync reset.

**Decoder-top additions:**
- **`F8` deleted-data-address-mark recognition:** in the `sync_count=3` branch add `elsif byte_in = x"F8"` → enter `SectorData` exactly like `FB`, but latch a `deleted_o<='1'` flag emitted alongside the sector. (`F8`=deleted, `FB`=normal; `FE`=ID.)
- **Expose C/H/R/N explicitly:** `found_cyl_o = seen_track`, `found_head_o = seen_side`, `found_sec_o = seen_sector`, `found_no_o = seen_size` (with a `header_valid_o` strobe at `HeaderCRC2`/`CheckCRC`).
- **ID-vs-data CRC distinction + stored-vs-calculated:** separate `header_crc_ok_o` (asserted at `CheckCRC` for the `FE` field) and `data_crc_ok_o` (asserted at `CheckCRC` for the `FB`/`F8` field). Optionally also surface the raw **stored** CRC (capture the two `HeaderCRC1/2` and `DataCRC1/2` bytes into a `u(15:0)`) and the **calculated** CRC (`crc_value` before the stored bytes are fed) so the caller/testbench can compare, in addition to the `crc_value=0` pass/fail.

---

## 7. LGPLv3 provenance

**License status of these specific files:** they carry **no per-file header** — each begins directly with `use WORK.ALL;`. They fall under the repo-wide `LICENSE.txt`:

> "Unless otherwise marked, the VHDL source files of the MEGA65 are released under the GNU Lesser General Public License … Version 3, 29 June 2007."

(The full LGPLv3 header seen in e.g. `audio_clock.vhdl` belongs to Adam Barnes' Tyto Project and is **not** the header for our codec files — do not copy that one.)

**Action:** because upstream has no per-file header, we must **add** an LGPLv3 provenance/copyright header to each adapted file, retaining attribution to Paul Gardner-Stephen / the MEGA65 project and citing the pinned commit. Suggested header block (paraphrase of the standard LGPLv3 grant + provenance line), plus this table recorded in-file or in a `PROVENANCE.md`:

| New file | Upstream file (`src/vhdl/`) | Author | Last-touch commit (as of pin) |
|---|---|---|---|
| `physical_1581_crc.vhd` | `crc1581.vhdl` | Paul Gardner-Stephen | `ee961fbe0` (fix #442) |
| `physical_1581_mfm_gaps.vhd` | `mfm_gaps.vhdl` | Paul Gardner-Stephen | `fca44a83e` |
| `physical_1581_mfm_quantise.vhd` | `mfm_quantise_gaps.vhdl` | Paul Gardner-Stephen | `cc0c8d799` (#129) |
| `physical_1581_mfm_gaps_to_bits.vhd` | `mfm_gaps_to_bits.vhdl` | Paul Gardner-Stephen | `851742def` (#230) |
| `physical_1581_mfm_bits_to_bytes.vhd` | `mfm_bits_to_bytes.vhdl` | Paul Gardner-Stephen | `07e0c3f6b` (#442) |
| `physical_1581_mfm_decoder.vhd` | `mfm_decoder.vhdl` | Paul Gardner-Stephen | `8b98b263d` (#736) |
| `physical_1581_mfm_bits_to_gaps.vhd` (write) | `mfm_bits_to_gaps.vhdl` | Paul Gardner-Stephen | `5ebbbb519` (#472) |

**Pinned tree commit to record:** `a9158930665763c592d004c895d52eff4a9eefc3` (mega65-core, "latest mega65-freezemenu version …", Oliver Graf, 2026-07-05). Record it as the exact `git show <commit>:src/vhdl/<file>.vhdl` source of each adaptation.
