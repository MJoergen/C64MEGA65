# Issue #90 — Codex handover

This is the Codex-owned handover for work after commits `2e2c852`, `3803152`
and `0ab9f92`. It is kept
separate from Fable's `HANDOVER.md` and must be updated with each material
finding or implementation step.

## Starting point

- Branch: `mh_implement_90`
- Starting commit: `2e2c852` (`Fix write-splice false-sync regression in the adaptive quantiser (#90)`)
- Working tree at takeover: clean
- Hardware result for `2e2c852`: the physical drive sees healthy flux but
  decodes zero IDs on every tested cylinder (`CNT_IDDEC = 0`); `LOAD"$",8` and
  `LOAD"SHADES",8,1` fail.
- Compatibility requirement: retain the adaptive MFM gap quantiser and read
  both stock Commodore 1581 / WD1772 media and MEGA65 F011-formatted media.

## Confirmed root cause in round 13

The round-13 preamble gate is incompatible with the MEGA65 F011 auto-formatter.
The production decoder accepts the first A1 only after at least 16 consecutive
short-class gaps, assuming every address-mark train has a 00 preamble.

Pinned mega65-core source `a9158930`, `src/vhdl/sdcardio.vhdl`, disproves that
assumption. In `FDCAutoFormatTrack`:

- sector ID: states 13..15 write three missing-clock A1 bytes immediately after
  the previous sector's 4E trailer; there is no 00 preamble;
- sector data: states 46..57 write twelve 00 bytes before states 58..60 write
  the three A1 bytes.

Thus round 13 rejects every F011 ID field by construction while it may still see
data marks. This exactly explains the hardware signature `CNT_IDDEC = 0` with
normal gap timing on every cylinder. The existing simulation only modeled the
stock-style layout with twelve 00 bytes before both ID and data, so it could not
catch this regression.

## Stock 1581 format ground truth

The genuine 318045-02 ROM bundled with the core provides the other required
layout. Its format routine at `$C3F8..$C51D` writes:

`32 x 4E, 12 x 00, 3 x F5, FE C H R N F7, 22 x 4E, 12 x 00, 3 x F5, FB data F7, gap`

Here WD1772 Write Track token `F5` emits a missing-clock A1 and `F7` emits the
CRC. This confirms that stock 1581 media has a 00 preamble before both ID and
data fields, unlike F011 auto-formatted media. The decoder must accept both.

## Implemented repair

Keep adaptive nearest-class gap quantisation. Replace formatter-specific
preamble qualification with format-neutral qualification of the complete
three-A1 channel structure. A legitimate `A1 A1 A1` train produces candidate
A1 patterns at non-overlapping, deterministic spacing; the reproduced splice
junk produces overlapping candidates every two gaps.

Production now treats the first A1 candidate as provisional and requires the
next two candidates to arrive exactly five quantised-gap events apart. A
wrong-spacing candidate restarts the train at that candidate. The field FSM is
armed, `locked_o` is asserted, and in-field quantiser adaptation begins only
after the complete three-A1 train. This matters for splice robustness: a lone
or overlapping junk candidate cannot switch acquisition into the more
permissive in-field adaptation phase.

The adaptive quantiser itself is retained. Its no-dead-band nearest-class
windows and sign-step estimate are unchanged. Production restores round 12's
all-gap adaptation while hunting. The round-13 short-only rule is unsafe on
F011 `4E` gaps under peak shift: it biases the estimate and can lose a later ID
train. Sync safety now comes from exact A1-train spacing, not from suppressing
adaptive input.

Test generics retain both historical failures as reference columns:

- `G_SYNC_GATE=false` plus `G_QUANT_HUNT_ADAPT_ALL=true`: exact round 12;
- `G_SYNC_PREAMBLE_GATE=true` plus `G_QUANT_HUNT_ADAPT_ALL=false`: exact
  round-13 preamble gate and short-only hunt adaptation;
- default generics: production three-A1 train qualifier.

## Permanent regression evidence

The F011 regression was reproduced before the repair: the source-derived row
reported `old=PASS, r12=PASS, r13=fail, tacq=PASS`, matching hardware zero-ID
behavior. The final five-way harness is:

`old fixed | round 12 adaptive | round 13 preamble | production A1 train | tight-acq`

It contains 51 trials and proves all of these simultaneously:

1. exact stock 1581 / WD1772 record layout passes;
2. F011 first ID after the TIB's 4 x 00 flush plus one 4E, and subsequent ID
   after 24 x 4E, both pass at nominal and peak S20 combined with +/-3% speed;
3. the deterministic round-12 splice chain cannot open a bogus field;
4. all round-12 adaptive far-cylinder stress wins remain;
5. CRC-approved data and IDs remain byte-exact.

Final result: `ALL ACCEPTANCE CRITERIA MET`, exit code 0. Production passes the
F011-plus-junk row while round 12 opens the expected bogus data field and round
13 still reproduces the zero-ID failure. Production-over-old family wins are
speed 2, drift 2, jitter 4, and peak/combo 5. The tight-acquisition control
fails five must-pass peak/combo rows, preserving the evidence against solving
this with narrower tolerance.

The canonical decoder round-trip, CRC, inputs, read FIFO, diagnostics,
mechanism, and overflow benches pass. The complete closed-loop controller bench
also passes on final RTL: byte-exact sectors on cylinders 0 and 1, Read Address,
Verify, expected RNF, pending-request sequencing, abort sequencing, and recovery.

## Hardware boundary

Commit `3803152` passed the 51-row matrix above but failed on physical R3 media.
This was not the previous zero-ID regression. Three independent attempts
(`LOAD"SHADES",8,1`, `LOAD"$",8` after soft reset, and
`LOAD"C64ANABALT",8,1`) produced the same localized signature:

- decoded IDs remained abundant: 1,442 / 2,483 / 4,369;
- estimates stayed healthy at `0x636`, `0x640`, `0x636` (99.375–100 cycles);
- CRC-error count remained zero;
- RNF accumulated 10/101, 15/151, and 30/304 read operations;
- every last-RNF context was `0x2701` (track 39, sector 1);
- each trace read sectors 2–10 successfully, then failed sector 1; a following
  Read Address could return sector 1 on the next pass.

This proves a deterministic index/splice-adjacent acquisition failure, not
global formatter incompatibility, DOS stale state, or a marginal cylinder.
The reference image `/Users/mirko/Downloads/C64.D81` has SHA-256
`16668c7eeb63d4307d7bd17d88625e0b7dc28e51289f99c256b17cf2aea0981e`.
Its track-40 reserved region begins at byte `0x61800`; the directory chain
containing both C64ANABALT and SHADES follows there. This corroborates why one
unreadable reserved-track record makes all filename searches fail, but the
sector image cannot reveal physical splice flux.

## Complete-A1 span repair after `3803152`

Review found that exact candidate spacing was necessary but insufficient. The
adaptive classifier accepts each `446/344/446/344` splice candidate because
every gap lies within the broad nearest-class tolerance. Yet those four gaps
sum to 1,580 cycles, whereas raw A1 `0x4489` spans 14 half-cells, approximately
1,400 cycles at the measured estimate. Real peak shift moves internal
transitions in opposite directions and largely cancels over the complete raw
word; the splice errors all lean long.

Production now retains the last four physical gap lengths and accepts a coarse
L-M-L-M candidate only when its complete span is within `est/2` of
`14 * est`. This is an aggregate tolerance over the whole A1, not the refuted
tight per-gap acquisition tolerance. Candidate spacing and the adaptive
no-dead-band field classifier remain unchanged.

A new correctly-spaced splice profile supplies three false L-M-L-M candidates
with genuine short inter-A1 separators and a fake FB tail. Before the span
check, current production locks, opens a bogus data field, and consumes the
following record. After the check, the row is:

`junk spaced A1: old=PASS | r12=fail | r13=PASS | prod=PASS | tacq=PASS`

The expanded 52-row six-way matrix adds an exact `3803152` spacing-only control
and passes completely. That control must reproduce the bogus-data-field failure
on the new spaced-A1 row. All stock and F011
source-derived layouts, F011 peak-S20 at +/-3% speed, round-12 adaptive wins,
CRC/byte-exact guards, and both splice-junk mechanisms remain green.

Final GHDL verification also passes the canonical decoder, diagnostic map,
overflow guard (CRC-only, never silent), and the complete closed-loop
controller: byte-exact cylinders 0/1, Read Address, Verify, expected RNF,
pending request sequencing, abort spacing, and post-abort recovery.

Diagnostic map v6 adds three 16-bit saturating counters without feedback into
the read path: `CNT_A1_CAND` at `0x38`, `CNT_A1_REJECT` at `0x39`, and
`CNT_A1_TRAIN` at `0x3A`. `VERSION` is now `0x067F`. The diagnostic unit bench
checks all three counters and passes.

