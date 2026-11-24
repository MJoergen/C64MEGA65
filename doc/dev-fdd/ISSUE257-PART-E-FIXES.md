# Issue #257, part E: the fixes (Internal 1581)

Entry point for anyone, human or coding agent, who picks up this work. paich64 ran part E of the test plan of issue #257 (everyday operation: scratch, rename, copy, validate, copy programs, JiffyDOS) with WIP-V6-A25 on his R3A with the drive mechanism of his R6 and reported in comments 34 and 35. The causes of what did not pass are recorded in `doc/dev-fdd/ISSUE257-PART-E.md` ("the analysis" below), with the evidence, which this file does not repeat. This file records the three changes and the instruments that follow from the analysis: the rule of each change as built, why it is safe, what it does not do, every decision with its reason, the numbers, what each change was verified with, and what the Vivado build and the hardware test still need to show.

## 0. State

* **Where:** branch `mh_fix_257_part_e` of the main repository, on top of `develop` at `6171d22`, and branch `mh_fix_257_part_e` of the submodule `CORE/C64_MiSTerMEGA65` (commit `c7907bf` on top of `8a3c962`). Push the submodule before the main repository.
* **Version:** `WIP-V6-A28` (D16). The version string stays as it is; A28 also contains the fix of the file browser (MiSTer2MEGA65 issue #84). Nothing of this is released: the internal drive as a 1581 is a feature of the unreleased version 6.
* **Done in simulation:** READY while the head moves (section 1), the step rate (section 2), the decoder's tolerance for a weak first sync byte (section 3), the diagnostic map v10 (section 4).
* **Not yet built with Vivado and not yet tested on hardware.** Section 9 lists what the build and the test need to show; the test plan is the part "Internal 1581" of the section `Version WIP-V6-A28` of `tests/README.md`.

| # | Change | Where | Commit | Cures |
|---|---|---|---|---|
| 1 | READY does not count the time in which the head moves | `CORE/vhdl/physical_1581/physical_1581_controller.vhd` | `6f02582` | `74,DRIVE NOT READY` after `UI` and after every other recalibration (analysis section 2) |
| 2 | The head steps at the rate the Type I command asks for | `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v` | submodule `c7907bf`, pointer and proofs `e25d93b` | the head that is 2 cylinders short after a long seek (analysis section 3) |
| 3 | The decoder tolerates a weak first sync byte | `CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd` | `04c0801` | the sector header that could not be read (analysis section 4) |
| 4 | Diagnostic map v10 | `CORE/vhdl/physical_1581/physical_1581_diag.vhd` | `d66db79` | the two inferences of change 1 become measurements on the hardware; a count and a switch for change 3 |

The other commits of the branch: `5338987` (the ports of the tolerance switch and of its counter through the controller and `main.vhd`), `365a783` (the specification of these changes), `5b1be2e` (the READY rule on the genuine ROM: `doc/dev-fdd/tools/part_e/mfcwt_74`), `d3ac6c0` and `a5f40d0` (the model and the survey of the tolerance, the flux benches with the switch: `doc/dev-fdd/tools/part_e/format_stop`).

Change 2 must not ship without change 1 (D15).

## 1. READY while the head moves

**What the tester saw.** Under JiffyDOS, MFCWT 1.6 (Multi Floppy Commander with Turbo, a cartridge) reported `REREAD DIRECTORY FIRST` or `REREAD TARGET DIRECTORY` at almost every check before a format or a file copy, and the error channel read `74,DRIVE NOT READY` (analysis section 2).

**The cause.** MFCWT sends `UI` before every check, and the DOS recalibrates the head inside that command: a Restore of 39 steps, then a Seek of 39 steps back to the directory cylinder. READY (`media_ready`) fell when no index edge had arrived for 500 ms (`2 * G_PERIOD_MAX_CYC`) while the motor was on. The mechanism of the tester's R6 most likely delivers no index pulses while it steps (inferred from the timing of the failures, not observed; the TEAC FD-235HF, for example, gates INDEX until 15.8 to 17.9 ms after the last step pulse). The two trains then hid two index pulses in a row, READY was low for some tens of milliseconds after the Seek, and the DOS examines READY once per job and does not retry. A genuine 1581 passes the same sequence: the READY of its mechanism does not depend on the head moving.

**The rule as built** (`physical_1581_controller.vhd`, the readiness part of the main process; its comment states the rule and its reason):

1. READY rises in the clock after the first index edge of a motor-on interval, also when that edge arrives while the head steps.
2. READY falls with the motor request, on reset, on disable, and when no index edge arrived for 500 ms of settled time.
3. Settled time is every clock in which the step engine is idle (`step_st = SI_IDLE`) and the head has settled (`head_settled = '1'`). `head_settled` falls when a step is accepted and rises `G_SETTLE_CYC` (18 ms) after the trailing edge of that step's pulse. In every other clock `idx_gap_cnt` is held at zero, so the 500 ms start anew when the head has settled.
4. An index edge restarts the count and sets `idx_seen` whenever it arrives, during a step as well.
5. Unchanged: the disk-change latch, the conditions of the read engine, of the write engine and of the read-ahead that use `media_ready`, and the spin-up measurement.

Both terms of rule 3 are needed. When `G_SETTLE_CYC` is shorter than the recovery time of a step, `head_settled` rises during the recovery, and only the term of the step engine holds the count there; the benches run with both ratios (section 8).

**Why it is safe.**

* A disk that is taken out while the head moves is noticed 500 ms after the head has settled instead of 500 ms after its last index pulse. In between, the disk-change line guards the data as it did. Its latch is set by the raw line and cleared only by a completed step with the line released, so steps without a disk cannot clear it. The DOS's readiness stage looks at the change line first and ends the job with 74 after its step pair, as under the old rule; the exam of READY before a Read Address comes only after that stage. The read engine aborts on the level of the latch in every state, the write engine on its edge. A Write Sector opens the gate only behind a CRC-valid sector header and a Write Track only at an index edge, so no gate opens without a disk, and when READY falls the write engine aborts as well.
* A disk that is exchanged during a train has its change latch cleared by the train's own steps, as on a genuine 1581.
* Without a disk there are no index edges, so READY can stay high only if it was high when the disk left; the guards above cover that case.
* The limit of the rule: on a mechanism that hides its index pulses, READY stays up as long as the hold time plus one revolution is shorter than 500 ms plus the settle time, about 318 ms (320, 319 and 318 ms at 3.03, 6 and 12 ms per step, computed with the rule of the harness for index phases in steps of 2 ms). The known hold time is below 18 ms.

**What it does not do.**

* It does not bound the suspension (D2): steps without end, a disk in the drive or not, keep READY at its last value for as long as they come closer than 500 ms plus the settle time.
* It does not notice a disk that is pulled during a seek before the head has settled, and a mechanism whose hold time exceeds about 318 ms would still lose READY.
* It does not change what READY needs to rise, the first index edge. A first index pulse later than the exam of the ROM (0.800 s after motor-on for an unchanged disk, 0.830 s after a disk change) still fails the first job: that is the limit of the ROM itself (`doc/dev-fdd/ISSUE257.md`, section 2).

## 2. The step rate

**What the tester saw.** After every long seek on the R6's mechanism the head was 2 cylinders short of where the DOS wanted it: the Read Address after a recalibration found cylinder 37 with the track register at 39, and the DOS corrected it with a Seek of two steps and a second Read Address (analysis section 3). Single steps and moves of two steps never slipped, and the data were never at risk.

**The cause.** In physical mode the seek machine of `fdc1772.v` requested one step from the controller and went on with the next one as soon as the controller acknowledged it. The acknowledge comes after the direction setup (24 µs), the pulse (4 µs) and the recovery (`G_STEP_REC_CYC`, 3 ms; `G_STEP_REV_CYC`, 4 ms after a reversal) of the controller's step engine: 3.03 ms per step, 4.03 ms after a reversal, whatever the rate bits of the command said. The 1581 ROM issues Restore `$08`, Seek `$18`, Step `$28`, Step In `$48` and Step Out `$68` (stored at `$C30C` to `$C340`): rate bits 00, which a WD1772 turns into 6 ms per step. So the head stepped twice as fast as on a 1581, at the limit for which mechanisms of this kind are specified, and the R6's mechanism lost two cylinders in a long train, in either direction. That the pace is the reason is inferred: it is what a stepper motor does that drops one electrical cycle.

**The rule as built** (`fdc1772.v`; everything is behind `phys_mode` or acts on `phys_rate_cnt`, which only the physical branch loads):

1. When the seek machine requests a step in physical mode, `phys_rate_cnt` is loaded with the rate time of the command's bits r1 r0 (`phys_rate_ticks`, 20 bits): 6, 12, 2 or 3 ms for a WD1772, that is 48000, 96000, 16000 or 24000 ticks of the 8 MHz clock enable. It is loaded two ticks short, so that the next request comes exactly one rate time after this one.
2. While `phys_rate_cnt` is not 0, the Type I machine does nothing: no evaluation of track 0 or of the target, no next step, no verify, no end of the command.
3. The acknowledge of the controller stays the lower bound: the machine goes on only when the count has run out and the step is acknowledged. The pace is the larger of the two times: 6 ms for the codes of the ROM (12 ms if its probe of the CIA TOD clock at `$C36A` fails and it switches to `$09`, `$19`, `$29`, `$49`, `$69`; in the core the TOD input of the 8520 is `ph2_f`, so the probe passes), and the acknowledge for the codes 10 and 11 (3.03 ms, 4.03 ms after a reversal).
4. BUSY of a command with n steps lasts the sum of its n paces plus two ticks of the 8 MHz clock enable (Step, Step In, Step Out) or three (Seek, Restore). BUSY of a command without a step is the minimum busy time `PHYS_T1_MIN_TICKS`, 1.5 ms, as before.
5. Every accepted command clears `phys_rate_cnt`, and in physical mode it starts the Type I machine in state 0 (D7).
6. Unchanged: the image path (its table `step_rate_clk` and its handling of `seek_state`), the track register, the Restore bound of 255 steps, the verify option, and what a Force Interrupt does to a running command.

What it means for the DOS: a Seek over 39 cylinders takes 234 ms instead of 119 ms, one over 50 cylinders 300 ms, one across the disk (79 cylinders) 474 ms. The step pair of the readiness stage after a disk change takes 12 ms instead of 8.06 ms, so the exam of READY after a disk change comes 0.830 s after motor-on instead of 0.826 s.

**Why it is safe.**

* Nothing changes for disk images: the image branch is untouched, its golden trace is byte-identical, and the golden trace rejects a mutant that paces the image path as well.
* The settling of the head is as before. The controller's read and write engines wait for `head_settled` (18 ms after the last pulse), and after every Type I command the DOS waits 18 ms itself (the delay at `$CBD5`, called at `$CB1E` after a Restore, at `$CD9C` after the step pair and at `$CE9C` after a Seek), so BUSY that ends about 6 ms after the last pulse changes nothing.
* Track 0 is examined after the rate time: a Restore whose track 0 sensor answers between the acknowledge and the end of the rate time ends with the right number of steps.
* The format does not become slower: the Write Track after the Seek of one step waits for its index pulse anyway (1200.0 ms per cylinder from the second side on in the genuine-ROM emulation, with the step time of WIP-V6-A25 and with the new one alike).
* At 6 ms per step a long seek lasts longer than the 500 ms that READY tolerated without an index pulse before change 1; hence D15.

**What it does not do.**

* Whether the R6's mechanism stops losing two cylinders at 6 ms can only be shown on the hardware (section 9).
* It does not close the corner in which the controller loses a step request after a Force Interrupt (section 6).
* The image path keeps its own table, which wraps for 12 ms and above (section 6).
* The verify option, which the ROM never sets, verifies 18 ms after the last pulse (the controller's settle time, after the rate time), where a WD1772 waits the rate time plus 15 ms.

## 3. The decoder's tolerance for a weak first sync byte

**What the tester saw.** One format from DraCopy under JiffyDOS stopped after track 78 with error 20: the verify of cylinder 77, side H=1, did not find sector 7 (analysis section 4).

**The cause.** In that pass the first of the three sync bytes in front of the ID of sector 7 was recorded weakly: its flux intervals were 6.47, 6.88, 6.75, 7.80 and 5.60 µs where 6, 8, 6, 8 and 6 µs are nominal (peak shift), the same in every revolution of the capture. The quantiser classifies every interval alone against the midpoints at 2.5 and 3.5 times its estimate of the half cell. The long interval of 6.88 µs fell below the midpoint between "medium" and "long", the candidate of that byte was lost, and a mark needed three candidates at the exact spacing. The header was invisible in every revolution, and the verify of a format has no retry. A WD1772 times every transition against a recovered clock and would most likely have read the header (a judgment: nobody read that track on a 1581).

**The rule as built** (variant A, D9; `physical_1581_mfm_decoder.vhd`, whose header states it):

1. While the parser is idle and `tol_off_i` is low, the decoder accepts the byte after a train of two sync candidates as the mark: two candidates (the second and the third sync byte) at the exact spacing of five gaps, each with a valid complete-word span.
2. `FE` opens an ID. Such an ID is reported only with a good CRC. With a bad CRC it leaves no trace: no `id_valid_o`, and the arm of the data mark and N of the last ID stay as they were.
3. `FB` or `F8` opens a data field only when a CRC-valid ID armed it and the zero run ended 7 to 11 gaps (`C_QUANT_SYNC_LAT + 1` to `C_QUANT_SYNC_LAT + C_QUANT_A1_SPACING`) before the first candidate of the pair: the window of a train of three, moved by the five gaps of the lost sync byte.
4. The CRC engine receives the `A1` of the lost byte before the mark, and the mark two clocks later (the engine buffers one byte), so the field is checked exactly as after three sync bytes.
5. A train of two never re-anchors an open field; the re-anchor of the parser on a qualified ID mark stays a matter of trains of three.
6. A weak second or third sync byte is not tolerated (D11).
7. `tol_hit_o` pulses once per mark accepted on a train of two. The other diagnostic outputs `a1_candidate_o`, `a1_span_reject_o`, `a1_train_o`, `mark_fe_o`, `mark_dam_o` and `dam_unarmed_o` keep their meaning (trains of three only) and are identical with and without the tolerance; `locked_o` is set also when a mark is accepted on a pair.
8. With `tol_off_i` high the decoder is the decoder without the tolerance, on every output and in every clock. The tolerance exists only with the production values of the sync generics (`C_TOL`, D12).
9. `tol_off_i` comes from bit 0 of `RD_CTRL` of the diagnostic device (`dec_tol_off_o` of the device, `dec_tol_off_i` of the controller); it is 0 after reset, so the tolerance is on.

**Why it is safe.**

* On the twelve flux captures of the issue it changes nothing but the ID and the data field of that sector (section 8): no field lost, none changed, no ID or data field with a bad CRC, and every gained field confirmed by an independent PLL decoder.
* It does not reopen what the three-byte rule closed. That rule exists against false syncs at write splices. The captures hold 9,894 sectors that the core rewrote one at a time, with their splices; in all twelve captures there is exactly one train of two outside the weak header, and the byte after it is three or more bits away from `FE`, `FB` and `F8`. Splice junk produces isolated candidates.
* A false `FE` on a pair does no harm on its own: its ID is silent unless its CRC is good (a chance of 1 in 65,536 for junk), so it can neither end a Read Address with an ID CRC error nor disarm the data mark of the ID before it.
* A data mark on a pair needs a CRC-valid ID and the lock-up run in front of it, as a data mark after three sync bytes does.
* The CRC covers three `A1` as before, so the drive CPU still never sees a byte of a sector whose CRC was not verified.

**What it does not do, and the residual risks** (a judgment):

* It does not change the quantiser: an interval near a midpoint is still classified alone (variant B was rejected, D9), and a weak second or third sync byte still hides its field.
* A false pair followed by `FE` in junk opens an ID for about 200 µs, which stays silent unless its CRC is good. A real data mark after a train of three within those 200 µs would be missed for that revolution. At a start splice the twelve zero bytes in front of a data mark prevent that, and the train of three of a real ID re-anchors the parser.
* A disk from another drive whose write splices produce two clean candidates at the exact spacing followed by `FE` is the case the captures do not contain.
* A weak first sync byte in front of a damaged data field now gives a CRC error where it gave "record not found"; the DOS retries both.

## 4. Instruments: diagnostic map v10

| Word | Name | Definition |
|---|---|---|
| `0xA2` | `IDX_GAP_MAX_MS` | the longest time between two index edges in a row with the motor-on level high in every clock between them, in whole milliseconds of real time (truncated), the largest since reset; `0x0000` before the first measurement; saturates at `0xFFFF`. A measurement starts with a motor-qualified index edge (`diag_index_qual_i`) and ends with the next one, which starts the next measurement; a clock with the motor-on level (`st_motor_on_i`, low also in reset and while the drive is disabled) low ends it without a result. It does not depend on READY. About 200 when every index pulse arrives, about 400 or 600 when one or two in a row are missing, thousands after a disk was taken out and put back with the motor on |
| `0xA3` | `CNT_RDY_STALE` | 16-bit saturating counter: falls of READY while the motor-on level stays high. The controller lowers READY together with that level with the motor request, on reset and on disable, so only the fall by the rule of 500 ms of settled time without an index edge counts |
| `0xA4` | `CNT_TOL_HIT` | 16-bit saturating counter of `tol_hit_i`: marks the decoder accepted on a train of two. Every `FE` accepted on a pair counts, also one whose ID then has a bad CRC and is not reported (it counts here and not in `CNT_IDDEC`), and every `FB` or `F8` on a pair that opened a data field |
| `0xA5` | `RD_CTRL` | readable and writable; bit 0 high switches the decoder's tolerance off (`dec_tol_off_o`); bits 15 to 1 read 0; `0x0000` after reset |

`VERSION` reads `0x0AFE`. The four words derive from inputs the device already had (`st_motor_on_i`, `diag_index_qual_i`, `st_media_ready_i`) and from `tol_hit_i`; for them no port of the device changes and no line of `main.vhd`. The read multiplexer gets four flat register entries and no arithmetic. All four words are cleared only by a reset. The dump command for the words of maps v8 to v10 is `MD 7080 70A5`; `doc/dev-fdd/tools/diag_dump_decode.py` decodes the new words and decodes dumps of maps v8 and v9 as before. The reference for the user is `doc/1581_dd_debug_device.md`, sections 2.4 and 3.6.

Lost sync bytes in the counters of map v6, with the tolerance: `CNT_A1_CAND - 3 * CNT_A1_TRAIN` still counts them, two per record and revolution, whether the tolerance recovered the record or not; `CNT_TOL_HIT` tells how many were recovered; `CNT_IDDEC - CNT_MARK_FE` is about the number of recovered IDs (in `tb_flux_ctl`: 18 - 16 = 2, with 2 uses).

## 5. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | The time in which the step engine works or the head has not settled does not count toward the 500 ms of READY, and the count starts anew when the head has settled. | Section 1. READY stays what it is meant to be, the READY of a mechanism that turns a disk, also on a mechanism that withholds its index pulses while it steps. The cost is a later notice of a disk that is pulled during a seek, which the disk-change line covers. |
| D2 | No bound on the suspension of the READY count. | Without a disk there are no index edges, so READY can stay high only if it was high when the disk left, and the disk-change line and the abort terms of the engines cover that. A bound would bring the false "not ready" back for programs that step for a long time with a disk on such a mechanism (drive music, protection code). Even after the longest train of the DOS, a Restore of 255 steps at 12 ms, READY falls 518 ms after the last step when no index edge comes. |
| D3 | The suspension ends with the settle time of the controller (`head_settled`, 18 ms after the trailing edge of the last pulse), with the busy step engine as a second term. | `head_settled` already marks the moment from which the controller reads and writes again, and the one known hold time (15.8 to 17.9 ms) lies inside it. A longer hold time is covered up to about 318 ms by the slack of the 500 ms. The second term holds the count where the settle time is shorter than the step recovery, so the rule holds for every ratio of the generics. |
| D4 | An index edge counts whenever it arrives, also during a step. | It is proof of rotation. Ignoring it would make READY rise later and fall earlier than the mechanism justifies; two mutants of the bench (an edge ignored during a step, READY that cannot rise while the head moves) show both. |
| D5 | In physical mode the steps are paced by the rate bits of the command, with the acknowledge of the controller as the lower bound. | That is what a WD1772 does and what the 1581 ROM asks for. The step engine of the controller stays as it is: its recovery is the limit of the mechanism, the rate is the choice of the command. |
| D6 | A rate table of its own in physical mode, 20 bits wide (`phys_rate_ticks`). | `step_rate_clk` of the image path is 16 bits wide and wraps for 12 ms and above (section 6); the image path stays untouched. |
| D7 | Every accepted command clears the rate count and, in physical mode, starts the Type I machine in state 0. | On a WD1772 the rate delay is part of the command: a Force Interrupt ends it with the command, and every command starts from its beginning. Before, a Force Interrupt left `seek_state` at 1 (waiting for the acknowledge) or 3 (minimum busy time), with the pacing also at 2 (rate time of a Step), and the next Type I command started there: it stepped at once in the old direction or ended without a step. The image path keeps the upstream behavior. |
| D8 | Proof I3 of `run_257_proofs.py` runs with the step model of WIP-V6-A25 (`paced = False`). | It reproduces the tester's dumps, and those were taken with the RTL of WIP-V6-A25, which stepped at the acknowledge. |
| D9 | Variant A for the decoder: a mark after a train of two sync bytes. Variant B, an interval near a midpoint decided by its phase against the cell clock as a PLL does it, was rejected. | On the twelve captures A gains the ID and the data field of sector 7 in each of the three revolutions and changes nothing else (3 uses). B (phase factor 0.7, within 25 cycles of a midpoint) reads that header in one revolution of three, with a margin of a few cycles, and decides 16,407 intervals of the captures differently: a large change of the decoder's behavior for a small and uncertain gain. |
| D10 | Four restrictions of variant A: (a) an ID accepted on a pair is reported only with a good CRC; (b) a data mark on a pair needs the arm of a CRC-valid ID; (c) it needs the zero run 7 to 11 gaps before the first candidate, the lower bound included; (d) a pair never re-anchors an open field. | (a) A bad-CRC ID ends a Read Address with an ID CRC error, and an ID during the wait for a data mark sends the read back to the search; a false `FE` on a pair could do both, and a mutant that reports such an ID loses the data field of the ID before it. (b) The record grammar of map v7 applies to every data mark; it is the guard against splices that reproduce a sync train. (c) A pair right after the zero run is the start of a train, never a complete one; the window is that of a train of three, moved by the five gaps of the lost byte. (d) Never needed in the evidence: variant A without its restrictions (re-anchor on a pair, no lower bound of the window, bad-CRC IDs reported) gives the same fields on all twelve captures, and the re-anchor, a guard against junk inside a field, stays with the stricter trains of three. |
| D11 | Only a weak first sync byte is recovered. | After a weak second byte a byte completes between the two remaining candidates (the four cases of a single misclassified interval, checked by hand), and after a weak third byte the byte after the pair is the damaged `A1`, not the mark. The evidence has no weak second sync byte: of the 88,457 real sync trains that follow a zero run, every byte within 0.10 half cells of a midpoint is a first byte of the three trains of that header or the third byte of the track information mark (`A1 A1 A1 65`) of the 11-sector disk G3, which is not a sector field. |
| D12 | The tolerance exists only with the production values of the sync generics (`C_TOL`). | The historical columns of the A/B harness of the quantiser keep their behavior, so the harness still compares the decoders of the past. |
| D13 | The switch `RD_CTRL` (bit 0 switches the tolerance off) and the counter `CNT_TOL_HIT`. | A disk can be compared with and without the tolerance on the hardware without a rebuild, and the counter shows how often the tolerance acts in the field. With the switch set, the decoder is the decoder without the tolerance, on every output and in every clock. |
| D14 | `IDX_GAP_MAX_MS` and `CNT_RDY_STALE` derive from inputs the diagnostic device already has. | They turn the two inferences behind change 1 into measurements on the tester's machine (does the mechanism withhold its index pulses while it steps, and how often does READY fall by the 500 ms rule), without a new port and without a change of `main.vhd`. |
| D15 | Change 2 does not ship without change 1. | At 6 ms a seek over 50 cylinders lasts 300 ms and one across the disk 474 ms. With the READY rule of WIP-V6-A25, a mechanism that hides its index pulses then loses READY before the exam right behind the seek: at 2 of 12 index phases over 50 cylinders and at all 12 across the disk, on the genuine ROM (section 8). |
| D16 | The changes go into `WIP-V6-A28`; the version string stays. Decided by sy2002. | `WIP-V6-A28` has been neither built nor released; one build carries the fix of the file browser and these changes, and the section `Version WIP-V6-A28` of `tests/README.md` covers both. |
| D17 | No entry in `VERSIONS.md`. | As D10 of `doc/dev-fdd/ISSUE257.md`: the changes improve a feature that was never released, the internal drive as a 1581 of the unreleased version 6. |

## 6. Found on the way

* **The rate table of the image path wraps.** `step_rate_clk` of `fdc1772.v` is 16 bits wide: the 12 ms entry gives 30,463 ticks, 3.81 ms (checked with Icarus Verilog), and the 20 ms and 30 ms entries of a WD1770 or WD1773 wrap as well. It matters only for a disk image and only if the ROM's probe of the CIA TOD clock fails, which it does not in the core. Not changed: the image path is outside of these changes; the physical path has a table of its own (D6).
* **The Restore bound sets the seek error without the V flag.** A Restore that has not found track 0 after 255 steps ends with the seek error bit, in both paths; the datasheet sets it only "providing the V flag is set", and the ROM's `$08` has V = 0. It concerns only a mechanism whose track 0 sensor never answers. Not changed.
* **A Force Interrupt in the image path.** There `step_rate_cnt` survives a Force Interrupt and delays every following command, of any type, for the rest of the rate time, and `seek_state` survives too. The 1581 ROM sends a Force Interrupt only at `$C367` (initialization) and at `$CADC` (from `$CA84`, the compare loop of a Read Sector, error 7), never during a Type I command, so only custom drive code meets it. Not changed (upstream behavior; for the physical path see D7).
* **A step request can be lost after a Force Interrupt.** The controller's step engine takes a request edge only while it is idle. In the sequence Step In, Force Interrupt 1 ms later, Step Out, the request of the Step Out falls into the recovery of the Step In and is lost, the stale acknowledge of the Step In completes the Step Out, and the head ends one cylinder further in instead of back where it was (case 25h of `tb_fdc1772_physical.sv`, reported by the bench, not checked). It was the same before change 2; the pacing narrows the window to the part of a stepping command's BUSY time in which the controller still works (about 3.03 of 6 ms for code 00, a quarter for code 01, all of it for codes 10 and 11). The ROM never reaches it; custom drive code could. Not changed. Two cures are possible: the controller latches an edge that arrives while its engine works, as `step_pend` does behind a write, or the WD model keeps an "acknowledge outstanding" flag across a Force Interrupt and holds the next request until the stale acknowledge has come.
* **The proofs P-M4 and P-M5 depend on the rotational phase.** The proofs of the read milestone (`doc/dev-fdd/rom_emu/run_proofs.py`) pass as they are; their `machine.py` takes 1.5 ms per step. In a copy of `machine.py` with 6 or 12 ms per step, P-M4 and P-M5 fail (the Read Address sequence is 4, 7, 8 instead of 5, 10, 11), and a sweep over the phase origin of the disk model shows both properties again at other phases (at 6 ms with the origin at 150 to 160 ms, at 12 ms at 30 to 40 ms). Their expectations are tied to one rotational phase, which the seek time moves; no dependence of the DOS on the seek time was found. `machine.py` is not changed. The write proofs (`run_write_proofs.py`) pass at 1.5, 6 and 12 ms.
* **The format time that R5 and R6 print depends on the phase.** These proofs of `run_257_proofs.py` extrapolate the format of 80 cylinders from the first cylinder, which includes the wait of the first Write Track for its index pulse. The longer Type I commands before it (the Restore job of the scenario among them) move that Write Track from 7.6 ms after an index pulse to 11.7 ms before one, so it no longer waits almost a revolution, and the printed times fall: with the read-ahead from 101.5 to 87.5 s, for a real chip from 100.2 to 86.1 s, for delivery v2 alone from 389.5 to 375.4 s. From the second side on a cylinder takes 1200.0 ms in every model, and the bounds of the proofs still hold. Not changed; measuring from the first to the third Write Track would remove the phase.
* **`pllcheck.py` misses the weak header at its default.** With its default phase gain of 0.60 the PLL of `doc/dev-fdd/tools/part_e/format_stop/pllcheck.py` does not read the ID of sector 7 in any revolution; with 0.45 and 0.30 (`--phase`) it reads it. The gained data fields are confirmed with all three gains. The Greaseweazle software's own conversion of the separate D81 read reported 10 of 10 sectors for that side. The analysis, section 4, says so.
* **The index period of `ctl_run.log`.** The log of `tb_flux_ctl` was made with `G_REV_CYC = 9954565`, the mean revolution of the looped flux; the default of the bench, 9954550, shifts the index edges by 15 cycles per revolution. The command in `doc/dev-fdd/tools/part_e/README.md` names the value.
* **A loss of lock does not disarm the data mark.** A gap error does not clear `data_armed` of the decoder. It is older than these changes and harmless for the tolerance, whose data mark needs the zero-run window as well. Not changed. No unit scenario combines a weak first sync byte with a gap error in between.
* **`G_SETTLE_CYC = 0`.** With that value the head never counts as settled after a step: reads wait for ever, and READY can no longer fall after a step. It was so before change 1; no configuration and no bench uses 0. Not changed.
* **Mutants outside of the repository.** The 12 mutants of change 2 and the 24 of map v10 (section 8) are not part of the repository and not part of the regression of `doc/dev-fdd/tools/regression`; the mutants of change 1 (`run_tb_media_contract.sh`) and of change 3 (`mutants_mfm_decoder.py`) are. A `mutants_diag.py` in the style of `mutants_rdahead.py` would bring the device's mutants into the regression.

## 7. Numbers

| What | Value | Source |
|---|---|---|
| Time that does not count toward the 500 ms of READY | from the acceptance of a step until 18 ms (`G_SETTLE_CYC`) after the trailing edge of its pulse, and every clock in which the step engine works | RTL |
| Longest hold time of index pulses after a step that READY survives | about 318 ms (320, 319 and 318 ms at 3.03, 6 and 12 ms per step) | the rule of `h257.py`, index phases in steps of 2 ms |
| A disk pulled during a step train | READY falls 500 ms after the head has settled (checked to 1 µs) | `tb_physical_1581_media_contract` |
| Pace of a step for the codes of the ROM | 6.000 ms (48000 ticks of 125 ns); 12 ms if the TOD probe fails | RTL; `tb_fdc1772_physical.sv` group 25 measures 5.76 ms at its tick of 120 ns, exact to the tick |
| Pace for the codes 10 and 11 | the acknowledge: 3.03 ms, 4.03 ms after a reversal | RTL, group 25 |
| BUSY of a Type I command | n paces plus 2 ticks (Step, Step In, Step Out) or 3 ticks (Seek, Restore); 1.5 ms without a step | group 25 |
| Seek over 39, 50, 79 cylinders | 234, 300, 474 ms (39 cylinders at 3.03 ms per step: 119 ms) | RTL |
| Recalibration inside `UI` at 6 ms per step (motor stopped, head on cylinder 39, every index pulse delivered) | exam of READY 800.9 ms after motor-on; Restore 801.1 to 1035.1 ms (head settled 1047.1); Seek 1107.3 to 1341.3 ms (settled 1353.3); the exam that failed in form 1, 1359.9 ms; `UI` ends at 1628.4 ms. With a 2-cylinder loss: Seek of 2 steps 1370.9 to 1382.9 ms, the exam that failed in form 2, 1401.5 ms, `UI` ends at 1667.1 ms. 72.2 ms between the two trains | genuine ROM in the emulator (`h257.py`); JiffyDOS ROM identical within 0.1 ms |
| Exam of READY after motor-on | 0.8000 s for an unchanged disk; 0.8303 s after a disk change (0.8263 s with the steps of WIP-V6-A25) | proof I1 |
| Latest first index pulse that passes the exam | 0.631 s with two pulses, 0.830 s with one pulse, after a disk change | proofs I2, I4 |
| READY count at an exam of the ROM | at most 197 ms with the rule of part E in 124 runs; the rule of WIP-V6-A25 counts up to 1713 ms at the same exams | `run_matrix.sh` |
| The weak sync byte (cylinder 77, H=1, sector 7) | intervals 6.47, 6.88, 6.75, 7.80, 5.60 µs (nominal 6, 8, 6, 8, 6); margin -0.076, -0.057 and -0.050 half cells in the three revolutions | analysis section 4, `tolsurvey/` |
| Next weakest sync byte in front of a sector field | +0.110 half cells | `tolsurvey/` |
| The twelve captures without the tolerance | 50,877 IDs, 49,597 data fields, all CRC-valid; 9,894 sectors rewritten one at a time | `tolsurvey/SUMMARY.txt` |
| Variant A against variant B on them | A: 3 IDs and 3 data fields gained, nothing lost or changed, 3 uses. B: 1 ID and 1 data field gained, 16,407 intervals decided differently | `tolsurvey/SUMMARY.txt` |
| Sector 7 in `tb_flux_ctl` | result 00 from the read-ahead buffer, 3.18 ms after the request; without the tolerance result 04 after 862 ms and five index edges | `ctl_run_tol.log`, `ctl_run.log` |
| Format time printed by R5 and R6 | read-ahead 87.5 s, real chip 86.1 s, delivery v2 alone 375.4 s (the phase of section 6); 1200.0 ms per cylinder from the second side on | `run_257_proofs.py` |
| `VERSION` of the diagnostic device | `0x0AFE` | RTL |

## 8. Proofs

What each change was verified with. The commands are those of the tools in section 10; wall times are from a machine with other simulations running.

### 8.1 READY while the head moves

* **`run_tb_media_contract.sh`** (`CORE/vhdl/test/tb_physical_1581_controller/`): `RESULT: PASS`. It runs the bench with nvc and with GHDL (both end at 575,801,050 ns, part 1 at 232,043,150 ns) and rejects 25 of 25 mutants of the controller with nvc (`SIM=ghdl` runs everything with GHDL; `JOBS` sets the parallel jobs): the 17 of WIP-V6-A25 and 8 of the new rule (no suspension, a suspension without the restart, one that lasts until the next index edge, one for the step engine only, one for the settle time only, an index edge ignored during a step, READY that cannot rise while the head moves, the drop held back until the head rests). 52 minutes with one job.
* **The bench** `tb_physical_1581_media_contract`. Part 1: the first controller with the cases of WIP-V6-A25, its step recovery (0.5 ms) longer than its settle time (two clocks), so the step engine alone holds the count. Part 2: a second controller with every time at 1/50 of production, on the mechanism model `mech_model_1581.vhd` with its option to withhold the index (generic `G_IDX_HIDE`, input `cfg_idx_hide_i`: from the leading edge of a step pulse until a settable time after its trailing edge, retriggered by the next pulse; off by default; the bench sets that time to the pace plus the hold time). A clocked model of the rule (`ready_ref`) compares `media_ready` of both controllers in every clock. Cases of part 2: 27 step trains (39 and 80 steps at 3.03, 6 and 12 ms per step with hold times of 0, 18 and 40 ms, and the recalibration, 39 steps, 70 ms, 39 steps, for all nine pairs of pace and hold): READY stays up; a disk pulled during a train: READY falls 500 ms after the head has settled; one pulled at rest: 500 ms after the last index edge; 39 steps without a disk: READY stays low; the first index edge after a motor restart that comes during an 80 × 12 ms train makes the drive ready at once; a motor restart and a disable and enable with the latch cleared.
* **Without the reference model** (a copy of the bench with the assertion of `ready_ref` removed) the 8 new mutants are still rejected, each by a check of the stimulus ("READY dropped where it has to stay up", "an index edge during a step did not make the drive ready", "a disk taken out during a train left READY up").
* **Unchanged benches:** `tb_physical_1581_controller` (end 1,431,124,570 ns), `tb_mech_model_1581` (211,646,410 ns) and `tb_physical_1581_ovf` (405,026,450 ns): ALL TESTS PASSED, the end times unchanged.
* **The genuine ROM** (`doc/dev-fdd/tools/part_e/mfcwt_74/run_matrix.sh`, 23 groups, 1.2 core hours; logs in `matrix/`). The `UI` of MFCWT followed by `$` 15 ms after it (the JiffyDOS bus), and long seeks with the motor running, on a mechanism that withholds its index pulses from the start of every Type I command until the hold time after its end. A run fails if one exam of READY fails; the last column gives the largest count of each rule at an exam of the run (an exam fails at 500 ms).

  | Group | Rule | Pace | Hold | Head or seek | Motor | ROM | Runs | Failed | Largest count, A25 rule / part E rule |
  |---|---|---|---|---|---|---|---|---|---|
  | `n_rate_h18_c39` | part E | 6 ms | 18 ms | cylinder 39 | stopped, first pulse 400:790:30 ms | stock | 14 | 0 | 794 / 191 ms |
  | `n_rate_h18_c79` | part E | 6 ms | 18 ms | cylinder 79 | stopped, 400:790:30 ms | stock | 14 | 0 | 1027 / 191 ms |
  | `n_rate_h18_c10` | part E | 6 ms | 18 ms | cylinder 10 | stopped, 400:790:65 ms | stock | 7 | 0 | 572 / 141 ms |
  | `n_rtl_h18_c39` | part E | 3.03 ms | 18 ms | cylinder 39 | stopped, 400:790:65 ms | stock | 7 | 0 | 513 / 141 ms |
  | `n_12_h30_c79` | part E | 12 ms | 30 ms | cylinder 79 | stopped, 400:790:65 ms | stock | 7 | 0 | 1713 / 141 ms |
  | `n_rate_h0_c39` | part E | 6 ms | 0 ms | cylinder 39 | stopped, 400:790:65 ms | stock | 7 | 0 | 687 / 141 ms |
  | `n_rate_h30_c39` | part E | 6 ms | 30 ms | cylinder 39 | stopped, 400:790:65 ms | stock | 7 | 0 | 752 / 141 ms |
  | `n_rate_h18_run` | part E | 6 ms | 18 ms | cylinder 39 | running, 9 phases | stock | 9 | 0 | 819 / 197 ms |
  | `n_jd_rate_h18` | part E | 6 ms | 18 ms | cylinder 39 | stopped, 400:790:65 ms | JiffyDOS | 7 | 0 | 687 / 141 ms |
  | `n_jd_12_h30_run` | part E | 12 ms | 30 ms | cylinder 39 | running, 9 phases | JiffyDOS | 9 | 0 | 1316 / 197 ms |
  | `o_rtl_h0_c39` | A25 | 3.03 ms | 0 ms | cylinder 39 | stopped, 480:690:15 ms | stock | 15 | 8 | |
  | `o_rate_h0_c39` | A25 | 6 ms | 0 ms | cylinder 39 | stopped, 480:690:15 ms | stock | 15 | 7 | |
  | `o_rtl_h18_c39` | A25 | 3.03 ms | 18 ms | cylinder 39 | stopped, 400:790:30 ms | stock | 14 | 8 | |
  | `o_rate_h18_c39` | A25 | 6 ms | 18 ms | cylinder 39 | stopped, 400:790:30 ms | stock | 14 | 10 | |
  | `o_rtl_h18_c79` | A25 | 3.03 ms | 18 ms | cylinder 79 | stopped, 400:790:65 ms | stock | 7 | 6 | |
  | `o_rate_h18_c79` | A25 | 6 ms | 18 ms | cylinder 79 | stopped, 400:790:65 ms | stock | 7 | 7 | |
  | `s_old_rtl_50`, `s_old_rate_50`, `s_new_rate_50` | A25, A25, part E | 3.03, 6, 6 ms | 18 ms | seek over 50 cylinders | running, 12 phases | stock | 12 each | 0, 2, 0 | |
  | `s_old_rtl_79`, `s_old_rate_79`, `s_new_rate_79`, `s_new_12_79` | A25, A25, part E, part E | 3.03, 6, 6, 12 ms | 18, 18, 18, 30 ms | seek across the disk (79 cylinders) | running, 12 phases | stock | 12 each | 0, 12, 0, 0 | |

  The rule of part E fails no exam in its 124 runs (88 of `UI` and `$`, 36 seeks), and its count at an exam never exceeds 197 ms; at the same exams the A25 rule counts up to 1713 ms and would fail 93 of the 124 runs, so the runs exercise the rule where it matters (after the Restore, after the Seek, after the two extra steps of form 2, after a seek across the disk). The A25 rule is the red control: at its own pace with hold 0 it fails exactly at the first-pulse times of the analysis (480, 510 and 615 to 690 ms; in 4 of them the `$` gets 74 as well), and 46 of its 72 `UI` runs fail. At 6 ms against 3.03 ms the A25 rule fails long seeks (2 of 12 against 0 of 12 over 50 cylinders, 12 of 12 against 0 of 12 across the disk), while in the `UI` sequence the failures move to other first-pulse times rather than becoming more (7 against 8 of 15 with hold 0, 10 against 8 of 14 with hold 18). The JiffyDOS ROM gives the same lines as the stock ROM where both have the same first-pulse times (400 and 790 ms). With the defaults of the harness the timelines of the analysis and the head-39 block of `sweep_stock.log` come out byte for byte as before.

### 8.2 The step rate

* **`tb_fdc1772_physical.sv`** (Icarus Verilog, in the submodule): PASS, 299 checks (212 before, 87 in the new group 25), 0 failures, simulated end 688.52 ms, 33 minutes; `+only25` 11 minutes; `+only25 +long` (with the Restore into its bound) 96 checks, 83 minutes. The RTL before the change fails group 25 (24 failures). The mock backend of the bench steps like the controller's step engine: it takes a request edge only while idle, acknowledges 3.028 ms after it (4.028 ms after a reversal) and reports the head settled 18 ms after the pulse. Measured in group 25 (the bench's tick of the 8 MHz clock enable is 120 ns, so the 6 ms of code 00 are 5.76 ms of bench time; on the hardware the tick is 125 ns):

  | Code | Distance between two step requests | BUSY |
  |---|---|---|
  | 00 | 5,760,000 ns (48000 ticks, exact) | Seek of 3 steps 17,280,360 ns; Seek and Restore of 5 steps 28,800,360 ns; Step In, Step Out and Step 5,760,240 ns |
  | 01 | 11,520,000 ns (96000 ticks, exact) | 3 steps 34,560,360 ns |
  | 10 | 3,028,680 ns (the acknowledge is the bound) | 3 steps 9,086,400 ns |
  | 11 | 3,028,680 ns; after a reversal 4,028,640 ns | 3 steps 9,086,400 ns; 2 steps with a reversal 7,057,680 ns |
  | no step | | 1,440,240 ns |
  | Restore into its bound (`+long`) | 255 requests, each exactly 5,760,000 ns apart | 1,468,800,240 ns, seek error set |

  The other cases of group 25: a Seek after a Restore to track 0 and a Step Out after a Step In (a reversal costs nothing at 6 ms); a Restore whose track 0 sensor answers 4 ms after the step pulse, after the acknowledge and before the end of the rate time (exactly 5 requests; the RTL before the change ran on); a Force Interrupt in the 12 ms rate time of a Step In followed by a Step Out (one outward request 240 ns after BUSY rose, BUSY 5,760,240 ns); a Force Interrupt in the minimum busy time of a Seek without steps followed by a Seek (it steps twice); a Force Interrupt in the rate time of a Seek followed by a Read Address (the request 2 µs after the command at the most, 6 bytes, CRC residue 0, no further step); the verify option (the verify request 18,028,440 ns after the last step request, BUSY 23.79 ms).
* **12 mutants of the change**, all rejected (run with `+only25 +stopfail`):

  | Mutant | Killed by |
  |---|---|
  | no pacing | distance 4,028,640 ns |
  | the gate only in state 1 | distance 5,759,880 ns |
  | pacing only while another step follows, none after the last one | Seek BUSY 26,069,040 ns |
  | code 01 as 6 ms | distance 5.76 ms |
  | the 16-bit table of the image path (12 ms wraps) | distance 3,655,680 ns |
  | code 10 as 20 ms | distance 19.2 ms |
  | code 11 as 30 ms | distance 28.8 ms |
  | the count one tick long | distance 5,760,120 ns |
  | the count survives into the next command | BUSY 12,279,360 ns after the Force Interrupt |
  | `seek_state` survives into the next command | no request after the Force Interrupt, BUSY 1.44 ms |
  | the acknowledge is not the lower bound | BUSY never ends, distances 1.92 ms |
  | the image path paced as well | the golden trace of the image path differs at line 11 |
* **`tb_fdc1772_image_golden.sv`**: byte-identical, also with `-DFDC_WR_PORTS` and with `+wrnoise`. The golden trace uses only the 6 ms codes, so it cannot see the 12 ms entry of the image table; the invariance of the image path rests also on the structure of the change (everything behind `phys_mode` or on `phys_rate_cnt`).
* **`run_257_proofs.py`**: `RESULT: ALL 257 PROOFS PASS`, with every Type I command at the step time of the new RTL (444 s). Before, only Step In and Step Out had the step time of the RTL, and Restore and Seek the 1.5 ms per step of `machine.py`. The expectations that moved:

  | Proof | WIP-V6-A25 | Now | Reason |
  |---|---|---|---|
  | I1 | exam after a disk change at 0.8263 s | 0.8303 s | the step pair takes 2 × 6 ms instead of 4.03 + 4.03 ms; the window of 0.80 to 0.86 s holds |
  | I2 | two pulses: in time at 0.62 s, 74 at 0.63 s | 74 at 0.635 s | the last first pulse in time is 0.631 s |
  | I3 | | unchanged (job error 3, the motor on for 11.030 s, 53 pulses) | runs with the step model of WIP-V6-A25 (D8) |
  | I4 | one pulse: limit 0.83 s | 0.835 s fails, the exam is at 0.830 s | as I1 |
  | R5, R6 | format: read-ahead 101.5 s, real chip 100.2 s, delivery v2 alone 389.5 s | 87.5 s, 86.1 s, 375.4 s | the phase of the first Write Track (section 6); the bounds are unchanged and hold |
* **`run_proofs.py` and `run_write_proofs.py`** pass as they are; with 6 and 12 ms per step in a copy of `machine.py`, see section 6.
* **The recalibration at 6 ms** on the genuine ROM: the timeline in section 7. As a check of the harness, the RTL of WIP-V6-A25 with a loss of two cylinders reproduces the table of the analysis (Restore 801.1 to 917.3 ms, Seek 992.5 to 1108.6 ms, exam 1130.2 ms, Seek of 2 steps at 1134.0 ms, exam 1158.6 ms).

### 8.3 The decoder's tolerance

* **`tb_physical_1581_mfm_decoder`** (`CORE/vhdl/test/tb_physical_1581_codec/`): two decoders, with and without the tolerance, on the same flux, through the original vector (scenario 0) and scenarios 1 to 16: a weak first, second and third sync byte for an ID and for a data field (normal and deleted), the grammar cases (no valid ID, no zero run, a pair right after the zero run, a pair inside an open data field), a splice-like false mark between an ID and its data, a train of one, overlapping candidates, a damaged header with a weak first byte. All OK, 47 s with nvc, 28 s with GHDL. `mfm_flux_gen_pkg.vhd` replays the recorded intervals of the weak byte (`mfm_a1_shift`, `A1_WEAK`). The bench on the decoder without the change fails exactly the checks with the tolerance of scenarios 1, 4, 5, 13 and 16 and passes every check without it.
* **`mutants_mfm_decoder.py`**: 17 of 17 mutants rejected (`MUTANTS RESULT: PASS`, nvc, 41 to 71 s each, about 16 minutes):

  | Mutant | Killed by |
  |---|---|
  | the tolerance ignores `tol_off_i` | scenario 1, decoder without the tolerance |
  | a train of one accepted | scenario 2, count of uses |
  | a candidate at the wrong spacing continues a pair | scenario 15 |
  | a spacing up to five continues a train | scenario 15 |
  | no stand-in `A1` in the CRC | scenario 1 |
  | `A1` instead of the mark in the CRC | scenario 1 |
  | the mark fed one clock after its stand-in (the engine drops it) | scenario 1 |
  | a data mark on a pair without the arm | scenario 8 |
  | a data mark on a pair without the zero run | scenario 10 |
  | the window without its lower bound | scenario 11 |
  | the window without its upper bound | scenario 10 |
  | `tol_hit_o` stuck low | scenario 1, count of uses |
  | `tol_hit_o` doubled | scenario 1, count of uses |
  | `tol_hit_o` stuck high | scenario 0 |
  | a pair ID with a bad CRC reported | scenario 13: two IDs, the data lost |
  | a pair ID sets N before its CRC verdict | scenario 13: a read of 512 bytes with bad bytes |
  | a pair re-anchors an open field | scenario 12 |
* **`units.sh`** (`doc/dev-fdd/tools/regression/`): `UNITS RESULT: PASS`. The A/B harness of the quantiser (`tb_physical_1581_quantise_ab`) has the column `toloff` (production with `tol_off_i` high) and three rows with a weak first sync byte: production equals `toloff` on every original row, only production passes the three new rows, and the seven columns of the past, the ranges of the estimate and the 12 probes give the same results row for row as before.
* **`tb_flux_dec`** on `f77h0.txt` (the flux of the failing track side): with the tolerance all ten headers in every revolution, 3 uses; with `G_TOL_OFF=1` the headers 1 to 6 and 8 to 10, and the log equals that of the decoder without the change byte for byte. `rtlcmp.py`: the model agrees with the RTL for both.
* **`tb_flux_ctl`** (`G_REV_CYC=9954565`): with the tolerance sector 7 ends with result 00, from the read-ahead buffer, 3.18 ms after the request; after the last read the counts are 1 unarmed data mark instead of 7 and 2 uses. With `G_TOL_OFF=1` every report line equals `ctl_run.log`, the times included.
* **Model against RTL** (`tolsurvey/RTL_SAMPLES.txt`): 26 track sides of the twelve captures, two revolutions each (the failing side, sides with rewritten sectors and splices, 11-sector sides, clean sides; 2.27 million edges). The model agrees with the RTL on all 52 runs, event for event, and the 26 runs without the tolerance equal those of the decoder without the change byte for byte, the cycles included.
* **`run_tb_write.sh <scratch> 7:15`**: ALL TESTS PASSED, ten write windows, the readbacks byte-exact, the twin check passes.
* **The survey of the twelve captures** (`tolsurvey.py`, all sides and all revolutions of every capture as one stream, on the model; two hours). A field is an ID or a data field, counted over all revolutions; "rewritten" is a sector whose data field does not sit a whole number of clean gap bytes after its ID (written in one pass the distance is 704 half cells on the 1581 format and 720 on the 11-sector format, rewritten 705 to 709). B70 is variant B with the phase factor 0.7. Captures: F4; G1, G3 and G3-after-C (11 sectors, formatted by the MEGA65 core); G4 and G4-after-E4; the disk G5 after the copies of E3 (DraCopy, DraCopy files, MFCWT files) and of E4 (DraCopy, DraCopy files) and after the failed format of E4.

  | Capture | IDs / data fields without tolerance | A: gained, lost, confirmed by the PLL, uses | B70: gained, uses | Rewritten sectors | Trains of two |
  |---|---|---|---|---|---|
  | F4 | 3200 / 3200 | 0, 0, -, 0 | 0, 148 | 483 | 0 |
  | G1 | 5280 / 4800 | 0, 0, -, 0 | 0, 2774 | 350 | 0 |
  | G3 | 3520 / 3200 | 0, 0, -, 0 | 0, 38 | 2 | 0 |
  | G3-after-C | 5280 / 4800 | 0, 0, -, 0 | 0, 2334 | 70 | 1 (the next byte three or more bits from every mark) |
  | G4 | 4800 / 4800 | 0, 0, -, 0 | 0, 1352 | 490 | 0 |
  | G4-after-E4 | 4800 / 4800 | 0, 0, -, 0 | 0, 1494 | 509 | 0 |
  | G5 after E3, DraCopy | 3200 / 3200 | 0, 0, -, 0 | 0, 541 | 1600 | 0 |
  | G5 after E3, DraCopy files | 3200 / 3200 | 0, 0, -, 0 | 0, 564 | 1590 | 0 |
  | G5 after E3, MFCWT files | 3200 / 3200 | 0, 0, -, 0 | 0, 558 | 1580 | 0 |
  | G5 after E4, DraCopy | 4800 / 4800 | 0, 0, -, 0 | 0, 2638 | 1600 | 0 |
  | G5 after E4, DraCopy files | 4800 / 4800 | 0, 0, -, 0 | 0, 2884 | 1590 | 0 |
  | G5 after the failed format | 4797 / 4797 | 6 (3 IDs, 3 data fields), 0, 6 of 6, 3 | 2 (one revolution), 1082 | 30 | 3 (sector 7) |
  | **Total** | **50,877 / 49,597** | **6, 0, 6 of 6, 3** | **2, 16,407** | **9,894** | **4** |

  No ID and no data field with a bad CRC in any capture and any variant, and no variant lost or changed a field. Variant A without its restrictions gives the same fields as A everywhere. The PLL confirms the three gained IDs with the phase gains 0.30 and 0.45 (not with its default of 0.60, section 6) and the three data fields with all three.

### 8.4 Diagnostic map v10

* **`tb_physical_1581_diag`**: ALL TESTS PASSED, 242 checks, end 35,551,102 ns. It checks the reset values; the gap in truncated milliseconds at 10 clocks per millisecond and at the production scale, the maximum, no result across a clock with the motor-on level low, the saturation; the stale count for a fall with the motor on, none for a fall together with or after the motor-on level, the saturation; the tolerance count and its saturation; `RD_CTRL` (bit 0 only, its output, independent of `WR_CTRL`); and that a reset clears all four words.
* **24 mutants of the device**, all rejected, each by one of these checks: 7 of the gap (the motor ignored, the last instead of the largest value, no run flag, the prescaler, no saturation, the milliseconds not restarted, the maximum not reset), 5 of the stale count (counts with the motor off, counts rises, a level instead of an edge, no saturation, not reset), 3 of the tolerance count (not counted, no saturation, not reset), 6 of `RD_CTRL` (not writable, the wrong bit, written by `WR_CTRL`, the output inverted, the output open, not reset), and the read path (`0xA3` and `0xA4` swapped, `RD_CTRL` missing, the version 9).
* **`diag_dump_decode.py`**: the output for all comments of issue #257 is byte for byte the same before and after the change; synthetic dumps of map v10 decode as intended.

## 9. What the Vivado build and the hardware test need to show

Vivado (R3 and R6 at least):

* Timing is met in every clock domain. The changes are in the 50 MHz domain (the QNICE clock: the controller, the decoder, the diagnostic device) and in the core clock domain (`fdc1772.v`: a 20-bit counter and its compare). The read multiplexer of the diagnostic device has four more words; it is on the half-cycle read path of the QNICE devices, which had little slack in earlier builds (0.188 ns on R3 and 0.487 ns on R6 for `qnice_clk` in the builds of WIP-V6-A22X3, `doc/dev-fdd/ISSUE257.md`, section 10).
* No latch and no new critical warning for `physical_1581_controller.vhd`, `physical_1581_mfm_decoder.vhd`, `physical_1581_diag.vhd`, `fdc1772.v` and `main.vhd`. Block RAM as in the build before: none of the changes adds a memory.
* The submodule `CORE/C64_MiSTerMEGA65` is at `c7907bf`.

Hardware (the part "Internal 1581" of the section `Version WIP-V6-A28` of `tests/README.md` is the test plan), on R3/R3A and R6, with a dump of the diagnostic device after each block (`MD 7000 703F`, `MD 7040 707F`, `MD 7080 70A5`; decode with `doc/dev-fdd/tools/diag_dump_decode.py`):

* MFCWT 1.6 with JiffyDOS reads, formats and copies without `REREAD DIRECTORY FIRST`, `REREAD TARGET DIRECTORY` or `74`, and the BASIC loop of `UI` and `$` of the analysis (section 9) shows no `74`.
* After a power cycle with a disk in the drive, the first Read Address after the recalibration finds cylinder 39 at once, without the Seek of two steps (the signature of the analysis, section 3). This is the one place that shows whether 6 ms per step cures the shortfall of the R6's mechanism.
* Three formats in a row, each `0 OK` with 3160 blocks free, in about the time of WIP-V6-A25 (1 min 45 s).
* The key numbers of the dump: `IDX_GAP_MAX_MS` (`0xA2`) per mechanism: about 200 says that the mechanism delivers its index pulses while the head steps, about 400 or 600 that it withholds them (and that the inference of the analysis was right); `CNT_RDY_STALE` (`0xA3`) 0 unless a disk was taken out with the motor on; `CNT_TOL_HIT` (`0xA4`), 0 or small on a healthy disk; `RD_CTRL` (`0xA5`) 0. Also, as for WIP-V6-A25: `SPINUP_MAX_MS` (`0xA1`) below 800, `CNT_RD_AHEAD` about nine tenths of the Read Sectors.
* With `RD_CTRL` set to 1 the drive works as well, and `CNT_TOL_HIT` stays where it was.
* A disk taken out with the motor running still gives `74`, half a second after the head rests.

Open, and none of it a defect of these changes:

* That the tester's mechanism withholds its index pulses while it steps is inferred, not observed; `IDX_GAP_MAX_MS` will tell.
* Whether a WD1772 reads the weak header remains a judgment (analysis section 9 describes the test with a Greaseweazle and a genuine 1581).
* Maverick V4.0 between two disk images (analysis section 7) is still to be tested; the test plan asks for it.

## 10. Tools

* `CORE/vhdl/test/tb_physical_1581_controller/run_tb_media_contract.sh`: the media contract with nvc and with GHDL and its 25 mutants (52 minutes with one job; `SIM=ghdl`, `JOBS`, `--keep`). The mechanism model `mech_model_1581.vhd` has the option `G_IDX_HIDE` with the input `cfg_idx_hide_i`.
* `CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_physical.sv`: the WD1772 model in physical mode, with group 25 for the step rate (`iverilog -g2012 -o tb.vvp tb_fdc1772_physical.sv fdc1772.v iecdrv_misc.sv`, then `vvp tb.vvp`, with `+only25`, `+long`, `+stopfail`; the header has the recipe). `tb_fdc1772_image_golden.sv`: the golden trace of the image path.
* `doc/dev-fdd/rom_emu/run_257_proofs.py`: the genuine-ROM proofs of issue #257, with the Type I timing of the RTL (`paced`).
* `doc/dev-fdd/tools/part_e/mfcwt_74/`: `h257.py` (the genuine ROM with both READY rules, `ready_rule`, and the pace of the steps, `pace`), `exp8_matrix.py` (`UI` and `$` as a sweep), `exp9_seek.py` (one long seek at n phases of the index), `run_matrix.sh` and its logs in `matrix/`, `exp5_sweep.py` and `exp7_timeline.py` with `rule=` and `pace=`.
* `CORE/vhdl/test/tb_physical_1581_codec/`: `tb_physical_1581_mfm_decoder.vhd` (two decoders, scenarios 0 to 16), `mutants_mfm_decoder.py <repository> <scratch>` (17 mutants, nvc, about 16 minutes), `tb_physical_1581_quantise_ab.vhd` (with the column `toloff`), `mfm_flux_gen_pkg.vhd` (`A1_WEAK`).
* `doc/dev-fdd/tools/part_e/format_stop/`: `decmodel.py` (the model of the decoder, with `--tol` the production rule), `tolsurvey.py` and `tolsum.py` (the survey of a capture and the table over all), `tolsurvey/` (the results of the twelve captures, `SUMMARY.txt`, `RTL_SAMPLES.txt`), `rtlcmp.py` (a `tb_flux_dec` log against the model), `pllcheck.py` (the PLL, `--phase`), `tb_flux_dec.vhd` and `tb_flux_ctl.vhd` with `G_TOL_OFF`, `ctl_run.log` and `ctl_run_tol.log`. The commands are in `doc/dev-fdd/tools/part_e/README.md`.
* `CORE/vhdl/test/tb_physical_1581_diag/`: the bench of the diagnostic device with the checks of map v10.
* `doc/dev-fdd/tools/diag_dump_decode.py`: decodes dumps of maps v8 to v10.
* `doc/dev-fdd/tools/regression/`: the simulation regression of `CORE/vhdl/physical_1581` (`doc/dev-fdd/tools/README.md`); its job `media_contract_runner` runs the 25 mutants of change 1, and `units.sh` the decoder bench and the A/B harness. The mutants of the decoder, the bench of `fdc1772.v` and the genuine-ROM proofs run outside of the queue.
