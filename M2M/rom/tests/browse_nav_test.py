#!/usr/bin/env python3
"""
Headless test of the cursor keys of the file browser, the browse loop of
SELECT_FILE in M2M/rom/selectfile.asm:

  * Cursor Up and Cursor Down move the cursor by one entry; at the upper and
    the lower edge of the screen the list scrolls by one entry. On the first
    and on the last entry they wrap around, as in the on-screen menu: Cursor
    Up on the first entry selects the last entry, Cursor Down on the last
    entry the first one. If that entry is not on the screen, the list
    scrolls there in one step, with one redraw.
  * Cursor Left and Cursor Right turn the pages. On the first page Cursor
    Left selects the first entry, on the last page Cursor Right the last
    one; they do not wrap around.
  * The browser starts at a remembered position (the absolute index of an
    entry, which it gets on the stack), as when it comes back to a folder.

The script cuts the browse loop out of selectfile.asm on every run (from
_S_BROWSE_START up to the Run/Stop handler) and assembles it with the real
llist.asm and with stubs: SCR$CLRINNER, SHOW_DIR and SELECT_LINE print what
they would draw, KEYB$GETKEY prints the state of the browser (first entry on
the screen, cursor line, entries up to the end of the screen, absolute index
of the cursor) and returns the next key of a script: Up, Up, Down, Down,
Down, Up and then runs of 1 to 16 random cursor keys. Run/Stop ends a case.
A screen model replays the trace: after every key the screen has to show the
right entries, exactly the cursor line has to be highlighted, the state has
to match an independent Python model of the browser, and the number of
redraws has to be the one of the model. The cases: lists of 1 to 1,927
entries on screens of 3, 7 and 27 lines, starting on the first entry, on the
last one, in the middle and around the end of the first screen.

Then the script applies mutants to the extracted code, each of which has to
be caught, and runs the testbed once more without the trace to count the
instructions per key: the cut code and llist.asm, plus the calls of the
stubs (about 10 instructions per key), without the drawing of the real
SHOW_DIR and SELECT_LINE.

Run it from anywhere:
    python3 browse_nav_test.py
    python3 browse_nav_test.py --perf-only <selectfile.asm>
The second form only counts the instructions per key, for example of an
older selectfile.asm, for a comparison.

Needs the QNICE assembler, emulator and monitor.out, see README.md.

Licensed under GPL v3
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "../../.."))
QNICE = os.path.join(REPO, "M2M", "QNICE")
ASM = os.path.join(QNICE, "assembler", "asm")
EMU = os.path.join(QNICE, "emulator", "qnice")
MON = os.path.join(QNICE, "monitor", "monitor.out")
SELECTFILE = os.path.join(REPO, "M2M", "rom", "selectfile.asm")
LLIST = os.path.join(REPO, "M2M", "rom", "llist.asm")
M2MSYSDEF = os.path.join(REPO, "M2M", "rom", "sysdef.asm")
QSYSDEF = os.path.join(QNICE, "dist_kit", "sysdef.asm")
MONDEF = os.path.join(QNICE, "dist_kit", "monitor.def")


def equ(path, name):
    for line in open(path, errors="replace"):
        m = re.match(r"^%s\s+\.EQU\s+(0x[0-9A-Fa-f]+|\d+)" % re.escape(name), line)
        if m:
            return int(m.group(1), 0)
    sys.exit("cannot find %s in %s" % (name, path))


UP, DOWN, LEFT, RIGHT = (equ(M2MSYSDEF, "M2M$KEY_" + k) for k in ("UP", "DOWN", "LEFT", "RIGHT"))
RUNSTOP = equ(M2MSYSDEF, "M2M$KEY_RUNSTOP")
COL_STD = equ(M2MSYSDEF, "M2M$SA_COL_STD")
COL_INV = equ(M2MSYSDEF, "M2M$SA_COL_STD_INV")
KEYNAME = {UP: "Up", DOWN: "Down", LEFT: "Left", RIGHT: "Right", RUNSTOP: "Run/Stop", 0: "start"}


# ---------------------------------------------------------------------------
# Extraction of the real code
# ---------------------------------------------------------------------------
def cut(path, start, end):
    """Lines from the one matching start up to (excluding) the one matching
    end; start has to match exactly one line."""
    lines = open(path).read().split("\n")
    s = [i for i, l in enumerate(lines) if re.match(start, l)]
    if len(s) != 1:
        sys.exit("%r matches %d lines of %s" % (start, len(s), path))
    for i in range(s[0] + 1, len(lines)):
        if re.match(end, lines[i]):
            return "\n".join(lines[s[0]:i]) + "\n"
    sys.exit("cannot find the end of %r in %s" % (start, path))


def browse_loop(path):
    return cut(path, r"^_S_BROWSE_START\s", r"^\s+; browsing interrupted by Run/Stop")


# ---------------------------------------------------------------------------
# Testbed
# ---------------------------------------------------------------------------
TESTBED = r"""
#include "@QSYSDEF@"
#include "@MONDEF@"
#include "@M2MSYSDEF@"
@PERF@
TB_LIST         .EQU    0xB000                  ; the linked list of a case
TB_PTAB         .EQU    0xD800                  ; perf: last key and count
ERR_FATAL_ITER  .EQU    0xEEEE

                .ORG    0x8000

