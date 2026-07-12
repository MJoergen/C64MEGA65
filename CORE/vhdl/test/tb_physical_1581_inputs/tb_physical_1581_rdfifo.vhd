-------------------------------------------------------------------------------
-- tb_physical_1581_rdfifo.vhd
--
-- Self-checking GHDL testbench for physical_1581_rdfifo.
-- Two async, relatively-prime clock periods: 20 ns write, 62 ns read. A writer
-- pushes 200 incrementing bytes (respecting wr_full_o); a reader pops them
-- (respecting rd_empty_o) and asserts each popped byte equals the expected
-- running value, and that exactly 200 come out in order.
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

  constant C_N_BYTES : integer := 200;

  signal wr_clk   : std_logic := '0';
  signal rd_clk   : std_logic := '0';
  signal wr_rst   : std_logic := '1';
  signal rd_rst   : std_logic := '1';

  signal wr_en    : std_logic := '0';
  signal wr_data  : unsigned(7 downto 0) := (others => '0');
  signal wr_full  : std_logic;

  signal rd_en    : std_logic := '0';
  signal rd_data  : unsigned(7 downto 0);
  signal rd_empty : std_logic;

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
  -- Writer: push 200 incrementing bytes, one per available slot.
  ---------------------------------------------------------------------------
  writer : process
  begin
    wr_en <= '0';
    wait until wr_rst = '0';
    for n in 0 to C_N_BYTES - 1 loop
      -- Wait for space.
      loop
        wait until rising_edge(wr_clk);
        exit when wr_full = '0';
      end loop;
      wr_en   <= '1';
      wr_data <= to_unsigned(n mod 256, 8);
      wait until rising_edge(wr_clk);
      wr_en   <= '0';
    end loop;
    wait;
  end process;

  ---------------------------------------------------------------------------
  -- Reader: pop 200 bytes, verify order and value.
  ---------------------------------------------------------------------------
  reader : process
    variable expected : integer := 0;
  begin
    rd_en <= '0';
    wait until rd_rst = '0';
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

    report "physical_1581_rdfifo: ALL " & integer'image(C_N_BYTES)
           & " BYTES IN ORDER -- TEST PASSED";
    finish;
  end process;

end architecture sim;
