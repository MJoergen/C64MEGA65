#!/usr/bin/env python3
# --------------------------------------------------------------------------------------------------
# Wiring of the input device settings (GitHub issues #190, #193), used by run.sh (part wiring)
#
#   wiring.py check   <repo> <build> <ghdl> <base>            the checks below on the working tree
#   wiring.py mutants <repo> <build> <ghdl> <base> <jobs>     every mutant must fail a check
#
# GHDL (with shells: the real entity declarations with empty architectures):
#   * the four board files analyze and elaborate against the entity declarations of framework,
#     MEGA65_Core, audio, max10 and pcm_to_pdm of the working tree
#   * differential analysis against the base commit: framework.vhd, qnice_wrapper.vhd and the four
#     board files, each in a library with what it instantiates (real entities where they analyze
#     on their own, shells otherwise) and with a stub of the Xilinx library xpm that declares the
#     component xpm_cdc_array_single, so that GHDL checks the port maps of i_sys2main,
#     i_main2qnice and i_qnice2main, the widths of the actuals included; the working tree must not
#     show a diagnostic that the base does not show, and only "not found" for entities outside the
#     library
# Static checks (what GHDL cannot see):
#   * i_qnice2main: every src_in slice has a dest_out slice with the identical range; the slices
#     are contiguous from 0, do not overlap and add up to WIDTH; each source is paired with the
#     destination it had in the base commit, except the four paddle values, which are gone
#   * i_qnice2main_paddles: cdc_stable with 32 bits and a source register, from qnice_clk to
#     main_clk_i, the four paddle values in the order and with the pairing of the base commit:
#     source slice k carries the source of the k-th paddle pair, destination slice k feeds the
#     debouncer input whose output is the destination of that pair
#   * i_joy_debouncer gets main_mouse_amiga_i, and as flip_joys_i the destination of
#     qnice_flip_joyports_i in i_qnice2main; main_pot1_x_o .. main_pot2_y_o have no other source
#   * i_qnice_wrapper gets qnice_paddle_atari_i; qnice_wrapper.vhd passes bit 0 to atari_paddles_a
#     and bit 1 to atari_paddles_b
#   * each board file connects qnice_paddle_atari_o and main_mouse_amiga_o of MEGA65_Core to
#     qnice_paddle_atari_i and main_mouse_amiga_i of framework, through two distinct signals
#   * every entity that framework.vhd, qnice_wrapper.vhd, debouncer.vhd, amiga_mouse.vhd,
#     mega65.vhd and the board file instantiate is declared in a source file of each Vivado project
#     CORE/CORE-R{3,4,5,6}.xpr
#
# done by sy2002 in 2026 and licensed under GPL v3
# --------------------------------------------------------------------------------------------------

import collections
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

FILES = {
    "framework":       "M2M/vhdl/framework.vhd",
    "qnice_wrapper":   "M2M/vhdl/qnice_wrapper.vhd",
    "r3":              "M2M/vhdl/top_mega65-r3.vhd",
    "r4":              "M2M/vhdl/top_mega65-r4.vhd",
    "r5":              "M2M/vhdl/top_mega65-r5.vhd",
    "r6":              "M2M/vhdl/top_mega65-r6.vhd",
    "mega65":          "CORE/vhdl/mega65.vhd",
    "audio":           "M2M/vhdl/controllers/M65/audio.vhd",
    "max10":           "M2M/vhdl/controllers/M65/max10.vhdl",
    "pcm_to_pdm":      "M2M/vhdl/controllers/M65/pcm_to_pdm.vhdl",
    "debounce":        "M2M/vhdl/debounce.vhd",
    "amiga_mouse":     "M2M/vhdl/amiga_mouse.vhd",
    "debouncer":       "M2M/vhdl/debouncer.vhd",
    "cdc_stable":      "M2M/vhdl/cdc_stable.vhd",
    "mouse_input":     "M2M/vhdl/controllers/M65/mouse_input.vhdl",
    "tools":           "M2M/QNICE/vhdl/tools.vhd",
    "video_modes_pkg": "M2M/vhdl/av_pipeline/video_modes_pkg.vhd",
    "types_pkg":       "M2M/vhdl/controllers/HDMI/types_pkg.vhd",
    "globals":         "CORE/vhdl/globals.vhd",
    "xpr_r3":          "CORE/CORE-R3.xpr",
    "xpr_r4":          "CORE/CORE-R4.xpr",
    "xpr_r5":          "CORE/CORE-R5.xpr",
    "xpr_r6":          "CORE/CORE-R6.xpr",
}
# design files of this change, whose instantiated entities have to be part of the Vivado projects
# (a board file only of its own project)
XPR_DESIGN = ["framework", "qnice_wrapper", "debouncer", "amiga_mouse", "mega65"]
# where the sources of the projects live (relative to the repository)
SRC_DIRS = ["M2M/vhdl", "M2M/QNICE/vhdl", "CORE/vhdl", "CORE/C64_MiSTerMEGA65"]
PKGS = ["tools", "video_modes_pkg", "types_pkg", "globals"]
BOARDS = ["r3", "r4", "r5", "r6"]
DIFFED = ["framework", "qnice_wrapper"] + BOARDS
GF = ["--std=08", "-frelaxed", "-fno-caret-diagnostics"]
PADDLES = ["pot1_x", "pot1_y", "pot2_x", "pot2_y"]
# diagnostics that entities outside the library of an analysis cause
OUTSIDE = [r'^unit "\w+" not found in library "work"$', r"ghdl: compilation error$"]

