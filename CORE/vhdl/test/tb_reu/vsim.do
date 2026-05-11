transcript file transcript.log
transcript on
onerror {resume}

# Synthesis files
vcom -2008 \
   ../../../../M2M/vhdl/memory/avm_cache.vhd \
   ../../../../M2M/vhdl/controllers/hyperram/hyperram_errata.vhd \
   ../../reu_mapper.vhd

vlog -sv \
   ../../../C64_MiSTerMEGA65/rtl/reu.v

# Simulation files
vcom -2008 \
   ../../../../M2M/vhdl/memory/avm_memory.vhd \
   ../../../../M2M/vhdl/memory/avm_pause.vhd \
   ../../../../M2M/vhdl/memory/avm_memory_pause.vhd \
   tb_reu.vhd

vlog \
   /opt/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v

# Run simulation
vsim -voptargs=+acc -t ps tb_reu glbl

do wave.do
run 70us

