#!/usr/bin/env python3
"""
Headless test: a file that the core rejects changes neither the mounted image
nor its menu line (HANDLE_MOUNTING and LOAD_IMAGE in M2M/rom/shell.asm).

When the user selects a file, LOAD_IMAGE asks the core callback
PREP_LOAD_IMAGE whether it accepts the file (the C64 core rejects a disk
image of the wrong size and a .crt that is too large). As long as the core
has not accepted the file, nothing may change:

  * The file handle of a virtual drive (HNDL_VD_FILES) must not be opened
    with the file. FLUSH_CACHE writes the drive back through this handle: if
    a rejected file were opened with it, the drive would keep its old image,
    but the next save of the core would overwrite the rejected file, in the
    size of the rejected file. So LOAD_IMAGE checks a disk image with the
    scratch file handle _DIRBR_FH first.
  * The menu line (the slot of the drive or CRT/ROM in OPTM_HEAP and its
    "%s is replaced" flag) must keep the name of what is really mounted or
    loaded, so HANDLE_MOUNTING writes it only after LOAD_IMAGE succeeded.

The test also checks HM_KEYREAD, the flag that tells HELP_MENU whether an
invisible session of a keyboard shortcut read a key of the user: HANDLE_MOUNTING
sets it before the file browser, before the error window of a failed SD card
mount and before the error window of a failed LOAD_IMAGE, and nowhere else.

The script cuts the real code out of the sources on every run: all of
HANDLE_MOUNTING and LOAD_IMAGE without the progress bar and the copy loop
(its head up to the progress bar and its end from _LI_FREAD_EOF on). It links
the code against stubs that print every access to the file system (f32_fopen
with the file handle it gets, f32_mnt_sd), to the core (PREP_LOAD_IMAGE with
handle, context and menu group, UNLOAD_CRTROM), to the hardware (CSR of the
CRT/ROM devices, VD_STROBE_IM) and to the menu (OPTM_SET, OPTM_SHOW, the error
message on the screen, and _OPTM_GK_MNT with the value of OPTM_DIRECT: after a
CRT/ROM load it brings the lines and menu bits of the drives in line with
their mount status, also in direct mode); the two stubs that read a key of
the user (the file browser and the wait for Space) print HM_KEYREAD. The
keyboard register of the wait for Return is a variable of the testbed. The
script runs one session
of cases in the QNICE emulator: a mounted, an empty and a preselected drive
(VD_NEXT_DISK, direct mode), a loaded and an empty CRT/ROM line, rejected
files with and without a message followed by Run/Stop or by an accepted file,
names that fit into the menu line exactly or that are cut with an ellipsis,
files that cannot be opened, and the paths that read no key: a drive that is
still saving, unmounting a drive and unloading a CRT/ROM with Space, each
with HM_KEYREAD clear and set at the start, and a failed SD card mount
followed by a preselected file. After every case the testbed prints the
registers, the file size in every file handle (which file it holds), the
mount status, the CRT/ROM load flags, HM_KEYREAD, the folder of VD_NEXT_DISK
(VD_NXT_INFO) and every menu line slot word by word. An independent model of
the intended behavior computes the expected output. Then the script applies
mutants to the extracted code, among them the reversal of each of the two
halves of the fix, a missing or misplaced HM_KEYREAD, and a call of
_OPTM_GK_MNT that is missing or skipped in direct mode; each mutant must make
the comparison fail.

Usage:  python3 mount_reject_test.py        (ends with "RESULT: PASS")
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

SHELL = os.path.join(REPO, "M2M", "rom", "shell.asm")
MENU = os.path.join(REPO, "M2M", "rom", "menu.asm")
M2MSYSDEF = os.path.join(REPO, "M2M", "rom", "sysdef.asm")
QSYSDEF = os.path.join(QNICE, "dist_kit", "sysdef.asm")


def equ(path, name):
    for line in open(path):
        m = re.match(r"^%s\s+\.EQU\s+(0x[0-9A-Fa-f]+|\d+)" % re.escape(name), line)
        if m:
            return int(m.group(1), 0)
    sys.exit("no %s in %s" % (name, path))


KEY_SELECT = equ(MENU, "OPTM_KEY_SELECT")
KEY_SELALT = equ(MENU, "OPTM_KEY_SELALT")
CTX = [equ(M2MSYSDEF, "CTX_MOUNT_DISKIMG"), equ(M2MSYSDEF, "CTX_LOAD_ROM")]
CSR_STATUS = equ(M2MSYSDEF, "CRTROM_CSR_STATUS")
CSR_LDNG = equ(M2MSYSDEF, "CRTROM_CSR_ST_LDNG")
CSR_ERR = equ(M2MSYSDEF, "CRTROM_CSR_ST_ERR")
FDH_SIZE = equ(QSYSDEF, "FAT32$FDH_STRUCT_SIZE")
FDH_LO, FDH_HI = equ(QSYSDEF, "FAT32$FDH_SIZE_LO"), equ(QSYSDEF, "FAT32$FDH_SIZE_HI")
DEV_SIZE = equ(QSYSDEF, "FAT32$DEV_STRUCT_SIZE")
DEV_CLUS = equ(QSYSDEF, "FAT32$DEV_AD_1STCLUS_LO"), equ(QSYSDEF, "FAT32$DEV_AD_1STCLUS_HI")

# The testbed: two virtual drives, two CRT/ROMs, a menu line slot of DX words
VDRIVES_BUFS = [0x0101, 0x0102]          # device of each virtual drive
CRTROM_MAN_DEV = [0x0104, 0x0103]        # device of each CRT/ROM
VDRIVES_NUM, OPTM_SCOUNT, DX = 2, 3, 20  # CRT/ROM id i uses slot 2 + 3 + i
NSLOTS = VDRIVES_NUM + OPTM_SCOUNT + len(CRTROM_MAN_DEV)
CTX_DATA = 0x00D7                        # SF_CONTEXT_DATA (menu group id)
SDGEN, CLUS, FBSTACK = 0x0003, (0x1234, 0x0056), 0x0ABC   # for VD_NXT_INFO
FOPEN_ERR = 0x00EE                       # error code of f32_fopen: not found
HANDLES = ["VD0", "VD1", "RM0", "RM1", "SCR"]
NEVER = (0xDEAD, 0xBEEF)                 # size in a handle that was never opened

# The files on the SD card: name -> (size low word, size high word). The core
# (the stub of PREP_LOAD_IMAGE) decides by the size, like the C64 core does:
# bit 15 of the high word set = rejected with the low byte as error code, and
# with a message unless bit 14 is set; otherwise accepted with the image type
# "high word AND 3".
LONG = "A_VERY_LONG_DISK_IMAGE_NAME.D64"  # longer than the menu line
NAME18 = "ABCDEFGHIJKLMN.PRG"             # exactly DX - 2 characters
NAME19 = "ABCDEFGHIJKLMNO.PRG"            # one more: ellipsis
FILES = {
    "A.D64": (0xAB00, 0x0002), "B.D64": (0x8000, 0x000D), "C.D64": (0x3333, 0x0003),
    "BAD1.D64": (0x1111, 0x8001), "BAD2.D64": (0x2222, 0xC003), LONG: (0x4444, 0x0001),
    "OLD.CRT": (0x9999, 0x0000), "BIG.CRT": (0x5555, 0x8002), "GOOD.CRT": (0x6666, 0x0000),
    NAME18: (0x7777, 0x0000), NAME19: (0x7878, 0x0000),
}
MISSING = ["MISSING.D64", "MISSING.CRT"]
NAMES = list(FILES) + MISSING
RUNSTOP = None
SDMNT_ERR = 0x00ED                       # error code of a failed f32_mnt_sd
KEPT = 0x5A5A                            # HM_KEYREAD set by an earlier session

# The session: (mode, id, key, preselected file, direct mode, what the file
# browser returns one call after the other[, options]). Mode 0 = virtual
# drive, 1 = CRT/ROM. At the start drive 0 is mounted with A.D64, drive 1 is
# empty, CRT/ROM 1 (.crt) is loaded with OLD.CRT and CRT/ROM 0 (.prg) is not
# loaded. Options (default 0): flag = HM_KEYREAD at the start of the case
# (the real code only ever writes 1, so KEPT shows that it was not written),
# dirty = the write cache of the drive is dirty, sdfail = the SD card is not
# mounted and so many mount attempts fail before one succeeds.
CASES = [
    (0, 0, KEY_SELECT, None, 0, ["BAD1.D64", RUNSTOP]),   # mounted, rejected, Run/Stop
    (0, 0, KEY_SELECT, None, 0, ["BAD2.D64", "B.D64"]),   # rejected (no message), accepted
    (0, 1, KEY_SELECT, None, 0, ["BAD1.D64", RUNSTOP]),   # empty drive, rejected, Run/Stop
    (0, 1, KEY_SELECT, None, 0, [LONG]),                  # first mount, name with ellipsis
    (1, 1, KEY_SELECT, None, 0, ["BIG.CRT", RUNSTOP]),    # loaded .crt, rejected, Run/Stop
    (1, 1, KEY_SELECT, None, 0, ["BIG.CRT", "GOOD.CRT"]), # rejected, then accepted
    (1, 0, KEY_SELECT, None, 0, ["BAD2.D64", RUNSTOP]),   # empty CRT/ROM line, rejected
    (1, 0, KEY_SELECT, None, 0, [NAME18]),                # name fits exactly
    (1, 0, KEY_SELECT, None, 1, [NAME19]),                # ellipsis, direct mode
    (0, 1, 0, "C.D64", 1, []),                            # Next disk: preselected, accepted
    (0, 1, 0, "BAD2.D64", 1, [RUNSTOP]),                  # preselected, rejected: browser
    (0, 0, KEY_SELECT, None, 0, [RUNSTOP]),               # nothing selected
    (0, 0, KEY_SELECT, None, 0, ["A.D64"]),               # mounted, accepted
    (0, 0, KEY_SELECT, None, 0, ["MISSING.D64"]),         # cannot be opened: fatal
    (1, 1, KEY_SELECT, None, 0, ["MISSING.CRT"]),         # cannot be opened: fatal
    # paths that read no key leave HM_KEYREAD alone
    (0, 1, 0, "C.D64", 1, [], dict(flag=KEPT)),           # Next disk: preselected, accepted
    (0, 0, KEY_SELECT, None, 0, [], dict(dirty=1)),       # drive still saving
    (0, 0, KEY_SELECT, None, 1, [], dict(dirty=1, flag=KEPT)),  # same, direct mode
    (0, 0, KEY_SELALT, None, 0, []),                      # unmount drive 0 with Space
    (0, 1, KEY_SELALT, None, 0, [], dict(flag=KEPT)),     # unmount drive 1 with Space
    (1, 1, KEY_SELALT, None, 0, []),                      # unload CRT/ROM 1 with Space
    (1, 0, KEY_SELALT, None, 0, [], dict(flag=KEPT)),     # unload CRT/ROM 0 with Space
    # the error window of a failed SD card mount waits for Return
    (0, 1, 0, "C.D64", 1, [], dict(sdfail=1)),            # then the preselected file
]


def fields(case):
    """(mode, id, key, pre, direct, script, flag, dirty, sdfail) of a case"""
    opt = dict(flag=0, dirty=0, sdfail=0)
    opt.update(case[6] if len(case) > 6 else {})
    return tuple(case[:6]) + (opt["flag"], opt["dirty"], opt["sdfail"])


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


def real_code():
    # the wait for Return after a failed SD card mount reads the keyboard
    # register directly: here it is a variable of the testbed
    return {
        "hm": cut(SHELL, r"^HANDLE_MOUNTING\s+SYSCALL\(enter, 1\)",
                  end=r"^; Load a disk or CRT/ROM image").replace("M2M$KEYBOARD", "TB_KEYB"),
        "li": cut(SHELL, r"^LOAD_IMAGE\s+SYSCALL\(enter, 1\)", end=r"^\s+; For showing a progress bar"),
        "tail": cut(SHELL, r"^_LI_FREAD_EOF\s", through=r"^\s+RET\b"),
    }


TESTBED = r"""
#include "{sysdef}"
#include "{mondef}"
#include "{m2msysdef}"

