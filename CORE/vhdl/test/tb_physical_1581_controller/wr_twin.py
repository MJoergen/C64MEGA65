#!/usr/bin/env python3
"""wr_twin.py - independent twin of the physical 1581 write path (issue #244).

A second implementation of the write serialization rules of WRITE-SPEC
5.5/5.6, written from the rules and not from the HDL, used to check the flux
that tb_physical_1581_write.vhd leaves in the writable mechanism model
(mech_model_1581, G_WRITABLE):

  * MFM: channel word c7 d7 c6 d6 ... c0 d0 per byte, c_i = not d_(i+1) and
    not d_i with d_8 the last data bit of the previous byte, carried across
    every byte boundary (sync words and CRC bytes included) and 0 at the
    start of a session; A1 sync = 0x4489 (carried bit afterwards 1), C2 sync
    = 0x5224 (carried bit afterwards 0); channel bits leave MSB first.
  * CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF). Write Sector: preset at
    the first A1, fed A1 A1 A1 DAM data[512], emitted high byte first, then
    one FF. Write Track tokens: F5 = A1 sync (preset when the previous token
    was not F5), F6 = C2 sync (fed), F7 = CRC high + low (two words), any
    other token a plain byte (fed).
  * Cell 100 cycles at 50 MHz, the falling WDATA edge of a '1' channel bit
    at cycle 50 of its cell, +/-7 cycles of precompensation: the direction
    comes from the wall-clock table of the MEGA65 core's floppy writer
    (AExp .research/RESEARCH-write-mega65-core.md section 4; written bit in
    the middle of a 7-bit neighbourhood, old -> new left -> right):
        0101000 early   1001000 early   0001000 none
        0101010 none    1001010 late    0001010 late
        0101001 early   1001001 none    0001001 late    others none
    A bit whose 7-bit neighbourhood reaches outside its session is not
    shifted (the boundary rule).
  * Edge k of a window sits at (wstart + 100*c + launch) mod t_rev, where
    wstart is the model's WGATE-fall position (the model samples the gate
    and WDATA in the same clock, so its one-clock sampling delay cancels).

Inputs (written by the bench):
  dump    '# meta t_rev=.. cell=.. slot=.. cyl=.. side=.. seed_key=.. windows=..'
          'G <gen> <open_pos> <len_cycles>'   one per WGATE window of the track
          'E <pos> <gen>'                     final flux (gen 0 = seed)
          'P <pos>'                           the seed as laid (pre-seed)
  stream  'S gen=<gen> kind=sector|track precomp=0|1 [dam=FB|F8]'
          'D <hex payload, 512 bytes>'  or  'T <hex tokens>'

Verdicts, each failing the run:
  V1  window length: sector = 531 words x 1600 cycles exactly; track = the
      window is a prefix of the token stream's words (cut at the index)
  V2  every expected edge of a window exists in the final flux with that
      window's generation within +/-1 cycle, and every final edge of that
      generation is expected (edge for edge)
  V3  no seed edge survives inside any written span
  V4  outside the written spans the final flux equals the pre-seed exactly
  V5  intervals between consecutive edges inside a span are 200/300/400
      +/- 16 cycles (legal MFM)
  D   an independent decoder (own quantiser, own sync search, own byte
      assembly and CRC) over the final flux reports every record (ID C/H/R/N
      + ID CRC, DAM, data CRC); the data field written in each sector window
      must decode with a good CRC and the stream's payload, and every ID on
      the track must have a good CRC (the splices did not damage an ID)

--flip-precomp predicts with every window's precomp flag inverted; the bench
runner uses it as a red control (it must fail where the flag mattered).
--selftest runs the twin's own red controls.

Usage:
  wr_twin.py --stream S --dump D [--flip-precomp] [--quiet]
  wr_twin.py --selftest
"""

import sys

CELL = 100
LAUNCH = 50
PRE = 7
TOL = 1
IV_TOL = 2 * PRE + 2
SYNC_A1 = 0x4489
SYNC_C2 = 0x5224
SECTOR_WORDS = 12 + 3 + 1 + 512 + 2 + 1      # 531

