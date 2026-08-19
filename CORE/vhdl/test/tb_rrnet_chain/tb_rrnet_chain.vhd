-- End-to-end chain testbench that nothing in the project currently exercises:
--   C64 bus  <->  rrnet.vhd  <->  axis_fifo_async (x2, CDC)  <->  eth_rmii.vhd  <->  wire
-- The wire is looped back (txd -> rxd, txen -> crsdv), so a frame written by the
-- "C64" must come back through the full MAC (preamble, FCS, FCS strip) and be
-- readable again through the CS8900A register interface.
--
-- Clocks are the real ones: core = 31.527778 MHz, eth = 50 MHz.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_rrnet_chain is
  generic (
    G_LENGTH : natural := 100
  );
end entity tb_rrnet_chain;

architecture tb of tb_rrnet_chain is

  constant C_CORE_HALF : time := 15.86 ns;   -- 31.527778 MHz
  constant C_ETH_HALF  : time := 10.00 ns;   -- 50 MHz

  signal core_clk : std_logic := '0';
  signal eth_clk  : std_logic := '0';
  signal rst      : std_logic := '1';

  signal cs      : std_logic := '0';
  signal addr    : std_logic_vector(7 downto 0) := (others => '0');
  signal we      : std_logic := '0';
  signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
  signal rd_data : std_logic_vector(7 downto 0);

  -- core-side stream
  signal core_rx_ready : std_logic;
  signal core_rx_valid : std_logic;
  signal core_rx_last  : std_logic;
  signal core_rx_ok    : std_logic; -- Not used
  signal core_rx_data  : std_logic_vector(7 downto 0);
  signal core_tx_ready : std_logic;
  signal core_tx_valid : std_logic;
  signal core_tx_last  : std_logic;
  signal core_tx_data  : std_logic_vector(7 downto 0);

  -- eth-side stream
  signal eth_rx_ready : std_logic;
  signal eth_rx_valid : std_logic;
  signal eth_rx_last  : std_logic;
  signal eth_rx_ok    : std_logic;
  signal eth_rx_data  : std_logic_vector(7 downto 0);
  signal eth_tx_ready : std_logic;
  signal eth_tx_valid : std_logic;
  signal eth_tx_last  : std_logic;
  signal eth_tx_data  : std_logic_vector(7 downto 0);

  signal wire_d  : std_logic_vector(1 downto 0);
  signal wire_en : std_logic;

  subtype R_DATA is natural range 7 downto 0;
  constant C_LAST : natural := 8;
  constant C_OK   : natural := 9;

