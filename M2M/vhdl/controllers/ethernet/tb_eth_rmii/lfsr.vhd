-- ---------------------------------------------------------------------------------------
-- Description: A simple Linear Feedback Shift Register
--
-- SPDX-License-Identifier: MIT
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity lfsr is
  generic (
    G_SEED  : std_logic_vector(63 downto 0) := (others => '1');
    G_TAPS  : std_logic_vector(63 downto 0);
    G_WIDTH : natural
  );
  port (
    clk_i    : in    std_logic;
    rst_i    : in    std_logic;
    update_i : in    std_logic;
    output_o : out   std_logic_vector(G_WIDTH - 1 downto 0)
  );
end entity lfsr;

architecture rtl of lfsr is

  constant C_UPDATE : std_logic_vector(G_WIDTH - 1 downto 0) := G_TAPS(G_WIDTH - 2 downto 0) & "1";

  signal   data : std_logic_vector(G_WIDTH - 1 downto 0);

begin

  lfsr_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if update_i = '1' then
        data <= data(G_WIDTH - 2 downto 0) & "0";
        if data(G_WIDTH - 1) = '1' then
          data <= (data(G_WIDTH - 2 downto 0) & "0") xor C_UPDATE;
        end if;
      end if;

      if rst_i = '1' then
        data <= G_SEED(G_WIDTH - 1 downto 0);
      end if;
    end if;
  end process lfsr_proc;

  output_o <= data;

end architecture rtl;

