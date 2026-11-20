# Genlock bench (issue #184)

`M2M/vhdl/av_pipeline/hdmi_genlock.vhd` holds the HDMI picture of a raw mode 2.0 ms (or, within a band of 2.5 ms, later) behind the picture of the core and makes the two frame rates equal, by making 16 lines of the vertical back porch longer (`doc/dev-hdmi-raw/SPEC.md`, section 5). This bench runs the entity in the four raw modes against a cycle-exact model of the scaler's output timing and a core reference with the exact frame period of the core, from start phases over the whole frame and through disturbances, and checks every line, every frame and every output against the specification.

## How to run

```
CORE/vhdl/test/tb_hdmi_genlock/run.sh [pal720|pal576|ntsc720|ntsc480|modes|quick|xcheck|synth|mutants|all] [--keep]
```

* `pal720`, `pal576`, `ntsc720`, `ntsc480`: the complete simulation of the mode with all instances of the entity (section "Instances").
* `modes`: the four complete simulations.
* `quick`: a smoke test for work on the entity: the four modes with a reduced set, then `synth`. The reduced set has the start phases whose pull-in is short (`target - 4081`, `target - 1025`, `target - 1`, `target`, `target + 4095`, `target - 300` in the aperture; in 576p and 480p also `1`, `frame - 1`, `frame` and `0`), pauses of the reference of 12 instead of 150 frames and 31 instead of 311 locked frames; of the disturbance instances in 576p and 480p all except the two that come back near the end of the frame, in 720p only `1 ref missing`, `pause, back at the same phase`, `1 ref missing in the pull-in`, `1 ref missing while locking`, `small jump, then 3 refs gone`, `rst in a long line, mid, at d` and `htotal_i short, then 4045`.
* `xcheck`: the cross-check of the stepped scaler models (section "The model of the scaler").
* `synth`: `ghdl --synth` of `hdmi_genlock` must run without error and without latch (a mutant with a latch must fail); prints the flip-flop count of the GHDL netlist: 57 flip-flops in 11 registers.
* `mutants`: the mutants below; each must make the bench fail.
* `all` (default): `modes`, `xcheck`, `synth` and `mutants`, the complete verification: this is the run that counts. At most two simulations run at the same time.
* `--keep`: keeps the build directory and prints its path.

The runner ends with `RESULT: PASS` (exit status 0) or `RESULT: FAIL ...`. Requirements: GHDL 5.1.1 (`/usr/local/bin/ghdl`, or set `GHDL`), python3. Runtime: see the section "Runtime".

## The model of the scaler

`scaler_step` in `tb_ascal_timing_pkg.vhd` is a copy of what `ascal.vhd` does with the output timing (`o_ce = '1'`, `run = '1'`): the timing inputs (`htotal`, `hsstart`, `hsend`, `hdisp` and the vertical ones) are registered in every clock cycle (lines 1878 to 1890, initial value 0), process `OSWEEP` (lines 2674 to 2720) counts `o_hcpt` and the vertical lead counter `o_vcpt_pre3` with the delayed `o_vcpt`, forms `o_hsv(0)`, `o_vsv(0)`, `o_dev(0)` and shifts them through the ten-stage delay lines, and the ports `o_hs`, `o_vs`, `o_de` are registers fed by stage 9 (lines 2852 to 2854): 11 clock cycles behind the counters. The `htotal` input of each model is the `htotal_o` of its instance, so the stretch acts on the model exactly as it acts on ascal. The model reports each line that ends with its number (`o_vcpt`) and its length. The package holds nothing but this model, so that other benches can use it (for example a bench of the wiring in `digital_pipeline.vhd`); everything that only this bench needs is in `tb_hdmi_genlock_pkg.vhd`.

The bench steps the model of an instance only at the clock edges at which something can change (a threshold of the horizontal counter, the end of a line, a change of the vertical counter, a delay line that has not settled, any change of an input or an output of the instance, the reference, a disturbance) and advances the horizontal counter arithmetically in between; this makes the simulation about ten times faster. `G_XCHECK` steps a second copy of every model at every edge and compares the two at every edge (ports, counters, line ends); `run.sh` runs this cross-check in NTSC 480p (45 frames, all disturbances) and PAL 720p (7 frames).

