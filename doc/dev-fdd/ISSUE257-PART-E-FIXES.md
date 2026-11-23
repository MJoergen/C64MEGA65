# Issue #257, part E: the fixes (Internal 1581)

Specification of the changes that follow from the analysis in `doc/dev-fdd/ISSUE257-PART-E.md` (read that file first: it has the causes and the evidence). Three changes and a set of instruments, each with its rule, its limits and the proofs it needs. Section numbers of "the record" below refer to that file.

## 0. Overview

| # | Change | Where | Cures |
|---|---|---|---|
| 1 | READY no longer falls while the head moves | `CORE/vhdl/physical_1581/physical_1581_controller.vhd` | `74,DRIVE NOT READY` after `UI` and after every other recalibration (record section 2) |
| 2 | Head steps at the rate the command asks for | `CORE/C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v` (submodule) | the head that is 2 cylinders short after a long seek (record section 3) |
| 3 | The decoder tolerates one weak sync byte | `CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd`, possibly `physical_1581_mfm_quantise.vhd` | the sector header that cannot be read (record section 4) |
| 4 | Instruments: diagnostic map v10 | `CORE/vhdl/physical_1581/physical_1581_diag.vhd` | turns two inferred points into measurements on the tester's machine |

Change 2 must not ship without change 1 (record section 8.2): at 6 ms per step a long seek lasts longer than the 500 ms that READY tolerates without an index pulse.

Rules for all four:

* Nothing changes for disk images: the image branch of `fdc1772.v` and the virtual drives are untouched.
* The rule of the read path stays: the drive CPU never sees a byte of a sector whose CRC was not verified.
* Every change comes with a bench that fails without it, and with mutants that the bench has to reject.
* The interface between the parts is fixed and already in the tree (ports without function yet): the decoder has `tol_off_i` and `tol_hit_o`, the controller passes them on as `dec_tol_off_i` and `diag_tol_hit_o`, `main.vhd` connects them to `dec_tol_off_o` and `tol_hit_i` of the diagnostic device.

## 1. READY while the head moves

**Today.** `media_ready` rises with the first index edge after the motor request rose. It falls with the motor request, on reset, on disable, and when no index edge arrived for `2 * G_PERIOD_MAX_CYC` (500 ms) while the motor request is on. A mechanism that delivers no index pulses while it steps (and for a hold time after the last step: 15.8 to 17.9 ms on a TEAC FD-235HF) makes READY fall although the disk turns, and the DOS examines READY once per job.

**Rule.**

1. The time in which the step engine works or the head has not settled (`head_settled` low: from the acceptance of a step until `G_SETTLE_CYC` after its pulse) does not count toward the 500 ms, and the count starts anew when the head has settled.
2. An index edge is used whenever it arrives, also during a step: it sets `idx_seen` and restarts the count.
3. Everything else stays: the rise with the first index edge of a motor-on interval, the fall with the motor request, on reset and on disable, the fall after 500 ms without an index edge while the head rests. The disk-change latch, the conditions of the read engine, of the write engine and of the read-ahead (which use `media_ready` as before) and the spin-up measurement are untouched.

**To be examined and answered in the hand-back** (change the rule if one of them needs it, with the reason):

* A disk that is pulled while the head moves: READY then falls 500 ms after the head has settled. What does the DOS see in between, and what guards the data (disk-change latch, abort terms of the read and of the write engine)?
* Steps without end and without a disk (a program with its own drive code): READY keeps its last value for as long as the steps come. Is a bound needed? The longest train of the DOS is a Restore (at most 255 steps of 12 ms).
* A mechanism with a longer hold time than 18 ms.
* The benches scale the generics: the rule must hold for every ratio of `G_SETTLE_CYC`, `G_STEP_REC_CYC` and `G_PERIOD_MAX_CYC`.

**Proofs.**

* `tb_physical_1581_media_contract` and its runner `run_tb_media_contract.sh`: the mechanism model gets an option that hides the index pulses while steps run and for a hold time after the last one. Cases: a train of 39 steps and one of 80 steps at 3 ms, 6 ms and 12 ms per step, two trains with 70 ms between them (the recalibration of the DOS), hold times 0, 18 and 40 ms: READY stays high in all of them. A disk pulled during a train: READY falls 500 ms after the head has settled, not earlier and not later. A disk pulled while the head rests: 500 ms as before. Steps with the motor on and no disk: READY stays low. The 17 mutants of the runner are still rejected, and new mutants of the new rule are rejected too (at least: no suspension, a suspension without the restart, a suspension that never ends, a suspension during the step pulses only and not during the settle time, an index edge that is ignored during a step).
* The genuine ROM (`doc/dev-fdd/tools/part_e/mfcwt_74/h257.py` with its sweep): the READY model of the harness gets the new rule next to the old one, and the step pace becomes a parameter. The `UI` + `$` sequence shows no failure with the new rule for every time of the first index pulse (400 to 800 ms in steps of 15 ms), head on cylinder 39, 79 and 10, motor stopped and running (nine index phases), hold times 0, 18 and 30 ms, step pace 3.03, 6 and 12 ms, with the stock ROM and with the JiffyDOS ROM. The old rule is the red control: it shows the failures of record section 2 at 3.03 ms and more of them at 6 ms (the claim of record section 8.2).

## 2. The step rate

**Today.** In physical mode the seek machine of `fdc1772.v` (state 1 of `seek_state`) requests one step from the controller and continues with the acknowledge: 3.03 ms per step, 4.03 ms after a reversal, whatever the rate bits of the command say. The 1581 ROM asks for 6 ms (`$08`, `$18`, `$48`, `$68`).

**Rule.**

