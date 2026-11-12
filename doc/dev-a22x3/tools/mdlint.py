#!/usr/bin/env python3
"""Marked 2 / MathJax lint for the Markdown lines that a range of commits adds.

Usage: mdlint.py <from> <to>

Checks every line that <from>..<to> adds to a .md file (outside of fenced code
blocks and inline code spans) for: two or more bare dollar signs on one line
(inline math), a bare "==" (highlight extension), "$$", "\\(" or "\\[", and
angle-bracket placeholders. Lines that existed before are not reported.
"""
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def git(*a):
    return subprocess.run(["git", "-C", REPO] + list(a), stdout=subprocess.PIPE, check=True).stdout.decode("utf-8", "replace")


def prose_lines(text):
    """yield (lineno, line with inline code removed) for lines outside fences"""
    fence = None
    for n, l in enumerate(text.split("\n"), 1):
        m = re.match(r"\s*(```+|~~~+)", l)
        if m:
            if fence is None:
                fence = m.group(1)[0]
            elif m.group(1)[0] == fence:
                fence = None
            continue
        if fence is not None:
            continue
        if re.match(r"(    |\t)", l) and not re.match(r"\s*([-*+]|\d+\.)\s", l):
            # indented code block (rough): skip
            continue
        s = re.sub(r"(`+)(.+?)\1", "", l)
        yield n, l, s


def main():
    a, b = sys.argv[1:3]
    files = [f for f in git("diff", "--name-only", a, b).splitlines() if f.endswith(".md")]
    total = 0
    for f in files:
        try:
            new = git("show", "%s:%s" % (b, f))
        except subprocess.CalledProcessError:
            continue
        added = set()
        for l in git("diff", "-U0", a, b, "--", f).splitlines():
            if l.startswith("+") and not l.startswith("+++"):
                added.add(l[1:])
        for n, raw, s in prose_lines(new):
            if raw not in added:
                continue
            probs = []
            bare = len(re.findall(r"(?<!\\)\$", s))
            if bare >= 2:
                probs.append("%d bare $" % bare)
            if "$$" in s:
                probs.append("$$")
            if re.search(r"(?<!\\)==", s):
                probs.append("bare ==")
            if re.search(r"\\\(|\\\[", s):
                probs.append("\\( or \\[")
            if re.search(r"<[A-Za-z][A-Za-z0-9_ -]*>", s):
                probs.append("angle bracket placeholder")
            if probs:
                total += 1
                print("%s:%d: %s\n    %s" % (f, n, ", ".join(probs), raw[:160]))
    print("MDLINT: %d suspicious added line(s) in %d changed .md file(s)" % (total, len(files)))


if __name__ == "__main__":
    main()
