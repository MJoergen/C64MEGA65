# Reset Architecture

This document is the reset guide for C64MEGA65. It is intentionally longer
than a source comment: reset is not one signal in this core, but a set of
policies layered over M2M, QNICE firmware, the C64 core, virtual drives,
HyperRAM/SDRAM, the HDMI scaler, hardware cartridges, and simulated
cartridges.

The short version is:

* A short MEGA65 reset button press resets the C64 side and the M2M memory
  clock-domain state used by the core, but it does not restart QNICE.
* A long MEGA65 reset button press resets the whole M2M framework and is the
  C64MEGA65 "hard reset" path.
* A QNICE menu reset through `M2M$CSR_RESET` is a smaller soft reset: C64 core
  only, no HyperRAM/SDRAM reset and no AV-pipeline disturbance.
* A soft reset starts or restarts cartridges. A hard reset exits cartridges.
* The QNICE firmware deliberately holds the core in reset during startup so
  menu/config/SD-card setup is stable before the C64 starts running.

Source references in this document point at the files as of this writing.
Line numbers will drift, but the named signals and blocks are the important
anchors.

## Mental Model

There are three levels that are easy to confuse:

1. **Framework reset rails** in `M2M/vhdl/reset_manager.vhd`,
   `M2M/vhdl/framework.vhd`, and `M2M/vhdl/clk_m2m.vhd`.
   These are board/framework-level resets such as `reset_m2m_n`,
   `reset_core_n`, `qnice_rst`, `hr_rst`, `sr_rst`, `audio_rst`, and
   `hdmi_rst`.

2. **Core reset inputs** into `CORE/vhdl/mega65.vhd` and then
   `CORE/vhdl/main.vhd`.
   These are `main_reset_m2m_i`, `main_reset_core_i`, local
   `main_reset_core` from the CRT loader, `main_reset_from_prgloader`,
   `reset_soft_i`, `reset_hard_i`, `cart_soft_reset_i`, and
   `cart_reset_i`.

3. **C64-specific reset meaning** inside `CORE/vhdl/main.vhd`.
   Here a reset is not just "put registers into known values". It also
   decides whether a cartridge should autostart, whether a reset-protected
   program should be escaped, whether disk-image writes may be interrupted,
   and whether the physical cartridge `/RESET` line should be driven or
   sensed.

The most important local rule is documented in `CORE/vhdl/main.vhd`:
do not use `reset_soft_i` or `reset_hard_i` directly throughout `main.vhd`.
Use the protected `reset_core_n` for ordinary consumers. `reset_core_n` is
gated by `prevent_reset`, which is asserted while any virtual-drive cache is
dirty. That protects disk images on the SD card from being reset while a
writeback is pending.

## Glossary

Most signals ending in `_n` are active low. Most M2M reset outputs such as
`qnice_rst`, `hr_rst`, `sr_rst`, `audio_rst`, and `hdmi_rst` are active high.
The names below are the ones used in the source.

| Signal | Active | Owner | Meaning |
| ------ | ------ | ----- | ------- |
| `reset_m2m_n` | low | `reset_manager` | Whole-framework reset rail after a long physical reset press. |
| `reset_core_n` in M2M | low | `reset_manager` | Framework core-reset rail after any physical reset press. |
| `qnice_rst` | high | `clk_m2m` | Resets QNICE and its MMIO registers. Depends on full M2M reset and QNICE PLL lock, not on short core reset. |
| `hr_rst` | high | `clk_m2m` | Resets HyperRAM-domain logic. Depends on full M2M reset, core reset, and QNICE PLL lock. |
| `sr_rst` | high | `clk_m2m` | Resets SDRAM-domain logic on boards that use SDRAM. Same policy as `hr_rst`. |
| `audio_rst` | high | `clk_m2m` | Resets audio-domain logic. Depends on full M2M reset and audio PLL lock. |
| `hdmi_rst` | high | `video_out_clock` | Resets HDMI output generation. Driven by full M2M reset/MMCM state, not by the QNICE menu reset. |
| `main_reset_m2m_i` | high | top -> `MEGA65_Core` | Core-domain copy of M2M reset; mapped to `reset_hard_i`. |
| `main_reset_core_i` | high | top -> `MEGA65_Core` | Core-domain copy of core reset plus QNICE CSR reset; mapped to `reset_soft_i` and `cart_soft_reset_i`. |
| `reset_soft_i` | high | `mega65.vhd` -> `main.vhd` | C64MEGA65 soft reset request. Minimum pulse is 32 `clk_main_i` cycles. |
| `reset_hard_i` | high | `mega65.vhd` -> `main.vhd` | C64MEGA65 hard reset request. Used for cartridge-exit semantics. |
| `reset_core_n` in `main.vhd` | low | `main.vhd` | Protected C64 reset used by most consumers. Gated by `prevent_reset`. |
| `hard_reset_n` | low | `main.vhd` | Not a general reset. It is the special hard-reset window used for CBM80 masking and simulated cartridge state reset. |
| `cart_reset_i` | low | cartridge port -> `main.vhd` | Physical cartridge reset request on boards that can sense the line. Treated like a soft reset. |
| `cart_reset_o`/`cart_reset_oe_o` | low/reset, high/OE | `main.vhd` -> cartridge port | Reset driven from the core to a physical cartridge when the core initiates reset. |
| `M2M$CSR_RESET` / `csr_reset_o` | high | QNICE firmware/register | Firmware-visible soft reset bit. Strict subset of a short button reset. |

## Reset Rails

### Physical Button Rails

The physical reset button enters `M2M/vhdl/reset_manager.vhd`. On R4/R5/R6
the board input is active high and the top file passes `not reset_button_i`
into the framework. On R3 the MAX10 controller provides `reset_n` to the
framework.

`reset_manager.vhd` debounces the button for 20 ms. After that:

* `reset_core_n_o` is asserted low immediately when the button is pressed.
* If the button stays pressed for `M2M_RST_TRIGGER = 1500` ms,
  `reset_m2m_n_o` is also asserted low.
