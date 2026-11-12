#!/usr/bin/env python3
"""
Regression test for the string ROM of the QNICE firmware (M2M/rom/strrom.asm,
device M2M$STRROM = C_DEV_STRROM in M2M/vhdl/qnice_wrapper.vhd, built by
M2M/tools/asm_strrom.sh).

The QNICE emulator has no M2M devices, so this test runs on simulated
hardware: it builds strrom_sim_test.asm as a self-contained RELEASE-style ROM
(QNICE Monitor at 0x0000, exactly like m2m-rom.asm) with the tool that also
builds the real firmware and simulates the real QNICE CPU inside the real
qnice_wrapper.vhd with ghdl (strrom_sim_tb.vhd): real device decoding, real
string ROM instance, preloaded from the file that the tool has written.

The string ROM of the test contains every string ROM string of the Shell
(the marked sections of all sources) and strings for the edge cases: the empty
string, one character, CR/LF, special characters, labels in the middle of a
string, a string that ends at the last address of a 4k window, a string that
is one character too long for the rest of a window, a string that fills a
whole window and characters above 0x7F. The strings whose length depends on
the length of the real strings are generated on every run
(strrom_sim_fixtures.asm).

What is checked:

    * Build: the string ROM image and the table of the handles that
      asm_strrom.sh produces are equal to what this script derives from the
      sources with a parser and a placement of its own.
    * Device: every word of all 4k windows of the string ROM, the windows
      behind its end and that it is read-only.
    * STRROM$OPEN and STRROM$CLOSE for every handle and for values that are
      no handles: R8, the selected device and 4k window, the stack pointer,
      the registers of the caller, the Carry and the Overflow flag (both set
      and both clear when called), nested calls. Every handle is read via
      STRROM$OPEN up to its terminator.
    * IO$PUTS (SYSCALL(puts, 1)), LOG_STR and SCR$PRINTSTR for handles and
      for ordinary strings in the ROM, in the RAM and in the 4k window of a
      device: the characters at the UART and in the video RAM, R8, the
      selected device and window and the stack pointer after the call; for
      IO$PUTS also the Carry and the Overflow flag, which it does not change.
      A few strings are transmitted by the real UART and decoded from its
      pin, all others are taken from the transmit register.

The firmware reports, it does not check: every expected value is computed
here. Each handle runs through one of the three output routines, the strings
for the edge cases through all of them; --full runs every handle through all
three. The simulation is slow (about 20,000 clock cycles per second), so the
work is split into up to five simulations that run in parallel (--jobs, four
by default if the computer has at least eight logical processors):

    python3 strrom_sim_test.py [--jobs N] [--full] [--keep]

Requires ghdl and the QNICE toolchain built for the host platform, see
AGENTS.md section 7. Skips (exit code 0) when ghdl is not installed.
"""

import argparse
import concurrent.futures
import glob
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ROM_SRC = os.path.join(REPO, "M2M", "rom")
TOOL = os.path.join(REPO, "M2M", "tools", "asm_strrom.sh")
QASM = os.path.join(REPO, "M2M", "QNICE", "assembler", "qasm")
WRAPPER_VHDL = os.path.join(REPO, "M2M", "vhdl", "qnice_wrapper.vhd")
GLOBALS_VHDL = os.path.join(REPO, "CORE", "vhdl", "globals.vhd")
CONFIG_VHDL = os.path.join(REPO, "CORE", "vhdl", "config.vhd")

FW = "strrom_sim_test"                  # firmware: FW.asm, .out, .lis, .rom
STR = "strrom_sim_strings"              # string ROM: STR.rom, .lis, .out
FIXTURES = os.path.join(HERE, "strrom_sim_fixtures.asm")
STRINGS_ASM = os.path.join(ROM_SRC, "strings.asm")

# sources that are searched for string ROM sections of the Shell
SHELL_SOURCES = ["M2M/rom/*.asm", "M2M/rom/monitor/*.asm", "CORE/m2m-rom/*.asm"]

WIN = 4096                              # size of the 4k window of QNICE
WIN_BASE = 0x7000                       # M2M$RAMROM_DATA
DEV_STRROM = 0x0007                     # M2M$STRROM
DEV_CONFIG = 0x0002                     # M2M$CONFIG
DEV_CORE = (0x0100, 0xFFFF)             # device and window of the testbench
VRAM_WORDS = 2048                       # 2 ** VRAM_ADDR_WIDTH (checked)
MAX_JOBS = 5                            # three bits per job in 16 bits

# the string constants of config.vhd that the firmware prints: 4k window
# (selector) and name of the constant
CONFIG_STRINGS = {0x0308: "OPTM_S_MOUNT", 0x0100: "DIR_START"}

# markers, sections and routines: mirrored from strrom_sim_test.asm
MK_START, MK_SERIAL, MK_TURBO, MK_CLR = 0xA000, 0x5E00, 0x7B00, 0xC1EA
MK_DUMP, MK_PROBE, MK_WRITE = 0xD000, 0xD100, 0xD200
MK_OPEN, MK_NEST, MK_WALK, MK_CASE = 0x0B00, 0x0B10, 0x0C00, 0xCA00
MK_VRAM, MK_END, MK_FATAL = 0x0D00, 0xE0D0, 0xFA7A
SEC_SERIAL, SEC_VRAM, SEC_DUMP, SEC_OPEN, SEC_WALK = 1, 2, 4, 8, 16
RT_PUTS, RT_LOG, RT_SCR = 1, 2, 4
RT_NAMES = {RT_PUTS: "IO$PUTS", RT_LOG: "LOG_STR", RT_SCR: "SCR$PRINTSTR"}
CASE_SIZE = 7
REG_PATTERN = [0xA0A0, 0xA1A1, 0xA2A2, 0xA3A3, 0xA4A4, 0xA5A5, 0xA6A6,
               0xA7A7, 0xB9B9, 0xBABA, 0xBBBB, 0xBCBC]  # R0..R7, R9..R12
FLAGS = 0x0024                          # Carry and Overflow flag in SR

# Devices and 4k windows that are selected while a routine under test runs,
# in turns. Device 4 is the HyperRAM, which does not answer in the testbench:
# a routine that accesses the 4k window while the device of its caller is
# selected gets stuck there. Not used are the devices whose inputs the
# testbench ties off: 3 (polyphase RAM), 5 (I2C) and 6 (RTC).
PRESETS = [(0x0000, 0x0000), (0x0100, 0xFFFF), (0x0002, 0x0308),
           (0x0007, 0x0001), (0x0001, 0x0000), (0x00FF, 0x0010),
           (0xFFFF, 0xFFFF), (0x0007, 0x0003), (0x0004, 0x0123),
           (0x0100, 0x0000), (0x0002, 0x1000), (0x8000, 0x0001)]

# SCR$PRINTSTR: cursor x, y and left margin, in turns
CURSORS = [(0, 0, 0), (1, 1, 1), (5, 2, 3), (0, 10, 0), (20, 4, 2),
           (44, 0, 1), (2, 30, 2)]

# Measured costs in clock cycles; they balance the jobs and set the timeouts
COST_CALL = {RT_PUTS: 420, RT_LOG: 420, RT_SCR: 760}
COST_CHAR = {RT_PUTS: 95, RT_LOG: 122, RT_SCR: 205}
COST_UART_CHAR = 4752                               # real UART: 11 bit times
SIM_SPEED = 5000                                    # clock cycles per second
                                                    # of a very slow computer
QUIET_LIMIT = 60                                    # seconds without output
                                                    # until a simulation is
                                                    # considered to be stuck

