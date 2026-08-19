-- Standalone probe testbench for CORE/vhdl/rrnet.vhd
-- Research only: drives the CPU-side bus directly (no 65c02 needed) and models
-- the ethernet side the way eth_wrapper.vhd actually wires it (AXI-stream with
-- back-pressure via eth_rx_ready_o, and a LEVEL tx ready coming from a FIFO).

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_rrnet_probe is
  generic (
    G_TEST      : string  := "T1";
    G_TX_LEVEL  : boolean := true;   -- true: ready is a level (real system), false: pulse every 2nd cycle (tb_rrnet)
    G_DELAY     : natural := 0       -- TC only: cycles between end-of-Rx-frame and the Tx trigger write
  );
end entity tb_rrnet_probe;

architecture tb of tb_rrnet_probe is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

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

  -- Captured transmitted frame
  type   byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);
  signal tx_cap     : byte_array_t(0 to 2047) := (others => (others => '0'));
  signal tx_cap_cnt : natural := 0;
  signal tx_frames  : natural := 0;

  signal rst_pulse : boolean := false;
  signal test_done : boolean := false;
  signal errors    : natural := 0;

  signal tx_ready_toggle : std_logic := '0';

begin

  clk <= not clk after 5 ns;   -- 100 MHz (timescale irrelevant, purely synchronous)
  rst <= '1' when rst_pulse else '0' after 105 ns;

  ----------------------------------------------------------------
  -- DUT
  ----------------------------------------------------------------
  rrnet_inst : entity work.rrnet
    generic map (
      G_DEBUG => false
    )
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

  ----------------------------------------------------------------
  -- Tx sink: emulate the async FIFO's s_ready_o
  ----------------------------------------------------------------
  tx_ready_toggle <= not tx_ready_toggle when rising_edge(clk);

  eth_tx_ready <= '1'             when G_TX_LEVEL and rst = '0' else
                  tx_ready_toggle when (not G_TX_LEVEL) and rst = '0' else
                  '0';

  tx_capture_proc : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '0' and eth_tx_valid = '1' and eth_tx_ready = '1' then
        if tx_cap_cnt < 2048 then
          tx_cap(tx_cap_cnt) <= eth_tx_data;
        end if;
        tx_cap_cnt <= tx_cap_cnt + 1;
        if eth_tx_last = '1' then
          tx_frames <= tx_frames + 1;
        end if;
      end if;
    end if;
  end process tx_capture_proc;

  ----------------------------------------------------------------
  -- Main stimulus
  ----------------------------------------------------------------
  main_proc : process

    -- One CPU bus cycle: cs high for 16 clocks, low for 16 clocks
    -- (mirrors core_ioe which is asserted for the CPU half of the 32-cycle
    --  sysCycle frame in fpga64_sid_iec.vhd).
    procedure cpu_write (a : in natural; d : in natural) is
    begin
      wait until rising_edge(clk);
      addr    <= std_logic_vector(to_unsigned(a, 8));
      wr_data <= std_logic_vector(to_unsigned(d, 8));
      we      <= '1';
      cs      <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(clk);
      end loop;
      cs <= '0';
      we <= '0';
      for i in 0 to 15 loop
        wait until rising_edge(clk);
      end loop;
    end procedure cpu_write;

    procedure cpu_read (a : in natural; d : out std_logic_vector(7 downto 0)) is
    begin
      wait until rising_edge(clk);
      addr <= std_logic_vector(to_unsigned(a, 8));
      we   <= '0';
      cs   <= '1';
      for i in 0 to 15 loop
        wait until rising_edge(clk);
      end loop;
      d  := rd_data;
      cs <= '0';
      for i in 0 to 15 loop
        wait until rising_edge(clk);
      end loop;
    end procedure cpu_read;

    procedure set_pp (a : in natural) is
    begin
      cpu_write(16#02#, a mod 256);
      cpu_write(16#03#, a / 256);
    end procedure set_pp;

    -- Feed one ethernet frame into the Rx port, honouring eth_rx_ready_o.
    -- pattern(i) = (i*7+3) mod 256, so it is reproducible.
    procedure rx_frame (len : in natural; mark_last : in boolean; seed : in natural) is
    begin
      -- Start frame with the byte pair 0xFFFF
      eth_rx_data  <= (others => '1');
      eth_rx_last  <= '0';
      eth_rx_ok    <= '0';
      eth_rx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when eth_rx_ready = '1';
      end loop;

      eth_rx_data  <= (others => '1');
      eth_rx_last  <= '0';
      eth_rx_ok    <= '0';
      eth_rx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when eth_rx_ready = '1';
      end loop;

      for i in 2 to len - 1 loop
        eth_rx_data  <= std_logic_vector(to_unsigned((i * 7 + seed) mod 256, 8));
        eth_rx_last  <= '1' when (i = len - 1 and mark_last) else '0';
        eth_rx_ok    <= '1';
        eth_rx_valid <= '1';
        loop
          wait until rising_edge(clk);
          exit when eth_rx_ready = '1';
        end loop;
      end loop;
      eth_rx_valid <= '0';
      eth_rx_last  <= '0';
      wait until rising_edge(clk);
    end procedure rx_frame;

    variable d      : std_logic_vector(7 downto 0);
    variable dhi    : std_logic_vector(7 downto 0);
    variable dlo    : std_logic_vector(7 downto 0);
    variable len_v  : natural;
    variable exp_v  : natural;
    variable bad_v  : natural;

  begin
    wait until rst = '0';
    wait until rising_edge(clk);

    ----------------------------------------------------------------
    if G_TEST = "T1" then
      -- Transmit a 64-byte frame exactly the way cs8900a.asm 'send' does
      report "=== T1: Tx frame, G_TX_LEVEL=" & boolean'image(G_TX_LEVEL) & " ===";
      cpu_write(16#0C#, 16#C9#);        -- TxCMD lo  (also resets reg_tx_ptr)
      cpu_write(16#0D#, 16#00#);        -- TxCMD hi
      cpu_write(16#0E#, 64);            -- TxLength lo
      cpu_write(16#0F#, 0);             -- TxLength hi
      for i in 0 to 31 loop
        cpu_write(16#08#, (2 * i) mod 256);       -- low byte
        cpu_write(16#09#, (2 * i + 1) mod 256);   -- high byte
      end loop;
      -- wait for the frame to drain
      for i in 0 to 999 loop
        wait until rising_edge(clk);
      end loop;
      assert tx_cap_cnt = 64
        report "T1: WRONG BYTE COUNT " & integer'image(tx_cap_cnt) & " (expected 64)"
          severity failure;
      for i in 0 to 63 loop
        assert tx_cap(i) = std_logic_vector(to_unsigned(i mod 256, 8))
          report "T1 MISMATCH at byte " & integer'image(i) &
                 ": got " & integer'image(to_integer(unsigned(tx_cap(i)))) &
                 " expected " & integer'image(i mod 256)
            severity failure;
      end loop;

    ----------------------------------------------------------------
    elsif G_TEST = "T2" then
      -- Receive a normal frame and read it back exactly like cs8900a.asm 'poll'
      report "=== T2: Rx 100-byte frame, cc65 driver access order ===";
      rx_frame(100, true, 3);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      -- poll: PACKETPP=$0124, read ppdata+1 ($DE05), test bit 0
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      assert d(0) = '1'
        report "T2: RxOK not set!"
          severity failure;
      -- discard RxStatus: ldx rxtxreg+1 ; lda rxtxreg
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      -- length: ldx rxtxreg+1 ; lda rxtxreg
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      assert len_v = 100
        report "T2: WRONG LENGTH"
          severity failure;
      -- payload loop: lda rxtxreg ; lda rxtxreg+1
      cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi);
      assert unsigned(dhi) = X"FF" and unsigned(dlo) = X"FF"
        report "Incorrect two first bytes"
          severity failure;
      for i in 1 to 49 loop
        cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi);
        exp_v := ((2 * i) * 7 + 3) mod 256;
        assert to_integer(unsigned(dlo)) = exp_v
          report "T2 payload MISMATCH at byte " & integer'image(2 * i) &
                 ": got " & integer'image(to_integer(unsigned(dlo))) &
                 " expected " & integer'image(exp_v)
            severity failure;
        exp_v := ((2 * i + 1) * 7 + 3) mod 256;
        assert to_integer(unsigned(dhi)) = exp_v
          report "T2 payload MISMATCH at byte " & integer'image(2 * i + 1) &
                 ": got " & integer'image(to_integer(unsigned(dhi))) &
                 " expected " & integer'image(exp_v)
            severity failure;
      end loop;
      -- after draining, RxEvent must be clear again
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      assert d(0) = '0'
        report "T2: RxEvent hi after drain = " & integer'image(to_integer(unsigned(d))) &
               " (bit0 should be 0)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "T3" then
      -- Oversized frame: does it wrap and corrupt the PacketPage registers?
      report "=== T3: oversized Rx frame (3500 bytes) ===";
      set_pp(16#0000#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = x"63" and dlo = x"0E"
        report "T3: EISA id BEFORE = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) & " (expect 99:14 = $630E)"
          severity failure;
      rx_frame(3500, true, 5);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0000#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      report "T3: EISA id AFTER  = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo))) & " (expect 99:14 = $630E)";
      assert dhi = x"63" and dlo = x"0E"
        report "T3: PACKETPAGE REGISTER AREA CORRUPTED BY OVERSIZED FRAME"
          severity failure;
      set_pp(16#0138#);
      cpu_read(16#05#, dhi);
      report "T3: BusST hi after = " & integer'image(to_integer(unsigned(dhi)));
      -- Does a module reset (= toggling the RR-Net menu item off/on) heal it?
      rst_pulse <= true;
      for i in 0 to 99 loop
        wait until rising_edge(clk);
      end loop;
      rst_pulse <= false;
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0000#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = x"63" and dlo = x"0E"
        report "T3: EISA id after RESET = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) & " (expect 99:14 = $630E if reset heals it)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "T4" then
      -- Frame whose 'last' beat never arrives (upstream FIFO overrun drop),
      -- followed by a normal frame.
      report "=== T4: truncated frame (no last), then a normal frame ===";
      rx_frame(60, false, 1);           -- no last marker
      for i in 0 to 50 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "T4: RxEvent hi after truncated frame = " & integer'image(to_integer(unsigned(d))) &
             " (bit0 = frame-ready)";
      rx_frame(80, true, 9);            -- normal frame
      for i in 0 to 50 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "T4: RxEvent hi after 2nd frame = " & integer'image(to_integer(unsigned(d)));
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "T4: reported RxLength = " & integer'image(len_v) &
             " (80 = frames kept separate, 140 = frames MERGED)";

    ----------------------------------------------------------------
    elsif G_TEST = "T5" then
      -- skipframe: cs8900a.asm sets bit 6 of RxCFG ($0102) to discard a frame.
      report "=== T5: skipframe (RxCFG $0102 bit 6) ===";
      rx_frame(100, true, 3);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      assert d(0) = '1'
        report "T5: RxEvent hi before skip = " & integer'image(to_integer(unsigned(d)))
          severity failure;
      -- skipframe: PACKETPP=$0102 ; PPDATA = PPDATA | $40  (low byte only)
      set_pp(16#0102#);
      cpu_read(16#04#, d);
      cpu_write(16#04#, to_integer(unsigned(d or x"40")));
      for i in 0 to 40 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      assert d(0) = '0'
        report "T5: skipframe DID NOT release the Rx buffer"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "T6" then
      -- Read the Rx header low-byte-first (a legal alternative driver order).
      report "=== T6: header read low-byte-first ===";
      rx_frame(100, true, 3);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      cpu_read(16#08#, dlo);   -- RxStatus lo
      cpu_read(16#09#, dhi);   -- RxStatus hi
      report "T6: RxStatus read lo-first = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo))) & " (expect 1:0 -> RxOK bit 8)";
      cpu_read(16#08#, dlo);   -- RxLength lo
      cpu_read(16#09#, dhi);   -- RxLength hi
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      assert len_v = 100
        report "T6: RxLength read lo-first = " & integer'image(len_v) & " (expect 100)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "T7" then
      -- Two frames back to back: is the second one dropped, and does the
      -- receiver re-arm cleanly afterwards?
      report "=== T7: two frames, single buffer ===";
      rx_frame(60, true, 1);
      for i in 0 to 10 loop
        wait until rising_edge(clk);
      end loop;
      report "T7: eth_rx_ready while frame pending = " & std_logic'image(eth_rx_ready);
      -- drain frame 1
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      report "T7: frame 1 length = " & integer'image(len_v);
      for i in 0 to 29 loop
        cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi);
      end loop;
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      report "T7: RxEvent hi after draining frame 1 = " & integer'image(to_integer(unsigned(d)));
      report "T7: eth_rx_ready after drain = " & std_logic'image(eth_rx_ready);
      rx_frame(70, true, 2);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      set_pp(16#0124#);
      cpu_read(16#05#, d);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi); cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      assert len_v = 70
        report "T7: frame 2 length = " & integer'image(len_v) & " (expect 70)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "T8" then
      -- Short frame: is the minimum-length padding taken from stale Tx buffer
      -- contents (Etherleak) ?
      report "=== T8: short Tx frame padding ===";
      -- First send a 64-byte frame with a recognisable pattern
      cpu_write(16#0C#, 16#C9#);
      cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 64);
      cpu_write(16#0F#, 0);
      for i in 0 to 31 loop
        cpu_write(16#08#, 16#AA#);
        cpu_write(16#09#, 16#55#);
      end loop;
      for i in 0 to 999 loop
        wait until rising_edge(clk);
      end loop;
      report "T8: first frame sent, " & integer'image(tx_cap_cnt) & " bytes";
      -- Now send a 20-byte frame; the chip pads to 60
      cpu_write(16#0C#, 16#C9#);
      cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 20);
      cpu_write(16#0F#, 0);
      for i in 0 to 9 loop
        cpu_write(16#08#, 16#11#);
        cpu_write(16#09#, 16#22#);
      end loop;
      for i in 0 to 999 loop
        wait until rising_edge(clk);
      end loop;
      report "T8: total captured " & integer'image(tx_cap_cnt) &
             " bytes in " & integer'image(tx_frames) & " frames (64 + 60 = 124 expected)";
      report "T8: padding bytes 84..91 of the capture = " &
             integer'image(to_integer(unsigned(tx_cap(84)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(85)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(86)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(87)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(88)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(89)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(90)))) & " " &
             integer'image(to_integer(unsigned(tx_cap(91)))) &
             "  (170/85 = leaked previous frame, 0 = zero padding)";

    ----------------------------------------------------------------
    elsif G_TEST = "T9" then
      -- Oversized TRANSMIT: TxLength = 2000 (> the 1536-byte Tx buffer).
      report "=== T9: oversized Tx frame (TxLength = 2000) ===";
      set_pp(16#0000#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      report "T9: EISA id BEFORE = " & integer'image(to_integer(unsigned(dhi))) & ":" &
             integer'image(to_integer(unsigned(dlo)));
      cpu_write(16#0C#, 16#C9#);
      cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 2000 mod 256);
      cpu_write(16#0F#, 2000 / 256);
      for i in 0 to 999 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      for i in 0 to 999 loop
        wait until rising_edge(clk);
      end loop;
      report "T9: bytes actually transmitted = " & integer'image(tx_cap_cnt) &
             " in " & integer'image(tx_frames) & " frame(s)  (0 = transmitter wedged)";
      set_pp(16#0000#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = x"63" and dlo = x"0E"
        report "T9: PACKETPAGE REGISTER AREA CORRUPTED BY OVERSIZED TX FRAME"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "TA" then
      -- PacketPage write WITH AutoIncrement (pointer bit 15 = 1).
      -- Write $1234 to PP $0200 and $5678 to PP $0202 using autoincrement,
      -- then read both words back without autoincrement.
      report "=== TA: PacketPage write with AutoIncrement ===";
      cpu_write(16#02#, 16#00#);          -- ptr lo  = $00
      cpu_write(16#03#, 16#82#);          -- ptr hi  = $82 -> $0200 + autoincrement
      cpu_write(16#04#, 16#34#);          -- low  byte of word 1
      cpu_write(16#05#, 16#12#);          -- high byte of word 1 (+ autoincrement)
      cpu_write(16#04#, 16#78#);          -- low  byte of word 2
      cpu_write(16#05#, 16#56#);          -- high byte of word 2 (+ autoincrement)
      set_pp(16#0200#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = X"12" and dlo = X"34"
        report "TA: PP $0200 = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) & "  (expect 18:52 = $1234)"
          severity failure;
      set_pp(16#0202#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = X"56" and dlo = X"78"
        report "TA: PP $0202 = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) & "  (expect 86:120 = $5678)"
          severity failure;
      set_pp(16#0204#);
      cpu_read(16#04#, dlo);
      cpu_read(16#05#, dhi);
      assert dhi = X"00" and dlo = X"00"
        report "TA: PP $0204 = " & integer'image(to_integer(unsigned(dhi))) & ":" &
               integer'image(to_integer(unsigned(dlo))) & "  (expect 0:0 - anything else = high bytes landed too far)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "TB" then
      -- A driver that programs TxCMD/TxLength through the PacketPage window
      -- ($0144/$0146) instead of the $DE0C/$DE0E shortcut leaves reg_tx_length
      -- at its reset value of 0. What happens on the first data word?
      report "=== TB: Tx with TxLength never written through $DE0E ===";
      set_pp(16#0144#);                     -- TxCMD via PacketPage
      cpu_write(16#04#, 16#C9#);
      cpu_write(16#05#, 16#00#);
      set_pp(16#0146#);                     -- TxLength via PacketPage
      cpu_write(16#04#, 100);
      cpu_write(16#05#, 0);
      -- now stream the frame through the RxTx window
      for i in 0 to 49 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      for i in 0 to 999 loop
        wait until rising_edge(clk);
      end loop;
      report "TB: transmitted " & integer'image(tx_cap_cnt) & " bytes in " &
             integer'image(tx_frames) & " frame(s)  (expect 0 frames; 1+ = spurious transmit)";

    ----------------------------------------------------------------
    elsif G_TEST = "TC" then
      -- Does a transmit that starts during the 2-cycle RX_HEADER_ST window
      -- lose the RxStatus / RxLength writes? Stage a Tx frame, hold back its
      -- final trigger write, stream 39 of 40 Rx bytes, then assert the Tx
      -- trigger and deliver the 40th Rx byte G_DELAY cycles into that window.
      cpu_write(16#0C#, 16#C9#);
      cpu_write(16#0D#, 16#00#);
      cpu_write(16#0E#, 64);
      cpu_write(16#0F#, 0);
      for i in 0 to 30 loop
        cpu_write(16#08#, (2 * i) mod 256);
        cpu_write(16#09#, (2 * i + 1) mod 256);
      end loop;
      cpu_write(16#08#, 16#FE#);
      -- stream 39 bytes, no end-of-frame marker yet
      for i in 0 to 38 loop
        eth_rx_data  <= std_logic_vector(to_unsigned((i * 7 + 3) mod 256, 8));
        eth_rx_last  <= '0';
        eth_rx_ok    <= '1';
        eth_rx_valid <= '1';
        loop
          wait until rising_edge(clk);
          exit when eth_rx_ready = '1';
        end loop;
      end loop;
      eth_rx_valid <= '0';
      wait until rising_edge(clk);
      -- assert the Tx trigger write
      addr    <= x"09";
      wr_data <= x"FF";
      we      <= '1';
      cs      <= '1';
      -- deliver the last Rx byte G_DELAY cycles into the CS window
      for i in 1 to G_DELAY loop
        wait until rising_edge(clk);
      end loop;
      eth_rx_data  <= std_logic_vector(to_unsigned((39 * 7 + 3) mod 256, 8));
      eth_rx_last  <= '1';
      eth_rx_ok    <= '1';
      eth_rx_valid <= '1';
      loop
        wait until rising_edge(clk);
        exit when eth_rx_ready = '1';
      end loop;
      eth_rx_valid <= '0';
      eth_rx_last  <= '0';
      for i in 0 to 30 loop
        wait until rising_edge(clk);
      end loop;
      cs <= '0';
      we <= '0';
      for i in 0 to 3000 loop
        wait until rising_edge(clk);
      end loop;
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      cpu_read(16#09#, dhi);
      cpu_read(16#08#, dlo);
      len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
      assert len_v = 40
        report "TC delay=" & integer'image(G_DELAY) & ": RxLength = " &
               integer'image(len_v) & " (expect 40; 0 or stale = header write lost)"
          severity failure;

    ----------------------------------------------------------------
    elsif G_TEST = "TD" then
      -- After a skipframe that did nothing: does the driver recover, and how?
      -- Emulate cs8900a.asm poll() repeatedly on a 400-byte frame whose
      -- reported length the driver keeps rejecting (bufsize < cnt).
      report "=== TD: recovery after a no-op skipframe ===";
      rx_frame(400, true, 3);
      for i in 0 to 20 loop
        wait until rising_edge(clk);
      end loop;
      bad_v := 0;                        -- poll counter
      exp_v := 0;                        -- number of polls that saw a frame
      for p in 1 to 220 loop
        set_pp(16#0124#);
        cpu_read(16#05#, d);
        exit when d(0) = '0';
        exp_v := exp_v + 1;
        -- read the two header words the way the driver does
        cpu_read(16#09#, dhi);
        cpu_read(16#08#, dlo);
        cpu_read(16#09#, dhi);
        cpu_read(16#08#, dlo);
        len_v := to_integer(unsigned(dhi)) * 256 + to_integer(unsigned(dlo));
        if p <= 4 or p mod 40 = 0 then
          report "TD poll " & integer'image(p) & ": reported length = " & integer'image(len_v);
        end if;
        -- driver decides bufsize < cnt and calls skipframe
        set_pp(16#0102#);
        cpu_read(16#04#, d);
        cpu_write(16#04#, to_integer(unsigned(d or x"40")));
        bad_v := p;
      end loop;
      report "TD: RxEvent finally cleared after " & integer'image(bad_v) &
             " polls (" & integer'image(exp_v) & " of them saw a frame)";

    end if;

    report "=== TEST " & G_TEST & " COMPLETE ===";
    test_done <= true;
    wait for 100 ns;
    std.env.stop;
    wait;
  end process main_proc;

end architecture tb;

