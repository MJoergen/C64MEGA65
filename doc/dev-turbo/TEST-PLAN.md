# Turbo modes: test plan

Collected from #87, #242, the linked sources and the analysis in `RESEARCH.md`. When branch `turbo-mode` exists, the hardware items become `@TODO` bullets of a new section `Version WIP-V6-A22X1 - TBD` at the top of `tests/README.md`.

## 1. Principles

* With turbo `Off`, nothing may differ from `WIP-V6-A22`.
* Test PAL and NTSC; R3 (HyperRAM shared with ascal, no SDRAM) and R6 at least, R4/R5 when available.
* Measure the effective speed instead of assuming the nominal factor: I/O, badlines and sprite DMA keep C64 timing.
* Where timing matters, test with `HDMI: Flicker-free` on and off.
* **Who tests:** the maintainer does not test games. Items marked **(community)** are for Boris and other community testers; the request goes out on GitHub (#87) when `WIP-V6-A22X1` is ready. All other items: core team and QA (paich64), to be assigned.

## 2. Simulation (before the first build)

| # | Check | Expected |
|---|---|---|
| I1 | Turbo `Off`: cycle trace of the baseline sources against the new sources, with `sysCycle`, CPU address, write enable, `enableCpu` and every signal toward the expansion port (address, data and its drive, R/W, ROML, ROMH, Ultimax ROMH, Ultimax unmapped area, IO1, IO2, PHI2, BA) | identical |
| S1 | CPU accesses per 1 MHz cycle with RAM-only code in `Off` / `2x` / `3x` / `4x` | 1 / 2 / 3 / 4, in the states `CPUC` / `CPU4`+`CPUC` / `CPU4`+`CPU8`+`CPUC` / `CPU0`+`CPU4`+`CPU8`+`CPUC` |
| S2 | I/O access (VIC, SID, CIA, color RAM, IO1, IO2) in turbo | only at `CPUC` of a cycle in which the CPU has not run yet |
| S3 | DMA request (SIMREU, SIMCRT bank load, hardware `/DMA`, cartridge loading) | no turbo access while it is active |
| S4 | C128 mode: write bit 0 of `$D030` | turbo on/off from the next cycle; `$D030` reads `$FF` with C128 mode off, `$FE` (bit clear) or `$FF` (bit set) with C128 mode on; the bit survives changes of the turbo mode, only a reset clears it |
| S5 | Smart: clock edge on each of `c64_iec_clk_out`, `c64_iec_clk_in`, `hw_iec_clk_n_in` | turbo off within one cycle, back on 0.5 s after the last edge |
| S6 | Real-cartridge ROM read directly after a turbo access (finding F2) | before the fix: the short address-to-sample time is reproduced; after the fix: the access runs in a clean cycle, with the CPU address at the port for about 410 ns (`CPU1` to `CPUD`) before the data is sampled, the same window as with turbo `Off` |
| S7 | SIMCRT ROM read in turbo | runs in the turbo states, correct data from the BRAM cache |
| S8 | Upstream `d6048db` | no effect: `cs_io` is 0 at the sample points `EXT1`/`EXT5` (`RESEARCH.md` section 4) |
| S9 | CPU writes to the cartridge area (ROML, ROMH including the Ultimax area `$E000-$FFFF`, IO1, IO2) in `Off` / `2x` / `3x` / `4x`, also directly after a turbo access | the cartridge sees exactly one write per CPU write: one strobe with R/W low at one PHI2 falling edge, none in a cycle in which the write only waits |
| S10 | CPU write to `$FF00` in `Off` / `2x` / `3x` / `4x`, also directly after a turbo access | address `$FF00` with R/W low at the port at a PHI2 falling edge in every speed |
| S11 | EF3 menu fingerprint (`$DE00`, `$DE0E`, `$0108`, `$0109`, `$0013`) and reset request in Smart `4x`, hardware-cartridge mode, heuristics enabled | the EF3 is detected and its reset request is executed, as with turbo `Off` |

## 3. Measuring the speed

* Benchmarks from the icomp wiki page "C64 Benchmarks": Synthmark64 (https://github.com/mrdudz/synthmark), Bouldermark, the fractal part of Coma Light 11, M.E.G.A. C64 Benchmark.
* A small own check: a loop that counts iterations per frame, in `Off` / `2x` / `3x` / `4x`, with the screen on and with the screen off (`POKE 53265,11`, no badlines).
* Expected: RAM-heavy code with the screen off comes close to the nominal factor; screen on costs the badline cycles; I/O-heavy code gains much less.

## 4. Hardware tests

### 4.1 Regression with turbo `Off`

* The usual demo set (`tests/demos.md`), a few games, hardware and simulated cartridges: identical to A22.

### 4.2 C128 mode

* **(community)** Rescue on Fractalus, patched by Boris (MagicDesk `.crt`, https://webdrive.commodoregames.net/SHARE_AL9YKJD5OG), in `2x` and `4x`: faster 3D, correct picture. Once as SIMCRT, once from a real cartridge (KFF or EF3).
* **(community)** Uridium+ (uses the C128 2 MHz mode: more background stars).
* **(community)** The original Rescue on Fractalus (reportedly fails on a real C128 because it touches `$D030`): see what happens in C128 mode.
* Software that never touches `$D030` stays at 1 MHz: a demo with C128 mode on behaves exactly like `Off`.
* `PRINT PEEK(53296)`: 255 with C128 mode off; 254 with C128 mode on; `POKE 53296,1` switches turbo on, `POKE 53296,0` off again.
* The `$D030` bit survives menu changes and is cleared only by a C64 reset: `POKE 53296,1` with turbo `Off`, then select `C128`: the turbo is on at once; switch to `Off` and back to `C128`: still on; reset the C64: off (MiSTer behavior).
* In C128 mode a program that reads `$D030` to detect a C128 sees one (254 instead of 255) and may take its C128 code path.

### 4.3 Smart mode

* **(community)** Test Drive II (the game behind #87) in `2x` / `3x` / `4x`.
* Loading and saving: simulated 1541 (D64 with the standard loader, a fastloader game, `SAVE`), simulated 1581 (D81), the built-in floppy drive as 1581, JiffyDOS (`@$` and a JiffyDOS load), a real drive or SD2IEC on the IEC port.
* **(community)** Rescue on Fractalus (patched) in Smart: screen corruption expected; this documents why such software needs C128 mode.
* **(community)** Koronis Rift V2.1 beta (EasyFlash `.crt`, https://webdrive.commodoregames.net/SHARE_BGVKGUOOR4) in Smart `4x`: does its C64 Ultimate speed check pass, and if so, does its 4 MHz version play correctly? Holding left SHIFT at the title picture skips the check.
* A timing-critical demo in Smart: breaks as expected (for the documentation).

### 4.4 Real cartridges in turbo (C128 and Smart, `2x` and `4x`, R3 and R6)

* **(community)** KFF with both patched games (exercises finding F2).
* EF3: menu, then start a game; on R3/R3A/R4 the EF3 reset detection (`cartridge_heuristics_inst`).
* EF3 on R3/R3A/R4 in Smart mode (`2x` and `4x`): start a game from the EF3 menu; the C64 resets and the game starts (turbo is off while the EF3 heuristics are armed, `RESEARCH.md` 5.3).
* Writes to a real cartridge happen exactly once (Ultimax writes, flash command sequences): in Smart `4x`, write an EasyFlash `.crt` to an EF3 with EasyProg (or another flash tool), let it verify the flash content, then start the written program. Use a spare cartridge: a failed write sequence can leave the flash in an unusable state.
* A freezer (Action Replay, Retro Replay or Final Cartridge III): freeze and resume in turbo.
* IDE64 (Ultimax unmapped path).
* GMod2.
* A hardware REU with DMA (REU Grande or 1764): DMA forces turbo off.
* A hardware REU transfer that a write to `$FF00` starts (command register with the `$FF00` trigger, for example a small test program that sets up the transfer and then writes to `$FF00`), in Smart `4x`: the transfer starts and the data is correct.
* Every failure here is a bug to fix: real cartridges stay usable in turbo (decision L6 in `STATUS.md`).

### 4.5 Simulated cartridges and REU

* Bank-switch-heavy SIMCRT cartridges (EasyFlash, GMod2, Magic Desk) in `4x`.
* SIMREU on R3 and R6 in `4x`: a REU test program (for example the CMD REU test used in #259) and a REU game or demo (MJoergen's R3 concern).
* SIMREU together with SIMCRT.

### 4.6 Clocks and drift

* The 1541 drift tests and the programs of #2 (Input 64 1/1985) in `2x` / `3x` / `4x`, with flicker-free on and off: unchanged behavior expected.
* TOD accuracy (10 minutes against a stopwatch) with turbo `4x`, PAL and NTSC: same result as with turbo `Off`.

### 4.7 OSM and settings

* Summary line: `Model: PAL` (turbo `Off`), `Model: PAL C128 2x`, `Model: NTSC Smart 4x`.
* The `Turbo speed` block (headline, `2x` / `3x` / `4x` and the blank line above it) is hidden while turbo is `Off` and appears for `C128` and `Smart`; no view shows two blank lines in a row.
* Changing turbo mode or speed does not reset the C64 and takes effect immediately.
* PAL/NTSC switch with turbo on: the machine-mode reset happens, the turbo setting stays, the `$D030` bit is cleared.
* Config file persistence (decision L7): select `Smart` and `4x`, save, power cycle: both are restored.
* A config file copied from WIP-V6-A22 may carry a turbo setting (A22 had the turbo items selectable but inactive): check the `Model:` summary line after the first start with such a file.
