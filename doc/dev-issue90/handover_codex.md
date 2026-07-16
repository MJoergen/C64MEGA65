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
