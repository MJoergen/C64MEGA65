onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group reu /tb_reu/i_reu/clk
add wave -noupdate -group reu /tb_reu/i_reu/reset
add wave -noupdate -group reu /tb_reu/i_reu/cfg
add wave -noupdate -group reu /tb_reu/i_reu/dma_req
add wave -noupdate -group reu /tb_reu/i_reu/dma_cycle
add wave -noupdate -group reu /tb_reu/i_reu/dma_addr
add wave -noupdate -group reu /tb_reu/i_reu/dma_dout
add wave -noupdate -group reu /tb_reu/i_reu/dma_din
add wave -noupdate -group reu /tb_reu/i_reu/dma_we
add wave -noupdate -group reu /tb_reu/i_reu/ram_cycle
add wave -noupdate -group reu /tb_reu/i_reu/ram_addr
add wave -noupdate -group reu /tb_reu/i_reu/ram_dout
add wave -noupdate -group reu /tb_reu/i_reu/ram_din
add wave -noupdate -group reu /tb_reu/i_reu/ram_we
add wave -noupdate -group reu /tb_reu/i_reu/ram_cs
add wave -noupdate -group reu /tb_reu/i_reu/cpu_addr
add wave -noupdate -group reu /tb_reu/i_reu/cpu_dout
add wave -noupdate -group reu /tb_reu/i_reu/cpu_din
add wave -noupdate -group reu /tb_reu/i_reu/cpu_we
add wave -noupdate -group reu /tb_reu/i_reu/cpu_cs
add wave -noupdate -group reu /tb_reu/i_reu/irq
add wave -noupdate -group reu /tb_reu/i_reu/ff00_wr
add wave -noupdate -group reu /tb_reu/i_reu/op
add wave -noupdate -group reu /tb_reu/i_reu/stage
add wave -noupdate -group reu /tb_reu/i_reu/op_cur
add wave -noupdate -group reu /tb_reu/i_reu/op_dev
add wave -noupdate -group reu /tb_reu/i_reu/op_dat
add wave -noupdate -group reu /tb_reu/i_reu/op_act
add wave -noupdate -group reu /tb_reu/i_reu/dma_we_r
add wave -noupdate -group reu /tb_reu/i_reu/addr_ram
add wave -noupdate -group reu /tb_reu/i_reu/addr_ram_r
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/clk_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/rst_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_ext_cycle_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_ext_cycle_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_addr_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_dout_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_din_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_we_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/reu_cs_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_write_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_read_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_address_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_writedata_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_byteenable_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_burstcount_o
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_readdata_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_readdatavalid_i
add wave -noupdate -group reu_mapper /tb_reu/i_reu_mapper/avm_waitrequest_i
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/reu_addr_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_preemptive_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_preemptive_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_preemptive_block
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/reu_cs_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_valid_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_write_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_read_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_address_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_writedata_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_byteenable_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_burstcount_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_write_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_read_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_address_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_writedata_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_byteenable_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/avm_burstcount_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/reu_ext_cycle_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/reu_rd_fifo_ready
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/reu_rd_fifo_valid
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/active_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/i_reu_mapper/active
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/clk_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/rst_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_waitrequest_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_write_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_read_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_address_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_writedata_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_byteenable_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_burstcount_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_readdata_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/s_avm_readdatavalid_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_waitrequest_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_write_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_read_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_address_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_writedata_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_byteenable_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_burstcount_o
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_readdata_i
add wave -noupdate -expand -group avm_cache /tb_reu/i_avm_cache/m_avm_readdatavalid_i
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_data
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_addr
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_count
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/rd_burstcount
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/state
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_offset_s
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_rd_hit_s
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_wr_hit_s
add wave -noupdate -expand -group avm_cache -group Internal /tb_reu/i_avm_cache/cache_filled_s
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {39203239 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 216
configure wave -valuecolwidth 132
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
WaveRestoreZoom {0 ps} {73500 ns}