* After the button is released, both reset rails remain asserted for
  `RST_DURATION = 50` ms before being released.

So the long press contains the short press: a long press first behaves as a
core reset, then escalates to a full M2M reset after about 1.5 seconds.

### Clock-Domain Resets

`M2M/vhdl/clk_m2m.vhd` turns those reset rails and MMCM lock signals into
domain-local resets:

* `qnice_rst` is asserted when QNICE PLL lock is missing or `sys_rstn_i`
  (`reset_m2m_n`) is low. A short reset does not reset QNICE.
* `hr_rst` and `sr_rst` are asserted when QNICE PLL lock is missing, full
  M2M reset is active, or `core_rstn_i` (`reset_core_n`) is low. This means a
  short button reset is still a HyperRAM/SDRAM-domain reset.
* `audio_rst` follows audio PLL lock and full M2M reset only.
* `hdmi_rst` is generated by the HDMI output clock block from full M2M reset
  and HDMI clock state.

The HyperRAM/SDRAM policy is deliberate. The Avalon memory clients and the
memory controllers keep burst/state information. Resetting only one side of
that relationship can leave the other side believing that a burst is still in
progress. Short physical reset therefore resets the memory-domain state even
though QNICE itself keeps running.

### QNICE CSR Reset

QNICE has an independent firmware-controlled reset bit:

* `M2M$CSR` lives at `$FFE0`.
* Bit 0 is `M2M$CSR_RESET`.
* In VHDL it is exported as `csr_reset_o <= reg_csr(0)`.

That signal is synchronized from `qnice_clk` into `main_clk_i` as
`main_qnice_reset_o` in `M2M/vhdl/framework.vhd`. The board top files then
OR it into `MEGA65_Core.main_reset_core_i` only. They intentionally do not
put it on the M2M/full reset rail.

That routing matters: if `M2M$CSR_RESET` were treated as a full M2M reset, it
would become `reset_hard_i` in `main.vhd`, mask CBM80, wipe simulated
cartridge state, and disturb the AV/HyperRAM pipeline. The firmware reset is
designed for menu-driven restarts where the picture should remain stable and
loaded cartridges should persist.

## Initiators

The reset initiators in this design are:

| Initiator | Source | Reset path | Main intent |
| --------- | ------ | ---------- | ----------- |
| FPGA power-on / MMCM not locked | Clocking and reset logic | Domain resets until clocks lock; QNICE CSR defaults to reset asserted | Bring every clock domain up in a known state. |
| QNICE reset / full M2M reset release | `qnice_rst` -> `qnice.vhd` register defaults | `reg_csr <= x"0839"`, so `csr_reset_o = 1` | Keep the core in reset until firmware has configured it. |
| Short MEGA65 reset button press | `reset_manager.vhd` | `reset_core_n = 0`; also `hr_rst`/`sr_rst` through `clk_m2m` | User soft reset of the C64 side. |
| Long MEGA65 reset button press | `reset_manager.vhd` after 1.5 s | `reset_m2m_n = 0`, `qnice_rst`, `audio_rst`, `hdmi_rst`, `hr_rst`, `sr_rst`, and `main_reset_m2m_i` | Full framework reset and C64MEGA65 hard reset. |
| Main/core MMCM reset | `CORE/vhdl/clk.vhd` -> `main_rst` | Top files OR `main_rst` into `main_reset_m2m_i` | Treat loss of the core clock as a hard core reset. |
| Firmware startup hold/release | QNICE CSR default plus `RP_SYSTEM_START` / `START_CONNECT` | `M2M$CSR_RESET` held then cleared | Keep C64 stopped until SD/config/menu/core prep has completed. |
| Firmware runtime reset helper | `CORE/m2m-rom/m2m-rom.asm` `RESET_CORE` | Pulse `M2M$CSR_RESET` with delay | Soft reset C64 after OSM settings that need restart. |
| OSM Kernal mode change | `OSM_SEL_POST` | `RESET_CORE` | Restart C64 so the selected Kernal mode is used from boot. |
| OSM expansion-port mode change | `OSM_SEL_POST` | `RESET_CORE` | Restart after switching hardware slot vs simulated cartridge mode. |
| OSM simulated REU toggle | `OSM_SEL_POST` | `RESET_CORE` | Restart with REU visibility/state coherent. |
| OSM CRT-load pre-transition | `OSM_SEL_PRE` | Force simulated cartridge mode, then `RESET_CORE` if hardware slot was active | Park the C64 while the hardware slot is decoupled and the file selector opens. |
| `.crt` parser reaches READY | `sw_cartridge_wrapper.vhd` | Local `main_reset_core_o` into `reset_soft_i` only | Start the newly loaded software cartridge after bank 0 is cache-ready. |
| `.prg` load request | `prg_loader.vhd` | `core_reset_o` -> `main_reset_from_prgloader` -> `reset_hard_i` | Reset C64 before injecting PRG data and triggering RUN. |
| Physical cartridge `/RESET` | Expansion port, R5/R6 and newer | `cart_reset_i = 0` -> protected `reset_core_n` | Let cartridges reset the C64. |
| EF3 reset workaround | `cartridge_heuristics.vhd` + `cart_reset_counter`, R3/R4 | Internal reset counter -> protected `reset_core_n` | Emulate cart-driven reset on boards that cannot sense cartridge `/RESET`. |
| Virtual drive not mounted | `vdrives.vhd` / `main.vhd` | Per-drive reset only | Hold an individual simulated IEC drive in reset until mounted. |

Opening the OSM itself is not a reset initiator. It may pause the core and
disconnect/reconnect keyboard/joysticks depending on configuration, but reset
only happens in C64-specific callbacks for settings that need it.

Changing the HDMI filter also does not reset the core. The C64-specific
callback reloads ascal coefficient RAM and lets the running C64 continue.

## Consumers

### M2M / Framework Consumers

