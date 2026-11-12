#!/usr/bin/env python3
"""
Static regression test: worst-case register bank nesting depth of the QNICE
firmware (the Shell together with the QNICE Monitor it includes).

Register banks
--------------
The QNICE registers R0..R7 are a window into a register file of
SHADOW_REGFILE_SIZE banks of eight registers each; R8..R15 are not banked.
The number of the active bank is held in the upper eight bits of the status
register SR. INCRB selects the next bank and DECRB the previous one, so a
routine that starts with INCRB and ends with DECRB gets eight fresh registers
without saving anything. The Monitor routines behind SYSCALL(enter, 1) and
SYSCALL(leave, 1) (MISC$ENTER and MISC$LEAVE in misc_library.asm) execute
INCRB twice and DECRB twice: a routine framed by enter/leave costs two bank
levels, a routine framed by INCRB/DECRB costs one. The bank level is 0 after
the cold start ("AND 0x00FF, SR" in INIT_FIRMWARE) and grows with every
nested frame.

Why this test exists
--------------------
The hardware register file has SHADOW_REGFILE_SIZE banks
(M2M/vhdl/QNICE/qnice_globals.vhd) and M2M/QNICE/vhdl/register_file.vhd
indexes it with "bank * 8 + register". A level at or above the number of
banks therefore aliases a lower bank and silently overwrites the registers of
routines further up the call chain. Nothing crashes at that moment; values
change later. The emulator testbeds cannot notice this: the QNICE emulator
uses all eight bits of the bank number (256 banks), and the testbeds do not
run the long call chains of the real firmware anyway. The deepest chains are
the invisible menu sessions of the keyboard shortcuts, which run the whole
menu engine, the file browser and the FAT32 library nested inside the main
loop.

How the analysis works
----------------------
The test preprocesses CORE/m2m-rom/m2m-rom.asm with the C preprocessor
exactly like M2M/QNICE/assembler/asm (RELEASE build, the QNICE Monitor is
part of the ROM), parses the qasm syntax and computes for every routine a
summary: the highest bank level reached relative to its entry, including
everything it calls, and the set of levels at which it returns. Within a
routine the analysis follows every path separately (conditional branches,
loops, fall-through into the next label, jumps into other routines as tail
calls), so the result is a worst case over all paths and not over source
lines. MISC$ENTER and MISC$LEAVE are analyzed like any other routine (+2/-2).
Two more things are tracked along each path: constants loaded into the
registers that select the target of a dispatcher (R7 for _OPTM_CALL, R10 for
FAT32$CALL_DEV) and copies of SR ("MOVE SR, Rn"), so that restoring such a
copy ("MOVE Rn, SR", used by STRROM$OPEN to keep the flags of its caller)
restores exactly the level at which the copy was taken.

The scenario table
------------------
The maximum is reported for the boot, the main loop without a key, the
visible menu (Help key), the debug Monitor and every action of the keyboard
shortcut jump table SC_ACTIONS:

    static     worst case of the call graph from this entry
    realistic  static without the key repeat edge _SC_REP_TICK -> SC_KEY for
               actions that never repeat: the repeat is only armed when an
               action returns Carry = 1 (Volume) and Help stops it
    clean      realistic, and FAT32$FLUSH finds no dirty sector buffer, i.e.
               no disk image write-back is pending on the same device

The verdict uses the static maximum over everything reachable from the reset
vector, which includes all scenarios.

Known limits
------------
* Indirect calls and jumps are resolved by the hand-made table INDIRECT
  below. A new indirect site, or an entry that no longer matches the code,
  makes the test fail until the table is updated.
* The two debug Monitor commands that run code at an address typed by the
  user or at the start of a file loaded from the SD card are not followed.
* Interrupts are not modeled. The Shell does not use them: the interrupt
  input of the CPU is tied to '1' in M2M/vhdl/QNICE/qnice.vhd and the
  firmware contains no RTI or INT instruction (one would fail the test).
* RET is assumed to return to the caller. Non-local exits are modeled as the
  end of a path: FATAL ends in the warm start of the Monitor ("AND 0x00FF,
  SR"), CTRL+E and the debug key combination enter the Monitor, which is
  analyzed as a separate root.
* Data values are not known beyond the tracked constants, so "static" may
  contain combinations that cannot happen at run time; the margin below
  covers that and the depth that the analysis cannot see.

Usage
-----
    python3 bankdepth_test.py [TREE] [--limit N] [--report] [--top N]
                              [--explain ROUTINE] [--via ROUTINE]
                              [--all-routines] [--selftest]

TREE defaults to the repository that contains this file. The number of banks
is read from M2M/vhdl/QNICE/qnice_globals.vhd of TREE unless --limit is
given. --report prints the deepest chains hop by hop, the top chains and the
sanity sections. --explain lists every call site of a routine with the level
reached through it, --via the deepest level reached inside the given routines
per scenario. --selftest checks that deliberate defects in an in-memory copy
of the preprocessed source are detected. Needs a C preprocessor "cc" (like
the assembler). Exit code 0 = pass, 1 = fail.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile
import textwrap
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
ENTRY = os.path.join("CORE", "m2m-rom", "m2m-rom.asm")
GLOBALS_VHD = os.path.join("M2M", "vhdl", "QNICE", "qnice_globals.vhd")

# Minimum number of unused banks above the static maximum. New features tend
# to add frames on the deepest paths (the keyboard shortcut sessions run the
# whole menu engine and file browser nested in the main loop), and the
# analysis cannot see everything (see "Known limits"). A margin below this
# value means the next feature could silently corrupt registers.
MIN_MARGIN = 8

# ---------------------------------------------------------------------------
# Indirect call / jump resolution table
#
# Key: (nearest preceding label, mnemonic, first operand) of the indirect site.
# Kinds:
#   targets      : list of code labels that can be called/jumped to
#   table        : name of a .DW table whose words are the possible targets
#   dispatch     : the routine is a dispatcher: the target depends on the
#                  value that register 'reg' holds at the ENTRY of the routine
#                  (tracked as a constant along every path of each caller);
#                  'map' maps that constant to targets, or 'record' names a
#                  .DW record whose word #index is the target (index = value
#                  of an .EQU constant whose name starts with one of
#                  'prefixes'); 'patch' adds run-time patched targets.
#                  Tracking: "MOVE <constant>, Rn" sets it; any other write,
#                  @Rn++/@--Rn and any call reset it; INCRB/DECRB reset R0..R7
#                  (banked) but not R8..R12 (not banked); a call keeps a
#                  banked value if the callee never writes that register in
#                  the bank of the caller (or saves and restores it).
#   nop          : ABRA R15, 1 = the NOP macro, falls through
#   unresolvable : target unknown; the path is not followed
# ---------------------------------------------------------------------------
INDIRECT = {
    # menu.asm _OPTM_CALL: "MOVE @R7, R7 / ASUB R7, 1": R7 on entry is an
    # index into the menu initialization record that OPTM_INIT stored in
    # OPTM_DATA. The only record ever passed to OPTM_INIT is the heap copy of
    # OPT_MENU_DATA (options.asm, HELP_MENU_INIT -> OPTM_INIT; HELP_MENU
    # copies OPT_MENU_DATA to HEAP). Index constants: OPTM_FP_* / OPTM_CLBK_*
    # in menu.asm. The only run-time patch of the record is SC$PRESS_IN
    # (shortcuts.asm), which replaces OPTM_FP_GETKEY by _SC_GETKEY while it
    # runs OPTM_RUN invisibly.
    ('_OPTM_CALL', 'ASUB', 'R7'): {
        'kind': 'dispatch', 'reg': 'R7', 'record': 'OPT_MENU_DATA',
        'prefixes': ('OPTM_FP_', 'OPTM_CLBK_'),
        'patch': {'OPTM_FP_GETKEY': ['_SC_GETKEY']},
        'note': 'menu init record OPT_MENU_DATA (options.asm) indexed by '
                'OPTM_FP_*/OPTM_CLBK_*; GETKEY patched to _SC_GETKEY by '
                'SC$PRESS_IN (shortcuts.asm)'},
    # shortcuts.asm SC$IN_SESSION: "ASUB R0" with R0 = @SC_S_ROUTINE, which
    # only SC$SESSION writes, from its R8. Callers of SC$SESSION:
    # SC$PRESS (R8 = SC$PRESS_IN) and _SCK_NEXT in shortcuts_c64.asm
    # (R8 = SC_NEXT_IN).
    ('SC$IN_SESSION', 'ASUB', 'R0'): {
        'kind': 'targets', 'targets': ['SC$PRESS_IN', 'SC_NEXT_IN'],
        'note': 'SC_S_ROUTINE, written only by SC$SESSION; callers pass '
                'SC$PRESS_IN (SC$PRESS) or SC_NEXT_IN (_SCK_NEXT)'},
    # shortcuts_c64.asm SC_KEY: "ABRA R2" with R2 = SC_ACTIONS[action].
    ('_SCK_FOUND', 'ABRA', 'R2'): {
        'kind': 'table', 'table': 'SC_ACTIONS',
        'note': 'jump table SC_ACTIONS (shortcuts_c64.asm)'},
    # fat32_library.asm FAT32$CALL_DEV: "ASUB @R0" through the device handle.
    # The only code that fills a device handle is FAT32$MOUNT_SD, which stores
    # the five SD$ functions (the Shell never calls FAT32$MOUNT directly).
    # R10 on entry is the function index FAT32$DEV_* (every caller loads it
    # with "MOVE FAT32$DEV_..., R10" right before the call).
    ('FAT32$CALL_DEV', 'ASUB', '@R0'): {
        'kind': 'dispatch', 'reg': 'R10',
        'map': {'FAT32$DEV_RESET': ['SD$RESET'],
                'FAT32$DEV_BLOCK_READ': ['SD$READ_BLOCK'],
                'FAT32$DEV_BLOCK_WRITE': ['SD$WRITE_BLOCK'],
                'FAT32$DEV_BYTE_READ': ['SD$READ_BYTE'],
                'FAT32$DEV_BYTE_WRITE': ['SD$WRITE_BYTE']},
        'note': 'device handle filled only by FAT32$MOUNT_SD; R10 = '
                'FAT32$DEV_* function index'},
    # llist.asm SLL$APPEND: filter function in R10 of the caller; the only
    # caller is DIRBROWSE_READ, which passes 0 or _DIRBR_FILTWRAP.
    ('SLL$APPEND', 'ASUB', 'R2'): {
        'kind': 'targets', 'targets': ['_DIRBR_FILTWRAP'],
        'note': 'only caller DIRBROWSE_READ passes 0 or _DIRBR_FILTWRAP'},
    # llist.asm SLL$SORT/_SORT_MERGE: comparator; the only callers
    # (DIRBROWSE_READ, twice) pass _DIRBR_COMPARE.
    ('_SORT_MERGE', 'ASUB', 'R11'): {
        'kind': 'targets', 'targets': ['_DIRBR_COMPARE'],
        'note': 'only callers (DIRBROWSE_READ) pass _DIRBR_COMPARE'},
    # dirbrowse.asm _DIRBR_FILTWRAP: "ASUB @R1" = @_DIRBR_FILTERFN, set by
    # DIRBROWSE_READ from R12; all callers (selectfile.asm x2, vdrives.asm)
    # pass FILTER_FILES (core callback in m2m-rom.asm) or 0.
    ('_DIRBR_FILTWRAP', 'ASUB', '@R1'): {
        'kind': 'targets', 'targets': ['FILTER_FILES'],
        'note': '_DIRBR_FILTERFN = R12 of DIRBROWSE_READ = FILTER_FILES'},
    # fat32_library.asm: NOP macro (#define NOP ABRA R15, 1)
    ('_F32_DLST_VITAL', 'ABRA', 'R15'): {'kind': 'nop', 'note': 'NOP macro'},
    # qmon_m2m.asm: debug Monitor commands that run code at an address typed
    # by the user (C/R) or at the start address of a loaded file (F/R).
    ('QMON$C_MAYBE_R', 'ABRA', 'R8'): {
        'kind': 'unresolvable',
        'note': 'Monitor C/R: jump to a user-typed address'},
    ('QMON$F_MAYBE_R', 'ABRA', 'R6'): {
        'kind': 'unresolvable',
        'note': 'Monitor F/R: run a file loaded from SD card'},
}

# Writes to SR that change the bank bits and need special knowledge. Other SR
# writes are understood generically: AND/OR/XOR with a constant that leaves
# bits 15..8 alone (flags only), "AND 0x00FF, SR" (absolute bank 0: the path
# ends as a restart, roots start there) and "MOVE Rn, SR" where Rn holds a
# copy of SR taken on the same path (restores the level of the copy).
SR_SPECIAL = {
    # QMON$SOFTMON saves SR to _QMON$SR, QMON$SOFTSTART (directly after it)
    # restores it. Inside the Monitor roots below this is the root level.
    # Jumps into QMON$SOFTMON/QMON$SOFTSTART from anywhere else are non-local
    # exits (see MONITOR_ENTRY), so the restore never runs in another context.
    ('QMON$SOFTSTART', 'MOVE', '@R8'): 'same',
}

# Roots: the reset vector. Execution starts at address 0 = "reset!".
ROOTS = ['reset']
# Code that starts with "AND 0x00FF, SR" (absolute bank 0) and is reached by
# a jump from elsewhere: the warm start of the Monitor (FATAL -> exit ->
# MISC$EXIT -> QMON$WARMSTART; Monitor commands). Analyzed as separate roots.
# QMON$SOFTMON: the debug Monitor, entered from START_MONITOR (shell.asm,
# reached from CHECK_DEBUG) with "INCRB / RBRA QMON$SOFTMON". It saves SR+SP
# and runs the Monitor loop at that level; IO$GETCHAR jumps back to
# QMON$SOFTSTART on CTRL+E, which restores the saved SR+SP (non-local exit).
EXTRA_ROOTS = ['QMON$WARMSTART', 'QMON$COLDSTART', 'QMON$SOFTMON']
# A jump (not a fall-through) to one of these labels from code that is not a
# Monitor root ends the path ("enters the Monitor", never returns).
MONITOR_ENTRY = {'QMON$SOFTMON', 'QMON$SOFTSTART'}
MONITOR_ROOTS = {'QMON$SOFTMON', 'QMON$WARMSTART', 'QMON$COLDSTART'}
# The routine that jumps into the Monitor (to compute the Monitor base level).
MONITOR_CALLER = 'CHECK_DEBUG'

# Routines that intentionally return at another level than their entry
# (exits relative to the entry). Every other routine has to return at the
# level of its entry on every path, or never return.
EXPECTED_EXITS = {
    'MISC$ENTER': [2],          # the two INCRB of SYSCALL(enter)
    'MISC$LEAVE': [-2],         # the two DECRB of SYSCALL(leave)
    # vdrives.asm: VD_DTY_ST_GET executes INCRB twice and calls this helper,
    # whose final DECRB (via _VDD_C0/_VDD_C1) undoes one of them
    '_VDDTY_GETINFO': [-1],
}

# ---------------------------------------------------------------------------
# Scenarios
# ---------------------------------------------------------------------------

# The boot scenario ends where the main loop starts.
MAIN_LOOP = 'MAIN_LOOP'
# Branches of HELP_MENU (options.asm) and CHECK_DEBUG (shell.asm) that select
# a scenario: no Help key, visible menu or invisible shortcut session, debug
# key combination. Key: (nearest label, mnemonic, target, condition).
BR_NO_HELP_KEY = ('HELP_MENU', 'RBRA', '_HLP_RET_DIRECT', '!Z')
BR_DIRECT_SESSION = ('_HLP_HEAP2_OK', 'RBRA', '_HLP_DIRECT', '!Z')
BR_DEBUG_KEYS = ('CHECK_DEBUG', 'RBRA', 'START_MONITOR', 'Z')
# Shortcut actions: the jump table, its indirect site, the indirect call of
# the session routine and the routine that each action installs.
SC_TABLE = 'SC_ACTIONS'
SC_TABLE_SITE = ('_SCK_FOUND', 'ABRA', 'R2')
SC_SESSION_SITE = ('SC$IN_SESSION', 'ASUB', 'R0')
SC_PRESS_ROUTINE = 'SC$PRESS_IN'            # Mount, Load PRG, Load CRT
SC_NEXT_ROUTINE = 'SC_NEXT_IN'              # actions with NEXT in the label
SC_ENTRY = 'SC$MAIN'
# The key function of the menu: interactive in the visible menu, scripted in
# the invisible session.
GETKEY_INDEX = 'OPTM_FP_GETKEY'
GETKEY_MENU = 'OPT_MENU_GETKEY'
GETKEY_SESSION = '_SC_GETKEY'

# "realistic" column: the key repeat (_SC_REP_TICK -> SC_KEY, shortcuts.asm)
# is only armed when SC_KEY returned Carry = 1, i.e. when the action ended at
# REPEAT_LABEL (shortcuts_c64.asm: only Volume up/down). The picker of a held
# key cannot change without opening the menu, and Help clears SC_REP_KEY
# (SC$MAIN). So for actions that cannot reach REPEAT_LABEL the edge
# _SC_REP_TICK -> SC_KEY is infeasible.
REPEAT_EDGE = ('_SC_REP_TICK', 'SC_KEY')
REPEAT_LABEL = '_SCK_REPEAT'

# "clean" column: FAT32$FLUSH returns early because the handle that owns the
# 512-byte sector buffer is not dirty (fat32_library.asm). A dirty owner
# exists while FLUSH_CACHE (shell.asm) writes a disk image back in chunks
# (it calls f32_fflush only after the last chunk), so the dirty case is
# realistic too; "clean" shows the depth without it.
CLEAN_FORCE = {('FAT32$FLUSH', 'RBRA', '_FAT32$FLUSH_R', 'Z'): True}

# ---------------------------------------------------------------------------
# Assembler syntax
# ---------------------------------------------------------------------------

CONDS_ALWAYS = {'1'}
MNEM_NORMAL = {'MOVE', 'ADD', 'ADDC', 'SUB', 'SUBC', 'SHL', 'SHR', 'SWAP',
               'NOT', 'AND', 'OR', 'XOR', 'CMP'}
MNEM_CTRL = {'HALT', 'RTI', 'INT', 'INCRB', 'DECRB', 'EXC'}
MNEM_BRANCH = {'ABRA', 'ASUB', 'RBRA', 'RSUB'}
DIRECTIVES = {'.ORG', '.ASCII_W', '.ASCII_P', '.EQU', '.BLOCK', '.DW'}
ALL_MNEM = MNEM_NORMAL | MNEM_CTRL | MNEM_BRANCH | DIRECTIVES

LEVEL_CAP = 256                 # the bank number has eight bits
GENERATED = ['osm_const.asm', 'globals.asm', 'shell_fhandles.asm',
             'shell_fh_ptrs.asm']
REG_RE = re.compile(r'^(@?)(--)?R(\d+)(\+\+)?$', re.I)


class Item:
    """one assembler line that emits something (instruction or data)"""
    __slots__ = ('idx', 'file', 'line', 'label', 'mnem', 'ops', 'text',
                 'nearest')

    def __init__(self, idx, file, line, label, mnem, ops, text):
        self.idx, self.file, self.line = idx, file, line
        self.label, self.mnem, self.ops, self.text = label, mnem, ops, text
        self.nearest = None

    def where(self):
        return '%s:%d' % (os.path.basename(self.file), self.line)


class TestError(Exception):
    """a problem that prevents the test from running at all"""


# ---------------------------------------------------------------------------
# Preprocessing and parsing
# ---------------------------------------------------------------------------

def preprocess(root):
    """run the C preprocessor like M2M/QNICE/assembler/asm, but keep the
    line markers; the files that make_rom.sh generates hold only data, so
    empty stand-ins in a temporary folder are used when they are missing"""
    path = os.path.join(root, ENTRY)
    if not os.path.isfile(path):
        raise TestError('%s not found: is %s the root of the repository?' %
                        (ENTRY, root))
    with tempfile.TemporaryDirectory(prefix='bankdepth_') as sroot:
        # shell.asm includes "../../CORE/m2m-rom/shell_fh_ptrs.asm", so the
        # include folder is x/y and the stand-ins also exist in CORE/m2m-rom
        incdir = os.path.join(sroot, 'x', 'y')
        for d in (incdir, os.path.join(sroot, 'CORE', 'm2m-rom')):
            os.makedirs(d)
            for g in GENERATED:
                open(os.path.join(d, g), 'w').close()
        try:
            proc = subprocess.run(['cc', '-xc', '-E', '-w', '-I', incdir,
                                   os.path.basename(path)],
                                  cwd=os.path.dirname(path),
                                  capture_output=True, text=True,
                                  errors='replace')
        except OSError as e:
            raise TestError('cannot run the C preprocessor "cc": %s' % e)
        if proc.returncode != 0:
            raise TestError('the C preprocessor failed:\n' + proc.stderr)
        used = sorted({os.path.basename(f) for f in re.findall(
            r'"([^"]*)"', proc.stdout) if f.startswith(sroot)})
        return proc.stdout, used


def strip_comment(line):
    """qasm: a comment starts at ";" unless a double quote comes first"""
    p = line.find(';')
    q = line.find('"')
    if p >= 0 and (q < 0 or p < q):
        return line[:p]
    return line


def split_ops(s):
    """split operands at commas outside of quotes"""
    out, cur, q = [], '', None
    for ch in s:
        if q:
            cur += ch
            if ch == q:
                q = None
            continue
        if ch in '"\'':
            q = ch
            cur += ch
            continue
        if ch == ',':
            out.append(cur.strip())
            cur = ''
            continue
        cur += ch
    if cur.strip() or out:
        out.append(cur.strip())
    return out


def parse(pp):
    """returns items, labels (name -> item index), equs (name -> value) and
    a list of lines that could not be parsed"""
    items = []
    labels = {}
    equs = {}
    pending = []         # labels on their own line
    problems = []
    cur_file, cur_line = '?', 0
    for raw in pp.split('\n'):
        if raw.startswith('#'):
            m = re.match(r'#\s*(\d+)\s+"([^"]*)"', raw)
            if m:
                cur_line = int(m.group(1)) - 1
                cur_file = m.group(2)
            continue
        cur_line += 1
        line = strip_comment(raw).rstrip()
        if not line.strip():
            continue
        col1 = not line[0].isspace()
        s = line.strip().replace('\t', ' ')
        first = re.split(r'[ ,]+', s, maxsplit=1)[0]
        label = None
        rest = s
        if first.upper() not in ALL_MNEM:
            if not col1:
                problems.append('%s:%d: %s' % (os.path.basename(cur_file),
                                               cur_line, s))
                continue
            label = first[:-1] if first.endswith('!') else first
            rest = s[len(first):].strip()
            if not rest:
                pending.append(label)
                continue
        m = re.match(r'^(\S+)\s*(.*)$', rest)
        mnem = m.group(1).upper()
        if mnem not in ALL_MNEM:
            problems.append('%s:%d: %s' % (os.path.basename(cur_file),
                                           cur_line, s))
            continue
        ops = split_ops(m.group(2)) if m.group(2) else []
        if mnem == '.EQU':
            if label:
                equs[label] = ops[0] if ops else ''
            continue
        it = Item(len(items), cur_file, cur_line, label, mnem, ops, s)
        for pl in pending:
            labels[pl] = it.idx
        if label:
            labels[label] = it.idx
        it.label = (pending + ([label] if label else [])) or None
        pending = []
        items.append(it)
    near = None
    for it in items:
        if it.label:
            near = it.label[-1]
        it.nearest = near
    return items, labels, equs, problems


def to_int(s):
    s = s.strip()
    try:
        if s.lower().startswith('0x'):
            return int(s, 16)
        if s.lower().startswith('0b'):
            return int(s[2:], 2)
        return int(s)
    except ValueError:
        return None


def dw_words(items, labels, name):
    """words of the .DW table that starts at label 'name' (until next label)"""
    if name not in labels:
        return None
    i = labels[name]
    words = []
    while i < len(items):
        it = items[i]
        if i != labels[name] and it.label:
            break
        if it.mnem != '.DW':
            break
        words += [w for w in it.ops if w != '']
        i += 1
    return words


def reg_of(op):
    """(indirect, register number, auto increment/decrement) or None"""
    m = REG_RE.match(op.strip())
    if not m:
        return None
    return (m.group(1) == '@', int(m.group(3)), bool(m.group(2) or m.group(4)))


def site_key(it):
    return (it.nearest, it.mnem, it.ops[0].upper() if it.ops else '')


def branch_key(it):
    return (it.nearest, it.mnem, it.ops[0].upper(),
            it.ops[1].upper() if len(it.ops) > 1 else '1')


def indirect_sites(items):
    """every branch through a register or a memory word"""
    return [it for it in items
            if it.mnem in MNEM_BRANCH and it.ops and reg_of(it.ops[0])]


# ---------------------------------------------------------------------------
# Analysis
# ---------------------------------------------------------------------------

class Summary:
    def __init__(self, key):
        self.key = key
        self.peak = 0
        self.chain = []         # hops to the peak: (item, kind, level, key)
        self.exits = set()
        self.restarts = 0       # paths that reset the bank to absolute 0
        self.monitor = 0        # paths that jump into the debug Monitor
        self.clob = set()       # (relative level, n): Rn (n < 8) written
        self.halts = 0
        self.cut = []           # (item, reason) paths that were not followed
        self.calls = []         # (item, callee_key, level, kind)
        self.local_peak = (0, None)   # (level, item) from INCRB in own body
        self.done = False


class Analyzer:
    """overrides (scenarios): 'indirect' replaces INDIRECT entries,
    'dispatch_override' replaces dispatch targets, 'force' fixes branches
    (key -> taken), 'stop_at' ends paths at labels, 'exclude_calls' and
    'exclude_edges' (caller, callee) skip calls"""

    def __init__(self, items, labels, equs, overrides=None):
        self.items, self.labels, self.equs = items, labels, equs
        self.ov = overrides or {}
        self.memo = {}
        self.stack = []
        self.recursion = set()
        self.notes = defaultdict(set)    # category -> set of strings
        self.indirect_seen = {}          # site key -> item
        self.dispatch_sites = []         # (caller item, routine, value)
        self.last_callee = None
        self.roots = set(ROOTS) | set(EXTRA_ROOTS)
        # tracked registers: dispatcher registers (constants) and registers
        # that receive a copy of SR ("MOVE SR, Rn"; SR is R14 after the
        # preprocessor), which hold an ('SR', level) token
        self.const_regs = {e['reg'].upper() for e in INDIRECT.values()
                           if e['kind'] == 'dispatch'}
        self.sr_regs = set()
        for it in items:
            if it.mnem == 'MOVE' and len(it.ops) == 2 and \
                    it.ops[0].strip().upper() == 'R14':
                ro = reg_of(it.ops[1])
                if ro and not ro[0] and not ro[2] and ro[1] <= 12:
                    self.sr_regs.add('R%d' % ro[1])
        self.tracked = sorted(self.const_regs | self.sr_regs)
        self.tidx = {r: i for i, r in enumerate(self.tracked)}
        self.none_rv = tuple(None for _ in self.tracked)
        self.entries = self._entries()

    # --- helpers -----------------------------------------------------------
    def code_label(self, name):
        return name in self.labels and self.items[self.labels[name]].mnem \
            not in DIRECTIVES

    def collapse(self, name):
        """follow trampolines: label whose instruction is RBRA/ABRA X, 1"""
        seen = set()
        while name in self.labels and name not in seen:
            seen.add(name)
            it = self.items[self.labels[name]]
            if it.mnem in ('RBRA', 'ABRA') and len(it.ops) == 2 and \
                    it.ops[1] in CONDS_ALWAYS and self.code_label(it.ops[0]):
                name = it.ops[0]
            else:
                break
        return name

    def indirect_entry(self, it):
        k = site_key(it)
        self.indirect_seen[k] = it
        return self.ov.get('indirect', {}).get(k) or INDIRECT.get(k)

    def table_targets(self, ent):
        if ent['kind'] == 'targets':
            return list(ent['targets'])
        if ent['kind'] == 'table':
            w = dw_words(self.items, self.labels, ent['table'])
            return [x for x in (w or []) if self.code_label(x)]
        return []

    def dispatch_map(self, ent):
        if 'map' in ent:
            out = {k: list(v) for k, v in ent['map'].items()}
        else:
            rec = dw_words(self.items, self.labels, ent['record']) or []
            out = {}
            # every EQU whose value indexes a code pointer of the record
            for name, val in self.equs.items():
                v = to_int(val)
                if v is not None and 0 <= v < len(rec) and \
                        self.code_label(rec[v]) and \
                        name.startswith(tuple(ent['prefixes'])):
                    out[name] = [rec[v]]
            for name, extra in ent.get('patch', {}).items():
                out[name] = out.get(name, []) + list(extra)
        for name, tg in self.ov.get('dispatch_override', {}).items():
            if name in out:
                out[name] = list(tg)
        return out

    def is_dispatcher(self, name):
        for k, ent in INDIRECT.items():
            if ent['kind'] == 'dispatch' and k[0] == name:
                return ent
        return None

    def _entries(self):
        """routine entries: call targets (direct and resolved indirect)"""
        ent = set(ROOTS)
        for it in self.items:
            if it.mnem in ('RSUB', 'ASUB') and it.ops:
                t = it.ops[0]
                if reg_of(t) is None and self.code_label(t):
                    ent.add(self.collapse(t))
        for k, e in INDIRECT.items():
            if k[1] in ('ASUB', 'RSUB'):
                if e['kind'] in ('targets', 'table'):
                    ent.update(self.collapse(x) for x in self.table_targets(e))
                if e['kind'] == 'dispatch':
                    for tg in self.dispatch_map(e).values():
                        ent.update(self.collapse(x) for x in tg)
        return ent

    def _saved_reg(self, name):
        """n if the routine starts with MOVE Rn, @--R13 (n < 8)"""
        it = self.items[self.labels[name]]
        if it.mnem == 'MOVE' and len(it.ops) == 2 and \
                it.ops[1].strip().upper() == '@--R13':
            ro = reg_of(it.ops[0])
            if ro and not ro[0] and not ro[2] and ro[1] < 8:
                return ro[1]
        return None

    # --- the per-routine data flow ----------------------------------------
    def summary(self, name, ctx=None):
        key = (name, ctx)
        if key in self.memo:
            s = self.memo[key]
            if not s.done:
                cyc = [k[0] for k in self.stack[self.stack.index(key):]]
                self.recursion.add(' -> '.join(cyc + [name]))
            return s
        s = Summary(key)
        self.memo[key] = s
        self.stack.append(key)
        rr = self._analyze(s, name, ctx)
        # a routine that saves Rn at entry and restores it before every RET
        # preserves Rn of the caller (writes in the caller bank are undone)
        n = self._saved_reg(name)
        if n is not None and rr and all(r == n for r in rr):
            s.clob = {(l, r) for (l, r) in s.clob if not (l == 0 and r == n)}
            self.notes['preserve'].add('%s saves and restores R%d' %
                                       (name, n))
        self.stack.pop()
        s.done = True
        return s

    def _call(self, s, it, lvl, rv, callee, kind):
        """apply callee summary; returns list of exit levels (relative)"""
        callee = self.collapse(callee)
        ctx = None
        disp = self.is_dispatcher(callee)
        if disp:
            v = rv[self.tidx[disp['reg'].upper()]]
            ctx = v if v is not None else '?'
            self.dispatch_sites.append((it, callee, ctx))
        cs = self.summary(callee, ctx)
        s.calls.append((it, cs.key, lvl, kind))
        if not cs.done:            # recursion: assume balanced (reported)
            self.last_callee = None
            return [lvl]
        if lvl + cs.peak > s.peak:
            s.peak = lvl + cs.peak
            s.chain = [(it, kind, lvl, cs.key)] + cs.chain
        s.restarts += cs.restarts
        s.monitor += cs.monitor
        s.clob |= {(lvl + l, r) for (l, r) in cs.clob}
        self.last_callee = cs
        return [lvl + e for e in cs.exits]

    def _analyze(self, s, name, ctx):
        items = self.items
        start = self.labels[name]
        stop = set(self.ov.get('stop_at', ()))
        force = self.ov.get('force', {})
        exclude = set(self.ov.get('exclude_calls', ()))
        exclude_edges = set(self.ov.get('exclude_edges', ()))
        disp = self.is_dispatcher(name)
        rv_init = list(self.none_rv)
        if disp and ctx is not None and ctx != '?':
            rv_init[self.tidx[disp['reg'].upper()]] = ctx
        seen = defaultdict(set)
        work = [(start, 0, tuple(rv_init))]
        ret_restores = []
        NONE = self.none_rv
        banked = [i for i, r in enumerate(self.tracked) if int(r[1:]) < 8]

        def after_call(rv, cs, net):
            """tracked values after a call: R8..R12 are lost (parameters),
            R0..R7 survive if the level is unchanged and the callee never
            writes them in the bank of the caller (relative level 0)"""
            out = list(NONE)
            if cs is None or net != 0:
                return tuple(out)
            for i in banked:
                n = int(self.tracked[i][1:])
                if (0, n) not in cs.clob:
                    out[i] = rv[i]
            return tuple(out)

        def bank_switch(rv):
            rv = list(rv)
            for i in banked:
                rv[i] = None
            return tuple(rv)

        def push(i, lvl, rv):
            if abs(lvl) > LEVEL_CAP:
                s.cut.append((items[min(i, len(items) - 1)], 'level runaway'))
                return
            if (lvl, rv) not in seen[i]:
                seen[i].add((lvl, rv))
                work.append((i, lvl, rv))

        def jump(it, lvl, rv, tgt, tail_exits):
            """jump to label: tail call if it is another routine entry"""
            if tgt in stop:
                s.cut.append((it, 'stop at ' + tgt))
                return
            if tgt in MONITOR_ENTRY and name not in MONITOR_ROOTS:
                s.monitor += 1                  # enters the debug Monitor
                self.notes['monitor'].add('%s %s: enters the Monitor '
                                          '(non-local, root %s)' %
                                          (it.where(), it.text, tgt))
                return
            if tgt != name and self.collapse(tgt) in self.entries and \
                    self.collapse(tgt) != name:
                for e in self._call(s, it, lvl, rv, tgt, 'tail'):
                    tail_exits.add(e)
                return
            push(self.labels[tgt], lvl, rv)

        while work:
            i, lvl, rv = work.pop()
            if i >= len(items):
                s.cut.append((items[-1], 'fell off the end'))
                continue
            it = items[i]
            # fall-through into another routine entry: tail call
            if i != start and it.label:
                ent_here = [l for l in it.label if l in self.entries and
                            self.collapse(l) != name and l != name]
                if any(l in stop for l in it.label):
                    s.cut.append((it, 'stop at ' + it.label[0]))
                    continue
                if ent_here:
                    for e in self._call(s, it, lvl, rv, ent_here[0], 'fall'):
                        s.exits.add(e)
                    continue
            m, ops = it.mnem, it.ops
            if m in DIRECTIVES:
                if m != '.ORG':
                    s.cut.append((it, 'fell into data ' + m))
                continue
            nxt = i + 1
            if m == 'INCRB':
                lvl += 1
                if lvl > s.peak:
                    s.peak = lvl
                    s.chain = [(it, 'incrb', lvl, None)]
                if lvl > s.local_peak[0]:
                    s.local_peak = (lvl, it)
                push(nxt, lvl, bank_switch(rv))
                continue
            if m == 'DECRB':
                push(nxt, lvl - 1, bank_switch(rv))
                continue
            if m == 'HALT':
                s.halts += 1
                continue
            if m in ('RTI', 'INT'):
                s.cut.append((it, 'interrupt instruction ' + m))
                continue
            if m in MNEM_BRANCH:
                tgt = ops[0] if ops else ''
                cond = ops[1].upper() if len(ops) > 1 else '1'
                always = cond in CONDS_ALWAYS
                fkey = (it.nearest, it.mnem, tgt.upper(), cond)
                if fkey in force:
                    always = force[fkey]
                    if not always:
                        push(nxt, lvl, rv)
                        continue
                is_call = m in ('RSUB', 'ASUB')
                if reg_of(tgt) is not None:          # indirect
                    ent = self.indirect_entry(it)
                    if ent is None:
                        s.cut.append((it, 'unresolved indirect site'))
                        if not always:
                            push(nxt, lvl, rv)
                        continue
                    kind = ent['kind']
                    if kind == 'nop':
                        push(nxt, lvl, rv)
                        continue
                    if kind == 'unresolvable':
                        s.cut.append((it, 'unresolvable: ' + ent['note']))
                        if not always:
                            push(nxt, lvl, rv)
                        continue
                    if kind == 'dispatch':
                        dmap = self.dispatch_map(ent)
                        val = s.key[1]
                        if val in dmap:
                            tg = dmap[val]
                        else:
                            # conservative: every target of the dispatcher
                            tg = sorted({x for v in dmap.values() for x in v})
                            self.notes['dispatch'].add(
                                '%s %s: %s is %s on entry of %s, so all %d '
                                'targets are assumed' %
                                (it.where(), it.text, ent['reg'],
                                 'unknown' if val in (None, '?') else
                                 'the unknown constant ' + val, name,
                                 len(tg)))
                    else:
                        tg = self.table_targets(ent)
                    if is_call:
                        for t in tg:
                            for e in self._call(s, it, lvl, rv, t, 'icall'):
                                push(nxt, e, after_call(rv, self.last_callee,
                                                        e - lvl))
                    else:
                        tail = set()
                        for t in tg:
                            jump(it, lvl, rv, t, tail)
                        s.exits.update(tail)
                    if not always:
                        push(nxt, lvl, rv)
                    continue
                # direct
                if not self.code_label(tgt):
                    s.cut.append((it, 'branch to non-code ' + tgt))
                    continue
                if is_call:
                    if self.collapse(tgt) in exclude or \
                            (name, self.collapse(tgt)) in exclude_edges:
                        push(nxt, lvl, rv)
                        continue
                    for e in self._call(s, it, lvl, rv, tgt, 'call'):
                        push(nxt, e, after_call(rv, self.last_callee,
                                                e - lvl))
                    if not always:
                        push(nxt, lvl, rv)
                else:
                    tail = set()
                    jump(it, lvl, rv, tgt, tail)
                    s.exits.update(tail)
                    if not always:
                        push(nxt, lvl, rv)
                continue
            # normal instructions and EXC
            dst = ops[-1].strip().upper() if len(ops) >= 2 else ''
            src = ops[0].strip().upper() if ops else ''
            if m == 'MOVE' and src == '@R13++' and dst == 'R15':
                s.exits.add(lvl)                     # RET
                # save/restore pattern: "MOVE @R13++, Rn" right before RET
                prev = items[i - 1] if i > 0 else None
                rn = None
                if not it.label and prev is not None and \
                        prev.mnem == 'MOVE' and len(prev.ops) == 2 and \
                        prev.ops[0].strip().upper() == '@R13++':
                    ro = reg_of(prev.ops[1])
                    if ro and not ro[0] and not ro[2]:
                        rn = ro[1]
                ret_restores.append(rn)
                continue
            writes_pc = (m != 'CMP' and dst == 'R15') or \
                (m == 'EXC' and 'R15' in (src, dst))
            if writes_pc:
                s.cut.append((it, 'computed jump (write to R15)'))
                continue
            writes_sr = (m != 'CMP' and dst == 'R14') or \
                (m == 'EXC' and 'R14' in (src, dst))
            if writes_sr:
                spec = SR_SPECIAL.get((it.nearest, m, src))
                v = to_int(src) if not src.startswith('@') and \
                    reg_of(src) is None else None
                srtok = None
                if m == 'MOVE' and src in self.tidx:
                    srtok = rv[self.tidx[src]]
                if spec == 'same':
                    self.notes['sr'].add('%s %s: treated as "same level" '
                                         '(SR_SPECIAL)' % (it.where(), it.text))
                elif isinstance(srtok, tuple) and srtok[0] == 'SR':
                    # restore of an SR copy taken earlier on this path: the
                    # bank bits become those of the copy
                    self.notes['sr'].add(
                        '%s %s: restores the SR saved by "MOVE SR, %s" '
                        '(level %+d -> %+d relative to %s)' %
                        (it.where(), it.text, src, lvl, srtok[1], name))
                    lvl = srtok[1]
                    if lvl > s.peak:
                        s.peak = lvl
                        s.chain = [(it, 'incrb', lvl, None)]
                    if lvl > s.local_peak[0]:
                        s.local_peak = (lvl, it)
                elif m == 'AND' and v is not None and (v & 0xFF00) == 0xFF00:
                    pass                              # flags only
                elif m in ('OR', 'XOR') and v is not None and v < 0x100:
                    pass                              # flags only
                elif m == 'AND' and v is not None and (v & 0xFF00) == 0 \
                        and name in self.roots:
                    lvl = 0                           # a root starts at 0
                elif m == 'AND' and v is not None and (v & 0xFF00) == 0:
                    s.restarts += 1                   # absolute bank 0
                    self.notes['sr'].add('%s %s: resets to bank 0 '
                                         '(path ends, separate root)' %
                                         (it.where(), it.text))
                    continue
                else:
                    s.cut.append((it, 'unknown SR write'))
                    continue
            # banked registers written in this bank (for after_call)
            if m != 'CMP':
                for op in ops:
                    ro = reg_of(op)
                    if ro and ro[1] < 8 and ro[2]:
                        s.clob.add((lvl, ro[1]))     # @Rn++ / @--Rn
                rd = reg_of(dst) if dst else None
                if rd and not rd[0] and rd[1] < 8:
                    s.clob.add((lvl, rd[1]))
                if m == 'EXC':
                    rs = reg_of(src)
                    if rs and not rs[0] and rs[1] < 8:
                        s.clob.add((lvl, rs[1]))
            # tracking of dispatcher constants and SR copies
            nrv = list(rv)
            for ti, treg in enumerate(self.tracked):
                tn = int(treg[1:])
                for op in ops:
                    ro = reg_of(op)
                    if ro and ro[1] == tn and ro[2]:
                        nrv[ti] = None               # @Rn++ / @--Rn
                if dst == treg and m != 'CMP':
                    if m == 'MOVE' and src == 'R14':
                        nrv[ti] = ('SR', lvl)        # copy of SR
                    elif m == 'MOVE' and treg in self.const_regs and \
                            reg_of(src) is None and not src.startswith('@'):
                        nrv[ti] = ops[0].strip()
                    else:
                        nrv[ti] = None
                if m == 'EXC' and treg in (src, dst):
                    nrv[ti] = None
            push(nxt, lvl, tuple(nrv))
        return ret_restores

    # --- reporting helpers ---------------------------------------------------
    def chain_text(self, base, root_key, chain):
        """one line per hop: absolute level at the call site (= entry level
        of the callee), (+n) = levels the caller added before the call"""
        out = ['  %-3d       %s (entry)' % (base, root_key[0])]
        run = base
        for it, kind, lvl, ck in chain:
            at = run + lvl
            if kind == 'incrb':
                out.append('  %-3d (+%d)  INCRB at %s  = deepest bank' %
                           (at, lvl, it.where()))
            else:
                out.append('  %-3d (%+d)  %-5s %s at %s -> %s' %
                           (at, lvl, kind, it.text.split(';')[0].strip(),
                            it.where(), key_name(ck)))
            run = at
        return out


def key_name(key):
    return key[0] + ('[%s]' % key[1] if key[1] else '')


def walk_to(an, root, target):
    """intra-procedural walk from root (calls are applied as summaries,
    jumps are followed) that records the levels at which label 'target' is
    reached"""
    items, labels = an.items, an.labels
    res = set()
    seen = set()
    work = [(labels[root], 0)]
    while work:
        i, lvl = work.pop()
        if (i, lvl) in seen or i >= len(items):
            continue
        seen.add((i, lvl))
        it = items[i]
        if it.label and target in it.label:
            res.add(lvl)
            continue
        m, ops = it.mnem, it.ops
        if m in DIRECTIVES or m == 'HALT':
            continue
        if m == 'INCRB':
            work.append((i + 1, lvl + 1))
            continue
        if m == 'DECRB':
            work.append((i + 1, lvl - 1))
            continue
        if m in MNEM_BRANCH:
            tgt = ops[0]
            cond = ops[1].upper() if len(ops) > 1 else '1'
            if reg_of(tgt) is not None:
                if cond not in CONDS_ALWAYS or m in ('RSUB', 'ASUB'):
                    work.append((i + 1, lvl))
                continue
            if m in ('RSUB', 'ASUB'):
                cs = an.summary(an.collapse(tgt))
                for e in cs.exits:
                    work.append((i + 1, lvl + e))
                if cond not in CONDS_ALWAYS:
                    work.append((i + 1, lvl))
            else:
                if an.code_label(tgt):
                    work.append((labels[tgt], lvl))
                if cond not in CONDS_ALWAYS:
                    work.append((i + 1, lvl))
            continue
        dst = ops[-1].strip().upper() if len(ops) >= 2 else ''
        if m == 'MOVE' and ops and ops[0].strip().upper() == '@R13++' and \
                dst == 'R15':
            continue
        if dst == 'R14' and m == 'AND' and to_int(ops[0]) is not None and \
                (to_int(ops[0]) & 0xFF00) == 0:
            lvl = 0
        work.append((i + 1, lvl))
    return res


def level_at_call(an, caller, callee):
    """bank level (relative to caller entry) at the call of callee"""
    s = an.memo.get((caller, None)) or an.summary(caller)
    lv = [lvl for it, ck, lvl, kind in s.calls if ck[0] == callee]
    return max(lv) if lv else 0


def is_library(an, name):
    """routine of the QNICE Monitor libraries (not Shell code)"""
    f = an.items[an.labels[name]].file.replace('\\', '/')
    return '/QNICE/monitor/' in f or '/rom/monitor/' in f


def enumerate_chains(an, root, base, top):
    """top-N deepest chains; chains are distinct in their Shell part (the
    routines outside the Monitor libraries), the library tail shown is the
    deepest one; a chain ends at the deepest INCRB of its last routine"""
    best = {}             # group key -> (level, names, chain)

    def gkey(names):
        return tuple(n for n in names if not is_library(an, n))

    def kth():
        if len(best) < top:
            return -10 ** 9
        return sorted((v[0] for v in best.values()), reverse=True)[top - 1]

    def rec(key, lvl0, names, chain, depth):
        s = an.memo.get(key)
        if s is None or depth > 200 or lvl0 + s.peak < kth():
            return
        lp, lit = s.local_peak
        if lit is not None:
            k = gkey(names)
            if k not in best or best[k][0] < lvl0 + lp:
                best[k] = (lvl0 + lp, names, chain + [
                    (lit, 'incrb', lvl0 + lp - base, None)])
        calls = sorted(s.calls, key=lambda c: -(c[2] + an.memo[c[1]].peak))
        seen = set()
        for it, ck, lvl, kind in calls:
            if (it.idx, ck) in seen or ck[0] in names:
                continue
            seen.add((it.idx, ck))
            if lvl0 + lvl + an.memo[ck].peak < kth() and \
                    gkey(names + [ck[0]]) in best:
                continue
            rec(ck, lvl0 + lvl, names + [ck[0]],
                chain + [(it, kind, lvl0 + lvl - base, ck)], depth + 1)

    rec(root, base, [root[0]], [], 0)
    out = sorted(best.values(), key=lambda r: -r[0])
    return out[:top]


def deepest_via(an, root, targets):
    """deepest level (relative to root) reached inside one of the routines
    in 'targets' and the chain to it; None if no target is reachable"""
    memo = {}

    def dv(key, depth):
        if key in memo:
            return memo[key]
        s = an.memo.get(key)
        res = None
        if s is not None and key[0] in targets:
            res = (s.peak, [])
        elif s is not None and depth < 300:
            memo[key] = None
            for it, ck, lvl, kind in s.calls:
                r = dv(ck, depth + 1)
                if r is not None and (res is None or lvl + r[0] > res[0]):
                    res = (lvl + r[0], [(it, kind, lvl, ck)] + r[1])
        memo[key] = res
        return res
    return dv(root, 0)


# ---------------------------------------------------------------------------
# Whole program, scenarios and checks
# ---------------------------------------------------------------------------

class Result:
    """the analysis of one tree"""

    def __init__(self, items, labels, equs, problems):
        self.items, self.labels, self.equs = items, labels, equs
        self.problems = problems
        self.an = Analyzer(items, labels, equs)
        an = self.an
        an.summary(ROOTS[0])
        self.main_level = max(walk_to(an, ROOTS[0], MAIN_LOOP) or {0}) \
            if MAIN_LOOP in labels else 0
        self.mon_base = 0
        if MONITOR_CALLER in labels and 'QMON$SOFTMON' in labels:
            self.mon_base = self.main_level + \
                level_at_call(an, MAIN_LOOP, MONITOR_CALLER) + \
                max(walk_to(an, MONITOR_CALLER, 'QMON$SOFTMON') or {0})
        base = {'QMON$SOFTMON': self.mon_base}
        for r in EXTRA_ROOTS:
            if r in labels:
                an.summary(r)
        self.roots = [(r, base.get(r, 0)) for r in ROOTS + EXTRA_ROOTS
                      if (r, None) in an.memo]
        self.top_root, self.top_base = max(
            self.roots, key=lambda rb: rb[1] + an.memo[(rb[0], None)].peak)
        self.top = an.memo[(self.top_root, None)]
        self.static_max = self.top_base + self.top.peak
        self.rows = []

    def scenarios(self):
        """rows: (name, static, realistic, clean, analyzer, summary, base,
        clean analyzer, clean summary) for the realistic chains"""
        items, labels, equs, an = self.items, self.labels, self.equs, self.an
        B = self.main_level

        def run(entry, ov):
            a = Analyzer(items, labels, equs, ov)
            return a, a.summary(entry)

        def scen(nm, entry, base, ov, ov_real=None):
            _, s_s = run(entry, ov)
            ov_real = ov if ov_real is None else ov_real
            a_r, s_r = run(entry, ov_real)
            ov_clean = dict(ov_real)
            ov_clean['force'] = dict(ov_real.get('force', {}))
            ov_clean['force'].update(CLEAN_FORCE)
            a_c, s_c = run(entry, ov_clean)
            self.rows.append((nm, base + s_s.peak, base + s_r.peak,
                              base + s_c.peak, a_r, s_r, base, a_c, s_c))

        scen('boot until %s' % MAIN_LOOP, ROOTS[0], 0, {'stop_at': [MAIN_LOOP]})
        scen('main loop, no key', MAIN_LOOP, B, {
            'exclude_calls': ['SC_KEY'],
            'force': {BR_NO_HELP_KEY: True, BR_DEBUG_KEYS: False}})
        scen('visible menu (Help key)', 'HELP_MENU',
             B + level_at_call(an, MAIN_LOOP, 'HELP_MENU'), {
                 'force': {BR_DIRECT_SESSION: False},
                 'dispatch_override': {GETKEY_INDEX: [GETKEY_MENU]}})
        scen('debug Monitor', 'QMON$SOFTMON', self.mon_base, {})
        lv_sc = B + level_at_call(an, MAIN_LOOP, SC_ENTRY)
        actions = []
        for lab in dw_words(items, labels, SC_TABLE) or []:
            if lab not in actions:
                actions.append(lab)
        for lab in actions:
            routine = SC_NEXT_ROUTINE if 'NEXT' in lab.upper() \
                else SC_PRESS_ROUTINE
            ov = {'indirect': {
                      SC_TABLE_SITE: {'kind': 'targets', 'targets': [lab]},
                      SC_SESSION_SITE: {'kind': 'targets',
                                        'targets': [routine]}},
                  'dispatch_override': {GETKEY_INDEX: [GETKEY_SESSION]},
                  'force': {BR_DIRECT_SESSION: True, BR_NO_HELP_KEY: False}}
            repeats = bool(walk_to(an, lab, REPEAT_LABEL))
            ov_real = dict(ov)
            if not repeats:
                ov_real['exclude_edges'] = [REPEAT_EDGE]
            scen('shortcut %s%s' % (lab, ' (repeats)' if repeats else ''),
                 SC_ENTRY, lv_sc, ov, ov_real)
        return self.rows


class Failure:
    def __init__(self, short, action):
        self.short, self.action = short, action


def check(res, banks):
    """all pass/fail rules; returns a list of Failure"""
    an, items, labels = res.an, res.items, res.labels
    fails = []

    def fail(short, action):
        fails.append(Failure(short, action))

    for p in res.problems:
        fail('line not understood by the parser: %s' % p,
             'fix the line or extend parse() in this file')

    # the resolution tables have to match the code
    sites = indirect_sites(items)
    keys = {site_key(it) for it in sites}
    for it in sites:
        if site_key(it) not in INDIRECT:
            fail('new indirect call site %s "%s" (nearest label %s)' %
                 (it.where(), it.text, it.nearest),
                 'add its possible targets to INDIRECT in this file')
    for k, ent in INDIRECT.items():
        if k not in keys:
            fail('INDIRECT entry %s matches no indirect site any more' %
                 (k,), 'remove the entry or update its key (nearest label, '
                       'mnemonic, operand) in this file')
            continue
        names = []
        if ent['kind'] == 'targets':
            names = ent['targets']
        elif ent['kind'] == 'table':
            if not an.table_targets(ent):
                fail('INDIRECT entry %s: table %s not found or empty' %
                     (k, ent['table']), 'update the entry in this file')
        elif ent['kind'] == 'dispatch':
            if 'record' in ent and ent['record'] not in labels:
                fail('INDIRECT entry %s: record %s not found' %
                     (k, ent['record']), 'update the entry in this file')
            names = [x for v in list(ent.get('map', {}).values()) +
                     list(ent.get('patch', {}).values()) for x in v]
            if not an.dispatch_map(ent):
                fail('INDIRECT entry %s resolves to no target' % (k,),
                     'update the entry in this file')
        for n in names:
            if not an.code_label(n):
                fail('INDIRECT entry %s names target %s, which is not a '
                     'code label any more' % (k, n),
                     'update the entry in this file')
    instr = {(it.nearest, it.mnem, it.ops[0].strip().upper())
             for it in items if it.ops}
    for k in SR_SPECIAL:
        if k not in instr:
            fail('SR_SPECIAL entry %s matches no instruction any more' % (k,),
                 'remove or update the entry in this file')
    for n in EXPECTED_EXITS:
        if n not in labels:
            fail('EXPECTED_EXITS names %s, which does not exist any more' % n,
                 'remove the entry in this file')
    needed = [MAIN_LOOP, MONITOR_CALLER, SC_ENTRY, SC_TABLE, REPEAT_LABEL,
              GETKEY_MENU, GETKEY_SESSION, SC_PRESS_ROUTINE, SC_NEXT_ROUTINE,
              'HELP_MENU'] + list(REPEAT_EDGE) + ROOTS + EXTRA_ROOTS
    for n in needed:
        if n not in labels:
            fail('label %s used by the scenarios does not exist any more' % n,
                 'update the scenario constants in this file')
    bkeys = {branch_key(it) for it in items if it.mnem in MNEM_BRANCH
             and it.ops}
    for k in [BR_NO_HELP_KEY, BR_DIRECT_SESSION, BR_DEBUG_KEYS] + \
            list(CLEAN_FORCE):
        if k not in bkeys:
            fail('scenario branch %s matches no instruction any more' % (k,),
                 'update the scenario constants in this file')
    for k in (SC_TABLE_SITE, SC_SESSION_SITE):
        if k not in INDIRECT:
            fail('scenario site %s is not in INDIRECT' % (k,),
                 'update the scenario constants in this file')

    # paths that were not followed
    cuts = defaultdict(set)
    for s in an.memo.values():
        for it, why in s.cut:
            if why.startswith('unresolvable:') or \
                    why == 'unresolved indirect site':
                continue                    # known, or reported above
            cuts[why].add('%s "%s"' % (it.where(), it.text))
    advice = {
        'unknown SR write': 'teach the SR handling of this file the new '
                            'construct (see SR_SPECIAL)',
        'computed jump (write to R15)': 'resolve the jump: add a rule for '
                                        'it to this file',
        'interrupt instruction RTI': 'the analysis does not model interrupts:'
                                     ' extend this file before using them',
        'interrupt instruction INT': 'the analysis does not model interrupts:'
                                     ' extend this file before using them',
        'level runaway': 'a loop executes INCRB without DECRB: fix it',
        'fell off the end': 'code runs past the last instruction: fix it',
    }
    for why, where in sorted(cuts.items()):
        act = advice.get(why)
        if act is None and why.startswith('fell into data'):
            act = 'execution can run into data: check the code before it'
        if act is None and why.startswith('branch to non-code'):
            act = 'the branch target is not code: check the label'
        fail('analysis path cut (%s) at %s' % (why, ', '.join(sorted(where))),
             act or 'extend the analysis in this file')
    for n in sorted(an.notes.get('dispatch', ())):
        fail('dispatch target not known: %s' % n,
             'load the index with "MOVE <constant>, <register>" before the '
             'call, or extend the INDIRECT entry in this file')

    # every routine returns at the level of its entry
    for key, s in sorted(an.memo.items(), key=lambda kv: str(kv[0])):
        ex = sorted(s.exits)
        if not ex or ex == [0] or EXPECTED_EXITS.get(key[0]) == ex:
            continue
        fail('routine %s returns at level %s relative to its entry' %
             (key_name(key), ', '.join('%+d' % e for e in ex)),
             'balance INCRB/DECRB (or enter/leave) on every path of it; if '
             'intended, add it to EXPECTED_EXITS in this file with a reason')
    for r in sorted(an.recursion):
        fail('recursion: %s' % r,
             'remove the recursion: its bank depth would be unbounded')

    # the limit
    if res.static_max >= banks:
        fail('deepest register bank level %d (static) needs %d banks, only '
             '%d available: bank %d aliases bank %d' %
             (res.static_max, res.static_max + 1, banks, res.static_max,
              res.static_max % banks),
             'reduce the nesting on the deepest chain (run with --report) or '
             'raise SHADOW_REGFILE_SIZE in %s' % GLOBALS_VHD)
    elif banks - 1 - res.static_max < MIN_MARGIN:
        fail('margin %d of the deepest register bank level %d (static) is '
             'below MIN_MARGIN = %d (%d banks)' %
             (banks - 1 - res.static_max, res.static_max, MIN_MARGIN, banks),
             'reduce the nesting on the deepest chain (run with --report) or '
             'raise SHADOW_REGFILE_SIZE in %s' % GLOBALS_VHD)
    return fails


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def print_table(res, banks):
    top = banks - 1
    print('scenario (bank levels, allowed 0..%d)       static realistic '
          'clean  margin' % top)
    for nm, lv, lr, lc, *_ in res.rows:
        print('  %-42s %4d %9d %5d %7d%s' % (
            nm, lv, lr, lc, top - lr,
            '' if lr <= top else '  OVERFLOW by %d' % (lr - top)))
    print('  (realistic: without the key repeat for actions that never '
          'repeat;')
    print('   clean: no disk image write-back pending; margin = %d - '
          'realistic)' % top)


def print_static(res, banks):
    names = [res.top_root] + [key_name(c[3]) for c in res.top.chain
                              if c[1] != 'incrb']
    head = 'static maximum: %d (allowed 0..%d), deepest chain: ' % \
        (res.static_max, banks - 1)
    for line in textwrap.wrap(head + ' > '.join(names), 78,
                              subsequent_indent='    ',
                              break_on_hyphens=False):
        print(line)


def print_report(res, banks, top_n, via):
    an = res.an
    top = banks - 1
    print()
    print('=' * 78)
    print('static maximum over everything reachable from the reset vector')
    print('=' * 78)
    print('  level %d (allowed 0..%d, %d banks), margin %d' %
          (res.static_max, top, banks, top - res.static_max))
    print('  roots: ' + ', '.join('%s (base %d) -> %d' %
                                  (r, b, b + an.memo[(r, None)].peak)
                                  for r, b in res.roots))
    print('  bank level when %s runs: %d; debug Monitor runs at level %d' %
          (MAIN_LOOP, res.main_level, res.mon_base))
    print('  deepest chain (level = absolute bank level at the call, (+n) = '
          'levels the caller added before it):')
    for line in an.chain_text(res.top_base, res.top.key, res.top.chain):
        print(line)

    print()
    print('=' * 78)
    print('top %d deepest chains from the reset vector' % top_n)
    print('=' * 78)
    print('(distinct in the Shell part; the Monitor library tail is in '
          '[brackets])')
    for n, (lv, names, ch) in enumerate(
            enumerate_chains(an, (ROOTS[0], None), 0, top_n), 1):
        tail = [c for c in ch if c[1] != 'incrb']
        shell = [c for c in tail if not is_library(an, c[3][0])]
        lib = [c for c in tail if is_library(an, c[3][0])]
        print('#%d level %d: %s [%s]' % (
            n, lv, ' > '.join(key_name(c[3]) for c in shell),
            ' > '.join(c[3][0] for c in lib)))

    print()
    print('=' * 78)
    print('scenario chains')
    print('=' * 78)
    for nm, lv, lr, lc, a_r, s_r, base, a_c, s_c in res.rows:
        print()
        print('  -- %s: deepest chain (realistic, entry level %d)' %
              (nm, base))
        for line in a_r.chain_text(base, s_r.key, s_r.chain):
            print('  ' + line)
        if lc != lr:
            print('  -- %s: deepest chain (clean)' % nm)
            for line in a_c.chain_text(base, s_c.key, s_c.chain):
                print('  ' + line)

    print()
    print('=' * 78)
    print('sanity sections')
    print('=' * 78)
    print('routines that do not return at their entry level on every path '
          '(exits relative to entry):')
    for key, s in sorted(an.memo.items(), key=lambda kv: str(kv[0])):
        ex = sorted(s.exits)
        if ex != [0]:
            extra = []
            if s.restarts:
                extra.append('restart-to-bank-0 paths')
            if s.monitor:
                extra.append('enters the Monitor')
            if s.halts:
                extra.append('HALT')
            if s.cut:
                extra.append('cut: ' + '; '.join(sorted(
                    {'%s %s' % (it.where(), why) for it, why in s.cut})))
            print('  %-28s exits=%-14s %s' % (key_name(key), ex,
                                               ' | '.join(extra)))
    print()
    print('recursion: %s' % (', '.join(sorted(an.recursion)) or 'none'))
    print()
    print('indirect sites:')
    for it in indirect_sites(res.items):
        ent = INDIRECT.get(site_key(it))
        if ent is None:
            desc = 'NOT IN INDIRECT'
        elif ent['kind'] == 'dispatch':
            desc = 'dispatch on %s: %s' % (ent['reg'], ent['note'])
        elif ent['kind'] in ('targets', 'table'):
            desc = '%s -> %s' % (ent['kind'],
                                 ', '.join(an.table_targets(ent)))
        else:
            desc = '%s (%s)' % (ent['kind'], ent['note'])
        reach = '' if site_key(it) in an.indirect_seen else '  [not reached]'
        print('  %-24s %-12s %s%s' % (it.where(), it.mnem + ' ' + it.ops[0],
                                      desc, reach))
    print()
    print('dispatch sites (call of a dispatcher, tracked register value):')
    agg = defaultdict(set)
    for it, routine, val in an.dispatch_sites:
        agg[(it.where(), it.text.split(';')[0].strip())].add(val)
    for (w, t), vals in sorted(agg.items()):
        print('  %-24s %-28s = %s' % (w, t, ', '.join(sorted(vals))))
    print()
    print('paths that were not followed:')
    cuts = sorted({'%-24s %s' % (it.where(), why)
                   for s in an.memo.values() for it, why in s.cut})
    for c in cuts or ['none']:
        print('  ' + c)
    for cat in ('dispatch', 'preserve', 'sr', 'monitor'):
        if an.notes.get(cat):
            print()
            print('notes [%s]:' % cat)
            for n in sorted(an.notes[cat]):
                print('  ' + n)
    if via:
        print_via(res, via)


def print_via(res, via):
    tset = set(via)
    print()
    print('deepest level reached inside %s (realistic):' %
          ' / '.join(sorted(tset)))
    for nm, lv, lr, lc, a_r, s_r, base, a_c, s_c in res.rows:
        r = deepest_via(a_r, s_r.key, tset)
        if r is None:
            print('  %-42s  -' % nm)
            continue
        last = r[1][-1][3][0] if r[1] else s_r.key[0]
        caller = r[1][-2][3][0] if len(r[1]) > 1 else s_r.key[0]
        print('  %-42s %3d   (in %s, called from %s)' %
              (nm, base + r[0], last, caller))


def print_explain(res, names):
    an = res.an
    for nm in names:
        keys = [k for k in an.memo if k[0] == nm]
        if not keys:
            print('\n--explain %s: not reached' % nm)
        for k in keys:
            s = an.memo[k]
            print('\n--explain %s: peak +%d, exits %s, own INCRB peak +%d' %
                  (key_name(k), s.peak, sorted(s.exits), s.local_peak[0]))
            rows = {}
            for it, ck, lvl, kind in s.calls:
                r = (it.where(), it.text.split(';')[0].strip(), key_name(ck))
                rows[r] = max(rows.get(r, (-99, 0)),
                              (lvl, lvl + an.memo[ck].peak))
            for (w, t, c), (lvl, pk) in sorted(rows.items(),
                                               key=lambda kv: -kv[1][1]):
                print('  %-24s at +%-2d -> peak +%-2d  %s  (%s)' %
                      (w, lvl, pk, c, t))


def print_all_routines(res):
    print()
    print('all routines: name, peak, exits')
    for key, s in sorted(res.an.memo.items(), key=lambda kv: str(kv[0])):
        print('  %-30s %3d %s' % (key_name(key), s.peak, sorted(s.exits)))


# ---------------------------------------------------------------------------
# Self-test: deliberate defects in a copy of the preprocessed source
# ---------------------------------------------------------------------------

def find_label_line(lines, label):
    for i, line in enumerate(lines):
        if re.match(re.escape(label) + r'!?(\s|$)', line):
            return i
    raise TestError('self-test: label %s not found' % label)


def find_after(lines, start, pattern):
    rx = re.compile(pattern)
    for i in range(start, len(lines)):
        if rx.match(strip_comment(lines[i]).rstrip()):
            return i
    raise TestError('self-test: no line matching %s after line %d' %
                    (pattern, start))


def mutate_around_select_file(pp, before, after):
    """insert lines before/after the call of SELECT_FILE in HANDLE_MOUNTING;
    a label on the call line moves to the first inserted line"""
    lines = pp.split('\n')
    i = find_after(lines, find_label_line(lines, 'HANDLE_MOUNTING'),
                   r'^\S*\s+RSUB\s+SELECT_FILE\s*,\s*1$')
    m = re.match(r'^(\S*)(\s+)(.*)$', lines[i])
    label, body = m.group(1), m.group(3)
    new = []
    for n, ins in enumerate(before):
        new.append((label if n == 0 else '') + '                ' + ins)
    new.append(('' if before else label) + '                ' + body)
    new += ['                ' + ins for ins in after]
    return '\n'.join(lines[:i] + new + lines[i + 1:])


def mutate_remove_decrb(pp, routine):
    """remove the first DECRB without a label after the entry of routine"""
    lines = pp.split('\n')
    i = find_after(lines, find_label_line(lines, routine), r'^\s+DECRB$')
    lines[i] = ''
    return '\n'.join(lines)


def selftest(pp, banks):
    def analyze(text):
        items, labels, equs, problems = parse(text)
        res = Result(items, labels, equs, problems)
        return res, check(res, banks)

    base, base_fails = analyze(pp)
    results = []

    # (a) a limit below the static maximum has to fail with the overflow
    forced = 32 if base.static_max >= 32 else base.static_max
    fa = check(base, forced)
    ok = any('only %d available' % forced in f.short for f in fa)
    results.append((ok, '(a) limit forced to %d banks: overflow %s' %
                    (forced, 'reported' if ok else 'NOT reported')))

    # (b) an extra INCRB/DECRB frame around a call on the deepest chain
    rb, _ = analyze(mutate_around_select_file(pp, ['INCRB'], ['DECRB']))
    ok = rb.static_max == base.static_max + 1
    results.append((ok, '(b) INCRB/DECRB around the SELECT_FILE call in '
                        'HANDLE_MOUNTING: static maximum %d -> %d' %
                    (base.static_max, rb.static_max)))

    # (c) a routine that loses its DECRB returns one level too high
    routine = 'SC$INIT'
    _, fc = analyze(mutate_remove_decrb(pp, routine))
    ok = any(f.short.startswith('routine %s returns at level +1' % routine)
             for f in fc)
    results.append((ok, '(c) DECRB removed from %s: unbalanced return %s' %
                    (routine, 'reported' if ok else 'NOT reported')))

    # (d) a new indirect call on a reachable path
    rd, fd = analyze(mutate_around_select_file(pp, ['ASUB    R5, 1'], []))
    ok = any(f.short.startswith('new indirect call site') and 'R5' in f.short
             for f in fd) and \
        any(k[2] == 'R5' for k in rd.an.indirect_seen)
    results.append((ok, '(d) ASUB R5, 1 before the SELECT_FILE call: new '
                        'indirect site %s' %
                    ('reported' if ok else 'NOT reported')))

    for ok, text in results:
        print('%s %s' % ('PASS' if ok else 'FAIL', text))
    passed = sum(1 for ok, _ in results if ok)
    if passed == len(results):
        print('BANKDEPTH SELFTEST OK: %d of %d defects detected' %
              (passed, len(results)))
        return 0
    print('BANKDEPTH SELFTEST FAILED: %d of %d defects detected' %
          (passed, len(results)))
    return 1


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def read_banks(root):
    path = os.path.join(root, GLOBALS_VHD)
    try:
        text = open(path, errors='replace').read()
    except OSError as e:
        raise TestError('cannot read %s: %s (use --limit N)' % (path, e))
    text = re.sub(r'--[^\n]*', '', text)
    m = re.search(r'constant\s+SHADOW_REGFILE_SIZE\s*:\s*natural\s*:=\s*'
                  r'(\d+)\s*;', text, re.I)
    if not m:
        raise TestError('cannot find "constant SHADOW_REGFILE_SIZE : natural '
                        ':= <number>;" in %s (use --limit N)' % path)
    return int(m.group(1))


def main():
    ap = argparse.ArgumentParser(
        description='Worst-case QNICE register bank nesting depth of the '
                    'firmware (see the header of this file).')
    ap.add_argument('tree', nargs='?', default=REPO,
                    help='root of the source tree (default: the repository '
                         'that contains this file)')
    ap.add_argument('--limit', type=int, metavar='N',
                    help='number of register banks (default: '
                         'SHADOW_REGFILE_SIZE of the tree)')
    ap.add_argument('--report', action='store_true',
                    help='print chains hop by hop, top chains and the '
                         'sanity sections')
    ap.add_argument('--top', type=int, default=10, metavar='N',
                    help='number of chains in the report (default 10)')
    ap.add_argument('--explain', action='append', default=[],
                    metavar='ROUTINE',
                    help='list every call site of ROUTINE with the level at '
                         'the call and the peak reached through the callee')
    ap.add_argument('--via', action='append', default=[], metavar='ROUTINE',
                    help='per scenario: deepest level reached inside the '
                         'given routines (may be repeated)')
    ap.add_argument('--all-routines', action='store_true',
                    help='print the summary of every analyzed routine')
    ap.add_argument('--selftest', action='store_true',
                    help='check that deliberate defects are detected')
    a = ap.parse_args()
    root = os.path.abspath(a.tree)

    try:
        if a.limit is not None:
            banks, source = a.limit, '--limit'
        else:
            banks, source = read_banks(root), GLOBALS_VHD
        if banks < 1:
            raise TestError('the number of banks has to be positive')
        pp, stubs = preprocess(root)
        print('bankdepth_test: %s' % root)
        print('register banks: %d (%s)%s' % (
            banks, source, '; empty stand-ins for %s' % ', '.join(stubs)
            if stubs else ''))
        if a.selftest:
            return selftest(pp, banks)
        items, labels, equs, problems = parse(pp)
        res = Result(items, labels, equs, problems)
        fails = check(res, banks)
        res.scenarios()
    except TestError as e:
        print('BANKDEPTH TEST FAILED: %s' % e)
        return 1

    print()
    print_table(res, banks)
    print()
    print_static(res, banks)
    if a.report:
        print_report(res, banks, a.top, a.via)
    elif a.via:
        print_via(res, a.via)
    if a.explain:
        print_explain(res, a.explain)
    if a.all_routines:
        print_all_routines(res)

    margin = banks - 1 - res.static_max
    print()
    for f in fails:
        print('FAIL: %s' % f.short)
        print('      -> %s' % f.action)
    if not fails:
        print('BANKDEPTH TEST OK: deepest register bank level %d (static), '
              '%d banks, margin %d' % (res.static_max, banks, margin))
        return 0
    if len(fails) == 1:
        print('BANKDEPTH TEST FAILED: %s' % fails[0].short)
    else:
        print('BANKDEPTH TEST FAILED: %d problems, the first: %s' %
              (len(fails), fails[0].short))
    return 1


if __name__ == '__main__':
    sys.exit(main())
