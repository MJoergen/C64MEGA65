onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group reu /tb_reu/reu_inst/clk
add wave -noupdate -group reu /tb_reu/reu_inst/reset
add wave -noupdate -group reu /tb_reu/reu_inst/cfg
add wave -noupdate -group reu /tb_reu/reu_inst/dma_req
add wave -noupdate -group reu /tb_reu/reu_inst/dma_cycle
add wave -noupdate -group reu /tb_reu/reu_inst/dma_addr
add wave -noupdate -group reu /tb_reu/reu_inst/dma_dout
add wave -noupdate -group reu /tb_reu/reu_inst/dma_din
add wave -noupdate -group reu /tb_reu/reu_inst/dma_we
add wave -noupdate -group reu /tb_reu/reu_inst/ram_cycle
add wave -noupdate -group reu /tb_reu/reu_inst/ram_addr
add wave -noupdate -group reu /tb_reu/reu_inst/ram_dout
add wave -noupdate -group reu /tb_reu/reu_inst/ram_din
add wave -noupdate -group reu /tb_reu/reu_inst/ram_we
add wave -noupdate -group reu /tb_reu/reu_inst/ram_cs
add wave -noupdate -group reu /tb_reu/reu_inst/cpu_addr
add wave -noupdate -group reu /tb_reu/reu_inst/cpu_dout
add wave -noupdate -group reu /tb_reu/reu_inst/cpu_din
add wave -noupdate -group reu /tb_reu/reu_inst/cpu_we
add wave -noupdate -group reu /tb_reu/reu_inst/cpu_cs
add wave -noupdate -group reu /tb_reu/reu_inst/irq
add wave -noupdate -group reu /tb_reu/reu_inst/ff00_wr
add wave -noupdate -group reu /tb_reu/reu_inst/op
add wave -noupdate -group reu /tb_reu/reu_inst/stage
add wave -noupdate -group reu /tb_reu/reu_inst/op_cur
add wave -noupdate -group reu /tb_reu/reu_inst/op_dev
add wave -noupdate -group reu /tb_reu/reu_inst/op_dat
add wave -noupdate -group reu /tb_reu/reu_inst/op_act
add wave -noupdate -group reu /tb_reu/reu_inst/dma_we_r
add wave -noupdate -group reu /tb_reu/reu_inst/addr_ram
add wave -noupdate -group reu /tb_reu/reu_inst/addr_ram_r
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/clk_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/rst_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_ext_cycle_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_ext_cycle_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_addr_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_dout_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_din_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_we_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/reu_cs_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_write_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_read_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_address_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_writedata_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_byteenable_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_burstcount_o
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_readdata_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_readdatavalid_i
add wave -noupdate -group reu_mapper /tb_reu/reu_mapper_inst/avm_waitrequest_i
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/reu_addr_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_preemptive_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_preemptive_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_preemptive_block
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/reu_cs_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_valid_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_write_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_read_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_address_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_writedata_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_byteenable_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_burstcount_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_write_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_read_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_address_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_writedata_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_byteenable_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/avm_burstcount_r
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/reu_ext_cycle_d
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/reu_rd_fifo_ready
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/reu_rd_fifo_valid
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/active_s
add wave -noupdate -group reu_mapper -expand -group Internal /tb_reu/reu_mapper_inst/active
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/clk_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/rst_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_waitrequest_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_write_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_read_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_address_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_writedata_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_byteenable_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_burstcount_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_readdata_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/s_avm_readdatavalid_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_waitrequest_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_write_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_read_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_address_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_writedata_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_byteenable_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_burstcount_o
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_readdata_i
add wave -noupdate -group avm_cache /tb_reu/avm_cache_inst/m_avm_readdatavalid_i
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_data
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_addr
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_count
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/rd_burstcount
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/state
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_offset_s
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_rd_hit_s
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_wr_hit_s
add wave -noupdate -group avm_cache -group Internal /tb_reu/avm_cache_inst/cache_filled_s
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/clk_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/clk_del_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/delay_refclk_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/rst_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_write_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_read_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_address_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_writedata_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_byteenable_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_burstcount_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_readdata_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_readdatavalid_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/avm_waitrequest_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/count_long_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/count_short_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_resetn_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_csn_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_ck_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_rwds_in_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_rwds_out_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_rwds_oe_n_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_dq_in_i
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_dq_out_o
add wave -noupdate -expand -group hyperram /tb_reu/hyperram_inst/hr_dq_oe_n_o
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_write
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_read
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_address
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_writedata
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_byteenable
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_burstcount
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_readdata
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_readdatavalid
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/errata_waitrequest
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_write
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_read
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_address
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_writedata
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_byteenable
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_burstcount
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_readdata
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_readdatavalid
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/cfg_waitrequest
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_rstn
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_csn
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_ck_ddr
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_dq_ddr_in
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_dq_ddr_out
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_dq_oe
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_dq_ie
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_rwds_ddr_out
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_rwds_oe
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_rwds_in
add wave -noupdate -expand -group hyperram -group Internal /tb_reu/hyperram_inst/ctrl_read
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
