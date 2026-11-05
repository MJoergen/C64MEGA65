# Turbo modes for C64MEGA65: design specification

Binding specification for issue #87 (`WIP-V6-A22X1`, branch `turbo-mode`). Background and line references: `RESEARCH.md`; file map: `recon_map.md`; decisions L1-L10: `STATUS.md` section 1.1. Line numbers refer to `develop` at `55918e6` and the submodule at `650c6b5`.

## 1. Scope and invariants

The core offers the turbo modes of the MiSTer C64 core and nothing else: `Turbo mode` = `Off` / `C128` / `Smart`, `Turbo speed` = `2x` / `3x` / `4x` (L1). The following invariants must hold; every one of them is checked by simulation or review (section 7).

* **I1, turbo Off is unchanged:** with `Turbo mode` = `Off`, the C64 runs cycle-identically to `WIP-V6-A22`. Every change of this spec is inactive unless `turbo_m /= "000"` or a turbo menu bit is set.
* **I2, real cartridges at 1 MHz:** in hardware-cartridge mode, a CPU access to the expansion port (`ROML`, `ROMH`, Ultimax `ROMH`, Ultimax unmapped area, IO1, IO2) executes only at `CYCLE_CPUC` of a clean 1 MHz cycle, one in which the CPU has not run before (`io_enable = '1'`). The cartridge strobes, R/W low and the data drive of such an access appear at the port only in that cycle. The cartridge therefore gets the same window as with turbo `Off`: the CPU address reaches the port at `CPU1` (while PHI2 is low the port shows the VIC address), and the data must be valid about 410 ns later, at `CPUD` (`RESEARCH.md` 5.2). Every CPU write reaches the cartridge exactly once.
* **I3, I/O at 1 MHz:** VIC-II, SID, CIA and color-RAM accesses keep the existing `io_enable` rule.
* **I4, DMA means 1 MHz:** while any DMA is requested (`dma_req`), there are no turbo accesses.
* **I5, no clock changes:** turbo never changes `clk_main`, `clk32_speed` or the enables of VIC-II, CIA and SID.
* **I6, no reset:** changing turbo mode or speed never resets the C64 and takes effect within one 1 MHz cycle.
* **I7, saved like any setting:** the turbo items stay ordinary menu items, saved in the config file (L7); no menu line is added or removed, so every `C_MENU_*` index stays the same.

## 2. Core changes (submodule `CORE/C64_MiSTerMEGA65`)

Work on a local branch `turbo-mode` in the submodule. Comment style: `-- 11/5/26 by sy2002:` like the existing MEGA65 change notes; add every change to the list of MEGA65 changes in the file header of `rtl/fpga64_sid_iec.vhd`.

### 2.1 Port upstream `d6048db` ("Disable turbo while I/O access for better compatibility")

In `rtl/fpga64_sid_iec.vhd`, exactly as upstream:

```vhdl
signal cs_io        : std_logic;                                                -- declaration
cs_io <= cs_vic or cs_sid or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i;  -- next to IOE <= ioe_i; IOF <= iof_i; (lines 562-563)
if cs_io = '0' and dma_req = '0' and ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then  -- turbo decision, line 929
```

The term is a no-op, here and upstream: the decision samples `cs_io` at `EXT1` and `EXT5`, where `cpuHasBus = '0'`, and every term of `cs_io` is set only while `cpuHasBus = '1'` (`RESEARCH.md` section 4). The port is kept for upstream parity; I/O stays at 1 MHz through `io_enable`.

### 2.2 Close the cartridge timing gap (finding F2, invariant I2)

In the `cpu_cyc` assignment (lines 899-911) the `CYCLE_CPUC` term changes from `cs_ram` to `cs_turbo_eligible`:

```vhdl
(sysCycle = CYCLE_CPUC and (io_enable = '1' or cs_turbo_eligible = '1')) else '0';
```