begin

  core_clk <= not core_clk after C_CORE_HALF;
  eth_clk  <= not eth_clk  after C_ETH_HALF;
  rst      <= '1', '0' after 300 ns;

  ----------------------------------------------------------------
  rrnet_inst : entity work.rrnet
    generic map (G_DEBUG => false)
    port map (
      clk_i             => core_clk,
      rst_i             => rst,
      cs_i              => cs,
      addr_i            => addr,
      we_i              => we,
      wr_data_i         => wr_data,
      rd_data_o         => rd_data,
      eth_rx_ready_o    => core_rx_ready,
      eth_rx_valid_i    => core_rx_valid,
      eth_rx_last_i     => core_rx_last,
      eth_rx_data_i     => core_rx_data,
      eth_tx_ready_i    => core_tx_ready,
      eth_tx_valid_o    => core_tx_valid,
      eth_tx_last_o     => core_tx_last,
      eth_tx_data_o     => core_tx_data,
      eth_rx_cnt_drop_i => (others => '0')
    );

  -- Rx FIFO: eth domain -> core domain (4096 deep, as in eth_wrapper)
  rx_fifo_inst : entity work.axis_fifo_async
    generic map (
      G_ADDR_BITS => 12,
      G_DATA_BITS => 10,
      G_RAM_STYLE => "block"
    )
    port map (
      async_rst_i      => rst,
      s_clk_i          => eth_clk,
      s_ready_o        => eth_rx_ready,
      s_valid_i        => eth_rx_valid,
      s_data_i(R_DATA) => eth_rx_data,
      s_data_i(C_LAST) => eth_rx_last,
      s_data_i(C_OK)   => eth_rx_ok,
      s_fill_o         => open,
      m_clk_i          => core_clk,
      m_ready_i        => core_rx_ready,
      m_valid_o        => core_rx_valid,
      m_data_o(R_DATA) => core_rx_data,
      m_data_o(C_LAST) => core_rx_last,
      m_data_o(C_OK)   => core_rx_ok,
      m_fill_o         => open
    );

  -- Tx FIFO: core domain -> eth domain (4 deep, as in eth_wrapper)
  tx_fifo_inst : entity work.axis_fifo_async
    generic map (
      G_ADDR_BITS => 2,
      G_DATA_BITS => 9,
      G_RAM_STYLE => "distributed"
    )
    port map (
      async_rst_i      => rst,
      s_clk_i          => core_clk,
      s_ready_o        => core_tx_ready,
      s_valid_i        => core_tx_valid,
      s_data_i(R_DATA) => core_tx_data,
      s_data_i(C_LAST) => core_tx_last,
      s_fill_o         => open,
      m_clk_i          => eth_clk,
      m_ready_i        => eth_tx_ready,
      m_valid_o        => eth_tx_valid,
      m_data_o(R_DATA) => eth_tx_data,
      m_data_o(C_LAST) => eth_tx_last,
      m_fill_o         => open
    );

  eth_rmii_inst : entity work.eth_rmii
    port map (
      eth_clk_i   => eth_clk,
      eth_rst_i   => rst,
      rx_valid_o  => eth_rx_valid,
      rx_last_o   => eth_rx_last,
      rx_ok_o     => eth_rx_ok,
      rx_data_o   => eth_rx_data,
      tx_ready_o  => eth_tx_ready,
      tx_valid_i  => eth_tx_valid,
      tx_last_i   => eth_tx_last,
      tx_data_i   => eth_tx_data,
      eth_rxd_i   => wire_d,
      eth_rxerr_i => '0',
      eth_crsdv_i => wire_en,
      eth_txd_o   => wire_d,
      eth_txen_o  => wire_en
    );

  ----------------------------------------------------------------
  main_proc : process

    procedure cpu_write (a : in natural; d : in natural) is
    begin
      wait until rising_edge(core_clk);
      addr    <= std_logic_vector(to_unsigned(a, 8));
      wr_data <= std_logic_vector(to_unsigned(d, 8));
      we      <= '1';
      cs      <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(core_clk);
      end loop;
      cs <= '0';
      we <= '0';
      for i in 0 to 15 loop
        wait until rising_edge(core_clk);
      end loop;
    end procedure cpu_write;

    procedure cpu_read (a : in natural; d : out std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(core_clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      we   <= '0';
      cs   <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(core_clk);
      end loop;
      d  := rd_data;
      cs <= '0';
      for i in 0 to 15 loop
        wait until rising_edge(core_clk);
      end loop;
    end procedure cpu_read;

    procedure set_pp (a : in natural) is
    begin
      cpu_write(16#02#, a mod 256);
      cpu_write(16#03#, a / 256);
    end procedure set_pp;

    variable d, dhi, dlo : std_logic_vector(7 downto 0);
    variable len_v, exp_v : natural;

  begin
    wait until rst = '0';
    wait until rising_edge(core_clk);

    report "=== CHAIN: C64 -> rrnet -> FIFO -> MAC -> wire -> MAC -> FIFO -> rrnet -> C64 ===";

    -- 'send' exactly as cs8900a.asm does
    cpu_write(16#0C#, 16#C9#);
    cpu_write(16#0D#, 16#00#);
    cpu_write(16#0E#, G_LENGTH mod 256);
    cpu_write(16#0F#, G_LENGTH / 256);
    -- First two bytes are 0xFF
    cpu_write(16#08#, 16#FF#);
    cpu_write(16#09#, 16#FF#);
    for i in 0 to G_LENGTH / 2 - 2 loop
      cpu_write(16#08#, (2 * i * 3 + 11) mod 256);
      cpu_write(16#09#, ((2 * i + 1) * 3 + 11) mod 256);
    end loop;

    -- let the frame go out and come back
    for i in 0 to 40000 loop
      wait until rising_edge(core_clk);
    end loop;

    -- 'poll'
    set_pp(16#0124#);
    cpu_read(16#05#, d);
    assert d(0) = '1'
      report "CHAIN: RxEvent hi = " & integer'image(to_integer(unsigned(d))) &
             " (bit0 must be 1)"
        severity failure;

    cpu_read(16#09#, dhi);
    cpu_read(16#08#, dlo);
    assert dhi(0) = '1'
      report "CHAIN: RxStatus = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo))) & "  (hi bit0 = RxOK from the MAC CRC check)"
        severity failure;

    cpu_read(16#09#, dhi);
    cpu_read(16#08#, dlo);
    len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
    assert G_LENGTH = len_v
      report "CHAIN: RxLength = " & integer'image(len_v) &
             " (expected " & integer'image(G_LENGTH) & ")"
        severity failure;

    cpu_read(16#08#, dlo);
    cpu_read(16#09#, dhi);
    assert unsigned(dlo) = 16#FF# and unsigned(dhi) = 16#FF#
      report "First two bytes are wrong"
        severity failure;

    for i in 0 to G_LENGTH / 2 - 2 loop
      cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi);
      exp_v := (2 * i * 3 + 11) mod 256;
      assert to_integer(unsigned(dlo)) = exp_v
        report "CHAIN mismatch byte " & integer'image(2 * i) &
               " got " & integer'image(to_integer(unsigned(dlo))) &
               " expected " & integer'image(exp_v)
          severity failure;
      exp_v := ((2 * i + 1) * 3 + 11) mod 256;
      assert to_integer(unsigned(dhi)) = exp_v
        report "CHAIN mismatch byte " & integer'image(2 * i + 1) &
               " got " & integer'image(to_integer(unsigned(dhi))) &
               " expected " & integer'image(exp_v)
          severity failure;
    end loop;

    report "=== CHAIN TEST COMPLETE ===";
    wait for 200 ns;
    std.env.stop;
    wait;
  end process main_proc;

end architecture tb;
