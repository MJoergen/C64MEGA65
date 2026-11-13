# WIP-V6-A22X3: merge of the four feature branches, status and running memory

Entry point for anyone, human or coding agent, who picks up this work. It records what was merged, every decision, the numbers, what was verified and how, what was found on the way, and what is still open. The record of the string ROM, on which the merge is built, is `doc/dev-strrom/STATUS.md`.

## 0. State

* **Done:** `mh_implement_247` (Stereo Mix), `mh_fix_issue_255` (bank cache with 32 banks), `mh_implement_153` (unload a cartridge) and `mh_implement_142` (keyboard shortcuts) are merged into `develop` in this order, each with `--no-ff`, on top of the string ROM (`622a0f4`). `CORE_VERSION` is `WIP-V6-A22X3`.
* **Follow-up commits on top of the merges:** 64 register banks for QNICE, the shorter text of the message for a too large `.crt`, `bankdepth_test.py`, the documentation, one flag correction in the shortcut code, and the fix of two defects in the mount code (section 2).
* **Follow-ups before the Vivado build (section 9), done:** the Stereo Mix decoder holds its value while the selection changes; every drive has a parking slot of its own for the menu text behind `<Saving>`; a shortcut session that read no key ends without the 333 ms waiting time; a shortcut session does not redraw the hidden menu; and one defect that was found on the way is fixed (the label of a drive line after `<Saving>`, section 5.5). Each change is one commit with a test of its own, was reviewed by an independent agent, and the final firmware ran in the full-system simulation.
* **Next:** the Vivado build of R3 and R6 and the hardware test (section 7).
* **Not yet built with Vivado and not yet tested on hardware.**

## 1. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | Merge order 247, 255, 153, 142; all suites and the benches of the merged branches after every merge. | 142 carries the big menu change; its conflicts are easiest against the settled menu. |
| D2 | Stereo Mix keeps menu group id 36; the shortcut groups of #142 are 37 to 42. | Both branches used 36. Group ids are not stored anywhere (the config file stores one bit per menu line). |
| D3 | The shortcut menu indices of #142 are 10 higher than on its branch; `OPTM_SIZE` is 301; `MENU_HEAP_SIZE` stays 5248. | The Stereo submenu of #247 (10 lines) sits in front of the Keyboard Shortcuts submenu (102 lines). |
| D4 | `mega65.vhd`: the clocked volume decoder of #142 (holds its value while no bit is set), followed by the Stereo Mix decoder of #247 as it is (9.2 made it a holding register, too). | Both branches changed the same place; the two decoders are independent. |
| D5 | One row for `WIP-V6-A22X3` in `doc/inofficial.md` (date and commit `TBD`) and one section in `tests/README.md` with one block per feature. | Every branch brought its own entry. |
| D6 | QNICE has 64 instead of 32 register banks (`SHADOW_REGFILE_SIZE`). Decided by sy2002. | The keyboard shortcuts nest deeper than 32 banks allow (section 5.1). |
| D7 | New text of `WRN_CRT_TOO_BIG`: two lines of 40 characters. Decided by sy2002. | The second line was two characters wider than the window. |
| D8 | The two defects of the mount code are fixed in this version. Decided by sy2002. | Section 5.2. |
| D9 | The twelve `SC_S_*` messages of the shortcuts stay in the firmware ROM. | Not needed for the size; `SC$MSG_ADD` would have to learn handles. |
| D10 | `doc/dev-strrom/MERGE-PLAYBOOK.md` and `doc/dev-strrom/merge/` are removed. Decided by sy2002. | The merge that they describe is done. |
| D11 | No follow-up of section 9 gets an entry in `VERSIONS.md`. Confirmed by sy2002. | Each one improves a feature that was never released (drive 9, Stereo Mix, keyboard shortcuts) and does not change what the entry of that feature says (the rule at the top of section 9). |
| D12 | The defect of section 5.5 (the label of a drive line after `<Saving>`) is fixed in this version. Decided by sy2002. | It was found while reading the code for 9.1 and sits in the same routine. |
| D13 | 9.4 stays, although it frees 6 words of stack and not about 300 as section 9.4 expected. Decided by the controller; sy2002 was asked on 2026-11-13 and had not answered when this was written. | The change is correct and tested, saves 14.7 ms per PRG or CRT load by shortcut and removes a latent fatal error (`OPTM_SELECT` in a session without `OPTM_RUN`). It is one commit (`c81361c`) with a test of its own and can be taken out again. |

## 2. Commits

On `develop`, on top of `622a0f4` (string ROM):

