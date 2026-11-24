# Tools for the Internal 1581

## `diag_dump_decode.py`: the dumps of the diagnostic device

Decodes the dumps that testers paste into a GitHub issue (the blocks of the QNICE monitor commands `MD 7000 703F`, `MD 7040 707F` and `MD 7080 70A5`) with the names of the register map in `doc/1581_dd_debug_device.md`, the trace ring oldest entry first. Dumps of older maps decode as well: map v8 ends at `709D`, map v9 at `70A1`; the words a dump does not contain are left out. The words of map v10 are decoded only for a device whose `VERSION` reports map v10 or later; a v10 device dumped without them gets a note. The decoder prints the longest index gap in revolutions of the index period of the same dump: within 0.1 of 2 to 5 revolutions it names the index pulses that did not arrive (what a mechanism that withholds them while the head steps shows after a recalibration at 6 ms per step), and it flags a gap that is not near a whole number of revolutions; with every gap longer than a revolution it prints the cross-check with `CNT_RDY_STALE` and `CNT_CHANGE`, which count a disk change and not withheld pulses. Then the count of stale READY, and the count and the switch of the decoder's tolerance for a weak sync byte (bits 15 to 1 of `RD_CTRL` are flagged when they are not 0). A line that is not `<address>: <words>`, a word that is not hexadecimal and a missing block are skipped with a note.

```text
gh api repos/MJoergen/C64MEGA65/issues/257/comments --paginate > comments.json
python3 -I doc/dev-fdd/tools/diag_dump_decode.py comments.json            # every dump of every comment
python3 -I doc/dev-fdd/tools/diag_dump_decode.py comments.json 17 18      # the dumps of comments 17 and 18
```

## `idx_gap_model.py`: what the index gap reads

Computes `IDX_GAP_MAX_MS` (map v10) after a recalibration from cylinders 0, 39 and 79, after seeks over 50 and 79 cylinders and for a recalibration from every cylinder, on a mechanism that withholds its index pulses from the first step pulse of a train until a hold time after its last one (or after the end of BUSY), at 6 and 3.03 ms per step, over every index phase. The model is in the header of the script; `python3 -I doc/dev-fdd/tools/idx_gap_model.py [revolution in ms]`, about 10 s.

## `regression/`: the simulation regression of `CORE/vhdl/physical_1581`

The benches of the controller simulate the 50 MHz clock for up to 1.5 s, so the whole regression takes seven and a half core hours (65 minutes with eight jobs at a time on an 8-core machine). These scripts run it as a queue of jobs with a limit on how many run at the same time, and they give a verdict per job. They need GHDL 5.1.1, python3 and git; `jobq.py` calls `script(1)` in the form of macOS.

```text
T=<repository>/doc/dev-fdd/tools/regression
D=<absolute path of a new directory outside of the repository>

bash $T/reg_setup.sh <repository> <commit> $D         # clones the commit into D/src and builds the benches: REG_SETUP_OK
{ python3 -I $T/reg_queue.py $D; echo END; } > $D/queue   # the 28 jobs, one per line
echo 4 > $D/slots                                     # jobs that run at the same time; re-read every 5 s
cd $D && python3 -I $T/jobq.py queue slots status.txt # the runner; start it as a background job
python3 -I $T/reg_check.py $D                         # the verdicts; exit status 0: all jobs passed
```

The regression runs on a clone of the commit, not on the working tree, so the tree can be edited while it runs. `status.txt` gets a line when a job starts and when it ends; the logs are in `D/b/logs`. Writing 0 into `slots` lets the running jobs finish and starts no new one.

