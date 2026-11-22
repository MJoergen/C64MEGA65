# Issue #257, part E: causes of the findings in everyday operation (Internal 1581)

Entry point for anyone, human or coding agent, who picks up this work. paich64 ran part E of the test plan (comment 31 of issue #257: scratch, rename, copy, validate, copy programs, JiffyDOS) with WIP-V6-A25 on his R3A with the drive mechanism of his R6, and reported in comments 34 and 35. Nearly everything passed. This file records the causes of the things that did not pass or raised a question. It is an analysis: no RTL was changed. Section 8 lists the changes that suggest themselves and how they depend on each other; section 9 the tests that would close what is still open.

## 0. Result

| Finding | Cause | Whose behavior | What follows |
| --- | --- | --- | --- |
| MFCWT gets `74,DRIVE NOT READY` at its check, almost always with JiffyDOS (section 2) | MFCWT sends `UI` before every check. The DOS recalibrates the head inside that command. Our READY falls when no index pulse arrived for 500 ms, and the mechanism delivers none while it steps: READY is low for some tens of milliseconds after the recalibration. The DOS examines READY once | a defect of our READY model; a genuine 1581 passes | change candidate 8.1 |
| After every long seek the head is 2 cylinders short of where the DOS wants it; the DOS corrects it (section 3) | Our controller steps every 3.03 ms. The DOS asks for 6 ms. The R6's mechanism does not follow a long train at 3 ms completely | a deviation of ours from the WD1772; harmless for the data | change candidate 8.2, only together with 8.1 |
| One format stopped after track 78 with error 20 (section 4) | One sync byte of one sector header was recorded weakly in that pass. Our decoder judges every flux interval alone against a fixed threshold and needs all three sync bytes; this header was invisible to it. The DOS does not retry in a format | a weakness of our decoder; a genuine 1581 would most likely have completed the format | change candidate 8.3 |
| Orphan blocks: 2 after each file copy, 29 after SAV-WRITE (section 5) | A file whose data ends exactly on a block boundary keeps the block that the DOS allocated ahead | the 1581 DOS (and the 1541 DOS); identical on a genuine drive | nothing |
| 32000 sector writes for a block copy with the standard Kernal, 1600 with JiffyDOS (section 6) | The DOS writes a changed track side back when the bus has been quiet for 320 ms. With the standard Kernal that happens after every `U2` | the 1581 DOS; identical on a genuine drive | nothing |
| `7080` reads `3880` after a block copy (section 7) | Bit 13 of `WR_STATE` is the side bit H of the ID of the last Write Sector | an instrument, no finding | nothing |
| Maverick V4.0 does not copy (section 7) | not analyzed: the test between two disk images is still to come | open | wait |

## 1. The evidence and how to read it

* The two reports: comments 34 (E1 to E3, standard ROMs) and 35 (E4, JiffyDOS) of issue #257, with 34 dumps of the diagnostic device (`doc/1581_dd_debug_device.md`) and twelve attachments (Greaseweazle reads with flux, the D81 images after the copies back, the copy programs).
* Decode the dumps with `python3 -I doc/dev-fdd/tools/diag_dump_decode.py comments.json 34 35`. A seek shows in the trace ring as one `STEP` entry per cylinder, with the controller's own estimate of the head position.
* The source disk of E3 and every read and image of the disk G5 after it contain adult material (the tester warns about it). Everything here was done on directory structure, block chains and flux; nothing of it needs to be looked at.
* How each statement below was obtained is marked: **executed** (the genuine ROM in the cycle-exact emulator of `doc/dev-fdd/rom_emu`, or the production RTL in a simulator), **measured** (in the tester's dumps, images or flux), **read** (in the RTL or in a disassembly), **inferred**.
* The tools are in `doc/dev-fdd/tools/part_e/` (section 10).

## 2. MFCWT and `74,DRIVE NOT READY`

**What the tester saw.** MFCWT 1.6 (Multi Floppy Commander with Turbo, a cartridge) checks before a format and before each file of a copy whether the disk has changed since it read the directory. With the JiffyDOS Kernal that check ended with `REREAD DIRECTORY FIRST` or `REREAD TARGET DIRECTORY` in almost every try, and the error channel read `74,DRIVE NOT READY,00,00`. With the standard Kernal the same thing happened once in two complete copies of 127 files. The dumps taken right after show two forms. Form 1: the ring is full of single steps inward, up to the directory cylinder, and nothing follows them (dump MFCWT-5; the stop of comment 34). Form 2: the same steps, a Read Address that finds cylinder 37 instead of 39, two more steps inward, and nothing after them (dumps MFCWT-1 and MFCWT-4).

**What MFCWT sends (read).** The check is at `$8562` of bank 1 of the cartridge. For a 1581 it first sends the command `UI` (`$8E43`; the two characters are stored at `$8E6C`) and reads the answer, then it opens `$` with secondary address 0 and reads the whole listing, comparing name, ID and a checksum with the values of its last `L`. Any I/O error gives one of the "REREAD" messages. The flag that asks for the `UI` (`$081A`) is set by the drive probe at start; only the branch for a 1571 clears it again while the drive answers, so for a 1581 the `UI` precedes every check, with either drive ROM.

**What the DOS does with `UI` (executed, stock ROM and JiffyDOS ROM, identical to 0.1 ms).** `UI` is a warm reset of the drive, and its whole initialization runs inside the command, 1.92 s with a stopped motor. Times in ms after the motor line rose:

| ms | What |
| --- | --- |
| -529 to -1 | job `$82`: test of the disk controller, the motor is not touched |
| 0 | bump (job `$C0`): motor on, then 80 ticks of 10 ms |
| 800.9 | readiness stage `$CD7B`: disk change line (PA7), then the exam of READY (PA1, `$CDBC`) |
| 801.1 | Restore: 39 steps outward from the directory cylinder |
| 939 to 990 | two Read Address on cylinder 0 with their exams, write protect sense, then the job for track 40 sector 0 with a third Read Address |
| 992.4 | Seek of 39 steps inward, then 18 ms of delay |
| 1130.2 | readiness stage again: **the exam that fails in form 1** |
| 1130.6 | exam at `$CD08`, Read Address: finds cylinder 37 on the R6's mechanism (section 3) |
| 1134 | Seek of 2 steps |
| 1158.6 | readiness stage: **the exam that fails in form 2** |
| after | Read Address, the sectors of the directory track; the command ends and answers `73,...` |

An error of the initialization is ignored: `UI` answers `73` in every case. Job error 3, which the DOS reports as 74, has two sources: the readiness stage (`$CDA8`: the disk change line still active after the DOS's step pair, or READY low) and the exam of READY in front of a Read Address (`$CD39`). The rings show no step pair, so the change line was quiet and it was READY. The motor line never falls in the sequence, and the bump waits its full 0.8 s.

**Why the exam fails (read, then inferred).** `media_ready` of `physical_1581_controller.vhd` (the process part "motor / readiness") rises with the first index edge after the motor request rose. It falls with the motor request, on reset or disable, and when no index edge arrived for `2 * G_PERIOD_MAX_CYC` = 500 ms while the motor request is on. Nothing else lowers it. In the failing dumps the motor was started from standstill by the bump (the last spin-up time, word `70A0`, is 620, 635 and 662 ms: a start from standstill, and no restart after it). The first exam at 800.9 ms passed, or there would be no steps in the ring. So READY was high at 800.9 ms and low at 1130 or 1159 ms with the motor on throughout: the controller saw no index edge for 500 ms, while the disk turned at 199.3 ms per revolution and a Read Address between the two exams of form 2 read a sector header. Two index pulses in a row did not reach the controller. For a first pulse at 620 ms the next two are due at 819 ms and at 1019 ms: the first falls into the Restore's step train (801 to 920 ms), the second into the Seek's (992 to 1112 ms).

**The mechanism withholds index pulses while it steps (inferred, not observed).** The RTL does not: the index input is filtered for 200 µs and nothing else, and the step logic does not touch it. Drives of this kind are known to do it: the TEAC FD-235HF, for example, gates INDEX until 15.8 to 17.9 ms after the last step pulse. The make of the tester's mechanism is not known. With that one assumption the genuine ROM reproduces the dumps without a free parameter (executed: a sweep over the time of the first index pulse in steps of 15 ms from 480 to 690 ms, head on the directory cylinder, motor stopped before; a first pulse later than 602 ms has both of its successors inside the two step trains, so READY falls 500 ms after it):

| First index pulse after motor-on | Result of the `UI` | Dump |
| --- | --- | --- |
| 480, 510 ms | READY falls during the directory reads of the initialization and is back when `UI` ends | |
| 495 ms, 525 to 600 ms | no failure | |
| 615, 630 ms | form 1: READY has fallen at the exam at 1130 ms | MFCWT-5: 620 ms |
| 645 ms | form 2: READY falls between the Read Address and the exam at 1159 ms | MFCWT-1: 635 ms |
| 660 ms | as form 2, with one more Read Address before the failing exam | MFCWT-4: 662 ms shows form 2 |
| 675, 690 ms | READY falls during the directory reads and is back when `UI` ends | |

The boundary between the last two forms depends on how long the first Read Address waits for a sector header, 0 to 20 ms on the disk and a fixed time in the emulation, so 662 ms fits form 2. With the head on another cylinder the windows move (head on cylinder 79: form 1 at 525 to 540 ms and again at 615 to 630 ms, form 2 at 555 to 570 ms; head on cylinder 10: no failure). With the motor already running the result depends on where the index is when the `UI` arrives: six of nine phases fail. The stop of comment 34 (standard ROM, in the middle of a copy) shows form 1 and cannot be placed more exactly: the dump holds neither the head position before the `UI` nor whether the motor was still running.

**Why the user sees it with JiffyDOS and hardly ever without (executed for the DOS side, inferred for the bus).** The failure inside `UI` is silent. READY comes back with the next index pulse, 60 to 90 ms after `UI` has ended in the two forms above. MFCWT's `$` then starts a job with the motor running, so the DOS examines READY at once, and it reports 74 if that happens before the pulse (executed: 10 ms and 60 ms after the end of `UI` give 74, 90 ms gives the directory). With JiffyDOS the 36 characters of the `73` answer and the OPEN take 10 to 20 ms. With the standard Kernal they take 80 to 90 ms (about 2 ms per byte, from the tester's `LOAD` times), which is usually enough. The drive ROM plays no part: the code of the controller, of the jobs and of the initialization is the same in the JiffyDOS ROM, byte for byte, except for one `SEI` at `$C160` that changes nothing here.

**A genuine 1581.** It runs the same ROM through the same sequence at every power-on, and the READY of its mechanism is a status of the drive that does not depend on the head moving. Every exam passes; MFCWT is merely slow on it (1.5 to 2 s per check).

**Where else our READY falls for the same reason (inferred).** READY falls when two index pulses in a row are hidden, and it stays low until the next pulse, 98 ms at the most. A single step train does that only if it lasts longer than a revolution, at our pace of 3.03 ms a seek over more than 60 to 65 cylinders, and then the low phase falls into the fill of the track cache that follows every seek: the controller's read operations wait for READY (for up to 1.1 s), and the DOS examines READY only when a job starts, so such a seek passes unnoticed. Two trains in a row, as in a recalibration, put the low phase where the next job starts: after `UI` or `UJ`, at power-on (silent: the next access is a new job, seconds later), and after the bump the DOS makes when two retries of a read have failed (the attempt after the bump can then end with 74). A program that sends `UI` and a disk command right behind it over a fast bus is the case that shows. A write operation would be cut off if READY fell while it runs, but the DOS puts the fill of its track cache, a fifth of a second of reading, between every seek and its next write.

## 3. The head is 2 cylinders short after a long seek

**What the dumps show (measured, every dump of the issue).** Whenever a ring shows the Read Address after a recalibration on the R6's mechanism, the track register is 39 and the ID says cylinder 37: comment 17 (dumps 9a and 10, R6 board, A21X1), comment 30 (9a and 10), comment 34 (DraCopy start), comment 35 (MFCWT-1, MFCWT-4). The DOS answers with a Seek of two steps and a second Read Address, which finds 39. About twenty more dumps show the controller's estimate 2 above the cylinder after a boot. The long seek outward at the end of a format (79 to 39) ends 2 cylinders short as well. Single steps and moves of two steps never slip, and the format, which steps one cylinder at a time, puts every track in its place (the IDs on the Greaseweazle read count 0 to 79). The R3A's own mechanism shows no shortfall in the one dump that can tell (comment 24, D1 and D2). There is never a 1 or a 3.

**The cause (read; the link to the mechanism is inferred).** The 1581 ROM issues Restore `$08`, Seek `$18`, Step In `$48` and Step Out `$68`: rate bits 00, which a WD1772 turns into 6 ms per step. In physical mode the WD1772 model does not pace the steps: state 1 of the seek machine in `fdc1772.v` requests one step from the controller and continues on its acknowledge, and only the branch for disk images loads `step_rate_cnt`. The controller's step engine alone sets the pace: 24 µs of direction setup, 4 µs of pulse, `G_STEP_REC_CYC` = 3 ms of recovery (4 ms after a reversal): 3.03 ms per step, twice as fast as a 1581 steps. Mechanisms of this kind are specified for 3 ms as their limit. The R6's mechanism loses two cylinders in a long train at that pace, in either direction, which is what a stepper motor does that drops one electrical cycle.

**Consequences.** None for the data: reads and writes take place only under a sector header whose cylinder matches the request, and the DOS checks the position with a Read Address after every seek. The cost is one Read Address, a Seek of two steps and one more exam of READY per long seek, about 40 ms. Form 2 of section 2 exists only because of it.

## 4. The format that stopped after track 78

**What the tester saw.** One format from DraCopy under JiffyDOS ended after about 1 min 37 s with error 20; the Greaseweazle read shows tracks 1 to 78 formatted and tracks 79 and 80 untouched. Two formats right after it were complete, as were about ten on the days before.

**What happened (measured in the dump and in the flux).** The format had written cylinder 77, side H=1, with a Write Track that ended without an error. In the verify the Read Address found sector 2, the Read Sectors 3 to 6 were fine, and Read Sector 7 ended with "record not found" after five index pulses. In the Greaseweazle read of the disk as that format left it, the first of the three sync bytes in front of the ID of sector 7 has the flux intervals 6.47, 6.88, 6.75, 7.80 and 5.60 µs where 6, 8, 6, 8 and 6 µs are nominal, the same in every revolution of the capture. That is peak shift: the short intervals have grown, the long one has shrunk by 1.1 µs. The whole side has more jitter than any other side of the disk, most of it between 99 and 177 ms after the index. The same header is normal in the five other formats of that disk, and the bits are correct. So one pass recorded weakly, a matter of head and medium in that moment; the writer is digital, precompensation was off as the ROM asks for cylinders 44 to 79, and there was no underrun.

**Why the drive could not read it (read and executed).** The quantiser of the decoder classifies each interval alone, against the midpoints at 2.5 and 3.5 times its estimate of the half cell. The shrunken interval is 343 to 346 clock cycles, the midpoint 350 to 352: it is taken for a medium interval instead of a long one, and the first sync byte does not match. An address mark needs three sync bytes at exact spacing, so the header of sector 7 is not seen in any revolution. The production decoder fed with the flux of that track side decodes the headers of sectors 1 to 6 and 8 to 10 in every revolution and never that of sector 7 (bench `tb_flux_dec`). The production controller with decoder and read-ahead buffer on the same flux gives the trace of the dump step for step: Read Address finds sector 2, sector 3 is read live, 4 to 6 come from the buffer, sector 7 ends with result 4 after 862 ms and five index edges (bench `tb_flux_ctl`). The read-ahead buffer of A25 has no part in it: it never held sector 7. The quantiser and the three-byte rule are unchanged since July 2026.

**The DOS (executed).** The verify of a format has no retry: job error 2 ends the command with error 20, and the motor runs on for 10.2 s. The JiffyDOS ROM is identical in all of that code and behaves the same to the cycle.

**The counters of that dump.** One lost sync byte per revolution leaves two sync candidates outside of a train, one ID mark fewer and one data mark that no header armed. The head stayed on that side for about 56 revolutions (verify, search, the 10.2 s of motor run-on), which accounts for the surplus in `CNT_A1_CAND` (111 more than three times `CNT_A1_TRAIN`, against 0 to 4 in every other dump) and in `CNT_DAM_UNARMED` (214 against about 158). The sector the last result names, C=77 H=1 R=6, is that of the previous read: a search that runs out does not update it.

**A genuine 1581.** A WD1772 times every transition against a recovered clock. The largest error of a single transition here is 0.66 µs, inside its window; the Greaseweazle's decoder of the same kind reads the header in every revolution. So a genuine 1581 would most likely have passed the verify (a judgment, not a measurement: nobody read that track on a 1581).

**How often, and where else.** In the six Greaseweazle reads of that disk, one sync train of about 19,200 is below the decoder's threshold, and the smallest margins are on cylinders 44 to 79. The field count fits: one failure in about 15 formats, none in hours of copies. A weak sync train in a file that is read later costs five attempts of the DOS (two retries, a bump, two more) and then error 20. One that a `SAVE` writes is caught by the write-back verify, which rewrites the side. A disk from another drive with such a train reads on a 1581 and not on ours.

## 5. Orphan blocks

**The rule (measured on ten images).** A file whose data fills its last block exactly, 254 x n bytes, leaves one block allocated in the BAM that belongs to no file: the block that follows the file's last block in the order of allocation. No other file leaves one. The two files of the copied disk with 508 and 14732 bytes give the two orphans at track 57 sector 38 and track 8 sector 26; the 29 files of SAV-WRITE have 7620 bytes each (60 records of 127 bytes) and give 29; the disk G3 has no such file and no orphan.

**The DOS (read).** When the 254th byte fills a buffer, the DOS allocates the next block at once (`$9112`, `$B668`, `$B572`) and writes the full block with a link to it. At CLOSE it finds the new buffer empty (`$9A40`), goes back to the previous block, writes it again with the link 00 `FF` and takes one off the block count (`$9A47` to `$9A69`). Nothing on that path frees the block it had allocated. The JiffyDOS ROM is identical there. The 1541 ROM has the same sequence at `$DB62` to `$DBA1`.

**A genuine drive (measured, issue #248).** In October the SAV-WRITE images of the core were compared with VICE 3.8 in true drive emulation, which runs the genuine ROMs: identical sector for sector, the BAM included, for a 1581 and for a 1541 (20 files of 30 full blocks: 2540 blocks free = 3160 - 620).

A validate frees these blocks, as E1 showed. Both of our drives show them because the BAM lives in the drive computer, whatever the medium.

## 6. The number of sector writes

**The DOS (read and executed).** A `U2` on a track side that is in the cache copies 256 bytes into the cache and marks it changed; no disk access follows (`$CF8A`). The side is written back as a whole, ten Write Sectors and, on a disk with verify on, ten reads, in two cases: when a job needs another side (`$C11D`), and when the drive has seen no ATN for 32 ticks of 10 ms (`$B151`; the counter `$9C` is reloaded from `$9D` at every ATN, `$ABD0`, and `$9D` is `$20` after a reset). The genuine ROM in the emulator, with a series of `U2` to one track: 10 Write Sectors per `U2` when 550 ms without ATN lie between them, one write-back per side when 90 ms do; the threshold is at 310 to 320 ms; the same with the JiffyDOS ROM, whose code is identical there.

**The copy.** DraCopy reads the next block from drive 9 between two `U2`. With the standard Kernal that transfer takes more than half a second in which drive 8 hears no ATN, so it writes its side back after every `U2`: 3200 x 10 = 32000. With JiffyDOS the transfer takes less than 100 ms, and each side is written once: 160 x 10 = 1600. A genuine 1581 does the same; the core adds no write of its own (the counter counts the Write Sector operations the DOS issues). The 10 writes per track side of a `SAVE` plus 20 for track 40 are the same mechanism. The command `"U0>I"+CHR$(n)` sets the delay in ticks of 10 ms (`$AA46`).

## 7. Smaller points

* **`7080` = `3880`:** bit 13 of `WR_STATE` is H of the ID under which the last Write Sector was written (`physical_1581_diag.vhd`, the read mux of `RM_WR_STATE`). A block copy ends on the last sector of track 80, which is on the side with H=1; a file copy ends with the BAM on the other side, hence `1C80` there (bit 10: precompensation, which the ROM uses on cylinders 1 to 43).
* **Maverick V4.0** drives the disk controller with its own code. With the internal drive as source it recalibrates and then issues no read at all; with the image drive as source it reports read errors. The test between two images that was asked for in comment 32 decides whether the simulated 1581 as such is the subject. The 2-cylinder shortfall does not explain its stop: the Restore in dump E3b ends on track 0.
* **MFCWT between two disk images under JiffyDOS** stopped once with `SOURCE READ ERROR` after 69 files. One observation, error channel not read, no instrument on the image drive: not analyzed.
* **The directory read after the failed format** reached no operation of the controller, and the LED blinked: the DOS answered it by itself after the failed format. Not followed up.

## 8. Changes that suggest themselves (none is implemented)

**8.1 READY while the head moves.** `media_ready` should not count the time of a step train and of the settle time after it toward the 500 ms without an index pulse (restart `idx_gap_cnt` with every step and while `head_settled` is low). A disk that is pulled during a seek is then noticed half a second after the head has settled; the disk change latch and the abort of the read engine guard the data as before. Proof to deliver with it: a bench of the controller whose index source pauses while steps run (READY has to stay), and the `UI` sequence of section 2 on the genuine ROM for every time of the first index pulse.

**8.2 The step rate of the WD1772.** Pace the steps in physical mode by the rate bits of the command, as the image branch does (6 ms for the ROM's commands, 12 ms if the ROM's probe of the CIA clock fails). Expected: the R6's mechanism no longer falls short, to be shown on the hardware, where the first Read Address after a reset has to find cylinder 39. Seeks then take as long as on a 1581: 234 ms instead of 119 ms for 39 cylinders. **Not without 8.1:** at 6 ms a seek over 50 cylinders lasts 300 ms and one across the whole disk 474 ms. On a mechanism that hides its index pulses meanwhile, READY then falls before the seek has ended, and the exam right behind it fails: in one of twelve seeks over 50 cylinders, in almost every seek across the disk.

**8.3 The decoder's tolerance for a weak sync byte.** Either accept the address mark after two sync bytes at exact spacing, with the CRC preset as for three, or decide an interval near a midpoint by its phase against the cell clock, as a PLL does. On the model of the decoder the first variant recovers the header of sector 7 and adds no mark and no bad ID on three captures with spliced sectors (4,800 sectors, `relaxcheck.py`). The three-byte rule was introduced against false syncs at write splices on our own mechanism, so the change needs the codec benches and the splice cases of the regression; `tb_flux_dec` with the flux of section 4 is the case that has to turn from failing to passing.

**8.4 Optional: precompensation on the inner cylinders too.** The 1581 ROM switches it off for cylinders 44 to 79, where the margins are smallest; switching it on there adds 0.07 to 0.14 half cells of margin and leaves the magnetic fingerprint of a 1581. `WR_CTRL` (`709A`) = 2 allows a trial without a build.

## 9. What is still open, and the cheapest tests

* **The index pulses during a step train have not been observed;** that they are missing follows from the READY rule and the timeline. Three ways to see it, in the order of effort:
  * The failure without MFCWT, with JiffyDOS active: a BASIC loop that sends `UI`, reads the answer and opens `$` in the next statement (`PRINT#15,"UI":INPUT#15,A,A$,B,C:OPEN 2,8,0,"$":INPUT#15,E,E$,T,S:CLOSE 2`), with a pause of 15 s between the rounds so that the motor stops. Expected: `74` in a good part of the rounds, and none when a pause of a quarter of a second sits between the answer and the OPEN.
  * The count: the same number of seconds with the motor on, once filled with `UI` commands (two step trains each) and once with a command that does not move the head, timed with `TI`, a dump before and after each. If the mechanism withholds index pulses, `CNT_IDX_RAW` (`7014`) grows by five per second in the second run and by about a sixth less in the first.
  * An instrument in the next build: the longest time between two index edges while the motor is on. It reads 199 ms on a mechanism that does not hide them and 398 or 598 ms on one that does.
* **The tester's copies could not have shown a long seek going wrong:** read in sequence, the files of the copied disk need one head move of more than 65 cylinders (`longseeks.py`), and section 2 explains why a single long seek passes anyway.
* **Whether 6 ms cures the shortfall** can only be shown on the hardware (8.2).
* **Whether a WD1772 reads the weak header:** write the captured track to a disk with the Greaseweazle and read it in a 1581. Not needed for 8.3.
* **How often a sync train is at the limit on other mechanisms and media:** `CNT_A1_CAND` minus three times `CNT_A1_TRAIN` in a dump after a format; a value above 4 means lost sync bytes (2 per revolution and train).
* **The margin of the standard Kernal** in section 2 is thin (80 to 90 ms against 60 to 90 ms): the one failure in 254 checks fits, but the bus times were derived from `LOAD` times, not measured.
* **Orphan blocks, by hand:** a SEQ file of exactly 254 bytes on a fresh disk gives 3158 blocks free, 3159 after a validate.

## 10. Tools

Everything is in `doc/dev-fdd/tools/part_e/`; its `README.md` has the commands. In short: `mfcwt_74/` the harness that runs DOS commands on the genuine ROM with the READY rule of the RTL and a mechanism model (`h257.py`), the `UI` experiments and the sweep with its log; `mechanism/` the statistics of head position against the IDs over every dump of the issue; `format_stop/` the reader for Greaseweazle flux, the margin survey of the sync trains, the model of the decoder, the two benches that run the production RTL on the flux of the failing track side, and that flux; `dos_behavior/` the orphan block analysis of a D81 and the `U2` series on the genuine ROM.