The four raw modes (`C_MODES` in `tb_hdmi_genlock_pkg.vhd`) have the totals and sync positions of SPEC section 4.1: PAL 720p 1980 x 750 (vsync falls in line 730, stretch lines 730 to 745), PAL 576p 864 x 624 with a vertical front porch of 4 lines (vsync falls in line 585, stretch lines 585 to 600), NTSC 720p 1650 x 750 (730 to 745), NTSC 480p 858 x 526 with a vertical back porch of 31 lines (495 to 510).

## The core reference

The length of a core frame in pixel clocks is exact: core clock 100 MHz x 227 / 720 (PAL) or 100 MHz x 36 / 110 (NTSC), 312 x 63 x 32 or 263 x 65 x 32 core clocks per frame, pixel clocks 100 MHz x 67 / 90, x 227 / 840, x 237 / 320 and 27 MHz. That gives 337139712 / 227 = 1485196.969 (PAL 720p), 539136 (PAL 576p), 14855555 / 12 = 1237962.917 (NTSC 720p) and 451308 (NTSC 480p) pixel clocks. The simulated pixel clock period is a multiple of the denominator in femtoseconds (13432725, 37004405, 13502112 and 37037037 fs, at most 8.3 ppm from the true period), so a core frame is a whole number of femtoseconds: the ratio of the two clocks is exact, with no rounding error at all, and does not drift over any number of frames. The deviation of the time scale changes only the seconds in the reports.

