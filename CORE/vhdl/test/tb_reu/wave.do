onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group reu /tb_reu/i_reu/clk
add wave -noupdate -expand -group reu /tb_reu/i_reu/reset
add wave -noupdate -expand -group reu /tb_reu/i_reu/cfg
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_req
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_cycle
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_addr
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_dout
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_din
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_we
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_cycle
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_addr
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_dout
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_din
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_we
add wave -noupdate -expand -group reu /tb_reu/i_reu/ram_cs
add wave -noupdate -expand -group reu /tb_reu/i_reu/cpu_addr
add wave -noupdate -expand -group reu /tb_reu/i_reu/cpu_dout
add wave -noupdate -expand -group reu /tb_reu/i_reu/cpu_din
add wave -noupdate -expand -group reu /tb_reu/i_reu/cpu_we
add wave -noupdate -expand -group reu /tb_reu/i_reu/cpu_cs
add wave -noupdate -expand -group reu /tb_reu/i_reu/irq
add wave -noupdate -expand -group reu /tb_reu/i_reu/ff00_wr
add wave -noupdate -expand -group reu /tb_reu/i_reu/op
add wave -noupdate -expand -group reu /tb_reu/i_reu/stage
add wave -noupdate -expand -group reu /tb_reu/i_reu/op_cur
add wave -noupdate -expand -group reu /tb_reu/i_reu/op_dev
add wave -noupdate -expand -group reu /tb_reu/i_reu/op_dat
add wave -noupdate -expand -group reu /tb_reu/i_reu/op_act
add wave -noupdate -expand -group reu /tb_reu/i_reu/dma_we_r
add wave -noupdate -expand -group reu /tb_reu/i_reu/addr_ram
add wave -noupdate -expand -group reu /tb_reu/i_reu/addr_ram_r
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {57675000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 216
configure wave -valuecolwidth 332
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
WaveRestoreZoom {0 ps} {63 us}
