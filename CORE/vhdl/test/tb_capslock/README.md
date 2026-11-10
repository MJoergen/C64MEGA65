# Caps Lock turbo benches (issue #261)

Caps Lock is the turbo key: while Caps Lock is on (its LED lights up), the C64 runs in `Smart` mode at `4x`, overriding the turbo setting of the `Model` submenu; with Caps Lock off the menu setting applies. The MEGA65 keyboard toggles Caps Lock by itself and sends the state that drives the LED on a dedicated line of its serial protocol. `M2M/vhdl/m2m_keyb.vhd` passes that line on as `capslock_n_o` (filtered, independent of the keyboard gate that the Shell closes while the on-screen menu is open), through `framework.vhd` and the four `top_mega65-r*.vhd` to `main_kb_capslock_n_i` of `CORE/vhdl/mega65.vhd`, whose turbo decode applies the override. `main.vhd` is unchanged, so the turbo engine and its bench `../tb_turbo` are unaffected.

## How to run

```
CORE/vhdl/test/tb_capslock/run.sh [keyb|decode|wiring|all] [--keep]
```

* `keyb`: the keyboard chain (below), Caps Lock off and on at power-on, plus two mutants of `m2m_keyb.vhd` that must fail: `capslock_n_o` gated by the keyboard gate, and no filter.
* `decode`: the turbo decode of `mega65.vhd`, all combinations, plus two mutants that must fail: Caps Lock without clearing the `C128` bit, and without forcing `4x`.
* `wiring`: GHDL analysis and elaboration of the four board top files against the real entity declarations of `framework` and `MEGA65_Core`; differential GHDL analysis of the complete `framework.vhd` and `mega65.vhd` against the base commit `522e5fc` (`WIP-V6-A22X1`), which must not show a single new diagnostic; two mutants that must be caught: an unconnected `main_kb_capslock_n_i` and a wrong formal in the `m2m_keyb` port map.
* `all` (default): everything.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3, git. Runtime about 30 seconds.

## Keyboard chain (`tb_capslock_keyb.vhd`)

The DUT is the unmodified chain `m2m_keyb` → `mega65kbd_to_matrix` → `matrix_to_keynum` (with `kb_matrix_ram`) at the PAL core clock. A behavioral MEGA65 keyboard answers the serial scan on `kio10`: after each sync pulse it sends one bit per `kio8` clock, bit n = key n, low active, bit 72 = Caps Lock. A calibration step proves that the model is aligned with the sampling of `mega65kbd_to_matrix` (the scan must report exactly the pressed key).

Checks with Caps Lock off at power-on: `capslock_n_o` stays `'1'`; Caps Lock on makes it `'0'` 4.0 to 4.5 ms later (filter plus at most one keyboard frame); with the core decoupled from the keyboard (`enable_core_i = '0'`, menu open) `capslock_n_o` keeps following the keyboard while `key_pressed_n_o` stays `'1'` for every key; a Caps Lock bit inverted for 1 frame or for 8 frames (3.7 ms) does not move `capslock_n_o`; Caps Lock off makes it `'1'` again; with the keyboard coupled again the scan reports key 72 as before. Checks with Caps Lock already on at power-on: `capslock_n_o` goes `'0'` within 5.5 ms, and follows a later Caps Lock off.

## Files

| File | Content |
|---|---|
| `run.sh` | Runner: builds, runs, mutants, wiring and differential analysis |
| `tb_capslock_keyb.vhd` | Keyboard chain bench with the behavioral MEGA65 keyboard |
| `tb_capslock_decode.vhd.in` | Template of the decode bench; `run.sh` copies the decode out of `mega65.vhd` into it |
