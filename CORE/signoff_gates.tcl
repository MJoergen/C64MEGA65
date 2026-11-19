# CORE.xdc sign-off gates, shared by build_bitstream.tcl and
# reroll_bitstream.tcl so that a first-pass bitstream and a re-rolled one are
# checked against exactly the same list.
#
# signoff_gates returns a list of human-readable problems with the constraints
# as actually applied to the currently-open design; an empty list means every
# gate passed. Each check mirrors a CORE.xdc line that turns into a silent
# no-op if the object it names has been renamed. When you add or rename
# hierarchy that CORE.xdc references, update this list in the same commit.
#
# signoff_bus_skew does the same for the bus skew constraints, which need a
# routed design: build_bitstream.tcl and reroll_bitstream.tcl call it after
# signoff_gates on the design that the bitstream is written from.

proc signoff_gates {} {
    set gate {}

    # set_case_analysis 1 on both bits of the core clock selector (CORE.xdc:17-18):
    # bit 0 = flicker-free leg, bit 1 = NTSC. If synthesis merged or renamed one
    # of the two flops, the main_clk tree would silently be timed against more
    # than one MMCM leg or not at all.
    foreach pin {{CORE/hr_core_speed_reg[0]/Q} {CORE/hr_core_speed_reg[1]/Q}} {
        if {[llength [get_pins -quiet $pin]] == 0} {
            lappend gate "set_case_analysis pin $pin missing"
        }
    }

    # main_clk generated clock and its source pin (CORE.xdc:20). The period is
    # fixed by the MMCM in clk.vhd (i_clk_c64_ntsc_ff CLKOUT0 = 32.7896996 MHz =>
    # 30.497 ns, the fastest of the four core clocks). The next slower leg, NTSC
    # original, is 32.727 MHz => 30.556 ns, so a 0.03 ns tolerance catches a
    # clock accidentally derived from the wrong leg.
    if {[llength [get_pins -quiet {CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0}]] == 0} {
        lappend gate "main_clk source pin CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0 missing"
    }
    set mc [get_clocks -quiet main_clk]
    if {[llength $mc] == 0} {
        lappend gate "generated clock main_clk missing"
    } elseif {[expr {abs([get_property PERIOD $mc] - 30.497)}] > 0.03} {
        lappend gate "main_clk period [get_property PERIOD $mc] ns, expected ~30.497 ns (wrong MMCM leg?)"
    }
    if {[llength [get_clocks -quiet qnice_clk]] == 0} {
        lappend gate "clock qnice_clk missing (common.xdc)"
    }

    # Deep IEC-drive CDC false-paths (CORE.xdc:29-52) -- the paths most likely
    # to drift when iec_drive internals are refactored. A pattern that resolves
    # to zero pins means its set_false_path constrained nothing, re-exposing a
    # metastability hazard that only bites on real hardware.
    foreach {desc pat} {
        "c1541_track busy_reg CDC" {CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/busy_reg/C}
        "iec_drive dtype_reg CDC"  {CORE/i_main/iec_drive_inst/dtype_reg[*][*]/C}
        "c1581 fdc sd_rdreq_sync"  {CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_rdreq_sync/s1_reg[*]/D}
    } {
        if {[llength [get_pins -quiet $pat]] == 0} {
            lappend gate "false_path target for $desc resolves to 0 pins ($pat)"
        }
    }

    # Bus skew constraint of the paddle crossing (CORE.xdc, set_bus_skew): both
    # ends need to resolve to all 32 flip-flops, otherwise a part of the bus is
    # not checked. The result of the check itself is signoff_bus_skew below.
    foreach {desc pat} {
        "paddle crossing, source registers"      {i_framework/i_qnice2main_paddles/input_reg_gen.src_data_reg[*]}
        "paddle crossing, destination registers" {i_framework/i_qnice2main_paddles/cdc_stable_gen.dst_data_d_reg[*]}
    } {
        set n [llength [get_cells -quiet $pat]]
        if {$n != 32} {
            lappend gate "set_bus_skew: $desc resolve to $n cells instead of 32 ($pat)"
        }
    }
    return $gate
}

# Bus skew sign-off, for a ROUTED design only (the numbers of an unrouted
# design are estimates). A bus skew violation appears neither in WNS nor in
# WHS and does not fail a build by itself, so this proc reads report_bus_skew:
#
#   * no constraint of the design may be violated (this includes the ones
#     that the XPM FIFOs bring along), and
#   * the constraint of the paddle crossing (CORE.xdc) needs to be there with
#     its 32 endpoints, its requirement of 10 ns and a slack that is met.
#
# It returns a list of problems like signoff_gates and prints one line with
# the measured numbers of the paddle crossing, prefixed with $tag.
proc signoff_bus_skew {tag} {
    if {[catch {report_bus_skew -return_string} rpt]} {
        return [list "report_bus_skew failed: $rpt"]
    }
    return [signoff_bus_skew_parse $tag $rpt]
}

# The part of signoff_bus_skew that works on the text of the report (section
# "Bus Skew Report Per Constraint": one block per constraint, starting with a
# line "Id: <n>", followed by the constraint, "Requirement: <r>ns",
# "Endpoints: <n>" and, for the worst endpoint, "Slack (MET|VIOLATED) : <s>ns").
proc signoff_bus_skew_parse {tag rpt} {
    set gate {}
    set ids {}
    set id ""
    foreach line [split $rpt \n] {
        if {[regexp {^Id: +(\d+) *$} $line -> i]} {
            set id $i
            lappend ids $id
            set blk($id) ""
        } elseif {$id ne ""} {
            append blk($id) $line \n
        }
    }

    set paddles 0
    foreach id $ids {
        set b $blk($id)
        set req "?"; set ends "?"; set verdict ""; set slack "?"
        regexp -line {^Requirement: +([-0-9.]+)ns} $b -> req
        regexp -line {^Endpoints: +(\d+)} $b -> ends
        regexp -line {^Slack \((\w+)\) *: +([-0-9.]+)ns} $b -> verdict slack
        set is_paddles [expr {[string first "i_qnice2main_paddles" $b] >= 0}]

        if {$verdict eq "VIOLATED"} {
            lappend gate "bus skew constraint $id is violated: requirement $req ns, slack $slack ns ([string range [string trim [lindex [split $b \n] 0]] 0 150] ...)"
        }
        if {!$is_paddles} { continue }
        incr paddles
        puts "$tag paddle crossing: requirement $req ns, $ends endpoints, slack $slack ns ($verdict)"
        if {$verdict eq ""} {
            lappend gate "bus skew of the paddle crossing: report_bus_skew shows no slack for it"
        }
        if {$ends ne "32"} {
            lappend gate "bus skew of the paddle crossing: $ends endpoints instead of 32"
        }
        if {$req eq "?" || abs($req - 10.0) > 0.0005} {
            lappend gate "bus skew of the paddle crossing: requirement $req ns instead of 10 ns"
        }
    }
    if {$paddles != 1} {
        lappend gate "bus skew of the paddle crossing: $paddles constraints in report_bus_skew instead of 1 (CORE.xdc set_bus_skew)"
    }
    return $gate
}
