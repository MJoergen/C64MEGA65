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
- Type-I (restore/seek/step) keeps the simple timed model.

## How to run the proofs

    python3 run_proofs.py      # any CWD; ROM found automatically
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
