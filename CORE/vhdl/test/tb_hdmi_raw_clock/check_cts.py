#!/usr/bin/env python3
"""Checker of tb_hdmi_raw_cts (issue #184, doc/dev-hdmi-raw/SPEC.md section 6).

    check_cts.py VCD REPO
    check_cts.py --packet VCD REPO

The CTS of a packet is the value of audio_pcm_cts at the rising edge of the packet
strobe audio_pcm_acr. Expected values come from the mode records of
video_modes_pkg.vhd and VIDEO_MODE_VECTOR of framework.vhd (parsed with
doc/dev-ntsc/tools/w2_checks.py); the copy of the vector in tb_hdmi_raw_cts.vhd must
be the same.

Checks:
  * a mode whose CTS_FRAC_N is 0 (every mode that is not a raw mode, and raw 480p):
    every packet carries CLK_KHZ, also the first one after a change from a raw mode
  * a raw mode with CTS_FRAC_N / CTS_FRAC_D: after the first two packets of the step
    (the accumulator may still hold the value of the previous mode) every window of
    CTS_FRAC_D consecutive packets has exactly CTS_FRAC_N packets with CLK_KHZ + 1
    and the others with CLK_KHZ, so the average over a whole number of windows is
    exactly CLK_KHZ + CTS_FRAC_N / CTS_FRAC_D kHz; that is the pixel clock of the
    table that the record selects (exact fraction printed)
  * CTS never changes less than 0.4 ms before or after a strobe

--packet (tb_hdmi_raw_cts with G_PACKET, the HDMI clock running): the CTS of an
ACR packet is the value of pcm_cts_s of vga_to_hdmi when the packet is sent
(rising edge of data_ack(1): its bytes are copied from pb(1), which holds
pcm_cts_s of the clock cycle before); a packet counts for the mode of its request,
and one that is requested before a change of the mode and sent after it is
reported and not counted. Checks: every ACR request (vga_acr) is
sent as one packet within 100 us; pcm_cts_s does not change in the 0.4 ms before
a packet; in raw 576p (17 / 21) at least 42 packets after the first two, every
window of 21 of them has exactly 17 packets with 27024 and 4 with 27023 (average
567500/21 kHz); in 576p every packet carries 27000.

Prints "RESULT: PASS" or "RESULT: FAIL ...".
"""

import importlib.util
import os
import re
import sys
from fractions import Fraction

FAILS = []


def check(cond, what):
    if not cond:
        FAILS.append(what)
        print("  MISMATCH: " + what)


def load_w2(repo):
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("w2_checks", os.path.join(repo, "doc", "dev-ntsc", "tools", "w2_checks.py"))
    w2 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w2)
    return w2


