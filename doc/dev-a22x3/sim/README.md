# Full-system simulation of the merged firmware

The real firmware runs on a simulated QNICE system, with scripted key presses, and everything it does is logged. This is the tool set of `doc/dev-strrom/sim/`, adapted to the firmware of `WIP-V6-A22X3`; `doc/dev-a22x3/STATUS.md`, section 6, has the results. It is a starting point for future simulations of the complete Shell, not a regression test (the permanent tests are in `M2M/rom/tests/`).

What is real and what is a model: `tb/qsys_tb.vhd` instantiates the unmodified `M2M/vhdl/qnice_wrapper.vhd` (QNICE CPU, firmware ROM, string ROM, `config.vhd`), the video RAM of the on-screen menu, and the unmodified `sw_cartridge_csr.vhd` and `crt_parser.vhd` as the cartridge device. Models: UART peer, keyboard word, HyperRAM, the virtual drives and the other core devices (a page store), the PRG loader (its parse status is always "ready"), and the SD card controller at its register interface (`tb/sdcard_model_arch.vhd`, block images in `sd/`). The cycle counter of QNICE runs 32 times faster (a 1 s wait of the firmware takes 31 ms of simulated time); busy loops and byte loops are not compressed, so a boot takes about 0.6 s and the load of a D64 about 1.6 s of simulated time.

Differences to the tool set of the string ROM:

* The menu state `control_m` is 512 bits wide, and `qnice_req_eject_o` of `sw_cartridge_csr.vhd` is wired to `req_eject_i` of `crt_parser.vhd`.
* The keyboard word knows the shortcut keys: F9, F11, F13 and Shift (bits 10 to 13, low active).
* The CPU spy records the program counter at every new peak of the stack and of the register bank level (`spy_peaks.log`, with stack dumps from a shadow copy of the RAM); the scenario command `memdump <tag> <address> <n>` writes RAM words to `memdump.log`.
* `crt.log` has the outputs of the cartridge parser and every access to its CSR window; `sdwrites.log` has the data of every block that is written to the SD card.
* `sim.py` has two more patch sets: `--cfg bank32` (32 register banks, unguarded: the simulator stops when the level reaches 32) and `--cfg bank32mod` (32 banks, index modulo 32, which is how the hardware behaves).

The scripts find their inputs relative to their own location and expect this layout outside of the repository:

```
<work>/wtA/                    copy of the repository with the QNICE toolchain built and the firmware built
<work>/out/A/sim/              a copy of this folder
<work>/out/A/runs, work        created by the tools
```

Commands, from `<work>/out/A/sim` (nvc 1.21; a boot takes about 14 minutes, a scenario with one disk image load about an hour):

```
python3 make_sd2.py                 # sd/card_full.blk: three D64 in one folder, a PRG, a valid and a too large CRT
python3 make_sd2.py --bad           # sd/card_bad.blk: the same plus BAD.D64 (wrong size)
python3 sim.py build --sim nvc
python3 sim.py run r4 NEW --sim nvc --sd sd/card_full.blk
python3 sim.py run rf NEW --sim nvc --sd sd/card_full.blk --cfg bank32 --tag bank32
python3 runtext.py uart|bits|cfg|peaks ...     # read the logs of a run; the header of each script has its options
```

Scenarios (`scenarios/*.stim`):

| Script | Content |
|---|---|
| `r1` | boot, Volume down and up, Mount drive 8 up to the file browser |
| `r2` | walk through the menu into the Keyboard Shortcuts submenu, change an assignment, close; load a CRT and unload it with Space |
| `r3a`, `r3b`, `r3c` | Next disk; Volume with the deferred save, Load PRG, Load CRT |
| `r4` | Mount drive 8 with a shortcut, including the load of the disk image |
| `rf`, `rf2` | the shortcut scenario for the runs with 32 register banks |
| `m1` | like `r4`, for the comparison of the SD commands before and after the fix of the mount code |
| `m2` | a rejected disk image over a mounted one, then Run/Stop; a rejected CRT over a loaded one |
| `m3` | a rejected disk image, then an accepted one |

Three things to know when writing a scenario: `press_until` releases the key at the first video RAM write of a redraw that may still be running, so keys get lost (use `press <key> 3` followed by `wait_quiet 20000`, and `wait_osm` after the first Help); `wait_uart` misses text that is sent while a key is held; and the cursor of the file browser starts on `<..>`, so a Down is needed before Return.
