#!/usr/bin/env python3
"""Checker of tb_hdmi_raw_clock (issue #184, doc/dev-hdmi-raw/SPEC.md section 4.2).

    check_drp.py OLD_LOG OLD_VHDL NEW_LOG NEW_VHDL REPO

OLD_LOG: the bench with the 3-bit version of video_out_clock.vhd (OLD_VHDL),
NEW_LOG: the bench with the 4-bit version (NEW_VHDL). A step of a log is
everything from one "SEL" line to the next; times are taken relative to the
SEL line of the step.

Checks:
  1. Both runs end ("SIMULATION DONE") without an ERROR line of the MMCM model.
  2. Every step: rsto is '0' and clko runs on the MMCM output (period 13 ns)
     when the step ends, i.e. the loader is back in IDLE; the step writes 23
     DRP registers, each one right after reading it, in the order of the table
     that the code selects, and every written value is
     (read value and mask) or (table data and not mask) for that table, the
     table being parsed from the VHDL file itself.
  3. The old and the new run are identical for the power-on step and the
     eight old codes (0000 to 0111 versus 000 to 111): every DRP access with
     address and data, every change of the MMCM reset and of LOCKED, at the
     same time relative to the change of the selector, and the end state.
  4. The three new codes 1000, 1001, 1010: the written registers decode
     (doc/dev-ntsc/tools/w2_checks.py) to the multiplier, dividers and pixel
     clocks of SPEC 4.2, and the table words of the file are the words of the
     generator doc/dev-hdmi-raw/tools/mmcm_tables.py.
  5. The codes 1011 to 1111 load exactly the table of 0010 (the same DRP
     accesses at the same addresses, the same written values, the same reset
     and lock events, all at the same times as in the step of 0010; only the
     values that the reads return differ, because they are what the step
     before wrote) and the loader returns to IDLE; the change from 1111 to
     0001 loads 0001 in the same way as the first change to 0001.

Prints "RESULT: PASS" or "RESULT: FAIL ...".
"""

import importlib.util
import os
import re
import sys
from fractions import Fraction

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("  MISMATCH: " + what)


def load_module(name, path):
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def parse_log(path):
    """Return (pre-events, steps, done, errors). A step: dict code, t0, events, done."""
    pre, steps, errors, done = [], [], [], False
    for line in open(path, errors="replace"):
        line = line.strip()
        if line == "SIMULATION DONE":
            done = True
            continue
        m = re.match(r"LOG (\d+) (\w+)\s*(.*)$", line)
        if not m:
            continue
        t, kind, args = int(m.group(1)), m.group(2), m.group(3).replace("'", "").split()
        if kind == "ERROR":
            errors.append(line)
        elif kind == "SEL":
            steps.append({"code": args[0], "t0": t, "events": [], "done": None})
        elif kind == "DONE":
            steps[-1]["done"] = (args[1], int(args[2]), t - steps[-1]["t0"])
        elif steps:
            steps[-1]["events"].append((t - steps[-1]["t0"], kind, tuple(args)))
        else:
            pre.append((t, kind, tuple(args)))
    return pre, steps, done, errors


def drp(step):
    """The DRP accesses of a step without times: [(kind, address, data)]."""
    return [(k, a[0], a[1]) for _, k, a in step["events"] if k in ("RD", "WR")]


def tables_of(mt, vhdl):
    """{code (int): rows [(daddr, data, mask)]} of every table in the file (9-bit table address / 32)."""
    out = {}
    for t in mt.parse_vhdl(vhdl):
        out[t["base"] >> 5] = [(r[1] & 0x7F, r[2], r[3]) for r in t["rows"]]
    return out


def no_read_data(step):
    """The events of a step without the data of the DRP reads: a read returns what the
    previous load wrote, which depends on the step before."""
    return [(t, k, a[:1] if k == "RD" else a) for t, k, a in step["events"]]


def table_code(code, width):
    """The table that a selector code loads (tbl_sel of the 4-bit file)."""
    c = int(code, 2)
    return 2 if width == 4 and c > 10 else c


