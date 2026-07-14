----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Wrapper for the MiSTer core that runs exclusively in the core's clock domain
--
-- based on C64_MiSTer by the MiSTer development team
-- port done by MJoergen and sy2002 in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.numeric_std_unsigned.all;

library work;
  use work.vdrives_pkg.all;
  use work.globals.all;

entity main is
  generic (
    G_BOARD : string; -- Which platform are we running on.
    G_VDNUM : natural -- amount of virtual drives
  );
  port (
    clk_main_i             : in    std_logic;

    -- Read the RESET SEMANTICS comment below
    -- A pulse of reset_soft_i needs to be 32 clock cycles long at a minimum
    reset_soft_i           : in    std_logic;
    reset_hard_i           : in    std_logic;

    -- Soft-reset that comes from the MEGA65's reset button or from the
    -- QNICE M2M$CSR_RESET reset pulse but not from sw_cartridge_wrapper. Used
    -- in the auto-reset scenarios where toggling SIMREU or switching between
    -- the hardware expansion slot and SIMCRT triggers an auto-reset. We need
    -- this to reliably start the SIMCRT cartridges after such an auto-reset.
    cart_soft_reset_i      : in    std_logic;
    cart_soft_reset_o      : out   std_logic;  -- gated by prevent_reset

    -- Pull high to pause the core
    pause_i                : in    std_logic;

    -- Trigger the sequence RUN<Return> to autostart PRG files
    trigger_run_i          : in    std_logic;

    ---------------------------
    -- Configuration options
    ---------------------------

    -- Select C64's ROM: 0=Custom, 1=Standard, 2=GS, 3=Japan
    c64_rom_i              : in    std_logic_vector(1 downto 0);

    -- Video mode selection:
    -- c64_ntsc_i: PAL/NTSC switch
    -- clk_main_speed_i: The core's clock speed depends on mode and needs to be very exact for avoiding clock drift
    -- video_retro15kHz_i: Analog video output configuration: Horizontal sync frequency: '0'=30 kHz ("normal" on "modern" analog monitors), '1'=retro 15 kHz
    c64_ntsc_i             : in    std_logic;                    -- 0 = PAL mode, 1 = NTSC mode, clocks need to be correctly set, too
    clk_main_speed_i       : in    natural;
    video_retro15khz_i     : in    std_logic;

    -- SID and CIA versions
    c64_sid_ver_i          : in    std_logic_vector(1 downto 0); -- SID version, 0=6581, 1=8580, low bit = left SID
    c64_sid_port_i         : in    unsigned(2 downto 0);         -- Right SID Port: 0=same as left, 1=DE00, 2=D420, 3=D500, 4=DF00
    c64_cia_ver_i          : in    std_logic;                    -- CIA version: 0=6526 "old", 1=8521 "new"

    -- Mode selection for Expansion Port (aka Cartridge Port):
    -- bit 0: 1 = Simulate cartridge (.CRT file), 0 = use Physical port
    -- bit 1: Simulate REU
    c64_exp_port_mode_i    : in    std_logic_vector(1 downto 0);

    ---------------------------
    -- Commodore 64 I/O ports
    ---------------------------

    -- M2M Keyboard interface
    kb_key_num_i           : in    integer range 0 to 79;        -- cycles through all MEGA65 keys
    kb_key_pressed_n_i     : in    std_logic;                    -- low active: debounced feedback: is kb_key_num_i pressed right now?

    -- MEGA65 joysticks and paddles
    joy_1_up_n_i           : in    std_logic;
    joy_1_down_n_i         : in    std_logic;
    joy_1_left_n_i         : in    std_logic;
    joy_1_right_n_i        : in    std_logic;
    joy_1_fire_n_i         : in    std_logic;
    joy_1_up_n_o           : out   std_logic;
    joy_1_down_n_o         : out   std_logic;
    joy_1_left_n_o         : out   std_logic;
    joy_1_right_n_o        : out   std_logic;
    joy_1_fire_n_o         : out   std_logic;
    joy_2_up_n_i           : in    std_logic;
    joy_2_down_n_i         : in    std_logic;
    joy_2_left_n_i         : in    std_logic;
    joy_2_right_n_i        : in    std_logic;
    joy_2_fire_n_i         : in    std_logic;
    joy_2_up_n_o           : out   std_logic;
    joy_2_down_n_o         : out   std_logic;
    joy_2_left_n_o         : out   std_logic;
    joy_2_right_n_o        : out   std_logic;
    joy_2_fire_n_o         : out   std_logic;
    pot1_x_i               : in    std_logic_vector(7 downto 0);
    pot1_y_i               : in    std_logic_vector(7 downto 0);
    pot2_x_i               : in    std_logic_vector(7 downto 0);
    pot2_y_i               : in    std_logic_vector(7 downto 0);

    -- Video output
    video_ce_o             : out   std_logic;
    video_ce_ovl_o         : out   std_logic;
    video_red_o            : out   std_logic_vector(7 downto 0);
    video_green_o          : out   std_logic_vector(7 downto 0);
    video_blue_o           : out   std_logic_vector(7 downto 0);
    video_vs_o             : out   std_logic;
    video_hs_o             : out   std_logic;
    video_hblank_o         : out   std_logic;
    video_vblank_o         : out   std_logic;

    -- Audio output (Signed PCM)
    audio_left_o           : out   signed(15 downto 0);
    audio_right_o          : out   signed(15 downto 0);

    -- C64 drive led (color is RGB)
    drive_led_o            : out   std_logic;
    drive_led_col_o        : out   std_logic_vector(23 downto 0);

    -- C64 RAM: No address latching necessary and the chip can always be enabled
    c64_ram_addr_o         : out   unsigned(15 downto 0);        -- C64 address bus
    c64_ram_data_o         : out   unsigned( 7 downto 0);        -- C64 RAM data out
    c64_ram_we_o           : out   std_logic;                    -- C64 RAM write enable
    c64_ram_data_i         : in    unsigned( 7 downto 0);        -- C64 RAM data in

    -- C64 IEC handled by QNICE
    c64_clk_sd_i           : in    std_logic;                    -- QNICE "sd card write clock" for floppy drive internal dual clock RAM buffer
    c64_qnice_addr_i       : in    std_logic_vector(27 downto 0);
    c64_qnice_data_i       : in    std_logic_vector(15 downto 0);
    c64_qnice_data_o       : out   std_logic_vector(15 downto 0);
    c64_qnice_ce_i         : in    std_logic;
    c64_qnice_we_i         : in    std_logic;

    -- CBM-488/IEC serial (hardware) port
    iec_hardware_port_en_i : in    std_logic;
    iec_reset_n_o          : out   std_logic;
    iec_atn_n_o            : out   std_logic;
    iec_clk_en_o           : out   std_logic;
    iec_clk_n_i            : in    std_logic;
    iec_clk_n_o            : out   std_logic;
    iec_data_en_o          : out   std_logic;
    iec_data_n_i           : in    std_logic;
    iec_data_n_o           : out   std_logic;
    iec_srq_en_o           : out   std_logic;
    iec_srq_n_i            : in    std_logic;
    iec_srq_n_o            : out   std_logic;

    -- MEGA65 physical internal 1581 (issue #90): drive 8 backed by the real
    -- internal 3.5" DD floppy (read-only milestone). The physical controller
    -- runs in the QNICE 50 MHz clock domain (c64_clk_sd_i); c64_rst_sd_i is its
    -- reset. The f_* pins connect ONLY to the controller.
    phys_1581_en_i         : in    std_logic;                    -- 1 = drive 8 uses the physical internal 1581
    c64_rst_sd_i           : in    std_logic;                    -- QNICE-domain (50 MHz) reset for the physical controller
    f_rdata_i              : in    std_logic;                    -- raw read flux from the drive
    f_index_i              : in    std_logic;
    f_track0_i             : in    std_logic;
    f_writeprotect_i       : in    std_logic;
    f_diskchanged_i        : in    std_logic;
    f_motora_o             : out   std_logic;
    f_selecta_o            : out   std_logic;
    f_side1_o              : out   std_logic;
    f_stepdir_o            : out   std_logic;
    f_step_o               : out   std_logic;
    f_density_o            : out   std_logic;

    -- Physical internal 1581 read-only QNICE diagnostic device (issue #90;
    -- C_DEV_C64_PHYS1581 = 0x0108). Same QNICE 50 MHz domain (c64_clk_sd_i) as
    -- the controller, so no CDC. Read-only: writes are ignored, no wait-state.
    phys_diag_ce_i         : in    std_logic;
    phys_diag_addr_i       : in    std_logic_vector(7 downto 0);
    phys_diag_data_o       : out   std_logic_vector(15 downto 0);

    -- C64 Expansion Port (aka Cartridge Port)
    cart_en_o              : out   std_logic;                    -- Enable port, active high
    cart_phi2_o            : out   std_logic;
    cart_dotclock_o        : out   std_logic;
    cart_dma_i             : in    std_logic;
    cart_reset_oe_o        : out   std_logic;
    cart_reset_i           : in    std_logic;
    cart_reset_o           : out   std_logic;
    cart_game_oe_o         : out   std_logic;
    cart_game_i            : in    std_logic;
    cart_game_o            : out   std_logic;
    cart_exrom_oe_o        : out   std_logic;
    cart_exrom_i           : in    std_logic;
    cart_exrom_o           : out   std_logic;
    cart_nmi_oe_o          : out   std_logic;
    cart_nmi_i             : in    std_logic;
    cart_nmi_o             : out   std_logic;
    cart_irq_oe_o          : out   std_logic;
    cart_irq_i             : in    std_logic;
    cart_irq_o             : out   std_logic;
    cart_roml_oe_o         : out   std_logic;
    cart_roml_i            : in    std_logic;
    cart_roml_o            : out   std_logic;
    cart_romh_oe_o         : out   std_logic;
    cart_romh_i            : in    std_logic;
    cart_romh_o            : out   std_logic;
    cart_ctrl_oe_o         : out   std_logic;                    -- 0 : tristate (i.e. input), 1 : output
    cart_ba_i              : in    std_logic;
    cart_rw_i              : in    std_logic;
    cart_io1_i             : in    std_logic;
    cart_io2_i             : in    std_logic;
    cart_ba_o              : out   std_logic;
    cart_rw_o              : out   std_logic;
    cart_io1_o             : out   std_logic;
    cart_io2_o             : out   std_logic;
    cart_addr_oe_o         : out   std_logic;                    -- 0 : tristate (i.e. input), 1 : output
    cart_a_i               : in    unsigned(15 downto 0);
    cart_a_o               : out   unsigned(15 downto 0);
    cart_data_oe_o         : out   std_logic;                    -- 0 : tristate (i.e. input), 1 : output
    cart_d_i               : in    unsigned( 7 downto 0);
    cart_d_o               : out   unsigned( 7 downto 0);

    -- RAM Expansion Unit
    avm_waitrequest_i      : in    std_logic;
    avm_write_o            : out   std_logic;
    avm_read_o             : out   std_logic;
    avm_address_o          : out   std_logic_vector(31 downto 0);
    avm_writedata_o        : out   std_logic_vector(15 downto 0);
    avm_byteenable_o       : out   std_logic_vector( 1 downto 0);
    avm_burstcount_o       : out   std_logic_vector( 7 downto 0);
    avm_readdata_i         : in    std_logic_vector(15 downto 0);
    avm_readdatavalid_i    : in    std_logic;

    -- Support for software based cartridges (aka ".CRT" files)
    cartridge_loading_i    : in    std_logic;
    cartridge_id_i         : in    std_logic_vector(15 downto 0);
    cartridge_exrom_i      : in    std_logic_vector( 7 downto 0);
    cartridge_game_i       : in    std_logic_vector( 7 downto 0);
    cartridge_size_i       : in    std_logic_vector(22 downto 0);
    cartridge_bank_laddr_i : in    std_logic_vector(15 downto 0);
    cartridge_bank_size_i  : in    std_logic_vector(15 downto 0);
    cartridge_bank_num_i   : in    std_logic_vector(15 downto 0);
    cartridge_bank_raddr_i : in    std_logic_vector(24 downto 0);
    cartridge_bank_wr_i    : in    std_logic;
    crt_bank_wait_i        : in    std_logic;
    crt_lo_ram_data_i      : in    std_logic_vector(15 downto 0);
    crt_hi_ram_data_i      : in    std_logic_vector(15 downto 0);
    crt_ioe_ram_data_i     : in    std_logic_vector( 7 downto 0);
    crt_iof_ram_data_i     : in    std_logic_vector( 7 downto 0);
    crt_addr_bus_o         : out   unsigned(15 downto 0);
    crt_ioe_we_o           : out   std_logic;
    crt_iof_we_o           : out   std_logic;
    crt_bank_lo_o          : out   std_logic_vector( 6 downto 0);
    crt_bank_hi_o          : out   std_logic_vector( 6 downto 0);
    crt_we_o               : out   std_logic;
    crt_ram_data_i         : in    std_logic_vector( 7 downto 0);

    -- Access custom Kernal: C64's Basic and DOS (in QNICE clock domain via c64_clk_sd_i)
    c64rom_we_i            : in    std_logic;
    c64rom_addr_i          : in    std_logic_vector(13 downto 0);
    c64rom_data_i          : in    std_logic_vector(7 downto 0);
    c64rom_data_o          : out   std_logic_vector(7 downto 0);

    -- Access custom DOS for the simulated C1541 (in QNICE clock domain via c64_clk_sd_i)
    c1541rom_we_i          : in    std_logic;
    c1541rom_addr_i        : in    std_logic_vector(15 downto 0);
    c1541rom_data_i        : in    std_logic_vector(7 downto 0);
    c1541rom_data_o        : out   std_logic_vector(7 downto 0);

    -- Contents of RTC (see user_io.cpp in Main_MiSTer):
    -- Bits  7 -  0 : Seconds    (BCD format, 0x00-0x60)
    -- Bits 15 -  8 : Minutes    (BCD format, 0x00-0x59)
    -- Bits 23 - 16 : Hours      (BCD format, 0x00-0x23)
    -- Bits 31 - 24 : DayOfMonth (BCD format, 0x01-0x31)
    -- Bits 39 - 32 : Month      (BCD format, 0x01-0x12)
    -- Bits 47 - 40 : Year       (BCD format, 0x00-0x99)
    -- Bits 55 - 48 : DayOfWeek  (0x00-0x06)
    -- Bits 63 - 56 : 0x40
    -- Bit       64 : Toggle flag
    rtc_i                  : in    std_logic_vector(64 downto 0)
  );
end entity main;

architecture synthesis of main is

  --------------------------------------------------------------------------------------------------
  -- SIGNAL-FAMILY LEGEND (read this before the declarations below)
  --------------------------------------------------------------------------------------------------
  --
  -- Signals in this architecture are grouped by name prefix. Each family has its own direction and
  -- polarity conventions; the prefix tells you which "world" a signal lives in:
  --
  --   core_*        MiSTer C64 core side (fpga64_sid_iec). Bus-access decodes/strobes are
  --                 ACTIVE-HIGH (core_roml, core_romh, core_ioe [= IO1 = $DExx],
  --                 core_iof [= IO2 = $DFxx], core_ba, core_dma); the genuinely low-active lines
  --                 carry _n (core_irq_n, core_nmi_n, core_exrom_n, core_game_n).
  --
  --   cart_out_* /  Physical Expansion Port (connector-pin) side. cart_out_* is driven OUT toward
  --   cart_in_*     the pin (or the core-side decode of such an access); cart_in_* is sensed IN from
  --                 the pin. Suffix _n = active-low (the slash lines /ROML /ROMH /IO1 /IO2 /DMA
  --                 /RESET /GAME /EXROM /NMI /IRQ); _q = the register nearest the connector;
  --                 bare = combinational / core-facing. Pipeline shape:
  --                     core --> cart_out_X  --(flop)--> cart_out_X_q --> pin
  --                     pin  --> cart_in_X_q --(gate)--> cart_in_X    --> core
  --
  --   cart_*_i /    The actual entity PORTS to the level-shifted connector (wired up in mega65.vhd).
  --   cart_*_o /    cart_*_oe_o is the output-enable: '1' drives the pin, '0' tristates / senses it.
  --   cart_*_oe_o
  --
  --   crt_*         Simulated ".crt" cartridge path (SIMCRT): BRAM bank-cache data, exrom/game,
  --                 IO write-enables. Fed from sw_cartridge_wrapper / cartridge.vhd in mega65.vhd.
  --
  --   reu_* /       Simulated 1750 REU. reu_dma_* = DMA between MiSTer's reu and the C64 core;
  --   sim_reu_* /   sim_reu_* = reu <-> reu_mapper; map_* = the reu_mapper <-> avm_cache Avalon
  --   map_*         bridge out to HyperRAM (see the avm_* top-level ports).
  --
  --   c64_iec_* /   Serial IEC bus (all lines low-active, hence the ANDing). c64_iec_* = the C64
  --   iec_* /       core's bus lines; hw_iec_* = sensed from the hardware CBM-488 port; iec_* = the
  --   hw_iec_*      simulated drives plus the SD/mount interface and the hardware-port entity ports.
  --
  --   c64_ram_* /   The core's external RAM bus, the raw (unprocessed, pre-scaler) video output, and
  --   vga_* /       the SID audio. NB: vga_* is just pre-pipeline RGB and feeds BOTH the analog VGA
  --   audio_*       and the HDMI path downstream, despite the name.
  --
  --   Resets: see the RESET SEMANTICS block further down. reset_core_n is the go-to reset for this
  --   file; NEVER use reset_soft_i / reset_hard_i directly.
  --------------------------------------------------------------------------------------------------

  -- Generic MiSTer C64 signals
  signal   c64_pause     : std_logic;
  signal   c64_drive_led : std_logic;

  -- directly connect the C64's CIA1 to the emulated keyboard matrix within keyboard.vhd
  signal   cia1_pa_in  : std_logic_vector(7 downto 0);
  signal   cia1_pa_out : std_logic_vector(7 downto 0);
  signal   cia1_pb_in  : std_logic_vector(7 downto 0);
  signal   cia1_pb_out : std_logic_vector(7 downto 0);

  -- Bit positions in c64_exp_port_mode_i
  constant C_SIM_CRT : natural := 0;
  constant C_SIM_REU : natural := 1;

  -- signals for RAM
  signal   c64_ram_ce   : std_logic;
  signal   c64_ram_we   : std_logic;
  signal   c64_ram_data : unsigned(7 downto 0);

  -- 18-bit SID from C64 : Needs to go through audio processing ported from Verilog to VHDL from MiSTer's c64.sv
  signal   c64_sid_l : std_logic_vector(17 downto 0);
  signal   c64_sid_r : std_logic_vector(17 downto 0);
  signal   alo       : std_logic_vector(15 downto 0);
  signal   aro       : std_logic_vector(15 downto 0);

  -- Special keys
  signal   restore_key_n : std_logic;   -- the Restore key is special: it creates a non maskable interrupt (NMI)
  signal   freeze_key_n  : std_logic;   -- F9 key = freezer key for simulated cartridges

  -- C64's IEC signals
  signal   c64_iec_clk_out  : std_logic;
  signal   c64_iec_clk_in   : std_logic;
  signal   c64_iec_atn_out  : std_logic;
  signal   c64_iec_data_out : std_logic;
  signal   c64_iec_data_in  : std_logic;

  -- Hardware IEC port
  signal   hw_iec_clk_n_in  : std_logic;
  signal   hw_iec_data_n_in : std_logic;
  signal   hw_iec_srq_n_in  : std_logic;

  -- 2-FF synchronizer for the asynchronous IEC SRQ input (see https://github.com/MJoergen/C64MEGA65/issues/219)
  signal   iec_srq_n_d      : std_logic := '1';
  signal   iec_srq_n_sync   : std_logic := '1';

  -- Simulated IEC drives
  signal   iec_drive_ce : std_logic;              -- chip enable for iec_drive (clock divider, see generate_drive_ce below)
  signal   iec_dce_sum  : integer     := 0;       -- caution: we expect 32-bit integers here and we expect the initialization to 0

  signal   iec_img_mounted  : std_logic_vector(G_VDNUM - 1 downto 0);
  signal   iec_img_readonly : std_logic;
  signal   iec_img_size     : std_logic_vector(31 downto 0);
  signal   iec_img_type     : std_logic_vector( 1 downto 0);

  signal   iec_drives_reset : std_logic_vector(G_VDNUM - 1 downto 0);
  signal   vdrives_mounted  : std_logic_vector(G_VDNUM - 1 downto 0);
  signal   cache_dirty      : std_logic_vector(G_VDNUM - 1 downto 0);
  signal   prevent_reset    : std_logic;

  -- Image-drive busy/dirty flag for the symmetric source-toggle idle-gate (issue #90):
  -- drive LED (activity of the 1541 and 1581 image engines, incl. WD1772 command-busy)
  -- OR any dirty write-back cache. Generated in the main clock domain, 2-FF-synced into
  -- the 50 MHz diag domain (c64_clk_sd_i) where the QNICE Shell reads it as a level.
  signal   img_drive_busy   : std_logic;
  signal   img_busy_sd_m    : std_logic;
  signal   img_busy_sd_s    : std_logic;

  -- Read-side reset for the physical-1581 read FIFO: the SAME reset event as the
  -- write side (c64_rst_sd_i = QNICE/framework reset), 2-FF-synchronized into the
  -- read clock domain (clk_main_i). Both Gray-pointer pairs of an async FIFO must
  -- reset from ONE common event or the pointers desynchronize permanently; a
  -- core-only reset (reset_core_n) must NOT reset either side -- residual bytes
  -- after an aborted operation are drained by the WD front end (fdc1772) instead.
  signal   p1581_fiforst_m  : std_logic := '1';
  signal   p1581_fiforst_s  : std_logic := '1';

  attribute async_reg : string;
  attribute async_reg of img_busy_sd_m : signal is "true";
  attribute async_reg of img_busy_sd_s : signal is "true";
  attribute async_reg of p1581_fiforst_m : signal is "true";
  attribute async_reg of p1581_fiforst_s : signal is "true";
  signal   cart_soft_reset  : std_logic;

  signal   iec_sd_lba          : vd_vec_array(G_VDNUM - 1 downto 0)(31 downto 0);
  signal   iec_sd_blk_cnt      : vd_vec_array(G_VDNUM - 1 downto 0)( 5 downto 0);
  signal   iec_sd_rd           : vd_std_array(G_VDNUM - 1 downto 0);
  signal   iec_sd_wr           : vd_std_array(G_VDNUM - 1 downto 0);
  signal   iec_sd_ack          : vd_std_array(G_VDNUM - 1 downto 0);
  signal   iec_sd_buf_addr     : std_logic_vector(13 downto 0);
  signal   iec_sd_buf_data_in  : std_logic_vector( 7 downto 0);
  signal   iec_sd_buf_data_out : vd_vec_array(G_VDNUM - 1 downto 0)(7 downto 0);
  signal   iec_sd_buf_wr       : std_logic;
  signal   iec_par_stb_in      : std_logic;
  signal   iec_par_stb_out     : std_logic;
  signal   iec_par_data_in     : std_logic_vector(7 downto 0);
  signal   iec_par_data_out    : std_logic_vector(7 downto 0);

  --------------------------------------------------------------------------------------------------
  -- Physical internal 1581 ABI (issue #90)
  --------------------------------------------------------------------------------------------------
  -- Intermediate signals bridging the SystemVerilog iec_drive (all ports appear
  -- as std_logic / std_logic_vector on the VHDL side) with the VHDL
  -- physical_1581_controller (numeric_std.unsigned data buses) and the dual-clock
  -- read FIFO. Each signal is typed to match its DRIVER, so the only type
  -- conversions needed are on the CONSUMER (input-side) associations.
  -- iec_drive OUTPUTS -> controller / rdfifo:
  signal   p1581_active        : std_logic;
  signal   p1581_cia_motor_on  : std_logic;
  signal   p1581_cia_side      : std_logic;
  signal   p1581_step_req_tgl  : std_logic;
  signal   p1581_step_outward  : std_logic;
  signal   p1581_rd_req_tgl    : std_logic;
  signal   p1581_rd_op         : std_logic_vector(2 downto 0);
  signal   p1581_rd_track      : std_logic_vector(7 downto 0);
  signal   p1581_rd_side       : std_logic;
  signal   p1581_rd_sector     : std_logic_vector(7 downto 0);
  signal   p1581_rd_cancel_tgl : std_logic;
  signal   p1581_rd_seq        : std_logic_vector(1 downto 0);
  signal   p1581_byte_rd_en    : std_logic;
  -- controller / rdfifo OUTPUTS -> iec_drive:
  signal   p1581_step_ack_tgl  : std_logic;
  signal   p1581_rd_done_tgl   : std_logic;
  signal   p1581_rd_done_seq   : std_logic_vector(1 downto 0);
  signal   p1581_rd_result     : std_logic_vector(4 downto 0);
  signal   p1581_rd_crc_err    : std_logic;
  signal   p1581_rd_rnf        : std_logic;
  signal   p1581_rd_deleted    : std_logic;
  signal   p1581_rd_c          : unsigned(7 downto 0);
  signal   p1581_rd_h          : unsigned(7 downto 0);
  signal   p1581_rd_r          : unsigned(7 downto 0);
  signal   p1581_rd_n          : unsigned(7 downto 0);
  signal   p1581_media_ready   : std_logic;
  signal   p1581_index         : std_logic;
  signal   p1581_track0        : std_logic;
  signal   p1581_wprot         : std_logic;
  signal   p1581_change        : std_logic;
  signal   p1581_motor_on      : std_logic;
  signal   p1581_head_settled  : std_logic;
  -- read-byte FIFO data path:
  signal   p1581_fifo_wr_data  : unsigned(7 downto 0);   -- controller byte_data_o -> rdfifo wr_data_i
  signal   p1581_fifo_wr_en    : std_logic;              -- controller byte_wr_o   -> rdfifo wr_en_i
  signal   p1581_fifo_wr_full  : std_logic;              -- rdfifo wr_full_o        -> controller byte_ovf_i
  signal   p1581_byte_data     : unsigned(7 downto 0);   -- rdfifo rd_data_o        -> iec_drive phys_byte_data
  signal   p1581_byte_empty    : std_logic;              -- rdfifo rd_empty_o       -> iec_drive phys_byte_empty

  -- fdc1772 delivery-v2 diagnostic taps (issue #90 round 10). The five event
  -- toggles are generated in the drive clock domain (clk_main_i) and 2-FF-synced
  -- below into the 50 MHz diag domain (c64_clk_sd_i), same precedent as
  -- img_drive_busy: a toggle is a slow, quasi-static level, so a plain 2-FF sync
  -- is sufficient and each edge marks exactly one event. p1581_dbg_pres_cnt is
  -- NOT synced: it is quasi-static long before (and after) its fin toggle and is
  -- captured inside physical_1581_diag on the synced fin edge.
  signal   p1581_dbg_lost_tgl      : std_logic;
  signal   p1581_dbg_drain_tgl     : std_logic;
  signal   p1581_dbg_staledone_tgl : std_logic;
  signal   p1581_dbg_busycmd_tgl   : std_logic;
  signal   p1581_dbg_fin_tgl       : std_logic;
  signal   p1581_dbg_pres_cnt      : std_logic_vector(10 downto 0);
  signal   p1581_dbg_lost_sd_m      : std_logic;
  signal   p1581_dbg_lost_sd_s      : std_logic;
  signal   p1581_dbg_drain_sd_m     : std_logic;
  signal   p1581_dbg_drain_sd_s     : std_logic;
  signal   p1581_dbg_staledone_sd_m : std_logic;
  signal   p1581_dbg_staledone_sd_s : std_logic;
  signal   p1581_dbg_busycmd_sd_m   : std_logic;
  signal   p1581_dbg_busycmd_sd_s   : std_logic;
  signal   p1581_dbg_fin_sd_m       : std_logic;
  signal   p1581_dbg_fin_sd_s       : std_logic;
  attribute async_reg of p1581_dbg_lost_sd_m      : signal is "true";
  attribute async_reg of p1581_dbg_lost_sd_s      : signal is "true";
  attribute async_reg of p1581_dbg_drain_sd_m     : signal is "true";
  attribute async_reg of p1581_dbg_drain_sd_s     : signal is "true";
  attribute async_reg of p1581_dbg_staledone_sd_m : signal is "true";
  attribute async_reg of p1581_dbg_staledone_sd_s : signal is "true";
  attribute async_reg of p1581_dbg_busycmd_sd_m   : signal is "true";
  attribute async_reg of p1581_dbg_busycmd_sd_s   : signal is "true";
  attribute async_reg of p1581_dbg_fin_sd_m       : signal is "true";
  attribute async_reg of p1581_dbg_fin_sd_s       : signal is "true";

  -- physical_1581 read-only diagnostics (issue #90): controller diag_* taps and
  -- the two previously-open st_* outputs, fed to physical_1581_diag (device 0x0108).
  signal   p1581_head_cyl        : unsigned(7 downto 0);
  signal   p1581_locked          : std_logic;
  signal   p1581_diag_in_bits    : std_logic_vector(15 downto 0);
  signal   p1581_diag_out_bits   : std_logic_vector(15 downto 0);
  signal   p1581_diag_idx_period : unsigned(31 downto 0);
  signal   p1581_diag_idx_width  : unsigned(31 downto 0);
  signal   p1581_diag_last_gap   : unsigned(15 downto 0);
  signal   p1581_diag_calc_crc   : unsigned(15 downto 0);
  signal   p1581_diag_stored_crc : unsigned(15 downto 0);
  signal   p1581_diag_index_edge : std_logic;
  signal   p1581_diag_index_qual : std_logic;
  signal   p1581_diag_id_valid   : std_logic;
  signal   p1581_diag_id_crc_ok  : std_logic;
  signal   p1581_diag_data_end   : std_logic;
  signal   p1581_diag_data_crc_ok: std_logic;
  signal   p1581_diag_gap_error  : std_logic;
  signal   p1581_diag_rd_phase   : std_logic_vector(3 downto 0);
  signal   p1581_diag_step_phase : std_logic_vector(1 downto 0);
  signal   p1581_diag_head_valid : std_logic;
  signal   p1581_diag_head_dir   : std_logic;
  signal   p1581_diag_rd_req     : std_logic;
  signal   p1581_diag_rd_req_op  : std_logic_vector(2 downto 0);
  signal   p1581_diag_rd_req_trk : unsigned(7 downto 0);
  signal   p1581_diag_rd_req_sec : unsigned(7 downto 0);
  signal   p1581_diag_rd_req_side: std_logic;
  signal   p1581_diag_runt       : std_logic;             -- controller diag_runt_o -> diag runt_i (both 50 MHz)
  signal   p1581_diag_est        : unsigned(11 downto 0); -- adaptive quantiser half-cell estimate, Q8.4 (round 12)
  signal   p1581_fifo_level      : unsigned(9 downto 0);  -- rdfifo wr_level_o      -> diag fifo_level_i (both 50 MHz)

  -- unprocessed video output of the C64 core
  signal   vga_hs    : std_logic;
  signal   vga_vs    : std_logic;
  signal   vga_red   : unsigned(7 downto 0);
  signal   vga_green : unsigned(7 downto 0);
  signal   vga_blue  : unsigned(7 downto 0);

  -- clock enable to derive the C64's pixel clock from the core's main clock : divide by 4
  signal   video_ce : std_logic_vector(1 downto 0);

  -- RESET SEMANTICS
  --
  -- The C64 core implements core specific semantics: A standard reset of the core is a soft reset and
  -- will not interfere with any "reset protections". This also means that a soft reset will start
  -- soft- and hardware cartridges. A hard reset on the other hand does circumvent "reset protections"
  -- and will therefore also exit games which prevent you from exiting them via reset and you can
  -- also exit from simulated cartridges using a hard reset.
  --
  -- Three-tier reset hierarchy (each tier strictly contains the one below):
  --    long  MEGA65 reset button (>= 1.5 s) => framework reset_m2m_n  (asserts reset_hard_i)
  --    short MEGA65 reset button            => framework reset_core_n (asserts reset_soft_i + hr_rst)
  --    QNICE Shell M2M$CSR_RESET pulse      => reset_soft_i only (no hr_rst, no AV-pipeline glitch)
  -- The QNICE pulse (issued via the RESET_CORE helper in CORE/m2m-rom/m2m-rom.asm) is intentionally
  -- a strict subset of a short button press: it soft-resets the C64 only and does not disturb the
  -- ASCAL/HDMI pipeline, so OSM-driven resets (kernal swap, EXP_PORT/REU toggle, .crt mount) keep
  -- the picture stable. See the routing in M2M/vhdl/top_mega65-r{3,4,5,6}.vhd and the rationale
  -- comment in M2M/vhdl/QNICE/qnice.vhd:96-110.
  --
  -- When pulsing reset_soft_i from the outside (mega65.vhd), then you need to ensure that this
  -- pulse is at least 32 clock cycles long. Currently (see mega65.vhd) there are three sources that
  -- trigger reset_soft_i: The M2M reset manager, sw_cartridge_wrapper, and the QNICE Shell's
  -- M2M$CSR_RESET write pulse (via RESET_CORE in CORE/m2m-rom/m2m-rom.asm, which inserts a small
  -- QNICE delay loop between the OR/AND CSR writes to widen the pulse to >= 64 main_clk cycles
  -- after the 2-stage CDC in framework.vhd). All three sources honor the 32-cycle minimum.
  --
  -- A reset that is coming from a hardware cartridge via cart_in_reset_n_q (which is low active) is treated
  -- just like reset_soft_i. We can assume that the pulse will be long enough because cartridges are
  -- aware of minimum reset durations. (Example: The EF3 pulses the reset for 7xphi2, which is way longer
  -- then 32 cycles.)
  --
  -- CAUTION: NEVER DIRECTLY USE THE INPUT SIGNALS
  --       reset_soft_i and
  --       reset_hard_i
  -- IN MAIN.VHD AS YOU WILL RISK DATA CORRUPTION!
  -- Exceptions are the processes "hard_reset" and "handle_cartridge_triggered_resets",
  -- which "know what they are doing".
  --
  -- The go-to signal for all standard reset situations within main.vhd:
  --       reset_core_n
  -- To prevent data corruption, there is a protected version of reset_soft_i called reset_core_n.
  -- Data corruption can for example occur, when a user presses the reset button while a simulated
  -- disk drive is still writing to the disk image on the SD card. Therefore reset_core_n is
  -- protected by using the signal prevent_reset.
  --
  -- hard_reset_n IS NOT MEANT TO BE USED IN MAIN.VHD
  -- with the exception of the "cpu_data_in" the reset input of "cartridge_inst".
  signal   reset_core_n     : std_logic                            := '1';
  signal   reset_core_int_n : std_logic                            := '1';
  signal   hard_reset_n     : std_logic                            := '1';

  constant C_HARD_RST_DELAY : natural                              := 100_000; -- roundabout 1/30 of a second
  signal   hard_rst_counter : natural                              := 0;
  signal   hard_reset_n_d   : std_logic                            := '1';
  signal   cold_start_done  : std_logic                            := '0';

  -- Core's simulated expansion port
  signal   core_roml            : std_logic;
  signal   core_romh            : std_logic;
  signal   core_ioe             : std_logic;
  signal   core_iof             : std_logic;
  signal   core_nmi_n           : std_logic;
  signal   core_nmi_ack         : std_logic;
  signal   core_ba              : std_logic;
  signal   core_irq_n           : std_logic;
  signal   core_dma             : std_logic;
  signal   core_exrom_n         : std_logic;
  signal   core_game_n          : std_logic;
  signal   core_umax_romh       : std_logic;
  signal   core_umax_unmapped   : std_logic;
  signal   core_io_rom          : std_logic;
  signal   core_io_ext          : std_logic;
  signal   core_io_data         : unsigned(7 downto 0);
  signal   core_dotclk          : std_logic;
  signal   core_phi2            : std_logic;
  signal   core_phi2_prev       : std_logic;
  signal   cartridge_bank_raddr : std_logic_vector(24 downto 0);

  -- Core's DMA interface (for hardware DMA cartridges and SIMREU)
  signal   core_dma_req   : std_logic;
  signal   core_dma_cycle : std_logic;
  signal   core_dma_addr  : unsigned(15 downto 0);
  signal   core_dma_dout  : unsigned(7 downto 0);
  signal   core_dma_din   : unsigned(7 downto 0);
  signal   core_dma_we    : std_logic;
  signal   core_irq_ext_n : std_logic;

  -- Cart-port output registration: see comment block at cart_output_pipeline_proc below
  signal   cart_out_a        : unsigned(15 downto 0); -- combinational, includes Ultimax override
  signal   cart_out_a_q      : unsigned(15 downto 0);
  signal   cart_out_roml_n_q : std_logic;
  signal   cart_out_romh_n_q : std_logic;
  signal   cart_out_io1_n_q  : std_logic;
  signal   cart_out_io2_n_q  : std_logic;
  signal   cart_out_rw_q     : std_logic;
  signal   cart_out_d_q      : unsigned( 7 downto 0); -- held copy of the C64's outgoing write byte
  signal   cart_out_sel      : std_logic;             -- combinational: any cart-window access decoded RIGHT NOW
  signal   cart_out_sel_q    : std_logic;             -- registered:    any cart-window access still showing at the pin

  -- Cart-port input registration: see comment block at cart_input_pipeline_proc below
  signal   cart_in_dma_n_q   : std_logic;
  signal   cart_in_reset_n_q : std_logic;
  signal   cart_in_game_n_q  : std_logic;
  signal   cart_in_exrom_n_q : std_logic;
  signal   cart_in_nmi_n_q   : std_logic;
  signal   cart_in_irq_n_q   : std_logic;
  signal   cart_in_roml_n_q  : std_logic;
  signal   cart_in_romh_n_q  : std_logic;
  signal   cart_in_ba_q      : std_logic;
  signal   cart_in_rw_q      : std_logic;
  signal   cart_in_io1_n_q   : std_logic;
  signal   cart_in_io2_n_q   : std_logic;
  signal   cart_in_a_q       : unsigned(15 downto 0);
  signal   cart_in_d_q       : unsigned( 7 downto 0);

  -- Hardware Expansion Port (aka Cartridge Port)
  signal   cart_out_roml_n : std_logic;
  signal   cart_out_romh_n : std_logic;
  signal   cart_out_io1_n  : std_logic;
  signal   cart_out_io2_n  : std_logic;
  signal   cart_in_nmi_n   : std_logic;
  signal   cart_in_irq_n   : std_logic;
  signal   cart_in_dma_n   : std_logic;
  signal   cart_in_exrom_n : std_logic;
  signal   cart_in_game_n  : std_logic;
  signal   cart_in_data    : unsigned(7 downto 0);

  -- Hardware Expansion Port: Handle specifics of certain cartridges
  constant C_EF3_RESET_LEN    : natural                            := 7;       -- measured in phi2 cycles
  signal   cart_reset_counter : natural range 0 to C_EF3_RESET_LEN := 0;
  signal   cart_res_flckr_ign : natural range 0 to 2;                          -- avoid a short cart_reset_o after cart_reset_counter reached zero
  signal   cart_is_an_ef3     : std_logic;

  -- RAM Expansion Unit (REU)
  signal   reu_cfg       : std_logic_vector(1 downto 0);
  signal   reu_dma_req   : std_logic;
  signal   reu_dma_cycle : std_logic;
  signal   reu_dma_addr  : std_logic_vector(15 downto 0);
  signal   reu_dma_dout  : std_logic_vector( 7 downto 0);
  signal   reu_dma_din   : unsigned(7 downto 0);
  signal   reu_dma_we    : std_logic;
  signal   reu_irq       : std_logic;
  signal   reu_iof       : std_logic;
  signal   reu_oe        : std_logic;
  signal   reu_dout      : unsigned(7 downto 0);

  -- Signals from the cartridge.vhd module (software defined cartridges)
  signal   crt_io_rom     : std_logic;
  signal   crt_io_ext     : std_logic;
  signal   crt_io_data    : std_logic_vector(7 downto 0);
  signal   crt_exrom      : std_logic;
  signal   crt_game       : std_logic;
  signal   crt_roml_we    : std_logic;
  signal   crt_nmi        : std_logic;
  signal   crt_ioe_wr_ena : std_logic;
  signal   crt_iof_wr_ena : std_logic;
  signal   crt_addr_9exx  : std_logic;
  signal   crt_addr_9fxx  : std_logic;

  -- RAM Expansion Unit
  signal   sim_ext_cycle : std_logic;
  signal   sim_reu_cycle : std_logic;
  signal   sim_reu_addr  : std_logic_vector(24 downto 0);
  signal   sim_reu_dout  : std_logic_vector( 7 downto 0);
  signal   sim_reu_din   : std_logic_vector( 7 downto 0);
  signal   sim_reu_we    : std_logic;
  signal   sim_reu_cs    : std_logic;

  signal   map_write         : std_logic;
  signal   map_read          : std_logic;
  signal   map_address       : std_logic_vector(31 downto 0);
  signal   map_writedata     : std_logic_vector(15 downto 0);
  signal   map_byteenable    : std_logic_vector( 1 downto 0);
  signal   map_burstcount    : std_logic_vector( 7 downto 0);
  signal   map_readdata      : std_logic_vector(15 downto 0);
  signal   map_readdatavalid : std_logic;
  signal   map_waitrequest   : std_logic;

  signal   cass_write : std_logic;
  signal   cass_motor : std_logic;
  signal   cass_rtc   : std_logic;
  signal   rtcf83_sda : std_logic;

  -- Verilog file from MiSTer core
  component reu is
    port (
      clk       : in    std_logic;
      reset     : in    std_logic;
      cfg       : in    std_logic_vector(1 downto 0);
      -- Connect to the DMA controller of the C64
      dma_req   : out   std_logic;
      dma_cycle : in    std_logic;
      dma_addr  : out   std_logic_vector(15 downto 0);
      dma_dout  : out   std_logic_vector( 7 downto 0);
      dma_din   : in    std_logic_vector( 7 downto 0);
      dma_we    : out   std_logic;
      -- Connect to the HyperRAM
      ram_cycle : in    std_logic;
      ram_addr  : out   std_logic_vector(24 downto 0);
      ram_dout  : out   std_logic_vector( 7 downto 0);
      ram_din   : in    std_logic_vector( 7 downto 0);
      ram_we    : out   std_logic;
      ram_cs    : out   std_logic;
      -- CPU register interface to the REU controller
      cpu_addr  : in    unsigned(15 downto 0);
      cpu_dout  : in    unsigned( 7 downto 0);
      cpu_din   : out   unsigned( 7 downto 0);
      cpu_we    : in    std_logic;
      cpu_cs    : in    std_logic;
      irq       : out   std_logic
    );
  end component reu;

  component rtcf83 is
    generic (
      CLOCK_RATE : integer;
      HAS_RAM    : integer
    );
    port (
      clk   : in    std_logic;
      ce    : in    std_logic;
      reset : in    std_logic;
      rtc   : in    std_logic_vector(64 downto 0);
      scl_i : in    std_logic;
      sda_i : in    std_logic;
      sda_o : out   std_logic
    );
  end component rtcf83;

begin

  -- prevent data corruption by not allowing a soft reset to happen while the cache is still dirty
  -- since we can have more than one cache that might be dirty, we convert the std_logic_vector of length G_VDNUM
  -- into an unsigned and check for zero
  prevent_reset     <= '0' when unsigned(cache_dirty) = 0 else '1';
  cart_soft_reset   <= cart_soft_reset_i and not prevent_reset;
  cart_soft_reset_o <= cart_soft_reset;

  -- the color of the drive led is green normally, but it turns yellow
  -- when the cache is dirty and/or currently being flushed
  drive_led_col_o <= x"00FF00" when unsigned(cache_dirty) = 0 else
                     x"FFFF00";

  -- the drive led is on if either the C64 is writing to the virtual disk (cached in RAM)
  -- or if the dirty cache is dirty and/or currently being flushed to the SD card
  drive_led_o     <= c64_drive_led when unsigned(cache_dirty) = 0 else
                     '1';

  -- "Image drive 8 is busy or holds unsaved data" for the symmetric idle-gate (issue #90):
  -- consulted by the QNICE Shell (via the phys-1581 diag device) before it allows switching
  -- drive 8 from disk image to the internal 1581. The LED covers live drive activity of both
  -- image engines; prevent_reset covers dirty write caches awaiting SD flush. While the
  -- INTERNAL drive is the active source the LED reflects PHYSICAL activity (the 1581 DOS
  -- drives it, e.g. the blinking error indicator), which the physical busy word already
  -- covers -- so mask the LED with the mode bit, otherwise an Internal->Image switch would
  -- be spuriously blocked whenever the toggle lands in a blink-ON phase. It is a slow,
  -- quasi-static level, so a plain 2-FF sync into the diag clock domain is sufficient.
  img_drive_busy <= (c64_drive_led and not phys_1581_en_i) or prevent_reset;

  img_busy_sync_proc : process (c64_clk_sd_i)
  begin
    if rising_edge(c64_clk_sd_i) then
      img_busy_sd_m <= img_drive_busy;
      img_busy_sd_s <= img_busy_sd_m;
    end if;
  end process img_busy_sync_proc;

  -- common-event FIFO read-side reset (see the signal declaration comment)
  p1581_fiforst_sync_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      p1581_fiforst_m <= c64_rst_sd_i;
      p1581_fiforst_s <= p1581_fiforst_m;
    end if;
  end process p1581_fiforst_sync_proc;

  -- 2-FF sync of the fdc1772 delivery-v2 diagnostic event toggles (drive clock
  -- domain) into the 50 MHz diag domain; edge detection and counting happen
  -- inside physical_1581_diag (see the signal declaration comment)
  p1581_dbg_sync_proc : process (c64_clk_sd_i)
  begin
    if rising_edge(c64_clk_sd_i) then
      p1581_dbg_lost_sd_m      <= p1581_dbg_lost_tgl;
      p1581_dbg_lost_sd_s      <= p1581_dbg_lost_sd_m;
      p1581_dbg_drain_sd_m     <= p1581_dbg_drain_tgl;
      p1581_dbg_drain_sd_s     <= p1581_dbg_drain_sd_m;
      p1581_dbg_staledone_sd_m <= p1581_dbg_staledone_tgl;
      p1581_dbg_staledone_sd_s <= p1581_dbg_staledone_sd_m;
      p1581_dbg_busycmd_sd_m   <= p1581_dbg_busycmd_tgl;
      p1581_dbg_busycmd_sd_s   <= p1581_dbg_busycmd_sd_m;
      p1581_dbg_fin_sd_m       <= p1581_dbg_fin_tgl;
      p1581_dbg_fin_sd_s       <= p1581_dbg_fin_sd_m;
    end if;
  end process p1581_dbg_sync_proc;

  --------------------------------------------------------------------------------------------------
  -- Hard reset
  --------------------------------------------------------------------------------------------------

  hard_reset_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      if reset_soft_i = '1' or reset_hard_i = '1' or cart_reset_counter /= 0 then
        -- Due to sw_cartridge_wrapper's logic, reset_soft_i stays high longer than reset_hard_i.
        -- We need to make sure that this is not interfering with hard_reset_n
        if reset_hard_i = '1' then
          hard_rst_counter <= C_HARD_RST_DELAY;
          hard_reset_n     <= '0';
        end if;

        -- reset_core_n is low-active, so prevent_reset = 0 means execute reset
        -- but a hard reset can override
        reset_core_int_n <= prevent_reset and (not reset_hard_i);
      else
        -- The idea of the hard reset is, that while reset_core_n is back at '1' and therefore the core is
        -- running (not being reset any more), hard_reset_n stays low for C_HARD_RST_DELAY clock cycles.
        -- Reason: We need to give the KERNAL time to execute the routine $FD02 where it checks for the
        -- cartridge signature "CBM80" in $8003 onwards. In case reset_n = '0' during these tests (i.e. hard
        -- reset active) we will return zero instead of "CBM80" and therefore perform a hard reset.
        reset_core_int_n <= '1';
        if hard_rst_counter = 0 then
          hard_reset_n <= '1';
        else
          hard_rst_counter <= hard_rst_counter - 1;
        end if;
      end if;
    end if;
  end process hard_reset_proc;

  -- Combined reset signal to be used throughout main.vhd: reset triggered by the MEGA65's reset button (reset_core_int_n)
  -- and reset triggered by an external cartridge.
  combined_reset_proc : process (all)
  begin
    reset_core_n <= '1';

    -- cart_in_reset_n_q becomes cart_reset_o as soon as cart_reset_oe_o = '1', and the latter one becomes '1' as soon
    -- as reset_core_int_n = '0' so we need to ignore cart_in_reset_n_q in this case
    if reset_core_int_n = '0' then
      reset_core_n <= '0';
    elsif cart_in_reset_n_q = '0' and prevent_reset = '0' then
      reset_core_n <= '0';
    end if;
  end process combined_reset_proc;

  -- To make sure that cartridges in the Expansion Port start properly, we must not do a hard reset and mask the $8000 memory area,
  -- when the core is launched for the first time (cold start).
  handle_cold_start_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      hard_reset_n_d <= hard_reset_n;
      -- detect the rising edge of hard_reset_n_d
      if hard_reset_n = '1' and hard_reset_n_d = '0' and cold_start_done = '0' then
        cold_start_done <= '1';
      end if;
    end if;
  end process handle_cold_start_proc;

  --------------------------------------------------------------------------------------------------
  -- Access to C64's RAM and hardware/simulated cartridge ROM
  --------------------------------------------------------------------------------------------------

  cpu_data_in_proc : process (all)
  begin
    c64_ram_data <= x"00";

    -- We are emulating what is written here: https://www.c64-wiki.com/wiki/Reset_Button
    -- and avoid that the KERNAL ever sees the CBM80 signature during hard reset reset.
    -- But we cannot do it like on real hardware using the exrom signal because the
    -- MiSTer core is not supporting this.
    if hard_reset_n = '0' and c64_ram_addr_o(15 downto 12) = x"8" and cold_start_done = '1' then
      c64_ram_data <= x"00";

    -- Access the hardware cartridge
    elsif c64_exp_port_mode_i(C_SIM_CRT) = '0' and (cart_out_roml_n = '0' or cart_out_romh_n = '0' or core_umax_unmapped = '1') then
      c64_ram_data <= cart_in_data;

    -- Access the simulated cartridge
    elsif c64_exp_port_mode_i(C_SIM_CRT) = '1' and (cart_out_roml_n = '0' or cart_out_romh_n = '0' or core_ioe = '1' or core_iof = '1') then
      c64_ram_data <= unsigned(crt_ram_data_i)                 when cart_out_roml_n = '0' and crt_roml_we       = '1'                           else
                      unsigned(crt_lo_ram_data_i(15 downto 8)) when cart_out_roml_n = '0' and crt_addr_bus_o(0) = '1'                           else
                      unsigned(crt_lo_ram_data_i( 7 downto 0)) when cart_out_roml_n = '0' and crt_addr_bus_o(0) = '0'                           else
                      unsigned(crt_hi_ram_data_i(15 downto 8)) when cart_out_romh_n = '0' and crt_addr_bus_o(0) = '1'                           else
                      unsigned(crt_hi_ram_data_i( 7 downto 0)) when cart_out_romh_n = '0' and crt_addr_bus_o(0) = '0'                           else
                      unsigned(crt_lo_ram_data_i(15 downto 8)) when core_ioe    = '1' and crt_addr_bus_o(0) = '1' and  crt_ioe_wr_ena = '0' else
                      unsigned(crt_lo_ram_data_i( 7 downto 0)) when core_ioe    = '1' and crt_addr_bus_o(0) = '0' and  crt_ioe_wr_ena = '0' else
                      unsigned(crt_lo_ram_data_i(15 downto 8)) when core_iof    = '1' and crt_addr_bus_o(0) = '1' and  crt_iof_wr_ena = '0' else
                      unsigned(crt_lo_ram_data_i( 7 downto 0)) when core_iof    = '1' and crt_addr_bus_o(0) = '0' and  crt_iof_wr_ena = '0' else
                      unsigned(crt_ioe_ram_data_i)             when core_ioe    = '1'                             and  crt_ioe_wr_ena = '1' else
                      unsigned(crt_iof_ram_data_i)             when core_iof    = '1'                             and  crt_iof_wr_ena = '1' else
                      x"EE";

    -- Standard access to the C64's RAM
    else
      c64_ram_data <= c64_ram_data_i;
    end if;
  end process cpu_data_in_proc;

  -- RAM write enable also needs to check for chip enable
  c64_ram_we_o <= c64_ram_ce and c64_ram_we;

  --------------------------------------------------------------------------------------------------
  -- MiSTer Commodore 64 core / main machine
  --------------------------------------------------------------------------------------------------

  fpga64_sid_iec_inst : entity work.fpga64_sid_iec
    port map (
      clk32         => clk_main_i,
      clk32_speed   => clk_main_speed_i,
      reset_n       => reset_core_n,

      -- Select C64's ROM: 0=Custom, 1=Standard, 2=GS, 3=Japan
      bios          => c64_rom_i,

      pause         => pause_i,
      pause_out     => c64_pause,          -- unused

      -- keyboard interface: directly connect the CIA1
      cia1_pa_i     => cia1_pa_in,
      cia1_pa_o     => cia1_pa_out,
      cia1_pb_i     => cia1_pb_in,
      cia1_pb_o     => cia1_pb_out,

      -- external memory
      ramaddr       => c64_ram_addr_o,     -- output
      ramdin        => c64_ram_data,       -- input
      ramdout       => c64_ram_data_o,     -- output
      ramce         => c64_ram_ce,         -- output
      ramwe         => c64_ram_we,         -- output

      io_cycle      => open,
      ext_cycle     => sim_ext_cycle,
      refresh       => open,

      cia_mode      => c64_cia_ver_i,      -- 0 - 6526 "old", 1 - 8521 "new"

      -- Turbo Mode
      turbo_mode    => "00",
      turbo_speed   => "00",
      sim_crt_i     => c64_exp_port_mode_i(C_SIM_CRT), -- turbo mode for SIMCRTs and protection for hardware cartridges

      -- VGA/SCART interface
      -- The hsync frequency is 15.64 kHz (period 63.94 us).
      -- The hsync pulse width is 12.69 us.
      ntscmode      => c64_ntsc_i,
      hsync         => vga_hs,
      vsync         => vga_vs,
      r             => vga_red,
      g             => vga_green,
      b             => vga_blue,

      -- cartridge port
      game          => core_game_n,        -- input: low active
      exrom         => core_exrom_n,       -- input: low active
      io_rom        => core_io_rom,        -- input
      io_ext        => core_io_ext,        -- input
      io_data       => core_io_data,       -- input
      irq_n         => core_irq_n,         -- input: low active
      nmi_n         => core_nmi_n,         -- input: important: in parallel with SIMCRT's or HW CRT's NMI, we always need to deliver the Restore key here, too. Otherwise Restore will never generate an NMI as it should.
      nmi_ack       => core_nmi_ack,       -- output
      ba            => core_ba,            -- output
      roml          => core_roml,          -- output: CPU access to 0x8000-0x9FFF
      romh          => core_romh,          -- output: CPU access to 0xA000-0xBFFF or 0xE000-0xFFFF (ultimax)
      umaxromh      => core_umax_romh,     -- output
      umaxnomap     => core_umax_unmapped, -- output
      ioe           => core_ioe,           -- output: aka IO1. CPU access to 0xDExx
      iof           => core_iof,           -- output: aka IO2. CPU access to 0xDFxx
      dotclk        => core_dotclk,        -- output
      phi2          => core_phi2,          -- output

      -- dma access
      dma_req       => core_dma_req,       -- input
      dma_cycle     => core_dma_cycle,     -- output
      dma_addr      => core_dma_addr,      -- input
      dma_dout      => core_dma_dout,      -- input
      dma_din       => core_dma_din,       -- output
      dma_we        => core_dma_we,        -- input
      irq_ext_n     => core_irq_ext_n,     -- input

      -- paddle interface
      pot1          => pot1_x_i,
      pot2          => pot1_y_i,
      pot3          => pot2_x_i,
      pot4          => pot2_y_i,

      -- SID
      audio_l       => c64_sid_l,
      audio_r       => c64_sid_r,
      sid_filter    => "11",               -- filter enable = true for both SIDs, low bit = left SID
      sid_ver       => c64_sid_ver_i,      -- SID version, 0=6581, 1=8580, low bit = left SID
      sid_mode      => c64_sid_port_i,     -- Right SID Port: 0=same as left, 1=DE00, 2=D420, 3=D500, 4=DF00
      sid_cfg       => "0000",             -- filter type: 0=Default, 1=Custom 1, 2=Custom 2, 3=Custom 3, lower two bits = left SID

      -- mechanism for loading custom SID filters: not supported, yet
      sid_ld_clk    => '0',
      sid_ld_addr   => "000000000000",
      sid_ld_data   => x"0000",
      sid_ld_wr     => '0',

      -- User Port: Unused inputs need to be high
      pb_i          => x"FF",
      pb_o          => open,
      pa2_i         => '1',
      pa2_o         => open,
      pc2_n_o       => open,
      flag2_n_i     => '1',
      sp2_i         => '1',
      sp2_o         => open,
      sp1_i         => '1',
      sp1_o         => open,
      cnt2_i        => '1',
      cnt2_o        => open,
      cnt1_i        => '1',
      cnt1_o        => open,

      -- IEC
      iec_clk_i     => c64_iec_clk_in and hw_iec_clk_n_in,
      iec_clk_o     => c64_iec_clk_out,
      iec_atn_o     => c64_iec_atn_out,
      iec_data_i    => c64_iec_data_in and hw_iec_data_n_in,
      iec_data_o    => c64_iec_data_out,

      -- Cassette drive
      cass_write    => cass_write,         -- output
      cass_motor    => cass_motor,         -- output

      -- @TODO: This is a temporary fix for https://github.com/MJoergen/C64MEGA65/issues/187
      -- We need to make the RTC configurable and then either connect cass_rtc to cass_sense when
      -- the user activates the RTC in the OSM or '1' (since low active) when it is NOT active.
      -- cass_sense  => cass_rtc,         -- input
      cass_sense    => '1',

      -- On a real C64 the cassette read line and the IEC SRQ line share the same PCB trace and
      -- both feed CIA1's /FLAG pin (edge-triggered IRQ source). We route the IEC SRQ here so that
      -- IEC devices using SRQ (e.g. the Meatloaf modem emulation) work. Both lines are low active,
      -- so we AND them; the cassette read line is still hardcoded '1' (inactive) until #187 wires it.
      -- See https://github.com/MJoergen/C64MEGA65/issues/219
      cass_read     => hw_iec_srq_n_in and '1',

      -- Access custom Kernal: C64's Basic and DOS
      c64rom_clk_i  => c64_clk_sd_i,
      c64rom_we_i   => c64rom_we_i,
      c64rom_addr_i => c64rom_addr_i,
      c64rom_data_i => c64rom_data_i,
      c64rom_data_o => c64rom_data_o
    ); -- fpga64_sid_iec_inst

  --------------------------------------------------------------------------------------------------
  -- Expansion Port (aka Cartridge Port) handling:
  --    * MEGA65's hardware expansion port
  --    * Simulated 1750 REU 512KB
  --    * Simulated cartridge using data from .crt file
  --------------------------------------------------------------------------------------------------

  -- Combinational pre-register address (includes Ultimax A14/A15 override).
  -- According to "The PLA Dissected", A12-A15 are pulled up by RP4 whenever the
  -- VIC-II has the bus, so they appear as %1111 to the cart in Ultimax mode.
  cart_out_a <= "11" & c64_ram_addr_o(13 downto 0) when core_umax_romh = '1'
                else c64_ram_addr_o;

  -- Live (combinational) and registered (one-cycle-held) "is the current access targeting
  -- the cart"? The live view leads the cart pins by one clk_main_i tick; the registered
  -- view is in phase with what the cartridge physically sees on /ROML, /ROMH, /IO1, /IO2.
  -- The data-direction envelope below uses both: live opens the window for early release /
  -- early write-data setup, registered holds the window closed through the pin tail.
  cart_out_sel <= '1' when cart_out_roml_n   = '0' or cart_out_romh_n   = '0' or
                            cart_out_io1_n    = '0' or cart_out_io2_n    = '0' or
                            core_umax_unmapped   = '1' else '0';

  -- The address mux in fpga64_buslogic.vhd has multiple inputs (cpuHasBus, aec, cpuAddr,
  -- vicAddr) that change on the same clock edge, producing combinational glitches during
  -- CPU<->VIC bus handoffs. These glitches reach the Expansion Port connector on address,
  -- ROML, ROMH, IO1, IO2, and R/W and would corrupt edge-triggered cart sampling.
  --
  -- We register the six pin-facing signals here through a single flip-flop stage, which
  -- filters out the transient values and presents only stable, post-settling values at the
  -- cart pin (cart_out_a_q, cart_out_roml_n_q, cart_out_romh_n_q, cart_out_io1_n_q, cart_out_io2_n_q, cart_out_rw_q).
  --
  -- We also register cart_out_d_q, a one-cycle-delayed copy of the C64's outgoing write byte,
  -- to hold valid write data during the registered tail of a cart write.
  --
  -- BA and dotclock are NOT registered because they come from clean register outputs in
  -- the core (VIC-II output and clock divider respectively) with no combinational mux
  -- upstream that could glitch.
  --
  -- PHI2 is NOT registered as it is already generated cart-port-faithful in fpga64_sid_iec.vhd
  cart_output_pipeline_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      cart_out_a_q      <= cart_out_a;            -- includes Ultimax override
      cart_out_roml_n_q <= cart_out_roml_n;
      cart_out_romh_n_q <= cart_out_romh_n;
      cart_out_io1_n_q  <= cart_out_io1_n;
      cart_out_io2_n_q  <= cart_out_io2_n;
      cart_out_rw_q     <= not c64_ram_we;
      cart_out_d_q      <= c64_ram_data_o;
      cart_out_sel_q    <= cart_out_sel;
    end if;
  end process cart_output_pipeline_proc;

  -- Cartridge input ports are treated as asynchronuous to clk_main_i and must be registered to avoid metastability.
  -- From UG473 Chapter 1 we have this wonderful paragraph:
  --   The setup time of the block RAM address and write enable pins must not be violated.  Violating the address setup
  --   time (even if write enable is Low) can corrupt the data contents of the block RAM.
  -- Without these input registers we do indeed see corruption of Block RAM.
  cart_input_pipeline_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      cart_in_dma_n_q   <= cart_dma_i;
      cart_in_reset_n_q <= cart_reset_i;
      cart_in_game_n_q  <= cart_game_i;
      cart_in_exrom_n_q <= cart_exrom_i;
      cart_in_nmi_n_q   <= cart_nmi_i;
      cart_in_irq_n_q   <= cart_irq_i;
      cart_in_roml_n_q  <= cart_roml_i;
      cart_in_romh_n_q  <= cart_romh_i;
      cart_in_ba_q      <= cart_ba_i;
      cart_in_rw_q      <= cart_rw_i;
      cart_in_io1_n_q   <= cart_io1_i;
      cart_in_io2_n_q   <= cart_io2_i;
      cart_in_a_q       <= cart_a_i;
      cart_in_d_q       <= cart_d_i;
    end if;
  end process cart_input_pipeline_proc;

  -- Handle signals that go to the Expansion Port hardware
  handle_hardware_expansion_proc : process (all)
  begin
    -- C64 Expansion Port (aka Cartridge Port) control lines
    -- *_en is low active else tri-state high impedance
    -- *_dir=1 means FPGA->Port, =0 means Port->FPGA

    -- Tristate all expansion port drivers that we can directly control
    -- @TODO: As soon as we support modules that can act as busmaster, we need to become more flexible here
    cart_ctrl_oe_o  <= '0';
    cart_addr_oe_o  <= '0';
    cart_data_oe_o  <= '0';

    -- Due to a bug in the R5/R6 boards, the cartridge port needs ALWAYS to be enabled,
    -- otherwise joystick port B is not working correctly
    cart_en_o       <= '1';

    -- For the time being, we are treating GAME, EXROM, NMI and IRQ as READ-ONLY on all board revisions at all times
    -- @TODO: As soon as we support more sophisticted modules, we need to become more flexible here, too
    cart_game_oe_o  <= '0';
    cart_exrom_oe_o <= '0';
    cart_nmi_oe_o   <= '0';
    cart_irq_oe_o   <= '0';

    -- For the time being, we are treating ROML and ROMH as WRITE-ONLY at all times, as soon as c64_exp_port_mode_i(C_SIM_CRT) = '0',
    -- so the "zero" here is just the deactivated output driver as long as the core is in a non-hardware cartridge mode
    -- and it will be switched to OUTPUT (WRITE-ONLY) in the code that follows below
    cart_roml_oe_o  <= '0';
    cart_romh_oe_o  <= '0';

    -- Bi-directional reset handling:
    -- The "zero" here is (similar to above) just the deactivated output in non-hardware cartridge mode.
    -- As soon as hardware cartridge mode is on, we will switch back and forth between READ and WRITE.
    -- On R3/R3A boards, we will never be able to read, because the driver is uni-directional output-only.
    -- This fact is mitigated by top_mega65-r3.vhd setting cart_in_reset_n_q to '1' and therefore we are always
    -- "reading" the situation "no reset from the cartridge" on R3/R3A boards.
    -- But on R5/R6 and newer boards, we will be able to sense the reset from the cartridge and therefore we will
    -- not need cartridge_heuristics_inst and handle_cartridge_triggered_resets. Instead, cartridges like the EF3
    -- and the KFF "are just working" on these newer boards.
    cart_reset_oe_o <= '0';

    -- Default values for all signals
    cart_phi2_o     <= '0';
    cart_reset_o    <= '1';
    cart_dotclock_o <= '0';
    cart_game_o     <= '1';
    cart_exrom_o    <= '1';
    cart_nmi_o      <= '1';
    cart_irq_o      <= '1';
    cart_roml_o     <= '0';
    cart_romh_o     <= '0';
    cart_ba_o       <= '0';     -- controlled by cart_ctrl_oe_o
    cart_rw_o       <= '0';     -- controlled by cart_ctrl_oe_o
    cart_io1_o      <= '0';     -- controlled by cart_ctrl_oe_o
    cart_io2_o      <= '0';     -- controlled by cart_ctrl_oe_o
    cart_a_o        <= (others => '0');
    cart_d_o        <= (others => '0');

    cart_in_nmi_n      <= '1';
    cart_in_irq_n      <= '1';
    cart_in_dma_n      <= '1';
    cart_in_exrom_n    <= '1';
    cart_in_game_n     <= '1';
    cart_in_data  <= x"00";

    -- memory access flags
    cart_out_roml_n     <= not core_roml;
    cart_out_romh_n     <= (not core_romh) and (not core_umax_romh);  -- normal ROMH and Ultimax VIC access ROMH
    cart_out_io1_n      <= not core_ioe;
    cart_out_io2_n      <= not core_iof;

    -- Default is to connect the CORE's DMA interface to the SIMREU
    core_dma_req    <= core_dma;
    reu_dma_cycle   <= core_dma_cycle;
    core_dma_addr   <= unsigned(reu_dma_addr);
    core_dma_dout   <= unsigned(reu_dma_dout);
    reu_dma_din     <= core_dma_din;
    core_dma_we     <= reu_dma_we;
    core_irq_ext_n  <= not reu_irq;

    -- Mode = Use hardware slot
    if c64_exp_port_mode_i(C_SIM_CRT) = '0' then
      -- Hardcoded to WRITE-ONLY (OUTPUT) for the time being
      cart_ctrl_oe_o  <= '1';
      cart_roml_oe_o  <= '1';
      cart_romh_oe_o  <= '1';

      -- Bi-directional RESET handling:
      -- Default is: READ (aka sense reset from the cartridge). We are switching this to WRITE
      -- as soon as there is a reset from the core that needs to be transmitted to the cartridge.
      -- cart_reset_o is low active, so by default, cart_reset_oe_o is zero (aka READ).
      -- We also need to ensure that we are not transmitting any reset that comes from the cartridge
      -- itself, because in such a case the cartridge wants to reset the C64 but does not want to be reset by the C64,
      -- which is why we use reset_core_int_n instead of reset_core_n.
      cart_reset_o    <= reset_core_int_n when cart_reset_counter = 0 and cart_res_flckr_ign = 0 else '1';
      cart_reset_oe_o <= not cart_reset_o;

      -- Directly use the core's phi2, dotclock and BA signal for the physical output...
      cart_phi2_o     <= core_phi2;
      cart_dotclock_o <= core_dotclk;
      cart_ba_o       <= core_ba;

      -- ...but use registered versions of address, ROML, ROMH, IO1, IO2 and RW to avoid glitches.
      --
      -- See comment block before cart_output_pipeline_proc to understand the separation
      -- of unregistered and registered signals here.
      cart_a_o        <= cart_out_a_q;      -- Ultimax override is baked in via cart_out_a
      cart_roml_o     <= cart_out_roml_n_q;
      cart_romh_o     <= cart_out_romh_n_q;
      cart_io1_o      <= cart_out_io1_n_q;
      cart_io2_o      <= cart_out_io2_n_q;
      cart_rw_o       <= cart_out_rw_q;

      -- Connect physical input lines (use registered signals to avoid metastability)
      cart_in_nmi_n      <= cart_in_nmi_n_q;
      cart_in_irq_n      <= cart_in_irq_n_q;
      cart_in_dma_n      <= cart_in_dma_n_q;
      cart_in_exrom_n    <= cart_in_exrom_n_q;
      cart_in_game_n     <= cart_in_game_n_q;

      -- Default in non-DMA mode
      cart_addr_oe_o  <= '1';

      -- Switch the data lines bi-directionally so that the CPU can also
      -- write to the cartridge, e.g. for bank switching.
      --
      -- Envelope on the level-shifter direction (cart_data_oe_o) AND on the outgoing
      -- write data (cart_d_o): the live decode opens the cart-read / cart-write window
      -- one clk_main_i tick before the cart pins (/ROML, /ROMH, /IO1, /IO2, R/W, A0..A15)
      -- update, and the registered decode keeps it open for one tick after the pins
      -- update again. That gives the cart "release early" / "drive early" at the leading
      -- edge of an access (a small bus-settle margin before /ROML asserts) and "hold
      -- late" at the trailing edge (no FPGA-vs-cart contention while /ROML still shows
      -- asserted at the connector). Also kills combinational-glitch propagation onto
      -- F_DATA_DIR for the same reason the strobe pipeline kills it onto the strobes.

      if cart_in_dma_n_q = '0' then
        -- When changing to DMA mode, we first set the FPGA pins to input (tristate)
        -- because the cartridge is driving the buses
        cart_ctrl_oe_o  <= '0';
        cart_addr_oe_o  <= '0';
        cart_data_oe_o  <= '0';

        -- Sample the values on the cartridge port
        -- and forward to the CORE's DMA interface.
        core_dma_addr  <= unsigned(cart_in_a_q);
        core_dma_dout  <= unsigned(cart_in_d_q);
        core_dma_we    <= not cart_in_rw_q;
        cart_d_o       <= core_dma_din;
        cart_data_oe_o <= cart_in_rw_q;

        if core_ba = '0' then
          -- When in DMA mode we need to sense the cart_in_rw_q pin. However, we also need to drive the cart_ba_o output.
          -- Due to a hardware limitation, we can not do both at the same time. Fortunately, we don't need to,
          -- since when BA is to be driven low, we don't care about the RW signal.
          -- When VIC needs the bus, set cartridge signals to safe values
          cart_ctrl_oe_o <= '1';
          cart_ba_o      <= '0';
          cart_io1_o     <= '1';
          cart_io2_o     <= '1';
          cart_rw_o      <= '1';
          cart_data_oe_o <= '0'; -- Leave data bus floating
        end if;
      elsif (c64_ram_we = '0' and cart_out_sel = '1') or (cart_out_rw_q = '1' and cart_out_sel_q = '1') then
        cart_data_oe_o <= '0';                  -- input (FPGA tri-stated, cart may drive)
        cart_in_data <= cart_in_d_q;
      else
        cart_data_oe_o <= '1';                  -- output (FPGA drives)
        if c64_ram_we = '1' and cart_out_sel = '1' then
          cart_d_o <= c64_ram_data_o;           -- live cart write: drive byte early for setup margin
        elsif cart_out_rw_q = '0' and cart_out_sel_q = '1' then
          cart_d_o <= cart_out_d_q;                 -- registered cart write: hold byte through the pin tail
        elsif c64_ram_we = '0' then
          cart_d_o <= c64_ram_data_i;           -- preserved non-cart default: mirror C64 read data
        else
          cart_d_o <= c64_ram_data_o;           -- preserved non-cart default: mirror C64 write data
        end if;
      end if;
    end if;
  end process handle_hardware_expansion_proc;

  handle_cores_expansion_port_signals_proc : process (all)
    variable core_dma_v : std_logic;
  begin
    core_io_rom    <= '0';
    core_irq_n     <= '1';
    reu_iof        <= '0';
    crt_addr_bus_o <= c64_ram_addr_o;

    core_dma_v := '0';

    if c64_exp_port_mode_i(C_SIM_CRT) = '1' then
      -- Simulated cartridge using data from .crt file
      core_game_n  <= crt_game;
      core_exrom_n <= crt_exrom;
      core_dma_v   := cartridge_loading_i or crt_bank_wait_i;
      core_io_rom  <= crt_io_rom;
      core_io_ext  <= crt_io_ext;
      core_io_data <= unsigned(crt_io_data);
      if core_umax_romh = '1' then
        -- Ultimax mode and VIC accesses the bus: we need to translate the address, see comment about "The PLA Dissected" above
        crt_addr_bus_o <= "11" & c64_ram_addr_o(13 downto 0);
      end if;
      core_nmi_n <= not crt_nmi; -- SIMCRT controls the NMI to the CPU which includes the Restore key
    else
      -- Use hardware slot
      core_game_n  <= cart_in_game_n;
      core_exrom_n <= cart_in_exrom_n;
      core_irq_n   <= cart_in_irq_n;
      core_nmi_n   <= cart_in_nmi_n and restore_key_n;
      core_io_ext  <= core_ioe or core_iof;
      core_io_data <= cart_in_data;
      core_dma_v   := not cart_in_dma_n; -- a hardware cart asserts /DMA (active low) to request a CPU DMA hold
    end if;

    if c64_exp_port_mode_i(C_SIM_REU) = '1' then
      -- Simulate 1750 REU 512KB
      core_dma_v   := core_dma_v or reu_dma_req;
      if c64_ram_addr_o(15 downto 5) = X"DF" & "000" then
        -- Only address range $DF00 to $DF1F is forwarded to SIMREU.
        -- See issue #208.
        core_io_ext  <= reu_oe;
        core_io_data <= reu_dout;
        reu_iof      <= core_iof;
      end if;
    end if;

    core_dma <= core_dma_v;
  end process handle_cores_expansion_port_signals_proc;

  -- Detect certain hardware cartridges that need a special treatment due to unidirectional reset, irq or nmi signals
  cartridge_heuristics_inst : entity work.cartridge_heuristics
    port map (
      clk_main_i     => clk_main_i,
      reset_core_n_i => reset_core_n,
      cart_exrom_n_i => cart_in_exrom_n,
      cart_game_n_i  => cart_in_game_n,
      cart_io1_n_i   => cart_out_io1_n,
      cart_io2_n_i   => cart_out_io2_n,
      c64_ram_we_i   => c64_ram_we,
      c64_ram_addr_i => std_logic_vector(c64_ram_addr_o),
      phi2_i         => core_phi2,
      is_an_ef3_o    => cart_is_an_ef3
    ); -- cartridge_heuristics_inst

  -- Cartridge-specific workaround due to the fact, that R3/R3A and R4 boards do not allow cartridges to pull the reset line to low (i.e. trigger a reset)
  handle_cartridge_triggered_resets_proc : process (clk_main_i)
  begin
    if G_BOARD = "MEGA65_R3" or G_BOARD = "MEGA65_R4" then
      if rising_edge(clk_main_i) then
        core_phi2_prev <= core_phi2;

        -- In contrast to what is written above in the comment RESET SEMANTICS, we cannot use
        -- reset_core_n here because as soon as cart_reset_counter is > 0 reset_core_n goes low
        -- and then cart_reset_counter would be reset back to 0 prematurely
        if reset_soft_i = '1' or reset_hard_i = '1' then
          cart_reset_counter <= 0;
          cart_res_flckr_ign <= 0;

        -- The reset duration is measured in multiples of phi2 cycles
        elsif cart_reset_counter > 0 and core_phi2_prev = '1' and core_phi2 = '0' then
          cart_reset_counter <= cart_reset_counter - 1;
        end if;

        -- Avoid the "flickering" (trailing) output of the reset to the cartridge after reset_core_n goes high again after the reset
        if reset_core_n = '0' and cart_reset_counter = 0 and cart_res_flckr_ign /= 0 then
          cart_res_flckr_ign <= cart_res_flckr_ign - 1;
        end if;

        -------------------------------------------------------------------------------------------------
        -- EasyFlash 3
        -------------------------------------------------------------------------------------------------

        -- The EF3 needs to send a reset signal to the C64 core
        -- Learn more about the exact mechanics here: https://github.com/MJoergen/C64MEGA65/issues/60
        -- And/or look at the EF3 source code:
        --   What happens when "start-entry" key is pressed in the main menu: https://gitlab.com/easyflash/easyflash3-bootimage/-/blob/master/efmenu/src/efmenu.c#L361
        --   Set the EF ROM bank and change to the given cartridge mode: https://gitlab.com/easyflash/easyflash3-bootimage/-/blob/master/efmenu/src/efmenu_asm.s#L96
        if cart_is_an_ef3 = '1' and c64_ram_we = '1' and cart_out_io1_n = '0' and c64_ram_addr_o = x"DE0F" then
          -- Modes that lead to a reset: https://gitlab.com/easyflash/easyflash3-core/-/blob/master/src/ef3.vhdl#L695
          -- We are deliberately not supporting the Kernal mode x"02" of the EF3, because in Kernal mode, the EF3 manipulates the address line A14.
          -- While we could emulate the behavior on our side of the transciever, the problem is, that the transciever and the EF3 would fight" against
          -- each other: There might be situations where the core sets A14 to zero while the EF3 sets it to one and this "fight" would lead to quite
          -- some current flowing which might damage either the MEGA65's transciever or the EF3's CPLD or other logic parts.
          if c64_ram_data_o = x"00" or c64_ram_data_o = x"04" or c64_ram_data_o = x"05" or c64_ram_data_o = x"07" then
            cart_reset_counter <= C_EF3_RESET_LEN;
            cart_res_flckr_ign <= 2; -- avoid a short cart_reset_o after cart_reset_counter reached zero
          end if;
        end if;
      end if;

    -- Boards newer than R3/R3A/R4 do not need this workaround
    else
      cart_reset_counter <= 0;
      cart_res_flckr_ign <= 0;
    end if;
  end process handle_cartridge_triggered_resets_proc;

  --------------------------------------------------------------------------------------------------
  -- Simulated REU
  --------------------------------------------------------------------------------------------------

  -- REU configuration: "00":None, "01":512k, "10":2M, "11":16M
  reu_cfg         <= "01" when c64_exp_port_mode_i(C_SIM_REU) = '1' else
                     "00";

  reu_inst : component reu
    port map (
      clk       => clk_main_i,
      reset     => not reset_core_n,
      cfg       => reu_cfg,
      dma_req   => reu_dma_req,
      dma_cycle => reu_dma_cycle,
      dma_addr  => reu_dma_addr,
      dma_dout  => reu_dma_dout,
      dma_din   => std_logic_vector(reu_dma_din),
      dma_we    => reu_dma_we,
      ram_cycle => sim_reu_cycle,
      ram_addr  => sim_reu_addr,
      ram_dout  => sim_reu_dout,
      ram_din   => sim_reu_din,
      ram_we    => sim_reu_we,
      ram_cs    => sim_reu_cs,
      cpu_addr  => c64_ram_addr_o,
      cpu_dout  => c64_ram_data_o,
      cpu_din   => reu_dout,
      cpu_we    => c64_ram_we,
      cpu_cs    => reu_iof,
      irq       => reu_irq
    ); -- reu_inst

  reu_oe          <= reu_iof;

  --------------------------------------------------------------------------------------------------
  -- Simulated Cartridge
  --------------------------------------------------------------------------------------------------

  -- This component handles the CPU writes to $DExx and $DFxx for the bank switching and contains
  -- the simulated banking, EXROM/GAME, etc. behavior of all known cartridge types.
  --
  -- IMPORTANT: The component sets the correct exrom_o and game_o while cart_loading_i='1'.
  -- During a reset signal via "rst_i" exrom_o, game_o and other stateful signals are reset
  -- to the neutral state. Due to the fact, that sw_cartridge_wrapper uses a soft reset to
  -- make sure the C64 starts the cartridge, we must not reset cartridge_inst on soft reset.
  --
  -- cart_soft_reset is OR'd into cart_loading_i (NOT into rst_i): on OSM-driven soft resets
  -- this re-runs the global init block AND the per-cart case-arm's cart_loading_i='1'
  -- sub-clause, leaving cartridge_inst in the cart's autostart configuration. Using rst_i
  -- would leave exrom_o=1/game_o=1 (no cart visible) because the rst_i block sits AFTER
  -- the case statement and last-assignment-wins. Required for bank-switched carts.
  --
  -- Additionally we are outputting cart_soft_reset via cart_soft_reset_o, so that in mega65.vhd
  -- we can trigger a bank 0 cache reload in i_sw_cartridge_wrapper so that the CBM80 signature
  -- can be seen after the OSM-driven reset.
  cartridge_inst : entity work.cartridge
    port map (
      clk_i          => clk_main_i,
      rst_i          => not hard_reset_n,
      cart_loading_i => cartridge_loading_i or cart_soft_reset,
      cart_id_i      => cartridge_id_i,
      cart_exrom_i   => cartridge_exrom_i,
      cart_game_i    => cartridge_game_i,
      cart_size_i    => cartridge_size_i,
      ioe_i          => core_ioe,         -- Access to $DExx
      iof_i          => core_iof,         -- Access to $DFxx
      wr_en_i        => c64_ram_we,
      wr_data_i      => std_logic_vector(c64_ram_data_o),
      addr_i         => std_logic_vector(c64_ram_addr_o),
      bank_lo_o      => crt_bank_lo_o,
      bank_hi_o      => crt_bank_hi_o,
      ioe_wr_ena_o   => crt_ioe_wr_ena,
      iof_wr_ena_o   => crt_iof_wr_ena,
      io_rom_o       => crt_io_rom,
      io_ext_o       => crt_io_ext,
      io_data_o      => crt_io_data,
      exrom_o        => crt_exrom,
      game_o         => crt_game,
      roml_we_o      => crt_roml_we,
      freeze_key_i      => (not restore_key_n) or (not freeze_key_n),
      suppress_freeze_i => not restore_key_n,
      nmi_o          => crt_nmi,
      nmi_ack_i      => core_nmi_ack
    ); -- cartridge_inst

  -- Values written to $9Fxx are also written to $Dxxx when crt_iox_wr_ena is set.
  -- This is relevant for Action Replay cartridge, see this schematic:
  -- https://www.zimmers.net/anonftp/pub/cbm/schematics/cartridges/c64/freezer/MK.gif
  -- Input to PLA is "10101001" and the output is "0101" indicating access to cartridge RAM.
  crt_addr_9exx   <= '1' when c64_ram_addr_o(12 downto 8) = "11110" else '0';
  crt_addr_9fxx   <= '1' when c64_ram_addr_o(12 downto 8) = "11111" else '0';

  crt_ioe_we_o    <= (core_ioe or (core_roml and crt_ioe_wr_ena and crt_addr_9exx)) and c64_ram_we;
  crt_iof_we_o    <= (core_iof or (core_roml and crt_iof_wr_ena and crt_addr_9fxx)) and c64_ram_we;
  crt_we_o        <= core_roml and crt_roml_we and c64_ram_we;

  --------------------------------------------------------------------------------------------------
  -- Generate video output for the M2M framework
  --------------------------------------------------------------------------------------------------

  -- The M2M framework needs the signals vga_hblank_o, vga_vblank_o, and vga_ce_o.
  -- This shortens the hsync pulse width to 4.82 us, still with a period of 63.94 us.
  -- This also crops the signal to 382x270 via the vs_hblank and vs_vblank signals.
  --
  -- IMPORTANT: For the C64 core, we need to use the video_sync component that is located in
  -- "C64_MiSTerMEGA65/rtl/video_sync.vhd" and NOT the version that is located in the M2M framework.
  -- Reason: See commit message for commit 99c27fa
  video_sync_inst : entity work.video_sync
    port map (
      clk32     => clk_main_i,
      pause     => '0',
      hsync     => vga_hs,
      vsync     => vga_vs,
      ntsc      => '0',
      wide      => '0',
      hsync_out => video_hs_o,
      vsync_out => video_vs_o,
      hblank    => video_hblank_o,
      vblank    => video_vblank_o
    ); -- video_sync_inst

  video_red_o     <= std_logic_vector(vga_red);
  video_green_o   <= std_logic_vector(vga_green);
  video_blue_o    <= std_logic_vector(vga_blue);
  video_ce_o      <= '1' when video_ce = 0 else
                     '0';
  video_ce_ovl_o  <= '1' when video_retro15khz_i = '0' else
                     not video_ce(0);

  -- Clock divider: The core's pixel clock is 1/4 of the main clock
  video_ce_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      video_ce <= video_ce + 1;
    end if;
  end process video_ce_proc;

  --------------------------------------------------------------------------------------------------
  -- Keyboard- and joystick controller
  --------------------------------------------------------------------------------------------------

  -- Convert MEGA65 keystrokes to the C64 keyboard matrix that the CIA1 can scan
  -- and convert the MEGA65 joystick signals to CIA1 signals as well
  keyboard_inst : entity work.keyboard
    port map (
      clk_main_i      => clk_main_i,
      reset_i         => not reset_core_n,

      -- Trigger the sequence RUN<Return> to autostart PRG files
      trigger_run_i   => trigger_run_i,

      -- Interface to the MEGA65 keyboard
      key_num_i       => kb_key_num_i,
      key_pressed_n_i => kb_key_pressed_n_i,

      -- Interface to the MEGA65 joysticks
      joy_1_up_n_i    => joy_1_up_n_i,
      joy_1_down_n_i  => joy_1_down_n_i,
      joy_1_left_n_i  => joy_1_left_n_i,
      joy_1_right_n_i => joy_1_right_n_i,
      joy_1_fire_n_i  => joy_1_fire_n_i,

      joy_1_up_n_o    => joy_1_up_n_o,
      joy_1_down_n_o  => joy_1_down_n_o,
      joy_1_left_n_o  => joy_1_left_n_o,
      joy_1_right_n_o => joy_1_right_n_o,
      joy_1_fire_n_o  => joy_1_fire_n_o,

      joy_2_up_n_i    => joy_2_up_n_i,
      joy_2_down_n_i  => joy_2_down_n_i,
      joy_2_left_n_i  => joy_2_left_n_i,
      joy_2_right_n_i => joy_2_right_n_i,
      joy_2_fire_n_i  => joy_2_fire_n_i,

      joy_2_up_n_o    => joy_2_up_n_o,
      joy_2_down_n_o  => joy_2_down_n_o,
      joy_2_left_n_o  => joy_2_left_n_o,
      joy_2_right_n_o => joy_2_right_n_o,
      joy_2_fire_n_o  => joy_2_fire_n_o,

      -- Interface to the MiSTer C64 core that directly connects to the C64's CIA1 instead of
      -- going the detour of converting the MEGA65 keystrokes into PS/2 keystrokes first.
      -- This means, that the "fpga64_keyboard" entity of the original core is not used. Instead,
      -- we are modifying the "fpga64_sid_iec" entity so that we can route the CIA1's ports
      -- A and B into this keyboard driver which then emulates the behavior of the physical
      -- C64 keyboard including the possibility to "scan" via the row, i.e. pull one or more bits of
      -- port A to zero (one by one) and read via the "column" (i.e. from port B) or vice versa.
      cia1_pai_o      => cia1_pa_in,
      cia1_pao_i      => cia1_pa_out,
      cia1_pbi_o      => cia1_pb_in,
      cia1_pbo_i      => cia1_pb_out,

      -- Special keys
      restore_n       => restore_key_n,   -- Restore key = NMI
      freeze_n        => freeze_key_n     -- F9 key = freezer key for simulated cartridges
    ); -- keyboard_inst

  --------------------------------------------------------------------------------------------------
  -- MiSTer audio signal processing: Convert the core's 18-bit signal to a signed 16-bit signal
  --------------------------------------------------------------------------------------------------

  audio_processing_proc : process (all)
    variable alm, arm : std_logic_vector(16 downto 0);
  begin
    -- "alm" and "arm" are used to mix various audio sources
    -- Additional to SID, MiSTer supports OPL, DAC and the noise of the tape drive. All these sound
    -- inputs are meant to be added here (see c64.sv in the MiSTER source) as soon as we support it.
    alm(16)          := c64_sid_l(17);
    alm(15 downto 0) := c64_sid_l(17 downto 2);
    arm(16)          := c64_sid_r(17);
    arm(15 downto 0) := c64_sid_r(17 downto 2);

    -- Anti-overflow mechanism for alm and arm. Right now this is not yet needed, because we are
    -- not adding multiple audio sources, but as soon as we will do that in future, we are prepared
    if alm(16) /= alm(15) then
      alo(15)          <= alm(16);
      alo(14 downto 0) <= (others => alm(15));
    else
      alo <= alm(15 downto 0);
    end if;

    if arm(16) /= arm(15) then
      aro(15)          <= arm(16);
      aro(14 downto 0) <= (others => arm(15));
    else
      aro <= arm(15 downto 0);
    end if;
  end process audio_processing_proc;

  audio_left_o    <= signed(alo);
  audio_right_o   <= signed(aro);

  --------------------------------------------------------------------------------------------------
  -- Hardware IEC port
  --------------------------------------------------------------------------------------------------

  handle_hardware_iec_proc : process (all)
  begin
    iec_reset_n_o    <= '1';
    iec_atn_n_o      <= '1';
    iec_clk_en_o     <= '0';
    iec_clk_n_o      <= '1';
    iec_data_en_o    <= '0';
    iec_data_n_o     <= '1';

    -- Since IEC is a bus, we need to connect the input lines coming from the hardware port
    -- to all participants of the bus. At this time these are:
    --    C64: fpga64_sid_iec_inst using the iec_ signals
    --    Simulated disk drives: iec_drive_inst using the iec_ signals
    -- All signals are LOW active, so we need to AND them.
    -- As soon as we have more participants than just fpga64_sid_iec_inst and iec_drive_inst we will
    -- need to have some more signals for the bus instead of directly connecting them as we do today.
    hw_iec_clk_n_in  <= '1';
    hw_iec_data_n_in <= '1';

    -- SRQ: on a real C64 this line is connected to the cassette read line and feeds CIA1's /FLAG pin,
    -- generating an IRQ on falling edges. The C64 itself never drives SRQ (it only senses it), so we
    -- keep the output driver disabled and only read iec_srq_n_i. Some IEC devices use SRQ to interrupt
    -- the C64 (e.g. the Meatloaf modem emulation), so we route the (synchronized) input to CIA1 /FLAG
    -- via hw_iec_srq_n_in below. Default '1' (inactive) when the hardware IEC port is not enabled.
    -- See https://github.com/MJoergen/C64MEGA65/issues/219
    iec_srq_en_o     <= '0';
    iec_srq_n_o      <= '1';
    hw_iec_srq_n_in  <= '1';

    if iec_hardware_port_en_i = '1' then
      -- The IEC bus is low active. By default, we let the hardware bus lines float by setting the NC7SZ126P5X
      -- output driver's OE to zero. We hardcode all output lines to zero and as soon as we need to pull a line
      -- to zero, we activate the NC7SZ126P5X OE by setting it to one. This means that the actual signalling is
      -- done by changing the NC7SZ126P5X OE instead of changing the output lines to high/low. This ensures
      -- that the lines keep floating when we have "nothing to say" to the bus.
      iec_clk_n_o      <= '0';
      iec_data_n_o     <= '0';

      -- These lines are not connected to a NC7SZ126P5X since the C64 is supposed to be the only
      -- party in the bus who is allowed to pull this line to zero
      iec_reset_n_o    <= reset_core_n;
      iec_atn_n_o      <= c64_iec_atn_out;

      -- Read from the hardware IEC port (see comment above: We need to connect this to fpga64_sid_iec_inst and iec_drive_inst)
      hw_iec_clk_n_in  <= iec_clk_n_i;
      hw_iec_data_n_in <= iec_data_n_i;

      -- Route the synchronized SRQ input to CIA1 /FLAG (only while the hardware IEC port is active)
      hw_iec_srq_n_in  <= iec_srq_n_sync;

      -- Write to the IEC port by pulling the signals low and otherwise let them float (using the NC7SZ126P5X chip)
      -- We need to invert the logic, because if the C64 wants to pull something to LOW we need to ENABLE the NC7SZ126P5X's OE
      iec_clk_en_o     <= not c64_iec_clk_out;
      iec_data_en_o    <= not c64_iec_data_out;
    end if;
  end process handle_hardware_iec_proc;

  -- 2-FF synchronizer for the asynchronous IEC SRQ pin into the main clock domain.
  -- We deliberately do NOT debounce: SRQ feeds CIA1's edge-triggered /FLAG pin and debouncing
  -- could swallow short but legitimate pulses. The ~2 cycle latency (~63 ns) is irrelevant
  -- compared to the C64's ~1 us CPU cycle. See https://github.com/MJoergen/C64MEGA65/issues/219
  iec_srq_sync_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      iec_srq_n_d    <= iec_srq_n_i;
      iec_srq_n_sync <= iec_srq_n_d;
    end if;
  end process iec_srq_sync_proc;

  --------------------------------------------------------------------------------------------------
  -- MiSTer IEC drives
  --------------------------------------------------------------------------------------------------

  -- Parallel C1541 port: not implemented, yet
  iec_par_stb_in  <= '0';
  iec_par_data_in <= (others => '0');

  -- Drive is held to reset if the core is held to reset or if the drive is not mounted, yet.
  -- Exception (issue #90): while "Use internal 1581" is active, drive 8 is backed by the REAL
  -- internal mechanism, so there is no disk image to mount -- the drive must run unmounted.
  -- Without this exception the whole drive (and with it the forced-active 1581 engine inside
  -- iec_drive.sv) would stay in reset until a D81 image is mounted, making the physical drive
  -- dead unless the user mounts an unrelated image first. phys_1581_en_i is in the main clock
  -- domain (CDC-d OSM bit), like everything else in this equation.
  -- @TODO: MiSTer also allows these options when it comes to drive-enable:
  --        "P2oPQ,Enable Drive #8,If Mounted,Always,Never;"
  --        "P2oNO,Enable Drive #9,If Mounted,Always,Never;"
  --        This code currently only implements the "If Mounted" option

  iec_drives_reset(0) <= (not reset_core_n) or ((not vdrives_mounted(0)) and (not phys_1581_en_i));
  iec_drv_reset_gen : for i in 1 to G_VDNUM - 1 generate
    iec_drives_reset(i) <= (not reset_core_n) or (not vdrives_mounted(i));
  end generate iec_drv_reset_gen;

  iec_drive_inst : entity work.iec_drive
    generic map (
      PARPORT => 0, -- Parallel C1541 port for faster (~20x) loading time using DolphinDOS
      DUALROM => 1, -- Two switchable ROMs: Standard DOS and JiffyDOS
      DRIVES  => G_VDNUM
    )
    port map (
      clk          => clk_main_i,
      ce           => iec_drive_ce,
      reset        => iec_drives_reset,
      pause        => pause_i,

      -- interface to the C64 core
      iec_clk_i    => c64_iec_clk_out and hw_iec_clk_n_in,
      iec_clk_o    => c64_iec_clk_in,
      iec_atn_i    => c64_iec_atn_out,
      iec_data_i   => c64_iec_data_out and hw_iec_data_n_in,
      iec_data_o   => c64_iec_data_in,

      -- disk image status
      img_mounted  => iec_img_mounted,
      img_readonly => iec_img_readonly,
      img_size     => iec_img_size,
      img_type     => iec_img_type,                 -- 00=1541 emulated GCR(D64), 01=1541 real GCR mode (G64,D64), 10=1581 (D81)

      -- QNICE SD-Card/FAT32 interface
      clk_sys      => c64_clk_sd_i,                 -- "SD card" clock for writing to the drives' internal data buffers

      sd_lba       => iec_sd_lba,
      sd_blk_cnt   => iec_sd_blk_cnt,
      sd_rd        => iec_sd_rd,
      sd_wr        => iec_sd_wr,
      sd_ack       => iec_sd_ack,
      sd_buff_addr => iec_sd_buf_addr,
      sd_buff_dout => iec_sd_buf_data_in,           -- data from SD card to the buffer RAM within the drive ("dout" is a strange name)
      sd_buff_din  => iec_sd_buf_data_out,          -- read the buffer RAM within the drive
      sd_buff_wr   => iec_sd_buf_wr,

      -- drive led
      led          => c64_drive_led,

      -- Parallel C1541 port
      par_stb_i    => iec_par_stb_in,
      par_stb_o    => iec_par_stb_out,
      par_data_i   => iec_par_data_in,
      par_data_o   => iec_par_data_out,

      -- Access custom rom (DOS): All in QNICE clock domain but rom_std_i is in main clock domain
      rom_std_i    => c64_rom_i(0) or c64_rom_i(1), -- 1=use the factory default ROM
      rom_addr_i   => c1541rom_addr_i,
      rom_data_i   => c1541rom_data_i,
      rom_wr_i     => c1541rom_we_i,
      rom_data_o   => c1541rom_data_o,

      -- MEGA65 physical internal 1581 (issue #90): drive-0 ABI to the VHDL
      -- physical_1581_controller + rdfifo (both in the c64_clk_sd_i 50 MHz domain).
      -- Inert unless physical_mode=1, so image-mode behavior is unchanged.
      physical_mode      => phys_1581_en_i,

      -- phys OUTPUTS (iec_drive -> controller / rdfifo)
      phys_active        => p1581_active,
      phys_cia_motor_on  => p1581_cia_motor_on,
      phys_cia_side      => p1581_cia_side,
      phys_step_req_tgl  => p1581_step_req_tgl,
      phys_step_outward  => p1581_step_outward,
      phys_rd_req_tgl    => p1581_rd_req_tgl,
      phys_rd_op         => p1581_rd_op,
      phys_rd_track      => p1581_rd_track,
      phys_rd_side       => p1581_rd_side,
      phys_rd_sector     => p1581_rd_sector,
      phys_rd_cancel_tgl => p1581_rd_cancel_tgl,
      phys_rd_seq        => p1581_rd_seq,
      phys_byte_ovf      => open,          -- fdc1772 ties this 0; unused here
      phys_byte_rd_en    => p1581_byte_rd_en,

      -- phys INPUTS (controller / rdfifo -> iec_drive)
      phys_step_ack_tgl  => p1581_step_ack_tgl,
      phys_rd_done_tgl   => p1581_rd_done_tgl,
      phys_rd_done_seq   => p1581_rd_done_seq,
      phys_rd_result     => p1581_rd_result,
      phys_rd_crc_err    => p1581_rd_crc_err,
      phys_rd_rnf        => p1581_rd_rnf,
      phys_rd_deleted    => p1581_rd_deleted,
      phys_rd_c          => std_logic_vector(p1581_rd_c),
      phys_rd_h          => std_logic_vector(p1581_rd_h),
      phys_rd_r          => std_logic_vector(p1581_rd_r),
      phys_rd_n          => std_logic_vector(p1581_rd_n),
      phys_byte_data     => std_logic_vector(p1581_byte_data),
      phys_byte_empty    => p1581_byte_empty,
      phys_media_ready   => p1581_media_ready,
      phys_index         => p1581_index,
      phys_track0        => p1581_track0,
      phys_wprot         => p1581_wprot,
      phys_change        => p1581_change,
      phys_motor_on      => p1581_motor_on,
      phys_head_settled  => p1581_head_settled,

      -- fdc1772 delivery-v2 diagnostic taps (drive clock; synced/captured above
      -- and inside physical_1581_diag, see the p1581_dbg_* declarations)
      phys_dbg_lost_tgl      => p1581_dbg_lost_tgl,
      phys_dbg_drain_tgl     => p1581_dbg_drain_tgl,
      phys_dbg_staledone_tgl => p1581_dbg_staledone_tgl,
      phys_dbg_busycmd_tgl   => p1581_dbg_busycmd_tgl,
      phys_dbg_fin_tgl       => p1581_dbg_fin_tgl,
      phys_dbg_pres_cnt      => p1581_dbg_pres_cnt
    ); -- iec_drive_inst

  --------------------------------------------------------------------------------------------------
  -- Physical internal 1581 controller + read-byte FIFO (issue #90)
  --------------------------------------------------------------------------------------------------
  -- The controller lives in the QNICE 50 MHz domain (c64_clk_sd_i); its reset is
  -- c64_rst_sd_i (== qnice_rst one level up). The f_* mechanism pins connect ONLY
  -- here. The read-byte stream crosses back to the drive clock (clk_main_i) through
  -- the dual-clock rdfifo. G_CAPABLE=true on every board (feature gated by the OSM
  -- bit phys_1581_en_i, not by synthesis).
  i_physical_1581_controller : entity work.physical_1581_controller
    generic map (
      G_CAPABLE => true
    )
    port map (
      clk_i            => c64_clk_sd_i,
      rst_i            => c64_rst_sd_i,

      -- physical mechanism pins (straight through to the MEGA65_Core ports)
      f_rdata_i        => f_rdata_i,
      f_index_i        => f_index_i,
      f_track0_i       => f_track0_i,
      f_writeprotect_i => f_writeprotect_i,
      f_diskchanged_i  => f_diskchanged_i,
      f_motora_o       => f_motora_o,
      f_selecta_o      => f_selecta_o,
      f_side1_o        => f_side1_o,
      f_stepdir_o      => f_stepdir_o,
      f_step_o         => f_step_o,
      f_density_o      => f_density_o,

      -- mode + maintained mechanics requests (from iec_drive)
      phys_active_i    => p1581_active,
      cia_motor_on_i   => p1581_cia_motor_on,
      cia_side_i       => p1581_cia_side,

      -- Type-I step request (toggle handshake)
      step_req_tgl_i   => p1581_step_req_tgl,
      step_outward_i   => p1581_step_outward,
      step_ack_tgl_o   => p1581_step_ack_tgl,

      -- read operation request (toggle handshake)
      rd_req_tgl_i     => p1581_rd_req_tgl,
      rd_op_i          => p1581_rd_op,
      rd_track_i       => unsigned(p1581_rd_track),
      rd_side_i        => p1581_rd_side,
      rd_sector_i      => unsigned(p1581_rd_sector),
      rd_seq_i         => p1581_rd_seq,
      rd_cancel_tgl_i  => p1581_rd_cancel_tgl,
      rd_done_tgl_o    => p1581_rd_done_tgl,
      rd_done_seq_o    => p1581_rd_done_seq,
      rd_result_o      => p1581_rd_result,
      rd_crc_err_o     => p1581_rd_crc_err,
      rd_rnf_o         => p1581_rd_rnf,
      rd_deleted_o     => p1581_rd_deleted,
      rd_c_o           => p1581_rd_c,
      rd_h_o           => p1581_rd_h,
      rd_r_o           => p1581_rd_r,
      rd_n_o           => p1581_rd_n,

      -- read-byte stream to the external dual-clock FIFO (50 MHz write side)
      byte_data_o      => p1581_fifo_wr_data,
      byte_wr_o        => p1581_fifo_wr_en,
      byte_ovf_i       => p1581_fifo_wr_full,

      -- live normalized state to the drive domain
      st_media_ready_o => p1581_media_ready,
      st_index_o       => p1581_index,
      st_track0_o      => p1581_track0,
      st_wprot_o       => p1581_wprot,
      st_change_o      => p1581_change,
      st_motor_on_o    => p1581_motor_on,
      st_head_settled_o => p1581_head_settled,
      st_head_cyl_o    => p1581_head_cyl,
      st_locked_o      => p1581_locked,

      -- read-only diagnostic taps -> physical_1581_diag
      diag_index_period_o => p1581_diag_idx_period,
      diag_index_width_o  => p1581_diag_idx_width,
      diag_index_edge_o   => p1581_diag_index_edge,
      diag_index_qual_o   => p1581_diag_index_qual,
      diag_last_gap_o     => p1581_diag_last_gap,
      diag_calc_crc_o     => p1581_diag_calc_crc,
      diag_stored_crc_o   => p1581_diag_stored_crc,
      diag_id_valid_o     => p1581_diag_id_valid,
      diag_id_crc_ok_o    => p1581_diag_id_crc_ok,
      diag_data_end_o     => p1581_diag_data_end,
      diag_data_crc_ok_o  => p1581_diag_data_crc_ok,
      diag_gap_error_o    => p1581_diag_gap_error,
      diag_runt_o         => p1581_diag_runt,
      diag_est_o          => p1581_diag_est,
      diag_rd_phase_o     => p1581_diag_rd_phase,
      diag_step_phase_o   => p1581_diag_step_phase,
      diag_head_valid_o   => p1581_diag_head_valid,
      diag_head_dir_out_o => p1581_diag_head_dir,
      diag_rd_req_o        => p1581_diag_rd_req,
      diag_rd_req_op_o     => p1581_diag_rd_req_op,
      diag_rd_req_track_o  => p1581_diag_rd_req_trk,
      diag_rd_req_sector_o => p1581_diag_rd_req_sec,
      diag_rd_req_side_o   => p1581_diag_rd_req_side,
      diag_in_bits_o      => p1581_diag_in_bits,
      diag_out_bits_o     => p1581_diag_out_bits
    ); -- i_physical_1581_controller

  i_physical_1581_rdfifo : entity work.physical_1581_rdfifo
    generic map (
      -- Depth = 512 = one full physical sector, so a streamed read can NEVER
      -- overflow, no matter how long the drive CPU is away servicing IEC/IRQ
      -- work mid-sector (observed on hardware with the earlier 32-byte depth:
      -- silently dropped bytes -> shifted directory names, programs that load
      -- but do not run). The controller additionally reports any write-while-
      -- full as a data error so a drop can never again be silent.
      G_AW => 9
    )
    port map (
      -- write side: controller, 50 MHz (c64_clk_sd_i)
      wr_clk_i   => c64_clk_sd_i,
      wr_rst_i   => c64_rst_sd_i,
      wr_en_i    => p1581_fifo_wr_en,
      wr_data_i  => p1581_fifo_wr_data,
      wr_full_o  => p1581_fifo_wr_full,
      wr_level_o => p1581_fifo_level,
      -- read side: drive clock, clk_main_i (fdc1772 drains at its DRQ cadence).
      -- Reset by the SAME event as the write side (QNICE reset, synced into this
      -- domain) -- never by reset_core_n alone: a one-sided reset would zero the
      -- read Gray pointer against a live write pointer and permanently
      -- desynchronize the FIFO (stale/shifted CRC-clean sector data). Leftover
      -- bytes after a core reset are drained by fdc1772 while no op is delivering.
      rd_clk_i   => clk_main_i,
      rd_rst_i   => p1581_fiforst_s,
      rd_en_i    => p1581_byte_rd_en,
      rd_data_o  => p1581_byte_data,
      rd_empty_o => p1581_byte_empty
    ); -- i_physical_1581_rdfifo

  --------------------------------------------------------------------------------------------------
  -- Physical internal 1581 read-only QNICE diagnostic register bank (issue #90)
  --------------------------------------------------------------------------------------------------
  -- Device C_DEV_C64_PHYS1581 = 0x0108. Runs on c64_clk_sd_i (== QNICE clock ==
  -- controller clock), so it observes the controller with zero CDC. Strictly
  -- observational: it drives nothing back into the read path. See
  -- doc/1581_dd_debug_device.md for the register map and how to read it from QNICE.
  i_physical_1581_diag : entity work.physical_1581_diag
    port map (
      clk_i             => c64_clk_sd_i,
      rst_i             => c64_rst_sd_i,

      -- live controller state (existing st_* outputs)
      st_media_ready_i  => p1581_media_ready,
      st_index_i        => p1581_index,
      st_track0_i       => p1581_track0,
      st_wprot_i        => p1581_wprot,
      st_change_i       => p1581_change,
      st_motor_on_i     => p1581_motor_on,
      st_head_settled_i => p1581_head_settled,
      st_locked_i       => p1581_locked,
      st_head_cyl_i     => p1581_head_cyl,

      -- read result (latched on rd_done edge inside diag) + step handshake
      rd_done_tgl_i     => p1581_rd_done_tgl,
      rd_result_i       => p1581_rd_result,
      rd_crc_err_i      => p1581_rd_crc_err,
      rd_rnf_i          => p1581_rd_rnf,
      rd_deleted_i      => p1581_rd_deleted,
      rd_c_i            => p1581_rd_c,
      rd_h_i            => p1581_rd_h,
      rd_r_i            => p1581_rd_r,
      rd_n_i            => p1581_rd_n,
      step_ack_tgl_i    => p1581_step_ack_tgl,

      -- controller diagnostic observation taps
      diag_in_bits_i      => p1581_diag_in_bits,
      diag_out_bits_i     => p1581_diag_out_bits,
      diag_index_period_i => p1581_diag_idx_period,
      diag_index_width_i  => p1581_diag_idx_width,
      diag_last_gap_i     => p1581_diag_last_gap,
      diag_calc_crc_i     => p1581_diag_calc_crc,
      diag_stored_crc_i   => p1581_diag_stored_crc,
      diag_index_edge_i   => p1581_diag_index_edge,
      diag_index_qual_i   => p1581_diag_index_qual,
      diag_id_valid_i     => p1581_diag_id_valid,
      diag_id_crc_ok_i    => p1581_diag_id_crc_ok,
      diag_data_end_i     => p1581_diag_data_end,
      diag_data_crc_ok_i  => p1581_diag_data_crc_ok,
      diag_gap_error_i    => p1581_diag_gap_error,
      diag_est_i          => p1581_diag_est,
      diag_rd_phase_i     => p1581_diag_rd_phase,
      diag_step_phase_i   => p1581_diag_step_phase,
      diag_head_valid_i   => p1581_diag_head_valid,
      diag_head_dir_out_i => p1581_diag_head_dir,

      -- image-drive busy/dirty (main clock domain, 2-FF-synced above; issue #90 idle-gate)
      img_drive_busy_i    => img_busy_sd_s,

      -- WD-dialogue trace taps (issue #90 bring-up)
      rd_req_evt_i        => p1581_diag_rd_req,
      rd_req_op_i         => p1581_diag_rd_req_op,
      rd_req_track_i      => p1581_diag_rd_req_trk,
      rd_req_sector_i     => p1581_diag_rd_req_sec,
      rd_req_side_i       => p1581_diag_rd_req_side,

      -- delivery-v2 observability (map v4, issue #90 round 10): the five event
      -- toggles are 2-FF-synced above (p1581_dbg_sync_proc); pres_cnt crosses
      -- unsynced as a quasi-static bus captured inside on the synced fin edge;
      -- fifo level and runt pulse are native 50 MHz
      dbg_lost_i          => p1581_dbg_lost_sd_s,
      dbg_drain_i         => p1581_dbg_drain_sd_s,
      dbg_staledone_i     => p1581_dbg_staledone_sd_s,
      dbg_busycmd_i       => p1581_dbg_busycmd_sd_s,
      dbg_fin_i           => p1581_dbg_fin_sd_s,
      dbg_pres_cnt_i      => unsigned(p1581_dbg_pres_cnt),
      fifo_level_i        => p1581_fifo_level,
      runt_i              => p1581_diag_runt,

      -- QNICE read interface (from mega65.vhd core_specific_devices decode)
      qnice_ce_i        => phys_diag_ce_i,
      qnice_addr_i      => phys_diag_addr_i,
      qnice_data_o      => phys_diag_data_o
    ); -- i_physical_1581_diag

  -- 16 MHz chip enable for the IEC drives, so that ph2_r and ph2_f can be 1 MHz (C1541's CPU runs with 1 MHz)
  -- Uses a counter to compensate for clock drift, because the input clock is not exactly at 32 MHz
  --
  -- It is important that also in the HDMI-Flicker-Free-mode we are using the vanilla clock speed given by
  -- CORE_CLK_SPEED_PAL (or CORE_CLK_SPEED_NTSC) and not a speed-adjusted version of this speed. Reason:
  -- Otherwise the drift-compensation in generate_drive_ce will compensate for the slower clock speed and
  -- ensure an exact 32 MHz frequency even though the system has been slowed down by the HDMI-Flicker-Free.
  -- This leads to a different frequency ratio C64 vs 1541 and therefore to incompatibilities such as the
  -- one described in this GitHub issue:
  -- https://github.com/MJoergen/C64MEGA65/issues/2
  iec_drive_ce_proc : process (all)
    variable msum, nextsum : integer;
  begin
    msum    := clk_main_speed_i;
    nextsum := iec_dce_sum + 16000000;

    if rising_edge(clk_main_i) then
      iec_drive_ce <= '0';
      if reset_core_n = '0' then
        iec_dce_sum <= 0;
      else
        iec_dce_sum <= nextsum;
        if nextsum >= msum then
          iec_dce_sum  <= nextsum - msum;
          iec_drive_ce <= '1';
        end if;
      end if;
    end if;
  end process iec_drive_ce_proc;

  vdrives_inst : entity work.vdrives
    generic map (
      VDNUM => G_VDNUM, -- amount of virtual drives
      BLKSZ => 1        -- 1 = 256 bytes block size
    )
    port map (
      clk_qnice_i      => c64_clk_sd_i,
      clk_core_i       => clk_main_i,
      reset_core_i     => not reset_core_n,

      -- MiSTer's "SD config" interface, which runs in the core's clock domain
      img_mounted_o    => iec_img_mounted,
      img_readonly_o   => iec_img_readonly,
      img_size_o       => iec_img_size,
      img_type_o       => iec_img_type,   -- 00=1541 emulated GCR(D64), 01=1541 real GCR mode (G64,D64), 10=1581 (D81)

      -- While "img_mounted_o" needs to be strobed, "drive_mounted" latches the strobe in the core's clock domain,
      -- so that it can be used for resetting (and unresetting) the drive.
      drive_mounted_o  => vdrives_mounted,

      -- Cache output signals: The dirty flags is used to enforce data consistency
      -- (for example by ignoring/delaying a reset or delaying a drive unmount/mount, etc.)
      -- and to signal via "the yellow led" to the user that the cache is not yet
      -- written to the SD card, i.e. that writing is in progress
      cache_dirty_o    => cache_dirty,
      cache_flushing_o => open,

      -- MiSTer's "SD block level access" interface, which runs in QNICE's clock domain
      -- using dedicated signal on Mister's side such as "clk_sys"
      sd_lba_i         => iec_sd_lba,
      sd_blk_cnt_i     => iec_sd_blk_cnt, -- number of blocks-1
      sd_rd_i          => iec_sd_rd,
      sd_wr_i          => iec_sd_wr,
      sd_ack_o         => iec_sd_ack,

      -- MiSTer's "SD byte level access": the MiSTer components use a combination of the drive-specific sd_ack and the sd_buff_wr
      -- to determine, which RAM buffer actually needs to be written to (using the clk_qnice_i clock domain)
      sd_buff_addr_o   => iec_sd_buf_addr,
      sd_buff_dout_o   => iec_sd_buf_data_in,
      sd_buff_din_i    => iec_sd_buf_data_out,
      sd_buff_wr_o     => iec_sd_buf_wr,

      -- QNICE interface (MMIO, 4k-segmented)
      -- qnice_addr is 28-bit because we have a 16-bit window selector and a 4k window: 65536*4096 = 268.435.456 = 2^28
      qnice_addr_i     => c64_qnice_addr_i,
      qnice_data_i     => c64_qnice_data_i,
      qnice_data_o     => c64_qnice_data_o,
      qnice_ce_i       => c64_qnice_ce_i,
      qnice_we_i       => c64_qnice_we_i
    ); -- vdrives_inst

  --------------------------------------------------------------------------------------------------
  -- RAM used by the REU inside i_main
  --------------------------------------------------------------------------------------------------

  -- Consists of a three-stage pipeline:
  -- 1) main2hr_avm_fifo does the CDC using a FIFO (as the name suggests) by utilizing Xilinx the specific "xpm_fifo_axis":
  --    It connects to the raw HyperRAM Avalon Memory Mapped interface that M2M's arbiter offers and converts the
  --    signals into the core's clock domain
  -- 2) avm_cache_inst optimizes latency, particularly for longer, subsequent RAM accesses
  -- 3) reu_mapper_inst: Converts the Avalon interface into the interface that the REU expects PLUS
  --    it includes an optimization ("hack") that ensures that the REU is cycle accurate
  -- The result of stage (3) is then passed to i_main which uses these signals directly with MiSTer's reu_inst
  reu_mapper_inst : entity work.reu_mapper
    generic map (
      G_BASE_ADDRESS => X"0" & C_HMAP_REU & X"000"
    )
    port map (
      clk_i               => clk_main_i,
      rst_i               => not reset_core_n,
      reu_ext_cycle_i     => sim_ext_cycle,
      reu_ext_cycle_o     => sim_reu_cycle,
      reu_addr_i          => sim_reu_addr,
      reu_dout_i          => sim_reu_dout,
      reu_din_o           => sim_reu_din,
      reu_we_i            => sim_reu_we,
      reu_cs_i            => sim_reu_cs,
      avm_write_o         => map_write,
      avm_read_o          => map_read,
      avm_address_o       => map_address,
      avm_writedata_o     => map_writedata,
      avm_byteenable_o    => map_byteenable,
      avm_burstcount_o    => map_burstcount,
      avm_readdata_i      => map_readdata,
      avm_readdatavalid_i => map_readdatavalid,
      avm_waitrequest_i   => map_waitrequest
    ); -- reu_mapper_inst

  avm_cache_inst : entity work.avm_cache
    generic map (
      G_CACHE_SIZE   => 8,
      G_ADDRESS_SIZE => 32,
      G_DATA_SIZE    => 16
    )
    port map (
      clk_i                 => clk_main_i,
      rst_i                 => not reset_core_n,
      s_avm_waitrequest_o   => map_waitrequest,
      s_avm_write_i         => map_write,
      s_avm_read_i          => map_read,
      s_avm_address_i       => map_address,
      s_avm_writedata_i     => map_writedata,
      s_avm_byteenable_i    => map_byteenable,
      s_avm_burstcount_i    => map_burstcount,
      s_avm_readdata_o      => map_readdata,
      s_avm_readdatavalid_o => map_readdatavalid,
      m_avm_waitrequest_i   => avm_waitrequest_i,
      m_avm_write_o         => avm_write_o,
      m_avm_read_o          => avm_read_o,
      m_avm_address_o       => avm_address_o,
      m_avm_writedata_o     => avm_writedata_o,
      m_avm_byteenable_o    => avm_byteenable_o,
      m_avm_burstcount_o    => avm_burstcount_o,
      m_avm_readdata_i      => avm_readdata_i,
      m_avm_readdatavalid_i => avm_readdatavalid_i
    ); -- avm_cache_inst

  -- Instantiate the PCF8583 RTC I2C emulator
  rtcf83_inst : component rtcf83
    generic map (
      CLOCK_RATE => CORE_CLK_SPEED,
      HAS_RAM    => 0
    )
    port map (
      clk   => clk_main_i,
      ce    => '1',
      reset => reset_hard_i,
      rtc   => rtc_i,
      scl_i => cass_write,
      sda_i => cass_motor,
      sda_o => rtcf83_sda
    ); -- rtcF83_inst

  cass_rtc <= not (rtcf83_sda and cass_motor);

end architecture synthesis;

