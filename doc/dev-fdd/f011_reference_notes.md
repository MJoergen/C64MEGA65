# F011 Reference Notes — What the MEGA65's Own Decoder Does Differently

Working note (Fable, 2026-07-16), written after the maintainer's control result
below. Audience: codex (currently in charge) and future sessions. Sources are
the pinned mega65-core `a9158930` copies in `doc/dev-fdd/upstream/` and
`../mega65-core`; architecture background in
`doc/how-MEGA65-uses-the-physical-disk-drive.md`.

## 1. The control result and what it proves

2026-07-16, maintainer: **the MEGA65 itself (C65 mode, F011 + the same internal
mechanism) reads the problem medium flawlessly.**

Consequences:

- Medium, mechanism, pins, cabling: **exonerated**. The failures live entirely
  in our decode/qualification/delivery stack.
- The F011 is a **purely digital** decoder — a 40.5 MHz sampler on the same
  `f_rdata` signal we get, no analog PLL. So "you need an analog data
  separator to survive splice junk" is disproved; a digital chain demonstrably
  suffices on this exact disk.
- Caveat: "flawless" at user level may include DOS-level retries. Only the ROM
  could quantify the retry budget (see section 6).

## 2. The F011 live read chain at pin `a9158930`

`f_rdata` → `mfm_gaps` → `mfm_quantise_gaps` → `mfm_gaps_to_bits` →
`mfm_bits_to_bytes` → record FSM in `mfm_decoder.vhdl` (CRC via `crc1581`).
Three decoder instances run in parallel in `sdcardio.vhdl`: DD fixed
(`cycles_per_interval = 81`), HD fixed (`40`), and a variable-rate instance fed
from the Track Info Block (also handles RLL2,7).

`mfm_deglitch.vhdl` exists in the tree but is **not instantiated** by
`sdcardio.vhdl` or `mfm_decoder.vhdl` at the pin — the live path has **no
glitch/runt filter at all**.

## 3. Mechanism inventory (verified in source)

1. **Quantiser** (`mfm_quantise_gaps.vhdl:39-63`): fixed thresholds,
   midpoint-touching, **no dead-bands, no adaptation**. Windows at DD
   (nominal gaps 4/6/8 µs): SHORT accepts 2.0–5.0 µs, MED 5.0–7.0 µs, LONG
   7.0–12.0 µs. The interior boundaries are exactly the class midpoints — the
   same points our adaptive quantiser uses. The **outer** edges are far wider
   than ours: 0.5x nominal at the bottom, 1.5x nominal at the top (in our
   50 MHz half-cell units: SHORT accepts down to 100 cycles where we cut at
   150; LONG accepts up to 600 where we cut at 450). Out-of-window gaps emit
   no bits and reset nothing.
2. **Sync detection** (`mfm_gaps_to_bits.vhdl`): the last four quantised gap
   classes are compared against the exact missing-clock A1 signature; a match
   pulses `sync_out` and realigns byte assembly. That is the entire
   acquisition rule — **no preamble rule, no A1-spacing rule, no aggregate
   span rule, no zero-run rule exist anywhere in the F011.**
3. **Record FSM** (`mfm_decoder.vhdl:418-477`): **any sync mark
   unconditionally re-anchors the parser, even in the middle of a data
   field** (state back to `WaitingForSync`, `byte_count` cleared). A mark byte
   (`FE` / `FB` / `65` = Track Info Block) is dispatched only when at least
   three consecutive syncs immediately precede it. The ID path checks CRC,
   then track+sector match — the side byte is deliberately ignored
   (`mfm_decoder.vhdl:363-364`), same call we made with H.
4. **Delivery arm** (`mfm_decoder.vhdl:671`):
   `byte_valid <= seen_valid and byte_valid_in`, and `seen_valid` is set only
   by a CRC-valid ID matching the requested track+sector. An unsolicited or
   splice-born DAM therefore **delivers zero bytes** — it is parsed, CRC'd,
   and discarded.
5. **Rate and retry policy** live above the decoder: the Track Info Block
   switches data rate/encoding per track, and the C65 DOS / hyppo owns
   retries. The F011 hardware itself never retries.

