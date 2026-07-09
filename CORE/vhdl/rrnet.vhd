-- ----------------------------------------------------------
-- Description: Simulates an CS8900A ethernet chip
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
-- 0A00        : Transmit Frame Location
--
-- Bus Status ($0138), Rdy4TxNOW bit (bit 8): live-overlaid from tx_state
-- on CPU reads of that PP offset. RAM contents at $0138 are never rewritten;
-- the RAM value provides the static (non-Rdy4TxNOW) bits.
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
    -- It is assumed that CS is deasserted between each single transaction.
    clk_i          : in    std_logic;
    rst_i          : in    std_logic;
    cs_i           : in    std_logic;                    -- Chip Select. Connect to IO1 ($DExx)
    addr_i         : in    std_logic_vector(7 downto 0);
    we_i           : in    std_logic;
    wr_data_i      : in    std_logic_vector(7 downto 0);
    rd_data_o      : out   std_logic_vector(7 downto 0);

    -- Ethernet interface (byte streaming, same clock domain as CPU interface)
    -- Byte-oriented interface to an RMII Ethernet PHY.
    --
    -- Rx contract : * eth_rx_valid_i pulses high for 1 clock cycle per byte (byte strobe).
    --               * eth_rx_last_i marks the last byte of a frame (client-visible payload;
    --                 the 4-byte FCS is already stripped).
    --               * eth_rx_ok_i is valid only on the beat with eth_rx_last_i = '1'; it is
    --                 '1' if the frame passed CRC and had no PHY error, '0' otherwise.
    --               * There is NO back-pressure on the Rx side (no eth_rx_ready_o). The
    --                 client must consume every valid beat.
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
    -- 2 - 3 clock cycles, so this is safe with margi
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

  constant C_PP_PTR     : unsigned(7 downto 0)                     := x"02";
  constant C_PP_DATA_0  : unsigned(7 downto 0)                     := x"04";
  constant C_PP_DATA_1  : unsigned(7 downto 0)                     := x"06"; -- Not used
  constant C_RXTX_REG_0 : unsigned(7 downto 0)                     := x"08";
  constant C_RXTX_REG_1 : unsigned(7 downto 0)                     := x"0A"; -- Not used
  constant C_TX_CMD     : unsigned(7 downto 0)                     := x"0C";
  constant C_TX_LENGTH  : unsigned(7 downto 0)                     := x"0E";

  constant C_RX_BUF_START : unsigned(11 downto 0)                  := X"400";
  constant C_TX_BUF_START : unsigned(11 downto 0)                  := X"A00";

  -- pp_ptr(15) is the AutoIncrement control bit, not an address bit.
  -- Only pp_ptr(11 downto 0) is passed to the RAM
  signal   reg_pp_ptr    : unsigned(15 downto 0)                   := (others => '0');
  signal   reg_tx_cmd    : unsigned(15 downto 0)                   := (others => '0');
  signal   reg_tx_length : unsigned(15 downto 0)                   := (others => '0');

  signal   pp_we    : std_logic_vector( 1 downto 0)                := (others => '0');
  signal   pp_wrdat : std_logic_vector(15 downto 0)                := (others => '0');
  signal   pp_rddat : std_logic_vector(15 downto 0)                := (others => '0');

  signal   rxtx_addr  : unsigned(11 downto 0)                      := (others => '0');
  signal   rxtx_we    : std_logic_vector( 1 downto 0)              := (others => '0');
  signal   rxtx_wrdat : std_logic_vector(15 downto 0)              := (others => '0');
  signal   rxtx_rddat : std_logic_vector(15 downto 0)              := (others => '0');

  -- cs_d is used to detect rising edge of the Chip Select
  signal   cs_d : std_logic                                        := '0';

  -- This holds the entire 2k words of PacketPage memory.
  type     word_array_type is array (natural range <>) of std_logic_vector(15 downto 0);

  -- This generates the reset-value of the 2k words PacketPage memory.

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
    ram_v(C_PP_ISA_ID / 2)  := x"630E";
    -- Product ID and Revision number
    ram_v(C_PP_PROD_ID / 2) := x"0700";
    -- Bus Status (set 'Rdy4TxNOW').
    ram_v(C_PP_BUS_ST / 2)  := x"0118";

    for i in 0 to 2047 loop
      ret_v(16 * i + 15 downto 16 * i) := ram_v(i);
    end loop;
    return ret_v;
  end function get_packet_page_init;

  -- PacketPage RAM initialization vector
  constant C_PP_RAM_INIT : std_logic_vector(4096 * 8 - 1 downto 0) := get_packet_page_init;


  ---------------------------------------------------------
  -- Transmit path
  ---------------------------------------------------------

  type     tx_state_type is (IDLE_ST, BUSY_ST);
  signal   tx_state : tx_state_type                                := IDLE_ST;

  -- Live "buffer ready" flag exposed to software as the Rdy4TxNOW bit of
  -- the CS8900A Bus Status register at PP offset $0138 (bit 8).
  signal   rdy_4_tx_now : std_logic;

  -- PP word address (12-bit RAM index) corresponding to the CS8900A
  -- Bus Status register at PP byte offset $0138.
  constant C_PP_BUS_ST_ADDR   : unsigned(11 downto 1)              := to_unsigned(16#138# / 2, 11);
  constant C_PP_RX_EVENT_ADDR : unsigned(11 downto 1)              := to_unsigned(16#124# / 2, 11);

  signal   tx_ptr   : unsigned(11 downto 0)                        := (others => '0');
  signal   tx_start : std_logic                                    := '0';


  ---------------------------------------------------------
  -- Receive path
  ---------------------------------------------------------

  type     rx_state_type is (RX_IDLE_ST, RX_DATA_ST, RX_HEADER_ST, RX_READY_ST);
  signal   rx_state : rx_state_type                                := RX_IDLE_ST;

  -- Current write address into PacketPage RAM (starts at $0404, skipping
  -- header words; header is filled in RX_HEADER_ST once the length is known).
  signal   rx_wr_addr : unsigned(11 downto 0)                      := (others => '0');

  -- Number of payload bytes accepted so far. Wide enough for max Ethernet
  -- frame (1518 - FCS = 1514). Same width as reg_tx_length for symmetry.
  signal   rx_byte_cnt : unsigned(15 downto 0)                     := (others => '0');

  -- Latched status of the completed frame.
  signal   rx_length : unsigned(15 downto 0)                       := (others => '0');
  signal   rx_ok     : std_logic                                   := '0';

  -- Live "frame available" flag exposed to software as the RxOK bit of
  -- the CS8900A RxEvent register at PP offset $0124 (bit 8).
  signal   rx_frame_ready : std_logic;

  -- Rx accepts new bytes only when Tx isn't using port B and there is no
  -- unread frame occupying the buffer. Any byte that arrives outside this
  -- window is discarded; if a frame is truncated we drop the whole thing.
  signal   rx_accept : std_logic;

begin

  ---------------------------------------------------------
  -- Transmit path
  ---------------------------------------------------------

  rdy_4_tx_now <= '1' when tx_state = IDLE_ST else
                  '0';

  tx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if eth_tx_ready_i = '1' then
        eth_tx_valid_o <= '0';
        eth_tx_last_o  <= '0';
      end if;

      case tx_state is

        when IDLE_ST =>
          if tx_start = '1' then
            tx_state <= BUSY_ST;
          end if;

        when BUSY_ST =>
          if eth_tx_ready_i = '1' then
            if rxtx_addr(0) = '0' then
              eth_tx_data_o <= rxtx_rddat(7 downto 0);
            else
              eth_tx_data_o <= rxtx_rddat(15 downto 8);
            end if;
            eth_tx_valid_o <= '1';
            rxtx_addr      <= rxtx_addr + 1;
            if rxtx_addr + 1 >= C_TX_BUF_START + reg_tx_length then
              rxtx_addr     <= C_TX_BUF_START;
              eth_tx_last_o <= '1';
              tx_state      <= IDLE_ST;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        rxtx_addr      <= C_TX_BUF_START;
        eth_tx_valid_o <= '0';
        eth_tx_last_o  <= '0';
        tx_state       <= IDLE_ST;
      end if;
    end if;
  end process tx_proc;


  ---------------------------------------------------------
  -- Receive path
  ---------------------------------------------------------

  rx_accept    <= '1' when tx_state = IDLE_ST and rx_state /= RX_READY_ST else
                  '0';

  rx_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then

      case rx_state is

        when RX_IDLE_ST =>
          null;

        when RX_DATA_ST =>
          null;

        when RX_HEADER_ST =>
          null;

        when RX_READY_ST =>
          null;

      end case;

      if rst_i = '1' then
        rx_state    <= RX_IDLE_ST;
        rx_wr_addr  <= C_RX_BUF_START + 4;
        rx_byte_cnt <= (others => '0');
        rx_length   <= (others => '0');
        rx_ok       <= '0';
      end if;
    end if;
  end process rx_proc;


  -- The 4kB PacketPage memory is abstracted away into a separate
  -- generic Dual-Port Single-Clock RAM.
  -- Addresses are in units of bytes, and are assumed to be word-aligned,
  -- i.e. bit 0 of the address must always be zero.
  rrnet_pp_inst : entity work.rrnet_pp
    generic map (
      G_INIT => C_PP_RAM_INIT
    )
    port map (
      clk_i      => clk_i,
      a_addr_i   => reg_pp_ptr(11 downto 0),
      a_wren_i   => pp_we,
      a_wrdata_i => pp_wrdat,
      a_rddata_o => pp_rddat,
      b_addr_i   => rxtx_addr and X"FFE",
      b_wren_i   => rxtx_we,
      b_wrdata_i => rxtx_wrdat,
      b_rddata_o => rxtx_rddat
    ); -- rrnet_pp_inst

  -- Main state machine
  fsm_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      assert not (tx_state = BUSY_ST and cs_d = '0' and cs_i = '1' and we_i = '1'
                  and (unsigned(addr_i) = C_RXTX_REG_0 or unsigned(addr_i) = C_RXTX_REG_0 + 1))
        report "rrnet: CPU write to Tx buffer while Tx is in progress"
        severity failure;

      tx_start <= '0';
      pp_we    <= (others => '0');
      cs_d     <= cs_i;
      -- Since Chip Select may be asserted for several consecutive clock cycles,
      -- we only react on the first beat with CS asserted.
      if cs_d = '0' and cs_i = '1' then
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

            when C_PP_DATA_0 + 1 =>
              pp_wrdat <= wr_data_i & wr_data_i;
              pp_we    <= "10";
              if reg_pp_ptr(15) = '1' then
                reg_pp_ptr <= reg_pp_ptr + 2;
              end if;

            when C_RXTX_REG_0 =>
              reg_pp_ptr <= "0000" & tx_ptr;
              pp_wrdat   <= wr_data_i & wr_data_i;
              pp_we      <= "01";

            when C_RXTX_REG_0 + 1 =>
              reg_pp_ptr <= "0000" & tx_ptr;
              tx_ptr     <= tx_ptr + 2;
              pp_wrdat   <= wr_data_i & wr_data_i;
              pp_we      <= "10";
              if tx_ptr + 2 >= C_TX_BUF_START + reg_tx_length then
                tx_start <= '1';
              end if;

            when C_TX_CMD =>
              reg_tx_cmd(7 downto 0) <= unsigned(wr_data_i);
              tx_ptr                 <= C_TX_BUF_START;

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
              rd_data_o <= pp_rddat(7 downto 0);

            when C_PP_DATA_0 + 1 =>
              if reg_pp_ptr(11 downto 1) = C_PP_BUS_ST_ADDR then
                rd_data_o <= pp_rddat(15 downto 9) & rdy_4_tx_now;
              elsif reg_pp_ptr(11 downto 1) = C_PP_RX_EVENT_ADDR then
                -- RxEvent $0124: overlay RxOK (bit 8 = bit 0 of high byte).
                rd_data_o <= pp_rddat(15 downto 9) & rx_frame_ready;
              else
                rd_data_o <= pp_rddat(15 downto 8);
              end if;
              -- Autoincrement fires only on high-byte access (per CS8900A spec).
              -- Drivers using autoincrement must always read low byte then high byte.
              if reg_pp_ptr(15) = '1' then
                reg_pp_ptr <= reg_pp_ptr + 2;
              end if;

            when C_RXTX_REG_0 =>
              rd_data_o <= X"FF";

            when C_RXTX_REG_0 + 1 =>
              rd_data_o <= X"FF";

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

      if rst_i = '1' then
        cs_d          <= '0';
        pp_we         <= (others => '0');
        reg_pp_ptr    <= (others => '0');
        reg_tx_cmd    <= (others => '0');
        reg_tx_length <= (others => '0');
        tx_start      <= '0';
      end if;
    end if;
  end process fsm_proc;

end architecture rtl;

