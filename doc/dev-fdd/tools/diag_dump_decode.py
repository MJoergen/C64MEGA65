#!/usr/bin/env python3
"""Decoder for the dumps of the diagnostic device of the Internal 1581 (doc/1581_dd_debug_device.md)
that testers paste into a GitHub issue: the blocks of the QNICE monitor commands MD 7000 703F,
MD 7040 707F and MD 7080 70A5 (map v8: up to 709D, map v9: up to 70A1), each in a code fence that
starts with "7000:".

  gh api repos/MJoergen/C64MEGA65/issues/257/comments --paginate > comments.json
  python3 -I diag_dump_decode.py comments.json                 # every dump of every comment
  python3 -I diag_dump_decode.py comments.json 17 18           # the dumps of comments 17 and 18
  python3 -I diag_dump_decode.py comments.json 17 --only FMT   # only dumps whose label contains FMT

The label of a dump is the nearest line before its code fence that mentions "Dump <name>". The
words are printed with the names of the register map; the trace ring is listed oldest entry first.
Words that a dump does not contain (an older map, or a block that was not pasted) are left out; a
line that is not "<address>: <words>" and the rest of a line after a word that is not hexadecimal are
skipped with a note. The words of map v10 (70A2 to 70A5) are decoded only for a device that reports
map v10 or later in VERSION (7001), and a note says so when such a device was dumped without them.

The index gap (70A2) is read against the index period of the same dump (700D/700E): a gap near a
whole number of revolutions is a count of index pulses that did not arrive while the disk turned; at
the 6 ms per step of the 1581 ROM, a mechanism that withholds its index pulses while the head steps
gives 2 to 5 revolutions after a recalibration or a long seek (doc/dev-fdd/tools/idx_gap_model.py).
A gap that is not near a whole number of revolutions is flagged. Whenever the gap is longer than one
revolution, the dump's two counters that tell a disk change apart are read with it: CNT_RDY_STALE
(70A3) and CNT_CHANGE (7022/7023).
"""
import json, re, sys

def dumps_of(body):
    """yield (label, {addr:word}, [notes]) for each fenced block that looks like a dump"""
    out = []
    body = body.replace("\r\n", "\n")
    # find label = nearest preceding line mentioning 'Dump' or 'dump'
    for m in re.finditer(r"```\n(7000:.*?)```", body, re.S):
        block = m.group(1)
        pre = body[:m.start()]
        lab = None
        for line in reversed(pre.splitlines()):
            mm = re.search(r"(Extra dump \w+|Dump \w+|dump \w+)", line)
            if mm:
                lab = mm.group(1); break
        words, notes = {}, []
        for line in block.strip().splitlines():
            mm = re.match(r"\s*([0-9A-Fa-f]{4})\s*:(.*)$", line)
            if not mm:
                notes.append(f"line skipped, not '<address>: <words>': {line.strip()[:60]!r}")
                continue
            base = int(mm.group(1), 16)
            for i, t in enumerate(mm.group(2).split()):
                if not re.fullmatch(r"[0-9A-Fa-f]{1,4}", t):
                    notes.append(f"line {mm.group(1)}: {t[:20]!r} is not a hexadecimal word, the rest of the line is skipped")
                    break
                words[base + i - 0x7000] = int(t, 16)
        out.append((lab, words, notes))
    return out

RES = {0:"OK",1:"not ready",2:"no index",3:"track0 failed",4:"RNF",5:"ID CRC",6:"missing DAM",7:"data CRC",8:"bad size",9:"WRITE PROTECTED",0xA:"DISK CHANGED",0xB:"LOST DATA",0xD:"cancelled",0xE:"invalid",0xF:"internal"}
OPS = {0:"ReadSector",1:"ReadAddress",2:"Verify",4:"WRITE SECTOR",5:"WRITE TRACK"}
PHASE = {1:"waiting for ready",2:"searching for the ID",3:"waiting for the data mark",4:"streaming data",5:"reading address",
         6:"waiting for the read-ahead capture",7:"copying from the read-ahead buffer"}