| Commit | Content |
|---|---|
| `d0ef7f9` | Merge of `mh_implement_247` |
| `bff2d27` | Merge of `mh_fix_issue_255` |
| `dee282a` | Merge of `mh_implement_153` |
| `fa839cb` | Merge of `mh_implement_142` |
| `e46bc75` | QNICE: 64 instead of 32 register banks |
| `7699899` | The message for a too large `.crt` fits into its window |
| `403bbff` | `M2M/rom/tests/bankdepth_test.py` with its documentation |
| `7e42af0` | Documentation of the merged state; the playbook of the merge is removed |
| `2836cb0` | `SC$MSG_SHOW` clears the Carry flag before `SHR` (no change at run time) |
| `3c1ba8f` | This record and the audit tools |
| `06cda88` | A rejected file no longer changes the mounted image or its menu line, with `mount_reject_test.py` |

No submodule pointer, no Vivado project file (`CORE/CORE-R?.xpr`) and no constraint file changed.

The follow-ups of section 9, on top of `8d704f7`:

| Commit | Content |
|---|---|
| `f14ee31` | 9.2: the Stereo Mix decoder is a register that holds its value (`mega65.vhd`), with the decode part of `tb_stereo_mix` |
| `4189874` | 9.1: one parking slot per drive for the text that `<Saving>` replaces, with `saving_text_test.py` |
| `8b9a2ad` | `<Saving>` on a drive that was mounted by a shortcut keeps the label of its line (section 5.5) |
| `14e8df9` | Benches: the decoders of the Stereo Mix and of the volume must be registers on the rising clock edge |
| `2731524` | `saving_text_test.py` selects devices like the real routines; comments on the parking slots |
| `cad409f` | 9.3: no waiting time after a shortcut session that read no key (`HM_KEYREAD`) |
| `0b437c7` | `shortcuts_test.py`: a session after a visible menu that set the flag; two comments |
| `c81361c` | 9.4: no redraw of the invisible menu after a PRG or CRT load, with `hidden_redraw_test.py` |
| `77686d5` | `mount_reject_test.py` traces the call of `_OPTM_GK_MNT`; wording of `hidden_redraw_test.py` |

The commit behind them brings the documentation, this record and the scenario `r3d` of the simulation. Again no submodule pointer, no Vivado project file and no constraint file changed; the only RTL change is the decoder in `CORE/vhdl/mega65.vhd`. The four commits that follow a review (`14e8df9`, `2731524`, `0b437c7`, `77686d5`) change tests, benches and comments only: the firmware ROM and the string ROM are byte-identical before and after each of them.

## 3. Numbers

| after | Firmware ROM (of 28,672 words) | String ROM (of 16,384 characters) |
|---|---|---|
| string ROM (`622a0f4`) | 18,490 | 9,076 in 196 strings |
| merge of #247 | 18,599 | 9,076 in 196 strings |
| merge of #255 | 18,599 | 9,076 in 196 strings |
| merge of #153 | 18,827 | 9,076 in 198 strings |
| merge of #142 | 20,198 | 9,076 in 198 strings |
| shorter `WRN_CRT_TOO_BIG` | 20,198 | 9,071 in 198 strings |
| fix of the mount code | 20,225 | 9,071 in 198 strings |
| 9.1: one parking slot per drive | 20,238 | 9,071 in 198 strings |
| the label of a drive line after `<Saving>` (section 5.5) | 20,256 | 9,071 in 198 strings |
| 9.3: no waiting time after a session that read no key | 20,278 | 9,071 in 198 strings |
| 9.4: no hidden redraw | 20,284 | 9,071 in 198 strings |

Menu: 301 lines, 18 submenus, `OPTM_ITEMS` has 3,192 characters, `OPTM_DY` is 29. Menu heap: 4,418 + 648 = 5,066 of 5,248 words by the formula in `m2m-rom.asm` (648 words are 24 slots of 27 words: one per drive, submenu and manually loadable CRT/ROM for the `%s` texts, and one parking slot per drive), and the firmware reports the same in the full-system simulation (830 words free after the menu structure, 182 after the slots). `HEAP` is at `0x82A1`, which leaves 1,599 words for the stack: 768 for the stack of the file browser, 768 for the general stack and 63 unused. The lowest stack pointers that the simulation saw are `0xF950` (a disk image that a shortcut mounts through the file browser) and `0xF951` (Load PRG and Load CRT by shortcut, and a CRT load in the visible menu), 112 and 113 words above the lower end of the general stack (`0xF8E0`); section 5.4 has the call chains. Register banks: deepest level 41 of 64. Block RAM: the bank cache adds 96 RAMB36 and the string ROM about 4 tiles; the last builds before the merge used 178 of 365 tiles.

