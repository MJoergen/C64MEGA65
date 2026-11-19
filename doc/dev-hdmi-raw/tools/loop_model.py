#!/usr/bin/env python3
# Frame-level model of the genlock control law of SPEC 5.3 (not cycle exact): checks convergence from every start phase.
from fractions import Fraction as F
import random
MODES = {
  # name: (core frame in pixel clocks (exact), totals H*V, CLK_KHZ)
  'PAL 720p':  (F(100_000_000*67, 90) * F(628992*180, 5675*1_000_000), 1980*750, 74444),
  'PAL 576p':  (F(539136), 864*624, 27023),
  'NTSC 720p': (F(100_000_000*237, 320) * F(547040*110, 36*100_000_000), 1650*750, 74062),
  'NTSC 480p': (F(451308), 858*526, 27000),
}
KMAX, GUARD = 4080, 4096
def run(name, d0, frames, jitter=True, seed=1):
    N, HV, khz = MODES[name]
    T = 2 * khz
    rnd = random.Random(seed)
    d = F(d0)            # true distance in pixel clocks (0 <= d < N)
    lock_at = None; inrow = 0; ks = []; dmin = dmax = None
    for f in range(frames):
        dm = int(d) + (rnd.choice((0, 1)) if jitter else 0)     # measured: quantized, one clock of synchronizer uncertainty
        if dm <= T:               k = min(T - dm, KMAX)
        elif dm < T + GUARD:      k = 0
        else:                     k = KMAX
        ok = (T - 1024 <= dm < T + 4096)
        inrow = inrow + 1 if ok else 0
        if inrow == 8 and lock_at is None: lock_at = f
        if lock_at is not None:
            ks.append(k); dmin = d if dmin is None else min(dmin, d); dmax = d if dmax is None else max(dmax, d)
            if not ok: return ('LOST LOCK', f)
        d = (d + HV + k - N) % N
    return (lock_at, min(ks) if ks else None, max(ks) if ks else None, float(dmin - T) if ks else None, float(dmax - T) if ks else None, float(sum(ks))/len(ks) if ks else None)
for name, (N, HV, khz) in MODES.items():
    worst = 0; res = []
    for i in range(64):
        d0 = int(N * i / 64)
        r = run(name, d0, 1200)
        if r[0] in (None, 'LOST LOCK'): print(name, 'start', d0, 'FAIL', r); break
        worst = max(worst, r[0]); res.append(r)
    else:
        kmin = min(r[1] for r in res); kmax = max(r[2] for r in res)
        dlo = min(r[3] for r in res); dhi = max(r[4] for r in res)
        print(f"{name:10s} surplus {float(N-HV):8.3f}  worst lock after {worst:4d} frames ({worst/ (74444000/float(N) if False else 1):.0f})  "
              f"k in lock {kmin}..{kmax}  d-T in lock {dlo:8.1f}..{dhi:8.1f} px  mean k {res[0][5]:.3f}")
