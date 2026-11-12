----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Testbench for the string ROM: runs the firmware built from strrom_sim_test.asm
-- on the real QNICE CPU inside the real qnice_wrapper.vhd, i.e. with the real
-- device decoding and the real string ROM instance i_strrom, and writes
-- everything that the firmware does to the standard output. strrom_sim_test.py
-- compares these lines with the values that it expects.
-- Run with: python3 strrom_sim_test.py
--
-- This file contains two design units:
--
-- 1. An additional architecture of the UART of QNICE (entity bus_uart). It
--    wraps the real UART and is the one that is elaborated, because it is the
--    architecture of bus_uart that is analyzed last. It leaves the UART as it
--    is and adds what the firmware needs to report to the testbench:
--
--       write to 0xFF10   bit 0 switches the turbo mode on or off     T <value>
--       write to 0xFF11   log port for data                           L <value>
--       write to 0xFF12   log port for markers                        M <value>
--       write to 0xFF13   the transmit register of the UART           U <value>
--
--    The real UART ignores write accesses to its first three registers. In
--    turbo mode the transmitter is reported as ready at once and the
--    character is only written to the standard output, so that the firmware
--    does not need to wait 4752 clock cycles per character. Without turbo
--    mode the real UART transmits the character and the testbench decodes it
--    from the pin.
--
-- 2. The testbench strrom_sim_tb. Next to qnice_wrapper it contains the video
--    RAM of the on-screen menu, instantiated like i_osm_vram_vga in
--    av_pipeline.vhd and wired like in framework.vhd, and a RAM as an example
--    of a device of the core (device 0x0100, window 0xFFFF). It writes these
--    lines:
--
--       V <address> <value>   write access to the video RAM: characters
--       A <address> <value>   write access to the video RAM: attributes
--       R <address> <value>   word of the video RAM that changed since the
--                             last dump, read via the port of the video side;
--                             the firmware requests a dump by changing the
--                             second word of M2M$CFD_DATA
--       E <amount>            end of a dump: amount of changed words
--       S <value>             character decoded from the pin of the UART
--       X <result> <cycles>   end of the simulation: END, FATAL or TIMEOUT
--
-- The markers and the characters that the real UART transmits are flushed, so
-- that strrom_sim_test.py can follow the simulation and stop it as soon as it
-- goes wrong.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use std.textio.all;

architecture sim of bus_uart is

   signal turbo         : std_logic := '0';
   signal real_en       : std_logic;
   signal real_data_out : std_logic_vector(15 downto 0);

