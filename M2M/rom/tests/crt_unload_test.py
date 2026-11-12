#!/usr/bin/env python3
"""
Headless test of "Space on a loaded .crt unloads it" (GitHub issue #153).

The script cuts the real routines out of the sources, links them against
recording stubs, runs them in the QNICE emulator and compares the trace with
an independent model of the intended behavior:

  * the head of HANDLE_MOUNTING           (M2M/rom/shell.asm)
  * the head of LOAD_IMAGE up to the copy (M2M/rom/shell.asm)
  * CRTROM_M_UNLD, CRTROM_G_ID            (M2M/rom/crts-and-roms.asm)
  * UNLOAD_CRTROM and OSM_SEL_PRE         (CORE/m2m-rom/m2m-rom.asm)

The stubs stand in for the hardware (CSR registers of the CRT/ROM devices,
M2M$CSR, virtual drives, settings) and for the rest of HANDLE_MOUNTING (file
browser path, virtual drive path, menu redraw path). Every stub call is
printed, so the trace shows what the real code does to the hardware and in
which order (for example: the C64 reset is held while the CSR status is
written). Then the script applies mutants to the extracted code; each one
must make the comparison fail.

Usage:  python3 crt_unload_test.py          (ends with "RESULT: PASS")
Needs:  the QNICE assembler, emulator and monitor.out, see README.md.

done by sy2002 in 2026 and licensed under GPL v3
"""

import itertools
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
QNICE = os.path.join(REPO, "M2M", "QNICE")
ASM = os.path.join(QNICE, "assembler", "asm")
EMU = os.path.join(QNICE, "emulator", "qnice")
MON = os.path.join(QNICE, "monitor", "monitor.out")

SHELL = os.path.join(REPO, "M2M", "rom", "shell.asm")
CRTROM = os.path.join(REPO, "M2M", "rom", "crts-and-roms.asm")
MENU = os.path.join(REPO, "M2M", "rom", "menu.asm")
STRINGS = os.path.join(REPO, "M2M", "rom", "strings.asm")
CORE = os.path.join(REPO, "CORE", "m2m-rom", "m2m-rom.asm")
CONFIG = os.path.join(REPO, "CORE", "vhdl", "config.vhd")
MEGA65 = os.path.join(REPO, "CORE", "vhdl", "mega65.vhd")

KEY_SELECT, KEY_SELALT = 3, 5
DEVS = [0x0104, 0x0103]          # CRTROM_MAN_DEV: PRG loader, SW cartridge
CSR_INIT = 0x0140                # other M2M$CSR bits that must survive
NEVER = 0xFFFF                   # TB_PARSE_N: the parser never gets idle


# ---------------------------------------------------------------------------
# Constants from the VHDL, the same way make_rom.sh generates osm_const.asm
# ---------------------------------------------------------------------------
def vhdl_constants():
    out = {}
    for line in open(MEGA65):
        if "constant C_MENU_" in line:
            f = line.split()
            out[f[1].replace("C_MENU_", "C64_OSM_")] = f[5].replace(";", "")
    for line in open(CONFIG):
        if "constant OPTM_G_" in line and "16#" not in line:
            f = line.split()
            out[f[1].replace("OPTM_G_", "C64_OPTM_G_")] = f[5].replace(";", "")
    return out


CONST = vhdl_constants()
G_CRT = int(CONST["C64_OPTM_G_MOUNT_CRT"])
G_PRG = int(CONST["C64_OPTM_G_LOAD_PRG"])
SIM_IDX = int(CONST["C64_OSM_SIM_CRT"])
G_OTHER = next(g for g in range(1, 255)
               if g not in [int(v) for k, v in CONST.items() if k.startswith("C64_OPTM_G_")])
GROUPS = [0x8000 | G_PRG, 0x8000 | G_CRT]   # CRTROM_M_GI: group words incl. flags


# ---------------------------------------------------------------------------
# Extraction of the real code
# ---------------------------------------------------------------------------
def cut(path, start, end=None, through=None):
    """Lines from the one matching start up to (excluding) the one matching
    end, or up to (including) the first one matching through."""
    lines = open(path).read().split("\n")
    s = next((i for i, l in enumerate(lines) if re.match(start, l)), None)
    if s is None:
        sys.exit("cannot find %r in %s" % (start, path))
    for i in range(s + 1, len(lines)):
        if end and re.match(end, lines[i]):
            return "\n".join(lines[s:i]) + "\n"
        if through and re.match(through, lines[i]):
            return "\n".join(lines[s:i + 1]) + "\n"
    sys.exit("cannot find the end of %r in %s" % (start, path))


