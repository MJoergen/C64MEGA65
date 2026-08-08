-- ----------------------------------------------------------
-- Description: Simulates a CS8900A ethernet chip
--
-- Datasheet: https://www.mi.fu-berlin.de/inf/groups/ag-tech/projects/ScatterWeb/moduleComponents/EWS_CS8900.pdf
--
-- Only I/O Space Operation is supported, see section 4.10 in datasheet.
--
-- Register map (Little-Endian format):
-- DE02 - DE03 : PacketPage Pointer (byte address)
-- DE04 - DE05 : PacketPage Data (bits 15-0)
-- DE06 - DE07 : PacketPage Data (bits 31-16). NOT USED
-- DE08 - DE09 : Receive/Transmit Data (bits 15-0)
-- DE0A - DE0B : Receive/Transmit Data (bits 31-16). NOT USED
-- DE0C - DE0D : Transmit Command
-- DE0E - DE0F : Transmit Length
--
-- PacketPage Address Map (byte address):
-- 0000 - 0045 : Bus Interface Registers
-- 0100 - 013F : Status and Control Registers
-- 0140 - 014F : Initiate Transmit Registers
-- 0150 - 015D : Address Filter Registers
-- 0400        : Receive Frame Location
--                 $0400-$0401 : RxStatus  (bit 8 = RxOK, live-overlaid)
--                 $0402-$0403 : RxLength  (bytes, no FCS)
--                 $0404+      : Payload
-- 0A00        : Transmit Frame Location
--
-- Bus Status ($0138), Rdy4TxNOW bit (bit 8): live-overlaid from tx_state
-- on CPU reads of that PP offset. RAM contents at $0138 are never rewritten;
-- the RAM value provides the static (non-Rdy4TxNOW) bits.
--
-- RxEvent ($0124), RxOK bit (bit 8): live-overlaid from rx_state on CPU
-- reads of that PP offset. Same convention as Rdy4TxNOW.
--
-- Rx frame consumption: the receiver is re-armed when ANY of
--   * the CPU auto-increments reg_pp_ptr past the end of the frame via
--     the PP data window ($DE04/05), OR
--   * the CPU reads past the end of the frame via the RxTx data window
--     ($DE08/09), OR
--   * the CPU explicitly writes to RxEvent ($0124) to clear it.
--
-- RxTx data window ($DE08/09) read path: uses port B of the PacketPage
-- RAM, addressed by an independent internal pointer reg_rx_ptr (starting
-- at $0400 for each frame). $DE08 returns the low byte of the current
-- word, $DE09 returns the high byte AND advances reg_rx_ptr by 2 (per
-- CS8900A word-oriented I/O). The internal pointer is reset to $0400
-- automatically after frame consumption.
--
-- Port-B arbitration: The Rx-write, Tx-read, and Rx-window-read paths
-- all share port B of the PacketPage RAM. They are naturally mutually
-- exclusive under normal driver flow:
--   * Rx-write is only active while rx_state = RX_DATA_ST/RX_HEADER_ST.
--   * Tx-read is only active while tx_state = TX_BUSY_ST.
--   * Rx-window-read is only meaningful while rx_state = RX_READY_ST.
-- Drivers must not initiate a Tx transaction while draining an Rx frame
-- via $DE08/09, or the Rx read will observe Tx-buffer data. The FSM
-- warns on this via a runtime assertion.
-- ----------------------------------------------------------


