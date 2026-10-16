-------------------------------------------------------------------------------
-- tb_physical_1581_mfm_encoder.vhd
--
-- Self-checking GHDL testbench for physical_1581_mfm_encoder.
--
-- Two references for the channel words, neither of them the DUT expression:
--   * ref_word: a time-ordered restatement of the MFM rule written here (a
--     clock cell is '1' iff the data cells on both sides of it are '0').
--   * the flux generator of the read-side benches (mfm_flux_gen_pkg): its
--     mfm_byte / mfm_a1 procedures are run in the time domain and every
--     falling RDATA edge is timestamped against the 2 us half-cell grid, so
--     the channel bits are recovered exactly as the decoder benches lay them
--     onto the wire.
-- CRC references: crc16_update from mfm_flux_gen_pkg (the mechanism model's
-- method for its ID and data CRCs) and a table-driven CRC-16/CCITT-FALSE
-- computed here.
--
--   (a) every byte 0..255 after both carried bits: DUT = ref_word = flux pkg,
--       and the carried bit the package leaves equals the DUT's next carry
--   (b) A1 -> 0x4489, C2 -> 0x5224 (A1 also against mfm_a1 of the package),
--       for both incoming carried bits, and the carry after them (A1 -> 1,
--       C2 -> 0) seen in the clock cell of the following byte
--   (c) crc_reset + A1, A1, A1 -> crc_o = C_CRC_AFTER_3XA1 (0xCDB4)
--   (d) full sector: 12 x 00, A1 A1 A1 FB, 512 bytes of golden_payload, CRC
--       hi/lo, FF -> crc_o equals both references; the whole word stream is
--       then decoded as one continuous channel-bit sequence: every clock
--       cell obeys the rule across every byte boundary except the two
--       missing clocks of each sync, the data cells give back the bytes, and
--       the CRC over the decoded field plus the stored CRC leaves residue 0
--   (e) the Write Track F5 preset rule: preset on the first F5 of a run only
--       gives 0xCDB4 after three F5; presetting on every F5 gives the CRC of
--       a single A1 instead (asserted different); the ID field CRC that
--       follows matches the references
--   (f) timing contract: word_valid_o exactly one cycle after each valid_i
--       and never otherwise; ready_o low for exactly 10 cycles after a CRC
--       strobe; strobes at the ready_o pace never lose a CRC byte
--   (g) reset while a CRC byte is shifting, then start + 3 x A1 -> 0xCDB4
--
-- Run (B = absolute scratch workdir; run from the scratch directory):
--   ghdl -a --std=08 --workdir=B \
--     CORE/vhdl/physical_1581/physical_1581_pkg.vhd \
--     CORE/vhdl/physical_1581/physical_1581_crc.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_encoder.vhd \
--     CORE/vhdl/test/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/golden_1581_pkg.vhd \
--     CORE/vhdl/test/tb_physical_1581_codec/tb_physical_1581_mfm_encoder.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_mfm_encoder --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;
use work.golden_1581_pkg.all;

entity tb_physical_1581_mfm_encoder is
end entity;

