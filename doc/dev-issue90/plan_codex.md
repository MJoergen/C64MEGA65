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

## 2026-07-16 checkpoint 8

- R3 tested the correct `ef272ef` map-v7 bitstream. The first cold
  `LOAD"$",8` failed after five clean Read Address commands. The last two
  replies were cylinder 39 sectors 6 and 11; no Read Sector command followed.
  There was no RNF, CRC, LOST, drain, stale completion, busy-command, or runt
  evidence.
- A genuine 318045-02 ROM-emulator control forced the sector-6 then sector-11
  sequence. It recovered by requesting sectors 1 and 2 and then sectors, so
  sector 11 is a useful correlation but not a proven cause.
- Do not patch away sector 11 yet. First model the actual F011 end-of-track
  layout, index splice, retained Read Address bytes, PA7 disk-change input, and
  PA1 ready timing around the ROM path.

## 2026-07-16 checkpoint 9

- The same bitstream later completed `LOAD"$",8` after power cycle, re-JTAG,
  feature enable, and disk reinsertion. This is the first end-to-end physical
  directory success with the adaptive quantizer and the first hardware proof
  of the full 512-byte CRC quarantine.
- Its dump proves a complete clean track-40 directory fill: five Read Address
  operations, then ten clean Read Sector operations in order
  3,4,5,6,7,8,9,10,1,2. `LAST_PRESENT=512`; LOST, drain, RNF, CRC, DAM miss,
  stale-done, busy-command, and runt are all zero.
- A following `LOAD"SHADES",8,1` failed with error channel
  `74 DRIVE NOT READY 40 0`, but generated no new step, Read Address, or Read
  Sector event. The failure is therefore above physical data acquisition.
- The leading discriminator is synthetic `/READY`: `media_ready` currently
  waits for motor plus two index edges, while the ROM has roughly 0.7 seconds
  before its short PA1 check. Establish whether the motor had spun down between
  commands and reproduce both warm-motor and stopped-motor cases.
- Raw disk change, conditioned change, and head validity were healthy in the
  successful dump. Keep disk-change as a secondary hypothesis rather than the
  primary regression.

## 2026-07-16 checkpoint 10: Fable 5 review and team protocol

- Fable 5 is an advisory teammate whose responses are relayed by the
  maintainer. Codex leads the integrated investigation and decisions at
  present; use Fable for adversarial review and independent source analysis.
- Fable's `f011_reference_notes.md` was read and checked against the pinned
  MEGA65 F011 RTL. Its strongest contributions are the permissive-acquisition /
  CRC-containment architecture, broad fixed gap windows, unconditional sync
  re-anchor, and proof that the formatter can emit an eleventh ID before index
  truncates the following record.
- Retain the documented disagreements: sector 11 is not yet causal; stored CRC
  diagnostics cannot be assigned to the last controller result; the ROM is not
  proven to have accepted its last reply; disk change is not persistently
  stuck; and unqualified gap counters are not exact media-per-revolution data.
- Tell Fable about the newly proven directory read and later no-FDC error 74 in
  the next exchange. Ask it to reassess whether readiness must precede its
  proposed sector-11 normalization and decoder simplifications.

## Next-session execution order

23. **DONE — separate the two hardware outcomes.** The adaptive decoder,
    qualified-record path, CRC quarantine, WD presentation, ROM, and IEC have
    now worked end to end. The later error 74 occurred without a new physical
    job and is a distinct readiness/login problem.
24. **DONE — isolate the PA1/PA7 media-state gates with the smallest hardware
    matrix.** The fresh-disk warm/stopped A/B changed only motor history: warm
    SHADES succeeded with physical traffic; after spin-down it returned error
    74 with zero new physical requests. PA1 is causal. Raw disk change and the
    sticky PA7 path were then tested independently in RTL and the genuine-ROM
    model.