Effect: RAM, character ROM, BASIC/KERNAL ROM and (in SIMCRT mode) the cartridge BRAM cache still run at `CPUC` after a turbo access; real-cartridge accesses wait for the next clean 1 MHz cycle. With turbo off, `io_enable` is always 1 at `CPUC`, so the term is unchanged (I1). Rewrite the comment block above `cpu_cyc` (it currently says that the `CPUC` clause stays on `cs_ram`) and the explanatory comment at `cs_turbo_eligible_o` in `rtl/fpga64_buslogic.vhd` so that both describe the clean-cycle rule. `ramCE` (line 896) keeps `cs_ram`.

### 2.3 Cartridge strobes, R/W and data drive only in clean cycles (core and `main.vhd`)

The clean-cycle rule of 2.2 decides when a cartridge access executes; this rule decides what the port shows while the access waits (`RESEARCH.md` 5.3, doubled writes). Requirements, in hardware-cartridge mode:

* A CPU access to the cartridge area that waits for the next clean cycle strobes nothing in the cycle in which it waits: no `ROML`, `ROMH`, IO1 or IO2. The Ultimax unmapped area has no strobe; a waiting access there shows its address as a read.
* Every waiting CPU write (cartridge area, I/O, `$FF00`, RAM) looks like a read at the port while it waits: R/W stays high, and the data bus behaves as for a read of that address (the FPGA mirrors internal data, or stays tri-stated for the cartridge area). The write reaches the port once, in the clean cycle in which it executes.
* In the clean cycle in which the access executes, strobe, R/W and data drive behave exactly as with turbo `Off`.
* In SIMCRT mode the BRAM cache serves `ROML`/`ROMH` in the turbo slots; nothing changes there. VIC-II fetches (Ultimax `ROMH` for the VIC) stay as they are.
* With turbo `Off` no access ever waits, so the port signals are unchanged (I1).

The implementation details (which select is gated with what, how `main.vhd` learns that an access waits) are documented in the code comments of `rtl/fpga64_buslogic.vhd`, `rtl/fpga64_sid_iec.vhd` and `main.vhd`.

### 2.4 `$FF00` writes are never turbo-eligible

A CPU write to `$FF00` runs only at `CYCLE_CPUC` of a clean 1 MHz cycle, in every mode and at every speed, so that a hardware REU set to the `$FF00` trigger sees the write, with R/W low, at a PHI2 falling edge (`RESEARCH.md` 5.3). The SIMREU recognizes the trigger in the same clean cycle. With turbo `Off` every write runs there anyway (I1).

### 2.5 No further core changes

`video_vicII_656x.vhd` (`$D030`) stays as is.

## 3. Wiring (`CORE/vhdl`)

### 3.1 `mega65.vhd`

* In the main clock domain, next to `c64_ntsc <= main_osm_control_i(C_MENU_MACHINE_NTSC);` (line 686): `c64_turbo_mode(0) <= main_osm_control_i(C_MENU_TURBO_C128)`, `c64_turbo_mode(1) <= main_osm_control_i(C_MENU_TURBO_SMART)`, `c64_turbo_speed <= "10"` when `C_MENU_TURBO_4X` is set, `"01"` when `C_MENU_TURBO_3X` is set, otherwise `"00"` (the encoding of `turbo_speed`). New signals are declared next to `c64_ntsc`.
* Pass both to `i_main` (around line 804). Replace the comment "turbo is not yet wired" (line 426).

### 3.2 `main.vhd`

