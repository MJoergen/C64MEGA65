-------------------------------------------------------------------------------
-- tb_physical_1581_quantise_ab.vhd   (issue #90 round 12)
--
-- A/B margin harness: the OLD fixed-window gap classifier versus the NEW
-- adaptive quantiser, measured through the COMPLETE production decoder on
-- identical stress flux. Two full physical_1581_mfm_decoder instances run in
-- parallel on the same RDATA line:
--
--   * library q_new = unmodified production sources (adaptive quantiser)
--   * library q_old = the same production sources, except that the test-only
--     ref_mfm_quantise_fixed.vhd (verbatim pre-round-12 fixed windows) is
--     analyzed in place of physical_1581_mfm_quantise
--
-- Build (three libraries, one workdir B):
--   ghdl -a --std=08 --work=q_new --workdir=B -PB  <pkg,crc,gaps,quantise,
--        gaps_to_bits,bits_to_bytes,decoder>
--   ghdl -a --std=08 --work=q_old --workdir=B -PB  <pkg,crc,gaps,
--        ref_mfm_quantise_fixed,gaps_to_bits,bits_to_bytes,decoder>
--   ghdl -a --std=08 --workdir=B -PB  mfm_flux_gen_pkg.vhd  <this file>
--   ghdl --elab-run --std=08 --workdir=B -PB tb_physical_1581_quantise_ab
--        --assert-level=error
--
-- Vector classes (one canonical 1581 record = ID field C/H/R/N + 512-byte
-- data field, lead-in/gap/trailer included):
--   (i)   canonical nominal        -- regression: BOTH must decode byte-exact
--   (ii)  uniform speed offsets    -- +/-1.5%, 3%, 5%, 8% (both) and the
--                                     +/-12% discriminators (old must die:
--                                     long gaps leave 355..445 / hit a
--                                     dead-band; new tracks, clamped +/-10%)
--   (iii) linear drift             -- +/-2% end-to-end (spec) and +/-12%
--   (iv)  random jitter            -- PER-EDGE uniform, +/-8 and +/-12 (spec;
--                                     strictly harder than the per-gap model,
--                                     a gap sees up to twice the amplitude),
--                                     +/-22 and +/-24 as discriminators
--   (v)   peak shift (ISI)         -- every flux transition moves S cycles
--                                     toward its longer neighboring gap,
--                                     S in {10,15,20} (spec) + {22,24};
--                                     combined with speed offsets ("combo",
--                                     the inner-cylinder hardware model:
--                                     S20 +/-3%, S15 +5%) where the old
--                                     windows demonstrably dead-band
--   (vi)  126-cycle artifact       -- the stable mid-gap extra edge measured
--                                     on the test disk (GAP_MIN = 0x007E),
--                                     injected into the ID sync-train preamble
--   (vii) splice                   -- abrupt +2.5% speed step mid-preamble
--
-- ACCEPTANCE (all machine-checked at the end):
--   * canonical decodes byte-exact on BOTH decoders;
--   * NO REGRESSION: no trial where the old decoder succeeds and the new
--     one fails;
--   * every trial marked must_new decodes byte-exact on the new decoder;
--   * per stress family (speed / drift / jitter / peak+combo) at least one
--     trial where the NEW decoder succeeds and the OLD one fails;
--   * SILENT-CORRUPTION GUARD: any CRC-approved decode (either decoder, any
--     trial) whose ID fields or payload differ from the golden record is a
--     FATAL failure -- CRC-caught corruption is acceptable, silent wrong
--     payload is not.
--
-- A quantiser-level probe phase additionally documents single-gap decisions
-- of old vs adaptive-est/2 vs adaptive-est/4 (the est/4 variant retains
-- ~50-cycle dead-bands, which is why production uses est/2 -- see
-- C_QUANT_TOL_SHR in physical_1581_pkg).
--
-- C64MEGA65 project. SIMULATION ONLY.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
use work.mfm_flux_gen_pkg.all;      -- crc16_update, MFM_A1_RAW

library q_new;
library q_old;

entity tb_physical_1581_quantise_ab is
end entity;

architecture sim of tb_physical_1581_quantise_ab is

  constant NAME_LEN : integer := 26;
  constant MAXT     : integer := 6144;   -- max flux transitions per record

  type int_arr  is array (natural range <>) of integer;
  type real_arr is array (natural range <>) of real;
  type byte_arr is array (0 to 511) of unsigned(7 downto 0);

  -- golden record identity (cyl 61 = the hardware failure region, sector 7)
  constant TC : unsigned(7 downto 0) := x"3D";
  constant TH : unsigned(7 downto 0) := x"00";
  constant TR : unsigned(7 downto 0) := x"07";
  constant TN : unsigned(7 downto 0) := x"02";

  -- golden payload (embeds mark-like values, as in the decoder tb)
  function pl(i : integer) return unsigned is
  begin
    case i is
      when  10    => return x"A1";
      when  20    => return x"FE";
      when  30    => return x"FB";
      when  40    => return x"F8";
      when others => return to_unsigned((i*13 + 7) mod 256, 8);
    end case;
  end function;

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal f_rdata : std_logic := '1';
  signal cap_clr : std_logic := '1';

  -- NEW (adaptive) decoder outputs + capture
  signal n_id_valid, n_id_crc_ok, n_data_start, n_bytev, n_data_end, n_data_crc_ok : std_logic;
  signal n_idc, n_idh, n_idr, n_idn, n_byte : unsigned(7 downto 0);
  signal n_est : unsigned(11 downto 0);
  signal n_id_seen, n_id_ok, n_saw_end, n_crc_ok : std_logic := '0';
  signal n_c, n_h, n_r, n_n : unsigned(7 downto 0) := (others => '0');
  signal n_cap : byte_arr := (others => (others => '0'));
  signal n_idx : integer range 0 to 4095 := 0;
  signal n_est_min : integer := 4095;
  signal n_est_max : integer := 0;

  -- OLD (fixed-window) decoder outputs + capture
  signal o_id_valid, o_id_crc_ok, o_data_start, o_bytev, o_data_end, o_data_crc_ok : std_logic;
  signal o_idc, o_idh, o_idr, o_idn, o_byte : unsigned(7 downto 0);
  signal o_id_seen, o_id_ok, o_saw_end, o_crc_ok : std_logic := '0';
  signal o_c, o_h, o_r, o_n : unsigned(7 downto 0) := (others => '0');
  signal o_cap : byte_arr := (others => (others => '0'));
  signal o_idx : integer range 0 to 4095 := 0;

  -- quantiser probe instances (fed directly, no gaps stage)
  signal p_rst   : std_logic := '1';
  signal p_valid : std_logic := '0';
  signal p_len   : unsigned(15 downto 0) := (others => '0');
  signal p_cls_old, p_cls_t2, p_cls_t4 : unsigned(1 downto 0);

  -- results table
  type res_rec is record
    name    : string(1 to NAME_LEN);
    fam     : integer;                  -- 0 can / 1 speed / 2 drift / 3 jit / 4 peak / 5 combo / 6 art / 7 splice
    old_ok  : boolean;
    new_ok  : boolean;
    must_n  : boolean;
    emin    : integer;                  -- new-side est excursion (integer cycles)
    emax    : integer;
  end record;
  type res_arr is array (0 to 63) of res_rec;

  function pad(s : string) return string is
    variable r : string(1 to NAME_LEN) := (others => ' ');
  begin
    r(1 to s'length) := s;
    return r;
  end function;

  function pf(b : boolean) return string is
  begin
    if b then return "PASS"; else return "fail"; end if;
  end function;

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  ---------------------------------------------------------------------------
  -- the two decoders under test, same flux
  ---------------------------------------------------------------------------
  dut_new : entity q_new.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => n_id_valid, id_c_o => n_idc, id_h_o => n_idh,
      id_r_o => n_idr, id_n_o => n_idn, id_crc_ok_o => n_id_crc_ok,
      data_start_o => n_data_start, data_byte_o => n_byte,
      data_byte_valid_o => n_bytev, data_end_o => n_data_end,
      data_crc_ok_o => n_data_crc_ok,
      est_o => n_est
    );

  dut_old : entity q_old.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => o_id_valid, id_c_o => o_idc, id_h_o => o_idh,
      id_r_o => o_idr, id_n_o => o_idn, id_crc_ok_o => o_id_crc_ok,
      data_start_o => o_data_start, data_byte_o => o_byte,
      data_byte_valid_o => o_bytev, data_end_o => o_data_end,
      data_crc_ok_o => o_data_crc_ok
    );

  ---------------------------------------------------------------------------
  -- quantiser probe instances (single-gap decision table)
  ---------------------------------------------------------------------------
  probe_old : entity q_old.physical_1581_mfm_quantise
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_old);

  probe_t2 : entity q_new.physical_1581_mfm_quantise   -- production: tol = est/2
    generic map (G_TOL_SHR => 1)
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_t2);

  probe_t4 : entity q_new.physical_1581_mfm_quantise   -- spec draft: tol = est/4
    generic map (G_TOL_SHR => 2)
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_t4);

  ---------------------------------------------------------------------------
  -- capture: NEW side
  ---------------------------------------------------------------------------
  cap_new_p : process (clk)
  begin
    if rising_edge(clk) then
      if cap_clr = '1' then
        n_id_seen <= '0'; n_id_ok <= '0'; n_saw_end <= '0'; n_crc_ok <= '0';
        n_idx <= 0; n_est_min <= 4095; n_est_max <= 0;
      else
        if n_data_start = '1' then
          n_idx <= 0;
        elsif n_bytev = '1' then
          if n_idx < 512 then
            n_cap(n_idx) <= n_byte;
          end if;
          if n_idx < 4095 then
            n_idx <= n_idx + 1;
          end if;
        end if;
        if n_id_valid = '1' then
          n_id_seen <= '1';
          n_c <= n_idc; n_h <= n_idh; n_r <= n_idr; n_n <= n_idn;
          n_id_ok <= n_id_crc_ok;
        end if;
        if n_data_end = '1' then
          n_saw_end <= '1';
          n_crc_ok  <= n_data_crc_ok;
        end if;
        if to_integer(n_est) < n_est_min then n_est_min <= to_integer(n_est); end if;
        if to_integer(n_est) > n_est_max then n_est_max <= to_integer(n_est); end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- capture: OLD side
  ---------------------------------------------------------------------------
  cap_old_p : process (clk)
  begin
    if rising_edge(clk) then
      if cap_clr = '1' then
        o_id_seen <= '0'; o_id_ok <= '0'; o_saw_end <= '0'; o_crc_ok <= '0';
        o_idx <= 0;
      else
        if o_data_start = '1' then
          o_idx <= 0;
        elsif o_bytev = '1' then
          if o_idx < 512 then
            o_cap(o_idx) <= o_byte;
          end if;
          if o_idx < 4095 then
            o_idx <= o_idx + 1;
          end if;
        end if;
        if o_id_valid = '1' then
          o_id_seen <= '1';
          o_c <= o_idc; o_h <= o_idh; o_r <= o_idr; o_n <= o_idn;
          o_id_ok <= o_id_crc_ok;
        end if;
        if o_data_end = '1' then
          o_saw_end <= '1';
          o_crc_ok  <= o_data_crc_ok;
        end if;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- stimulus + evaluation
  ---------------------------------------------------------------------------
  stim : process
    -- golden record as flux-transition half-cell indices ---------------------
    variable tp          : int_arr(0 to MAXT - 1) := (others => 0);
    variable nt          : integer := 0;
    variable hc          : integer := 0;
    variable prev        : std_logic := '0';
    variable art_after_t : integer := -1;   -- artifact goes into the gap after this transition
    variable splice_t    : integer := -1;   -- speed step applies from this transition on
    variable crcv        : unsigned(15 downto 0);

    -- rng
    variable seed1, seed2 : positive := 1;
    variable rnd          : real;

    -- results
    variable res   : res_arr;
    variable nres  : integer := 0;
    variable wins  : int_arr(0 to 7) := (others => 0);   -- new-wins per family
    variable fails : integer := 0;

    type mode_t is (M_UNIFORM, M_DRIFT, M_SPLICE);

    procedure enc_byte(b : unsigned(7 downto 0)) is
      variable d, c : std_logic;
    begin
      for i in 7 downto 0 loop
        d := b(i);
        c := not (prev or d);
        if c = '1' then tp(nt) := hc; nt := nt + 1; end if;
        hc := hc + 1;
        if d = '1' then tp(nt) := hc; nt := nt + 1; end if;
        hc := hc + 1;
        prev := d;
      end loop;
    end procedure;

    procedure enc_a1 is
    begin
      for i in 15 downto 0 loop
        if MFM_A1_RAW(i) = '1' then tp(nt) := hc; nt := nt + 1; end if;
        hc := hc + 1;
      end loop;
      prev := '1';
    end procedure;

    -- probe a single gap through the three quantiser variants ---------------
    procedure probe_gap(gap : integer;
                        exp_old, exp_t2, exp_t4 : unsigned(1 downto 0)) is
    begin
      p_rst <= '1';                                  -- re-seed est to nominal
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      p_rst <= '0';
      wait until rising_edge(clk);
      p_len   <= to_unsigned(gap, 16);
      p_valid <= '1';
      wait until rising_edge(clk);
      p_valid <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      report "PROBE gap=" & integer'image(gap)
           & "  old=" & to_string(p_cls_old)
           & "  est/4=" & to_string(p_cls_t4)
           & "  est/2=" & to_string(p_cls_t2) & " (production)";
      if p_cls_old /= exp_old or p_cls_t2 /= exp_t2 or p_cls_t4 /= exp_t4 then
        report "FAIL: probe gap=" & integer'image(gap) & " classification mismatch"
          severity error;
        fails := fails + 1;
      end if;
    end procedure;

    -- one A/B trial ----------------------------------------------------------
    procedure run_trial(
      name     : string;
      fam      : integer;
      mode     : mode_t;
      sp0      : real;
      sp1      : real;
      jit      : integer;
      pshift   : integer;
      artifact : boolean;
      must_new : boolean;
      seed     : integer
    ) is
      variable t   : real_arr(0 to MAXT - 1);
      variable sh  : real_arr(0 to MAXT - 1);
      variable ti  : int_arr(0 to MAXT);
      variable g, gb, ga, sfac : real;
      variable ne  : integer;
      variable ok_o, ok_n, pm : boolean;
    begin
      seed1 := 1000 + seed;
      seed2 := 77;

      -- 1) speed / drift / splice model (instantaneous speed scales each gap)
      t(0) := 0.0;
      for j in 1 to nt - 1 loop
        g := real(tp(j) - tp(j - 1)) * 100.0;
        case mode is
          when M_UNIFORM => sfac := sp0;
          when M_DRIFT   => sfac := sp0 + (sp1 - sp0) * real(j) / real(nt - 1);
          when M_SPLICE  =>
            if j >= splice_t then sfac := sp1; else sfac := sp0; end if;
        end case;
        t(j) := t(j - 1) + g * sfac;
      end loop;

      -- 2) peak shift: each interior transition moves S toward its longer
      --    neighboring gap (ISI pushes crowded transitions apart)
      sh(0)      := t(0);
      sh(nt - 1) := t(nt - 1);
      for j in 1 to nt - 2 loop
        gb := t(j) - t(j - 1);
        ga := t(j + 1) - t(j);
        if gb > ga + 0.5 then
          sh(j) := t(j) - real(pshift);
        elsif ga > gb + 0.5 then
          sh(j) := t(j) + real(pshift);
        else
          sh(j) := t(j);
        end if;
      end loop;

      -- 3) independent per-edge jitter
      if jit > 0 then
        for j in 0 to nt - 1 loop
          uniform(seed1, seed2, rnd);
          sh(j) := sh(j) + (rnd * 2.0 - 1.0) * real(jit);
        end loop;
      end if;

      -- 4) 126-cycle artifact + integer quantization
      ne := 0;
      for j in 0 to nt - 1 loop
        ti(ne) := integer(round(sh(j)));
        ne := ne + 1;
        if artifact and j = art_after_t then
          ti(ne) := integer(round(sh(j))) + 126;
          ne := ne + 1;
        end if;
      end loop;
      for j in 1 to ne - 1 loop
        assert ti(j) - ti(j - 1) >= 40
          report "generator error: gap " & integer'image(ti(j) - ti(j-1)) & " below emission floor"
          severity failure;
      end loop;

      -- 5) reset both decoders, clear captures
      f_rdata <= '1';
      cap_clr <= '1';
      rst     <= '1';
      for k in 1 to 8 loop wait until rising_edge(clk); end loop;
      rst     <= '0';
      cap_clr <= '0';
      for k in 1 to 8 loop wait until rising_edge(clk); end loop;

      -- 6) emit the flux (200 ns low pulse per transition)
      for j in 0 to ne - 1 loop
        if j > 0 then
          wait for (ti(j) - ti(j - 1)) * 20 ns - 200 ns;
        end if;
        f_rdata <= '0';
        wait for 200 ns;
        f_rdata <= '1';
      end loop;
      wait for 400 us;   -- settle: let the last data field complete

      -- 7) evaluate. Success = ID byte-exact + CRC, data CRC + payload exact.
      pm := (n_idx = 512);
      if pm then
        for i in 0 to 511 loop
          if n_cap(i) /= pl(i) then pm := false; end if;
        end loop;
      end if;
      ok_n := (n_id_seen = '1' and n_id_ok = '1' and n_c = TC and n_h = TH and
               n_r = TR and n_n = TN and n_saw_end = '1' and n_crc_ok = '1' and pm);
      -- SILENT-CORRUPTION GUARD (new): CRC-approved but wrong content is FATAL
      if n_id_seen = '1' and n_id_ok = '1' then
        assert (n_c = TC and n_h = TH and n_r = TR and n_n = TN)
          report "SILENT ID CORRUPTION (new) in trial " & name severity failure;
      end if;
      if n_saw_end = '1' and n_crc_ok = '1' then
        assert pm
          report "SILENT PAYLOAD CORRUPTION (new) in trial " & name severity failure;
      end if;

      pm := (o_idx = 512);
      if pm then
        for i in 0 to 511 loop
          if o_cap(i) /= pl(i) then pm := false; end if;
        end loop;
      end if;
      ok_o := (o_id_seen = '1' and o_id_ok = '1' and o_c = TC and o_h = TH and
               o_r = TR and o_n = TN and o_saw_end = '1' and o_crc_ok = '1' and pm);
      -- SILENT-CORRUPTION GUARD (old)
      if o_id_seen = '1' and o_id_ok = '1' then
        assert (o_c = TC and o_h = TH and o_r = TR and o_n = TN)
          report "SILENT ID CORRUPTION (old) in trial " & name severity failure;
      end if;
      if o_saw_end = '1' and o_crc_ok = '1' then
        assert pm
          report "SILENT PAYLOAD CORRUPTION (old) in trial " & name severity failure;
      end if;

      res(nres) := (name => pad(name), fam => fam, old_ok => ok_o, new_ok => ok_n,
                    must_n => must_new, emin => n_est_min / 16, emax => (n_est_max + 15) / 16);
      nres := nres + 1;
      if ok_n and not ok_o then
        wins(fam) := wins(fam) + 1;
      end if;
      report "TRIAL " & pad(name) & " old=" & pf(ok_o) & " new=" & pf(ok_n)
           & "  est=[" & integer'image(n_est_min / 16) & ".." & integer'image((n_est_max + 15) / 16) & "]";
    end procedure;

  begin
    ---------------------------------------------------------------------
    -- build the golden record ONCE (half-cell transition positions)
    ---------------------------------------------------------------------
    for k in 1 to 8 loop enc_byte(x"4E"); end loop;         -- lead-in
    for k in 1 to 12 loop                                    -- ID preamble
      if k = 7 then art_after_t := nt - 1; end if;           -- artifact target: inside the sync train
      enc_byte(x"00");
    end loop;
    enc_a1; enc_a1; enc_a1;
    enc_byte(x"FE");
    enc_byte(TC); enc_byte(TH); enc_byte(TR); enc_byte(TN);
    crcv := x"FFFF";
    crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"A1");
    crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"FE");
    crcv := crc16_update(crcv, TC);    crcv := crc16_update(crcv, TH);
    crcv := crc16_update(crcv, TR);    crcv := crc16_update(crcv, TN);
    enc_byte(crcv(15 downto 8)); enc_byte(crcv(7 downto 0));
    for k in 1 to 22 loop enc_byte(x"4E"); end loop;         -- ID/data gap
    for k in 1 to 12 loop                                    -- data preamble
      if k = 7 then splice_t := nt; end if;                  -- splice: mid-preamble
      enc_byte(x"00");
    end loop;
    enc_a1; enc_a1; enc_a1;
    enc_byte(x"FB");
    crcv := x"FFFF";
    crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"A1");
    crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"FB");
    for i in 0 to 511 loop
      enc_byte(pl(i));
      crcv := crc16_update(crcv, pl(i));
    end loop;
    enc_byte(crcv(15 downto 8)); enc_byte(crcv(7 downto 0));
    for k in 1 to 8 loop enc_byte(x"4E"); end loop;          -- trailer
    report "record built: " & integer'image(nt) & " flux transitions, "
         & integer'image(hc) & " half-cells";
    assert nt < MAXT - 8 report "MAXT too small" severity failure;
    assert art_after_t > 0 and splice_t > 0 severity failure;

    rst <= '1';
    wait for 200 ns;

    ---------------------------------------------------------------------
    -- PHASE 0: single-gap probe table (old / est-div-4 / est-div-2), all
    -- from a freshly-seeded est = 100.0. Documents the dead-band removal
    -- and why production tolerance is est/2 (C_QUANT_TOL_SHR = 1):
    -- the est/4 draft rejects the very dead-band gaps (241..257, 343..354)
    -- the hardware failure produced.
    ---------------------------------------------------------------------
    report "==== PHASE 0: single-gap probes (est seeded 100.0) ====";
    probe_gap(200, "00", "00", "00");   -- nominal short
    probe_gap(300, "01", "01", "01");   -- nominal medium
    probe_gap(400, "10", "10", "10");   -- nominal long
    probe_gap(248, "11", "00", "11");   -- old dead-band 241..257 -> new: short
    probe_gap(250, "11", "01", "11");   -- midpoint: new snaps to medium
    probe_gap(252, "11", "01", "11");   -- old dead-band -> new: medium
    probe_gap(344, "11", "01", "11");   -- old dead-band 343..354 -> new: medium
    probe_gap(352, "11", "10", "11");   -- old dead-band -> new: long
    probe_gap(126, "11", "11", "11");   -- the measured artifact gap: loud everywhere
    probe_gap(448, "11", "10", "11");   -- past the old long window -> new: long
    probe_gap(460, "11", "11", "11");   -- beyond 4.5*est: loud everywhere
    probe_gap(148, "11", "11", "11");   -- below 1.5*est: loud everywhere

    ---------------------------------------------------------------------
    -- PHASE 1: A/B decoder trials
    ---------------------------------------------------------------------
    report "==== PHASE 1: A/B decoder trials ====";
    --         name                fam mode       sp0    sp1    jit ps  art   must  seed
    run_trial("canonical",          0, M_UNIFORM, 1.000, 1.000,  0,  0, false, true,  1);

    run_trial("speed +1.5%",        1, M_UNIFORM, 1.015, 1.015,  0,  0, false, true,  2);
    run_trial("speed -1.5%",        1, M_UNIFORM, 0.985, 0.985,  0,  0, false, true,  3);
    run_trial("speed +3%",          1, M_UNIFORM, 1.030, 1.030,  0,  0, false, true,  4);
    run_trial("speed -3%",          1, M_UNIFORM, 0.970, 0.970,  0,  0, false, true,  5);
    run_trial("speed +5%",          1, M_UNIFORM, 1.050, 1.050,  0,  0, false, true,  6);
    run_trial("speed -5%",          1, M_UNIFORM, 0.950, 0.950,  0,  0, false, true,  7);
    run_trial("speed +8%",          1, M_UNIFORM, 1.080, 1.080,  0,  0, false, true,  8);
    run_trial("speed -8%",          1, M_UNIFORM, 0.920, 0.920,  0,  0, false, true,  9);
    run_trial("speed +12% (disc)",  1, M_UNIFORM, 1.120, 1.120,  0,  0, false, true, 10);
    run_trial("speed -12% (disc)",  1, M_UNIFORM, 0.880, 0.880,  0,  0, false, true, 11);

    run_trial("drift 0..+2%",       2, M_DRIFT,   1.000, 1.020,  0,  0, false, true, 12);
    run_trial("drift 0..-2%",       2, M_DRIFT,   1.000, 0.980,  0,  0, false, true, 13);
    run_trial("drift 0..+12% (disc)", 2, M_DRIFT, 1.000, 1.120,  0,  0, false, true, 14);
    run_trial("drift 0..-12% (disc)", 2, M_DRIFT, 1.000, 0.880,  0,  0, false, true, 15);

    run_trial("jitter +/-8 s1",     3, M_UNIFORM, 1.000, 1.000,  8,  0, false, true, 16);
    run_trial("jitter +/-8 s2",     3, M_UNIFORM, 1.000, 1.000,  8,  0, false, true, 17);
    run_trial("jitter +/-8 s3",     3, M_UNIFORM, 1.000, 1.000,  8,  0, false, true, 18);
    run_trial("jitter +/-12 s1",    3, M_UNIFORM, 1.000, 1.000, 12,  0, false, true, 19);
    run_trial("jitter +/-12 s2",    3, M_UNIFORM, 1.000, 1.000, 12,  0, false, true, 20);
    run_trial("jitter +/-12 s3",    3, M_UNIFORM, 1.000, 1.000, 12,  0, false, true, 21);
    run_trial("jitter +/-22 s1 (disc)", 3, M_UNIFORM, 1.000, 1.000, 22, 0, false, false, 22);
    run_trial("jitter +/-22 s2 (disc)", 3, M_UNIFORM, 1.000, 1.000, 22, 0, false, false, 23);
    run_trial("jitter +/-22 s3 (disc)", 3, M_UNIFORM, 1.000, 1.000, 22, 0, false, false, 24);
    run_trial("jitter +/-24 s1 (disc)", 3, M_UNIFORM, 1.000, 1.000, 24, 0, false, false, 25);
    run_trial("jitter +/-24 s2 (disc)", 3, M_UNIFORM, 1.000, 1.000, 24, 0, false, false, 26);
    run_trial("jitter +/-24 s3 (disc)", 3, M_UNIFORM, 1.000, 1.000, 24, 0, false, false, 27);

    run_trial("peak S=10",          4, M_UNIFORM, 1.000, 1.000,  0, 10, false, true, 28);
    run_trial("peak S=15",          4, M_UNIFORM, 1.000, 1.000,  0, 15, false, true, 29);
    run_trial("peak S=20",          4, M_UNIFORM, 1.000, 1.000,  0, 20, false, true, 30);
    run_trial("peak S=22 (disc)",   4, M_UNIFORM, 1.000, 1.000,  0, 22, false, false, 31);
    run_trial("peak S=24 (cliff)",  4, M_UNIFORM, 1.000, 1.000,  0, 24, false, false, 32);

    -- inner-cylinder hardware model: peak shift at a speed offset. These are
    -- counted toward the peak family (they ARE peak-shift vectors at real
    -- operating points; pure peak shift <= 20 stays inside the old windows
    -- by construction, so the old classifier only dead-bands where shift and
    -- speed combine -- exactly the cyl-60+ hardware evidence).
    run_trial("combo S20 +3% (disc)", 4, M_UNIFORM, 1.030, 1.030, 0, 20, false, true, 33);
    run_trial("combo S20 -3% (disc)", 4, M_UNIFORM, 0.970, 0.970, 0, 20, false, true, 34);
    run_trial("combo S15 +5% (disc)", 4, M_UNIFORM, 1.050, 1.050, 0, 15, false, true, 35);

    run_trial("artifact 126",       6, M_UNIFORM, 1.000, 1.000,  0,  0, true,  true, 36);
    run_trial("artifact 126 +3%",   6, M_UNIFORM, 1.030, 1.030,  0,  0, true,  true, 37);

    run_trial("splice +2.5% step",  7, M_SPLICE,  1.000, 1.025,  0,  0, false, true, 38);

    ---------------------------------------------------------------------
    -- PHASE 2: table + acceptance
    ---------------------------------------------------------------------
    report "==== A/B RESULT TABLE (old fixed windows vs new adaptive) ====";
    for k in 0 to nres - 1 loop
      report res(k).name & " | old=" & pf(res(k).old_ok) & " | new=" & pf(res(k).new_ok)
           & " | est " & integer'image(res(k).emin) & ".." & integer'image(res(k).emax);
    end loop;

    for k in 0 to nres - 1 loop
      if res(k).old_ok and not res(k).new_ok then
        report "FAIL (REGRESSION): " & res(k).name & " old passed, new failed" severity error;
        fails := fails + 1;
      end if;
      if res(k).must_n and not res(k).new_ok then
        report "FAIL (must_new): " & res(k).name & " new decoder did not decode" severity error;
        fails := fails + 1;
      end if;
    end loop;
    if not (res(0).old_ok and res(0).new_ok) then
      report "FAIL: canonical regression (both must decode byte-exact)" severity error;
      fails := fails + 1;
    end if;
    if wins(1) < 1 then
      report "FAIL: no new-over-old win in the SPEED family" severity error; fails := fails + 1;
    end if;
    if wins(2) < 1 then
      report "FAIL: no new-over-old win in the DRIFT family" severity error; fails := fails + 1;
    end if;
    if wins(3) < 1 then
      report "FAIL: no new-over-old win in the JITTER family" severity error; fails := fails + 1;
    end if;
    if wins(4) < 1 then
      report "FAIL: no new-over-old win in the PEAK/COMBO family" severity error; fails := fails + 1;
    end if;
    report "family wins (new ok, old fail): speed=" & integer'image(wins(1))
         & " drift=" & integer'image(wins(2)) & " jitter=" & integer'image(wins(3))
         & " peak/combo=" & integer'image(wins(4)) & " artifact=" & integer'image(wins(6))
         & " splice=" & integer'image(wins(7));

    if fails = 0 then
      report "tb_physical_1581_quantise_ab: ALL ACCEPTANCE CRITERIA MET";
    else
      report "tb_physical_1581_quantise_ab: " & integer'image(fails) & " FAILURES" severity failure;
    end if;
    finish;
  end process;

  -- global guard: 38 trials x ~20 ms + probes
  guard : process
  begin
    wait for 1500 ms;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