## 4. The architectural lesson

The F011 does **not** out-discriminate splice junk. Its quantiser and sync
detector are *more* permissive than ours: the reconstructed round-12 junk
chain (446/344-cycle gaps) passes its windows and its 4-gap signature check
just as it passed ours. The F011 is simply **immune to the consequences**:

- an unsolicited field delivers nothing (mechanism 4);
- a bogus parse can never consume the following real record, because the real
  record's own A1 train re-anchors the parser mid-parse (mechanism 3);
- CRC plus DOS retry decide everything else.

Junk costs the F011 nothing, so it needs no junk discrimination. Our failures
happened because, before the quarantine, junk had consequences: speculative
bytes reached a fragile consumer (the genuine 1581 ROM: the `CD5A` status
table hole maps CRC+RNF to success; one LOST flag corrupts its stack return
path), and bogus parses ate real records.

Commit `ef272ef` converges on the F011 structure: the CRC-valid-ID arm
(`47432c8`) is `seen_valid`; the qualified-FE re-anchor is a weaker form of
mechanism 3; the sector quarantine is a *stronger* delivery gate than the
F011's live streaming — justified, because our consumer is fragile where the
F011's (its own sector buffer + status register) is not. The remaining
timing qualifiers — A1 spacing, aggregate span, DAM zero-run — have **no
F011 counterpart**. With arm + CRC + quarantine in place they no longer
protect integrity; they are availability filters only, and each can only
subtract (reject a real mark on real flux).

## 5. If the `ef272ef` bitstream still fails

The expected residual failure mode is availability (RNF or CRC-retry at
splice-adjacent sectors), not corruption. Cheapest-evidence-first options:

1. **A/B the true F011 windows** as a harness column: fixed, no-dead-band,
   outer edges 0.5x/1.5x nominal. Note the existing "old fixed" column is
   *not* this — the old C64MEGA65 windows had dead-bands and tighter outer
   edges. The actual F011 classifier has never been in the matrix, despite
   being the one decoder proven on this disk.
2. **Adopt the any-sync re-anchor** (or any-qualified-sync), F011-style,
   instead of FE-only — recovery from a slipped-through bogus DAM then costs
   bytes, not a revolution.
3. **Relax or remove the spacing/span (and possibly zero-run) gates** and let
   arm + CRC + quarantine + DOS retry carry the load, keeping a gate only
   where the harness proves an availability win on real-flux-derived vectors.
4. **Ground truth before more hypotheses**: a raw gap-length trace ring
   around the index/splice window (the diag/trace infrastructure exists)
   turns the next failure into a waveform instead of another counter-derived
   guess.
5. **Runt filter semantics**: the F011 live path has no filter — sub-window
   gaps classify invalid and vanish without side effects. Ours merges runts
   shorter than 16 cycles into the successor gap. The difference is small but
   nonzero exactly at splices; the trace ring in (4) would settle it.

## 6. Why the MEGA65 ROM is not the artifact to mine

Maintainer offered `~/Downloads/MEGA65.ROM` (the C65/MEGA65 system ROM) for
inspection. Assessment: **wrong layer for this bug.** The ROM (C65 DOS +
hyppo) never touches flux — it programs F011 job registers (`D080`–`D08F`),
polls BUSY/DRQ/status, and consumes whole, already-validated sectors. Every
mechanism our failures involve — gap classification, sync acquisition, record
grammar, CRC, byte delivery — is FPGA VHDL on the MEGA65 too, and that VHDL
is already pinned in-repo (`doc/dev-fdd/upstream/`, `../mega65-core` @
`a9158930`) and summarized in `doc/how-MEGA65-uses-the-physical-disk-drive.md`.
Sections 2–4 above are the distilled result of mining it.

What the ROM *could* still answer, cheaply, if ever needed: the DOS retry
budget (whether "flawless" is retry-masked), format/verify policy, and how the
DOS consumes Track Info Blocks. That is tie-breaker material for interpreting
marginal hardware results — not decoder-design input. Keep the file handy; no
disassembly is warranted now. The drive-side ROM that *is* load-bearing for
us — the 1581's genuine `318045-02` — is already in-repo and runs in the
`rom_emu` proof suite.

