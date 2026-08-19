-- Answer to MJoergen's challenge on issue #252 item R2:
--   "If you still believe there is a bug, then please provide a testbench that
--    includes instantiation of eth_wrapper.vhd."
--
-- This instantiates eth_wrapper.vhd AS SHIPPED (with a behavioural stand-in for
-- the Xilinx ODDR output primitive only, which is not in the receive path), on
-- the real clocks (core 31.527778 MHz, eth 50 MHz), with the RMII wire looped
-- back so the wrapper receives exactly what it transmits.
--
-- The client (which in the real design is rrnet.vhd) is modelled by its
-- back-pressure signal core_rx_ready_i.  rrnet holds that low whenever it has
-- an undrained frame -- which on a real LAN is most of the time, because the
-- 1 MHz 6510 needs milliseconds to copy a frame out.
--
-- The experiment: transmit G_FRAMES frames of G_LENGTH bytes while the client
-- is stalled, then release the client and inspect the beat stream that comes
-- out of the wrapper.  Every frame the client sees must be terminated by
-- exactly one core_rx_last_o beat and must have the transmitted length.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_wrapper_overrun is
  generic (
    G_FRAMES : natural := 6;
    G_LENGTH : natural := 1000
  );
end entity tb_wrapper_overrun;

architecture tb of tb_wrapper_overrun is

  constant C_CORE_HALF : time := 15.86 ns;   -- 31.527778 MHz
  constant C_ETH_HALF  : time := 10.00 ns;   -- 50 MHz

  signal core_clk : std_logic := '0';
  signal eth_clk  : std_logic := '0';
  signal rst      : std_logic := '1';

  signal core_rx_ready : std_logic := '0';
  signal core_rx_valid : std_logic;
  signal core_rx_last  : std_logic;
  signal core_rx_data  : std_logic_vector(7 downto 0);
  signal core_tx_ready : std_logic;
  signal core_tx_valid : std_logic := '0';
  signal core_tx_last  : std_logic := '0';
  signal core_tx_data  : std_logic_vector(7 downto 0) := (others => '0');

  -- PHY pins, looped back
  signal eth_clk_o    : std_logic;
  signal eth_rst_n    : std_logic;
  signal eth_led2     : std_logic;
  signal eth_mdc      : std_logic;
  signal eth_mdio     : std_logic;
  signal wire_d       : std_logic_vector(1 downto 0);
  signal wire_en      : std_logic;
  signal wire_er      : std_logic := '0';

  -- observation
  signal beats        : natural := 0;   -- beats in the current frame
  signal frames_out   : natural := 0;
  signal bad_len      : natural := 0;
  signal total_beats  : natural := 0;

begin

  core_clk <= not core_clk after C_CORE_HALF;
  eth_clk  <= not eth_clk  after C_ETH_HALF;
  rst      <= '1', '0' after 300 ns;

  eth_wrapper_inst : entity work.eth_wrapper
    generic map (
      G_SIM => true                       -- shortens the 25 ms PHY reset to 1 us
    )
    port map (
      core_clk_i      => core_clk,
      core_rst_i      => rst,
      core_rx_ready_i => core_rx_ready,
      core_rx_valid_o => core_rx_valid,
      core_rx_last_o  => core_rx_last,
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
      eth_rxer_i      => wire_er,
      eth_tx_d_o      => wire_d,
      eth_tx_en_o     => wire_en
    );

  ------------------------------------------------------------------
  -- Client model: count beats and frame boundaries
  ------------------------------------------------------------------
  mon_proc : process (core_clk)
  begin
    if rising_edge(core_clk) then
      if rst = '0' and core_rx_valid = '1' and core_rx_ready = '1' then
        total_beats <= total_beats + 1;
        if core_rx_last = '1' then
          frames_out <= frames_out + 1;
          report "  frame out #" & integer'image(frames_out + 1) &
                 ": " & integer'image(beats + 1) & " bytes";
          if beats + 1 /= G_LENGTH then
            bad_len <= bad_len + 1;
          end if;
          beats <= 0;
        else
          beats <= beats + 1;
        end if;
      end if;
    end if;
  end process mon_proc;

  ------------------------------------------------------------------
  -- Stimulus
  ------------------------------------------------------------------
  stim_proc : process
  begin
    core_rx_ready <= '0';                 -- client stalled: an undrained frame
    core_tx_valid <= '0';
    core_tx_last  <= '0';
    wait until rst = '0';
    for i in 0 to 200 loop
      wait until rising_edge(core_clk);
    end loop;

    report "=== eth_wrapper overrun test: " & integer'image(G_FRAMES) &
           " frames of " & integer'image(G_LENGTH) &
           " bytes, Rx FIFO is 4096 bytes, client stalled ===";

    for f in 1 to G_FRAMES loop
      for i in 0 to G_LENGTH - 1 loop
        core_tx_data  <= std_logic_vector(to_unsigned((i + f) mod 256, 8));
        core_tx_last  <= '1' when i = G_LENGTH - 1 else '0';
        core_tx_valid <= '1';
        loop
          wait until rising_edge(core_clk);
          exit when core_tx_ready = '1';
        end loop;
      end loop;
      core_tx_valid <= '0';
      core_tx_last  <= '0';
      -- let the frame finish on the wire and come back in
      for i in 0 to 3 * G_LENGTH + 2000 loop
        wait until rising_edge(core_clk);
      end loop;
    end loop;

    report "=== all frames transmitted; now releasing the client ===";
    core_rx_ready <= '1';
    for i in 0 to 300000 loop
      wait until rising_edge(core_clk);
      exit when i > 200 and core_rx_valid = '0' and beats = 0;
    end loop;
    for i in 0 to 5000 loop
      wait until rising_edge(core_clk);
    end loop;

    report "SUMMARY: transmitted " & integer'image(G_FRAMES) &
           " frames of " & integer'image(G_LENGTH) & " bytes";
    report "SUMMARY: client saw " & integer'image(frames_out) &
           " complete frames, " & integer'image(total_beats) & " beats total";
    report "SUMMARY: frames with the WRONG length: " & integer'image(bad_len);
    report "SUMMARY: beats left over after the last 'last' marker: " &
           integer'image(beats) & "  (non-zero = a frame with no end marker)";
    assert bad_len = 0
      report "ERROR: bad_len"
        severity error;
    assert beats = 0
      report "ERROR: beats"
        severity error;
    std.env.stop;
    wait;
  end process stim_proc;

end architecture tb;
