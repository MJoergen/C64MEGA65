#!/usr/bin/env python3
"""
Headless test: no redraw of the menu in the invisible menu session of a
keyboard shortcut (_OPTM_GK_MNT and _OPTM_GK_CRTROM in M2M/rom/options.asm).

_OPTM_GK_MNT brings the menu items and the bits in M2M$CFM_DATA of all virtual
drives in line with their mount status, _OPTM_GK_CRTROM does the same for the
CRT/ROM items whose load status changed. Both end at _OPTM_GK_MNT_S, which
redraws the menu with OPTM_SHOW and shows the selection again with
OPTM_SELECT. The key loop of the visible menu (OPT_MENU_GETKEY) calls both,
and HANDLE_MOUNTING calls _OPTM_GK_MNT after it loaded a CRT/ROM, also in the
invisible session of a keyboard shortcut (OPTM_DIRECT is not zero, see
SC$SESSION in shortcuts.asm). There the on-screen menu is off, so the redraw
is skipped; the updates of the menu items and of M2M$CFM_DATA are not.

The script cuts both routines out of options.asm on every run and links them
against stubs that print a trace line for every call (VD_ACTIVE,
VD_MNT_ST_GET, VD_MENGRP, OPTM_SET, CRTROM_M_GI, M2M$SET_SETTING,
CRTROM_MLST_GET, OPTM_SHOW, OPTM_SELECT, FATAL). M2M$CFM_ADDR and M2M$CFM_DATA
become variables of the testbed that behave like the hardware (32 banks of 16
bits, the data register shows the selected bank): the script inserts a call
of a trace routine behind every instruction of the extracted code that writes
to memory through a register, so every access to the two registers is in
the trace, and so would be any other write. The cases: OPTM_DIRECT 0, 1 and
0x8000, entry through _OPTM_GK_MNT and through _OPTM_GK_CRTROM, no virtual
drive at all, one and two drives in every combination of mounted and
unmounted (on two different contents of the banks, so that every bit is once
set and once clear before), one and several changed CRT/ROM statuses, and a
drive or CRT/ROM without a menu item (fatal). After every case the testbed
prints all registers, the change of the stack pointer and of the register
bank, the two registers and all banks of M2M$CFM_DATA and OPTM_DIRECT.

An independent model computes the trace of the routines as they were before
the redraw was skipped and, from it, the expected trace: the same, without
the lines of OPTM_SHOW and OPTM_SELECT in the cases with OPTM_DIRECT not
zero. The code without the skip (the code before the change) must produce
the trace of the model without the skip, and the real code and the code
without the skip must produce identical traces in the cases with OPTM_DIRECT
zero. Then the script applies mutants to the extracted code; each must make
the comparison fail.

Usage:  python3 hidden_redraw_test.py [--keep]   (ends with "RESULT: PASS")
        --keep keeps the work folder with the testbed and the traces
Needs:  the QNICE assembler, emulator and monitor.out, see README.md.

done by sy2002 in 2026 and licensed under GPL v3
"""

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

OPTIONS = os.path.join(REPO, "M2M", "rom", "options.asm")
MENU = os.path.join(REPO, "M2M", "rom", "menu.asm")
STRINGS = os.path.join(REPO, "M2M", "rom", "strings.asm")
QSYSDEF = os.path.join(QNICE, "dist_kit", "sysdef.asm")
MONDEF = os.path.join(QNICE, "dist_kit", "monitor.def")


def equ(path, name):
    for line in open(path):
        m = re.match(r"^%s\s+\.EQU\s+(0x[0-9A-Fa-f]+|\d+)" % re.escape(name), line)
        if m:
            return int(m.group(1), 0)
    sys.exit("no %s in %s" % (name, path))


SEL_SEL = equ(MENU, "OPTM_SEL_SEL")
INST4 = equ(STRINGS, "ERR_FATAL_INST4")
INSTB = equ(STRINGS, "ERR_FATAL_INSTB")

# The testbed: the menu index of each virtual drive (VD_MENGRP) is in bank 0
# and in the last bank, at the lowest and the highest bit position of a bank
# that the drives use; CRT/ROM id i has the menu index 0x0140 + i, and id 7
# has no menu item
IDX = [0x0005, 0x01FF]
NOCRT = 7
JUNK = 0x0BAD                           # M2M$CFM_ADDR and _DATA before a case
NONE = 0xFFFF                           # no drive without a menu item
REGS_IN = [0x1000 + i for i in range(13)]   # R0..R12 before the call
DIRECTS = [0, 1, 0x8000]


