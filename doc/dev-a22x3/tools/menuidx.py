#!/usr/bin/env python3
"""Independent cross-check of the menu index constants.

Usage: menuidx.py <rev> [<rev> ...]      (a rev can be WORKTREE)

For every revision: parses OPTM_ITEMS and OPTM_GROUPS of CORE/vhdl/config.vhd
and every C_MENU_* / R_MENU_* constant and subtype of CORE/vhdl/mega65.vhd and
prints, for each constant, the menu line it points to together with its
submenu path and its group. With several revisions it then compares: a
constant that exists in two revisions must point to the same line text, the
same submenu path and the same group name in both, and to the same position
within its group. Nothing of menu_test.py is used.
"""
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def read(rev, path):
    if rev == "WORKTREE":
        return open(REPO + "/" + path, encoding="utf-8", errors="replace").read()
    r = subprocess.run(["git", "-C", REPO, "show", "%s:%s" % (rev, path)],
                       stdout=subprocess.PIPE, check=True)
    return r.stdout.decode("utf-8", "replace")


def strip_comment(line):
    # VHDL comment outside of string literals
    out = []
    instr = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            instr = not instr
        if not instr and line.startswith("--", i):
            break
        out.append(c)
        i += 1
    return "".join(out)


def parse_config(text):
    lines = text.split("\n")
    # OPTM_ITEMS
    start = next(i for i, l in enumerate(lines) if re.match(r"\s*constant\s+OPTM_ITEMS\s*:", l))
    buf = []
    i = start
    while True:
        l = strip_comment(lines[i])
        buf.append(l)
        if ";" in re.sub(r'"[^"]*"', '""', l):
            break
        i += 1
    joined = " ".join(buf)
    lits = re.findall(r'"((?:[^"]|"")*)"', joined.split(":=", 1)[1])
    s = "".join(x.replace('""', '"') for x in lits)
    items = s.split("\\n")
    assert items[-1] == "", "OPTM_ITEMS does not end with \\n"
    items = items[:-1]
    # group constants
    gconst = {}
    for l in lines:
        m = re.match(r"\s*constant\s+(OPTM_G_\w+)\s*:\s*integer\s*:=\s*([0-9#A-Fa-f_]+)\s*;", l)
        if m:
            v = m.group(2)
            gconst[m.group(1)] = int(v.split("#")[1], 16) if "#" in v else int(v)
    # OPTM_GROUPS
    start = next(i for i, l in enumerate(lines) if re.match(r"\s*constant\s+OPTM_GROUPS\s*:", l))
    buf = []
    i = start
    depth = 0
    seen = False
    while True:
        l = strip_comment(lines[i])
        buf.append(l)
        depth += l.count("(") - l.count(")")
        if "(" in l:
            seen = True
        if seen and depth <= 0:
            break
        i += 1
    body = " ".join(buf).split(":=", 1)[1]
    body = body[body.index("(") + 1:body.rindex(")")]
    # split at top-level commas
    ents, cur, d = [], "", 0
    for c in body:
        if c == "(":
            d += 1
        elif c == ")":
            d -= 1
        if c == "," and d == 0:
            ents.append(cur.strip())
            cur = ""
        else:
            cur += c
    if cur.strip():
        ents.append(cur.strip())
    m = re.search(r"constant\s+OPTM_SIZE\s*:\s*natural\s*:=\s*(\d+)", text)
    size = int(m.group(1))
    return items, ents, gconst, size


