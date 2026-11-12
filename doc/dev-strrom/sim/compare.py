#!/usr/bin/env python3
"""
Compare two runs of the same scenario (qsys_tb.vhd / sim.py), normally the old
firmware (strings in the firmware ROM) against the new one (string ROM).

    compare.py RUN_A RUN_B [--report FILE] [--strict-reads] [--prefix]

Everything that the firmware does to the outside world is compared:

    uart.log     the decoded UART output, byte by byte
    vram_*.txt   the video RAM at each checkpoint, cell by cell, plus the OSM
                 registers and the selected device and window at that moment
                 (while the firmware polls a device in a wait loop, the window
                 at the instant of the dump depends on the timing: reported,
                 but not counted as a difference)
    regs.log     the sequence of register values at the ports of the wrapper
    win.log      the sequence of write accesses through the 4k MMIO window, and
                 the sequence of read accesses without the string ROM (device
                 0x0007), which only the new firmware reads
    sd.log       the sequence of SD card commands
    spy.log      (runs with the CPU spy) stack pointer and register bank balance
    events.log   the script must have run in the same way (no timeouts)

Time stamps are not compared: the two firmwares need a different number of
clock cycles for the same job.

Known and accepted differences, all in the UART log (ACCEPTED below). They are
replaced by a placeholder on both sides before the comparison and reported:

    * the number that follows "Free space in QNICE ROM:" (the ROM got smaller)
    * the two code addresses that the firmware prints when it enters the debug
      mode ("press C R xxxx"), and the echo of the address that the script
      types into the QNICE Monitor to return ("RUN ADDRESS=xxxx"): the code
      moved inside the ROM

Read accesses of the devices that the firmware polls in its wait loops (POLLED
below) differ in the number of repetitions. The complete access sequence is
therefore compared after immediate repetitions of blocks of up to 64 accesses
were collapsed on both sides, unless --strict-reads is given. Write accesses
and the read accesses of all other devices are compared as they are.

Exit code 0: no difference apart from the accepted one. Exit code 1: differences.
"""

import argparse
import glob
import os
import re
import sys

ACCEPTED = [
    ("free ROM space", re.compile(rb"(Free space in QNICE ROM: +)(\d+)")),
    ("debug mode address", re.compile(rb"(press C R )([0-9A-F]{4})")),
    ("monitor run address", re.compile(rb"(RUN ADDRESS=)([0-9A-F]{4})")),
]


class Report:
    def __init__(self):
        self.lines = []
        self.diffs = 0

    def say(self, text=""):
        self.lines.append(text)

    def diff(self, text):
        self.diffs += 1
        self.lines.append("DIFFERENCE: " + text)


def read_lines(path):
    if not os.path.exists(path):
        return None
    with open(path, errors="replace") as f:
        lines = [l.rstrip("\n") for l in f]
    if SNAPSHOT and lines:
        lines = lines[:-1]      # a run that is still going on: the last line may be incomplete
    return lines


def uart_bytes(run):
    lines = read_lines(os.path.join(run, "uart.log"))
    if lines is None:
        return None, 0
    data = bytearray()
    framing = 0
    for l in lines:
        parts = l.split()
        if len(parts) >= 2:
            data.append(int(parts[1], 16))
        if "FRAMING_ERROR" in l:
            framing += 1
    return bytes(data), framing


def printable(b):
    return "".join(chr(c) if 32 <= c < 127 else ("\\n" if c == 10 else "\\r" if c == 13 else "\\x%02X" % c)
                   for c in b)


def strip_time(lines):
    return [l.split(" ", 1)[1] if " " in l else l for l in lines]


def first_mismatch(a, b):
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return n if len(a) != len(b) else -1


