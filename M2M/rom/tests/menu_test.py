#!/usr/bin/env python3
"""
Golden model, fixture generator and headless test runner for the M2M menu
structure algorithms (menu_struct.asm + menu.asm submenu state machine).

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
    RTC_GEOS=29, VICII_MODEL=30,
)

OPEN = ("SUBMENU",)
CLOSE = ("SUBMENU", "CLOSEF")

# Each entry: (label, [group name or None], [flag names])
# The flat index of each entry is its position in this list.
V6_MENU = [
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
    (" 16:9 720p 50 Hz (PAL)",   "HDMI_MODES_PAL", ["STDSEL"]),
    (" 16:9 720p 60 Hz (NTSC)",  "HDMI_MODES_NTSC", ["STDSEL"]),
    (" 4:3 576p 50 Hz (PAL)",    "HDMI_MODES_PAL", []),
    (" 4:3 576p 60 Hz (NTSC)",   "HDMI_MODES_NTSC", []),
    (" 5:4 576p 50 Hz (PAL)",    "HDMI_MODES_PAL", []),
    (" 5:4 576p 60 Hz (NTSC)",   "HDMI_MODES_NTSC", []),
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
    (" 6581",                    "SID_SETUP", []),
    (" 8580",                    "SID_SETUP", []),
    ("",                         None, ["LINE"]),
    (" Stereo SID",              None, []),
    ("",                         None, ["LINE"]),
    (" L: 6581 R: 6581",         "SID_SETUP", []),
    (" L: 6581 R: 8580",         "SID_SETUP", []),
    (" L: 8580 R: 6581",         "SID_SETUP", []),
    (" L: 8580 R: 8580",         "SID_SETUP", ["STDSEL"]),
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
    (" 90%",                     "VOLUME", []),
    (" 80%",                     "VOLUME", []),
    (" 70%",                     "VOLUME", []),
    (" 60%",                     "VOLUME", []),
    (" 50%",                     "VOLUME", []),
    (" 40%",                     "VOLUME", []),
    (" 30%",                     "VOLUME", []),
    (" 20%",                     "VOLUME", []),
    (" 10%",                     "VOLUME", []),
    (" 0%",                      "VOLUME", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 7
    (" Advanced Settings",       None, OPEN),            # region 8
    (" Advanced Settings",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" RTC for GEOS",            "RTC_GEOS", ["SINGLESEL"]),
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


def menu_words(menu):
    """(vhdl integer, masked firmware word, stdsel, line, start) per entry"""
    out = []
    for label, group, flags in menu:
        v = G[group] if group else 0
        for f in flags:
            v += FLAGVAL[f]
        out.append(v)
    return out


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


def build_new(groups, level):
    """Port of OPTM_STRUCT_BUILD. Returns dict or {'err': idx}."""
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


def summ_scan(groups, heading, stdsel):
    """Port of OPTM_SUMM_SCAN. Returns ('found', idx) or ('err', class)."""
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
        if stdsel[i] == 0:
            continue
        return ("found", i)


def num_regions(groups):
    return sum(1 for w in groups if classify(w) == "open")


# ---------------------------------------------------------------------------
# Navigation simulator (port of the OPTM_RUN state machine in menu.asm)
# ---------------------------------------------------------------------------

KEY_UP, KEY_DOWN, KEY_SELECT, KEY_CLOSE, KEY_SELALT, KEY_MENUUP = 1, 2, 3, 4, 5, 6


class NavSim:
    def __init__(self, groups, stdsel, start):
        self.g = list(groups)
        self.sel = list(stdsel)
        self.n = len(groups)
        self.level = 0
        self.cursor = start
        self.trace = []
        self.keys = []

    def _struct(self):
        return build_new(self.g, self.level)

    def _visible(self, i):
        return bool(self._struct()["arr"][i] & 0x8000)

    def _emit_k(self):
        b = self._struct()
        self.trace.append("K L=%04X C=%04X P=%04X O=%04X"
                          % (self.level, self.cursor, b["parent"], b["opener"]))

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
                while True:
                    i += 1
                    assert i < self.n, "NOSEL fatal"
                    if self.g[i] & 0x40FF:
                        break
                self.cursor = i
            else:                                   # leave
                self._leave()
            return None
        if self.sel[self.cursor]:
            if w & 0x8000:                          # single-select: flip off
                self.sel[self.cursor] = 0
                self.trace.append("S G=%04X I=%04X K=%04X" % (w, 0, key))
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
        return None

    def feed(self, key):
        """Process one key as OPTM_RUN would. Returns 'close' if menu ends."""
        self._emit_k()                              # GETKEY trace happens
        self.keys.append(key)                       # before the key acts
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
    fx.append(("V6 menu with START on nested opener", 130,
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
    # heading 33 (HDMI): nothing selected of its own; child skipped; the
    # selected line 54 inside the child must NOT leak: ends at own closer
    fx.append(("HDMI region empty -> own closer", 33, v6g,
               sel(i36=0, i37=0, i43=0, i44=0)))
    # heading 33 with 4:3 PAL selected -> found 38
    fx.append(("HDMI region finds 4:3 PAL", 33, v6g, sel(i36=0, i38=1)))
    # heading 126 (Advanced): no radio group of its own at all
    fx.append(("Advanced has no own radio group", 126, v6g, base))
    # heading 130 (OSM scaling): default -> 133
    fx.append(("OSM scaling default", 130, v6g, base))
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


def nav_script():
    """Build the nav-test key script with the simulator and return
    (keys, expected trace lines)."""
    g = menu_masked(V6_MENU)
    s = NavSim(g, menu_stdsel(V6_MENU), 2)

    s.feed(KEY_UP)                  # wrap to "Close Menu" (158)
    assert s.cursor == 158
    s.feed(KEY_DOWN)                # wrap back to mount line (2)
    assert s.cursor == 2
    s.until(KEY_DOWN, 14)           # to "Model: %s"
    s.feed(KEY_SELECT)              # enter region 1
    assert (s.level, s.cursor) == (1, 17)
    s.feed(KEY_DOWN)                # NTSC
    s.feed(KEY_SELALT)              # radio-select NTSC via Space
    s.feed(KEY_MENUUP)              # pop to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 14)
    s.until(KEY_DOWN, 33)           # to "HDMI: %s"
    s.feed(KEY_SELECT)              # enter region 2
    assert (s.level, s.cursor) == (2, 36)
    s.feed(0x8000 | KEY_DOWN)       # background redraw + down
    s.until(KEY_DOWN, 46)           # to nested "HDMI: %s" (filter)
    s.feed(KEY_SELECT)              # enter region 3 (depth 2)
    assert (s.level, s.cursor) == (3, 49)
    s.until(KEY_DOWN, 58)           # to the " Back" closer line
    s.feed(KEY_SELECT)              # leave via the closer
    assert (s.level, s.cursor) == (2, 46)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 33)
    s.until(KEY_DOWN, 126)          # to "Advanced Settings"
    s.feed(KEY_SELECT)              # enter region 8
    assert (s.level, s.cursor) == (8, 129)
    s.feed(KEY_SELECT)              # single-select RTC for GEOS on
    s.feed(KEY_SELECT)              # and off again
    s.until(KEY_DOWN, 145)          # to "VIC-II: %s"
    s.feed(KEY_SELECT)              # enter region 10 (depth 2)
    assert (s.level, s.cursor) == (10, 148)
    s.feed(0x8000 | KEY_UP)         # redraw + up: wraps within the view
    assert s.cursor == 152          # lands on the closer line
    r = s.feed(KEY_CLOSE)           # Help: close the OSM
    assert r == "close"
    # reopen: same level and cursor (persistence)
    assert (s.level, s.cursor) == (10, 152)
    s.feed(KEY_MENUUP)              # pop to region 8
    assert (s.level, s.cursor) == (8, 145)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 126)
    r = s.feed(KEY_MENUUP)          # Run/Stop at main: close
    assert r == "close"
    return s.keys, s.trace


def nav2_script():
    """Second nav scenario on a synthetic menu, covering the enter-scan stop
    positions of spec section 10 item 4 that the V6 menu cannot provide:
    a region whose FIRST content is a nested child opener (this is the only
    input that distinguishes the new 0x40FF stop mask in _OPTM_RUN_SM_2 from
    the old 0x00FF one - found by mutation testing), and an empty region
    (the scan must stop on the closer)."""
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
    s = NavSim(groups, stdsel, 0)
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


def expect_nav():
    _, trace = nav_script()
    _, _, _, trace2 = nav2_script()
    return "\n".join(trace) + "\nN2\n" + "\n".join(trace2) + "\nDONE\n"


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
    L.append("NAV2_SCRIPT_CNT .EQU %d" % len(keys2))
    L.append("NAV2_SCRIPT")
    L += dw_lines(keys2)
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
    ("C_MENU_HDMI_16_9_60_N", "HDMI_MODES_NTSC", 0),
    ("C_MENU_HDMI_4_3_60_N",  "HDMI_MODES_NTSC", 1),
    ("C_MENU_HDMI_5_4_60_N",  "HDMI_MODES_NTSC", 2),
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
        entries = [e.strip() for e in body.split(",")
                   if e.strip()]
        # re-join entries that were split inside an expression: VHDL entries
        # here never contain commas, so a plain split is fine
        env = dict(gconsts)
        env.update(parse_vhdl_constants(cfg, "OPTM_G"))
        vals = []
        for e in entries:
            try:
                vals.append(eval(e.replace("16#", "0x").replace("#", ""),
                                 {}, env))
            except Exception:
                errors.append("cannot evaluate OPTM_GROUPS entry %r" % e)
                vals.append(-1)
        model_words = menu_words(V6_MENU)
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
    return 0


# ---------------------------------------------------------------------------
# gen / run
# ---------------------------------------------------------------------------


def gen():
    emit_fixtures_asm(os.path.join(HERE, "menu_test_fixtures.asm"))
    emit_equiv_asm(os.path.join(HERE, "menu_equiv_fixtures.asm"))
    emit_nav_asm(os.path.join(HERE, "menu_nav_fixtures.asm"))
    for name, content in [("menu_struct_test.exp", expect_struct()),
                          ("menu_equiv_test.exp", expect_equiv()),
                          ("menu_nav_test.exp", expect_nav())]:
        with open(os.path.join(HERE, name), "w") as f:
            f.write(content)
    print("generated fixtures and expected outputs")


def run():
    gen()
    asm = os.path.join(REPO, "M2M/QNICE/assembler/asm")
    emu = os.path.join(REPO, "M2M/QNICE/emulator/qnice")
    mon = os.path.join(REPO, "M2M/QNICE/monitor/monitor.out")
    fails = 0
    for tb in ("menu_struct_test", "menu_equiv_test", "menu_nav_test"):
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
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
