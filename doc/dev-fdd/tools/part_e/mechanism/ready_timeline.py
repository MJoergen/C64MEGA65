#!/usr/bin/env python3
"""Timeline model: does the A25 READY rule (READY with the first index edge after motor-on,
falls 500 ms after the last index edge) hold through the 1581 boot recalibration, if the
mechanism hides INDEX while it steps (TEAC FD-235HF 8.3.9: INDEX = index * select * ready *
seek-complete, seek-complete = 15.8..17.9 ms after the trailing edge of the last STEP)?

DOS command latencies are those of the genuine-ROM emulator boot (tools/boot_timing.py);
step timing is the controller's (24 us setup + 4 us pulse + 3 ms recovery, 4 ms after a
reversing pulse). Assumptions are marked A1..A6 in the code. Usage:
  python3 -I ready_timeline.py [step_ms] [mask_ms] [restore_pulses]
"""
import sys

T = 0.1993          # revolution (s), measured IDX_PERIOD of the R6 drive
STEP = float(sys.argv[1]) / 1000 if len(sys.argv) > 1 else 0.00303   # step interval
MASK = float(sys.argv[2]) / 1000 if len(sys.argv) > 2 else 0.017     # A1: index hidden until last step + MASK
NREST = int(sys.argv[3]) if len(sys.argv) > 3 else 41                # A2: Restore pulses (C=39 + 2 lag)
RA_T = 0.010        # A3: a Read Address takes 10 ms (next ID, 10 IDs per revolution)
DOS_AFTER_T1 = 0.0234   # emulator: RA command 23.4 ms after a Type-I busy end
STALE = 0.500       # A25 rule: 2 * G_PERIOD_MAX_CYC


def schedule(lag):
    """Return (list of step trailing-edge times, list of (time, label) READY exams)."""
    steps, exams = [], []
    t = 0.800                               # A4: readiness stage: step pair at 0.800 s after motor-on
    # Step In, Step Out (Step Out written 11 us after busy end)
    for _ in range(2):
        steps.append(t + 28e-6)
        t = t + 28e-6 + 0.003 + 11e-6
    exams.append((0.826, "PA1 exam 0.826 s"))   # README: 0.8263 s after a disk change
    t = 0.827                               # Restore command
    for k in range(NREST):
        steps.append(t + 28e-6)
        t = t + 28e-6 + STEP - 28e-6 + 28e-6
    t += DOS_AFTER_T1                       # RA #1..#3 on track 0
    for k in range(3):
        exams.append((t, f"RA trk0 #{k+1} ($CD08)"))
        t += RA_T + 0.002
    t += 0.0034                             # Seek 39
    for k in range(39):
        steps.append(t + 28e-6)
        t += STEP + (0.001 if k == 0 else 0.0)   # 4 ms recovery after the reversing pulse
    t += DOS_AFTER_T1
    exams.append((t, "RA trk39 ($CD08)"))
    t += RA_T
    if lag:                                 # RA found C=37: 2 more steps, RA again
        t += 0.002
        for k in range(2):
            steps.append(t + 28e-6)
            t += STEP
        t += DOS_AFTER_T1
        exams.append((t, "RA after correction ($CD08)"))
    return steps, exams


def masked(tp, steps):
    for s in steps:
        if s - 0.0005 <= tp <= s + MASK:    # A5: hidden from (just before) a step until MASK after it
            return True
    return False


def run(ts, lag, mask_on=True):
    steps, exams = schedule(lag)
    edges = []
    k = 0
    while True:
        tp = ts + k * T
        if tp > 2.0:
            break
        if not (mask_on and masked(tp, steps)):
            edges.append(tp)
        k += 1
    res = []
    for (te, lab) in exams:
        past = [e for e in edges if e <= te]
        ready = bool(past) and (te - past[-1]) < STALE      # A6: READY rises with the first edge
        res.append((lab, te, ready, (te - past[-1]) if past else None))
    return res


def main():
    print(f"step={STEP*1e3:.2f} ms mask={MASK*1e3:.1f} ms restore_pulses={NREST}")
    for lag in (False, True):
        for mask_on in (False, True):
            fails = []
            for i in range(0, 301):
                ts = 0.45 + i * 0.001
                r = run(ts, lag, mask_on)
                bad = [x for x in r if not x[2]]
                if bad:
                    fails.append((ts, bad[0][0]))
            # compress into intervals per failing exam
            ivs = []
            for ts, lab in fails:
                if ivs and ivs[-1][2] == lab and abs(ts - ivs[-1][1] - 0.001) < 1e-9:
                    ivs[-1][1] = ts
                else:
                    ivs.append([ts, ts, lab])
            desc = "; ".join(f"t_s {a:.3f}-{b:.3f} s fails at '{l}'" for a, b, l in ivs) or "never fails"
            print(f"lag={'yes' if lag else 'no ':<3} index_mask={'yes' if mask_on else 'no ':<3}: {desc}")


if __name__ == "__main__":
    main()
