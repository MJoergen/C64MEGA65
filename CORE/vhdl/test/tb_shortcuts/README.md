# Keyboard shortcuts benches (issue #142)

The keys F9 to F14 are configurable keyboard shortcuts: each one gets an action in the `Keyboard Shortcuts` submenu. F10, F12 and F14 are Shift+F9, Shift+F11 and Shift+F13 on the MEGA65 keyboard. The VHDL side of the feature:

* `M2M/vhdl/m2m_keyb.vhd` reports F9, F11, F13 and Shift (left or right) to the Shell as QNICE key bits 10, 11, 12 and 13 (`M2M$KEY_F9`, `M2M$KEY_F11`, `M2M$KEY_F13`, `M2M$KEY_SHIFT` in `sysdef.asm`). The Shell handles every action except Freeze.
* `CORE/vhdl/keyboard.vhd` handles Freeze: Shift is sampled when the physical function key goes down and decides between F9 and F10 (F11/F12, F13/F14) for the whole key press; `freeze_n` is low while a key is held whose resolved function is configured as Freeze (`sc_freeze_i`). While F9, F11 or F13 is held, the CIA does not see the physical Shift keys; the Shift that cursor up and cursor left synthesize stays visible.
* `CORE/vhdl/main.vhd` passes the freezer key to `cartridge_inst` only for simulated cartridges with a freeze button (cartridge ids 1, 3 and 20); the Restore key is unchanged.
* `CORE/vhdl/mega65.vhd` derives the six freezer key bits from the menu (`C_MENU_SC_F9` to `C_MENU_SC_F14` plus `C_SC_FREEZE`) and decodes the volume with a register that holds its value while no bit of the Volume group is set, so that a torn update of the menu bits cannot let a 100% sample through.

## How to run

```
CORE/vhdl/test/tb_shortcuts/run.sh [keyb|qnice|decode|wiring|all] [--keep]
```

* `keyb`: `tb_shortcuts_keyb.vhd` against `keyboard.vhd`, plus two mutants that must fail: Shift not latched at the key press, and left Shift not masked.
* `qnice`: `tb_shortcuts_qnice.vhd` against the keyboard chain `m2m_keyb` → `mega65kbd_to_matrix` → `matrix_to_keynum`, plus a mutant that must fail: right Shift not reported.
* `decode`: `run.sh` copies the volume decoder, the freezer key bits and their constants out of `mega65.vhd` and the cartridge gate out of `main.vhd` into `tb_shortcuts_decode.vhd.in`, then runs the bench; plus five mutants that must fail: volume falling back to 100% when no bit is set, a freezer key bit taken from the wrong picker, the cartridge gate removed, and two that only the timing check of the volume decoder can see: the volume decoder without the clock (a transparent latch) and the volume register on the falling edge.
* `wiring`: differential GHDL analysis of `main.vhd`, `mega65.vhd`, `keyboard.vhd` and `m2m_keyb.vhd` against the base commit `1470473` (`WIP-V6-A22X2`). Pass A uses identical libraries (packages, a stub of the Xilinx XPM library, the keyboard chain) for both versions. Pass B adds the entity declarations of every instantiated sub-entity (for `main` and `keyboard` from the same version), so that the port maps are checked; only the SystemVerilog `iec_drive` stays unresolved. Both passes must show identical diagnostics. Two mutants must be caught: an unconnected `sc_freeze_i` in `main.vhd` and an unconnected `kb_sc_freeze_i` in `mega65.vhd`.
* `all` (default): everything.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 1 minute.

## Benches

`tb_shortcuts_keyb.vhd` plays the M2M key scan (one key per clock cycle) and the CIA (scans the matrix in both directions). Checks: F9 as Freeze while held and released; Shift+F9 with and without F10 as Freeze; Shift pressed after F9 keeps F9, Shift released while Shift+F9 is held keeps F10; the same for F11/F12 and F13/F14 with left and right Shift; two shortcut keys at once; left and right Shift invisible to the CIA while F9, F11 or F13 is held and visible again after the release; the synthesized Shift of cursor up and cursor left visible while F9 is held; no Freeze at all when no key is configured as Freeze; a monitor counts every falling edge of `freeze_n`; the autostart still types its first key.

`tb_shortcuts_qnice.vhd` uses the behavioral MEGA65 keyboard of `../tb_capslock/tb_capslock_keyb.vhd`, extended by the dedicated late phases of Ins/Del and Return. Checks all 16 QNICE key bits after every step: F9, F11, F13 alone and together; left, right and both Shift keys; Shift with each function key; Return, F1 and F3 unchanged; the same while the core is decoupled from the keyboard; bits 14 and 15 stay `'1'` in every clock cycle.

`tb_shortcuts_decode.vhd.in`: power-up at 100%; all 21 volume items; all 420 transitions between two items, torn both ways (no bit set first: the old value is held; both bits set first: the lower volume wins), with a monitor that allows only the old or the new value in every clock cycle; all of it with the other menu bits at `'0'` and at `'1'`; a timing check that pins the volume decoder to exactly one register on the rising edge of `main_clk_o` (the other checks change the selection on the falling edge and sample on the next falling edge, so they cannot tell a latch or a register on the falling edge from it): the selection changes 1 ns after a rising edge, `main_volume` is sampled every 1 ns and must keep the old value up to 1 ns before the next rising edge (so also 1 ns after the change and 1 ns after the falling edge in between) and have the new value 1 ns after that rising edge, for the step from the power-up state to the first item ever selected (50%) and for all 420 transitions with the other menu bits at `'0'` and at `'1'`; all 66 picker and item combinations of the freezer key bits; the cartridge gate for the cartridge ids 0 to 300 and `0xFFFF` with all combinations of Restore and the freezer key.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, runs, mutants, differential analysis |
| `tb_shortcuts_keyb.vhd` | Bench of `keyboard.vhd` |
| `tb_shortcuts_qnice.vhd` | Bench of the QNICE key bits of `m2m_keyb.vhd` |
| `tb_shortcuts_decode.vhd.in` | Template of the decode bench; `run.sh` copies the code out of `mega65.vhd` and `main.vhd` into it |