library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity rrnet is
  generic (
    G_DEBUG : boolean := false
  );
  port (
    -- CPU interface @ 32 MHz.
    -- It is assumed that cs_i is deasserted between each single transaction.
    -- It is further assumed that cs_i is asserted for at least two consecutive clock cycles,
    -- and that addr_i, we_i, and wr_data_i do not change while cs_i is asserted.
    clk_i          : in    std_logic;
    rst_i          : in    std_logic;
    cs_i           : in    std_logic;                    -- Chip Select. Connect to IO1 ($DExx)
    addr_i         : in    std_logic_vector(7 downto 0);
    we_i           : in    std_logic;
    wr_data_i      : in    std_logic_vector(7 downto 0);
    rd_data_o      : out   std_logic_vector(7 downto 0);

    -- Ethernet interface (byte streaming, same clock domain as CPU interface)
    -- Bytes are transferred at the frequency of 100 / 8 = 12.5 Mbytes per second.
    --
    -- Rx contract : * eth_rx_valid_i pulses high for 1 clock cycle per byte (byte strobe).
    --               * eth_rx_last_i marks the last byte of a frame (client-visible payload;
    --                 the 4-byte FCS is already stripped).
    --               * eth_rx_ok_i is valid only on the beat with rx_last_i = '1'; it is
    --                 '1' if the frame passed CRC and had no PHY error, '0' otherwise.
    --               * There is NO back-pressure on the Rx side (no eth_rx_ready_o). The
    --                 client must consume every valid beat; frames arriving while the
    --                 emulator's single Rx buffer is unavailable are silently dropped.
    --
    -- Tx contract : * Standard valid/ready handshake, sampled once per byte-time on the
    --                 cycle eth_tx_ready_i = '1'. The client must present each new byte on
    --                 that cycle or the frame is aborted.
    --               * eth_tx_valid_o = '0' on a byte boundary during payload aborts the
    --                 frame (no Tx buffering); the MAC then holds the required IFG
    --                 before accepting a new frame.
    --               * The FCS is automatically computed and appended before sending on
    --                 the wire.
    --
    -- Assumption: eth_tx_ready_i pulses at most once every 2 clock cycles,
    -- which allows the 2-cycle port B RAM read latency to be absorbed
    -- without stalling. With a 32 MHz clock speed, tx_ready_i pulses every
    -- 32 / 12.5 = 2.56 clock cycles, so this is safe with margin.
    eth_rx_ready_o : out   std_logic;                    -- One-cycle strobe per received byte
    eth_rx_valid_i : in    std_logic;                    -- One-cycle strobe per received byte
    eth_rx_last_i  : in    std_logic;                    -- Last byte of frame
    eth_rx_ok_i    : in    std_logic;                    -- Only meaningful when rx_last_i = '1'
    eth_rx_data_i  : in    std_logic_vector(7 downto 0); -- Received byte
    eth_tx_ready_i : in    std_logic;                    -- Pulses '1' on the byte-boundary cycle
    eth_tx_valid_o : out   std_logic;                    -- Client presents a byte
    eth_tx_last_o  : out   std_logic;                    -- Client marks the last byte
    eth_tx_data_o  : out   std_logic_vector(7 downto 0)  -- Byte to transmit
  );
end entity rrnet;

