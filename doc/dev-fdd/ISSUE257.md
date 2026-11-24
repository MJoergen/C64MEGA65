# Issue #257: three changes after the hardware test of the Internal 1581

Entry point for anyone, human or coding agent, who picks up this work. paich64 tested writing with the internal drive (WIP-V6-A21X1, R6) and reported two deviations in comment 17 of issue #257: the first access after inserting a disk fails with `74,DRIVE NOT READY`, and a format takes 6 min 43 s. This file records the proven causes, the changes, every decision, the numbers, what was verified and how, and what the Vivado build and the hardware test still need to show. The write engine itself passed that hardware test; its record is `doc/dev-fdd/WRITE-SPEC.md` and `doc/dev-fdd/WRITE-PLAN.md`.

## 0. State

* **Where:** `develop`: six commits on top of `f9f3ca1` (`WIP-V6-A22X3`), the last one is the version `WIP-V6-A25` (section 7). The submodule `CORE/C64_MiSTerMEGA65` has two commits of its own on its branch `develop` (`803b661` and `8a3c962`); push the submodule before the main repository.
* **Done in simulation:** READY with the first index pulse (section 2), the read-ahead buffer (section 3), the error blink of a 1581 on the drive LED (section 4), the corrections of the test documents (section 6).
* **Not yet built with Vivado and not yet tested on hardware.** Section 10 lists what the build and the test need to show.

## 1. The evidence

All dumps are in comment 17 of issue #257 (decode them with the register map in `doc/1581_dd_debug_device.md`).

**First access after an insert.** Seen twice, both times with a disk that was inserted while the MEGA65 was on and the drive was idle: `SAVE` on a formatted disk (the C64 shows `READY.`, the file is not on the disk, error channel `74,DRIVE NOT READY,00,00`), and `N0:` on a blank disk (`74,DRIVE NOT READY,01,00`). The next access works. With the disk in the drive at power-on the first access works. The two dumps taken right after the failures ("10-pre" and "FMT-0") agree in every detail:

| Word | "10-pre" (difference to the dump before) | "FMT-0" (since power-on) |
|---|---|---|
| `CNT_STEP` (`0x18`) | +2: one step in, one step out (trace ring: `102A`, `1129`) | 12: six step pairs (five of them from the power-on without a disk) |
| `CNT_READOP` (`0x1A`) | +0 | 0 |
| `CNT_IDX_QUAL` (`0x16`) | +`0x35` = 53 | `0x35` = 53 (no index pulses without a disk) |
| `CTRL_STATE` (`0x04`) | disk-change latch clear, motor off, READY off | the same |

So the DOS switched the motor on, stepped in and out once, issued no read or write command, reported error 74, and the motor ran for 53 revolutions.

**Format.** `N0:` on the second try: `0 OK`, 3160 blocks free, 160 Write Tracks (`CNT_WR_TRACK`), 1791 read operations, and 2051 index pulses for the whole format: 12.8 revolutions per track side, where a 1581 needs about three. With verify on, a `SAVE` was "noticeably longer" too.

## 2. Cause and fix 1: READY waited for a second index pulse

**What the ROM does** (318045-02, `doc/dev-fdd/rom_emu/run_257_proofs.py`, proofs I1 to I5, cycle exact). A job on a stopped drive switches the motor on (`$CD63`) and lets 80 ticks of 10 ms pass (the tick is CIA timer B with 20000 cycles at 2 MHz, counted down at `$CE53`; the count 80 is set at `$B095`). Then it runs the readiness stage `$CD7B` once: it looks at the disk-change line first (PA7, `$CD83`); if PA7 shows a disk change it steps in and out (`$CD8A`, commands `$48` and `$68`), waits 18 ms and looks at PA7 again (`$CDA1`); only then it examines READY (PA1, `$CDAD` calls `$CDBC`: 30 reads within about 200 us, a single "not ready" read fails). Before a Read Address it examines READY once more, alone (`$CD08`). A failed exam is job error 3 = DOS error 74. There is no retry, and the motor stays on for about ten more seconds (`$CDE4`). The exam falls 0.8000 s after motor-on for an unchanged disk and 0.8263 s after a disk change (0.8303 s in WIP-V6-A28, whose steps take the 6 ms the ROM asks for: `doc/dev-fdd/ISSUE257-PART-E-FIXES.md`, section 8.2).