## 7. Source-proven: the truncated 11th sector (the real identity of the "splice junk")

The pinned F011 auto-formatter (`sdcardio.vhdl`, `FDCAutoFormatTrack`) has
**no sector-count stop**: the sector loop's last state (599) unconditionally
returns to state 13 ("Move to next sector"), `format_sector_number` keeps
incrementing, and the only terminator is the next index rising edge, which
drops `f_wgate` mid-record and aborts ("write as many sectors as will fit,
but no more"). The TIB (`A1 A1 A1 65 track rate encoding sectors CRC CRC`,
states 1000–1014) is written once at the track start, at DD rate, after 13
zero bytes.

Consequence: **every F011-auto-formatted track carries the beginning of an
11th sector, cut off by the format-abort write splice at the index.** On the
maintainer's disk the 11th ID field completes before the index: the 2026-07-16
dump shows it decoded as found `C=39 H=0 R=11 N=2` with a clean controller
result — a CRC-valid, *real* ID record (its stored CRC computes to `0x43C7`).
Note that the `ID_STORED_CRC` diagnostic word is free-running — it keeps
updating with every ID the decoder flies over while the disk spins — so it
must not be paired with the last operation's CHRN words. This one structure
explains years of accumulated observations at once:

- the ~10.9 decoded IDs/revolution (bring-up round 2);
- the 22-vs-20 qualified A1 trains/revolution that disproved the span check
  (map-v6 analysis) — two extra *timing-perfect* trains, because they are
  genuinely formatter-written, not random noise;
- the persistent trouble right after the index at sector 1 (rounds 12–13 and
  all codex rounds): reading sector 1 means traversing truncated-11th-sector
  remains, the wgate-off splice, the 00 lead-in and the TIB first;
- Read Address replies with `R=11` (rounds 2, 5, and today).

The stock 1581 ROM was never designed for an 11th CRC-valid ID on a 10-sector
track. Note a **real 1581** (real WD1772) would see the same ID — its Read
Address returns whatever ID comes next. F011 media is subtly out-of-spec as
stock 1581 media; the MEGA65 itself is immune only because its own DOS never
does 1581-ROM-style RA-driven positioning on it.

## 8. Hardware dump decode, 2026-07-16 (`ef272ef` bitstream, map v7)

Failed cold `LOAD"$",8`; dump `0x7000`–`0x707F`. Decoded highlights:

**A. The delivery war is won.** `CNT_LOST=0` (was 686 on `47432c8`),
`CNT_DRAIN=0`, `CNT_STALEDONE=0`, `CNT_BUSYCMD=0`, `CNT_RUNT=0`, `EST=0x640`
(exactly 100.0 cycles), `CNT_READOP=5` with `CNT_RNF=0`, `CNT_CRCERR=0`,
`CNT_CANCEL=0` — five for five clean operations, `LAST_PRESENT=6` (a Read
Address reply). `CNT_LOST=0` also proves timely consumption of every
presented byte except possibly the final one of the last reply (a trailing
unconsumed byte has no successor to overwrite it, so it is unobservable);
whether the ROM accepted that last reply and continued is not provable from
the dump. The quarantine + presentation fixes are hardware-proven.

