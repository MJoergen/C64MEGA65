SRC += ../../crt_parser.vhd
SRC += ../../../../M2M/vhdl/qnice_csr.vhd

#CRT_FILE = Super_Mario_Bros_64_v1.2_-_Zeropaige.crt
#CRT_FILE = Final_Cartridge_III,_The_\(USA,_Europe\)_\(May_88\)_\(Program\).crt
#CRT_FILE = ar4.crt
#CRT_DIR  = $(HOME)/Downloads
#CRT_FILE = last_ninja_remix_ef_patched2.crt
CRT_FILE = SoulForce_GMod2.crt
#CRT_DIR  = $(HOME)/Documents/FPGA/MEGA65_1/MEGA65-SD/c64/SoulForce
CRT_DIR  = $(HOME)/Documents/PRIVATE/MEGA65/C64


DUT ?= crt_parser

TB = tb_$(DUT)
SRC += $(TB).vhd
WAVE = $(TB).ghw
SAVE = $(TB).gtkw

sim: $(SRC)
	ghdl -i --std=08 --work=work $(SRC)
	ghdl -m --std=08 -fexplicit $(TB)
	ghdl -r --std=08 $(TB) $(GENERIC) --assert-level=error --wave=$(WAVE) --max-stack-alloc=2097151 --stop-time=3000us | tee output.txt

questa: $(SRC)
	vcom -2008 $(SRC)
	vsim $(TB)

show: $(WAVE)
	gtkwave $(WAVE) $(SAVE)

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
	rm -rf output.txt

