#!/usr/bin/env python3
"""Differential ghdl analysis: base revision versus working tree.

For every VHDL file given on the command line this script builds two
identical-in-shape ghdl libraries, one from the base revision (default HEAD)
and one from the working tree, analyzes the file into each, normalizes file
names, line and column numbers out of the diagnostics and compares the two
diagnostic multisets.

Seeding (done per side, each side from its own revision, so that an edit that
spans several files, for example a new constant in globals.vhd that main.vhd
uses, is checked consistently):

  1. Stub libraries unisim and xpm (doc/dev-ntsc/tools/stubs, shared, -P).
  2. Packages: qnice_tools, video_modes_pkg, types_pkg, globals and the
     package part of vdrives.vhd (vdrives_pkg).
  3. The entity declarations (context clause plus entity, no architecture)
     of every sub-entity that the file instantiates as "entity work.X" and
     that exists as VHDL in the repo. This lets ghdl check the port and
     generic maps of those instances against the real entity declarations.

Verdict per file:
  PASS  identical diagnostic multisets, zero "no declaration for" errors on
        both sides, and no vacuity marker (missing resource library, missing
        vcomponents, parse errors that stop analysis early).
  FAIL  anything else; the differing diagnostics are printed.

Usage: analyze.sh [--base REV] [-j N] [--keep] [--selftest] [-v] file.vhd ...
"""

import argparse
import collections
import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

GHDL = os.environ.get("GHDL", "/usr/local/bin/ghdl")
FLAGS = ["--std=08", "-frelaxed", "-fsynopsys"]

HERE = os.path.dirname(os.path.realpath(__file__))
REPO = os.path.realpath(os.path.join(HERE, "..", "..", ".."))
STUBS = [("unisim", os.path.join(HERE, "stubs", "unisim_vcomponents.vhd")),
         ("xpm", os.path.join(HERE, "stubs", "xpm_vcomponents.vhd"))]

# Seed packages, in dependency order. The last element optionally restricts
# the seed to one package of a file (by package name).
SEED_PACKAGES = [
    ("M2M/QNICE/vhdl/tools.vhd", None),
    ("M2M/vhdl/av_pipeline/video_modes_pkg.vhd", None),
    ("M2M/vhdl/controllers/HDMI/types_pkg.vhd", None),
    ("CORE/vhdl/globals.vhd", None),
    ("M2M/vhdl/vdrives.vhd", "vdrives_pkg"),
]

# Where to look for entity declarations of sub-entities (first match wins).
ENTITY_DIRS = ["CORE/vhdl", "M2M/vhdl", "CORE/C64_MiSTerMEGA65/rtl", "M2M/QNICE/vhdl"]
ENTITY_SKIP = re.compile(r"(/test/|/tests/|/sim/|/tb_|/testbench)", re.I)

RE_LOC = re.compile(r"^(?P<file>[^:\s]+\.vhdl?):(?P<line>\d+):(?P<col>\d+):\s*(?P<msg>.*)$")
RE_EMBED_LOC = re.compile(r"[\w./-]+\.vhdl?:\d+(:\d+)?")
RE_NODECL = re.compile(r"no declaration for", re.I)
RE_NOTFOUND = re.compile(r'unit "[^"]+" not found', re.I)
RE_VACUOUS = re.compile(r'(cannot find resource library|library "[^"]+" not found|'
                        r'"vcomponents" not found|unexpected end of file|'
                        r'cannot open file)', re.I)


def git_repo_of(path):
    """Return (toplevel, relpath) of the git repo that owns repo-relative path."""
    absd = os.path.dirname(os.path.join(REPO, path))
    top = os.path.realpath(subprocess.run(["git", "-C", absd, "rev-parse", "--show-toplevel"],
                                          capture_output=True, text=True).stdout.strip())
    rel = os.path.relpath(os.path.join(REPO, path), top)
    return top, rel


def read_side(path, side, base):
    """Contents of repo-relative path on a side ('base' or 'work'), or None."""
    if side == "work":
        p = os.path.join(REPO, path)
        if not os.path.exists(p):
            return None
        with open(p, encoding="latin-1") as f:
            return f.read()
    top, rel = git_repo_of(path)
    # The base revision applies to the top-level repo; a submodule uses its HEAD.
    rev = base if os.path.realpath(top) == os.path.realpath(REPO) else "HEAD"
    r = subprocess.run(["git", "-C", top, "show", f"{rev}:{rel}"],
                       capture_output=True)
    if r.returncode != 0:
        return None
    return r.stdout.decode("latin-1")


