#!/usr/bin/env python3
"""Headless emulator test of the C64 core's custom SUBMENU_SUMMARY callback
(CORE/m2m-rom/m2m-rom.asm): the main-menu lines "Model: %s", "Kernal: %s" and
"Volume: %s" (issue #247: the Stereo Mix tag while a stereo SID is selected).

Unlike jiffy_test.py, nothing is mirrored by hand: this script copies the real
code out of the sources into a generated testbed (summary_test_gen.asm):
SUBMENU_SUMMARY with its helpers, its data (summary tags, scratch buffers),
M2M$RPL_S from M2M/rom/tools.asm, and assembles it together with the real
../menu.asm (OPTM_SUMM_SCAN, OPTM_NL, the init-record offsets). The fixtures
come from the golden model of menu_test.py (V6_MENU) and from mega65.vhd (the
C_MENU_* constants, translated like make_rom.sh does), so the testbed sees the
same menu as the Shell: the masked groups array sits in the M2M$RAMROM window
at 0x7000, the selected-state array and the OPTM_ITEMS string (with "\\n" as
two characters, like the VHDL string) hang off a stub init record at HEAP.

Every case sets a menu state (and the JiffyDOS load flags), calls
SUBMENU_SUMMARY for one opener line and prints either DEFAULT (R8 = 0:
standard semantics) or the custom line. The expected output is computed here
independently from the rules in the comment block above SUBMENU_SUMMARY. Each
call also checks the contract: R9 and R10 unchanged, and the register bank of
the caller (R0..R7) intact.

Usage:  python3 M2M/rom/tests/summary_test.py           (exit status 0 = PASS)
        python3 M2M/rom/tests/summary_test.py mutants   (broken copies of
                m2m-rom.asm that the test must reject; exit status 0 = all
                rejected)
"""
import itertools
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import menu_test as mt  # noqa: E402  (golden model of the menu)

ASM = os.path.join(REPO, "M2M/QNICE/assembler/asm")
QNICE = os.path.join(REPO, "M2M/QNICE/emulator/qnice")
MONITOR = os.path.join(REPO, "M2M/QNICE/monitor/monitor.out")
M2M_ROM = os.path.join(REPO, "CORE/m2m-rom/m2m-rom.asm")
TOOLS = os.path.join(REPO, "M2M/rom/tools.asm")
STRINGS = os.path.join(REPO, "M2M/rom/strings.asm")
SYSDEF = os.path.join(REPO, "M2M/rom/sysdef.asm")
MEGA65 = os.path.join(REPO, "CORE/vhdl/mega65.vhd")
CONFIG = os.path.join(REPO, "CORE/vhdl/config.vhd")
GEN = os.path.join(HERE, "summary_test_gen.asm")
SRC = "summary_test.asm"
OUT = "summary_test.out"


class TestFail(Exception):
    pass


class AssemblyFail(Exception):
    pass


def fail(msg):
    raise TestFail(msg)


def read(path):
    with open(path) as f:
        return f.read()


def cut(lines, start_re, end_re, what, include_end=True):
    """Lines from the first match of start_re up to (and with include_end
    including) the first following match of end_re; exactly one start."""
    s = [i for i, l in enumerate(lines) if re.match(start_re, l)]
    if len(s) != 1:
        fail("%s: %d starts found (expected 1)" % (what, len(s)))
    for j in range(s[0] + 1, len(lines)):
        if re.match(end_re, lines[j]):
            return lines[s[0]:j + 1] if include_end else lines[s[0]:j]
    fail("%s: end not found" % what)


# ---------------------------------------------------------------------------
# what the testbed needs from the sources
# ---------------------------------------------------------------------------

def osm_constants():
    """C_MENU_* constants of mega65.vhd as C64_OSM_* (the make_rom.sh rule:
    'constant C_MENU_' lines only, subtypes are skipped)."""
    out = {}
    for m in re.finditer(r"^\s*constant\s+C_MENU_(\w+)\s*:\s*natural\s*:=\s*(\d+)\s*;",
                         read(MEGA65), re.M):
        out["C64_OSM_" + m.group(1)] = int(m.group(2))
    return out


def osm_dx():
    m = re.search(r"constant\s+OPTM_DX\s*:\s*natural\s*:=\s*(\d+)", read(CONFIG))
    if not m:
        fail("OPTM_DX not found in config.vhd")
    return int(m.group(1)) + 2           # SEL_OPTM_DIMENSIONS: getDXDY adds the frame


def ramrom_data():
    m = re.search(r"^M2M\$RAMROM_DATA\s+\.EQU\s+(0x[0-9A-Fa-f]+)", read(SYSDEF), re.M)
    if not m:
        fail("M2M$RAMROM_DATA not found in M2M/rom/sysdef.asm")
    return m.group(1)


