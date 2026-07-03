-- ----------------------------------------------------------------------------
-- Description:
-- Provides a byte-oriented interface to an RMII Ethernet PHY (10/100 Mbit/s).
-- The packet receive does not support back-pressure (no rx_ready_i).
-- CRC checking is performed, but bad packets are not dropped (instead marked with rx_ok_o = 0 and rx_last_o = 1).
-- There is no Tx buffering, so data must be available when needed.
-- Everything runs at the PHY clock of 50 MHz.
-- I/O buffering and constraints must be handled elsewhere.
-- ----------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity eth_rmii is
  port (
    eth_clk_i   : in    std_logic; -- Must be 50 MHz, same as PHY clock
    eth_rst_i   : in    std_logic;

    -- Client Rx interface
    rx_valid_o  : out   std_logic;
    rx_last_o   : out   std_logic;
    rx_ok_o     : out   std_logic; -- Valid only when rx_last_o = 1.  -- True if frame has correct CRC and no errors.
    rx_data_o   : out   std_logic_vector(7 downto 0);

    -- Client Tx interface
    tx_ready_o  : out   std_logic;
    tx_valid_i  : in    std_logic;
    tx_last_i   : in    std_logic;
    tx_data_i   : in    std_logic_vector(7 downto 0);

    -- Connected to the PHY
    eth_rxd_i   : in    std_logic_vector(1 downto 0);
    eth_rxerr_i : in    std_logic;
    eth_crsdv_i : in    std_logic;
    eth_txd_o   : out   std_logic_vector(1 downto 0);
    eth_txen_o  : out   std_logic
  );
end entity eth_rmii;

architecture synthesis of eth_rmii is

  -- This is the generating polynomial for the CRC-32 used by Ethernet.
  -- See e.g. https://en.wikipedia.org/wiki/Cyclic_redundancy_check
  constant C_CRC_POLY : std_logic_vector(31 downto 0)    := x"04C11DB7";

  -- This is the expected CRC residue when no errors are present.
  -- See e.g. https://en.wikipedia.org/wiki/Ethernet_frame
  constant C_CRC_RESIDUE : std_logic_vector(31 downto 0) := x"C704DD7B";

  -------------------------------------------
  -- Receive path
  -------------------------------------------
  type     rx_fsm_state_type is (RX_IDLE_ST, RX_PRE_ST, RX_PAYLOAD_ST);
  signal   rx_fsm_state : rx_fsm_state_type              := RX_IDLE_ST;
  signal   rx_byte      : std_logic_vector(7 downto 0);
  signal   rx_dibit_cnt : natural range 0 to 3;
  signal   rx_crc       : std_logic_vector(31 downto 0);
  signal   eth_crsdv_d  : std_logic;

  type     rx_stage_type is record
    valid : std_logic; -- Remaining fields are valid.
    last  : std_logic; -- End of frame. Asserted on last byte.
    ok    : std_logic; -- Frame is OK. Valid when last = 1.
    data  : std_logic_vector(7 downto 0);
  end record rx_stage_type;

  type     rx_stage_vector_type is array (natural range<>) of rx_stage_type;
  signal   rx_stages : rx_stage_vector_type(5 downto 0)  := (others => ('0', '0', '0', x"00"));


  -------------------------------------------
  -- Transmit path
  -------------------------------------------
  type     tx_fsm_state_type is (TX_IDLE_ST, TX_PRE1_ST, TX_PRE2_ST, TX_PAYLOAD_ST, TX_LAST_ST, TX_CRC_ST, TX_IFG_ST);
  signal   tx_fsm_state  : tx_fsm_state_type             := TX_IDLE_ST;
  signal   eth_txd       : std_logic_vector(7 downto 0);
  signal   tx_data       : std_logic_vector(7 downto 0);
  signal   tx_byte_cnt   : natural range 0 to 12;
  signal   tx_twobit_cnt : std_logic_vector(1 downto 0);
  signal   tx_crc        : std_logic_vector(31 downto 0);
  signal   tx_crc_reg    : std_logic_vector(31 downto 0);
  signal   tx_crc_enable : std_logic;