OPTM_KEY_SELECT .EQU    {key_select}
OPTM_KEY_SELALT .EQU    {key_selalt}
                .ORG    0x8000

; ----------------------------------------------------------------------------
; Driver: one row = mode, id, key, preselected file or 0, direct mode, script
; of the file browser, HM_KEYREAD, dirty write cache, failing SD card mounts;
; 0xFFFF ends the list
; ----------------------------------------------------------------------------
START           MOVE    S_BEGIN, R8
                SYSCALL(puts, 1)
                MOVE    CASES, R6
                XOR     R7, R7                  ; R7: case number
_CASE           MOVE    @R6++, R0               ; R0: mode
                CMP     0xFFFF, R0
                RBRA    _DONE, Z
                MOVE    @R6++, R1               ; R1: drive or CRT/ROM id
                MOVE    @R6++, R2               ; R2: key
                MOVE    HM_PRESELECT, R4
                MOVE    @R6++, @R4
                MOVE    OPTM_DIRECT, R4
                MOVE    @R6++, @R4
                MOVE    TB_SCRPOS, R4
                MOVE    @R6++, @R4
                MOVE    HM_KEYREAD, R4
                MOVE    @R6++, @R4
                MOVE    TB_DIRTY, R4
                MOVE    @R6++, @R4
                MOVE    TB_SDFAIL, R4
                MOVE    @R6++, @R4
                CMP     0, @R4                  ; failing mounts: the SD card
                RBRA    _CASE_1, Z              ; is not mounted
                MOVE    HANDLE_DEV, R4
                MOVE    0, @R4
