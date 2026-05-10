# FC3 101% / R3 ILA waveform helper.
#
# Usage in Vivado Hardware Manager:
#   1. Program the R3 bitstream with the matching .ltx probes file.
#   2. Run an ILA capture.
#   3. In the Tcl Console:
#        source CORE/fc3_ila_wave_setup.tcl
#        fc3_ila_wave_setup
#
# This creates a labeled waveform view for the debug taps in main.vhd.
# It does not rename the underlying hardware probes used in the trigger setup.

namespace eval fc3_ila {
  variable script_dir [file dirname [file normalize [info script]]]
  variable wave_path_candidates {
    {CORE/i_main}
    {/CORE/i_main}
  }

  proc add_divider {name} {
    catch {add_wave_divider $name}
  }

  proc add_named_wave {display_name suffix {radix default}} {
    variable wave_path_candidates

    foreach base $wave_path_candidates {
      set item "${base}/${suffix}"
      if {![catch {add_wave -quiet -name $display_name -radix $radix $item} result]} {
        foreach wave $result {
          catch {set_property label $display_name $wave}
          catch {set_property DisplayName label $wave}
          catch {set_property ElementShortName $display_name $wave}
          catch {set_property ObjectShortName $display_name $wave}
        }
        return $result
      }
    }

    puts "FC3 ILA: could not add wave '${display_name}' from '${suffix}'"
    return {}
  }

  proc add_flag_bit {display_name vector bit} {
    add_named_wave $display_name "${vector}\[${bit}\]" bin
  }

  proc display_latest_capture {} {
    set datas [get_hw_ila_datas -quiet]
    if {[llength $datas] == 0} {
      set ilas [get_hw_ilas -quiet]
      if {[llength $ilas] == 0} {
        error "No hw_ila found. Open Hardware Manager and program the device first."
      }

      set ila [lindex $ilas 0]
      puts "FC3 ILA: no uploaded capture found; uploading from ${ila}"
      set data [upload_hw_ila_data $ila]
    } else {
      set data [lindex $datas end]
    }

    display_hw_ila_data $data
  }

  proc clear_wave_window {} {
    set waves [get_waves -quiet *]
    if {[llength $waves] == 0} {
      return
    }

    if {[catch {remove_wave -quiet $waves} error_message]} {
      puts "FC3 ILA: could not clear default wave rows: ${error_message}"
      puts "FC3 ILA: labeled waves will be appended below Vivado's default probe list."
    }
  }
}

