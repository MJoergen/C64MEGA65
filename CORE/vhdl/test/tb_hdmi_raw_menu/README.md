# HDMI Frame Sync decoders (issue #184)

The submenu `HDMI: %s` has two radio groups `HDMI Frame Sync`, one per machine mode: `Off`, `Flicker-free` (default) and `Raw 50.1 Hz` (PAL) or `Raw 59.8 Hz` (NTSC); `doc/dev-hdmi-raw/SPEC.md`, sections 1 and 3. `CORE/vhdl/mega65.vhd` decodes them in two places:

* `main_hdmi_ff` (main clock domain): the item `Flicker-free` of the active machine mode and not its item `Raw`. It is the switch of `hr_core_speed`, so only `Flicker-free` moves the core to the flicker-free clock.
* `qnice_video_mode_o` (QNICE clock domain): while the item `Raw` of the active machine mode is selected, the raw member of the selected display mode (`C_VIDEO_HDMI_*_RAW` of `M2M/vhdl/av_pipeline/video_modes_pkg.vhd`); otherwise the standard member, chosen by the same chain as before.

`Off` is "neither `Flicker-free` nor `Raw`"; its two constants `C_MENU_HDMI_SYNC_OFF` and `C_MENU_HDMI_SYNC_OFF_NTSC` are not decoded. The Shell writes the menu bits one bank at a time, so two items of a group can be set for a moment; then `Raw` wins in both decoders.

## How to run

```
CORE/vhdl/test/tb_hdmi_raw_menu/run.sh [table|mutants|all] [--keep]
```

* `table`: the runner copies the constants `C_MENU_MACHINE_NTSC` and `C_MENU_HDMI_*` and the assignments to `c64_ntsc`, `main_hdmi_ff` and `qnice_video_mode_o` verbatim out of `mega65.vhd` of the working tree and of the base commit `8a0e3ab` (the menu of `WIP-V6-A26`, with the single-select switch `HDMI: Flicker-free` per machine mode) into two blocks of `tb_hdmi_raw_menu.vhd.in`. A lint refuses a second assignment to any of the three targets. The bench addresses the menu vector of the working tree with the flat indices of the golden model `M2M/rom/tests/menu_test.py`, not with the constants of `mega65.vhd`, so a constant that points to another line fails. It applies every combination of the 13 menu bits involved (machine mode, six display modes, six Frame Sync items), with all other bits of the 512-bit menu vectors at `'0'` and at `'1'`, and checks: without a Raw bit, both outputs equal those of the base commit, with the item `Flicker-free` in the place of the old switch (4096 combinations); with the Raw bit of the active machine mode, `qnice_video_mode_o` is the raw member of the mode that the base commit selects and `main_hdmi_ff` is `'0'` (8192); with only the Raw bit of the other machine mode, both outputs equal those of the base commit (4096). In addition, for every combination, both outputs against a model that does not use the base commit, and `video_mode_is_ntsc` of the mode against the machine mode.
* `mutants`: eight defects that the table must reject: `Raw` does not keep the PAL core on the original clock; the NTSC switch reads the Raw bit of PAL; the NTSC raw modes read the Raw bit of PAL; the PAL raw 16:9 mode also in NTSC; 4:3 raw delivers the 5:4 raw mode; `C_MENU_HDMI_RAW` on the line of `Flicker-free`; `C_MENU_HDMI_RAW_NTSC` on the line of `Off`; the raw lines behind the standard chain, where they are never reached.
* `all` (default): both.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 20 seconds. `VIDEO_MODES_PKG` can name another file of the package `video_modes_pkg` than the one of the working tree.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: extraction, build, run, mutants |
| `tb_hdmi_raw_menu.vhd.in` | Template of the bench; `run.sh` copies the decoders of both revisions into it |