; ----------------------------------------------------------------------------
; Driver: one case per row of TB_CASES (entries, lines on the screen, start
; position, seed, runs of random keys); 0 entries end the table
; ----------------------------------------------------------------------------

                MOVE    TB_CASEPTR, R0
                MOVE    TB_CASES, @R0

TB_NEXT_CASE    MOVE    TB_CASEPTR, R0
                MOVE    @R0, R1
                MOVE    @R1++, R2               ; R2: entries
                RBRA    TB_END, Z
                MOVE    @R1++, R3               ; R3: lines on the screen
                MOVE    @R1++, R4               ; R4: start position
                MOVE    @R1++, R5               ; R5: seed
                MOVE    @R1++, R6               ; R6: runs of random keys
                MOVE    R1, @R0

                MOVE    TB_CASE_STR, R8         ; "CASE entries lines start"
                SYSCALL(puts, 1)
                MOVE    R2, R8
                RSUB    TB_HEXSP, 1
                MOVE    R3, R8
                RSUB    TB_HEXSP, 1
                MOVE    R4, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)

                MOVE    SCR$OSM_M_DY, R0        ; the window has two more
                MOVE    R3, @R0                 ; lines (the frame)
                ADD     2, @R0
                MOVE    TB_SEED, R0
                MOVE    R5, @R0
                MOVE    TB_RUNS_LEFT, R0
                MOVE    R6, @R0
                MOVE    TB_RUN_LEFT, R0
                MOVE    0, @R0
                MOVE    TB_PRO_PTR, R0
                MOVE    TB_PROLOGUE, @R0
                MOVE    TB_PRO_LEFT, R0
                MOVE    TB_PROLOGUE_N, @R0
                MOVE    TB_PCOUNT, R0
                MOVE    0, @R0
                MOVE    TB_LASTKEY, R0
                MOVE    0, @R0

                MOVE    R2, R8                  ; build the list
                RSUB    TB_BUILD, 1
                MOVE    R8, R10                 ; R10: head of the list

                MOVE    TB_SP, R0               ; the stack of the driver
                MOVE    SP, @R0
                MOVE    R4, @--SP               ; remembered cursor position
                MOVE    IO$CYC_STATE, R0        ; count the instructions
                MOVE    CYC$RESET, @R0
                RBRA    _S_BROWSE_START, 1

                ; end of a case: back to the driver and its stack
TB_CASE_END     MOVE    TB_SP, R0
                MOVE    @R0, SP
                RBRA    TB_NEXT_CASE, 1

TB_END          MOVE    TB_DONE_STR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                SYSCALL(exit, 1)

; build a list of R8 entries at TB_LIST, the data word of an entry is its
; index; returns the head in R8
TB_BUILD        INCRB
                MOVE    TB_LIST, R0             ; R0: current entry
                XOR     R1, R1                  ; R1: its index
                XOR     R2, R2                  ; R2: previous entry
_TBB_LOOP       MOVE    R1, R4
                ADD     1, R4                   ; R4: index of the next one
                MOVE    R0, R3
                ADD     4, R3                   ; R3: next entry..
                CMP     R4, R8
                RBRA    _TBB_NOTLAST, !Z
                XOR     R3, R3                  ; ..or none
