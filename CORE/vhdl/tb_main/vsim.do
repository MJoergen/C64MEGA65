transcript file transcript.log
transcript on
onerror {resume}

# Synthesis files
vlog -sv \
    ../../C64_MiSTerMEGA65/rtl/mos6526.v \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/c1541_drv.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/c1541_gcr.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/c1541_logic.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/c1541_multi.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/c1541_track.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/iecdrv_misc.sv \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv \
    ../../C64_MiSTerMEGA65/rtl/reu.v \
    ../../C64_MiSTerMEGA65/rtl/rtcF83.sv \
    ../../C64_MiSTerMEGA65/rtl/sid/sid_envelope.sv \
    ../../C64_MiSTerMEGA65/rtl/sid/sid_filters.sv \
    ../../C64_MiSTerMEGA65/rtl/sid/sid_tables.sv \
    ../../C64_MiSTerMEGA65/rtl/sid/sid_voice.sv \
    ../../C64_MiSTerMEGA65/rtl/sid/sid_top.sv

vcom -2008 \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_VCOMP.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_memory/hdl/xpm_memory_base.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_sync_rst.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_gray.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_single.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_cdc/hdl/xpm_cdc_array_single.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_counter_updn.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_rst.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_bit.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_reg_vec.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_reg_pipe_bit.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_base.vhd \
    ../../../../../fransschreuder/xpm_vhdl/src/xpm/xpm_fifo/hdl/xpm_fifo_axis.vhd


vcom -2008 \
    ../../../../65c02/src/fmt.vhd \
    ../../../../65c02/src/debug.vhd \
    ../../../M2M/vhdl/av_pipeline/video_modes_pkg.vhd \
    ../../../M2M/QNICE/vhdl/tools.vhd \
    ../globals.vhd \
    ../../../M2M/vhdl/cdc_stable.vhd \
    ../../../M2M/vhdl/cdc_slow.vhd \
    ../../../M2M/vhdl/tdp_ram.vhd \
    ../../../M2M/vhdl/qnice_csr.vhd \
    ../../../M2M/vhdl/qnice2hyperram.vhd \
    ../../../M2M/vhdl/2port2clk_ram.vhd \
    ../../../M2M/vhdl/memory/axi_fifo.vhd \
    ../../../M2M/vhdl/memory/avm_fifo.vhd \
    ../../../M2M/vhdl/memory/avm_memory.vhd \
    ../../../M2M/vhdl/memory/avm_pause.vhd \
    ../../../M2M/vhdl/memory/avm_memory_pause.vhd \
    ../../../M2M/vhdl/memory/avm_cache.vhd \
    ../../../M2M/vhdl/memory/avm_arbit.vhd \
    ../../../M2M/vhdl/memory/avm_rom.vhd \
    ../../C64_MiSTerMEGA65/rtl/fmt.vhd \
    ../../C64_MiSTerMEGA65/rtl/video_sync.vhd \
    ../../C64_MiSTerMEGA65/rtl/t65/T65_Pack.vhd \
    ../../C64_MiSTerMEGA65/rtl/t65/T65_MCode.vhd \
    ../../C64_MiSTerMEGA65/rtl/t65/T65_ALU.vhd \
    ../../C64_MiSTerMEGA65/rtl/t65/T65.vhd \
    ../../C64_MiSTerMEGA65/rtl/cpu_6510.vhd \
    ../../C64_MiSTerMEGA65/rtl/dprom.vhd \
    ../../C64_MiSTerMEGA65/rtl/fpga64_buslogic.vhd \
    ../../C64_MiSTerMEGA65/rtl/fpga64_rgbcolor.vhd \
    ../../C64_MiSTerMEGA65/rtl/spram.vhd \
    ../../C64_MiSTerMEGA65/rtl/video_vicII_656x.vhd \
    ../../C64_MiSTerMEGA65/rtl/iec_drive/iecdrv_via6522.vhd \
    ../../C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd \
    ../reu_mapper.vhd \
    ../cartridge.vhd \
    ../keyboard.vhd \
    ../cartridge_heuristics.vhd \
    vdrives.vhd \
    ../crt_parser.vhd \
    ../crt_cacher.vhd \
    ../crt_loader.vhd \
    ../sw_cartridge_csr.vhd \
    ../sw_cartridge_wrapper.vhd \
    ../main.vhd


# Simulation files
vcom -2008 \
    qnice_sim.vhd \
    tb_main.vhd

vlog \
    /opt/Xilinx/Vivado/2021.2/data/verilog/src/glbl.v

# Run simulation
vsim -voptargs=+acc -t ps \
    -gG_CRT_FILE_NAME=snappyrom-5.34-pal.crt \
    tb_main glbl

do wave.do
run 1ms

