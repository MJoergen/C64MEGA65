#!/usr/bin/env python3
"""
Headless test: the text that <Saving> replaces in the menu line of a virtual
drive comes back to its own line (OPTM_CB_SHOW in M2M/rom/options.asm).

While the write cache of a mounted drive is dirty, its menu line shows
OPTM_S_SAVING ("<Saving>"). OPTM_CB_SHOW parks the text of the line in a
parking slot behind the "%s" slots of OPTM_HEAP and sets the "%s is replaced"
flag of the line to 2; when the cache is clean again, it copies the parked
text back. Every virtual drive has a parking slot of its own (the slot of
drive n is @OPTM_HEAP_LAST + n x @SCR$OSM_O_DX), so drives 8 and 9 can save at
the same time, and HELP_MENU reserves VDRIVES_NUM parking slots in its check
of the heap budget. The last word of a parking slot keeps the flag of the
parked text: a keyboard shortcut can mount a disk image while the menu is
invisible, so the line can still hold the bare file name that
HANDLE_MOUNTING stored (flag 0) when it is parked, and such a name must come
back as the complete line with its label.

The script cuts the real code out of the sources on every run:

  * OPTM_CB_SHOW with its helper _OPTM_CBS_REPL      (M2M/rom/options.asm)
  * the budget check of HELP_MENU, from the "%s" demand to the heap check
                                                      (M2M/rom/options.asm)
  * M2M$RPL_S                                        (M2M/rom/tools.asm)
  * the block of HANDLE_MOUNTING that stores the file name in the menu line
    slot                                             (M2M/rom/shell.asm)
  * OPTM_NL (menu.asm) and FN_ELLIPSIS (strings.asm)

It links them against stubs for everything else: the virtual drives
(VD_DRVNO, VD_MOUNTED, VD_DRV_READ; the last two also overwrite R9 to R12),
the CRT/ROM items, SUBMENU_SUMMARY and OPTM_SUMM_SCAN, LOG_HEAP2 (prints the
demand in R10) and FATAL. The emulator has no config.vhd device, so the
selector registers M2M$RAMROM_DEV and M2M$RAMROM_4KWIN become RAM variables
in the extracted OPTM_CB_SHOW, the menu groups sit in the M2M$RAMROM_DATA
window, and the three reads of a string window (OPTM_S_MOUNT, OPTM_S_SAVING,
OPTM_S_CRTROM, taken from config.vhd) become a call of a stub that returns
the string of the selected device and window.

Two configurations run in the QNICE emulator: the real numbers of this core
(two drives, menu width 27) and three drives with a width of 20. Each first
runs the budget block for several counts of drives, submenus, CRT/ROMs and
widths (heap large enough, exactly large enough, one word too small; LOG_HEAP2,
OPTM_HEAP_LAST, FATAL with the overrun, registers), and then scripted
sessions of mounts, dirty and clean write caches and redraws of the menu
(every "%s" line through OPTM_CB_SHOW): two drives that save at the same
time and finish in every order, one drive alone, redraws while dirty, names
that fit, get an ellipsis or have the longest form that HANDLE_MOUNTING
stores, unmounted drives, loaded and empty CRT/ROM lines and submenu lines,
and bare file names that are parked (also on two drives at once and next to
a parked complete line).
After every step the testbed dumps all slots, the parking slots and a guard
area before and behind them word by word. An independent model of the
intended behavior computes the expected trace. Then the script applies
mutants to the extracted code; each must make the comparison fail.

Usage:  python3 saving_text_test.py        (ends with "RESULT: PASS")
        python3 saving_text_test.py --keep (keeps the work folder with the
                                            testbed, the trace and the model)
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
SHELL = os.path.join(REPO, "M2M", "rom", "shell.asm")
TOOLS = os.path.join(REPO, "M2M", "rom", "tools.asm")
STRINGS = os.path.join(REPO, "M2M", "rom", "strings.asm")
MENU = os.path.join(REPO, "M2M", "rom", "menu.asm")
M2MSYSDEF = os.path.join(REPO, "M2M", "rom", "sysdef.asm")
QSYSDEF = os.path.join(QNICE, "dist_kit", "sysdef.asm")
CONFIG = os.path.join(REPO, "CORE", "vhdl", "config.vhd")


def equ(path, name):
    for line in open(path):
        m = re.match(r"^%s\s+\.EQU\s+(0x[0-9A-Fa-f]+|\d+)" % re.escape(name), line)
        if m:
            return int(m.group(1), 0)
    sys.exit("no %s in %s" % (name, path))


def vhdl_string(name):
    m = re.search(r"^\s*constant\s+%s\s*:\s*string\s*:=\s*\"([^\"]*)\"" % name, open(CONFIG).read(), re.M)
    if not m:
        sys.exit("no %s in %s" % (name, CONFIG))
    return m.group(1)


OPTM_SUBMENU = equ(MENU, "OPTM_SUBMENU")
IR_ITEMS, IR_STDSEL = equ(MENU, "OPTM_IR_ITEMS"), equ(MENU, "OPTM_IR_STDSEL")
STRUCTSIZE = equ(MENU, "OPTM_STRUCTSIZE")
RAMROM_DATA = equ(M2MSYSDEF, "M2M$RAMROM_DATA")
S_MOUNT, S_SAVING, S_CRTROM = (vhdl_string("OPTM_S_MOUNT"), vhdl_string("OPTM_S_SAVING"),
                               vhdl_string("OPTM_S_CRTROM"))
REGION = 0xC000                    # the guard, the slots and the parking slots
BHEAP = 0xE000                     # OPTM_HEAP in the budget cases (never written)
MARK = [0xA88A, 0xB99B, 0xC00C, 0xB11B, 0xC12C]   # R8 to R12 before every call
DRV, CRT = 0, 1
MOUNT, UNMOUNT, DIRTY, DRAW, SESSION = 1, 2, 3, 4, 5
KEEP = "--keep" in sys.argv[1:]


# ---------------------------------------------------------------------------
# The configurations: counts, the menu and the scripted sessions
# ---------------------------------------------------------------------------
class Config:
    def __init__(self, name, vdrives, crtroms, submenus, dx, budget, sessions):
        self.name, self.v, self.c, self.dx = name, vdrives, len(crtroms), dx
        self.s = len(submenus)
        # the menu: (text, group id); every "%s" line goes through the callback
        menu = [("Drives", 0x0001)]
        menu += [(" %d:%%s" % (8 + n), 0x00D0 + n) for n in range(vdrives)]
        menu += [(" %s:%%s" % t, 0x00E0 + i) for i, t in enumerate(crtroms)]
        for i, (title, items) in enumerate(submenus):
            menu += [(" %s: %%s" % title, OPTM_SUBMENU)]
            menu += [("  " + it, 0x0020 + i) for it in items]
            menu += [(" Back", OPTM_SUBMENU | 0x0001)]
        menu += [(" Close Menu", 0x0002)]
        self.menu = menu
        # the budget cases (drives, submenus, CRT/ROMs, width, heap size); the
        # last one is this configuration with a heap that is exactly large
        # enough: it leaves OPTM_HEAP and OPTM_HEAP_LAST for the sessions
        demand = (2 * self.v + self.s + self.c) * dx
        self.budget = [(v, s, c, w, size, BHEAP) for v, s, c, w, size in budget]
        self.budget.append((self.v, self.s, self.c, dx, demand, REGION + dx))
        self.heap = REGION + dx
        self.last = self.heap + (self.v + self.s + self.c) * dx
        self.rows = 1 + (self.v + self.s + self.c) + self.v + 1
        self.sessions = sessions

    def lines(self):
        return [(i, t) for i, (t, g) in enumerate(self.menu) if "%s" in t]

    def names(self):
        return sorted({st[3] for st in self.steps() if st[3]})

    def steps(self):
        out = []
        for n, (title, steps) in enumerate(self.sessions):
            out.append((SESSION, n, 0, None))
            out += steps
        return out


def mount(i, name):
    return (MOUNT, DRV, i, name)


def load(i, name):
    return (MOUNT, CRT, i, name)


def unmount(i):
    return (UNMOUNT, DRV, i, None)


def unload(i):
    return (UNMOUNT, CRT, i, None)


def dirty(i, v=1):
    return (DIRTY, i, v, None)


def clean(i):
    return (DIRTY, i, 0, None)


D = (DRAW, 0, 0, None)


def sessions_two(dx):
    """Sessions for two drives; dx is the menu width."""
    fit = dx - 2 - 3                          # longest name that fits behind " 8:"
    n_fit = ("ABCDEFGHIJKLMNOPQRSTUVWXYZ"[:fit - 4] + ".D64")
    n_ell = ("ELLIPSIS-NAME-FOR-DRIVE-NINE"[:fit - 3] + ".D64")   # one too long
    n_25 = ("STORED-AS-IT-IS-BY-THE-SHELL"[:dx - 2 - 4] + ".D64")  # dx - 2 characters
    n_long = "THE-LONGEST-FORM-THAT-HANDLE-MOUNTING-STORES.D64"
    assert len(n_fit) == fit and len(n_ell) == fit + 1 and len(n_25) == dx - 2 and len(n_long) > dx
    return [
        ("all lines empty", [D]),
        ("the reported defect: 8 and 9 save, 8 finishes first", [
            mount(0, "GAME-A.D64"), mount(1, "DISK-B.D64"), D,
            dirty(0), dirty(1), D, clean(0), D, clean(1), D]),
        ("9 finishes first", [dirty(0), dirty(1), D, clean(1), D, clean(0), D]),
        ("both finish in the same redraw", [dirty(0), dirty(1), D, clean(0), clean(1), D]),
        ("8 parks first, 9 later, 8 finishes first", [
            dirty(0), D, dirty(1), D, clean(0), D, clean(1), D]),
        ("9 parks first, 8 later, 9 finishes first", [
            dirty(1), D, dirty(0), D, clean(1), D, clean(0), D]),
        ("drive 8 alone", [dirty(0), D, clean(0), D]),
        ("drive 9 alone, redraws while dirty, a second cycle", [
            dirty(1), D, D, D, clean(1), D, D, dirty(1), D, clean(1), D]),
        ("a name that fits exactly and one with an ellipsis", [
            mount(0, n_fit), mount(1, n_ell), D, dirty(0), dirty(1), D, D,
            clean(1), D, clean(0), D]),
        ("names of dx - 2 characters and the longest form", [
            mount(0, n_long), mount(1, n_25), D, dirty(1), dirty(0), D,
            clean(0), D, clean(1), D, dirty(0), D, clean(0), D]),
        ("an empty drive and CRT/ROM lines in between", [
            dirty(0), D, unmount(1), D, load(0, "GAME.PRG"), D, dirty(1), D,
            clean(0), D, load(1, "CART.CRT"), unload(0), D, clean(1),
            mount(1, "DISK-C.D64"), D, dirty(1), D, dirty(0), D, unload(1), D,
            clean(1), clean(0), D]),
        ("a new image on a drive whose text is parked", [
            dirty(0), D, mount(0, "NEW.D64"), clean(0), D, dirty(0), D, clean(0), D]),
        # a keyboard shortcut mounts while the menu is invisible: the slot
        # still holds the bare file name (flag 0) when the drive is dirty at
        # the next redraw
        ("a name stored by a shortcut is parked", [
            mount(0, "BY-SHORTCUT.D64"), dirty(0), D, clean(0), D]),
        ("the same with the ellipsis name and with the longest form", [
            mount(1, n_ell), dirty(1), D, D, clean(1), D, mount(0, n_long), dirty(0), D, clean(0), D]),
        ("both drives park a name, finish together and one after the other", [
            mount(0, "SHORTCUT-8.D64"), mount(1, "SHORTCUT-9.D64"), dirty(0), dirty(1), D,
            clean(0), clean(1), D, mount(0, n_25), mount(1, n_long), dirty(1), dirty(0), D,
            clean(1), D, clean(0), D]),
        ("a parked name and a parked complete line at the same time", [
            mount(1, "LINE-9.D64"), D, mount(0, "NAME-8.D64"), dirty(0), dirty(1), D,
            clean(1), D, clean(0), D, dirty(0), D, clean(0), D]),
    ]


def sessions_three():
    return [
        ("all lines empty", [D]),
        ("three drives save, finish in the order 10, 8, 9", [
            mount(0, "EIGHT.D64"), mount(1, "NINE.D81"), mount(2, "TEN.G64"), D,
            dirty(0), dirty(1), dirty(2), D, clean(2), D, clean(0), D, clean(1), D]),
        ("the order 9, 10, 8 with an ellipsis on drive 10", [
            mount(2, "A-LONG-NAME-OF-TEN.D64"), D, dirty(2), D, dirty(1), dirty(0), D,
            clean(1), D, clean(2), D, clean(0), D]),
        ("loaded and empty CRT/ROM line in between", [
            load(0, "X.CRT"), dirty(1), D, unload(0), D, clean(1), D]),
        ("names stored by shortcuts on 9 (longest form) and 10, a complete line on 8", [
            mount(2, "TEN-BY-KEY.D64"), mount(1, "NINE-BY-A-SHORTCUT-KEY.D81"), dirty(2), dirty(0),
            dirty(1), D, clean(0), D, clean(2), D, clean(1), D]),
    ]


CONFIGS = [
    Config("2 drives, width 27", 2, ["PRG", "CRT"],
           [("Model", ["PAL C64", "NTSC C64"]), ("Kernal", ["Standard", "JiffyDOS", "GS"])], 27,
           [(2, 18, 2, 27, 830), (2, 18, 2, 27, 648), (2, 18, 2, 27, 647),
            (1, 3, 1, 20, 300), (1, 3, 1, 20, 119), (3, 5, 2, 30, 390), (3, 5, 2, 30, 389),
            (0, 4, 1, 25, 125), (0, 4, 1, 25, 124), (0, 0, 0, 27, 0), (4, 0, 0, 16, 127)],
           sessions_two(27)),
    Config("3 drives, width 20", 3, ["CRT"], [("SID", ["6581", "8580"])], 20,
           [(2, 18, 2, 27, 648), (3, 1, 1, 20, 160), (3, 1, 1, 20, 159)],
           sessions_three()),
]


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


def one_line(path, pattern):
    got = [l for l in open(path).read().split("\n") if re.match(pattern, l)]
    if len(got) != 1:
        sys.exit("%r is not exactly once in %s" % (pattern, path))
    return got[0] + "\n"


def real_code():
    cb = cut(OPTIONS, r"^OPTM_CB_SHOW\s+SYSCALL\(enter, 1\)", end=r"^_OPTM_CBS_REPL\s")
    cb += cut(OPTIONS, r"^_OPTM_CBS_REPL\s", through=r"^\s+RET\b")
    # the selectors of the config.vhd device become RAM variables, and the
    # reads of the three string windows ask the stub TB_WINDOW for the string
    for hw, tb in (("M2M$RAMROM_DEV,", "TB_RAMROM_DEV,"), ("M2M$RAMROM_4KWIN,", "TB_4KWIN,")):
        if cb.count(hw) < 4:
            sys.exit("OPTM_CB_SHOW does not use %s as expected any more: adapt the test" % hw)
        cb = cb.replace(hw, tb)
    cb, n = re.subn(r"(MOVE[ \t]+M2M\$CFG_OPTM_(?:MSTR|SSTR|CRSTR), @R3[^\n]*\n[ \t]+)"
                    r"MOVE[ \t]+M2M\$RAMROM_DATA, R8", r"\1RSUB    TB_WINDOW, 1", cb)
    if n != 3:
        sys.exit("OPTM_CB_SHOW does not read the three string windows as expected: adapt the test")
    return {
        "cb": cb,
        "rpl": cut(TOOLS, r"^M2M\$RPL_S\s+SYSCALL\(enter, 1\)", through=r"^_M2M\$RPL_S_S\s+\.ASCII_W"),
        "budget": cut(OPTIONS, r"^\s+; Check if the planned memory usage in OPTM_HEAP will not",
                      end=r"^_HLP_HEAP2_OK\s"),
        "hm": cut(SHELL, r"^_HM_SDMOUNTED6A\s", end=r"^\s+RSUB\s+SCR\$OSM_OFF, 1\s+; hide the big window"),
        "nl": one_line(MENU, r"^OPTM_NL\s"),
        "ellipsis": one_line(STRINGS, r"^FN_ELLIPSIS\s"),
    }


TESTBED = r"""
#include "{sysdef}"
#include "{mondef}"
#include "{m2msysdef}"

