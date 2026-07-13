# Issue #90 — Internal MEGA65 Drive as a Physical 1581 — HANDOVER

Self-contained handover for a fresh session/developer. Read this first, then
`PLAN.md` (the detailed chronological checkpoint) and `DESIGN.md` (the frozen
architecture). All paths are relative to the repo root
`/Users/mirko/Documents/Privat/GNR/dev/MEGA65/C64MEGA65`.

Branch (both repos): `mh_implement_90`. **No commits have been made** — the
maintainer commits. Commit-message drafts were provided in chat (submodule first,
then parent with the pointer bump).

---

## 0. TL;DR — status

The **read-only** internal-1581 feature is **implemented and verified in
simulation, and is buildable** on all four board revisions (behind a runtime OSM
toggle). A Vivado build of R3 + a genuine DD 1581 disk should read (directory /
LOAD). Writing and formatting are a **separate later milestone** (not started).
Everything is gated by `G_PHYS1581_CAPABLE` (true on all boards) and a runtime
"Use internal 1581" menu item (default Off = disk image).

Phases R1–R5 + docs + the idle-gate are done. Session 2 (2026-07-12) additionally:
**applied the timing-closure constraints (8.0), fixed the "enable internal 1581
without a mounted D81 = dead drive" bug set (8.4), and made the idle-gate
symmetric (8.1)**. Next step: rebuild R3 in Vivado and re-test on hardware.

---

## 1. What this is

Port target: **C64MEGA65** (MiSTer C64 core on MEGA65 via the M2M framework +
QNICE). The feature lets the user select the MEGA65's real internal 3.5" floppy
mechanism as the media source for the existing emulated Commodore 1581 on IEC
device 8, instead of a mounted D64/D81 image. The emulated 1581 CPU/ROM/CIA/VIA
and the WD1772 register interface stay; only the *media-facing* half changes: a
new 50 MHz FPGA controller conditions the real pins, decodes DD-MFM, checks CRCs,
and drives the mechanics.

- **Normative spec:** `doc/issue_90_internal_mega65_drive_as_1581.md` (5190 lines,
  extremely detailed, `MUST`/`SHOULD` language). We did **not** implement it
  literally — see section 2.2.
- **Research provenance:** `doc/how-MEGA65-uses-the-physical-disk-drive.md`.
- **Project guide:** `AGENTS.md` (repo conventions, build flow, QNICE testing).

---

## 2. KEY DECISIONS (most important section)

### 2.1 Scope & approach (maintainer decisions, locked)

| # | Decision |
|---|---|
| Approach | **Pragmatic ("B")**: same real functional behavior, but trim the spec's heavy ceremony (see 2.2). The maintainer explicitly chose this over literal spec compliance. |
| Milestone | **Read-only first.** Write + format is a distinct later milestone. |
| Boards | `G_PHYS1581_CAPABLE = true` on **all four** (R3/R4/R5/R6); functional testing on **R3**. |
| Switch UX | Source toggle is **idle-gated in the ROM** (`CORE/m2m-rom/m2m-rom.asm`), not via the spec's cache-drain machinery. |
| Diagnostics | Build a **read-only QNICE diag device** (`0x0108`) — the maintainer's only on-hardware debug tool (no scope/logic-analyzer). |
| Version | `WIP-V6-A18X1` (then `X2`, `X3`, … per feature). |
| Licensing | **Mix-and-match freely** with MEGA65/Paul Gardner-Stephen code (friends); only a light "adapted from mega65-core" comment, no provenance tables. |
| Constants | **No hardware instruments** → bake the spec's *stated initial* timing values as the real compile-time constants (generics in `physical_1581_pkg.vhd`). |
| Commits | Agent does **not** commit. |

### 2.2 How we pragmatically treated the (very elaborate) spec

The spec is normative and enormous. We implemented the **functional core** and
deliberately **omitted** machinery that a single personal internal drive does not
need for a working read path. A future *shipped/qualified* release would add these
back; for a personal build they are unnecessary. Deviations:

| Spec area | Spec wants | What we did | Why |
|---|---|---|---|
| §9.2/9.5/9.6/15.2/17.3 identity system | 16-bit `source_epoch` / `media_generation` / `request_id` / `buffer_generation`, no-alias wrap protocols, dual-ack control broadcasts, stale-response rejection | Simple **toggle handshakes**, one operation at a time, single request→result | one drive, no aliasing risk |
| §15.3/15.4 data-preserving live switch | flush the 1581 ROM `$0087` side-cache + 1541 GCR track cache before switching (quiet windows, drain generations, `$0087` T65-write classifier, custom-ROM digest/readback, 120 s watchdog) | **Idle-gate** only (switch when drive idle) | read-only; maintainer accepts re-init on switch |
| §16.2/§12.2 outer 100 MHz safety island | continuous 100 MHz block, async WGATE/WDATA clamp, heartbeat, clock-loss, `outer_write_kill`, mechanism-power monitor | **Not built** — WGATE/WDATA are tied inactive (`'1'`) in read-only | no writes → no write-safety island yet (REQUIRED for the write milestone) |
| §10.6/10.9/13.3/14.7–14.10 write path | two-pass sector-write fingerprinting, precomp, WDATA pulse gen, tail-close, index-anchored format start, raw WP/change async clamp, 700 µs guard | **Deferred** to write milestone | out of read-only scope |
| §13.4 head-position safety | reject Type-II/III until explicit Restore (`restore_required`) | Track `head_valid` **diagnostically only, non-blocking**; reads match on decoded C; the 1581 ROM restores at init | avoids breaking normal operation |
| §18.2 diag ABI | 64+ words, snapshot bank, ABI versioning, tearing protection | Pragmatic **40-word read-only** map (single clock domain, no tearing) | sufficient for debug |
| §11.2 measured constants (Q-01..Q-10) | freeze ~30 values by bench measurement | **Baked spec initial values** as generics | no instruments |
| §19 verification | H0–H6 hardware gates, real-media interop, endurance, formal, coverage | **Simulation** (GHDL/iverilog/menu_test) + adversarial review of risky diffs | hardware/Vivado = maintainer |
| §5.5 sector size | derive 128/256/512/1024 from N | **N=2 / 512 only**; other N → RNF + unsupported-size | spec-sanctioned specialization |

Kept faithfully: WD1772 command/status/DRQ/IRQ model, DD-MFM codec + CRC-16
(bit-exact), real mechanics timing (24 µs DIR setup, 4 µs STEP, 3/4 ms recovery,
18 ms settle, 505 ms motor-ready, index qualification), the conservative
power-up disk-change latch (§13.4/16.3), and **image mode byte-identical when the
feature is off** (adversarially verified).

### 2.3 SYMMETRIC IDLE-GATE — maintainer decision (2026-07-12), IMPLEMENTED (session 2)

The idle-gate blocks the drive-8 source toggle in **both** directions: the
physical-busy word gates Internal→Image, and a new image-busy diag word (drive
LED OR dirty write-back cache) gates Image→Internal, because the **simulated
(image) drive can WRITE** — switching away while it is busy or has unsaved data
would lose data. Details in section 8.1.

---

## 3. Architecture as-built (pragmatic)

Detailed contract: `DESIGN.md`. Summary:

- **New controller lives in `CORE/vhdl/main.vhd`**, clocked on `c64_clk_sd_i`
  (exactly 50 MHz = QNICE clock; already inside the drive subsystem). This keeps
  the SystemVerilog↔VHDL boundary at the existing `main`↔`iec_drive` seam, so the
  VHDL stays fully GHDL-testable.
- The WD1772 model (`fdc1772.v`, ~16 MHz drive clock) talks to the controller
  over a **flat `phys_*` toggle/level ABI** (33 signals). The controller owns the
  CDC (2-FF sync + toggle handshakes); the SV side reuses the existing
  `iecdrv_sync` discipline.
- Decoded read bytes cross 50 MHz→drive-clock via a **dual-clock FIFO**
  (`physical_1581_rdfifo`), drained by the WD front end at its DRQ cadence.