**B. The failure is now purely a DOS-dialogue phenomenon.** Reconstructed
flow: position-locate RAs at the resting cylinder (~3), a 36-step seek to
cylinder 39 (head estimate ends at 36 because it started unanchored at 0 —
the DOS positions itself relatively via RA, it never restores), then
RA → `(39,0,6,2)` OK, RA → `(39,0,11,2)` OK — **the truncated 11th ID** —
and then *zero* further WD data operations. The motor accumulated 65
qualified revolutions before idle timeout; the load failed without a single
Read Sector (`CNT_MATCH_ID=0`). The trace's second RA request word also
proves the WD1772 RA quirk (found track written into the sector register,
`0x27` visible) works. Leading suspect: the stock ROM mishandles the
out-of-range `R=11` reply in its positioning logic and goes silent — a
rotational lottery (which ID an RA catches), which is why earlier rounds
sometimes sailed through. This is correlation, not proven causality: a
*forced* `R=6` then `R=11` reply sequence in the genuine-ROM emulator
recovers with further Read Addresses, so only a rotationally-faithful F011
end-of-track model can settle it. One competing explanation converges on
the same transition point (positioning complete, first Read Sector never
issued): a momentary PA1 ready dip. The emulator can force both conditions
independently. (A stuck `/DSKCHG` was a third suspect until the evening
dump pair exonerated the latch path — see C.) *Update:* codex's
rotationally-faithful F011 layout in the ROM emulator (6250 bytes/rev,
ten sectors plus the truncated 11th ID) subsequently produced a run
matching failure #1 exactly — locate RA at the resting cylinder, 36-step
seek, RA `R=10`, RA `R=11`, then job error `02` with **zero** Read
Sectors — while a phase-shifted neighbor run (RA `R=5`, `R=6`) completed
with ten sector reads. Pending codex's controlled one-variable write-up,
this is the R=11 causality reproducing in the model.

**C. Disk-change latch — RESOLVED, path exonerated.** The evening dump pair
(section 9) settles the counting semantics empirically: the power-up arm is
an *initial value*, not a counted edge (post-enable dump: wiggle cleared the
latch, `CNT_CHANGE=0`), and every counted event is a real re-latch
(post-eject dump: `CNT_CHANGE=1` with the latch set). Retroactively,
failure #1's `CNT_CHANGE=1` with the latch set and the raw pin asserted =
the maintainer ejected the disk *before* dumping; the latch had cleared
normally during the session and the DOS saw `/DSKCHG` clear throughout.
PA7 is off the suspect list for failure #1; the remaining suspects are the
`R=11` reply handling and a momentary PA1 ready dip. (Maintainer also
confirmed: failure #1 ended in FILE NOT FOUND, no hang, error channel not
read.)

**D. Worth a baseline:** `CNT_GAPERR=27,345` over 65 revolutions (~420/rev)
versus the ~42/rev round-9-era baseline. Possibly definitional under the
adaptive classifier; possibly availability evidence. Compare against a
known-good session.

**Recommended next steps** (in order): (1) extend the `rom_emu` track model
with a faithful F011 end-of-track — truncated 11th sector + TIB + splice —
and replay the genuine-ROM login until it reproduces the silence after an
`R=11` RA reply; the emulator shows the exact ROM branch. Two emulator
control runs discriminate the co-suspects: 11-ID track with PA7 normal,
10-ID track with PA7 (`/DSKCHG`) stuck asserted. (2) If confirmed, the fix
is a compatibility shim on our side: the physical Read Address (and ID-match
candidacy) should skip IDs with `R` outside 1..10, presenting F011 media to
the stock ROM as clean ten-sector 1581 media — robustness over
bug-compatibility with real-1581 behavior on out-of-spec media. (3)
Root-cause the change-latch clear (RTL clear condition; on hardware watch
`CTRL_STATE` bit 4 across steps). (4) The `CNT_GAPERR` baseline.

**Same-day follow-up:** a retry (disk out, power-cycle, re-JTAG of the same
`ef272ef` core) loaded the directory successfully. This is the predicted
signature — the `R=11` exposure is a per-attempt rotational lottery (which
ID the critical Read Address catches), so intermittency confirms rather
than contradicts. The success also carries new information: it is the first
hardware proof of full 512-byte sector delivery through the CRC quarantine
(the failed session never reached a Read Sector). Hardware protocol until
the rom_emu verdict lands: repeat cold `LOAD"$",8`; on each failure check
the fingerprint `CHRN_CR=0x270B` (offset `0x07`) with `CNT_MATCH_ID=0`
(offset `0x3E`); after at least one success, dump with the disk still
inserted and read `CTRL_STATE` bit 4 to learn whether the disk-change latch
also stays stuck on good runs (benign) or cleared (condition-dependent
co-suspect).

