# Internal 1581 — WRITE and FORMAT support (issue #244) — Plan

Status: DRAFT v0.1, 2026-10-15. The plan that executes `doc/dev-fdd/WRITE-SPEC.md`. Written in
the working style of the wof-wasm controller handbook: one controller session (the one the
maintainer talks to) drives bounded worker sessions, verifies every report with a check of its
own, keeps the spec true, and is the only session that asks the maintainer anything. Every ask is
self-contained; the maintainer is away for hours at a time.

---

## 0. Where things stand (2026-10-15)

* Read-only internal 1581: shipped in `WIP-V6-A18X1` (2026-07-18), integrated into `develop` for
  `A19`, extended to "drive 8 or 9" in `A20`; current build `WIP-V6-A20X3` (issue #248 fix for
  the *simulated* 1581's write timing). Branch `mh_dev_drives`, tree clean.
* Writing to the physical drive: **nothing exists** beyond the two WD-side fake-finishes and the
  tied-off pins. The spec is written; no code, no testbench, no build.
* Research assets ready for the workers: the three research notes of this planning session —
  `doc/dev-fdd/write_research_aexp_lessons.md` (what AExp learned, with file:line pointers into
  its writer, FIFO, testbench, twin and flux tools), `doc/dev-fdd/write_research_wd_path.md` (the
  current `fdc1772.v` write path, the phys ABI, the exact pin tie-off lines, the diag map, the
  testbench inventory) and `doc/dev-fdd/write_research_dos1581.md` (the genuine ROM's write and
  format behaviour with addresses and measured cycle counts) — plus the ROM write-probe tooling
  in `doc/dev-fdd/rom_emu/write_probes/` (an accurate-cycle 6502 table and a timed writable
  WD1772 model; M2 grows it into the fixture generator), the mega65-core F011 writer facts
  (`../AExp/.research/RESEARCH-write-mega65-core.md`), the existing GHDL/iverilog suites and the
  diag device.
* A latent bug in the shipped read-only build, found during this planning (spec 5.1 and 4.1): a
  SAVE to a *writable* disk in physical mode passes the DOS's own write-protect check (it samples
  the real tab) and reaches the WD, whose physical-mode fake-finish drops BUSY after ~125 ns; the
  ROM's command writer spins until it sees BUSY high and, measured in the ROM emulator, hangs
  forever on a BUSY pulse that short. Expected symptom today: the drive freezes (LED off, no
  further IEC traffic) until the next reset. Not yet reproduced on hardware. Milestone M3 replaces
  that path; an interim one-liner is offered in section 8, decision 5.

---

## 1. Milestones

| | Milestone | Deliverable | Gate (must be green before the next starts) | Sessions |
|---|---|---|---|---|
| **M1** | Writer front end + Write Sector, in simulation | `physical_1581_wfifo/_mfm_encoder/_writer.vhd`, the controller write engine (sector only), writable `mech_model_1581`, the Python twin, scenarios W1 W2 W4–W10 W13, the mutant matrix | all scenarios green; every mutant killed by its named scenario; existing suites unchanged | 1 worker (VHDL) |
| **M2** | WD front end write branch | `fdc1772.v` physical Write Sector + Write Track request/DRQ/FIFO/status, threading through `c1581_drv/c1581_multi/iec_drive`, iverilog scenarios incl. the ROM polling idiom, image-mode golden trace; `rom_emu` WD write model producing the W2/W3 fixtures | iverilog green; golden trace byte-identical; fixtures recorded | 1 worker (SV + Python) |
| **M3** | Integration, bitstream, bench round 1 (sector writes) | pins through the four tops / `mega65.vhd` / `main.vhd`, diag map v8, Shell labels + busy mask, `CORE_VERSION WIP-V6-A21X1`, `.xpr` file lists, docs; **maintainer builds R3 (+R6)** | timing closed; read regression; single SAVE/LOAD; SAV-WRITE; diag balance (section 5) | 1 worker + maintainer bench |
| **M4** | Format (Write Track), bench round 2 | controller track engine, W3/W12 in sim with the genuine-ROM token stream, hardware `N0:` + `VALIDATE` + directory; referee read of a core-formatted + core-written disk | referee passes (section 5.3) | 1 worker + maintainer bench |
| **M5** | Community alpha, robustness, release bookkeeping | Discord recipes (section 6), fixes from reports as bounded tasks, `tests/README.md`, `VERSIONS.md`, FAQ/README, `doc/models.md`; merge to `develop`; V6-or-later decision | definition of done (spec 1.3) | findings worker + maintainer |

Why this order: M1 and M2 are independent of each other but share the ABI of spec 5.2, which is
frozen in the spec, so they *could* run in parallel in two worktrees; the repository rule "one
working directory, one active worker" says sequential. M1 first because it is where the
magnetically dangerous logic lives and where the flux model and twin give the strongest early
evidence. Format waits for sector writes to be proven on hardware because a sector write touches
one 17 ms window and a format touches whole tracks — the cheaper experiment first.

