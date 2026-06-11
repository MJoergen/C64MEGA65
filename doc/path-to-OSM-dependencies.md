Path to OSM dependencies
========================

Design document for **dependent menu entries** in the MiSTer2MEGA65 on-screen menu (OSM). Research result of June 2026; no code has been written yet.

* Testbed: C64MEGA65 **V6** (this repository, including its vendored `M2M/` folder).
* Framework: ships as a **minor** release **M2M V2.1.0** — existing M2M cores must keep working unchanged (see section 6).
* Related issues: [#181](https://github.com/MJoergen/C64MEGA65/issues/181) (NTSC mode), [#105](https://github.com/MJoergen/C64MEGA65/issues/105) (remove the PAL-only 720p 60 Hz entry), [#189](https://github.com/MJoergen/C64MEGA65/issues/189) (new V6 on-screen menu), [#229](https://github.com/MJoergen/C64MEGA65/issues/229) (smart dependencies — the feature specified here).

1. Motivation and use case
--------------------------

V6 brings an NTSC mode (#181). A PAL/NTSC switch in the OSM has consequences for other menu items: the HDMI output modes that make sense in PAL (720p 50 Hz, 576p, ...) differ from those that make sense in NTSC (720p 60 Hz, 480p, ...). So the items visible in the HDMI submenu must change depending on the PAL/NTSC selection — and the same pattern will recur (e.g. flicker-free, see section 5.3). The new V6 menu (#189) already sketches this: the "Model" submenu holds the PAL/NTSC selection and the HDMI submenu interleaves PAL and NTSC display modes, annotated "will use smart dependencies".

Today the OSM has no notion of conditional visibility: every line in `config.vhd`'s `OPTM_ITEMS` is unconditionally present (verified — see section 2). This document specifies a deliberately **simple, step-1** dependency system:

* The `config.vhd` author **unrolls** all variants as separate menu lines ("HDMI PAL mode 1", "HDMI NTSC mode 1", ...).
* Each unrolled line keeps its **own unique bit** in the 256-bit `osm_control` vector. Nothing changes for `mega65.vhd` (`C_MENU_*`), for `m2m-rom.asm`/`osm_const.asm`, or for the config-file format — the feature is *invisible* to every consumer of menu state. It boils down to a pure **visibility** question inside the firmware: when to *show* a line.
* A per-line dependency tag declares: *this line is visible if and only if a specific item of a specific "mother" group is currently selected.*

### Resolved design decisions

These were discussed and decided up front (sy2002, 2026-06-11):

1. **Explicit mother-item index** (`OPTM_DEP(mother, item)`), not positional round-robin unrolling. Rationale: variant sets may have *different sizes per mode* (PAL will plausibly offer three HDMI modes, NTSC three or four different ones), and positional inference silently mis-maps lines when the author reorders them, while explicit tags are order-independent and produce precise fatal errors.
2. Development happens on a feature branch that deliberately oversizes the menu (adds a PAL/NTSC group even though the main menu then no longer fits the VGA OSM height). This is reverted after testing; productive use waits for the planned multi-level-submenu enhancement and the #189 menu restructuring. *(Update 2026-06-12: superseded — the multi-level-submenu enhancement is now specified in [path-to-OSM-submenus.md](path-to-OSM-submenus.md) and lands **first**, so dependency development and testing happen directly on the V6/#189 menu; the oversized flat dev branch is obsolete, and test-plan item 4 in section 8 retargets accordingly.)*
3. **Single-select toggles can be mothers too**: `OPTM_DEP(G, 1)` = visible while the toggle is ON, `OPTM_DEP(G, 0)` = visible while it is OFF.
4. **Flicker-free exists twice** in the NTSC world: two lines, both labeled identically for the user, with different group IDs and different `osm_control` bits, routed apart on the VHDL side (section 5.3).
5. Naming: `OPTM_G_DEPENDENT` (flag) and `OPTM_DEP(mother, item)` (helper function).

2. Ground truth: how the OSM works today
----------------------------------------

Everything in this section was verified against the source on branch `develop` (June 2026); file:line references are anchors, not approximations. Readers familiar with the internals can skip to section 3.

### 2.1 The data model in config.vhd

* `OPTM_ITEMS` is one big `\n`-separated string; `OPTM_GROUPS` is the parallel per-line attribute array: `type OPTM_GTYPE is array (0 to OPTM_SIZE - 1) of integer range 0 to 2**OPTM_GTC - 1;` with `constant OPTM_GTC : natural := 17` (config.vhd:353, 387). The base type `integer` guarantees at least 31 value bits, so the range can grow far beyond 17 — this is the headroom the design uses.
* Current bit usage of an `OPTM_GROUPS` element — **all 17 bits are taken** (config.vhd:337-353):

  | Bits  | Meaning                                                        |
  | ----- | -------------------------------------------------------------- |
  | 7..0  | group ID (0 = `OPTM_G_TEXT`, 255 = `OPTM_G_CLOSE`, cores use 1..N) |
  | 8     | `OPTM_G_STDSEL` (default-selected)                             |
  | 9     | `OPTM_G_LINE` (separator)                                      |
  | 10    | `OPTM_G_START` (initial cursor position)                       |
  | 11    | mount-drive discriminator (part of `OPTM_G_MOUNT_DRV` = 0x08800) |
  | 12    | `OPTM_G_HEADLINE`                                              |
  | 13    | help discriminator (part of `OPTM_G_HELP` = 0x0A000)           |
  | 14    | submenu discriminator (part of `OPTM_G_SUBMENU` = 0x0C000)     |
  | 15    | `OPTM_G_SINGLESEL`                                             |
  | 16    | load-ROM discriminator (part of `OPTM_G_LOAD_ROM` = 0x18000)   |

* The C64 core uses group IDs 1..21 (config.vhd:514-534), `OPTM_SIZE = 110`, `OPTM_DX/DY = 25/31`.

### 2.2 The QNICE config device

QNICE reads `config.vhd` through 16-bit windows selected by `address_i(27 downto 12)` and decoded in the "DO NOT TOUCH" process (config.vhd:668-789). Facts that matter for this design:

* The `SEL_OPTM_GROUPS` window (0x0301) serves a **masked** 16-bit view of each element: `{b15, b14, 0, b12, 0000, b7..b0}` (config.vhd:771-774). Bits 8-11, 13, and 16 are stripped; each stripped flag has its **own derived one-bit-per-line window** (`SEL_OPTM_STDSEL` 0x0302, `_LINES` 0x0303, `_START` 0x0304, `_MOUNT_DRV` 0x0306, `_HELP` 0x0310, `_CRTROM` 0x0311). So "a new per-line attribute = a new derived window" is the established pattern, and high element bits are *invisible* to firmware that does not know the new window.
* **Any selector the decoder does not know returns `0xEEEE`** — the process pre-assigns `data_o <= x"EEEE"` (config.vhd:736) and ends with `when others => null` (config.vhd:785). This is the hook for feature detection (section 3.4); today no firmware↔config.vhd version handshake exists at all.

### 2.3 Firmware: menu data, and the visibility layer that already exists

* On every menu open, `HELP_MENU` (M2M/rom/options.asm:21-236) copies items/groups/lines onto a 1920-word heap (`MENU_HEAP_SIZE`, CORE/m2m-rom/m2m-rom.asm:576) and builds the per-line selected-state array `OPTM_IR_STDSEL` from the live hardware bits. The menu library `menu.asm` consumes a 19-word init record (`OPTM_STRUCTSIZE = 19`, menu.asm:173) with function pointers, callbacks and the five data pointers.
* **The key discovery: a per-line visibility mask already exists.** `_OPTM_STRUCT` (menu.asm:1262-1362) rebuilds — on every `OPTM_SHOW` and every `OPTM_RUN` — a per-line array on the stack: bits 0..14 = submenu number of the line, **bit 15 = "visible at the current menu level"**. Every consumer already honors it: drawing skips bit-15-clear lines with a skip counter (`OPT_PRINTSTR`, options.asm:840-841; OPTM_SHOW menu.asm:303-327, 474-547), cursor movement skips them (menu.asm:649-650, 697-698), the flat-index→screen-row translator counts only visible lines (`_OPTM_R_F2M`, menu.asm:1364-1424), and `OPTM_SET` tolerates "line not in current view" via carry (menu.asm:1162). Today bit 15 is derived *exclusively* from submenu membership vs. `OPTM_MENULEVEL`. Dependencies therefore reduce to **one additional AND term in a single producer**, not a new subsystem.
* Redraw granularity: a toggle repaints only the marker glyphs (menu.asm:832-901); a (sub)menu level change does restore-SP → full `OPTM_SHOW` → restart `OPTM_RUN` (menu.asm:997-1003) — the exact pattern a visibility change needs. After every toggle, `OPTM_CB_SEL` re-serializes the whole per-line state into the hardware register in real time (options.asm:1228-1259).
* The `%s` submenu summary (`OPTM_CB_SHOW`, options.asm:1313-1519) walks forward from the submenu heading and returns the label of the **first selected radio item** (options.asm:1356-1379). It has **no visibility input** — a selected-but-hidden line *would* leak into the summary. This must be fixed as part of this feature (section 4.4).

### 2.4 Live state, persistence, limits

* The 256-bit menu state is the hardware register `control_m_o` (M2M/vhdl/QNICE/qnice.vhd:72, written 16 bits at a time via `M2M$CFM_ADDR`/`M2M$CFM_DATA` 0xFFF2/0xFFF3). Bit *i* = menu line *i* is a strict firmware convention (sysdef.asm:183-187). It reaches the core raw (`qnice_osm_control_i`) and CDC'd (`main_osm_control_i`); **nothing in the M2M framework VHDL interprets it positionally** — positional consumers are only `mega65.vhd`'s `C_MENU_*` constants and the auto-generated `osm_const.asm`.
* Config file on SD: exactly `OPTM_SIZE` bytes, one byte (0/1) per line, byte *n* = bit *n*; first byte 0xFF = virgin file; name is version-suffixed (`CFG_FILE = "/c64/c64mega65-" & CORE_VERSION`, the #182 mechanism). Hidden lines keeping their bits means the file format is untouched by this feature.
* Limits: `OPTM_SIZE` max 254 (options.asm:274-281) within the 256-bit vector (146 bits spare today); the C64 main menu currently fills the 33-character OSM height **exactly** (31 visible lines + 2 frame rows = `CHARS_DY`), i.e. zero slack — which is why the dev feature branch deliberately accepts an oversized menu (decision 2).

3. The design
-------------

### 3.1 Authoring model: unroll the variants

If a "mother" group has N selectable items, then every menu line whose meaning depends on that selection is written N times (or fewer — variants may be asymmetric), each tagged with the mother item it belongs to. Visually, only the lines belonging to the *currently selected* mother item are shown; the menu compacts around the hidden lines (the existing skip-counter rendering does this for free).

Two rules make the system predictable:

* **Each variant set is its own group.** "HDMI modes (PAL)" and "HDMI modes (NTSC)" are *separate* radio groups with separate group IDs. Each keeps its own exactly-one-selected invariant and its own bits — so switching PAL → NTSC → PAL **remembers the previous PAL choice for free**, because hidden lines keep their state (and their byte in the config file).
* **The VHDL side multiplexes explicitly.** `mega65.vhd` sees unique `C_MENU_*` bits for every unrolled line and decides itself which set to honor (e.g. `if NTSC then decode NTSC bits else decode PAL bits`). No hidden re-interpretation of bits, ever.

### 3.2 config.vhd syntax

`OPTM_GTC` grows from 17 to **30** (the maximum: `2**31` would overflow VHDL's `integer` in the range expression). The 13 new bits encode the dependency:

| Bits   | Meaning                                              |
| ------ | ---------------------------------------------------- |
| 16..0  | unchanged (group ID + existing flags, section 2.1)   |
| 24..17 | mother group ID (1..254)                             |
| 28..25 | mother item index (0..15)                            |
| 29     | `OPTM_G_DEPENDENT` flag                              |

```vhdl
constant OPTM_GTC : natural := 30;   -- was 17

-- this line is only visible if item <item> of group <mother> is selected
constant OPTM_G_DEPENDENT : natural := 16#2000_0000#;

function OPTM_DEP(mother : natural; item : natural) return natural is
begin
   return OPTM_G_DEPENDENT + (item * 16#0200_0000#) + (mother * 16#0002_0000#);
end function OPTM_DEP;
```

`OPTM_DEP` lives next to the existing helper functions in config.vhd (`getGenConf`, `getDXDY`, `str2data`). Authoring then looks like this (the syntax envisioned at the start of this research, with the explicit item index added):

```vhdl
-- inside OPTM_GROUPS, parallel to the OPTM_ITEMS lines:
OPTM_G_HDMI_MODES_PAL  + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0),  -- "16:9 720p 50 Hz"
OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1),  -- "16:9 720p 60 Hz"
OPTM_G_HDMI_MODES_PAL  +                 OPTM_DEP(OPTM_G_MACHINE_MODE, 0),  -- "4:3 576p 50 Hz"
OPTM_G_HDMI_MODES_NTSC +                 OPTM_DEP(OPTM_G_MACHINE_MODE, 1),  -- "4:3 480p 59.94 Hz"
```

Because the existing `OPTM_G_*` values are untouched, raising `OPTM_GTC` changes nothing for a menu that uses no dependencies — the constant arrays are bit-identical in their low 17 bits.

### 3.3 Semantics

* **Visibility rule.** A line tagged `OPTM_DEP(G, K)` is visible iff:
  * *G is a radio (multi-select) group:* the K-th member of G (counting G's lines top-down in flat `config.vhd` order, starting at 0) is currently selected. Since exactly one member of a radio group is always selected, exactly one item index "wins" at any time.
  * *G is a single-select toggle* (a line carrying `OPTM_G_SINGLESEL`, identified by its unique group ID): `K = 1` means visible while the toggle is ON, `K = 0` means visible while it is OFF. This covers patterns like "show tuning options only while feature X is enabled" and provides negation where it is actually needed.
* **Untagged lines are always visible** (dependency field = 0). Any line type may carry a dependency — including group-0 lines (`OPTM_G_TEXT` labels, `OPTM_G_LINE` separators, `OPTM_G_HEADLINE` headlines), so whole visual blocks can appear/disappear together. Exceptions (step-1 restrictions, fatal at boot): lines flagged `OPTM_G_MOUNT_DRV`, `OPTM_G_LOAD_ROM`, `OPTM_G_START`, `OPTM_G_SUBMENU`, `OPTM_G_HELP`, and the `OPTM_G_CLOSE` line must not be dependent, and a mother's own lines must not be dependent (no dependency chains). See section 7 for why and for the evolution path.
* **Uniformity within a group.** All members of one selectable group must carry the *same* dependency word (including "none"). Otherwise the exactly-one-selected invariant could point at a hidden line while visible members show no selection. This is validated at boot (section 4.5).
* **Cross-(sub)menu dependencies are allowed and expected.** The predicate reads global menu state, so the mother can live in the "Model" submenu while the dependents live in the "HDMI" submenu (#189 does exactly this). If mother and dependents share the same view, the menu re-renders in real time (section 4.3).
* **State and persistence are visibility-blind.** Hidden lines keep their `osm_control` bits, their saved config-file bytes, and their `OPTM_G_STDSEL` defaults. The VHDL side must simply ignore bits of variant groups that are not active (section 3.1, second rule).
* **Menu height.** `OPTM_DY` stays a hand-sized constant. The author sizes it for the *largest* variant; smaller variants leave blank rows at the bottom inside the frame (same behavior as today's short submenus). If stable optics matter, keep variant sets the same size per mode — with explicit indices this is the author's choice, not a system requirement.

### 3.4 The new selector window and feature detection

A new derived window, following the established pattern of `SEL_OPTM_STDSEL` & friends:

```vhdl
constant SEL_OPTM_DEPS : std_logic_vector(15 downto 0) := x"0313";
```

* Addresses `0 .. OPTM_SIZE-1` serve one 16-bit word per line: bits 7..0 = mother group ID (element bits 24..17), bits 11..8 = mother item index (element bits 28..25), bit 12 = dependency flag (element bit 29), bits 15..13 = `"000"`.
* Address `0xFFF` serves the **magic word `x"1DEF"`** ("DEPendency Format 1" — out-of-band, since per-line words end at index 253 max).

```vhdl
when SEL_OPTM_DEPS =>
   if index = 16#FFF# then
      data_o <= x"1DEF";
   else
      data_o <= "000" &
                std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(29)) &
                std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(28 downto 17));
   end if;
```

**Feature detection:** at menu initialization the firmware reads `SEL_OPTM_DEPS[0xFFF]` once. Exactly `x"1DEF"` enables the feature; anything else (an old config.vhd returns `0xEEEE` via the unknown-selector default, config.vhd:736) disables it and the firmware behaves bit-identically to today. This doubles as a format version for future extensions (`x"2DEF"`, ...). The firmware logs the outcome to the serial console either way.

4. Firmware implementation inventory
------------------------------------

All locations verified against the current source. The dependency *resolution and validation* logic should live in a new standalone module `M2M/rom/optm_deps.asm` so it can be emulator-tested in isolation (section 8); the integration points below stay thin.

### 4.1 Reading and resolving (HELP_MENU / HELP_MENU_INIT, options.asm)

* `HELP_MENU` copies one more per-line array onto the menu heap, after the LINES array (options.asm:120-127 is the template): the DEPS words (`OPTM_SIZE` words; zero-filled when feature detection failed). Heap budget grows from `19 + strlen(OPTM_ITEMS)+1 + 3*OPTM_SIZE + 1` to `20 + strlen+1 + 4*OPTM_SIZE + 1` words (the trailing +1 is added by the check itself, options.asm:134) — and the `ERR_FATAL_HEAP1` guard (options.asm:136-145) **does** trip `MENU_HEAP_SIZE` (1920, a core-local `.EQU` in CORE/m2m-rom/m2m-rom.asm:576): already on today's 110-line menu the DEPS array pushes the total to 1682 + 270 (`%s` slots) = 1952. Resolution: `MENU_HEAP_SIZE := 3072`, sized for the V6 menu with both OSM features — see [path-to-OSM-submenus.md](path-to-OSM-submenus.md) section 5.7.
* **Resolution pass** (once per menu open, after the copy): each nonzero DEPS word is rewritten *in place* into resolved form — bits 7..0 = flat line index of the **controlling line**, bit 8 = **expected state** (0 or 1), bit 15 = valid. For a radio mother, the controlling line is the K-th member of group G (scan the heap GROUPS array for low-byte == G) and the expected state is 1; for a single-select mother, the controlling line is the mother line itself and the expected state is K. After this pass, the runtime visibility test is two loads and a compare: `visible(i) = (OPTM_IR_STDSEL[ctl(i)] == expected(i))`.
* The init record grows by one field: `OPTM_IR_DEPS = 19` (pointer to the resolved array; 0 = feature off), `OPTM_STRUCTSIZE = 20` (menu.asm:173). The record is internal between options.asm and menu.asm — cores never build it — so this is not an API break.

### 4.2 Visibility evaluation (_OPTM_STRUCT, menu.asm)

`_OPTM_STRUCT` (menu.asm:1262-1362) gains one AND term when computing bit 15 of each line's struct word: `bit15 = (visible at current menu level) AND (dependency satisfied)`, with "dependency satisfied" = the two-load compare above (or trivially true when `OPTM_IR_DEPS` is 0 or the line's word is 0). Every consumer — drawing, skip counters, cursor movement, `_OPTM_R_F2M`, `OPTM_SET`'s out-of-view tolerance — works unchanged, because they all already go through bit 15 (section 2.3). This is the entire core of the feature.

### 4.3 Real-time redraw when a mother changes

When the user toggles a mother while dependents are in the same view, the menu must re-render immediately:

* `OPTM_CB_SEL` (options.asm:1149-1276) already runs on every selection change and updates the hardware in real time. It additionally checks whether any resolved DEPS entry's controlling line is one of the lines whose state just changed (a radio flip changes two lines — the deselected and the selected member; a toggle changes one). An O(`OPTM_SIZE`) scan of the resolved array suffices.
* New internal return convention: `OPTM_CLBK_SEL` returns "menu structure changed" in R8. On that flag, `OPTM_RUN` executes the existing submenu-switch sequence — restore SP, full `OPTM_SHOW`, restart `OPTM_RUN` (the `_OPTM_RUN_SM_4` pattern, menu.asm:997-1003) — which rebuilds `_OPTM_STRUCT` with the new visibility and recomputes all screen rows. Again internal between options.asm and menu.asm; core callbacks (`OSM_SEL_PRE/POST`) keep their conventions.
* **Cursor safety falls out structurally:** the cursor sits on the mother line the user just toggled, and mothers cannot be dependent (no chains), so the cursor's line is still visible after the rebuild — the fatal-on-hidden-cursor path (`OPTM_F_MENUIDX` via `_OPTM_R_F2M` carry, menu.asm:614-617) cannot fire. `OPTM_CUR_SEL` is kept across the restart, exactly as the submenu path does.
* Known step-1 limitation: `OPTM_SET` calls from background handlers (e.g. mounting) that change a *mother* group while the menu is open would leave the view stale until the next redraw. No current core does this; if it becomes real, hook the same structure-changed redraw into the existing background-redraw path (`OPT_MENU_GETKEY`, options.asm:969-980).

### 4.4 The %s submenu summary must skip hidden lines

Confirmed leak (section 2.3): the default summary walk would report a selected-but-hidden line — e.g. with both `HDMI_MODES_PAL` and `HDMI_MODES_NTSC` having a selected member, the heading would always show whichever comes first in flat order. Fix: in `_OPTM_CBS_A.._OPTM_CBS_C` (options.asm:1356-1379), skip lines whose resolved dependency predicate is false, symmetric to the existing "not selected → continue" branch at options.asm:1379. The resolved DEPS array is on the heap and `OPTM_IR_STDSEL` is live, so the check is the same two-load compare as in `_OPTM_STRUCT`. (Note: `OPTM_CB_SHOW` runs outside `OPTM_RUN`'s stack frame, which is exactly why the heap copy — not the stack struct — must be the data source here.)

### 4.5 Validation: new fatal errors at boot

Checked once in `HELP_MENU_INIT`, where the existing config sanity fatals live (`ERR_F_MENUSIZE` etc., strings.asm:167-180). All of these are authoring errors in config.vhd, hence fatals, not warnings:

| Fatal             | Condition                                                                                                   |
| ----------------- | ----------------------------------------------------------------------------------------------------------- |
| `ERR_F_DEPMOTHER` | dependency references group ID 0 or 255, or a group ID with no member lines                                  |
| `ERR_F_DEPIDX`    | radio mother: item index ≥ member count; single-select mother: item index > 1                                |
| `ERR_F_DEPMIX`    | members of one selectable group carry differing dependency words (including some-tagged/some-not)            |
| `ERR_F_DEPCHAIN`  | a line of a mother group is itself dependent                                                                 |
| `ERR_F_DEPSPECIAL`| dependency on a line flagged `MOUNT_DRV`, `LOAD_ROM`, `START`, `SUBMENU`, `HELP`, or on the `CLOSE` line     |

A failed feature probe (section 3.4) is **not** an error — the feature is silently (well, serial-logged) off.

### 4.6 The submenu enter scan must skip hidden lines

Found during the multi-level-submenu research (2026-06-12, gap in the original version of this document): `_OPTM_RUN_SM_2` (menu.asm:981-994), which parks the cursor on the first selectable line after entering a submenu, consults only the group words — never visibility. Entering a submenu whose first selectable line is dep-hidden (exactly the HDMI submenu of section 5.1 while NTSC is selected) would park the cursor on a hidden line and halt with `OPTM_F_MENUIDX` on the redraw restart. Fix: the scan additionally skips lines whose resolved dependency predicate is false (the same two-load compare as everywhere else); a region's closer can never be dependent (section 3.3), so the scan always terminates on a visible line. The combined stop condition (this skip plus the nested-region rule) is specified in [path-to-OSM-submenus.md](path-to-OSM-submenus.md) section 5.3 — implement it once, there.

5. Core-side usage: the C64 V6 PAL/NTSC example
-----------------------------------------------

### 5.1 Menu sketch (dev feature branch)

For testing the mechanism, the feature branch adds a machine-mode radio group (next free group ID is 22) and unrolls the HDMI mode group; the main menu temporarily exceeds the VGA OSM height (decision 2 — accepted and reverted later; the productive layout is #189's "Model" submenu):

```
 Machine\n                      OPTM_G_TEXT + OPTM_G_HEADLINE
 PAL\n                          OPTM_G_MACHINE_MODE + OPTM_G_STDSEL          -- item 0
 NTSC\n                         OPTM_G_MACHINE_MODE                          -- item 1
 ...
 (inside the HDMI submenu:)
 16:9 720p 50 Hz\n              OPTM_G_HDMI_MODES_PAL  + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
 4:3 576p 50 Hz\n               OPTM_G_HDMI_MODES_PAL                  + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
 5:4 576p 50 Hz\n               OPTM_G_HDMI_MODES_PAL                  + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
 16:9 720p 60 Hz\n              OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)
 4:3 480p 59.94 Hz\n            OPTM_G_HDMI_MODES_NTSC                 + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)
 Flicker-free\n                 OPTM_G_HDMI_FF      + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
 Flicker-free\n                 OPTM_G_HDMI_FF_NTSC + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)
```

Notes:

* The PAL set has three entries because the PAL-only "16:9 720p 60 Hz" line is removed in V6 anyway (#105) — 60 Hz modes belong to NTSC. The NTSC set lists modes that are **already fully plumbed** through `framework.vhd:475-481` / `digital_pipeline.vhd:179-185` but unreachable from today's menu: `C_VIDEO_HDMI_16_9_60` (1280x720@60), `C_VIDEO_HDMI_720_5994` (720x480@59.94, the classic NTSC 480p), and optionally `C_VIDEO_HDMI_640_60` / `C_VIDEO_SVGA_800_60`. The sets are deliberately different sizes — this is what the explicit item index buys (decision 1). #189's labels ("4:3 576p 60 Hz" etc.) are the eventual user-facing wording; the constants above name what the modes technically are.
* New lines are **appended** behind the existing 110 lines on the dev branch, so no existing `C_MENU_*` value shifts; the V6 release reorders the menu anyway (#189), which is covered by the version-suffixed config-file name.

### 5.2 mega65.vhd

* New `C_MENU_*` constants for every new line — `osm_const.asm` picks them up automatically (it is generated by `make_rom.sh` from `mega65.vhd` + `config.vhd`).
* `c64_ntsc` (today hardcoded `'0'`, mega65.vhd:495) becomes `main_osm_control_i(C_MENU_MACHINE_NTSC)`.
* The HDMI mode decode (mega65.vhd:771-774) becomes a two-branch mux: when the NTSC bit is set, a priority chain over the `HDMI_MODES_NTSC` bits; otherwise the existing chain over the PAL bits. Bits of the inactive group are simply ignored — the "explicit multiplex" rule from section 3.1.
* Out of scope here but adjacent (tracked in #181): `CORE_CLK_SPEED_NTSC = 32_727_264` is an existing `@TODO` (globals.vhd:48), `clk.vhd`'s `core_speed_i` already documents `2 = NTSC` (mega65.vhd:422), and the 1541-drift compensation (main.vhd:1352++) and CIA TOD (`clk32_speed`) depend on the exact clock value.

### 5.3 Flicker-free in NTSC (decision 4)

NTSC needs the flicker-free mechanism just like PAL: the NTSC C64 core rate (~59.8 Hz) does not equal the exact HDMI 60.000/59.94 Hz, the same class of mismatch as PAL's 50.125 vs. 50.000 Hz. So `clk.vhd` will eventually need an NTSC clock pair analogous to the PAL pair (50.124/49.999). For the menu this means **two lines, both labeled "Flicker-free"**: group `OPTM_G_HDMI_FF` (existing, bit 63) visible in PAL, new group `OPTM_G_HDMI_FF_NTSC` visible in NTSC. The user sees one stable-looking toggle; the VHDL side routes the two bits into the respective clock-switching logic (`hr_core_speed`, mega65.vhd:438-451). The per-mode state retention even becomes a feature: flicker-free can default ON in PAL and (say) OFF in NTSC, and user overrides are remembered per mode.

6. Compatibility contract (M2M V2.1.0)
--------------------------------------

The framework ships as a minor release; this is the complete compatibility matrix:

| Combination                            | Behavior                                                                                                                                                |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| new firmware + old config.vhd          | Feature probe reads `0xEEEE` (unknown-selector default, present in the "DO NOT TOUCH" section of every M2M core) instead of `x"1DEF"` → feature off → **bit-identical behavior to today**. This is the case every other M2M core hits when it upgrades the M2M folder without touching its config.vhd. |
| old firmware + new config.vhd          | Old firmware never reads selector 0x0313, and `SEL_OPTM_GROUPS` masks the element to bits {15,14,12,7..0} — the dependency bits are invisible. All unrolled variants simply render as always-visible lines. Degraded optics, nothing breaks. *Caveat for the combined V6 core: the V6 config.vhd is also nested (multi-level submenus), and nested configs crash old firmware — see path-to-OSM-submenus.md section 7. The graceful degradation described here applies to the dependency tags alone.* |
| new firmware + new config.vhd, no deps | `OPTM_GTC = 30` with unchanged `OPTM_G_*` values is bit-identical in the low 17 bits; the probe succeeds, the DEPS array is all zeros, every line is visible. |

Further compatibility properties:

* **Config-file format unchanged** (one byte per line, exactly `OPTM_SIZE` bytes, version-suffixed name). `make_config.sh` works unchanged.
* **No core-facing API changes.** The init-record extension (`OPTM_IR_DEPS`) and the `OPTM_CLBK_SEL` return convention are internal between `options.asm` and `menu.asm`, which ship together in M2M. Core callbacks (`OSM_SEL_PRE/POST`, `SUBMENU_SUMMARY`, ...) keep their signatures.
* **Template care:** the M2M template config.vhd must extract the dependency bits with an explicit width (bits 29/28..17 of `to_unsigned(..., OPTM_GTC)` with `OPTM_GTC = 30`). A core that keeps `OPTM_GTC = 17` must not get the new `SEL_OPTM_DEPS` decode pasted in (indexing bit 29 of a 17-bit vector is a compile error) — the template ships both changes as one unit: `OPTM_GTC := 30` together with the new selector arm.

7. Step-1 restrictions and future evolution
-------------------------------------------

Deliberate simplifications, each with its relaxation path:

* **No dependency chains** (mothers must not be dependent). Keeps visibility a single two-load predicate and guarantees cursor safety on mother toggles (section 4.3). Relaxation: effective visibility = own predicate AND controller's effective visibility, computed in dependency-depth order with a cycle check at boot — a contained extension of the resolution pass.
* **No dependent special lines** (`MOUNT_DRV`, `LOAD_ROM`, `START`, `SUBMENU`, `HELP`, `CLOSE`). The ordinal scans for drives/ROMs/help are actually visibility-blind (they scan the flat one-hot windows, vdrives.asm:355-372 etc.), so hiding would not even renumber anything — but the UX interactions (e.g. mounting UI on a hidden drive line, the submenu-label special case in `_OPTM_STRUCT` pass 3, menu.asm:1322-1359) are untested territory. Forbid now, relax case by case. Dependent **submenu headings** (hide a whole submenu per mode) are the most attractive relaxation and are structurally just another line — they only collide with the pass-3 label logic, which is where the work would happen.
* **Multi-level submenus** (planned before productive use of this feature, level count still open — fixed "max 2" vs. arbitrary N, see #189's sub-submenus): no interaction by design. Visibility is a pure per-line predicate over (resolved DEPS word, live selected-state array), evaluated in `_OPTM_STRUCT`, which encodes submenu membership in bits 0..14 *separately* from bit 15. A multi-level enhancement changes the region/level logic (bits 0..14 and `OPTM_MENULEVEL` handling); the dependency AND term on bit 15 is orthogonal and carries over verbatim. *(Update 2026-06-12: that enhancement is now specified in [path-to-OSM-submenus.md](path-to-OSM-submenus.md) — unlimited depth, no probe — and lands **before** this feature. The prediction held: the AND term integrates into the plain-line `v :=` case of its new single-pass builder. Note that the `_OPTM_STRUCT` description and anchors in section 4.2 above refer to the pre-nesting three-pass code that the new builder replaces; see the composition table in that document, section 8.)*
* **Mother item count ≤ 16** (4 index bits). No real-world group comes close (largest C64 group today: 11 members, Volume in #189); the encoding has no spare room for more without going beyond `OPTM_GTC = 30`.

8. Test plan
------------

Per this repo's convention (AGENTS.md section 7: "verify QNICE code in the emulator — write testbeds, run them headlessly"):

1. **Emulator testbed for the resolution + validation module.** Put resolution and validation into `M2M/rom/optm_deps.asm` (section 4) precisely so a standalone testbed `optm_deps_test.asm` (style: `llist_test.asm`) can feed synthetic GROUPS/DEPS arrays and print the resolved table and the fatal decisions via `SYSCALL(puts/puthex)`; a python checker asserts: correct controlling-line/expected-state resolution for radio and single-select mothers, and every fatal from section 4.5 firing on a crafted bad input (dangling mother, index overflow, mixed group, chain, special line).
2. **Visibility-predicate testbed.** Drive `_OPTM_STRUCT` with a stubbed init record (the function pointers can point to no-op/logging stubs; `_OPTM_STRUCT` itself only consumes the record and `OPTM_MENULEVEL`) and assert the bit-15 vector for combinations of menu level × mother states, including the compaction counts that `_OPTM_R_F2M` derives.
3. **Feature-probe test.** Run the firmware against a config device that answers `0xEEEE` on selector 0x0313 (i.e. an unmodified config.vhd) and assert the feature stays off and behavior is unchanged — this is the regression proxy for "other M2M cores keep working".
4. **On-hardware feature branch** (decision 2, as updated: the V6/#189 menu with multi-level submenus already in place — no oversized flat branch); manual test script: PAL↔NTSC switching with the HDMI submenu open (real-time reflow, cursor stays on the mother), `%s` summary correctness on the HDMI heading in both modes, per-mode memory of the HDMI selection and the two flicker-free toggles across mode switches and across power cycles (config-file save/restore), and a deliberately corrupted dependency in config.vhd per fatal class.
5. **Regression suite:** the V2.15-style test list in `tests/` gets a new `Version X - TBD` section on top (append-only convention) with these procedures once implementation starts.

9. Quick reference
------------------

| What                       | Where                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------- |
| Author syntax              | `OPTM_G_<my_group> [+ flags] + OPTM_DEP(<mother group>, <item index>)` in `OPTM_GROUPS`   |
| Helper + flag              | `OPTM_DEP(m, k) = 16#2000_0000# + k*16#0200_0000# + m*16#0002_0000#`; `OPTM_G_DEPENDENT = 16#2000_0000#`; `OPTM_GTC = 30` |
| Visibility rule            | radio mother: visible iff member *k* selected; single-select mother: visible iff state == *k* |
| New selector               | `SEL_OPTM_DEPS = x"0313"`; per-line `{000, flag, item(4), mother(8)}`; magic `x"1DEF"` at 0xFFF |
| Feature probe              | firmware reads 0x0313[0xFFF]; `x"1DEF"` = on, anything else (old cores: `0xEEEE`) = off    |
| Firmware touchpoints       | new `optm_deps.asm` (resolve+validate); options.asm `HELP_MENU`/`HELP_MENU_INIT` (heap copy, probe), `OPTM_CB_SEL` (structure-changed flag), `OPTM_CB_SHOW` `_OPTM_CBS_C` (%s skip); menu.asm `_OPTM_STRUCT` (AND term), `OPTM_RUN` (redraw-restart on flag), init record `OPTM_IR_DEPS=19` |
| Fatals                     | `ERR_F_DEPMOTHER`, `ERR_F_DEPIDX`, `ERR_F_DEPMIX`, `ERR_F_DEPCHAIN`, `ERR_F_DEPSPECIAL`   |
| Step-1 restrictions        | no chains; no deps on MOUNT_DRV/LOAD_ROM/START/SUBMENU/HELP/CLOSE lines; mother ≤ 16 items |
