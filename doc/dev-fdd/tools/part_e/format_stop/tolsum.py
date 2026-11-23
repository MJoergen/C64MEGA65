#!/usr/bin/env python3
"""Table of tolsurvey.py results: one row per capture and variant, and the
totals. Usage: tolsum.py <result.txt>..."""
import sys, os, re

rows = {}
extra = []
tot = {}
for path in sys.argv[1:]:
    name = os.path.basename(path)[:-4]
    txt = open(path).read().splitlines()
    i = [k for k, l in enumerate(txt) if l.startswith('variant ')][0]
    for l in txt[i + 1:]:
        if not l.strip():
            break
        p = l.split()
        v = p[0]; nums = list(map(int, p[1:]))
        rows.setdefault(name, []).append((v, nums))
        t = tot.setdefault(v, [0] * len(nums))
        for k, x in enumerate(nums):
            t[k] += x
    sp = [l for l in txt if l.startswith('distinct sectors')]
    sides = [l for l in txt if l.startswith('sides ')]
    base = [l for l in txt if l.startswith('decoder without tolerance')]
    pairs = [l.strip() for l in txt if l.startswith('   A ') or l.startswith('   A_wide ')]
    marg = [l for l in txt if l.startswith('real sync trains')]
    extra.append((name, sides[0] if sides else '', sp[0] if sp else '', base[0] if base else '', pairs, marg[0] if marg else ''))

hdr = '%-50s %-7s %7s %6s %7s %7s %6s %5s %5s %5s %6s' % ('capture', 'variant', 'IDok', 'IDbad', 'DATAok', 'DATAbad', 'gained', 'lost', 'PLLok', 'PLLno', 'uses')
print(hdr)
for name in sorted(rows):
    for v, n in rows[name]:
        print('%-50s %-7s %7d %6d %7d %7d %6d %5d %5d %5d %6d' % ((name[:50], v) + tuple(n)))
print()
for v, n in tot.items():
    print('%-50s %-7s %7d %6d %7d %7d %6d %5d %5d %5d %6d' % (('TOTAL', v) + tuple(n)))
print()
for name, sides, sp, base, pairs, marg in sorted(extra):
    print('%s: %s; %s' % (name, sides, sp))
    print('   ' + base)
    print('   ' + marg)
    for p in pairs:
        print('   pairs ' + p)
