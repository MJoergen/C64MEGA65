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
set_false_path -from [get_pins -hier busy_reg/C]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/reset_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/change_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/save_sync/s1_reg[*]/D]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/c1541/drives[*].c1541_drv/c1541_track/track_sync/s1_reg[*]/D]

## Disk type register that moves very slow (on each (re-)mount) and that is initialized with very stable signals
set_false_path -from [get_pins CORE/i_main/iec_drive_inst/dtype_reg[*][*]/C]
set_false_path -to   [get_pins CORE/i_main/iec_drive_inst/dtype_reg[*][*]/D]