**Second follow-up (same day, decoded by codex):** the successful-session
dump proves the full stack end to end — ten quarantined sector reads in
physical order 3..10,1,2, `CNT_MATCH_ID=10`, `CNT_LOST=0`, zero error
counters, trace arithmetic exact (`TRC_CNT 110 = 80 steps + 2×15 ops`),
head estimate anchored and valid at 39, disk-change pin and latch both
clear. The subsequent
`LOAD"SHADES"` failed with `74, DRIVE NOT READY,40,0` and **zero** physical
operations after the directory fill — the PA1 ready-gate class already seen
in bring-up round 4 and logged-deferred in round 12: synthetic ready needs
motor spin-up plus two index edges, while the stock ROM allows about 0.7 s
before its one-shot 30-sample PA1 check at `CDBC`. Joint-fix idea: if
`/DSKCHG` has never asserted since the last confirmed rotation, the same
disk is necessarily still inserted, so ready may re-assert on the *first*
index edge after motor-on instead of the second — a full revolution less
worst-case latency with no loss of eject detection. Codex also extracted
the first on-hardware availability datum for the F011-window experiment:
`GAP_MIN=126` cycles on this disk versus our ~145-cycle lower acceptance
edge at `EST=96.625` — real flux we reject, the true F011 windows accept
(down to ~100). Open maintainer facts that discriminate the theories: the
exact error text of the first failed session (`74` vs `FILE NOT FOUND` vs
hang), whether the motor had audibly stopped before the SHADES command and
how long the pause was, and whether the disk was inserted before or after
power-on in the first failed session. (Answered same evening: failure #1
showed FILE NOT FOUND, no hang; the SHADES failure followed a ~1 minute
pause with the motor audibly stopped — supporting the PA1 spin-up-latency
reading.)

## 9. The "gross clicking" session, 2026-07-16 evening — a mechanical event, fully decoded

Session: disk inserted before power-cycling, JTAG of the same `ef272ef`
core, loud clicking (~3 s) the moment "Use internal 1581" was enabled,
clicking again (>1 s) on `LOAD"$",8`, error channel
`74, DRIVE NOT READY,00,00`; the maintainer ejected the disk mid-test out
of concern for the medium. Two dumps (post-enable, post-eject) decode to
one clear story:

**The medium was never at risk.** Writing is *physically impossible* in
this bitstream: `f_wgate_o` and `f_wdata_o` are hardwired `'1'` (inactive)
at the FPGA top level (`M2M/vhdl/top_mega65-r3.vhd:470-471`) — no logic
state can energize the write head. Total mechanical activity across the
whole session: the DOS disk-change wiggle, i.e. one step inward and one
step outward (`CNT_STEP=2`, `TRC_CNT=2`, both trace entries decoded), zero
read operations. Head steps cannot damage media.

**What the noise was: the disk never rotated properly this session.** The
post-eject dump shows a last index period of `0x01D92DD6` = 619 ms
(healthy: 199.65 ms) while the index *pulse width* stayed normal
(`0x000202CE` ≈ 2.6 ms) — the signature of normal-speed bursts separated
by stalls, i.e. **the disk slipping and re-catching on the spindle
clamp**, which is exactly a rhythmic clacking sound. Corroborating
starvation: ~1 decoded ID per revolution post-enable and 5 IDs in ~17
revolutions during the LOAD (a healthy pass decodes ~11/rev), gap-error
rate ~3,000–5,500/rev (working session: ~420/rev), `EST` pinned at the
100.0 reseed value (constant loss of lock). Error 74 is the *designed
correct response*: index edges go stale between stalls, synthetic ready
drops, and the DOS refuses to operate on garbage.

**RTL exonerated:** the same bitstream measured a perfect 199.65 ms
rotation twice earlier the same day (failed and successful sessions
alike). The variable is this insertion — the disk was seated badly
(inserted before power-cycling; clamp likely never engaged cleanly).
`CNT_IDX_RAW` equals `CNT_IDX_QUAL` in both dumps, so the motor line was
held steadily on during rotation windows (no motor-line cycling).

