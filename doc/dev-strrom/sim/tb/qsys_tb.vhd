----------------------------------------------------------------------------------
-- Full-system testbench for the QNICE subsystem of the C64MEGA65 core
--
-- Device under test: the unmodified M2M/vhdl/qnice_wrapper.vhd (QNICE SoC with the
-- real CPU, the firmware ROM, config.vhd, the string ROM, qnice2hyperram and
-- mouse_input). The firmware ROM and the string ROM are read from the files that
-- QNICE_FIRMWARE (globals.vhd) and C_STRROM_FILE (qnice_wrapper.vhd) name, relative
-- to the working directory of the simulation run.
--
-- The testbench provides what framework.vhd and mega65.vhd provide on the board:
--
-- * 50 MHz clock and reset
-- * the on-screen-menu video RAM: the same dualport_2clk_ram_byteenable instance and
--   the same wiring as i_osm_vram_vga in av_pipeline.vhd / framework.vhd
-- * the keyboard word of m2m_keyb (low active)
-- * constant video measurement values, PPS, idle I2C and RTC
-- * a HyperRAM model behind the Avalon master of qnice2hyperram
-- * the cartridge device (C_DEV_C64_CRT) as in sw_cartridge_wrapper.vhd, without
--   its clock domain crossings: the unmodified sw_cartridge_csr.vhd (with
--   qnice_csr.vhd and a second qnice2hyperram) and the unmodified crt_parser.vhd,
--   both connected to the HyperRAM model
-- * a model of the other core devices (device IDs >= 0x0100): a page store that
--   returns what was written and zero otherwise, with the constants of vdrives.vhd
-- * a UART receiver for uart_txd_o and a UART transmitter for uart_rxd_i
--
-- The run is controlled by the script "stim.txt" in the working directory. One
-- command per line; empty lines and lines that start with '#' are ignored:
--
--    set <name> <decimal>          hdmax vdmax h_pixels v_pixels h_pulse h_bp h_fp
--                                  v_pulse v_bp v_fp h_freq sd_int sd_ext
--    wait_ms <n>                   wait n milliseconds
--    wait_us <n>                   wait n microseconds
--    wait_quiet <us> <timeout ms>  wait until neither the UART nor the video RAM
--                                  nor the SD card was active for <us> microseconds
--    wait_osm <0|1> <timeout ms>   wait until the OSM enable bit has this value
--    wait_uart <timeout ms> <text> wait until <text> was received via UART
--                                  (searched in what arrives after the command)
--    keys <hex>                    keys that are held down (M2M$KEY_* bit mask)
--    press <hex> <ms>              hold the keys for <ms> milliseconds, then release
--    press_until <hex> <timeout>   hold the keys until the firmware reacts (video RAM
--                                  write, UART output or change of the OSM enable
--                                  bit), then release
--    send <text>                   send <text> to the UART; \r \n \\ and \xHH
--    dump <tag>                    write the video RAM to vram_<tag>.txt
--    mark <text>                   write a line into events.log
--    reset                         pulse the reset of the QNICE subsystem
--    end                           end of the simulation
--
-- Output files in the working directory:
--
--    uart.log     one line per byte received from uart_txd_o: <time> <hex>
--                 (all time stamps are in microseconds)
--    vram_*.txt   video RAM dumps (header with the OSM registers and the selected
--                 device and window, then one line of hexadecimal words per row:
--                 attribute in the high byte, character in the low byte)
--    win.log      accesses of the 4k MMIO window: W <dev> <addr> <data> for each
--                 write and R <dev> <addr> for each read
--    regs.log     changes of the registers that are visible at the ports
--    events.log   what the script did, and timeouts
--    sd.log       commands of the SD card model (sdcard_model_arch.vhd)
--    spy.log      only with G_SPY: at each dump the stack pointer and the register
--                 bank of the CPU: lowest and highest value since the dump before
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;
use std.env.all;

library work;
use work.globals.all;

entity qsys_tb is
generic (
   G_BOARD     : string  := "MEGA65_R6";
   G_LOG_READS : boolean := true;           -- log the read accesses of the 4k MMIO window
   G_SPY       : boolean := false;          -- log the stack pointer and the register bank of the CPU
   G_WATCH1    : natural := 65535;          -- with G_SPY: count how often the program counter reaches..
   G_WATCH2    : natural := 65535           -- ..these two addresses (65535: no address)
                                            -- (VHDL-2008 external names: not with GHDL 5.1.1)
);
end entity qsys_tb;

