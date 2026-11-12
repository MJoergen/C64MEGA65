# String ROM: status and running memory

Entry point for anyone, human or coding agent, who picks up this work. The design is described in `doc/developer.md` (section "Message strings and the string ROM") and in the header of `M2M/rom/strrom.asm`; the rules for daily work are in `AGENTS.md`, section 7. This file records the decisions, the numbers, what was verified and how, what is still open, and what was found along the way.

## 0. TL;DR

* **What:** the message strings of the QNICE firmware are stored in a block RAM of their own, the string ROM (QNICE device `M2M$STRROM` = `0x0007`), instead of in the firmware ROM.
* **Why:** the firmware ROM has 28,672 words and was 27,214 words full; a string costs one word per character. The branches `mh_implement_247`, `mh_fix_issue_255`, `mh_implement_153` and `mh_implement_142` need 29,028 words together, 356 more than there are.
* **Result:** firmware ROM 18,490 of 28,672 words (10,182 free); string ROM 9,076 of 16,384 characters in 196 strings. With the four branches merged (`WIP-V6-A22X3`): 20,225 words (8,447 free) and 9,071 characters in 198 strings.
* **Phase:** implemented, simulated, reviewed and on `develop` as part of `WIP-V6-A22X3`, together with the four feature branches (section 6). **Not yet built with Vivado and not yet tested on hardware.**
* **Next:** build R3 and R6, run the `WIP-V6-A22X3` section of `tests/README.md`.

## 1. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | The string ROM is a framework device (id `0x0007`, instantiated in `M2M/vhdl/qnice_wrapper.vhd`), not a core device. | The strings belong to the Shell; no new VHDL file and no change of the four Vivado projects. |
| D2 | 16,384 characters of 8 bit (`C_STRROM_ADDR_WIDTH` = 14), same block RAM entity and falling-edge read as the other QNICE devices, preloaded from `CORE/m2m-rom/m2m-strings.rom`. | Proven timing pattern (C64 RAM, video filter ROM); about 4 block RAM tiles. |
| D3 | Strings are marked in place with the comment lines `;STRROM_BEGIN` and `;STRROM_END`; `M2M/tools/asm_strrom.sh` moves them at build time. | The sources stay ordinary assembler sources: the emulator testbeds and a firmware built for RAM assemble the strings in place, and branches that add strings merge without special care. |
| D4 | The label of a moved string is a handle: the address of a table word in the firmware ROM that holds the position of the string. One word per string stays in the firmware ROM. | A handle is recognized by its address range, so pointers to ordinary strings keep working everywhere. |
| D5 | Handle-aware are `IO$PUTS` (`SYSCALL(puts, 1)`), `LOG_STR` and `SCR$PRINTSTR`, and through them `FATAL` and `FATAL_IDX`. Nothing else. | These three routines consume 223 of 223 uses of the moved strings. |
| D6 | Strings that are processed by other code stay in the firmware ROM: `NEWLINE`, `SPACE`, `FN_ROOT_DIR`, `FN_UPDIR`, `FN_ELLIPSIS`, `ERR_F_ATRMLOAD`, `P1581_OSM*`, `SS_K*`, the file extensions, the tables of the QNICE Monitor libraries. | They are read by `strlen`, `strcpy`, `strcmp`, `M2M$CHK_EXT`, `OPTM_LIVE_TEXT` or character by character. |
| D7 | `STRROM$OPEN` and `STRROM$CLOSE` keep the status flags. | `IO$PUTS` preserved Carry and Overflow before the string ROM; Carry is the return flag convention of the firmware. |
| D8 | The string ROM is used in release builds only (`;STRROM_TABLE` is inside `#ifdef RELEASE`). | A firmware built for RAM runs with the stock QNICE Monitor, whose `puts` does not know handles. |
| D9 | No entry in `VERSIONS.md`. | Nothing changes for the user. |

## 2. Numbers

| | Firmware ROM (of 28,672 words) | String ROM (of 16,384 characters) |
|---|---|---|
| `WIP-V6-A22X2` | 27,214 | does not exist |
| `WIP-V6-A22X3`, this change | 18,490 | 9,076 in 196 strings |
| plus `mh_implement_247` | 18,599 | 9,076 in 196 strings |
| plus `mh_fix_issue_255` | 18,599 | 9,076 in 196 strings |
| plus `mh_implement_153` | 18,827 | 9,076 in 198 strings |
| plus `mh_implement_142` | 20,198 | 9,076 in 198 strings |
| shorter text of `WRN_CRT_TOO_BIG` | 20,198 | 9,071 in 198 strings |
| rejected files do not change the mounted image (`doc/dev-a22x3/STATUS.md`) | 20,225 | 9,071 in 198 strings |