def extracted_code():
    rom = read(M2M_ROM).splitlines()
    code = cut(rom, r"^SUBMENU_SUMMARY\s", r"^; Core specific callback functions: File browsing",
               "SUBMENU_SUMMARY", include_end=False)
    while code and code[-1].startswith("; ---"):          # the separator above the next section
        code.pop()
    data = cut(rom, r'^; On-screen "Kernal: %s" summary tags', r"^SS_V_T_MONO\s",
               "summary tags")
    bufs = cut(rom, r"^SS_VALUE_LEN\s", r"^SS_LINE\s", "summary buffers")
    rpl = cut(read(TOOLS).splitlines(), r"^M2M\$RPL_S\s", r'^_M2M\$RPL_S_S\s', "M2M$RPL_S")
    strs = read(STRINGS).splitlines()
    ell = [l for l in strs if re.match(r"^FN_ELLIPSIS\s", l)]
    err = [l for l in strs if re.match(r"^ERR_F_NO_S\s", l)]
    if len(ell) != 1 or len(err) != 1:
        fail("FN_ELLIPSIS / ERR_F_NO_S not found in M2M/rom/strings.asm")
    return code, data + [""] + ell + err, bufs, rpl


# ---------------------------------------------------------------------------
# the menu (golden model) and the test cases
# ---------------------------------------------------------------------------

MENU = mt.V6_MENU
N = len(MENU)
LABELS = [t for t, _, _ in MENU]
BASE = mt.menu_stdsel(MENU)
GROUPS = mt.menu_masked(MENU)


def idx(label, nth=0):
    return mt.flat_index(label, nth)


def members(g):
    return mt.group_members(MENU, g)


def trimmed(i):
    return LABELS[i].lstrip(" ")


def radio(state, group, ordinal):
    for i in members(group):
        state[i] = 0
    if ordinal is not None:
        state[members(group)[ordinal]] = 1


def clamp(line, width):
    """M2M$RPL_S: a result longer than width is cut and ends in '...'."""
    return line if len(line) <= width else line[:width - 3] + "..."


def expect(opener, state, ldf, width):
    """The rules documented above SUBMENU_SUMMARY, written independently."""
    sel = lambda g: [i for i in members(g) if state[i]]
    prefix = LABELS[opener].split("%s")[0]
    if LABELS[opener] == " Model: %s":
        mach, mode, speed = sel("MACHINE_MODE"), sel("TURBO_MODE"), sel("TURBO_SPEED")
        if not mach or not mode or mode[0] == members("TURBO_MODE")[0] or not speed:
            return "DEFAULT"
        return clamp(prefix + " ".join(trimmed(i) for i in (mach[0], mode[0], speed[0])), width)
    if LABELS[opener] == " Kernal: %s":
        k = sel("KERNAL_MODES")
        if not k or trimmed(k[0]) != "JiffyDOS" or not ldf[0]:
            return "DEFAULT"
        if ldf[1] and ldf[2]:
            return clamp(prefix + "Jiffy 1541+1581", width)
        if ldf[1] or ldf[2]:
            return clamp(prefix + "JiffyDOS " + ("1541" if ldf[1] else "1581"), width)
        return "DEFAULT"
    if LABELS[opener] == " Volume: %s":
        sid = sel("SID_SETUP")
        if not sid or not trimmed(sid[0]).startswith("L:"):     # mono SID: standard semantics
            return "DEFAULT"
        mix = sel("STEREO_MIX")
        vol = sel("VOLUME")
        if not mix or not vol:
            return "DEFAULT"
        tag = {"Full Stereo": "Stereo", "Wide Stereo": "Wide",
               "Narrow Stereo": "Narrow", "Mono": "Mono"}[trimmed(mix[0])]
        return clamp(prefix + trimmed(vol[0]) + " " + tag, width)
    return "DEFAULT"