def ring(w):
    n = w[0x29]
    ents = []
    newest = (n - 1) % 32
    order = [(newest + 1 + i) % 32 for i in range(32)] if n >= 32 else list(range(n))
    for k in order:
        w0, w1 = w[0x40 + 2*k], w[0x41 + 2*k]
        t = w0 >> 12
        if t == 1:
            s = f"STEP dir={'out(->trk0)' if (w0>>8)&1 else 'in'} head_est={w0&0xFF} trk0_after={w1&1}"
        elif t == 2:
            op = (w0 >> 9) & 7
            s = f"REQ  {OPS.get(op,op):12s} side={(w0>>8)&1} trk={w0&0xFF:2d} sec={w1>>8}"
        elif t == 3:
            code = w1 & 0xFF
            s = f"RES  C={w0&0xFF:2d} H={(w0>>8)&1} R={w1>>8:2d} rnf={(w0>>11)&1} crc={(w0>>10)&1} del={(w0>>9)&1} -> {RES.get(code,hex(code))}"
        else:
            s = f"?? {w0:04X} {w1:04X}"
        ents.append(s)
    return n, ents

def u32(w, lo): return w[lo] | (w[lo+1] << 16)

def gap_lines(w):
    """the lines of the index gap (map v10) and its cross-check with the counters of a disk change"""
    gap, stale = w[0xA2], w[0xA3]
    per = u32(w, 0xD) if 0xD in w and 0xE in w else 0
    rev = (per / 50e3) if per else 200.0
    if gap == 0:
        return "no measurement since reset", []
    if gap == 0xFFFF:
        note, r = "saturated (65.5 s or more)", float("inf")
    else:
        r = gap / rev
        k = round(r)
        note = f"{gap} ms = {r:.2f} revolutions"
        if k < 1 or abs(r - k) > 0.1:
            note += "  <-- not within 0.1 of a whole number of revolutions: not a count of index pulses that did not arrive while the disk turned"
        elif k == 1:
            note += "  (every index pulse arrived)"
        elif k <= 5:
            note += (f"  <-- {k - 1} index pulse(s) in a row did not arrive with the motor on (2 to 5 revolutions:"
                     " a mechanism that withholds its index pulses while the head steps, after a recalibration or a long seek)")
        else:
            note += (f"  <-- {k - 1} index pulses in a row did not arrive with the motor on: longer than the steps of a"
                     " recalibration or a seek withhold them (a disk out and in with the motor on, or a disk that stopped)")
    extra = []
    if r > 1.1 and 0x22 in w and 0x23 in w:
        change = u32(w, 0x22)
        whole = r != float("inf") and round(r) >= 2 and abs(r - round(r)) <= 0.1
        if stale == 0 and change == 0:
            extra.append("CROSS-CHECK: CNT_RDY_STALE=0 and CNT_CHANGE=0: no disk change latched and no stale READY since reset, so"
                         + (" the gap is not the time without a disk" if whole else
                            " neither withheld index pulses nor a disk change explain this gap"))
        else:
            extra.append(f"CROSS-CHECK: CNT_RDY_STALE={stale}, CNT_CHANGE={change}: a disk change was latched or READY went stale"
                         " since reset, so the gap " + ("can also be" if whole else "is most likely") + " the time without a disk;"
                         " a clean reading needs a power cycle with the disk in the drive and no disk change before the dump")
    return note, extra

def show(lab, w, notes=(), full_ring=True):
    print(f"\n================ {lab} ================")
    for n in notes:
        print(f"NOTE: {n}")
    missing = [a for a in range(0x40) if a not in w]
    if missing:
        print(f"NOTE: the block MD 7000 703F is incomplete ({len(missing)} of its 64 words missing, the first at"
              f" {0x7000 + missing[0]:04X}): its words are not decoded")
    else:
        show_7000(w)
    if all(a in w for a in range(0x80, 0x9E)):
        show_v8(w)
    if all(a in w for a in range(0x9E, 0xA2)):
        show_v9(w)
    ver = w.get(1, 0) >> 8
    v10 = [a for a in range(0xA2, 0xA6) if a in w]
    if 1 in w and ver >= 0x0A:
        if len(v10) == 4:
            show_v10(w)
        else:
            print(f"NOTE: VERSION={w[1]:04X} is map v{ver}, but the dump lacks words of 70A2 to 70A5 (index gap, stale"
                  " READY, decoder tolerance): dump them with MD 7080 70A5")
    elif v10:
        print(f"NOTE: the dump holds words from 70A2 on, but VERSION={w.get(1, 0):04X} is map v{ver}: they are not words of"
              " that map and are not decoded")
    if 0x29 in w and all(a in w for a in range(0x40, 0x80)):
        n, ents = ring(w)
        if full_ring:
            print(f"-- trace ring, oldest -> newest (TRC_CNT={n}) --")
            for e in ents: print("   ", e)
    else:
        print("NOTE: the trace ring (MD 7040 707F) is not in the dump, or not completely")