def bank_patterns():
    p0 = [((0x9E37 * (i + 3)) ^ (i << 9)) & 0xFFFF for i in range(32)]
    p0[IDX[0] >> 4] |= 1 << (IDX[0] & 15)
    p0[IDX[1] >> 4] &= ~(1 << (IDX[1] & 15)) & 0xFFFF
    return [p0, [~w & 0xFFFF for w in p0]]


PATTERNS = bank_patterns()


def make_cases():
    cases = []
    for direct in DIRECTS:
        mnt = dict(entry=0, direct=direct)
        cases.append(dict(mnt, ndrv=0, mnt=0, pat=0))                   # no drive at all
        for pat in (0, 1):
            for m in (0, 1):
                cases.append(dict(mnt, ndrv=1, mnt=m, pat=pat))         # one drive
            for m in range(4):
                cases.append(dict(mnt, ndrv=2, mnt=m, pat=pat))         # two drives
        cases.append(dict(mnt, ndrv=1, mnt=0xFFFE, pat=0))              # bits of absent drives
        cases.append(dict(mnt, ndrv=2, mnt=3, pat=1, mgfail=1))         # drive 1: no menu item
        crt = dict(entry=1, direct=direct)
        cases.append(dict(crt, crt=(0, 1), script=[]))                  # one changed status
        cases.append(dict(crt, crt=(1, 0), script=[]))
        cases.append(dict(crt, crt=(0, 1), script=[(1, 0)]))            # several
        cases.append(dict(crt, crt=(2, 1), script=[(0, 0), (1, 1), (2, 0)]))
        cases.append(dict(crt, crt=(NOCRT, 1), script=[]))              # no menu item
        cases.append(dict(crt, crt=(0, 1), script=[(NOCRT, 0)]))        # no menu item later
    for n, c in enumerate(cases):
        c.setdefault("ndrv", 0)
        c.setdefault("mnt", 0)
        c.setdefault("pat", n % 2)
        c.setdefault("mgfail", NONE)
        c.setdefault("crt", (REGS_IN[8], REGS_IN[9]))
        c.setdefault("script", [])
        c["cur"] = 0x0100 + n                                           # OPTM_CUR_SEL
    return cases


CASES = make_cases()


# ---------------------------------------------------------------------------
# Extraction of the real code
# ---------------------------------------------------------------------------
def cut(path, start, end):
    """Lines from the one matching start up to (excluding) the one matching
    end."""
    lines = open(path).read().split("\n")
    s = next((i for i, l in enumerate(lines) if re.match(start, l)), None)
    if s is None:
        sys.exit("cannot find %r in %s" % (start, path))
    for i in range(s + 1, len(lines)):
        if re.match(end, lines[i]):
            return "\n".join(lines[s:i]) + "\n"
    sys.exit("cannot find the end of %r in %s" % (start, path))


def real_code():
    """_OPTM_GK_MNT and _OPTM_GK_CRTROM: from the label of _OPTM_GK_MNT up to
    the header of the next routine (OPTM_CB_SEL)."""
    code = cut(OPTIONS, r"^_OPTM_GK_MNT\s+SYSCALL\(enter, 1\)", r"^; -{20,}")
    for label in ("_OPTM_GK_MNT_S", "_OPTM_GK_MNT_R", "_OPTM_GK_CRTROM"):
        if not re.search(r"^%s\s" % label, code, re.M):
            sys.exit("no %s in the code cut out of %s: adapt the test" % (label, OPTIONS))
    return code


DEST = re.compile(r"^\S*\s+([A-Z]+)\s+[^;]*?,\s*(@\S+)")


def instrument(code):
    """The registers M2M$CFM_ADDR and M2M$CFM_DATA become variables of the
    testbed, and every instruction that writes to memory through a register
    is followed by a call of the trace routine TB_W_<register>, which keeps
    all registers and flags. Returns None for a destination that the trace
    routines do not know (@--Rn, @Rn++)."""
    code = code.replace("M2M$CFM_ADDR", "TB_CFM_ADDR").replace("M2M$CFM_DATA", "TB_CFM_DATA")
    out = []
    for line in code.split("\n"):
        out.append(line)
        m = DEST.match(line.split(";")[0])
        if not m or m.group(1) == "CMP":                # CMP does not write
            continue
        r = re.match(r"^@(R[0-7])$", m.group(2))
        if not r:
            return None
        out.append(" " * 16 + "RSUB    TB_W_%s, 1" % r.group(1))
    return "\n".join(out)


