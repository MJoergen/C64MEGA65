# Makefile for verifying the RR-NET emulator
# Simply type 'make' to run the test.
# The test compiles a short assembly program (in rrnet.s) to generate the stimuli.

DUT ?= rrnet
SRC += ../../rrnet.vhd

TB_SRC += ../../../../M2M/vhdl/tdp_ram.vhd
TB_SRC += ../../../../../65c02/src/datapath/alu.vhd
TB_SRC += ../../../../../65c02/src/datapath/ar.vhd
TB_SRC += ../../../../../65c02/src/datapath/datapath.vhd
TB_SRC += ../../../../../65c02/src/datapath/hi.vhd
TB_SRC += ../../../../../65c02/src/datapath/lo.vhd
TB_SRC += ../../../../../65c02/src/datapath/mr.vhd
TB_SRC += ../../../../../65c02/src/datapath/pc.vhd
TB_SRC += ../../../../../65c02/src/datapath/sp.vhd
TB_SRC += ../../../../../65c02/src/datapath/sr.vhd
TB_SRC += ../../../../../65c02/src/datapath/xr.vhd
TB_SRC += ../../../../../65c02/src/datapath/yr.vhd
TB_SRC += ../../../../../65c02/src/datapath/zp.vhd
TB_SRC += ../../../../../65c02/src/control/control.vhd
TB_SRC += ../../../../../65c02/src/control/microcode_6502.vhd
TB_SRC += ../../../../../65c02/src/control/microcode_65c02.vhd
TB_SRC += ../../../../../65c02/src/fmt.vhd
TB_SRC += ../../../../../65c02/src/debug.vhd
TB_SRC += ../../../../../65c02/src/cpu_65c02.vhd
TB_SRC += axip_logger.vhd
TB_SRC += ../../../../M2M/vhdl/axi_fifo_small.vhd

TB = tb_$(DUT)
TB_SRC += $(TB).vhd

WAVE = $(TB).ghw
SAVE = $(TB).gtkw

LOG_FILE = cpulog.txt

STOPTIME = 600us

PROG_SRC = rrnet.asm cs8900a.asm
PROG_OBJ = $(PROG_SRC:.asm=.o)
PROG_BIN = rrnet.bin
PROG_HEX = rrnet.hex
LD_CFG   = ld.cfg

GENERIC += -gG_ROM_FILE=$(PROG_HEX) -gG_LOG_FILE=$(LOG_FILE)

#DEBUG_CA65 = -l $<.lst
#DEBUG_LD65 = -m $@.map

sim: $(SRC) $(PROG_HEX)
sim: $(SRC) $(TB_SRC) $(PROG_HEX)
	ghdl -i --std=08 --work=work $(SRC) $(TB_SRC)
	ghdl -m --std=08 -fexplicit $(TB)
	ghdl -r --std=08 $(TB) $(GENERIC) --ieee-asserts=disable-at-0 --assert-level=error --wave=$(WAVE) --stop-time=$(STOPTIME) | tee output.txt

show: $(WAVE)
	gtkwave $(WAVE) $(SAVE)

%.o: %.asm
	ca65 $< $(DEBUG_CA65)

$(PROG_BIN): $(PROG_OBJ) $(LD_CFG)
	ld65 -C $(LD_CFG) $(PROG_OBJ) $(DEBUG_LD65)

$(PROG_HEX): $(PROG_BIN)
	xxd -p -c 1 $(PROG_BIN) $(PROG_HEX)

synth: $(SRC)
	ghdl -i --std=08 --work=$(DUT)_work $^
	ghdl -m --std=08 --work=$(DUT)_work $(DUT) $(GHDL_GENERICS)
	yosys -m ghdl -p 'ghdl --std=08 --work=$(DUT)_work $(GHDL_GENERICS) $(DUT); synth_xilinx -top $(DUT) -edif $@' > $(DUT).log

clean:
	rm -rf *.o
	rm -rf work-obj08.cf
	rm -rf xpm-obj08.cf
	rm -rf $(TB)
	rm -rf $(WAVE)
	rm -rf output.txt
	rm -rf a.out
	rm -rf $(PROG_BIN)
	rm -rf $(PROG_HEX)
	rm -rf $(LOG_FILE)
	rm -rf *.lst
	rm -rf *.map
	rm -rf rrnet.log
	rm -rf synth
	rm -rf rrnet_work-obj08.cf

