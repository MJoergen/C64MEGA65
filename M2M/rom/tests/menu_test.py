#!/usr/bin/env python3
"""
Golden model, fixture generator and headless test runner for the M2M menu
structure algorithms, submenu state machine and live-text API.

Run it from anywhere; the script locates the repository relative to itself
(it lives in M2M/rom/tests/). See the README.md in this folder for the full
picture, including how to adapt the golden menu model when you change the
menu in CORE/vhdl/config.vhd.

Usage:
    python3 menu_test.py gen      generate fixture .asm files + expected outputs
    python3 menu_test.py run      gen + assemble testbeds + run in QNICE
                                  emulator + compare against expected outputs
    python3 menu_test.py vhdl     print the mega65.vhd C_MENU_* constants
                                  derived from the golden menu model
    python3 menu_test.py verify   parse CORE/vhdl/config.vhd + mega65.vhd and
                                  cross-check them against the golden model
    python3 menu_test.py mutate   inject behavior-changing edits into the
                                  dependency assembly and confirm the suite
                                  catches every one (coverage proof for #229)
    python3 menu_test.py ghdl     drive the real config.vhd SEL_OPTM_DEPS
                                  decoder through ghdl and check the raw word
                                  against the model (skips if ghdl is absent;
                                  also run as part of "verify")

The python implementations in this file are instruction-level ports of the
QNICE assembly (menu_struct.asm and, for the legacy parser, the pre-V2.1.0
menu.asm). The testbeds print traces; this script generates the expected
traces independently and diffs them, so the assembly is verified against the
model without any in-asm assertions.
"""

import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

SUBMENU = 0x4000

# ---------------------------------------------------------------------------
# Group ids and flags (mirror of config.vhd)
# ---------------------------------------------------------------------------

F_TEXT      = 0x00000
F_CLOSE     = 0x000FF
F_STDSEL    = 0x00100
F_LINE      = 0x00200
F_START     = 0x00400
F_HEADLINE  = 0x01000
F_SINGLESEL = 0x08000
F_MOUNT_DRV = 0x08800
F_HELP      = 0x0A000
F_SUBMENU   = 0x0C000
F_LOAD_ROM  = 0x18000


def masked(g):
    """The 16-bit view the firmware gets through SEL_OPTM_GROUPS."""
    return (g & 0x8000) | (g & 0x4000) | (g & 0x1000) | (g & 0xFF)


# ---------------------------------------------------------------------------
# The V6 menu (#189 submenus, #93 two virtual drives, #229 dependencies) -
# source of truth: CORE/vhdl/config.vhd (OPTM_ITEMS / OPTM_GROUPS)
# ---------------------------------------------------------------------------

G = dict(
    MOUNT_8=1, MOUNT_9=2, LOAD_PRG=3, EXP_PORT=4, MOUNT_CRT=5, FLIP_JOYS=6,
    SID_SETUP=7, SID_PORT=8, IMPROVE_AUDIO=9, CIA_8521=10, IEC=11,
    KERNAL_MODES=12, HDMI_MODES_PAL=13, HDMI_FF=14, HDMI_DVI=15,
    HDMI_FILTER=16, HDMI_ZOOM=17, VGA_MODES=18, OSM_MODE=19, ABOUT_HELP=20,
    REU=21, MACHINE_MODE=22, TURBO_MODE=23, TURBO_SPEED=24,
    HDMI_MODES_NTSC=25, HDMI_FF_NTSC=26, HDMI_RAW50=27, VOLUME=28,
    RTC_GEOS=29, VICII_MODEL=30, DRV8_MODE=31, DRV8_UNMOUNT=32,
    DRV9_MODE=33, DRV9_UNMOUNT=34,
)

OPEN = ("SUBMENU",)
CLOSE = ("SUBMENU", "CLOSEF")