TESTBED = r"""
#include "{sysdef}"
#include "{mondef}"

OPTM_SEL_SEL    .EQU    {sel_sel}
ERR_FATAL_INST4 .EQU    {inst4}
ERR_FATAL_INSTB .EQU    {instb}
                .ORG    0x8000

; ----------------------------------------------------------------------------
; Driver: one row per case (TB_ROWLEN words, see the variables TB_ENTRY to
; TB_MLST); 0xFFFF ends the list
; ----------------------------------------------------------------------------
START           MOVE    S_BEGIN, R8
                SYSCALL(puts, 1)
                MOVE    TB_ROW, R0
                MOVE    CASES, @R0
                MOVE    TB_CNO, R0
                MOVE    0, @R0

_CASE           MOVE    TB_ROW, R0
                MOVE    @R0, R1                 ; R1: row of the case
                CMP     0xFFFF, @R1
                RBRA    _DONE, Z
                MOVE    TB_ENTRY, R2            ; copy the row into the
                MOVE    {rowlen}, R3            ; variables of the case
_ROWCP          MOVE    @R1++, @R2++
                SUB     1, R3
                RBRA    _ROWCP, !Z
                MOVE    R1, @R0

                MOVE    TB_PATTERN, R8          ; the banks of M2M$CFM_DATA
                MOVE    @R8, R8
                MOVE    TB_BANKS, R9
                MOVE    32, R10
                SYSCALL(memcpy, 1)
                MOVE    TB_CFM_ADDR, R0
                MOVE    {junk}, @R0
                MOVE    TB_CFM_DATA, R0
                MOVE    {junk}, @R0

                MOVE    S_CASE, R8
                SYSCALL(puts, 1)
                MOVE    TB_CNO, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    TB_ENTRY, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    OPTM_DIRECT, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)

                MOVE    TB_SP, R0               ; for FATAL and the SP check
                MOVE    SP, @R0
                MOVE    TB_SR, R0
                MOVE    SR, @R0
                MOVE    TB_ENTRY, R0
                CMP     0, @R0
                RBRA    _CALL_CR, !Z
                RSUB    TB_LOADREGS, 1
                RSUB    _OPTM_GK_MNT, 1
                RBRA    _CALLED, 1
_CALL_CR        RSUB    TB_LOADREGS, 1
                RSUB    _OPTM_GK_CRTROM, 1
_CALLED         MOVE    SR, @--SP               ; keep everything the call
                MOVE    R12, @--SP              ; left behind
                MOVE    R11, @--SP
                MOVE    R10, @--SP
                MOVE    R9, @--SP
                MOVE    R8, @--SP
                MOVE    R7, @--SP
                MOVE    R6, @--SP
                MOVE    R5, @--SP
                MOVE    R4, @--SP
                MOVE    R3, @--SP
                MOVE    R2, @--SP
                MOVE    R1, @--SP
                MOVE    R0, @--SP
                MOVE    TB_REGS, R0             ; TB_REGS: R0..R12, SR, SP
                MOVE    14, R1
_SAVEREGS       MOVE    @SP++, @R0++
                SUB     1, R1
                RBRA    _SAVEREGS, !Z
                MOVE    SP, @R0

                MOVE    S_REGS, R8
                SYSCALL(puts, 1)
                MOVE    TB_REGS, R0
                MOVE    13, R1
_PRREGS         MOVE    @R0++, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _PRREGS, !Z
                MOVE    S_SP, R8                ; SP difference
                SYSCALL(puts, 1)
                MOVE    @R0++, R2               ; R2: SR after the call
                MOVE    @R0, R8
                MOVE    TB_SP, R3
                SUB     @R3, R8
                RSUB    PRHEX, 1
                MOVE    S_BANK, R8              ; register bank difference
                SYSCALL(puts, 1)
                MOVE    R2, R8
                MOVE    TB_SR, R3
                XOR     @R3, R8
                AND     0xFF00, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                RBRA    _DUMP, 1

                ; FATAL returns here with the SP and the register bank of the
                ; driver
_FATALRET       MOVE    S_REGSF, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)

_DUMP           MOVE    S_CFM, R8               ; M2M$CFM_ADDR and _DATA
                SYSCALL(puts, 1)
                MOVE    TB_CFM_ADDR, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    TB_CFM_DATA, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    S_BANKS, R8             ; all banks
                SYSCALL(puts, 1)
                MOVE    TB_BANKS, R0
                MOVE    32, R1
_PRBANKS        MOVE    @R0++, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _PRBANKS, !Z
                SYSCALL(crlf, 1)
                MOVE    S_DIRECT, R8
                SYSCALL(puts, 1)
                MOVE    OPTM_DIRECT, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)

                MOVE    TB_CNO, R0
                ADD     1, @R0
                RBRA    _CASE, 1

_DONE           MOVE    S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

; R0..R12 before the call; R8 and R9 are the input of _OPTM_GK_CRTROM
TB_LOADREGS     MOVE    {r0}, R0
                MOVE    {r1}, R1
                MOVE    {r2}, R2
                MOVE    {r3}, R3
                MOVE    {r4}, R4
                MOVE    {r5}, R5
                MOVE    {r6}, R6
                MOVE    {r7}, R7
                MOVE    TB_IN8, R8
                MOVE    @R8, R8
                MOVE    TB_IN9, R9
                MOVE    @R9, R9
                MOVE    {r10}, R10
                MOVE    {r11}, R11
                MOVE    {r12}, R12
                RET

; print a blank and R8 as four hex digits; keeps all registers
PRHEX           MOVE    R8, @--SP
                MOVE    S_BLANK, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                SYSCALL(puthex, 1)
                RET

; ----------------------------------------------------------------------------
; Trace of the writes to memory: the instrumented code calls TB_W_<register>
; behind every instruction that writes through that register; registers and
; flags stay unchanged. M2M$CFM_ADDR selects one of 32 banks and
; M2M$CFM_DATA shows and changes the selected bank, as in the hardware.
; ----------------------------------------------------------------------------
{hooks}

TB_WRITE        INCRB
                MOVE    R8, R0                  ; R0: address written to
                CMP     TB_CFM_ADDR, R0
                RBRA    _TBW_DATA, !Z
                MOVE    S_CFMA, R8              ; M2M$CFM_ADDR: select a bank
                SYSCALL(puts, 1)
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    @R0, R1                 ; M2M$CFM_DATA shows the bank
                AND     0x001F, R1
                ADD     TB_BANKS, R1
                MOVE    TB_CFM_DATA, R2
                MOVE    @R1, @R2
                RBRA    _TBW_RET, 1
_TBW_DATA       CMP     TB_CFM_DATA, R0
                RBRA    _TBW_OTHER, !Z
                MOVE    S_CFMD, R8              ; M2M$CFM_DATA: change the bank
                SYSCALL(puts, 1)
                MOVE    TB_CFM_ADDR, R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    TB_CFM_ADDR, R1
                MOVE    @R1, R1
                AND     0x001F, R1
                ADD     TB_BANKS, R1
                MOVE    @R0, @R1
                RBRA    _TBW_RET, 1
_TBW_OTHER      MOVE    S_WRITE, R8             ; any other write
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
_TBW_RET        DECRB
                RET

; ----------------------------------------------------------------------------
; Stubs: each prints a trace line and treats the registers like the real
; routine
; ----------------------------------------------------------------------------

; VD_ACTIVE: R8 = amount of virtual drives, Carry = 1 if there is one
VD_ACTIVE       INCRB
                MOVE    VDRIVES_NUM, R0
                MOVE    @R0, R0
                MOVE    S_VDACT, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                CMP     0, R8
                RBRA    _VDA_NO, Z
                OR      0x0004, SR
                RET
_VDA_NO         AND     0xFFFB, SR
                RET

; VD_MNT_ST_GET: R8 = mount status of all drives (TB_MNT), Carry = 1
VD_MNT_ST_GET   INCRB
                MOVE    TB_MNT, R0
                MOVE    @R0, R0
                MOVE    S_MNTGET, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                OR      0x0004, SR
                RET

; VD_MENGRP: R8 = drive -> R8 = menu group, R9 = menu index (TB_IDX),
; Carry = 1; the drive TB_MGFAIL has no menu item (Carry = 0)
VD_MENGRP       INCRB
                MOVE    R8, R0                  ; R0: drive
                MOVE    S_MENGRP, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    TB_MGFAIL, R1
                CMP     @R1, R0
                RBRA    _VDMG_OK, !Z
                MOVE    S_NONE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                AND     0xFFFB, SR
                RET
_VDMG_OK        MOVE    TB_IDX, R1
                ADD     R0, R1
                MOVE    @R1, R2                 ; R2: menu index
                MOVE    R2, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    0x8020, R8              ; R8: menu group
                ADD     R0, R8
                MOVE    R2, R9                  ; R9: menu index
                DECRB
                OR      0x0004, SR
                RET

; CRTROM_M_GI: R8 = CRT/ROM id -> R8 = menu group, R9 = menu index
; 0x0140 + id, Carry = 1; the id {nocrt} has no menu item (Carry = 0)
CRTROM_M_GI     INCRB
                MOVE    R8, R0                  ; R0: CRT/ROM id
                MOVE    S_MGI, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                CMP     {nocrt}, R0
                RBRA    _MGI_OK, !Z
                MOVE    S_NONE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                AND     0xFFFB, SR
                RET
_MGI_OK         MOVE    0x0140, R2              ; R2: menu index
                ADD     R0, R2
                MOVE    R2, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    0x8030, R8              ; R8: menu group
                ADD     R0, R8
                MOVE    R2, R9                  ; R9: menu index
                DECRB
                OR      0x0004, SR
                RET

; CRTROM_MLST_GET: the next pair of the script TB_MLST: R8 = CRT/ROM id,
; R9 = status, Carry = 1; at its end (0xFFFF) R8 and R9 stay, Carry = 0
CRTROM_MLST_GET INCRB
                MOVE    R8, R2
                MOVE    R9, R3
                MOVE    S_MLST, R8
                SYSCALL(puts, 1)
                MOVE    TB_MLST, R0
                MOVE    @R0, R1                 ; R1: next pair
                CMP     0xFFFF, @R1
                RBRA    _MLST_END, Z
                MOVE    @R1++, R2               ; R2: CRT/ROM id
                MOVE    @R1++, R3               ; R3: status
                MOVE    R1, @R0
                MOVE    R2, R8
                RSUB    PRHEX, 1
                MOVE    R3, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R2, R8
                MOVE    R3, R9
                DECRB
                OR      0x0004, SR
                RET
_MLST_END       MOVE    S_NONE, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R2, R8
                MOVE    R3, R9
                DECRB
                AND     0xFFFB, SR
                RET

; OPTM_SET, M2M$SET_SETTING, OPTM_SELECT: print R8 and R9, change nothing
OPTM_SET        INCRB
                MOVE    S_OSET, R0
                RBRA    TB_PR89, 1
M2M$SET_SETTING INCRB
                MOVE    S_SETS, R0
                RBRA    TB_PR89, 1
OPTM_SELECT     INCRB
                MOVE    S_OSEL, R0
TB_PR89         MOVE    R8, R1
                MOVE    R0, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R1, R8
                DECRB
                RET

; OPTM_SHOW: changes nothing
OPTM_SHOW       MOVE    R8, @--SP
                MOVE    S_OSHOW, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; FATAL: print, then back to the driver with its SP and register bank
FATAL           MOVE    R9, R10
                MOVE    R8, R11
                MOVE    S_FATAL, R8
                SYSCALL(puts, 1)
                MOVE    R11, R8
                SYSCALL(puts, 1)
                MOVE    R10, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    TB_SR, R8
                MOVE    @R8, SR
                MOVE    TB_SP, R8
                MOVE    @R8, SP
                RBRA    _FATALRET, 1

; ----------------------------------------------------------------------------
; The real code (instrumented)
; ----------------------------------------------------------------------------
{gk}

; ----------------------------------------------------------------------------
; Strings
; ----------------------------------------------------------------------------
S_BEGIN         .ASCII_W "== BEGIN ==\n"
S_DONE          .ASCII_W "DONE\n"
S_CASE          .ASCII_W "CASE"
S_REGS          .ASCII_W "REGS"
S_REGSF         .ASCII_W "REGS FATAL"
S_SP            .ASCII_W " SP"
S_BANK          .ASCII_W " BANK"
S_CFM           .ASCII_W "CFM"
S_BANKS         .ASCII_W "BANKS"
S_DIRECT        .ASCII_W "DIRECT"
S_BLANK         .ASCII_W " "
S_NONE          .ASCII_W " NONE"
S_CFMA          .ASCII_W "CFM ADDR"
S_CFMD          .ASCII_W "CFM DATA"
S_WRITE         .ASCII_W "WRITE"
S_VDACT         .ASCII_W "VD_ACTIVE"
S_MNTGET        .ASCII_W "VD_MNT_ST_GET"
S_MENGRP        .ASCII_W "VD_MENGRP"
S_MGI           .ASCII_W "CRTROM_M_GI"
S_MLST          .ASCII_W "CRTROM_MLST_GET"
S_OSET          .ASCII_W "OPTM_SET"
S_SETS          .ASCII_W "SET_SETTING"
S_OSEL          .ASCII_W "OPTM_SELECT"
S_OSHOW         .ASCII_W "OPTM_SHOW"
S_FATAL         .ASCII_W "FATAL "
ERR_FATAL_INST  .ASCII_W "ERR_FATAL_INST"

; ----------------------------------------------------------------------------
; Variables and data
; ----------------------------------------------------------------------------
TB_IDX          .DW     {idx}
{patterns}
{scripts}
CASES
{cases}
                .DW     0xFFFF

; the row of the current case: keep the order of the columns of CASES
TB_ENTRY        .BLOCK  1                       ; 0: _OPTM_GK_MNT, 1: _CRTROM
OPTM_DIRECT     .BLOCK  1
VDRIVES_NUM     .BLOCK  1
TB_MNT          .BLOCK  1                       ; mount status of the drives
TB_MGFAIL       .BLOCK  1                       ; drive without a menu item
TB_PATTERN      .BLOCK  1                       ; banks before the call
OPTM_CUR_SEL    .BLOCK  1
TB_IN8          .BLOCK  1                       ; R8 and R9 before the call
TB_IN9          .BLOCK  1
TB_MLST         .BLOCK  1                       ; script of CRTROM_MLST_GET

TB_ROW          .BLOCK  1
TB_CNO          .BLOCK  1
TB_SP           .BLOCK  1
TB_SR           .BLOCK  1
TB_REGS         .BLOCK  15
TB_CFM_ADDR     .BLOCK  1
TB_CFM_DATA     .BLOCK  1
TB_BANKS        .BLOCK  32
"""