_TBB_NOTLAST    MOVE    R0, R5
                MOVE    R3, @R5++               ; SLL$NEXT
                MOVE    R2, @R5++               ; SLL$PREV
                MOVE    1, @R5++                ; SLL$DATA_SIZE
                MOVE    R1, @R5                 ; SLL$DATA: the index
                MOVE    R0, R2
                MOVE    R3, R0
                MOVE    R4, R1
                CMP     R1, R8
                RBRA    _TBB_LOOP, !Z
                MOVE    TB_LIST, R8
                DECRB
                RET

; print R8 as hex and a space; keeps all registers
TB_HEXSP        MOVE    R8, @--SP
                SYSCALL(puthex, 1)
                MOVE    0x0020, R8
                SYSCALL(putc, 1)
                MOVE    @SP++, R8
                RET

; next key of the script in R8: the prologue, then runs of random keys,
; then Run/Stop
TB_NEXTKEY      INCRB
                MOVE    TB_PRO_LEFT, R0         ; keys of the prologue left?
                CMP     0, @R0
                RBRA    _TBNK_RUN, Z
                SUB     1, @R0
                MOVE    TB_PRO_PTR, R1
                MOVE    @R1, R2
                MOVE    @R2++, R8
                MOVE    R2, @R1
                RBRA    _TBNK_RET, 1
_TBNK_RUN       MOVE    TB_RUN_LEFT, R0         ; keys of the run left?
                CMP     0, @R0
                RBRA    _TBNK_NEWRUN, Z
                SUB     1, @R0
                MOVE    TB_RUN_KEY, R1
                MOVE    @R1, R8
                RBRA    _TBNK_RET, 1
_TBNK_NEWRUN    MOVE    TB_RUNS_LEFT, R1        ; runs left?
                CMP     0, @R1
                RBRA    _TBNK_STOP, Z
                SUB     1, @R1
                RSUB    TB_RND, 1               ; R8: random word
                MOVE    R8, R2
                AND     3, R2                   ; bits 0..1: the key
                ADD     TB_KEYS, R2
                MOVE    @R2, R2
                MOVE    TB_RUN_KEY, R3
                MOVE    R2, @R3
                AND     0xFFFB, SR              ; clear C: shift in zeros
                SHR     2, R8
                AND     15, R8                  ; bits 2..5: 0..15 more keys
                MOVE    R8, @R0
                MOVE    R2, R8
                RBRA    _TBNK_RET, 1
_TBNK_STOP      MOVE    M2M$KEY_RUNSTOP, R8
_TBNK_RET       DECRB
                RET

; xorshift16 (7, 9, 8): returns the next random word in R8
TB_RND          INCRB
                MOVE    TB_SEED, R0
                MOVE    @R0, R1
                MOVE    R1, R2
                AND     0xFFFD, SR              ; clear X: shift in zeros
                SHL     7, R2
                XOR     R2, R1
                MOVE    R1, R2
                AND     0xFFFB, SR              ; clear C: shift in zeros
                SHR     9, R2
                XOR     R2, R1
                MOVE    R1, R2
                AND     0xFFFD, SR
                SHL     8, R2
                XOR     R2, R1
                MOVE    R1, @R0
                MOVE    R1, R8
                DECRB
                RET

; ----------------------------------------------------------------------------
; Stubs
; ----------------------------------------------------------------------------

HANDLE_IO       RET
KEYB$SCAN       RET

#ifdef TB_PERF

SCR$CLRINNER    RET
SELECT_LINE     RET
SHOW_DIR        MOVE    R9, R10                 ; the lists of the perf run..
                RET                             ; ..are longer than a screen

