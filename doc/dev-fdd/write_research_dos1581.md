# 1581 DOS ROM 318045-02 at the WD1772 register interface: WRITE and FORMAT

Scope: what the stock 1581 DOS (ROM 318045-02, SHA-256 `8f6892…bfcb`, spec §2.3 l.188) does when it writes sectors, flushes its side cache and formats, as seen through the four WD1772 registers at `$6000`–`$6003`, so that the physical write engine can be designed against the real workload. Addresses are ROM addresses; cycle counts are 6502 cycles at 2 MHz (1 cycle = 0.5 µs); one DD MFM byte-time = 32 µs = 64 cycles.

Method: full disassembly of the ROM (`dis65.py`), then every claim re-executed on the genuine ROM in the project emulator (`doc/dev-fdd/rom_emu`) extended in the scratchpad with (a) an exact per-opcode 6502 cycle table (the stock emulator charges a flat 3 cycles per instruction and is therefore not timing-accurate), (b) a rotationally timed WD1772 model with Write Sector (datasheet sequence) and Write Track (index-to-index token consumption), write protect and error injection. Scripts: `work/dos1581/wmachine.py`, `probe_flush2.py`, `probe_format.py`, `probe_replace.py`, `probe_errors.py`, `probe_wp.py`, `probe_change.py` (run with `python3 -I`). The disassembly listings are in `work/dos1581/full.dis` and `r_*.dis`.

Sources used: book ch. 4 (l.555), 7 (l.780), 8 (l.833; transfer loop l.859, status epilogue l.868, LOST DATA bug l.892, readiness l.904), 12 (l.1121), 15 (l.1568), 18 (l.1738), C4 (l.2772); spec §2.3 (l.188), §5.7 (l.442), §10.1–10.3 (l.1260–1446), §10.6 (l.1539), §10.9 (l.1740), §10.10 (l.1799), §13.6 (l.2569), §14.6–14.10 (l.2757–2966), §15.3.1 (l.3128).

## 0. Register map, command bytes, and the two idioms every WD access uses

- `$6000` command/status, `$6001` track, `$6002` sector, `$6003` data. CIA at `$4000`: PA0 side select (0 = side 0), PA1 /READY, PA2 motor (0 = on), PA7 /DISK CHANGE, PB6 write-protect sense (0 = protected).
- Command bytes live in RAM, initialised at `$C2FF`–`$C342` (reset path): `$01DA`=`$08` Restore, `$01DB`=`$18` Seek, `$01DC`=`$28` Step, `$01DD`=`$48` Step-in, `$01DE`=`$68` Step-out (all h=1, V=0, r=00; `$C377` bumps r to 01 depending on a CIA probe at `$C36A`), `$01DF`=`$88` Read Sector, `$01E0`=`$AA` Write Sector, `$01E1`=`$C8` Read Address, `$01E2`=`$E8` Read Track (never used), `$01E3`=`$FA` Write Track, `$01E4`=`$D0` Force Interrupt (no interrupt condition). Nothing else ever writes a different command code; `$01E0`/`$01E3` are only modified in bit 1 by the precompensation routine `$CFE3` (see A).
- Command issue, `$CBF4`: `NOP; STA $6000; LDA #1; BIT $6000; BEQ` (loop until BUSY = 1, first sample 6 cycles after the write, period 7 cycles, no timeout), then `JMP $AD34` (26-cycle delay) and return. The DOS **will not proceed until it has seen BUSY high**.
- Wait for completion, `$CBEC`: `BIT $6000; BNE` until BUSY = 0, no timeout.
- Status evaluation, `$CD3F` (book l.868): `JSR $CBEC; PHP; LDA $6000; LSR; LSR; LSR; BCS $CD53; AND #$0B; TAX; PLP; LDA $CD5A,X; STA $7D`. The index is status bits 3 (CRC) → bit 0, 4 (RNF) → bit 1, 6 (WP) → bit 3; status bit 5 (write fault / record type) and bit 7 are **masked out and never seen**; status bit 2 (Lost Data) goes to carry and takes the `$CD53` path that skips the `PLP` (the stack bug: job code 9 is stored but the RTS misreturns, book l.892). Table `$CD5A`: `00 05 02 00 00 00 00 00 08 A5 26 30` → index 0 = OK, 1 (CRC) = job 5 (DOS 23), 2 (RNF) = job 2 (DOS 20), 3 (CRC+RNF) = **0 = success** (the hole), 8 (WP alone) = job 8 (DOS 26 WRITE PROTECT ON), 9/10/11 (WP with CRC and/or RNF) = `$A5`/`$26`/`$30`, garbage bytes of the following routine (`$A5` has bit 7 set and makes the DOS-level wait loop `$95A3` spin forever).
- All jobs run with interrupts disabled (`$C5AF: SEI; JMP ($0048)`), so nothing can lengthen the loops below.