def show_7000(w):
    li, lo_, cs, hd = w[2], w[3], w[4], w[5]
    print(f"SIG={w[0]:04X} VER={w[1]:04X}")
    print(f"LIVE_IN ={li:04X}: raw rdata={li&1} index={(li>>1)&1} trk0={(li>>2)&1} WPpin={(li>>3)&1}(0=protected) chgpin={(li>>4)&1}(0=changed) | cond WP={(li>>8)&1} cond CHG={(li>>9)&1} cond TRK0={(li>>7)&1}")
    print(f"LIVE_OUT={lo_:04X}: motor_n={lo_&1} sel_n={(lo_>>1)&1} side1_n={(lo_>>2)&1} enable={(lo_>>6)&1}")
    print(f"CTRL    ={cs:04X}: ready={cs&1} settled={(cs>>1)&1} seplock={(cs>>2)&1} motor={(cs>>3)&1} chg_latch={(cs>>4)&1} headvalid={(cs>>5)&1} phys={(cs>>6)&1} wp={(cs>>9)&1} stepfsm={(cs>>10)&3} phase={(cs>>12)&15}")
    if (cs >> 12) & 15:
        print(f"          phase {(cs>>12)&15} = {PHASE.get((cs>>12)&15, 'write code, see the register map')}")
    print(f"HEAD    ={hd:04X}: cyl={hd&0xFF} valid={(hd>>8)&1} lastdir={(hd>>9)&1} trk0={(hd>>10)&1}")
    lr = w[6]
    print(f"LAST_RESULT={lr:04X} ({RES.get(lr&31)}; crc={(lr>>5)&1} rnf={(lr>>6)&1})  CHRN: C={w[7]>>8} R={w[7]&0xFF} H={w[8]>>8} N={w[8]&0xFF}  CRCflags={w[0xC]:X} idcalc={w[0xA]:04X} datacalc={w[0xB]:04X}")
    per = u32(w, 0xD); wid = u32(w, 0xF)
    rpm = f"{60e3/(per/50e3):.2f} RPM" if per else "no index period measured"
    print(f"IDX_PERIOD={per} cyc = {per/50e3:.3f} ms -> {rpm} | IDX_WIDTH={wid/50e3:.3f} ms | GAP last/min/max={w[0x11]}/{w[0x12]}/{w[0x13]}")
    print(f"CNT: idx_raw={u32(w,0x14)} idx_qual={u32(w,0x16)} step={u32(w,0x18)} READOP={u32(w,0x1A)} RNF={u32(w,0x1C)} CRCERR={u32(w,0x1E)} cancel={u32(w,0x20)} CHANGE={u32(w,0x22)} iddec={u32(w,0x24)} gaperr={u32(w,0x26)}")
    print(f"IMG_DRIVE={w[0x28]} TRC_CNT={w[0x29]} FIFO={w[0x2A]} LAST_PRESENT={w[0x2B]} | rdLOST={u32(w,0x2C)} drain={u32(w,0x2E)} staledone={u32(w,0x30)} busycmd={u32(w,0x32)} runt={u32(w,0x34)}")
    print(f"EST={w[0x36]/16:.3f} RNF_CTX={w[0x37]:04X} (trk {w[0x37]>>8} sec {w[0x37]&0xFF})")
    print(f"A1: cand={w[0x38]} reject={w[0x39]} train={w[0x3A]} FE={w[0x3B]} DAM={w[0x3C]} DAM_UNARMED={w[0x3D]} MATCH_ID={w[0x3E]} DAM_MISS={w[0x3F]}  (DAM-FE={w[0x3C]-w[0x3B]}, train-(FE+DAM)={w[0x3A]-w[0x3B]-w[0x3C]})")