The hardware qualification requested for `0ab9f92` was:

- cold power-on, enable physical 1581, then `LOAD"$",8`;
- load SHADES and C64ANABALT repeatedly;
- dump through `0x703A`; verify `CNT_IDDEC` and `CNT_A1_TRAIN` grow normally,
  `CNT_A1_REJECT` shows rejected splice candidates, and `RNF_CTX` no longer
  remains `0x2701`;
- verify far cylinders remain reliable and `EST` remains bounded near nominal;
- confirm splice-adjacent sector 1 remains readable.

## Hardware result for `0ab9f92` (map v6)

The maintainer committed the span-qualified repair as `0ab9f92` and tested a
new R3 bitstream. A cold `LOAD"SHADES",8,1` again failed with `RNF_CTX=0x2701`.
The new counters make this result decisive:

- 138 qualified index revolutions (`CNT_IDX_QUAL=0x008A`);
- 1,379 decoded IDs (`CNT_IDDEC=0x0563`), essentially exactly ten per
  revolution;
- 9,054 A1 candidates and 3,018 qualified trains (`0x235E = 3 * 0x0BCA`);
- zero span rejects;
- 94 read operations, nine RNFs, zero CRC-error completions;
- healthy estimate `0x0638` and the same sector-1 trace signature.

After startup phase is accounted for, the train count is 22 per revolution,
not the 20 real trains expected from ten ID plus ten data fields. Every train
contains exactly three accepted candidates, and none violates the full-word
span. Therefore the physical splice supplies two complete timing-valid
A1-like trains per revolution. The aggregate-span hypothesis is disproved for
this disk. The span check remains a sound additional rejection layer for the
simulated long-biased junk profile, but it cannot be the primary discriminator.

No more repetitions of the map-v6 bitstream are useful; they will reproduce
the same already-counted structure.

## Record-sequencing repair after `0ab9f92`

Once splice residue can be timing-indistinguishable from a real A1 train, no
further sync tolerance can reliably separate it without rejecting legitimate
media. Production now enforces the next invariant in the standard IBM/WD
record grammar:

1. a data address mark (`FB`/`F8`) is decoded only after a CRC-valid ID field
   has armed it;
2. accepting or ignoring a DAM consumes that arm;
3. a qualified `A1 A1 A1 FE` always re-anchors the parser, even if splice junk
   had already opened a bogus data parse.

This is not F011-specific. Stock 1581/WD1772 and MEGA65/F011 tracks differ in
their gap and 00-preamble lengths, but both necessarily encode an ID record
before its data record. Adaptive gap classification, estimate tracking,
complete-A1 span qualification and candidate spacing are otherwise unchanged.

The A/B harness now has seven columns. The new `seqoff` column is exact
`0ab9f92` behavior (span qualification on, record sequencing off). A permanent
upper-bound vector emits a timing-perfect `A1x3 + FB` before any ID, followed
by a real stock record. `seqoff` opens the unsolicited 512-byte field and loses
the real record; production ignores it and decodes the real ID/data byte-exact.
A second vector first emits a CRC-valid ID, then a timing-perfect bogus DAM.
This deliberately arms and starts the bogus field even in production; the next
qualified real `A1x3 + FE` must preempt it and recover the genuine record. The
final 54-row matrix reports:

`valid unsolicited DAM: old=fail | r12=fail | r13=fail | prod=PASS | tacq=fail | spanoff=fail | seqoff=fail`

`armed bogus DAM recovery: old=fail | r12=fail | r13=fail | prod=PASS | tacq=fail | spanoff=fail | seqoff=fail`

All prior stock and F011 layouts, F011 peak-S20 +/-3% rows, adaptive
far-cylinder wins, splice profiles, and CRC/byte-exact guards remain green.
The focused decoder bench also injects a timing-perfect unsolicited DAM and
requires exactly one ignored-DAM event before the valid record.

Final verification is green:

- seven-way 54-row A/B matrix: `ALL ACCEPTANCE CRITERIA MET`, exit 0;
- canonical decoder with unsolicited-DAM recovery: pass;
- diagnostic map unit bench: pass;
- complete closed-loop controller: byte-exact cylinders 0/1, Read Address,
  Verify, expected RNF, pending/abort tag sequencing and recovery: pass;
- FIFO overflow guard: CRC-only failure, never silent: pass;
- `git diff --check`: pass.

Diagnostic map v7 is `VERSION=0x07FF`. Five new 16-bit counters occupy the
remaining scalar words before the trace ring:

- `0x3B CNT_MARK_FE`: qualified train followed by FE;
- `0x3C CNT_MARK_DAM`: qualified train followed by FB/F8;
- `0x3D CNT_DAM_UNARMED`: DAM ignored without a valid ID arm (current repair
  also counts a missing data lock-up; see below);
- `0x3E CNT_MATCH_ID`: requested sector ID matched;
- `0x3F CNT_DAM_MISS`: matched ID abandoned because another ID arrived or the
  local DAM timeout expired.

For the next R3 test, dump `0x7000..0x707F` as before. A successful directory
and program load is the primary criterion. If sector 1 still fails, the five
new words distinguish an unsolicited splice DAM from a target-ID/DAM pairing
failure without another instrumentation build.

## Hardware result for `47432c8` (map v7)

The maintainer power-cycled the R3 machine and ran the normal `LOAD"$",8`
test. It failed. The dump was from the intended map-v7 build
(`VERSION=0x07FF`) and materially changes the diagnosis:

- 22 qualified index revolutions, 163 decoded IDs and 12 read operations;
- seven requested-ID matches, one missing-DAM event and no RNF completion;
- the last request reached track 39, sector 7 and paired with an `FE`/`FB`
  record (`C/H/R/N = 39/0/7/2`);
- the operation completed with data CRC error (`LAST_RESULT=0x27`, data CRC
  residue `0x917B`), not record-not-found;
- acquisition timing stayed healthy (`EST=0x0640`, exactly 100 cycles);
- 1,641 A1 candidates produced 327 qualified trains, 164 FE marks and 163 DAM
  marks; five DAMs were ignored and the target pairing mostly worked;
- the WD-facing path recorded 686 cumulative LOST DATA events; the last
  operation's presentation count was 512 bytes.

Thus record sequencing did move the failure boundary: the controller now finds
the requested ID and a following DAM, but it can still accept a timing-perfect
splice DAM after the valid ID and before the genuine data field. That bogus
512-byte parse naturally ends with a bad CRC. Independently, hundreds of LOST
events prove that the WD/drive-CPU delivery seam is not yet safe enough for the
stock ROM.

## First-principles audit after the map-v7 failure

The genuine bundled `318045-02` ROM was converted and disassembled, then run
through `doc/dev-issue90/rom_emu/run_proofs.py`. All proofs pass. The important
ROM facts are:

- the transfer loop at `$C969` polls BUSY first, then DRQ, and reads `$6003`;
- a clean directory-track model fills all ten sectors byte-exact with zero
  LOST events;
- measured worst ROM consumption latency is 33 drive-CPU cycles, versus the
  configured 64-cycle DD byte pace, so a healthy interface has about 47%
  timing margin;
- the genuine error epilogue at `$CD3F` has an asymmetric stack path when LOST
  is set: it skips a `PLP` and returns through a corrupted stack. One false
  LOST indication can therefore derail the drive firmware rather than merely
  produce a normal retry.

The 1986 Western Digital storage handbook gives the relevant WD1772 contract:
after a CRC-valid target ID, the data address mark must occur within 43 DD byte
times; the standard data lock-up is 22 x `4E`, 12 x `00`, 3 x missing-clock
`A1`, then `FB`/`F8`; and LOST is asserted when DRQ is not serviced within one
byte time. The genuine 1581 ROM writes that sequence. Pinned MEGA65 F011 source
uses 23 x `4E`, 12 x `00`, 3 x `A1`, then `FB` for sector data. F011 differs for
ID fields, which can lack the adjacent zero preamble, but both formats have the
same twelve-zero data-field lock-up. Therefore a zero-run qualifier is valid
for DAMs only and remains invalid for general ID acquisition.

The MiSTer-derived upper drive remains the right compatibility anchor: its
T65/ROM/CIA/IEC and image-backed WD path already read D81 images reliably. The
fragile duplication is below that boundary. At the map-v7 failure, the physical
path streamed unvalidated bytes into the asynchronous FIFO while CRC was still
being computed, then independently recreated WD pacing. The stronger boundary
is:

`physical flux -> qualified complete sector + result -> existing WD/ROM path`