## A. WRITE SECTOR as the DOS does it

Command byte `$AA` = `1010 1010`: Write Sector, m = 0 (single sector), h = 1 (no WD spin-up wait; the DOS runs the motor itself via CIA PA2 with its own 800 ms allowance, `$B095`), E = 0 (no 15 ms head-settle delay), P = bit 1 (see below), a0 = 0 (normal `FB` data mark). The DOS never sets m, E or a0 and never writes a deleted data mark.

P bit, routine `$CFE3` (entered with A = cylinder): `SEC; SBC $94; CMP #$2B; BCC clear` — `$94` is the constant 1, so for cylinder − 1 ≥ 43 it ORs `$02` into `$01E0` and `$01E3`, otherwise ANDs `$FD`. Result, confirmed by running the ROM: **cylinders 1–43 issue `$A8` (P = 0), cylinders 44–79 issue `$AA` (P = 1), and cylinder 0 issues `$AA` because 0 − 1 underflows to `$FF`**. Format uses the same routine (`$C3DB`): `$F8` on cylinders 1–43, `$FA` on 0 and 44–79. Per the WD1772 datasheet (and spec §14.9 l.2935) P = 0 *enables* precompensation, so the real 1581 precompensates the outer cylinders 1–43 and not the inner ones; this is inverted from the usual intent but it is what the hardware does. Decision point for the engine: honour P literally (bit-exact 1581) or ignore P and apply the MEGA65's own cylinder-based policy; both are harmless on DD media.

Register loading, write-back job entry `$C600` (the burst single-sector write `$C700` is the same loop without the cache; see F):

1. `$C600: JSR $CFA6` → Read Address `$CD00` (readiness check `$CDBC` first, then `$C8`, six bytes collected by the `$CD17` loop, status via `$CD3F`, then the software CRC check `$DA63` when `$8D` bit 6 is set, about 2.0–2.3 ms of CPU time). `$1F..$24` = C, H, R, N, CRC, CRC; `$27` = C (current cylinder), `$91` = N.
2. `$C603: LDA $95; CMP $1F` — the cached cylinder must equal the cylinder read from the disk, otherwise job error 2 (`$CB88`). `$C60C: STA $6001` — track register = cylinder. No seek is issued here; the job dispatcher already seeked (`$C135`/`$CE78`, seek `$18` with data register = target, then an 18.3 ms settle loop `$CBD5` with Y = `$98` = 18).
3. `$C60F: JSR $CFE3` (P bit), `$C612: JSR $CFB7` (buffer pointer `$4A/$4B` = `$8B/$8C` = `$0C00`, the side cache).
4. `$C615`–`$C643`: `$3A` = `$92` = 10 sectors to go; X = R from the Read Address; **sector register = R + 1, wrapping 10 → 1** (`$C639`–`$C643`); buffer page = `$0C` + 2 × (R − 1 + 1 …) via `$CB8D` so that the data pointer tracks the physical sector.
5. 20 × `NOP` (40 cycles = 20 µs) between the last register write and the command write.
6. `$C65A: LDA $01E0; JSR $CBF4` — command issued; the DOS waits for BUSY = 1.

DRQ service, the write transfer loop `$C667` (Y = page count 2):