For each instance a reference level rises once per core frame (the first visible pixel after the core's vsync) and falls 7/8 of a frame later (the next vsync), at times computed in femtoseconds. In the pixel clock domain it passes two flip-flops, and a third flip-flop forms the one-cycle pulse `ref_i` from its rising edge, as the real crossing through `xpm_cdc_single` will do. A change of the level less than 500 ps before a clock edge is taken over at that edge or at the next one, at random: this is the one-cycle uncertainty of the real crossing. In 720p the phase of the reference moves through the clock period from frame to frame (the core frame is not a whole number of pixel clocks), so every long run passes the aperture many times; in 576p and 480p the phase is constant, and one instance per mode places the reference inside the aperture, so that it is taken one cycle early or late at random in every frame.

## Instances

The complete simulation runs 35 instances of the entity side by side on the pixel clock of its mode. All start in reset; the reset ends right after the first falling edge of vsync, and the reference of each instance is placed so that its first measurement (the picture start of the second frame) is its distance `d0`.

Start phases (the first measured distance; `target` = `target_i` = 2 x `CLK_KHZ`, `frame` = the core frame):

| `d0` | why |
|---|---|
| 1, `target / 2` | far below the target: stretches of 4080 |
| `target - 4081`, `target - 4080` | one stretch of 4080 more or less |
| `target - 1025`, `target - 1024` | just outside and at the lower edge of the lock window |
| `target - 1`, `target`, `target + 1` | just before, at and just after the target |
| `target + 4096` | inside the band (the band of the first draft of the specification ended here) |
| `target + band - 1` | last phase of the band (`band = target + target / 4`, 2.5 ms): in 720p `d` glides back to the target without stretch (up to 945 frames in PAL), in 576p and 480p it stays |
| `target + band` | the first phase beyond the band, the worst case: the picture start has to come round the whole frame |
| `frame / 4`, `frame / 2`, `frame * 3 / 4` | the middle of the frame |
| `frame - 4000`, `frame - 1` | just before the next reference |
| `frame` | the next reference comes in the clock cycle of the measurement |
| `0` | no reference before the first measurement, the first one comes in its clock cycle: the measurement is not valid, the reference counts for the next one (in 576p and 480p every following reference comes in the cycle of a measurement until the first stretch) |
| `target - 300` | the reference inside the aperture of the synchronizer |

A start instance runs until it is locked and has been locked for 10 frames; `target - 1` (and in 576p and 480p also `target - 300`) stays locked for 311 frames.

Disturbance instances start at `target - 2000`, lock, and then execute their list; each step waits until the instance has been locked for 3 frames, if the list says so:

| Instance | Disturbance |
|---|---|
| 3 refs missing, new phase | 3 reference pulses missing, the following ones 30000 pixel clocks later |
| pause, back at another phase | no reference for 150 frames (the core is paused: 3 s in PAL, 2.5 s in NTSC), then back near the end of the frame: normal pull-in |
| pause, back at the same phase | no reference for 150 frames, back at the same phase: the genlock stays locked through it all and keeps the stretch of the last valid frame (the flywheel), no pull-in |
| 1 ref missing, 2 refs missing | back at the same phase: stays locked; after the single missing reference the next valid `d` is within twice the uncertainty of `target - surplus` |
| 1 ref missing in the pull-in | start at `target - 20000`, one reference missing before the lock (lock counter 0): no stretch in that frame (no flywheel while not locked) |
| 1 ref missing while locking | one reference missing while the lock counter is 3 (in 720p the stretch of the frame before is the surplus, not 0): no stretch in that frame, the counter neither counts nor clears, the lock comes one valid measurement later |
| small jump, then 3 refs gone | while locked, the reference moves so that `d` lands 960 below the target (inside the lock window: 763 pixel clocks later in PAL 720p, 497 in NTSC 720p, 960 in 576p and 480p), and the next 3 references are missing: the flywheel holds the catch-up stretch of about 960 for the whole outage, `d` moves by the jump per frame of it into the band, and the genlock stays locked |
| ref jumps 40000 later | the reference moves by a part of a frame while locked |
| ref jumps to frame end | the reference moves so that `d` is near the end of the frame |
| enable off in a long line | a jump, then `enable_i = '0'` inside the extension of a stretch line of 255 extra clock cycles, 3 frames later back on |
| rst in a long line, mid, at d | a jump, then `rst_i` for 5 cycles inside the extension of a stretch line; later `rst_i` for one cycle in the middle of the picture and in the clock cycle of the measurement |
| htotal_i short, then 4045 | `htotal_i` below `hsstart` for about 30000 pixel clocks (no hsync in those lines), back; in the next frame (stretch 4080) `htotal_i` = 4045 for three stretch lines, so that `htotal_o` saturates at 4095 |
| target_i + 30000, - 2000 | `target_i` changes while locked, up and later down into the band |
| enable_i one-cycle pulses | the reference jumps so that `d` = 6000 (it then comes after the falling edge of vsync), `enable_i` goes to `'0'`; then `enable_i = '1'` for exactly one clock cycle, in the cycle of a rising edge of `hs_i`, of a rising edge of `de_i`, of `ref_i`, at an arbitrary point, and last in the cycle of a falling edge of `vs_i`; two lines after that falling edge `enable_i` goes to `'1'` for good. A pulse must leave nothing behind: in the cycle of each pulse `htotal_o = htotal_i`, `stretch_o` = 0 and `locked_o = '0'`, and in all cycles after it as well; a measurement armed by the last pulse would show at the next picture start, which is not a measurement after the real enable (no falling edge of `vs_i` since then) |

## Checks

At every clock edge (the bench steps an instance at every edge at which one of its inputs or outputs changes or can change; between two such edges inputs and outputs are constant, so a check that holds at the first holds at all of them):

* `htotal_i <= htotal_o <= htotal_i + 256`.
* With `enable_i = '0'`: `htotal_o = htotal_i`, `locked_o = '0'`, `stretch_o = 0`.
* After a clock edge with `rst_i = '1'`: `htotal_o = htotal_i`.
* `htotal_o` changes only after a rising edge of `hs_i`, after `rst_i`, or with `htotal_i` or `enable_i`.
* `stretch_o` and `locked_o` equal a model of SPEC section 5.3 in the bench: the distance counter, the new reference since the last measurement, the measurement at the first rising edge of `de_i` after a falling edge of `vs_i`, the table of the stretch with the band, the flywheel (a measurement without a new reference keeps the stretch while locked and gives 0 otherwise, and never changes the lock counter), the lock rule. With the model, the line checks below also prove that during a pause of the reference every frame keeps the length of the last valid frame.

At every line end:

* A line during which neither `rst_i`, `enable_i` nor `htotal_i` changed is exactly `htotal_i` long, except the lines `vsend` to `vsend + 15` (numbered by the scaler's own `o_vcpt`, independent of the entity): of the stretch `k` of the frame, the first `k mod 16` of them are `htotal_i + k / 16 + 1` long, the others `htotal_i + k / 16` (at most 4095).
* Any other line is between the smallest `htotal_i` during the line and the largest plus 256.

At every measurement (the checks of `d` only at valid ones, with a new reference):

* The first measurement after the start is `d0`, at the predicted clock edge (`d0` or `d0 - 1` with the reference in the aperture).
* Between two valid measurements without a disturbance, `d` moves by `k - surplus` modulo a core frame, within the uncertainty of the crossing (`1 + 500 ps / period` pixel clocks).
* A lock is lost only through a disturbance; every lock comes within the bound of SPEC section 5.3 (8, 3, 6 and 2 s: 400, 150, 358 and 119 frames), counted from the start or from the last disturbance (without the frames in which the reference was missing). The instances with references missing at an unchanged phase never lose the lock.
* After lock `d` stays in the lock window. In 720p, from the first `d <= target`: `|d - (target - surplus)|` and `|k - surplus|` stay below the uncertainty. In 576p and 480p: `k` = 0 after lock, every frame has the static length of the record; with the reference inside the aperture at most one frame with `k` = 1 (see "Bounds").
* For the instances locked for 311 frames: from the 10th locked frame on, the sum of the HDMI frame lengths (clock edges between two picture starts) differs from the same number of core frames by less than `1 + 500 ps / period` pixel clocks, over 300 frames.

Coverage: the bench marks the 4096-pixel-clock sections of the frame in which the start instances measured `d` before lock; the trajectories cover every section outside the band (section "Results").

## Bounds

Equal rates. Let `e(n)` be the clock edge at which the entity sees the picture start `n`, and `r(n) = R(n) + delta(n)` the edge at which it takes the reference before it, with `R(n)` the exact time of the core's picture start (in pixel clocks) and `delta(n)` the delay of the crossing (from 2 to 3 cycles; a change of the level inside the aperture can be taken one cycle later, so `delta` lies between 2 and `3 + 500 ps / period`). Then `d(n) = e(n) - r(n)` and `e(n+1) - e(n) = htotal x vtotal + k(n)`. In the steady state `k(n) = target - d(n)`, so `d(n+1) = target - surplus - (delta(n+1) - delta(n))` and `k(n) = surplus + delta(n) - delta(n-1)`. The sum of `k(n) - surplus` over `N` frames telescopes to `delta(N-1) - delta(-1)`: the HDMI frames of any number of locked frames differ from as many core frames by less than one pixel clock plus the aperture (1.037 pixel clocks in 720p, 1.014 in 576p and 480p). In 576p and 480p `k` = 0 and the difference is 0.

Steady state. In 720p `|d - (target - surplus)| < 1 + aperture / period` and `k` takes the two integers around the surplus (one more or less when the reference falls into the aperture). In 576p and 480p with the reference inside the aperture `d + delta` stays constant while `k = 0`: after the arrival `d` is `target` or `target - 1`, and the first time it is `target - 1` the genlock stretches by 1, after which `d` is `target` or `target + 1` for good. So at most one frame with `k` = 1.

Pull-in. Beyond the band (`d >= target + band`) the picture start falls behind by `4080 - surplus` per frame until it comes round to the target from below. A frame-level model of the control law (every 523rd phase of the frame, and every phase of the first 4200 pixel clocks beyond the band) finds the longest pull-in a few hundred pixel clocks beyond the band: 343, 124, 299 and 102 measurements until `locked_o` (6.84, 2.47, 5.00 and 1.70 s); the bench's start at `target + band` needs exactly as many. Below the target the pull-in is at most `ceil(target / (4080 - surplus))` frames plus the 8 frames of the lock rule; inside the band the genlock is locked after 8 frames and stretches nothing.

Missing reference. While locked, a frame without a new reference keeps the stretch `k(n)` of the last valid frame instead of `k(n+1) = surplus + delta(n+1) - delta(n)`; after one missing reference in the steady state `d` therefore differs from `target - surplus` by less than twice the uncertainty (two differences of crossing delays). In the steady state the held stretch differs from the surplus by less than one pixel clock per frame (in 720p it is one of the integers around the surplus), so `d` moves by less than one pixel clock per frame of a pause: 150 frames move it by less than 150 pixel clocks, far inside the lock window; in 576p and 480p the held stretch is 0 and `d` does not move.

This holds only in the steady state. If the references stop right after a valid measurement that is inside the lock window but below `target - surplus` (for example after a small jump of the core's phase), the catch-up stretch of that frame (up to 1024 plus the surplus) is held for the whole outage, and `d` moves by its difference to the surplus in every frame of it: the instance `small jump, then 3 refs gone` holds about 960 for 3 frames and ends inside the band. A long outage after such a frame can carry `d` beyond the band (in 576p a held stretch of 1000 for 100 frames moves `d` by 3.7 ms), and when the references come back the genlock has to come round the whole frame. Nothing is known that would stop the core's references right after such a jump; the behavior is accepted.

## Results

From the complete run (`run.sh all`), per mode:

| | PAL 720p | PAL 576p | NTSC 720p | NTSC 480p |
|---|---|---|---|---|
| `target` / `band` (pixel clocks) | 148888 / 186110 | 54046 / 67557 | 148124 / 185155 | 54000 / 67500 |
| clock edges simulated | 525.6 M | 172.0 M | 394.9 M | 144.0 M |
| longest pull-in (start `target + band`), measurements until `locked_o` | 343 (6.84 s) | 124 (2.47 s) | 299 (5.00 s) | 102 (1.70 s) |
| bound of SPEC 5.3 | 400 (8 s) | 150 (3 s) | 358 (6 s) | 119 (2 s) |
| other starts in the middle of the frame (`frame / 4`, `frame / 2`, `frame * 3 / 4`) | 333, 238, 142 | 121, 88, 55 | 8 (inside the band), 220, 135 | 8 (inside the band), 77, 49 |
| `d - target` after the arrival | -197 to -196 | 0 | -463 to -462 | 0 |
| `k` after the arrival | 196, 197 | 0 | 462, 463 | 0 |
| sum of 300 locked HDMI frames minus 300 core frames | 0.991 (bound 1.037) | 0 (bound 1.014) | 0.833 (bound 1.037) | 0 (bound 1.014) |
| first valid `d` after one missing reference, from `target - surplus` | 0.031 (bound 2.074) | 0 | 0.083 (bound 2.074) | 0 |
| pause of 150 frames at the same phase | locked throughout | locked | locked | locked |
| a reference missing while the lock counter is 3 | stretch 0 in that frame, lock one valid measurement later | the same | the same | the same |
| small jump, then 3 references gone: `d` at the return, from the target | +2092 (3 x 763 - 197), locked | +2880 (3 x 960), locked | +1028 (3 x 497 - 463), locked | +2880, locked |
| 4096-clock sections of the frame where a start measured `d` before lock | 320 of 363 | 118 of 132 | 263 of 303 | 98 of 111 |

The sections that no start crosses are those of the band (45 in 720p, 16 to 17 in 576p and 480p): nothing is stretched there, a phase inside the band is locked at once and glides back (720p) or stays (576p, 480p); the bench has starts at `target + 4096` and `target + band - 1` inside it. Every lock came within the bound, every line had the length of SPEC section 5.2, and the cross-check found the stepped scaler models equal to models stepped at every edge (NTSC 480p, 45 frames, 21.2 M edges; PAL 720p, 7 frames, 13.4 M edges).

## Mutants

Each mutant is an exact text replacement in `hdmi_genlock.vhd`; it runs in NTSC 480p (`no_hold` and `hold_unless_zero` in NTSC 720p) with the start or the disturbance instances and stops at its first error. A mutant counts as rejected only if its run fails with an error of the bench (`TB_ERROR`, for `no_saturation` the bound check of GHDL); a run that fails in any other way (crash, timeout, killed) is a failure of the runner. All are rejected:

| Mutant | Change | First error |
|---|---|---|
| `band_edge` | `d = target_i + band` counts as inside the band | start `target + band`: `stretch_o` 0, expected 4080 |
| `no_pullin` | no stretch above the band | start `target + band`: `stretch_o` 0, expected 4080 |
| `late_first_line` | the stretch lines begin with index 1 (15 lines) | start `target - 1`: line 495 is 858 long, expected 859 |
| `distribution` | one stretch line too many gets the extra clock cycle | start `1`: line 495 is 859 long, expected 858 |
| `index_stuck` | the line index does not advance, every line after vsync is stretched | start `target - 1`: line 0 is 859 long, expected 858 |
| `no_saturation` | `htotal_o` not limited to 4095 | `htotal_i` = 4045 in a stretch line: `htotal_o` out of its range (GHDL bound check) |
| `lock_early` | `locked_o` after 7 frames | start `target`: `locked_o` '1' after 7 good frames |
| `stale_ref` | a measurement without a new reference is used | 1 reference missing in the pull-in: `stretch_o` 4080, expected 0 |
| `same_cycle_ref` | a `ref_i` in the clock cycle of the measurement is lost | start `0`: `stretch_o` 0, expected 4080 (never valid again) |
| `rst_keeps_extra` | `rst_i` does not clear the extra length of the current line | `rst_i` in a long line: `htotal_o` 1113 after `rst_i` |
| `no_bypass` | `htotal_o` follows `enable_i = '0'` one clock cycle late | `enable_i = '0'` in a long line: `htotal_o` 1113 |
| `count_from_0` | `d` one clock cycle short | start `target - 1025`: `stretch_o` 1026, expected 1025 |
| `k_max_4095` | largest stretch 4095 | start `1`: `stretch_o` 4095, expected 4080 |
| `window_low` | the lock window starts at `target_i - 1023` | start `target - 1024`: `locked_o` '0' after 8 good frames |
| `every_de` | a measurement at every rising edge of `de_i` after the first falling edge of `vs_i` | start `1`: `stretch_o` 0, expected 4080 |
| `armed_kept` | `enable_i = '0'` does not clear the armed measurement | one-cycle pulses of `enable_i`: `stretch_o` 4080, expected 0 at the picture start after the real enable |
| `band_4096` | the band of the first draft (4096 pixel clocks) | start `target + 4096`: `stretch_o` 4080, expected 0 |
| `band_no_quarter` | `band = target_i` | start `target + band - 1`: `stretch_o` 4080, expected 0 |
| `no_hold` | no flywheel: stretch 0 without a new reference also while locked (runs in NTSC 720p, where the held stretch is not 0) | 3 references missing: `stretch_o` 0, expected 463 (the held stretch) |
| `gap_clears_lock` | a measurement without a new reference clears the lock counter | 1 reference missing while locking: `locked_o` '0' after 8 valid good frames |
| `hold_unlocked` | the stretch is held without a new reference also while not locked | 1 reference missing in the pull-in: `stretch_o` 4080, expected 0 |
| `hold_unless_zero` | the stretch is held without a new reference unless the lock counter is 0 | 1 reference missing while locking (NTSC 720p): `stretch_o` 463, expected 0 |
| `gap_counts_good` | a measurement without a new reference counts as inside the lock window | 1 reference missing while locking: `locked_o` '1' after 7 valid good frames |
| `hold_max_470` | the flywheel keeps only stretches up to 470 | small jump, then 3 references gone: `stretch_o` 0, expected 960 (the held catch-up stretch) |

`synth` adds a mutant with a latch, which `ghdl --synth` rejects.

Mutants that cannot be told apart from the entity, and why: clearing `ref_new` or `cnt` only with `rst_i` (and not with `enable_i = '0'`) changes nothing that can be seen, because a measurement needs both a new reference since `enable_i` came back and a counter that is not saturated; clearing `line_idx`, `vs_pend` or `extra` only with `rst_i` changes nothing either, because the stretch is 0 while `enable_i = '0'` and the line index runs out after 16 lines.

## Runtime

Measured on the development machine (8 cores, shared with other simulations), with two simulations at a time:

| Part | Wall time | Simulations |
|---|---|---|
| `quick` | 5 min (301 s) | the four modes with the reduced set (PAL 720p 170 s, NTSC 720p 141 s, PAL 576p 143 s, NTSC 480p 125 s), synthesis |
| `mutants` | 8 min (476 s) | 24 mutants, each until its first error |
| `xcheck` | about 3 min | NTSC 480p 185 s, PAL 720p 153 s |
| `all` | 36.4 min (2184 s; 3911 s CPU) | PAL 720p 1430 s, NTSC 720p 1100 s, PAL 576p 380 s, NTSC 480p 287 s, the cross-check, synthesis, the mutants |

The complete run is long because it simulates every clock cycle of every pull-in and of the 300 locked frames: in PAL 720p 525.6 M pixel clock edges. GHDL needs about 0.6 µs per clock edge for the clock and the bench, and every active instance adds about 0.25 µs, most of it in the signal updates of the entity itself; the bench gives an instance the clock only while it still has something to prove, and steps its scaler model only at the edges where something can change.