## 4. Conflicts and how they were resolved

* **Merges 1 to 3:** only documentation. `doc/inofficial.md` and `tests/README.md` (D5); in merge 3 also `M2M/rom/tests/README.md` and `VERSIONS.md` (the entries of both sides are kept).
* **Merge 4, `CORE/vhdl/config.vhd`:** `OPTM_SIZE` 301; group ids (D2).
* **Merge 4, `CORE/vhdl/mega65.vhd`:** all signals and constants of both sides; `C_MENU_SC_F9` to `C_MENU_SC_F14` are 200, 216, 232, 248, 264 and 280; the RR-Net slice stays `192 downto 190`; decoders (D4).
* **Merge 4, `CORE/m2m-rom/m2m-rom.asm`:** `MENU_HEAP_SIZE` 5248 with the numbers of the merged menu in its comment; `(301 lines today)` in the stack comment.
* **Merge 4, `M2M/rom/tests/menu_test.py`:** group ids as in `config.vhd`; the Keyboard Shortcuts block of #142 with region numbers that are one higher; the fixtures of both sides. The two summary fixtures and the navigation steps at the OSM control bits 255/256 use the F12 picker (bits 248 to 258), because the F13 picker moved above that boundary; an assertion pins the boundary.
* **Merge 4, documentation:** `M2M/rom/tests/README.md`, `tests/README.md`, and the row in `doc/inofficial.md`.

## 5. Found on the way

### 5.1 Register banks (fixed, D6)

The keyboard shortcuts of #142 run the menu engine invisibly from the main loop, 11 register bank levels deeper than the on-screen menu. A shortcut that opens the file browser reaches level 38 or 39 while the SD card is read, 41 in the worst case of the call graph; the on-screen menu alone reaches 27. The QNICE of this core had 32 banks. On the hardware the bank number wraps around and the registers of the outermost routines are overwritten: mostly without a visible effect, in the worst case (Next disk that falls back to the file browser while another disk image is written back) `SC$SESSION` loses its pointer to `OPTM_DIRECT` and the on-screen menu stays invisible until a reset. The emulator has 256 banks, so no testbed could see it. `M2M/rom/tests/bankdepth_test.py` computes the deepest chain from the sources and is the permanent guard; AGENTS.md, section 7 "Register bank depth", has the rules.

### 5.2 Two defects in the mount code (fixed, D8)

`HANDLE_MOUNTING` and `LOAD_IMAGE` (`M2M/rom/shell.asm`) change state before the core has accepted the selected file:

1. **Since #153, cosmetic.** A `.crt` is loaded, the user picks another `.crt` that `PREP_LOAD_IMAGE` rejects (too large) and leaves the file browser with Run/Stop: the old cartridge keeps running, as intended, but the `CRT:` line shows the name of the rejected file. Cause: `HANDLE_MOUNTING` writes the name into the menu line before it calls `LOAD_IMAGE`.
2. **Old, also in the released V5, data loss.** A disk image A is mounted, the user presses Return on the line of the drive, picks an image that is rejected (wrong size) and leaves with Run/Stop: the drive keeps A, but `LOAD_IMAGE` has already reopened the file handle of the drive (`HNDL_VD_FILES`) with the rejected file B. `FLUSH_CACHE` then writes the next save of the C64 into B, in the size of B; A does not get the save, and the menu shows the name of B.

Fix: `LOAD_IMAGE` checks a new disk image with a scratch file handle first (`_DIRBR_FH`, the pattern of `VD_NEXT_DISK`) and reopens the file with the file handle of the drive only when `PREP_LOAD_IMAGE` accepts it, and `HANDLE_MOUNTING` writes the menu line only after `LOAD_IMAGE` succeeded. `M2M/rom/tests/mount_reject_test.py` runs the real routines against recording stubs in 15 cases and fails on the code before the fix; 11 mutants, among them the reversal of each half of the fix, are caught. The price: a disk image is opened twice when it is mounted. Tested in the emulator only.

### 5.3 Small things (fixed)

* The second line of `WRN_CRT_TOO_BIG` was 45 characters wide in a window of 43 columns (D7).
* `SC$MSG_SHOW` cleared the X flag before `SHR`, which shifts in the Carry flag. The Carry flag was always clear at that point.

### 5.4 Known, left as it is

