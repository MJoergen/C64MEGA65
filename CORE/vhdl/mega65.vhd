----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- MEGA65 main file that contains the whole machine
--
-- based on C64_MiSTer by the MiSTer development team
-- powered by MiSTer2MEGA65 done by sy2002 and MJoergen in 2023
-- port done by MJoergen and sy2002 in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.globals.all;
use work.types_pkg.all;
use work.qnice_tools.all;
use work.video_modes_pkg.all;

library xpm;
use xpm.vcomponents.all;

entity MEGA65_Core is
generic (
   G_BOARD : string                                         -- Which platform are we running on.
);
port (
   --------------------------------------------------------------------------------------------------------
   -- QNICE Clock Domain
   --------------------------------------------------------------------------------------------------------

   -- Get QNICE clock from the framework: for the vdrives as well as for RAMs and ROMs
   qnice_clk_i             : in  std_logic;
   qnice_rst_i             : in  std_logic;

   -- Video and audio mode control
   qnice_dvi_o             : out std_logic;                 -- 0=HDMI (with sound), 1=DVI (no sound)
   qnice_video_mode_o      : out video_mode_type;           -- Defined in video_modes_pkg.vhd
   qnice_osm_cfg_scaling_o : out std_logic_vector(8 downto 0);
   qnice_scandoubler_o     : out std_logic;                 -- 0 = no scandoubler, 1 = scandoubler
   qnice_audio_mute_o      : out std_logic;
   qnice_audio_filter_o    : out std_logic;
   qnice_zoom_crop_o       : out std_logic;
   qnice_ascal_mode_o      : out std_logic_vector(1 downto 0);
   qnice_ascal_polyphase_o : out std_logic;
   qnice_ascal_triplebuf_o : out std_logic;
   qnice_retro15kHz_o      : out std_logic;                 -- 0 = normal frequency, 1 = retro 15 kHz frequency
   qnice_csync_o           : out std_logic;                 -- 0 = normal HS/VS, 1 = Composite Sync

   -- Flip joystick ports
   qnice_flip_joyports_o   : out std_logic;

   -- On-Screen-Menu selections
   qnice_osm_control_i     : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register
   qnice_gp_reg_i          : in  std_logic_vector(255 downto 0);

   -- Core-specific devices
   qnice_dev_id_i          : in  std_logic_vector(15 downto 0);
   qnice_dev_addr_i        : in  std_logic_vector(27 downto 0);
   qnice_dev_data_i        : in  std_logic_vector(15 downto 0);
   qnice_dev_data_o        : out std_logic_vector(15 downto 0);
   qnice_dev_ce_i          : in  std_logic;
   qnice_dev_we_i          : in  std_logic;
   qnice_dev_wait_o        : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- HyperRAM Clock Domain.
   --------------------------------------------------------------------------------------------------------

   hr_clk_i                : in  std_logic;
   hr_rst_i                : in  std_logic;
   hr_core_write_o         : out std_logic;
   hr_core_read_o          : out std_logic;
   hr_core_address_o       : out std_logic_vector(31 downto 0);
   hr_core_writedata_o     : out std_logic_vector(15 downto 0);
   hr_core_byteenable_o    : out std_logic_vector( 1 downto 0);
   hr_core_burstcount_o    : out std_logic_vector( 7 downto 0);
   hr_core_readdata_i      : in  std_logic_vector(15 downto 0);
   hr_core_readdatavalid_i : in  std_logic;
   hr_core_waitrequest_i   : in  std_logic;
   hr_high_i               : in  std_logic; -- Core is too fast
   hr_low_i                : in  std_logic; -- Core is too slow

   --------------------------------------------------------------------------------------------------------
   -- Video Clock Domain
   --------------------------------------------------------------------------------------------------------

   video_clk_o             : out std_logic;
   video_rst_o             : out std_logic;
   video_ce_o              : out std_logic;
   video_ce_ovl_o          : out std_logic;
   video_red_o             : out std_logic_vector(7 downto 0);
   video_green_o           : out std_logic_vector(7 downto 0);
   video_blue_o            : out std_logic_vector(7 downto 0);
   video_vs_o              : out std_logic;
   video_hs_o              : out std_logic;
   video_hblank_o          : out std_logic;
   video_vblank_o          : out std_logic;

   --------------------------------------------------------------------------------------------------------
   -- Core Clock Domain
   --------------------------------------------------------------------------------------------------------

   clk_i                   : in  std_logic;              -- 100 MHz clock

   -- Share clock and reset with the framework
   main_clk_o              : out std_logic;                 -- CORE's clock
   main_rst_o              : out std_logic;                 -- CORE's reset, synchronized

   -- M2M's reset manager provides 2 signals:
   --    m2m:   Reset the whole machine: Core and Framework
   --    core:  Only reset the core
   main_reset_m2m_i        : in  std_logic;
   main_reset_core_i       : in  std_logic;

   main_pause_core_i       : in  std_logic;

   -- On-Screen-Menu selections
   main_osm_control_i      : in  std_logic_vector(255 downto 0);

   -- QNICE general purpose register converted to main clock domain
   main_qnice_gp_reg_i     : in  std_logic_vector(255 downto 0);

   -- Audio output (Signed PCM)
   main_audio_left_o       : out signed(15 downto 0);
   main_audio_right_o      : out signed(15 downto 0);

   -- M2M Keyboard interface (incl. power led and drive led)
   main_kb_key_num_i       : in  integer range 0 to 79;     -- cycles through all MEGA65 keys
   main_kb_key_pressed_n_i : in  std_logic;                 -- low active: debounced feedback: is kb_key_num_i pressed right now?
   main_power_led_o        : out std_logic;
   main_power_led_col_o    : out std_logic_vector(23 downto 0);
   main_drive_led_o        : out std_logic;
   main_drive_led_col_o    : out std_logic_vector(23 downto 0);

   -- Joysticks and paddles input
   main_joy_1_up_n_i       : in  std_logic;
   main_joy_1_down_n_i     : in  std_logic;
   main_joy_1_left_n_i     : in  std_logic;
   main_joy_1_right_n_i    : in  std_logic;
   main_joy_1_fire_n_i     : in  std_logic;
   main_joy_1_up_n_o       : out std_logic;
   main_joy_1_down_n_o     : out std_logic;
   main_joy_1_left_n_o     : out std_logic;
   main_joy_1_right_n_o    : out std_logic;
   main_joy_1_fire_n_o     : out std_logic;
   main_joy_2_up_n_i       : in  std_logic;
   main_joy_2_down_n_i     : in  std_logic;
   main_joy_2_left_n_i     : in  std_logic;
   main_joy_2_right_n_i    : in  std_logic;
   main_joy_2_fire_n_i     : in  std_logic;
   main_joy_2_up_n_o       : out std_logic;
   main_joy_2_down_n_o     : out std_logic;
   main_joy_2_left_n_o     : out std_logic;
   main_joy_2_right_n_o    : out std_logic;
   main_joy_2_fire_n_o     : out std_logic;

   main_pot1_x_i           : in  std_logic_vector(7 downto 0);
   main_pot1_y_i           : in  std_logic_vector(7 downto 0);
   main_pot2_x_i           : in  std_logic_vector(7 downto 0);
   main_pot2_y_i           : in  std_logic_vector(7 downto 0);
   main_rtc_i              : in  std_logic_vector(64 downto 0);

   -- CBM-488/IEC serial port
   iec_reset_n_o           : out std_logic;
   iec_atn_n_o             : out std_logic;
   iec_clk_en_o            : out std_logic;
   iec_clk_n_i             : in  std_logic;
   iec_clk_n_o             : out std_logic;
   iec_data_en_o           : out std_logic;
   iec_data_n_i            : in  std_logic;
   iec_data_n_o            : out std_logic;
   iec_srq_en_o            : out std_logic;
   iec_srq_n_i             : in  std_logic;
   iec_srq_n_o             : out std_logic;

   -- MEGA65 physical internal 1581 (issue #90): board floppy pins routed to the
   -- physical_1581_controller inside main.vhd. Read-only milestone: the write
   -- pins (f_wgate/f_wdata) and drive-B pins stay tied inactive at the top level.
   f_rdata_i               : in  std_logic;
   f_index_i               : in  std_logic;
   f_track0_i              : in  std_logic;
   f_writeprotect_i        : in  std_logic;
   f_diskchanged_i         : in  std_logic;
   f_motora_o              : out std_logic;
   f_selecta_o             : out std_logic;
   f_side1_o               : out std_logic;
   f_stepdir_o             : out std_logic;
   f_step_o                : out std_logic;
   f_density_o             : out std_logic;

   -- C64 Expansion Port (aka Cartridge Port)
   cart_en_o               : out std_logic;  -- Enable port, active high
   cart_phi2_o             : out std_logic;
   cart_dotclock_o         : out std_logic;
   cart_dma_i              : in  std_logic;
   cart_reset_oe_o         : out std_logic;
   cart_reset_i            : in  std_logic;
   cart_reset_o            : out std_logic;
   cart_game_oe_o          : out std_logic;
   cart_game_i             : in  std_logic;
   cart_game_o             : out std_logic;
   cart_exrom_oe_o         : out std_logic;
   cart_exrom_i            : in  std_logic;
   cart_exrom_o            : out std_logic;
   cart_nmi_oe_o           : out std_logic;
   cart_nmi_i              : in  std_logic;
   cart_nmi_o              : out std_logic;
   cart_irq_oe_o           : out std_logic;
   cart_irq_i              : in  std_logic;
   cart_irq_o              : out std_logic;
   cart_roml_oe_o          : out std_logic;
   cart_roml_i             : in  std_logic;
   cart_roml_o             : out std_logic;
   cart_romh_oe_o          : out std_logic;
   cart_romh_i             : in  std_logic;
   cart_romh_o             : out std_logic;
   cart_ctrl_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_ba_i               : in  std_logic;
   cart_rw_i               : in  std_logic;
   cart_io1_i              : in  std_logic;
   cart_io2_i              : in  std_logic;
   cart_ba_o               : out std_logic;
   cart_rw_o               : out std_logic;
   cart_io1_o              : out std_logic;
   cart_io2_o              : out std_logic;
   cart_addr_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_a_i                : in  unsigned(15 downto 0);
   cart_a_o                : out unsigned(15 downto 0);
   cart_data_oe_o          : out std_logic; -- 0 : tristate (i.e. input), 1 : output
   cart_d_i                : in  unsigned( 7 downto 0);
   cart_d_o                : out unsigned( 7 downto 0);

    -- Ethernet interface
   eth_rx_ready_o          : out std_logic;                    -- One-cycle strobe per received byte
   eth_rx_valid_i          : in  std_logic;                    -- One-cycle strobe per received byte
   eth_rx_last_i           : in  std_logic;                    -- Last byte of frame
   eth_rx_data_i           : in  std_logic_vector(7 downto 0); -- Received byte
   eth_tx_ready_i          : in  std_logic;                    -- Pulses '1' on the byte-boundary cycle
   eth_tx_valid_o          : out std_logic;                    -- Client presents a byte
   eth_tx_last_o           : out std_logic;                    -- Client marks the last byte
   eth_tx_data_o           : out std_logic_vector(7 downto 0); -- Byte to transmit
   eth_rx_cnt_drop_i       : in  std_logic_vector(15 downto 0) -- Number of Rx frames dropped (e.g. FIFO overrun or bad CRC)
);
end entity MEGA65_Core;

architecture synthesis of MEGA65_Core is

---------------------------------------------------------------------------------------------
-- main_clk (MiSTer core's clock)
---------------------------------------------------------------------------------------------

-- C64 specific signals for PAL/NTSC and core speed switching
signal c64_rom                    : std_logic_vector(1 downto 0); -- Select C64's ROM: 0=Custom, 1=Standard, 2=GS, 3=Japan
signal c64_ntsc                   : std_logic;               -- global switch: 0 = PAL mode, 1 = NTSC mode
signal c64_clock_speed            : natural;                 -- clock speed depending on PAL/NTSC
signal c64_exp_port_mode          : std_logic_vector(3 downto 0);
                                                             -- bit    0: Simulate cartridge (.CRT file)
                                                             -- bit    1: Simulate REU
                                                             -- bits 3-2: Simulate RR-NET
signal phys_1581_en               : std_logic;               -- 1 = drive 8 backed by the physical internal 1581 (issue #90)

-- C64 config settings
signal sid_setup                  : std_logic_vector(1 downto 0);
signal sid_port                   : natural range 0 to 4;
signal main_volume                : natural range 0 to 20;   -- OSM "Volume" slider step: 0 = 0%/mute .. 20 = 100% (5% each)

-- C64 RAM
signal main_ram_addr              : unsigned(15 downto 0);         -- C64 address bus
signal main_ram_data_from_c64     : unsigned(7 downto 0);          -- C64 RAM data out
signal main_ram_we                : std_logic;                     -- C64 RAM write enable
signal main_ram_data_to_c64       : std_logic_vector( 7 downto 0); -- C64 RAM data in
signal main_crt_lo_ram_data       : std_logic_vector(15 downto 0);
signal main_crt_hi_ram_data       : std_logic_vector(15 downto 0);
signal main_crt_ioe_ram_data      : std_logic_vector( 7 downto 0);
signal main_crt_iof_ram_data      : std_logic_vector( 7 downto 0);
signal main_crt_we                : std_logic;
signal main_crt_ram_data          : std_logic_vector( 7 downto 0);

-- RAM Expansion Unit
signal main_avm_reu_write         : std_logic;
signal main_avm_reu_read          : std_logic;
signal main_avm_reu_address       : std_logic_vector(31 downto 0);
signal main_avm_reu_writedata     : std_logic_vector(15 downto 0);
signal main_avm_reu_byteenable    : std_logic_vector( 1 downto 0);
signal main_avm_reu_burstcount    : std_logic_vector( 7 downto 0);
signal main_avm_reu_readdata      : std_logic_vector(15 downto 0);
signal main_avm_reu_readdatavalid : std_logic;
signal main_avm_reu_waitrequest   : std_logic;

signal main_crt_loading           : std_logic;
signal main_crt_id                : std_logic_vector(15 downto 0);
signal main_crt_exrom             : std_logic_vector( 7 downto 0);
signal main_crt_game              : std_logic_vector( 7 downto 0);
signal main_crt_size              : std_logic_vector(22 downto 0);
signal main_crt_bank_laddr        : std_logic_vector(15 downto 0);
signal main_crt_bank_size         : std_logic_vector(15 downto 0);
signal main_crt_bank_num          : std_logic_vector(15 downto 0);
signal main_crt_bank_raddr        : std_logic_vector(24 downto 0);
signal main_crt_bank_wr           : std_logic;

signal main_crt_addr_bus          : unsigned(15 downto 0);
signal main_crt_ioe_we            : std_logic;
signal main_crt_iof_we            : std_logic;
signal main_crt_bank_lo           : std_logic_vector( 6 downto 0);
signal main_crt_bank_hi           : std_logic_vector( 6 downto 0);
signal main_crt_bank_wait         : std_logic;

signal main_reset_core            : std_logic;
signal main_reset_from_prgloader  : std_logic;
signal main_prg_trigger_run       : std_logic;
signal main_cart_soft_reset       : std_logic;

---------------------------------------------------------------------------------------------
-- hr_clk
---------------------------------------------------------------------------------------------

signal hr_core_speed              : unsigned(1 downto 0);    -- see clock.vhd for details

signal hr_reu_write               : std_logic;
signal hr_reu_read                : std_logic;
signal hr_reu_address             : std_logic_vector(31 downto 0);
signal hr_reu_writedata           : std_logic_vector(15 downto 0);
signal hr_reu_byteenable          : std_logic_vector( 1 downto 0);
signal hr_reu_burstcount          : std_logic_vector( 7 downto 0);
signal hr_reu_readdata            : std_logic_vector(15 downto 0);
signal hr_reu_readdatavalid       : std_logic;
signal hr_reu_waitrequest         : std_logic;

signal hr_crt_write               : std_logic;
signal hr_crt_read                : std_logic;
signal hr_crt_address             : std_logic_vector(31 downto 0);
signal hr_crt_writedata           : std_logic_vector(15 downto 0);
signal hr_crt_byteenable          : std_logic_vector( 1 downto 0);
signal hr_crt_burstcount          : std_logic_vector( 7 downto 0);
signal hr_crt_readdata            : std_logic_vector(15 downto 0);
signal hr_crt_readdatavalid       : std_logic;
signal hr_crt_waitrequest         : std_logic;

-- D81 enable: HyperRAM avalon master for the disk-image mount buffer (3rd arbiter slave)
signal hr_mnt_write               : std_logic;
signal hr_mnt_read                : std_logic;
signal hr_mnt_address             : std_logic_vector(31 downto 0);
signal hr_mnt_writedata           : std_logic_vector(15 downto 0);
signal hr_mnt_byteenable          : std_logic_vector( 1 downto 0);
signal hr_mnt_burstcount          : std_logic_vector( 7 downto 0);
signal hr_mnt_readdata            : std_logic_vector(15 downto 0);
signal hr_mnt_readdatavalid       : std_logic;
signal hr_mnt_waitrequest         : std_logic;

-- D81 enable: packed slave buses for the 3-master HyperRAM arbiter (avm_arbit_general)
-- slave index 0 = REU, 1 = CRT, 2 = MOUNT
signal hr_arb_write               : std_logic_vector( 2 downto 0);
signal hr_arb_read                : std_logic_vector( 2 downto 0);
signal hr_arb_address             : std_logic_vector(95 downto 0);
signal hr_arb_writedata           : std_logic_vector(47 downto 0);
signal hr_arb_byteenable          : std_logic_vector( 5 downto 0);
signal hr_arb_burstcount          : std_logic_vector(23 downto 0);
signal hr_arb_readdata            : std_logic_vector(47 downto 0);
signal hr_arb_readdatavalid       : std_logic_vector( 2 downto 0);
signal hr_arb_waitrequest         : std_logic_vector( 2 downto 0);

signal hr_hdmi_ff                 : std_logic;

---------------------------------------------------------------------------------------------
-- qnice_clk
---------------------------------------------------------------------------------------------

-- OSM selections within qnice_osm_control_i: one bit per OPTM_ITEMS line
-- (flat index, see config.vhd). The values below are machine-checked
-- against the menu structure: run "python3 M2M/rom/tests/menu_test.py verify"
-- after every menu change.
constant C_MENU_INTERNAL_1581 : natural := 3;   -- internal MEGA65 1581 physical drive backs drive 8 (issue #90)
constant C_MENU_EXP_PORT_HW   : natural := 8;
constant C_MENU_SIM_CRT       : natural := 9;
constant C_MENU_SIM_REU       : natural := 11;
-- Model submenu: machine mode and turbo are not yet wired, see #181
-- C_MENU_MODEL is the flat index of the " Model: %s" submenu opener; the
-- custom SUBMENU_SUMMARY callback in m2m-rom.asm uses it to recognize that line
constant C_MENU_MODEL         : natural := 15;
constant C_MENU_MACHINE_PAL   : natural := 18;
constant C_MENU_MACHINE_NTSC  : natural := 19;
constant C_MENU_TURBO_OFF     : natural := 23;
constant C_MENU_TURBO_C128    : natural := 24;
constant C_MENU_TURBO_SMART   : natural := 25;
constant C_MENU_TURBO_2X      : natural := 28;
constant C_MENU_TURBO_3X      : natural := 29;
constant C_MENU_TURBO_4X      : natural := 30;
constant C_MENU_FLIP_JOYS     : natural := 33;
-- HDMI submenu; the NTSC display modes (59.94 Hz) and the NTSC
-- flicker-free twin are not yet wired, see #181/#105, neither is raw
-- 50.1 Hz
constant C_MENU_HDMI_16_9_50  : natural := 37;
constant C_MENU_HDMI_16_9_5994 : natural := 38;
constant C_MENU_HDMI_4_3_50   : natural := 39;
constant C_MENU_HDMI_4_3_5994 : natural := 40;
constant C_MENU_HDMI_5_4_50   : natural := 41;
constant C_MENU_HDMI_5_4_5994 : natural := 42;
constant C_MENU_HDMI_FF       : natural := 44;
constant C_MENU_HDMI_FF_NTSC  : natural := 45;
constant C_MENU_HDMI_DVI      : natural := 46;
-- HDMI Filter submenu (nested inside the HDMI submenu; replaces V1's CRT
-- emulation single-toggle). The selection is interpreted entirely by the
-- core's m2m-rom.asm (LOAD_HDMI_FILTER), which writes M2M$ASCAL_MODE for
-- native modes and loads the matching (H, V) coefficient pair via
-- M2M$LOAD_POLYPHASE for polyphase modes. ASCAL_USAGE=1 in config.vhd
-- routes mode control to QNICE directly.
constant C_MENU_HDMI_FLT_NO_FILTER     : natural := 50;  -- ascal native NEAREST (intentional #223 wonky-pixel look)
constant C_MENU_HDMI_FLT_SHARP         : natural := 51;  -- ascal native SBILINEAR (cubic-warped Sharp Bilinear)
constant C_MENU_HDMI_FLT_BICUBIC       : natural := 52;  -- ascal native BICUBIC
constant C_MENU_HDMI_FLT_SMOOTH        : natural := 53;
constant C_MENU_HDMI_FLT_LANCZOS       : natural := 54;
constant C_MENU_HDMI_FLT_SCANLINES     : natural := 55;  -- default; bit-identical to V1's CRT emulation
constant C_MENU_HDMI_FLT_CRT_SVIDEO    : natural := 56;
constant C_MENU_HDMI_FLT_CRT_COMPOSITE : natural := 57;
constant C_MENU_HDMI_ZOOM     : natural := 60;
constant C_MENU_HDMI_RAW50    : natural := 61;           -- not yet wired
-- VGA submenu
constant C_MENU_VGA_STD       : natural := 67;
constant C_MENU_VGA_15KHZHSVS : natural := 71;
constant C_MENU_VGA_15KHZCS   : natural := 72;
-- SID submenu
constant C_MENU_MONO_6581     : natural := 80;
constant C_MENU_MONO_8580     : natural := 81;
constant C_MENU_STEREO_L6R6   : natural := 85;
constant C_MENU_STEREO_L6R8   : natural := 86;
constant C_MENU_STEREO_L8R6   : natural := 87;
constant C_MENU_STEREO_L8R8   : natural := 88;
constant C_MENU_STEREO_R_D420 : natural := 92;
constant C_MENU_STEREO_R_D500 : natural := 93;
constant C_MENU_STEREO_R_DE00 : natural := 94;
constant C_MENU_STEREO_R_DF00 : natural := 95;
constant C_MENU_IMPROVE_AUDIO : natural := 98;
constant C_MENU_IEC           : natural := 101;
-- Kernal submenu
constant C_MENU_KERNAL        : natural := 102; -- flat index of the " Kernal: %s" submenu opener used by the custom SUBMENU_SUMMARY callback in m2m-rom.asm 
constant C_MENU_KERNAL_STD    : natural := 105;
constant C_MENU_KERNAL_GS     : natural := 106;
constant C_MENU_KERNAL_JAPAN  : natural := 107;
constant C_MENU_KERNAL_JIFFY  : natural := 108;
-- Volume submenu (master volume slider, 5% steps): decoded into main_volume and
-- applied as a perceptual attenuation in main.vhd (see volume_decode_proc below)
subtype C_MENU_VOLUME is natural range 134 downto 114;
-- Advanced Settings submenu
constant C_MENU_RTC_GEOS      : natural := 140;         -- GEOS Real-Time-Clock, see #133, #164 and #187
subtype C_MENU_OSM_SCALING is natural range 152 downto 144;
constant C_MENU_8521          : natural := 155;
-- There is deliberately no VIC-II model selection: we stick to the hardcoded old-HMOS variant
-- of fpga64_sid_iec.vhd. See issue #120 and doc/vic_ii_variants.md
subtype R_MENU_RRNET is natural range 162 downto 159;

-- HyperRAM-backed disk-image mount buffer. QNICE 4k-window byte protocol.
signal qnice_mnt_qnice_ce           : std_logic;
signal qnice_mnt_qnice_we           : std_logic;
signal qnice_mnt_qnice_data         : std_logic_vector(15 downto 0);
signal qnice_mnt_qnice_wait         : std_logic;

-- Custom Kernal access: C64 ROM
signal qnice_c64rom_we              : std_logic;
signal qnice_c64rom_addr            : std_logic_vector(13 downto 0);
signal qnice_c64rom_data_to         : std_logic_vector(7 downto 0);
signal qnice_c64rom_data_from       : std_logic_vector(7 downto 0);

-- Custom DOS access: Simulated C1541
signal qnice_c1541rom_we            : std_logic;
signal qnice_c1541rom_addr          : std_logic_vector(15 downto 0);
signal qnice_c1541rom_data_to       : std_logic_vector(7 downto 0);
signal qnice_c1541rom_data_from     : std_logic_vector(7 downto 0);

-- Custom RR-NET MK3 ROM (simulated)
signal qnice_rrnetmk3_we            : std_logic;
signal qnice_rrnetmk3_addr          : std_logic_vector(12 downto 0);
signal qnice_rrnetmk3_data_to       : std_logic_vector(7 downto 0);
signal qnice_rrnetmk3_data_from     : std_logic_vector(7 downto 0);

-- Physical internal 1581 read-only diagnostic device (issue #90; C_DEV_C64_PHYS1581)
signal phys_diag_ce                 : std_logic;
signal phys_diag_data               : std_logic_vector(15 downto 0);

-- Signals for multiplexing the C64's RAM between C_DEV_C64_RAM and C_DEV_C64_PRG
signal qnice_c64_ramx_we            : std_logic;
signal qnice_c64_ramx_addr          : std_logic_vector(15 downto 0);
signal qnice_c64_ramx_d_to          : std_logic_vector(7 downto 0);
signal qnice_c64_ramx_d_from        : std_logic_vector(7 downto 0);

-- QNICE signals passed down to main.vhd to handle IEC drives using vdrives.vhd
signal qnice_c64_qnice_ce           : std_logic;
signal qnice_c64_qnice_we           : std_logic;
signal qnice_c64_qnice_data         : std_logic_vector(15 downto 0);

-- QNICE signals for the PRG loader
signal qnice_prg_qnice_ce           : std_logic;
signal qnice_prg_qnice_we           : std_logic;
signal qnice_prg_qnice_data         : std_logic_vector(15 downto 0);
signal qnice_prg_wait               : std_logic;
signal qnice_prg_c64ram_we          : std_logic;
signal qnice_prg_c64ram_addr        : std_logic_vector(15 downto 0);
signal qnice_prg_c64ram_d_to        : std_logic_vector(7 downto 0);
signal qnice_prg_c64ram_d_frm       : std_logic_vector(7 downto 0);
signal qnice_reset_for_prgloader    : std_logic;
signal qnice_reset_from_prgloader   : std_logic;
signal qnice_prg_trigger_run        : std_logic;

-- QNICE signals passed down to sw_cartridge_wrapper.vhd to handle CRT files
signal qnice_crt_qnice_ce           : std_logic;
signal qnice_crt_qnice_we           : std_logic;
signal qnice_crt_qnice_data         : std_logic_vector(15 downto 0);
signal qnice_crt_qnice_wait         : std_logic;

begin

   -- MMCME2_ADV clock generators
   --   C64 PAL: 31.528 MHz (main) and 63.056 MHz (video)
   --            HDMI: Flicker-free: 0.25% slower
   clk_gen : entity work.clk
      port map (
         sys_clk_i         => clk_i,           -- expects 100 MHz

         core_speed_i      => hr_core_speed,   -- 0=PAL/original C64, 1=PAL/HDMI flicker-free, 2=NTSC

         main_clk_o        => main_clk_o,      -- core's clock
         main_rst_o        => main_rst_o       -- core's reset, synchronized
      ); -- clk_gen

   -- Video clock is the same as core clock
   video_clk_o <= main_clk_o;
   video_rst_o <= main_rst_o;

   ---------------------------------------------------------------------------------------------
   -- hr_clk (HyperRAM clock)
   ---------------------------------------------------------------------------------------------

   -- Switch between two clock rates for the CORE, corresponding to frame rates that
   -- closely "embrace" the output rate of exactly 50 Hz (determined by the HDMI resolution).
   process (hr_clk_i)
   begin
      if rising_edge(hr_clk_i) then
         if hr_low_i = '1' then     -- the core is too slow ...
            hr_core_speed <= "00";  -- ... switch to PAL original (50.124 Hz)
         end if;
         if hr_high_i = '1' then    -- the core is too fast ...
            hr_core_speed <= "01";  -- ... switch to PAL slow (49.999 Hz)
         end if;
         if hr_hdmi_ff = '0' then
            hr_core_speed <= "00";
         end if;
      end if;
   end process;

   -- 3-master HyperRAM arbiter (REU, CRT, MOUNT). avm_arbit_general uses
   -- flattened slave vectors; slave index k occupies bits ((k+1)*W-1 downto k*W), so a
   -- VHDL "a & b & c" concatenation puts a at the MSBs. Index 0 = REU (LSBs), 1 = CRT,
   -- 2 = MOUNT. The new MOUNT slave only touches HyperRAM during disk mount/serve/flush
   -- (QNICE-paced, <1% of HyperRAM bandwidth) so it cannot starve the real-time REU.
   hr_arb_write      <= hr_mnt_write      & hr_crt_write      & hr_reu_write;
   hr_arb_read       <= hr_mnt_read       & hr_crt_read       & hr_reu_read;
   hr_arb_address    <= hr_mnt_address    & hr_crt_address    & hr_reu_address;
   hr_arb_writedata  <= hr_mnt_writedata  & hr_crt_writedata  & hr_reu_writedata;
   hr_arb_byteenable <= hr_mnt_byteenable & hr_crt_byteenable & hr_reu_byteenable;
   hr_arb_burstcount <= hr_mnt_burstcount & hr_crt_burstcount & hr_reu_burstcount;

   hr_reu_readdata      <= hr_arb_readdata(15 downto  0);
   hr_crt_readdata      <= hr_arb_readdata(31 downto 16);
   hr_mnt_readdata      <= hr_arb_readdata(47 downto 32);
   hr_reu_readdatavalid <= hr_arb_readdatavalid(0);
   hr_crt_readdatavalid <= hr_arb_readdatavalid(1);
   hr_mnt_readdatavalid <= hr_arb_readdatavalid(2);
   hr_reu_waitrequest   <= hr_arb_waitrequest(0);
   hr_crt_waitrequest   <= hr_arb_waitrequest(1);
   hr_mnt_waitrequest   <= hr_arb_waitrequest(2);

   i_avm_arbit : entity work.avm_arbit_general
      generic map (
         G_NUM_SLAVES   => 3,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i                 => hr_clk_i,
         rst_i                 => hr_rst_i,
         s_avm_write_i         => hr_arb_write,
         s_avm_read_i          => hr_arb_read,
         s_avm_address_i       => hr_arb_address,
         s_avm_writedata_i     => hr_arb_writedata,
         s_avm_byteenable_i    => hr_arb_byteenable,
         s_avm_burstcount_i    => hr_arb_burstcount,
         s_avm_readdata_o      => hr_arb_readdata,
         s_avm_readdatavalid_o => hr_arb_readdatavalid,
         s_avm_waitrequest_o   => hr_arb_waitrequest,
         m_avm_write_o         => hr_core_write_o,
         m_avm_read_o          => hr_core_read_o,
         m_avm_address_o       => hr_core_address_o,
         m_avm_writedata_o     => hr_core_writedata_o,
         m_avm_byteenable_o    => hr_core_byteenable_o,
         m_avm_burstcount_o    => hr_core_burstcount_o,
         m_avm_readdata_i      => hr_core_readdata_i,
         m_avm_readdatavalid_i => hr_core_readdatavalid_i,
         m_avm_waitrequest_i   => hr_core_waitrequest_i
      ); -- i_avm_arbit

   ---------------------------------------------------------------------------------------------
   -- main_clk (C64 MiSTer Core clock)
   ---------------------------------------------------------------------------------------------

   c64_ntsc          <= '0'; -- @TODO: For now, we hardcode PAL mode

   -- Select C64's ROM: 0=Custom, 1=Standard, 2=GS, 3=Japan
   c64_rom <= "00" when main_osm_control_i(C_MENU_KERNAL_JIFFY)   else
              "10" when main_osm_control_i(C_MENU_KERNAL_GS)      else
              "11" when main_osm_control_i(C_MENU_KERNAL_JAPAN)   else
              "01";   -- Use standard ROM as default

   -- needs to be in main clock domain
   c64_clock_speed   <= CORE_CLK_SPEED;

   -- Mode selection for Expansion Port (aka Cartridge Port):
   -- bit 0 = 0: Use the MEGA65's actual hardware slot
   -- bit 0 = 1: Simulate a cartridge by using a cartridge from from the SD card (.crt file)
   -- bit 1 = 0: No simulated REU
   -- bit 1 = 1: Simulate a 1750 REU with 512KB
   -- bits  3-2: Simulated RR-Net ethernet cartridge
   c64_exp_port_mode(0) <= main_osm_control_i(C_MENU_SIM_CRT);
   c64_exp_port_mode(1) <= main_osm_control_i(C_MENU_SIM_REU);
   c64_exp_port_mode(3 downto 2) <=
     "01" when main_osm_control_i(R_MENU_RRNET) = "0010" else -- Enabled, no MK3 ROM
     "10" when main_osm_control_i(R_MENU_RRNET) = "0100" else -- Enabled, standard MK3 ROM
     "11" when main_osm_control_i(R_MENU_RRNET) = "1000" else -- Enabled, custom MK3 ROM
     "00";                                                    -- Disabled

   -- Physical internal 1581 (issue #90): drive 8 uses the real internal floppy
   phys_1581_en <= main_osm_control_i(C_MENU_INTERNAL_1581);

   -- SID version, 0=6581, 1=8580, low bit = left SID
   sid_setup <= "00" when main_osm_control_i(C_MENU_MONO_6581)    else
                "11" when main_osm_control_i(C_MENU_MONO_8580)    else
                "00" when main_osm_control_i(C_MENU_STEREO_L6R6)  else
                "10" when main_osm_control_i(C_MENU_STEREO_L6R8)  else
                "01" when main_osm_control_i(C_MENU_STEREO_L8R6)  else
                "11" when main_osm_control_i(C_MENU_STEREO_L8R8)  else
                "00";

   -- Right SID Port: 0=same as left, 1=DE00, 2=D420, 3=D500, 4=DF00
   sid_port  <= 0 when main_osm_control_i(C_MENU_MONO_6581) or main_osm_control_i(C_MENU_MONO_8580) else
                1 when main_osm_control_i(C_MENU_STEREO_R_DE00) else
                2 when main_osm_control_i(C_MENU_STEREO_R_D420) else
                3 when main_osm_control_i(C_MENU_STEREO_R_D500) else
                4 when main_osm_control_i(C_MENU_STEREO_R_DF00) else
                0;

   -- Master volume: the OSM "Volume" slider (C_MENU_VOLUME) is a 21-way radio
   -- group in 5% steps. Its lowest bit (C_MENU_VOLUME'low) is 100% and its
   -- highest bit is 0%, so translate the one-hot selection into a 0..20 step
   -- index (0 = 0%/mute, 20 = 100%). Default to 100% if nothing is (yet)
   -- selected. The perceptual, loudness-linear attenuation itself is applied in
   -- main.vhd (see C_VOL_LUT there), so it affects HDMI and analog audio alike.
   volume_decode_proc : process (all)
   begin
      main_volume <= 20;                                        -- default 100%
      for b in C_MENU_VOLUME'low to C_MENU_VOLUME'high loop
         if main_osm_control_i(b) = '1' then
            main_volume <= C_MENU_VOLUME'high - b;              -- bit 114 -> 20 (100%) .. bit 134 -> 0 (0%)
         end if;
      end loop;
   end process volume_decode_proc;

   -- MEGA65's power led: By default, it is on and glows green when the MEGA65 is powered on.
   -- We switch it to blue when a long reset is detected and as long as the user keeps pressing the preset button
   main_power_led_o     <= '1';
   main_power_led_col_o <= x"0000FF" when main_reset_m2m_i else x"00FF00";

   -- main.vhd contains the actual MiSTer core
   i_main : entity work.main
      generic map (
         G_BOARD => G_BOARD,    -- Which platform are we running on.
         G_VDNUM => C_VDNUM
      )
      port map (
         clk_main_i             => main_clk_o,
         
         -- see RESET SEMANTICS in main.vhd
         -- reset_soft_i minimum pulse length is 32 clock cycles
         reset_soft_i           => main_reset_core_i or main_reset_core,
         reset_hard_i           => main_reset_m2m_i or main_reset_from_prgloader,

         -- Soft reset routed to cartridge_inst (in main.vhd): deliberately
         -- excludes sw_cartridge_wrapper's local main_reset_core, so the
         -- wrapper's post-parse pulse does NOT wipe the just-installed cart
         -- state. See cartridge_inst port map comment block in main.vhd.
         cart_soft_reset_i      => main_reset_core_i,
         cart_soft_reset_o      => main_cart_soft_reset,

         pause_i                => main_pause_core_i,
         trigger_run_i          => main_prg_trigger_run,

         ---------------------------
         -- Configuration options
         ---------------------------

         -- Select C64's ROM: 0=Custom, 1=Standard, 2=GS, 3=Japan
         c64_rom_i              => c64_rom,

         -- Video mode selection:
         -- c64_ntsc_i: PAL/NTSC switch
         -- clk_main_speed_i: The core's clock speed depends on mode and needs to be very exact for avoiding clock drift
         -- video_retro15kHz_i: Analog video output configuration: Horizontal sync frequency: '0'  =30 kHz ("normal" on "modern" analog monitors), '1'=retro 15 kHz
         c64_ntsc_i             => c64_ntsc,
         clk_main_speed_i       => c64_clock_speed,
         video_retro15kHz_i     => main_osm_control_i(C_MENU_VGA_15KHZHSVS) or main_osm_control_i(C_MENU_VGA_15KHZCS),

         -- SID and CIA versions
         c64_sid_ver_i          => sid_setup,
         c64_sid_port_i         => to_unsigned(sid_port, 3),
         c64_cia_ver_i          => main_osm_control_i(C_MENU_8521),

         -- GEOS Real-Time-Clock: connects the emulated PCF8583 to the cassette port. Defaults to
         -- off, because a connected RTC looks like an attached datasette to the C64 and that
         -- breaks some software. See issues #133, #164 and #187.
         c64_rtc_geos_i         => main_osm_control_i(C_MENU_RTC_GEOS),

         -- Master volume (OSM "Volume" slider): 0..20 step index = 0%..100%
         audio_volume_i         => main_volume,

         -- Mode selection for Expansion Port (aka Cartridge Port):
         -- bit 0: 1 = Simulate cartridge (.CRT file), 0 = use Physical port
         -- bit 1: Simulate REU
         -- bit 2: Simulate RR-NET
         c64_exp_port_mode_i    => c64_exp_port_mode,

         -- Current date/time from RTC
         rtc_i                  => main_rtc_i,

         ---------------------------
         -- Commodore 64 I/O ports
         ---------------------------

         -- M2M Keyboard interface
         kb_key_num_i           => main_kb_key_num_i,
         kb_key_pressed_n_i     => main_kb_key_pressed_n_i,

         -- MEGA65 joysticks and paddles
         joy_1_up_n_i           => main_joy_1_up_n_i ,
         joy_1_down_n_i         => main_joy_1_down_n_i,
         joy_1_left_n_i         => main_joy_1_left_n_i,
         joy_1_right_n_i        => main_joy_1_right_n_i,
         joy_1_fire_n_i         => main_joy_1_fire_n_i,
         joy_1_up_n_o           => main_joy_1_up_n_o ,
         joy_1_down_n_o         => main_joy_1_down_n_o,
         joy_1_left_n_o         => main_joy_1_left_n_o,
         joy_1_right_n_o        => main_joy_1_right_n_o,
         joy_1_fire_n_o         => main_joy_1_fire_n_o,
         joy_2_up_n_i           => main_joy_2_up_n_i,
         joy_2_down_n_i         => main_joy_2_down_n_i,
         joy_2_left_n_i         => main_joy_2_left_n_i,
         joy_2_right_n_i        => main_joy_2_right_n_i,
         joy_2_fire_n_i         => main_joy_2_fire_n_i,
         joy_2_up_n_o           => main_joy_2_up_n_o ,
         joy_2_down_n_o         => main_joy_2_down_n_o,
         joy_2_left_n_o         => main_joy_2_left_n_o,
         joy_2_right_n_o        => main_joy_2_right_n_o,
         joy_2_fire_n_o         => main_joy_2_fire_n_o,
         pot1_x_i               => main_pot1_x_i,
         pot1_y_i               => main_pot1_y_i,
         pot2_x_i               => main_pot2_x_i,
         pot2_y_i               => main_pot2_y_i,

         -- Video output
         -- This is PAL 720x576 @ 50 Hz (pixel clock 27 MHz), but synchronized to main_clk (54 MHz).
         video_ce_o             => video_ce_o,
         video_ce_ovl_o         => video_ce_ovl_o,
         video_red_o            => video_red_o,
         video_green_o          => video_green_o,
         video_blue_o           => video_blue_o,
         video_vs_o             => video_vs_o,
         video_hs_o             => video_hs_o,
         video_hblank_o         => video_hblank_o,
         video_vblank_o         => video_vblank_o,

         -- Audio output (PCM format, signed values)
         audio_left_o           => main_audio_left_o,
         audio_right_o          => main_audio_right_o,

         -- C64 drive led
         drive_led_o            => main_drive_led_o,
         drive_led_col_o        => main_drive_led_col_o,

         -- C64 RAM
         c64_ram_addr_o         => main_ram_addr,
         c64_ram_data_o         => main_ram_data_from_c64,
         c64_ram_we_o           => main_ram_we,
         c64_ram_data_i         => unsigned(main_ram_data_to_c64),

         -- C64 IEC handled by QNICE
         c64_clk_sd_i           => qnice_clk_i,   -- "sd card write clock" for floppy drive internal dual clock RAM buffer
         c64_qnice_addr_i       => qnice_dev_addr_i,
         c64_qnice_data_i       => qnice_dev_data_i,
         c64_qnice_data_o       => qnice_c64_qnice_data,
         c64_qnice_ce_i         => qnice_c64_qnice_ce,
         c64_qnice_we_i         => qnice_c64_qnice_we,

         -- CBM-488/IEC serial (hardware) port
         iec_hardware_port_en_i => main_osm_control_i(C_MENU_IEC),
         iec_reset_n_o          => iec_reset_n_o,
         iec_atn_n_o            => iec_atn_n_o,
         iec_clk_en_o           => iec_clk_en_o,
         iec_clk_n_i            => iec_clk_n_i,
         iec_clk_n_o            => iec_clk_n_o,
         iec_data_en_o          => iec_data_en_o,
         iec_data_n_i           => iec_data_n_i,
         iec_data_n_o           => iec_data_n_o,
         iec_srq_en_o           => iec_srq_en_o,
         iec_srq_n_i            => iec_srq_n_i,
         iec_srq_n_o            => iec_srq_n_o,

         -- Physical internal 1581 (issue #90): mode bit, QNICE-domain reset, board pins
         phys_1581_en_i         => phys_1581_en,
         c64_rst_sd_i           => qnice_rst_i,
         f_rdata_i              => f_rdata_i,
         f_index_i              => f_index_i,
         f_track0_i             => f_track0_i,
         f_writeprotect_i       => f_writeprotect_i,
         f_diskchanged_i        => f_diskchanged_i,
         f_motora_o             => f_motora_o,
         f_selecta_o            => f_selecta_o,
         f_side1_o              => f_side1_o,
         f_stepdir_o            => f_stepdir_o,
         f_step_o               => f_step_o,
         f_density_o            => f_density_o,

         -- Physical internal 1581 read-only QNICE diagnostic device (issue #90)
         phys_diag_ce_i         => phys_diag_ce,
         phys_diag_addr_i       => qnice_dev_addr_i(7 downto 0),
         phys_diag_data_o       => phys_diag_data,

         -- C64 Expansion Port (aka Cartridge Port)
         cart_en_o              => cart_en_o,
         cart_phi2_o            => cart_phi2_o,
         cart_dotclock_o        => cart_dotclock_o,
         cart_dma_i             => cart_dma_i,
         cart_reset_oe_o        => cart_reset_oe_o,
         cart_reset_i           => cart_reset_i,
         cart_reset_o           => cart_reset_o,
         cart_game_oe_o         => cart_game_oe_o,
         cart_game_i            => cart_game_i,
         cart_game_o            => cart_game_o,
         cart_exrom_oe_o        => cart_exrom_oe_o,
         cart_exrom_i           => cart_exrom_i,
         cart_exrom_o           => cart_exrom_o,
         cart_nmi_oe_o          => cart_nmi_oe_o,
         cart_nmi_i             => cart_nmi_i,
         cart_nmi_o             => cart_nmi_o,
         cart_irq_oe_o          => cart_irq_oe_o,
         cart_irq_i             => cart_irq_i,
         cart_irq_o             => cart_irq_o,
         cart_roml_oe_o         => cart_roml_oe_o,
         cart_roml_i            => cart_roml_i,
         cart_roml_o            => cart_roml_o,
         cart_romh_oe_o         => cart_romh_oe_o,
         cart_romh_i            => cart_romh_i,
         cart_romh_o            => cart_romh_o,
         cart_ctrl_oe_o         => cart_ctrl_oe_o,
         cart_ba_i              => cart_ba_i,
         cart_rw_i              => cart_rw_i,
         cart_io1_i             => cart_io1_i,
         cart_io2_i             => cart_io2_i,
         cart_ba_o              => cart_ba_o,
         cart_rw_o              => cart_rw_o,
         cart_io1_o             => cart_io1_o,
         cart_io2_o             => cart_io2_o,
         cart_addr_oe_o         => cart_addr_oe_o,
         cart_a_i               => cart_a_i,
         cart_a_o               => cart_a_o,
         cart_data_oe_o         => cart_data_oe_o,
         cart_d_i               => cart_d_i,
         cart_d_o               => cart_d_o,

         -- RAM Expansion Unit (REU)
         avm_waitrequest_i   => main_avm_reu_waitrequest,
         avm_write_o         => main_avm_reu_write,
         avm_read_o          => main_avm_reu_read,
         avm_address_o       => main_avm_reu_address,
         avm_writedata_o     => main_avm_reu_writedata,
         avm_byteenable_o    => main_avm_reu_byteenable,
         avm_burstcount_o    => main_avm_reu_burstcount,
         avm_readdata_i      => main_avm_reu_readdata,
         avm_readdatavalid_i => main_avm_reu_readdatavalid,

         -- Support for software based cartridges (aka ".CRT" files)
         cartridge_loading_i    => main_crt_loading,
         cartridge_id_i         => main_crt_id,
         cartridge_exrom_i      => main_crt_exrom,
         cartridge_game_i       => main_crt_game,
         cartridge_size_i       => main_crt_size,
         cartridge_bank_laddr_i => main_crt_bank_laddr,
         cartridge_bank_size_i  => main_crt_bank_size,
         cartridge_bank_num_i   => main_crt_bank_num,
         cartridge_bank_raddr_i => main_crt_bank_raddr,
         cartridge_bank_wr_i    => main_crt_bank_wr,
         crt_bank_wait_i        => main_crt_bank_wait,
         crt_lo_ram_data_i      => main_crt_lo_ram_data,
         crt_hi_ram_data_i      => main_crt_hi_ram_data,
         crt_ioe_ram_data_i     => main_crt_ioe_ram_data,
         crt_iof_ram_data_i     => main_crt_iof_ram_data,
         crt_addr_bus_o         => main_crt_addr_bus,
         crt_ioe_we_o           => main_crt_ioe_we,
         crt_iof_we_o           => main_crt_iof_we,
         crt_bank_lo_o          => main_crt_bank_lo,
         crt_bank_hi_o          => main_crt_bank_hi,
         crt_we_o               => main_crt_we,
         crt_ram_data_i         => main_crt_ram_data,

         -- Custom Kernal: C64 ROM (in QNICE clock domain via c64_clk_sd_i)
         c64rom_we_i            => qnice_c64rom_we,
         c64rom_addr_i          => qnice_c64rom_addr,
         c64rom_data_i          => qnice_c64rom_data_to,
         c64rom_data_o          => qnice_c64rom_data_from,

         -- Access custom DOS for the simulated C1541 (in QNICE clock domain via c64_clk_sd_i)
         c1541rom_we_i          => qnice_c1541rom_we,
         c1541rom_addr_i        => qnice_c1541rom_addr,
         c1541rom_data_i        => qnice_c1541rom_data_to,
         c1541rom_data_o        => qnice_c1541rom_data_from,

         -- Custom RRNET MK3 ROM (simulated)
         rrnetmk3_we_i          => qnice_rrnetmk3_we,
         rrnetmk3_addr_i        => qnice_rrnetmk3_addr,
         rrnetmk3_data_i        => qnice_rrnetmk3_data_to,
         rrnetmk3_data_o        => qnice_rrnetmk3_data_from,

         eth_rx_ready_o         => eth_rx_ready_o,
         eth_rx_valid_i         => eth_rx_valid_i,
         eth_rx_last_i          => eth_rx_last_i,
         eth_rx_data_i          => eth_rx_data_i,
         eth_tx_ready_i         => eth_tx_ready_i,
         eth_tx_valid_o         => eth_tx_valid_o,
         eth_tx_last_o          => eth_tx_last_o,
         eth_tx_data_o          => eth_tx_data_o,
         eth_rx_cnt_drop_i      => eth_rx_cnt_drop_i
      ); -- i_main

   ---------------------------------------------------------------------------------------------
   -- Audio and video settings (QNICE clock domain)
   ---------------------------------------------------------------------------------------------

   -- Due to a discussion on the MEGA65 discord (https://discord.com/channels/719326990221574164/794775503818588200/1039457688020586507)
   -- we decided to choose a naming convention for the PAL modes that might be more intuitive for the end users than it is
   -- for the programmers: "4:3" means "meant to be run on a 4:3 monitor", "5:4 on a 5:4 monitor".
   -- The technical reality is though, that in our "5:4" mode we are actually doing a 4/3 aspect ratio adjustment
   -- while in the 4:3 mode we are outputting a 5:4 image. This is kind of odd, but it seemed that our 4/3 aspect ratio
   -- adjusted image looks best on a 5:4 monitor and the other way round.
   -- Not sure if this will stay forever or if we will come up with a better naming convention.
   -- The V6 menu (#189) removed the PAL-clocked "16:9 720p 60 Hz" mode (see #105): the
   -- NTSC-rate modes are reserved for the upcoming NTSC support (#181). The NTSC menu
   -- entries (C_MENU_HDMI_*_5994) exist already, but they are deliberately not wired up yet.
   qnice_video_mode_o <= C_VIDEO_HDMI_5_4_50   when qnice_osm_control_i(C_MENU_HDMI_5_4_50)  = '1' else
                         C_VIDEO_HDMI_4_3_50   when qnice_osm_control_i(C_MENU_HDMI_4_3_50)  = '1' else
                         C_VIDEO_HDMI_16_9_50;                       -- C_MENU_HDMI_16_9_50

   -- Use On-Screen-Menu selections to configure several audio and video settings
   -- Video and audio mode control
   qnice_dvi_o                <= qnice_osm_control_i(C_MENU_HDMI_DVI);        -- 0=HDMI (with sound), 1=DVI (no sound)

   -- no scandoubler when using the retro 15 kHz RGB mode
   qnice_scandoubler_o        <= (not qnice_osm_control_i(C_MENU_VGA_15KHZHSVS)) and
                                 (not qnice_osm_control_i(C_MENU_VGA_15KHZCS));

   qnice_audio_mute_o         <= '0';                                         -- audio is not muted
   qnice_audio_filter_o       <= qnice_osm_control_i(C_MENU_IMPROVE_AUDIO);   -- 0 = raw audio, 1 = use filters from globals.vhd
   qnice_zoom_crop_o          <= qnice_osm_control_i(C_MENU_HDMI_ZOOM);       -- 0 = no zoom/crop
   qnice_retro15kHz_o         <= qnice_osm_control_i(C_MENU_VGA_15KHZHSVS) or qnice_osm_control_i(C_MENU_VGA_15KHZCS);
   qnice_csync_o              <= qnice_osm_control_i(C_MENU_VGA_15KHZCS);     -- Composite sync (CSYNC)
   qnice_osm_cfg_scaling_o    <= qnice_osm_control_i(C_MENU_OSM_SCALING);

   -- In config.vhd, we chose ASCAL_USAGE = 1 (AUSE_CUSTOM), which hands the control over ASCAL
   -- modes to our core-specific m2m-rom.asm. There, we are handling the multiple HDMI Filter
   -- choices. This means: The following three lines are ignored by M2M during runtime
   qnice_ascal_mode_o         <= "00";
   qnice_ascal_polyphase_o    <= '0';
   qnice_ascal_triplebuf_o    <= '0';

   -- Flip joystick ports (i.e. the joystick in port 2 is used as joystick 1 and vice versa)
   qnice_flip_joyports_o      <= qnice_osm_control_i(C_MENU_FLIP_JOYS);

   ---------------------------------------------------------------------------------------------
   -- Core specific device handling (QNICE clock domain, device IDs in globals.vhd)
   ---------------------------------------------------------------------------------------------

   core_specific_devices : process(all)
   begin
      -- avoid latches
      qnice_dev_data_o           <= x"EEEE";
      qnice_dev_wait_o           <= '0';
      qnice_c64_qnice_ce         <= '0';
      qnice_c64_qnice_we         <= '0';
      qnice_mnt_qnice_ce         <= '0';
      qnice_mnt_qnice_we         <= '0';
      qnice_prg_qnice_ce         <= '0';
      qnice_prg_qnice_we         <= '0';
      qnice_prg_c64ram_d_frm     <= (others => '0');
      qnice_crt_qnice_ce         <= '0';
      qnice_crt_qnice_we         <= '0';
      qnice_c64_ramx_addr        <= (others => '0');
      qnice_c64_ramx_d_to        <= (others => '0');
      qnice_c64_ramx_we          <= '0';
      qnice_c64rom_we            <= '0';
      qnice_c64rom_addr          <= (others => '0');
      qnice_c64rom_data_to       <= (others => '0');
      qnice_c1541rom_we          <= '0';
      qnice_c1541rom_addr        <= (others => '0');
      qnice_c1541rom_data_to     <= (others => '0');
      qnice_rrnetmk3_we          <= '0';
      qnice_rrnetmk3_addr        <= (others => '0');
      qnice_rrnetmk3_data_to     <= (others => '0');
      phys_diag_ce               <= '0';

      case qnice_dev_id_i is
         -- C64 RAM
         when C_DEV_C64_RAM =>
            qnice_c64_ramx_addr        <= qnice_dev_addr_i(15 downto 0);
            qnice_c64_ramx_we          <= qnice_dev_we_i;
            qnice_c64_ramx_d_to        <= qnice_dev_data_i(7 downto 0);
            qnice_dev_data_o           <= x"00" & qnice_c64_ramx_d_from;

         -- C64 IEC drives
         when C_VD_DEVICE =>
            qnice_c64_qnice_ce         <= qnice_dev_ce_i;
            qnice_c64_qnice_we         <= qnice_dev_we_i;
            qnice_dev_data_o           <= qnice_c64_qnice_data;

         -- Disk mount buffer (now HyperRAM-backed; see i_mount_buf_wrapper). The byte
         -- data + wait-state come from the bridge, mirroring the CRT device arm below.
         when C_DEV_C64_MOUNT =>
            qnice_mnt_qnice_ce         <= qnice_dev_ce_i;
            qnice_mnt_qnice_we         <= qnice_dev_we_i;
            qnice_dev_data_o           <= qnice_mnt_qnice_data;
            qnice_dev_wait_o           <= qnice_mnt_qnice_wait;

         -- PRG file loader (*.PRG)
         when C_DEV_C64_PRG =>
            qnice_c64_ramx_addr        <= qnice_prg_c64ram_addr;
            qnice_c64_ramx_we          <= qnice_prg_c64ram_we;
            qnice_c64_ramx_d_to        <= qnice_prg_c64ram_d_to;
            qnice_prg_c64ram_d_frm     <= qnice_c64_ramx_d_from;
            qnice_prg_qnice_ce         <= qnice_dev_ce_i;
            qnice_prg_qnice_we         <= qnice_dev_we_i;
            qnice_dev_data_o           <= qnice_prg_qnice_data;
            qnice_dev_wait_o           <= qnice_prg_wait;

         -- SW cartridges (*.CRT)
         when C_DEV_C64_CRT =>
            qnice_crt_qnice_ce         <= qnice_dev_ce_i;
            qnice_crt_qnice_we         <= qnice_dev_we_i;
            qnice_dev_data_o           <= qnice_crt_qnice_data;
            qnice_dev_wait_o           <= qnice_crt_qnice_wait;

         -- Custom Kernal Access: C64 ROM
         when C_DEV_C64_KERNAL_C64 =>
            qnice_c64rom_addr          <= qnice_dev_addr_i(13 downto 0);
            qnice_c64rom_we            <= qnice_dev_we_i;
            qnice_dev_data_o           <= x"00" & qnice_c64rom_data_from;
            qnice_c64rom_data_to       <= qnice_dev_data_i(7 downto 0);

         -- Custom Kernal Access: C1541 ROM. Bit 15 of the shared drive-ROM address bus
         -- selects the engine inside iec_drive.sv: 0 = c1541 (16 KB), 1 = c1581 (32 KB).
         when C_DEV_C64_KERNAL_C1541 =>
            qnice_c1541rom_addr        <= '0' & qnice_dev_addr_i(14 downto 0);
            qnice_c1541rom_we          <= qnice_dev_we_i;
            qnice_dev_data_o           <= x"00" & qnice_c1541rom_data_from;
            qnice_c1541rom_data_to     <= qnice_dev_data_i(7 downto 0);

         -- Custom Kernal Access: C1581 ROM. Same shared carrier as the c1541
         -- ROM, but bit 15 = '1' steers writes/reads to the 1581's 32 KB DOS ROM window.
         when C_DEV_C64_KERNAL_C1581 =>
            qnice_c1541rom_addr        <= '1' & qnice_dev_addr_i(14 downto 0);
            qnice_c1541rom_we          <= qnice_dev_we_i;
            qnice_dev_data_o           <= x"00" & qnice_c1541rom_data_from;
            qnice_c1541rom_data_to     <= qnice_dev_data_i(7 downto 0);

         -- Physical internal 1581: read-only diagnostic register bank (issue #90).
         -- Mirrors the C_DEV_C64_RAM pattern: no wait-state, writes ignored inside
         -- the diag bank. Its QNICE port lives in i_main (same 50 MHz domain).
         when C_DEV_C64_PHYS1581 =>
            phys_diag_ce               <= qnice_dev_ce_i;
            qnice_dev_data_o           <= phys_diag_data;

         -- Custom RRNET MK3 ROM (simulated)
         when C_DEV_C64_RRNET_MK3 =>
            qnice_rrnetmk3_addr        <= qnice_dev_addr_i(12 downto 0);
            qnice_rrnetmk3_we          <= qnice_dev_we_i;
            qnice_dev_data_o           <= x"00" & qnice_rrnetmk3_data_from;
            qnice_rrnetmk3_data_to     <= qnice_dev_data_i(7 downto 0);

         when others => null;
      end case;
   end process core_specific_devices;

   -- PRG file loader
   i_prg_loader : entity work.prg_loader
      port map(
         qnice_clk_i       => qnice_clk_i,
         qnice_rst_i       => qnice_rst_i or qnice_reset_for_prgloader,
         qnice_addr_i      => qnice_dev_addr_i,
         qnice_data_i      => qnice_dev_data_i,
         qnice_ce_i        => qnice_prg_qnice_ce,
         qnice_we_i        => qnice_prg_qnice_we,
         qnice_data_o      => qnice_prg_qnice_data,
         qnice_wait_o      => qnice_prg_wait,

         c64ram_we_o       => qnice_prg_c64ram_we,
         c64ram_addr_o     => qnice_prg_c64ram_addr,
         c64ram_data_i     => qnice_prg_c64ram_d_frm,
         c64ram_data_o     => qnice_prg_c64ram_d_to,

         core_reset_o      => qnice_reset_from_prgloader,
         core_triggerrun_o => qnice_prg_trigger_run
      );

   ---------------------------------------------------------------------------------------------
   -- Dual Clocks
   ---------------------------------------------------------------------------------------------

   -- Clock Domain Crossing: CORE -> HyperRAM
   i_cdc_main2hr : entity work.cdc_stable
      generic map (
         G_REGISTER_SRC => true,
         G_DATA_SIZE    => 1
      )
      port map (
         src_clk_i     => main_clk_o,
         src_data_i(0) => main_osm_control_i(C_MENU_HDMI_FF),
         dst_clk_i     => hr_clk_i,
         dst_data_o(0) => hr_hdmi_ff
      ); -- i_cdc_main2hr

   -- Clock Domain Crossing: CORE -> QNICE
   i_cdc_main2qnice : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF => 2,
         WIDTH        => 1
      )
      port map (
         src_clk           => main_clk_o,
         src_in(0)         => main_reset_core_i or main_reset_core,
         dest_clk          => qnice_clk_i,
         dest_out(0)       => qnice_reset_for_prgloader
      ); -- i_cdc_main2qnice


   -- Clock Domain Crossing: QNICE -> CORE
   i_cdc_qnice2main : xpm_cdc_array_single
      generic map (
         DEST_SYNC_FF => 2,
         WIDTH        => 2
      )
      port map (
         src_clk           => qnice_clk_i,
         src_in(0)         => qnice_reset_from_prgloader,
         src_in(1)         => qnice_prg_trigger_run,
         dest_clk          => main_clk_o,
         dest_out(0)       => main_reset_from_prgloader,
         dest_out(1)       => main_prg_trigger_run
      ); -- i_cdc_qnice2main


   -- C64's RAM modelled as dual clock & dual port RAM so that the Commodore 64 core
   -- as well as QNICE can access it
   c64_ram : entity work.dualport_2clk_ram
      generic map (
         ROM_FILE          => "../../CORE/ram_init.hex",
         ROM_FILE_HEX      => true,
         ROM_PRELOAD       => true,
         ADDR_WIDTH        => 16,
         DATA_WIDTH        => 8,
         FALLING_A         => false,      -- C64 expects read/write to happen at the rising clock edge
         FALLING_B         => true        -- QNICE expects read/write to happen at the falling clock edge
      )
      port map (
         -- C64 MiSTer core
         clock_a           => main_clk_o,
         address_a         => std_logic_vector(main_ram_addr),
         data_a            => std_logic_vector(main_ram_data_from_c64),
         wren_a            => main_ram_we,
         q_a               => main_ram_data_to_c64,

         -- QNICE
         clock_b           => qnice_clk_i,
         address_b         => qnice_c64_ramx_addr,
         data_b            => qnice_c64_ramx_d_to,
         wren_b            => qnice_c64_ramx_we,
         q_b               => qnice_c64_ramx_d_from
      ); -- c64_ram

   -- Handle SW based cartridges, aka *.CRT files
   i_sw_cartridge_wrapper : entity work.sw_cartridge_wrapper
   generic map (
      G_BASE_ADDRESS => C_HMAP_CRT(9 downto 0) & X"000"
   )
   port map (
      qnice_clk_i            => qnice_clk_i,
      qnice_rst_i            => qnice_rst_i,
      qnice_addr_i           => qnice_dev_addr_i,
      qnice_data_i           => qnice_dev_data_i,
      qnice_ce_i             => qnice_crt_qnice_ce,
      qnice_we_i             => qnice_crt_qnice_we,
      qnice_data_o           => qnice_crt_qnice_data,
      qnice_wait_o           => qnice_crt_qnice_wait,
      main_clk_i             => main_clk_o,
      main_rst_i             => main_reset_m2m_i,
      main_reset_core_o      => main_reset_core,        -- see RESET SEMANTICS in main.vhd, min. pulse length is 32 clock cycles
      main_loading_o         => main_crt_loading,
      main_id_o              => main_crt_id,
      main_exrom_o           => main_crt_exrom,
      main_game_o            => main_crt_game,
      main_size_o            => main_crt_size,
      main_bank_laddr_o      => main_crt_bank_laddr,
      main_bank_size_o       => main_crt_bank_size,
      main_bank_num_o        => main_crt_bank_num,
      main_bank_raddr_o      => main_crt_bank_raddr,
      main_bank_wr_o         => main_crt_bank_wr,
      main_bank_lo_i         => main_crt_bank_lo,
      main_bank_hi_i         => main_crt_bank_hi,
      main_bank_wait_o       => main_crt_bank_wait,
      main_ram_addr_i        => std_logic_vector(main_crt_addr_bus),
      main_ram_data_i        => std_logic_vector(main_ram_data_from_c64),
      main_ioe_we_i          => main_crt_ioe_we,
      main_iof_we_i          => main_crt_iof_we,
      main_lo_ram_data_o     => main_crt_lo_ram_data,
      main_hi_ram_data_o     => main_crt_hi_ram_data,
      main_ioe_ram_data_o    => main_crt_ioe_ram_data,
      main_iof_ram_data_o    => main_crt_iof_ram_data,
      main_crt_we_i          => main_crt_we,
      main_crt_ram_data_o    => main_crt_ram_data,
      main_cart_soft_reset_i => main_cart_soft_reset,   -- see main.vhd comment at cartridge_inst
      hr_clk_i               => hr_clk_i,
      hr_rst_i               => hr_rst_i,
      hr_write_o             => hr_crt_write,
      hr_read_o              => hr_crt_read,
      hr_address_o           => hr_crt_address,
      hr_writedata_o         => hr_crt_writedata,
      hr_byteenable_o        => hr_crt_byteenable,
      hr_burstcount_o        => hr_crt_burstcount,
      hr_readdata_i          => hr_crt_readdata,
      hr_readdatavalid_i     => hr_crt_readdatavalid,
      hr_waitrequest_i       => hr_crt_waitrequest
   ); -- i_sw_cartridge_wrapper

   -- HyperRAM-backed disk-image mount buffer
   -- QNICE side is the C_DEV_C64_MOUNT device; HyperRAM side is the 3rd arbiter slave.
   i_mount_buf_wrapper : entity work.mount_buf_wrapper
      generic map (
         G_BASE_ADDRESS => C_HMAP_VD0(9 downto 0) & X"000"
      )
      port map (
         qnice_clk_i        => qnice_clk_i,
         qnice_rst_i        => qnice_rst_i,
         qnice_addr_i       => qnice_dev_addr_i,
         qnice_data_i       => qnice_dev_data_i,
         qnice_ce_i         => qnice_mnt_qnice_ce,
         qnice_we_i         => qnice_mnt_qnice_we,
         qnice_data_o       => qnice_mnt_qnice_data,
         qnice_wait_o       => qnice_mnt_qnice_wait,
         hr_clk_i           => hr_clk_i,
         hr_rst_i           => hr_rst_i,
         hr_write_o         => hr_mnt_write,
         hr_read_o          => hr_mnt_read,
         hr_address_o       => hr_mnt_address,
         hr_writedata_o     => hr_mnt_writedata,
         hr_byteenable_o    => hr_mnt_byteenable,
         hr_burstcount_o    => hr_mnt_burstcount,
         hr_readdata_i      => hr_mnt_readdata,
         hr_readdatavalid_i => hr_mnt_readdatavalid,
         hr_waitrequest_i   => hr_mnt_waitrequest
      ); -- i_mount_buf_wrapper

   main2hr_avm_fifo : entity work.avm_fifo
      generic map (
         G_WR_DEPTH     => 16,
         G_RD_DEPTH     => 16,
         G_FILL_SIZE    => 1,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         s_clk_i               => main_clk_o,
         s_rst_i               => main_reset_m2m_i,
         s_avm_waitrequest_o   => main_avm_reu_waitrequest,
         s_avm_write_i         => main_avm_reu_write,
         s_avm_read_i          => main_avm_reu_read,
         s_avm_address_i       => main_avm_reu_address,
         s_avm_writedata_i     => main_avm_reu_writedata,
         s_avm_byteenable_i    => main_avm_reu_byteenable,
         s_avm_burstcount_i    => main_avm_reu_burstcount,
         s_avm_readdata_o      => main_avm_reu_readdata,
         s_avm_readdatavalid_o => main_avm_reu_readdatavalid,
         m_clk_i               => hr_clk_i,
         m_rst_i               => hr_rst_i,
         m_avm_waitrequest_i   => hr_reu_waitrequest,
         m_avm_write_o         => hr_reu_write,
         m_avm_read_o          => hr_reu_read,
         m_avm_address_o       => hr_reu_address,
         m_avm_writedata_o     => hr_reu_writedata,
         m_avm_byteenable_o    => hr_reu_byteenable,
         m_avm_burstcount_o    => hr_reu_burstcount,
         m_avm_readdata_i      => hr_reu_readdata,
         m_avm_readdatavalid_i => hr_reu_readdatavalid
      ); -- main2hr_avm_fifo

end architecture synthesis;