_CASE_1

                MOVE    S_CASE, R8
                SYSCALL(puts, 1)
                MOVE    R7, R8
                RSUB    PRHEX, 1
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    R2, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)

                MOVE    TB_SP, R4               ; for FATAL and the SP check
                MOVE    SP, @R4
                MOVE    TB_SR, R4
                MOVE    SR, @R4
                MOVE    R1, R8
                MOVE    R2, R9
                MOVE    R0, R10
                MOVE    0xB11B, R11
                MOVE    0xC12C, R12
                RSUB    HANDLE_MOUNTING, 1
                MOVE    SR, R5                  ; R5: SR after the call
                MOVE    SAVE, R4
                MOVE    R8, @R4++
                MOVE    R9, @R4++
                MOVE    R10, @R4++
                MOVE    R11, @R4++
                MOVE    R12, @R4++
                MOVE    SP, @R4

                MOVE    S_REGS, R8
                SYSCALL(puts, 1)
                MOVE    SAVE, R4
                MOVE    5, R3
_PRSAVE         MOVE    @R4++, R8
                RSUB    PRHEX, 1
                SUB     1, R3
                RBRA    _PRSAVE, !Z
                MOVE    S_SP, R8                ; SP difference
                SYSCALL(puts, 1)
                MOVE    @R4, R8
                MOVE    TB_SP, R3
                SUB     @R3, R8
                RSUB    PRHEX, 1
                MOVE    S_BANK, R8              ; register bank difference
                SYSCALL(puts, 1)
                MOVE    TB_SR, R3
                MOVE    R5, R8
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

_DUMP           RSUB    DUMP, 1
                ADD     1, R7
                RBRA    _CASE, 1

_DONE           MOVE    S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; Dump of the state after a case
; ----------------------------------------------------------------------------
DUMP            INCRB
                MOVE    S_HNDL, R8              ; file size in every handle
                SYSCALL(puts, 1)
                MOVE    TB_HANDLES, R0
                MOVE    5, R1
_DH             MOVE    @R0++, R2
                MOVE    R2, R3
                ADD     FAT32$FDH_SIZE_LO, R3
                MOVE    @R3, R8
                RSUB    PRHEX, 1
                MOVE    R2, R3
                ADD     FAT32$FDH_SIZE_HI, R3
                MOVE    @R3, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _DH, !Z
                SYSCALL(crlf, 1)

                MOVE    S_MNT, R8               ; mount status, load flags
                SYSCALL(puts, 1)
                MOVE    TB_MNT, R0
                MOVE    @R0++, R8
                RSUB    PRHEX, 1
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    S_LDF, R8
                SYSCALL(puts, 1)
                MOVE    CRTROM_MAN_LDF, R0
                MOVE    @R0++, R8
                RSUB    PRHEX, 1
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    S_PRE, R8
                SYSCALL(puts, 1)
                MOVE    HM_PRESELECT, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                MOVE    S_FLAG, R8
                SYSCALL(puts, 1)
                MOVE    HM_KEYREAD, R0
                MOVE    @R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)

                MOVE    S_NXT, R8               ; folders of VD_NEXT_DISK
                SYSCALL(puts, 1)
                MOVE    VD_NXT_INFO, R0
                MOVE    8, R1
_DN             MOVE    @R0++, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _DN, !Z
                SYSCALL(crlf, 1)

                MOVE    TB_HEAP, R0             ; every menu line slot
                XOR     R2, R2
_DS             MOVE    S_SLOT, R8
                SYSCALL(puts, 1)
                MOVE    R2, R8
                RSUB    PRHEX, 1
                MOVE    {dx}, R1
_DSW            MOVE    @R0++, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _DSW, !Z
                SYSCALL(crlf, 1)
                ADD     1, R2
                CMP     {nslots}, R2
                RBRA    _DS, !Z
                DECRB
                RET

; print a blank and R8 as four hex digits; keeps all registers
PRHEX           MOVE    R8, @--SP
                MOVE    S_BLANK, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                SYSCALL(puthex, 1)
                RET

; print "FLAG <HM_KEYREAD>" on a line of its own; keeps all registers
PRFLAG          MOVE    R8, @--SP
                MOVE    S_FLAGL, R8
                SYSCALL(puts, 1)
                MOVE    HM_KEYREAD, R8
                MOVE    @R8, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; print a blank and the name of the file handle in R8; keeps all registers
PRHID           INCRB
                MOVE    R8, R0
                MOVE    TB_HANDLES, R1
                MOVE    TB_HNAMES, R2
                MOVE    5, R3
_PHL            CMP     @R1++, R0
                RBRA    _PHF, Z
                ADD     1, R2
                SUB     1, R3
                RBRA    _PHL, !Z
                MOVE    S_HUNK, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                DECRB
                RET
_PHF            MOVE    @R2, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                DECRB
                RET

; R8: file name -> R8: pointer to its size (low word, high word) or 0
FINDFILE        INCRB
                MOVE    R8, R0
                MOVE    R9, R3
                MOVE    R10, R4
                MOVE    TB_FILES, R1
_FF_LOOP        MOVE    @R1++, R2
                CMP     0, R2
                RBRA    _FF_NONE, Z
                MOVE    R0, R8
                MOVE    R2, R9
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _FF_HIT, Z
                ADD     2, R1
                RBRA    _FF_LOOP, 1
_FF_HIT         MOVE    R1, R8
                RBRA    _FF_RET, 1
_FF_NONE        XOR     R8, R8
_FF_RET         MOVE    R3, R9
                MOVE    R4, R10
                DECRB
                RET

; ----------------------------------------------------------------------------
; Stubs
; ----------------------------------------------------------------------------