Estimated effort (sessions of the kind the read milestone used): M1 ≈ 2, M2 ≈ 1–2, M3 ≈ 1 plus
one bench round, M4 ≈ 1 plus one bench round, M5 ≈ open-ended, community-paced. The read milestone
took five weeks with eleven bring-up rounds; the write milestone inherits its instruments, its
ABI and a proven writer, so two to three weeks to a community alpha is realistic if the bench
rounds go as the sim predicts.

---

## 2. Worker briefs

Each brief follows the handbook's ten points. Model/effort per the handbook table: Opus at xhigh
for the implementation milestones (everything below is checkable by simulation, a golden trace or
a bench value); the controller on Fable. The maintainer sets model, effort and the session name;
suggested names: `Worker M1 writer sim`, `Worker M2 WD write branch`, `Worker M3 integration`,
`Worker M4 format`, `Worker test findings`.

### 2.1 Common to every brief

1. First line: the task in one sentence and that it comes from the controller.
2. The maintainer set the session up; the worker reports to the controller only and never asks the
   maintainer anything; questions go into the report.
3. Read first: `AGENTS.md`, `doc/dev-fdd/WRITE-SPEC.md` (whole), `doc/dev-fdd/HANDOVER.md`
   sections 2, 3, 8.3, 8.5, 9; `doc/dev-fdd/DESIGN.md`; then the milestone's own list.
4. `git status` first; stop if the tree is not clean. Branch from `mh_dev_drives` (or the branch
   the controller names) as `write-m<N>`; no merge, no push, no remote; the submodule
   `CORE/C64_MiSTerMEGA65` is committed first on its own branch, then the parent pointer.
5. Never edit `WRITE-SPEC.md`, `AGENTS.md`, the four `.xpr` files unless the brief says so, nor
   anything under `tests/` before `Version WIP-V6-A21 - TBD` exists; spec changes are proposed in
   the report. No apostrophes in QNICE assembly comments. Marked-2-clean Markdown.
6. Deliverables: numbered, below.
7. Verification: stated as a method; every claim in the report carries the command and its real
   output. GHDL drops `tb_*`/`e~*.o` in the cwd — run from a scratch directory.
8. Acceptance: the milestone's gate in section 1.
9. Stop and report (instead of retrying) when a scenario disagrees with the spec, when the twin
   and the flux model disagree, when a mutant survives, when a change to image-mode code seems
   necessary, or after two failed attempts at the same fix.
10. The report: files touched, commands with output, deviations from the spec and places where the
    spec was wrong or silent, what is unfinished or fragile, anything the maintainer must know,
    the commits.

Do not think for long stretches without emitting output; interleave small tool calls and status
lines (the harness kills silent sessions). Commit whatever is green before a long run.

### 2.2 M1 — writer front end + Write Sector in simulation (VHDL)

Deliverables:
1. `CORE/vhdl/physical_1581/physical_1581_wfifo.vhd`: port of
   `../AExp/CORE/vhdl/physical_fdd/physical_fdd_wfifo.vhd` with an 8-bit data width generic, both
   occupancy taps; header credits AExp (same author, GPLv3).
2. `physical_1581_mfm_encoder.vhd` per spec 5.5, with its own GHDL unit test: every byte value,
   clock carry across bytes, the two sync words, the `0xCDB4` anchor, the `F5` preset rule.
3. `physical_1581_writer.vhd`: port of `physical_fdd_writer.vhd` per spec 5.6 (episode = `session`,
   same clock; select/side terms → motor/enable; `v_hold` deleted; word source = a 4-deep
   same-clock FWFT FIFO fed by the encoder).
4. The controller write engine for `WROP_WRITE_SECTOR` per spec 5.3/5.4, the ABI of 5.2 as new
   ports (write-track op decoded but completing `RES_INVALID_REQUEST` until M4), the mechanics
   guard, `dec_rst` during gate + tail, the diag taps of spec 8 as ports (the diag entity itself is
   M3).
5. `mech_model_1581.vhd` writable per spec 10.1 (flux store per cylinder/side, erase/write/playback,
   pulse census, edge-outside-WGATE assert) and `golden_1581_pkg` laying the seed track into the
   store; `tb_mech_model_1581` still self-tests.
6. `wr_twin.py` (port of `td_write_check.py`) + a dump format from the model; an independent
   decoder over the flux dump.
7. Scenarios W1, W2 (with the DOS cadence: 10 single-sector ops k+1…10,1…k, next op ~70 µs after
   done, service latency sweep 0…30 µs), W4–W10, W13 in `tb_physical_1581_controller` (or a new
   `tb_physical_1581_write.vhd` sharing the harness); a runner script with per-scenario workdirs.
8. The mutant matrix of spec 10.1 as a script with anchored single-site edits of file copies;
   every mutant killed by its named scenario.
9. `physical_1581_pkg.vhd`: op/result codes and constants of spec 5.7.

Verification: the full existing GHDL suite (codec, inputs, controller, media contract, ovf, diag)
unchanged and green; the new scenarios; the mutant run; the twin agreement ± 1 cycle; `ghdl -s`
on every file. Report the measured `G_WR_GAP_BYTES` calibration (where WGATE opens relative to
the ID CRC in the model, in cells).