; count the instructions since the last key and note the state after it
; (R3, R4 and R6 of the browse loop), then return the next key; the count
; ends with the second instruction and starts again after the reset
KEYB$GETKEY     MOVE    IO$CYC_LO, R8
                MOVE    @R8, R8                 ; R8: low word of the count
                MOVE    R9, @--SP
                MOVE    TB_PSTATE, R9
                MOVE    R3, @R9++
                MOVE    R4, @R9++
                MOVE    R6, @R9
                INCRB
                MOVE    R8, R0                  ; R0: low word of the count
                MOVE    IO$CYC_MID, R1
                MOVE    @R1, R1                 ; R1: middle word
                MOVE    TB_PCOUNT, R2
                MOVE    @R2, R4
                ADD     R4, R4
                ADD     @R2, R4
                ADD     R4, R4                  ; R4: 6 words per entry
                ADD     TB_PTAB, R4
                MOVE    TB_LASTKEY, R5
                MOVE    @R5, @R4++              ; the key
                MOVE    R0, @R4++               ; its count
                MOVE    R1, @R4++
                MOVE    TB_PSTATE, R6
                MOVE    @R6++, R7               ; first entry on the screen..
                ADD     SLL$DATA, R7            ; ..as an index
                MOVE    @R7, @R4++
                MOVE    @R6++, @R4++            ; cursor line
                MOVE    @R6, @R4                ; absolute index
                ADD     1, @R2
                RSUB    TB_NEXTKEY, 1
                MOVE    R8, @R5
                MOVE    IO$CYC_STATE, R0
                MOVE    CYC$RESET, @R0
                DECRB
                MOVE    @SP++, R9
                RET

; print the counts of the case: "P key low middle first line index"
_IL_KEY_RUNSTOP MOVE    TB_PCOUNT, R0
                MOVE    @R0, R0
                MOVE    TB_PTAB, R1
_TBRS_LOOP      CMP     0, R0
                RBRA    _TBRS_DONE, Z
                MOVE    TB_P_STR, R8
                SYSCALL(puts, 1)
                MOVE    5, R2
_TBRS_WORD      MOVE    @R1++, R8
                RSUB    TB_HEXSP, 1
                SUB     1, R2
                RBRA    _TBRS_WORD, !Z
                MOVE    @R1++, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                SUB     1, R0
                RBRA    _TBRS_LOOP, 1
_TBRS_DONE      MOVE    TB_E_STR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RBRA    TB_CASE_END, 1

#else

; "C"
SCR$CLRINNER    MOVE    R8, @--SP
                MOVE    TB_C_STR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; "L line color"
SELECT_LINE     MOVE    R8, @--SP
                MOVE    R8, @--SP
                MOVE    TB_L_STR, R8
                SYSCALL(puts, 1)
                MOVE    @SP++, R8
                RSUB    TB_HEXSP, 1
                MOVE    R9, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    @SP++, R8
                RET

; "D index-of-first-entry entries-shown lines", returns the entries shown
; in R10 like the real SHOW_DIR
SHOW_DIR        INCRB
                MOVE    R8, R0
                XOR     R1, R1                  ; R1: entries shown
_TBSD_LOOP      CMP     R9, R1
                RBRA    _TBSD_DONE, Z
                CMP     0, R0
                RBRA    _TBSD_DONE, Z
                ADD     1, R1
                MOVE    @R0, R0                 ; SLL$NEXT is at offset 0
                RBRA    _TBSD_LOOP, 1
_TBSD_DONE      MOVE    R8, R3                  ; keep R8 and R9
                MOVE    R9, R4
                MOVE    R8, R2
                ADD     SLL$DATA, R2
                MOVE    TB_D_STR, R8
                SYSCALL(puts, 1)
                MOVE    @R2, R8
                RSUB    TB_HEXSP, 1
                MOVE    R1, R8
                RSUB    TB_HEXSP, 1
                MOVE    R4, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    R3, R8
                MOVE    R4, R9
                MOVE    R1, R10
                DECRB
                RET

; "S first-entry cursor-line shown absolute-index", then "K key"; R3 to R6
; are the registers of the browse loop
KEYB$GETKEY     MOVE    R9, @--SP
                MOVE    TB_S_STR, R8
                SYSCALL(puts, 1)
                MOVE    R3, R8
                ADD     SLL$DATA, R8
                MOVE    @R8, R8
                RSUB    TB_HEXSP, 1
                MOVE    R4, R8
                RSUB    TB_HEXSP, 1
                MOVE    R5, R8
                RSUB    TB_HEXSP, 1
                MOVE    R6, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                RSUB    TB_NEXTKEY, 1
                MOVE    R8, R9
                MOVE    TB_K_STR, R8
                SYSCALL(puts, 1)
                MOVE    R9, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                MOVE    R9, R8
                MOVE    @SP++, R9
                RET

_IL_KEY_RUNSTOP MOVE    TB_E_STR, R8
                SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RBRA    TB_CASE_END, 1

#endif

