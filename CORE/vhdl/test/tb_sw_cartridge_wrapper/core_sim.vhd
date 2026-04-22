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
      main_crt_we_o       : out std_logic;
      main_crt_ram_data_i : in  std_logic_vector( 7 downto 0);
      main_running_o      : out std_logic := '1'
   );
end entity core_sim;

architecture simulation of core_sim is

   constant C_ROM_FILE_NAME : string := "../../../CORE/C64_MiSTerMEGA65/rtl/roms/std_C64.mif.bin";

   signal main_ultimax         : std_logic;
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
   signal main_crt_roml_we     : std_logic;
   signal main_ce              : std_logic := '0';
   signal main_irq             : std_logic;

   signal cia1_pra_in  : std_logic_vector(7 downto 0);
   signal cia1_prb_in  : std_logic_vector(7 downto 0);
   signal cia1_pra_out : std_logic_vector(7 downto 0);
   signal cia1_prb_out : std_logic_vector(7 downto 0);
   signal cia1_pra     : std_logic_vector(7 downto 0);
   signal cia1_prb     : std_logic_vector(7 downto 0);
   signal cia1_ddra    : std_logic_vector(7 downto 0);
   signal cia1_ddrb    : std_logic_vector(7 downto 0);

   signal main_cia_data : std_logic_vector(7 downto 0);
   signal main_cia_en   : std_logic;

   type slv8_vector is array (natural range <>) of std_logic_vector(7 downto 0);
   signal keyboard_matrix : slv8_vector(0 to 7) := (others => (others => '1'));

begin

   main_ultimax <= main_exrom and not main_game;

   main_ram_data_to_c64 <= main_cia_data                   when main_cia_en = '1' else
                           main_crt_ram_data_i             when main_roml = '1' and main_crt_roml_we = '1'   else
                           main_lo_ram_data_i(15 downto 8) when main_roml = '1' and main_ram_addr_o(0) = '1' else
                           main_lo_ram_data_i( 7 downto 0) when main_roml = '1' and main_ram_addr_o(0) = '0' else
                           main_hi_ram_data_i(15 downto 8) when main_romh = '1' and main_ram_addr_o(0) = '1' else
                           main_hi_ram_data_i( 7 downto 0) when main_romh = '1' and main_ram_addr_o(0) = '0' else
                           main_lo_ram_data_i(15 downto 8) when main_ioe  = '1' and main_ram_addr_o(0) = '1' and main_ioe_wr_ena = '0' else
                           main_lo_ram_data_i( 7 downto 0) when main_ioe  = '1' and main_ram_addr_o(0) = '0' and main_ioe_wr_ena = '0' else
                           main_lo_ram_data_i(15 downto 8) when main_iof  = '1' and main_ram_addr_o(0) = '1' and main_iof_wr_ena = '0' else
                           main_lo_ram_data_i( 7 downto 0) when main_iof  = '1' and main_ram_addr_o(0) = '0' and main_iof_wr_ena = '0' else
                           main_ioe_ram_data_i             when main_ioe  = '1' and main_ioe_wr_ena = '1'    else
                           main_iof_ram_data_i             when main_iof  = '1' and main_iof_wr_ena = '1'    else
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
   main_crt_we_o   <= main_crt_roml_we and main_wr_en;

   -- Simplified PLA
   main_roml <= '1' when main_ram_addr_o(15 downto 13) = "100"      -- 0x8000 - 0x9FFF
                     and (main_game  = '0' or
                          main_exrom = '0')
           else '0';
   main_romh <= '1' when main_ram_addr_o(15 downto 13) = "101"      -- 0xA000 - 0xBFFF
                     and main_exrom = '0'
                     and main_game = '0'
           else '1' when main_ram_addr_o(15 downto 13) = "111"      -- 0xE000 - 0xFFFF
                     and main_exrom = '1'
                     and main_game = '0'
           else '0';

   main_ce <= not main_ce when rising_edge(main_clk_i);

   irq_proc : process
   begin
     main_irq <= '0';
     wait for 16 ms;
     wait until rising_edge(main_clk_i);
     main_irq <= '1';
     wait for 10 us;
     wait until rising_edge(main_clk_i);
   end process;


   i_cpu_65c02 : entity work.cpu_65c02
      generic map (
         G_ENABLE_IOPORT => true,
         G_LOG_NAME      => "cpu.txt",
         G_SIM           => true,
         G_VERBOSE       => 2,
         G_VARIANT       => "6502"
      )
      port map (
         clk_i        => main_clk_i,
         rst_i        => main_rst_i or main_reset_core_i or main_loading_i,
         ce_i         => main_ce and not main_bank_wait_i,
         nmi_i        => '0',
         irq_i        => main_irq,
         addr_o       => main_ram_addr_o,
         wr_en_o      => main_wr_en,
         wr_data_o    => main_ram_data_o,
         rd_en_o      => open,
         rd_data_i    => main_ram_data_to_c64,
         ioport_in_i  => (others => '1'),
         debug_o      => open
      ); -- i_cpu_65c02


   cia_rd_proc : process (all)
   begin
     main_cia_data <= X"FF";
     main_cia_en   <= '0';
     case main_ram_addr_o is
       when X"DC00" => main_cia_en <= '1'; main_cia_data <= cia1_pra_in;
       when X"DC01" => main_cia_en <= '1'; main_cia_data <= cia1_prb_in;
       when X"DC02" => main_cia_en <= '1'; main_cia_data <= cia1_ddra;
       when X"DC03" => main_cia_en <= '1'; main_cia_data <= cia1_ddrb;
       when others  => null;
     end case;
   end process cia_rd_proc;

   cia_wr_proc : process (main_clk_i)
   begin
     if rising_edge(main_clk_i) then
       if main_wr_en = '1' then
         case main_ram_addr_o is
           when X"DC00" => cia1_pra  <= main_ram_data_o;
           when X"DC01" => cia1_prb  <= main_ram_data_o;
           when X"DC02" => cia1_ddra <= main_ram_data_o;
           when X"DC03" => cia1_ddrb <= main_ram_data_o;
           when others  => null;
         end case;
       end if;

       if main_rst_i = '1' then
         cia1_pra  <= X"00";
         cia1_prb  <= X"00";
         cia1_ddra <= X"00";
         cia1_ddrb <= X"00";
       end if;

       cia1_pra_out <= cia1_pra or not cia1_ddra;
       cia1_prb_out <= cia1_prb or not cia1_ddrb;
     end if;
   end process cia_wr_proc;

   cia1_prb_in <= cia1_prb_out;

   keyboard_proc : process (all)
   begin
     for i in 0 to 7 loop
       cia1_pra_in(i) <= cia1_pra_out(i) and (and(cia1_prb_out or keyboard_matrix(i)));
     end loop;
   end process keyboard_proc;

   keypress : process
   begin
     keyboard_matrix <= (others => X"FF");
     wait for 400 ms;

     report "Press F7";
     keyboard_matrix <= (0 => X"F7", others => X"FF");
     wait for 50 ms;

     report "Release F7";
     keyboard_matrix <= (others => X"FF");
     wait;
   end process keypress;


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
         roml_we_o      => main_crt_roml_we,
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

