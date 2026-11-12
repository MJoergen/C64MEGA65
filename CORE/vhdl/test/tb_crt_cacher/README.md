# Bank cache bench for simulated cartridges (issue #255)

Simulation benches for the BRAM bank cache of simulated cartridges (`*.crt`):

* The cacher bench runs `CORE/vhdl/crt_cacher.vhd` with the cache size that `CORE/vhdl/sw_cartridge_wrapper.vhd` ships (`C_CACHE_SIZE`, read from the file) and with the former size 3, compares every hit and miss with a reference model and checks the contents of every selected cache slot.
* The wrapper bench elaborates the real `sw_cartridge_wrapper.vhd`, whose vector widths all derive from `C_CACHE_SIZE`.

## How to run

```
CORE/vhdl/test/tb_crt_cacher/run.sh [--keep]
```

The runner builds in a temporary directory, prints one result line per simulation and ends with `RESULT: PASS` or `RESULT: FAIL ...`; the exit status is 0 only on PASS. `--keep` keeps the build directory (logs) and prints its path. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl` or `GHDL`), python3. `JOBS` (default 2) sets the number of parallel simulations. Runtime on this machine: about 4 minutes.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: reads `C_CACHE_SIZE`, builds the benches and two mutants, runs the simulations, evaluates |
| `tb_crt_cacher.vhd` | Cacher bench: DUT, HyperRAM controller, device model, BRAM model, reference model, checks |
| `tb_wrapper_elab.vhd` | Wrapper bench: the real `sw_cartridge_wrapper.vhd` with idle inputs |
| `avm_fifo_stand_in.vhd` | Stand-in for `M2M/vhdl/memory/avm_fifo.vhd`, which needs the Xilinx xpm library |

## What is simulated

### Cacher bench

The DUT is the real `crt_cacher`. Its Avalon master is connected to the real HyperRAM controller state machine (`M2M/vhdl/controllers/hyperram/hyperram_ctrl.vhd`), so every bank load consists of the same 32 bursts of 128 words with the same command, latency and recovery phases as in the core. A small model stands in for the HyperRAM device and the receive path (first word three clocks after the controller starts reading, short latency). Every word it returns is a function of its word address, which tells the bench what each cache slot must contain. The two cache BRAMs are modeled with the addressing of `sw_cartridge_wrapper.vhd` (cache slot and word address).

Not part of the bench: the arbiters between the cacher and the HyperRAM controller, the clock domain crossings of `sw_cartridge_wrapper.vhd` and the C64 core.

### Wrapper bench

The slot addresses of the cache, their clock domain crossing and the address width of the two cache BRAMs in `sw_cartridge_wrapper.vhd` all derive from `C_CACHE_SIZE`. The bench elaborates the real wrapper together with the real `crt_loader`, `crt_parser`, `crt_cacher`, `sw_cartridge_csr`, `qnice2hyperram`, `avm_arbit`, `cdc_stable`, `cdc_slow` and `tdp_ram` and runs it for 5 µs with idle inputs: a width that does not fit shows as an elaboration or bound error. Only `avm_fifo` is replaced by a stand-in without function. The simulation needs `--max-stack-alloc=0`, because `tdp_ram` builds the initial value of a cache BRAM (128k x 16) in one local variable.

## Checks

The wrapper bench passes if the wrapper elaborates and the simulation reaches its end without an error (`wrapper` in the output of the runner).

In the cacher bench, for a random sequence of bank selections (a set of frequently selected banks mixed with random others) the bench checks after every selection:

* Hit or miss: `bank_wait_o` is asserted exactly when the reference model predicts a miss. The reference model has `2**G_CACHE_SIZE` slots per cache, replaces them round-robin and starts with the bank of the cartridge's start in slot 0.
* Data: all 4096 words of the selected ROML slot and all 4096 words of the selected ROMH slot are the words of the selected bank.

| Simulation | Cache size | Bank selection | Expected |
|---|---|---|---|
| `ship_easyflash_seed1`, `ship_easyflash_seed2` | as shipped | ROML and ROMH together (EasyFlash), 64 banks, 300 selections | no errors |
| `ship_independent_seed3` | as shipped | ROML and ROMH independently, 64 banks, 300 selections | no errors |
| `ship_40banks_seed4` | as shipped | EasyFlash, 40 banks, 1500 selections (many hits) | no errors |
| `size3_easyflash_seed5`, `size3_independent_seed6` | 3 (8 slots) | as above | no errors |
| `mut_pointer` | 3 | EasyFlash; mutant: the round-robin pointer of the ROML cache never advances | errors reported |
| `mut_tag` | 3 | EasyFlash; mutant: a ROMH miss does not write its tag | errors reported |

The result lines also show the duration of a miss that loads both halves (`full_miss_clocks`, in clocks of the 100 MHz HyperRAM clock): 8962 clocks = 89.6 µs = 88 PHI2 cycles of a PAL C64 = 1.4 raster lines. The arbiters of the core add a few clocks; on R3 boards, where the HDMI scaler shares the HyperRAM, a miss takes about 100 to 115 PHI2 cycles.

## Background: why the cache holds 32 banks per half

Selecting a bank that is not in the cache asserts `bank_wait`, which stops the C64's CPU through the core's DMA input until the bank is copied from the HyperRAM. The CPU's clock enable is gated completely, so the CPU does not sample interrupts during that time, while the VIC-II keeps running. A raster interrupt that falls into a miss is therefore served late by up to the length of the miss.

"Eye of the Beholder" V1.00 (EasyFlash) made this visible (issue #255):

* It calls across banks through a trampoline in RAM that writes `$DE00` twice per call: 95 to 180 bank switches per frame, some of them from inside its interrupt handlers.
* It chains 11 raster interrupts per frame (lines 45, 49, 70, 90, 112, 133, 153, 200, 225, 248 and 256) for the sprite multiplexer, the `CAMP` button and the switch from bitmap to text mode below the 3D view. The handler at line 225 has about 17 cycles of slack before the switch becomes visible. Every handler programs the next raster line first and acknowledges the interrupt afterwards; the handler at line 45 has about 45 cycles of slack before the interrupt of line 49 is lost, and with it the rest of the chain for that frame.
* While the party stands still the game works with 8 banks. While it moves it works with 19 to 23 banks within a second and with 24 within two minutes on level 1.

Misses per frame for a recorded bank selection sequence of the game (level 1, 120 s of walking and turning, cache warm):

| Slots per half | 8 | 16 | 20 | 24 and more |
|---|---|---|---|---|
| Misses per frame | 1.03 | 0.44 | 0.09 | 0.01 (first use of a bank only) |

With 8 slots that is one CPU stop of 1.4 raster lines in about every frame; the ones that hit a raster interrupt showed as one to three lines of garbage below the bitmap area or, when the chain was lost, as a frame without message lines and `CAMP` button. 32 slots per half (`C_CACHE_SIZE = 5`) leave room for scenes that use more banks than the measured 24 and take 2 x 64 RAMB36 instead of 2 x 16.