25. **DONE — extend the genuine-ROM emulator.** Add controllable PA1 ready
    latency and PA7 disk-change behavior, then a rotational F011 track model
    containing sectors 1..10, the complete sector-11 ID, truncated following
    record, TIB, and index splice. Force three conditions independently:
    faithful R=11 with healthy PA1/PA7, a PA1 dip on a ten-sector track, and
    stuck PA7 on a ten-sector track. Record the exact ROM branch and WD command
    history for each.
26. **DONE — return Fable's response to the evidence ledger.** Fable accepted
    the CRC-tap, final-byte/ROM-acceptance, and R=11-causality corrections. Its
    PA1/PA7 unifying hypothesis and change-history-qualified ready proposal are
    captured as experiments, not assumed conclusions. Codex remains
    responsible for the merged recommendation and experiment ordering.
27. **DEFERRED — retain true-F011-window/any-sync work as stress-media
    research, not a repaired-build gate.** Fresh hardware proved the present
    production decoder end to end, while the two failures now have independent
    PA1 and R=11 causes. The F011-style broad fixed window would also accept the
    measured 126-cycle artifact that production deliberately rejects, so it is
    not a causally justified safety improvement. The existing seven-way 55-row
    production matrix remains mandatory and passes.
28. **DONE — decide sector-11 normalization from the faithful model.** A
    physical Read Address rule that skips R outside 1..10 may be a valid stock
    1581 compatibility shim. P-M4 and P-M5 change only R=11 visibility:
    `RA=[5,10,11]`, job 02 and zero sector reads becomes `RA=[5,10,1]`, job 00,
    ten sector reads and a byte-exact fill. Normalization is confined to
    physical Read Address; Read Sector and decoder diagnostics are unchanged.
29. **DONE in RTL/simulation; TODO on repaired R3 hardware — make the smallest
    justified change.** Implement the change-qualified one-index resume and
    physical Read Address R=1..10 filter. The complete decoder, controller, WD
    dialogue, genuine-ROM, FIFO, diagnostic and mechanism suites pass. Map v7
    is retained. The stopped-motor and eject/reinsert cases now qualify the
    repaired bitstream.

No RTL or testbench was changed during checkpoints 8 through 10.

## 2026-07-16 checkpoint 11: consolidated Codex/Fable position

- Fable's updated note now incorporates Codex's factual corrections. There is
  no remaining dispute about the free-running CRC tap, the unobservable final
  presented byte, the lack of proof that the ROM processed its last reply, or
  the non-causal status of the R=11 correlation.
- New joint hypothesis: both failures may be synthesized media-state failures
  above the WD layer. Failure 2 is strongly identified as PA1 `/READY` by
  error 74 plus zero new physical jobs. Failure 1 had PA7 `/DSKCHG` asserted
  throughout the captured session, but its exact visible error is still
  unknown. R=11 may be a passenger in that attempt.
- The ROM emulator must independently force the faithful truncated-R=11
  layout, a PA1 dip, and stuck PA7. A one-variable-at-a-time result is required
  before choosing between sector normalization and media-state repair.
- Promising ready design: after a previously confirmed rotation, allow ready
  on the first new index if no disk-change assertion occurred meanwhile. This
  saves one revolution but remains a hypothesis until power-up, CDC, sensor,
  eject/reinsert, and latch-clear behavior are proven.
- `GAP_MIN=126` versus the current approximately 145-cycle lower edge is
  suggestive hardware support for a true-F011-window A/B, not proof of an
  in-record rejection because the diagnostic is not motor/record-qualified.
- Ask the maintainer next: exact outcome of failure 1; motor state and pause
  before SHADES; and whether the disk was inserted before or after power-on in
  failure 1.
- Priority: collect those facts and build the three-condition ROM model; then
  run F011-window/any-sync availability experiments; then make the smallest
  justified RTL change and repeat the complete simulation and R3 suite.

No RTL or testbench was changed during checkpoint 11.

## 2026-07-16 checkpoint 12: hardware matrix paused for mechanism noise

- Maintainer facts are now resolved as far as memory permits: failure 1 was a
  prompt BASIC `FILE NOT FOUND` after loading, with no error-channel read and no
  hang; the later SHADES/error-74 command followed roughly a one-minute pause
  and an audibly stopped motor; original failure-1 insertion timing is unknown.
