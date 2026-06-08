library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity uart_crc is
  generic (
    G_ADDR_SIZE : natural;
    G_DATA_SIZE : natural;
    G_CLOCK_KHZ : natural;
    G_BAUDRATE  : natural
  );
  port (
    clk_i        : in    std_logic;
    rst_i        : in    std_logic;
    uart_tx_o    : out   std_logic;
    uart_rx_i    : in    std_logic;

    -- Wishbone bus Master interface
    fast_clk_i   : in    std_logic;
    fast_rst_i   : in    std_logic;
    wbus_cyc_o   : out   std_logic;                                  -- Valid bus cycle
    wbus_stall_i : in    std_logic;
    wbus_stb_o   : out   std_logic;                                  -- Strobe signals / core select signal
    wbus_addr_o  : out   std_logic_vector(G_ADDR_SIZE - 1 downto 0); -- lower address bits
    wbus_we_o    : out   std_logic;                                  -- Write enable
    wbus_wrdat_o : out   std_logic_vector(G_DATA_SIZE - 1 downto 0); -- Write Databus
    wbus_ack_i   : in    std_logic;                                  -- Bus cycle acknowledge
    wbus_rddat_i : in    std_logic_vector(G_DATA_SIZE - 1 downto 0)  -- Read Databus
  );
end entity uart_crc;

architecture synthesis of uart_crc is

  signal tx_valid : std_logic;
  signal tx_ready : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0);
  signal rx_valid : std_logic;
  signal rx_ready : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);

  signal start : std_logic;
  signal crc   : std_logic_vector(31 downto 0);
  signal crc_d : std_logic_vector(31 downto 0);

  signal fast_busy       : std_logic;
  signal fast_crc        : std_logic_vector(31 downto 0);
  signal fast_crc_stable : std_logic_vector(31 downto 0);

  signal message : std_logic_vector(79 downto 0) := (others => '0'); -- 10 characters

  pure function bin2asc (
    arg : std_logic_vector
  ) return std_logic_vector is
  begin
    if unsigned(arg) < 10 then
      return std_logic_vector(unsigned(arg) + x"30");
    else
      return std_logic_vector(unsigned(arg) + x"41" - 10);
    end if;
  end function bin2asc;

  pure function slv2asc (
    arg : std_logic_vector
  ) return std_logic_vector is
    variable res_v : std_logic_vector(2 * arg'length - 1 downto 0);
  begin
    --
    for i in 0 to arg'length / 4 - 1 loop
      res_v(8 * i + 7 downto 8 * i) := bin2asc(arg(4 * i + 3 downto 4 * i));
    end loop;

    return res_v;
  end function slv2asc;

begin

  crc_proc : process (fast_clk_i)
  begin
    if rising_edge(fast_clk_i) then
      if fast_busy = '0' then
        fast_crc_stable <= fast_crc;
      end if;
    end if;
  end process crc_proc;

  cdc_stable_inst : entity work.cdc_stable
    generic map (
      G_DATA_SIZE    => 32,
      G_REGISTER_SRC => true
    )
    port map (
      src_clk_i  => fast_clk_i,
      src_data_i => fast_crc_stable,
      dst_clk_i  => clk_i,
      dst_data_o => crc
    ); -- cdc_stable_inst : entity work.cdc_stable


  rx_ready <= '1';

  uart_serdes_inst : entity work.uart_serdes
    generic map (
      G_DIVISOR => (G_CLOCK_KHZ * 1000) / G_BAUDRATE
    )
    port map (
      clk_i      => clk_i,
      rst_i      => rst_i,
      tx_valid_i => tx_valid,
      tx_ready_o => tx_ready,
      tx_data_i  => tx_data,
      rx_valid_o => rx_valid,
      rx_ready_i => rx_ready,
      rx_data_o  => rx_data,
      uart_tx_o  => uart_tx_o,
      uart_rx_i  => uart_rx_i
    ); -- uart_serdes_inst : entity work.uart_serdes

  tx_data <= message(79 downto 72);

  uart_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if tx_ready = '1' then
        tx_valid <= '0';
      end if;

      if tx_valid = '0' then
        message <= message(71 downto 0) & x"00";

        if or(message(71 downto 64)) = '1' then
          -- Any nonzero data is transmitted.
          tx_valid <= '1';
        else
          crc_d <= crc;
          if crc_d /= crc then
            message  <= slv2asc(crc) & x"0D0A";
            tx_valid <= '1';
          end if;
        end if;
      end if;

      if rst_i = '1' or rx_valid = '1' then
        crc_d    <= (others => '0');
        tx_valid <= '1';
        message  <= x"4D464A0D0A0000000000";
      end if;
    end if;
  end process uart_proc;

  sweeper_inst : entity work.sweeper
    generic map (
      G_ADDR_SIZE => G_ADDR_SIZE,
      G_DATA_SIZE => G_DATA_SIZE
    )
    port map (
      clk_i        => fast_clk_i,
      rst_i        => fast_rst_i,
      start_i      => '1',
      busy_o       => fast_busy,
      crc_o        => fast_crc,
      wbus_cyc_o   => wbus_cyc_o,
      wbus_stall_i => wbus_stall_i,
      wbus_stb_o   => wbus_stb_o,
      wbus_addr_o  => wbus_addr_o,
      wbus_we_o    => wbus_we_o,
      wbus_wrdat_o => wbus_wrdat_o,
      wbus_ack_i   => wbus_ack_i,
      wbus_rddat_i => wbus_rddat_i
    ); -- sweeper_inst : entity work.sweeper

end architecture synthesis;

