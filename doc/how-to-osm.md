# How to build an On-Screen Menu (OSM) in `config.vhd`

This guide explains, from the ground up, how the **On-Screen Menu (OSM)** of a
MiSTer2MEGA65 (M2M) core is defined. The OSM is the overlay menu the user opens
with the <kbd>Help</kbd> key to mount disk images, switch options, load ROMs and
so on. **You author the whole menu in a single VHDL file, `config.vhd`** — no
firmware programming required.

> **Scope of this guide.** We focus on *defining the menu* in `config.vhd`: the
> menu text, the item types, submenus, the `%s` placeholder, conditional
> (“smart”) visibility, and how a menu choice reaches your core. We deliberately
> do **not** cover how the QNICE “Shell” firmware draws the menu, nor the welcome
> & help *screens*, nor the rest of `config.vhd` (clocks, resets, ascal, …).
> Those are separate topics. Everything here is real and matches the shipped
> C64 core, which we use as the running example.

---

## 1. The mental model: two parallel arrays

The single most important idea: **a menu is two arrays that run in lockstep.**

* **`OPTM_ITEMS`** — one big string. Every menu line is separated by a `\n`. This
  is *what the user sees*.
* **`OPTM_GROUPS`** — an array with **one entry per menu line**. Each entry is a
  number that encodes *what that line is* (a headline? a toggle? a submenu? …).
  This is the *meaning* behind each line.

Line *i* of `OPTM_ITEMS` is described by entry *i* of `OPTM_GROUPS`. They must
have the **same number of lines/entries**, and that number is `OPTM_SIZE`.

```
        OPTM_ITEMS (text)              OPTM_GROUPS (meaning)
  line 0 " C64 for MEGA65\n"     <->   OPTM_G_HEADLINE
  line 1 "\n"                    <->   OPTM_G_LINE
  line 2 " 8:%s\n"              <->   OPTM_G_MOUNT_8 + OPTM_G_MOUNT_DRV + OPTM_G_START
  line 3 " PRG:%s\n"            <->   OPTM_G_LOAD_PRG + OPTM_G_LOAD_ROM
  ...                                 ...
```

(Don’t worry about the exact constant names yet — every one is explained in the
sections that follow. For now just see that each line of *text* on the left pairs
with one entry of *meaning* on the right.)

That is the entire data model. Everything else in this guide is just *which
numbers you can put into `OPTM_GROUPS`*, and a few supporting constants.

### Where the menu lives in the bigger picture

```
  config.vhd  (you edit this)         QNICE "Shell" firmware        your core, e.g. mega65.vhd
  ┌───────────────────────────┐       ┌──────────────────────┐      ┌─────────────────────────┐
  │ OPTM_ITEMS  (the text)    │ reads │ draws the menu,       │write │ 256-bit "osm_control"   │
  │ OPTM_GROUPS (the meaning) │──────►│ moves the cursor,     │─────►│ vector: bit i = line i  │
  │ OPTM_SIZE, OPTM_DX/DY, …  │       │ remembers selections, │      │ is currently selected.  │
  │ (no firmware code at all) │       │ saves them to SD card │      │ Your logic reads it via │
  └───────────────────────────┘       └──────────────────────┘      │ the C_MENU_* constants. │
                                                                     └─────────────────────────┘
```

You only ever edit `config.vhd`. The firmware is generic and shipped with M2M;
the connection to your hardware is a handful of `C_MENU_*` constants in your
core’s top-level VHDL (section 11).

### The golden rule about `config.vhd`

`config.vhd` has two clearly marked regions:

* a **“START YOUR CONFIGURATION BELOW THIS LINE”** region, where you do all your
  work, and
* a **“!!! DO NOT TOUCH ANYTHING BELOW THIS LINE !!!”** region at the bottom (the
  address decoder, see the Appendix).

Stay in the first region. The framework constants marked `!!! DO NOT TOUCH !!!`
(the `SEL_OPTM_*` selectors and the `OPTM_G_*` flag values) must keep their
values, because the firmware depends on them — but you *use* them constantly.

---

## 2. Your first menu (a minimal complete example)

