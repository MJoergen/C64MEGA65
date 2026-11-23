-------------------------------------------------------------------------------
-- tb_physical_1581_mfm_decoder.vhd
--
-- End-to-end GHDL test of the DD-MFM read decoder. Uses mfm_flux_gen_pkg to lay
-- down canonical 1581 physical records as raw active-low RDATA flux. Two
-- decoders run on the same flux: dut(0) with its tolerance for a weak first
-- sync byte (tol_off_i low, production) and dut(1) without it (tol_off_i
-- high). Every scenario starts with a decoder reset and checks, for both, the
-- counts of decoded IDs, CRC-good IDs, data fields, CRC-good data fields,
-- tol_hit_o pulses and ignored DAMs, the deleted flag of the last data field
-- and every payload byte.
--
-- Scenario 0 (both decoders identical) is the original vector: an ID field
-- (C/H/R/N, CRC good) and a 512-byte data field whose payload embeds
-- 0xA1/0xFE/0xFB/0xF8/0xF5/0xF6/0xF7 values that must NOT trigger a false
-- sync/mark (only the missing-clock gap pattern establishes sync); a timing-
-- valid unsolicited DAM before the ID and a timing-valid DAM after the valid
-- ID but before the real data lock-up preamble, both ignored (the ID arm is
-- retained); and one synthetic sub-C_GAP_GLITCH runt double edge inside the
-- ID field and one inside the data field (issue #90 round 10): both fields
-- decode byte-exact, runt_o pulses exactly twice, gap_error_o never fires.
--
-- Scenarios 1 to 15 (issue #257 part E): the tolerance. A weak sync byte is
-- A1_WEAK of mfm_flux_gen_pkg, the recorded peak shift of the ID that stopped
-- a format: its long interval of 6.88 us classifies as medium, the candidate
-- of that byte is lost.
--   1  ID, first sync byte weak            on: ID + data, 1 hit  off: DAM ignored
--   2  ID, second sync byte weak           both: no ID, DAM ignored
--   3  ID, third sync byte weak            both: no ID, DAM ignored
--   4  data FB, first sync byte weak       on: data, 1 hit       off: no data
--   5  data F8, first sync byte weak       on: deleted data      off: no data
--   6  data, second sync byte weak         both: no data
--   7  data, third sync byte weak          both: no data
--   8  ID with a bad CRC, data first weak  both: ID (CRC bad), no data, 0 hits
--   9  no ID, data first weak              both: no data, 0 hits
--  10  ID, a false train of two + FB in gap 2 without the zero run, then the
--      real data field                     both: the false DAM ignored, data
--  11  ID, 12 x 00 and only two A1 + FB (the pair right after the zero run),
--      then the real data field            both: data of the real field only
--  12  ID with first sync byte weak inside an open data field (no re-anchor
--      on a train of two)                  both: only the outer ID and data
--  13  splice-like false mark: after a valid ID a junk burst, two A1 and FE,
--      six junk bytes, then the real data field. on: 1 hit, the false ID
--      (bad CRC) is not reported and neither disarms the data field nor
--      changes its length; off: no hit; both: data decoded
--  14  ID, first and second sync byte weak (a train of one)  both: no ID
--  15  overlapping candidates (two gaps apart) followed by FE and a
--      CRC-valid ID body                   both: no ID
--  16  ID weak first byte and a bad CRC (a damaged header): on: 1 hit, no ID
--      reported, the DAM after it ignored; off: no ID, DAM ignored
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

  -- decoder outputs, index 0 = tolerance on, 1 = tolerance off
  type u8_arr  is array (0 to 1) of unsigned(7 downto 0);
  type u16_arr is array (0 to 1) of unsigned(15 downto 0);
  signal tol_off         : std_logic_vector(0 to 1) := "01";
  signal id_valid        : std_logic_vector(0 to 1);
  signal id_c, id_h, id_r, id_n : u8_arr;
  signal id_crc_ok       : std_logic_vector(0 to 1);
  signal id_crc_stored   : u16_arr;
  signal data_start      : std_logic_vector(0 to 1);
  signal data_deleted    : std_logic_vector(0 to 1);
  signal data_byte       : u8_arr;
  signal data_byte_valid : std_logic_vector(0 to 1);
  signal data_end        : std_logic_vector(0 to 1);
  signal data_crc_ok     : std_logic_vector(0 to 1);
  signal locked          : std_logic_vector(0 to 1);
  signal gap_error       : std_logic_vector(0 to 1);
  signal runt            : std_logic_vector(0 to 1);
  signal dam_unarmed     : std_logic_vector(0 to 1);
  signal tol_hit         : std_logic_vector(0 to 1);
  signal last_gap        : u16_arr;

  -- record identity of scenario 0
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

  -- event counters per decoder (monotonic; the stimulus compares deltas)
  type cnt_t is record
    ids, ids_ok, dat, dat_ok, tol, unarmed, runts, gerr, bad_bytes : natural;
    last_bytes : natural;
    last_del   : std_logic;
    last_id_c, last_id_r, last_id_n : unsigned(7 downto 0);
    last_id_ok : std_logic;
  end record;
  constant CNT0 : cnt_t := (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, '0', x"00", x"00", x"00", '0');
  type cnt_arr is array (0 to 1) of cnt_t;
  signal cnt : cnt_arr := (others => CNT0);

  -- expectation of one scenario for one decoder (deltas)
  type exp_t is record
    ids, ids_ok, dat, dat_ok, tol, unarmed : natural;
    del : std_logic;                          -- deleted flag of the last data field
  end record;

  signal fails : natural := 0;

  function hs(v : unsigned) return string is
  begin
    return to_hstring(std_logic_vector(v));
  end function;
begin

  clk <= not clk after 10 ns;   -- 50 MHz

  g_dut : for k in 0 to 1 generate
    dut : entity work.physical_1581_mfm_decoder
      port map (
        clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
        tol_off_i => tol_off(k), tol_hit_o => tol_hit(k),
        id_valid_o => id_valid(k), id_c_o => id_c(k), id_h_o => id_h(k), id_r_o => id_r(k),
        id_n_o => id_n(k), id_crc_ok_o => id_crc_ok(k), id_crc_stored_o => id_crc_stored(k),
        data_start_o => data_start(k), data_deleted_o => data_deleted(k),
        data_byte_o => data_byte(k), data_byte_valid_o => data_byte_valid(k),
        data_end_o => data_end(k), data_crc_ok_o => data_crc_ok(k),
        locked_o => locked(k), gap_error_o => gap_error(k), runt_o => runt(k),
        dam_unarmed_o => dam_unarmed(k),
        last_gap_o => last_gap(k)
      );
  end generate;

  -- count events and check every payload byte against gen_data
  monitor : process (clk)
    variable c   : cnt_arr := (others => CNT0);
    variable idx : integer;
    type idx_arr is array (0 to 1) of integer;
    variable bi  : idx_arr := (0, 0);
  begin
    if rising_edge(clk) then
      for k in 0 to 1 loop
        if runt(k) = '1' then c(k).runts := c(k).runts + 1; end if;
        if gap_error(k) = '1' then c(k).gerr := c(k).gerr + 1; end if;
        if dam_unarmed(k) = '1' then c(k).unarmed := c(k).unarmed + 1; end if;
        if tol_hit(k) = '1' then c(k).tol := c(k).tol + 1; end if;
        if id_valid(k) = '1' then
          c(k).ids := c(k).ids + 1;
          if id_crc_ok(k) = '1' then c(k).ids_ok := c(k).ids_ok + 1; end if;
          c(k).last_id_c := id_c(k); c(k).last_id_r := id_r(k); c(k).last_id_n := id_n(k);
          c(k).last_id_ok := id_crc_ok(k);
        end if;
        if data_start(k) = '1' then
          bi(k) := 0;
        elsif data_byte_valid(k) = '1' then
          if data_byte(k) /= gen_data(bi(k)) then
            c(k).bad_bytes := c(k).bad_bytes + 1;
          end if;
          bi(k) := bi(k) + 1;
        end if;
        if data_end(k) = '1' then
          c(k).dat := c(k).dat + 1;
          if data_crc_ok(k) = '1' then c(k).dat_ok := c(k).dat_ok + 1; end if;
          c(k).last_bytes := bi(k);
          c(k).last_del := data_deleted(k);
        end if;
      end loop;
      cnt <= c;
    end if;
  end process;

  -- flux stimulus
  stim : process
    variable prev : std_logic := '0';
    variable v    : unsigned(15 downto 0);
    variable s0   : cnt_arr;
    type weak_t is array (1 to 3) of boolean;
    constant NONE_W : weak_t := (false, false, false);

    -- the three sync bytes, the ones marked weak shifted like A1_WEAK
    procedure a1_train(w : weak_t) is
    begin
      for i in 1 to 3 loop
        if w(i) then mfm_a1_shift(f_rdata, prev, A1_WEAK);
        else         mfm_a1(f_rdata, prev); end if;
      end loop;
    end procedure;

    function weak(i : natural) return weak_t is
      variable r : weak_t := NONE_W;
    begin
      if i >= 1 and i <= 3 then r(i) := true; end if;
      return r;
    end function;

    -- ID field: [12 x 00] + A1 x 3 + FE + C H R N + CRC (corrupted if bad)
    procedure id_field(c, h, r, n : unsigned(7 downto 0); w : weak_t;
                       bad : boolean; zeros : boolean) is
      variable crc : unsigned(15 downto 0);
    begin
      if zeros then mfm_bytes(f_rdata, x"00", 12, prev); end if;
      a1_train(w);
      mfm_byte(f_rdata, x"FE", prev);
      mfm_byte(f_rdata, c, prev); mfm_byte(f_rdata, h, prev);
      mfm_byte(f_rdata, r, prev); mfm_byte(f_rdata, n, prev);
      crc := x"FFFF";
      crc := crc16_update(crc, x"A1"); crc := crc16_update(crc, x"A1"); crc := crc16_update(crc, x"A1");
      crc := crc16_update(crc, x"FE");
      crc := crc16_update(crc, c); crc := crc16_update(crc, h);
      crc := crc16_update(crc, r); crc := crc16_update(crc, n);
      if bad then crc := crc xor x"0400"; end if;
      mfm_byte(f_rdata, crc(15 downto 8), prev);
      mfm_byte(f_rdata, crc(7 downto 0), prev);
    end procedure;

    -- data field: 12 x 00 + A1 x 3 + mark + gen_data(0 .. len-1) + CRC
    procedure data_field(mark : unsigned(7 downto 0); len : natural; w : weak_t) is
      variable crc : unsigned(15 downto 0);
    begin
      mfm_bytes(f_rdata, x"00", 12, prev);
      a1_train(w);
      mfm_byte(f_rdata, mark, prev);
      crc := x"FFFF";
      crc := crc16_update(crc, x"A1"); crc := crc16_update(crc, x"A1"); crc := crc16_update(crc, x"A1");
      crc := crc16_update(crc, mark);
      for i in 0 to len - 1 loop
        mfm_byte(f_rdata, gen_data(i), prev);
        crc := crc16_update(crc, gen_data(i));
      end loop;
      mfm_byte(f_rdata, crc(15 downto 8), prev);
      mfm_byte(f_rdata, crc(7 downto 0), prev);
    end procedure;

    -- a gap as a flux interval of n cycles (for hand-built gap sequences)
    procedure gap_c(n : natural) is
    begin
      f_rdata <= '0'; wait for MFM_LOW_WIDTH; f_rdata <= '1';
      wait for n * 20 ns - MFM_LOW_WIDTH;
    end procedure;

    procedure begin_scn is
    begin
      wait until rising_edge(clk);
      rst <= '1';
      for i in 1 to 4 loop wait until rising_edge(clk); end loop;
      rst <= '0';
      wait for 20 us;                         -- no flux: the gaps stage starts afresh
      prev := '0';
      mfm_bytes(f_rdata, x"4E", 16, prev);    -- lead-in: the estimate settles
      s0 := cnt;
    end procedure;

    function choose(k : natural) return string is
    begin
      if k = 0 then return "on "; else return "off"; end if;
    end function;

    procedure check(name : string; k : natural; e : exp_t) is
      variable c : cnt_t;
      variable ok : boolean := true;
    begin
      c := cnt(k);
      if c.ids - s0(k).ids /= e.ids or c.ids_ok - s0(k).ids_ok /= e.ids_ok or
         c.dat - s0(k).dat /= e.dat or c.dat_ok - s0(k).dat_ok /= e.dat_ok or
         c.tol - s0(k).tol /= e.tol or c.unarmed - s0(k).unarmed /= e.unarmed or
         (e.dat_ok = e.dat and c.bad_bytes /= s0(k).bad_bytes) or
         (e.dat /= 0 and c.last_del /= e.del) then
        ok := false;
      end if;
      if ok then
        report name & " tolerance " & choose(k) & ": OK";
      else
        report "FAIL: " & name & " tolerance " & choose(k) &
               ": IDs " & integer'image(c.ids - s0(k).ids) & "/" & integer'image(e.ids) &
               " IDs ok " & integer'image(c.ids_ok - s0(k).ids_ok) & "/" & integer'image(e.ids_ok) &
               " data " & integer'image(c.dat - s0(k).dat) & "/" & integer'image(e.dat) &
               " data ok " & integer'image(c.dat_ok - s0(k).dat_ok) & "/" & integer'image(e.dat_ok) &
               " hits " & integer'image(c.tol - s0(k).tol) & "/" & integer'image(e.tol) &
               " unarmed " & integer'image(c.unarmed - s0(k).unarmed) & "/" & integer'image(e.unarmed) &
               " bad bytes " & integer'image(c.bad_bytes - s0(k).bad_bytes) &
               " deleted " & std_logic'image(c.last_del) & "/" & std_logic'image(e.del)
          severity error;
        fails <= fails + 1;
      end if;
    end procedure;

    procedure end_scn(name : string; on_e, off_e : exp_t) is
    begin
      mfm_bytes(f_rdata, x"4E", 8, prev);
      wait for 100 us;
      check(name, 0, on_e);
      check(name, 1, off_e);
    end procedure;

    --            ids ok dat ok tol una del
    constant E_NONE : exp_t := (0, 0, 0, 0, 0, 0, '0');
  begin
    rst <= '1';
    wait for 200 ns;
    rst <= '0';
    wait for 200 ns;
    s0 := cnt;

    -- ===== scenario 0: the original vector ==================================
    -- timing-valid unsolicited DAM (write-splice upper bound): a complete
    -- A1x3+FB cannot be rejected from sync timing alone; with no preceding
    -- CRC-valid ID, production must ignore it and still acquire the record.
    mfm_bytes(f_rdata, x"00", 8, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 8, prev);
    -- ID field with a runt inside
    mfm_bytes(f_rdata, x"00", 12, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FE", prev);
    mfm_byte(f_rdata, TC, prev);
    mfm_byte_runt(f_rdata, TH, prev);
    mfm_byte(f_rdata, TR, prev);
    mfm_byte(f_rdata, TN, prev);
    v := x"FFFF";
    v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FE");
    v := crc16_update(v, TC); v := crc16_update(v, TH);
    v := crc16_update(v, TR); v := crc16_update(v, TN);
    mfm_byte(f_rdata, v(15 downto 8), prev);
    mfm_byte(f_rdata, v(7 downto 0), prev);
    -- armed write-splice DAM (must not consume the ID arm): 8 x 4E + A1x3/FB
    -- + 10 x 4E = 22 byte times of Gap 2, so the real DAM stays at the
    -- standard 38-byte post-ID position (inside WD's 43-byte search window).
    mfm_bytes(f_rdata, x"4E", 8, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 10, prev);
    -- DATA field with a runt inside the payload
    mfm_bytes(f_rdata, x"00", 12, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    v := x"FFFF";
    v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FB");
    for i in 0 to 511 loop
      if i = 100 then
        mfm_byte_runt(f_rdata, gen_data(i), prev);
      else
        mfm_byte(f_rdata, gen_data(i), prev);
      end if;
      v := crc16_update(v, gen_data(i));
    end loop;
    mfm_byte(f_rdata, v(15 downto 8), prev);
    mfm_byte(f_rdata, v(7 downto 0), prev);
    mfm_bytes(f_rdata, x"4E", 8, prev);
    wait for 300 us;
    for k in 0 to 1 loop
      assert cnt(k).dat = 1
        report "FAIL: data field never completed (decoder " & choose(k) & ")" severity error;
      assert cnt(k).ids = 1 and cnt(k).last_id_ok = '1' and cnt(k).last_id_c = TC and
             cnt(k).last_id_r = TR and cnt(k).last_id_n = TN
        report "FAIL: ID field C/R/N/CRC (decoder " & choose(k) & ")" severity error;
      assert cnt(k).dat_ok = 1 and cnt(k).last_del = '0' and cnt(k).last_bytes = 512 and
             cnt(k).bad_bytes = 0
        report "FAIL: data field CRC/deleted/length/payload (decoder " & choose(k) & ")" severity error;
      assert cnt(k).runts = 2
        report "FAIL: runt_o pulsed " & integer'image(cnt(k).runts) & " times, expected 2" severity error;
      assert cnt(k).gerr = 0
        report "FAIL: gap_error fired " & integer'image(cnt(k).gerr) & " times, expected 0" severity error;
      assert cnt(k).unarmed = 2
        report "FAIL: ignored DAM count=" & integer'image(cnt(k).unarmed) & ", expected 2" severity error;
      assert cnt(k).tol = 0
        report "FAIL: tol_hit pulsed in scenario 0" severity error;
    end loop;
    report "scenario 0: ID OK, DATA 512 bytes byte-for-byte, 2 runts merged, 0 gap errors, unsolicited and post-ID preamble-less DAMs ignored (both decoders)";

    -- ===== scenario 1: ID, first sync byte weak =============================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", weak(1), false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 1 (ID, sync byte 1 weak)", (1, 1, 1, 1, 1, 0, '0'), (0, 0, 0, 0, 0, 1, '0'));

    -- ===== scenario 2: ID, second sync byte weak ============================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", weak(2), false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 2 (ID, sync byte 2 weak)", (0, 0, 0, 0, 0, 1, '0'), (0, 0, 0, 0, 0, 1, '0'));

    -- ===== scenario 3: ID, third sync byte weak =============================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", weak(3), false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 3 (ID, sync byte 3 weak)", (0, 0, 0, 0, 0, 1, '0'), (0, 0, 0, 0, 0, 1, '0'));

    -- ===== scenario 4: data FB, first sync byte weak ========================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, weak(1));
    end_scn("scenario 4 (data FB, sync byte 1 weak)", (1, 1, 1, 1, 1, 0, '0'), (1, 1, 0, 0, 0, 0, '0'));

    -- ===== scenario 5: deleted data F8, first sync byte weak, 512 bytes =====
    begin_scn;
    id_field(x"4D", x"01", x"07", x"02", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"F8", 512, weak(1));
    end_scn("scenario 5 (data F8, sync byte 1 weak)", (1, 1, 1, 1, 1, 0, '1'), (1, 1, 0, 0, 0, 0, '0'));

    -- ===== scenario 6: data, second sync byte weak ==========================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, weak(2));
    end_scn("scenario 6 (data, sync byte 2 weak)", (1, 1, 0, 0, 0, 0, '0'), (1, 1, 0, 0, 0, 0, '0'));

    -- ===== scenario 7: data, third sync byte weak ===========================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, weak(3));
    end_scn("scenario 7 (data, sync byte 3 weak)", (1, 1, 0, 0, 0, 0, '0'), (1, 1, 0, 0, 0, 0, '0'));

    -- ===== scenario 8: ID with a bad CRC, data first weak ===================
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, true, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, weak(1));
    end_scn("scenario 8 (no valid ID, data sync byte 1 weak)", (1, 0, 0, 0, 0, 0, '0'), (1, 0, 0, 0, 0, 0, '0'));

    -- ===== scenario 9: no ID at all, data first weak ========================
    begin_scn;
    data_field(x"FB", 128, weak(1));
    end_scn("scenario 9 (no ID, data sync byte 1 weak)", E_NONE, E_NONE);

    -- ===== scenario 10: train of two + FB without the zero run ==============
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 8, prev);
    a1_train(weak(1));
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 10, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 10 (pair + FB without zero run)", (1, 1, 1, 1, 0, 0, '0'), (1, 1, 1, 1, 0, 0, '0'));

    -- ===== scenario 11: only two A1 right after the zero run + FB ===========
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 8, prev);
    mfm_bytes(f_rdata, x"00", 12, prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FB", prev);
    mfm_bytes(f_rdata, x"4E", 10, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 11 (two A1 after the zero run + FB)", (1, 1, 1, 1, 0, 0, '0'), (1, 1, 1, 1, 0, 0, '0'));

    -- ===== scenario 12: weak-first ID inside an open data field ============
    -- The data field of a 128-byte record opens; after 40 payload bytes the
    -- flux continues with 12 x 00 and an ID whose first sync byte is weak.
    -- A train of two never re-anchors: the parser stays in the data field,
    -- which ends with a bad CRC; the inner ID is not reported.
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    mfm_bytes(f_rdata, x"00", 12, prev);
    a1_train(NONE_W);
    mfm_byte(f_rdata, x"FB", prev);
    for i in 0 to 39 loop mfm_byte(f_rdata, gen_data(i), prev); end loop;
    id_field(x"4D", x"01", x"08", x"00", weak(1), false, true);
    mfm_bytes(f_rdata, x"4E", 120, prev);
    end_scn("scenario 12 (pair + FE inside a data field)", (1, 1, 1, 0, 0, 0, '0'), (1, 1, 1, 0, 0, 0, '0'));

    -- ===== scenario 13: splice-like false mark between ID and data ==========
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", NONE_W, false, true);
    mfm_bytes(f_rdata, x"4E", 4, prev);
    mfm_splice_junk(f_rdata, junk_splice_rand(7));
    prev := '0';
    mfm_byte(f_rdata, x"4E", prev);
    mfm_a1(f_rdata, prev); mfm_a1(f_rdata, prev);
    mfm_byte(f_rdata, x"FE", prev);
    mfm_byte(f_rdata, x"4E", prev); mfm_byte(f_rdata, x"4E", prev);
    mfm_byte(f_rdata, x"4E", prev); mfm_byte(f_rdata, x"4E", prev);
    mfm_byte(f_rdata, x"4E", prev); mfm_byte(f_rdata, x"4E", prev);
    mfm_bytes(f_rdata, x"4E", 6, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 13 (splice junk + two A1 + FE before the data)", (1, 1, 1, 1, 1, 0, '0'), (1, 1, 1, 1, 0, 0, '0'));

    -- ===== scenario 14: first and second sync byte weak (train of one) ======
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", (true, true, false), false, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 14 (ID, sync bytes 1 and 2 weak)", (0, 0, 0, 0, 0, 1, '0'), (0, 0, 0, 0, 0, 1, '0'));

    -- ===== scenario 15: overlapping candidates (spacing 2) + FE =============
    -- Hand-built after a zero run: M, then L M L M L M, i.e. the candidate
    -- window L,M,L,M closes twice, two gaps apart (a spacing below 5 always
    -- overlaps like this; above 5 a byte completes between the candidates).
    -- The last transition plays the end of an A1, so the FE that follows is
    -- byte-aligned, and the ID body after it has the CRC of a real train.
    begin_scn;
    mfm_bytes(f_rdata, x"00", 12, prev);
    wait for 100 * 20 ns;                     -- first transition 3 half cells after the last 00 one
    gap_c(400); gap_c(300); gap_c(400); gap_c(300); gap_c(400); gap_c(300);
    gap_c(100);                               -- closes the last medium gap, then the byte boundary
    prev := '1';
    mfm_byte(f_rdata, x"FE", prev);
    mfm_byte(f_rdata, x"4D", prev); mfm_byte(f_rdata, x"01", prev);
    mfm_byte(f_rdata, x"07", prev); mfm_byte(f_rdata, x"00", prev);
    v := x"FFFF";
    v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FE");
    v := crc16_update(v, x"4D"); v := crc16_update(v, x"01");
    v := crc16_update(v, x"07"); v := crc16_update(v, x"00");
    mfm_byte(f_rdata, v(15 downto 8), prev);
    mfm_byte(f_rdata, v(7 downto 0), prev);
    end_scn("scenario 15 (overlapping candidates + FE)", E_NONE, E_NONE);

    -- ===== scenario 16: weak first byte and a bad CRC (damaged header) ======
    begin_scn;
    id_field(x"4D", x"01", x"07", x"00", weak(1), true, true);
    mfm_bytes(f_rdata, x"4E", 22, prev);
    data_field(x"FB", 128, NONE_W);
    end_scn("scenario 16 (ID sync byte 1 weak, bad CRC)", (0, 0, 0, 0, 1, 1, '0'), (0, 0, 0, 0, 0, 1, '0'));

    wait for 10 us;
    if fails = 0 then
      report "physical_1581_mfm_decoder: ALL TESTS PASSED";
    else
      report "physical_1581_mfm_decoder: " & integer'image(fails) & " SCENARIO CHECKS FAILED" severity error;
    end if;
    finish;
  end process;

  -- global timeout guard
  guard : process
  begin
    wait for 400 ms;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