def show_v8(w):
    ws = w[0x80]; wl = w[0x81]
    print(f"WR_STATE={ws:04X}: fsm={ws&15} writer={(ws>>4)&7} wr_ok(tab writable)={(ws>>7)&1} session={(ws>>8)&1} feed={(ws>>9)&1} precomp={(ws>>10)&1} wgate_pin={(ws>>11)&1}(0=writing) wdata_pin={(ws>>12)&1} H={(ws>>13)&1} abort={(ws>>14)&1}")
    print(f"WR_LAST={wl:04X}: completed={(wl>>8)&1} lost={(wl>>9)&1} aborted={(wl>>10)&1} wp_refusal={(wl>>11)&1} firstbyte_abort={(wl>>12)&1} track={(wl>>13)&1} deleted={(wl>>14)&1} precomp={(wl>>15)&1} reason={wl&0xFF:02X}")
    print(f"WR_LAST_CHR={w[0x82]:04X} (R={w[0x82]>>8} C={w[0x82]&0xFF})  WR_GATE_CYC={u32(w,0x83)} ({'exactly one sector' if u32(w,0x83)==849600 else 'NOT 849600'})  BYTES_LAST={w[0x85]}")
    print(f"CNT_WR: SECT={u32(w,0x86)} TRACK={u32(w,0x88)} GATE={u32(w,0x8A)} LOST={u32(w,0x8C)} WP={u32(w,0x8E)} ABORT={u32(w,0x90)} | REASON_ACC={w[0x92]:04X} FIFO_OVF={w[0x93]} UNDERRUN={w[0x94]} PRECOMP_CNT={w[0x95]} FIRST_MARGIN={w[0x96]} DRQ_MARGIN={w[0x97]} TRK_CYC={u32(w,0x98)} WR_CTRL={w[0x9A]} FIN={w[0x9B]} PUSHFULL={w[0x9C]} DISCARD={w[0x9D]}")

def show_v9(w):
    rs = u32(w, 0x1A)
    print(f"READ-AHEAD (map v9): served from the buffer={w[0x9E]} adoptions given up={w[0x9F]}" + (f" (read ops in all: {rs})" if rs else ""))
    last, mx = w[0xA0], w[0xA1]
    note = "no measurement since reset" if last == 0xFFFF else ("saturated" if last == 0xFFFE else f"{last} ms")
    print(f"SPINUP (map v9): motor-on to first index pulse: last={note}, max={mx} ms" + ("  <-- 800 ms or more: the READY exam of the DOS (0.80 s after motor-on) can fail, unless the motor was switched on without a disk" if mx >= 800 else ""))

def show_v10(w):
    gnote, extra = gap_lines(w)
    print(f"INDEX GAP (map v10): longest time between two index edges with the motor on: {gnote}")
    rc = w[0xA5]
    flag = "  <-- bits 15 to 1 are not 0, but the device reads them as 0: a wrong address or a garbled dump" if rc & 0xFFFE else ""
    print(f"STALE READY (map v10): READY fell with the motor on {w[0xA3]} times | DECODER TOLERANCE: used {w[0xA4]} times, RD_CTRL={rc:04X} ({'tolerance OFF' if rc & 1 else 'tolerance on'}){flag}")
    for e in extra: print(e)

def main():
    args = sys.argv[1:]
    only = []
    while "--only" in args:
        i = args.index("--only")
        only.append(args[i + 1]); del args[i:i + 2]
    if not args:
        sys.exit(__doc__)
    c = json.load(open(args[0]))
    numbers = [int(a) for a in args[1:]] or range(1, len(c) + 1)
    for idx in numbers:
        for lab, w, notes in dumps_of(c[idx - 1]["body"]):
            tag = f"comment {idx} / {lab}"
            if only and not any(k in tag for k in only): continue
            show(tag, w, notes)

if __name__ == "__main__":
    main()