# Each entry: (label, [group name or None], [flag names])
# The flat index of each entry is its position in this list.
V6_MENU = [
    (" C64 for MEGA65",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 8:%s",                    "MOUNT_8", ["MOUNT_DRV", "START"]),
    (" 8:Internal 1581        ", None, []),              # live status TEXT line
    (" 9:%s",                    "MOUNT_9", ["MOUNT_DRV"]),
    (" 9:Internal 1581        ", None, []),              # live status TEXT line
    (" PRG:%s",                  "LOAD_PRG", ["LOAD_ROM"]),
    (" Drive Settings",          None, OPEN),            # region 1 (issue #93)
    (" Drive 8",                 None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Disk Image: If mounted",  "DRV8_MODE", ["STDSEL"]),
    (" Disk Image: Always",      "DRV8_MODE", []),
    (" Internal 1581",           "DRV8_MODE", []),
    (" Off",                     "DRV8_MODE", []),
    (" Unmount on reset",        "DRV8_UNMOUNT", ["SINGLESEL", "STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Drive 9",                 None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Disk Image: If mounted",  "DRV9_MODE", []),
    (" Disk Image: Always",      "DRV9_MODE", []),
    (" Internal 1581",           "DRV9_MODE", ["STDSEL"]),
    (" Off",                     "DRV9_MODE", []),
    (" Unmount on reset",        "DRV9_UNMOUNT", ["SINGLESEL", "STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 1
    ("",                         None, ["LINE"]),
    (" Expansion Port",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Use hardware slot",       "EXP_PORT", ["STDSEL"]),
    (" Simulate cartridge:",     "EXP_PORT", []),
    (" CRT:%s",                  "MOUNT_CRT", ["LOAD_ROM"]),
    (" Simulate 1750 REU 512KB", "REU", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" C64 Configuration",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Model: %s",               None, OPEN),            # region 2
    (" Model",                   None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" PAL",                     "MACHINE_MODE", ["STDSEL"]),
    (" NTSC",                    "MACHINE_MODE", []),
    ("",                         None, ["LINE"]),
    (" Turbo mode",              None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Off",                     "TURBO_MODE", ["STDSEL"]),
    (" C128",                    "TURBO_MODE", []),
    (" Smart",                   "TURBO_MODE", []),
    ("",                         None, ["LINE"]),
    (" Turbo speed",             None, ["HEADLINE"]),
    (" 2x",                      "TURBO_SPEED", ["STDSEL"]),
    (" 3x",                      "TURBO_SPEED", []),
    (" 4x",                      "TURBO_SPEED", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 2
    (" Flip joystick ports",     "FLIP_JOYS", ["SINGLESEL"]),
    (" HDMI: %s",                None, OPEN),            # region 3
    (" HDMI Display Mode",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 16:9 720p 50 Hz",         "HDMI_MODES_PAL", ["STDSEL"]),
    (" 16:9 720p 59.94 Hz",      "HDMI_MODES_NTSC", ["STDSEL"]),
    (" 4:3  576p 50 Hz",         "HDMI_MODES_PAL", []),
    (" 4:3  480p 59.94 Hz",      "HDMI_MODES_NTSC", []),
    (" 5:4  576p 50 Hz",         "HDMI_MODES_PAL", []),
    (" 5:4  480p 59.94 Hz",      "HDMI_MODES_NTSC", []),
    ("",                         None, ["LINE"]),
    (" HDMI: Flicker-free",      "HDMI_FF", ["SINGLESEL", "STDSEL"]),
    (" HDMI: Flicker-free",      "HDMI_FF_NTSC", ["SINGLESEL", "STDSEL"]),
    (" HDMI: DVI (no sound)",    "HDMI_DVI", ["SINGLESEL"]),
    (" HDMI: %s",                None, OPEN),            # region 4 (in 3)
    (" HDMI Filter",             None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" No Filter",               "HDMI_FILTER", []),
    (" Sharp Bilinear",          "HDMI_FILTER", []),
    (" Bicubic",                 "HDMI_FILTER", []),
    (" Smooth",                  "HDMI_FILTER", []),
    (" Lanczos",                 "HDMI_FILTER", []),
    (" Scanlines",               "HDMI_FILTER", ["STDSEL"]),
    (" CRT (S-Video)",           "HDMI_FILTER", []),
    (" CRT (Composite)",         "HDMI_FILTER", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 4
    (" HDMI: Zoom-in",           "HDMI_ZOOM", ["SINGLESEL"]),
    (" HDMI: Raw 50.1 Hz",       "HDMI_RAW50", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 3
    (" VGA: %s",                 None, OPEN),            # region 5
    (" VGA Display Mode",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "VGA_MODES", ["STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Retro 15 kHz mode",       None, []),
    ("",                         None, ["LINE"]),
    (" 15 kHz with HS/VS",       "VGA_MODES", []),
    (" 15 kHz with CSYNC",       "VGA_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 5
    (" SID: %s",                 None, OPEN),            # region 6
    (" SID Settings",            None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Mono SID",                None, []),
    ("",                         None, ["LINE"]),
    (" 6581",                    "SID_SETUP", ["STDSEL"]),
    (" 8580",                    "SID_SETUP", []),
    ("",                         None, ["LINE"]),
    (" Stereo SID",              None, []),
    ("",                         None, ["LINE"]),
    (" L: 6581 R: 6581",         "SID_SETUP", []),
    (" L: 6581 R: 8580",         "SID_SETUP", []),
    (" L: 8580 R: 6581",         "SID_SETUP", []),
    (" L: 8580 R: 8580",         "SID_SETUP", []),
    ("",                         None, ["LINE"]),
    (" Right SID Port",          None, []),
    ("",                         None, ["LINE"]),
    (" D420",                    "SID_PORT", ["STDSEL"]),
    (" D500",                    "SID_PORT", []),
    (" DE00",                    "SID_PORT", []),
    (" DF00",                    "SID_PORT", []),
    (" Same as left SID port",   "SID_PORT", []),
    ("",                         None, ["LINE"]),
    (" Audio improvements",      "IMPROVE_AUDIO", ["SINGLESEL", "STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 6
    (" IEC: Use hardware port",  "IEC", ["SINGLESEL"]),
    (" Kernal: %s",              None, OPEN),            # region 7
    (" Kernal Selection",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "KERNAL_MODES", ["STDSEL"]),
    (" Games System",            "KERNAL_MODES", []),
    (" Japanese",                "KERNAL_MODES", []),
    (" JiffyDOS",                "KERNAL_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 7
    (" Volume: %s",              None, OPEN),            # region 8
    (" Volume Control",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 100%",                    "VOLUME", ["STDSEL"]),
    (" 95%",                     "VOLUME", []),
    (" 90%",                     "VOLUME", []),
    (" 85%",                     "VOLUME", []),
    (" 80%",                     "VOLUME", []),
    (" 75%",                     "VOLUME", []),
    (" 70%",                     "VOLUME", []),
    (" 65%",                     "VOLUME", []),
    (" 60%",                     "VOLUME", []),
    (" 55%",                     "VOLUME", []),
    (" 50%",                     "VOLUME", []),
    (" 45%",                     "VOLUME", []),
    (" 40%",                     "VOLUME", []),
    (" 35%",                     "VOLUME", []),
    (" 30%",                     "VOLUME", []),
    (" 25%",                     "VOLUME", []),
    (" 20%",                     "VOLUME", []),
    (" 15%",                     "VOLUME", []),
    (" 10%",                     "VOLUME", []),
    (" 5%",                      "VOLUME", []),
    (" 0%",                      "VOLUME", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 8
    (" Advanced Settings",       None, OPEN),            # region 9
    (" Advanced Settings",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" GEOS Real-Time-Clock",    "RTC_GEOS", ["SINGLESEL"]),
    (" OSM: %s",                 None, OPEN),            # region 10 (in 9)
    (" OSM Scaling",             None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 100%",                    "OSM_MODE", ["STDSEL"]),
    (" 89%",                     "OSM_MODE", []),
    (" 80%",                     "OSM_MODE", []),
    (" 73%",                     "OSM_MODE", []),
    (" 67%",                     "OSM_MODE", []),
    (" 62%",                     "OSM_MODE", []),
    (" 57%",                     "OSM_MODE", []),
    (" 53%",                     "OSM_MODE", []),
    (" 50%",                     "OSM_MODE", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 10
    (" CIA: Use 8521 (C64C)",    "CIA_8521", ["SINGLESEL"]),
    (" VIC-II: %s",              None, OPEN),            # region 11 (in 9)
    (" VIC-II model",            None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 656x/NMOS",               "VICII_MODEL", ["STDSEL"]),
    (" 856x/HMOS",               "VICII_MODEL", []),
    (" 856x/old HMOS",           "VICII_MODEL", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 11
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 9
    ("",                         None, ["LINE"]),
    (" About & Help",            "ABOUT_HELP", ["HELP"]),
    ("",                         None, ["LINE"]),
    (" Close Menu",              None, ["CLOSEF"]),
]

FLAGVAL = dict(STDSEL=F_STDSEL, LINE=F_LINE, START=F_START,
               HEADLINE=F_HEADLINE, SINGLESEL=F_SINGLESEL,
               MOUNT_DRV=F_MOUNT_DRV, HELP=F_HELP, SUBMENU=F_SUBMENU,
               LOAD_ROM=F_LOAD_ROM, CLOSEF=F_CLOSE)

# Smart dependencies (OPTM_DEP / OPTM_DEP2, see optm_deps.asm + config.vhd):
# the high bits of an OPTM_GROUPS element encode that a line is only visible
# while one of the items in a 4-bit item MASK of mother group <gid> is
# selected (dependency format 2, magic 0x2DEF). OPTM_G_DEPENDENT is bit 29;
# bits 28..25 carry the mask, bits 24..17 the mother group id.
F_DEPENDENT = 0x20000000


def dep_value(gid, mask):
    """The value added to an OPTM_GROUPS element for a dependency with the
    given 4-bit item mask. OPTM_DEP(m, i) == dep_value(m, 2**i) and
    OPTM_DEP2(m, a, b) == dep_value(m, 2**a + 2**b)."""
    return F_DEPENDENT + (mask * 0x02000000) + (gid * 0x00020000)


# flat index -> (mother group name, 4-bit item mask); the dependent lines of
# the V6 menu: the per-drive mount lines + internal-1581 status lines (#93)
# and the PAL/NTSC HDMI variants, flicker-free twins + Raw 50.1 (#229)
V6_DEPS = {
    2:  ("DRV8_MODE", 0b0011), 3: ("DRV8_MODE", 0b0100),
    4:  ("DRV9_MODE", 0b0011), 5: ("DRV9_MODE", 0b0100),
    57: ("MACHINE_MODE", 0b0001), 58: ("MACHINE_MODE", 0b0010),
    59: ("MACHINE_MODE", 0b0001), 60: ("MACHINE_MODE", 0b0010),
    61: ("MACHINE_MODE", 0b0001), 62: ("MACHINE_MODE", 0b0010),
    64: ("MACHINE_MODE", 0b0001), 65: ("MACHINE_MODE", 0b0010),
    81: ("MACHINE_MODE", 0b0001),
}


def menu_words(menu, deps=None):
    """The full VHDL integer per entry, optionally including OPTM_DEP() bits.
    deps maps flat index -> (mother group name, item mask)."""
    out = []
    for i, (label, group, flags) in enumerate(menu):
        v = G[group] if group else 0
        for f in flags:
            v += FLAGVAL[f]
        if deps and i in deps:
            mg, mask = deps[i]
            v += dep_value(G[mg], mask)
        out.append(v)
    return out


def menu_deps_raw(menu, deps):
    """The raw per-line dependency word as served by SEL_OPTM_DEPS:
    bit 12 = flag, bits 11..8 = item mask, bits 7..0 = mother group id."""
    out = []
    for i in range(len(menu)):
        if deps and i in deps:
            mg, mask = deps[i]
            out.append(0x1000 | (mask << 8) | G[mg])
        else:
            out.append(0)
    return out


def resolve_deps(masked_groups, raw_deps):
    """Port of OPTM_DEPS_RESOLVE: raw dependency words -> resolved words
    (bit 15 = valid, bits 11..8 = item mask copied through, bits 7..0 =
    flat index of the FIRST member of the mother group, for BOTH mother
    types; OPTM_DEP_OK branches on the mother type at runtime)."""
    out = []
    for w in raw_deps:
        if not (w & 0x1000):                    # not dependent
            out.append(0)
            continue
        mother = w & 0xFF
        mask = w & 0x0F00                        # kept in place (bits 11-8)
        members = [j for j, g in enumerate(masked_groups) if (g & 0xFF) == mother]
        if not members:                          # defensive (boot-validated)
            out.append(0)
            continue
        out.append(0x8000 | mask | members[0])
    return out


def dep_ok(i, resolved, stdsel, groups):
    """Port of OPTM_DEP_OK: is line i visible w.r.t. its dependency?
    Needs the (masked) groups array to find the mother type and to walk the
    mother group members (the assembly reads it via OPTM_IR_GROUPS)."""
    if resolved is None:                          # feature off
        return True
    w = resolved[i]
    if not (w & 0x8000):                          # not dependent
        return True
    first = w & 0xFF                              # first member of the mother
    mask = (w >> 8) & 0xF
    if groups[first] & 0x8000:                    # single-select mother:
        k = 1 if stdsel[first] else 0             # k = live state (0/1)
        return bool((mask >> k) & 1)
    gid = groups[first] & 0xFF                    # radio mother: find the
    k = 0                                         # ordinal k of the currently
    j = first                                     # selected member
    while True:
        if j == len(groups):
            return False                          # no selected member: hidden
        if (groups[j] & 0xFF) == gid:
            if stdsel[j]:
                break                             # selected member, ordinal k
            k += 1
        j += 1
    return bool((mask >> k) & 1)                  # k >= 4 shifts the mask out


def menu_masked(menu):
    return [masked(v) for v in menu_words(menu)]


def menu_stdsel(menu):
    return [1 if "STDSEL" in flags else 0 for _, _, flags in menu]


def menu_special(menu):
    """The special-line array that HELP_MENU_INIT hands to OPTM_DEPS_VAL:
    since dependency format 2 only HELP and LOAD_ROM lines are special
    (mount-drive and cursor-start lines MAY be dependent, see issue #93)."""
    return [1 if ("HELP" in flags or "LOAD_ROM" in flags) else 0
            for _, _, flags in menu]


# ---------------------------------------------------------------------------
# The current (pre-V6) C64 menu - for the equivalence harness
# ---------------------------------------------------------------------------

CUR_MENU = [
    (" C64 for MEGA65",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 8:%s",                    "MOUNT_8", ["MOUNT_DRV", "START"]),
    (" PRG:%s",                  "LOAD_PRG", ["LOAD_ROM"]),
    ("",                         None, ["LINE"]),
    (" Expansion Port",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Use hardware slot",       "EXP_PORT", ["STDSEL"]),
    (" Simulate cartridge:",     "EXP_PORT", []),
    (" CRT:%s",                  "MOUNT_CRT", ["LOAD_ROM"]),
    (" Simulate 1750 REU 512KB", "REU", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" C64 Configuration",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Flip joystick ports",     "FLIP_JOYS", ["SINGLESEL"]),
    (" SID: %s",                 None, OPEN),
    (" SID Settings",            None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Mono SID",                None, []),
    ("",                         None, ["LINE"]),
    (" 6581",                    "SID_SETUP", ["STDSEL"]),
    (" 8580",                    "SID_SETUP", []),
    ("",                         None, ["LINE"]),
    (" Stereo SID",              None, []),
    ("",                         None, ["LINE"]),
    (" L: 6581 R: 6581",         "SID_SETUP", []),
    (" L: 6581 R: 8580",         "SID_SETUP", []),
    (" L: 8580 R: 6581",         "SID_SETUP", []),
    (" L: 8580 R: 8580",         "SID_SETUP", []),
    ("",                         None, ["LINE"]),
    (" Right SID Port",          None, []),
    ("",                         None, ["LINE"]),
    (" D420",                    "SID_PORT", ["STDSEL"]),
    (" D500",                    "SID_PORT", []),
    (" DE00",                    "SID_PORT", []),
    (" DF00",                    "SID_PORT", []),
    (" Same as left SID port",   "SID_PORT", []),
    ("",                         None, ["LINE"]),
    (" Audio improvements",      "IMPROVE_AUDIO", ["SINGLESEL", "STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    (" CIA: Use 8521 (C64C)",    "CIA_8521", ["SINGLESEL"]),
    (" IEC: Use hardware port",  "IEC", ["SINGLESEL"]),
    (" Kernal: %s",              None, OPEN),
    (" Kernal Selection",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "KERNAL_MODES", ["STDSEL"]),
    (" Games System",            "KERNAL_MODES", []),
    (" Japanese",                "KERNAL_MODES", []),
    (" JiffyDOS",                "KERNAL_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    ("",                         None, ["LINE"]),
    (" Display Settings",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" HDMI: %s",                None, OPEN),
    (" HDMI Display Mode",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 16:9 720p 50 Hz",         "HDMI_MODES_PAL", ["STDSEL"]),
    (" 16:9 720p 60 Hz",         "HDMI_MODES_PAL", []),
    (" 4:3  576p 50 Hz",         "HDMI_MODES_PAL", []),
    (" 5:4  576p 50 Hz",         "HDMI_MODES_PAL", []),
    ("",                         None, ["LINE"]),
    (" HDMI: Flicker-free",      "HDMI_FF", ["SINGLESEL", "STDSEL"]),
    (" HDMI: DVI (no sound)",    "HDMI_DVI", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    (" HDMI: %s",                None, OPEN),
    (" HDMI Filter",             None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" No Filter",               "HDMI_FILTER", []),
    (" Sharp Bilinear",          "HDMI_FILTER", []),
    (" Bicubic",                 "HDMI_FILTER", []),
    (" Smooth",                  "HDMI_FILTER", []),
    (" Lanczos",                 "HDMI_FILTER", []),
    (" Scanlines",               "HDMI_FILTER", ["STDSEL"]),
    (" CRT (S-Video)",           "HDMI_FILTER", []),
    (" CRT (Composite)",         "HDMI_FILTER", []),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    (" HDMI: Zoom-in",           "HDMI_ZOOM", ["SINGLESEL"]),
    (" VGA: %s",                 None, OPEN),
    (" VGA Display Mode",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "VGA_MODES", ["STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Retro 15 kHz mode",       None, []),
    ("",                         None, ["LINE"]),
    (" 15 kHz with HS/VS",       "VGA_MODES", []),
    (" 15 kHz with CSYNC",       "VGA_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    (" OSM: %s",                 None, OPEN),
    (" OSM Scaling",             None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 100%",                    "OSM_MODE", ["STDSEL"]),
    (" 89%",                     "OSM_MODE", []),
    (" 80%",                     "OSM_MODE", []),
    (" 73%",                     "OSM_MODE", []),
    (" 67%",                     "OSM_MODE", []),
    (" 62%",                     "OSM_MODE", []),
    (" 57%",                     "OSM_MODE", []),
    (" 53%",                     "OSM_MODE", []),
    (" 50%",                     "OSM_MODE", []),
    ("",                         None, ["LINE"]),
    (" Back to main menu",       None, CLOSE),
    ("",                         None, ["LINE"]),
    (" About & Help",            "ABOUT_HELP", ["HELP"]),
    ("",                         None, ["LINE"]),
    (" Close Menu",              None, ["CLOSEF"]),
]

# ---------------------------------------------------------------------------
# Golden models (instruction-level ports of the assembly)
# ---------------------------------------------------------------------------


def classify(w):
    if w & SUBMENU:
        return "open" if (w & 0xFF) == 0 else "close"
    return "plain"


def build_new(groups, level, resolved=None, stdsel=None):
    """Port of OPTM_STRUCT_BUILD. Returns dict or {'err': idx}. When resolved
    (+ stdsel) is given, the plain-line visibility is ANDed with the
    dependency predicate (openers/closers are never dependent)."""
    cur, nxt, vis, par, opn, lastopen = 0, 1, 0, 0, 0, 0
    stack, out = [], []
    for i, w in enumerate(groups):
        c = classify(w)
        if c == "open":
            lastopen = i
            if nxt == level:
                par, opn = cur, i
            v = 1 if level == cur else 0
            stack.append(cur)
            cur = nxt
            nxt += 1
            out.append(cur | (0x8000 if v else 0))
            vis += v
        elif c == "close":
            if not stack:
                return {"err": i}
            v = 1 if level == cur else 0
            out.append(cur | (0x8000 if v else 0))
            vis += v
            cur = stack.pop()
        else:
            v = 1 if level == cur else 0
            if v and not dep_ok(i, resolved, stdsel, groups):
                v = 0
            out.append(cur | (0x8000 if v else 0))
            vis += v
    if stack:
        return {"err": lastopen}
    return {"arr": out, "vis": vis, "parent": par, "opener": opn}


def build_old(groups, level):
    """Port of the pre-V2.1.0 three-pass _OPTM_STRUCT (toggle parser)."""
    n = len(groups)
    arr, r3, r4, r5 = [], 0, 1, 0
    for w in groups:
        if w & SUBMENU:
            if r5 == 1:
                arr.append(r3)
                r5, r3 = 0, 0
                continue
            r5, r3 = 1, r4
            r4 += 1
            arr.append(r3)
        else:
            arr.append(r3)
    if r5 == 1:
        return None
    vis = 0
    for i in range(n):
        if arr[i] == level:
            arr[i] |= 0x8000
            vis += 1
        else:
            arr[i] &= 0x7FFF
    last, flag = 0, 1
    for i in range(n):
        m = arr[i] & 0xFF
        if m != last:
            last, flag = m, 1
        if not (arr[i] & 0x8000):
            if level == 0 and flag == 1:
                flag = 0
                arr[i] |= 0x8000
                vis += 1
        else:
            if level != 0 and flag == 1:
                flag = 0
                arr[i] &= 0x7FFF
                vis -= 1
    return {"arr": arr, "vis": vis}


def validate(groups, start):
    """Port of OPTM_STRUCT_VAL. start=0xFFFF skips the start check."""
    depth, h, opens, maxh, last = 0, 0, 0, 0, 0
    stack = []
    for i, w in enumerate(groups):
        c = classify(w)
        if c == "close":
            if depth == 0:
                return ("err", 0, i)
            if i == start:
                return ("err", 2, i)
            h += 1
            maxh = max(maxh, h)
            h = stack.pop()
            depth -= 1
        elif c == "open":
            if i == start and depth != 0:
                return ("err", 2, i)
            last = i
            h += 1
            stack.append(h)
            h = 0
            depth += 1
            opens += 1
        else:
            h += 1
            if i == start and depth != 0:
                return ("err", 2, i)
    if depth:
        return ("err", 1, last)
    maxh = max(maxh, h)
    return ("ok", opens, maxh)


def summ_scan(groups, heading, stdsel, resolved=None):
    """Port of OPTM_SUMM_SCAN. Returns ('found', idx) or ('err', class).
    When resolved is given, dependency-hidden radio members are skipped."""
    d, i, n = 0, heading, len(groups)
    while True:
        i += 1
        if i == n:
            return ("err", 0)
        w = groups[i]
        if w & SUBMENU:
            if (w & 0xFF) == 0:
                d += 1
                continue
            if d > 0:
                d -= 1
                continue
            return ("err", 1)
        if d > 0:
            continue
        if not (1 <= w < 255):
            continue
        if not dep_ok(i, resolved, stdsel, groups):
            continue
        if stdsel[i] == 0:
            continue
        return ("found", i)


def num_regions(groups):
    return sum(1 for w in groups if classify(w) == "open")


def validate_deps(groups, raw, special):
    """Port of OPTM_DEPS_VAL. groups are masked words, raw are raw dependency
    words, special[i] != 0 marks load_rom/help lines (mount and start lines
    are no longer special since dependency format 2). Returns ('ok',) or
    ('err', class, idx) with class 0..4."""
    n = len(groups)
    for i in range(n):                            # pass A
        if not (raw[i] & 0x1000):
            continue
        if ((groups[i] & 0x4000) or (groups[i] & 0xFF) == 255
                or special[i]):                   # class 4: special line
            return ("err", 4, i)                  # (incl. a bare CLOSE, id 255)
        mother = raw[i] & 0xFF
        mask = (raw[i] >> 8) & 0xF
        if mother == 0 or mother == 255:          # class 0: bad mother id
            return ("err", 0, i)
        count = single = chain = 0
        for j in range(n):
            if (groups[j] & 0xFF) == mother:
                if groups[j] & 0x8000:
                    single = 1
                if raw[j] & 0x1000:
                    chain = 1
                count += 1
        if count == 0:                            # class 0: mother has no members
            return ("err", 0, i)
        if chain:                                 # class 3: dependency chain
            return ("err", 3, i)
        if mask == 0:                             # class 1: empty mask
            return ("err", 1, i)
        if single:
            if mask & 0xC:                        # class 1: single-sel mothers
                return ("err", 1, i)              # only have items 0 and 1
        elif count < 4 and (mask >> count):       # class 1: radio mask bit at or
            return ("err", 1, i)                  # beyond the member count
    for i in range(n):                            # pass B: group uniformity
        gid = groups[i] & 0xFF
        if gid == 0 or gid == 255 or (groups[i] & 0x4000):
            continue
        first = next(j for j in range(n) if (groups[j] & 0xFF) == gid)
        if first != i and raw[first] != raw[i]:   # class 2: mixed group
            return ("err", 2, i)
    return ("ok",)


def deps_minhid(groups, raw):
    """Port of OPTM_DEPS_MINHID: the guaranteed-hidden dependent-line count
    for the boot-time height check in options.asm. Sum over all mother
    groups - found via a first-occurrence scan of the dependent lines - of
    the MINIMUM, over the mother's selectable states, of the number of
    dependent lines of that mother whose mask bit for the state is clear
    (= hidden in that state). States: single-select mothers 0..1; radio
    mothers 0..min(member count, 4)-1 (states beyond the 4-bit mask width
    hide every dependent line and can never lower the minimum). The sum is
    GLOBAL over all views - a safe under-approximation, see the routine
    header in optm_deps.asm; the exact per-view maximum is what
    dep_aware_max_height() computes for the OPTM_DY authoring check."""
    n = len(groups)
    total = 0
    for i in range(n):
        if not (raw[i] & 0x1000):                 # not dependent
            continue
        mother = raw[i] & 0xFF
        if any((raw[j] & 0x1000) and (raw[j] & 0xFF) == mother
               for j in range(i)):                # not the first occurrence
            continue
        count = sum(1 for w in groups if (w & 0xFF) == mother)
        if count == 0:                            # defensive (boot-validated)
            continue
        single = any((w & 0x8000) and (w & 0xFF) == mother for w in groups)
        states = 2 if single else min(count, 4)
        total += min(
            sum(1 for j in range(n)
                if (raw[j] & 0x1000) and (raw[j] & 0xFF) == mother
                and not (((raw[j] >> 8) & 0xF) >> s) & 1)
            for s in range(states))
    return total


def dep_aware_max_height(menu, deps):
    """The dependency-aware OPTM_DY: the maximum number of SIMULTANEOUSLY
    visible lines over all view levels. Per view, the structural line count
    (build_new with deps off marks the view's members via bit 15) is
    reduced, per mother group, by the minimum number of that mother's
    dependent lines IN THIS VIEW that are hidden in any selectable state of
    the mother - mutually exclusive dependent lines (e.g. the per-drive
    mount/status twins of issue #93) can never be visible together. This is
    the authoring convention documented above OPTM_DX/OPTM_DY in config.vhd;
    the firmware's boot-time warning uses the global under-approximation
    OPTM_DEPS_MINHID instead (see deps_minhid)."""
    groups = menu_masked(menu)
    raw = menu_deps_raw(menu, deps)
    n = len(groups)
    mothers = []
    for i in range(n):                            # first-occurrence order
        if (raw[i] & 0x1000) and (raw[i] & 0xFF) not in mothers:
            mothers.append(raw[i] & 0xFF)
    best = 0
    for lv in range(num_regions(groups) + 1):
        b = build_new(groups, lv)
        height = b["vis"]
        for mother in mothers:
            members = [j for j in range(n) if (groups[j] & 0xFF) == mother]
            single = any(groups[j] & 0x8000 for j in members)
            states = 2 if single else min(len(members), 4)
            masks = [(raw[j] >> 8) & 0xF for j in range(n)
                     if (raw[j] & 0x1000) and (raw[j] & 0xFF) == mother
                     and (b["arr"][j] & 0x8000)]
            if masks:
                height -= min(sum(1 for m in masks if not (m >> s) & 1)
                              for s in range(states))
        best = max(best, height)
    return best


# A synthetic menu for the dependency testbed: a radio mother (gid 22, members
# at idx 2/3), a single-select mother (gid 14, idx 5) and dependent lines
# inside region 2 (idx 7..14): plain radio lines, a two-bit-mask line, a
# MOUNT_DRV-style line (masked as single-select, legal since dependency
# format 2 / issue #93) and a TEXT status line (group id 0).
DEP_MOTHER_R = 22
DEP_MOTHER_S = 14
DEP_GROUPS = [
    0x1000,             # 0  headline
    0xC000,             # 1  open region 1
    DEP_MOTHER_R,       # 2  PAL  (radio mother member 0)
    DEP_MOTHER_R,       # 3  NTSC (radio mother member 1)
    0xC0FF,             # 4  close region 1
    0x8000 | DEP_MOTHER_S,  # 5  toggle (single-select mother)
    0xC000,             # 6  open region 2 (heading for %s)
    13,                 # 7  PAL variant a   dep(22, mask 0b01)
    25,                 # 8  NTSC variant a  dep(22, mask 0b10)
    13,                 # 9  PAL variant b   dep(22, mask 0b01)
    25,                 # 10 NTSC variant b  dep(22, mask 0b10)
    15,                 # 11 toggle-dependent line dep(14, mask 0b10)
    16,                 # 12 both-modes line dep(22, mask 0b11) - two-bit mask
    0x8000 | 17,        # 13 MOUNT_DRV-style line dep(22, mask 0b01)
    0x0000,             # 14 TEXT status line dep(22, mask 0b10)
    0xC0FF,             # 15 close region 2
    0x00FF,             # 16 Close Menu
]
DEP_RAW_MAP = {7: (22, 0b01), 8: (22, 0b10), 9: (22, 0b01), 10: (22, 0b10),
               11: (14, 0b10), 12: (22, 0b11), 13: (22, 0b01), 14: (22, 0b10)}


def dep_raw_array(rawmap, n):
    raw = [0] * n
    for idx, (m, mask) in rawmap.items():
        raw[idx] = 0x1000 | (mask << 8) | m
    return raw


def deps_resolve_fixtures():
    """(name, groups, raw) -> expected resolved array via resolve_deps."""
    fx = []
    fx.append(("synthetic model", DEP_GROUPS,
               dep_raw_array(DEP_RAW_MAP, len(DEP_GROUPS))))
    # single-select mother: mask 0b01 = visible while OFF, 0b10 = while ON
    g = [0x8000 | 9, 12, 12]
    r = [0, 0x1000 | (0b01 << 8) | 9, 0x1000 | (0b10 << 8) | 9]
    fx.append(("single-select off/on", g, r))
    # no dependencies at all
    fx.append(("none", [1, 2, 0x1000], [0, 0, 0]))
    # the real V6 menu: masks 0b0011/0b0100 (drives) and 0b0001/0b0010 (HDMI)
    fx.append(("v6 real menu", menu_masked(V6_MENU),
               menu_deps_raw(V6_MENU, V6_DEPS)))
    return fx


def deps_val_fixtures():
    """(name, groups, raw, special) -> expected via validate_deps."""
    n = len(DEP_GROUPS)
    base = dep_raw_array(DEP_RAW_MAP, n)
    fx = [("valid synthetic model", DEP_GROUPS, base, [0] * n)]
    # class 0: mother does not exist (gid 99)
    r = list(base); r[7] = 0x1000 | (0b01 << 8) | 99
    fx.append(("mother missing", DEP_GROUPS, r, [0] * n))
    # class 1: radio mask bits 0+2, bit 2 out of range (mother 22: 2 members)
    r = list(base); r[7] = 0x1000 | (0b0101 << 8) | 22
    # keep the group uniform so the mask error is hit, not the mix error
    r[9] = r[7]
    fx.append(("mask overflow", DEP_GROUPS, r, [0] * n))
    # class 1: pure out-of-range mask bit (bit 2 only)
    r = list(base); r[7] = 0x1000 | (0b0100 << 8) | 22
    r[9] = r[7]
    fx.append(("mask bit out of range", DEP_GROUPS, r, [0] * n))
    # class 1: empty mask
    r = list(base); r[7] = 0x1000 | (0b0000 << 8) | 22
    r[9] = r[7]
    fx.append(("empty mask", DEP_GROUPS, r, [0] * n))
    # class 1: single-select mother with a mask bit beyond bit 1
    r = list(base); r[11] = 0x1000 | (0b0100 << 8) | 14
    fx.append(("single-select mask too wide", DEP_GROUPS, r, [0] * n))
    # class 2: members of one group carry different dependency words
    r = list(base); r[9] = 0x1000 | (0b10 << 8) | 22  # idx 7 mask 0b01, idx 9 0b10
    fx.append(("mixed group", DEP_GROUPS, r, [0] * n))
    # class 3: the mother group is itself dependent (chain)
    r = list(base); r[2] = 0x1000 | (0b01 << 8) | 13; r[3] = r[2]
    fx.append(("dependency chain", DEP_GROUPS, r, [0] * n))
    # class 4: a special (load-ROM) line is dependent
    r = list(base); r[0] = 0x1000 | (0b01 << 8) | 22
    sp = [0] * n; sp[0] = 1
    fx.append(("special line", DEP_GROUPS, r, sp))
    # class 4: a dependency on the bare main-level Close line (group id 255,
    # no submenu bit) - this is the case the adversarial review caught (#1)
    r = list(base); r[16] = 0x1000 | (0b01 << 8) | 22
    fx.append(("dependent bare close", DEP_GROUPS, r, [0] * n))
    # legal since dependency format 2: ONLY a mount-style (single-select
    # masked) line is dependent; its special flag is 0 because options.asm no
    # longer folds the mount window into the special array (issue #93)
    g2 = [22, 22, 0x8000 | 1, 0x00FF]
    r2 = [0, 0, 0x1000 | (0b01 << 8) | 22, 0]
    fx.append(("dependent mount line accepted", g2, r2, [0] * 4))
    # the real V6 menu with its real special array (help | load_rom): the
    # dependent mount/START/TEXT lines of issue #93 must validate cleanly
    fx.append(("v6 real menu", menu_masked(V6_MENU),
               menu_deps_raw(V6_MENU, V6_DEPS), menu_special(V6_MENU)))
    return fx


def deps_build_fixtures():
    """(name, groups, resolved, stdsel, level) -> expected via build_new."""
    n = len(DEP_GROUPS)
    res = resolve_deps(DEP_GROUPS, dep_raw_array(DEP_RAW_MAP, n))
    # a single-select mother referenced with mask 0b01 = "visible while OFF";
    # this is the only way mask bit 0 of a single-select mother reaches
    # OPTM_DEP_OK at runtime, so it pins the predicate's state-0 arm (#4)
    res0 = resolve_deps(DEP_GROUPS,
                        dep_raw_array({**DEP_RAW_MAP, 11: (14, 0b01)}, n))

    def sd(**kw):
        s = [0] * n
        for k, v in kw.items():
            s[int(k[1:])] = v
        return s

    fx = []
    # PAL selected, toggle off: PAL variants + both-modes + mount visible,
    # NTSC variants + toggle-dep + TEXT status hidden
    fx.append(("region2 PAL", DEP_GROUPS, res, sd(i2=1, i5=0), 2))
    # NTSC selected, toggle on: NTSC variants + both-modes + toggle-dep +
    # TEXT status visible, PAL variants + mount hidden
    fx.append(("region2 NTSC", DEP_GROUPS, res, sd(i3=1, i5=1), 2))
    # main level: dependents are hidden by level anyway
    fx.append(("main level", DEP_GROUPS, res, sd(i2=1), 0))
    # mask 0b01 on a single-select mother: visible while the toggle is OFF
    fx.append(("mask(G,0b01) toggle OFF visible", DEP_GROUPS, res0,
               sd(i2=1, i5=0), 2))
    # and hidden while the toggle is ON
    fx.append(("mask(G,0b01) toggle ON hidden", DEP_GROUPS, res0,
               sd(i2=1, i5=1), 2))
    # no member of the radio mother selected at all: every line that depends
    # on it is hidden (pins the no-selected-member arm of OPTM_DEP_OK)
    fx.append(("no mother member selected", DEP_GROUPS, res, sd(i5=1), 2))
    # the real V6 menu at the main level with factory defaults: 8:%s visible,
    # 8:Internal 1581 hidden, 9:%s hidden, 9:Internal 1581 visible (#93)
    v6g = menu_masked(V6_MENU)
    v6res = resolve_deps(v6g, menu_deps_raw(V6_MENU, V6_DEPS))
    fx.append(("v6 defaults main level", v6g, v6res, menu_stdsel(V6_MENU), 0))
    # drive 9 switched to "Disk Image: Always": 9:%s appears, status line hides
    s = menu_stdsel(V6_MENU)
    s[20], s[19] = 0, 1
    fx.append(("v6 drive 9 Always", v6g, v6res, s, 0))
    # the HDMI submenu level with the PAL machine mode: NTSC variants hidden
    fx.append(("v6 HDMI level PAL", v6g, v6res, menu_stdsel(V6_MENU), 3))
    return fx


def deps_summ_fixtures():
    """(name, groups, resolved, stdsel, heading) -> expected via summ_scan."""
    n = len(DEP_GROUPS)
    res = resolve_deps(DEP_GROUPS, dep_raw_array(DEP_RAW_MAP, n))

    def sd(**kw):
        s = [0] * n
        for k, v in kw.items():
            s[int(k[1:])] = v
        return s

    fx = []
    # PAL selected + PAL variant a selected -> the walk finds idx 7
    fx.append(("PAL variant", DEP_GROUPS, res, sd(i2=1, i7=1, i8=1), 6))
    # NTSC selected: idx 7 is dep-hidden even though selected; finds idx 8
    fx.append(("NTSC skips hidden", DEP_GROUPS, res, sd(i3=1, i7=1, i8=1), 6))
    # NTSC selected + only the two-bit-mask line selected: the walk skips the
    # dep-hidden 7, the unselected 8/10, the hidden 11 and finds idx 12
    fx.append(("two-bit mask member", DEP_GROUPS, res, sd(i3=1, i12=1), 6))
    return fx


# Synthetic menus for the OPTM_DEPS_MINHID testbed. "State cap": a radio
# mother (gid 40) with FIVE members, so the state loop is capped at
# min(5, 4) = 4 states, and dependent-line masks whose per-state hidden
# counts are s0:2 s1:2 s2:1 s3:1 - the minimum (1) is only reached in the
# capped-in states 2/3, which kills a cap-at-2 mutant; plus a single-select
# mother (gid 41) whose two dependent lines are hidden in state 0 and
# visible in state 1 (minimum 0 at state 1), which kills a states=1 mutant.
# The dependent lines are TEXT-style (group id 0): MINHID reads only their
# raw dependency words, never their own group membership.
MH_CAP_GROUPS = [
    0x1000,          # 0  headline
    40, 40, 40, 40, 40,  # 1..5  radio mother gid 40, 5 members (cap!)
    0x8000 | 41,     # 6  single-select mother gid 41
    0, 0, 0,         # 7..9  dependent lines of mother 40
    0, 0,            # 10..11  dependent lines of mother 41
    0x00FF,          # 12 close menu
]
MH_CAP_RAW = dep_raw_array({7: (40, 0b1100), 8: (40, 0b1100),
                            9: (40, 0b0011),
                            10: (41, 0b10), 11: (41, 0b10)},
                           len(MH_CAP_GROUPS))

# "Different minimum states": mother 50 (radio, 3 members) reaches its
# minimum (1) only in states 1/2 (per-state hidden counts s0:2 s1:1 s2:1),
# mother 51 (radio, 2 members) only in state 0 (s0:0 s1:1) - so the
# min-over-states comparison must actually compare, not just take state 0.
MH_MIN_GROUPS = [
    50, 50, 50,      # 0..2  radio mother gid 50, 3 members
    51, 51,          # 3..4  radio mother gid 51, 2 members
    0, 0, 0, 0,      # 5..8  dependent lines of mother 50
    0, 0,            # 9..10 dependent lines of mother 51
    0x00FF,          # 11 close menu
]
MH_MIN_RAW = dep_raw_array({5: (50, 0b011), 6: (50, 0b101),
                            7: (50, 0b110), 8: (50, 0b110),
                            9: (51, 0b11), 10: (51, 0b01)},
                           len(MH_MIN_GROUPS))


def deps_minhid_fixtures():
    """(name, groups, raw) -> expected sum via deps_minhid."""
    fx = []
    # the real V6 arrays: DRV8_MODE min 1 + DRV9_MODE min 1 + MACHINE_MODE
    # min 4 (in the PAL state the four NTSC HDMI lines are hidden) = 6
    fx.append(("v6 real menu", menu_masked(V6_MENU),
               menu_deps_raw(V6_MENU, V6_DEPS)))
    # no dependencies at all -> 0
    fx.append(("no dependencies", [1, 2, 0x1000], [0, 0, 0]))
    # the synthetic dependency model: mother 22 min 3, mother 14 min 0
    fx.append(("synthetic model", DEP_GROUPS,
               dep_raw_array(DEP_RAW_MAP, len(DEP_GROUPS))))
    # multi-mother with the radio state cap + a single-select mother
    fx.append(("state cap + single-select", MH_CAP_GROUPS, MH_CAP_RAW))
    # minima in different (non-zero) states per mother
    fx.append(("different minimum states", MH_MIN_GROUPS, MH_MIN_RAW))
    return fx


# ---------------------------------------------------------------------------
# Navigation simulator (port of the OPTM_RUN state machine in menu.asm)
# ---------------------------------------------------------------------------

KEY_UP, KEY_DOWN, KEY_SELECT, KEY_CLOSE, KEY_SELALT, KEY_MENUUP = 1, 2, 3, 4, 5, 6


class NavSim:
    def __init__(self, groups, stdsel, start, labels=None, raw_deps=None):
        self.g = list(groups)
        self.sel = list(stdsel)
        self.n = len(groups)
        self.labels = labels or [""] * self.n
        self.level = 0
        self.cursor = start
        self.trace = []
        self.keys = []
        self.resolved = resolve_deps(self.g, raw_deps) if raw_deps else None

    def _struct(self):
        return build_new(self.g, self.level, self.resolved, self.sel)

    def _affects(self, w):
        """Port of OPTM_DEPS_AFFECTS: does group word w control a dependent?"""
        if self.resolved is None:
            return False
        for rw in self.resolved:
            if (rw & 0x8000) and self.g[rw & 0xFF] == w:
                return True
        return False

    def _visible(self, i):
        return bool(self._struct()["arr"][i] & 0x8000)

    def _emit_k(self):
        b = self._struct()
        self.trace.append("K L=%04X C=%04X P=%04X O=%04X"
                          % (self.level, self.cursor, b["parent"], b["opener"]))

    def _emit_w(self):
        """OPTM_SHOW runs the %s machinery: for every line that contains a
        %s and that is visible at the current level, the OPTM_CLBK_SHOW
        callback fires with the flat line index - the testbed stub prints
        one W line per call. This is the regression gate for the
        percent-terminated-label desync bug in the OPTM_SHOW scanner."""
        arr = self._struct()["arr"]
        for i, t in enumerate(self.labels):
            if "%s" in t and (arr[i] & 0x8000):
                self.trace.append("W I=%04X" % i)

    def _normalize(self):
        """Port of the _OPTM_RUN_INI* entry normalization that OPTM_RUN runs
        right after building the structure: if the entry position is hidden
        at the current level or not selectable, advance (with wrap-around
        and a guard counter) to the next visible selectable line. Needed
        since dependency format 2, where a selectable line (e.g. the mount
        line carrying OPTM_G_START, issue #93) can be dependency-hidden."""
        arr = self._struct()["arr"]
        guard = self.n
        c = self.cursor
        while True:
            if arr[c] & 0x8000:                   # visible at this level?
                w = self.g[c]
                if (w & SUBMENU) or (w & 0xFF):   # selectable?
                    break
            c += 1                                # advance with wrap-around
            if c == self.n:
                c = 0
            guard -= 1
            if guard == 0:                        # cannot happen (validators),
                c = 0                             # but never loop forever
                break
        self.cursor = c

    def _redraw(self):
        """A structure-rebuild redraw (the _OPTM_RUN_SM_4 path: enter / leave /
        section-4.3 mother toggle). The runtime rebuilds the (sub)menu structure
        and restarts OPTM_RUN with the kept cursor, which re-runs the entry
        normalization (_OPTM_RUN_INI*). On this path the cursor sits on the
        just-entered line, the opener it left to, or the mother it just
        toggled - none of which a dependency can hide - so the normalization
        must be a no-op here. Assert that invariant so a future regression
        that strands the cursor is caught by the suite instead of silently
        warping the cursor on hardware. (Background OPTM_SET redraws do NOT
        rebuild the struct, so neither the normalization nor the assertion
        applies to them - see the refuted findings #8/#10 in the adversarial
        review.)"""
        self._emit_w()
        before = self.cursor
        self._normalize()
        assert self.cursor == before, (
            "cursor moved %d -> %d by a structure-rebuild redraw at level %d"
            % (before, self.cursor, self.level))

    def run_start(self):
        """The testbed calls OPTM_SHOW before each OPTM_RUN, like HELP_MENU
        does in production; OPTM_RUN then normalizes the entry cursor."""
        self._emit_w()
        self._normalize()

    def _move(self, step):
        c = self.cursor
        guard = 0
        while True:
            guard += 1
            assert guard < 1000, "movement loop stuck"
            c = (c + step) % self.n
            if not self._visible(c):
                continue
            w = self.g[c]
            if w & SUBMENU:
                break
            if w & 0xFF:
                break
        self.cursor = c

    def _leave(self):
        b = self._struct()
        self.level = b["parent"]
        self.cursor = b["opener"]

    def _select(self, key):
        w = self.g[self.cursor]
        if w & SUBMENU:
            if (w & 0xFF) == 0:                     # enter
                rid = self._struct()["arr"][self.cursor] & 0x7FFF
                self.level = rid
                i = self.cursor
                while True:                          # enter-cursor scan
                    i += 1
                    assert i < self.n, "NOSEL fatal"
                    if self.g[i] & 0x4000:           # child opener / own closer
                        break
                    if (self.g[i] & 0xFF) and dep_ok(i, self.resolved,
                                                     self.sel, self.g):
                        break                        # visible selectable line
                self.cursor = i
                self._redraw()                      # SM_4 rebuild + cursor check
            else:                                   # leave
                self._leave()
                self._redraw()                      # SM_4 rebuild + cursor check
            return None
        if self.sel[self.cursor]:
            if w & 0x8000:                          # single-select: flip off
                self.sel[self.cursor] = 0
                self.trace.append("S G=%04X I=%04X K=%04X" % (w, 0, key))
                if self._affects(w):                # toggled a mother: redraw
                    self._redraw()
            return None                             # multi already set: ignore
        if w & 0x8000:
            self.sel[self.cursor] = 1
            item = 1
        else:
            for j in range(self.n):                 # radio: clear whole group
                if self.g[j] == w:
                    self.sel[j] = 0
            self.sel[self.cursor] = 1
            first = self.g.index(w)
            item = sum(1 for j in range(first, self.cursor)
                       if self.g[j] == w)
        self.trace.append("S G=%04X I=%04X K=%04X" % (w, item, key))
        if w == 0x00FF:
            return "close"
        if self._affects(w):                        # changed a mother: redraw
            self._redraw()
        return None

    def feed(self, key):
        """Process one key as OPTM_RUN would. Returns 'close' if menu ends."""
        self._emit_k()                              # GETKEY trace happens
        self.keys.append(key)                       # before the key acts
        if key & 0x8000:                            # background redraw:
            self._emit_w()                          # OPTM_SHOW runs first
        k = key & 0x7FFF
        if k == KEY_UP:
            self._move(-1)
        elif k == KEY_DOWN:
            self._move(+1)
        elif k == KEY_CLOSE:
            self.trace.append("R C=%04X" % self.cursor)
            return "close"
        elif k == KEY_MENUUP:
            if self.level == 0:
                self.trace.append("R C=%04X" % self.cursor)
                return "close"
            self._leave()
            self._redraw()                          # SM_4 rebuild + cursor check
        elif k in (KEY_SELECT, KEY_SELALT):
            if self._select(k) == "close":
                self.trace.append("R C=%04X" % self.cursor)
                return "close"
        return None

    def until(self, key, target):
        guard = 0
        while self.cursor != target:
            guard += 1
            assert guard < 400, "until() did not reach %d" % target
            assert self.feed(key) is None, "menu closed during until()"


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

O, C = 0xC000, 0xC0FF


def flat_index(label, nth=0):
    """Flat index of the nth V6 menu line with exactly this label."""
    idxs = [i for i, (t, _, _) in enumerate(V6_MENU) if t == label]
    return idxs[nth]


def struct_fixtures():
    fx = []
    fx.append(("current C64 menu", 2, menu_masked(CUR_MENU)))
    fx.append(("V6 #189 menu", 2, menu_masked(V6_MENU)))
    fx.append(("adjacent regions", 1, [0x1000, 5, O, 6, C, O, 7, C, 8]))
    fx.append(("region at flat 0", 3, [O, 5, C, 7]))
    fx.append(("region at end", 0, [7, O, 5, C]))
    fx.append(("empty region", 0, [1, O, C, 2]))
    fx.append(("deep chain 10 levels", 0,
               [1] + [O] * 10 + [2] + [C] * 10))
    fx.append(("fatal unclosed opener", 0, [1, O, 5]))
    fx.append(("fatal closer first", 1, [C, 1]))
    fx.append(("fatal dangling single opener", 0xFFFF, [O, 5]))
    fx.append(("START on nested opener", 1, [O, O, 5, C, C]))
    fx.append(("close-first complex", 1, [O, 5, C, C, O, 5, C]))
    fx.append(("opener surplus", 1, [O, 5, O, 6, C]))
    fx.append(("START on plain line inside region", 1, [O, 5, C]))
    fx.append(("START on closer", 0, [1, O, 5, C]))
    fx.append(("START on depth-1 opener", 0, [O, 5, C]))
    fx.append(("V6 menu with START on nested opener",
               flat_index(" OSM: %s"), menu_masked(V6_MENU)))
    return fx


def summ_fixtures():
    v6g = menu_masked(V6_MENU)
    base = menu_stdsel(V6_MENU)

    def sel(**kw):
        s = list(base)
        for k, v in kw.items():
            s[int(k[1:])] = v
        return s

    hdmi = flat_index(" HDMI: %s")               # 54: the HDMI submenu opener
    adv = flat_index(" Advanced Settings")       # 157: the Advanced opener
    osm = flat_index(" OSM: %s")                 # 161: the OSM scaling opener
    fx = []
    # HDMI heading: nothing selected of its own; child skipped; the selected
    # Scanlines line inside the child must NOT leak: ends at own closer
    fx.append(("HDMI region empty -> own closer", hdmi, v6g,
               sel(i57=0, i58=0, i64=0, i65=0)))
    # HDMI heading with 4:3 576p 50 Hz selected -> found 59
    fx.append(("HDMI region finds 4:3 PAL", hdmi, v6g, sel(i57=0, i59=1)))
    # Advanced Settings: no radio group of its own at all
    fx.append(("Advanced has no own radio group", adv, v6g, base))
    # OSM scaling: default -> 164
    fx.append(("OSM scaling default", osm, v6g, base))
    # walk that runs off the end of the whole menu (heading = a closer)
    fx.append(("end of menu reached", 2, [O, 1, C], [0, 0, 0]))
    return fx


def equiv_fixtures():
    fx = []
    fx.append(("current C64 menu", menu_masked(CUR_MENU)))
    fx.append(("adjacent regions", [0x1000, 5, O, 6, C, O, 7, C, 8]))
    fx.append(("region at flat 0", [O, 5, C, 7]))
    fx.append(("region at end", [7, O, 5, C]))
    fx.append(("empty region", [1, O, C, 2]))
    fx.append(("two regions same group ids", [1, O, 1, C, O, 1, C, 1]))
    fx.append(("plain only", [1, 0, 0x1000, 2, 0x8003]))
    rng = random.Random(0xC64)
    palette = [0x0000, 0x1000]
    for _ in range(8):
        palette.append(rng.randint(1, 254))
        palette.append(0x8000 | rng.randint(1, 254))
    for k in range(150):
        words = []
        for _ in range(rng.randint(0, 5)):          # leading plain lines
            words.append(rng.choice(palette))
        for _ in range(rng.randint(0, 5)):          # regions
            words.append(O)
            for _ in range(rng.randint(0, 6)):
                words.append(rng.choice(palette))
            words.append(C)
            for _ in range(rng.randint(0, 3)):      # gap (0 = adjacent)
                words.append(rng.choice(palette))
        if not words:
            words = [1]
        if len(words) > 254:
            words = words[:254]
            # keep it balanced after truncation
            depth = 0
            for w in words:
                c = classify(w)
                depth += 1 if c == "open" else (-1 if c == "close" else 0)
            words += [C] * depth
        fx.append(("random legacy %d" % k, words))
    return fx


# ---------------------------------------------------------------------------
# Expected outputs
# ---------------------------------------------------------------------------


def expect_struct():
    lines = []
    for k, (name, start, groups) in enumerate(struct_fixtures()):
        lines.append("FX %04X" % k)
        v = validate(groups, start)
        if v[0] == "ok":
            lines.append("V OK R=%04X H=%04X" % (v[1], v[2]))
            levels = range(0, num_regions(groups) + 1)
        else:
            lines.append("V ERR C=%04X I=%04X" % (v[1], v[2]))
            levels = [0]
        for lv in levels:
            b = build_new(groups, lv)
            if "err" in b:
                lines.append("B L=%04X ERR I=%04X" % (lv, b["err"]))
            else:
                words = "".join(" %04X" % w for w in b["arr"])
                lines.append("B L=%04X C=%04X P=%04X O=%04X W=%s"
                             % (lv, b["vis"], b["parent"], b["opener"], words))
    for k, (name, heading, groups, stdsel) in enumerate(summ_fixtures()):
        r = summ_scan(groups, heading, stdsel)
        if r[0] == "found":
            lines.append("S %04X FOUND I=%04X" % (k, r[1]))
        else:
            lines.append("S %04X ERR C=%04X" % (k, r[1]))
    lines.append("DONE")
    return "\n".join(lines) + "\n"


def expect_equiv():
    lines = []
    for k, (name, groups) in enumerate(equiv_fixtures()):
        for lv in range(0, num_regions(groups) + 1):
            o = build_old(groups, lv)
            n = build_new(groups, lv)
            ok = (o is not None and "arr" in n and o["arr"] == n["arr"]
                  and o["vis"] == n["vis"])
            assert ok, "model self-check failed: %s level %d" % (name, lv)
            lines.append("E %04X L=%04X OK" % (k, lv))
    lines.append("DONE")
    return "\n".join(lines) + "\n"


def expect_deps():
    lines = ["P8 OK"]                              # OPTM_DEPS_VAL preserves R8 (#5)
    for k, (name, g, raw) in enumerate(deps_resolve_fixtures()):
        res = resolve_deps(g, raw)
        words = "".join(" %04X" % w for w in res)
        lines.append("R %04X W=%s" % (k, words))
    for k, (name, g, raw, sp) in enumerate(deps_val_fixtures()):
        r = validate_deps(g, raw, sp)
        if r[0] == "ok":
            lines.append("V %04X OK" % k)
        else:
            lines.append("V %04X ERR C=%04X I=%04X" % (k, r[1], r[2]))
    for k, (name, g, res, sd, lv) in enumerate(deps_build_fixtures()):
        b = build_new(g, lv, res, sd)
        words = "".join(" %04X" % w for w in b["arr"])
        lines.append("B %04X C=%04X W=%s" % (k, b["vis"], words))
    for k, (name, g, res, sd, h) in enumerate(deps_summ_fixtures()):
        r = summ_scan(g, h, sd, res)
        if r[0] == "found":
            lines.append("D %04X FOUND I=%04X" % (k, r[1]))
        else:
            lines.append("D %04X ERR C=%04X" % (k, r[1]))
    for k, (name, g, raw) in enumerate(deps_minhid_fixtures()):
        lines.append("M %04X S=%04X" % (k, deps_minhid(g, raw)))
    lines.append("DONE")
    return "\n".join(lines) + "\n"


def emit_deps_asm(path):
    L = ["; AUTOGENERATED by menu_test.py gen - DO NOT EDIT", ""]

    def block(prefix, fxs, extra):
        out = ["", "%-15s .EQU %d" % (prefix + "_CNT", len(fxs))]
        out += dw_label_table(prefix + "_TAB",
                              ["%s_%04X" % (prefix, k) for k in range(len(fxs))])
        for k, fx in enumerate(fxs):
            arrays, head = extra(fx)
            out.append("")
            out.append("; %s %d: %s" % (prefix, k, fx[0]))
            out.append("%-15s .DW     %s" % ("%s_%04X" % (prefix, k), head))
            for a in arrays:
                out += dw_lines(a)
        return out

    L += block("DR", deps_resolve_fixtures(),
               lambda fx: ([fx[1], fx[2]], "0x%04X" % len(fx[1])))
    L += block("DV", deps_val_fixtures(),
               lambda fx: ([fx[1], fx[2], fx[3]], "0x%04X" % len(fx[1])))
    L += block("DB", deps_build_fixtures(),
               lambda fx: ([fx[1], fx[2], fx[3]],
                           "0x%04X, 0x%04X" % (len(fx[1]), fx[4])))
    L += block("DS", deps_summ_fixtures(),
               lambda fx: ([fx[1], fx[2], fx[3]],
                           "0x%04X, 0x%04X" % (len(fx[1]), fx[4])))
    L += block("DM", deps_minhid_fixtures(),
               lambda fx: ([fx[1], fx[2]], "0x%04X" % len(fx[1])))
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def nav_start():
    """The flat index of the OPTM_G_START line of the V6 menu."""
    return next(i for i, (_, _, f) in enumerate(V6_MENU) if "START" in f)


def nav_script():
    """Build the nav-test key script with the simulator and return
    (keys, expected trace lines). The testbed record keeps the dependency
    feature OFF for this scenario (all dependent lines stay visible); the
    dependency-aware paths of OPTM_RUN are covered by scenario 3."""
    g = menu_masked(V6_MENU)
    s = NavSim(g, menu_stdsel(V6_MENU), nav_start(),
               labels=[t for t, _, _ in V6_MENU])

    s.run_start()                   # the testbed draws before OPTM_RUN
    assert s.cursor == 2            # start line: visible and selectable
    s.feed(KEY_UP)                  # wrap to "Close Menu" (189)
    assert s.cursor == 189
    s.feed(KEY_DOWN)                # wrap back to mount line (2)
    assert s.cursor == 2
    s.until(KEY_DOWN, 7)            # to "Drive Settings" (issue #93)
    s.feed(KEY_SELECT)              # enter region 1
    assert (s.level, s.cursor) == (1, 10)
    s.until(KEY_DOWN, 12)           # to "Internal 1581"
    s.feed(KEY_SELALT)              # radio-select the drive-8 mode via Space
    s.feed(KEY_MENUUP)              # pop to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 7)
    s.until(KEY_DOWN, 35)           # to "Model: %s"
    s.feed(KEY_SELECT)              # enter region 2
    assert (s.level, s.cursor) == (2, 38)
    s.feed(KEY_DOWN)                # NTSC
    s.feed(KEY_SELALT)              # radio-select NTSC via Space
    s.feed(KEY_MENUUP)              # pop to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 35)
    s.until(KEY_DOWN, 54)           # to "HDMI: %s"
    s.feed(KEY_SELECT)              # enter region 3
    assert (s.level, s.cursor) == (3, 57)
    s.feed(0x8000 | KEY_DOWN)       # background redraw + down
    s.until(KEY_DOWN, 67)           # to nested "HDMI: %s" (filter)
    s.feed(KEY_SELECT)              # enter region 4 (depth 2)
    assert (s.level, s.cursor) == (4, 70)
    s.until(KEY_DOWN, 79)           # to the " Back" closer line
    s.feed(KEY_SELECT)              # leave via the closer
    assert (s.level, s.cursor) == (3, 67)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 54)
    s.until(KEY_DOWN, 131)          # to "Volume: %s" - entering this region
    s.feed(KEY_SELECT)              # is the regression case for the percent-
    assert (s.level, s.cursor) == (8, 134)   # terminated-label scanner bug
    s.feed(KEY_MENUUP)              # back to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 131)
    s.until(KEY_DOWN, 157)          # to "Advanced Settings"
    s.feed(KEY_SELECT)              # enter region 9
    assert (s.level, s.cursor) == (9, 160)
    s.feed(KEY_SELECT)              # single-select GEOS Real-Time-Clock on
    s.feed(KEY_SELECT)              # and off again
    s.until(KEY_DOWN, 176)          # to "VIC-II: %s"
    s.feed(KEY_SELECT)              # enter region 11 (depth 2)
    assert (s.level, s.cursor) == (11, 179)
    s.feed(0x8000 | KEY_UP)         # redraw + up: wraps within the view
    assert s.cursor == 183          # lands on the closer line
    r = s.feed(KEY_CLOSE)           # Help: close the OSM
    assert r == "close"
    # reopen: same level and cursor (persistence)
    assert (s.level, s.cursor) == (11, 183)
    s.run_start()                   # the testbed draws before OPTM_RUN
    s.feed(KEY_MENUUP)              # pop to region 9
    assert (s.level, s.cursor) == (9, 176)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 157)
    r = s.feed(KEY_MENUUP)          # Run/Stop at main: close
    assert r == "close"
    return s.keys, s.trace


NAV2_LABELS = [" 50%", " A:%s", " B:%s", " x", " back", " back",
               " C", " back", " quit"]


def nav2_script():
    """Second nav scenario on a synthetic menu, covering the enter-scan stop
    positions of spec section 10 item 4 that the V6 menu cannot provide:
    a region whose FIRST content is a nested child opener (this is the only
    input that distinguishes the new 0x40FF stop mask in _OPTM_RUN_SM_2 from
    the old 0x00FF one - found by mutation testing), and an empty region
    (the scan must stop on the closer). The labels additionally place a
    percent-terminated label (idx 0) BEFORE two %s lines, which guards the
    OPTM_SHOW scanner against the percent-eats-newline desync bug."""
    groups = [
        0x0001,   # 0: radio id 1 (START line, visible at main)
        0xC000,   # 1: open region A
        0xC000,   # 2: open region B - the FIRST content of A
        0x0002,   # 3: radio id 2
        0xC0FF,   # 4: close B
        0xC0FF,   # 5: close A
        0xC000,   # 6: open region C - empty
        0xC0FF,   # 7: close C
        0x00FF,   # 8: bare "Close Menu"
    ]
    stdsel = [1, 0, 0, 1, 0, 0, 0, 0, 0]
    s = NavSim(groups, stdsel, 0, labels=NAV2_LABELS)
    s.run_start()                   # the testbed draws before OPTM_RUN
    s.feed(KEY_DOWN)                # to the opener of A
    assert s.cursor == 1
    s.feed(KEY_SELECT)              # enter A: scan must STOP on the child
    assert (s.level, s.cursor) == (1, 2)   # opener of B (kills the 0x00FF
                                           # enter-scan mutant)
    s.feed(KEY_SELECT)              # enter B
    assert (s.level, s.cursor) == (2, 3)
    s.feed(KEY_MENUUP)              # pop to A
    assert (s.level, s.cursor) == (1, 2)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 1)
    s.feed(KEY_DOWN)                # to the opener of C
    assert s.cursor == 6
    s.feed(KEY_SELECT)              # enter the EMPTY region C: the scan
    assert (s.level, s.cursor) == (3, 7)   # stops on its own closer
    s.feed(KEY_SELECT)              # leave C via the closer line
    assert (s.level, s.cursor) == (0, 6)
    r = s.feed(KEY_MENUUP)          # Run/Stop at main: close
    assert r == "close"
    return groups, stdsel, s.keys, s.trace


NAV3_LABELS = [" Tog", " D:%s", " E:%s", " S:%s", " F", " G", " back", " quit"]


NAV3_START = 1                          # deliberately a dep-hidden line: the
                                        # OPTM_RUN entry normalization must
                                        # advance to the next selectable line


def nav3_script():
    """Dependency scenario in the live OPTM_RUN state machine: a single-select
    mother (idx 0) with a same-view dependent (idx 1) drives the real-time
    redraw (OPTM_DEPS_AFFECTS -> OPTM_SHOW); a submenu whose first content
    (idx 4) is dependent drives the enter-scan dependency skip
    (_OPTM_RUN_SM_2); the start cursor sits on the dep-hidden idx 1 and
    drives the _OPTM_RUN_INI* entry normalization. All three are no-ops for
    the deps-off scenarios 1 and 2."""
    groups = [
        0x8001,   # 0 single-select toggle, mother gid 1
        0x0002,   # 1 dependent radio gid 2, mask 0b10: same view as the mother
        0x0003,   # 2 radio gid 3 (always visible)
        0xC000,   # 3 open region 1 (submenu " S:%s")
        0x0004,   # 4 dependent radio gid 4, mask 0b10: first content of reg. 1
        0x0005,   # 5 radio gid 5 (always visible)
        0xC0FF,   # 6 close region 1
        0x00FF,   # 7 Close Menu
    ]
    raw = [0] * 8
    raw[1] = 0x1000 | (0b10 << 8) | 1   # dep(gid 1, mask 0b10): visible if ON
    raw[4] = 0x1000 | (0b10 << 8) | 1
    stdsel = [0] * 8                    # toggle OFF
    s = NavSim(groups, stdsel, NAV3_START, labels=NAV3_LABELS, raw_deps=raw)
    s.run_start()                       # normalization: idx1 is dep-hidden ->
    assert s.cursor == 2                # the cursor advances to idx2
    s.until(KEY_UP, 0)                  # to the toggle (skips hidden idx1)
    s.feed(KEY_SELECT)                  # toggle ON  -> redraw, idx1 appears
    s.feed(KEY_SELECT)                  # toggle OFF -> redraw, idx1 hidden
    s.until(KEY_DOWN, 3)                # to the submenu opener
    s.feed(KEY_SELECT)                  # enter: idx4 dep-hidden (OFF), scan
    assert (s.level, s.cursor) == (1, 5)   # skips it -> lands on idx5
    s.feed(KEY_MENUUP)                  # back to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 3)
    s.until(KEY_UP, 0)                  # back to the toggle
    s.feed(KEY_SELECT)                  # toggle ON
    s.until(KEY_DOWN, 3)               # to the opener (idx1 is visible now)
    s.feed(KEY_SELECT)                  # enter: idx4 now visible -> lands there
    assert (s.level, s.cursor) == (1, 4)
    s.feed(KEY_MENUUP)
    assert (s.level, s.cursor) == (0, 3)
    r = s.feed(KEY_MENUUP)              # Run/Stop at main: close
    assert r == "close"
    return groups, stdsel, raw, s.keys, s.trace


def expect_nav():
    _, trace = nav_script()
    _, _, _, trace2 = nav2_script()
    _, _, _, _, trace3 = nav3_script()
    return ("\n".join(trace) + "\nN2\n" + "\n".join(trace2)
            + "\nN3\n" + "\n".join(trace3) + "\nDONE\n")


# ---------------------------------------------------------------------------
# .asm emission
# ---------------------------------------------------------------------------


def dw_lines(words, per=8):
    out = []
    for i in range(0, len(words), per):
        chunk = ", ".join("0x%04X" % w for w in words[i:i + per])
        out.append("                .DW     %s" % chunk)
    return out


def dw_label_table(label, names, per=6):
    out = []
    for i in range(0, len(names), per):
        chunk = ", ".join(names[i:i + per])
        head = label if i == 0 else "                "
        out.append("%-16s.DW     %s" % (head, chunk))
    return out


def emit_fixtures_asm(path):
    L = ["; AUTOGENERATED by menu_test.py gen - DO NOT EDIT", ""]
    sf = struct_fixtures()
    L.append("FXT_CNT         .EQU %d" % len(sf))
    L += dw_label_table("FXT_TAB", ["FXT_%04X" % k for k in range(len(sf))])
    for k, (name, start, groups) in enumerate(sf):
        L.append("")
        L.append("; fixture %d: %s" % (k, name))
        L.append("FXT_%04X        .DW     0x%04X, 0x%04X" %
                 (k, start, len(groups)))
        L += dw_lines(groups)
    sm = summ_fixtures()
    L.append("")
    L.append("SUM_CNT         .EQU %d" % len(sm))
    L += dw_label_table("SUM_TAB", ["SUM_%04X" % k for k in range(len(sm))])
    for k, (name, heading, groups, stdsel) in enumerate(sm):
        L.append("")
        L.append("; summary fixture %d: %s" % (k, name))
        L.append("SUM_%04X        .DW     0x%04X, 0x%04X" %
                 (k, heading, len(groups)))
        L += dw_lines(groups)
        L += dw_lines(stdsel)
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def emit_equiv_asm(path):
    fx = equiv_fixtures()
    L = ["; AUTOGENERATED by menu_test.py gen - DO NOT EDIT", ""]
    L.append("EQV_CNT         .EQU %d" % len(fx))
    L += dw_label_table("EQV_TAB", ["EQV_%04X" % k for k in range(len(fx))])
    for k, (name, groups) in enumerate(fx):
        L.append("")
        L.append("; fixture %d: %s" % (k, name))
        L.append("EQV_%04X        .DW     0x%04X, 0x%04X" %
                 (k, len(groups), num_regions(groups)))
        L += dw_lines(groups)
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def ascii_item_lines(label, labels):
    """Emit a complete OPTM_ITEMS-style string: every menu line followed by
    a literal two-character backslash-n, zero-terminated at the very end -
    identical to what the firmware reads from config.vhd. CAUTION: the
    newline must NOT be written as "\\n" inside an .ASCII_* literal: qasm
    translates that escape into CR LF (0x0D 0x0A), while the menu system
    expects the two characters backslash (0x5C) and lower-case n (0x6E),
    exactly as a VHDL string stores them. Hence the explicit .DW pair."""
    out = [label]
    for t in labels:
        if t:
            out.append('                .ASCII_P "%s"' % t)
        out.append("                .DW     0x005C, 0x006E")
    out.append("                .DW     0x0000")
    return out


def emit_nav_asm(path):
    keys, _ = nav_script()
    g = menu_masked(V6_MENU)
    sd = menu_stdsel(V6_MENU)
    g2, sd2, keys2, _ = nav2_script()
    L = ["; AUTOGENERATED by menu_test.py gen - DO NOT EDIT", ""]
    L.append("NAV_N           .EQU %d" % len(g))
    L.append("NAV_START       .EQU %d" % nav_start())
    L.append("NAV_GROUPS")
    L += dw_lines(g)
    L.append("NAV_STDSEL_DEF")
    L += dw_lines(sd)
    L += ascii_item_lines("NAV_ITEMS", [t for t, _, _ in V6_MENU])
    L.append("NAV_SCRIPT_CNT  .EQU %d" % len(keys))
    L.append("NAV_SCRIPT")
    L += dw_lines(keys)
    L.append("")
    L.append("; scenario 2: synthetic menu, see nav2_script() in menu_test.py")
    L.append("NAV2_N          .EQU %d" % len(g2))
    L.append("NAV2_START      .EQU 0")
    L.append("NAV2_GROUPS")
    L += dw_lines(g2)
    L.append("NAV2_STDSEL_DEF")
    L += dw_lines(sd2)
    L += ascii_item_lines("NAV2_ITEMS", NAV2_LABELS)
    L.append("NAV2_SCRIPT_CNT .EQU %d" % len(keys2))
    L.append("NAV2_SCRIPT")
    L += dw_lines(keys2)
    g3, sd3, raw3, keys3, _ = nav3_script()
    res3 = resolve_deps(g3, raw3)
    L.append("")
    L.append("; scenario 3: dependency menu, see nav3_script() in menu_test.py")
    L.append("NAV3_N          .EQU %d" % len(g3))
    L.append("NAV3_START      .EQU %d" % NAV3_START)
    L.append("NAV3_GROUPS")
    L += dw_lines(g3)
    L.append("NAV3_STDSEL_DEF")
    L += dw_lines(sd3)
    L.append("NAV3_DEPS")                    # resolved dependency array
    L += dw_lines(res3)
    L += ascii_item_lines("NAV3_ITEMS", NAV3_LABELS)
    L.append("NAV3_SCRIPT_CNT .EQU %d" % len(keys3))
    L.append("NAV3_SCRIPT")
    L += dw_lines(keys3)
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


# ---------------------------------------------------------------------------
# VHDL emission and verification (V6 menu)
# ---------------------------------------------------------------------------

# C_MENU_* constants for mega65.vhd: name -> (label substring, group, ordinal
# within group). Ordinal disambiguates radio members that share a label.
C_MENU = [
    ("C_MENU_DRV8_IMG_MNT", "DRV8_MODE", 0),
    ("C_MENU_DRV8_IMG_ALW", "DRV8_MODE", 1),
    ("C_MENU_DRV8_1581",    "DRV8_MODE", 2),
    ("C_MENU_DRV8_OFF",     "DRV8_MODE", 3),
    ("C_MENU_DRV8_UNMOUNT", "DRV8_UNMOUNT", 0),
    ("C_MENU_DRV9_IMG_MNT", "DRV9_MODE", 0),
    ("C_MENU_DRV9_IMG_ALW", "DRV9_MODE", 1),
    ("C_MENU_DRV9_1581",    "DRV9_MODE", 2),
    ("C_MENU_DRV9_OFF",     "DRV9_MODE", 3),
    ("C_MENU_DRV9_UNMOUNT", "DRV9_UNMOUNT", 0),
    ("C_MENU_EXP_PORT_HW",  "EXP_PORT", 0),
    ("C_MENU_SIM_CRT",      "EXP_PORT", 1),
    ("C_MENU_SIM_REU",      "REU", 0),
    ("C_MENU_FLIP_JOYS",    "FLIP_JOYS", 0),
    ("C_MENU_MONO_6581",    "SID_SETUP", 0),
    ("C_MENU_MONO_8580",    "SID_SETUP", 1),
    ("C_MENU_STEREO_L6R6",  "SID_SETUP", 2),
    ("C_MENU_STEREO_L6R8",  "SID_SETUP", 3),
    ("C_MENU_STEREO_L8R6",  "SID_SETUP", 4),
    ("C_MENU_STEREO_L8R8",  "SID_SETUP", 5),
    ("C_MENU_STEREO_R_D420", "SID_PORT", 0),
    ("C_MENU_STEREO_R_D500", "SID_PORT", 1),
    ("C_MENU_STEREO_R_DE00", "SID_PORT", 2),
    ("C_MENU_STEREO_R_DF00", "SID_PORT", 3),
    ("C_MENU_IMPROVE_AUDIO", "IMPROVE_AUDIO", 0),
    ("C_MENU_8521",         "CIA_8521", 0),
    ("C_MENU_IEC",          "IEC", 0),
    ("C_MENU_KERNAL_STD",   "KERNAL_MODES", 0),
    ("C_MENU_KERNAL_GS",    "KERNAL_MODES", 1),
    ("C_MENU_KERNAL_JAPAN", "KERNAL_MODES", 2),
    ("C_MENU_KERNAL_JIFFY", "KERNAL_MODES", 3),
    ("C_MENU_HDMI_16_9_50", "HDMI_MODES_PAL", 0),
    ("C_MENU_HDMI_4_3_50",  "HDMI_MODES_PAL", 1),
    ("C_MENU_HDMI_5_4_50",  "HDMI_MODES_PAL", 2),
    ("C_MENU_HDMI_16_9_5994", "HDMI_MODES_NTSC", 0),
    ("C_MENU_HDMI_4_3_5994",  "HDMI_MODES_NTSC", 1),
    ("C_MENU_HDMI_5_4_5994",  "HDMI_MODES_NTSC", 2),
    ("C_MENU_HDMI_FF",      "HDMI_FF", 0),
    ("C_MENU_HDMI_FF_NTSC", "HDMI_FF_NTSC", 0),
    ("C_MENU_HDMI_DVI",     "HDMI_DVI", 0),
    ("C_MENU_HDMI_FLT_NO_FILTER", "HDMI_FILTER", 0),
    ("C_MENU_HDMI_FLT_SHARP",     "HDMI_FILTER", 1),
    ("C_MENU_HDMI_FLT_BICUBIC",   "HDMI_FILTER", 2),
    ("C_MENU_HDMI_FLT_SMOOTH",    "HDMI_FILTER", 3),
    ("C_MENU_HDMI_FLT_LANCZOS",   "HDMI_FILTER", 4),
    ("C_MENU_HDMI_FLT_SCANLINES", "HDMI_FILTER", 5),
    ("C_MENU_HDMI_FLT_CRT_SVIDEO", "HDMI_FILTER", 6),
    ("C_MENU_HDMI_FLT_CRT_COMPOSITE", "HDMI_FILTER", 7),
    ("C_MENU_HDMI_ZOOM",    "HDMI_ZOOM", 0),
    ("C_MENU_HDMI_RAW50",   "HDMI_RAW50", 0),
    ("C_MENU_VGA_STD",      "VGA_MODES", 0),
    ("C_MENU_VGA_15KHZHSVS", "VGA_MODES", 1),
    ("C_MENU_VGA_15KHZCS",  "VGA_MODES", 2),
    ("C_MENU_MACHINE_PAL",  "MACHINE_MODE", 0),
    ("C_MENU_MACHINE_NTSC", "MACHINE_MODE", 1),
    ("C_MENU_TURBO_OFF",    "TURBO_MODE", 0),
    ("C_MENU_TURBO_C128",   "TURBO_MODE", 1),
    ("C_MENU_TURBO_SMART",  "TURBO_MODE", 2),
    ("C_MENU_TURBO_2X",     "TURBO_SPEED", 0),
    ("C_MENU_TURBO_3X",     "TURBO_SPEED", 1),
    ("C_MENU_TURBO_4X",     "TURBO_SPEED", 2),
    ("C_MENU_RTC_GEOS",     "RTC_GEOS", 0),
    ("C_MENU_VICII_NMOS",   "VICII_MODEL", 0),
    ("C_MENU_VICII_HMOS",   "VICII_MODEL", 1),
    ("C_MENU_VICII_OLDHMOS", "VICII_MODEL", 2),
]


def group_members(menu, gname):
    return [i for i, (_, g, _) in enumerate(menu) if g == gname]


def c_menu_values():
    """name -> flat index in the V6 menu, derived independently from labels
    and group ordinals."""
    out = {}
    for name, gname, ordinal in C_MENU:
        members = group_members(V6_MENU, gname)
        out[name] = members[ordinal]
    return out


def volume_indices():
    return group_members(V6_MENU, "VOLUME")


def osm_scaling_range():
    m = group_members(V6_MENU, "OSM_MODE")
    assert m == list(range(m[0], m[0] + len(m)))
    return (m[-1], m[0])


def vhdl_tb_vectors():
    """(28-bit address, expected 16-bit data) pairs for the SEL_OPTM_DEPS
    decoder, derived from the golden model. Closes the VHDL->QNICE raw-word
    contract that verify()/run() otherwise never exercise (#2)."""
    raw = menu_deps_raw(V6_MENU, V6_DEPS)
    SEL = 0x0313
    vecs = []
    for idx in sorted(V6_DEPS):                   # every dependent line
        vecs.append((SEL << 12 | idx, raw[idx]))
    vecs.append((SEL << 12 | 0, 0x0000))          # a non-dependent line -> 0
    vecs.append((SEL << 12 | 0xFFF, 0x2DEF))      # feature probe: dep format 2
    vecs.append((0x0999 << 12 | 0, 0xEEEE))       # unknown selector -> default
    return vecs


def emit_vhdl_tb(path):
    """Generate a self-checking ghdl testbench for the real config.vhd
    SEL_OPTM_DEPS decoder (the VHDL OPTM_DEP() producer)."""
    vecs = vhdl_tb_vectors()
    rows = ",\n".join('    (x"%07X", x"%04X")' % (a, d) for a, d in vecs)
    L = '''-- AUTOGENERATED by menu_test.py gen - DO NOT EDIT
-- Self-checking testbench for the config.vhd SEL_OPTM_DEPS decoder. Drives the
-- real DUT and asserts the raw per-line dependency word against the golden
-- model (menu_deps_raw). Run with: python3 menu_test.py ghdl
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity config_deps_tb is
end entity config_deps_tb;

architecture sim of config_deps_tb is
   signal clk_i     : std_logic := '0';
   signal address_i : std_logic_vector(27 downto 0) := (others => '0');
   signal data_o    : std_logic_vector(15 downto 0);
   signal done      : boolean := false;
   type vec_t is record
      addr : std_logic_vector(27 downto 0);
      dat  : std_logic_vector(15 downto 0);
   end record;
   type vec_array is array (natural range <>) of vec_t;
   constant VECS : vec_array := (
%s
   );
begin
   dut : entity work.config
      port map (clk_i => clk_i, address_i => address_i, data_o => data_o);

   clk_proc : process
   begin
      while not done loop
         clk_i <= '0'; wait for 5 ns;
         clk_i <= '1'; wait for 5 ns;
      end loop;
      wait;
   end process;

   stim : process
      variable errors : integer := 0;
   begin
      for i in VECS'range loop
         address_i <= VECS(i).addr;
         wait until falling_edge(clk_i);
         wait for 1 ns;
         if data_o /= VECS(i).dat then
            report "DEPS_TB MISMATCH at vector " & integer'image(i)
               severity error;
            errors := errors + 1;
         end if;
      end loop;
      done <= true;
      if errors = 0 then
         report "DEPS_TB OK" severity note;
      else
         report "DEPS_TB FAIL" severity failure;
      end if;
      wait;
   end process;
end architecture sim;
''' % rows
    with open(path, "w") as f:
        f.write(L)


def vhdl_check():
    """Compile config.vhd + the generated testbench with ghdl and run it.
    Skips gracefully (returns 0) when ghdl is not installed."""
    import shutil
    import tempfile
    ghdl = shutil.which("ghdl")
    if not ghdl:
        print("VHDL DECODER TB: SKIP (ghdl not found)")
        return 0
    tb = os.path.join(HERE, "config_deps_tb.vhd")
    emit_vhdl_tb(tb)
    cfg = os.path.join(REPO, "CORE/vhdl/config.vhd")
    work = tempfile.mkdtemp(prefix="ghdl_deps_")
    opts = ["--std=08", "--workdir=" + work]
    try:
        for step in ([[ghdl, "-a"] + opts + [cfg, tb],
                      [ghdl, "-e"] + opts + ["config_deps_tb"],
                      [ghdl, "-r"] + opts + ["config_deps_tb",
                                             "--assert-level=error"]]):
            r = subprocess.run(step, cwd=work, capture_output=True, text=True,
                               timeout=120)
            out = r.stdout + r.stderr
            if r.returncode != 0 or "DEPS_TB FAIL" in out or "MISMATCH" in out:
                print("VHDL DECODER TB: FAIL")
                print(out[-2000:])
                return 1
        if "DEPS_TB OK" not in out:
            print("VHDL DECODER TB: FAIL (no OK marker)")
            print(out[-2000:])
            return 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("VHDL DECODER TB: OK (config.vhd SEL_OPTM_DEPS decoder matches model,"
          " %d vectors)" % len(vhdl_tb_vectors()))
    return 0


def vhdl_blocks():
    words = menu_words(V6_MENU)
    n = len(V6_MENU)
    label_chars = sum(len(t) for t, _, _ in V6_MENU)
    strlen = label_chars + 2 * n
    out = []
    out.append("-- === OPTM_SIZE / OPTM_DY (V6 menu: %d items, %d regions,"
               % (n, num_regions(menu_masked(V6_MENU))))
    out.append("-- === dependency-aware max height %d, strlen incl."
               " two-character newlines: %d)"
               % (dep_aware_max_height(V6_MENU, V6_DEPS), strlen))
    vals = c_menu_values()
    out.append("")
    out.append("-- === C_MENU constants for mega65.vhd ===")
    out.append("constant %-33s: natural := %d;"
               % ("C_MENU_DRV8_1581_LN", flat_index(" 8:Internal 1581        ")))
    out.append("constant %-33s: natural := %d;"
               % ("C_MENU_DRV9_1581_LN", flat_index(" 9:Internal 1581        ")))
    for name, gname, ordinal in C_MENU:
        out.append("constant %-33s: natural := %d;" % (name, vals[name]))
    lo, hi = osm_scaling_range()[1], osm_scaling_range()[0]
    out.append("subtype C_MENU_OSM_SCALING is natural range %d downto %d;"
               % (hi, lo))
    vol = volume_indices()
    out.append("subtype C_MENU_VOLUME is natural range %d downto %d;"
               % (vol[-1], vol[0]))
    return "\n".join(out)


def parse_vhdl_constants(text, prefix):
    """Parse 'constant <name> : <type> := <expr>;' lines. Returns name->expr
    with expressions evaluated against already-parsed names."""
    out = {}
    rx = re.compile(r"constant\s+(" + prefix +
                    r"\w*)\s*:\s*\w+\s*:=\s*([^;]+);")
    for m in rx.finditer(text):
        name, expr = m.group(1), m.group(2)
        expr = expr.split("--")[0].strip()
        expr = expr.replace("16#", "0x").replace("#", "")
        try:
            out[name] = eval(expr, {}, out)
        except Exception:
            pass
    return out


def verify():
    errors = []
    # strip VHDL comments up front: none of the parsed constants contain
    # "--" inside a string literal, but comments may contain ";" which
    # would derail the regexes below
    cfg = re.sub(r"--[^\n]*", "",
                 open(os.path.join(REPO, "CORE/vhdl/config.vhd")).read())
    mega = re.sub(r"--[^\n]*", "",
                  open(os.path.join(REPO, "CORE/vhdl/mega65.vhd")).read())

    # --- config.vhd: OPTM_SIZE, OPTM_DX/DY
    consts = parse_vhdl_constants(cfg, "OPTM_")
    n = len(V6_MENU)
    if consts.get("OPTM_SIZE") != n:
        errors.append("OPTM_SIZE = %s, model says %d"
                      % (consts.get("OPTM_SIZE"), n))
    # OPTM_DY is the dependency-aware maximum of simultaneously visible
    # lines over all views (see the comment above OPTM_DX in config.vhd):
    # per view, mutually exclusive dependent lines - e.g. the per-drive
    # mount/status twins - count as the most that can show at once
    exp_dy = dep_aware_max_height(V6_MENU, V6_DEPS)
    if consts.get("OPTM_DY") != exp_dy:
        errors.append("OPTM_DY = %s, model says %d"
                      % (consts.get("OPTM_DY"), exp_dy))

    # --- config.vhd: group id constants
    gconsts = parse_vhdl_constants(cfg, "OPTM_G_")
    for gname, gid in G.items():
        cn = "OPTM_G_" + gname
        if gconsts.get(cn) != gid:
            errors.append("%s = %s, model says %d"
                          % (cn, gconsts.get(cn), gid))

    # --- config.vhd: OPTM_GROUPS array entries
    m = re.search(r"constant\s+OPTM_GROUPS\s*:\s*OPTM_GTYPE\s*:=\s*\((.*?)\);",
                  cfg, re.S)
    if not m:
        errors.append("OPTM_GROUPS array not found")
    else:
        body = re.sub(r"--[^\n]*", "", m.group(1))
        # split on top-level commas only: an entry may contain commas inside
        # an OPTM_DEP(mother, item) / OPTM_DEP2(mother, a, b) call
        entries, depth, cur = [], 0, ""
        for ch in body:
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            if ch == "," and depth == 0:
                if cur.strip():
                    entries.append(cur.strip())
                cur = ""
            else:
                cur += ch
        if cur.strip():
            entries.append(cur.strip())
        env = dict(gconsts)
        env.update(parse_vhdl_constants(cfg, "OPTM_G"))
        # dependency format 2 helpers: a 4-bit item MASK in bits 28..25
        env["OPTM_DEP"] = lambda m, i: dep_value(m, 2 ** i)
        env["OPTM_DEP2"] = lambda m, a, b: dep_value(m, 2 ** a + 2 ** b)
        vals = []
        for e in entries:
            try:
                # parenthesize: an entry may span multiple source lines
                vals.append(eval("(" + e.replace("16#", "0x").replace("#", "")
                                 + ")", {}, env))
            except Exception:
                errors.append("cannot evaluate OPTM_GROUPS entry %r" % e)
                vals.append(-1)
        model_words = menu_words(V6_MENU, V6_DEPS)
        if len(vals) != len(model_words):
            errors.append("OPTM_GROUPS has %d entries, model says %d"
                          % (len(vals), len(model_words)))
        else:
            for i, (a, b) in enumerate(zip(vals, model_words)):
                if a != b:
                    errors.append(
                        "OPTM_GROUPS[%d] = 0x%X, model says 0x%X (%r)"
                        % (i, a, b, V6_MENU[i][0]))

    # --- config.vhd: OPTM_ITEMS string lines
    m = re.search(r"constant\s+OPTM_ITEMS\s*:\s*string\s*:=(.*?);", cfg, re.S)
    if not m:
        errors.append("OPTM_ITEMS not found")
    else:
        body = re.sub(r"--[^\n]*", "", m.group(1))
        parts = re.findall(r'"((?:[^"]|"")*)"', body)
        items = "".join(parts)
        lines = items.split("\\n")
        if lines and lines[-1] == "":
            lines = lines[:-1]
        model_labels = [t for t, _, _ in V6_MENU]
        if len(lines) != len(model_labels):
            errors.append("OPTM_ITEMS has %d lines, model says %d"
                          % (len(lines), len(model_labels)))
        else:
            for i, (a, b) in enumerate(zip(lines, model_labels)):
                if a != b:
                    errors.append("OPTM_ITEMS[%d] = %r, model says %r"
                                  % (i, a, b))

    # --- mega65.vhd: C_MENU_* values
    mconsts = parse_vhdl_constants(mega, "C_MENU_")
    for name, val in c_menu_values().items():
        if mconsts.get(name) != val:
            errors.append("%s = %s, model says %d"
                          % (name, mconsts.get(name), val))
    # C_MENU_MODEL is the flat index of the " Model: %s" submenu opener (used by
    # the custom SUBMENU_SUMMARY callback); it is not a group member, so check it
    # against the model directly
    model_idx = [i for i, (lbl, _, _) in enumerate(V6_MENU) if lbl == " Model: %s"]
    if not model_idx:
        errors.append("no \" Model: %s\" opener found in the golden model")
    elif mconsts.get("C_MENU_MODEL") != model_idx[0]:
        errors.append("C_MENU_MODEL = %s, model says %d"
                      % (mconsts.get("C_MENU_MODEL"), model_idx[0]))
    # C_MENU_KERNAL is the flat index of the " Kernal: %s" submenu opener (used by
    # the custom SUBMENU_SUMMARY callback to render which JiffyDOS drive ROMs are
    # installed); like C_MENU_MODEL it is an opener, not a group member
    kernal_idx = [i for i, (lbl, _, _) in enumerate(V6_MENU) if lbl == " Kernal: %s"]
    if not kernal_idx:
        errors.append("no \" Kernal: %s\" opener found in the golden model")
    elif mconsts.get("C_MENU_KERNAL") != kernal_idx[0]:
        errors.append("C_MENU_KERNAL = %s, model says %d"
                      % (mconsts.get("C_MENU_KERNAL"), kernal_idx[0]))
    # C_MENU_DRV8_1581_LN / C_MENU_DRV9_1581_LN are the flat indices of the
    # two "Internal 1581" live-status TEXT lines (issue #93). They carry no
    # group, so resolve them from the golden model by label and check that
    # they really are group-less TEXT lines
    for cname, prefix in (("C_MENU_DRV8_1581_LN", " 8:Internal 1581"),
                          ("C_MENU_DRV9_1581_LN", " 9:Internal 1581")):
        idxs = [i for i, (lbl, grp, flg) in enumerate(V6_MENU)
                if lbl.startswith(prefix) and grp is None and not flg]
        if len(idxs) != 1:
            errors.append("no unique %r TEXT line in the golden model" % prefix)
        elif mconsts.get(cname) != idxs[0]:
            errors.append("%s = %s, model says %d"
                          % (cname, mconsts.get(cname), idxs[0]))
    m = re.search(r"subtype\s+C_MENU_OSM_SCALING\s+is\s+natural\s+range\s+"
                  r"(\d+)\s+downto\s+(\d+)", mega)
    hi, lo = osm_scaling_range()
    if not m or (int(m.group(1)), int(m.group(2))) != (hi, lo):
        errors.append("C_MENU_OSM_SCALING range mismatch: model says "
                      "%d downto %d" % (hi, lo))
    m = re.search(r"subtype\s+C_MENU_VOLUME\s+is\s+natural\s+range\s+"
                  r"(\d+)\s+downto\s+(\d+)", mega)
    vol = volume_indices()
    if not m or (int(m.group(1)), int(m.group(2))) != (vol[-1], vol[0]):
        errors.append("C_MENU_VOLUME range mismatch: model says "
                      "%d downto %d" % (vol[-1], vol[0]))

    if errors:
        print("VERIFY FAIL (%d errors):" % len(errors))
        for e in errors:
            print("  -", e)
        return 1
    print("VERIFY OK: config.vhd + mega65.vhd match the golden model")
    print("  OPTM_SIZE=%d  OPTM_DY=%d  regions=%d  C_MENU constants=%d"
          % (n, exp_dy, num_regions(menu_masked(V6_MENU)), len(C_MENU)))
    # additionally drive the real SEL_OPTM_DEPS decoder through ghdl, if present
    return vhdl_check()


# ---------------------------------------------------------------------------
# gen / run
# ---------------------------------------------------------------------------


def expect_live():
    return ("VISIBLE OK\nINVALID OK\nHIDDEN OK\n"
            "CALLBACK OK\nFOREGROUND OK\nINACTIVE OK\nDONE\n")


def gen():
    emit_fixtures_asm(os.path.join(HERE, "menu_test_fixtures.asm"))
    emit_equiv_asm(os.path.join(HERE, "menu_equiv_fixtures.asm"))
    emit_nav_asm(os.path.join(HERE, "menu_nav_fixtures.asm"))
    emit_deps_asm(os.path.join(HERE, "optm_deps_fixtures.asm"))
    for name, content in [("menu_struct_test.exp", expect_struct()),
                          ("menu_equiv_test.exp", expect_equiv()),
                          ("menu_nav_test.exp", expect_nav()),
                          ("optm_deps_test.exp", expect_deps()),
                          ("optm_live_test.exp", expect_live())]:
        with open(os.path.join(HERE, name), "w") as f:
            f.write(content)
    print("generated fixtures and expected outputs")


def run():
    gen()
    asm = os.path.join(REPO, "M2M/QNICE/assembler/asm")
    emu = os.path.join(REPO, "M2M/QNICE/emulator/qnice")
    mon = os.path.join(REPO, "M2M/QNICE/monitor/monitor.out")
    fails = 0
    for tb in ("menu_struct_test", "menu_equiv_test", "menu_nav_test",
               "optm_deps_test", "optm_live_test"):
        r = subprocess.run([asm, tb + ".asm"], cwd=HERE,
                           capture_output=True, text=True, timeout=120)
        listing = os.path.join(HERE, tb + ".out")
        if r.returncode != 0 or not os.path.exists(listing):
            print("ASSEMBLE FAIL:", tb)
            print(r.stdout[-3000:])
            print(r.stderr[-3000:])
            fails += 1
            continue
        try:
            r = subprocess.run([emu, "-b", "0x8000", mon, listing],
                               stdin=subprocess.DEVNULL, capture_output=True,
                               text=True, timeout=120)
        except subprocess.TimeoutExpired:
            print("RUN TIMEOUT:", tb)
            fails += 1
            continue
        # normalize: the monitor's crlf emits LF+CR; drop blank lines and
        # cut everything outside the BEGIN/DONE markers
        glines = [l for l in r.stdout.replace("\r", "").split("\n") if l]
        if "== BEGIN ==" in glines:
            glines = glines[glines.index("== BEGIN ==") + 1:]
        if "DONE" in glines:
            glines = glines[:glines.index("DONE") + 1]
        got = "\n".join(glines) + "\n"
        exp = open(os.path.join(HERE, tb + ".exp")).read()
        if got == exp:
            print("PASS:", tb)
        else:
            print("FAIL:", tb)
            ge, ee = got.split("\n"), exp.split("\n")
            for i in range(max(len(ge), len(ee))):
                a = ge[i] if i < len(ge) else "<missing>"
                b = ee[i] if i < len(ee) else "<missing>"
                if a != b:
                    print("  first diff at line %d:" % (i + 1))
                    print("    got:      %s" % a[:200])
                    print("    expected: %s" % b[:200])
                    break
            with open(os.path.join(HERE, tb + ".got"), "w") as f:
                f.write(got)
            fails += 1
    print("%s" % ("ALL TESTS PASSED" if fails == 0 else
                  "%d TESTBED(S) FAILED" % fails))
    return fails


# ---------------------------------------------------------------------------
# Mutation testing: prove that the dependency code paths are actually covered.
# Each mutant is a behavior-changing single-token edit to the assembly; a
# correct test suite must catch (kill) every one. A surviving mutant marks a
# blind spot. The golden model (this file) is left untouched, so the mutated
# assembly is checked against the correct expectation.
# ---------------------------------------------------------------------------

MUTANTS = [
    ("optm_deps.asm  OPTM_DEP_OK never hides a line",
     "M2M/rom/optm_deps.asm",
     "_ODO_HID        AND     0xFFFB, SR",
     "_ODO_HID        OR      0x0004, SR"),
    ("optm_deps.asm  RESOLVE truncates the item mask to 2 bits",
     "M2M/rom/optm_deps.asm",
     "AND     0x0F00, R5              ; (bits 11-8, as in the raw word)",
     "AND     0x0300, R5              ; (bits 11-8, as in the raw word)"),
    ("optm_deps.asm  VAL skips the dependency-chain fatal",
     "M2M/rom/optm_deps.asm",
     "RBRA    _VAL_E_CHAIN, !Z",
     "RBRA    _VAL_E_CHAIN, Z"),
    ("optm_deps.asm  AFFECTS never triggers a redraw",
     "M2M/rom/optm_deps.asm",
     "_ODA_YES        OR      0x0004, SR",
     "_ODA_YES        AND     0xFFFB, SR"),
    ("menu_struct.asm  builder ignores the dependency predicate",
     "M2M/rom/menu_struct.asm",
     "RBRA    _OSB_PLN_1, !C",
     "RBRA    _OSB_PLN_1, C"),
    ("menu_struct.asm  %s walk ignores the dependency predicate",
     "M2M/rom/menu_struct.asm",
     "RBRA    _OSS_LOOP, !C           ; (no-op when deps are off)",
     "RBRA    _OSS_LOOP, C            ; (no-op when deps are off)"),
    ("menu.asm  enter-cursor scan ignores the dependency predicate",
     "M2M/rom/menu.asm",
     "RBRA    _OPTM_RUN_SM_2, !C",
     "RBRA    _OPTM_RUN_SM_2, C"),
    ("optm_deps.asm  VAL accepts a dependent bare CLOSE line (#1)",
     "M2M/rom/optm_deps.asm",
     "RBRA    _VAL_E_SPEC, Z          ; without the submenu marker bit",
     "RBRA    _VAL_E_SPEC, N          ; without the submenu marker bit"),
    ("optm_deps.asm  OPTM_DEP_OK swaps the single-select mask bits (#4)",
     "M2M/rom/optm_deps.asm",
     "RBRA    _ODO_TSTB0, Z           ; state 0: test mask bit 0",
     "RBRA    _ODO_TSTB0, !Z          ; state 0: test mask bit 0"),
    ("optm_deps.asm  VAL drops its R8-preservation contract (#5)",
     "M2M/rom/optm_deps.asm",
     "MOVE    @SP++, R8\n                AND     0xFFFB, SR              ; clear Carry: success",
     "MOVE    @SP++, R0\n                AND     0xFFFB, SR              ; clear Carry: success"),
    ("optm_deps.asm  OPTM_DEP_OK shows lines whose mother has no selection",
     "M2M/rom/optm_deps.asm",
     "RBRA    _ODO_HID, Z             ; no selected member: hidden",
     "RBRA    _ODO_VIS, Z             ; no selected member: hidden"),
    ("optm_deps.asm  VAL accepts an empty item mask",
     "M2M/rom/optm_deps.asm",
     "CMP     0, R8                   ; empty mask: error\n                RBRA    _VAL_E_IDX, Z",
     "CMP     0, R8                   ; empty mask: error\n                RBRA    _VAL_A_NEXT, Z"),
    ("optm_deps.asm  VAL accepts an out-of-range radio mask bit",
     "M2M/rom/optm_deps.asm",
     "CMP     0, R8                   ; anything left is out of range\n                RBRA    _VAL_E_IDX, !Z",
     "CMP     0, R8                   ; anything left is out of range\n                RBRA    _VAL_A_NEXT, !Z"),
    ("optm_deps.asm  VAL accepts mask bits 2/3 on a single-select mother",
     "M2M/rom/optm_deps.asm",
     "AND     0x000C, R12\n                RBRA    _VAL_E_IDX, !Z",
     "AND     0x000C, R12\n                RBRA    _VAL_A_NEXT, !Z"),
    ("menu.asm  entry normalization inverts the visibility test",
     "M2M/rom/menu.asm",
     "RBRA    _OPTM_RUN_INIA, !C      ; no: advance",
     "RBRA    _OPTM_RUN_INIA, C       ; no: advance"),
    ("menu.asm  entry normalization never accepts a plain selectable line",
     "M2M/rom/menu.asm",
     "AND     0x00FF, R7              ; group id != 0: selectable\n                RBRA    _OPTM_RUN_INID, !Z",
     "AND     0x00FF, R7              ; group id != 0: selectable\n                RBRA    _OPTM_RUN_INID, Z"),
    ("optm_deps.asm  MINHID caps the radio states at 2 instead of 4",
     "M2M/rom/optm_deps.asm",
     "RBRA    _DMH_STATES, N\n                MOVE    4, R7",
     "RBRA    _DMH_STATES, N\n                MOVE    2, R7"),
    ("optm_deps.asm  MINHID first-occurrence skip broken (mothers recounted)",
     "M2M/rom/optm_deps.asm",
     "RBRA    _DMH_NEXT, Z            ; yes: already counted",
     "RBRA    _DMH_SEENN, Z           ; yes: already counted"),
    ("optm_deps.asm  MINHID tests only state 0 of a single-select mother",
     "M2M/rom/optm_deps.asm",
     "MOVE    2, R7                   ; single-select: states 0 and 1",
     "MOVE    1, R7                   ; single-select: states 0 and 1"),
]


def _quiet_run():
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        return run()


def mutate():
    print("baseline (unmutated) suite must pass first:")
    if _quiet_run() != 0:
        print("  BASELINE FAILS - fix the suite before mutation testing")
        return 1
    print("  baseline OK\n")
    fails = 0
    for desc, rel, old, new in MUTANTS:
        path = os.path.join(REPO, rel)
        src = open(path).read()
        if src.count(old) != 1:
            print("SETUP ERROR (%d matches): %s" % (src.count(old), desc))
            fails += 1
            continue
        try:
            with open(path, "w") as f:
                f.write(src.replace(old, new))
            killed = _quiet_run() != 0
        finally:
            with open(path, "w") as f:        # always restore the original
                f.write(src)
        if killed:
            print("KILLED   %s" % desc)
        else:
            print("SURVIVED %s   <-- TEST GAP" % desc)
            fails += 1
    # the suite regenerates its own fixtures on the next run, but restore a
    # clean, unmutated set right away
    gen()
    print("\n%s" % ("ALL %d MUTANTS KILLED" % len(MUTANTS) if fails == 0 else
                    "%d MUTANT(S) SURVIVED OR FAILED SETUP" % fails))
    return fails


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "run"
    if cmd == "gen":
        gen()
    elif cmd == "run":
        sys.exit(1 if run() else 0)
    elif cmd == "vhdl":
        print(vhdl_blocks())
    elif cmd == "verify":
        sys.exit(verify())
    elif cmd == "ghdl":
        sys.exit(vhdl_check())
    elif cmd == "mutate":
        sys.exit(1 if mutate() else 0)
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
