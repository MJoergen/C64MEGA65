#!/usr/bin/env python3
"""
Readable views of a run directory of qsys_tb.vhd.

    runtext.py uart RUN          UART output as text, each line with the time stamp (us)
                                 of its first byte
    runtext.py bits RUN          changes of the 512 menu bits (control_m in regs.log):
                                 time, bits switched on, bits switched off (bit = flat
                                 menu index, names from config.vhd OPTM_ITEMS)
    runtext.py cfg RUN           block writes of the SD card model (sdwrites.log) compared
                                 with the config file on the card (sd/card_full.cfg.bin)
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(HERE))), "wtA")


def uart(run):
    cur, t0 = "", None
    for l in open(os.path.join(run, "uart.log")):
        p = l.split()
        if len(p) < 2:
            continue
        c = chr(int(p[1], 16))
        if t0 is None:
            t0 = p[0]
        if c == "\n":
            print("%12s  %s" % (t0, cur.rstrip("\r")))
            cur, t0 = "", None
        else:
            cur += c
    if cur:
        print("%12s  %s" % (t0, cur))


def menu_items():
    text = open(os.path.join(REPO, "CORE", "vhdl", "config.vhd")).read()
    body = text[text.index("constant OPTM_ITEMS"):]
    body = "\n".join(line.split("--")[0] for line in body.split("\n"))
    body = body[:body.index(";")]
    s = "".join(re.findall(r'"((?:[^"\\]|\\.)*)"', body))
    return s.split("\\n")


def bits(run):
    names = menu_items()
    prev = None
    for l in open(os.path.join(run, "regs.log")):
        m = re.match(r"\s*([\d.]+) control_m=([0-9A-F]+)", l)
        if not m:
            continue
        v = int(m.group(2), 16)
        if prev is not None and v != prev:
            on = [i for i in range(512) if (v >> i) & 1 and not (prev >> i) & 1]
            off = [i for i in range(512) if (prev >> i) & 1 and not (v >> i) & 1]
            f = lambda lst: ", ".join("%d%s" % (i, "(" + names[i].strip() + ")" if i < len(names) else "")
                                      for i in lst)
            print("%12s  on: %s   off: %s" % (m.group(1), f(on) or "-", f(off) or "-"))
        elif prev is None:
            print("%12s  initial: %s" % (m.group(1), [i for i in range(512) if (v >> i) & 1]))
        prev = v


def cfg(run):
    ref = open(os.path.join(HERE, "sd", "card_full.cfg.bin"), "rb").read()
    names = menu_items()
    path = os.path.join(run, "sdwrites.log")
    if not os.path.exists(path):
        print("no sdwrites.log")
        return
    for l in open(path):
        lba, hx = l.split()
        data = bytes.fromhex(hx)
        diffs = [i for i in range(min(len(ref), 512)) if data[i] != ref[i]]
        print("write block %s: first bytes %s ..." % (lba, data[:16].hex()))
        print("  positions that differ from the config file on the card: %s" %
              ", ".join("%d %s: %d -> %d" % (i, names[i].strip() if i < len(names) else "", ref[i], data[i])
                        for i in diffs))
        print("  bytes behind the config file (%d..511) all zero: %s" % (len(ref), not any(data[len(ref):])))


def peaks(run):
    """Per checkpoint of spy.log: highest bank level and lowest stack pointer (>= 0x8000) with routines."""
    import mapstack
    labels, _ = mapstack.load_listing(mapstack.DEFAULT_LIS)
    for l in open(os.path.join(run, "spy.log")):
        m = re.search(r"([\d.]+) (\S+)\s+sp_min=(\w+) .* bank_max=(\w+) .*pc_at_bank_max=(\w+) pc_at_sp_min=(\w+)", l)
        if not m:
            continue
        sp, bk = int(m.group(3), 16), int(m.group(4), 16)
        pcb, pcs = int(m.group(5), 16), int(m.group(6), 16)
        print("%12s %-22s bank_max=%2d at %04X %-26s sp_min=%04X at %04X %s" %
              (m.group(1), m.group(2), bk, pcb, mapstack.routine(labels, pcb), sp, pcs,
               mapstack.routine(labels, pcs) if sp >= 0x8000 else "(reset value)"))


if __name__ == "__main__":
    {"uart": uart, "bits": bits, "cfg": cfg, "peaks": peaks}[sys.argv[1]](sys.argv[2])
