-- ----------------------------------------------------------
-- Description: Simulates an CS8900A ethernet chip
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

  constant C_PP_PTR     : unsigned(7 downto 0)        := x"02";
  constant C_PP_DATA_0  : unsigned(7 downto 0)        := x"04";
  constant C_PP_DATA_1  : unsigned(7 downto 0)        := x"06";
  constant C_RXTX_REG_0 : unsigned(7 downto 0)        := x"08";
  constant C_RXTX_REG_1 : unsigned(7 downto 0)        := x"0A";
  constant C_TX_CMD     : unsigned(7 downto 0)        := x"0C";
  constant C_TX_LENGTH  : unsigned(7 downto 0)        := x"0E";

  signal   pp_ptr     : std_logic_vector(15 downto 0) := (others => '0');
  signal   pp_data_0  : std_logic_vector(15 downto 0) := (others => '0');
  signal   pp_data_1  : std_logic_vector(15 downto 0) := (others => '0');
  signal   rxtx_reg_0 : std_logic_vector(15 downto 0) := (others => '0');
  signal   rxtx_reg_1 : std_logic_vector(15 downto 0) := (others => '0');
  signal   tx_cmd     : std_logic_vector(15 downto 0) := (others => '0');
  signal   tx_length  : std_logic_vector(15 downto 0) := (others => '0');

  type     byte_array_type is array (natural range <>) of std_logic_vector(7 downto 0);
  signal   packet_page : byte_array_type(0 to 4095)   := (others => (others => '0'));

begin

  fsm_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if cs_i = '1' then
        if we_i = '1' then

          case unsigned(addr_i) is

            when C_PP_PTR =>
              pp_ptr(7 downto 0) <= wr_data_i;

            when C_PP_PTR + 1 =>
              pp_ptr(15 downto 8) <= wr_data_i;

            when C_RXTX_REG_0 =>
              rxtx_reg_0(7 downto 0) <= wr_data_i;

            when C_RXTX_REG_0 + 1 =>
              rxtx_reg_0(15 downto 8) <= wr_data_i;

            when C_TX_CMD =>
              tx_cmd(7 downto 0) <= wr_data_i;

            when C_TX_CMD + 1 =>
              tx_cmd(15 downto 8) <= wr_data_i;

            when C_TX_LENGTH =>
              tx_length(7 downto 0) <= wr_data_i;

            when C_TX_LENGTH + 1 =>
              tx_length(15 downto 8) <= wr_data_i;

            when others =>
              null;

          end case;

        else
          rd_data_o <= (others => '0');

          case unsigned(addr_i) is

            when C_PP_PTR =>
              rd_data_o <= pp_ptr(7 downto 0);

            when C_PP_PTR + 1 =>
              rd_data_o <= pp_ptr(15 downto 8);

            when C_RXTX_REG_0 =>
              rd_data_o <= rxtx_reg_0(7 downto 0);

            when C_RXTX_REG_0 + 1 =>
              rd_data_o <= rxtx_reg_0(15 downto 8);

            when C_TX_CMD =>
              rd_data_o <= tx_cmd(7 downto 0);

            when C_TX_CMD + 1 =>
              rd_data_o <= tx_cmd(15 downto 8);

            when C_TX_LENGTH =>
              rd_data_o <= tx_length(7 downto 0);

            when C_TX_LENGTH + 1 =>
              rd_data_o <= tx_length(15 downto 8);

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

