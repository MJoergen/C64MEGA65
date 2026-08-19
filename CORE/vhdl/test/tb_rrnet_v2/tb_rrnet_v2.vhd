-- Re-verification testbench for the hardened rrnet.vhd (WIP-V6-A19X1).
-- Unlike the suite checked into the branch, this one FIRST programs the MAC
-- address through PacketPage $0158/$015A/$015C exactly like cs8900a.asm's
-- reset routine, so the new receive filter actually lets frames through.

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_rrnet_v2 is
  generic (
    G_TEST  : string  := "M0";
    G_LEN   : natural := 100;
    G_DELAY : natural := 0;
    G_FIRST : natural := 255      -- first destination octet of the injected frame
  );
end entity tb_rrnet_v2;

architecture tb of tb_rrnet_v2 is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal rst_pulse : boolean := false;

  signal cs      : std_logic := '0';
  signal addr    : std_logic_vector(7 downto 0) := (others => '0');
  signal we      : std_logic := '0';
  signal wr_data : std_logic_vector(7 downto 0) := (others => '0');
  signal rd_data : std_logic_vector(7 downto 0);

  signal eth_rx_ready : std_logic;
  signal eth_rx_valid : std_logic := '0';
  signal eth_rx_last  : std_logic := '0';
  signal eth_rx_ok    : std_logic := '1';
  signal eth_rx_data  : std_logic_vector(7 downto 0) := (others => '0');

  signal eth_tx_ready : std_logic := '0';
  signal eth_tx_valid : std_logic;
  signal eth_tx_last  : std_logic;
  signal eth_tx_data  : std_logic_vector(7 downto 0);

  type   byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
  signal tx_cap     : byte_array_t(0 to 4095) := (others => (others => '0'));
  signal tx_cap_cnt : natural := 0;
  signal tx_frames  : natural := 0;

  signal fails : natural := 0;