The existing 512-byte async FIFO can serve as the sector quarantine without a
new memory block: fill it during physical decoding, release it to WD pacing
only after the controller reports a clean CRC, and drain it without presenting
bytes on an error. This prevents a false field from reaching the ROM at all and
makes physical acquisition a transaction producer rather than a second live
WD implementation. The WD presenter also needs to defer on the registered
data-read clear pulse, not only while `cpu_sel` is visibly open; a one-cycle
select can otherwise close exactly when a paced byte arrives, swallowing its
DRQ and falsely setting LOST.

## Implemented uncommitted repair

A permanent 55th A/B row now emits a CRC-valid target ID, a timing-perfect
`A1x3+FB` splice mark with no zero lock-up, and then the genuine stock/F011-
compatible data preamble and field. The false four-byte mark replaces four
bytes of the normal 22-byte Gap 2, so the genuine DAM remains at its standard
38-byte post-ID position, within the WD1772's 43-byte search window. Before the
repair the exact result is:

`armed splice before data: old=fail | r12=fail | r13=PASS | prod=fail | tacq=fail | spanoff=fail | seqoff=fail`

The production failure is asserted immediately. The working-tree decoder
captures whether the first A1 of a train follows the zero run, requires that
bit only for a DAM, preserves the CRC-valid-ID arm when an early DAM is
rejected, and leaves FE/ID acquisition formatter-neutral. The repaired row is:

`armed splice before data: old=fail | r12=fail | r13=PASS | prod=PASS | tacq=fail | spanoff=fail | seqoff=fail`

The WD front end now treats the existing production-depth 512-byte async FIFO
as a quarantine. `phys_present_now` requires a tag-matched clean controller
completion; an RNF/CRC completion closes `phys_reading`, so the established
residue path drains all speculative bytes without DRQ. Clean data is then
released at the existing 32 us WD pace. Presentation is also excluded while
the registered `cpu_rw_data` clear pulse is active, closing the short-select
DRQ/lost-data race after the combinational bus select disappears.

This intentionally trades latency for a much stronger boundary. A 512-byte
read gains about 16.4 ms of replay time after physical CRC validation, but the
ROM has no busy-loop deadline and the WD remains disk-paced once release starts.
No new RAM is used, and the image-backed path is untouched because every new
gate is inside `phys_mode` presentation logic.

The strengthened SystemVerilog bench first failed on unmodified RTL, exposing
371 speculative bytes before its guard, leaving FIFO residue that poisoned the
next operation, and reproducing LOST on the one-cycle select collision. With
the repair it proves:

- a production-sized 512-byte FIFO holds a complete clean sector until done;
- a full 512-byte CRC-bad capture exposes zero bytes and zero DRQs to the ROM,
  drains completely, reports CRC-only, and the next Read Address is byte-exact;
- no byte is presented before clean completion;
- both a normal 16-cycle read window and a one-cycle select/registered-clear
  collision defer the next byte, preserve its fresh DRQ and leave LOST clear;
- the controller's same-edge sixth Read Address byte plus done toggle cannot
  outrun the FIFO pointer synchronization;
- all prior register, Type-I minimum-busy, stalled-CPU real-LOST, Force
  Interrupt, stale-done, multi-sector and status-belt checks remain green.

Final verification on the current working tree:

- final seven-way 55-row A/B matrix: `ALL ACCEPTANCE CRITERIA MET`, exit 0;
- focused decoder: two ignored false DAMs, real payload byte-exact/CRC OK;
- CRC, conditioned inputs, async FIFO and map-v7 diagnostics: pass;
- overflow bench: CRC-only failure, never silent: pass;
- mechanism decoder loop: cylinders 0 and 1 byte-exact: pass;
- long controller loop: cylinder 0/1 reads, Read Address, Verify, expected RNF,
  pending tags, abort spacing and recovery: pass;
- CRC-gated SystemVerilog WD dialogue bench: pass;
- genuine 318045-02 ROM proof suite: `RESULT: ALL PROOFS PASS`;
- root and submodule `git diff --check`: pass.

Diagnostic addresses and capabilities are unchanged, so the map remains
`VERSION=0x07FF`. The meaning of `CNT_DAM_UNARMED` is deliberately broadened:
it counts a DAM ignored either because no CRC-valid ID armed it or because its
A1 train lacked the data zero-lock-up. For the next R3 build the decisive
success signature is a working cold `LOAD"$",8` with `CNT_LOST=0`; clean sector
ops should finish with `LAST_PRESENT=512`, while rejected/CRC-bad speculative
captures may increase `CNT_DAM_UNARMED`/`CNT_DRAIN` but must present zero bytes.

## Source discipline

- Do not modify Fable's `HANDOVER.md` or `PLAN.md`.
- Codex progress belongs in this file and `plan_codex.md`.
- The maintainer commits; Codex does not commit.

## 2026-07-16 R3 hardware qualification of `ef272ef`

Commit `ef272ef` is the map-v7 build containing DAM-only zero-run
qualification, full-sector CRC quarantine, and the registered CPU-read
presentation exclusion. The first cold R3 `LOAD"$",8` failed, but its trace
did not resemble the earlier false-DAM or LOST failures:

- all five Read Address operations completed without RNF, CRC, LOST, drain,
  stale-done, busy-command, or runt errors;
- the final two Read Address results were cylinder 39, sector 6 and then
  cylinder 39, sector 11;
- no Read Sector command followed the sector-11 reply; and
- the 58 trace entries exactly accounted for 48 step events plus five request
  and five result events.

This localized that attempt above the magnetic decoder: the ROM stopped at a
Read Address transition rather than losing or corrupting a sector. A genuine
318045-02 ROM-emulator experiment forced the same sector-6 then sector-11
sequence. The ROM did not stop; it requested sectors 1 and 2 and then began
sector reads. Consequently, sector 11 is correlated with the hardware failure
but is not yet a demonstrated root cause. A faithful rotational F011 track
model is required before installing an out-of-range-sector workaround.

After a power cycle, re-JTAG, feature re-enable, and disk reinsertion, the same
build successfully completed `LOAD"$",8`. This is the first unequivocal R3
proof since introducing the adaptive quantizer that the complete chain works:

`physical disk -> adaptive MFM decoder -> qualified records -> CRC quarantine
-> WD presentation -> stock 1581 ROM -> IEC -> C64 directory load`

The next `LOAD"SHADES",8,1` returned `FILE NOT FOUND`, with error channel
`74 DRIVE NOT READY 40 0`. Its map-v7 dump is especially important:

- 80 step events reached a valid, settled cylinder-39 estimate;
- all 15 controller operations were clean: five Read Address operations and
  ten Read Sector operations;
- the last ten sector reads were 3, 4, 5, 6, 7, 8, 9, 10, 1, and 2, i.e. a
  complete successful directory-track cache fill;
- `LAST_PRESENT=512`, and LOST, drain, stale-done, busy-command, runt, RNF,
  CRC, and DAM-miss counters were all zero;
- all 110 trace entries are explained exactly by 80 steps plus 15 request and
  15 result entries; there was no physical FDC request after the directory
  fill; and
- raw disk change was deasserted, the conditioned change latch was clear, and
  the head estimate was valid. The live ready bit was low only after the motor
  had stopped.

Therefore the successful directory load and the subsequent error are
consistent, not contradictory. The second command failed before submitting a
physical job. The leading hypothesis is the synthetic `/READY` contract, not
the decoder: current `media_ready` requires motor-on plus at least two index
edges, while the stock ROM allows only roughly 0.7 seconds of spin-up before a
short CIA PA1 readiness sample. Motor ramp plus two revolutions can
intermittently miss that window. Whether the motor had stopped between the two
commands is the most valuable next observation. The disk-change path remains a
secondary possibility, but the successful dump refutes it as a persistent
regression.

The successful trace materially strengthens the present architecture decision.
Keep the MiSTer/T65/stock-ROM/IEC upper drive and the full-sector quarantine.
The end-to-end sector path is now proven on hardware. Diagnose readiness first;
do not replace the WD presenter or broaden record acceptance merely because
the later high-level command returned error 74.

## Fable 5 advisory collaboration

The maintainer is also using Fable 5 as an assistant and will relay its replies
between sessions. At least for the present phase, Codex leads the investigation:
Codex owns the integrated evidence model, execution order, and final technical
recommendation; Fable is an adversarial reviewer and independent source-code
analyst. Treat its work as team input, neither as an authority to follow
blindly nor as a competing plan. Preserve disagreements until an experiment
resolves them.

Fable's current analysis is in the maintainer-owned, currently untracked
`doc/dev-issue90/f011_reference_notes.md`. Do not edit that file. Its most
valuable source-derived findings, which Codex independently checked against
the pinned MEGA65 F011 RTL, are:

- the MEGA65 F011 succeeds with a permissive fixed-window quantizer, a
  four-gap A1 detector, unconditional parser re-anchoring on any sync, and
  CRC/matching-ID gating that prevents acquired junk from reaching software;