def equ_lines(path, pattern):
    got = [l for l in open(path).read().split("\n") if re.match(pattern, l)]
    if not got:
        sys.exit("no %r in %s" % (pattern, path))
    return "\n".join(got) + "\n"


def real_code():
    code = {
        "hm": cut(SHELL, r"^HANDLE_MOUNTING\s+SYSCALL\(enter, 1\)",
                  end=r"^\s+; we treat already mounted drives differently"),
        "unld": cut(CRTROM, r"^CRTROM_M_UNLD\s+INCRB", end=r"^; Perform the automatic loading of ROMs"),
        "crmn": cut(CRTROM, r"^_CRMN_C0\s", through=r"^\s+RET\b"),
        "chkno": cut(CRTROM, r"^CRTROM_CHK_NO\s+INCRB", through=r"^\s+RET\b"),
        "cb": cut(CORE, r"^UNLOAD_CRTROM\s+INCRB", end=r"^; Core specific callback functions: Custom tasks"),
        "pre": cut(CORE, r"^OSM_SEL_PRE\s+INCRB", end=r"^; Core specific callback functions: Custom messages"),
        "li": cut(SHELL, r"^LOAD_IMAGE\s+SYSCALL\(enter, 1\)", end=r"^\s+; For showing a progress bar"),
    }
    # the M2M$CSR register becomes a RAM variable that the stubs can observe
    code["cb"] = code["cb"].replace("M2M$CSR,", "TB_CSR,")
    if "TB_CSR," not in code["cb"]:
        sys.exit("UNLOAD_CRTROM does not use M2M$CSR any more: adapt the test")
    return code


def testbed(code, work):
    consts = "".join("%-27s .EQU %s\n" % kv for kv in CONST.items())
    # the monitor entry points, except f32_fopen, which is stubbed
    mondef = os.path.join(work, "monitor_tb.def")
    open(mondef, "w").write("".join(l for l in open(os.path.join(QNICE, "dist_kit", "monitor.def"))
                                    if not re.match(r"^f32_fopen\s", l)))
    return TESTBED.format(
        sysdef=os.path.join(QNICE, "dist_kit", "sysdef.asm"),
        mondef=mondef,
        m2msysdef=os.path.join(REPO, "M2M", "rom", "sysdef.asm"),
        consts=consts,
        keys=equ_lines(MENU, r"^OPTM_KEY_SEL"),
        p1581=equ_lines(CORE, r"^P1581_\w+\s+\.EQU"),
        strs=equ_lines(STRINGS, r"^(LOG_STR_ROMUNL\w*|ERR_FATAL_INST\w*|ERR_FATAL_FNF)\s"),
        rows=rows_asm(),
        devs=", ".join("0x%04X" % d for d in DEVS),
        groups=", ".join("0x%04X" % g for g in GROUPS),
        **code)


