-------------------------------------------------------------------------------
-- tb_physical_1581_mfm_decoder.vhd
--
-- End-to-end GHDL test of the DD-MFM read decoder. Uses mfm_flux_gen_pkg to lay
-- down a canonical 1581 physical record (ID field + 512-byte data field) as raw
-- active-low RDATA flux, then checks that the decoder recovers:
--   * ID  : C/H/R/N exactly, id_crc_ok = 1
--   * DATA: all 512 payload bytes exactly, data_crc_ok = 1, deleted = 0
-- The payload deliberately embeds 0xA1/0xFE/0xFB/0xF8/0xF5/0xF6/0xF7 values to
-- prove they do NOT trigger a false sync/mark (only the missing-clock gap
-- pattern establishes sync).
-- A second timing-valid false DAM is placed after the valid ID but before the
-- real data lock-up preamble. ID sequencing alone arms it; production must
-- reject it for lack of the stock/F011 00 run, retain the ID arm, and decode
-- the genuine data field that follows.
--
-- Runt-filter vectors (issue #90 round 10): one synthetic sub-C_GAP_GLITCH
-- double edge is injected inside the ID field (the H byte) and one inside the
-- data field (payload byte 100). Both fields must still decode byte-exact with
-- CRC OK, runt_o must pulse exactly twice, and gap_error_o must never fire
-- (without the filter each runt splits a legit gap into an out-of-window pair
-- and kills the field).
--
-- Run: ghdl -a --std=08 --workdir=B  <pkg> <crc> <4 stages> <decoder> <flux_pkg> <this>
--      ghdl --elab-run --std=08 --workdir=B tb_physical_1581_mfm_decoder --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;

entity tb_physical_1581_mfm_decoder is
end entity;

architecture sim of tb_physical_1581_mfm_decoder is
  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal f_rdata : std_logic := '1';   -- idle high (active low)

  -- decoder outputs
  signal id_valid        : std_logic;
  signal id_c, id_h, id_r, id_n : unsigned(7 downto 0);
  signal id_crc_ok       : std_logic;
  signal id_crc_stored   : unsigned(15 downto 0);
  signal data_start      : std_logic;
  signal data_deleted    : std_logic;
  signal data_byte       : unsigned(7 downto 0);
  signal data_byte_valid : std_logic;
  signal data_end        : std_logic;
  signal data_crc_ok     : std_logic;
  signal locked          : std_logic;
  signal gap_error       : std_logic;
  signal runt            : std_logic;
  signal dam_unarmed     : std_logic;
  signal last_gap        : unsigned(15 downto 0);

  -- runt-filter observation
  signal runt_cnt      : integer := 0;
  signal gap_error_cnt : integer := 0;
  signal dam_unarmed_cnt : integer := 0;

  -- test record identity
  constant TC : unsigned(7 downto 0) := x"05";   -- cylinder
  constant TH : unsigned(7 downto 0) := x"01";   -- head/side
  constant TR : unsigned(7 downto 0) := x"03";   -- sector
  constant TN : unsigned(7 downto 0) := x"02";   -- size code 512

  -- payload generator (variety + embedded mark-like bytes)
  function gen_data(i : integer) return unsigned is
  begin
    case i is
      when  10 => return x"A1";
      when  20 => return x"FE";
      when  30 => return x"FB";
      when  40 => return x"F8";
      when  50 => return x"F5";
      when  60 => return x"F6";
      when  70 => return x"F7";
      when others => return to_unsigned((i*13 + 7) mod 256, 8);
    end case;
  end function;

  -- captured payload
  type arr_t is array (0 to 511) of unsigned(7 downto 0);
  signal cap     : arr_t := (others => (others => '0'));
  signal cap_idx : integer := 0;

  -- latched id
  signal id_seen   : std_logic := '0';
  signal id_c_l    : unsigned(7 downto 0);
  signal id_r_l    : unsigned(7 downto 0);
  signal id_n_l    : unsigned(7 downto 0);
  signal id_ok_l   : std_logic;

  -- latched data completion (data_end is a 1-cycle pulse fired during emission)
  signal saw_data_end   : std_logic := '0';
  signal data_crc_ok_l  : std_logic := '0';
  signal data_deleted_l : std_logic := '0';

  function hs(v : unsigned) return string is
  begin
    return to_hstring(std_logic_vector(v));
  end function;
begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => id_valid, id_c_o => id_c, id_h_o => id_h, id_r_o => id_r,
      id_n_o => id_n, id_crc_ok_o => id_crc_ok, id_crc_stored_o => id_crc_stored,
      data_start_o => data_start, data_deleted_o => data_deleted,
      data_byte_o => data_byte, data_byte_valid_o => data_byte_valid,
      data_end_o => data_end, data_crc_ok_o => data_crc_ok,
      locked_o => locked, gap_error_o => gap_error, runt_o => runt,
      dam_unarmed_o => dam_unarmed,
      last_gap_o => last_gap
    );

  -- count runt merges and gap errors over the whole run
  runt_watch : process (clk)
  begin
    if rising_edge(clk) then
      if runt = '1' then
        runt_cnt <= runt_cnt + 1;
      end if;
      if gap_error = '1' then
        gap_error_cnt <= gap_error_cnt + 1;
      end if;
      if dam_unarmed = '1' then
        dam_unarmed_cnt <= dam_unarmed_cnt + 1;
      end if;
    end if;
  end process;

  -- capture streamed payload + latch id
  capture : process (clk)
  begin
    if rising_edge(clk) then
      if data_start = '1' then
        cap_idx <= 0;
      elsif data_byte_valid = '1' then
        cap(cap_idx) <= data_byte;
        cap_idx <= cap_idx + 1;
      end if;
      if id_valid = '1' then
        id_seen <= '1';
        id_c_l  <= id_c;
        id_r_l  <= id_r;
        id_n_l  <= id_n;
        id_ok_l <= id_crc_ok;
      end if;
      if data_end = '1' then
        saw_data_end   <= '1';
        data_crc_ok_l  <= data_crc_ok;
        data_deleted_l <= data_deleted;
      end if;
    end if;
  end process;

  -- flux stimulus
  stim : process
    variable prev : std_logic := '0';
    variable v    : unsigned(15 downto 0);
  begin
    rst <= '1';
    wait for 200 ns;
    rst <= '0';
    wait for 200 ns;

    -- ===== timing-valid unsolicited DAM (write-splice upper bound) ==========
    -- A complete A1x3+FB cannot be rejected from sync timing alone. With no
    -- preceding CRC-valid ID, production must ignore it and remain able to
    -- acquire the real record that follows.
    mfm_bytes(f_rdata, x"00", 8, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 8, prev);

    -- ===== ID field ==========================================================
    mfm_bytes(f_rdata, x"00", 12, prev);         -- 12 x 00 preamble
    mfm_a1(f_rdata, prev);                        -- 3 x A1 (missing clock)
    mfm_a1(f_rdata, prev);
    mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FE", prev);               -- ID address mark
    mfm_byte(f_rdata, TC, prev);
    mfm_byte_runt(f_rdata, TH, prev);             -- runt injected INSIDE the ID field
    mfm_byte(f_rdata, TR, prev);
    mfm_byte(f_rdata, TN, prev);
    -- ID CRC over A1,A1,A1,FE,C,H,R,N
    v := x"FFFF";
    v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FE");
    v := crc16_update(v, TC); v := crc16_update(v, TH);
    v := crc16_update(v, TR); v := crc16_update(v, TN);
    mfm_byte(f_rdata, v(15 downto 8), prev);
    mfm_byte(f_rdata, v(7 downto 0), prev);

    -- ===== armed write-splice DAM (must not consume the ID arm) =============
    -- The false four-byte mark occupies part of the normal 22-byte Gap 2:
    -- 8 x 4E + A1x3/FB + 10 x 4E = 22 byte times. The real DAM below therefore
    -- remains at the standard 38-byte post-ID position (inside WD's 43-byte
    -- search window), rather than relying on the decoder's longer-lived arm.
    mfm_bytes(f_rdata, x"4E", 8, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 10, prev);

    -- ===== DATA field ========================================================
    mfm_bytes(f_rdata, x"00", 12, prev);          -- 12 x 00 preamble
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);               -- normal data address mark
    v := x"FFFF";
    v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FB");
    for i in 0 to 511 loop
      if i = 100 then
        mfm_byte_runt(f_rdata, gen_data(i), prev);  -- runt INSIDE the data field
      else
        mfm_byte(f_rdata, gen_data(i), prev);
      end if;
      v := crc16_update(v, gen_data(i));
    end loop;
    mfm_byte(f_rdata, v(15 downto 8), prev);      -- data CRC high
    mfm_byte(f_rdata, v(7 downto 0), prev);       -- data CRC low

    -- ===== trailing gap ======================================================
    mfm_bytes(f_rdata, x"4E", 8, prev);

    -- let the decoder finish the data field (data_end pulses during emission)
    wait for 300 us;
    assert saw_data_end = '1'
      report "FAIL: data field never completed (decoder stalled)" severity error;

    -- ===== checks ============================================================
    assert id_seen = '1' report "FAIL: ID field never decoded" severity error;
    assert id_c_l = TC report "FAIL: ID C = " & hs(id_c_l) & " expected " & hs(TC) severity error;
    assert id_r_l = TR report "FAIL: ID R = " & hs(id_r_l) & " expected " & hs(TR) severity error;
    assert id_n_l = TN report "FAIL: ID N = " & hs(id_n_l) & " expected " & hs(TN) severity error;
    assert id_ok_l = '1' report "FAIL: ID CRC not OK" severity error;
    report "ID OK: C=" & hs(id_c_l) & " R=" & hs(id_r_l) & " N=" & hs(id_n_l) & " crc_ok=1";

    assert data_crc_ok_l = '1' report "FAIL: data CRC not OK" severity error;
    assert data_deleted_l = '0' report "FAIL: deleted flag set on FB record" severity error;
    assert cap_idx = 512 report "FAIL: captured " & integer'image(cap_idx) & " data bytes, expected 512" severity error;
    report "DATA OK: 512 bytes streamed, crc_ok=1, deleted=0";

    for i in 0 to 511 loop
      assert cap(i) = gen_data(i)
        report "FAIL: data[" & integer'image(i) & "] = " & hs(cap(i)) & " expected " & hs(gen_data(i))
        severity error;
    end loop;
    report "DATA payload byte-for-byte MATCH (incl. embedded A1/FE/FB/F8/F5/F6/F7 values)";

    -- runt-filter checks: both injected runts merged, no field killed
    assert runt_cnt = 2
      report "FAIL: runt_o pulsed " & integer'image(runt_cnt) & " times, expected 2" severity error;
    assert gap_error_cnt = 0
      report "FAIL: gap_error fired " & integer'image(gap_error_cnt) & " times, expected 0 (runt not merged?)" severity error;
    assert dam_unarmed_cnt = 2
      report "FAIL: ignored DAM count=" & integer'image(dam_unarmed_cnt) & ", expected 2" severity error;
    report "RUNT FILTER OK: 2 runts merged (ID + data field), 0 gap errors";
    report "RECORD SEQUENCE OK: unsolicited and post-ID preamble-less DAMs ignored";

    report "physical_1581_mfm_decoder: ALL TESTS PASSED";
    finish;
  end process;

  -- debug monitor
  dbg : process (clk)
    variable plock : std_logic := '0';
    variable gapn  : integer := 0;
    variable pgap  : unsigned(15 downto 0) := (others => '1');
  begin
    if rising_edge(clk) then
      if last_gap /= pgap then
        pgap := last_gap;
        if gapn < 40 then
          report "gap#" & integer'image(gapn) & " = " & integer'image(to_integer(last_gap)) & " cyc";
        end if;
        gapn := gapn + 1;
      end if;
      if locked = '1' and plock = '0' then
        report "LOCKED (after " & integer'image(gapn) & " gaps)";
      end if;
      plock := locked;
      if id_valid = '1' then
        report "ID_VALID C=" & hs(id_c) & " R=" & hs(id_r) & " N=" & hs(id_n)
             & " crc_ok=" & std_logic'image(id_crc_ok);
      end if;
      if data_start = '1' then
        report "DATA_START deleted=" & std_logic'image(data_deleted);
      end if;
      if data_end = '1' then
        report "DATA_END crc_ok=" & std_logic'image(data_crc_ok);
      end if;
    end if;
  end process;

  -- global timeout guard
  guard : process
  begin
    wait for 40 ms;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