```
$C667 LDA $6000 ; AND #$03 ; LSR A ; BCC done($C6CC) ; BEQ $C667   -- BUSY first, DRQ second, 13-cycle poll
$C671 STY $82 ; LDY #$00 ; LDA ($4A),Y ; STA $6003 ; LDY $82        -- one byte per DRQ
$C67C INC $4A ; BNE $C667 ; INC $4B ; DEY ; BNE $C667
$C685 JSR $CD3F ; BNE $C6CC ; DEC $3A ; BEQ $C6CC                    -- all 512 written: status, next sector
$C68E LDA $6002 ; INC $6002 ; 20xNOP ; CMP $93 ; BNE $C65A            -- sector := sector+1, re-issue $01E0
$C6AC LDA $8C ; STA $4B ; LDA $94 ; STA $6002 ; 20xNOP ; JMP $C65A    -- after sector 10: buffer base, sector 1
$C6CC JSR $CD3F ; BEQ $C6D4 ; JMP $CDCC ; $C6D4 JMP $C9E1             -- early BUSY drop: error or completion
```

- The first byte is **not** preloaded: the DOS waits in the poll loop and writes the data register only when DRQ appears. Measured first-DRQ-to-write latency 22–33 cycles (11–16.5 µs); the WD1772 window for the first byte is 9 byte-times (288 µs, spec §10.3 l.1429, §10.6 l.1550).
- Worst-case DRQ-to-data-write latency in the data phase: one missed 13-cycle poll plus 22 cycles from the status sample to the write = **35 cycles = 17.5 µs** (measured maximum 34 cycles, every sector). Per byte-time the loop needs 11 cycles (20 at the page crossing) to return to the poll. The read loop `$C969` is 30 cycles to the data read, the verify loop `$CA69` 45 cycles (22.5 µs, see C).
- Completion: the loop exits on the BUSY drop (`BCC`), never on DRQ count. After the 512th byte the DOS calls `$CD3F`, which itself waits for BUSY = 0 (the WD still writes CRC, CRC, `FF`). Status bits used: WP → job 8, RNF → job 2, CRC → job 5, CRC+RNF → success (hole), Lost Data → crash, bit 5 never (D).
- Between consecutive Write Sector commands the DOS needs **132–135 cycles = 66–68 µs** from BUSY drop to the next command write (190 cycles = 95 µs on the 10 → 1 wrap). There is no Read Address, no seek, no settle between the ten sectors; the next command simply expects the next ID on the disk (the following ID's CRC ends 56 byte-times = 1.8 ms after the previous write's `FF`).

## B. The write-back side cache and what a flush looks like

Facts (spec §15.3.1 l.3137–3152 confirmed): cache `$0C00`–`$1FFF`, one physical side = ten 512-byte records; dirty byte `$87` (`$80` dirty, `$00` clean); cached cylinder `$95` (`$80` = invalid); side `$97`; idle counter `$9C` reloaded from `$9D` (default `$20`) on every ATN at `$ABD0`, decremented every 10 ms controller tick at `$CE0B`. A write job (`$90`) on a cache hit only copies the 256-byte buffer into the cache and sets `$87` = `$80` (`$CF8A`–`$CF96`); no WD activity. Cache misses fill the side with ten Read Sectors (`$C900`, starting at R + 1 from a Read Address).

Three flush triggers, all ending in the same WD sequence:

1. Idle: main loop `$B151` sees `$9C` = 0 and `$87` ≠ 0 → `$B15B` → `$FF6C` → `$BFE3` ("dump track"): posts job `$A2` with track = `$95`, loads `$28` = `$30` AND `$3F` (retry count, `$30` defaults to 2 at `$B071`, `U0>Rn` sets it at `$AA2D`), waits.
2. Replacement: any job needing a different cylinder/side on a dirty cache reaches `$C11D` (dispatcher stage bit 2): if the head is not on `$95` it seeks there first (`$C140` → `$CE78`), selects side `$97` (`$CFC0`, CIA PA0) and jumps to `$C600`; afterwards the original job is re-dispatched (`$CDE2` → `$C0C7`).
3. The dump-track job `$A2` itself (idle path and `U0>` dump), same `$C11D` → `$C600`.

Measured sequence of one flush (cylinder 0, side 0, head already there, verify on):

```
RDADDR C8 (job stage $CFA6)      RDADDR C8 ($C600 own)        10 x WRSEC $AA/$A8, sectors R+1 .. R (wrap 10->1)
RDADDR C8 ($CA00 verify)         10 x RDSEC $88, sectors R'+1 .. R' (compare)      RDADDR C8 (re-dispatch of $A2)
```