Let’s build the smallest useful menu: a title, one on/off option, and a way to
close the menu.

```vhdl
-- 1) How many menu lines are there in total?
constant OPTM_SIZE : natural := 5;

-- 2) Define an id for every selectable GROUP you invent (more on ids in §5).
constant OPTM_G_FAST : integer := 1;   -- our one toggle gets group id 1

-- 3) The text the user sees (one line per \n, lower-case \n, trailing \n!):
constant OPTM_ITEMS : string :=
   " My Core\n"     &   -- line 0: a title
   "\n"             &   -- line 1: a blank separator line
   " Fast mode\n"   &   -- line 2: an on/off option
   "\n"             &   -- line 3: a blank separator line
   " Close Menu\n";     -- line 4: closes the OSM

-- 4) The meaning of each line, in the SAME order:
constant OPTM_GROUPS : OPTM_GTYPE := (
   OPTM_G_HEADLINE,                              -- line 0
   OPTM_G_LINE,                                  -- line 1
   OPTM_G_FAST + OPTM_G_SINGLESEL + OPTM_G_START,-- line 2 (toggle, cursor starts here)
   OPTM_G_LINE,                                  -- line 3
   OPTM_G_CLOSE                                  -- line 4
);
```

That is a fully working menu. Read it top to bottom:

* **Line 0** is a *headline*: bright, non-selectable text.
* **Line 1** is a *separator*: a thin horizontal line. Its text is just `"\n"`.
* **Line 2** is a *single-select toggle* (`OPTM_G_SINGLESEL`) in group `1`. The
  user moves the cursor here and presses a key to turn it on/off. `OPTM_G_START`
  says “put the cursor here when the menu first opens”.
* **Line 3** is another separator.
* **Line 4** closes the menu when selected.

Two formatting rules you must follow (they are easy to get wrong):

1. **Every line ends with a lower-case `\n`** — including the last one.
2. **Every line that contains a real, selectable item starts with a space.**
   (Decoration lines like headlines/separators conventionally do too.) Forgetting
   the leading space causes visual glitches.

