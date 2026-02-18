----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is part of the testbench for the sw_cartridge_wrapper module.
--
-- It provides the stimulus to run the simulation.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity core_sim is
   port (
      main_clk_i          : in  std_logic;
      main_rst_i          : in  std_logic;
      main_reset_core_i   : in  std_logic;
      main_loading_i      : in  std_logic;
      main_id_i           : in  std_logic_vector(15 downto 0);
      main_exrom_i        : in  std_logic_vector( 7 downto 0);
      main_game_i         : in  std_logic_vector( 7 downto 0);
      main_size_i         : in  std_logic_vector(22 downto 0);
      main_bank_laddr_i   : in  std_logic_vector(15 downto 0);
      main_bank_size_i    : in  std_logic_vector(15 downto 0);
      main_bank_num_i     : in  std_logic_vector(15 downto 0);
      main_bank_raddr_i   : in  std_logic_vector(24 downto 0);
      main_bank_wr_i      : in  std_logic;
      main_bank_lo_o      : out std_logic_vector( 6 downto 0);
      main_bank_hi_o      : out std_logic_vector( 6 downto 0);
      main_bank_wait_i    : in  std_logic;
      main_ram_addr_o     : out std_logic_vector(15 downto 0);
      main_ram_data_o     : out std_logic_vector( 7 downto 0);
      main_ioe_we_o       : out std_logic;
      main_iof_we_o       : out std_logic;
      main_lo_ram_data_i  : in  std_logic_vector(15 downto 0);
      main_hi_ram_data_i  : in  std_logic_vector(15 downto 0);
      main_ioe_ram_data_i : in  std_logic_vector( 7 downto 0);
      main_iof_ram_data_i : in  std_logic_vector( 7 downto 0);
      main_running_o      : out std_logic := '1'
   );
end entity core_sim;

architecture simulation of core_sim is

   constant C_ROM_FILE_NAME : string := "../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin";

   signal main_roml            : std_logic;
   signal main_romh            : std_logic;
   signal main_ioe             : std_logic;
   signal main_iof             : std_logic;
   signal main_ioe_wr_ena      : std_logic;
   signal main_iof_wr_ena      : std_logic;
   signal main_ram_data_to_c64 : std_logic_vector(7 downto 0);
   signal main_rom_readdata    : std_logic_vector(7 downto 0);
   signal main_ram_readdata    : std_logic_vector(7 downto 0);
   signal main_io_dxxx         : std_logic_vector(7 downto 0);
   signal main_wr_en           : std_logic;
   signal main_io_rom          : std_logic;
   signal main_exrom           : std_logic;
   signal main_game            : std_logic;
   signal main_ce              : std_logic := '0';