def extract_package(text, pkg):
    m = re.search(r"^\s*package\s+%s\s+is\b" % re.escape(pkg), text, re.I | re.M)
    if not m:
        return None
    e = re.search(r"^\s*end(\s+package)?(\s+%s)?\s*;" % re.escape(pkg), text[m.end():], re.I | re.M)
    if not e:
        return None
    ctx = context_before(text, m.start())
    return ctx + text[m.start():m.end() + e.end()] + "\n"


def context_before(text, pos):
    lines = []
    for ln in text[:pos].splitlines():
        s = ln.split("--")[0].strip()
        if re.match(r"^(library|use)\s", s, re.I):
            if s not in lines:
                lines.append(s)
    return "\n".join(lines) + "\n\n"


def extract_entity(text, name):
    m = re.search(r"^\s*entity\s+%s\s+is\b" % re.escape(name), text, re.I | re.M)
    if not m:
        return None
    e = re.search(r"^\s*end(\s+entity)?(\s+%s)?\s*;" % re.escape(name), text[m.end():], re.I | re.M)
    if not e:
        return None
    return context_before(text, m.start()) + text[m.start():m.end() + e.end()] + "\n"


def build_entity_index():
    """Index of entity and package declarations: name -> repo-relative path."""
    idx = {}
    pidx = {}
    for d in ENTITY_DIRS:
        for root, _, files in os.walk(os.path.join(REPO, d)):
            for fn in sorted(files):
                if not fn.lower().endswith((".vhd", ".vhdl")):
                    continue
                full = os.path.join(root, fn)
                rel = os.path.relpath(full, REPO)
                if ENTITY_SKIP.search("/" + rel):
                    continue
                try:
                    with open(full, encoding="latin-1") as f:
                        t = f.read()
                except OSError:
                    continue
                for m in re.finditer(r"^\s*entity\s+(\w+)\s+is\b", t, re.I | re.M):
                    idx.setdefault(m.group(1).lower(), rel)
                for m in re.finditer(r"^\s*package\s+(\w+)\s+is\b", t, re.I | re.M):
                    pidx.setdefault(m.group(1).lower(), rel)
    return idx, pidx


def strip_comments(text):
    return "\n".join(ln.split("--")[0] for ln in text.splitlines())


def sub_entities(text):
    t = strip_comments(text)
    own = {m.group(1).lower() for m in re.finditer(r"^\s*entity\s+(\w+)\s+is\b", t, re.I | re.M)}
    subs = []
    for m in re.finditer(r"\bentity\s+work\.(\w+)", t, re.I):
        n = m.group(1).lower()
        if n not in own and n not in subs:
            subs.append(n)
    return subs


def work_packages(text):
    t = strip_comments(text)
    return [m.group(1).lower() for m in re.finditer(r"\buse\s+work\.(\w+)\.", t, re.I)]


def ghdl(args, cwd):
    r = subprocess.run([GHDL] + args, capture_output=True, text=True, cwd=cwd)
    return r.returncode, (r.stdout + r.stderr)


def normalize(out):
    diags = []
    for ln in out.splitlines():
        m = RE_LOC.match(ln.strip())
        if m:
            msg = RE_EMBED_LOC.sub("<loc>", m.group("msg")).strip()
            diags.append(msg)
        elif re.search(r"(error|warning)", ln, re.I) and "compilation error" not in ln:
            diags.append(RE_EMBED_LOC.sub("<loc>", ln.strip()))
    return diags


def analyze_target(target, side, base, lib, src, common, mutate):
    ttxt = read_side(target, side, base)
    if ttxt is None:
        return {"missing": True, "diags": [], "notes": [], "seeds": []}
    if mutate:
        ttxt = mutate(ttxt)
    fn = os.path.join(src, os.path.basename(target))
    with open(fn, "w", encoding="latin-1") as f:
        f.write(ttxt)
    rc, out = ghdl(["-a"] + common + [fn], lib)
    return {"missing": False, "diags": normalize(out), "rc": rc, "notes": [], "seeds": [], "raw": out}


