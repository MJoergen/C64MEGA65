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
  -- after the byte's first flux transition: the legitimate low pulse is split
  -- by a 60 ns glitchy high spike, so a spurious second falling edge follows
  -- the legit one after 160 ns = 8 controller cycles -- below C_GAP_GLITCH
  -- (16, round 11), modeling the GAP_MIN = 0x0001 hardware evidence. The gaps
  -- stage must merge it (runt_o pulse, no gap emitted), so the decoder sees
  -- only clean full-length gaps -- WITHOUT the filter the split gap pair falls
  -- below the shortest valid window and kills the field via a class-11 error.
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

  -----------------------------------------------------------------------------
  -- Write-splice junk model (issue #90 round 13)
  --
  -- Models the garbage flux a write splice leaves on the medium (write-gate
  -- turn-off transient + partially erased residue of earlier writes + AGC/
  -- read-channel settling): a burst of gaps with junk lengths, including
  -- fluxless stretches. Two profiles, both driven by a deterministic 16-bit
  -- LFSR (no real randomness):
  --
  --   * junk_splice_rand: 28..36 pseudo-random gaps spanning [130..480]
  --     cycles plus two fluxless stretches. Naive splice garbage; it turned
  --     out to be TOO TAME to reproduce the round-12 hardware failure (all
  --     classifiers survive it: enough gaps land outside every acceptance
  --     profile, so the pipeline keeps re-syncing loudly).
  --
  --   * junk_splice_chain: the profile that DOES reproduce the hardware
  --     failure gap-exact, derived from what the round-12 acceptance uniquely
  --     swallows: random junk, a fluxless stretch, a run of ~205-cycle
  --     short-ish gaps (walks the round-12 estimate up a little, exactly what
  --     coherent splice residue does), then an alternating ~446/~344 chain --
  --     which the no-dead-band round-12 classifier reads as the A1 sync gap
  --     pattern long,med,long,med (false syncs every two gaps; three arm the
  --     decoder) -- and a 224/446 tail whose decoded bits spell the FB data
  --     mark, opening a bogus 512-byte data field that eats the following
  --     sector. The OLD fixed windows reject every chain element loudly
  --     (446..450 is beyond C_GAP_LONG_HI = 445; 344 is inside the 343..354
  --     dead-band), which is precisely why round 11 read the post-splice
  --     sector fine and round 12 deterministically lost it.
  --
  -- The last entry of a profile is the boundary gap to the first real flux
  -- transition that follows the junk (the caller emits it as the final wait).
  -----------------------------------------------------------------------------
  type nat_arr is array (natural range <>) of natural;
  constant JUNK_MAX : natural := 63;
  type junk_arr_t is record
    cnt : natural;                        -- number of valid entries in g
    g   : nat_arr(0 to JUNK_MAX);         -- gap lengths in 50 MHz cycles
  end record;

  -- one step of a maximal 16-bit Fibonacci LFSR (x^16 + x^14 + x^13 + x^11 + 1)
  function lfsr16_step(x : natural) return natural;

  function junk_splice_rand (seed : natural) return junk_arr_t;
  function junk_splice_chain(seed : natural) return junk_arr_t;

  -- Emit a junk burst on RDATA in the time domain (one low pulse per entry,
  -- then the entry's gap). The caller's next flux transition closes the final
  -- (boundary) gap.
  procedure mfm_splice_junk(signal rdata : out std_logic; j : in junk_arr_t);

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

    -- like mfm_halfcell, but splits the low pulse with a glitchy spike so a
    -- runt second falling edge trails the legit one by 160 ns (8 cycles)
    procedure runt_halfcell(signal rd : out std_logic) is
    begin
      rd <= '0';                                 -- the legitimate transition
      wait for 100 ns;
      rd <= '1';                                 -- glitchy high spike
      wait for 60 ns;                            -- runt leading-edge distance: 160 ns
      rd <= '0';                                 -- the RUNT (spurious) transition
      wait for MFM_LOW_WIDTH - 160 ns;           -- remainder of the low pulse
      rd <= '1';
      wait for MFM_HALF_CELL - MFM_LOW_WIDTH;
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

  -----------------------------------------------------------------------------
  -- write-splice junk model (round 13) -- see package declaration
  -----------------------------------------------------------------------------
  function lfsr16_step(x : natural) return natural is
    variable v  : unsigned(15 downto 0) := to_unsigned(x mod 65536, 16);
    variable fb : std_logic;
  begin
    fb := v(15) xor v(13) xor v(12) xor v(10);
    return to_integer(unsigned'(v(14 downto 0) & fb));
  end function;

  function junk_splice_rand(seed : natural) return junk_arr_t is
    variable s : natural := (seed mod 65535) + 1;   -- LFSR state, never 0
    variable r : junk_arr_t := (cnt => 0, g => (others => 300));
    variable n : natural;
  begin
    s := lfsr16_step(s);
    n := 28 + (s mod 9);                            -- 28..36 gaps
    for k in 0 to n - 1 loop
      s      := lfsr16_step(s);
      r.g(k) := 130 + (s mod 351);                  -- [130..480] cycles
    end loop;
    s := lfsr16_step(s);
    r.g(n / 3) := 900 + (s mod 400);                -- fluxless stretch 1
    s := lfsr16_step(s);
    r.g((2 * n) / 3) := 1300 + (s mod 700);         -- fluxless stretch 2
    r.cnt := n;                                     -- g(n-1) = boundary gap
    return r;
  end function;

  function junk_splice_chain(seed : natural) return junk_arr_t is
    variable s  : natural := (seed mod 65535) + 1;  -- LFSR state, never 0
    variable r  : junk_arr_t := (cnt => 0, g => (others => 300));
    variable i  : natural := 0;
    variable np : natural;
  begin
    -- random splice garbage
    s := lfsr16_step(s);
    np := 8 + (s mod 5);
    for k in 1 to np loop
      s      := lfsr16_step(s);
      r.g(i) := 130 + (s mod 351);
      i      := i + 1;
    end loop;
    -- a fluxless stretch (class 11 everywhere -> re-seeds the adaptive est)
    s := lfsr16_step(s);
    r.g(i) := 1100 + (s mod 500);  i := i + 1;
    -- four medium/long-ish values: deliberately NOT short-class, so the
    -- round-13 preamble-run gate cannot be banked by what follows
    for k in 1 to 4 loop
      s      := lfsr16_step(s);
      r.g(i) := 251 + (s mod 230);
      i      := i + 1;
    end loop;
    -- 14 short-ish gaps (~205): coherent residue that walks the round-12
    -- estimate up by ~1.75 cycles -- and stays BELOW the round-13
    -- C_QUANT_SYNC_RUN = 16 threshold, so the gate stays closed
    for k in 1 to 14 loop
      r.g(i) := 205;  i := i + 1;
    end loop;
    -- the killer: ~446/~344 alternation = the A1 sync gap pattern
    -- long,med,long,med under the round-12 no-dead-band acceptance
    -- (deviations +46/+44 <= est/2), while the OLD windows reject BOTH
    -- (446 > C_GAP_LONG_HI = 445; 344 inside the 343..354 dead-band).
    -- Four pairs -> false syncs after gaps 4, 6 and 8 -> decoder armed.
    for k in 1 to 4 loop
      r.g(i) := 446;  i := i + 1;
      r.g(i) := 344;  i := i + 1;
    end loop;
    -- tail spelling the FB data mark: gap classes S,S,S,S,S,L,S decode to
    -- bits 1,1,1,1,1,0,1,1 = 0xFB after the last false sync
    r.g(i) := 224;  i := i + 1;
    r.g(i) := 224;  i := i + 1;
    r.g(i) := 224;  i := i + 1;
    r.g(i) := 224;  i := i + 1;
    r.g(i) := 224;  i := i + 1;
    r.g(i) := 446;  i := i + 1;
    r.g(i) := 224;  i := i + 1;
    -- boundary gap to the first real flux transition after the splice
    r.g(i) := 300;  i := i + 1;
    r.cnt := i;
    return r;
  end function;

  procedure mfm_splice_junk(signal rdata : out std_logic; j : in junk_arr_t) is
  begin
    for k in 0 to j.cnt - 1 loop
      rdata <= '0';
      wait for MFM_LOW_WIDTH;
      rdata <= '1';
      wait for j.g(k) * 20 ns - MFM_LOW_WIDTH;
    end loop;
  end procedure;

end package body mfm_flux_gen_pkg;