Timing on a 300 rpm stock-layout disk: first command to last Write Sector BUSY drop 243 ms (one Read Address, ~2.3 ms of software CRC, then ten sequential writes: 35 ms for the first, 19.4 ms each (one sector pitch = 609 byte-times) and 24.5 ms across the index); flush including verify and the final Read Address 495 ms. The ten writes are issued back-to-back with 66–95 µs gaps; the whole side is always rewritten even if one 256-byte block changed.

Completion path `$C9E1`: `BIT $8D; BPL no-verify; JSR $CBDC` (3308-cycle = 1.65 ms delay), `JSR $CA00` (verify), `ASL $87` (clean), `JMP $CDE2`. Without verify: the same 1.65 ms delay, then `ASL $87`.

Verify job `$CA00`: Read Address again (cylinder must match, else job 2), sector = R + 1 wrapping, ten Read Sectors with the `$CA69` loop comparing every byte against the cache (`CMP $6003`; when the fill byte `$9B` ≠ `$F5` it compares against `$9B` instead, format mode). A mismatch leaves the Read Sector running: `$CADC: JSR $CFD1` → **Force Interrupt `$D0`** written directly to `$6000`, 251 cycles (126 µs) of delay, wait for BUSY = 0, then job error 7 (DOS 25 WRITE ERROR). Any WD error status during the verify goes through `$CD3F` as usual (CRC → 5, RNF → 2). Force Interrupt is issued by the DOS only here and at power-up (`$C367`); never during a Write Sector or Write Track.

Verify flag: `$8D` bit 7 (default `$C0` at `$B093`, bit 6 = check Read Address CRC in software). It is **stored in the BAM** (track 40 sector 1 byte 6, written by `$B484`) and reloaded from the disk at every initialise (`$8F6F`); `U0>V0/1` (`$AA9A`) changes it until the next initialise; a BAM with byte 6 = `$00` (foreign formatter) silently turns verify and the header CRC check off.

Retry of a failed flush, `$BFFE`–`$C00A`: on job code ≥ 2 the controller has already cleared `$87` and set `$95` = `$80` (`$CDCC`–`$CDDB`); the DOS re-dirties (`$C019: LDA #$80; STA $87`), restores `$95` and re-posts `$A2`, `$28` times → **3 attempts in total, no Restore/bump in between, every attempt rewrites and re-verifies all ten sectors from a fresh Read Address** (measured: RNF on one sector → 3 × (RDADDR, RDADDR, WRSEC…) then DOS error and a re-read of the directory track). After the last failure the cached side is gone: the user's SAVE had already been acknowledged.

## C. FORMAT

Entry: `N:` → `$8746`: `$B0CF` re-initialises the geometry constants (`$75` = 40, `$91` = 2, `$92/$93` = 10, `$94` = 1, `$9B` = `$F5`, `$9A` = `$23` = 35), posts job `$C0` (Restore `$08`, `$CB0F`, then an 18.3 ms settle), sets the fill byte `$9B` = 0, posts job `$F0` (format all, `$CB35`), restores `$9B`. Job `$F0` dispatcher stages: logical translation, motor, readiness, seek to the job cylinder (`$01BC,Y`); no Read Address, no cache flush (a dirty cache is simply abandoned).

`$CB35` per cylinder: for side 0 and 1: select side (`$CFC0`), buffer pointer, `$C3D6` (Write Track), `$CD3F` (status), 1.65 ms delay, verify `$CA00`; after side 1: if `$88` ≠ `$8F` (last cylinder, 79) then `$01BC,Y` += 1 and re-dispatch (seek one cylinder, 18.3 ms settle plus up to one 10 ms tick), else job code 1 (done). Measured gaps: verify of side 0 → Write Track of side 1: **~150 µs after the last Read Sector's BUSY drop, including the side switch**; seek completion → Write Track: 20.8 ms.

`$C3D6`: `LDA $88; STA $6001` (track register = cylinder), `JSR $CFE3` (P bit), `$39` = 1 (first sector), `$3A` = 10, `LDA $01E3; JSR $CBF4` (Write Track `$F8`/`$FA`, h = 1, E = 0). The DOS does **not** wait for the index; it loads the first token as soon as DRQ appears (measured 19 cycles after DRQ; it reaches the token loop ~30 cycles after seeing BUSY) and then keeps feeding tokens at the DRQ pace. Token stream, confirmed token-for-token in the emulator (spec §14.7 l.2810–2838):