def check_step(name, step, rows):
    d = step["done"]
    check(d is not None and d[0] == "0" and d[1] == 13000,
          "%s: at the end of the step rsto = %s, clko period %s ps (loader not back in IDLE)" % (
              name, d and d[0], d and d[1]))
    acc = drp(step)
    wr = [x for x in acc if x[0] == "WR"]
    check(len(wr) == len(rows) == 23, "%s: %d DRP writes, table has %d rows" % (name, len(wr), len(rows)))
    check(len(acc) == 2 * len(rows), "%s: %d DRP accesses" % (name, len(acc)))
    for i, (daddr, data, mask) in enumerate(rows):
        if 2 * i + 1 >= len(acc):
            break
        rd, w = acc[2 * i], acc[2 * i + 1]
        exp = (int(rd[2], 16) & mask) | (data & ~mask & 0xFFFF)
        check(rd[0] == "RD" and w[0] == "WR" and int(rd[1], 16) == daddr and int(w[1], 16) == daddr and
              int(w[2], 16) == exp,
              "%s row %d: %s / %s, expected RD/WR of %02X with %04X" % (name, i, rd, w, daddr, exp))


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        return 2
    old_log, old_vhdl, new_log, new_vhdl, repo = sys.argv[1:6]
    w2 = load_module("w2_checks", os.path.join(repo, "doc", "dev-ntsc", "tools", "w2_checks.py"))
    mt = load_module("mmcm_tables", os.path.join(repo, "doc", "dev-hdmi-raw", "tools", "mmcm_tables.py"))

    old_pre, old, old_done, old_err = parse_log(old_log)
    new_pre, new, new_done, new_err = parse_log(new_log)
    print("old run: %d steps (%s), new run: %d steps (%s)" % (
        len(old), " ".join(s["code"] for s in old), len(new), " ".join(s["code"] for s in new)))
    check(old_done and new_done, "a run did not finish")
    check(not old_err and not new_err, "ERROR lines: %s" % (old_err + new_err)[:4])
    check(len(old) == 9 and len(new) == 18, "unexpected number of steps")

    # 2. every step against the table of its file
    old_tbl, new_tbl = tables_of(mt, old_vhdl), tables_of(mt, new_vhdl)
    check(sorted(old_tbl) == list(range(8)), "old file: tables %s" % sorted(old_tbl))
    check(sorted(new_tbl) == list(range(11)), "new file: tables %s" % sorted(new_tbl))
    for i, s in enumerate(old):
        check_step("old step %d (%s)" % (i, s["code"]), s, old_tbl[table_code(s["code"], 3)])
    for i, s in enumerate(new):
        check_step("new step %d (%s)" % (i, s["code"]), s, new_tbl[table_code(s["code"], 4)])
    print("every step: 23 read-modify-writes in table order with the table data of its code, loader back in IDLE")

    # 3. old versus new for the power-on and the eight old codes
    check(old_pre == new_pre, "events before the first selector change differ")
    n_events = 0
    for i in range(min(9, len(old), len(new))):
        o, n = old[i], new[i]
        same = ("0" + o["code"] == n["code"] and o["t0"] == n["t0"] and o["events"] == n["events"]
                and o["done"] == n["done"])
        n_events += len(o["events"])
        check(same, "step %d: old %s and new %s differ" % (i, o["code"], n["code"]))
        print("  step %d: old %s / new %s: %d events (DRP accesses, reset, lock) %s" % (
            i, o["code"], n["code"], len(o["events"]), "identical" if same else "DIFFER"))
    print("old codes: %d events compared, %s" % (n_events, "all identical" if not FAILS else "see above"))

    # 4. the new tables: decode of the written registers, generator words
    spec = {"1000": ("33.5", 3, 3, 15, Fraction(100 * 67, 90)),
            "1001": ("28.375", 3, 7, 35, Fraction(100 * 227, 840)),
            "1010": ("29.625", 4, 2, 10, Fraction(100 * 237, 320))}
    for s in new:
        if s["code"] not in spec:
            continue
        m_, d_, o0_, o1_, f_ = spec[s["code"]]
        regs = {int(a, 16): int(v, 16) for k, a, v in drp(s) if k == "WR"}
        try:
            m, d, o0, o1, f = w2.mmcm_freq(regs)
        except (KeyError, ValueError) as e:
            check(False, "code %s: the written registers do not decode (%s)" % (s["code"], e))
            continue
        good = (Fraction(m) == Fraction(m_) and d == d_ and o0 == o0_ and o1 == o1_ and
                Fraction(100) * Fraction(m) / d / Fraction(o1) == f_)
        check(good, "code %s decodes to M %s D %s O0 %s O1 %s" % (s["code"], m, d, o0, o1))
        gen = [(a, data, mask) for a, data, mask in mt.table(m_, d_, o0_, o1_, "m2m")]
        check(gen == new_tbl[int(s["code"], 2)], "code %s: the table of the file is not the generator's" % s["code"])
        print("code %s: written registers decode to M %.3f D %d O0 %g O1 %g -> pixel clock %.6f MHz "
              "(SPEC 4.2: %.6f MHz), serializer %.4f MHz; table = generator: %s" % (
                  s["code"], m, d, o0, o1, f, float(f_), f * o1 / o0,
                  "yes" if gen == new_tbl[int(s["code"], 2)] else "NO"))

    # 5. codes without a table and the way back
    ref = new[3]                         # the second load of 0010 (the first one is the power-on)
    check(ref["code"] == "0010", "step 3 is not 0010")
    for s in new:
        if s["code"] in ("1011", "1100", "1101", "1110", "1111"):
            same = no_read_data(s) == no_read_data(ref) and s["done"] == ref["done"]
            check(same, "code %s does not load exactly like 0010" % s["code"])
            print("code %s: %d events, identical to the load of 0010 (except read data): %s; end: rsto %s, clko %s ps" % (
                s["code"], len(s["events"]), "yes" if same else "NO", s["done"][0], s["done"][1]))
    last, first = new[-1], new[2]
    same = (last["code"] == first["code"] == "0001" and no_read_data(last) == no_read_data(first)
            and last["done"] == first["done"])
    check(same, "the change from 1111 to 0001 does not load 0001 as before")
    print("1111 -> 0001: %d events, identical to the first load of 0001 (except read data): %s" % (
        len(last["events"]), "yes" if same else "NO"))

    if FAILS:
        print("RESULT: FAIL %d mismatch(es)" % len(FAILS))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