- the F011 acceptance window is substantially broader than our present
  adaptive 1.5x-to-4.5x window and has no equivalent adaptive deadbands;
- its formatter has no explicit ten-sector stop: it loops until index, so a
  complete sector-11 ID followed by a truncated record at the index splice is
  plausible and explains roughly 10.9 IDs per revolution; and
- the architectural principle is sound: make acquisition tolerant, re-anchor
  quickly, and make false acquisitions harmless through semantic checks, CRC,
  and retry. Our ID arm plus full-sector quarantine is converging on that
  principle.

Codex's current qualifications to Fable's conclusions must be retained for its
next reply:

1. Fable called sector 11 the confirmed or prime root cause too strongly. It
   is a real correlation, but the genuine-ROM forced-sequence experiment
   recovered from sector 11. Reproduce the actual F011 rotational layout and
   ready inputs before deciding.
2. The diagnostic stored CRC value `0x06AA` must not be paired with the final
   sector-11 result. That diagnostic tap updates continuously: `0x06AA` is the
   cylinder-39/head-0/sector-7/size-2 ID CRC, whereas the sector-11 ID CRC is
   `0x43C7`. The later successful dump similarly retains `0x53F9` (sector 4)
   while the last controller CHRN is sector 2. The controller's clean result
   proves a valid sector-11 ID without that tap.
3. Absence of a software CRC storm does not prove the ROM accepted and
   processed the final reply; it may have stopped on that reply.
4. Disk-change was not stuck in the successful session, so it is not presently
   a demonstrated systematic regression.
5. Decoder diagnostics such as gap-error totals continue outside useful motor
   intervals and must not be treated as exact per-revolution media statistics.
6. The new successful directory read proves the production sector architecture
   before any proposed F011-style simplification. The immediate problem is the
   readiness/login boundary, while a true-F011-window and any-sync-reanchor A/B
   remain promising controlled experiments.

That response was subsequently delivered to Fable; its reply is captured in
the next section. A physical-Read-Address compatibility rule that hides sectors
outside 1..10 remains a possible normalization for stock 1581 media, but only
after the faithful ROM/F011 experiment. Read Sector already naturally selects
requested sectors 1..10, so do not generalize such a rule to every decoder
path.

No RTL or testbench was changed during this analysis round.

## Fable 5 response: corrections resolved, media-state hypothesis added

Fable re-read Codex's analysis and updated
`doc/dev-issue90/f011_reference_notes.md` to remove the inherited errors. It
accepts the following as resolved factual corrections:

- `ID_STORED_CRC` is free-running and cannot be paired with the final
  operation's CHRN result;
- `CNT_LOST=0` proves timely consumption of each presented byte that had a
  successor, but cannot show whether the final byte of the final reply was
  consumed or acted upon;
- the dump does not prove that the ROM accepted its final Read Address reply;
  and
- sector 11 is correlated with the first failure, not established as its
  cause. The forced sector-6/sector-11 genuine-ROM control remains decisive
  against treating that correlation as a verdict.

Fable agrees that the second failure is best explained by the synthetic PA1
`/READY` gate and accepts the current plan ordering. It adds a useful unifying
hypothesis: both failed attempts may have died at stock-DOS media-validation
gates while the WD/controller was silent. In the second failure, error 74 and
the absence of new physical operations identify PA1. In the first failure,
PA7 `/DSKCHG` was asserted for the entire captured session; therefore the
critical transition might have been a PA7 validation gate, with the observed
sector-11 reply merely a passenger. This is plausible, not yet proven, because
the exact user-visible result of the first failure is not recorded.

The genuine-ROM experiment should now adjudicate three conditions
independently rather than being designed only to reproduce R=11:

1. a rotationally faithful F011 track containing sectors 1..10, the complete
   sector-11 ID, the truncated following record, TIB, and index splice, with
   PA1 and PA7 healthy;
2. a normal ten-sector control with a PA1 ready dip at the DOS validation
   point; and
3. a normal ten-sector control with PA7 disk change stuck asserted.

Run combinations where necessary, but keep one variable changed at a time for
the causal verdicts. This one harness can show the exact ROM branch and WD
silence produced by each condition. Only after that result should a sector-11
normalization or media-state RTL change enter production.

Fable also proposes treating readiness and change history as one design
problem. If no `/DSKCHG` assertion has occurred since a confirmed rotation,
the same medium should still be present, potentially allowing `media_ready` to
reassert after the first index edge following motor-on instead of waiting for
two. This could recover one full revolution of the ROM's spin-up allowance
without deliberately weakening eject detection. It is a promising invariant,
not an approved fix: verify power-up state, CDC/sampling, raw-pin polarity,
remove/reinsert behavior, and latch-clear semantics first.

The successful dump's `GAP_MIN=126` is also directionally useful: at
`EST=96.625`, our lower adaptive acceptance edge is about 145 cycles, whereas
the F011-style fixed window reaches roughly 100. It proves that such a short
gap occurred in the observed session, but the present diagnostic is not
motor/record-qualified. Do not claim that a real record mark was rejected from
this value alone. It strengthens the case for the true-F011-window A/B and for
a motor-qualified raw-gap trace around the splice; it does not move that work
ahead of PA1/PA7 diagnosis.

Three maintainer-only facts must be requested at the start of the next session:

1. What was the exact visible outcome of the first failed `LOAD"$",8`: error
   74 `DRIVE NOT READY`, `FILE NOT FOUND`, a hang, or something else?
2. Before the `LOAD"SHADES",8,1` failure, had the motor audibly stopped, and
   approximately how long was the pause after the successful directory load?
3. In the first failed session, was the disk already inserted at power-on, or
   inserted afterward?

These answers are high-value discriminators but do not block building the
three-condition ROM-emulator harness. The consolidated priority remains:
media-state evidence and faithful ROM modeling first, then the true-F011
availability A/B, then the smallest evidence-backed RTL change.

Codex remains technical lead for the present collaboration. Fable's role is
independent review and source-derived challenge; the maintainer relays results
between them. The next Codex instance should re-read the now-corrected Fable
note rather than relying only on the older summary above.

No RTL or testbench was changed in this final handoff update.

## 2026-07-16 hardware matrix start: unexpected mechanism noise

The maintainer clarified the outstanding observations before beginning the
controlled matrix:

- the first failed `LOAD"$",8` ended promptly with the BASIC `FILE NOT FOUND`
  error after visible loading activity; it did not hang, and the drive error
  channel was not read in that attempt;
- the later `LOAD"SHADES",8,1` was issued roughly one minute after the
  successful directory load, after the motor had audibly stopped; and
- the insertion timing of the original first failed session is no longer
  known.

For the first new cold condition, "cold" meant power-cycle the MEGA65, JTAG-load
`ef272ef`, then enable `Use internal 1581`; the disk had remained inserted since
power-on. Enabling the option caused roughly three seconds of unfamiliar heavy
clicking/mechanical noise, so the maintainer took a map-v7 dump before issuing a
C64 drive command. Its important facts are:

- physical mode was active but motor-off at the snapshot (`LIVE_OUT=0x0079`,
  `CTRL_STATE=0x0042`); raw/conditioned disk change and the sticky change latch
  were all clear;
- exactly two completed step events occurred, and the entire trace consists of
  `0x1001/0x0000` followed by `0x1100/0x0000` (one inward and one outward step);
- the mechanism produced 20 qualified index edges but no WD read operation;
- only 22 IDs decoded and `CNT_GAPERR=0x0001B032` during that startup interval,
  an unusually poor availability sample that must not yet be treated as a
  steady-state per-revolution statistic; and
- the physical path remains structurally read-only: the R3 top level hard-ties
  both `f_wgate_o` and `f_wdata_o` inactive. No magnetic write or erase was
  possible.

The maintainer then tried `LOAD"$",8`, heard the noise again, and ejected the
disk for safety before completion. The command promptly ended with BASIC `FILE
NOT FOUND`; the error channel was `74 DRIVE NOT READY 0 0`. The post-ejection
dump has raw and conditioned disk change asserted and the sticky latch set
(`LIVE_IN=0x022F`, `CTRL_STATE=0x0052`). It still has exactly two steps and zero
read operations. Therefore the second dump cannot adjudicate the intended PA1
or PA7 condition: ejection itself makes not-ready unavoidable. It does prove
that the noise during this command was not accompanied by additional completed
head-step requests.

Disk-in testing was paused. The next observation should separate mechanism
startup noise from disk/spindle noise without risking the problem medium; do
not interpret this aborted attempt as a pass or failure of the planned cold
matrix. No RTL or testbench was changed.