* New ports next to `c64_ntsc_i`, documented in the same style: `c64_turbo_mode_i : in std_logic_vector(1 downto 0)` (bit 0 `C128`, bit 1 `Smart`, `"00"` = `Off`) and `c64_turbo_speed_i : in std_logic_vector(1 downto 0)` (`"00"` 2x, `"01"` 3x, `"10"` 4x).
* **Smart disk-activity detector** (new process, clock `clk_main_i`), MiSTer `disk_access` semantics: an edge on any of `c64_iec_clk_out`, `c64_iec_clk_in`, `hw_iec_clk_n_in` sets `turbo_disk_access` to 1 and restarts a counter of `clk_main_speed_i / 2` cycles (0.5 s); when the counter has expired, `turbo_disk_access` returns to 0. Check whether `iec_clk_n_i` is already synchronized to `clk_main_i` on its way in; if not, the detector uses its own two-flip-flop synchronizer for `hw_iec_clk_n_in` (the existing IEC paths stay untouched). The process is independent of the C64 resets. Interface contract for the bench (section 6): the detector is one clocked process whose first line is `-- [turbo_smart_iec_detector begin]` and whose last line is `-- [turbo_smart_iec_detector end]`; all its internal state (previous line values, counter) lives in process variables; it reads only `clk_main_i`, `clk_main_speed_i`, `c64_iec_clk_out`, `c64_iec_clk_in` and either `hw_iec_clk_n_in` (if already synchronous) or `hw_iec_clk_n_sync` (output of a separate two-flip-flop synchronizer with `ASYNC_REG`, outside the markers); it drives only `turbo_disk_access`.
* Core port map (lines 1248-1251): `turbo_mode => (c64_turbo_mode_i(1) and not turbo_disk_access) & c64_turbo_mode_i(0)`, with both bits additionally masked by the EF3 busy mask of 3.3; `turbo_speed => c64_turbo_speed_i`; `sim_crt_i` unchanged.
* RESET SEMANTICS block (lines 745-767): one sentence that changes of the turbo settings never reset the C64.

### 3.3 EF3 busy mask (`main.vhd`, `cartridge_heuristics.vhd`)

On R3, R3A and R4 the EF3 is recognized from a bus pattern that expects one CPU access per PHI2 falling edge (`RESEARCH.md` 5.3). Requirements:

* `cartridge_heuristics.vhd` reports whether a detection is in progress: from the write to `$DE00` until the heuristics have decided (EF3 detected or back to idle).
* While a detection is in progress, `main.vhd` turns the turbo off for both modes, `C128` and `Smart`; the change takes effect at the next turbo decision (`EXT1`/`EXT5`), like every turbo change (I6).
* The mask applies only in hardware-cartridge mode and only on the boards that use the heuristics (R3, R3A, R4); in SIMCRT mode and on R5/R6 it is inactive.
* The EF3 menu before the detection and the game after its reset run in turbo as selected.
* Side effects, accepted: the pause clears both mode bits, so in `C128` mode `$D030` reads `$FF` while the pause lasts (a few µs after a `$DE00` write, at most about 10 µs). Every `$DE00` write of a real cartridge in 16K mode on R3/R3A/R4 starts such a pause, so cartridges that switch banks very often (EasyFlash, Ocean, Magic Desk) gain less from turbo on these boards.

## 4. OSM (`config.vhd`, `menu_test.py`)

* Remove the "not yet wired" comments of the turbo block (lines 460, 644, 645).
* Hide the `Turbo speed` block while `Turbo mode` = `Off`, as MiSTer does: mark the `Turbo speed` headline, its three items and one adjacent separator line with `OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2)`, choosing the separator so that the visible menu has no double blank line in either state. First confirm from `config.vhd` and the dependency documentation that headlines and separator lines can be dependent and that the mother group may live in the same submenu; if any of this is not supported cleanly, leave the block visible and report why.
* Update `M2M/rom/tests/menu_test.py` (lines 77, 130-139, 1815-1820) accordingly and run it in verify and run mode. No change to `m2m-rom.asm` and `osm_const.asm` (indices unchanged, I7); confirm that `osm_const.asm` would regenerate identically.

## 5. Version and documentation

