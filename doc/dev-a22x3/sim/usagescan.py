#!/usr/bin/env python3
"""
usagescan.py: static scan of the firmware sources for every use of a string ROM
label (a label that is defined between ;STRROM_BEGIN and ;STRROM_END).

For each use the scan follows the code that comes after it, up to the next call
or jump, and names the routine that receives the value (the "sink"). Sinks that
accept a handle are listed in OK_SINKS; every other use is printed for a manual
review.

usage: usagescan.py SRC_ROOT [--all]
"""
import os
import re
import sys

OK_SINKS = {
    "SYSCALL(puts", "IO$PUTS", "LOG_STR", "SCR$PRINTSTR", "SCR$PRINTSTRXY", "FATAL", "FATAL_IDX",
    "STRROM$OPEN",
}

FILES_GLOBS = ["M2M/rom", "M2M/rom/monitor", "CORE/m2m-rom"]


def sources(root):
    res = []
    for d in FILES_GLOBS:
        p = os.path.join(root, d)
        for n in sorted(os.listdir(p)):
            if n.endswith(".asm"):
                res.append(os.path.join(p, n))
    return res


def main():
    root = sys.argv[1]
    show_all = "--all" in sys.argv
    files = sources(root)
    text = {f: open(f, errors="replace").read().split("\n") for f in files}
    labels = {}
    for f, lines in text.items():
        inside = False
        for i, l in enumerate(lines):
            s = l.strip()
            if s.startswith(";STRROM_BEGIN"):
                inside = True
                continue
            if s.startswith(";STRROM_END"):
                inside = False
                continue
            if inside:
                m = re.match(r"^([A-Za-z_$][A-Za-z0-9_$]*)(\s|$)", l)
                if m:
                    labels[m.group(1)] = (f, i + 1)
    print("%d string ROM labels in %d source files" % (len(labels), len(files)))
    word = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
    uses = []
    for f, lines in text.items():
        for i, l in enumerate(lines):
            code = l.split(";", 1)[0]
            if not code.strip():
                continue
            m0 = re.match(r"^([A-Za-z_$][A-Za-z0-9_$]*)", code)
            deflabel = m0.group(1) if m0 else None
            body = code[len(deflabel):] if deflabel else code
            for w in word.findall(body):
                if w in labels:
                    uses.append((w, f, i, body.strip()))
    counts = {}
    review = []
    unused = set(labels)
    for w, f, i, body in uses:
        unused.discard(w)
        lines = text[f]
        sink = None
        trail = []
        # the use itself may be a .DW/.EQU (table of strings) or an instruction
        if re.match(r"^\.(DW|EQU)\b", body):
            sink = "table/.DW" if body.startswith(".DW") else ".EQU"
        else:
            for k in range(i + 1, min(i + 14, len(lines))):
                c = lines[k].split(";", 1)[0]
                c2 = re.sub(r"^[A-Za-z_$][A-Za-z0-9_$]*", "", c).strip()
                if not c2:
                    continue
                trail.append(c2)
                m = re.match(r"^(RSUB|RBRA|ABRA|ASUB)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*,\s*(\S+)", c2)
                if m:
                    cond = m.group(3)
                    if m.group(1) in ("RSUB", "ASUB") or cond == "1":
                        sink = m.group(2)
                        break
                    continue            # conditional branch: keep following the straight path
                m = re.match(r"^SYSCALL\(\s*([a-z0-9_]+)", c2)
                if m:
                    sink = "SYSCALL(" + m.group(1)
                    break
                if re.match(r"^(RET|HALT)\b", c2):
                    sink = "RET"
                    break
        key = sink or "?"
        counts[key] = counts.get(key, 0) + 1
        ok = key in OK_SINKS
        # a use with an accepted sink still needs a look if the code between the use and
        # the call does more than moving values around
        busy = [t for t in trail[:-1] if not re.match(r"^(MOVE|XOR)\b", t)]
        if show_all or not ok or busy:
            review.append((key if not (ok and busy) else key + " after other instructions", w,
                           os.path.relpath(f, root), i + 1, body, trail[:8]))
    print("uses: %d; sinks: %s" % (len(uses), ", ".join("%s x%d" % kv for kv in sorted(counts.items(), key=lambda kv: -kv[1]))))
    print("labels without any use in the sources: %d %s" % (len(unused), " ".join(sorted(unused))))
    print()
    for key, w, f, ln, body, trail in sorted(review):
        print("[%s] %s  %s:%d  %s" % (key, w, f, ln, body))
        if key not in OK_SINKS:
            for t in trail:
                print("        | " + t)
    return 0


if __name__ == "__main__":
    sys.exit(main())
