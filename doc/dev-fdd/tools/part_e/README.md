# Tools of the part E analysis (issue #257)

The one-off tools behind `doc/dev-fdd/ISSUE257-PART-E.md`, kept so that every number of that record can be reproduced and so that a fix has its test cases at hand. They read the tester's dumps, disk images and flux captures; none of them changes anything in the repository.

Common points:

* Run the scripts with `python3 -I -B` from any directory outside of the repository.
* The scripts that run the 1581 ROM use the emulator of `doc/dev-fdd/rom_emu` as it is. It loads the stock ROM of the repository. To run another ROM (the JiffyDOS ROM of a 1581, a licensed file that is not part of the repository), start the script in a directory that holds that ROM under the name `c1581.rom`: the emulator looks there first, and the scripts print which ROM they run.
* The Greaseweazle captures (`.scp`) and the disk images are attachments of comments 18, 30, 34 and 35 of issue #257. The source disk of step E3 and every read of the disk G5 after it contain adult material: these tools read structure and flux only, and nothing needs to be displayed.
* `comments.json` below is the output of `gh api repos/MJoergen/C64MEGA65/issues/257/comments --paginate`, and `decoded.txt` the output of `python3 -I doc/dev-fdd/tools/diag_dump_decode.py comments.json 9 10 11 12 17 18 20 22 24 30 34 35`.

## `mfcwt_74/`: what the DOS does with the `UI` that MFCWT sends (section 2 of the record)