TESTBED = r"""
#include "{sysdef}"
#include "{mondef}"
#include "{m2msysdef}"

{consts}
{keys}
{p1581}
                .ORG    0x8000

; ----------------------------------------------------------------------------
; Driver: one row = kind, R8, R9, R10, LDF[0], LDF[1], sim, #vdrives, dirty
; mask, parse_n, PREP_LOAD_IMAGE result; kind 1 = HANDLE_MOUNTING,
; 2 = UNLOAD_CRTROM, 3 = CRTROM_M_UNLD, 4 = CRTROM_G_ID, 5 = OSM_SEL_PRE,
; 6 = LOAD_IMAGE
; ----------------------------------------------------------------------------
START           MOVE    S_BEGIN, R8
                SYSCALL(puts, 1)
                MOVE    ROWS, R6
_ROW            MOVE    @R6++, R0               ; R0: kind
                CMP     0, R0
                RBRA    _DONE, Z
                MOVE    @R6++, R1
                MOVE    @R6++, R2
                MOVE    @R6++, R3
                MOVE    CRTROM_MAN_LDF, R4
                MOVE    @R6++, @R4++
                MOVE    @R6++, @R4
                MOVE    TB_SIM, R4
                MOVE    @R6++, @R4
                MOVE    TB_NVD, R4
                MOVE    @R6++, @R4
                MOVE    TB_DIRTY, R4
                MOVE    @R6++, @R4
                MOVE    TB_PARSE_N, R4
                MOVE    @R6++, @R4
                MOVE    TB_PREP, R4
                MOVE    @R6++, @R4
                MOVE    TB_LASTDEV, R4
                MOVE    0xFFFF, @R4
                MOVE    TB_CSR, R4
                MOVE    {csr_init}, @R4
                MOVE    TB_POLLS, R4
                MOVE    0, @R4

                MOVE    S_ROW, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    R2, R8
                RSUB    PRHEX, 1
                MOVE    R3, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)

                MOVE    R1, R8
                MOVE    R2, R9
                MOVE    R3, R10
                MOVE    0xB11B, R11
                MOVE    0xC12C, R12
                CMP     1, R0
                RBRA    _K2, !Z
                RSUB    HANDLE_MOUNTING, 1
                RBRA    _AFTER, 1
_K2             CMP     2, R0
                RBRA    _K3, !Z
                RSUB    UNLOAD_CRTROM, 1
                RBRA    _AFTER, 1
_K3             CMP     3, R0
                RBRA    _K4, !Z
                RSUB    CRTROM_M_UNLD, 1
                RBRA    _AFTER, 1
_K4             CMP     4, R0
                RBRA    _K5, !Z
                RSUB    CRTROM_G_ID, 1
                RBRA    _AFTER, 1
_K5             CMP     5, R0
                RBRA    _K6, !Z
                RSUB    OSM_SEL_PRE, 1
                RBRA    _AFTER, 1
_K6             RSUB    LOAD_IMAGE, 1

_AFTER          MOVE    SR, R5                  ; R5: flags after the call
                MOVE    SAVE, R4
                MOVE    R8, @R4++
                MOVE    R9, @R4++
                MOVE    R10, @R4++
                MOVE    R11, @R4++
                MOVE    R12, @R4

                MOVE    S_END, R8
                SYSCALL(puts, 1)
                MOVE    R5, R8                  ; carry
                SHR     2, R8
                AND     1, R8
                RSUB    PRHEX, 1
                MOVE    SAVE, R4
                MOVE    5, R3
_PRSAVE         MOVE    @R4++, R8
                RSUB    PRHEX, 1
                SUB     1, R3
                RBRA    _PRSAVE, !Z
                MOVE    CRTROM_MAN_LDF, R4
                MOVE    @R4++, R8
                RSUB    PRHEX, 1
                MOVE    @R4, R8
                RSUB    PRHEX, 1
                MOVE    TB_CSR, R4
                MOVE    @R4, R8
                RSUB    PRHEX, 1
                MOVE    TB_POLLS, R4
                MOVE    @R4, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                RBRA    _ROW, 1

_DONE           MOVE    S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

; print a blank and R8 as four hex digits; keeps all registers
PRHEX           MOVE    R8, @--SP
                MOVE    S_BLANK, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                SYSCALL(puthex, 1)
                RET

S_BEGIN         .ASCII_W "== BEGIN ==\n"
S_DONE          .ASCII_W "DONE\n"
S_ROW           .ASCII_W "ROW"
S_END           .ASCII_W "END"
S_BLANK         .ASCII_W " "
S_CSRW          .ASCII_W "CSRW"
S_RESET         .ASCII_W "RESET"
S_FORCE         .ASCII_W "FORCE"
S_START         .ASCII_W "PATH START"
S_VDRIVE        .ASCII_W "PATH VDRIVE"
S_OSET          .ASCII_W "OPTM_SET"
S_SHOW          .ASCII_W "OPTM_SHOW"
S_OSMON         .ASCII_W "OSM_O_ON"
S_MNTSET        .ASCII_W "VD_MNT_ST_SET"
S_FATAL         .ASCII_W "FATAL"
S_GETS          .ASCII_W "UNEXPECTED GET_SETTING"
S_VDRD          .ASCII_W "UNEXPECTED VD_DRV_READ"
S_CSRR          .ASCII_W "UNEXPECTED CSR_R"
S_CSRRDEV       .ASCII_W "CSR_R OF ANOTHER DEVICE"
S_VDRD_OK       .ASCII_W "VDRD"
S_FOPEN         .ASCII_W "FOPEN"
S_PREP          .ASCII_W "PREP"
S_COPY          .ASCII_W "COPY"
S_REJECT        .ASCII_W "REJECT"
{strs}

; ----------------------------------------------------------------------------
; Stubs
; ----------------------------------------------------------------------------

; CRTROM_M_GI: R8 = CRT/ROM id -> C=1, R8 = group word, R9 = menu index
CRTROM_M_GI     INCRB
                CMP     2, R8
                RBRA    _GI_OK, N               ; R8 < 2
                MOVE    0xEEEE, R8
                MOVE    0xEEEE, R9
                AND     0xFFFB, SR
                DECRB
                RET
_GI_OK          MOVE    R8, R9
                ADD     40, R9                  ; menu index (arbitrary)
                MOVE    TB_GROUPS, R0
                ADD     R8, R0
                MOVE    @R0, R8
                OR      0x0004, SR
                DECRB
                RET

; CRTROM_CSR_W: R8 = device, R9 = register, R10 = value
CRTROM_CSR_W    INCRB
                MOVE    TB_LASTDEV, R1
                MOVE    R8, @R1
                MOVE    R8, R0
                MOVE    S_CSRW, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                MOVE    R10, R8
                RSUB    PRHEX, 1
                MOVE    TB_CSR, R8
                MOVE    @R8, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET

; CRTROM_CSR_R: only the parse status is read; it is "OK" for TB_PARSE_N
; polls, then idle (TB_PARSE_N = 0xFFFF: never idle)
CRTROM_CSR_R    INCRB
                CMP     CRTROM_CSR_PARSEST, R9
                RBRA    _CSRR_PS, Z
                MOVE    R8, R0
                MOVE    S_CSRR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                XOR     R10, R10
                DECRB
                RET
_CSRR_PS        MOVE    TB_LASTDEV, R0
                CMP     @R0, R8
                RBRA    _CSRR_DEV, Z
                MOVE    R8, R0
                MOVE    S_CSRRDEV, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
_CSRR_DEV       MOVE    TB_POLLS, R0
                ADD     1, @R0
                MOVE    TB_PARSE_N, R0          ; @R0: "OK" polls still to come
                MOVE    CRTROM_CSR_PT_OK, R10
                CMP     0xFFFF, @R0
                RBRA    _CSRR_RET, Z            ; never idle
                CMP     0, @R0
                RBRA    _CSRR_IDLE, Z
                SUB     1, @R0
                RBRA    _CSRR_RET, 1
_CSRR_IDLE      MOVE    CRTROM_CSR_PT_IDLE, R10
_CSRR_RET       DECRB
                RET

M2M$GET_SETTING INCRB
                CMP     C64_OSM_SIM_CRT, R8
                RBRA    _GETS_OK, Z
                MOVE    R8, R0
                MOVE    S_GETS, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                XOR     R9, R9
                DECRB
                RET
_GETS_OK        MOVE    TB_SIM, R9
                MOVE    @R9, R9
                DECRB
                RET

M2M$FORCE_MENU  INCRB
                MOVE    R8, R0
                MOVE    S_FORCE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET

; RESET_CORE: prints M2M$CSR, then releases the reset like the real one
RESET_CORE      INCRB
                MOVE    R8, R0
                MOVE    S_RESET, R8
                SYSCALL(puts, 1)
                MOVE    TB_CSR, R8
                MOVE    @R8, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    TB_CSR, R8
                AND     M2M$CSR_UN_RESET, @R8
                MOVE    R0, R8
                DECRB
                RET

VD_ACTIVE       INCRB
                MOVE    TB_NVD, R8
                MOVE    @R8, R8
                AND     0xFFFB, SR
                CMP     0, R8
                RBRA    _VDA_RET, Z
                OR      0x0004, SR
_VDA_RET        DECRB
                RET

; VD_DRV_READ: R8 = drive, R9 = register -> R8 (overwrites R8 like the real one)
VD_DRV_READ     INCRB
                CMP     VD_CACHE_DIRTY, R9
                RBRA    _VDR_OK, Z
                MOVE    S_VDRD, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                XOR     R8, R8
                DECRB
                RET
_VDR_OK         MOVE    R8, R1
                MOVE    S_VDRD_OK, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    TB_CSR, R8
                MOVE    @R8, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R1, R8
                MOVE    TB_DIRTY, R0
                MOVE    @R0, R0
                CMP     0, R8
                RBRA    _VDR_2, Z
_VDR_1          SHR     1, R0
                SUB     1, R8
                RBRA    _VDR_1, !Z
_VDR_2          AND     1, R0
                MOVE    R0, R8
                DECRB
                RET

FATAL           MOVE    R8, R0
                MOVE    S_FATAL, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; menu functions used by the unload exit of HANDLE_MOUNTING
OPTM_SET        INCRB
                MOVE    R8, R0
                MOVE    S_OSET, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET
OPTM_SHOW       MOVE    R8, @--SP
                MOVE    S_SHOW, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET
SCR$OSM_O_ON    MOVE    R8, @--SP
                MOVE    S_OSMON, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET
; must not be called on the unload path (see HANDLE_MOUNTING)
VD_MNT_ST_SET   MOVE    R8, @--SP
                MOVE    S_MNTSET, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; the other two exits of the head of HANDLE_MOUNTING (inside its SYSCALL(enter))
_HM_START_MOUNT MOVE    S_START, R8
                RBRA    _HM_STUB, 1
_HM_VDRIVE      MOVE    R8, R4
                MOVE    S_VDRIVE, R8
                RBRA    _HM_STUB, 1
_HM_STUB        MOVE    R8, R3
                SYSCALL(puts, 1)
                MOVE    R5, R8
                RSUB    PRHEX, 1
                MOVE    R7, R8
                RSUB    PRHEX, 1
                CMP     S_START, R3
                RBRA    _HM_STUB2, Z            ; R8 is not an input there
                MOVE    R4, R8
                RSUB    PRHEX, 1
_HM_STUB2       SYSCALL(crlf, 1)
                SYSCALL(leave, 1)
                RET

; f32_fopen (monitor) and PREP_LOAD_IMAGE (core callback) for LOAD_IMAGE
f32_fopen       MOVE    R8, @--SP
                MOVE    S_FOPEN, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                XOR     R10, R10                ; no error
                RET
PREP_LOAD_IMAGE INCRB
                MOVE    S_PREP, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    TB_PREP, R8
                MOVE    @R8, R8
                MOVE    0x0007, R9              ; image type or error message
                DECRB
                RET

; ----------------------------------------------------------------------------
; The real code
; ----------------------------------------------------------------------------
{li}
; LOAD_IMAGE would show the progress bar and copy the file from here on
_LI_PROGRESS    MOVE    S_COPY, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(leave, 1)
                RET
; the end of LOAD_IMAGE after a rejected file (PREP_LOAD_IMAGE error)
_LI_FREAD_RET   MOVE    S_REJECT, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(leave, 1)
                RET

{hm}
{unld}
{crmn}
{chkno}
{cb}
{pre}

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------
CRTROM_MAN_NUM  .DW     2
CRTROM_MAN_DEV  .DW     {devs}
CRTROM_MAN_LDF  .BLOCK  2
TB_GROUPS       .DW     {groups}
TB_CSR          .BLOCK  1
TB_SIM          .BLOCK  1
TB_NVD          .BLOCK  1
TB_DIRTY        .BLOCK  1
TB_PARSE_N      .BLOCK  1
TB_PREP         .BLOCK  1
TB_LASTDEV      .BLOCK  1
VDRIVES_BUFS    .DW     0x0101, 0x0102
HNDL_VD_FILES   .DW     TB_FH, TB_FH
HNDL_RM_FILES   .DW     TB_FH, TB_FH
TB_FH           .BLOCK  1
HANDLE_DEV      .BLOCK  1
SF_CONTEXT      .BLOCK  1
SF_CONTEXT_DATA .BLOCK  1
LOAD_IMAGE_TYPE .BLOCK  1
TB_POLLS        .BLOCK  1
SAVE            .BLOCK  5

ROWS
{rows}
                .DW     0
""".replace("{csr_init}", "0x%04X" % CSR_INIT)


