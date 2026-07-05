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
    clk_i     : in    std_logic;
    rst_i     : in    std_logic;

    -- CPU interface
    cs_i      : in    std_logic; -- Connect to IO1 ($DExx)
    addr_i    : in    std_logic_vector(7 downto 0);
    we_i      : in    std_logic;
    wr_data_i : in    std_logic_vector(7 downto 0);
    rd_data_o : out   std_logic_vector(7 downto 0)
  );
end entity rrnet;

architecture rtl of rrnet is

  constant C_PP_PTR     : unsigned(7 downto 0)      := x"02";
  constant C_PP_DATA_0  : unsigned(7 downto 0)      := x"04";
  constant C_PP_DATA_1  : unsigned(7 downto 0)      := x"06";
  constant C_RXTX_REG_0 : unsigned(7 downto 0)      := x"08";
  constant C_RXTX_REG_1 : unsigned(7 downto 0)      := x"0A";
  constant C_TX_CMD     : unsigned(7 downto 0)      := x"0C";
  constant C_TX_LENGTH  : unsigned(7 downto 0)      := x"0E";

  signal   pp_ptr     : unsigned(15 downto 0)       := (others => '0');
  signal   pp_data_0  : unsigned(15 downto 0)       := (others => '0');
  signal   pp_data_1  : unsigned(15 downto 0)       := (others => '0');
  signal   rxtx_reg_0 : unsigned(15 downto 0)       := (others => '0');
  signal   rxtx_reg_1 : unsigned(15 downto 0)       := (others => '0');
  signal   tx_cmd     : unsigned(15 downto 0)       := (others => '0');
  signal   tx_length  : unsigned(15 downto 0)       := (others => '0');

  signal   pp_we    : std_logic;
  signal   pp_wrdat : std_logic_vector(15 downto 0);
  signal   pp_rddat : std_logic_vector(15 downto 0);


  -- This holds the entire 2k words of PacketPage memory.
  type     byte_array_type is array (natural range <>) of std_logic_vector(15 downto 0);

  -- This generates the reset-value of the 2k words PacketPage memory.

  pure function get_packet_page_init return byte_array_type is
    variable ret_v : byte_array_type(0 to 2047) := (others => (others => '0'));
  begin
    -- EISA registration number for Crystal Semiconductor
    ret_v(0) := x"630E";
    -- Product ID and Revision number
    ret_v(1) := x"0700";
    return ret_v;
  end function get_packet_page_init;

  signal   packet_page : byte_array_type(0 to 2047) := get_packet_page_init;

begin

  pp_proc : process (clk_i)
  begin
    -- Note: Deliberately using falling edge
    if falling_edge(clk_i) then
      if pp_we = '1' then
        packet_page(to_integer(pp_ptr)) <= pp_wrdat;
      end if;
      pp_rddat <= packet_page(to_integer(pp_ptr));
    end if;
  end process pp_proc;

  fsm_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if cs_i = '1' then
        if we_i = '1' then

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

            when C_RXTX_REG_0 + 1 =>
              rxtx_reg_0(15 downto 8) <= unsigned(wr_data_i);

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