# the QNICE SoC and what qnice_wrapper.vhd needs, in analysis order (without
# sd_spi.vhd and byte_bram.vhd, which only the replaced SD card controller
# needs)
VHDL = [
    "M2M/vhdl/QNICE/qnice_globals.vhd",
    "M2M/QNICE/vhdl/tools.vhd",
    "M2M/QNICE/vhdl/cpu_constants.vhd",
    "M2M/QNICE/vhdl/alu_shifter.vhd",
    "M2M/QNICE/vhdl/alu.vhd",
    "M2M/QNICE/vhdl/register_file.vhd",
    "M2M/QNICE/vhdl/qnice_cpu.vhd",
    "M2M/QNICE/vhdl/block_rom.vhd",         # patched, see GHDL_PATCHES
    "M2M/QNICE/vhdl/block_ram.vhd",
    "M2M/QNICE/vhdl/fifo.vhd",
    "M2M/QNICE/vhdl/basic_uart.vhd",
    "M2M/QNICE/vhdl/bus_uart.vhd",
    "M2M/QNICE/vhdl/EAE.vhd",
    "M2M/QNICE/vhdl/sdcard.vhd",            # idle stub, see SDCARD_STUB
    "M2M/QNICE/vhdl/cycle_counter.vhd",     # patched, see GHDL_PATCHES
    "M2M/vhdl/QNICE/qnice_mmio.vhd",
    "M2M/vhdl/QNICE/sdmux.vhd",
    "M2M/vhdl/QNICE/qnice.vhd",
    "M2M/vhdl/av_pipeline/video_modes_pkg.vhd",
    "M2M/vhdl/controllers/HDMI/types_pkg.vhd",
    "CORE/vhdl/globals.vhd",
    "CORE/vhdl/config.vhd",
    "M2M/vhdl/tdp_ram.vhd",
    "M2M/vhdl/2port2clk_ram.vhd",
    "M2M/vhdl/2port2clk_ram_byteenable.vhd",
    "M2M/vhdl/qnice2hyperram.vhd",
    "M2M/vhdl/controllers/M65/mouse_input.vhdl",
    "M2M/vhdl/qnice_wrapper.vhd",
]

# two QNICE-FPGA files use syntax that ghdl rejects in VHDL-2008 mode (Vivado
# accepts it); the test analyzes patched copies, the sources stay untouched
GHDL_PATCHES = {
    "block_rom.vhd": [(r"file\s+rom_file\s*:\s*text\s+is\s+in\s+rom_file_name;",
                       "file rom_file : text open read_mode is rom_file_name;")],
    "cycle_counter.vhd": [(r"(\n(\s*)when \"11\" => [^\n]*\n)",
                           "\\1\\2when others => null;\n")],
}

# The SD card controller is not involved and its SPI state machine trips a
# simulation-only range check while it idles without a card, so the test
# replaces it by an idle stub that keeps the real entity declaration of
# sdcard.vhd (a changed port list still fails to elaborate).
SDCARD_STUB = """
architecture stub of sdcard is
begin
   data_out <= (others => '0');
   sd_reset <= '1';
   sd_clk   <= '0';
   sd_mosi  <= '1';
end architecture stub;
"""

RX_BEGIN = re.compile(r"^[ \t]*;[ \t]*STRROM_BEGIN[ \t]*$")
RX_END = re.compile(r"^[ \t]*;[ \t]*STRROM_END[ \t]*$")
RX_TABLE = re.compile(r"^[ \t]*;[ \t]*STRROM_TABLE[ \t]*$")
RX_ASCII = re.compile(r"[ \t]+\.ASCII_([WP])[ \t]+\"")


class TestError(Exception):
    """The test cannot be built or run; this is a failure, too."""


def read_text(path):
    with open(path, "rb") as f:
        return f.read().decode("latin-1")


def h4(value):
    return "%04X" % (value & 0xFFFF)


# ---------------------------------------------------------------------------
# Model of the string ROM, derived from the sources
# ---------------------------------------------------------------------------

class Unit:
    """A string ROM string: everything up to and including a terminator."""

    def __init__(self, origin):
        self.origin = origin        # source file
        self.labels = []            # (name, offset inside of the string)
        self.words = []             # characters and the terminator
        self.pos = None             # position in the string ROM


def parse_literal(text, where):
    """Characters of the text between the double quotes of an .ASCII_W or
    .ASCII_P line, as the QNICE assembler encodes them. Only what the Shell
    uses is supported, because the assembler treats other escape sequences
    in ways that are not worth relying on."""
    out, i = [], 0
    while i < len(text):
        c = text[i]
        if c == "\\":
            if i + 1 >= len(text):
                raise TestError("%s: a backslash at the end of a string "
                                "is not supported" % where)
            d = text[i + 1]
            if d == "n":
                out += [0x0D, 0x0A]
            elif d in "t\\" or i + 2 != len(text):
                # after a backslash that is not followed by an n the
                # assembler stays in its escape state until the end of the
                # line, so such a pair needs to be the last one
                raise TestError("%s: only \\n and, at the end of a line, a "
                                "backslash and one other character are "
                                "supported" % where)
            else:
                out += [0x5C, ord(d)]
            i += 2
        else:
            out.append(0x20 if c == "\t" else ord(c))   # tabs become blanks
            i += 1
    return out


def parse_marked(lines):
    """Units of all string ROM sections. lines: (origin, text) of the source
    after the C preprocessor. Returns (units, amount of table markers)."""
    units, pending, cur = [], [], None
    inside, tables = False, 0
    for origin, line in lines:
        line = line.rstrip("\r\n")
        where = "%s: %s" % (os.path.basename(origin), line.strip())
        if RX_TABLE.match(line):
            tables += 1
            continue
        if RX_BEGIN.match(line):
            if inside:
                raise TestError("STRROM_BEGIN inside of a section: " + where)
            inside = True
            continue
        if RX_END.match(line):
            if not inside or pending or cur is not None:
                raise TestError("STRROM_END at the wrong place, after a "
                                "label or after an .ASCII_P: " + where)
            inside = False
            continue
        if not inside or re.match(r"^[ \t]*(;.*)?$", line):
            continue
        if len(line) > 250:
            raise TestError("line too long for the assembler: " + where)
        label, rest = None, line
        if line[0] not in " \t":
            label = re.match(r"[^ \t;]+", line).group(0)
            rest = line[len(label):]
        if re.match(r"^[ \t]*(;.*)?$", rest):       # a label on its own
            if cur is None:
                pending.append(label)
            else:
                cur.labels.append((label, len(cur.words)))
            continue
        m = RX_ASCII.match(rest)
        if not m:
            raise TestError("not allowed in a string ROM section: " + where)
        if cur is None:
            if label is None and not pending:
                raise TestError("string without a label: " + where)
            cur = Unit(origin)
            cur.labels = [(name, 0) for name in pending]
            pending = []
        if label is not None:
            cur.labels.append((label, len(cur.words)))
        body = rest[m.end():]
        if '"' not in body:
            raise TestError("missing closing double quote: " + where)
        cur.words += parse_literal(body[:body.index('"')], where)
        if m.group(1) == "W":
            cur.words.append(0)
            units.append(cur)
            cur = None
    if inside:
        raise TestError("STRROM_BEGIN without STRROM_END")
    return units, tables


def place(units, size):
    """Positions of the units: a string is read through the 4k window, so it
    must not cross a 4k boundary. A string that would do so starts at the
    next boundary. Returns the amount of characters that are needed."""
    cursor = 0
    for unit in units:
        length = len(unit.words)
        if length > WIN:
            raise TestError("the string %s has %d characters including its "
                            "terminator, the maximum is %d"
                            % (unit.labels[0][0], length, WIN))
        if cursor % WIN + length > WIN:
            cursor += WIN - cursor % WIN
        unit.pos = cursor
        cursor += length
    if cursor > size:
        raise TestError("the strings need %d characters, the string ROM has "
                        "%d" % (cursor, size))
    return cursor


class Model:
    """Expected content of the string ROM and expected table of handles."""

    def __init__(self, units, size):
        self.units = units
        self.size = size
        self.used = place(units, size)
        self.image = bytearray(size)
        self.labels = []            # names in the order of the table
        self.pos = {}               # label -> position in the string ROM
        self.unit = {}              # label -> (unit, offset)
        for unit in units:
            for offset, word in enumerate(unit.words):
                if not 0 <= word <= 255:
                    raise TestError("character above 0xFF in "
                                    + unit.labels[0][0])
                self.image[unit.pos + offset] = word
            for name, offset in unit.labels:
                if name in self.pos:
                    raise TestError("label %s is defined twice" % name)
                self.labels.append(name)
                self.pos[name] = unit.pos + offset
                self.unit[name] = (unit, offset)

    def string(self, name):
        """Characters of a handle including the terminator."""
        unit, offset = self.unit[name]
        return unit.words[offset:]


# ---------------------------------------------------------------------------
# Sources: C preprocessor, sections of the Shell, fixtures
# ---------------------------------------------------------------------------

def build_env():
    """The firmware of the test is built in the C locale, in which all tools
    process the sources byte by byte: its strings contain characters above
    0x7F to exercise all eight data bits of the string ROM, and the sed of
    BSD, which is part of the build, rejects such bytes in UTF-8 locales."""
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    return env