- The physical `f_*` pins are plain wires threaded top → `mega65.vhd` → `main.vhd`
  → controller (VHDL only; no CDC — pins are async, synchronized inside the
  controller). `f_wgate`/`f_wdata` stay tied `'1'` (read-only).
- Module list (all under `CORE/vhdl/physical_1581/`): `physical_1581_pkg`, `_crc`,
  `_mfm_gaps`, `_mfm_quantise`, `_mfm_gaps_to_bits`, `_mfm_bits_to_bytes`,
  `_mfm_decoder`, `_inputs`, `_rdfifo`, `_controller`, `_diag`. The four small MFM
  stages + CRC are faithful ports of mega65-core helpers; the decoder + controller
  + diag are fresh project logic.

---

## 4. Status by phase (done + how verified)

| Phase | Files | Verified |
|---|---|---|
| **R1** read path | `CORE/vhdl/physical_1581/*` | GHDL: `tb_physical_1581_crc`, `tb_physical_1581_mfm_decoder` (canonical sector round-trip), `tb_physical_1581_inputs`, `tb_physical_1581_rdfifo`, and the **closed-loop** `tb_physical_1581_controller` (controller + read-FIFO + `mech_model_1581` behavioral mechanism + `golden_1581_pkg`): motor→index→real stepping→flux decode→CRC→512-byte payload; Read Sector/Address/Verify; RNF. All `rc=0`. |
| **R2** WD physical branch | `fdc1772.v` (submodule) + `tb_fdc1772_physical.sv` | iverilog (Restore/Seek/Read Sector, status `0x80`); **adversarial review** confirmed image mode byte-identical. |
| **R3** threading + integration | SV: `iec_drive.sv`/`c1581_multi.sv`/`c1581_drv.sv`; VHDL: `main.vhd`/`mega65.vhd`/`top_mega65-r{3,4,5,6}.vhd`; projects: `CORE-R{3,4,5,6}.{xpr,tcl}` | iverilog junction elaboration; `ghdl -s`; cross-boundary port names verified perfect-match; all 10 modules registered VHDL-2008. |
| **R4** menu/version/config | `config.vhd`, `mega65.vhd` (`C_MENU_INTERNAL_1581=3` + shift), `M2M/rom/tests/menu_test.py`, `M2M/tools/c64mega65-WIP-V6-A18X1` (160-byte config) | `menu_test.py` all modes incl. 10/10 mutants. |
| **R5** diag device | `globals.vhd`, `physical_1581_diag.vhd`, `main.vhd`/`mega65.vhd`, `doc/1581_dd_debug_device.md` | GHDL diag test; controller re-run (no regression). |
| docs | `VERSIONS.md`, `ROADMAP.md`, `README.md`, `FAQ.md` (Q23), `tests/README.md` (append-only), `doc/models.md` | review; Marked-2 + append-only rules followed. |
| idle-gate | `CORE/m2m-rom/m2m-rom.asm` (`OSM_SEL_PRE`) | Shell ROM builds clean (27506/28672 words). **One-directional — see 2.3 / 8.1.** |

Full GHDL suite was re-run green after all edits (no regressions).

---

## 5. Verification boundary — what is proven here vs. maintainer's job

- **Proven here (free tools):** VHDL logic (GHDL), SV WD frontend (iverilog),
  menu structure (`menu_test.py`), cross-boundary port matching (grep/`ghdl -s`),
  image-mode preservation (adversarial review), and no upstream drift (the
  adapted mega65-core files are byte-identical to `development` HEAD `a9158930`).
- **Maintainer / hardware (NOT done here):** Vivado synthesis, timing (WNS/WHS),
  `report_cdc`/`report_methodology`, resource; the full mixed-language elaboration;
  and all real-hardware behavior. There is **no** oscilloscope/logic-analyzer,
  so the spec's Q-01..Q-10 measurements and H0–H6 gates are the maintainer's
  loop. Confirm on hardware: `change_o` polarity (assumed active-low, marked in
  `physical_1581_inputs.vhd`) and the `f_side1_o` inversion.

---

## 6. How to build & test (read-only)

