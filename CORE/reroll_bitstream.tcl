# Re-roll one board whose build only missed timing - normally called by
# build_all.sh after build_bitstream.tcl reported TIMING-FAILED:
#
#   vivado -mode batch -source reroll_bitstream.tcl -tclargs <board> <jobs> <wns> <whs>
#
# <wns> and <whs> are the slacks of the failed build. Every attempt continues
# from a checkpoint of that build, i.e. from the same synthesized and optimized
# netlist with the same constraints; only placement, routing and phys_opt are
# redone, with other directives. A hold miss is attacked with new placements
# first, because the placement decides for example the fabric route of the
# HyperRAM read strobe. A setup-only miss is attacked first with harder
# optimization and routing of the existing placement. See doc/timing_closure.md.
#
# The first attempt that meets setup and hold and passes the sign-off gates of
# signoff_gates.tcl replaces mega65_<board>.bit and mega65_<board>.mmi in
# CORE-<board>.runs/impl_1, and leaves mega65_<board>_reroll.dcp,
# mega65_<board>_reroll_timing.rpt and mega65_<board>_reroll.txt next to them.
# Prints one "REROLL <board> ..." line per attempt and one final
# "RESULT <board> ..." line. Exits 0 on success, 2 if no attempt met timing and
# 3 if a sign-off gate failed.

set board [lindex $argv 0]
set jobs  [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set wns0  [lindex $argv 2]
set whs0  [lindex $argv 3]

# Vivado accepts at most 8 threads.
set_param general.maxThreads [expr {min($jobs, 8)}]

set b   [string tolower $board]
set run CORE-${board}.runs/impl_1
set ckpt(opt)    $run/mega65_${b}_opt.dcp
set ckpt(phys)   $run/mega65_${b}_physopt.dcp
set ckpt(routed) $run/mega65_${b}_postroute_physopt.dcp

foreach k {opt phys routed} {
    if {![file exists $ckpt($k)]} {
        puts "RESULT $board REROLL-FAILED $ckpt($k) not found"
        exit 2
    }
}

# The same gates as build_bitstream.tcl. A board that misses timing never
# reaches them there, so they have to be checked here.
source -notrace signoff_gates.tcl

proc signoff_failed {board gate why} {
    foreach g $gate { puts "GATE $board: $g" }
    puts "RESULT $board SIGNOFF-FAILED $why"
    exit 3
}

# Worst slack over both corners, or "" if there is no such path.
proc worst_slack {args} {
    set p [get_timing_paths -max_paths 1 -nworst 1 {*}$args]
    if {[llength $p] == 0} { return "" }
    return [get_property SLACK $p]
}

proc is_num {x} { return [string is double -strict $x] }

proc met {wns whs} {
    return [expr {[is_num $wns] && [is_num $whs] && $wns >= 0 && $whs >= 0}]
}

proc describe {start place route} {
    switch $start {
        opt    { return "place_design $place, route_design $route" }
        phys   { return "placement kept, route_design $route" }
        routed { return "placement and routing kept, phys_opt_design AggressiveExplore" }
    }
}

# The placer and router directives of the project strategy. The failed build
# already used them, and Vivado is deterministic, so an attempt with the same
# directive on the same checkpoint would only repeat it: they are left out of
# the lists below. A new placement is routed with the router of the project.
set proj_place Explore
set proj_route Explore
if {[catch {
    open_project -read_only CORE-${board}.xpr
    set proj_place [get_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]]
    set proj_route [get_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE [get_runs impl_1]]
    close_project
} err]} {
    puts "REROLL $board: could not read the directives of CORE-${board}.xpr, assuming Explore: [string map {\n " "} $err]"
    catch {close_project}
}
puts "REROLL $board: project strategy uses place_design $proj_place, route_design $proj_route"

# Explore, the directive of Performance_ExplorePostRoutePhysOpt, heads both
# lists for a project that uses another strategy. Then come the placer
# directives that aim at timing; the block-placement ones come last, because
# the misses seen so far are in fabric routing, not around block RAM or DSPs.
set placements {
    Explore
    ExtraPostPlacementOpt ExtraTimingOpt ExtraNetDelay_high ExtraNetDelay_low
    Default AltSpreadLogic_low AltSpreadLogic_medium AltSpreadLogic_high
    EarlyBlockPlacement WLDrivenBlockPlacement
}
set routes {
    Explore
    NoTimingRelaxation AggressiveExplore MoreGlobalIterations HigherDelayCost
    AdvancedSkewModeling
}
set placements [lsearch -all -inline -not -exact $placements $proj_place]
set routes     [lsearch -all -inline -not -exact $routes     $proj_route]

