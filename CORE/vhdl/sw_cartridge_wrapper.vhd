----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This module acts as a complete wrapper around the SW cartridge emulation.
-- It contains interfaces to the QNICE, to the C64 core, and to the HyperRAM.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity sw_cartridge_wrapper is
   generic (
      G_BASE_ADDRESS : std_logic_vector(21 downto 0)
   );
   port (
      qnice_clk_i         : in    std_logic;
      qnice_rst_i         : in    std_logic;
      qnice_addr_i        : in    std_logic_vector(27 downto 0);
      qnice_data_i        : in    std_logic_vector(15 downto 0);
      qnice_ce_i          : in    std_logic;
      qnice_we_i          : in    std_logic;
      qnice_data_o        : out   std_logic_vector(15 downto 0);
      qnice_wait_o        : out   std_logic;

      main_clk_i          : in    std_logic;
      main_rst_i          : in    std_logic;
      main_reset_core_o   : out   std_logic;
      main_loading_o      : out   std_logic;
      main_id_o           : out   std_logic_vector(15 downto 0);
      main_exrom_o        : out   std_logic_vector( 7 downto 0);
      main_game_o         : out   std_logic_vector( 7 downto 0);
      main_size_o         : out   std_logic_vector(22 downto 0);
      main_bank_laddr_o   : out   std_logic_vector(15 downto 0);
      main_bank_size_o    : out   std_logic_vector(15 downto 0);
      main_bank_num_o     : out   std_logic_vector(15 downto 0);
      main_bank_raddr_o   : out   std_logic_vector(24 downto 0);
      main_bank_wr_o      : out   std_logic;
      main_bank_lo_i      : in    std_logic_vector( 6 downto 0);
      main_bank_hi_i      : in    std_logic_vector( 6 downto 0);
      main_bank_wait_o    : out   std_logic;
      main_ram_addr_i     : in    std_logic_vector(15 downto 0);
      main_ram_data_i     : in    std_logic_vector( 7 downto 0);
      main_ioe_we_i       : in    std_logic;
      main_iof_we_i       : in    std_logic;
      main_lo_ram_data_o  : out   std_logic_vector(15 downto 0);
      main_hi_ram_data_o  : out   std_logic_vector(15 downto 0);
      main_ioe_ram_data_o : out   std_logic_vector( 7 downto 0);
      main_iof_ram_data_o : out   std_logic_vector( 7 downto 0);

      hr_clk_i            : in    std_logic;
      hr_rst_i            : in    std_logic;
      hr_write_o          : out   std_logic;
      hr_read_o           : out   std_logic;
      hr_address_o        : out   std_logic_vector(31 downto 0);
      hr_writedata_o      : out   std_logic_vector(15 downto 0);
      hr_byteenable_o     : out   std_logic_vector( 1 downto 0);
      hr_burstcount_o     : out   std_logic_vector( 7 downto 0);
      hr_readdata_i       : in    std_logic_vector(15 downto 0);
      hr_readdatavalid_i  : in    std_logic;
      hr_waitrequest_i    : in    std_logic
   );
end entity sw_cartridge_wrapper;

