# Drive LED benches: error blink of the 1581 (issue #257)

A real 1581 has two LEDs: the activity LED and the power LED. Its DOS reports an error by blinking the power LED; the MEGA65 has one drive LED, which used to show only the activity of the drives, so an error of a 1581 (a disk image or the internal drive) was invisible. Now the drive LED also lights in the lit phases of the error blink of a 1581: after a failed command the LED of the idle drive flashes five times per second until the next command clears the error, like the LED of a 1541 does.

What the DOS does (genuine ROM 318045-02, measured with `doc/dev-fdd/rom_emu`): while an error is pending, and while it retries a failing job, it toggles the power LED (CIA PA5) every 100.0 ms (`$CE11`: every tenth 10 ms tick). When the error is cleared it only stops toggling and leaves the LED wherever the last toggle put it, lit or dark. So the level of the line means nothing; only the toggling does.

* `CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv` passes the power LEDs of the 1581 engines on as `pwr_led` (one bit per drive).
* `CORE/vhdl/c1581_error_led.vhd` detects the blinking of one power LED: from the third toggle of a row in which each toggle follows the one before within 200 ms, until no toggle arrived for 200 ms. Its output is the power LED while it blinks, and off otherwise. One or two edges are not a blink (the reset of a drive forces its LED off and releases it again).
* `CORE/vhdl/main.vhd` lights the drive LED for the activity of a drive or for the error blink of a 1581. The error blink is not part of the "image drive is busy" word that the Shell consults before it lets the user change the mode of a drive: a drive that only reports an error is idle.

## How to run

```
CORE/vhdl/test/tb_drive_led/run.sh [detect|wiring|all] [--keep]
```

* `detect`: the detector (below), plus six mutants that must fail: a blink after two toggles, a blink only after four toggles, the output not following the LED, a window that never ends, a window that is not restarted by a toggle, and the inverted phase.
* `wiring`, four parts:
  * The three assignments `drive_led_col_o`, `drive_led_o` and `img_drive_busy` of `main.vhd`, copied verbatim into `tb_drive_led_wiring.vhd`, checked for all 256 combinations of two drives (activity, error blink, dirty cache, internal drive), plus three mutants that must fail: no error blink in the LED, exclusive or instead of or, and the error blink in the busy word.
  * The generate block `drive_err_led_gen` of `main.vhd`, copied verbatim into `tb_drive_led_inst.vhd` (below), plus four mutants that must fail: every detector watching drive 8, a detector watching the activity LED, a detector on another clock, and a window of a tenth of the length.
  * The port map of `iec_drive` in `main.vhd` associates `led` with `c64_drive_led` and `pwr_led` with `c64_drive_pwr_led` (a check of the text: `iec_drive.sv` is SystemVerilog and out of the reach of GHDL), plus one mutant: `pwr_led` left open.
  * The differential GHDL analysis of the complete `main.vhd` against the base commit `f9f3ca1` (`WIP-V6-A22X3`) with the real `c1581_error_led` in the library, which must not show a single new diagnostic, and one mutant that must be caught: a wrong formal in the port map of `c1581_error_led`.
* `all` (default): everything.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime one to two minutes (the instance bench simulates 1.5 s at 32.79 MHz).

What no simulation here can show is that the bit of `pwr_led` really follows CIA PA5 of the right drive inside the SystemVerilog hierarchy (`c1581_drv.sv`, `c1581_multi.sv`, `iec_drive.sv`): that is three one-line assignments to read, and the hardware test of `tests/README.md` (an error on drive 8, on drive 9, on the internal drive).

## Detector (`tb_c1581_error_led.vhd`)

The window is scaled to 200 clock cycles, the half period of the blink is 100 cycles (the real ratio). Checks: a steady LED, lit or dark, is no blink; one edge (the reset of the drive released) is no blink; the third toggle of an error starts the blink, whether it turns the LED dark (an error after a lit LED) or lit (an error after the DOS left the LED dark), and from then on the output shows the LED, lit and dark phases, without a gap; when the toggling stops with the LED dark, the output stays off, also for a single later edge; when it stops with the LED lit, the output stays lit until the window ends and is off afterwards although the LED stays lit; a short reset pulse (two edges) is no blink; slow changes are no blink; a row that was interrupted for longer than the window starts anew.

## Detector instances (`tb_drive_led_inst.vhd`)

The bench runs the generate block of `main.vhd` as it is: the real detector with its default window, on the core clock, one instance per drive. It runs in real time at the fastest core clock (NTSC flicker-free, 32.79 MHz), where the window of 6,400,000 cycles is shortest (195 ms; 204 ms at the slowest clock). For drive 8 and then for drive 9 the power LED toggles six times, 100 ms apart, as the DOS does it, while the activity LED of the same drive changes too. Checks: the blink of a drive appears in its own bit and never in the bit of the other drive; lit and dark phases are shown; after the last toggle (LED left lit) the output is still lit 150 ms later and off 250 ms later. The bench declares only the signals that the block may use, so a block that takes another clock or source does not analyze.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, runs, mutants, differential analysis |
| `tb_c1581_error_led.vhd` | Bench of the blink detector |
| `tb_drive_led_wiring.vhd.in` | Template of the bench of the LED equations; `run.sh` copies the assignments out of `main.vhd` into it |
| `tb_drive_led_inst.vhd.in` | Template of the bench of the detector instances; `run.sh` copies the generate block out of `main.vhd` into it |