def preprocess():
    """The firmware source after the C preprocessor as (origin, text) lines,
    the way asm_strrom.sh and the asm wrapper of QNICE produce it."""
    cpp = shutil.which("cc") or shutil.which("gcc")
    if not cpp:
        raise TestError("neither cc nor gcc found: the C preprocessor is "
                        "needed to assemble the firmware")
    res = subprocess.run([cpp, "-xc", "-E", FW + ".asm"], cwd=HERE,
                         env=build_env(), capture_output=True, timeout=120)
    if res.returncode != 0:
        raise TestError("the C preprocessor failed:\n"
                        + res.stderr.decode("latin-1")[-2000:])
    lines, origin = [], os.path.join(HERE, FW + ".asm")
    for line in res.stdout.decode("latin-1").split("\n"):
        if line.startswith("#"):
            m = re.match(r'#(?:line)?\s+\d+\s+"([^"]*)"', line)
            if m and not m.group(1).startswith("<"):
                origin = os.path.normpath(os.path.join(HERE, m.group(1)))
            continue
        lines.append((origin, line))
    return lines


def shell_sections(present):
    """String ROM sections of the Shell that the firmware of the test does
    not include: [(file, lines)]. present: labels that it already has."""
    found = []
    for pattern in SHELL_SOURCES:
        for path in sorted(glob.glob(os.path.join(REPO, *pattern.split("/")))):
            if os.path.basename(path).startswith("__"):
                continue                        # leftovers of asm_strrom.sh
            section = None
            for line in read_text(path).split("\n"):
                line = line.rstrip("\r")
                if RX_BEGIN.match(line):
                    section = []
                elif RX_END.match(line):
                    if section is None:
                        raise TestError("STRROM_END without STRROM_BEGIN "
                                        "in " + path)
                    first = next((re.match(r"[^ \t;]+", l).group(0)
                                  for l in section
                                  if l and l[0] not in " \t;#"), None)
                    if first is not None and first not in present:
                        found.append((path, section))
                    section = None
                elif section is not None:
                    section.append(line)
            if section is not None:
                raise TestError("STRROM_BEGIN without STRROM_END in " + path)
    return found


def filler_text(length, tag):
    """Text of the given length that shows its position every eight chars."""
    text = ""
    while len(text) < length:
        n = len(text) // 8
        text += "%s%04d:%s%s" % (tag, n, chr(97 + n % 26), chr(65 + n % 23))
    return text[:length]


def ascii_lines(label, text, per_line=56):
    """Assembler lines for a string ROM string."""
    out = []
    chunks = [text[i:i + per_line] for i in range(0, len(text), per_line)]
    chunks = chunks or [""]
    for i, chunk in enumerate(chunks):
        directive = ".ASCII_W" if i == len(chunks) - 1 else ".ASCII_P"
        out.append("%-15s %s \"%s\"" % (label if i == 0 else "", directive,
                                       chunk))
    return out


def unit_of(label, text, origin=FIXTURES):
    unit = Unit(origin)
    unit.labels = [(label, 0)]
    unit.words = [ord(c) for c in text] + [0]
    return unit


class Layout:
    """Strings that are generated to create the edge cases that depend on
    positions, for the current length of the real strings:

    SST_G_ALIGN1  in front of ../strings.asm: fills the gap in front of the
                  first of its strings that does not fit into its 4k window,
                  so that a real string ends at the last address of a window
    SST_G_ALIGN2  behind ../strings.asm: fills its 4k window up to the point
                  where SST_G_MOVED is one character too long for the rest
    SST_G_MOVED   the string that the tool moves to the next 4k window
    SST_G_HIGH    characters above 0x7F
    SST_G_LONG    the longest possible string: it fills a whole 4k window
    """

    HIGH = "8 bit: \x80\x81\xa5\xc4\xe9\xfe\xff\x7f."
    MOVED = "moved, one too long!"

    def __init__(self, units, extras, size):
        first = next((i for i, u in enumerate(units)
                      if u.origin == STRINGS_ASM), None)
        if first is None or any(u.origin != STRINGS_ASM
                                for u in units[first:]):
            raise TestError("the string ROM section of ../strings.asm is "
                            "expected to be the last one in front of the "
                            "generated strings")
        head, shell = units[:first], units[first:]
        self.extras = extras
        self.notes = []
        tail = [u for _, _, us in extras for u in us]
        tail += [unit_of("SST_G_HIGH", self.HIGH),
                 unit_of("SST_G_LONG", filler_text(WIN - 1, "L"))]

        # SST_G_ALIGN1
        self.align1 = None
        place(head + shell, 1 << 16)
        for i, unit in enumerate(shell):
            before = (shell[i - 1] if i else head[-1]) if (i or head) else None
            gap = unit.pos - (before.pos + len(before.words)) if before else 0
            if gap:
                self.align1 = filler_text(gap - 1, "A")
                break
        if self.align1 is None:
            self.notes.append("no string of ../strings.asm crosses a 4k "
                              "boundary: no real string is placed at the "
                              "end of a window")
        aligned = head + ([unit_of("SST_G_ALIGN1", self.align1)]
                          if self.align1 is not None else []) + shell

        # SST_G_ALIGN2 and SST_G_MOVED
        self.align2 = self.moved = None
        pair = []
        rest = WIN - place(aligned, 1 << 16) % WIN
        if rest < WIN:
            moved = self.MOVED[:min(len(self.MOVED), rest)]
            pair = [unit_of("SST_G_MOVED", moved)]
            if rest > len(moved):
                self.align2 = filler_text(rest - len(moved) - 1, "B")
                pair.insert(0, unit_of("SST_G_ALIGN2", self.align2))
            try:
                place(aligned + pair + tail, size)
                self.moved = moved
            except TestError:
                self.align2, pair = None, []
        if self.moved is None:
            self.notes.append("the string that is one character too long "
                              "for the rest of its window does not fit any "
                              "more: the real strings have grown")
        try:
            place(aligned + pair + tail, size)
        except TestError:
            raise TestError(
                "The strings of the test do not fit into the string ROM any "
                "more next to the real strings of the Shell. Remove strings "
                "from the test or increase C_STRROM_ADDR_WIDTH.")

    def strings_part(self):
        """The part of the fixtures that contains the string ROM sections."""
        def section(lines):
            return [";STRROM_BEGIN"] + lines + [";STRROM_END", ""]

        out = []
        if self.align1 is not None:
            out += section(ascii_lines("SST_G_ALIGN1", self.align1))
        out += ["#include \"../strings.asm\"", ""]
        if self.moved is not None:
            lines = []
            if self.align2 is not None:
                lines += ascii_lines("SST_G_ALIGN2", self.align2)
            out += section(lines + ascii_lines("SST_G_MOVED", self.moved))
        for path, lines, _ in self.extras:
            out += ["; string ROM section of "
                    + os.path.relpath(path, REPO).replace(os.sep, "/")]
            out += section(lines)
        out += section(ascii_lines("SST_G_HIGH", self.HIGH))
        out += section(ascii_lines("SST_G_LONG", filler_text(WIN - 1, "L")))
        return out


def write_fixtures(tables, strings):
    header = ["; AUTOGENERATED by strrom_sim_test.py - DO NOT EDIT", ""]
    with open(FIXTURES, "wb") as f:
        f.write("\n".join(header + tables + strings + [""]).encode("latin-1"))


# ---------------------------------------------------------------------------
# Outputs of the assembler
# ---------------------------------------------------------------------------

class Firmware:
    """Labels, constants and words of the assembled firmware."""

    def __init__(self):
        lis = read_text(os.path.join(HERE, FW + ".lis"))
        if "Label-list:" not in lis:
            raise TestError(FW + ".lis has no label list")
        tail = lis[min(lis.index(name) for name in ("EQU-list:", "Label-list:")
                       if name in lis):]
        self.sym = {m.group(1): int(m.group(2), 16) for m in
                    re.finditer(r"(\S+)\s*:\s*0x([0-9A-Fa-f]{4})\b", tail)}
        self.mem = {}
        self.rom_words = 0
        with open(os.path.join(HERE, FW + ".out")) as f:
            for number, line in enumerate(f):
                addr, value = (int(x, 16) for x in line.split()[:2])
                self.mem[addr] = value
                if addr == number == self.rom_words:
                    self.rom_words += 1
                elif addr < WIN_BASE:
                    raise TestError("%s.out: the ROM is not contiguous at "
                                    "0x%04X" % (FW, addr))
        if self.rom_words > WIN_BASE:
            raise TestError("the firmware of the test has %d words, the ROM "
                            "ends at 0x7000" % self.rom_words)

    def words(self, addr):
        """Zero terminated string in the ROM."""
        out = []
        while True:
            out.append(self.mem[addr + len(out)])
            if out[-1] == 0:
                return out


