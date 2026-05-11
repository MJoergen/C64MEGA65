transcript file transcript.log
transcript on
onerror {resume}

# Synthesis files
vcom -2008 \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_bit.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_reg_pipe_bit.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_vec.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_array_single.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_async_rst.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_gray.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_single.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_handshake.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_low_latency_handshake.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_pulse.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_sync_rst.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_base.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_dpdistram.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_dprom.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_sdpram.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_spram.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_sprom.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_tdpram.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_counter_updn.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_rst.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_base.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_async.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_axi_reg_slice.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_axif.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_axil.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_axis.vhd \
   ../../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_sync.vhd \
   ../../../../M2M/vhdl/memory/axi_fifo.vhd \
   ../../../../M2M/vhdl/memory/avm_cache.vhd \
   ../../../../M2M/vhdl/memory/avm_fifo.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_config.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_ctrl.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_errata.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_fifo.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_rx.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_tx.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram.vhd \
   ../../reu_mapper.vhd

vlog -sv \
   ../../../C64_MiSTerMEGA65/rtl/reu.v

# Simulation files
vcom -2008 \
   tb_reu.vhd

vlog \
   s27kl0642.v \
   /opt/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v

# Run simulation
vsim -voptargs=+acc -t ps tb_reu glbl

do wave.do
run 300us