PRECOMP_TABLE = {
    "0101000": -1, "1001000": -1, "0001000": 0,
    "0101010": 0, "1001010": +1, "0001010": +1,
    "0101001": -1, "1001001": 0, "0001001": +1,
}


# ---------------------------------------------------------------------------
# encoder twin
# ---------------------------------------------------------------------------

def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


class Enc:
    """byte/mark -> channel words, with the carried data bit and a CRC."""

    def __init__(self, carry=True, a1_word=SYNC_A1, lsb_first=False):
        self.p = 0
        self.crc = 0xFFFF
        self.words = []
        self.carry = carry
        self.a1_word = a1_word
        self.lsb_first = lsb_first

    def plain(self, b, feed):
        w = 0
        prev = self.p if self.carry else 0
        for i in range(7, -1, -1):
            d = (b >> i) & 1
            c = 1 if (prev == 0 and d == 0) else 0
            w = (w << 2) | (c << 1) | d
            prev = d
        self.p = b & 1
        self.words.append(w)
        if feed:
            self.crc = crc16([b], self.crc)

    def a1(self, preset):
        if preset:
            self.crc = 0xFFFF
        self.words.append(self.a1_word)
        self.p = 1
        self.crc = crc16([0xA1], self.crc)

    def c2(self):
        self.words.append(SYNC_C2)
        self.p = 0
        self.crc = crc16([0xC2], self.crc)

    def crc_out(self):
        c = self.crc
        self.plain(c >> 8, False)
        self.plain(c & 0xFF, False)


def sector_words(payload, dam=0xFB, **kw):
    preset_first = kw.pop("preset", True)
    feed_runup = kw.pop("feed_runup", False)
    e = Enc(**kw)
    for _ in range(12):
        e.plain(0x00, feed_runup)
    for i in range(3):
        e.a1(preset_first and i == 0)
    e.plain(dam, True)
    for b in payload:
        e.plain(b, True)
    e.crc_out()
    e.plain(0xFF, False)
    return e.words


def track_words(tokens, **kw):
    e = Enc(**kw)
    prev = None
    for t in tokens:
        if t == 0xF5:
            e.a1(prev != 0xF5)
        elif t == 0xF6:
            e.c2()
        elif t == 0xF7:
            e.crc_out()
        else:
            e.plain(t, True)
        prev = t
    return e.words


def words_to_bits(words, lsb_first=False):
    bits = []
    for w in words:
        rng = range(0, 16) if lsb_first else range(15, -1, -1)
        for j in rng:
            bits.append((w >> j) & 1)
    return bits


def launch(bits, c, precomp, sign=+1):
    if not precomp:
        return LAUNCH
    if c - 3 < 0 or c + 3 >= len(bits):
        return LAUNCH                     # boundary rule
    pat = "".join(str(b) for b in bits[c - 3:c + 4])
    d = PRECOMP_TABLE.get(pat, 0)
    return LAUNCH + sign * d * PRE


def expected_edges(words, wstart, t_rev, precomp, wlen=None, cell=CELL,
                   sign=+1, lsb_first=False):
    bits = words_to_bits(words, lsb_first)
    out = []
    for c, b in enumerate(bits):
        if not b:
            continue
        off = cell * c + launch(bits, c, precomp, sign)
        if wlen is not None and off >= wlen:
            break                         # cut at the window end
        out.append((wstart + off) % t_rev)
    return out


# ---------------------------------------------------------------------------
# independent decoder over the flux
# ---------------------------------------------------------------------------

def flux_bits(edges, t_rev, revs=2):
    """Edge list -> channel bit stream with the bit positions (cycles)."""
    e = sorted(edges)
    if not e:
        return [], []
    seq = []
    for r in range(revs):
        seq += [x + r * t_rev for x in e]
    bits, where = [], []
    for a, b in zip(seq, seq[1:]):
        g = b - a
        n = int(round(g / CELL))
        if n < 2 or n > 4 or abs(g - n * CELL) > 45:
            # not a legal MFM interval (a splice): emit it anyway, the sync
            # search below re-frames on the next A1
            n = max(1, min(n, 5))
        for k in range(n - 1):
            bits.append(0)
            where.append(a + (k + 1) * CELL)
        bits.append(1)
        where.append(b)
    return bits, where


