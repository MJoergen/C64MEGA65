# Physical 1581 issue #90 — Codex plan and checkpoint

This is the Codex-owned live plan after commit `2e2c852`. It is deliberately
separate from Fable's `PLAN.md`.

## Acceptance requirements

- Preserve the adaptive MFM gap quantiser; do not return to fixed dead-band
  windows unless evidence disproves the adaptive design itself.
- Read stock Commodore 1581 / WD1772-formatted and written disks.
- Read MEGA65 F011-formatted and written disks.
- Reject the round-12 write-splice false-sync chain.
- Preserve the complete round-12 speed, drift, jitter, peak-shift, artifact,
  and splice-step result table.
- Require byte-exact ID and payload data whenever CRC passes.

## Work plan

1. **DONE — reconstruct history and audit round 13.** Read the issue handover,
   chronological plan tail, commits `154ce26`, `79c19d3`, and `2e2c852`, plus
   the quantiser, gap-to-bit sync detector, decoder, flux generator, and A/B
   harness.
2. **DONE — establish F011 ground truth.** Pinned mega65-core `a9158930`
   `sdcardio.vhdl` shows no 00 preamble before auto-formatted sector IDs; twelve
   00 bytes exist only before data fields. This proves why round 13 yields zero
   IDs on the maintainer's F011-formatted disk.
3. **DONE — add source-derived reproductions.** The genuine 318045-02 ROM
   format loop at `$C3F8..$C51D` establishes the stock layout: 32 x 4E, 12 x 00,
   3 x F5/A1, ID, 22 x 4E, 12 x 00, 3 x F5/A1, data. Add permanent stock and
   F011 vectors. The F011 vector must fail on the current round-13 production
   column before any RTL repair.
   F011 vectors fail on the preserved round-13 column and pass on old/round 12.
4. **DONE — replace preamble qualification.** Production requires three A1
   candidates at exact five-gap spacing, separate from adaptive classification
   and independent of preceding gap bytes. Wrong spacing restarts the train.
5. **DONE — focused verification.** Run decoder tests and the multi-column
   A/B harness, requiring current round-13 failure on F011 and repaired
   production success on both formats plus junk rejection.
6. **DONE — full verification.** The final 51-trial five-way matrix, every
   short physical-1581 GHDL bench, and the long closed-loop controller bench
   pass. No SystemVerilog production source changed, so the unrelated iverilog
   junction benches do not need repetition.
7. **DONE — final documentation.** Record exact RTL, test matrix, results,
   remaining hardware boundary, and expected QNICE signatures here and in
   `handover_codex.md`.
8. **DONE — analyze `3803152` hardware failure.** Three dumps prove healthy
   global decoding but deterministic RNF at track 39 sector 1 immediately
   after the index splice. IDs, estimate, and all other sectors remain healthy.
9. **DONE — reproduce the remaining acquisition hole.** A new profile emits
   three coarse-class-valid false A1 candidates at the correct five-gap
   spacing with real short separators, followed by a fake FB tail. Unmodified
   `3803152` production locks and opens a bogus data field.
10. **DONE — qualify the complete raw A1 span.** Require each L-M-L-M candidate
    to total 14 estimated half-cells within a whole-word tolerance of `est/2`.
    Keep adaptive classification and candidate spacing unchanged.
11. **DONE — add targeted diagnostics.** Map v6 (`VERSION=0x067F`) exposes
    16-bit candidate, span-reject, and qualified-train counters at `0x38`–`0x3A`.
12. **DONE — final verification and R3 handoff.** The 52-row six-way matrix,
    canonical decoder, diagnostic bank, overflow guard, and full closed-loop
    controller pass. The resulting `0ab9f92` bitstream was synthesized and its
    physical-media qualification failed at the same track-39 sector-1 boundary.
13. **DONE — interpret map-v6 hardware evidence.** Normalize the new counters
    per revolution. The disk produces ten decoded IDs but 22 qualified A1
    trains per revolution; candidate count is exactly three times train count
    and span rejects are zero. The physical splice therefore contains two
    complete timing-valid trains, disproving aggregate span as the sufficient
    discriminator.