# stub of the Xilinx library xpm: the declaration of the component as in xpm.vcomponents of Vivado
XPM_STUB = """library ieee;
use ieee.std_logic_1164.all;
package vcomponents is
   component xpm_cdc_array_single is
      generic (
         DEST_SYNC_FF   : integer := 4;
         INIT_SYNC_FF   : integer := 0;
         SIM_ASSERT_CHK : integer := 0;
         SRC_INPUT_REG  : integer := 1;
         WIDTH          : integer := 2
      );
      port (
         dest_out : out std_logic_vector(WIDTH - 1 downto 0);
         dest_clk : in  std_logic;
         src_clk  : in  std_logic;
         src_in   : in  std_logic_vector(WIDTH - 1 downto 0)
      );
   end component xpm_cdc_array_single;
end package vcomponents;
"""
IDX = None


# --------------------------------------------------------------------------------------------------
# sources

def load_tree(repo):
    return {k: open(os.path.join(repo, p)).read() for k, p in FILES.items()}


def load_base(repo, rev):
    out = {}
    for k in DIFFED + XPR_DESIGN + ["xpr_" + b for b in BOARDS]:
        r = subprocess.run(["git", "-C", repo, "show", f"{rev}:{FILES[k]}"], capture_output=True, text=True)
        if r.returncode != 0:
            if k in DIFFED or k.startswith("xpr_"):
                raise SystemExit(f"cannot read {FILES[k]} of {rev}")
            out[k] = ""                         # the file did not exist yet (amiga_mouse.vhd)
        else:
            out[k] = r.stdout
    return out


def strip_comments(text):
    return "\n".join(l.split("--", 1)[0] for l in text.splitlines())


def no_unisim(text):
    return "\n".join(l for l in text.splitlines()
                     if not re.match(r"\s*(library|use)\s+unisim\b", l, re.I)) + "\n"


def shell(text, ent):
    lines = text.splitlines()
    s = next(i for i, l in enumerate(lines) if re.match(rf"\s*entity\s+{ent}\s+is\b", l, re.I))
    e = next(i for i in range(s, len(lines)) if re.match(rf"\s*end(\s+entity)?(\s+{ent})?\s*;", lines[i], re.I))
    ctx = [l for l in lines[:s] if re.match(r"\s*(library|use)\b", l, re.I) and not re.search(r"\b(xpm|unisim)\b", l, re.I)]
    return "\n".join(ctx + lines[s:e + 1] + [f"architecture shell of {ent} is begin end architecture shell;", ""])


# --------------------------------------------------------------------------------------------------
# GHDL