* The general stack has little room left, and the follow-ups of section 9 did not change that. `OPTM_RUN` and `OPTM_SHOW` each reserve one stack word per menu line (301 lines). Three call chains are about equally deep and leave about 113 of the 768 words free. First, a CRT or PRG load in the visible menu, where `HANDLE_MOUNTING` redraws the menu (`_OPTM_GK_MNT`, `OPTM_SHOW`) while `OPTM_RUN` is on the stack: lowest stack pointer `0xF951`, 653 words used. Second, the opening of a file in a shortcut session, where `FAT32$CD_OR_OF` of the Monitor has about 290 words of local data on top of the 305 words of `OPTM_RUN`: `0xF950` to `0xF954`. Third, until 9.4, the redraw of the hidden menu in a shortcut session: `0xF94B`, 661 words. Every further menu line costs two words in the first chain and one word in the second. There is no static analysis of the stack depth like `bankdepth_test.py` for the register banks.
* Switching the Stereo Mix is an abrupt step (section 9.2, "Limit").
* A key press while the progress bar of Next disk is visible is not seen: the keyboard is not scanned during a session, and a key that is released and pressed again in that time looks like a key that was held all the time.
* After a session for F10, F12 or F14 that read no key, the C64 sees Shift at once if the user still holds it when the function key is released. That is the same input as at the start of every such key combination, where Shift is down before the function key.
* `tdp_ram.vhd` builds the initial value of a RAM in a local variable of `InitRAM`; for the two cache RAMs of #255 that is 128k x 16 bit each, four times the size that has been synthesized so far (section 7).
* Small things that the agents of the follow-ups saw and did not touch: `CRTROM_CHK_NO` (`crts-and-roms.asm`) accepts the id `CRTROM_MAN_NUM`, one behind the last valid one (harmless: `CRTROM_M_NO` only returns existing ids); the label `_OPTM_GK_CR_R` (`options.asm`) is unreachable; a comment in `HANDLE_MOUNTING` reads "so we need to we need to check"; a CRT/ROM slot of `OPTM_HEAP` keeps the flag 1 when its line goes back to `<Load>` (harmless: a load resets it); the mutant loop of the decode part of `tb_shortcuts` counts a mutant as rejected also when it does not build (its two new mutants were checked by hand: 841 wrong cases each).

### 5.5 Found during the follow-ups (fixed)

* **The label of a drive line after `<Saving>` (D12).** A drive that is mounted by a keyboard shortcut keeps the bare file name in its slot of `OPTM_HEAP` (flag 0) until the menu is drawn, because an invisible session does not draw the menu. If the drive was saving at that first draw, the bare name was parked, and after the saving it came back marked as a complete line: the line showed the file name without its label (`8:`) until the next mount, and with the longest file name, whose zero terminator is the flag word, the text ran on into the next slot and over the border of the menu. Only since the shortcuts exist. The parking slot now keeps the flag of the parked text in its last word, and a bare name that is restored is completed like in the normal path.
* **Gaps in tests, found by the reviews and closed.** The decode benches of the Stereo Mix and of the volume did not notice a latch, a register on the falling clock edge or a second register stage, and the lint for a second driver of `main_stereo_mix` missed a slice assignment. `saving_text_test.py` did not model which device is selected, so a missing selection of `config.vhd` before a string read passed. `shortcuts_test.py` had no session behind a visible menu that set `HM_KEYREAD`, so a flag that is cleared at the end of a session instead of at its start passed. No test saw the call from `HANDLE_MOUNTING` into `_OPTM_GK_MNT`: deleting it, or skipping it in a shortcut session together with the updates that must stay, passed.
* **`HEAP` moved by one word** because of `HM_KEYREAD`: it is at `0x82A1` and the stack has 1,599 instead of 1,600 words. The comment at the stack in `m2m-rom.asm` is corrected.
* **`tb_turbo` in a clone.** The bench reads an old revision of the submodule `CORE/C64_MiSTerMEGA65` with `git -C`, so it fails in a clone whose submodule folder is a plain copy of the working tree. A clone for an agent needs a git directory of its own in that folder.

## 6. Verification record

