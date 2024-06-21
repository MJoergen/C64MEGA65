transcript file transcript.log
transcript on
onerror {resume}

# Synthesis files
vcom -2008 \
   ../../../M2M/vhdl/cdc_stable.vhd \
   ../../../M2M/vhdl/cdc_slow.vhd \
   ../../../M2M/vhdl/memory/axi_fifo.vhd \
   ../../../M2M/vhdl/memory/avm_arbit.vhd \
   ../../../M2M/vhdl/memory/avm_fifo.vhd \
   ../../../M2M/vhdl/2port2clk_ram.vhd \
   ../../../M2M/vhdl/qnice2avalon.vhd \
   ../crt_cacher.vhd \
   ../crt_parser.vhd \
   ../crt_loader.vhd \
   ../sw_cartridge_wrapper.vhd

vlog -sv \
   ../../C64_MiSTerMEGA65/rtl/cartridge.v

# Simulation files
vcom -2008 \
   ../../../M2M/vhdl/memory/avm_rom.vhd \
   tester_sim.vhd \
   tb_sw_cartridge_wrapper.vhd

vlog \
   /opt/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v

vsim -voptargs=+acc -t ps -gG_FILE_NAME=/home/mfj/apigquest_1.02_ef.crt tb_sw_cartridge_wrapper glbl

do wave.do
run 200us