class Ghdl:
    def __init__(self, ghdl, build):
        self.ghdl, self.build = ghdl, build
        os.makedirs(build, exist_ok=True)
        self.xpm = os.path.join(build, "xpm")
        os.makedirs(self.xpm, exist_ok=True)
        p = os.path.join(build, "xpm_stub.vhd")
        open(p, "w").write(XPM_STUB)
        r = subprocess.run([ghdl, "-a"] + GF + ["--work=xpm", f"--workdir={self.xpm}", p], capture_output=True, text=True)
        if r.returncode != 0:
            raise SystemExit("cannot analyze the stub of xpm: " + r.stdout + r.stderr)

    def write(self, name, text):
        p = os.path.join(self.build, name)
        open(p, "w").write(text)
        return p

    def analyze(self, lib, paths):
        os.makedirs(lib, exist_ok=True)
        r = subprocess.run([self.ghdl, "-a"] + GF + [f"--workdir={lib}"] + paths, capture_output=True, text=True)
        return r.returncode == 0, r.stdout + r.stderr

    def elaborate(self, lib, unit):
        r = subprocess.run([self.ghdl, "-e"] + GF + ["--workdir=.", unit], cwd=lib, capture_output=True, text=True)
        return r.returncode == 0, r.stdout + r.stderr

    def diags(self, lib, name, text):
        # analyze text into a copy of lib; the diagnostics without file names and positions
        work = os.path.join(self.build, "d_" + name)
        if os.path.exists(work):
            shutil.rmtree(work)
        shutil.copytree(lib, work)
        p = os.path.join(work, name + ".vhd")
        open(p, "w").write(no_unisim(text))
        r = subprocess.run([self.ghdl, "-a"] + GF + [f"--workdir={work}", f"-P{self.xpm}", p], capture_output=True, text=True)
        out = []
        for l in (r.stdout + r.stderr).splitlines():
            m = re.match(r"^[^:]*:\d+:\d+:\s*(.*)$", l)
            out.append(m.group(1) if m else l.strip())
        return sorted(x for x in out if x)


def first_error(text):
    for l in text.splitlines():
        m = re.match(r"^[^:]*:\d+:\d+:\s*(.*)$", l)
        if m and "warning" not in l:
            return m.group(1).strip()
    for l in text.splitlines():
        if "error" in l.lower():
            return l.strip()
    return text.strip().splitlines()[0] if text.strip() else "?"


def ghdl_checks(tree, base, g):
    """returns (errors, notes)"""
    errs, notes = [], []
    pk = [g.write(k + ".vhd", tree[k]) for k in PKGS]
    shells = [g.write("sh_" + k + ".vhd", shell(tree[k], ent)) for k, ent in
              (("framework", "framework"), ("mega65", "MEGA65_Core"), ("audio", "audio"), ("max10", "max10"),
               ("pcm_to_pdm", "pcm_to_pdm"))]
    lib_b = os.path.join(g.build, "lib_boards")
    ok, out = g.analyze(lib_b, pk + shells)
    if not ok:
        return [f"GHDL analysis of the shells: {first_error(out)}"], notes
    # board files: analysis and elaboration
    for b in BOARDS:
        lib = os.path.join(g.build, "lib_" + b)
        if os.path.exists(lib):
            shutil.rmtree(lib)
        shutil.copytree(lib_b, lib)
        p = g.write(b + ".vhd", tree[b])
        ent = re.search(r"^entity\s+(\w+)\s+is", tree[b], re.M | re.I).group(1)
        ok, out = g.analyze(lib, [p])
        if not ok:
            errs.append(f"GHDL analysis of top_mega65-{b}.vhd: {first_error(out)}")
            continue
        ok, out = g.elaborate(lib, ent)
        if not ok:
            errs.append(f"GHDL elaboration of top_mega65-{b}.vhd: {first_error(out)}")
            continue
        notes.append(f"top_mega65-{b}.vhd ({ent}): analysis and elaboration against the entity declarations OK")
    # differential analysis
    lib_f = os.path.join(g.build, "lib_framework")
    ok, out = g.analyze(lib_f, pk + [g.write(k + ".vhd", tree[k]) for k in ("cdc_stable", "debounce", "amiga_mouse", "debouncer")]
                        + [g.write("sh_qnice_wrapper.vhd", shell(tree["qnice_wrapper"], "qnice_wrapper"))])
    if not ok:
        return errs + [f"GHDL analysis of the library for framework.vhd: {first_error(out)}"], notes
    lib_w = os.path.join(g.build, "lib_wrapper")
    ok, out = g.analyze(lib_w, pk + [g.write("mouse_input.vhd", tree["mouse_input"])])
    if not ok:
        return errs + [f"GHDL analysis of the library for qnice_wrapper.vhd: {first_error(out)}"], notes
    for k, lib in [("framework", lib_f), ("qnice_wrapper", lib_w)] + [(b, lib_b) for b in BOARDS]:
        d_base = g.diags(lib, k + "_base", base[k])
        d_new = g.diags(lib, k + "_new", tree[k])
        extra = collections.Counter(d_new) - collections.Counter(d_base)
        # the working tree may only show what the entities outside the library cause
        other = [d for d in d_new if not any(re.search(p, d) for p in OUTSIDE)]
        name = os.path.basename(FILES[k])
        if extra:
            errs.append(f"differential analysis of {name}: new diagnostic: {sorted(extra)[0]}")
        elif other:
            errs.append(f"analysis of {name}: {other[0]}")
        elif not d_new:
            notes.append(f"{name}: no diagnostic (the base: {len(d_base)})")
        else:
            notes.append(f"{name}: {len(d_new)} diagnostics, none that {len(d_base)} of the base do not have, "
                         f"all about entities outside the library")
    return errs, notes