; SELECT_FILE: prints HM_KEYREAD (the file browser reads keys), then the
; next entry of the script: a file name or 0xFFFF (Run/Stop)
SELECT_FILE     INCRB
                RSUB    PRFLAG, 1
                MOVE    TB_SCRPOS, R0
                MOVE    @R0, R1
                MOVE    @R1++, R2               ; R2: entry
                MOVE    R1, @R0
                CMP     0, R2
                RBRA    _SF_END, Z
                MOVE    S_SELECT, R8
                SYSCALL(puts, 1)
                CMP     0xFFFF, R2
                RBRA    _SF_STOP, Z
                MOVE    R2, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R2, R8                  ; R8: file name
                XOR     R9, R9                  ; R9: 0 = file selected
                DECRB
                RET
_SF_STOP        MOVE    S_RUNSTOP, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                XOR     R8, R8
                MOVE    2, R9                   ; R9: 2 = Run/Stop
                DECRB
                RET
_SF_END         MOVE    S_SEND, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; f32_mnt_sd (monitor): "SDMOUNT <error code>"; fails while TB_SDFAIL is not
; zero, otherwise the device handle is mounted again
f32_mnt_sd      INCRB
                MOVE    R8, R0                  ; R0: device handle
                MOVE    TB_SDFAIL, R1
                MOVE    {sdmnt_err}, R9
                CMP     0, @R1
                RBRA    _FM_FAIL, !Z
                MOVE    1, @R0                  ; mounted
                XOR     R9, R9
                RBRA    _FM_PRINT, 1
_FM_FAIL        SUB     1, @R1
_FM_PRINT       MOVE    S_SDMOUNT, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET

; f32_fopen (monitor): the size of the file goes into the file handle
f32_fopen       INCRB
                MOVE    R8, R0                  ; R0: device handle
                MOVE    R9, R1                  ; R1: file handle
                MOVE    R10, R2                 ; R2: file name
                MOVE    R11, R3                 ; R3: separator
                MOVE    S_FOPEN, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                RSUB    PRHID, 1
                MOVE    S_BLANK, R8
                SYSCALL(puts, 1)
                MOVE    R2, R8
                SYSCALL(puts, 1)
                CMP     HANDLE_DEV, R0
                RBRA    _FO_1, Z
                MOVE    S_BADDEV, R8
                SYSCALL(puts, 1)
_FO_1           CMP     0, R3
                RBRA    _FO_2, Z
                MOVE    S_BADSEP, R8
                SYSCALL(puts, 1)
_FO_2           SYSCALL(crlf, 1)
                MOVE    R2, R8
                RSUB    FINDFILE, 1
                MOVE    {fopen_err}, R10
                CMP     0, R8
                RBRA    _FO_RET, Z
                MOVE    @R8++, R4
                MOVE    @R8, R5
                MOVE    R1, R8
                ADD     FAT32$FDH_SIZE_LO, R8
                MOVE    R4, @R8
                MOVE    R1, R8
                ADD     FAT32$FDH_SIZE_HI, R8
                MOVE    R5, @R8
                XOR     R10, R10
_FO_RET         MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R3, R11
                DECRB
                RET

; PREP_LOAD_IMAGE (core): decides by the size in the file handle
PREP_LOAD_IMAGE INCRB
                MOVE    R8, R0                  ; R0: file handle
                MOVE    R9, R1                  ; R1: context
                MOVE    R10, R2                 ; R2: menu group id
                MOVE    S_PREP, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHID, 1
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    R2, R8
                RSUB    PRHEX, 1
                MOVE    R0, R3
                ADD     FAT32$FDH_SIZE_HI, R3
                MOVE    @R3, R3                 ; R3: size high word
                MOVE    R3, R4
                AND     0x8000, R4
                RBRA    _PLI_REJ, !Z
                MOVE    S_ACCEPT, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                XOR     R8, R8
                MOVE    R3, R9
                AND     0x0003, R9              ; R9: image type
                RBRA    _PLI_RET, 1
_PLI_REJ        MOVE    S_REJECT, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R3, R8
                AND     0x00FF, R8              ; R8: error code
                MOVE    S_WARN, R9              ; R9: message
                AND     0x4000, R3
                RBRA    _PLI_RET, Z
                XOR     R9, R9                  ; R9: no message
_PLI_RET        MOVE    R2, R10
                DECRB
                RET

; HANDLE_CRTROM_M: R8 = device, R9 = CRT/ROM id, R10 = file handle
HANDLE_CRTROM_M INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    S_PARSE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R1, R8
                RSUB    PRHEX, 1
                MOVE    R2, R8
                RSUB    PRHID, 1
                SYSCALL(crlf, 1)
                MOVE    CRTROM_MAN_LDF, R3      ; loaded
                ADD     R1, R3
                MOVE    1, @R3
                XOR     R8, R8
                XOR     R9, R9
                MOVE    R2, R10
                DECRB
                RET

; VD_STROBE_IM: R8 = drive, R9/R10 = size, R11 = read-only, R12 = type
VD_STROBE_IM    INCRB
                MOVE    R8, R0
                MOVE    S_STROBE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                MOVE    R10, R8
                RSUB    PRHEX, 1
                MOVE    R11, R8
                RSUB    PRHEX, 1
                MOVE    R12, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    TB_MNT, R1
                ADD     R0, R1
                MOVE    0, @R1
                MOVE    R9, R2
                OR      R10, R2
                RBRA    _VSI_RET, Z
                MOVE    1, @R1
_VSI_RET        MOVE    R0, R8
                DECRB
                RET

VD_MOUNTED      INCRB
                MOVE    TB_MNT, R0
                ADD     R8, R0
                AND     0xFFFB, SR
                CMP     0, @R0
                RBRA    _VDM_RET, Z
                OR      0x0004, SR
_VDM_RET        DECRB
                RET

VD_DRV_READ     CMP     VD_CACHE_DIRTY, R9
                RBRA    _VDR_OK, Z
                MOVE    S_VDRD, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
_VDR_OK         MOVE    TB_DIRTY, R8            ; the write cache of the drive
                MOVE    @R8, R8
                RET

; menu index of a drive: 10 + drive, of a CRT/ROM: 40 + id
VD_MENGRP       MOVE    R8, R9
                ADD     10, R9
                OR      0x0004, SR
                RET
CRTROM_M_GI     MOVE    R8, R9
                ADD     40, R9
                OR      0x0004, SR
                RET

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

; CRTROM_CSR_W: R8 = device, R9 = register, R10 = value
CRTROM_CSR_W    INCRB
                MOVE    R8, R0
                MOVE    S_CSRW, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                MOVE    R10, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET

; UNLOAD_CRTROM (core): "UNLOAD <id>", unloads it and reports it (Carry = 1)
UNLOAD_CRTROM   INCRB
                MOVE    R8, R0
                MOVE    S_UNLD, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    CRTROM_MAN_LDF, R1
                ADD     R0, R1
                MOVE    0, @R1
                MOVE    R0, R8
                DECRB
                OR      0x0004, SR
                RET

; KEYB$GETKEY: prints HM_KEYREAD (a key of the user is read), returns Space
KEYB$GETKEY     RSUB    PRFLAG, 1
                MOVE    M2M$KEY_SPACE, R8
                RET

; WORD2HEXSTR: prints the error code that HANDLE_MOUNTING shows
WORD2HEXSTR     INCRB
                MOVE    R8, R0
                MOVE    S_ERRCODE, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    0, @R9
                DECRB
                RET

; SCR$PRINTSTR: reports the message of PREP_LOAD_IMAGE (or a copy of it)
SCR$PRINTSTR    INCRB
                MOVE    R8, R0
                MOVE    R9, R1
                MOVE    R10, R2
                MOVE    S_WARN, R9
                SYSCALL(strcmp, 1)
                CMP     0, R10
                RBRA    _SPS_RET, !Z
                MOVE    S_SHOWMSG, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
_SPS_RET        MOVE    R0, R8
                MOVE    R1, R9
                MOVE    R2, R10
                DECRB
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

SCR$OSM_O_ON
SCR$OSM_OFF
FRAME_FULLSCR
SCR$GOTOXY
SCR$OSM_M_ON
SCR$CLRINNER
WAIT333MS
FB_RE_INIT
HANDLE_IO
KEYB$SCAN
SAVE_DEVSEL
RESTORE_DEVSEL
VD_MNT_ST_SET   RET

; _OPTM_GK_MNT: "GK_MNT <OPTM_DIRECT>", so that the mode of the call is visible;
; changes nothing, like the real routine (enter and leave)
_OPTM_GK_MNT    INCRB
                MOVE    R8, R0
                MOVE    S_GKMNT, R8
                SYSCALL(puts, 1)
                MOVE    OPTM_DIRECT, R8
                MOVE    @R8, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R0, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; The real code
; ----------------------------------------------------------------------------
{hm}
{li}
; LOAD_IMAGE would show the progress bar and copy the file from here on
; (the CSR write of the CRT/ROM mode falls through to this point):
; print the file handle and the device of the copy, then continue with the
; real end of LOAD_IMAGE
_LI_PROGRESS    MOVE    S_COPY, R8
                SYSCALL(puts, 1)
                MOVE    R5, R8
                RSUB    PRHID, 1
                MOVE    R0, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                RBRA    _LI_FREAD_EOF, 1

{tail}

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
S_HNDL          .ASCII_W "HNDL"
S_MNT           .ASCII_W "MNT"
S_LDF           .ASCII_W " LDF"
S_PRE           .ASCII_W " PRE"
S_FLAG          .ASCII_W " FLAG"
S_FLAGL         .ASCII_W "FLAG"
S_SDMOUNT       .ASCII_W "SDMOUNT"
S_NXT           .ASCII_W "NXT"
S_SLOT          .ASCII_W "SLOT"
S_BLANK         .ASCII_W " "
S_HUNK          .ASCII_W " UNKNOWN"
S_SELECT        .ASCII_W "SELECT "
S_RUNSTOP       .ASCII_W "RUNSTOP"
S_SEND          .ASCII_W "SCRIPT END"
S_FOPEN         .ASCII_W "FOPEN"
S_BADDEV        .ASCII_W " WRONG DEVICE HANDLE"
S_BADSEP        .ASCII_W " WRONG SEPARATOR"
S_PREP          .ASCII_W "PREP"
S_ACCEPT        .ASCII_W " ACCEPT"
S_REJECT        .ASCII_W " REJECT"
S_COPY          .ASCII_W "COPY"
S_PARSE         .ASCII_W "PARSE"
S_STROBE        .ASCII_W "STROBE"
S_VDRD          .ASCII_W "UNEXPECTED VD_DRV_READ"
S_OSET          .ASCII_W "OPTM_SET"
S_SHOW          .ASCII_W "SHOW"
S_GKMNT         .ASCII_W "GK_MNT"
S_CSRW          .ASCII_W "CSRW"
S_UNLD          .ASCII_W "UNLOAD"
S_ERRCODE       .ASCII_W "ERRCODE"
S_SHOWMSG       .ASCII_W "SHOWMSG"
S_FATAL         .ASCII_W "FATAL "
S_WARN          .ASCII_W "The core rejects this file."
S_HVD0          .ASCII_W " VD0"
S_HVD1          .ASCII_W " VD1"
S_HRM0          .ASCII_W " RM0"
S_HRM1          .ASCII_W " RM1"
S_HSCR          .ASCII_W " SCR"

LOG_STR_FILE    .ASCII_W "LOG FILE "
LOG_STR_MOUNT   .ASCII_W "LOG MOUNT "
LOG_STR_LOADOK  .ASCII_W "LOG LOADOK\n"
LOG_STR_ROMOK   .ASCII_W "LOG ROMOK\n"
LOG_STR_SD      .ASCII_W "UNEXPECTED SD CARD CHANGE\n"
ERR_FATAL_FNF   .ASCII_W "ERR_FATAL_FNF"
ERR_FATAL_INST  .ASCII_W "ERR_FATAL_INST"
ERR_FATAL_INSTD
ERR_FATAL_INST2
ERR_FATAL_INST3
ERR_FATAL_INST7
ERR_FATAL_INSTA .ASCII_W ""
ERR_MOUNT       .ASCII_W "ERR_MOUNT"
ERR_BROWSE_UNKN .ASCII_W "ERR_BROWSE_UNKN"
ERR_MOUNT_RET
ERR_CODE
NEWLINE
STR_SPACE       .ASCII_W ""

