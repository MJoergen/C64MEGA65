# WIP-V6-A22X3: merge of the four feature branches, status and running memory

Entry point for anyone, human or coding agent, who picks up this work. It records what was merged, every decision, the numbers, what was verified and how, what was found on the way, and what is still open. The record of the string ROM, on which the merge is built, is `doc/dev-strrom/STATUS.md`.

## 0. State

* **Done:** `mh_implement_247` (Stereo Mix), `mh_fix_issue_255` (bank cache with 32 banks), `mh_implement_153` (unload a cartridge) and `mh_implement_142` (keyboard shortcuts) are merged into `develop` in this order, each with `--no-ff`, on top of the string ROM (`622a0f4`). `CORE_VERSION` is `WIP-V6-A22X3`.
* **Follow-up commits on top of the merges:** 64 register banks for QNICE, the shorter text of the message for a too large `.crt`, `bankdepth_test.py`, the documentation, one flag correction in the shortcut code, and the fix of two defects in the mount code (section 2).
* **Next:** Vivado build of R3 and R6, hardware test (section 7).
* **Not yet built with Vivado and not yet tested on hardware.**

## 1. Decisions

| # | Decision | Reason |
|---|---|---|
| D1 | Merge order 247, 255, 153, 142; all suites and the benches of the merged branches after every merge. | 142 carries the big menu change; its conflicts are easiest against the settled menu. |
| D2 | Stereo Mix keeps menu group id 36; the shortcut groups of #142 are 37 to 42. | Both branches used 36. Group ids are not stored anywhere (the config file stores one bit per menu line). |
| D3 | The shortcut menu indices of #142 are 10 higher than on its branch; `OPTM_SIZE` is 301; `MENU_HEAP_SIZE` stays 5248. | The Stereo submenu of #247 (10 lines) sits in front of the Keyboard Shortcuts submenu (102 lines). |
| D4 | `mega65.vhd`: the clocked volume decoder of #142 (holds its value while no bit is set), followed by the Stereo Mix decoder of #247 as it is. | Both branches changed the same place; the two decoders are independent. |
| D5 | One row for `WIP-V6-A22X3` in `doc/inofficial.md` (date and commit `TBD`) and one section in `tests/README.md` with one block per feature. | Every branch brought its own entry. |
| D6 | QNICE has 64 instead of 32 register banks (`SHADOW_REGFILE_SIZE`). Decided by sy2002. | The keyboard shortcuts nest deeper than 32 banks allow (section 5.1). |
| D7 | New text of `WRN_CRT_TOO_BIG`: two lines of 40 characters. Decided by sy2002. | The second line was two characters wider than the window. |
| D8 | The two defects of the mount code are fixed in this version. Decided by sy2002. | Section 5.2. |
| D9 | The twelve `SC_S_*` messages of the shortcuts stay in the firmware ROM. | Not needed for the size; `SC$MSG_ADD` would have to learn handles. |
| D10 | `doc/dev-strrom/MERGE-PLAYBOOK.md` and `doc/dev-strrom/merge/` are removed. Decided by sy2002. | The merge that they describe is done. |

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

Menu: 301 lines, 18 submenus, `OPTM_ITEMS` has 3,192 characters, `OPTM_DY` is 29. Menu heap: 4,418 + 621 = 5,039 of 5,248 words by the formula in `m2m-rom.asm`. `HEAP` is at `0x82A0`, which leaves 1,600 words for the stack. Register banks: deepest level 41 of 64. Block RAM: the bank cache adds 96 RAMB36 and the string ROM about 4 tiles; the last builds before the merge used 178 of 365 tiles.

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

* The Stereo Mix decoder of `mega65.vhd` is combinational. The Shell writes the menu bits one at a time, so while the selection moves downwards the mix is Full Stereo for a few microseconds. Probably inaudible; the hardware test of #247 listens for clicks.
* `OPTM_HEAP_LAST` (`options.asm`) parks the menu text of a drive while it shows `<Saving>`, and there is only one such buffer: when drives 8 and 9 save at the same time, the line of one drive can show the text of the other until the next mount. Cosmetic, old, found by reading only.
* `tdp_ram.vhd` builds the initial value of a RAM in a local variable of `InitRAM`; for the two cache RAMs of #255 that is 128k x 16 bit each, four times the size that has been synthesized so far (section 7).

## 6. Verification record

