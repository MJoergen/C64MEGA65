# This is a tcl script used to generate a bit-file.
# It allows building the core file directly from the command-line.
# It is provided for "convenience" only, and may not always
# be fully up-to-date.
# The project file CORE-R4.xpr is the "master" file.

create_project -in_memory
set_property PART xc7a200tfbg484-2 [current_project]
set_property XPM_LIBRARIES {XPM_CDC XPM_FIFO} [current_project]
read_vhdl -vhdl2008 { \
      C64_MiSTerMEGA65/rtl/cpu_6510.vhd \
      C64_MiSTerMEGA65/rtl/dprom.vhd \
      C64_MiSTerMEGA65/rtl/fpga64_buslogic.vhd \
      C64_MiSTerMEGA65/rtl/fpga64_rgbcolor.vhd \
      C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd \
      C64_MiSTerMEGA65/rtl/iec_drive/iecdrv_via6522.vhd \
      C64_MiSTerMEGA65/rtl/spram.vhd \
      C64_MiSTerMEGA65/rtl/t65/T65_ALU.vhd \
      C64_MiSTerMEGA65/rtl/t65/T65_MCode.vhd \
      C64_MiSTerMEGA65/rtl/t65/T65_Pack.vhd \
      C64_MiSTerMEGA65/rtl/t65/T65.vhd \
      C64_MiSTerMEGA65/rtl/video_vicII_656x.vhd \
      C64_MiSTerMEGA65/rtl/video_sync.vhd \
      ../M2M/QNICE/vhdl/alu_shifter.vhd \
      ../M2M/QNICE/vhdl/alu.vhd \
      ../M2M/QNICE/vhdl/basic_uart.vhd \
      ../M2M/QNICE/vhdl/block_ram.vhd \
      ../M2M/QNICE/vhdl/block_rom.vhd \
      ../M2M/QNICE/vhdl/bus_uart.vhd \
      ../M2M/QNICE/vhdl/byte_bram.vhd \
      ../M2M/QNICE/vhdl/cpu_constants.vhd \
      ../M2M/QNICE/vhdl/cycle_counter.vhd \
      ../M2M/QNICE/vhdl/EAE.vhd \
      ../M2M/QNICE/vhdl/fifo.vhd \
      ../M2M/QNICE/vhdl/qnice_cpu.vhd \
      ../M2M/QNICE/vhdl/register_file.vhd \
      ../M2M/QNICE/vhdl/sdcard.vhd \
      ../M2M/QNICE/vhdl/sd_spi.vhd \
      ../M2M/QNICE/vhdl/tools.vhd \
      ../M2M/vhdl/2port2clk_ram_byteenable.vhd \
      ../M2M/vhdl/2port2clk_ram.vhd \
      ../M2M/vhdl/axi_fifo_small.vhd \
      ../M2M/vhdl/av_pipeline/analog_pipeline.vhd \
      ../M2M/vhdl/av_pipeline/ascal.vhd \
      ../M2M/vhdl/av_pipeline/av_pipeline.vhd \
      ../M2M/vhdl/av_pipeline/clk_synthetic_enable.vhd \
      ../M2M/vhdl/av_pipeline/crop.vhd \
      ../M2M/vhdl/av_pipeline/digital_pipeline.vhd \
      ../M2M/vhdl/av_pipeline/vga_osm.vhd \
      ../M2M/vhdl/av_pipeline/vga_recover_counters.vhd \
      ../M2M/vhdl/av_pipeline/video_counters.vhd \
      ../M2M/vhdl/av_pipeline/video_modes_pkg.vhd \
      ../M2M/vhdl/av_pipeline/video_overlay.vhd \
      ../M2M/vhdl/cdc_pulse.vhd \
      ../M2M/vhdl/cdc_slow.vhd \
      ../M2M/vhdl/cdc_stable.vhd \
      ../M2M/vhdl/clk_m2m.vhd \
      ../M2M/vhdl/clock_counter.vhd \
      ../M2M/vhdl/controllers/HDMI/hdmi_tx_encoder.vhd \
      ../M2M/vhdl/controllers/HDMI/serialiser_10to1_selectio.vhd \
      ../M2M/vhdl/controllers/HDMI/sync_reg.vhd \
      ../M2M/vhdl/controllers/HDMI/types_pkg.vhd \
      ../M2M/vhdl/controllers/HDMI/vga_to_hdmi.vhd \
      ../M2M/vhdl/controllers/HDMI/video_out_clock.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_config.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_ctrl.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_errata.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_fifo.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_rx.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram_tx.vhd \
      ../M2M/vhdl/controllers/hyperram/hyperram.vhd \
      ../M2M/vhdl/controllers/M65/audio.vhd \
      ../M2M/vhdl/controllers/M65/kb_matrix_ram.vhdl \
      ../M2M/vhdl/controllers/M65/matrix_to_keynum.vhdl \
      ../M2M/vhdl/controllers/M65/mega65kbd_to_matrix.vhdl \
      ../M2M/vhdl/controllers/M65/mouse_input.vhdl \
      ../M2M/vhdl/controllers/SDRAM/sdram.vhd \
      ../M2M/vhdl/debouncer.vhd \
      ../M2M/vhdl/debounce.vhd \
      ../M2M/vhdl/framework.vhd \
      ../M2M/vhdl/hdmi_flicker_free.vhd \
      ../M2M/vhdl/i2c/cpu_to_i2c_master.vhd \
      ../M2M/vhdl/i2c/i2c_controller.vhd \
      ../M2M/vhdl/i2c/i2c_master.vhd \
      ../M2M/vhdl/i2c/rtc_controller.vhd \
      ../M2M/vhdl/i2c/rtc_master.vhd \
      ../M2M/vhdl/i2c/rtc_wrapper.vhd \
      ../M2M/vhdl/m2m_keyb.vhd \
      ../M2M/vhdl/memory/avm_arbit_general.vhd \
      ../M2M/vhdl/memory/avm_arbit.vhd \
      ../M2M/vhdl/memory/avm_cache.vhd \
      ../M2M/vhdl/memory/avm_decrease.vhd \
      ../M2M/vhdl/memory/avm_fifo.vhd \
      ../M2M/vhdl/memory/axi_fifo.vhd \
      ../M2M/vhdl/qnice2hyperram.vhd \
      ../M2M/vhdl/qnice_arbit.vhd \
      ../M2M/vhdl/qnice_csr.vhd \
      ../M2M/vhdl/QNICE/qnice_globals.vhd \
      ../M2M/vhdl/QNICE/qnice_mmio.vhd \
      ../M2M/vhdl/QNICE/qnice.vhd \
      ../M2M/vhdl/QNICE/sdmux.vhd \
      ../M2M/vhdl/qnice_wrapper.vhd \
      ../M2M/vhdl/ram_init.vhd \
      ../M2M/vhdl/reset_manager.vhd \
      ../M2M/vhdl/tdp_ram.vhd \
      ../M2M/vhdl/top_mega65-r4.vhd \
      ../M2M/vhdl/vdrives.vhd \
      vhdl/cartridge_heuristics.vhd \
      vhdl/cartridge.vhd \
      vhdl/clk.vhd \
      vhdl/config.vhd \
      vhdl/crt_cacher.vhd \
      vhdl/crt_loader.vhd \
      vhdl/crt_parser.vhd \
      vhdl/globals.vhd \
      vhdl/keyboard.vhd \
      vhdl/main.vhd \
      vhdl/physical_1581/physical_1581_pkg.vhd \
      vhdl/physical_1581/physical_1581_crc.vhd \
      vhdl/physical_1581/physical_1581_mfm_gaps.vhd \
      vhdl/physical_1581/physical_1581_mfm_quantise.vhd \
      vhdl/physical_1581/physical_1581_mfm_gaps_to_bits.vhd \
      vhdl/physical_1581/physical_1581_mfm_bits_to_bytes.vhd \
      vhdl/physical_1581/physical_1581_inputs.vhd \
      vhdl/physical_1581/physical_1581_mfm_decoder.vhd \
      vhdl/physical_1581/physical_1581_controller.vhd \
      vhdl/physical_1581/physical_1581_rdfifo.vhd \
      vhdl/physical_1581/physical_1581_diag.vhd \
      vhdl/mega65.vhd \
      vhdl/prg_loader.vhd \
      vhdl/reu_mapper.vhd \      vhdl/mount_buf_wrapper.vhd \

      vhdl/sw_cartridge_csr.vhd \
      vhdl/sw_cartridge_wrapper.vhd }