Controller's own check for M1: run W2 with a service latency and a sector order the worker never
used, and with the seed payload inverted; decode the resulting flux with the independent decoder
only; compare the 10 × 512 bytes against the source without the DUT's read path.

### 2.3 M2 — WD front end write branch (SystemVerilog + Python)

Deliverables:
1. `fdc1772.v`: the physical Write Sector and Write Track branch per spec 5.1 (request on the
   existing channel, `phys_wr_feed`-gated DRQ = FIFO not full, data-register writes → FIFO push,
   WP pre-check, completion after the writer's busy, status bits, m = 1 re-issue as stretch), the
   forced-WP term removed; image mode expression-for-expression unchanged.
2. Threading of the new signals through `c1581_drv.sv`, `c1581_multi.sv` (incl. the per-drive
   toggle collector), `iec_drive.sv`; the write FIFO instance belongs to `main.vhd` (M3), so the
   SV side exposes push/data/full/level ports.
3. `tb_fdc1772_physical.sv`: the scenario groups of spec 10.2, with a 16-clkcpu bus-cycle 6502
   model and the ROM's `$CBF4` wait-busy-set / per-byte DRQ-wait idiom; a FIFO stub on a 50 MHz
   clock with a modelled consumer at 32 µs.
4. The image-mode golden trace: a register-level transcript of an image-mode SAVE (and a format
   attempt) recorded from the pre-change RTL, replayed against the changed RTL, byte-identical.
5. `doc/dev-fdd/rom_emu`: the WD write model (DRQ/DR/status per spec 5.1) so the genuine ROM's
   `SAVE` and `N0:` jobs run; record the command/byte transcripts as fixtures
   (`fixtures/write_back_order.json`, `fixtures/format_tokens.bin`) and the ROM's observed
   reactions to LOST DATA / WP / RNF for the spec's section 4.

Verification: iverilog green; the golden trace; the `rom_emu` proofs run headlessly. Stop and
report if the ROM's write loop turns out to depend on DRQ timing in a way spec 5.4's
"FIFO-room DRQ" would change.

Controller's own check for M2: diff the image-mode paths of `fdc1772.v` before/after with
`phys_mode` constant-folded to 0 (a script that strips the `phys_mode` branches) and show the
image-mode text identical; run the shipped issue-#248 testbench (`sim_fdc`, see the A20X3 release)
against the changed file.

### 2.4 M3 — integration, bitstream, bench round 1

Deliverables:
1. `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd`: route `f_wdata_o`/`f_wgate_o` from `MEGA65_Core` (the
   AExp `M2M-UPSTREAM floppy-pins` block as template; keep motorb/selectb tied).
2. `mega65.vhd`, `main.vhd`: ports; `physical_1581_wfifo` instance (write side `clk_main_i`, read
   side `c64_clk_sd_i`, both resets from the QNICE reset event, synchronized per side); encoder +
   writer instances (or a `physical_1581_top.vhd` wrapper); the writer's busy/ok 2-FF into the
   drive domain; `img_drive_busy`/busy vector extension.
3. `physical_1581_diag.vhd` map v8 per spec 8 + `doc/1581_dd_debug_device.md`.
4. `CORE/m2m-rom/m2m-rom.asm`: `WRITING`/`FORMAT` states and labels, `P1581_BUSY_MASK`; Shell ROM
   builds within budget; `menu_test.py verify` unchanged.
5. `CORE/vhdl/config.vhd`: `CORE_VERSION := "WIP-V6-A21X1"`; `M2M/tools/make_config.sh` run for
   the new file name; `.xpr` file lists (all four) with the three new files in dependency order.
6. Docs: `tests/README.md` gets `Version WIP-V6-A21 - TBD` on top with the bench and community
   gates of sections 5 and 6 as `@TODO`s; `doc/inofficial.md` row drafted (the maintainer commits
   the hash); README/FAQ "Writing" section drafted.
7. The interim guard of decision 5 is moot here (the path is replaced).

Verification: `ghdl -s` of the whole `physical_1581` tree + `main.vhd` per the memory recipe;
the full GHDL/iverilog suites; `menu_test.py`; the Shell ROM build; a dry synthesis is the
maintainer's (`cd CORE && ./build_all.sh R3 R6`).

Controller's own check for M3: read the four tops' diffs line by line against AExp's; confirm the
reset values of the two pins through `mega65.vhd` down to the writer; grep that no `f_wgate` is
assigned anywhere but the writer; after the build, read `report_cdc` and the utilization delta.

### 2.5 M4 — Write Track (format)

Deliverables: the controller track engine per spec 5.3 (arm on the filtered index edge, token
decoder with `F5`/`F6`/`F7`, close on the next edge, watchdogs); W3 and W12 using the M2 fixture
token stream; `WR_TRK_CYC` instrument; the WD side's Write Track feed (already in M2) exercised end
to end in `tb_fdc1772_physical.sv` with the fixture; docs.

Controller's own check for M4: feed the format fixture through the sim, dump the written flux,
decode it with the independent decoder and verify the ten ID fields per side carry the ROM's C/H/R
and CRCs and that the first sector's preamble survives the index splice; run the genuine ROM in
`rom_emu` against the decoded track to read the directory it just formatted.

### 2.6 Findings worker (M5)

Bounded fix tasks from bench and community reports; each task names the diag dump, the recipe,
the expected vs observed values, and the scenario that must be added to the sim suite so the
class cannot return (the AExp rule: classify before theorising — compare, scan, then dump deltas).

---

## 3. Controller duties per milestone

1. Before a task: `main`/`mh_dev_drives` checked out, tree clean, no other worker active; the
   brief names the session to report to.
2. On a report: git facts (commits, merge base, forbidden paths untouched, no generated files);
   the full suites run by the controller; the "one check of your own" above; read the code that
   carries the weight (the WGATE conjunction, the abort latch, the FIFO reset, the CRC preset, the
   image-mode gating).
3. Merge by fast-forward, fold findings into `WRITE-SPEC.md`, keep the chronicle in this file
   (section 9), commit.
4. Ask the maintainer only for bench rounds, decisions of section 8, and the real-hardware
   referee.

---

## 4. The ABI is frozen before M1 starts

Spec 5.2 is the contract between M1 (VHDL) and M2 (SV). Both workers implement against it; a
change proposed by either goes into the spec first, then into both. The controller re-reads the
port lists of both sides against the spec table before M3 wires them (the read milestone's
"cross-boundary port names verified perfect-match" step).

---

## 5. Bench protocol (maintainer; R3 first, then R6)

Pre-registered: each step names its expected observation; an observation outside it stops the
round and goes back to simulation with the dump. Media: NOS DD blanks only, labelled; originals
and anything irreplaceable stay write-protected (tab window open). Dump the diag bank in the same
session as the step (`M 7000 707F` style per `doc/1581_dd_debug_device.md`, now through `0x9A`).

### 5.1 Round 1 (after M3, sector writes only)

| Step | Action | Expected | If not |
|---|---|---|---|
| 1 | Read regression: the A18X2 read recipes (directory, LOAD, a side-1 file, a genuine-1581 disk if available) | unchanged | stop: integration regressed the read path |
| 2 | Power-on, Internal 1581 on drive 8, blank disk tab **open** (protected): `SAVE"T",8` | `26, WRITE PROTECT ON`; `CNT_WR_WP` = 3 (the DOS tries three times), `CNT_WR_GATE` = 0, `WR_STATE.wr_ok` = 0 | gate opened: STOP everything, sim W4 is wrong |
| 3 | Close the tab (writable), wait 1 s: `WR_STATE.wr_ok` = 1 | 1 | qualifier never qualifies: check polarity / settle |
| 4 | Use a disk that is already 1581-formatted (by the MEGA65 core's F011 or a real 1581 — format is M4): `SAVE"T",8` of a 2-block program | drive LED; `CNT_WR_SECT` a multiple of 10 (one flush per touched side: directory side + data side, so 20 or 30); `WR_GATE_CYC` = 849,600 ± 100; `CNT_WR_LOST` = 0; `CNT_WR_ABORT` = 0; `WR_FIRST_MARGIN` ≥ 18; `WR_DRQ_MARGIN` ≥ 1; the trace ring shows each flush as RA, RA, ten writes starting at R + 1, RA, ten reads | LOST > 0: DRQ service slower than modelled; FIRST_MARGIN < 10: the gap calibration is off |
| 5 | `LOAD"T",8` after a power cycle; `VALIDATE` | loads; `0, OK` | FILE NOT FOUND / 23 READ ERROR: splice or CRC — Greaseweazle or MEGA65-core read of the disk |
| 6 | A 30-block file spanning both sides; LOAD back | byte-exact (compare in memory or via a D81 copy) | |
| 7 | paich64's `SAV-WRITE` (D81 on 8, Internal 1581 on 9), run 0 | completes; all files audit clean; counters as in 4 | |
| 8 | Eject mid-SAVE (sacrificial disk) | `CNT_WR_ABORT` +1 reason 0x08; DOS error; no hang; next disk works | |
| 9 | Press reset mid-SAVE | no hang after reset; counters show the abort; next SAVE works | |
| 10 | Referee: the disk from step 6 read by an independent reader (section 5.3) | directory + file identical | |

### 5.2 Round 2 (after M4, format)

| Step | Action | Expected |
|---|---|---|
| 1 | `OPEN 15,8,15,"N0:ALPHA,A1":CLOSE 15` on a blank | ≈ 80 × 2 track writes; `CNT_WR_TRACK` = 160, `CNT_WR_LOST` = 0, `WR_TRK_CYC` ≈ 9.99 M; the DOS's own verify pass passes; `0, OK`; directory shows 3160 blocks free |
| 2 | Fill the disk with files (a copier or a BASIC loop), `VALIDATE`, power cycle, LOAD some | all OK |
| 3 | Format a disk that was previously F011-formatted by the MEGA65 core, and one previously written by a real 1581 | both OK |
| 4 | Referee on the formatted + written disk | passes |

### 5.3 Referee options (any one suffices for the gate, all three are welcome)

1. **MEGA65 native core**: boot the MEGA65's own core, select the internal floppy as drive 8
   (freezer), `DIR` and `DLOAD` the file — the F011 decoder and the C65 DOS are independent of
   everything in this project.
2. **A real Commodore 1581 / CMD FD** on a C64 — community (the issue-#90 reporter has the
   hardware).
3. **Greaseweazle**: `gw read --format commodore.1581 disk.d81`, then `cmp` against the source D81
   on the PC — community (the AExp tester owns one); also the only instrument that shows the
   splice position and the precomp step on the medium (`../AExp/.research/scp_flux/` tools need a
   1581-sector twin for the structure scan; `precomp_step.py` works as is with the track mapping).

---

## 6. Community protocol (Discord)

Published with `WIP-V6-A21X1` (sector writes) and `A21X2` (format). Each recipe says what to do,
what to expect, and what to paste back (the diag dump and the step at which it was taken; the
Shell's QNICE console is reachable with the usual key combination, procedure in
`doc/1581_dd_debug_device.md`).

* **R1 Save and load.** Blank DD disk, tab closed. `SAVE"HELLO",8` a short program, power cycle,
  `LOAD"HELLO",8`, `LIST`. Expect identical; paste the dump if not.
* **R2 Write protect.** Same with the tab open: expect `26, WRITE PROTECT ON`, nothing written
  (format the disk afterwards elsewhere to prove it is untouched — or just trust `CNT_WR_GATE`).
* **R3 Stress.** paich64's SAV-WRITE tool, Internal 1581 on 9, D81 on 8, then the reverse; run 0;
  report the audit result and the dump.
* **R4 Format.** `OPEN 15,8,15,"N0:MYDISK,ID":CLOSE 15` on a blank; time it with a stopwatch
  (a real 1581 takes roughly 75–105 s, typically 90 s; the core should be in the same range);
  directory (3160 blocks free); fill; validate.
* **R5 Copy a D81 to a real disk and back.** Drive 8 = D81 image, drive 9 = Internal 1581; a C64
  1581 copier (the community knows which ones work on two 1581s — Dracopy, 1581 Copy, Maverick's
  1581 copier, JiffyDOS's own commands); then copy the real disk to a fresh D81 and compare the
  two D81s on the PC. This is the X-Copy round trip of the Amiga world and the strongest community
  evidence short of a referee.
* **R6 JiffyDOS.** Repeat R1 and R5 with `jd-c64.bin` + `jd-c1581.bin`.
* **R7 GEOS.** Boot GEOS from a D81 (or a real disk), save a document to the real disk, reboot,
  open it.
* **R8 Referee.** Anyone with a real 1581 or a Greaseweazle: read a disk written in R5 and report
  (and send the `.d81`/`.scp`).
* **R9 Reads still fine.** Your genuine-1581-written disks still read (the open read gate C4 of the
  book).

Report template: core version, board revision, disk brand/type, recipe + step, what happened, the
dump, and whether the disk reads elsewhere. The findings worker classifies: compare first, then
the counters (`CNT_WR_LOST`, `CNT_WR_ABORT` + `WR_REASON_ACC`, `WR_FIRST_MARGIN`,
`WR_DRQ_MARGIN`), then theories.

---

## 7. Risk register

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | The decoder's ID-CRC → `id_valid` latency makes the 22-byte splice land early/late | medium | calibrate `G_WR_GAP_BYTES` in the flux-model bench; ±2 bytes is harmless (spec 5.7); the referee shows the real position |
| 2 | DOS DRQ service slower than modelled on hardware (IEC interrupts, JiffyDOS) | low | `WR_DRQ_MARGIN` / `WR_FIRST_MARGIN` instruments; the FIFO gives 3 bytes of slack vs the chip's 1 |
| 3 | R3 timing closure (`qnice_clk` domain grows by ≈ 400 LUTs) | medium | the re-roll machinery (`build_all.sh`); the writer is registered logic with no long combinational paths; AExp R3 closed at +0.18 ns with the same writer |
| 4 | Our own write splice confuses our reader's A1-train qualification (round-13 history with F011 splices) | low–medium | W1/W2 read back through the real decoder; the splice lands in the 12 × `00` run, the easiest case |
| 5 | HD disk in the drive (electronics reject DD-rate flux) | user error | docs; DD only; `CNT_WR_LOST` stays 0 but the DOS verify fails — document the symptom |
| 6 | JiffyDOS 1581 uses m = 1 or other flags | unknown | S3 stretch; community R6 early |
| 7 | GEOS 1581 driver bypasses the DOS job queue | unknown | community R7; if it issues WD commands directly they are the same commands |
| 8 | A reset/eject mid-write tears a sector | by design | same as real hardware; documented |
| 9 | Mechanism controller power-up wedge (knocks) | known | docs (power cycle) |
| 10 | Source switch with a dirty DOS cache (JiffyDOS timing) | low | motor-on proxy in the idle gate; the switch presents a disk change which invalidates the cache |
| 11 | Image-mode regression in `fdc1772.v` | medium (big file, shared code) | golden trace + `phys_mode`-stripped diff + the #248 testbench |
| 12 | Burst-mode formats with N ≠ 2 (16 × 256 or 5 × 1024) write fine but cannot be read back here | by design | document; unchanged read scope |
| 13 | Verify is off on foreign-formatted disks (BAM byte 6 = 0): a silently failed write is not caught by the DOS | low | the engine's own instruments and the referee, never the DOS's verify, are the safety net |
| 14 | Stale cached side written onto a newly inserted disk after an aborted flush | inherent 1581 behaviour | document; the DOS, not the core, decides |

---

## 8. Decisions (maintainer, 2026-10-16: "all as recommended" — every item below is decided as recommended)

1. **OSM write switch.** Recommended: none (AExp precedent; the tab is the guard; the DOS reports
   it). Alternative: a "Internal 1581 writes: Allowed/Blocked" single-select in Drive Settings
   (one OSM bit, one gate term, `OPTM_SIZE` +1, config regenerated).
2. **Precomp default.** Recommended: follow the WD P bit at 140 ns, diag-selectable (`0x9A`).
3. **m = 1 multi-sector writes in the first build.** Recommended: implement as stretch in M2 if the
   re-issue pattern of reads carries over in a day; otherwise defer to M5 (the stock DOS never
   uses it; JiffyDOS unknown).
4. **Version.** Recommended: `WIP-V6-A21X1` for the sector-write alpha, `A21X2` for format, row in
   `doc/inofficial.md` "Write support for the built-in floppy drive as 1581 (issue #244)".
5. **Interim guard for the fake-finish bug** (spec 5.1, plan section 0): recommended: yes, a
   small change in `fdc1772.v` that completes the phys-mode Write Sector/Write Track with the
   Type-I minimum busy (`PHYS_T1_MIN_TICKS`, 1.5 ms) so the ROM's wait-busy poll sees the edge and
   the DOS reports `26, WRITE PROTECT ON` instead of freezing — worth an `A20X4` on its own if any
   user saves to a writable disk in Internal 1581 mode before M3 lands; otherwise folded into M3.
6. **Referee access.** Who in the community has a real 1581 and/or a Greaseweazle and is willing;
   whether the maintainer wants to use the MEGA65 native core as the first referee (recommended:
   yes, it is free and independent).
7. **V6 or later.** Not a planning input; recommended to decide after bench round 2.

---

## 9. Bookkeeping and conventions

* `tests/README.md`: prepend a `Version WIP-V6-A21 - TBD` section (Setext underline)
  with the gates of sections 5 and 6 as `@TODO`s; never edit older sections.
* `doc/inofficial.md`: one row per alpha with the hash the maintainer commits.
* `VERSIONS.md`: at release time, maintainer's wording.
* Config file: name follows `CORE_VERSION` (`c64mega65-WIP-V6-A21X1.cfg`), size unchanged unless
  decision 1 adds an item.
* Submodule first, then the parent pointer; no Claude co-author trailer (repo rule).
* `doc/the_1581_book.md`: chapter 18 ("The physical drive cannot write. Physically.") and C4
  become historical once M3 ships; add a chapter or an addendum rather than rewriting the book's
  claims in place.
* The chronicle of this milestone (decisions, findings, dates) goes into this file's section 10
  as it happens.

---

## 10. Chronicle

* 2026-10-15 — Planning session (controller): read the read-milestone handover, the normative
  spec's write sections, the AExp write spec/handover/writer source and flux results, the mega65-core
  F011 writer research, the current controller and WD model; three research agents mapped the
  AExp lessons, the current WD write path/pins and the 1581 DOS write behaviour (the latter by
  re-executing the genuine ROM in an extended emulator: command bytes, P-bit policy, flush order
  and timing, DRQ latencies, status decoding, verify, retries, format stream). Decisions proposed:
  single-pass real-time Write Sector, FIFO-room DRQ, index-to-index Write Track, AExp writer
  reused, no OSM switch, no outer safety island, follow-P precomp. Found the fake-finish bug.
  Wrote `WRITE-SPEC.md` v0.2, this plan, and the three research notes. Nothing coded, nothing
  committed.
* 2026-10-16 — Maintainer: all seven decisions of section 8 as recommended (no OSM switch, follow-P
  precomp at 140 ns, m = 1 as M2 stretch, `WIP-V6-A21X1`/`X2`, interim BUSY guard yes, MEGA65 native
  core as first referee, V6-or-later after bench round 2). Next: freeze the ABI, M1 brief.
* 2026-10-16 — M1a done (worker, Opus xhigh; branch `write-m1`, commits 02d8491, 0a54059, 0a014b6):
  pkg additions, `physical_1581_wfifo`, `physical_1581_mfm_encoder`, `physical_1581_writer`, three
  unit benches (wfifo 15k words, encoder 512/512 words against `mfm_flux_gen_pkg`, writer 2927 flux
  edges / 19 gate windows), 15 of 16 writer mutants killed (the survivor is equivalent). Controller
  review: git facts clean (only the six new/changed physical_1581 paths), the fast suite re-run
  green by the controller, the long benches re-run, and the controller's own check — the real
  encoder + writer streaming a complete ID + data record into the real read decoder: ID C/H/R/N and
  CRC ok, 512 bytes byte-exact, data CRC ok, WGATE window exactly 631 × 1600 cycles, with and
  without precompensation. Spec folded to v0.3 (writer `cut_i`, session = episode not gate term,
  immediate Force Interrupt, reason codes, media_ready abort term, encoder `ready_o`).
  Pre-existing breakage found: `tb_physical_1581_diag` does not compile on `mh_dev_drives` since
  c18c6d7 widened `img_drive_busy_i` to two bits (one-line port-map fix, scheduled for M3).
* 2026-10-16 — M2 done (worker, Opus xhigh, in its own worktree while M1b ran in the main tree;
  parent branch `write-m2` from 0a014b6: e1bb9d0 + 216cf1a; submodule branch `write-m2` from
  aa353e1: 54c2c29 + 650c6b5): `fdc1772.v` physical Write Sector / Write Track on the existing request
  channel (the WP pre-check and every write issue arm the 1.5 ms minimum busy, FIFO-room DRQ,
  data-register writes pushed into the external write FIFO, completion after the writer busy, status
  purity, m = 1 re-issue), the twelve new ports threaded through `c1581_drv`/`c1581_multi`/`iec_drive`,
  bench groups 14–24 of `tb_fdc1772_physical.sv` (212 checks), the image-mode golden trace bench
  `tb_fdc1772_image_golden.sv` with its recorded transcript, the `rom_emu` write model with 19 proofs
  and the fixtures `write_back_order.json` / `format_tokens.bin` (section 4 of the spec confirmed:
  flush 243.2 ms, 132–138 cycles between commands, 6,230 tokens per side, token latency 14–32
  cycles). Controller review: git facts clean (only `rtl/iec_drive` and `doc/dev-fdd/rom_emu`, the
  gitlink moved, no trailer, no generated file); the physical bench, the three golden runs (recorded,
  original, changed, changed with random activity on every new input: one md5) and both proof runs
  re-run green by the controller; the diff read hunk by hunk (every change phys-gated or a
  declaration; `cpu_we` is a one-cycle strobe, so one CPU write is one push); the controller's own
  check — three WD-side mutants through the bench: no minimum busy on a WP refusal → killed by
  group 18 (the ROM's `\$CBF4` poll never sees BUSY), write LOST DATA hidden from status bit 2 →
  killed by 16/17, the acceptance guard after feed fell removed → survives, equivalent under the
  `WR_TAIL` order of spec 5.3 (the controller drains before the done; the WD guard is belt and
  braces). The issue-#248 `sim_fdc` bench is not in the repository; the golden bench is the
  image-mode instrument from now on. Decisions folded into spec v0.4: four bytes ahead (the FIFO
  depth) is the contract; `WR_TAIL` drops feed first, waits for the writer plus 16 cycles, drains,
  then reports (plus the idle/acceptance drain of the write FIFO); the minimum busy at every write
  termination; WP alone forced on the WD side; `phys_wr_lost` held through the done until the next
  acceptance; m = 1 in scope; the double cancel toggle of a Force Interrupt documented. Observed and
  left alone: in image mode a zero-step Restore and the Write Track fake still drop BUSY within a
  microsecond (the round-11 hang class on the image side) — candidate for a separate issue. The
  branch is not buildable for hardware until M3 wires the ports; the submodule branch is fetched into
  the main submodule repository, the checkout and the rebase onto `write-m1` follow the M1b review.
* 2026-10-17 — M1b done (worker, Opus xhigh; branch `write-m1`: 8e2de2c, 3639a81, c299064): the
  controller's Write Sector and Write Track engines as `WR_*` states of the one request/done discipline
  (the encoder and the writer instantiated inside the controller, which owns the two pins), the
  writable rotating flux store in `mech_model_1581` behind `G_WRITABLE` (the old generator untouched),
  `tb_physical_1581_write` with scenario groups 1–5 (W1, W2 at 0/15/30 µs, W3, W4a/b, W5 + W5b, W6,
  W7, W8, W9, W10 in four precomp modes, W12, W13 on the store), `wr_twin.py` (edge-for-edge prediction
  and an independent decode of the flux dumps), `run_tb_write.sh`, seven controller mutants killed
  (one after a checker fix: the model now echoes WDATA onto RDATA under WGATE so an unheld decoder is
  observable), the gap calibration `C_WR_GAP_CAL_CYC = 488` (WGATE opens exactly 22 byte-times after
  the ID CRC in W1, within 35,099–35,299 cycles over 15 windows). Controller review: git facts clean
  (only `physical_1581` and its tests, no trailer); the whole existing suite re-run by the controller
  (the four model/controller benches end at their pre-change timestamps), all seven write groups and
  the twin re-run with the worker's exact numbers; the load-bearing code read (the writer's gate
  terms wired to the controller's own enable, motor request, media_ready, side, tab and change; the
  lost level cleared only at the next acceptance; the mechanics guard defers steps instead of dropping
  them; the abort terms and the writer-outcome mapping; the decoder held in reset while the session
  or the writer busy is up; the write FIFO drained in every non-consuming state); the controller's own
  check — W2 at a DRQ latency (7 µs) and a sector order the worker never used, writing the bitwise
  inverse of the pre-seeded flux: the bench green, the twin's independent decode of all ten records
  CRC-clean and equal to the streams, and a separate comparison against the seed formula proving every
  written sector is the exact inverse of what the track held. Spec folded to v0.5 (disk change as an
  edge for writes, the writer-outcome result mapping, WR_WAIT waits for an idle writer and the tab
  qualifier, the deferring guard, the cut window one clock short, the calibration, the diag tap names).
  The cross-boundary port check of section 4 passed (SV side, controller, wfifo). Not built and
  accepted as such: the W4 tab bounce inside the writer's few-clock ARM window, W11 (m = 1 is a WD-side
  re-issue of ordinary ops). Left for M3: `WR_TAIL` still drops the feed at the done rather than on
  entry (hygiene; both sides already drain the residue). Integration the same night: `write-m2`
  rebased onto c299064 (97a7898, e7ebd53), `write-m1` fast-forwarded, the submodule checked out at
  650c6b5, and the branch `write-support` created at e7ebd53 as the line M3 continues; M3 launched
  00:34 CEST. With Write Track and the genuine ROM's token fixtures in hand, M4 reduces to the format
  bench round and its documentation.
* 2026-10-17 — M3 done (worker, Opus xhigh; branch `write-support` from e7ebd53: 45d15bc diag map v8 +
  bench + debug doc, 5d5b1d0 `main.vhd`/`mega65.vhd`/the four tops, e01bba5 Shell Writing/Format,
  2828060 the four `.xpr`, ffd0aa8 controller feed-first `WR_TAIL` with the 16-clock guard, 83e6ee2
  `WIP-V6-A21X1` + `tests/README.md` + `inofficial.md`, 07efa80 README/FAQ/book/models): the two write
  pins routed from the writer through `main`, `MEGA65_Core` and the four tops (tie-offs gone, drive B
  still tied), the wfifo between `iec_drive` and the controller (write side on the drive clock with the
  QNICE reset synchronized into it), the twelve write ports of the drive wired, the diag at map v8
  (0x08FE, words 0x80–0x9D, `WR_CTRL` the one writable word via a new QNICE write strobe), the Shell
  classifying Writing/Format from bits 15:12 of the one word it already reads (busy mask unchanged,
  +116 ROM words), the three new sources in the project files, the docs. Controller review: git facts
  clean (22 files, only the allowed set, submodules untouched, no trailer, no `.rom`/`.cfg`, only
  additions in `tests/README.md`); the full GHDL suite re-run by the controller (12 benches, the four
  read benches at their exact previous timestamps, the repaired diag bench with 175 checks), write
  groups 2 (0/15 µs) and 5 with the twin, the iverilog bench (212 checks, submodule unchanged), the
  Shell ROM (27,182 of 28,672 words) and `menu_test.py verify`; the controller's own checks — the
  four tops' diffs read against AExp's block and shown identical modulo whitespace, the pin path
  traced (writer register reset `'1'` → controller and `main` ports defaulting `'1'` → `mega65` →
  tops, `f_wgate` assigned nowhere but the writer), and the differential `ghdl -a` of `main.vhd`,
  `mega65.vhd` and the four tops redone from an `e7ebd53` archive: identical diagnostic sets (12/10
  unit-not-found for the SystemVerilog and unseeded units, zero undeclared signals). Spec folded to
  v0.6 (the status word's write code, the corrected healthy-session balance, the extension words
  0x9B–0x9D, read counters count reads only, the three direct-done exits, the static gates incl. the
  LUT estimate); plan 5.1 step 2 corrected to `CNT_WR_WP` = 3. Nothing synthesized: the next step is
  the maintainer's Vivado build (R3, R6) and bench round 1 (section 5.1).

* 2026-10-17 — Vivado build (maintainer, Vivado 2022.2 on Ubuntu, `build_all.sh R3 R6` from
  07efa80; reviewed by the controller from the logs and reports): both boards `RESULT OK` on the
  first implementation, no re-roll — R3 WNS 0.165 ns / WHS 0.040 ns, R6 WNS 0.371 ns / WHS
  0.034 ns (the 10 October builds of the branch base 735841f: R3 0.328 / 0.038, R6 0.336 / 0.039).
  Utilization against that base, read from its Time Machine copy: R3 LUTs 36,297 → 37,419
  (+1,122), registers 26,168 → 27,175 (+1,007), LUT-as-memory +18 (the four-deep write FIFO),
  block RAM 178 tiles unchanged; R6 LUTs +1,067, registers +1,007, block RAM unchanged. The LUT
  delta sits inside the pre-registered 1,000–1,500; the register delta is about 200 above the
  600–800 estimate, which the map-v8 counters account for. Methodology (62 / 96 items) and DRC
  (211 / 215) counts identical to the base, the generic TIMING-9 / TIMING-10 CDC entries present
  before and after; no synthesis warning touches the write-path files; `f_wgate_o` / `f_wdata_o`
  placed as outputs on N3 / N4 on both boards; the qnice ↔ main false-path cut of `CORE.xdc`
  covers the FIFO crossing and every new synchronizer carries `async_reg`; Shell ROM 27,182 of
  28,672 words from the pre-synthesis hook. Next: bench round 1 (section 5.1).
