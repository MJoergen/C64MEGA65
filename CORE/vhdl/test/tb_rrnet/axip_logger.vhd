-- ----------------------------------------------------------------------------
-- Author     : Michael Jørgensen
-- Platform   : simulation
-------------------------------------------------------------------------------
-- Description: This dumps the AXI packet data, in byte order
-------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity axip_logger is
  generic (
    G_ENABLE        : boolean;
    G_LOG_NAME      : string(1 to 3);
    G_BYTES_PER_ROW : natural;
    G_DATA_BYTES    : natural
  );
  port (
    clk_i   : in    std_logic;
    rst_i   : in    std_logic;
    ready_i : in    std_logic;
    valid_i : in    std_logic;
    data_i  : in    std_logic_vector(G_DATA_BYTES * 8 - 1  downto 0);
    last_i  : in    std_logic;
    bytes_i : in    natural range 0 to G_DATA_BYTES
  );
end entity axip_logger;

architecture simulation of axip_logger is

begin

  logger_proc : process (clk_i)
    constant C_EMPTY_STR_V : string(1 to 2 * G_DATA_BYTES) := (others => '.');
    variable first_str_v   : string(1 to 6);
    variable last_str_v    : string(1 to 5);
    variable bytes_v       : natural range 1 to G_DATA_BYTES;
    variable first_row_v   : natural range 0 to G_DATA_BYTES / G_BYTES_PER_ROW;
    variable last_row_v    : natural range 0 to G_DATA_BYTES / G_BYTES_PER_ROW;
    variable first_idx_v   : natural range 0 to G_BYTES_PER_ROW;
  begin
    if rising_edge(clk_i) then
      if valid_i = '1' and ready_i = '1' and G_ENABLE then
        if bytes_i > 0 then
          bytes_v     := bytes_i;

          -- Determine which rows are active
          first_row_v := 0;
          last_row_v  := (bytes_i - 1)  / G_BYTES_PER_ROW;

          for row in first_row_v to last_row_v loop
            first_str_v := "      ";
            first_idx_v := 0;
            last_str_v  := "     ";

            if row = first_row_v then
              first_str_v := G_LOG_NAME & " : ";
            end if;

            if row = last_row_v then
              first_idx_v := G_BYTES_PER_ROW - bytes_i;
              if last_i = '1' then
                last_str_v := " LAST";
              end if;
            end if;

            report first_str_v &
                   C_EMPTY_STR_V(2 * G_BYTES_PER_ROW + 1 to 2 * G_BYTES_PER_ROW) &
                   to_hstring(data_i(
                   row * G_BYTES_PER_ROW * 8 + G_BYTES_PER_ROW * 8 - 1 downto
                   row * G_BYTES_PER_ROW * 8 + first_idx_v * 8)) &
                   C_EMPTY_STR_V(1 to 2 * first_idx_v) &
                   last_str_v;
          end loop;

        end if;
      end if;
    end if;
  end process logger_proc;

end architecture simulation;

