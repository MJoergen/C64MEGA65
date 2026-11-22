#!/usr/bin/env python3
"""List the sector ID fields (C H R N, CRC) found on every physical track of an SCP flux file.

Only ID address marks are decoded (A1 A1 A1 FE C H R N CRC); no sector data is decoded or
printed. Usage: python3 -I scp_ids.py file.scp [rev]
Output per track: phys cyl, head, number of IDs, the set of C values (with counts), the H values,
R values seen, CRC failures, and the time (ms after index) of the first ID.
"""
import struct
import sys
from collections import Counter


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else (crc << 1)
            crc &= 0xFFFF
    return crc


def read_scp(path):
    raw = open(path, "rb").read()
    assert raw[:3] == b"SCP"
    revs = raw[5]
    res = raw[11]
    tick_ns = 25 * (res + 1)
    offs = struct.unpack("<168I", raw[16:16 + 168 * 4])
    tracks = {}
    for t, o in enumerate(offs):
        if not o:
            continue
        assert raw[o:o + 3] == b"TRK", (t, raw[o:o + 4])
        rv = []
        for r in range(revs):
            idx_t, length, doff = struct.unpack("<III", raw[o + 4 + 12 * r:o + 16 + 12 * r])
            rv.append((idx_t, length, o + doff))
        tracks[t] = rv
    return raw, tracks, tick_ns


def flux_us(raw, start, length, tick_ns):
    vals = struct.unpack(">%dH" % length, raw[start:start + 2 * length])
    out = []
    acc = 0
    for v in vals:
        if v == 0:
            acc += 65536
            continue
        out.append((acc + v) * tick_ns / 1000.0)
        acc = 0
    return out


def cells(fl):
    """Simple adaptive clock: cell nominal 2 us (DD), track the average."""
    cell = 2.0
    bits = []
    times = []
    t = 0.0
    for d in fl:
        t += d
        n = int(round(d / cell))
        if n < 2:
            n = 2
        if n > 5:
            n = 5
        # adapt slowly
        cell += 0.02 * (d / n - cell)
        bits.extend([0] * (n - 1))
        bits.append(1)
        times.append((len(bits), t))
    return bits, times


def decode_ids(bits, times):
    # sync word 0x4489 as cell bits
    sync = [int(c) for c in format(0x4489, "016b")]
    s = "".join(map(str, bits))
    pat = "".join(map(str, sync)) * 3
    ids = []
    pos = s.find(pat)
    tmap = times
    ti = 0
    while pos >= 0:
        p = pos + 48
        # decode 7 bytes: mark + C H R N + CRC(2)
        byts = []
        for k in range(7):
            seg = s[p + 16 * k:p + 16 * (k + 1)]
            if len(seg) < 16:
                break
            v = 0
            for j in range(8):
                v = (v << 1) | int(seg[2 * j + 1])
            byts.append(v)
        if len(byts) == 7 and byts[0] == 0xFE:
            ok = crc16(bytes([0xA1, 0xA1, 0xA1] + byts)) == 0
            # time of this ID in us
            while ti + 1 < len(tmap) and tmap[ti][0] < pos:
                ti += 1
            ids.append((byts[1], byts[2], byts[3], byts[4], ok, tmap[ti][1] / 1000.0))
        pos = s.find(pat, pos + 48)
    return ids


def main():
    path = sys.argv[1]
    rev = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    raw, tracks, tick = read_scp(path)
    for t in sorted(tracks):
        cyl, head = t // 2, t % 2
        idx_t, length, start = tracks[t][rev]
        fl = flux_us(raw, start, length, tick)
        bits, times = cells(fl)
        ids = decode_ids(bits, times)
        good = [i for i in ids if i[4]]
        bad = len(ids) - len(good)
        cs = Counter(i[0] for i in good)
        hs = Counter(i[1] for i in good)
        rs = sorted(set(i[2] for i in good))
        first = f"{good[0][5]:.1f}" if good else "-"
        print(f"phys c{cyl:02d} h{head}: ids={len(good):2d} badcrc={bad} C={dict(cs)} H={dict(hs)} R={rs} "
              f"firstID@{first}ms flux={len(fl)} rev_ms={idx_t*tick/1e6:.2f}")


if __name__ == "__main__":
    main()