HOOK = r"""TB_W_R{n}          MOVE    SR, @--SP
                MOVE    R8, @--SP
                MOVE    R{n}, R8
                RSUB    TB_WRITE, 1
                MOVE    @SP++, R8
                MOVE    @SP++, SR
                RET"""

ROWLEN = 10


def words(ws):
    return ", ".join("0x%04X" % (w & 0xFFFF) for w in ws)


def testbed(code):
    gk = instrument(code)
    if gk is None:
        return None
    scripts, cases = [], []
    for n, c in enumerate(CASES):
        pairs = [w for p in c["script"] for w in p] + [0xFFFF]
        scripts.append("TB_SCRIPT_%-5d .DW     %s" % (n, words(pairs)))
        row = ["0x%04X" % w for w in (c["entry"], c["direct"], c["ndrv"], c["mnt"], c["mgfail"])]
        row += ["TB_PAT_%d" % c["pat"], "0x%04X" % c["cur"],
                "0x%04X" % c["crt"][0], "0x%04X" % c["crt"][1], "TB_SCRIPT_%d" % n]
        assert len(row) == ROWLEN
        cases.append(" " * 16 + ".DW     " + ", ".join(row))
    regs = {"r%d" % i: "0x%04X" % v for i, v in enumerate(REGS_IN) if i not in (8, 9)}
    return TESTBED.format(
        sysdef=QSYSDEF, mondef=MONDEF, sel_sel=SEL_SEL, inst4=INST4, instb=INSTB,
        rowlen=ROWLEN, junk="0x%04X" % JUNK, nocrt=NOCRT, idx=words(IDX),
        hooks="\n\n".join(HOOK.format(n=n) for n in range(8)),
        patterns="\n".join("%-15s .DW     %s" % ("TB_PAT_%d" % i if k == 0 else "", words(p[k:k + 8]))
                           for i, p in enumerate(PATTERNS) for k in range(0, 32, 8)),
        scripts="\n".join(scripts), cases="\n".join(cases), gk=gk, **regs)


