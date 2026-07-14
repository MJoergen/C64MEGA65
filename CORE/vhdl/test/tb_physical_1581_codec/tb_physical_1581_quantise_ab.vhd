-------------------------------------------------------------------------------
-- tb_physical_1581_quantise_ab.vhd   (issue #90 rounds 12 through 14)
--
-- A/B margin harness: SEVEN complete decoders run in parallel on
-- identical stress flux, so every trial reports one row of
--   old | r12 | r13 | prod | tacq | spanoff | seqoff
--
--   * old  = the pre-round-12 FIXED-WINDOW classifier (library q_old = the
--            production sources with the test-only ref_mfm_quantise_fixed.vhd
--            analyzed in place of physical_1581_mfm_quantise; sync gate off =
--            exact round-11 behavior)
--   * r12  = round-12 compatibility instance (production sources with
--            G_SYNC_GATE => false, G_QUANT_HUNT_ADAPT_ALL => true -- exactly
--            the round-12 RTL semantics: no sync gate, adapt on every
--            accepted gap)
--   * r13  = superseded round-13 00-preamble gate, retained to prove both
--            its splice fix and its F011 zero-ID regression
--   * prod = production adaptive quantiser + complete-A1 span, exact
--            three-A1 train spacing and ID-before-DAM record sequencing
--   * tacq = the REFUTED round-13 fix candidate (two-tier tolerance, tight
--            est/4 acquisition: G_QUANT_TOL_ACQ_SHR => 2, no gate). Kept as
--            live evidence of WHY the shipped fix is the preamble-run sync
--            gate instead: ISI deviates every gap of the A1 train itself by
--            2*S, so est/4 rejects the sync train of any record with peak
--            shift S >= 13 and loses the peak/combo win rows below.
--   * spanoff = exact commit-3803152 production semantics: adaptive hunting
--               plus candidate spacing, but no complete-A1 span check. Kept
--               to hard-prove the new spaced-junk failure mechanism.
--   * seqoff = exact commit-0ab9f92 production semantics: complete-A1 span
--              qualification, but no ID-before-DAM record sequencing. Kept
--              to reproduce the new hardware failure upper bound.
--
-- Build (three libraries, SEPARATE workdirs -- the per-library object files
-- share basenames and would overwrite each other in a shared directory):
--   ghdl -a --std=08 --work=q_new --workdir=B/new  <pkg,crc,gaps,quantise,
--        gaps_to_bits,bits_to_bytes,decoder>
--   ghdl -a --std=08 --work=q_old --workdir=B/old  <pkg,crc,gaps,
--        ref_mfm_quantise_fixed,gaps_to_bits,bits_to_bytes,decoder>
--   ghdl -a --std=08 --workdir=B/top -PB/new -PB/old  mfm_flux_gen_pkg.vhd
--        <this file>
--   ghdl --elab-run --std=08 --workdir=B/top -PB/new -PB/old
--        tb_physical_1581_quantise_ab --assert-level=error
--
-- Vector classes (one canonical 1581 record = ID field C/H/R/N + 512-byte
-- data field, lead-in/gap/trailer included):
--   (i)    dual formatter layouts   -- exact stock-ROM and pinned-F011 ID gaps
--                                      (including F011's first/subsequent IDs)
--   (ii)   uniform speed offsets    -- +/-1.5%, 3%, 5%, 8% (both) and the
--                                      +/-12% discriminators (old must die:
--                                      long gaps leave 355..445 / hit a
--                                      dead-band; adaptive tracks, clamped
--                                      +/-10%)
--   (iii)  linear drift             -- +/-2% end-to-end (spec) and +/-12%
--   (iv)   random jitter            -- PER-EDGE uniform, +/-8 and +/-12 (spec;
--                                      strictly harder than the per-gap model,
--                                      a gap sees up to twice the amplitude),
--                                      +/-22 and +/-24 as discriminators
--   (v)    peak shift (ISI)         -- every flux transition moves S cycles
--                                      toward its longer neighboring gap,
--                                      S in {10,15,20} (spec) + {22,24};
--                                      combined with speed offsets ("combo",
--                                      the inner-cylinder hardware model:
--                                      S20 +/-3%, S15 +5%) where the old
--                                      windows demonstrably dead-band
--   (vi)   126-cycle artifact       -- the stable mid-gap extra edge measured
--                                      on the test disk (GAP_MIN = 0x007E),
--                                      injected into the ID sync-train preamble
--   (vii)  splice                   -- abrupt +2.5% speed step mid-preamble
--   (viii) JUNK SPLICE (round 13)   -- write-splice garbage flux emitted
--                                      before the record (profiles in
--                                      mfm_flux_gen_pkg). The "junk chain"
--                                      trials reproduce the round-12 hardware
--                                      regression gap-exact (t39 s1 after the
--                                      index splice deterministically
--                                      unreadable): they MUST show
--                                      old=PASS, r12=FAIL, r13=PASS, prod=PASS
--                                      on the stock layout; production also
--                                      passes the F011 layout and junk chain.
--                                      The "junk spaced A1" profile adds three
--                                      false candidates at correct spacing and
--                                      with short separators, but with a 1580-
--                                      cycle rather than ~1400-cycle raw-word
--                                      span.
--
-- ACCEPTANCE (all machine-checked at the end):
--   * canonical decodes byte-exact on old, r12, r13 and production;
--   * F011 first and subsequent IDs decode in production while the r13 column
--     hard-reproduces its zero-ID failure;
--   * NO REGRESSION: no trial where the old decoder succeeds and production
--     fails; every must_new trial decodes byte-exact in production;
--   * the r12 instance passes every must_new row of the original round-12
--     table (fam < 8) -- proves the compatibility instance is faithful;
--   * per stress family (speed / drift / jitter / peak+combo) at least one
--     trial where production succeeds and the OLD decoder fails (the round-12 wins
--     are preserved);
--   * every stock-layout junk-chain trial: old/r13/production=PASS, r12=FAIL,
--     while the F011 junk-chain row is production=PASS and r13=FAIL; the r12
--     failure is a BOGUS DATA FIELD opened during the junk (data_start
--     observed before the record could have produced one) -- the confirmed
--     false-A1 mechanism;
--   * the tacq instance fails at least one must_new peak/combo row -- the
--     recorded refutation of the tight-acquisition fix candidate;
--   * SILENT-CORRUPTION GUARD: any CRC-approved decode (any instance, any
--     trial) whose ID fields or payload differ from the golden record is a
--     FATAL failure -- CRC-caught corruption is acceptable, silent wrong
--     payload is not.
--
-- A quantiser-level probe phase additionally documents single-gap decisions
-- of old vs adaptive-est/2 vs adaptive-est/4 (the est/4 variant retains
-- ~50-cycle dead-bands -- see the C_QUANT_* comments in physical_1581_pkg).
--
-- C64MEGA65 project. SIMULATION ONLY.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
use work.mfm_flux_gen_pkg.all;      -- crc16_update, MFM_A1_RAW, junk model

library q_new;
library q_old;

entity tb_physical_1581_quantise_ab is
end entity;

architecture sim of tb_physical_1581_quantise_ab is

  constant NAME_LEN : integer := 26;
  constant MAXT     : integer := 6144;   -- max flux transitions per record
  constant NDUT     : integer := 7;      -- 0=old 1=r12 2=r13 3=prod 4=tacq 5=spanoff 6=seqoff

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
  signal in_junk : std_logic := '0';

  -- per-instance decoder outputs
  type u8xN   is array (0 to NDUT - 1) of unsigned(7 downto 0);
  type bytexN is array (0 to NDUT - 1) of byte_arr;
  type intxN  is array (0 to NDUT - 1) of integer;
  type timexN is array (0 to NDUT - 1) of time;

  signal d_id_valid, d_id_crc_ok, d_data_start, d_bytev, d_data_end,
         d_data_crc_ok, d_lock, d_gerr : std_logic_vector(0 to NDUT - 1);
  signal d_idc, d_idh, d_idr, d_idn, d_byte : u8xN;
  signal n_est : unsigned(11 downto 0);            -- production instance only

  -- per-instance captures
  signal c_id_seen, c_id_ok, c_saw_end, c_crc_ok : std_logic_vector(0 to NDUT - 1) := (others => '0');
  signal c_c, c_h, c_r, c_n : u8xN := (others => (others => '0'));
  signal c_cap : bytexN := (others => (others => (others => '0')));
  signal c_idx : intxN := (others => 0);
  signal n_est_min : integer := 4095;
  signal n_est_max : integer := 0;

  -- mechanism instrumentation (round 13): junk-window gap errors, junk-window
  -- locks (false A1 evidence) and data_start pulses with first-pulse time
  signal m_jerr   : intxN := (others => 0);
  signal m_lockj  : std_logic_vector(0 to NDUT - 1) := (others => '0');
  signal m_ds_cnt : intxN := (others => 0);
  signal m_ds_t   : timexN := (others => 0 fs);

  -- quantiser probe instances (fed directly, no gaps stage)
  signal p_rst   : std_logic := '1';
  signal p_valid : std_logic := '0';
  signal p_len   : unsigned(15 downto 0) := (others => '0');
  signal p_cls_old, p_cls_t2, p_cls_t4 : unsigned(1 downto 0);

  -- results table
  type res_rec is record
    name    : string(1 to NAME_LEN);
    fam     : integer;   -- 0 can / 1 speed / 2 drift / 3 jit / 4 peak+combo
                         -- / 6 art / 7 splice / 8 junk
    ok      : boolean_vector(0 to NDUT - 1);   -- old/r12/r13/prod/tacq/spanoff/seqoff
    must_n  : boolean;
    emin    : integer;   -- production-side est excursion (integer cycles)
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

  function iname(k : integer) return string is
  begin
    case k is
      when 0      => return "old ";
      when 1      => return "r12 ";
      when 2      => return "r13 ";
      when 3      => return "prod";
      when 4      => return "tacq";
      when 5      => return "spanoff";
      when others => return "seqoff";
    end case;
  end function;

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  ---------------------------------------------------------------------------
  -- the seven decoders under test, same flux
  ---------------------------------------------------------------------------
  -- 0: pre-round-12 fixed windows (exact round-11: no sync gate)
  dut_old : entity q_old.physical_1581_mfm_decoder
    generic map (G_SYNC_GATE => false, G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(0), id_c_o => d_idc(0), id_h_o => d_idh(0),
      id_r_o => d_idr(0), id_n_o => d_idn(0), id_crc_ok_o => d_id_crc_ok(0),
      data_start_o => d_data_start(0), data_byte_o => d_byte(0),
      data_byte_valid_o => d_bytev(0), data_end_o => d_data_end(0),
      data_crc_ok_o => d_data_crc_ok(0),
      locked_o => d_lock(0), gap_error_o => d_gerr(0)
    );

  -- 1: round-12 compatibility (exact round-12 RTL semantics)
  dut_r12 : entity q_new.physical_1581_mfm_decoder
    generic map (G_SYNC_GATE => false, G_QUANT_HUNT_ADAPT_ALL => true,
                 G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(1), id_c_o => d_idc(1), id_h_o => d_idh(1),
      id_r_o => d_idr(1), id_n_o => d_idn(1), id_crc_ok_o => d_id_crc_ok(1),
      data_start_o => d_data_start(1), data_byte_o => d_byte(1),
      data_byte_valid_o => d_bytev(1), data_end_o => d_data_end(1),
      data_crc_ok_o => d_data_crc_ok(1),
      locked_o => d_lock(1), gap_error_o => d_gerr(1)
    );

  -- 2: exact round-13 preamble-gate behavior (historical regression column)
  dut_r13 : entity q_new.physical_1581_mfm_decoder
    generic map (G_SYNC_PREAMBLE_GATE => true, G_QUANT_HUNT_ADAPT_ALL => false,
                 G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(2), id_c_o => d_idc(2), id_h_o => d_idh(2),
      id_r_o => d_idr(2), id_n_o => d_idn(2), id_crc_ok_o => d_id_crc_ok(2),
      data_start_o => d_data_start(2), data_byte_o => d_byte(2),
      data_byte_valid_o => d_bytev(2), data_end_o => d_data_end(2),
      data_crc_ok_o => d_data_crc_ok(2),
      locked_o => d_lock(2), gap_error_o => d_gerr(2)
    );

  -- 3: production adaptive decoder with exact A1-train qualification
  dut_new : entity q_new.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(3), id_c_o => d_idc(3), id_h_o => d_idh(3),
      id_r_o => d_idr(3), id_n_o => d_idn(3), id_crc_ok_o => d_id_crc_ok(3),
      data_start_o => d_data_start(3), data_byte_o => d_byte(3),
      data_byte_valid_o => d_bytev(3), data_end_o => d_data_end(3),
      data_crc_ok_o => d_data_crc_ok(3),
      locked_o => d_lock(3), gap_error_o => d_gerr(3),
      est_o => n_est
    );

  -- 4: refuted fix candidate (tight est/4 acquisition tier, no gate)
  dut_tacq : entity q_new.physical_1581_mfm_decoder
    generic map (G_SYNC_GATE => false, G_QUANT_TOL_ACQ_SHR => 2,
                 G_QUANT_HUNT_ADAPT_ALL => false,
                 G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(4), id_c_o => d_idc(4), id_h_o => d_idh(4),
      id_r_o => d_idr(4), id_n_o => d_idn(4), id_crc_ok_o => d_id_crc_ok(4),
      data_start_o => d_data_start(4), data_byte_o => d_byte(4),
      data_byte_valid_o => d_bytev(4), data_end_o => d_data_end(4),
      data_crc_ok_o => d_data_crc_ok(4),
      locked_o => d_lock(4), gap_error_o => d_gerr(4)
    );

  -- 5: exact commit-3803152 spacing-only production behavior
  dut_spanoff : entity q_new.physical_1581_mfm_decoder
    generic map (G_SYNC_SPAN_GATE => false, G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(5), id_c_o => d_idc(5), id_h_o => d_idh(5),
      id_r_o => d_idr(5), id_n_o => d_idn(5), id_crc_ok_o => d_id_crc_ok(5),
      data_start_o => d_data_start(5), data_byte_o => d_byte(5),
      data_byte_valid_o => d_bytev(5), data_end_o => d_data_end(5),
      data_crc_ok_o => d_data_crc_ok(5),
      locked_o => d_lock(5), gap_error_o => d_gerr(5)
    );

  -- 6: exact commit-0ab9f92 behavior (span-qualified, no record sequencing)
  dut_seqoff : entity q_new.physical_1581_mfm_decoder
    generic map (G_RECORD_SEQUENCE_GATE => false)
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => d_id_valid(6), id_c_o => d_idc(6), id_h_o => d_idh(6),
      id_r_o => d_idr(6), id_n_o => d_idn(6), id_crc_ok_o => d_id_crc_ok(6),
      data_start_o => d_data_start(6), data_byte_o => d_byte(6),
      data_byte_valid_o => d_bytev(6), data_end_o => d_data_end(6),
      data_crc_ok_o => d_data_crc_ok(6),
      locked_o => d_lock(6), gap_error_o => d_gerr(6)
    );

  ---------------------------------------------------------------------------
  -- quantiser probe instances (single-gap decision table)
  ---------------------------------------------------------------------------
  probe_old : entity q_old.physical_1581_mfm_quantise
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_old);

  probe_t2 : entity q_new.physical_1581_mfm_quantise   -- production: tol = est/2
    generic map (G_TOL_ACQ_SHR => 1, G_TOL_FIELD_SHR => 1)
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_t2);

  probe_t4 : entity q_new.physical_1581_mfm_quantise   -- refuted: tol = est/4
    generic map (G_TOL_ACQ_SHR => 2, G_TOL_FIELD_SHR => 2)
    port map (clk_i => clk, rst_i => p_rst, gap_valid_i => p_valid,
              gap_len_i => p_len, gap_class_o => p_cls_t4);

  ---------------------------------------------------------------------------
  -- capture, all instances
  ---------------------------------------------------------------------------
  cap_p : process (clk)
  begin
    if rising_edge(clk) then
      if cap_clr = '1' then
        c_id_seen <= (others => '0'); c_id_ok  <= (others => '0');
        c_saw_end <= (others => '0'); c_crc_ok <= (others => '0');
        c_idx     <= (others => 0);
        n_est_min <= 4095; n_est_max <= 0;
        m_jerr    <= (others => 0);
        m_lockj   <= (others => '0');
        m_ds_cnt  <= (others => 0);
        m_ds_t    <= (others => 0 fs);
      else
        for k in 0 to NDUT - 1 loop
          if d_data_start(k) = '1' then
            c_idx(k) <= 0;
          elsif d_bytev(k) = '1' then
            if c_idx(k) < 512 then
              c_cap(k)(c_idx(k)) <= d_byte(k);
            end if;
            if c_idx(k) < 4095 then
              c_idx(k) <= c_idx(k) + 1;
            end if;
          end if;
          if d_id_valid(k) = '1' then
            c_id_seen(k) <= '1';
            c_c(k) <= d_idc(k); c_h(k) <= d_idh(k);
            c_r(k) <= d_idr(k); c_n(k) <= d_idn(k);
            c_id_ok(k) <= d_id_crc_ok(k);
          end if;
          if d_data_end(k) = '1' then
            c_saw_end(k) <= '1';
            c_crc_ok(k)  <= d_data_crc_ok(k);
          end if;
          -- mechanism instrumentation
          if d_gerr(k) = '1' and in_junk = '1' then
            m_jerr(k) <= m_jerr(k) + 1;
          end if;
          if d_lock(k) = '1' and in_junk = '1' then
            m_lockj(k) <= '1';
          end if;
          if d_data_start(k) = '1' then
            if m_ds_cnt(k) = 0 then
              m_ds_t(k) <= now;
            end if;
            m_ds_cnt(k) <= m_ds_cnt(k) + 1;
          end if;
        end loop;
        if to_integer(n_est) < n_est_min then n_est_min <= to_integer(n_est); end if;
        if to_integer(n_est) > n_est_max then n_est_max <= to_integer(n_est); end if;
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
    variable wins  : int_arr(0 to 9) := (others => 0);   -- production-over-old wins per family
    variable fails : integer := 0;
    variable tacq_peak_fails : integer := 0;

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

    -- Build one complete 512-byte record using an explicit formatter layout.
    -- Stock 1581 ROM (318045-02, $C3F8..$C51D): 32 x 4E + 12 x 00
    -- before the ID, 22 x 4E + 12 x 00 before data. MEGA65 F011
    -- auto-format (mega65-core a9158930 sdcardio.vhdl FDCAutoFormatTrack):
    -- no 00 bytes before IDs; data still has 12 x 00. Keeping these as
    -- separate vectors prevents formatter-specific acquisition rules.
    procedure build_record(lead_4e, id_zeros, id_data_4e, trailer_4e : natural;
                           prefix_zeros : natural := 0;
                           prefix_fake_dam : boolean := false;
                           prefix_armed_fake_dam : boolean := false) is
    begin
      nt := 0; hc := 0; prev := '0';
      art_after_t := -1; splice_t := -1;
      for k in 1 to prefix_zeros loop enc_byte(x"00"); end loop;
      -- Hardware map-v6 evidence shows two additional, timing-valid A1 trains
      -- per revolution. This is the indistinguishable upper bound: a complete
      -- A1x3+FB before any valid ID, followed by enough junk for the old parser
      -- to consume the real record as a bogus 512-byte data field. Production
      -- must ignore the unsolicited DAM and acquire the following real ID.
      if prefix_fake_dam then
        for k in 1 to 8 loop enc_byte(x"00"); end loop;
        enc_a1; enc_a1; enc_a1; enc_byte(x"FB");
        for k in 1 to 32 loop enc_byte(x"4E"); end loop;
      end if;
      -- Stronger recovery case: a CRC-valid decoy ID legitimately arms the
      -- following bogus DAM. Production must start that field, then let the
      -- real record's qualified FE preempt the unfinished 512-byte parse.
      if prefix_armed_fake_dam then
        for k in 1 to 8 loop enc_byte(x"00"); end loop;
        enc_a1; enc_a1; enc_a1; enc_byte(x"FE");
        enc_byte(TC); enc_byte(TH); enc_byte(TR); enc_byte(TN);
        crcv := x"FFFF";
        crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"A1");
        crcv := crc16_update(crcv, x"A1"); crcv := crc16_update(crcv, x"FE");
        crcv := crc16_update(crcv, TC); crcv := crc16_update(crcv, TH);
        crcv := crc16_update(crcv, TR); crcv := crc16_update(crcv, TN);
        enc_byte(crcv(15 downto 8)); enc_byte(crcv(7 downto 0));
        for k in 1 to 8 loop enc_byte(x"4E"); end loop;
        for k in 1 to 8 loop enc_byte(x"00"); end loop;
        enc_a1; enc_a1; enc_a1; enc_byte(x"FB");
        for k in 1 to 32 loop enc_byte(x"4E"); end loop;
      end if;
      for k in 1 to lead_4e loop enc_byte(x"4E"); end loop;
      for k in 1 to id_zeros loop
        if k = 7 then art_after_t := nt - 1; end if;
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
      for k in 1 to id_data_4e loop enc_byte(x"4E"); end loop;
      for k in 1 to 12 loop
        if k = 7 then splice_t := nt; end if;
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
      for k in 1 to trailer_4e loop enc_byte(x"4E"); end loop;
      report "record built: " & integer'image(nt) & " flux transitions, "
           & integer'image(hc) & " half-cells";
      assert nt < MAXT - 8 report "MAXT too small" severity failure;
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
      name         : string;
      fam          : integer;
      mode         : mode_t;
      sp0          : real;
      sp1          : real;
      jit          : integer;
      pshift       : integer;
      artifact     : boolean;
      must_new     : boolean;
      seed         : integer;
      junk         : integer := -1;      -- <0 none; 100+s rand; 200+s chain; 300+s spaced
      exp_r12_fail : boolean := false;   -- junk-chain: r12 MUST fail (regression proof)
      exp_seqoff_fail : boolean := false -- timing-valid unsolicited DAM: 0ab9f92 MUST fail
    ) is
      variable t   : real_arr(0 to MAXT - 1);
      variable sh  : real_arr(0 to MAXT - 1);
      variable ti  : int_arr(0 to MAXT);
      variable g, gb, ga, sfac : real;
      variable ne  : integer;
      variable okv : boolean_vector(0 to NDUT - 1);
      variable pm  : boolean;
      variable jarr   : junk_arr_t;
      variable rec_t0 : time;
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

      -- 5) reset all decoders, clear captures
      f_rdata <= '1';
      cap_clr <= '1';
      rst     <= '1';
      for k in 1 to 8 loop wait until rising_edge(clk); end loop;
      rst     <= '0';
      cap_clr <= '0';
      for k in 1 to 8 loop wait until rising_edge(clk); end loop;

      -- 5b) write-splice junk (round 13): emitted RAW in the cycle domain
      --     before the record; the profile's last entry is the boundary gap,
      --     closed by the record's first transition
      if junk >= 300 then
        jarr := junk_splice_spaced(junk - 300);
      elsif junk >= 200 then
        jarr := junk_splice_chain(junk - 200);
      elsif junk >= 100 then
        jarr := junk_splice_rand(junk - 100);
      end if;
      if junk >= 0 then
        in_junk <= '1';
        for k in 0 to jarr.cnt - 1 loop
          f_rdata <= '0';
          wait for 200 ns;
          f_rdata <= '1';
          wait for jarr.g(k) * 20 ns - 200 ns;
        end loop;
        in_junk <= '0';
      end if;
      rec_t0 := now;

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

      -- 7) evaluate every instance. Success = ID byte-exact + CRC, data CRC
      --    + payload exact. SILENT-CORRUPTION GUARD per instance: a
      --    CRC-approved decode with wrong content is FATAL.
      for k in 0 to NDUT - 1 loop
        pm := (c_idx(k) = 512);
        if pm then
          for i in 0 to 511 loop
            if c_cap(k)(i) /= pl(i) then pm := false; end if;
          end loop;
        end if;
        okv(k) := (c_id_seen(k) = '1' and c_id_ok(k) = '1' and c_c(k) = TC and
                   c_h(k) = TH and c_r(k) = TR and c_n(k) = TN and
                   c_saw_end(k) = '1' and c_crc_ok(k) = '1' and pm);
        if c_id_seen(k) = '1' and c_id_ok(k) = '1' then
          assert (c_c(k) = TC and c_h(k) = TH and c_r(k) = TR and c_n(k) = TN)
            report "SILENT ID CORRUPTION (" & iname(k) & ") in trial " & name
            severity failure;
        end if;
        if c_saw_end(k) = '1' and c_crc_ok(k) = '1' then
          assert pm
            report "SILENT PAYLOAD CORRUPTION (" & iname(k) & ") in trial " & name
            severity failure;
        end if;
      end loop;
      -- junk trials: mechanism evidence + expectations
      if junk >= 0 then
        for k in 0 to NDUT - 1 loop
          report "MECH " & pad(name) & " " & iname(k)
               & ": junk_gap_errors=" & integer'image(m_jerr(k))
               & " junk_lock=" & std_logic'image(m_lockj(k))
               & " data_start_cnt=" & integer'image(m_ds_cnt(k))
               & " first_data_start=" & time'image(m_ds_t(k))
               & " (record starts " & time'image(rec_t0) & ")";
        end loop;
        if not okv(0) then
          report "FAIL: junk trial " & name & " broke the OLD decoder (model too aggressive)"
            severity error;
          fails := fails + 1;
        end if;
        if not okv(3) then
          report "FAIL: junk trial " & name & " broke the production decoder"
            severity error;
          fails := fails + 1;
        end if;
        if fam = 8 and not okv(2) then
          report "FAIL: stock-layout junk trial " & name
               & " broke the round-13 reference decoder" severity error;
          fails := fails + 1;
        end if;
        if exp_r12_fail then
          if okv(1) then
            report "FAIL: JUNK MODEL TOO TAME in " & name
                 & " -- the round-12 decoder did not fail" severity error;
            fails := fails + 1;
          else
            -- confirm the mechanism: r12 opened a data field during/right
            -- after the junk, before the record's real FB mark (which sits
            -- 68 byte times = ~2.2 ms into the record) could have produced one
            if m_ds_cnt(1) = 0 or m_ds_t(1) > rec_t0 + 1 ms then
              report "FAIL: r12 failed " & name
                   & " but WITHOUT the bogus-data-field signature (mechanism?)"
                severity error;
              fails := fails + 1;
            else
              report "CONFIRMED (" & pad(name) & "): r12 false-A1 chain opened a bogus"
                   & " data field in the splice junk at " & time'image(m_ds_t(1))
                   & " and consumed the record";
            end if;
          end if;
        end if;
        if junk >= 300 then
          if okv(5) then
            report "FAIL: SPACING-ONLY CONTROL TOO STRONG in " & name
                 & " -- commit-3803152 behavior did not fail" severity error;
            fails := fails + 1;
          elsif m_ds_cnt(5) = 0 or m_ds_t(5) > rec_t0 + 1 ms then
            report "FAIL: spacing-only control failed " & name
                 & " without the bogus-data-field signature" severity error;
            fails := fails + 1;
          else
            report "CONFIRMED (" & pad(name) & "): commit-3803152 spacing-only"
                 & " qualification opened a bogus data field at "
                 & time'image(m_ds_t(5));
          end if;
        end if;
      end if;
      if exp_seqoff_fail then
        if not okv(3) then
          report "FAIL: record-sequenced production did not recover after unsolicited DAM"
            severity error;
          fails := fails + 1;
        end if;
        if okv(6) then
          report "FAIL: 0ab9f92 control survived timing-valid unsolicited DAM"
            severity error;
          fails := fails + 1;
        elsif m_ds_cnt(6) = 0 then
          report "FAIL: 0ab9f92 control failed without opening the bogus data field"
            severity error;
          fails := fails + 1;
        else
          report "CONFIRMED: 0ab9f92 opened an unsolicited timing-valid DAM;"
               & " record-sequenced production ignored it and decoded the real record";
        end if;
      end if;

      res(nres) := (name => pad(name), fam => fam, ok => okv,
                    must_n => must_new, emin => n_est_min / 16,
                    emax => (n_est_max + 15) / 16);
      nres := nres + 1;
      if okv(3) and not okv(0) then
        wins(fam) := wins(fam) + 1;
      end if;
      report "TRIAL " & pad(name) & " old=" & pf(okv(0)) & " r12=" & pf(okv(1))
           & " r13=" & pf(okv(2)) & " prod=" & pf(okv(3)) & " tacq=" & pf(okv(4))
           & " spanoff=" & pf(okv(5)) & " seqoff=" & pf(okv(6))
           & "  est=[" & integer'image(n_est_min / 16) & ".." & integer'image((n_est_max + 15) / 16) & "]";
    end procedure;

  begin
    ---------------------------------------------------------------------
    -- Build the stock 1581-ROM record first. The exact ROM uses 32 lead-in
    -- 4E bytes and 22 ID/data-gap 4E bytes. Eight trailing bytes are enough
    -- for this finite test vector after the completed data CRC.
    ---------------------------------------------------------------------
    build_record(32, 12, 22, 8);
    assert art_after_t > 0 and splice_t > 0 severity failure;

    rst <= '1';
    wait for 200 ns;

    ---------------------------------------------------------------------
    -- PHASE 0: single-gap probe table (old / est-div-4 / est-div-2), all
    -- from a freshly-seeded est = 100.0. Documents the dead-band removal
    -- and why the production tolerance is est/2 (C_QUANT_TOL_SHR = 1):
    -- the est/4 variant rejects the very dead-band gaps (241..257,
    -- 343..354) the round-11 hardware failure produced.
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
    -- PHASE 1a: MEGA65 F011 auto-format compatibility. Do this first so
    -- a formatter-specific acquisition regression fails quickly instead
    -- of after the complete margin matrix. Sector IDs have NO 00 preamble
    -- The first ID follows the track-info block's four-zero flush and one final
    -- 4E; subsequent IDs follow 24 x 4E. Neither has an immediately adjacent
    -- 00 preamble. Data retains 12 x 00.
    ---------------------------------------------------------------------
    report "==== PHASE 1a: F011 auto-format compatibility ====";
    build_record(1, 0, 23, 8, prefix_zeros => 4);
    run_trial("F011 first ID", 9, M_UNIFORM, 1.000, 1.000, 0, 0, false, true, 46);
    assert c_id_seen(2) = '0'
      report "round-13 reference no longer reproduces the F011 zero-ID regression"
      severity failure;
    assert c_id_seen(3) = '1' and c_id_ok(3) = '1'
      report "production decoder rejected the F011 ID field without a 00 preamble"
      severity failure;
    run_trial("F011 first S20 +3%", 9, M_UNIFORM, 1.030, 1.030, 0, 20, false, true, 48);
    run_trial("F011 first S20 -3%", 9, M_UNIFORM, 0.970, 0.970, 0, 20, false, true, 49);
    build_record(24, 0, 23, 8);
    run_trial("F011 subsequent ID", 9, M_UNIFORM, 1.000, 1.000, 0, 0, false, true, 47);
    run_trial("F011 later S20 +3%", 9, M_UNIFORM, 1.030, 1.030, 0, 20, false, true, 50);
    run_trial("F011 later S20 -3%", 9, M_UNIFORM, 0.970, 0.970, 0, 20, false, true, 51);
    run_trial("F011 + junk chain",   9, M_UNIFORM, 1.000, 1.000, 0, 0, false, true, 47,
              junk => 204, exp_r12_fail => true);

    -- Map-v6 hardware upper bound: a complete timing-valid A1x3+FB splice
    -- field precedes a stock record. Sync timing alone cannot reject it;
    -- enforcing valid-ID-before-DAM must recover, while exact 0ab9f92 fails.
    build_record(32, 12, 22, 8, prefix_fake_dam => true);
    run_trial("valid unsolicited DAM", 5, M_UNIFORM, 1.000, 1.000, 0, 0,
              false, true, 53, exp_seqoff_fail => true);
    build_record(32, 12, 22, 8, prefix_armed_fake_dam => true);
    run_trial("armed bogus DAM recovery", 5, M_UNIFORM, 1.000, 1.000, 0, 0,
              false, true, 54, exp_seqoff_fail => true);

    -- Restore the stock-ROM layout for the complete historical matrix.
    build_record(32, 12, 22, 8);

    ---------------------------------------------------------------------
    -- PHASE 1: A/B decoder trials
    ---------------------------------------------------------------------
    report "==== PHASE 1: A/B decoder trials ====";
    --         name                fam mode       sp0    sp1    jit ps  art   must  seed
    run_trial("canonical",          0, M_UNIFORM, 1.000, 1.000,  0,  0, false, true,  1);
    assert c_id_seen(2) = '1' and c_id_ok(2) = '1' and
           c_saw_end(2) = '1' and c_crc_ok(2) = '1'
      report "round-13 reference failed the canonical stock-1581 record"
      severity failure;

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
    -- PHASE 1b: write-splice junk trials (round 13). The rand profile is
    -- the naive model (too tame -- everyone survives, kept as evidence of
    -- the iteration); the chain profile reproduces the round-12 hardware
    -- regression. The spaced-A1 profile defeats spacing alone and is rejected
    -- by the complete-word span qualifier.
    ---------------------------------------------------------------------
    report "==== PHASE 1b: write-splice junk trials ====";
    run_trial("junk rand s1",       8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 40, junk => 101);
    run_trial("junk rand s2",       8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 41, junk => 102);
    run_trial("junk rand s3",       8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 42, junk => 103);
    run_trial("junk chain s1",      8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 43, junk => 201, exp_r12_fail => true);
    run_trial("junk chain s2",      8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 44, junk => 202, exp_r12_fail => true);
    run_trial("junk chain s3",      8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 45, junk => 203, exp_r12_fail => true);
    run_trial("junk spaced A1",     8, M_UNIFORM, 1.000, 1.000,  0,  0, false, true, 52, junk => 301, exp_r12_fail => true);

    ---------------------------------------------------------------------
    -- PHASE 2: table + acceptance
    ---------------------------------------------------------------------
    report "==== A/B RESULT TABLE (old | r12 | r13 | prod | tacq | spanoff | seqoff) ====";
    for k in 0 to nres - 1 loop
      report res(k).name & " | old=" & pf(res(k).ok(0)) & " | r12=" & pf(res(k).ok(1))
           & " | r13=" & pf(res(k).ok(2)) & " | prod=" & pf(res(k).ok(3))
           & " | tacq=" & pf(res(k).ok(4)) & " | spanoff=" & pf(res(k).ok(5))
           & " | seqoff=" & pf(res(k).ok(6))
           & " | est " & integer'image(res(k).emin) & ".." & integer'image(res(k).emax);
    end loop;

    for k in 0 to nres - 1 loop
      if res(k).ok(0) and not res(k).ok(3) then
        report "FAIL (REGRESSION): " & res(k).name & " old passed, production failed" severity error;
        fails := fails + 1;
      end if;
      if res(k).must_n and not res(k).ok(3) then
        report "FAIL (must_new): " & res(k).name & " production did not decode" severity error;
        fails := fails + 1;
      end if;
      -- Keep the round-13 hardware failure live: every source-derived F011 ID
      -- layout must fail that historical preamble-gate column.
      if res(k).fam = 9 and res(k).ok(2) then
        report "FAIL (r13 reference): " & res(k).name
             & " no longer reproduces the F011 zero-ID regression" severity error;
        fails := fails + 1;
      end if;
      -- round-12 compat instance must reproduce the round-12 green table
      if res(k).fam < 8 and res(k).fam /= 5 and res(k).must_n and not res(k).ok(1) then
        report "FAIL (r12 compat): " & res(k).name
             & " failed on the round-12 compatibility instance" severity error;
        fails := fails + 1;
      end if;
      -- record the refutation of the tight-acquisition candidate
      if res(k).fam = 4 and res(k).must_n and not res(k).ok(4) then
        tacq_peak_fails := tacq_peak_fails + 1;
        report "REFUTATION: tight-acq candidate fails must-pass row " & res(k).name;
      end if;
    end loop;
    if wins(1) < 1 then
      report "FAIL: no production-over-old win in the SPEED family" severity error; fails := fails + 1;
    end if;
    if wins(2) < 1 then
      report "FAIL: no production-over-old win in the DRIFT family" severity error; fails := fails + 1;
    end if;
    if wins(3) < 1 then
      report "FAIL: no production-over-old win in the JITTER family" severity error; fails := fails + 1;
    end if;
    if wins(4) < 1 then
      report "FAIL: no production-over-old win in the PEAK/COMBO family" severity error; fails := fails + 1;
    end if;
    if tacq_peak_fails < 1 then
      report "FAIL: the tight-acquisition candidate passed every peak/combo row"
           & " -- the round-13 fix-selection rationale no longer holds, re-evaluate"
        severity error;
      fails := fails + 1;
    end if;
    report "family wins (production ok, old fail): speed=" & integer'image(wins(1))
         & " drift=" & integer'image(wins(2)) & " jitter=" & integer'image(wins(3))
         & " peak/combo=" & integer'image(wins(4)) & " artifact=" & integer'image(wins(6))
         & " splice=" & integer'image(wins(7)) & " junk=" & integer'image(wins(8))
         & "; tacq peak/combo refutation rows=" & integer'image(tacq_peak_fails);

    if fails = 0 then
      report "tb_physical_1581_quantise_ab: ALL ACCEPTANCE CRITERIA MET";
    else
      report "tb_physical_1581_quantise_ab: " & integer'image(fails) & " FAILURES" severity failure;
    end if;
    finish;
  end process;

  -- global guard: 54 trials x ~20 ms + probes
  guard : process
  begin
    wait for 2000 ms;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
