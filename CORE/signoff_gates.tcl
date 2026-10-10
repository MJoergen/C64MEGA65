# CORE.xdc sign-off gates, shared by build_bitstream.tcl and
# reroll_bitstream.tcl so that a first-pass bitstream and a re-rolled one are
# checked against exactly the same list.
#
# signoff_gates returns a list of human-readable problems with the constraints
# as actually applied to the currently-open design; an empty list means every
# gate passed. Each check mirrors a CORE.xdc line that turns into a silent
# no-op if the object it names has been renamed. When you add or rename
# hierarchy that CORE.xdc references, update this list in the same commit.

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
