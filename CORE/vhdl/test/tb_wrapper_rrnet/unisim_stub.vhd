-- Minimal stand-in for the Xilinx UNISIM primitives that eth_wrapper.vhd
-- instantiates, so the wrapper can be simulated with GHDL without Vivado.
-- ODDR is an output DDR register; it plays no part in the receive-path logic
-- under test, so a behavioural model is sufficient and does not weaken the
-- experiment.

library ieee;
  use ieee.std_logic_1164.all;

entity oddr is
  generic (
    DDR_CLK_EDGE : string    := "OPPOSITE_EDGE";
    INIT         : bit       := '0';
    SRTYPE       : string    := "SYNC"
  );
  port (
    q  : out   std_logic;
    c  : in    std_logic;
    ce : in    std_logic;
    d1 : in    std_logic;
    d2 : in    std_logic;
    r  : in    std_logic;
    s  : in    std_logic
  );
end entity oddr;

architecture behav of oddr is
  signal q1 : std_logic := '0';
  signal q2 : std_logic := '0';
begin
  process (c)
  begin
    if rising_edge(c) then
      if r = '1' then q1 <= '0'; elsif ce = '1' then q1 <= d1; end if;
    end if;
  end process;
  process (c)
  begin
    if falling_edge(c) then
      if r = '1' then q2 <= '0'; elsif ce = '1' then q2 <= d2; end if;
    end if;
  end process;
  q <= q1 when c = '1' else q2;
end architecture behav;

----------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;

package vcomponents is

  component oddr is
    generic (
      DDR_CLK_EDGE : string := "OPPOSITE_EDGE";
      INIT         : bit    := '0';
      SRTYPE       : string := "SYNC"
    );
    port (
      q  : out   std_logic;
      c  : in    std_logic;
      ce : in    std_logic;
      d1 : in    std_logic;
      d2 : in    std_logic;
      r  : in    std_logic;
      s  : in    std_logic
    );
  end component oddr;

end package vcomponents;