def packet_main(vcd, repo):
    w2 = load_w2(repo)
    pkg = w2.read(repo, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd")
    recs = w2.parse_records(pkg)
    members = w2.parse_members(pkg)
    _, vector, _, _ = w2.parse_framework(w2.read(repo, "M2M/vhdl/framework.vhd"))
    ch = w2.parse_vcd(vcd)
    state = {}
    acr, sent, cts_ch = [], [], []
    for t, name, v in ch:
        prev = state.get(name)
        state[name] = v
        if name == "vga_acr" and v == "1" and prev == "0":
            acr.append((t, int(state["tb_phase"], 2)))
        elif name == "data_ack" and prev is not None and len(v) == 4 and v[1] == "1" and prev[1] == "0":
            # the packet belongs to the mode of its request; one whose request comes before a
            # change of the mode and which is sent after it carries the CTS of the new mode
            # (phase -1: not counted in either mode)
            ph = acr[len(sent)][1] if len(sent) < len(acr) else int(state["tb_phase"], 2)
            if ph != int(state["tb_phase"], 2):
                ph = -1
            sent.append((t, ph, int(state["pcm_cts_s"], 2)))
        elif name == "pcm_cts_s" and prev is not None and prev != v:
            cts_ch.append(t)
    print("%d ACR requests, %d ACR packets sent, %d changes of pcm_cts_s" % (len(acr), len(sent), len(cts_ch)))
    check(len(acr) == len(sent) and len(sent) >= 60, "requests and packets do not match")
    for i, (ts, _, _) in enumerate(sent):
        if i < len(acr):
            check(0 <= ts - acr[i][0] <= 100 * 10 ** 9, "packet %d sent %s fs after its request" % (i, ts - acr[i][0]))
        near = [t for t in cts_ch if ts - 400 * 10 ** 9 <= t <= ts]
        # the first packets after the end of the HDMI reset and the mode change are exempt
        if i >= 2 and sent[i - 2][1] == sent[i][1]:
            check(not near, "pcm_cts_s changes %s fs before packet %d" % (ts - near[-1] if near else 0, i))
    boundary = [(ts, cts) for ts, ph, cts in sent if ph == -1]
    print("%d packet(s) requested before a change of the mode and sent after it: CTS %s" % (
        len(boundary), [c for _, c in boundary]))
    steps = []
    for ts, ph, cts in sent:
        if ph == -1:
            continue
        if not steps or steps[-1][0] != ph:
            steps.append((ph, []))
        steps[-1][1].append(cts)
    for ph, ctss in steps:
        rec = recs[vector[ph]]
        k, n, d = rec["CLK_KHZ"], rec["CTS_FRAC_N"], rec["CTS_FRAC_D"]
        if n == 0:
            check(all(c == k for c in ctss), "%s: packets carry %s" % (members[ph], sorted(set(ctss))))
            print("%-26s %3d packets, every one with CTS %d" % (members[ph], len(ctss), k))
            continue
        body = ctss[2:]
        check(len(body) >= 42, "%s: only %d packets" % (members[ph], len(body)))
        check(all(c in (k, k + 1) for c in body), "%s: CTS values %s" % (members[ph], sorted(set(body))))
        inc = [c - k for c in body]
        bad = [i for i in range(len(inc) - d + 1) if sum(inc[i:i + d]) != n]
        check(not bad, "%s: windows of %d packets with other than %d increments at %s" % (members[ph], d, n, bad[:3]))
        whole = (len(body) // d) * d
        avg = Fraction(sum(body[:whole]), whole)
        check(avg == k + Fraction(n, d), "%s: average %s" % (members[ph], avg))
        print("%-26s %3d packets (after the first two): %d with %d, %d with %d; every window of %d packets has %d "
              "with %d; average %s = %.6f kHz" % (members[ph], len(body), inc.count(0), k, inc.count(1), k + 1,
                                                  d, n, k + 1, avg, float(avg)))
    if FAILS:
        print("RESULT: FAIL %d mismatch(es)" % len(FAILS))
        return 1
    print("RESULT: PASS")
    return 0


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--packet":
        return packet_main(sys.argv[2], sys.argv[3])
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    vcd, repo = sys.argv[1:3]
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location("w2_checks", os.path.join(repo, "doc", "dev-ntsc", "tools", "w2_checks.py"))
    w2 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(w2)

    pkg = w2.read(repo, "M2M/vhdl/av_pipeline/video_modes_pkg.vhd")
    recs = w2.parse_records(pkg)
    members = w2.parse_members(pkg)
    _, vector, _, _ = w2.parse_framework(w2.read(repo, "M2M/vhdl/framework.vhd"))
    tb = w2.strip_comments(w2.read(repo, "CORE/vhdl/test/tb_hdmi_raw_clock/tb_hdmi_raw_cts.vhd"))
    tbvec = re.findall(r"\b(C_\w+)", re.search(r"VIDEO_MODE_VECTOR\s*:.*?:=\s*\((.*?)\);", tb, re.S).group(1))
    check(tbvec == vector, "the vector of tb_hdmi_raw_cts.vhd is not VIDEO_MODE_VECTOR of framework.vhd")
    vo = w2.read(repo, "M2M/vhdl/controllers/HDMI/video_out_clock.vhd")

    # packets: (time, phase, cts); changes of CTS: times
    ch = w2.parse_vcd(vcd)
    state, packets, cts_changes = {}, [], []
    for t, name, v in ch:
        if name == "audio_pcm_cts" and state.get(name) is not None and state.get(name) != v:
            cts_changes.append(t)
        prev = state.get(name)
        state[name] = v
        if name == "audio_pcm_acr" and v == "1" and prev == "0":
            packets.append((t, int(state["tb_phase"], 2), int(state["audio_pcm_cts"], 2)))
    # the CTS value at the strobe is the value after all changes at that time
    final = {}
    for t, name, v in ch:
        if name == "audio_pcm_cts":
            final[t] = int(v, 2)
    print("%d packets, %d changes of CTS" % (len(packets), len(cts_changes)))

    # steps: consecutive packets with the same phase
    steps = []
    for t, ph, cts in packets:
        cts = final.get(t, cts)
        if ph == 99:
            continue
        if not steps or steps[-1][0] != ph:
            steps.append((ph, []))
        steps[-1][1].append(cts)
    print("%-28s %-26s %7s %10s %-26s %s" % ("mode", "record", "packets", "CLK_KHZ", "average CTS (kHz)", "pixel clock (kHz)"))
    for ph, ctss in steps:
        rec = recs[vector[ph]]
        k, n, d = rec["CLK_KHZ"], rec["CTS_FRAC_N"], rec["CTS_FRAC_D"]
        m, dd, o0, o1, f = w2.mmcm_freq(w2.drp_table(vo, rec["CLK_SEL"]))
        pix = Fraction(100000) * Fraction(m) / dd / Fraction(o1)
        if n == 0:
            check(all(c == k for c in ctss), "%s: CTS %s, expected %d in every packet" % (
                members[ph], sorted(set(ctss)), k))
            avg = Fraction(sum(ctss), len(ctss))
        else:
            body = ctss[2:]
            check(all(c in (k, k + 1) for c in body), "%s: CTS values %s" % (members[ph], sorted(set(body))))
            inc = [c - k for c in body]
            for i in range(len(inc) - d + 1):
                if sum(inc[i:i + d]) != n:
                    check(False, "%s: window at packet %d has %d increments, expected %d" % (
                        members[ph], i + 2, sum(inc[i:i + d]), n))
                    break
            whole = (len(body) // d) * d
            avg = Fraction(sum(body[:whole]), whole) if whole else None
            check(avg == k + Fraction(n, d), "%s: average CTS %s, expected %s" % (members[ph], avg, k + Fraction(n, d)))
            check(pix == k + Fraction(n, d), "%s: pixel clock %s kHz, record says %s" % (members[ph], pix, k + Fraction(n, d)))
        print("%-28s %-26s %7d %10d %-26s %s" % (members[ph], vector[ph], len(ctss), k,
                                                 "%s (%.6f)" % (avg, float(avg)), "%s (%.6f)" % (pix, float(pix))))
    # every change of CTS lies at least 0.4 ms away from every strobe, except at a change of the mode
    # (the CTS follows the new record at once, the accumulator is cleared one audio clock later)
    strobes = [t for t, _, _ in packets]
    mode_times = [t for t, name, _ in ch if name == "tb_phase"]
    near, unexplained = 0, 0
    for t in cts_changes:
        if any(abs(s - t) < 400 * 10 ** 9 for s in strobes):          # VCD unit: fs; 0.4 ms
            near += 1
            if not any(0 <= t - m <= 200 * 10 ** 6 for m in mode_times):   # 200 ns
                unexplained += 1
    print("changes of CTS within 0.4 ms of a strobe: %d, all of them at a change of the mode: %s" % (
        near, "yes" if unexplained == 0 else "NO (%d)" % unexplained))
    check(unexplained == 0, "CTS changes close to a strobe without a change of the mode")
    seen_raw = {members[ph] for ph, _ in steps if recs[vector[ph]]["CTS_FRAC_N"] != 0}
    check(seen_raw == {"C_VIDEO_HDMI_16_9_50_RAW", "C_VIDEO_HDMI_4_3_50_RAW", "C_VIDEO_HDMI_5_4_50_RAW",
                       "C_VIDEO_HDMI_16_9_5994_RAW"}, "raw modes with a fraction covered: %s" % sorted(seen_raw))
    check(len({ph for ph, _ in steps}) == 16, "not every mode covered")
    if FAILS:
        print("RESULT: FAIL %d mismatch(es)" % len(FAILS))
        return 1
    print("RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