OPTM_SUBMENU    .EQU    {optm_submenu}
OPTM_IR_ITEMS   .EQU    {ir_items}
OPTM_IR_STDSEL  .EQU    {ir_stdsel}

                .ORG    0x8000

; ----------------------------------------------------------------------------
; Driver
; ----------------------------------------------------------------------------
START           MOVE    S_BEGIN, R8
                SYSCALL(puts, 1)
                MOVE    TB_GROUPS, R8           ; the menu groups into the
                MOVE    M2M$RAMROM_DATA, R9     ; window of config.vhd
                MOVE    {nitems}, R10
                SYSCALL(memcpy, 1)
                MOVE    OPTM_ICOUNT, R0
                MOVE    {nitems}, @R0

                ; the budget cases; the last one leaves OPTM_HEAP and
                ; OPTM_HEAP_LAST for the sessions
                MOVE    S_SECB, R8
                SYSCALL(puts, 1)
                MOVE    TB_BCASES, R6
_BCASE          CMP     0xFFFF, @R6
                RBRA    _SESSIONS, Z
                MOVE    R6, R8
                RSUB    BROW, 1
                ADD     6, R6
                RBRA    _BCASE, 1

                ; the sessions: one row = opcode, two arguments, name or 0
_SESSIONS       MOVE    S_SECD, R8
                SYSCALL(puts, 1)
                MOVE    TB_STEPS, R6
                XOR     R7, R7                  ; R7: step number
