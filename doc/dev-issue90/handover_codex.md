# Issue #90 — Codex handover

This is the Codex-owned handover for work after commit `2e2c852`. It is kept
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

Simulation now covers the two real formatter layouts and both known decoder
regressions. The next bitstream must still be qualified on physical R3 media:

- cold power-on, enable physical 1581, then `LOAD"$",8`;
- load SHADES and C64ANABALT repeatedly;
- verify `CNT_IDDEC` is nonzero/normal and `RNF_CTX` does not remain at the
  round-13 zero-ID signature;
- verify far cylinders remain reliable and `EST` remains bounded near nominal;
- confirm splice-adjacent sector 1 remains readable.

## Source discipline

- Do not modify Fable's `HANDOVER.md` or `PLAN.md`.
- Codex progress belongs in this file and `plan_codex.md`.
- The maintainer commits; Codex does not commit.
