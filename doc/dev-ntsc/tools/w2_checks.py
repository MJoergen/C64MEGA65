#!/usr/bin/env python3
"""Checks of the HDMI video modes (issues #181 and #184: doc/dev-ntsc/NTSC-SPEC.md 10.2,
doc/dev-hdmi-raw/SPEC.md section 4).

    w2_checks.py REPO                      source-level checks and OSM transcription
    w2_checks.py REPO --window-vcd FILE    check the VCD of tb_window_av.vhd

Source-level checks (read from the working tree, nothing hand-copied):

  1. video_modes_pkg.vhd: the 16 members (NTSC at 7 to 9, raw at 10 to 15), the
     records, C_HDMI_720p_5994 = 1650 x 750 at CLK_KHZ 74167, CLK_SEL "0110",
     VIC 4; the raw records against the records they are derived from.
  2. framework.vhd: VIDEO_MODE_VECTOR(0 to 15), and the clock-select decode maps
     every video_mode_type member to the record of the same index.
  3. video_out_clock.vhd: the DRP table of every CLK_SEL that a record uses,
     decoded according to XAPP888 (the tables 0010, 0001 and 0110 are
     field-proven and validate the decoder): CLK_KHZ of a record that is not
     a raw record is the pixel clock rounded to kHz (CTS_FRAC 0 / 1); for a
     raw record CLK_KHZ + CTS_FRAC_N / CTS_FRAC_D is the pixel clock exactly.
     CLK_SEL 1011 to 1111 load the table of 0010. The raw records give the exact frame rate of the
     C64 (576p, 480p) or the surplus of doc/dev-hdmi-raw/SPEC.md 4.2 (720p).
  4. OSM placement: an integer transcription of vga_osm.vhd (stage 1 and 2,
     row direction) plus video_overlay.vhd (vga_row = pix_y + vshift, or
     pix_y * 2 + vshift at 15 kHz) for every NTSC output and every OSM scaling
     index s = 0 .. 8, without and with the change of spec section 7.4.
     It prints the table of spec section 7.3 and asserts that, with the
     change, the options menu (27 x 31 characters at character row 0) and the
     main screen (45 x 33 at row 0) are fully visible everywhere.

Prints "RESULT: PASS" or "RESULT: FAIL ...".
"""

import os
import re
import sys
from fractions import Fraction

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("  MISMATCH: " + what)


def read(repo, rel):
    return open(os.path.join(repo, rel), errors="replace").read()


def strip_comments(t):
    return re.sub(r"--[^\n]*", "", t)


# --------------------------------------------------------------------------------------------
# video_modes_pkg.vhd
# --------------------------------------------------------------------------------------------

def parse_records(pkg):
    recs = {}
    for m in re.finditer(r"constant\s+(C_\w+)\s*:\s*video_modes_t\s*:=\s*\((.*?)\);", pkg, re.S):
        fields = {}
        for f in re.finditer(r"(\w+)\s*=>\s*([^,\n]+)", strip_comments(m.group(2))):
            v = f.group(2).strip()
            if v.startswith('"') or v.startswith("'"):
                fields[f.group(1)] = v.strip("\"'")
            else:
                fields[f.group(1)] = int(v)
        recs[m.group(1)] = fields
    return recs


def parse_members(pkg):
    body = re.search(r"type\s+video_mode_type\s+is\s*\((.*?)\);", pkg, re.S).group(1)
    return re.findall(r"\b(C_VIDEO_\w+)", strip_comments(body))


def htotal(r):
    return r["H_PIXELS"] + r["H_FP"] + r["H_PULSE"] + r["H_BP"]


def vtotal(r):
    return r["V_PIXELS"] + r["V_FP"] + r["V_PULSE"] + r["V_BP"]


# --------------------------------------------------------------------------------------------
# framework.vhd
# --------------------------------------------------------------------------------------------

def parse_framework(fw):
    t = strip_comments(fw)
    vec = re.search(r"VIDEO_MODE_VECTOR\s*:\s*video_modes_vector\(0 to (\d+)\)\s*:=\s*\((.*?)\);", t, re.S)
    vector = re.findall(r"\b(C_\w+)", vec.group(2))
    dec = re.search(r"video_mode\s*<=(.*?);", t[t.index("i_clk_m2m"):], re.S).group(1)
    arms = re.findall(r"(C_\w+)\s+when\s+qnice_video_mode_i\s*=\s*(C_VIDEO_\w+)\s+else", dec)
    default = re.findall(r"(C_\w+)\s*$", dec.strip())[0]
    return int(vec.group(1)), vector, dict((b, a) for a, b in arms), default


