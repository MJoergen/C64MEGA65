#!/usr/bin/env python3
"""Per dump: the offset d = (controller head estimate) - (cylinder C of the ID found), for every
OK result in the trace ring, with the estimate reconstructed from the STEP entries and HEAD.

Usage: python3 -I offsets.py decoded1.txt [...]
Uses the parser of steps.py (same folder).
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from steps import parse  # noqa: E402


def est_track(d):
    ring = d["ring"]
    head = next((h for h in d["hdr"] if h.startswith("HEAD")), "")
    m = re.search(r"cyl=(\d+) valid=(\d)", head)
    hcyl, hvalid = int(m.group(1)), int(m.group(2))
    steps = [i for i, e in enumerate(ring) if e[0] == "STEP"]
    est = [None] * len(ring)
    if not steps:
        est = [hcyl] * len(ring)
        return est, hcyl, hvalid
    f = steps[0]
    e0 = ring[f]
    if e0[1] == "in":
        before = e0[2] - 1
    elif e0[2] > 0:
        before = e0[2] + 1
    else:
        before = None
    cur = before
    for i, e in enumerate(ring):
        if e[0] == "STEP":
            cur = e[2]
        est[i] = cur
    return est, hcyl, hvalid


def main():
    dumps = parse(sys.argv[1:])
    for d in dumps:
        ring = d["ring"]
        est, hcyl, hvalid = est_track(d)
        trc = next((h for h in d["hdr"] if "TRC_CNT" in h), "")
        m = re.search(r"TRC_CNT=(\d+)", trc)
        cnt = next((h for h in d["hdr"] if h.startswith("CNT:")), "")
        ms = re.search(r"idx_raw=(\d+) idx_qual=(\d+) step=(\d+) READOP=(\d+)", cnt)
        offs = []
        for i, e in enumerate(ring):
            if e[0] == "RES" and e[6] == "OK" and est[i] is not None:
                req = ring[i - 1] if i > 0 and ring[i - 1][0] == "REQ" else None
                if req and req[1] in ("WRITE TRACK", "Verify"):
                    pass
                offs.append((i, est[i] - e[1], e[1], req[1] if req else "?", req[3] if req else -1))
        dset = sorted(set(o[1] for o in offs))
        trk = sorted(set((o[4], o[2]) for o in offs))
        print(f"c{d['c']:>2} {d['name']:<14} TRC={m.group(1) if m else '?':>6} "
              f"idx={ms.group(1) if ms else '?'} steps={ms.group(3) if ms else '?'} reads={ms.group(4) if ms else '?'} "
              f"HEAD={hcyl} v={hvalid} d={dset} (WDtrk,C)={trk[:6]}")


if __name__ == "__main__":
    main()