def collapse(seq, maxp=64):
    """
    Removes immediate repetitions of blocks of up to maxp elements: a polling
    loop that runs n times leaves the same trace as one that runs once.
    """
    out = []
    for x in seq:
        out.append(x)
        again = True
        while again:
            again = False
            n = len(out)
            last = out[-1]
            for p in range(1, min(maxp, n // 2) + 1):
                if out[n - 1 - p] == last and out[n - p:] == out[n - 2 * p:n - p]:
                    del out[n - p:]
                    again = True
                    break
    return out


def compare_uart(a, b, rep, prefix=False):
    da, fa = uart_bytes(a)
    db, fb = uart_bytes(b)
    if da is None or db is None:
        rep.diff("uart.log is missing")
        return
    rep.say("UART: %d bytes (A), %d bytes (B)" % (len(da), len(db)))
    if fa or fb:
        rep.diff("UART framing errors: A %d, B %d" % (fa, fb))
    ta, tb = da, db
    accepted = False
    for name, rx in ACCEPTED:
        na = [m.group(2).decode() for m in rx.finditer(ta)]
        nb = [m.group(2).decode() for m in rx.finditer(tb)]
        if na != nb:
            accepted = True
            rep.say("UART: accepted difference '%s': A %s, B %s" % (name, ",".join(na) or "-", ",".join(nb) or "-"))
        ta = rx.sub(rb"\1<N>", ta)
        tb = rx.sub(rb"\1<N>", tb)
    if prefix:
        tb = tb[:len(ta)]
    if SNAPSHOT:
        n = min(len(ta), len(tb))
        ta, tb = ta[:n], tb[:n]
        rep.say("UART: the first %d bytes (after normalization) are compared" % n)
    i = first_mismatch(ta, tb)
    if i < 0:
        rep.say("UART: identical" + (" apart from the accepted differences" if accepted else ""))
    else:
        rep.diff("UART output differs at byte %d (after normalization)" % i)
        rep.say("   A: ..." + printable(ta[max(0, i - 60):i]) + " >>> " + printable(ta[i:i + 80]))
        rep.say("   B: ..." + printable(tb[max(0, i - 60):i]) + " >>> " + printable(tb[i:i + 80]))


def parse_dump(path):
    lines = read_lines(path)
    head = dict(kv.split("=", 1) for kv in lines[0].split() if "=" in kv)
    words = []
    for l in lines[1:]:
        words += [int(w, 16) for w in l.split()]
    return head, words


def render(words, cols, rows):
    out = []
    for y in range(rows):
        row = words[y * cols:(y + 1) * cols]
        out.append("".join(chr(w & 0xFF) if 32 <= (w & 0xFF) < 127 else ("." if (w & 0xFF) else " ")
                           for w in row))
    return out


_POLLED_WINDOWS = {}


def polled_windows(run, dev):
    """Windows (as 4 hex digits) of the read accesses of a device in a run."""
    if (run, dev) not in _POLLED_WINDOWS:
        wins = set()
        for l in read_lines(os.path.join(run, "win.log")) or []:
            if l.startswith("R " + dev + " "):
                wins.add(l.split()[2][:4])
        _POLLED_WINDOWS[(run, dev)] = wins
    return _POLLED_WINDOWS[(run, dev)]


def compare_vram(a, b, rep, cols=45, rows=33, prefix=False):
    fa = sorted(os.path.basename(p) for p in glob.glob(os.path.join(a, "vram_*.txt")))
    fb = sorted(os.path.basename(p) for p in glob.glob(os.path.join(b, "vram_*.txt")))
    if prefix:
        fb = [n for n in fb if n in fa]
    if SNAPSHOT:
        fa, fb = [n for n in fa if n in fb], [n for n in fb if n in fa]
    if fa != fb:
        rep.diff("different sets of video RAM dumps: A %s, B %s" % (fa, fb))
    for name in [n for n in fa if n in fb]:
        ha, wa = parse_dump(os.path.join(a, name))
        hb, wb = parse_dump(os.path.join(b, name))
        tag = name[5:-4]
        regs = ["osm", "xy", "dxdy", "dev", "win"]
        same = [k for k in regs if ha.get(k) == hb.get(k)]
        if len(same) == 4 and "win" not in same and ha.get("dev") in POLLED and \
                {ha.get("win"), hb.get("win")} <= polled_windows(a, ha.get("dev")) & polled_windows(b, ha.get("dev")):
            # The firmware is in a wait loop that polls this device and selects its windows
            # in turn: the window at the instant of the dump is a matter of timing.
            rep.say("checkpoint %s: selected window A %s, B %s while both sides poll device %s "
                    "(the polling loops of both sides read these windows in turn): sampling instant" %
                    (tag, ha.get("win"), hb.get("win"), ha.get("dev")))
        elif len(same) != len(regs):
            rep.diff("checkpoint %s: registers differ: A %s, B %s" %
                     (tag, {k: ha.get(k) for k in regs}, {k: hb.get(k) for k in regs}))
        cells = [i for i in range(max(len(wa), len(wb)))
                 if (wa[i] if i < len(wa) else None) != (wb[i] if i < len(wb) else None)]
        nonzero = sum(1 for w in wa if w)
        if not cells:
            rep.say("VRAM %-12s identical (%d cells, %d not zero; osm=%s xy=%s dxdy=%s dev=%s win=%s)" %
                    (tag, len(wa), nonzero, ha.get("osm"), ha.get("xy"), ha.get("dxdy"), ha.get("dev"),
                     ha.get("win")))
        else:
            rep.diff("checkpoint %s: %d video RAM cells differ, first at x=%d y=%d: A %04X, B %04X" %
                     (tag, len(cells), cells[0] % cols, cells[0] // cols, wa[cells[0]], wb[cells[0]]))
            ra, rb = render(wa, cols, rows), render(wb, cols, rows)
            for y in sorted(set(c // cols for c in cells))[:12]:
                if y < rows:
                    rep.say("   row %2d A: |%s|" % (y, ra[y]))
                    rep.say("   row %2d B: |%s|" % (y, rb[y]))


PREFIX = False                  # B may be longer than A (A is the first part of the scenario of B)
SNAPSHOT = False                # both runs are still going on: compare the common first part


def compare_seq(name, sa, sb, rep, what):
    if PREFIX:
        sb = sb[:len(sa)]
    if SNAPSHOT:
        n = min(len(sa), len(sb))
        sa, sb = sa[:n], sb[:n]
    i = first_mismatch(sa, sb)
    if i < 0:
        rep.say("%s: %s identical (%d entries)" % (name, what, len(sa)))
        return True
    rep.diff("%s: %s differ at entry %d (A has %d, B has %d entries)" % (name, what, i, len(sa), len(sb)))
    for k in range(max(0, i - 3), min(max(len(sa), len(sb)), i + 4)):
        rep.say("   %6d  A: %-40s B: %s" % (k, sa[k] if k < len(sa) else "-", sb[k] if k < len(sb) else "-"))
    return False


# Devices that the firmware polls in its wait loops: the number of polls depends on the
# time that the firmware spends in a loop, which is not the same for the two firmwares.
POLLED = ("0101", "0103", "0104", "0108")


def compare_win(a, b, rep, strict):
    la = read_lines(os.path.join(a, "win.log"))
    lb = read_lines(os.path.join(b, "win.log"))
    if la is None or lb is None:
        rep.diff("win.log is missing")
        return
    wa = [l for l in la if l.startswith("W")]
    wb = [l for l in lb if l.startswith("W")]
    compare_seq("4k window", wa, wb, rep, "write accesses")
    sa = sum(1 for l in la if l.startswith("R 0007"))
    sb = sum(1 for l in lb if l.startswith("R 0007"))
    rep.say("4k window: read accesses of the string ROM (device 0007): A %d, B %d" % (sa, sb))
    # reads of the devices that are not polled: exactly the same sequence
    ra = [l for l in la if l.startswith("R") and l[2:6] != "0007" and l[2:6] not in POLLED]
    rb = [l for l in lb if l.startswith("R") and l[2:6] != "0007" and l[2:6] not in POLLED]
    compare_seq("4k window", ra, rb, rep, "read accesses of the devices that are not polled")
    # everything without the string ROM, reads and writes interleaved
    xa = [l for l in la if not l.startswith("R 0007")]
    xb = [l for l in lb if not l.startswith("R 0007")]
    if (xb[:len(xa)] if PREFIX else xb) == xa:
        rep.say("4k window: complete access sequence without the string ROM (reads and writes "
                "interleaved) identical (%d entries)" % len(xa))
    elif strict:
        compare_seq("4k window", xa, xb, rep, "complete access sequence without the string ROM")
    else:
        ca, cb = collapse(xa), collapse(xb)
        if SNAPSHOT:
            # the end of the collapsed sequence depends on where the snapshot cut a polling loop
            n = max(0, min(len(ca), len(cb)) - 200)
            ca, cb = ca[:n], cb[:n]
        rep.say("4k window: complete access sequence without the string ROM: A %d, B %d entries; the "
                "polled devices %s are read a different number of times; with repeated polls "
                "collapsed: A %d, B %d entries" % (len(xa), len(xb), "/".join(POLLED), len(ca), len(cb)))
        # A run ends at an arbitrary point of the last polling loop: one side may show the
        # beginning of one more pass of the loop, which is made of reads of the polled devices only.
        n = min(len(ca), len(cb))
        extra = (ca if len(ca) > len(cb) else cb)[n:]
        if not SNAPSHOT and extra and ca[:n] == cb[:n] and all(l.startswith("R") and l[2:6] in POLLED for l in extra):
            rep.say("4k window: complete access sequence (repeated polls collapsed) identical (%d entries); "
                    "side %s ends %d read(s) further into its last polling loop: %s" %
                    (n, "A" if len(ca) > len(cb) else "B", len(extra), ", ".join(extra[:6])))
        else:
            compare_seq("4k window", ca, cb, rep, "complete access sequence (repeated polls collapsed)")


def compare_simple(a, b, rep, fname, title):
    la = read_lines(os.path.join(a, fname))
    lb = read_lines(os.path.join(b, fname))
    if la is None and lb is None:
        return
    if la is None or lb is None:
        rep.diff("%s exists only on one side" % fname)
        return
    compare_seq(title, strip_time(la), strip_time(lb), rep, "sequence")


def compare_events(a, b, rep):
    la = read_lines(os.path.join(a, "events.log"))
    lb = read_lines(os.path.join(b, "events.log"))
    if la is None or lb is None:
        rep.diff("events.log is missing")
        return
    for side, lines in (("A", la), ("B", lb)):
        # messages of the script interpreter start with the keyword; a text that a wait_uart
        # waits for may contain the same word ("ERROR #")
        bad = [l for l in lines if re.match(r"^\S+ (TIMEOUT|ERROR)\b", l)]
        for l in bad:
            rep.diff("script problem on side %s: %s" % (side, l))
        if not SNAPSHOT and (not lines or "end of script" not in lines[-1]):
            rep.diff("the script did not run to its end on side %s" % side)
    # durations differ, and the device and window of a dump are compared with the dump itself
    norm = lambda ls: [re.sub(r" dev=\w+ win=\w+$", "", re.sub(r"(after|reaction after) \d+ us", r"\1 <t> us", l))
                       for l in strip_time(ls) if not (PREFIX and "end of script" in l)]
    compare_seq("script", norm(la), norm(lb), rep, "events")
    ta = float(la[-1].split()[0]) if la else 0
    tb = float(lb[-1].split()[0]) if lb else 0
    rep.say("simulated time: A %.3f ms, B %.3f ms (B - A = %+.3f ms)" % (ta / 1e3, tb / 1e3, (tb - ta) / 1e3))


def compare_spy(a, b, rep):
    """
    spy.log (nvc runs only): at each checkpoint the highest stack pointer and the
    lowest register bank since the checkpoint before must be the same on both
    sides (stack and register bank balance). The lowest stack pointer and the
    highest register bank show the additional stack and bank depth of side B.
    """
    la = read_lines(os.path.join(a, "spy.log"))
    lb = read_lines(os.path.join(b, "spy.log"))
    if la is None or lb is None:
        rep.say("CPU spy: no spy.log on %s" % ("both sides" if la is None and lb is None else "one side"))
        return

    def parse(lines):
        res = []
        for l in lines:
            p = l.split()
            res.append((p[1], dict(kv.split("=") for kv in p[2:])))
        return res
    pa, pb = parse(la), parse(lb)
    if PREFIX:
        pb = pb[:len(pa)]
    if SNAPSHOT:
        n = min(len(pa), len(pb))
        pa, pb = pa[:n], pb[:n]
    if [x[0] for x in pa] != [x[0] for x in pb]:
        rep.diff("CPU spy: different checkpoints")
        return
    worst_sp = worst_bank = 0
    bad = 0
    for (tag, va), (_, vb) in zip(pa, pb):
        if va["sp_max"] != vb["sp_max"] or va["bank_min"] != vb["bank_min"]:
            bad += 1
            rep.diff("CPU spy: checkpoint %s: highest stack pointer A %s, B %s; lowest register bank A %s, B %s" %
                     (tag, va["sp_max"], vb["sp_max"], va["bank_min"], vb["bank_min"]))
        worst_sp = max(worst_sp, int(va["sp_min"], 16) - int(vb["sp_min"], 16))
        worst_bank = max(worst_bank, int(vb["bank_max"], 16) - int(va["bank_max"], 16))
    if not bad:
        rep.say("CPU spy: highest stack pointer and lowest register bank identical at all %d checkpoints; "
                "B needs at most %d more stack words and %d more register banks than A" %
                (len(pa), worst_sp, worst_bank))


def compare_runs(a, b, strict=False, prefix=False, snapshot=False):
    global PREFIX, SNAPSHOT
    PREFIX = prefix
    SNAPSHOT = snapshot
    rep = Report()
    rep.say("A = " + a)
    rep.say("B = " + b)
    if prefix:
        rep.say("prefix mode: B is compared up to the end of A")
    if snapshot:
        rep.say("snapshot mode: the runs are not complete; the common first part of each log is compared")
    compare_events(a, b, rep)
    compare_uart(a, b, rep, prefix)
    compare_vram(a, b, rep, prefix=prefix)
    compare_simple(a, b, rep, "regs.log", "port registers")
    compare_win(a, b, rep, strict)
    compare_simple(a, b, rep, "sd.log", "SD card commands")
    compare_spy(a, b, rep)
    rep.say()
    rep.say("RESULT: %s" % ("no difference apart from the accepted one" if rep.diffs == 0
                            else "%d DIFFERENCE(S)" % rep.diffs))
    return rep


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run_a")
    ap.add_argument("run_b")
    ap.add_argument("--report")
    ap.add_argument("--strict-reads", action="store_true")
    ap.add_argument("--prefix", action="store_true",
                    help="B ran a longer script that starts with the script of A")
    ap.add_argument("--snapshot", action="store_true",
                    help="both runs are incomplete: compare the common first part of each log")
    args = ap.parse_args()
    rep = compare_runs(args.run_a, args.run_b, args.strict_reads, args.prefix, args.snapshot)
    text = "\n".join(rep.lines) + "\n"
    sys.stdout.write(text)
    if args.report:
        with open(args.report, "w") as f:
            f.write(text)
    return 1 if rep.diffs else 0


if __name__ == "__main__":
    sys.exit(main())