def decode(edges, t_rev):
    """Find every A1-synced record; return a list of dicts."""
    bits, where = flux_bits(edges, t_rev)
    recs = []
    sh = 0
    i = 0
    n = len(bits)

    def word_at(j):
        w = 0
        for k in range(16):
            w = (w << 1) | bits[j + k]
        return w

    def data_byte(w):
        b = 0
        for k in range(7, -1, -1):
            b = (b << 1) | ((w >> (2 * k)) & 1)
        return b

    while i < n:
        sh = ((sh << 1) | bits[i]) & 0xFFFF
        i += 1
        if sh != SYNC_A1:
            continue
        # an A1 ends at bit i-1; count the run
        na1 = 1
        j = i
        while j + 16 <= n and word_at(j) == SYNC_A1:
            na1 += 1
            j += 16
        if j + 16 > n:
            break
        mark = data_byte(word_at(j))
        pos = where[i - 16] % t_rev
        j += 16
        if mark == 0xFE and j + 6 * 16 <= n:
            body = [data_byte(word_at(j + 16 * k)) for k in range(6)]
            crc = crc16([0xA1] * na1 + [0xFE] + body[:4])
            recs.append({"kind": "ID", "pos": pos, "a1": na1, "chrn": body[:4],
                         "crc_ok": crc == (body[4] << 8 | body[5])})
            i = j + 6 * 16
            sh = 0
        elif mark in (0xFB, 0xF8) and j + 514 * 16 <= n:
            body = [data_byte(word_at(j + 16 * k)) for k in range(514)]
            crc = crc16([0xA1] * na1 + [mark] + body[:512])
            recs.append({"kind": "DATA", "pos": pos, "a1": na1, "dam": mark,
                         "data": body[:512],
                         "crc_ok": crc == (body[512] << 8 | body[513])})
            i = j + 514 * 16
            sh = 0
    # one revolution's worth, deduplicated by position
    seen, out = set(), []
    for r in recs:
        if r["pos"] in seen:
            continue
        seen.add(r["pos"])
        out.append(r)
    return out


# ---------------------------------------------------------------------------
# dump / stream parsing and the verdicts
# ---------------------------------------------------------------------------

def parse_dump(path):
    meta, wins, fin, pre = {}, [], [], []
    for ln in open(path):
        t = ln.split()
        if not t:
            continue
        if t[0] == "#":
            for kv in t[2:]:
                k, v = kv.split("=")
                meta[k] = int(v)
        elif t[0] == "G":
            wins.append({"gen": int(t[1]), "pos": int(t[2]), "len": int(t[3])})
        elif t[0] == "E":
            fin.append((int(t[1]), int(t[2])))
        elif t[0] == "P":
            pre.append(int(t[1]))
    return meta, wins, fin, pre


def parse_stream(path):
    secs = []
    cur = None
    for ln in open(path):
        t = ln.split()
        if not t:
            continue
        if t[0] == "S":
            cur = {"kind": "sector", "precomp": 0, "dam": 0xFB}
            for kv in t[1:]:
                k, v = kv.split("=")
                if k == "gen":
                    cur["gen"] = int(v)
                elif k == "kind":
                    cur["kind"] = v
                elif k == "precomp":
                    cur["precomp"] = int(v)
                elif k == "dam":
                    cur["dam"] = int(v, 16)
            secs.append(cur)
        elif t[0] in ("D", "T"):
            h = t[1]
            cur["bytes"] = [int(h[k:k + 2], 16) for k in range(0, len(h), 2)]
    return secs


def in_span(p, s, n, t_rev):
    return (p - s) % t_rev < n