def analyze(rev):
    items, ents, gconst, size = parse_config(read(rev, "CORE/vhdl/config.vhd"))
    problems = []
    if len(items) != size:
        problems.append("OPTM_ITEMS has %d lines, OPTM_SIZE is %d" % (len(items), size))
    if len(ents) != size:
        problems.append("OPTM_GROUPS has %d entries, OPTM_SIZE is %d" % (len(ents), size))
    ids = {}
    for k, v in gconst.items():
        if v < 255 and v > 0:
            ids.setdefault(v, []).append(k)
    for v, ks in sorted(ids.items()):
        if len(ks) > 1:
            problems.append("group id %d is used by %s" % (v, ", ".join(ks)))
    # path, group name, ordinal within the group
    info = []
    stack = []
    ordinal = {}
    for i, (it, en) in enumerate(zip(items, ents)):
        toks = [t.strip() for t in re.split(r"\+", re.sub(r"OPTM_DEP\w*\s*\([^)]*\)", "DEP", en))]
        is_close = "OPTM_G_CLOSE" in toks and "OPTM_G_SUBMENU" in toks
        is_open = "OPTM_G_SUBMENU" in toks and not is_close
        flags = ("OPTM_G_HEADLINE", "OPTM_G_LINE", "OPTM_G_STDSEL", "OPTM_G_SINGLESEL", "OPTM_G_SUBMENU",
                 "OPTM_G_CLOSE", "OPTM_G_HELP", "OPTM_G_MOUNT_DRV", "OPTM_G_LOAD_ROM", "OPTM_G_START",
                 "OPTM_G_TEXT", "DEP")
        grp = [t for t in toks if t.startswith("OPTM_G_") and t not in flags]
        g = grp[0] if grp else None
        path = " > ".join(stack)
        o = None
        if g:
            o = ordinal.get(g, 0)
            ordinal[g] = o + 1
        info.append(dict(idx=i, text=it, path=path, group=g, ord=o, std="OPTM_G_STDSEL" in toks, raw=en))
        if is_open:
            stack.append(it.strip())
        elif is_close:
            if not stack:
                problems.append("line %d closes a submenu that is not open" % i)
            else:
                stack.pop()
    if stack:
        problems.append("submenus left open at the end: %s" % stack)
    # constants of mega65.vhd
    consts = {}
    for l in read(rev, "CORE/vhdl/mega65.vhd").split("\n"):
        m = re.match(r"\s*constant\s+([CR]_MENU_\w+)\s*:\s*natural\s*:=\s*(\d+)\s*;", l)
        if m:
            consts[m.group(1)] = (int(m.group(2)),)
        m = re.match(r"\s*subtype\s+([CR]_MENU_\w+)\s+is\s+natural\s+range\s+(\d+)\s+downto\s+(\d+)\s*;", l)
        if m:
            consts[m.group(1)] = (int(m.group(3)), int(m.group(2)))
    return dict(rev=rev, items=items, info=info, consts=consts, problems=problems, size=size)


def describe(a, idx):
    if idx >= len(a["info"]):
        return ("<OUT OF RANGE>", "", None, None)
    x = a["info"][idx]
    return (x["text"], x["path"], x["group"], x["ord"])


def main():
    revs = sys.argv[1:]
    res = [analyze(r) for r in revs]
    for a in res:
        print("=== %s: OPTM_SIZE %d, %d constants, OPTM_ITEMS %d characters"
              % (a["rev"], a["size"], len(a["consts"]),
                 sum(len(x) + 2 for x in a["items"])))
        for p in a["problems"]:
            print("  PROBLEM: " + p)
    bad = 0
    names = []
    for a in res:
        for n in a["consts"]:
            if n not in names:
                names.append(n)
    last = res[-1]
    for n in names:
        rows = []
        for a in res:
            if n in a["consts"]:
                rows.append((a["rev"], a["consts"][n], [describe(a, i) for i in a["consts"][n]]))
        ref = rows[-1][2]
        same = all(r[2] == ref for r in rows)
        if not same:
            bad += 1
        if n in last["consts"]:
            v = last["consts"][n]
            d = ref
            txt = " .. ".join("%d=%r [%s] %s#%s" % (i, t[0], t[1], t[2], t[3]) for i, t in zip(v, d))
            print("%s %-26s %s%s" % ("ok " if same else "BAD", n, txt,
                                     "" if same else "   <-- differs: " + "; ".join(
                                         "%s: %s" % (r[0], r[2]) for r in rows)))
        else:
            print("??? %-26s not in %s" % (n, last["rev"]))
    # default selections of the last revision
    print("--- default selections (OPTM_G_STDSEL) in %s:" % last["rev"])
    for x in last["info"]:
        if x["std"]:
            print("  %3d %-28r [%s] %s#%s" % (x["idx"], x["text"], x["path"], x["group"], x["ord"]))
    print("RESULT: %s" % ("OK" if bad == 0 and not any(a["problems"] for a in res) else "CHECK (%d constants differ)" % bad))


if __name__ == "__main__":
    main()
