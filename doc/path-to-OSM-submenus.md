Path to OSM submenus
====================

Design document for **multi-level (nested) submenus** in the MiSTer2MEGA65 on-screen menu (OSM). Research result of June 2026; no code has been written yet. Together with [path-to-OSM-dependencies.md](path-to-OSM-dependencies.md) this is the second of the two OSM enhancements that ship with **M2M V2.1.0** and the **C64MEGA65 V6** core.

* Testbed: C64MEGA65 **V6** (this repository, including its vendored `M2M/` folder). The reference menu structure is [#189](https://github.com/MJoergen/C64MEGA65/issues/189) (new V6 on-screen menu), which contains three sub-submenus and therefore needs exactly three menu levels: main menu → submenu → sub-submenu.
* Framework: ships as a **minor** release **M2M V2.1.0** — existing M2M cores must keep working unchanged (see section 7).
* Companion: [path-to-OSM-dependencies.md](path-to-OSM-dependencies.md) ([#229](https://github.com/MJoergen/C64MEGA65/issues/229), "smart dependencies"). Both features modify the same firmware routines; section 8 specifies how they compose and in which order to implement them.

1. Motivation and use case
--------------------------

The V6 menu (#189) reorganizes everything behind submenus — and three of its menus are nested two deep: "OSM Scaling" and "VIC-II model" live inside "Advanced Settings", and the scanline/filter selection ("HDMI: Scanlines") lives inside the HDMI submenu. MJoergen already tried this with the current firmware and reported in #189 (2026-04-26): *"I just made a quick test, and the OSM crashes when using sub-sub menus."* That crash is fully explained in section 3.5: the firmware's submenu parser treats the submenu markers as a **toggle**, so a nested "open" marker is misread as the close of the enclosing region.

This document specifies multi-level submenus with these headline properties:

* **Zero new `config.vhd` syntax.** A nested submenu is written exactly the way MJoergen intuitively tried it: put a complete `OPTM_G_SUBMENU` … `OPTM_G_SUBMENU + OPTM_G_CLOSE` block *inside* another one. No new constants, no new selectors, no probe, no `OPTM_GTC` change.
* **No breaking changes in M2M.** The new bracket parser is proven (by survey *and* by an emulator regression harness) to behave bit-identically to the old toggle parser on every legacy config (section 4.3).
* **No depth limit.** The algorithm is depth-agnostic; depth is naturally bounded by `OPTM_SIZE ≤ 254` (≈127 levels). No per-level RAM: the design needs **one net additional word** of variable space.

### Resolved design decisions

Discussed and decided up front (sy2002, 2026-06-12):

1. **The close line and the <kbd>Run/Stop</kbd> key pop exactly one level** (sub-submenu → submenu → main menu), with the cursor restored onto the submenu label the user came from. Consequence for #189: the "Back to main menu" labels inside sub-submenus should be reworded (e.g. " Back"), since they return to the *parent* menu. Labels are core-author text; the firmware does not care.
2. **No opt-in probe.** The bracket parser ships always-on. Justification: the ecosystem survey (section 3.7) found zero deviations from the open/close convention in 112 submenu regions across 59 real-world configs, the shipped parser provably *forces* that convention, and the emulator equivalence harness (section 10) is the regression gate.
3. **No hardcoded depth cap.** Earlier drafts considered a fixed "main → sub → sub-sub" limit; the chosen builder algorithm makes arbitrary depth free, so no `OPTM_MAX_DEPTH` constant exists.

2. Terminology
--------------

* **Region** — a contiguous flat range of menu lines bracketed by an *opener* line and a *closer* line. Region **ids** are assigned 1, 2, 3, … in the order the openers appear in `config.vhd` (the main menu is "region 0").
* **Opener** — a line whose group word has the `OPTM_SUBMENU` flag (0x4000) and group-id low byte **0x00** (in `config.vhd`: plain `OPTM_G_SUBMENU`, optionally + `OPTM_G_START`). It doubles as the submenu's **label line** in the parent menu.
* **Closer** — a line with the `OPTM_SUBMENU` flag and a **nonzero** low byte; by universal convention `OPTM_G_SUBMENU + OPTM_G_CLOSE` (0x0C0FF). The "Back" line.
* **Parent** of a region — the region (or main menu) its opener sits in. Nesting = a region whose parent is not 0.
* **Level** — the value of the firmware variable `OPTM_MENULEVEL`: the region id whose contents are currently displayed (0 = main menu). Note: a level is a region id, **not** a depth counter — this is true today and stays true.

3. Ground truth: how submenus work today
----------------------------------------

Everything in this section was verified against the source on branch `develop` (June 2026); file:line references are anchors into the current code. Readers familiar with the internals can skim to 3.5.

### 3.1 Authoring model and data flow

A submenu is a bracketed flat range inside `OPTM_ITEMS`/`OPTM_GROUPS` (`CORE/vhdl/config.vhd`). The C64 core currently has six regions, all at depth 1: SID (flat 15..40), Kernal (43..51), HDMI display mode (55..66), HDMI filter (67..79), VGA (81..91), OSM scaling (92..105). Every opener is exactly `OPTM_G_SUBMENU` (resolved 0x0C000, low byte 0x00) and every closer is exactly `OPTM_G_CLOSE + OPTM_G_SUBMENU` (0x0C0FF). The main "Close Menu" line (flat 109) is `OPTM_G_CLOSE` *without* the submenu flag — that is the only structural difference between "close the whole OSM" and "leave a submenu".

The firmware sees the group words through config selector `SEL_OPTM_GROUPS` 0x0301 (config.vhd:771-774), masked to `{b15, b14, '0', b12, "0000", b7..b0}` — the submenu discriminator bit 14 **does** reach the firmware; `menu.asm` masks it with `OPTM_SUBMENU .EQU 0x4000` (menu.asm:20).

Two facts that constrain any design:

* **Openers cannot carry a group id.** The enter-vs-leave dispatch (menu.asm:964-967) tests *only* the selected line's low byte: zero → enter, nonzero → leave. A nonzero id on an opener would flip "enter" into "leave". This has been true since submenus shipped (M2M V2.0.0) and is why the wild configs are perfectly uniform.
* `OPTM_G_SUBMENU` = 0x0C000 also sets bit 15 (`OPTM_G_SINGLESEL`), but the firmware only ever masks bit 14 on these lines; bit 15 is dead weight on submenu lines. Submenu lines have no selected state and are never saved to the config file (config.vhd:355-360).

### 3.2 The structure builder `_OPTM_STRUCT` — today a toggle parser

`_OPTM_STRUCT` (menu.asm:1262-1362) is rebuilt from scratch **on the caller's stack** at every `OPTM_SHOW` (menu.asm:257-262) and every `OPTM_RUN` (menu.asm:596-604). It produces the per-line *structure array*: word 0 = item count, then one word per flat line with **bits 0..14 = region id** of the line and **bit 15 = "visible at the current `OPTM_MENULEVEL`"** (doc block menu.asm:1242-1254). Every consumer of menu geometry goes through this array: drawing skips bit-15-clear lines with a skip counter (OPTM_SHOW menu.asm:303-327, 474-547; `OPT_PRINTSTR` options.asm:840-841), cursor movement skips them (menu.asm:649-650, 697-698), the flat-index→screen-row translator `_OPTM_R_F2M` counts only visible lines (menu.asm:1364-1424), and `OPTM_SET` tolerates out-of-view lines via carry (menu.asm:1159-1162).

Today the array is built in three passes:

* **Pass 1** (menu.asm:1276-1294) assigns region ids with a **single boolean region flag R5** that simply *toggles* on every `OPTM_SUBMENU`-flagged line: flag clear → the line opens a region (R3 := next id, id counter increments); flag set → the line is treated as the closer (stored with the current id, flag cleared, id reset to 0). The low byte is **not** consulted here. There is no stack and no nesting concept.
* A dangling region (flag still set at the end, i.e. an odd number of flagged lines) is fatal `OPTM_F_MENUSUB` (menu.asm:1296-1301).
* **Pass 2** (menu.asm:1303-1317) sets bit 15 := (region id == `OPTM_MENULEVEL`), full-word compare.
* **Pass 3** (menu.asm:1322-1359) implements the *label special case*: the first line of a region (detected heuristically as "first occurrence after the low byte of the id changed", menu.asm:1330-1334) is forced **visible when at main level** (`OR 0x8000` at menu.asm:1345, only when `OPTM_MENULEVEL == 0`) and forced **invisible inside its own region** (`AND 0x7FFF` at menu.asm:1354). The opener's array word keeps the region's **own** id in bits 0..14 — that is what the enter path reads.

### 3.3 Enter, leave, keys, state

* Selecting any `OPTM_SUBMENU`-flagged line short-circuits **before** the selection callback (menu.asm:746-753 → `_OPTM_RUN_SM`; documented at menu.asm:563-566). `OPTM_CB_SEL` / the core's `OSM_SEL_PRE/POST` are **never invoked** for openers and closers.
* `_OPTM_RUN_SM` (menu.asm:955-978): reads the region id from the structure-array word of the selected line (`AND 0x7FFF`), then decides enter-vs-leave purely on the group word's low byte (menu.asm:964-967). **Enter** (`_OPTM_RUN_SM_1`): `OPTM_MENULEVEL` := the line's region id; the current cursor is saved in `OPTM_MAINSEL` — a **single word** (menu_vars.asm:18-19). **Leave** (`_OPTM_RUN_SM_L`, menu.asm:969-973): `OPTM_MENULEVEL` := **0, hardcoded** ("0=main menu"), cursor := `OPTM_MAINSEL`. These two single-level assumptions (hardcoded 0, one-word save) are the entire reason "Back" cannot pop one level today.
* After enter or leave, `_OPTM_RUN_SM_4` (menu.asm:997-1003) frees the on-stack array, calls `OPTM_SHOW` (which rebuilds the array under the new level) and restarts `OPTM_RUN`.
* The find-first-selectable scan after entering, `_OPTM_RUN_SM_2` (menu.asm:981-994), walks the **group words only** (`AND 0x00FF` ≠ 0 = selectable) and never consults visibility — today safe, because inside a depth-1 region every line is visible (section 5.3 explains why nesting breaks this).
* Keys (OPT_MENU_GETKEY, options.asm:964-1021): <kbd>Run/Stop</kbd> = `OPTM_KEY_MENUUP`: at a submenu level it jumps into the shared leave path; at main level it closes the OSM (menu.asm:722-728; the comment at menu.asm:719-721 even says *"as long as we only have one submenu level this means: back to main menu"*). <kbd>Help</kbd> closes the OSM from any level.
* **`OPTM_MENULEVEL` persists across OSM close/reopen.** Nothing resets it except `OPTM_INIT` at firmware boot (menu.asm:205-206, reached via options.asm:261 ← shell.asm:113). Close the OSM inside a submenu, press Help again: you are back inside that submenu, cursor on the same line (`OPTM_SELECTED` persists too, options.asm:210-221). The multi-level design keeps this behavior.
* Background redraws while the OSM is open (vdrive dirty/mount/CRT-ROM status, options.asm:969-980, 1092-1098) call `OPTM_SHOW` + `OPTM_SELECT` with no state changes — they redraw the *current* level, at any depth.

### 3.4 Validation, %s summaries, heap slots

* **Boot check** `_HLP_S3` (options.asm:516-545): counts all `OPTM_SUBMENU`-flagged group words; odd count → fatal `ERR_F_MENUSUB` (strings.asm:171); `OPTM_SCOUNT` := count/2 (the number of regions).
* **Heap budget 2** (options.asm:156-198): the `%s` replacement-string area holds `(@VDRIVES_NUM + @OPTM_SCOUNT + @CRTROM_MAN_NUM + 1)` slots of `@SCR$OSM_O_DX` (= 27) words, in the fixed order vdrives → submenus → CRT/ROMs → scratch (shell_vars.asm:29-46; same convention duplicated in shell.asm:410-435).
* **`%s` summary** (`OPTM_CB_SHOW` case (a), options.asm:1313-1519): the **slot index** of a heading = the number of lines before it that have the SUBMENU flag *and* low byte ≠ 0xFF — i.e. it counts **openers** (options.asm:1464-1492). The **default summary walk** (options.asm:1354-1379) scans forward from the heading for the first *selected* plain radio member (full group word passing `in_range_u(1, 255)`, options.asm:1369-1371 — single-select, headline and other flagged words fall outside); reaching the end of the whole menu is fatal `ERR_F_MENUSUB` (options.asm:1359-1361); hitting **any** `OPTM_SUBMENU`-flagged word is fatal `ERR_F_MENUNGRP` (options.asm:1365-1367) — the code cannot tell a nested opener from its own closer. The core can override the summary via the `SUBMENU_SUMMARY` callback (CORE/m2m-rom/m2m-rom.asm:45-62; the C64 returns 0 = default semantics).
* Important for nesting: both the slot-index count (openers) and `OPTM_SCOUNT` (flagged/2) generalize *unchanged* to balanced nested configs — every region is exactly one opener + one closer, nested or not, so the heap layout, the crtrom slot offsets (options.asm:1676-1696) and `HANDLE_MOUNTING`'s offsets (shell.asm:424-435) all stay consistent for free.

### 3.5 Anatomy of the sub-submenu crash (what MJoergen hit)

Take the "Advanced Settings" pattern: `open(Adv)`, item, `open(OSM)`, items…, `close`, `open(VIC)`, items…, `close`, sep, `close`. Six flagged lines — an **even** number, so neither the boot parity check nor the in-builder dangling check fires. Pass 1's toggle then misparses: `open(Adv)` opens region 1; **`open(OSM)` is treated as region 1's closer**; the OSM items land at *main level* (id 0); `close` opens region 2(!); `open(VIC)` "closes" it; VIC items land at main level; the second `close` opens region 3; the final `close` "closes" it. At main level the user sees the sub-submenus' *contents* inlined and orphaned "Back" lines (which pass 3 even surfaces as bogus region labels). The actual crash: selecting the `open(OSM)` line inside region 1 — its structure word carries the *parent's* id 1, so "enter" re-enters level 1, `_OPTM_RUN_SM_2` then parks the cursor on the next nonzero-low-byte line, which is **invisible at level 1**, and the next `_OPTM_R_F2M` conversion returns carry → fatal `OPTM_F_MENUIDX` (menu.asm:607-617, 1005-1009) → the Shell's fatal handler **halts all of QNICE** (options.asm:810 registers `FATAL` as the menu library's fatal callback). A variant with a shared closer (odd count) dies earlier, at boot, with `ERR_F_MENUSUB`. If a nested label carries `%s`, `OPTM_CB_SHOW`'s walk can also fatal `ERR_F_MENUNGRP`. All of these are symptoms of one root cause: **the toggle parser cannot represent nesting.**

### 3.6 Budgets today (the RAM situation)

* Menu heap: `MENU_HEAP_SIZE` = 1920 words (CORE/m2m-rom/m2m-rom.asm:576). Usage today: 19 (record) + 1220 (OPTM_ITEMS string — note `\n` is **two** characters in a VHDL string literal, there are no escape sequences) + 1 + 3×110 (groups/stdsel/lines arrays) + 1 = **1571** words (budget-1 check options.asm:129-145), plus `%s` slots (1+6+2+1)×27 = **270** (budget-2 check options.asm:156-198). **Total 1841 of 1920 — only 79 words spare.** Any menu growth requires raising `MENU_HEAP_SIZE` (a core-local `.EQU`); see section 5.7.
* Stack: the structure array costs `OPTM_SIZE`+1 words on the QNICE stack per build; worst case two arrays coexist (OPTM_RUN's plus a background-redraw OPTM_SHOW via options.asm:976/1092): 2N+4 words plus ~100 words of call overhead, against a declared main-stack budget of 1536−768−2 = 766 words (m2m-rom.asm:607-613, shell.asm:91-97). Safe up to N ≈ 330; the architectural cap is 254 anyway.
* ROM: 24212 of 28672 usable words (the 4K MMIO window 0x7000-0x7FFF is not ROM, qnice.vhd:519-523) — **4460 words headroom**; this feature needs an estimated 250-400. (The checked-in `m2m-rom.rom` has 24723 lines because qasm2rom appends the RAM `.BLOCK` sections as zero words; the `.lis` END_OF_ROM figure governs. The sizing comment at m2m-rom.asm:594-602 is one word stale vs. the fresh listing — HEAP is 0x81E7, physical stack 1785.)
* Variables: 487 words at 0x8000..0x81E6, allocated by `.BLOCK` in include order; adding words just shifts the heap up — the physical stack region has 249 words of undeclared reserve, so a handful of new variable words is free.

### 3.7 The ecosystem survey (June 2026)

To validate the no-breaking-changes claim empirically, all discoverable M2M cores on GitHub were surveyed (gh code search for `OPTM_G_SUBMENU`/`OPTM_GROUPS`, the repo search for MiSTer2MEGA65, plus manual probes): **59 config.vhd files from 56 repos**, including the M2M template itself, VIC20MEGA65, MegaPET/PET_MEGA65, two C128 efforts, two Amiga ports, zxuno4mega65, sharp-mz-mega65, the complete sho3string arcade fleet (21 submenu-using repos), the rjaremczak arcade forks, and every MyFirstM2M clone. Results:

* 46 configs use submenus, **112 regions** in total. In **all** of them the closer is `OPTM_G_CLOSE + OPTM_G_SUBMENU` (whitespace variants only) and the opener's low byte is 0x00 (bare `OPTM_G_SUBMENU`; in exactly 3 regions plus `OPTM_G_START`, which does not touch the low byte: zxuno4mega65, MegaPET, PET_MEGA65). **Zero nesting, zero unbalanced files, zero deviations.**
* Adjacent regions (closer at flat index *i*, opener at *i*+1) are common in the arcade fleet — the new parser must (and does) handle them.
* `M2M/rom/menu.asm` is **byte-identical** (same md5) across template V2.0.0, V2.0.1, master, develop, this repo and all 14 V2-era cores hashed — there is exactly **one parser generation** in the wild. (One core, Rhialto/MegaPET, carries a benign local `OPTM_SET` patch; its submenu parser is untouched.) The 13 remaining configs are V1-era (no submenu support at all).
* All cores vendor `M2M/` as a plain committed directory, not a submodule: **no deployed core changes behavior when M2M releases** — only when an author actively re-vendors, and at that moment their configs are provably bracket-clean.
* There is no official documentation to contradict: the wiki's On-Screen-Menu page is 100% `@TODO`; the only written statement is one line in the Ultimate Porting Guide ("marks both the entry line in the main menu AND the closing line of the submenu block"). Authors copy the template — which is why the convention is perfectly uniform.

4. The design
-------------

### 4.1 Authoring model: nest the brackets

A nested submenu is a complete `open … close` block placed inside another region. That is the whole syntax. From the #189 "Advanced Settings" menu:

```vhdl
-- inside OPTM_ITEMS:                       -- parallel OPTM_GROUPS entries:
" Advanced Settings\n"  &                   OPTM_G_SUBMENU,                       -- open  "Advanced"      (region 8)
" Advanced Settings\n"  &                   OPTM_G_HEADLINE,
"\n"                    &                   OPTM_G_LINE,
" RTC for GEOS\n"       &                   OPTM_G_RTC_GEOS + OPTM_G_SINGLESEL,
" OSM: %s\n"            &                   OPTM_G_SUBMENU,                       -- open  "OSM Scaling"   (region 9, nested)
" OSM Scaling\n"        &                   OPTM_G_HEADLINE,
--  ... the nine scaling percentages ...
" Back\n"               &                   OPTM_G_SUBMENU + OPTM_G_CLOSE,        -- close "OSM Scaling"
" CIA: Use 8521 (C64C)\n" &                 OPTM_G_CIA_8521 + OPTM_G_SINGLESEL,
" VIC-II: %s\n"         &                   OPTM_G_SUBMENU,                       -- open  "VIC-II model"  (region 10, nested)
--  ... 656x/856x options ...
" Back\n"               &                   OPTM_G_SUBMENU + OPTM_G_CLOSE,        -- close "VIC-II model"
"\n"                    &                   OPTM_G_LINE,
" Back\n"               &                   OPTM_G_SUBMENU + OPTM_G_CLOSE,        -- close "Advanced"
```

Authoring rules (unchanged from today, now explicit):

* Opener = `OPTM_G_SUBMENU`, low byte must stay 0x00 (only `OPTM_G_START` may be added — and only on a *depth-1* opener, section 5.5). Closer = `OPTM_G_SUBMENU + OPTM_G_CLOSE`. Brackets must balance; regions nest strictly (overlap is inexpressible).
* The opener doubles as the label in the parent view; `%s` in its text shows the summary of the region's first selected radio group, at any depth.
* `OPTM_DY` is still hand-sized: it must cover the **largest view** (usually the main menu) — count one line per direct child label, none for nested contents (section 6.2 shows the #189 numbers).

### 4.2 Semantics

* **Region ids** are assigned in opener order (1-based), exactly as today. `OPTM_MENULEVEL` keeps meaning "the region id currently displayed".
* **Visibility** of a line at level L (this is the complete rule set — it replaces the pass-2/pass-3 pair):
  * plain line in region R (innermost): visible ⇔ L == R;
  * opener of region R with parent P: visible ⇔ **L == P** (the label shows in the *parent* view; today's "label visible in main menu" is the P = 0 special case);
  * closer of region R: visible ⇔ L == R.
* **Enter**: selecting an opener sets `OPTM_MENULEVEL` to that region's id and redraws — today's code, minus the `OPTM_MAINSEL` bookkeeping.
* **Leave** (selecting the closer, or <kbd>Run/Stop</kbd> at any level > 0): `OPTM_MENULEVEL` := the **parent** region's id, cursor := the flat index of the left region's **opener**. From a sub-submenu this lands in the parent submenu with the cursor on its label — decision 1. <kbd>Run/Stop</kbd> at main level still closes the OSM; <kbd>Help</kbd> still closes from anywhere; reopening still returns to the persisted level.
* **State, persistence, bits**: untouched. Every line keeps owning one bit of the 256-bit `osm_control` vector by flat position; submenu lines still have no state; the config-file format (one byte per line, exactly `OPTM_SIZE` bytes) is unchanged.
* **`%s` summaries**: per region, at any depth; the default walk reports the first selected radio member *of that region*, skipping nested child regions (section 5.4).
* **The intentional behavior change** (only for configs that are already broken): even-but-unbalanced marker sequences now fatal cleanly at boot (section 5.5) instead of misbehaving later. The newly rejected set has exactly two classes (established by brute force over all marker sequences up to length 8 — the divergence is strictly old-accepts → new-rejects, never the reverse): (a) **close-first** sequences (a closer before any matching opener) — today these render a scrambled menu whose surfaced closer line dispatches as "leave" and whose contents are unreachable; (b) **opener-surplus** sequences (more openers than closers, no prefix violation, e.g. `O O … C`) — today these render a perfectly *normal-looking* menu, but the unmatched opener (drawn exactly where the "Back" line would be, and always cursor-reachable) **halts all of QNICE** with `OPTM_F_MENUIDX`/`OPTM_F_NOSEL` the moment it is selected. Both classes are guaranteed-reachable landmines, not working configs; the survey found zero of either. Do not mistake an even-count boot fatal on a menu that "looked fine" (class b) for a regression.

### 4.3 Why this cannot break legacy configs (the equivalence argument)

For any well-formed depth-1 config — opener (low byte 0x00) … closer (low byte ≠ 0) pairs, never nested, which is **every functioning M2M config in existence** (section 3.7) — the bracket parser and the toggle parser produce *word-identical* structure arrays at every level:

| Line class | Old result (passes 1-3) | New result (section 5.1) |
| ---------- | ----------------------- | ------------------------ |
| plain line outside any region | id 0; visible ⇔ L==0 | id 0 (empty region stack); visible ⇔ L==0 |
| opener of region R | id R (pass 1); pass 2 gives visible ⇔ L==R, pass 3 then forces visible at L==0 and invisible at L==R ⇒ net: visible ⇔ L==0 | id R; visible ⇔ L==parent==0 |
| plain line inside region R | id R; visible ⇔ L==R | id R (innermost = R, no children exist); same |
| closer of region R | id R (stored before the toggle resets); visible ⇔ L==R | id R; visible ⇔ L==R |

Pass 3's heuristics ("first occurrence after the low byte of the id changed") touch only openers in such configs — adjacent regions (ids R, R+1) and a region at flat index 0 re-arm the detection correctly, and the first line of an id-run *inside* a view is skipped because the run's opener already consumed the first-occurrence flag. The visible-count output (R9) is the count of bit-15 lines in both versions. Enter/leave equivalence: enter saves nothing the new design needs; leave goes to parent 0 (= old hardcoded 0) with the cursor on the region's opener — which is exactly what `OPTM_MAINSEL` contained, because entering a region always happens by selecting its opener. The boot check accepts every balanced sequence the old parity check accepted; the even-but-unbalanced remainder (the close-first and opener-surplus classes, section 4.2) is rejected earlier and more cleanly than today's behavior.

This argument is verified mechanically by the equivalence harness in section 10 (old and new builder run side by side over legacy-shaped fixtures, including the current C64 110-entry GROUPS array and the wild-survey patterns, at every level — arrays must match word-for-word). That harness, not the survey, is the regression gate for "no breaking changes".

Compatibility in the other direction — a *nested* config on *old* firmware — is unsupported and crashes exactly as today (section 3.5); a core that wants nesting re-vendors M2M ≥ 2.1.0 together with its menu change. This is the normal M2M upgrade model.

5. Firmware implementation inventory
------------------------------------

All changes live in `M2M/rom/menu.asm` and `M2M/rom/options.asm` (shared M2M code, ships with V2.1.0) except the heap constant (5.7, core-local). No init-record change, no new selectors, no config.vhd change. Estimated ROM cost: 250-400 words (headroom 4460).

### 5.1 The new structure builder (replaces `_OPTM_STRUCT` passes 1-3, menu.asm:1262-1362)

One forward pass; the **CPU stack** doubles as the transient region-parse stack (push on open, pop on close — at most *depth* words, bounded by `OPTM_SIZE`/2 ≤ 127; see 5.6 for the stack budget). The array layout (word 0 = count; bits 0..14 = region id; bit 15 = visible) is **unchanged**, so every consumer — `_OPTM_R_F2M`/`_OPTM_R_F2M_O`, the three OPTM_SHOW loops, `OPT_PRINTSTR`, cursor movement, `OPTM_SET`'s out-of-view tolerance, `_OPTM_RUN_SM`'s id read — keeps working without modification.

```
; In:  GROUPS = heap groups array, N = item count, L = @OPTM_MENULEVEL
; Out: STRUCT[0] = N; STRUCT[1+i] = id(i) | visible(i)<<15;  R9 = number of visible lines
; Side effects (the "leave bookkeeping", see 5.2):
;   OPTM_LVL_PARENT := parent region id of L     (0 when L == 0)
;   OPTM_LVL_OPENER := flat index of L's opener  (unused when L == 0)
cur := 0            ; current innermost region id (0 = main)
next := 1           ; next region id to assign
vis := 0            ; visible-line counter
if L == 0: OPTM_LVL_PARENT := 0                       ; refresh byproducts every build
for i in 0 .. N-1:
    w := GROUPS[i]
    if w AND 0x4000:                                  ; OPTM_SUBMENU-flagged
        if (w AND 0x00FF) == 0:                       ; ---- opener
            parent := cur
            push cur                                  ; CPU stack = region stack
            cur := next;  next := next + 1
            if cur == L:                              ; builder runs AT level L:
                OPTM_LVL_PARENT := parent             ;   record parent + opener
                OPTM_LVL_OPENER := i                  ;   as a byproduct
            v := (L == parent)                        ; label visible in parent view
            STRUCT[1+i] := cur OR (v << 15)
        else:                                         ; ---- closer
            if region stack empty: FATAL OPTM_F_MENUSUB (R9 := i)
            v := (L == cur)
            STRUCT[1+i] := cur OR (v << 15)
            cur := pop
    else:                                             ; ---- plain line
        v := (L == cur)
        STRUCT[1+i] := cur OR (v << 15)
    if v: vis := vis + 1
if region stack not empty: FATAL OPTM_F_MENUSUB (R9 := flat index of the last opener seen)
R9 := vis
```

Notes for the implementer:

* **Calling contract unchanged**: the caller reserves R9+1 stack words and passes the array pointer in R8, the item count in R9 (menu.asm:253-262, 596-604); R9 returns the visible count, R8 stays the array pointer. The GROUPS array is fetched internally via the init record (`@OPTM_DATA` + `OPTM_IR_GROUPS`) and the level via `OPTM_MENULEVEL`, exactly as the old code does (menu.asm:1262-1272).
* "Push/pop" can literally be `MOVE Rx, @--SP` / `MOVE @SP++, Rx` interleaved with the pass, with a depth counter in a register for the empty-check; the pass must pop everything before returning on the fatal paths too (the fatal callback never returns, so only the success path matters in practice).
* `OPTM_F_MENUSUB` (menu.asm:49-51) is reused for both balance fatals; passing the offending flat index in R9 costs nothing and turns "missing submenu-end-flag" into a locatable diagnostic (today R9 is always 0, menu.asm:1300). Caveat: `FATAL` suppresses the hex code when R9 = 0 (shell.asm:1433-1436) — hence "last opener seen" rather than 0 for the unclosed case; the closer-at-flat-index-0 corner of the other fatal stays blind, which is acceptable.
* Pass 3's label heuristics and the pass-1 toggle disappear entirely; the routine gets *shorter* in concept (one loop instead of three) even if the register juggling grows slightly.
* The `cur == L` byproduct assignment fires at most once per build (region ids are unique); when L is a stale id larger than `next` ever reaches (impossible within one power session, since the config cannot change), the defensive outcome is an empty view — an optional `vis == 0 && L != 0` assert can fatal early, but it is unreachable by construction.

### 5.2 Enter and leave (`_OPTM_RUN_SM`, menu.asm:955-1003)

* **Enter** (`_OPTM_RUN_SM_1`, menu.asm:975-978): keep `OPTM_MENULEVEL := struct word AND 0x7FFF`; **delete** the `OPTM_MAINSEL` save (menu.asm:977-978). Nothing else: the builder's byproduct variables make saved return-state unnecessary at any depth.
* **Leave** (`_OPTM_RUN_SM_L`, menu.asm:969-973), shared by the closer line and <kbd>Run/Stop</kbd>-at-level>0 (menu.asm:722-728): replace `MOVE 0, @R9` + `OPTM_MAINSEL` restore with:

```
_OPTM_RUN_SM_L  MOVE    OPTM_LVL_PARENT, R8
                MOVE    @R8, @R9                ; OPTM_MENULEVEL := parent id
                MOVE    OPTM_LVL_OPENER, R8
                MOVE    @R8, R2                 ; cursor := opener of left region
                RBRA    _OPTM_RUN_SM_4, 1       ; redraw + restart (unchanged)
```

The byproduct variables always describe the *current* level because the builder runs on every `OPTM_SHOW`/`OPTM_RUN` — including after reopening the OSM at a persisted level and after background redraws. The restored cursor (the opener) is by definition visible in the parent view, so the `_OPTM_R_F2M` conversion after the restart cannot fatal. Update the stale comment at menu.asm:719-721 ("as long as we only have one submenu level…") while there.

### 5.3 The enter-cursor scan (`_OPTM_RUN_SM_2`, menu.asm:981-994)

Today the scan stops at the first line with a nonzero group-id low byte. With nesting, the first such line after an opener can sit **inside a nested child** (invisible at the entered level) → cursor on an invisible line → fatal `OPTM_F_MENUIDX` on restart. New stop condition, scanning from the opener+1:

```
stop at the first line i with:  (GROUPS[i] AND 0x4000) != 0   OR   (GROUPS[i] AND 0x00FF) != 0
```

A child opener (0x4000, low byte 0) now *stops* the scan — correct, because the child's label is a visible, selectable line of the entered view (cursor lands on it; today's code would have skipped it). A child's contents can never be reached: the child's opener is encountered first. The entered region's own closer (low byte 0xFF) also stops the scan, so the cursor always finds a visible line and the `OPTM_F_NOSEL` fatal (menu.asm:991-994) becomes unreachable for well-formed configs (keep it as a guard). **Dependencies composition:** when the DEPS feature (companion doc) is active, the scan must additionally skip lines whose dependency predicate is false (two-load test against the resolved DEPS array + `OPTM_IR_STDSEL`); a region's closer cannot be dependent (deps doc, section 3.3 restrictions), so termination is still guaranteed. *This closes a gap in the dependencies doc, which patched the visibility consumers but not this scan.*

### 5.4 The `%s` summary walk (`OPTM_CB_SHOW`, options.asm:1354-1379)

The default walk must skip nested child regions instead of fataling on them. Combined algorithm (including the DEPS skip from the companion doc, section 4.4):

```
; walking forward from the heading; R6 = end-of-menu sentinel (options.asm:1329-1331)
d := 0                                       ; child-region depth counter
loop:
    advance to next line; reaching end of whole menu -> FATAL ERR_F_MENUSUB    (unchanged, options.asm:1359-1361)
    w := group word
    if w AND 0x4000:
        if (w AND 0x00FF) == 0:  d := d + 1;  continue        ; child opener: start skipping
        if d > 0:                d := d - 1;  continue        ; child closer: stop skipping
        FATAL ERR_F_MENUNGRP                                  ; own region's closer reached: no group found (unchanged semantics, options.asm:1365-1367)
    if d > 0:                    continue                     ; inside a child region
    if w fails in_range_u(1,255): continue                    ; not a plain radio member (keep the existing test verbatim, options.asm:1369-1371)
    if DEPS active and line is dep-hidden:  continue          ; companion doc §4.4
    if OPTM_IR_STDSEL[line] == 0: continue
    -> found: extract this line's label (unchanged, options.asm:1383-1431)
```

For legacy configs `d` never leaves 0 and the behavior is bit-identical. The slot-index loop (options.asm:1464-1492) and the heap budget already count openers/regions correctly for nested configs (section 3.4) — **no change there**. While touching this routine, remove the stray `ADD 1, @R2` at options.asm:1515 — at that point R2 holds the masked group word (0x4000, produced at options.asm:1337-1339), so the instruction increments the word at *address* 0x4000: a silent no-op on the ROM-mapped hardware today, a latent hazard in any other memory map.

Authoring rule that falls out: a region whose opener carries `%s` must contain at least one multi-select (radio) group of its own, outside any child region — otherwise `ERR_F_MENUNGRP`, same as today's rule, now with "outside any child region" added.

### 5.5 Boot validation (`_HLP_S3`, options.asm:516-545)

Replace the parity check with a real balance scan over the config-device GROUPS window (no stack needed — only balance is validated here, parentage is the builder's job):

```
depth := 0;  opens := 0;  lastopen := 0
for i in 0 .. OPTM_ICOUNT-1:
    w := GROUPS[i]
    if i == start_line:                                         ; the OPTM_G_START line, located just
        if depth != 0 and not opens-just-incremented-to-depth-1: ;   before this scan (options.asm:284-302)
            FATAL ERR_F_MENUSTART-class fatal (R9 := i)          ; START on a line invisible at main level
    if w AND 0x4000:
        if (w AND 0x00FF) == 0:  depth := depth + 1;  opens := opens + 1;  lastopen := i
        else:
            if depth == 0:  FATAL ERR_F_MENUSUB  (R9 := i)       ; closer without opener
            depth := depth - 1
if depth != 0:  FATAL ERR_F_MENUSUB  (R9 := lastopen)            ; opener without closer
OPTM_SCOUNT := opens
```

For balanced configs `opens` equals the old flagged/2, so `OPTM_SCOUNT`'s three consumers (heap budget options.asm:172, crtrom slots options.asm:1688, mount slots shell.asm:429) are untouched. Strictly stronger than the parity check: everything it newly rejects is one of the two already-broken classes of section 4.2 — both reject all odd counts, and the divergence is strictly old-accepts → new-rejects. The `ERR_F_MENUSUB` string (strings.asm:171) still fits; consider appending "(item index in code)" to the message (R9 = 0 suppresses the code display, shell.asm:1433-1436).

**The START check is mandatory, not optional** — it guards a crash that the new visibility rules *introduce*: `OPTM_G_START` must sit on a line that is visible at main level, i.e. either at depth 0 or on a *depth-1 opener* (the condition above: the line is outside all regions, or it is itself the opener that took depth from 0 to 1). Under the old parser every opener was forced visible at main, so START on a *nested* opener was harmless; under the new rules a nested opener is invisible at level 0, and a start cursor on an invisible line halts with `OPTM_F_MENUIDX` on the very first Help press — and again after every "Close Menu" exit, because `_HLP_RESETPOS` rewrites `OPTM_SELECTED := @OPTM_START` (options.asm:216-221). A boot fatal with the offending index is the correct failure mode for this authoring error. (Putting START on a line *inside* a region was already broken before this feature — the check now catches that pre-existing trap too.)

**Optional, recommended: validate view heights.** Nothing checks that every view fits `OPTM_DY` — `OPTM_SHOW` silently draws past the frame (no clipping; "scroll" does not exist in menu.asm), and nesting makes the hand-count error likelier. The scan can compute every view's height with a small parse stack (2 words per depth: region id + running line counter): on an opener, credit one line (the label) to the current counter, push it, start a fresh counter; on a closer, credit the closer line, compare the completed counter against `@SCR$OSM_O_DY − 2`, pop; at the end compare the main-level counter. Overflow → fatal (reuse `ERR_F_MENUSIZE`'s neighborhood in strings.asm:167-180) or at least a serial log line. If implemented here, this scan needs the parse stack that the plain balance check otherwise avoids — still bounded by depth, at boot, on an otherwise empty stack.

### 5.6 Variables and stack budget

* `menu_vars.asm`: **delete** `OPTM_MAINSEL` (menu_vars.asm:18-19), **add** `OPTM_LVL_PARENT .BLOCK 1` and `OPTM_LVL_OPENER .BLOCK 1`. Net **+1 word** of RAM; in `OPTM_INIT`, replace the `OPTM_MAINSEL` init pair (menu.asm:207-208) with zero-inits of the two new variables (the `OPTM_MENULEVEL` init at 205-206 stays). No other persistent state — there is deliberately **no return stack**: parent and opener are re-derived by every build, so arbitrary depth costs nothing and the state can never go stale or overflow.
* Transient: the builder's region stack adds ≤ depth words below the structure array. Worst-case stack load (background redraw while OPTM_RUN is live, two arrays + one build): 2·N + 4 + depth + ~100 call-overhead words. For the V6 menu (N=159, depth 2): ≈ 425 of 766 declared words. Theoretical maximum (N=254, depth 127): ≈ 739 — still inside the budget, no `STACK_SIZE` change required.

### 5.7 Heap sizing (core-local; the V6 numbers)

`MENU_HEAP_SIZE` (CORE/m2m-rom/m2m-rom.asm:576) must grow — **independently of this feature**: the companion DEPS design alone (4th per-line array + 1 record word) puts today's 110-line menu at 20+1220+1+4·110+1 = 1682 + 270 = **1952 > 1920**. With the V6/#189 menu (section 6: N=159, strlen=1596, 10 regions, with DEPS):

```
budget 1: 20 + 1596 + 1 + 4*159 + 1                  = 2254 words
budget 2: (1 vdrive + 10 submenus + 2 crtroms + 1)*27 =  378 words
total                                                 = 2632 words
```

**Recommendation: `MENU_HEAP_SIZE .EQU 3072`** (slack ≈ 440 for label growth), compensated per the file's own convention: RELEASE `HEAP_SIZE` 28288 → 27136, DEBUG 5248 → 4096 (m2m-rom.asm:578-592). The file-browser heap loses ≈ 50 directory entries per directory in RELEASE; overflow there is graceful (DIRBROWSE_READ code 2 = truncated listing, dirbrowse.asm:40-44). Do not touch `STACK_SIZE`. Other cores keep their own values until they need bigger menus; the budget-1/-2 fatals (`ERR_FATAL_HEAP1/2`) report the exact overrun at boot, as today.

### 5.8 Hardening and cleanup (cheap, do in the same pass)

* `OPTM_SELECT` ignores the carry from `_OPTM_R_F2M_O` (menu.asm:1033) and would highlight a wrong row for an out-of-view index — add the carry check (return instead of draw). Pre-existing latent bug, becomes more reachable with more levels.
* A selectable group spanning menu levels fatals on two paths: the user-select path fires *first* — the radio-deselect loop `_OPTM_RUN_7` converts every full-word-equal group member with `_OPTM_R_F2M` and fatals `OPTM_F_MENUIDX` on carry (menu.asm:846-854) — and `OPTM_SET`'s partner search fatals `OPTM_F_MENUGRP3` (menu.asm:1196-1200). Already an (undocumented) authoring error today; document it: **a selectable group must live entirely inside one region**.
* Grep hygiene: menu.asm threads `OPTM_MENULEVEL` into R11 for `OPTM_FP_PRINTXY` calls (menu.asm:795-796, 862-863) — the Shell's `SCR$PRINTSTRXY` ignores R11 entirely; the parameter is vestigial and needs no multi-level attention.
* Update comments: menu.asm:719-721 (Run/Stop), menu.asm:1242-1254 (`_OPTM_STRUCT` doc block), config.vhd template comment for `OPTM_G_SUBMENU` ("starts/ends a section…" → describe nesting), and the M2M Porting-Guide wiki line. The M2M template's `config.vhd` needs **no functional change** — only the comment.

6. Core-side: the V6 menu from #189 as the worked example
---------------------------------------------------------

This is the complete target menu, transcribed from #189 with four adjustments, each flagged inline: (a) the "HDMI: Scanlines" sub-submenu gets the existing eight HDMI-filter options as its content (#189 leaves it empty; today's "HDMI Filter" submenu is exactly this list, config.vhd:609-621); (b) the flicker-free line exists twice (PAL/NTSC twin groups — companion doc, decision 4); (c) "Back to main menu" inside submenus becomes " Back" (decision 1: it pops one level); (d) where #189's `*`/`=` marker glyphs are internally inconsistent (e.g. "=CRT:&lt;Load&gt;" marks a load line, not a toggle; "=Audio improvements" carries no `*` although it defaults on today), the listing follows today's config.vhd semantics for `OPTM_G_STDSEL`/`OPTM_G_SINGLESEL`. Lines carrying `OPTM_DEP(…)` tags require the companion DEPS feature; until it lands, drop the tags — the only effect is that both PAL and NTSC variant lines show at once (dev-branch optics, nothing breaks). The three NTSC display-mode rows (37/39/41) are **structural placeholders**: "576p 60 Hz" as sketched in #189 has no plumbed video mode today (the plumbed NTSC-rate modes are 720p60, 480p59.94, 640×480p60, 800×600p60 — companion doc, section 5.1); keep the row count and swap the labels/modes when #181/#105 decide the final set — flat indices and `OPTM_DEP` tags do not change.

```
  idx  OPTM_ITEMS line                    OPTM_GROUPS entry
    0  " C64 for MEGA65\n"                OPTM_G_HEADLINE
    1  "\n"                               OPTM_G_LINE
    2  " 8:%s\n"                          OPTM_G_MOUNT_8 + OPTM_G_MOUNT_DRV + OPTM_G_START
    3  " PRG:%s\n"                        OPTM_G_LOAD_PRG + OPTM_G_LOAD_ROM
    4  "\n"                               OPTM_G_LINE
    5  " Expansion Port\n"                OPTM_G_HEADLINE
    6  "\n"                               OPTM_G_LINE
    7  " Use hardware slot\n"             OPTM_G_EXP_PORT + OPTM_G_STDSEL
    8  " Simulate cartridge:\n"           OPTM_G_EXP_PORT
    9  " CRT:%s\n"                        OPTM_G_MOUNT_CRT + OPTM_G_LOAD_ROM
   10  " Simulate 1750 REU 512KB\n"       OPTM_G_REU + OPTM_G_SINGLESEL
   11  "\n"                               OPTM_G_LINE
   12  " C64 Configuration\n"             OPTM_G_HEADLINE
   13  "\n"                               OPTM_G_LINE
   14  " Model: %s\n"                     OPTM_G_SUBMENU                  -- OPEN region 1 "Model" (parent: main)
   15  " Model\n"                         OPTM_G_HEADLINE
   16  "\n"                               OPTM_G_LINE
   17  " PAL\n"                           OPTM_G_MACHINE_MODE + OPTM_G_STDSEL
   18  " NTSC\n"                          OPTM_G_MACHINE_MODE
   19  "\n"                               OPTM_G_LINE
   20  " Turbo mode\n"                    OPTM_G_HEADLINE
   21  "\n"                               OPTM_G_LINE
   22  " Off\n"                           OPTM_G_TURBO_MODE + OPTM_G_STDSEL
   23  " C128\n"                          OPTM_G_TURBO_MODE
   24  " Smart\n"                         OPTM_G_TURBO_MODE
   25  "\n"                               OPTM_G_LINE
   26  " Turbo speed\n"                   OPTM_G_HEADLINE
   27  " 2x\n"                            OPTM_G_TURBO_SPEED + OPTM_G_STDSEL
   28  " 3x\n"                            OPTM_G_TURBO_SPEED
   29  " 4x\n"                            OPTM_G_TURBO_SPEED
   30  "\n"                               OPTM_G_LINE
   31  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 1
   32  " Flip joystick ports\n"           OPTM_G_FLIP_JOYS + OPTM_G_SINGLESEL
   33  " HDMI: %s\n"                      OPTM_G_SUBMENU                  -- OPEN region 2 "HDMI" (parent: main)
   34  " HDMI Display Mode\n"             OPTM_G_HEADLINE
   35  "\n"                               OPTM_G_LINE
   36  " 16:9 720p 50 Hz (PAL)\n"         OPTM_G_HDMI_MODES_PAL  + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE,0)
   37  " 16:9 720p 60 Hz (NTSC)\n"        OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE,1)
   38  " 4:3 576p 50 Hz (PAL)\n"          OPTM_G_HDMI_MODES_PAL  + OPTM_DEP(OPTM_G_MACHINE_MODE,0)
   39  " 4:3 576p 60 Hz (NTSC)\n"         OPTM_G_HDMI_MODES_NTSC + OPTM_DEP(OPTM_G_MACHINE_MODE,1)
   40  " 5:4 576p 50 Hz (PAL)\n"          OPTM_G_HDMI_MODES_PAL  + OPTM_DEP(OPTM_G_MACHINE_MODE,0)
   41  " 5:4 576p 60 Hz (NTSC)\n"         OPTM_G_HDMI_MODES_NTSC + OPTM_DEP(OPTM_G_MACHINE_MODE,1)
   42  "\n"                               OPTM_G_LINE
   43  " HDMI: Flicker-free\n"            OPTM_G_HDMI_FF      + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE,0)
   44  " HDMI: Flicker-free\n"            OPTM_G_HDMI_FF_NTSC + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE,1)
   45  " HDMI: DVI (no sound)\n"          OPTM_G_HDMI_DVI + OPTM_G_SINGLESEL
   46  " HDMI: %s\n"                      OPTM_G_SUBMENU                  -- OPEN region 3 "HDMI Filter" (parent: region 2) -- #189's "HDMI: Scanlines" sub-submenu
   47  " HDMI Filter\n"                   OPTM_G_HEADLINE
   48  "\n"                               OPTM_G_LINE
   49  " No Filter\n"                     OPTM_G_HDMI_FILTER
   50  " Sharp Bilinear\n"                OPTM_G_HDMI_FILTER
   51  " Bicubic\n"                       OPTM_G_HDMI_FILTER
   52  " Smooth\n"                        OPTM_G_HDMI_FILTER
   53  " Lanczos\n"                       OPTM_G_HDMI_FILTER
   54  " Scanlines\n"                     OPTM_G_HDMI_FILTER + OPTM_G_STDSEL
   55  " CRT (S-Video)\n"                 OPTM_G_HDMI_FILTER
   56  " CRT (Composite)\n"               OPTM_G_HDMI_FILTER
   57  "\n"                               OPTM_G_LINE
   58  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 3
   59  " HDMI: Zoom-in\n"                 OPTM_G_HDMI_ZOOM + OPTM_G_SINGLESEL
   60  " HDMI: Raw 50.1 Hz\n"             OPTM_G_HDMI_RAW50 + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_MACHINE_MODE,0)
   61  "\n"                               OPTM_G_LINE
   62  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 2
   63  " VGA: %s\n"                       OPTM_G_SUBMENU                  -- OPEN region 4 "VGA" (parent: main)
   64  " VGA Display Mode\n"              OPTM_G_HEADLINE
   65  "\n"                               OPTM_G_LINE
   66  " Standard\n"                      OPTM_G_VGA_MODES + OPTM_G_STDSEL
   67  "\n"                               OPTM_G_LINE
   68  " Retro 15 kHz mode\n"             OPTM_G_TEXT
   69  "\n"                               OPTM_G_LINE
   70  " 15 kHz with HS/VS\n"             OPTM_G_VGA_MODES
   71  " 15 kHz with CSYNC\n"             OPTM_G_VGA_MODES
   72  "\n"                               OPTM_G_LINE
   73  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 4
   74  " SID: %s\n"                       OPTM_G_SUBMENU                  -- OPEN region 5 "SID" (parent: main)
   75  " SID Settings\n"                  OPTM_G_HEADLINE
   76  "\n"                               OPTM_G_LINE
   77  " Mono SID\n"                      OPTM_G_TEXT
   78  "\n"                               OPTM_G_LINE
   79  " 6581\n"                          OPTM_G_SID_SETUP
   80  " 8580\n"                          OPTM_G_SID_SETUP
   81  "\n"                               OPTM_G_LINE
   82  " Stereo SID\n"                    OPTM_G_TEXT
   83  "\n"                               OPTM_G_LINE
   84  " L: 6581 R: 6581\n"               OPTM_G_SID_SETUP
   85  " L: 6581 R: 8580\n"               OPTM_G_SID_SETUP
   86  " L: 8580 R: 6581\n"               OPTM_G_SID_SETUP
   87  " L: 8580 R: 8580\n"               OPTM_G_SID_SETUP + OPTM_G_STDSEL   -- default per the #189 sketch (today ships mono 6581 as default, config.vhd:557; final defaults are a #189 decision)
   88  "\n"                               OPTM_G_LINE
   89  " Right SID Port\n"                OPTM_G_TEXT
   90  "\n"                               OPTM_G_LINE
   91  " D420\n"                          OPTM_G_SID_PORT + OPTM_G_STDSEL
   92  " D500\n"                          OPTM_G_SID_PORT
   93  " DE00\n"                          OPTM_G_SID_PORT
   94  " DF00\n"                          OPTM_G_SID_PORT
   95  " Same as left SID port\n"         OPTM_G_SID_PORT
   96  "\n"                               OPTM_G_LINE
   97  " Audio improvements\n"            OPTM_G_IMPROVE_AUDIO + OPTM_G_SINGLESEL + OPTM_G_STDSEL
   98  "\n"                               OPTM_G_LINE
   99  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 5
  100  " IEC: Use hardware port\n"        OPTM_G_IEC + OPTM_G_SINGLESEL
  101  " Kernal: %s\n"                    OPTM_G_SUBMENU                  -- OPEN region 6 "Kernal" (parent: main)
  102  " Kernal Selection\n"              OPTM_G_HEADLINE
  103  "\n"                               OPTM_G_LINE
  104  " Standard\n"                      OPTM_G_KERNAL_MODES + OPTM_G_STDSEL
  105  " Games System\n"                  OPTM_G_KERNAL_MODES
  106  " Japanese\n"                      OPTM_G_KERNAL_MODES
  107  " JiffyDOS\n"                      OPTM_G_KERNAL_MODES
  108  "\n"                               OPTM_G_LINE
  109  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 6
  110  " Volume: %s\n"                    OPTM_G_SUBMENU                  -- OPEN region 7 "Volume" (parent: main)
  111  " Volume Control\n"                OPTM_G_HEADLINE
  112  "\n"                               OPTM_G_LINE
  113  " 100%\n"                          OPTM_G_VOLUME + OPTM_G_STDSEL
  114  " 90%\n"                           OPTM_G_VOLUME
  115  " 80%\n"                           OPTM_G_VOLUME
  116  " 70%\n"                           OPTM_G_VOLUME
  117  " 60%\n"                           OPTM_G_VOLUME
  118  " 50%\n"                           OPTM_G_VOLUME
  119  " 40%\n"                           OPTM_G_VOLUME
  120  " 30%\n"                           OPTM_G_VOLUME
  121  " 20%\n"                           OPTM_G_VOLUME
  122  " 10%\n"                           OPTM_G_VOLUME
  123  " 0%\n"                            OPTM_G_VOLUME
  124  "\n"                               OPTM_G_LINE
  125  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 7
  126  " Advanced Settings\n"             OPTM_G_SUBMENU                  -- OPEN region 8 "Advanced" (parent: main; no %s)
  127  " Advanced Settings\n"             OPTM_G_HEADLINE
  128  "\n"                               OPTM_G_LINE
  129  " RTC for GEOS\n"                  OPTM_G_RTC_GEOS + OPTM_G_SINGLESEL
  130  " OSM: %s\n"                       OPTM_G_SUBMENU                  -- OPEN region 9 "OSM Scaling" (parent: region 8)
  131  " OSM Scaling\n"                   OPTM_G_HEADLINE
  132  "\n"                               OPTM_G_LINE
  133  " 100%\n"                          OPTM_G_OSM_MODE + OPTM_G_STDSEL
  134  " 89%\n"                           OPTM_G_OSM_MODE
  135  " 80%\n"                           OPTM_G_OSM_MODE
  136  " 73%\n"                           OPTM_G_OSM_MODE
  137  " 67%\n"                           OPTM_G_OSM_MODE
  138  " 62%\n"                           OPTM_G_OSM_MODE
  139  " 57%\n"                           OPTM_G_OSM_MODE
  140  " 53%\n"                           OPTM_G_OSM_MODE
  141  " 50%\n"                           OPTM_G_OSM_MODE
  142  "\n"                               OPTM_G_LINE
  143  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 9
  144  " CIA: Use 8521 (C64C)\n"          OPTM_G_CIA_8521 + OPTM_G_SINGLESEL
  145  " VIC-II: %s\n"                    OPTM_G_SUBMENU                  -- OPEN region 10 "VIC-II" (parent: region 8)
  146  " VIC-II model\n"                  OPTM_G_HEADLINE
  147  "\n"                               OPTM_G_LINE
  148  " 656x/NMOS\n"                     OPTM_G_VICII_MODEL + OPTM_G_STDSEL
  149  " 856x/HMOS\n"                     OPTM_G_VICII_MODEL
  150  " 856x/old HMOS\n"                 OPTM_G_VICII_MODEL
  151  "\n"                               OPTM_G_LINE
  152  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 10
  153  "\n"                               OPTM_G_LINE
  154  " Back\n"                          OPTM_G_SUBMENU + OPTM_G_CLOSE   -- CLOSE region 8
  155  "\n"                               OPTM_G_LINE
  156  " About & Help\n"                  OPTM_G_ABOUT_HELP + OPTM_G_HELP
  157  "\n"                               OPTM_G_LINE
  158  " Close Menu\n"                    OPTM_G_CLOSE
```

### 6.1 The numbers

* `OPTM_SIZE` = **159** (≤ 254 ✓); 159 of 256 `osm_control` bits used (97 spare); config file grows to 159 bytes — regenerate with `M2M/tools/make_config.sh c64mega65-<version> auto` and bump `CORE_VERSION` (the #182 versioned-filename mechanism keeps old settings files harmless).
* 10 regions; region ids / parents / opener indices: 1 Model @14 (parent 0), 2 HDMI @33 (0), 3 HDMI-Filter @46 (**2**), 4 VGA @63 (0), 5 SID @74 (0), 6 Kernal @101 (0), 7 Volume @110 (0), 8 Advanced @126 (0), 9 OSM @130 (**8**), 10 VIC-II @145 (**8**). Maximum depth 2 → three menu levels.
* View heights (visible lines per level): main **27**; Model 17, HDMI 17, HDMI-Filter 12, VGA 10, SID 25, Kernal 8, Volume 15, Advanced 8, OSM 13, VIC-II 7. → `OPTM_DX` stays 25, **`OPTM_DY` = 27** (largest view = main); 27+2 = 29 ≤ CHARS_DY 33 — the menu fits the VGA OSM with four rows to spare, matching MJoergen's count in #189.
* strlen(OPTM_ITEMS) = 1278 label characters + 2×159 = **1596** (`\n` = two chars in VHDL). Heap budgets: see section 5.7 (total 2632 with DEPS → `MENU_HEAP_SIZE` 3072).
* `%s` slot order (= opener order): vdrive 0, then regions 1..10, then CRT/ROM 0..1, then scratch — 14 slots × 27 words = 378.

### 6.2 Group IDs and VHDL wiring

Existing group IDs keep their values (the asm callbacks in CORE/m2m-rom/m2m-rom.asm reference `C64_OPTM_G_LOAD_PRG`=3, `C64_OPTM_G_EXP_PORT`=4, `C64_OPTM_G_MOUNT_CRT`=5, `C64_OPTM_G_KERNAL_MODES`=12, `C64_OPTM_G_HDMI_FILTER`=16, `C64_OPTM_G_REU`=21 — all unchanged). Renamed: `OPTM_G_HDMI_MODES` → `OPTM_G_HDMI_MODES_PAL` (id 13 — no asm reference; `osm_const.asm` is regenerated by `make_rom.sh` anyway). New IDs (next free is 22, per config.vhd:514-534; id 2 stays reserved for drive 9): **22** `OPTM_G_MACHINE_MODE`, **23** `OPTM_G_TURBO_MODE`, **24** `OPTM_G_TURBO_SPEED`, **25** `OPTM_G_HDMI_MODES_NTSC`, **26** `OPTM_G_HDMI_FF_NTSC`, **27** `OPTM_G_HDMI_RAW50`, **28** `OPTM_G_VOLUME`, **29** `OPTM_G_RTC_GEOS`, **30** `OPTM_G_VICII_MODEL`.

Because the whole menu is reordered, **every `C_MENU_*` constant in CORE/vhdl/mega65.vhd (321-365) must be re-derived from the idx column above** (bit = flat index: e.g. `C_MENU_SIM_REU` 10, `C_MENU_FLIP_JOYS` 32, `C_MENU_HDMI_FF` 43, kernal 104..107, `C_MENU_HDMI_FLT_*` 49..56, VGA 66/70/71, and `C_MENU_OSM_SCALING` becomes `range 141 downto 133`). `CORE/m2m-rom/osm_const.asm` regenerates automatically from mega65.vhd + config.vhd via `make_rom.sh`. The genuinely **new** groups (MACHINE_MODE, TURBO_*, VOLUME, RTC_GEOS, VICII_MODEL, HDMI_MODES_NTSC, HDMI_FF_NTSC, HDMI_RAW50) get `C_MENU_*` bits now but their VHDL feature wiring is out of scope here — it belongs to #181 (NTSC), #85 (volume) and friends; until wired, the bits are simply unread, which is harmless and lets the menu structure ship first.

7. Compatibility contract (M2M V2.1.0)
--------------------------------------

| Combination | Behavior |
| ----------- | -------- |
| new firmware + any existing config.vhd | **Bit-identical.** The bracket parser reproduces the toggle parser on every well-formed depth-1 config (section 4.3); verified against the 59-config survey corpus and enforced by the emulator equivalence harness (section 10). No config.vhd edit, no probe, no re-synthesis semantics change. |
| new firmware + broken legacy config (unbalanced markers) | Was: silently scrambled menu (odd counts: boot fatal). Now: clean boot fatal `ERR_F_MENUSUB` with the offending line index. Survey found zero such configs; a functioning one cannot exist (section 4.2). |
| old firmware + nested config | Crashes (`OPTM_F_MENUIDX` halt or boot fatal) exactly as MJoergen observed — **unsupported**. Nesting requires re-vendoring M2M ≥ 2.1.0; cores vendor M2M as a directory, so this is always a deliberate author action. |
| config file / `make_config.sh` / `osm_const.asm` generation / init record / core callbacks | Unchanged. `OPTM_STRUCTSIZE` stays 19 (20 only with the DEPS feature, which is its own contract). `OSM_SEL_PRE/POST` still never fire for submenu lines, at any depth. |

8. Composition with path-to-OSM-dependencies.md
-----------------------------------------------

The two features are orthogonal by design but touch the same routines. Shared-touchpoint map and the required order of changes within each routine:

| Routine | This feature (nesting) | DEPS feature | Composition |
| ------- | ---------------------- | ------------ | ----------- |
| structure builder (menu.asm) | rewrites region/visibility computation (5.1) | adds one AND term to bit 15 | implement the new builder first; the dep predicate slots into the three `v := …` assignments as `v := v AND dep_ok(i)` — openers/closers are never dependent (deps restriction), so only the plain-line case actually changes |
| `_OPTM_RUN_SM_2` (menu.asm) | new stop condition (5.3) | must skip dep-hidden lines | combined rule given in 5.3 — **this fixes a gap in the DEPS doc**, which did not cover the enter scan |
| `%s` walk (options.asm) | skip child regions | skip dep-hidden lines | combined loop given in 5.4 |
| heap (HELP_MENU) | bigger menus | +1 record word, +`OPTM_SIZE` DEPS words | single `MENU_HEAP_SIZE` bump to 3072 covers both (5.7); note DEPS alone already overflows 1920 on today's menu — the DEPS doc's "re-check the heap" is hereby answered: it trips |
| config.vhd | no change | `OPTM_GTC` 17→30, `OPTM_DEP()`, selector 0x0313 | disjoint; nesting reserves nothing (0x0314+ and the 0x030B-0x030F gap stay free) |
| validation | balance scan (5.5) | five `ERR_F_DEP*` fatals | independent checks, both in `HELP_MENU_INIT` |

**Recommended implementation order: nesting first, DEPS second.** Nesting rewrites the builder that DEPS only amends; the V6 menu structure (#189) can ship and be tested without DEPS (variant lines temporarily all-visible), and DEPS's productive home — the PAL/NTSC mother in #189's Model submenu — only exists once the restructure has landed. The companion doc's decision 2 (an *oversized flat dev menu* for early dependency testing) predates this document and is superseded: DEPS development and testing happen directly on the V6 menu. The DEPS doc's section 7 already anticipated this feature and its claim holds: dependencies are a pure bit-15 predicate and carry over into the new builder verbatim.

The companion doc has been updated in lockstep (2026-06-12) with: a supersession note on its decision 2 and test-plan item 4 (oversized branch → V6 menu); the heap-formula `+1` correction and the definite answer that its `ERR_FATAL_HEAP1` guard *does* trip (→ `MENU_HEAP_SIZE` 3072, section 5.7 here); a new section 4.6 adopting the `_OPTM_RUN_SM_2` fix (the gap closed by section 5.3 here); a nested-config caveat in its compatibility matrix row "old firmware + new config.vhd"; and a forward note that its builder description refers to the pre-nesting code.

9. Restrictions and future evolution
------------------------------------

* **Openers cannot carry group ids, state, or dependency tags** (dispatch constraint, section 3.1; DEPS restriction). They may carry `OPTM_G_START` — but only **depth-1** openers (3 wild configs do exactly that).
* **`OPTM_G_START` must sit on a line visible at main level** — a region-0 line or a depth-1 opener; validated at boot (section 5.5). A nested opener is invisible at level 0, and a start cursor on an invisible line is a QNICE halt.
* **Bare `OPTM_G_CLOSE` ("Close Menu") lines belong at main level.** A 0x00FF line *inside* a region is a pre-existing trap (unchanged by this feature): selecting it closes the OSM and resets the remembered cursor to the `OPTM_G_START` line (options.asm:216-221) while `OPTM_MENULEVEL` stays inside the region — the next Help press fatals `OPTM_F_MENUIDX`. No known config does this.
* **A selectable group must live entirely inside one region** (5.8). Radio groups spanning a parent and its child region are authoring errors.
* **A `%s` opener needs a radio group of its own, outside child regions** (5.4) — or the core overrides via `SUBMENU_SUMMARY`.
* **One window geometry for all levels**: `OPTM_DY` covers the largest view; smaller views draw the existing closing line under their last item (menu.asm:525-547, works at any depth).
* Evolution options deliberately **not** in step 1: a "jump to main" closer variant (a second low-byte marker, e.g. 0xFE — the dispatch already treats any nonzero low byte as "leave", so this is encodable later without breaking 0xFF closers); per-level window sizes; dependent submenu labels (hide a whole submenu per machine mode — blocked by the DEPS step-1 restriction, and the natural next step after both features land).

10. Test plan
-------------

Per AGENTS.md section 7 ("verify QNICE code in the emulator — write testbeds, run them headlessly"); the builder and walks are pure functions over arrays, ideal for the `llist_test.asm` pattern:

1. **Builder testbed** (`menu_struct_test.asm` + python checker): feed synthetic GROUPS arrays and assert the full `(id, bit15)` array and visible count for every level. Testbed mechanics: build a minimal 19-word `OPT_MENU_DATA`-style init record and stub `OPTM_CLBK_FATAL` (record word 9) with a routine that prints R8/R9 via `SYSCALL(puts/puthex)` and exits — so fatal fixtures are *observable* instead of halting the emulator. Fixtures: today's flat C64 menu shape; adjacent regions (arcade pattern); region at flat index 0; region at the end; empty region (opener+closer adjacent); the #189 model (section 6) at all 11 levels; deep chain (10 levels); the fatals — unbalanced opener (R9 = last opener), closer-first (R9 = closer index), odd count, **`OPTM_G_START` on a nested opener** (must boot-fatal cleanly per 5.5, not `OPTM_F_MENUIDX`-halt at first open).
2. **Equivalence harness** (the no-breaking-changes gate): implement the *old* 3-pass algorithm alongside in the testbed **under renamed labels** (menu.asm cannot be `#include`d twice — label collisions; copy the routine into the testbed source); run both over every **legacy-shaped** fixture — including the real 110-entry GROUPS array extracted from today's config.vhd by script, and survey-derived patterns (back-to-back regions, `OPTM_G_START` on a depth-1 opener) — at every level; assert word-identical arrays and counts. (This was already done once in python during this research — old vs. new were word-identical over the real menu, 13 edge fixtures and 5000 randomized legacy configs — the QNICE testbed re-proves it against the *actual assembly*.)
3. **Leave-bookkeeping testbed**: after building at each level of the #189 model, assert `OPTM_LVL_PARENT`/`OPTM_LVL_OPENER` (e.g. level 9 → parent 8, opener 130) and simulate the leave path: level 10 → 8 → 0 with cursors 145, 126.
4. **Enter-scan and `%s`-walk testbeds**: `_OPTM_RUN_SM_2` stop positions for regions whose first content is a plain item / a child opener / only a closer; the walk over region 2 (must skip region 3 and report the selected display mode), region 3 (filter), region 8 (no radio group → `ERR_F_MENUNGRP` if it carried `%s`), plus dep-hidden combinations once DEPS lands.
5. **On-hardware script** (V6 feature branch, #189 menu): navigate main → Advanced → OSM Scaling and back twice (cursor lands on " OSM: %s" then " Advanced Settings"); Run/Stop pops one level at depth 2/1 and closes at main; Help-close inside the VIC-II sub-submenu, reopen → still inside, cursor preserved; mount a disk image, then enter a sub-submenu and verify the background `<Saving>` redraw keeps level and cursor; all `%s` summaries correct at all levels (incl. both " HDMI: %s" headings); settings save/restore across power cycle (159-byte config file); each authoring fatal provoked once (unbalanced, closer-first).
6. **Regression bookkeeping**: prepend a `Version 6 - TBD` section to `tests/README.md` (append-only convention) with these procedures.

11. Quick reference
-------------------

| What | Where |
| ---- | ----- |
| Author syntax | nest `OPTM_G_SUBMENU` … `OPTM_G_SUBMENU + OPTM_G_CLOSE` blocks; nothing new |
| Semantics | opener visible at parent level; contents+closer at own level; Back/Run-Stop pop one level (cursor → opener); ids in opener order; `OPTM_MENULEVEL` = region id, persists across OSM close |
| Builder | single pass, CPU-stack region stack, byproducts `OPTM_LVL_PARENT`/`OPTM_LVL_OPENER`; replaces menu.asm:1262-1362; array format unchanged |
| Firmware touchpoints | menu.asm: builder, `_OPTM_RUN_SM_L` (pop), `_OPTM_RUN_SM_1` (drop MAINSEL), `_OPTM_RUN_SM_2` (stop condition), comments; options.asm: `_HLP_S3` balance scan, `%s` walk child-skip, drop options.asm:1515; menu_vars.asm: −MAINSEL +LVL_PARENT +LVL_OPENER |
| Core-side (V6) | section 6 listing = source of truth; `OPTM_SIZE` 159, `OPTM_DY` 27, `MENU_HEAP_SIZE` 3072, new group ids 22-30, regenerate config file + `CORE_VERSION` bump |
| Fatals | `ERR_F_MENUSUB`/`OPTM_F_MENUSUB` now = unbalanced brackets (R9 = flat index of closer / last opener); new boot fatal: `OPTM_G_START` on a line invisible at main level; `ERR_F_MENUNGRP` unchanged (no radio group in `%s` region) |
| Compatibility | no probe, no config.vhd change; legacy configs bit-identical (survey: 59 configs/112 regions clean; gate: equivalence harness); nested configs require M2M ≥ 2.1.0 |
| RAM/ROM cost | +1 word variables, ≤ depth words transient stack, `MENU_HEAP_SIZE` +1152 (core-local), ~250-400 words ROM |
