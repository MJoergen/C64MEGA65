----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Testbench for the 512-bit menu state register of qnice.vhd (M2M$CFM_ADDR /
-- M2M$CFM_DATA): runs the ROM built from cfm_test.asm on the real QNICE CPU
-- inside the real QNICE entity and checks the result word that the testbed
-- writes into control_d_o(15 downto 0) as well as the final control_m_o.
-- Run with: python3 cfm_test.py
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cfm_tb is
generic (
   G_ROM     : string;                             -- cfm_test.rom
   G_TIMEOUT : natural := 50000                    -- in microseconds
);
end entity cfm_tb;

architecture sim of cfm_tb is

   type idx_array is array (natural range <>) of natural;
   constant C_IDX       : idx_array := (0, 15, 16, 255, 256, 300, 511);   -- CT_IDX in cfm_test.asm

   signal clk           : std_logic := '0';
   signal reset_n       : std_logic := '0';
   signal done          : boolean := false;
   signal control_d     : std_logic_vector(255 downto 0);
   signal control_m     : std_logic_vector(511 downto 0);

begin

   clk <= not clk after 10 ns when not done;      -- 50 MHz

   dut : entity work.QNICE
      generic map (
         G_FIRMWARE        => G_ROM,
         G_VGA_DX          => 720,
         G_VGA_DY          => 576,
         G_FONT_DX         => 16,
         G_FONT_DY         => 16
      )
      port map (
         clk50_i           => clk,
         reset_n_i         => reset_n,
         uart_rxd_i        => '1',
         uart_txd_o        => open,
         sd_reset_o        => open,
         sd_clk_o          => open,
         sd_mosi_o         => open,
         sd_miso_i         => '1',
         sd_cd_i           => '1',
         sd2_reset_o       => open,
         sd2_clk_o         => open,
         sd2_mosi_o        => open,
         sd2_miso_i        => '1',
         sd2_cd_i          => '1',
         csr_reset_o       => open,
         csr_pause_o       => open,
         csr_osm_o         => open,
         csr_keyboard_o    => open,
         csr_joy1_o        => open,
         csr_joy2_o        => open,
         osm_xy_o          => open,
         osm_dxdy_o        => open,
         ascal_mode_i      => (others => '0'),
         ascal_mode_o      => open,
         keys_n_i          => (others => '1'),
         control_d_o       => control_d,
         control_m_o       => control_m,
         special_i         => (others => '0'),
         general_i         => (others => '0'),
         ramrom_dev_o      => open,
         ramrom_addr_o     => open,
         ramrom_data_o     => open,
         ramrom_data_i     => (others => '0'),
         ramrom_ce_o       => open,
         ramrom_wait_i     => '0',
         ramrom_we_o       => open
      );

   stim : process
      variable expected : std_logic_vector(511 downto 0);
   begin
      reset_n <= '0';
      wait for 200 ns;
      reset_n <= '1';

      wait until control_d(15 downto 0) /= x"0000" for G_TIMEOUT * 1 us;
      wait for 100 ns;

      expected := (others => '0');
      for i in C_IDX'range loop
         expected(C_IDX(i)) := '1';
      end loop;

      if control_d(15 downto 0) = x"0000" then
         report "CFM_TB FAIL: timeout, the testbed did not finish; control_m_o = 0x" &
                to_hstring(control_m) severity failure;
      elsif control_d(15 downto 0) /= x"600D" then
         report "CFM_TB FAIL: testbed result 0x" & to_hstring(control_d(15 downto 0)) severity failure;
      elsif control_m /= expected then
         report "CFM_TB FAIL: control_m_o = 0x" & to_hstring(control_m) severity failure;
      else
         report "CFM_TB OK: 32 banks, items 0/15/16/255/256/300/511 set via M2M$SET_SETTING" severity note;
      end if;
      done <= true;
      wait;
   end process;

end architecture sim;
