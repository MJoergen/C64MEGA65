#!/usr/bin/env python3
"""Minimal SCP reader + IBM MFM decoder (issue #257, part E).

Usage:
  scp.py info  <file.scp>
  scp.py track <file.scp> <cyl> <head> [--verbose]

Data-only: reads flux, never interprets sector payloads beyond CRC/zero checks.
"""
import struct, sys

def read_scp(path):
    with open(path, 'rb') as f:
        data = f.read()
    assert data[0:3] == b'SCP', 'not an SCP file'
    hdr = dict(version=data[3], disk_type=data[4], revs=data[5], start=data[6],
               end=data[7], flags=data[8], cellw=data[9], heads=data[10],
               res=data[11])
    hdr['tick_ns'] = 25.0 * (hdr['res'] + 1)
    offs = struct.unpack('<168I', data[16:16 + 168 * 4])
    return data, hdr, offs

def track_revs(data, hdr, offs, tnum):
    """Return list of (index_time_ticks, [flux ticks]) per revolution."""
    o = offs[tnum]
    if o == 0:
        return None
    assert data[o:o + 3] == b'TRK', 'bad TRK at %d' % o
    revs = []
    for r in range(hdr['revs']):
        it, nflux, doff = struct.unpack('<III', data[o + 4 + 12 * r:o + 16 + 12 * r])
        raw = data[o + doff:o + doff + 2 * nflux]
        vals = struct.unpack('>%dH' % nflux, raw)
        flux = []
        acc = 0
        for v in vals:
            if v == 0:
                acc += 65536
            else:
                flux.append(acc + v)
                acc = 0
        revs.append((it, flux))
    return revs

# ---------------------------------------------------------------- MFM
def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc

def flux_to_bits(flux_ns, cell_ns=4000.0, pll_gain=0.05):
    """Simple software PLL: returns list of bits (raw MFM cells, half-cells of
    1 us for DD) and the time (ns) of each bit. cell_ns = MFM bit cell (2 us DD
    data bit -> 1 us per raw cell)."""
    half = cell_ns / 2.0           # raw MFM cell = 1 us
    per = half
    bits = []
    times = []
    t = 0.0
    for f in flux_ns:
        t_flux = f
        # number of cells this interval spans
        n = int(round(t_flux / per))
        if n < 1:
            n = 1
        err = t_flux - n * per
        per += pll_gain * err / n
        per = min(max(per, half * 0.9), half * 1.1)
        for k in range(n - 1):
            bits.append(0)
        bits.append(1)
        t += f
        times.append(t)
    return bits

def decode_track(flux_ns):
    """Decode an IBM MFM track. Returns list of records:
    ('ID', bitpos, c,h,r,n, crc_ok) / ('DAM', bitpos, mark, len, crc_ok)
    bit positions are indices into the raw cell stream."""
    bits = flux_to_bits(flux_ns)
    # build cumulative time per raw cell index for position reporting
    s = ''.join('1' if b else '0' for b in bits)
    SYNC = '0100010010001001'   # 4489
    recs = []
    i = 0
    L = len(s)
    def get_byte(pos):
        # data bits at odd positions of 16 raw cells
        w = s[pos:pos + 16]
        if len(w) < 16:
            return None
        v = 0
        for k in range(8):
            v = (v << 1) | (1 if w[2 * k + 1] == '1' else 0)
        return v
    while True:
        j = s.find(SYNC * 3, i)
        if j < 0:
            break
        p = j + 48
        mark = get_byte(p)
        if mark == 0xFE:
            by = [get_byte(p + 16 * k) for k in range(1, 7)]
            if None in by:
                break
            ok = crc16([0xA1, 0xA1, 0xA1, 0xFE] + by) == 0
            recs.append(('ID', j, by[0], by[1], by[2], by[3], ok))
            i = p + 16 * 7
        elif mark in (0xFB, 0xF8):
            n = 512
            by = [get_byte(p + 16 * k) for k in range(1, n + 3)]
            if None in by:
                recs.append(('DAM', j, mark, n, None, None))
                break
            ok = crc16([0xA1, 0xA1, 0xA1, mark] + by) == 0
            allzero = all(b == 0 for b in by[:n])
            recs.append(('DAM', j, mark, n, ok, allzero))
            i = p + 16 * (n + 3)
        else:
            recs.append(('MARK?', j, mark))
            i = p
    return recs, s

def main():
    cmd = sys.argv[1]
    data, hdr, offs = read_scp(sys.argv[2])
    if cmd == 'info':
        print(hdr)
        tracks = [k for k in range(168) if offs[k]]
        print('tracks present:', len(tracks), tracks[:4], '...', tracks[-4:])
        return
    if cmd == 'track':
        cyl, head = int(sys.argv[3]), int(sys.argv[4])
        tn = cyl * 2 + head
        revs = track_revs(data, hdr, offs, tn)
        tick = hdr['tick_ns']
        for r, (it, flux) in enumerate(revs):
            fns = [v * tick for v in flux]
            print('rev %d: index time %.3f ms, %d flux, sum %.3f ms' % (
                r, it * tick / 1e6, len(flux), sum(fns) / 1e6))
            recs, s = decode_track(fns)
            for rec in recs:
                pos_ms = rec[1] * 2e-3   # 1 raw cell ~ 2 us
                if rec[0] == 'ID':
                    print('   %8.3f ms ID  C=%d H=%d R=%d N=%d crc=%s' % (pos_ms, rec[2], rec[3], rec[4], rec[5], 'ok' if rec[6] else 'BAD'))
                elif rec[0] == 'DAM':
                    print('   %8.3f ms DAM %02X crc=%s zero=%s' % (pos_ms, rec[2], rec[4], rec[5]))
                else:
                    print('   %8.3f ms %s' % (pos_ms, rec))

if __name__ == '__main__':
    main()
