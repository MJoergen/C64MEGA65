#!/usr/bin/env python3
"""
Static scan of a qasm listing for a side effect of the handle-aware string
output routines: STRROM$OPEN executes CMP, "AND 0xFFFB, SR", SHR and ADD, so
IO$PUTS (SYSCALL puts), LOG_STR and SCR$PRINTSTR do not preserve the Carry
flag (C) and the overflow flag (V) any more. The old IO$PUTS consisted of
MOVE, AND and branches only and preserved both.

    flagscan.py LISTING

Flag rules of the QNICE CPU (qnice_cpu.vhd): ADD, ADDC, SUB and SUBC define C
and V; SHL defines C; CMP defines V; SHR, ADDC and SUBC consume C; a branch or
call with the condition C, !C, V or !V consumes the flag; a write to SR
defines all flags; RET is a MOVE to PC and defines Z, N and X but not C and V.

Two scans:

  forward   from every call of an output routine along the fall-through path:
            is C or V consumed before it is defined again? Routines that reach
            their RET with C as the output call left it are listed.
  backward  from every consumer of C or V along the listing: what is the
            nearest instruction before it that defines the flag or calls a
            routine? Reported if that is an output routine or one of the
            routines of the forward scan that return with an undefined C.
"""
import re
import sys

LINE = re.compile(r"^(\d{6})\s+([0-9A-F]{4})\s+((?:[0-9A-F]{4}\s+)+)\s*(.*)$")
MN = ("MOVE", "ADD", "ADDC", "SUB", "SUBC", "SHL", "SHR", "SWAP", "NOT", "AND", "OR", "XOR", "CMP",
      "HALT", "RTI", "INT", "INCRB", "DECRB", "ABRA", "ASUB", "RBRA", "RSUB")
OUTPUT = re.compile(r"^(ASUB puts|RSUB IO\$PUTS|RSUB LOG_STR|RSUB SCR\$PRINTSTR(XY)?)\s*,")
TRANSPARENT = re.compile(r"^(ASUB (crlf|leave|enter|putc)|RSUB (IO\$PUT_CRLF|IO\$PUTCHAR|STRROM\$CLOSE))\s*,")


def load(path):
    rows = []
    for line in open(path, errors="replace"):
        if line.startswith("Label-list:"):
            break
        m = LINE.match(line.rstrip("\n"))
        if not m:
            continue
        text = m.group(4).split(";")[0].rstrip()
        parts = text.split()
        for i, p in enumerate(parts):
            if p in MN:
                rows.append(dict(addr=m.group(2), mn=p, ops=" ".join(parts[i + 1:]),
                                 label=parts[0] if i > 0 else None, text=text.strip()))
                break
    return rows


def cond(r):
    return r["ops"].split(",")[-1].strip() if r["mn"] in ("RBRA", "ABRA", "RSUB", "ASUB") else ""


def dst(r):
    return r["ops"].split(",")[-1].strip() if "," in r["ops"] else ""


def is_ret(r):
    return r["mn"] == "MOVE" and r["ops"].replace(" ", "") == "@R13++,R15"


def defines_c(r):
    return r["mn"] in ("ADD", "ADDC", "SUB", "SUBC", "SHL") or dst(r) in ("SR", "R14")


def defines_v(r):
    return r["mn"] in ("ADD", "ADDC", "SUB", "SUBC", "CMP") or dst(r) in ("SR", "R14")


def routine(rows, i):
    for j in range(i, -1, -1):
        if rows[j]["label"] and not rows[j]["label"].startswith("_"):
            return rows[j]["label"]
    return "?"


def main():
    rows = load(sys.argv[1])
    key = lambda r: r["mn"] + " " + r["ops"]
    sites = [i for i, r in enumerate(rows) if OUTPUT.match(key(r))]
    print("%d calls of puts / IO$PUTS / LOG_STR / SCR$PRINTSTR(XY)" % len(sites))

    # ---- forward scan
    hits = 0
    tail = {}
    for i in sites:
        c_live = v_live = True
        for j in range(i + 1, min(i + 60, len(rows))):
            q = rows[j]
            c = cond(q)
            if (c_live and (c in ("C", "!C") or q["mn"] in ("ADDC", "SUBC", "SHR"))) or (v_live and c in ("V", "!V")):
                hits += 1
                print("forward: call at %s (%s) -> flag consumed at %s: %s" %
                      (rows[i]["addr"], rows[i]["text"], q["addr"], q["text"]))
                break
            if defines_c(q):
                c_live = False
            if defines_v(q):
                v_live = False
            if not c_live and not v_live:
                break
            if is_ret(q):
                if c_live:
                    tail.setdefault(routine(rows, i), []).append(rows[i]["addr"])
                break
            if q["mn"] in ("RBRA", "ABRA") and c == "1":
                break
            if q["mn"] in ("RSUB", "ASUB") and not OUTPUT.match(key(q)) and not TRANSPARENT.match(key(q)):
                break
    print("forward: %d consumers of C or V after an output call" % hits)
    print("forward: routines that return with C as an output call left it: %s" %
          (", ".join("%s (%s)" % (k, " ".join(v)) for k, v in tail.items()) or "-"))

    # ---- backward scan
    suspicious = re.compile(r"^(RSUB|ASUB) (%s)\s*," % "|".join(re.escape(k) for k in tail)) if tail else None
    hits = unknown = consumers = 0
    for i, r in enumerate(rows):
        c = cond(r)
        want_c = c in ("C", "!C") or r["mn"] in ("ADDC", "SUBC", "SHR")
        want_v = c in ("V", "!V")
        if not want_c and not want_v:
            continue
        consumers += 1
        found = None
        for j in range(i - 1, max(i - 40, -1), -1):
            q = rows[j]
            if (want_c and defines_c(q)) or (want_v and defines_v(q)):
                found = "defined"
                break
            if q["mn"] in ("RSUB", "ASUB"):
                if OUTPUT.match(key(q)) or (suspicious and suspicious.match(key(q))):
                    found = "OUTPUT"
                    hits += 1
                    print("backward: %s at %s (%s) gets its flag from %s: %s" %
                          ("C" if want_c else "V", r["addr"], r["text"], q["addr"], q["text"]))
                elif TRANSPARENT.match(key(q)):
                    continue
                else:
                    found = "call"
                break
            if is_ret(q) or (q["mn"] in ("RBRA", "ABRA") and cond(q) == "1"):
                found = "entry"               # start of a block: the flag comes from a jump or a caller
                break
        if found in (None, "entry"):
            unknown += 1
    print("backward: %d consumers of C or V; %d get the flag from an output routine; for %d the flag is "
          "defined before the start of the basic block (jump target or routine entry)" %
          (consumers, hits, unknown))


if __name__ == "__main__":
    main()