| Consumer | Reset input | Reset by short button | Reset by long button | Reset by QNICE `M2M$CSR_RESET` | Notes |
| -------- | ----------- | --------------------- | -------------------- | ------------------------------ | ----- |
| QNICE CPU and QNICE MMIO registers | `qnice_rst` / `reset_ctl` | No | Yes | No | `reg_csr`, OSM registers, control flags, RAM/ROM window registers reset to defaults. |
| QNICE CSR bit outputs | `reg_csr` reset to `x"0839"` | No | Yes | No, except firmware writes bit 0 | Bit 0 defaults asserted. |
| SDMux / SD control in QNICE wrapper | QNICE reset/control | No | Yes | No | SD-card hardware is managed by QNICE. |
| HyperRAM domain | `hr_rst` | Yes | Yes | No | Includes HyperRAM controller/arbiters and HyperRAM-side Avalon clients. |
| SDRAM domain | `sr_rst` | Yes | Yes | No | Present on newer boards for ascal/framebuffer paths. |
| Ascal scaler | `reset_na = not (video_rst_i or hr_rst_i)` | Yes, through `hr_rst` | Yes | No | Also resets when core video reset is active. |
| HDMI output clock / TMDS | `hdmi_rst` | No | Yes | No | Short button can disturb ascal/memory path, but not the HDMI output clock reset. |
| Audio domain | `audio_rst` | No | Yes | No | The C64 audio source may reset, but the audio clock domain reset is full-reset only. |
| OSM visibility | `csr_osm_o` and OSM registers | No | Yes | No, unless firmware writes CSR bit 2 | OSM control flags reset when QNICE resets. |

### CORE / C64 Consumers

| Consumer | Reset input | Soft reset | Hard reset | QNICE CSR reset | Notes |
| -------- | ----------- | ---------- | ---------- | --------------- | ----- |
| MiSTer C64 top `fpga64_sid_iec` | `reset_n => reset_core_n` | Yes, unless `prevent_reset` blocks it | Yes | Yes, unless `prevent_reset` blocks it | This fans into CPU, VIC-II, SID, CIAs, bus logic, TOD, etc. |
| C64 RAM read mux | `hard_reset_n` only for CBM80 masking | No CBM80 mask | CBM80 mask active after cold start | No CBM80 mask | The mux is also where hardware/sim cart data is selected. |
| C64 RAM BRAM | No C64 reset port | Not hardware-cleared | Not hardware-cleared | Not hardware-cleared | Preloaded from `ram_init.hex` at FPGA initialization; later reset behavior is software/KERNAL behavior plus the read mux. |
| Simulated cartridge state machine | `rst_i => not hard_reset_n` | No wipe; soft reset enters through `cart_loading_i` | Wiped/neutralized | No wipe | This split is required for cart autostart on soft reset. |
| Simulated cartridge bank cache | `cart_soft_reset` to loader/cacher | Reloads bank 0 on OSM/menu soft reset | Loader reset through hard/full paths | Reloads bank 0 | The post-parse wrapper reset is deliberately excluded from `cart_soft_reset_i`. |
| Physical cartridge `/RESET` output | `reset_core_int_n` | Driven low for core-originated reset | Driven low for core-originated reset | Driven low if reset is not blocked | Uses `reset_core_int_n`, not `reset_core_n`, to avoid echoing a cartridge-originated reset back to the cartridge. |
| Physical cartridge `/RESET` input | `cart_reset_i` | Acts like soft reset | N/A | N/A | Only sensed on R5/R6 and newer. R3/R4 hardwire no incoming cart reset. |
| REU core and REU HyperRAM mapper/cache | `not reset_core_n` | Yes | Yes | Yes | Soft reset clears C64-visible REU logic. |
| Keyboard adapter | `not reset_core_n` | Yes | Yes | Yes | QNICE CSR bits separately gate whether keyboard is connected. |
| Virtual drives | `reset_core_i => not reset_core_n` | Yes, if not blocked | Yes | Yes, if not blocked | Reset clears mounted state and QNICE-domain vdrive registers. Dirty cache blocks standard C64 reset. |
| Simulated IEC drive cores | `not reset_core_n` or not mounted | Yes | Yes | Yes | Drives are held reset until mounted. |
| Hardware IEC reset output | `iec_reset_n_o <= reset_core_n` when hardware IEC enabled | Yes | Yes | Yes | External IEC devices see reset with the C64 side. |
| RTC emulator `rtcF83` | `reset => reset_hard_i` | No | Yes | No | Exception: wired directly to hard reset input. |
| PRG autostart trigger | `trigger_run_i` from `prg_loader` | N/A | Reset before trigger | N/A | Loader waits after reset, writes pointers, then pulses trigger-run. |

### `main.vhd` Reset Engine

`CORE/vhdl/main.vhd` is where the generic reset rails become C64 behavior.
It does not simply forward `reset_soft_i` to the MiSTer core. It derives
several local signals, each with a different job:

| Local signal | How it is produced | What it means |
| ------------ | ------------------ | ------------- |
| `prevent_reset` | `1` when any `cache_dirty` bit from `vdrives` is set | A virtual-drive writeback is pending; standard C64 resets must be blocked to avoid disk-image corruption. |
| `cart_soft_reset` | `cart_soft_reset_i and not prevent_reset` | OSM/menu soft reset that should also make SIMCRT reload bank 0 and re-run cartridge load behavior. |
| `reset_core_int_n` | Internal result of `hard_reset_proc` | Core-originated C64 reset request before physical cartridge reset is considered. |
| `reset_core_n` | `reset_core_int_n` plus physical `cart_reset_i` | Final protected active-low reset used by almost all C64-side consumers. |
| `hard_reset_n` | Separate hard-reset window with its own counter | Not the normal reset line. Used for cartridge-exit behavior and `cartridge.vhd` reset. |
| `cold_start_done` | Set after the first rising edge of `hard_reset_n` | Prevents CBM80 masking on the very first boot, so a real plugged-in cartridge can autostart. |

The reset decision in `hard_reset_proc` can be read as this truth table:

| Situation | `prevent_reset` | `reset_hard_i` | `reset_core_int_n` | `hard_reset_n` |
| --------- | --------------- | -------------- | ------------------ | -------------- |
| Soft reset, no dirty vdrive cache | 0 | 0 | 0, so C64 resets | unchanged/high |
| Soft reset, dirty vdrive cache | 1 | 0 | 1, so C64 reset is blocked | unchanged/high |
| Hard reset | 0 or 1 | 1 | 0, so C64 resets | forced low and delay counter loaded |
| EF3 internal reset counter, no dirty cache | 0 | 0 | 0, so C64 resets | unchanged/high |
| EF3 internal reset counter, dirty cache | 1 | 0 | 1, so reset is blocked | unchanged/high |

When no reset request is active anymore, `reset_core_int_n` returns high
immediately. `hard_reset_n` may remain low for `C_HARD_RST_DELAY = 100_000`
main-clock cycles after that. This is intentional: during that window the
C64 core is running again, but the read mux still knows that a hard reset is
in progress and can hide CBM80 from the KERNAL.

`combined_reset_proc` then builds the final C64 reset:

* If `reset_core_int_n = 0`, then `reset_core_n = 0`.
* Otherwise, if a physical cartridge pulls `cart_reset_i = 0` and
  `prevent_reset = 0`, then `reset_core_n = 0`.
* Otherwise, `reset_core_n = 1`.

That means a physical cartridge reset is soft-reset-like and dirty-cache
protected. It also means `cart_reset_i` is not gated by SIMCRT vs hardware
slot mode; on R5/R6 a real cartridge holding `/RESET` low can still reset
the C64 even while the menu is in simulated-cartridge mode.

### What `reset_core_n` Actually Resets

The final `reset_core_n` signal is the reset input for the C64-side logic
that should behave like the machine was reset:

* `fpga64_sid_iec.reset_n` receives `reset_core_n`. Inside the MiSTer C64
  top, this reset is sampled into the local `reset` signal and then forwarded
  to reset-aware machine components: the 6510 wrapper, VIC-II, SID, CIAs, bus
  logic, and TOD-related logic. The master cycle generator itself keeps
  running; reset is a machine/peripheral reset, not a stop-the-clock event.
* The keyboard adapter receives `reset_i => not reset_core_n`.
* The simulated REU receives `reset => not reset_core_n`.
* The REU-to-HyperRAM mapper and its Avalon cache receive
  `rst_i => not reset_core_n`.
* `vdrives.vhd` receives `reset_core_i => not reset_core_n`, clearing its
  core-domain mount state and synchronized QNICE-domain vdrive registers.
* Each simulated IEC drive reset bit is
  `(not reset_core_n) or (not vdrives_mounted(i))`. A drive is therefore held
  reset until an image is mounted, even if the C64 itself is running.
* If the hardware IEC port is enabled, `iec_reset_n_o <= reset_core_n`, so
  external IEC devices see the C64 reset.
* The IEC drive clock-enable generator clears its accumulator when
  `reset_core_n = 0`, so the simulated drive timing restarts cleanly.

There are also important things `reset_core_n` does **not** do:

* It does not clear the external C64 RAM BRAM. `main.vhd` drives the RAM
  address, data, chip-enable, and write-enable, but the RAM block in
  `mega65.vhd` has no C64 reset clear. It is preloaded from `ram_init.hex` at
  FPGA initialization, but later C64 resets do not reload that file. Real C64
  RAM is not cleared by reset either; the KERNAL/software startup path decides
  what memory contents mean.
* It does not reset QNICE, the OSM control registers, or the firmware state.
* It does not by itself create the CBM80 mask. That mask is controlled by
  `hard_reset_n`.
* It does not reset the RTC emulator. `rtcF83` is wired directly to
  `reset_hard_i`, so it only follows the hard-reset/PRG-load hard path.

### C64 Data Mux During Reset

The C64 core reads a byte through `cpu_data_in_proc`. The order of this mux is
part of reset behavior:

1. If `hard_reset_n = 0`, `cold_start_done = 1`, and the C64 address is in
   `$8000-$8FFF`, return `$00`.
2. Else, if hardware cartridge mode is selected and the C64 is reading a
   hardware cartridge window, return `data_from_cart`.
3. Else, if simulated cartridge mode is selected and the C64 is reading a
   simulated cartridge ROM/IO window, return the corresponding CRT cache or
   cartridge IO byte.
4. Else, return normal C64 RAM data from `c64_ram_data_i`.

The first rule deliberately wins over both hardware and simulated cartridge
data. That is the whole hard-reset cartridge-exit mechanism. It only masks
`$8xxx`, because hiding the CBM80 signature at `$8003` is enough to prevent
KERNAL cartridge autostart.

### Expansion-Port Reset Details In `main.vhd`

The physical expansion port has its own reset concerns:

* `cart_en_o` is always driven high. This is not a reset policy, but it is a
  reset-adjacent trap: on R5/R6, disabling the cartridge-port level shifter
  breaks joystick port B.
* In hardware-slot mode, the core drives ROML/ROMH/IO1/IO2/RW/address toward
  the cartridge, but address/control timing is carefully registered. PHI2,
  DotCLK, and BA are not registered because they already come from clean core
  outputs and must stay phase-faithful.
* Cartridge `/RESET` defaults to sense/read mode. `main.vhd` switches it to
  drive mode only when the core has its own reset to send to the cartridge.
* The reset driven to the cartridge is based on `reset_core_int_n`, not
  `reset_core_n`. This prevents a cartridge-originated reset from being
  echoed back into the cartridge.
* In simulated-cartridge mode, EXROM/GAME/NMI/IO data come from
  `cartridge.vhd` and the CRT cache, not from the physical slot. The physical
  slot can still pull `/RESET` low on boards where that line is sensed.

### Expansion-Port Consumers Inside The C64 Core

`handle_cores_expansion_port_signals_proc` decides what the MiSTer C64 core
sees on its cartridge/expansion inputs:

* In SIMCRT mode, `core_game_n` and `core_exrom_n` come from
  `cartridge.vhd`; `core_dma` is asserted while a cartridge is loading or a
  CRT bank cache fill is in progress; `core_nmi_n` comes from simulated
  cartridge NMI handling, including Restore/freeze behavior.