def cases():
    """(description, opener flat index, state, ldf)"""
    out = []
    vol_open = idx(" Volume: %s")
    nvol = len(members("VOLUME"))
    for sid, mix, vol in itertools.product(range(6), range(4), (0, 1, 10, 19, 20)):
        st = list(BASE)
        radio(st, "SID_SETUP", sid)
        radio(st, "STEREO_MIX", mix)
        radio(st, "VOLUME", vol)
        out.append(("volume sid=%d mix=%d vol=%d" % (sid, mix, vol), vol_open, st, (0, 0, 0)))
    for vol in range(nvol):                                 # every volume label, Narrow
        st = list(BASE)
        radio(st, "SID_SETUP", 3)
        radio(st, "STEREO_MIX", 2)
        radio(st, "VOLUME", vol)
        out.append(("volume label %d" % vol, vol_open, st, (0, 0, 0)))
    for what in ("VOLUME", "STEREO_MIX"):                   # guards: empty radio groups
        st = list(BASE)
        radio(st, "SID_SETUP", 2)
        radio(st, what, None)
        out.append(("volume guard: no %s item" % what, vol_open, st, (0, 0, 0)))
    st = list(BASE)                                         # the Stereo Mix of the hidden...
    radio(st, "SID_SETUP", 1)                               # ...mono SID never shows
    radio(st, "STEREO_MIX", 3)
    out.append(("volume: mono 8580 + Mono mix", vol_open, st, (0, 0, 0)))
    for m, t, s in itertools.product(range(2), range(3), range(3)):
        st = list(BASE)
        radio(st, "MACHINE_MODE", m)
        radio(st, "TURBO_MODE", t)
        radio(st, "TURBO_SPEED", s)
        out.append(("model m=%d t=%d s=%d" % (m, t, s), idx(" Model: %s"), st, (0, 0, 0)))
    for k, ldf in itertools.product(range(4), itertools.product((0, 1), repeat=3)):
        st = list(BASE)
        radio(st, "KERNAL_MODES", k)
        out.append(("kernal k=%d ldf=%s" % (k, ldf), idx(" Kernal: %s"), st, ldf))
    # every other "%s" opener stays standard, also with a stereo SID + Wide selected
    # (the nested " Stereo: %s" opener must not be mistaken for the Volume line)
    others = [i for i, (t, _, f) in enumerate(MENU)
              if tuple(f) == mt.OPEN and "%s" in t and t not in (" Model: %s", " Kernal: %s", " Volume: %s")]
    for o in others:
        for stereo in (False, True):
            st = list(BASE)
            if stereo:
                radio(st, "SID_SETUP", 4)
                radio(st, "STEREO_MIX", 1)
            out.append(("other opener %d stereo=%s" % (o, stereo), o, st, (1, 1, 1)))
    return out


# ---------------------------------------------------------------------------
# generated testbed
# ---------------------------------------------------------------------------

def dw(words, per=12):
    out = []
    for k in range(0, len(words), per):
        out.append("                .DW     " + ", ".join("0x%04X" % (w & 0xFFFF) for w in words[k:k + per]))
    return out


def ascii_w(name, text):
    if '"' in text or "\\" in text:
        return [name] + dw([ord(c) for c in text] + [0])
    return ['%-15s .ASCII_W "%s"' % (name, text)]


def gen(case_list):
    code, data, bufs, rpl = extracted_code()
    consts = osm_constants()
    L = ["; DO NOT EDIT: generated by summary_test.py", ""]
    L += ["%-27s .EQU %d" % (k, v) for k, v in sorted(consts.items())]
    L += ["%-27s .EQU %s" % ("M2M$RAMROM_DATA", ramrom_data()),
          "%-27s .EQU %d" % ("ST_N", N),
          "%-27s .EQU %d" % ("ST_OSM_DX", osm_dx()), ""]
    L += ["; ---- copied verbatim from CORE/m2m-rom/m2m-rom.asm ----"] + code
    L += [""] + data + [""]
    L += ["; ---- copied verbatim from M2M/rom/tools.asm ----"] + rpl + [""]
    # the real OPTM_ITEMS string: "\n" is two characters, exactly like the VHDL string
    items = "".join(t + "\\n" for t in LABELS)
    L += ["ST_ITEMS"] + dw([ord(c) for c in items] + [0])
    L += ["ST_GROUPS"] + dw(GROUPS)
    L += ["ST_BASE"] + dw(BASE)
    # opener strings (with %s), one per case opener
    used = sorted({c[1] for c in case_list})
    for o in used:
        L += ascii_w("ST_LBL_%d" % o, LABELS[o])
    # cases: opener index, opener string, ldf0..2, then (index, value) diffs to BASE, 0xFFFF
    L += ["ST_CASES"]
    for _, o, st, ldf in case_list:
        diffs = [w for i in range(N) if st[i] != BASE[i] for w in (i, st[i])]
        L += ["                .DW     %d, ST_LBL_%d, %d, %d, %d" % ((o, o) + tuple(ldf))]
        L += dw(diffs + [0xFFFF]) if diffs else ["                .DW     0xFFFF"]
    L += ["                .DW     0xFFFF", ""]
    L += [""] + bufs + [""]
    L += ["HEAP            .BLOCK  24                      ; stub init record (OPTM_IR_*)",
          "CRTROM_AUT_LDF  .BLOCK  3",
          "SCR$OSM_O_DX    .BLOCK  1",
          "ST_STDSEL       .BLOCK  %d" % N, ""]
    with open(GEN, "w") as f:
        f.write("\n".join(L) + "\n")