1. Build `CORE-R3` in Vivado (`./CORE/run_vivado_r3.sh` → synth/impl/bitstream).
   The feature compiles in on all boards; it is gated at runtime.
2. Copy the new **160-byte** `M2M/tools/c64mega65-WIP-V6-A18X1` to the SD card
   `/c64/` (old 159-byte configs are rejected → safe defaults; expected).
3. Flash → OSM menu: **"Use internal 1581" = On** → insert a genuine DD 1581 disk
   → `LOAD"$",8` / `LOAD"name",8`.
4. Debug via the QNICE diag device `0x0108` — procedure in
   `doc/1581_dd_debug_device.md` (live index/track0/WP/motor/CRC/state + counters).
5. Writing/formatting is intentionally inert.

---

## 7. Document & file map

- **Working notes (this folder, `doc/dev-issue90/`):** `HANDOVER.md` (this),
  `PLAN.md` (living chronological checkpoint + resume hints + GHDL recipe),
  `DESIGN.md` (frozen architecture + ABI), `recon_map.md` (the codebase map:
  clocks, threading chain, injection points, 12 integration risks),
  `codec_adaptation.md` (MFM/CRC adaptation), `upstream/` (the pinned `a9158930`
  helper sources). *These are scratch notes, deletable; not part of the feature.*
- **Normative spec:** `doc/issue_90_internal_mega65_drive_as_1581.md`.
- **Feature doc:** `doc/1581_dd_debug_device.md`.
- **New RTL:** `CORE/vhdl/physical_1581/*.vhd`; **tests:**
  `CORE/vhdl/test/tb_physical_1581_{codec,inputs,controller,diag}/`.
- **Submodule SV:** `CORE/C64_MiSTerMEGA65/rtl/iec_drive/{fdc1772.v, iec_drive.sv,
  c1581_multi.sv, c1581_drv.sv, tb_fdc1772_physical.sv}`.
- **Integration:** `CORE/vhdl/{main.vhd, mega65.vhd, config.vhd, globals.vhd}`,
  `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd`, `CORE/CORE-R{3,4,5,6}.{xpr,tcl}`,
  `CORE/m2m-rom/m2m-rom.asm`, `M2M/rom/tests/menu_test.py`.
- **Upstream reference checkout:** `../mega65-core` (@ `a9158930`, no drift).
- **GHDL/iverilog recipes:** in `PLAN.md` ("GHDL build recipe" + R2 notes). GHDL
  5.1.1 and iverilog are installed; no Vivado/Verilator. macOS has no `timeout`;
  testbenches self-bound. QNICE toolchain was rebuilt for macOS (see `AGENTS.md`).

---

## 8. Next steps & milestones

### 8.0 R3 timing closure — FIX APPLIED (session 2, 2026-07-12); verify with the next build

The first R3 build (`CORE/CORE-R3.runs/impl_1/mega65_r3_timing_summary_routed.rpt`)
did **not** close timing: setup **WNS = −5.051 ns**, 83 failing endpoints (hold and
pulse-width are fine). Diagnosis (from that report's Inter/Intra-Clock tables +
violated-path endpoints):

- **71 endpoints = the physical_1581 CDC**, cross-clock between `qnice_clk` (50 MHz,
  the new controller / read-FIFO / diag) and `main_clk` (~31.5 MHz, the WD1772 +
  drive). Confirmed cells: `i_physical_1581_controller/{motor_m, op_r, sec_r}` (2FF +
  handshake captures), `i_physical_1581_rdfifo/rq1_wgray` (Gray pointer),
  `.../c1581_drv/fdc/phys_rddone_sync/s1_reg` (`fdc1772` phys toggle sync). **Root
  cause: we never added CDC timing exceptions for these crossings** (the repo cuts
  drive CDC with granular false-paths in `CORE/CORE.xdc:12-41`; `M2M/common.xdc:106`
  documents the two system clocks as asynchronous).
- **12 endpoints = pre-existing framework**: an intra-`qnice_clk` half-cycle path
  `QNICE_SOC/ramrom_dev_o_reg → cpu/SP_reg/CE` at **−0.281 ns**. This is downstream
  of our diag read-mux (our mux does not lengthen it); it is almost certainly
  congested by the 71 failing CDC routes and should recover once they are cut.