* In hardware-slot mode, `core_game_n`, `core_exrom_n`, IRQ, NMI, DMA, and
  IO data come from the physical port. Restore is ANDed into NMI so the C64
  still sees the Restore key as an NMI source.
* If SIMREU is enabled, REU DMA is ORed into `core_dma`. The `$DF00-$DF1F`
  range is forwarded to the REU, replacing the cartridge IOF data path only
  for that narrow address range.

So reset and expansion-port state meet in two places: reset decides whether
the machine restarts, and the expansion-port mux decides what external or
simulated device the restarted machine sees while it boots.

## Initiator To Consumer Matrix

This table is deliberately redundant. It is the fastest way to answer
"what does this reset actually hit?"

| Initiator | C64 core | Hard reset / CBM80 mask | Sim cart state | Physical cart reset output | HyperRAM/SDRAM/ascal | QNICE/OSM registers | HDMI/audio reset | Vdrives/cache protection |
| --------- | -------- | ----------------------- | -------------- | -------------------------- | -------------------- | ------------------- | ---------------- | ------------------------ |
| Power-on before QNICE firmware release | Held in reset by CSR bit 0 and clock-domain resets | Main/core MMCM reset can assert the hard path, but `cold_start_done = 0` prevents CBM80 masking on first boot | Neutral until loaded | Not meaningful until core runs | Domain resets until clocks lock | Reset to defaults (`x"0839"`, control flags zero) | Reset until clocks lock | Not active yet |
| Firmware startup release | Starts C64 when CSR bit 0 is cleared | No | Preserved if already configured | No extra reset beyond core reset | No | CSR bit 0 cleared by firmware | No | N/A |
| Short reset button | Yes | No | Preserved/re-autostarts | Yes, if in hardware slot mode and not cartridge-originated | Yes | No | No QNICE/audio/HDMI clock reset | `prevent_reset` can block C64-side reset while cache dirty |
| Long reset button | Yes | Yes | Reset to neutral/exit | Yes | Yes | Yes | Yes | Hard reset overrides `prevent_reset` |
| QNICE `RESET_CORE` helper | Yes | No | Preserved/re-autostarts; bank 0 cache reload via `cart_soft_reset` | Yes, if not blocked and hardware slot mode | No | No, except CSR bit 0 pulse | No | `prevent_reset` can block C64-side reset while cache dirty |
| OSM Kernal/EXP_PORT/REU change | Same as QNICE `RESET_CORE` | No | Preserved/re-autostarts | Same as QNICE reset | No | OSM setting bits already updated | No | Same as QNICE reset |
| OSM CRT-load pre-transition | Same as QNICE `RESET_CORE`, only when switching from hardware slot | No | Existing cart preserved until new load flow | Hardware slot decoupled first | No | Menu bit forced to SIMCRT | No | Same as QNICE reset |
| `.crt` parse READY | Yes, via local wrapper reset | No | Newly loaded cart state preserved | No, excluded from `cart_soft_reset_i` | No | No | No | Not dirty-cache gated in wrapper; reset width is local and cache-ready gated |
| `.prg` load request | Yes | Yes, because wired to `reset_hard_i` | Reset to neutral/exit | Yes | No M2M HR reset from this path | No | No | Hard-reset semantics in `main.vhd` |
| Physical cart `/RESET` on R5/R6 | Yes | No | If SIMCRT mode, real cart can still reset the core because `cart_reset_i` is not mode-gated | Cartridge-originated, so not echoed back | No | No | No | Blocked while `prevent_reset = 1` |
| EF3 heuristic reset on R3/R4 | Yes | No | Hardware-cart workaround only | Internal reset counter drives local reset behavior | No | No | No | Same protected C64 reset path |
| Virtual drive not mounted | Only drive core held reset | No | No | No | No | No | No | Per-drive reset, not global |

## Startup Timeline

The firmware startup behavior is important because it explains why the C64
does not start immediately after the FPGA clocks become valid.

1. **Clock/reset hardware comes up.**
   `clk_m2m.vhd` holds QNICE, memory, audio, and video-related reset domains
   until their clocks are locked and the full system reset is released.
   Separately, the core MMCM reset `main_rst` is ORed into
   `main_reset_m2m_i`, so the `main.vhd` hard-reset path can be active during
   clock startup. `cold_start_done` is still `0` at this point, so the CBM80
   mask is disabled and a real cartridge can autostart on first boot.

2. **QNICE registers reset to defaults.**
   `M2M/vhdl/QNICE/qnice.vhd` sets `reg_csr <= x"0839"` whenever QNICE reset
   is active. That means:
   * bit 0 reset is asserted;
   * pause and OSM overlay are off;
   * keyboard and joystick connections default on;
   * SD card mode is auto;
   * ascal auto-sync defaults on.

3. **The C64 is held in reset before firmware policy runs.**
   This is intentional. The comment above `CSR_DEFAULT` explains the reason:
   without reset asserted by default, the core could see a flickering reset
   sequence during firmware initialization. Some cores do not tolerate that,
   and the M2M menu/config code also needs time to prepare SD-card and menu
   state.

4. **`START_SHELL` records an SD-card stabilization deadline.**
   `M2M/rom/shell.asm` stores the current 50 MHz system cycle counter and
   defines a target of `SD_WAIT = 0x05F6` mid-counter ticks, about two
   seconds. `WAIT_FOR_SD` later waits until that deadline, but only once per
   shell start.

5. **Shell libraries and menu state initialize while reset is still asserted.**
   `START_SHELL` initializes file handles, browser state, screen/menu
   support, virtual drives, CRT/ROM loading, keyboard support, and then calls
   `HELP_MENU_INIT`.

6. **Config loading can wait for SD while the C64 is stopped.**
   In the current C64MEGA65 config, `SAVE_SETTINGS = true`, so
   `HELP_MENU_INIT` calls `WAIT_FOR_SD` before mounting the SD card for the
   config file. The code comment explicitly relies on the core still being in
   reset at this point.

