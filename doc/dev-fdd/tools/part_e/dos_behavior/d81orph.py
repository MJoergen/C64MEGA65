#!/usr/bin/env python3
# Structure-only analysis of a D81: directory, block chains, BAM, orphan blocks.
# Prints no file contents. Usage: python3 -I d81orph.py image.d81 [-v]
import sys

def off(t, s):
    return ((t - 1) * 40 + s) * 256

def blk(img, t, s):
    o = off(t, s)
    return img[o:o + 256]

def bam_free(img):
    free = set()
    for half, (bt, bs) in enumerate(((40, 1), (40, 2))):
        b = blk(img, bt, bs)
        for i in range(40):
            t = half * 40 + i + 1
            e = b[0x10 + 6 * i:0x10 + 6 * i + 6]
            bits = int.from_bytes(e[1:6], 'little')
            for s in range(40):
                if bits >> s & 1:
                    free.add((t, s))
    return free

def chain(img, t, s, limit=4000):
    out = []
    seen = set()
    while t != 0 and len(out) < limit:
        if not (1 <= t <= 80 and 0 <= s < 40) or (t, s) in seen:
            out.append(('BAD', t, s))
            break
        seen.add((t, s))
        b = blk(img, t, s)
        out.append((t, s, b[0], b[1]))
        t, s = b[0], b[1]
    return out

def directory(img):
    ents = []
    t, s = 40, 3
    seen = set()
    while t != 0 and (t, s) not in seen:
        seen.add((t, s))
        b = blk(img, t, s)
        for i in range(8):
            e = b[i * 32:(i + 1) * 32]
            typ = e[2]
            if typ == 0:
                continue
            name = bytes(e[5:21]).rstrip(b'\xa0').decode('latin-1')
            ents.append(dict(dirts=(t, s, i), typ=typ, t=e[3], s=e[4], name=name,
                             blocks=e[30] | e[31] << 8, ss=(e[21], e[22])))
        t, s = b[0], b[1]
    return ents, seen

def analyze(path, verbose=False):
    img = open(path, 'rb').read()
    free = bam_free(img)
    ents, dirblocks = directory(img)
    used = {(40, 0), (40, 1), (40, 2)} | dirblocks
    files = []
    for e in ents:
        if e['typ'] & 0x07 == 0 and e['t'] == 0:
            continue  # DEL entry without blocks
        c = chain(img, e['t'], e['s'])
        blks = [(x[0], x[1]) for x in c if x[0] != 'BAD']
        last = c[-1] if c else None
        fill = (last[3] - 1) if last and last[0] != 'BAD' and last[2] == 0 else None
        nbytes = 254 * (len(blks) - 1) + fill if fill is not None else None
        e.update(chain=blks, fill=fill, nbytes=nbytes, bad=any(x[0] == 'BAD' for x in c))
        if e['ss'][0]:
            ssc = chain(img, *e['ss'])
            e['sschain'] = [(x[0], x[1]) for x in ssc if x[0] != 'BAD']
            used |= set(e['sschain'])
        used |= set(blks)
        files.append(e)
    allb = {(t, s) for t in range(1, 81) for s in range(40)}
    alloc = allb - free
    orphans = sorted(alloc - used)
    freed_but_used = sorted(used & free)
    return img, files, free, orphans, freed_but_used

def main():
    path = sys.argv[1]
    verbose = '-v' in sys.argv
    img, files, free, orphans, fbu = analyze(path, verbose)
    print(f'{path}: {len(files)} files, BAM free {len([b for b in free if b[0] != 40])}'
          f' (of 3160, excl. track 40), orphans {len(orphans)}: {orphans}')
    if fbu:
        print('  blocks used by files but free in BAM:', fbu)
    full = [f for f in files if f['fill'] == 254]
    print(f'  files with a completely full last block (fill 254): {len(full)}')
    for i, f in enumerate(files):
        tag = 'FULL' if f['fill'] == 254 else ''
        if verbose or tag:
            print(f"  #{i:3d} typ={f['typ']:02X} blk={f['blocks']:4d} chain={len(f['chain']):4d}"
                  f" first={f['chain'][0] if f['chain'] else None} last={f['chain'][-1] if f['chain'] else None}"
                  f" fill={f['fill']} bytes={f['nbytes']} {tag} {'BADCHAIN' if f['bad'] else ''}"
                  + (f" name={f['name']}" if '-n' in sys.argv else ''))

if __name__ == '__main__':
    main()
