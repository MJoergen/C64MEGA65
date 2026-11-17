#!/usr/bin/env python3
"""
The on-screen menu window of video RAM dumps (vram_*.txt of a run) as text.

    osmtext.py DUMP [DUMP ...]      every row of the menu window
    osmtext.py --summary RUN_DIR    one line per dump, in the order of events.log

Characters: '*' is the selection mark of a radio item (character 7); a selected
single-select item shows its own mark '=' (M2M$OPT_SEL_SINGLE); '+' is any other
character that is not printable (frame and separator lines); '>' in front of a row
means that the row is highlighted (the cursor).

The summary gives the title of the window, the row and text of the cursor, all text
lines of the window, and "LEFT OVER" with the rows that should be blank but are not:
below the last text row of a window only one separator line and then blank rows may
follow. A text line that a redraw left behind shows up in the list of text lines.
"""
import os
import re
import sys


def window(path):
    """Returns (osm flag, header, rows): rows = list of (text, highlighted) of the menu window."""
    lines = open(path).read().split("\n")
    words = [int(x, 16) for l in lines[1:] for x in l.split()]
    m = re.search(r"osm='(\d)' xy=([0-9A-F]{2})([0-9A-F]{2}) dxdy=([0-9A-F]{2})([0-9A-F]{2})", lines[0])
    osm = m.group(1)
    x0, y0, dx, dy = (int(m.group(i), 16) for i in range(2, 6))
    rows = []
    for y in range(y0, y0 + dy):
        row = words[y * 45:(y + 1) * 45][x0:x0 + dx]
        text = "".join("*" if (v & 0xFF) == 7 else (chr(v & 0xFF) if 32 <= (v & 0xFF) < 127 else ("+" if v & 0xFF else " "))
                       for v in row)
        rows.append((text, any((v >> 8) & 0xF0 for v in row[1:-1])))
    return osm, lines[0], rows


def show(path):
    osm, header, rows = window(path)
    print("== %s %s" % (os.path.basename(path), header))
    for y, (text, hl) in enumerate(rows):
        print("%2d %s %s" % (y, ">" if hl else " ", text))


def summary(run):
    for name in re.findall(r"^\S+ dump (\S+)", open(os.path.join(run, "events.log")).read(), re.M):
        osm, _, rows = window(os.path.join(run, "vram_%s.txt" % name))
        if osm != "1":
            print("%-22s (menu not shown)" % name)
            continue
        inner = [t[1:-1] for t, _ in rows]
        is_text = [bool(re.search(r"[A-Za-z0-9]", t)) for t in inner]
        is_sep = [set(t) == {"+"} for t in inner]
        last = max(i for i in range(len(inner) - 1) if is_text[i])
        left = []
        for i in range(last + 1, len(inner) - 1):
            if is_sep[i] and i == last + 1:
                continue
            if inner[i].strip():
                left.append(i)
        cur = [i for i, (_, hl) in enumerate(rows) if hl]
        items = [inner[i].rstrip() for i in range(2, last + 1) if is_text[i]]
        print("%-22s %-18s cursor %-3s %-22s | %s%s" % (
            name, inner[1].strip(), cur[0] if cur else "-", inner[cur[0]].strip() if cur else "-",
            " | ".join(items), "   LEFT OVER rows %s" % left if left else ""))


if __name__ == "__main__":
    if sys.argv[1] == "--summary":
        summary(sys.argv[2])
    else:
        for p in sys.argv[1:]:
            show(p)
