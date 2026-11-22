# Issue #266: the mouse settings and "Flip joystick ports"

GitHub issue [#266](https://github.com/MJoergen/C64MEGA65/issues/266) (2026-11-22, on WIP-V6-A26 or A27): Amiga mouse in port 1, joystick in port 2, `Mouse` > `Port 1: Amiga`, then `Flip joystick ports`. Reported: the joystick, now C64 port 1, "does not work because it is in Amiga mouse mode" and its fire buttons 2 and 3 read as pressed; the mouse, now C64 port 2, "disturbs" that port. Expected: "Flip joysticks also flips the mouse settings".

## Result: no defect

The core already behaves as the report expects. `Port 1` and `Port 2` in the submenus `Mouse` and `Paddles` are the two sockets of the MEGA65 (`SPEC.md` section 1, decision D1 of `STATUS.md`). Every setting is applied to its socket in front of the port switcher, and `Flip joystick ports` then moves the processed device, its five lines and its two paddle values, to the other C64 port. The setting therefore stays with the device:

* `Mouse` (`C64` / `Amiga`) and the switch `MEGA+left = right`: `M2M/vhdl/debouncer.vhd`, the lines of each socket are replaced by its own setting (`s1_*`, `s2_*`) before `handle_outputs` switches them; each `amiga_mouse` instance reads the raw pins of its own socket, is enabled by the bit of its own socket, gets the measured values of its own socket (`meas_x`, `meas_y`) and delivers its position to the C64 port of that socket (`handle_paddles`).
* `Paddles` (`C64` / `Atari CX30`): applied per socket inside `mouse_input.vhdl` (`atari_paddles_a`, `atari_paddles_b` in `qnice_wrapper.vhd`), before `correct_and_flip_paddles` switches the four values.
* Menu bits: 53 (`Flip joystick ports`), 309, 310, 313, 314 (`Mouse`), 321, 324 (`Paddles`); the flip is in bank 3 of `M2M$CFM_DATA`, the others in banks 19 and 20. Neither the menu nor the keyboard shortcut `Flip joysticks` (`_SCK_FLIP` in `CORE/m2m-rom/shortcuts_c64.asm`) touches any bit but 53, and no callback of the Shell reads or writes the mouse or paddle groups. `menu_test.py verify` passes on `ecfd5f3`.
* The C64 side: C64 port 1 is CIA 1 port B (`$DC01`), C64 port 2 is port A (`$DC00`) (`keyboard.vhd`); the SID reads the paddles of port 1 while bit 6 of `$DC00` is set, those of port 2 while bit 7 is set, and the AND of both while both are set (`fpga64_sid_iec.vhd`, `pot_x1` to `pot_y2`).
* `debouncer.vhd`, `amiga_mouse.vhd`, `mouse_input.vhdl`, `qnice_wrapper.vhd`, `shortcuts_c64.asm` and `tools.asm` are identical in A26, A27 and `ecfd5f3`.

## What produces the reported symptoms

All three symptoms appear together in exactly one state: the setting `Amiga` on the socket that holds the joystick, here `Port 2: Amiga` with the joystick in port 2 (variant 4 of the bench). With `Flip joystick ports` on:

| C64 port | Device | What the C64 sees | Reported as |
|---|---|---|---|
| 1 | joystick, its socket set to `Amiga` | only fire passes, the directions are gone; POT X and Y are 64 (the position of an Amiga mouse that never moves) | "does not work because it is in Amiga mouse mode", "fire buttons 2 and 3 constantly pressed" (a pressed fire 2 or 3 reads low, see `c64.sv` around line 986) |
| 2 | Amiga mouse, its socket set to `C64` | the quadrature of the mouse on the direction lines | "disturbing the Commodore mode there" |

That is the state a user reaches who selects `Port 2: Amiga` after the flip because the menu line reads like "C64 port 2". The labels do not say that they mean the sockets of the MEGA65; only the FAQ, `tests/README.md` and the README of the input monitor do.

With the correct setting a part of the report can also be seen: a program that reads C64 port 2 (most games) gets the mouse after the flip, as a 1351 without direction lines and with POT values from 64 to 190, so a program that knows three fire buttons shows fire 2 and 3 as pressed, and the joystick seems dead because it is on port 1 now. A program that reads the POT registers without selecting a port reads port 1 (the KERNAL leaves `$DC00` at `$7F`) or, with both bits set, the AND of both ports.

## The bench

`tb_issue266.vhd` connects the real `mouse_input.vhdl` (50 MHz) with a model of the paddle pins, the process `correct_and_flip_paddles` of `qnice_wrapper.vhd` (verbatim), `cdc_stable.vhd`, a model of `xpm_cdc_array_single` for the flip bit and the settings, the real `debouncer.vhd` with its two `amiga_mouse.vhd` and ten `debounce.vhd` (31,527,778 Hz), the real `keyboard.vhd` and the paddle selection of `fpga64_sid_iec.vhd` (verbatim). It reads both ports as `tests/input-devices/inputmon.prg` does (the five lines, POT X and Y for port 1, port 2, both and none selected) and checks every value against the expected one; a monitor in every core clock cycle fails the run if a movement of the mouse reaches a direction line or a button changes where none may change, also while the flip changes during a movement.

| Variant | Setup | Flip off, on, off, toggled while the mouse moves | Checks |
|---|---|---|---|
| 1 | Amiga tank mouse in socket 1 (pins 5 and 9 open), `Port 1: Amiga`; joystick in socket 2 | the mouse is a 1351 on the C64 port of socket 1, the joystick works on the other one; the position is kept across the flip | 148 |
| 2 | as 1, but the mouse holds pins 5 and 9 high (active pot lines): right and middle button, and `#1: MEGA+left = right` | the three buttons and the right click with the MEGA key follow the mouse | 238 |
| 3 | Commodore paddles in socket 1, Atari CX30 paddles in socket 2, `Paddles` > `Port 2: Atari CX30` | the halved count follows socket 2; on the wrong socket the CX30 paddles read 255 and the Commodore paddles half their values | 16 |
| 4 | as 1, but `Port 2: Amiga` (the socket with the joystick) | the reported symptoms, see above | 50 |

```
doc/dev-input/issue266/run.sh            # variants 1 to 4, four processes, about 45 s with nvc
doc/dev-input/issue266/run.sh 2          # one variant
doc/dev-input/issue266/run.sh control    # variant 1 against a debouncer whose setting follows the C64 port: must FAIL
```

The script copies the sources of this checkout into a temporary folder and checks the two verbatim blocks against the sources first. `control` changes every use of `amiga_i` in the architecture of `debouncer.vhd` into the setting of the C64 port; variant 1 then fails with 315,341 failed checks, so the bench tells the two behaviors apart.

One detail without consequence: in the core clock cycle after the flip bit arrives, a C64 port that receives a socket in the setting `C64` still shows the measured values of the other socket, because `cdc_stable` delivers the switched values one cycle later (32 ns).

## Open

* Questions for the reporter: was the `Mouse` submenu changed after the flip (a photo of it with the flip on helps); which program showed the symptoms; the screen of `inputmon.prg` with the flip off and on; the exact build.
* If the labels are to say what they mean: renaming `Port 1:` and `Port 2:` of the eight items of `Mouse` and `Paddles` (for example `Socket 1: Atari CX30`, the longest, 21 characters with the leading space; the menu is 25 wide) moves no menu bit, but adds two characters per line to `OPTM_ITEMS` and 16 words to the peak of the menu heap (217 words of headroom on `ecfd5f3`, `menu_test.py verify` asks for at least 180) and changes the texts of the FAQ, of `tests/README.md` and of the documentation issues #39 and #40 of `Kugelblitz360/C64MEGA65DOCS`. An additional text line would move every later menu bit and cost stack words in the deepest menu chain.