_STEP           MOVE    @R6++, R0               ; R0: opcode
                CMP     0xFFFF, R0
                RBRA    _DONE, Z
                MOVE    @R6++, R1
                MOVE    @R6++, R2
                MOVE    @R6++, R3
                CMP     {op_session}, R0
                RBRA    _S_HEAD, !Z
                MOVE    S_SESSION, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                RBRA    _STEP, 1
_S_HEAD         MOVE    S_STEP, R8
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
                CMP     {op_mount}, R0
                RBRA    _S_MOUNT, Z
                CMP     {op_unmount}, R0
                RBRA    _S_UNMOUNT, Z
                CMP     {op_dirty}, R0
                RBRA    _S_DIRTY, Z
                RSUB    DRAW, 1
                RBRA    _S_DUMP, 1
_S_MOUNT        MOVE    R1, R8                  ; the file name into the slot,
                MOVE    R2, R9                  ; as HANDLE_MOUNTING does it
                MOVE    R3, R10
                RSUB    TB_MOUNT, 1
                MOVE    1, R4
                RBRA    _S_STATE, 1
_S_UNMOUNT      XOR     R4, R4
_S_STATE        MOVE    TB_MNT, R5              ; mounted / loaded
                CMP     0, R1
                RBRA    _S_STATE2, Z
                MOVE    CRTROM_MAN_LDF, R5