The requested empty-drive activation baseline reproduces the clicking and
identifies it unambiguously as head stepping. `CNT_STEP=10`, `TRC_CNT=10`, and
the complete trace is five repetitions of:

`0x1001/0x0000` (one inward step to estimate 1), then
`0x1100/0x0000` (one outward step to estimate 0).

There are no read request/result entries and `CNT_READOP=0`. At the snapshot
the motor is off, physical mode remains enabled, raw and conditioned disk
change are asserted, and the sticky change latch is set (`LIVE_IN=0x022F`,
`CTRL_STATE=0x0052`). This is a bounded sequence of ordinary 4 us STEP pulses,
not a runaway restore and not a write. The leading explanation is stock-ROM
media-change handling repeatedly using an in/out step pair while the empty
mechanism continues to assert `/DSKCHG`; confirm that dialogue in the ROM model.

One datum requires provenance clarification before treating this as a clean
empty-drive reset baseline: the same dump contains 24 qualified index edges,
seven decoded IDs, CRC-good ID/data flags, and `ID_STORED_CRC=0x43C7` (the known
F011 cylinder-39 sector-11 ID CRC). Those values cannot have been newly decoded
from an empty mechanism. Establish whether the disk was absent for the entire
FPGA configuration and whether a full reconfiguration/reset actually preceded
the dump; otherwise regard the magnetic counters as retained from an earlier
disk-present interval. The ten-entry step trace itself is internally complete
and sufficient to identify the clicking.

## Hardware control recovered with replacement DD medium

The previously known-good native MEGA65/C65 core subsequently reproduced the
clicking on the old medium and `DIR` returned `27, READ ERROR,40,00`. This moved
that immediate symptom outside the issue-90 RTL boundary. The maintainer then
inserted a different genuine DD disk, formatted it successfully with the native
MEGA65, and copied the complete reference `~/Downloads/C64.D81` image to it.
Thus the mechanism, native F011 path, and write/read path are operational; the
old approximately 30-year-old new-old-stock medium (or its seating/clamp) was
the failed variable.

Do not claim that issue-90 reads magnetically trashed the old disk: the tested
bitstream physically cannot assert WGATE. Repeated handling or ordinary media
age may have exposed a mechanical or magnetic weakness, but causation is not
available from the evidence. The replacement is a particularly useful test
medium because it is genuine DD media freshly formatted and written by the
native F011 from the same reference image.

Resume the PA1/PA7 hardware matrix using only this replacement disk. Preserve
each failed state until the map-v7 dump is captured; do not eject before the
dump. In parallel, the next software work remains the genuine-ROM
three-condition model (faithful F011 end-of-track, PA1 dip, and PA7 assertion),
followed by true-F011-window/any-sync A/B experiments. No production RTL change
is justified before those results.

## Manual RPM pre-flight rejected; clean insertion baseline captured

The proposed manual Step 0 (enter QNICE and sample index period while the brief
automatic motor interval is still active) is not operationally achievable: the
motor stops before the maintainer can close the OSM, enter the QNICE monitor,
select the diagnostic device, and read the words. A period sampled after motor
stop is not a trustworthy steady-state RPM gate. Remove this as a required
manual test rather than turning an inaccessible timing point into ceremony.

A fresh replacement-disk session nevertheless produced a decisive static
baseline. The drive was empty through power-on, JTAG load, feature enable and
the bounded startup wiggle. The first full dump is genuinely clean: ten
alternating step events and zero index, ID, CRC, gap, A1, or read-operation
activity. The replacement disk was then inserted while the motor was off; a
second dump was bit-for-bit identical. In particular, raw and conditioned
`/DSKCHG` and the sticky latch remain asserted (`LIVE_IN=0x022F`,
`CTRL_STATE=0x0052`) after insertion alone. This confirms the mechanism
contract: insertion does not clear disk change; a subsequent physical STEP
must clear it. It also resolves the earlier nominally empty dump with retained
sector-11/CRC evidence as a contaminated, non-clean-reset baseline.

This live session already instantiates hardware-matrix condition 4 (enable
empty, let the wiggle finish, then insert). The next action is to leave the disk
inserted, exit QNICE, run `LOAD"$",8`, and dump before any eject or menu toggle.

## Replacement-disk matrix test 1: cold directory plus warm SHADES passes

The first complete replacement-disk trial followed the requested condition 1:
cold directory access followed immediately by `LOAD"SHADES",8,1` while the
motor was still warm. Both succeeded. Map v7 is internally exact:

- steady index period is `0x00985053` = 199.641 ms and pulse width is
  `0x0001CA82` = 2.348 ms;
- 246 qualified revolutions produced 2,698 decoded IDs = 10.97 IDs/revolution,
  the expected F011 ten sectors plus truncated sector-11 structure;
- 56 read operations completed with zero RNF, CRC error, cancel, LOST, drain,
  stale completion, busy-command, runt, or DAM-miss events;
- 40 requested IDs matched and `LAST_PRESENT=512`; the final result is clean;
- `TRC_CNT=137` equals exactly 25 completed steps plus two events for each of
  the 56 read operations, so no trace event is unexplained;
- raw/conditioned/sticky disk change are clear, FIFO occupancy is zero, and the
  final estimate is healthy at `0x063A` = 99.625 cycles; and
- all 2,698 FE marks and 2,698 DAM marks were accepted, with no span reject or
  unarmed-DAM event. `GAP_MIN=126` repeats on a clean successful medium/session,
  strengthening its value as an availability A/B datum without proving that a
  record mark used that minimum.

This re-proves the complete physical decoder, CRC quarantine, WD/ROM/IEC path
on a fresh F011-formatted medium and establishes the warm-motor control. The
next hardware trial must change only one variable: after a fresh successful
directory load, wait for the motor to stop plus approximately one second before
issuing SHADES.

## Replacement-disk matrix test 2: stopped-motor SHADES proves PA1 failure

The controlled stopped-motor trial is the causal complement to test 1.
`LOAD"$",8` succeeded. After the motor audibly stopped and one additional
second elapsed, `LOAD"SHADES",8,1` displayed `FILE NOT FOUND`; the error channel
was `74 DRIVE NOT READY 40 0`. The dump proves the failure occurred before the
WD/controller boundary:

- exactly 15 read operations completed, comprising the successful directory
  login/fill; ten target IDs matched and `LAST_PRESENT=512`;
- every completed operation is clean: zero RNF, CRC, LOST, drain, stale,
  busy-command, runt, unarmed-DAM, or DAM-miss events;
- `TRC_CNT=134` equals exactly 104 steps plus two events for each of 15
  operations; there is no request/result pair for SHADES;
- the final directory result is clean (`C/R=39/4`, size code 2), the head is
  valid and settled at cylinder 39, disk change is clear, and FIFO level is
  zero;
- rotation during the directory was healthy: `0x00984EC5` = 199.633 ms with a
  2.477-ms index width; 1,295 IDs over 117 revolutions and estimate `0x063A`
  show normal media/decode behavior; and
- at the post-failure snapshot motor and synthesized ready are both low, as
  expected after the DOS has already rejected the command.

Together with test 1, this changes one variable only:

`warm motor -> SHADES succeeds with physical traffic`

`stopped motor -> error 74 with zero new physical traffic`

The synthetic PA1 `/READY` spin-up contract is therefore hardware-proven as
the immediate bug. Further tests 3/4 on the unchanged bitstream cannot improve
the causal verdict and are deferred to qualification of the repaired build.
Proceed with the genuine-ROM PA1 model, retain PA7/F011 one-variable controls,
then implement the smallest safe readiness change.

## Genuine-ROM closure: PA1 and F011 R=11 are independent

The emulator now has four explicit media controls (`ready_after_cycles`,
`ready_resume_after_cycles`, `rotation_confirmed`, and forced PA1/PA7 state)
plus a source-derived rotational F011 layout. The layout is 6,250 DD bytes per
revolution; ID ends are spaced 587 bytes apart, so all ten stock sectors and a
CRC-valid R=11 ID fit before index truncates the following data record.

Five permanent P-M proofs run against the genuine 318045-02 ROM:

1. Late PA1 after motor restart returns job 03 with zero WD read commands.
2. The same state with confirmed-medium one-index readiness returns job 00,
   issues ten Read Sector commands and fills the cache byte-exactly.
3. Independently forced PA7 returns job 03 with zero WD reads and the expected
   two-step disk-change wiggle.
4. Faithful F011 rotation from the original seek context returns Read Address
   sectors `[5,10,11]`, then job 02 with zero Read Sector commands.
5. Hiding only out-of-range physical Read Address IDs changes the sequence to
   `[5,10,1]` and heals the job byte-exactly.

This is the controlled one-variable evidence that was previously missing.
Failure 2 is PA1 on hardware and in the ROM. The R=11 sequence is causal in the
faithful ROM/F011 model. Neither result calls for detecting a disk format:
stock and F011 media stay on the same physical decoder path.