architecture synthesis of sw_cartridge_wrapper is

   constant C_CACHE_SIZE : natural                               := 3;

   -- Request and response
   signal   qnice_req_status   : std_logic_vector(15 downto 0);
   signal   qnice_req_length   : std_logic_vector(22 downto 0);
   signal   qnice_req_valid    : std_logic;
   signal   qnice_resp_status  : std_logic_vector( 3 downto 0);
   signal   qnice_resp_error   : std_logic_vector( 3 downto 0);
   signal   qnice_resp_address : std_logic_vector(22 downto 0);

   signal   qnice_avm_write         : std_logic;
   signal   qnice_avm_read          : std_logic;
   signal   qnice_avm_address       : std_logic_vector(31 downto 0);
   signal   qnice_avm_writedata     : std_logic_vector(15 downto 0);
   signal   qnice_avm_byteenable    : std_logic_vector( 1 downto 0);
   signal   qnice_avm_burstcount    : std_logic_vector( 7 downto 0);
   signal   qnice_avm_readdata      : std_logic_vector(15 downto 0);
   signal   qnice_avm_readdatavalid : std_logic;
   signal   qnice_avm_waitrequest   : std_logic;

   -- Request and response
   signal   hr_req_length   : std_logic_vector(22 downto 0);
   signal   hr_req_valid    : std_logic;
   signal   hr_resp_status  : std_logic_vector( 3 downto 0);
   signal   hr_resp_error   : std_logic_vector( 3 downto 0);
   signal   hr_resp_address : std_logic_vector(22 downto 0);

   signal   hr_qnice_write         : std_logic;
   signal   hr_qnice_read          : std_logic;
   signal   hr_qnice_address       : std_logic_vector(31 downto 0);
   signal   hr_qnice_writedata     : std_logic_vector(15 downto 0);
   signal   hr_qnice_byteenable    : std_logic_vector(1 downto 0);
   signal   hr_qnice_burstcount    : std_logic_vector(7 downto 0);
   signal   hr_qnice_readdata      : std_logic_vector(15 downto 0);
   signal   hr_qnice_readdatavalid : std_logic;
   signal   hr_qnice_waitrequest   : std_logic;

   signal   hr_crt_write         : std_logic;
   signal   hr_crt_read          : std_logic;
   signal   hr_crt_address       : std_logic_vector(31 downto 0) := (others => '0');
   signal   hr_crt_writedata     : std_logic_vector(15 downto 0);
   signal   hr_crt_byteenable    : std_logic_vector(1 downto 0);
   signal   hr_crt_burstcount    : std_logic_vector(7 downto 0);
   signal   hr_crt_readdata      : std_logic_vector(15 downto 0);
   signal   hr_crt_readdatavalid : std_logic;
   signal   hr_crt_waitrequest   : std_logic;

   -- Writing to BRAM
   signal   hr_bram_address : std_logic_vector(11 downto 0);
   signal   hr_bram_data    : std_logic_vector(15 downto 0);
   signal   hr_bram_lo_wren : std_logic;
   signal   hr_bram_hi_wren : std_logic;

   -- Connect to CORE
   signal   hr_bank_lo       : std_logic_vector( 6 downto 0);
   signal   hr_bank_hi       : std_logic_vector( 6 downto 0);
   signal   hr_bank_wait     : std_logic;
   signal   hr_cache_addr_lo : std_logic_vector(C_CACHE_SIZE - 1 downto 0);
   signal   hr_cache_addr_hi : std_logic_vector(C_CACHE_SIZE - 1 downto 0);
   signal   hr_loading       : std_logic;
   signal   hr_id            : std_logic_vector(15 downto 0);
   signal   hr_exrom         : std_logic_vector( 7 downto 0);
   signal   hr_game          : std_logic_vector( 7 downto 0);
   signal   hr_size          : std_logic_vector(22 downto 0);
   signal   hr_bank_laddr    : std_logic_vector(15 downto 0);
   signal   hr_bank_size     : std_logic_vector(15 downto 0);
   signal   hr_bank_num      : std_logic_vector(15 downto 0);
   signal   hr_bank_raddr    : std_logic_vector(24 downto 0);
   signal   hr_bank_wr       : std_logic;

   signal   main_resp_status   : std_logic_vector( 3 downto 0);
   signal   main_resp_status_d : std_logic_vector( 3 downto 0);
   signal   main_reset_core    : std_logic_vector(65 downto 0);
   signal   main_cache_addr_lo : std_logic_vector(C_CACHE_SIZE - 1 downto 0);
   signal   main_cache_addr_hi : std_logic_vector(C_CACHE_SIZE - 1 downto 0);