architecture sim of qsys_tb is

   constant C_CLK_PERIOD   : time    := 20 ns;                  -- 50 MHz
   constant C_BIT_TIME     : time    := 432 * C_CLK_PERIOD;     -- 16 x UART_DIVISOR (27) clock cycles
   constant C_VRAM_WORDS   : natural := 2 ** VRAM_ADDR_WIDTH;

   signal clk              : std_logic := '0';
   signal rst              : std_logic := '1';
   signal running          : boolean   := true;

   signal uart_rxd         : std_logic := '1';
   signal uart_txd         : std_logic;

   signal sd_cd_ext_n      : std_logic := '1';                  -- low active: SD card in the back slot
   signal sd_cd_int_n      : std_logic := '1';                  -- low active: SD card in the bottom tray

   signal osm_enable       : std_logic;
   signal osm_xy           : std_logic_vector(15 downto 0);
   signal osm_dxdy         : std_logic_vector(15 downto 0);

   signal hdmax            : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(384, 12));
   signal vdmax            : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(270, 12));
   signal h_pixels         : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(384, 12));
   signal v_pixels         : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(270, 12));
   signal h_pulse          : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(32, 12));
   signal h_bp             : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(40, 12));
   signal h_fp             : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(48, 12));
   signal v_pulse          : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(4, 12));
   signal v_bp             : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(20, 12));
   signal v_fp             : std_logic_vector(11 downto 0) := std_logic_vector(to_unsigned(18, 12));
   signal h_freq           : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(15625, 16));

   signal control_m        : std_logic_vector(255 downto 0);
   signal gp_reg           : std_logic_vector(255 downto 0);
   signal csr_reset        : std_logic;
   signal csr_pause        : std_logic;
   signal csr_keyboard_on  : std_logic;
   signal csr_joy1_on      : std_logic;
   signal csr_joy2_on      : std_logic;
   signal ascal_mode       : std_logic_vector(4 downto 0);
   signal poly_wr          : std_logic;

   signal vram_data        : std_logic_vector(15 downto 0);
   signal vram_we          : std_logic;
   signal vram_attr_we     : std_logic;
   signal vram_wren        : std_logic;
   signal vram_byteenable  : std_logic_vector(1 downto 0);
   signal vram_data_in     : std_logic_vector(15 downto 0);
   signal dump_addr        : std_logic_vector(VRAM_ADDR_WIDTH - 1 downto 0) := (others => '0');
   signal dump_data        : std_logic_vector(15 downto 0);

   signal keys_n           : std_logic_vector(15 downto 0) := (others => '1');

   signal avm_write        : std_logic;
   signal avm_read         : std_logic;
   signal avm_address      : std_logic_vector(31 downto 0);
   signal avm_writedata    : std_logic_vector(15 downto 0);
   signal avm_byteenable   : std_logic_vector(1 downto 0);
   signal avm_burstcount   : std_logic_vector(7 downto 0);
   signal avm_readdata     : std_logic_vector(15 downto 0) := (others => '0');
   signal avm_readdatavalid: std_logic := '0';

   signal pps              : std_logic := '0';

   signal i2c_ce, i2c_we   : std_logic;
   signal rtc_ce, rtc_we   : std_logic;

   signal ramrom_dev       : std_logic_vector(15 downto 0);
   signal ramrom_addr      : std_logic_vector(27 downto 0);
   signal ramrom_data_out  : std_logic_vector(15 downto 0);
   signal ramrom_data_in   : std_logic_vector(15 downto 0);
   signal ramrom_ce        : std_logic;
   signal ramrom_we        : std_logic;
   signal ramrom_wait      : std_logic;
   signal core_dev_data    : std_logic_vector(15 downto 0) := (others => '0');

   -- cartridge device
   constant C_CRT_BASE     : std_logic_vector(21 downto 0) := C_HMAP_CRT(9 downto 0) & X"000";   -- as in mega65.vhd
   signal crt_sel          : std_logic;
   signal crt_ce           : std_logic;
   signal crt_we           : std_logic;
   signal crt_data         : std_logic_vector(15 downto 0);
   signal crt_wait         : std_logic;
   signal crt_req_length   : std_logic_vector(22 downto 0);
   signal crt_req_valid    : std_logic;
   signal crt_resp_status  : std_logic_vector(3 downto 0);
   signal crt_resp_error   : std_logic_vector(3 downto 0);
   signal crt_resp_address : std_logic_vector(22 downto 0);
   signal crt_avm_write    : std_logic;
   signal crt_avm_read     : std_logic;
   signal crt_avm_address  : std_logic_vector(31 downto 0);
   signal crt_avm_writedata: std_logic_vector(15 downto 0);
   signal crt_avm_byteenable : std_logic_vector(1 downto 0);
   signal crt_avm_readdata : std_logic_vector(15 downto 0) := (others => '0');
   signal crt_avm_readdatavalid : std_logic := '0';
   signal prs_avm_read     : std_logic;
   signal prs_avm_address  : std_logic_vector(21 downto 0);
   signal prs_avm_burstcount : std_logic_vector(7 downto 0);
   signal prs_avm_readdata : std_logic_vector(15 downto 0) := (others => '0');
   signal prs_avm_readdatavalid : std_logic := '0';

   -- activity tracking for wait_quiet and wait_uart
   signal uart_count       : natural := 0;                      -- bytes received so far
   signal uart_last        : character := ' ';                  -- the byte received last
   signal last_uart_act    : time := 0 ns;
   signal last_bus_act     : time := 0 ns;

   -- the script interpreter announces each dump to the spy
   signal dump_count       : natural := 0;
   signal dump_tag         : string(1 to 24) := (others => ' ');

   file   events_f         : text;

   function hex(v : std_logic_vector) return string is
   begin
      return to_hstring(to_bitvector(v));
   end function;

   -- time stamp in microseconds with three decimals, independent of the simulator
   impure function ts return string is
      constant t_us : natural := now / 1 us;
      constant t_ns : natural := (now - t_us * 1 us) / 1 ns;
      constant s    : string  := integer'image(1000 + t_ns);
   begin
      return integer'image(t_us) & "." & s(s'right - 2 to s'right);
   end function;