14. **DONE — enforce format-neutral record sequencing.** Accept FB/F8 only
    after a CRC-valid ID and let qualified FE re-anchor the parser out of a
    bogus data parse. Keep adaptive classification and both A1 timing checks.
15. **DONE — add decisive acquisition diagnostics.** Map v7
    (`VERSION=0x07FF`) adds FE, DAM, unarmed-DAM, requested-ID-match and
    missing-DAM counters at `0x3B`–`0x3F`.
16. **DONE — reproduce and verify.** Timing-perfect unsolicited and
    CRC-valid-ID-armed bogus A1x3+FB vectors fail the exact `0ab9f92` control
    and pass production. The latter also proves that a real qualified FE can
    preempt an already-started bogus data parse. The final 54-row seven-way
    matrix, focused decoder, diagnostic bank, overflow guard and full
    closed-loop controller all pass. Remaining work is maintainer R3
    synthesis/timing and physical-media qualification of this record-sequenced
    candidate.
17. **DONE — interpret the map-v7 hardware failure from `47432c8`.** The cold
    directory read now reaches the target ID/DAM pair and ends in data CRC
    error rather than RNF. Healthy estimate/ID counts rule out global
    acquisition loss. `CNT_LOST=686` exposes a second, ROM-fatal WD delivery
    problem.
18. **DONE — re-derive the contract from primary implementations.** The stock
    ROM, WD1772 handbook and pinned F011 formatter agree on a twelve-zero
    lock-up before data marks, while F011 IDs can lack it. ROM-in-the-loop
    proofs show 33-cycle maximum consumption versus a 64-cycle byte pace and
    prove that even one LOST flag can corrupt the genuine ROM return path.
19. **DONE — reject an armed splice DAM without rejecting F011 IDs.** A
    permanent valid-ID -> preamble-less `A1x3+FB` -> legitimate data-field
    vector fails current production and passes the historical round-13
    control. Implement a DAM-only zero-run qualifier, retain the ID arm after
    rejecting the false DAM, and keep FE acquisition preamble-independent.
20. **DONE — make the physical/WD boundary transactional.** Use the
    existing 512-byte async FIFO as quarantine: no WD presentation before the
    controller's CRC/result completion; release clean sectors at WD pace and
    drain failed sectors unseen. Also block presentation during the registered
    data-register read-clear pulse so a short CPU-select window cannot swallow
    DRQ or generate false LOST.
21. **DONE — verify the complete repaired chain.** Run the focused decoder,
    55-row A/B matrix, physical controller/FIFO benches, SystemVerilog WD
    dialogue bench including the short-select collision, ROM proofs, lint/
    compile checks and `git diff --check`.
22. **TODO — R3 qualification.** Synthesize the repaired candidate, cold boot,
    run `LOAD"$",8` and program loads, then inspect map-v7 counters. Success
    requires correct data plus zero LOST, not merely a clean WD completion.

## 2026-07-14 checkpoint 1

- Tree was clean at takeover.
- Fable's round-13 claim that every real field has a 00 preamble is false for
  the pinned F011 auto-formatter.
- The failure is in sync acquisition, not adaptive gap classification.
- A preamble-independent three-A1 structural detector is the leading repair,
  but it is not yet accepted or implemented.
- Genuine 318045-02 ROM disassembly confirms the stock formatter does use
  twelve 00 bytes before both ID and data, so stock and F011 layouts must remain
  separate regression vectors.

## 2026-07-14 checkpoint 2

- Failing regression captured before RTL change: current round 13 rejects the
  F011 ID row while old, round 12, and the tight-acquisition control pass.
- Production repair implemented without changing adaptive classification:
  three missing-clock A1 candidates must be five quantised gaps apart.
- Five permanent columns now distinguish old, round 12, round 13, production,
  and tight acquisition.
- Exact F011 first-sector and subsequent-sector ID layouts both pass production
  and fail the round-13 control as expected.
- F011 plus coherent splice junk passes production with no junk-window lock;
  round 12 opens its bogus field before the record and fails.