7. **ROM autoload runs before reset management completes.**
   `CRTROM_AUTOLOAD` is called before `RP_SYSTEM_START`. It reuses the config
   SD handle if available, or calls `WAIT_FOR_SD` itself if it must mount SD
   independently. `WAIT_FOR_SD` is idempotent via `SD_WAIT_DONE`.

8. **`RP_SYSTEM_START` applies reset/pause configuration and releases reset.**
   `M2M/rom/gencfg.asm` reads the `SEL_GENERAL` config block, waits
   `M2M$CFG_RP_COUNTER`, then clears `M2M$CSR_RESET`. In this core,
   `RESET_COUNTER = 100`, so there is an additional small firmware busy-loop
   hold after config setup.

9. **C64-specific `PREP_START` runs after the common firmware setup.**
   `CORE/m2m-rom/m2m-rom.asm` applies C64-specific startup work such as HDMI
   filter/ascal setup and optional JiffyDOS fallback checks.

10. **`START_CONNECT` waits about 333 ms, clears reset again, and reconnects
    inputs.**
    The second reset clear is defensive. In current code `RP_SYSTEM_START`
    already clears reset, but older comments still refer to a conceptual
    `RESET_KEEP` mode. `START_CONNECT` also ORs keyboard and joystick bits
    back into `M2M$CSR` so the key used to leave a splash/menu does not leak
    immediately into the C64.

The practical result: on a normal boot with settings saved, the C64 is held
in reset across firmware initialization and the SD-card stabilization window,
then released only after the menu/control registers are valid.

## Runtime Flows

### Short MEGA65 Reset Button

After debounce, `reset_manager` asserts `reset_core_n_o = 0`. It does not
assert `reset_m2m_n_o` unless the press lasts at least 1.5 seconds.

Consequences:

* `framework.vhd` synchronizes `not reset_core_n` into `main_clk_i` as
  `main_reset_core_o`.
* `clk_m2m.vhd` asserts `hr_rst` and `sr_rst`, because those resets depend on
  `core_rstn_i`.
* `mega65.vhd` maps `main_reset_core_i` to `main.vhd` `reset_soft_i` and
  `cart_soft_reset_i`.
* `main.vhd` asserts protected `reset_core_n` unless `prevent_reset` is high.
* `hard_reset_n` is not asserted, so CBM80 is not masked and cartridge state
  is not wiped.

This is the user-visible normal C64 reset: reset the machine, but let
cartridges boot again.

### Long MEGA65 Reset Button

A long press first does everything a short press does. After about 1.5 s,
`reset_manager` asserts `reset_m2m_n_o = 0`.

Consequences:

* `qnice_rst` resets QNICE and all QNICE MMIO registers.
* `reg_csr` returns to `x"0839"`, so the core is held in reset again until
  firmware releases it.
* `hr_rst`, `sr_rst`, `audio_rst`, and HDMI reset paths assert as full-system
  resets.
* `main_reset_m2m_i` is asserted and `mega65.vhd` maps it to
  `main.vhd` `reset_hard_i`.
* `main.vhd` starts the hard-reset window (`hard_reset_n = 0`) and sets
  `hard_rst_counter = C_HARD_RST_DELAY`.

This is the "exit the cartridge / escape reset protection / restart the
framework" reset.

### Firmware `RESET_CORE`

`CORE/m2m-rom/m2m-rom.asm` implements the helper:

1. OR `M2M$CSR_RESET` into `M2M$CSR`.
2. Run a 64-iteration delay loop.
3. AND `M2M$CSR_UN_RESET` into `M2M$CSR`.

The delay loop exists because a bare OR/AND pair would be too narrow after
the two flip-flop CDC in `framework.vhd`. `main.vhd` requires any
`reset_soft_i` pulse to be at least 32 main-clock cycles wide.

This reset does not touch the M2M reset manager, HyperRAM/SDRAM resets, QNICE
reset, HDMI reset, or audio reset. It is used when the menu changes C64
configuration that only needs the C64 to reboot.

### `.crt` Load Flow

There are two separate soft reset paths around simulated cartridges:

1. **Before opening the CRT file selector**, `OSM_SEL_PRE` forces the menu
   into simulated-cartridge mode. If the previous mode was hardware slot, it
   calls `RESET_CORE`. This avoids leaving the running C64 attached to a
   suddenly disappearing physical cartridge while the file selector is open.

2. **After a `.crt` file parses successfully**, `sw_cartridge_wrapper.vhd`
   pulses its local `main_reset_core_o` for 66 shift-register cycles and keeps
   it asserted while the bank cache is still waiting. `mega65.vhd` ORs that
   into `reset_soft_i`.

The second reset is deliberately not fed into `cart_soft_reset_i`.
`cart_soft_reset_i` is the path that re-runs cartridge loading behavior in
`cartridge.vhd`; using it at the wrong time would wipe the just-installed
cart state. This is why `mega65.vhd` maps:

* `reset_soft_i => main_reset_core_i or main_reset_core`
* `cart_soft_reset_i => main_reset_core_i`

where `main_reset_core` is the wrapper-local post-parse reset.

### `.prg` Load Flow

`CORE/vhdl/prg_loader.vhd` has a state machine that:

1. Detects a QNICE load request.
2. Asserts `core_reset_o` for `C_COMM_DELAY = 50` QNICE cycles.
3. Releases reset and waits with `C_RESET_DELAY = 4 * CORE_CLK_SPEED` loaded
   into the QNICE-clocked state-machine delay counter while the C64 boots far
   enough for the loader protocol.
4. Writes the end/start pointer information.
5. Pulses `core_triggerrun_o` so the C64 starts the program.

Despite the local name `core_reset_o`, `mega65.vhd` synchronizes this as
`main_reset_from_prgloader` and ORs it into `reset_hard_i`. Therefore PRG
loading uses hard-reset semantics in `main.vhd`, including CBM80 masking and
simulated cartridge neutralization.

The source comment next to `C_RESET_DELAY` says "3 seconds", but the code is
`4 * CORE_CLK_SPEED` and the counter is decremented in the `qnice_clk_i`
process. Treat the expression and clocked process as authoritative.

### Physical Cartridge Reset

