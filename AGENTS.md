# C64MEGA65 — Project Guide for Coding Agents

This file is the cold-start brief for coding agents. Read it first; it covers what this project *is*, what its conventions look like, and where to find things — so you can spend context on the task instead of rediscovering the layout.

---

## 1. What is this project?

**C64MEGA65** is a port of the **MiSTer C64 core** (a Commodore 64
re-implementation in HDL) to the **MEGA65** computer, using the
**MiSTer2MEGA65 (M2M)** porting framework and **QNICE-FPGA** as the on-board
helper CPU.

### Background concepts (brief)

- **Commodore 64 (C64)**: 8-bit home computer (1982), MOS 6510 @ ~1 MHz, 64 KB
  RAM, VIC-II video, SID audio. Best-selling personal computer ever.
- **MEGA65**: Modern open-source recreation/successor of the unreleased
  Commodore 65, built around a Xilinx Artix-7 FPGA, with native MEGA65 keyboard,
  HDMI + analog VGA, two SD slots, joystick & expansion (cartridge) ports,
  HyperRAM, optional SDRAM on newer revisions. Ships as a real product.
- **MiSTer**: Open-source FPGA platform on the Intel-based Terasic DE10-Nano
  board. Hosts hundreds of "cores" that recreate retro systems. Cores are
  written in Verilog/VHDL and follow MiSTer conventions (clk_sys, ioctl_*,
  sd_lba, HPS communication, etc.).