* `CORE/vhdl/config.vhd` line 71: `WIP-V6-A22X1`.
* `VERSIONS.md`: a "Turbo modes" bullet after the NTSC bullet in "New Features", same style: where to find it, the three modes in one sentence each, that real cartridges stay usable, GitHub issue #87.
* `doc/inofficial.md`: row `WIP-V6-A22X1` directly after `WIP-V6-A22`, date and commit `TBD` (filled in at release).
* `tests/README.md`: new section `Version WIP-V6-A22X1 - TBD` above `Version WIP-V6-A22 - TBD`, with the hardware items of `doc/dev-turbo/TEST-PLAN.md` section 4 as `@TODO` bullets (keep the **(community)** marks).
* `AGENTS.md` section 9: a debugging row for turbo (`fpga64_sid_iec.vhd` `cpu_cyc` and turbo decision, `main.vhd` Smart detector, `doc/dev-turbo/`).
* Markdown must render in Marked 2 with MathJax: every `$` outside code spans or fences escaped or, better, inside backticks; no bare `==` in prose; American English; paragraphs as long lines.

## 6. Simulation (`CORE/vhdl/test/tb_turbo/`)

Follow the pattern of `CORE/vhdl/test/tb_ntsc/` (`run.sh`-style runner printing `RESULT: PASS` or `RESULT: FAIL ...`, exit status 0 only on PASS, build products in a temporary directory, GHDL or nvc). Required:

* **Core bench:** `fpga64_sid_iec` with VHDL stubs for the Verilog/SystemVerilog components (`mos6526`, `sid_top`), a 64 KB RAM model on the RAM port, and a cartridge model that can act as a real cartridge (hardware mode, data served with the main.vhd pipeline latency of one output and two input register stages, see `RESEARCH.md` 5.2) or as SIMCRT. A small 6502 test program (for example booted from an Ultimax cartridge) exercises RAM, I/O, cartridge ROM fetches and cartridge writes directly after RAM accesses, `$FF00` writes, and `$D030`. The EF3 check (f) adds `cartridge_heuristics.vhd` with the turbo mask of 3.3 and replays the bus pattern of the EF3 menu.
* **Checks:** I1 and S1-S11 of `TEST-PLAN.md` section 2, in detail: (a) I1 by comparing a cycle trace of the baseline sources and the new sources with turbo `Off`: `sysCycle`, CPU address, write enable, `enableCpu` and every cartridge-facing signal (address, data and its drive, R/W, `ROML`, `ROMH`, Ultimax `ROMH`, Ultimax unmapped area, IO1, IO2, PHI2, BA), identical; (b) F2 reproduced on the baseline sources and gone with the new sources (every real-cartridge access in a clean cycle, CPU address at the port from `CPU1`, data sampled about 410 ns later, as with turbo `Off`); (c) `d6048db` shown to be a no-op; (d) cartridge writes exactly once per CPU write in all speeds (`Off`, `2x`, `3x`, `4x`), including writes that wait after a turbo access: one strobe with R/W low at one PHI2 falling edge, and in the waiting cycle no strobe, R/W high and no data drive (2.3); (e) a `$FF00` write is at the port, with R/W low, at a PHI2 falling edge in all speeds (2.4); (f) the EF3 detection succeeds in turbo: the menu fingerprint and the reset request in Smart `4x`, hardware-cartridge mode, with the heuristics active, lead to the EF3 reset as with turbo `Off` (3.3).
* **Baseline sources** come from `git show` of `55918e6` / `650c6b5`, so the bench does not depend on the state of the working tree.
* **Smart detector bench:** tests the process copied into the bench; the runner extracts the process between the marker lines from `CORE/vhdl/main.vhd` and fails if the copy differs. Checks: edge on each input, 0.5 s timeout, retrigger, idle lines stay quiet.
* **Static analysis:** analyze the changed `main.vhd` and `mega65.vhd` (and the changed submodule files) with GHDL or nvc, differential against the baseline: no new errors or warnings (recipe in the memory note `project_ghdl_local_analysis.md`).

## 7. Acceptance

* All benches and `menu_test.py` print PASS.
* Independent adversarial review (RTL and integration) without unresolved findings of severity high.
* Nothing is committed and nothing is pushed until the maintainer approves; afterwards the submodule commit comes first, then the pointer bump with the main-repo changes. No `Co-Authored-By: Claude` trailer.
* The maintainer builds R3 and R6 (later R4/R5) and runs the hardware tests; community testers get asked on GitHub (L10).
