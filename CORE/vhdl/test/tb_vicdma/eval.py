#!/usr/bin/env python3
"""Evaluate the tb_vicdma runs (issue #259).

usage: eval.py <builddir>

Reads <tag>.log (STAT lines of the monitors), <tag>.pix and <tag>.fetch (VIC-II traces) of the runs
started by run.sh, applies the expectations of each variant and prints C1..C7 and RESULT."""
import re, sys

B = sys.argv[1]
RUNS = ['ref', 'fix', 'fixff', 'a24', 'a24ff', 'x1', 'neg', 'late']
DMA_RUNS = ['fix', 'fixff', 'a24', 'a24ff', 'x1']
CLS = ['bad', 'spr']
S, LOG = {}, {}
for r in RUNS:
    txt = open(f'{B}/{r}.log').read()
    LOG[r] = txt
    S[r] = {m.group(1): int(m.group(2)) for m in re.finditer(rf'STAT {r} (\S+) (-?\d+)', txt)}
    if 'end_ns' not in S[r]:
        sys.exit(f"RESULT: FAIL run {r} did not finish (see {r}.log)")

fails = []


def check(name, cond, msg):
    print(f"  {'ok  ' if cond else 'FAIL'} {name}: {msg}")
    if not cond:
        fails.append(name)


def v(r, k):
    return S[r].get(k, 0)


def tot(r, c, kind):
    return v(r, f'stalls_{c}_{kind}')


def diff(a, b):
    la, lb = open(a).read().splitlines(), open(b).read().splitlines()
    n = sum(1 for x, y in zip(la, lb) if x != y) + abs(len(la) - len(lb))
    first = next((i for i, (x, y) in enumerate(zip(la, lb)) if x != y), None)
    if first is None and len(la) != len(lb):
        first = min(len(la), len(lb))
    return n, first, len(la)


def stalls(r, c):
    return sum(tot(r, c, k) for k in ('non', 'ver', 'fet', 'swa'))


print("C1  VIC-II output and fetch equivalence (tick by tick, three frames, reference = no DMA)")
for r in DMA_RUNS + ['late', 'neg']:
    np_, fp_, lp = diff(f'{B}/ref.pix', f'{B}/{r}.pix')
    nf, ff_, lf = diff(f'{B}/ref.fetch', f'{B}/{r}.fetch')
    desc = (f"{lp} pixel samples, {np_} differ" + (f" (first at sample {fp_})" if fp_ is not None else "") +
            f"; {lf} VIC data samples with AEC, {nf} differ" + (f" (first at sample {ff_})" if ff_ is not None else ""))
    if r == 'neg':
        check("C1 negative control (grace 4, one cycle too many) changes the display", np_ > 0 and nf > 0, desc)
    elif r == 'late':
        print(f"  info C1 {r} (REC resumes one cycle late): {desc}")
    else:
        check(f"C1 {r}", np_ == 0 and nf == 0 and lp > 400000, desc)

print("C2  AEC never high in a DMA-served CPU half; the VIC's phi2 fetches start in BA-low cycle 4")
for r in DMA_RUNS:
    nst = {c: stalls(r, c) for c in CLS}
    check(f"C2 {r}", v(r, 'c2a_viol') == 0 and v(r, 'rep_viol') == 0 and
          all(v(r, f'firstaec_{c}_4') == nst[c] for c in CLS) and v(r, 'earlyc_bad') == 0 and v(r, 'earlys_spr') == 0 and
          v(r, 'cacc_bad') == 40 * nst['bad'],
          f"DMA-served CPU halves {v(r, 'dma_cycles')} (with BA low {v(r, 'dma_cycles_ba_low')}), with AEC {v(r, 'c2a_viol')}; "
          f"first phi2 with AEC in BA-low cycle 4 in {v(r, 'firstaec_bad_4')}/{nst['bad']} badline and "
          f"{v(r, 'firstaec_spr_4')}/{nst['spr']} sprite stalls; screen-matrix phi2 samples with AEC {v(r, 'cacc_bad')} "
          f"(= 40 x {nst['bad']} badlines), without AEC {v(r, 'earlyc_bad')}; sprite-data phi2 samples with AEC "
          f"{v(r, 'sacc_spr') + v(r, 'sacc_bad')}, without {v(r, 'earlys_spr') + v(r, 'earlys_bad')}; baCnt replica vs addrValid "
          f"mismatches {v(r, 'rep_viol')}")
check("C2 negative control (grace 4) is caught", v('neg', 'c2a_viol') > 0,
      f"DMA-served CPU halves with AEC: {v('neg', 'c2a_viol')} (badline {v('neg', 'c2a_bad')}, sprite {v('neg', 'c2a_spr')})")