## Implemented minimum repair

`CORE/vhdl/physical_1581/physical_1581_controller.vhd` now contains two small,
independent compatibility rules:

- `rotation_confirmed` remembers that the unchanged medium previously passed
  a two-index qualification. Ordinary motor-off preserves it; the next start
  asserts ready after one fresh index. Reset/disable, raw `/DSKCHG`, or index
  staleness while motor is commanded clears it. Cold, changed and newly enabled
  media still requires two indexes. Type-I handling is untouched.
- Physical `RDOP_READ_ADDRESS` accepts only R=1..10. The decoder still sees and
  counts every ID, including F011 R=11; Read Sector remains unchanged and
  naturally matches the requested 1..10 sector.

The new
`CORE/vhdl/test/tb_physical_1581_controller/tb_physical_1581_media_contract.vhd`
proves cold two-edge readiness, confirmed-medium one-edge restart, stale-index
invalidation, raw disk-change invalidation plus fresh two-edge qualification,
and a CRC-valid R11 followed by R1 returning R1 cleanly.

## Verification and remaining hardware gate

Every software regression passes:

- focused media-contract test;
- complete closed-loop controller/mechanism loop, including cold ready at
  398.2 ms, Type-I, byte-exact cylinder 0/1 reads, Read Address, Verify, RNF,
  pending requests, abort and recovery;
- CRC, canonical MFM decoder, conditioned inputs, async FIFO, diagnostic map,
  FIFO-overflow quarantine and standalone mechanism tests;
- seven-way 55-row quantizer A/B matrix (`ALL ACCEPTANCE CRITERIA MET`);
- SystemVerilog `tb_fdc1772_physical` delivery dialogue; and
- genuine-ROM `run_proofs.py` (`RESULT: ALL PROOFS PASS`).

Fable's three readiness cautions are valid release criteria and are covered as
far as simulation can cover them. Eject/change and index staleness both clear
the history; cold qualification remains two-index; Type-I is unchanged and
passes the long loop. Timing remains the one necessarily physical gate. The
fresh disk measures 199.63--199.64 ms/revolution, so one-index resume saves one
full revolution. The ROM model last samples PA1 at about 0.810 s and a 0.750-s
one-index stand-in succeeds, but the modeled delays are intentionally abstract
and cannot guarantee real spindle acceleration.

Next repaired-R3 qualification, using the fresh DD disk and no intermediate
eject before each dump:

1. Fresh power/JTAG session, enable internal 1581, run `LOAD"$",8`; it must
   pass. Immediately run `LOAD"SHADES",8,1`; it must pass. This rechecks the
   cold and warm controls.
2. In the same session let the motor stop, wait one additional second, then run
   `LOAD"SHADES",8,1`; it must now pass. Dump map v7 immediately. This is the
   direct repaired PA1 A/B.
3. Eject and reinsert, then run `LOAD"$",8`; it must pass and must not reuse
   stale one-index confidence. Dump map v7 before another eject. This qualifies
   `/DSKCHG` invalidation and the restored cold two-index path.
4. Repeat directory plus SHADES once after a fresh JTAG/power session with the
   disk already inserted. This covers the original cold insertion class and
   gives the R=11 normalization multiple natural rotational opportunities.

Keep diagnostic map v7. No new counters are needed. The earlier broad-F011
fixed-window / unconditional-any-sync idea is deferred to marginal-media
research: fresh hardware already proves the production decoder, both current
failures have independent causes, and the broad F011 window would accept the
measured 126-cycle artifact that production deliberately rejects.

## Qualification of Fable's secondary observations

Fable's causal PA1 verdict, R=11 model interpretation and three repair gates
are adopted. Three secondary claims need narrower wording in future summaries:

- The old working medium's roughly 420 gap errors/revolution versus 17.6 in
  fresh test 2 (22.9 in fresh test 1) is strong evidence that the old disk was
  a marginal stress medium. The counters cannot distinguish weak magnetization
  from hub/shell-induced timing instability, so do not call the failure
  specifically magnetic or specifically mechanical.
- Exact `CNT_A1_CAND = 3 * CNT_A1_TRAIN` holds for fresh test 2
  (`7776 = 3 * 2592`). Fresh test 1 has five additional candidates
  (`16565` versus `3 * 5520 = 16560`). Both sessions have zero span rejects
  and clean records, so fresh media is dramatically cleaner; "zero junk on
  every fresh session" is nevertheless too broad.
- The head estimate is anchored and valid in the stopped-motor test-2 flow.
  That resolves the cosmetic concern for this normal restore/seek path, not for
  every possible enable/insertion history.

## Repaired R3 hardware: stopped-motor PA1 boundary passes

The rebuilt candidate (branch `mh_implement_90`, repository HEAD `b13d99e` at
report time) passed the exact sequence that failed before the repair. The disk
was out during power-up, JTAG and `Use internal 1581` activation. After startup
activity ended, the fresh F011-written disk was inserted. All three commands
succeeded:

1. cold `LOAD"$",8`;
2. immediate warm `LOAD"SHADES",8,1`; and
3. the same SHADES load after the motor audibly stopped plus a one-second wait.

The post-test map-v7 dump is internally exact:

- index period `0x00985187` = 199.647 ms and width `0x00024F0E` = 3.026 ms;
- 388 raw and motor-qualified revolutions, 4,251 IDs = 10.96/revolution;
- 81 completed steps and 103 completed read operations;
- `TRC_CNT=287 = 81 + 2 * 103`, so every event is accounted for;
- 80 matching IDs, final clean C/R=62/6 and `LAST_PRESENT=512`;
- zero RNF, CRC error, cancel, LOST, drain, stale completion, ignored busy
  command, runt, span reject or DAM miss;
- `EST=0x063E` = 99.875 cycles and disk-change raw/conditioned/latch clear;
- `CNT_A1_CAND=26236`, exactly one more than `3 * CNT_A1_TRAIN=26235`, and one
  unarmed DAM was safely ignored; and
- the retained trace contains successful cylinder-61/62 reads plus normal
  Read Address replies R=3,5,6. No retained result is R=11, consistent with the
  RTL rule that cannot present it to the ROM.

This first pass proved that the same-medium first-index shortcut can land
inside the real 1581-ROM window and preserve clean delivery. It did not yet
prove that every spindle-start phase reaches the first index before the
controller's separate running-media staleness deadline. It also gave repeated
natural opportunities to the R=11 normalizer, although a passing trace cannot
reveal an R=11 that was correctly skipped internally.

The planned eject/reinsert test was postponed after a later same-session motor
restart failed. Use the refined RTL and second rebuilt bitstream described
below before resuming any hardware matrix.

## Follow-up PA1 failure: pre-first-index staleness must preserve history

Without ejecting, toggling the feature, resetting or JTAG-loading again, the
maintainer next ran another `LOAD"$",8`, which succeeded, followed by
`LOAD"C64ANABALT",8,1`, which returned `FILE NOT FOUND` and error channel
`74 DRIVE NOT READY 41 0`. The motor probably stopped before C64ANABALT, but
that detail was not observed with certainty. `41` is the requested DOS track,
not a distinct error class.

The new dump compared with the prior successful-SHADES dump proves where the
failure occurred:

- steps rose from 81 to 104: delta 23;
- completed reads rose from 103 to 129: delta 26;
- trace count rose from 287 to 362: delta 75, exactly
  `23 + 2 * 26 = 75`;
- requested-ID matches rose from 80 to 100 and `LAST_PRESENT` remains 512;
- every physical error counter remains zero and the index period remains
  healthy at approximately 199.64 ms;
- `CNT_CHANGE` remains zero and raw, conditioned and sticky disk-change state
  is clear; and
- the newest retained trace is entirely clean cylinder-39 directory traffic,
  with no cylinder-41 request.

The successful directory therefore accounts for every new physical operation.
The later C64ANABALT command again died on PA1 before issuing a WD request. It
cannot be an R=11, decoder, FIFO, media-change or delivery failure.

RTL review exposed a deterministic hole capable of producing this intermittent
result. The first repair preserved `rotation_confirmed` across motor-off, but
the commanded-motor `idx_gap_cnt` path unconditionally erased it after two
maximum periods (500 ms), even if no index had yet arrived on that restart. A
slow or worst-phase spindle start could therefore lose same-medium history
before its first edge, making that edge cold edge 1 and forcing the ROM to wait
for edge 2 again.

The refined rule in `physical_1581_controller.vhd` is deliberately narrow:

- readiness always remains low until a fresh edge;
- the staleness deadline always resets the current edge count;
- before the first edge of a motor-on interval, it preserves the prior
  `rotation_confirmed` proof; raw `/DSKCHG` remains authoritative for eject or
  replacement;