architecture rtl of rrnet is

  ----------------------------------------------------------
  -- CPU-side I/O register offsets (relative to $DE00)
  ----------------------------------------------------------
  constant C_PP_PTR     : unsigned(7 downto 0)                         := X"02";
  constant C_PP_DATA_0  : unsigned(7 downto 0)                         := X"04";
  constant C_PP_DATA_1  : unsigned(7 downto 0)                         := X"06"; -- Not used
  constant C_RXTX_REG_0 : unsigned(7 downto 0)                         := X"08";
  constant C_RXTX_REG_1 : unsigned(7 downto 0)                         := X"0A"; -- Not used
  constant C_TX_CMD     : unsigned(7 downto 0)                         := X"0C";
  constant C_TX_LENGTH  : unsigned(7 downto 0)                         := X"0E";

  ----------------------------------------------------------
  -- PacketPage buffer locations (byte addresses in RAM)
  ----------------------------------------------------------
  constant C_RX_BUF_START : unsigned(11 downto 0)                      := X"400";
  constant C_TX_BUF_START : unsigned(11 downto 0)                      := X"A00";

  -- PP word addresses (12-bit RAM index, i.e. byte offset / 2) for the
  -- registers whose live-status bits we overlay on CPU reads.
  constant C_PP_BUS_ST_ADDR   : unsigned(11 downto 1)                  := to_unsigned(16#138# / 2, 11);
  constant C_PP_LINE_ST_ADDR  : unsigned(11 downto 1)                  := to_unsigned(16#134# / 2, 11);
  constant C_PP_RX_EVENT_ADDR : unsigned(11 downto 1)                  := to_unsigned(16#124# / 2, 11);
  constant C_PP_SELF_CTL_ADDR : unsigned(11 downto 1)                  := to_unsigned(16#114# / 2, 11);

  ----------------------------------------------------------
  -- CPU-visible registers
  ----------------------------------------------------------

  -- reg_pp_ptr(15) is the AutoIncrement control bit, not an address bit.
  -- Only reg_pp_ptr(11 downto 0) is passed to the RAM.
  signal   reg_pp_ptr    : unsigned(15 downto 0)                       := (others => '0');
  signal   reg_tx_cmd    : unsigned(15 downto 0)                       := (others => '0');
  signal   reg_tx_length : unsigned(15 downto 0)                       := (others => '0');
  signal   reg_tx_ptr    : unsigned(11 downto 0)                       := (others => '0');
  signal   reg_tx_start  : std_logic                                   := '0';

  -- Independent internal Rx read pointer used by the $DE08/09 window.
  -- Starts at $0400 (RxStatus low byte) at the beginning of each frame,
  -- advances by 2 on each $DE09 (high byte) read. Separate from
  -- reg_pp_ptr so drivers can interleave PP-window and RxTx-window
  -- accesses without interference.
  signal   reg_rx_ptr : unsigned(11 downto 0)                          := (others => '0');

  ----------------------------------------------------------
  -- Port A (CPU-side) RAM signals
  ----------------------------------------------------------
  signal   pp_we    : std_logic_vector( 1 downto 0)                    := (others => '0');
  signal   pp_wrdat : std_logic_vector(15 downto 0)                    := (others => '0');
  signal   pp_rddat : std_logic_vector(15 downto 0)                    := (others => '0');

  ----------------------------------------------------------
  -- Port B (packet-side) RAM signals. Muxed between Tx-read
  -- (driven by tx_proc), Rx-write (driven by rx_proc), and
  -- Rx-window-read (driven by fsm_proc for $DE08/09 accesses).
  ----------------------------------------------------------
  signal   rxtx_addr  : unsigned(11 downto 0)                          := (others => '0');
  signal   rxtx_we    : std_logic_vector( 1 downto 0)                  := (others => '0');
  signal   rxtx_wrdat : std_logic_vector(15 downto 0)                  := (others => '0');
  signal   rxtx_rddat : std_logic_vector(15 downto 0)                  := (others => '0');

  -- Per-process port-B drivers; multiplexed to rxtx_* below.
  signal   tx_addr  : unsigned(11 downto 0)                            := (others => '0');
  signal   rx_addr  : unsigned(11 downto 0)                            := (others => '0');
  signal   rx_we    : std_logic_vector( 1 downto 0)                    := (others => '0');
  signal   rx_wrdat : std_logic_vector(15 downto 0)                    := (others => '0');

  -- cs_d is used to detect rising edge of the Chip Select.
  signal   cs_d  : std_logic                                           := '0';
  signal   cs_dd : std_logic                                           := '0';

  ----------------------------------------------------------
  -- PacketPage RAM initialisation
  ----------------------------------------------------------

  -- This holds the entire 2k words of PacketPage memory.
  type     word_array_type is array (natural range <>) of std_logic_vector(15 downto 0);

  pure function get_packet_page_init return std_logic_vector is
    variable ram_v        : word_array_type(0 to 2047)              := (others => (others => '0'));
    variable ret_v        : std_logic_vector(4096 * 8 - 1 downto 0) := (others => '0');
    -- PacketPage memory map
    constant C_PP_ISA_ID  : natural                                 := 16#000#;
    constant C_PP_PROD_ID : natural                                 := 16#002#;
    constant C_PP_BUS_ST  : natural                                 := 16#138#;
  begin
    -- Note: Addresses are divided by two, to convert from byte to word addressing.
    -- EISA registration number for Crystal Semiconductor
    ram_v(C_PP_ISA_ID / 2)  := X"630E";
    -- Product ID and Revision number
    ram_v(C_PP_PROD_ID / 2) := X"0700";
    -- Bus Status (set 'Rdy4TxNOW').
    ram_v(C_PP_BUS_ST / 2)  := X"0118";

    for i in 0 to 2047 loop
      ret_v(8 * i + 7 downto 8 * i)                        := ram_v(i)(7 downto 0);
      ret_v(8 * i + 7 + 2048 * 8 downto 8 * i + 2048 * 8 ) := ram_v(i)(15 downto 8);
    end loop;

    return ret_v;
  end function get_packet_page_init;

  -- PacketPage RAM initialisation vector, split into MSB and LSB
  constant C_PP_RAM_INIT_LSB : std_logic_vector(2048 * 8 - 1 downto 0) := get_packet_page_init(2048 * 8 - 1 downto 0);
  constant C_PP_RAM_INIT_MSB : std_logic_vector(2048 * 8 - 1 downto 0) := get_packet_page_init(4096 * 8 - 1 downto 2048 * 8);

  ----------------------------------------------------------
  -- Tx path state
  ----------------------------------------------------------
  type     tx_state_type is (TX_IDLE_ST, TX_BUSY_ST);
  signal   tx_state : tx_state_type                                    := TX_IDLE_ST;

  -- Live "buffer ready" flag exposed to software as the Rdy4TxNOW bit of
  -- the CS8900A Bus Status register at PP offset $0138 (bit 8).
  signal   rdy_4_tx_now : std_logic;

  ----------------------------------------------------------
  -- Rx path state
  ----------------------------------------------------------

  -- Rx FSM:
  --   RX_IDLE_ST    : waiting for a frame; incoming bytes accepted only
  --                   if rx_accept = '1'.
  --   RX_DATA_ST    : streaming payload bytes into $0404+.
  --   RX_DROP_ST    : discarding remainder of long frame.
  --   RX_HEADER_ST  : writing RxStatus at $0400 and RxLength at $0402.
  --                   Two clock cycles (one word per cycle).
  --   RX_READY_ST   : frame available; RxOK visible via RxEvent overlay.
  --                   Waits until rx_frame_consumed pulses.
  type     rx_state_type is (RX_IDLE_ST, RX_DATA_ST, RX_DROP_ST, RX_HEADER_ST, RX_READY_ST);
  signal   rx_state : rx_state_type                                    := RX_IDLE_ST;

  -- Byte-granular write pointer into the RAM.
  signal   rx_wr_addr : unsigned(11 downto 0)                          := (others => '0');

  -- Payload bytes captured so far (also reused as a 1-bit sub-state in
  -- RX_HEADER_ST via its LSB).
  signal   rx_byte_cnt : unsigned(15 downto 0)                         := (others => '0');

  -- Frame length (payload bytes, no FCS) and OK flag, latched at end-of-frame.
  signal   rx_length : unsigned(15 downto 0)                           := (others => '0');
  signal   rx_ok     : std_logic                                       := '0';

  -- Live "frame available" flag exposed to software as the RxOK bit of
  -- the CS8900A RxEvent register at PP offset $0124 (bit 8).
  signal   rx_frame_ready : std_logic;

  -- Rx acceptance gate: '1' when the receiver may write a new byte into
  -- the RAM (Tx not using port B, and no unread frame occupying the buffer).
  signal   rx_accept : std_logic;

  -- One-cycle strobe that returns the Rx FSM from RX_READY_ST to RX_IDLE_ST.
  -- Asserted by fsm_proc on any of the three consumption paths.
  signal   rx_frame_consumed : std_logic                               := '0';

begin

  ----------------------------------------------------------
  -- Live status flags (concurrent)
  ----------------------------------------------------------

  rdy_4_tx_now   <= '1' when tx_state = TX_IDLE_ST else
                    '0';
  rx_frame_ready <= '1' when rx_state = RX_READY_ST else
                    '0';

  -- Rx accepts new bytes only when the Tx path is idle;
  -- the gate exists mainly to arbitrate
  -- port B and to enforce the single-buffer contract from RX_IDLE_ST.
  rx_accept      <= '1' when tx_state = TX_IDLE_ST else
                    '0';

  ----------------------------------------------------------
  -- Port-B arbitration
  --
  -- Three users, mutually exclusive under normal driver flow:
  --   * Tx-read : driven by tx_proc (tx_addr); active when
  --               tx_state = TX_BUSY_ST or reg_tx_start = '1'.
  --   * Rx-write: driven by rx_proc (rx_addr / _wrdat / _we);
  --               active when tx_state = TX_IDLE_ST (and Rx has a frame
  --               in progress).
  --   * Rx-read : driven by fsm_proc via reg_rx_ptr; active while a
  --               CPU access to $DE08/09 is being processed and
  --               rx_state = RX_READY_ST.
  --
  -- The mux below prioritises Tx-read whenever Tx is either running
  -- or about to start (reg_tx_start), then Rx-read when the CPU is
  -- accessing the RxTx window on a ready frame, and otherwise gives
  -- port B to the Rx-write path.
  ----------------------------------------------------------

  rxtx_addr      <= tx_addr + 1 when tx_state = TX_BUSY_ST and eth_tx_ready_i = '1' and eth_tx_valid_o = '1' else
                    tx_addr when tx_state = TX_BUSY_ST or reg_tx_start = '1' else
                    reg_rx_ptr(11 downto 0) when rx_state = RX_READY_ST and cs_i = '1' and we_i = '0' and
                                                 (unsigned(addr_i) = C_RXTX_REG_0 or
                      unsigned(addr_i) = C_RXTX_REG_0 + 1) else
                    rx_addr;
  rxtx_we        <= rx_we when tx_state = TX_IDLE_ST else
                    (others => '0');
  rxtx_wrdat     <= rx_wrdat;

  ----------------------------------------------------------
  -- Tx process
  ----------------------------------------------------------

  tx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if eth_tx_ready_i = '1' then
        eth_tx_valid_o <= '0';
        eth_tx_last_o  <= '0';
      end if;

      case tx_state is

        when TX_IDLE_ST =>
          if reg_tx_start = '1' then
            tx_state <= TX_BUSY_ST;
          end if;

        when TX_BUSY_ST =>
          if eth_tx_ready_i = '1' then
            if tx_addr(0) = '0' then
              eth_tx_data_o <= rxtx_rddat(7 downto 0);
            else
              eth_tx_data_o <= rxtx_rddat(15 downto 8);
            end if;
            -- Undersize frames must be padded with zeros.
            -- Fixes issue #252, item R6.
            if tx_addr >= reg_tx_ptr then
              eth_tx_data_o <= (others => '0');
            end if;
            eth_tx_valid_o <= '1';
            tx_addr        <= tx_addr + 1;
            if tx_addr + 1 >= C_TX_BUF_START + reg_tx_length then
              tx_addr       <= C_TX_BUF_START;
              eth_tx_last_o <= '1';
              tx_state      <= TX_IDLE_ST;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        tx_addr        <= C_TX_BUF_START;
        eth_tx_valid_o <= '0';
        eth_tx_last_o  <= '0';
        eth_tx_data_o  <= (others => '0');
        tx_state       <= TX_IDLE_ST;
      end if;
    end if;
  end process tx_proc;


  ----------------------------------------------------------
  -- Rx process
  --
  -- Streams incoming bytes into the RAM starting at $0404 (leaving room
  -- for the 4-byte RxStatus/RxLength header at $0400..$0403). Once the
  -- last byte has been captured, writes the header in two cycles and
  -- transitions to RX_READY_ST. Held there until rx_frame_consumed
  -- pulses, at which point the receiver re-arms.
  ----------------------------------------------------------

  eth_rx_ready_o <= rx_accept when rx_state = RX_IDLE_ST or
                                   rx_state = RX_DATA_ST or
                                   rx_state = RX_DROP_ST else
                    '0';

  rx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      -- Default: no port-B write this cycle.
      rx_we <= (others => '0');

      case rx_state is

        when RX_IDLE_ST =>
          -- Point at the first payload word ($0404) for the next arrival.
          rx_wr_addr  <= C_RX_BUF_START + 4;
          rx_byte_cnt <= (others => '0');
          rx_addr     <= C_RX_BUF_START + 4;

          if eth_rx_valid_i = '1' and rx_accept = '1' then
            -- First byte of a new frame lands in the low half of the word
            -- at $0404 (byte address bit 0 = '0').
            rx_addr     <= C_RX_BUF_START + 4;
            rx_wrdat    <= eth_rx_data_i & eth_rx_data_i;
            rx_we       <= "01";
            rx_wr_addr  <= C_RX_BUF_START + 5;
            rx_byte_cnt <= to_unsigned(1, rx_byte_cnt'length);
            rx_state    <= RX_DATA_ST;

            -- Pathological single-byte frame: end-of-frame on the very
            -- first byte. Latch length and fall through to header write.
            if eth_rx_last_i = '1' then
              rx_length   <= to_unsigned(1, rx_length'length);
              rx_ok       <= eth_rx_ok_i;
              rx_state    <= RX_HEADER_ST;
              rx_byte_cnt <= (others => '0');                       -- reused as header sub-state
            end if;
          end if;

        when RX_DATA_ST =>
          if eth_rx_valid_i = '1' and rx_accept = '1' then
            -- Byte-lane selection follows the LSB of the write address,
            -- same convention used on the Tx read side.
            rx_addr  <= rx_wr_addr;
            rx_wrdat <= eth_rx_data_i & eth_rx_data_i;
            if rx_wr_addr(0) = '0' then
              rx_we <= "01";
            else
              rx_we <= "10";
            end if;

            rx_wr_addr  <= rx_wr_addr + 1;
            rx_byte_cnt <= rx_byte_cnt + 1;

            if eth_rx_last_i = '1' then
              rx_length   <= rx_byte_cnt + 1;
              rx_ok       <= eth_rx_ok_i;
              rx_state    <= RX_HEADER_ST;
              rx_byte_cnt <= (others => '0');                       -- reused as header sub-state
            elsif rx_wr_addr + 2 >= C_TX_BUF_START then
              -- Frame is not finished yet, and next byte will spill out of the
              -- Rx buffer. We drop the remainder of this frame.
              rx_state <= RX_DROP_ST;
            end if;
          end if;

        when RX_DROP_ST =>
          -- Wait until end of frame, then return to RX_IDLE_ST.
          if eth_rx_valid_i = '1' and eth_rx_last_i = '1' then
            rx_state <= RX_IDLE_ST;
          end if;

        when RX_HEADER_ST =>
          -- Two clocks: first write RxStatus at $0400, then RxLength at $0402.
          -- rx_byte_cnt(0) is used as a 1-bit sub-state.
          if rx_byte_cnt(0) = '0' then
            rx_addr        <= C_RX_BUF_START;                       -- $0400
            -- RxStatus: bit 8 = RxOK. All other bits zero for now
            -- (extend here to expose more per-frame status bits).
            rx_wrdat       <= "0000000" & rx_ok & X"00";
            rx_we          <= "11";
            rx_byte_cnt(0) <= '1';
          else
            rx_addr  <= C_RX_BUF_START + 2;                         -- $0402
            rx_wrdat <= std_logic_vector(rx_length);
            rx_we    <= "11";
            rx_state <= RX_READY_ST;
          end if;

        when RX_READY_ST =>
          -- Held here until the CPU consumes the frame (via autoincrement
          -- PP-window reads, RxTx-window reads, or explicit RxEvent write).
          if rx_frame_consumed = '1' then
            rx_state <= RX_IDLE_ST;
          end if;

      end case;

      if rst_i = '1' then
        rx_state    <= RX_IDLE_ST;
        rx_wr_addr  <= C_RX_BUF_START + 4;
        rx_byte_cnt <= (others => '0');
        rx_length   <= (others => '0');
        rx_ok       <= '0';
        rx_we       <= (others => '0');
      end if;
    end if;
  end process rx_proc;


  ----------------------------------------------------------
  -- PacketPage RAM (4 kB, dual-port, single-clock)
  ----------------------------------------------------------
  -- Addresses are in units of bytes, and are assumed to be word-aligned,
  -- i.e. bit 0 of the address must always be zero, and is ignored here.
  -- Two separate instances of tdp_ram, to account for LSB and MSB of each word.
  tdp_ram_lsb_inst : entity work.tdp_ram
    generic map (
      INIT_VAL   => C_PP_RAM_INIT_LSB,
      ADDR_WIDTH => 11,
      DATA_WIDTH => 8
    )
    port map (
      clock_a   => clk_i,
      address_a => std_logic_vector(reg_pp_ptr(11 downto 1)),
      data_a    => pp_wrdat(7 downto 0),
      wren_a    => pp_we(0),
      q_a       => pp_rddat(7 downto 0),
      clock_b   => clk_i,
      address_b => std_logic_vector(rxtx_addr(11 downto 1)),
      data_b    => rxtx_wrdat(7 downto 0),
      wren_b    => rxtx_we(0),
      q_b       => rxtx_rddat(7 downto 0)
    ); -- tdp_ram_lsb_inst : entity work.tdp_ram

  tdp_ram_msb_inst : entity work.tdp_ram
    generic map (
      INIT_VAL   => C_PP_RAM_INIT_MSB,
      ADDR_WIDTH => 11,
      DATA_WIDTH => 8
    )
    port map (
      clock_a   => clk_i,
      address_a => std_logic_vector(reg_pp_ptr(11 downto 1)),
      data_a    => pp_wrdat(15 downto 8),
      wren_a    => pp_we(1),
      q_a       => pp_rddat(15 downto 8),
      clock_b   => clk_i,
      address_b => std_logic_vector(rxtx_addr(11 downto 1)),
      data_b    => rxtx_wrdat(15 downto 8),
      wren_b    => rxtx_we(1),
      q_b       => rxtx_rddat(15 downto 8)
    ); -- tdp_ram_msb_inst : entity work.tdp_ram


  ----------------------------------------------------------
  -- CPU-side FSM: handles $DExx reads and writes, decodes
  -- autoincrement, drives the RxTx-window read pointer, and
  -- signals frame consumption.
  ----------------------------------------------------------

  fsm_proc : process (clk_i)
    variable rx_end_ptr_v : unsigned(11 downto 0);
  begin
    if rising_edge(clk_i) then
      -- Sanity assertion: catch drivers that write to the Tx buffer while
      -- transmission is still in progress (they should have polled Rdy4TxNOW
      -- first). This is a driver bug, not a hardware one.
      assert not (tx_state = TX_BUSY_ST and cs_d = '0' and cs_i = '1' and we_i = '1'
                  and (unsigned(addr_i) = C_RXTX_REG_0 or unsigned(addr_i) = C_RXTX_REG_0 + 1))
        report "rrnet: CPU write to Tx buffer while Tx is in progress"
        severity failure;

      -- Sanity assertion: warn if the CPU tries to read the RxTx window
      -- for Rx purposes while a Tx is in progress. This would return
      -- Tx-buffer data instead of Rx-buffer data because port B is
      -- arbitrated to Tx-read.
      assert not (tx_state = TX_BUSY_ST and rx_state = RX_READY_ST and
                  cs_d = '0' and cs_i = '1' and we_i = '0' and
                  (unsigned(addr_i) = C_RXTX_REG_0 or unsigned(addr_i) = C_RXTX_REG_0 + 1))
        report "rrnet: CPU read from Rx window while Tx is in progress"
        severity warning;

      -- Defaults each cycle: clear one-cycle strobes.
      reg_tx_start      <= '0';
      pp_we             <= (others => '0');
      rx_frame_consumed <= '0';
      cs_d              <= cs_i;
      cs_dd             <= cs_d;

      -- End-of-frame byte address for autoincrement detection: header
      -- occupies $0400..$0403, payload starts at $0404, ends at
      -- $0404 + rx_length - 1. When the pointer has advanced to or past
      -- $0404 + rx_length, the frame is considered consumed.
      rx_end_ptr_v      := C_RX_BUF_START + 4 + rx_length(11 downto 0);

      -- On entering RX_READY_ST, reset the RxTx-window read pointer so
      -- $DE08/09 reads start at $0400 (RxStatus low byte). We spot the
      -- transition by looking at rx_state's registered value; on the
      -- cycle rx_state has just become RX_READY_ST, rx_frame_consumed
      -- is guaranteed to be '0'.
      if rx_state = RX_READY_ST and reg_rx_ptr = 0 then
        reg_rx_ptr <= C_RX_BUF_START;
      end if;

      -- Since Chip Select may be asserted for several consecutive clock
      -- cycles, we only react on the second beat with CS asserted.
      -- We use the second (and not the first) beat because we need to
      -- wait for rxtx_rddat to be driven.
      if cs_dd = '0' and cs_d = '1' and cs_i = '1' then
        if we_i = '1' then
          if G_DEBUG then
            report "RRNET: WRITE " & to_hstring(wr_data_i) & " TO $DE" & to_hstring(addr_i);
          end if;

          case unsigned(addr_i) is

            when C_PP_PTR =>
              reg_pp_ptr(7 downto 0) <= unsigned(wr_data_i);

            when C_PP_PTR + 1 =>
              reg_pp_ptr(15 downto 8) <= unsigned(wr_data_i);

            when C_PP_DATA_0 =>
              -- Replicate the byte into both halves of the 16-bit word; the pp_we
              -- byte-enable pattern selects which half actually gets written.
              pp_wrdat <= wr_data_i & wr_data_i;
              pp_we    <= "01";

              -- Explicit RxEvent acknowledgement: a CPU write to $0124/25
              -- clears RxOK and re-arms the receiver. Matches drivers that
              -- clear-by-write rather than clear-by-read.
              if reg_pp_ptr(11 downto 1) = C_PP_RX_EVENT_ADDR and
                 rx_state = RX_READY_ST then
                rx_frame_consumed <= '1';
                reg_rx_ptr        <= (others => '0');
              end if;

            when C_PP_DATA_0 + 1 =>
              pp_wrdat <= wr_data_i & wr_data_i;
              pp_we    <= "10";
              if reg_pp_ptr(15) = '1' then
                reg_pp_ptr <= reg_pp_ptr + 2;
              end if;

              if reg_pp_ptr(11 downto 1) = C_PP_RX_EVENT_ADDR and
                 rx_state = RX_READY_ST then
                rx_frame_consumed <= '1';
                reg_rx_ptr        <= (others => '0');
              end if;

            when C_RXTX_REG_0 =>
              reg_pp_ptr <= "0000" & reg_tx_ptr;
              pp_wrdat   <= wr_data_i & wr_data_i;
              pp_we      <= "01";

            when C_RXTX_REG_0 + 1 =>
              reg_pp_ptr <= "0000" & reg_tx_ptr;
              reg_tx_ptr <= reg_tx_ptr + 2;
              pp_wrdat   <= wr_data_i & wr_data_i;
              pp_we      <= "10";
              if reg_tx_ptr + 2 >= C_TX_BUF_START + reg_tx_length then
                -- Minimum frame length is 60 bytes
                -- Here we append the frame with extra random bytes. They will be ignored by receiver.
                if reg_tx_length < 60 then
                  reg_tx_length <= to_unsigned(60, 16);
                end if;
                reg_tx_start <= '1';
              end if;

            when C_TX_CMD =>
              reg_tx_cmd(7 downto 0) <= unsigned(wr_data_i);
              reg_tx_ptr             <= C_TX_BUF_START;

            when C_TX_CMD + 1 =>
              reg_tx_cmd(15 downto 8) <= unsigned(wr_data_i);

            when C_TX_LENGTH =>
              reg_tx_length(7 downto 0) <= unsigned(wr_data_i);

            when C_TX_LENGTH + 1 =>
              reg_tx_length(15 downto 8) <= unsigned(wr_data_i);

            when others =>
              null;

          end case;

        else
          if G_DEBUG then
            report "RRNET: READ FROM $DE" & to_hstring(addr_i);
          end if;

          rd_data_o <= (others => '0');

          case unsigned(addr_i) is

            when C_PP_PTR =>
              rd_data_o <= std_logic_vector(reg_pp_ptr(7 downto 0));

            when C_PP_PTR + 1 =>
              rd_data_o <= std_logic_vector(reg_pp_ptr(15 downto 8));

            when C_PP_DATA_0 =>
              -- low-byte read: apply live-status overlays before returning.
              if reg_pp_ptr(11 downto 1) = C_PP_SELF_CTL_ADDR then
                -- Self Control. RESET (bit 6) always reads zero.
                rd_data_o <= pp_rddat(7 downto 0) and X"BF";
              elsif reg_pp_ptr(11 downto 1) = C_PP_LINE_ST_ADDR then
                -- LineST $0134: LinkOK (bit 7) always reads one.
                rd_data_o <= pp_rddat(7 downto 0) or X"80";
              else
                rd_data_o <= pp_rddat(7 downto 0);
              end if;

            when C_PP_DATA_0 + 1 =>
              -- High-byte read: apply live-status overlays before returning.
              if reg_pp_ptr(11 downto 1) = C_PP_BUS_ST_ADDR then
                -- Bus Status $0138: overlay Rdy4TxNOW at bit 8 (bit 0 of the high byte).
                rd_data_o <= pp_rddat(15 downto 9) & rdy_4_tx_now;
              elsif reg_pp_ptr(11 downto 1) = C_PP_RX_EVENT_ADDR then
                -- RxEvent $0124: overlay RxOK at bit 8 (bit 0 of the high byte).
                rd_data_o <= pp_rddat(15 downto 9) & rx_frame_ready;
              else
                rd_data_o <= pp_rddat(15 downto 8);
              end if;

              -- Autoincrement fires only on high-byte access (per CS8900A spec).
              -- Drivers using autoincrement must always read low byte then high byte.
              if reg_pp_ptr(15) = '1' then
                reg_pp_ptr <= reg_pp_ptr + 2;

                -- Frame-consumed detection: the CPU has just auto-incremented
                -- reg_pp_ptr past the end of the current Rx frame. Re-arm the
                -- receiver. Compare against the address that WILL be in
                -- reg_pp_ptr on the next cycle (reg_pp_ptr + 2).
                if rx_state = RX_READY_ST and
                   (reg_pp_ptr(11 downto 0) + 2) >= rx_end_ptr_v then
                  rx_frame_consumed <= '1';
                  reg_rx_ptr        <= (others => '0');
                end if;
              end if;

            when C_RXTX_REG_0 =>
              -- RxTx window low-byte read.
              -- Returns the low byte of the current Rx word (addressed via
              -- port B by the arbitration mux above). Does NOT advance
              -- reg_rx_ptr; that fires on the high-byte access only.
              if rx_state = RX_READY_ST then
                rd_data_o <= rxtx_rddat(7 downto 0);
                if reg_rx_ptr < C_RX_BUF_START + 4 then
                  reg_rx_ptr <= reg_rx_ptr + 2;

                  if (reg_rx_ptr + 2) >= rx_end_ptr_v then
                    rx_frame_consumed <= '1';
                    reg_rx_ptr        <= (others => '0');
                  end if;
                end if;
              else
                -- No frame available: return zero (idle bus behaviour).
                rd_data_o <= X"00";
              end if;

            when C_RXTX_REG_0 + 1 =>
              -- RxTx window high-byte read.
              -- Returns the high byte and advances reg_rx_ptr by 2 (word).
              -- Frame-consumed detection is identical to the PP-window path:
              -- when the pointer has advanced past $0404 + rx_length, the
              -- receiver is re-armed.
              if rx_state = RX_READY_ST then
                rd_data_o <= rxtx_rddat(15 downto 8);
                if reg_rx_ptr >= C_RX_BUF_START + 4 then
                  reg_rx_ptr <= reg_rx_ptr + 2;

                  if (reg_rx_ptr + 2) >= rx_end_ptr_v then
                    rx_frame_consumed <= '1';
                    reg_rx_ptr        <= (others => '0');
                  end if;
                end if;
              else
                rd_data_o <= X"00";
              end if;

            when C_TX_CMD =>
              rd_data_o <= std_logic_vector(reg_tx_cmd(7 downto 0));

            when C_TX_CMD + 1 =>
              rd_data_o <= std_logic_vector(reg_tx_cmd(15 downto 8));

            when C_TX_LENGTH =>
              rd_data_o <= std_logic_vector(reg_tx_length(7 downto 0));

            when C_TX_LENGTH + 1 =>
              rd_data_o <= std_logic_vector(reg_tx_length(15 downto 8));

            when others =>
              null;

          end case;

        end if;
      end if;

      -- Synchronous reset overrides above logic.
      if rst_i = '1' then
        cs_d              <= '0';
        cs_dd             <= '0';
        pp_we             <= (others => '0');
        reg_pp_ptr        <= (others => '0');
        reg_tx_cmd        <= (others => '0');
        reg_tx_length     <= (others => '0');
        reg_tx_ptr        <= C_TX_BUF_START;
        reg_tx_start      <= '0';
        reg_rx_ptr        <= (others => '0');
        rx_frame_consumed <= '0';
      end if;
    end if;
  end process fsm_proc;

end architecture rtl;

