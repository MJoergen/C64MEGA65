-------------------------------------------------------------------------------
-- tb_physical_1581_rdfifo.vhd
--
-- Self-checking GHDL testbench for physical_1581_rdfifo.
-- Two async, relatively-prime clock periods: 20 ns write, 62 ns read.
--
-- Phase 1 (wr_level_o sanity, issue #90 round 10): with the reader held off,
-- the writer pushes 5 bytes and asserts the write-side occupancy tap rises to
-- exactly 5; the reader is then released, drains them, and the tap must fall
-- back to 0 (after the read Gray pointer crosses the sync).
--
-- Phase 2 (streaming): the writer pushes 200 more incrementing bytes
-- (respecting wr_full_o); the reader pops all 205 (respecting rd_empty_o) and
-- asserts each popped byte equals the expected running value and that they
-- come out in order; finally the level must read 0 again and can never have
-- exceeded the FIFO depth.
--
-- Run:  ghdl -a --std=08 physical_1581_rdfifo.vhd tb_physical_1581_rdfifo.vhd
--       ghdl --elab-run --std=08 tb_physical_1581_rdfifo --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_physical_1581_rdfifo is
end entity;

architecture sim of tb_physical_1581_rdfifo is

  constant C_N_PRE   : integer := 5;    -- phase-1 bytes (level check)
  constant C_N_BYTES : integer := 205;  -- total bytes through the FIFO

  signal wr_clk   : std_logic := '0';
  signal rd_clk   : std_logic := '0';
  signal wr_rst   : std_logic := '1';
  signal rd_rst   : std_logic := '1';

  signal wr_en    : std_logic := '0';
  signal wr_data  : unsigned(7 downto 0) := (others => '0');
  signal wr_full  : std_logic;
  signal wr_level : unsigned(9 downto 0);

  signal rd_en    : std_logic := '0';
  signal rd_data  : unsigned(7 downto 0);
  signal rd_empty : std_logic;

  signal reader_go   : boolean := false;
  signal reader_done : boolean := false;

begin

  wr_clk <= not wr_clk after 10 ns;   -- 20 ns period
  rd_clk <= not rd_clk after 31 ns;   -- 62 ns period

  dut : entity work.physical_1581_rdfifo
    generic map (
      G_AW => 5   -- depth 32
    )
    port map (
      wr_clk_i   => wr_clk,
      wr_rst_i   => wr_rst,
      wr_en_i    => wr_en,
      wr_data_i  => wr_data,
      wr_full_o  => wr_full,
      wr_level_o => wr_level,
      rd_clk_i   => rd_clk,
      rd_rst_i   => rd_rst,
      rd_en_i    => rd_en,
      rd_data_o  => rd_data,
      rd_empty_o => rd_empty
    );

  -- Common reset release.
  rst_gen : process
  begin
    wr_rst <= '1';
    rd_rst <= '1';
    wait for 200 ns;
    wr_rst <= '0';
    rd_rst <= '0';
    wait;
  end process;

  -- Watchdog.
  watchdog : process
  begin
    wait for 2 ms;
    report "TIMEOUT" severity failure;
  end process;

  ---------------------------------------------------------------------------
  -- Level invariant: the occupancy tap can never exceed the FIFO depth.
  ---------------------------------------------------------------------------
  level_bound : process (wr_clk)
  begin
    if rising_edge(wr_clk) then
      assert to_integer(wr_level) <= 32
        report "wr_level_o = " & integer'image(to_integer(wr_level))
               & " exceeds depth 32" severity error;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Writer: phase 1 = 5 bytes with the reader off + level checks;
  -- phase 2 = 200 more bytes, one per available slot.
  ---------------------------------------------------------------------------
  writer : process
  begin
    wr_en <= '0';
    wait until wr_rst = '0';

    -- Phase 1: reader held off; level must rise with each write.
    for n in 0 to C_N_PRE - 1 loop
      loop
        wait until rising_edge(wr_clk);
        exit when wr_full = '0';
      end loop;
      wr_en   <= '1';
      wr_data <= to_unsigned(n mod 256, 8);
      wait until rising_edge(wr_clk);
      wr_en   <= '0';
    end loop;
    wait for 200 ns;                     -- settle (writes count immediately)
    assert to_integer(wr_level) = C_N_PRE
      report "wr_level_o after " & integer'image(C_N_PRE) & " writes = "
             & integer'image(to_integer(wr_level)) severity error;
    report "wr_level_o = " & integer'image(C_N_PRE) & " with reader stalled -- OK";

    -- Release the reader; level must fall back to 0 once the read Gray
    -- pointer has crossed the 2-FF sync into the write domain.
    reader_go <= true;
    wait until rising_edge(wr_clk) and to_integer(wr_level) = 0 for 10 us;
    assert to_integer(wr_level) = 0
      report "wr_level_o did not return to 0 after drain (= "
             & integer'image(to_integer(wr_level)) & ")" severity error;
    report "wr_level_o back to 0 after drain -- OK";

    -- Phase 2: stream the remaining bytes.
    for n in C_N_PRE to C_N_BYTES - 1 loop
      loop
        wait until rising_edge(wr_clk);
        exit when wr_full = '0';
      end loop;
      wr_en   <= '1';
      wr_data <= to_unsigned(n mod 256, 8);
      wait until rising_edge(wr_clk);
      wr_en   <= '0';
    end loop;

    -- Final: after the reader finished everything, the level must be 0 again.
    wait until reader_done for 2 ms;
    assert reader_done report "reader never finished" severity failure;
    wait for 500 ns;                     -- let the last read pointer sync over
    assert to_integer(wr_level) = 0
      report "final wr_level_o = " & integer'image(to_integer(wr_level))
             & ", expected 0" severity error;
    report "physical_1581_rdfifo: ALL " & integer'image(C_N_BYTES)
           & " BYTES IN ORDER + LEVEL TAP SANE -- TEST PASSED";
    finish;
  end process;

  ---------------------------------------------------------------------------
  -- Reader: held off until phase 1's level check, then pops all bytes,
  -- verifying order and value.
  ---------------------------------------------------------------------------
  reader : process
    variable expected : integer := 0;
  begin
    rd_en <= '0';
    wait until rd_rst = '0';
    wait until reader_go;
    while expected < C_N_BYTES loop
      -- Wait for data.
      loop
        wait until rising_edge(rd_clk);
        exit when rd_empty = '0';
      end loop;
      -- First-word-fall-through: rd_data_o shows the head now.
      assert rd_data = to_unsigned(expected mod 256, 8)
        report "MISMATCH at index " & integer'image(expected)
               & ": got " & integer'image(to_integer(rd_data))
               & " expected " & integer'image(expected mod 256)
        severity error;
      rd_en <= '1';
      wait until rising_edge(rd_clk);
      rd_en <= '0';
      expected := expected + 1;
    end loop;
    reader_done <= true;
    wait;
  end process;

end architecture sim;