# {start place route}: "opt" places anew, "phys" keeps the placement and
# re-routes, "routed" keeps both and only runs post-route phys_opt harder.
set new_placement {}
foreach p $placements { lappend new_placement [list opt $p $proj_route] }
set new_routing {}
foreach r $routes { lappend new_routing [list phys - $r] }

if {[is_num $whs0] && $whs0 < 0} {
    set attempts [concat $new_placement $new_routing]
} else {
    set attempts [concat [list {routed - -}] $new_routing $new_placement]
}
set total [llength $attempts]

# No attempt can repair a gate, so check them once before spending hours.
open_checkpoint $ckpt(opt)
set gate [signoff_gates]
close_design
if {[llength $gate] > 0} {
    signoff_failed $board $gate "before the first re-roll attempt (first pass WNS=$wns0 WHS=$whs0)"
}

set n 0
foreach a $attempts {
    incr n
    lassign $a start place route
    set what [describe $start $place $route]
    set t0 [clock seconds]
    set rc [catch {
        open_checkpoint $ckpt($start)
        switch $start {
            opt {
                place_design    -directive $place
                phys_opt_design -directive Explore
                route_design    -directive $route
                phys_opt_design -directive Explore
            }
            phys {
                route_design    -directive $route
                phys_opt_design -directive Explore
            }
            routed {
                phys_opt_design -directive AggressiveExplore
            }
        }
        set wns [worst_slack -setup]
        set whs [worst_slack -hold]
        # A pure setup miss often yields to one more, harder phys_opt pass.
        if {$start ne "routed" && ![met $wns $whs] && [is_num $whs] && $whs >= 0} {
            phys_opt_design -directive AggressiveExplore
            append what ", phys_opt_design AggressiveExplore"
            set wns [worst_slack -setup]
            set whs [worst_slack -hold]
        }
    } err]
    set mins [expr {([clock seconds] - $t0 + 30) / 60}]
    set tag "REROLL $board $n/$total $what:"

    if {$rc} {
        puts "$tag ERROR ($mins min): [string map {\n " "} $err]"
        catch {close_design}
        continue
    }
    if {![met $wns $whs]} {
        puts "$tag fail WNS=$wns WHS=$whs ($mins min)"
        close_design
        continue
    }

    set gate [signoff_gates]
    if {[llength $gate] > 0} {
        signoff_failed $board $gate "on the design of attempt $n/$total ($what)"
    }
    # The same outputs as the write_bitstream step of the project run.
    set rc [catch {
        write_checkpoint -force $run/mega65_${b}_reroll.dcp
        report_timing_summary -max_paths 10 -report_unconstrained \
            -file $run/mega65_${b}_reroll_timing.rpt
        catch {write_mem_info -force -no_partial_mmi $run/mega65_${b}_reroll.mmi}
        write_bitstream -force $run/mega65_${b}_reroll.bit
    } err]
    if {$rc} {
        puts "$tag met timing, but writing the results failed ($mins min): [string map {\n " "} $err]"
        catch {close_design}
        continue
    }

    # Only a complete result replaces the files of the failed first pass.
    file rename -force $run/mega65_${b}_reroll.bit $run/mega65_${b}.bit
    if {[file exists $run/mega65_${b}_reroll.mmi]} {
        file rename -force $run/mega65_${b}_reroll.mmi $run/mega65_${b}.mmi
    }
    set fh [open $run/mega65_${b}_reroll.txt w]
    puts $fh "mega65_${b}.bit and mega65_${b}.mmi were written by a build_all.sh re-roll on [clock format [clock seconds]]."
    puts $fh "The first pass with the strategy of CORE-${board}.xpr missed timing: WNS=$wns0 WHS=$whs0."
    puts $fh "Winning attempt $n of $total: $what."
    puts $fh "Result: WNS=$wns WHS=$whs. Details: mega65_${b}_reroll_timing.rpt and mega65_${b}_reroll.dcp."
    puts $fh "All other reports in this folder describe the failed first pass."
    close $fh

    puts "$tag PASS WNS=$wns WHS=$whs ($mins min)"
    puts "RESULT $board OK after re-roll $n/$total ($what) WNS=$wns WHS=$whs bit=$run/mega65_${b}.bit"
    exit 0
}

puts "RESULT $board REROLL-FAILED none of $total attempts met timing (first pass WNS=$wns0 WHS=$whs0)"
exit 2