def run_side(target, side, base, xlib, tmproot, eidx, mutate=None):
    """Analyze target on one side. Returns dict with diagnostics and notes."""
    lib = os.path.join(tmproot, side + "_" + re.sub(r"\W", "_", target))
    os.makedirs(lib, exist_ok=True)
    src = os.path.join(lib, "src")
    os.makedirs(src, exist_ok=True)
    common = FLAGS + ["--workdir=" + lib, "-P" + xlib]
    notes = []
    # 1) seed packages; a target that is itself a seed package file is
    #    analyzed at its place in the seed order (and only once)
    early = None
    for path, pkg in SEED_PACKAGES:
        if path == target and pkg is None:
            early = analyze_target(target, side, base, lib, src, common, mutate)
            continue
        txt = read_side(path, side, base)
        if txt is None:
            notes.append(f"seed missing: {path}")
            continue
        if pkg:
            txt = extract_package(txt, pkg)
            if txt is None:
                notes.append(f"seed package {pkg} not found in {path}")
                continue
        fn = os.path.join(src, "seed_" + os.path.basename(path))
        with open(fn, "w", encoding="latin-1") as f:
            f.write(txt)
        rc, out = ghdl(["-a"] + common + [fn], lib)
        if rc != 0:
            notes.append(f"seed failed: {path}: {out.strip().splitlines()[:1]}")
    if early is not None:
        early["notes"] = notes + early["notes"]
        return early
    # 2) target text
    ttxt = read_side(target, side, base)
    if ttxt is None:
        return {"missing": True, "diags": [], "notes": notes, "seeds": []}
    if mutate:
        ttxt = mutate(ttxt)
    # 3) seed sub-entity declarations (and the packages their context needs)
    eidx, pidx = eidx
    seeded = {pkg or os.path.basename(path)[:-4].lower() for path, pkg in SEED_PACKAGES}
    seeded |= {"qnice_tools", "globals"}

    def ensure_pkgs(text, depth=0):
        for pn in work_packages(text):
            if pn in seeded or pn not in pidx or depth > 6:
                continue
            seeded.add(pn)
            ptxt = read_side(pidx[pn], side, base)
            ptxt = extract_package(ptxt, pn) if ptxt else None
            if ptxt is None:
                continue
            ensure_pkgs(ptxt, depth + 1)
            fn = os.path.join(src, "pkg_" + pn + ".vhd")
            with open(fn, "w", encoding="latin-1") as f:
                f.write(ptxt)
            rc, out = ghdl(["-a"] + common + [fn], lib)
            notes.append(f"package seed {pn} from {pidx[pn]}: {'ok' if rc == 0 else 'failed'}")

    ensure_pkgs(ttxt)
    seeds = []
    for n in sub_entities(ttxt):
        path = eidx.get(n)
        if path is None:
            continue
        etxt = read_side(path, side, base)
        etxt = extract_entity(etxt, n) if etxt else None
        if etxt is None:
            notes.append(f"entity {n}: declaration not extractable from {path}")
            continue
        ensure_pkgs(etxt)
        fn = os.path.join(src, "ent_" + n + ".vhd")
        with open(fn, "w", encoding="latin-1") as f:
            f.write(etxt)
        rc, out = ghdl(["-a"] + common + [fn], lib)
        seeds.append((n, rc == 0))
        if rc != 0:
            notes.append(f"entity seed {n} failed: {(normalize(out) or ['?'])[0]}")
    # 4) analyze the target itself
    fn = os.path.join(src, os.path.basename(target))
    with open(fn, "w", encoding="latin-1") as f:
        f.write(ttxt)
    rc, out = ghdl(["-a"] + common + [fn], lib)
    return {"missing": False, "diags": normalize(out), "rc": rc, "notes": notes,
            "seeds": seeds, "raw": out}


def verdict(target, rb, rw, verbose):
    lines = []
    if rw["missing"]:
        return False, [f"FAIL {target}: file missing in working tree"]
    nd_w = sum(1 for d in rw["diags"] if RE_NODECL.search(d))
    vac_w = [d for d in rw["diags"] if RE_VACUOUS.search(d)]
    nf_w = sum(1 for d in rw["diags"] if RE_NOTFOUND.search(d))
    seeds_ok = sum(1 for _, ok in rw["seeds"] if ok)
    info = (f"diags={len(rw['diags'])} unit-not-found={nf_w} no-declaration={nd_w} "
            f"entity-seeds={seeds_ok}/{len(rw['seeds'])}")
    if rb["missing"]:
        others = [d for d in rw["diags"] if not RE_NOTFOUND.search(d)]
        ok = nd_w == 0 and not vac_w and not others
        lines.append(f"{'PASS' if ok else 'FAIL'} {target} (new file, no base version) {info}")
        for d in others:
            lines.append("   + " + d)
        return ok, lines
    nd_b = sum(1 for d in rb["diags"] if RE_NODECL.search(d))
    vac_b = [d for d in rb["diags"] if RE_VACUOUS.search(d)]
    cb = collections.Counter(rb["diags"])
    cw = collections.Counter(rw["diags"])
    only_b = cb - cw
    only_w = cw - cb
    ok = not only_b and not only_w and nd_b == 0 and nd_w == 0 and not vac_b and not vac_w
    lines.append(f"{'PASS' if ok else 'FAIL'} {target} {info}")
    if nd_b:
        lines.append(f"   base side has {nd_b} 'no declaration' errors")
    if vac_b or vac_w:
        lines.append("   vacuous analysis (analysis stopped early):")
        for d in sorted(set(vac_b + vac_w)):
            lines.append("   ! " + d)
    for d, n in sorted(only_b.items()):
        lines.append(f"   - [{n}x] {d}")
    for d, n in sorted(only_w.items()):
        lines.append(f"   + [{n}x] {d}")
    if verbose:
        for side, r in (("base", rb), ("work", rw)):
            for nt in r["notes"]:
                lines.append(f"   ({side}) note: {nt}")
            for d in sorted(set(r["diags"])):
                lines.append(f"   ({side}) diag: {d}")
    return ok, lines


