-- ---------------------------------------------------------------------------------------
-- Title       : eth_rmii - RMII Ethernet MAC (10/100 Mbit/s)
-- Description : Byte-oriented interface to an RMII Ethernet PHY. Everything runs
--               at the PHY reference clock of 50 MHz. On a 100 Mbit link the PHY
--               presents/consumes two bits ("a dibit") per 50 MHz cycle, so one
--               MAC-layer byte spans 4 clock cycles.
--
-- RMII notes  : * eth_rxd_i[1:0] carries the current Rx dibit (LSB first within a byte).
--               * eth_crsdv_i is asserted while a frame is being received; some PHYs
--                 toggle it during CRC/end-of-frame, so we sample both this cycle and
--                 the previous cycle before declaring end-of-carrier.
--               * eth_txd_o[1:0] carries the current Tx dibit (LSB first).
--               * eth_txen_o is asserted throughout preamble + SFD + payload + FCS.
--
-- Rx contract : * rx_valid_o pulses high for 1 clock cycle per byte (byte strobe).
--               * rx_last_o marks the last byte of a frame (client-visible payload;
--                 the 4-byte FCS is stripped by the pipeline).
--               * rx_ok_o is valid only on the beat with rx_last_o = '1'; it is
--                 '1' if the frame passed CRC and had no PHY error, '0' otherwise.
--               * There is NO back-pressure on the Rx side (no rx_ready_i). The
--                 client must consume every valid beat.
--
-- Tx contract : * Standard valid/ready handshake, sampled once per byte-time on the
--                 cycle tx_ready_o = '1'. The client must present each new byte on
--                 that cycle or the frame is aborted.
--               * tx_valid_i = '0' on a byte boundary during payload aborts the
--                 frame (no Tx buffering); the MAC then holds the required IFG
--                 before accepting a new frame.
--
-- Framing     : * Rx CRC is checked but bad frames are NOT dropped; they are
--                 delivered with rx_last_o = '1' and rx_ok_o = '0'.
--               * Tx generates preamble (7 x 0x55), SFD (0xD5), payload, FCS,
--                 and enforces a minimum inter-frame gap (12 byte-times = 96
--                 bit-times, per IEEE 802.3).
--
-- I/O         : I/O buffering and timing constraints must be handled at the
--               top level; this module is pure synthesizable RTL.
--
-- SPDX-License-Identifier: GPL v3
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity eth_rmii is
  port (
    eth_clk_i   : in    std_logic;                    -- Must be 50 MHz, same as PHY reference clock
    eth_rst_i   : in    std_logic;                    -- Synchronous, active-high reset

    -- Client Rx interface (byte-strobe; no back-pressure)
    rx_valid_o  : out   std_logic;                    -- One-cycle strobe per received byte
    rx_last_o   : out   std_logic;                    -- Last byte of frame
    rx_ok_o     : out   std_logic;                    -- Only meaningful when rx_last_o = '1'
    rx_data_o   : out   std_logic_vector(7 downto 0); -- Received byte

    -- Client Tx interface (valid/ready handshake, one handshake per byte-time)
    tx_ready_o  : out   std_logic;                    -- Pulses '1' on the byte-boundary cycle
    tx_valid_i  : in    std_logic;                    -- Client presents a byte
    tx_last_i   : in    std_logic;                    -- Client marks the last byte
    tx_data_i   : in    std_logic_vector(7 downto 0); -- Byte to transmit

    -- PHY-side RMII signals
    eth_rxd_i   : in    std_logic_vector(1 downto 0); -- Rx dibit from PHY
    eth_rxerr_i : in    std_logic;                    -- Rx error from PHY
    eth_crsdv_i : in    std_logic;                    -- Carrier-sense + data-valid from PHY
    eth_txd_o   : out   std_logic_vector(1 downto 0); -- Tx dibit to PHY
    eth_txen_o  : out   std_logic                     -- Tx enable to PHY
  );
end entity eth_rmii;