_S_STATE2       ADD     R2, R5
                MOVE    R4, @R5
                RBRA    _S_DUMP, 1
_S_DIRTY        MOVE    TB_DTY, R5              ; write cache of a drive
                ADD     R1, R5
                MOVE    R2, @R5
_S_DUMP         RSUB    DUMP, 1
                ADD     1, R7
                RBRA    _STEP, 1

_DONE           MOVE    S_DONE, R8
                SYSCALL(puts, 1)
                SYSCALL(exit, 1)

; ----------------------------------------------------------------------------
; One budget case: R8 points to drives, submenus, CRT/ROMs, width, heap size,
; heap address
; ----------------------------------------------------------------------------
BROW            INCRB
                MOVE    R8, R0
                MOVE    S_B, R8
                SYSCALL(puts, 1)
                MOVE    VDRIVES_NUM, R1
                MOVE    @R0++, @R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    OPTM_SCOUNT, R1
                MOVE    @R0++, @R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    CRTROM_MAN_NUM, R1
                MOVE    @R0++, @R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    SCR$OSM_O_DX, R1
                MOVE    @R0++, @R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    OPTM_HEAP_SIZE, R1
                MOVE    @R0++, @R1
                MOVE    @R1, R8
                RSUB    PRHEX, 1
                MOVE    OPTM_HEAP, R1
                MOVE    @R0, @R1
                SYSCALL(crlf, 1)
                MOVE    OPTM_HEAP_LAST, R1
                MOVE    0xDEAD, @R1

                MOVE    TB_SP, R1               ; for FATAL and the SP check
                MOVE    SP, @R1
                MOVE    TB_SR, R1
                MOVE    SR, @R1
                MOVE    TB_CONT, R1
                MOVE    _BR_LAST, @R1
                MOVE    {m8}, R8
                MOVE    {m9}, R9
                MOVE    {m10}, R10
                MOVE    {m11}, R11
                MOVE    {m12}, R12
                RSUB    TB_BUDGET, 1
                MOVE    SR, R5                  ; R5: SR after the call
                RSUB    PRREGS, 1

_BR_LAST        MOVE    S_LAST, R8              ; OPTM_HEAP_LAST - OPTM_HEAP
                SYSCALL(puts, 1)
                MOVE    OPTM_HEAP_LAST, R1
                MOVE    @R1, R8
                MOVE    OPTM_HEAP, R1
                SUB     @R1, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                DECRB
                RET

; HELP_MENU runs the budget check in its own register bank and needs R12
; afterwards
TB_BUDGET       SYSCALL(enter, 1)
{budget}
_HLP_HEAP2_OK   MOVE    S_OK, R8
                SYSCALL(puts, 1)
                MOVE    R12, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; One redraw: every "%s" line of the menu through OPTM_CB_SHOW
; ----------------------------------------------------------------------------
DRAW            INCRB
                MOVE    TB_LINES, R0
_DRW_LINE       MOVE    @R0++, R1               ; R1: menu index
                CMP     0xFFFF, R1
                RBRA    _DRW_RET, Z
                MOVE    @R0++, R2               ; R2: the line with the %s
                MOVE    TB_SP, R3
                MOVE    SP, @R3
                MOVE    TB_SR, R3
                MOVE    SR, @R3
                MOVE    TB_CONT, R3
                MOVE    _DRW_LINE, @R3
                MOVE    S_LINE, R8
                SYSCALL(puts, 1)
                MOVE    R1, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    R2, R8
                MOVE    R1, R9
                MOVE    {m10}, R10
                MOVE    {m11}, R11
                MOVE    {m12}, R12
                RSUB    OPTM_CB_SHOW, 1
                MOVE    SR, R5                  ; R5: SR after the call
                MOVE    R8, R4
                RSUB    PRREGS, 1
                MOVE    S_TEXT, R8              ; the text of the line
                SYSCALL(puts, 1)
                MOVE    R4, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RBRA    _DRW_LINE, 1
_DRW_RET        DECRB
                RET

; print R8 to R12, the SP and the register bank relative to TB_SP and TB_SR;
; R5 is the SR right after the call
PRREGS          MOVE    R8, @--SP
                MOVE    S_REGS, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                RSUB    PRHEX, 1
                MOVE    R9, R8
                RSUB    PRHEX, 1
                MOVE    R10, R8
                RSUB    PRHEX, 1
                MOVE    R11, R8
                RSUB    PRHEX, 1
                MOVE    R12, R8
                RSUB    PRHEX, 1
                MOVE    S_SP, R8
                SYSCALL(puts, 1)
                MOVE    SP, R8                  ; SP inside PRREGS + 1
                ADD     1, R8                   ; = SP of the caller
                MOVE    TB_SP, R9
                SUB     @R9, R8
                RSUB    PRHEX, 1
                MOVE    S_BANK, R8
                SYSCALL(puts, 1)
                MOVE    TB_SR, R9
                MOVE    R5, R8
                XOR     @R9, R8
                AND     0xFF00, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                RET

; dump of the guard area, all slots, the parking slots and the guard behind
DUMP            INCRB
                MOVE    {region}, R0
                XOR     R2, R2
_DMP_ROW        MOVE    S_D, R8
                SYSCALL(puts, 1)
                MOVE    R2, R8
                RSUB    PRHEX, 1
                MOVE    {dx}, R1
_DMP_WORD       MOVE    @R0++, R8
                RSUB    PRHEX, 1
                SUB     1, R1
                RBRA    _DMP_WORD, !Z
                SYSCALL(crlf, 1)
                ADD     1, R2
                CMP     {rows}, R2
                RBRA    _DMP_ROW, !Z
                DECRB
                RET

; print a blank and R8 as four hex digits; keeps all registers
PRHEX           MOVE    R8, @--SP
                MOVE    S_BLANK, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                SYSCALL(puthex, 1)
                RET

; HANDLE_MOUNTING stores the name: R8 = 0 (drive) or 1 (CRT/ROM), R9 = id,
; R10 = file name
TB_MOUNT        SYSCALL(enter, 1)
                MOVE    R8, R5                  ; R5: mode
                MOVE    R9, R7                  ; R7: drive or CRT/ROM id
                MOVE    R10, R2                 ; R2: file name
                XOR     R9, R9
{hm}
                SYSCALL(leave, 1)
                RET