# --------------------------------------------------------------------------------------------------
# static checks

ASSOC = re.compile(r"^\s*(\w+)\s*(?:\(\s*([^()]*?)\s*\))?\s*=>\s*(.*?)\s*,?\s*$")


def block(text, label):
    m = re.search(r"^\s*" + label + r"\s*:\s*(?:entity\s+work\.(\w+)|(\w+))(.*?)^\s*\)\s*;\s*--\s*" + label + r"\s*$",
                  text, re.S | re.M | re.I)
    if not m:
        return None, None
    return (m.group(1) or m.group(2)), m.group(3)


def assocs(blk):
    out = []
    for line in strip_comments(blk).splitlines():
        if "=>" not in line:
            continue
        m = ASSOC.match(line)
        if m:
            out.append((m.group(1).lower(), m.group(2), m.group(3).strip()))
    return out


def rng(s):
    s = " ".join(s.split())
    m = re.match(r"^(\d+) downto (\d+)$", s)
    if m:
        return int(m.group(1)), int(m.group(2))
    if re.match(r"^\d+$", s):
        return int(s), int(s)
    raise ValueError(s)


def slices(a, formal):
    return [(rng(r), act) for f, r, act in a if f == formal and r is not None]


def actual(a, formal):
    v = [act for f, r, act in a if f == formal and r is None]
    return v[0] if len(v) == 1 else None


def contiguous(ranges, width, what):
    errs = []
    rs = sorted(ranges, key=lambda x: x[1])
    nxt = 0
    for hi, lo in rs:
        if lo != nxt:
            errs.append(f"{what}: slice ({hi} downto {lo}) does not follow bit {nxt - 1}" if lo > nxt else
                        f"{what}: slice ({hi} downto {lo}) overlaps the slice before")
        nxt = max(nxt, hi + 1)
    if nxt != width:
        errs.append(f"{what}: the slices end at bit {nxt - 1}, WIDTH is {width}")
    return errs


def cdc_pairs(text, what):
    """(errors, width, {range: (src, dst)}) of i_qnice2main"""
    errs = []
    ent, blk = block(text, "i_qnice2main")
    if blk is None:
        return [f"{what}: i_qnice2main not found"], 0, {}
    a = assocs(blk)
    w = actual(a, "width")
    width = int(w) if w and w.isdigit() else -1
    src = dict(slices(a, "src_in"))
    dst = dict(slices(a, "dest_out"))
    if len(src) != len(slices(a, "src_in")) or len(dst) != len(slices(a, "dest_out")):
        errs.append(f"{what}: i_qnice2main associates a range twice")
    for r in src:
        if r not in dst:
            errs.append(f"{what}: i_qnice2main src_in({r[0]} downto {r[1]}) has no dest_out slice with that range")
    for r in dst:
        if r not in src:
            errs.append(f"{what}: i_qnice2main dest_out({r[0]} downto {r[1]}) has no src_in slice with that range")
    errs += contiguous(list(src), width, f"{what}: i_qnice2main src_in")
    errs += contiguous(list(dst), width, f"{what}: i_qnice2main dest_out")
    return errs, width, {r: (src[r], dst.get(r)) for r in src}


