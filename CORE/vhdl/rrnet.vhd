-- ----------------------------------------------------------
-- Description: Simulates an CS8900A ethernet chip
--
-- Datasheet: https://www.mi.fu-berlin.de/inf/groups/ag-tech/projects/ScatterWeb/moduleComponents/EWS_CS8900.pdf
--
-- Only I/O Space Operation is supported, see section 4.10 in datasheet.
--
-- PacketPage Address:
-- 0000 - 0045 : Bus Interface Registers
-- 0100 - 013F : Status and Control Registers
-- 0140 - 014F : Initiate Transmit Registers
-- 0150 - 015D : Address Filter Registers
-- 0400        : Receive Frame Location
-- 0A00        : Transmit Frame Location
-- ----------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity rrnet is
  port (
    -- CPU interface
    clk_i          : in    std_logic;
    rst_i          : in    std_logic;
    cs_i           : in    std_logic;                    -- Connect to IO1 ($DExx)
    addr_i         : in    std_logic_vector(7 downto 0);
    we_i           : in    std_logic;
    wr_data_i      : in    std_logic_vector(7 downto 0);
    rd_data_o      : out   std_logic_vector(7 downto 0);

    -- Ethernet interface
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
  constant C_PP_DATA_1  : unsigned(7 downto 0)                     := x"06";
  constant C_RXTX_REG_0 : unsigned(7 downto 0)                     := x"08";
  constant C_RXTX_REG_1 : unsigned(7 downto 0)                     := x"0A";
  constant C_TX_CMD     : unsigned(7 downto 0)                     := x"0C";
  constant C_TX_LENGTH  : unsigned(7 downto 0)                     := x"0E";

  signal   pp_ptr     : unsigned(15 downto 0)                      := (others => '0');
  signal   pp_data_0  : unsigned(15 downto 0)                      := (others => '0');
  signal   pp_data_1  : unsigned(15 downto 0)                      := (others => '0');
  signal   rxtx_reg_0 : unsigned(15 downto 0)                      := (others => '0');
  signal   rxtx_reg_1 : unsigned(15 downto 0)                      := (others => '0');
  signal   tx_cmd     : unsigned(15 downto 0)                      := (others => '0');
  signal   tx_length  : unsigned(15 downto 0)                      := (others => '0');

  signal   pp_we    : std_logic_vector( 1 downto 0);
  signal   pp_wrdat : std_logic_vector(15 downto 0);
  signal   pp_rddat : std_logic_vector(15 downto 0);

  signal   rxtx_addr  : unsigned(11 downto 0)                      := (others => '0');
  signal   rxtx_we    : std_logic_vector( 1 downto 0)              := (others => '0');
  signal   rxtx_wrdat : std_logic_vector(15 downto 0)              := (others => '0');
  signal   rxtx_rddat : std_logic_vector(15 downto 0)              := (others => '0');

  signal   cs_d : std_logic                                        := '0';

  -- This holds the entire 2k words of PacketPage memory.
  type     byte_array_type is array (natural range <>) of std_logic_vector(15 downto 0);

  -- This generates the reset-value of the 2k words PacketPage memory.

  pure function get_packet_page_init return std_logic_vector is
    variable ram_v : byte_array_type(0 to 2047)              := (others => (others => '0'));
    variable ret_v : std_logic_vector(4096 * 8 - 1 downto 0) := (others => '0');
  begin
    -- Note: Addresses are divided by two, to convert from byte to word addressing.
    -- EISA registration number for Crystal Semiconductor
    ram_v(16#000# / 2) := x"630E";
    -- Product ID and Revision number
    ram_v(16#002# / 2) := x"0700";
    -- Bus Status (set 'Rdy4TxNOW').
    ram_v(16#138# / 2) := x"0118";

    for i in 0 to 2047 loop
      ret_v(16 * i + 15 downto 16 * i) := ram_v(i);
    end loop;
    return ret_v;
  end function get_packet_page_init;

  -- PacketPage RAM initialization vector
  constant C_PP_RAM_INIT : std_logic_vector(4096 * 8 - 1 downto 0) := get_packet_page_init;

begin

  -- TBD!!!
  eth_tx_valid_o <= eth_rx_valid_i;
  eth_tx_last_o  <= eth_rx_last_i;
  eth_tx_data_o  <= eth_rx_data_i;

  -- Instantiate 4kB Packet Page memory (dual port, single clock)
  rrnet_pp_inst : entity work.rrnet_pp
    generic map (
      G_INIT => C_PP_RAM_INIT
    )
    port map (
      clk_i      => clk_i,
      a_addr_i   => pp_ptr(11 downto 0),
      a_wren_i   => pp_we,
      a_wrdata_i => pp_wrdat,
      a_rddata_o => pp_rddat,
      b_addr_i   => rxtx_addr,
      b_wren_i   => rxtx_we,
      b_wrdata_i => rxtx_wrdat,
      b_rddata_o => rxtx_rddat
    ); -- rrnet_pp_inst

  fsm_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      pp_we <= (others => '0');
      cs_d  <= cs_i;
      if cs_d = '0' and cs_i = '1' then
        if we_i = '1' then
          report "RRNET: WRITE " & to_hstring(wr_data_i) & " TO $DE" & to_hstring(addr_i);

          case unsigned(addr_i) is

            when C_PP_PTR =>
              pp_ptr(7 downto 0) <= unsigned(wr_data_i);

            when C_PP_PTR + 1 =>
              pp_ptr(15 downto 8) <= unsigned(wr_data_i);

            when C_PP_DATA_0 =>
              pp_data_0(7 downto 0) <= unsigned(wr_data_i);

            when C_PP_DATA_0 + 1 =>
              pp_data_0(15 downto 8) <= unsigned(wr_data_i);

            when C_RXTX_REG_0 =>
              rxtx_reg_0(7 downto 0) <= unsigned(wr_data_i);
              pp_wrdat               <= wr_data_i & wr_data_i;
              pp_we                  <= "01";

            when C_RXTX_REG_0 + 1 =>
              rxtx_reg_0(15 downto 8) <= unsigned(wr_data_i);
              pp_wrdat                <= wr_data_i & wr_data_i;
              pp_we                   <= "10";

            when C_TX_CMD =>
              tx_cmd(7 downto 0) <= unsigned(wr_data_i);

            when C_TX_CMD + 1 =>
              tx_cmd(15 downto 8) <= unsigned(wr_data_i);

            when C_TX_LENGTH =>
              tx_length(7 downto 0) <= unsigned(wr_data_i);

            when C_TX_LENGTH + 1 =>
              tx_length(15 downto 8) <= unsigned(wr_data_i);

            when others =>
              null;

          end case;

        else
          report "RRNET: READ FROM $DE" & to_hstring(addr_i);

          rd_data_o <= (others => '0');

          case unsigned(addr_i) is

            when C_PP_PTR =>
              rd_data_o <= std_logic_vector(pp_ptr(7 downto 0));

            when C_PP_PTR + 1 =>
              rd_data_o <= std_logic_vector(pp_ptr(15 downto 8));

            when C_PP_DATA_0 =>
              rd_data_o <= std_logic_vector(pp_rddat(7 downto 0));

            when C_PP_DATA_0 + 1 =>
              rd_data_o <= std_logic_vector(pp_rddat(15 downto 8));

            when C_RXTX_REG_0 =>
              rd_data_o <= std_logic_vector(rxtx_reg_0(7 downto 0));

            when C_RXTX_REG_0 + 1 =>
              rd_data_o <= std_logic_vector(rxtx_reg_0(15 downto 8));

            when C_TX_CMD =>
              rd_data_o <= std_logic_vector(tx_cmd(7 downto 0));

            when C_TX_CMD + 1 =>
              rd_data_o <= std_logic_vector(tx_cmd(15 downto 8));

            when C_TX_LENGTH =>
              rd_data_o <= std_logic_vector(tx_length(7 downto 0));

            when C_TX_LENGTH + 1 =>
              rd_data_o <= std_logic_vector(tx_length(15 downto 8));

            when others =>
              null;

          end case;

        end if;
      end if;

      if rst_i = '1' then
        pp_we      <= (others => '0');
        pp_ptr     <= (others => '0');
        pp_data_0  <= (others => '0');
        pp_data_1  <= (others => '0');
        rxtx_reg_0 <= (others => '0');
        rxtx_reg_1 <= (others => '0');
        tx_cmd     <= (others => '0');
        tx_length  <= (others => '0');
      end if;
    end if;
  end process fsm_proc;

end architecture rtl;

