# Sweep: MFCWT's "UI" (DOS warm reset) on the 1581 ROM (stock, or c1581.rom of the current directory),
# motor stopped before, against mechanism parameters.
# usage: exp5_sweep.py <hold_ms> <lose_steps> <head> <tfirst_from> <tfirst_to> <step> [suppress 0/1] [motor_running 0/1]
import sys, os, copy
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from h257 import *
from exp3 import idle_until_motor_off

hold = float(sys.argv[1]); lose = int(sys.argv[2]); head = int(sys.argv[3])
t_a, t_b, t_s = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
supp = int(sys.argv[7]) if len(sys.argv) > 7 else 1
running = int(sys.argv[8]) if len(sys.argv) > 8 else 0

base = boot()
base.watch_pc = {0xCDA8: 'E3-readiness', 0xCD39: 'E3-CD08', 0xAFE6: 'UI-done', 0xA7AE: 'ERROR', 0xCB0F: 'RESTORE', 0xCE78: 'SEEKSTAGE'}
idle_until_motor_off(base)
base.head = head; base.wd_track = head; base.ram[0x27] = head

def classify(m, t_motor):
    ev = []
    after = False
    for c, k, x in m.log:
        if k == 'WD' and 'RESTORE' in x: after = True; ev.append('R'); continue
        if not after: continue
        if k == 'WD' and 'SEEK ' in x:
            n = int(x.split(', ')[1].split()[0]); ev.append('S%d' % n)
        elif k == 'WD' and 'STEP' in x: ev.append('s')
        elif k == 'WD' and 'RA done' in x: ev.append('C%s' % x.split('C=')[1].split()[0])
        elif k == 'WD' and 'RDSEC' in x: ev.append('rd')
        elif k == 'PC' and x.startswith('E3'): ev.append('[74 %s @%.0fms]' % (x[3:], (c - t_motor) / MS))
        elif k == 'EXAM' and x[5]: pass
    # compress reads
    out = []
    for e in ev:
        if e == 'rd' and out and out[-1].startswith('rd'):
            out[-1] = 'rd%d' % (int(out[-1][2:] or 1) + 1)
        elif e == 'rd': out.append('rd1')
        else: out.append(e)
    return ' '.join(out)

print('# hold=%.0fms lose=%d head=%d suppress=%d motor_running=%d ROM=%s' % (hold, lose, head, supp, running, ('stock' if machmod.ROM[0xC160 - 0x8000] == 0x4C else 'c1581.rom of the current directory')))
for tf in range(t_a, t_b + 1, t_s):
    m = copy.deepcopy(base)
    m.t_first = int(tf * MS); m.suppress_steps = bool(supp); m.suppress_hold = int(hold * MS)
    m.lose_in_steps = lose; m.lose_min = 10
    m.logging = True; m.log.clear()
    if running:
        # case (b): the motor is running when UI comes (a job on track 20 just before)
        post_job(m, 0x80, 41, 0, bufpage=3, slot=0)
        run_until_idle(m, 20_000_000, 'pre-job')
        m.run(int(running) * 1000)
        m.log.clear()
    inject(m, 'UI', sa=15)
    t0 = m.cyc
    while m.cyc - t0 < 3.0 * CPS:
        m.run(5000)
        if any(k == 'PC' and x in ('UI-done', 'ERROR') for c, k, x in m.log[-50:]): break
    m.run(20000)
    ons = [c for c, k, x in m.log if k == 'MOTOR' and x == 'ON']
    tmot = ons[-1] if ons else (m.motor_on_at if m.motor_on_at is not None else t0)
    exams = [(x[2] / MS, x[5]) for c, k, x in m.log if k == 'EXAM']
    res = 'ERR74' if any(k == 'PC' and x == 'ERROR' for c, k, x in m.log) else 'OK'
    uiend = [c for c, k, x in m.log if k == 'PC' and x == 'UI-done']
    win = ''
    if uiend:
        u = uiend[-1]; e = m.last_edge(u)
        nxt = None
        for k2 in range(40):
            cand = tmot + m.t_first + k2 * m.rev_cyc
            if cand > u and not m.suppressed(cand): nxt = cand; break
        rdy_at_end = m.ready()
        win = 'UIend %.0f, READY at end %d, next edge +%.0f ms' % ((u - tmot) / MS, int(rdy_at_end), ((nxt - u) / MS) if nxt else -1)
    print('t_first %4d ms: %s | %s | exams(age ms,fails): %s' % (tf, win, classify(m, tmot),
          ' '.join('%.0f%s' % (a, '!' if f else '') for a, f in exams)), flush=True)
