----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Stand-in for M2M/vhdl/memory/avm_fifo.vhd in tb_wrapper_elab.vhd, see README.md.
--
-- The real avm_fifo needs the Xilinx xpm library. This entity has the same generics
-- and ports and no function, which is enough to elaborate sw_cartridge_wrapper.vhd.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;

entity avm_fifo is
   generic (
      G_WR_DEPTH     : integer;
      G_RD_DEPTH     : integer;
      G_FILL_SIZE    : natural := 5;
      G_ADDRESS_SIZE : integer;
      G_DATA_SIZE    : integer
   );
   port (
      s_clk_i               : in    std_logic;
      s_rst_i               : in    std_logic;
      s_avm_waitrequest_o   : out   std_logic;
      s_avm_write_i         : in    std_logic;
      s_avm_read_i          : in    std_logic;
      s_avm_address_i       : in    std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
      s_avm_writedata_i     : in    std_logic_vector(G_DATA_SIZE - 1 downto 0);
      s_avm_byteenable_i    : in    std_logic_vector(G_DATA_SIZE / 8 - 1 downto 0);
      s_avm_burstcount_i    : in    std_logic_vector(7 downto 0);
      s_avm_readdata_o      : out   std_logic_vector(G_DATA_SIZE - 1 downto 0);
      s_avm_readdatavalid_o : out   std_logic;
      m_clk_i               : in    std_logic;
      m_rst_i               : in    std_logic;
      m_avm_waitrequest_i   : in    std_logic;
      m_avm_write_o         : out   std_logic;
      m_avm_read_o          : out   std_logic;
      m_avm_address_o       : out   std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
      m_avm_writedata_o     : out   std_logic_vector(G_DATA_SIZE - 1 downto 0);
      m_avm_byteenable_o    : out   std_logic_vector(G_DATA_SIZE / 8 - 1 downto 0);
      m_avm_burstcount_o    : out   std_logic_vector(7 downto 0);
      m_avm_readdata_i      : in    std_logic_vector(G_DATA_SIZE - 1 downto 0);
      m_avm_readdatavalid_i : in    std_logic
   );
end entity avm_fifo;

architecture stand_in of avm_fifo is
begin

   s_avm_waitrequest_o   <= '0';
   s_avm_readdata_o      <= (others => '0');
   s_avm_readdatavalid_o <= '0';
   m_avm_write_o         <= '0';
   m_avm_read_o          <= '0';
   m_avm_address_o       <= (others => '0');
   m_avm_writedata_o     <= (others => '0');
   m_avm_byteenable_o    <= (others => '0');
   m_avm_burstcount_o    <= (others => '0');

end architecture stand_in;
