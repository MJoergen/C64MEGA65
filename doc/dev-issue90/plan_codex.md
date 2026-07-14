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