The number of string ROM characters is the end position behind the last string and includes the gaps at the 4k boundaries, so it does not grow with every string that is added.

Strings that are still part of the firmware ROM: 851 words after this change and 1,016 words with the four branches merged (`python3 M2M/rom/tests/strrom_test.py --report` lists them). The largest blocks are the `P1581_OSM*` status texts (336 words; a handle-aware `OPTM_LIVE_TEXT` would save about 322), the mnemonic tables of the Monitor debug library (264 words, in the QNICE submodule), the messages of the keyboard shortcuts (`SC_S_*`, 141 words, see section 6) and `ERR_F_ATRMLOAD` (78 words).

RAM: no variable was added; all labels at or above `0x7000` and all `.EQU` values are unchanged. `STRROM$OPEN` uses two stack words more while a string is printed.

## 3. Verification record

### 3.1 Static (permanent: `M2M/rom/tests/strrom_test.py`)

* All 196 strings in `m2m-strings.rom` are identical to the strings of the `WIP-V6-A22X2` firmware (commit `1470473`) and to a reference build that assembles all strings in place.
* The source that the assembler sees differs from the preprocessed source exactly by the removed marked lines and the added table lines.
* No string crosses a 4k window; everything outside of the strings is zero.
* All 223 uses of the 196 handles reach a handle-aware routine: 196 are recognized automatically, 27 were traced by hand and are pinned in the allowlist of the test (the menu fatal callback, `CUSTOM_MSG`, `PREP_LOAD_IMAGE` to `HANDLE_MOUNTING`, the JiffyDOS report, `FATAL_IDX`, the dependency errors).
* The test detects 19 of 19 deliberately wrong variants (wrong ROM content, changed table word, dropped or changed source line, lost 4k padding, a handle passed to `strlen` or `strcpy`, a `.DW` of a handle, arithmetic with a handle, a routine without `STRROM$OPEN`, the changed guard in `HANDLE_MOUNTING`).

### 3.2 Build tool (permanent: `M2M/rom/tests/strrom_tool_test.py`)

* 55 small programs, most of them broken on purpose: the tool accepts the correct ones with the right ROM content and rejects every broken one with exit code 1, a message that names the problem, and no ROM file left behind.
* The tool checks two limits of the QNICE assembler by itself, because the assembler reacts differently on macOS and Linux: an undefined word for a backslash followed by a backslash or a double quote, and source lines of 243 characters or more.
* Linux: both tests were run on the Ubuntu build machine (its awk, C preprocessor and assembler) with the same results as on macOS, including the numbers of section 2.

### 3.3 Simulated hardware (permanent: `M2M/rom/tests/strrom_sim_test.py`)

* GHDL simulation of the real QNICE CPU in the real `qnice_wrapper.vhd` with the real string ROM instance, a test firmware built by `asm_strrom.sh`, and a string ROM that holds all 196 real strings plus 20 strings for edge cases and is full to the last address.
* Checked: every word of all windows as QNICE reads it; `STRROM$OPEN` and `STRROM$CLOSE` for every handle and for values around the limits of the table (R8, device, window, stack pointer, registers, flags) with twelve different devices and windows selected before the call; `IO$PUTS`, `LOG_STR` and `SCR$PRINTSTR` for every handle and for ordinary strings in ROM, in RAM and in the windows of other devices (UART characters, video RAM writes and content, device selection after the call).
* The test detects 30 of 30 deliberately wrong variants of the firmware routines, the build tool and the VHDL (for example: `STRROM$CLOSE` does not restore the window, a wrong shift count, wrong limit checks, read on the rising clock edge, the device decode removed, a string across a 4k window, one changed ROM byte, changed flags).

### 3.4 The complete firmware in simulation, before against after (one-off)

The real firmware ROMs ran on the simulated QNICE system (real `qnice_wrapper.vhd`, CPU, `config.vhd`; video RAM, UART, keyboard, HyperRAM and SD card as models) with scripted key presses and UART input. The tools are in `sim/`.

* **Main scenario** (cold boot until the core info is logged; debug console with Monitor help, memory commands and return into the Shell; menu, submenu, changed selection, help pages; drive mount without SD card): UART output (3,232 bytes), 14 snapshots of the video RAM, every change of the port registers and every access through the 4k window are identical. The only differences are the logged free ROM space, two code addresses that the debug banner prints, and 0.06 percent more run time. No stack or register bank level differs at the checkpoints.
* **Fatal error scenario** (a deliberately wrong `C_VDNUM`, then Monitor commands): UART log (79 lines) and screen identical. A device that is selected by hand in the Monitor stays selected across the output of string ROM strings.
* **Negative control:** one wrong character in the string ROM and two swapped table words are both reported by the comparison.
* Simulators: nvc 1.21 for the main scenario, GHDL 5.1.1 for the fatal error scenario. The cycle counter ran 32 times faster in both firmwares to shorten the real-time waits. `sim/README.md` describes the tools.