- The first controlled cold sequence was power-cycle, JTAG-load `ef272ef`, then
  enable `Use internal 1581` with the disk present since power-on. Enabling the
  option caused unfamiliar heavy clicking for about three seconds.
- The pre-command dump proves only two completed steps, 20 motor-qualified index
  edges, zero read operations, clear raw/conditioned/sticky disk-change state,
  and an idle motor at snapshot. Its 22 decoded IDs and very high gap-error total
  are suspicious startup availability evidence, not yet a steady-state rate.
- The subsequent directory attempt was aborted by ejecting the disk when the
  noise recurred. Its error 74 and asserted raw/conditioned/change-latch state
  are consequently expected and cannot discriminate PA1 from PA7. Step count
  remained two and read-operation count remained zero.
- The RTL hard-ties R3 `f_wgate_o` and `f_wdata_o` inactive, so the read-only
  candidate could not magnetically alter the disk. Pause disk-in matrix testing
  until the noise is isolated safely; production RTL remains unchanged.
- The empty-drive activation baseline conclusively maps the noise to ten
  completed head steps: five alternating inward/outward pairs, with no read
  requests or results. This is bounded stepper activity, not a runaway seek or
  a write; raw/conditioned disk change and the sticky latch remain asserted.
- The nominally empty baseline nevertheless reports seven decoded IDs, good
  CRC flags, and stored ID CRC `0x43C7`, so reset/disk-presence provenance must
  be clarified before using its flux counters. Independently confirm in the ROM
  model that persistent PA7 change produces the five in/out pairs.

## 2026-07-16 checkpoint 13: replacement medium restores native baseline

- The old medium also failed in the known-good native MEGA65 core with
  `27, READ ERROR,40,00`, temporarily moving the symptom outside issue 90.
- A different genuine DD disk then formatted successfully in the native core
  and accepted a complete copy of `~/Downloads/C64.D81`. The mechanism and
  native F011 path are therefore operational; use this freshly F011-written
  replacement for all further qualification.
- The read-only issue-90 bitstream still cannot assert WGATE, so do not state
  that it magnetically destroyed the old new-old-stock disk. Media age,
  handling, seating, and ordinary failure remain indistinguishable.
- Resume step 24's controlled PA1/PA7 hardware matrix without ejecting before
  diagnostic capture. In software, proceed with step 25's faithful F011 plus
  independently forced PA1/PA7 ROM model before any production RTL edit.

## 2026-07-16 checkpoint 14: static insertion semantics; no manual RPM gate

- The brief enable-time motor interval ends before manual entry into QNICE can
  sample it. Drop the proposed live-RPM Step 0; a post-stop last-period value is
  not a valid steady-state pre-flight.
- A genuinely clean empty-drive session has ten alternating steps and zero
  index/decoder/read activity, resolving the earlier CRC-bearing empty dump as
  contaminated. Inserting the replacement disk with the motor off changes no
  register: raw/conditioned/sticky disk change stay asserted until a STEP.
- This session is already matrix condition 4. Run the directory command now,
  preserve the state, and dump before ejecting; then execute conditions 1--3
  from fresh JTAG/power cycles.

## 2026-07-16 checkpoint 15: warm-motor control passes cleanly

- Replacement-disk test 1 completed cold `LOAD"$",8` and immediate warm-motor
  `LOAD"SHADES",8,1` successfully.
- Hardware is exact: 199.641-ms rotation, 2,698 IDs across 246 revolutions
  (10.97/rev), 56 clean read operations, 40 target-ID matches, final 512-byte
  presentation, and zero RNF/CRC/LOST/drain/stale/busy/runt/DAM-miss errors.
- Trace arithmetic is exact: 137 = 25 steps + 2 x 56 operations. Disk change
  is clear and the estimate is healthy at 99.625 cycles.
- This is the warm control for PA1. Next run only the stopped-motor variant from
  a fresh session: successful directory, wait for motor stop plus about one
  second, then SHADES and dump without ejecting.