; ----------------------------------------------------------------------------
; Stubs
; ----------------------------------------------------------------------------

; the string of the selected window of config.vhd in R8
TB_WINDOW       INCRB
                MOVE    TB_RAMROM_DEV, R0
                CMP     M2M$CONFIG, @R0
                RBRA    _TBW_BAD, !Z
                MOVE    TB_4KWIN, R0
                MOVE    @R0, R0
                MOVE    TB_MSTR, R8
                CMP     M2M$CFG_OPTM_MSTR, R0
                RBRA    _TBW_RET, Z
                MOVE    TB_SSTR, R8
                CMP     M2M$CFG_OPTM_SSTR, R0
                RBRA    _TBW_RET, Z
                MOVE    TB_CRSTR, R8
                CMP     M2M$CFG_OPTM_CRSTR, R0
                RBRA    _TBW_RET, Z
_TBW_BAD        MOVE    TB_BADWIN, R8
_TBW_RET        DECRB
                RET

; menu group 0x00D0 + n is drive n
VD_DRVNO        INCRB
                MOVE    R8, R0
                AND     0xFFF0, R0
                CMP     0x00D0, R0
                RBRA    _VDN_NO, !Z
                AND     0x000F, R8
                OR      0x0004, SR
                DECRB
                RET
_VDN_NO         MOVE    0xFFFF, R8
                AND     0xFFFB, SR
                DECRB
                RET

; Carry = drive R8 is mounted; R8 unchanged, R9 to R12 overwritten
VD_MOUNTED      INCRB
                MOVE    TB_MNT, R0
                ADD     R8, R0
                MOVE    0x7E01, R9
                MOVE    0x7E02, R10
                MOVE    0x7E03, R11
                MOVE    0x7E04, R12
                CMP     0, @R0
                RBRA    _VDM_NO, Z
                OR      0x0004, SR
                RBRA    _VDM_RET, 1
_VDM_NO         AND     0xFFFB, SR
_VDM_RET        DECRB
                RET

; R8 = write cache of drive R8 is dirty; R9 to R12 overwritten
VD_DRV_READ     INCRB
                CMP     VD_CACHE_DIRTY, R9
                RBRA    _VDR_OK, Z
                MOVE    R8, R0
                MOVE    S_VDRD, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
_VDR_OK         MOVE    TB_DTY, R0
                ADD     R8, R0
                MOVE    @R0, R8
                MOVE    0x7E05, R9
                MOVE    0x7E06, R10
                MOVE    0x7E07, R11
                MOVE    0x7E08, R12
                DECRB
                RET

; menu group 0x00E0 + n is CRT/ROM n
CRTROM_M_NO     INCRB
                MOVE    R8, R0
                AND     0xFFF0, R0
                CMP     0x00E0, R0
                RBRA    _CMN_NO, !Z
                AND     0x000F, R8
                OR      0x0004, SR
                DECRB
                RET
_CMN_NO         MOVE    0xFFFF, R8
                AND     0xFFFB, SR
                DECRB
                RET

CRTROM_CHK_NO   INCRB
                MOVE    CRTROM_MAN_NUM, R0
                CMP     @R0, R8
                RBRA    _CCN_RET, N
                MOVE    R8, R0
                MOVE    S_CHKNO, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    R0, R8
_CCN_RET        DECRB
                RET

; standard semantics for every submenu
SUBMENU_SUMMARY XOR     R8, R8
                RET

; the selected item of a submenu is the second line behind its opener
OPTM_SUMM_SCAN  ADD     2, R8
                OR      0x0004, SR
                RET

LOG_HEAP2       MOVE    R8, @--SP
                MOVE    S_HEAP2, R8
                SYSCALL(puts, 1)
                MOVE    R10, R8
                RSUB    PRHEX, 1
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; FATAL: print, then continue at TB_CONT with the SP and the register bank of
; TB_SP and TB_SR
FATAL_IDX
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
                MOVE    TB_CONT, R8
                MOVE    @R8, R8
                ABRA    R8, 1

SAVE_DEVSEL
RESTORE_DEVSEL  RET

; ----------------------------------------------------------------------------
; The real code
; ----------------------------------------------------------------------------
{cb}
{rpl}
{nl}
{ellipsis}

; ----------------------------------------------------------------------------
; Strings
; ----------------------------------------------------------------------------
S_BEGIN         .ASCII_W "== BEGIN ==\n"
S_DONE          .ASCII_W "DONE\n"
S_SECB          .ASCII_W "SECTION BUDGET\n"
S_SECD          .ASCII_W "SECTION SESSIONS\n"
S_SESSION       .ASCII_W "SESSION"
S_STEP          .ASCII_W "STEP"
S_B             .ASCII_W "BUDGET"
S_OK            .ASCII_W "OK R12"
S_LAST          .ASCII_W "LAST"
S_HEAP2         .ASCII_W "LOG_HEAP2"
S_LINE          .ASCII_W "LINE"
S_TEXT          .ASCII_W "TEXT "
S_REGS          .ASCII_W "REGS"
S_SP            .ASCII_W " SP"
S_BANK          .ASCII_W " BANK"
S_D             .ASCII_W "D"
S_BLANK         .ASCII_W " "
S_FATAL         .ASCII_W "FATAL "
S_VDRD          .ASCII_W "VD_DRV_READ WITH A WRONG REGISTER"
S_CHKNO         .ASCII_W "CRTROM_CHK_NO: ILLEGAL NUMBER"
TB_MSTR         .ASCII_W "{s_mount}"
TB_SSTR         .ASCII_W "{s_saving}"
TB_CRSTR        .ASCII_W "{s_crtrom}"
TB_BADWIN       .ASCII_W "?WRONG WINDOW?"
ERR_F_MENUSUB   .ASCII_W "ERR_F_MENUSUB"
ERR_F_MENUNGRP  .ASCII_W "ERR_F_MENUNGRP"
ERR_F_MENUDRV   .ASCII_W "ERR_F_MENUDRV"
ERR_F_NO_S      .ASCII_W "ERR_F_NO_S"
ERR_FATAL_HEAP2 .ASCII_W "ERR_FATAL_HEAP2"
ERR_FATAL_INST  .ASCII_W "ERR_FATAL_INST"
ERR_FATAL_INST1
ERR_FATAL_INST6
ERR_FATAL_INST7
ERR_FATAL_INST8
ERR_FATAL_INST9 .ASCII_W ""
{templates}
{names}
TB_ITEMS        .DW     {items}