- **MiSTer C64 core**: The reference C64 implementation maintained by the
  MiSTer community (origin: Peter Wendrich's FPGA64). Highly compatible.
- **MiSTer2MEGA65 (M2M)** — https://github.com/sy2002/MiSTer2MEGA65
  — framework that adapts MiSTer cores to the MEGA65's Xilinx FPGA, hardware,
  and conventions. **C64MEGA65 is the reference implementation of M2M.**

### Authorship

- MJoergen and sy2002 (port + framework, since 2022).
- paich64 (Amokphaze101) — testing / QA.
- Kugelblitz360 — user docs at https://c64.mega65.org.
- License: GPL v3.

### Source authority

Several MiSTer2MEGA65 wiki sub-pages have historically been marked WIP/@TODO.
For QNICE, virtual drives, OSM, and MiSTer-core integration, prefer this
project guide and the actual source code over upstream wiki text when they
disagree.

---

## 2. Repository layout

```
/
├── README.md, FAQ.md, ROADMAP.md, VERSIONS.md, AUTHORS, CONTRIBUTING.md
├── CORE/                  ← This core: C64-specific RTL, project files, QNICE ROM
│   ├── CORE-R{3,4,5,6}.xpr  Vivado project files, one per MEGA65 board revision
│   ├── CORE-R{3,4,5,6}.{cache,hw,runs,sim,tcl}  Vivado runtime / generated dirs
│   ├── CORE.xdc           core-specific timing/pin constraints
│   ├── run_vivado_r{3,4,5,6}.sh   open Vivado on the right project
│   ├── load_bitstream.sh, debug.tcl
│   ├── ram_init.{hex,py}  initial RAM contents helper
│   ├── vhdl/              ← C64-side VHDL (top of port, NOT the MiSTer core itself)
│   │   ├── mega65.vhd     TOP "MEGA65_Core" entity glue: clocks, QNICE devices,
│   │   │                  CDC, REU/CRT HyperRAM paths, OSM bit decoding
│   │   ├── main.vhd       Main-clock-domain wrapper around the MiSTer core
│   │   │                  (instantiates fpga64_sid_iec, REU, drives, etc.)
│   │   ├── clk.vhd        MMCM clock generation (PAL/NTSC, HDMI flicker-free)
│   │   ├── config.vhd     OSM/help/welcome text + OPTM_GROUPS menu structure
│   │   ├── globals.vhd    Constants: clock speeds, device IDs, vdrives, ROMs
│   │   ├── keyboard.vhd   MEGA65 keyboard → C64 CIA matrix (replaces MiSTer PS/2)
│   │   ├── cartridge*.vhd, crt_loader/parser/cacher.vhd, sw_cartridge_*.vhd
│   │   │                  Software cartridge (.crt) handling — MEGA65-specific
│   │   │                  bank cache in BRAM (HyperRAM is too slow for direct exec)
│   │   ├── reu_mapper.vhd REU → HyperRAM Avalon bridge
│   │   └── prg_loader.vhd .prg autostart logic
│   ├── m2m-rom/           ← QNICE assembly: the "Shell" firmware (on-screen menu,
│   │   │                    file browser, mounting, ROM/cartridge loading)
│   │   ├── m2m-rom.asm    entry; pulls in M2M/rom/main.asm + shell.asm + callbacks
│   │   │                  (FILTER_FILES, SUBMENU_SUMMARY, etc.)
│   │   ├── globals.asm, osm_const.asm, shell_fhandles.asm, shell_fh_ptrs.asm
│   │   ├── make_rom.sh    builds m2m-rom.rom (consumed by qnice.vhd)
│   │   └── synth_pre.tcl  Vivado pre-synthesis hook
│   └── C64_MiSTerMEGA65/  ← UNMODIFIED-ish MiSTer C64 core (git submodule-ish drop)
│       ├── c64.sv         original MiSTer top (we don't use it as top here)
│       └── rtl/           the actual MiSTer core RTL:
│                          fpga64_sid_iec.vhd (THE C64), fpga64_buslogic.vhd
│                          (PLA+ROMs+memmap), fpga64_keyboard.vhd, cpu_6510.vhd,
│                          mos6526.v (CIA), video_vicII_656x.vhd (VIC-II),
│                          sid/, t65/, iec_drive/, reu.v, cartridge.v, opl3/,
│                          rtcF83.sv, sdram.v, c1351.v (mouse), c1530.vhd (tape)
├── M2M/                   ← MiSTer2MEGA65 framework (board-side; core-independent)
│   ├── MEGA65-R{3,4,5,6}.xdc   per-board pin constraints
│   ├── common.xdc          timing constraints
│   ├── vhdl/
│   │   ├── top_mega65-r{3,4,5,6}.vhd   FPGA top entities, board-specific I/O;
│   │   │                  instantiates framework.vhd AND CORE/vhdl/mega65.vhd
│   │   ├── framework.vhd   HAL: instantiates QNICE, AV pipeline, controllers,
│   │   │                  resets
│   │   ├── reset_manager.vhd, clk_m2m.vhd, ram_init.vhd, m2m_keyb.vhd
│   │   ├── qnice_wrapper.vhd, qnice_arbit.vhd, qnice_csr.vhd
│   │   │                    QNICE bus glue, MMIO arbitration, status registers
│   │   ├── qnice2hyperram.vhd  let QNICE access HyperRAM
│   │   ├── vdrives.vhd     virtual disk drive / mount engine (RAM-cached image,
│   │   │                  talks to MiSTer-style sd_lba/sd_buff/img_mounted iface)
│   │   ├── tdp_ram.vhd, 2port2clk_ram*.vhd  shared dual-port RAM building blocks
│   │   ├── cdc_*.vhd, debounce*.vhd, hdmi_flicker_free.vhd, axi_fifo*.vhd
│   │   ├── av_pipeline/   ← video pipeline (read this dir for any video issue):
│   │   │                  ascal.vhd (the MiSTer scaler — input → HyperRAM →
│   │   │                  HDMI), analog_pipeline.vhd, digital_pipeline.vhd,
│   │   │                  vga_controller.vhd, vga_osm.vhd, video_overlay.vhd,
│   │   │                  video_modes_pkg.vhd, frame_buffer.vhd, crop.vhd
│   │   ├── memory/        Avalon arbiters, caches, FIFOs (avm_*.vhd)
│   │   ├── controllers/   HDMI/, M65/ (keyboard etc.), MiSTer/, SDRAM/, hyperram/
│   │   ├── i2c/, democore/, QNICE/ (qnice.vhd, qnice_mmio.vhd, sdmux.vhd)
│   ├── QNICE/             ← QNICE-FPGA submodule (https://github.com/sy2002/QNICE-FPGA)
│   │   ├── monitor/       QNICE OS "Monitor" sources + monitor.rom
│   │   ├── assembler/     qasm + linker
│   │   ├── tools/make-toolchain.sh   builds the QNICE toolchain
│   │   ├── vhdl/          QNICE CPU + peripherals VHDL (we synthesize a subset)
│   │   ├── c/, emulator/, dist_kit/, doc/, demos/, test_programs/, qbin/, hw/
│   ├── rom/               ← M2M Shell sources (QNICE assembly), included by
│   │                        CORE/m2m-rom/m2m-rom.asm:
│   │                      main.asm, shell.asm, menu.asm, options.asm,
│   │                      selectfile.asm, dirbrowse.asm, vdrives.asm,
│   │                      keyboard.asm, screen.asm, whs.asm,
│   │                      filters.asm, gencfg.asm, llist.asm, tools.asm,
│   │                      coreinfo.asm, crts-and-roms.asm, sysdef.asm, strings.asm
│   ├── tools/             make_config.sh, optm_heap.py, bin2qnice.py, mover.sh
│   ├── font/, video_filters/
├── doc/                   ← Internal developer notes (NOT the user's guide)
│   ├── developer.md       BUILD INSTRUCTIONS — start here for build flow
│   ├── clock_reset.md     clock domains and reset semantics
│   ├── PLA.md             PLA logic fixes vs. MiSTer
│   ├── cartridges.md, hdmi.md, retrotubes.md, jiffy.md, RTC.md,
│   ├── speed.md, graphics.md, models.md, inofficial.md
│   └── GEOS_WITH_THE_C64_CORE.pdf, c64.jpg, demopics/
├── tests/                 demos.md, carts.md, sidtests/, platest/, V2.15 suite
└── bin/                   pre-built .cor / .bit per release
```

---

## 3. Architecture

### 3.1 Layered view

```
        ┌────────────────────────────────────────────────────────────┐
        │  M2M/vhdl/top_mega65-rX.vhd     (one per board revision)    │
        │  Pin I/O, board-specific glue; instantiates BOTH:           │
        │                                                             │
        │   ├── M2M/vhdl/framework.vhd    (HAL: QNICE, AV pipeline,   │
        │   │     ├── qnice + shell ROM     reset mgr, controllers,   │
        │   │     ├── av_pipeline (ascal,   keyboard, joys, SD, etc.) │
        │   │     │   analog/digital)                                 │
        │   │     ├── reset_manager                                   │
        │   │     └── HyperRAM / SDRAM ctrl                           │
        │   │                                                         │
        │   └── CORE/vhdl/mega65.vhd  (entity MEGA65_Core)            │
        │        ├── clk.vhd (MMCMs for core+video)                   │
        │        ├── config.vhd (menu/help text → ROM)                │
        │        ├── sw_cartridge_wrapper / crt_loader/cacher         │
        │        ├── prg_loader                                       │
        │        └── main.vhd  (entity main; main_clk domain)         │
        │             ├── keyboard.vhd (MEGA65 → CIA matrix)          │
        │             ├── reu_mapper                                  │
        │             ├── fpga64_sid_iec  ← THE C64 (MiSTer)          │
        │             ├── reu (Verilog), rtcF83, opl3, ...            │
        │             ├── iec_drive (simulated 1541)                  │
        │             └── cartridge.vhd (.crt logic)                  │
        └────────────────────────────────────────────────────────────┘
```

**Key separation (this is the M2M philosophy):**
- `CORE/` is core-dependent and **board-independent**.
- `M2M/` is core-independent and **board-dependent**.
- The contract between them is the entity `MEGA65_Core` declared in
  `CORE/vhdl/mega65.vhd`.

### 3.2 mega65.vhd — the top of the port

Entity `MEGA65_Core` (CORE/vhdl/mega65.vhd). It exposes ports grouped by clock
domain (heavy commenting in the file marks each section):

- **QNICE clock domain** — connects to QNICE's MMIO bus. Outputs OSM/video
  config (DVI/HDMI, scandoubler, ascal_mode, retro15kHz, csync, etc.) and
  receives `qnice_osm_control_i` (the menu state) and `qnice_gp_reg_i`. Also
  exposes `qnice_dev_*` for core-specific devices (RAM, CRT cache, mount
  buffer, kernel ROMs — see `globals.vhd` `C_DEV_*` constants).
- **HyperRAM clock domain (`hr_clk`)** — Avalon master for SIMCRT (cartridge
  bank cache backing store) and SIMREU. `hr_high_i / hr_low_i` from M2M tell
  us whether the core is faster/slower than the HDMI fifo level (drives the
  dynamic flicker-free clock-switching, see §3.5).
- **Video clock domain** — RGB + HS/VS/blanks, plus `video_ce_o` (core pixel
  clock-enable) and `video_ce_ovl_o` (post-scandoubler CE for overlay).
- **Core (main) clock domain** — keyboard, joys/paddles, audio, drive LED,
  IEC, expansion port (a *very* large pin list — bidirectional with `_oe_o`
  enables and separate `_i`/`_o` directions), RTC.

`mega65.vhd` is mostly **glue**: it instantiates `clk`, `main`, the CRT loader
chain, `prg_loader`, and a bunch of dual-port BRAMs that
QNICE writes from one side and the C64 reads from the other (C64 RAM, mount
buffer, kernel ROMs, c1541 ROM, CRT cache). The OSM-bit constants
(`C_MENU_*`) live here — they map menu group IDs to bits of
`main_osm_control_i`.

### 3.3 main.vhd — the C64 in its own clock domain

Entity `main` (CORE/vhdl/main.vhd). Runs entirely on `clk_main_i`. Wraps the
MiSTer core (`fpga64_sid_iec`) and supplies all peripherals that need C64-clock
timing: keyboard adapter, REU instance, IEC simulated drives, hardware-port
cartridge logic, audio post-processing, video CE divider, and reset
sequencing.

**Critical conventions in main.vhd (read the giant RESET SEMANTICS comment at
~line 325):**
- `reset_soft_i` must be ≥32 cycles wide — caller's responsibility.
- **Never use `reset_soft_i` / `reset_hard_i` directly.** Use `reset_core_n`
  (soft) and `hard_reset_n` (hard); the protected versions hold off resets
  while a virtual disk is mid-write to prevent SD-card corruption.
- A hard reset escapes "reset-protected" cartridges/games and exits simulated
  cartridges; a soft reset doesn't.
- The expansion-port outputs go through a registration pipeline
  (`cart_output_pipeline_proc`) for timing — don't bypass.

### 3.4 QNICE — the on-board helper CPU

QNICE-FPGA is a 16-bit CPU + minimal SoC by sy2002. In M2M it runs the
**Shell**: the on-screen menu, the file/directory browser, mounting of disk
images, loading of ROMs and `.crt`/`.prg` files, and saving menu settings to
the SD card.

- CPU & monitor live under `M2M/QNICE/`. `monitor.rom` is built once via
  `M2M/QNICE/tools/make-toolchain.sh`.
- Shell (M2M) sources are `M2M/rom/*.asm`. The C64 core's entry is
  `CORE/m2m-rom/m2m-rom.asm`, which `#include`s the M2M sources and
  implements **callbacks** (e.g. `FILTER_FILES`, `SUBMENU_SUMMARY`).
  `make_rom.sh` builds `m2m-rom.rom`.
- Switch between release/debug firmware in `CORE/vhdl/globals.vhd`:
  `QNICE_FIRMWARE_M2M` (release) vs `QNICE_FIRMWARE_MONITOR` (debug; lets
  you M/L code into RAM via the JTAG serial console).
- Talks to the rest of the FPGA via an MMIO bus (`qnice_mmio.vhd`,
  `qnice_csr.vhd`, `qnice_arbit.vhd`). Devices are addressed by a 16-bit
  device ID + 28-bit address (see `C_DEV_*` in `globals.vhd`).
- QNICE is also the bridge to FAT32 SD cards (it has the SDMux + filesystem),
  to HyperRAM (`qnice2hyperram.vhd`), and to the keyboard at OSM time.
- QNICE assembly is explained in this LaTex document
  `M2M/QNICE/doc/intro/qnice_intro.tex` and remember that the monitor acts
  as kind of the "operating system". Here is an overview of the
  relevant "operating system" functions `M2M/QNICE/doc/monitor/doc.pdf` but
  *ONLY read this if you really NEED TO* since this is a PDF and it will cost
  a lot of context window space.

### 3.5 Video pipeline

Core outputs RGB + HS/VS/blanks at the C64 native pixel rate (clock-enabled
on `main_clk`). M2M splits it:

- **Analog VGA (`analog_pipeline.vhd`)**: optional scandoubler (15 kHz → 30+
  kHz), optional composite sync. "Pure retro" output, no CRT emulation. The
  core puts out 720x576 @ 50.125 Hz in PAL.
- **Digital HDMI (`digital_pipeline.vhd`)**: feeds `ascal.vhd` (MiSTer's
  poly-phase scaler). Ascal writes input frames into HyperRAM and reads them
  out at the chosen HDMI mode (720p/576p, 50/60 Hz). Defaults to 1280x720@50
  with 4:3 letterboxing. CRT emulation, zoom, polyphase filters live here.
- **Flicker-free (HDMI)**: C64 native frame rate is 50.125 Hz; HDMI is
  exactly 50.000 Hz. The Xilinx PLL can't synthesize a perfect 31.4496 MHz,
  so M2M continuously monitors ascal's FIFO level and pulses `hr_high_i` /
  `hr_low_i` to mega65.vhd, which switches between two PLL outputs (50.124
  Hz / 49.999 Hz) via a glitch-free clock mux. Average → 50 Hz exactly.
  Disable on VGA/CRT (it can flicker analog displays).

### 3.6 Memory

- **C64 RAM (64 KB)**: a BRAM block in mega65.vhd, dual-port: C64 side at
  `main_clk`, QNICE side at `qnice_clk` (see device `C_DEV_C64_RAM`). QNICE
  writes it during PRG loading.
- **HyperRAM**: shared between M2M (ascal frame buffer + QNICE), the SIMCRT
  bank cache, and SIMREU. Layout in `globals.vhd`:
  `C_HMAP_M2M=0x0000`, `C_HMAP_CRT=0x0200`, `C_HMAP_REU=0x03BF` (units of
  4 kW = 8 kB). The final 8 kB of HyperRAM is kept as a guard for SIMREU
  bursts.
- **SDRAM (R4+)**: ascal frame buffer lives here on newer boards; frees
  HyperRAM contention.
- `.crt` files: **NOT** executed in place from HyperRAM (latency up to ~1500
  ns vs. 500 ns budget). Instead a BRAM bank cache (`crt_cacher.vhd`) holds
  the last 8 banks; on a bank switch (`$DExx/$DFxx` write) the CPU is paused
  via DMA while the new bank is fetched (~82 cycles avg).

### 3.7 OSM / On-Screen Menu

- Defined as text in `CORE/vhdl/config.vhd` (constant `OPTM_ITEMS`). `%s` in
  a header line means "show the current sub-selection here" (handled by the
  `SUBMENU_SUMMARY` QNICE callback).
- Each visual line gets a **group ID** in the parallel `OPTM_GROUPS` array,
  OR'd with flags (`OPTM_G_HEADLINE`, `OPTM_G_LINE`, `OPTM_G_STDSEL`,
  `OPTM_G_SINGLESEL`, `OPTM_G_SUBMENU`, `OPTM_G_CLOSE`, `OPTM_G_HELP`,
  `OPTM_G_MOUNT_DRV`, `OPTM_G_LOAD_ROM`, `OPTM_G_START`, `OPTM_G_TEXT`).
  Group IDs are referenced both in VHDL (`C_MENU_*` bit positions in
  mega65.vhd) and QNICE asm (e.g. `C64_OPTM_G_LOAD_PRG` in
  `CORE/m2m-rom/m2m-rom.asm`).
