# Turbo-mode benches (issue #87)

Simulation benches for the turbo modes (`doc/dev-turbo/TURBO-SPEC.md` section 6, `doc/dev-turbo/TEST-PLAN.md` section 2). They run the real C64 core (`CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd` with T65, VIC-II and PLA) with nvc, compare the baseline sources (`55918e6`, submodule `650c6b5`, taken with `git show`, so the state of the working tree does not matter) against the working tree, and test the Smart disk-activity detector of `CORE/vhdl/main.vhd`.

## How to run

```
CORE/vhdl/test/tb_turbo/run.sh [baseline|d6048db|new|smart|static|all] [--keep]
```

* `baseline`: core bench on the baseline sources plus the latency mutants. Expects every check to pass and finding F2 to be reproduced.
* `d6048db`: baseline versus baseline plus upstream commit `d6048db` (S8).
* `new`: core bench on the working tree plus the latency mutants; F2 must be gone, and the per-clock trace with turbo `Off` must equal the baseline trace (I1). Runs the baseline set as reference.
* `smart`: Smart detector bench.
* `static`: GHDL analysis, working tree versus baseline.
* `all` (default): everything.
* `--keep`: keeps the build directory (logs, compressed traces) and prints its path.

The runner prints the results of every simulation and ends with `RESULT: PASS` or `RESULT: FAIL ...`; the exit status is 0 only on PASS. Requirements: nvc 1.21 (`/usr/local/bin/nvc`, the core bench uses VHDL-2008 external names, which GHDL 5.1.1 cannot elaborate), GHDL 5.1.1 for `static`, python3. `JOBS` (default and maximum 2) sets the number of parallel simulations. Runtimes on this machine: `baseline` about 2 minutes, `d6048db` about 3 minutes, `new` about 3 minutes, `all` about 4 minutes, `smart` 1 second, `static` 15 seconds.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: exports and patches the sources, builds them, runs the scenarios, evaluates |
| `evaluate.py` | Scenario list (single source of truth) and the verdicts per source set |
| `tb_turbo_core.vhd` | Core bench: DUT, RAM, `main.vhd` cartridge glue, cartridge model, monitors |
| `tb_turbo_stubs.vhd` | VHDL stand-ins for the Verilog components `mos6526` and `sid_top` |
| `gen_cart.py` | Builds the 16 KB Ultimax test cartridge (contains a small 6502 assembler) |
| `tb_turbo_smart.vhd` | Smart detector bench with a verbatim copy of the detector process |

## Core bench

### What is simulated

The DUT is the complete `fpga64_sid_iec` with the real T65, VIC-II, `fpga64_buslogic` (PLA, BASIC/KERNAL/character ROMs, custom Kernal RAM) and color RAM; CIA and SID are register-level stubs with the bus timing of `mos6526.v`. Around it the bench reproduces the data paths of `mega65.vhd` and `main.vhd`, with the latencies read from the RTL (counted in `clk_main` cycles from "address changes at the core's `ramAddr`" to "valid data at `ramDin`"):

| Source | RTL | Read latency | In the bench |
|---|---|---|---|
| C64 RAM | `mega65.vhd` `c64_ram`: `dualport_2clk_ram` / `tdp_ram`, port A on `clk_main`, no address latch, read-first; `main.vhd` `cpu_data_in_proc` combinational | 1 | same structure |
| RAM writes | `wren_a` = `ramCE and ramWE` (`c64_ram_we_o`), `data_a` = `ramDout`, all combinational from the core | written at the end of the `cpu_cyc` state, in turbo the first clock after the address change | same; every CPU write is checked |
| BASIC, KERNAL (standard, GS, Japan) and character ROM | `dprom` inside `fpga64_buslogic` | 1 | real RTL (DUT) |
| Custom Kernal | `dualport_2clk_ram` port A inside `fpga64_buslogic` | 1 | real RTL, loaded through the QNICE port at reset |
| SIMCRT ROML / ROMH | `sw_cartridge_wrapper.vhd` `crt_lo_ram` / `crt_hi_ram`: `tdp_ram`, 16 bit, address cache slot and `crt_addr_bus_o(12 downto 1)`; byte selected by the live `crt_addr_bus_o(0)` in `cpu_data_in_proc` | 1 | same structure |
| SIMCRT cartridge RAM, IO1/IO2 RAMs, RR-Net MK3 ROMs | `tdp_ram` with the live address | 1 | not modeled separately (same latency as ROML/ROMH) |
| Hardware cartridge | `cart_output_pipeline_proc` (1 register), cartridge, `cart_input_pipeline_proc` (`cart_in_d_q`, 1 register), then combinational (`cart_in_data`, `cpu_data_in_proc`); the CPU's sampling flip-flop is the second input stage | pins plus access time | same structure, cartridge with access time `T_ACC` |