begin

  --------------------------------------
  -- Receive path
  --------------------------------------

  rx_proc : process (eth_clk_i)
    variable rx_crc_v     : std_logic_vector(31 downto 0);
    variable rx_newdata_v : std_logic_vector(7 downto 0);
  begin
    if rising_edge(eth_clk_i) then
      -- Some PHY's toggle the crsdv line at end of frame (during CRC).
      -- Therefore, we need to store the previous value of crsdv.
      eth_crsdv_d        <= eth_crsdv_i;

      -- Set default values
      rx_stages(0).valid <= '0';
      rx_stages(0).last  <= '0';
      rx_stages(0).ok    <= '0';
      rx_stages(0).data  <= x"00";

      -- If valid bits are received from the PHY,
      -- shift them into the data register and update the CRC.
      if eth_crsdv_i = '1' or eth_crsdv_d = '1' then
        rx_newdata_v := eth_rxd_i & rx_byte(7 downto 2);
        rx_byte      <= rx_newdata_v;
        rx_dibit_cnt <= (rx_dibit_cnt + 1) mod 4;

        -- Calculate CRC
        -- Consume two bits of data
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

        -- Wait until a new frame starts.
        when RX_IDLE_ST =>
          if eth_crsdv_i = '1' and eth_rxerr_i = '0' then
            rx_fsm_state <= RX_PRE_ST;
            rx_byte      <= (others => '0');
          end if;

        -- Wait until the preamble is finished.
        when RX_PRE_ST =>
          -- Check after every 2 bits received.
          if rx_byte = x"D5" then
            rx_dibit_cnt <= 0;
            rx_fsm_state <= RX_PAYLOAD_ST;
          end if;
          if rx_newdata_v = x"D5" then
            -- Initialize CRC calculation.
            rx_crc <= (others => '1');
          end if;
          if eth_crsdv_i = '0' or eth_rxerr_i = '1' then
            rx_fsm_state <= RX_IDLE_ST;
          end if;

        -- Process the frame
        when RX_PAYLOAD_ST =>
          if (eth_crsdv_i = '0' and eth_crsdv_d = '0') or eth_rxerr_i = '1' then
            -- Premature end of frame (or invalid CRC)
            rx_stages(0).valid <= '1';
            rx_stages(0).last  <= '1';
            rx_stages(0).ok    <= '0'; -- Indicate error
            rx_stages(0).data  <= rx_byte;
            rx_fsm_state       <= RX_IDLE_ST;
          end if;

          if rx_dibit_cnt = 3 then
            -- Valid byte received
            rx_stages(0).valid <= '1';
            rx_stages(0).last  <= '0';
            rx_stages(0).ok    <= '0';
            rx_stages(0).data  <= rx_byte;
            -- Valid CRC indicates end of frame
            if eth_crsdv_i = '0' and eth_rxerr_i = '0' and rx_crc = C_CRC_RESIDUE then
              rx_stages(0).last <= '1';
              rx_stages(0).ok   <= '1';
              rx_fsm_state      <= RX_IDLE_ST;
            end if;
          end if;

      end case;

      if eth_rst_i = '1' then
        rx_stages(0).valid <= '0';
        rx_fsm_state       <= RX_IDLE_ST;
      end if;
    end if;
  end process rx_proc;

  -- Generate signals for stages 1 to 5.
  rx_strip_crc_proc : process (eth_clk_i)
  begin
    if rising_edge(eth_clk_i) then
      rx_stages(5) <= ('0', '0', '0', x"00");

      -- Move pipeline forward one stage.
      if rx_stages(0).valid = '1' then
        rx_stages(1) <= rx_stages(0);
        rx_stages(2) <= rx_stages(1);
        rx_stages(3) <= rx_stages(2);
        rx_stages(4) <= rx_stages(3);
        rx_stages(5) <= rx_stages(4);
      end if;

      -- Strip away CRC
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

  tx_ready_o <= '1' when (tx_fsm_state = TX_IDLE_ST or
                           tx_fsm_state = TX_PAYLOAD_ST) and
                           tx_twobit_cnt = 0  and
                           eth_rst_i = '0' else
                '0';

  tx_proc : process (eth_clk_i)
    variable tx_crc_v : std_logic_vector(31 downto 0);
  begin
    if rising_edge(eth_clk_i) then
      -- Calculate CRC
      if tx_crc_enable = '1' then
        -- Consume two bits of data
        tx_crc_v := tx_crc;

        for i in 0 to 1 loop
          if eth_txd(i) = tx_crc_v(31) then
            tx_crc_v :=  tx_crc_v(30 downto 0) & '0';
          else
            tx_crc_v := (tx_crc_v(30 downto 0) & '0') xor C_CRC_POLY;
          end if;
        end loop;

        tx_crc <= tx_crc_v;
      else
        tx_crc <= (others => '1');
      end if;

      tx_twobit_cnt <= tx_twobit_cnt + 1;
      eth_txd       <= "00" & eth_txd(7 downto 2);

      if tx_twobit_cnt = 0 then
        -- Only change state on a byte boundary.

        case tx_fsm_state is

          when TX_IDLE_ST =>
            eth_txen_o <= '0';
            eth_txd    <= x"00";
            if tx_valid_i = '1' then
              tx_data      <= tx_data_i;
              tx_byte_cnt  <= 7;
              tx_fsm_state <= TX_PRE1_ST;
              eth_txen_o   <= '1';
              eth_txd      <= x"55";
            end if;

          when TX_PRE1_ST =>
            if tx_byte_cnt > 0 then
              eth_txd     <= x"55";
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              eth_txd      <= x"D5";
              tx_byte_cnt  <= 1;
              tx_fsm_state <= TX_PRE2_ST;
            end if;

          when TX_PRE2_ST =>
            eth_txd       <= tx_data;
            tx_crc_enable <= '1';
            tx_fsm_state  <= TX_PAYLOAD_ST;

          when TX_PAYLOAD_ST =>
            eth_txd <= tx_data_i;
            if tx_last_i = '1' then
              tx_fsm_state <= TX_LAST_ST;
            end if;

            -- Abort! Data not available yet.
            if tx_valid_i = '0' then
              eth_txd      <= (others => '0');
              tx_fsm_state <= TX_IFG_ST;
              eth_txen_o   <= '0';
            end if;

          when TX_LAST_ST =>
            -- CRC is transmitted MSB first.
            eth_txd       <= not (tx_crc_v(24) & tx_crc_v(25) & tx_crc_v(26) & tx_crc_v(27) &
                                  tx_crc_v(28) & tx_crc_v(29) & tx_crc_v(30) & tx_crc_v(31));
            tx_crc_reg    <= tx_crc_v(23 downto 0) & x"00";
            tx_byte_cnt   <= 4;
            -- This will reset the CRC.
            tx_crc_enable <= '0';
            tx_fsm_state  <= TX_CRC_ST;

          when TX_CRC_ST =>
            -- CRC is transmitted MSB first.
            eth_txd    <= not (tx_crc_reg(24) & tx_crc_reg(25) & tx_crc_reg(26) & tx_crc_reg(27) &
                               tx_crc_reg(28) & tx_crc_reg(29) & tx_crc_reg(30) & tx_crc_reg(31));
            tx_crc_reg <= tx_crc_reg(23 downto 0) & x"00";
            if tx_byte_cnt > 1 then
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              -- Only 11 octets, because the next state is always the idle state.
              tx_byte_cnt  <= 11;
              eth_txd      <= (others => '0');
              eth_txen_o   <= '0';
              tx_fsm_state <= TX_IFG_ST;
            end if;

          when TX_IFG_ST =>
            if tx_byte_cnt > 1 then
              tx_byte_cnt <= tx_byte_cnt - 1;
            else
              tx_fsm_state <= TX_IDLE_ST;
            end if;

        end case;

      end if;

      if eth_rst_i = '1' then
        eth_txd       <= x"00";
        eth_txen_o    <= '0';
        tx_twobit_cnt <= (others => '0');
        tx_crc_reg    <= (others => '0');
        tx_crc_enable <= '0';
        tx_fsm_state  <= TX_IDLE_ST;
      end if;
    end if;
  end process tx_proc;

  -- Drive output signals
  eth_txd_o  <= eth_txd(1 downto 0);

end architecture synthesis;