**Applied fix (in `CORE/CORE.xdc`, right after the `sd_lba` block; APPLIED in
session 2):** two clock-to-clock false-paths, both directions, between `qnice_clk`
and `main_clk` (same idiom as `common.xdc:122`'s `qnice_clk→hdmi_clk`). This is safe
(clock-to-clock cannot exempt a same-clock path, so it does NOT hit the `fdc1772
busy` hazard the repo warns about), correct (the clocks are documented-async and
every crossing is synchronized), and complete (cannot miss a synchronizer). It
subsumes the granular drive-CDC cuts above. Additionally, `CORE-R{3,4,5,6}.tcl`
`read_xdc` was reordered to `MEGA65-Rx → common → CORE` because `CORE.xdc` now
references `qnice_clk`, which `common.xdc` creates (the `.xpr` fileset already
used that order, so project builds were always fine).

- **Alternative (maintainer's granular style), if preferred over the clock-pair cut:**
  replace the two lines with per-synchronizer `set_false_path -to` on:
  controller `i_physical_1581_controller/{active_m,motor_m,side_m,stq_m,rdq_m,cnq_m}_reg/D`
  + the handshake-captured `{op_r,trk_r,sec_r}_reg[*]/D` + the `i_inputs` 2FF flops;
  the `fdc1772` `phys_*_sync/s1_reg[*]/D` + phys result/state capture regs; and the
  `physical_1581_rdfifo` Gray-pointer syncs + a `-datapath_only` on its RAM read. (More
  lines, easy to miss one → another failed multi-hour build; that risk is why the
  clock-pair cut was chosen.)

**Verify before declaring closed:** re-run R3 implementation; confirm `WNS ≥ 0` in the
routed timing summary and `report_cdc` shows no Critical (an expected new
"asynchronous clock groups"/false-path note is fine). If the −0.281 ns framework path
persists after the CDC cut, it is congestion — reduce the qnice-domain footprint
(e.g. narrow the diag device's ten 32-bit counters, or add a scoped multicycle on that
QNICE half-cycle path) and re-run. **No functional RTL change is needed for closure —
this is purely a constraints issue.**

### 8.1 Symmetric idle-gate — DONE (session 2, 2026-07-12)

Implemented as: `main.vhd` `img_drive_busy <= c64_drive_led or prevent_reset`
(covers live activity of both image engines + dirty caches), 2-FF-synced into
the diag domain; new diag word `RM_IMG_DRIVE = 0x28` bit 0 (map version `0x02`,
capability `0x0F`); `m2m-rom.asm` `_OSM_PRE_1581` reads both busy words and
reverts the toggle via `M2M$FORCE_MENU` if either is set — one code path gates
both directions, since each side reads idle while the other is the active
source. Shell ROM: 27515/28672 words. Original plan below for reference:

Goal: block the drive-8 source toggle in **both** directions while the relevant
drive is busy. Reason: the image drive writes; switching away with unsaved data
loses it. Approach (a small RTL tap + a few asm lines; **safe to do only when
Vivado is not mid-build**):

1. Route the emulated 1581's **WD busy** (`fdc_busy` in `c1581_drv.sv`, already
   used for `act_led`) up to `main.vhd`, and OR it with the **vdrives
   `cache_dirty`** (already present in `main.vhd`, used by `prevent_reset`) →
   "image drive busy/dirty".
2. 2-FF sync that into the diag domain (`c64_clk_sd_i`) and expose it as a spare
   bit in `physical_1581_diag.vhd` (e.g. a bit in `RM_CTRL_STATE` word `0x04`, or
   a new word). No new device.
3. In `m2m-rom.asm` `OSM_SEL_PRE`, when toggling `C64_OPTM_G_INT1581`: for
   Internal→Image use the existing physical-busy mask; for Image→Internal use the
   new image-busy bit; revert via `M2M$FORCE_MENU` in either case.

Accepted minor points: "busy" includes the brief motor spin-down tail (fine);
revert is silent (matches "just ignore").

### 8.4 "Internal 1581 without a mounted D81" bug set — FIXED (session 2, 2026-07-12)

User-reported: enabling "Use internal 1581" with no D81 mounted left the drive
dead (held in reset, no 1581 active anywhere); with a D81 mounted and the first
(non-timing-closed) bitstream, `LOAD"$",8` from a real disk also failed. Five
root causes were found and fixed:

1. **`main.vhd` reset hold** — `iec_drives_reset(0)` required `vdrives_mounted(0)`;
   now excepted while `phys_1581_en_i='1'` (there is no image to mount).
2. **CIA PA7 `/DSKCHG` stuck asserted** — it was the image-mode `disk_chng_n`,
   which only `floppy_step` clears, and `floppy_step` never pulses in phys mode
   (steps go over the toggle ABI). The 1581 DOS therefore never saw valid media.
   Now muxed in `c1581_drv.sv` to the controller's sticky change latch
   (2-FF-synced, inverted); PB6 `/WPRT` likewise now senses the real WP pin.
3. **WD Type-I deadlock** — `fdc1772.v` rejected Type-I with RNF while media was
   not ready, but media-ready needs the change latch cleared, only a step clears
   it, and steps ARE Type-I commands. Type-I now runs unconditionally in phys
   mode (the real WD1772 has no READY input; Type-II/III still fast-fail).
4. **Silent media swap on source switch** — the controller now re-arms
   `change_latched` whenever it is disabled (not only on reset), and
   `c1581_drv.sv` asserts the image-side disk change on any `phys_mode` edge, so
   BOTH switch directions present as a disk change and the DOS revalidates.
5. **Zero-step verify wedge** — controller `head_settled` now initializes to
   `'1'` (head at rest = settled); the old `'0'` could hang a Restore-with-Verify
   that needs no steps, because only a step ever set it.

A 43-agent adversarial review (7 dimensions × independent refuters) of all the
session-2 diffs then confirmed and led to fixing **eight more defects** — most
notably: the read-FIFO's one-sided reset (permanent Gray-pointer desync → silent
CRC-clean data corruption after any core reset mid-read; both sides now reset
from the same QNICE-reset event and fdc1772 drains residue while idle), the WD
popping the next byte at the *start* of the drive CPU's data-register access
while the T65 latches at the *end* (deterministic one-byte stream shift, proven
by the upgraded `tb_fdc1772_physical.sv` with a realistic 16-clkcpu bus cycle),
an unbounded physical RESTORE (now real-WD1772 255-step bound → Seek Error), a
CDC skew window on the rd-done handshake that could leave the WD busy forever
(done now consumed 2 cycles delayed), a missing RD_STREAM watchdog, a stale
settle-timer window, and the image-busy diag bit conflating the physical LED.
Full list + fixes: `PLAN.md` ("ADVERSARIAL REVIEW ROUND" entry).