The `main.vhd` glue of the bench (cartridge-port pipeline, strobes, data-bus direction, `exp_port_we`, `cpu_data_in_proc`, the turbo-mode gating with `turbo_ef3_pause`) consists of verbatim copies of `CORE/vhdl/main.vhd` between `-- [main.vhd copy begin]` and `-- [main.vhd copy end]`, written with the `main.vhd` signal names (aliases in the bench). `run.sh` fails if one of these blocks no longer appears in the current `main.vhd` as a contiguous block (comments and whitespace aside), so the bench cannot drift from the RTL. Sources without the core output `cpu_deferred` and the `cartridge_heuristics` output `busy_o` (the baseline) leave both at `'0'`; the copied glue then equals the baseline `main.vhd` (`exp_port_we` = `c64_ram_we`, no EF3 pause). The board (`G_BOARD`) is part of the scenario.

The latency budget in turbo: the CPU address changes at the clock edge of an `enableCpu`, the next turbo access samples four clocks later, so a source may have up to 3 register stages. All sources of our port have 1. The mutants prove that the read checker sees stale data: RAM with 3 stages passes at 4x, RAM with 4 stages and a SIMCRT cache with 4 stages fail.

The hardware cartridge model drives the ROM byte only once address and strobes at the pins have been stable for `T_ACC`; before that it drives the inverted byte. Writes are latched when PHI2 falls; a latched write in a cycle without a CPU write access to the cartridge counts as a phantom write. The cartridge has 8 KB ROML, 8 KB ROMH (Ultimax boot), a RAM at `$1000-$10FF` and a pattern in the rest of the Ultimax unmapped area (IDE64-like), registers at IO1 (`$DE00` bit 7 switches the cartridge off, so that BASIC, KERNAL and character ROM become visible; `$DE02` bit 0 selects 16K mode instead of Ultimax) and a 256-byte RAM at IO2. The real `CORE/vhdl/cartridge_heuristics.vhd` of the selected source set is connected as in `main.vhd`. `/GAME` comes back through the input register like on the real port.

The bench also contains two simulator patches, applied identically to every source set: `preCycle <= sysCycleDef'succ(preCycle)` is guarded (nvc evaluates `'succ` of the last value before the following `if` overrides it), and `rfsh_cycle` gets its FPGA power-up value `"00"` (otherwise the state machine never starts in simulation).

### Test program

`gen_cart.py` builds an Ultimax cartridge whose boot code copies a program to RAM `$0200` and runs it. The program reports phases by writing to `$0FF0`; the bench applies the turbo settings when phase 1 is reached, so the boot code runs at 1 MHz.

| Phase | Content |
|---|---|
| 1 | booted; C128 mode: `$D030` = 1 |
| 2 | RAM-only loop (S1) |
| 3 | VIC, SID, CIA1, CIA2, color RAM, IO1 and IO2 accesses with read-back (S2) |
| 4 | `$D030` reads, off, on through the mirror `$D070` (S4) |
| 5 | RAM loop; the bench requests DMA for 20 cycles from the middle of a cycle; Smart: the bench switches turbo off and on four times (S3, S5, I6) |
| 6 | cartridge off: BASIC, KERNAL and character ROM (`$01` = `$33`) read directly after RAM accesses; four writes to `$FF00` (hardware REU trigger) with different cycle alignment |
| 7 | ROML, ROMH and Ultimax unmapped reads directly after RAM accesses, unmapped writes, absolute writes to the cartridge RAM (`$1080`) and to ROML (`$8123`, flash on real cartridges) directly after RAM accesses (F2 data path, S7) |
| 8 | EasyFlash 3 menu tail in 16K mode, run from RAM at `$0100`: `STA $DE00`, `LDA #`, `STA $DE0E`, `LDA $13` (the fingerprint of `CORE/vhdl/cartridge_heuristics.vhd`) |
| 9 | code executed from cartridge ROMH that accesses zero page (F2 opcode fetches) |

In C128 mode the bench finally resets the C64 and checks the `$D030` bit and the first `$D030` read after the reset.

### Scenarios and checks

Scenarios (see `evaluate.py`): `off_hw`, `off_sim`, `c128_2x_hw`, `c128_3x_hw`, `c128_4x_hw`, `c128_2x_hw250` (250 ns cartridge), `smart_2x_hw`, `smart_4x_hw`, `c128_4x_sim`, `smart_3x_sim` on board R3 (EF3 detection and its turbo pause active in hardware-cartridge mode), `c128_4x_hw_r6` on board R6; hardware cartridges with 150 ns access time unless noted; mutants `mut_ram3`, `mut_ram4`, `mut_crt4`.