**What the controller did.** READY needed two index pulses of the current motor-on interval for a cold or changed disk; one pulse was enough only for a disk that had been qualified before and not changed since (`rotation_confirmed`, commits `b13d99e` and `bdd457b` of July 2026). That exception was made after the same error 74 on restarts of an unchanged disk; the two-pulse rule for cold media stayed because it seemed fine in every cold session. It only seemed so: after a power-on with a disk in the drive, the DOS's own start-up job takes the cold path and its failure is invisible, and every later access is a "restart of an unchanged disk". The first job after an insert with a stopped motor is the only one that shows the cold path to the user.

**Why it failed.** With two pulses, the job fails as soon as the first index pulse comes later than 0.62 s after motor-on (proof I2; 0.631 s at the step rate of WIP-V6-A28). The failing job of the emulation has exactly the signature of the two dumps: error 3, one step pair, no read or write command, the motor on for 11.030 s (proof I3). 53 index pulses in 11.030 s mean that the first pulse came between 0.465 s and 0.665 s after motor-on; since the job fails from 0.63 s on, both failing accesses had their first pulse 0.63 to 0.665 s after motor-on. So the mechanism of that R6 can take two thirds of a second from motor-on to its first index pulse (the read milestone had to assume a first pulse later than the 500 ms staleness deadline for an R3 in July, `doc/dev-fdd/handover_codex.md`), and a second pulse 0.2 s later misses the exam in a part of the spindle phases.

**The fix** (`physical_1581_controller.vhd`). READY asserts with the first index pulse of a motor-on interval, for every disk. It falls with the motor request, when no pulse arrived for 500 ms, on reset and on disable, as before. `rotation_confirmed` and the pulse counter are gone; `idx_seen` replaces them. The disk-change latch is untouched. With one pulse the job succeeds for a first pulse up to 0.82 s after motor-on (proof I4; 0.830 s at the step rate of WIP-V6-A28); that is the limit of the ROM itself, since READY cannot honestly assert without any sign of rotation.

**What the second pulse was for, and why it is not missed.** It was meant as a proof of rotation for an unknown disk. It never judged the speed (no period was checked), a second pulse came even from a disk that was still accelerating, and the rule already allowed one pulse for the common case. The protection that matters is elsewhere and unchanged: a missing disk keeps the disk-change line asserted, so the DOS's step pair cannot clear PA7 and the job ends with 74; reads are CRC-checked and retried; a Write Sector needs a CRC-valid ID of the right sector first; a Write Track starts at an index edge of its own; and every write engine state aborts when READY falls.

## 3. Cause and fix 2: every sector of a track cost a revolution

**What the ROM does** (proofs R1 to R6). It reads a track side with ten single Read Sector commands, starting with the sector after the one a Read Address returned and wrapping from 10 to 1 (cache fill `$C900`, verify `$CA00`). It issues the next Read Sector 66 to 68 us after the BUSY drop (95 us at the wrap) and 2.25 ms after a Read Address. On a real WD1772, BUSY drops right after the data CRC, and the next ID is still 1.1 ms away: ten sectors take 215 ms.

