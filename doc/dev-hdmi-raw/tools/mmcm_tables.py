#!/usr/bin/env python3
"""
mmcm_tables.py -- DRP tables for the HDMI MMCM of video_out_clock.vhd (XAPP888)

Python 3, standard library only. Run from anywhere; paths default to this repo.

Usage:
  mmcm_tables.py check [--vhdl FILE] [-v]
      Parse every table of M2M/vhdl/controllers/HDMI/video_out_clock.vhd,
      regenerate it from the parameters in its comment header and compare
      address, mask and data of every row bit by bit (style "m2m"). Also
      lists every word in which the pure XAPP888 reference ROM (style
      "xapp888") differs, and decodes every table with the independent
      decoder doc/dev-ntsc/tools/w2_checks.py. Exit code 0 only if all match.

  mmcm_tables.py gen M D O0 O1 [--base 0xNN] [--desired MHZ] [--note TEXT]
                     [--style m2m|xapp888] [--bandwidth OPTIMIZED|HIGH|LOW|LOW_SS]
                     [--addr-style hex|hex9|int]
      Print one table in the VHDL format of video_out_clock.vhd.
      M = CLKFBOUT_MULT_F (2.000 .. 64.000, steps of 0.125), D = DIVCLK_DIVIDE,
      O0 = CLKOUT0_DIVIDE_F (serializer clock), O1 = CLKOUT1_DIVIDE (pixel clock).

  mmcm_tables.py new [--style m2m|xapp888] [--first-sel N] [--addr-style ...] [--alternatives]
      The tables for the HDMI modes at the C64's native frame rate (PAL 720p,
      PAL 576p, NTSC 720p for the clk_sel codes 1000, 1001, 1010), with limit
      checks, a w2_checks.py decode, the closest existing table and the frame
      rates. --alternatives adds the settings that were considered and not used.

  mmcm_tables.py limits M D O0 O1
      MMCM limit checks for xc7a200t speed grade -2 (DS181 Table 37, UG472 Table 3-7).

  mmcm_tables.py equiv M D O0 O1
      Every legal (M, D, O0 = n, O1 = 5n) that gives exactly the same pixel clock.

Styles:
  m2m      reproduces the conventions of the existing tables (made with the
           video_out_clock.xls spreadsheet of the tyto2 project): reserved bit 12 of
           ClkReg1 written as 1 (masked, no effect), mask 0x8000 for every ClkReg2,
           EDGE of DIVCLK always 0, EDGE set for an output divider of 1, and the
           top two bits of LockCnt and LockSatHigh stored as {0, bit 9}.
  xapp888  the ROM words of the XAPP888 reference design mmcme2_drp.v
           (mmcme2_drp_func.h v1.31): exact lock words, DIVCLK EDGE, masks
           0xFC00 / 0xC000 for the reserved bits of ClkReg2, bit 12 = 0.
Both styles keep the row order of video_out_clock.vhd; the order does not matter
because the MMCM is held in reset while the table is written.

Only phase 0 and 50 % duty cycle are implemented (all that video_out_clock uses).
"""

import argparse
import importlib.util
import os
import re
import sys
from fractions import Fraction as F

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
VHDL_DEFAULT = os.path.join(REPO, "M2M", "vhdl", "controllers", "HDMI", "video_out_clock.vhd")
W2_CHECKS = os.path.join(REPO, "doc", "dev-ntsc", "tools", "w2_checks.py")

F_REF = F(100)          # MHz, board oscillator (generic fref of video_out_clock)

# --------------------------------------------------------------------------------------------
# Transcription of the XAPP888 functions (mmcme2_drp_func.h v1.31, 19 Sep 2018)
# --------------------------------------------------------------------------------------------

FRAC_PRECISION = 10
MASK32 = 0xFFFFFFFF

# mmcm_lock_lookup: LockRefDly(5) LockFBDly(5) LockCnt(10) LockSatHigh(10) UnlockCnt(10), index = M (1..64)
_LOCK = """
00110_00110_1111101000_1111101001_0000000001
00110_00110_1111101000_1111101001_0000000001
01000_01000_1111101000_1111101001_0000000001
01011_01011_1111101000_1111101001_0000000001
01110_01110_1111101000_1111101001_0000000001
10001_10001_1111101000_1111101001_0000000001
10011_10011_1111101000_1111101001_0000000001
10110_10110_1111101000_1111101001_0000000001
11001_11001_1111101000_1111101001_0000000001
11100_11100_1111101000_1111101001_0000000001
11111_11111_1110000100_1111101001_0000000001
11111_11111_1100111001_1111101001_0000000001
11111_11111_1011101110_1111101001_0000000001
11111_11111_1010111100_1111101001_0000000001
11111_11111_1010001010_1111101001_0000000001
11111_11111_1001110001_1111101001_0000000001
11111_11111_1000111111_1111101001_0000000001
11111_11111_1000100110_1111101001_0000000001
11111_11111_1000001101_1111101001_0000000001
11111_11111_0111110100_1111101001_0000000001
11111_11111_0111011011_1111101001_0000000001
11111_11111_0111000010_1111101001_0000000001
11111_11111_0110101001_1111101001_0000000001
11111_11111_0110010000_1111101001_0000000001
11111_11111_0110010000_1111101001_0000000001
11111_11111_0101110111_1111101001_0000000001
11111_11111_0101011110_1111101001_0000000001
11111_11111_0101011110_1111101001_0000000001
11111_11111_0101000101_1111101001_0000000001
11111_11111_0101000101_1111101001_0000000001
11111_11111_0100101100_1111101001_0000000001
11111_11111_0100101100_1111101001_0000000001
11111_11111_0100101100_1111101001_0000000001
11111_11111_0100010011_1111101001_0000000001
11111_11111_0100010011_1111101001_0000000001
11111_11111_0100010011_1111101001_0000000001
""" + "11111_11111_0011111010_1111101001_0000000001\n" * 28
LOCK_TABLE = [int(s.replace("_", ""), 2) for s in _LOCK.split()]

