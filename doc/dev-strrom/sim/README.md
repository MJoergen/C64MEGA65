# Tools of the full-system simulation

These are the tools of the one-off comparison "firmware before the string ROM against firmware after" that `../STATUS.md` reports in sections 3.4 and 3.8: the real firmware ROMs run on a simulated QNICE system and everything they output is compared. They are kept as a starting point for future simulations of the complete Shell; they are not a regression test (the permanent tests are in `M2M/rom/tests/`).

What is real and what is a model: `tb/qsys_tb.vhd` instantiates the unmodified `M2M/vhdl/qnice_wrapper.vhd` (QNICE CPU, firmware ROM, string ROM, `config.vhd`), the video RAM of the on-screen menu wired like in `av_pipeline.vhd`, and the unmodified `sw_cartridge_csr.vhd` and `crt_parser.vhd` as the cartridge device. Models: UART peer, keyboard word, HyperRAM, the other core devices, and the SD card controller at its register interface (`tb/sdcard_model_arch.vhd`, block images in `sd/`, built by `make_sd.py` and `mkfat32.py`). `sim.py` analyzes patched copies of six project files (GHDL syntax, initial values of the register file, range guards for array indexes that are only a problem in simulation, the SD card model, and a cycle counter that runs 32 times faster to shorten the real-time waits); the constants at its top list every patch.

The scripts find their inputs relative to their own location and expect this layout outside of the repository:

```
<work>/wtA/                    copy of the repository with the QNICE toolchain built; the "after" firmware is built here
<work>/baseline/m2m-rom.rom    the "before" firmware
<work>/out/A/sim/              a copy of this folder
<work>/out/A/runs, work        created by the tools
```

Commands, from `<work>/out/A/sim` (nvc is about twice as fast as GHDL here; a long scenario takes 20 to 25 minutes):

```
python3 sim.py build --sim nvc
python3 runq.py LOG main:OLD:nvc main:NEW:nvc
python3 runq.py LOG sdcard:OLD:nvc:default:card_files sdcard:NEW:nvc:default:card_files
python3 runq.py LOG emptycard:OLD:nvc:default:card_empty emptycard:NEW:nvc:default:card_empty
python3 runq.py LOG fatal:OLD:nvc:fatal_size fatal:NEW:nvc:fatal_size strdump:NEW:nvc:fatal_size
python3 summary.py                 # compares every OLD/NEW pair
python3 negctl.py --sim nvc        # shows that the comparison can fail
```

The header comment of each script describes its options. `scenarios/*.stim` are the key press and UART scripts; `compare.py` compares two runs (UART bytes, video RAM snapshots, port registers, accesses through the 4k window, SD card commands, stack and register bank levels); `strrom_tools.py` and `covmatrix.py` report which string ROM strings a run read.
