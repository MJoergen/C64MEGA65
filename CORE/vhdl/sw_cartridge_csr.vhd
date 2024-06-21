----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This module handles the QNICE "Control and Status" interface of the
-- sw_cartridge_wrapper modulde.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.qnice_csr_pkg.all;

entity sw_cartridge_csr is
generic (
   G_BASE_ADDRESS : std_logic_vector(21 downto 0)
);
port (
   qnice_clk_i               : in  std_logic;
   qnice_rst_i               : in  std_logic;
   qnice_addr_i              : in  std_logic_vector(27 downto 0);
   qnice_data_i              : in  std_logic_vector(15 downto 0);
   qnice_ce_i                : in  std_logic;
   qnice_we_i                : in  std_logic;
   qnice_data_o              : out std_logic_vector(15 downto 0);
   qnice_wait_o              : out std_logic;

   qnice_req_length_o        : out std_logic_vector(22 downto 0);
   qnice_req_valid_o         : out std_logic;
   qnice_resp_status_i       : in  std_logic_vector( 3 downto 0);
   qnice_resp_error_i        : in  std_logic_vector( 3 downto 0);
   qnice_resp_address_i      : in  std_logic_vector(22 downto 0);

   qnice_avm_write_o         : out std_logic;
   qnice_avm_read_o          : out std_logic;
   qnice_avm_address_o       : out std_logic_vector(31 downto 0);
   qnice_avm_writedata_o     : out std_logic_vector(15 downto 0);
   qnice_avm_byteenable_o    : out std_logic_vector( 1 downto 0);
   qnice_avm_burstcount_o    : out std_logic_vector( 7 downto 0);
   qnice_avm_readdata_i      : in  std_logic_vector(15 downto 0);
   qnice_avm_readdatavalid_i : in  std_logic;
   qnice_avm_waitrequest_i   : in  std_logic
);
end entity sw_cartridge_csr;

architecture synthesis of sw_cartridge_csr is

   signal qnice_csr               : std_logic;
   signal qnice_csr_wait          : std_logic;
   signal qnice_csr_data          : std_logic_vector(15 downto 0);
   signal qnice_req_status        : std_logic_vector( 3 downto 0);

   signal qnice_mem_ce            : std_logic;
   signal qnice_mem_addr          : std_logic_vector(31 downto 0);
   signal qnice_mem_wait          : std_logic;
   signal qnice_mem_data          : std_logic_vector(15 downto 0);
   signal qnice_mem_byteenable    : std_logic_vector( 1 downto 0);

   constant C_ERROR_STRINGS : string_vector(0 to 15) := (
     "OK                 \n",
     "Missing CRT header \n",
     "Missing CHIP header\n",
     "Wrong CRT header   \n",
     "Wrong CHIP header  \n",
     "Truncated CHIP     \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n",
     "OK                 \n");

begin

   -- Handle the generic framework CSR registers
   i_qnice_csr : entity work.qnice_csr
      generic map (
         G_ERROR_STRINGS => C_ERROR_STRINGS
      )
      port map (
         qnice_clk_i          => qnice_clk_i,
         qnice_rst_i          => qnice_rst_i,
         qnice_addr_i         => qnice_addr_i,
         qnice_data_i         => qnice_data_i,
         qnice_ce_i           => qnice_ce_i,
         qnice_we_i           => qnice_we_i,
         qnice_data_o         => qnice_csr_data,
         qnice_wait_o         => qnice_csr_wait,
         qnice_csr_o          => qnice_csr,
         qnice_req_status_o   => qnice_req_status,
         qnice_req_length_o   => qnice_req_length_o,
         qnice_resp_status_i  => qnice_resp_status_i,
         qnice_resp_error_i   => qnice_resp_error_i,
         qnice_resp_address_i => qnice_resp_address_i
      ); -- i_qnice_csr

   qnice_req_valid_o <= '1' when qnice_req_status = C_CSR_REQ_OK else '0';

   p_read : process (all)
   begin
      qnice_data_o <= x"0000"; -- By default read back zeros.
      qnice_wait_o <= '0';

      if qnice_ce_i = '1' then
         case qnice_csr is
            when '0' =>
               qnice_wait_o <= qnice_mem_wait;
               if qnice_addr_i(0) = '1' then
                  qnice_data_o <= X"00" & qnice_mem_data(15 downto 8);
               else
                  qnice_data_o <= X"00" & qnice_mem_data(7 downto 0);
               end if;

            when '1' =>
               qnice_wait_o <= qnice_csr_wait;
               qnice_data_o <= qnice_csr_data;

            when others =>
               null;
         end case;
      end if;
   end process p_read;

   qnice_mem_ce <= qnice_ce_i and not qnice_csr;
   qnice_mem_addr <= std_logic_vector(("00000" & unsigned(qnice_addr_i(27 downto 1))) +
                                     ("0000000000" & unsigned(G_BASE_ADDRESS)));
   qnice_mem_byteenable <= "10" when qnice_addr_i(0) = '1'
                     else "01";

   i_qnice2avalon : entity work.qnice2avalon
      port map (
         clk_i                 => qnice_clk_i,
         rst_i                 => qnice_rst_i,
         s_qnice_wait_o        => qnice_mem_wait,
         s_qnice_address_i     => qnice_mem_addr,
         s_qnice_cs_i          => qnice_mem_ce,
         s_qnice_write_i       => qnice_we_i,
         s_qnice_writedata_i   => qnice_data_i(7 downto 0) & qnice_data_i(7 downto 0),
         s_qnice_byteenable_i  => qnice_mem_byteenable,
         s_qnice_readdata_o    => qnice_mem_data,
         m_avm_write_o         => qnice_avm_write_o,
         m_avm_read_o          => qnice_avm_read_o,
         m_avm_address_o       => qnice_avm_address_o,
         m_avm_writedata_o     => qnice_avm_writedata_o,
         m_avm_byteenable_o    => qnice_avm_byteenable_o,
         m_avm_burstcount_o    => qnice_avm_burstcount_o,
         m_avm_readdata_i      => qnice_avm_readdata_i,
         m_avm_readdatavalid_i => qnice_avm_readdatavalid_i,
         m_avm_waitrequest_i   => qnice_avm_waitrequest_i
      ); -- i_qnice2avalon

end architecture synthesis;