# ---------------------------------------------------------------------------
# The model
# ---------------------------------------------------------------------------
def hx(*ws):
    return " ".join("%04X" % (w & 0xFFFF) for w in ws)


def model_case(n, c):
    """Trace of one case as the routines behave without the skip of the
    redraw"""
    out = ["CASE " + hx(n, c["entry"], c["direct"])]
    banks = list(PATTERNS[c["pat"]])
    addr = data = JUNK
    fatal = None
    if c["entry"] == 0:
        out.append("VD_ACTIVE " + hx(c["ndrv"]))
        if c["ndrv"] == 0:
            redraw = False                                  # no drives: return
        else:
            redraw = True
            out.append("VD_MNT_ST_GET " + hx(c["mnt"]))
            for d in range(c["ndrv"]):
                if d == c["mgfail"]:
                    out.append("VD_MENGRP " + hx(d) + " NONE")
                    fatal = INST4
                    break
                idx, v = IDX[d], (c["mnt"] >> d) & 1
                out.append("VD_MENGRP " + hx(d, idx))
                out.append("OPTM_SET " + hx(idx, v))
                addr = idx >> 4
                data = banks[addr & 31]
                out.append("CFM ADDR " + hx(addr))
                data = data | (1 << (idx & 15)) if v else data & ~(1 << (idx & 15))
                banks[addr & 31] = data
                out.append("CFM DATA " + hx(addr, data))
    else:
        redraw = True
        cid, st = c["crt"]
        script = list(c["script"])
        while True:
            if cid == NOCRT:
                out.append("CRTROM_M_GI " + hx(cid) + " NONE")
                fatal = INSTB
                break
            idx = 0x0140 + cid
            out.append("CRTROM_M_GI " + hx(cid, idx))
            out.append("OPTM_SET " + hx(idx, st))
            out.append("SET_SETTING " + hx(idx, st))
            if not script:
                out.append("CRTROM_MLST_GET NONE")
                break
            cid, st = script.pop(0)
            out.append("CRTROM_MLST_GET " + hx(cid, st))
    if fatal is not None:
        out.append("FATAL ERR_FATAL_INST " + hx(fatal))
        out.append("REGS FATAL")
    else:
        if redraw:
            out.append("OPTM_SHOW")
            out.append("OPTM_SELECT " + hx(c["cur"], SEL_SEL))
        regs = list(REGS_IN)
        if c["entry"] == 1:
            regs[8], regs[9] = c["crt"]
        out.append("REGS " + hx(*regs) + " SP 0000 BANK 0000")
    out.append("CFM " + hx(addr, data))
    out.append("BANKS " + hx(*banks))
    out.append("DIRECT " + hx(c["direct"]))
    return out