begin

   -- In turbo mode the real UART does not get to see what is sent
   real_en <= '0' when turbo = '1' and uart_we = '1' else uart_en;

   i_real_uart : entity work.bus_uart(beh)
      generic map (
         DIVISOR        => DIVISOR
      )
      port map (
         clk            => clk,
         reset          => reset,
         rx             => rx,
         tx             => tx,
         rts            => rts,
         cts            => cts,
         uart_en        => real_en,
         uart_we        => uart_we,
         uart_reg       => uart_reg,
         uart_cpu_ws    => uart_cpu_ws,
         cpu_data_in    => cpu_data_in,
         cpu_data_out   => real_data_out
      ); -- i_real_uart

   -- Status register in turbo mode: Bit 1 = ready to transmit
   cpu_data_out <= real_data_out or x"0002" when turbo = '1' and uart_en = '1' and uart_we = '0' and uart_reg = "01"
              else real_data_out;

   -- Like the real UART, sample the write accesses of the CPU at the rising clock edge
   p_report : process (clk)
      variable line_v : line;
   begin
      if rising_edge(clk) then
         if reset = '1' then
            turbo <= '0';
         elsif uart_en = '1' and uart_we = '1' then
            case uart_reg is
               when "00"   => write(line_v, string'("T "));
                              turbo <= cpu_data_in(0);
               when "01"   => write(line_v, string'("L "));
               when "10"   => write(line_v, string'("M "));
               when others => write(line_v, string'("U "));
            end case;
            hwrite(line_v, cpu_data_in);
            writeline(output, line_v);
            -- the bulk of the output comes fast enough to pass the buffer of the standard output soon
            if uart_reg = "10" or (uart_reg = "11" and turbo = '0') then
               flush(output);
            end if;
         end if;
      end if;
   end process p_report;

end architecture sim;


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.env1_globals.all;
use work.globals.all;

entity strrom_sim_tb is
generic (
   G_JOB     : natural := 0;                       -- the firmware reads it from M2M$KEYBOARD: part of the test to run
   G_TIMEOUT : natural := 1000                     -- in milliseconds of simulated time
);
end entity strrom_sim_tb;

architecture sim of strrom_sim_tb is

   constant C_CLK_PERIOD   : time := 20 ns;        -- 50 MHz
   constant C_UART_BIT     : time := 16 * UART_DIVISOR * C_CLK_PERIOD;

   -- Device of the core that the testbench provides: a RAM in the last 4k window of the first device id that
   -- is free for the core
   constant C_DEV_CORE     : std_logic_vector(15 downto 0) := x"0100";
   constant C_WIN_CORE     : std_logic_vector(15 downto 0) := x"FFFF";

   signal clk              : std_logic := '0';
   signal rst              : std_logic := '1';
   signal done             : boolean   := false;

   signal uart_txd         : std_logic;
   signal gp_reg           : std_logic_vector(255 downto 0);

   -- QNICE device management
   signal ramrom_dev       : std_logic_vector(15 downto 0);
   signal ramrom_addr      : std_logic_vector(27 downto 0);
   signal ramrom_data_out  : std_logic_vector(15 downto 0);
   signal ramrom_data_in   : std_logic_vector(15 downto 0);
   signal ramrom_we        : std_logic;

   -- Video RAM of the on-screen menu
   signal vram_data        : std_logic_vector(15 downto 0);
   signal vram_we          : std_logic;
   signal vram_attr_we     : std_logic;
   signal video_clk        : std_logic := '0';
   signal video_addr       : std_logic_vector(VRAM_ADDR_WIDTH - 1 downto 0) := (others => '0');
   signal video_data       : std_logic_vector(15 downto 0);

   -- Device of the core
   signal core_sel         : std_logic;
   signal core_we          : std_logic;
   signal core_data        : std_logic_vector(15 downto 0);
   signal core_zero_addr   : std_logic_vector(11 downto 0) := (others => '0');
   signal core_zero_data   : std_logic_vector(15 downto 0) := (others => '0');

begin

   clk <= not clk after C_CLK_PERIOD / 2 when not done;

   dut : entity work.qnice_wrapper
      generic map (
         G_BOARD                   => "strrom_sim_tb"
      )
      port map (
         clk_i                     => clk,
         rst_i                     => rst,
         uart_rxd_i                => '1',
         uart_txd_o                => uart_txd,
         sd_reset_o                => open,
         sd_clk_o                  => open,
         sd_mosi_o                 => open,
         sd_miso_i                 => '1',
         sd_cd_i                   => '1',
         sd2_reset_o               => open,
         sd2_clk_o                 => open,
         sd2_mosi_o                => open,
         sd2_miso_i                => '1',
         sd2_cd_i                  => '1',
         paddle_i                  => "0000",
         paddle_drain_o            => open,
         qnice_osm_cfg_enable_o    => open,
         qnice_osm_cfg_xy_o        => open,
         qnice_osm_cfg_dxdy_o      => open,
         qnice_hdmax_i             => (others => '0'),
         qnice_vdmax_i             => (others => '0'),
         qnice_h_pixels_i          => (others => '0'),
         qnice_v_pixels_i          => (others => '0'),
         qnice_h_pulse_i           => (others => '0'),
         qnice_h_bp_i              => (others => '0'),
         qnice_h_fp_i              => (others => '0'),
         qnice_v_pulse_i           => (others => '0'),
         qnice_v_bp_i              => (others => '0'),
         qnice_v_fp_i              => (others => '0'),
         qnice_h_freq_i            => (others => '0'),
         qnice_ascal_mode_i        => "00",
         qnice_ascal_polyphase_i   => '0',
         qnice_ascal_triplebuf_i   => '0',
         qnice_flip_joyports_i     => '0',
         qnice_osm_control_m_o     => open,
         qnice_gp_reg_o            => gp_reg,
         qnice_csr_reset_o         => open,
         qnice_csr_pause_o         => open,
         qnice_csr_keyboard_on_o   => open,
         qnice_csr_joy1_on_o       => open,
         qnice_csr_joy2_on_o       => open,
         qnice_ascal_mode_o        => open,
         qnice_poly_wr_o           => open,
         qnice_vram_data_i         => vram_data,
         qnice_vram_we_o           => vram_we,
         qnice_vram_attr_we_o      => vram_attr_we,
         qnice_qnice_keys_n_i      => std_logic_vector(to_unsigned(G_JOB, 16)),
         qnice_pot1_x_n_o          => open,
         qnice_pot1_y_n_o          => open,
         qnice_pot2_x_n_o          => open,
         qnice_pot2_y_n_o          => open,
         qnice_avm_write_o         => open,
         qnice_avm_read_o          => open,
         qnice_avm_address_o       => open,
         qnice_avm_writedata_o     => open,
         qnice_avm_byteenable_o    => open,
         qnice_avm_burstcount_o    => open,
         qnice_avm_readdata_i      => (others => '0'),
         qnice_avm_readdatavalid_i => '0',
         qnice_avm_waitrequest_i   => '0',
         qnice_pps_i               => '0',
         qnice_hdmi_clk_freq_i     => (others => '0'),
         qnice_hr_count_long_i     => (others => '0'),
         qnice_hr_count_short_i    => (others => '0'),
         qnice_i2c_wait_i          => '0',
         qnice_i2c_ce_o            => open,
         qnice_i2c_we_o            => open,
         qnice_i2c_rd_data_i       => (others => '0'),
         qnice_rtc_wait_i          => '0',
         qnice_rtc_ce_o            => open,
         qnice_rtc_we_o            => open,
         qnice_rtc_rd_data_i       => (others => '0'),
         qnice_ramrom_dev_o        => ramrom_dev,
         qnice_ramrom_addr_o       => ramrom_addr,
         qnice_ramrom_data_out_o   => ramrom_data_out,
         qnice_ramrom_data_in_i    => ramrom_data_in,
         qnice_ramrom_ce_o         => open,
         qnice_ramrom_we_o         => ramrom_we,
         qnice_ramrom_wait_i       => '0'
      ); -- dut

   ---------------------------------------------------------------------------------------------------------------
   -- Video RAM of the on-screen menu: characters in bits 7 downto 0, attributes in bits 15 downto 8
   -- (see i_osm_vram_vga in av_pipeline.vhd and the port map of i_av_pipeline in framework.vhd)
   ---------------------------------------------------------------------------------------------------------------

   i_osm_vram : entity work.dualport_2clk_ram_byteenable
      generic map (
         G_ADDR_WIDTH      => VRAM_ADDR_WIDTH,
         G_DATA_WIDTH      => 16,
         G_FALLING_A       => true  -- QNICE expects read/write to happen at the falling clock edge
      )
      port map (
         a_clk_i           => clk,
         a_address_i       => ramrom_addr(VRAM_ADDR_WIDTH - 1 downto 0),
         a_data_i          => ramrom_data_out(7 downto 0) & ramrom_data_out(7 downto 0),
         a_wren_i          => vram_attr_we or vram_we,
         a_byteenable_i    => vram_attr_we & vram_we,
         a_q_o             => vram_data,

         b_clk_i           => video_clk,
         b_address_i       => video_addr,
         b_q_o             => video_data
      ); -- i_osm_vram

   p_vram_log : process (clk)
      variable line_v : line;
   begin
      if falling_edge(clk) then
         if vram_we = '1' then
            write(line_v, string'("V "));
            hwrite(line_v, ramrom_addr);
            write(line_v, ' ');
            hwrite(line_v, ramrom_data_out);
            writeline(output, line_v);
         end if;
         if vram_attr_we = '1' then
            write(line_v, string'("A "));
            hwrite(line_v, ramrom_addr);
            write(line_v, ' ');
            hwrite(line_v, ramrom_data_out);
            writeline(output, line_v);
         end if;
      end if;
   end process p_vram_log;

   -- Reads the whole video RAM like the video output does, i.e. via port B, and writes the words that changed
   -- since the last dump. The dump takes less than half a clock cycle of QNICE.
   p_vram_dump : process
      type     vram_t is array (0 to 2 ** VRAM_ADDR_WIDTH - 1) of std_logic_vector(15 downto 0);
      variable shadow_v  : vram_t := (others => (others => '0'));
      variable changed_v : natural;
      variable line_v    : line;
   begin
      wait on gp_reg(31 downto 16);
      if rst = '0' and not is_x(gp_reg(31 downto 16)) and gp_reg(31 downto 16) /= x"0000" then
         changed_v := 0;
         for i in vram_t'range loop
            video_addr <= std_logic_vector(to_unsigned(i, VRAM_ADDR_WIDTH));
            video_clk  <= '0';
            wait for 1 ps;
            video_clk  <= '1';
            wait for 1 ps;
            if video_data /= shadow_v(i) then
               shadow_v(i) := video_data;
               changed_v   := changed_v + 1;
               write(line_v, string'("R "));
               hwrite(line_v, std_logic_vector(to_unsigned(i, 12)));
               write(line_v, ' ');
               hwrite(line_v, video_data);
               writeline(output, line_v);
            end if;
         end loop;
         video_clk <= '0';
         write(line_v, string'("E "));
         write(line_v, changed_v);
         writeline(output, line_v);
      end if;
   end process p_vram_dump;

   ---------------------------------------------------------------------------------------------------------------
   -- Device of the core: a RAM, connected like the RAMs and ROMs of a core are connected to QNICE
   ---------------------------------------------------------------------------------------------------------------

   core_sel       <= '1' when ramrom_dev = C_DEV_CORE and ramrom_addr(27 downto 12) = C_WIN_CORE else '0';
   core_we        <= ramrom_we and core_sel;
   ramrom_data_in <= core_data when core_sel = '1' else x"EEEE";

   i_core_ram : entity work.dualport_2clk_ram
      generic map (
         ADDR_WIDTH        => 12,
         DATA_WIDTH        => 16,
         FALLING_A         => false,
         FALLING_B         => true
      )
      port map (
         -- unused port
         clock_a           => clk,
         address_a         => core_zero_addr,
         data_a            => core_zero_data,
         wren_a            => '0',
         q_a               => open,

         -- QNICE
         clock_b           => clk,
         address_b         => ramrom_addr(11 downto 0),
         data_b            => ramrom_data_out,
         wren_b            => core_we,
         q_b               => core_data
      ); -- i_core_ram

   ---------------------------------------------------------------------------------------------------------------
   -- UART: decode what the real UART transmits (8-N-1)
   ---------------------------------------------------------------------------------------------------------------

   p_serial : process
      variable byte_v : std_logic_vector(7 downto 0);
      variable line_v : line;
   begin
      wait until falling_edge(uart_txd);
      wait for C_UART_BIT / 2;
      if uart_txd = '0' then                       -- start bit
         for i in 0 to 7 loop
            wait for C_UART_BIT;
            byte_v(i) := uart_txd;
         end loop;
         wait for C_UART_BIT;                      -- stop bit
         write(line_v, string'("S "));
         hwrite(line_v, byte_v);
         if uart_txd /= '1' then
            write(line_v, string'(" framing error"));
         end if;
         writeline(output, line_v);
         flush(output);
      end if;
   end process p_serial;

   ---------------------------------------------------------------------------------------------------------------
   -- Reset and end of the simulation: the firmware writes its result to the first word of M2M$CFD_DATA
   ---------------------------------------------------------------------------------------------------------------

   p_control : process
      variable line_v : line;
   begin
      rst <= '1';
      wait for 10 * C_CLK_PERIOD;
      rst <= '0';

      wait until gp_reg(15 downto 0) = x"600D" or gp_reg(15 downto 0) = x"DEAD" for G_TIMEOUT * 1 ms;
      wait for 10 * C_CLK_PERIOD;

      if gp_reg(15 downto 0) = x"600D" then
         write(line_v, string'("X END "));
      elsif gp_reg(15 downto 0) = x"DEAD" then
         write(line_v, string'("X FATAL "));
      else
         write(line_v, string'("X TIMEOUT "));
      end if;
      write(line_v, natural(now / C_CLK_PERIOD));
      writeline(output, line_v);
      flush(output);

      done <= true;
      wait;
   end process p_control;

end architecture sim;