On R5/R6 and newer, the cartridge `/RESET` pin is bidirectional. The top file
passes it into `main.vhd` as `cart_reset_i`. When the cartridge pulls it low,
`combined_reset_proc` treats it like a soft reset if `prevent_reset = 0`.

When the core itself resets and hardware-cartridge mode is active, `main.vhd`
drives `cart_reset_o` low to reset the cartridge too. It uses
`reset_core_int_n`, not `reset_core_n`, so a reset that originated from the
cartridge is not immediately driven back to the cartridge.

On R3/R3A/R4, the board cannot sense the cartridge reset line. The top files
wire `cart_reset_i => '1'`. For EasyFlash 3, `cartridge_heuristics.vhd`
recognizes a specific bus access fingerprint and `main.vhd` converts a later
EF3 mode write to `$DE0F` into an internal reset pulse of
`C_EF3_RESET_LEN = 7` PHI2 cycles. EF3 mode `$02` is intentionally not
supported because it would require A14 behavior that risks a bus fight through
the transceiver.

## Cartridge Reset Semantics And CBM80

This is the part that usually causes confusion.

On a real C64, normal 8K/16K cartridges autostart because the KERNAL reset
routine checks for the ASCII signature `CBM80` at `$8003`. If it sees the
signature, it jumps through the cartridge cold-start vector at `$8000`.

C64MEGA65 uses this behavior deliberately:

* **Soft reset should start cartridges.**
  The CBM80 bytes must remain visible. Hardware cartridges and simulated
  cartridges should autostart again after a short reset or QNICE menu reset.

* **Hard reset should exit cartridges.**
  Reset-protected games and loaded simulated cartridges need an escape path.
  During a hard reset, `main.vhd` masks reads from `$8000-$8FFF` to `$00`
  while `hard_reset_n = 0` and `cold_start_done = 1`. That hides CBM80 from
  the KERNAL, so the KERNAL performs a normal C64 start instead of jumping
  into the cartridge.

The code cannot implement the hard-reset behavior in the most "real C64"
way by manipulating EXROM, because the MiSTer C64 core does not expose the
needed path for that. The chosen workaround is the C64 RAM/cart read mux in
`cpu_data_in_proc`.

`cold_start_done` is the other important guard. On the first launch after the
core comes up, C64MEGA65 must not hide CBM80, otherwise a real cartridge
plugged into the MEGA65 expansion port would not autostart. Therefore the
mask is only active after the first hard-reset window has completed once.

Simulated cartridges add one more subtlety. `cartridge.vhd` has two different
control inputs:

* `rst_i`, wired to `not hard_reset_n`, resets EXROM/GAME/banks to neutral.
* `cart_loading_i`, ORed with `cart_soft_reset`, re-runs the per-cart loading
  branch that makes a cart visible and ready to autostart.

This is why soft reset does not wipe `cartridge.vhd`, and hard reset does.
It is also why OSM-driven soft resets send `cart_soft_reset` to the
`sw_cartridge_wrapper`: the cacher needs a fresh bank 0 load so CBM80 is
present again when the KERNAL checks `$8003`.

## QNICE CSR Signals At `qnice.vhd:263-271`

The relevant code is:

```vhdl
csr_reset_o       <= reg_csr(0);
csr_pause_o       <= reg_csr(1);
csr_osm_o         <= reg_csr(2);
csr_keyboard_o    <= reg_csr(3);
csr_joy1_o        <= reg_csr(4);
csr_joy2_o        <= reg_csr(5);
sd_mode           <= reg_csr(6);
sd_inuse_wr       <= reg_csr(7);
ascal_usage       <= reg_csr(11);
```

These are direct combinational exports of bits from `reg_csr`; they are not
one-shot pulse generators.

`reg_csr` is reset in `handle_regs` on the falling edge of `clk50_i` whenever
`reset_ctl = 1`. `reset_ctl` is generated from the QNICE pre/post power-on
reset logic. On that reset, `reg_csr <= CSR_DEFAULT`, and
`CSR_DEFAULT = x"0839"`.

When `reset_ctl = 0`, a QNICE write to `$FFE0` replaces the whole CSR word
with `cpu_data_out`. Firmware uses OR masks such as `M2M$CSR_RESET` and AND
masks such as `M2M$CSR_UN_RESET` to change one bit without destroying the
other bits.

| Export | CSR bit | Default from `x"0839"` | Asserted when | Deasserted when | Main consumers |
| ------ | ------- | ---------------------- | ------------- | --------------- | -------------- |
| `csr_reset_o` | 0 | 1 | QNICE reset/default, or firmware writes bit 0 as 1 | Firmware writes bit 0 as 0 | Crosses to `main_qnice_reset_o`, then `main_reset_core_i`, then `reset_soft_i`. |
| `csr_pause_o` | 1 | 0 | Firmware writes bit 1 as 1 | Firmware writes bit 1 as 0 | Crosses to `main_pause_core_i`; pauses C64 core and IEC drive logic. |
| `csr_osm_o` | 2 | 0 | Screen/menu firmware sets OSM visible | Firmware hides OSM | Enables OSM overlay in video pipeline. This is visibility, not menu state. |
| `csr_keyboard_o` | 3 | 1 | Firmware writes bit 3 as 1 | Firmware writes bit 3 as 0 | Gates MEGA65 keyboard connection into the core. |
| `csr_joy1_o` | 4 | 1 | Firmware writes bit 4 as 1 | Firmware writes bit 4 as 0 | Gates joystick port 1 connection. |
| `csr_joy2_o` | 5 | 1 | Firmware writes bit 5 as 1 | Firmware writes bit 5 as 0 | Gates joystick port 2 connection. |
| `sd_mode` | 6 | 0 | Firmware writes bit 6 as 1 | Firmware writes bit 6 as 0 | Selects forced SD-card mode vs auto mode. |
| `sd_inuse_wr` | 7 | 0 | Firmware writes bit 7 as 1 | Firmware writes bit 7 as 0 | Selects forced internal/external card when forced mode is active. |
| `ascal_usage` | 11 | 1 | Firmware writes bit 11 as 1 | Firmware writes bit 11 as 0 | Selects whether `ascal_mode_o` follows `ascal_mode_i` automatically. |