**What the core did.** Delivery v2 of `fdc1772.v` uses the read FIFO as a CRC quarantine: nothing is presented to the drive CPU before the controller's verdict on the data CRC, and then the sector is presented at disk pace, 512 bytes in 16.4 ms. So the request for the next sector arrives 16.5 ms after the previous sector ended on the disk. Its ID passed after 1.7 ms, its data field is in flight, and the controller waited a full revolution for the ID to come round again: 2032 ms for ten sectors in the emulation, 196 ms per sector in the RTL bench `tb_physical_1581_rdseq`, 12.8 revolutions per track side on hardware. A format of 80 cylinders takes 390 s in the emulation and took 403 s on hardware (`run_257_proofs.py` of WIP-V6-A28 prints 375.4 s: see the next paragraph). The older ROM models presented the bytes as they came off the disk, like a real chip, which is why the simulations of the write milestone did not show it.

**The fix:** a read-ahead buffer in the controller (`physical_1581_rdahead.vhd`, states `RD_ADOPT` and `RD_COPY` of the controller). After a clean Read Sector the controller keeps listening to the decoder and captures every sector that passes into a 512-byte buffer: a CRC-valid ID with N = 2, the data mark in time, exactly 512 bytes, a good data CRC. A Read Sector whose sector is complete in the buffer, or on its way into it, is served from the buffer: the controller waits for the capture to finish if necessary, copies the sector into the read FIFO (one byte per 16 clocks, 164 us) and completes like a live read. Everything else takes the live path, which is the code it was (with one correction, D15), and so does a request whose capture fails for any reason. The quarantine rule stays as it is, and the logic of `fdc1772.v` is untouched (D14): the drive CPU still never sees a byte of a sector whose CRC was not verified. The data served was captured on the unchanged, ready, settled medium: a step, a side change, the motor request falling, the loss of READY, the disk-change line, a Force Interrupt, any decoder reset and any operation other than an adopted Read Sector end the read-ahead. And it is at most 24 ms old, about one sector time: the next data mark that starts a capture replaces the sector in the buffer, and a sector that nothing replaces is released 24 ms after its own data mark (D13).

With the buffer, ten sectors take 232 ms in the emulation (nine of ten served from the buffer) and a format 102 s, against 100 s for a real chip. In WIP-V6-A28 `run_257_proofs.py` prints 87.5 s and 86.1 s: it extrapolates from the first cylinder, and the longer steps of that version move the first Write Track to another phase of the index; from the second side on a cylinder takes 1200.0 ms with either step time (`doc/dev-fdd/ISSUE257-PART-E-FIXES.md`, section 6).

## 4. The error blink of a 1581 on the drive LED

Ordered by sy2002 on 2026-11-14 ("1581 physical disk errors should be shown on the drive led"). A 1581 has two LEDs, and its DOS reports an error by blinking the power LED (CIA PA5), not the activity LED; the core showed only the activity LED (PA6 or WD1772 busy), so the error of a 1581 was invisible, unlike the error of a 1541, which blinks its one LED.

What the DOS does (proofs L1 to L4): while an error is pending, and while it retries a failing job, it toggles PA5 every 100.0 ms (`$CE11`); when the error is cleared it only stops toggling and leaves the line as it is, lit or dark. So only the toggling means "error", never the level.

The change: `iec_drive.sv` (submodule commit `803b661`) passes the power LEDs of the 1581 engines on as `pwr_led`; `CORE/vhdl/c1581_error_led.vhd` detects the blinking of one power LED; `main.vhd` lights the drive LED for the activity of a drive or for the lit phases of a blink. Bench and reasons: `CORE/vhdl/test/tb_drive_led/README.md`.