| File | What it does |
| --- | --- |
| `h257.py` | the harness: the genuine ROM on the cycle-exact 6502 of `rom_emu`, READY as the RTL derives it by one of two rules (`ready_rule`: `old`, the RTL of A25, rises with the first index edge after motor-on and falls 500 ms after the last one; `new`, the RTL of part E, counts only settled time: from the start of a Type-I command with steps until 18 ms after the trailing edge of its last step pulse the 500 ms do not run, and they start anew at its end; the header of the file lists the correspondence with the RTL), the pace of the steps (`pace`: `None` as the RTL of A25 does it, 3.03 ms and 4.03 ms after a reversal; `'rate'` by the rate bits of the command as a WD1772 and the RTL of part E do it, 6 ms for the commands of the 1581 ROM; or a fixed number of milliseconds), a mechanism with a settable time of the first index pulse, with or without index pulses during step trains (hidden from the start of a Type-I command until the hold time after the end of its BUSY time), and with a settable number of steps it loses in a long seek; DOS commands are put into the command buffer, and every exam of READY, every job and every command to the disk controller is logged with its time; `rule_state()` gives what either rule says at a given moment |
| `exp7_timeline.py` | the full timeline of `UI` and the `$` that follows it; `rule=` and `pace=` select the READY rule and the pace of `h257.py` (default: `old` and the pace of A25) |
| `exp5_sweep.py`, `run_sweeps.sh` | the sweep over the time of the first index pulse; `sweep_stock.log` is its output for the head on cylinders 39, 79 and 10; `rule=` and `pace=` as for `exp7_timeline.py` |
| `exp8_matrix.py` | MFCWT's check as a sweep: `UI`, then `$` 15 ms after the end of `UI` (the JiffyDOS bus), with a READY rule, a pace, a hold time, a head position, the motor stopped (a list of times of the first index pulse) or running (n phases of the index at which `UI` arrives); one line per case with the trains, every exam of READY (`!` = failed), the job errors 3 (74), and the largest count of either rule at the exams |
| `exp9_seek.py` | one long seek of the DOS (a job on a far track with the motor running) at n phases of the index: the claim of record section 8.2 about seeks at 6 ms |
| `run_matrix.sh` | the covering matrix of the READY rule of part E on the genuine ROM (23 groups of `exp8_matrix.py` and `exp9_seek.py`, the table is in the script); `matrix/` holds its logs, one per group |
| `exp4_ui.py`, `exp4b.py` | `UI` alone: the warm reset and what runs inside the command |
| `exp1.py`, `exp1b.py`, `exp3.py` | the `$` alone: with the directory track in the cache, with another track in the cache, after an error 74 |
| `exp2_boot.py`, `exp2b.py` | the power-on initialization for comparison |
| `exp6_after.py` | `UI` with a failing initialization, then the `$` after a settable delay |
| `jobtable.py` | the job table of the ROM and the stages each job runs |
| `dis.py`, `findref.py`, `findimm.py`, `hexdump_range.py` | a small 6502 disassembler and search helpers, used on the MFCWT cartridge (`main.bin` of https://gitlab.com/retro3872809/commodore-64/mfcwt, not part of the repository; bank n is at file offset n x `$2000`) |
| `timeline_stock_V2_tf620.txt`, `timeline_jd_V1_tf635.txt` | the two timelines the record quotes |

```text
T=<repository>/doc/dev-fdd/tools/part_e/mfcwt_74
python3 -I -B $T/exp7_timeline.py 620 15          # first index pulse at 620 ms, "$" 15 ms after UI: form 1, then 74 (40 s)
python3 -I -B $T/exp7_timeline.py 635 15          # form 2
python3 -I -B $T/exp5_sweep.py 0 2 39 480 690 15  # hold 0 ms, 2 steps lost, head on cylinder 39, 480 to 690 ms in steps of 15
python3 -I -B $T/exp5_sweep.py 0 2 39 480 690 15 0   # the same mechanism with its index pulses left alone: no failure
python3 -I $T/dis.py main.bin 2000 8000 8E43 8E78    # the routine of MFCWT that sends UI (bank 1)
python3 -I -B $T/exp7_timeline.py 620 15 0 2 39 rule=new pace=rate   # the same sequence with the READY rule and the pace of part E
python3 -I -B $T/exp8_matrix.py new rate 18 39 stopped 400:790:30    # UI + "$", rule of part E, 6 ms, hold 18 ms, head on 39, 14 cases (10 minutes)
python3 -I -B $T/exp8_matrix.py old rtl 0 39 stopped 480:690:15      # the red control: the cases of sweep_stock.log with the rule of A25
python3 -I -B $T/exp9_seek.py old rate 18 10 61 12   # a seek over 50 cylinders at 6 ms with the rule of A25, at twelve phases of the index
bash $T/run_matrix.sh <stock dir> <jd dir> <out dir> 2   # the whole matrix, 23 groups, 1.2 core hours
```

Both timelines were reproduced from this folder, the second one with the JiffyDOS ROM as `c1581.rom`; the outputs are identical to the two files except for the header line. With the READY rule and the pace of part E selectable, `h257.py` with its defaults still reproduces them, and `exp5_sweep.py 0 2 39 480 690 15 1` still gives the first block of `sweep_stock.log` byte for byte.

**The READY rule of part E on the genuine ROM** (`run_matrix.sh`, logs in `matrix/`). A mechanism that withholds its index pulses from the start of every Type-I command until the hold time after its end, the `UI` of MFCWT followed by `$` 15 ms after it (the JiffyDOS bus), and long seeks with the motor running. Every run checks every exam of READY, inside `UI` and at the `$`; a run fails if one exam fails. The last two columns show whether a run exercises the rule: they give, for the exams of the run, what each rule counts at the instant of the exam (the A25 rule the time since the last index edge, the rule of part E the settled time since then; an exam fails at 500 ms).

| Group | Rule | Pace | Hold | Head / seek | Motor | ROM | Cases | Failed | Largest count at an exam, A25 rule / part E rule | Cases in which the A25 rule counts 500 ms or more at an exam |
|---|---|---|---|---|---|---|---|---|---|---|
| `n_rate_h18_c39` | part E | 6 ms (rate bits) | 18 ms | cylinder 39 | stopped, first pulse 400:790:30 ms | stock | 14 | 0 | 794 / 191 ms | 10 |
| `n_rate_h18_c79` | part E | 6 ms (rate bits) | 18 ms | cylinder 79 | stopped, first pulse 400:790:30 ms | stock | 14 | 0 | 1027 / 191 ms | 14 |
| `n_rate_h18_c10` | part E | 6 ms (rate bits) | 18 ms | cylinder 10 | stopped, first pulse 400:790:65 ms | stock | 7 | 0 | 572 / 141 ms | 2 |
| `n_rtl_h18_c39` | part E | 3.03 ms | 18 ms | cylinder 39 | stopped, first pulse 400:790:65 ms | stock | 7 | 0 | 513 / 141 ms | 2 |
| `n_12_h30_c79` | part E | 12 ms | 30 ms | cylinder 79 | stopped, first pulse 400:790:65 ms | stock | 7 | 0 | 1713 / 141 ms | 7 |
| `n_rate_h0_c39` | part E | 6 ms (rate bits) | 0 ms | cylinder 39 | stopped, first pulse 400:790:65 ms | stock | 7 | 0 | 687 / 141 ms | 5 |
| `n_rate_h30_c39` | part E | 6 ms (rate bits) | 30 ms | cylinder 39 | stopped, first pulse 400:790:65 ms | stock | 7 | 0 | 752 / 141 ms | 7 |
| `n_rate_h18_run` | part E | 6 ms (rate bits) | 18 ms | cylinder 39 | running, 9 phases | stock | 9 | 0 | 819 / 197 ms | 6 |
| `n_jd_rate_h18` | part E | 6 ms (rate bits) | 18 ms | cylinder 39 | stopped, first pulse 400:790:65 ms | jd | 7 | 0 | 687 / 141 ms | 5 |
| `n_jd_12_h30_run` | part E | 12 ms | 30 ms | cylinder 39 | running, 9 phases | jd | 9 | 0 | 1316 / 197 ms | 9 |
| `o_rtl_h0_c39` | A25 | 3.03 ms | 0 ms | cylinder 39 | stopped, first pulse 480:690:15 ms | stock | 15 | 8 | 596 / 186 ms | 8 |
| `o_rate_h0_c39` | A25 | 6 ms (rate bits) | 0 ms | cylinder 39 | stopped, first pulse 480:690:15 ms | stock | 15 | 7 | 783 / 186 ms | 7 |
| `o_rtl_h18_c39` | A25 | 3.03 ms | 18 ms | cylinder 39 | stopped, first pulse 400:790:30 ms | stock | 14 | 8 | 594 / 191 ms | 8 |
| `o_rate_h18_c39` | A25 | 6 ms (rate bits) | 18 ms | cylinder 39 | stopped, first pulse 400:790:30 ms | stock | 14 | 10 | 788 / 191 ms | 10 |
| `o_rtl_h18_c79` | A25 | 3.03 ms | 18 ms | cylinder 79 | stopped, first pulse 400:790:65 ms | stock | 7 | 6 | 593 / 141 ms | 6 |
| `o_rate_h18_c79` | A25 | 6 ms (rate bits) | 18 ms | cylinder 79 | stopped, first pulse 400:790:65 ms | stock | 7 | 7 | 669 / 141 ms | 7 |
| `s_old_rtl_50` | A25 | 3.03 ms | 18 ms | seek from cylinder 10 to track 61 | running, 12 phases | stock | 12 | 0 | 378 / 192 ms | 0 |
| `s_old_rate_50` | A25 | 6 ms (rate bits) | 18 ms | seek from cylinder 10 to track 61 | running, 12 phases | stock | 12 | 2 | 516 / 192 ms | 2 |
| `s_new_rate_50` | part E | 6 ms (rate bits) | 18 ms | seek from cylinder 10 to track 61 | running, 12 phases | stock | 12 | 0 | 534 / 192 ms | 2 |
| `s_old_rtl_79` | A25 | 3.03 ms | 18 ms | seek from cylinder 0 to track 80 | running, 12 phases | stock | 12 | 0 | 476 / 192 ms | 0 |
| `s_old_rate_79` | A25 | 6 ms (rate bits) | 18 ms | seek from cylinder 0 to track 80 | running, 12 phases | stock | 12 | 12 | 690 / 192 ms | 12 |
| `s_new_rate_79` | part E | 6 ms (rate bits) | 18 ms | seek from cylinder 0 to track 80 | running, 12 phases | stock | 12 | 0 | 695 / 192 ms | 12 |
| `s_new_12_79` | part E | 12 ms | 30 ms | seek from cylinder 0 to track 80 | running, 12 phases | stock | 12 | 0 | 1178 / 192 ms | 12 |

What the matrix shows:

* With the rule of part E no exam fails in any of its 124 runs: 88 runs of `UI` and `$` (first index pulse 400 to 790 ms after motor-on with the motor stopped, or the motor running at nine phases of the index; head on cylinders 39, 79 and 10; hold times 0, 18 and 30 ms; 3.03, 6 and 12 ms per step; stock ROM and JiffyDOS ROM) and 36 seeks over 50 and 79 cylinders. Its count at an exam never exceeds 197 ms. At the same exams the A25 rule counts up to 1713 ms, and in 93 of these 124 runs it reaches 500 ms at one exam at least: the runs exercise the rule where it matters, at the exams right after the Restore, after the Seek to the directory, after the two extra steps of "form 2" (the head 2 cylinders short) and after a seek across the disk.
* The A25 rule is the red control. With its own pace (3.03 ms) and hold 0 it fails at the same times of the first index pulse as `sweep_stock.log` (480, 510 and 615 to 690 ms: 8 of 15); in 4 of them the `$` gets 74, as in form 1 and form 2 of the record.
* The A25 rule at 6 ms per step against 3.03 ms (record section 8.2): in `UI` and `$` with the head on 39 it fails 7 against 8 of 15 runs with hold 0 and 10 against 8 of 14 with hold 18; with the head on 79 (hold 18) 7 against 6 of 7. A seek over 50 cylinders fails at 2 of 12 index phases at 6 ms and at none at 3.03 ms, a seek across the disk (79 cylinders, 474 ms) at all 12 phases at 6 ms and at none at 3.03 ms. So the claim holds for long seeks; in the `UI` sequence, where the trains are 39 cylinders long, 6 ms moves the failures to other times of the first pulse rather than adding many.
* Why this covers the rule: under the rule of part E READY can fall only when 500 ms of settled time pass without an index edge. While the disk turns, the longest such time is the hold time beyond the settle time plus one revolution (at most 30 - 18 + 199 ms here); every run confirms it with a count below 200 ms. The dimensions of the matrix move the exams relative to the trains and to the index (first pulse, phase, head, pace, hold); the JiffyDOS ROM has the same code in the controller, the jobs and the initialization, and it gives the same results (`n_jd_rate_h18` and `n_rate_h18_c39` have identical lines at the two times of the first pulse that both contain, 400 and 790 ms). A first index pulse later than 0.80 s fails the first exam under either rule: that is the limit of the ROM itself (record of A25, `doc/dev-fdd/ISSUE257.md`, section 2), not a matter of the step trains.

## `mechanism/`: head position against sector headers, in every dump (section 3)

| File | What it does |
| --- | --- |
| `steps.py` | the parser for the decoded trace rings: runs of steps and the read that follows them |
| `mismatch.py` | for every run of steps: the track register of the next read against the cylinder its header shows (the position error as the DOS sees it); output for all dumps of the issue in `mismatch_all.txt` |
| `offsets.py`, `deltas.py` | the controller's own estimate against the cylinder found, per dump (`offsets_all.txt`) and before and after each run |
| `scp_ids.py` | the sector headers on every physical track of a flux capture (headers only): shows that a format put every track in its place |
| `longseeks.py` | the head moves a sequential read of every file of a D81 needs, by length |
| `boot_timing.py` | every command of the ROM's power-on initialization to the disk controller, with its time |
| `ready_timeline.py` | a timeline model of READY through a recalibration for a mechanism that hides its index pulses while it steps |

```text
T=<repository>/doc/dev-fdd/tools/part_e/mechanism
python3 -I $T/mismatch.py decoded.txt
python3 -I $T/offsets.py decoded.txt
python3 -I $T/scp_ids.py capture.scp
python3 -I $T/longseeks.py image.d81 60
python3 -I -B $T/boot_timing.py <repository>/doc/dev-fdd/rom_emu
```

## `format_stop/`: the sector header our decoder could not see (section 4)

| File | What it does |
| --- | --- |
| `scp.py` | reader for SuperCard Pro flux files and a simple MFM decoder; the other scripts use it |
| `a1margins.py`, `a1profile.py`, `a1scan.py`, `idmargins.py` | the margin of every sync train of a capture against the decoder's thresholds (in half cells; below 0 means the decoder loses the sync byte) |
| `window.py`, `outliers.py`, `sidestats.py`, `recwin.py` | raw flux intervals around a point of a track; flux quality per side and per sector |
| `decmodel.py` | a model of the production decoder at the level of flux intervals, checked against the RTL on the failing track side; `survey` lists the headers the decoder cannot read on every side of a capture |
| `pllcheck.py` | the same track side decoded with a phase-tracking PLL of the kind the Greaseweazle software uses |
| `relaxcheck.py` | on the model: what accepting an address mark after two sync bytes at exact spacing would recover, and whether it adds false marks |
| `romdiff.py` | the stock ROM against another 1581 ROM, by address range |
| `exp_weak_id.py` | the genuine ROM formatting two cylinders with one header made unreadable after its Write Track: job result, retries, motor time |
| `mkflux.py`, `f77h0.txt.gz` | writes the flux of one track side as edge times for the benches; the file is cylinder 77, side H=1, of the disk as the failed format left it (three revolutions of a formatted, empty track) |
| `tb_flux_dec.vhd`, `evsum.py` | bench: the production decoder on such an edge file, with a summary of what it decoded per revolution |
| `tb_flux_ctl.vhd`, `ctl_run.log` | bench: the production controller with decoder, read-ahead buffer and read FIFO on the same flux, replaying the verify of the failed format; the log of the run |

The capture is `G5-after-E4-format-JiffyDOS-R3A-R6drive-A25.scp` from the attachment of the same name of comment 35.

```text
T=<repository>/doc/dev-fdd/tools/part_e/format_stop
P=<repository>/CORE/vhdl/physical_1581

python3 -I $T/a1margins.py capture.scp                 # worst margin per side; cylinder 77 head 0: -0.073 at 118.14 ms
python3 -I $T/decmodel.py survey capture.scp           # the headers the decoder misses, per side
python3 -I $T/mkflux.py capture.scp 77 0 f77h0.txt     # the file that is in this folder, gzipped
python3 -I $T/mkflux.py capture.scp 77 0 f77h0_x4.txt --loops 4

# the decoder alone (45 s): every revolution decodes the headers 1 2 3 4 5 6 8 9 10 and never 7
nvc --std=2008 -a $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $P/physical_1581_mfm_gaps.vhd \
    $P/physical_1581_mfm_quantise.vhd $P/physical_1581_mfm_gaps_to_bits.vhd $P/physical_1581_mfm_bits_to_bytes.vhd \
    $P/physical_1581_mfm_decoder.vhd $T/tb_flux_dec.vhd -e -gG_IN=f77h0.txt -gG_OUT=events.txt tb_flux_dec -r
python3 -I $T/evsum.py events.txt 9954550

# controller, decoder and read-ahead buffer (7 minutes): Read Address finds sector 2, sector 3 is read live,
# 4 to 6 come from the buffer, sector 7 ends with result 04 (record not found) after five index edges
nvc --std=2008 -a $P/physical_1581_pkg.vhd $P/physical_1581_crc.vhd $P/physical_1581_inputs.vhd \
    $P/physical_1581_mfm_gaps.vhd $P/physical_1581_mfm_quantise.vhd $P/physical_1581_mfm_gaps_to_bits.vhd \
    $P/physical_1581_mfm_bits_to_bytes.vhd $P/physical_1581_mfm_decoder.vhd $P/physical_1581_mfm_encoder.vhd \
    $P/physical_1581_writer.vhd $P/physical_1581_rdahead.vhd $P/physical_1581_rdfifo.vhd \
    $P/physical_1581_controller.vhd $T/tb_flux_ctl.vhd -e -gG_IN=f77h0_x4.txt tb_flux_ctl -r

python3 -I -B $T/exp_weak_id.py                        # the DOS side: error 20 without a retry
```

Both benches were run from this folder against the RTL of the repository, with the results given in the comments above. For a change of the decoder, `tb_flux_dec` on `f77h0.txt` is the case that has to turn from "never 7" into all ten headers.

## `dos_behavior/`: orphan blocks and the number of sector writes (sections 5 and 6)

| File | What it does |
| --- | --- |
| `d81orph.py` | directory, block chains and BAM of a D81: the blocks that are allocated but belong to no file, and the files whose last block is completely full |
| `orph_match.py` | pairs every orphan block with the file whose last block it follows |
| `chunks.py` | the number of transfers DraCopy's file copy needs per file |
| `u2_spacing.py`, `runs/` | a series of `U2` block writes on the genuine ROM with a settable time without ATN between them, counting the Write Sector commands; the logs of the runs the record quotes |

```text
T=<repository>/doc/dev-fdd/tools/part_e/dos_behavior
python3 -I $T/d81orph.py image.d81
python3 -I -B $T/u2_spacing.py stock 2 0 40 550 400    # track 2, 40 blocks, 550 ms without ATN: 10 Write Sectors per U2
python3 -I -B $T/u2_spacing.py stock 2 0 40 90 200     # 90 ms: one write-back per track side
```

The first argument of `u2_spacing.py` is a ROM file whose name ends in `.rom`, or any other word for the stock ROM.