- Full 47-trial matrix before the final F011 stress expansion: exit 0,
  `ALL ACCEPTANCE CRITERIA MET`. All speed, drift,
  jitter, peak-shift/combo, artifact, splice-step, stock-layout junk, and
  byte/CRC guards pass. Decoder round-trip and CRC benches pass.
- Remaining verification boundary: other physical-1581 benches, especially
  the long closed-loop controller, then R3 synthesis and hardware qualification.

## 2026-07-14 checkpoint 3

- Added exact F011 far-cylinder rows instead of inferring them from stock
  preamble vectors: first ID (`4 x 00` TIB flush, `1 x 4E`) and later ID
  (`24 x 4E`), each with peak S20 at both +3% and -3% speed.
- Those rows disproved round 13's second acquisition assumption: short-only
  hunt adaptation biases `est` on peak-shifted `4E` gaps. Production now
  restores round 12 all-gap adaptation; the three-A1 qualifier alone rejects
  splice false syncs. The exact r13 column explicitly keeps short-only behavior.
- Focused result: all six F011 nominal/stress rows pass production; all fail
  round 13; the four peak/speed rows also demonstrate old fixed-window and
  tight-acquisition failures. F011 plus junk still passes production with no
  junk lock while round 12 opens the reproduced bogus field.
- The expanded 51-trial full matrix passes with exit 0 and
  `ALL ACCEPTANCE CRITERIA MET`. Short benches are also green:
  CRC, decoder round-trip, inputs, read FIFO, diagnostics, mechanism model, and
  overflow.
- Final-RTL closed-loop controller passes through byte-exact cylinder 0/1
  reads, Read Address, Verify, expected RNF, pending-request delivery, abort
  sequencing, and post-abort recovery.

## 2026-07-14 checkpoint 4

- Maintainer committed the prior repair as `3803152` and tested it on R3.
- Three hardware reproductions all show `RNF_CTX=0x2701`, zero CRC errors,
  roughly ten decoded IDs per revolution, and successful reads of sectors
  2–10 followed by deterministic sector-1 RNF. This supersedes the old
  round-13 zero-ID diagnosis.
- A first hypothesis about a non-short inter-A1 separator was explicitly
  disproved: the bit pipeline emits a byte and clears provisional sync before
  such a candidate can continue the train.
- The accepted hypothesis is complete-word timing. The original coherent
  splice candidate totals 1,580 cycles versus about 1,400 for a real 14-cell
  A1. A permanent correctly-spaced false-train vector reproduced production
  lock and bogus-data-field consumption before the RTL change.
- Production now checks aggregate A1 span within `est/2`. This is independent
  of stock-versus-F011 preamble policy and does not narrow individual gap
  windows.
- The expanded 52-row six-way matrix passes with all prior wins. The new row
  reports `old=PASS, r12=fail, r13=PASS, prod=PASS, tacq=PASS`, while the exact
  `3803152` spacing-only control also fails with the required bogus-data-field
  signature.
- Diagnostic map v6 adds `CNT_A1_CAND`, `CNT_A1_REJECT`, and `CNT_A1_TRAIN` at
  `0x38`–`0x3A`; its unit bench passes.
- Final closed-loop controller passes byte-exact cylinder-0/1 sector reads,
  Read Address, Verify, expected RNF, pending-request tags, abort spacing, and
  post-abort recovery. The overflow bench also passes with CRC-only reporting
  and no silent corruption.

## 2026-07-14 checkpoint 5

- Maintainer tested commit `0ab9f92` on R3. Cold `LOAD"SHADES",8,1` still
  failed with `RNF_CTX=0x2701`; this supersedes the simulated span-rejection
  prediction.
- Map-v6 counters are internally exact: `CNT_A1_CAND=0x235E` equals three times
  `CNT_A1_TRAIN=0x0BCA`, while `CNT_A1_REJECT=0`. Across 138 revolutions the
  disk yields essentially ten IDs and 22 trains per revolution. Two splice
  trains are timing-valid all the way through the span check.
- The next discriminator is record grammar, not narrower flux tolerance.
  Production now requires a CRC-valid ID before accepting a DAM and treats a
  qualified FE as an unconditional parser re-anchor. Both stock WD1772 and
  F011 media obey this ID-before-data structure.