def static_checks(tree, base):
    errs, notes = [], []
    fw, fwb = tree["framework"], base["framework"]
    # i_qnice2main
    e, width, pairs = cdc_pairs(fw, "framework.vhd")
    eb, wb, pairs_b = cdc_pairs(fwb, "framework.vhd of the base")
    errs += e
    if eb:
        errs += eb
    pad_b = sorted([(r, s, d) for r, (s, d) in pairs_b.items() if "qnice_pot" in s], key=lambda x: x[0][1])
    if len(pad_b) != 4:
        errs.append(f"base: {len(pad_b)} paddle slices in i_qnice2main, expected 4")
    exp = collections.Counter((s, d) for r, (s, d) in pairs_b.items() if "qnice_pot" not in s)
    got = collections.Counter(pairs.values())
    if got != exp:
        for p in sorted((got - exp).keys()):
            errs.append(f"framework.vhd: i_qnice2main pairs {p[0]} with {p[1]}, which the base does not")
        for p in sorted((exp - got).keys()):
            errs.append(f"framework.vhd: i_qnice2main lost the pair {p[0]} -> {p[1]} of the base")
    if not e and got == exp:
        notes.append(f"i_qnice2main: WIDTH {width}, {len(pairs)} slices with identical ranges on both sides, "
                     f"contiguous from 0; every pair as in the base ({wb} bits) without the four paddle values")
    # i_qnice2main_paddles
    ent, blk = block(fw, "i_qnice2main_paddles")
    deb_ent, deb = block(fw, "i_joy_debouncer")
    da = assocs(deb) if deb else []
    if blk is None or ent.lower() != "cdc_stable":
        errs.append("framework.vhd: i_qnice2main_paddles (cdc_stable) not found")
    else:
        a = assocs(blk)
        if actual(a, "g_data_size") != "32" or (actual(a, "g_register_src") or "").lower() != "true":
            errs.append("framework.vhd: i_qnice2main_paddles needs G_DATA_SIZE 32 and G_REGISTER_SRC true")
        if actual(a, "src_clk_i") != "qnice_clk" or actual(a, "dst_clk_i") != "main_clk_i":
            errs.append("framework.vhd: i_qnice2main_paddles must cross from qnice_clk to main_clk_i")
        src = sorted(slices(a, "src_data_i"), key=lambda x: x[0][1])
        dst = sorted(slices(a, "dst_data_o"), key=lambda x: x[0][1])
        errs += contiguous([r for r, _ in src], 32, "framework.vhd: i_qnice2main_paddles src_data_i")
        errs += contiguous([r for r, _ in dst], 32, "framework.vhd: i_qnice2main_paddles dst_data_o")
        if [r for r, _ in src] != [r for r, _ in dst] or any(r[0] - r[1] != 7 for r, _ in src):
            errs.append("framework.vhd: i_qnice2main_paddles needs four bytes with identical ranges on both sides")
        elif len(src) == 4 and len(pad_b) == 4:
            ok = True
            for k, ((_, s), (_, d), (_, sb, db)) in enumerate(zip(src, dst, pad_b)):
                m = re.match(r"^main_(pot\d_[xy])_o$", db)
                name = m.group(1) if m else "?"
                if s != sb:
                    errs.append(f"framework.vhd: i_qnice2main_paddles byte {k} carries {s}, the base pairs {sb} there")
                    ok = False
                if actual(da, name + "_i") != d:
                    errs.append(f"framework.vhd: byte {k} of i_qnice2main_paddles ({d}) is not the {name}_i of "
                                f"i_joy_debouncer ({actual(da, name + '_i')})")
                    ok = False
                if actual(da, name + "_o") != db:
                    errs.append(f"framework.vhd: {name}_o of i_joy_debouncer is {actual(da, name + '_o')}, "
                                f"expected {db}")
                    ok = False
            if ok:
                notes.append("i_qnice2main_paddles: cdc_stable, 32 bits with a source register, qnice_clk to "
                             "main_clk_i; byte k carries the k-th paddle value of the base, its destination "
                             "feeds potN_i of i_joy_debouncer, whose potN_o is the destination of the base")
    if deb is None or actual(da, "amiga_i") != "main_mouse_amiga_i":
        errs.append("framework.vhd: i_joy_debouncer does not get amiga_i => main_mouse_amiga_i")
    # the port switcher of the debouncer: the core clock domain version of qnice_flip_joyports_i, which
    # is its destination in i_qnice2main
    flip_dst = [d for s, d in pairs.values() if s == "qnice_flip_joyports_i"]
    if len(flip_dst) != 1 or actual(da, "flip_joys_i") != flip_dst[0]:
        errs.append(f"framework.vhd: flip_joys_i of i_joy_debouncer is {actual(da, 'flip_joys_i')}, expected the "
                    f"destination of qnice_flip_joyports_i in i_qnice2main ({', '.join(flip_dst) or 'none'})")
    code = strip_comments(fw)
    for p in PADDLES:
        n = len(re.findall(rf"\bmain_{p}_o\b", code, re.I))
        if n != 2:
            errs.append(f"framework.vhd: main_{p}_o appears {n} times, expected the port and one association "
                        f"(i_joy_debouncer)")
    if not re.search(r"^\s*main_mouse_amiga_i\s*:\s*in\s+std_logic_vector\(1 downto 0\)\s*;", code, re.M | re.I):
        errs.append("framework.vhd: no port main_mouse_amiga_i : in std_logic_vector(1 downto 0)")
    if not re.search(r"^\s*qnice_paddle_atari_i\s*:\s*in\s+std_logic_vector\(1 downto 0\)\s*;", code, re.M | re.I):
        errs.append("framework.vhd: no port qnice_paddle_atari_i : in std_logic_vector(1 downto 0)")
    _, wr = block(fw, "i_qnice_wrapper")
    if wr is None or actual(assocs(wr), "qnice_paddle_atari_i") != "qnice_paddle_atari_i":
        errs.append("framework.vhd: i_qnice_wrapper does not get qnice_paddle_atari_i")
    # qnice_wrapper.vhd
    _, mi = block(tree["qnice_wrapper"], "i_mouse_paddles")
    ma = assocs(mi) if mi else []
    if actual(ma, "atari_paddles_a") != "qnice_paddle_atari_i(0)" or \
       actual(ma, "atari_paddles_b") != "qnice_paddle_atari_i(1)":
        errs.append(f"qnice_wrapper.vhd: atari_paddles_a / _b of i_mouse_paddles are {actual(ma, 'atari_paddles_a')} / "
                    f"{actual(ma, 'atari_paddles_b')}, expected qnice_paddle_atari_i(0) / (1)")
    if not errs:
        notes.append("framework.vhd: i_joy_debouncer gets main_mouse_amiga_i, main_pot1_x_o .. main_pot2_y_o have no "
                     "other source, i_qnice_wrapper gets qnice_paddle_atari_i; qnice_wrapper.vhd: bit 0 to "
                     "atari_paddles_a, bit 1 to atari_paddles_b")
    # board files
    for b in BOARDS:
        t = tree[b]
        _, fb = block(t, "i_framework")
        _, cb = block(t, "CORE")
        if fb is None or cb is None:
            errs.append(f"top_mega65-{b}.vhd: i_framework or CORE not found")
            continue
        fa, ca = assocs(fb), assocs(cb)
        A, M = actual(fa, "qnice_paddle_atari_i"), actual(fa, "main_mouse_amiga_i")
        A2, M2 = actual(ca, "qnice_paddle_atari_o"), actual(ca, "main_mouse_amiga_o")
        bad = []
        if A is None or A2 is None or A != A2:
            bad.append(f"qnice_paddle_atari: framework gets {A}, MEGA65_Core drives {A2}")
        if M is None or M2 is None or M != M2:
            bad.append(f"main_mouse_amiga: framework gets {M}, MEGA65_Core drives {M2}")
        if A is not None and A == M:
            bad.append("both settings on the same signal")
        bcode = strip_comments(t)
        for sig in {x for x in (A, M) if x}:
            if not re.search(rf"^\s*signal\s+{sig}\s*:\s*std_logic_vector\(1 downto 0\)\s*;", bcode, re.M | re.I):
                bad.append(f"{sig} is not a signal of std_logic_vector(1 downto 0)")
            else:
                uses = len(re.findall(rf"\b{sig}\b", bcode)) - 1
                if uses != 2:
                    bad.append(f"{sig} is used {uses} times, expected 2")
        for x in bad:
            errs.append(f"top_mega65-{b}.vhd: {x}")
        if not bad:
            notes.append(f"top_mega65-{b}.vhd: MEGA65_Core -> {A} -> framework, MEGA65_Core -> {M} -> framework")
    return errs, notes


