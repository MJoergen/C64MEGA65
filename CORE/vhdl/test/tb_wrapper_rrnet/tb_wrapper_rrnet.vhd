-- Issue #252 item R2, end to end, with eth_wrapper.vhd instantiated as shipped.
--
--   CPU bus <-> rrnet.vhd <-> eth_wrapper.vhd (2 async FIFOs + eth_rmii) <-> wire
--
-- The wire is looped back.  The "C64" programs its MAC, then deliberately does
-- NOT drain the receive buffer while several frames arrive -- exactly what a
-- 1 MHz 6510 does on a busy LAN, since it needs milliseconds per frame.  The
-- 4096-byte Rx FIFO in eth_wrapper then overruns.
--
-- Question under test: does the frame boundary survive?  We finally drain
-- through $DE08/$DE09 and print the RxLength the driver is told.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_wrapper_rrnet is
  generic (
    G_FRAMES : natural := 6;
    G_LENGTH : natural := 1000
  );
end entity tb_wrapper_rrnet;

architecture tb of tb_wrapper_rrnet is

  constant C_CORE_HALF : time := 15.86 ns;
  constant C_ETH_HALF  : time := 10.00 ns;

  signal core_clk : std_logic := '0';
  signal eth_clk  : std_logic := '0';
  signal rst      : std_logic := '1';

  signal cs      : std_logic := '0';
  signal addr    : std_logic_vector(7 downto 0) := (others => '0');
  signal we      : std_logic := '0';
  signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
  signal rd_data : std_logic_vector(7 downto 0);

  signal core_rx_ready : std_logic;
  signal core_rx_valid : std_logic;
  signal core_rx_last  : std_logic;
  signal core_rx_ok    : std_logic;
  signal core_rx_data  : std_logic_vector(7 downto 0);
  signal core_tx_ready : std_logic;
  signal core_tx_valid : std_logic;
  signal core_tx_last  : std_logic;
  signal core_tx_data  : std_logic_vector(7 downto 0);

  signal eth_clk_o : std_logic;
  signal eth_rst_n : std_logic;
  signal eth_led2  : std_logic;
  signal eth_mdc   : std_logic;
  signal eth_mdio  : std_logic;
  signal wire_d    : std_logic_vector(1 downto 0);
  signal wire_en   : std_logic;

