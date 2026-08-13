W=../../../..

TB=tb_wrapper_overrun
WAVE=$(TB).ghw
SAVE=$(TB).gtkw

sim:
	ghdl -a --std=08 -frelaxed --work=unisim ../tb_wrapper_rrnet/unisim_stub.vhd
	ghdl -a --std=08 -frelaxed -P. ../tb_wrapper_rrnet/globals_min.vhd \
		 $W/M2M/vhdl/axis_fifo_async.vhd \
		 $W/M2M/vhdl/controllers/ethernet/eth_rmii.vhd \
		 $W/M2M/vhdl/controllers/ethernet/eth_wrapper.vhd \
		 $W/M2M/vhdl/tdp_ram.vhd $W/CORE/vhdl/rrnet.vhd \
		 tb_wrapper_overrun.vhd
	ghdl -e --std=08 -frelaxed -P. $(TB)
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_FRAMES=6 -gG_LENGTH=1000 \
		 --stop-time=800ms --assert-level=none

show:
	gtkwave $(WAVE) $(SAVE)

.PHONY: clean
clean:
	rm -f unisim-obj08.cf
	rm -f work-obj08.cf
	rm -f $(WAVE)

