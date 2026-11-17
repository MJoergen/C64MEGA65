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
                                  catches every one (coverage proof for #229);
                                  edits of config.vhd / mega65.vhd must be
                                  caught by verify
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
    RTC_GEOS=29, DRV8_MODE=31, DRV8_UNMOUNT=32,
    DRV9_MODE=33, DRV9_UNMOUNT=34, SIM_RRNET=35, STEREO_MIX=36,
    SC_F9=37, SC_F10=38, SC_F11=39, SC_F12=40, SC_F13=41, SC_F14=42,
    MOUSE_P1=43, MOUSE_P2=44, PADDLES_P1=45, PADDLES_P2=46,
    MOUSE_P1_RCLICK=47, MOUSE_P2_RCLICK=48,
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
    (" Internal 1581",           "DRV9_MODE", []),
    (" Off",                     "DRV9_MODE", ["STDSEL"]),
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
    ("",                         None, ["LINE"]),         # dep: C128 or Smart
    (" Turbo speed",             None, ["HEADLINE"]),     # dep: C128 or Smart
    (" 2x",                      "TURBO_SPEED", ["STDSEL"]),  # dep: C128 or Smart
    (" 3x",                      "TURBO_SPEED", []),      # dep: C128 or Smart
    (" 4x",                      "TURBO_SPEED", []),      # dep: C128 or Smart
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
    (" Stereo: %s",              None, OPEN),            # region 9 (in 8, #247)
    (" Stereo Mix",              None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Full Stereo",             "STEREO_MIX", ["STDSEL"]),
    (" Wide Stereo",             "STEREO_MIX", []),
    (" Narrow Stereo",           "STEREO_MIX", []),
    (" Mono",                    "STEREO_MIX", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 9
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 8
    (" Advanced Settings",       None, OPEN),            # region 10
    (" Advanced Settings",       None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" GEOS Real-Time-Clock",    "RTC_GEOS", ["SINGLESEL"]),
    (" OSM: %s",                 None, OPEN),            # region 11 (in 10)
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
    (" Back",                    None, CLOSE),           # close region 11
    (" CIA: Use 8521 (C64C)",    "CIA_8521", ["SINGLESEL"]),
    ("",                         None, ["LINE"]),
    (" RR-Net",                  None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Off",                     "SIM_RRNET", ["STDSEL"]),
    (" On: MK2",                 "SIM_RRNET", []),
    (" On: MK3 & Std ROM",       "SIM_RRNET", []),
    (" On: MK3 & Custom ROM",    "SIM_RRNET", []),
    ("",                         None, ["LINE"]),
    (" Input Devices",           None, ["HEADLINE"]),    # #142, #190, #193
    ("",                         None, ["LINE"]),
    (" Keyboard Shortcuts",     None, OPEN),            # region 12 (in 10), #142
    (" Keyboard Shortcuts",     None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" F9:  %s",                None, OPEN),            # region 13 (in 12)
    (" F9 Key",                 None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F9", []),
    (" Freeze",                 "SC_F9", ["STDSEL"]),
    (" Mount drive 8",          "SC_F9", []),
    (" Mount drive 9",          "SC_F9", []),
    (" Next disk drive 8",      "SC_F9", []),
    (" Next disk drive 9",      "SC_F9", []),
    (" Load PRG",               "SC_F9", []),
    (" Load CRT",               "SC_F9", []),
    (" Flip joysticks",         "SC_F9", []),
    (" Volume down",            "SC_F9", []),
    (" Volume up",              "SC_F9", []),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 13
    (" F10: %s",                None, OPEN),            # region 14 (in 12)
    (" F10 Key (Shift+F9)",     None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F10", []),
    (" Freeze",                 "SC_F10", []),
    (" Mount drive 8",          "SC_F10", []),
    (" Mount drive 9",          "SC_F10", []),
    (" Next disk drive 8",      "SC_F10", []),
    (" Next disk drive 9",      "SC_F10", []),
    (" Load PRG",               "SC_F10", []),
    (" Load CRT",               "SC_F10", ["STDSEL"]),
    (" Flip joysticks",         "SC_F10", []),
    (" Volume down",            "SC_F10", []),
    (" Volume up",              "SC_F10", []),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 14
    (" F11: %s",                None, OPEN),            # region 15 (in 12)
    (" F11 Key",                None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F11", []),
    (" Freeze",                 "SC_F11", []),
    (" Mount drive 8",          "SC_F11", ["STDSEL"]),
    (" Mount drive 9",          "SC_F11", []),
    (" Next disk drive 8",      "SC_F11", []),
    (" Next disk drive 9",      "SC_F11", []),
    (" Load PRG",               "SC_F11", []),
    (" Load CRT",               "SC_F11", []),
    (" Flip joysticks",         "SC_F11", []),
    (" Volume down",            "SC_F11", []),
    (" Volume up",              "SC_F11", []),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 15
    (" F12: %s",                None, OPEN),            # region 16 (in 12)
    (" F12 Key (Shift+F11)",    None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F12", []),
    (" Freeze",                 "SC_F12", []),
    (" Mount drive 8",          "SC_F12", []),
    (" Mount drive 9",          "SC_F12", []),
    (" Next disk drive 8",      "SC_F12", []),
    (" Next disk drive 9",      "SC_F12", []),
    (" Load PRG",               "SC_F12", ["STDSEL"]),
    (" Load CRT",               "SC_F12", []),
    (" Flip joysticks",         "SC_F12", []),
    (" Volume down",            "SC_F12", []),
    (" Volume up",              "SC_F12", []),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 16
    (" F13: %s",                None, OPEN),            # region 17 (in 12)
    (" F13 Key",                None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F13", []),
    (" Freeze",                 "SC_F13", []),
    (" Mount drive 8",          "SC_F13", []),
    (" Mount drive 9",          "SC_F13", []),
    (" Next disk drive 8",      "SC_F13", []),
    (" Next disk drive 9",      "SC_F13", []),
    (" Load PRG",               "SC_F13", []),
    (" Load CRT",               "SC_F13", []),
    (" Flip joysticks",         "SC_F13", []),
    (" Volume down",            "SC_F13", ["STDSEL"]),
    (" Volume up",              "SC_F13", []),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 17
    (" F14: %s",                None, OPEN),            # region 18 (in 12)
    (" F14 Key (Shift+F13)",    None, ["HEADLINE"]),
    ("",                        None, ["LINE"]),
    (" Off",                    "SC_F14", []),
    (" Freeze",                 "SC_F14", []),
    (" Mount drive 8",          "SC_F14", []),
    (" Mount drive 9",          "SC_F14", []),
    (" Next disk drive 8",      "SC_F14", []),
    (" Next disk drive 9",      "SC_F14", []),
    (" Load PRG",               "SC_F14", []),
    (" Load CRT",               "SC_F14", []),
    (" Flip joysticks",         "SC_F14", []),
    (" Volume down",            "SC_F14", []),
    (" Volume up",              "SC_F14", ["STDSEL"]),
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 18
    ("",                        None, ["LINE"]),
    (" Back",                   None, CLOSE),           # close region 12
    (" Mouse",                   None, OPEN),            # region 19 (in 10), #190
    (" Mouse",                   None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Port 1: C64",             "MOUSE_P1", ["STDSEL"]),
    (" Port 1: Amiga",           "MOUSE_P1", []),
    (" #1: MEGA+left = right",   "MOUSE_P1_RCLICK", ["SINGLESEL"]),   # dependent, #190
    ("",                         None, ["LINE"]),
    (" Port 2: C64",             "MOUSE_P2", ["STDSEL"]),
    (" Port 2: Amiga",           "MOUSE_P2", []),
    (" #2: MEGA+left = right",   "MOUSE_P2_RCLICK", ["SINGLESEL"]),   # dependent, #190
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 19
    (" Paddles",                 None, OPEN),            # region 20 (in 10), #193
    (" Paddles",                 None, ["HEADLINE"]),
    ("",                         None, ["LINE"]),
    (" Port 1: C64",             "PADDLES_P1", ["STDSEL"]),
    (" Port 1: Atari CX30",      "PADDLES_P1", []),
    ("",                         None, ["LINE"]),
    (" Port 2: C64",             "PADDLES_P2", ["STDSEL"]),
    (" Port 2: Atari CX30",      "PADDLES_P2", []),
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 20
    ("",                         None, ["LINE"]),
    (" Back",                    None, CLOSE),           # close region 10
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
# and the PAL/NTSC HDMI variants, flicker-free twins + Raw 50.1 (#229), plus
# the "Turbo speed" block (separator, headline, 2x/3x/4x) that is only visible
# while the turbo mode is C128 or Smart (#87): a mother in the same submenu;
# and the switch "MEGA+left = right" of each port in the Mouse submenu, only
# visible while its port is set to Amiga, item 1 of its radio mother (#190)
V6_DEPS = {
    2:  ("DRV8_MODE", 0b0011), 3: ("DRV8_MODE", 0b0100),
    4:  ("DRV9_MODE", 0b0011), 5: ("DRV9_MODE", 0b0100),
    46: ("TURBO_MODE", 0b0110), 47: ("TURBO_MODE", 0b0110),
    48: ("TURBO_MODE", 0b0110), 49: ("TURBO_MODE", 0b0110),
    50: ("TURBO_MODE", 0b0110),
    57: ("MACHINE_MODE", 0b0001), 58: ("MACHINE_MODE", 0b0010),
    59: ("MACHINE_MODE", 0b0001), 60: ("MACHINE_MODE", 0b0010),
    61: ("MACHINE_MODE", 0b0001), 62: ("MACHINE_MODE", 0b0010),
    64: ("MACHINE_MODE", 0b0001), 65: ("MACHINE_MODE", 0b0010),
    81: ("MACHINE_MODE", 0b0001),
    302: ("MOUSE_P1", 0b0010), 306: ("MOUSE_P2", 0b0010),
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
    (bit 15 = valid, bits 12..9 = item mask moved up from bits 11..8,
    bits 8..0 = flat index (0..511) of the FIRST member of the mother group,
    for BOTH mother types; OPTM_DEP_OK branches on the mother type at
    runtime)."""
    out = []
    for w in raw_deps:
        if not (w & 0x1000):                    # not dependent
            out.append(0)
            continue
        mother = w & 0xFF
        mask = (w & 0x0F00) << 1                 # bits 11-8 -> bits 12-9
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
    first = w & 0x1FF                             # first member of the mother
    mask = (w >> 9) & 0xF
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


def menu_lines(menu):
    """The separator flags (OPTM_G_LINE), as SEL_OPTM_LINES serves them"""
    return [1 if "LINE" in flags else 0 for _, _, flags in menu]


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


# A synthetic menu at the maximum menu size of 512 items (one bit per item in
# the 512-bit M2M$CFM_DATA register). The mothers sit at the flat indices that
# stress the 9-bit controlling-line field (bits 8-0) of the resolved
# dependency word: a radio mother whose first member is 255 (the largest
# 8-bit index, members 255/258/300), a radio mother that starts exactly at 256
# (members 256/257), a single-select mother at 400 and one on the very last
# line 511. Dependent lines (TEXT lines and a dependent radio group) sit below
# 256, above it at the main level and inside a submenu (region 1, 470..479).
WIDE_N = 512
WIDE_R255, WIDE_R256, WIDE_S400, WIDE_S511 = 70, 71, 72, 73
WIDE_RAW_MAP = {
    10: (WIDE_R256, 0b01), 11: (WIDE_R256, 0b10),
    12: (WIDE_R255, 0b100), 13: (WIDE_R255, 0b011),
    20: (WIDE_S511, 0b01),
    450: (WIDE_S400, 0b10), 451: (WIDE_S400, 0b01), 452: (WIDE_S511, 0b10),
    472: (WIDE_R256, 0b10), 473: (WIDE_S400, 0b10),
    474: (WIDE_R256, 0b01), 475: (WIDE_R256, 0b01),
}


def wide_groups():
    g = [0] * WIDE_N                    # TEXT lines (group id 0) as filler
    g[0] = 0x1000                       # headline
    for i in range(100, 200):           # ten plain radio groups as filler
        g[i] = 1 + (i % 10)
    g[255] = g[258] = g[300] = WIDE_R255
    g[256] = g[257] = WIDE_R256
    g[400] = 0x8000 | WIDE_S400
    g[470] = 0xC000                     # open region 1
    g[471] = 0x1000                     # headline inside region 1
    g[474] = g[475] = 74                # dependent radio group
    g[476] = g[477] = 75
    g[479] = 0xC0FF                     # close region 1
    g[510] = 0x00FF                     # Close Menu
    g[511] = 0x8000 | WIDE_S511
    return g


def wide_raw():
    return dep_raw_array(WIDE_RAW_MAP, WIDE_N)


def wide_stdsel(state):
    """State "A": first member of the 256 mother, third member (300) of the
    255 mother, 400 off, 511 on. State "B": the opposite choices. State "C":
    like A, but no member of the 256 mother is selected."""
    s = [0] * WIDE_N
    for i in range(100, 110):           # one member per filler group
        s[i] = 1
    s[475] = s[476] = 1
    if state == "B":
        s[257] = s[255] = s[400] = 1
    else:
        s[300] = s[511] = 1
        if state == "A":
            s[256] = 1
    return s


# Intended visibility of the dependent lines of the wide menu, derived by hand
# from WIDE_RAW_MAP and wide_stdsel(), independent of the resolved word format
# (the asm-vs-model comparison alone cannot catch a format limit that the
# golden model shares, which is exactly what the old 8-bit field was):
#   A: 256 mother = member 0, 255 mother = member 2 (flat 300), 400 off, 511 on
#   B: 256 mother = member 1, 255 mother = member 0, 400 on, 511 off
#   C: as A, but no member of the 256 mother selected
WIDE_VISIBLE = {
    ("A", 0): [10, 12, 451, 452], ("A", 1): [474, 475],
    ("B", 0): [11, 13, 20, 450],  ("B", 1): [472, 473],
    ("C", 0): [12, 451, 452],     ("C", 1): [],
}
WIDE_SUMMARY = {"A": 475, "B": 476}     # %s walk from the opener at 470


def wide_menu_errors():
    """Check the golden model against WIDE_VISIBLE / WIDE_SUMMARY."""
    errors = []
    g = wide_groups()
    raw = wide_raw()
    if validate_deps(g, raw, [0] * WIDE_N) != ("ok",):
        errors.append("wide menu does not validate")
    res = resolve_deps(g, raw)
    for (state, level), want in sorted(WIDE_VISIBLE.items()):
        b = build_new(g, level, res, wide_stdsel(state))
        got = [i for i in sorted(WIDE_RAW_MAP) if b["arr"][i] & 0x8000]
        if got != want:
            errors.append("state %s level %d: visible dependents %r, "
                          "expected %r" % (state, level, got, want))
    for state, want in sorted(WIDE_SUMMARY.items()):
        r = summ_scan(g, 470, wide_stdsel(state), res)
        if r != ("found", want):
            errors.append("state %s: summary walk %r, expected %r"
                          % (state, r, ("found", want)))
    return errors


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
    # the real V6 menu: masks 0b0011/0b0100 (drives), 0b0001/0b0010 (HDMI)
    # and 0b0110 (Turbo speed block)
    fx.append(("v6 real menu", menu_masked(V6_MENU),
               menu_deps_raw(V6_MENU, V6_DEPS)))
    # 512 items: first-member indices 255, 256, 400 and 511 must survive the
    # resolved word intact (the field was 8 bits wide before)
    fx.append(("wide 512-item menu", wide_groups(), wide_raw()))
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
    # 512 items: valid, and a missing mother reported at flat index 460
    fx.append(("wide 512-item menu", wide_groups(), wide_raw(),
               [0] * WIDE_N))
    r = wide_raw(); r[460] = 0x1000 | (0b01 << 8) | 99
    fx.append(("wide: mother missing at 460", wide_groups(), r,
               [0] * WIDE_N))
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
    # the Model submenu level (#87): turbo Off (factory default) hides the
    # Turbo speed block (separator, headline, 2x/3x/4x = idx 46..50); C128
    # and Smart show it - a mother in the same submenu as its dependents
    fx.append(("v6 Model level turbo Off", v6g, v6res, menu_stdsel(V6_MENU), 2))
    for name, idx in (("C128", 44), ("Smart", 45)):
        s = menu_stdsel(V6_MENU)
        s[43], s[idx] = 0, 1
        fx.append(("v6 Model level turbo " + name, v6g, v6res, s, 2))
    # 512 items: OPTM_DEP_OK with mothers at flat 255/256/400/511 (state A
    # and its opposite B, both at the main level and inside region 1) and
    # with no member of the 256 mother selected (C)
    wg = wide_groups()
    wres = resolve_deps(wg, wide_raw())
    fx.append(("wide main level A", wg, wres, wide_stdsel("A"), 0))
    fx.append(("wide main level B", wg, wres, wide_stdsel("B"), 0))
    fx.append(("wide region 1 A", wg, wres, wide_stdsel("A"), 1))
    fx.append(("wide region 1 B", wg, wres, wide_stdsel("B"), 1))
    fx.append(("wide main level C", wg, wres, wide_stdsel("C"), 0))
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
    # 512 items: the walk from the opener at 470 finds the selected member 475
    # while the 256 mother allows it (A) and skips it to 476 otherwise (B)
    wg = wide_groups()
    wres = resolve_deps(wg, wide_raw())
    fx.append(("wide region visible", wg, wres, wide_stdsel("A"), 470))
    fx.append(("wide region hidden", wg, wres, wide_stdsel("B"), 470))
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
    # min 4 (in the PAL state the four NTSC HDMI lines are hidden) + TURBO_MODE
    # min 0 (C128 and Smart show the whole Turbo speed block) = 6
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
    # 512 items: mothers at flat 255/256/400/511
    fx.append(("wide 512-item menu", wide_groups(), wide_raw()))
    return fx


# ---------------------------------------------------------------------------
# Navigation simulator (port of the OPTM_RUN state machine in menu.asm)
# ---------------------------------------------------------------------------

KEY_UP, KEY_DOWN, KEY_SELECT, KEY_CLOSE, KEY_SELALT, KEY_MENUUP = 1, 2, 3, 4, 5, 6
KEY_FIRST, KEY_LAST = 7, 8      # Cursor left / Cursor right (issue #258)

# The screen of the nav testbed (screen trace of scenario 4): scenario 4
# places the menu at the column NAV4_X and the row 0 (the Shell places it at
# the right edge of the screen and at row 0, see SCR$OSM_O_X and SCR$OSM_O_Y
# in screen.asm), so the marker column, which is also the first column of a
# %s string, is NAV4_X + 1 (behind the frame). The record NT_REC of the
# testbed draws the marker of a selected radio item as r and the marker of a
# selected single-select item as s: two different characters, like
# M2M$OPT_SEL_MULTI and M2M$OPT_SEL_SINGLE
NAV4_X = 7
NAV_COL = NAV4_X + 1
NAV_MARK_RADIO, NAV_MARK_SINGLE = "r", "s"
# OPTM_INIT of scenario 4: x, y, dx and dy of the menu (the frame)
NAV_FRAME = (NAV4_X, 0, 30, 30)
# the modes of OPTM_FP_SELECT (OPTM_SEL_* in menu.asm)
SEL_STD, SEL_SEL, SEL_TLL = 0, 1, 2


class NavSim:
    def __init__(self, groups, stdsel, start, labels=None, raw_deps=None,
                 screen=False, lines=None):
        self.g = list(groups)
        self.sel = list(stdsel)
        self.n = len(groups)
        self.labels = labels or [""] * self.n
        self.level = 0
        self.cursor = start
        self.trace = []
        self.keys = []
        self.resolved = resolve_deps(self.g, raw_deps) if raw_deps else None
        # the separator flags that the testbed passes as the lines array of
        # the init record (all 0 except in scenario 4)
        self.lines = list(lines) if lines else [0] * self.n
        # screen trace (scenario 4): the testbed prints a line for every call
        # of a screen function (C clear, FR frame, D print, X printxy, L line,
        # B select) and an M line behind every S line (the flat indices of
        # all selected items). The model keeps the screen as these calls
        # leave it: whether a frame was drawn since the last clear, the drawn
        # lines, the first character of every printed string at its row, the
        # rows of the separators and the mode of every position that
        # OPTM_FP_SELECT set to a mode other than OPTM_SEL_STD
        self.screen = screen
        self._clear_screen()

    def _struct(self):
        return build_new(self.g, self.level, self.resolved, self.sel)

    def _vis(self):
        return [i for i, w in enumerate(self._struct()["arr"]) if w & 0x8000]

    def _row(self, i):
        """Screen row of line i in the current view, as _OPTM_R_F2M + 1 and
        the y counter of OPTM_SHOW compute it (OPTM_Y is 0 in the testbed);
        a hidden line has no row, the firmware ends in OPTM_F_F2M"""
        vis = self._vis()
        assert i in vis, "row of the hidden line %d" % i
        return vis.index(i) + 1

    def _clear_screen(self):
        self.scr_frame = False
        self.scr_vis = None
        self.scr_mark = {}
        self.scr_seps = set()
        self.scr_attr = {}

    def _pos(self, i):
        """position of line i in the current view, counted from 0 (what
        _OPTM_R_F2M returns and OPTM_FP_SELECT gets)"""
        vis = self._vis()
        assert i in vis, "position of the hidden line %d" % i
        return vis.index(i)

    def _printxy(self, row, text, col=NAV_COL):
        self.trace.append("X X=%04X Y=%04X [%s]" % (col, row, text))
        self.scr_mark[(row, col)] = text[:1]

    def _bar(self, pos, mode):
        """OPTM_FP_SELECT: the cursor bar (OPTM_SEL_SEL), its removal
        (OPTM_SEL_STD) or a highlighted headline (OPTM_SEL_TLL)"""
        self.trace.append("B P=%04X M=%04X" % (pos, mode))
        if mode == SEL_STD:
            self.scr_attr.pop(pos, None)
        else:
            self.scr_attr[pos] = mode

    def _line(self, row):
        self.trace.append("L Y=%04X" % row)
        self.scr_seps.add(row)

    def _loop_sel(self):
        """the top of the main loop of OPTM_RUN draws the cursor bar on the
        current line before it asks for the next key"""
        if self.screen:
            self._bar(self._pos(self.cursor), SEL_SEL)

    def _marker(self, i):
        """the marker of line i when it is selected: OPTM_SHOW and OPTM_RUN
        take the single-select string for a line with the single-select
        flag and the radio string otherwise"""
        return NAV_MARK_SINGLE if self.g[i] & 0x8000 else NAV_MARK_RADIO

    def _emit_m(self):
        if self.screen:
            self.trace.append("M" + "".join(" %04X" % i for i, v in
                                            enumerate(self.sel) if v))

    def _check_screen(self):
        """What the screen shows after a key, derived from the state of the
        model: a frame drawn after the last clear; exactly the visible lines
        of the current view; in the marker column the marker of its type
        (radio or single-select) in the row of every visible selected line
        and in no other row; a separator in the row of every visible line
        with the separator flag that is not selected and, in a submenu, in
        the row below the last line if that row is at least two rows above
        the bottom of the frame, and in no other row; the cursor bar on the
        position of the cursor, the headline highlight on the position of
        every visible headline and no other position in another mode than
        OPTM_SEL_STD; and the cursor on a visible line. The column of the
        strings is not part of this check: the model prints in NAV_COL only,
        and the comparison of its X lines with the trace of the testbed is
        what checks the column of the firmware."""
        vis = self._vis()
        assert self.scr_frame, "no frame since the last clear"
        assert self.scr_vis == vis, (
            "stale screen at level %d: drawn %r, visible %r"
            % (self.level, self.scr_vis, vis))
        seps = {row for row, i in enumerate(vis, 1)
                if self.lines[i] and not self.sel[i]}
        if self.level != 0 and \
                len(vis) + 1 <= NAV_FRAME[1] + NAV_FRAME[3] - 3:
            seps.add(len(vis) + 1)
        assert self.scr_seps == seps, (
            "separators in the rows %r, expected %r"
            % (sorted(self.scr_seps), sorted(seps)))
        attr = {p: SEL_TLL for p, i in enumerate(vis) if self.g[i] & 0x1000}
        assert self.cursor in vis, "cursor on the hidden line %d" % self.cursor
        attr[vis.index(self.cursor)] = SEL_SEL
        assert self.scr_attr == attr, (
            "cursor bar and highlights %r, expected %r"
            % (sorted(self.scr_attr.items()), sorted(attr.items())))
        for row, i in enumerate(vis, 1):
            want = self._marker(i) if self.sel[i] else " "
            got = self.scr_mark.get((row, NAV_COL), " ")
            assert got == want, (
                "row %d (line %d) shows %r, expected %r"
                % (row, i, got, want))

    def _affects(self, w):
        """Port of OPTM_DEPS_AFFECTS: does group word w control a dependent?"""
        if self.resolved is None:
            return False
        for rw in self.resolved:
            if (rw & 0x8000) and self.g[rw & 0x1FF] == w:
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
        percent-terminated-label desync bug in the OPTM_SHOW scanner.
        With the screen trace, OPTM_SHOW first draws the visible lines (D),
        prints the string of each %s callback in its row (X) and then the
        marker of every visible selected line (X), the single-select or the
        radio marker by the type of the line."""
        arr = self._struct()["arr"]
        vis = [i for i, w in enumerate(arr) if w & 0x8000]
        if self.screen:
            self.trace.append("C")              # OPTM_FP_CLEAR
            self._clear_screen()
            self.trace.append("FR X=%04X Y=%04X W=%04X H=%04X" % NAV_FRAME)
            self.scr_frame = True
            self.trace.append("D" + "".join(" %04X" % i for i in vis))
            self.scr_vis = vis
            for p, i in enumerate(vis):         # highlight the headlines
                if self.g[i] & 0x1000:
                    self._bar(p, SEL_TLL)
        for i, t in enumerate(self.labels):
            if "%s" in t and (arr[i] & 0x8000):
                self.trace.append("W I=%04X" % i)
                if self.screen:
                    self._printxy(vis.index(i) + 1, t)
        if self.screen:
            for row, i in enumerate(vis, 1):    # markers and separators
                if self.sel[i]:
                    self._printxy(row, self._marker(i))
                elif self.lines[i]:
                    self._line(row)
            row = len(vis) + 1                  # the line below a submenu
            if self.level != 0 and row <= NAV_FRAME[1] + NAV_FRAME[3] - 3:
                self._line(row)

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
        if self.screen:
            self._loop_sel()
            self._check_screen()

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

    def _jump(self, last):
        """Cursor left / right (issue #258): the first / last line of the flat
        list that is visible in the current (sub)menu and selectable. This
        is the intended behavior written down directly - deliberately not a
        port of the assembly, which reuses the cursor-up/down search with a
        wrapped start position."""
        arr = self._struct()["arr"]
        order = range(self.n - 1, -1, -1) if last else range(self.n)
        for c in order:
            w = self.g[c]
            if (arr[c] & 0x8000) and ((w & SUBMENU) or (w & 0xFF)):
                self.cursor = c
                return
        raise AssertionError("no selectable line in the current view")

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
                if self.screen:                     # delete the marker
                    self._printxy(self._row(self.cursor), " ")
                self.trace.append("S G=%04X I=%04X K=%04X" % (w, 0, key))
                self._emit_m()
                if self._affects(w):                # toggled a mother: redraw
                    self._redraw()
            return None                             # multi already set: ignore
        if w & 0x8000:
            if self.screen:                         # draw the marker
                self._printxy(self._row(self.cursor), NAV_MARK_SINGLE)
            self.sel[self.cursor] = 1
            item = 1
        else:
            for j in range(self.n):                 # radio: clear whole group
                if self.g[j] == w:
                    self.sel[j] = 0
                    if self.screen:                 # delete each marker
                        self._printxy(self._row(j), " ")
            if self.screen:                         # draw the new one
                self._printxy(self._row(self.cursor), NAV_MARK_RADIO)
            self.sel[self.cursor] = 1
            first = self.g.index(w)
            item = sum(1 for j in range(first, self.cursor)
                       if self.g[j] == w)
        self.trace.append("S G=%04X I=%04X K=%04X" % (w, item, key))
        self._emit_m()
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
            self._emit_w()                          # OPTM_SHOW runs first,
            self._loop_sel()                        # then OPTM_SELECT
        k = key & 0x7FFF
        old = self.cursor
        if k == KEY_UP:
            self._move(-1)
        elif k == KEY_DOWN:
            self._move(+1)
        elif k == KEY_FIRST:
            self._jump(last=False)
        elif k == KEY_LAST:
            self._jump(last=True)
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
        if self.screen:
            if k in (KEY_UP, KEY_DOWN, KEY_FIRST, KEY_LAST):
                self._bar(self._pos(old), SEL_STD)  # remove the old bar
            self._loop_sel()
            self._check_screen()
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
    vol = flat_index(" Volume: %s")              # 131: the Volume opener
    adv = flat_index(" Advanced Settings")       # 167: the Advanced opener
    osm = flat_index(" OSM: %s")                 # 171: the OSM scaling opener
    fx = []
    # HDMI heading: nothing selected of its own; child skipped; the selected
    # Scanlines line inside the child must NOT leak: ends at own closer
    fx.append(("HDMI region empty -> own closer", hdmi, v6g,
               sel(i57=0, i58=0, i64=0, i65=0)))
    # HDMI heading with 4:3 576p 50 Hz selected -> found 59
    fx.append(("HDMI region finds 4:3 PAL", hdmi, v6g, sel(i57=0, i59=1)))
    # Advanced Settings: no radio group of its own at all
    fx.append(("Advanced has no own radio group", adv, v6g, base))
    # OSM scaling: default -> 174
    fx.append(("OSM scaling default", osm, v6g, base))
    # Volume (#247): default -> " 100%" (134), found before the nested Stereo
    # region; with no volume item selected the scan must skip the nested
    # Stereo region (whose " Full Stereo" stays selected) and end at its own
    # closer instead of leaking the stereo selection into "Volume: %s"
    fx.append(("Volume default", vol, v6g, base))
    novol = list(base)
    for i in group_members(V6_MENU, "VOLUME"):
        novol[i] = 0
    fx.append(("Volume empty, nested Stereo must not leak", vol, v6g, novol))
    # the nested Stereo opener itself: default " Full Stereo", and " Mono"
    smix = group_members(V6_MENU, "STEREO_MIX")
    stereo = flat_index(" Stereo: %s")           # 156: the nested opener
    fx.append(("Stereo default", stereo, v6g, base))
    mono = list(base)
    mono[smix[0]], mono[smix[3]] = 0, 1
    fx.append(("Stereo Mono", stereo, v6g, mono))
    # Keyboard Shortcuts (#142): the region of pickers has no radio group
    # of its own; each picker summarizes its own selected action
    f9 = flat_index(" F9:  %s")
    f11 = flat_index(" F11: %s")
    f12 = flat_index(" F12: %s")
    # the items of the F12 picker (f12 + 3 .. f12 + 13) straddle OSM control
    # bit 255/256: its default " Load PRG" (f12 + 9) is below the boundary,
    # " Volume up" (f12 + 13) above it
    assert f12 + 3 <= 255 and f12 + 13 >= 256
    fx.append(("Keyboard Shortcuts has no own radio group",
               flat_index(" Keyboard Shortcuts"), v6g, base))
    fx.append(("F9 picker default Freeze", f9, v6g, base))
    fx.append(("F11 picker Next disk drive 8", f11, v6g,
               sel(**{"i%d" % (f11 + 5): 0, "i%d" % (f11 + 7): 1})))
    fx.append(("F12 picker across bit 255/256", f12, v6g, base))
    fx.append(("F12 picker Volume up above bit 255", f12, v6g,
               sel(**{"i%d" % (f12 + 9): 0, "i%d" % (f12 + 13): 1})))
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
    s.feed(KEY_LAST)                # Cursor right: last item (#258)
    assert s.cursor == flat_index(" Close Menu")
    s.feed(KEY_FIRST)               # Cursor left: first item (#258)
    assert s.cursor == 2            # the first mount line
    s.feed(KEY_FIRST)               # already there: stays
    assert s.cursor == 2
    s.feed(KEY_UP)                  # wrap to "Close Menu"
    assert s.cursor == flat_index(" Close Menu")
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
    s.feed(KEY_LAST)                # last item of the nested view: " Back"
    assert (s.level, s.cursor) == (4, 79)
    s.feed(0x8000 | KEY_FIRST)      # background redraw + first item
    assert (s.level, s.cursor) == (4, 70)
    s.until(KEY_DOWN, 79)           # to the " Back" closer line
    s.feed(KEY_SELECT)              # leave via the closer
    assert (s.level, s.cursor) == (3, 67)
    s.feed(KEY_MENUUP)              # pop to main
    assert (s.level, s.cursor) == (0, 54)
    s.until(KEY_DOWN, 131)          # to "Volume: %s" - entering this region
    s.feed(KEY_SELECT)              # is the regression case for the percent-
    assert (s.level, s.cursor) == (8, 134)   # terminated-label scanner bug
    s.feed(KEY_LAST)                # last item of the Volume view: " Back"
    last_vol = s.cursor
    assert s.level == 8 and last_vol > 134 and s.g[last_vol] == 0xC0FF
    s.feed(KEY_FIRST)               # first item: " 100%"
    assert (s.level, s.cursor) == (8, 134)
    s.until(KEY_DOWN, 156)          # to the nested "Stereo: %s" (#247)
    s.feed(KEY_SELECT)              # enter region 9 (depth 2)
    assert (s.level, s.cursor) == (9, 159)   # " Full Stereo"
    s.feed(KEY_DOWN)                # " Wide Stereo"
    s.feed(KEY_SELALT)              # radio-select it via Space
    assert s.sel[160] == 1 and s.sel[159] == 0
    s.feed(KEY_LAST)                # last item of the nested view: " Back"
    assert (s.level, s.cursor) == (9, 164)
    s.feed(KEY_SELECT)              # leave via the closer: back in Volume,
    assert (s.level, s.cursor) == (8, 156)   # cursor on the nested opener
    s.feed(KEY_MENUUP)              # back to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 131)
    s.until(KEY_DOWN, 167)          # to "Advanced Settings"
    s.feed(KEY_SELECT)              # enter region 10
    assert (s.level, s.cursor) == (10, 170)
    s.feed(KEY_SELECT)              # single-select GEOS Real-Time-Clock on
    s.feed(KEY_SELECT)              # and off again
    s.until(KEY_DOWN, 171)          # to "OSM: %s"
    s.feed(KEY_SELECT)              # enter region 11 (depth 2)
    assert (s.level, s.cursor) == (11, 174)
    s.feed(0x8000 | KEY_UP)         # redraw + up: wraps within the view
    assert s.cursor == 184          # lands on the closer line
    s.feed(KEY_FIRST)               # first item of the depth-2 OSM view
    assert (s.level, s.cursor) == (11, 174)
    s.feed(0x8000 | KEY_LAST)       # background redraw + last item
    assert (s.level, s.cursor) == (11, 184)
    r = s.feed(KEY_CLOSE)           # Help: close the OSM
    assert r == "close"
    # reopen: same level and cursor (persistence)
    assert (s.level, s.cursor) == (11, 184)
    s.run_start()                   # the testbed draws before OPTM_RUN
    s.feed(KEY_MENUUP)              # pop to region 10
    assert (s.level, s.cursor) == (10, 171)
    s.feed(KEY_MENUUP)              # pop to main
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
    # Input Devices (#190, #193): the submenus Mouse and Paddles follow the
    # Keyboard Shortcuts submenu in Advanced Settings. Each holds two radio
    # groups of two items (port 1, port 2) that must not influence each
    # other. Selecting an item that is already selected is silent (no S line
    # in the trace), so a selection that wrongly cleared the other group would
    # show up in the emulator trace as an extra S line.
    mo = flat_index(" Mouse")                    # opener of region 19
    pa = flat_index(" Paddles")                  # opener of region 20
    adv_close = next(i for i in range(pa + 1, len(V6_MENU))
                     if V6_MENU[i][0] == " Back"
                     and submenu_path(V6_MENU, i) == [" Advanced Settings"])
    m1c, m1a = group_members(V6_MENU, "MOUSE_P1")
    m2c, m2a = group_members(V6_MENU, "MOUSE_P2")
    m1r, = group_members(V6_MENU, "MOUSE_P1_RCLICK")
    m2r, = group_members(V6_MENU, "MOUSE_P2_RCLICK")
    p1c, p1a = group_members(V6_MENU, "PADDLES_P1")
    p2c, p2a = group_members(V6_MENU, "PADDLES_P2")

    def radio(on, off):
        return s.sel[on] == 1 and s.sel[off] == 0

    assert radio(m1c, m1a) and radio(m2c, m2a)   # factory defaults: C64
    assert radio(p1c, p1a) and radio(p2c, p2a)
    s.feed(KEY_DOWN)                # Keyboard Shortcuts -> Mouse
    assert (s.level, s.cursor) == (10, mo)
    s.feed(KEY_SELECT)              # enter region 19 (depth 2)
    assert (s.level, s.cursor) == (19, m1c)      # " Port 1: C64"
    s.feed(KEY_DOWN)                # " Port 1: Amiga"
    s.feed(KEY_SELECT)              # radio-select it via Return
    assert radio(m1a, m1c) and radio(m2c, m2a)   # port 2 stays C64
    s.feed(KEY_DOWN)                # the switch of port 1: dependencies are
    assert s.cursor == m1r          # off here, so it is always visible
    s.feed(KEY_DOWN)                # skips the separator: " Port 2: C64"
    assert s.cursor == m2c
    s.feed(KEY_DOWN)                # " Port 2: Amiga"
    s.feed(KEY_SELALT)              # radio-select it via Space
    assert radio(m2a, m2c) and radio(m1a, m1c)   # port 1 stays Amiga
    s.until(KEY_UP, m1a)            # back to " Port 1: Amiga"
    s.feed(KEY_SELECT)              # still selected: silent
    s.until(KEY_DOWN, m2c)          # " Port 2: C64"
    s.feed(KEY_SELECT)              # port 2 back to C64, port 1 unchanged
    assert radio(m2c, m2a) and radio(m1a, m1c)
    s.feed(KEY_LAST)                # last item of the view: " Back"
    assert (s.level, s.cursor) == (19, m2r + 2)
    s.feed(KEY_SELECT)              # leave via the closer: Advanced Settings,
    assert (s.level, s.cursor) == (10, mo)       # cursor on the opener
    s.feed(KEY_DOWN)                # " Paddles"
    assert s.cursor == pa
    s.feed(KEY_SELECT)              # enter region 20 (depth 2)
    assert (s.level, s.cursor) == (20, p1c)      # " Port 1: C64"
    s.feed(KEY_LAST)                # " Back"
    assert (s.level, s.cursor) == (20, p2a + 2)
    s.feed(KEY_UP)                  # " Port 2: Atari CX30"
    assert s.cursor == p2a
    s.feed(KEY_SELECT)              # radio-select it via Return
    assert radio(p2a, p2c) and radio(p1c, p1a)   # port 1 stays C64
    s.until(KEY_UP, p1a)            # " Port 1: Atari CX30"
    s.feed(KEY_SELALT)              # radio-select it via Space
    assert radio(p1a, p1c) and radio(p2a, p2c)   # port 2 stays Atari
    assert radio(m1a, m1c) and radio(m2c, m2a)   # the mouse groups unchanged
    s.until(KEY_DOWN, p2a)          # " Port 2: Atari CX30"
    s.feed(KEY_SELALT)              # still selected: silent
    s.feed(KEY_MENUUP)              # Run/Stop: back to Advanced Settings,
    assert (s.level, s.cursor) == (10, pa)       # cursor on the opener
    s.feed(KEY_DOWN)                # the closer of Advanced Settings
    assert s.cursor == adv_close
    s.feed(KEY_SELECT)              # leave via the closer: main menu,
    assert (s.level, s.cursor) == (0, 167)       # cursor on the opener
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


# ---------------------------------------------------------------------------
# Intended layout of the Model submenu (#87): the "Turbo speed" block
# (separator, headline, 2x/3x/4x) is visible only while the turbo mode is
# C128 or Smart, so the submenu view (headline "Model" through " Back") shows
# 12 lines with Off and 17 with C128 or Smart
# ---------------------------------------------------------------------------

MODEL_VISIBLE = {"Off": 12, "C128": 17, "Smart": 17}


def model_submenu_span(menu):
    """Flat indices (opener, closer) of the " Model: %s" submenu."""
    o = [i for i, (t, _, _) in enumerate(menu) if t == " Model: %s"][0]
    depth = 0
    for i in range(o, len(menu)):
        f = tuple(menu[i][2])
        if f == OPEN:
            depth += 1
        elif f == CLOSE:
            depth -= 1
            if depth == 0:
                return o, i
    raise AssertionError("the Model submenu has no closer")


def visible_lines(groups, level, resolved, stdsel):
    """Flat indices of the lines visible in the view of the given level."""
    b = build_new(groups, level, resolved, stdsel)
    return [i for i, w in enumerate(b["arr"]) if w & 0x8000]


def double_separators(vis, labels):
    """Pairs of visible separator lines (empty label) that follow each other
    directly in a view; vis is the list of visible flat indices."""
    return [(a, b) for a, b in zip(vis, vis[1:])
            if labels[a] == "" and labels[b] == ""]


def mother_states(menu, mother):
    """Every selectable state of a dependency mother group as a dict
    {flat index: selected 0/1} over its members."""
    mem = group_members(menu, mother)
    if "SINGLESEL" in menu[mem[0]][2]:
        return [{mem[0]: 0}, {mem[0]: 1}]
    return [{j: int(j == k) for j in mem} for k in mem]


def menu_layout_errors():
    """The intended layout of the V6 menu, checked on the golden model:
    (1) no view shows two separator lines in a row, in every combination of
    the states of all dependency mothers; (2) the Model submenu shows
    MODEL_VISIBLE lines per turbo mode, with the Turbo speed block exactly
    while the turbo mode is C128 or Smart; (3) the turbo toggle walk of
    nav_turbo_toggles() passes on the complete V6 menu with dependencies on.
    Returns a list of error strings."""
    import itertools
    errors = []
    menu = V6_MENU
    labels = [t for t, _, _ in menu]
    g = menu_masked(menu)
    s0 = menu_stdsel(menu)
    res = resolve_deps(g, menu_deps_raw(menu, V6_DEPS))
    mothers = []
    for i in sorted(V6_DEPS):
        if V6_DEPS[i][0] not in mothers:
            mothers.append(V6_DEPS[i][0])
    doubles = set()
    for combo in itertools.product(*[mother_states(menu, m) for m in mothers]):
        s = list(s0)
        for state in combo:
            for j, v in state.items():
                s[j] = v
        for lv in range(num_regions(g) + 1):
            for a, b in double_separators(visible_lines(g, lv, res, s), labels):
                doubles.add((lv, a, b))
    for lv, a, b in sorted(doubles):
        errors.append("view %d shows the separators %d and %d in a row in "
                      "some state of the dependency mothers" % (lv, a, b))

    opener, _ = model_submenu_span(menu)
    level = build_new(g, 0)["arr"][opener] & 0x7FFF
    turbo = group_members(menu, "TURBO_MODE")
    speed = group_members(menu, "TURBO_SPEED")
    names = [labels[j].strip() for j in turbo]
    if sorted(names) != sorted(MODEL_VISIBLE):
        errors.append("TURBO_MODE items %r, MODEL_VISIBLE expects %r"
                      % (names, sorted(MODEL_VISIBLE)))
    else:
        for k, name in zip(turbo, names):
            s = list(s0)
            for j in turbo:
                s[j] = int(j == k)
            vis = visible_lines(g, level, res, s)
            if len(vis) != MODEL_VISIBLE[name]:
                errors.append("Model submenu with turbo %s: %d visible lines, "
                              "expected %d" % (name, len(vis),
                                               MODEL_VISIBLE[name]))
            if [j in vis for j in speed] != [name != "Off"] * len(speed):
                errors.append("Model submenu with turbo %s: the Turbo speed "
                              "items are %s" % (name, "shown" if name == "Off"
                                                else "hidden"))
    try:
        nav_turbo_v6_model()
    except AssertionError as e:
        errors.append("turbo toggle walk on the V6 menu: %s" % e)
    errors += input_devices_errors()
    return errors


def nav_turbo_toggles(s, ofs):
    """Toggle the radio mother TURBO_MODE in its own view: Off -> C128 ->
    Smart -> Off. s is a NavSim at the main level whose menu holds the V6
    Model submenu at V6 flat index + ofs (the dependency feature on). After
    each toggle the cursor must stay on the toggled item (the structure
    rebuild of the mother toggle), the view must show MODEL_VISIBLE lines
    without double separators, and the Turbo speed block must be visible
    exactly for C128 and Smart. The cursor moves prove the visibility in the
    emulator trace as well: with Off, DOWN from Smart lands on Back; with
    C128 or Smart it lands on 2x."""
    opener, closer = [i + ofs for i in model_submenu_span(V6_MENU)]
    off, c128, smart = [i + ofs for i in group_members(V6_MENU, "TURBO_MODE")]
    speed = [i + ofs for i in group_members(V6_MENU, "TURBO_SPEED")]
    pal = group_members(V6_MENU, "MACHINE_MODE")[0] + ofs
    names = {off: "Off", c128: "C128", smart: "Smart"}

    s.until(KEY_DOWN, opener)
    s.feed(KEY_SELECT)                  # enter the Model submenu
    assert s.cursor == pal, "enter landed on %d, not on PAL" % s.cursor
    level = s.level

    def check(item, cursor=None):
        name = names[item]
        cursor = item if cursor is None else cursor
        vis = [i for i, w in enumerate(s._struct()["arr"]) if w & 0x8000]
        assert (s.level, s.cursor) == (level, cursor), (
            "turbo %s: level/cursor %d/%d, expected %d/%d"
            % (name, s.level, s.cursor, level, cursor))
        assert s.sel[item] == 1, "turbo %s is not selected" % name
        assert len(vis) == MODEL_VISIBLE[name], (
            "turbo %s: %d visible lines, expected %d"
            % (name, len(vis), MODEL_VISIBLE[name]))
        assert [i in vis for i in speed] == [item != off] * len(speed), (
            "turbo %s: wrong Turbo speed visibility" % name)
        assert not double_separators(vis, s.labels), (
            "turbo %s: double separator" % name)

    check(off, pal)                     # factory default: block hidden
    s.feed(KEY_LAST)                    # Cursor right: " Back" (#258)
    assert s.cursor == closer, "Off: LAST went to %d" % s.cursor
    s.feed(KEY_FIRST)                   # Cursor left: PAL
    assert s.cursor == pal, "Off: FIRST went to %d" % s.cursor
    s.until(KEY_DOWN, smart)
    s.feed(KEY_DOWN)                    # hidden block: Smart -> Back
    assert s.cursor == closer, "Off: DOWN from Smart went to %d" % s.cursor
    s.until(KEY_UP, c128)
    s.feed(KEY_SELECT)                  # Off -> C128: the block appears
    check(c128)
    s.feed(KEY_DOWN)                    # Smart
    s.feed(KEY_DOWN)                    # the first speed item
    assert s.cursor == speed[0], "C128: DOWN from Smart went to %d" % s.cursor
    s.feed(KEY_UP)                      # back to Smart
    s.feed(KEY_SELECT)                  # C128 -> Smart: the block stays
    check(smart)
    s.feed(KEY_LAST)                    # Cursor right: " Back", also with
    assert s.cursor == closer, "Smart: LAST went to %d" % s.cursor
    s.feed(KEY_UP)                      # the speed block visible: UP from
    assert s.cursor == speed[-1], "Smart: UP from Back went to %d" % s.cursor
    s.until(KEY_UP, smart)              # Back is 4x; back to Smart
    s.feed(KEY_DOWN)
    assert s.cursor == speed[0], "Smart: DOWN went to %d" % s.cursor
    s.until(KEY_UP, off)
    s.feed(KEY_SELECT)                  # Smart -> Off: the block hides
    check(off)
    for expect in (c128, smart, closer):    # Off, C128, Smart, then Back
        s.feed(KEY_DOWN)
        assert s.cursor == expect, "Off: DOWN went to %d, expected %d" % (
            s.cursor, expect)
    s.feed(KEY_SELECT)                  # leave via Back
    assert (s.level, s.cursor) == (0, opener), "Back did not return to main"


def nav_turbo_v6_model():
    """The turbo toggle walk on the complete V6 menu with the dependency
    feature on (model only; scenario 3 runs the same walk in the emulator
    on a verbatim copy of the Model submenu)."""
    s = NavSim(menu_masked(V6_MENU), menu_stdsel(V6_MENU), nav_start(),
               labels=[t for t, _, _ in V6_MENU],
               raw_deps=menu_deps_raw(V6_MENU, V6_DEPS))
    s.run_start()
    nav_turbo_toggles(s, 0)
    assert s.feed(KEY_MENUUP) == "close", "Run/Stop at main did not close"


# Scenario 3 appends a verbatim copy of the V6 Model submenu (opener through
# closer, with its real group words and OPTM_DEP2 dependencies) to the
# synthetic lines 0..6, so the emulator runs the turbo toggle walk on the real
# layout: a radio mother whose dependent lines live in the same view
NAV3_SYN_N = 7
_NAV3_MO, _NAV3_MC = model_submenu_span(V6_MENU)
NAV3_MODEL = list(range(_NAV3_MO, _NAV3_MC + 1))    # V6 flat indices
NAV3_MODEL_OFS = NAV3_SYN_N - _NAV3_MO              # V6 index -> NAV3 index
NAV3_LABELS = ([" Tog", " D:%s", " E:%s", " S:%s", " F", " G", " back"]
               + [V6_MENU[i][0] for i in NAV3_MODEL] + [" quit"])


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
    the deps-off scenarios 1 and 2. The copied V6 Model submenu (region 2)
    then drives the turbo toggle walk of nav_turbo_toggles(): a radio
    mother toggled in the same view as its dependent lines."""
    v6g = menu_masked(V6_MENU)
    v6raw = menu_deps_raw(V6_MENU, V6_DEPS)
    v6sel = menu_stdsel(V6_MENU)
    groups = [
        0x8001,   # 0 single-select toggle, mother gid 1
        0x0002,   # 1 dependent radio gid 2, mask 0b10: same view as the mother
        0x0003,   # 2 radio gid 3 (always visible)
        0xC000,   # 3 open region 1 (submenu " S:%s")
        0x0004,   # 4 dependent radio gid 4, mask 0b10: first content of reg. 1
        0x0005,   # 5 radio gid 5 (always visible)
        0xC0FF,   # 6 close region 1
    ] + [v6g[i] for i in NAV3_MODEL] + [   # 7.. region 2: the Model submenu
        0x00FF,   # Close Menu
    ]
    n = len(groups)
    raw = [0] * n
    raw[1] = 0x1000 | (0b10 << 8) | 1   # dep(gid 1, mask 0b10): visible if ON
    raw[4] = 0x1000 | (0b10 << 8) | 1
    for i in NAV3_MODEL:                # the real Turbo speed dependencies
        raw[i + NAV3_MODEL_OFS] = v6raw[i]
    stdsel = ([0] * NAV3_SYN_N          # toggle OFF
              + [v6sel[i] for i in NAV3_MODEL] + [0])   # PAL, Off, 2x
    s = NavSim(groups, stdsel, NAV3_START, labels=NAV3_LABELS, raw_deps=raw)
    s.run_start()                       # normalization: idx1 is dep-hidden ->
    assert s.cursor == 2                # the cursor advances to idx2
    s.feed(KEY_LAST)                    # Cursor right: "Close Menu" (#258)
    assert s.cursor == n - 1
    s.feed(KEY_FIRST)                   # Cursor left: the toggle
    assert s.cursor == 0
    s.until(KEY_DOWN, 2)                # back to idx2 (skips hidden idx1)
    s.until(KEY_UP, 0)                  # to the toggle (skips hidden idx1)
    s.feed(KEY_SELECT)                  # toggle ON  -> redraw, idx1 appears
    s.feed(KEY_SELECT)                  # toggle OFF -> redraw, idx1 hidden
    s.until(KEY_DOWN, 3)                # to the submenu opener
    s.feed(KEY_SELECT)                  # enter: idx4 dep-hidden (OFF), scan
    assert (s.level, s.cursor) == (1, 5)   # skips it -> lands on idx5
    s.feed(KEY_LAST)                    # last item: the closer idx6
    assert (s.level, s.cursor) == (1, 6)
    s.feed(KEY_FIRST)                   # first item: idx4 is dep-hidden, so
    assert (s.level, s.cursor) == (1, 5)   # it must be idx5
    s.feed(KEY_MENUUP)                  # back to main, cursor on the opener
    assert (s.level, s.cursor) == (0, 3)
    s.until(KEY_UP, 0)                  # back to the toggle
    s.feed(KEY_SELECT)                  # toggle ON
    s.until(KEY_DOWN, 3)               # to the opener (idx1 is visible now)
    s.feed(KEY_SELECT)                  # enter: idx4 now visible -> lands there
    assert (s.level, s.cursor) == (1, 4)
    s.feed(KEY_LAST)                    # last item: the closer idx6
    assert (s.level, s.cursor) == (1, 6)
    s.feed(KEY_FIRST)                   # first item: idx4, visible now
    assert (s.level, s.cursor) == (1, 4)
    s.feed(KEY_MENUUP)
    assert (s.level, s.cursor) == (0, 3)
    nav_turbo_toggles(s, NAV3_MODEL_OFS)   # Model submenu: Off/C128/Smart/Off
    r = s.feed(KEY_MENUUP)              # Run/Stop at main: close
    assert r == "close"
    return groups, stdsel, raw, s.keys, s.trace


def mouse_view_lines(a1, a2):
    """The lines of the V6 Mouse submenu view (headline to Back) while port 1
    (a1) and port 2 (a2) are set to Amiga (1) or C64 (0): the switch
    "MEGA+left = right" of a port directly behind its Amiga item, only while
    that item is selected (#190)"""
    mo = flat_index(" Mouse")
    m1c, m1a = group_members(V6_MENU, "MOUSE_P1")
    m2c, m2a = group_members(V6_MENU, "MOUSE_P2")
    m1r, = group_members(V6_MENU, "MOUSE_P1_RCLICK")
    m2r, = group_members(V6_MENU, "MOUSE_P2_RCLICK")
    back = mouse_back()
    return ([mo + 1, mo + 2, m1c, m1a] + ([m1r] if a1 else []) + [m1r + 1,
            m2c, m2a] + ([m2r] if a2 else []) + [m2r + 1, back])


def mouse_back():
    """Flat index of the closer (" Back") of the V6 Mouse submenu"""
    mo = flat_index(" Mouse")
    return next(i for i in range(mo + 1, len(V6_MENU))
                if tuple(V6_MENU[i][2]) == CLOSE
                and submenu_path(V6_MENU, i) == [" Advanced Settings", " Mouse"])


def nav4_script():
    """Scenario 4: the complete V6 menu with the dependency feature on and
    the screen trace on (see NavSim). It walks into the Mouse submenu and
    proves the two switches "MEGA+left = right" (#190): hidden while their
    port is C64, shown directly behind the Amiga item of their own port,
    toggled by Return and Space, each changing exactly its own menu bit,
    independent of each other and of the four radio groups of the Mouse and
    Paddles submenus, keeping their bit while hidden and showing it again;
    the cursor movement in all four visibility states; Back and Run/Stop.
    The testbed starts from the factory defaults (no config file), so both
    switches are off. Every key is checked against the screen model by
    NavSim._check_screen(); the emulator trace has to match the model."""
    labels = [t for t, _, _ in V6_MENU]
    s = NavSim(menu_masked(V6_MENU), menu_stdsel(V6_MENU), nav_start(),
               labels=labels, raw_deps=menu_deps_raw(V6_MENU, V6_DEPS),
               screen=True, lines=menu_lines(V6_MENU))
    adv = flat_index(" Advanced Settings")
    mo = flat_index(" Mouse")
    pa = flat_index(" Paddles")
    m1c, m1a = group_members(V6_MENU, "MOUSE_P1")
    m2c, m2a = group_members(V6_MENU, "MOUSE_P2")
    m1r, = group_members(V6_MENU, "MOUSE_P1_RCLICK")
    m2r, = group_members(V6_MENU, "MOUSE_P2_RCLICK")
    p1c, p1a = group_members(V6_MENU, "PADDLES_P1")
    back = mouse_back()

    def flip(key, changed):
        """press key and check that exactly the items in changed flip"""
        before = list(s.sel)
        assert s.feed(key) is None
        diff = [i for i in range(s.n) if s.sel[i] != before[i]]
        assert diff == sorted(changed), "key %d changed %r, expected %r" % (
            key, diff, sorted(changed))

    def view(a1, a2):
        vis = s._vis()
        assert vis == mouse_view_lines(a1, a2), (
            "Mouse view %d/%d shows %r" % (a1, a2, vis))
        if not a1:                      # behind " Port 1: Amiga": separator
            assert labels[vis[vis.index(m1a) + 1]] == ""
        return [i for i in vis if s.g[i] & 0x4000 or s.g[i] & 0xFF]

    def walk(a1, a2):
        """first and last item (#258), a full cycle down and up with the
        wrap-around, over the place of every hidden line; ends on Back"""
        order = view(a1, a2)
        assert order[-1] == back
        s.feed(KEY_FIRST)
        assert s.cursor == order[0]
        for c in order[1:] + order[:1]:
            s.feed(KEY_DOWN)
            assert s.cursor == c, "DOWN went to %d, expected %d" % (s.cursor, c)
        s.feed(KEY_LAST)
        assert s.cursor == back
        for c in order[-2::-1] + order[-1:]:
            s.feed(KEY_UP)
            assert s.cursor == c, "UP went to %d, expected %d" % (s.cursor, c)

    s.run_start()
    assert s.sel[m1r] == 0 and s.sel[m2r] == 0  # factory defaults: off
    s.until(KEY_DOWN, adv)
    s.feed(KEY_SELECT)                  # enter Advanced Settings
    adv_level = s.level
    s.until(KEY_DOWN, mo)
    s.feed(KEY_SELECT)                  # enter Mouse
    level = s.level
    assert s.cursor == m1c
    walk(0, 0)                          # both C64: no switch shown
    s.until(KEY_DOWN, m1a)              # wraps from Back
    flip(KEY_SELECT, [m1c, m1a])        # Port 1: Amiga
    walk(1, 0)                          # #1 directly behind it, #2 hidden
    s.until(KEY_DOWN, m1r)
    for key, on in ((KEY_SELECT, 1), (KEY_SELALT, 0), (KEY_SELALT, 1),
                    (KEY_SELECT, 0), (KEY_SELALT, 1)):
        flip(key, [m1r])                # Return and Space toggle #1 alone
        assert s.sel[m1r] == on
    s.until(KEY_DOWN, m2a)
    flip(KEY_SELALT, [m2c, m2a])        # Port 2: Amiga
    assert s.sel[m1r] == 1
    walk(1, 1)                          # both switches shown
    s.until(KEY_UP, m2r)
    flip(KEY_SELECT, [m2r])             # #2 on, #1 stays on
    flip(KEY_SELALT, [m2r])             # #2 off
    flip(KEY_SELECT, [m2r])             # #2 on
    s.until(KEY_UP, m1r)
    flip(KEY_SELALT, [m1r])             # #1 off, #2 stays on
    flip(KEY_SELECT, [m1r])             # #1 on
    s.until(KEY_UP, m1c)
    flip(KEY_SELECT, [m1c, m1a])        # Port 1: C64 hides #1, keeps its bit
    assert s.sel[m1r] == 1 and s.sel[m2r] == 1
    walk(0, 1)
    s.until(KEY_DOWN, m2c)
    flip(KEY_SELALT, [m2c, m2a])        # Port 2: C64 hides #2, keeps its bit
    assert s.sel[m1r] == 1 and s.sel[m2r] == 1
    walk(0, 0)                          # both hidden and on
    s.until(KEY_DOWN, m1a)
    flip(KEY_SELECT, [m1c, m1a])        # Port 1: Amiga: #1 shown, still on
    view(1, 0)
    s.feed(KEY_DOWN)
    assert s.cursor == m1r
    flip(KEY_SELECT, [m1r])             # off: the firmware had it on
    assert s.sel[m1r] == 0
    s.until(KEY_DOWN, m2a)
    flip(KEY_SELECT, [m2c, m2a])        # Port 2: Amiga: #2 shown, still on
    view(1, 1)
    s.feed(KEY_DOWN)
    assert s.cursor == m2r
    flip(KEY_SELALT, [m2r])             # off: the firmware had it on
    assert s.sel[m2r] == 0
    flip(KEY_SELALT, [m2r])             # and on again
    s.feed(KEY_LAST)
    assert s.cursor == back
    s.feed(KEY_SELECT)                  # leave via Back
    assert (s.level, s.cursor) == (adv_level, mo)
    s.feed(KEY_SELECT)                  # enter again: the state persists
    assert (s.level, s.cursor) == (level, m1c)
    view(1, 1)
    s.until(KEY_DOWN, m2a)
    s.feed(KEY_MENUUP)                  # Run/Stop: back to Advanced Settings
    assert (s.level, s.cursor) == (adv_level, mo)
    s.feed(KEY_DOWN)
    assert s.cursor == pa
    s.feed(KEY_SELECT)                  # enter Paddles
    assert s.cursor == p1c
    s.feed(KEY_DOWN)
    flip(KEY_SELECT, [p1c, p1a])        # the paddle groups leave the
    flip(KEY_SELECT, [])                # switches alone (already selected)
    s.feed(KEY_UP)
    flip(KEY_SELALT, [p1c, p1a])
    s.feed(KEY_MENUUP)
    assert (s.level, s.cursor) == (adv_level, pa)
    s.feed(KEY_MENUUP)
    assert (s.level, s.cursor) == (0, adv)
    assert s.sel[m1r] == 0 and s.sel[m2r] == 1
    r = s.feed(KEY_MENUUP)              # Run/Stop at main: close
    assert r == "close"
    return s.keys, s.trace


def expect_nav():
    _, trace = nav_script()
    _, _, _, trace2 = nav2_script()
    _, _, _, _, trace3 = nav3_script()
    _, trace4 = nav4_script()
    return ("\n".join(trace) + "\nN2\n" + "\n".join(trace2)
            + "\nN3\n" + "\n".join(trace3)
            + "\nN4\n" + "\n".join(trace4) + "\nDONE\n")


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
    keys4, _ = nav4_script()
    L.append("")
    L.append("; scenario 4: the V6 menu of scenario 1 with the dependency feature")
    L.append("; on and the screen trace on, see nav4_script() in menu_test.py")
    L.append("NAV4_DEPS")                    # resolved dependency array
    L += dw_lines(resolve_deps(g, menu_deps_raw(V6_MENU, V6_DEPS)))
    L.append("NAV4_LINES")                   # separator flags
    L += dw_lines(menu_lines(V6_MENU))
    L.append("NAV4_X          .EQU %d" % NAV4_X)
    L.append("NAV4_SCRIPT_CNT .EQU %d" % len(keys4))
    L.append("NAV4_SCRIPT")
    L += dw_lines(keys4)
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
    ("C_MENU_STEREO_MIX_FULL",   "STEREO_MIX", 0),
    ("C_MENU_STEREO_MIX_WIDE",   "STEREO_MIX", 1),
    ("C_MENU_STEREO_MIX_NARROW", "STEREO_MIX", 2),
    ("C_MENU_STEREO_MIX_MONO",   "STEREO_MIX", 3),
    ("C_MENU_SC_F9",      "SC_F9", 0),   # first item ("Off") of the F9 picker (#142)
    ("C_MENU_SC_F10",     "SC_F10", 0),   # first item ("Off") of the F10 picker (#142)
    ("C_MENU_SC_F11",     "SC_F11", 0),   # first item ("Off") of the F11 picker (#142)
    ("C_MENU_SC_F12",     "SC_F12", 0),   # first item ("Off") of the F12 picker (#142)
    ("C_MENU_SC_F13",     "SC_F13", 0),   # first item ("Off") of the F13 picker (#142)
    ("C_MENU_SC_F14",     "SC_F14", 0),   # first item ("Off") of the F14 picker (#142)
    ("C_MENU_VOLUME_100",   "VOLUME", 0),   # 100%: first item of the volume radio group
    # Input Devices (#190, #193): the non-default item of each radio group,
    # pinned to its label and submenu by input_devices_errors() below
    ("C_MENU_MOUSE_P1_AMIGA",   "MOUSE_P1", 1),     # Amiga mouse at port 1
    ("C_MENU_MOUSE_P2_AMIGA",   "MOUSE_P2", 1),     # Amiga mouse at port 2
    ("C_MENU_MOUSE_P1_RCLICK",  "MOUSE_P1_RCLICK", 0),  # MEGA+left = right, port 1
    ("C_MENU_MOUSE_P2_RCLICK",  "MOUSE_P2_RCLICK", 0),  # MEGA+left = right, port 2
    ("C_MENU_PADDLES_P1_ATARI", "PADDLES_P1", 1),   # Atari CX30 paddles at port 1
    ("C_MENU_PADDLES_P2_ATARI", "PADDLES_P2", 1),   # Atari CX30 paddles at port 2
    # the simulated RR-Net is not a list of single C_MENU_* constants: mega65.vhd
    # decodes its three "On" items as one slice, see rrnet_range() below
]


def group_members(menu, gname):
    return [i for i, (_, g, _) in enumerate(menu) if g == gname]


def c_menu_values():
    """name -> flat index in the V6 menu, derived independently from labels
    and group ordinals. An entry whose group has no member with its ordinal
    is left out; c_menu_errors() reports it."""
    out = {}
    for name, gname, ordinal in C_MENU:
        members = group_members(V6_MENU, gname)
        if 0 <= ordinal < len(members):
            out[name] = members[ordinal]
    return out


def c_menu_errors():
    """The C_MENU entries that c_menu_values() cannot resolve."""
    errors = []
    for name, gname, ordinal in C_MENU:
        members = group_members(V6_MENU, gname)
        if not 0 <= ordinal < len(members):
            errors.append("%s: group %s has %d member(s) in the golden model, "
                          "there is no item with the ordinal %d"
                          % (name, gname, len(members), ordinal))
    return errors


def volume_indices():
    return group_members(V6_MENU, "VOLUME")


def osm_scaling_range():
    m = group_members(V6_MENU, "OSM_MODE")
    assert m == list(range(m[0], m[0] + len(m)))
    return (m[-1], m[0])


def rrnet_range():
    """The three "On" items of the simulated RR-Net radio group, as the
    (hi, lo) slice mega65.vhd decodes (R_MENU_RRNET). Item 0 of the group is
    "Off" and is encoded as "none of the three bits set", so it stays outside
    the slice.

    The slice is positional, so the encoding silently inverts if the group is
    ever reordered. Pin the layout down here: four contiguous items, "Off"
    first and carrying the default selection, then MK2, MK3 standard ROM and
    MK3 custom ROM in the order mega65.vhd decodes as "001"/"010"/"100"."""
    m = group_members(V6_MENU, "SIM_RRNET")
    assert m == list(range(m[0], m[0] + len(m))), "RR-Net group is not contiguous"
    labels = [V6_MENU[i][0] for i in m]
    assert labels == [" Off", " On: MK2", " On: MK3 & Std ROM",
                      " On: MK3 & Custom ROM"], \
        "RR-Net group reordered/renamed: %r - R_MENU_RRNET no longer decodes " \
        "the same modes, see mega65.vhd" % (labels,)
    assert "STDSEL" in V6_MENU[m[0]][2], "RR-Net default is no longer \" Off\""
    return (m[-1], m[1])


# The Input Devices section of Advanced Settings (#190, #193): each constant is
# the flat index of the non-default item of a radio group of two. mega65.vhd
# decodes only that bit, so a constant that points to the C64 item or to the
# other port silently inverts or swaps a device. Pin each constant to its
# label, its group, its submenu and its default partner directly in front of it.
INPUT_DEVICES = [
    # (constant, submenu, item label, group, label of the default item)
    ("C_MENU_MOUSE_P1_AMIGA",   " Mouse",   " Port 1: Amiga",      "MOUSE_P1",   " Port 1: C64"),
    ("C_MENU_MOUSE_P2_AMIGA",   " Mouse",   " Port 2: Amiga",      "MOUSE_P2",   " Port 2: C64"),
    ("C_MENU_PADDLES_P1_ATARI", " Paddles", " Port 1: Atari CX30", "PADDLES_P1", " Port 1: C64"),
    ("C_MENU_PADDLES_P2_ATARI", " Paddles", " Port 2: Atari CX30", "PADDLES_P2", " Port 2: C64"),
]

# the lines of the Advanced Settings view from the Input Devices headline on
INPUT_DEVICES_VIEW = [" Input Devices", "", " Keyboard Shortcuts", " Mouse",
                      " Paddles", "", " Back"]

# The switches "MEGA+left = right" of the Mouse submenu (#190): each constant
# is the flat index of a single-select item that is off by default, the only
# member of its group, directly behind the Amiga item of its own port, and a
# dependent line of the radio group of its own port that is visible only
# while item 1 of that group (Amiga) is selected. mega65.vhd decodes the bit
# as it is, so a constant that points to another line, a default that is on
# or a dependency on the wrong port silently changes the mouse of a port.
INPUT_RCLICK = [
    # (constant, item label, group, constant of the Amiga item, mother group)
    ("C_MENU_MOUSE_P1_RCLICK", " #1: MEGA+left = right", "MOUSE_P1_RCLICK",
     "C_MENU_MOUSE_P1_AMIGA", "MOUSE_P1"),
    ("C_MENU_MOUSE_P2_RCLICK", " #2: MEGA+left = right", "MOUSE_P2_RCLICK",
     "C_MENU_MOUSE_P2_AMIGA", "MOUSE_P2"),
]


def submenu_path(menu, idx):
    """Labels of the submenu openers that enclose line idx, outermost first
    (an opener is not part of its own path, a closer is)."""
    stack = []
    for i in range(idx):
        f = tuple(menu[i][2])
        if f == OPEN:
            stack.append(menu[i][0])
        elif f == CLOSE:
            stack.pop()
    return stack


def input_devices_errors():
    """Structural checks of the Input Devices section on the golden model.
    Returns a list of error strings."""
    errors = []
    menu = V6_MENU
    vals = c_menu_values()
    adv = " Advanced Settings"
    for name, sub, label, gname, dlabel in INPUT_DEVICES:
        if name not in vals:
            errors.append("%s cannot be resolved in the golden model (see the "
                          "C_MENU errors)" % name)
            continue
        v = vals[name]
        t, g, f = menu[v]
        if (t, g) != (label, gname) or "STDSEL" in f:
            errors.append("%s = %d points to %r (group %s, flags %r), expected "
                          "the non-default %r of %s" % (name, v, t, g, f, label, gname))
        if submenu_path(menu, v) != [adv, sub]:
            errors.append("%s = %d is in the submenu path %r, expected %r"
                          % (name, v, submenu_path(menu, v), [adv, sub]))
        mem = group_members(menu, gname)
        if mem != [v - 1, v]:
            errors.append("group %s has the members %r, expected the default "
                          "directly followed by %s = %d" % (gname, mem, name, v))
        elif menu[v - 1][0] != dlabel or "STDSEL" not in menu[v - 1][2]:
            errors.append("group %s: line %d is %r %r, expected the default %r"
                          % (gname, v - 1, menu[v - 1][0], menu[v - 1][2], dlabel))
    for sub in (" Mouse", " Paddles"):
        op = [i for i, (t, _, f) in enumerate(menu) if t == sub and tuple(f) == OPEN]
        if len(op) != 1:
            errors.append("%d openers %r, expected one" % (len(op), sub))
        elif submenu_path(menu, op[0]) != [adv]:
            errors.append("opener %r is in %r, expected %r"
                          % (sub, submenu_path(menu, op[0]), [adv]))
    g = menu_masked(menu)
    opener = flat_index(adv)
    level = build_new(g, 0)["arr"][opener] & 0x7FFF
    vis = visible_lines(g, level, None, menu_stdsel(menu))
    labels = [menu[i][0] for i in vis]
    if " Input Devices" not in labels:
        errors.append("no Input Devices headline in the Advanced Settings view")
    else:
        tail = labels[labels.index(" Input Devices"):]
        if tail != INPUT_DEVICES_VIEW:
            errors.append("Advanced Settings view from Input Devices on: %r, "
                          "expected %r" % (tail, INPUT_DEVICES_VIEW))
    errors += input_rclick_errors()
    return errors


def input_rclick_errors():
    """Checks of the two switches "MEGA+left = right" on the golden model
    (see INPUT_RCLICK): the items themselves, their dependency, the Mouse
    view in every state of the two mothers and the two switches, and the
    walk of scenario 4 (nav4_script). Returns a list of error strings."""
    import itertools
    errors = []
    menu = V6_MENU
    vals = c_menu_values()
    path = [" Advanced Settings", " Mouse"]
    for name, label, gname, amiga, mother in INPUT_RCLICK:
        if name not in vals or amiga not in vals:
            errors.append("%s or %s cannot be resolved in the golden model "
                          "(see the C_MENU errors)" % (name, amiga))
            continue
        v = vals[name]
        t, grp, f = menu[v]
        if (t, grp, list(f)) != (label, gname, ["SINGLESEL"]):
            errors.append("%s = %d is %r (group %s, flags %r), expected the "
                          "single-select item %r of %s that is off by default"
                          % (name, v, t, grp, list(f), label, gname))
        if group_members(menu, gname) != [v]:
            errors.append("group %s has the members %r, expected only %s = %d"
                          % (gname, group_members(menu, gname), name, v))
        if submenu_path(menu, v) != path:
            errors.append("%s = %d is in the submenu path %r, expected %r"
                          % (name, v, submenu_path(menu, v), path))
        if vals[amiga] != v - 1:
            errors.append("%s = %d is not directly behind %s = %d"
                          % (name, v, amiga, vals[amiga]))
        mem = group_members(menu, mother)
        if V6_DEPS.get(v) != (mother, 0b0010) or len(mem) != 2 \
                or mem[1] != vals[amiga]:
            errors.append("%s = %d depends on %r, expected item 1 (%s = %d) "
                          "of %s only, mask 0b0010"
                          % (name, v, V6_DEPS.get(v), amiga, vals[amiga], mother))
    if errors:
        return errors
    # the Mouse view in all states of the two mothers and the two switches:
    # a switch is shown exactly while its own port is set to Amiga
    g = menu_masked(menu)
    res = resolve_deps(g, menu_deps_raw(menu, V6_DEPS))
    mo = flat_index(" Mouse")
    level = build_new(g, 0)["arr"][flat_index(" Advanced Settings")] & 0x7FFF
    level = build_new(g, level)["arr"][mo] & 0x7FFF
    m1 = group_members(menu, "MOUSE_P1")
    m2 = group_members(menu, "MOUSE_P2")
    r1, r2 = vals["C_MENU_MOUSE_P1_RCLICK"], vals["C_MENU_MOUSE_P2_RCLICK"]
    for a1, a2, s1, s2 in itertools.product((0, 1), repeat=4):
        s = menu_stdsel(menu)
        s[m1[0]], s[m1[1]] = 1 - a1, a1
        s[m2[0]], s[m2[1]] = 1 - a2, a2
        s[r1], s[r2] = s1, s2
        vis = visible_lines(g, level, res, s)
        if vis != mouse_view_lines(a1, a2):
            errors.append("Mouse view with port 1 %s, port 2 %s, switches "
                          "%d/%d: lines %r, expected %r"
                          % ("Amiga" if a1 else "C64", "Amiga" if a2 else "C64",
                             s1, s2, vis, mouse_view_lines(a1, a2)))
    try:
        nav4_script()
    except (AssertionError, ValueError, IndexError, StopIteration) as e:
        errors.append("walk through the Mouse submenu (scenario 4): %s: %s"
                      % (type(e).__name__, e))
    return errors


def vhdl_tb_vectors():
    """(28-bit address, expected 16-bit data) pairs for the SEL_OPTM_DEPS
    decoder, derived from the golden model. Closes the VHDL->QNICE raw-word
    contract that verify()/run() otherwise never exercise (#2). Every line
    of the menu is probed, not only the V6_DEPS lines: a dependency that
    config.vhd declares but the model does not track reads back as a
    non-zero word where the model expects 0x0000. Every line is also probed
    through SEL_OPTM_GROUPS, SEL_OPTM_STDSEL and SEL_OPTM_SINGLESEL."""
    raw = menu_deps_raw(V6_MENU, V6_DEPS)
    SEL = 0x0313
    vecs = []
    for idx in range(len(V6_MENU)):               # every line: dependent or 0
        vecs.append((SEL << 12 | idx, raw[idx]))
    # every line through SEL_OPTM_GROUPS (the 16-bit view of the firmware),
    # SEL_OPTM_STDSEL (the factory default that the Shell uses without a
    # config file) and SEL_OPTM_SINGLESEL
    for idx, w in enumerate(menu_words(V6_MENU, V6_DEPS)):
        vecs.append((0x0301 << 12 | idx, masked(w)))
        vecs.append((0x0302 << 12 | idx, (w >> 8) & 1))
        vecs.append((0x0307 << 12 | idx, (w >> 15) & 1))
    vecs.append((SEL << 12 | 0xFFF, 0x2DEF))      # feature probe: dep format 2
    vecs.append((0x0305 << 12 | 0, len(V6_MENU))) # SEL_OPTM_ICOUNT: full 16 bits
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
    print("VHDL DECODER TB: OK (config.vhd SEL_OPTM_DEPS, GROUPS, STDSEL and "
          "SINGLESEL decoders match the model, %d vectors)" % len(vhdl_tb_vectors()))
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
        if name in vals:
            out.append("constant %-33s: natural := %d;" % (name, vals[name]))
        else:
            out.append("-- %s: no line in the golden model" % name)
    for e in c_menu_errors():
        out.append("-- ERROR: " + e)
    lo, hi = osm_scaling_range()[1], osm_scaling_range()[0]
    out.append("subtype C_MENU_OSM_SCALING is natural range %d downto %d;"
               % (hi, lo))
    vol = volume_indices()
    out.append("subtype C_MENU_VOLUME is natural range %d downto %d;"
               % (vol[-1], vol[0]))
    rhi, rlo = rrnet_range()
    out.append("subtype R_MENU_RRNET is natural range %d downto %d;"
               % (rhi, rlo))
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


def config_deps_errors(entries, vals):
    """Cross-check every dependency that config.vhd declares against V6_DEPS,
    in both directions. entries are the OPTM_GROUPS source expressions and
    vals their evaluated values, one per flat line. A line is dependent in
    config.vhd if it calls OPTM_DEP / OPTM_DEP2 or if its value carries
    OPTM_G_DEPENDENT (bit 29) in any other spelling; the call arguments and
    the decoded bits must agree. Returns (errors, {flat index: (mother group
    name, item mask)})."""
    errors, found = [], {}
    gname = {gid: name for name, gid in G.items()}
    rx1 = re.compile(r"OPTM_DEP\s*\(\s*OPTM_G_(\w+)\s*,\s*(\d+)\s*\)")
    rx2 = re.compile(r"OPTM_DEP2\s*\(\s*OPTM_G_(\w+)\s*,\s*(\d+)\s*,"
                     r"\s*(\d+)\s*\)")
    for i, (e, v) in enumerate(zip(entries, vals)):
        calls = ([(m, 2 ** int(a)) for m, a in rx1.findall(e)]
                 + [(m, 2 ** int(a) + 2 ** int(b)) for m, a, b in rx2.findall(e)])
        if len(calls) != len(re.findall(r"OPTM_DEP2?\s*\(", e)):
            errors.append("OPTM_GROUPS[%d] (%r): unparsable OPTM_DEP call %r"
                          % (i, V6_MENU[i][0], e))
            continue
        if len(calls) > 1:
            errors.append("OPTM_GROUPS[%d] (%r): more than one OPTM_DEP call"
                          % (i, V6_MENU[i][0]))
            continue
        bits = None
        if v >= 0 and v & F_DEPENDENT:
            bits = (gname.get((v >> 17) & 0xFF, "gid %d" % ((v >> 17) & 0xFF)),
                    (v >> 25) & 0xF)
        if calls and calls[0] != bits:
            errors.append("OPTM_GROUPS[%d] (%r): %r evaluates to dependency "
                          "bits %r" % (i, V6_MENU[i][0], calls[0], bits))
        if bits:
            found[i] = bits
    for i in sorted(set(found) | set(V6_DEPS)):
        label = V6_MENU[i][0] if i < len(V6_MENU) else "?"
        if i not in V6_DEPS:
            errors.append("config.vhd line %d (%r) depends on %s mask 0b%s, "
                          "but V6_DEPS does not track it"
                          % (i, label, found[i][0], format(found[i][1], "04b")))
        elif i not in found:
            errors.append("V6_DEPS[%d] (%r) = %r, but config.vhd declares no "
                          "dependency there" % (i, label, V6_DEPS[i]))
        elif found[i] != V6_DEPS[i]:
            errors.append("config.vhd line %d (%r) depends on %r, V6_DEPS "
                          "says %r" % (i, label, found[i], V6_DEPS[i]))
    return errors, found


def config_groups(cfg):
    """The OPTM_GROUPS array of config.vhd (cfg without comments): returns
    (source expression per line, evaluated value per line, errors), or
    (None, None, []) if the array is not found."""
    m = re.search(r"constant\s+OPTM_GROUPS\s*:\s*OPTM_GTYPE\s*:=\s*\((.*?)\);",
                  cfg, re.S)
    if not m:
        return None, None, []
    errors = []
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
    env = dict(parse_vhdl_constants(cfg, "OPTM_G_"))
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
    return entries, vals, errors


def config_items(cfg):
    """The OPTM_ITEMS string of config.vhd (cfg without comments) as the
    Shell reads it through the config window: VHDL has no escapes in string
    literals, so every "\\n" is two characters. None if it is not found."""
    m = re.search(r"constant\s+OPTM_ITEMS\s*:\s*string\s*:=(.*?);", cfg, re.S)
    if not m:
        return None
    parts = re.findall(r'"((?:[^"]|"")*)"', m.group(1))
    return "".join(p.replace('""', '"') for p in parts)


# ---------------------------------------------------------------------------
# The menu heap of the Shell (MENU_HEAP_SIZE and HEAP_SIZE in
# CORE/m2m-rom/m2m-rom.asm), computed from the real menu of config.vhd and
# globals.vhd exactly as HELP_MENU in M2M/rom/options.asm allocates it:
#   structure: OPTM_STRUCTSIZE (record) + OPTM_ITEMS + 1 (zero terminator)
#              + 4 x OPTM_SIZE (groups, stdsel, lines, dependencies) + 1
#   slots:     (2 x C_VDNUM + submenu openers + C_CRTROMS_MAN_NUM) x
#              (OPTM_DX + 2), for the "%s" texts and one parking slot per drive
# A MENU_HEAP_SIZE that is too small ends in ERR_FATAL_HEAP1 or
# ERR_FATAL_HEAP2 at the first press of Help; a HEAP_SIZE that is too large
# lets the heap of the file browser run into the stack.
# ---------------------------------------------------------------------------

MENU_HEAP_HEADROOM = 180        # words that MENU_HEAP_SIZE keeps free at peak
# MENU_HEAP_SIZE + HEAP_SIZE in each branch of m2m-rom.asm (see the comments
# at HEAP_SIZE and at the stack there): firmware in ROM (RELEASE) or in RAM
HEAP_TOTAL = {"RELEASE": 30208, "not RELEASE": 7168}


def heap_branches(asm):
    """The HEAP_SIZE definitions of m2m-rom.asm per preprocessor branch:
    {"RELEASE": [(value, line)], "not RELEASE": [...], "unconditional": [...]}"""
    out = {"RELEASE": [], "not RELEASE": [], "unconditional": []}
    stack = []
    for line in asm.split("\n"):
        t = line.strip()
        m = re.match(r"#(ifdef|ifndef)\s+(\w+)", t)
        if m:
            stack.append((m.group(2), m.group(1) == "ifdef"))
            continue
        if re.match(r"#if\b", t):
            stack.append((None, True))
            continue
        if re.match(r"#else\b", t) and stack:
            name, pos = stack.pop()
            stack.append((name, not pos))
            continue
        if re.match(r"#endif\b", t) and stack:
            stack.pop()
            continue
        m = re.match(r"HEAP_SIZE\s+\.EQU\s+(\d+)", line)
        if m:
            rel = [pos for name, pos in stack if name == "RELEASE"]
            key = ("unconditional" if not rel else
                   "RELEASE" if rel[-1] else "not RELEASE")
            out[key].append((int(m.group(1)), line))
    return out


def heap_check():
    """Returns (errors, numbers) of the menu heap check, see above."""
    errors = []
    cfg = re.sub(r"--[^\n]*", "", open(os.path.join(REPO, "CORE/vhdl/config.vhd")).read())
    glb = re.sub(r"--[^\n]*", "", open(os.path.join(REPO, "CORE/vhdl/globals.vhd")).read())
    asm = open(os.path.join(REPO, "CORE/m2m-rom/m2m-rom.asm")).read()
    masm = open(os.path.join(REPO, "M2M/rom/menu.asm")).read()

    def one(rx, text, what):
        found = re.findall(rx, text, re.M)
        if len(found) != 1:
            errors.append("%s: found %d times, expected once" % (what, len(found)))
            return None
        return found[0]

    oc = parse_vhdl_constants(cfg, "OPTM_")
    gc = parse_vhdl_constants(glb, "C_")
    n, dx = oc.get("OPTM_SIZE"), oc.get("OPTM_DX")
    vd, crt = gc.get("C_VDNUM"), gc.get("C_CRTROMS_MAN_NUM")
    rec = one(r"^OPTM_STRUCTSIZE\s+\.EQU\s+(\d+)", masm, "M2M/rom/menu.asm: OPTM_STRUCTSIZE")
    items = config_items(cfg)
    entries, vals, _ = config_groups(cfg)
    mhs = one(r"^MENU_HEAP_SIZE\s+\.EQU\s+(\d+)", asm, "m2m-rom.asm: MENU_HEAP_SIZE")
    if None in (n, dx, vd, crt, rec, items, entries, mhs):
        errors.append("menu heap: cannot read OPTM_SIZE, OPTM_DX, OPTM_ITEMS, "
                      "OPTM_GROUPS, C_VDNUM, C_CRTROMS_MAN_NUM, OPTM_STRUCTSIZE "
                      "or MENU_HEAP_SIZE")
        return errors, {}
    rec, mhs = int(rec), int(mhs)
    if len(vals) != n:
        errors.append("menu heap: OPTM_GROUPS has %d entries, OPTM_SIZE is %d"
                      % (len(vals), n))
    strlen = len(items)
    openers = sum(1 for v in vals if v >= 0 and (v & SUBMENU) and not (v & 0xFF))
    structure = rec + strlen + 1 + 4 * n + 1
    slots = 2 * vd + openers + crt
    width = dx + 2
    budget2 = slots * width
    peak = structure + budget2
    num = dict(items=n, submenus=openers, chars=strlen, record=rec + 2,
               structure=structure, slots=slots, width=width, budget2=budget2,
               peak=peak, menu_heap=mhs, headroom=mhs - peak, heap={})

    # (a) the peak fits with the required headroom
    if peak + MENU_HEAP_HEADROOM > mhs:
        errors.append("menu heap: peak %d (structure %d + slots %d) leaves %d "
                      "words of MENU_HEAP_SIZE %d, at least %d are required"
                      % (peak, structure, budget2, mhs - peak, mhs,
                         MENU_HEAP_HEADROOM))
    # (b) MENU_HEAP_SIZE + HEAP_SIZE in each branch
    br = heap_branches(asm)
    if br["unconditional"]:
        errors.append("m2m-rom.asm: HEAP_SIZE outside of the RELEASE branches")
    for key, total in HEAP_TOTAL.items():
        if len(br[key]) != 1:
            errors.append("m2m-rom.asm: %d HEAP_SIZE definitions in the %s "
                          "branch, expected one" % (len(br[key]), key))
            continue
        hs, line = br[key][0]
        num["heap"][key] = hs
        if mhs + hs != total:
            errors.append("m2m-rom.asm (%s): MENU_HEAP_SIZE %d + HEAP_SIZE %d = "
                          "%d, expected %d" % (key, mhs, hs, mhs + hs, total))
        m = re.search(r";\s*(\d+)\s*-\s*(\d+)\s*=\s*(\d+)", line)
        if not m or tuple(map(int, m.groups())) != (total, mhs, hs):
            errors.append("m2m-rom.asm (%s): the comment of HEAP_SIZE is %r, "
                          "expected \"%d - %d = %d\"" % (key, line.split(";", 1)[-1].strip(),
                                                         total, mhs, hs))
    # (c) the numbers in the comment above MENU_HEAP_SIZE and at the stack
    lines = asm.split("\n")
    at = [i for i, l in enumerate(lines) if re.match(r"MENU_HEAP_SIZE\s+\.EQU", l)][0]
    k = at
    while k > 0 and lines[k - 1].lstrip().startswith(";"):
        k -= 1
    text = " ".join(l.strip().lstrip(";").strip() for l in lines[k:at])
    total = HEAP_TOTAL["RELEASE"]
    sentences = [
        ("the example", r"Example: If your HEAP_SIZE would be (\d+), then you "
         r"write (\d+)-(\d+)=(\d+)", (total, total, mhs, total - mhs)),
        ("the menu and budget 1", r"(\d+) words comfortably fit the current menu: "
         r"(\d+) items, (\d+) submenus and a (\d+)-character OPTM_ITEMS string "
         r"give budget 1 = (\d+) \+ (\d+) \+ 4\s*\*\s*(\d+) = (\d+)",
         (mhs, n, openers, strlen, rec + 2, strlen, n, structure)),
        ("budget 2", r"OSM width = (\d+) x (\d+) = (\d+) words", (slots, width, budget2)),
        ("peak and headroom", r"Peak use is (\d+) \+ (\d+) = (\d+), leaving (\d+) "
         r"words of headroom", (structure, budget2, peak, mhs - peak)),
        ("the length of OPTM_ITEMS", r"below 4096 characters \((\d+) now\)", (strlen,)),
    ]
    for what, rx, exp in sentences:
        found = re.findall(rx, text)
        if len(found) != 1:
            errors.append("comment above MENU_HEAP_SIZE: %s found %d times, "
                          "expected once" % (what, len(found)))
            continue
        got = tuple(int(x) for x in (found[0] if isinstance(found[0], tuple)
                                     else (found[0],)))
        if got != exp:
            errors.append("comment above MENU_HEAP_SIZE, %s: %r, the menu gives %r"
                          % (what, got, exp))
    today = one(r"\((\d+) lines today\)", asm, "m2m-rom.asm: \"(N lines today)\" at the stack")
    if today is not None and int(today) != n:
        errors.append("m2m-rom.asm, comment at the stack: %s lines today, the "
                      "menu has %d" % (today, n))
    return errors, num


def heap_summary(num):
    return ("menu heap: structure %d + slots %d x %d = %d words at peak of "
            "MENU_HEAP_SIZE %d (headroom %d, at least %d), HEAP_SIZE %s"
            % (num["structure"], num["slots"], num["width"], num["peak"],
               num["menu_heap"], num["headroom"], MENU_HEAP_HEADROOM,
               " / ".join("%d (%s)" % (v, k) for k, v in num["heap"].items())))


def verify():
    errors = []
    cfg_deps = {}
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
    entries, vals, gerrors = config_groups(cfg)
    if entries is None:
        errors.append("OPTM_GROUPS array not found")
    else:
        errors += gerrors
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
            dep_errors, cfg_deps = config_deps_errors(entries, vals)
            errors += dep_errors

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
    errors += c_menu_errors()
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
    # C_MENU_VOLUME_OPENER is the flat index of the " Volume: %s" submenu opener
    # (used by the custom SUBMENU_SUMMARY callback to append the Stereo Mix
    # setting while a stereo SID is selected, #247); an opener, not a member
    vol_idx = [i for i, (lbl, _, _) in enumerate(V6_MENU) if lbl == " Volume: %s"]
    if not vol_idx:
        errors.append("no \" Volume: %s\" opener found in the golden model")
    elif mconsts.get("C_MENU_VOLUME_OPENER") != vol_idx[0]:
        errors.append("C_MENU_VOLUME_OPENER = %s, model says %d"
                      % (mconsts.get("C_MENU_VOLUME_OPENER"), vol_idx[0]))
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
    m = re.search(r"subtype\s+R_MENU_RRNET\s+is\s+natural\s+range\s+"
                  r"(\d+)\s+downto\s+(\d+)", mega)
    hi, lo = rrnet_range()
    if not m or (int(m.group(1)), int(m.group(2))) != (hi, lo):
        errors.append("R_MENU_RRNET range mismatch: model says "
                      "%d downto %d" % (hi, lo))
    # --- mega65.vhd: the ports of the Input Devices section (#190, #193).
    # Index 0 is the physical port 1, index 1 port 2; each bit has exactly one
    # driver, the assignment from the non-default item of its own port (from
    # the switch "MEGA+left = right" of its own port for main_mouse_rclick_o),
    # out of the menu vector of the clock domain of the port. Drivers are
    # counted per statement (comments are stripped above, statements end at
    # ";"): every "<port>(k) <=", "<port> <=" or "<port>(a downto b) <="
    # anywhere in a statement, and every "=> <port>" (an actual in a port map)
    stmts = [" ".join(s.split()) for s in mega.split(";")]
    for port, vec, names in (
            ("qnice_paddle_atari_o", "qnice_osm_control_i",
             ("C_MENU_PADDLES_P1_ATARI", "C_MENU_PADDLES_P2_ATARI")),
            ("main_mouse_amiga_o", "main_osm_control_i",
             ("C_MENU_MOUSE_P1_AMIGA", "C_MENU_MOUSE_P2_AMIGA")),
            ("main_mouse_rclick_o", "main_osm_control_i",
             ("C_MENU_MOUSE_P1_RCLICK", "C_MENU_MOUSE_P2_RCLICK"))):
        if not re.search(r"\b%s\s*:\s*out\s+std_logic_vector\s*\(\s*1\s+downto"
                         r"\s+0\s*\)" % port, mega):
            errors.append("mega65.vhd: no port %s : out std_logic_vector(1 "
                          "downto 0)" % port)
        rx_target = re.compile(r"\b%s\s*(\(\s*(\d+)\s*\)|\([^()]*\))?\s*<=" % port)
        rx_actual = re.compile(r"=>\s*%s\b\s*(\(\s*(\d+)\s*\))?" % port)
        drivers = {k: [] for k in range(len(names))}
        for s in stmts:
            for rx in (rx_target, rx_actual):
                for m in rx.finditer(s):
                    bits = ([int(m.group(2))] if m.group(2) is not None
                            else list(drivers))
                    for b in bits:
                        drivers.setdefault(b, []).append(s)
        for k, cname in enumerate(names):
            want = r"%s\s*\(\s*%d\s*\)\s*<=\s*%s\s*\(\s*%s\s*\)" % (port, k, vec, cname)
            got = drivers[k]
            if len(got) != 1 or not re.fullmatch(want, got[0]):
                errors.append("mega65.vhd: %s(%d) must have exactly one driver, "
                              "%s <= %s(%s); found %d: %r"
                              % (port, k, port + "(%d)" % k, vec, cname,
                                 len(got), [g[:80] for g in got]))
        for b in sorted(set(drivers) - set(range(len(names)))):
            errors.append("mega65.vhd: %s(%d) is driven, the port has 2 bits"
                          % (port, b))

    # --- the intended layout of the golden model itself (Model submenu line
    # counts, no double separators in any view and state, turbo toggle walk)
    errors += menu_layout_errors()

    # --- m2m-rom.asm: the menu heap fits the real menu, the heap sizes add
    # up and the numbers in their comments are the real ones
    herrors, hnum = heap_check()
    errors += herrors

    if errors:
        print("VERIFY FAIL (%d errors):" % len(errors))
        for e in errors:
            print("  -", e)
        return 1
    print("VERIFY OK: config.vhd + mega65.vhd match the golden model")
    print("  OPTM_SIZE=%d  OPTM_DY=%d  regions=%d  C_MENU constants=%d"
          % (n, exp_dy, num_regions(menu_masked(V6_MENU)), len(C_MENU)))
    print("  dependent lines=%d (every OPTM_DEP/OPTM_DEP2 in config.vhd is "
          "tracked in V6_DEPS)" % len(cfg_deps))
    print("  layout: Model submenu %s visible lines, no double separators"
          % "/".join("%s=%d" % kv for kv in MODEL_VISIBLE.items()))
    print("  switches MEGA+left = right: %s, Mouse view in 16 states, "
          "walk of scenario 4"
          % " ".join("%s=%d" % (r[0], c_menu_values()[r[0]]) for r in INPUT_RCLICK))
    print("  " + heap_summary(hnum))
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
    layout = menu_layout_errors()       # golden-model layout, no emulator
    if layout:
        print("FAIL: menu layout")
        for e in layout:
            print("  -", e)
        fails += 1
    else:
        print("PASS: menu layout (Model submenu %s visible lines, no double "
              "separators, turbo toggle walk)"
              % "/".join("%s=%d" % kv for kv in MODEL_VISIBLE.items()))
    herrors, hnum = heap_check()        # real menu against m2m-rom.asm
    if herrors:
        print("FAIL: menu heap")
        for e in herrors:
            print("  -", e)
        fails += 1
    else:
        print("PASS: " + heap_summary(hnum))
    wide = wide_menu_errors()           # golden model at 512 items
    if wide:
        print("FAIL: wide menu")
        for e in wide:
            print("  -", e)
        fails += 1
    else:
        print("PASS: wide menu (%d items, dependency mothers at flat "
              "255/256/400/511)" % WIDE_N)
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
# A mutant is (description, file, old, new[, gates]). old and new are one
# string or tuples of strings (several replacements in the same file, each
# old string must occur exactly once). file can also be a tuple of files;
# old and new then hold one such entry per file (a defect that is consistent
# across config.vhd, mega65.vhd and the golden model, which only the checks
# of the intended layout can catch). gates names the gate or the tuple of
# gates that must all catch it, "run" if it is missing: "run" runs the suite
# in this process, "verify" runs verify in a fresh process (so it also sees a
# mutant of this file) and counts only a reported VERIFY FAIL, not a crash.
# ---------------------------------------------------------------------------

# the lines of m2m-rom.asm that the heap mutants below edit
_MHS = "MENU_HEAP_SIZE  .EQU 5696"
_HS_DBG = "HEAP_SIZE       .EQU 1472                       ; 7168 - 5696 = 1472"
_HS_REL = "HEAP_SIZE       .EQU 24512                      ; 30208 - 5696 = 24512"


def _heap_sizes(mhs):
    """the three lines of m2m-rom.asm for MENU_HEAP_SIZE mhs"""
    return ("MENU_HEAP_SIZE  .EQU %d" % mhs,
            "HEAP_SIZE       .EQU %-4d                       ; 7168 - %d = %d"
            % (7168 - mhs, mhs, 7168 - mhs),
            "HEAP_SIZE       .EQU %-5d                      ; 30208 - %d = %d"
            % (30208 - mhs, mhs, 30208 - mhs))

# The switches "MEGA+left = right" of the Mouse submenu (#190): the lines of
# config.vhd, mega65.vhd and the golden model that the mutants below edit.
# The strings of the golden model are split so that they occur only once in
# this file (in V6_MENU and V6_DEPS)
_CFG_R1 = ("OPTM_G_MOUSE_P1_RCLICK + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_MOUSE_P1, 1), "
           "-- #1: MEGA+left = right (only with Amiga)")
_CFG_R2 = ("OPTM_G_MOUSE_P2_RCLICK + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_MOUSE_P2, 1), "
           "-- #2: MEGA+left = right (only with Amiga)")
_CFG_IND = "\n" + " " * 45
_CFG_ITM_A1 = '   " Port 1: Amiga\\n"           &'
_CFG_ITM_R1 = ('   " #1: MEGA+left = right\\n"   &  -- right click with the MEGA key; '
               'only shown while port 1 is "Amiga"')
_CFG_ITM_A2 = '   " Port 2: Amiga\\n"           &'
_CFG_ITM_R2 = ('   " #2: MEGA+left = right\\n"   &  -- right click with the MEGA key; '
               'only shown while port 2 is "Amiga"')
_CFG_GRP_A1 = "OPTM_G_MOUSE_P1,                         -- Port 1: Amiga"
_CFG_GRP_A2 = "OPTM_G_MOUSE_P2,                         -- Port 2: Amiga"
_MEGA_R1 = "constant C_MENU_MOUSE_P1_RCLICK  : natural := 302;"
_MEGA_R2 = "constant C_MENU_MOUSE_P2_RCLICK  : natural := 306;"
_MEGA_A1 = "constant C_MENU_MOUSE_P1_AMIGA   : natural := 301;"
_MEGA_A2 = "constant C_MENU_MOUSE_P2_AMIGA   : natural := 305;"
_MEGA_PA1 = "constant C_MENU_PADDLES_P1_ATARI : natural := 313;"
_MEGA_PA2 = "constant C_MENU_PADDLES_P2_ATARI : natural := 316;"
_MEGA_D0 = "main_mouse_rclick_o(0) <= main_osm_control_i(C_MENU_MOUSE_P1_RCLICK);"
_MEGA_D1 = "main_mouse_rclick_o(1) <= main_osm_control_i(C_MENU_MOUSE_P2_RCLICK);"
_MDL_A1 = '(" Port 1: Amiga",' + " " * 11 + '"MOUSE_P1", []),'
_MDL_R1 = ('(" #1: MEGA+left' + ' = right",   "MOUSE_P1_RCLICK", ["SINGLE'
           'SEL"]),   # dependent, #190')
_MDL_D1 = '302: ("MOUSE_P1", 0b' + '0010)'
_MDL_D2 = '306: ("MOUSE_P2", 0b' + '0010)'
_MDL_F1 = '"MOUSE_P1_RCLICK", ["SINGLE' + 'SEL"])'
_MDL_F2 = '"MOUSE_P2_RCLICK", ["SINGLE' + 'SEL"])'
_I16 = " " * 16                 # the indentation of an instruction
_CFG, _MEGA, _MDL = ("CORE/vhdl/config.vhd", "CORE/vhdl/mega65.vhd",
                     "M2M/rom/tests/menu_test.py")

RCLICK_MUTANTS = [
    # mega65.vhd: every new and every moved constant one line off or stale
    ("mega65.vhd  C_MENU_MOUSE_P1_RCLICK points to Port 1: Amiga", _MEGA,
     _MEGA_R1, _MEGA_R1.replace("302", "301"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P1_RCLICK points to the separator behind it", _MEGA,
     _MEGA_R1, _MEGA_R1.replace("302", "303"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P2_RCLICK points to Port 2: Amiga", _MEGA,
     _MEGA_R2, _MEGA_R2.replace("306", "305"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P2_RCLICK points to the switch of port 1", _MEGA,
     _MEGA_R2, _MEGA_R2.replace("306", "302"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P1_AMIGA points to the switch behind it", _MEGA,
     _MEGA_A1, _MEGA_A1.replace("301", "302"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P2_AMIGA keeps its old value 304 (Port 2: C64)", _MEGA,
     _MEGA_A2, _MEGA_A2.replace("305", "304"), "verify"),
    ("mega65.vhd  C_MENU_MOUSE_P2_AMIGA points to the switch behind it", _MEGA,
     _MEGA_A2, _MEGA_A2.replace("305", "306"), "verify"),
    ("mega65.vhd  C_MENU_PADDLES_P1_ATARI keeps its old value 311 (a separator)", _MEGA,
     _MEGA_PA1, _MEGA_PA1.replace("313", "311"), "verify"),
    ("mega65.vhd  C_MENU_PADDLES_P1_ATARI points to Port 1: C64", _MEGA,
     _MEGA_PA1, _MEGA_PA1.replace("313", "312"), "verify"),
    ("mega65.vhd  C_MENU_PADDLES_P2_ATARI keeps its old value 314 (a separator)", _MEGA,
     _MEGA_PA2, _MEGA_PA2.replace("316", "314"), "verify"),
    ("mega65.vhd  C_MENU_PADDLES_P2_ATARI points to Port 2: C64", _MEGA,
     _MEGA_PA2, _MEGA_PA2.replace("316", "315"), "verify"),
    # mega65.vhd: the decoding and the drivers of main_mouse_rclick_o
    ("mega65.vhd  main_mouse_rclick_o(0) decodes the switch of port 2", _MEGA,
     _MEGA_D0, _MEGA_D0.replace("P1_RCLICK", "P2_RCLICK"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(1) decodes the switch of port 1", _MEGA,
     _MEGA_D1, _MEGA_D1.replace("P2_RCLICK", "P1_RCLICK"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(0) decodes Port 1: Amiga", _MEGA,
     _MEGA_D0, _MEGA_D0.replace("P1_RCLICK", "P1_AMIGA"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(1) decodes Port 2: Amiga", _MEGA,
     _MEGA_D1, _MEGA_D1.replace("P2_RCLICK", "P2_AMIGA"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(0) from the menu vector of the QNICE clock", _MEGA,
     _MEGA_D0, _MEGA_D0.replace("main_osm", "qnice_osm"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(1) from the menu vector of the QNICE clock", _MEGA,
     _MEGA_D1, _MEGA_D1.replace("main_osm", "qnice_osm"), "verify"),
    ("mega65.vhd  main_mouse_rclick_o(1) not driven", _MEGA,
     "\n   " + _MEGA_D1, "", "verify"),
    ("mega65.vhd  a second driver of main_mouse_rclick_o(1) behind another statement",
     _MEGA, _MEGA_D0, _MEGA_D0 + " main_mouse_rclick_o(1) <= '0';", "verify"),
    ("mega65.vhd  main_mouse_rclick_o also driven as a whole vector", _MEGA,
     _MEGA_D1, _MEGA_D1 + "\n   main_mouse_rclick_o <= \"00\";", "verify"),
    ("mega65.vhd  main_mouse_rclick_o(0) also driven as the actual of a port map",
     _MEGA,
     "         c64_cia_ver_i          => main_osm_control_i(C_MENU_8521),",
     "         mouse_rclick_o         => main_mouse_rclick_o(0),\n"
     "         c64_cia_ver_i          => main_osm_control_i(C_MENU_8521),", "verify"),
    ("mega65.vhd  the port main_mouse_rclick_o has one bit", _MEGA,
     "main_mouse_rclick_o     : out std_logic_vector(1 downto 0);",
     "main_mouse_rclick_o     : out std_logic_vector(0 downto 0);", "verify"),
    # config.vhd alone: verify compares it with the golden model
    ("config.vhd  #1 without its dependency", _CFG,
     _CFG_R1, _CFG_R1.replace(" + OPTM_DEP(OPTM_G_MOUSE_P1, 1)", ""), "verify"),
    ("config.vhd  #1 depends on Port 1: C64 (item 0)", _CFG,
     _CFG_R1, _CFG_R1.replace("P1, 1)", "P1, 0)"), "verify"),
    ("config.vhd  #1 depends on the mouse of port 2", _CFG,
     _CFG_R1, _CFG_R1.replace("DEP(OPTM_G_MOUSE_P1", "DEP(OPTM_G_MOUSE_P2"), "verify"),
    ("config.vhd  #2 depends on both items of its port", _CFG,
     _CFG_R2, _CFG_R2.replace("OPTM_DEP(OPTM_G_MOUSE_P2, 1)",
                              "OPTM_DEP2(OPTM_G_MOUSE_P2, 0, 1)"), "verify"),
    ("config.vhd  #2 on by default", _CFG,
     _CFG_R2, _CFG_R2.replace("SINGLESEL +", "SINGLESEL + OPTM_G_STDSEL +"), "verify"),
    ("config.vhd  #2 without OPTM_G_SINGLESEL", _CFG,
     _CFG_R2, _CFG_R2.replace(" + OPTM_G_SINGLESEL", ""), "verify"),
    ("config.vhd  #2 in the group of #1", _CFG,
     _CFG_R2, _CFG_R2.replace("OPTM_G_MOUSE_P2_RCLICK", "OPTM_G_MOUSE_P1_RCLICK"), "verify"),
    ("config.vhd  both switches with the group id 47", _CFG,
     "constant OPTM_G_MOUSE_P2_RCLICK : integer := 48;",
     "constant OPTM_G_MOUSE_P2_RCLICK : integer := 47;", "verify"),
    ("config.vhd  #2 in front of Port 2: Amiga", _CFG,
     (_CFG_ITM_A2 + "\n" + _CFG_ITM_R2, _CFG_GRP_A2 + _CFG_IND + _CFG_R2),
     (_CFG_ITM_R2 + "\n" + _CFG_ITM_A2, _CFG_R2 + _CFG_IND + _CFG_GRP_A2), "verify"),
    ("config.vhd  the text of #2 says #1", _CFG,
     _CFG_ITM_R2, _CFG_ITM_R2.replace("#2: MEGA", "#1: MEGA"), "verify"),
    ("config.vhd  OPTM_SIZE stays 323", _CFG,
     "constant OPTM_SIZE         : natural := 325;",
     "constant OPTM_SIZE         : natural := 323;", "verify"),
    # the same defects consistently in config.vhd, mega65.vhd and the golden
    # model: only the checks of the intended layout (INPUT_DEVICES,
    # INPUT_RCLICK, the Mouse views and the walk of scenario 4) can catch them
    ("consistent  #1 depends on Port 1: C64 (item 0)", (_CFG, _MDL),
     (_CFG_R1, _MDL_D1), (_CFG_R1.replace("P1, 1)", "P1, 0)"),
                          _MDL_D1.replace("0b0010", "0b0001")), "verify"),
    ("consistent  #2 depends on the mouse of port 1", (_CFG, _MDL),
     (_CFG_R2, _MDL_D2),
     (_CFG_R2.replace("DEP(OPTM_G_MOUSE_P2", "DEP(OPTM_G_MOUSE_P1"),
      _MDL_D2.replace("MOUSE_P2", "MOUSE_P1")), "verify"),
    ("consistent  #1 without its dependency", (_CFG, _MDL),
     (_CFG_R1, _MDL_D1 + ", "),
     (_CFG_R1.replace(" + OPTM_DEP(OPTM_G_MOUSE_P1, 1)", ""), ""), "verify"),
    ("consistent  #2 on by default", (_CFG, _MDL),
     (_CFG_R2, _MDL_F2),
     (_CFG_R2.replace("SINGLESEL +", "SINGLESEL + OPTM_G_STDSEL +"),
      _MDL_F2.replace('"])', '", "STDSEL"])')), "verify"),
    ("consistent  #1 without OPTM_G_SINGLESEL", (_CFG, _MDL),
     (_CFG_R1, _MDL_F1),
     (_CFG_R1.replace(" + OPTM_G_SINGLESEL", ""),
      _MDL_F1.replace('["SINGLESEL"])', '[])')), "verify"),
    ("consistent  #1 in the group of #2", (_CFG, _MDL),
     (_CFG_R1, _MDL_F1),
     (_CFG_R1.replace("OPTM_G_MOUSE_P1_RCLICK", "OPTM_G_MOUSE_P2_RCLICK"),
      _MDL_F1.replace("P1_RCLICK", "P2_RCLICK")), "verify"),
    ("consistent  #1 in front of Port 1: Amiga", (_CFG, _MEGA, _MDL),
     ((_CFG_ITM_A1 + "\n" + _CFG_ITM_R1, _CFG_GRP_A1 + _CFG_IND + _CFG_R1),
      (_MEGA_A1, _MEGA_R1),
      (_MDL_A1 + "\n    " + _MDL_R1, _MDL_D1)),
     ((_CFG_ITM_R1 + "\n" + _CFG_ITM_A1, _CFG_R1 + _CFG_IND + _CFG_GRP_A1),
      (_MEGA_A1.replace("301", "302"), _MEGA_R1.replace("302", "301")),
      (_MDL_R1 + "\n    " + _MDL_A1, _MDL_D1.replace("302", "301"))), "verify"),
    # the decoders of config.vhd: only the ghdl testbench reads them
    ("config.vhd  SEL_OPTM_STDSEL reads the line flag (bit 9)", _CFG,
     "when SEL_OPTM_STDSEL       => data_o <= x\"000\" & \"000\" & "
     "std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(8));",
     "when SEL_OPTM_STDSEL       => data_o <= x\"000\" & \"000\" & "
     "std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(9));", "ghdl"),
    ("config.vhd  SEL_OPTM_SINGLESEL reads bit 14", _CFG,
     "when SEL_OPTM_SINGLESEL    => data_o <= x\"000\" & \"000\" & "
     "std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15));",
     "when SEL_OPTM_SINGLESEL    => data_o <= x\"000\" & \"000\" & "
     "std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(14));", "ghdl"),
    ("config.vhd  SEL_OPTM_GROUPS reads the headline flag from bit 13", _CFG,
     "OPTM_GTC)(12)) & \"0000\" &", "OPTM_GTC)(13)) & \"0000\" &", "ghdl"),
    # the screen of the menu: only the screen trace of scenario 4 sees it
    ("menu.asm  OPTM_SHOW draws a marker in front of every line",
     "M2M/rom/menu.asm",
     "_OPTM_SHOW_1A   CMP     0, @R2                  ; show select. at this point?",
     "_OPTM_SHOW_1A   CMP     2, @R2                  ; show select. at this point?"),
    ("menu.asm  the marker of a single-select item switched off is deleted one row too high",
     "M2M/rom/menu.asm",
     "                ADD     R8, R10\n                ADD     1, R10\n"
     "                MOVE    R11, @--SP              ; save R11\n"
     "                MOVE    OPTM_MENULEVEL, R11     ; R11: (sub)menu level, 0=main",
     "                ADD     R8, R10\n"
     "                MOVE    R11, @--SP              ; save R11\n"
     "                MOVE    OPTM_MENULEVEL, R11     ; R11: (sub)menu level, 0=main"),
    ("menu.asm  the markers of a radio group are deleted one row too high",
     "M2M/rom/menu.asm",
     "                ADD     1, R8                   ; add 1 because of top frame\n",
     ""),
    ("menu.asm  the marker of a selected item is drawn one row too high",
     "M2M/rom/menu.asm",
     "_OPTM_RUN_9     MOVE    OPTM_Y, R10\n                MOVE    @R10, R10\n"
     "                ADD     1, R10\n",
     "_OPTM_RUN_9     MOVE    OPTM_Y, R10\n                MOVE    @R10, R10\n"),
] + [
    # the type and the column of the markers: only the screen trace of
    # scenario 4 sees them (the testbed draws r for a radio item and s for a
    # single-select item, like the two different characters of the firmware)
    ("menu.asm  " + desc, "M2M/rom/menu.asm", old, new)
    for desc, old, new in (
        ("OPTM_SHOW draws the radio marker for single-select lines",
         _I16 + "ADD     2, R8                   ; single-select\n", ""),
        ("switching a single-select item on draws the radio marker",
         _I16 + "MOVE    OPTM_SSMS, R7           ; single select flag\n"
         + _I16 + "ADD     @R7, R8\n",
         _I16 + "MOVE    OPTM_SSMS, R7           ; single select flag\n"),
        ("selecting a radio item draws the single-select marker",
         "_OPTM_RUN_16    MOVE    OPTM_SSMS, R12          ; Flag on stack: multi-select\n"
         + _I16 + "MOVE    0, @R12",
         "_OPTM_RUN_16    MOVE    OPTM_SSMS, R12          ; Flag on stack: multi-select\n"
         + _I16 + "MOVE    2, @R12"),
        ("OPTM_SHOW swaps the radio and the single-select marker",
         _I16 + "RBRA    _OPTM_SHOW_1B, Z        ; multi-select",
         _I16 + "RBRA    _OPTM_SHOW_1B, !Z       ; multi-select"),
        ("the marker of a single-select item switched on one column to the right",
         _I16 + "MOVE    2, @R12\n" + _I16 + "MOVE    OPTM_X, R9              ; R9: x-coord\n"
         + _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     1, R9                \n",
         _I16 + "MOVE    2, @R12\n" + _I16 + "MOVE    OPTM_X, R9              ; R9: x-coord\n"
         + _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     2, R9                \n"),
        ("the marker of a single-select item switched off deleted one column to the right",
         _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     1, R9\n"
         + _I16 + "MOVE    OPTM_Y, R10             ; R10: y-coord",
         _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     2, R9\n"
         + _I16 + "MOVE    OPTM_Y, R10             ; R10: y-coord"),
        ("the markers of a radio group deleted one column to the right",
         _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     1, R9\n"
         + _I16 + "XOR     R10, R10                ; R10: flat list item pos",
         _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     2, R9\n"
         + _I16 + "XOR     R10, R10                ; R10: flat list item pos"),
        ("OPTM_SHOW draws the markers one column to the right",
         "_OPTM_SHOW_1B   MOVE    OPTM_X, R9              ; R9: current x-pos\n"
         + _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     1, R9",
         "_OPTM_SHOW_1B   MOVE    OPTM_X, R9              ; R9: current x-pos\n"
         + _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     2, R9"),
        ("OPTM_SHOW prints the strings of the %s lines one column to the left",
         "ADD     1, R9                   ; add 1 to x because of frame\n", ""),
    )
]

# the redraw: clear, frame, separators, the line below a submenu, the cursor
# bar and the headline highlight; only the screen trace of scenario 4 sees
# them, the other scenarios do not trace these screen functions
_SH_CLEAR = (_I16 + "MOVE    OPTM_FP_CLEAR, R7       ; clear VRAM\n"
             + _I16 + "RSUB    _OPTM_CALL, 1\n")
_SH_FRAME = (_I16 + "MOVE    OPTM_FP_FRAME, R7       ; draw frame\n"
             + _I16 + "RSUB    _OPTM_CALL, 1\n")
_SH_SEP = (_I16 + "MOVE    R6, R8                  ; yes: R8: y-pos of line\n"
           + _I16 + "SUB     R12, R8                 ; adjust for skipped items\n")
_SH_END = (_I16 + "MOVE    R6, R8                  ; R8: y-pos of line\n"
           + _I16 + "SUB     R12, R8                 ; adjust for skipped items\n")
_RUN_BAR = (_I16 + "RBRA    _OPTM_R_FATAL, C        ; failed? fatal!\n"
            + _I16 + "MOVE    OPTM_SEL_SEL, R9\n")
_RUN_STD = (_I16 + "MOVE    OPTM_SEL_STD, R9\n" + _I16 + "RSUB    _OPTM_CALL, 1\n"
            + _I16 + "MOVE    R2, R3                  ; remember current item as old")
RCLICK_MUTANTS += [
    ("menu.asm  " + desc, "M2M/rom/menu.asm", old, new)
    for desc, old, new in (
        ("N1  OPTM_SHOW does not clear the screen", _SH_CLEAR, ""),
        ("N2  separators drawn without the skip counter", _SH_SEP,
         _SH_SEP.replace(_I16 + "SUB     R12, R8                 ; adjust for skipped items\n", "")),
        ("N3  the cursor bar drawn one row too low", _RUN_BAR,
         _RUN_BAR.replace("MOVE    OPTM_SEL_SEL", "ADD     1, R8\n" + _I16 + "MOVE    OPTM_SEL_SEL")),
        ("N4  the cursor bar of the old line not removed", _RUN_STD,
         _RUN_STD.replace(_I16 + "RSUB    _OPTM_CALL, 1\n", "")),
        ("N7  headlines highlighted without the skip counter",
         _I16 + "SUB     R4, R8                  ; deduct skip counter\n", ""),
        ("N9  the line below a submenu drawn without the skip counter", _SH_END,
         _SH_END.replace(_I16 + "SUB     R12, R8                 ; adjust for skipped items\n", "")),
        ("N5  OPTM_SHOW clears the screen after it drew the frame",
         (_SH_CLEAR, _SH_FRAME), ("", _SH_FRAME + _SH_CLEAR)),
        ("N6  OPTM_SHOW draws no frame", _SH_FRAME, ""),
        ("N8  separators drawn one row too low", _SH_SEP,
         _SH_SEP + _I16 + "ADD     1, R8\n"),
        ("N10 the line below a submenu drawn one row too low", _SH_END,
         _SH_END + _I16 + "ADD     1, R8\n"),
        ("N11 the line below a submenu never drawn",
         _I16 + "RBRA    _OPTM_SHOW_RET, N       ; no",
         _I16 + "RBRA    _OPTM_SHOW_RET, 1       ; no"),
        ("N12 the cursor bar removed from the new line instead of the old one",
         "_OPTM_RUN_2     MOVE    OPTM_FP_SELECT, R7      ; unselect old item\n"
         + _I16 + "MOVE    R3, R8",
         "_OPTM_RUN_2     MOVE    OPTM_FP_SELECT, R7      ; unselect old item\n"
         + _I16 + "MOVE    R2, R8"),
        ("N13 the cursor bar of the old line replaced by a headline highlight",
         _RUN_STD, _RUN_STD.replace("OPTM_SEL_STD", "OPTM_SEL_TLL")),
        ("N14 the cursor bar drawn as a headline highlight", _RUN_BAR,
         _RUN_BAR.replace("OPTM_SEL_SEL", "OPTM_SEL_TLL")),
        ("N15 headlines highlighted as the cursor bar",
         _I16 + "MOVE    OPTM_SEL_TLL, R9\n", _I16 + "MOVE    OPTM_SEL_SEL, R9\n"),
        ("N16 no headline highlighted",
         _I16 + "RBRA    _OPTM_TT_1B, Z          ; flag not set: continue",
         _I16 + "RBRA    _OPTM_TT_1B, 1          ; flag not set: continue"),
        ("N17 every line highlighted as a headline",
         _I16 + "AND     OPTM_HEADLINE, R3\n", _I16 + "OR      OPTM_HEADLINE, R3\n"),
    )
]

# the column of the menu: scenario 4 places the menu away from the left edge
# (NAV4_X), so a path that ignores OPTM_X prints in the wrong column
_X_COL = _I16 + "MOVE    @R9, R9\n" + _I16 + "ADD     1, R9"
RCLICK_MUTANTS += [
    ("menu.asm  " + desc, "M2M/rom/menu.asm", old, new)
    for desc, old, new in (
        ("X1  OPTM_SHOW draws the markers without the column of the menu",
         "_OPTM_SHOW_1B   MOVE    OPTM_X, R9              ; R9: current x-pos\n" + _X_COL,
         "_OPTM_SHOW_1B   MOVE    1, R9                   ; R9: current x-pos"),
        ("X2  OPTM_SHOW prints the %s strings without the column of the menu",
         _I16 + "MOVE    OPTM_X, R9\n" + _X_COL + "                   ; add 1 to x because of frame",
         _I16 + "MOVE    1, R9                   ; add 1 to x because of frame"),
        ("X3  the marker of a single-select item switched on without the column of the menu",
         _I16 + "MOVE    2, @R12\n" + _I16 + "MOVE    OPTM_X, R9              ; R9: x-coord\n"
         + _X_COL + "                \n",
         _I16 + "MOVE    2, @R12\n" + _I16 + "MOVE    1, R9\n"),
        ("X4  the marker of a single-select item switched off deleted without the column of the menu",
         _I16 + "MOVE    OPTM_X, R9              ; R9: x-coord\n" + _X_COL + "\n"
         + _I16 + "MOVE    OPTM_Y, R10             ; R10: y-coord",
         _I16 + "MOVE    1, R9\n" + _I16 + "MOVE    OPTM_Y, R10             ; R10: y-coord"),
        ("X5  the markers of a radio group deleted without the column of the menu",
         _I16 + "MOVE    OPTM_X, R9              ; R9: x-coord\n" + _X_COL + "\n"
         + _I16 + "XOR     R10, R10                ; R10: flat list item pos",
         _I16 + "MOVE    1, R9\n" + _I16 + "XOR     R10, R10                ; R10: flat list item pos"),
    )
]

MUTANTS = [
    ("optm_deps.asm  OPTM_DEP_OK never hides a line",
     "M2M/rom/optm_deps.asm",
     "_ODO_HID        AND     0xFFFB, SR",
     "_ODO_HID        OR      0x0004, SR"),
    ("optm_deps.asm  RESOLVE truncates the item mask to 2 bits",
     "M2M/rom/optm_deps.asm",
     "AND     0x0F00, R5              ; bits 11-8 of the raw word to",
     "AND     0x0300, R5              ; bits 11-8 of the raw word to"),
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
    ("menu.asm  Cursor left starts the search on the current line (#258)",
     "M2M/rom/menu.asm",
     "MOVE    R0, R2                  ; R2: last line of the list\n                SUB     1, R2\n",
     "MOVE    R2, R2\n                MOVE    R2, R2\n"),
    ("menu.asm  Cursor right starts the search on the current line (#258)",
     "M2M/rom/menu.asm",
     "XOR     R2, R2                  ; R2: line 0",
     "MOVE    R2, R2                  ; R2: line 0"),
    ("menu.asm  Cursor left and right swapped (#258)",
     "M2M/rom/menu.asm",
     "_OPTM_RUN_FL1   CMP     OPTM_KEY_FIRST, R8      ; key: first item?",
     "_OPTM_RUN_FL1   CMP     OPTM_KEY_LAST, R8       ; key: first item?"),
    ("menu.asm  Cursor right ignored (#258)",
     "M2M/rom/menu.asm",
     "RBRA    _OPTM_RUN_5A, !Z        ; no: check other key\n                XOR     R2, R2",
     "RBRA    _OPTM_RUN_5A, 1         ; no: check other key\n                XOR     R2, R2"),
    ("optm_deps.asm  MINHID tests only state 0 of a single-select mother",
     "M2M/rom/optm_deps.asm",
     "MOVE    2, R7                   ; single-select: states 0 and 1",
     "MOVE    1, R7                   ; single-select: states 0 and 1"),
    # Input Devices (#190, #193): edits of config.vhd and mega65.vhd, which
    # only "verify" reads (fifth element: the gate that must catch them)
    ("mega65.vhd  C_MENU_MOUSE_P1_AMIGA points to Port 1: C64",
     "CORE/vhdl/mega65.vhd",
     "constant C_MENU_MOUSE_P1_AMIGA   : natural := 301;",
     "constant C_MENU_MOUSE_P1_AMIGA   : natural := 300;", "verify"),
    ("mega65.vhd  C_MENU_PADDLES_P2_ATARI points to the item of port 1",
     "CORE/vhdl/mega65.vhd",
     "constant C_MENU_PADDLES_P2_ATARI : natural := 316;",
     "constant C_MENU_PADDLES_P2_ATARI : natural := 313;", "verify"),
    ("mega65.vhd  main_mouse_amiga_o(1) decodes the mouse of port 1",
     "CORE/vhdl/mega65.vhd",
     "main_mouse_amiga_o(1) <= main_osm_control_i(C_MENU_MOUSE_P2_AMIGA);",
     "main_mouse_amiga_o(1) <= main_osm_control_i(C_MENU_MOUSE_P1_AMIGA);", "verify"),
    ("config.vhd  Port 1: Atari CX30 in the radio group of port 2",
     "CORE/vhdl/config.vhd",
     "OPTM_G_PADDLES_P1,                       -- Port 1: Atari CX30",
     "OPTM_G_PADDLES_P2,                       -- Port 1: Atari CX30", "verify"),
    ("config.vhd  Amiga instead of C64 is the default of the mouse at port 2",
     "CORE/vhdl/config.vhd",
     "OPTM_G_MOUSE_P2      + OPTM_G_STDSEL,    -- Port 2: C64\n"
     "                                             OPTM_G_MOUSE_P2,                         -- Port 2: Amiga",
     "OPTM_G_MOUSE_P2,                         -- Port 2: C64\n"
     "                                             OPTM_G_MOUSE_P2      + OPTM_G_STDSEL,    -- Port 2: Amiga", "verify"),
    # second drivers of a port bit that a count of the assignments at the
    # start of a line does not see
    ("mega65.vhd  a second driver of main_mouse_amiga_o(0) behind another statement",
     "CORE/vhdl/mega65.vhd",
     "main_mouse_amiga_o(1) <= main_osm_control_i(C_MENU_MOUSE_P2_AMIGA);",
     "main_mouse_amiga_o(1) <= main_osm_control_i(C_MENU_MOUSE_P2_AMIGA); "
     "main_mouse_amiga_o(0) <= '0';", "verify"),
    ("mega65.vhd  main_mouse_amiga_o(1) also driven as the actual of a port map",
     "CORE/vhdl/mega65.vhd",
     "         c64_cia_ver_i          => main_osm_control_i(C_MENU_8521),",
     "         mouse_type_o           => main_mouse_amiga_o(1),\n"
     "         c64_cia_ver_i          => main_osm_control_i(C_MENU_8521),", "verify"),
    # an unresolvable C_MENU entry of the golden model itself must be a
    # reported error of verify, not a crash (the strings are split so that
    # they occur only once in this file: in V6_MENU)
    ("menu_test.py  Port 1: Amiga in the radio group of port 2 (golden model)",
     "M2M/rom/tests/menu_test.py",
     '(" Port 1: Amiga",' + " " * 11 + '"MOUSE_P1", [])',
     '(" Port 1: Amiga",' + " " * 11 + '"MOUSE_P2", [])', "verify"),
] + [
    # the menu heap of m2m-rom.asm, see heap_check(): every mutant must be
    # caught by verify and by run
    (desc, "CORE/m2m-rom/m2m-rom.asm", old, new, ("verify", "run"))
    for desc, old, new in (
        ("H1  the sizes of the menu of 323 lines (5632 / 24576 / 1536)",
         (_MHS, _HS_DBG, _HS_REL), _heap_sizes(5632)),
        ("H2  HEAP_SIZE 24576 with MENU_HEAP_SIZE 5696 (into the stack area)",
         _HS_REL,
         "HEAP_SIZE       .EQU 24576                      ; 30208 - 5696 = 24512"),
        ("H3  MENU_HEAP_SIZE 5632, consistent everywhere (158 words headroom)",
         (_MHS, _HS_DBG, _HS_REL,
          "write 30208-5696=24512", "; 5696 words comfortably fit",
          "leaving 222 words of"),
         _heap_sizes(5632) + (
          "write 30208-5632=24576", "; 5632 words comfortably fit",
          "leaving 158 words of")),
        ("H4  MENU_HEAP_SIZE 5653, consistent everywhere (179 words headroom)",
         (_MHS, _HS_DBG, _HS_REL,
          "write 30208-5696=24512", "; 5696 words comfortably fit",
          "leaving 222 words of"),
         _heap_sizes(5653) + (
          "write 30208-5653=24555", "; 5653 words comfortably fit",
          "leaving 179 words of")),
        ("H5  HEAP_SIZE of the branch without RELEASE left at 1536",
         _HS_DBG,
         "HEAP_SIZE       .EQU 1536                       ; 7168 - 5696 = 1472"),
        ("H6  stale line count in the comment at the stack",
         "; line (325 lines today),", "; line (323 lines today),"),
        ("H7  stale submenu count in the comment above MENU_HEAP_SIZE",
         "325 items, 20 submenus and a", "325 items, 18 submenus and a"),
        ("H8  stale item count in the comment above MENU_HEAP_SIZE",
         "fit the current menu: 325 items", "fit the current menu: 323 items"),
        ("H9  stale length of OPTM_ITEMS in the comment above MENU_HEAP_SIZE",
         "(3450 now)", "(3402 now)"),
        ("H10 stale peak in the comment above MENU_HEAP_SIZE",
         "Peak use is 4772 + 702 = 5474, leaving 222",
         "Peak use is 4716 + 702 = 5418, leaving 278"),
    )
] + RCLICK_MUTANTS


def _quiet_run():
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        return run()


def _run_gate():
    """run in this process; returns (caught, first failure line)"""
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        fails = run()
    out = buf.getvalue().split("\n")
    detail = [l for l in out if l.startswith("  - ")]
    first = [l for l in out if l.startswith(("FAIL", "ASSEMBLE FAIL", "RUN TIMEOUT"))]
    return fails != 0, (detail or first or [""])[0]


def _verify_gate():
    """verify in a fresh process, so that it reads the mutated file (also a
    mutated menu_test.py); only a reported VERIFY FAIL counts as caught, a
    crash of the script does not. Returns (caught, first error line)"""
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "verify"],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True,
                       timeout=600)
    errs = [l for l in r.stdout.split("\n") if l.startswith("  - ")]
    if r.returncode != 0 and "VERIFY FAIL" in r.stdout:
        return True, errs[0] if errs else ""
    if r.returncode != 0:
        tail = (r.stdout + r.stderr).strip().split("\n")[-1]
        return False, "verify did not report the error, it ended with: " + tail
    return False, ""


def _ghdl_gate():
    """the ghdl testbench of the config.vhd decoders in a fresh process;
    only a reported decoder failure counts. Returns (caught, first line)"""
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "ghdl"],
                       stdin=subprocess.DEVNULL, capture_output=True, text=True,
                       timeout=600)
    if r.returncode != 0 and "VHDL DECODER TB: FAIL" in r.stdout:
        miss = [l for l in r.stdout.split("\n") if "MISMATCH" in l]
        return True, (miss[0].strip() if miss else "VHDL DECODER TB: FAIL")
    return False, (r.stdout + r.stderr).strip().split("\n")[-1]


GATES = {"run": _run_gate, "verify": _verify_gate, "ghdl": _ghdl_gate}


def mutate():
    print("baseline (unmutated) suite must pass first:")
    if _quiet_run() != 0 or subprocess.run(
            [sys.executable, os.path.abspath(__file__), "verify"],
            stdin=subprocess.DEVNULL, capture_output=True).returncode != 0:
        print("  BASELINE FAILS - fix the suite before mutation testing")
        return 1
    print("  baseline OK\n")
    fails = 0
    for mutant in MUTANTS:
        desc, rel, old, new = mutant[:4]
        # the gates that must catch the mutant: one name or a tuple of names
        gates = mutant[4] if len(mutant) > 4 else "run"
        gates = (gates,) if isinstance(gates, str) else gates
        # a mutant edits one file or, with a tuple of files, several files
        # (old and new then hold one entry per file); the entry of a file is
        # one replacement or a tuple of replacements in that file
        edits = (list(zip(rel, old, new)) if isinstance(rel, tuple)
                 else [(rel, old, new)])
        srcs, mutated, bad = {}, {}, []
        for r, o, n in edits:
            path = os.path.join(REPO, r)
            if path not in srcs:
                srcs[path] = mutated[path] = open(path).read()
            pairs = list(zip(o, n)) if isinstance(o, tuple) else [(o, n)]
            for oo, nn in pairs:
                if mutated[path].count(oo) != 1:
                    bad.append(mutated[path].count(oo))
                mutated[path] = mutated[path].replace(oo, nn)
        if bad:
            print("SETUP ERROR (%s matches): %s" % (bad, desc))
            fails += 1
            continue
        notes = []
        try:
            for path, text in mutated.items():
                with open(path, "w") as f:
                    f.write(text)
            killed = True
            for g in gates:
                caught, note = GATES[g]()
                notes.append("%s: %s" % (g, note[:110] if caught else
                                         "NOT CAUGHT " + note[:90]))
                killed = killed and caught
        finally:
            for path, text in srcs.items():   # always restore the originals
                with open(path, "w") as f:
                    f.write(text)
        if killed:
            print("KILLED   %s" % desc)
        else:
            print("SURVIVED %s   <-- TEST GAP" % desc)
            fails += 1
        if len(mutant) > 4:
            for nt in notes:
                print("           %s" % nt)
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