The 256-bit menu state is not `csr_osm_o`. Menu state is `control_m_o`,
written through `$FFF2`/`$FFF3`, synchronized as `qnice_osm_control_m_o` and
then `main_osm_control_i`. `csr_osm_o` only says whether the overlay is drawn.

## Data Integrity Rules

The reset system has disk-image safety logic because virtual drives cache
writes before flushing them to SD.

`main.vhd` receives `cache_dirty` from `vdrives.vhd`. If any bit is set:

* `prevent_reset = 1`
* ordinary soft reset is blocked at `reset_core_n`
* cartridge-originated reset is blocked
* `cart_soft_reset` is blocked
* the drive LED is forced on/yellow

Hard reset overrides this protection. That is a conscious tradeoff: a long
reset is the user's emergency escape hatch, but it can interrupt pending
writeback.

One caveat: `prevent_reset` lives inside `CORE/vhdl/main.vhd`. It protects
the C64-side reset consumers. It does not feed back into `M2M/vhdl/clk_m2m.vhd`.
Therefore a short physical reset still asserts `hr_rst`/`sr_rst` at the
framework level even if the C64-side reset is blocked by a dirty vdrive cache.

Firmware also avoids saving OSM settings while vdrive cache is dirty because
the config save and vdrive writeback share SD resources.

## Board Differences

* **R3/R3A**: reset button comes through MAX10. Cartridge `/RESET` cannot be
  sensed by the FPGA; top file wires `cart_reset_i => '1'`.
* **R4**: cartridge `/RESET` is also not sensed; top file wires
  `cart_reset_i => '1'`.
* **R5/R6 and newer**: cartridge `/RESET` is bidirectional and true
  cart-originated reset is supported.
* **R3 HyperRAM pressure**: ascal, QNICE, and core-side users share
  HyperRAM more tightly, so the "reset both sides of the Avalon state"
  requirement is especially visible.
* **R4/R5/R6 SDRAM ascal path**: ascal frame-buffer use moves to SDRAM, but
  the reset policy remains: short physical reset still asserts memory-domain
  resets; QNICE menu reset does not.

## Requirements For Future Changes

1. **Keep `M2M$CSR_RESET` on the core soft-reset rail only.**
   Do not route it to `main_reset_m2m_i` or any full M2M reset path. Menu
   resets must not become hard resets.

2. **Any new `reset_soft_i` source must be at least 32 `clk_main_i` cycles.**
   Existing sources honor this: M2M reset manager, QNICE `RESET_CORE`, and
   `sw_cartridge_wrapper`.

3. **Do not bypass `reset_core_n` in `main.vhd`.**
   Consumers should use the protected reset unless there is a documented
   reason to be in the small exception set.

4. **Do not use `hard_reset_n` as a general reset.**
   It exists for the hard-reset cartridge-exit window and for
   `cartridge.vhd` reset.

5. **Preserve the soft vs hard cartridge split.**
   Soft reset must leave CBM80 visible and must not wipe `cartridge.vhd`.
   Hard reset must hide CBM80 after cold start and reset simulated cartridge
   state to neutral.

6. **Do not echo cartridge-originated reset back into the cartridge.**
   The hardware-cart reset output uses `reset_core_int_n` for this reason.

7. **Treat R3/R4 cartridge reset as a special case.**
   Those boards cannot sense `/RESET`, so EF3 behavior depends on the
   heuristic state machine. Do not assume a real incoming reset pin exists.

8. **Remember that short physical reset is not the same as QNICE menu reset.**
   Short physical reset resets HyperRAM/SDRAM/ascal-domain state; QNICE menu
   reset intentionally does not.

9. **If adding reset behavior to firmware, preserve CSR bits with masks.**
   A write to `$FFE0` replaces the whole CSR. Use the existing OR/AND masks
   unless a full CSR replacement is intended.

10. **If reset affects SD-card or vdrive behavior, account for dirty cache.**
    Standard C64 reset must remain protected against pending disk-image
    writeback.

## Source Map

Primary reset files:

* `M2M/vhdl/reset_manager.vhd`: physical button debounce, short vs long
  reset, 1.5 s trigger, 50 ms hold after release.
* `M2M/vhdl/clk_m2m.vhd`: QNICE, HyperRAM, SDRAM, audio reset generation.
* `M2M/vhdl/framework.vhd`: reset manager instantiation and CDCs for reset,
  QNICE CSR, menu state, and pause.
* `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd`: board-specific reset routing,
  cartridge reset line wiring, QNICE reset rail mapping.
* `M2M/vhdl/QNICE/qnice.vhd`: CSR default `x"0839"`, CSR bit exports,
  OSM/control register reset.
* `M2M/rom/sysdef.asm`: CSR bit definitions and masks.
* `M2M/rom/shell.asm`: startup sequence, SD wait setup, reset release flow.
* `M2M/rom/options.asm`: menu initialization, config loading, OSM behavior.
* `M2M/rom/gencfg.asm`: reset/pause startup policy and `RP_SYSTEM_START`.
* `CORE/m2m-rom/m2m-rom.asm`: C64-specific `RESET_CORE`, OSM pre/post
  callbacks.
* `CORE/vhdl/mega65.vhd`: reset inputs into `main.vhd`, PRG loader and CRT
  wrapper reset routing.
* `CORE/vhdl/main.vhd`: C64 reset semantics, dirty-cache protection, CBM80
  mask, cartridge reset handling, consumers.
* `CORE/vhdl/sw_cartridge_wrapper.vhd`: post-CRT-parse reset and bank-cache
  ready hold.
* `CORE/vhdl/prg_loader.vhd`: PRG load reset/wait/run sequence.
* `CORE/vhdl/cartridge_heuristics.vhd`: EF3 reset workaround for boards that
  cannot sense cartridge `/RESET`.
* `M2M/vhdl/vdrives.vhd`: virtual-drive reset and dirty-cache state.