; ----------------------------------------------------------------------------
; Variables
; ----------------------------------------------------------------------------
HEAP            .DW     {heap}
TB_STDSEL       .DW     {stdsel}
TB_GROUPS       .DW     {groups}
TB_LINES        .DW     {lines}
                .DW     0xFFFF
TB_BCASES       .DW     {bcases}
                .DW     0xFFFF
TB_STEPS
{steps}
                .DW     0xFFFF
OPTM_ICOUNT     .DW     0
OPTM_SCOUNT     .DW     0
VDRIVES_NUM     .DW     0
CRTROM_MAN_NUM  .DW     0
SCR$OSM_O_DX    .DW     0
OPTM_HEAP       .DW     0
OPTM_HEAP_LAST  .DW     0
OPTM_HEAP_SIZE  .DW     0
CRTROM_MAN_LDF  .DW     0, 0, 0, 0, 0, 0, 0, 0
TB_MNT          .DW     0, 0, 0, 0, 0, 0, 0, 0
TB_DTY          .DW     0, 0, 0, 0, 0, 0, 0, 0
TB_RAMROM_DEV   .DW     0
TB_4KWIN        .DW     0
TB_SP           .DW     0
TB_SR           .DW     0
TB_CONT         .DW     0
SCRATCH_HEX     .BLOCK  5

                .ORG    {region}
