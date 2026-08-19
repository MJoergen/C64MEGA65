-- ------------------------------------------------
-- Description: Encapsulate low-level communication with
-- ethernet PHY. The core clock must be at least 12.5 MHz,
-- to allow back-to-back byte transfers.
-- Frames with errors (e.g. bad CRC) are discarded, and
-- counted in core_rx_cnt_drop_o.
-- ------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library work;
  -- for ETH_FIFO_ADDR_BITS
  use work.globals.all;

library unisim;
  -- for ODDR
  use unisim.vcomponents.all;

entity eth_wrapper is
  generic (
    G_SIM : boolean := false
  );
  port (
    -- Connect to CORE
    core_clk_i         : in    std_logic; -- At least 12.5 MHz
    core_rst_i         : in    std_logic; -- Synchronous, active high
    core_rx_ready_i    : in    std_logic;
    core_rx_valid_o    : out   std_logic;
    core_rx_last_o     : out   std_logic;
    core_rx_data_o     : out   std_logic_vector(7 downto 0);
    core_tx_ready_o    : out   std_logic;
    core_tx_valid_i    : in    std_logic;
    core_tx_last_i     : in    std_logic;
    core_tx_data_i     : in    std_logic_vector(7 downto 0);
    core_rx_cnt_drop_o : out   std_logic_vector(15 downto 0);

    -- Connect to framework
    eth_clk_i          : in    std_logic; -- 50 MHz
    eth_rst_i          : in    std_logic; -- Synchronous, active high

    -- Connected to the PHY
    eth_clk_o          : out   std_logic;
    eth_rst_n_o        : out   std_logic;
    eth_led2_o         : out   std_logic;
    eth_mdc_o          : out   std_logic;
    eth_mdio_io        : inout std_logic;
    eth_rx_d_i         : in    std_logic_vector(1 downto 0);
    eth_crs_dv_i       : in    std_logic;
    eth_rxer_i         : in    std_logic;
    eth_tx_d_o         : out   std_logic_vector(1 downto 0);
    eth_tx_en_o        : out   std_logic
  );
end entity eth_wrapper;

architecture rtl of eth_wrapper is

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

  subtype  R_DATA is natural range 7 downto 0;

  constant C_LAST : natural          := 8;
  constant C_OK   : natural          := 9;

  signal   eth_rx_valid : std_logic;
  signal   eth_rx_last  : std_logic;
  signal   eth_rx_ok    : std_logic;
  signal   eth_rx_data  : std_logic_vector(7 downto 0);
  signal   eth_tx_ready : std_logic;
  signal   eth_tx_valid : std_logic;
  signal   eth_tx_last  : std_logic;
  signal   eth_tx_data  : std_logic_vector(7 downto 0);

  signal   core_rx_ready : std_logic;
  signal   core_rx_valid : std_logic;
  signal   core_rx_last  : std_logic;
  signal   core_rx_ok    : std_logic;
  signal   core_rx_data  : std_logic_vector(7 downto 0);

begin

  -- Default (unused) connections
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

  oddr_clk_inst : component ODDR
    port map (
      c  => eth_clk_i,
      ce => '1',
      d1 => '1',
      d2 => '0',
      r  => '0',
      s  => '0',
      q  => eth_clk_o
    ); -- oddr_clk_inst

  oddr_txen_inst : component ODDR
    port map (
      c  => eth_clk_i,
      ce => '1',
      d1 => eth_txen,
      d2 => eth_txen,
      r  => '0',
      s  => '0',
      q  => eth_tx_en_o
    ); -- oddr_clk_inst

  eth_txd_gen : for i in 0 to 1 generate

    oddr_txd_inst : component ODDR
      port map (
        c  => eth_clk_i,
        ce => '1',
        d1 => eth_txd(i),
        d2 => eth_txd(i),
        r  => '0',
        s  => '0',
        q  => eth_tx_d_o(i)
      ); -- oddr_txd_inst

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


  --------------------------------------------------
  -- Packet buffer.
  -- Frames are dropped either when buffer is full,
  -- or in case of CRC errors.
  --------------------------------------------------

  axis_dropper_inst : entity work.axis_dropper
    generic map (
      G_ADDR_BITS => ETH_FIFO_ADDR_BITS,
      G_DATA_BITS => 8,
      G_CNT_BITS  => 16,
      G_RAM_STYLE => "block"
    )
    port map (
      clk_i      => core_clk_i,
      rst_i      => core_rst_i,
      cnt_drop_o => core_rx_cnt_drop_o,
      s_ready_o  => core_rx_ready,
      s_valid_i  => core_rx_valid,
      s_data_i   => core_rx_data,
      s_drop_i   => (core_rx_valid and not core_rx_ready) or (core_rx_last and not core_rx_ok),
      s_last_i   => core_rx_last,
      m_ready_i  => core_rx_ready_i,
      m_valid_o  => core_rx_valid_o,
      m_data_o   => core_rx_data_o,
      m_last_o   => core_rx_last_o
    ); -- axis_dropper_inst


  --------------------------------------------------
  -- Clock Domain Crossing
  --------------------------------------------------

  axis_fifo_async_rx_inst : entity work.axis_fifo_async
    generic map (
      G_ADDR_BITS => 2,
      G_DATA_BITS => 10,
      G_RAM_STYLE => "distributed"
    )
    port map (
      async_rst_i      => eth_rst,
      s_clk_i          => eth_clk_i,
      s_ready_o        => open, -- Back-pressure here not supported
      s_valid_i        => eth_rx_valid,
      s_data_i(R_DATA) => eth_rx_data,
      s_data_i(C_LAST) => eth_rx_last,
      s_data_i(C_OK)   => eth_rx_ok,
      s_fill_o         => open,
      m_clk_i          => core_clk_i,
      m_ready_i        => '1',  -- Back-pressure handled by axis_dropper
      m_valid_o        => core_rx_valid,
      m_data_o(R_DATA) => core_rx_data,
      m_data_o(C_LAST) => core_rx_last,
      m_data_o(C_OK)   => core_rx_ok,
      m_fill_o         => open
    ); -- axis_fifo_async_rx_inst

  axis_fifo_async_tx_inst : entity work.axis_fifo_async
    generic map (
      G_ADDR_BITS => 2,
      G_DATA_BITS => 9,
      G_RAM_STYLE => "distributed"
    )
    port map (
      async_rst_i      => eth_rst,
      s_clk_i          => core_clk_i,
      s_ready_o        => core_tx_ready_o,
      s_valid_i        => core_tx_valid_i,
      s_data_i(R_DATA) => core_tx_data_i,
      s_data_i(C_LAST) => core_tx_last_i,
      s_fill_o         => open,
      m_clk_i          => eth_clk_i,
      m_ready_i        => eth_tx_ready,
      m_valid_o        => eth_tx_valid,
      m_data_o(R_DATA) => eth_tx_data,
      m_data_o(C_LAST) => eth_tx_last,
      m_fill_o         => open
    ); -- axis_fifo_async_tx_inst

end architecture rtl;