begin

   ---------------------------------------------------
   -- Handle QNICE interface (control and status)
   ---------------------------------------------------

   sw_cartridge_csr_inst : entity work.sw_cartridge_csr
      generic map (
         G_BASE_ADDRESS => G_BASE_ADDRESS
      )
      port map (
         qnice_clk_i               => qnice_clk_i,
         qnice_rst_i               => qnice_rst_i,
         qnice_addr_i              => qnice_addr_i,
         qnice_data_i              => qnice_data_i,
         qnice_ce_i                => qnice_ce_i,
         qnice_we_i                => qnice_we_i,
         qnice_data_o              => qnice_data_o,
         qnice_wait_o              => qnice_wait_o,
         qnice_req_length_o        => qnice_req_length,
         qnice_req_valid_o         => qnice_req_valid,
         qnice_resp_status_i       => qnice_resp_status,
         qnice_resp_error_i        => qnice_resp_error,
         qnice_resp_address_i      => qnice_resp_address,
         qnice_avm_write_o         => qnice_avm_write,
         qnice_avm_read_o          => qnice_avm_read,
         qnice_avm_address_o       => qnice_avm_address,
         qnice_avm_writedata_o     => qnice_avm_writedata,
         qnice_avm_byteenable_o    => qnice_avm_byteenable,
         qnice_avm_burstcount_o    => qnice_avm_burstcount,
         qnice_avm_readdata_i      => qnice_avm_readdata,
         qnice_avm_readdatavalid_i => qnice_avm_readdatavalid,
         qnice_avm_waitrequest_i   => qnice_avm_waitrequest
      ); -- sw_cartridge_csr_inst


   --------------------------------------------
   -- Clock Domain Crossing: QNICE -> HyperRAM
   --------------------------------------------

   cdc_qnice2hr_inst : entity work.cdc_stable
      generic map (
         G_REGISTER_SRC => true,
         G_DATA_SIZE    => 24
      )
      port map (
         src_clk_i                => qnice_clk_i,
         src_data_i(22 downto  0) => qnice_req_length,
         src_data_i(23)           => qnice_req_valid,
         dst_clk_i                => hr_clk_i,
         dst_data_o(22 downto  0) => hr_req_length,
         dst_data_o(23)           => hr_req_valid
      ); -- cdc_qnice2hr_inst

   avm_fifo_qnice_inst : entity work.avm_fifo
      generic map (
         G_WR_DEPTH     => 16,
         G_RD_DEPTH     => 16,
         G_FILL_SIZE    => 1,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         s_clk_i               => qnice_clk_i,
         s_rst_i               => qnice_rst_i,
         s_avm_waitrequest_o   => qnice_avm_waitrequest,
         s_avm_write_i         => qnice_avm_write,
         s_avm_read_i          => qnice_avm_read,
         s_avm_address_i       => qnice_avm_address,
         s_avm_writedata_i     => qnice_avm_writedata,
         s_avm_byteenable_i    => qnice_avm_byteenable,
         s_avm_burstcount_i    => qnice_avm_burstcount,
         s_avm_readdata_o      => qnice_avm_readdata,
         s_avm_readdatavalid_o => qnice_avm_readdatavalid,
         m_clk_i               => hr_clk_i,
         m_rst_i               => hr_rst_i,
         m_avm_waitrequest_i   => hr_qnice_waitrequest,
         m_avm_write_o         => hr_qnice_write,
         m_avm_read_o          => hr_qnice_read,
         m_avm_address_o       => hr_qnice_address,
         m_avm_writedata_o     => hr_qnice_writedata,
         m_avm_byteenable_o    => hr_qnice_byteenable,
         m_avm_burstcount_o    => hr_qnice_burstcount,
         m_avm_readdata_i      => hr_qnice_readdata,
         m_avm_readdatavalid_i => hr_qnice_readdatavalid
      ); -- avm_fifo_qnice_inst


   --------------------------------------------
   -- Clock Domain Crossing: CORE -> HyperRAM
   --------------------------------------------

   cdc_main2hr_inst : entity work.cdc_stable
      generic map (
         G_DATA_SIZE => 14
      )
      port map (
         src_clk_i                => main_clk_i,
         src_data_i( 6 downto  0) => main_bank_lo_i,
         src_data_i(13 downto  7) => main_bank_hi_i,
         dst_clk_i                => hr_clk_i,
         dst_data_o( 6 downto  0) => hr_bank_lo,
         dst_data_o(13 downto  7) => hr_bank_hi
      ); -- idc_main2hr_inst


   -------------------------------------------------------------
   -- Instantiate CRT loader and parser
   -- This module runs entirely within the HyperRAM clock domain.
   -------------------------------------------------------------

   crt_loader_inst : entity work.crt_loader
      generic map (
         G_CACHE_SIZE => C_CACHE_SIZE
      )
      port map (
         clk_i               => hr_clk_i,
         rst_i               => hr_rst_i,
         req_address_i       => G_BASE_ADDRESS,
         req_length_i        => hr_req_length,
         req_start_i         => hr_req_valid,
         resp_status_o       => hr_resp_status,
         resp_error_o        => hr_resp_error,
         resp_address_o      => hr_resp_address,
         bank_lo_i           => hr_bank_lo,
         bank_hi_i           => hr_bank_hi,
         bank_wait_o         => hr_bank_wait,
         cache_addr_lo_o     => hr_cache_addr_lo,
         cache_addr_hi_o     => hr_cache_addr_hi,
         avm_write_o         => hr_crt_write,
         avm_read_o          => hr_crt_read,
         avm_address_o       => hr_crt_address(21 downto 0),
         avm_writedata_o     => hr_crt_writedata,
         avm_byteenable_o    => hr_crt_byteenable,
         avm_burstcount_o    => hr_crt_burstcount,
         avm_readdata_i      => hr_crt_readdata,
         avm_readdatavalid_i => hr_crt_readdatavalid,
         avm_waitrequest_i   => hr_crt_waitrequest,
         cart_bank_laddr_o   => hr_bank_laddr,
         cart_bank_size_o    => hr_bank_size,
         cart_bank_num_o     => hr_bank_num,
         cart_bank_raddr_o   => hr_bank_raddr,
         cart_bank_wr_o      => hr_bank_wr,
         cart_loading_o      => hr_loading,
         cart_id_o           => hr_id,
         cart_exrom_o        => hr_exrom,
         cart_game_o         => hr_game,
         cart_size_o         => hr_size,
         bram_address_o      => hr_bram_address,
         bram_data_o         => hr_bram_data,
         bram_lo_wren_o      => hr_bram_lo_wren,
         bram_lo_q_i         => (others => '0'),
         bram_hi_wren_o      => hr_bram_hi_wren,
         bram_hi_q_i         => (others => '0')
      ); -- crt_loader_inst


   --------------------------------------------
   -- Arbiter for HypeRAM access
   --------------------------------------------

   avm_arbit_inst : entity work.avm_arbit
      generic map (
         G_PREFER_SWAP  => false,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i                  => hr_clk_i,
         rst_i                  => hr_rst_i,
         s0_avm_write_i         => hr_qnice_write,
         s0_avm_read_i          => hr_qnice_read,
         s0_avm_address_i       => hr_qnice_address,
         s0_avm_writedata_i     => hr_qnice_writedata,
         s0_avm_byteenable_i    => hr_qnice_byteenable,
         s0_avm_burstcount_i    => hr_qnice_burstcount,
         s0_avm_readdata_o      => hr_qnice_readdata,
         s0_avm_readdatavalid_o => hr_qnice_readdatavalid,
         s0_avm_waitrequest_o   => hr_qnice_waitrequest,
         s1_avm_write_i         => hr_crt_write,
         s1_avm_read_i          => hr_crt_read,
         s1_avm_address_i       => hr_crt_address,
         s1_avm_writedata_i     => hr_crt_writedata,
         s1_avm_byteenable_i    => hr_crt_byteenable,
         s1_avm_burstcount_i    => hr_crt_burstcount,
         s1_avm_readdata_o      => hr_crt_readdata,
         s1_avm_readdatavalid_o => hr_crt_readdatavalid,
         s1_avm_waitrequest_o   => hr_crt_waitrequest,
         m_avm_write_o          => hr_write_o,
         m_avm_read_o           => hr_read_o,
         m_avm_address_o        => hr_address_o,
         m_avm_writedata_o      => hr_writedata_o,
         m_avm_byteenable_o     => hr_byteenable_o,
         m_avm_burstcount_o     => hr_burstcount_o,
         m_avm_readdata_i       => hr_readdata_i,
         m_avm_readdatavalid_i  => hr_readdatavalid_i,
         m_avm_waitrequest_i    => hr_waitrequest_i
      ); -- avm_arbit_inst


   --------------------------------------------
   -- Clock Domain Crossing: HyperRAM -> QNICE
   --------------------------------------------

   cdc_hr2qnice_inst : entity work.cdc_stable
      generic map (
         G_DATA_SIZE => 31
      )
      port map (
         src_clk_i               => hr_clk_i,
         src_data_i( 3 downto 0) => hr_resp_status,
         src_data_i( 7 downto 4) => hr_resp_error,
         src_data_i(30 downto 8) => hr_resp_address,
         dst_clk_i               => qnice_clk_i,
         dst_data_o( 3 downto 0) => qnice_resp_status,
         dst_data_o( 7 downto 4) => qnice_resp_error,
         dst_data_o(30 downto 8) => qnice_resp_address
      ); -- cdc_hr2qnice_inst


   --------------------------------------------
   -- Clock Domain Crossing: HyperRAM -> CORE
   --------------------------------------------

   cdc_slow_inst : entity work.cdc_slow
      generic map (
         G_DATA_SIZE    => 73,
         G_REGISTER_SRC => false
      )
      port map (
         src_clk_i                => hr_clk_i,
         src_rst_i                => hr_rst_i,
         src_valid_i              => hr_bank_wr,
         src_data_i(15 downto  0) => hr_bank_laddr,
         src_data_i(31 downto 16) => hr_bank_size,
         src_data_i(47 downto 32) => hr_bank_num,
         src_data_i(72 downto 48) => hr_bank_raddr,
         dst_clk_i                => main_clk_i,
         dst_valid_o              => main_bank_wr_o,
         dst_data_o(15 downto  0) => main_bank_laddr_o,
         dst_data_o(31 downto 16) => main_bank_size_o,
         dst_data_o(47 downto 32) => main_bank_num_o,
         dst_data_o(72 downto 48) => main_bank_raddr_o
      ); -- cdc_slow_inst

   cdc_stable_inst : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 57 + 2 * C_CACHE_SIZE,
         G_REGISTER_SRC => false
      )
      port map (
         src_clk_i                                                  => hr_clk_i,
         src_data_i(15 downto  0)                                   => hr_id,
         src_data_i(23 downto 16)                                   => hr_exrom,
         src_data_i(31 downto 24)                                   => hr_game,
         src_data_i(54 downto 32)                                   => hr_size,
         src_data_i(55)                                             => hr_loading,
         src_data_i(56)                                             => hr_bank_wait,
         src_data_i(56 + C_CACHE_SIZE   downto 57)                  => hr_cache_addr_lo,
         src_data_i(56 + 2 * C_CACHE_SIZE downto 57 + C_CACHE_SIZE) => hr_cache_addr_hi,
         dst_clk_i                                                  => main_clk_i,
         dst_data_o(15 downto  0)                                   => main_id_o,
         dst_data_o(23 downto 16)                                   => main_exrom_o,
         dst_data_o(31 downto 24)                                   => main_game_o,
         dst_data_o(54 downto 32)                                   => main_size_o,
         dst_data_o(55)                                             => main_loading_o,
         dst_data_o(56)                                             => main_bank_wait_o,
         dst_data_o(56 + C_CACHE_SIZE   downto 57)                  => main_cache_addr_lo,
         dst_data_o(56 + 2 * C_CACHE_SIZE downto 57 + C_CACHE_SIZE) => main_cache_addr_hi
      ); -- cdc_stable_inst

   cdc_hr2main_inst : entity work.cdc_stable
      generic map (
         G_DATA_SIZE => 4
      )
      port map (
         src_clk_i              => hr_clk_i,
         src_data_i(3 downto 0) => hr_resp_status,
         dst_clk_i              => main_clk_i,
         dst_data_o(3 downto 0) => main_resp_status
      ); -- cdc_hr2main_inst


   ---------------------------------------------------
   -- Reset core when CRT file is successfully parsed
   ---------------------------------------------------

   reset_core_proc : process (main_clk_i)
      constant C_STAT_READY : std_logic_vector(3 downto 0) := "0010"; -- Successfully parsed CRT file
   begin
      if rising_edge(main_clk_i) then
         main_resp_status_d <= main_resp_status;
         main_reset_core    <= main_reset_core(64 downto 0) & '0';
         if main_resp_status = C_STAT_READY and main_resp_status_d /= C_STAT_READY then
            main_reset_core <= (others => '1');
         end if;
         -- Stay in reset until cache is ready
         if main_reset_core(65) = '1' and main_bank_wait_o = '1' then
            main_reset_core <= (others => '1');
         end if;

         -- see comment RESET SEMANTICS in main.vhd: minimum reset pulse length is 32 cycles
         main_reset_core_o <= main_reset_core(65);

         if main_rst_i = '1' then
            main_reset_core <= (others => '1');
         end if;
      end if;
   end process reset_core_proc;


   -------------------------------------------------------------
   -- Instantiate bank cache memory
   -------------------------------------------------------------

   crt_lo_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 12 + C_CACHE_SIZE,         -- 4 kW = 8 kB
         DATA_WIDTH => 16
      )
      port map (
         -- C64 MiSTer core
         clock_a   => main_clk_i,
         address_a => main_cache_addr_lo & main_ram_addr_i(12 downto 1),
         data_a    => (others => '0'),
         wren_a    => '0',
         q_a       => main_lo_ram_data_o,

         clock_b   => hr_clk_i,
         address_b => hr_cache_addr_lo & hr_bram_address,
         data_b    => hr_bram_data,
         wren_b    => hr_bram_lo_wren,
         q_b       => open
      ); -- crt_lo_ram_inst

   crt_hi_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 12 + C_CACHE_SIZE,         -- 4 kW = 8 kB
         DATA_WIDTH => 16
      )
      port map (
         -- C64 MiSTer core
         clock_a   => main_clk_i,
         address_a => main_cache_addr_hi & main_ram_addr_i(12 downto 1),
         data_a    => (others => '0'),
         wren_a    => '0',
         q_a       => main_hi_ram_data_o,

         clock_b   => hr_clk_i,
         address_b => hr_cache_addr_hi & hr_bram_address,
         data_b    => hr_bram_data,
         wren_b    => hr_bram_hi_wren,
         q_b       => open
      ); -- crt_lo_ram_inst


   -------------------------------------------------------------
   -- Instantiate I/O memory
   -------------------------------------------------------------

   ioe_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 8,         -- 256 bytes
         DATA_WIDTH => 8
      )
      port map (
         -- C64 MiSTer core
         clock_a   => main_clk_i,
         address_a => main_ram_addr_i(7 downto 0),
         data_a    => main_ram_data_i,
         wren_a    => main_ioe_we_i,
         q_a       => main_ioe_ram_data_o,

         clock_b   => '0',
         address_b => (others => '0'),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => open
      ); -- ioe_ram_inst

   iof_ram_inst : entity work.tdp_ram
      generic map (
         ADDR_WIDTH => 8,         -- 256 bytes
         DATA_WIDTH => 8
      )
      port map (
         -- C64 MiSTer core
         clock_a   => main_clk_i,
         address_a => main_ram_addr_i(7 downto 0),
         data_a    => main_ram_data_i,
         wren_a    => main_iof_we_i,
         q_a       => main_iof_ram_data_o,

         clock_b   => '0',
         address_b => (others => '0'),
         data_b    => (others => '0'),
         wren_b    => '0',
         q_b       => open
      ); -- iof_ram_inst

end architecture synthesis;

