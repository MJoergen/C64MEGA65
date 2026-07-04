# Author:  Michael Jørgensen
#
# Description: Makefile for simulating the axi_wbus.vhd file.

# List of source files
SRC += ../eth_rmii.vhd

# List of test specific simulation files
SRC += tb_eth_rmii.vhd

# List of generic simulation files
SRC += axip_master_sim.vhd
SRC += axip_slave_sim.vhd
SRC += lfsr.vhd
SRC += random.vhd

# Top level entity
DUT = eth_rmii

# Test duration
STOP_TIME = 300us

# Test bench configuration
GENERIC += -gG_DEBUG=false
GENERIC += -gG_MIN_LENGTH=20
GENERIC += -gG_MAX_LENGTH=60
GENERIC += -gG_CNT_SIZE=12

# Don't stop on errors
#ASSERT_LEVEL = none

include Makefile.inc

