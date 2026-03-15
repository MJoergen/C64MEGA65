onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/mode
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/bcd_en
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/res_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/enable
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/clk
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/rdy
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/abort_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/irq_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/nmi_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/so_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/r_w_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/sync
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ef
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/mf
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/xf
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ml_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/vp_n
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/vda
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/vpa
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/a
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/din
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/dout
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/regs
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/debug
add wave -noupdate -group cpu_6510 /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/nmi_ack
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ABC
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/X
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Y
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/P
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/AD
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/DL
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/PwithB
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BAH
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BAL
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/PBR
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/DBR
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/PC
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/S
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/EF_i
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/MF_i
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/XF_i
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/IR
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/MCycle
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/DO_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Mode_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BCD_en_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ALU_Op_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Write_Data_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Set_Addr_To_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/PCAdder
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/RstCycle
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/IRQCycle
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/NMICycle
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/IRQReq
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/NMIReq
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/SO_n_o
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/IRQ_n_o
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/NMI_n_o
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/NMIAct
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Break
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BusA
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BusA_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BusB
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BusB_r
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ALU_Q
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/P_Out
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LCycle
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ALU_Op
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Set_BusA_To
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Set_Addr_To
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Write_Data
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Jump
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BAAdd
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BAQuirk
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/BreakAtNA
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/ADAdd
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/AddY
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/PCAdd
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Inc_S
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Dec_S
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDA
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDP
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDX
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDY
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDS
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDDI
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDALU
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDAD
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDBAL
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/LDBAH
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/SaveP
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Write
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Res_n_i
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/Res_n_d
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/rdy_mod
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/really_rdy
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/WRn_i
add wave -noupdate -group cpu_6510 -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/cpu/cpu/NMI_entered
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/clk
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/phi
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/enaData
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/enaPixel
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSync
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/ba
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/ba_dma
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/mode6569
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/mode6567old
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/mode6567R8
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/mode6572
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/turbo_en
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/turbo_state
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/variant
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/reset
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/cs
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/we
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/lp_n
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/aRegisters
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/diRegisters
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/di
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/diColor
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/do
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/vicAddr
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/irq_n
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/hSync
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/vSync
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/colorIndex
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/debugX
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/debugY
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/vicRefresh
add wave -noupdate -group {vic II} /tb_main/main_inst/fpga64_sid_iec_inst/vic/addrValid
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/lastLineFlag
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/vicCycle
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/sprite
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shiftChars
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shiftLoadEna
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/idle
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterIrqDone
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterEnable
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/badLine
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baLoc
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baCnt
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baChars
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSprite04
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSprite15
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSprite26
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSprite37
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/baSpriteLast
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/refreshCounter
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MX
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MY
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ME
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MXE
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MYE
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MPRIO
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCColorDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCColor
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/BMM
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/BMMDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ECM
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ECMDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCM
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCMDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/DEN
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/RSEL
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/CSEL
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/RES
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/VM
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/CB
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/EC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/B0C
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/B1C
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/B2C
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/B3C
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MM0
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MM1
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/spriteColors
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MainBorder
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/TBBorder
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/setTBBorder
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/hBlack
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/vBlanking
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/hBlanking
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/xscroll
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/yscroll
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterCmp
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/vicAddrReg
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/vicAddrLoc
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ColCounter
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ColRestart
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/RowCounter
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/IRST
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ERST
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/IMBC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/EMBC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/IMMC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/EMMC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ILP
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/ELP
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/IRQ
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/collision
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2M
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2D
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2DDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2Mhit
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2Dhit
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/M2MClr
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterX
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterY
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterY_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/cycleLast
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/cycleLastDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rasterXDelay
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/lightPenHit
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/lpX
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/lpY
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/resetLightPenIrq
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/resetIMMC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/resetIMBC
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/resetRasterIrq
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/charStore
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/nextChar
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/waitingChar
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/waitingChar_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/waitingPixels
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/waitingPixels_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shiftingChar
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shiftingChar_d
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shiftingPixels
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/currentPixels
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/currentPixels_d
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/shifting_ff
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MPtr
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MPixels
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MPixelStore
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MActive
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MActive_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MDMA
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MDMA_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCnt
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCnt_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCBase
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCBase_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MXE_ff
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MYE_ff
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MYE_ff_next
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MC_ff
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MShift_stop
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCurrentPixel_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/MCurrentPixel
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/pixelBgFlag
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/we_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/rd_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/addr_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/di_r
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/myWr_phi1
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/myWr_a
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/myWr_b
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/myWr_c
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/myRd
add wave -noupdate -group {vic II} -expand -group Internal /tb_main/main_inst/fpga64_sid_iec_inst/vic/turbo_reg
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/clk
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/reset
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cfg
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_req
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_cycle
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/dma_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_cycle
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/ram_cs
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_addr
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_dout
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_din
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_we
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/cpu_cs
add wave -noupdate -group reu /tb_main/main_inst/reu_inst/irq
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/ff00_wr
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/stage
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_cur
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_dev
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_dat
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/op_act
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/dma_we_r
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/addr_ram
add wave -noupdate -group reu -group Internal /tb_main/main_inst/reu_inst/addr_ram_r
add wave -noupdate -group main /tb_main/main_inst/clk_main_i
add wave -noupdate -group main /tb_main/main_inst/reset_soft_i
add wave -noupdate -group main /tb_main/main_inst/reset_hard_i
add wave -noupdate -group main /tb_main/main_inst/pause_i
add wave -noupdate -group main /tb_main/main_inst/trigger_run_i
add wave -noupdate -group main /tb_main/main_inst/c64_rom_i
add wave -noupdate -group main /tb_main/main_inst/c64_ntsc_i
add wave -noupdate -group main /tb_main/main_inst/clk_main_speed_i
add wave -noupdate -group main /tb_main/main_inst/video_retro15khz_i
add wave -noupdate -group main /tb_main/main_inst/c64_sid_ver_i
add wave -noupdate -group main /tb_main/main_inst/c64_sid_port_i
add wave -noupdate -group main /tb_main/main_inst/c64_cia_ver_i
add wave -noupdate -group main /tb_main/main_inst/c64_exp_port_mode_i
add wave -noupdate -group main /tb_main/main_inst/kb_key_num_i
add wave -noupdate -group main /tb_main/main_inst/kb_key_pressed_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_up_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_down_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_left_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_right_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_fire_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_1_up_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_1_down_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_1_left_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_1_right_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_1_fire_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_2_up_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_2_down_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_2_left_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_2_right_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_2_fire_n_i
add wave -noupdate -group main /tb_main/main_inst/joy_2_up_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_2_down_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_2_left_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_2_right_n_o
add wave -noupdate -group main /tb_main/main_inst/joy_2_fire_n_o
add wave -noupdate -group main /tb_main/main_inst/pot1_x_i
add wave -noupdate -group main /tb_main/main_inst/pot1_y_i
add wave -noupdate -group main /tb_main/main_inst/pot2_x_i
add wave -noupdate -group main /tb_main/main_inst/pot2_y_i
add wave -noupdate -group main /tb_main/main_inst/video_ce_o
add wave -noupdate -group main /tb_main/main_inst/video_ce_ovl_o
add wave -noupdate -group main /tb_main/main_inst/video_red_o
add wave -noupdate -group main /tb_main/main_inst/video_green_o
add wave -noupdate -group main /tb_main/main_inst/video_blue_o
add wave -noupdate -group main /tb_main/main_inst/video_vs_o
add wave -noupdate -group main /tb_main/main_inst/video_hs_o
add wave -noupdate -group main /tb_main/main_inst/video_hblank_o
add wave -noupdate -group main /tb_main/main_inst/video_vblank_o
add wave -noupdate -group main /tb_main/main_inst/audio_left_o
add wave -noupdate -group main /tb_main/main_inst/audio_right_o
add wave -noupdate -group main /tb_main/main_inst/drive_led_o
add wave -noupdate -group main /tb_main/main_inst/drive_led_col_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_addr_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_data_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_we_o
add wave -noupdate -group main /tb_main/main_inst/c64_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/c64_clk_sd_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_addr_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_data_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_data_o
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_ce_i
add wave -noupdate -group main /tb_main/main_inst/c64_qnice_we_i
add wave -noupdate -group main /tb_main/main_inst/iec_hardware_port_en_i
add wave -noupdate -group main /tb_main/main_inst/iec_reset_n_o
add wave -noupdate -group main /tb_main/main_inst/iec_atn_n_o
add wave -noupdate -group main /tb_main/main_inst/iec_clk_en_o
add wave -noupdate -group main /tb_main/main_inst/iec_clk_n_i
add wave -noupdate -group main /tb_main/main_inst/iec_clk_n_o
add wave -noupdate -group main /tb_main/main_inst/iec_data_en_o
add wave -noupdate -group main /tb_main/main_inst/iec_data_n_i
add wave -noupdate -group main /tb_main/main_inst/iec_data_n_o
add wave -noupdate -group main /tb_main/main_inst/iec_srq_en_o
add wave -noupdate -group main /tb_main/main_inst/iec_srq_n_i
add wave -noupdate -group main /tb_main/main_inst/iec_srq_n_o
add wave -noupdate -group main /tb_main/main_inst/cart_en_o
add wave -noupdate -group main /tb_main/main_inst/cart_phi2_o
add wave -noupdate -group main /tb_main/main_inst/cart_dotclock_o
add wave -noupdate -group main /tb_main/main_inst/cart_dma_i
add wave -noupdate -group main /tb_main/main_inst/cart_reset_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_reset_i
add wave -noupdate -group main /tb_main/main_inst/cart_reset_o
add wave -noupdate -group main /tb_main/main_inst/cart_game_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_game_i
add wave -noupdate -group main /tb_main/main_inst/cart_game_o
add wave -noupdate -group main /tb_main/main_inst/cart_exrom_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_exrom_i
add wave -noupdate -group main /tb_main/main_inst/cart_exrom_o
add wave -noupdate -group main /tb_main/main_inst/cart_nmi_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_nmi_i
add wave -noupdate -group main /tb_main/main_inst/cart_nmi_o
add wave -noupdate -group main /tb_main/main_inst/cart_irq_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_irq_i
add wave -noupdate -group main /tb_main/main_inst/cart_irq_o
add wave -noupdate -group main /tb_main/main_inst/cart_roml_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_roml_i
add wave -noupdate -group main /tb_main/main_inst/cart_roml_o
add wave -noupdate -group main /tb_main/main_inst/cart_romh_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_romh_i
add wave -noupdate -group main /tb_main/main_inst/cart_romh_o
add wave -noupdate -group main /tb_main/main_inst/cart_ctrl_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_ba_i
add wave -noupdate -group main /tb_main/main_inst/cart_rw_i
add wave -noupdate -group main /tb_main/main_inst/cart_io1_i
add wave -noupdate -group main /tb_main/main_inst/cart_io2_i
add wave -noupdate -group main /tb_main/main_inst/cart_ba_o
add wave -noupdate -group main /tb_main/main_inst/cart_rw_o
add wave -noupdate -group main /tb_main/main_inst/cart_io1_o
add wave -noupdate -group main /tb_main/main_inst/cart_io2_o
add wave -noupdate -group main /tb_main/main_inst/cart_addr_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_a_i
add wave -noupdate -group main /tb_main/main_inst/cart_a_o
add wave -noupdate -group main /tb_main/main_inst/cart_data_oe_o
add wave -noupdate -group main /tb_main/main_inst/cart_d_i
add wave -noupdate -group main /tb_main/main_inst/cart_d_o
add wave -noupdate -group main /tb_main/main_inst/avm_waitrequest_i
add wave -noupdate -group main /tb_main/main_inst/avm_write_o
add wave -noupdate -group main /tb_main/main_inst/avm_read_o
add wave -noupdate -group main /tb_main/main_inst/avm_address_o
add wave -noupdate -group main /tb_main/main_inst/avm_writedata_o
add wave -noupdate -group main /tb_main/main_inst/avm_byteenable_o
add wave -noupdate -group main /tb_main/main_inst/avm_burstcount_o
add wave -noupdate -group main /tb_main/main_inst/avm_readdata_i
add wave -noupdate -group main /tb_main/main_inst/avm_readdatavalid_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_loading_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_id_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_exrom_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_game_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_size_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_bank_laddr_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_bank_size_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_bank_num_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_bank_raddr_i
add wave -noupdate -group main /tb_main/main_inst/cartridge_bank_wr_i
add wave -noupdate -group main /tb_main/main_inst/crt_bank_wait_i
add wave -noupdate -group main /tb_main/main_inst/crt_lo_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/crt_hi_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/crt_ioe_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/crt_iof_ram_data_i
add wave -noupdate -group main /tb_main/main_inst/crt_addr_bus_o
add wave -noupdate -group main /tb_main/main_inst/crt_ioe_we_o
add wave -noupdate -group main /tb_main/main_inst/crt_iof_we_o
add wave -noupdate -group main /tb_main/main_inst/crt_bank_lo_o
add wave -noupdate -group main /tb_main/main_inst/crt_bank_hi_o
add wave -noupdate -group main /tb_main/main_inst/c64rom_we_i
add wave -noupdate -group main /tb_main/main_inst/c64rom_addr_i
add wave -noupdate -group main /tb_main/main_inst/c64rom_data_i
add wave -noupdate -group main /tb_main/main_inst/c64rom_data_o
add wave -noupdate -group main /tb_main/main_inst/c1541rom_we_i
add wave -noupdate -group main /tb_main/main_inst/c1541rom_addr_i
add wave -noupdate -group main /tb_main/main_inst/c1541rom_data_i
add wave -noupdate -group main /tb_main/main_inst/c1541rom_data_o
add wave -noupdate -group main /tb_main/main_inst/rtc_i
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_pause
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_drive_led
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cia1_pa_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cia1_pa_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cia1_pb_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cia1_pb_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_ram_ce
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_ram_we
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_ram_data
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_sid_l
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_sid_r
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/alo
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/aro
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/restore_key_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_iec_clk_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_iec_clk_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_iec_atn_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_iec_data_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/c64_iec_data_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/hw_iec_clk_n_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/hw_iec_data_n_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_drive_ce
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_dce_sum
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_img_mounted
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_img_readonly
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_img_size
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_img_type
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_drives_reset
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vdrives_mounted
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cache_dirty
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/prevent_reset
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_lba
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_blk_cnt
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_rd
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_wr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_ack
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_buf_addr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_buf_data_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_buf_data_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_sd_buf_wr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_par_stb_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_par_stb_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_par_data_in
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/iec_par_data_out
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vga_hs
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vga_vs
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vga_red
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vga_green
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/vga_blue
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/video_ce
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reset_core_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reset_core_int_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/hard_reset_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/hard_rst_counter
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/hard_reset_n_d
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cold_start_done
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_roml
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_romh
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_ioe
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_iof
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_nmi_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_nmi_ack
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_ba
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_irq_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_dma
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_exrom_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_game_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_umax_romh
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_umax_unmapped
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_io_rom
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_io_ext
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_io_data
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_dotclk
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/core_phi2
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cartridge_bank_raddr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_roml_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_romh_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_io1_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_io2_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_nmi_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_irq_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_dma_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_exrom_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_game_n
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/data_from_cart
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_reset_counter
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_res_flckr_ign
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cart_is_an_ef3
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_cfg
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_req
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_cycle
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_addr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_dout
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_din
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dma_we
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_irq
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_iof
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_oe
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/reu_dout
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_io_rom
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_io_ext
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_io_data
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_exrom
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_game
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_nmi
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_ioe_wr_ena
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/crt_iof_wr_ena
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_ext_cycle
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_cycle
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_addr
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_dout
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_din
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_we
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/sim_reu_cs
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_write
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_read
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_address
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_writedata
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_byteenable
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_burstcount
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_readdata
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_readdatavalid
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/map_waitrequest
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cass_write
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cass_motor
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/cass_rtc
add wave -noupdate -group main -expand -group Internal /tb_main/main_inst/rtcf83_sda
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/clk_qnice_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/clk_core_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/reset_core_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/img_mounted_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/img_readonly_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/img_size_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/img_type_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/drive_mounted_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/cache_dirty_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/cache_flushing_o
add wave -noupdate -expand -group vdrives -radix unsigned /tb_main/main_inst/vdrives_inst/sd_lba_i
add wave -noupdate -expand -group vdrives -radix unsigned /tb_main/main_inst/vdrives_inst/sd_blk_cnt_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_rd_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_wr_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_ack_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_buff_addr_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_buff_dout_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_buff_din_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/sd_buff_wr_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/qnice_addr_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/qnice_data_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/qnice_data_o
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/qnice_ce_i
add wave -noupdate -expand -group vdrives /tb_main/main_inst/vdrives_inst/qnice_we_i
add wave -noupdate -radix unsigned /tb_main/main_inst/fpga64_sid_iec_inst/debug_proc/clk
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {532093 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 169
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {432925 ps} {1163948 ps}
