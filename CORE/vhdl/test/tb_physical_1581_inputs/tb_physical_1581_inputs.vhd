-------------------------------------------------------------------------------
-- tb_physical_1581_inputs.vhd
--
-- Self-checking GHDL testbench for physical_1581_inputs.
-- The DUT clock is 50 MHz (20 ns). To keep the run short the glitch floor is
-- overridden to 50 cycles and a scaled index period is used (low 2000 ns,
-- high 4000 ns => 6000 ns period == 300 cycles).
--
-- Checks:
--   (a) five clean index pulses produce exactly five accepted leading edges;
--       index_period_o ~= 300 cycles; index_width_o ~= 100 cycles.
--   (b) a 20-cycle (400 ns) low glitch (< 50-cycle floor) produces NO edge.
--   (c) track0_o / wprot_o / change_o follow their active-low inputs with
--       positive semantics; rdata_sync_o preserves active-low sense.
--
-- Run:  ghdl -a --std=08 physical_1581_pkg.vhd physical_1581_inputs.vhd \
--                        tb_physical_1581_inputs.vhd
--       ghdl --elab-run --std=08 tb_physical_1581_inputs --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_physical_1581_inputs is
end entity;

architecture sim of tb_physical_1581_inputs is

  constant C_FLOOR : natural := 50;   -- short glitch floor for fast sim

  signal clk    : std_logic := '0';
  signal rst    : std_logic := '1';

  signal f_index        : std_logic := '1';
  signal f_track0       : std_logic := '1';
  signal f_writeprotect : std_logic := '1';
  signal f_diskchanged  : std_logic := '1';
  signal f_rdata        : std_logic := '1';

  signal rdata_sync   : std_logic;
  signal index_active : std_logic;
  signal index_edge   : std_logic;
  signal index_period : unsigned(31 downto 0);
  signal index_width  : unsigned(31 downto 0);
  signal track0       : std_logic;
  signal wprot        : std_logic;
  signal change       : std_logic;

  signal edge_cnt : integer := 0;

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_inputs
    generic map (
      G_FDC_HZ            => 50_000_000,
      G_INDEX_MIN_LOW_CYC => C_FLOOR
    )
    port map (
      clk_i            => clk,
      rst_i            => rst,
      f_index_i        => f_index,
      f_track0_i       => f_track0,
      f_writeprotect_i => f_writeprotect,
      f_diskchanged_i  => f_diskchanged,
      f_rdata_i        => f_rdata,
      rdata_sync_o     => rdata_sync,
      index_active_o   => index_active,
      index_edge_o     => index_edge,
      index_period_o   => index_period,
      index_width_o    => index_width,
      track0_o         => track0,
      wprot_o          => wprot,
      change_o         => change
    );

  -- Count accepted leading edges.
  edge_counter : process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        edge_cnt <= 0;
      elsif index_edge = '1' then
        edge_cnt <= edge_cnt + 1;
      end if;
    end if;
  end process;

  -- Watchdog: fail loudly instead of hanging.
  watchdog : process
  begin
    wait for 2 ms;
    report "TIMEOUT" severity failure;
  end process;

  stim : process
  begin
    -- Reset.
    rst <= '1';
    wait for 200 ns;
    rst <= '0';
    wait for 100 ns;

    ---------------------------------------------------------------------------
    -- (a) Five clean index pulses.
    ---------------------------------------------------------------------------
    for i in 1 to 5 loop
      f_index <= '0';
      wait for 2000 ns;      -- low  = 100 cycles (> 50 floor)
      f_index <= '1';
      wait for 4000 ns;      -- high = 200 cycles ; period 300 cycles
    end loop;
    wait for 1000 ns;        -- settle

    assert edge_cnt = 5
      report "T(a) FAIL: expected 5 accepted edges, got " & integer'image(edge_cnt)
      severity error;
    report "T(a) OK: 5 accepted edges";

    assert to_integer(index_period) >= 297 and to_integer(index_period) <= 303
      report "T(a) FAIL: index_period = " & integer'image(to_integer(index_period))
             & " (expected ~300)"
      severity error;
    report "T(a) OK: index_period = " & integer'image(to_integer(index_period));

    assert to_integer(index_width) >= 97 and to_integer(index_width) <= 103
      report "T(a) FAIL: index_width = " & integer'image(to_integer(index_width))
             & " (expected ~100)"
      severity error;
    report "T(a) OK: index_width = " & integer'image(to_integer(index_width));

    ---------------------------------------------------------------------------
    -- (b) Sub-floor glitch: 20 cycles (400 ns) low -> NO new edge.
    ---------------------------------------------------------------------------
    f_index <= '0';
    wait for 400 ns;         -- 20 cycles < 50 floor
    f_index <= '1';
    wait for 2000 ns;

    assert edge_cnt = 5
      report "T(b) FAIL: glitch produced an edge, edge_cnt = " & integer'image(edge_cnt)
      severity error;
    report "T(b) OK: glitch rejected, edge_cnt still 5";

    ---------------------------------------------------------------------------
    -- (c) Static status polarity + rdata sense.
    ---------------------------------------------------------------------------
    f_track0 <= '0'; f_writeprotect <= '0'; f_diskchanged <= '0'; f_rdata <= '0';
    wait for 200 ns;
    assert track0 = '1' and wprot = '1' and change = '1'
      report "T(c) FAIL: active-low asserted not seen as '1'"
      severity error;
    assert rdata_sync = '0'
      report "T(c) FAIL: rdata_sync did not preserve active-low '0'"
      severity error;
    report "T(c) OK: active-low inputs -> positive '1'; rdata sense preserved";

    f_track0 <= '1'; f_writeprotect <= '1'; f_diskchanged <= '1'; f_rdata <= '1';
    wait for 200 ns;
    assert track0 = '0' and wprot = '0' and change = '0'
      report "T(c) FAIL: deasserted active-low not seen as '0'"
      severity error;
    assert rdata_sync = '1'
      report "T(c) FAIL: rdata_sync did not follow high"
      severity error;
    report "T(c) OK: deasserted inputs -> '0'";

    report "physical_1581_inputs: ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
