#!/usr/bin/env python3
"""
Static checks and coverage for the string ROM.

    strrom_tools.py check
        For every string that was moved into the string ROM: compare the
        characters in the string ROM (new build) with the characters that the
        old firmware ROM has at the label of the same name, and with the
        .ASCII_W/.ASCII_P lines between the markers of the sources. Also checks the
        table: every position inside the string ROM, no string across a 4096
        boundary, zero terminator present.

    strrom_tools.py coverage RUN [RUN ...]
        Which strings of the string ROM were read through the 4k MMIO window
        in the given runs of the new firmware (win.log of qsys_tb.vhd).

    strrom_tools.py seen RUN [RUN ...]
        Sanity check of the new firmware on its own: every string that a run
        read completely from the string ROM must show up in what the firmware
        put out in that run: either in the UART log or, line by line, in a
        video RAM dump. Strings that were read but are found nowhere are
        listed (a screen message can be gone before the next dump is taken).
        "check" proves that the string ROM holds the strings of the sources.

    strrom_tools.py dumpcheck RUN
        Scenario strdump: compares the memory dumps of the string ROM that the
        QNICE Monitor printed in the run with m2m-strings.rom.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCR = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
NEW_DIR = os.path.join(SCR, "wtA", "CORE", "m2m-rom")
OLD_DIR = os.path.join(SCR, "baseline")


def labels(lis):
    """Label list at the end of a qasm listing: name -> address."""
    res = {}
    inlist = False
    with open(lis, errors="replace") as f:
        for line in f:
            if line.startswith("Label-list:"):
                inlist = True
                continue
            if inlist:
                for m in re.finditer(r"(\S+)\s*:\s*0x([0-9A-Fa-f]{4})", line):
                    res[m.group(1)] = int(m.group(2), 16)
    return res


def out_words(out):
    """.out file of qasm: address -> word."""
    mem = {}
    with open(out) as f:
        for line in f:
            p = line.split()
            if len(p) == 2:
                mem[int(p[0], 16)] = int(p[1], 16)
    return mem


def strrom_bytes(path):
    with open(path) as f:
        return [int(l, 16) for l in f if l.strip()]


def table():
    """Handles of the new firmware: list of (label, handle address, position)."""
    lab = labels(os.path.join(NEW_DIR, "m2m-rom.lis"))
    mem = out_words(os.path.join(NEW_DIR, "m2m-rom.out"))
    lo, hi = lab["STRROM$TAB"], lab["STRROM$TAB_END"]
    res = [(n, a, mem[a]) for n, a in lab.items() if lo <= a < hi and n not in ("STRROM$TAB",)]
    res.sort(key=lambda t: t[1])
    return res, lo, hi


def zstr(mem_get, start, limit=5000):
    s = []
    for i in range(limit):
        c = mem_get(start + i)
        if c is None:
            return None
        if c == 0:
            return s
        s.append(c)
    return None


def check():
    tab, lo, hi = table()
    rom = strrom_bytes(os.path.join(NEW_DIR, "m2m-strings.rom"))
    old_lab = labels(os.path.join(OLD_DIR, "m2m-rom.lis"))
    old_mem = out_words(os.path.join(OLD_DIR, "m2m-rom.out"))
    src = source_strings()
    print("string ROM: %d characters; table 0x%04X..0x%04X: %d handles, %d table words" %
          (len(rom), lo, hi - 1, len(tab), hi - lo))
    bad = 0
    if len(tab) != hi - lo:
        # several labels can share one table word only if the tool emits one word per label
        print("NOTE: %d labels for %d table words" % (len(tab), hi - lo))
    used = 0
    for name, addr, pos in tab:
        new = zstr(lambda a: rom[a] if a < len(rom) else None, pos)
        if new is None:
            print("FAIL %-18s position 0x%04X: no terminator inside the string ROM" % (name, pos))
            bad += 1
            continue
        if pos // 4096 != (pos + len(new)) // 4096:
            print("FAIL %-18s position 0x%04X length %d crosses a 4096 boundary" % (name, pos, len(new)))
            bad += 1
        if name not in old_lab:
            print("FAIL %-18s is not a label of the old firmware" % name)
            bad += 1
            continue
        old = zstr(lambda a: old_mem.get(a), old_lab[name])
        if old is None or [c & 0xFF for c in old] != new or any(c > 0xFF for c in old):
            print("FAIL %-18s differs: old ROM 0x%04X %r, string ROM 0x%04X %r" %
                  (name, old_lab[name], old and "".join(map(chr, old))[:60], pos,
                   "".join(map(chr, new))[:60]))
            bad += 1
        if src.get(name) != new:
            print("FAIL %-18s differs from the source: source %r, string ROM %r" %
                  (name, src.get(name) and "".join(map(chr, src[name]))[:60], "".join(map(chr, new))[:60]))
            bad += 1
        used = max(used, pos + len(new) + 1)
    extra = sorted(set(src) - set(n for n, _, _ in tab))
    if extra:
        print("FAIL labels between the markers without a handle: %s" % extra)
        bad += 1
    print("highest used position: %d; labels between the markers of the sources: %d" % (used - 1, len(src)))
    print("STRROM CHECK: %s" % ("OK: all %d strings are identical to the strings of the old firmware ROM "
                                "and to the strings as written in the sources"
                                % len(tab) if bad == 0 else "%d FAILURES" % bad))
    return 1 if bad else 0


def coverage(runs):
    tab, lo, hi = table()
    rom = strrom_bytes(os.path.join(NEW_DIR, "m2m-strings.rom"))
    read = set()
    for run in runs:
        path = os.path.join(run, "win.log")
        with open(path) as f:
            for line in f:
                if line.startswith("R 0007 "):
                    read.add(int(line.split()[2], 16))
    full, partial, none = [], [], []
    for name, addr, pos in tab:
        s = zstr(lambda a: rom[a] if a < len(rom) else None, pos)
        want = set(range(pos, pos + len(s) + 1))
        got = want & read
        if got == want:
            full.append(name)
        elif got:
            partial.append("%s (%d of %d)" % (name, len(got), len(want)))
        else:
            none.append(name)
    stray = sorted(a for a in read if not any(pos <= a <= pos + len(zstr(lambda x: rom[x], pos))
                                              for _, _, pos in tab))
    print("string ROM coverage over %d run(s): %d of %d strings read completely, %d partly, %d not read" %
          (len(runs), len(full), len(tab), len(partial), len(none)))
    print("read completely: " + " ".join(full))
    print("read partly: " + (", ".join(partial) or "-"))
    print("not read: " + " ".join(none))
    print("reads outside of any string: %d %s" % (len(stray), ["0x%04X" % a for a in stray[:20]]))
    return 0


SOURCES = [
    ("M2M", "rom", "monitor", "qmon_m2m.asm"),
    ("M2M", "rom", "strings.asm"),
    ("M2M", "rom", "menu.asm"),
    ("CORE", "m2m-rom", "m2m-rom.asm"),
]


def source_strings():
    """
    The strings between the markers as the sources spell them: label -> list of
    character codes without the terminator. RELEASE is defined, RAM_MONITOR is
    not; "\\n" stands for CR LF.
    """
    res = {}
    for parts in SOURCES:
        data = []                                   # characters and terminators in source order
        labels = {}                                 # label -> index into data
        inside = False
        skip = []                                   # one entry per open #ifdef: True = skipped
        for line in open(os.path.join(SCR, "wtA", *parts), errors="replace"):
            s = line.rstrip("\n")
            if s.startswith(";STRROM_BEGIN"):
                inside = True
                continue
            if s.startswith(";STRROM_END"):
                inside = False
                continue
            if not inside:
                continue
            d = s.split()
            if d and d[0] in ("#ifdef", "#ifndef"):
                defined = d[1] == "RELEASE"
                skip.append(not defined if d[0] == "#ifdef" else defined)
                continue
            if d and d[0] == "#else":
                skip[-1] = not skip[-1]
                continue
            if d and d[0] == "#endif":
                skip.pop()
                continue
            if any(skip) or not d or d[0].startswith(";"):
                continue
            m = re.match(r'^([A-Za-z_$][A-Za-z0-9_$]*)?\s*(?:\.(ASCII_[WP])\s+"([^"]*)")?\s*(;.*)?$', s)
            if not m:
                sys.exit("FAIL: cannot parse a line between the markers of %s: %s" % (parts[-1], s))
            if m.group(1):
                labels[m.group(1)] = len(data)
            if m.group(2):
                data += [ord(c) for c in m.group(3).replace("\\n", "\r\n")]
                if m.group(2) == "ASCII_W":
                    data.append(0)
        for name, start in labels.items():
            res[name] = data[start:data.index(0, start)]
    return res


def seen(runs):
    tab, lo, hi = table()
    rom = strrom_bytes(os.path.join(NEW_DIR, "m2m-strings.rom"))
    bad = 0
    for run in runs:
        uart = b""
        with open(os.path.join(run, "uart.log")) as f:
            uart = bytes(int(l.split()[1], 16) for l in f if len(l.split()) >= 2)
        screens = []
        for name in sorted(os.listdir(run)):
            if name.startswith("vram_"):
                lines = open(os.path.join(run, name)).read().split("\n")
                words = []
                for l in lines[1:]:
                    words += [int(w, 16) & 0xFF for w in l.split()]
                screens.append(bytes(words))
        read = set()
        with open(os.path.join(run, "win.log")) as f:
            for line in f:
                if line.startswith("R 0007 "):
                    read.add(int(line.split()[2], 16))
        n_uart = n_screen = 0
        missing = []
        for name, addr, pos in tab:
            s = bytes(zstr(lambda a: rom[a] if a < len(rom) else None, pos))
            if not set(range(pos, pos + len(s) + 1)) <= read:
                continue
            if s in uart:
                n_uart += 1
                continue
            rows = [r for r in s.split(b"\r\n") if r.strip()]
            if rows and all(any(r in scr for scr in screens) for r in rows):
                n_screen += 1
                continue
            missing.append(name)
        print("%s: strings read completely: %d found in the UART log, %d found in a video RAM dump, "
              "%d found nowhere %s" % (os.path.basename(os.path.dirname(run)) + "/" + os.path.basename(run),
                                       n_uart, n_screen, len(missing), missing))
    return 0


def dumpcheck(run):
    """
    Scenario strdump: compares the memory dumps that the QNICE Monitor printed
    (device 0007 selected, window set with MC FFF5) with m2m-strings.rom.
    """
    rom = strrom_bytes(os.path.join(NEW_DIR, "m2m-strings.rom"))
    with open(os.path.join(run, "uart.log")) as f:
        text = bytes(int(l.split()[1], 16) for l in f if len(l.split()) >= 2).decode("latin1")
    window = None
    words = bad = 0
    seen_windows = set()
    for line in re.split(r"[\r\n]+", text):
        m = re.search(r"CHANGE ADDRESS=FFF5 CURRENT VALUE=[0-9A-F]{4} NEW VALUE=([0-9A-F]{4})", line)
        if m:
            window = int(m.group(1), 16)
            continue
        m = re.match(r"^([0-9A-F]{4}): ((?:[0-9A-F]{4} ?)+)$", line.strip())
        if m and window is not None:
            addr = int(m.group(1), 16)
            for k, w in enumerate(m.group(2).split()):
                pos = (window * 4096 + (addr + k - 0x7000)) % len(rom)
                words += 1
                seen_windows.add(window)
                if int(w, 16) != rom[pos]:
                    bad += 1
                    print("FAIL window %d address %04X: dump %s, string ROM position %d holds %02X" %
                          (window, addr + k, w, pos, rom[pos]))
    ex = re.findall(r"EXAMINE ADDRESS=(FFF[45]) ([0-9A-F]{4})", text)
    print("monitor examine after the dumps: %s" % ex)
    print("STRROM DUMP CHECK: %d words in windows %s compared with m2m-strings.rom: %s" %
          (words, sorted(seen_windows), "OK" if bad == 0 and words > 0 else "%d FAILURES" % bad))
    return 1 if bad or not words else 0


def main():
    if len(sys.argv) >= 2 and sys.argv[1] == "check":
        return check()
    if len(sys.argv) >= 3 and sys.argv[1] == "dumpcheck":
        return dumpcheck(sys.argv[2])
    if len(sys.argv) >= 3 and sys.argv[1] == "seen":
        return seen(sys.argv[2:])
    if len(sys.argv) >= 3 and sys.argv[1] == "coverage":
        return coverage(sys.argv[2:])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
