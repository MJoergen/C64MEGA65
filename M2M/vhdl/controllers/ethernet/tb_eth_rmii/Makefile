# Author:  Michael Jørgensen
#
# Description: Makefile for simulating the axi_wbus.vhd file.

# List of source files
SRC += ../eth_rmii.vhd

# List of test specific simulation files
SRC += tb_eth_rmii.vhd

# Top level entity
DUT = eth_rmii

# Test duration
STOP_TIME = 300us

# Test bench configuration
GENERIC += -gG_TOGGLE_DIBITS=5
GENERIC += -gG_TOGGLE_PHASE=0
GENERIC += -gG_FRAMES=4
GENERIC += -gG_LENGTH=64

# Don't stop on errors
#ASSERT_LEVEL = none

include Makefile.inc

