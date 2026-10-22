## Commodore 64 for MEGA65 (C64MEGA65)
##
## MEGA65 port done by MJoergen and sy2002 in 2023 and licensed under GPL v3

## The core clock main_clk is one of four MMCM outputs (CORE/vhdl/clk.vhd), selected at run time by
## the two bits of hr_core_speed (CORE/vhdl/mega65.vhd) through a two-level BUFGCTRL tree:
##    00 = PAL original      31.527778 MHz  31.718 ns   i_clk_c64_orig
##    01 = PAL flicker-free  31.448993 MHz  31.798 ns   i_clk_c64_slow
##    10 = NTSC original     32.727273 MHz  30.556 ns   i_clk_c64_ntsc
##    11 = NTSC flicker-free 32.789700 MHz  30.497 ns   i_clk_c64_ntsc_ff
## Time the core at its fastest clock (NTSC flicker-free, 32.789700 MHz). All four core
## clocks share the post-mux clock tree, so this covers the three slower ones as well.
## Forcing both select bits to 1 lets only i_clk_c64_ntsc_ff reach any sequential element,
## so no set_clock_groups and no additional false paths are needed. Keep the name main_clk:
## the constraints below and the [get_generated_clocks] rules in M2M/common.xdc rely on it.
## CORE/signoff_gates.tcl checks the two pins, the source pin and the period.
set_case_analysis 1 [get_pins CORE/hr_core_speed_reg[0]/Q]
set_case_analysis 1 [get_pins CORE/hr_core_speed_reg[1]/Q]

create_generated_clock -name main_clk [get_pins CORE/clk_gen/i_clk_c64_ntsc_ff/CLKOUT0]

## CDC in IEC drives, handled manually in the source code
set_false_path -from [get_pins -hier id1_reg[*]/C]
set_false_path -from [get_pins -hier id2_reg[*]/C]
## Scope the c1541_track 'busy' CDC exception to its real instance. The unscoped
## '-hier busy_reg/C' used to be unambiguous, but enabling the 1581 pulls fdc1772.v
## into the design, which has its own same-clock (clkcpu) 'busy' register -- the
## wildcard would otherwise silently exempt that legitimate timing path from analysis.
set_false_path -from [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/busy_reg/C]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/reset_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/change_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/save_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/track_sync/s1_reg[*]/D]

## Disk type register that moves very slow (on each (re-)mount) and that is initialized with very stable signals
set_false_path -from [get_pins CORE/i_main/iec_drive_inst/dtype_reg[*][*]/C]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/dtype_reg[*][*]/D]

## CDC in the simulated 1581 (D81), handled manually in fdc1772.v (mirror of the c1541
## c1541_track rework). The fdc1772 SD-request FSM and FIFO SD-port run on clk_sys (QNICE)
## while the WD1772/drive run on clkcpu (main); these synchronizers bridge the two domains:
##   sd_rdreq_sync / sd_wrreq_sync : clkcpu request toggles  -> clk_sys (launch transfer)
##   sd_frst_sync                  : clkcpu floppy_reset      -> clk_sys (SD-FSM reset)
##   sd_done_sync                  : clk_sys completion toggle -> clkcpu (release sd_io_idle gate)
set_false_path -to [get_pins CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_rdreq_sync/s1_reg[*]/D]
set_false_path -to [get_pins CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_wrreq_sync/s1_reg[*]/D]
set_false_path -to [get_pins CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_frst_sync/s1_reg[*]/D]
set_false_path -to [get_pins CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_done_sync/s1_reg[*]/D]

## sd_lba is latched into clk_sys at the start of each SD transfer from the quasi-static
## (clkcpu) track/sector geometry, which is stable long before the request fires.
set_false_path -to [get_pins CORE/i_main/iec_drive_inst/c1581/drives[*].c1581_drv/fdc/sd_lba_reg[*]/D]

## CDC between the two asynchronous system clocks (physical internal 1581, issue #90).
## The physical_1581 controller / read-FIFO / diag device run on qnice_clk (50 MHz) while
## the WD1772 + drive logic run on main_clk (31.4 to 32.8 MHz). Every crossing is explicitly
## synchronized in the source: iecdrv_sync 2-FF chains, toggle handshakes whose payload is
## stable before the toggle flips, Gray-coded FIFO pointers (physical_1581_rdfifo), and
## async_reg-tagged 2-FF pairs. Cut the clock pair in both directions -- the same idiom
## M2M/common.xdc uses for qnice_clk -> hdmi_clk. This subsumes the granular drive-CDC
## exceptions above. NOTE: a clock-to-clock false path can never exempt a SAME-clock path,
## so the fdc1772 same-clock 'busy' hazard documented at the top of this file is unaffected.
set_false_path -from [get_clocks qnice_clk] -to [get_clocks main_clk]
set_false_path -from [get_clocks main_clk]  -to [get_clocks qnice_clk]