* **After every merge:** `make_rom.sh`, `menu_test.py run` and `verify`, `strrom_test.py`, `strrom_tool_test.py`, `strrom_sim_test.py`, `rosm_save_test.py`, `jiffy_test.py`, and from the merge that brings it: `summary_test.py`, `crt_unload_test.py`, `shortcuts_test.py`, `next_disk_test.py`, `cfm_test.py`. Benches: `tb_stereo_mix`, `tb_crt_cacher`, `tb_crt_eject`, `tb_shortcuts`, `tb_capslock`, `tb_turbo`, `tb_ntsc`. All passed, also on `develop` before the first merge.
* **Line provenance** (`tools/provenance.py`): of the 80 files that the branches touch, 74 are the exact sum of the changes of the branches; the 6 others are the hand-resolved files of section 4, and every deviating line was read.
* **Menu indices** (`tools/menuidx.py`, independent of `menu_test.py`): every `C_MENU_*` and `R_MENU_*` constant points to the same line text, submenu path and position in its group as on its branch; group ids are unique; the default selections are the intended ones.
* **Mutants of the hand resolutions:** ten plausible resolution errors (indices that are not shifted, the RR-Net slice, swapped Stereo Mix constants, the old `OPTM_SIZE`, group id 36 used twice with and without the model, a moved default, a lost menu line) were all caught by `menu_test.py`; a group id that is used twice in `config.vhd` and in the model is only caught by `run`, not by `verify`. `summary_test.py mutants`: 6 of 6.
* **Independent review of the merged RTL:** no defect. The 512-bit path of the menu state was elaborated and simulated from `qnice.vhd` to `MEGA65_Core` (all 512 bits arrive unshifted); the bank cache is invalidated on every new cartridge also after an eject; no generate block reads a signal before its declaration; the four `.xpr` list every file.
* **Independent review of the merged firmware:** the two defects of section 5.2 and the flag of section 5.3; no handle of a string ROM string reaches code that needs characters; the unload exit of `HANDLE_MOUNTING` cannot be reached in an invisible shortcut session; no code is left that assumes 256 menu bits; the init order and the consecutive variable blocks are right.
* **Register bank depth:** static analysis, hop by hop by hand for the deepest chain; `bankdepth_test.py --selftest` detects 4 of 4 planted defects.
* **Mount fix:** `mount_reject_test.py` (15 cases, 11 mutants) fails on the code before the fix and passes after it; `crt_unload_test.py` and the handle lint of `strrom_test.py` were extended for the second path of `LOAD_IMAGE`; the register bank depth is unchanged (41).
* **Full-system simulation** (the real firmware on the simulated QNICE system: real CPU, firmware ROM, string ROM, `config.vhd`, `qnice_wrapper.vhd`, video RAM, `sw_cartridge_csr.vhd` and `crt_parser.vhd`; SD card, keyboard and the other devices as models; tools of `doc/dev-strrom/sim/` adapted to the 512-bit menu state and the eject signal), on the merged firmware with 64 banks: boot without a fatal error; a walk through the menu into the Keyboard Shortcuts submenu with a changed assignment, saved on close with exactly the two changed bytes; Volume down and up with their messages and one deferred save 3 s after the last change; Mount drive 8, Load PRG and Load CRT through the invisible file browser; Next disk including the fallback to the file browser; unloading a `.crt` with Space (reset asserted, status idle, parser reports cartridge id 0 with EXROM and GAME high, reset released, line shows `<Load>`). Register bank peaks: 23 for the menu with the file browser, 34 for a shortcut during the directory read, 35 for Next disk with the fallback; each is 4 below the static worst case because the small test card never takes one branch of the FAT32 library. The same shortcut scenario with 32 banks stops with an index error in `register_file.vhd` at the moment the level reaches 32.
* **Mount fix in the full-system simulation** (real FAT32 library, final firmware): an accepted image mounts as before, with two more block reads of the SD card (538 instead of 536 commands) and 0.5 ms more time. A rejected image over a mounted one: the error message appears, and after Run/Stop the menu line and the file handle of the drive (size and start cluster, dumped from RAM) still belong to the mounted image; an accepted image after the rejected one is mounted normally. A rejected `.crt` over a loaded one: the line keeps the name of the loaded cartridge and the cartridge device is not written. The control run with the firmware before the fix shows the name, the size and the start cluster of the rejected file in the same places.
* **Markdown** (`tools/mdlint.py`): the lines that the merges and the follow-ups add contain no bare dollar pair and no bare `==` outside of code.
* **Follow-ups (section 9), per change:** the test was written first and fails on the code before the change; the implementing agent ran the suites in its clone; the controller read the diff and ran the suites again in the main checkout after every `git cherry-pick`. After each of the four commits that change tests and comments only, the firmware ROM and the string ROM were compared with `cmp`: byte-identical.
* **Adversarial reviews of the follow-ups** (one independent agent per change, with mutants of its own): no defect and no regression in the firmware or in the RTL. 9.2: the old and the new decoder agree for all 15 non-empty selections from every previous value (128 cases with the other menu bits at 0 and at 1); GHDL synthesis gives one 2-bit register with the initial value `"00"`, no reset and no latch; `main_clk_o` is the clock of the menu vector and of the consumer in `main.vhd`. 9.1 and section 5.5: a single drive behaves byte-identically to the code before 9.1; for a parked complete line only the last word of the parking slot differs; the area that the budget check demands is exactly the area that can be written, and it ends 182 words before the heap of the file browser; 16 of 18 extra mutants are caught and the other two cannot change the behavior. 9.3: every place of the Shell that reads a key was listed and followed; none can run in an invisible session without the flag being set, and no path sets the flag without reading a key; a key that is still held cannot fire a shortcut twice; the trace of the visible menu is identical before and after. 9.4: everything that `OPTM_SHOW` and `OPTM_SELECT` do besides the video RAM was followed to its readers (cursor variables, device selection, `OPTM_LVL_PARENT` and `OPTM_LVL_OPENER`, the `%s` slots); none depends on the skipped redraw, and no stale screen can become visible, because every caller that switches the on-screen display on clears characters and attributes first. The gaps that the reviews found in the tests are in section 5.5.
* **Full-system simulation of the final firmware** (the tool set of `sim/` with nvc; the same scripts on the firmware of `8d704f7` as the baseline; the ROM files of the simulated firmware are byte-identical to the build of the final commit). `r3b` (Volume down and up with the deferred save, Load PRG and Load CRT by shortcut): the firmware reports `Free OPTM heap space: 182` (209 before); each of the two loads ends 14.7 ms earlier; the lowest stack pointer is `0xF951` instead of `0xF94B`. The UART output is identical except for four numbers (the available and the free memory, one word less each because of `HM_KEYREAD`; the free ROM space; the free OPTM heap), and the port registers (195 changes), the SD card commands (59) and all 9,374 writes to devices other than the video RAM are identical. The video RAM writes are those of the baseline without the two hidden redraws (3,785 and 3,763 writes, and the 25 attribute writes of one selection bar), so the two dumps that are taken after the loads, while the on-screen display is off, differ. `r3d` (Next disk): the session that falls back to the file browser reconnects the keyboard 340 ms after its window is gone, as before. After the direct mount of DISK2 the keyboard is reconnected 1.2 ms and the message `Drive 8: DISK2.D64` is on the screen 2.1 ms after the UART text of the mount (336.7 ms and 337.7 ms before). An F13 key press 60 ms after the mount is honored: the menu bits change from 100% to 95%, the message `Volume: 95%` appears, and the deferred save writes exactly this change to the config file. Before the change the key press was lost. Up to that key press both runs are identical in all 371,533 writes through the 4k window, in the port registers and in the SD card commands. `r2` (visible menu: a changed shortcut assignment, a CRT load and its unload): all 21 video RAM dumps, also the menu after the CRT load, the port registers (189 changes), all 64,601 writes through the 4k window, the reads of the devices that are not polled and the SD card commands (55) are identical to the baseline; the UART output differs in the same four numbers; both closings of the menu reconnect the keyboard 345 ms after the Help key as before. The register bank peaks are the same as before in all three scripts (35 at most), and the lowest stack pointer of every checkpoint of `r2` and of the mounts of `r3d` is unchanged (`0xF951`, `0xF950`).
* **Final run on the final tree:** all 22 suites of `tools/suites.py` (the firmware suites including `saving_text` and `hidden_redraw`, `strrom_sim`, and the benches `tb_capslock`, `tb_stereo_mix`, `tb_shortcuts`, `tb_crt_eject`, `tb_crt_cacher`, `tb_ntsc`, `tb_turbo`), `bankdepth_test.py` (deepest level 41, margin 22; `--selftest` detects 4 of 4 planted defects), `mount_reject_test.py` (23 cases, 18 mutants) and `summary_test.py mutants` (6 of 6): all pass.