## 5. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | READY with the first index pulse for every disk; no memory of earlier qualifications. | Section 2. One rule instead of two, and the rule that the field has used for every restart of an unchanged disk since July. |
| D2 | The read latency is fixed in the controller, with a buffer of its own; `fdc1772.v` and the quarantine rule stay as they are. | The WD front end and its delivery contract are proven against the ROM (LOST DATA rules, status purity); a read-ahead only adds a second source for the same completed-sector transaction. |
| D3 | The read-ahead is used only when everything is perfect; a capture with a bad CRC is not reported, the request takes the live path instead. | The buffer can then only make a read faster, never make it fail: a marginal sector gets the same live attempt as before. |
| D4 | The read-ahead starts only after a clean Read Sector and ends with every other operation. | The first sector of every sequence goes the proven way, and no data that was captured before a write, a step or a disk change can be served. |
| D5 | The copy into the read FIFO takes one byte per 16 clocks. | The Gray-coded write pointer of the FIFO crosses into the drive clock over a false path; 320 ns between pushes make the crossing independent of routing. The sector pitch leaves about 3 ms. |
| D6 | The error blink is combined with the activity by OR, in the same green. | The LED is then never darker than before in any state: a ROM self-test failure flashes both LEDs of the 1581 in phase, and an exclusive or would hide it. A failed command leaves the drive idle, so the blink is visible where it matters. |
| D7 | A blink is three toggles in a row, each within 200 ms of the one before. | The reset of a drive forces the power LED off and releases it: two edges. |
| D8 | The error blink is not part of `img_drive_busy`. | A drive that only reports an error is idle; the Shell must not refuse a mode change in the lit phases. |
| D9 | The error blink applies to every 1581 engine, D81 images included. | It is the same drive with the same DOS; only the 1541 showed its errors so far. |
| D10 | No entry in `VERSIONS.md`. | The three changes improve features that were never released (the internal drive as a 1581, D81 images) and do not change what the entries of these features say. |
| D11 | Diagnostic map v9: counters for the read-ahead (`0x9E`, `0x9F`) and the time from motor-on to the first index pulse (`0xA0`, `0xA1`). | The hardware test can then show the margin of the READY exam and the effect of the buffer with numbers instead of impressions. |
| D12 | The changes go to `develop` as `WIP-V6-A25`. Decided by sy2002. | The build that paich64 tests needs a name of its own. |
| D13 | The read-ahead releases a held sector 24 ms after its data mark (`G_DATA_WD_CYC`, the counter that also bounds a capture). | Without it a sector stayed in the buffer for as long as no later sector replaced it, for example behind an unreadable ID. Its bytes would still be the bytes on the disk, because every event that can change them ends the read-ahead; but a hard bound on the age does not depend on that list being complete, and it is what the design promises: about one sector time. A request that comes later takes the live path, as before the read-ahead. |
| D14 | One comment in `fdc1772.v` is corrected (submodule commit `8a3c962`); its code is untouched. | The comment said that READY depends on the disk-change latch. The file without its comments is identical before and after. |
| D15 | A live Read Sector reports the deleted flag of its own data field (`rd_deleted_o` is taken at `data_end`, not at the data mark). | Section 6. It is the only change to the live read path, and it changes nothing for a disk without deleted data marks: the flag was 0 there before and is 0 now. |

## 6. Found on the way

* `rd_deleted_o` of a live Read Sector was sampled at the data mark, where the decoder still shows the flag of the previous data field (it sets `data_deleted_o` together with `data_end_o`): a sector with a deleted data mark reported 0, and the normal sector after it 1. The 1581 DOS masks this status bit (`$CD3F`), and its own disks have no deleted data marks, so nothing depended on it. With the read-ahead, whose path takes the flag where it is valid, the two paths would have disagreed. Fixed (D15): the live path reports the flag of its own data field.
* The ROM models of the read and write milestones (`machine.py`, `wd_write_model.py`) present the bytes of a Read Sector while the data field passes, like a real WD1772. That hides the latency of delivery v2. `run_257_proofs.py` has the delivery as the RTL does it; use it for anything that depends on read timing.
* The tester's dumps show the diagnostic head estimate (`HEAD`, `0x05`) off by 2 to 6 cylinders against the ID fields in sessions that start without a Restore. It is diagnostic only. Not changed.
* Four statements of the documents for WIP-V6-A21 did not hold on hardware and are corrected (`tests/README.md` section WIP-V6-A21, `doc/dev-fdd/WRITE-PLAN.md` 5.1, `README.md`, `FAQ.md`). `CNT_WR_WP` stays 0 when a disk is write-protected at its log-in: the DOS samples the tab then (`$CB76`) and refuses the write job by itself (`$CF8A`); the counter shows three attempts only when the tab is opened after the log-in. An eject or a reset in the middle of a `SAVE` leaves the abort signature only if it cuts a running write burst, and a burst takes about a quarter of a second. The DOS reads written sectors back only with its verify switch on, which it loads from the disk at every log-in (BAM byte 6): on for a disk formatted by a 1581 or by this core, off for a disk formatted by the MEGA65 core, and `U0>V1` switches it on. And formatting has been part of the core since WIP-V6-A21X1; the documents announced it for a later version.
* One track of the tester's disk F1 (cylinder 53, head 0) held a constant tone without address marks. It is not the handwriting of this core (the flux statistics differ from the tracks the core wrote) and did not show up again on F2 to F4. Unexplained, no action.

