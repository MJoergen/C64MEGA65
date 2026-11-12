----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Elaboration check for sw_cartridge_wrapper.vhd, see README.md. GitHub issue #255.
--
-- Every vector width of the bank cache in sw_cartridge_wrapper.vhd derives from
-- C_CACHE_SIZE: the slot addresses, their clock domain crossing and the address
-- width of the two cache BRAMs. This bench elaborates the real wrapper with the real
-- crt_loader, crt_parser, crt_cacher, sw_cartridge_csr, qnice2hyperram, arbiter,
-- clock domain crossings and tdp_ram, and runs it for a few microseconds with idle
-- inputs: a width that does not fit shows as an elaboration or bound error.
--
-- avm_fifo.vhd needs the Xilinx xpm library; avm_fifo_stand_in.vhd stands in for it.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;

entity tb_wrapper_elab is
end entity tb_wrapper_elab;

architecture simulation of tb_wrapper_elab is

   signal qnice_clk : std_logic := '0';
   signal main_clk  : std_logic := '0';
   signal hr_clk    : std_logic := '0';
   signal rst       : std_logic := '1';
   signal running   : boolean   := true;

begin

   qnice_clk <= not qnice_clk after 10 ns when running else '0';
   main_clk  <= not main_clk after 15.86 ns when running else '0';
   hr_clk    <= not hr_clk after 5 ns when running else '0';
   rst       <= '0' after 200 ns;

   sw_cartridge_wrapper_inst : entity work.sw_cartridge_wrapper
      generic map (
         G_BASE_ADDRESS => "00" & X"00200"
      )
      port map (
         qnice_clk_i            => qnice_clk,
         qnice_rst_i            => rst,
         qnice_addr_i           => (others => '0'),
         qnice_data_i           => (others => '0'),
         qnice_ce_i             => '0',
         qnice_we_i             => '0',
         qnice_data_o           => open,
         qnice_wait_o           => open,
         main_clk_i             => main_clk,
         main_rst_i             => rst,
         main_reset_core_o      => open,
         main_loading_o         => open,
         main_id_o              => open,
         main_exrom_o           => open,
         main_game_o            => open,
         main_size_o            => open,
         main_bank_laddr_o      => open,
         main_bank_size_o       => open,
         main_bank_num_o        => open,
         main_bank_raddr_o      => open,
         main_bank_wr_o         => open,
         main_bank_lo_i         => "0000101",
         main_bank_hi_i         => "0000101",
         main_bank_wait_o       => open,
         main_ram_addr_i        => X"8123",
         main_ram_data_i        => X"00",
         main_ioe_we_i          => '0',
         main_iof_we_i          => '0',
         main_lo_ram_data_o     => open,
         main_hi_ram_data_o     => open,
         main_ioe_ram_data_o    => open,
         main_iof_ram_data_o    => open,
         main_crt_we_i          => '0',
         main_crt_ram_data_o    => open,
         main_cart_soft_reset_i => '0',
         hr_clk_i               => hr_clk,
         hr_rst_i               => rst,
         hr_write_o             => open,
         hr_read_o              => open,
         hr_address_o           => open,
         hr_writedata_o         => open,
         hr_byteenable_o        => open,
         hr_burstcount_o        => open,
         hr_readdata_i          => (others => '0'),
         hr_readdatavalid_i     => '0',
         hr_waitrequest_i       => '0'
      ); -- sw_cartridge_wrapper_inst

   test_proc : process
   begin
      wait for 5 us;
      report "RESULT wrapper elaborated and ran ERRORS=0";
      running <= false;
      wait;
   end process test_proc;

end architecture simulation;
