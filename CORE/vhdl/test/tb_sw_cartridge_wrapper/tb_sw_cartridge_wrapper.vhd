----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is a testbench for the sw_cartridge_wrapper module.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_sw_cartridge_wrapper is
   generic (
      G_FILE_NAME : string := ""
   );
end entity tb_sw_cartridge_wrapper;

architecture simulation of tb_sw_cartridge_wrapper is

   -- Clock and reset
   signal qnice_clk            : std_logic := '0';
   signal qnice_rst            : std_logic := '1';
   signal qnice_running        : std_logic := '1';
   signal main_clk             : std_logic := '0';
   signal main_rst             : std_logic := '1';
   signal main_running         : std_logic := '1';
   signal hr_clk               : std_logic := '0';
   signal hr_rst               : std_logic := '1';
   signal hr_running           : std_logic := '1';

   signal main_reset_core      : std_logic;
   signal main_loading         : std_logic;
   signal main_id              : std_logic_vector(15 downto 0);
   signal main_exrom           : std_logic_vector( 7 downto 0);
   signal main_game            : std_logic_vector( 7 downto 0);
   signal main_size            : std_logic_vector(22 downto 0);
   signal main_bank_laddr      : std_logic_vector(15 downto 0);
   signal main_bank_size       : std_logic_vector(15 downto 0);
   signal main_bank_num        : std_logic_vector(15 downto 0);
   signal main_bank_raddr      : std_logic_vector(24 downto 0);
   signal main_bank_wr         : std_logic;
   signal main_bank_wait       : std_logic;
   signal main_ram_data        : std_logic_vector( 7 downto 0);
   signal main_ioe_we          : std_logic;
   signal main_iof_we          : std_logic;
   signal main_lo_ram_data     : std_logic_vector(15 downto 0);
   signal main_hi_ram_data     : std_logic_vector(15 downto 0);
   signal main_ioe_ram_data    : std_logic_vector( 7 downto 0);
   signal main_iof_ram_data    : std_logic_vector( 7 downto 0);
   signal main_ram_addr        : std_logic_vector(15 downto 0);
   signal main_bank_lo         : std_logic_vector( 6 downto 0);
   signal main_bank_hi         : std_logic_vector( 6 downto 0);
   signal main_crt_we          : std_logic;
   signal main_crt_ram_data    : std_logic_vector( 7 downto 0);

   signal qnice_addr           : std_logic_vector(27 downto 0);
   signal qnice_writedata      : std_logic_vector(15 downto 0);
   signal qnice_ce             : std_logic;
   signal qnice_we             : std_logic;
   signal qnice_readdata       : std_logic_vector(15 downto 0);
   signal qnice_wait           : std_logic;

   signal hr_write             : std_logic;
   signal hr_read              : std_logic;
   signal hr_address           : std_logic_vector(31 downto 0);
   signal hr_writedata         : std_logic_vector(15 downto 0);
   signal hr_byteenable        : std_logic_vector( 1 downto 0);
   signal hr_burstcount        : std_logic_vector( 7 downto 0);
   signal hr_readdata          : std_logic_vector(15 downto 0);
   signal hr_readdatavalid     : std_logic;
   signal hr_waitrequest       : std_logic;
   signal hr_length            : natural;