TB_REGION       .DW     {region_words}
"""


def words(ws):
    return ", ".join(w if isinstance(w, str) else "0x%04X" % (w & 0xFFFF) for w in ws)


def asm_words(ws, per=12):
    """.DW rows; the first one continues a label line"""
    rows = [ws[i:i + per] for i in range(0, len(ws), per)] or [[]]
    return ("\n                .DW     ").join(words(r) for r in rows)


def name_label(cfg, name):
    return "N_%d" % cfg.names().index(name)


def pattern(k):
    """initial content of word k of the region"""
    return 0x0A00 + k


def testbed(code, cfg, work):
    mondef = os.path.join(work, "monitor_tb.def")
    if not os.path.exists(mondef):
        shutil.copy(os.path.join(QNICE, "dist_kit", "monitor.def"), mondef)
    items = []
    for t, g in cfg.menu:
        items += [ord(ch) for ch in t] + [0x5C, 0x6E]        # "\n" as two characters
    items.append(0)
    heap = [0] * STRUCTSIZE
    heap[IR_ITEMS], heap[IR_STDSEL] = "TB_ITEMS", "TB_STDSEL"
    lines = []
    for i, t in cfg.lines():
        lines += [i, "L_%d" % i]
    steps = []
    for op, a, b, name in cfg.steps():
        steps.append("                .DW     0x%04X, 0x%04X, 0x%04X, %s"
                     % (op, a, b, name_label(cfg, name) if name else "0"))
    bcases = []
    for row in cfg.budget:
        bcases += list(row)
    return TESTBED.format(
        sysdef=QSYSDEF, mondef=mondef, m2msysdef=M2MSYSDEF,
        optm_submenu="0x%04X" % OPTM_SUBMENU, ir_items=IR_ITEMS, ir_stdsel=IR_STDSEL,
        nitems=len(cfg.menu), op_session=SESSION, op_mount=MOUNT, op_unmount=UNMOUNT,
        op_dirty=DIRTY, m8="0x%04X" % MARK[0], m9="0x%04X" % MARK[1], m10="0x%04X" % MARK[2],
        m11="0x%04X" % MARK[3], m12="0x%04X" % MARK[4],
        region="0x%04X" % REGION, dx=cfg.dx, rows=cfg.rows,
        s_mount=S_MOUNT, s_saving=S_SAVING, s_crtrom=S_CRTROM,
        templates="\n".join('L_%-13d .ASCII_W "%s"' % (i, t) for i, t in cfg.lines()),
        names="\n".join('%-15s .ASCII_W "%s"' % (name_label(cfg, n), n) for n in cfg.names()),
        items=asm_words(items),
        heap=", ".join(h if isinstance(h, str) else "0x%04X" % h for h in heap),
        stdsel=words([0] * len(cfg.menu)), groups=asm_words([g for t, g in cfg.menu]),
        lines=asm_words(lines), bcases=asm_words(bcases), steps="\n".join(steps),
        region_words=asm_words([pattern(k) for k in range(cfg.rows * cfg.dx)]),
        **code)


# ---------------------------------------------------------------------------
# The model
# ---------------------------------------------------------------------------
def h(v):
    return "%04X" % (v & 0xFFFF)


def rpl_s(template, repl, maxw):
    """M2M$RPL_S: the first %s replaced, at most maxw characters, an ellipsis
    when the part up to the replacement does not fit"""
    p = template.index("%s")
    prefix, suffix = template[:p], template[p + 2:]
    if len(prefix) + len(repl) > maxw:
        return (prefix + repl)[:maxw - 3] + "..."
    s = prefix + repl
    return s + suffix[:maxw - len(s)]


class Mem:
    def __init__(self, cfg):
        self.w = {REGION + k: pattern(k) for k in range(cfg.rows * cfg.dx)}

    def string(self, a):
        s = ""
        while self.w[a] != 0:
            s += chr(self.w[a])
            a += 1
        return s

    def put(self, a, s):
        for k, ch in enumerate(s):
            self.w[a + k] = ord(ch)
        self.w[a + len(s)] = 0

    def strcpy(self, src, dst):
        self.put(dst, self.string(src))


def model(cfg):
    dx, maxw = cfg.dx, cfg.dx - 2
    out = ["== BEGIN ==", "SECTION BUDGET"]
    for v, s, c, w, size, heap in cfg.budget:
        demand = ((2 * v + s + c) * w) & 0xFFFF       # one parking slot per drive
        out.append("BUDGET %s %s %s %s %s" % (h(v), h(s), h(c), h(w), h(size)))
        out.append("LOG_HEAP2 " + h(demand))
        if demand <= size:
            out.append("OK R12 " + h(MARK[4]))
            out.append("REGS %s SP 0000 BANK 0000" % " ".join(h(m) for m in MARK))
        else:
            out.append("FATAL ERR_FATAL_HEAP2 " + h(demand - size))
        out.append("LAST " + h((v + s + c) * w))

    out.append("SECTION SESSIONS")
    mem = Mem(cfg)
    mnt, dty, ldf = [0] * cfg.v, [0] * cfg.v, [0] * cfg.c
    slot = lambda k: cfg.heap + k * dx
    park = lambda n: cfg.last + n * dx
    flag = lambda a: a + dx - 1
    group = {i: g for i, (t, g) in enumerate(cfg.menu)}
    texts = {i: t for i, (t, g) in enumerate(cfg.menu)}
    subidx = {}
    for i, (t, g) in enumerate(cfg.menu):
        if g == OPTM_SUBMENU:
            subidx[i] = len(subidx)

    def complete(a, tpl):                 # _OPTM_CBS_3 and _OPTM_CBS_4
        mem.put(a, rpl_s(tpl, mem.string(a), maxw))
        mem.w[flag(a)] = 1

    def callback(i, tpl):
        g = group[i]
        if g & OPTM_SUBMENU:              # the label of the selected item
            label = texts[i + 2].lstrip(" ")
            a = slot(cfg.v + subidx[i])
            mem.put(a, rpl_s(tpl, label, maxw))
            return a
        if g & 0xFFF0 == 0x00E0:          # CRT/ROM
            n = g & 0xF
            a = slot(cfg.v + cfg.s + n)
            if not ldf[n]:
                mem.put(a, rpl_s(tpl, S_CRTROM, maxw))
            elif mem.w[flag(a)] != 1:
                complete(a, tpl)
            return a
        n = g & 0xF                       # virtual drive
        a = slot(n)
        if not mnt[n]:
            mem.put(a, rpl_s(tpl, S_MOUNT, maxw))
        elif dty[n]:
            if mem.w[flag(a)] != 2:       # park the text and its flag, show <Saving>
                f = mem.w[flag(a)]
                mem.strcpy(a, park(n))
                mem.w[flag(park(n))] = f
                mem.put(a, rpl_s(tpl, S_SAVING, maxw))
                mem.w[flag(a)] = 2
        elif mem.w[flag(a)] == 2:         # the parked text comes back
            mem.strcpy(park(n), a)
            if mem.w[flag(park(n))] == 0: # a bare file name: the complete line
                complete(a, tpl)
            else:
                mem.w[flag(a)] = 1
        elif mem.w[flag(a)] != 1:
            complete(a, tpl)
        return a

    stepno = 0
    for op, a, b, name in cfg.steps():
        if op == SESSION:
            out.append("SESSION " + h(a))
            continue
        out.append("STEP %s %s %s %s" % (h(stepno), h(op), h(a), h(b)))
        if op == MOUNT:                   # HANDLE_MOUNTING
            k = b if a == DRV else cfg.v + cfg.s + b
            s = name if len(name) <= maxw else name[:maxw + 1]
            mem.put(slot(k), s)
            mem.w[flag(slot(k))] = 0
            (mnt if a == DRV else ldf)[b] = 1
        elif op == UNMOUNT:
            (mnt if a == DRV else ldf)[b] = 0
        elif op == DIRTY:
            dty[a] = b
        elif op == DRAW:
            for i, tpl in cfg.lines():
                out.append("LINE " + h(i))
                r8 = callback(i, tpl)
                out.append("REGS %s %s %s SP 0000 BANK 0000"
                           % (h(r8), h(i), " ".join(h(m) for m in MARK[2:])))
                out.append("TEXT " + mem.string(r8))
        for row in range(cfg.rows):
            out.append("D %s %s" % (h(row), " ".join(h(mem.w[REGION + row * dx + k]) for k in range(dx))))
        stepno += 1
    out.append("DONE")
    return out


# ---------------------------------------------------------------------------
# Assemble, run, compare
# ---------------------------------------------------------------------------
def run(code, cfg, work):
    src = os.path.join(work, "saving_text_tb.asm")
    open(src, "w").write(testbed(code, cfg, work))
    out = os.path.join(work, "saving_text_tb.out")
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([ASM, "saving_text_tb.asm"], cwd=work, capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, "assembly failed: " + (r.stdout + r.stderr)[-2000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=120, errors="replace")
    except subprocess.TimeoutExpired:
        return None, "emulator timeout"
    lines = [l.rstrip() for l in r.stdout.replace("\r", "").split("\n") if l.strip()]
    if "== BEGIN ==" in lines:
        lines = lines[lines.index("== BEGIN =="):]
    if "DONE" in lines:
        lines = lines[:lines.index("DONE") + 1]
    return lines, ""


def sections(lines):
    out, cur = {}, "HEAD"
    for l in lines:
        if l.startswith("SECTION "):
            cur = l
        out.setdefault(cur, []).append(l)
    return out


def compare(got, exp):
    """None if equal, else the first difference of each section"""
    if got is None:
        return ["no output"]
    gs, es = sections(got), sections(exp)
    diffs = []
    for name in list(es) + [n for n in gs if n not in es]:
        g_l, e_l = gs.get(name, []), es.get(name, [])
        ctx = {}
        for i in range(max(len(g_l), len(e_l))):
            g = g_l[i] if i < len(g_l) else "<missing>"
            e = e_l[i] if i < len(e_l) else "<missing>"
            for key in ("BUDGET", "SESSION", "STEP", "LINE"):
                if e.startswith(key + " "):
                    ctx[key] = e
                    for later in {"SESSION": ("STEP", "LINE"), "STEP": ("LINE",)}.get(key, ()):
                        ctx.pop(later, None)
            if g.upper() != e.upper():
                diffs.append("%s, %s: expected %r, got %r" % (name, " / ".join(ctx.values()), e, g))
                break
    return diffs or None


# ---------------------------------------------------------------------------
# Mutants: each must make the comparison fail
# ---------------------------------------------------------------------------
def replace(part, *pairs):
    def mutate(code):
        text = code[part]
        for old, new in pairs:
            if text.count(old) != 1:
                return None
            text = text.replace(old, new)
        return dict(code, **{part: text})
    return mutate


I = "\n" + " " * 16      # a new line of code, indented like options.asm

PARK = ("MOVE    OPTM_HEAP_LAST, R9      ; remember the text of the line" + I +
        "MOVE    @R9, R9                 ; in the parking slot of this" + I +
        "ADD     R0, R9                  ; drive: @OPTM_HEAP_LAST plus" + I +
        "MOVE    OPTM_HEAP, R8           ; R0 minus @OPTM_HEAP" + I +
        "SUB     @R8, R9" + I +
        "MOVE    R0, R8")
UNPARK = ("MOVE    OPTM_HEAP_LAST, R8      ; restore the text from the" + I +
          "MOVE    @R8, R8                 ; parking slot of this drive" + I +
          "ADD     R0, R8" + I +
          "MOVE    OPTM_HEAP, R9" + I +
          "SUB     @R9, R8")
PARKFLAG = (I + "MOVE    SCR$OSM_O_DX, R8" + I +
            "MOVE    @R8, R8" + I +
            "SUB     1, R8                   ; R8: offset of the flag" + I +
            "ADD     R8, R9                  ; R9: flag in the parking slot" + I +
            "ADD     R0, R8                  ; R8: flag of the line" + I +
            "MOVE    @R8, @R9")
BUDGET = ("MOVE    SCR$OSM_O_DX, R8        ; demand: R9 is still the" + I +
          "MOVE    @R8, R8                 ; amount of %s strings; add" + I +
          "MOVE    VDRIVES_NUM, R11        ; one parking slot per" + I +
          "ADD     @R11, R9                ; virtual drive and multiply" + I +
          "SYSCALL(mulu, 1)                ; with @SCR$OSM_O_DX")

MUTANTS = [
    # the parking slot of the drive, when the text is parked and restored
    ("park_single_buffer", replace("cb", (PARK, "MOVE    R0, R8" + I + "MOVE    OPTM_HEAP_LAST, R9" + I +
                                          "MOVE    @R9, R9"))),
    ("restore_single_buffer", replace("cb", (UNPARK, "MOVE    OPTM_HEAP_LAST, R8" + I + "MOVE    @R8, R8"))),
    ("park_base_optm_heap", replace("cb", ("MOVE    OPTM_HEAP_LAST, R9      ; remember the text",
                                           "MOVE    OPTM_HEAP, R9           ; remember the text"))),
    ("restore_base_optm_heap", replace("cb", ("MOVE    OPTM_HEAP_LAST, R8      ; restore the text",
                                              "MOVE    OPTM_HEAP, R8           ; restore the text"))),
    ("park_twice_the_offset", replace("cb", ("ADD     R0, R9                  ; drive: @OPTM_HEAP_LAST plus",
                                             "ADD     R0, R9" + I + "ADD     R0, R9" + I +
                                             "MOVE    OPTM_HEAP, R8" + I + "SUB     @R8, R9"))),
    ("restore_next_slot", replace("cb", ("SUB     @R9, R8\n", "SUB     @R9, R8" + I +
                                         "MOVE    SCR$OSM_O_DX, R9" + I + "ADD     @R9, R8\n"))),
    # the budget check
    ("budget_one_slot", replace("budget", (BUDGET, "MOVE    SCR$OSM_O_DX, R8" + I + "ADD     @R8, R10"))),
    ("budget_one_slot_too_many", replace("budget", ("ADD     @R11, R9                ; virtual drive",
                                                    "ADD     @R11, R9" + I + "ADD     1, R9"))),
    ("budget_last_behind_parking", replace("budget", (
        "SYSCALL(mulu, 1)                ; R10 = result lo word of mulu",
        "MOVE    VDRIVES_NUM, R11" + I + "ADD     @R11, R9" + I + "SYSCALL(mulu, 1)" + I +
        "MOVE    VDRIVES_NUM, R11" + I + "SUB     @R11, R9"))),
    ("budget_heap_check_off", replace("budget", ("RBRA    _HLP_HEAP2_OK, !N", "RBRA    _HLP_HEAP2_OK, 1"))),
    # a parked bare file name comes back as the complete line
    ("park_without_flag", replace("cb", (PARKFLAG, ""))),
    ("restore_ignores_parked_flag", replace("cb", ("RBRA    _OPTM_CBS_3, Z\n", ""))),
    ("restore_condition_inverted", replace("cb", ("RBRA    _OPTM_CBS_3, Z\n", "RBRA    _OPTM_CBS_3, !Z\n"))),
    ("restore_reads_flag_of_line", replace("cb", ("ADD     R8, R9                  ; like the normal case #2b",
                                                  "ADD     R0, R9"))),
]


def main():
    for tool in (ASM, EMU, MON):
        if not os.path.exists(tool):
            sys.exit("missing %s (see README.md: build the QNICE toolchain first)" % tool)
    work = tempfile.mkdtemp(prefix="saving_text_test.")
    fails = 0
    try:
        code = real_code()
        expected = [model(cfg) for cfg in CONFIGS]
        for cfg, exp in zip(CONFIGS, expected):
            got, err = run(code, cfg, work)
            diff = compare(got, exp)
            if KEEP:
                tag = cfg.name.split(",")[0].replace(" ", "")
                open(os.path.join(work, "trace_%s.got" % tag), "w").write("\n".join(got or []) + "\n")
                open(os.path.join(work, "trace_%s.exp" % tag), "w").write("\n".join(exp) + "\n")
                shutil.copy(os.path.join(work, "saving_text_tb.asm"), os.path.join(work, "tb_%s.asm" % tag))
            if diff:
                for d in diff:
                    print("FAIL: real code, %s: %s %s" % (cfg.name, d, err))
                fails += 1
            else:
                print("PASS: real code, %s: %d budget cases, %d sessions, %d steps, %d lines of trace"
                      % (cfg.name, len(cfg.budget), len(cfg.sessions),
                         sum(1 for s in cfg.steps() if s[0] != SESSION), len(exp)))
        for name, mutate in MUTANTS:
            mcode = mutate(code)
            if mcode is None:
                print("FAIL: mutant %s: its pattern is not found exactly once: adapt the mutant" % name)
                fails += 1
                continue
            caught = None
            for cfg, exp in zip(CONFIGS, expected):
                got, err = run(mcode, cfg, work)
                if err.startswith("assembly failed"):
                    caught = "ASSEMBLY"
                    print("FAIL: mutant %s does not assemble: %s" % (name, err))
                    fails += 1
                    break
                diff = compare(got, exp)
                if diff:
                    caught = "%s: %s" % (cfg.name, diff[0])
                    break
            if caught == "ASSEMBLY":
                continue
            if caught:
                print("PASS: mutant %-27s caught (%s)" % (name, caught[:150]))
            else:
                print("FAIL: mutant %s not caught" % name)
                fails += 1
    finally:
        if KEEP:
            print("work folder kept: " + work)
        else:
            shutil.rmtree(work, ignore_errors=True)
    print("RESULT: PASS" if fails == 0 else "RESULT: FAIL (%d)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
