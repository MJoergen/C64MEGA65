#!/usr/bin/env python3
"""
Fixture tests for M2M/tools/asm_strrom.sh, the tool that builds the string
ROM (see M2M/rom/strrom.asm and strrom_test.py).

Every case writes a small QNICE program into a directory of its own and calls
the tool with its absolute path from there. A broken fixture must end with
exit code 1, an error message that names the problem, and neither
<firmware>.rom nor <strings>.rom. A correct fixture must end with exit code 0,
and its string ROM must contain, at the position that the table word of each
label holds, the same zero-terminated string that the assembler produces for
that label when the strings are assembled in place. No case may leave
temporary files behind.

Usage:
    python3 strrom_tool_test.py [<repository>] [<case> ...]

The repository defaults to the one that contains this file; the cases default
to all of them. Exit code 0: every case behaves, 1: at least one does not.
The fixtures are deleted when every case behaves, otherwise they are kept and
their directory is printed.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
if len(sys.argv) > 1 and os.path.isdir(sys.argv[1]):
    REPO = os.path.abspath(sys.argv.pop(1))
else:
    REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "M2M", "rom", "tests"))
import strrom_test as T   # noqa: E402  (Listing, read_out, zstring, ...)

TOOL = os.path.join(REPO, "M2M", "tools", "asm_strrom.sh")
QASM = os.path.join(REPO, "M2M", "QNICE", "assembler", "qasm")

HEAD = """\
                .ORG    0x0000
                MOVE    0x1234, R0
                HALT
