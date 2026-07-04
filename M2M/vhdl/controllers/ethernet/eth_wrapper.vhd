library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library unisim;
  use unisim.vcomponents.all;

entity eth_wrapper is
  generic (
    G_SIM   : boolean := false
  );
  port (
    -- PHY clock
    eth_clk_i       : in    std_logic;
    eth_rst_i       : in    std_logic;

    -- Connected to the PHY
    eth_clk_o       : out   std_logic;
    eth_rst_n_o     : out   std_logic;
    eth_led2_o      : out   std_logic;
    eth_mdc_o       : out   std_logic;
    eth_mdio_io     : inout std_logic;
    eth_rx_d_i      : in    std_logic_vector(1 downto 0);
    eth_crs_dv_i    : in    std_logic;
    eth_rxer_i      : in    std_logic;
    eth_tx_d_o      : out   std_logic_vector(1 downto 0);
    eth_tx_en_o     : out   std_logic
  );
end entity eth_wrapper;

architecture synthesis of eth_wrapper is

  signal   eth_rx_valid : std_logic;
  signal   eth_rx_last  : std_logic;
  signal   eth_rx_ok    : std_logic;
  signal   eth_rx_data  : std_logic_vector(7 downto 0);

  signal   eth_tx_ready : std_logic;
  signal   eth_tx_valid : std_logic;
  signal   eth_tx_last  : std_logic;
  signal   eth_tx_data  : std_logic_vector(7 downto 0);

  pure function cond_expr (
    c: boolean;
    t,
    f: natural
  ) return natural is
  begin
    if c then
      return t;
    else
      return f;
    end if;
  end function cond_expr;

  constant C_ETH_RESET_US  : natural := cond_expr(G_SIM, 1, 25_000);
  constant C_ETH_RESET_CNT : natural := C_ETH_RESET_US * 50;

  signal   eth_rst_cnt : natural range 0 to C_ETH_RESET_CNT;
  signal   eth_rst     : std_logic   := '1';
  signal   eth_txd     : std_logic_vector(1 downto 0);
  signal   eth_txen    : std_logic;
  signal   eth_rxd     : std_logic_vector(1 downto 0);
  signal   eth_rxdv    : std_logic;
  signal   eth_rxer    : std_logic;

begin

  eth_led2_o  <= '0';
  eth_mdc_o   <= '0';
  eth_mdio_io <= 'Z';


  --------------------------------------------------
  -- Keep PHY in reset for prescribed time.
  --------------------------------------------------

  clk_rst_proc : process (eth_clk_i)
  begin
    if rising_edge(eth_clk_i) then
      if eth_rst_cnt > 0 then
        eth_rst_cnt <= eth_rst_cnt - 1;
        eth_rst     <= '1';
      else
        eth_rst <= '0';
      end if;

      if eth_rst_i = '1' then
        eth_rst_cnt <= C_ETH_RESET_CNT;
        eth_rst     <= '1';
      end if;
    end if;
  end process clk_rst_proc;


  --------------------------------------------------
  -- I/O buffering
  --------------------------------------------------

  oddr_clk_inst : component oddr
    port map (
      c  => eth_clk_i,
      ce => '1',
      d1 => '1',
      d2 => '0',
      r  => '0',
      s  => '0',
      q  => eth_clk_o
    ); -- oddr_clk_inst : component oddr

  oddr_txen_inst : component oddr
    port map (
      c  => eth_clk_i,
      ce => '1',
      d1 => eth_txen,
      d2 => eth_txen,
      r  => '0',
      s  => '0',
      q  => eth_tx_en_o
    ); -- oddr_clk_inst : component oddr

  eth_txd_gen : for i in 0 to 1 generate

    oddr_txd_inst : component oddr
      port map (
        c  => eth_clk_i,
        ce => '1',
        d1 => eth_txd(i),
        d2 => eth_txd(i),
        r  => '0',
        s  => '0',
        q  => eth_tx_d_o(i)
      ); -- oddr_txd_inst : component oddr

  end generate eth_txd_gen;

  eth_rst_proc : process (eth_clk_i)
  begin
    if rising_edge(eth_clk_i) then
      eth_rst_n_o <= not eth_rst;
    end if;
  end process eth_rst_proc;

  eth_input_proc : process (eth_clk_i)
  begin
    if rising_edge(eth_clk_i) then
      eth_rxd  <= eth_rx_d_i;
      eth_rxdv <= eth_crs_dv_i;
      eth_rxer <= eth_rxer_i;
    end if;
  end process eth_input_proc;


  --------------------------------------------------
  -- Interface to PHY
  --------------------------------------------------

  eth_rmii_inst : entity work.eth_rmii
    port map (
      eth_clk_i   => eth_clk_i,
      eth_rst_i   => eth_rst,
      rx_valid_o  => eth_rx_valid,
      rx_last_o   => eth_rx_last,
      rx_ok_o     => eth_rx_ok,
      rx_data_o   => eth_rx_data,
      tx_ready_o  => eth_tx_ready,
      tx_valid_i  => eth_tx_valid,
      tx_last_i   => eth_tx_last,
      tx_data_i   => eth_tx_data,
      eth_rxd_i   => eth_rxd,
      eth_crsdv_i => eth_rxdv,
      eth_rxerr_i => eth_rxer,
      eth_txd_o   => eth_txd,
      eth_txen_o  => eth_txen
    ); -- eth_rmii : entity work.eth_rmii

end architecture synthesis;

