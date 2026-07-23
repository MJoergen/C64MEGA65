# Build one C64MEGA65 board bitstream straight from its Vivado project.
#
# The .xpr is the SINGLE SOURCE OF TRUTH: file list, VHDL-2008/Verilog/SV
# classification, target part, XPM libraries, the synthesis and implementation
# strategies (impl_1 uses Performance_ExtraTimingOpt), the XDC read order and
# the synth_pre.tcl firmware/log-hygiene hook all come from the project. This
# script only drives the runs -- it never restates any of that, so it cannot
# drift from what the Vivado IDE builds.
#
# Normally called by build_all.sh, but usable standalone:
#
#   vivado -mode batch -source build_bitstream.tcl -tclargs <R3|R4|R5|R6> [jobs] [debug]
#
# Positional -tclargs:
#   1  board   R3 | R4 | R5 | R6                              (required)
#   2  jobs    number of parallel Vivado jobs                (default 4)
#   3  debug   "debug" -> insert ILA cores on mark_debug nets via debug.tcl;
#              omitted / anything else -> normal release build
#
# The bitstream is written where make_release.py and load_bitstream.sh look
# for it:  CORE-<board>.runs/impl_1/mega65_<board>.bit
#
# On a release build the routed design is re-opened and the CORE.xdc sign-off
# gates are checked, because those constraints silently constrain nothing when
# an instance name drifts. One machine-readable "RESULT <board> ..." line is
# printed and the script exits non-zero on any failure (distinct code per
# class): 1 build failed, 2 timing failed, 3 sign-off failed.

# ---------------------------------------------------------------------------
# CORE.xdc sign-off gates. Returns a list of human-readable problems with the
# constraints as actually applied to the currently-open routed design; an empty
# list means every gate passed. Each check mirrors a CORE.xdc line that turns
# into a silent no-op if the object it names has been renamed.
# ---------------------------------------------------------------------------
proc signoff_gates {} {
    set gate {}

    # set_case_analysis 0 on the flicker-free fast/slow clock selector (CORE.xdc:7)
    if {[llength [get_pins -quiet {CORE/hr_core_speed_reg[0]/Q}]] == 0} {
        lappend gate "set_case_analysis pin CORE/hr_core_speed_reg\[0\]/Q missing"
    }

    # main_clk generated clock and its source pin (CORE.xdc:9). The period is
    # fixed by the MMCM in clk.vhd (i_clk_c64_orig CLKOUT0 = 31.5277778 MHz =>
    # 31.718 ns). The slow flicker-free leg is 31.449 MHz => 31.797 ns, so a
    # 0.05 ns tolerance catches a clock accidentally derived from the wrong leg.
    if {[llength [get_pins -quiet {CORE/clk_gen/i_clk_c64_orig/CLKOUT0}]] == 0} {
        lappend gate "main_clk source pin CORE/clk_gen/i_clk_c64_orig/CLKOUT0 missing"
    }
    set mc [get_clocks -quiet main_clk]
    if {[llength $mc] == 0} {
        lappend gate "generated clock main_clk missing"
    } elseif {[expr {abs([get_property PERIOD $mc] - 31.718)}] > 0.05} {
        lappend gate "main_clk period [get_property PERIOD $mc] ns, expected ~31.718 ns (wrong MMCM leg?)"
    }
    if {[llength [get_clocks -quiet qnice_clk]] == 0} {
        lappend gate "clock qnice_clk missing (common.xdc)"
    }

    # Deep IEC-drive CDC false-paths (CORE.xdc:18-41) -- the paths most likely
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
    return $gate
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
set board [lindex $argv 0]
set jobs  [expr {[llength $argv] > 1 ? [lindex $argv 1] : 4}]
set debug [expr {[llength $argv] > 2 && [string match -nocase debug [lindex $argv 2]]}]

if {![regexp {^R[3456]$} $board]} {
    puts "RESULT ? FAILED bad board '$board' (expected R3|R4|R5|R6)"
    exit 1
}
set bit CORE-${board}.runs/impl_1/mega65_[string tolower $board].bit

open_project CORE-${board}.xpr

# ---------------------------------------------------------------------------
# Synthesis (project run -> uses the .xpr file list, part and synth strategy)
# ---------------------------------------------------------------------------
reset_run synth_1                       ;# force a clean rebuild; invalidates impl_1
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    puts "RESULT $board FAILED synth_1: [get_property STATUS [get_runs synth_1]]"
    exit 1
}

# ---------------------------------------------------------------------------
# Debug build: insert ILA cores on the synthesized netlist.
#
# debug.tcl (batch_insert_ila) must run after synthesis and before opt_design
# -- its documented slot -- so implementation is driven here in-session on the
# opened synth netlist that carries the freshly inserted cores. Consequence:
# the .xpr impl STRATEGY (Performance_ExtraTimingOpt) is NOT applied to a debug
# build; that is fine, a debug bitstream is for hardware bring-up, not release.
# ---------------------------------------------------------------------------
if {$debug} {
    open_run synth_1
    file delete -force debug_constraints.xdc   ;# debug.tcl save_constraints_as wont overwrite
    source debug.tcl                    ;# scans mark_debug nets; writes debug_nets.ltx
    opt_design
    place_design
    phys_opt_design
    route_design
    file mkdir [file dirname $bit]
    write_bitstream -force $bit
    write_debug_probes -force [file rootname $bit].ltx
    foreach g [signoff_gates] { puts "GATE $board: $g" }   ;# informational only for debug
    puts "RESULT $board OK-DEBUG bit=$bit probes=[file rootname $bit].ltx"
    close_project
    exit 0
}

# ---------------------------------------------------------------------------
# Release build: pure project mode; impl_1 applies the .xpr strategy and writes
# the bitstream to the location make_release.py / load_bitstream.sh expect.
# ---------------------------------------------------------------------------
launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    puts "RESULT $board FAILED impl_1: [get_property STATUS [get_runs impl_1]]"
    exit 1
}

set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
if {$wns eq "" || $whs eq "" || $wns < 0 || $whs < 0} {
    puts "RESULT $board TIMING-FAILED WNS=$wns WHS=$whs"
    exit 2
}

open_run impl_1
set gate [signoff_gates]
if {[llength $gate] > 0} {
    foreach g $gate { puts "GATE $board: $g" }
    puts "RESULT $board SIGNOFF-FAILED WNS=$wns WHS=$whs"
    exit 3
}

puts "RESULT $board OK WNS=$wns WHS=$whs bit=$bit"
close_project
