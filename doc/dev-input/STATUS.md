# Input devices (issues #190 and #193): status and running memory

Amiga mouse and Atari CX30 paddles, selectable per port in the on-screen menu. `SPEC.md` is the design, `RESEARCH-amiga-mouse.md` and `RESEARCH-paddles.md` are the facts behind it. This file records the state of the work, the decisions, the verification and what is open.

## 0. State

* Branch `mh_implement_190_193`, branched from `develop` at `6845596` (WIP-V6-A25). The version of this work is WIP-V6-A26. Not merged into `develop`.
* Nothing of this has run on hardware. No Vivado build has been made from the branch.

| Part | State |
|---|---|
| Research (both issues, all links of the issues, board schematics, MEGA65 core sources) | done |
| Specification | done |
| Menu, menu bits, ports of `MEGA65_Core`, firmware budgets | done (section 4), independent review in work |
| `amiga_mouse.vhd`, `debouncer.vhd`, bench `tb_amiga_mouse` | in work |
| Atari mode of `mouse_input.vhdl`, bench `tb_paddles` | in work |
| Wiring (`qnice_wrapper.vhd`, `framework.vhd`, four board files, four `.xpr`), `cdc_stable` for the paddle values | open |
| Independent reviews, full run of all suites, stack margin of the larger menu in the full-system simulation | open |
| Version bump, `tests/README.md`, `VERSIONS.md`, `FAQ.md`, `ROADMAP.md`, `AGENTS.md`, `doc/inofficial.md` | open |

## 1. Decisions

