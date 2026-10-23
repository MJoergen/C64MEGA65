# Clock and Reset in MiSTer2MEGA65

The M2M framework uses a number of different clock domains, and associated reset signals:

Source | Clock Name  | Reset Name  | Use
------ | ----------  | ----------  | -----
M2M    | `qnice_clk` | `qnice_rst` | OSM (QNICE)
M2M    | `audio_clk` | `audio_rst` | Audio
M2M    | `hr_clk_x1` | `hr_rst`    | HyperRAM
M2M    | `hdmi_clk`  | `hdmi_rst`  | HDMI
CORE   | `core_clk`  | `core_rst`  | Core (The main clock for the core)
CORE   | `video_clk` | `video_rst` | Video (Optional, otherwise same as Core)

Each clock domains associated reset signal is automatically asserted upon power-on, and
de-asserted when the corresponding clock signal (from the MMCM) is stable.

## Reset handling

The MEGA65 has an external reset button on the left of the case. This is used to control
the assertion of the reset signals after power-on.

Two modes of operation are supported by the framework:
* Core Reset (short press): only `core_rst` is asserted.
* Full Reset (long press): complete system, i.e. all resets are asserted.

## Specific complication with the HyperRAM
The interface between the FPGA and the HyperRAM device is stateful, meaning that if either
end is reset, the other end must be reset too. Furthermore, the interface from the HDMI
ascal'er to the HyperRAM is stateful too. Finally, the Core is using the HyperRAM
interface too.  This all implies the need for a very strict reset handling, where either
none or all are reset simultaneously. This applies specifically to the three reset signals
`hr_rst`, `hdmi_rst`, and `core_rst`.


## The core clock of the C64 core

In C64MEGA65 the core clock `core_clk` (`main_clk` in `CORE/vhdl/mega65.vhd` and in `CORE/CORE.xdc`)
comes from `CORE/vhdl/clk.vhd`. Four MMCMs run permanently, one per machine standard and speed:

`core_speed_i` | MMCM                | Clock          | C64 frame rate | Used for
-------------- | ------------------- | -------------- | -------------- | -----
`00`           | `i_clk_c64_orig`    | 31.527778 MHz  | 50.124291 Hz   | PAL, original speed
`01`           | `i_clk_c64_slow`    | 31.448993 MHz  | 49.999035 Hz   | PAL, HDMI flicker-free
`10`           | `i_clk_c64_ntsc`    | 32.727273 MHz  | 59.826105 Hz   | NTSC, original speed
`11`           | `i_clk_c64_ntsc_ff` | 32.789700 MHz  | 59.940223 Hz   | NTSC, HDMI flicker-free

A two-level tree of glitch-free clock multiplexers (`BUFGCTRL`) selects one of them: bit 0 of
`core_speed_i` chooses between the original and the flicker-free clock of a standard, bit 1
chooses the standard. Because all four MMCMs keep running, every switch is a switch between two
running clocks, which is what a `BUFGCTRL` needs to switch without a glitch. `core_speed_i` is
driven by the `hr_core_speed` process in `mega65.vhd` from the OSM machine mode and from the
`hr_low_i` / `hr_high_i` feedback of the HDMI flicker-free logic. The core reset `main_rst_o`
is released when all four MMCMs have locked; no MMCM is ever reset or reprogrammed afterwards.

The static timing analysis times the core once, at its fastest clock (NTSC flicker-free,
30.497 ns), see `CORE/CORE.xdc` and `CORE/signoff_gates.tcl`.

## Mode-change reset (PAL / NTSC)

Switching the machine mode (OSM `Model > PAL / NTSC`) changes the VIC-II, the core clock and the
HDMI mode at once. The C64 KERNAL decides between PAL and NTSC only once, during its reset
routine (`$02A6`), so `CORE/vhdl/main.vhd` soft-resets the C64 after every change of the
machine mode:

* `mode_change_reset_proc` detects every change of `c64_ntsc_i` and produces one `mode_reset`
  pulse of 1024 core clock cycles. That is longer than the 32-cycle minimum of the core's
  reset rules and covers the clock switch in `clk.vhd`, which takes well below 1 us.
* `mode_reset` behaves like a short press of the reset button: it pulls `reset_core_n` low
  (soft reset, so cartridges start again), re-initializes the simulated cartridge
  (`cart_soft_reset_o`) and resets the simulated drives; drives whose "Unmount on reset"
  setting is on (the default) unmount their disk image. It never asserts the hard reset.
* While a virtual drive still writes its cache back to the SD card (`prevent_reset = '1'`),
  ordinary soft resets are ignored. The mode-change reset is deferred instead and happens as
  soon as the write-back has finished; several changes inside that window lead to one reset.
* At power-on the Shell restores the config file while the C64 is still held in reset (the
  reset bit of `M2M$CSR` is set from `CSR_DEFAULT` until `RP_SYSTEM_START` clears it). If the
  file contains NTSC, the core therefore starts directly in NTSC; there is no visible PAL phase.
  The restore is still a change of `c64_ntsc_i` and produces a mode-change reset, which falls
  inside the held reset and is harmless.

The `RESET SEMANTICS` comment block in `main.vhd` is the authoritative description of all
reset sources of the C64 core.