FATAL           MOVE    R8, R0
                MOVE    TB_FATAL_STR, R8
                SYSCALL(puts, 1)
                MOVE    R0, R8
                SYSCALL(puthex, 1)
                SYSCALL(crlf, 1)
                RBRA    TB_CASE_END, 1

_S_NOTHING      MOVE    TB_NOTH_STR, R8
                RBRA    TB_BAD, 1
_IL_KEY_RETURN  MOVE    TB_RETURN_STR, R8
                RBRA    TB_BAD, 1
_IL_KEY_F1_F3   MOVE    TB_F1F3_STR, R8
                RBRA    TB_BAD, 1
_S_RET          MOVE    TB_RET_STR, R8
                RBRA    TB_BAD, 1
WAIT1SEC        MOVE    TB_WAIT_STR, R8
TB_BAD          SYSCALL(puts, 1)
                SYSCALL(crlf, 1)
                RBRA    TB_CASE_END, 1

; ----------------------------------------------------------------------------
; The browse loop of SELECT_FILE, cut out of selectfile.asm
; ----------------------------------------------------------------------------

@BROWSE@

; ----------------------------------------------------------------------------
; Data
; ----------------------------------------------------------------------------

SCR$OSM_M_DY    .BLOCK  1
SD_CHANGED      .DW     0
TB_CASEPTR      .BLOCK  1
TB_SP           .BLOCK  1
TB_SEED         .BLOCK  1
TB_RUNS_LEFT    .BLOCK  1
TB_RUN_LEFT     .BLOCK  1
TB_RUN_KEY      .BLOCK  1
TB_PRO_PTR      .BLOCK  1
TB_PRO_LEFT     .BLOCK  1
TB_PCOUNT       .BLOCK  1
TB_LASTKEY      .BLOCK  1
TB_PSTATE       .BLOCK  3
_SLL_TAIL       .BLOCK  1                       ; variable of llist.asm
TB_KEYS         .DW     M2M$KEY_UP, M2M$KEY_DOWN, M2M$KEY_LEFT, M2M$KEY_RIGHT
TB_PROLOGUE     .DW     M2M$KEY_UP, M2M$KEY_UP, M2M$KEY_DOWN
                .DW     M2M$KEY_DOWN, M2M$KEY_DOWN, M2M$KEY_UP
TB_PROLOGUE_N   .EQU    6

LOG_STR_ITM_AMT .ASCII_W "I "
TB_CASE_STR     .ASCII_W "CASE "
TB_DONE_STR     .ASCII_W "DONE"
TB_S_STR        .ASCII_W "S "
TB_K_STR        .ASCII_W "K "
TB_C_STR        .ASCII_W "C"
TB_D_STR        .ASCII_W "D "
TB_L_STR        .ASCII_W "L "
TB_E_STR        .ASCII_W "E"
TB_P_STR        .ASCII_W "P "
TB_FATAL_STR    .ASCII_W "FATAL "
TB_NOTH_STR     .ASCII_W "BAD _S_NOTHING"
TB_RETURN_STR   .ASCII_W "BAD _IL_KEY_RETURN"
TB_F1F3_STR     .ASCII_W "BAD _IL_KEY_F1_F3"
TB_RET_STR      .ASCII_W "BAD _S_RET"
TB_WAIT_STR     .ASCII_W "BAD WAIT1SEC"

#include "@LLIST@"

TB_CASES        @CASES@
                .DW     0