def c3(r, g_expect):
    ok = v(r, 'norm_viol') == 0
    parts = [f"normal served reads {v(r, 'norm_n')}: data valid from tick <= {v(r, 'norm_max')}"]
    for c in CLS:
        rd = v(r, f'rdstalls_{c}')
        for g in (1, 2, 3, 4):
            n = v(r, f'fv_n_{c}_{g}')
            exp_n = rd if g <= g_expect else 0
            ok &= n == exp_n and (n == 0 or v(r, f'fv_max_{c}_{g}') <= 20)
        ok &= v(r, f'gviol_{c}') == 0 and v(r, f'pgviol_{c}') == 0
        ok &= v(r, f'postgrace_{c}_{g_expect + 1}') >= tot(r, c, 'ver')
        fv = "/".join(f"{v(r, f'fv_min_{c}_{g}')}..{v(r, f'fv_max_{c}_{g}')}" if v(r, f'fv_n_{c}_{g}') else "-" for g in (1, 2, 3))
        parts.append(f"{c}: {rd} verify stalls, grace cycles 1/2/3 served with read data in {v(r, f'fv_n_{c}_1')}/"
                     f"{v(r, f'fv_n_{c}_2')}/{v(r, f'fv_n_{c}_3')}, valid from tick {fv}, late {v(r, f'gviol_{c}')}; "
                     f"first unserved BA-low cycle {g_expect + 1} in {v(r, f'postgrace_{c}_{g_expect + 1}')} stalls, data released "
                     f"from tick {v(r, f'postgrace_off_max_{c}')}, driven in its CPU half {v(r, f'pgviol_{c}')}")
    return ok, "; ".join(parts)


print("C3  data path in every served grace cycle (ticks counted from CYCLE_EXT0, PHI2 high in 17..30)")
for r, g in (('fix', 3), ('fixff', 3), ('a24', 1), ('a24ff', 1), ('x1', 3)):
    ok, msg = c3(r, g)
    check(f"C3 {r}", ok, msg)

print("C4  REC verify comparator and transfer completion")
for r in DMA_RUNS:
    a24 = r.startswith('a24')
    ff = r.endswith('ff')
    xf = re.findall(r'XFER (\d+) (verify|fetch|swap) +c64=\$(\w+) len=(\d+) counted=(\d+) cycles=(\d+) stalls=(\d+) held_reads=(\d+) mismatches=(\d+)', LOG[r])
    ok = v(r, 'xfers_done') == v(r, 'xfers') and all(x[3] == x[4] for x in xf) and v(r, 'unserved') == 0 and v(r, 'mis_out') == 0
    totmis = sum(v(r, f'mis_{c}_{i}') for c in CLS for i in range(4))
    for c in CLS:
        ok &= v(r, f'grace_{c}_ver_{1 if a24 else 3}') == tot(r, c, 'ver') and v(r, f'grace_{c}_fet_1') == tot(r, c, 'fet')
        if a24 and not ff:
            exp = v(r, f'rdstalls_{c}') - v(r, f'rdstalls_ff_{c}')
            ok &= (v(r, f'mis_{c}_0') == 0 and v(r, f'mis_{c}_1') == 0 and v(r, f'misnonff_{c}') == 0 and
                   v(r, f'rdstalls_mis23_{c}') == exp and v(r, f'mis_{c}_2') == exp and v(r, f'mis_{c}_3') == exp)
    if not a24 or ff:
        ok &= totmis == 0
    det = "; ".join(f"{c}: verify stalls {tot(r, c, 'ver')} (held byte $FF in {v(r, f'rdstalls_ff_{c}')}), fetch stalls "
                    f"{tot(r, c, 'fet')}, mismatches counted/held1/held2/held3 " +
                    "/".join(str(v(r, f'mis_{c}_{i}')) for i in range(4)) + f" (not $FF: {v(r, f'misnonff_{c}')})"
                    for c in CLS)
    xs = ", ".join(f"#{x[0]} {x[1]} ${x[2]}+{x[3]}: {x[5]} cycles, {x[6]} stalls, {x[8]} faults" for x in xf)
    check(f"C4 {r}", ok, f"{len(xf)} transfers complete ({xs}); {det}")

print("C5  fetch: no byte lost, nothing written elsewhere (whole 64 KB compared)")
for r in DMA_RUNS:
    check(f"C5 {r}", v(r, 'ram_diffs') == 0 and v(r, 'lost_writes') == 0 and tot(r, 'bad', 'fet') > 0 and tot(r, 'spr', 'fet') > 0,
          f"RAM differences {v(r, 'ram_diffs')}, counted REC writes not written by the FPGA {v(r, 'lost_writes')}; fetch stalls covered: badline {tot(r, 'bad', 'fet')}, sprite {tot(r, 'spr', 'fet')}; "
          f"DMA RAM write ticks {v(r, 'ram_we_ticks_dma')}, all in tick " +
          ",".join(k.split('_')[-1] for k in S[r] if k.startswith('ram_we_tick_')))