read_verilog {
      C64_MiSTerMEGA65/rtl/iec_drive/c1541_drv.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1541_gcr.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1541_logic.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1541_multi.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1541_track.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1581_multi.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/c1581_drv.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/iecdrv_mos8520.v \
      C64_MiSTerMEGA65/rtl/iec_drive/floppy.v \
      C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv \
      C64_MiSTerMEGA65/rtl/iec_drive/iecdrv_misc.sv \
      C64_MiSTerMEGA65/rtl/mos6526.v \
      ../M2M/vhdl/controllers/MiSTer/csync.sv \
      ../M2M/vhdl/controllers/MiSTer/hq2x.sv }

read_verilog -sv {
      C64_MiSTerMEGA65/rtl/reu.v \
      C64_MiSTerMEGA65/rtl/iec_drive/fdc1772.v \
      C64_MiSTerMEGA65/rtl/rtcF83.sv \
      C64_MiSTerMEGA65/rtl/sid/sid_envelope.sv \
      C64_MiSTerMEGA65/rtl/sid/sid_filters.sv \
      C64_MiSTerMEGA65/rtl/sid/sid_tables.sv \
      C64_MiSTerMEGA65/rtl/sid/sid_top.sv \
      C64_MiSTerMEGA65/rtl/sid/sid_voice.sv \
      ../M2M/vhdl/av_pipeline/audio_out.v \
      ../M2M/vhdl/controllers/MiSTer/iir_filter.v \
      ../M2M/vhdl/controllers/MiSTer/scandoubler.v \
      ../M2M/vhdl/controllers/MiSTer/video_freezer.sv \
      ../M2M/vhdl/controllers/MiSTer/video_mixer.sv }

read_xdc { \
      CORE.xdc \
      ../M2M/common.xdc \
      ../M2M/MEGA65-R4.xdc }

cd m2m-rom
exec ./make_rom.sh <@stdin >@stdout 2>@stderr
cd ..
synth_design -top mega65_r4 -flatten_hierarchy none
source debug.tcl
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force mega65_r4.dcp
write_bitstream -force mega65_r4.bit
exit