| Check | Expected |
|---|---|
| S1 | in the RAM loop every 1 MHz cycle has exactly 1/2/3/4 accesses in `CPUC` / `CPU4`+`CPUC` / `CPU4`+`CPU8`+`CPUC` / all four |
| S2 | every access the PLA decodes as VIC, SID, color RAM, CIA or IO1/IO2 happens at `CPUC` with no CPU access before it in the same cycle |
| S3 | in every cycle whose `EXT5` decision saw `dma_req` there is no CPU access and `turbo_m = "000"`; turbo resumes afterwards |
| S4 | `$D030` reads `$FF,$FE,$FF` in C128 mode and `$FF` otherwise; the cycle after a write shows the new turbo state; a reset clears the bit (`$FE` after reset) |
| S5, I6 | Smart: a change of `turbo_mode(1)` shows in the same or the next 1 MHz cycle |
| S6 (F2) | baseline: real-cartridge accesses directly after turbo accesses (short pin time, wrong data with a 150 ns cartridge at 3x/4x and with a 250 ns cartridge at 2x); new: every real-cartridge access at `CPUC` of a clean cycle, CPU address set before the cycle, pins stable 14 clocks as at 1 MHz, no wrong data, no short write setup, the program completes |
| S7 | SIMCRT ROM reads run in turbo states and return correct data |
| S8 | `cs_io` (the condition of `d6048db`) is never 1 at the `EXT1`/`EXT5` decision; the per-clock traces of baseline and baseline plus `d6048db` are identical |
| I1 | per-clock trace with turbo `Off`, from the release of the power-up reset on: new equals baseline (before that, registers that the FPGA initializes to 0 are `'U'` in simulation). Fields: state index, CPU address, write enable, `enableCpu`, `dma_active`, RAM port, the core outputs `romL`, `romH`, `UMAXromH`, `UMAXnomap`, `IOE`, `IOF`, PHI2, BA, the cartridge port as `main.vhd` drives it (registered address, `/ROML`, `/ROMH`, `/IO1`, `/IO2`, R/W, `cart_out_sel`, data direction, outgoing data, `cart_in_data`), the EF3 flag, and `exp_port_we` (versus `c64_ram_we` on the baseline: the SIMREU write input is unchanged) |
| (a), I2 | every CPU write to the cartridge (Ultimax ROML, ROMH, unmapped area, IO1, IO2) is one write cycle at the pins (R/W low when PHI2 falls, decoded by the cartridge), none is missing, there is no write cycle without a CPU write (phantom), the latched address and data equal the CPU's, and the FPGA drives the data bus in the clock before and the clock after PHI2 falls |
| read pulses | no `/ROML` or `/ROMH` pulse at the pins without a CPU read; Ultimax unmapped addresses on the bus without a CPU access (no strobe) are counted separately |
| (b) | every CPU write to `$FF00` is on the pins (address, R/W low) when PHI2 falls (hardware REU trigger); baseline in turbo: must be reproduced as broken |
| (c) | the EF3 fingerprint is detected by `cartridge_heuristics.vhd` on R3 in every speed; baseline in turbo: must be reproduced as not detected; the EF3 turbo pause is never active on R6 and in SIMCRT mode |
| I5 | VIC, CIA and SID enables at their fixed states |
| data | every CPU read is compared against the reference of its source (RAM, BASIC/KERNAL, character ROM, cartridge, SIMCRT), every CPU RAM write must reach the RAM during its access |

## Expected results

### Baseline sources

Every check of the sets `baseline` and `d6048db` passes, i.e. F2, (b) and (c) are reproduced on the baseline (the R6 scenario behaves like R3 there):

| Scenario | Cartridge accesses after a turbo access in the same cycle (`CPU0`/`CPU4`/`CPU8`) | Pin time before the data is sampled | Wrong reads | `$FF00` writes not on the pins | EF3 detected |
|---|---|---|---|---|---|
| any mode, normal 1 MHz access | none | 444 ns (14 clocks) | 0 | 0 of 4 | yes |
| C128 2x, 150 ns | 0 / 294 / 0 | 190 ns after `CPU4` | 0 | 3 of 4 | no |
| C128 2x, 250 ns | 0 / 2142 / 0 | 190 ns | 2138, program crashed in phase 9 | 3 of 4 | no |
| C128 3x, 150 ns | 0 / 426 / 760 | 190 ns, 63 ns after `CPU8` | 757, crashed in phase 9 | 2 of 4 | no |
| C128 4x, 150 ns | 518 / 338 / 260 | 317 ns after `CPU0`, 190 ns, 63 ns | 260, crashed in phase 9 | 3 of 4 | no |
| Smart 4x, 150 ns | 520 / 338 / 261 | 317 / 190 / 63 ns | 261, crashed in phase 9 | 3 of 4 | no |

