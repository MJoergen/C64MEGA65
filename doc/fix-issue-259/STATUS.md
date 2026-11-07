# Issue #259: genuine Commodore REU (MOS 8726) fails while the VIC-II steals cycles

Running record of the investigation. Read this before touching `reu1764` again.

**Resume checklist for the next session, once Joe3f00ff has posted his round-4 results:**

1. Read this file completely, then `PROTOCOL-round4.md` (what he was asked to run) and section 7c
   (what each outcome means). Section 6c holds the root cause as established after round 3; do not
   re-derive sections 6, 6b and 6c.
2. Fetch the new issue comments and photos (`gh issue view 259 --repo MJoergen/C64MEGA65 --json comments`;
   images are `github.com/user-attachments/assets/<id>`, downloadable with `curl -H "Authorization: Bearer $(gh auth token)"`).
3. Fill in the round-4 results and map every outcome with section 7c. All zero on A24X1 closes the
   issue (then: Kugelblitz360's DMA-cartridge regression, merge into `develop`, community build).
   Faults left on A24X1: `14-ffff` on A24 and on A24X1 says whether the REC drives its address
   during the held reads (section 7c); then section 8 (ILA or logic analyzer) is the next step.
Do not launch VICE on this machine (windows pop up); the VICE command-line tools `petcat` and
`c1541` in `/Applications/Vice/bin` are fine, `tests/round3/build.sh` and `tests/round4/build.sh`
use them. Everything marked *verified* was checked against code, disassembly or the official
documents named below; everything else is marked as a hypothesis.

Branch state: `reu1764` = WIP-V6-A24X1. A23 = commits 2ce5e53, 1213bed, 94b496f; A24 = ade48e6
(read grace, superseded) and 39d75f3 (bump); A24X1 = cff5e95 (three grace cycles for reads in
`CORE/vhdl/main.vhd`, bench scenarios in `CORE/vhdl/test/tb_cartport/gen_tb.py`), 791e457 (bump)
and dbcd348 (this record, `PROTOCOL-round4.md`, `tests/round4/`), all of 2026-11-07;
submodule `CORE/C64_MiSTerMEGA65` @ 98492d1, unchanged. A23 was tested by Joe3f00ff on 2026-11-03
(CMD test and round 2): it fixed the lost fetch bytes and nothing else. A24 was built by sy2002 on
2026-11-05 from 4074da1 and tested by Joe3f00ff on 2026-11-06 (`3-verify`, `9-values`, CMD): **it
changed nothing against A23** (section 1c). A24X1 is the fix derived from round 3 (sections 6c and
9); **it has not been synthesized or run on hardware yet**: sy2002 builds it (Vivado in the Ubuntu
VM), then Joe3f00ff runs `PROTOCOL-round4.md`. A24 and A24X1 go to Joe only, not to the community.
Do not merge `reu1764` into `develop` before round 4 is clean.

Folder contents:

- `tests/reu-tests.d64` and `tests/*.bas` / `*.prg`: the seven round-2 BASIC experiments (section 7).
- `tests/round3/`: the round-3 programs (section 7b): three BASIC programs, two machine-code programs
  (ca65 sources, each glued behind its BASIC driver at `$0A00`), `build.sh` (petcat, ca65/ld65, c1541)
  producing `reu-tests3.d64` / `reu-tests3.zip`, and `validate.py` (py65 smoke test with a stubbed REC
  and VIC; it checks control flow and bookkeeping, not hardware semantics).
- `decoded/cmd-reutest-ml-3000.dis`: disassembly of the CMD 1750/1750XL REUTEST machine code
  (loaded at `$3000`; the PRG is file `REUTEST` on `CMD-1750XL.d64`, download:
  `https://www.zimmers.net/anonftp/pub/cbm/demodisks/cmd/CMD-1750XL.d64.gz`).
- `decoded/cmd-reutest-basic.bas`: the BASIC part of REUTEST (petcat listing). Lines 190-196 are the
  Bit Fill loop: `FOR I=0 TO 255 STEP 17: POKE SB,I: SYS ML+15`, i.e. 16 patterns, no display switching.
- `decoded/vice-reu.c`: VICE `reu.c` (full file; the BA functions are also excerpted below).
- `decoded/turbo-reu-tester-0900.dis`, `turbo-reu-tester-09c0.dis`: the unpacked Turbo REU Tester
  1.2 (CSDb 109935, `reutest.d64`, crunched; unpacked with py65 by running its depacker).
- `decoded/vice-reu-c-ba-functions.txt`: the VICE x64sc BA handling of the REU (`reu.c`) and the
  `vicii_cycle_reu` / `vicii_steal_cycles` callbacks.
- `decoded/dis6502.py`: the disassembler used (`dis6502.py <file> <offset> <org> <len>`).
- `PROTOCOL-for-Joe.md`, `PROTOCOL-round3.md`, `PROTOCOL-round4.md`: the test protocols of rounds 2,
  3 and 4, as pasted into the GitHub issue (round 4: to be pasted together with the A24X1 build).
- `tests/round4/`: `13-swapchk.bas` (swap integrity with the display on, byte by byte) and
  `14-ffff.s` + `.bas` (verify with the KERNAL banked out and a chosen byte at `$FFFF`: tells a
  floating data bus from a floating address bus), `build.sh` producing `reu-tests4.d64` / `.zip`,
  `validate.py` (py65 smoke test of the machine code).

Reference documents (public):

- Commodore service schematics 1750/1764, schematic 312534 rev 3 with the 8726 pin
  description: `https://bio.nic.funet.fi/pub/cbm/schematics/misc/1750_1764_Service_Schematics.pdf`
- Wolfgang Moser, CSG 8726R1 Technical Reference 1.0 (register behavior, half-autoload bug,
  I/O-area DMA unreliability, SWAP speculation):
  `https://github.com/mist-devel/mist-binaries/files/5684202/CSG8726R1-TechnicalReference-1.0.pdf`
- VICE `vice/src/c64/cart/reu.c` and `vice/src/viciisc/vicii-cycle.c` (GitHub mirror VICE-Team/svn-mirror).

## 1. Result matrix (Joe3f00ff, MEGA65 R6A, display on unless noted)

| CMD phase | A: A22 Oct 25 | C: A22 Oct 26 | E: A23 Nov 3 | F: A23 Nov 3 (line 181 patched) |
|---|---|---|---|---|
| Buffer Memory (CPU only) | OK | OK | OK | OK |
| Block/Page Addressing | err 1 | OK | err 1 | err 1 |
| Byte Addressing | err 1, page 0 | err 1, page 12 | err 1, page 2 | err 1, page 2 |
| Interrupt Register | OK | OK | OK | OK |
| Address Control | OK | err 4 | err 3 | err 1 |
| `$FF00` Option | err 1 | OK | OK | OK |
| CBR Refresh a / b | err a | err a | err a | err a, err b |
| Bit Fill | OK | OK | OK | OK |

Display off (`55 POKE 53265,11`): run B (A22, Oct 25) all OK except Interrupt Register err 1
(one-off, unexplained); run D (A22, Oct 26) all OK including the 10 s refresh check. Turbo REU
Tester 1.2 on A22, display on: left its size-detection loop (it must loop forever on a 512 KB
REU), then printed OK for 20+ banks. Real C64 with the same REU (Gross test program): OK.
Regression evidence for the A23 port changes (Kugelblitz360, 2026-11-04, issue comment
6636575530): TeensyROM+ in NTSC and PAL runs 1 MB EasyFlash images with bank switching and BA
halt, its internal REU, its Expansion Port test and the Gameboy and Doom virtual machines exactly
as on A22; Kung Fu Flash 2 did not work before and does not work now. One data point, but a
fully-fledged DMA cartridge with no side effect from the dot clock, the BA recharge and the
write grace. It says nothing about the A24 read grace, which drives read data in the first
BA-low cycle after a cartridge read; a TeensyROM+ run on A24 would close that gap.

Round 2 (2026-11-03, the seven BASIC programs of section 7, simulated REU off, JiffyDOS, HDMI 720p,
photos in `REU-Test-Results_A22-A23.pdf` attached to the issue):

| Program | Core | Result |
|---|---|---|
| `1-fetch` | A23 | 20 runs OK, 0 bad bytes |
| `1-fetch` | A22 | runs 1, 3, 4, 10, 13, 14, 19, 20 each lose exactly one byte (positions 64, 84, 71, 64, 120, 160, 188, 221, value 255 = never written); 8 bad bytes |
| `2-stash` | A23 | 20 runs OK, 0 bad bytes |
| `3-verify` | A23 | 256 B 0..255: 34 faults in 100; 256 B `$AA`: 34 in 100; 4 KB 0..255: 22 in 25; 64 KB fixed-C64 `$AA`: 10 in 10; 16 KB fixed-C64 `$AA`: 25 in 25; no "(fault w/ display off!)" |
| `3-verify` | A22 | 33, 33, 21 in 25, 10 in 10, 25 in 25 (identical within noise) |
| `4-long` | A23 | m1 (on/on) and m2 (off/on): 256 B ok ok ok, 4 KB / 16 KB / 32 KB / 64 KB fault fault fault; m3 (stash on, verify off): all ok; RAM canary `$5000-$7FFF` ok |
| `5-sprites` | A23 | without sprites: 5 faults in 5; with 8 sprites: 5 in 5 |
| `6-idle` | A23 | wait on / verify off: ok; wait off / verify on: fault; on / on: fault; off / off: ok |
| `7-chain` | A23 | chains A, B, C: 5 faults in 5 each |

The verify fault rates equal the probability that a transfer of that length overlaps a badline
(PAL: 25 badlines per frame, 504 cycles apart; a 256-cycle window hits one with probability
`(200*63*256/504 + 256) / (312*63)` = 0.34, a 4096-cycle window with 0.82): **every interrupted verify
faults**, whatever the data, on A22 and A23 alike.

## 1c. Round 3 (2026-11-06, Joe3f00ff, issue comment 6686590417, `A23-Tests.pdf` and `A24-Tests.pdf`)

All on A23 with the display on unless noted (the programs of section 7b):

| Program | Result |
|---|---|
| `8-swap` | before: FAULT FAULT FAULT; after 1-byte fetch, after 1-byte swap, after re-stash, after 256-byte swap with the display off, after 16 KB swap with the display on plus re-stash: FAULT FAULT FAULT each. A swap changes nothing |
| `9-values` | faults in 50: `$FF` 0, `$00` 20, `$AA` 15, `$55` 17, `$FE` 18, `$7F` 16, `$0F` 16, `$F0` 16 |
| `10-after` | 7 faults in 20 (runs 3, 5, 7, 8, 10, 19 visible: fault at byte 39, 3, 119, 248, 88, 82 with remaining length `255 - byte`, status 48), `REU DATA INTACT` after every one, 0 wrong REU bytes; control with byte 100 changed and the display off: `ST 48 FAULT AT BYTE 100` |
| `11-bitfill` | variants 0 (exact chain), 1 (no swap), 2 (no sprites), 3 (CLI), 4 (no `$FF00`), 5 (no fetch), 7 (stash, fixed-REU verify, verify), 8 (planted error) and 9 (planted error, display off): `R 4 C 4 CPU 0 1ST 1`; variant 6 (stash plus fixed-C64 verify): `R 0 C 4 CPU 0 1ST 2` |
| `12-position` | line 50 (badline at 51), 10 runs: `ST 48 BYTE 49 LEN 206 CYC 113 END 51` every time, display-off status 80; line 52 (control), 10 runs: `ST 80 BYTE 255 LEN 1 CYC 275 END 56` every time |

On A24 (the read grace of section 9, first BA-low cycle served), display on:

| Program | Result |
|---|---|
| `3-verify` | 256 B 0..255: 29 faults in 100; 256 B `$AA`: 36 in 100; 4 KB: 22 in 25; 64 KB fixed-C64 `$AA`: 10 in 10; 16 KB fixed-C64: 25 in 25 (A23: 34, 34, 22, 10, 25) |
| `9-values` | faults in 50: `$FF` 0, `$00` 18, `$AA` 16, `$55` 16, `$FE` 18, `$7F` 19, `$0F` 17, `$F0` 11 |
| CMD REUTEST | Buffer Memory OK, Block/Page OK, Byte Addressing err 1 (page 8), Interrupt OK, Address Control err 3, `$FF00` OK, CBR err a, Bit Fill `(00) ... (ff) : OK`; stopwatch for the Bit Fill line: **about 6 s** (64 s if all transfers ran) |

Kugelblitz360 on A24 (2026-11-05): TeensyROM+ and EasyFlash testing without regressions; Kernal
replacement (EasyFlash 3, TeensyROM) did not work before and does not work now; KFF2 unchanged.

## 2. What the test programs really do (verified by disassembly)

All CMD transfers use command values `$B0..$B3` (execute, autoload, immediate; stash, fetch,
swap, verify). The C64 buffer is `$5000..$8FFF`. `SB` = `$FA` = result, `$FB` = bank count (8).

| Phase (SYS ML+n) | Operation | Result codes |
|---|---|---|
| +3 size | 1-byte stash of the bank number to bank 2,4,6,8,... from `$5000`, fetch from bank 0; the wrap at bank 8 gives 512K | capacity |
| +6 Buffer Memory | CPU-only test of `$5000..$8FFF` (address pattern, 0..255 per page, `$55`/`$AA`) | 1, 2, 3, 4 |
| +9 Block/Page | 2048 two-byte stashes of (page, bank) from `$5000/$5001` to each page start of all 8 banks, then 2048 two-byte verifies | 1 = verify FAULT |
| +12 Byte Addressing | 2048 page stashes of the pattern 0..255 (whole REU), then 256 page verifies of **bank 0 only** (`$FC` is never reset, CMD bug), then 256 one-byte verifies | 1 = page verify FAULT, 2 = byte verify FAULT; printed numbers: `$FC` (always 8) and `$DF05` = page |
| +18 Interrupt | 1-byte stash with `$DF09 = $C0`, ISR reads `$DF00`, loop of 256 waits for bits `$C0` | 1 timeout, 2 wrong flags |
| +21 Address Control | 1: stash 256 x `$AA` then verify; 2: fixed-C64 stash of `$00`, fetch, CPU check; 3: stash (`$AA`,0,...,0) then verify; 4: fixed-REU fetch of 256 x `$AA`, CPU check | 1..4 = failing part |
| +24 `$FF00` Option | 256 one-byte stashes triggered by writes to `$FF00` with all RAM mapped (source `$ii80`, value i), then a 256-byte fetch to `$5000` checked by the CPU | 1 |
| +27 / +30 CBR Refresh | a: per bank: fixed-C64 stash of `$AA` (64 KB, length register 0) then fixed-C64 verify of 64 KB; b: the same verify again after 10 s | 1 = verify FAULT |
| +15 Bit Fill | 8 sprites on (`$D015 = $FF`, Y = `$E0`); per 16 KB quarter of every bank: fixed-C64 stash of P, swap, stash, fetch, CPU check of `$5000`, fixed-REU verify, fixed-C64 verify; P = `$00`,`$11`,...,`$FF` | 1 verify FAULT, 2 CPU check |

Consequences that matter:

- Every failing phase fails in a **verify** (or, on A22, in a fetch: Address Control 4, `$FF00`).
- Bit Fill does fail (section 6c.4, established after round 3): its first verify faults for every
  pattern but `$FF`, the machine code returns `$FA = 1`, and the modified BASIC wrapper that Joe
  runs (the one without the error stop) ignores it. The earlier reading of the photos as "1024
  passing verifies" was wrong.
- CBR a is the twin of Bit Fill's last verify (fixed-C64, uniform `$AA`) but with 64 KB instead
  of 16 KB, no sprites, directly after a stash, and 66 ms after the bytes were written. It fails
  in every display-on run.
- Address Control parts 1 and 3 (256 bytes, uniform or nearly uniform, stash then verify) failed
  on A23 in 2 of 4 runs and on A22 in 0 of 4; each run contains about one badline.
- Bit Fill is run by the BASIC wrapper for all 16 patterns `$00`, `$11`, ..., `$FF` (line 191
  `FOR I=0 TO 255 STEP 17`), 8 banks and 4 quarters each; it checks the FAULT bit with
  `LDA #$20 / BIT $DF00` two instructions after every verify, exactly like the phases that do fail
  (Block/Page `$325E`, Byte Addressing `$33A5`, Address Control `$35A2`, CBR `$3648`), and on a fault
  it leaves the loops at once with `$FA = 1` (`$345F` / `$3470` branch to `$3495`). The original
  BASIC line 194 (`IF PEEK(SB)<>0 THEN 1500`) would stop with "Error!" at `(00)`; the modified copy
  prints the next pattern instead. The display is never switched off by REUTEST.

Turbo REU Tester 1.2 (unpacked): the size loop (`$0AD4`) stashes a 25-byte text from `$0B92` to
bank N address `$0800`, poisons only the first N/64 bytes of `$0200` (N = KB counter high byte),
fetches 25 bytes back to `$0200` and compares 18 bytes; it exits only on a mismatch. The exit on
A22 therefore proves a lost fetch write in the first bytes of a transfer (or a stash corruption).
The per-bank test (`$0955`) stashes 4 KB from `$0D00` (page 0 holds the pattern 0..255, the rest
is program code) and fetches one page back per iteration, comparing it; 20+ banks printed OK on
A22 with the display on, i.e. tens of thousands of stall boundaries inside stashes of
non-uniform data produced no visible corruption.

## 3. Hardware facts

From the service schematic (8726 pin description, verified):

- `1MHz`: "the system clock, used to synchronize all data transfers" (PHI2).
- `DOT CLOCK`: "used to derive DRAM control signals".
- `/BA`: "the 8726 monitors this signal to determine whether or not it can use the bus".
- `/DMA`: output; `/CS` = `/IO2`; `/IRQ` output; A0..A15 "used to detect address FF00".
- `RESET`: "DRAM refresh is not interrupted during a reset".
- Board: 33 Ohm series resistors in D0..D7 (R5..R12), 68 Ohm in the address lines (RP8/RP9),
  ferrite beads FB1 (R/W), FB2 (PHI2), FB3/FB4 (/IRQ, /DMA), FB5 (+5 V); R4 = 390 Ohm pull-up on
  DOTCLK "populate only for C128 units (1700/1750)"; for the -03 (1764) FB2 is a 430 Ohm resistor.
- Joe's unit: FAB 312535, MOS 8726 3187, second DRAM row added (KM41256-15 / LH21256-15), R4
  empty, FB2 is a bead (looks replaced), vertical riser, JiffyDOS, HDMI 720p.

MEGA65 R6A cartridge port (verified from `/Users/mirko/.dev/MEGA65/doc/PCB/R6A/SCH-TE0765-07-A.PDF`,
page 5, `EXP_Slot.SchDoc`; the same folder holds R2..R6):

- Three `SN74LVCH16T245` dual-supply transceivers, **with bus hold** on both ports (the "H"): U2 =
  D0..D7 (`F_DATA_DIR`, `F_DATA_EN`) and A0..A7; U8 = R/W, /IO1, /IO2, BA on one direction pin
  (`F_CTRL_DIR`, `F_CTRL_EN`) and A8..A15; U9 = /NMI, /IRQ, /DMA and the joystick lines as inputs,
  and DOTCLK (`C64_CLOCK`) and PHI2 (`C64_O2`) as outputs.
- Single-gate buffers (NC7SZ126 + 74AHCT1G125 pairs) for /ROML, /ROMH, /RESET, /GAME, /EXROM,
  /NMI, /IRQ.
- **4.7 kOhm pull-ups to the switched 5 V (`5V_EXT`) on every port line**: BA (R71), R/W (R38),
  /IO1 (R40), /IO2 (R43), /DMA (R90), /IRQ (R37), /NMI, /RESET, /ROML, /ROMH, PHI2 (R102),
  DOTCLK (R39), D0..D7 (R91..R98), A0..A15 (R103..R118); 3.3 kOhm on /GAME and /EXROM.
- Consequence: a line the FPGA stops driving is pulled to 5 V through 4.7 kOhm against the weak
  bus-hold latch, i.e. it rises with a time constant of roughly 0.3 to 1 us (bus capacitance
  including the riser). A released data bus therefore reads `$FF` well within one C64 cycle; a
  released BA (A22) crawls up in the same way, which is what A23's active drive removed.

Board differences do not matter for a REU: R3/R3A/R4 only lack the ability to *sense* /RESET and
to *drive* /GAME, /EXROM, /NMI, /IRQ (`top_mega65-r3.vhd`: reset output only, the other four input
only). An 8726 REU drives /DMA and /IRQ (inputs on every board), reads BA, PHI2, DOTCLK and /IO2
(outputs on every board), and uses the data, address and R/W transceivers (bidirectional on every
board); it never drives /RESET, /GAME or /EXROM. The same failure must therefore be expected on
R3, and no board-specific bidirectional path needs to be added for this issue.

From Moser's reference: on a real C64 the REC's verify is already timing-marginal for I/O-area
reads ("verify operations were a lot more unreliable than simple transfers"), the REU hides its
registers during its own DMA, and the SWAP probably uses the VIC half-cycles for internal DRAM
work (refresh in the other half). No official statement exists about what the REC does in the
cycle in which BA falls.

## 4. The VICE 8726 model (x64sc), the only cycle-level reference

Verbatim in `decoded/vice-reu-c-ba-functions.txt`. Meaning:

- after a **write** (fetch, second half of a swap): the clock advances; if BA is low in the new
  cycle, a counter `delay` increments; only when `delay > 1` the REU waits for BA. So the REC
  performs **one more access in the first BA-low cycle after a write** (the next write of a
  fetch or the next read of a swap), then stalls.
- after a **read** (stash, verify, first half of a swap): if BA is low in the next cycle the REU
  waits immediately. No extra access.
- the wait ends in the first cycle whose BA is high (`vicii_steal_cycles`), i.e. PAL cycle 55 of
  a badline (BA low in cycles 12..54 per VICE's 6569 table).
- `vicii_cycle_reu` contains a measured corner case (sprite 0 switching on in cycle 54), which
  shows that the model was fitted to logic-analyzer data, not guessed.

## 5. The core's hardware-DMA path (A23), timing facts (verified in `main.vhd`, `fpga64_sid_iec.vhd`)

One C64 cycle is 32 ticks of `clk_main_i` (31.7 ns each). Ticks 0..15 are the VIC half
(`CYCLE_EXT0..CYCLE_VIC3`), ticks 16..31 the CPU half (`CYCLE_CPU0..CYCLE_CPUF`).

```
tick      0 1 2 3 4 5 6 7 8 9 10  12  14  16 17 18 ... 30 31 | 0 1 2
PHI2 pin  _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _  _ 1 1 ... 1  _  | _ _ _     rises at edge into tick 17, falls at edge into tick 31
DOTCLK    A22: 32 ns pulses rising at the edges into ticks 3,7,11,...,31 (one coincides with the PHI2 fall)
          A23: square wave, high during ticks 2-3, 6-7, ..., 30-31 (rises at the edges into 2,6,...,30)
BA (VIC)  changes at the edge into tick 1, badline and sprite stalls alike (= 63 ns after PHI2 fell)
grant     cpuHasBus for the CPU half is decided at the edge into tick 16 from baLoc, ba_dma, dma_grace
/DMA      sampled into dma_active at ticks 1 and 9 only
RAM write a cartridge write is executed on every tick 16..31 with the registered pins (1 tick late);
          the final write uses the pins as they were just before the PHI2 falling edge
```

- `BA`, `R/W`, `/IO1`, `/IO2` share one level-shifter direction (`cart_ctrl_oe_o`). During a DMA
  the shifter is in input mode (to sense R/W), so at the cartridge **BA, /IO1 and /IO2 float**
  except while the FPGA drives them: during a stall (BA low, R/W high, IO1/IO2 high, data and
  address tri-stated), during A23's recharge (BA high for ticks 2..5 after the VIC releases BA)
  and during A23's grace cycle (first BA-low cycle after a served write: served, R/W driven like
  the cartridge, write accepted only if the address equals last+1).
- While the cartridge reads, the FPGA drives the data bus continuously (`cart_data_oe_o =
  cart_in_rw_q`), also during the VIC half, where it carries the VIC's fetch data like on a real
  C64. At the stall start the last byte driven (until the edge into tick 1 of the first BA-low
  cycle) is the DMA byte of the previous cycle; afterwards the bus floats at that value.
- The VIC model grants the CPU half of the **second** BA-low cycle of a badline to any DMA master
  (`ba_dma`, MiSTer's approximation for its simulated REU); for a hardware cartridge this cycle is
  served with R/W forced high and no data driven, i.e. harmless.
- `ramWE` is active only in the CPU half; a floating address/data bus during stalls cannot write
  C64 RAM. No I/O side effects are triggered by a floating DMA address during stalls (the bus
  logic selects RAM only).

## 6. Deductions before round 2 (kept as written; 6b supersedes items 2 and 8)

1. **Fetches lose the write of the first BA-low cycle on A22** (Address Control 4, `$FF00`
   run A, the Turbo size-loop exit). A23's grace serves it; in two A23 runs no fetch-side failure
   occurred (weak evidence, Turbo not yet run on A23).
2. **The REC performs no read at all in the first BA-low cycle** (superseded: this rested on Bit Fill, see 6b.5 and 6b.6). A counted read would corrupt
   Turbo's non-uniform stashes; an uncounted, 6502-like repeated read would compare the released
   data bus, which the 4.7 kOhm pull-ups drive to `$FF` within the cycle (section 3), and Bit
   Fill's verifies of `$00..$EE` would fault at every badline. They never do. So the verify
   failures, patterned and uniform alike, share one still unknown cause; the "stale previous byte"
   idea of the earlier handover is dead.
3. **Stashes are not corrupted by stalls** (Turbo; Bit Fill's chain would expose a missing or
   misplaced byte).
4. **The uniform-data verify failures are deterministic, not per-stall random**: Bit Fill passes
   4096 stall-hit verifies per run, CBR a fails every run with 130 stalls per verify. Whatever
   breaks CBR a is tied to one of: length register 0 (65536 bytes), verify directly after a
   stash, no sprites, 66 ms since the bytes were written without any access to their DRAM rows
   (Bit Fill re-accesses every row at least every 32 ms). Each is split by the experiments.
5. **Refresh works while idle** (display off, 10 s, run D) and the chips retain data at least
   66 ms without stalls (display-off CBR a). A refresh/retention explanation needs a mechanism
   by which stalls on the MEGA65 (but not on a real C64) disturb the REC; none was found in the
   signals the core drives differently (only BA, R/W, IO1, IO2 during stalls, all as expected).
   The 10 s idle test (program 6) settles this directly.
6. The DOTCLK change of A23 is not visible with the display off (all OK on both). The Address
   Control difference (A23 2 of 4, A22 0 of 4) is weak evidence that A23 made reads worse; only
   a bisect build (dot clock only / recharge only / grace only) or the experiments can tell.
7. The one-off Interrupt Register timeout with the display off (run B) is unexplained and low
   priority.
8. **Not excluded: the failures may not be tied to BA stalls at all** but to something else the
   display switches on (the VIC's graphics fetches on the data bus in every VIC half, the
   badline c-accesses, the different bus traffic). No run so far separates "verify interrupted by
   a badline" from "verify with the display on". Program 3 does: about half of its 100 short
   verifies are interrupted, so roughly 50 faults mean the stall, roughly 100 mean the display
   itself.

## 6b. Deductions after round 2 (kept as written; 6c supersedes items 5, 6 and 9)

1. **Confirmed: A22 lost one write per stall in fetches, A23 serves it.** `1-fetch` on A22 shows one
   never-written byte per interrupted run; A23 is clean in 20 runs. The REC drives the next
   address (last + 1) in the first BA-low cycle after a write, otherwise the A23 address gate
   would have refused the write.
2. **Stashes are never corrupted by stalls** (`2-stash`, `4-long` m3 with 64 KB, Turbo). Whatever
   the REC does in the first BA-low cycle after a read is not a counted read of the floating bus:
   that would store garbage. An uncounted ("held", 6510-like) read that is repeated after the
   stall remains possible: a stash would overwrite the garbage with the repeated read.
3. **Every interrupted verify faults** (section 1b), for incrementing and fixed C64 addresses, for
   uniform and non-uniform data, after any preceding operation, with and without sprites, and
   identically on A22 and A23. So the A23 changes (dot clock, BA recharge, write grace) touch
   nothing the verify depends on, and the stash/verify asymmetry is the whole problem.
4. **The REU data is not lost by an interrupted verify as far as we know**; `10-after` (round 3)
   checks it directly. Idle stalls do not disturb the DRAM (`6-idle`).
5. **The Bit Fill paradox is real and unexplained.** Excluded as the reason for its immunity, each by
   a failing test that shares the property: machine code with SEI and the `$FF00` writes (all other
   REUTEST phases fail), the C64 buffer at `$5000` (the other phases use it), 16 KB length and
   fixed C64 address (`3-verify` p5, `4-long`, `7-chain` fail), uniform data (`$AA` fails
   everywhere, Bit Fill passes with `$00..$FF`), 8 sprites at Y = 224 with the same X positions
   and pointers (`5-sprites` fails), a fetch or a fixed-REU verify directly before the verify
   (`7-chain` b and c fail), a verify started within 20 cycles after the previous DMA (CBR a,
   Byte Addressing fail), the bank loop (bank 0 passes in Bit Fill and fails elsewhere). The only
   element of Bit Fill that no failing test contains is the **swap** (16 KB, both addresses
   incrementing, display on) that precedes the stash/fetch/verify/verify of every quarter. No
   mechanism is known by which a swap could change how the REC or the core handle a later stall;
   `8-swap` tests it directly, `11-bitfill` replays the exact machine code with one element
   removed per variant.
6. **The one hypothesis that fits everything except Bit Fill** ("H1"): in the first BA-low cycle
   after a read the REC performs an uncounted read (address driven, like a 6510 holding a read
   cycle with RDY low), latches the data bus at the PHI2 fall and feeds it to the comparator; on a
   real C64 that cycle still has AEC high and the RAM answers, so the compare passes; on the MEGA65
   the FPGA releases the data bus at tick 1 of that cycle, the lines float from the previous byte
   toward `$FF` through the 4.7 kOhm pull-ups, and the compare fails. A stash stores the garbage
   and overwrites it with the repeated read after the stall; a fetch is a write and is served by
   the A23 grace. H1 predicts that a verify of uniform `$FF` data never faults and a verify of
   `$00` data faults at every stall (`9-values`), that the fault position is the byte after the
   last served one and the REU data stays intact (`10-after`, `12-position`), and it predicts
   Bit Fill to fault, which it does not. H1 is therefore wrong or incomplete; round 3 decides.
7. **The REC's compare is pipelined** (VICE "weird behaviour no. 1": a mismatch at byte k is acted
   on one cycle later, during the access of byte k+1; the address registers point to k+1 and
   the length register to `L-k-1` after a verify without autoload). `10-after` and `12-position`
   use these registers to locate the faulting byte.
8. **Weak signals, not to be built on:** 256-byte fixed-C64 verifies passed 6 of 6 in `4-long`
   (expected 2 faults at the stall rate); Address Control parts 1 and 3 passed 8 of 8 on A22.
9. **Bit Fill's "OK" proves only that FAULT was never set, not that 1024 compares ran.** Its
   CPU check reads `$5000`, a byte the CPU itself stored before the first transfer; its verifies
   compare P with P; a verify that never executes, or executes without comparing, leaves FAULT
   clear because the previous `BIT $DF00` cleared it; a status read the REC does not answer
   would float high (FAULT set), so a lost status read is not the way out. The core keeps no
   state between transfers (everything is cleared while /DMA is high) and serves stash and
   verify identically, so whatever makes Bit Fill pass sits inside the REC: either (A) the swap
   leaves the REC in a state in which later verifies tolerate stalls, or (B) after the swap the
   verifies do not run or do not compare. One fact settles it: the exact chain with a mismatch
   planted by the CPU after the fetch (`11-bitfill` variants 8 and 9, the latter with the
   display off). FAULT there means (A); no FAULT means Bit Fill is blind and the paradox
   disappears. A free second fact: with 114688 DMA cycles per quarter and 32 quarters, one Bit
   Fill pattern takes about 4 s if everything runs (about 64 s for the 16 patterns on the CMD
   screen), about 2.9 s if the two verifies are skipped, under 1 s if nothing runs after the
   swap; Joe can time the CMD test's Bit Fill line with a stopwatch.
10. **No positive control existed for long verifies**: every clean verify so far would also
    pass if the comparator could never fail (only the 1-byte Interrupt Register test proves a
    genuine mismatch sets FAULT on the MEGA65). `10-after` now ends with a display-off verify
    of 256 bytes with byte 100 changed by the CPU and prints the fault byte from the registers.

## 6c. Deductions after round 3 (the root cause)

1. **Every interrupted verify compares its REU byte against exactly `$FF`** (`9-values`: `$FF`
   never faults, 0 of 50 on A23 and on A24; every other value, `$FE` and `$7F` included, faults at
   the stall rate of about 17 in 50). That is the level of a port line nobody drives: the 4.7 kOhm
   pull-ups (section 3) raise a released line to 5 V within the cycle. Not VIC data (that would
   let `$FF` fault sometimes and the other values pass sometimes), not a stale byte.
2. **The fault is a false compare on the first stalled byte, the REU data is intact.** `10-after`:
   seven faults, zero wrong REU bytes, the positive control reports byte 100. `12-position`: the
   verify started at line 50 faults on byte 49 in ten of ten runs (the raster sync has no jitter),
   with the REC releasing the bus 94 cycles after the command (`113 - 19`, the control run at line
   52 reports 275 for 256 reads): 49 reads before the badline, the 43-cycle stall (BA low in cycles
   12..54), the fault on byte 49, VICE's extra cycle. The transfer ends in line 51.
3. **A24 changed nothing**, although it drove the RAM byte for the address the cartridge shows
   during the whole first BA-low cycle (bench S2/S8 of `tb_cartport`, the branch in
   `handle_hardware_expansion_proc`). So the failing compare is not fed from that cycle alone.
   The REC cannot have released its address lines there while reading: on a real C64 a released
   address bus drifts within the cycle (TTL input currents of the 74LS257 multiplexers) and the
   verify would fail there too. The resume cycle is excluded as well: the C64 RAM is a BRAM that
   is read continuously, `fpga64_buslogic` puts the DMA address on it from tick 16, so the FPGA
   drives the correct byte about 60 ns after PHI2 rises, earlier than the DRAM of a real C64, as
   long as the cartridge's address is on the pins by tick 16; a REC that drove it later would fail
   on a real C64, whose DRAM latches the row address with RAS at the PHI2 rise. The decisive
   evidence for the resume cycle is simpler, though (adversarial review, 2026-11-07): stashes
   use the same C64-side resume read and store correct data (`2-stash`, `4-long` m3 with 64 KB,
   Turbo), fetches use the same REU-side resume read and deliver correct data (`1-fetch` on A23,
   poison value 255), so the resume read is good on both sides. (The value `$FF` alone does not
   exclude a latch during a VIC half: the FPGA tri-states D0..D7 during both halves of every
   stall cycle and during the first ticks of the resume cycle, so such a latch would read `$FF`
   too; what excludes it is the real C64, whose bus carries VIC data in those halves.) What
   remains is the **second and third BA-low cycle**: the FPGA served neither (A22 to A24 tri-state the data
   bus there, `cart_data_oe_o <= '0'` in the stall branch), a real C64 answers both (AEC stays
   high in phi2 for exactly three BA-low cycles; the VIC model does the same, `baCnt` and
   `addrValid` in `video_vicII_656x.vhd`), and a REC that keeps its read on the bus like a 6510
   with RDY low, latching and comparing in every such cycle, sees `$FF` there on the MEGA65 and
   valid RAM on a real C64. Stashes survive because the held reads store the garbage at the same,
   non-advancing REU address and the counted read after the stall overwrites it. Fetches lost
   exactly one write per stall on A22 because the REC counts the write of the first BA-low cycle
   (VICE) and whatever it repeats afterwards is a repeat of the next byte, which it writes again
   after the stall. This is the mechanism A24X1 is built on (section 9); `14-ffff` (section 7c)
   checks the one assumption that has no direct measurement yet, that the REC drives its address
   during the held reads. The round-3 facts do not *force* this mechanism; they force "the
   comparator took a `$FF` operand from an access whose data neither a stash stores nor a fetch
   writes", and the held read in the AEC window is the most economical way to get there. The
   one alternative that survives on paper (adversarial review): the REU-side operand is `$FF`,
   i.e. a verify-only DRAM read inside the REC disturbed by a MEGA65-specific edge, such as the
   stall-end BA rise coinciding with a DOTCLK edge on A23/A24 (both at the edge into tick 2).
   Against it: the fault rates are identical on A22, where BA was released through the pull-up
   and the dot clock had a different shape and phase, and fetches read the DRAM at the resume
   without error. A24X1 decides: it serves the second and third BA-low cycle and changes no
   edge. Also to be confirmed in round 4: Joe really booted A24 (the core version is shown in
   the core's About screen and in the config file name); equal counts are also what an A23 boot
   gives.
4. **The Bit Fill paradox is resolved** (verified by disassembly, `$33F4..$34A7`): Bit Fill
   resets its own state (`$FC = 0` at `$3413`, length `$4000`, `$DF0A` written before every
   quarter, all commands with autoload), runs the seven-transfer chain per quarter, and after each
   verify executes `LDA #$20 / BIT $DF00 / BNE $3495`, where `$3495` sets `$FA = 1` and returns.
   For every pattern except `$FF` the first fixed-REU verify of quarter 0 (16 KB, always hit by a
   badline) faults, and the machine code returns after one of 32 quarters, about 0.09 s. Joe's
   modified BASIC (the copy without the error stop, 2026-10-26) does not act on `PEEK(SB)` and
   prints the next pattern. Only `$FF` runs all 32 quarters (4.0 s) and passes vacuously, because
   `$FF` cannot fault (item 1). 4.0 s plus 15 times 0.09 s plus BASIC overhead = 5.7 to 7 s; Joe's
   stopwatch says about 6 s. `11-bitfill` variant 0 (`$AA`) faulting on A23 is the same thing
   under our control; a variant with `$FF` would pass. The swap, the sprites, the chain and the
   "1024 verifies" were never involved; 6b.5 and 6b.9 are void. Prediction for Joe:
   `:PRINTPEEK(SB);` after `SYS ML+15` prints 1 for `(00)` to `(ee)` and 0 for `(ff)` on A24, and
   0 sixteen times on A24X1.
5. **Sprite stalls fault like badlines**: `11-bitfill` variant 9 (display off, eight sprites on)
   faulted its fixed-C64 verifies (`C 4`), and only sprite DMA stalls the bus there. Consistent
   with the three-cycle window being the VIC's AEC rule for every BA source.
6. **No swap has ever been checked byte by byte after a stall** (every swap test could only report
   the verify fault that followed); `13-swapchk` does it on A24X1.
7. **Side effects of the grace reads on other DMA masters** (adversarial review): a grace cycle is
   granted with `cpuHasBus = '1'`, so the full memory map is decoded and an I/O address on the bus
   is really read (`$DC0D`/`$DD0D` clear ICR flags, `$D01E`/`$D01F` the collision registers).
   For a REC this is what a real C64 does; for a master that idles in those cycles with an I/O
   address left on the bus it is a spurious read, up to three per stall (A24: one). No known
   master ends a transfer that way (a REC releases /DMA after its last access). Pre-existing and
   unrelated to the grace, noted for later: a DMA read from `$8000..$BFFF` or `$E000..$FFFF`
   while a cartridge ROM is mapped returns `cart_in_data = $00` (the hardware-cart branch of
   `cpu_data_in_proc`) and the FPGA drives it against the cartridge's ROM data in every served
   cycle; a 1541 Ultimate II+ with a cartridge image and its REU could notice, a 1764 cannot. A
   fetch to a fixed C64 address still loses its first-BA-low-cycle write (the address gate), as
   since A23.

## 7. Experiments for Joe (`tests/reu-tests.d64`, BASIC, simulated REU must be off)

All transfers use autoload commands 176..179 (`$B0..$B3`); the display is switched with
`POKE 53265,11/27` and 100 ms settling. Each program prints its own verdicts.

| Program | What it does | What the outcome means |
|---|---|---|
| `1-fetch` | stash 0..255 with display off; 20 x fetch into a buffer poisoned with 255, display on; prints every wrong byte | A22: positions still 255 = lost writes at stall starts. A23: none expected (grace works). Any other wrong value = the fetch delivered wrong data |
| `2-stash` | 20 x stash 0..255 with display on, fetch back with display off, compare | wrong bytes = stash corruption; the value tells the mechanism (previous byte = stale bus, 255 = floating high, shifted = slip) |
| `3-verify` | clean data stashed with display off, then repeated verifies with display on: 256 B 0..255, 256 B `$AA`, 4 KB, 64 KB fixed-C64 `$AA` (CBR a twin, 10 runs), 16 KB fixed-C64 | faults with non-uniform but not uniform data = uncounted read of the floating bus; 64 KB faulting while 16 KB passes = length effect; all zero = the verify is fine and CBR a's problem is in the stash |
| `4-long` | fixed-C64 stash of `$AA` then verify for 256 B, 4 KB, 16 KB, 32 KB, 64 KB, each 3 x, with display on/on, off/on, on/off; plus a 12 KB RAM canary at `$5000` | which length fails, and whether the stash (on/off) or the verify (off/on) is the victim; canary changed = the core wrote garbage into C64 RAM |
| `5-sprites` | 64 KB fixed-C64 stash+verify, display on, 5 x without and 5 x with 8 sprites | passes only with sprites = Bit Fill's immunity comes from the sprites |
| `6-idle` | stash 64 KB with display off, wait 10 s with display on or off, verify with display on or off | fault only when the wait had the display on = stalls disturb the REU while idle (refresh); fault only when the verify had the display on = the verify is the victim |
| `7-chain` | 16 KB fixed-C64: stash+verify; stash+fetch+verify; stash+fixed-REU-verify+verify, 5 x each | tells whether the operation before the verify matters (Bit Fill's chain) |

Core versions: everything on A23; `1-fetch` and `3-verify` additionally on A22.

Baseline (sy2002, 2026-11-03): all seven programs run on a MEGA65 with A23 and the **simulated**
REU switched on, display on, every verdict OK. So the programs are correct, and any fault Joe sees
with the hardware REU is the REU/port interaction, not the test.

## 7b. Round 3 experiments (`tests/round3/reu-tests3.d64`, all on A23, simulated REU off)

Built by `tests/round3/build.sh`; the machine-code programs sit behind their BASIC drivers in one
PRG (`LOAD"name",8` and `RUN`, nothing else). Every program prints its own verdicts.

| Program | What it does | What the outcome means |
|---|---|---|
| `8-swap` | 16 KB fixed-C64 stash of `$AA`, then 3 verifies with the display on ("before"); then a 1-byte fetch, a 1-byte swap, a re-stash, a 256-byte swap with the display off, a 16 KB swap with the display on plus re-stash, each followed by 3 verifies | "before" FAULT and everything after the first swap OK: a swap puts the REC (or the core) into a state in which verifies survive stalls, which explains Bit Fill; then the smallest swap that helps tells what the state is. All FAULT: the swap is not the key and Bit Fill's immunity lies in the machine-code chain (`11-bitfill`). "after 1b fetch" OK: any REU-to-C64 write helps, contradicting `7-chain` b |
| `9-values` | 256-byte incrementing verifies of uniform data, 50 each with the display on, for `$FF`, `$00`, `$AA`, `$55`, `$FE`, `$7F`, `$0F`, `$F0` | `$FF`: 0 faults and `$00`: about 17 = H1 (the comparator sees a released bus that has risen to `$FF`); the values with single low bits (`$FE`, `$7F`) and nibbles tell which bits rise within the cycle. All values about 17: the compare does not see the floating bus, H1 is dead. All 0: the bus holds its value (then `3-verify` p2 needs re-explaining) |
| `10-after` | 256-byte 0..255 verify without autoload, display on, 20 runs; after each fault it prints the registers (fault byte index, remaining length, status: 48 = FAULT plus the 1764 size bit) and fetches the 256 REU bytes back with the display off, printing every wrong one; ends with the positive control: display off, byte 100 changed by the CPU, verify, prints the fault byte (expect 100) | "reu data intact" after every fault: the fault is a false compare, the DRAM is fine (H1 family). Wrong bytes: the interrupted verify damaged the REU data (DRAM/refresh mechanism), the positions tell how much. The fault byte index per run is uniform in 0..255 under any per-stall theory |
| `11-bitfill` | the exact REUTEST Bit Fill chain in machine code (variant 0 is a cycle-exact copy of `$3426..$3470` up to the first fault: SEI, `$FF00`, 8 sprites, per quarter stash/swap/stash/fetch/CPU check/verify fixed-REU/verify fixed-C64, pattern `$AA`, bank 0, 4 quarters), then variants: 1 no swap, 2 no sprites, 3 CLI, 4 no `$FF00`, 5 no fetch, 6 stash+verify only (CBR a with 16 KB), 7 stash+fixed-REU verify+verify (`7-chain` c in machine code), 8 the exact chain with `$55` planted by the CPU into `$7000` after every fetch, 9 the same with the display off. Per variant it prints `r` (fixed-REU verifies faulted, of 4), `c` (fixed-C64 verifies faulted, of 4; variant 6 has no `r`), `cpu` (CPU checks failed) and `1st` (first fault: quarter times 2, plus 1 for fixed-REU or 2 for fixed-C64; 0 = none). The CPU fills `$5000-$8FFF` with `$AA` at entry so every variant verifies valid data | read variant 9 first: `r 4` means the chain's fixed-REU verifies do compare (the planted byte `$2000` of every quarter is found with no stalls around), `r 0` means they do not, Bit Fill is blind and the paradox is gone (then look for the reason the REC skips or empties a verify issued 17 cycles after a fetch with `$DF0A = $40`). Variant 8 adds the stalls: `r 4 c 0` = the verifies compare and the fixed-C64 verify survives stalls in this chain (mechanism A), `r 4 c 4` = no immunity at all in our replay. Variant 0 with `r 0 c 0` reproduces the paradox under our control; the first variant with faults names the element that protects Bit Fill. Variant 0 faulting: the paradox was an artifact of something outside the chain (bank loop, pattern loop, the BASIC program), re-read `cmd-reutest-basic.bas`. Variants 6 and 7 passing while the BASIC twins fault: the difference is BASIC versus machine code (IRQ, timing gap, dummy read of `$DF01` by the POKE) |
| `12-position` | machine code: 256-byte 0..255 verify without autoload started at the beginning of raster line 50 (badline at 51: BA falls after about 47..57 served bytes, the line-start jitter is 0..10 cycles and the command is written at cycle 18..28) and at line 52 (the transfer ends in line 56, the next badline is 59), 10 runs each, one screen per line with a key wait between them; per run: `st` status, `byte` = fault index from `$DF02/03` (255 with `len 1` = ran to the end), `len` remaining length, `cyc` = CIA timer count from 6 cycles before the command write to 14 cycles after the CPU resumed (transfer = `cyc - 20`), `end` = raster line right after the transfer | line 52: all `byte 255 len 1`, `cyc` about 280 (control). Line 50: `byte` 46..58 = the fault is at the first stall (H1 or a resume problem); `cyc` about byte + 70 = the transfer ended with the stall; `byte` far from 46..58 or spread over the transfer = not a stall-start effect. The spread over the 10 runs mirrors the sync jitter. `st` 48 = FAULT plus the 1764 size bit, 112 = FAULT with end of block |

## 7c. Round 4 experiments (`tests/round4/reu-tests4.d64`, simulated REU off, see `PROTOCOL-round4.md`)

Part A on A24 (`14-ffff` only), part B on A24X1: `3-verify`, `9-values`, `12-position`,
`11-bitfill`, `13-swapchk`, `14-ffff`, `1-fetch`, `2-stash`, the CMD test with the display on and
the stopwatch (expected about 64 s for the Bit Fill line, and 0 sixteen times with the
`PRINTPEEK(SB);` addition).

| Program | What it does | What the outcome means |
|---|---|---|
| `13-swapchk` | C64 `$4000..$40FF` holds `i`, REU `$0000..` holds `255-i`; 20 times: 256-byte swap with the display on, then with the display off a CPU check of the C64 side and a fetch of the REU side into `$4200` with a CPU check (after an odd number of swaps the C64 holds `255-i` and the REU `i`); then a 16 KB swap at `$5000` with page-dependent data (`(i + i/256) and 255` against its complement, REU bank 1) checked the same way, about three minutes of BASIC | any wrong byte, with run, position and both values, is a swap damaged by a stall: the position relative to the stall tells whether the read half or the write half went wrong. All zero: swaps survive stalls on A24X1 |
| `14-ffff` | machine code: `$01 = $35` (KERNAL and BASIC out, I/O in), the buffer at `$2000..$20FF` (its half-floated supersets `$2100..$3FFF`, `$6000..$7FFF`, `$A000..$BFFF`, `$E000..$FFFF` contain no I/O), a chosen byte F stored in all of those ranges including `$FFFF` (NMI vector parked on an RTI), 256-byte incrementing verifies of uniform data D without autoload, each started at raster line 50 like `12-position` (badline at 51, the held read is byte 49), 10 runs per pair, for (D, F) = (`$FF`, `$00`), (`$00`, `$00`), (`$00`, `$FF`), (`$FF`, `$FF`), (`$55`, `$AA`), (`$AA`, `$55`), (`$AA`, `$AA`); prints faults of 10 and the fault byte of the first fault | on A24: 10 of 10 exactly in the lines with D not `$FF` (lines 2, 3, 5, 6, 7), byte 49 = the comparator sees a floating **data** bus (the REC drives its address; A24X1 fixes it). 10 of 10 exactly where D differs from F (lines 1, 3, 5, 6) = the REC's **address** lines float during the held read and the FPGA serves F (A24X1 cannot help; the core would have to serve the address of the last served read, and section 8 is next). Faults in both kinds of line = both; a byte other than 49 = the fault is not the held read. On A24X1: all seven lines 0 of 10; any remaining fault pattern reads as above |

Expected on A24X1 for the round-2 and round-3 programs: `3-verify` and `9-values` zero faults;
`12-position` line 50 like line 52 (`80 255 1`, `CYC` about 318 = 275 plus the 43-cycle stall,
`END` 55); `11-bitfill` `R 0 C 0` for variants 0..7 and `R 4 C 0` for 8 and 9 (the planted byte is
found, the fixed-C64 verifies no longer fault, with the display on or off); `1-fetch` and
`2-stash` unchanged (0 bad bytes).

## 8. Logic analyzer capture (when Joe gets one, about two weeks)

Channels, in priority order: PHI2, BA, /DMA, R/W, /IO2, A0..A3, D0..D7, DOTCLK; at least 25 MHz
sampling (100 MHz preferred); trigger on BA falling while /DMA is low; capture 100 us before and
after. Run `3-verify` (64 KB fixed-C64) so badlines hit a verify. Questions it answers: does the
REC put an address and R/W on the bus in the first BA-low cycle (uncounted read); does it
tri-state address and R/W during the stall; in which cycle does it resume after BA rises; does
R/W ever float low; what the data bus does at the stall start. The same capture during a fetch
shows the extra write and whether A23 serves it.

**Alternative without an external analyzer: an ILA debug build.** Joe's R6A has the JTAG header
populated (issue comment 6365704850). A `debug` build (`build_bitstream.tcl ... debug`, see
`doc/developer.md` "Debug builds") inserts an Integrated Logic Analyzer on every `mark_debug`
net and writes the probes file next to the bitstream. Candidate nets in `main.vhd`:
`cart_in_a_q`, `cart_in_d_q`, `cart_in_rw_q`, `cart_in_dma_n_q`, `cart_in_ba_q`, `cart_in_io2_n_q`,
`core_ba`, `core_dma_cycle`, `core_dma_grace`, `cart_ctrl_oe_o`, `cart_data_oe_o`, `core_phi2`,
`cart_dotclk_q`; depth 8192 samples at 31.5 MHz = 260 us, trigger on `core_ba` falling while
`cart_in_dma_n_q` is low. Joe would need the JTAG adapter cable, Vivado Lab Edition (free) on a
PC, the debug bitstream and the `.ltx` file, plus a short recipe from us. Caveats: the ILA sees
the FPGA side of the level shifters (what the core sees, delayed by the input registers), not the
5 V bus; a debug build is not timing-gated. Priority set by sy2002 (2026-11-03): first the
round-2 programs, then further BASIC experiments derived from their outcome, because guiding Joe
through Vivado is a lot of work for him; the ILA only if BASIC-level tests cannot pin the cause.
Building a QNICE debug device (as done for the physical floppy work) is explicitly a last resort.

## 9. The core changes: A24X1 (the fix), A24 (superseded), and other ideas

- **A24X1: three grace cycles for reads, implemented 2026-11-07 in `CORE/vhdl/main.vhd`
  (`cart_dma_ba_proc`, `handle_hardware_expansion_proc`, constant `C_CART_DMA_GRACE_RD_CYCLES = 3`,
  counter `core_dma_grace_cnt`, flag `core_dma_grace_long`).** After a served read (stash, verify,
  the first access of a session) `core_dma_grace` now stays up for three served BA-low cycles,
  each served as a read with the RAM byte for the address the cartridge shows (BA driven low, R/W
  driven high, no RAM write); after a swap's write exactly one grace cycle as a read (the swap's
  counted next read, as in A24; a swap never compares, and a master of another make might drive
  its next write there, so the cycles after it stay unserved, a point from the adversarial
  review); after a fetch's write exactly one grace cycle as a write with the address gate, as in
  A23; none after a swap's read (a read that follows a write), as in A24; the grace ends early if
  BA rises, and all state clears when /DMA goes high. Nothing changes for cartridges that do not
  assert /DMA (the whole logic sits inside `cart_in_dma_n_q = '0'`) and nothing for SIMCRT or
  SIMREU. `fpga64_sid_iec` grants
  the CPU half of any cycle with `dma_grace` set, unchanged; the VIC model keeps `addrValid`
  (`aec`) low in the CPU half while `baCnt < 4` (`video_vicII_656x.vhd` lines 325..340 and
  694..700), for badlines and sprites alike, so the VIC never needs the three CPU halves the grace
  uses; this is the same three-cycle window in which a real C64's AEC stays high. Bench
  (`CORE/vhdl/test/tb_cartport/run.sh`, PASS): S2 three grace reads with data driven, fourth stall
  cycle floating; S7 the swap's grace read lasts one cycle, the second BA-low cycle floats; S8
  first read of a session; new S9 BA rising after two BA-low cycles ends the grace, the resume
  cycle is served normally; S1, S3, S4, S4b, S5, S6, S7b, S7c unchanged. GHDL analysis of
  `main.vhd` against HEAD: identical diagnostics (only the expected missing sub-entities). An RTL
  bench with the real VIC-II and bus-logic entities (`CORE/vhdl/test/tb_vicdma/`, in progress)
  checks that the grant of the second and third BA-low cycle changes nothing the VIC fetches and
  that the data path delivers the right byte in every grace cycle. Risk: a DMA master of another
  make that writes in the second or third BA-low cycle after two reads would meet driven read
  data for those cycles (same class as A23's write grace meeting an idle master; the REC never
  writes there, such a write was never accepted anyway, and the level shifter wins the fight:
  logic garbage for that master, no damage); the I/O side effect of 6c.7. Options from the
  review that were not taken, to keep the build free of new surfaces: a run-time register for
  the grace length (0..3) at `$D03F` and an address-hold diagnostic readable through IO1; one
  hardware session with them would tell which of the three cycles carries the held read, which
  the fix does not need to know. Not yet synthesized; sy2002 builds WIP-V6-A24X1.
- **A24 (commit ade48e6), superseded: read grace in the first BA-low cycle only**, implemented 2026-11-04 in `CORE/vhdl/main.vhd` (`cart_dma_ba_proc`,
  `handle_hardware_expansion_proc`, commit ade48e6) and benched** (`CORE/vhdl/test/tb_cartport/run.sh`: scenarios
  S2 read-read-stall, S7c swap read then stall, S8 first read then stall, all PASS). After a served
  read the first BA-low cycle is served as a read: BA driven low, R/W driven high, the read data
  for the address the cartridge shows driven for the whole cycle, no RAM write. Not armed after a
  read that follows a write (a swap's read: the REC stops at once there, VICE). The grace
  direction is the last access's direction, except a write after a read (swap) which gets a
  read. The fetch grace keeps its address gate; the read grace has none (fixed-C64-address
  transfers read the same address again). This is the fix if H1 (section 6b.6) holds: it hands
  the REC's uncounted read the RAM byte a real C64 delivers in that cycle. It cannot explain Bit
  Fill, so it is a hypothesis under test, not a diagnosis: it is **WIP-V6-A24** (bump 39d75f3), and
  Joe runs `3-verify`, `9-values` and the CMD test on it after the round-3 programs on A23. If `9-values` on A23
  shows `$FF` never faulting while `$00` does, A24 is expected to pass every verify.
  Risk accepted: a DMA master of another make that writes in the first BA-low cycle after a read
  would meet driven read data for that one cycle (same class as the A23 write grace meeting an
  idle master); such a write was refused by A23 already, so no data regression.
- Bisect builds of A23: dot clock only (`cart_dotclock_o <= core_dotclk`), recharge only
  (`cart_ba_recharge <= '0'`), grace only (`core_dma_grace_armed <= '0'`).
- Address-side variant of H1, not yet tested: the FPGA never drives A0..A15 during a DMA
  (a real C64's VIC drives them in every stall), so if the REC released its address lines
  during the first BA-low cycle but still latched data, the read grace would serve RAM at a
  drifting address. Discriminating test (machine code, SEI, `$01 = $35`): 16 KB fixed-C64
  stash and verify of `$AA` with the C64 address `$FFFF` (RAM, where a drifting bus lands)
  versus `$4000`, display on; only `$4000` faulting puts the cause on the address side. Low
  priority: a REC that latches data without driving its address would fail on a real C64 too
  (the bus there holds the VIC's refresh address).
- Hardware facts of the R6A port are in section 3; the R3 port uses the same transceiver family
  (`/Users/mirko/.dev/MEGA65/doc/PCB/R3/sn74lvc16t245.pdf` is next to its schematic).
