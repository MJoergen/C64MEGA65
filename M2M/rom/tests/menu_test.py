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
# The V6 (#189) menu - source of truth: doc/path-to-OSM-submenus.md section 6
# group ids
# ---------------------------------------------------------------------------

G = dict(
    MOUNT_8=1, MOUNT_9=2, LOAD_PRG=3, EXP_PORT=4, MOUNT_CRT=5, FLIP_JOYS=6,
    SID_SETUP=7, SID_PORT=8, IMPROVE_AUDIO=9, CIA_8521=10, IEC=11,
    KERNAL_MODES=12, HDMI_MODES_PAL=13, HDMI_FF=14, HDMI_DVI=15,
    HDMI_FILTER=16, HDMI_ZOOM=17, VGA_MODES=18, OSM_MODE=19, ABOUT_HELP=20,
    REU=21, MACHINE_MODE=22, TURBO_MODE=23, TURBO_SPEED=24,
    HDMI_MODES_NTSC=25, HDMI_FF_NTSC=26, HDMI_RAW50=27, VOLUME=28,
    RTC_GEOS=29, VICII_MODEL=30, INT1581=31, SIM_RRNET=32,
)

OPEN = ("SUBMENU",)
CLOSE = ("SUBMENU", "CLOSEF")

# Each entry: (label, [group name or None], [flag names])
# The flat index of each entry is its position in this list.
V6_MENU = [
    (" C64 for MEGA65",          None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 8:%s",                    "MOUNT_8", ["MOUNT_DRV", "START"]),
    (" Use internal 1581      ", "INT1581", ["SINGLESEL"]),
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
    (" Model: %s",               None, OPEN),            # region 1
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
    (" Back",                    None, CLOSE),           # close region 1
    (" Flip joystick ports",     "FLIP_JOYS", ["SINGLESEL"]),
    (" HDMI: %s",                None, OPEN),            # region 2
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
    (" HDMI: %s",                None, OPEN),            # region 3 (in 2)
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
    (" Back",                    None, CLOSE),           # close region 3
    (" HDMI: Zoom-in",           "HDMI_ZOOM", ["SINGLESEL"]),
    (" HDMI: Raw 50.1 Hz",       "HDMI_RAW50", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 2
    (" VGA: %s",                 None, OPEN),            # region 4
    (" VGA Display Mode",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "VGA_MODES", ["STDSEL"]),
    ("",                         None, ["LINE"]),
    (" Retro 15 kHz mode",       None, []),
    ("",                         None, ["LINE"]),
    (" 15 kHz with HS/VS",       "VGA_MODES", []),
    (" 15 kHz with CSYNC",       "VGA_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 4
    (" SID: %s",                 None, OPEN),            # region 5
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
    (" Back",                    None, CLOSE),           # close region 5
    (" IEC: Use hardware port",  "IEC", ["SINGLESEL"]),
    (" Kernal: %s",              None, OPEN),            # region 6
    (" Kernal Selection",        None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Standard",                "KERNAL_MODES", ["STDSEL"]),
    (" Games System",            "KERNAL_MODES", []),
    (" Japanese",                "KERNAL_MODES", []),
    (" JiffyDOS",                "KERNAL_MODES", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 6
    (" Volume: %s",              None, OPEN),            # region 7
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
    (" Back",                    None, CLOSE),           # close region 7
    (" Advanced Settings",       None, OPEN),            # region 8
    (" Advanced Settings",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" GEOS Real-Time-Clock",    "RTC_GEOS", ["SINGLESEL"]),
    (" OSM: %s",                 None, OPEN),            # region 9 (in 8)
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
    (" Back",                    None, CLOSE),           # close region 9
    (" CIA: Use 8521 (C64C)",    "CIA_8521", ["SINGLESEL"]),
    (" VIC-II: %s",              None, OPEN),            # region 10 (in 8)
    (" VIC-II model",            None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" 656x/NMOS",               "VICII_MODEL", ["STDSEL"]),
    (" 856x/HMOS",               "VICII_MODEL", []),
    (" 856x/old HMOS",           "VICII_MODEL", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 10
    ("",                         None, ["LINE"]),
    (" RR-Net",                  None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Off",                     "SIM_RRNET", ["STDSEL"]),
    (" On: MK2",                 "SIM_RRNET", []),
    (" On: MK3 & Std ROM",       "SIM_RRNET", []),
    (" On: MK3 & Custom ROM",    "SIM_RRNET", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 8
    ("",                         None, ["LINE"]),
    (" About & Help",            "ABOUT_HELP", ["HELP"]),
    ("",                         None, ["LINE"]),
    (" Close Menu",              None, ["CLOSEF"]),
]

FLAGVAL = dict(STDSEL=F_STDSEL, LINE=F_LINE, START=F_START,
               HEADLINE=F_HEADLINE, SINGLESEL=F_SINGLESEL,
               MOUNT_DRV=F_MOUNT_DRV, HELP=F_HELP, SUBMENU=F_SUBMENU,
               LOAD_ROM=F_LOAD_ROM, CLOSEF=F_CLOSE)

# Smart dependencies (OPTM_DEP, see optm_deps.asm + config.vhd): the high bits
# of an OPTM_GROUPS element encode that a line is only visible while item
# <item> of mother group <gid> is selected. OPTM_G_DEPENDENT is bit 29.
F_DEPENDENT = 0x20000000


def dep_value(gid, item):
    """OPTM_DEP(mother, item) - the value added to an OPTM_GROUPS element."""
    return F_DEPENDENT + (item * 0x02000000) + (gid * 0x00020000)


# flat index -> (mother group name, item index); the dependent lines of the V6
# menu (the PAL/NTSC HDMI variants and the two flicker-free twins + Raw 50.1)
V6_DEPS = {
    37: ("MACHINE_MODE", 0), 38: ("MACHINE_MODE", 1),
    39: ("MACHINE_MODE", 0), 40: ("MACHINE_MODE", 1),
    41: ("MACHINE_MODE", 0), 42: ("MACHINE_MODE", 1),
    44: ("MACHINE_MODE", 0), 45: ("MACHINE_MODE", 1),
    61: ("MACHINE_MODE", 0),
}


def menu_words(menu, deps=None):
    """The full VHDL integer per entry, optionally including OPTM_DEP() bits.
    deps maps flat index -> (mother group name, item index)."""
    out = []
    for i, (label, group, flags) in enumerate(menu):
        v = G[group] if group else 0
        for f in flags:
            v += FLAGVAL[f]
        if deps and i in deps:
            mg, item = deps[i]
            v += dep_value(G[mg], item)
        out.append(v)
    return out


def menu_deps_raw(menu, deps):
    """The raw per-line dependency word as served by SEL_OPTM_DEPS:
    bit 12 = flag, bits 11..8 = item, bits 7..0 = mother group id."""
    out = []
    for i in range(len(menu)):
        if deps and i in deps:
            mg, item = deps[i]
            out.append(0x1000 | (item << 8) | G[mg])
        else:
            out.append(0)
    return out


def resolve_deps(masked_groups, raw_deps):
    """Port of OPTM_DEPS_RESOLVE: raw dependency words -> resolved words
    (bit 15 = valid, bit 8 = expected state, bits 7..0 = controlling line)."""
    out = []
    for w in raw_deps:
        if not (w & 0x1000):                    # not dependent
            out.append(0)
            continue
        mother = w & 0xFF
        item = (w >> 8) & 0xF
        members = [j for j, g in enumerate(masked_groups) if (g & 0xFF) == mother]
        if not members:                          # defensive (boot-validated)
            out.append(0)
            continue
        if masked_groups[members[0]] & 0x8000:   # single-select mother
            ctl, expected = members[0], item
        else:                                     # radio mother
            ctl, expected = members[item], 1
        out.append(0x8000 | (expected << 8) | ctl)
    return out


def dep_ok(i, resolved, stdsel):
    """Port of OPTM_DEP_OK: is line i visible w.r.t. its dependency?"""
    if resolved is None:                          # feature off
        return True
    w = resolved[i]
    if not (w & 0x8000):                          # not dependent
        return True
    ctl = w & 0xFF
    expected = (w >> 8) & 1
    return (1 if stdsel[ctl] else 0) == expected


def menu_masked(menu):
    return [masked(v) for v in menu_words(menu)]


def menu_stdsel(menu):
    return [1 if "STDSEL" in flags else 0 for _, _, flags in menu]


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
            if v and not dep_ok(i, resolved, stdsel):
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
        if not dep_ok(i, resolved, stdsel):
            continue
        if stdsel[i] == 0:
            continue
        return ("found", i)


def num_regions(groups):
    return sum(1 for w in groups if classify(w) == "open")


def validate_deps(groups, raw, special):
    """Port of OPTM_DEPS_VAL. groups are masked words, raw are raw dependency
    words, special[i] != 0 marks mount/load_rom/help/start lines. Returns
    ('ok',) or ('err', class, idx) with class 0..4."""
    n = len(groups)
    for i in range(n):                            # pass A
        if not (raw[i] & 0x1000):
            continue
        if ((groups[i] & 0x4000) or (groups[i] & 0xFF) == 255
                or special[i]):                   # class 4: special line
            return ("err", 4, i)                  # (incl. a bare CLOSE, id 255)
        mother = raw[i] & 0xFF
        item = (raw[i] >> 8) & 0xF
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
        if single:
            if item > 1:                          # class 1: single-sel item > 1
                return ("err", 1, i)
        elif item >= count:                       # class 1: radio item overflow
            return ("err", 1, i)
    for i in range(n):                            # pass B: group uniformity
        gid = groups[i] & 0xFF
        if gid == 0 or gid == 255 or (groups[i] & 0x4000):
            continue
        first = next(j for j in range(n) if (groups[j] & 0xFF) == gid)
        if first != i and raw[first] != raw[i]:   # class 2: mixed group
            return ("err", 2, i)
    return ("ok",)


# A synthetic menu for the dependency testbed: a radio mother (gid 22, members
# at idx 2/3), a single-select mother (gid 14, idx 5) and dependent radio /
# toggle lines inside region 2 (idx 7..11).
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
    13,                 # 7  PAL variant a   dep(22,0)
    25,                 # 8  NTSC variant a  dep(22,1)
    13,                 # 9  PAL variant b   dep(22,0)
    25,                 # 10 NTSC variant b  dep(22,1)
    15,                 # 11 toggle-dependent line dep(14,1)
    0xC0FF,             # 12 close region 2
    0x00FF,             # 13 Close Menu
]
DEP_RAW_MAP = {7: (22, 0), 8: (22, 1), 9: (22, 0), 10: (22, 1), 11: (14, 1)}


def dep_raw_array(rawmap, n):
    raw = [0] * n
    for idx, (m, it) in rawmap.items():
        raw[idx] = 0x1000 | (it << 8) | m
    return raw


def deps_resolve_fixtures():
    """(name, groups, raw) -> expected resolved array via resolve_deps."""
    fx = []
    fx.append(("v6 model", DEP_GROUPS, dep_raw_array(DEP_RAW_MAP, len(DEP_GROUPS))))
    # single-select mother, expected state 0 (visible while OFF)
    g = [0x8000 | 9, 12, 12]
    r = [0, 0x1000 | (0 << 8) | 9, 0x1000 | (1 << 8) | 9]
    fx.append(("single-select off/on", g, r))
    # no dependencies at all
    fx.append(("none", [1, 2, 0x1000], [0, 0, 0]))
    return fx


def deps_val_fixtures():
    """(name, groups, raw, special) -> expected via validate_deps."""
    n = len(DEP_GROUPS)
    base = dep_raw_array(DEP_RAW_MAP, n)
    fx = [("valid v6 model", DEP_GROUPS, base, [0] * n)]
    # class 0: mother does not exist (gid 99)
    r = list(base); r[7] = 0x1000 | (0 << 8) | 99
    fx.append(("mother missing", DEP_GROUPS, r, [0] * n))
    # class 1: radio item index out of range (mother 22 has 2 members)
    r = list(base); r[7] = 0x1000 | (5 << 8) | 22
    # keep the group uniform so the index error is hit, not the mix error
    r[9] = r[7]
    fx.append(("item overflow", DEP_GROUPS, r, [0] * n))
    # class 2: members of one group carry different dependency words
    r = list(base); r[9] = 0x1000 | (1 << 8) | 22    # idx 7 is (22,0), idx 9 (22,1)
    fx.append(("mixed group", DEP_GROUPS, r, [0] * n))
    # class 3: the mother group is itself dependent (chain)
    r = list(base); r[2] = 0x1000 | (0 << 8) | 13; r[3] = r[2]
    fx.append(("dependency chain", DEP_GROUPS, r, [0] * n))
    # class 4: a special (load-ROM) line is dependent
    r = list(base); r[0] = 0x1000 | (0 << 8) | 22
    sp = [0] * n; sp[0] = 1
    fx.append(("special line", DEP_GROUPS, r, sp))
    # class 4: a dependency on the bare main-level Close line (group id 255,
    # no submenu bit) - this is the case the adversarial review caught (#1)
    r = list(base); r[13] = 0x1000 | (0 << 8) | 22
    fx.append(("dependent bare close", DEP_GROUPS, r, [0] * n))
    return fx


def deps_build_fixtures():
    """(name, groups, resolved, stdsel, level) -> expected via build_new."""
    n = len(DEP_GROUPS)
    res = resolve_deps(DEP_GROUPS, dep_raw_array(DEP_RAW_MAP, n))
    # a single-select mother referenced with item 0 = "visible while OFF"; this
    # is the only way a resolved expected-state-0 word (bit 8 = 0) reaches
    # OPTM_DEP_OK at runtime, so it pins the predicate's expected-0 arm (#4)
    res0 = resolve_deps(DEP_GROUPS, dep_raw_array({**DEP_RAW_MAP, 11: (14, 0)}, n))

    def sd(**kw):
        s = [0] * n
        for k, v in kw.items():
            s[int(k[1:])] = v
        return s

    fx = []
    # PAL selected, toggle off: PAL variants visible, NTSC + toggle-dep hidden
    fx.append(("region2 PAL", DEP_GROUPS, res, sd(i2=1, i5=0), 2))
    # NTSC selected, toggle on: NTSC variants + toggle-dep visible
    fx.append(("region2 NTSC", DEP_GROUPS, res, sd(i3=1, i5=1), 2))
    # main level: dependents are hidden by level anyway
    fx.append(("main level", DEP_GROUPS, res, sd(i2=1), 0))
    # dep(G,0): the toggle-dependent line is visible while the toggle is OFF
    fx.append(("dep(G,0) toggle OFF visible", DEP_GROUPS, res0, sd(i2=1, i5=0), 2))
    # dep(G,0): and hidden while the toggle is ON
    fx.append(("dep(G,0) toggle ON hidden", DEP_GROUPS, res0, sd(i2=1, i5=1), 2))
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

    def _redraw(self):
        """A structure-rebuild redraw (the _OPTM_RUN_SM_4 path: enter / leave /
        section-4.3 mother toggle). The runtime rebuilds the (sub)menu structure
        and restarts OPTM_RUN with the kept cursor; if that cursor were on a
        line the rebuild hides, _OPTM_R_F2M would halt with OPTM_F_MENUIDX. The
        feature guarantees it never is (the cursor sits on the just-entered
        line, the opener it left to, or the mother it just toggled - none of
        which a dependency can hide). Assert that invariant here so a future
        regression that strands the cursor is caught by the suite, not by a
        QNICE halt on hardware. (Background OPTM_SET redraws do NOT rebuild the
        struct, so this assertion deliberately does not apply to them - see the
        refuted findings #8/#10 in the adversarial review.)"""
        self._emit_w()
        assert self._visible(self.cursor), (
            "cursor %d hidden after a structure-rebuild redraw at level %d"
            % (self.cursor, self.level))

    def run_start(self):
        """The testbed calls OPTM_SHOW before each OPTM_RUN, like
        HELP_MENU does in production."""
        self._emit_w()

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
                    if (self.g[i] & 0xFF) and dep_ok(i, self.resolved, self.sel):
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
    fx.append(("V6 menu with START on nested opener", 141,
               menu_masked(V6_MENU)))
    return fx


def summ_fixtures():
    v6g = menu_masked(V6_MENU)
    base = menu_stdsel(V6_MENU)

    def sel(**kw):
        s = list(base)
        for k, v in kw.items():
            s[int(k[1:])] = v
        return s

    fx = []
    # heading 34 (HDMI): nothing selected of its own; child skipped; the
    # selected line 55 inside the child must NOT leak: ends at own closer
    fx.append(("HDMI region empty -> own closer", 34, v6g,
               sel(i37=0, i38=0, i44=0, i45=0)))
    # heading 34 with 4:3 PAL selected -> found 39
    fx.append(("HDMI region finds 4:3 PAL", 34, v6g, sel(i37=0, i39=1)))
    # heading 137 (Advanced): no radio group of its own at all
    fx.append(("Advanced has no own radio group", 137, v6g, base))
    # heading 141 (OSM scaling): default -> 144
    fx.append(("OSM scaling default", 141, v6g, base))
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
    with open(path, "w") as f:
        f.write("\n".join(L) + "\n")


def nav_script():
    """Build the nav-test key script with the simulator and return
    (keys, expected trace lines)."""
    g = menu_masked(V6_MENU)
    s = NavSim(g, menu_stdsel(V6_MENU), 2,
               labels=[t for t, _, _ in V6_MENU])

    s.run_start()                   # the testbed draws before OPTM_RUN
    s.feed(KEY_UP)                  # wrap to "Close Menu" (176)
    assert s.cursor == 176
    s.feed(KEY_DOWN)                # wrap back to mount line (2)
    assert s.cursor == 2
    s.until(KEY_DOWN, 15)           # to "Model: %s"
    s.feed(KEY_SELECT)              # enter region 1
    assert (s.level, s.cursor) == (1, 18)
    s.feed(KEY_DOWN)                # NTSC
    s.feed(KEY_SELALT)              # radio-select NTSC via Space
    s.feed(KEY_MENUUP)              # pop to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 15)
    s.until(KEY_DOWN, 34)           # to "HDMI: %s"
    s.feed(KEY_SELECT)              # enter region 2
    assert (s.level, s.cursor) == (2, 37)
    s.feed(0x8000 | KEY_DOWN)       # background redraw + down
    s.until(KEY_DOWN, 47)           # to nested "HDMI: %s" (filter)
    s.feed(KEY_SELECT)              # enter region 3 (depth 2)
    assert (s.level, s.cursor) == (3, 50)
    s.until(KEY_DOWN, 59)           # to the " Back" closer line
    s.feed(KEY_SELECT)              # leave via the closer
    assert (s.level, s.cursor) == (2, 47)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 34)
    s.until(KEY_DOWN, 111)          # to "Volume: %s" - entering this region
    s.feed(KEY_SELECT)              # is the regression case for the percent-
    assert (s.level, s.cursor) == (7, 114)   # terminated-label scanner bug
    s.feed(KEY_MENUUP)              # back to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 111)
    s.until(KEY_DOWN, 137)          # to "Advanced Settings"
    s.feed(KEY_SELECT)              # enter region 8
    assert (s.level, s.cursor) == (8, 140)
    s.feed(KEY_SELECT)              # single-select GEOS Real-Time-Clock on
    s.feed(KEY_SELECT)              # and off again
    s.until(KEY_DOWN, 156)          # to "VIC-II: %s"
    s.feed(KEY_SELECT)              # enter region 10 (depth 2)
    assert (s.level, s.cursor) == (10, 159)
    s.feed(0x8000 | KEY_UP)         # redraw + up: wraps within the view
    assert s.cursor == 163          # lands on the closer line
    r = s.feed(KEY_CLOSE)           # Help: close the OSM
    assert r == "close"
    # reopen: same level and cursor (persistence)
    assert (s.level, s.cursor) == (10, 163)
    s.run_start()                   # the testbed draws before OPTM_RUN
    s.feed(KEY_MENUUP)              # pop to region 8
    assert (s.level, s.cursor) == (8, 156)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 137)
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


def nav3_script():
    """Dependency scenario in the live OPTM_RUN state machine: a single-select
    mother (idx 0) with a same-view dependent (idx 1) drives the real-time
    redraw (OPTM_DEPS_AFFECTS -> OPTM_SHOW); a submenu whose first content
    (idx 4) is dependent drives the enter-scan dependency skip
    (_OPTM_RUN_SM_2). Both are no-ops for the deps-off scenarios 1 and 2."""
    groups = [
        0x8001,   # 0 single-select toggle, mother gid 1 (START line)
        0x0002,   # 1 dependent radio gid 2  dep(1,1)  same view as the mother
        0x0003,   # 2 radio gid 3 (always visible)
        0xC000,   # 3 open region 1 (submenu " S:%s")
        0x0004,   # 4 dependent radio gid 4  dep(1,1)  first content of region 1
        0x0005,   # 5 radio gid 5 (always visible)
        0xC0FF,   # 6 close region 1
        0x00FF,   # 7 Close Menu
    ]
    raw = [0] * 8
    raw[1] = 0x1000 | (1 << 8) | 1     # dep(mother gid 1, item 1): visible if ON
    raw[4] = 0x1000 | (1 << 8) | 1
    stdsel = [0] * 8                    # toggle OFF
    s = NavSim(groups, stdsel, 0, labels=NAV3_LABELS, raw_deps=raw)
    s.run_start()
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
    L.append("NAV_START       .EQU 2")
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
    L.append("NAV3_START      .EQU 0")
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
    ("C_MENU_EXP_PORT_HW",  "EXP_PORT", 0),
    ("C_MENU_SIM_CRT",      "EXP_PORT", 1),
    ("C_MENU_SIM_REU",      "REU", 0),
    ("C_MENU_INTERNAL_1581", "INT1581", 0),
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
    ("C_MENU_RRNET_OFF",        "SIM_RRNET", 0),
    ("C_MENU_RRNET_MK2",        "SIM_RRNET", 1),
    ("C_MENU_RRNET_MK3_STD",    "SIM_RRNET", 2),
    ("C_MENU_RRNET_MK3_CUSTOM", "SIM_RRNET", 3),
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
    vecs.append((SEL << 12 | 0xFFF, 0x1DEF))      # the feature-probe magic
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
    out.append("-- === strlen incl. two-character newlines: %d)" % strlen)
    vals = c_menu_values()
    out.append("")
    out.append("-- === C_MENU constants for mega65.vhd ===")
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
    exp_dy = max(validate(menu_masked(V6_MENU), 2)[2],
                 build_new(menu_masked(V6_MENU), 0)["vis"])
    if consts.get("OPTM_DY") != exp_dy:
        errors.append("OPTM_DY = %s, model says %d"
                      % (consts.get("OPTM_DY"), exp_dy))

    # --- config.vhd: group id constants
    gconsts = parse_vhdl_constants(cfg, "OPTM_G_")
    for gname, gid in G.items():
        cn = "OPTM_G_" + gname
        if gname in ("MOUNT_9",) and cn not in gconsts:
            continue
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
        # split on top-level commas only: an entry may contain a comma inside
        # an OPTM_DEP(mother, item) call
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
        env["OPTM_DEP"] = dep_value          # OPTM_DEP(mother, item) helper
        vals = []
        for e in entries:
            try:
                vals.append(eval(e.replace("16#", "0x").replace("#", ""),
                                 {}, env))
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
    m = re.search(r"subtype\s+C_MENU_OSM_SCALING\s+is\s+natural\s+range\s+"
                  r"(\d+)\s+downto\s+(\d+)", mega)
    hi, lo = osm_scaling_range()
    if not m or (int(m.group(1)), int(m.group(2))) != (hi, lo):
        errors.append("C_MENU_OSM_SCALING range mismatch: model says "
                      "%d downto %d" % (hi, lo))

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
    ("optm_deps.asm  RESOLVE uses the wrong expected state",
     "M2M/rom/optm_deps.asm",
     "MOVE    1, R8                   ; expected = 1",
     "MOVE    0, R8                   ; expected = 1"),
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
    ("optm_deps.asm  OPTM_DEP_OK inverts the expected-state-0 arm (#4)",
     "M2M/rom/optm_deps.asm",
     "CMP     0, R3                   ; expected 0: visible iff state 0\n                RBRA    _ODO_VIS, Z",
     "CMP     0, R3                   ; expected 0: visible iff state 0\n                RBRA    _ODO_HID, Z"),
    ("optm_deps.asm  VAL drops its R8-preservation contract (#5)",
     "M2M/rom/optm_deps.asm",
     "MOVE    @SP++, R8\n                AND     0xFFFB, SR              ; clear Carry: success",
     "MOVE    @SP++, R0\n                AND     0xFFFB, SR              ; clear Carry: success"),
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