- The current state of the menu is exposed as `qnice_osm_control_i(255 downto
  0)` (and the CDC'd `main_osm_control_i`) — one bit per item.
- Screens (Welcome, Help) are also in `config.vhd`, in the `WHS` array
  (record of pages of strings).
- The framework's address-decoding process at the bottom of `config.vhd`
  (after the **DO NOT TOUCH** banner) maps QNICE reads to all of this.

### 3.8 Virtual drives

`M2M/vhdl/vdrives.vhd` simulates the MiSTer-style mount interface
(`img_mounted`, `img_size`, `sd_lba`, `sd_rd/wr/ack`, `sd_buff_*`) for the
core, but backs storage with an in-FPGA RAM disk-image cache (device
`C_DEV_C64_MOUNT`) that QNICE pre-fills from FAT32. Number of drives:
`C_VDNUM` in `globals.vhd`. Anti-thrashing delay and write-back of dirty
caches to SD are handled by the Shell.

### 3.9 Inside the MiSTer C64 core (CORE/C64_MiSTerMEGA65/rtl)

This is the actual C64 emulation. Originally Peter Wendrich's FPGA64,
heavily modified by Dar (2014), Alexey Melnikov (2021), and **patched by
sy2002/MJoergen** for the MEGA65 port. Don't refactor without reason —
match upstream conventions wherever possible.

#### 3.9.1 `fpga64_sid_iec.vhd` — the C64 top

The whole machine in one file. Runs on a **32 MHz `clk32`** (in our port
fed by `clk_main_i` ≈ 31.527778 MHz). Around it everything is generated
via clock-enable strobes — there is **only one rising edge** for the whole
chip.

- **Master state machine `sysCycle`** (16+16 cycles per "phi" cycle):
  - First 16 cycles → VIC-II accesses (refresh, sprite fetch, char fetch).
  - Last 16 cycles → CPU access. Effective CPU clock ≈ 1 MHz.
  - Generates `enableCpu`, `enableVic`, `enablePixel`, `enableSid`,
    `phi0_cpu`, `aec`, plus the M2M-added `dotclk` and `phi2`.
- **Components instantiated:**
  - `cpu_6510` (T65 + 6510 I/O port) — the CPU.
  - `video_vicii_656x` — VIC-II.
  - `sid_top` (in `sid/`) — dual SID with filter/version/mode config.
  - Two `mos6526` instances — CIA1 (keyboard/joys/timer) and CIA2 (RS-232,
    user port, NMI, VIC bank).
  - `fpga64_buslogic` — PLA + ROMs + bank decoding.
  - Color RAM, Refresh, DMA engine (Melnikov), Turbo logic.
- **MEGA65 port deltas (read the comment block at the top of the file):**
  - PS/2 keyboard component **removed**; CIA1 ports `cia1_pa_i/o`,
    `cia1_pb_i/o` are exposed and driven by `CORE/vhdl/keyboard.vhd`.
  - `bios` input (custom/standard/GS/Japan) selects which Kernal ROM and
    enables a custom-Kernal write port (used by JiffyDOS / GEOS RTC).
  - `clk32_speed : in natural` — exact integer clock speed; the time-of-
    day clock (CIA TOD) divides by it, so feeding the wrong value gives
    "wall-clock drift" symptoms.
  - `dotclk`, `phi2`, `UMAXnomap` outputs, plus `ramCE` fix that respects
    `romL`/`romH`/`UMAXromH`/`UMAXnomap` for hardware-cartridge accuracy.

#### 3.9.2 `fpga64_buslogic.vhd` — PLA + ROMs + memmap

Pure combinational decoder (with a clocked ROM data register). Inputs:

- `bankSwitch(2:0)` = CHAREN, HIRAM, LORAM (from CPU port at $0001).
- `game`, `exrom` (cartridge config).
- `cpuAddr`, `cpuWe`, `aec`, `cpuHasBus`.
- I/O contributions: `vicData`, `sidData`, `colorData`, `cia1Data`,
  `cia2Data`, `io_data` (from cartridge IOE/IOF).

Outputs:

- Chip-selects: `cs_vic`, `cs_sid`, `cs_color`, `cs_cia1`, `cs_cia2`,
  `cs_ram`, `cs_ioE`, `cs_ioF`, `cs_romL`, `cs_romH`, `cs_UMAXromH`,
  `cs_UMAXnomap`.
- `dataToCpu`, `dataToVic` muxes.
- Includes BASIC, Char, and Kernal ROMs (multiple variants: standard, GS,
  Japanese, plus a *custom* Kernal RAM written from QNICE → JiffyDOS).

**MEGA65 PLA fixes (sy2002, see file header):** matched to "The C64 PLA
Dissected" by skoe — ultimax mode `$E000-$FFFF` writes hit `cs_romH`;
non-ultimax never writes to cart space; correct AEC dependencies; ramCE
fix; Ultimax unmapped-region (`$1000-$7FFF`, `$C000-$CFFF`) handling for
IDE64 (issue #176). If a cartridge "almost works", the bug is usually
here.

#### 3.9.3 `cpu_6510.vhd` — the CPU

Thin wrapper around the **T65** core (`rtl/t65/`). Adds the 6510-specific
**8-bit I/O port at `$0000/$0001`**: data direction at $00, data at $01.
Bits 0..2 of $01 are LORAM/HIRAM/CHAREN (drive `bankSwitch` in
`fpga64_buslogic`); bit 3 is the cassette write line; bits 4..5 cassette
sense / motor. The wrapper also handles tri-state via `ioDir` and a
sensible reset value (`"00111111"`) so the KERNAL boots correctly.

T65 itself is the well-known generic 65xx core (modes 6502/65C02/6510 via
`Mode`). Note the comment about renamed `din`/`dout` ports — be aware if
you ever update T65 from upstream.

#### 3.9.4 `video_vicii_656x.vhd` — VIC-II

Cycle-accurate VIC-II covering multiple variants:

- `mode6569` — PAL 63 cycles × 312 lines.
- `mode6567old`, `mode6567R8` — old / new NTSC.
- `mode6572` — PAL-N.
- `variant(1:0)` — NMOS / HMOS / old HMOS color matrix.

Driven by `phi` (0=VIC, 1=CPU) and clock enables `enaPixel`/`enaData`.
Internal state machine cycles through `cycleRefresh1..5`, `cycleIdle1/2`,
`cycleChar`, `cycleCalcSprites`, `cycleSpriteBa1..3`, `cycleSpriteA/B`.
Drives `ba` (BA line — pulled low to halt CPU during bad lines / sprite
fetches), produces 14-bit `vicAddr`, 4-bit `colorIndex`, `hSync`/`vSync`,
and the raster IRQ. **`PIX_DELAY = 6`** pixels of pipeline latency.

#### 3.9.5 `iec_drive/` — simulated 1541 / 1581

SystemVerilog (Melnikov 2021). Cleanly partitioned:

- **`iec_drive.sv`** — top-level selector. Picks between 1541 (D64/G64)
  and 1581 (D81) per drive based on `img_type`. Routes IEC bus, parallel
  bus, sd_* signals, and ROMs.
- **`c1541_multi.sv`** — instantiates up to 4 C1541 drives sharing one
  ROM. Two clock domains: `clk` (drive logic, fed by core clock with a
  divided CE for ~16 MHz) and `clk_sys` (used for ROM/RAM writes and SD
  block transfers — in our port this is the **QNICE clock**, registered
  on falling edge per QNICE convention).
- **`c1541_drv.sv` / `c1541_logic.sv` / `c1541_track.sv` / `c1541_gcr.sv`
  / `c1541_direct_gcr.sv`** — the actual 6502 inside the drive, VIA, ROM,
  RAM, and GCR encode/decode.
- **`c1581_drv.sv` / `c1581_multi.sv` / `fdc1772.v`** — 1581 with WD1772
  FDC. Note: in C64MEGA65 R6, 1581/D81 support is on the roadmap but
  partially commented out (see `iec_drive.sv` `c1581_*` lines).
- **`iecdrv_via6522.vhd`, `iecdrv_mos8520.v`, `iecdrv_misc.sv`,
  `floppy.v`** — supporting peripherals.

The drive talks to the rest of the world through:

- **IEC pins** (`iec_atn_i`, `iec_data_i/o`, `iec_clk_i/o`) — the serial
  bus to the C64.
- **Mount interface** — the MiSTer convention `img_mounted`, `img_size`,
  `img_type`, `sd_lba[]`, `sd_blk_cnt[]`, `sd_rd/wr/ack`, `sd_buff_*`. In
  our port these are wired to `M2M/vhdl/vdrives.vhd`, which serves
  blocks from a RAM-cached disk image (filled by QNICE/Shell from FAT32).
- **ROM port** (`rom_addr_i`, `rom_data_i`, `rom_wr_i`, `rom_std_i`) —
  driven by QNICE for custom-DOS support (e.g. JiffyDOS-1541 — see
  `C_DEV_C64_KERNAL_C1541` in `globals.vhd`).

When debugging "drive 8 doesn't mount" or "save fails": follow the chain
**Shell asm (vdrives.asm) → M2M `vdrives.vhd` → main.vhd `i_iec_drive`
→ this folder**, watching `img_mounted`, `sd_rd`, `sd_ack`, and the
`prevent_reset`/`cache_dirty` interlock in `main.vhd`.

## 4. Cartridges

The C64MEGA65 supports cartridges in **two distinct modes**, switched by a
single 2-bit signal `c64_exp_port_mode_i` (driven from the OSM via
`C_MENU_SIM_CRT` and `C_MENU_SIM_REU` in `mega65.vhd`):

- bit 0 = `C_SIM_CRT` — `0` = real hardware cartridge in MEGA65 expansion
  port; `1` = simulated `.crt` file from the SD card.
- bit 1 = `C_SIM_REU` — independent of `C_SIM_CRT`; enables the simulated
  1750 REU (512 KB).

Constants live in `CORE/vhdl/main.vhd:259-260`. The single multiplexer that
chooses **what byte the C64 CPU sees on a read** is `cpu_data_in_proc` at
`main.vhd:597-631` — it picks between hard cart, sim cart BRAM cache, hard-
reset CBM80 mask, and plain C64 RAM. **Reading this process is the fastest
way to understand cartridge data flow.**

### 4.1 Background: the C64 expansion port

(Confirmed against https://www.c64-wiki.com/wiki/Expansion_Port — pin
names below match that page; this is not invented.)

The C64's expansion port is a 44-pin (2×22) edge connector that exposes the
6510 bus to the outside world. Key pins relevant to anything we do in this
codebase:

| Pin(s)        | Signal              | Purpose                                  |
| ------------- | ------------------- | ---------------------------------------- |
| 8             | `/GAME` (in)        | Cartridge tells the PLA "I'm here"       |
| 9             | `/EXROM` (in)       | Together with `/GAME` selects map mode   |
| 11            | `/ROML` (out)       | CPU reads $8000–$9FFF (LO ROM bank)      |
| B             | `/ROMH` (out)       | CPU reads $A000–$BFFF (HI ROM bank), or $E000–$FFFF in **Ultimax** |
| 7             | `/IO1` (out)        | CPU access to $DE00–$DEFF                |
| 10            | `/IO2` (out)        | CPU access to $DF00–$DFFF                |
| C             | R/`W` (out)         | Read/Write strobe                        |
| 12            | `BA` (out)          | VIC bus-available — bus owner indicator  |
| 13            | `/DMA` (in)         | External master can halt the CPU         |
| 4             | `/IRQ` (in)         | Maskable interrupt                       |
| F             | `/NMI` (in)         | Non-maskable interrupt (RESTORE / freeze)|
| 3             | `/RESET` (bidir)    | System reset; cartridges may pull it low |
| E             | `Phi2` (out)        | 0.985 MHz PAL CPU clock                  |
| 6             | `DotCLK` (out)      | 7.88 MHz PAL pixel clock                 |
| 14–21         | `D7..D0`            | Data bus                                 |
| 22–A          | `A15..A0`           | Address bus                              |

**The four PLA cart map modes** (set by `/EXROM:/GAME`):
| EXROM | GAME | Map           | Behavior                                  |
| ----- | ---- | ------------- | ----------------------------------------- |
| 1     | 1    | "no cart"     | Cart pins ignored                         |
| 0     | 1    | 8K cart       | ROML at $8000–$9FFF                       |
| 0     | 0    | 16K cart      | ROML at $8000–$9FFF + ROMH at $A000–$BFFF |
| 1     | 0    | **Ultimax**   | ROML at $8000–$9FFF + ROMH at $E000–$FFFF (KERNAL gone, RAM hidden) |

**The CBM80 trick:** for an 8K/16K cart to autostart, the KERNAL reads the
6 bytes at `$8003` after RESET and looks for the ASCII `CBM80` signature —
if present, it jumps via the cold-start vector at `$8000`. Hiding those
bytes is enough to *exit* a cart (this is what `main.vhd` does for hard
reset, see §4.5).

### 4.2 Hardware cartridges (real cart in the MEGA65 slot)

The MEGA65's expansion port is electrically a C64 expansion port behind a
bidirectional level translator. Pins are wired through `top_mega65-rX.vhd`
into the core's `cart_*_i / cart_*_o / cart_*_oe_o` ports
(`main.vhd:147-179`). For each line we control whether we drive it
(`*_oe_o = '1'`) or sense it (`*_oe_o = '0'`).

Routing for hardware mode (`c64_exp_port_mode_i(C_SIM_CRT) = '0'`) lives in
**`handle_hardware_expansion_proc`** at `main.vhd:884-940`:

- `core_roml/romh/ioe/iof` come from inside the MiSTer core (`fpga64_sid_iec`
  → `fpga64_buslogic`) and are **registered** through `cart_*_q` (see the
  `cart_output_pipeline_proc` block) before being driven onto the slot —
  this is critical because real cartridges sample these on PHI2 edges and
  glitches break them.
- `cart_phi2_o`, `cart_dotclock_o`, `cart_ba_o` go out **combinationally**
  (must be in lockstep with the C64's clock).
- `cart_a_o` carries the registered address. In Ultimax + VIC fetch the
  upper bits are forced via `cart_a_pre` so the cart sees `$3xxx` mapped to
  the ROMH window.
- The data bus `cart_d_io` is bidirectional: written when CPU writes to the
  ROM/IO window (e.g. for bank-switch registers), read when CPU reads from
  it. The expression at `main.vhd:929-939` does the direction switch.
- `cart_en_o` is **always `'1'`** even when no cart is plugged in — there is
  a hardware bug on R5/R6 where joystick port B fails if the cart-port
  level shifter is disabled (`main.vhd:825-827`). Don't "fix" this.
- `cart_game_oe_o`, `cart_exrom_oe_o`, `cart_nmi_oe_o`, `cart_irq_oe_o` are
  hardcoded to `'0'` (read-only / sense). MEGA65 currently does not act as
  a busmaster on the slot. Comments in main.vhd flag this as a `@TODO`
  blocker for DMA-capable cartridges.

The CPU's read mux for hardware-cart mode is just:

```vhdl
elsif c64_exp_port_mode_i(C_SIM_CRT) = '0' and
      (cart_roml_n = '0' or cart_romh_n = '0' or core_umax_unmapped = '1') then
   c64_ram_data <= data_from_cart;
```
(`main.vhd:609-610` — `data_from_cart` comes from `cart_d_i` and is captured in `handle_hardware_expansion_proc`.)

#### EasyFlash 3 / cart-driven reset on R3/R3A (and R4)

R3, R3A and R4 boards have a **unidirectional** `/RESET` driver on the slot
— the C64MEGA65 can drive it but cannot sense a cartridge pulling it low.
Cartridges like the **EasyFlash 3** depend on this signal to reset the C64
when you pick a slot in their menu. To work around this we **infer the
intent** from a recognisable bus-access pattern:

- `cartridge_heuristics.vhd` watches a state machine: a write to `$DE00`,
  then a write to `$DE0E` (within ~200 main-clock cycles), a rising edge of
  `/IO1`, then three sequential PHI2-aligned addresses `$0108`, `$0109`,
  `$0013` (the EF3 menu's stack/jiffy-pointer fingerprint). When all of
  this aligns, `is_an_ef3_o` latches `'1'` until reset.
- Once flagged as EF3, `handle_cartridge_triggered_resets_proc`
  (`main.vhd:1004-1054`) catches the EF3's actual *reset request* — a
  write to `$DE0F` while in IO1 with data `$00`, `$04`, `$05`, or `$07`
  (kernel mode `$02` is deliberately unsupported because of an A14
  bus-fight risk) — and pulses `cart_reset_counter` for
  **`C_EF3_RESET_LEN = 7` PHI2 cycles** (`main.vhd:412`).
- `cart_res_flckr_ign` is a 2-cycle tail to suppress trailing glitches on
  `cart_reset_o` after the counter expires.
- On R5/R6 and newer the slot's `/RESET` is bidirectional, so cartridges
  reset the C64 directly and `cart_reset_counter` simply stays at `0`
  (the `else` branch at `main.vhd:1050-1053`).

Issue context: https://github.com/MJoergen/C64MEGA65/issues/60.

### 4.3 Simulated `.crt` cartridges — the file format

A `.crt` file (the format VICE adopted and which became the de-facto
emulator container) is:

```
CRT HEADER (0x40 bytes; padded to 64)          ← parsed once
   "C64 CARTRIDGE   "  16-byte ASCII signature
   $0010..$0013       Header length (BE, usually 0x00000040)
   $0014..$0015       Cartridge version
   $0016..$0017       Cartridge type ID  ← drives bank switching logic
   $0018              EXROM line at reset (0=low, 1=high)
   $0019              GAME line at reset
   $001A..$001F       reserved
   $0020..$003F       Cartridge name (ASCII, padded)

CHIP packet  (repeats; one per ROM bank or RAM block)
   "CHIP"             4-byte signature
   $04..$07           Total packet length (header + image), BE
   $08..$09           Chip type (0=ROM, 1=RAM no-image, 2=Flash ROM)
   $0A..$0B           Bank number
   $0C..$0D           Load address ($8000 / $A000 / $E000)
   $0E..$0F           Image size (typically $2000 = 8K, or $4000 = 16K)
   $10..$10+size-1    Raw ROM bytes
```

All multi-byte fields are **big-endian** in the file. The byte-level offsets
above are encoded in the `subtype R_CRT_*` / `R_CHIP_*` ranges in
`crt_parser.vhd:77-88`; that is the authoritative source for this codebase.
Do not just trust web docs — confirm against `crt_parser.vhd`.

### 4.4 Simulated cart loader pipeline

Top-level wrapper: **`sw_cartridge_wrapper.vhd`** (`CORE/vhdl/`). It
straddles three clock domains and contains everything below:

```
QNICE clock                    main clock                   HyperRAM clock
─────────────                  ─────────────                ─────────────────
QNICE writes raw .crt          cart_id, exrom, game,         crt_loader.vhd
into HyperRAM at the           bank_lo/hi (live state)         ├ crt_parser.vhd
G_BASE_ADDRESS offset                                            (reads HyperRAM,
(= C_HMAP_CRT = 0x0200,                                          decodes hdr+CHIPs)
~3.49 MB pool from globals.vhd)                                └ crt_cacher.vhd
        │                            ▲                            (fills 2×8 KB
        │ start, length              │                             BRAM bank cache
        ▼                            │                             on demand)
   crt_parser ───────────► header tables ──► cartridge.vhd  ──► bank_lo/hi
                                               (state machine     to crt_cacher
                                                per cart_id;
                                                drives EXROM/GAME)
```

Key files:

- **`crt_loader.vhd`** — arbiter wrapper that ties parser + cacher to the
  HyperRAM Avalon master via `i_avm_arbit` (`G_PREFER_SWAP=true`,
  parser-vs-cacher arbitration). Defines the BRAM port shape (12-bit addr,
  16-bit word, two BRAMs for ROML/ROMH).
- **`crt_parser.vhd`** — state machine
  `IDLE → WAIT_FOR_CRT_HEADER_00 → _10 → WAIT_FOR_CHIP_HEADER → READY/ERROR`.
  Validates the `"C64 CARTRIDGE   "` and `"CHIP"` signatures; emits a
  `cart_bank_wr_o` pulse per CHIP packet that the cacher latches into its
  bank tables. Error codes: `NO_CRT_HDR`, `NO_CHIP_HDR`, `WRONG_CRT_HDR`,
  `WRONG_CHIP_HDR`, `TRUNCATED_CHIP`.
- **`crt_cacher.vhd`** — keeps two `lobanks(0..127)` / `hibanks(0..127)`
  arrays of byte-addresses-in-HyperRAM. By default ROML and ROMH point to
  the same HyperRAM bank; if a CHIP packet declares `image_size > $2000`
  (i.e. a 16 KB bank), the HI half is offset by `+$2000` so a single
  16K bank populates both windows (`crt_cacher.vhd:111-124`). FSM:
  `IDLE → READ_HI → READ_LO`, asserting `bank_wait_o` while a fill is in
  progress. The BRAM cache itself holds **2^G_CACHE_SIZE = 8** entries
  (`G_CACHE_SIZE = 3`, set in `sw_cartridge_wrapper.vhd:71`).
- **`cartridge.vhd`** — *replaces* MiSTer's `cartridge.v`. This is the
  per-cart-id state machine that watches CPU writes to `$DExx` / `$DFxx`
  and updates `bank_lo_o`, `bank_hi_o`, `exrom_o`, `game_o`,
  `ioe_wr_ena_o`, `iof_wr_ena_o`, plus NMI on the freeze key. Currently
  supported `cart_id_i` values (from the `case … is` at line 105):
  `0` Generic 8K/16K/Ultimax, `1` Action Replay v4+, `3` Final Cart III,
  `4` Simons BASIC, `5` Ocean Type 1, `7` PowerPlay/FunPlay,
  `8` Super Games, `15` C64GS, `17` Dinamic, `19` Magic Desk,
  `20` Super Snapshot V5, `21` COMAL 80, `22` Waterloo, `28` Mikro Asm,
  `32` EasyFlash, `60` GMod2, `83` BMP-Data Turbo 2000,
  `85` Magic Desk 16K / MD2. Anything else falls through to `null` and
  the ROM is just whatever `bank_lo/hi = 0` exposes.

The CPU's read mux for sim-cart mode lives in the long `crt_lo/hi/ioe/iof`
chain at `main.vhd:613-625` — note the `crt_addr_bus_o(0)` switch picks the
correct byte from the 16-bit-wide BRAM word (the cache stores in word
units; LSB of the C64 byte address selects high/low byte of the BRAM word).

#### How cache misses pause the CPU

When the program writes to a bank-switch register and the new ROML/ROMH
bank isn't yet in the BRAM cache, `crt_cacher` raises `bank_wait_o`. That
signal arrives in `main.vhd` as `crt_bank_wait_i` and is OR-ed into
`core_dma_v` in `handle_cores_expansion_port_signals_proc`
(`main.vhd:953-958`):

```vhdl
core_dma_v := cartridge_loading_i or crt_bank_wait_i;
```

`core_dma` then asserts the MiSTer C64 core's `dma` input — which puts the
6510 into a tri-state hold (BA=0). The CPU resumes once the burst
completes. Average cost is on the order of an 8 KB HyperRAM burst (~82
PHI2 cycles in the comment block elsewhere), which is invisible to most
games but **can be felt on bank-switch-heavy carts** that hit the cache
hard. This is the headline reason the BRAM cache exists at all (see §4.5).

### 4.5 Why HyperRAM (not SDRAM) — and why a BRAM cache is required

The MiSTer C64 core was designed to run cart ROMs **directly out of SDRAM**
on the DE10-Nano. We **cannot** do that on the MEGA65 because:

- On R3/R3A boards there is **no SDRAM**, only a small HyperRAM. The
  HyperRAM has high single-access latency (read latency ≈ 6 cycles after a
  command, plus burst time) and is **shared with `ascal.vhd`** (the HDMI
  scaler), the M2M framework, the REU mapper, and QNICE.
- A C64 read cycle is ~1 µs (PHI2 ≈ 985 kHz). Even one un-cached HyperRAM
  read per cycle would miss timing badly under ascal contention.
- On R4+ boards SDRAM exists, but ascal already lives there (`M2M: Swap
  around ascal and core access to SDRAM`, recent commit), so freeing
  SDRAM for cart ROM access isn't currently a free lunch.

Solution: **stage the entire `.crt` file in HyperRAM, then keep only the
two currently-active 8 KB banks in BRAM**, where the C64 can read them at
single-cycle latency. The price is a brief CPU stall on bank-switch (the
DMA pause described above). The BRAM cache size is `2**3 = 8` slots, so
the most-recently-used 8 LO/HI banks stay warm — bank flips between those
are zero-cost.

#### HyperRAM memory map

From `CORE/vhdl/globals.vhd:97-100`:

| Constant       | Offset (units of 8 KB) | Region       | Size   | Used by              |
| -------------- | ---------------------- | ------------ | ------ | -------------------- |
| `C_HMAP_M2M`   | `x"0000"`              | M2M          | 4 MB   | framework reserved   |
| `C_HMAP_CRT`   | `x"0200"`              | SIMCRT       | ~3.49 MB | `.crt` staging     |
| `C_HMAP_REU`   | `x"03BF"`              | SIMREU       | 0.5 MB | simulated 1750 REU   |
| implicit guard | `x"03FF"`              | guard        | 8 KB   | SIMREU burst overrun guard |
| `C_HMAP_SIZE`  | `x"0400"`              | total        | 8 MB   |                      |

`sw_cartridge_wrapper`'s `G_BASE_ADDRESS` is wired to `C_HMAP_CRT` from
`mega65.vhd`. The ~3.49 MB pool is the hard upper bound on a single `.crt`
file size; in practice the largest stock cartridge formats (1 MB
EasyFlash, 8 MB GMod2 in theory) fit either trivially or not at all.

### 4.6 Reset semantics around cartridges

The reset rules around the cartridge subsystem are subtle and documented
in the **`RESET SEMANTICS` block at `main.vhd:325-358`**. Read it before
touching any reset-adjacent code. Key invariants:

1. **`reset_soft_i` and `reset_hard_i` must NEVER be used directly** in
   `main.vhd` (the comment block is explicit). Use `reset_core_n`. Two
   exceptions are commented in: `handle_cold_start_proc` and
   `handle_cartridge_triggered_resets_proc`.
2. **A soft reset starts cartridges** — both real and simulated. This is
   the normal "reset button" behavior, and it relies on the CBM80
   signature being visible at `$8003` so the KERNAL autoboots the cart.
3. **A hard reset must *exit* a cartridge.** It does this by masking
   `$8000–$8FFF` reads to `$00` while `hard_reset_n = '0'`
   (`main.vhd:605-606`):
   ```vhdl
   if hard_reset_n = '0' and c64_ram_addr_o(15 downto 12) = x"8" and
      cold_start_done = '1' then
     c64_ram_data <= x"00";
   ```
   This hides CBM80 from the KERNAL during the reset window so the cart
   does *not* re-autostart. The mask is gated by `cold_start_done`
   (`handle_cold_start_proc`, line ~582) so that a *first* boot still
   sees the signature and autoboots a real cartridge. The MiSTer core
   does not expose the EXROM line on the right path to do this the
   "proper" way (via PLA), so the data-bus mask is the chosen workaround.
4. **The minimum reset pulse is 32 main-clock cycles.** Both upstream
   reset sources (M2M reset manager, sw_cartridge_wrapper) guarantee that.
   A cart-driven reset (`cart_reset_i`) is assumed to satisfy this — EF3
   pulses for 7 PHI2 ≫ 32 main-clock cycles.
5. **`prevent_reset` interlock** — `reset_core_n` is gated against
   `vdrives.cache_dirty` so a reset cannot drop in-flight disk writes.
   This is mentioned in §3 (vdrives) and is *separate* from the cart
   reset machinery, but the two must coexist.
6. **`cartridge_inst` resets on `not hard_reset_n`, not on `reset_core_n`**
   (`main.vhd:1103`). Soft resets must *not* clear the cartridge state
   machine, otherwise `sw_cartridge_wrapper`'s soft reset (used to make
   the C64 re-enter the cart after a `.crt` mount) would itself wipe the
   `cartridge.vhd` `bank_lo/hi/exrom/game` registers. See the comment at
   `main.vhd:1095-1099`.

When debugging "cart doesn't autostart", "cart can't be exited via reset",
or "EF3 menu does nothing": work through this list before doing anything
else.

### 4.7 Cross-reference

- §3 — overall architecture / `mega65.vhd` glue (where `C_MENU_SIM_CRT`
  / `C_MENU_SIM_REU` are wired into the OSM and into `c64_exp_port_mode`).
- §3 (MiSTer core deep-dive) — `fpga64_buslogic.vhd` is what actually
  implements PLA-style address decoding from EXROM/GAME/ROML/ROMH and
  is *not* per-cart-type; the per-cart-type logic is entirely above
  the core in `cartridge.vhd`.
- §6 — board deltas; this is where "no SDRAM on R3" matters.
- §9 (debugging table) — fast lookup by symptom.

---

## 5. Build & development workflow

(See `doc/developer.md` for the canonical version.)

```bash
git clone https://github.com/MJoergen/C64MEGA65.git
cd C64MEGA65
git submodule update --init --recursive

# 1) QNICE toolchain (one-time; produces M2M/QNICE/monitor/monitor.rom)
cd M2M/QNICE/tools && ./make-toolchain.sh && cd ../../..

# 2) Build the Shell ROM whenever you change CORE/m2m-rom/*.asm or M2M/rom/*.asm
cd CORE/m2m-rom && ./make_rom.sh && cd ../..
# Output: CORE/m2m-rom/m2m-rom.rom (read by qnice.vhd at synthesis)

# 3) Open Vivado on the project for the target MEGA65 revision.
#    There is one Vivado project per board revision — they all share the same
#    sources but use a different top + xdc.
./CORE/run_vivado_r6.sh    # or _r3 / _r4 / _r5
# In Vivado: Run Synthesis → Run Implementation → Generate Bitstream

# 4) Flash / load
#    JTAG dev loop:   m65 -q yourbitstream.bit   (mega65-tools)
#    Distribution:    bit2core mega65rX <bit> "C64 for MEGA65" "<ver>" out.cor "=default,c64cart+c64cart"
```

**Per-revision Vivado projects:**
`CORE/CORE-R{3,4,5,6}.xpr` — synth/impl/bit runs are kept under
`CORE/CORE-R{3,4,5,6}.{cache,hw,runs,sim}/`. Don't accidentally edit the
generated dirs; Vivado regenerates them.

**Config file (saves user menu choices to SD):**
The framework cannot grow files on FAT32. Generate a correctly-sized
`/c64/c64mega65-<version>` file with
`M2M/tools/make_config.sh c64mega65-<version> auto`, where `<version>`
matches the `CORE_VERSION` constant in `CORE/vhdl/config.vhd` (size must
match `OPTM_SIZE` from `config.vhd`). The version suffix on the filename
was introduced in V6 (issue #182) so multiple core versions can keep their
settings side by side on the same SD card; `CFG_FILE` in `config.vhd`
derives the full path from `CORE_VERSION`.

**Debug console:** JTAG cable + serial 115200 8N1; press
<kbd>Run/Stop</kbd>+<kbd>Cursor Up</kbd>+<kbd>Help</kbd> to get the QNICE
interactive console. Set `QNICE_FIRMWARE := QNICE_FIRMWARE_MONITOR` in
`CORE/vhdl/globals.vhd` to load Shell into RAM via M/L instead of synthesizing
it as ROM.

---

## 6. Where C64MEGA65 differs from upstream MiSTer (gotchas)

These are documented in `doc/developer.md` and in code comments — but
internalize them before debugging anything visual or timing-related:

1. **PLL accuracy.** Xilinx MMCMs can't synthesize MiSTer's exact 31.527954
   MHz; we use 31.527778 MHz (≈6 Hz off). For dynamic flicker-free we use
   two clocks and switch between them.
2. **Keyboard.** MEGA65 has a real keyboard, not PS/2. `keyboard.vhd`
   replaces `fpga64_keyboard.vhd` and feeds CIA1 directly.
3. **PHI2 to expansion port.** Added on top of MiSTer's `fpga64_sid_iec`;
   timing is fragile because real cartridges sample it.
4. **PLA.** MiSTer fuses PLA + ROMs + memmap into `fpga64_buslogic.vhd`. We
   bug-fixed it to match the documented PLA truth tables (see `doc/PLA.md`).
5. **Software cartridges (.crt).** MiSTer executes from SDRAM. We can't —
   HyperRAM contention from ascal is too high. Solution: BRAM bank cache,
   DMA-pause the CPU during bank fills (`crt_cacher.vhd`,
   `sw_cartridge_wrapper.vhd`).
6. **Reset semantics.** See main.vhd `RESET SEMANTICS` block. Soft vs hard,
   minimum-32-cycle pulse, prevent_reset interlock with vdrives.

---

## 7. Coding conventions

- **VHDL** for almost everything; some Verilog/SystemVerilog from MiSTer
  (`reu.v`, `mos6526.v`, `c64.sv`, `rtcF83.sv`, `cartridge.v`). Don't rewrite
  upstream Verilog without a reason.
- **Style:** mixed within the repo; **match the surrounding file** (per
  CONTRIBUTING.md). Signals `lower_snake_case_with_io_suffix`: `_i` input,
  `_o` output, `_io` bidir, `_n` low-active, `_oe` output-enable.
- **American English** in comments and identifiers (color, behavior, …).
- **Branches:** PRs target `develop`. `master` ≈ latest release. Long-lived
  feature work goes on `dev-*` / `develop-*` branches and *may* be broken.
- **License:** GPL v3. New contributions must also be GPL v3.

---

## 8. Useful pointers

- User docs (authoritative for behavior): https://c64.mega65.org
- M2M wiki (parts WIP): https://github.com/sy2002/MiSTer2MEGA65/wiki
- QNICE-FPGA: https://github.com/sy2002/QNICE-FPGA and http://qnice-fpga.com/
- Upstream MiSTer C64: https://github.com/MiSTer-devel/C64_MiSTer
- MEGA65 project: https://mega65.org
- Issue tracker: https://github.com/MJoergen/C64MEGA65/issues
  (at-mention `@MJoergen`, `@sy2002`, `@paich64` for big changes)

---

## 9. When debugging — quick orientation

| Symptom area              | Files to look at first                                    |
| ------------------------- | --------------------------------------------------------- |
| HDMI tearing / flicker    | `clk.vhd`, `mega65.vhd` (hr_core_speed), `hdmi_flicker_free.vhd`, `ascal.vhd` |
| VGA / scandoubler / CSYNC | `analog_pipeline.vhd`, `vga_controller.vhd`               |
| OSM rendering / scaling   | `vga_osm.vhd`, `video_overlay.vhd`, `vga_recover_counters.vhd` |
| Menu items / labels       | `CORE/vhdl/config.vhd` (OPTM_ITEMS, OPTM_GROUPS, WHS)     |
| Menu wiring → core        | `mega65.vhd` `C_MENU_*` constants → `main_osm_control_i`  |
| Disk mount / vdrive       | `vdrives.vhd`, `M2M/rom/vdrives.asm`, `iec_drive/`        |
| `.crt` won't load / parse | `crt_parser.vhd` (state machine + error codes), `sw_cartridge_wrapper.vhd` (QNICE side) |
| `.crt` cart-id unsupported| `cartridge.vhd` `case to_integer(unsigned(cart_id_i))` at line 109 |
| `.crt` bank-switch broken | `cartridge.vhd` per-id branch + `crt_cacher.vhd` (BRAM cache fill, bank tables) |
| `.crt` exec stalls / glitch| `crt_cacher.vhd` (bank_wait_o), `main.vhd:957` (DMA pause), HyperRAM contention |
| Hardware cart port        | `main.vhd` `handle_hardware_expansion_proc` (lines 884–940), `cart_output_pipeline_proc` |
| EF3 / KFF doesn't reset C64 (R3/R3A/R4) | `cartridge_heuristics.vhd`, `main.vhd:1004-1054`         |
| Cart won't autostart / can't be exited  | `main.vhd` `cpu_data_in_proc` ($8xxx mask), `cold_start_done` flag |
| Keyboard                  | `keyboard.vhd`, `M2M/vhdl/m2m_keyb.vhd`                   |
| Reset / data corruption   | `main.vhd` RESET SEMANTICS block, `vdrives.vhd` (cache_dirty / prevent_reset) |
| QNICE Shell behavior      | `M2M/rom/shell.asm` + neighbors; callbacks in `CORE/m2m-rom/m2m-rom.asm` |
| ROM autoload (JiffyDOS)   | `globals.vhd` C_CRTROMS_AUTO, `M2M/rom/crts-and-roms.asm` |
| HyperRAM contention       | `globals.vhd` C_HMAP_*, `qnice2hyperram.vhd`, ascal       |
| REU                       | `reu_mapper.vhd`, MiSTer `reu.v`, `globals.vhd` C_HMAP_REU |
| Per-board pinout/timing   | `M2M/MEGA65-Rx.xdc`, `M2M/vhdl/top_mega65-rx.vhd`, `CORE/CORE.xdc` |