## 7. Commits

The six commits on `develop`, on top of `f9f3ca1`:

| Commit | Content |
|---|---|
| `1d19895` | READY with the first index pulse of a motor-on interval: `physical_1581_controller.vhd`, the media-contract bench and its runner with 17 mutants |
| `ab81a1a` | The error blink of a 1581 on the drive LED: `c1581_error_led.vhd`, `main.vhd`, the four `.xpr`, the bench `tb_drive_led`, and the submodule `CORE/C64_MiSTerMEGA65` at `8a3c962` (`803b661`: `pwr_led` of `iec_drive.sv`; `8a3c962`: a comment in `fdc1772.v`) |
| `7ceefa0` | The read-ahead buffer: `physical_1581_rdahead.vhd`, the controller states `RD_ADOPT` and `RD_COPY`, the deleted flag of the live path (D15), diagnostic map v9, the benches |
| `18edba5` | `doc/dev-fdd/rom_emu/run_257_proofs.py`: the genuine-ROM proofs |
| "Docs: the Internal 1581 after the hardware test of issue #257" | The documentation: this record, the 1581 book, the debug device, the corrections from the hardware test, the dump decoder and the regression tools in `doc/dev-fdd/tools`, `AGENTS.md` |
| "WIP-V6-A25" | The version: `config.vhd`, the test section in `tests/README.md`, the row in `doc/inofficial.md` |

The two submodule commits are on the branch `develop` of the submodule and local until pushed: push the submodule before the main repository.

## 8. Numbers

| What | Value | Source |
|---|---|---|
| READY exam of the ROM after motor-on | 0.8000 s for an unchanged disk, 0.8263 s after a disk change (WIP-V6-A28: 0.8303 s) | proofs I1, I5 |
| Latest first index pulse that still passes | 0.62 s with two pulses (0.63 s fails), 0.82 s with one pulse (0.83 s fails); WIP-V6-A28: 0.631 s and 0.830 s | proofs I2, I4 |
| First index pulse in the two failing accesses on the tester's R6 | 0.63 to 0.665 s after motor-on | 53 pulses in the 11.030 s the motor ran, proof I3 |
| Next Read Sector of the DOS after the BUSY drop | 66 to 68 us (95 us at the wrap from 10 to 1), 2.25 ms after a Read Address | proof R1 |
| First status poll of the DOS after a command | 49 CPU cycles = 24.5 us (`$CBF5` to `$C969`); the earliest data byte from the buffer comes 165 us after the command | disassembly |
| Ten sectors of a track side, genuine ROM in the emulator | 215 ms real WD1772, 2032 ms delivery v2 alone, 232 ms with the read-ahead (9 of 10 from the buffer) | proofs R2 to R4 |
| Ten sectors, RTL bench `tb_physical_1581_rdseq` | 1965 ms before (9 sectors waited a revolution each), 225 ms now (9 from the buffer, no sector waited) | section 9 |
| Format of 80 cylinders | 100 s real chip, 390 s delivery v2 alone (403 s measured on hardware), 102 s with the read-ahead; as printed in WIP-V6-A28: 86.1 s, 375.4 s, 87.5 s (the phase of the first Write Track, `doc/dev-fdd/ISSUE257-PART-E-FIXES.md` section 6) | proofs R5, R6 |
| Copy from the buffer into the read FIFO | 512 bytes at 16 clocks = 164 us, done 64 clocks later | RTL |
| Oldest byte the buffer can serve | 24 ms after its sector's data mark (`G_DATA_WD_CYC`) | RTL, unit bench P1 to P14 |
| Error blink of the DOS | the power LED toggles every 100.0 ms | proof L2 |
| Blink detector | three toggles in a row, window 6,400,000 cycles = 195 to 204 ms at the core clocks | RTL, `tb_drive_led` |
| Buffer of the read-ahead | 512 x 8, one synchronous write port, one synchronous read port (block RAM or distributed RAM) | GHDL synthesis: "found RAM" |