> The `\n` is two characters in the VHDL string (`\` and `n`); it is **not** a
> control character. Always lower-case. An empty/separator line is literally the
> two characters `"\n"`.

To make this option actually *do* something, you wire one bit to your logic —
that is section 11. For now, focus on the menu structure.

---

## 3. The building blocks (item types overview)

Every `OPTM_GROUPS` entry is built by **adding named constants together**.
Because each constant occupies its own disjoint bits, `+` behaves like a bitwise
OR — you are simply switching attributes on. Here is the full toolbox; the rest
of the guide explains each one:

| You write …                       | … and the line becomes                                   |
| --------------------------------- | -------------------------------------------------------- |
| `OPTM_G_TEXT` (value 0)           | plain, non-selectable text                               |
| `OPTM_G_HEADLINE`                 | non-selectable text in a brighter colour                 |
| `OPTM_G_LINE`                     | a horizontal separator line                              |
| `<your id> + OPTM_G_SINGLESEL`    | an on/off **toggle**                                     |
| `<your id>` (shared by ≥2 lines)  | one member of a **radio group** (pick exactly one)       |
| `… + OPTM_G_STDSEL`               | this item is **selected by default**                     |
| `… + OPTM_G_START`                | the **cursor starts here** (use on exactly one line)     |
| `OPTM_G_SUBMENU`                  | **opens** a submenu (this line is its label)             |
| `OPTM_G_SUBMENU + OPTM_G_CLOSE`   | **closes** a submenu (a “Back” line)                     |
| `<id> + OPTM_G_MOUNT_DRV`         | a **mount-a-disk-image** line                            |
| `<id> + OPTM_G_LOAD_ROM`          | a **load-a-ROM/cartridge** line                          |
| `<id> + OPTM_G_HELP`              | opens a **help screen**                                  |
| `OPTM_G_CLOSE`                    | **closes the whole OSM**                                 |
| `… + OPTM_DEP(mother, item)`      | this line is only **visible** under a condition (§9)     |

The named constants and their exact bit values are defined for you in the
framework part of `config.vhd`. You normally never touch the values — you just
combine the names.

---

## 4. Non-selectable decoration: text, headlines, separators

These lines structure the menu visually; the cursor skips over them.

```vhdl
-- OPTM_ITEMS:                       -- OPTM_GROUPS:
" C64 Configuration\n"               OPTM_G_HEADLINE   -- a bright section title
"\n"                                 OPTM_G_LINE       -- a thin separator line
" Right SID Port\n"                  OPTM_G_TEXT       -- normal-colour caption
```

* `OPTM_G_HEADLINE` — a section title, drawn brighter.
* `OPTM_G_TEXT` — plain caption text. Its value is literally `0`, so it is the
  “neutral” entry; a line with no special attributes *is* `OPTM_G_TEXT`.
* `OPTM_G_LINE` — a horizontal rule. Its text line is just `"\n"`.

None of these can be selected and none of them have a state.

---

## 5. The group id — the key concept

This is the heart of the system, so read slowly.

The **low byte (bits 7…0) of every `OPTM_GROUPS` entry is a “group id”.**

* Group id **0** means “this line belongs to no group” — that is decoration
  (`OPTM_G_TEXT`, `OPTM_G_LINE`, `OPTM_G_HEADLINE`) or a structural line.
* Group ids **1…254** are **yours to invent**. You declare them as plain
  constants in the configuration region, e.g.:

  ```vhdl
  constant OPTM_G_EXP_PORT     : integer := 4;
  constant OPTM_G_KERNAL_MODES : integer := 12;
  constant OPTM_G_MACHINE_MODE : integer := 22;
  ```
* Group id **255** is reserved for `OPTM_G_CLOSE`.

**Lines that share the same group id form one selectable group.** There are
exactly two flavours:

### 5.1 Radio groups (“pick exactly one”)

Give *several* lines the *same* group id and you get a radio group: the user can
select exactly one member, and selecting a new one automatically deselects the
old one.

```vhdl
-- OPTM_ITEMS:               -- OPTM_GROUPS:
" Standard\n"                OPTM_G_KERNAL_MODES + OPTM_G_STDSEL  -- default choice
" Games System\n"           OPTM_G_KERNAL_MODES
" Japanese\n"               OPTM_G_KERNAL_MODES
" JiffyDOS\n"               OPTM_G_KERNAL_MODES
```

All four lines carry group id `12` (`OPTM_G_KERNAL_MODES`). Exactly one of them
must carry `OPTM_G_STDSEL` (the default). Keep the members of a group **together
and inside a single menu level** (don’t split a group across a submenu boundary).

### 5.2 Single-select toggles (“on / off”)

Add `OPTM_G_SINGLESEL` to a line with its own unique group id and you get an
independent on/off switch:

```vhdl
" Simulate 1750 REU 512KB\n"   OPTM_G_REU + OPTM_G_SINGLESEL
" Flip joystick ports\n"       OPTM_G_FLIP_JOYS + OPTM_G_SINGLESEL
```

A toggle is its own group (one line). Add `OPTM_G_STDSEL` if it should default
to *on*.

### 5.3 What an `OPTM_GROUPS` entry looks like inside (advanced)

You can stop reading this sub-section if “add the named constants” is enough for
you. For the curious, here is the full bit layout of one `OPTM_GROUPS` element.
The type allows `OPTM_GTC` significant bits (currently **30**):

| Bits   | Meaning                                                              |
| ------ | -------------------------------------------------------------------- |
| 7…0    | group id (0 = none, 1…254 = your groups, 255 = `OPTM_G_CLOSE`)        |
| 8      | `OPTM_G_STDSEL` (selected by default)                                 |
| 9      | `OPTM_G_LINE` (separator)                                             |
| 10     | `OPTM_G_START` (initial cursor position)                              |
| 11     | mount-drive marker (part of `OPTM_G_MOUNT_DRV`)                       |
| 12     | `OPTM_G_HEADLINE`                                                     |
| 13     | help marker (part of `OPTM_G_HELP`)                                   |
| 14     | submenu marker (part of `OPTM_G_SUBMENU`)                             |
| 15     | `OPTM_G_SINGLESEL`                                                    |
| 16     | load-ROM marker (part of `OPTM_G_LOAD_ROM`)                           |
| 24…17  | dependency mother group id (8 bits; set by `OPTM_DEP`, see §9)         |
| 28…25  | dependency mother item index (4 bits, 0…15; set by `OPTM_DEP`)         |
| 29     | `OPTM_G_DEPENDENT` flag (set by `OPTM_DEP`)                           |

The composite constants are just convenient bit combinations, e.g.
`OPTM_G_SUBMENU = 16#0C000#` is bit 14 + bit 15, and
`OPTM_G_MOUNT_DRV = 16#08800#` is bit 11 + bit 15. **You never need to compute
these — always use the named constants and `+`.**

---

## 6. Default selection, the start cursor, and closing the menu

Three small but essential attributes:

* **`OPTM_G_STDSEL`** — marks the *default* selection. A radio group needs
  **exactly one** member with `OPTM_G_STDSEL`; a toggle uses it to default to on.
  Defaults are what the user gets on first boot (or when settings can’t be loaded
  from SD, see §13).
* **`OPTM_G_START`** — marks where the **cursor sits when the OSM opens**. Put it
  on **exactly one** selectable line that is visible in the main menu. (Forgetting
  it, or hiding it inside a submenu, is a boot error — see §14.)
* **`OPTM_G_CLOSE`** — a line that closes the whole OSM when selected. By
  convention this is a `" Close Menu\n"` line at the end of the main menu.

---

## 7. Submenus

Long menus become submenus. A submenu is a **bracketed range**:

* it **opens** with a line carrying `OPTM_G_SUBMENU`, and
* it **closes** with a line carrying `OPTM_G_SUBMENU + OPTM_G_CLOSE`.

The opener line is special: **it is also the submenu’s label in the parent
menu.** Selecting it enters the submenu; the closer line (typically `" Back\n"`)
returns to the parent.

```vhdl
-- OPTM_ITEMS:               -- OPTM_GROUPS:
" Kernal: %s\n"              OPTM_G_SUBMENU                 -- opens "Kernal" (label shows in parent)
" Kernal Selection\n"        OPTM_G_HEADLINE
"\n"                         OPTM_G_LINE
" Standard\n"                OPTM_G_KERNAL_MODES + OPTM_G_STDSEL
" Games System\n"            OPTM_G_KERNAL_MODES
" Japanese\n"                OPTM_G_KERNAL_MODES
" JiffyDOS\n"                OPTM_G_KERNAL_MODES
"\n"                         OPTM_G_LINE
" Back\n"                    OPTM_G_SUBMENU + OPTM_G_CLOSE  -- closes "Kernal"
```

In the main menu the user sees one line, `" Kernal: %s"` (the `%s` shows the
current choice, see §8). Entering it reveals the four options.

**Nesting.** A submenu may contain another submenu — just place a complete
open…close block inside another one. Nesting depth is effectively unlimited
(bounded only by QNICE stack space). `" Back\n"` (or the <kbd>Run/Stop</kbd> key)
always returns exactly one level up.

```vhdl
" Advanced Settings\n"       OPTM_G_SUBMENU                 -- open "Advanced"
  ...
"  OSM: %s\n"                OPTM_G_SUBMENU                 -- open "OSM Scaling" INSIDE Advanced
   ... options ...
"  Back\n"                   OPTM_G_SUBMENU + OPTM_G_CLOSE  -- close "OSM Scaling"
  ...
" Back\n"                    OPTM_G_SUBMENU + OPTM_G_CLOSE  -- close "Advanced"
```

The opener/closer markers must be **balanced** — every open needs a matching
close, like parentheses. The firmware checks this at boot (§14).

---

## 8. The `%s` placeholder

If a menu line’s text contains `%s`, the firmware replaces it at runtime with a
piece of live text. Where the line gets that text from depends on the line type:

* **On a submenu opener** (`OPTM_G_SUBMENU`): `%s` becomes the label of the
  **first** currently-selected radio item found inside that submenu (in flat
  order, skipping any nested child submenus). So `" Kernal: %s\n"` shows
  `Kernal: JiffyDOS` when JiffyDOS is selected. The submenu must contain a radio
  group of its own; otherwise the firmware aborts with a fatal error the moment it
  first tries to render that `%s`. (A submenu that holds several radio groups
  summarises only its *first* one.)
* **On a mount line** (`OPTM_G_MOUNT_DRV`): `%s` becomes the **mounted disk
  image’s filename**, or a placeholder when nothing is mounted. The placeholder is
  the string constant `OPTM_S_MOUNT` (e.g. `"<Mount Drive>"`). While the write
  cache is being flushed to SD it briefly shows `OPTM_S_SAVING` (`"<Saving>"`).
* **On a load line** (`OPTM_G_LOAD_ROM`): `%s` becomes the **loaded file’s name**,
  or `OPTM_S_CRTROM` (`"<Load>"`) when nothing is loaded.

```vhdl
constant OPTM_S_MOUNT  : string := "<Mount Drive>";  -- shown for an empty drive
constant OPTM_S_CRTROM : string := "<Load>";         -- shown for an empty ROM/cart slot
constant OPTM_S_SAVING : string := "<Saving>";       -- shown while flushing to SD
```

A line may contain at most one `%s`. Lines without `%s` are shown verbatim.

---

## 9. Smart dependencies: showing a line only sometimes (`OPTM_DEP`)

Sometimes a line only makes sense in a certain context. Example: a C64 can run in
PAL or NTSC; the sensible HDMI resolutions differ between the two. **Smart
dependencies** let you list *all* variants and show only the relevant ones.

Tag a line with `OPTM_DEP(mother, item)` and it becomes **visible only while a
specific item of a specific “mother” group is selected**:

```vhdl
-- the "mother": a radio group that chooses PAL (item 0) or NTSC (item 1)
" PAL\n"                  OPTM_G_MACHINE_MODE + OPTM_G_STDSEL  -- item 0
" NTSC\n"                 OPTM_G_MACHINE_MODE                  -- item 1

-- dependent lines elsewhere in the menu (e.g. inside the HDMI submenu):
" 16:9 720p 50 Hz\n"      OPTM_G_HDMI_MODES_PAL  + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
" 16:9 720p 59.94 Hz\n"   OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)
" 4:3  576p 50 Hz\n"      OPTM_G_HDMI_MODES_PAL                  + OPTM_DEP(OPTM_G_MACHINE_MODE, 0)
" 4:3  480p 59.94 Hz\n"   OPTM_G_HDMI_MODES_NTSC                 + OPTM_DEP(OPTM_G_MACHINE_MODE, 1)
```

While **PAL** is selected the user sees only the `50 Hz` lines; switch to **NTSC**
and the menu instantly reflows to show only the `59.94 Hz` lines. The hidden lines
keep their own state, so a PAL choice and an NTSC choice are each remembered.

**The two forms of `OPTM_DEP(mother, item)`:**

* **Radio mother:** `item` is the **0-based index** of the controlling member
  (counting that group’s lines top to bottom), in the range **0…15** (the field
  is 4 bits, so a radio mother used as a dependency source may have at most 16
  members). Visible while that member is selected. Above, PAL is item 0 and NTSC
  is item 1.
* **Single-select (toggle) mother:** `item = 1` means *visible while the toggle is
  ON*; `item = 0` means *visible while the toggle is OFF*.

**Rules (enforced at boot — see §14):**

* Each variant set should be its **own group** (e.g. the PAL HDMI modes are one
  group, the NTSC HDMI modes another). That way each remembers its own choice.
* **All members of one group must carry the same `OPTM_DEP` tag** (or none).
* A “mother” group must **not itself be dependent** (no chains).
* You may **not** put `OPTM_DEP` on a submenu opener/closer, a mount line, a
  load-ROM line, a help line, the close line, or the start line.

> **Compatibility.** Smart dependencies are invisible to your core: a dependent
> line keeps its own state bit, its default and its saved byte. Older cores whose
> `config.vhd` predates this feature keep working unchanged — the firmware detects
> the feature is absent and behaves exactly as before.

> **Layout tip.** Place a mother group and the lines that depend on it so the
> cursor can never sit on a dependent line at the instant its mother changes — the
> easiest way is to keep them in **different submenus** (the C64 keeps PAL/NTSC in
> the *Model* submenu and the dependent display modes in the *HDMI* submenu).

---

## 10. Special function lines (mount, load, help)

A few line types connect the menu to other M2M subsystems. You declare them like
any group, plus the matching attribute. The detailed behaviour of these
subsystems is out of scope here; what matters for the *menu* is how you mark the
line:

* **Mount a disk image:** `<id> + OPTM_G_MOUNT_DRV`. The *N*-th such line in the
  menu corresponds to virtual drive *N* (first occurrence = drive 0, etc.).
  Usually paired with `%s` to show the mounted filename.
* **Load a ROM / cartridge:** `<id> + OPTM_G_LOAD_ROM`. The *N*-th such line is
  load slot *N*. Also usually paired with `%s`.
* **Open a help screen:** `<id> + OPTM_G_HELP`. The first such line opens the
  first help screen, the second opens the next, and so on. (The help/welcome
  *screens* themselves are configured elsewhere in `config.vhd` and are a
  separate topic.)

```vhdl
" 8:%s\n"            OPTM_G_MOUNT_8   + OPTM_G_MOUNT_DRV + OPTM_G_START
" CRT:%s\n"          OPTM_G_MOUNT_CRT + OPTM_G_LOAD_ROM
" About & Help\n"    OPTM_G_ABOUT_HELP + OPTM_G_HELP
```

---

## 11. Connecting a menu choice to your core

Defining the menu is only half the story — a toggle does nothing until your
hardware reads it. **Adding one option touches three places:**

1. **Declare a group id** in `config.vhd`’s configuration region —
   `constant OPTM_G_FAST : integer := 1;`
2. **Add the line** to `OPTM_ITEMS` and `OPTM_GROUPS`, and bump `OPTM_SIZE`.
3. **Read the bit** in your core’s top-level VHDL — `CORE/vhdl/mega65.vhd` for the
   C64 — via a `C_MENU_*` constant. This step is what the rest of this section is
   about. (Note the split: the `OPTM_G_*` group ids live in `config.vhd`; the
   `C_MENU_*` line indices live in `mega65.vhd`.)

The firmware maintains a **256-bit vector** of the menu state, one bit per menu
**line** (not per group): bit *i* is 1 when line *i* is currently selected. The
framework hands you this vector in **both clock domains** — `qnice_osm_control_i`
(QNICE clock) and `main_osm_control_i` (your core’s clock), with identical bit
layout. **Read whichever copy matches the clock domain of the logic that consumes
it.**

To read a specific option you need its **flat line index** — exactly what the
`C_MENU_*` constants in `mega65.vhd` provide:

```vhdl
-- in mega65.vhd: the flat line index (0-based) of each option you care about
constant C_MENU_KERNAL_JIFFY : natural := 107;  -- " JiffyDOS" is line 107
constant C_MENU_FLIP_JOYS    : natural := 32;   -- " Flip joystick ports" is line 32

-- core-clock logic reads the core-clock copy:
if main_osm_control_i(C_MENU_KERNAL_JIFFY) = '1' then
   kernal <= KERNAL_JIFFYDOS;
end if;

-- logic that runs in the QNICE clock domain reads the QNICE copy instead:
joyport_flip <= qnice_osm_control_i(C_MENU_FLIP_JOYS);
```

**How to find a flat index.** Count lines from 0, including blank, headline and
submenu lines — and note that **a submenu’s interior lines occupy indices too**,
even though they are hidden at the main level. In the §15 slice, `" Model: %s"`
(a submenu opener) is line 14; the Model submenu’s entire interior then consumes
the next indices, so the following main-menu entry, `" HDMI: %s"`, is line **33**,
not 15. Hand-counting around submenu brackets is the easiest place to slip.

Key points:

* **A `C_MENU_*` constant is a line index into `OPTM_ITEMS`/`OPTM_GROUPS`**
  (0-based, counting every line). Insert a line and all indices below it shift —
  so re-check your `C_MENU_*` values whenever you edit the menu.
* For a **radio group** you typically define one `C_MENU_*` per member and test
  the bits (or use a small priority chain). For a **toggle**, one bit is enough.
* This is the *only* place the menu is interpreted positionally. To avoid silent
  mistakes the C64 core ships a checker that re-derives every `C_MENU_*` from a
  model of the menu and fails if `config.vhd` and `mega65.vhd` disagree:
  `python3 M2M/rom/tests/menu_test.py verify`.

---

## 12. Sizing and geometry

A handful of constants control size:

* **`OPTM_SIZE`** — the number of menu lines. Must equal the number of `\n`-lines
  in `OPTM_ITEMS` *and* the number of entries in `OPTM_GROUPS`. Maximum 254.
* **`OPTM_DX`** — the menu’s inner width in characters.
* **`OPTM_DY`** — the menu’s inner height in lines. **With submenus, set this to
  the height of the *tallest single view*, not the grand total** — only one level
  is on screen at a time. Count one line per item visible at that level, including
  one line for each submenu *label*, but excluding the contents of submenus.

The firmware draws a frame around the menu, so the on-screen size is
`OPTM_DX + 2` by `OPTM_DY + 2`. Keep `OPTM_DY + 2` within the overlay height or
the menu draws past the frame (the boot checker warns about this on the serial
console).

---

## 13. Remembering settings across power cycles

Set `constant SAVE_SETTINGS : boolean := true;` and the firmware will persist the
user’s choices to a file on the SD card and reload them next time.

* The file is exactly `OPTM_SIZE` bytes — **one byte per menu line** (0 or 1),
  matching the state bits.
* Its name is derived from the core version, so different versions keep separate
  settings files and an old file never corrupts a new layout.
* The firmware falls back to the `OPTM_G_STDSEL` defaults in three cases: the
  file is missing, its size does not match `OPTM_SIZE`, or its first byte is
  `0xFF` — the explicit “use defaults” marker that a freshly generated settings
  file carries.

The practical consequence for you: **whenever you change `OPTM_SIZE` (add/remove
lines), regenerate the settings file** (the M2M tools include a helper for that),
because the old file no longer matches the new line count.

---

## 14. What the firmware checks — and the error messages

At boot the firmware validates your menu and shows a fatal error screen if
something is wrong. Knowing these helps you debug fast:

* **Menu size out of range** — `OPTM_SIZE` must be 1…254.
* **No start item** — exactly one line must carry `OPTM_G_START`.
* **Start item not visible at the main level** — `OPTM_G_START` must be on a
  main-menu line (or a top-level submenu label), not on a line inside a submenu.
* **Unbalanced submenus** — every `OPTM_G_SUBMENU` opener needs a matching
  `OPTM_G_SUBMENU + OPTM_G_CLOSE` closer; the error reports the offending line
  index.
* **No selectable item inside a `%s` submenu** — a `%s` submenu label needs a
  radio group of its own to summarise. *(Unlike the other checks here, this one
  is not part of the boot validation pass — it fires the first time that
  submenu’s `%s` is drawn.)*
* **Smart-dependency errors** (`OPTM_DEP`): a missing/invalid mother group, an
  out-of-range item index, a group whose members carry inconsistent tags, a
  dependency chain, or `OPTM_DEP` on a forbidden line type (§9).

These checks exist precisely because the two parallel arrays are easy to get
subtly out of sync.

---

## 15. A guided tour of a real menu

Here is a slice of the actual C64 main menu, annotated. Compare the text on the
left with the meaning on the right and the concepts above should click:

```
idx  OPTM_ITEMS                     OPTM_GROUPS                                   what it is
  0  " C64 for MEGA65\n"           OPTM_G_HEADLINE                                bright title
  1  "\n"                          OPTM_G_LINE                                    separator
  2  " 8:%s\n"                     OPTM_G_MOUNT_8 + OPTM_G_MOUNT_DRV + OPTM_G_START   drive 0 mount + cursor
  3  " PRG:%s\n"                   OPTM_G_LOAD_PRG + OPTM_G_LOAD_ROM              load a .prg
  4  "\n"                          OPTM_G_LINE
  5  " Expansion Port\n"           OPTM_G_HEADLINE
  6  "\n"                          OPTM_G_LINE
  7  " Use hardware slot\n"        OPTM_G_EXP_PORT + OPTM_G_STDSEL                radio member (default)
  8  " Simulate cartridge:\n"      OPTM_G_EXP_PORT                                radio member
  9  " CRT:%s\n"                   OPTM_G_MOUNT_CRT + OPTM_G_LOAD_ROM             load a .crt
 10  " Simulate 1750 REU 512KB\n"  OPTM_G_REU + OPTM_G_SINGLESEL                  on/off toggle
 ...
 14  " Model: %s\n"                OPTM_G_SUBMENU                                 opens "Model" submenu
 ...
 33  " HDMI: %s\n"                 OPTM_G_SUBMENU                                 opens "HDMI" submenu
```

Lines 7 and 8 share group id `OPTM_G_EXP_PORT` (= 4), so they are one radio group
— “Use hardware slot” vs. “Simulate cartridge”, with the former as default. Line
10 is an independent toggle. Lines 14 and 33 are submenu labels whose `%s` shows
the current sub-choice. Line 2 both mounts drive 0 *and* is where the cursor
starts.

---

## 16. Cheat sheet

**The two arrays (must be the same length = `OPTM_SIZE`):**
`OPTM_ITEMS` = text, one line per `\n`. `OPTM_GROUPS` = meaning, one entry per
line, built by `+`-combining named constants.

**Line types:**

| Goal                         | `OPTM_GROUPS` entry                                  |
| ---------------------------- | ---------------------------------------------------- |
| section title                | `OPTM_G_HEADLINE`                                    |
| separator line               | `OPTM_G_LINE` (text is `"\n"`)                        |
| caption / plain text         | `OPTM_G_TEXT` (= 0)                                   |
| on/off toggle                | `<id> + OPTM_G_SINGLESEL`                             |
| radio group (≥2 lines)       | `<id>` on each member; one gets `+ OPTM_G_STDSEL`     |
| default-on                   | `… + OPTM_G_STDSEL`                                  |
| initial cursor (exactly one) | `… + OPTM_G_START`                                   |
| open / close a submenu       | `OPTM_G_SUBMENU` / `OPTM_G_SUBMENU + OPTM_G_CLOSE`    |
| mount a drive / load a ROM   | `<id> + OPTM_G_MOUNT_DRV` / `<id> + OPTM_G_LOAD_ROM`  |
| help screen                  | `<id> + OPTM_G_HELP`                                  |
| close the OSM                | `OPTM_G_CLOSE`                                        |
| conditional visibility       | `… + OPTM_DEP(mother_group, item)`                   |

**Golden rules:**

1. `OPTM_ITEMS` lines, `OPTM_GROUPS` entries and `OPTM_SIZE` must all agree.
2. Lower-case `\n` at the end of every line; lead selectable lines with a space.
3. Group ids 1…254 are yours; declare them as `constant OPTM_G_… : integer`.
4. Radio group = same id on several lines; toggle = unique id + `OPTM_G_SINGLESEL`.
5. Exactly one `OPTM_G_STDSEL` per radio group; exactly one `OPTM_G_START` overall,
   visible at the main level.
6. Submenu open/close brackets must balance; keep a group inside one level.
7. Re-derive `C_MENU_*` in your core’s VHDL after editing the menu, and run
   `menu_test.py verify`.
8. Stay above the `!!! DO NOT TOUCH !!!` banner; never edit the address decoder.

---

## Appendix: the “DO NOT TOUCH” address decoder

Below the configuration region, `config.vhd` contains an `addr_decode` process.
This is **framework code — do not edit it.** Its job is purely mechanical: when
the QNICE firmware asks for a piece of the configuration (selected by the upper
bits of an address), the decoder returns it 16 bits at a time. For example it
serves `OPTM_ITEMS` character by character, and serves `OPTM_GROUPS` through
several “views” — a masked group word plus one-bit-per-line views for flags such
as default-selected, separator and start. The smart-dependency words and the
feature-probe magic value are served the same way. You benefit from all of this
for free by editing only the arrays above; you never call or modify the decoder.