def check(stream_path, dump_path, flip=False, quiet=False):
    meta, wins, fin, pre = parse_dump(dump_path)
    secs = parse_stream(stream_path)
    t_rev = meta["t_rev"]
    errs = []
    say = (lambda *a: None) if quiet else print
    by_gen = {w["gen"]: w for w in wins}
    fin_by_gen = {}
    for p, g in fin:
        fin_by_gen.setdefault(g, []).append(p)

    say("twin: %s + %s: t_rev=%d cyl=%d side=%d seed_key=%d, %d window(s), %d stream section(s)%s"
        % (dump_path, stream_path, t_rev, meta.get("cyl", -1), meta.get("side", -1),
           meta.get("seed_key", -1), len(wins), len(secs), " [precomp flipped]" if flip else ""))
    if len(secs) != len(wins):
        errs.append("stream has %d sections, the dump %d windows" % (len(secs), len(wins)))

    spans = [(w["pos"], w["len"]) for w in wins]
    for sec in secs:
        w = by_gen.get(sec["gen"])
        if w is None:
            errs.append("gen %d: no such window in the dump" % sec["gen"])
            continue
        prec = sec["precomp"] ^ (1 if flip else 0)
        if sec["kind"] == "sector":
            words = sector_words(sec["bytes"], sec["dam"])
            if w["len"] != len(words) * 1600:
                errs.append("V1 gen %d: window %d cycles, expected %d" % (w["gen"], w["len"], len(words) * 1600))
        else:
            words = track_words(sec["bytes"])
            if w["len"] > len(words) * 1600 or w["len"] % CELL != 0:
                errs.append("V1 gen %d: window %d cycles for %d words" % (w["gen"], w["len"], len(words)))
        exp = expected_edges(words, w["pos"], t_rev, prec, wlen=w["len"])
        # edges of later windows overwrite earlier ones (none in these scenarios)
        later = [(x["pos"], x["len"]) for x in wins if x["gen"] > w["gen"]]
        exp = [e for e in exp if not any(in_span(e, s, n, t_rev) for s, n in later)]
        got = sorted(fin_by_gen.get(w["gen"], []))
        gs = set(got)
        miss = [e for e in exp if not any(((e + d) % t_rev) in gs for d in range(-TOL, TOL + 1))]
        es = set(exp)
        extra = [g for g in got if not any(((g + d) % t_rev) in es for d in range(-TOL, TOL + 1))]
        if miss or extra:
            errs.append("V2 gen %d: %d expected edges missing, %d unexpected (first missing %s, first extra %s)"
                        % (w["gen"], len(miss), len(extra), miss[:3], extra[:3]))
        bits = words_to_bits(words)
        sh_e = sum(1 for c, b in enumerate(bits) if b and launch(bits, c, prec) < LAUNCH)
        sh_l = sum(1 for c, b in enumerate(bits) if b and launch(bits, c, prec) > LAUNCH)
        say("  window gen=%d pos=%d len=%d (%s, %d words, precomp=%d): %d edges, %d expected, "
            "%d missing, %d extra; predicted shifts early=%d late=%d"
            % (w["gen"], w["pos"], w["len"], sec["kind"], len(words), prec, len(got), len(exp),
               len(miss), len(extra), sh_e, sh_l))
        # V5
        inside = sorted((p - w["pos"]) % t_rev for p in got)
        bad_iv = [b - a for a, b in zip(inside, inside[1:])
                  if min(abs((b - a) - k) for k in (200, 300, 400)) > IV_TOL]
        if bad_iv:
            errs.append("V5 gen %d: %d illegal intervals, e.g. %s" % (w["gen"], len(bad_iv), bad_iv[:5]))

    # V3 / V4
    surv = [p for p, g in fin if g == 0 and any(in_span(p, s, n, t_rev) for s, n in spans)]
    if surv:
        errs.append("V3: %d seed edges survive inside the written spans, e.g. %s" % (len(surv), surv[:3]))
    out_fin = sorted(p for p, g in fin if not any(in_span(p, s, n, t_rev) for s, n in spans))
    out_pre = sorted(p for p in pre if not any(in_span(p, s, n, t_rev) for s, n in spans))
    if out_fin != out_pre:
        a, b = set(out_fin), set(out_pre)
        errs.append("V4: outside the spans %d edges differ from the pre-seed (%d new, %d lost)"
                    % (len(a ^ b), len(a - b), len(b - a)))

    # independent decode
    recs = decode([p for p, g in fin], t_rev)
    ids = [r for r in recs if r["kind"] == "ID"]
    dats = [r for r in recs if r["kind"] == "DATA"]
    say("  decode: %d ID fields (%d CRC ok), %d data fields (%d CRC ok)"
        % (len(ids), sum(r["crc_ok"] for r in ids), len(dats), sum(r["crc_ok"] for r in dats)))
    for r in ids:
        if not r["crc_ok"]:
            errs.append("D: ID at %d C/H/R/N=%s has a bad CRC" % (r["pos"], r["chrn"]))
    for sec in secs:
        w = by_gen.get(sec["gen"])
        if w is None:
            continue
        if sec["kind"] == "sector":
            hit = [r for r in dats if in_span(r["pos"], w["pos"], w["len"], t_rev)]
            if len(hit) != 1:
                errs.append("D gen %d: %d data fields decoded inside the window" % (w["gen"], len(hit)))
                continue
            r = hit[0]
            prev_ids = sorted(ids, key=lambda x: (r["pos"] - x["pos"]) % t_rev)
            chrn = prev_ids[0]["chrn"] if prev_ids else None
            ok = r["crc_ok"] and r["data"] == sec["bytes"] and r["dam"] == sec["dam"]
            say("  record C/H/R/N=%s DAM=%02X data CRC %s, payload %s (first bytes %s)"
                % (chrn, r["dam"], "ok" if r["crc_ok"] else "BAD",
                   "= stream" if r["data"] == sec["bytes"] else "DIFFERS",
                   " ".join("%02X" % x for x in r["data"][:6])))
            if not ok:
                errs.append("D gen %d: written data field does not decode to the stream" % w["gen"])
        else:
            say("  track window: %d IDs and %d data fields on the track after the write"
                % (len(ids), len(dats)))
    for e in errs:
        print("  FAIL " + e)
    print("twin: %s" % ("PASS" if not errs else "FAIL (%d)" % len(errs)))
    return not errs