begin

   clk <= not clk after C_CLK_PERIOD / 2 when running else '0';

   pps_gen : process
   begin
      wait for 1 sec - C_CLK_PERIOD + 3 ns;
      loop
         pps <= '1';
         wait for C_CLK_PERIOD;
         pps <= '0';
         wait for 1 sec - C_CLK_PERIOD;
      end loop;
   end process pps_gen;

   ---------------------------------------------------------------------------------------------
   -- Device under test
   ---------------------------------------------------------------------------------------------

   dut : entity work.qnice_wrapper
      generic map (
         G_BOARD                   => G_BOARD
      )
      port map (
         clk_i                     => clk,
         rst_i                     => rst,
         uart_rxd_i                => uart_rxd,
         uart_txd_o                => uart_txd,
         sd_reset_o                => open,
         sd_clk_o                  => open,
         sd_mosi_o                 => open,
         sd_miso_i                 => sd_cd_ext_n,              -- sdcard_model_arch.vhd: '0' = card inserted
         sd_cd_i                   => sd_cd_ext_n,
         sd2_reset_o               => open,
         sd2_clk_o                 => open,
         sd2_mosi_o                => open,
         sd2_miso_i                => sd_cd_int_n,              -- sdcard_model_arch.vhd: '0' = card inserted
         sd2_cd_i                  => sd_cd_int_n,
         paddle_i                  => "0000",
         paddle_drain_o            => open,
         qnice_osm_cfg_enable_o    => osm_enable,
         qnice_osm_cfg_xy_o        => osm_xy,
         qnice_osm_cfg_dxdy_o      => osm_dxdy,
         qnice_hdmax_i             => hdmax,
         qnice_vdmax_i             => vdmax,
         qnice_h_pixels_i          => h_pixels,
         qnice_v_pixels_i          => v_pixels,
         qnice_h_pulse_i           => h_pulse,
         qnice_h_bp_i              => h_bp,
         qnice_h_fp_i              => h_fp,
         qnice_v_pulse_i           => v_pulse,
         qnice_v_bp_i              => v_bp,
         qnice_v_fp_i              => v_fp,
         qnice_h_freq_i            => h_freq,
         qnice_ascal_mode_i        => "00",                     -- mega65.vhd: ASCAL_USAGE is custom
         qnice_ascal_polyphase_i   => '0',
         qnice_ascal_triplebuf_i   => '0',
         qnice_flip_joyports_i     => '0',
         qnice_osm_control_m_o     => control_m,
         qnice_gp_reg_o            => gp_reg,
         qnice_csr_reset_o         => csr_reset,
         qnice_csr_pause_o         => csr_pause,
         qnice_csr_keyboard_on_o   => csr_keyboard_on,
         qnice_csr_joy1_on_o       => csr_joy1_on,
         qnice_csr_joy2_on_o       => csr_joy2_on,
         qnice_ascal_mode_o        => ascal_mode,
         qnice_poly_wr_o           => poly_wr,
         qnice_vram_data_i         => vram_data,
         qnice_vram_we_o           => vram_we,
         qnice_vram_attr_we_o      => vram_attr_we,
         qnice_qnice_keys_n_i      => keys_n,
         qnice_pot1_x_n_o          => open,
         qnice_pot1_y_n_o          => open,
         qnice_pot2_x_n_o          => open,
         qnice_pot2_y_n_o          => open,
         qnice_avm_write_o         => avm_write,
         qnice_avm_read_o          => avm_read,
         qnice_avm_address_o       => avm_address,
         qnice_avm_writedata_o     => avm_writedata,
         qnice_avm_byteenable_o    => avm_byteenable,
         qnice_avm_burstcount_o    => avm_burstcount,
         qnice_avm_readdata_i      => avm_readdata,
         qnice_avm_readdatavalid_i => avm_readdatavalid,
         qnice_avm_waitrequest_i   => '0',
         qnice_pps_i               => pps,
         qnice_hdmi_clk_freq_i     => std_logic_vector(to_unsigned(74_250_000, 28)),
         qnice_hr_count_long_i     => (others => '0'),
         qnice_hr_count_short_i    => (others => '0'),
         qnice_i2c_wait_i          => '0',
         qnice_i2c_ce_o            => i2c_ce,
         qnice_i2c_we_o            => i2c_we,
         qnice_i2c_rd_data_i       => x"0000",
         qnice_rtc_wait_i          => '0',
         qnice_rtc_ce_o            => rtc_ce,
         qnice_rtc_we_o            => rtc_we,
         qnice_rtc_rd_data_i       => x"0000",
         qnice_ramrom_dev_o        => ramrom_dev,
         qnice_ramrom_addr_o       => ramrom_addr,
         qnice_ramrom_data_out_o   => ramrom_data_out,
         qnice_ramrom_data_in_i    => ramrom_data_in,
         qnice_ramrom_ce_o         => ramrom_ce,
         qnice_ramrom_we_o         => ramrom_we,
         qnice_ramrom_wait_i       => ramrom_wait
      ); -- dut

   ---------------------------------------------------------------------------------------------
   -- On-screen-menu video RAM: instance and wiring of i_osm_vram_vga (av_pipeline.vhd) and of
   -- the port map of i_av_pipeline in framework.vhd. Port B is the video side in the design;
   -- here the testbench reads the video RAM through it.
   ---------------------------------------------------------------------------------------------

   vram_data_in    <= ramrom_data_out(7 downto 0) & ramrom_data_out(7 downto 0);   -- 2 copies of the same data
   vram_wren       <= vram_attr_we or vram_we;
   vram_byteenable <= vram_attr_we & vram_we;

   i_osm_vram : entity work.dualport_2clk_ram_byteenable
      generic map (
         G_ADDR_WIDTH   => VRAM_ADDR_WIDTH,
         G_DATA_WIDTH   => 16,
         G_FALLING_A    => true   -- QNICE expects read/write to happen at the falling clock edge
      )
      port map (
         a_clk_i        => clk,
         a_address_i    => ramrom_addr(VRAM_ADDR_WIDTH - 1 downto 0),
         a_data_i       => vram_data_in,
         a_wren_i       => vram_wren,
         a_byteenable_i => vram_byteenable,
         a_q_o          => vram_data,

         b_clk_i        => clk,
         b_address_i    => dump_addr,
         b_q_o          => dump_data
      ); -- i_osm_vram

   ---------------------------------------------------------------------------------------------
   -- HyperRAM model: 8 MB, no wait request. Three masters share it, as they share the HyperRAM
   -- of the board: qnice2hyperram of the wrapper (QNICE device 0x0004), qnice2hyperram of the
   -- cartridge device (the firmware stores the .crt file) and the cartridge parser (burst reads).
   ---------------------------------------------------------------------------------------------

   hyperram_model : process (clk)
      type     mem_t   is array (0 to 2 ** 22 - 1) of integer range 0 to 65535;
      type     mem_ptr is access mem_t;
      variable mem     : mem_ptr;
      variable p_addr  : natural := 0;
      variable p_left  : natural := 0;

      procedure wr(a : in natural; d : in std_logic_vector(15 downto 0); be : in std_logic_vector(1 downto 0)) is
         variable w : std_logic_vector(15 downto 0);
      begin
         w := std_logic_vector(to_unsigned(mem(a), 16));
         if be(0) = '1' then
            w(7 downto 0) := d(7 downto 0);
         end if;
         if be(1) = '1' then
            w(15 downto 8) := d(15 downto 8);
         end if;
         mem(a) := to_integer(unsigned(w));
      end procedure;
   begin
      if rising_edge(clk) then
         if mem = null then
            mem := new mem_t;                         -- all elements are 0
         end if;

         -- QNICE device 0x0004
         avm_readdatavalid <= '0';
         if avm_write = '1' then
            wr(to_integer(unsigned(avm_address(21 downto 0))), avm_writedata, avm_byteenable);
         elsif avm_read = '1' then
            avm_readdata      <= std_logic_vector(to_unsigned(mem(to_integer(unsigned(avm_address(21 downto 0)))), 16));
            avm_readdatavalid <= '1';
         end if;

         -- cartridge device: the .crt file as the firmware stores it
         crt_avm_readdatavalid <= '0';
         if crt_avm_write = '1' then
            wr(to_integer(unsigned(crt_avm_address(21 downto 0))), crt_avm_writedata, crt_avm_byteenable);
         elsif crt_avm_read = '1' then
            crt_avm_readdata      <= std_logic_vector(to_unsigned(mem(to_integer(unsigned(crt_avm_address(21 downto 0)))), 16));
            crt_avm_readdatavalid <= '1';
         end if;

         -- cartridge parser: burst reads
         prs_avm_readdatavalid <= '0';
         if p_left > 0 then
            prs_avm_readdata      <= std_logic_vector(to_unsigned(mem(p_addr mod 2 ** 22), 16));
            prs_avm_readdatavalid <= '1';
            p_addr := p_addr + 1;
            p_left := p_left - 1;
         elsif prs_avm_read = '1' then
            p_addr := to_integer(unsigned(prs_avm_address));
            p_left := to_integer(unsigned(prs_avm_burstcount));
         end if;
      end if;
   end process hyperram_model;

   ---------------------------------------------------------------------------------------------
   -- Cartridge device (C_DEV_C64_CRT): QNICE side and parser of sw_cartridge_wrapper.vhd. On the
   -- board the request and the response cross between the QNICE and the HyperRAM clock domain;
   -- here both modules run on the QNICE clock and are connected directly.
   ---------------------------------------------------------------------------------------------

   crt_sel        <= '1' when ramrom_dev = C_DEV_C64_CRT else '0';
   crt_ce         <= ramrom_ce and crt_sel;
   crt_we         <= ramrom_we and crt_sel;
   ramrom_data_in <= crt_data when crt_sel = '1' else core_dev_data;
   ramrom_wait    <= crt_wait when crt_sel = '1' else '0';

   i_sw_cartridge_csr : entity work.sw_cartridge_csr
      generic map (
         G_BASE_ADDRESS            => C_CRT_BASE
      )
      port map (
         qnice_clk_i               => clk,
         qnice_rst_i               => rst,
         qnice_addr_i              => ramrom_addr,
         qnice_data_i              => ramrom_data_out,
         qnice_ce_i                => crt_ce,
         qnice_we_i                => crt_we,
         qnice_data_o              => crt_data,
         qnice_wait_o              => crt_wait,
         qnice_req_length_o        => crt_req_length,
         qnice_req_valid_o         => crt_req_valid,
         qnice_resp_status_i       => crt_resp_status,
         qnice_resp_error_i        => crt_resp_error,
         qnice_resp_address_i      => crt_resp_address,
         qnice_avm_write_o         => crt_avm_write,
         qnice_avm_read_o          => crt_avm_read,
         qnice_avm_address_o       => crt_avm_address,
         qnice_avm_writedata_o     => crt_avm_writedata,
         qnice_avm_byteenable_o    => crt_avm_byteenable,
         qnice_avm_burstcount_o    => open,
         qnice_avm_readdata_i      => crt_avm_readdata,
         qnice_avm_readdatavalid_i => crt_avm_readdatavalid,
         qnice_avm_waitrequest_i   => '0'
      ); -- i_sw_cartridge_csr

   i_crt_parser : entity work.crt_parser
      port map (
         clk_i               => clk,
         rst_i               => rst,
         req_start_i         => crt_req_valid,
         req_address_i       => C_CRT_BASE,
         req_length_i        => crt_req_length,
         resp_status_o       => crt_resp_status,
         resp_error_o        => crt_resp_error,
         resp_address_o      => crt_resp_address,
         avm_write_o         => open,
         avm_read_o          => prs_avm_read,
         avm_address_o       => prs_avm_address,
         avm_writedata_o     => open,
         avm_byteenable_o    => open,
         avm_burstcount_o    => prs_avm_burstcount,
         avm_readdata_i      => prs_avm_readdata,
         avm_readdatavalid_i => prs_avm_readdatavalid,
         avm_waitrequest_i   => '0',
         cart_bank_laddr_o   => open,
         cart_bank_size_o    => open,
         cart_bank_num_o     => open,
         cart_bank_raddr_o   => open,
         cart_bank_wr_o      => open,
         cart_loading_o      => open,
         cart_id_o           => open,
         cart_exrom_o        => open,
         cart_game_o         => open,
         cart_size_o         => open
      ); -- i_crt_parser

   ---------------------------------------------------------------------------------------------
   -- Model of the other core devices (device IDs >= 0x0100, mega65.vhd on the board): read and write
   -- happen at the falling clock edge like in the block RAMs of the design. A page store keeps
   -- what the firmware writes; everything else reads as zero, except for the two constants of
   -- vdrives.vhd (window 0: 0x0008 = number of drives, 0x0009 = block size) and the latched
   -- drive_mounted bits (0x000A), which follow the writes to img_mounted (0x0000).
   ---------------------------------------------------------------------------------------------

   core_devices : process (clk)
      constant C_MAX_PAGES : natural := 4096;
      type     page_t      is array (0 to 4095) of integer range 0 to 65535;
      type     page_ptr    is access page_t;
      type     key_arr_t   is array (0 to C_MAX_PAGES - 1) of integer;
      type     ptr_arr_t   is array (0 to C_MAX_PAGES - 1) of page_ptr;
      variable keys        : key_arr_t := (others => -1);
      variable ptrs        : ptr_arr_t;
      variable n_pages     : natural := 0;
      variable last        : integer := -1;
      variable key         : integer;
      variable idx         : integer;
      variable offs        : natural;
      variable d           : integer;
      variable mounted     : integer := 0;

      impure function find(k : integer) return integer is
      begin
         if last >= 0 and keys(last) = k then
            return last;
         end if;
         for i in 0 to n_pages - 1 loop
            if keys(i) = k then
               return i;
            end if;
         end loop;
         return -1;
      end function;
   begin
      if falling_edge(clk) then
         if ramrom_ce = '1' and unsigned(ramrom_dev) >= x"0100" and crt_sel = '0' then
            -- key: device (low byte is enough: 0x0100 .. 0x01FF) and 4k window
            key  := to_integer(unsigned(ramrom_dev(7 downto 0))) * 65536 + to_integer(unsigned(ramrom_addr(27 downto 12)));
            offs := to_integer(unsigned(ramrom_addr(11 downto 0)));
            idx  := find(key);
            if ramrom_we = '1' then
               if idx < 0 then
                  assert n_pages < C_MAX_PAGES report "core device model: too many pages" severity failure;
                  idx := n_pages;
                  keys(idx) := key;
                  ptrs(idx) := new page_t;                -- all elements are 0
                  n_pages := n_pages + 1;
               end if;
               ptrs(idx)(offs) := to_integer(unsigned(ramrom_data_out));
               if ramrom_dev = C_VD_DEVICE and unsigned(ramrom_addr) = 0 then
                  mounted := to_integer(unsigned(ramrom_data_out(7 downto 0)) or to_unsigned(mounted, 8));
               end if;
            end if;
            if idx >= 0 then
               last := idx;
               d := ptrs(idx)(offs);
            else
               d := 0;
            end if;
            if ramrom_dev = C_VD_DEVICE and unsigned(ramrom_addr(27 downto 4)) = 0 then
               case ramrom_addr(3 downto 0) is
                  when x"8"   => d := C_VDNUM;
                  when x"9"   => d := 512;
                  when x"A"   => d := mounted;
                  when others => null;
               end case;
            end if;
            core_dev_data <= std_logic_vector(to_unsigned(d, 16));
         end if;
      end if;
   end process core_devices;

   ---------------------------------------------------------------------------------------------
   -- UART receiver: decodes uart_txd_o (115200 baud 8N1 as generated by the QNICE UART)
   ---------------------------------------------------------------------------------------------

   uart_receiver : process
      file     f : text;
      variable l : line;
      variable b : std_logic_vector(7 downto 0);
   begin
      file_open(f, "uart.log", write_mode);
      wait until rst = '0';
      loop
         wait until uart_txd = '0';                             -- start bit
         last_uart_act <= now;
         wait for C_BIT_TIME + C_BIT_TIME / 2;
         for i in 0 to 7 loop
            b(i) := uart_txd;
            wait for C_BIT_TIME;
         end loop;
         write(l, ts & " " & hex(b));
         if uart_txd /= '1' then
            write(l, string'(" FRAMING_ERROR"));
            wait until uart_txd = '1';
         end if;
         writeline(f, l);
         flush(f);
         uart_last     <= character'val(to_integer(unsigned(b)));
         uart_count    <= uart_count + 1;
         last_uart_act <= now;
      end loop;
   end process uart_receiver;

   ---------------------------------------------------------------------------------------------
   -- Monitors
   ---------------------------------------------------------------------------------------------

   -- Accesses of the 4k MMIO window as the devices see them at the falling clock edge. A write
   -- is logged in each cycle with an active write enable. A read is logged when the window is
   -- addressed for reading and the address differs from the one of the cycle before.
   bus_monitor : process (clk)
      file     f         : text;
      variable l         : line;
      variable opened    : boolean := false;
      variable prev_rd   : boolean := false;
      variable prev_addr : std_logic_vector(27 downto 0) := (others => '0');
      variable prev_dev  : std_logic_vector(15 downto 0) := (others => '0');
   begin
      if falling_edge(clk) then
         if not opened then
            opened := true;
            file_open(f, "win.log", write_mode);
         end if;
         if ramrom_ce = '1' then
            if ramrom_we = '1' then
               write(l, "W " & hex(ramrom_dev) & " " & hex(ramrom_addr) & " " & hex(ramrom_data_out));
               writeline(f, l);
               prev_rd := false;
               if vram_we = '1' or vram_attr_we = '1' then
                  last_bus_act <= now;
               end if;
            elsif G_LOG_READS then
               if not prev_rd or prev_addr /= ramrom_addr or prev_dev /= ramrom_dev then
                  write(l, "R " & hex(ramrom_dev) & " " & hex(ramrom_addr));
                  writeline(f, l);
               end if;
               prev_rd   := true;
               prev_addr := ramrom_addr;
               prev_dev  := ramrom_dev;
            end if;
         else
            prev_rd := false;
         end if;
      end if;
   end process bus_monitor;

   -- Registers of QNICE that are visible at the ports of the wrapper
   reg_monitor : process
      file     f : text;
      variable l : line;
   begin
      file_open(f, "regs.log", write_mode);
      wait until rst = '0';
      wait for 1 us;
      loop
         write(l, ts &
                  " csr_reset=" & std_logic'image(csr_reset) & " pause=" & std_logic'image(csr_pause) &
                  " osm=" & std_logic'image(osm_enable) & " kbd=" & std_logic'image(csr_keyboard_on) &
                  " joy1=" & std_logic'image(csr_joy1_on) & " joy2=" & std_logic'image(csr_joy2_on) &
                  " xy=" & hex(osm_xy) & " dxdy=" & hex(osm_dxdy) & " ascal=" & hex("000" & ascal_mode) &
                  " i2c=" & std_logic'image(i2c_ce) & " rtc=" & std_logic'image(rtc_ce));
         writeline(f, l);
         write(l, ts & " control_m=" & hex(control_m));
         writeline(f, l);
         write(l, ts & " control_d=" & hex(gp_reg));
         writeline(f, l);
         flush(f);
         wait on csr_reset, csr_pause, osm_enable, csr_keyboard_on, csr_joy1_on, csr_joy2_on,
                 osm_xy, osm_dxdy, ascal_mode, control_m, gp_reg, i2c_ce, rtc_ce;
         wait for 1 ns;
      end loop;
   end process reg_monitor;

   -- Stack pointer and register bank of the CPU. Both firmwares have to pass the same checkpoint
   -- with the same highest stack pointer and the same lowest register bank, otherwise a routine
   -- leaves something on the stack or does not return its register bank. The lowest stack
   -- pointer shows how much stack the firmware uses.
   gen_spy : if G_SPY generate
      spy : process (clk)
         alias    cpu_sp  is <<signal .qsys_tb.dut.QNICE_SOC.cpu.SP : std_logic_vector(15 downto 0)>>;
         alias    cpu_sr  is <<signal .qsys_tb.dut.QNICE_SOC.cpu.SR : std_logic_vector(15 downto 0)>>;
         alias    cpu_pc  is <<signal .qsys_tb.dut.QNICE_SOC.cpu.PC : std_logic_vector(15 downto 0)>>;
         variable pc_prev : natural := 65535;
         variable w1      : natural := 0;
         variable w2      : natural := 0;
         file     f       : text;
         variable l       : line;
         variable opened  : boolean := false;
         variable sp_min  : natural := 65535;
         variable sp_max  : natural := 0;
         variable rb_min  : natural := 255;
         variable rb_max  : natural := 0;
         variable seen    : natural := 0;
         variable v       : natural;
      begin
         if rising_edge(clk) and rst = '0' then
            if not opened then
               opened := true;
               file_open(f, "spy.log", write_mode);
            end if;
            if dump_count /= seen then
               seen := dump_count;
               write(l, ts & " " & dump_tag & " sp_min=" & to_hstring(to_unsigned(sp_min, 16)) &
                        " sp_max=" & to_hstring(to_unsigned(sp_max, 16)) &
                        " sp_now=" & hex(cpu_sp) &
                        " bank_min=" & to_hstring(to_unsigned(rb_min, 8)) &
                        " bank_max=" & to_hstring(to_unsigned(rb_max, 8)) &
                        " bank_now=" & hex(cpu_sr(15 downto 8)) &
                        " w1=" & integer'image(w1) & " w2=" & integer'image(w2));
               writeline(f, l);
               flush(f);
               sp_min := 65535;
               sp_max := 0;
               rb_min := 255;
               rb_max := 0;
            end if;
            -- program counter watch: number of times the program counter changes to the address
            v := to_integer(unsigned(cpu_pc));
            if v /= pc_prev then
               pc_prev := v;
               if v = G_WATCH1 then
                  w1 := w1 + 1;
               end if;
               if v = G_WATCH2 then
                  w2 := w2 + 1;
               end if;
            end if;
            v := to_integer(unsigned(cpu_sp));
            if v < sp_min then
               sp_min := v;
            end if;
            if v > sp_max then
               sp_max := v;
            end if;
            v := to_integer(unsigned(cpu_sr(15 downto 8)));
            if v < rb_min then
               rb_min := v;
            end if;
            if v > rb_max then
               rb_max := v;
            end if;
         end if;
      end process spy;
   end generate gen_spy;

   ---------------------------------------------------------------------------------------------
   -- Script interpreter
   ---------------------------------------------------------------------------------------------

   stimulus : process
      file     stim_f   : text;
      variable sl       : line;
      variable l        : line;
      variable cmd      : string(1 to 16);
      variable cmd_len  : natural;
      variable arg      : string(1 to 256);
      variable arg_len  : natural;
      variable n1, n2   : integer;
      variable keymask  : std_logic_vector(15 downto 0);
      variable t0       : time;
      variable base     : natural;
      variable matched  : natural;
      variable ok       : boolean;

      procedure log_event(s : string) is
         variable el : line;
      begin
         write(el, ts & " " & s);
         writeline(events_f, el);
         flush(events_f);
      end procedure;

      -- skip blanks, then read characters up to the next blank
      procedure get_word(ln : inout line; w : out string; len : out natural) is
         variable c    : character;
         variable good : boolean;
         variable n    : natural := 0;
      begin
         w := (w'range => ' ');
         loop
            exit when ln = null or ln'length = 0;
            read(ln, c, good);
            exit when not good;
            if c = ' ' or c = HT then
               exit when n > 0;
            else
               n := n + 1;
               w(n) := c;
            end if;
         end loop;
         len := n;
      end procedure;

      -- the rest of the line, with the escapes \r \n \\ and \xHH resolved
      procedure get_text(ln : inout line; w : out string; len : out natural) is
         variable c    : character;
         variable h    : string(1 to 2);
         variable good : boolean;
         variable n    : natural := 0;

         function hexval(ch : character) return natural is
         begin
            case ch is
               when '0' to '9' => return character'pos(ch) - character'pos('0');
               when 'a' to 'f' => return character'pos(ch) - character'pos('a') + 10;
               when 'A' to 'F' => return character'pos(ch) - character'pos('A') + 10;
               when others     => return 0;
            end case;
         end function;
      begin
         w := (w'range => ' ');
         loop
            exit when ln = null or ln'length = 0;
            read(ln, c, good);
            exit when not good;
            if c = '\' and ln'length > 0 then
               read(ln, c, good);
               case c is
                  when 'r'    => c := CR;
                  when 'n'    => c := LF;
                  when 'x'    =>
                     read(ln, h, good);
                     c := character'val(hexval(h(1)) * 16 + hexval(h(2)));
                  when others => null;
               end case;
            end if;
            n := n + 1;
            w(n) := c;
         end loop;
         len := n;
      end procedure;

      function to_int(s : string; len : natural) return integer is
         variable v : integer := 0;
      begin
         for i in 1 to len loop
            v := v * 10 + character'pos(s(i)) - character'pos('0');
         end loop;
         return v;
      end function;

      function to_slv16(s : string; len : natural) return std_logic_vector is
         variable v : unsigned(15 downto 0) := (others => '0');
         variable d : natural;
      begin
         for i in 1 to len loop
            case s(i) is
               when '0' to '9' => d := character'pos(s(i)) - character'pos('0');
               when 'a' to 'f' => d := character'pos(s(i)) - character'pos('a') + 10;
               when 'A' to 'F' => d := character'pos(s(i)) - character'pos('A') + 10;
               when others     => d := 0;
            end case;
            v := v(11 downto 0) & to_unsigned(d, 4);
         end loop;
         return std_logic_vector(v);
      end function;

      procedure send_byte(b : std_logic_vector(7 downto 0)) is
      begin
         uart_rxd <= '0';
         wait for C_BIT_TIME;
         for i in 0 to 7 loop
            uart_rxd <= b(i);
            wait for C_BIT_TIME;
         end loop;
         uart_rxd <= '1';
         wait for 2 * C_BIT_TIME;
      end procedure;

      procedure dump_vram(tag : string) is
         file     f  : text;
         variable dl : line;
         variable n  : natural := 0;
      begin
         file_open(f, "vram_" & tag & ".txt", write_mode);
         write(dl, "time=" & ts & " osm=" & std_logic'image(osm_enable) &
                   " xy=" & hex(osm_xy) & " dxdy=" & hex(osm_dxdy) &
                   " dev=" & hex(ramrom_dev) & " win=" & hex(ramrom_addr(27 downto 12)));
         writeline(f, dl);
         for a in 0 to C_VRAM_WORDS - 1 loop
            dump_addr <= std_logic_vector(to_unsigned(a, VRAM_ADDR_WIDTH));
            wait for C_CLK_PERIOD;
            write(dl, hex(dump_data));
            n := n + 1;
            if n = CHARS_DX or a = C_VRAM_WORDS - 1 then
               writeline(f, dl);
               n := 0;
            else
               write(dl, ' ');
            end if;
         end loop;
         file_close(f);
      end procedure;
   begin
      file_open(events_f, "events.log", write_mode);
      file_open(stim_f, "stim.txt", read_mode);

      -- all stimuli change 3 ns after a falling clock edge
      rst <= '1';
      wait for 3 ns;

      while not endfile(stim_f) loop
         readline(stim_f, sl);
         next when sl'length = 0;
         next when sl(sl'left) = '#';
         get_word(sl, cmd, cmd_len);
         next when cmd_len = 0;

         if cmd(1 to cmd_len) = "set" then
            get_word(sl, cmd, cmd_len);
            get_word(sl, arg, arg_len);
            n1 := to_int(arg, arg_len);
            if    cmd(1 to cmd_len) = "hdmax"    then hdmax    <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "vdmax"    then vdmax    <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "h_pixels" then h_pixels <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "v_pixels" then v_pixels <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "h_pulse"  then h_pulse  <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "h_bp"     then h_bp     <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "h_fp"     then h_fp     <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "v_pulse"  then v_pulse  <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "v_bp"     then v_bp     <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "v_fp"     then v_fp     <= std_logic_vector(to_unsigned(n1, 12));
            elsif cmd(1 to cmd_len) = "h_freq"   then h_freq   <= std_logic_vector(to_unsigned(n1, 16));
            elsif cmd(1 to cmd_len) = "sd_int"   then sd_cd_int_n <= '0' when n1 = 1 else '1';
            elsif cmd(1 to cmd_len) = "sd_ext"   then sd_cd_ext_n <= '0' when n1 = 1 else '1';
            else
               log_event("ERROR unknown name in set: " & cmd(1 to cmd_len));
            end if;
            log_event("set " & cmd(1 to cmd_len) & " " & integer'image(n1));

         elsif cmd(1 to cmd_len) = "reset" then
            rst <= '1';
            wait for 10 * C_CLK_PERIOD;
            rst <= '0';
            log_event("reset released");

         elsif cmd(1 to cmd_len) = "wait_ms" then
            get_word(sl, arg, arg_len);
            wait for to_int(arg, arg_len) * 1 ms;

         elsif cmd(1 to cmd_len) = "wait_us" then
            get_word(sl, arg, arg_len);
            wait for to_int(arg, arg_len) * 1 us;

         elsif cmd(1 to cmd_len) = "wait_quiet" then
            get_word(sl, arg, arg_len);
            n1 := to_int(arg, arg_len);
            get_word(sl, arg, arg_len);
            n2 := to_int(arg, arg_len);
            t0 := now;
            ok := false;
            loop
               wait for 20 us;
               if now - last_uart_act >= n1 * 1 us and now - last_bus_act >= n1 * 1 us and uart_txd = '1' then
                  ok := true;
                  exit;
               end if;
               exit when now - t0 >= n2 * 1 ms;
            end loop;
            if ok then
               log_event("quiet after " & integer'image((now - t0) / 1 us) & " us");
            else
               log_event("TIMEOUT wait_quiet after " & integer'image((now - t0) / 1 us) & " us");
            end if;

         elsif cmd(1 to cmd_len) = "wait_osm" then
            get_word(sl, arg, arg_len);
            n1 := to_int(arg, arg_len);
            get_word(sl, arg, arg_len);
            n2 := to_int(arg, arg_len);
            t0 := now;
            if (n1 = 1 and osm_enable /= '1') or (n1 = 0 and osm_enable /= '0') then
               wait on osm_enable for n2 * 1 ms;
            end if;
            if (n1 = 1 and osm_enable = '1') or (n1 = 0 and osm_enable = '0') then
               log_event("osm=" & integer'image(n1) & " after " & integer'image((now - t0) / 1 us) & " us");
            else
               log_event("TIMEOUT wait_osm " & integer'image(n1) & " after " & integer'image((now - t0) / 1 us) & " us");
            end if;
            wait for 3 ns - (now mod C_CLK_PERIOD) + C_CLK_PERIOD;   -- re-align to 3 ns after a falling edge

         elsif cmd(1 to cmd_len) = "wait_uart" then
            get_word(sl, arg, arg_len);
            n2 := to_int(arg, arg_len);
            get_text(sl, arg, arg_len);
            t0 := now;
            matched := 0;
            ok := false;
            while now - t0 < n2 * 1 ms loop
               wait on uart_count for n2 * 1 ms - (now - t0);
               exit when not uart_count'event;
               -- simple matcher: restart at the first character on a mismatch
               if uart_last = arg(matched + 1) then
                  matched := matched + 1;
               elsif uart_last = arg(1) then
                  matched := 1;
               else
                  matched := 0;
               end if;
               if matched = arg_len then
                  ok := true;
                  exit;
               end if;
            end loop;
            if ok then
               log_event("uart text seen after " & integer'image((now - t0) / 1 us) & " us" & ": " & arg(1 to arg_len));
            else
               log_event("TIMEOUT wait_uart after " & integer'image((now - t0) / 1 us) & " us" & ": " & arg(1 to arg_len));
            end if;
            wait for 3 ns - (now mod C_CLK_PERIOD) + C_CLK_PERIOD;   -- re-align to 3 ns after a falling edge

         elsif cmd(1 to cmd_len) = "keys" then
            get_word(sl, arg, arg_len);
            keymask := to_slv16(arg, arg_len);
            keys_n  <= not keymask;
            log_event("keys " & hex(keymask));

         elsif cmd(1 to cmd_len) = "press" then
            get_word(sl, arg, arg_len);
            keymask := to_slv16(arg, arg_len);
            get_word(sl, arg, arg_len);
            n1 := to_int(arg, arg_len);
            keys_n <= not keymask;
            log_event("press " & hex(keymask) & " for " & integer'image(n1) & " ms");
            wait for n1 * 1 ms;
            keys_n <= (others => '1');
            log_event("release");

         elsif cmd(1 to cmd_len) = "press_until" then
            get_word(sl, arg, arg_len);
            keymask := to_slv16(arg, arg_len);
            get_word(sl, arg, arg_len);
            n2 := to_int(arg, arg_len);
            t0 := now;
            keys_n <= not keymask;
            log_event("press " & hex(keymask) & " until the firmware reacts");
            wait on last_bus_act, last_uart_act, osm_enable for n2 * 1 ms;
            if now - t0 >= n2 * 1 ms then
               log_event("TIMEOUT press_until after " & integer'image((now - t0) / 1 us) & " us");
            else
               log_event("reaction after " & integer'image((now - t0) / 1 us) & " us");
            end if;
            wait for 3 ns - (now mod C_CLK_PERIOD) + C_CLK_PERIOD;   -- re-align to 3 ns after a falling edge
            keys_n <= (others => '1');
            log_event("release");

         elsif cmd(1 to cmd_len) = "send" then
            get_text(sl, arg, arg_len);
            log_event("send " & integer'image(arg_len) & " characters");
            -- 2 ms between two characters, and no pause after the last one, so that a wait_uart
            -- that follows sees the complete answer of the firmware
            for i in 1 to arg_len loop
               send_byte(std_logic_vector(to_unsigned(character'pos(arg(i)), 8)));
               if i < arg_len then
                  wait for 2 ms;
               end if;
            end loop;

         elsif cmd(1 to cmd_len) = "dump" then
            get_word(sl, arg, arg_len);
            dump_tag   <= arg(1 to 24);
            dump_count <= dump_count + 1;
            log_event("dump " & arg(1 to arg_len) & " osm=" & std_logic'image(osm_enable) &
                  " xy=" & hex(osm_xy) & " dxdy=" & hex(osm_dxdy) &
                  " dev=" & hex(ramrom_dev) & " win=" & hex(ramrom_addr(27 downto 12)));
            dump_vram(arg(1 to arg_len));

         elsif cmd(1 to cmd_len) = "mark" then
            get_text(sl, arg, arg_len);
            log_event("mark " & arg(1 to arg_len));

         elsif cmd(1 to cmd_len) = "end" then
            exit;

         else
            log_event("ERROR unknown command: " & cmd(1 to cmd_len));
         end if;
      end loop;

      log_event("end of script");
      running <= false;
      wait for 100 ns;
      finish;
   end process stimulus;

end architecture sim;