The time a real cartridge gets for a normal access is 14 clocks (about 444 ns), not a full microsecond: during the first half of each cycle the address pins carry the VIC-II address, and the CPU address with `/ROML` or `/ROMH` reaches the pins one clock after `CYCLE_CPU0`. S1 to S5, S7 and (a) pass on the baseline (cartridge writes after a turbo access execute once, at `CPUC`, but with the short setup time of F2); RAM, ROM and character ROM reads and RAM writes in turbo states are all correct at the real one-clock latencies (up to 8172 RAM reads and 1300 RAM writes in turbo states per run). The `$FF00` write is lost for a hardware REU when it executes in a turbo state, because PHI2 falls only once per 1 MHz cycle and the pins then show a later access. The EF3 fingerprint fails in turbo because the accesses to `$0108`, `$0109` and `$0013` no longer fall on three consecutive PHI2 edges. `cs_io` was never 1 at a turbo decision in any scenario, because `cpuHasBus` is 0 during `EXT0`-`VIC3`, so `fpga64_buslogic` decodes no I/O chip select there: upstream `d6048db` has no functional effect in this core.

### Working tree (turbo implementation)

`run.sh all` passes: 427 of 427 core-bench checks (sets `baseline`, `d6048db`, `new`, mutants on the working tree), the Smart detector bench and the static analysis. On the working tree:

| Scenario | Cartridge accesses after a turbo access | Pin time | Wrong reads | Phantom / missing cartridge writes | `/ROML`, `/ROMH` pulses without a CPU read | Unmapped addresses without a CPU access | `$FF00` writes not on the pins | EF3 detected | EF3 pause clocks |
|---|---|---|---|---|---|---|---|---|---|
| R3 Off (hardware cartridge) | 0 | 444 ns | 0 | 0 / 0 | 0 | 0 | 0 of 4 | yes | 303 |
| R3 C128 2x, 3x, 4x, Smart 2x, 4x (150 ns) | 0 | 444 ns | 0 | 0 / 0 | 0 | 66 to 68 | 0 of 4 | yes | 303 |
| R3 C128 2x, 250 ns | 0 | 444 ns | 0 | 0 / 0 | 0 | 68 | 0 of 4 | yes | 303 |
| R6 C128 4x | 0 | 444 ns | 0 | 0 / 0 | 0 | 68 | 0 of 4 | no (no pause on R6) | 0 |
| SIMCRT Off, C128 4x, Smart 3x | n/a | n/a | 0 | n/a | 0 | 0 | 0 of 4 | no (detection off) | 0 |

Every program completes in every scenario, S1 to S5, S7, I5 and the data checks pass as on the baseline, the latency mutants are detected, and the I1 traces with turbo `Off` are identical to the baseline (622,546 and 623,954 clocks, including `exp_port_we` against the baseline `c64_ram_we`). The remaining unmapped addresses without a CPU access are the Ultimax unmapped accesses that wait for the next clean cycle; they carry no strobe and, with R/W held high by `exp_port_we`, no write. The EF3 pause (303 clocks per run on R3) is the detection window after each write to `$DE00`; with turbo `Off` it has no effect.

## Smart detector bench

`run.sh smart` compares the process between `-- [turbo_smart_iec_detector begin]` and `-- [turbo_smart_iec_detector end]` in `CORE/vhdl/main.vhd` with the copy between `-- BEGIN COPY` and `-- END COPY` in `tb_turbo_smart.vhd` (whitespace aside) and fails if they differ; if the markers are missing it reports "not yet implemented". The bench runs with `clk_main_speed_i` = 1000 and 777 and checks: idle lines (high from power-up, later low) never set `turbo_disk_access`; a falling and a rising edge on each of `c64_iec_clk_out`, `c64_iec_clk_in` and the hardware IEC clock set it with the next clock edge and keep it for `clk_main_speed_i / 2` plus one clocks; edges every 0.6 timeouts keep it set without a gap; a one-clock glitch and simultaneous edges set it. Two mutants (timeout `/ 4`, hardware IEC clock not watched) must be rejected. `hw_iec_clk_n_in` and `hw_iec_clk_n_sync` are both driven by the stimulus; the two-flip-flop synchronizer in front of `hw_iec_clk_n_sync` adds two clocks for the real pin.

## Static analysis

`run.sh static` analyzes the core files, `main.vhd` and `mega65.vhd` with GHDL for the baseline and for the working tree and compares the diagnostics without line numbers. `main.vhd` is checked against the real `fpga64_sid_iec` entity and `mega65.vhd` against the `main` entity, so new ports and port maps are covered; the remaining diagnostics are "unit not found" for sub-entities that are not analyzed. GHDL rejects case statements on `std_logic_vector` without `others` (Vivado accepts them), so `fpga64_rgbcolor` is analyzed as entity only and the `turbo_speed` case gets `others` instead of `"11"`, on both sides.