architecture sim of tb_physical_1581_mfm_encoder is

  subtype byte_t is std_logic_vector(7 downto 0);
  subtype word_t is std_logic_vector(15 downto 0);

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal start      : std_logic := '0';
  signal byte_s     : byte_t := (others => '0');
  signal mark_s     : enc_mark_t := ENC_MARK_NONE;
  signal feed_s     : std_logic := '0';
  signal crst_s     : std_logic := '0';
  signal valid_s    : std_logic := '0';
  signal ready      : std_logic;
  signal word       : word_t;
  signal word_valid : std_logic;
  signal crc        : std_logic_vector(15 downto 0);

  -- flux-package capture
  signal flux_sig   : std_logic := '1';
  signal flux_t0    : time := 0 ns;
  signal flux_start : boolean := false;
  signal flux_req   : boolean := false;
  signal flux_done  : boolean := false;
  signal flux_kind  : integer := 0;          -- 0 = mfm_byte, 1 = mfm_a1
  signal flux_b     : byte_t := (others => '0');
  signal flux_p     : std_logic := '0';
  signal flux_pout  : std_logic := '0';      -- prev_data the package leaves
  signal rec_bits   : word_t := (others => '0');
  signal rec_offgrid : integer := 0;

  -- timing-contract monitor
  signal n_strobe   : integer := 0;
  signal n_wvalid   : integer := 0;
  signal lat_errors : integer := 0;

  -----------------------------------------------------------------------------
  -- Reference MFM word, stated in time order: channel cell 2k is the clock
  -- in front of data bit (7-k), cell 2k+1 that data bit; a clock cell is '1'
  -- iff the data cells before and after it are both '0'.
  -----------------------------------------------------------------------------
  function ref_word(b : byte_t; p : std_logic) return word_t is
    variable cells  : std_logic_vector(0 to 15);
    variable before : std_logic;
    variable w      : word_t;
  begin
    before := p;
    for k in 0 to 7 loop
      if before = '0' and b(7 - k) = '0' then
        cells(2 * k) := '1';
      else
        cells(2 * k) := '0';
      end if;
      cells(2 * k + 1) := b(7 - k);
      before := b(7 - k);
    end loop;
    for k in 0 to 15 loop
      w(15 - k) := cells(k);          -- first cell in time is the MSB
    end loop;
    return w;
  end function;

  -----------------------------------------------------------------------------
  -- Table-driven CRC-16/CCITT-FALSE (poly 0x1021, MSB first), integers only.
  -----------------------------------------------------------------------------
  type crc_tab_t is array (0 to 255) of natural;
  function make_tab return crc_tab_t is
    variable t : crc_tab_t;
    variable c : natural;
  begin
    for i in 0 to 255 loop
      c := i * 256;
      for k in 1 to 8 loop
        if c >= 32768 then
          c := ((c - 32768) * 2) mod 65536;
          c := to_integer(to_unsigned(c, 16) xor to_unsigned(16#1021#, 16));
        else
          c := (c * 2) mod 65536;
        end if;
      end loop;
      t(i) := c;
    end loop;
    return t;
  end function;
  constant CRC_TAB : crc_tab_t := make_tab;

  function crc_tab_upd(c : natural; b : natural) return natural is
    variable idx : natural;
  begin
    idx := to_integer(to_unsigned(c / 256, 8) xor to_unsigned(b, 8));
    return to_integer(to_unsigned((c mod 256) * 256, 16)
                      xor to_unsigned(CRC_TAB(idx), 16));
  end function;

  function hx(v : std_logic_vector) return string is
  begin
    return to_hstring(v);
  end function;

  -- the encoded stream of a sector, for the continuous decode in (d)
  constant C_SEC_WORDS : natural := 12 + 3 + 1 + 512 + 2 + 1;
  type word_arr_t is array (natural range <>) of word_t;
  type mark_arr_t is array (natural range <>) of boolean;

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_mfm_encoder
    port map (
      clk_i        => clk,
      rst_i        => rst,
      start_i      => start,
      byte_i       => byte_s,
      mark_i       => mark_s,
      crc_feed_i   => feed_s,
      crc_reset_i  => crst_s,
      valid_i      => valid_s,
      ready_o      => ready,
      word_o       => word,
      word_valid_o => word_valid,
      crc_o        => crc
    );

  watchdog : process
  begin
    wait for 40 ms;
    report "TIMEOUT" severity failure;
  end process;

  -----------------------------------------------------------------------------
  -- (f) latency monitor: word_valid_o in cycle n+1 iff valid_i in cycle n
  -----------------------------------------------------------------------------
  lat_mon : process
    variable prev_valid : std_logic := '0';
    variable errs       : integer := 0;
  begin
    wait until rising_edge(clk);     -- delta 0: pre-edge values
    if rst = '0' then
      if word_valid /= prev_valid then
        errs := errs + 1;
        report "word_valid_o = " & std_logic'image(word_valid)
               & " but valid_i one cycle earlier = " & std_logic'image(prev_valid)
               severity error;
      end if;
      if valid_s = '1' then
        n_strobe <= n_strobe + 1;
      end if;
      if word_valid = '1' then
        n_wvalid <= n_wvalid + 1;
      end if;
    end if;
    prev_valid := valid_s when rst = '0' else '0';
    lat_errors <= errs;
  end process;

  -----------------------------------------------------------------------------
  -- flux-package capture: run mfm_byte / mfm_a1 on flux_sig and timestamp
  -----------------------------------------------------------------------------
  fluxgen : process
    variable prev : std_logic;
  begin
    wait on flux_req;
    prev := flux_p;
    flux_t0    <= now;
    flux_start <= not flux_start;
    wait for 0 ns;
    if flux_kind = 0 then
      mfm_byte(flux_sig, unsigned(flux_b), prev);
    else
      mfm_a1(flux_sig, prev);
    end if;
    flux_pout <= prev;
    flux_done <= not flux_done;
  end process;

  recorder : process
    variable v   : word_t := (others => '0');
    variable idx : integer;
    variable off : integer := 0;
  begin
    wait on flux_sig, flux_start;
    if flux_start'event then
      v := (others => '0');
    end if;
    if flux_sig'event and flux_sig = '0' then
      idx := (now - flux_t0) / MFM_HALF_CELL;
      if (now - flux_t0) /= idx * MFM_HALF_CELL or idx > 15 then
        off := off + 1;
        report "flux edge off the half-cell grid at " & time'image(now - flux_t0)
               severity error;
      else
        v(15 - idx) := '1';
      end if;
    end if;
    rec_bits    <= v;
    rec_offgrid <= off;
  end process;

  -----------------------------------------------------------------------------
  -- main sequence
  -----------------------------------------------------------------------------
  main : process

    procedure cycles(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    -- one encoder strobe at the ready_o pace; returns the channel word
    procedure enc(b    : in  byte_t;
                  m    : in  enc_mark_t;
                  feed : in  std_logic;
                  crst : in  std_logic;
                  w    : out word_t) is
    begin
      loop
        wait until rising_edge(clk);
        exit when ready = '1';
      end loop;
      byte_s  <= b;
      mark_s  <= m;
      feed_s  <= feed;
      crst_s  <= crst;
      valid_s <= '1';
      wait until rising_edge(clk);       -- the DUT samples the strobe here
      valid_s <= '0';
      feed_s  <= '0';
      crst_s  <= '0';
      mark_s  <= ENC_MARK_NONE;
      byte_s  <= (others => 'X');
      wait until rising_edge(clk);       -- word_valid_o is high before this edge
      assert word_valid = '1'
        report "word_valid_o not high one cycle after valid_i" severity error;
      w := word;
    end procedure;

    procedure do_start is
    begin
      loop
        wait until rising_edge(clk);
        exit when ready = '1';
      end loop;
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
    end procedure;

    procedure wait_ready is
    begin
      loop
        wait until rising_edge(clk);
        exit when ready = '1';
      end loop;
    end procedure;

    procedure flux_ref(kind : in integer; b : in byte_t; p : in std_logic;
                       w : out word_t; pout : out std_logic) is
    begin
      flux_kind <= kind;
      flux_b    <= b;
      flux_p    <= p;
      wait for 0 ns;
      flux_req  <= not flux_req;
      wait on flux_done;
      wait for 0 ns;
      w    := rec_bits;
      pout := flux_pout;
    end procedure;

    variable w, wr, wf : word_t;
    variable pf        : std_logic;
    variable setup     : byte_t;
    variable p         : std_logic;
    variable n_ok      : integer;
    variable c_pkg     : unsigned(15 downto 0);
    variable c_tab     : natural;
    variable c_dut     : std_logic_vector(15 downto 0);
    variable c_one     : std_logic_vector(15 downto 0);
    variable b         : byte_t;
    variable words     : word_arr_t(0 to C_SEC_WORDS - 1);
    variable is_sync   : mark_arr_t(0 to C_SEC_WORDS - 1);
    variable bytes     : word_arr_t(0 to C_SEC_WORDS - 1);   -- low 8 bits used
    variable nw        : integer;
    variable cells     : std_logic_vector(0 to 16 * C_SEC_WORDS - 1);
    variable dprev, dnext, cexp : std_logic;
    variable clk_viol, missing : integer;
    variable dec       : byte_t;
    variable cnt       : integer;
    variable first     : std_logic;

  begin
    rst <= '1';
    cycles(5);
    rst <= '0';
    wait_ready;

    ---------------------------------------------------------------------------
    -- (a) every byte after both carried bits
    ---------------------------------------------------------------------------
    n_ok := 0;
    for pi in 0 to 1 loop
      for bi in 0 to 255 loop
        p := '1' when pi = 1 else '0';
        b := std_logic_vector(to_unsigned(bi, 8));
        -- set the carry through a preceding byte whose bit 0 is p
        setup := std_logic_vector(to_unsigned((bi * 37 + 11) mod 256, 8));
        setup(0) := p;
        enc(setup, ENC_MARK_NONE, '0', '0', w);
        enc(b, ENC_MARK_NONE, '0', '0', w);
        wr := ref_word(b, p);
        flux_ref(0, b, p, wf, pf);
        assert w = wr
          report "(a) byte 0x" & hx(b) & " p=" & std_logic'image(p) & ": DUT 0x"
                 & hx(w) & " /= reference 0x" & hx(wr) severity error;
        assert w = wf
          report "(a) byte 0x" & hx(b) & " p=" & std_logic'image(p) & ": DUT 0x"
                 & hx(w) & " /= mfm_flux_gen_pkg 0x" & hx(wf) severity error;
        assert pf = b(0)
          report "(a) mfm_flux_gen_pkg carry differs from bit 0" severity error;
        if w = wr and w = wf then
          n_ok := n_ok + 1;
        end if;
      end loop;
    end loop;
    assert n_ok = 512 report "(a) only " & integer'image(n_ok) & "/512 words agree" severity error;
    report "(a) 512/512 words (256 bytes x 2 carried bits) agree with the reference and with mfm_flux_gen_pkg -- OK";

    ---------------------------------------------------------------------------
    -- (b) sync marks
    ---------------------------------------------------------------------------
    for pi in 0 to 1 loop
      p := '1' when pi = 1 else '0';
      setup := (0 => p, others => '0');
      -- A1
      enc(setup, ENC_MARK_NONE, '0', '0', w);
      enc(x"00", ENC_MARK_A1, '0', '0', w);
      wr := ref_word(x"A1", p);
      wr(5) := '0';                                  -- the missing clock c2
      flux_ref(1, x"00", p, wf, pf);
      assert w = x"4489" and w = C_MFM_SYNC_A1 and w = wr and w = wf
        report "(b) A1 p=" & std_logic'image(p) & ": DUT 0x" & hx(w) & ", ref 0x"
               & hx(wr) & ", pkg 0x" & hx(wf) severity error;
      assert pf = '1' report "(b) mfm_a1 leaves prev_data /= 1" severity error;
      enc(x"00", ENC_MARK_NONE, '0', '0', w);       -- carry after A1 must be 1
      assert w = ref_word(x"00", '1') and w = x"2AAA"
        report "(b) byte after A1: 0x" & hx(w) & " (carry not 1)" severity error;
      -- C2
      enc(setup, ENC_MARK_NONE, '0', '0', w);
      enc(x"FF", ENC_MARK_C2, '0', '0', w);
      wr := ref_word(x"C2", p);
      wr(7) := '0';                                  -- the missing clock c3
      assert w = x"5224" and w = C_MFM_SYNC_C2 and w = wr
        report "(b) C2 p=" & std_logic'image(p) & ": DUT 0x" & hx(w) & ", ref 0x"
               & hx(wr) severity error;
      enc(x"00", ENC_MARK_NONE, '0', '0', w);       -- carry after C2 must be 0
      assert w = ref_word(x"00", '0') and w = x"AAAA"
        report "(b) byte after C2: 0x" & hx(w) & " (carry not 0)" severity error;
    end loop;
    report "(b) A1 -> 0x4489, C2 -> 0x5224 for both carried bits, carry after A1 = 1, after C2 = 0 -- OK";

    ---------------------------------------------------------------------------
    -- (c) crc_reset + A1 A1 A1 -> 0xCDB4
    ---------------------------------------------------------------------------
    do_start;
    wait_ready;
    assert crc = x"FFFF" report "(c) crc_o after start_i = 0x" & hx(crc) severity error;
    enc(x"00", ENC_MARK_A1, '1', '1', w);
    enc(x"00", ENC_MARK_A1, '1', '0', w);
    enc(x"00", ENC_MARK_A1, '1', '0', w);
    wait_ready;
    assert unsigned(crc) = C_CRC_AFTER_3XA1
      report "(c) crc after A1 A1 A1 = 0x" & hx(crc) & " (expected CDB4)" severity error;
    report "(c) crc_reset + A1 A1 A1 -> 0x" & hx(crc) & " -- OK";

    ---------------------------------------------------------------------------
    -- (d) a full sector (cylinder 39, side 1, sector 1: the D81 header/BAM)
    ---------------------------------------------------------------------------
    do_start;
    nw := 0;
    for k in 1 to 12 loop
      enc(x"00", ENC_MARK_NONE, '0', '0', w);
      words(nw) := w; is_sync(nw) := false; bytes(nw) := x"0000"; nw := nw + 1;
    end loop;
    for k in 1 to 3 loop
      first := '1' when k = 1 else '0';
      enc(x"00", ENC_MARK_A1, '1', first, w);
      words(nw) := w; is_sync(nw) := true; bytes(nw) := x"00A1"; nw := nw + 1;
    end loop;
    enc(x"FB", ENC_MARK_NONE, '1', '0', w);
    words(nw) := w; is_sync(nw) := false; bytes(nw) := x"00FB"; nw := nw + 1;
    c_pkg := x"FFFF";
    c_pkg := crc16_update(c_pkg, x"A1");
    c_pkg := crc16_update(c_pkg, x"A1");
    c_pkg := crc16_update(c_pkg, x"A1");
    c_pkg := crc16_update(c_pkg, x"FB");
    c_tab := 16#FFFF#;
    c_tab := crc_tab_upd(c_tab, 16#A1#);
    c_tab := crc_tab_upd(c_tab, 16#A1#);
    c_tab := crc_tab_upd(c_tab, 16#A1#);
    c_tab := crc_tab_upd(c_tab, 16#FB#);
    for off in 0 to 511 loop
      b := std_logic_vector(golden_payload(39, 1, 1, off));
      enc(b, ENC_MARK_NONE, '1', '0', w);
      words(nw) := w; is_sync(nw) := false; bytes(nw) := x"00" & b; nw := nw + 1;
      c_pkg := crc16_update(c_pkg, unsigned(b));
      c_tab := crc_tab_upd(c_tab, to_integer(unsigned(b)));
    end loop;
    wait_ready;
    c_dut := crc;
    assert unsigned(c_dut) = c_pkg
      report "(d) sector CRC 0x" & hx(c_dut) & " /= crc16_update 0x"
             & hx(std_logic_vector(c_pkg)) severity error;
    assert to_integer(unsigned(c_dut)) = c_tab
      report "(d) sector CRC 0x" & hx(c_dut) & " /= table CRC 0x"
             & hx(std_logic_vector(to_unsigned(c_tab, 16))) severity error;
    -- the CRC goes out as two plain unfed bytes, then the trailing FF
    enc(c_dut(15 downto 8), ENC_MARK_NONE, '0', '0', w);
    words(nw) := w; is_sync(nw) := false; bytes(nw) := x"00" & c_dut(15 downto 8); nw := nw + 1;
    enc(c_dut(7 downto 0), ENC_MARK_NONE, '0', '0', w);
    words(nw) := w; is_sync(nw) := false; bytes(nw) := x"00" & c_dut(7 downto 0); nw := nw + 1;
    assert crc = c_dut report "(d) crc_o moved while the CRC bytes went out" severity error;
    enc(x"FF", ENC_MARK_NONE, '0', '0', w);
    words(nw) := w; is_sync(nw) := false; bytes(nw) := x"00FF"; nw := nw + 1;
    assert nw = C_SEC_WORDS report "(d) word count" severity failure;

    -- continuous decode of the whole stream (p = 0 at the session start)
    for i in 0 to nw - 1 loop
      for k in 0 to 15 loop
        cells(16 * i + k) := words(i)(15 - k);
      end loop;
    end loop;
    clk_viol := 0;
    missing  := 0;
    for j in 0 to 8 * nw - 1 loop
      if j = 0 then dprev := '0'; else dprev := cells(2 * j - 1); end if;
      dnext := cells(2 * j + 1);
      cexp  := (not dprev) and (not dnext);
      if cells(2 * j) /= cexp then
        -- allowed only as a missing clock (expected '1', written '0') inside
        -- a sync word
        if is_sync(j / 8) and cexp = '1' and cells(2 * j) = '0' then
          missing := missing + 1;
        else
          clk_viol := clk_viol + 1;
          report "(d) clock rule violated at channel cell " & integer'image(2 * j)
                 & " (word " & integer'image(j / 8) & ")" severity error;
        end if;
      end if;
    end loop;
    assert clk_viol = 0 and missing = 3
      report "(d) " & integer'image(clk_viol) & " clock violations, "
             & integer'image(missing) & " missing clocks (expected 0 and 3)" severity error;
    -- data cells give back the bytes; residue over the decoded field
    c_pkg := x"FFFF";
    for i in 0 to nw - 1 loop
      for k in 0 to 7 loop
        dec(7 - k) := cells(16 * i + 2 * k + 1);
      end loop;
      assert dec = bytes(i)(7 downto 0)
        report "(d) word " & integer'image(i) & " decodes to 0x" & hx(dec)
               & ", expected 0x" & hx(bytes(i)(7 downto 0)) severity error;
      if i >= 12 and i <= 12 + 3 + 1 + 512 + 2 - 1 then
        c_pkg := crc16_update(c_pkg, unsigned(dec));
      end if;
    end loop;
    assert c_pkg = x"0000"
      report "(d) residue over the decoded field = 0x" & hx(std_logic_vector(c_pkg))
      severity error;
    report "(d) sector A1 A1 A1 FB + 512 golden bytes: CRC 0x" & hx(c_dut)
           & " = crc16_update = table CRC; " & integer'image(nw)
           & "-word stream decodes byte-exact, clock rule holds across every boundary"
           & " (3 missing clocks, all in the A1 syncs), residue 0 -- OK";

    ---------------------------------------------------------------------------
    -- (e) the Write Track F5 preset rule
    ---------------------------------------------------------------------------
    -- (e1) preset on the first F5 of the run only (every token fed)
    do_start;
    for k in 1 to 12 loop
      enc(x"4E", ENC_MARK_NONE, '1', '0', w);
    end loop;
    for k in 1 to 12 loop
      enc(x"00", ENC_MARK_NONE, '1', '0', w);
    end loop;
    for k in 1 to 3 loop
      first := '1' when k = 1 else '0';
      enc(x"F5", ENC_MARK_A1, '1', first, w);
      assert w = x"4489" report "(e1) F5 not written as 0x4489" severity error;
    end loop;
    wait_ready;
    assert unsigned(crc) = C_CRC_AFTER_3XA1
      report "(e1) first-F5 preset: crc = 0x" & hx(crc) & " (expected CDB4)" severity error;
    report "(e1) preset on the first F5 only: crc after 3 x F5 = 0x" & hx(crc) & " -- OK";
    c_pkg := C_CRC_AFTER_3XA1;
    c_tab := to_integer(C_CRC_AFTER_3XA1);
    for k in 0 to 4 loop                 -- FE C H R N
      case k is
        when 0 => b := x"FE";
        when 1 => b := x"27";
        when 2 => b := x"01";
        when 3 => b := x"05";
        when others => b := x"02";
      end case;
      enc(b, ENC_MARK_NONE, '1', '0', w);
      c_pkg := crc16_update(c_pkg, unsigned(b));
      c_tab := crc_tab_upd(c_tab, to_integer(unsigned(b)));
    end loop;
    wait_ready;
    assert unsigned(crc) = c_pkg and to_integer(unsigned(crc)) = c_tab
      report "(e1) ID CRC 0x" & hx(crc) & " /= references" severity error;
    report "(e1) ID field FE 27 01 05 02 CRC 0x" & hx(crc) & " = both references -- OK";

    -- (e2) the defect: preset on every F5
    do_start;
    for k in 1 to 12 loop
      enc(x"00", ENC_MARK_NONE, '1', '0', w);
    end loop;
    for k in 1 to 3 loop
      enc(x"F5", ENC_MARK_A1, '1', '1', w);
    end loop;
    wait_ready;
    c_one := std_logic_vector(crc16_update(x"FFFF", x"A1"));
    assert unsigned(crc) /= C_CRC_AFTER_3XA1
      report "(e2) presetting every F5 still gave CDB4 -- the rule is untested" severity error;
    assert crc = c_one
      report "(e2) every-F5 preset: crc = 0x" & hx(crc) & ", expected the single-A1 value 0x"
             & hx(c_one) severity error;
    report "(e2) preset on every F5 gives 0x" & hx(crc)
           & " (the CRC of one A1), not 0xCDB4 -- the difference is asserted -- OK";

    ---------------------------------------------------------------------------
    -- (f) timing contract
    ---------------------------------------------------------------------------
    wait_ready;
    cycles(3);
    byte_s <= x"55"; feed_s <= '1'; valid_s <= '1';
    wait until rising_edge(clk);
    valid_s <= '0'; feed_s <= '0';
    cnt := 0;
    for k in 1 to 20 loop
      wait until rising_edge(clk);
      if ready = '0' then
        cnt := cnt + 1;
      end if;
    end loop;
    assert cnt = 10
      report "(f) ready_o low for " & integer'image(cnt) & " cycles (expected 10)" severity error;
    -- back-to-back CRC strobes at the ready pace: 64 bytes, check the CRC
    do_start;
    c_tab := 16#FFFF#;
    for k in 0 to 63 loop
      b := std_logic_vector(to_unsigned((k * 73 + 5) mod 256, 8));
      enc(b, ENC_MARK_NONE, '1', '0', w);
      c_tab := crc_tab_upd(c_tab, to_integer(unsigned(b)));
    end loop;
    wait_ready;
    assert to_integer(unsigned(crc)) = c_tab
      report "(f) CRC at ready pace = 0x" & hx(crc) & " /= table CRC" severity error;
    cycles(2);
    assert lat_errors = 0 and n_strobe = n_wvalid
      report "(f) latency monitor: " & integer'image(lat_errors) & " errors, "
             & integer'image(n_strobe) & " strobes vs " & integer'image(n_wvalid)
             & " words" severity error;
    report "(f) word_valid_o exactly 1 cycle after each of " & integer'image(n_strobe)
           & " strobes, ready_o low 10 cycles after a CRC strobe, no CRC byte lost at the ready pace -- OK";

    ---------------------------------------------------------------------------
    -- (g) reset while a CRC byte is shifting
    ---------------------------------------------------------------------------
    wait_ready;
    byte_s <= x"C3"; feed_s <= '1'; valid_s <= '1';
    wait until rising_edge(clk);
    valid_s <= '0'; feed_s <= '0';
    cycles(3);                           -- the byte is mid-shift now
    rst <= '1';
    cycles(4);
    rst <= '0';
    wait until rising_edge(clk);
    assert ready = '0' report "(g) ready_o high right after reset" severity error;
    do_start;                            -- waits for ready_o first
    enc(x"00", ENC_MARK_A1, '1', '1', w);
    enc(x"00", ENC_MARK_A1, '1', '0', w);
    enc(x"00", ENC_MARK_A1, '1', '0', w);
    wait_ready;
    assert unsigned(crc) = C_CRC_AFTER_3XA1
      report "(g) after a mid-shift reset: crc = 0x" & hx(crc) severity error;
    enc(x"00", ENC_MARK_NONE, '0', '0', w);
    assert w = x"2AAA" report "(g) carry after reset + A1 wrong" severity error;
    report "(g) reset mid-shift, then start + A1 A1 A1 -> 0x" & hx(crc) & " -- OK";

    assert rec_offgrid = 0 report "flux capture saw off-grid edges" severity error;
    report "physical_1581_mfm_encoder: ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
