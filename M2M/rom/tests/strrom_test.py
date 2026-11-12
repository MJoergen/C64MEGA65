#!/usr/bin/env python3
"""
Static verification of the string ROM build of the QNICE firmware.

CORE/m2m-rom/make_rom.sh assembles the firmware with M2M/tools/asm_strrom.sh:
the strings between the marker comments ;STRROM_BEGIN and ;STRROM_END are
stored in the string ROM (CORE/m2m-rom/m2m-strings.rom) instead of in the
firmware ROM, and their labels become handles: addresses of table words
between STRROM$TAB and STRROM$TAB_END that hold the position of the string in
the string ROM (see M2M/rom/strrom.asm).

This test runs make_rom.sh and then verifies the artifacts without reusing
anything of asm_strrom.sh. It assembles a reference firmware itself, with all
strings in place (C preprocessor and qasm, exactly like the "asm" wrapper of
QNICE), and checks:

  strings    Each table entry leads to the same zero-terminated string in
             m2m-strings.rom as its label in the reference firmware. The table
             covers every label and every word of every marked section and
             has no entry without a label in the reference firmware.
  transform  The listings of both builds contain the same source lines,
             except for the lines between the markers (removed) and the table
             lines behind ;STRROM_TABLE (added).
  layout     m2m-strings.rom has 2**C_STRROM_ADDR_WIDTH lines (read from
             M2M/vhdl/qnice_wrapper.vhd) of two hexadecimal digits each, no
             string crosses a 4k window, every table position is inside of the
             ROM, everything outside of the strings is zero, and strings only
             overlap where labels point into the same string in the sources.
  handles    Every use of a handle in the firmware reaches a handle-aware
             routine. Simple uses are recognized automatically, all other uses
             need an entry in ALLOWLIST (see the comment above HANDLE_AWARE).

The test does not depend on the awk or the C preprocessor that make_rom.sh
uses: it only reads the final artifacts and the sources, so it proves on
every build machine that the build produced the right files.

Usage:
    python3 strrom_test.py             run make_rom.sh, then verify
    python3 strrom_test.py --no-build  verify the artifacts of the last build
    python3 strrom_test.py --report    run make_rom.sh, verify, and list the
                                       strings that are still part of the
                                       firmware ROM (largest first) together
                                       with the reason why they stay there

The options can be combined. Exit code 0: all checks passed, 1: a check
failed, 2: usage or setup error.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ROMDIR = os.path.join(REPO, "CORE", "m2m-rom")
QASM = os.path.join(REPO, "M2M", "QNICE", "assembler", "qasm")
WRAPPER_VHD = os.path.join(REPO, "M2M", "vhdl", "qnice_wrapper.vhd")

FW_ASM = "m2m-rom.asm"
FW_OUT = os.path.join(ROMDIR, "m2m-rom.out")
FW_LIS = os.path.join(ROMDIR, "m2m-rom.lis")
FW_ROM = os.path.join(ROMDIR, "m2m-rom.rom")
STR_ROM = os.path.join(ROMDIR, "m2m-strings.rom")

WINDOW = 4096                       # size of the 4k MMIO window of QNICE
TIMEOUT = 300                       # seconds for make_rom.sh, cpp and qasm

MARKER = re.compile(r"^[ \t]*;[ \t]*STRROM_(BEGIN|END|TABLE)[ \t]*$")

# ---------------------------------------------------------------------------
# Handle lint
#
# A label between the markers is a handle, not a pointer to characters. Only
# routines that call STRROM$OPEN and STRROM$CLOSE accept a handle as a string
# (HANDLE_AWARE; check_aware_routines verifies that they still do).
#
# A use of a handle is accepted automatically if the label is loaded into R8,
# the following instructions do not touch R8 and do not change the control
# flow, and the next call or jump is an unconditional call of a handle-aware
# routine. After such a call R8 still holds the handle: the instructions that
# follow until R8 is overwritten or the control flow changes must not read R8
# and must not pass it to a routine that needs a pointer (POINTER_ONLY).
#
# Every other use needs an entry in ALLOWLIST. The lint flags arithmetic on a
# handle and a handle in a .DW table with a message of its own; they need an
# ALLOWLIST entry as well (with a proof that the consumer is handle-aware).
#
# The lint works on the source as the assembler sees it, i.e. after the C
# preprocessor: SYSCALL(x, 1) is "ASUB x, 1", RET is "MOVE @R13++, R15" and
# SP is R13. Lines are compared without comments and with normalized blanks.
# ---------------------------------------------------------------------------

HANDLE_AWARE = {
    "puts",             # SYSCALL(puts, 1): jump table entry to IO$PUTS
    "IO$PUTS",          # monitor/io_library_m2m.asm
    "LOG_STR",          # tools.asm
    "SCR$PRINTSTR",     # screen.asm
    "SCR$PRINTSTRXY",   # screen.asm, calls SCR$PRINTSTR
    "FATAL",            # shell.asm, prints with SCR$PRINTSTR and puts
    "FATAL_IDX",        # shell.asm, enters FATAL
}

# Routines that read characters through R8 or use R8 as a buffer pointer.
# Passing a handle in R8 to them is always wrong.
POINTER_ONLY = {
    "strlen", "strcpy", "strcmp", "strchr", "strstr", "strrplchr", "split",
    "str2upper", "chomp", "memcpy", "memset", "gets", "gets_s", "gets_slf",
    "STR$LEN", "STR$CPY", "STR$CMP", "STR$STRCHR", "STR$STRSTR", "STR$RPLCHR",
    "STR$SPLIT", "STR$TO_UPPER", "STR$CHOMP", "MEM$MOVE", "MEM$FILL",
    "M2M$CHK_EXT", "M2M$RPL_S", "OPTM_LIVE_TEXT", "_SS_APPEND_STR",
}

# Code that handles flow through on their way to a handle-aware routine. Each
# pin is a sequence of consecutive code lines that must occur exactly once in
# the given file. If a pin is not found, the code changed: check again that
# every ALLOWLIST entry that names the pin in "via" is still safe, then update
# the pin.
PINS = {
    # FATAL_IDX loads the handle ERR_ITEMIDX into R1. FATAL keeps the message
    # in R0 and the hint in R1 (all called routines switch the register bank)
    # and passes both only to SCR$PRINTSTR and puts.
    "fatal": ("M2M/rom/shell.asm", [
        "FATAL_IDX MOVE ERR_ITEMIDX, R1",
        "RBRA _FATAL_START, 1",
        "FATAL XOR R1, R1",
        "_FATAL_START MOVE R8, R0",
        "RSUB SCR$OSM_OFF, 1",
        "RSUB SCR$OSM_M_ON, 1",
        "RSUB SCR$CLR, 1",
        "MOVE SCR$ILX, R8",
        "MOVE 1, @R8",
        "MOVE ERR_FATAL, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "MOVE R0, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "CMP 0, R1",
        "RBRA _FATAL_CODE, Z",
        "MOVE R1, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "_FATAL_CODE CMP 0, R9",
        "RBRA _FATAL_END, Z",
        "MOVE ERR_CODE, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "MOVE R9, R8",
        "MOVE SCRATCH_HEX, R9",
        "RSUB WORD2HEXSTR, 1",
        "MOVE R9, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "_FATAL_END MOVE NEWLINE, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB crlf, 1",
        "MOVE ERR_FATAL_STOP, R8",
        "RSUB SCR$PRINTSTR, 1",
        "ASUB puts, 1",
        "ASUB exit, 1",
    ]),
    # The jump table entry of SYSCALL(puts, 1)
    "puts": ("M2M/rom/monitor/qmon_m2m.asm", [
        "puts! RBRA IO$PUTS, 1",
    ]),
    # Targets of branches that carry a handle in R8 to FATAL_IDX or puts
    "hlp_ca_ncf": ("M2M/rom/options.asm", [
        "_HLP_CA_NCF ASUB puts, 1",
    ]),
    "hlp_depfat": ("M2M/rom/options.asm", [
        "_HLP_DEPFAT MOVE R0, R9",
        "RBRA FATAL_IDX, 1",
    ]),
    # The menu calls the function pointer number OPTM_CLBK_FATAL of its init
    # record without touching R8; check_menu_fatal verifies that this
    # function pointer is FATAL.
    "optm_call": ("M2M/rom/menu.asm", [
        "_OPTM_CALL MOVE R7, @--R13",
        "MOVE OPTM_DATA, R7",
        "MOVE @R7, R7",
        "ADD @R13, R7",
        "MOVE @R7, R7",
        "ASUB R7, 1",
        "MOVE @R13++, R7",
        "MOVE @R13++, R15",
    ]),
    # _JD_RPT_LINE passes the label in R8 to puts, and the file name in R10
    # (via R1) to puts as well.
    "jd_rpt_line": ("CORE/m2m-rom/m2m-rom.asm", [
        "_JD_RPT_LINE INCRB",
        "MOVE R9, R0",
        "MOVE R10, R1",
        "ASUB puts, 1",
        "CMP 0, R0",
        "RBRA _JD_RPT_STD, Z",
        "MOVE JDS_V_JIFFY, R8",
        "ASUB puts, 1",
        "RBRA _JD_RPT_RET, 1",
        "_JD_RPT_STD MOVE JDS_STD_PRE, R8",
        "ASUB puts, 1",
        "MOVE R1, R8",
        "ASUB puts, 1",
        "MOVE JDS_STD_SUF, R8",
        "ASUB puts, 1",
        "_JD_RPT_RET DECRB",
        "MOVE @R13++, R15",
    ]),
    # _JD_REVERT keeps the reason in R0 and passes it only to puts.
    "jd_revert": ("CORE/m2m-rom/m2m-rom.asm", [
        "_JD_REVERT MOVE R8, R0",
        "MOVE JDS_V_DIS_PRE, R8",
        "ASUB puts, 1",
        "MOVE R0, R8",
        "ASUB puts, 1",
        "MOVE JDS_V_DIS_SUF, R8",
        "ASUB puts, 1",
        "MOVE C64_OSM_KERNAL_JIFFY, R8",
    ]),
    # PREP_LOAD_IMAGE returns its message in R9. Its only caller LOAD_IMAGE
    # keeps it in R7 and returns it in R9 (via the stack, over the "leave
    # hump").
    "prep_li_ret": ("CORE/m2m-rom/m2m-rom.asm", [
        "_PREP_LI_RET DECRB",
        "MOVE @R13++, R15",
    ]),
    "load_image": ("M2M/rom/shell.asm", [
        "RSUB PREP_LOAD_IMAGE, 1",
        "MOVE R8, R6",
        "MOVE R9, R7",
        "CMP 0, R6",
        "RBRA _LI_FREAD_RET, !Z",
    ]),
    "load_image_ret": ("M2M/rom/shell.asm", [
        "_LI_FREAD_RET MOVE R6, @--R13",
        "MOVE R7, @--R13",
        "ASUB leave, 1",
        "MOVE @R13++, R9",
        "MOVE @R13++, R8",
        "MOVE @R13++, R15",
    ]),
    # The only caller of LOAD_IMAGE prints its message (R9, kept in R1). Only
    # an error string of the CRT/ROM device (address >= M2M$RAMROM_DATA) is
    # copied with strlen and strcpy; handles are below 0x7000 and go directly
    # to SCR$PRINTSTR. SCR$CLRINNER does not touch R8 and R9 (see
    # check_aware_routines).
    "handle_mounting": ("M2M/rom/shell.asm", [
        "RSUB LOAD_IMAGE, 1",
        "CMP 0, R8",
        "RBRA _HM_SDMOUNTED6A, Z",
        "RSUB SCR$CLRINNER, 1",
        "MOVE R8, R0",
        "MOVE R9, R1",
        "MOVE ERR_CODE, R8",
        "RSUB SCR$PRINTSTR, 1",
        "MOVE R0, R8",
        "MOVE SCRATCH_HEX, R9",
        "RSUB WORD2HEXSTR, 1",
        "MOVE R9, R8",
        "RSUB SCR$PRINTSTR, 1",
        "CMP 0, R1",
        "RBRA _HM_SDMOUNTED5A, Z",
        "MOVE NEWLINE, R8",
        "RSUB SCR$PRINTSTR, 1",
        "CMP 1, R5",
        "RBRA _HM_SDMOUNTED5S, !Z",
        "CMP M2M$RAMROM_DATA, R1",
        "RBRA _HM_SDMOUNTED5S, N",
    ]),
    "handle_mounting_print": ("M2M/rom/shell.asm", [
        "_HM_SDMOUNTED5S MOVE R1, R8",
        "RSUB SCR$PRINTSTR, 1",
    ]),
    # The only caller of CUSTOM_MSG prints the returned message after
    # SCR$CLRINNER, which does not touch R8 (see check_aware_routines).
    "custom_msg_caller": ("M2M/rom/selectfile.asm", [
        "RSUB CUSTOM_MSG, 1",
        "CMP 0, R8",
        "RBRA _S_NOTHING_1, !Z",
        "MOVE WRN_EMPTY_BRW, R8",
        "_S_NOTHING_1 RSUB SCR$CLRINNER, 1",
        "RSUB SCR$PRINTSTR, 1",
    ]),
}

# Uses of handles that are not simple and that have been proven safe by hand.
# "context" are the code lines around the line that uses the label (the first
# context line that names the label), up to the point where the handle
# reaches a handle-aware routine or where the pins in "via" take over. A use
# that matches no entry fails the test, and so does an entry that matches no
# use, so that the list stays exact.
ALLOWLIST = [
    # FATAL_IDX keeps its hint in R1
    dict(file="M2M/rom/shell.asm", label="ERR_ITEMIDX", via=["fatal"],
         context=["FATAL_IDX MOVE ERR_ITEMIDX, R1",
                  "RBRA _FATAL_START, 1"]),

    # A corrupt config file shares the output with the "no config file" case
    dict(file="M2M/rom/options.asm", label="LOG_STR_CFG_E4",
         via=["hlp_ca_ncf"],
         context=["_HLP_CA_CCF MOVE LOG_STR_CFG_E4, R8",
                  "RBRA _HLP_CA_NCF, 1"]),

    # config.vhd sanity checks: the chain of conditional branches only selects
    # the message, every path ends in FATAL_IDX (the last message of the
    # chain, ERR_F_DEPSPECIAL, falls through to FATAL_IDX and is simple)
    dict(file="M2M/rom/options.asm", label="ERR_F_DEPMOTHER",
         via=["hlp_depfat", "fatal"],
         context=["MOVE ERR_F_DEPMOTHER, R8",
                  "CMP 0, R1",
                  "RBRA _HLP_DEPFAT, Z",
                  "MOVE ERR_F_DEPIDX, R8"]),
    dict(file="M2M/rom/options.asm", label="ERR_F_DEPIDX",
         via=["hlp_depfat", "fatal"],
         context=["MOVE ERR_F_DEPIDX, R8",
                  "CMP 1, R1",
                  "RBRA _HLP_DEPFAT, Z",
                  "MOVE ERR_F_DEPMIX, R8"]),
    dict(file="M2M/rom/options.asm", label="ERR_F_DEPMIX",
         via=["hlp_depfat", "fatal"],
         context=["MOVE ERR_F_DEPMIX, R8",
                  "CMP 2, R1",
                  "RBRA _HLP_DEPFAT, Z",
                  "MOVE ERR_F_DEPCHAIN, R8"]),
    dict(file="M2M/rom/options.asm", label="ERR_F_DEPCHAIN",
         via=["hlp_depfat", "fatal"],
         context=["MOVE ERR_F_DEPCHAIN, R8",
                  "CMP 3, R1",
                  "RBRA _HLP_DEPFAT, Z",
                  "MOVE ERR_F_DEPSPECIAL, R8"]),

    # Fatal errors of the menu go to the function pointer OPTM_CLBK_FATAL of
    # the init record, which is FATAL; R9 carries the error code
    dict(file="M2M/rom/menu.asm", label="OPTM_F_NOSEL", via=["optm_call"],
         context=["_OPTM_RUN_SM_3 MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_NOSEL, R8",
                  "XOR R9, R9",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MENUIDX", via=["optm_call"],
         context=["_OPTM_R_FATAL MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE R8, R9",
                  "MOVE OPTM_F_MENUIDX, R8",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MENUGRP2", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_MENUGRP2, R8",
                  "XOR R9, R9",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MENUGRP", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_MENUGRP, R8",
                  "MOVE R3, R9",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MENUGRP3", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_MENUGRP3, R8",
                  "MOVE R12, R9",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MENUSUB", via=["optm_call"],
         context=["_OPTM_STRUCT_F MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE R10, R9",
                  "MOVE OPTM_F_MENUSUB, R8",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_F2M", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_F2M, R8",
                  "MOVE R2, R9",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MSTRUCT", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_MSTRUCT, R8",
                  "RBRA _OPTM_CALL, 1"]),
    dict(file="M2M/rom/menu.asm", label="OPTM_F_MSTRUCT", via=["optm_call"],
         context=["MOVE OPTM_CLBK_FATAL, R7",
                  "MOVE OPTM_F_MSTRUCT, R8",
                  "MOVE OPTM_F_MS_SELF, R9",
                  "RBRA _OPTM_CALL, 1"]),

    # The standard message for an empty file browser is printed like the
    # custom message of CUSTOM_MSG
    dict(file="M2M/rom/selectfile.asm", label="WRN_EMPTY_BRW",
         via=["custom_msg_caller"],
         context=["MOVE WRN_EMPTY_BRW, R8",
                  "_S_NOTHING_1 RSUB SCR$CLRINNER, 1",
                  "RSUB SCR$PRINTSTR, 1"]),

    # CUSTOM_MSG returns its message in R8 to its only caller
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="WRN_NO_D64",
         via=["custom_msg_caller"],
         context=["MOVE WRN_NO_D64, R8",
                  "_CUSTOM_MSG_RET DECRB",
                  "MOVE @R13++, R15"]),

    # PREP_LOAD_IMAGE returns its message in R9 to LOAD_IMAGE, which returns
    # it to HANDLE_MOUNTING
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="WRN_CRT_TOO_BIG",
         via=["prep_li_ret", "load_image", "load_image_ret",
              "handle_mounting", "handle_mounting_print"],
         context=["_PREP_LI_CRT_BIG MOVE 1, R8",
                  "MOVE WRN_CRT_TOO_BIG, R9",
                  "RBRA _PREP_LI_RET, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="WRN_WRONG_IMG",
         via=["prep_li_ret", "load_image", "load_image_ret",
              "handle_mounting", "handle_mounting_print"],
         context=["_PREP_LI_WRONG MOVE 1, R8",
                  "MOVE WRN_WRONG_IMG, R9",
                  "RBRA _PREP_LI_RET, 1"]),

    # JiffyDOS status report: the labels go in R8 and the file names in R10
    # to _JD_RPT_LINE; the reasons go in R8 to _JD_REVERT
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_L_C64",
         via=["jd_rpt_line"],
         context=["MOVE JDS_L_C64, R8",
                  "MOVE @R0, R9",
                  "MOVE JDS_F_C64, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_F_C64",
         via=["jd_rpt_line"],
         context=["MOVE JDS_F_C64, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_L_1541",
         via=["jd_rpt_line"],
         context=["MOVE JDS_L_1541, R8",
                  "MOVE @R0, R9",
                  "MOVE JDS_F_1541, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_F_1541",
         via=["jd_rpt_line"],
         context=["MOVE JDS_F_1541, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_L_1581",
         via=["jd_rpt_line"],
         context=["MOVE JDS_L_1581, R8",
                  "MOVE @R0, R9",
                  "MOVE JDS_F_1581, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_F_1581",
         via=["jd_rpt_line"],
         context=["MOVE JDS_F_1581, R10",
                  "RSUB _JD_RPT_LINE, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_R_NOC64",
         via=["jd_revert"],
         context=["MOVE JDS_R_NOC64, R8",
                  "RBRA _JD_REVERT, 1"]),
    dict(file="CORE/m2m-rom/m2m-rom.asm", label="JDS_R_NODRV",
         via=["jd_revert"],
         context=["_JD_NODRV MOVE JDS_R_NODRV, R8",
                  "_JD_REVERT MOVE R8, R0"]),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


class SetupError(Exception):
    pass


def rel(path):
    return os.path.relpath(path, REPO)


def strip_comment(text):
    """Removes a comment the way qasm does: a ";" starts a comment unless a
    double quote stands in front of it."""
    p = text.find(";")
    q = text.find('"')
    if p >= 0 and (q < 0 or p < q):
        return text[:p]
    return text


def norm(text):
    """A code line without comment and with normalized blanks; "" if the line
    contains no code."""
    t = strip_comment(text.rstrip("\r\n"))
    if t.lstrip().startswith((".ASCII_W", ".ASCII_P")) or '"' in t:
        return " ".join(t.split())
    t = re.sub(r"\s*,\s*", ", ", t)
    return " ".join(t.split())


def parse_code(text):
    """(label, MNEMONIC, [operands]) of a source line; mnemonic "" for lines
    without an instruction."""
    t = strip_comment(text.rstrip("\r\n")).rstrip()
    label = ""
    if t and t[0] not in " \t":
        parts = t.split(None, 1)
        label = parts[0]
        t = parts[1] if len(parts) > 1 else ""
    parts = t.split(None, 1)
    if not parts:
        return label, "", []
    mn = parts[0].upper()
    if mn in (".ASCII_W", ".ASCII_P"):
        return label, mn, [parts[1] if len(parts) > 1 else ""]
    ops = [o.strip() for o in parts[1].split(",")] if len(parts) > 1 else []
    return label, mn, ops


R8_RE = re.compile(r"(?<![A-Za-z0-9_$])R8(?![A-Za-z0-9_$])", re.I)
IDENT_RE = re.compile(r"[A-Za-z_$][A-Za-z0-9_$!]*")
JUMPS = ("RBRA", "ABRA", "RSUB", "ASUB")
ARITH = ("ADD", "ADDC", "SUB", "SUBC", "AND", "OR", "XOR", "NOT", "SHL",
         "SHR", "SWAP")


def mentions_r8(ops):
    return any(R8_RE.search(o) for o in ops)


def writes_r8_only(mn, ops):
    if len(ops) != 2:
        return False
    if mn in ("MOVE", "NOT", "SWAP"):
        return ops[1].upper() == "R8" and not R8_RE.search(ops[0])
    if mn in ("XOR", "SUB"):
        return ops[0].upper() == "R8" and ops[1].upper() == "R8"
    return False


def is_control(mn, ops):
    return (mn in JUMPS or mn in ("HALT", "RTI", "INT")
            or (len(ops) == 2 and ops[1].upper() in ("R15", "PC")))


def is_aware_call(mn, ops):
    return (mn in JUMPS and len(ops) == 2 and ops[0] in HANDLE_AWARE
            and ops[1] == "1")


def zstring(mem, addr, limit):
    """Words from addr up to and including the zero terminator, or None if
    there is no terminator below limit."""
    out = []
    while addr < limit:
        v = mem.get(addr) if isinstance(mem, dict) else mem[addr]
        if v is None:
            return None
        out.append(v)
        if v == 0:
            return out
        addr += 1
    return None


def show(words):
    s = []
    for v in words:
        if v == 0:
            break
        s.append(chr(v) if 32 <= v < 127 else "\\x%02X" % v)
    return '"' + "".join(s) + '"'


def run(cmd, cwd, env=None):
    try:
        return subprocess.run(cmd, cwd=cwd, env=env, stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        raise SetupError("%s timed out after %d s" % (" ".join(cmd), TIMEOUT))
    except OSError as e:
        raise SetupError("cannot run %s: %s" % (cmd[0], e))


def decode(b):
    return b.decode("latin-1")


def lines_of(text):
    """Lines separated by LF only (like qasm and cpp; str.splitlines() would
    also split at form feeds and other control characters)."""
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [l[:-1] if l.endswith("\r") else l for l in lines]


# ---------------------------------------------------------------------------
# Reading the artifacts
# ---------------------------------------------------------------------------


def read_out(path):
    """Words of a qasm .out file as {address: value}."""
    mem = {}
    with open(path, "rb") as f:
        for n, line in enumerate(lines_of(decode(f.read())), 1):
            m = re.match(r"^0x([0-9A-Fa-f]{4}) 0x([0-9A-Fa-f]{4})\s*$", line)
            if not m:
                raise SetupError("%s line %d is not \"0xADDR 0xVALUE\": %r"
                                 % (rel(path), n, line))
            a, v = int(m.group(1), 16), int(m.group(2), 16)
            if a in mem:
                raise SetupError("%s: address 0x%04X occurs twice"
                                 % (rel(path), a))
            mem[a] = v
    return mem


class Listing:
    """A qasm listing: the source lines as the assembler saw them, the words
    that each line emitted, and the EQU and label lists."""

    def __init__(self, path):
        self.path = path
        self.lines = []          # [(text, [addresses of emitted words])]
        self.labels = {}
        self.equs = {}
        section = "src"
        with open(path, "rb") as f:
            raw = lines_of(decode(f.read()))
        for line in raw:
            if line.startswith("EQU-list:"):
                section = "equ"
                continue
            if line.startswith("Label-list:"):
                section = "lab"
                continue
            if line.startswith("The following names appear"):
                section = "dup"
                continue
            if section == "src":
                if (len(line) >= 26 and line[:6].isdigit()
                        and line[6:8] == "  "):
                    words = []
                    addr, data, second = line[8:12], line[14:18], line[20:24]
                    if addr.strip() and data.strip():
                        a = int(addr, 16)
                        words.append(a)
                        if second.strip():
                            words.append(a + 1)
                    self.lines.append((line[26:], words))
                elif re.match(r"^        [0-9A-F]{4}  [0-9A-F]{4}$", line):
                    if self.lines:
                        self.lines[-1][1].append(int(line[8:12], 16))
                elif len(line) >= 6 and line[:6].isdigit():
                    # a source line without any text (shorter than 26)
                    self.lines.append(("", []))
                # anything else is an error or warning text of qasm
            elif section in ("equ", "lab"):
                for name, val in re.findall(r"(\S+)\s*: 0x([0-9A-Fa-f]{4})",
                                            line):
                    (self.equs if section == "equ" else self.labels)[name] = \
                        int(val, 16)
        if not self.labels:
            raise SetupError("%s has no label list" % rel(path))


class Source:
    """The firmware source after the C preprocessor, with the file and line
    of every line (from the line markers of the preprocessor)."""

    def __init__(self, cpp_output):
        self.text = []
        self.where = []
        cur_file, cur_line = FW_ASM, 1
        for line in lines_of(cpp_output):
            if line.startswith("#"):
                m = re.match(r'^#\s*(?:line\s+)?(\d+)\s+"([^"]*)"', line)
                if m:
                    cur_line = int(m.group(1))
                    cur_file = m.group(2)
                continue
            self.text.append(line)
            self.where.append((cur_file, cur_line))
            cur_line += 1
        self.relname = {}
        for f in {f for f, _ in self.where}:
            p = os.path.normpath(os.path.join(ROMDIR, f))
            self.relname[f] = rel(p) if os.path.exists(p) else f

    def file_of(self, i):
        return self.relname[self.where[i][0]]

    def loc(self, i):
        f, n = self.where[i]
        return "%s:%d" % (self.relname[f], n)


def marked_regions(texts):
    """Indices of the lines between the markers, the indices of the marker
    lines, and a list of problems with the marker structure."""
    marked, markers, problems = set(), [], []
    inside = False
    for i, t in enumerate(texts):
        m = MARKER.match(t)
        if m:
            markers.append((i, m.group(1)))
            if m.group(1) == "BEGIN":
                if inside:
                    problems.append("STRROM_BEGIN twice in line %d" % (i + 1))
                inside = True
            elif m.group(1) == "END":
                if not inside:
                    problems.append("STRROM_END without STRROM_BEGIN in line "
                                    "%d" % (i + 1))
                inside = False
            continue
        if inside:
            marked.add(i)
    if inside:
        problems.append("STRROM_BEGIN without STRROM_END")
    return marked, markers, problems


def defined_label(text):
    """The label defined in column 1 of a line, without the export mark."""
    if text and text[0] not in " \t;":
        lab = re.split(r"[ \t;]", text, 1)[0]
        return lab[:-1] if lab.endswith("!") else lab
    return ""


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------


def no_clipboard_env(tmp):
    """make_rom.sh offers its result on the clipboard: replace the clipboard
    tools by no-ops for the test."""
    bindir = os.path.join(tmp, "bin")
    os.mkdir(bindir)
    for tool in ("pbcopy", "xclip"):
        p = os.path.join(bindir, tool)
        with open(p, "w") as f:
            f.write("#!/bin/sh\ncat > /dev/null\nexit 0\n")
        os.chmod(p, 0o755)
    env = dict(os.environ)
    env["PATH"] = bindir + os.pathsep + env.get("PATH", "")
    return env


def build(tmp):
    print("Running CORE/m2m-rom/make_rom.sh ...")
    start = time.time() - 2
    r = run(["bash", "make_rom.sh"], ROMDIR, no_clipboard_env(tmp))
    out = decode(r.stdout)
    summary = [l for l in out.splitlines()
               if l.startswith(("String ROM:", "Shell ROM:"))]
    for l in summary:
        print("  " + l)
    if r.returncode != 0 or len(summary) != 2:
        sys.stdout.write(out + decode(r.stderr))
        raise SetupError("make_rom.sh failed (exit code %d)" % r.returncode)
    for p in (FW_OUT, FW_LIS, FW_ROM, STR_ROM):
        if not os.path.exists(p) or os.path.getmtime(p) < start:
            raise SetupError("make_rom.sh did not write %s" % rel(p))


def reference_build(tmp):
    """Assembles the firmware with the strings in place, like the "asm"
    wrapper of QNICE: C preprocessor, delete the lines that start with "#",
    qasm. Returns the Source and the reference Listing and words."""
    cpp = shutil.which("cc") or shutil.which("gcc")
    if not cpp:
        raise SetupError("neither cc nor gcc found (C preprocessor)")
    if not os.access(QASM, os.X_OK):
        raise SetupError("%s not found; build the QNICE toolchain first"
                         % rel(QASM))
    r = run([cpp, "-xc", "-E", FW_ASM], ROMDIR)
    if r.returncode != 0:
        sys.stdout.write(decode(r.stderr))
        raise SetupError("the C preprocessor failed on %s" % FW_ASM)
    src = Source(decode(r.stdout))
    asm = os.path.join(tmp, "ref.asm")
    with open(asm, "w", encoding="latin-1", newline="\n") as f:
        for t in src.text:
            f.write(t + "\n")
    out = os.path.join(tmp, "ref.out")
    r = run([QASM, asm, out], tmp)
    lis = os.path.join(tmp, "ref.lis")
    if r.returncode != 0 or not os.path.exists(out):
        sys.stdout.write(decode(r.stdout))
        raise SetupError("the reference build (qasm) failed")
    return src, Listing(lis), read_out(out)


def strrom_size():
    with open(WRAPPER_VHD, "rb") as f:
        m = re.search(r"^[ \t]*constant\s+C_STRROM_ADDR_WIDTH\s*:\s*natural"
                      r"\s*:=\s*(\d+)\s*;", decode(f.read()), re.I | re.M)
    if not m:
        raise SetupError("C_STRROM_ADDR_WIDTH not found in %s"
                         % rel(WRAPPER_VHD))
    return 1 << int(m.group(1))


def read_strrom(size, errors):
    with open(STR_ROM, "rb") as f:
        data = decode(f.read())
    if "\r" in data:
        errors.append("m2m-strings.rom contains CR characters")
    lines = data.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    else:
        errors.append("m2m-strings.rom does not end with a newline")
    if len(lines) != size:
        errors.append("m2m-strings.rom has %d lines, but the string ROM in "
                      "qnice_wrapper.vhd has 2**C_STRROM_ADDR_WIDTH = %d "
                      "characters" % (len(lines), size))
    rom = []
    for n, l in enumerate(lines, 1):
        if not re.match(r"^[0-9A-Fa-f]{2}$", l.rstrip("\r")):
            errors.append("m2m-strings.rom line %d is not two hexadecimal "
                          "digits: %r" % (n, l))
            return None
        rom.append(int(l[:2], 16))
    return rom


# ---------------------------------------------------------------------------
# The checks
# ---------------------------------------------------------------------------


class Build:
    """Everything the checks need, read once."""

    def __init__(self, tmp):
        self.src, self.ref, self.ref_mem = reference_build(tmp)
        self.new = Listing(FW_LIS)
        self.new_mem = read_out(FW_OUT)
        self.size = strrom_size()
        self.rom_errors = []
        self.rom = read_strrom(self.size, self.rom_errors)

        # marked sections, from the source as the assembler saw it
        texts = [t for t, _ in self.ref.lines]
        self.marked, self.markers, self.marker_problems = \
            marked_regions(texts)
        self.has_table = any(k == "TABLE" for _, k in self.markers)
        self.marked_labels = []
        self.marked_words = set()
        for i in sorted(self.marked):
            lab = defined_label(texts[i])
            if lab:
                self.marked_labels.append(lab)
            self.marked_words.update(self.ref.lines[i][1])

        # the table of the string ROM build
        lab = self.new.labels
        self.table = {}                  # label -> address of its table word
        self.table_problems = []
        if "STRROM$TAB" not in lab or "STRROM$TAB_END" not in lab:
            self.table_problems.append("STRROM$TAB or STRROM$TAB_END is "
                                       "missing in m2m-rom.lis")
            self.tab = self.tab_end = 0
        else:
            self.tab, self.tab_end = lab["STRROM$TAB"], lab["STRROM$TAB_END"]
            at = {}
            for name, a in lab.items():
                if self.tab <= a < self.tab_end and name != "STRROM$TAB":
                    at.setdefault(a, []).append(name)
            for a in range(self.tab, self.tab_end):
                names = at.get(a, [])
                if len(names) != 1:
                    self.table_problems.append(
                        "table word 0x%04X has %d labels: %s"
                        % (a, len(names), ", ".join(names) or "none"))
                for name in names:
                    self.table[name] = a
        self.pos = {l: self.new_mem.get(a) for l, a in self.table.items()}


def check_strings(b):
    """(a) Every table entry leads to the same string as in the reference
    build, and the table covers the marked sections completely."""
    errors = list(b.marker_problems) + list(b.table_problems)
    if b.rom is None:
        return errors + b.rom_errors
    if not b.has_table:
        if b.table:
            errors.append("the table is not empty, but the source has no "
                          ";STRROM_TABLE marker")
        return errors
    if len(set(b.marked_labels)) != len(b.marked_labels):
        errors.append("a label occurs twice between the markers")
    missing = [l for l in b.marked_labels if l not in b.table]
    extra = [l for l in b.table if l not in set(b.marked_labels)]
    for l in missing:
        errors.append("label %s between the markers has no table entry" % l)
    for l in extra:
        if l not in b.ref.labels:
            errors.append("table entry %s has no label in the reference "
                          "build" % l)
        else:
            errors.append("table entry %s is not a label between the "
                          "markers" % l)
    covered = set()
    for l, a in sorted(b.table.items(), key=lambda x: x[1]):
        p = b.pos.get(l)
        if p is None:
            errors.append("table word of %s (0x%04X) is not in m2m-rom.out"
                          % (l, a))
            continue
        if l not in b.ref.labels:
            continue
        ra = b.ref.labels[l]
        want = zstring(b.ref_mem, ra, 0x10000)
        if p >= len(b.rom):
            errors.append("%s: position 0x%04X is outside of the string ROM"
                          % (l, p))
            continue
        got = zstring(b.rom, p, len(b.rom))
        if want is None:
            errors.append("%s: no zero-terminated string at 0x%04X in the "
                          "reference build" % (l, ra))
            continue
        covered.update(range(ra, ra + len(want)))
        if got != want:
            errors.append("%s: the string ROM holds %s at 0x%04X, the "
                          "reference build %s"
                          % (l, show(got or []), p, show(want)))
    uncovered = sorted(b.marked_words - covered)
    if uncovered:
        errors.append("%d words of the marked sections are not reachable "
                      "through any table entry, the first at 0x%04X of the "
                      "reference build" % (len(uncovered), uncovered[0]))
    return errors


def check_transform(b):
    """(b) The firmware source of the string ROM build is the reference
    source without the marked lines and with the table lines."""
    errors = []
    # without a table marker the strings stay where they are
    ref = [t for i, (t, _) in enumerate(b.ref.lines)
           if i not in b.marked or not b.has_table]
    new = [t for t, _ in b.new.lines]
    table_at = [k for k, t in enumerate(ref) if MARKER.match(t)
                and MARKER.match(t).group(1) == "TABLE"]
    if len(table_at) > 1:
        return ["the source contains %d ;STRROM_TABLE markers"
                % len(table_at)]
    n_tab = len(b.table) if table_at else 0
    if len(new) != len(ref) + n_tab:
        errors.append("m2m-rom.lis has %d source lines, expected %d (%d "
                      "reference lines without the %d moved lines, plus "
                      "%d table lines)"
                      % (len(new), len(ref) + n_tab, len(b.ref.lines),
                         len(b.ref.lines) - len(ref), n_tab))
    cut = table_at[0] + 1 if table_at else len(ref)
    for k in range(min(cut, len(new))):
        if new[k] != ref[k]:
            return errors + ["first difference in line %d of m2m-rom.lis: "
                             "%r, expected %r" % (k + 1, new[k], ref[k])]
    if table_at:
        order = [l for l in b.marked_labels]
        for k, l in enumerate(order):
            if cut + k >= len(new):
                return errors + ["m2m-rom.lis ends inside of the table"]
            got = new[cut + k].split()
            want = [l, ".DW", "0x%04X" % (b.pos.get(l) or 0)]
            if len(got) == 3 and re.match(r"^0x[0-9A-Fa-f]+$", got[2]):
                got[1:] = [got[1].upper(), "0x%04X" % int(got[2], 16)]
            if got != want:
                return errors + ["table line %d of m2m-rom.lis is %r, "
                                 "expected %r" % (cut + k + 1, new[cut + k],
                                                  " ".join(want))]
    for k in range(cut, len(ref)):
        if k + n_tab >= len(new):
            break
        if new[k + n_tab] != ref[k]:
            return errors + ["first difference in line %d of m2m-rom.lis: "
                             "%r, expected %r" % (k + n_tab + 1,
                                                  new[k + n_tab], ref[k])]
    return errors


def check_layout(b):
    """(c) Size and layout of m2m-strings.rom."""
    errors = list(b.rom_errors)
    if b.rom is None:
        return errors
    rom = b.rom
    used = set()
    term = {}                         # label -> position of its terminator
    for l, p in b.pos.items():
        if p is None or p >= len(rom):
            errors.append("%s: position %s is outside of the string ROM "
                          "(%d characters)" % (l, p, len(rom)))
            continue
        s = zstring(rom, p, len(rom))
        if s is None:
            errors.append("%s: the string at 0x%04X has no zero terminator"
                          % (l, p))
            continue
        end = p + len(s) - 1
        term[l] = end
        if p // WINDOW != end // WINDOW:
            errors.append("%s: the string at 0x%04X..0x%04X crosses a 4k "
                          "window boundary" % (l, p, end))
        used.update(range(p, end + 1))
    junk = [a for a in range(len(rom)) if rom[a] != 0 and a not in used]
    if junk:
        errors.append("%d nonzero characters of m2m-strings.rom are not part "
                      "of any string, the first at 0x%04X"
                      % (len(junk), junk[0]))
    # strings that share a terminator overlap; that is only allowed where the
    # labels share a string in the sources, at the same distance
    by_term = {}
    for l, e in term.items():
        by_term.setdefault(e, []).append(l)
    for e, ls in by_term.items():
        if len(ls) < 2:
            continue
        ra = [b.ref.labels.get(l) for l in ls]
        if None in ra:
            continue
        rterm = set()
        for l in ls:
            s = zstring(b.ref_mem, b.ref.labels[l], 0x10000)
            rterm.add(b.ref.labels[l] + len(s) - 1 if s else None)
        dist_ok = all(b.pos[l] - b.ref.labels[l] == b.pos[ls[0]]
                      - b.ref.labels[ls[0]] for l in ls)
        if len(rterm) != 1 or not dist_ok:
            errors.append("the strings of %s overlap in the string ROM but "
                          "not in the sources" % ", ".join(sorted(ls)))
    if not b.has_table and any(rom):
        errors.append("there is no ;STRROM_TABLE marker, but m2m-strings.rom "
                      "is not all zero")
    return errors


# --- handle lint ------------------------------------------------------------


def uses_of(b, labels):
    """Every line outside of the marked sections that references one of the
    labels as an operand: [(line index, label)]."""
    texts = b.src.text
    marked, _, _ = marked_regions(texts)
    labels = set(labels)
    uses = []
    for i, t in enumerate(texts):
        if i in marked:
            continue
        code = strip_comment(t)
        if '"' in code:
            code = code[:code.find('"')]
        toks = IDENT_RE.findall(code)
        if code and code[0] not in " \t" and toks:
            toks = toks[1:]               # the label defined in column 1
        for tok in toks:
            if tok in labels:
                uses.append((i, tok))
    return uses


def code_lines(texts, i, step):
    """Normalized code lines from line i on (step = 1) or before line i
    (step = -1), skipping lines without code."""
    j = i
    while 0 <= j < len(texts):
        n = norm(texts[j])
        if n:
            yield j, n
        j += step


def simple_use(texts, i, label):
    """None if the use of label in line i is the simple pattern, otherwise
    the reason why it is not."""
    _, mn, ops = parse_code(texts[i])
    if mn == ".DW":
        return "the label is used as a .DW table entry"
    if mn in ARITH:
        return "arithmetic on the label (%s)" % mn
    if not (mn == "MOVE" and len(ops) == 2 and ops[0] == label
            and ops[1].upper() == "R8"):
        return "the label is not loaded into R8 (\"%s\")" % norm(texts[i])
    consumer = None
    for j, n in code_lines(texts, i + 1, 1):
        _, mn, ops = parse_code(texts[j])
        if mn == "":
            continue
        if is_aware_call(mn, ops):
            if mn in ("RBRA", "ABRA"):
                return None
            consumer = ops[0]
            continue
        if consumer is None:
            if mentions_r8(ops) or is_control(mn, ops) or mn.startswith("."):
                return ("R8 reaches \"%s\" before a handle-aware routine"
                        % n)
            continue
        if writes_r8_only(mn, ops):
            return None
        if mentions_r8(ops):
            return ("after %s, R8 still holds the label and \"%s\" reads it"
                    % (consumer, n))
        if mn in JUMPS and ops and ops[0] in POINTER_ONLY:
            return ("after %s, R8 still holds the label and goes to the "
                    "pointer-only routine %s" % (consumer, ops[0]))
        if is_control(mn, ops) or mn.startswith("."):
            return None
    return "the source ends after the use"


def find_pin(b, name):
    """Indices of the occurrences of a pin in the file it names."""
    fname, lines = PINS[name]
    idx = [i for i in range(len(b.src.text)) if b.src.file_of(i) == fname
           and norm(b.src.text[i])]
    seq = [norm(b.src.text[i]) for i in idx]
    hits = []
    for k in range(len(seq) - len(lines) + 1):
        if seq[k:k + len(lines)] == lines:
            hits.append(idx[k])
    return hits


def entry_matches(b, i, label, entry):
    texts = b.src.text
    if b.src.file_of(i) != entry["file"] or label != entry["label"]:
        return False
    ctx = entry["context"]
    k = [n for n, c in enumerate(ctx)
         if label in IDENT_RE.findall(strip_comment(c))]
    if not k:
        return False
    k = k[0]
    after = [n for _, n in code_lines(texts, i, 1)][:len(ctx) - k]
    before = [n for _, n in code_lines(texts, i - 1, -1)][:k]
    return before[::-1] + after == ctx


def check_aware_routines(b):
    """The routines in HANDLE_AWARE really accept handles."""
    errors = []
    texts = b.src.text
    starts = {}
    for i, t in enumerate(texts):
        lab = defined_label(t)
        if lab:
            starts.setdefault(lab, i)

    def body(name):
        """(MNEMONIC, operands) of the instructions of a routine, from its
        label to its first RET."""
        if name not in starts:
            errors.append("routine %s not found" % name)
            return []
        out = []
        for j, _ in code_lines(texts, starts[name], 1):
            _, mn, ops = parse_code(texts[j])
            if mn:
                out.append((mn, ops))
            if mn == "MOVE" and ops == ["@R13++", "R15"]:
                break
        return out

    open_call = ("RSUB", ["STRROM$OPEN", "1"])
    close_call = ("RSUB", ["STRROM$CLOSE", "1"])
    for name in ("IO$PUTS", "LOG_STR", "SCR$PRINTSTR"):
        code = body(name)
        if open_call not in code or close_call not in code:
            errors.append("%s does not call STRROM$OPEN and STRROM$CLOSE, so "
                          "it is not handle-aware" % name)
            continue
        for mn, ops in code[:code.index(open_call)]:
            if mentions_r8(ops) and not (mn == "MOVE" and ops[0] == "R8"
                                         and re.match(r"^R[0-7]$", ops[1])):
                errors.append("%s uses R8 before STRROM$OPEN: %s %s"
                              % (name, mn, ", ".join(ops)))
    code = body("SCR$PRINTSTRXY")
    if ("RSUB", ["SCR$PRINTSTR", "1"]) not in code or \
            any(mentions_r8(ops) for _, ops in code):
        errors.append("SCR$PRINTSTRXY no longer passes R8 unchanged to "
                      "SCR$PRINTSTR")
    for mn, ops in body("SCR$CLRINNER"):
        if any(re.search(r"(?<![A-Za-z0-9_$])R(8|9)(?![A-Za-z0-9_$])", o)
               for o in ops):
            errors.append("SCR$CLRINNER touches R8 or R9 (%s %s); the pins "
                          "custom_msg_caller and handle_mounting rely on it"
                          % (mn, ", ".join(ops)))
    return errors


def check_menu_fatal(b):
    """The function pointer OPTM_CLBK_FATAL of the menu init record
    OPT_MENU_DATA is FATAL (in the built firmware)."""
    lab, equ, mem = b.new.labels, b.new.equs, b.new_mem
    for n in ("OPT_MENU_DATA", "FATAL"):
        if n not in lab:
            return ["label %s not found in m2m-rom.lis" % n]
    if "OPTM_CLBK_FATAL" not in equ:
        return ["OPTM_CLBK_FATAL not found in m2m-rom.lis"]
    a = lab["OPT_MENU_DATA"] + equ["OPTM_CLBK_FATAL"]
    if mem.get(a) != lab["FATAL"]:
        return ["OPT_MENU_DATA[OPTM_CLBK_FATAL] is 0x%04X, not FATAL (0x%04X):"
                " the menu passes handles to this function pointer"
                % (mem.get(a, -1), lab["FATAL"])]
    return []


def check_handles(b, verbose=False):
    """(d) Every use of a handle reaches a handle-aware routine."""
    if not b.has_table:
        if verbose:
            print("  no handles: the string ROM is not used")
        return []
    errors = check_aware_routines(b) + check_menu_fatal(b)
    texts = b.src.text
    labels = set(b.marked_labels)
    used_entries = [0] * len(ALLOWLIST)
    used_pins = set()
    n_simple = 0
    for i, label in uses_of(b, labels):
        why = simple_use(texts, i, label)
        if why is None:
            n_simple += 1
            continue
        hits = [k for k, e in enumerate(ALLOWLIST)
                if entry_matches(b, i, label, e)]
        if not hits:
            ctx = [n for _, n in code_lines(texts, i, 1)][:4]
            errors.append(
                "%s: %s\n"
                "      label %s is a handle (it is between ;STRROM_BEGIN and "
                ";STRROM_END)\n"
                "      code: %s\n"
                "      Either make sure that every consumer of the handle is "
                "handle-aware (see\n"
                "      M2M/rom/strrom.asm) and add an entry to ALLOWLIST in "
                "strrom_test.py, or\n"
                "      move the string out of the markers."
                % (b.src.loc(i), why, label, " | ".join(ctx)))
            continue
        for k in hits:
            used_entries[k] += 1
            used_pins.update(ALLOWLIST[k]["via"])
    for k, e in enumerate(ALLOWLIST):
        if used_entries[k] == 0:
            errors.append("ALLOWLIST entry for %s in %s matches no use (the "
                          "code changed or the string left the markers): "
                          "update the entry" % (e["label"], e["file"]))
        for p in e["via"]:
            if p not in PINS:
                errors.append("ALLOWLIST entry for %s names the unknown pin "
                              "%s" % (e["label"], p))
    for name in sorted(PINS):
        hits = find_pin(b, name)
        if len(hits) != 1:
            users = sorted({e["label"] for e in ALLOWLIST
                            if name in e["via"]})
            errors.append(
                "pin %s (%s) found %d times: the code that handles flow "
                "through changed.\n      Check that it is still safe for %s, "
                "then update the pin."
                % (name, PINS[name][0], len(hits),
                   ", ".join(users) or "the aware routines"))
    if verbose:
        print("  %d uses of %d handles: %d simple, %d allowlisted"
              % (n_simple + sum(used_entries), len(labels), n_simple,
                 sum(used_entries)))
    return errors


# --- report -----------------------------------------------------------------


def report(b):
    """Strings that are still part of the firmware ROM, largest first, with
    the way they are consumed. Strings without a label that directly follow
    a labeled string are counted as a table of that label. Moving a string
    into the string ROM saves its size minus one word (its table word)."""
    texts = b.src.text
    rom_end = b.ref.labels.get("END_OF_ROM", 0x7000)
    strings = []
    cur = last = None
    for i, (t, words) in enumerate(b.ref.lines):
        _, mn, _ = parse_code(t)
        if i in b.marked or (mn and mn not in (".ASCII_W", ".ASCII_P")) \
                or (words and words[0] > rom_end):
            cur = last = None
            continue
        if not mn or not words:
            if defined_label(t):
                cur = last = None
            continue
        lab = defined_label(t)
        if lab or (cur is None and last is None):
            cur = dict(label=lab or "(no label)", line=i, size=0, count=1)
            strings.append(cur)
        elif cur is None:
            cur = last
            cur["count"] += 1
        cur["size"] += len(words)
        if mn == ".ASCII_W":
            last, cur = cur, None
    names = {s["label"] for s in strings}
    uses = {}
    for i, label in uses_of(b, names):
        uses.setdefault(label, []).append(i)
    rows = []
    for s in strings:
        u = uses.get(s["label"], [])
        why = [(i, simple_use(texts, i, s["label"])) for i in u]
        if not u:
            reason = "not referenced by name"
        elif all(w is None for _, w in why):
            reason = "CANDIDATE: only handle-aware consumers"
        else:
            reason = "; ".join("%s: %s" % (b.src.loc(i), w)
                               for i, w in why if w is not None)
        label = s["label"]
        if s["count"] > 1:
            label += " (table of %d)" % s["count"]
        rows.append((s["size"], label, b.src.file_of(s["line"]), reason))
    rows.sort(key=lambda r: (-r[0], r[1]))
    total = sum(r[0] for r in rows)
    print("\nStrings in the firmware ROM: %d labels, %d words" % (len(rows),
                                                                 total))
    print("%6s  %-30s %-38s %s" % ("words", "label", "file", "uses"))
    for size, label, f, why in rows:
        print("%6d  %-30s %-38s %s" % (size, label, f, why))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main(argv):
    opts = set(argv[1:])
    unknown = opts - {"--no-build", "--report"}
    if unknown:
        sys.stderr.write(__doc__)
        return 2
    tmp = tempfile.mkdtemp(prefix="strrom_test_")
    try:
        if "--no-build" not in opts:
            build(tmp)
        for p in (FW_OUT, FW_LIS, STR_ROM):
            if not os.path.exists(p):
                raise SetupError("%s does not exist; run make_rom.sh first"
                                 % rel(p))
        b = Build(tmp)
    except SetupError as e:
        print("SETUP ERROR: %s" % e)
        shutil.rmtree(tmp, ignore_errors=True)
        return 2
    shutil.rmtree(tmp, ignore_errors=True)

    if b.has_table:
        print("Checking %d string ROM handles, string ROM of %d characters"
              % (len(b.table), b.size))
    else:
        print("No ;STRROM_TABLE marker: the string ROM is not used")
    failed = 0
    for name, fn in (("strings", check_strings),
                     ("transform", check_transform),
                     ("layout", check_layout),
                     ("handles", lambda x: check_handles(x, True))):
        errors = fn(b)
        if errors:
            failed += 1
            print("FAIL %s:" % name)
            for e in errors[:50]:
                print("    " + e)
            if len(errors) > 50:
                print("    ... and %d more" % (len(errors) - 50))
        else:
            print("ok   %s" % name)
    if "--report" in opts:
        report(b)
    if failed:
        print("STRROM TEST FAILED: %d of 4 checks" % failed)
        return 1
    print("STRROM TEST OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
