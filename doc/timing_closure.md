# Timing closure and the build re-roll

Now and then a board fails timing although nothing is wrong with the design:
one hold check in the HyperRAM read path misses, usually by a few tens of
picoseconds. [Issue #224](https://github.com/MJoergen/C64MEGA65/issues/224)
is such a case: an R3 build missed hold by 0.055 ns at `hr_d_io[4]`. Which
board and which build it hits is a matter of placement luck, so
`CORE/build_all.sh` re-rolls such a board automatically. This note explains
the path, why at present neither a tool setting nor a design change can fix
it, and why the re-roll is safe.

The short version:

* The failing check is the **HyperRAM read capture** of the M2M framework.
  Its hold margin is only a few tenths of a nanosecond, and it is decided by
  the fabric route of the RWDS strobe, which changes with every placement.
* **Vivado cannot repair it**, and building again unchanged gives the
  identical result: Vivado is deterministic and has no seed.
* The design-side lever, the **IDELAY tap of the strobe, is
  field-calibrated** and must not change.
* A new placement is a **fresh draw** from the same distribution that every
  shipped build came from. Most placements pass, so `build_all.sh` keeps
  drawing until one does.

## The path

`M2M/vhdl/controllers/hyperram/hyperram_rx.vhd` samples the eight HyperRAM
data lines with IDDRs that are clocked by the RWDS strobe:

```
hr_d_io[n] -> IBUF -> IDDR D                                   (hard-wired)
hr_rwds_io -> IBUF -> IDELAYE2 (FIXED, 20 taps) -> fabric route -> IDDR C
```

The strobe is a clock on general fabric routing (`CLOCK_BUFFER_TYPE NONE` in
`M2M/common.xdc`) with 36 loads: the eight IDDRs, the receive FIFO and a
clock-domain-crossing flop. For each data bit, the hold slack in the slow
corner comes down to

```
hold slack = 1.544 ns - fabric route from the IDELAY to this IDDR
```

Everything else in the path is fixed silicon: the pins, the IDDR and IDELAY
sites and the constraints are identical on R3, R4, R5 and R6. The route is
not fixed. It depends on where the placer puts the fabric loads of the
strobe, and it moves by a few tenths of a nanosecond from build to build.
Two R3 builds show the range:

| Build | Route to the DQ4 IDDR | Hold slack of DQ4 |
|-------|-----------------------|-------------------|
| Issue #224 (June 2026) | about 1.60 ns | −0.055 ns |
| WIP-V6-A20X3 (October 2026) | 1.306 ns | +0.237 ns |

The same HyperRAM controller and constraints are used by other MiSTer2MEGA65
cores. AExp, for example, has seen routes between 0.87 and 1.55 ns, and one
miss in 13 R3 and R6 builds with the implementation strategy that all four
C64MEGA65 boards use (`Performance_ExplorePostRoutePhysOpt`).

### Reading the timing report

The hold check shows a **requirement of 0.000 ns**. That is normal for a hold
check: launch and capture happen on the same RWDS edge, which the report
spells out as `hr_rwds rise@2.500ns - hr_rwds rise@2.500ns`. The input
delay of 4.2 ns (5.0 ns plus `tDSHmin` of −0.8 ns from `M2M/common.xdc`) is
part of the arrival time, not of the requirement, so it does not point to a
misconfigured constraint.

## Why the tools cannot fix it

* The router repairs hold violations by making the **data** path longer.
  Here the data path is the hard-wired pad-to-IDDR connection, so there is
  nothing to lengthen, and the router does not shorten the strobe route to
  gain hold.
* Post-route `phys_opt_design` only works on setup.
* Vivado is deterministic: the same sources, constraints and settings give
  the same bitstream, bit for bit. Issue #224 shows it: synthesis and
  implementation were run again, and the same path missed by the same
  0.055 ns. There is no placer seed; a different directive is the closest
  equivalent.

## Why we do not change the design

The sampling point of the HyperRAM read is the IDELAY delay plus the fabric
route of the strobe. The IDELAY value 20 is the result of a long field
process: individual MEGA65 machines (serial numbers, not board revisions)
differ slightly in their HyperRAM behavior, and 20 works on 99.999% of
them. So:

* **Changing the tap** would move the sampling point of every MEGA65 away
  from the field-proven setting. That needs a new field campaign, not a build
  fix.
* **Forcing the strobe route**, with fixed routing or by re-routing single
  strobe branches with delay targets, moves the sampling point just the same.
  Re-routing a single branch does not even help much: the new branch has to
  hang off the existing strobe tree, so it cannot be faster than the slow
  trunk that caused the miss.
* **Loosening the input delay constraints** would only hide the missing
  margin.

A new placement changes none of this. It gives the strobe a new route from
the same distribution that every shipped build was drawn from, so the
sampling point stays inside the calibrated range.

## The re-roll in `build_all.sh`

After all selected boards are built, `build_all.sh` re-rolls every board
whose build only missed timing: `TIMING-FAILED` with a setup or hold miss of
at most `REROLL_MAX_MISS` (0.3 ns by default). Synthesis failures, failed
sign-off gates and crashes are never re-rolled, because they are real
problems. Debug builds (`DEBUG=1`) are not checked for timing and therefore
never re-rolled.

`CORE/reroll_bitstream.tcl` then works through every attempt until one
meets setup and hold:

* After a **hold miss** it tries new placements first (ten placer
  directives), then five router directives on the existing placement.
* After a **setup-only miss** it first runs a harder post-route
  `phys_opt_design`, then the re-routes, then the new placements.
* An attempt that misses setup only gets one more, harder `phys_opt_design`
  pass before it counts as failed.

The placer and router directives of the project strategy (`Explore` for
both) are read from the `.xpr` and left out: the failed build already used
them, so an attempt with them would only repeat it.

Every attempt starts from the checkpoints of the failed build, which
`build_all.sh` checks are newer than that build's start. That is the same
synthesized and optimized netlist with the same constraints; only placement,
routing and `phys_opt_design` are redone. The result passes the same sign-off
as a first pass: full timing analysis in both corners, the bitstream
design-rule check and the gates of `CORE/signoff_gates.tcl`, which
`build_bitstream.tcl` and `reroll_bitstream.tcl` share. A re-rolled
bitstream is therefore exactly as valid as a first-pass one.

The winner replaces `mega65_<board>.bit` and `mega65_<board>.mmi` in
`CORE/CORE-<board>.runs/impl_1`, so `make_release.py`, `m65` and everything
else find it where they always do. Next to it, `mega65_<board>_reroll.txt`
records which attempt won, `mega65_<board>_reroll_timing.rpt` holds its
timing report and `mega65_<board>_reroll.dcp` its checkpoint. All other
reports in that folder describe the failed first pass. The console output
of a re-roll goes to `CORE/build_<board>_reroll.log`.

The summary at the end of `build_all.sh` shows the outcome per board, for
example:

```
RESULT R3 OK after re-roll 2/15 (place_design ExtraTimingOpt, route_design Explore) WNS=0.312 WHS=0.036 bit=CORE-R3.runs/impl_1/mega65_r3.bit
    first pass: TIMING-FAILED WNS=0.345 WHS=-0.055
    REROLL R3 1/15 place_design ExtraPostPlacementOpt, route_design Explore: fail WNS=0.301 WHS=-0.012 (10 min)
    REROLL R3 2/15 place_design ExtraTimingOpt, route_design Explore: PASS WNS=0.312 WHS=0.036 (10 min)
RESULT R6 OK WNS=0.336 WHS=0.039 bit=CORE-R6.runs/impl_1/mega65_r6.bit
```

An attempt takes about as long as the implementation part of a normal
build, roughly 10 minutes per board. `./build_all.sh --no-reroll` skips the
re-roll pass, and `./build_all.sh --help` lists all options.

### What this means for the Vivado IDE

A re-rolled bitstream is the one case in which a command-line build differs
from what *Run Implementation* in the IDE produces: its placement and
routing come from the winning directives. It is still reproducible, because
Vivado is deterministic: the same checkpoint and the directives recorded in
`mega65_<board>_reroll.txt` give the same bitstream.

If an IDE build misses this check, running the implementation again
unchanged gives the same miss. The checkpoints of an IDE build are the same
as those of a command-line build, so the re-roll can be started by hand
afterwards, from `CORE/`, with the slacks of the failed build:

```
vivado -mode batch -source reroll_bitstream.tcl -tclargs R3 4 0.345 -0.055
```