* **After every merge:** `make_rom.sh`, `menu_test.py run` and `verify`, `strrom_test.py`, `strrom_tool_test.py`, `strrom_sim_test.py`, `rosm_save_test.py`, `jiffy_test.py`, and from the merge that brings it: `summary_test.py`, `crt_unload_test.py`, `shortcuts_test.py`, `next_disk_test.py`, `cfm_test.py`. Benches: `tb_stereo_mix`, `tb_crt_cacher`, `tb_crt_eject`, `tb_shortcuts`, `tb_capslock`, `tb_turbo`, `tb_ntsc`. All passed, also on `develop` before the first merge.
* **Line provenance** (`tools/provenance.py`): of the 80 files that the branches touch, 74 are the exact sum of the changes of the branches; the 6 others are the hand-resolved files of section 4, and every deviating line was read.
* **Menu indices** (`tools/menuidx.py`, independent of `menu_test.py`): every `C_MENU_*` and `R_MENU_*` constant points to the same line text, submenu path and position in its group as on its branch; group ids are unique; the default selections are the intended ones.
* **Mutants of the hand resolutions:** ten plausible resolution errors (indices that are not shifted, the RR-Net slice, swapped Stereo Mix constants, the old `OPTM_SIZE`, group id 36 used twice with and without the model, a moved default, a lost menu line) were all caught by `menu_test.py`; a group id that is used twice in `config.vhd` and in the model is only caught by `run`, not by `verify`. `summary_test.py mutants`: 6 of 6.
* **Independent review of the merged RTL:** no defect. The 512-bit path of the menu state was elaborated and simulated from `qnice.vhd` to `MEGA65_Core` (all 512 bits arrive unshifted); the bank cache is invalidated on every new cartridge also after an eject; no generate block reads a signal before its declaration; the four `.xpr` list every file.
* **Independent review of the merged firmware:** the two defects of section 5.2 and the flag of section 5.3; no handle of a string ROM string reaches code that needs characters; the unload exit of `HANDLE_MOUNTING` cannot be reached in an invisible shortcut session; no code is left that assumes 256 menu bits; the init order and the consecutive variable blocks are right.
* **Register bank depth:** static analysis, hop by hop by hand for the deepest chain; `bankdepth_test.py --selftest` detects 4 of 4 planted defects.
* **Mount fix:** `mount_reject_test.py` (15 cases, 11 mutants) fails on the code before the fix and passes after it; `crt_unload_test.py` and the handle lint of `strrom_test.py` were extended for the second path of `LOAD_IMAGE`; the register bank depth is unchanged (41).
* **Markdown** (`tools/mdlint.py`): the lines that the merges add contain no bare dollar pair and no bare `==` outside of code.

## 7. What the Vivado build and the hardware test need to show

Vivado (R3 and R6 at least):

* The log shows `String ROM: 9071/16384 characters in 198 strings.` and `Shell ROM: 20225/28672 words.`
* `synth_design` finishes; if it is killed, look for `Killed` or `tcmalloc` in the log: the suspect is then the initial value of the two 128k x 16 cache RAMs (section 5.4).
* Timing is met in every clock domain. `qnice_clk` had 0.415 ns (R3) and 0.458 ns (R6) of slack in the last builds, on the half-cycle read paths of the devices; the register file is twice as large now. `hr_clk` had 1.1 ns: the bank cache looks up 32 instead of 8 banks per half in one clock cycle.
* Block RAM: about 278 of 365 tiles.
* On the build machine: `python3 M2M/rom/tests/strrom_test.py` and `python3 M2M/rom/tests/bankdepth_test.py` pass with the Linux tools.

Hardware: the section `Version WIP-V6-A22X3` of `tests/README.md`.

## 8. Tools

`doc/dev-a22x3/tools/` (all take git revisions, nothing is written into the repository):

* `provenance.py <base> <mainline-before> <final> <branch>...` : line provenance audit of a merge of several branches.
* `menuidx.py <rev>...` (a rev can be `WORKTREE`): what every menu index constant points to, compared across revisions.
* `mdlint.py <from> <to>` : Marked 2 and MathJax lint of the Markdown lines that a range of commits adds.
* `suites.py <step> <suite>...` : runs the firmware suites and the benches one after the other with one result line each; it replaces the clipboard tools by no-ops, because `make_rom.sh` and the assembler wrapper of QNICE copy their output to the clipboard.