# mmcm_filter_lookup: CP(4) RES(4) LFHF(2), index = M (1..64)
_FILTER_LOW = ("0010_1111_00 " * 4 + "0010_0111_00 0010_1011_00 0010_1101_00 0010_0011_00 "
               "0010_0101_00 0010_0101_00 0010_1001_00 " + "0010_1110_00 " * 4 + "0010_0001_00 " * 3 +
               "0010_0110_00 " * 7 + "0010_1010_00 " * 5 + "0010_1100_00 " * 17 + "0010_0010_00 " * 17)
_FILTER_HIGH = ("0010_1111_00 0100_1111_00 0101_1011_00 0111_0111_00 1101_0111_00 1110_1011_00 "
                "1110_1101_00 1111_0011_00 1110_0101_00 1111_0101_00 1111_1001_00 1101_0001_00 " +
                "1111_1001_00 " * 4 + "1111_0101_00 " * 2 + "1100_0001_00 " * 3 + "0101_1100_00 " * 4 +
                "0011_0100_00 " * 16 + "0010_1000_00 " * 5 + "0111_0001_00 " * 2 + "0100_1100_00 " * 4 +
                "0110_0001_00 " * 2 + "0101_0110_00 " * 3 + "0010_0100_00 " * 4 +
                "0100_1010_00 0011_1100_00 0011_1100_00")
FILTER_TABLES = {
    "LOW": [int(s.replace("_", ""), 2) for s in _FILTER_LOW.split()],
    "HIGH": [int(s.replace("_", ""), 2) for s in _FILTER_HIGH.split()],
}
FILTER_TABLES["OPTIMIZED"] = FILTER_TABLES["HIGH"]                       # identical in v1.04 and v1.31
FILTER_TABLES["LOW_SS"] = [v | 0b11 for v in FILTER_TABLES["LOW"]]       # v1.31: LFHF = 11
assert len(LOCK_TABLE) == 64 and all(len(t) == 64 for t in FILTER_TABLES.values())


def round_frac(decimal, precision):
    """round_frac(): Verilog vector [32:1], so decimal[k] is bit k-1 of the integer."""
    if (decimal >> (FRAC_PRECISION - precision - 1)) & 1:
        return (decimal + (1 << (FRAC_PRECISION - precision))) & MASK32
    return decimal


def mmcm_divider(divide, duty_cycle=50000):
    """mmcm_divider(): returns (w_edge, no_count, high_time, low_time)."""
    if divide >= 64:     # duty-cycle clamp of v1.31 for divide >= 64
        dmin = ((divide - 64) * 100000) // divide
        dmax = int((64.5 / divide) * 100000)
        duty_cycle = min(max(duty_cycle, dmin), dmax)
    duty_fix = ((duty_cycle << FRAC_PRECISION) & MASK32) // 100000
    if divide == 1:
        return 0, 1, 1, 1
    temp = round_frac((duty_fix * divide) & MASK32, 1)
    high = (temp >> FRAC_PRECISION) & 0x7F          # temp[FRAC_PRECISION+7 : FRAC_PRECISION+1]
    w_edge = (temp >> (FRAC_PRECISION - 1)) & 1      # temp[FRAC_PRECISION]
    if high == 0:
        high, w_edge = 1, 0
    if high == divide:
        high, w_edge = divide - 1, 1
    low = divide - high
    return w_edge, 0, high & 0x3F, low & 0x3F


def mmcm_count_calc(divide):
    """mmcm_count_calc() for phase 0: returns (reg1, reg2) = (lower, upper) 16-bit words.
    mmcm_phase(divide, 0) gives mx = 0, phase_mux = 0, delay_time = 0."""
    edge, no_count, high, low = mmcm_divider(divide)
    reg1 = (0 << 13) | (0 << 12) | (high << 6) | low
    reg2 = (0 << 8) | (edge << 7) | (no_count << 6) | 0
    return reg1, reg2