## 2026-07-16 checkpoint 16: stopped-motor A/B proves PA1 root cause

- Test 2 reproduced the exact boundary: directory succeeds, motor stops, then
  SHADES returns `FILE NOT FOUND` / `74 DRIVE NOT READY 40 0` with zero new
  physical request.
- The directory side is wholly clean: 15 operations, ten ID matches, final
  512-byte presentation, zero RNF/CRC/LOST/drain/stale/busy/runt/DAM errors,
  healthy 199.633-ms rotation, and valid settled cylinder-39 state.
- Trace accounting is exact: 134 = 104 steps + 2 x 15 operations. Therefore no
  request was lost below the WD boundary; the stock DOS rejected readiness
  before issuing one.
- Warm test 1 succeeds and stopped test 2 fails with only motor history changed.
  PA1 readiness is now hardware-proven. Defer old-RTL insertion tests 3/4;
  reproduce PA1 in the genuine-ROM model and use them to qualify the fix.

## 2026-07-16 checkpoint 17: genuine-ROM proofs isolate both repairs

- The emulator now models PA1 latency, PA7 disk change, confirmed-medium
  restart, and the pinned F011 rotational layout: 6,250 bytes/revolution with
  587-byte sector spacing, ten complete sectors and the CRC-valid sector-11 ID
  before the truncated tail.
- P-M1 reproduces the stopped-motor failure as job 03 with zero WD read
  commands. P-M2 changes only confirmed-medium one-index readiness and heals a
  ten-sector fill byte-exactly. P-M3 forces PA7 and independently returns job
  03 with zero WD reads.
- P-M4 reproduces the other signature from the real seek context:
  `RA=[5,10,11]`, job 02, zero Read Sector. P-M5 hides only physical Read
  Address IDs outside 1..10 and obtains `RA=[5,10,1]`, job 00, ten Read Sector
  commands and a byte-exact cache.
- This supports two independent changes, not a formatter discriminator: a
  same-medium PA1 resume rule and a stock-1581 Read Address compatibility view.
  Both stock and F011 media continue through the same adaptive decoder.

## 2026-07-16 checkpoint 18: minimum RTL repair and regressions complete

- `rotation_confirmed` is set only after a two-index qualification with disk
  change clear. It survives ordinary motor-off, allowing one fresh index on
  restart, and clears on reset/disable, raw `/DSKCHG`, or index staleness while
  the motor is commanded. Cold/changed media still requires two edges.
- Physical Read Address ignores decoded IDs unless R is 1..10. Read Sector,
  decoder counters and CRC diagnostics still observe the physical layout.
- The new focused media-contract test proves cold two-edge readiness,
  unchanged-medium one-edge restart, stale-index invalidation, raw-change
  invalidation followed by a fresh two-edge qualification, and R11-to-R1 Read
  Address recovery.
- The complete long controller loop passes, including cold ready at 398.2 ms,
  Type-I restore/seek/step, byte-exact cylinder 0/1 reads, Verify, bounded RNF,
  pending requests, abort and disk-change recovery. This directly clears the
  cold-start and Type-I regression gates.
- All supporting tests pass: CRC, canonical decoder, inputs, async FIFO,
  diagnostic map, FIFO-overflow quarantine, mechanism model, the seven-way
  55-row quantizer A/B matrix, the SystemVerilog WD1772 physical dialogue, and
  every genuine-ROM proof.
- Timing arithmetic is supportive, not an absolute mechanical guarantee. The
  measured disk revolution is 199.63--199.64 ms, so the repaired warm restart
  saves exactly one revolution. The genuine-ROM model last samples PA1 at about
  0.810 s and its 0.750-s one-edge stand-in passes, but those readiness delays
  are abstract. The repaired stopped-motor hardware A/B remains the decisive
  timing qualification.
- Do not add a broad F011 fixed quantizer or unconditional any-sync re-anchor
  to this repair. Fresh hardware already proves production decoding, the known
  failures are independently pinned, and the broad upstream window would
  accept the observed 126-cycle artifact. Keep that experiment for a future
  marginal-media stress campaign.