begin

  clk <= not clk after 5 ns;
  rst <= '1' when rst_pulse else '0' after 105 ns;

  eth_tx_ready <= '1' when rst = '0' else '0';

  rrnet_inst : entity work.rrnet
    generic map (G_DEBUG => false)
    port map (
      clk_i          => clk,
      rst_i          => rst,
      cs_i           => cs,
      addr_i         => addr,
      we_i           => we,
      wr_data_i      => wr_data,
      rd_data_o      => rd_data,
      eth_rx_ready_o => eth_rx_ready,
      eth_rx_valid_i => eth_rx_valid,
      eth_rx_last_i  => eth_rx_last,
      eth_rx_ok_i    => eth_rx_ok,
      eth_rx_data_i  => eth_rx_data,
      eth_tx_ready_i => eth_tx_ready,
      eth_tx_valid_o => eth_tx_valid,
      eth_tx_last_o  => eth_tx_last,
      eth_tx_data_o  => eth_tx_data
    );

  tx_cap_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' and eth_tx_valid = '1' and eth_tx_ready = '1' then
        if tx_cap_cnt < 4096 then
          tx_cap(tx_cap_cnt) <= eth_tx_data;
        end if;
        tx_cap_cnt <= tx_cap_cnt + 1;
        if eth_tx_last = '1' then
          tx_frames <= tx_frames + 1;
        end if;
      end if;
    end if;
  end process tx_cap_proc;

  main_proc : process

    procedure cpu_write (a : in natural; d : in natural) is
    begin
      wait until rising_edge(clk);
      addr    <= std_logic_vector(to_unsigned(a, 8));
      wr_data <= std_logic_vector(to_unsigned(d, 8));
      we      <= '1';
      cs      <= '1';
      for i in 0 to 15 loop wait until rising_edge(clk); end loop;
      cs <= '0'; we <= '0';
      for i in 0 to 15 loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure cpu_read (a : in natural; d : out std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      we   <= '0';
      cs   <= '1';
      for i in 0 to 15 loop wait until rising_edge(clk); end loop;
      d := rd_data;
      cs <= '0';
      for i in 0 to 15 loop wait until rising_edge(clk); end loop;
    end procedure;

    procedure set_pp (a : in natural) is
    begin
      cpu_write(16#02#, a mod 256);
      cpu_write(16#03#, a / 256);
    end procedure;

    -- Program MAC 00:0E:3A:64:64:64 exactly like cs8900a.asm 'reset' does
    procedure set_mac is
    begin
      set_pp(16#0158#); cpu_write(16#04#, 16#00#); cpu_write(16#05#, 16#0E#);
      set_pp(16#015A#); cpu_write(16#04#, 16#3A#); cpu_write(16#05#, 16#64#);
      set_pp(16#015C#); cpu_write(16#04#, 16#64#); cpu_write(16#05#, 16#64#);
    end procedure;

    -- Inject a frame. Byte 0 = first_octet, remaining bytes = (i*7+seed) mod 256.
    procedure rx_frame (len : in natural; first_octet : in natural;
                        mark_last : in boolean; seed : in natural; ok : in std_logic) is
    begin
      for i in 0 to len - 1 loop
        if i = 0 then
          eth_rx_data <= std_logic_vector(to_unsigned(first_octet, 8));
        else
          eth_rx_data <= std_logic_vector(to_unsigned((i * 7 + seed) mod 256, 8));
        end if;
        eth_rx_last  <= '1' when (i = len - 1 and mark_last) else '0';
        eth_rx_ok    <= ok when (i = len - 1) else '1';
        eth_rx_valid <= '1';
        loop
          wait until rising_edge(clk);
          exit when eth_rx_ready = '1';
        end loop;
      end loop;
      eth_rx_valid <= '0';
      eth_rx_last  <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure chk (cond : in boolean; msg : in string) is
    begin
      if cond then
        report "  PASS: " & msg;
      else
        report "  FAIL: " & msg severity failure;
        fails <= fails + 1;
      end if;
    end procedure;

    variable d, dhi, dlo : std_logic_vector(7 downto 0);
    variable len_v, exp_v, bad_v : natural;

  begin
    wait until rst = '0';
    wait until rising_edge(clk);

    ------------------------------------------------------------------
    if G_TEST = "M0" then
      -- Baseline: with the MAC programmed, is a frame received at all?
      report "=== M0: baseline Rx, first octet = " & integer'image(G_FIRST) & " ===";
      set_mac;
      rx_frame(G_LEN, G_FIRST, true, 3, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "M0: RxEvent hi = " & integer'image(to_integer(unsigned(d)));
      if d(0) = '1' then
        cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
        report "M0: RxStatus = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo)));
        cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
        len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
        report "M0: RxLength = " & integer'image(len_v) & " (sent " & integer'image(G_LEN) & ")";
        bad_v := 0;
        for i in 0 to G_LEN / 2 - 1 loop
          cpu_read(16#08#, dlo);
          cpu_read(16#09#, dhi);
          if i = 0 then
            exp_v := G_FIRST;
          else
            exp_v := ((2 * i) * 7 + 3) mod 256;
          end if;
          if to_integer(unsigned(dlo)) /= exp_v then bad_v := bad_v + 1; end if;
          exp_v := ((2 * i + 1) * 7 + 3) mod 256;
          if to_integer(unsigned(dhi)) /= exp_v then bad_v := bad_v + 1; end if;
        end loop;
        report "M0: " & integer'image(bad_v) & " payload mismatches out of " & integer'image(G_LEN);
        chk(len_v = G_LEN and bad_v = 0, "frame received intact");
      else
        report "M0: FRAME DROPPED (filter)";
        chk(false, "frame accepted");
      end if;

    ------------------------------------------------------------------
    elsif G_TEST = "FILT" then
      -- Acceptance matrix for the new one-octet MAC filter.
      report "=== FILT: first octet " & integer'image(G_FIRST) & " ===";
      set_mac;
      rx_frame(64, G_FIRST, true, 3, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      if d(0) = '1' then
        report "FILT: first octet " & integer'image(G_FIRST) & " -> ACCEPTED";
      else
        report "FILT: first octet " & integer'image(G_FIRST) & " -> dropped";
      end if;

    ------------------------------------------------------------------
    elsif G_TEST = "R1" then
      -- Oversized Rx frame with the filter satisfied.
      report "=== R1: oversized Rx frame, " & integer'image(G_LEN) & " bytes ===";
      set_mac;
      set_pp(16#0000#);
      cpu_read(16#04#, dlo); cpu_read(16#05#, dhi);
      report "R1: EISA before = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo)));
      rx_frame(G_LEN, 16#FF#, true, 5, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0000#);
      cpu_read(16#04#, dlo); cpu_read(16#05#, dhi);
      report "R1: EISA after  = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo)));
      chk(dhi = X"63" and dlo = X"0E", "PacketPage registers intact");
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "R1: RxEvent hi = " & integer'image(to_integer(unsigned(d))) &
             " (0 = oversized frame discarded)";
      if d(0) = '1' then
        cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
        len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
        report "R1: a frame WAS delivered, RxLength = " & integer'image(len_v);
      end if;
      -- receiver must still work afterwards
      rx_frame(80, 16#FF#, true, 9, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "R1: next frame RxLength = " & integer'image(len_v) & " (expect 80)";
      chk(len_v = 80, "receiver recovered after an oversized frame");

    ------------------------------------------------------------------
    elsif G_TEST = "P5" then
      -- Frame with a CRC error must be discarded.
      report "=== P5: frame with eth_rx_ok = 0 ===";
      set_mac;
      rx_frame(100, 16#FF#, true, 3, '0');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "P5: RxEvent hi after bad frame = " & integer'image(to_integer(unsigned(d)));
      chk(d(0) = '0', "bad frame discarded");
      rx_frame(70, 16#FF#, true, 9, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "P5: good frame after bad one, RxLength = " & integer'image(len_v) & " (expect 70)";
      chk(len_v = 70, "receiver still works after a bad frame");

    ------------------------------------------------------------------
    elsif G_TEST = "P1" then
      -- skipframe must now release the buffer.
      report "=== P1: skipframe (RxCFG $0102 bit 6) ===";
      set_mac;
      rx_frame(100, 16#FF#, true, 3, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#); cpu_read(16#05#, d);
      chk(d(0) = '1', "frame is pending before skip");
      set_pp(16#0102#);
      cpu_read(16#04#, d);
      cpu_write(16#04#, to_integer(unsigned(d or X"40")));
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#); cpu_read(16#05#, d);
      report "P1: RxEvent hi after skip = " & integer'image(to_integer(unsigned(d)));
      chk(d(0) = '0', "skipframe released the buffer");
      rx_frame(70, 16#FF#, true, 9, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#); cpu_read(16#05#, d);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "P1: next frame RxLength = " & integer'image(len_v) & " (expect 70)";
      chk(len_v = 70, "receiver re-armed after skipframe");

    ------------------------------------------------------------------
    elsif G_TEST = "R4" then
      -- Tx starting near the RX_HEADER_ST window must not lose the header.
      set_mac;
      cpu_write(16#0C#, 16#C9#); cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 64);     cpu_write(16#0F#, 0);
      for i in 0 to 30 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      cpu_write(16#08#, 16#FE#);
      for i in 0 to 38 loop
        if i = 0 then
          eth_rx_data <= X"FF";
        else
          eth_rx_data <= std_logic_vector(to_unsigned((i * 7 + 3) mod 256, 8));
        end if;
        eth_rx_last <= '0'; eth_rx_ok <= '1'; eth_rx_valid <= '1';
        loop wait until rising_edge(clk); exit when eth_rx_ready = '1'; end loop;
      end loop;
      eth_rx_valid <= '0';
      wait until rising_edge(clk);
      addr <= X"09"; wr_data <= X"FF"; we <= '1'; cs <= '1';
      for i in 1 to G_DELAY loop wait until rising_edge(clk); end loop;
      eth_rx_data <= std_logic_vector(to_unsigned((39 * 7 + 3) mod 256, 8));
      eth_rx_last <= '1'; eth_rx_ok <= '1'; eth_rx_valid <= '1';
      loop wait until rising_edge(clk); exit when eth_rx_ready = '1'; end loop;
      eth_rx_valid <= '0'; eth_rx_last <= '0';
      for i in 0 to 30 loop wait until rising_edge(clk); end loop;
      cs <= '0'; we <= '0';
      for i in 0 to 4000 loop wait until rising_edge(clk); end loop;
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "R4 delay=" & integer'image(G_DELAY) & ": RxLength = " & integer'image(len_v) &
             " (expect 40)";
      chk(len_v = 40, "header survived a Tx start at delay " & integer'image(G_DELAY));

    ------------------------------------------------------------------
    elsif G_TEST = "R3" then
      -- Oversized TxLength must be rejected, and the transmitter must recover.
      report "=== R3: TxLength = " & integer'image(G_LEN) & " ===";
      cpu_write(16#0C#, 16#C9#); cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, G_LEN mod 256); cpu_write(16#0F#, G_LEN / 256);
      for i in 0 to (G_LEN + 1) / 2 - 1 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      for i in 0 to 3000 loop wait until rising_edge(clk); end loop;
      report "R3: transmitted " & integer'image(tx_cap_cnt) & " bytes in " &
             integer'image(tx_frames) & " frame(s)";
      set_pp(16#0138#);
      cpu_read(16#04#, dlo);
      report "R3: BusST lo = " & integer'image(to_integer(unsigned(dlo))) &
             " (bit 7 = TxBidErr)";
      set_pp(16#0000#);
      cpu_read(16#04#, dlo); cpu_read(16#05#, dhi);
      chk(dhi = X"63" and dlo = X"0E", "PacketPage registers intact");
      -- now a legal frame must go out
      exp_v := tx_cap_cnt;
      cpu_write(16#0C#, 16#C9#); cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 64); cpu_write(16#0F#, 0);
      for i in 0 to 31 loop
        cpu_write(16#08#, 16#11#);
        cpu_write(16#09#, 16#22#);
      end loop;
      for i in 0 to 2000 loop wait until rising_edge(clk); end loop;
      report "R3: after recovery attempt, total " & integer'image(tx_cap_cnt) &
             " bytes in " & integer'image(tx_frames) & " frame(s)";
      chk(tx_cap_cnt = exp_v + 64, "transmitter recovered and sent the next 64-byte frame");

    ------------------------------------------------------------------
    elsif G_TEST = "P2" then
      -- TxCMD/TxLength through the PacketPage window.
      report "=== P2: TxCMD/TxLength via PacketPage ===";
      set_pp(16#0146#);                    -- TxLength first
      cpu_write(16#04#, 100); cpu_write(16#05#, 0);
      set_pp(16#0144#);                    -- then TxCMD (resets reg_tx_ptr)
      cpu_write(16#04#, 16#C9#); cpu_write(16#05#, 16#00#);
      for i in 0 to 49 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      for i in 0 to 3000 loop wait until rising_edge(clk); end loop;
      report "P2: transmitted " & integer'image(tx_cap_cnt) & " bytes in " &
             integer'image(tx_frames) & " frame(s)  (expect 100 in 1)";
      chk(tx_frames = 1 and tx_cap_cnt = 100, "exactly one 100-byte frame");
      bad_v := 0;
      for i in 0 to 99 loop
        if tx_cap(i) /= std_logic_vector(to_unsigned(i mod 256, 8)) then
          bad_v := bad_v + 1;
        end if;
      end loop;
      chk(bad_v = 0, "payload correct");

    ------------------------------------------------------------------
    elsif G_TEST = "R5" then
      -- An autoincrement PP read in the Tx-buffer area must NOT discard a frame.
      report "=== R5: autoincrement read at $0A00 with a frame pending ===";
      set_mac;
      rx_frame(64, 16#FF#, true, 3, '1');
      for i in 0 to 40 loop wait until rising_edge(clk); end loop;
      set_pp(16#0124#); cpu_read(16#05#, d);
      chk(d(0) = '1', "frame pending");
      cpu_write(16#02#, 16#00#);
      cpu_write(16#03#, 16#8A#);           -- ptr = $0A00 + autoincrement
      for i in 0 to 7 loop
        cpu_read(16#04#, dlo);
        cpu_read(16#05#, dhi);
      end loop;
      set_pp(16#0124#); cpu_read(16#05#, d);
      report "R5: RxEvent hi after Tx-buffer walk = " & integer'image(to_integer(unsigned(d)));
      chk(d(0) = '1', "frame survived the unrelated autoincrement read");

    ------------------------------------------------------------------
    elsif G_TEST = "P7" then
      -- PacketPage reset values.
      report "=== P7: PacketPage reset values ===";
      for a in 0 to 15 loop
        set_pp(16#0100# + 2 * a);
        cpu_read(16#04#, dlo);
        cpu_read(16#05#, dhi);
        exp_v := (16#0100# + 2 * a + 1) mod 64;
        report "P7: PP $01" & integer'image(16#00# + 2 * a) & " = " &
               integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) &
               "  expect lo=" & integer'image(exp_v);
      end loop;
      for a in 0 to 15 loop
        set_pp(16#0120# + 2 * a);
        cpu_read(16#04#, dlo);
        cpu_read(16#05#, dhi);
        exp_v := (16#0120# + 2 * a + 1 - 33) mod 64;
        report "P7: PP $01" & integer'image(16#20# + 2 * a) & " = " &
               integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) &
               "  expect lo=" & integer'image(exp_v);
      end loop;

    end if;

    report "=== TEST " & G_TEST & " DONE, failures = " & integer'image(fails) & " ===";
    wait for 100 ns;
    std.env.stop;
    wait;
  end process main_proc;

end architecture tb;