{names}

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------
TB_HANDLES      .DW     FH_VD0, FH_VD1, FH_RM0, FH_RM1, _DIRBR_FH
TB_HNAMES       .DW     S_HVD0, S_HVD1, S_HRM0, S_HRM1, S_HSCR
HNDL_VD_FILES   .DW     FH_VD0, FH_VD1
HNDL_RM_FILES   .DW     FH_RM0, FH_RM1
{handles}
VDRIVES_BUFS    .DW     {vdrives_bufs}
VDRIVES_NUM     .DW     {vdrives_num}
CRTROM_MAN_DEV  .DW     {crtrom_man_dev}
CRTROM_MAN_LDF  .DW     0, 1
TB_MNT          .DW     1, 0
OPTM_SCOUNT     .DW     {optm_scount}
SCR$OSM_O_DX    .DW     {dx}
OPTM_HEAP       .DW     TB_HEAP
HANDLE_DEV      .DW     {handle_dev}
SD_CHANGED      .DW     0
VD_SDGEN        .DW     {sdgen}
FB_LASTCALLER   .DW     0xFFFF
FB_STACK        .DW     {fbstack}
SF_CONTEXT      .DW     0
SF_CONTEXT_DATA .DW     {ctx_data}
HM_PRESELECT    .DW     0
OPTM_DIRECT     .DW     0
HM_KEYREAD      .DW     0
TB_DIRTY        .DW     0
TB_SDFAIL       .DW     0
TB_KEYB         .DW     0                       ; M2M$KEYBOARD: Return pressed
VD_NXT_INFO     .DW     {nxt}
SCRATCH_HEX     .BLOCK  5
LOAD_IMAGE_TYPE .BLOCK  1
TB_SCRPOS       .BLOCK  1
TB_SP           .BLOCK  1
TB_SR           .BLOCK  1
SAVE            .BLOCK  6
TB_FILES
{files}
                .DW     0
{scripts}
CASES
{cases}
                .DW     0xFFFF
{heap}
"""


def words(ws):
    return ", ".join("0x%04X" % (w & 0xFFFF) for w in ws)


def label(name):
    return "F_%d" % NAMES.index(name)


def slot_of(mode, cid):
    return cid if mode == 0 else VDRIVES_NUM + OPTM_SCOUNT + cid


def initial_state():
    slots = []
    for i in range(NSLOTS):
        w = [0x0100 + 0x20 * i + k for k in range(DX)]   # no characters
        text = {slot_of(0, 0): "A.D64", slot_of(1, 1): "OLD.CRT"}.get(i)
        if text:
            w[:len(text) + 1] = [ord(c) for c in text] + [0]
        w[DX - 1] = 1                                    # "%s is replaced"
        slots.append(w)
    return {"handles": {"VD0": FILES["A.D64"], "VD1": NEVER, "RM0": NEVER,
                        "RM1": FILES["OLD.CRT"], "SCR": NEVER},
            "mnt": [1, 0], "ldf": [0, 1], "nxt": [0x00E0 + k for k in range(8)], "slots": slots}


def testbed(code, work):
    # the monitor entry points, except f32_fopen and f32_mnt_sd, which are
    # stubbed
    mondef = os.path.join(work, "monitor_tb.def")
    open(mondef, "w").write("".join(l for l in open(os.path.join(QNICE, "dist_kit", "monitor.def"))
                                    if not re.match(r"^(f32_fopen|f32_mnt_sd)\s", l)))
    st = initial_state()
    handles = []
    for lbl, hid in zip(["FH_VD0", "FH_VD1", "FH_RM0", "FH_RM1", "_DIRBR_FH"], HANDLES):
        w = [0] * FDH_SIZE
        w[FDH_LO], w[FDH_HI] = st["handles"][hid]
        handles.append("%-15s .DW     %s" % (lbl, words(w)))
    dev = [0] * DEV_SIZE
    dev[0] = 1                                    # the SD card is mounted
    dev[DEV_CLUS[0]], dev[DEV_CLUS[1]] = CLUS     # active directory
    scripts, cases = [], []
    for n, case in enumerate(CASES):
        mode, cid, key, pre, direct, script, flag, dirty, sdfail = fields(case)
        entries = [0xFFFF if s is RUNSTOP else label(s) for s in script] + [0]
        scripts.append("SCRIPT_%d%s .DW     %s" % (n, " " * (7 - len(str(n))),
                                                  ", ".join(e if isinstance(e, str) else "0x%04X" % e
                                                            for e in entries)))
        cases.append("                .DW     0x%04X, 0x%04X, 0x%04X, %s, 0x%04X, SCRIPT_%d, "
                     "0x%04X, 0x%04X, 0x%04X"
                     % (mode, cid, key, label(pre) if pre else "0", direct, n, flag, dirty, sdfail))
    heap = ["%-15s .DW     %s" % ("TB_HEAP" if i == 0 else "", words(s)) for i, s in enumerate(st["slots"])]
    return TESTBED.format(
        sysdef=QSYSDEF, mondef=mondef, m2msysdef=M2MSYSDEF,
        key_select=KEY_SELECT, key_selalt=KEY_SELALT, dx=DX, nslots=NSLOTS, fopen_err=FOPEN_ERR,
        sdmnt_err=SDMNT_ERR,
        names="\n".join('%-15s .ASCII_W "%s"' % (label(n), n) for n in NAMES),
        handles="\n".join(handles),
        vdrives_bufs=words(VDRIVES_BUFS), vdrives_num=VDRIVES_NUM,
        crtrom_man_dev=words(CRTROM_MAN_DEV), optm_scount=OPTM_SCOUNT,
        handle_dev=words(dev), sdgen=SDGEN, fbstack=FBSTACK, ctx_data=CTX_DATA,
        nxt=words(st["nxt"]),
        files="\n".join("                .DW     %s, 0x%04X, 0x%04X" % (label(n), lo, hi)
                         for n, (lo, hi) in FILES.items()),
        scripts="\n".join(scripts), cases="\n".join(cases), heap="\n".join(heap),
        **code)


# ---------------------------------------------------------------------------
# The model
# ---------------------------------------------------------------------------
def core(name):
    """What the stub of PREP_LOAD_IMAGE returns: (error code, message flag)
    for a rejected file, (0, image type) for an accepted one."""
    lo, hi = FILES[name]
    if hi & 0x8000:
        return hi & 0x00FF, 0 if hi & 0x4000 else 1
    return 0, hi & 0x0003


def write_slot(slot, name):
    """The menu line slot after a successful mount or load: the name, or
    one character more than fits (that triggers the ellipsis), plus the zero
    terminator, and the "%s is replaced" flag cleared."""
    codes = [ord(c) for c in name]
    fit = DX - 2
    if len(codes) <= fit:
        slot[:len(codes) + 1] = codes + [0]
    else:
        slot[:fit + 2] = codes[:fit + 1] + [0]
    slot[DX - 1] = 0


def model():
    h = lambda v: "%04X" % (v & 0xFFFF)
    st = initial_state()
    sdgen = SDGEN
    out = ["== BEGIN =="]
    for n, case in enumerate(CASES):
        mode, cid, key, pre, direct, script, flag, dirty, sdfail = fields(case)
        out.append("CASE %s %s %s %s" % (h(n), h(mode), h(cid), h(key)))
        script = list(script)
        menu = (10 if mode == 0 else 40) + cid
        dev = (VDRIVES_BUFS if mode == 0 else CRTROM_MAN_DEV)[cid]
        own = ("VD%d" if mode == 0 else "RM%d") % cid      # file handle of the drive or CRT/ROM
        check = "SCR" if mode == 0 else own                # a disk image is checked first
        fatal, mount, show = False, True, not direct        # the OSM is shown at the end
        if mode == 1 and key == KEY_SELALT and st["ldf"][cid]:
            out.append("UNLOAD %s" % h(cid))               # Space unloads the CRT/ROM
            st["ldf"][cid] = 0
            out.append("OPTM_SET %s 0000" % h(menu))
            mount, show = False, True                       # redrawn and shown in any mode
        elif mode == 0 and st["mnt"][cid] and not dirty and key == KEY_SELALT:
            out.append("STROBE %s 0000 0000 0000 0000" % h(cid))   # Space unmounts the drive
            st["mnt"][cid] = 0
            mount = False
        elif mode == 0 and st["mnt"][cid]:
            out.append("OPTM_SET %s 0001" % h(menu))       # the drive stays selected
            mount = not dirty                               # still saving: nothing else
        if mount and sdfail:                                # the SD card is not mounted
            for _ in range(sdfail):                         # error window, wait for Return
                out.append("SDMOUNT %s" % h(SDMNT_ERR))
                out.append("ERRCODE %s" % h(SDMNT_ERR))
                sdgen += 1
                flag = 1
            out.append("SDMOUNT 0000")
            sdgen += 1
        while mount:
            if pre:
                name, pre = pre, None
            else:
                flag = 1                                    # the file browser reads keys
                out.append("FLAG %s" % h(flag))
                name = script.pop(0)
                if name is RUNSTOP:                         # the menu line shows the old state
                    out.append("SELECT RUNSTOP")
                    out.append("OPTM_SET %s %s" % (h(menu), h(st["mnt"][cid] if mode == 0
                                                             else st["ldf"][cid])))
                    break
                out.append("SELECT " + name)
            out.append("LOG FILE " + name)
            out.append("FOPEN %s %s" % (check, name))
            if name not in FILES:                           # fatal: the C64 core would stop here
                if mode == 1:
                    out.append("CSRW %s %s %s" % (h(dev), h(CSR_STATUS), h(CSR_ERR)))
                out.append("FATAL ERR_FATAL_FNF " + h(CSR_ERR if mode == 1 else FOPEN_ERR))
                fatal = True
                break
            st["handles"][check] = FILES[name]
            err, val = core(name)
            out.append("PREP %s %s %s %s" % (check, h(CTX[mode]), h(CTX_DATA),
                                             "REJECT" if err else "ACCEPT"))
            if err:                                         # message, Space, file browser again
                out.append("ERRCODE " + h(err))
                if val:
                    out.append("SHOWMSG")
                flag = 1                                    # the wait for Space reads keys
                out.append("FLAG %s" % h(flag))
                continue
            if mode == 0:                                   # now with the handle of the drive
                out.append("FOPEN %s %s" % (own, name))
                st["handles"][own] = FILES[name]
                out.append("PREP %s %s %s ACCEPT" % (own, h(CTX[mode]), h(CTX_DATA)))
            else:
                out.append("CSRW %s %s %s" % (h(dev), h(CSR_STATUS), h(CSR_LDNG)))
            out.append("COPY %s %s" % (own, h(dev)))
            if mode == 0:
                out.append("LOG LOADOK")
            else:
                out.append("LOG ROMOK")
                out.append("PARSE %s %s %s" % (h(dev), h(cid), own))
                st["ldf"][cid] = 1
            write_slot(st["slots"][slot_of(mode, cid)], name)
            if mode == 0:
                lo, hi = FILES[name]
                out.append("STROBE %s %s %s 0000 %s" % (h(cid), h(lo), h(hi), h(val)))
                st["mnt"][cid] = 1
                st["nxt"][4 * cid:4 * cid + 4] = [sdgen, CLUS[0], CLUS[1], FBSTACK]
                out.append("LOG MOUNT " + h(cid))
            else:
                out.append("OPTM_SET %s 0001" % h(menu))
                out.append("GK_MNT %s" % h(direct))         # drives, also in direct mode
            break
        if fatal:
            out.append("REGS FATAL")
        else:
            if show:
                out.append("SHOW")
            out.append("REGS %s %s %s B11B C12C SP 0000 BANK 0000" % (h(cid), h(key), h(mode)))
        out.append("HNDL " + " ".join("%s %s" % (h(st["handles"][k][0]), h(st["handles"][k][1]))
                                      for k in HANDLES))
        out.append("MNT %s %s LDF %s %s PRE 0000 FLAG %s"
                   % tuple(h(v) for v in st["mnt"] + st["ldf"] + [flag]))
        out.append("NXT " + " ".join(h(v) for v in st["nxt"]))
        for i, s in enumerate(st["slots"]):
            out.append("SLOT %s %s" % (h(i), " ".join(h(v) for v in s)))
    out.append("DONE")
    return out


# ---------------------------------------------------------------------------
# Assemble, run, compare
# ---------------------------------------------------------------------------
def run(code, work):
    src = os.path.join(work, "mount_reject_tb.asm")
    open(src, "w").write(testbed(code, work))
    r = subprocess.run([ASM, "mount_reject_tb.asm"], cwd=work, capture_output=True, text=True,
                       timeout=120)
    out = os.path.join(work, "mount_reject_tb.out")
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, "assembly failed: " + (r.stdout + r.stderr)[-2000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=60)
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
    case = "?"
    for i in range(max(len(got), len(exp))):
        g = got[i] if i < len(got) else "<missing>"
        e = exp[i] if i < len(exp) else "<missing>"
        if e.startswith("CASE"):
            case = e
        if g.upper() != e.upper():
            return "%s: expected %r, got %r" % (case, e, g)
    return None


# ---------------------------------------------------------------------------
# Mutants: each must make the comparison fail
# ---------------------------------------------------------------------------
def unfix_load_image(code):
    """LOAD_IMAGE without the check of a disk image with the scratch handle."""
    li, n = re.subn(r"\n\n[ \t]+; Check the file with PREP_LOAD_IMAGE before it is opened with\n"
                    r".*?(?=\n[ \t]+MOVE[ \t]+HNDL_VD_FILES, R9\n)", "", code["li"], flags=re.S)
    return dict(code, li=li) if n == 1 else None


def unfix_handle_mounting(code):
    """HANDLE_MOUNTING that writes the menu line before it calls LOAD_IMAGE."""
    hm = code["hm"]
    m = re.search(r"_HM_SDMOUNTED6A[ \t]+MOVE[ \t]+R9, R6[^\n]*\n(\n[ \t]+; remember the file name"
                  r".*?\n[ \t]+MOVE[ \t]+0, @R8\n)(?=\n[ \t]+RSUB[ \t]+SCR\$OSM_OFF, 1)", hm, re.S)
    if not m:
        return None
    hm = hm[:m.start(1)] + hm[m.end(1):]
    a = re.search(r"\n[ \t]+MOVE[ \t]+R8, R2[^\n]*\n(?=\n[ \t]+; load the disk image)", hm)
    if not a:
        return None
    return dict(code, hm=hm[:a.end()] + m.group(1) + hm[a.end():])


def unfix_both(code):
    c = unfix_load_image(code)
    return unfix_handle_mounting(c) if c else None


def replace(part, *pairs):
    def mutate(code):
        text = code[part]
        for old, new in pairs:
            if text.count(old) != 1:
                return None
            text = text.replace(old, new)
        return dict(code, **{part: text})
    return mutate


I = "\n" + " " * 16      # a new line of code, indented like shell.asm

MUTANTS = [
    # the reversal of the two halves of the fix and of both together
    ("unfixed_load_image", unfix_load_image),
    ("unfixed_handle_mounting", unfix_handle_mounting),
    ("unfixed_both", unfix_both),
    # the check of a disk image with the scratch file handle
    ("check_verdict_ignored",
     replace("li", ("RBRA    _LI_FREAD_RET, !Z       ; yes: drive stays untouched", "MOVE    R0, R0"))),
    ("check_with_drive_handle",
     replace("li", ("MOVE    _DIRBR_FH, R9           ; R9: scratch file handle",
                    "MOVE    HNDL_VD_FILES, R9" + I + "ADD     R1, R9" + I + "MOVE    @R9, R9"))),
    ("check_without_group",
     replace("li", ("R8: scratch file handle" + I + "MOVE    SF_CONTEXT, R9" + I + "MOVE    @R9, R9"
                    + I + "MOVE    SF_CONTEXT_DATA, R10" + I + "MOVE    @R10, R10",
                    "R8: scratch file handle" + I + "MOVE    SF_CONTEXT, R9" + I + "MOVE    @R9, R9"
                    + I + "XOR     R10, R10"))),
    ("check_open_error_ignored", replace("li", ("RBRA    _LI_OPENFATAL, !Z\n", ""))),
    # the menu line, written after LOAD_IMAGE succeeded
    ("type_saved_too_late",
     replace("hm", ("_HM_SDMOUNTED6A MOVE    R9, R6                  ; R6: disk image type\n",
                    "_HM_SDMOUNTED6A MOVE    R0, R0\n"),
             ("RSUB    SCR$OSM_OFF, 1          ; hide the big window\n\n                ; Step #5",
              "MOVE    R9, R6" + I + "RSUB    SCR$OSM_OFF, 1\n\n                ; Step #5"))),
    ("flag_not_cleared", replace("hm", ("ADD     R0, R8" + I + "MOVE    0, @R8", "ADD     R0, R8"))),
    ("no_ellipsis", replace("hm", ("MOVE    R1, R10" + I + "ADD     1, R10", "MOVE    R1, R10"))),
    ("crtrom_slot_of_drive", replace("hm", ("CMP     1, R5                   ; case (b)?", "CMP     0, R5"))),
    # HM_KEYREAD: set before each of the three key reads, and nowhere else
    ("keyread_unset_browser",
     replace("hm", (I + "MOVE    HM_KEYREAD, R9          ; the file browser reads keys"
                    + I + "MOVE    1, @R9                  ; (see shell_vars.asm)", ""))),
    ("keyread_unset_sd_error",
     replace("hm", (I + "MOVE    HM_KEYREAD, R8          ; Return is read below (see"
                    + I + "MOVE    1, @R8                  ; shell_vars.asm)", ""))),
    ("keyread_unset_load_err",
     replace("hm", (I + "MOVE    HM_KEYREAD, R8          ; Space is read below (see"
                    + I + "MOVE    1, @R8                  ; shell_vars.asm)", ""))),
    ("keyread_on_preselect",
     replace("hm", ("_HM_PRESEL      XOR     @R9, @R9",
                    "_HM_PRESEL      XOR     @R9, @R9" + I + "MOVE    HM_KEYREAD, R10" + I + "MOVE    1, @R10"))),
    ("keyread_on_entry",
     replace("hm", ("MOVE    R10, R5                 ; R5: mount mode",
                    "MOVE    R10, R5" + I + "MOVE    HM_KEYREAD, R10" + I + "MOVE    1, @R10"))),
    # _OPTM_GK_MNT after a CRT/ROM load: the call is missing, or skipped in
    # direct mode together with the updates of the drives that it makes
    ("gk_mnt_missing", replace("hm", (I + "RSUB    _OPTM_GK_MNT, 1", ""))),
    ("gk_mnt_skipped_direct",
     replace("hm", (I + "RSUB    _OPTM_GK_MNT, 1",
                    I + "MOVE    OPTM_DIRECT, R8" + I + "CMP     0, @R8" + I + "RBRA    _HM_SDMOUNTED7, !Z"
                    + I + "RSUB    _OPTM_GK_MNT, 1"))),
]


def main():
    for tool in (ASM, EMU, MON):
        if not os.path.exists(tool):
            sys.exit("missing %s (see README.md: build the QNICE toolchain first)" % tool)
    work = tempfile.mkdtemp(prefix="mount_reject_test.")
    fails = 0
    try:
        code = real_code()
        exp = model()
        got, err = run(code, work)
        diff = compare(got, exp)
        if diff:
            print("FAIL: real code: %s %s" % (diff, err))
            fails += 1
        else:
            print("PASS: real code, %d cases (HANDLE_MOUNTING and LOAD_IMAGE), %d lines of trace"
                  % (len(CASES), len(exp)))
        for name, mutate in MUTANTS:
            mcode = mutate(code)
            if mcode is None:
                print("FAIL: mutant %s: its pattern is not found exactly once: adapt the mutant" % name)
                fails += 1
                continue
            got, err = run(mcode, work)
            diff = compare(got, exp)
            if err.startswith("assembly failed"):
                print("FAIL: mutant %s does not assemble: %s" % (name, err))
                fails += 1
            elif diff:
                print("PASS: mutant %-24s caught (%s)" % (name, diff[:110]))
            else:
                print("FAIL: mutant %s not caught" % name)
                fails += 1
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("RESULT: PASS" if fails == 0 else "RESULT: FAIL (%d)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