proc fc3_ila_wave_setup {} {
  fc3_ila::display_latest_capture
  fc3_ila::clear_wave_window

  fc3_ila::add_divider "FC3 quick view"
  fc3_ila::add_named_wave "C64_ADDR"              {dbg_fc3_c64_addr[15:0]}       hex
  fc3_ila::add_named_wave "CPU_SEES_DATA"         {dbg_fc3_c64_data_mux[7:0]}    hex
  fc3_ila::add_named_wave "DATA_FROM_CART"        {dbg_fc3_data_from_cart[7:0]}  hex
  fc3_ila::add_named_wave "CPU_WRITE_DATA"        {dbg_fc3_c64_data_out[7:0]}    hex
  fc3_ila::add_flag_bit "C64_RW_WRITE"            dbg_fc3_core_flags 9
  fc3_ila::add_flag_bit "CORE_PHI2"               dbg_fc3_core_flags 11
  fc3_ila::add_flag_bit "CORE_ROML"               dbg_fc3_core_flags 14
  fc3_ila::add_flag_bit "CORE_ROMH"               dbg_fc3_core_flags 15
  fc3_ila::add_flag_bit "CORE_GAME_N"             dbg_fc3_core_flags 18
  fc3_ila::add_flag_bit "CORE_EXROM_N"            dbg_fc3_core_flags 19
  fc3_ila::add_flag_bit "CART_RESET_I"            dbg_fc3_cart_flags 0
  fc3_ila::add_flag_bit "CART_RESET_O"            dbg_fc3_cart_flags 1
  fc3_ila::add_flag_bit "CART_RESET_OE"           dbg_fc3_cart_flags 2
  fc3_ila::add_flag_bit "CART_GAME_N"             dbg_fc3_cart_flags 8
  fc3_ila::add_flag_bit "CART_EXROM_N"            dbg_fc3_cart_flags 9
  fc3_ila::add_flag_bit "CART_NMI_N"              dbg_fc3_cart_flags 10
  fc3_ila::add_flag_bit "CART_ROML_N"             dbg_fc3_cart_flags 13
  fc3_ila::add_flag_bit "CART_ROMH_N"             dbg_fc3_cart_flags 14
  fc3_ila::add_flag_bit "CART_IO1_N"              dbg_fc3_cart_flags 15
  fc3_ila::add_flag_bit "CART_IO2_N"              dbg_fc3_cart_flags 16

  fc3_ila::add_divider "FC3 CPU bus"
  fc3_ila::add_named_wave "C64_ADDR"              {dbg_fc3_c64_addr[15:0]}       hex
  fc3_ila::add_named_wave "CPU_WRITE_DATA"        {dbg_fc3_c64_data_out[7:0]}    hex
  fc3_ila::add_named_wave "RAW_RAM_DATA_IN"       {dbg_fc3_c64_data_in[7:0]}     hex
  fc3_ila::add_named_wave "CPU_SEES_DATA"         {dbg_fc3_c64_data_mux[7:0]}    hex
  fc3_ila::add_named_wave "DATA_FROM_CART"        {dbg_fc3_data_from_cart[7:0]}  hex
  fc3_ila::add_named_wave "CART_ADDR_PRE"         {dbg_fc3_cart_addr_pre[15:0]}  hex
  fc3_ila::add_named_wave "CART_ADDR_Q"           {dbg_fc3_cart_addr_q[15:0]}    hex
  fc3_ila::add_named_wave "CART_DATA_IN"          {dbg_fc3_cart_data_in[7:0]}    hex
  fc3_ila::add_named_wave "CART_DATA_OUT"         {dbg_fc3_cart_data_out[7:0]}   hex

  fc3_ila::add_divider "FC3 address decode"
  fc3_ila::add_flag_bit "ADDR_8000_BFFF"          dbg_fc3_addr_decode 0
  fc3_ila::add_flag_bit "ADDR_8000"               dbg_fc3_addr_decode 1
  fc3_ila::add_flag_bit "ADDR_8003"               dbg_fc3_addr_decode 2
  fc3_ila::add_flag_bit "ADDR_9E00"               dbg_fc3_addr_decode 3
  fc3_ila::add_flag_bit "ADDR_DE00"               dbg_fc3_addr_decode 4
  fc3_ila::add_flag_bit "ADDR_DFFF"               dbg_fc3_addr_decode 5
  fc3_ila::add_flag_bit "ADDR_DE00_DFFF"          dbg_fc3_addr_decode 6
  fc3_ila::add_flag_bit "ADDR_DF00_DFFF"          dbg_fc3_addr_decode 7

  fc3_ila::add_divider "FC3 core flags"
  fc3_ila::add_flag_bit "RESET_SOFT"              dbg_fc3_core_flags 0
  fc3_ila::add_flag_bit "RESET_HARD"              dbg_fc3_core_flags 1
  fc3_ila::add_flag_bit "RESET_CORE_INT_N"        dbg_fc3_core_flags 2
  fc3_ila::add_flag_bit "RESET_CORE_N"            dbg_fc3_core_flags 3
  fc3_ila::add_flag_bit "HARD_RESET_N"            dbg_fc3_core_flags 4
  fc3_ila::add_flag_bit "COLD_START_DONE"         dbg_fc3_core_flags 5
  fc3_ila::add_flag_bit "PREVENT_RESET"           dbg_fc3_core_flags 6
  fc3_ila::add_flag_bit "PHYSICAL_CART_MODE"      dbg_fc3_core_flags 7
  fc3_ila::add_flag_bit "SIM_REU_MODE"            dbg_fc3_core_flags 8
  fc3_ila::add_flag_bit "C64_RW_WRITE"            dbg_fc3_core_flags 9
  fc3_ila::add_flag_bit "C64_RAM_CE"              dbg_fc3_core_flags 10
  fc3_ila::add_flag_bit "CORE_PHI2"               dbg_fc3_core_flags 11
  fc3_ila::add_flag_bit "CORE_DOTCLK"             dbg_fc3_core_flags 12
  fc3_ila::add_flag_bit "CORE_BA"                 dbg_fc3_core_flags 13
  fc3_ila::add_flag_bit "CORE_ROML"               dbg_fc3_core_flags 14
  fc3_ila::add_flag_bit "CORE_ROMH"               dbg_fc3_core_flags 15
  fc3_ila::add_flag_bit "CORE_IO1_DE"             dbg_fc3_core_flags 16
  fc3_ila::add_flag_bit "CORE_IO2_DF"             dbg_fc3_core_flags 17
  fc3_ila::add_flag_bit "CORE_GAME_N"             dbg_fc3_core_flags 18
  fc3_ila::add_flag_bit "CORE_EXROM_N"            dbg_fc3_core_flags 19
  fc3_ila::add_flag_bit "CORE_NMI_N"              dbg_fc3_core_flags 20
  fc3_ila::add_flag_bit "CORE_IRQ_N"              dbg_fc3_core_flags 21
  fc3_ila::add_flag_bit "CORE_DMA"                dbg_fc3_core_flags 22
  fc3_ila::add_flag_bit "CORE_UMAX_ROMH"          dbg_fc3_core_flags 23
  fc3_ila::add_flag_bit "CORE_UMAX_UNMAPPED"      dbg_fc3_core_flags 24
  fc3_ila::add_flag_bit "CART_IS_EF3"             dbg_fc3_core_flags 25
  fc3_ila::add_flag_bit "PAUSE_I"                 dbg_fc3_core_flags 26
  fc3_ila::add_flag_bit "C64_PAUSE"               dbg_fc3_core_flags 27
  fc3_ila::add_flag_bit "CARTRIDGE_LOADING"       dbg_fc3_core_flags 28
  fc3_ila::add_flag_bit "CRT_BANK_WAIT"           dbg_fc3_core_flags 29
  fc3_ila::add_flag_bit "CORE_IO_ROM"             dbg_fc3_core_flags 30
  fc3_ila::add_flag_bit "CORE_IO_EXT"             dbg_fc3_core_flags 31

  fc3_ila::add_divider "FC3 cartridge port flags"
  fc3_ila::add_flag_bit "CART_RESET_I"            dbg_fc3_cart_flags 0
  fc3_ila::add_flag_bit "CART_RESET_O"            dbg_fc3_cart_flags 1
  fc3_ila::add_flag_bit "CART_RESET_OE"           dbg_fc3_cart_flags 2
  fc3_ila::add_flag_bit "CART_GAME_I_RAW"         dbg_fc3_cart_flags 3
  fc3_ila::add_flag_bit "CART_EXROM_I_RAW"        dbg_fc3_cart_flags 4
  fc3_ila::add_flag_bit "CART_NMI_I_RAW"          dbg_fc3_cart_flags 5
  fc3_ila::add_flag_bit "CART_IRQ_I_RAW"          dbg_fc3_cart_flags 6
  fc3_ila::add_flag_bit "CART_DMA_I_RAW"          dbg_fc3_cart_flags 7
  fc3_ila::add_flag_bit "CART_GAME_N"             dbg_fc3_cart_flags 8
  fc3_ila::add_flag_bit "CART_EXROM_N"            dbg_fc3_cart_flags 9
  fc3_ila::add_flag_bit "CART_NMI_N"              dbg_fc3_cart_flags 10
  fc3_ila::add_flag_bit "CART_IRQ_N"              dbg_fc3_cart_flags 11
  fc3_ila::add_flag_bit "CART_DMA_N"              dbg_fc3_cart_flags 12
  fc3_ila::add_flag_bit "CART_ROML_N"             dbg_fc3_cart_flags 13
  fc3_ila::add_flag_bit "CART_ROMH_N"             dbg_fc3_cart_flags 14
  fc3_ila::add_flag_bit "CART_IO1_N"              dbg_fc3_cart_flags 15
  fc3_ila::add_flag_bit "CART_IO2_N"              dbg_fc3_cart_flags 16
  fc3_ila::add_flag_bit "CART_ROML_Q"             dbg_fc3_cart_flags 17
  fc3_ila::add_flag_bit "CART_ROMH_Q"             dbg_fc3_cart_flags 18
  fc3_ila::add_flag_bit "CART_IO1_Q"              dbg_fc3_cart_flags 19
  fc3_ila::add_flag_bit "CART_IO2_Q"              dbg_fc3_cart_flags 20
  fc3_ila::add_flag_bit "CART_RW_Q"               dbg_fc3_cart_flags 21
  fc3_ila::add_flag_bit "CART_DATA_OE"            dbg_fc3_cart_flags 22
  fc3_ila::add_flag_bit "CART_ADDR_OE"            dbg_fc3_cart_flags 23
  fc3_ila::add_flag_bit "CART_CTRL_OE"            dbg_fc3_cart_flags 24
  fc3_ila::add_flag_bit "CART_EN"                 dbg_fc3_cart_flags 25
  fc3_ila::add_flag_bit "CART_PHI2"               dbg_fc3_cart_flags 26
  fc3_ila::add_flag_bit "CART_BA"                 dbg_fc3_cart_flags 27
  fc3_ila::add_flag_bit "CART_DOTCLOCK"           dbg_fc3_cart_flags 28
  fc3_ila::add_flag_bit "CART_RESET_TAIL_ACTIVE"  dbg_fc3_cart_flags 29
  fc3_ila::add_flag_bit "CART_ROML_I_RAW"         dbg_fc3_cart_flags 30
  fc3_ila::add_flag_bit "CART_ROMH_I_RAW"         dbg_fc3_cart_flags 31

  fc3_ila::add_divider "FC3 reset helper"
  fc3_ila::add_named_wave "RESET_COUNTER"         {dbg_fc3_reset_counter[3:0]} hex
  fc3_ila::add_named_wave "RESET_TAIL"            {dbg_fc3_reset_tail[1:0]}    hex

  set wcfg_path [file join $fc3_ila::script_dir fc3_ila_wave.wcfg]
  catch {save_wave_config $wcfg_path}
  puts "FC3 ILA: waveform setup complete. If Vivado accepted the bit slices, ${wcfg_path} was saved."
}