def mmcm_frac_count_calc(divide, frac8):
    """mmcm_frac_count_calc() for phase 0, 50 %: returns (reg1, reg2, shared4).
    frac8 is the fraction in eighths (frac / 125 in the Verilog). shared4 =
    {pm_fall_frac_filtered[2:0], wf_fall_frac} = bits [35:32] of the return value."""
    even_high = divide >> 1
    even_low = even_high
    odd = divide - even_high - even_low
    oaf = 8 * odd + frac8
    lt = even_high - (1 if oaf <= 9 else 0)
    ht = even_low - (1 if oaf <= 8 else 0)
    pm_fall = ((odd & 0x7F) << 2) + (frac8 >> 1)
    wf_fall = 1 if ((2 <= oaf <= 9) or (frac8 == 1 and divide == 2)) else 0
    wf_rise = 1 if (1 <= oaf <= 8) else 0
    a_per_in_octets = 8 * divide + frac8
    a_phase = (0 + 10) * a_per_in_octets // 360000
    pm_rise = 0 if (a_phase & 0xFF) == 0 else (a_phase & 0xFF) - (a_phase & 0xF8)
    dt = (((0 + 10) * a_per_in_octets // 8) // 360000) & 0xFF
    pm_rise_f = pm_rise - 8 if pm_rise >= 8 else pm_rise
    pm_fall_frac = pm_fall + pm_rise
    pm_fall_f = (pm_fall + pm_rise - (pm_fall_frac & 0xF8)) & 0xFF
    reg1 = ((pm_rise_f & 7) << 13) | (0 << 12) | ((ht & 0x3F) << 6) | (lt & 0x3F)
    reg2 = (0 << 15) | ((frac8 & 7) << 12) | (1 << 11) | (wf_rise << 10) | (0 << 6) | (dt & 0x3F)
    shared4 = ((pm_fall_f & 7) << 1) | wf_fall
    return reg1, reg2, shared4


def lock_lookup(m_int):
    return LOCK_TABLE[m_int - 1]


def filter_lookup(m_int, bandwidth):
    return FILTER_TABLES[bandwidth][m_int - 1]


# --------------------------------------------------------------------------------------------
# Table generator
# --------------------------------------------------------------------------------------------

ROW_NAMES = [
    (0x06, "CLKOUT5 Register 1"), (0x07, "CLKOUT5 Register 2"),
    (0x08, "CLKOUT0 Register 1"), (0x09, "CLKOUT0 Register 2"),
    (0x0A, "CLKOUT1 Register 1"), (0x0B, "CLKOUT1 Register 2"),
    (0x0C, "CLKOUT2 Register 1"), (0x0D, "CLKOUT2 Register 2"),
    (0x0E, "CLKOUT3 Register 1"), (0x0F, "CLKOUT3 Register 2"),
    (0x10, "CLKOUT4 Register 1"), (0x11, "CLKOUT4 Register 2"),
    (0x12, "CLKOUT6 Register 1"), (0x13, "CLKOUT6 Register 2"),
    (0x14, "CLKFBOUT Register 1"), (0x15, "CLKFBOUT Register 2"),
    (0x16, "DIVCLK Register"),
    (0x18, "Lock Register 1"), (0x19, "Lock Register 2"), (0x1A, "Lock Register 3"),
    (0x28, "Power Register"),
    (0x4E, "Filter Register 1"), (0x4F, "Filter Register 2"),
]
NAME = dict(ROW_NAMES)

MASKS_M2M = {0x06: 0x1000, 0x07: 0x8000, 0x08: 0x1000, 0x09: 0x8000, 0x0A: 0x1000, 0x0B: 0x8000,
             0x0C: 0x1000, 0x0D: 0x8000, 0x0E: 0x1000, 0x0F: 0x8000, 0x10: 0x1000, 0x11: 0x8000,
             0x12: 0x1000, 0x13: 0x8000, 0x14: 0x1000, 0x15: 0x8000, 0x16: 0xC000,
             0x18: 0xFC00, 0x19: 0x8000, 0x1A: 0x8000, 0x28: 0x0000, 0x4E: 0x66FF, 0x4F: 0x666F}
MASKS_XAPP = dict(MASKS_M2M)
MASKS_XAPP.update({0x07: 0xC000, 0x0B: 0xFC00, 0x0D: 0xFC00, 0x0F: 0xFC00, 0x11: 0xFC00, 0x13: 0xC000})


def to_eighths(x, what):
    v = F(str(x))
    if (v * 8).denominator != 1:
        raise ValueError("%s = %s is not a multiple of 0.125" % (what, x))
    return v


def lock_m2m(v10):
    """The spreadsheet quirk: bits [9:8] of a 10-bit lock field become {0, bit 9}."""
    return (v10 & 0xFF) | (((v10 >> 9) & 1) << 8)


def counter_words(divide_f, frac_allowed):
    """(reg1, reg2, shared4 or None) for an output / feedback counter."""
    di = int(divide_f)
    f8 = int((divide_f - di) * 8)
    if f8:
        if not frac_allowed:
            raise ValueError("fractional divide only on CLKOUT0 and CLKFBOUT")
        return mmcm_frac_count_calc(di, f8)
    r1, r2 = mmcm_count_calc(di)
    return r1, r2, None


def table(mult, divclk, o0, o1, style="m2m", bandwidth="OPTIMIZED", unused_divide=10):
    """Return [(drp_addr, data, mask)] in the row order of video_out_clock.vhd."""
    m = to_eighths(mult, "CLKFBOUT_MULT_F")
    o0 = to_eighths(o0, "CLKOUT0_DIVIDE_F")
    if F(str(o1)).denominator != 1:
        raise ValueError("CLKOUT1_DIVIDE must be an integer")
    o1 = int(F(str(o1)))
    d = int(divclk)
    m2m = style == "m2m"
    masks = MASKS_M2M if m2m else MASKS_XAPP

    fb1, fb2, fb_sh = counter_words(m, True)
    c01, c02, c0_sh = counter_words(o0, True)
    c11, c12, _ = counter_words(F(o1), False)
    u1, u2, _ = counter_words(F(unused_divide), False)       # CLKOUT2..6 (not used by the design)
    dv1, dv2 = mmcm_count_calc(d)

    if m2m:
        if int(o0) == 1 and o0.denominator == 1:
            c02 |= 0x0080       # EDGE with NO_COUNT for a divide of 1
        if o1 == 1:
            c12 |= 0x0080

    c5_2 = u2 if c0_sh is None else (u2 & 0xC000) | (c0_sh << 10) | (u2 & 0x03FF)
    c6_2 = u2 if fb_sh is None else (u2 & 0xC000) | (fb_sh << 10) | (u2 & 0x03FF)

    edge_d, nocount_d = (dv2 >> 7) & 1, (dv2 >> 6) & 1
    if m2m:
        edge_d = 0
    div = (edge_d << 13) | (nocount_d << 12) | dv1

    lk = lock_lookup(int(m))
    ref_dly, fb_dly = (lk >> 35) & 0x1F, (lk >> 30) & 0x1F
    lock_cnt, sat_high, unlock = (lk >> 20) & 0x3FF, (lk >> 10) & 0x3FF, lk & 0x3FF
    if m2m:
        lock_cnt, sat_high, unlock = lock_m2m(lock_cnt), lock_m2m(sat_high), lock_m2m(unlock)
    fl = filter_lookup(int(m), bandwidth)
    fb = [(fl >> i) & 1 for i in range(10)]
    filt1 = (fb[9] << 15) | (fb[8] << 12) | (fb[7] << 11) | (fb[6] << 8)
    filt2 = (fb[5] << 15) | (fb[4] << 12) | (fb[3] << 11) | (fb[2] << 8) | (fb[1] << 7) | (fb[0] << 4)

    words = {
        0x06: u1, 0x07: c5_2, 0x08: c01, 0x09: c02, 0x0A: c11, 0x0B: c12,
        0x0C: u1, 0x0D: u2, 0x0E: u1, 0x0F: u2, 0x10: u1, 0x11: u2, 0x12: u1, 0x13: c6_2,
        0x14: fb1, 0x15: fb2, 0x16: div,
        0x18: lock_cnt, 0x19: (fb_dly << 10) | unlock, 0x1A: (ref_dly << 10) | sat_high,
        0x28: 0xFFFF, 0x4E: filt1, 0x4F: filt2,
    }
    if m2m:
        for a in (0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x14):
            words[a] |= 0x1000          # reserved bit 12, masked (retained from the read-back)
    return [(a, words[a], masks[a]) for a, _ in ROW_NAMES]


def pixel_mhz(mult, divclk, o1):
    return F_REF * F(str(mult)) / int(divclk) / int(o1)


def fmt_addr(addr, style):
    if style == "hex":
        if addr > 0xFF:
            raise ValueError("table address 0x%X needs --addr-style hex9 or int" % addr)
        return 'x"%02X"' % addr
    if style == "hex9":
        return '9x"%03X"' % addr
    return "16#%03X#" % addr


def vhdl_block(mult, divclk, o0, o1, base, style="m2m", bandwidth="OPTIMIZED", desired=None,
               note=None, addr_style="hex"):
    rows = table(mult, divclk, o0, o1, style, bandwidth)
    act = pixel_mhz(mult, divclk, o1)
    des = F(str(desired)) if desired is not None else act
    ind = " " * 10
    out = []
    if note:
        for line in note.split("\n"):
            out.append(ind + "-- " + line)
    out.append(ind + "-- Desired frequency = %.3f MHz" % float(des))
    out.append(ind + "-- CLKFBOUT_MULT_F   = %.3f" % float(F(str(mult))))
    out.append(ind + "-- DIVCLK_DIVIDE     = %d" % int(divclk))
    out.append(ind + "-- CLKOUT0_DIVIDE_F  = %.3f" % float(F(str(o0))))
    out.append(ind + "-- CLKOUT1_DIVIDE    = %d" % int(o1))
    out.append(ind + "-- Actual frequency  = %.3f MHz" % float(act))
    for i, (a, data, mask) in enumerate(rows):
        aa = a | (0x80 if i == len(rows) - 1 else 0)
        out.append(ind + 'when %s => data := x"%02X" & x"%04X" & x"%04X";  -- %s' % (
            fmt_addr(base + i, addr_style), aa, data, mask, NAME[a]))
    return "\n".join(out)


# --------------------------------------------------------------------------------------------
# Parser for video_out_clock.vhd
# --------------------------------------------------------------------------------------------

ROW_RE = re.compile(r'when\s+(?:\d*x"([0-9A-Fa-f]{2,3})"|16#([0-9A-Fa-f]+)#)\s*=>\s*data\s*:=\s*'
                    r'x"([0-9A-Fa-f]{2})"\s*&\s*x"([0-9A-Fa-f]{4})"\s*&\s*x"([0-9A-Fa-f]{4})"')
HDR_RE = {
    "desired": re.compile(r"--\s*Desired frequency\s*=\s*([0-9.]+)"),
    "mult": re.compile(r"--\s*CLKFBOUT_MULT_F\s*=\s*([0-9.]+)"),
    "divclk": re.compile(r"--\s*DIVCLK_DIVIDE\s*=\s*([0-9]+)"),
    "o0": re.compile(r"--\s*CLKOUT0_DIVIDE_F\s*=\s*([0-9.]+)"),
    "o1": re.compile(r"--\s*CLKOUT1_DIVIDE\s*=\s*([0-9]+)"),
    "actual": re.compile(r"--\s*Actual frequency\s*=\s*([0-9.]+)"),
}


def parse_vhdl(path):
    """Return a list of tables: {base, params (from the comment), rows [(tbl_addr, daddr_byte, data, mask)]}."""
    tables = []
    cur_hdr = {}
    cur = None
    for line in open(path, errors="replace"):
        for k, r in HDR_RE.items():
            mm = r.search(line)
            if mm:
                if k == "desired":
                    cur_hdr = {}
                    cur = None
                cur_hdr[k] = mm.group(1)
        mm = ROW_RE.search(line)
        if mm:
            addr = int(mm.group(1) or mm.group(2), 16)
            row = (addr, int(mm.group(3), 16), int(mm.group(4), 16), int(mm.group(5), 16))
            if cur is None:
                cur = {"base": addr & ~0x1F, "params": dict(cur_hdr), "rows": []}
                tables.append(cur)
            cur["rows"].append(row)
    return tables


# --------------------------------------------------------------------------------------------
# Independent decoder (doc/dev-ntsc/tools/w2_checks.py)
# --------------------------------------------------------------------------------------------

def load_w2():
    sys.dont_write_bytecode = True      # no __pycache__ in doc/dev-ntsc/tools
    spec = importlib.util.spec_from_file_location("w2_checks", W2_CHECKS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def w2_decode(w2, mult, divclk, o0, o1, style):
    text = vhdl_block(mult, divclk, o0, o1, 0x00, style)
    regs = w2.drp_table(text, "000")
    return w2.mmcm_freq(regs)


def lock_filter_origin(rows):
    """Which XAPP888 lookup entries produce the lock and filter words of a table (by DRP address)."""
    w = {r[1] & 0x7F: r[2] for r in rows}
    found_lock = []
    for idx, lk in enumerate(LOCK_TABLE, 1):
        for name, tf in (("exact", lambda v: v), ("m2m", lock_m2m)):
            l1 = tf((lk >> 20) & 0x3FF)
            l2 = (((lk >> 30) & 0x1F) << 10) | tf(lk & 0x3FF)
            l3 = (((lk >> 35) & 0x1F) << 10) | tf((lk >> 10) & 0x3FF)
            if (w.get(0x18, -1) & 0x3FF, w.get(0x19, -1) & 0x7FFF, w.get(0x1A, -1) & 0x7FFF) == (l1, l2, l3):
                found_lock.append((idx, name))
    found_filt = []
    for bw in ("HIGH", "LOW"):
        for idx, fl in enumerate(FILTER_TABLES[bw], 1):
            fb = [(fl >> i) & 1 for i in range(10)]
            f1 = (fb[9] << 15) | (fb[8] << 12) | (fb[7] << 11) | (fb[6] << 8)
            f2 = (fb[5] << 15) | (fb[4] << 12) | (fb[3] << 11) | (fb[2] << 8) | (fb[1] << 7) | (fb[0] << 4)
            if (w.get(0x4E, -1) & 0x9900, w.get(0x4F, -1) & 0x9990) == (f1, f2):
                found_filt.append((idx, bw))
    return found_lock, found_filt


def ranges(idxs):
    idxs = sorted(set(idxs))
    out, s = [], None
    for i, v in enumerate(idxs):
        if s is None:
            s = v
        if i == len(idxs) - 1 or idxs[i + 1] != v + 1:
            out.append(str(s) if s == v else "%d..%d" % (s, v))
            s = None
    return ",".join(out)


# --------------------------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------------------------

def explain(daddr, diff, file_word, xapp_word, file_mask, xapp_mask):
    if daddr in (0x06, 0x08, 0x0A, 0x0C, 0x0E, 0x10, 0x12, 0x14) and diff == 0x1000:
        return "reserved bit 12 of ClkReg1: masked (0x1000), the MMCM keeps its own value"
    if daddr in (0x07, 0x0B, 0x0D, 0x0F, 0x11, 0x13) and file_mask != xapp_mask and diff == 0:
        return "mask 0x%04X instead of 0x%04X: reserved bits written as 0 instead of retained" % (file_mask, xapp_mask)
    if daddr == 0x16 and diff == 0x2000:
        return "DIVCLK EDGE (odd D): only the duty cycle of the PFD input, the PFD uses rising edges"
    if daddr in (0x18, 0x1A) and diff & ~0x0300 == 0:
        return "lock field bits [9:8] stored as {0, bit 9} (spreadsheet quirk)"
    if daddr == 0x09 and diff == 0x0080:
        return "EDGE with NO_COUNT (divide 1): counter bypassed"
    return "UNEXPLAINED"


def cmd_check(args):
    tables = parse_vhdl(args.vhdl)
    try:
        w2 = load_w2()
    except Exception as e:      # pragma: no cover
        w2 = None
        print("w2_checks.py not loadable (%s): independent decode skipped" % e)
    ok = True
    path = os.path.abspath(args.vhdl)
    print("File: %s" % (os.path.relpath(path, REPO) if path.startswith(REPO + os.sep) else path))
    print("%-7s %-8s %-7s %-4s %-6s %-4s %-5s %-11s %-11s %-12s %-30s" % (
        "clk_sel", "base", "M", "D", "O0", "O1", "rows", "m2m match", "xapp888", "pixel MHz", "w2_checks decode of file rows"))
    xapp_notes = []
    for t in tables:
        p = t["params"]
        sel = format(t["base"] >> 5, "03b")
        try:
            gen = table(p["mult"], p["divclk"], p["o0"], p["o1"], "m2m")
            xap = table(p["mult"], p["divclk"], p["o0"], p["o1"], "xapp888")
        except Exception as e:
            print("%s: cannot generate (%s)" % (sel, e))
            ok = False
            continue
        rows = t["rows"]
        mism = []
        if len(rows) != len(gen):
            mism.append("row count %d, generated %d" % (len(rows), len(gen)))
        for i, (row, g) in enumerate(zip(rows, gen)):
            tbl_addr, daddr_b, data, mask = row
            g_daddr_b = g[0] | (0x80 if i == len(gen) - 1 else 0)
            if tbl_addr != t["base"] + i:
                mism.append("row %d: table address %02X, expected %02X" % (i, tbl_addr, t["base"] + i))
            if daddr_b != g_daddr_b:
                mism.append("row %d: DRP address %02X, generated %02X" % (i, daddr_b, g_daddr_b))
            if data != g[1]:
                mism.append("row %d (%s): data %04X, generated %04X, xor %04X" % (i, NAME.get(g[0], "?"), data, g[1], data ^ g[1]))
            if mask != g[2]:
                mism.append("row %d (%s): mask %04X, generated %04X" % (i, NAME.get(g[0], "?"), mask, g[2]))
        nx = 0
        for i, (row, x) in enumerate(zip(rows, xap)):
            d_diff = row[2] ^ x[1]
            if d_diff or row[3] != x[2]:
                nx += 1
                xapp_notes.append((sel, x[0], row[2], x[1], row[3], x[2],
                                   explain(x[0], d_diff, row[2], x[1], row[3], x[2])))
        dec = ""
        if w2 is not None:
            vo_text = "\n".join('when x"%02X" => data := x"%02X" & x"%04X" & x"%04X";' % (r[0] - t["base"], r[1], r[2], r[3])
                                for r in rows)
            m, d, o0, o1, f = w2.mmcm_freq(w2.drp_table(vo_text, "000"))
            same = (F(str(m)) == F(p["mult"]) and d == int(p["divclk"]) and F(str(o0)) == F(p["o0"])
                    and F(str(o1)) == F(p["o1"]))
            dec = "M %.3f D %d O0 %g O1 %g -> %.6f %s" % (m, d, o0, o1, f, "= header" if same else "!= HEADER")
            if not same:
                ok = False
        match = "yes" if not mism else "NO (%d)" % len(mism)
        ok = ok and not mism
        print("%-7s 0x%02X     %-7s %-4s %-6s %-4s %-5d %-11s %-11s %-12.6f %s" % (
            sel, t["base"], p["mult"], p["divclk"], p["o0"], p["o1"], len(rows), match,
            "%d words" % nx, float(pixel_mhz(p["mult"], p["divclk"], p["o1"])), dec))
        if args.verbose or mism:
            for s in mism:
                print("        " + s)
        lk, fl = lock_filter_origin(rows)
        if args.verbose:
            print("        lock words = XAPP888 lock table M %s; filter words = XAPP888 filter table %s" % (
                ", ".join("%s %s" % (ranges([i for i, s in lk if s == st]), st) for st in ("exact", "m2m")
                          if any(s == st for _, s in lk)) or "NONE",
                ", ".join("%s M %s" % (bw, ranges([i for i, b in fl if b == bw])) for bw in ("HIGH", "LOW")
                          if any(b == bw for _, b in fl)) or "NONE"))
        if int(F(p["mult"])) not in [i for i, s in lk if s == "m2m"]:
            print("        lock words do not come from lock table entry M = %d" % int(F(p["mult"])))
            ok = False
        if int(F(p["mult"])) not in [i for i, b in fl if b == "HIGH"]:
            print("        filter words do not come from the HIGH/OPTIMIZED entry M = %d" % int(F(p["mult"])))
            ok = False
    print()
    print("Words in which the file differs from the pure XAPP888 reference ROM (style xapp888):")
    print("  %-7s %-20s %-6s %-6s %-6s %-6s %s" % ("clk_sel", "register", "file", "xapp", "fmask", "xmask", "reason"))
    unexplained = 0
    for sel, daddr, fw, xw, fm, xm, why in xapp_notes:
        print("  %-7s %-20s %04X   %04X   %04X   %04X   %s" % (sel, NAME[daddr], fw, xw, fm, xm, why))
        unexplained += why == "UNEXPLAINED"
    print()
    print("RESULT: %s (%d tables, generator style m2m; %d xapp888 differences, %d unexplained)" % (
        "PASS" if ok and unexplained == 0 else "FAIL", len(tables), len(xapp_notes), unexplained))
    return 0 if ok and unexplained == 0 else 1


# DS181 v1.27.1 Table 37 (MMCM, speed grade -2), Table 32 (BUFG), Table 15 (OSERDES DDR); UG472 v1.14 Table 3-7
LIM = dict(fin=(10, 800), pfd=(10, 500), vco=(600, 1440), vco_m1=1200, fout=(F("4.69"), 800), bufg=628,
           oserdes_ddr=1250, m=(2, 64), d=(1, 106), o=(1, 128))


def limits(mult, divclk, o0, o1, quiet=False):
    m, o0f, d, o1i = F(str(mult)), F(str(o0)), int(divclk), int(o1)
    pfd = F_REF / d
    vco = pfd * m
    f0, f1 = vco / o0f, vco / o1i
    res = []

    def chk(cond, text, warn=False):
        res.append(("ok  " if cond else ("NOTE" if warn else "FAIL"), text))

    chk((m * 8).denominator == 1 and LIM["m"][0] <= m <= LIM["m"][1],
        "CLKFBOUT_MULT_F %.3f in 2.000..64.000, steps of 0.125 (UG472 Table 3-7)" % float(m))
    chk(LIM["d"][0] <= d <= LIM["d"][1], "DIVCLK_DIVIDE %d in 1..106 (UG472 Table 3-7)" % d)
    chk((o0f * 8).denominator == 1 and (o0f == 1 or 2 <= o0f <= 128),
        "CLKOUT0_DIVIDE_F %.3f in 1 or 2.000..128.000 (UG472 Table 3-7)" % float(o0f))
    chk(1 <= o1i <= 128, "CLKOUT1_DIVIDE %d in 1..128 (UG472 Table 3-7)" % o1i)
    chk(o1i == 5 * o0f, "CLKOUT1_DIVIDE = 5 x CLKOUT0_DIVIDE_F (pixel clock = serializer clock / 5)")
    chk(o0f.denominator == 1, "CLKOUT0 integer: no fractional output divider, rising edges of CLKOUT0 and "
        "CLKOUT1 coincide every %d VCO cycles" % o1i)
    chk(LIM["fin"][0] <= F_REF <= LIM["fin"][1], "CLKIN 100 MHz in 10..800 MHz (MMCM_FINMIN/FINMAX)")
    chk(LIM["pfd"][0] <= pfd <= LIM["pfd"][1], "PFD %.3f MHz in 10..500 MHz (MMCM_FPFDMIN/FPFDMAX, -2)" % float(pfd))
    chk(pfd >= 20, "PFD %.3f MHz >= 20 MHz, the lowest PFD of the existing tables (D = 5)" % float(pfd), warn=True)
    chk(LIM["vco"][0] <= vco <= LIM["vco"][1], "VCO %.3f MHz in 600..1440 MHz (MMCM_FVCOMIN/FVCOMAX, -2)" % float(vco))
    chk(vco <= LIM["vco_m1"], "VCO %.3f MHz <= 1200 MHz (also legal on a -1 part)" % float(vco), warn=True)
    chk(f0 <= LIM["fout"][1] and f1 >= LIM["fout"][0],
        "outputs %.4f / %.6f MHz in 4.69..800 MHz (MMCM_FOUTMIN/FOUTMAX)" % (float(f0), float(f1)))
    chk(f0 <= LIM["bufg"], "serializer clock %.4f MHz <= 628 MHz (FMAX_BUFG, -2)" % float(f0))
    chk(2 * f0 <= LIM["oserdes_ddr"], "TMDS bit rate %.2f Mb/s <= 1250 Mb/s (DDR OSERDES transmitter, -2)"
        % float(2 * f0))
    chk(1 <= int(m) <= 64, "lock and filter lookup index int(M) = %d in 1..64" % int(m))
    if (m * 8) % 8:
        chk(True, "fractional CLKFBOUT: CLKOUT6 shares ClkReg2 (unused here), phase 0, no fine phase shift (UG472)")
    if o0f.denominator == 1 and int(o0f) % 2:
        chk(True, "odd CLKOUT0 divide %d: 50 %% duty cycle by the EDGE bit (high %d.5 + low %d.5 VCO cycles)"
            % (int(o0f), int(o0f) // 2, int(o0f) // 2))
    if not quiet:
        for st, text in res:
            print("  %s %s" % (st, text))
    return res, dict(pfd=pfd, vco=vco, f0=f0, f1=f1)


def equivalents(mult, divclk, o0, o1, vco_max=1440):
    target = pixel_mhz(mult, divclk, o1)
    out = []
    for d in range(1, 11):                          # PFD >= 10 MHz
        for k in range(16, 64 * 8 + 1):
            m = F(k, 8)
            vco = F_REF / d * m
            if not (600 <= vco <= vco_max):
                continue
            for n in range(1, 26):                  # O1 = 5 n <= 128
                if vco / (5 * n) == target:
                    out.append((m, d, n, 5 * n, vco, F_REF / d))
    return target, out


def cmd_gen(args):
    print(vhdl_block(args.M, args.D, args.O0, args.O1, int(args.base, 0), args.style, args.bandwidth,
                     args.desired, args.note, args.addr_style))
    return 0


def cmd_limits(args):
    res, _ = limits(args.M, args.D, args.O0, args.O1)
    return 1 if any(s == "FAIL" for s, _ in res) else 0


def cmd_equiv(args):
    target, out = equivalents(args.M, args.D, args.O0, args.O1)
    print("pixel clock %.6f MHz (= %s MHz): every legal setting with O1 = 5 x O0 (VCO 600..1440, PFD >= 10 MHz)"
          % (float(target), target))
    for m, d, n, o1, vco, pfd in out:
        print("  M %7.3f  D %2d  O0 %2d  O1 %3d  VCO %9.3f MHz  PFD %7.3f MHz%s" % (
            float(m), d, n, o1, float(vco), float(pfd), "  (VCO > 1200)" if vco > 1200 else ""))
    return 0


# HDMI modes at the C64 frame rate: (name, M, D, O0, O1, htotal, vtotal, standard, role, slot).
# "table" entries are the tables for the clk_sel codes first_sel + slot; "alternative" entries
# are settings that were considered and are not used (printed with --alternatives).
NEW_TABLES = [
    ("PAL 720p (1280x720, 1980 x 750 total)", "33.5", 3, 3, 15, 1980, 750, "PAL", "table", 0),
    ("PAL 576p (720x576, 864 x 624 total)", "28.375", 3, 7, 35, 864, 624, "PAL", "table", 1),
    ("NTSC 720p (1280x720, 1650 x 750 total)", "29.625", 4, 2, 10, 1650, 750, "NTSC", "table", 2),
    ("PAL 576p (720x576, 864 x 624 total)", "56.75", 6, 7, 35, 864, 624, "PAL", "alternative", 1),
    ("PAL 576p (720x576, 864 x 625 total)", "47.375", 7, 5, 25, 864, 625, "PAL", "alternative", 1),
    ("PAL 576p (720x576, 864 x 625 total)", "47.375", 5, 7, 35, 864, 625, "PAL", "alternative", 1),
    ("NTSC 480p (720x480, 858 x 525 total)", "43.125", 4, 8, 40, 858, 525, "NTSC", "alternative", 3),
]
CORE_FRAME = {"PAL": F_REF * F("56.75") / (6 * 30) / (63 * 312 * 32),     # CORE/vhdl/clk.vhd, Hz x 1e-6
              "NTSC": F_REF * 36 / (5 * 22) / (65 * 263 * 32)}


def closest_existing(rows, vhdl):
    """The existing table with the fewest differing (address, data, mask) rows."""
    best = None
    for t in parse_vhdl(vhdl):
        diff = [(i, r[1] & 0x7F, r[2], g[1]) for i, (r, g) in enumerate(zip(t["rows"], rows))
                if (r[1] & 0x7F, r[2], r[3]) != (g[0], g[1], g[2])]
        if best is None or len(diff) < len(best[1]):
            best = (format(t["base"] >> 5, "03b"), diff, t["params"])
    return best


def cmd_new(args):
    w2 = load_w2()
    rc = 0
    for name, m, d, o0, o1, ht, vt, std, role, slot in NEW_TABLES:
        if role != "table" and not args.alternatives:
            continue
        sel = args.first_sel + slot
        pix = pixel_mhz(m, d, o1)
        fr = pix * 1000000 / (ht * vt)
        core = CORE_FRAME[std] * 1000000
        print("=" * 100)
        print("%s, %s setting M %s D %d O0 %d O1 %d" % (name, role, m, d, o0, o1))
        print("  pixel clock %.6f MHz, frame %.6f Hz, core frame %.6f Hz, %+.1f ppm" % (
            float(pix), float(fr), float(core), float((fr / core - 1) * 1000000)))
        res, _ = limits(m, d, o0, o1)
        if any(s == "FAIL" for s, _ in res):
            rc = 1
        for style in ("m2m", "xapp888"):
            dm, dd, do0, do1, df = w2_decode(w2, m, d, o0, o1, style)
            good = (F(str(dm)) == F(m) and dd == d and do0 == o0 and do1 == o1 and abs(df - float(pix)) < 1e-9)
            print("  %s w2_checks.py decode of the generated %s rows: M %.3f D %d O0 %g O1 %g -> %.6f MHz, x5 %.4f MHz" % (
                "ok  " if good else "FAIL", style, dm, dd, do0, do1, df, df * do1 / do0))
            if not good:
                rc = 1
        rows = table(m, d, o0, o1, args.style)
        sel_e, diff, p = closest_existing(rows, args.vhdl)
        print("  closest existing table: CLK_SEL %s (M %s D %s O0 %s O1 %s), %d of 23 rows differ:" % (
            sel_e, p["mult"], p["divclk"], p["o0"], p["o1"], len(diff)))
        for i, a, old, new in diff:
            print("      %-20s %04X -> %04X" % (NAME[a], old, new))
        xr = table(m, d, o0, o1, "xapp888" if args.style == "m2m" else "m2m")
        other = [(NAME[a], dv, xr[i][1], mk, xr[i][2]) for i, (a, dv, mk) in enumerate(rows)
                 if (dv, mk) != (xr[i][1], xr[i][2]) and a in (0x16, 0x18, 0x19, 0x1A, 0x09, 0x0B)]
        if other:
            print("  frequency-neutral words that the other style writes differently:")
            for nm, dv, xv, mk, xm in other:
                print("      %-20s data %04X / %04X  mask %04X / %04X" % (nm, dv, xv, mk, xm))
        note = "%s at the C64 frame rate: %.6f Hz" % (name, float(fr))
        print()
        print(vhdl_block(m, d, o0, o1, sel * 0x20, args.style, "OPTIMIZED", None, note, args.addr_style))
        print()
    return rc


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    c = sub.add_parser("check")
    c.add_argument("--vhdl", default=VHDL_DEFAULT)
    c.add_argument("-v", "--verbose", action="store_true")
    for nm in ("gen", "limits", "equiv"):
        g = sub.add_parser(nm)
        g.add_argument("M")
        g.add_argument("D", type=int)
        g.add_argument("O0")
        g.add_argument("O1", type=int)
        if nm == "gen":
            g.add_argument("--base", default="0x00")
            g.add_argument("--desired", default=None)
            g.add_argument("--note", default=None)
            g.add_argument("--style", choices=("m2m", "xapp888"), default="m2m")
            g.add_argument("--bandwidth", choices=("OPTIMIZED", "HIGH", "LOW", "LOW_SS"), default="OPTIMIZED")
            g.add_argument("--addr-style", choices=("hex", "hex9", "int"), default="hex")
    n = sub.add_parser("new")
    n.add_argument("--style", choices=("m2m", "xapp888"), default="m2m")
    n.add_argument("--first-sel", type=int, default=8)
    n.add_argument("--addr-style", choices=("hex", "hex9", "int"), default="hex9")
    n.add_argument("--vhdl", default=VHDL_DEFAULT)
    n.add_argument("--alternatives", action="store_true", help="also the settings that are not used")
    args = ap.parse_args()
    if args.cmd == "check":
        return cmd_check(args)
    if args.cmd == "gen":
        return cmd_gen(args)
    if args.cmd == "limits":
        return cmd_limits(args)
    if args.cmd == "equiv":
        return cmd_equiv(args)
    if args.cmd == "new":
        return cmd_new(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    try:
        sys.exit(main())
    except ValueError as e:
        print("error: %s" % e, file=sys.stderr)
        sys.exit(2)
