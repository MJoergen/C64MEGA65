# 1581-ROM-in-the-loop emulator (issue #90 bring-up tool)

Lives at `doc/dev-fdd/rom_emu/` (moved out of the submodule in round 10).
Runs the genuine 1581 DOS ROM (318045-02, converted on the fly from
`CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1581_rom.mif.hex`) on a small Python
6502 against device models that mirror the C64MEGA65 phys-mode RTL semantics
(WD1772 front end, CIA senses, controller readiness). This is how the round-5
hardware failure (DOS error `$09` after six Read Addresses) and the round-10
`$CD5A` status-table hole were reproduced and root-caused offline.

## What the WD model implements (DELIVERY v2, round 10)

`machine.py` mirrors the round-10 DELIVERY v2 CONTRACT, not the older
consumption-coupled pipeline:

- **Disk-paced presentation**: one byte per DD MFM byte-time (32 us = 64 CPU
  cycles at the drive's 2 MHz) from a FIFO fed by the controller model; the
  pace counter starts expired at op start. Presentation never waits for the
  CPU: a byte still unconsumed when the next one presents is **overwritten**
  and latches **LOST DATA** (status bit2).
- **Command start** clears DRQ and the status flags (real-WD1772 semantics);
  **non-Force-Interrupt command writes while busy are ignored** (counted in
  `dbg['busycmd']`).
- **Completion** = controller done AND FIFO empty AND at least one full
  byte-time after the last presentation, so busy outlives the last DRQ by
  >= 1 byte-time (the ROM transfer loop exits on the busy drop, then reads
  status).
- **Status composition**: CRC (bit3) suppresses RNF (bit4) — never both
  (`legacy_crc_rnf = True` restores the pre-v2 pair for regression demos).
- **No unilateral not-ready completions**: a Type-II/III op issued while the
  medium is not ready completes through the controller's own bounded
  RNF-class result (`T_NOTREADY`; time constants are scaled stand-ins, the
  semantics are what is mirrored).
- Type-I (restore/seek/step) keeps the simple timed model: 1.5 ms per step,
  1.5 ms for a command without a step. That is not the step time of the RTL
  (the rate of the command, with the controller's acknowledge as the lower
  bound, which `run_257_proofs.py` models); the proofs of this model do not
  depend on it. `run_proofs.py` and `run_write_proofs.py` take
  `--t1-step-ms=<ms>` and pass at 1.5, 6 and 12 ms per step
  (`run_write_proofs.py` rewrites its fixtures, which at another step time
  come out at another rotational phase: restore them from git).

## How to run the proofs

    python3 run_proofs.py      # any CWD; ROM found automatically; --t1-step-ms=6 for 6 ms per step
    python3 run_boot.py        # plain boot + WD trace dump

`run_proofs.py` must end with `RESULT: ALL PROOFS PASS`. It proves, against
the genuine ROM: the `$C343` register self-test and boot (P-A); a paced
`$C900` directory-track fill with byte-exact cache (P-B); truncated sector +
CRC-only status -> job error 5, cache invalidated, retry heals (P-C — the
`$CD5A` hole fix); corrupted Read Address reply -> software-CRC error 9 +
retry (P-D2); the legacy crc+rnf pair -> silent success with a valid-marked
stale cache (P-E regression demonstrator); the transfer-loop timing margin
(P-T); WD unit semantics (P-U); and the shipped-ROM LOST-DATA defect
(P-D1/P-D3, below). The P-M media-state proofs additionally establish:

- stopped-motor PA1 readiness that lands after the ROM window returns job 03
  without issuing any WD read command;
- a one-index resume for a previously confirmed, unchanged medium succeeds
  with a byte-exact ten-sector fill;
- independently forced PA7 disk change also returns job 03 without WD reads;
- the source-derived F011 rotation (`6250` bytes, sector records every `587`
  bytes, complete sector-11 ID before the truncated tail) exposes Read Address
  sequence `5,10,11` and returns job 02 before any Read Sector; and
- hiding only physical Read Address IDs outside `1..10` changes that sequence
  to `5,10,1` and heals the fill byte-exactly.

`machine.py` keeps the historical simple RA model by default. Set
`ra_layout='f011'` for the rotational source-derived model. The readiness
controls (`ready_after_cycles`, `ready_resume_after_cycles`,
`rotation_confirmed`, `force_ready`, and `force_change`) exist solely to force
one media-state variable at a time around the genuine ROM.

## Timing-exact proofs: `run_write_proofs.py` and `run_257_proofs.py`

`machine.py` charges a flat three cycles per instruction, and its readiness
controls are stand-ins. Two further runners use the cycle-exact 6502 and the
rotational disk of `wd_write_model.py`:

    python3 -I run_write_proofs.py   # issue #244: write-back, format, write protect (doc/dev-fdd/WRITE-SPEC.md)
    python3 -I run_257_proofs.py     # issue #257, about 6 minutes; must end with RESULT: ALL 257 PROOFS PASS

`run_257_proofs.py` models two things the other runners leave out: READY
derived from index pulses (the time of the first pulse after motor-on is a
parameter of the mechanism, the number of pulses READY waits for is the rule
under test), and the delivery of a Read Sector as the RTL does it (`live` = a
real WD1772, `quarantine` = delivery v2 of `fdc1772.v`, `readahead` = delivery
v2 with the controller's read-ahead buffer). Every Type I command takes the
time it takes in the RTL: each step the larger of the rate of the command
(6 ms for the ROM's `$08`, `$18`, `$48` and `$68`) and the acknowledge of the
controller (3.03 ms, 4.03 ms after a reversal; the direction of the last
step is kept across all Type I commands, as the controller keeps it); a
command without a step 1.5 ms. With `paced = False` a step takes the
acknowledge alone: the step timing before WIP-V6-A28, which WIP-V6-A21X1 (the
hardware of comment 17 of issue #257) and WIP-V6-A25 share. It proves:

- **I1 to I6, the READY exam.** The ROM switches the motor on (`$CD63`), lets 80
  ticks of 10 ms pass (`$CE53`; the count is set at `$B095`), and then examines
  PA1 (`$CDAD` calls `$CDBC`, 30 reads). "Not ready" there is job error 3 =
  `74,DRIVE NOT READY`, and the job is not retried. (A Read Address examines
  PA1 again right before its command, `$CD08`.) I1 to I5 run with the steps at
  the acknowledge, the timing of the hardware they describe: the exam comes
  0.8000 s after motor-on for an unchanged disk and 0.8253 s for a changed one
  (step pair `$48`/`$68` of 3.03 and 4.03 ms, as the last step before it went
  inward, and 18 ms settle first, `$CD8A`). With
  READY after two index pulses (the controller up to WIP-V6-A22X3) the job
  fails as soon as the first pulse comes later than 0.62 s after motor-on (I2
  checks 0.62 s and 0.63 s); with READY after one pulse (WIP-V6-A25) the limit
  is the exam itself (I4 checks 0.82 s and 0.83 s). The failing case (I3)
  reproduces the dumps "10-pre" and "FMT-0" of comment 17 (WIP-V6-A21X1)
  exactly: one step pair, no read or write command, the motor on for
  11.030 s, 53 index pulses. I6 is the exam with the RTL of WIP-V6-A28 (READY
  after one pulse, steps at the rate): the step pair takes 12 ms, the exam
  comes 4.94 ms later, at 0.8303 s, and a first pulse at 0.83 s is in time,
  at 0.835 s the job fails.
- **R1 to R6, sequential reads.** The DOS issues the next Read Sector 66 to
  95 us after the BUSY drop (2.25 ms after a Read Address). Ten sectors of a
  side take 215 ms on a real WD1772, 2032 ms with delivery v2 alone (the
  sector is presented for 16.4 ms after its CRC verdict, so the next ID has
  passed and every sector waits a revolution), and 232 ms with the read-ahead
  buffer. A format of 80 cylinders, measured from the second Write Track to
  the fourth (one cylinder, side 1 to side 1; every Write Track starts at an
  index pulse, so the measurement does not depend on the rotational phase at
  which the format begins): 96.0 s on a real WD1772 and with the read-ahead
  of WIP-V6-A28, both stepping at the rate, and 384.0 s with delivery v2
  alone and the steps at the acknowledge, the hardware of comment 17 (it
  measured 403 s). A Write Track after the Seek of one step waits for its
  index pulse, so the step time does not change the time of a format.
- **L1 to L4, the LED lines.** The power LED (PA5) is lit and steady without
  an error and toggles every 100.0 ms while an error is pending; when the
  error is cleared, the DOS leaves it as it is, lit or dark. The activity LED
  (PA6) follows the jobs.

## Transfer-loop timing margin (P-T)

The `$C969` loop is busy-first/DRQ-second:
`LDA $6000 / AND #$03 / LSR / BCC done / BEQ poll / LDA $6003 / STA ($4A),Y`.
Real 6502 numbers at
2 MHz: poll iteration 13 cycles, consume iteration 38 (47 with page cross),
worst-case consumption latency = 13 + 21 = 34 cycles against the 64-cycle
byte pace — a 30-cycle (47 percent) margin, so the ROM can never lose a
byte at exact 32 us pacing (it runs the loop with I set). The emulator
measures max consumption latency 33 of 64 cycles and a 66-cycle busy tail
after the last DRQ.

## Genuine-ROM findings encoded in the proofs

- **`$CD5A` hole**: `$CD3F` maps WD status `(status>>3)&$0B` through the
  table `00 05 02 00 ...`; CRC+RNF together (X=3) = job SUCCESS. Hence the
  v2 rule "CRC suppresses RNF" (CRC-only = job error 5 = DOS 23, retried).
- **LOST-DATA stack defect (shipped ROM)**: the `$CD49 BCS $CD53` branch
  (status bit2) latches error `$09` into `$7D` but skips the `PLP` that
  balances the `PHP` at `$CD42`; its `RTS` pops the flags byte as PCL and
  misreturns — wild execution, not error-9-and-retry (P-D1 unit proof,
  P-D3 end-to-end). Latent on real hardware because of the P-T margin.
  Consequence for the RTL: LOST DATA stays real-chip-faithful but must
  remain practically unreachable; the diag CNT_LOST counter is the way to
  see it ever firing.
- Job-visible **error 9 + retry** exists via the Read Address software CRC
  check at `$DA63` (P-D2), which is also the round-5 signature.

## Harness gotchas (cost hours; do not rediscover)

1. **Boot needs a fixed ~3M-step budget before poking RAM.** The job queue
   is legitimately empty during early boot, so "wait for idle" fires early;
   poking RAM then corrupts the power-on RAM test and the ROM lands in the
   `$AF13` blink loop.
2. **Read Address replies need a TRUE CCITT CRC** over
   `A1 A1 A1 FE C H R N` (the ROM software-verifies them at `$DA63`,
   preset `$B230` after the sync bytes); a fake CRC kills every job with
   error `$09`. `machine.py` computes it (`crc16_ccitt`).

Useful ROM anchors: `$C343` power-up WD register self test (error `$0D`),
`$C104` job pipeline, `$C900` read-job entry, `$C969` sector transfer loop
(early busy-drop exits to `$C9CE`, the whole-fill epilogue), `$CD00` Read
Address (`$CDBC` instant PA1 ready check), `$CD3F`/`$CD5A` status epilogue
and table, `$CE78` seek stage, `$DA63` reply CRC check (error `$09`),
`$B095` spin-up allowance (`$50` dispatcher ticks), `$B0F0-$B135` idle loop.

Working notes, deletable; not part of the shipped feature.