REDRAW = re.compile(r"^OPTM_(SHOW|SELECT)\b")


def model(skip):
    """skip = False: the routines before the change. skip = True: the same
    trace without OPTM_SHOW and OPTM_SELECT while OPTM_DIRECT is not zero."""
    out = ["== BEGIN =="]
    for n, c in enumerate(CASES):
        lines = model_case(n, c)
        if skip and c["direct"] != 0:
            lines = [l for l in lines if not REDRAW.match(l)]
        out += lines
    out.append("DONE")
    return out


# ---------------------------------------------------------------------------
# Assemble, run, compare
# ---------------------------------------------------------------------------
def run(code, work, name="hidden_redraw_tb"):
    tb = testbed(code)
    if tb is None:
        return None, "assembly failed: a write to memory that the trace routines do not know"
    src = os.path.join(work, name + ".asm")
    open(src, "w").write(tb)
    r = subprocess.run([ASM, name + ".asm"], cwd=work, capture_output=True, text=True, timeout=120)
    out = os.path.join(work, name + ".out")
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, "assembly failed: " + (r.stdout + r.stderr)[-2000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return None, "emulator timeout"
    lines = [l.rstrip() for l in r.stdout.replace("\r", "").split("\n") if l.strip()]
    if "== BEGIN ==" in lines:
        lines = lines[lines.index("== BEGIN =="):]
    if "DONE" in lines:
        lines = lines[:lines.index("DONE") + 1]
    open(os.path.join(work, name + ".got"), "w").write("\n".join(lines) + "\n")
    return lines, ""


def compare(got, exp):
    """Returns None if equal, else a short description of the first difference."""
    if got is None:
        return "no output"
    case = "?"
    for i in range(max(len(got), len(exp))):
        g = got[i] if i < len(got) else "<missing>"
        e = exp[i] if i < len(exp) else "<missing>"
        if e.startswith("CASE"):
            case = e
        if g.upper() != e.upper():
            return "%s: expected %r, got %r" % (case, e, g)
    return None


def by_case(lines):
    """{case number: lines of the case}"""
    cases, cur = {}, None
    for l in lines:
        if l.startswith("CASE "):
            cur = int(l.split()[1], 16)
            cases[cur] = []
        if cur is not None and l != "DONE":
            cases[cur].append(l.upper())
    return cases


def differential(new, old):
    """The real code against the code without the skip, case by case: the
    same trace with OPTM_DIRECT zero, without the redraw lines otherwise."""
    n, o = by_case(new), by_case(old)
    if sorted(n) != list(range(len(CASES))) or sorted(o) != list(range(len(CASES))):
        return "the traces do not contain every case"
    for k, c in enumerate(CASES):
        want = o[k] if c["direct"] == 0 else [l for l in o[k] if not REDRAW.match(l)]
        if n[k] != want:
            return "case %d (OPTM_DIRECT %04X) differs" % (k, c["direct"])
    return None


# ---------------------------------------------------------------------------
# Mutants: each must make the comparison fail
# ---------------------------------------------------------------------------
I = "\n" + " " * 16      # a new line of code, indented like options.asm

SKIP = ("_OPTM_GK_MNT_S  MOVE    OPTM_DIRECT, R8         ; invisible session of a" + I
        + "CMP     0, @R8                  ; keyboard shortcut?" + I
        + "RBRA    _OPTM_GK_MNT_R, !Z      ; yes: no redraw" + I
        + "RSUB    OPTM_SHOW, 1")
NOSKIP = "_OPTM_GK_MNT_S  RSUB    OPTM_SHOW, 1"
CHECK = "MOVE    OPTM_DIRECT, R8" + I + "CMP     0, @R8" + I + "RBRA    _OPTM_GK_MNT_R, !Z"
# the same check at the start of a routine, where R8 is an input and R0 is free
CHECK0 = "MOVE    OPTM_DIRECT, R0" + I + "CMP     0, @R0" + I + "RBRA    _OPTM_GK_MNT_R, !Z"


def replace(*pairs):
    def mutate(code):
        for old, new in pairs:
            if code.count(old) != 1:
                return None
            code = code.replace(old, new)
        return code
    return mutate


never_skipped = replace((SKIP, NOSKIP))

MUTANTS = [
    ("never_skipped", never_skipped),                       # the code before the change
    ("skipped_always", replace(("RBRA    _OPTM_GK_MNT_R, !Z      ; yes: no redraw",
                                "RBRA    _OPTM_GK_MNT_R, 1"))),
    ("condition_inverted", replace(("RBRA    _OPTM_GK_MNT_R, !Z      ; yes: no redraw",
                                    "RBRA    _OPTM_GK_MNT_R, Z"))),
    ("only_direct_1", replace(("CMP     0, @R8                  ; keyboard shortcut?", "CMP     1, @R8"),
                              ("RBRA    _OPTM_GK_MNT_R, !Z      ; yes: no redraw",
                               "RBRA    _OPTM_GK_MNT_R, Z"))),
    ("updates_skipped_mnt", replace(("_OPTM_GK_MNT    SYSCALL(enter, 1)\n",
                                     "_OPTM_GK_MNT    SYSCALL(enter, 1)" + I + CHECK0 + "\n"))),
    ("updates_skipped_crtrom", replace(("_OPTM_GK_CRTROM SYSCALL(enter, 1)\n",
                                        "_OPTM_GK_CRTROM SYSCALL(enter, 1)" + I + CHECK0 + "\n"))),
    ("select_not_skipped", replace(("RBRA    _OPTM_GK_MNT_R, !Z      ; yes: no redraw",
                                    "RBRA    _TB_MUT_SEL, !Z"),
                                   ("\n                MOVE    OPTM_CUR_SEL, R8\n",
                                    "\n_TB_MUT_SEL     MOVE    OPTM_CUR_SEL, R8\n"))),
    ("show_not_skipped", replace((SKIP, "_OPTM_GK_MNT_S  RSUB    OPTM_SHOW, 1" + I + CHECK))),
]


def main():
    keep = "--keep" in sys.argv[1:]
    for tool in (ASM, EMU, MON):
        if not os.path.exists(tool):
            sys.exit("missing %s (see README.md: build the QNICE toolchain first)" % tool)
    work = tempfile.mkdtemp(prefix="hidden_redraw_test.")
    fails = 0
    try:
        code = real_code()
        exp, exp_old = model(True), model(False)
        open(os.path.join(work, "model.exp"), "w").write("\n".join(exp) + "\n")
        open(os.path.join(work, "model_without_skip.exp"), "w").write("\n".join(exp_old) + "\n")
        got, err = run(code, work)
        diff = compare(got, exp)
        if diff:
            print("FAIL: real code: %s %s" % (diff, err))
            fails += 1
        else:
            print("PASS: real code, %d cases (_OPTM_GK_MNT and _OPTM_GK_CRTROM), %d lines of trace"
                  % (len(CASES), len(exp)))
        old = never_skipped(code)
        if old is None:
            diff = compare(got, exp_old)
            print("INFO: the skip is not found; the real code %s the trace of the model without "
                  "the skip%s" % ("produces" if not diff else "does not produce",
                                  "" if not diff else ": " + diff))
        got_old, err = run(old, work, "hidden_redraw_old") if old else (None, "")
        diff = compare(got_old, exp_old) if old else "the skip is not found: adapt SKIP"
        if diff:
            print("FAIL: the code without the skip does not produce the trace of the model "
                  "without the skip: %s %s" % (diff, err))
            fails += 1
        else:
            print("PASS: the code without the skip (as before the change) produces the trace of "
                  "the model without the skip")
        diff = differential(got or [], got_old or [])
        if diff:
            print("FAIL: real code against the code without the skip: %s" % diff)
            fails += 1
        else:
            print("PASS: real code against the code without the skip: identical with OPTM_DIRECT "
                  "zero, without OPTM_SHOW and OPTM_SELECT otherwise")
        for name, mutate in MUTANTS:
            mcode = mutate(code)
            if mcode is None:
                print("FAIL: mutant %s: its pattern is not found exactly once: adapt the mutant" % name)
                fails += 1
                continue
            got, err = run(mcode, work, "hidden_redraw_mut")
            diff = compare(got, exp)
            if err.startswith("assembly failed"):
                print("FAIL: mutant %s does not assemble: %s" % (name, err))
                fails += 1
            elif diff:
                print("PASS: mutant %-22s caught (%s)" % (name, diff[:110]))
            else:
                print("FAIL: mutant %s not caught" % name)
                fails += 1
    finally:
        if keep:
            print("work folder: %s" % work)
        else:
            shutil.rmtree(work, ignore_errors=True)
    print("RESULT: PASS" if fails == 0 else "RESULT: FAIL (%d)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
