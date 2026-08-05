-- ---------------------------------------------------------------------------------------
-- Description: Verify axip_sim
--
-- SPDX-License-Identifier: MIT
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_eth_rmii is
  generic (
    G_DEBUG      : boolean;
    G_MIN_LENGTH : natural;
    G_MAX_LENGTH : natural;
    G_CNT_SIZE   : natural
  );
end entity tb_eth_rmii;

architecture tb of tb_eth_rmii is

  signal clk : std_logic := '1';
  signal rst : std_logic := '1';

  signal s_ready : std_logic;
  signal s_valid : std_logic;
  signal s_data  : std_logic_vector(7 downto 0);
  signal s_last  : std_logic;

  signal m_ready : std_logic;
  signal m_valid : std_logic;
  signal m_data  : std_logic_vector(7 downto 0);
  signal m_last  : std_logic;

  signal eth_data  : std_logic_vector(1 downto 0);
  signal eth_valid : std_logic;

begin

  ----------------------------------------------
  -- Clock and Reset
  ----------------------------------------------

  clk <= not clk after 5 ns;
  rst <= '1', '0' after 100 ns;


  ----------------------------------------------
  -- Instantiate DUT
  ----------------------------------------------

  eth_rmii_inst : entity work.eth_rmii
    port map (
      eth_clk_i   => clk,
      eth_rst_i   => rst,
      rx_valid_o  => m_valid,
      rx_data_o   => m_data,
      rx_ok_o     => open,
      rx_last_o   => m_last,
      tx_ready_o  => s_ready,
      tx_valid_i  => s_valid,
      tx_last_i   => s_last,
      tx_data_i   => s_data,
      eth_rxd_i   => eth_data,
      eth_rxerr_i => '0',
      eth_crsdv_i => eth_valid,
      eth_txd_o   => eth_data,
      eth_txen_o  => eth_valid
    ); -- eth_rmii_inst


  ----------------------------------------------
  -- Generate stimulus
  ----------------------------------------------

  axip_master_sim_inst : entity work.axip_master_sim
    generic map (
      G_DEBUG      => G_DEBUG,
      G_CNT_SIZE   => G_CNT_SIZE,
      G_DATA_BYTES => 1,
      G_MIN_LENGTH => G_MIN_LENGTH,
      G_MAX_LENGTH => G_MAX_LENGTH
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      m_ready_i => s_ready,
      m_valid_o => s_valid,
      m_data_o  => s_data,
      m_last_o  => s_last,
      m_bytes_o => open
    ); -- axip_master_sim_inst


  ----------------------------------------------
  -- Verify response
  ----------------------------------------------

  axip_slave_sim_inst : entity work.axip_slave_sim
    generic map (
      G_DEBUG      => G_DEBUG,
      G_CNT_SIZE   => G_CNT_SIZE,
      G_DATA_BYTES => 1
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      s_ready_o => open,
      s_valid_i => m_valid,
      s_data_i  => m_data,
      s_last_i  => m_last,
      s_bytes_i => 1
    ); -- axip_slave_sim_inst

end architecture tb;