## 7. What the Vivado build and the hardware test need to show

Vivado (R3 and R6 at least):

* The log shows `String ROM: 9071/16384 characters in 198 strings.` and `Shell ROM: 20284/28672 words.`
* `synth_design` finishes; if it is killed, look for `Killed` or `tcmalloc` in the log: the suspect is then the initial value of the two 128k x 16 cache RAMs (section 5.4).
* Timing is met in every clock domain. `qnice_clk` had 0.415 ns (R3) and 0.458 ns (R6) of slack in the last builds, on the half-cycle read paths of the devices; the register file is twice as large now. `hr_clk` had 1.1 ns: the bank cache looks up 32 instead of 8 banks per half in one clock cycle.
* Block RAM: about 278 of 365 tiles.
* The only RTL change of the follow-ups is the Stereo Mix decoder in `mega65.vhd`: two flip-flops with the power-up value `"00"` in the main clock domain instead of combinational logic. No latch may be reported for `main_stereo_mix`.
* On the build machine: `python3 M2M/rom/tests/strrom_test.py` and `python3 M2M/rom/tests/bankdepth_test.py` pass with the Linux tools.

Hardware: the section `Version WIP-V6-A22X3` of `tests/README.md`.

## 8. Tools

`doc/dev-a22x3/sim/` is the tool set of the full-system simulation (its `README.md` describes it).

