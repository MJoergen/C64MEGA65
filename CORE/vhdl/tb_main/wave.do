onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/mode
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/bcd_en
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/res_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/enable
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/clk
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/rdy
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/abort_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/irq_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/nmi_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/so_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/r_w_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/sync
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/a
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/din
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/dout
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/debug
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/nmi_ack
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/clk
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/reset
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cfg
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_req
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_cycle
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_cycle
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_cs
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_cs
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/irq
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/ff00_wr
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/stage
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_cur
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_dev
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_dat
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_act
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/dma_we_r
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/addr_ram
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/addr_ram_r
add wave -noupdate -group main /tb_main/main_inst/clk_main_i
add wave -noupdate -group main /tb_main/main_inst/reset_soft_i
add wave -noupdate -group main /tb_main/main_inst/reset_hard_i
add wave -noupdate -group main /tb_main/main_inst/pause_i
add wave -noupdate -group main /tb_main/main_inst/trigger_run_i
add wave -noupdate -group main /tb_main/main_inst/c64_rom_i
add wave -noupdate -group main /tb_main/main_inst/c64_ntsc_i
add wave -noupdate -group main /tb_main/main_inst/clk_main_speed_i
add wave -noupdate -group main /tb_main/main_inst/video_retro15khz_i
add wave -noupdate -group main /tb_main/main_inst/c64_sid_ver_i
add wave -noupdate -group main /tb_main/main_inst/c64_sid_port_i
add wave -noupdate -group main /tb_main/main_inst/c64_cia_ver_i
add wave -noupdate -group main /tb_main/main_inst/c64_exp_port_mode_i
add wave -noupdate -group main /tb_main/main_inst/kb_key_num_i
add wave -noupdate -group main /tb_main/main_inst/kb_key_pressed_n_i
add wave -noupdate -group main /tb_main/main_inst/drive_led_o
add wave -noupdate -group main /tb_main/main_inst/drive_led_col_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_addr_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_data_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_we_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/c64_clk_sd_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_addr_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_data_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_data_o
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_ce_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_we_i
add wave -noupdate -group main /tb_main/main_inst/avm_waitrequest_i
add wave -noupdate -group main /tb_main/main_inst/avm_write_o
add wave -noupdate -group main /tb_main/main_inst/avm_read_o
add wave -noupdate -group main /tb_main/main_inst/avm_address_o
add wave -noupdate -group main /tb_main/main_inst/avm_writedata_o
add wave -noupdate -group main /tb_main/main_inst/avm_byteenable_o
add wave -noupdate -group main /tb_main/main_inst/avm_burstcount_o
add wave -noupdate -group main /tb_main/main_inst/avm_readdata_i
add wave -noupdate -group main /tb_main/main_inst/avm_readdatavalid_i
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_pause
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_drive_led
add wave -noupdate -group main -group Internal /tb_main/main_inst/cia1_pa_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/cia1_pa_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/cia1_pb_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/cia1_pb_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_ram_ce
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_ram_we
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_ram_data
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_sid_l
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_sid_r
add wave -noupdate -group main -group Internal /tb_main/main_inst/alo
add wave -noupdate -group main -group Internal /tb_main/main_inst/aro
add wave -noupdate -group main -group Internal /tb_main/main_inst/restore_key_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_iec_clk_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_iec_clk_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_iec_atn_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_iec_data_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/c64_iec_data_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/hw_iec_clk_n_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/hw_iec_data_n_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_drive_ce
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_dce_sum
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_img_mounted
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_img_readonly
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_img_size
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_img_type
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_drives_reset
add wave -noupdate -group main -group Internal /tb_main/main_inst/vdrives_mounted
add wave -noupdate -group main -group Internal /tb_main/main_inst/cache_dirty
add wave -noupdate -group main -group Internal /tb_main/main_inst/prevent_reset
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_lba
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_blk_cnt
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_rd
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_wr
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_ack
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_buf_addr
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_buf_data_in
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_buf_data_out
add wave -noupdate -group main -group Internal /tb_main/main_inst/iec_sd_buf_wr
add wave -noupdate -group main -group Internal /tb_main/main_inst/reset_core_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/reset_core_int_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/hard_reset_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/hard_rst_counter
add wave -noupdate -group main -group Internal /tb_main/main_inst/hard_reset_n_d
add wave -noupdate -group main -group Internal /tb_main/main_inst/cold_start_done
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_roml
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_romh
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_ioe
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_iof
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_nmi_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_nmi_ack
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_ba
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_irq_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_dma
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_exrom_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_game_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_umax_romh
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_umax_unmapped
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_io_rom
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_io_ext
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_io_data
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_dotclk
add wave -noupdate -group main -group Internal /tb_main/main_inst/core_phi2
add wave -noupdate -group main -group Internal /tb_main/main_inst/cartridge_bank_raddr
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_roml_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_romh_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_io1_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_io2_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_nmi_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_irq_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_dma_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_exrom_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_game_n
add wave -noupdate -group main -group Internal /tb_main/main_inst/data_from_cart
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_reset_counter
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_res_flckr_ign
add wave -noupdate -group main -group Internal /tb_main/main_inst/cart_is_an_ef3
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_cfg
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_req
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_cycle
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_addr
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_dout
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_din
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dma_we
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_irq
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_iof
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_oe
add wave -noupdate -group main -group Internal /tb_main/main_inst/reu_dout
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_io_rom
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_io_ext
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_io_data
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_exrom
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_game
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_nmi
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_ioe_wr_ena
add wave -noupdate -group main -group Internal /tb_main/main_inst/crt_iof_wr_ena
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_ext_cycle
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_cycle
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_addr
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_dout
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_din
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_we
add wave -noupdate -group main -group Internal /tb_main/main_inst/sim_reu_cs
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_write
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_read
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_address
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_writedata
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_byteenable
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_burstcount
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_readdata
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_readdatavalid
add wave -noupdate -group main -group Internal /tb_main/main_inst/map_waitrequest
add wave -noupdate -group main -group Internal /tb_main/main_inst/cass_write
add wave -noupdate -group main -group Internal /tb_main/main_inst/cass_motor
add wave -noupdate -group main -group Internal /tb_main/main_inst/cass_rtc
add wave -noupdate -group main -group Internal /tb_main/main_inst/rtcf83_sda
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/clk32
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/clk32_speed
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/reset_n
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/bios
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pause
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pause_out
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pa_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pa_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pb_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pb_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ramAddr
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ramDin
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ramDout
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ramCE
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ramWE
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/io_cycle
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ext_cycle
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/refresh
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cia_mode
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/turbo_mode
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/turbo_speed
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ntscMode
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/hsync
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/vsync
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/r
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/g
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/b
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/game
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/exrom
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/io_rom
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/io_ext
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/io_data
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/irq_n
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/nmi_n
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/nmi_ack
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/ba
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/romL
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/romH
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/UMAXromH
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/UMAXnomap
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/IOE
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/IOF
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dotclk
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/phi0
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/phi2
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_req
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_cycle
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_addr
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_dout
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_din
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/dma_we
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/irq_ext_n
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pb_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pb_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pa2_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pa2_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/pc2_n_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/flag2_n_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/sp2_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/sp2_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/sp1_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/sp1_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cnt2_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cnt2_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cnt1_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/cnt1_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/iec_data_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/iec_data_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/iec_clk_o
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/iec_clk_i
add wave -noupdate -expand -group fpga_sid_iec /tb_main/main_inst/fpga64_sid_iec_inst/iec_atn_o
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/sysCycle
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/preCycle
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/sysEnable
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/rfsh_cycle
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/dma_active
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/phi0_cpu
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuHasBus
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/baLoc
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/ba_dma
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/aec
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enableCpu
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enableVic
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enablePixel
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enableSid
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/irq_cia1
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/irq_cia2
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/irq_vic
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/systemWe
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/pulseWr_io
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/systemAddr
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_vic
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_sid
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_color
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_cia1
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_cia2
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cs_ram
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuWe
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuWe_pre
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuAddr
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuAddr_pre
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuDi
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuDo
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuDo_pre
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuIO
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/io_data_i
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/ioe_i
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/iof_i
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/io_enable
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu_cyc
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu_cyc_s
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/turbo_m
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/reset
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enableCia_p
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/enableCia_n
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia1Do
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2Do
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pao
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia1_pbo
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2_pai
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2_pao
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2_pbi
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2_pbo
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cia2_pbe
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/todclk
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicColorIndex
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicBus
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicDi
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicDiAec
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicAddr
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicData
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/lastVicDi
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vicAddr1514
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/colorData
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/colorDataAec
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/turbo_en
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/turbo_state
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic_debugx
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic_debugy
add wave -noupdate -expand -group fpga_sid_iec -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpuSync
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {1024000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 198
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ps} {497421926400 ps}