## 9. Verification record

Everything below ran on the final RTL and benches (the tree of commit `7ceefa0` with the proofs of `18edba5`; the two commits after them hold the documents, the tools and the version string).

* **Genuine ROM.** `run_257_proofs.py`: the boot check and the 15 proofs I1 to I5, R1 to R6 and L1 to L4 pass (`RESULT: ALL 257 PROOFS PASS`). `run_proofs.py` and `run_write_proofs.py`, the proofs of the read and of the write milestone, pass unchanged.
* **READY.** `tb_physical_1581_media_contract` checks the contract with monitors on every clock. `run_tb_media_contract.sh`: the bench passes and rejects 17 of 17 mutants of the controller (READY gated by the latch, after two edges, from an edge with the motor off, without an edge, kept at motor-off or on disable, dropped by a step, by a raw change or at an edge; staleness that never drops, drops for one clock, does not restart or is 3 percent long; a latch that follows the raw line or is cleared by the release or by an index edge). An independent review of the change, with the specification and the commit only: no RTL defect.
* **Read-ahead, engine.** `tb_physical_1581_rdahead`: 100 checks, end at 657,571 ns. `mutants_rdahead.py`: 35 of 35 mutants of the engine are rejected, among them the mutants of the age rule D13.
* **Read-ahead, controller on a synthetic record stream.** `run_tb_rdahead_ctl.sh`: the bench passes (scenarios S1 to S19; 12 sectors from the buffer, 2 adoptions given up) and rejects 18 of 18 mutants of the controller: every kill term that acts alone, the track compare, a copy during a capture, the buffer reserved from the commit clock on, the release of a served sector, the done gap, cancel during the copy, the push pace, a dropped push, the arm, the deleted flag on both paths, and the age rule at the controller level.
* **Read-ahead, closed loop** (controller, production FIFO, mechanism model). `tb_physical_1581_rdseq` reads a track side the way the DOS does. With the request 67 us after the BUSY drop, ten sectors take 225.154 ms (limit of the acceptance run: 260 ms), 9 of them from the buffer, none waits for a revolution, no wrong byte. The same bench with other distances between the BUSY drop and the next request:

  | Distance | Sectors | Time | From the buffer | Waited a revolution |
  |---|---|---|---|---|
  | 0 us | 10 | 225.087 ms | 9 | 0 |
  | 67 us (the DOS: 66 to 95 us) | 10 | 225.154 ms | 9 | 0 |
  | 3200 us | 10 | 422.280 ms | 8 | 1 |
  | 10000 us | 4 | 698.796 ms | 0 | 3 |

  A request that comes later than about 3 ms finds its sector replaced by the capture of the next one and takes the live path, which waits for the sector to come round: that is the behavior from before the read-ahead, and no byte is wrong in any of the runs. `tb_physical_1581_rdahead_loop`, groups 1 to 5 (adoption, the kill events, the failing captures, the pending request, the races of one clock): all pass. Groups 6 and 7 of `tb_physical_1581_write`: after a Write Track and after a Write Sector the sector that the buffer held is read live and returns the new data (group 6); ten sectors written and read back in the DOS's verify order are byte-exact, 9 of them from the buffer, in 215.5 ms (group 7).
