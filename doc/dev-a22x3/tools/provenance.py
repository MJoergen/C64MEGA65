#!/usr/bin/env python3
"""Line provenance audit of a multi-branch merge.

Usage: provenance.py <base> <mainline-before> <final> <branch> [<branch> ...]

All branches start at <base>. <mainline-before> is the mainline before the
merges (it may contain changes of its own relative to <base>). For every file
that a branch or the merge touched, the script counts every distinct line and
compares the count in <final> with the additive expectation

    count(mainline-before) + sum over branches (count(branch) - count(base))

Every line whose count differs is printed: these are exactly the places where
a conflict was resolved by hand (or where a merge lost or duplicated a line).
The order of lines is not checked.
"""
import collections
import os
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))


def git(*args):
    return subprocess.run(["git", "-C", REPO] + list(args), stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False)


def files_changed(a, b):
    r = git("diff", "--name-only", "--no-renames", a, b)
    return set(l for l in r.stdout.decode().splitlines() if l)


def content(rev, path):
    r = git("show", "%s:%s" % (rev, path))
    if r.returncode != 0:
        return None
    return r.stdout


def counts(blob):
    c = collections.Counter()
    if blob is None:
        return c
    try:
        text = blob.decode("utf-8")
    except UnicodeDecodeError:
        text = blob.decode("latin-1")
    for l in text.split("\n"):
        c[l.rstrip("\r")] += 1
    return c


def main():
    base, before, final = sys.argv[1:4]
    branches = sys.argv[4:]
    files = files_changed(before, final)
    for b in branches:
        files |= files_changed(base, b)
    total_dev = 0
    files_with_dev = 0
    identical_new = 0
    for f in sorted(files):
        cb = content(base, f)
        blobs = [content(b, f) for b in branches]
        cd = content(before, f)
        cf = content(final, f)
        # binary files: compare whole blobs
        if any(x is not None and b"\0" in x for x in [cb, cd, cf] + blobs):
            srcs = [n for n, x in zip(branches, blobs) if x == cf]
            print("BINARY %s: final equals %s" % (f, srcs or ("before" if cd == cf else "NOTHING")))
            continue
        exp = counts(cd)
        kb = counts(cb)
        for x in blobs:
            kx = counts(x)
            for l in set(kx) | set(kb):
                d = kx[l] - kb[l]
                if d:
                    exp[l] += d
        kf = counts(cf)
        dev = []
        for l in set(exp) | set(kf):
            d = kf[l] - exp[l]
            if d:
                dev.append((d, l))
        if not dev:
            if cd is None:
                identical_new += 1
            continue
        files_with_dev += 1
        total_dev += len(dev)
        print("=== %s: %d deviating line(s)" % (f, len(dev)))
        for d, l in sorted(dev, key=lambda t: (t[0] > 0, t[1])):
            print("  %+d | %s" % (d, l))
    print("SUMMARY: %d files examined, %d with deviations, %d deviating distinct lines"
          % (len(files), files_with_dev, total_dev))


if __name__ == "__main__":
    main()
