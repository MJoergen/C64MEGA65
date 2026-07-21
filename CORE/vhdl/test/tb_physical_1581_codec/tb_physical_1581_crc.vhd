-------------------------------------------------------------------------------
-- tb_physical_1581_crc.vhd
--
-- Self-checking GHDL testbench for physical_1581_crc.
-- Verifies CRC-16/CCITT-FALSE known vectors and the zero-residue property:
--   * A1 A1 A1            -> 0xCDB4
--   * A1 A1 A1 FE         -> 0xB230
--   * A1 A1 A1 FB         -> 0xE295
--   * "123456789"         -> 0x29B1   (standard CCITT-FALSE check value)
--   * field + stored CRC  -> 0x0000   (zero residue for ID and data phases)
--
-- Run:  ghdl -a --std=08 physical_1581_pkg.vhd physical_1581_crc.vhd tb_physical_1581_crc.vhd
--       ghdl -e --std=08 tb_physical_1581_crc
--       ghdl -r --std=08 tb_physical_1581_crc
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;

entity tb_physical_1581_crc is
end entity;

architecture sim of tb_physical_1581_crc is
  signal clk       : std_logic := '0';
  signal crc_byte  : unsigned(7 downto 0) := (others => '0');
  signal crc_feed  : std_logic := '0';
  signal crc_reset : std_logic := '0';
  signal crc_ready : std_logic;
  signal crc_value : unsigned(15 downto 0);

  function hs(v : unsigned(15 downto 0)) return string is
  begin
    return to_hstring(std_logic_vector(v));
  end function;
begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_crc
    port map (
      clk_i       => clk,
      crc_byte_i  => crc_byte,
      crc_feed_i  => crc_feed,
      crc_reset_i => crc_reset,
      crc_ready_o => crc_ready,
      crc_value_o => crc_value
    );

  stim : process
    procedure do_reset is
    begin
      crc_reset <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      crc_reset <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure feed(b : unsigned(7 downto 0)) is
    begin
      -- wait for the engine to be idle
      wait until rising_edge(clk) and crc_ready = '1';
      crc_feed <= '1';
      crc_byte <= b;
      wait until rising_edge(clk);
      crc_feed <= '0';
      -- 1 load + 8 shift + settle; 12 cycles is comfortably enough
      for k in 0 to 11 loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    variable idcrc : unsigned(15 downto 0);
  begin
    wait until rising_edge(clk);

    -- T1: A1 A1 A1 -> CDB4
    do_reset;
    feed(x"A1"); feed(x"A1"); feed(x"A1");
    assert crc_value = C_CRC_AFTER_3XA1
      report "T1 FAIL: A1A1A1 = " & hs(crc_value) & " (expected CDB4)" severity error;
    report "T1 OK: A1A1A1 = " & hs(crc_value);

    -- T2: A1 A1 A1 FE -> B230
    do_reset;
    feed(x"A1"); feed(x"A1"); feed(x"A1"); feed(x"FE");
    assert crc_value = x"B230"
      report "T2 FAIL: +FE = " & hs(crc_value) & " (expected B230)" severity error;
    report "T2 OK: +FE = " & hs(crc_value);

    -- T3: A1 A1 A1 FB -> E295
    do_reset;
    feed(x"A1"); feed(x"A1"); feed(x"A1"); feed(x"FB");
    assert crc_value = x"E295"
      report "T3 FAIL: +FB = " & hs(crc_value) & " (expected E295)" severity error;
    report "T3 OK: +FB = " & hs(crc_value);

    -- T4: "123456789" -> 29B1 (CCITT-FALSE check value)
    do_reset;
    for i in 0 to 8 loop
      feed(to_unsigned(character'pos('1') + i, 8));
    end loop;
    assert crc_value = x"29B1"
      report "T4 FAIL: check = " & hs(crc_value) & " (expected 29B1)" severity error;
    report "T4 OK: check-string = " & hs(crc_value);

    -- T5: zero residue for an ID field: A1A1A1 FE 00 00 01 02 + its stored CRC.
    do_reset;
    feed(x"A1"); feed(x"A1"); feed(x"A1"); feed(x"FE");
    feed(x"00"); feed(x"00"); feed(x"01"); feed(x"02");
    idcrc := crc_value;                 -- generated ID CRC
    feed(idcrc(15 downto 8));           -- stored CRC high
    feed(idcrc(7 downto 0));            -- stored CRC low
    assert crc_value = x"0000"
      report "T5 FAIL: residue = " & hs(crc_value) & " (expected 0000)" severity error;
    report "T5 OK: ID(FE 00 00 01 02) CRC = " & hs(idcrc) & ", residue = " & hs(crc_value);

    report "physical_1581_crc: ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
