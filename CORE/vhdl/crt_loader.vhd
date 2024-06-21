----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This module reads and parses the CRT file that is loaded into the external memory.
-- It stores decoded header information in various tables.
-- Furthermore, it loads and caches the active banks into BRAM.
--
-- This module runs entirely in the external memory clock domain, and therefore the BRAM
-- is placed outside this module.
--
-- It acts as a master towards both the external memory and the BRAM.
-- The maximum amount of addressable external memory is 22 address bits @ 16 data bits, i.e. 8 MB of memory.
-- Not all this memory will be available to the CRT file, though.
-- The CRT file is stored in little-endian format, i.e. even address bytes are in bits 7-0 and
-- odd address bytes are in bits 15-8.
--
-- req_start_i   : Asserted when the entire CRT file has been loaded verbatim into external memory.
-- req_address_i : The start address in external memory (in units of 16-bit words).
-- req_length_i  : The length of the CRT file (in units of bytes).
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

entity crt_loader is
   generic (
      G_CACHE_SIZE : natural
   );
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;

      -- Control interface (QNICE)
      req_start_i         : in  std_logic;
      req_address_i       : in  std_logic_vector(21 downto 0);     -- Address in external memory of start of CRT file
      req_length_i        : in  std_logic_vector(22 downto 0);     -- Length of CRT file in external memory
      resp_status_o       : out std_logic_vector( 3 downto 0);
      resp_error_o        : out std_logic_vector( 3 downto 0);
      resp_address_o      : out std_logic_vector(22 downto 0) := (others => '0');

      -- Control interface (CORE)
      bank_lo_i           : in  std_logic_vector( 6 downto 0);     -- Current bank number of ROM LO
      bank_hi_i           : in  std_logic_vector( 6 downto 0);     -- Current bank number of ROM HI
      bank_wait_o         : out std_logic;                         -- Asserted when cache is being updated
      cache_addr_lo_o     : out std_logic_vector(G_CACHE_SIZE-1 downto 0);
      cache_addr_hi_o     : out std_logic_vector(G_CACHE_SIZE-1 downto 0);

      -- Connect to external memory
      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(21 downto 0);
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic;

      -- Connect to cartridge.v
      cart_bank_laddr_o   : out std_logic_vector(15 downto 0);     -- bank loading address
      cart_bank_size_o    : out std_logic_vector(15 downto 0);     -- length of each bank
      cart_bank_num_o     : out std_logic_vector(15 downto 0);
      cart_bank_raddr_o   : out std_logic_vector(24 downto 0);     -- chip packet address (low 13 bits are ignored)
      cart_bank_wr_o      : out std_logic;
      cart_loading_o      : out std_logic;
      cart_id_o           : out std_logic_vector(15 downto 0);     -- cart ID or cart type
      cart_exrom_o        : out std_logic_vector( 7 downto 0);     -- CRT file EXROM status
      cart_game_o         : out std_logic_vector( 7 downto 0);     -- CRT file GAME status
      cart_size_o         : out std_logic_vector(22 downto 0);     -- CRT file size (in bytes)

      -- Connect to BRAM (2*8kB)
      bram_address_o      : out std_logic_vector(11 downto 0);
      bram_data_o         : out std_logic_vector(15 downto 0);
      bram_lo_wren_o      : out std_logic;
      bram_lo_q_i         : in  std_logic_vector(15 downto 0);
      bram_hi_wren_o      : out std_logic;
      bram_hi_q_i         : in  std_logic_vector(15 downto 0)
   );
end entity crt_loader;

architecture synthesis of crt_loader is

   constant C_STAT_READY           : std_logic_vector(3 downto 0) := "0010"; -- Successfully parsed CRT file
   signal cart_valid               : std_logic;

   signal avm_parser_write         : std_logic;
   signal avm_parser_read          : std_logic;
   signal avm_parser_address       : std_logic_vector(21 downto 0);
   signal avm_parser_writedata     : std_logic_vector(15 downto 0);
   signal avm_parser_byteenable    : std_logic_vector( 1 downto 0);
   signal avm_parser_burstcount    : std_logic_vector( 7 downto 0);
   signal avm_parser_readdata      : std_logic_vector(15 downto 0);
   signal avm_parser_readdatavalid : std_logic;
   signal avm_parser_waitrequest   : std_logic;

   signal avm_cacher_write         : std_logic;
   signal avm_cacher_read          : std_logic;
   signal avm_cacher_address       : std_logic_vector(21 downto 0);
   signal avm_cacher_writedata     : std_logic_vector(15 downto 0);
   signal avm_cacher_byteenable    : std_logic_vector( 1 downto 0);
   signal avm_cacher_burstcount    : std_logic_vector( 7 downto 0);
   signal avm_cacher_readdata      : std_logic_vector(15 downto 0);
   signal avm_cacher_readdatavalid : std_logic;
   signal avm_cacher_waitrequest   : std_logic;

