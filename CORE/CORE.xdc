## Commodore 64 for MEGA65 (C64MEGA65)
##
## MEGA65 port done by MJoergen and sy2002 in 2023 and licensed under GPL v3

## Assume the core is running at the original (slightly faster) clock.
## This halves the number of set_false_path needed.
set_case_analysis 0 [get_pins CORE/hr_core_speed_reg[0]/Q]

create_generated_clock -name main_clk [get_pins CORE/clk_gen/i_clk_c64_orig/CLKOUT0]

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