```
32 x 4E                                                      ($C3EC, LDX #$20)
repeat 10 x (R = 1..10):
   12 x 00 ; 3 x F5 ; FE ; C (= $6001) ; H (= $96) ; R (= $39) ; N (= $91 = 2) ; F7
   22 x 4E ; 12 x 00 ; 3 x F5 ; FB ; 512 x data ; F7 ; 35 x 4E   (gap3 = $9A = $23)
then 4E forever ($C52D) until BUSY drops
```

Data bytes: `$C4E5: LDA $9B; CMP #$F5; BNE` → when `$9B` ≠ `$F5` the constant `$9B` is written (stock NEW: `$00`), otherwise bytes come from the cache buffer `($4A),Y`. Magnetic length 32 + 10 × 609 = 6122 byte-times = 195.9 ms; the last data CRC ends at byte-time 6087; the DOS feeds `4E` until the WD ends the command at the next index (6230 host tokens for a 6250-byte-time revolution, 20 of them `F7` counting double). If the index comes early the BCC chain falls through to `$C544` (carry clear) and the DOS treats the track as written; the verify then catches a truncated last sector.

Worst-case DRQ-to-token-write latency (one missed 13-cycle poll plus the service path): constant tokens 27 cycles, ID bytes 28–29 cycles, data bytes **33 cycles = 16.5 µs** in fill mode (stock NEW), **45 cycles = 22.5 µs** in buffer mode (`$9B` = `$F5`), measured maximum 32 cycles in fill mode. After an `F7` the next DRQ is two byte-times away.

After Write Track completes: `$CD3F` (WP → 8, Lost Data → crash, RNF/CRC impossible on a real chip), 1.65 ms delay, then the verify pass of B (Read Address, ten Read Sectors compared against `$9B` = 0, mismatch → Force Interrupt + job 7). **There is no retry anywhere in the format path**: any status error or verify mismatch ends job `$F0` (`$CB65` → `$CDCC`), `$8766` reports the DOS error and the disk stays half formatted.

Geometry and time: 80 cylinders × 2 sides, 160 Write Tracks and 160 verify passes, plus the Restore and the BAM/directory writes afterwards (`$B3F0`–`$B432`, through the normal cache path). Per side: index wait 0–200 ms (mean 100) + 200 ms write + 2 ms + ~240 ms verify (Read Address lands on sector 2, reads 3…10, then 1 and 2 on the next revolution); per cylinder ≈ 2 × 540 ms + ~30 ms seek/settle/tick ≈ 1.1 s; whole disk ≈ 73 s (all index waits short) to ≈ 105 s (all long), **typically ~90 s on a real 1581**.

Burst-mode format (`U0` format command, `$BD7C`–`$BDE4`) uses the same `$F0` job but can change the parameters: last cylinder `$8F`, first track `$90`, sectors per track `$92` (table `$BD06`: N = 1 → 16, N = 2 → 10, N = 3 → 5), sector size code `$91`, fill byte `$9B` (default `$E5`), and gap3 `$9A` from table `$BDF8` (N = 1 → 22, N = 2 → **38**, N = 3 → 68). So a burst-formatted 10 × 512 track is 32 + 10 × 612 = 6152 byte-times (98 byte-times of index margin at nominal speed), N = 3 tracks carry five 1024-byte records, and a fill byte of `$F5` selects buffer mode (22.5 µs worst case). `N_format_required_max` (spec §14.7) must cover these variants or reject them.

## D. Error handling that matters for the hardware writer

Write protect has three layers:

1. At initialise (`$8EDC`), job `$B6` (`$CB76`) reads **CIA PB6** and returns job 8 if protected; the result is stored in `$01FA`. Every later write job on a cache hit checks `$01FA` first (`$CF8A`) and returns job 8 (DOS 26) **without any WD write and without dirtying the cache** (the cache fill reads still happen). The DOS never re-samples PB6 later.
2. WD status bit 6 after Write Sector / Write Track → `$CD5A` index 8 → job 8. Measured with the tab flipped after login: the flush issues Read Address, Read Address, Write Sector → WP, three times (DOS retry), then `26, WRITE PROTECT ON`, the cache is dropped and the directory track is re-read. A format on a protected disk fails at the first Write Track with job 8.
3. Mid-write protection is invisible to the DOS: nothing samples PB6 or status during the data loop; the hardware's asynchronous clamp (spec §13.6) decides, and the resulting status is evaluated only when BUSY drops. Report WP **alone**: WP with CRC or RNF indexes `$CD63`–`$CD65` (job codes `$A5`/`$26`/`$30`; `$A5` hangs the DOS-level wait loop because bit 7 means "job pending").

Lost Data (status bit 2) on any Type II/III completion sends the ROM through the `$CD49`/`$CD53` misreturn: no retry, wild execution, drive RAM corruption (book l.892, emulator proofs P-D1/P-D3). Write-side deadlines the DOS actually meets: first Write Sector byte within 35 cycles of DRQ (limit 288 µs), data bytes within 35 cycles (17.5 µs), Write Track first token within ~65 cycles (limit 96 µs), format tokens within 33 cycles fill mode / 45 cycles buffer mode. The hardware must only ever raise Lost Data for a genuine miss of the real-chip deadline (data register not loaded when the next byte starts serialising), never for a shortened internal deadline.

Write Fault (status bit 5) is masked by `AND #$0B`: the DOS cannot see it. A hardware fault during a write must therefore be surfaced as RNF (job 2 → retried three times, then DOS 20) or CRC (job 5 → DOS 23) if the DOS is to react at all; with verify on, a damaged sector is in any case caught by the read-back compare (job 7).

RNF on a Write Sector (no matching ID within the search budget, pending disk change, unsafe timing per spec §10.2) → job 2 → cache dropped, DOS retries the whole side three times from a fresh Read Address; each retry re-dirties the cache (`$C019`). The DOS never issues Force Interrupt against a write and never times out: a Write Sector that silently never completes hangs the drive.

Disk change (CIA PA7): sampled only in the readiness stage before a job (`$CD7B`: `$CD8A` steps in and out with `$48`/`$68`, no track update, to clear the mechanism latch, then error 3 = DOS 74 if still asserted) and in the idle tick `$CE39` (drops the dirty cache: `$87` = 0, `$95` = `$80`, `$25` = 1). **During a flush PA7 is never looked at**: measured, with PA7 asserted after the first Write Sector the DOS wrote all ten sectors and verified them; the hardware is the only guard. Note the retry interaction: if the hardware aborts the flush with RNF because of a pending change, the DOS re-dirties and retries; once the readiness stage's step pair clears the change latch on a newly inserted disk, the stale side **is written onto the new disk** (same cylinder, same R values) — real 1581 behaviour, not preventable below the DOS.