STRROM$TAB
;STRROM_TABLE
STRROM$TAB_END
"""


def sec(*lines):
    return ";STRROM_BEGIN\n" + "".join(l + "\n" for l in lines) + \
        ";STRROM_END\n"


def long_string(label, n, ch="x", terminated=True, width=150):
    """A string of n characters, built from .ASCII_P lines of at most width
    characters (the tool accepts lines of at most 200 characters between the
    markers)."""
    out, first = [], True
    while n > 0:
        k = min(n, width)
        n -= k
        last = n == 0
        d = ".ASCII_W" if (last and terminated) else ".ASCII_P"
        out.append("%-16s%s \"%s\"" % (label if first else "", d, ch * k))
        first = False
    if not out:
        out.append("%-16s.ASCII_W \"\"" % label)
    return out


CASES = []


def case(name, src, expect, msg=None, aw="12", fw="fw.asm", strs="strs",
         labels=None, check=None, args=None, dirname=None, crlf=False,
         nofile=False):
    CASES.append(dict(name=name, src=src, expect=expect, msg=msg, aw=aw,
                      fw=fw, strs=strs, labels=labels, check=check,
                      args=args, dirname=dirname, crlf=crlf, nofile=nofile))


# --- correct use --------------------------------------------------------
case("several_sections",
     HEAD + sec('A1              .ASCII_W "first"',
                'A2              .ASCII_P "second, "',
                '                .ASCII_W "continued"') +
     "                MOVE    R1, R2\n" +
     sec('B1              .ASCII_W "third"') +
     "; between\n" + sec('C1              .ASCII_W ""'),
     "ok", labels=["A1", "A2", "B1", "C1"])
case("label_only_line",
     HEAD + sec("LBL", '                .ASCII_W "on the next line"'),
     "ok", labels=["LBL"])
case("label_then_comment_then_string",
     HEAD + sec("LBL             ; comment with \"quote\"", "; comment",
                "", '                .ASCII_W "after a comment"'),
     "ok", labels=["LBL"])
case("two_labels_same_string",
     HEAD + sec("L1", 'L2              .ASCII_W "shared"'),
     "ok", labels=["L1", "L2"])
case("label_into_middle_of_string",
     HEAD + sec('L1              .ASCII_P "head "',
                'L2              .ASCII_W "tail"'),
     "ok", labels=["L1", "L2"])
case("comment_between_continuations",
     HEAD + sec('L1              .ASCII_P "part 1, "',
                "; a comment line", "",
                '                .ASCII_P "part 2, "',
                '                .ASCII_W "part 3"'),
     "ok", labels=["L1"])
case("special_characters",
     HEAD + sec('S1              .ASCII_W "semi;colon"',
                'S2              .ASCII_W "percent %s %d 100%"',
                'S3              .ASCII_W "newline\\n tab\\t end"',
                'S5              .ASCII_W "literal\ttab"',
                'S7              .ASCII_W "\\x41 \\a"'),
     "ok", labels=["S1", "S2", "S3", "S5", "S7"])
# qasm stores an undefined word for a backslash that is followed by a double
# quote or by a backslash (see assemble() in qasm.c), so the tool rejects both
case("backslash_before_double_quote",
     HEAD + sec('S4              .ASCII_W "quote \\" end"'),
     "fail", msg=r"backslash that is followed by")
case("backslash_before_backslash",
     HEAD + sec('S6              .ASCII_W "back\\\\slash"'),
     "fail", msg=r"backslash that is followed by")
case("string_without_closing_quote",
     HEAD + sec('S8              .ASCII_W "open end'),
     "fail", msg=r"without a closing double quote")
case("label_with_dollar",
     HEAD + sec('MOD$NAME        .ASCII_W "dollar"'),
     "ok", labels=["MOD$NAME"])
case("crlf_line_endings",
     HEAD + sec('C1              .ASCII_W "crlf"', "C2",
                '                .ASCII_W "crlf 2"'),
     "ok", labels=["C1", "C2"], crlf=True)
case("marker_leading_blanks_tabs_trailing_blanks",
     HEAD.replace(";STRROM_TABLE", " \t;STRROM_TABLE  ") +
     "   ;STRROM_BEGIN\n" + 'M1              .ASCII_W "m1"\n' +
     "\t; STRROM_END \t\n",
     "ok", labels=["M1"])
case("marker_trailing_text_is_no_marker",
     HEAD + ";STRROM_BEGIN here\n" + 'T1              .ASCII_W "t1"\n' +
     ";STRROM_END here\n",
     "ok", labels=[], check="not_moved:T1")
case("marker_lower_case_is_no_marker",
     HEAD + ";strrom_begin\n" + 'T1              .ASCII_W "t1"\n' +
     ";strrom_end\n",
     "ok", labels=[], check="not_moved:T1")
case("no_table_marker",
     HEAD.replace(";STRROM_TABLE\n", "") +
     sec('N1              .ASCII_W "stays in the firmware"'),
     "ok", labels=[], check="no_table:N1")
case("string_fills_4k_block",
     HEAD + sec(*long_string("F1", 4095)), "ok", aw="13", labels=["F1"],
     check="pos:F1=0")
case("exactly_full_rom",
     HEAD + sec(*(long_string("F1", 4095) + long_string("F2", 4095))),
     "ok", aw="13", labels=["F1", "F2"], check="pos:F2=4096")
case("padding_at_4k_boundary",
     HEAD + sec(*(long_string("P1", 3000) + long_string("P2", 2000) +
                  long_string("P3", 10))),
     "ok", aw="13", labels=["P1", "P2", "P3"],
     check="pos:P2=4096,P3=6097")
case("directory_with_space",
     HEAD + sec('D1              .ASCII_W "space"'), "ok", labels=["D1"],
     dirname="dir with space")
case("empty_string_only",
     HEAD + sec('E1              .ASCII_W ""'), "ok", labels=["E1"])

# --- errors -------------------------------------------------------------
case("begin_twice",
     HEAD + ";STRROM_BEGIN\n" + sec('A .ASCII_W "a"'.replace("A ", "A1 ")),
     "fail", msg=r"STRROM_BEGIN follows STRROM_BEGIN")
case("end_without_begin",
     HEAD + ";STRROM_END\n", "fail", msg=r"STRROM_END without STRROM_BEGIN")
case("begin_without_end",
     HEAD + ";STRROM_BEGIN\n" + 'A1              .ASCII_W "a"\n',
     "fail", msg=r"STRROM_BEGIN without STRROM_END")
case("equ_between_markers",
     HEAD + sec("CONST           .EQU    5", 'A1              .ASCII_W "a"'),
     "fail", msg=r"only labels.*\.EQU")
case("dw_between_markers",
     HEAD + sec("TBL             .DW     1, 2", 'A1              .ASCII_W "a"'),
     "fail", msg=r"only labels.*\.DW")
case("block_between_markers",
     HEAD + sec("BUF             .BLOCK  4", 'A1              .ASCII_W "a"'),
     "fail", msg=r"only labels.*\.BLOCK")
case("instruction_between_markers",
     HEAD + sec('A1              .ASCII_W "a"', "                MOVE    R1, R2",
                'A2              .ASCII_W "b"'),
     "fail", msg=r"only labels.*MOVE")
case("section_ends_with_ascii_p",
     HEAD + sec('A1              .ASCII_P "open"'),
     "fail", msg=r"needs to end with an \.ASCII_W")
case("label_without_string",
     HEAD + sec('A1              .ASCII_W "a"', "DANGLING"),
     "fail", msg=r"label DANGLING is not followed by a string")
case("string_without_label",
     HEAD + sec('A1              .ASCII_W "a"', '                .ASCII_W "b"'),
     "fail", msg=r"string without a label")
case("empty_section",
     HEAD + sec("; nothing here"), "fail", msg=r"no string between")
case("string_longer_than_4095",
     HEAD + sec(*long_string("L1", 4096)), "fail", aw="13",
     msg=r"4097 characters.*maximum is 4096")
case("rom_overflow",
     HEAD + sec(*(long_string("F1", 4095) + long_string("F2", 1))),
     "fail", aw="12", msg=r"string ROM is full")
case("rom_overflow_by_padding",
     HEAD + sec(*(long_string("F1", 3000) + long_string("F2", 2000))),
     "fail", aw="12", msg=r"string ROM is full")
case("two_table_markers",
     HEAD + ";STRROM_TABLE\n" + sec('A1              .ASCII_W "a"'),
     "fail", msg=r"STRROM_TABLE occurs 2 times")
case("table_marker_inside_section",
     HEAD.replace(";STRROM_TABLE\n", "") +
     sec('A1              .ASCII_W "a"', ";STRROM_TABLE"),
     "fail", msg=r"STRROM_TABLE is located between")
case("lower_case_directive",
     HEAD + sec('A1              .ascii_w "a"'), "fail", msg=r"only labels")
case("directive_in_column_1",
     HEAD + sec('.ASCII_W "a"'), "fail", msg=r"only labels")
# qasm does not handle long source lines (it reads at most 254 characters of
# a line and its listing writer needs room for the indentation), so the tool
# limits the lines between the markers to 200 characters
# (the C preprocessor keeps the indentation of a line, but reduces the blanks
# behind a label to one, so the limit is tested with a continuation line)
case("line_with_200_characters",
     HEAD + sec('A1              .ASCII_P "a"',
                '                .ASCII_W "%s"' % ("y" * 173)),
     "ok", labels=["A1"])
case("line_with_201_characters",
     HEAD + sec('A1              .ASCII_P "a"',
                '                .ASCII_W "%s"' % ("y" * 174)),
     "fail", msg=r"more than 200 characters")
case("line_longer_than_242",
     HEAD + sec('A1              .ASCII_W "%s"' % ("y" * 216)),
     "fail", msg=r"more than 200 characters")
case("address_width_11", HEAD + sec('A1              .ASCII_W "a"'),
     "fail", aw="11", msg=r"between 12 and 16")
case("address_width_17", HEAD + sec('A1              .ASCII_W "a"'),
     "fail", aw="17", msg=r"between 12 and 16")
case("address_width_abc", HEAD + sec('A1              .ASCII_W "a"'),
     "fail", aw="abc", msg=r"not a number")
case("address_width_empty", HEAD + sec('A1              .ASCII_W "a"'),
     "fail", aw="", msg=r"not a number")
case("address_width_leading_zero_014",
     HEAD + sec('A1              .ASCII_W "a"'), "ok", aw="014",
     labels=["A1"], check="rom_lines:16384")
case("address_width_leading_zero_09",
     HEAD + sec('A1              .ASCII_W "a"'), "fail", aw="09",
     msg=r"address width")
case("missing_source_file", "", "fail", nofile=True,
     msg=r"not an existing \.asm file")
case("wrong_argument_count", HEAD, "fail", args=["fw.asm", "strs"],
     msg=r"Usage")
case("strings_name_equals_firmware_name",
     HEAD + sec('A1              .ASCII_W "a"'), "fail", strs="fw",
     msg=r"needs to differ")
case("strings_name_with_directory",
     HEAD + sec('A1              .ASCII_W "a"'), "fail", strs="sub/strs",
     msg=r"without a directory")
case("exported_label_between_markers",
     HEAD + sec('EXPORTED!       .ASCII_W "exported"'), "fail",
     msg=r"label EXPORTED! is exported")
case("assembler_error_in_strings",
     HEAD + sec('A1              .ASCII_W "a"', 'A1              .ASCII_W "b"'),
     "fail", msg=r"assembling the string ROM strings failed")
case("assembler_error_in_firmware",
     HEAD + "                BOGUS   R1\n" + sec('A1              .ASCII_W "a"'),
     "fail", msg=r"assembling fw\.asm failed")


# -------------------------------------------------------------------------


def run(cmd, cwd):
    r = subprocess.run(cmd, cwd=cwd, stdin=subprocess.DEVNULL,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                       timeout=120)
    return r.returncode, r.stdout.decode("latin-1")


def reference(src_path, workdir):
    """Assemble the fixture with the strings in place."""
    os.makedirs(workdir)
    cpp = shutil.which("cc") or shutil.which("gcc")
    r = subprocess.run([cpp, "-xc", "-E", src_path], stdout=subprocess.PIPE,
                       stderr=subprocess.DEVNULL)
    text = "\n".join(l for l in r.stdout.decode("latin-1").splitlines()
                     if not l.startswith("#")) + "\n"
    asm = os.path.join(workdir, "ref.asm")
    with open(asm, "w", encoding="latin-1") as f:
        f.write(text)
    run([QASM, asm, os.path.join(workdir, "ref.out")], workdir)
    lis = T.Listing(os.path.join(workdir, "ref.lis"))
    return lis, T.read_out(os.path.join(workdir, "ref.out"))


def verify_ok(c, d, problems):
    fw = c["fw"][:-4]
    strs = c["strs"]
    size = 1 << int(c["aw"], 10)
    rom_path = os.path.join(d, strs + ".rom")
    with open(rom_path) as f:
        lines = f.read().split("\n")
    if lines[-1] == "":
        lines.pop()
    if c["check"] and c["check"].startswith("rom_lines:"):
        size = int(c["check"].split(":")[1])
    if len(lines) != size:
        problems.append("%s.rom has %d lines, expected %d"
                        % (strs, len(lines), size))
    rom = [int(l, 16) for l in lines]
    new = T.Listing(os.path.join(d, fw + ".lis"))
    mem = T.read_out(os.path.join(d, fw + ".out"))
    ref, ref_mem = reference(os.path.join(d, c["fw"]), os.path.join(d, "ref"))
    tab, end = new.labels["STRROM$TAB"], new.labels["STRROM$TAB_END"]
    table = {n: a for n, a in new.labels.items()
             if tab <= a < end and n != "STRROM$TAB"}
    want = set(c["labels"] or [])
    if set(table) != want:
        problems.append("table labels %s, expected %s"
                        % (sorted(table), sorted(want)))
    used = set()
    pos = {}
    for n, a in table.items():
        p = mem[a]
        pos[n] = p
        got = T.zstring(rom, p, len(rom))
        exp = T.zstring(ref_mem, ref.labels[n], 0x10000)
        if got != exp:
            problems.append("%s: ROM %s, in place %s"
                            % (n, T.show(got or []), T.show(exp or [])))
            continue
        if p // 4096 != (p + len(got) - 1) // 4096:
            problems.append("%s crosses a 4k boundary" % n)
        used.update(range(p, p + len(got)))
    junk = [a for a in range(len(rom)) if rom[a] and a not in used]
    if junk:
        problems.append("%d nonzero characters outside of the strings"
                        % len(junk))
    chk = c["check"] or ""
    if chk.startswith("pos:"):
        for item in chk[4:].split(","):
            n, v = item.split("=")
            if pos.get(n) != int(v):
                problems.append("%s at %s, expected %s" % (n, pos.get(n), v))
    if chk.startswith("not_moved:") or chk.startswith("no_table:"):
        n = chk.split(":")[1]
        if n in table:
            problems.append("%s was moved into the string ROM" % n)
        exp = T.zstring(ref_mem, ref.labels[n], 0x10000)
        got = T.zstring(mem, new.labels[n], 0x10000)
        if got != exp:
            problems.append("%s in the firmware differs" % n)
        if any(rom):
            problems.append("the string ROM is not all zero")


def main():
    only = set(sys.argv[1:])
    unknown = only - {c["name"] for c in CASES}
    if unknown:
        print("unknown case: %s" % ", ".join(sorted(unknown)))
        return 2
    base = tempfile.mkdtemp(prefix="strrom_tool_test_")
    bad = 0
    print("Each case feeds asm_strrom.sh one small program, many of them broken on")
    print("purpose. \"accepted\" and \"rejected\" say what the tool did, followed by its")
    print("message; \"ok\" means that this is the expected reaction, \"BAD\" that it is")
    print("not.")
    for c in CASES:
        if only and c["name"] not in only:
            continue
        d = os.path.join(base, c["name"], c["dirname"] or "fx")
        os.makedirs(d)
        if "/" in c["strs"]:
            os.makedirs(os.path.join(d, os.path.dirname(c["strs"])))
        if not c["nofile"]:
            src = c["src"]
            if c["crlf"]:
                src = src.replace("\n", "\r\n")
            with open(os.path.join(d, c["fw"]), "w", newline="") as f:
                f.write(src)
        args = c["args"] if c["args"] is not None else \
            [c["fw"], c["strs"], c["aw"]]
        rc, out = run(["bash", TOOL] + args, d)
        problems = []
        fw = c["fw"][:-4]
        leftovers = sorted(f for f in os.listdir(d) if f.startswith("__"))
        if leftovers:
            problems.append("temporary files left: %s" % ", ".join(leftovers))
        if c["expect"] == "fail":
            if rc != 1:
                problems.append("exit code %d, expected 1" % rc)
            if "ERROR" not in out and "Usage" not in out:
                problems.append("no error message")
            if c["msg"] and not re.search(c["msg"], out, re.S):
                problems.append("message does not match /%s/" % c["msg"])
            for f in (fw + ".rom", c["strs"] + ".rom"):
                if os.path.exists(os.path.join(d, f)):
                    problems.append("%s left behind" % f)
        else:
            if rc != 0:
                problems.append("exit code %d, expected 0" % rc)
            else:
                try:
                    verify_ok(c, d, problems)
                except Exception as e:     # report, do not stop the run
                    problems.append("verification crashed: %r" % e)
        status = "ok  " if not problems else "BAD "
        bad += bool(problems)
        first = [l for l in out.splitlines() if l.strip()]
        msg = next((l for l in first if "ERROR" in l or "String ROM" in l),
                   first[-1] if first else "")
        what = "accepted" if rc == 0 else "rejected"
        msg = msg.replace("ERROR: ", "", 1)
        print("%s %-44s %s: %s" % (status, c["name"], what, msg[:104]))
        for p in problems:
            print("       - " + p)
    n = len(only) if only else len(CASES)
    if bad:
        print("STRROM TOOL TEST FAILED: %d of %d cases misbehave; the "
              "fixtures are in %s" % (bad, n, base))
        return 1
    shutil.rmtree(base, ignore_errors=True)
    print("STRROM TOOL TEST OK: %d cases" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