`doc/dev-a22x3/tools/` (all take git revisions, nothing is written into the repository):

* `provenance.py <base> <mainline-before> <final> <branch>...` : line provenance audit of a merge of several branches.
* `menuidx.py <rev>...` (a rev can be `WORKTREE`): what every menu index constant points to, compared across revisions.
* `mdlint.py <from> <to>` : Marked 2 and MathJax lint of the Markdown lines that a range of commits adds.
* `suites.py <step> <suite>...` : runs the firmware suites and the benches one after the other with one result line each; it replaces the clipboard tools by no-ops, because `make_rom.sh` and the assembler wrapper of QNICE copy their output to the clipboard. `bankdepth_test.py` and `mount_reject_test.py` are not part of it and are run directly.

## 9. Follow-ups before the Vivado build (done)

Four small changes that sy2002 decided to take into `WIP-V6-A22X3` before it is built, and one defect that was found on the way (section 5.5). Each change is one commit with a test of its own; what the reviews found is in follow-up commits that change tests, benches and comments only. Section 2 has the commits, section 6 the verification.

**Bugfixes are documented in `VERSIONS.md` as soon as they are done:** every fix that a user can notice gets its entry in the section `## Bugfixes` of Version 6 in the same commit as the fix, written from the point of view of the user (what went wrong, in which situation). A change that only improves a feature of this version that was never released belongs into the entry of that feature instead, if it changes what the entry says; if it is unclear where a change belongs, ask sy2002. By this rule none of the changes of this section has an entry (D11).

### 9.1 One parking slot per drive for the menu text