# ---------------------------------------------------------------------------
# Rows and the model
# ---------------------------------------------------------------------------
def make_rows():
    rows = []
    # kind 1: HANDLE_MOUNTING, every combination
    for mode, key, cid, ldf, other, sim, nvd, dirty in itertools.product(
            (0, 1), (KEY_SELECT, KEY_SELALT), (0, 1), (0, 1), (0, 1), (0, 1), (0, 1, 2), (0, 1, 2, 3)):
        l = [other, other]
        l[cid] = ldf
        rows.append((1, cid, key, mode, l[0], l[1], sim, nvd, dirty, 3, 0))
    # kind 2: UNLOAD_CRTROM directly (also for a not loaded id: the Shell never
    # does that, but the callback must still not touch the other id)
    for cid, sim, nvd, dirty in itertools.product((0, 1), (0, 1), (0, 1, 2), (0, 1, 2)):
        rows.append((2, cid, 0x9999, 0xAAAA, 1, 1, sim, nvd, dirty, 0, 0))
    # kind 3: CRTROM_M_UNLD with different parser timings, incl. the time limit
    for cid, pn in itertools.product((0, 1), (0, 1, 4, 65534, 65535, NEVER)):
        rows.append((3, cid, 0x9999, 0xAAAA, 1, 1, 0, 0, 0, pn, 0))
    # kind 4: CRTROM_G_ID
    for g in (G_PRG, G_CRT, G_OTHER, 0, 0xFF):
        rows.append((4, g, 0x9999, 0xAAAA, 0, 0, 0, 0, 0, 0, 0))
    # kind 5: OSM_SEL_PRE for the CRT line and for an unrelated group
    for g, key, ldf, sim, item in itertools.product((G_CRT, G_OTHER), (KEY_SELECT, KEY_SELALT),
                                                     (0, 1), (0, 1), (0, 1)):
        rows.append((5, g, item, key, 1, ldf, sim, 2, 0, 0, 0))
    # kind 6: LOAD_IMAGE with an accepted and a rejected file, CRT/ROM and disk image mode
    for cid, mode, prep in itertools.product((0, 1), (0, 1), (0, 1)):
        rows.append((6, cid, 0x1234, mode, 1, 1, 1, 2, 0, 0, prep))
    return rows


