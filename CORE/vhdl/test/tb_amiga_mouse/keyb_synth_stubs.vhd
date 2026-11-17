----------------------------------------------------------------------------------------------------
-- Amiga mouse bench (GitHub issue #190): stubs of the two sub-entities of m2m_keyb for ghdl synth
--
-- ghdl synth rejects the real mega65kbd_to_matrix (an integer port of range 0 to 9 on a formal of
-- range 0 to 15). These stubs have the ports that m2m_keyb connects, with the ranges of its
-- signals, and drive every output from a register of an input, so that no logic of m2m_keyb is
-- optimized away. run.sh counts the flip-flops of m2m_keyb itself, without these stubs.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mega65kbd_to_matrix is
   port (
      ioclock           : in  std_logic;
      clock_frequency   : in  natural;
      powerled_steady   : in  std_logic;
      powerled_col      : in  std_logic_vector(23 downto 0);
      driveled_steady   : in  std_logic;
      driveled_blinking : in  std_logic;
      driveled_col      : in  std_logic_vector(23 downto 0);
      matrix_col        : out std_logic_vector(7 downto 0);
      matrix_col_idx    : in  integer range 0 to 9;
      capslock_out      : out std_logic;
      kio8              : out std_logic;
      kio9              : out std_logic;
      kio10             : in  std_logic
   );
end entity mega65kbd_to_matrix;

architecture stub of mega65kbd_to_matrix is
begin
   process (ioclock)
   begin
      if rising_edge(ioclock) then
         matrix_col   <= (7 downto 0 => kio10) xor std_logic_vector(to_unsigned(matrix_col_idx, 8));
         capslock_out <= kio10 xor driveled_blinking;
         kio8         <= powerled_steady xor driveled_steady;
         kio9         <= (xor powerled_col) xor (xor driveled_col);
      end if;
   end process;
end architecture stub;

library ieee;
use ieee.std_logic_1164.all;

entity matrix_to_keynum is
   generic (
      scan_frequency         : integer := 1000
   );
   port (
      clk                    : in  std_logic;
      clock_frequency        : in  natural;
      reset_in               : in  std_logic;
      matrix_col             : in  std_logic_vector(7 downto 0);
      matrix_col_idx         : in  integer range 0 to 9;
      m65_key_num            : out integer range 0 to 79;
      m65_key_status_n       : out std_logic;
      suppress_key_glitches  : in  std_logic;
      suppress_key_retrigger : in  std_logic;
      bucky_key              : out std_logic_vector(6 downto 0)
   );
end entity matrix_to_keynum;

architecture stub of matrix_to_keynum is
   signal n : integer range 0 to 79 := 0;
begin
   process (clk)
   begin
      if rising_edge(clk) then
         if n = 79 then
            n <= 0;
         else
            n <= n + 1;
         end if;
         m65_key_status_n <= matrix_col(0) xor matrix_col(7) xor reset_in;
         bucky_key        <= matrix_col(6 downto 0);
      end if;
   end process;
   m65_key_num <= n;
end architecture stub;
