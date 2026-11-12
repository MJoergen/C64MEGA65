# Merge playbook: the four feature branches on top of the string ROM

For whoever merges `mh_implement_247`, `mh_fix_issue_255`, `mh_implement_153` and `mh_implement_142` into `develop` after the string ROM refactor (`mh_string_rom`). Everything below was done for real in a scratch clone (no push) and every number was measured there. The raw record is in `REPORT.md` next to this file.

## Verdict

- All four branches merge on top of the string ROM refactor. Only the last one (#142) has conflicts that need thought (the menu indices). All other conflicts are documentation: every branch adds its own "WIP-V6-A22X3" entry.
- The result fits easily: `Shell ROM: 20196/28672 words` (8476 free), `String ROM: 9076/16384 characters in 198 strings`. Without the string ROM the same sources need 29028 words, 356 more than the ROM has. So the refactor must be on `develop` before #142 is merged.
- No branch has to move strings in the same step. The two new log strings of #153 end up inside the markers on their own (correct), and all other new strings must stay outside (see "Strings").
- After every merge all firmware suites pass. After the last merge 11 of 11 firmware suites and 5 of 5 VHDL benches of the branches pass.
- No branch moves a submodule pointer (`M2M/QNICE`, `CORE/C64_MiSTerMEGA65`), so the QNICE toolchain stays valid for the whole sequence.

## Before you start

1. The string ROM change is on `develop` (the commit "QNICE firmware: message strings live in a string ROM"). The trial used an earlier state of it, so the conflicts below can differ slightly, see "Resolutions as diffs" at the end.
2. Check that the local `develop` is not behind `origin/develop`.
3. Where the branches live in the main repository: `mh_implement_142` is a local branch only (8 commits, a2b5c71). `mh_implement_247` (4f146da), `mh_fix_issue_255` (8438f11) and `mh_implement_153` (27944b4) exist only as `origin/...` refs. All four start at 1470473 (`WIP-V6-A22X2`).
4. Order: #247, #255, #153, #142 (the tested order). #142 goes last because it carries the big menu change; its conflicts are easiest to solve against the settled menu. Whatever the order, the shortcut menu indices of #142 shift by 10 because of the Stereo submenu of #247, and `python3 M2M/rom/tests/menu_test.py verify` plus `run` decide.

Builds: `cd CORE/m2m-rom && ./make_rom.sh` (about 5 s). It prints `String ROM:` and `Shell ROM:`, and it fails with an error if the firmware exceeds 28672 words.

## Expected numbers

| after | String ROM (characters incl. padding at 4k boundaries) | strings | Shell ROM (words of 28672) | free |
|---|---|---|---|---|
| string ROM refactor | 9076 | 196 | 18488 | 10184 |
| + #247 | 9076 | 196 | 18597 | 10075 |
| + #255 | 9076 | 196 | 18597 | 10075 |
| + #153 | 9076 | 198 | 18825 | 9847 |
| + #142 | 9076 | 198 | 20196 | 8476 |
| optional: shortcut messages moved | 9207 | 210 | 20073 | 8599 |

The `String ROM:` number is the end position after placing the strings, including the gaps at the 4k boundaries; it can stay the same when a few strings are added (the 49 characters of #153 fill a gap). The raw string sizes are 8981, 8981, 8981, 9030, 9030 and 9171 characters.

## Tests

Run from anywhere in the repository after every merge (all must pass; times on this Mac):

| command | from | runtime | expected last line |
|---|---|---|---|
| `python3 M2M/rom/tests/menu_test.py run` | always | 3 to 6 s | `ALL TESTS PASSED` |
| `python3 M2M/rom/tests/menu_test.py verify` | always (needs ghdl) | 2 s | `VHDL DECODER TB: OK (...)` after `VERIFY OK` |
| `python3 M2M/rom/tests/rosm_save_test.py` | always | 10 s | `ROSM_SAVE TEST OK` |
| `python3 M2M/rom/tests/jiffy_test.py` | always | under 1 s | `JIFFY TEST OK: 6 decision-table rows match ...` |
| `python3 M2M/rom/tests/summary_test.py` | #247 | 1 s | `PASS: summary_test` (206 cases, 218 after #142) |
| `python3 M2M/rom/tests/crt_unload_test.py` | #153 | 1 min | `RESULT: PASS` |
| `python3 M2M/rom/tests/shortcuts_test.py` | #142 | under 1 s | `PASS: shortcuts_test (505 trace lines)` |
| `python3 M2M/rom/tests/next_disk_test.py` | #142 | under 1 s | `PASS: 8 cases: ...` |
| `python3 M2M/rom/tests/cfm_test.py` | #142 (needs ghdl) | 22 s | `CFM TEST OK` |

VHDL benches that were also run on the final merge result (one at a time, all `RESULT: PASS`): `CORE/vhdl/test/tb_shortcuts/run.sh all`, `CORE/vhdl/test/tb_stereo_mix/run.sh all`, `CORE/vhdl/test/tb_capslock/run.sh all`, `CORE/vhdl/test/tb_crt_eject/run.sh` (1 min), `CORE/vhdl/test/tb_crt_cacher/run.sh` (4 min). They are worth running once after the last merge: the mega65.vhd resolution of #142 is otherwise only checked by `menu_test.py verify` and the shortcut bench.

`cfm_test.py` and the string ROM: `cfm_test.asm` defines `RELEASE` and includes `M2M/rom/main.asm`, so `strrom.asm` with its `;STRROM_TABLE` marker is in that ROM. The test assembles with the plain `asm` wrapper, so the marker is only a comment, the handle table is empty (`STRROM$TAB` equals `STRROM$TAB_END`) and every string is an ordinary string. It works as is.

## Merge 1: `mh_implement_247` (Stereo Mix)

`git merge --no-ff origin/mh_implement_247` merges without conflicts. It already sets `CORE_VERSION` to `WIP-V6-A22X3`.

Strings: `SS_V_T_FULL`, `SS_V_T_WIDE`, `SS_V_T_NARROW`, `SS_V_T_MONO` in `CORE/m2m-rom/m2m-rom.asm` land below `;STRROM_END`, behind `SS_V_MIX`. Keep them there: `SUBMENU_SUMMARY` copies them character by character with `_SS_APPEND_STR`.

Expect: `String ROM: 9076/16384 characters in 196 strings.`, `Shell ROM: 18597/28672 words.` New test: `summary_test.py`.

## Merge 2: `mh_fix_issue_255` (bank cache)

No firmware change. Two conflicts, both "two branches add the first A22X3 entry":

1. `doc/inofficial.md`, version table: keep one row for `WIP-V6-A22X3` and join the descriptions with "; " like the A22X2 row does: `... Mono (issue #247); bank cache for simulated cartridges holds 32 instead of 8 banks: fixes the flickering of "Eye of the Beholder" and other bank-heavy .crt games (issue #255)` (with the backticks of the original around `.crt`).
2. `tests/README.md`, section `Version WIP-V6-A22X3 - TBD`: one intro line for both issues, then one block per feature. The intro line used in the trial: `@TODO: Test the Stereo Mix (issue #247) and the larger bank cache for simulated cartridges (issue #255) on R3/R3A and R6 at least (R4/R5 when available), the Stereo Mix on HDMI and on the 3.5 mm audio jack, best with headphones. Everything of WIP-V6-A22X2 below still applies.` Then the sub-heading `Stereo Mix for stereo SIDs in the Volume submenu (issue #247):` with the #247 bullets, then the #255 sub-heading `Bank cache for simulated cartridges (32 instead of 8 ROML and ROMH banks):` with its bullets.

`M2M/vhdl/tdp_ram.vhd` of #255 only changes a comment; the string ROM instance `i_strrom` is not affected.

Expect: unchanged numbers (18597). Optional bench: `tb_crt_cacher`.

## Merge 3: `mh_implement_153` (unload a cartridge)

Four documentation conflicts:

1. `M2M/rom/tests/README.md`, list of testbeds: keep both bullets, `summary_test` first, then `crt_unload_test.py`.
2. `VERSIONS.md`, top of `## Bugfixes`: keep both entries (#255 first, then the Super Snapshot V5 entry of #153), with a blank line between them.
3. `doc/inofficial.md`: append `; Space on the CRT: line of the on-screen menu unloads a simulated cartridge (issue #153); a .crt after Super Snapshot V5 starts again` to the A22X3 row (again with the original backticks; keep the capital "Space", it is the key name).
4. `tests/README.md`: the intro line also names "unloading simulated cartridges (issue #153)"; append the #153 block (sub-heading `Unload a .crt with Space on the CRT: line of the on-screen menu:` plus its bullets) after the #255 block.

Firmware (merges without conflict, checked):

- `LOG_STR_ROMUNL` and `LOG_STR_ROMUNLT` land in `M2M/rom/strings.asm` inside the existing `;STRROM_BEGIN` .. `;STRROM_END` region. That is right: `CRTROM_M_UNLD` only passes them to `SYSCALL(puts, 1)`. The new `.EQU` codes `ERR_FATAL_INSTC/INSTD` are below `;STRROM_END`.
- `M2M/rom/shell.asm`: the guard of the refactor at `_HM_SDMOUNTED5` and the changes of #153 (`HANDLE_MOUNTING`, `_HM_UNLOADED`, the "loading" CSR write in `LOAD_IMAGE` moved behind `PREP_LOAD_IMAGE`) do not overlap and fit together: a rejected `.crt` prints `WRN_CRT_TOO_BIG` (a handle) through the guard, and the running cartridge stays loaded.
- `CORE/vhdl/sw_cartridge_wrapper.vhd` (touched by #255 and #153) merges into `C_CACHE_SIZE := 5` plus the eject path.

Expect: `String ROM: 9076/16384 characters in 198 strings.`, `Shell ROM: 18825/28672 words.` New test: `crt_unload_test.py`. Optional bench: `tb_crt_eject`.

## Merge 4: `mh_implement_142` (keyboard shortcuts)

Six conflicted files, 16 hunks. The exact resolution against the conflicted state: `merge/B4_merge_142_conflict_resolution.remerge.diff`.

The cause of most of them: #247 adds 10 menu lines (the nested Stereo submenu) in front of the `Advanced Settings` submenu, where #142 adds its `Keyboard Shortcuts` submenu (102 lines, 7 submenus). The merged menu has 189 + 10 + 102 = 301 lines, 18 submenus, an `OPTM_ITEMS` string of 3192 characters. `python3 M2M/rom/tests/menu_test.py vhdl` prints all derived constants for the merged golden model once `menu_test.py` is resolved; use it for the values below.

### CORE/vhdl/config.vhd

- `OPTM_SIZE`: 199 versus 291. Take `301`.
- Group ids: both branches use 36 (`OPTM_G_STEREO_MIX` versus `OPTM_G_SC_F9`). Keep `OPTM_G_STEREO_MIX := 36` and renumber `OPTM_G_SC_F9 .. OPTM_G_SC_F14` to `37 .. 42`. Group ids are not stored anywhere (the config file stores one bit per menu line, `osm_const.asm` is generated by `make_rom.sh`), and ids up to 254 fit.
- `OPTM_DY` stays 29 (verify computes and checks it).

### CORE/vhdl/mega65.vhd

1. Signals: keep all three, `signal main_volume : natural range 0 to 20 := 20;` (with the initial value of #142), `main_stereo_mix` (#247), `main_sc_freeze` (#142).
2. After `subtype C_MENU_VOLUME is natural range 154 downto 134;`: keep both, the four `C_MENU_STEREO_MIX_*` constants (159 .. 162) and `C_MENU_VOLUME_100 := 134`.
3. RR-Net and shortcuts: keep the RR-Net lines of `develop` (`R_MENU_RRNET is natural range 192 downto 190`, comment "189 .. 192"), then the keyboard-shortcut block of #142 with every index plus 10:

    | constant | #142 | merged |
    |---|---|---|
    | `C_MENU_SC_F9` | 190 | 200 |
    | `C_MENU_SC_F10` | 206 | 216 |
    | `C_MENU_SC_F11` | 222 | 232 |
    | `C_MENU_SC_F12` | 238 | 248 |
    | `C_MENU_SC_F13` | 254 | 264 |
    | `C_MENU_SC_F14` | 270 | 280 |

    `C_SC_FREEZE := 1` unchanged.
4. `volume_decode_proc`: take the version of #142 completely (clocked, holds the last value, the assertion `C_MENU_VOLUME_100 = C_MENU_VOLUME'low`, the six `main_sc_freeze` assignments), then append the Stereo Mix decoder of #247 (`main_stereo_mix <= ...`) after it.

### CORE/m2m-rom/m2m-rom.asm

- `MENU_HEAP_SIZE`: 3456 versus 5248. Take `5248`; the `HEAP_SIZE` lines merge to 1920 and 24960 (= 7168 and 30208 minus 5248) on their own, which is consistent.
- Update the numbers in the comment above it for the merged menu: `301 items, 18 submenus and a 3192-character OPTM_ITEMS string give budget 1 = 22 + 3192 + 4*301 = 4418`, `23 x 27 = 621 words`, `Peak use is 4418 + 621 = 5039, leaving about 209`, and `(3192 now)` at the end.
- Not a conflict, but stale after the merge: further down, in the stack calculation, `(291 lines today)` must read `(301 lines today)`. The rest of that comment is right for the merged firmware: `HEAP` is at 0x82A0, which leaves 1600 words for the stack. `OPTM_SHOW` and `OPTM_RUN` together reserve about 606 words for 301 lines while the menu is drawn (menu.asm, lines 274 and 623), inside that limit.

### M2M/rom/tests/menu_test.py (7 hunks)

1. Group dict: `STEREO_MIX=36,` and `SC_F9=37, SC_F10=38, SC_F11=39, SC_F12=40, SC_F13=41, SC_F14=42,` (same as config.vhd).
2. `V6_MENU`, end of `Advanced Settings`: take the `Keyboard Shortcuts` block of #142 and add 1 to every region number in its comments (the Stereo submenu is region 9 now): `region 12 (in 10)`, `region 13 (in 12)` .. `region 18 (in 12)`, closers `close region 18` .. `close region 13`, `close region 12`, and the final `Back` of `Advanced Settings` is `close region 10`.
3. Summary fixtures: keep the Volume/Stereo fixtures of #247 and add the shortcut fixtures of #142. Two fixtures of #142 test the F13 picker "across bit 255/256" and "Off at bit 254". After the shift by 10 the F13 picker covers bits 264 .. 274 and the F12 picker (248 .. 258) is the one that straddles bit 255/256. The trial uses F12 for these two cases and asserts the straddle, so that the next menu change cannot silently drop the coverage:

    ```python
        f12 = flat_index(" F12: %s")
        # the items of the F12 picker (f12 + 3 .. f12 + 13) straddle OSM control
        # bit 255/256: its default " Load PRG" (f12 + 9) is below the boundary,
        # " Volume up" (f12 + 13) above it
        assert f12 + 3 <= 255 and f12 + 13 >= 256
        ...
        fx.append(("F12 picker across bit 255/256", f12, v6g, base))
        fx.append(("F12 picker Volume up above bit 255", f12, v6g,
                   sel(**{"i%d" % (f12 + 9): 0, "i%d" % (f12 + 13): 1})))
    ```

    (Keeping F13 and only fixing the comments also passes, but then nothing tests the boundary.)
4. and 5. The two "Close Menu" asserts: take the index-free version of #142, `assert s.cursor == flat_index(" Close Menu")`.
6. Navigation script after the OSM submenu: `develop` ends with `assert (s.level, s.cursor) == (0, 167)`, #142 continues from `(0, 157)` with its own numbers. Merged: Advanced Settings is region 10 at flat 167, its first item is 170, Keyboard Shortcuts is region 12, F11 region 15, and (for the bit-255/256 straddle, as above) F12 region 16 instead of F13:

    ```python
        assert (s.level, s.cursor) == (0, 167)
        # Keyboard Shortcuts (#142): pickers two submenu levels below Advanced
        # Settings; the F12 picker straddles OSM control bit 255/256
        ks = flat_index(" Keyboard Shortcuts")       # opener of region 12
        f11 = flat_index(" F11: %s")                 # opener of region 15
        f12 = flat_index(" F12: %s")                 # opener of region 16
        s.feed(KEY_SELECT)              # enter region 10 again
        assert (s.level, s.cursor) == (10, 170)
        s.until(KEY_DOWN, ks)           # to "Keyboard Shortcuts"
        s.feed(KEY_SELECT)              # enter region 12 (depth 2)
        assert s.level == 12 and ks < s.cursor < f11
        s.until(KEY_DOWN, f11)          # to " F11: %s"
        s.feed(KEY_SELECT)              # enter region 15 (depth 3)
        assert s.level == 15 and f11 + 3 <= s.cursor <= f11 + 13
        s.until(KEY_DOWN, f11 + 7)      # to " Next disk drive 8"
        s.feed(KEY_SELALT)              # radio-select it via Space
        s.feed(KEY_LAST)                # last item of the picker: " Back"
        assert (s.level, s.cursor) == (15, f11 + 15)
        s.feed(KEY_SELECT)              # leave via the closer
        assert (s.level, s.cursor) == (12, f11)
        s.until(KEY_DOWN, f12)          # to " F12: %s"
        s.feed(KEY_SELECT)              # enter region 16 (depth 3)
        assert s.level == 16
        s.until(KEY_DOWN, f12 + 3 + 10) # to " Volume up" (above bit 255)
        s.feed(KEY_SELALT)              # radio-select it via Space
        s.feed(KEY_MENUUP)              # pop to region 12, cursor on the opener
        assert (s.level, s.cursor) == (12, f12)
        s.feed(KEY_MENUUP)              # pop to region 10
        assert (s.level, s.cursor) == (10, ks)
        s.feed(KEY_MENUUP)              # pop to main
        assert (s.level, s.cursor) == (0, 167)
    ```
7. `C_MENU` table: keep both, the four Stereo Mix rows and the seven rows of #142 (`C_MENU_SC_F9` .. `C_MENU_SC_F14`, `C_MENU_VOLUME_100`).

No other hard-coded index of #142 is left in `menu_test.py` (checked).

### Documentation

- `M2M/rom/tests/README.md`: keep the `summary_test` and `crt_unload_test.py` bullets and add the `next_disk_test` bullet of #142 after them.
- `tests/README.md`: the intro line names all four issues (`... the Stereo Mix (issue #247), the larger bank cache for simulated cartridges (issue #255), unloading simulated cartridges (issue #153) and the keyboard shortcuts (issue #142) ...`). The bullets of #142 have no sub-heading of their own; give them `Keyboard shortcuts F9 to F14 (issue #142):` and append them as the fourth block.
- `doc/inofficial.md` (no conflict, but #142 still had `WIP-V6-A22X2` and no row): append `; keyboard shortcuts F9 to F14 (issue #142)` to the A22X3 row.
- `CORE_VERSION` stays `WIP-V6-A22X3` (#142 does not touch it).

Auto-merged files that the refactor and #142 both touch, all checked and independent of each other: `M2M/vhdl/qnice_wrapper.vhd` (#142 widens `qnice_osm_control_m_o` to 512 bits, the refactor adds `C_DEV_STRROM` and `i_strrom`), `M2M/rom/menu.asm` (#142 changes `_OPTM_SET_S`, the refactor adds the markers), `M2M/rom/sysdef.asm`, `M2M/rom/shell.asm`, `M2M/rom/strings.asm` (#142 changes the text of `ERR_F_MENUSIZE` inside the markers; it is only passed to `FATAL`).

Expect: `String ROM: 9076/16384 characters in 198 strings.`, `Shell ROM: 20196/28672 words.` `menu_test.py verify` reports `OPTM_SIZE=301  OPTM_DY=29  regions=18  C_MENU constants=73`. New tests: `shortcuts_test.py`, `next_disk_test.py`, `cfm_test.py`.

## Strings

What each branch adds to the firmware and where it belongs:

| branch | labels | file | read by | between the markers? |
|---|---|---|---|---|
| #247 | `SS_V_T_FULL`, `SS_V_T_WIDE`, `SS_V_T_NARROW`, `SS_V_T_MONO` | `CORE/m2m-rom/m2m-rom.asm` | `_SS_APPEND_STR` (copies characters) | no, keep below `;STRROM_END` (where the merge puts them) |
| #153 | `LOG_STR_ROMUNL`, `LOG_STR_ROMUNLT` | `M2M/rom/strings.asm` | `SYSCALL(puts, 1)` only | yes; the merge already puts them inside |
| #142 | `ERR_F_MENUSIZE` (changed text) | `M2M/rom/strings.asm` | `FATAL` | yes, already inside |
| #142 | `SC_S_DRIVE`, `SC_S_COLON`, `SC_S_OFF`, `SC_S_1581`, `SC_S_SAVING`, `SC_S_NONEXT`, `SC_S_NEXTERR`, `SC_S_JOYS`, `SC_S_FLIPPED`, `SC_S_NORMAL`, `SC_S_VOLUME`, `SC_S_PERCENT` | `CORE/m2m-rom/shortcuts_c64.asm` | `SC$MSG_START`, `SC$MSG_ADD`, `SC$TOAST2` (copy characters into `SC_TOAST_BUF`), also via the table `SC_NEXT_MSGS` | no, not as #142 stands |

So the merges need no string work at all. A check that no merged code passes a handle to a routine that needs a pointer: every label in the generated table (between `STRROM$TAB` and `STRROM$TAB_END` in `CORE/m2m-rom/m2m-rom.lis`) that appears in a line the branches added; the trial found three such lines, all handle-aware (`crts-and-roms.asm` 652 and 658: `puts`; `shell.asm` 262: `FATAL`). The script used is `handle_refs.py` next to this file (`python3 handle_refs.py <clone> <commit of the refactor>`).

Optional follow-up, not needed for the size: the twelve `SC_S_*` messages can move into the string ROM if `SC$MSG_ADD` learns handles, exactly like `LOG_STR` did in the refactor. Tested as commit 8e798fd, `merge/0001-Trial-keyboard-shortcut-messages-in-the-string-ROM-1.patch`:

- `M2M/rom/shortcuts.asm`, `SC$MSG_ADD`: `MOVE R8, R4` / `RSUB STRROM$OPEN, 1` / `MOVE R8, R2` / `MOVE R4, R8` before the copy loop, `RSUB STRROM$CLOSE, 1` after the terminator is written; the header says that the inputs can be handles.
- `CORE/m2m-rom/shortcuts_c64.asm`: a comment plus `;STRROM_BEGIN` before `SC_S_DRIVE` and `;STRROM_END` after `SC_S_PERCENT`.
- `M2M/rom/strrom.asm`: add `SC$MSG_START, SC$MSG_ADD (shortcuts.asm) and therefore SC$TOAST and SC$TOAST2` to the list of routines that take handles.
- `M2M/rom/tests/shortcuts_test.asm`: `#include "../strrom.asm"`; without it the testbed does not assemble (`STRROM$OPEN`/`STRROM$CLOSE` undefined).

Result: Shell ROM 20073 (123 words less), String ROM 9207 characters in 210 strings; all 11 firmware suites pass; every moved string decodes correctly from `m2m-strings.rom` through its table word, none crosses a 4k boundary. Not tested: the handle path on hardware or in a simulation with the string ROM device (the emulator has no M2M window, and in the testbed the table is empty). Not worth doing for `SS_V_T_*` (25 characters).

## Pitfalls

1. Group id 36 used twice. If the group-id hunk of config.vhd is resolved by keeping both lines unchanged (`OPTM_G_STEREO_MIX := 36` and `OPTM_G_SC_F9 := 36`), and `menu_test.py` the same way, then `menu_test.py verify` still reports `VERIFY OK`. Only `menu_test.py run` fails: `menu_nav_test` stops with a FATAL of the real firmware (`F C=0008`) where the model expects normal navigation. Always run both.
2. The shortcut indices of #142 must move by 10. The conflict hunk shows the old values (190 .. 270) on the #142 side; taking that side as is gives wrong freezer keys and wrong menu bits. `verify` catches it.
3. The bit-255/256 coverage of the #142 menu tests silently moves from the F13 picker to the F12 picker with the shift (see `menu_test.py` hunks 3 and 6).
4. `MENU_HEAP_SIZE` must stay 5248 (the merged menu needs 5039 at peak). Taking 3456 from `develop` would let the menu heap overflow; the comment numbers must be recomputed, and `(291 lines today)` further down is stale after the merge.
5. Strings that a branch adds inside an existing marked region become handles without any conflict. Here this happens to #153 and is correct; for future merges check every new label inside the markers against its consumers.
6. The `String ROM:` figure includes the padding at the 4k boundaries, so it does not grow with every added string.
7. The four documentation conflicts repeat in every merge (A22X3 row, A22X3 test section). Resolve them the same way each time: one row, one section, one block per feature.
8. Optional observation, not caused by the merge and not tested on hardware: the Stereo Mix decoder of #247 in mega65.vhd is combinational over single menu bits. #142 rewrote the volume decoder because the Shell writes menu bits one at a time ("no bit set" for a moment). For Stereo Mix "no bit" means Full Stereo, so a switch between Wide, Narrow and Mono can pass through Full Stereo for a few clock cycles. Probably inaudible; worth a look by the author of #247.

## Resolutions as diffs

The folder `merge/` next to this file contains the conflict resolutions of the trial merge as diffs: `B2_merge_255_conflict_resolution.remerge.diff`, `B3_merge_153_conflict_resolution.remerge.diff` and `B4_merge_142_conflict_resolution.remerge.diff` are the output of `git show --remerge-diff`, i.e. exactly what was changed relative to the conflicted merge, and `0001-Trial-keyboard-shortcut-messages-in-the-string-ROM-1.patch` is the optional step described in "Strings". The trial was made on top of an earlier state of the string ROM change, in which the firmware was two words smaller and the documentation was not complete yet: the numbers of this playbook are two words lower than what you will see, and the documentation files have a few more simple conflicts.