| Jobs | What they run | Wall time per job (eight at a time on eight cores) |
|---|---|---|
| `unit_rdahead`, `diag`, `mech_model`, `ovf` | unit bench of the read-ahead engine, bench of the diagnostic device, of the mechanism model, of the read FIFO overflow | seconds; `ovf` 7 minutes |
| `units` | `units.sh`: the eight unit benches that have no runner of their own (CRC, MFM decoder and encoder, the A/B harness of the quantiser, input synchronizer, read FIFO, write FIFO, writer) | 9 minutes |
| `mut_rdahead` | `mutants_rdahead.py`: 35 mutants of the read-ahead engine, each of which the unit bench has to reject | 1 minute |
| `mut_diag_runner` | `mutants_diag.py`: 59 mutants of the diagnostic device (the words of map v10 and the words around them), each of which its unit bench has to reject unless it is marked equivalent with the reason (3 are); nvc, or GHDL with `SIM=ghdl` | 10 minutes with nvc |
| `rdseq_accept_n10_max260`, `sweep_gap*` | `tb_physical_1581_rdseq`: ten sectors of a track side within 260 ms, and three points of the sweep of the request time | 8 to 23 minutes |
| `write_g6_l15`, `write_g7_l15` | `run_tb_write.sh`, groups 6 and 7: the read-ahead next to the write engine | 28 and 11 minutes |
| `loop_g1` to `loop_g5` | `tb_physical_1581_rdahead_loop`: the read-ahead in the closed loop | 17 to 44 minutes |
| `controller` | `tb_physical_1581_controller` | 34 minutes |
| `media_contract_runner` | `run_tb_media_contract.sh`: the media contract with nvc and with GHDL, and 31 mutants with nvc (with GHDL alone if nvc is not installed) | 40 minutes |
| `write_g1_l15` to `write_g5_l15` | `run_tb_write.sh`, groups 1 to 5 (group 2 with three DRQ latencies) | 12 to 21 minutes |
| `rdahead_ctl_runner` | `run_tb_rdahead_ctl.sh`: the controller's read-ahead on a synthetic record stream and 18 mutants | 13 minutes |

`reg_check.py` passes a job only if its log shows the pass line of its kind (`ALL TESTS PASSED` and `simulation finished` for a bench, `RESULT: PASS` for a runner (a job whose name ends in `_runner`), 35 killed mutants, `UNITS RESULT: PASS`), no error or failure report, and the exit status 0. For a write group it also wants the line `group G latency L us: rc=0 | ... ALL TESTS PASSED ... | ... simulation finished`: `run_tb_write.sh` returns the exit status of the twin check, which is 0 even when the simulation was killed or failed.

Each of these also runs alone:

* `units.sh <repository> <scratch directory>`
* `mutants_rdahead.py <repository> <scratch directory> [mutant ...]`
* `mutants_diag.py <repository> <scratch directory> [mutant ...]` (`SIM=nvc`, the default when nvc is installed, or `SIM=ghdl`)
* `main_diff_check.sh <repository> <base commit> <scratch directory> [tools.vhd of QNICE]`: the differential GHDL analysis of `CORE/vhdl/main.vhd` against a base commit, with the entities of `CORE/vhdl/physical_1581` and `c1581_error_led` in the library. GHDL cannot analyze `main.vhd` completely (the sub-entities in Verilog and those of the framework are not in its library), so the check is that the set of diagnostics is the same on both sides.

Not part of the queue, because they need the submodules and analyze `main.vhd`: `CORE/vhdl/test/tb_drive_led/run.sh`, the runners of `tb_shortcuts`, `tb_stereo_mix`, `tb_capslock`, `tb_turbo` and `tb_ntsc` (`doc/dev-a22x3/tools/suites.py` runs them in a row), and the genuine-ROM proofs in `doc/dev-fdd/rom_emu`.

Not part of the queue either: the 17 mutants of the decoder's tolerance for a weak first sync byte (`python3 -I -B CORE/vhdl/test/tb_physical_1581_codec/mutants_mfm_decoder.py <repository> <absolute scratch directory>`, nvc, about 16 minutes, `MUTANTS RESULT: PASS`), the bench of the WD1772 model in physical mode in the submodule (`CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_physical.sv`, Icarus Verilog, about half an hour; its header has the recipe), and the flux benches and tools of part E of issue #257 (`doc/dev-fdd/tools/part_e/README.md`).