# --------------------------------------------------------------------------------------------
# video_out_clock.vhd (XAPP888 DRP register decode)
# --------------------------------------------------------------------------------------------

def drp_table(vo, sel):
    """Return {DRP address: write data} of the table that one CLK_SEL value loads.

    video_out_clock.vhd has two table ROMs, selected by bit 8 of the table address:
    cfg_tbl (CLK_SEL 0000 to 0111, label = CLK_SEL x 0x20 + row) and cfg_tbl_raw
    (CLK_SEL 1000 and up, label = (CLK_SEL - 8) x 0x20 + row); CLK_SEL 1011 to 1111
    load the table of 0010 (tbl_sel). A text without cfg_tbl_raw (a single table, or
    the file with a 3-bit CLK_SEL) is read as a whole with base CLK_SEL x 0x20."""
    code = int(sel, 2)
    funcs = {m.group(1).lower(): m.group(2) for m in re.finditer(
        r"function\s+(cfg_tbl\w*)\s*\(.*?\bis\b(.*?)\bend\s+function\s+\1\s*;", vo, re.S | re.I)}
    if "cfg_tbl_raw" in funcs:
        if code > 10:
            code = 2
        text = funcs["cfg_tbl_raw"] if code >= 8 else funcs["cfg_tbl"]
        base = (code & 7) * 0x20
    else:
        text = vo
        base = code * 0x20
    regs = {}
    for m in re.finditer(r'when\s+x"([0-9A-Fa-f]{2})"\s*=>\s*data\s*:=\s*x"([0-9A-Fa-f]{2})"\s*&\s*x"([0-9A-Fa-f]{4})"', text):
        a = int(m.group(1), 16)
        if base <= a < base + 0x20:
            regs[int(m.group(2), 16) & 0x7F] = int(m.group(3), 16)
    return regs


def counter(reg1, reg2):
    """Divide value of an MMCM output counter (XAPP888 ClkReg1 / ClkReg2).

    Integer counters: HIGH_TIME + LOW_TIME VCO cycles, 1 with NO_COUNT (EDGE
    only moves the falling edge by half a VCO cycle). Fractional counters
    (FRAC_EN, CLKOUT0 and CLKFBOUT only): XAPP888 mmcm_frac_count_calc lowers
    HIGH_TIME / LOW_TIME by one each when 8 * odd + FRAC is at most 8 / 9;
    the parity of the integer part follows from FRAC_WF_R, which is set
    exactly when 1 <= 8 * odd + FRAC <= 8."""
    high = (reg1 >> 6) & 0x3F
    low = reg1 & 0x3F
    frac = (reg2 >> 12) & 0x7
    frac_en = (reg2 >> 11) & 1
    wf_rise = (reg2 >> 10) & 1
    no_count = (reg2 >> 6) & 1
    if no_count:
        return 1.0
    if not frac_en:
        return float(high + low)
    for odd in (0, 1):
        oaf = 8 * odd + frac
        integer = high + low + (oaf <= 8) + (oaf <= 9) + odd
        if integer % 2 == odd and wf_rise == (1 <= oaf <= 8):
            return integer + frac / 8.0
    raise ValueError("inconsistent fractional counter %04X %04X" % (reg1, reg2))


def divclk(reg):
    if (reg >> 12) & 1:          # NO_COUNT
        return 1
    return ((reg >> 6) & 0x3F) + (reg & 0x3F)


def mmcm_freq(regs, fref=100.0):
    m = counter(regs[0x14], regs[0x15])      # CLKFBOUT
    d = divclk(regs[0x16])                    # DIVCLK
    o1 = counter(regs[0x0A], regs[0x0B])      # CLKOUT1 = pixel clock
    o0 = counter(regs[0x08], regs[0x09])      # CLKOUT0 = serializer clock
    return m, d, o0, o1, fref * m / d / o1


