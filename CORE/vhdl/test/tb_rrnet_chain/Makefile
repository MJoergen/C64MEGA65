# Makefile for verifying the RR-NET emulator
# Simply type 'make' to run the test.
# The test compiles a short assembly program (in rrnet.s) to generate the stimuli.

DUT ?= rrnet_chain

SRC += ../../rrnet.vhd
SRC += ../../../../M2M/vhdl/controllers/ethernet/eth_rmii.vhd

TB_SRC += ../../../../M2M/vhdl/tdp_ram.vhd
TB_SRC += ../../../../M2M/vhdl/axis_fifo_async.vhd

TB = tb_$(DUT)
TB_SRC += $(TB).vhd

WAVE = $(TB).ghw
SAVE = $(TB).gtkw

STOPTIME = 20ms

sim: $(SRC) $(TB_SRC)
	ghdl -i --std=08 --work=work $(SRC) $(TB_SRC)
	ghdl -m --std=08 -fexplicit $(TB)
	ghdl -r --std=08 $(TB) -gG_LENGTH=60 --stop-time=$(STOPTIME)
	ghdl -r --std=08 $(TB) -gG_LENGTH=100 --stop-time=$(STOPTIME)
	ghdl -r --std=08 $(TB) -gG_LENGTH=1500 --stop-time=$(STOPTIME)
	ghdl -r --std=08 $(TB) -gG_LENGTH=1518 --stop-time=$(STOPTIME)

show: $(WAVE)
	gtkwave $(WAVE) $(SAVE)

clean:
	rm -rf work-obj08.cf
	rm -rf $(WAVE)