def entity_index(repo):
    """entity (or Verilog module) name, lower case -> files that declare it, relative to the repository"""
    idx = collections.defaultdict(set)
    for d in SRC_DIRS:
        for root, dirs, files in os.walk(os.path.join(repo, d)):
            dirs[:] = [x for x in dirs if x not in ("test", "tests", "sim") and not x.startswith(".")]
            for fn in files:
                p = os.path.join(root, fn)
                rel = os.path.relpath(p, repo)
                try:
                    t = open(p, errors="replace").read()
                except OSError:
                    continue
                if fn.endswith((".vhd", ".vhdl")):
                    for m in re.finditer(r"^\s*entity\s+(\w+)\s+is\b", strip_comments(t), re.M | re.I):
                        idx[m.group(1).lower()].add(rel)
                elif fn.endswith((".v", ".sv")):
                    for m in re.finditer(r"^\s*module\s+(\w+)", t, re.M):
                        idx[m.group(1).lower()].add(rel)
    return idx


def missing_in_projects(tree, idx):
    """per board: {entity: text} of the entities that the design files instantiate and that no
    source file of the project declares"""
    out = {}
    for b in BOARDS:
        listed = set(re.findall(r'<File Path="\$PPRDIR/([^"]+)"', tree["xpr_" + b]))
        need = collections.OrderedDict()
        for k in XPR_DESIGN + [b]:
            for m in re.finditer(r"\bentity\s+work\.(\w+)", strip_comments(tree[k]), re.I):
                need.setdefault(m.group(1).lower(), os.path.basename(FILES[k]))
        miss = {}
        for ent, by in need.items():
            files = idx.get(ent, set())
            if not files:
                miss[ent] = f"{ent} (instantiated by {by}): no source file declares it"
            elif not {os.path.relpath(f, "CORE") for f in files} & listed:
                miss[ent] = f"{ent} (instantiated by {by}): none of {', '.join(sorted(files))} is in CORE-R{b[1]}.xpr"
        out[b] = (len(need), miss)
    return out