begin

   -------------------
   -- Clock and reset
   -------------------

   hr_clk    <= hr_running    and not hr_clk    after  5 ns;
   qnice_clk <= qnice_running and not qnice_clk after 10 ns;
   main_clk  <= main_running  and not main_clk  after 15 ns;

   hr_rst    <= '1', '0' after 100 ns;
   qnice_rst <= '1', '0' after 100 ns;
   main_rst  <= '1', '0' after 100 ns;


   -------------------
   -- Instantiate DUT
   -------------------

   i_sw_cartridge_wrapper : entity work.sw_cartridge_wrapper
      generic map (
         G_BASE_ADDRESS => (others => '0')
      )
      port map (
         qnice_clk_i         => qnice_clk,
         qnice_rst_i         => qnice_rst,
         qnice_addr_i        => qnice_addr,
         qnice_data_i        => qnice_writedata,
         qnice_ce_i          => qnice_ce,
         qnice_we_i          => qnice_we,
         qnice_data_o        => qnice_readdata,
         qnice_wait_o        => qnice_wait,
         main_clk_i          => main_clk,
         main_rst_i          => main_rst,
         main_reset_core_o   => main_reset_core,
         main_loading_o      => main_loading,
         main_id_o           => main_id,
         main_exrom_o        => main_exrom,
         main_game_o         => main_game,
         main_size_o         => main_size,
         main_bank_laddr_o   => main_bank_laddr,
         main_bank_size_o    => main_bank_size,
         main_bank_num_o     => main_bank_num,
         main_bank_raddr_o   => main_bank_raddr,
         main_bank_wr_o      => main_bank_wr,
         main_bank_lo_i      => main_bank_lo,
         main_bank_hi_i      => main_bank_hi,
         main_bank_wait_o    => main_bank_wait,
         main_ram_addr_i     => main_ram_addr,
         main_ram_data_i     => main_ram_data,
         main_ioe_we_i       => main_ioe_we,
         main_iof_we_i       => main_iof_we,
         main_lo_ram_data_o  => main_lo_ram_data,
         main_hi_ram_data_o  => main_hi_ram_data,
         main_ioe_ram_data_o => main_ioe_ram_data,
         main_iof_ram_data_o => main_iof_ram_data,
         main_crt_we_i       => main_crt_we,
         main_crt_ram_data_o => main_crt_ram_data,
         hr_clk_i            => hr_clk,
         hr_rst_i            => hr_rst,
         hr_write_o          => hr_write,
         hr_read_o           => hr_read,
         hr_address_o        => hr_address,
         hr_writedata_o      => hr_writedata,
         hr_byteenable_o     => hr_byteenable,
         hr_burstcount_o     => hr_burstcount,
         hr_readdata_i       => hr_readdata,
         hr_readdatavalid_i  => hr_readdatavalid,
         hr_waitrequest_i    => hr_waitrequest
      ); -- i_sw_cartridge_wrapper

   -----------------------------------
   -- Instantiate simulation models
   -----------------------------------

   i_qnice_sim : entity work.qnice_sim
      port map (
         qnice_clk_i       => qnice_clk,
         qnice_rst_i       => qnice_rst,
         qnice_addr_o      => qnice_addr,
         qnice_writedata_o => qnice_writedata,
         qnice_ce_o        => qnice_ce,
         qnice_we_o        => qnice_we,
         qnice_readdata_i  => qnice_readdata,
         qnice_wait_i      => qnice_wait,
         qnice_length_i    => std_logic_vector(to_unsigned(hr_length*2, 32)),
         qnice_running_o   => qnice_running
      ); -- i_qnice_sim

   i_core_sim : entity work.core_sim
      port map (
         main_clk_i          => main_clk,
         main_rst_i          => main_rst,
         main_reset_core_i   => main_reset_core,
         main_loading_i      => main_loading,
         main_id_i           => main_id,
         main_exrom_i        => main_exrom,
         main_game_i         => main_game,
         main_size_i         => main_size,
         main_bank_laddr_i   => main_bank_laddr,
         main_bank_size_i    => main_bank_size,
         main_bank_num_i     => main_bank_num,
         main_bank_raddr_i   => main_bank_raddr,
         main_bank_wr_i      => main_bank_wr,
         main_bank_lo_o      => main_bank_lo,
         main_bank_hi_o      => main_bank_hi,
         main_bank_wait_i    => main_bank_wait,
         main_ram_addr_o     => main_ram_addr,
         main_ram_data_o     => main_ram_data,
         main_ioe_we_o       => main_ioe_we,
         main_iof_we_o       => main_iof_we,
         main_lo_ram_data_i  => main_lo_ram_data,
         main_hi_ram_data_i  => main_hi_ram_data,
         main_ioe_ram_data_i => main_ioe_ram_data,
         main_iof_ram_data_i => main_iof_ram_data,
         main_crt_we_o       => main_crt_we,
         main_crt_ram_data_i => main_crt_ram_data,
         main_running_o      => main_running
      ); -- i_core_sim

   i_avm_rom : entity work.avm_rom
      generic map (
         G_INIT_FILE    => G_FILE_NAME,
         G_ADDRESS_SIZE => 20,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i               => hr_clk,
         rst_i               => hr_rst,
         avm_write_i         => hr_write,
         avm_read_i          => hr_read,
         avm_address_i       => hr_address(19 downto 0),
         avm_writedata_i     => hr_writedata,
         avm_byteenable_i    => hr_byteenable,
         avm_burstcount_i    => hr_burstcount,
         avm_readdata_o      => hr_readdata,
         avm_readdatavalid_o => hr_readdatavalid,
         avm_waitrequest_o   => hr_waitrequest,
         length_o            => hr_length
      ); -- i_avm_rom

end architecture simulation;