def vhdl_constant(path, name, kind):
    """Value of a simple constant of a VHDL file."""
    rx = {"natural": r":\s*natural\s*:=\s*(\d+)\s*;",
          "string": r":\s*string\s*:=\s*\"([^\"]*)\"\s*;"}[kind]
    m = re.search(r"constant\s+%s\s*%s" % (name, rx), read_text(path))
    if not m:
        raise TestError("cannot read the constant %s from %s: the test "
                        "expects a plain %s" % (name, path, kind))
    return int(m.group(1)) if kind == "natural" else m.group(1)


# ---------------------------------------------------------------------------
# Models of the routines under test
# ---------------------------------------------------------------------------

def model_puts(words):
    """IO$PUTS: the lower eight bits of each word, a zero byte ends it."""
    out = []
    for word in words:
        if word & 0xFF == 0:
            break
        out.append("U " + h4(word & 0xFF))
    return out


def model_log_str(words):
    """LOG_STR: a backslash and the character behind it become LF CR (the
    crlf of the QNICE Monitor); IO$PUTCHAR drops words above 0xFF."""
    out, i = [], 0
    while words[i] != 0:
        if words[i] == 0x5C:
            out += ["U 000A", "U 000D"]
            i += 2
        else:
            if words[i] & 0xFF00 == 0:
                out.append("U " + h4(words[i]))
            i += 1
    return out


def model_printstr(words, x, y, ilx, dx):
    """SCR$PRINTSTR: write accesses to the 4k window as (offset, word) and
    the cursor after the call. CR or backslash followed by LF or n is a new
    line; followed by something else both characters are printed and the
    cursor stays where it is."""
    writes, i = [], 0
    offset = y * dx + x
    while True:
        c = words[i]
        i += 1
        if c in (0x0D, 0x5C):
            d = words[i]
            i += 1
            if d in (0x0A, ord("n")):
                x, y = ilx, y + 1
                offset = y * dx + x
            else:
                writes += [(offset, c), (offset + 1, d)]
                offset += 2
            continue
        if c == ord("<"):
            c = 17                              # M2M$DIR_L
        elif c == ord(">"):
            c = 16                              # M2M$DIR_R
        elif c == 0:
            return writes, x, y
        writes.append((offset, c))
        offset += 1
        x += 1


def check_printable(words, name):
    """LOG_STR and SCR$PRINTSTR read behind the terminator of a string that
    ends with a backslash or a CR: the test must not contain such strings."""
    i = 0
    while words[i] != 0:
        if words[i] in (0x0D, 0x5C):
            i += 1
            if words[i] == 0:
                raise TestError("the string %s ends with a backslash or a "
                                "CR" % name)
        i += 1


# ---------------------------------------------------------------------------
# The test
# ---------------------------------------------------------------------------

class Case:
    """A record of the case table."""

    def __init__(self, value, dev, win, cursor, name):
        self.value = value          # R8: number or name of a label
        self.dev, self.win = dev, win
        self.cursor = cursor
        self.name = name
        self.routines = []          # (routine, job)
        self.wanted = []            # routines to distribute to the jobs
        self.words = None
        self.kind = "handle"