begin

   main_ram_data_to_c64 <= main_lo_ram_data_i(15 downto 8) when main_roml = '1' and main_ram_addr_o(0) = '1' else
                           main_lo_ram_data_i( 7 downto 0) when main_roml = '1' and main_ram_addr_o(0) = '0' else
                           main_hi_ram_data_i(15 downto 8) when main_romh = '1' and main_ram_addr_o(0) = '1' else
                           main_hi_ram_data_i( 7 downto 0) when main_romh = '1' and main_ram_addr_o(0) = '0' else
                           main_lo_ram_data_i(15 downto 8) when main_ioe  = '1' and main_ram_addr_o(0) = '1' and main_ioe_wr_ena = '0' else
                           main_lo_ram_data_i( 7 downto 0) when main_ioe  = '1' and main_ram_addr_o(0) = '0' and main_ioe_wr_ena = '0' else
                           main_lo_ram_data_i(15 downto 8) when main_iof  = '1' and main_ram_addr_o(0) = '1' and main_iof_wr_ena = '0' else
                           main_lo_ram_data_i( 7 downto 0) when main_iof  = '1' and main_ram_addr_o(0) = '0' and main_iof_wr_ena = '0' else
                           main_ioe_ram_data_i             when main_ioe  = '1' and main_ioe_wr_ena = '1'     else
                           main_iof_ram_data_i             when main_iof  = '1' and main_iof_wr_ena = '1'     else
                           main_rom_readdata               when main_ram_addr_o(15 downto 13) = "101"        else
                           main_rom_readdata               when main_ram_addr_o(15 downto 13) = "111"        else
                           main_io_dxxx                    when main_ram_addr_o(15 downto 12) = "1101"       else
                           main_ram_readdata;

   main_io_dxxx <= X"FF" when main_ram_addr_o(11 downto 0) = X"C01" else
                   X"00";

   main_ioe        <= '1' when main_ram_addr_o(15 downto 8) = X"DE" else '0';
   main_iof        <= '1' when main_ram_addr_o(15 downto 8) = X"DF" else '0';
   main_ioe_we_o   <= main_ioe and main_wr_en;
   main_iof_we_o   <= main_iof and main_wr_en;

   -- Simplified PLA
   main_roml <= '1' when main_ram_addr_o(15 downto 13) = "100"      -- 0x8000 - 0x9FFF
                     and main_exrom = '0'
           else '0';
   main_romh <= '1' when main_ram_addr_o(15 downto 13) = "101"      -- 0xA000 - 0xBFFF
                     and main_exrom = '0'
                     and main_game = '0'
           else '1' when main_ram_addr_o(15 downto 13) = "111"      -- 0xE000 - 0xFFFF
                     and main_exrom = '1'
                     and main_game = '0'
           else '0';

   main_ce <= not main_ce when rising_edge(main_clk_i);

   i_cpu_65c02 : entity work.cpu_65c02
      port map (
         clk_i       => main_clk_i,
         rst_i       => main_rst_i or main_reset_core_i or main_loading_i,
         ce_i        => main_ce and not main_bank_wait_i,
         nmi_i       => '0',
         irq_i       => '0',
         addr_o      => main_ram_addr_o,
         wr_en_o     => main_wr_en,
         wr_data_o   => main_ram_data_o,
         rd_en_o     => open,
         rd_data_i   => main_ram_data_to_c64,
         ioport_in_i => (others => '1'),
         debug_o     => open
      ); -- i_cpu_65c02

   i_cartridge : entity work.cartridge
      port map (
         clk_i          => main_clk_i,
         rst_i          => main_rst_i,
         cart_loading_i => main_loading_i,
         cart_id_i      => main_id_i,
         cart_exrom_i   => main_exrom_i,
         cart_game_i    => main_game_i,
         cart_size_i    => main_size_i,
         ioe_i          => main_ioe,
         iof_i          => main_iof,
         ioe_wr_ena_o   => main_ioe_wr_ena,
         iof_wr_ena_o   => main_iof_wr_ena,
         wr_en_i        => main_wr_en,
         wr_data_i      => main_ram_data_o,
         addr_i         => main_ram_addr_o,
         bank_lo_o      => main_bank_lo_o,
         bank_hi_o      => main_bank_hi_o,
         io_rom_o       => main_io_rom,
         exrom_o        => main_exrom,
         game_o         => main_game,
         freeze_key_i   => '0',
         mod_key_i      => '0',
         nmi_ack_i      => '0'
      ); -- i_cartridge

   i_avm_rom : entity work.avm_rom
      generic map (
         G_INIT_FILE    => C_ROM_FILE_NAME,
         G_ADDRESS_SIZE => 14,
         G_DATA_SIZE    => 8
      )
      port map (
         clk_i               => not main_clk_i,
         rst_i               => main_rst_i,
         avm_write_i         => '0',
         avm_read_i          => not main_wr_en,
         avm_address_i       => main_ram_addr_o(14) & main_ram_addr_o(12 downto 0),
         avm_writedata_i     => (others => '0'),
         avm_byteenable_i    => (others => '1'),
         avm_burstcount_i    => X"01",
         avm_readdata_o      => main_rom_readdata,
         avm_readdatavalid_o => open,
         avm_waitrequest_o   => open,
         length_o            => open
      ); -- i_avm_rom

   i_avm_memory : entity work.avm_memory
      generic map (
         G_ADDRESS_SIZE => 16,
         G_DATA_SIZE    => 8
      )
      port map (
         clk_i               => not main_clk_i,
         rst_i               => main_rst_i or main_reset_core_i,
         avm_write_i         => main_wr_en,
         avm_read_i          => not main_wr_en,
         avm_address_i       => main_ram_addr_o,
         avm_writedata_i     => main_ram_data_o,
         avm_byteenable_i    => (others => '1'),
         avm_burstcount_i    => X"01",
         avm_readdata_o      => main_ram_readdata,
         avm_readdatavalid_o => open,
         avm_waitrequest_o   => open
      ); -- i_avm_memory

end architecture simulation;