begin

   i_crt_parser : entity work.crt_parser
      port map (
         clk_i               => clk_i,
         rst_i               => rst_i,
         req_start_i         => req_start_i,
         req_address_i       => req_address_i,
         req_length_i        => req_length_i,
         resp_status_o       => resp_status_o,
         resp_error_o        => resp_error_o,
         resp_address_o      => resp_address_o,
         avm_write_o         => avm_parser_write,
         avm_read_o          => avm_parser_read,
         avm_address_o       => avm_parser_address,
         avm_writedata_o     => avm_parser_writedata,
         avm_byteenable_o    => avm_parser_byteenable,
         avm_burstcount_o    => avm_parser_burstcount,
         avm_readdata_i      => avm_parser_readdata,
         avm_readdatavalid_i => avm_parser_readdatavalid,
         avm_waitrequest_i   => avm_parser_waitrequest,
         cart_bank_laddr_o   => cart_bank_laddr_o,
         cart_bank_size_o    => cart_bank_size_o,
         cart_bank_num_o     => cart_bank_num_o,
         cart_bank_raddr_o   => cart_bank_raddr_o,
         cart_bank_wr_o      => cart_bank_wr_o,
         cart_loading_o      => cart_loading_o,
         cart_id_o           => cart_id_o,
         cart_exrom_o        => cart_exrom_o,
         cart_game_o         => cart_game_o,
         cart_size_o         => cart_size_o
      ); -- i_crt_parser

   cart_valid <= '1' when resp_status_o = C_STAT_READY
            else '0';

   i_crt_cacher : entity work.crt_cacher
      generic map (
         G_CACHE_SIZE => G_CACHE_SIZE
      )
      port map (
         clk_i               => clk_i,
         rst_i               => rst_i,
         cart_valid_i        => cart_valid,
         cart_bank_laddr_i   => cart_bank_laddr_o,
         cart_bank_size_i    => cart_bank_size_o,
         cart_bank_num_i     => cart_bank_num_o,
         cart_bank_raddr_i   => cart_bank_raddr_o,
         cart_bank_wr_i      => cart_bank_wr_o,
         bank_lo_i           => bank_lo_i,
         bank_hi_i           => bank_hi_i,
         bank_wait_o         => bank_wait_o,
         cache_addr_lo_o     => cache_addr_lo_o,
         cache_addr_hi_o     => cache_addr_hi_o,
         avm_write_o         => avm_cacher_write,
         avm_read_o          => avm_cacher_read,
         avm_address_o       => avm_cacher_address,
         avm_writedata_o     => avm_cacher_writedata,
         avm_byteenable_o    => avm_cacher_byteenable,
         avm_burstcount_o    => avm_cacher_burstcount,
         avm_readdata_i      => avm_cacher_readdata,
         avm_readdatavalid_i => avm_cacher_readdatavalid,
         avm_waitrequest_i   => avm_cacher_waitrequest,
         bram_address_o      => bram_address_o,
         bram_data_o         => bram_data_o,
         bram_lo_wren_o      => bram_lo_wren_o,
         bram_lo_q_i         => bram_lo_q_i,
         bram_hi_wren_o      => bram_hi_wren_o,
         bram_hi_q_i         => bram_hi_q_i
      ); -- i_crt_cacher

   -- TBD: Could we use a simpler multiplexer, instead of the general-purpose arbiter ?
   i_avm_arbit : entity work.avm_arbit
      generic map (
         G_PREFER_SWAP  => true,
         G_ADDRESS_SIZE => 22,
         G_DATA_SIZE    => 16
      )
      port map (
         clk_i                  => clk_i,
         rst_i                  => rst_i,
         s0_avm_write_i         => avm_parser_write,
         s0_avm_read_i          => avm_parser_read,
         s0_avm_address_i       => avm_parser_address,
         s0_avm_writedata_i     => avm_parser_writedata,
         s0_avm_byteenable_i    => avm_parser_byteenable,
         s0_avm_burstcount_i    => avm_parser_burstcount,
         s0_avm_readdata_o      => avm_parser_readdata,
         s0_avm_readdatavalid_o => avm_parser_readdatavalid,
         s0_avm_waitrequest_o   => avm_parser_waitrequest,
         s1_avm_write_i         => avm_cacher_write,
         s1_avm_read_i          => avm_cacher_read,
         s1_avm_address_i       => avm_cacher_address,
         s1_avm_writedata_i     => avm_cacher_writedata,
         s1_avm_byteenable_i    => avm_cacher_byteenable,
         s1_avm_burstcount_i    => avm_cacher_burstcount,
         s1_avm_readdata_o      => avm_cacher_readdata,
         s1_avm_readdatavalid_o => avm_cacher_readdatavalid,
         s1_avm_waitrequest_o   => avm_cacher_waitrequest,
         m_avm_write_o          => avm_write_o,
         m_avm_read_o           => avm_read_o,
         m_avm_address_o        => avm_address_o,
         m_avm_writedata_o      => avm_writedata_o,
         m_avm_byteenable_o     => avm_byteenable_o,
         m_avm_burstcount_o     => avm_burstcount_o,
         m_avm_readdata_i       => avm_readdata_i,
         m_avm_readdatavalid_i  => avm_readdatavalid_i,
         m_avm_waitrequest_i    => avm_waitrequest_i
      ); -- i_avm_arbit

end architecture synthesis;