- once at least one index has occurred, later index staleness clears history,
  so a stalled/removed running disk must requalify with two edges; and
- reset, disable and raw `/DSKCHG` still clear history unconditionally.

The complete state/assignment audit has no uncovered transition:

- reset or `en=0` forces count 0, ready 0, confirmation 0 and change latch 1;
- cold start advances 0 -> 1 -> 2 indexes, asserting ready only after edge 2;
- confirmed motor-off preserves only confirmation, while count and ready are 0;
- fast or delayed restart keeps ready 0 until edge 1, then uses confirmation;
- a stall after any current-run edge sees the old nonzero count on the clock
  edge, clears confirmation and count together, and returns to cold state;
- raw change clears confirmation and sets the latch even if it coincides with
  index/staleness processing; the second-index set condition is explicitly
  blocked while change is asserted or latched; and
- a Type-I step may clear the latch once the sensor is inactive, but it cannot
  restore confirmation. In the qualified eject flow, motor-off/absence also
  resets the live edge count, so the replacement requires two new indexes.

VHDL signal-assignment semantics are important in the staleness branch:
`idx_motor_cnt > 0` is evaluated from the pre-clock value, so the simultaneous
`idx_motor_cnt <= 0` cannot hide evidence that this interval had already
rotated. There are only four assignments to `rotation_confirmed`: clear on
reset/disable, clear on asserted change, set on the second clean index, and
clear on post-index staleness. Type-I handling contains no `media_ready` gate.

The focused media-contract regression now waits 41 ms with a scaled 40-ms
staleness deadline before delivering the first restart edge. The committed RTL
fails at 42.20575 ms with `confirmed unchanged medium lost history before
delayed first index`; the refined RTL passes. The following independent check
still withholds index after readiness and proves that post-index staleness
clears history and requires two fresh edges. Raw-change, disable/re-enable
cold qualification and R=11-to-R1 tests also pass. Genuine-ROM
`run_proofs.py` remains `RESULT: ALL PROOFS PASS`.

The refinement is regression-complete and ready for a second R3 build:

- focused media-state/Read-Address contract: all tests pass, including delayed
  first edge and disable/re-enable;
- genuine 318045-02 ROM proofs: `RESULT: ALL PROOFS PASS`;
- full closed-loop controller/mechanism test: cold ready at 398.2 ms, Type-I,
  byte-exact cylinder 0/1 reads, Read Address, Verify, RNF, pending requests,
  change-abort spacing and recovery all pass; and
- tiny-FIFO overflow/quarantine test: CRC-only failure, RNF clear and no silent
  success.

Decoder, quantizer, input, diagnostic and SystemVerilog production sources are
unchanged from `b13d99e`; their already-green full matrices remain applicable.
The controller refinement and focused test were committed as `bdd457b`, and
all hardware gates described below subsequently passed.

## Working tree at final hardware handoff

Repository HEAD is the pushed maintainer commit `aa6b70f` (`Document final R3
physical 1581 qualification (#90)`). Its parent `bdd457b` contains the final
controller RTL and focused contract; `aa6b70f` is documentation-only and
records all four successful final hardware checkpoints below. There are no
generated simulator artifacts. Before the final next-instance addendum at the
end of this file, the working tree was clean.

## Second R3 hardware: varied-pause restart qualification passes

The bitstream containing the delayed-first-index refinement passed hardware
steps 1 and 2. The disk was absent during power/JTAG/feature activation and was
then inserted. Directory and all prescribed unchanged-media stopped-motor
loads succeeded after short, approximately 30-second and minute-scale waits.

The post-sequence map-v7 dump is exact and clean:

- `CNT_IDX_RAW=CNT_IDX_QUAL=632`, with
  `IDX_PERIOD=0x00985257` = 199.651 ms and a 2.636-ms index width;
- 64 completed steps, 154 completed reads and `TRC_CNT=372`, exactly
  `64 + 2 * 154`;
- 120 requested-ID matches, final clean `C/R=41/7`, size code 2 and
  `LAST_PRESENT=512`;
- zero RNF, CRC, cancel, disk-change, LOST, drain, stale completion,
  busy-command, runt and DAM-miss counters;
- 6,955 decoded IDs, 13,595 gap errors = about 21.5 per qualified revolution,
  and `EST=0x063C` = 99.75 cycles; and
- the newest ring entries are a complete clean cylinder-41 sector sequence
  `8,9,10,1,2,3,4,5,6,7`, proving C64ANABALT reached the physical medium.

The acquisition diagnostics are safe rather than perfectly empty:
`CNT_A1_CAND=42878`, `CNT_A1_REJECT=15`, `CNT_A1_TRAIN=14269`, and
`CNT_DAM_UNARMED=1`. There are 71 candidates beyond three per completed train,
but zero CRC/RNF/DAM-miss consequences; the complete-span and record-sequencing
guards rejected the observed splice/junk candidates as designed.

This closes the fast- and slow-restart classes on real hardware. The maintainer
is continuing immediately with (3) motor-off eject/reinsert in the same FPGA
session, with a dump before another eject, and (4) a fresh disk-preinserted
power/JTAG session followed by directory and immediate SHADES.

## Second R3 hardware: eject/reinsert qualification passes

In the same FPGA session, after motor-off the disk was ejected, left out for
the prescribed pause, reinserted, and `LOAD"$",8` succeeded. The dump was taken
before another eject. Compared with the varied-pause dump:

- `CNT_CHANGE` rose 0 -> 1 exactly once; raw, conditioned and sticky change
  state are clear at the final snapshot;
- steps rose 64 -> 68, reads 154 -> 169 and trace count 372 -> 406, exactly
  `34 = 4 + 2 * 15`;
- requested-ID matches rose 120 -> 130, final `C/R=39/8` is clean, and
  `LAST_PRESENT=512`;
- all RNF, CRC, cancel, LOST, drain, stale, busy, runt and DAM-miss counters
  remain zero;
- qualified indexes rose 632 -> 696, with
  `IDX_PERIOD=0x0098515F` = 199.646 ms; and
- gap errors rose by 1,060 = 16.6 per added revolution, while A1 candidates
  rose by 4,209 and trains by 1,403 exactly, with no new span reject.

This is the load-bearing hardware proof that a real eject asserts `/DSKCHG`,
destroys the same-medium history, and allows a clean cold requalification. The
then-remaining read-milestone gate was the disk-preinserted cold case, which
also passed as recorded below.

## Final R3 hardware: disk-preinserted cold qualification passes

With the disk already inserted, the maintainer performed a fresh power-on,
JTAG load and internal-1581 activation, then successfully ran the directory and
immediate SHADES sequence. The final map-v7 dump is wholly clean:

- 217 raw and 217 motor-qualified index edges,
  `IDX_PERIOD=0x009850A6` = 199.642 ms and index width 2.992 ms;
- 103 steps, 53 completed reads and `TRC_CNT=209`, exactly
  `103 + 2 * 53`;
- 40 requested-ID matches, final clean `C/R=62/8`, size code 2 and
  `LAST_PRESENT=512`;
- zero RNF, CRC, cancel, disk-change, LOST, drain, stale completion,
  busy-command, runt, span-reject, unarmed-DAM and DAM-miss counters;
- a valid anchored head estimate at cylinder 62;
- 2,363 decoded IDs, 5,295 gap errors = about 24.4/revolution, and
  `EST=0x0634` = 99.25 cycles; and
- 14,543 A1 candidates versus `3 * 4,847 = 14,541` complete trains, only two
  incomplete extras, with `CNT_MARK_FE=CNT_MARK_DAM=CNT_IDDEC=2,363`.

The retained trace contains clean Read Address and sector operations on
cylinders 61/62 and ends with successful cylinder-62 delivery. Together with
the varied-pause and eject/reinsert checkpoints, this closes every prescribed
fresh-media R3 hardware class: cold, warm, fast restart, slow restart,
post-eject, and disk-preinserted JTAG cold. The read-only physical-1581
milestone is complete in substance. Marginal-media stress and physical
write/format support remain explicitly separate future milestones.

## Bonus R3 stress: concurrent load transport passes; clean control runs

In the same successful disk-preinserted session, SHADES was left playing its
SID tune while the maintainer issued `LOAD"C64ana*",8,1`. The wildcard program
load command completed successfully. Attempting to start C64ANABALT in that
still-live application environment then crashed. This is not evidence of a
drive error: an arbitrary SID player may own code/data memory, zero page,
vectors and IRQ state that the game load overwrites or continues to modify.
Compared with the immediately preceding dump, the drive transaction itself is
clean:

- steps rose 103 -> 128, completed reads 53 -> 104 and trace count 209 -> 336,
  exactly `127 = 25 + 2 * 51`;