**Actions:** eject, inspect, reinsert firmly; verify the disk in C65 mode
(F011 `DIR`) to confirm it is unharmed; then resume the codex test matrix
from test 1. **New pre-flight rule for all future hardware tests:** after
enabling the internal 1581, read `IDX_PERIOD` (`0x0D`/`0x0E`, expect
≈ `0x0098xxxx`) and watch `CNT_IDX_QUAL` tick ~5/s *before* the first
LOAD — a ten-second check that separates mechanical sessions from logic
sessions. Caveat: gap statistics from this session (`GAP_MIN` 126→70) come
from bad rotation and must not feed quantiser-window tuning; the
`GAP_MIN=126` availability datum from the *successful* session stands on
its own.

**Cross-core confirmation (same evening):** the maintainer then booted the
stock MEGA65 core (previously read this disk flawlessly) — **same
clicking**, and `DIR` returned `27, READ ERROR,40,00` (header checksum
error at the directory track). The fault follows the physical drive+disk
pair across two completely independent cores, which (a) definitively
exonerates the C64 core's logic, and (b) confirms the failure is
mechanical, arising between the morning's healthy sessions (twice-measured
199.65 ms rotation) and now, persisting across power-cycles. The read
error is the same bad-rotation symptom, *not* evidence of media damage.

Standing facts and plan:

- **No unique data is at risk.** The physical disk is a C65-mode BACKUP of
  `~/Downloads/C64.D81` (SHA-256 recorded in `handover_codex.md`); worst
  case it is rewritten from the image onto any fresh DD disk once the
  mechanism is healthy.
- **Disk-vs-drive discriminator:** insert a *different* 3.5" disk (content
  irrelevant — the test is sound + spin). Other disk also clicks → the
  drive (mechanism/clamp or its cabling) is at fault. Other disk spins
  silently → this disk's shell/hub is at fault.
- **Prime hardware suspects** given healthy-morning → faulty-evening
  across handling and power-cycles: floppy power/data cable seating
  (torque sag from a marginal power contact produces exactly slip-clack
  stutter), then the clamp mechanism, then this disk's hub/shell.
- **Quantitative instrument:** the C64 core's diag device is the only
  rotation meter available — enable the internal 1581 (its disk-change
  service spins the motor several seconds) and read `IDX_PERIOD` +
  `CNT_IDX_QUAL`; measure both disks. The stock MEGA65 core offers no
  equivalent.
- **Safety rule until rotation is healthy:** avoid all write operations in
  the stock MEGA65 core (its write path is live, unlike our read-only
  build): no SAVE, no scratch, no format, no BACKUP.
- Resume the codex matrix only after a measured-healthy rotation and a
  clean C65-mode `DIR`.

**Resolution (same evening):** in the stock MEGA65 core the maintainer
formatted a fresh DD disk and copied `~/Downloads/C64.D81` onto it — works
perfectly, no noise. Verdict: drive exonerated, the old disk's shell/hub
was mechanically at fault (not magnetically — nothing could write to it).

## 10. Fresh-disk matrix results — PA1 proven on hardware; fresh-flux baselines

Codex's warm/stopped A/B on the fresh disk (its handover records the full
decode) is a clean single-variable causal proof: warm motor → SHADES
succeeds with physical traffic; stopped motor + ~1 s → `74, DRIVE NOT
READY` with *zero* new physical requests and exact trace arithmetic. The
synthetic PA1 ready contract (motor + two index edges vs. the ROM's ~0.7 s
allowance before its one-shot PA1 check) is hardware-proven as the
immediate bug. Tests 3–4 are rightly deferred to qualify the repaired
build.

Three additional facts from the test-2 dump, worth keeping as baselines:

- **The old disk was magnetically marginal too.** Gap-error rate on the
  fresh disk: `CNT_GAPERR=2064` over 117 revolutions ≈ **17.6/rev**, versus
  ~420/rev on the old disk in its *working* session. This retroactively
  reframes part of the historical far-cylinder marginality (round 12) as
  media aging, and sets the healthy-media baseline for future dumps.