### 3.5 Independent review

An adversarial review of the complete change found no blocker and no major problem. Its findings and what became of them:

* `puts` did not preserve Carry and Overflow anymore. No code depended on it (control flow scan over the firmware and over the four feature branches), fixed anyway (D7).
* A handle that reaches code which needs a pointer builds without an error. `strrom_test.py` is the guard; it has to run after every firmware change.
* `make_rom.sh` ended with an error for a firmware that is built for RAM, which stopped the Vivado pre-synthesis hook. Fixed: it reports `Firmware for RAM: ...` and returns 0.
* The QNICE of this core had 32 register banks at that time. `STRROM$OPEN` and `STRROM$CLOSE` need one level while they run; the highest level measured during a complete boot was 9. The string output routines do not get deeper through it: each of them already nests further for every character it prints. Since the merge of the keyboard shortcuts the CPU has 64 banks (section 6).

### 3.6 Existing suites

`menu_test.py run` and `verify`, `rosm_save_test.py` and `jiffy_test.py` pass unchanged. `keyboard_test.asm` includes `strrom.asm` now.

### 3.7 Not verified

* Vivado: block RAM inference of `i_strrom`, the resolution of the file name `C_STRROM_FILE`, timing of the two half-cycle paths (address to block RAM, block RAM to CPU), and the block RAM count (the string ROM adds about 4 tiles; the firmware ROM is sized by the line count of `m2m-rom.rom` and may need fewer than before).
* Real hardware: the section `WIP-V6-A22X3` of `tests/README.md` is the test plan.
* In the simulation of the complete firmware (3.4, 3.8) the SD card controller, the virtual drives, the HyperRAM, the keyboard and the video pipeline are models. Not exercised: a change of the SD card, a successful disk image mount with write-back, PRG loading, JiffyDOS with a drive ROM, and 89 of the 196 strings at run time.

### 3.8 Scenarios with an SD card and further fatal errors

Same method as in 3.4, with nvc and the final firmware; the main scenario of 3.4 was repeated with it as well. In every pair the firmware before and after are equal in UART output, video RAM snapshots, port registers, accesses through the 4k window, SD card commands and stack and register bank levels; the only difference is the logged free ROM space.

* **SD card with files:** a config file with JiffyDOS selected while only `jd-c64.bin` is on the card (JiffyDOS status report from window 2 of the string ROM, the Kernal falls back to Standard), the file browser with a sub-directory, a disk image of a wrong size (`WRN_WRONG_IMG`), a `.crt` that is too large (`WRN_CRT_TOO_BIG`), a broken `.crt` (the error string of the real `crt_parser.vhd`, copied from the window of the cartridge device), a valid `.crt`, and saving the settings to the card (same block, same data).
* **The changed code in `HANDLE_MOUNTING`:** a program counter watch shows that the new firmware prints the too-large message directly (the copy is not executed), that the firmware before copied it, and that both copy the device string of the broken `.crt`.
* **Empty SD card:** config file not found, both "Nothing to browse" messages (`WRN_NO_D64` of the core and `WRN_EMPTY_BRW` of the Shell), the status line of the internal 1581.
* **Fatal errors:** an illegal menu size (`FATAL`) and an unbalanced submenu (`FATAL_IDX` with `ERR_ITEMIDX`), each followed by Monitor commands.
* **Monitor dump of the string ROM** through device `0007`, windows 0 to 4: 240 words, equal to `m2m-strings.rom`. Window 4 shows window 0 again, because the device decodes 14 address bits.
* **Coverage at run time:** 107 of the 196 strings were read completely in at least one scenario (81 of 120 in window 0, 11 of 58 in window 1, 15 of 18 in window 2), and each of them appears in the UART log or on the screen. The other 89 (file commands of the Monitor, the fatal errors that were not provoked, a few log lines) are covered by 3.1 and 3.3.
* **Speed:** the new firmware needs 0.06 to 0.08 percent more time in these scenarios, because every string output saves and restores the device selection.

## 4. Found along the way, not caused by the string ROM, left unchanged