### 8.2 Hardware bring-up (read) — COMPLETE (2026-07-13): READ MILESTONE REACHED

After eight bring-up rounds (full log in `PLAN.md`, 2026-07-13 entries):
`LOAD"$",8` is reliable and programs load and RUN from a genuine DD disk,
including files whose chains span side 1 (verified against the mother D81:
SHADES, 20 of 35 blocks on side 1, loaded and played). Fixed along the way:
media-ready semantics, side-select mapping (empirical, from on-disk H bytes —
see the controller comment), the WD data-register readback (1581 ROM self-test),
busy-until-consumed byte delivery (ROM software-CRCs the Read Address reply),
and the silent read-FIFO overflow (depth 512 + honest error reporting). Known
non-blocking imperfections and the queued diagnostic fix are listed in the
PLAN.md round-8 entry. The next milestone is WRITE + FORMAT (8.3).

Original round-1 notes below for reference:

First R3 hardware test: timing closed (WNS +0.366), error channel returns 73,
but `LOAD"$",8` failed with FILE NOT FOUND and the drive LED never lit (the DOS
never issued a WD command). Root cause found and fixed: `media_ready` (CIA PA1
/RDY) was gated on the disk-change latch, which only a step clears — but the
stock 1581 ROM waits for RDY *before* running the job whose seeks would step
(and a Restore with the head already on track 0 steps zero times). RDY now
models the real FB-354 line (motor + live index only); the change latch drives
only PA7/read-abort; ejects are caught by index-pulse loss. Companion WD fix:
real index feeds the WD spin-up/IRQ-at-index/motor-timeout housekeeping in phys
mode. Needs a REBUILD + retest; if reads then abort with result `0x0A`
(disk changed), suspect the DSKCHG pin polarity (flip `change_o` in
`physical_1581_inputs.vhd`) — see PLAN.md 2026-07-13 entry.