* **Problem:** while the line of a drive shows `<Saving>`, its real text is parked in a buffer behind the `%s` slots of `OPTM_HEAP`. There was one buffer for all drives, so when two drives saved at the same time, the second one overwrote the parked text of the first, and the line of the first drive showed the text of the other until the next mount.
* **Change:** every drive has a parking slot of its own: the slot of drive n is at `@OPTM_HEAP_LAST` + n x `@SCR$OSM_O_DX` (`OPTM_CB_SHOW` in `M2M/rom/options.asm`, cases #2a and #2b). The budget check of `HELP_MENU` demands one parking slot per drive instead of one for all: 24 x 27 = 648 instead of 621 words with two drives, peak 5,066 of 5,248.
* **Test:** `M2M/rom/tests/saving_text_test.py` runs the real `OPTM_CB_SHOW`, the budget block of `HELP_MENU`, `M2M$RPL_S` and the block of `HANDLE_MOUNTING` that stores the file name, in two configurations (two drives with the width 27 of this core, three drives with width 20), dumps every slot after every step and compares the trace with an independent model; 22 mutants. On the code before the change the line of drive 8 shows ` 9:DISK-B.D64` after drive 8 finished saving.
* **Result:** in the full-system simulation the firmware reports 182 free words of the menu heap (209 before).

### 9.2 Stereo Mix decoder as a holding register

* **Problem:** `main_stereo_mix` (`CORE/vhdl/mega65.vhd`) was decoded combinationally. The Shell writes the menu bits one at a time in ascending order, so while the selection moves downwards no bit is set for a few microseconds, and the mix was Full Stereo for that time.
* **Change:** `stereo_mix_decode_proc`, a clocked process like `volume_decode_proc` next to it: the register starts at `"00"`, takes the value of a set bit and holds its value while no bit of the group is set. For every selection that is not empty it gives the value of the former decoder, one clock cycle later.
* **Test:** the decode part of `CORE/vhdl/test/tb_stereo_mix` copies the constants, the declaration and the process out of `mega65.vhd` and checks the power-up value, every item alone, the hold from every value for 100 clock cycles, all 12 transitions torn both ways under a monitor that allows only the old and the new value in every clock cycle, and the timing (the output changes with the rising clock edge behind the change of the selection, not before and not later); 12 mutants, among them the former decoder, a latch, a register on the falling clock edge and a second register stage. The volume part of `tb_shortcuts` got the same timing check and two mutants.
* **Limit:** switching the mix stays an abrupt step. If the hardware test still hears a tick, the next step is a crossfade of a few milliseconds in `audio_stereo_mix_proc` of `main.vhd` (one multiplier per channel), which would also suit the volume steps.

### 9.3 No waiting time after a shortcut session that read no key

* **Problem:** every invisible session of a shortcut left `HELP_MENU` through the exit of the visible menu, which waits 333 ms before the keyboard is connected to the core again, so that the Return or Run/Stop that closed the menu does not reach the C64. After a session that read no key (Next disk that mounts the next image) there is no such key: F9 to F14 are not part of the C64 keyboard. The message of Next disk appeared only after the wait, and a second key press within it was lost.
* **Change:** the flag `HM_KEYREAD` (`M2M/rom/shell_vars.asm`). `SC$SESSION` clears it; `HANDLE_MOUNTING` sets it before the file browser and before its two error windows, which are the only places where an invisible session reads a key (the preselected path of `VD_NEXT_DISK` does not pass them); the direct exit of `HELP_MENU` (`_HLP_DIRECT` in `M2M/rom/options.asm`) skips `WAIT333MS` when the flag is clear. The exit of the visible menu always waits and does not look at the flag.
* **Test:** `shortcuts_test.py` runs the real tail of `HELP_MENU`: sessions with and without a key read in both orders, the visible menu with the flag clear and set, and a session behind a visible menu that set the flag; 6 mutants. `mount_reject_test.py` checks the flag in all 23 cases of the real `HANDLE_MOUNTING`; 5 mutants for the flag. The trace of the visible menu is the same before and after the change.
* **Result in the full-system simulation** (`sim/scenarios/r3d.stim`): after the direct mount of the next image the keyboard is reconnected 1.2 ms and the message of Next disk is on the screen 2.1 ms after the mount (337 ms and 338 ms before), and a second shortcut key 60 ms after the mount is honored, which was lost before. A session with a file browser waits as before.

### 9.4 No redraw of the hidden menu in a shortcut session

* **Problem:** after a CRT or PRG load in an invisible session, `_OPTM_GK_MNT` (`M2M/rom/options.asm`) redrew the whole menu into the hidden video RAM.
* **Change:** `_OPTM_GK_MNT_S` skips `OPTM_SHOW` and `OPTM_SELECT` while `OPTM_DIRECT` is set. The state updates of `_OPTM_GK_MNT` and `_OPTM_GK_CRTROM` (`OPTM_SET`, the menu bits) stay, and with `OPTM_DIRECT` zero the code path is the former one.
* **Test:** `hidden_redraw_test.py` runs the real `_OPTM_GK_MNT` and `_OPTM_GK_CRTROM` in 63 cases: with `OPTM_DIRECT` zero the trace is the one of the code without the skip, otherwise the same without the two redraw calls; 8 mutants. `mount_reject_test.py` traces the call from the real `HANDLE_MOUNTING` in both modes; 2 mutants.
* **Result in the full-system simulation** (`sim/scenarios/r3b.stim`, Load PRG and Load CRT by shortcut): each of the two sessions ends 14.7 ms earlier, and nothing else differs (section 6).
* **The stack is not relieved.** The expectation was that the lowest stack pointer ends up about 300 words higher. It moves from `0xF94B` to `0xF951`, 6 words, because two other call chains are as deep as the one that 9.4 removes (section 5.4): the opening of the file in the same session, and the CRT or PRG load in the visible menu, which needs its redraw.

### How the work was organized

One implementing agent per change on a private clone (`git clone --local` of this repository, plus the working trees of the two submodules, a git directory of its own for `CORE/C64_MiSTerMEGA65` and the QNICE binaries of the main checkout), with a brief that contains the design. The controller read every diff, brought the commit into the main checkout with `git cherry-pick` and ran the suites there. Every change was then reviewed by a second, independent agent on a clone of its own. It got the specification and the commit and nobody's conclusions, and its job was to find defects, side effects, regressions, untested paths and tests that cannot fail, with mutants of its own. What a review found went back to the implementing agent for a follow-up commit. Every command that assembles needs a no-op `pbcopy` first in PATH (`tools/suites.py` does it by itself), and a clone runs at most one firmware build or test at a time, because the assembler wrapper uses one fixed temporary file per folder.
