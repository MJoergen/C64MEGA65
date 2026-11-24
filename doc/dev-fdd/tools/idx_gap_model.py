#!/usr/bin/env python3
"""idx_gap_model.py [revolution in ms] : what IDX_GAP_MAX_MS (0xA2, map v10 of the diagnostic device of the
Internal 1581) reads after a recalibration or a long seek on a mechanism that withholds its index pulses
while the head steps.

The model:
  * the disk turns at a constant speed, one index pulse per revolution (default 199.35 ms, the
    IDX_PERIOD of the tester's R6 mechanism, 9,967,370 cycles of 50 MHz);
  * the mechanism delivers no index pulse from the first step pulse of a step train until the hold time
    after its last step pulse ("pulse"), or until the hold time after the end of the command's BUSY,
    one pace after the last step pulse ("busy", the model of doc/dev-fdd/tools/part_e/mfcwt_74);
  * a recalibration from cylinder c is the one of the 1581 ROM (UI, UJ, the power-on initialization,
    the bump after two failed reads): a Restore of c steps, then a Seek of 39 steps back to the
    directory cylinder, whose first step pulse comes 72.2 ms after the end of the Restore's BUSY at
    6 ms per step and 75.2 ms at 3.03 ms per step (the timelines of the genuine ROM in
    doc/dev-fdd/ISSUE257-PART-E-FIXES.md, sections 7 and 8.2); BUSY lasts one pace per step;
  * the device reports the longest time between two delivered index pulses in whole milliseconds; the
    motor stays on throughout, and there is a delivered pulse before the first train.
Every index phase is tried in steps of 0.1 ms. For each sequence the script prints the readings that
occur, in revolutions and in milliseconds, with the share of the index phases that give them.
"""
import collections, sys

REV = float(sys.argv[1]) if len(sys.argv) > 1 else 199.35
GAP_AFTER_RESTORE = {6.0: 72.2, 3.03: 75.2}

def trains_recal(c, pace):
    t = [(0.0, c)] if c else []
    seek0 = c * pace + GAP_AFTER_RESTORE[pace]
    return t + [(seek0, 39)]

def hidden(trains, pace, hold, tail):
    w = []
    for t0, n in trains:
        last = t0 + (n - 1) * pace
        w.append((t0, last + (pace if tail == "busy" else 0.0) + hold))
    return w

def readings(trains, pace, hold, tail):
    win = hidden(trains, pace, hold, tail)
    res = collections.Counter()
    steps = int(round(REV * 10))
    for i in range(steps):
        ph = -REV + i * 0.1
        pulses = [ph + k * REV for k in range(0, 14)]
        vis = [p for p in pulses if not any(a <= p <= b for a, b in win)]
        g = max(b - a for a, b in zip(vis, vis[1:]))
        res[round(g / REV)] += 1
    return {k: (int(k * REV), 100.0 * v / steps) for k, v in sorted(res.items())}

def show(label, trains, pace, hold, tail):
    r = readings(trains, pace, hold, tail)
    print("  %-44s %s" % (label, ", ".join("%d rev = %d ms (%.0f %%)" % (k, ms, p) for k, (ms, p) in r.items())))

print("revolution %.2f ms" % REV)
for pace in (6.0, 3.03):
    for tail in ("pulse", "busy"):
        for hold in (0.0, 18.0):
            print("pace %.2f ms, index withheld until %g ms after the last %s:" % (
                pace, hold, "step pulse" if tail == "pulse" else "BUSY"))
            for c in (0, 39, 79):
                show("recalibration from cylinder %d" % c, trains_recal(c, pace), pace, hold, tail)
            for n in (50, 79):
                show("seek over %d cylinders" % n, [(0.0, n)], pace, hold, tail)
# the whole range of the head position at a recalibration, at the pace of the 1581 ROM
for tail in ("pulse", "busy"):
    for hold in (0.0, 18.0):
        ks = collections.Counter()
        for c in range(0, 80):
            for k in readings(trains_recal(c, 6.0), 6.0, hold, tail):
                ks[k] += 1
        print("6 ms, hold %g ms after the last %s, recalibration from any cylinder 0 to 79: %s" % (
            hold, "step pulse" if tail == "pulse" else "BUSY",
            ", ".join("%d rev (from %d cylinders)" % (k, v) for k, v in sorted(ks.items()))))