def xpr_checks(tree, base, idx):
    # an entity may be missing in a project only if it was missing there in the base commit already:
    # framework.vhd instantiates sdram only in the generate branch that MEGA65_R3 does not elaborate
    errs, notes = [], []
    now = missing_in_projects(tree, idx)
    before = missing_in_projects(base, idx)
    for b in BOARDS:
        n, miss = now[b]
        new = [t for e, t in miss.items() if e not in before[b][1]]
        for t in new:
            errs.append(f"CORE-R{b[1]}.xpr: {t}")
        if not new:
            old = sorted(miss)
            notes.append(f"CORE-R{b[1]}.xpr: the {n} entities that the design files of this change instantiate are "
                         f"declared in source files of the project" +
                         (f" (except {', '.join(old)}, as in the base: not elaborated for this board)" if old else ""))
    return errs, notes


def run_checks(tree, base, ghdl, build, idx=None):
    g = Ghdl(ghdl, build)
    e1, n1 = ghdl_checks(tree, base, g)
    e2, n2 = static_checks(tree, base)
    e3, n3 = xpr_checks(tree, base, idx if idx is not None else IDX)
    return e1, e2 + e3, n1 + n2 + n3


# --------------------------------------------------------------------------------------------------
# mutants: name, file, [(old, new), ...]; a board mutant exists for each of the four board files