* **Independent review of the read-ahead**, with the specification and the commit only and with mutants of its own: no path found that breaks the rule "never an unverified byte, never another sector, never a byte older than the last event that can change the flux, never residue". The one deviation from the specification, the buffer reserved for the copy from the commit clock on, is needed: without it a data mark in that clock starts a capture into the buffer that is being copied (a mutant of the closed loop and one of the fast bench show it). From the review: the deleted flag of the live path (D15), and two gaps in the tests (the track compare, the release of a served sector), which the fast bench closes. A second pass over D13 and D15: no defect.
* **Regression of `CORE/vhdl/physical_1581`** as the job queue of `doc/dev-fdd/tools/regression`: 27 jobs, 7.6 core hours, all pass. End of the simulations: `tb_physical_1581_controller` 1,431,124,570 ns (unchanged against the READY commit), `tb_physical_1581_ovf` 405,026,450 ns, `tb_mech_model_1581` 211,646,410 ns, `tb_physical_1581_diag` 18,401,312 ns; the loop groups 1 to 5 at 772.459, 1835.330, 1352.134, 868.930 and 1178.180 ms; the write groups 1 to 7 of `run_tb_write.sh` (group 2 with the DRQ latencies 0, 15 and 30 us) each with `ALL TESTS PASSED`, no refused push and no underrun of the writer, and with the independent twin `wr_twin.py` passing on every written stream, the red control (flipped precompensation must fail) included.
* **Unit benches** (`units.sh`): CRC, MFM decoder, MFM encoder, the A/B harness of the quantiser, input synchronizer, read FIFO, write FIFO and writer pass. Of the sources they test, only `physical_1581_mfm_decoder.vhd` changed, in one comment line: the file without its comments is identical to the one of `f9f3ca1`.
* **`fdc1772.v`:** the file without comments and white space is identical before and after `8a3c962`, and its bench `tb_fdc1772_physical.sv` (Icarus Verilog, 212 checks) passes on that commit.
* **`main.vhd`:** differential GHDL analysis against `f9f3ca1` with the entities of `physical_1581`, the read-ahead engine and `c1581_error_led` bound (`main_diff_check.sh`): 13 diagnostics on both sides, identical (only sub-entities that are not in the library); the same for each of the three RTL commits. The runners that analyze `main.vhd` pass: `tb_shortcuts`, `tb_stereo_mix`, `tb_capslock`, `tb_turbo`, `tb_ntsc`.
* **Drive LED:** `tb_drive_led/run.sh` passes: the detector with 6 mutants, the LED equations for all 256 combinations with 3 mutants, the detector instances with 4 mutants, the port map of `iec_drive`, and the differential analysis of `main.vhd`. An independent review of the change: no RTL defect.
* **Markdown:** the lines that these commits add or change contain no bare dollar sign, no bare `==` and no bare angle bracket outside of code.

No simulation here shows three things: that the design meets timing, how long real drives take to their first index pulse, and that `pwr_led` follows CIA PA5 of the right drive inside the SystemVerilog hierarchy (`c1581_drv.sv`, `c1581_multi.sv`, `iec_drive.sv`: three assignments of one line each). Section 10 hands them to the build and to the hardware test.

## 10. What the Vivado build and the hardware test need to show

Vivado (R3 and R6 at least):

* Timing is met in every clock domain. The new logic is in the 50 MHz domain of the controller (the QNICE clock) and in the main clock domain (the blink detector, two instances). The read multiplexer of the diagnostic device has four more words; it is on the half-cycle read path of the QNICE devices, and `qnice_clk` had 0.188 ns (R3) and 0.487 ns (R6) of slack in the WIP-V6-A22X3 builds.
* The synthesis log shows how the buffer `mem` of `physical_1581_rdahead` was built: a RAMB18 or distributed RAM. Both are right. No latch and no new critical warning for `physical_1581_rdahead.vhd` and `c1581_error_led.vhd`.
* Block RAM: 274 of 365 tiles in the WIP-V6-A22X3 builds; one more at the most.
* The submodule `CORE/C64_MiSTerMEGA65` is at `8a3c962`.

