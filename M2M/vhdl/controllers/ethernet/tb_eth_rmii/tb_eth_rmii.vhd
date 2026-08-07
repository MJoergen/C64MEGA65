-- Loopback testbench for eth_rmii.vhd with a PHY model that reproduces the
-- RMII "CRS_DV toggles at 25 MHz when carrier is lost while data is still
-- valid" behaviour at the end of a frame (RMII 1.2 / KSZ8081 datasheet).
--
-- G_TOGGLE_DIBITS = 0  -> ideal PHY (what the project's own tb_eth_rmii does)
-- G_TOGGLE_DIBITS > 0  -> CRS_DV toggles for the last N dibits of the frame
-- G_TOGGLE_PHASE       -> which of the two toggle phases

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_eth_rmii is
  generic (
    G_TOGGLE_DIBITS : natural := 0;
    G_TOGGLE_PHASE  : natural := 0;
    G_FRAMES        : natural := 4;
    G_LENGTH        : natural := 64
  );
end entity tb_eth_rmii;

architecture tb of tb_eth_rmii is

  constant C_PIPE : natural                        := 12;

  signal   clk : std_logic                         := '1';
  signal   rst : std_logic                         := '1';

  signal   s_ready : std_logic;
  signal   s_valid : std_logic                     := '0';
  signal   s_data  : std_logic_vector(7 downto 0)  := (others => '0');
  signal   s_last  : std_logic                     := '0';

  signal   m_valid : std_logic;
  signal   m_data  : std_logic_vector(7 downto 0);
  signal   m_last  : std_logic;
  signal   m_ok    : std_logic;

  signal   tx_d  : std_logic_vector(1 downto 0);
  signal   tx_en : std_logic;

  signal   rx_d     : std_logic_vector(1 downto 0);
  signal   rx_crsdv : std_logic;

  type     pipe2_type is array (0 to C_PIPE) of std_logic_vector(1 downto 0);
  signal   d_pipe  : pipe2_type                    := (others => "00");
  signal   en_pipe : std_logic_vector(0 to C_PIPE) := (others => '0');
  signal   phase   : std_logic                     := '0';

  -- Rx frame bookkeeping
  signal   rx_bytes    : natural                   := 0;
  signal   rx_frames   : natural                   := 0;
  signal   rx_good     : natural                   := 0;
  signal   rx_bad      : natural                   := 0;
  signal   rx_len_last : natural                   := 0;

  signal   tx_frames : natural                     := 0;

begin

  clk  <= not clk after 5 ns;
  rst  <= '1', '0' after 100 ns;

  ----------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------
  eth_rmii_inst : entity work.eth_rmii
    port map (
      eth_clk_i   => clk,
      eth_rst_i   => rst,
      rx_valid_o  => m_valid,
      rx_data_o   => m_data,
      rx_ok_o     => m_ok,
      rx_last_o   => m_last,
      tx_ready_o  => s_ready,
      tx_valid_i  => s_valid,
      tx_last_i   => s_last,
      tx_data_i   => s_data,
      eth_rxd_i   => rx_d,
      eth_rxerr_i => '0',
      eth_crsdv_i => rx_crsdv,
      eth_txd_o   => tx_d,
      eth_txen_o  => tx_en
    );

  ----------------------------------------------------------------
  -- PHY model: delay the wire by C_PIPE cycles so we can look ahead
  -- and know when the frame is about to end.
  ----------------------------------------------------------------
  phy_proc : process (clk)
  begin
    if rising_edge(clk) then
      d_pipe(0)  <= tx_d;
      en_pipe(0) <= tx_en;

      for i in 1 to C_PIPE loop
        d_pipe(i)  <= d_pipe(i - 1);
        en_pipe(i) <= en_pipe(i - 1);
      end loop;

      phase <= not phase;
    end if;
  end process phy_proc;

  rx_d <= d_pipe(C_PIPE);

  -- CRS_DV: normally = carrier. During the last G_TOGGLE_DIBITS dibits of a
  -- frame the PHY has lost carrier but is still presenting valid data, so
  -- CRS_DV toggles at 25 MHz (every other 50 MHz cycle).
  crsdv_proc : process (all)
    variable near_end_v : boolean;
  begin
    near_end_v := false;
    if G_TOGGLE_DIBITS > 0 and en_pipe(C_PIPE) = '1' then

      for i in 0 to G_TOGGLE_DIBITS - 1 loop
        if C_PIPE - 1 - i >= 0 then
          if en_pipe(C_PIPE - 1 - i) = '0' then
            near_end_v := true;
          end if;
        end if;
      end loop;

    end if;

    if en_pipe(C_PIPE) = '0' then
      rx_crsdv <= '0';
    elsif near_end_v then
      if G_TOGGLE_PHASE = 0 then
        rx_crsdv <= phase;
      else
        rx_crsdv <= not phase;
      end if;
    else
      rx_crsdv <= '1';
    end if;
  end process crsdv_proc;

  ----------------------------------------------------------------
  -- Rx monitor
  ----------------------------------------------------------------
  mon_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' and m_valid = '1' then
        rx_bytes <= rx_bytes + 1;
        if m_data /= std_logic_vector(to_unsigned((rx_bytes * 5 + rx_frames + 1) mod 256, 8)) then
          report "RX DATA MISMATCH at byte " & integer'image(rx_bytes) &
                 " got " & integer'image(to_integer(unsigned(m_data))) &
                 " expected " & integer'image((rx_bytes * 5 + rx_frames + 1) mod 256)
            severity warning;
        end if;
        if m_last = '1' then
          rx_frames   <= rx_frames + 1;
          rx_len_last <= rx_bytes + 1;
          rx_bytes    <= 0;
          if m_ok = '1' then
            rx_good <= rx_good + 1;
          else
            rx_bad <= rx_bad + 1;
          end if;
          report "RX frame #" & integer'image(rx_frames + 1) &
                 " len=" & integer'image(rx_bytes + 1) &
                 " ok=" & std_logic'image(m_ok);
        end if;
      end if;
    end if;
  end process mon_proc;

  ----------------------------------------------------------------
  -- Tx stimulus
  ----------------------------------------------------------------
  stim_proc : process
  begin
    s_valid <= '0';
    s_last  <= '0';
    wait until rst = '0';

    for f in 1 to G_FRAMES loop
      --
      for i in 0 to G_LENGTH - 1 loop
        s_data  <= std_logic_vector(to_unsigned((i * 5 + f) mod 256, 8));
        s_last  <= '1' when i = G_LENGTH - 1 else '0';
        s_valid <= '1';

        loop
          wait until rising_edge(clk);
          exit when s_ready = '1';
        end loop;

      --
      end loop;

      s_valid <= '0';
      s_last  <= '0';
      -- wait for the MAC to finish the frame + IFG
      for i in 0 to 400 loop
        wait until rising_edge(clk);
      end loop;

    --
    end loop;

    for i in 0 to 400 loop
      wait until rising_edge(clk);
    end loop;

    report "SUMMARY toggle_dibits=" & integer'image(G_TOGGLE_DIBITS) &
           " phase=" & integer'image(G_TOGGLE_PHASE) &
           " : tx_frames=" & integer'image(G_FRAMES) &
           " rx_frames=" & integer'image(rx_frames) &
           " good=" & integer'image(rx_good) &
           " bad=" & integer'image(rx_bad) &
           " last_len=" & integer'image(rx_len_last) &
           " (expected len " & integer'image(G_LENGTH) & ")";
    std.env.stop;
    wait;
  end process stim_proc;

end architecture tb;
