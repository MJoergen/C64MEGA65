# Makefile for verifying the RR-NET emulator
# Simply type 'make' to run the test.

DUT ?= rrnet_probe

SRC += ../../rrnet.vhd

TB_SRC += ../../../../M2M/vhdl/tdp_ram.vhd

TB = tb_$(DUT)
TB_SRC += $(TB).vhd

SAVE = $(DUT).gtkw
WAVE = $(DUT).ghw

sim: $(SRC) $(TB_SRC)
	ghdl -i --std=08 --work=work $(SRC) $(TB_SRC)
	ghdl -m --std=08 -fexplicit $(TB)
	ghdl -r --std=08 $(TB) -gG_TEST=T1 --wave=$(WAVE) --stop-time=8ms   # Tx, cc65 'send' sequence
	ghdl -r --std=08 $(TB) -gG_TEST=T2 --wave=$(WAVE) --stop-time=8ms   # Rx, cc65 'poll' sequence
	ghdl -r --std=08 $(TB) -gG_TEST=T3 --wave=$(WAVE) --stop-time=8ms   # oversized Rx frame
	ghdl -r --std=08 $(TB) -gG_TEST=T4 --wave=$(WAVE) --stop-time=8ms   # frame with no 'last' -> merge
	ghdl -r --std=08 $(TB) -gG_TEST=T5 --wave=$(WAVE) --stop-time=8ms   # skipframe
	ghdl -r --std=08 $(TB) -gG_TEST=T6 --wave=$(WAVE) --stop-time=8ms   # header read low-byte-first
	ghdl -r --std=08 $(TB) -gG_TEST=T7 --wave=$(WAVE) --stop-time=8ms   # two frames, single buffer
	ghdl -r --std=08 $(TB) -gG_TEST=T8 --wave=$(WAVE) --stop-time=8ms   # short-frame padding
	ghdl -r --std=08 $(TB) -gG_TEST=T9 --wave=$(WAVE) --stop-time=20ms  # oversized TxLength
	ghdl -r --std=08 $(TB) -gG_TEST=TA --wave=$(WAVE) --stop-time=2ms   # PP write with AutoIncrement
	ghdl -r --std=08 $(TB) -gG_TEST=TB --wave=$(WAVE) --stop-time=10ms --assert-level=none # TxCMD/TxLength via PacketPage
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=0 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=1 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=2 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=3 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=4 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=5 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=6 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=7 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=8 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=9 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TC -gG_DELAY=10 --wave=$(WAVE) --stop-time=5ms --assert-level=none # Tx start during RX_HEADER_ST
	ghdl -r --std=08 $(TB) -gG_TEST=TD --wave=$(WAVE) --stop-time=60ms  # recovery after a no-op skipframe

show: $(WAVE)
	gtkwave $(WAVE) $(SAVE)

clean:
	rm -rf work-obj08.cf
	rm -rf $(WAVE)