begin

  core_clk <= not core_clk after C_CORE_HALF;
  eth_clk  <= not eth_clk  after C_ETH_HALF;
  rst      <= '1', '0' after 300 ns;

  rrnet_inst : entity work.rrnet
    generic map (G_DEBUG => false)
    port map (
      clk_i          => core_clk,
      rst_i          => rst,
      cs_i           => cs,
      addr_i         => addr,
      we_i           => we,
      wr_data_i      => wr_data,
      rd_data_o      => rd_data,
      eth_rx_ready_o => core_rx_ready,
      eth_rx_valid_i => core_rx_valid,
      eth_rx_last_i  => core_rx_last,
      eth_rx_ok_i    => core_rx_ok,
      eth_rx_data_i  => core_rx_data,
      eth_tx_ready_i => core_tx_ready,
      eth_tx_valid_o => core_tx_valid,
      eth_tx_last_o  => core_tx_last,
      eth_tx_data_o  => core_tx_data
    );

  eth_wrapper_inst : entity work.eth_wrapper
    generic map (G_SIM => true)
    port map (
      core_clk_i      => core_clk,
      core_rst_i      => rst,
      core_rx_ready_i => core_rx_ready,
      core_rx_valid_o => core_rx_valid,
      core_rx_last_o  => core_rx_last,
      core_rx_ok_o    => core_rx_ok,
      core_rx_data_o  => core_rx_data,
      core_tx_ready_o => core_tx_ready,
      core_tx_valid_i => core_tx_valid,
      core_tx_last_i  => core_tx_last,
      core_tx_data_i  => core_tx_data,
      eth_clk_i       => eth_clk,
      eth_rst_i       => rst,
      eth_clk_o       => eth_clk_o,
      eth_rst_n_o     => eth_rst_n,
      eth_led2_o      => eth_led2,
      eth_mdc_o       => eth_mdc,
      eth_mdio_io     => eth_mdio,
      eth_rx_d_i      => wire_d,
      eth_crs_dv_i    => wire_en,
      eth_rxer_i      => '0',
      eth_tx_d_o      => wire_d,
      eth_tx_en_o     => wire_en
    );

  main_proc : process

    procedure cpu_write (a : in natural; d : in natural) is
    begin
      wait until rising_edge(core_clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      wr_data <= std_logic_vector(to_unsigned(d, 8));
      we <= '1'; cs <= '1';
      for i in 0 to 15 loop wait until rising_edge(core_clk); end loop;
      cs <= '0'; we <= '0';
      for i in 0 to 15 loop wait until rising_edge(core_clk); end loop;
    end procedure;

    procedure cpu_read (a : in natural; d : out std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(core_clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      we <= '0'; cs <= '1';
      for i in 0 to 15 loop wait until rising_edge(core_clk); end loop;
      d := rd_data;
      cs <= '0';
      for i in 0 to 15 loop wait until rising_edge(core_clk); end loop;
    end procedure;

    procedure set_pp (a : in natural) is
    begin
      cpu_write(16#02#, a mod 256);
      cpu_write(16#03#, a / 256);
    end procedure;

    procedure set_mac is
    begin
      set_pp(16#0158#); cpu_write(16#04#, 16#00#); cpu_write(16#05#, 16#0E#);
      set_pp(16#015A#); cpu_write(16#04#, 16#3A#); cpu_write(16#05#, 16#64#);
      set_pp(16#015C#); cpu_write(16#04#, 16#64#); cpu_write(16#05#, 16#64#);
    end procedure;

    -- Transmit one broadcast frame of G_LENGTH bytes (first octet $FF so the
    -- looped-back copy passes the receive filter).
    procedure send_frame (tag : in natural) is
    begin
      cpu_write(16#0C#, 16#C9#); cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, G_LENGTH mod 256); cpu_write(16#0F#, G_LENGTH / 256);
      for i in 0 to G_LENGTH / 2 - 1 loop
        if i = 0 then
          cpu_write(16#08#, 16#FF#);
        else
          cpu_write(16#08#, (2 * i + tag) mod 256);
        end if;
        cpu_write(16#09#, (2 * i + 1 + tag) mod 256);
      end loop;
      for i in 0 to 4000 loop wait until rising_edge(core_clk); end loop;
    end procedure;

    variable d, dhi, dlo : std_logic_vector(7 downto 0);
    variable len_v : natural;
    variable n : natural;

  begin
    wait until rst = '0';
    for i in 0 to 400 loop wait until rising_edge(core_clk); end loop;

    report "=== R2 end to end: rrnet + eth_wrapper, " & integer'image(G_FRAMES) &
           " frames of " & integer'image(G_LENGTH) & " bytes, C64 never drains ===";
    set_mac;

    for f in 1 to G_FRAMES loop
      send_frame(f);
    end loop;

    for i in 0 to 20000 loop wait until rising_edge(core_clk); end loop;

    report "=== now the C64 starts polling ===";
    n := 0;
    for p in 1 to 12 loop
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      exit when d(0) = '0';
      n := n + 1;
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);          -- RxStatus, discarded
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);          -- RxLength
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "  poll " & integer'image(p) & ": driver is told RxLength = " &
             integer'image(len_v) & "   (transmitted length was " &
             integer'image(G_LENGTH) & ")";
      assert len_v = G_LENGTH
        report "  ^^^ CORRUPT FRAME DELIVERED TO THE IP STACK" severity error;
      -- drain it the way cs8900a.asm does
      for i in 0 to (len_v + 1) / 2 - 1 loop
        cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi);
      end loop;
      for i in 0 to 6000 loop wait until rising_edge(core_clk); end loop;
    end loop;
    report "=== " & integer'image(n) & " frame(s) delivered to the C64 before the extra frame ===";

    -- Now one more perfectly good frame arrives.
    report "=== transmitting one more good frame ===";
    send_frame(99);
    for i in 0 to 20000 loop wait until rising_edge(core_clk); end loop;
    for p in 1 to 4 loop
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      exit when d(0) = '0';
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "  AFTER: driver is told RxLength = " & integer'image(len_v) &
             "   (the frame actually sent was " & integer'image(G_LENGTH) & " bytes)";
      assert len_v = G_LENGTH
        report "  ^^^ CORRUPT FRAME DELIVERED TO THE IP STACK" severity error;
      for i in 0 to (len_v + 1) / 2 - 1 loop
        cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi);
      end loop;
      for i in 0 to 6000 loop wait until rising_edge(core_clk); end loop;
    end loop;

    std.env.stop;
    wait;
  end process main_proc;

end architecture tb;
