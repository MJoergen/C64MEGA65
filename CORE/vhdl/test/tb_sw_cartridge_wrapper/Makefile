SRC += ../../crt_parser.vhd
SRC += ../../crt_cacher.vhd
SRC += ../../crt_loader.vhd
SRC += ../../sw_cartridge_csr.vhd
SRC += ../../sw_cartridge_wrapper.vhd
SRC += ../../cartridge.vhd
SRC += ../../../../M2M/vhdl/memory/axi_fifo.vhd
SRC += ../../../../M2M/vhdl/memory/avm_fifo.vhd
SRC += ../../../../M2M/vhdl/memory/avm_arbit.vhd
SRC += ../../../../M2M/vhdl/memory/avm_rom.vhd
SRC += ../../../../M2M/vhdl/memory/avm_memory.vhd
SRC += ../../../../M2M/vhdl/cdc_slow.vhd
SRC += ../../../../M2M/vhdl/cdc_stable.vhd
SRC += ../../../../M2M/vhdl/qnice2hyperram.vhd
SRC += ../../../../M2M/vhdl/tdp_ram.vhd
SRC += ../../../../M2M/vhdl/qnice_csr.vhd

SRC += ../../../../../65c02/src/datapath/alu.vhd
SRC += ../../../../../65c02/src/datapath/ar.vhd
SRC += ../../../../../65c02/src/datapath/datapath.vhd
SRC += ../../../../../65c02/src/datapath/hi.vhd
SRC += ../../../../../65c02/src/datapath/lo.vhd
SRC += ../../../../../65c02/src/datapath/mr.vhd
SRC += ../../../../../65c02/src/datapath/pc.vhd
SRC += ../../../../../65c02/src/datapath/sp.vhd
SRC += ../../../../../65c02/src/datapath/sr.vhd
SRC += ../../../../../65c02/src/datapath/xr.vhd
SRC += ../../../../../65c02/src/datapath/yr.vhd
SRC += ../../../../../65c02/src/datapath/zp.vhd
SRC += ../../../../../65c02/src/control/control.vhd
SRC += ../../../../../65c02/src/control/microcode_6502.vhd
SRC += ../../../../../65c02/src/control/microcode_65c02.vhd
SRC += ../../../../../65c02/src/fmt.vhd
SRC += ../../../../../65c02/src/debug.vhd
SRC += ../../../../../65c02/src/cpu_65c02.vhd

SRC += qnice_sim.vhd
SRC += core_sim.vhd

#CRT_FILE = Super_Mario_Bros_64_v1.2_-_Zeropaige.crt
#CRT_FILE = Final_Cartridge_III,_The_\(USA,_Europe\)_\(May_88\)_\(Program\).crt
#CRT_FILE = ar4.crt
#CRT_DIR  = $(HOME)/Downloads
#CRT_FILE = last_ninja_remix_ef_patched2.crt
#CRT_FILE = SoulForce_GMod2.crt
#CRT_DIR  = $(HOME)/Documents/FPGA/MEGA65_1/MEGA65-SD/c64/SoulForce
#CRT_DIR  = $(HOME)/Documents/PRIVATE/MEGA65/C64
#CRT_DIR  = $(HOME)/Documents
#CRT_FILE = snappyrom534/crt/snappyrom-5.34-pal.crt
CRT_DIR  = .
CRT_FILE = snappy.crt


G_FILE_NAME=$(CRT_DIR)/$(CRT_FILE)
#DUT ?= crt_parser
DUT ?= sw_cartridge_wrapper
GENERIC ?= -gG_FILE_NAME=$(G_FILE_NAME)


TB = tb_$(DUT)
SRC += $(TB).vhd
WAVE = $(TB).ghw
FST  = $(TB).fst
SAVE = $(TB).gtkw

XPM_TOP_DIR = ../../../../../../fransschreuder/xpm_vhdl

sim: $(SRC) xpm-obj08.cf ../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin $(G_FILE_NAME)
	ghdl -i --std=08 --work=work $(SRC)
	ghdl -m --std=08 -fexplicit $(TB)
	ghdl -r --std=08 $(TB) $(GENERIC) --assert-level=error --fst=$(FST) --max-stack-alloc=2097151 --stop-time=3000us | tee output.txt

../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin: ../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.hex
	xxd -r -p ../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.hex ../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin

xpm-obj08.cf:
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_VCOMP.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_single.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_array_single.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_async_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_gray.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_handshake.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_low_latency_handshake.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_pulse.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_cdc/hdl/xpm_cdc_sync_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_base.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_dpdistram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_dprom.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_sdpram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_spram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_sprom.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_memory/hdl/xpm_memory_tdpram.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_rst.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_bit.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_counter_updn.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_vec.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_reg_pipe_bit.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_base.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_async.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axi_reg_slice.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axif.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axil.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_axis.vhd
	ghdl -a --work=xpm --std=08 ${XPM_TOP_DIR}/src/xpm/xpm_fifo/hdl/xpm_fifo_sync.vhd

questa: $(SRC)
	vcom -2008 $(SRC)
	vsim $(TB)

show: $(FST)
	gtkwave $(FST) $(SAVE)

formal: $(DUT)_bmc/PASS
$(DUT)_bmc/PASS: $(DUT).sby $(DUT).psl $(DUT).vhd
	sby --yosys "yosys -m ghdl" -f $(DUT).sby

show_bmc:
	gtkwave $(DUT)_bmc/engine_0/trace.vcd $(DUT).gtkw

show_cover:
	gtkwave $(DUT)_cover/engine_0/trace.vcd $(DUT).gtkw

clean:
	rm -rf *.o
	rm -rf work-obj08.cf
	rm -rf xpm-obj08.cf
	rm -rf $(TB)
	rm -rf $(WAVE)
	rm -rf $(FST)
	rm -rf ../../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin
	rm -rf output.txt

PROG_SRC = snappy.s
PROG_OBJ = $(PROG_SRC:.s=.o)
LD_CFG   = ld.cfg

%.o: %.s
	ca65 $<

./snappy.crt: $(PROG_OBJ) $(LD_CFG)
	ld65 -C $(LD_CFG) $(PROG_OBJ)