- The seven-column harness retains exact `0ab9f92` as `seqoff`. New
  timing-perfect unsolicited-DAM and armed-bogus-DAM rows hard-prove
  `seqoff=fail` and `production=PASS`; all 52 prior rows are unchanged.
- Final 54-row matrix, focused decoder, map-v7 diagnostic unit test, overflow
  guard and long closed-loop controller all pass. Map v7 (`0x07FF`) adds
  counters at `0x3B`–`0x3F`; the next hardware dump remains `0x7000..0x707F`.

## 2026-07-16 checkpoint 6

- The verified R3 map-v7 bitstream failed a cold `LOAD"$",8`, but no longer by
  RNF: the target ID/DAM was found and the operation ended with data CRC
  residue `0x917B`. This is progress and localizes the remaining media error
  to a false post-ID data field.
- A new source-derived regression places a preamble-less timing-perfect DAM
  after a CRC-valid ID and before the real data field. Unmodified production
  fails exactly there; the superseded whole-field preamble gate passes, proving
  the missing discriminator without reviving its F011-ID bug.
- Stock ROM and F011 source both write twelve zero bytes before data A1 trains.
  The repair therefore records zero-run qualification at the first A1 and uses
  it for DAMs only. A rejected early DAM does not consume the valid-ID arm.
- The same hardware dump contains 686 LOST events. ROM proofs show this cannot
  be dismissed as an error-status detail: the genuine `$CD3F` path skips a
  `PLP` when LOST is set and can return through a corrupt stack. Normal ROM
  servicing has ample margin (33 versus 64 drive-CPU cycles), so LOST points
  to the presenter handshake.
- Architecture decision: retain the proven MiSTer/T65/ROM/IEC upper drive and
  turn physical acquisition into a validated-sector producer. The existing
  512-byte async FIFO becomes a quarantine buffer; only CRC-clean completion
  opens WD-paced delivery. Failed captures are drained without exposure.
- Documentation is now updated before verification. Current edits remain
  uncommitted; the maintainer owns commits.

## 2026-07-16 checkpoint 7

- The 55th A/B row now passes production while retaining the expected
  `r13=PASS` and all other historical controls failing. The complete seven-way
  matrix reports `ALL ACCEPTANCE CRITERIA MET`; all earlier stock/F011 and
  adaptive-margin rows remain unchanged. The false four-byte mark occupies
  part of Gap 2, keeping the real DAM at byte 38 after the ID and therefore
  inside the controller/WD 43-byte acquisition window.
- The WD path now exposes FIFO bytes only after a tag-matched clean result.
  CRC/RNF completions drop `phys_reading` and drain quarantine unseen. This
  uses the existing 512-byte FIFO and adds no memory; image-mode behavior is
  outside the modified physical presentation predicate.
- A registered `cpu_rw_data` pulse is now an explicit presentation exclusion
  window. The permanent one-cycle-select regression previously swallowed the
  new DRQ and left LOST set; repaired RTL defers the byte and presents it later
  with a fresh DRQ and clean status.
- The strengthened WD bench uses the production 512-byte depth and exact
  controller timing where the sixth Read Address FIFO write and done toggle
  share one source edge. It passes clean/CRC-bad quarantine, normal and short
  CPU-read collisions, forced real LOST, stale tags, Force Interrupt,
  multi-sector reissue, Type-I busy visibility and post-error recovery.
- All VHDL physical-1581 benches pass, including the 1.431-second simulated
  closed loop (cylinder 0/1 byte-exact, expected RNF, pending requests,
  abort-done spacing and recovery). The genuine-ROM proof suite and both diff
  checks pass.
- Correctness cost: clean sector data is replayed for about 16.4 ms after its
  physical CRC is known. This is intentional; the ROM has no busy deadline,
  and it prevents speculative magnetic data from crossing into the WD/ROM
  contract. Hardware performance can be measured after correctness is proven.
- Remaining step is R3 synthesis and cold hardware qualification. Keep map v7
  (`0x07FF`); on a clean directory read require `CNT_LOST=0` and
  `LAST_PRESENT=512` for the last successful sector.