Hardware (the section `Version WIP-V6-A25` of `tests/README.md`):

* Not a single `74,DRIVE NOT READY` as the first access after inserting a disk, on R3 and on R6. `SPINUP_MAX_MS` (`0xA1`) of every board: it is the margin of the READY exam (800 ms) on real mechanisms, and nobody has measured it yet. A value above 800 that comes from a motor-on interval without a disk is no fault (`doc/1581_dd_debug_device.md`, section 2.3).
* A format in about 1 min 45 s; `CNT_RD_AHEAD` about nine tenths of the Read Sectors; `CNT_RD_AHEAD_DROP` 0 or small; no CRC, RNF or LOST counts on a healthy disk.
* The error blink on the drive LED for a D81 image and for the internal drive, and no blink where there is no error.
* Decode the dumps with `doc/dev-fdd/tools/diag_dump_decode.py`.

Open remarks, none of them a defect:

* A drive with JiffyDOS in its 1581 ROM, or custom drive code, may toggle the power LED on its own; the blink detector has only been checked against the stock ROM.
* The error blink of a 1541 is, as before, a blink of its activity LED, so it still counts as activity for the mode change in `Drive Settings`; only the blink of a 1581 does not.
* The Gray-coded pointers of the read FIFO cross between the two clocks over a false path. The copy from the buffer keeps 320 ns between pushes for that reason (D5); a bus-skew constraint on the pointers would make the crossing independent of that spacing.
* The 1581 book and the issue #90 specification still carry a few statements from July that later work has overtaken (the diagnostic device as read-only, the state of the write path and of the drives). They are outside of this change.

## 11. Tools

* `doc/dev-fdd/rom_emu/run_257_proofs.py`: the genuine-ROM proofs (`python3 -I`, about 6 minutes).
* `doc/dev-fdd/tools/regression/`: the simulation regression of section 9 as a job queue (`reg_setup.sh`, `reg_queue.py`, `jobq.py`, `reg_check.py`), the runner of the small unit benches (`units.sh`), the mutants of the read-ahead engine (`mutants_rdahead.py`) and the differential analysis of `main.vhd` (`main_diff_check.sh`). How to run it: `doc/dev-fdd/tools/README.md`.
* `CORE/vhdl/test/tb_physical_1581_controller/run_tb_media_contract.sh`: the media contract and its 17 mutants (half an hour; in WIP-V6-A28 31 mutants, with nvc and GHDL, 40 minutes: `doc/dev-fdd/ISSUE257-PART-E-FIXES.md` section 8.1).
* `CORE/vhdl/test/tb_physical_1581_controller/run_tb_rdahead_ctl.sh`: the controller's read-ahead on a synthetic record stream and its 18 mutants (a quarter of an hour).
* `CORE/vhdl/test/tb_physical_1581_controller/run_tb_write.sh <scratch> [group:latency ...]`: the closed-loop write groups with the twin check; `JOBS` limits how many run at the same time. Its exit status is that of the twin check: read the line `group G latency L us: rc=...` for the verdict of the simulation.
* `CORE/vhdl/test/tb_drive_led/run.sh`: the drive LED.
* `doc/dev-fdd/tools/diag_dump_decode.py <comments.json> [comment numbers]`: decodes the dumps of the diagnostic device that testers paste into an issue (`gh api repos/MJoergen/C64MEGA65/issues/257/comments --paginate > comments.json`).
* The closed-loop benches take their run recipe from their header comments; one simulated second of the controller costs about 17 minutes of wall time (47 minutes with the writable disk model).