# ---------------------------------------------------------------------------
# self test: the twin's own red controls
# ---------------------------------------------------------------------------

def selftest():
    import random
    rnd = random.Random(244)
    ok = True
    t_rev = 10_000_000
    payload = [rnd.randrange(256) for _ in range(512)]
    ref_words = sector_words(payload)
    assert len(ref_words) == SECTOR_WORDS
    # anchors
    e = Enc()
    for i in range(3):
        e.a1(i == 0)
    if e.crc != 0xCDB4:
        print("selftest FAIL: CRC after A1 A1 A1 = %04X" % e.crc); ok = False
    if crc16(b"123456789") != 0x29B1:
        print("selftest FAIL: CRC-16/CCITT-FALSE check value"); ok = False
    # the precomp table against hand-built neighbourhoods
    cases = [("0101000", -1), ("0001010", +1), ("0101010", 0), ("1001001", 0),
             ("0101001", -1), ("0001001", +1), ("1001000", -1), ("1001010", +1),
             ("1101000", 0)]
    for pat, d in cases:
        bits = [int(x) for x in pat]
        if launch(bits, 3, True) != LAUNCH + d * PRE:
            print("selftest FAIL: precomp table %s" % pat); ok = False
    if launch([1, 0, 1, 0, 0, 0, 0], 2, True) != LAUNCH:
        print("selftest FAIL: boundary rule"); ok = False

    for prec in (0, 1):
        ref = expected_edges(ref_words, 1234, t_rev, prec)
        refs = set(ref)

        def differs(other):
            return set(other) != refs
        mutants = {
            "LSB-first words": expected_edges(ref_words, 1234, t_rev, prec, lsb_first=True),
            "no carried clock bit": expected_edges(sector_words(payload, carry=False), 1234, t_rev, prec),
            "plain A1 instead of 0x4489": expected_edges(sector_words(payload, a1_word=0x44A9), 1234, t_rev, prec),
            "CRC not preset at the sync (run-up fed)": expected_edges(
                sector_words(payload, preset=False, feed_runup=True), 1234, t_rev, prec),
            "99-cycle cell": expected_edges(ref_words, 1234, t_rev, prec, cell=99),
            "101-cycle cell": expected_edges(ref_words, 1234, t_rev, prec, cell=101),
            "one word dropped": expected_edges(ref_words[:200] + ref_words[201:], 1234, t_rev, prec),
            "splice one byte late": expected_edges(ref_words, 1234 + 1600, t_rev, prec),
        }
        if prec:
            mutants["precomp sign inverted"] = expected_edges(ref_words, 1234, t_rev, prec, sign=-1)
        else:
            mutants["precomp on"] = expected_edges(ref_words, 1234, t_rev, 1)
        for name, m in mutants.items():
            if not differs(m):
                print("selftest FAIL: mutant '%s' (precomp=%d) not detected" % (name, prec)); ok = False
        # the decoder decodes the reference and rejects a flipped bit
        recs = decode(ref, t_rev)
        d = [r for r in recs if r["kind"] == "DATA"]
        if not (len(d) == 1 and d[0]["crc_ok"] and d[0]["data"] == payload):
            print("selftest FAIL: decoder on the reference (precomp=%d)" % prec); ok = False
        bad = list(ref_words)
        bad[100] ^= 0x0004 | 0x0010            # move a transition inside a data byte
        recs = decode(expected_edges(bad, 1234, t_rev, prec), t_rev)
        d = [r for r in recs if r["kind"] == "DATA"]
        if d and d[0]["crc_ok"]:
            print("selftest FAIL: decoder accepted a corrupted data field"); ok = False
        recs = decode(expected_edges(sector_words(payload, a1_word=0x44A9), 1234, t_rev, prec), t_rev)
        if any(r["kind"] == "DATA" for r in recs):
            print("selftest FAIL: decoder synced on a plain A1"); ok = False
    # track tokens: F5 F5 F5 FE ... F7 equals the sector-style ID field
    toks = [0x4E] * 4 + [0x00] * 12 + [0xF5] * 3 + [0xFE, 1, 0, 3, 2, 0xF7] + [0x4E] * 4
    tw = track_words(toks)
    recs = decode(expected_edges(tw, 0, t_rev, 0), t_rev)
    ids = [r for r in recs if r["kind"] == "ID"]
    if not (len(ids) == 1 and ids[0]["crc_ok"] and ids[0]["chrn"] == [1, 0, 3, 2]):
        print("selftest FAIL: track tokens F5/F7"); ok = False
    toks_bad = [0x4E] * 4 + [0x00] * 12 + [0xF5] * 3 + [0xFE, 1, 0, 3, 2, 0xF7]
    e = Enc()
    for t in toks_bad:                       # F5 presetting on every token (mutant iv)
        if t == 0xF5:
            e.a1(True)
        elif t == 0xF7:
            e.crc_out()
        else:
            e.plain(t, True)
    recs = decode(expected_edges(e.words + [0xAAAA] * 4, 0, t_rev, 0), t_rev)
    if any(r["kind"] == "ID" and r["crc_ok"] for r in recs):
        print("selftest FAIL: per-token F5 preset not detected"); ok = False
    print("wr_twin selftest: %s" % ("PASS" if ok else "FAIL"))
    return ok


def main(argv):
    if "--selftest" in argv:
        return 0 if selftest() else 1
    stream = dump = None
    flip = "--flip-precomp" in argv
    quiet = "--quiet" in argv
    for k, a in enumerate(argv):
        if a == "--stream":
            stream = argv[k + 1]
        elif a == "--dump":
            dump = argv[k + 1]
    if not stream or not dump:
        print(__doc__)
        return 2
    return 0 if check(stream, dump, flip, quiet) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