# --------------------------------------------------------------------------------------------
# OSM transcription (vga_osm.vhd p_stage1 / p_stage2 rows, video_overlay.vhd stage1.vga_row)
# --------------------------------------------------------------------------------------------

G_VGA_DY = 540
FONT_DY = 16


def vhdl_div(a, b):
    """VHDL integer division truncates toward zero."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def osm_rows(rows, r15, vshift, s, box_y, box_dy, first=0):
    """For the screen rows first .. rows-1: the OSM character row they show (rows without OSM omitted)."""
    shown = {}
    for r in range(first, rows):
        vga_row = (2 * r if r15 else r) + vshift
        if vga_row < 0:
            continue
        row = vga_row
        if vga_row < G_VGA_DY:
            row = vga_row + vhdl_div(s * (vga_row - box_dy * FONT_DY // 2), 8)
        if row < 0 or row > 2047:          # 11-bit wrap in hardware: far below any box
            continue
        cy = row // FONT_DY
        if box_y <= cy < box_y + box_dy:
            shown[r] = cy
    return shown


def osm_summary(rows, r15, vshift, s, box_y, box_dy):
    """Screen rows that show the box, and the character rows that are cut off.

    A character row counts as lost when any screen row that would show it lies
    above the first or below the last visible row (the extent is taken from a
    screen that is unbounded in both directions, because the scaler skips some
    font rows anyway)."""
    unbounded = osm_rows(1024, r15, vshift, s, box_y, box_dy, first=-128)
    lost = []
    for c in range(box_y, box_y + box_dy):
        rc = [r for r, cc in unbounded.items() if cc == c]
        if not rc or min(rc) < 0 or max(rc) >= rows:
            lost.append(c)
    vis = [r for r in unbounded if 0 <= r < rows]
    rng = (min(vis), max(vis)) if vis else None
    return rng, lost


OUTPUTS = [
    # name, rows, 15 kHz, NTSC force, shift with the change
    ("NTSC VGA 31 kHz (500 rows)", 500, False, True, 0),
    ("NTSC VGA 15 kHz (250 lines)", 250, True, True, 0),
    ("NTSC HDMI 480p (480 rows)", 480, False, True, 24),
    ("NTSC HDMI 720p (720 rows)", 720, False, False, 0),
    ("PAL VGA (540 rows)", 540, False, False, 0),
    ("PAL HDMI 576p (576 rows)", 576, False, False, 0),
]
BOXES = [("options menu 27x31", 0, 31), ("main screen 45x33", 0, 33)]


def fmt(rng, lost):
    if rng is None:
        return "not visible"
    if not lost:
        return "fully visible (rows %d..%d)" % rng
    return "rows %d..%d, character rows %s lost" % (rng[0], rng[1], ",".join(map(str, lost)))


def osm_checks():
    print("OSM placement (transcription of vga_osm.vhd rows and video_overlay.vhd vga_row)")
    # spec section 7.3, reproduced literally
    t73 = [
        ("NTSC VGA 100 %, options", (500, False, 0, 0, 0, 31), ((0, 495), [])),
        ("NTSC VGA 100 %, main", (500, False, 0, 0, 0, 33), (None, [31, 32])),
        ("NTSC VGA 89 %, main", (500, False, 0, 1, 0, 33), ((29, 498), [])),
        ("NTSC 480p 100 %, options", (480, False, 0, 0, 0, 31), (None, [30])),
        ("NTSC 480p 100 %, main", (480, False, 0, 0, 0, 33), (None, [30, 31, 32])),
        ("NTSC 480p 89 %, options", (480, False, 0, 1, 0, 31), ((27, 468), [])),
        ("NTSC 480p 89 %, main", (480, False, 0, 1, 0, 33), (None, [31, 32])),
        ("NTSC 480p 89 % + 24 up, options", (480, False, 24, 1, 0, 31), ((3, 444), [])),
        ("NTSC 480p 89 % + 24 up, main", (480, False, 24, 1, 0, 33), ((5, 474), [])),
        # s = 0 cases that tb_osm_place.vhd simulates with the real video_overlay
        ("NTSC VGA 15 kHz 100 %, options", (250, True, 0, 0, 0, 31), ((0, 247), [])),
        ("NTSC VGA 15 kHz 100 %, main", (250, True, 0, 0, 0, 33), ((0, 249), [31, 32])),
        ("NTSC 480p 100 % + 24 up, options", (480, False, 24, 0, 0, 31), ((0, 471), [0, 1])),
        ("NTSC 480p 100 % + 24 up, main", (480, False, 24, 0, 0, 33), ((0, 479), [0, 1, 31, 32])),
        ("PAL VGA 100 %, main", (540, False, 0, 0, 0, 33), ((0, 527), [])),
    ]
    print("  spec section 7.3:")
    for name, args, (exp_rng, exp_lost) in t73:
        rng, lost = osm_summary(*args)
        print("    %-34s %s" % (name, fmt(rng, lost)))
        check(lost == exp_lost, "7.3 %s: lost %s, expected %s" % (name, lost, exp_lost))
        if exp_rng is not None:
            check(rng == exp_rng, "7.3 %s: rows %s, expected %s" % (name, rng, exp_rng))
    # every output, every user index, with the change of section 7.4
    print("  with the change of section 7.4, user OSM scaling s = 0 .. 8:")
    for oname, rows, r15, force, shift in OUTPUTS:
        for bname, by, bdy in BOXES:
            cells = []
            for s in range(9):
                eff = max(s, 1) if force else s
                rng, lost = osm_summary(rows, r15, shift, eff, by, bdy)
                cells.append("%d:%s" % (s, "ok" if not lost else "LOST" + ",".join(map(str, lost))))
                check(not lost, "%s, %s, s=%d: character rows %s lost" % (oname, bname, s, lost))
            print("    %-28s %-18s %s" % (oname, bname, " ".join(cells)))


# --------------------------------------------------------------------------------------------
# tb_window_av VCD
# --------------------------------------------------------------------------------------------

def parse_vcd(path):
    ids = {}
    changes = []        # (time, name, value)
    t = 0
    with open(path) as f:
        in_defs = True
        for line in f:
            line = line.strip()
            if in_defs:
                m = re.match(r"\$var\s+\S+\s+\d+\s+(\S+)\s+(\S+)", line)
                if m:
                    ids[m.group(1)] = re.sub(r"\[.*\]", "", m.group(2))
                if line.startswith("$enddefinitions"):
                    in_defs = False
                continue
            if line.startswith("#"):
                t = int(line[1:])
            elif line.startswith("b"):
                v, i = line[1:].split()
                changes.append((t, ids[i], v))
            elif line and line[0] in "01UXZWLH-" and line[1:] in ids:
                changes.append((t, ids[line[1:]], line[0]))
    return changes


# position in video_mode_type of the mode that each raw mode is derived from
RAW_BASE = {10: 0, 11: 2, 12: 3, 13: 7, 14: 8, 15: 9}
NTSC_MODES = (7, 8, 9, 13, 14, 15)
NTSC480_MODES = (8, 9, 14, 15)

# The C64 frame (CORE/vhdl/clk.vhd, doc/dev-hdmi-raw/research/R2-local-map.md section 0):
# clock in Hz and core clock cycles per frame
C64_FRAME = {"PAL": (Fraction(283750000, 9), 63 * 312 * 32), "NTSC": (Fraction(360000000, 11), 65 * 263 * 32)}

# The raw records (doc/dev-hdmi-raw/SPEC.md 4.1): base record, the fields that differ,
# machine standard, surplus of the core frame in pixel clocks per frame (SPEC 4.2, 0 = exact)
RAW_RECORDS = {
    "C_HDMI_720p_50_RAW": ("C_HDMI_720p_50", {"CLK_KHZ": 74444, "CLK_SEL": "1000", "CTS_FRAC_N": 4, "CTS_FRAC_D": 9},
                           "PAL", Fraction("196.969")),
    "C_HDMI_576p_50_RAW": ("C_HDMI_576p_50", {"CLK_KHZ": 27023, "CLK_SEL": "1001", "CTS_FRAC_N": 17, "CTS_FRAC_D": 21,
                                              "V_FP": 4}, "PAL", 0),
    "C_HDMI_720p_5994_RAW": ("C_HDMI_720p_5994", {"CLK_KHZ": 74062, "CLK_SEL": "1010", "CTS_FRAC_N": 1, "CTS_FRAC_D": 2},
                             "NTSC", Fraction("462.917")),
    "C_HDMI_720x480p_5994_RAW": ("C_HDMI_720x480p_5994", {"CLK_KHZ": 27000, "CLK_SEL": "0001", "CTS_FRAC_N": 0,
                                                          "CTS_FRAC_D": 1, "V_BP": 31}, "NTSC", 0),
}


def window_checks(repo, vcd):
    pkg = read(repo, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd")
    recs = parse_records(pkg)
    members = parse_members(pkg)
    _, vector, _, _ = parse_framework(read(repo, "M2M/vhdl/framework.vhd"))
    changes = parse_vcd(vcd)
    state = {}
    samples = {}
    phase = None
    for t, name, v in changes:
        if name == "tb_phase":
            if phase is not None:
                samples[phase] = dict(state)
            phase = int(v, 2)
        state[name] = v
    win = {   # NTSC spec section 6.3 for 7 .. 9, today's values for 0 .. 6; a raw mode has the window of its base
        0: (160, 1119, 0, 719), 1: (160, 1119, 0, 719), 2: (0, 719, 0, 575), 3: (0, 719, 18, 558),
        4: (0, 639, 0, 479), 5: (0, 719, 0, 479), 6: (0, 799, 0, 599),
        7: (160, 1119, 0, 719), 8: (0, 719, 0, 479), 9: (0, 719, 15, 465)}
    for m, base in RAW_BASE.items():
        win[m] = win[base]
    # values that a raw mode must share with its base mode (sampled at the same step)
    same_as_base = ("hdmi_hmin", "hdmi_hmax", "hdmi_vmin", "hdmi_vmax", "hdmi_htotal", "hdmi_shift",
                    "hdmi_osm_vshift", "vic", "aspect", "hs_pol", "vs_pol", "video_ntsc", "qnice_ntsc",
                    "hdmi_osm_ntsc480", "x_min", "x_max", "y_min", "y_max", "hdmi_osm_cfg_scaling_i",
                    "video_osm_cfg_scaling_i", "hdmi_hsstart", "hdmi_hsend", "hdmi_hdisp", "hdmi_vdisp")
    print("tb_window_av: %d steps sampled" % len(samples))
    print("  mode                        zoom  hmin  hmax vmin vmax  htot x vtot ascal  CTS   VIC AR  shift vshift ntsc raw crop window        OSM s:HDMI/VGA")
    n = 0
    for m in range(16):
        r = recs[vector[m]]
        is_ntsc = m in NTSC_MODES
        is_480n = m in NTSC480_MODES
        is_raw = m >= 10
        for z in (0, 1):
            osm = []
            for s in range(9):
                if z == 1 and s > 0:
                    continue
                key = 1000 + 100 * m + 10 * z + s
                if key not in samples:
                    check(False, "step %d missing in the VCD" % key)
                    continue
                st = samples[key]
                def iv(k, st=st):
                    v = st[k]
                    if set(v) - set("01"):
                        return None
                    n = int(v, 2)
                    return n - (1 << 32) if len(v) == 32 and v[0] == "1" else n   # VHDL integer
                n += 1
                exp_w = win[m] if z == 0 else (0, r["H_PIXELS"] - 1, 0, r["V_PIXELS"] - 1)
                got_w = tuple(iv(k) for k in ("hdmi_hmin", "hdmi_hmax", "hdmi_vmin", "hdmi_vmax"))
                check(got_w == exp_w, "mode %d zoom %d: window %s, expected %s" % (m, z, got_w, exp_w))
                check(iv("hdmi_htotal") == htotal(r) and iv("hdmi_vtotal") == vtotal(r),
                      "mode %d: total %sx%s" % (m, iv("hdmi_htotal"), iv("hdmi_vtotal")))
                check(iv("hdmi_hsstart") == r["H_PIXELS"] + r["H_FP"] and
                      iv("hdmi_hsend") == r["H_PIXELS"] + r["H_FP"] + r["H_PULSE"] and
                      iv("hdmi_hdisp") == r["H_PIXELS"] and
                      iv("hdmi_vsstart") == r["V_PIXELS"] + r["V_FP"] and
                      iv("hdmi_vsend") == r["V_PIXELS"] + r["V_FP"] + r["V_PULSE"] and
                      iv("hdmi_vdisp") == r["V_PIXELS"], "mode %d: sync positions" % m)
                # the scaler gets hdmi_htotal unchanged outside the raw modes (and from the
                # pass-through stand-in of the genlock in the raw modes)
                check(iv("hdmi_ascal_htotal") == htotal(r), "mode %d: scaler htotal %s" % (m, iv("hdmi_ascal_htotal")))
                check(st["hdmi_raw"] == ("1" if is_raw else "0"), "mode %d: hdmi_raw %s" % (m, st["hdmi_raw"]))
                check(iv("hdmi_genlock_target") == 2 * r["CLK_KHZ"], "mode %d: genlock target" % m)
                cts = iv("audio_pcm_cts")
                if r["CTS_FRAC_N"] == 0:
                    check(cts == r["CLK_KHZ"], "mode %d: CTS %s" % (m, cts))
                else:
                    check(cts in (r["CLK_KHZ"], r["CLK_KHZ"] + 1), "mode %d: CTS %s" % (m, cts))
                check(iv("vic") == r["CEA_CTA_VIC"] and st["aspect"] == r["ASPECT"], "mode %d: VIC/aspect" % m)
                check(st["hs_pol"] == r["H_POL"] and st["vs_pol"] == r["V_POL"], "mode %d: sync polarity" % m)
                check(iv("hdmi_shift") == r["H_PIXELS"] - 720, "mode %d: hdmi_shift" % m)
                check(iv("hdmi_osm_vshift") == (24 if is_480n else 0), "mode %d: vshift" % m)
                check(st["video_ntsc"] == ("1" if is_ntsc else "0") and st["qnice_ntsc"] == st["video_ntsc"],
                      "mode %d: video_ntsc %s" % (m, st["video_ntsc"]))
                check(st["hdmi_osm_ntsc480"] == ("1" if is_480n else "0"), "mode %d: hdmi_osm_ntsc480" % m)
                crop = tuple(iv(k) for k in ("x_min", "x_max", "y_min", "y_max"))
                check(crop == ((30, 377, 22, 229) if is_ntsc else (19, 366, 31, 238)), "mode %d: crop %s" % (m, crop))
                hs, vs = iv("hdmi_osm_cfg_scaling_i"), iv("video_osm_cfg_scaling_i")
                check(hs == (max(s, 1) if is_480n else s), "mode %d s=%d: HDMI OSM scaling %s" % (m, s, hs))
                check(vs == (max(s, 1) if is_ntsc else s), "mode %d s=%d: VGA OSM scaling %s" % (m, s, vs))
                if is_raw:
                    bkey = 1000 + 100 * RAW_BASE[m] + 10 * z + s
                    if bkey in samples:
                        diff = [k for k in same_as_base if samples[bkey].get(k) != st.get(k)]
                        check(not diff, "mode %d differs from its base mode %d in %s" % (m, RAW_BASE[m], diff))
                osm.append("%d:%d/%d" % (s, hs, vs))
                if s == 0:
                    line = "  %-27s %d   %5d %5d %4d %4d  %4d x %3d  %4d %6d %3d %s %5d %6d   %s   %s  %3d..%3d/%3d..%3d" % (
                        members[m], z, got_w[0], got_w[1], got_w[2], got_w[3], iv("hdmi_htotal"),
                        iv("hdmi_vtotal"), iv("hdmi_ascal_htotal"), cts, iv("vic"), st["aspect"], iv("hdmi_shift"),
                        iv("hdmi_osm_vshift"), st["video_ntsc"], st["hdmi_raw"], crop[0], crop[1], crop[2], crop[3])
            print(line + "  " + " ".join(osm))
    r7 = recs["C_HDMI_720p_5994"]
    check(htotal(r7) == 1650 and vtotal(r7) == 750 and r7["CLK_KHZ"] == 74167, "C_HDMI_720p_5994 1650x750/74167")
    print("  %d steps checked; every raw mode compared with its base mode in %d values" % (n, len(same_as_base)))


def exact_khz(vo, sel):
    """Pixel clock in kHz (Fraction) of the table that CLK_SEL loads, and the decoded parameters."""
    m, d, o0, o1, f = mmcm_freq(drp_table(vo, sel))
    return Fraction(100000) * Fraction(m) / d / Fraction(o1), (m, d, o0, o1)


def source_checks(repo):
    pkg = read(repo, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd")
    recs = parse_records(pkg)
    members = parse_members(pkg)
    print("video_mode_type: %d members: %s" % (len(members), ", ".join(members)))
    check(len(members) == 16, "video_mode_type does not have 16 members")
    check(members[7:10] == ["C_VIDEO_HDMI_16_9_5994", "C_VIDEO_HDMI_4_3_5994", "C_VIDEO_HDMI_5_4_5994"],
          "the three NTSC members are not at positions 7 to 9")
    check(members[10:] == ["C_VIDEO_HDMI_16_9_50_RAW", "C_VIDEO_HDMI_4_3_50_RAW", "C_VIDEO_HDMI_5_4_50_RAW",
                           "C_VIDEO_HDMI_16_9_5994_RAW", "C_VIDEO_HDMI_4_3_5994_RAW", "C_VIDEO_HDMI_5_4_5994_RAW"],
          "the six raw members are not appended at positions 10 to 15")
    for m, base in RAW_BASE.items():
        check(members[m] == members[base] + "_RAW", "%s is not the raw member of %s" % (members[m], members[base]))
    r = recs["C_HDMI_720p_5994"]
    print("C_HDMI_720p_5994: %d x %d total, CLK_KHZ %d, CLK_SEL %s, VIC %d, ASPECT %s, pol %s/%s, %.6f Hz" % (
        htotal(r), vtotal(r), r["CLK_KHZ"], r["CLK_SEL"], r["CEA_CTA_VIC"], r["ASPECT"], r["H_POL"], r["V_POL"],
        r["CLK_KHZ"] * 1000.0 / (htotal(r) * vtotal(r))))
    check(htotal(r) == 1650 and vtotal(r) == 750, "C_HDMI_720p_5994 is not 1650 x 750")
    check(r["CLK_KHZ"] == 74167 and r["CLK_SEL"] == "0110" and r["CEA_CTA_VIC"] == 4 and r["ASPECT"] == "10",
          "C_HDMI_720p_5994 CLK_KHZ / CLK_SEL / VIC / ASPECT")
    check(r["H_POL"] == recs["C_HDMI_720p_50"]["H_POL"] and r["V_POL"] == recs["C_HDMI_720p_50"]["V_POL"],
          "C_HDMI_720p_5994 polarity differs from C_HDMI_720p_50")
    for name, rec in sorted(recs.items()):
        check(len(rec["CLK_SEL"]) == 4, "%s: CLK_SEL %s is not 4 bits" % (name, rec["CLK_SEL"]))
        if name not in RAW_RECORDS:
            check(rec["CTS_FRAC_N"] == 0 and rec["CTS_FRAC_D"] == 1, "%s: CTS_FRAC is not 0 / 1" % name)

    size, vector, dec, default = parse_framework(read(repo, "M2M/vhdl/framework.vhd"))
    print("framework VIDEO_MODE_VECTOR(0 to %d): %s" % (size, ", ".join(vector)))
    check(size == 15 and len(vector) == 16, "VIDEO_MODE_VECTOR is not 0 to 15")
    for i, mem in enumerate(members):
        rec = dec.get(mem, default)
        check(i < len(vector) and rec == vector[i],
              "framework clock select: %s -> %s, vector(%d) = %s" % (mem, rec, i, vector[i] if i < len(vector) else "-"))
    print("framework clock select: every member maps to VIDEO_MODE_VECTOR(index); NTSC and raw: %s" %
          ", ".join("%s -> %s (CLK_SEL %s)" % (m, dec.get(m, default), recs[dec.get(m, default)]["CLK_SEL"])
                    for m in members[7:]))

    vo = read(repo, "M2M/vhdl/controllers/HDMI/video_out_clock.vhd")
    # 0010 and 0001 are field-proven (720p50, 576p50 and 480p): they validate the decoder
    for sel, name in (("0010", "C_HDMI_720p_50"), ("0001", "C_HDMI_576p_50"), ("0110", "C_HDMI_720p_5994")):
        m, d, o0, o1, f = mmcm_freq(drp_table(vo, sel))
        print("video_out_clock CLK_SEL %s: CLKFBOUT_MULT_F %.3f, DIVCLK %d, CLKOUT0 %.3f, CLKOUT1 %.3f -> pixel %.6f MHz, serializer %.4f MHz = %.1f x pixel; %s CLK_KHZ %d" % (
            sel, m, d, o0, o1, f, f * o1 / o0, o1 / o0, name, recs[name]["CLK_KHZ"]))
    m, d, o0, o1, f = mmcm_freq(drp_table(vo, "0110"))
    check((m, d, o1) == (22.25, 3, 10.0), "CLK_SEL 0110 is not 22.25 / 3 / 10")
    print("720p59.94 frame rate: %.6f Hz (pixel clock %.1f ppm from 74.25/1.001 MHz)" % (
        f * 1e6 / (1650 * 750), (f / (74.25 / 1.001) - 1) * 1e6))

    # every record: the table of its CLK_SEL gives CLK_KHZ (rounded) and CLK_KHZ + fraction (exact if not 0)
    for name, rec in sorted(recs.items()):
        khz, (m, d, o0, o1) = exact_khz(vo, rec["CLK_SEL"])
        frac = Fraction(rec["CTS_FRAC_N"], rec["CTS_FRAC_D"])
        print("record %-26s CLK_SEL %s: M %.3f D %d O0 %g O1 %g -> %.6f kHz; CLK_KHZ %d + %s" % (
            name, rec["CLK_SEL"], m, d, o0, o1, float(khz), rec["CLK_KHZ"], frac))
        check(abs(Fraction(o1) / Fraction(o0) - 5) == 0, "%s: serializer clock is not 5x" % name)
        if name in RAW_RECORDS:
            # CLK_KHZ is the integer part, CTS_FRAC the exact rest
            check(0 <= frac < 1 and khz == rec["CLK_KHZ"] + frac,
                  "%s: CLK_KHZ + CTS_FRAC = %s kHz, table gives %s kHz" % (name, rec["CLK_KHZ"] + frac, khz))
        else:
            check(frac == 0 and abs(khz - rec["CLK_KHZ"]) <= Fraction(1, 2),
                  "%s: CLK_KHZ %d is not the pixel clock %.4f kHz rounded" % (name, rec["CLK_KHZ"], float(khz)))
    # the codes without a table load the table of 0010
    for code in range(11, 16):
        sel = format(code, "04b")
        check(drp_table(vo, sel) == drp_table(vo, "0010") and drp_table(vo, sel),
              "CLK_SEL %s does not load the table of 0010" % sel)
    print("CLK_SEL 1011 to 1111: the table of 0010 (74.25 MHz)")

    # the raw records against their base records, and their frame rates
    for name, (base, delta, std, surplus) in RAW_RECORDS.items():
        rec, b = recs[name], recs[base]
        diff = {k: rec[k] for k in rec if rec[k] != b.get(k)}
        exp = {k: v for k, v in delta.items() if v != b.get(k)}
        check(diff == exp, "%s differs from %s in %s, expected %s" % (name, base, diff, exp))
        khz, _ = exact_khz(vo, rec["CLK_SEL"])
        clk, cyc = C64_FRAME[std]
        core_frame = khz * 1000 * cyc / clk                         # core frame in pixel clocks
        got = core_frame - htotal(rec) * vtotal(rec)
        print("raw %-26s %d x %d, pixel clock %.6f MHz, frame %.6f Hz, C64 %.6f Hz, surplus %.3f pixel clocks per frame" % (
            name, htotal(rec), vtotal(rec), float(khz / 1000), float(khz * 1000 / (htotal(rec) * vtotal(rec))),
            float(clk / cyc), float(got)))
        if surplus == 0:
            check(got == 0, "%s: frame rate is not exactly the C64 frame rate" % name)
        else:
            check(abs(got - surplus) < Fraction(1, 1000), "%s: surplus %.4f, SPEC 4.2 says %s" % (name, float(got), surplus))

    osm_checks()


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    repo = sys.argv[1]
    if len(sys.argv) >= 4 and sys.argv[2] == "--window-vcd":
        window_checks(repo, sys.argv[3])
    else:
        source_checks(repo)
    if FAILS:
        print("RESULT: FAIL %d mismatch(es)" % len(FAILS))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