def mutants():
    ms = []
    for b in BOARDS:
        ms += [
            (f"{b}_framework_without_atari", b, [("      qnice_paddle_atari_i    => qnice_paddle_atari,\n", "")]),
            (f"{b}_framework_without_amiga", b, [("      main_mouse_amiga_i      => main_mouse_amiga,\n", "")]),
            (f"{b}_core_without_atari", b, [("         qnice_paddle_atari_o    => qnice_paddle_atari,\n", "")]),
            (f"{b}_core_without_amiga", b, [("         main_mouse_amiga_o      => main_mouse_amiga,\n", "")]),
            (f"{b}_settings_exchanged", b, [
                ("      qnice_paddle_atari_i    => qnice_paddle_atari,\n", "      qnice_paddle_atari_i    => main_mouse_amiga,\n"),
                ("      main_mouse_amiga_i      => main_mouse_amiga,\n", "      main_mouse_amiga_i      => qnice_paddle_atari,\n")]),
        ]
    ms += [
        ("framework_wrapper_without_atari", "framework",
         [("      qnice_paddle_atari_i      => qnice_paddle_atari_i,\n", "")]),
        ("wrapper_bit0_to_port_b", "qnice_wrapper",
         [("atari_paddles_b         => qnice_paddle_atari_i(1),", "atari_paddles_b         => qnice_paddle_atari_i(0),")]),
        ("framework_debouncer_without_amiga", "framework",
         [("         amiga_i              => main_mouse_amiga_i,\n", "")]),
        ("framework_debouncer_without_paddle", "framework",
         [("         pot2_y_i             => main_pot2_y_n,\n", "")]),
        ("framework_debouncer_paddles_exchanged", "framework",
         [("         pot1_x_i             => main_pot1_x_n,\n         pot1_y_i             => main_pot1_y_n,",
           "         pot1_x_i             => main_pot1_y_n,\n         pot1_y_i             => main_pot1_x_n,")]),
        ("xpr_r6_without_amiga_mouse", "xpr_r6",
         [('''      <File Path="$PPRDIR/../M2M/vhdl/amiga_mouse.vhd">
        <FileInfo SFType="VHDL2008">
          <Attr Name="UsedIn" Val="synthesis"/>
          <Attr Name="UsedIn" Val="simulation"/>
        </FileInfo>
      </File>
''', "")]),
        ("framework_pot_from_old_synchronizer", "framework",
         [("         dest_out(838 downto 774)   => main_rtc_o\n",
           "         dest_out(838 downto 774)   => main_rtc_o,\n         dest_out(846 downto 839)   => main_pot1_x_o\n")]),
        ("framework_paddle_order", "framework",
         [("         dst_data_o( 7 downto  0) => main_pot1_x_n,\n         dst_data_o(15 downto  8) => main_pot1_y_n,",
           "         dst_data_o( 7 downto  0) => main_pot1_y_n,\n         dst_data_o(15 downto  8) => main_pot1_x_n,")]),
        ("framework_rtc_shifted", "framework",
         [("         src_in(838 downto 774)     => qnice_rtc,", "         src_in(839 downto 775)     => qnice_rtc,")]),
        ("framework_width_not_adapted", "framework",
         [("         WIDTH        => 839", "         WIDTH        => 871")]),
        ("framework_rtc_slice_short", "framework",
         [("         WIDTH        => 839", "         WIDTH        => 838"),
          ("         src_in(838 downto 774)     => qnice_rtc,", "         src_in(837 downto 774)     => qnice_rtc,"),
          ("         dest_out(838 downto 774)   => main_rtc_o", "         dest_out(837 downto 774)   => main_rtc_o")]),
        ("framework_debouncer_flip_from_qnice", "framework",
         [("         flip_joys_i          => main_flip_joyports,", "         flip_joys_i          => qnice_flip_joyports_i,")]),
    ]
    return ms


def apply(text, reps, name):
    for old, new in reps:
        if text.count(old) != 1:
            raise SystemExit(f"mutant {name}: pattern found {text.count(old)} times: {old!r}")
        text = text.replace(old, new)
    return text


def main():
    global IDX
    mode, repo, build, ghdl, base_rev = sys.argv[1:6]
    IDX = entity_index(repo)
    tree = load_tree(repo)
    base = load_base(repo, base_rev)
    if mode == "check":
        e1, e2, notes = run_checks(tree, base, ghdl, build)
        for n in notes:
            print("  " + n)
        for e in e1 + e2:
            print("  FAIL: " + e)
        return 0 if not (e1 or e2) else 1
    if mode == "mutants":
        jobs = int(sys.argv[6])
        ms = mutants()

        def one(m):
            name, key, reps = m
            t = dict(tree)
            t[key] = apply(tree[key], reps, name)
            e1, e2, _ = run_checks(t, base, ghdl, os.path.join(build, "mut_" + name))
            return name, e1, e2
        bad = 0
        with ThreadPoolExecutor(jobs) as ex:
            for name, e1, e2 in ex.map(one, ms):
                if not e1 and not e2:
                    print(f"  mutant {name}: SURVIVED")
                    bad += 1
                else:
                    by = []
                    if e1:
                        by.append("GHDL: " + e1[0])
                    if e2:
                        by.append("static: " + e2[0])
                    print(f"  mutant {name}: rejected by " + "; ".join(by))
                sys.stdout.flush()
        print(f"  {len(ms)} wiring mutants, {len(ms) - bad} rejected")
        return 0 if bad == 0 else 1
    return 2


if __name__ == "__main__":
    sys.exit(main())