architecture rtl of eth_rmii is

  -- CRC-32 generating polynomial for Ethernet (IEEE 802.3, section 3.2.9).
  -- Reference: https://en.wikipedia.org/wiki/Cyclic_redundancy_check
  constant C_CRC_POLY : std_logic_vector(31 downto 0)    := x"04C11DB7";

  -- Expected CRC residue on a correctly-received Ethernet frame. When the
  -- CRC register equals this value at end-of-carrier, the FCS is valid.
  -- Reference: https://en.wikipedia.org/wiki/Ethernet_frame
  constant C_CRC_RESIDUE : std_logic_vector(31 downto 0) := x"C704DD7B";

  -- Minimum inter-frame gap in byte-times (IEEE 802.3 requires 96 bit-times
  -- = 12 byte-times at 100 Mbit). We spend 1 byte-time transitioning out of
  -- TX_CRC_ST, so TX_IFG_ST counts the remaining 11.
  constant C_IFG_BYTES : natural                         := 11;

  -------------------------------------------
  -- Receive path
  -------------------------------------------

  type     rx_fsm_state_type is (
    RX_IDLE_ST,                           -- Waiting for a new frame (crsdv rising)
    RX_PRE_ST,                            -- Consuming preamble; watching for SFD (0xD5)
    RX_PAYLOAD_ST                         -- Streaming payload bytes (includes FCS, stripped later)
  );
  signal   rx_fsm_state : rx_fsm_state_type              := RX_IDLE_ST;

  -- Byte-in-progress shift register. Dibits from eth_rxd_i are shifted into
  -- the MSB end (positional convention below); after 4 dibits a full byte
  -- is present in rx_byte.
  signal   rx_byte : std_logic_vector(7 downto 0)        := (others => '0');

  -- Dibit position within the current byte (0..3). Wrapped modulo 4.
  signal   rx_dibit_cnt : natural range 0 to 3           := 0;

  -- Running Ethernet CRC. Initialised to all-ones at the start of every
  -- frame (see RX_IDLE_ST -> RX_PRE_ST transition) so leftover residue
  -- from a previous frame cannot leak into the current one.
  signal   rx_crc : std_logic_vector(31 downto 0)        := (others => '1');

  -- Registered previous crsdv value: some PHYs toggle crsdv during the FCS
  -- portion of a frame, so end-of-carrier is only declared when BOTH the
  -- current and previous crsdv samples are '0'.
  signal   eth_crsdv_d : std_logic                       := '0';

  -- Rx pipeline stage payload.
  type     rx_stage_type is record
    valid : std_logic;                    -- Byte strobe (1 cycle)
    last  : std_logic;                    -- End of frame
    ok    : std_logic;                    -- Valid only when last = '1'
    data  : std_logic_vector(7 downto 0); -- Byte value
  end record rx_stage_type;

  type     rx_stage_vector_type is array (natural range <>) of rx_stage_type;

  -- Six-stage byte pipeline. Stages 1..4 are used to hold back four bytes so
  -- that when a byte arrives at stage 0 marked as the last raw byte of the
  -- frame (i.e. the last CRC byte), stage 4 holds the last PAYLOAD byte.
  -- The end-of-frame indication is then promoted to stage 5 while stages
  -- 1..4 are silenced, effectively stripping the 4-byte FCS from the output.
  signal   rx_stages : rx_stage_vector_type(5 downto 0)  :=
        (others => (valid => '0', last => '0', ok => '0', data => (others => '0')));

  -------------------------------------------
  -- Transmit path
  -------------------------------------------

  type     tx_fsm_state_type is (
    TX_IDLE_ST,                           -- Idle; tx_ready_o asserted on byte boundaries
    TX_PRE1_ST,                           -- Emitting 7 preamble bytes (0x55)
    TX_PRE2_ST,                           -- Emitting the SFD byte (0xD5)
    TX_PAYLOAD_ST,                        -- Emitting payload bytes; CRC accumulator running
    TX_LAST_ST,                           -- First FCS byte (freezes CRC value)
    TX_CRC_ST,                            -- Remaining 3 FCS bytes
    TX_IFG_ST                             -- Inter-frame gap (line idle for 11 more byte-times)
  );
  signal   tx_fsm_state : tx_fsm_state_type              := TX_IDLE_ST;

  -- 8-bit shift register for the byte currently being transmitted. Loaded
  -- on the byte-boundary cycle (tx_twobit_cnt = 0), shifted right by 2 on
  -- every other cycle so that tx_shift(1 downto 0) always carries the
  -- next dibit to drive onto the PHY. Only bits 1:0 leave the module.
  signal   tx_shift : std_logic_vector(7 downto 0)       := (others => '0');

  -- First payload byte, captured at IDLE_ST when the client's tx_valid_i
  -- first goes high. See the IDLE_ST comment for why this is needed.
  signal   tx_data : std_logic_vector(7 downto 0)        := (others => '0');

  -- Multi-purpose byte counter: preamble countdown in TX_PRE1_ST, FCS
  -- byte countdown in TX_CRC_ST, IFG byte countdown in TX_IFG_ST.
  signal   tx_byte_cnt : natural range 0 to 12           := 0;

  -- Dibit position within the current byte (0..3). Free-running; wraps
  -- automatically because it is a 2-bit vector.
  signal   tx_twobit_cnt : std_logic_vector(1 downto 0)  := (others => '0');

  -- Running Ethernet CRC over the outgoing payload. Held at all-ones
  -- (init value) whenever tx_crc_enable = '0'.
  signal   tx_crc : std_logic_vector(31 downto 0)        := (others => '1');

  -- Snapshot of the CRC captured at end-of-payload, from which the four
  -- FCS bytes are shifted out one per byte-time in TX_LAST_ST + TX_CRC_ST.
  signal   tx_crc_reg : std_logic_vector(31 downto 0)    := (others => '0');

  -- Gates CRC accumulation. Set at end of preamble; cleared at end of
  -- payload (which also re-initialises tx_crc to all-ones for the next frame).
  signal   tx_crc_enable : std_logic                     := '0';

