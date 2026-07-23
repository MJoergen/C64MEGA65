C64 for MEGA65 developer documentation
======================================

Building the core
-----------------

Refer to the
[MiSTer2MEGA65 documentation](https://github.com/sy2002/MiSTer2MEGA65/wiki)
for more details and for operating system specific details: You need a `bash`
or compatible shell, the GCC compiler environment including make, `awk` and
other typical tools.

```bash
git clone https://github.com/MJoergen/C64MEGA65.git
cd C64MEGA65
git submodule update --init --recursive
cd M2M/QNICE/tools/
./make-toolchain.sh 
```

Answer all questions that you are being asked while the QNICE tool chain is
being built by pressing Enter. You can check the success of the process by
checking if the Monitor is available as .rom file:

```bash
ls -l ../monitor/monitor.rom
```

Now build the Shell (firmware for on-screen-menu, mounting `D64` images on
an SD card, etc.):

```bash
cd ../../../CORE/m2m-rom/
./make_rom.sh
ls -l m2m-rom.rom
```

If everything went well, then the last command will generate the expected
output.

### Building in the Vivado GUI

Open the Vivado project for the target board revision — `CORE/CORE-R3.xpr`, `CORE-R4.xpr`, `CORE-R5.xpr` or `CORE-R6.xpr` — and run *Run Synthesis → Run Implementation → Generate Bitstream*. The bitstream is written to `CORE/CORE-R<rev>.runs/impl_1/mega65_r<rev>.bit`.

### Building from the command line

For headless or overnight builds, two scripts in `CORE/` drive Vivado in batch mode. Both build **directly from the `CORE-R{3,4,5,6}.xpr` projects** — the projects are the single source of truth for the source file list, the target part, the synthesis and implementation strategies, the XDC read order and the `synth_pre.tcl` firmware hook. Nothing is restated in the scripts, so a command-line build is identical to what the Vivado GUI produces and it writes the bitstream to the same location the GUI does — and that `make_release.py` and `load_bitstream.sh` expect: `CORE/CORE-R<rev>.runs/impl_1/mega65_r<rev>.bit`.

Prerequisites: a `bash` shell with `vivado` on the `PATH` (source Vivado's `settings64.sh` first), and the QNICE tool chain already built once (`make-toolchain.sh`, see above) so that `monitor.rom` exists. The scripts rebuild the QNICE assembler and the Shell ROM for you on every run.

**`build_bitstream.tcl` — build one board.** This is the low-level script; run it directly for a single board, or let `build_all.sh` call it. It takes up to three positional `-tclargs`:

| Position | Argument | Meaning | Default |
|----------|----------|---------|---------|
| 1 | `board` | `R3`, `R4`, `R5` or `R6` | — (required) |
| 2 | `jobs` | number of parallel Vivado jobs | `4` |
| 3 | `debug` | the literal word `debug` inserts an ILA (see below); anything else, or omitted, builds a normal release | release |

```bash
cd CORE
source /opt/Xilinx/2025.1/Vivado/settings64.sh                        # or wherever Vivado lives
vivado -mode batch -source build_bitstream.tcl -tclargs R6            # R6, 4 jobs, release
vivado -mode batch -source build_bitstream.tcl -tclargs R6 8          # R6, 8 jobs
vivado -mode batch -source build_bitstream.tcl -tclargs R6 8 debug    # R6, 8 jobs, with ILA
```

It runs a clean synthesis (`reset_run synth_1`) followed by implementation through `write_bitstream`, then re-opens the routed design and checks the sign-off gates (see below). It prints exactly one machine-readable result line and returns a distinct exit code per outcome:

| Exit | Result line | Meaning |
|------|-------------|---------|
| `0` | `` `RESULT <board> OK WNS=.. WHS=.. bit=..` `` | success: timing met and all gates passed |
| `0` | `` `RESULT <board> OK-DEBUG bit=.. probes=..` `` | debug build finished (ILA inserted) |
| `1` | `` `RESULT <board> FAILED synth_1/impl_1: ..` `` | synthesis or implementation failed |
| `2` | `` `RESULT <board> TIMING-FAILED WNS=.. WHS=..` `` | negative setup or hold slack |
| `3` | `` `RESULT <board> SIGNOFF-FAILED ..` `` | a `CORE.xdc` sign-off gate failed |

**`build_all.sh` — build every board, made for overnight runs.** This is the wrapper you will normally use. It rebuilds the QNICE assembler for the current OS (`make_qasm.sh`) and assembles the Shell ROM (`make_rom.sh`) once, up front — so a firmware problem aborts the run before the first multi-hour synthesis — then calls `build_bitstream.tcl` for each board, each with its own `build_<board>.log` and `build_<board>.jou`, and finally prints a one-line-per-board summary. It exits non-zero if any board failed.

```bash
cd CORE
source /opt/Xilinx/2025.1/Vivado/settings64.sh
nohup ./build_all.sh > build_all.out 2>&1 &      # all four boards, in the background
./build_all.sh R4 R6                             # only the listed boards
JOBS=8 ./build_all.sh                            # 8 parallel Vivado jobs per board
DEBUG=1 ./build_all.sh R6                        # R6 with an ILA (see debug builds)
```

`JOBS` sets the parallel-jobs count passed to each build (default `4`); `DEBUG` with any non-empty value turns every board in the run into a debug build. Board names on the command line restrict the run to that subset; with none given it builds `R3 R4 R5 R6`.

**Debug builds (ILA insertion).** Passing `debug` (or `DEBUG=1` to `build_all.sh`) inserts an Integrated Logic Analyzer on every net that carries the `mark_debug` attribute in the RTL, using the stock Xilinx helper `CORE/debug.tcl`. Mark the nets you want to capture with `attribute mark_debug of <signal> : signal is "true";` in the VHDL, rebuild with the `debug` flag, then load both the bitstream and the generated probes file into the Vivado hardware manager. The probes are written next to the bitstream as `mega65_r<rev>.ltx` (and `debug.tcl` also drops a `CORE/debug_nets.ltx`). Two caveats: a debug build drives implementation in-session, so the `.xpr` `Performance_ExtraTimingOpt` implementation strategy is **not** applied — a debug bitstream is for hardware bring-up, not for release — and it is deliberately not gated on timing, because the ILA logic often eats into slack.

**The sign-off gates.** After a release build, `build_bitstream.tcl` re-opens the routed design and verifies that the load-bearing `CORE.xdc` constraints actually attached to real objects. This matters because a constraint whose target instance was renamed silently constrains nothing, and Vivado only emits a warning that is easy to miss in a long log. The gates check the flicker-free clock-selector pin (`CORE/hr_core_speed_reg[0]/Q`), the generated `main_clk` (present, and sourced from the correct MMCM leg so its period is ~31.718 ns), the `qnice_clk` clock, and a representative set of the deep IEC-drive CDC false-path pins. If any gate fails, the build is reported `SIGNOFF-FAILED` and exits `3` even though synthesis, implementation and timing all succeeded. When you add or rename hierarchy that `CORE.xdc` references, update the gate list in `build_bitstream.tcl` in the same commit.

Making a `.cor` file
--------------------

### Get `bit2core`

* [Linux and Windows binaries](https://builder.mega65.org/job/mega65-tools/job/development/)
* [macOS binaries](https://github.com/MEGA65/mega65-tools/releases/tag/CI-development-latest)
* [GitHub repository](https://github.com/MEGA65/mega65-tools)

### Use `bit2core`

The C64 core can run cartridges that are inserted into the MEGA65's expansion
port. To make sure that the MEGA65's CORE #0 core selection logic knows that
and automatically starts the C64 core if an appropriate C64 cartridge is
inserted, make sure that you use the correct flags for the `bit2core` tool:

```bash
bit2core mega65r3 C64M65-WIP-V5-A23.bit "C64 for MEGA65" "WIP-V5-A23" C64M65-WIP-V5-A23.cor "=default,c64cart+c64cart"
```

Conventions for version info in `*.cor` files:

* Releases are called "V4", "V5", etc.
* Alpha releases are called "WIP-Vx-Ay", where `x` is the upcoming next major
  release that this alpha release works towards and y is the version of the
  alpha release, just counting upwards.

Configuration file
------------------

The FAT32 writing abilities of the M2M framework are currently limited: It
can only change data in existing files such as disk images or configuration
files. This means the current version of the M2M framework is not able to
create new files on an SD card and since it is also not able to change the
length of any file (e.g. append data), you always need to make sure that
there is a valid `c64mega65-<version>` configuration file located in the
`/c64` folder on the SD card, where `<version>` is the value of the
`CORE_VERSION` constant in `CORE/vhdl/config.vhd` (e.g.
`c64mega65-WIP-V6-A15`).

This is how you create a valid configuration file that uses default
settings:

```bash
./make_config.sh c64mega65-WIP-V6-A15 auto
```

The size of the configuration file needs to be equal to the constant
`OPTM_SIZE` in `CORE/vhdl/config.vhd`. The `auto` parameter extracts this
information automatically. The script is located in `M2M/tools`.

The reason the file name carries the version is so that several core
versions can keep their settings side by side on the same SD card; see
[GitHub issue #182](https://github.com/MJoergen/C64MEGA65/issues/182). On
release builds, `make_release.py` generates this file automatically with
the correct version suffix.

Core-specific `m2m-rom.asm`
---------------------------

Everything the user sees *around* the running C64 — the on-screen menu (OSM),
the file browser, mounting disk images, loading `.prg`/`.crt` files and ROMs,
saving settings — is drawn and driven by **QNICE**, the small 16-bit helper
CPU, not by the C64 itself. The QNICE program that does this is the **Shell**,
and it ships as part of the M2M framework (`M2M/rom/*.asm`).
`CORE/m2m-rom/m2m-rom.asm` is the *core-specific* top of that program: it pulls
in the framework Shell and then customizes it for the C64.

The design follows the same CORE/M2M split as the VHDL side (see the project
guide `AGENTS.md`): the framework is core-independent, the core is
board-independent, and they meet at a well-defined contract. On the QNICE side
that contract has two halves:

* **Data:** the menu layout and a handful of hardware sizes are declared once,
  in VHDL (`config.vhd`, `mega65.vhd`, `globals.vhd`), and mechanically
  mirrored into QNICE constants at build time.
* **Behavior:** the framework owns the control flow (the menu loop, the
  browser, the mount engine) and calls back into a small set of core-provided
  **callback functions** whenever core-specific behavior is needed.

`m2m-rom.asm` is therefore mostly glue: two `#include`s that pull in the whole
framework Shell, a trivial entry point, the callback implementations, and the
core's strings and tables.

### The mental model: the Shell calls you back

The firmware entry point is `START_FIRMWARE`. After the QNICE "operating
system" (the *Monitor*) has booted, `M2M/rom/main.asm` jumps to it, and in the
C64 core it does exactly one thing (`m2m-rom.asm:39`):

```
START_FIRMWARE  RBRA    START_SHELL, 1
```

`START_SHELL` lives in `M2M/rom/shell.asm` and is the framework's main loop.
**The core writes no main loop of its own.** Instead it plugs into the Shell at
defined hook points — the callback functions — each of which is an ordinary
QNICE subroutine with a fixed register contract, documented in the comment
block above it in `m2m-rom.asm`. When the framework needs core-specific
behavior (Which files should the browser show? Is this a valid disk image? What
should happen after the user picks a menu item?), it calls the matching
callback; the core does its thing and returns.

Two `#include`s wire the framework in (`m2m-rom.asm:30` and `:33`):

```
#include "../../M2M/rom/main.asm"    ; Monitor + jump to START_FIRMWARE
#include "../../M2M/rom/shell.asm"   ; the whole Shell (menu, browser, mount, ...)
```

Because the QNICE assembler is multi-pass, the framework files can reference
the core's callbacks even though those are defined further down in
`m2m-rom.asm`, after the `#include`s.

### Building the Shell ROM: `make_rom.sh` step by step

`CORE/m2m-rom/make_rom.sh` turns the assembly sources into `m2m-rom.rom`, the
file that `qnice.vhd` bakes into the bitstream as the Shell ROM. Re-run it every
time you change any `CORE/m2m-rom/*.asm` or `M2M/rom/*.asm` file. It performs
these steps **in this order** (the order matters — see below):

1. **Sanity-check the assembler.** If `M2M/QNICE/assembler/qasm` is missing, it
   stops with instructions to build the QNICE toolchain first
   (`make-toolchain.sh`).
2. **Generate `osm_const.asm`** from the VHDL menu definition.
3. **Generate `globals.asm`** from `CORE/vhdl/globals.vhd`.
4. **Generate `shell_fhandles.asm`** (FAT32 file-handle storage).
5. **Generate `shell_fh_ptrs.asm`** (pointer tables into that storage).
6. **Assemble `m2m-rom.asm`** with the `asm` wrapper, producing `m2m-rom.def`,
   `m2m-rom.lis`, `m2m-rom.out` and `m2m-rom.rom`.
7. **Guard the ROM budget.** QNICE reserves `0x7000`–`0x7FFF` for memory-mapped
   I/O, so the usable Shell ROM is `0x0000`–`0x6FFF` = 28,672 words. The script
   counts the words in `m2m-rom.rom` and fails the build if assembly failed or
   the ROM overflows that budget (the assembler itself does not check this).

**Why steps 2–5 come before step 6:** the four generated `.asm` files are
`#include`d into the assembly (directly or through the framework, see below), so
they must exist on disk before `asm` runs. The *content order* inside the
assembly does not matter — `qasm` resolves labels across multiple passes — but
the *files* have to be there. Regenerating them from the VHDL on every build is
what keeps the QNICE side from silently drifting out of sync with the hardware
when you reorder a menu or change a constant.

### The autogenerated files

Four files are regenerated on every build. All four carry a
`; DO NOT MANUALLY EDIT` banner — edit the VHDL source instead and re-run
`make_rom.sh`.

**`osm_const.asm` — the menu bridge.** This is the most important generated
file. The menu layout is authored in VHDL, and `make_rom.sh` mirrors it into
QNICE constants with two `awk` one-liners:

* Every `constant C_MENU_<name>` in `CORE/vhdl/mega65.vhd` becomes
  `C64_OSM_<name>` — the **flat item index** of a menu line (its position,
  counting from zero, in the `OPTM_ITEMS` list; this is also its bit in the
  256-bit OSM selection state). Example: `C_MENU_KERNAL_JIFFY := 107` becomes
  `C64_OSM_KERNAL_JIFFY .EQU 107`.
* Every *decimal* `constant OPTM_G_<name>` in `CORE/vhdl/config.vhd` becomes
  `C64_OPTM_G_<name>` — a **menu group id**. The `awk` deliberately skips the
  `16#...#` hex constants (`OPTM_G_HEADLINE`, `OPTM_G_SUBMENU`,
  `OPTM_G_MOUNT_DRV`, ...): those are M2M framework *flag bits*, known to the
  framework by their own names, not core group ids.

The payoff: callback code refers to menu items and groups **by name**
(`C64_OSM_KERNAL_JIFFY`, `C64_OPTM_G_MOUNT_CRT`) instead of by magic number.
Reorder the menu in `config.vhd` and the indices are simply regenerated, so a
callback can never silently point at the wrong line. `menu_test.py`
additionally checks these indices against a golden model.

**`globals.asm` — hardware constants.** Mirrors a few `globals.vhd` values the
Shell needs at runtime:

* `VDRIVES_MAX` (from `C_VDNUM`) — number of virtual drives.
* `CRTROM_MAN_MAX` (from `C_CRTROMS_MAN_NUM`) — number of *manually* loadable
  ROMs/cartridges (menu-triggered: `.prg`, `.crt`).
* `CRTROM_AUT_MAX` (from `C_CRTROMS_AUTO_NUM`) — number of *auto*-loaded ROMs
  (loaded before the core starts, e.g. the three JiffyDOS ROMs). The Shell
  keeps a per-ROM load-success flag array `CRTROM_AUT_LDF`; the JiffyDOS boot
  gate reads it (see `PREP_START` below).
* `C64_CRT_MAX_SIZE_HI/LO` — the largest `.crt` the SIMCRT HyperRAM pool can
  hold, computed directly from the HyperRAM map
  (`(C_HMAP_VD0 - C_HMAP_CRT) * 8192` bytes) so the Shell size check can never
  drift from the VHDL memory map.

A count of `0` is bumped to `1` by the script, so the file-handle tables below
are always well-formed even for a core with no virtual drives.

**`shell_fhandles.asm` / `shell_fh_ptrs.asm` — FAT32 file handles.** The Shell
keeps one FAT32 file-handle structure open per mountable object.
`shell_fhandles.asm` reserves the storage — one `HANDLE_VD_FILE<n>` block per
virtual drive and one `HANDLE_RM_FILE<n>` block per manually loadable ROM/cart,
each `FAT32$FDH_STRUCT_SIZE` words. `shell_fh_ptrs.asm` builds the pointer
tables `HNDL_VD_FILES` and `HNDL_RM_FILES` that the Shell indexes by drive or
ROM number.

A subtlety worth internalizing: although these four files are *generated into*
`CORE/m2m-rom/`, three of them are `#include`d by the **framework**, not by the
core — `M2M/rom/shell_vars.asm` pulls in `globals.asm` and `shell_fhandles.asm`,
and `M2M/rom/shell.asm` pulls in `shell_fh_ptrs.asm`. Only `osm_const.asm` is
`#include`d directly by `m2m-rom.asm`. This is the framework reaching back into
the core for core-sized tables it cannot know when it is authored.

The assembly step (step 6) also produces three non-`.asm` outputs:

| File | What it is |
|------|------------|
| `m2m-rom.rom` | Vivado-compatible ROM image, one 16-bit word per line; this is what `qnice.vhd` loads. |
| `m2m-rom.out` | Loadable image for the QNICE Monitor (`M/L`) and the emulator — used for the debug console and headless tests. |
| `m2m-rom.lis` | Full assembler listing (source alongside addresses and assembled words). |
| `m2m-rom.def` | Monitor operating-system call definitions. |

### Implementing features through callbacks

This is where the core actually customizes the Shell. Each callback is a
labelled subroutine in `m2m-rom.asm` with a register contract in the comment
above it; the framework calls it at a specific moment. Two conventions recur:

* Callbacks run inside their own QNICE register bank (`INCRB`/`DECRB`), so
  `R0`–`R7` are private scratch and `R8`–`R12` carry the contract.
* Two of them — `SUBMENU_SUMMARY` and `CUSTOM_MSG` — use "return `0` in `R8`"
  to mean "no custom value, use the framework default." The core only supplies
  a value when it wants to override the generic behavior.

The C64 core implements seven callbacks:

| Callback | The framework calls it... | Purpose (C64 core) |
|----------|---------------------------|--------------------|
| `PREP_START` | right before the core leaves reset (`shell.asm:144`) | apply saved settings at boot |
| `OSM_SEL_PRE` | *before* it applies a menu selection (`options.asm:1359`) | pre-empt a selection |
| `OSM_SEL_POST` | *after* it applied a selection (`options.asm:1458`) | react to a selection |
| `SUBMENU_SUMMARY` | when drawing a submenu opener that contains `%s` (`options.asm:1539`) | render a live summary |
| `FILTER_FILES` | once per entry in the file browser (via a pointer, `selectfile.asm:71`) | show or hide files |
| `PREP_LOAD_IMAGE` | after a file is picked, before it is mounted (`shell.asm:722`) | validate and type a file |
| `CUSTOM_MSG` | when the Shell needs a user message (`selectfile.asm:522`) | override a message string |

The rest of this section walks through what each one does for the C64, which
doubles as a tour of how the core's menu features are implemented.

**`PREP_START` — apply saved settings at boot.** The framework calls this once,
after it has loaded the saved settings from the SD-card config file into the
in-memory mirror `M2M$CFM_DATA`, and while the core is still held in reset — so
the core boots straight into the saved state with no visible glitch. The C64
core does two jobs here. First, it reads the saved *HDMI Filter* choice and
pushes the matching polyphase coefficients into `ascal` (`LOAD_HDMI_FILTER`), so
the very first HDMI frame already shows the chosen filter. Second, the
*JiffyDOS gate*: if the saved Kernal is JiffyDOS, it checks the JiffyDOS ROM
load flags in `CRTROM_AUT_LDF` (`jd-c64`, `jd-c1541`, `jd-c1581`), prints a
per-component status report to the debug console, and — if the required ROMs are
missing — reverts the live Kernal setting to Standard for this session only
(`M2M$SET_SETTING` writes the in-memory mirror, not the SD file, so the saved
choice survives).

**`OSM_SEL_PRE` / `OSM_SEL_POST` — react to menu changes.** These fire when the
user selects an item, respectively *before* and *after* the framework has
applied the selection's built-in semantics. The split lets the core either
pre-empt or follow up on the framework's action:

* `OSM_SEL_PRE` reacts to *CRT: Load* (`C64_OPTM_G_MOUNT_CRT`): if the core is
  not already in "Simulate cartridge" mode, it switches to that mode with
  `M2M$FORCE_MENU` and soft-resets, so the running C64 does not hang while the
  hardware slot is decoupled and the file selector is open. (If sim-cartridge
  mode is already active, it does nothing.)
* `OSM_SEL_POST` performs the *auto soft-reset on settings that need a clean
  restart* — changing the Kernal (`C64_OPTM_G_KERNAL_MODES`), the
  expansion-port mode (`C64_OPTM_G_EXP_PORT`) or the simulated REU
  (`C64_OPTM_G_REU`) calls `RESET_CORE`. For a change of HDMI filter
  (`C64_OPTM_G_HDMI_FILTER`) it instead *hot-reloads* the coefficients with
  `LOAD_HDMI_FILTER` and does **not** reset — the C64 keeps running and the new
  filter appears on the next frame.

**`SUBMENU_SUMMARY` — live submenu summaries.** A submenu opener in `config.vhd`
can contain a `%s`, e.g. `" Model: %s"` or `" Kernal: %s"`. Each time the main
menu is drawn, the framework calls `SUBMENU_SUMMARY` for that line so the core
can fill in the `%s`. The callback recognizes the opener by its flat index
(`C64_OSM_MODEL`, `C64_OSM_KERNAL`); it returns `0` to accept the framework
default (which shows the currently selected radio item), or a pointer to a
custom string. The C64 uses it to show, at a glance, the machine and turbo
state under `Model:` and which JiffyDOS drive ROMs are installed under
`Kernal:` — without entering the submenu.

**`FILTER_FILES` — what the browser shows.** Unlike the others, this one is
handed to the file/directory browser as a *function pointer* (`selectfile.asm:71`
loads its address into `R12`) and the browser calls it once per entry. Given a
filename, a file/directory flag and a *context* (`CTX_MOUNT_DISKIMG`,
`CTX_LOAD_ROM`, ...) plus the triggering menu group, the core returns `0` to
show the entry or non-zero to hide it. It shows directories always, `.d64`/
`.d81` when mounting a disk (intentionally not `.g64`), `.prg` for *PRG: Load*,
and `.crt` for *CRT: Load*.

**`PREP_LOAD_IMAGE` — validate and type a file.** After a file is chosen but
before it is mounted or loaded, the framework calls this to let the core parse
or sanity-check it and, for disk images, return the 2-bit *image type* the mount
engine needs. The C64 core derives that type from the file *size*: 174,848
(35 tracks) or 196,608 (40 tracks) bytes becomes image type D64 (1541); 819,200
bytes becomes image type D81 (1581); any other size is rejected with an error
message. (Extensions were already filtered in `FILTER_FILES`, so the check here
is purely by size.) When the callback is instead reached from *CRT: Load*, it
enforces the `.crt` size ceiling `C64_CRT_MAX_SIZE_*` so an oversized cartridge
cannot overrun the SIMCRT HyperRAM pool; `.prg` and other ROM loads pass through
unchecked.

**`CUSTOM_MSG` — override Shell messages.** The Shell emits user messages for
various generic situations (`CMSG_*`). This callback lets the core replace the
generic text with a core-specific one for a given situation and context; the
C64 uses it to show a D64/D81-specific "nothing to browse" message when the
browser finds no mountable disk image. Returning `0` keeps the framework
default.

Taken together, these seven callbacks are the whole story of how the C64's menu
behaves: the menu *structure* is declared in VHDL and mirrored through
`osm_const.asm`, and its *behavior* — boot-time setup, auto-resets, summaries,
filtering and validation — is these subroutines.

Debug mode
----------

If you do not have a
[JTAG adapter](https://files.mega65.org?ar=3c388c8c-bc3f-461b-84bb-e12dfd479ae2),
then you cannot use the debug mode.

The C64 core - like all MEGA65 cores powered by the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
framework - has a debug mode that consists of a real-time log of various system
states and an interactive debug console.

To access the log and the console, connect a serial terminal to the MEGA65
using the JTAG adapter while making sure that the serial terminal's parameters
are set to 115,200 baud 8-N-1, no flow control such as XON/XOFF, RTS/CTS,
DTR/DSR. Set any terminal emulation to "None" and if you can configure it,
set the send mode to "Interactive" (instead of things like "Line buffered").

To switch from the real-time log to the interactive mode, press
<kbd>Run/Stop</kbd> + <kbd>Cursor Up</kbd> and then while holding these press
<kbd>Help</kbd>.

Learn more about the debug mode in the MiSTer2MEGA65 Wiki in the "Hello World"
chapter, section
[Understanding the QNICE debug console](https://github.com/sy2002/MiSTer2MEGA65/wiki/3.-%22Hello-World%22-Tutorial#understanding-the-qnice-debug-console).

Main differences compared to the MiSTer core
--------------------------------------------

### Main clock speed

The Intel FPGA (platform for MiSTer) is able to synthesize clock frequencies with an
accuracy of around 1 Hz.  This is not possible on the Xilinx FPGA used by the MEGA65.

For instance, the official C64 clock speed (in PAL mode) is 0.985248 MHz.

On MiSTer the PLL generates a clock with 31.527954 MHz, which after a clock divider by 32
leads to a core clock frequency of 0.985249 MHz. In other words, MiSTer achieves practically
perfect accuracy of clock speed.

Our old core (before the flicker fix) had a PLL clock frequency of 31.527778 MHz, which
after the clock divider leads to C64 core frequency of 0.985243 MHz. So from a practical
point of view, this is still very close.

### Visual artifacts and dynamic HDMI flicker-fix

The official C64 has a frame rate of 985248/312/63 = 50.125 Hz. Since this is not exactly
50 Hz, this will inevitably lead to flickering and/or screen tearing when viewing on a
HDMI monitor. The reason is that HDMI only allows a pre-defined set of screen resolutions
and frame rates. The difference between the C64 frame rate of 50.125 Hz and the monitor
frequency of 50 Hz leads to tearing at a frequency of 0.125 Hz, i.e.  roughly every eight
seconds.

The "Dynamic HDMI flicker-fix" is meant to eliminate this screen tearing. This is done by
slowing down the core by approx 0.125/50.125 = 0.25%. The goal is to have the core
generate a frame rate of exactly 50 Hz. However, this requires a PLL frequency of
50\*63\*312\*32 = 31.449600 MHz, which unfortunately is not synthesizable on the Xilinx FPGA
in the MEGA65 (due to the before-mentioned limitations of the PLL).

The solution chosen is therefore to dynamically alternate the core frame rate between 50.1
Hz and 49.9 Hz. On average the core frame rate will be exactly 50 Hz, and this average is
achieved by continuously monitoring the input and output frame rates. More specifically,
the VGA-to-HDMI conversion is done by MiSTer's `ascal.vhd` module. Here the input frame
data is written to HyperRAM, and the output frame data is read from HyperRAM.

From a "helicopter-perspective", the `ascal.vhd` module acts as a regular FIFO, where the
filling level is determined by the difference between the current scan line generated by the
core, and the current scan line displayed on the HDMI. Whenever there is a FIFO underrun
or overflow, then visual screen tearing occurs.

So the "Dynamic HDMI flicker-free" works by continuously monitoring the FIFO level (i.e.
difference between input and output scan line), and - through a simple hysteresis
mechanism - switches between a "slow" core and a "fast" core. I.e. when the core is
running "slow" the FIFO filling is gradually decreasing, and when the core is running
"fast" the FIFO filling is gradually increasing.

For this to work, the PLL generates two different frequencies, and a glitch-free clock
multiplexer is subsequently used to dynamically switch between the two frequencies.

The M2M framework takes care of the FIFO level monitoring and the hysteresis, and outputs
two signals to the core, indicating when to switch over to the other clock frequency.  The
core may choose to ignore these signals, if the "Dynamic HDMI flicker-free" option is not
wanted.

Even though this "switching between two frame rates" works perfectly on the HDMI output,
it can lead to flickering on some VGA monitors. So for this reason, it is important to
have the option of disabling this feature.

### Keyboard

MiSTer uses a PS/2 keyboard and then translates the PS/2 keystrokes into
signals for the C64's CIA. This is done in `fpga64_keyboard.vhd` (located in
the file `CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd`).

Since the MEGA65 has a built-in keyboard, we routed the CIA signals on the
level of `fpga64_sid_iec` (located in the file
`CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd`)
so that our own `keyboard` entity (located in the file
`CORE/vhdl/keyboard.vhd`) can directly and latency-free generate the
appropriate signals for the C64's CIA.

### PHI2

For supporting hardware cartridges, one needs to output a correct PHI2
signal to the Expansion port. MiSTer did not offer a PHI2 signal. We added
it to `fpga64_sid_iec`. The exact timing of this PHI2 signal is very important (and
fragile), because it directly translates into a hardware signal used by the various
hardware cartridges.

### PLA

The MiSTer C64 core architecture does not "literally" implement a PLA chip
but bundles the PLA together with the ROMs and other logic in a VHDL entity
called `fpga64_buslogic` and located in
`CORE/C64_MiSTerMEGA65/rtl/fpga64_buslogic.vhd`.

We bugfixed and enhanced `fpga64_buslogic` and `fpga64_sid_iec` so that the
simulated PLA behaves according to the [correct logic formulas](PLA.md).

### Simulated cartridges

On the MiSTer platform, the simulated cartridges (`*.crt`) are loaded into SDRAM, and the
C64 CPU executes code directly from there. On the MEGA65 platform, the HyperRAM is shared
between the core and the framework (specifically the `ascal.vhd` VGA-to-HDMI converter).
Due to the behaviour and requirements of the `ascal.vhd`, the HyperRAM can be busy for
extended periods of time. This can lead to considerable latency when the core accesses
HyperRAM, i.e. more than 500 ns, which is the half clock cycle the C64 CPU has the bus.
Currently, the worst-case latency is around 1500 ns. In other words, it's not possible for
the C64 CPU to execute code directly from the HyperRAM, in the same way the MiSTer does.

Instead, we've taken a different approach, where we read the current ROM bank into a local
BRAM cache. In all the existing cartridge types, the switching of banks happen during a
read or write access to `$DExx` or `$DFxx`. If such a bank switching requires updating the
local BRAM cache, then the CPU is momentarily paused (using the DMA signal) while the BRAM
is filled. The maximum data rate available from the HyperRAM is 200 MB/second. The
`ascal.vhd` uses on average 50 % of this bandwidth.  Therefore, the time it takes to fill
one BRAM bank is on average 8192/100 = 82 CPU cycles.

Some cartridges switch banks multiple times each second (or even each frame), and
therefore a caching mechanism has been added, so the last eight banks used are stored in
BRAM.

While the above is not completely cycle accurate, in almost all cases the extra delays
caused by bank loading occur only during game initialization or when changing levels. In
practice, the player does not notice.

Another difference between MiSTer and our core is that the MiSTer decodes the file on the
fly and only stores the actual ROM bank contents in SDRAM. In our implementation we
store the complete CRT file (including all headers) in HyperRAM.