1. In physical mode a Type I command paces its steps by its rate bits, with the table the image branch uses (`step_rate_clk`: 6, 12, 2 and 3 ms for a WD1772). The next step is not requested, and the command does not end, before the rate time of the previous step has passed.
2. The acknowledge of the controller stays the lower bound: the pace is the larger of the two times.
3. As on a WD1772, BUSY of a command with n steps lasts n rate times. The minimum BUSY time of a command without a step (`PHYS_T1_MIN_TICKS`, 1.5 ms) is unchanged.
4. Unchanged: the image branch (its golden trace bench passes without a change), the track register, the bound of a Restore (255 steps), the verify option, what a Force Interrupt does.

**To be examined and answered in the hand-back:** a Force Interrupt during a rate time and the command that follows it; the reversal; a Restore that runs into its bound; every place of the benches and of the ROM proofs that has a seek time in its expectations.

**Proofs.**

* `tb_fdc1772_physical.sv` (Icarus Verilog): the distance between two step requests and the BUSY time for all four rate codes, a reversal, a Restore over several cylinders, a single Step In and Step Out, the command without a step; mutants (no pacing, pacing only between steps and not after the last one, a wrong table entry, a rate count that survives into the next command).
* `tb_fdc1772_image_golden.sv` passes unchanged.
* `doc/dev-fdd/rom_emu/run_257_proofs.py` with the step time of the new RTL: all proofs pass; expectations that contain a seek time are adapted, each with its reason. `run_proofs.py` and `run_write_proofs.py` pass as they are, and also with 6 ms and 12 ms per step as an experiment.
* Whether the mechanism of the R6 then stops losing 2 cylinders can only be shown on the hardware.

## 3. The decoder's tolerance for one weak sync byte

**Today.** A mark (ID, data, deleted data) is accepted only after three sync bytes (`A1` with a missing clock) at exact spacing, and the quantiser classifies every flux interval alone against the midpoints 2.5 and 3.5 times its estimate of the half cell. One interval of one sync byte that falls on the wrong side of a midpoint makes the field invisible in every revolution.

**Rule.** To be chosen with evidence between these variants (or a third one, with the reason):

* **A:** accept the mark after two sync bytes at exact spacing, with the CRC as for three.
* **B:** decide an interval near a midpoint by its phase against the cell clock, as a PLL does.

Design it on the model first (`doc/dev-fdd/tools/part_e/format_stop/decmodel.py`, `relaxcheck.py`), then in the RTL, and show that model and RTL agree.

**Requirements for either variant.**

1. With `tol_off_i` high the decoder is the decoder of today, on every output and in every clock. `tol_hit_o` pulses once for every use of the tolerance (variant A: a mark accepted on fewer than three sync bytes; variant B: an interval whose class differs from today's decision).
2. The case of the record: the production decoder on `format_stop/f77h0.txt.gz` decodes all ten headers in every revolution (`tb_flux_dec`; today never sector 7), and the production controller reads sector 7 with a good CRC (`tb_flux_ctl`).
3. No field is lost and none changes: on every available flux capture, every ID and every data field that decodes today decodes the same (C, H, R, N, CRC verdict, data bytes). New fields appear only where a sync byte was weak, and an independent decoder (the PLL of `pllcheck.py`) confirms each of them.
4. No false mark: the three-byte rule exists because of false syncs at write splices. The captures with rewritten sectors (the disks after file copies and after `SAVE`) show no additional mark that is not on the disk and no additional ID with a bad CRC. The grammar of the records stays in force for a mark that is accepted with the tolerance: a data mark needs a CRC-valid ID before it and the lock-up run of zero bytes.
5. The qualified ID mark inside an open field (the re-anchor of the parser) is a case of its own: decide with evidence whether the tolerance applies there.
6. A unit test in the decoder bench with a weak first, second and third sync byte, for an ID and for a data field, with the tolerance on and off; mutants.
7. The existing benches of the codec pass (`units.sh`: CRC, decoder, encoder, the A/B harness of the quantiser), and so do the splice cases of the write benches (run with the regression).

**Evidence.** The flux captures of the tester (attachments of comments 18, 30, 34 and 35 of issue #257). The source disk of step E3 and every read of the disk G5 after it contain adult material: work on structure and flux only, display nothing of the content.

## 4. Instruments (diagnostic map v10)

| Word | Name | Meaning |
|---|---|---|
| `0xA2` | `IDX_GAP_MAX_MS` | the longest time between two index edges in a row with the motor on throughout, in ms, since reset; saturating; 0 before the first measurement. About 200 on a mechanism that delivers every index pulse, about 400 or 600 on one that hides them while it steps |
| `0xA3` | `CNT_RDY_STALE` | how often READY fell while the motor request stayed on (the 500 ms rule) |
| `0xA4` | `CNT_TOL_HIT` | how often the decoder used its tolerance for a weak sync byte (`tol_hit_i`) |
| `0xA5` | `RD_CTRL` | readable and writable; bit 0 high switches the tolerance of the decoder off (`dec_tol_off_o`); 0 after reset |

`IDX_GAP_MAX_MS` measures real time and is independent of the READY rule. The counters follow the conventions of the existing ones (width, saturation, what clears them). `VERSION` becomes `0x0A..`. `doc/1581_dd_debug_device.md` and `doc/dev-fdd/tools/diag_dump_decode.py` follow (the dump command becomes `MD 7080 70A5`; dumps of older maps still decode), and `tb_physical_1581_diag` checks the four words.

## 5. Integration

The three changes are developed side by side and then integrated. After the integration: the cross proof of changes 1 and 2 on the genuine ROM (part of section 1), the whole regression of `doc/dev-fdd/tools/README.md`, `run_257_proofs.py`, `run_proofs.py`, `run_write_proofs.py`, the differential analysis of `main.vhd` and one bench that analyzes it, then one independent review per change, with mutants of its own.