"""

PROLOGUE = (UP, UP, DOWN, DOWN, DOWN, UP)


def testbed(code, cases, perf):
    rows = "\n                ".join(".DW     %d, %d, %d, 0x%04X, %d" % c for c in cases)
    t = TESTBED
    for k, v in (("@QSYSDEF@", QSYSDEF), ("@MONDEF@", MONDEF), ("@M2MSYSDEF@", M2MSYSDEF),
                 ("@LLIST@", LLIST), ("@PERF@", "#define TB_PERF" if perf else ""),
                 ("@CASES@", rows), ("@BROWSE@", code)):
        t = t.replace(k, v)
    return t


def run(code, cases, perf, work):
    open(os.path.join(work, "browse_nav_tb.asm"), "w").write(testbed(code, cases, perf))
    out = os.path.join(work, "browse_nav_tb.out")
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([ASM, "browse_nav_tb.asm"], cwd=work, capture_output=True, text=True,
                       timeout=120)
    if r.returncode != 0 or not os.path.exists(out) or "rror" in r.stdout:
        return None, "assembly failed: " + (r.stdout + r.stderr)[-3000:]
    try:
        r = subprocess.run([EMU, "-b", "0x8000", MON, out], stdin=subprocess.DEVNULL,
                           capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return None, "emulator timeout"
    lines = [l.strip() for l in r.stdout.replace("\r", "").split("\n") if l.strip()]
    if "DONE" not in lines:
        return None, "the testbed did not finish: " + "\n".join(lines[-20:])
    first = next((i for i, l in enumerate(lines) if l.startswith("CASE ")), 0)
    return lines[first:lines.index("DONE")], ""


# ---------------------------------------------------------------------------
# Model of the browser (written from the behavior described above, not from
# the assembly code): the first entry on the screen (top), the cursor line
# and the absolute index of the cursor
# ---------------------------------------------------------------------------
def model_start(n, rows, start):
    if start < rows:
        return [0, start, start]
    top, row = divmod(start, rows)
    top *= rows
    if top + rows > n:                          # the last screen is full
        under = top + rows - n
        top -= under
        row += under
    return [top, row, top + row]


def model_key(st, key, n, rows):
    """New state and kind of the key; the kinds with "scroll" in the name
    redraw the screen once, the others do not redraw it"""
    top, row, a = st
    vis = min(n, rows)
    if key == UP:
        if a == 0:                              # wrap around to the last
            a, ntop = n - 1, max(0, n - rows)
            kind = "wrap, scroll" if ntop != top else "wrap"
            top, row = ntop, n - 1 - ntop
        elif row > 0:
            row, a, kind = row - 1, a - 1, "line"
        else:
            top, a, kind = top - 1, a - 1, "scroll by one"
    elif key == DOWN:
        if a == n - 1:                          # wrap around to the first
            kind = "wrap, scroll" if top != 0 else "wrap"
            top, row, a = 0, 0, 0
        elif row < vis - 1:
            row, a, kind = row + 1, a + 1, "line"
        else:
            top, a, kind = top + 1, a + 1, "scroll by one"
    elif key == LEFT:
        if top == 0:                            # first page: first entry
            row, a, kind = 0, 0, "page, first/last entry"
        else:
            s = min(rows, top)
            top, a, kind = top - s, a - s, "page, scroll"
    elif key == RIGHT:
        below = n - (top + vis)
        if below == 0:                          # last page: last entry
            row, a, kind = vis - 1, n - 1, "page, first/last entry"
        else:
            s = min(rows, below)
            top, a, kind = top + s, a + s, "page, scroll"
    else:
        raise ValueError("unknown key 0x%04X" % key)
    return [top, row, a], kind


# ---------------------------------------------------------------------------
# Replay of the trace
# ---------------------------------------------------------------------------
def hexs(line, count):
    parts = line.split()
    if len(parts) != count + 1:
        raise ValueError("malformed line: " + line)
    return [int(p, 16) for p in parts[1:]]


def check_trace(lines):
    """Returns (number of checked keys, list of errors)"""
    errors, keys, i = [], 0, 0
    while i < len(lines):
        if not lines[i].startswith("CASE "):
            errors.append("expected CASE, got %r" % lines[i])
            break
        n, rows, start = hexs(lines[i], 3)
        name = "%d entries, %d lines, start %d" % (n, rows, start)
        i += 1
        st, vis, key, kind = model_start(n, rows, start), min(n, rows), 0, "start"
        top_shown, count_shown, hl, history = None, 0, set(), []
        redraws, failed = 0, False
        while i < len(lines):
            l = lines[i]
            i += 1
            try:
                if l == "C":
                    top_shown, count_shown, hl = None, 0, set()
                elif l.startswith("D "):
                    top_shown, count_shown, r = hexs(l, 3)
                    redraws += 1
                    if r != rows:
                        raise ValueError("SHOW_DIR for %d lines" % r)
                elif l.startswith("L "):
                    line, col = hexs(l, 2)
                    if top_shown is None or not 0 <= line < count_shown:
                        raise ValueError("SELECT_LINE of line %d of %d" % (line, count_shown))
                    if col == COL_INV:
                        hl.add(line)
                    elif col == COL_STD:
                        hl.discard(line)
                    else:
                        raise ValueError("SELECT_LINE with color 0x%02X" % col)
                elif l.startswith("I "):
                    if hexs(l, 1)[0] != n:
                        raise ValueError("the browser counted %d entries" % hexs(l, 1)[0])
                elif l.startswith("S "):
                    got = hexs(l, 4)
                    want = [st[0], st[1], st[0] + vis, st[2]]
                    if got != want:
                        raise ValueError("state %s, model %s" % (got, want))
                    if top_shown != st[0] or count_shown != vis:
                        raise ValueError("the screen shows %d entries from %s, model %d from %d"
                                         % (count_shown, top_shown, vis, st[0]))
                    if hl != {st[1]}:
                        raise ValueError("highlighted lines %s, model line %d" % (sorted(hl), st[1]))
                    want_redraws = 1 if (kind == "start" or "scroll" in kind) else 0
                    if redraws != want_redraws:
                        raise ValueError("%d redraws for %s (%s), model %d"
                                         % (redraws, KEYNAME[key], kind, want_redraws))
                    redraws = 0
                elif l.startswith("K "):
                    key = hexs(l, 1)[0]
                    history.append(KEYNAME.get(key, hex(key)))
                    if key == RUNSTOP:
                        if lines[i] != "E":
                            raise ValueError("Run/Stop did not end the case: " + lines[i])
                        i += 1
                        break
                    st, kind = model_key(st, key, n, rows)
                    keys += 1
                else:
                    raise ValueError("unexpected line: " + l)
            except (ValueError, IndexError) as e:
                errors.append("%s, after the keys %s: %s"
                              % (name, " ".join(history[-8:]) or "(none)", e))
                failed = True
            if failed:
                while i < len(lines) and not lines[i].startswith("CASE "):
                    i += 1
                break
    return keys, errors


def perf_counts(lines):
    """kind of key -> list of (instructions, entries the screen moved); the
    kind comes from the states before and after the key, which the testbed
    noted, so that it also works for a selectfile.asm without wrap-around"""
    res, i = {}, 0
    while i < len(lines):
        hexs(lines[i], 3)
        i += 1
        prev = None
        while lines[i] != "E":
            l = lines[i]
            i += 1
            if not l.startswith("P "):
                continue
            key, lo, mid, top, row, a = hexs(l, 6)
            count, moved = lo + (mid << 16), 0
            if prev is None:
                kind = "start (first screen)"
            else:
                ptop, prow, pa = prev
                moved = abs(top - ptop)
                if (top, row, a) == prev:
                    kind = "ignored"
                elif moved == 0:
                    kind = "cursor moves by one" if abs(a - pa) == 1 else "cursor jumps on the screen"
                elif moved == 1 and abs(a - pa) == 1:
                    kind = "scroll by one"
                else:
                    kind = "wrap, scroll" if key in (UP, DOWN) else "page, scroll"
                kind = "%s: %s" % ("Up/Down" if key in (UP, DOWN) else "Left/Right", kind)
            res.setdefault(kind, []).append((count, moved))
            prev = (top, row, a)
        i += 1
    return res


# ---------------------------------------------------------------------------
# Cases and mutants
# ---------------------------------------------------------------------------
def cases():
    out, seed = [], 0xACE1
    for rows in (3, 7, 27):
        sizes = {1, 2, rows - 1, rows, rows + 1, 2 * rows - 1, 2 * rows, 2 * rows + 1,
                 3 * rows + 5, 100, 1927}
        for n in sorted(s for s in sizes if s >= 1):
            for start in sorted({0, n - 1, n // 2, min(n - 1, rows), min(n - 1, rows + 1)}):
                seed = (seed * 75 + 74) % 65537 or 1
                out.append((n, rows, start, seed & 0xFFFF or 1, 24))
    return out


PERF_CASES = [(n, 27, start, 0x1234 + start, 40) for n in (100, 1927)
              for start in (0, n // 2, n - 1)]

MUTANTS = [
    ("Cursor Up on the first entry is ignored",
     "RBRA    _IL_WRAP_BTTM, !N", "RBRA    _S_INPUT_LOOP, !N"),
    ("Cursor Down on the last entry of a short list is ignored",
     "(bottom reached?)\n                RBRA    _IL_WRAP_TOP, Z",
     "(bottom reached?)\n                RBRA    _S_INPUT_LOOP, Z"),
    ("Cursor Down on the last entry of a long list is ignored",
     "already shown?\n                RBRA    _IL_WRAP_TOP, Z",
     "already shown?\n                RBRA    _S_INPUT_LOOP, Z"),
    ("the wrap to the last entry scrolls too far",
     "                SUB     R5, R10                 ; ..below the screen\n", ""),
    ("the wrap to the last entry keeps the absolute index",
     "                MOVE    R4, R6                  ; ..the abs. index of the line\n", ""),
    ("the wrap to the last entry puts the cursor below the screen",
     "                SUB     1, R4                   ; ..of the screen and R6 to..\n", ""),
    ("the wrap to the first entry tests the wrong condition",
     "RBRA    _IL_GOTO_TOP, !N        ; no: first entry is visible",
     "RBRA    _IL_GOTO_TOP, N         ; no: first entry is visible"),
    ("the wrap to the first entry keeps the cursor line",
     "                XOR     R4, R4                  ; ..where the cursor goes\n", ""),
    ("the wrap to the first entry scrolls by one entry only",
     "MOVE    R6, R10                 ; R10: amount of entries..",
     "MOVE    1, R10                  ; R10: amount of entries.."),
    ("Cursor Left turns one entry less than a page",
     "_IL_PAGE_DEFUP  MOVE    R2, R10                 ; R10: one page up\n",
     "_IL_PAGE_DEFUP  MOVE    R2, R10                 ; R10: one page up\n"
     "                SUB     1, R10\n"),
]


def summary(res):
    out = []
    for kind in sorted(res):
        c = sorted(x[0] for x in res[kind])
        out.append("  %-42s %5d keys %6d .. %6d instructions" % (kind, len(c), c[0], c[-1]))
        if kind.endswith("wrap, scroll"):
            per = {}
            for count, moved in res[kind]:
                per.setdefault(moved, []).append(count)
            for d, x in sorted(per.items()):
                out.append("  %-42s %5d keys %6d .. %6d instructions"
                           % ("    screen moves by %d entries" % d, len(x), min(x), max(x)))
    return "\n".join(out)


def main():
    for f in (ASM, EMU, MON):
        if not os.path.exists(f):
            sys.exit("missing %s, see README.md" % f)
    work = tempfile.mkdtemp(prefix="browse_nav_test_")
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "--perf-only":
            lines, err = run(browse_loop(sys.argv[2]), PERF_CASES, True, work)
            if lines is None:
                sys.exit("FAIL: " + err)
            print("Instructions per key of %s:" % sys.argv[2])
            print(summary(perf_counts(lines)))
            return 0

        code = browse_loop(SELECTFILE)
        all_cases = cases()
        lines, err = run(code, all_cases, False, work)
        if lines is None:
            print("FAIL: " + err)
            return 1
        keys, errors = check_trace(lines)
        if len([l for l in lines if l.startswith("CASE ")]) != len(all_cases):
            errors.append("only %d of %d cases ran"
                          % (len([l for l in lines if l.startswith("CASE ")]), len(all_cases)))
        if errors:
            print("FAIL: %d errors, the first ones:" % len(errors))
            print("\n".join("  " + e for e in errors[:10]))
            return 1
        print("OK: %d cases, %d keys, the trace matches the model" % (len(all_cases), keys))

        caught = 0
        for name, old, new in MUTANTS:
            if code.count(old) != 1:
                print("FAIL: the mutant %r does not apply (%d matches)" % (name, code.count(old)))
                return 1
            mlines, err = run(code.replace(old, new), all_cases, False, work)
            if mlines is not None:
                k, merr = check_trace(mlines)
                if not merr and len([l for l in mlines if l.startswith("CASE ")]) == len(all_cases):
                    print("FAIL: mutant not caught: " + name)
                    return 1
            caught += 1
        print("OK: %d of %d mutants caught" % (caught, len(MUTANTS)))

        lines, err = run(code, PERF_CASES, True, work)
        if lines is None:
            print("FAIL: perf run: " + err)
            return 1
        print("Instructions per key (lists of 100 and 1,927 entries, 27 lines):")
        print(summary(perf_counts(lines)))
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