Build all four, test on R3 per section 6. Confirm pin polarities on real
hardware (`change_o`, `f_side1_o` inversion, index/RDATA). Use the `0x0108` diag
device as the primary observability. Fill in a board/mechanism qualification note
in `doc/models.md`.

### 8.3 NEXT MILESTONE — WRITE + FORMAT (large)

This is the big remaining feature and is genuinely more dangerous (can damage
media), so it needs the safety machinery we deferred:

- **MFM write encoder** (adapt `mega65-core` `mfm_bits_to_gaps.vhdl`, staged in
  `upstream/`), WDATA pulse generation + **write precompensation** (§14.9).
- **Write Sector** (§10.6): the two-pass ID fingerprint + splice, or a pragmatic
  equivalent; the 22-byte post-ID gap, `FB`/`F8`, 512 bytes, CRC, trailing `FF`.
- **Write Track / format** (§10.9/14.7): the F5/F6/F7 token stream, CRC-preset
  (`0xCDB4` after `A1 A1 A1`), index-anchored start, **conservative pre-index tail
  close**, and the stock-ROM `6122`-byte trace.
- **The outer safety island we skipped (§16.2/12.2):** raw WP/change async clamp
  (`outer_write_kill`), the 100 MHz heartbeat/clock-loss path, the 700 µs guard —
  WGATE/WDATA must never fire outside authorization. This is the main new RTL.
- **Hardware qualification** for write (Q-07 raw-kill clamp ≤ 2 µs, RPM lock,
  precomp read-back) — needs instruments the maintainer said they lack, so the
  write milestone will lean on careful design + on-disk read-back verification.
- Once writes exist, the **data-preserving source switch** (§15.3/15.4) matters
  more; the symmetric idle-gate (8.1) is the pragmatic stand-in.

---

## 9. Known gotchas / open items

- **Pin polarity assumptions** to confirm on hardware (5.5 / 8.2).
- `head_valid`/`restore_required` is diagnostic-only, non-blocking (2.2).
- **GHDL `--elab-run` drops executables (`tb_*`, `e~tb_*.o`) in the repo root** —
  clean with `rm -f tb_physical_1581_* e~tb_*.o work-obj*.cf` after runs, or add
  per-test Makefiles like `CORE/vhdl/test/tb_crt_parser`. (Do NOT leave these for
  a commit.)
- **iverilog can't compile the full drive chain** (upstream MiSTer
  declaration-after-use); only minimal safe reorders were made in `fdc1772.v`.
  Full elaboration is Vivado's job.
- **Submodule workflow:** commit `CORE/C64_MiSTerMEGA65` first, then bump the
  parent pointer. Drafts are in the chat history.
- **No commits made.**

---

## 10. How the work was done + how to resume

The implementation was driven by heavy **subagent delegation** with a consistent
pattern: define an interface/contract precisely → delegate implementation →
require GHDL/iverilog/menu_test verification → adversarially review risky diffs
(esp. image-mode preservation). `PLAN.md` is the living checkpoint (chronological
status log + resume hints + the exact GHDL recipe).

To resume: read `PLAN.md` "Resume hint" + this file's section 8. The RTL is
coherent and GHDL-green; the next actionable task is the symmetric idle-gate
(8.1), then hardware bring-up (8.2), then the write/format milestone (8.3). Verify
any change with the GHDL/iverilog/menu_test recipes before handing a build back.
Do not modify build-relevant files while a Vivado build is running.