* `LOG_STR` (`M2M/rom/tools.asm`) treats a backslash followed by any character as a line break: after finding the backslash it compares the backslash itself with `n`.
* `SCR$PRINTSTR` prints a CR or a backslash that is not followed by LF or `n` together with the next character without advancing the cursor, reads past the terminator if a string ends that way, and does not clip at the end of the 4k window.
* QNICE assembler: an undefined word for a backslash followed by a backslash or a double quote; after a backslash followed by another character the escape state stays active until the next `n` or `t`; a buffer overflow in the listing writer for source lines of 243 characters or more (macOS aborts, Linux continues).
* Without an SD card the boot log shows `LOADING ROM #...: FAILED` for each auto-load ROM instead of `LOG_STR_RNOMNT`, because `CONFIG_DEVH` is not zero after the failed mount (`crts-and-roms.asm`, seen in simulation only).
* `crts-and-roms.asm` uses `ERR_F_CR_M_CNT` for the check of the auto-load count; `ERR_F_CR_A_CNT` is never used. `LOG_GEN_ROM_NA`, `C64_IMGFILE_G64` and `SPACE` are unused in a release build.
* `M2M/vhdl/QNICE/sdmux.vhd`: the state `s_reset_controller` goes to `s_idle` in both branches, its 100 ms counter is never used.
* Simulation only: `register_file.vhd` has no initial values (the firmware clears registers with `XOR Rx, Rx`, which stays undefined in a simulator), and `qnice_wrapper.vhd` and `config.vhd` index constant arrays with address bits that are out of range while the window is not addressed (the index in the auto-load file name branch of `qnice_wrapper.vhd` is negative for every address). Hardware is not affected; a simulation of the Shell needs guards in copies of these files (`sim/sim.py` has them).
* GHDL 5.1.1 (LLVM) aborts on VHDL-2008 external names; nvc supports them.

## 5. How to check

```
python3 M2M/rom/tests/strrom_test.py          # build + static checks, about 10 s
python3 M2M/rom/tests/strrom_test.py --report # also: what is left in the firmware ROM
python3 M2M/rom/tests/strrom_tool_test.py     # the build tool against 55 inputs, about 6 s
python3 M2M/rom/tests/strrom_sim_test.py      # simulated hardware, needs ghdl, 1.5 to 4 minutes
```

Run the first one after every change of the firmware: it is the only thing that notices a handle that is passed to code which needs a pointer.

## 6. Merge of the feature branches

`mh_implement_247` (Stereo Mix), `mh_fix_issue_255` (bank cache with 32 banks), `mh_implement_153` (unload a cartridge) and `mh_implement_142` (keyboard shortcuts) were merged into `develop` in this order on top of this change. After every merge all firmware suites and the benches of the merged branches passed; the numbers are in section 2. What matters for later work:

* **Strings.** `LOG_STR_ROMUNL` and `LOG_STR_ROMUNLT` of `mh_implement_153` (`strings.asm`) are string ROM strings: they are only printed with `puts`. The strings of `mh_implement_247` (`SS_V_T_*` in `m2m-rom.asm`) and of `mh_implement_142` (`SC_S_*` in `shortcuts_c64.asm`) are copied character by character and are located outside of the markers. `SC$MSG_ADD` of the keyboard shortcuts could learn handles the way `LOG_STR` did; that would move the twelve `SC_S_*` messages (141 words) into the string ROM and save about 123 words.
* **Menu.** `mh_implement_247` and `mh_implement_142` both used menu group id 36: Stereo Mix kept it, the shortcut groups are 37 to 42. The Stereo submenu sits in front of the Keyboard Shortcuts submenu, so the menu indices of the shortcuts are 10 higher than on their branch (`C_MENU_SC_F9` to `C_MENU_SC_F14`: 200, 216, 232, 248, 264, 280). `OPTM_SIZE` is 301 and `MENU_HEAP_SIZE` is 5248 (peak use 5039). `menu_test.py verify` does not notice a group id that is used twice; `menu_test.py run` does. Always run both.
* **Register banks.** The keyboard shortcuts run the menu engine invisibly from the main loop, 11 register bank levels deeper than the on-screen menu. A shortcut that opens the file browser reaches level 38 or 39 while the SD card is read (41 in the worst case of the call graph), which is more than the 32 banks that the QNICE of this core had; the on-screen menu alone reaches 27. On the hardware the bank number wraps around and the registers of the outermost routines are overwritten, and the emulator testbeds cannot see it because the emulator has 256 banks. `SHADOW_REGFILE_SIZE` in `M2M/vhdl/QNICE/qnice_globals.vhd` is 64 now, and `M2M/rom/tests/bankdepth_test.py` computes the deepest call chain from the sources and fails when it comes too close to that limit.
* **Block RAM.** The bank cache of `mh_fix_issue_255` adds 96 RAMB36 on top of the tiles of the string ROM (section 3.7).
