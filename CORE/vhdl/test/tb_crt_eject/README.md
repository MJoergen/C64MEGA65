Bench: unloading a simulated cartridge (issue #153)
===================================================

Since WIP-V6-A22X3, `Space` on the `CRT:` line of the on-screen menu unloads a `.crt`. In the RTL this is one rule: when QNICE sets the CSR status of the cartridge device to "idle" (`CRTROM_CSR_ST_IDLE`), `sw_cartridge_csr.vhd` raises `req_eject`, which crosses into the HyperRAM clock domain, and `crt_parser.vhd` reports the neutral cartridge of the power-on state (id 0, EXROM and GAME `$FF`, size 0) whenever it is idle. The Shell side (`UNLOAD_CRTROM` in `CORE/m2m-rom/m2m-rom.asm`) holds the C64 in soft reset around the unload; the Shell is tested by `M2M/rom/tests/crt_unload_test.py`.

```
CORE/vhdl/test/tb_crt_eject/run.sh [--keep]
```

Runs `tb_crt_eject.vhd` with four seeds and seven mutants, ends with `RESULT: PASS` or `RESULT: FAIL ...`. Needs GHDL 5.1.1 (`/usr/local/bin/ghdl` or `$GHDL`) and python3; takes about a minute.

What the bench is
-----------------

The devices under test are the real `sw_cartridge_wrapper.vhd` (CSR, clock domain crossings, parser, bank cacher, bank cache RAMs) and the real `cartridge.vhd`, wired like `cartridge_inst` in `main.vhd` (not modelled: `prevent_reset` in `main.vhd`, which the Shell side handles and `crt_unload_test.py` tests): the hard reset into `rst_i`, the OSM soft reset (`cart_soft_reset`) into `cart_loading_i` and into the wrapper. QNICE (50 MHz), HyperRAM (100 MHz) and the C64 core (about 31.5 MHz) run on three unrelated clocks. A HyperRAM model with random wait states, latency and data gaps serves the `.crt` images that the bench builds itself (a generic 8K cartridge, an EasyFlash with two banks, a file with a broken CHIP header). `avm_fifo_stand_in.vhd` replaces `M2M/vhdl/memory/avm_fifo.vhd`, which needs the Xilinx xpm library; in the wrapper it only carries the QNICE writes of a file into the HyperRAM, and the bench writes the files into its HyperRAM model directly.

The bench drives the QNICE bus like the Shell does (status "loading", file size, status "OK", polling of the parse status; status "idle" to unload) and the C64 side like `main.vhd` and a CPU do (soft reset pulses, writes to `$DE00`/`$DE02`, reads of `$DF00`).

Cases
-----

* T0: after power-on the status is "idle" and there is no cartridge.
* T1, T2: load a generic 8K cartridge, unload it while the C64 is held in reset: neutral cartridge, the C64 sees EXROM/GAME high, no bank wait, and the unload itself does not make the wrapper reset the C64.
* T3 to T5: load an EasyFlash (Ultimax, RAM at `$DF00`), switch to bank 1 and 16K mode; the statuses "loading" and "error" keep it (as before); unload it in reset: neutral, `$DF00` no longer answered by the cartridge.
* T5b: unload while a bank cache load is in flight: the load finishes and the result is neutral.
* T6, T7: a short reset (HyperRAM reset plus soft reset) after the unload does not bring the cartridge back; unloading twice is harmless.
* T8: loading works again after an unload; a short reset still keeps a loaded cartridge (it is parsed again).
* T9: a `.crt` that ended with a parse error can be unloaded.
* T10: unloading without a reset ("Use hardware slot") neutralizes id/EXROM/GAME at once, but the EasyFlash RAM at `$DF00` stays visible until the next soft reset: this is why `UNLOAD_CRTROM` resets the C64 in "Simulate cartridge" mode.
* T11: the long reset (M2M reset) also leaves no cartridge.
* T12: Super Snapshot V5 starts with its RAM writable at ROML; after unloading it, the next cartridge sees its ROM at ROML again (`roml_we_o` is cleared).
* Every unload also checks that the C64 side sees the neutral cartridge at most 8 C64 clock cycles after the parse status reads "idle"; `RESET_CORE` keeps the reset for at least 64.

Mutants (each must fail): no clearing in the parser, the id or GAME or size not cleared, eject also on the statuses "loading"/"error", eject signal not wired through the clock domain crossing, `roml_we_o` not cleared in `cartridge.vhd`.