print("C6  sprite stalls (BA low 3 cycles before the sprite's fetches)")
for r in DMA_RUNS:
    a24 = r.startswith('a24')
    check(f"C6 {r}", v(r, 'rdstalls_spr') > 0 and v(r, 'c2a_spr') == 0 and v(r, 'firstaec_spr_4') == stalls(r, 'spr') and
          v(r, 'gviol_spr') == 0 and v(r, 'pgviol_spr') == 0,
          f"verify-covered sprite stalls {v(r, 'rdstalls_spr')}, DMA-served CPU halves with AEC {v(r, 'c2a_spr')}, "
          f"grace cycles served {1 if a24 else 3} in {v(r, 'grace_spr_ver_' + ('1' if a24 else '3'))}, "
          f"first AEC cycle 4 in {v(r, 'firstaec_spr_4')}/{stalls(r, 'spr')}, sprite-data phi2 samples with AEC {v(r, 'sacc_spr')}")

print("C7  swap: the REU side stores what the REC latched last, the C64 side is covered by C5")
for r in DMA_RUNS:
    sw = re.findall(rf'SWAP {r} (\d+) case1=(\d+) case2=(\d+) reu_bad=(\d+) reu_ff=(\d+)', LOG[r])
    c1, c2, bad, ffn = (sum(int(x[i]) for x in sw) for i in (1, 2, 3, 4))
    g = {n: sum(v(r, f'grace_{c}_swa_{n}') for c in CLS) for n in range(6)}
    nsw = sum(tot(r, c, 'swa') for c in CLS)
    full = r in ('fix', 'fixff')                      # the read of the first BA-low cycle is served through the AEC window
    served = 3 if full else 1
    ok = len(sw) > 0 and c1 > 0 and c2 > 0 and c1 + c2 == nsw and g[served] == c1 and g[0] == c2
    ok &= all(tot(r, c, 'swa') > 0 for c in CLS)
    if full:
        ok &= bad == 0
        ok &= all(v(r, f'sfv_n_{c}_{i}') == sum(v(r, f'grace_{c}_swa_{n}') for n in (3,)) and v(r, f'sfv_max_{c}_{i}') <= 20
                  for c in CLS for i in (1, 2, 3))
    else:
        ok &= bad == c1 and ffn == c1                 # one byte per stall after the swap's write, always $FF
    check(f"C7 {r}", ok,
          f"{len(sw)} swap(s), stalls {nsw} (badline {tot(r, 'bad', 'swa')}, sprite {tot(r, 'spr', 'swa')}): BA fell after the write "
          f"(read in the first BA-low cycle) {c1}, after the read {c2}; grace cycles served 0/1/3 in {g[0]}/{g[1]}/{g[3]} stalls; "
          f"REU bytes stored wrong {bad}, of them $FF {ffn}" +
          (f"; read data valid from tick <= {max(v(r, f'sfv_max_{c}_{i}') for c in CLS for i in (1, 2, 3))} in all three" if full else ""))

print("Coverage (all DMA runs need badline and sprite stalls under verify and fetch)")
for r in DMA_RUNS:
    check(f"coverage {r}", all(v(r, f'rdstalls_{c}') > 0 and tot(r, c, 'fet') > 0 for c in CLS),
          f"verify: badline {v(r, 'rdstalls_bad')}, sprite {v(r, 'rdstalls_spr')}; fetch: badline {tot(r, 'bad', 'fet')}, "
          f"sprite {tot(r, 'spr', 'fet')}")

print("Information (not part of the verdict)")
for r in DMA_RUNS + ['late', 'neg']:
    fr = {k: n for k, n in S[r].items() if k.startswith('fightrw_')}
    names = {'0': 'stall', '1': 'recharge', '2': 'grace'}
    desc = ", ".join(f"{names[k.split('_')[1]]} branch, BA-low cycle {k.split('_')[2]}, tick {k.split('_')[3]}: {n}" for k, n in sorted(fr.items(), key=lambda x: -x[1]))
    print(f"  {r}: R/W driven both ways (FPGA high, REC low) in {v(r, 'fight_rw')} ticks [{desc}]; "
          f"address fights {v(r, 'fight_a')}, data fights {v(r, 'fight_d')}; same-level parallel drive R/W {v(r, 'par_rw')} ticks")
L = S['late']
print(f"  late: RAM differences {L.get('ram_diffs')}, mismatches " +
      "/".join(str(sum(L.get(f'mis_{c}_{i}', 0) for c in CLS)) for i in range(4)) +
      f", unserved counted accesses {L.get('unserved')}, lost writes {L.get('lost_writes')}, data fights {L.get('fight_d')}")
N = S['neg']
print(f"  neg: RAM differences {N.get('ram_diffs')}, grace cycles served per verify stall 4 in "
      f"{N.get('grace_bad_ver_4', 0) + N.get('grace_spr_ver_4', 0)} stalls")

if fails:
    print("RESULT: FAIL " + ", ".join(fails))
    sys.exit(1)
print("RESULT: PASS")