- requested-ID matches rose 40 -> 80, final `C/R=41/4` is clean, and
  `LAST_PRESENT=512`;
- every RNF, CRC, cancel, disk-change, LOST, drain, stale completion,
  busy-command, runt, unarmed-DAM and DAM-miss counter remains zero;
- qualified indexes rose 217 -> 413, with
  `IDX_PERIOD=0x00985356` = 199.656 ms;
- gap errors rose by 4,216 = 21.5 per added revolution, with
  `EST=0x0638` = 99.5 cycles; and
- the newest trace contains clean cylinder-41 sectors
  `7,8,9,10,1,2,3,4`.

The 16 A1 span rejects and 34 candidates beyond `3 * 9,316` complete trains
were safely quarantined with no requested-record effect. This proves that
simultaneous C64 SID playback and the load command exposed no physical-drive
delivery or media-state weakness; it does not claim arbitrary loaded programs
can start safely over an active SID player.

The maintainer then performed the necessary one-variable control: short C64
reset, no SID player, normal C64ANABALT reload and start. The game ran normally.
Therefore the disk content, program, physical/WD path and normal IEC transfer
are good, while the earlier crash is isolated to application memory/IRQ state.
No further fresh-media read testing is needed for this milestone.

## 2026-07-18 addendum: restore strict image/physical isolation

### Corrected diagnosis

An image-backed D81 mounted but `LOAD"$",8` could remain forever at
`SEARCHING FOR $`; D64 continued to work because it uses the separate 1541
engine. The governing issue-90 invariant is stricter than merely making this
specific command complete: with physical mode off, the proven simulated-D81
path must behave exactly as it did before the physical-drive work.

The first attempted repair generalized the physical-only minimum Type-I BUSY
timer to image mode. That repair was rejected and fully reverted because it
changed image timing instead of restoring isolation.

A historical differential test then located the actual image-visible branch
delta. Early physical commit `88c09d2` retains the old image expression
`data_out <= data_in` on a WD data-register write. Commit `b2bd629` changed it
unconditionally to `data_out <= cpu_din` for the physical ROM startup test.
That physical fix was correct but its missing mode gate altered simulated-D81
register behavior too.

The controls are exact:

- `tb_fdc1772_image.sv` compiled against `88c09d2` passes;
- the same test compiled against `b2bd629` fails only the data-register
  compatibility check (`5A` observed instead of legacy `A5`);
- unmodified branch HEAD fails identically; and
- Read Address, all ten directory sectors, all ten LBAs and all 5,120 payload
  bytes pass in every case, isolating the regression from image-sector DMA.

Direct source comparison also confirms that `data_out <= data_in` is the
pre-physical `develop` (`1377b8d`) expression. The executable differential uses
`88c09d2` because `1377b8d` still relies on declaration-after-use constructs
accepted by Vivado but rejected by Icarus; `88c09d2` made that source strictly
elaboratable before the first image-visible behavior change.

### Isolation fix

`fdc1772.v` now uses:

`data_out <= phys_mode ? cpu_din : data_in;`

Therefore image mode executes the exact pre-change expression, while physical
mode executes the exact already-qualified current-value readback expression.
The physical-only Type-I timer remains physical-only.

A complete comparison against pre-physical `develop` (`1377b8d`) confirmed
that the existing `pa_out[6] | fdc_busy` LED expression predates issue 90 and
is part of the legacy image behavior; it must therefore remain unchanged. All
other shared-path changes either sit inside `if (phys_mode)` or select their
old expression explicitly when `phys_mode=0`. The deliberate source-switch
disk-change indication remains the one transition-specific exception; it is
needed to prevent stale BAM state when changing media backends.

### Permanent image regression

New self-checking test
`CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_image.sv` holds
`phys_mode=0` and checks:

- the legacy WD data-register contract from `88c09d2`;
- six-byte Read Address;
- directory-login order `7,8,9,10,1,2,3,4,5,6` at cylinder 39;
- exact D81 LBAs and all 5,120 bytes through the real dual-clock FDC RAM and
  `clk_sys` SD request state machine; and
- inactive SD-write and physical-controller outputs.

Fixed RTL and `88c09d2` produce byte-identical passing transcripts with SHA-256
`896991a5265fdff23ec3c4881688a654d563394b49a1c6a855c1748f9644f64e`.

### Physical-read non-regression evidence

For `phys_mode=1`, the changed WD assignment reduces exactly to the unmodified
branch expression `data_out <= cpu_din`; no other product expression changed.
Fixed and unmodified-HEAD physical WD benches pass and produce byte-identical
transcripts with SHA-256
`28695e37d2898a4a6ff7a448783c115ddd3d7d5f68bc991ff738be35f5c8a1d3`.
The already completed physical VHDL/controller and genuine-ROM proof suites are
unaffected because no physical-mode expression or physical controller source
changed.

This establishes two-sided source-level isolation plus behavioral controls.
The final release gate remains a newly synthesized R3 hardware run: image-mode
`LOAD"$",8` plus a program, followed by the qualified physical sequence (cold
preinserted directory/program, stopped-motor repeat, eject/reinsert). Simulation
cannot certify synthesis, a particular board or a particular disk.

## Next-instance continuation: community stock-media gate, then write milestone

The implemented milestone is deliberately **read-only**. R3 hardware is fully
qualified with a fresh MEGA65/F011-written DD disk, and source-derived tests
exercise the exact genuine 318045-02 stock formatter layout byte-exactly. A
physical disk formatted and written by a genuine Commodore 1581 has not yet
been available locally. Confidence is high because stock ID fields have the
conventional zero preamble (easier than the F011 no-preamble ID case), use
sectors 1..10 (unaffected by the Read Address filter), and share the same DD
MFM/index/readiness path. This remains strong evidence, not hardware proof.

The immediate external gate is Discord/community testing, not new RTL:

1. Distribute the R3 bitstream built from production commit `bdd457b`
   (`aa6b70f` differs only in documentation). State prominently that the
   physical write gate and write-data pins remain inactive.
2. Prefer a backed-up or sacrificial genuine DD disk formatted/written by an
   actual 1581 and verified in that drive immediately before testing. Record
   the source drive, disk/media provenance, MEGA65 board revision and whether
   the known file ran on the genuine machine.
3. On MEGA65, run a cold `LOAD"$",8`, load one known program, let the motor
   stop and repeat one load. Capture the BASIC result, error channel and map-v7
   `0x7000..0x707F` dump before ejecting. An optional same-session
   eject/reinsert directory test covers `/DSKCHG` again.
4. A pass requires correct directory/program behavior, exact request/result
   trace pairing, `LAST_PRESENT=512`, and zero RNF/CRC/LOST/delivery/DAM-miss
   counters. Do not retune the decoder from one aged-disk failure: first prove
   the disk still reads on its genuine 1581, reproduce it, and compare several
   independently written disks if available.

If that gate passes, freeze/merge the read-only milestone without further
decoder changes. If a verified stock disk reproducibly fails, diagnose from
map v7 before choosing any acquisition change; marginal-media work remains a
separate evidence-driven branch.

The next implementation milestone after read qualification is physical
**write and format support**, and must start as a new safety-scoped plan:

1. Add an explicit write-capability generic/interlock that defaults off; retain
   inactive WGATE/WDATA on unsupported builds and honor write-protect, eject,
   reset, cancel, underrun and motor/readiness safety on every path.
2. Implement physical WD1772 Write Sector first: drive-CPU byte ingestion,
   reverse-direction buffering, MFM encoder, sync/mark generation, CRC, exact
   byte pacing and bounded abort/finalization. Read behavior must remain
   unchanged when write capability is false.
3. Prove normal and adversarial writes in simulation with a writable mechanism
   model, including write-protect, starvation, reset/eject mid-command and
   byte-exact read-after-write. Do not enable physical WGATE before these gates
   pass.
4. Qualify on sacrificial DD media with SAVE, overwrite, SCRATCH/VALIDATE and
   power-cycle readback, checking the disk both in MEGA65 and another reader.
5. Add WD1772 Write Track/stock-1581 format only after sector writes are safe;
   verify formatter gaps, address/data marks, CRCs and interoperability with a
   genuine 1581. Then qualify other MEGA65 board revisions separately.

Do not begin this implementation merely by continuing the current read patch.
The user must explicitly open the write milestone because it changes the core
from magnetically incapable of writing to intentionally energizing WGATE.

For a fresh Codex instance, read in this order: repository `AGENTS.md`, this
file completely, `doc/dev-issue90/plan_codex.md` completely, and Fable-owned
`doc/dev-issue90/f011_reference_notes.md` completely. Preserve the Fable file
unless Fable updates it. Current engineering state: no active RTL task; wait
for community stock-disk evidence or explicit authorization to plan writes.