def run(quiet=False):
    for p in (ASM, QNICE, MONITOR):
        if not os.path.exists(p):
            fail("missing %s (build the QNICE toolchain, see README.md)" % p)
    case_list = cases()
    gen(case_list)
    if os.path.exists(os.path.join(HERE, OUT)):              # never run a stale binary
        os.remove(os.path.join(HERE, OUT))
    r = subprocess.run([ASM, SRC], cwd=HERE, capture_output=True, text=True)
    errs = [l for l in (r.stdout + r.stderr).splitlines() if re.search(r"\berror\b", l, re.I)]
    if r.returncode != 0 or errs or not os.path.exists(os.path.join(HERE, OUT)):
        if not quiet:
            print(r.stdout[-2000:], r.stderr[-2000:])
        raise AssemblyFail("assembly failed")
    try:
        p = subprocess.run([QNICE, "-b", "0x8000", MONITOR, OUT], cwd=HERE, stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        fail("emulator timeout")
    out = p.stdout.decode("latin-1").replace("\r", "")
    got = [l for l in out.split("\n") if l.startswith("C ")]
    if "DONE" not in out:
        print(out[-2000:])
        fail("testbed did not finish")
    width = osm_dx() - 2
    bad = 0
    if len(got) != len(case_list):
        fail("%d results for %d cases" % (len(got), len(case_list)))
    seen_custom = {"Model": 0, "Kernal": 0, "Volume": 0}
    for (desc, o, st, ldf), g in zip(case_list, got):
        exp = "C " + expect(o, st, ldf, width) + " | REGS OK"
        if g != exp:
            bad += 1
            if bad <= 15 and not quiet:
                print("  MISMATCH %-34s got %r expected %r" % (desc, g, exp))
        elif "DEFAULT" not in g:
            for k in seen_custom:
                if g.startswith("C  " + k + ":"):
                    seen_custom[k] += 1
    summary = ("%d cases, %d custom lines (Model %d, Kernal %d, Volume %d), %d mismatches"
               % (len(case_list), sum(seen_custom.values()), seen_custom["Model"],
                  seen_custom["Kernal"], seen_custom["Volume"], bad))
    if bad or not all(seen_custom.values()):
        fail(summary)
    return summary


# mutants of CORE/m2m-rom/m2m-rom.asm that the test must reject: (name, old, new)
MUTANTS = [
    ("stereo SID list misses L: 8580 R: 8580",
     "C64_OSM_STEREO_L8R6, C64_OSM_STEREO_L8R8, 0", "C64_OSM_STEREO_L8R6, 0, 0"),
    ("Wide and Narrow tags swapped",
     'SS_V_T_WIDE     .ASCII_W "Wide"', 'SS_V_T_WIDE     .ASCII_W "Narrow"'),
    ("mono 8580 treated as a stereo SID",
     "SS_V_SID        .DW     C64_OSM_STEREO_L6R6,", "SS_V_SID        .DW     C64_OSM_MONO_8580, C64_OSM_STEREO_L6R6,"),
    ("Volume branch never taken",
     "CMP     C64_OSM_VOLUME_OPENER, R9", "CMP     C64_OSM_VOLUME_OPENER, R8"),
    ("no space before the tag",
     "MOVE    0x0020, @R8\n                ADD     1, R8\n_SS_V_TAG",
     "NOP\n                NOP\n_SS_V_TAG"),
    ("volume label taken from the opener line instead of the selected item",
     "SUB     M2M$RAMROM_DATA, R5     ; line", "MOVE    C64_OSM_VOLUME_OPENER, R5 ; line"),
]


def mutants():
    global M2M_ROM
    orig = M2M_ROM
    src = read(orig)
    killed = 0
    for name, old, new in MUTANTS:
        old = old.replace("\\n", "\n")
        new = new.replace("\\n", "\n")
        if src.count(old) != 1:
            print("  mutant %r: pattern found %d times (expected once)" % (name, src.count(old)))
            continue
        with tempfile.TemporaryDirectory() as d:
            M2M_ROM = os.path.join(d, "m2m-rom.asm")
            with open(M2M_ROM, "w") as f:
                f.write(src.replace(old, new))
            try:
                res = run(quiet=True)
                print("  mutant %r NOT detected (%s)" % (name, res))
            except AssemblyFail:
                print("  mutant %r is invalid: it does not assemble" % name)
            except TestFail as e:
                killed += 1
                print("  mutant %r rejected: %s" % (name, e))
        M2M_ROM = orig
    print("summary_test mutants: %d/%d rejected" % (killed, len(MUTANTS)))
    return 0 if killed == len(MUTANTS) else 1


def main():
    try:
        if len(sys.argv) > 1 and sys.argv[1] == "mutants":
            return mutants()
        print("summary_test: " + run())
        print("PASS: summary_test")
        return 0
    except (TestFail, AssemblyFail) as e:
        print("FAIL: summary_test: %s" % e)
        return 1


if __name__ == "__main__":
    sys.exit(main())