- **Fresh splices produce zero junk.** `CNT_A1_CAND=7776` is *exactly*
  three times `CNT_A1_TRAIN=2592`, and `CNT_A1_REJECT=0` — every candidate
  belonged to a complete train; no spurious candidates at all. The
  splice-junk phenomenology of rounds 12–13 and the codex rounds was
  substantially an old-disk artifact. (Consequence: an aging DD disk is
  *valuable* as a stress medium — if another old disk turns up, keep it
  for availability testing.)
- `CNT_CHANGE=0` with the latch clear confirms the section-8C semantics on
  a compliant no-eject dump, and `HEAD=0x0127` shows the estimate anchored
  and valid at 39 (the restore in the 104-step sequence anchored it — the
  old "head_valid never anchors" cosmetic is gone in this flow).

**Design cautions for the ready repair** (the resume shortcut —
`rotation_confirmed` and no disk change since → one index edge suffices —
is the right shape; codex's emulator already models it):

1. Eject safety rests on two invariants: a mechanical eject *always*
   asserts `/DSKCHG`, and index staleness must clear `rotation_confirmed`
   *once the current motor-on interval has produced an index edge*. Before
   the first edge, spindle acceleration can legitimately exceed the
   staleness deadline, so raw `/DSKCHG` alone is the authoritative eject
   signal there — this is safe because ready still requires a fresh edge,
   so a stalled disk keeps ready low no matter what history says. (A
   blanket "staleness always clears confirmation" rule is wrong: it was
   exactly the delayed-first-index `74` failure of 2026-07-18.)
2. Verify the budget arithmetic, not just the test: warm worst case =
   spin-up + one index edge and must land clearly inside the ROM's ~0.7 s
   window with the emulator's measured timings; the cold path (empirically
   fine in every cold session) should remain untouched.
3. Regression gates: the round-4 cold-start class, round-1's rule that
   ready must never gate Type-I commands, and the one-variable ROM proofs
   (`media_log`) codex added.

**Status 2026-07-18:** both repairs (change-qualified one-index resume +
physical Read Address `R=1..10` filter) shipped in `b13d99e` and the
rebuilt R3 **passed the exact formerly-failing A/B on hardware** — cold
directory, warm SHADES, and post-spin-down SHADES all clean (103 reads,
80 ID matches, zero error counters, trace arithmetic exact, far-cylinder
61/62 reads in the trace, no `R=11` reaching the ROM). An improvised
follow-up (directory → uncertain pause → `LOAD"C64ANABALT"`) then exposed
one residual PA1 corner: a motor restart whose *first* index edge arrives
after the 500 ms staleness deadline had its `rotation_confirmed` history
erased, defeating the one-index shortcut → `74` with zero physical
requests. Codex reproduced it as a red regression against the committed
RTL, applied the minimal guard (staleness invalidates history only after
the current motor interval has produced an edge; `idx_motor_cnt > 0`),
and re-greened the focused contract plus the genuine-ROM proof suite; the
long closed-loop bench and the wider suites run next. Pending after that:
maintainer commit, rebuild, and hardware qualification of (a) the exact
C64ANABALT pause sequence with varied pause lengths, (b) **eject/reinsert
— now the load-bearing test**, since the refined rule leans fully on
`/DSKCHG` authority before the first edge, (c) the disk-inserted-cold
JTAG case.
Testing continues on the new disk. What carries over unchanged: the new
disk is again F011-auto-formatted from the same image, so it has the same
content layout (directory at cylinder 39/40, SHADES at 61–62) *and* the
same F011 structures — TIB and the truncated 11th sector with its
CRC-valid `R=11` ID — so every open question and the codex test matrix
transfer 1:1. One caveat for interpreting results: fresh flux is stronger
and splices are clean, so marginal failures observed on the old
(aging) disk — e.g. the round-12 far-cylinder RNF rates — may reproduce
less often or not at all; a vanished symptom on the new disk is
media-dependence, not necessarily a fix. Record a healthy-rotation
baseline (`IDX_PERIOD` ≈ `0x0098xxxx`) on the first pre-flight for future
comparison.