class Test:
    def __init__(self, args):
        self.full = args.full
        self.jobs = args.jobs
        self.aw = vhdl_constant(WRAPPER_VHDL, "C_STRROM_ADDR_WIDTH", "natural")
        self.size = 1 << self.aw
        self.windows = self.size // WIN
        if self.windows < 2:
            raise TestError("the test needs a string ROM of at least two 4k "
                            "windows (C_STRROM_ADDR_WIDTH >= 13)")
        self.dx = (vhdl_constant(GLOBALS_VHDL, "VGA_DX", "natural")
                   // vhdl_constant(GLOBALS_VHDL, "FONT_DX", "natural"))
        self.dy = (vhdl_constant(GLOBALS_VHDL, "VGA_DY", "natural")
                   // vhdl_constant(GLOBALS_VHDL, "FONT_DY", "natural"))
        if not self.dx * self.dy <= VRAM_WORDS < 2 * self.dx * self.dy:
            raise TestError("unexpected size of the video RAM")
        self.config = {win: vhdl_constant(CONFIG_VHDL, name, "string")
                       for win, name in CONFIG_STRINGS.items()}
        self.failures = []
        self.notes = []
        self.processes = []         # simulations

    def fail(self, text):
        self.failures.append(text)

    # -- sources ------------------------------------------------------------

    def generate(self):
        """Writes the fixtures and builds the model of the string ROM."""
        write_fixtures([], ["#include \"../strings.asm\""])
        units, _ = parse_marked(preprocess())
        present = {name for unit in units for name, _ in unit.labels}
        extras = []
        for path, lines in shell_sections(present):
            extra, _ = parse_marked([(path, ";STRROM_BEGIN")]
                                    + [(path, line) for line in lines
                                       if not line.startswith("#")]
                                    + [(path, ";STRROM_END")])
            extras.append((path, lines, extra))
        self.layout = Layout(units, extras, self.size)
        self.notes += self.layout.notes
        strings = self.strings_part = self.layout.strings_part()

        write_fixtures([], strings)
        units, tables = parse_marked(preprocess())
        if tables != 1:
            raise TestError("the marker STRROM_TABLE is expected exactly "
                            "once in the firmware, found %d" % tables)
        self.model = Model(units, self.size)
        self.plan_cases()
        write_fixtures(self.tables_part(), strings)
        units, _ = parse_marked(preprocess())
        if [u.words for u in units] != [u.words for u in self.model.units]:
            raise TestError("the tables of the fixtures changed the strings")

    def coverage(self):
        """The edge cases that the strings of the test are made for. They
        depend on the layout, so make sure that they are really there."""
        m = self.model
        facts = []

        def window(name):
            return m.pos[name] // WIN

        ends = [u for u in m.units if (u.pos + len(u.words)) % WIN == 0]
        short = [u for u in ends if len(u.words) < WIN]
        if short:
            facts.append("%s ends at the last address of window %d"
                         % (short[0].labels[0][0], short[0].pos // WIN))
        elif self.layout.align1 is not None:
            self.fail("coverage: no short string ends at the last address "
                      "of a 4k window")
        if "SST_G_MOVED" in m.pos:
            unit = m.unit["SST_G_MOVED"][0]
            before = m.units[m.units.index(unit) - 1]
            gap = unit.pos - before.pos - len(before.words)
            if unit.pos % WIN or gap != len(unit.words) - 1:
                self.fail("coverage: SST_G_MOVED is not one character too "
                          "long for the rest of its window (gap %d, length "
                          "%d)" % (gap, len(unit.words)))
            facts.append("SST_G_MOVED did not fit by one character and "
                         "starts window %d" % window("SST_G_MOVED"))
        longest = m.unit["SST_G_LONG"][0]
        if len(longest.words) != WIN or longest.pos % WIN:
            self.fail("coverage: SST_G_LONG does not fill a 4k window")
        facts.append("SST_G_LONG fills window %d%s"
                     % (window("SST_G_LONG"), " up to the last address of "
                        "the string ROM" if m.used == m.size else ""))
        moved = [u for i, u in enumerate(m.units) if i and u.pos % WIN == 0
                 and u.pos != m.units[i - 1].pos + len(m.units[i - 1].words)]
        if not moved:
            self.fail("coverage: no string was moved to the next 4k window")
        used = sorted({u.pos // WIN for u in m.units})
        if len(used) < 2:
            self.fail("coverage: only one 4k window is in use")
        if not any(offset for u in m.units for _, offset in u.labels):
            self.fail("coverage: no label in the middle of a string")
        if not any(w > 0x7F for u in m.units for w in u.words):
            self.fail("coverage: no character above 0x7F")
        if not any(len(u.words) == 1 for u in m.units):
            self.fail("coverage: no empty string")
        facts.append("%d strings were moved to the next window, windows in "
                     "use: %s" % (len(moved), ", ".join(map(str, used))))
        return facts

    # -- case table and jobs ------------------------------------------------

    def plan_cases(self):
        """Cases for the handles and their distribution to the jobs."""
        m = self.model
        special = set()                 # handles that run all routines
        for unit in m.units:
            names = [name for name, _ in unit.labels]
            if (unit.pos % WIN == 0                 # first of a window
                    or (unit.pos + len(unit.words)) % WIN == 0  # last
                    or len(names) > 1):             # several labels
                special.update(names)
        special.update(name for name in m.labels
                       if name.startswith("SST_S_") or name in
                       ("SST_G_MOVED", "SST_G_HIGH", m.labels[0]))
        cheap = {"SST_G_ALIGN1", "SST_G_ALIGN2", "SST_G_LONG"}

        self.handle_cases = []
        number = 0
        for i, name in enumerate(m.labels):
            if self.full or (name in special and name not in cheap):
                routines = [RT_PUTS, RT_LOG, RT_SCR]
            elif name in cheap:
                routines = [RT_PUTS]
            else:
                routines = [(RT_PUTS, RT_LOG, RT_SCR)[i % 3]]
            presets = [PRESETS[i % len(PRESETS)]]
            if name in ("SST_S_ONE", "SST_S_LINES"):
                presets = PRESETS                   # with every preset
            for dev, win in presets:
                case = Case(name, dev, win, CURSORS[number % len(CURSORS)],
                            name)
                case.words = m.string(name)
                check_printable(case.words, name)
                case.wanted = self.fit(case, routines)
                self.handle_cases.append(case)
                number += 1

    def fit(self, case, routines):
        """SCR$PRINTSTR does not clip: a string that would leave the 4k
        window of the video RAM gets the cursor 0|0 or another routine."""
        if RT_SCR not in routines:
            return routines
        for cursor in (case.cursor, (0, 0, 0)):
            writes, _, _ = model_printstr(case.words, *cursor, self.dx)
            if all(offset < WIN for offset, _ in writes):
                case.cursor = cursor
                return routines
        self.notes.append("%s is too long for SCR$PRINTSTR" % case.name)
        return [r for r in routines if r != RT_SCR] or [RT_LOG]

    def cost(self, case, routine):
        return COST_CALL[routine] + COST_CHAR[routine] * len(case.words)

    def section_costs(self):
        m = self.model
        handles = len(m.labels)
        chars = sum(len(m.string(name)) for name in m.labels)
        return {SEC_SERIAL: 9 * COST_UART_CHAR,
                SEC_VRAM: 31 * self.dx * self.dy,
                SEC_DUMP: 6 * self.size + 1000,
                SEC_OPEN: 1050 * (handles + 12),
                SEC_WALK: 10.5 * chars + 150 * handles}

    def distribute(self):
        """Assigns sections and cases to the jobs: the most expensive item
        goes to the job with the smallest load so far."""
        costs = self.section_costs()
        load = [5000.0] * self.jobs
        self.job_sections = [0] * self.jobs
        # one job has the UART, the video RAM and the static cases
        self.job_sections[0] = SEC_SERIAL | SEC_VRAM
        load[0] += costs[SEC_SERIAL] + costs[SEC_VRAM]
        load[0] += sum(self.cost(case, r) for case in self.static_cases
                       for r, _ in case.routines)
        items = [(costs[sec], n, ("section", sec)) for n, sec in
                 enumerate((SEC_DUMP, SEC_OPEN, SEC_WALK))]
        for case in self.handle_cases:
            case.routines = []
            for r in case.wanted:
                items.append((self.cost(case, r), len(items), (case, r)))
        for cost, _, item in sorted(items, key=lambda t: (-t[0], t[1])):
            job = load.index(min(load))
            load[job] += cost
            if item[0] == "section":
                self.job_sections[job] |= item[1]
            else:
                item[0].routines.append((item[1], job))
        self.load = load

    def tables_part(self):
        """The part of the fixtures that contains the tables. The cases are
        distributed later, when the static cases are known, so the first
        word of each record is patched by a second run of this function."""
        out = ["; case table: records for the handles"]
        for case in self.handle_cases:
            bits = 0
            for routine, job in case.routines:
                bits |= routine << (3 * job)
            x, y, ilx = case.cursor
            out.append("                .DW     0x%04X, %s, 0x%04X, 0x%04X, "
                       "%d, %d, %d" % (bits, case.value, case.dev, case.win,
                                       x, y, ilx))
        out += ["                .DW     0xFFFF", ""]
        sections = getattr(self, "job_sections", [0] * self.jobs)
        sections = sections + [0] * (MAX_JOBS - len(sections))
        out += ["; sections of the test per job",
                "SST_JOBSEC      .DW     "
                + ", ".join("0x%04X" % s for s in sections), "",
                "; devices and 4k windows that are selected in turns"]
        for i, (dev, win) in enumerate(PRESETS):
            out.append("%-15s .DW     0x%04X, 0x%04X"
                       % ("SST_PRESETS" if i == 0 else "", dev, win))
        out += ["SST_PRESETS_END", "",
                "; amount of 4k windows of the string ROM",
                "SST_WINDOWS     .EQU    %d" % self.windows, ""]
        return out

    # -- build --------------------------------------------------------------

    def build(self):
        """Assembles the firmware with the tool of the real firmware."""
        res = subprocess.run([TOOL, FW + ".asm", STR, str(self.aw)],
                             cwd=HERE, env=build_env(), capture_output=True,
                             timeout=300)
        out = res.stdout.decode("latin-1")
        rom = os.path.join(HERE, STR + ".rom")
        if res.returncode != 0 or not os.path.exists(rom):
            lines = [l for l in out.split("\n") if l.strip()]
            raise TestError("asm_strrom.sh failed (exit code %d):\n%s"
                            % (res.returncode, "\n".join(lines[-15:])))
        self.tool_summary = re.search(
            r"String ROM: (\d+)/(\d+) characters in (\d+) strings", out)
        return out

    def read_static_cases(self):
        """The records of the case table that strrom_sim_test.asm contains:
        ordinary strings."""
        fw = self.fw
        copies = []
        addr = fw.sym["SST_COPY"]
        while fw.mem[addr] != 0:
            copies.append([fw.mem[addr + i] for i in range(4)])
            addr += 4

        def copied(value, in_window):
            """String that the firmware copied to the RAM or to the 4k
            window of the device of the testbench."""
            for src, dst, dev, win in copies:
                words = fw.words(src)
                if ((WIN_BASE <= dst < WIN_BASE + WIN) == in_window
                        and (not in_window or (dev, win) == DEV_CORE)
                        and dst <= value < dst + len(words)):
                    return words[value - dst:]
            raise TestError("no string at 0x%04X" % value)

        self.static_cases = []
        addr = fw.sym["SST_CASES"]
        end = addr
        while fw.mem[end] != 0xFFFF:
            end += CASE_SIZE
        count = (end - addr) // CASE_SIZE - len(self.handle_cases)
        for n in range(count):
            bits, value, dev, win, x, y, ilx = (
                fw.mem[addr + n * CASE_SIZE + i] for i in range(CASE_SIZE))
            case = Case(value, dev, win, (x, y, ilx), "0x%04X" % value)
            case.routines = [(r, 0) for r in (RT_PUTS, RT_LOG, RT_SCR)
                             if bits & r]
            if bits & ~7:
                raise TestError("static records belong to job 0")
            if value < WIN_BASE:
                if fw.sym["STRROM$TAB"] <= value < fw.sym["STRROM$TAB_END"]:
                    raise TestError("static record with a handle")
                case.words, case.kind = fw.words(value), "ROM"
            elif value >= WIN_BASE + WIN:
                case.words, case.kind = copied(value, False), "RAM"
            elif (dev, win) == DEV_CORE:
                case.words, case.kind = copied(value, True), "device"
            elif dev == DEV_CONFIG and win in self.config:
                text = self.config[win][value - WIN_BASE:]
                case.words = [ord(c) for c in text] + [0]
                case.kind = "config.vhd"
            else:
                raise TestError("static record with an unknown string")
            check_printable(case.words, case.name)
            writes, _, _ = model_printstr(case.words, x, y, ilx, self.dx)
            if any(offset >= WIN for offset, _ in writes):
                raise TestError("static record leaves the video RAM")
            self.static_cases.append(case)
        # the ordinary strings that the test is made for
        kinds = {case.kind for case in self.static_cases}
        if kinds != {"ROM", "RAM", "device", "config.vhd"}:
            self.fail("coverage: ordinary strings only in " + str(kinds))
        if not any(case.kind == "ROM" and case.value < fw.sym["STRROM$TAB"]
                   for case in self.static_cases):
            self.fail("coverage: no ordinary string below the table")
        if not any(case.kind == "device" and
                   case.value + len(case.words) == WIN_BASE + WIN
                   for case in self.static_cases):
            self.fail("coverage: no string at the end of a device window")
        if not any(a == 0x5C and b == ord("n") for case in self.static_cases
                   for a, b in zip(case.words, case.words[1:])):
            self.fail("coverage: no ordinary string with backslash and n")

    def static_checks(self, tool_output):
        """Compares the outputs of asm_strrom.sh with the model."""
        m, fw = self.model, self.fw
        with open(os.path.join(HERE, STR + ".rom")) as f:
            rom = f.read().split("\n")
        if rom and rom[-1] == "":
            rom.pop()
        if len(rom) != self.size:
            self.fail("build: %s.rom has %d lines, expected %d"
                      % (STR, len(rom), self.size))
        diff = [a for a in range(min(len(rom), self.size))
                if rom[a].strip().upper() != "%02X" % m.image[a]]
        if diff:
            a = diff[0]
            self.fail("build: %s.rom differs from the sources at %d "
                      "addresses, first at 0x%04X: found %s, expected %02X"
                      % (STR, len(diff), a, rom[a], m.image[a]))
        tab, tab_end = fw.sym["STRROM$TAB"], fw.sym["STRROM$TAB_END"]
        if tab_end - tab != len(m.labels):
            self.fail("build: the table has %d entries, the sources have "
                      "%d labels" % (tab_end - tab, len(m.labels)))
        bad = []
        for name in m.labels:
            addr = fw.sym.get(name)
            if addr is None or not tab <= addr < tab_end:
                bad.append("%s is no handle" % name)
            elif fw.mem[addr] != m.pos[name]:
                bad.append("%s: table says 0x%04X, expected 0x%04X"
                           % (name, fw.mem[addr], m.pos[name]))
        if bad:
            self.fail("build: %d wrong table entries, first: %s"
                      % (len(bad), bad[0]))
        self.table_ok = (tab_end - tab == len(m.labels)
                         and not any("no handle" in text for text in bad))
        s = self.tool_summary
        if not s or (int(s.group(1)), int(s.group(2)), int(s.group(3))) != (
                m.used, self.size, len(m.labels)):
            self.fail("build: unexpected summary of asm_strrom.sh, expected "
                      "%d/%d characters in %d strings: %s"
                      % (m.used, self.size, len(m.labels),
                         s.group(0) if s else tool_output[-200:]))
        # the file names that the hardware uses need to be the outputs of
        # make_rom.sh; they are relative to the VHDL file that opens them
        for vhdl, name, opener, target in (
                (WRAPPER_VHDL, "C_STRROM_FILE", "M2M/vhdl",
                 "CORE/m2m-rom/m2m-strings.rom"),
                (GLOBALS_VHDL, "QNICE_FIRMWARE_M2M", "M2M/QNICE/vhdl",
                 "CORE/m2m-rom/m2m-rom.rom")):
            path = vhdl_constant(vhdl, name, "string")
            if os.path.normpath(os.path.join(REPO, opener, path)) != \
                    os.path.join(REPO, *target.split("/")):
                self.fail("build: %s = \"%s\" is not %s" % (name, path,
                                                            target))

    # -- expected output of the simulation ----------------------------------

    def handle_state(self, value):
        """R8, device and window after STRROM$OPEN, None if no handle."""
        fw = self.fw
        if not fw.sym["STRROM$TAB"] <= value < fw.sym["STRROM$TAB_END"]:
            return None
        pos = self.model.pos[self.handle_name[value]]
        return WIN_BASE + pos % WIN, DEV_STRROM, pos // WIN

    def expected(self, job):
        """Records that the simulation of a job has to write: (marker,
        description, lines). Also returns the characters at the UART pin."""
        m, fw = self.model, self.fw
        sections = self.job_sections[job]
        tab, tab_end = fw.sym["STRROM$TAB"], fw.sym["STRROM$TAB_END"]
        stack = fw.sym["VAR$STACK_START"]
        records, serial = [], []
        preset = [0]

        def log(*values):
            return ["L " + h4(v) for v in values]

        def next_preset():
            preset[0] += 1
            return PRESETS[(preset[0] - 1) % len(PRESETS)]

        records.append((MK_START + job, "start",
                        log(tab, tab_end, self.dx, self.dy)))

        if sections & SEC_DUMP:
            for window in range(self.windows):
                records.append((MK_DUMP + window, "string ROM, window %d"
                                % window, log(*m.image[window * WIN:
                                                       (window + 1) * WIN])))
            probes = range(fw.sym["SST_PROBES"], fw.sym["SST_PROBES_END"])
            lines = []
            for window in (fw.mem[a] for a in probes):
                for offset in (0, 1, WIN - 2, WIN - 1):
                    # the window selector continues the address and the
                    # string ROM only decodes the address bits that it has
                    lines += log(m.image[(window * WIN + offset) % m.size])
            records.append((MK_PROBE, "windows behind the string ROM",
                            lines))
            records.append((MK_WRITE, "the string ROM is read-only",
                            log(m.image[0], m.image[0])))

        def open_close(value, sp, calls=(), flags=None):
            """Lines of SST$LOGSEL around STRROM$OPEN and STRROM$CLOSE. With
            flags: the Carry and the Overflow flag are reported after each
            of the two calls, and neither of them changes these flags."""
            dev, win = next_preset()
            state = self.handle_state(value)
            r8, odev, owin = state or (value, dev, win)
            kept = [] if flags is None else log(flags)
            lines = log(value, dev, win, sp)
            lines += kept + log(r8, odev, owin, sp - 2)
            for inner in calls:                 # nested: (value)
                istate = self.handle_state(inner)
                i8, idev, iwin = istate or (inner, odev, owin)
                lines += log(i8, idev, iwin, sp - 4)
                lines += log(i8, odev, owin, sp - 2)
                r8 = i8
            return lines + kept + log(r8, dev, win, sp)

        if sections & SEC_OPEN:
            bound = range(fw.sym["SST_BOUND"], fw.sym["SST_BOUND_END"], 2)
            values = list(range(tab, tab_end))
            values += [(fw.mem[a] + fw.mem[a + 1]) & 0xFFFF for a in bound]
            for value in values:
                name = self.handle_name.get(value, "no handle")
                for flags, text in ((FLAGS, "set"), (0, "clear")):
                    records.append((MK_OPEN, "STRROM$OPEN/CLOSE with 0x%04X "
                                    "(%s), Carry and Overflow %s"
                                    % (value, name, text),
                                    open_close(value, stack - 1, flags=flags)
                                    + log(*REG_PATTERN)))
            records.append((MK_NEST, "nested: first and last handle",
                            open_close(tab, stack, [tab_end - 1])))
            records.append((MK_NEST + 1, "nested: last handle and a pointer",
                            open_close(tab_end - 1, stack,
                                       [fw.sym["SST_RAMSTR"]])))
            required = [tab - 1, tab, tab_end - 1, tab_end, 0, 0xFFFF]
            bvalues = values[tab_end - tab:]
            if (any(v not in bvalues for v in required)
                    or not any(v < tab - 1 for v in bvalues if v)
                    or not any(tab_end < v < WIN_BASE for v in bvalues)
                    or not any(WIN_BASE <= v < WIN_BASE + WIN
                               for v in bvalues)
                    or not any(WIN_BASE + WIN <= v < 0xFF00
                               for v in bvalues)):
                self.fail("coverage: SST_BOUND misses a kind of value")

        if sections & SEC_WALK:
            for value in range(tab, tab_end):
                name = self.handle_name[value]
                dev, win = next_preset()
                records.append((MK_WALK, "read " + name,
                                log(value, *m.string(name)) + log(dev, win)))

        if sections & SEC_SERIAL:
            for n, (name, model, words) in enumerate((
                    ("SST_S_ONE", model_puts, m.string("SST_S_ONE")),
                    ("SST_S_UART", model_log_str, m.string("SST_S_UART")),
                    ("NEWLINE", model_puts, fw.words(fw.sym["NEWLINE"])))):
                lines = model(words)
                records.append((MK_SERIAL + n + 1, "real UART: " + name,
                                lines))
                serial += ["S " + line[-2:] for line in lines]
        records.append((MK_TURBO, "turbo mode", ["T 0001"]))

        vram = [0] * VRAM_WORDS         # attribute << 8 | character
        shadow = [0] * VRAM_WORDS       # as of the last dump

        def dump():
            lines = ["R %03X %04X" % (a, vram[a]) for a in range(VRAM_WORDS)
                     if vram[a] != shadow[a]]
            shadow[:] = vram
            return lines + ["E %d" % len(lines)]

        if sections & SEC_VRAM:
            lines = []
            for cell in range(self.dx * self.dy):
                lines += ["V %07X 0000" % cell, "A %07X 000B" % cell]
                vram[cell] = 0x0B00             # M2M$SA_COL_STD
            records.append((MK_CLR, "SCR$CLR", lines + dump()))

        for number, case in enumerate(self.static_cases + self.handle_cases):
            value = case.value if isinstance(case.value, int) \
                else fw.sym[case.value]
            select = log(value, case.dev, case.win, stack - 1)
            for routine in (RT_PUTS, RT_LOG, RT_SCR):
                if (routine, job) not in case.routines:
                    continue
                lines = log(number) + select
                if routine == RT_PUTS:
                    # IO$PUTS keeps the Carry and the Overflow flag: both
                    # are set for even records and clear for odd ones
                    lines += model_puts(case.words)
                    lines += log(0 if number % 2 else FLAGS) + select
                elif routine == RT_LOG:
                    lines += model_log_str(case.words) + select
                else:
                    writes, x, y = model_printstr(case.words, *case.cursor,
                                                  self.dx)
                    for offset, word in writes:
                        lines.append("V %07X %s" % (offset, h4(word)))
                        cell = offset % VRAM_WORDS
                        vram[cell] = vram[cell] & 0xFF00 | word & 0xFF
                    lines += select + log(x, y) + dump()
                records.append((MK_CASE + routine, "%s with %s, device "
                                "0x%04X, window 0x%04X" % (
                                    RT_NAMES[routine], case.name, case.dev,
                                    case.win), lines))

        if sections & SEC_VRAM:
            cells = range(fw.sym["SST_VRAM_CELLS"])
            records.append((MK_VRAM, "video RAM read by QNICE",
                            log(*[vram[c] & 0xFF for c in cells])
                            + log(*[vram[c] >> 8 for c in cells])))
        records.append((MK_END, "end", []))
        return records, serial

    # -- simulation ---------------------------------------------------------

    def prepare_simulation(self, ghdl, work):
        """Analyzes and elaborates the design. Returns the command prefix
        and the directory to run the simulation in."""
        version = subprocess.run([ghdl, "--version"], capture_output=True,
                                 text=True).stdout.lower()
        opts = ["--std=08", "-frelaxed", "-fsynopsys", "--workdir=" + work]
        if "llvm" in version or "gcc" in version:
            opts.insert(0, "-O2")       # the code generators can optimize
        files = []
        for rel in VHDL:
            src = os.path.join(REPO, *rel.split("/"))
            name = os.path.basename(rel)
            text = None
            if name == "sdcard.vhd":
                s = re.search(r"^library.*?^end\s+(entity\s+)?sdcard\s*;",
                              read_text(src), re.S | re.M | re.I)
                if not s:
                    raise TestError("entity sdcard not found in " + src)
                text = s.group(0) + "\n" + SDCARD_STUB
            elif name in GHDL_PATCHES:
                text = read_text(src)
                for rx, rep in GHDL_PATCHES[name]:
                    text, n = re.subn(rx, rep, text)
                    if n == 0:
                        raise TestError("ghdl patch for %s does not apply"
                                        % name)
            if text is not None:
                src = os.path.join(work, name)
                with open(src, "w", encoding="latin-1") as f:
                    f.write(text)
            files.append(src)
        files.append(os.path.join(HERE, "strrom_sim_tb.vhd"))

        # The design opens its ROMs by names that are constants of the VHDL
        # sources, relative to the VHDL file that opens them. ghdl resolves
        # them relative to the working directory, so the simulation runs in
        # a directory that makes both names point into the work directory.
        selected = re.search(r"constant\s+QNICE_FIRMWARE\s*:\s*string\s*:=\s*"
                             r"(\w+)\s*;", read_text(GLOBALS_VHDL))
        if not selected:
            raise TestError("cannot read QNICE_FIRMWARE from " + GLOBALS_VHDL)
        roms = {vhdl_constant(GLOBALS_VHDL, selected.group(1), "string"):
                self.firmware_rom(),
                vhdl_constant(WRAPPER_VHDL, "C_STRROM_FILE", "string"):
                read_text(os.path.join(HERE, STR + ".rom"))}
        depth = 0
        for name in roms:
            parts = name.split("/")
            ups = len([p for p in parts if p == ".."])
            if parts[:ups] != [".."] * ups or ".." in parts[ups:]:
                raise TestError("unexpected ROM file name " + name)
            depth = max(depth, ups)
        rundir = os.path.join(work, *["run%d" % i for i in range(depth)])
        os.makedirs(rundir)
        for name, content in roms.items():
            path = os.path.normpath(os.path.join(rundir, name))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w") as f:
                f.write(content)

        for step in ([ghdl, "-a"] + opts + files,
                     [ghdl, "-e"] + opts + ["strrom_sim_tb"]):
            res = subprocess.run(step, cwd=rundir, capture_output=True,
                                 text=True, timeout=900)
            if res.returncode != 0:
                raise TestError("ghdl %s failed:\n%s" % (
                    step[1], (res.stdout + res.stderr)[-3000:]))
        return [ghdl, "-r"] + opts + ["strrom_sim_tb"], rundir

    def firmware_rom(self):
        """The ROM image: the words below the variables."""
        with open(os.path.join(HERE, FW + ".rom")) as f:
            lines = f.read().split("\n")[:self.fw.rom_words]
        for addr, line in enumerate(lines):
            if int(line, 2) != self.fw.mem[addr]:
                raise TestError("%s.rom differs from %s.out at 0x%04X"
                                % (FW, FW, addr))
        return "\n".join(lines) + "\n"

    def run_job(self, job, expected, command, rundir, work):
        """Runs the simulation of a job and compares its output with the
        expected records while it runs."""
        records, serial = expected
        cycles = self.load[job]
        check = Checker(job, records, serial)
        with open(os.path.join(HERE, "strrom_sim_job%d.exp" % job), "w") as f:
            for marker, _, lines in records:
                f.write("\n".join(["M " + h4(marker)] + lines) + "\n")
            f.write("\n".join(serial + ["X END"]) + "\n")
        # the function of block_rom.vhd that reads the firmware returns it on
        # the stack, which ghdl limits to 128 kB by default
        command = command + ["-gG_JOB=%d" % job, "-gG_TIMEOUT=%d"
                             % (cycles * 1.5 * 20e-6 + 10),
                             "--ieee-asserts=disable", "--max-stack-alloc=0"]
        errors = os.path.join(work, "job%d.err" % job)
        limit = max(600, 3 * cycles / SIM_SPEED)
        start = time.time()
        with open(errors, "w") as err, \
                open(os.path.join(HERE, "strrom_sim_job%d.got" % job),
                     "w") as got:
            # a session of its own: ghdl -r starts the simulation as a child
            # process and stopping the simulation means stopping both
            proc = subprocess.Popen(command, cwd=rundir, stdout=subprocess.PIPE,
                                    stderr=err, text=True, encoding="latin-1",
                                    start_new_session=True)
            self.processes.append(proc)

            def watchdog():
                while proc.poll() is None:
                    time.sleep(1)
                    if time.time() - check.active > QUIET_LIMIT:
                        check.stuck = "no output for %d s" % QUIET_LIMIT
                    elif time.time() - start > limit:
                        check.stuck = "not finished after %d s" % limit
                    if check.stuck:
                        stop_simulation(proc)
                        return

            threading.Thread(target=watchdog, daemon=True).start()
            for line in proc.stdout:
                got.write(line)
                if not check.feed(line.rstrip("\r\n")):
                    stop_simulation(proc)
                    break
            proc.stdout.close()
            proc.wait()
        check.finish(proc.returncode, read_text(errors))
        check.seconds = time.time() - start
        return check


def stop_simulation(proc):
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except OSError:
        pass                        # it is gone already


class Checker:
    """Compares the output of a simulation with the expected records."""

    MAX_FAILURES = 8                # stop the simulation after that many
    MAX_EXCESS = 64                 # lines that a record may be too long
    PREFIXES = ("L ", "U ", "T ", "V ", "A ", "R ", "E ")

    def __init__(self, job, records, serial):
        self.job = job
        self.records = records
        self.serial = serial
        self.failures = []
        self.index = -1             # current record
        self.lines = []             # its lines so far
        self.got_serial = []
        self.end = None             # the X line
        self.complete = False
        self.cycles = 0
        self.aborted = False
        self.active = time.time()   # time of the last output
        self.stuck = None           # reason why the watchdog stopped it

    def fail(self, text):
        self.failures.append("job %d: %s" % (self.job, text))
        if len(self.failures) >= self.MAX_FAILURES:
            self.aborted = True

    def close_record(self):
        if self.index < 0:
            if self.lines:
                self.fail("output in front of the first marker: "
                          + self.lines[0])
            return
        marker, text, expected = self.records[self.index]
        if self.lines == expected:
            return
        n = next((i for i, (a, b) in enumerate(zip(self.lines, expected))
                  if a != b), min(len(self.lines), len(expected)))
        wrong = sum(a != b for a, b in zip(self.lines, expected)) \
            + abs(len(self.lines) - len(expected))
        got = self.lines[n] if n < len(self.lines) else "nothing"
        exp = expected[n] if n < len(expected) else "nothing"
        self.fail("%s: %d of %d lines differ, first at line %d: found "
                  "\"%s\", expected \"%s\" (record %d, marker %04X)"
                  % (text, wrong, len(expected), n + 1, got, exp,
                     self.index, marker))

    def feed(self, line):
        """Returns False when the simulation shall be stopped."""
        self.active = time.time()
        if line.startswith("S "):
            self.got_serial.append(line)
        elif line.startswith("X "):
            self.close_record()
            self.lines = []
            self.end = line.split()
            self.complete = self.index == len(self.records) - 1
        elif line.startswith("M "):
            self.close_record()
            self.lines = []
            self.index += 1
            if line == "M " + h4(MK_FATAL):
                self.fail("the firmware called FATAL after record %d"
                          % (self.index - 1))
                self.aborted = True
            elif (self.index >= len(self.records) or
                    line != "M " + h4(self.records[self.index][0])):
                exp = "M " + h4(self.records[self.index][0]) \
                    if self.index < len(self.records) else "the end"
                self.fail("unexpected marker \"%s\" instead of \"%s\" after "
                          "record %d (%s)" % (
                              line, exp, self.index - 1,
                              self.records[self.index - 1][1]
                              if self.index > 0 else "none"))
                self.aborted = True
        elif line.startswith(self.PREFIXES):
            self.lines.append(line)
            if 0 <= self.index < len(self.records) and len(self.lines) > \
                    len(self.records[self.index][2]) + self.MAX_EXCESS:
                self.close_record()
                self.fail("stopped: the output of this record does not end")
                self.aborted = True
        elif line.strip():
            self.fail("unexpected output: " + line[:200])
        return not self.aborted

    def finish(self, returncode, errors):
        errors = "\n".join(l for l in errors.split("\n") if l.strip())
        if self.aborted:
            return
        if self.stuck:
            self.close_record()
            self.fail("stopped: %s in record %d of %d (%s)" % (
                self.stuck, self.index + 1, len(self.records),
                self.records[self.index][1] if 0 <= self.index
                < len(self.records) else "none"))
            self.aborted = True
            return
        if self.end is None:
            self.close_record()
            self.fail("the simulation ended without a result (exit code "
                      "%s)%s" % (returncode, ":\n" + errors[-1500:]
                                 if errors else ""))
            return
        if self.end[1] != "END":
            self.fail("the simulation ended with %s after record %d"
                      % (self.end[1], self.index))
        elif not self.complete:
            self.fail("the simulation ended early, after record %d of %d"
                      % (self.index + 1, len(self.records)))
        self.cycles = int(self.end[2]) if len(self.end) > 2 else 0
        if self.got_serial != self.serial:
            self.fail("UART pin: found %s, expected %s"
                      % (" ".join(l[2:] for l in self.got_serial) or
                         "nothing", " ".join(l[2:] for l in self.serial)))
        if returncode != 0 or re.search(r"error|failure", errors, re.I):
            self.fail("ghdl reported (exit code %s):\n%s"
                      % (returncode, errors[-1500:]))


def run(args, ghdl):
    start = time.time()
    test = Test(args)
    for old in glob.glob(os.path.join(HERE, "strrom_sim_job*.???")):
        os.remove(old)

    test.generate()
    output = test.build()
    test.fw = Firmware()
    test.handle_name = {test.fw.sym[name]: name for name in test.model.labels
                        if name in test.fw.sym}
    test.read_static_cases()
    test.distribute()
    # the jobs are part of the firmware: build it again with the final table
    write_fixtures(test.tables_part(), test.strings_part)
    output = test.build()
    fw = Firmware()
    if fw.sym != test.fw.sym:
        raise TestError("the distribution of the jobs moved labels")
    test.fw = fw
    test.static_checks(output)
    facts = test.coverage()

    m = test.model
    print("string ROM: %d of %d characters in %d strings with %d handles; "
          "firmware: %d words" % (m.used, m.size, len(m.units),
                                  len(m.labels), fw.rom_words))
    for fact in facts:
        print("layout: " + fact)
    for note in test.notes:
        print("note: " + note)
    calls = sum(len(case.routines)
                for case in test.static_cases + test.handle_cases)
    print("cases: %d calls of IO$PUTS, LOG_STR and SCR$PRINTSTR for %d "
          "strings%s" % (calls, len(m.labels) + len(test.static_cases),
                         " (--full)" if test.full else ""))
    if not test.table_ok:
        for failure in test.failures:
            print("FAIL: " + failure)
        raise TestError("the handles of the firmware are not the labels of "
                        "the sources: nothing to simulate")
    expected = [test.expected(job) for job in range(test.jobs)]
    for failure in test.failures:
        print("FAIL: " + failure)

    work = tempfile.mkdtemp(prefix="ghdl_strrom_")
    try:
        command, rundir = test.prepare_simulation(ghdl, work)
        print("simulating %d job%s, estimated %s million clock cycles ..."
              % (test.jobs, "s" if test.jobs > 1 else "",
                 " + ".join("%.1f" % (c / 1e6) for c in test.load)))
        sys.stdout.flush()
        with concurrent.futures.ThreadPoolExecutor(args.parallel) as pool:
            futures = [pool.submit(test.run_job, job, expected[job], command,
                                   rundir, work) for job in range(test.jobs)]
            try:
                for future in concurrent.futures.as_completed(futures):
                    check = future.result()
                    if check.aborted:
                        print("job %d: FAILED, stopped at record %d of %d "
                              "after %d s" % (check.job, check.index + 1,
                                              len(check.records),
                                              check.seconds))
                    else:
                        print("job %d: %s, %d records, %d clock cycles in "
                              "%d s" % (check.job, "FAILED" if check.failures
                                        else "ok", len(check.records),
                                        check.cycles, check.seconds))
                    for failure in check.failures:
                        print("FAIL: " + failure)
                    sys.stdout.flush()
                    test.failures += check.failures
            except BaseException:       # for example Ctrl-C
                for proc in test.processes:
                    stop_simulation(proc)
                raise
    finally:
        if args.keep:
            print("work directory: " + work)
        else:
            shutil.rmtree(work, ignore_errors=True)

    print("runtime: %d s" % (time.time() - start))
    return test.failures


def main():
    parser = argparse.ArgumentParser(description="Regression test for the "
                                     "string ROM on simulated hardware")
    # four simulations if the computer has at least eight logical processors
    parser.add_argument("--jobs", type=int,
                        default=max(1, min(4, (os.cpu_count() or 2) // 2)),
                        help="split the test into this amount of simulations "
                        "that run in parallel, 1 to %d (default: %%(default)s)"
                        % MAX_JOBS)
    parser.add_argument("--full", action="store_true",
                        help="run every handle through all three output "
                        "routines (about two and a half times the work)")
    parser.add_argument("--keep", action="store_true",
                        help="keep the work directory of the simulation")
    args = parser.parse_args()
    if not 1 <= args.jobs <= MAX_JOBS:
        parser.error("--jobs needs to be between 1 and %d" % MAX_JOBS)
    args.parallel = args.jobs

    ghdl = shutil.which("ghdl") or (
        "/usr/local/bin/ghdl" if os.path.exists("/usr/local/bin/ghdl") else None)
    if not ghdl:
        print("STRROM SIM TEST: SKIP (ghdl not found)")
        return 0
    try:
        if not os.access(TOOL, os.X_OK) or not os.access(QASM, os.X_OK):
            raise TestError("M2M/tools/asm_strrom.sh or the QNICE assembler "
                            "is missing: build the QNICE toolchain first")
        failures = run(args, ghdl)
    except TestError as error:
        print("FAIL: " + str(error))
        failures = [str(error)]
    if failures:
        print("STRROM SIM TEST FAILED")
        return 1
    print("STRROM SIM TEST OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