| # | Decision | Why |
|---|---|---|
| D1 | "Port 1" and "Port 2" in the two submenus are the sockets of the MEGA65; the setting travels with "Flip joystick ports". | The setting describes the device that is plugged in. |
| D2 | The user selects the device; nothing is detected automatically. | The autodetection of the MEGA65 core has false positives and lets quadrature through to the keyboard before it has decided (mega65-core issues #963, #779, #549). |
| D3 | A new decoder (`amiga_mouse.vhd`) on the raw pins in the core clock domain; the Amiga part of the MEGA65 module `mouse_input.vhdl` stays switched off. | The debouncer swallows the quadrature (the experiment of 2022 on branch `dev-amigamouse` ran through a 5 ms filter, which explains its result); decoding in the core clock domain needs no crossing of a multi-bit position. |
| D4 | The mouse is presented as a 1351: POT value = 64 + position with bit 0 clear; two counts of the mouse are one position unit of a 1351 driver. | Format of a real 1351; scale of the MEGA65 core and of VICE, so the same mouse feels the same in both cores. An exported bit 0 would make the drivers lose half a unit at every call with an odd difference. |
| D5 | Rate limiter: one step per 400 µs, backlog of 127 counts. | A 1351 driver takes more than 63 steps between two calls as a movement in the other direction; fast optical mice would reach that at 8 cm/s. |
| D6 | Right and middle button only for a mouse or adapter that holds pins 9 and 5 high while the buttons are released, found out by observation (a value below 128 has been seen); a button that is pressed for 30 s is released. No key of the keyboard as a substitute. | The board cannot tell an open pin from a grounded one. The release covers the exchange of such a device for one that only grounds the lines. The Amiga core for the MEGA65 (AExp) uses the same mechanism in the field. A substitute key is essential on an Amiga; C64 programs rarely use the right button. |
| D7 | The direction lines of a port in Amiga mode are hidden from the C64. | On port 1 they are in parallel with the keyboard matrix. |
| D8 | Atari paddles: the count of a longer window, halved (factor 2, window of 510 ticks, cycle of 769 ticks). The cycle is only long while a port is set to Atari, and a port in C64 mode is always counted in the same 255 ticks. | A ratio is independent of the board. A 1 MOhm paddle then reads like a 500 kOhm one. With all settings at "C64" the measurement is bit-identical to before, and a 1351 on a port in C64 mode always sees its window. |
| D9 | The four paddle values cross into the core clock domain through `cdc_stable` instead of per-bit synchronizers. | Found during the analysis: a read of the SID register in the clock cycle of a change could return a value that was never measured (a 1351 jumps by up to 32 units). |
| D12 | The four comparator inputs of the paddle measurement get a two-stage synchronizer. | Found during the work on the Atari mode: they went straight from the pins into the count enables of multi-bit counters. The measurement moves by 40 ns, far less than one count of 1 µs. |
| D10 | Menu: section "Input Devices" in "Advanced Settings" with the submenus "Keyboard Shortcuts", "Mouse" and "Paddles"; the two new submenus have a headline, the two items of port 1, a line, the two items of port 2, a line and "Back"; no `%s` summary on the openers. | Layout asked for by the owner; the line between the ports is an addition. |
| D11 | The 1 ms debouncer stays as it is for the setting "C64". | A 1351 only sends its buttons over the debounced lines; the devices that the filter breaks (section 6 of `RESEARCH-amiga-mouse.md`) also need the core to drive the port lines, which it does not do. |

## 2. Questions to the owner

Asked on 2026-11-14, answered on 2026-11-15.

1. Are the ports of the submenus the sockets of the MEGA65 (D1)? Yes.
2. Does the right button of an Amiga mouse work with the MEGA65 core? No; the documentation of the Amiga core (AExp) has the workarounds (section 7 of `RESEARCH-amiga-mouse.md`).
3. Menu details (D10)? Yes, as described.
4. End state: the branch is pushed, not merged? Yes.

## 3. Numbers

| | Before (WIP-V6-A25) | Now |
|---|---|---|
| Menu lines (`OPTM_SIZE`) | 301 | 323 |
| Submenus | 18 | 20 |
| Characters of `OPTM_ITEMS` (a line end counts as 2; limit 4094) | 3,192 | 3,402 |
| `OPTM_DY` | 29 | 29 (the main menu is still the largest view; "Advanced Settings" has 20 lines) |
| Menu heap: structure + slots = peak, of `MENU_HEAP_SIZE` | 4,418 + 648 = 5,066 of 5,248 | 4,716 + 702 = 5,418 of 5,632 (214 words free) |
| `HEAP_SIZE` of the file browser (release / debug build) | 24,960 / 1,920 | 24,576 / 1,536 |
| Firmware ROM, string ROM | 20,284 words, 9,071 characters in 198 strings | unchanged (21 words differ: the immediate values of the two heap sizes and the six entries of the shortcut picker table) |
| Stack words that `OPTM_SHOW` and `OPTM_RUN` reserve | 302 and 304 | 324 and 326 |

Menu indices: the headline "Input Devices" is line 194, the Keyboard Shortcuts submenu 196 to 296 (two lines later than before: `C_MENU_SC_F9` to `C_MENU_SC_F14` are 202, 218, 234, 250, 266, 282), the Mouse submenu 297 to 306 with `C_MENU_MOUSE_P1_AMIGA` 301 and `C_MENU_MOUSE_P2_AMIGA` 304, the Paddles submenu 307 to 316 with `C_MENU_PADDLES_P1_ATARI` 311 and `C_MENU_PADDLES_P2_ATARI` 314. No other constant moved.

Stack, computed from the code (the measurement in the full-system simulation is pending): the deepest chain, a CRT or PRG load in the visible menu, gets 44 words deeper (697 instead of 653 words; lowest stack pointer `0xF925`), the opening of a file in a shortcut session 22 words. The general stack nominally has 768 words down to `0xF8E0`; nothing enforces that bound, and below it are 63 unused words before the heap of the file browser ends at `0xF8A1`.

## 4. Verification record

* **Menu and firmware (commits "OSM: Input Devices section ..." and "menu_test.py: mutant ..."):** `menu_test.py verify` (323 lines, 20 regions, 77 constants, decoder testbench with 326 vectors) and `run` pass; `mutate` kills all 28 mutants, five of them new ones that change `config.vhd` or `mega65.vhd` (a wrong index of two of the new constants, port 2 decoded from the bit of port 1, an item in the group of the other port, the default on the wrong item). The model pins each new constant to its label, group, submenu path and the default in front of it, and checks that each of the four port bits is assigned once, from the right constant and from the menu vector of the right clock domain. `doc/dev-a22x3/tools/menuidx.py` between `6845596` and the working tree: all 81 constants that existed point to the same line text, submenu path and position in their group. GHDL analysis of `config.vhd` and `mega65.vhd`: no new diagnostics. All 22 suites of `doc/dev-a22x3/tools/suites.py`, `bankdepth_test.py` (deepest level 41 of 64, unchanged) and `mount_reject_test.py` pass. `saving_text_test.py` runs the budget check of the `%s` slots with the numbers of the new menu (916 words free after the menu structure, demand 702; one word less is a fatal error).
* Limits of the Shell that were checked against the larger menu: 1 to 512 menu lines, the 4094 characters of `OPTM_ITEMS`, group ids 1 to 254, the nesting depth (still 3), the `%s` slots (allocated per submenu, no fixed number), the label width (19 of 25 characters), the config file (one byte per menu line).

## 5. Found on the way

* `menu_test.py mutate` stopped with a setup error since commit `ea48c0d` because the search string of one mutant was stale; fixed.
* `shortcuts_test.py` models the menu state with 300 words although the menu has more lines; the highest index it uses is 292.
* The SD card images of the full-system simulation under `doc/dev-a22x3/sim/sd/` hold config files for WIP-V6-A22X3 (301 bytes), which the firmware of later versions does not find.

## 6. What only the hardware can show

The list is in section 8 of `RESEARCH-amiga-mouse.md` and section 8 of `RESEARCH-paddles.md`; the test steps will be in `tests/README.md`.
