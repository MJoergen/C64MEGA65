W=../../../..

TB=tb_rrnet_v2
WAVE=$(TB).ghw
SAVE=$(TB).gtkw

sim:
	ghdl -a --std=08 -frelaxed $W/M2M/vhdl/tdp_ram.vhd $W/CORE/vhdl/rrnet.vhd tb_rrnet_v2.vhd
	ghdl -e --std=08 -frelaxed $(TB)
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=M0   -gG_LEN=100 -gG_FIRST=255 --stop-time=10ms
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=FILT -gG_FIRST=1   --stop-time=5ms   # filter matrix
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=R1   -gG_LEN=1600  --stop-time=30ms  # oversized Rx
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=P5   --stop-time=20ms                # CRC-bad frame
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=P1   --stop-time=20ms                # skipframe
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=R5   --stop-time=20ms                # autoincrement read
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=R4   -gG_DELAY=0 --stop-time=10ms    # sweep 0..16
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=R3   -gG_LEN=1515 --stop-time=40ms   # oversized TxLength
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=P2   --stop-time=20ms                # PacketPage TxCMD
	ghdl -r --std=08 $(TB) --wave=$(WAVE) -gG_TEST=P7   --stop-time=20ms                # reset values

show:
	gtkwave $(WAVE) $(SAVE)

.PHONY: clean
clean:
	rm -f unisim-obj08.cf
	rm -f work-obj08.cf
	rm -f $(WAVE)

