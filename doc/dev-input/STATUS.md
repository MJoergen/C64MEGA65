# Input devices (issues #190 and #193): status and running memory

Amiga mouse and Atari CX30 paddles, selectable per port in the on-screen menu. `SPEC.md` is the design, `RESEARCH-amiga-mouse.md` and `RESEARCH-paddles.md` are the facts behind it. This file records the state of the work, the decisions, the verification and what is open.

## 0. State

* Branch `mh_implement_190_193`, branched from `develop` at `6845596` (WIP-V6-A25). The version of this work is WIP-V6-A26. Not merged into `develop`.
* Nothing of this has run on hardware. No Vivado build has been made from the branch.

| Part | State |
|---|---|
| Research (both issues, all links of the issues, board schematics, MEGA65 core sources) | done |
| Specification | done |
| Menu, menu bits, ports of `MEGA65_Core`, firmware budgets | in work |
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
| D4 | The mouse is presented as a 1351: POT value = 64 + 7-bit position, one count of the mouse is one LSB. | Format of a real 1351; scale of the MEGA65 core and of VICE, so the same mouse feels the same in both cores. |
| D5 | Rate limiter: one step per 400 µs, backlog of 127 counts. | A 1351 driver takes more than 63 steps between two calls as a movement in the other direction; fast optical mice would reach that at 8 cm/s. |
| D6 | Right and middle button only for a mouse or adapter with pull-ups on pins 9 and 5, found out by observation (a value below 128 has been seen); a button that is pressed for 30 s is released. | The board cannot tell an open pin from a grounded one. The release covers the exchange of a mouse with pull-ups for one without. |
| D7 | The direction lines of a port in Amiga mode are hidden from the C64. | On port 1 they are in parallel with the keyboard matrix. |
| D8 | Atari paddles: the count of a longer window, halved (factor 2, window of 510 ticks, cycle of 769 ticks). The cycle is only long while a port is set to Atari, and a port in C64 mode is always counted in the same 255 ticks. | A ratio is independent of the board. A 1 MOhm paddle then reads like a 500 kOhm one. With all settings at "C64" the measurement is bit-identical to before, and a 1351 on a port in C64 mode always sees its window. |
| D9 | The four paddle values cross into the core clock domain through `cdc_stable` instead of per-bit synchronizers. | Found during the analysis: a read of the SID register in the clock cycle of a change could return a value that was never measured (a 1351 jumps by up to 32 units). |
| D10 | Menu: section "Input Devices" in "Advanced Settings" with the submenus "Keyboard Shortcuts", "Mouse" and "Paddles"; the two new submenus have a headline, the two items of port 1, a line, the two items of port 2, a line and "Back"; no `%s` summary on the openers. | Layout asked for by the owner; the line between the ports is an addition. |
| D11 | The 1 ms debouncer stays as it is for the setting "C64". | A 1351 only sends its buttons over the debounced lines; the devices that the filter breaks (section 6 of `RESEARCH-amiga-mouse.md`) also need the core to drive the port lines, which it does not do. |

## 2. Questions to the owner

Asked on 2026-11-14, no answer yet; the work continues with the default.

1. Are the ports of the submenus the sockets of the MEGA65 (D1)? Default: yes.
2. Does the right button of an Amiga mouse work with the MEGA65 core? Research answered it: not without a pull-up (mega65-core issue #751).
3. Menu details (D10). Default: as described.
4. End state: the branch is pushed, not merged. Default: yes.

## 3. What only the hardware can show

The list is in section 7 of `RESEARCH-amiga-mouse.md` and section 8 of `RESEARCH-paddles.md`; the test steps will be in `tests/README.md`.
