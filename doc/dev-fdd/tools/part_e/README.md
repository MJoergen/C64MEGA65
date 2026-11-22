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
| `h257.py` | the harness: the genuine ROM on the cycle-exact 6502 of `rom_emu`, READY as the RTL derives it (rises with the first index edge after motor-on, falls 500 ms after the last one), a mechanism with a settable time of the first index pulse, with or without index pulses during step trains (and for a hold time after them), and with a settable number of steps it loses in a long seek; DOS commands are put into the command buffer, and every exam of READY, every job and every command to the disk controller is logged with its time |
| `exp7_timeline.py` | the full timeline of `UI` and the `$` that follows it |
| `exp5_sweep.py`, `run_sweeps.sh` | the sweep over the time of the first index pulse; `sweep_stock.log` is its output for the head on cylinders 39, 79 and 10 |
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
```

Both timelines were reproduced from this folder, the second one with the JiffyDOS ROM as `c1581.rom`; the outputs are identical to the two files except for the header line.

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