def make_mutator(text):
    """Rename the declaration of a used signal so that its uses become undeclared."""
    t = strip_comments(text)
    for kind in ("signal", "constant"):
        cands = re.findall(r"^\s*%s\s+(\w+)\s*:" % kind, t, re.I | re.M)
        for name in reversed(cands):
            if len(re.findall(r"\b%s\b" % re.escape(name), t, re.I)) >= 2:
                def mut(x, name=name, kind=kind):
                    return re.sub(r"^(\s*%s\s+)%s(\s*:)" % (kind, re.escape(name)),
                                  r"\1%s_selftest_mut\2" % name, x, count=1, flags=re.I | re.M)
                return f"{kind} {name}", mut
    return None, None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+")
    ap.add_argument("--base", default="HEAD", help="base revision of the top-level repo (default HEAD)")
    ap.add_argument("-j", type=int, default=int(os.environ.get("JOBS", "3")), help="parallel ghdl jobs (max 3)")
    ap.add_argument("--keep", action="store_true", help="keep the temporary libraries")
    ap.add_argument("--selftest", action="store_true",
                    help="mutation self-test: rename one used signal declaration in the working copy "
                         "and expect FAIL with new 'no declaration' errors (proves the check is not vacuous)")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()
    jobs = max(1, min(3, a.j))

    if not os.path.exists(GHDL):
        print(f"RESULT: FAIL ghdl not found at {GHDL}")
        return 2
    tmproot = tempfile.mkdtemp(prefix="ntsc_analyze_")
    t0 = time.time()
    xlib = os.path.join(tmproot, "xlib")
    os.makedirs(xlib)
    for libname, fn in STUBS:
        rc, out = ghdl(["-a"] + FLAGS + ["--work=" + libname, "--workdir=" + xlib, fn], xlib)
        if rc != 0:
            print(out)
            print(f"RESULT: FAIL stub library {libname} does not analyze")
            return 2
    eidx = build_entity_index()

    targets = []
    for f in a.files:
        p = os.path.relpath(os.path.realpath(f), REPO) if os.path.exists(f) else f
        targets.append(p)

    all_ok = True
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        for tgt in targets:
            ts = time.time()
            mut = None
            mname = None
            if a.selftest:
                wt = read_side(tgt, "work", a.base) or ""
                mname, mut = make_mutator(wt)
                if mut is None:
                    print(f"SKIP {tgt}: no used signal or constant declaration to mutate")
                    continue
            fb = ex.submit(run_side, tgt, "base", a.base, xlib, tmproot, eidx)
            fw = ex.submit(run_side, tgt, "work", a.base, xlib, tmproot, eidx, mut)
            rb, rw = fb.result(), fw.result()
            ok, lines = verdict(tgt, rb, rw, a.verbose)
            dt = time.time() - ts
            if a.selftest:
                caught = not ok and any(RE_NODECL.search(d) for d in rw["diags"])
                print(f"{'PASS' if caught else 'FAIL'} selftest {tgt}: mutated {mname} "
                      f"{'detected' if caught else 'NOT detected'} ({dt:.1f} s)")
                all_ok &= caught
            else:
                lines[0] += f" ({dt:.1f} s)"
                print("\n".join(lines))
                all_ok &= ok
            sys.stdout.flush()
    if a.keep:
        print(f"libraries kept in {tmproot}")
    else:
        shutil.rmtree(tmproot, ignore_errors=True)
    print(f"total {time.time() - t0:.1f} s")
    if all_ok:
        print("RESULT: PASS")
        return 0
    print("RESULT: FAIL see the FAIL lines above")
    return 1


if __name__ == "__main__":
    sys.exit(main())
