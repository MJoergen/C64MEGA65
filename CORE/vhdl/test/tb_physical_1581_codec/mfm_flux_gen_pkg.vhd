-------------------------------------------------------------------------------
-- mfm_flux_gen_pkg.vhd   (simulation only)
--
-- Synthetic DD-MFM flux generator for physical_1581 codec testbenches. Drives an
-- active-low RDATA signal: one ~0.4 us low pulse at every MFM channel-bit "1"
-- (flux transition), channel half-cells 2 us apart, so leading-edge-to-leading-
-- edge gaps come out as the valid 4/6/8 us intervals.
--
-- Encoding: standard IBM MFM. For an ordinary data byte, each data bit d (MSB
-- first) is preceded by clock bit c = NOT(prev_data OR d); transitions occur at
-- half-cells whose channel bit is '1'. Address-mark A1 uses the fixed raw word
-- 0x4489 (missing clock) whose gap sequence is long,med,long,med = the sync
-- pattern the decoder locks onto; after A1, prev_data = 1 (A1 data = 0xA1).
--
-- Verified analytically against the decoder's "10011001" sync detection.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mfm_flux_gen_pkg is

  constant MFM_HALF_CELL : time := 2 us;      -- clock/data half-cell
  constant MFM_LOW_WIDTH : time := 400 ns;    -- RDATA active-low pulse (in 0.15..0.8 us)
  constant MFM_A1_RAW    : std_logic_vector(15 downto 0) := x"4489";

  -- Emit one MFM channel half-cell: a transition pulse when ch='1', else idle.
  procedure mfm_halfcell(signal rdata : out std_logic; ch : in std_logic);

  -- Emit one ordinary data byte (MSB first), updating prev_data.
  procedure mfm_byte(signal rdata : out std_logic;
                     b            : in  unsigned(7 downto 0);
                     prev_data    : inout std_logic);

  -- Emit a missing-clock A1 sync byte; leaves prev_data = '1'.
  procedure mfm_a1(signal rdata : out std_logic; prev_data : inout std_logic);

  -- Emit one data byte like mfm_byte, but inject a RUNT double edge right
  -- after the byte's first flux transition: legit pulse, 600 ns idle, then a
  -- 200 ns spurious low pulse. Leading-edge distance legit->runt = 1000 ns =
  -- 50 controller cycles, far below C_GAP_GLITCH (120), so the gaps stage must
  -- merge it into the following gap (which it shortens by the same 1000 ns --
  -- WITHOUT the runt filter that remainder falls below the shortest valid
  -- window and kills the field via a class-11 gap error).
  procedure mfm_byte_runt(signal rdata : out std_logic;
                          b            : in  unsigned(7 downto 0);
                          prev_data    : inout std_logic);

  -- Emit N copies of a byte (e.g. gap 0x4E or 0x00 preamble).
  procedure mfm_bytes(signal rdata : out std_logic;
                      b            : in  unsigned(7 downto 0);
                      n            : in  natural;
                      prev_data    : inout std_logic);

  -- CRC-16/CCITT-FALSE bytewise update, bit-identical to physical_1581_crc.
  function crc16_update(crc : unsigned(15 downto 0); b : unsigned(7 downto 0))
    return unsigned;

end package mfm_flux_gen_pkg;

package body mfm_flux_gen_pkg is

  procedure mfm_halfcell(signal rdata : out std_logic; ch : in std_logic) is
  begin
    if ch = '1' then
      rdata <= '0';
      wait for MFM_LOW_WIDTH;
      rdata <= '1';
      wait for MFM_HALF_CELL - MFM_LOW_WIDTH;
    else
      rdata <= '1';
      wait for MFM_HALF_CELL;
    end if;
  end procedure;

  procedure mfm_byte(signal rdata : out std_logic;
                     b            : in  unsigned(7 downto 0);
                     prev_data    : inout std_logic) is
    variable d : std_logic;
    variable c : std_logic;
  begin
    for i in 7 downto 0 loop
      d := b(i);
      c := not (prev_data or d);   -- MFM clock rule
      mfm_halfcell(rdata, c);      -- clock half-cell
      mfm_halfcell(rdata, d);      -- data half-cell
      prev_data := d;
    end loop;
  end procedure;

  procedure mfm_a1(signal rdata : out std_logic; prev_data : inout std_logic) is
  begin
    for i in 15 downto 0 loop      -- MSB channel bit first in time
      mfm_halfcell(rdata, MFM_A1_RAW(i));
    end loop;
    prev_data := '1';              -- A1 data = 0xA1, last data bit = 1
  end procedure;

  procedure mfm_byte_runt(signal rdata : out std_logic;
                          b            : in  unsigned(7 downto 0);
                          prev_data    : inout std_logic) is
    variable d        : std_logic;
    variable c        : std_logic;
    variable injected : boolean := false;

    -- like mfm_halfcell, but appends the runt double edge after the pulse
    procedure runt_halfcell(signal rd : out std_logic) is
    begin
      rd <= '0';                                 -- the legitimate transition
      wait for MFM_LOW_WIDTH;                    -- 400 ns low
      rd <= '1';
      wait for 600 ns;                           -- runt leading-edge distance: 1000 ns
      rd <= '0';                                 -- the RUNT (spurious) transition
      wait for 200 ns;
      rd <= '1';
      wait for MFM_HALF_CELL - MFM_LOW_WIDTH - 600 ns - 200 ns;
    end procedure;
  begin
    for i in 7 downto 0 loop
      d := b(i);
      c := not (prev_data or d);   -- MFM clock rule
      if c = '1' and not injected then
        runt_halfcell(rdata); injected := true;
      else
        mfm_halfcell(rdata, c);    -- clock half-cell
      end if;
      if d = '1' and not injected then
        runt_halfcell(rdata); injected := true;
      else
        mfm_halfcell(rdata, d);    -- data half-cell
      end if;
      prev_data := d;
    end loop;
    assert injected report "mfm_byte_runt: byte had no flux transition" severity failure;
  end procedure;

  procedure mfm_bytes(signal rdata : out std_logic;
                      b            : in  unsigned(7 downto 0);
                      n            : in  natural;
                      prev_data    : inout std_logic) is
  begin
    for k in 1 to n loop
      mfm_byte(rdata, b, prev_data);
    end loop;
  end procedure;

  function crc16_update(crc : unsigned(15 downto 0); b : unsigned(7 downto 0))
    return unsigned is
    variable v  : unsigned(15 downto 0) := crc;
    variable nv : unsigned(15 downto 0);
    variable fb : std_logic;
  begin
    for i in 7 downto 0 loop
      fb := b(i) xor v(15);
      nv := v(14 downto 0) & '0';   -- shift left one
      nv(0)  := fb;
      nv(5)  := v(4)  xor fb;
      nv(12) := v(11) xor fb;
      v      := nv;
    end loop;
    return v;
  end function;

end package body mfm_flux_gen_pkg;