begin

  --------------------------------------
  -- Receive path
  --------------------------------------

  rx_proc : process (eth_clk_i)
    variable rx_crc_v     : std_logic_vector(31 downto 0);
    variable rx_newdata_v : std_logic_vector(7 downto 0);
  begin
    if rising_edge(eth_clk_i) then
      -- NOTE: When considering RMII Specification 1.2 and 1.0, the behavior of
      -- CRS_DV is different. For RMII 1.0, CRS_DV remains asserted until the final
      -- data is clocked in, while for RMII 1.2, it will toggle at the end of the
      -- packet while data is being transferred.

      -- Therefore, end-of-carrier is only trusted when both the current and
      -- previous crsdv are '0'.
      eth_crsdv_d  <= eth_crsdv_i;

      -- Default: no new byte offered to the pipeline this cycle. The FSM
      -- may override these below.
      rx_stages(0) <= (valid => '0', last => '0', ok => '0', data => (others => '0'));

      -- Whenever the PHY is presenting data (or was on the previous cycle),
      -- shift the current dibit into rx_byte and advance the CRC by 2 bits.
      if eth_crsdv_i = '1' or eth_crsdv_d = '1' then
        rx_newdata_v := eth_rxd_i & rx_byte(7 downto 2);
        rx_byte      <= rx_newdata_v;
        rx_dibit_cnt <= (rx_dibit_cnt + 1) mod 4;

        -- Consume two bits of data into the CRC. Bit 0 first (LSB-first
        -- within a byte, per Ethernet convention), then bit 1.
        rx_crc_v     := rx_crc;

        for i in 0 to 1 loop
          if eth_rxd_i(i) = rx_crc_v(31) then
            rx_crc_v :=  rx_crc_v(30 downto 0) & '0';
          else
            rx_crc_v := (rx_crc_v(30 downto 0) & '0') xor C_CRC_POLY;
          end if;
        end loop;

        rx_crc <= rx_crc_v;
      end if;

      case rx_fsm_state is

        -- Wait for the PHY to raise crsdv, marking the start of a frame.
        -- On entry to RX_PRE_ST we explicitly reset the byte shift
        -- register, the dibit counter, and the CRC accumulator so the new
        -- frame is completely independent of any residue from the previous
        -- one (belt-and-braces safety; the SFD-triggered reset below
        -- covers the CRC only if the SFD is detected cleanly).
        when RX_IDLE_ST =>
          if eth_crsdv_i = '1' and eth_rxerr_i = '0' then
            rx_fsm_state <= RX_PRE_ST;
            rx_byte      <= (others => '0');
            rx_dibit_cnt <= 0;
            rx_crc       <= (others => '1');
          end if;

        -- Consume the preamble. Ethernet preamble is 7 bytes of 0x55
        -- followed by the SFD 0xD5. Because the shift register is byte-
        -- unaligned during preamble, we detect the SFD by shape-matching
        -- rx_byte = 0xD5 every clock cycle rather than relying on the
        -- dibit counter. The moment SFD is seen we align the counter to 0
        -- so payload bytes are captured on rx_dibit_cnt = 3 boundaries.
        when RX_PRE_ST =>
          if rx_byte = x"D5" then
            rx_dibit_cnt <= 0;
            rx_fsm_state <= RX_PAYLOAD_ST;
          end if;
          if rx_newdata_v = x"D5" then
            -- Re-initialise the CRC on the exact cycle SFD arrives, so the
            -- first payload dibit will be the first to affect the CRC.
            rx_crc <= (others => '1');
          end if;
          if eth_crsdv_i = '0' or eth_rxerr_i = '1' then
            rx_fsm_state <= RX_IDLE_ST;
          end if;

        -- Stream payload bytes (including the 4-byte FCS) into the
        -- pipeline. Two exit conditions are handled with priority:
        --   1. Byte boundary (rx_dibit_cnt = 3): emit a valid byte, with
        --      last/ok set if the CRC has just become correct AND the PHY
        --      has just de-asserted crsdv (i.e., FCS just clocked in).
        --   2. Premature end-of-carrier or PHY error: emit an error beat.
        -- Note the elsif: if a premature-end and a byte boundary happen
        -- in the same cycle, the byte boundary wins so the client always sees
        -- exactly one last=1 beat per frame.
        when RX_PAYLOAD_ST =>
          if rx_dibit_cnt = 3 then
            -- Full byte assembled: forward it to the pipeline.
            rx_stages(0).valid <= '1';
            rx_stages(0).last  <= '0';
            rx_stages(0).ok    <= '0';
            rx_stages(0).data  <= rx_byte;
            -- End-of-frame detection: CRC-valid residue at the moment the
            -- PHY drops carrier. This byte is the last CRC byte from the
            -- raw stream; the CRC-strip pipeline downstream will present
            -- the last PAYLOAD byte to the client on this beat.
            if eth_crsdv_i = '0' and eth_rxerr_i = '0' and rx_crc = C_CRC_RESIDUE then
              rx_stages(0).last <= '1';
              rx_stages(0).ok   <= '1';
              rx_fsm_state      <= RX_IDLE_ST;
            end if;
          elsif (eth_crsdv_i = '0' and eth_crsdv_d = '0') or eth_rxerr_i = '1' then
            -- Premature end of frame or PHY-reported error.
            rx_stages(0).valid <= '1';
            rx_stages(0).last  <= '1';
            rx_stages(0).ok    <= '0';
            rx_stages(0).data  <= rx_byte;
            rx_fsm_state       <= RX_IDLE_ST;
          end if;

      end case;

      -- Synchronous reset overrides above logic.
      if eth_rst_i = '1' then
        rx_stages(0).valid <= '0';
        rx_fsm_state       <= RX_IDLE_ST;
      end if;
    end if;
  end process rx_proc;

  --------------------------------------
  -- Rx CRC-strip pipeline (stages 1..5)
  --
  -- Six-stage byte-strobe pipeline. Because valid beats arrive at stage 0
  -- only once every 4 clocks (RMII byte cadence), stages 1..5 are only
  -- advanced when a new byte arrives at stage 0. Between byte arrivals
  -- stage 5 is force-cleared, so rx_valid_o pulses high for exactly 1
  -- clock cycle per byte (a byte strobe).
  --
  -- When a raw last=1 beat arrives at stage 0 (the last CRC byte), we
  -- silence stages 1..4 (their contents ARE the 4 CRC bytes we want to
  -- strip) and promote a synthetic last-beat to stage 5 carrying the
  -- ok flag from stage 0 and the DATA that was in stage 4 (which is the
  -- last actual payload byte, since it lagged the CRC bytes by 4 slots).
  --------------------------------------

  rx_strip_crc_proc : process (eth_clk_i)
  begin
    if rising_edge(eth_clk_i) then
      -- Default: no output beat this cycle (byte-strobe behaviour).
      rx_stages(5) <= (valid => '0', last => '0', ok => '0', data => (others => '0'));

      -- Advance the pipeline one stage on each byte arrival at stage 0.
      if rx_stages(0).valid = '1' then
        rx_stages(1) <= rx_stages(0);
        rx_stages(2) <= rx_stages(1);
        rx_stages(3) <= rx_stages(2);
        rx_stages(4) <= rx_stages(3);
        rx_stages(5) <= rx_stages(4);
      end if;

      -- Strip the 4-byte FCS: when the raw last=1 arrives, invalidate
      -- stages 1..4 (they hold the 4 CRC bytes) and jam a synthetic
      -- end-of-frame beat into stage 5. Its .data comes from stage 4
      -- (the true last payload byte) via the pipeline advance above.
      if rx_stages(0).valid = '1' and rx_stages(0).last = '1' then
        rx_stages(1).valid <= '0';
        rx_stages(1).last  <= '0';
        rx_stages(2).valid <= '0';
        rx_stages(2).last  <= '0';
        rx_stages(3).valid <= '0';
        rx_stages(3).last  <= '0';
        rx_stages(4).valid <= '0';
        rx_stages(4).last  <= '0';
        rx_stages(5).ok    <= rx_stages(0).ok;
        rx_stages(5).valid <= '1';
        rx_stages(5).last  <= '1';
      end if;
    end if;
  end process rx_strip_crc_proc;

  rx_valid_o <= rx_stages(5).valid;
  rx_last_o  <= rx_stages(5).last;
  rx_ok_o    <= rx_stages(5).ok;
  rx_data_o  <= rx_stages(5).data;


  --------------------------------------
  -- Transmit path
  --------------------------------------

  -- tx_ready_o pulses high once per byte-time (on tx_twobit_cnt = 0) while
  -- the FSM is willing to accept a new byte: either at frame start
  -- (TX_IDLE_ST) or between payload bytes (TX_PAYLOAD_ST).
  tx_ready_o <= '1' when (tx_fsm_state = TX_IDLE_ST or
                           tx_fsm_state = TX_PAYLOAD_ST) and
                           tx_twobit_cnt = 0 and
                           eth_rst_i = '0' else
                '0';

  tx_proc : process (eth_clk_i)
    variable tx_crc_v : std_logic_vector(31 downto 0);
  begin
    if rising_edge(eth_clk_i) then
      -- CRC accumulator: consume the two bits currently at the LSB end of
      -- tx_shift (which are the two bits being placed on the wire this
      -- cycle) while tx_crc_enable = '1'. When disabled the CRC is held
      -- at all-ones so the next frame starts with a clean initial value.
      if tx_crc_enable = '1' then
        tx_crc_v := tx_crc;

        for i in 0 to 1 loop
          if tx_shift(i) = tx_crc_v(31) then
            tx_crc_v :=  tx_crc_v(30 downto 0) & '0';
          else
            tx_crc_v := (tx_crc_v(30 downto 0) & '0') xor C_CRC_POLY;
          end if;
        end loop;

        tx_crc <= tx_crc_v;
      else
        tx_crc <= (others => '1');
      end if;

      -- Free-running dibit counter (2 bits, wraps naturally).
      tx_twobit_cnt <= tx_twobit_cnt + 1;

      -- Shift the outgoing byte down by 2 bits every clock. Byte-boundary
      -- FSM transitions may override this with a fresh byte load.
      tx_shift      <= "00" & tx_shift(7 downto 2);

      if tx_twobit_cnt = 0 then
        -- Byte boundary: FSM transitions and new-byte loads happen here.

        case tx_fsm_state is

          -- Idle: waiting for the client to present a frame. When tx_valid_i
          -- rises we capture the first payload byte into tx_data (it will
          -- be needed 8 byte-times later, at TX_PRE2_ST, by which point
          -- tx_data_i has long since changed). Then we start emitting the
          -- preamble (7 bytes of 0x55).
          when TX_IDLE_ST =>
            eth_txen_o <= '0';
            tx_shift   <= x"00";
            if tx_valid_i = '1' then
              tx_data      <= tx_data_i;
              tx_byte_cnt  <= 6;
              tx_fsm_state <= TX_PRE1_ST;
              eth_txen_o   <= '1';
              tx_shift     <= x"55";
            end if;

          -- Emit the remaining preamble bytes. After the 7th 0x55 we jump
          -- to TX_PRE2_ST and emit the SFD (0xD5).
          when TX_PRE1_ST =>
            if tx_byte_cnt > 0 then
              tx_shift    <= x"55";
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              tx_shift     <= x"D5";
              tx_byte_cnt  <= 1;
              tx_fsm_state <= TX_PRE2_ST;
            end if;

          -- SFD has been queued; now enable CRC and start payload. The
          -- first payload byte was captured back in TX_IDLE_ST because
          -- tx_ready_o has been low since then and tx_data_i is no longer
          -- guaranteed to hold its original value.
          when TX_PRE2_ST =>
            tx_shift      <= tx_data;
            tx_crc_enable <= '1';
            tx_fsm_state  <= TX_PAYLOAD_ST;

          -- Emit successive payload bytes. Because tx_ready_o was high on
          -- the previous byte boundary, the client should now be presenting
          -- the next byte on tx_data_i. If tx_last_i is asserted with this
          -- byte, the next byte-boundary transitions to TX_LAST_ST which
          -- will replace payload with the first FCS byte.
          --
          -- Abort: if the client failed to keep tx_valid_i high (and this
          -- is not the last-byte case), the frame is aborted and we jump
          -- straight to the IFG. tx_byte_cnt is initialised to the full
          -- IFG length so the abort does not accidentally shorten the gap.
          when TX_PAYLOAD_ST =>
            tx_shift <= tx_data_i;
            if tx_last_i = '1' then
              tx_fsm_state <= TX_LAST_ST;
            end if;

            if tx_valid_i = '0' and tx_last_i = '0' then
              tx_shift     <= (others => '0');
              tx_byte_cnt  <= C_IFG_BYTES;
              tx_fsm_state <= TX_IFG_ST;
              eth_txen_o   <= '0';
            end if;

          -- First FCS byte. tx_crc_v (variable, computed at the top of
          -- this same process invocation) already includes the CRC update
          -- for the last 2 bits of the last payload byte, so it is the
          -- final CRC value. Ethernet transmits the FCS bit-reversed and
          -- complemented within each byte, and byte-reversed across the
          -- 32-bit word; we assemble the first byte here and stash the
          -- remaining three in tx_crc_reg for the next three byte-times.
          when TX_LAST_ST =>
            tx_shift      <= not (tx_crc_v(24) & tx_crc_v(25) & tx_crc_v(26) & tx_crc_v(27) &
                                  tx_crc_v(28) & tx_crc_v(29) & tx_crc_v(30) & tx_crc_v(31));
            tx_crc_reg    <= tx_crc_v(23 downto 0) & x"00";
            tx_byte_cnt   <= 4;
            -- Disable CRC: also re-arms tx_crc to all-ones for the next frame.
            tx_crc_enable <= '0';
            tx_fsm_state  <= TX_CRC_ST;

          -- Remaining FCS bytes (3 total). Each byte is bit-reversed and
          -- complemented from the top byte of tx_crc_reg, which is then
          -- shifted up by 8 bits to expose the next FCS byte. When the
          -- last FCS byte has been queued we deassert txen and enter IFG.
          when TX_CRC_ST =>
            tx_shift   <= not (tx_crc_reg(24) & tx_crc_reg(25) & tx_crc_reg(26) & tx_crc_reg(27) &
                               tx_crc_reg(28) & tx_crc_reg(29) & tx_crc_reg(30) & tx_crc_reg(31));
            tx_crc_reg <= tx_crc_reg(23 downto 0) & x"00";
            if tx_byte_cnt > 1 then
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              -- Only C_IFG_BYTES (=11) IFG octets remaining, because the
              -- current byte-time is used for the transition itself.
              tx_byte_cnt  <= C_IFG_BYTES;
              tx_shift     <= (others => '0');
              eth_txen_o   <= '0';
              tx_fsm_state <= TX_IFG_ST;
            end if;

          -- Inter-frame gap: hold the line idle for C_IFG_BYTES byte-times
          -- before returning to TX_IDLE_ST where a new frame may start.
          when TX_IFG_ST =>
            if tx_byte_cnt > 1 then
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              tx_fsm_state <= TX_IDLE_ST;
            end if;

        end case;

      end if;

      -- Synchronous reset overrides above logic.
      if eth_rst_i = '1' then
        tx_shift      <= x"00";
        eth_txen_o    <= '0';
        tx_twobit_cnt <= (others => '0');
        tx_crc_reg    <= (others => '0');
        tx_crc_enable <= '0';
        tx_fsm_state  <= TX_IDLE_ST;
      end if;
    end if;
  end process tx_proc;

  -- Drive the two Tx dibit lines from the low bits of the shift register.
  eth_txd_o  <= tx_shift(1 downto 0);

end architecture rtl;

