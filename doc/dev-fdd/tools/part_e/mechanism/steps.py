#!/usr/bin/env python3
"""Extract step sequences and the ID read that follows them from decoded dumps.

Usage: python3 -I steps.py decoded1.txt [decoded2.txt ...]
Prints one line per step run: dump, index in ring, steps (dir/count), est range,
trk0 flags, the following REQ (op, trk) and RES (C/H/R), offset = est - foundC.
"""
import re
import sys

HDR = re.compile(r"^=+ comment (\d+) / (.*?) =+$")
STEP = re.compile(r"^\s+STEP dir=(out\(->trk0\)|in) head_est=(\d+) trk0_after=(\d)")
REQ = re.compile(r"^\s+REQ\s+(\S+(?: \S+)?)\s+side=(\d) trk=(\d+) sec=(\d+)")
RES = re.compile(r"^\s+RES\s+C=\s*(\d+) H=(\d) R=\s*(\d+) rnf=(\d) crc=(\d) del=(\d) -> (\S+)")


def parse(paths):
    dumps = []
    cur = None
    for p in paths:
        for line in open(p, encoding="utf-8", errors="replace"):
            line = line.rstrip("\n")
            m = HDR.match(line)
            if m:
                cur = {"c": int(m.group(1)), "name": m.group(2), "hdr": [], "ring": []}
                dumps.append(cur)
                continue
            if cur is None:
                continue
            m = STEP.match(line)
            if m:
                cur["ring"].append(("STEP", "out" if m.group(1).startswith("out") else "in",
                                    int(m.group(2)), int(m.group(3))))
                continue
            m = REQ.match(line)
            if m:
                cur["ring"].append(("REQ", m.group(1).strip(), int(m.group(2)), int(m.group(3)), int(m.group(4))))
                continue
            m = RES.match(line)
            if m:
                cur["ring"].append(("RES", int(m.group(1)), int(m.group(2)), int(m.group(3)),
                                    int(m.group(4)), int(m.group(5)), m.group(7)))
                continue
            if line.strip().startswith(("STEP", "REQ", "RES")):
                cur["ring"].append(("UNPARSED", line.strip()))
                continue
            if not line.startswith("    "):
                cur["hdr"].append(line)
    return dumps


def runs(ring):
    """Yield (start, end) index pairs of maximal STEP runs."""
    i = 0
    n = len(ring)
    while i < n:
        if ring[i][0] == "STEP":
            j = i
            while j + 1 < n and ring[j + 1][0] == "STEP":
                j += 1
            yield i, j
            i = j + 1
        else:
            i += 1


def desc_run(ring, i, j):
    parts = []
    k = i
    while k <= j:
        d = ring[k][1]
        m = k
        while m + 1 <= j and ring[m + 1][1] == d:
            m += 1
        ests = [ring[x][2] for x in range(k, m + 1)]
        t0 = [ring[x][3] for x in range(k, m + 1)]
        t0s = "".join(str(x) for x in t0)
        parts.append(f"{d}x{m-k+1}[{ests[0]}..{ests[-1]} t0={t0s}]")
        k = m + 1
    return " ".join(parts)


def main():
    dumps = parse(sys.argv[1:])
    for d in dumps:
        ring = d["ring"]
        head = next((h for h in d["hdr"] if h.startswith("HEAD")), "")
        trc = next((h for h in d["hdr"] if "TRC_CNT" in h), "")
        m = re.search(r"TRC_CNT=(\d+)", trc)
        print(f"## c{d['c']} {d['name']} | {head} | TRC_CNT={m.group(1) if m else '?'} | ring={len(ring)}")
        for i, j in runs(ring):
            # preceding op
            prev = ring[i - 1] if i > 0 else None
            prevreq = None
            for x in range(i - 1, -1, -1):
                if ring[x][0] == "REQ":
                    prevreq = ring[x]
                    break
            nxt = ring[j + 1] if j + 1 < len(ring) else None
            nres = ring[j + 2] if j + 2 < len(ring) else None
            last_est = ring[j][2]
            s = f"  ring[{i}..{j}] {desc_run(ring, i, j)}"
            if prevreq:
                s += f" | prevREQ {prevreq[1]} trk={prevreq[3]}"
            if prev and prev[0] == "RES":
                s += f" C={prev[1]}"
            if nxt and nxt[0] == "REQ":
                s += f" || next {nxt[1]} side={nxt[2]} trk={nxt[3]} sec={nxt[4]}"
                if nres and nres[0] == "RES":
                    s += f" -> C={nres[1]} H={nres[2]} R={nres[3]} {nres[6]}  est-C={last_est - nres[1]:+d}"
            elif nxt is None:
                s += " || (end of ring)"
            print(s)


if __name__ == "__main__":
    main()