def rows_asm():
    return "\n".join("                .DW     " + ", ".join("0x%04X" % v for v in r) for r in ROWS)


def model(rows):
    out = ["== BEGIN =="]
    h = lambda v: "%04X" % (v & 0xFFFF)
    for kind, r8, r9, r10, l0, l1, sim, nvd, dirty, pn, prep in rows:
        out.append("ROW " + " ".join(h(v) for v in (kind, r8, r9, r10)))
        st = {"ldf": [l0, l1], "csr": CSR_INIT, "polls": 0}

        def m_unld(cid):
            out.append("CSRW %s 7000 0000 %s" % (h(DEVS[cid]), h(st["csr"])))
            st["polls"] = 65536 if pn == NEVER else min(pn + 1, 65536)
            st["ldf"][cid] = 0
            out.append("Unloaded CRT/ROM #" + h(cid) + (" (parser did not report idle)" if pn == NEVER else ""))

        def callback(cid):                       # UNLOAD_CRTROM, returns carry
            if cid != 1:                         # only the .crt
                return 0
            if sim == 0:
                m_unld(cid)
                return 1
            st["csr"] |= 1                       # hold the C64 in reset, then check
            for d in range(nvd):
                out.append("VDRD %s %s" % (h(d), h(st["csr"])))
                if (dirty >> d) & 1:             # unsaved disk data: release, ignore Space
                    st["csr"] &= 0xFFFE
                    return 1
            m_unld(cid)
            out.append("RESET " + h(st["csr"]))
            st["csr"] &= 0xFFFE
            return 1

        regs = [r8, r9, r10, 0xB11B, 0xC12C]
        carry = None
        if kind == 1:
            cid, key, mode = r8, r9, r10
            if mode != 1:
                out.append("PATH VDRIVE %s %s %s" % (h(mode), h(cid), h(cid)))
            elif key != KEY_SELALT or st["ldf"][cid] != 1 or not callback(cid):
                out.append("PATH START %s %s" % (h(mode), h(cid)))
            else:   # menu item := load status, redraw, no VD_MNT_ST_SET
                out.append("OPTM_SET %s %s" % (h(cid + 40), h(st["ldf"][cid])))
                out.append("OPTM_SHOW")
                out.append("OSM_O_ON")
        elif kind == 2:
            carry = callback(r8)
        elif kind == 3:
            m_unld(r8)
        elif kind == 4:
            ids = [i for i, g in enumerate(GROUPS) if g & 0xFF == r8]
            carry = 1 if ids else 0
            regs[0] = ids[0] if ids else r8
        elif kind == 5:
            group, key = r8, r10
            if group == G_CRT and not (key == KEY_SELALT and st["ldf"][1] == 1) and sim == 0:
                out.append("FORCE %s 0001" % h(SIM_IDX))
                out.append("RESET " + h(st["csr"]))
                st["csr"] &= 0xFFFE
            regs[0], regs[1] = 0, 0
        elif kind == 6:
            cid, mode = r8, r10
            out.append("FOPEN")
            out.append("PREP")
            if prep:
                out.append("REJECT")             # the device is not touched
            else:
                if mode == 1:
                    out.append("CSRW %s 7000 0001 %s" % (h(DEVS[cid]), h(st["csr"])))
                out.append("COPY")
        out.append("END %s %s %s %s %s %s" % (
            "C" if carry is None else h(carry), " ".join(h(v) for v in regs),
            h(st["ldf"][0]), h(st["ldf"][1]), h(st["csr"]), h(st["polls"])))
    out.append("DONE")
    return out


