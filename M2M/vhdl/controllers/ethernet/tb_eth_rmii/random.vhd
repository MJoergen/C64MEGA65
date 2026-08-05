-- ---------------------------------------------------------------------------------------
-- Description: A random number generator.
--
-- SPDX-License-Identifier: MIT
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity random is
  generic (
    G_SEED : std_logic_vector(63 downto 0) := X"01234567FEDCBA98"
  );
  port (
    clk_i    : in    std_logic;
    rst_i    : in    std_logic;
    update_i : in    std_logic;
    output_o : out   std_logic_vector(63 downto 0)
  );
end entity random;

architecture rtl of random is

  -- See https://users.ece.cmu.edu/~koopman/lfsr/64.txt
  constant C_TAPS1 : std_logic_vector(63 downto 0) := X"80000000000019E2";
  constant C_TAPS2 : std_logic_vector(63 downto 0) := X"80000000000011E5";

  pure function reverse (
    arg : std_logic_vector
  ) return std_logic_vector is
    variable res_v : std_logic_vector(arg'range);
  begin
    --
    for i in arg'low to arg'high loop
      res_v(arg'high - i) := arg(i);
    end loop;

    return res_v;
  end function reverse;

  signal   random1 : std_logic_vector(63 downto 0);
  signal   random2 : std_logic_vector(63 downto 0);

begin

  lfsr1_inst : entity work.lfsr
    generic map (
      G_SEED  => G_SEED,
      G_WIDTH => 64,
      G_TAPS  => C_TAPS1
    )
    port map (
      clk_i    => clk_i,
      rst_i    => rst_i,
      update_i => update_i,
      output_o => random1
    ); -- lfsr1_inst

  lfsr2_inst : entity work.lfsr
    generic map (
      G_SEED  => not G_SEED,
      G_WIDTH => 64,
      G_TAPS  => C_TAPS2
    )
    port map (
      clk_i    => clk_i,
      rst_i    => rst_i,
      update_i => update_i,
      output_o => random2
    ); -- lfsr2_inst

  output_o <= random1 + reverse(random2);

end architecture rtl;