Lower-level status rules that follow: (1) never CRC+RNF together on a write (index 3 = success → `ASL $87` marks the lost data clean); (2) status bit 5 must be 0 on write completions (masked anyway); (3) after Force Interrupt during the verify the DOS waits 126 µs then polls BUSY = 0 and later issues a new command tens of ms later; (4) BUSY must be visibly high for every command, including immediate WP/not-ready terminations: with BUSY high for only 4 cycles the ROM hung forever in `$CBFA` (measured; 7-cycle poll). Hold BUSY ≥ one byte-time on any immediate termination (the book's 1.5 ms Type-I minimum, l.1621, is the same idea).

## E. Timing facts the hardware must respect

WD1772 Write Sector (spec §10.6 steps 1–7, §14.8): find matching ID with valid CRC → DRQ 2 byte-times after the ID CRC → DR must be loaded by 11 byte-times (else Lost Data, no write) → WGATE at 22 byte-times → 12 × `00`, 3 × `A1`, `FB` (16 byte-times, byte 0 moves DR→DSR at the end and DRQ for byte 1) → 512 data byte-times (DRQ each) → CRC, CRC, `FF` → WGATE off, BUSY off, INTRQ. 531 byte-times = 16.99 ms of WGATE per sector; command-to-BUSY-drop = ID wait + 553 byte-times (17.7 ms). Write Track: DRQ at acceptance, first token within 3 byte-times (96 µs) else Lost Data; WGATE from the next index leading edge to the following one, one token per byte-time (`F7` = two), `00` written and Lost Data set on a missed token without aborting.

DOS tolerances, measured on the genuine ROM:

- No BUSY timeout anywhere (`$CBEC`, `$C667`, `$C3EE`…). A Write Sector that costs an extra revolution is simply waited for: with sector 4 delayed by one revolution the flush took 691 ms instead of 495 ms and succeeded. A design that writes on the *next* occurrence of the ID (second-pass splice, spec §10.6 step 4) therefore works functionally, but turns the 10-sector burst from ~220 ms into ~10 revolutions (≥ 2 s) plus verify, during which the C64 is held on the IEC bus (jobs run with SEI).
- Re-arm time between Write Sectors is 66–95 µs after BUSY drop; the next ID's sync (12 × `00`) starts 34 byte-times = 1.09 ms after the previous `FF`, its CRC ends 1.8 ms after. A post-write guard of 700 µs (spec §10.6 step 8) still leaves ~390 µs to be searching before the next sync; anything longer costs a full revolution per sector.
- Read Address → first Write Sector: 2.0–2.3 ms (software CRC); Write Track → Read Address: 1.98 ms; last Write Sector → verify Read Address: 1.98 ms; Read Address → first verify Read Sector: 2.2 ms. Freshly written sectors are read back within ~2 ms (verify) and the next revolution.
- Side select → Write Track command: ~100 µs (`$CB39`–`$C3E9`); side select → Read Address: a few µs plus the readiness check. The DOS relies on the index wait (0–200 ms) for side settle; the engine must enforce its own side-settle before arming the index.
- Seek → Write Track / Write Sector: ≥ 18.3 ms settle in the DOS (`$CBD5`), plus up to a 10 ms tick.
- Between a register write and the command write the DOS leaves ≥ 20 µs (`NOP` block); after a Force Interrupt ≥ 126 µs before polling and much longer before the next command (spec §10.10's 16 µs rule is met).
- Index-period margin for the stock stream: 6250 − 6122 = 128 byte-times (4.1 ms, 2.0 %); the burst format's 38-byte gap3 leaves 98 byte-times (1.6 %). A fast revolution that ends before the stock record 10 is complete is not detected by the DOS until the verify fails.

## F. What a naive implementation would break

1. **Sector order and wrap.** Writes start at (Read Address R) + 1 and wrap 10 → 1 inside one command burst; the ten commands arrive 66–95 µs apart with no Read Address between them. A controller that needs a fresh index or a seek-settle per command, or that cannot accept a command within ~60 µs of BUSY drop, adds a revolution per sector.
2. **The Read Address side effect.** `$C603` compares the cached cylinder with the C byte of the Read Address and the `$CD00` epilogue relies on the sector register being replaced by C (book l.634); after Read Address the DOS rewrites `$6002` itself before the write.
3. **BUSY must be observed.** `$CBF4` loops until BUSY = 1 (7-cycle period). Immediate terminations (write protect, not ready, unsafe timing) must keep BUSY up long enough; 4 cycles hung the ROM.
4. **Status purity.** Only bits 6, 4, 3 (and the fatal bit 2) are decoded. Never CRC+RNF (hole → success → cache marked clean, data lost), never WP together with CRC/RNF (garbage job codes, one of them a permanent hang), never Lost Data unless the DOS truly missed the real-chip deadline, bit 5 is ignored.
5. **Deadlines.** DOS worst cases: 17.5 µs per data byte on Write Sector, 16.5 µs (fill) / 22.5 µs (buffer mode) per format token. The spec's 23.5 µs test deadline (§10.3 l.1421) leaves 2 CPU cycles over the buffer-mode formatter; implement the true DR-capture-at-serialisation deadline (≈ one byte-time) instead of a shortened one.
6. **Whole-side rewrites.** One changed 256-byte block → ten Write Sectors plus ten Read Sectors; a retry → everything again, three times; a verify mismatch on sector k → Force Interrupt mid-Read-Sector, then everything again.
7. **Idle flush timing is not a promise.** Default 320 ms after the last ATN (`$9D` = 32 ticks); `U0>I` sets anything 0–255 (`$AA36`), `U0>R` the retry count (`$30`, `$AA2D`, default 2 → 3 attempts), `U0>V` verify. Motor stays on ~10 s after the last job (`$CDE4`: 255 × 4 ticks), so a flush normally finds the motor running and `$CD63` skips spin-up; after a longer idle the flush begins with the 800 ms spin-up allowance and the one-shot readiness exam (`$CDBC`, 30 reads of PA1).
8. **Verify can be off per disk.** BAM byte 6 of a foreign-formatted disk may be `$00`; then no read-back happens and a silently failed write (hole, wrong sector, truncated data) is never noticed by the DOS. The engine must not rely on the verify pass as its safety net.
9. **Format has no error tolerance** and never retries; one RNF/CRC/mismatch anywhere in 160 tracks aborts `N:` with the disk half done. The Write Track command is issued ~100 µs after the side switch and the DOS keeps feeding `4E` until the index ends the command; a model that ends after a fixed token count, or that starts WGATE before a qualified index, writes a different track than a 1581.
10. **Two Write Sector issuers.** `$C65A` (cache write-back) and `$C733` (burst single-sector write `$A6`: Read Address, track/sector from the job, buffer `$0300`, no verify, no cache flush, one command). Burst reads/writes bypass the side cache entirely; a dirty cache can later overwrite a burst-written sector (real 1581 behaviour).
11. **Disk swap during a dirty cache** is handled only by the hardware's pending-change latch; the DOS will retry a failed flush onto whatever disk is present once the change latch clears (see D).
12. **P bit** is set on cylinder 0 and 44–79, clear on 1–43 (inverted from the common intent, with the cylinder-0 underflow). Decide explicitly whether to honour it.
13. **Command byte variants** the engine will see: `$A8`/`$AA` (Write Sector), `$F8`/`$FA` (Write Track), `$88` (Read Sector), `$C8` (Read Address), `$D0` (Force Interrupt), `$08`/`$18`/`$48`/`$68` (Type I, h = 1, with r possibly incremented to 01). No m, E, a0, V or spin-up-wait bits are ever set.

## Appendix: ROM address index used above

`$C2FF`–`$C342` command-byte init · `$C343` register self-test · `$C367` boot Force Interrupt · `$C3BB`/`$C3D6` single-track format job and Write Track routine · `$C3EC`–`$C545` token stream loops · `$C600`–`$C6D4` write-back (ten Write Sectors) · `$C700` burst write · `$C800` burst read · `$C900` cache fill · `$C969` read loop · `$C9E1`–`$C9F3` completion/verify/`ASL $87` · `$CA00`–`$CAE1` verify job, `$CADC` Force Interrupt on mismatch · `$CB0F` Restore job · `$CB35`–`$CB73` format-all · `$CB76` CIA write-protect job · `$CB8D` buffer page · `$CBD5`/`$CBDC`/`$CBDF` delay loops · `$CBEC` wait not busy · `$CBF4` command issue · `$CD00` Read Address, `$CD17` reply loop, `$CDBC` readiness · `$CD3F`/`$CD5A` status epilogue and table · `$CD63` motor on, `$CD7B`/`$CD8A` readiness and change-latch clearing · `$CDCC`–`$CDFD` job error exit (cache drop) · `$CE0B` idle countdown · `$CE39` disk change drops cache · `$CE78` seek stage · `$CF8A`–`$CF96` cache-hit write (dirty set, `$01FA` check) · `$CFA6` Read Address wrapper · `$CFC0` side select · `$CFD1` Force Interrupt helper · `$CFE3` P bit · `$DA63` Read Address software CRC · `$8746` NEW → jobs `$C0`, `$F0` · `$8EDC` initialise (job `$B6` → `$01FA`) · `$8F6F` verify flag from BAM · `$9564`–`$9583` generic job retry (bump via job `$C0` when `$30` bit 7 clear) · `$959D` post-and-wait · `$AA2D`/`$AA36`/`$AA9A` `U0>R`/`I`/`V` · `$ABD0` ATN reload of `$9C` · `$B071` retry default · `$B093` verify default · `$B0CF` geometry constants (gap3 35) · `$B151`/`$B15B` idle flush · `$BD7C` burst format parameters · `$BFE3`–`$C023` dump-track with retry · `$B484` verify flag into BAM.