ROWS = make_rows()


# ---------------------------------------------------------------------------
# Assemble, run, compare
# ---------------------------------------------------------------------------
def run(code, work):
    src = os.path.join(work, "crt_unload_tb.asm")
    open(src, "w").write(testbed(code, work))
    r = subprocess.run([ASM, "crt_unload_tb.asm"], cwd=work, capture_output=True, text=True, timeout=120)
    out = os.path.join(work, "crt_unload_tb.out")
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, (r.stdout + r.stderr)[-2000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        return None, "emulator timeout"
    lines = [l for l in r.stdout.replace("\r", "").split("\n") if l]
    if "== BEGIN ==" in lines:
        lines = lines[lines.index("== BEGIN =="):]
    if "DONE" in lines:
        lines = lines[:lines.index("DONE") + 1]
    return lines, ""


def compare(got, exp):
    """Returns None if equal, else a short description of the first difference."""
    if got is None:
        return "no output"
    row = "?"
    for i in range(max(len(got), len(exp))):
        g = got[i] if i < len(got) else "<missing>"
        e = exp[i] if i < len(exp) else "<missing>"
        if e.startswith("ROW"):
            row = e
        if e.startswith("END C ") and g.startswith("END "):
            g = "END C " + g.split(" ", 2)[2]    # carry is not part of the contract here
        if g.upper() != e.upper():
            return "%s: expected %r, got %r" % (row, e, g)
    return None


# mutants: (name, part, old, new); each must make the comparison fail
MUTANTS = [
    ("osm_pre_no_guard", "pre", "CMP     OPTM_KEY_SELALT, R10    ; Space?", "CMP     0x7777, R10"),
    ("hm_no_ldf_check", "hm", "CMP     1, @R8\n                RBRA    _HM_START_MOUNT, !Z",
     "CMP     1, @R8\n                MOVE    R0, R0"),
    ("hm_callback_ignored", "hm", "RBRA    _HM_START_MOUNT, !C     ; no: browse and load",
     "MOVE    R0, R0"),
    ("cb_no_prg_check", "cb", "CMP     R0, R8\n                RBRA    _UNLD_RET, !Z",
     "CMP     R0, R8\n                MOVE    R0, R0"),
    ("cb_sim_inverted", "cb", "RBRA    _UNLD_SIM, Z", "RBRA    _UNLD_SIM, !Z"),
    ("cb_no_dirty_check", "cb", "RBRA    _UNLD_KEEP, !Z          ; dirty: ignore Space", "MOVE    R0, R0"),
    ("cb_no_release", "cb", "AND     M2M$CSR_UN_RESET, @R2   ; release the reset", "MOVE    R0, R0"),
    ("cb_no_reset_hold", "cb", "OR      M2M$CSR_RESET, @R2      ; assert soft reset", "MOVE    R0, R0"),
    ("cb_reset_first", "cb",
     "MOVE    R0, R8\n                RSUB    CRTROM_M_UNLD, 1        ; waits for the idle parser\n"
     "                RSUB    RESET_CORE, 1           ; keep and release the reset",
     "RSUB    RESET_CORE, 1\n                MOVE    R0, R8\n"
     "                RSUB    CRTROM_M_UNLD, 1"),
    ("cb_no_reset", "cb", "RSUB    RESET_CORE, 1           ; keep and release the reset", "MOVE    R0, R0"),
    ("hm_snapshot_mounts", "hm", "RSUB    SCR$OSM_O_ON, 1\n                SYSCALL(leave, 1)",
     "RSUB    SCR$OSM_O_ON, 1\n                RSUB    VD_MNT_ST_SET, 1\n                SYSCALL(leave, 1)"),
    ("hm_wrong_status", "hm", "MOVE    @R9, R9\n                RSUB    OPTM_SET, 1",
     "MOVE    1, R9\n                RSUB    OPTM_SET, 1"),
    ("unld_poll_wrong_dev", "unld", "MOVE    CRTROM_CSR_PARSEST, R9  ; wait for the idle parser",
     "ADD     1, R8\n                MOVE    CRTROM_CSR_PARSEST, R9"),
    ("unld_no_timeout_flag", "unld", "RBRA    _CRTRUNL_1, !Z\n                MOVE    1, R4",
     "RBRA    _CRTRUNL_1, !Z"),
    ("li_ldng_first", "li", [
        ("MOVE    @R0, R0                 ; R0: device number\n                MOVE    HNDL_RM_FILES, R9",
         "MOVE    @R0, R0                 ; R0: device number\n                MOVE    R0, R8\n"
         "                MOVE    CRTROM_CSR_STATUS, R9\n                MOVE    CRTROM_CSR_ST_LDNG, R10\n"
         "                RSUB    CRTROM_CSR_W, 1\n                MOVE    HNDL_RM_FILES, R9"),
        ("                MOVE    R0, R8\n                MOVE    CRTROM_CSR_STATUS, R9   ; set CSR to \"loading\"\n"
         "                MOVE    CRTROM_CSR_ST_LDNG, R10\n                RSUB    CRTROM_CSR_W, 1\n", "")]),
    ("li_no_mode_check", "li", "RBRA    _LI_PROGRESS, !Z        ; no", "MOVE    R0, R0"),
    ("unld_no_wait", "unld", "RBRA    _CRTRUNL_1, !Z", "MOVE    R0, R0"),
    ("unld_ldf_kept", "unld", "ADD     R0, R8\n                MOVE    0, @R8", "ADD     R0, R8"),
    ("unld_r9_lost", "unld", "MOVE    R1, R9\n                MOVE    R2, R10\n                DECRB",
     "MOVE    R2, R10\n                DECRB"),
    ("gid_no_flag_mask", "unld", "AND     0x00FF, R8              ; remove flags", "MOVE    R8, R8"),
]


def main():
    for tool in (ASM, EMU, MON):
        if not os.path.exists(tool):
            sys.exit("missing %s (see README.md: build the QNICE toolchain first)" % tool)
    work = tempfile.mkdtemp(prefix="crt_unload_test.")
    fails = 0
    try:
        code = real_code()
        exp = model(ROWS)
        got, err = run(code, work)
        diff = compare(got, exp)
        n = sum(1 for l in exp if l.startswith("ROW"))
        if diff:
            print("FAIL: real code: %s %s" % (diff, err))
            fails += 1
        else:
            print("PASS: real code, %d rows (HANDLE_MOUNTING, UNLOAD_CRTROM, CRTROM_M_UNLD, "
                  "CRTROM_G_ID, OSM_SEL_PRE, LOAD_IMAGE)" % n)
        for m in MUTANTS:
            name, part = m[0], m[1]
            pairs = m[2] if isinstance(m[2], list) else [(m[2], m[3])]
            text = code[part]
            for old, new in pairs:
                if text.count(old) != 1:
                    break
                text = text.replace(old, new)
            else:
                old = None
            if old is not None:
                print("FAIL: mutant %s: pattern found %d times" % (name, text.count(old)))
                fails += 1
                continue
            mcode = dict(code)
            mcode[part] = text
            got, err = run(mcode, work)
            diff = compare(got, exp)
            if diff:
                print("PASS: mutant %-20s caught (%s)" % (name, diff[:100]))
            else:
                print("FAIL: mutant %s not caught" % name)
                fails += 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("RESULT: PASS" if fails == 0 else "RESULT: FAIL (%d)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
