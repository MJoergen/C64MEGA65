-------------------------------------------------------------------------------
-- tb_physical_1581_writer.vhd
--
-- Self-checking GHDL testbench for physical_1581_writer, at the production
-- constants (10 ms qualifier, 50 us settle, 100-cycle cell).
--
-- Instruments (time unit: 50 MHz clock edges, numbered by the value the
-- counter `cyc` holds after them):
--   * flux recorder: the stamp of every WDATA falling edge, the width of
--     every WDATA low pulse, every WGATE and wr_ok edge
--   * FATAL assert on WDATA low while WGATE is high, every cycle, whole run
--   * a controller model (feeder) that raises session_i, pushes words while
--     word_level_o (plus a push in flight) is at most 1 -- the admission rule
--     of WRITE-SPEC 5.5 -- and drops session_i after the last push
-- A process that applies an input right after edge c is seen by the DUT at
-- edge c+2 ("t_seen"); a registered reaction in that same clock carries the
-- stamp t_seen, i.e. the pin moves less than one clock after the input.
--
-- Expected flux is computed here, independently of the DUT: channel words
-- come from a time-ordered MFM restatement; the ideal edge of channel bit k
-- of a session is G + 100*k + 50 (G = WGATE fall); the precomp shift is
-- derived from the intervals to the neighbouring transitions of the ideal
-- edge list (shift toward the closer neighbour, 140 ns; no shift for an
-- interval of one cell, for equal intervals, or when a 3-cell window would
-- reach outside the session).
--
--   W-a qualifier: 10 ms + 50 us settle to wr_ok, exact; a 3-sample tab
--       glitch is ignored, a 4-sample protected level revokes at t_seen+4;
--       a qualification started while protected never qualifies (30 ms);
--       a change assert edge revokes and the next 10 ms re-qualify with the
--       change still asserted; en_i low pauses the accumulator
--   W-b precomp off: WGATE window = N x 1600 cycles pin to pin, first edge
--       at G+50 (inside the first cell), every '1' bit one falling edge at
--       cell cycle 50, no other edge, every pulse 25 cycles, gate rises at
--       G + 1600*N exactly
--   W-c precomp on: every neighbourhood class (2/3/4-cell intervals both
--       sides, symmetric, invalid MFM), edges at exactly -7/0/+7, boundary
--       bits unshifted, d_precnt_o equals the reference count
--   W-d abort terms mid-stream: motor, enable, media_ready, side, abort_i
--       close WGATE at t_seen; protected level and change edge at t_seen+4;
--       latched until the session falls; reason codes, d_abort_o,
--       d_reason_acc_o; a new session arms and writes afterwards
--   W-e underrun: two words then none with the session open -> abort 0x40
--       at a cell boundary, d_underrun_o; a session with no words at all
--       waits in ARM with the gate shut
--   W-f discard: a session without wr_ok never opens WGATE, consumes its
--       words at cell pace, d_discard_o
--   W-g back-to-back sessions: the second session's first flux is its own
--       first word; pushes while idle and a push while full are refused and
--       counted (d_pushfull_o) and never reach the disk
--   W-h reset mid-session (inside a WDATA pulse): both pins high at t_seen,
--       and they stay high
--   W-i cut_i (Write Track end at the index): WGATE closes at the next cell
--       boundary, the written flux is the exact prefix, completed + cut, not
--       aborted
--
-- Run (B = absolute scratch workdir; run from the scratch directory):
--   ghdl -a --std=08 --workdir=B \
--     CORE/vhdl/physical_1581/physical_1581_pkg.vhd \
--     CORE/vhdl/physical_1581/physical_1581_writer.vhd \
--     CORE/vhdl/test/tb_physical_1581_writer/tb_physical_1581_writer.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_writer --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;

entity tb_physical_1581_writer is
end entity;

architecture sim of tb_physical_1581_writer is

  subtype word_t is std_logic_vector(15 downto 0);
  subtype byte_t is std_logic_vector(7 downto 0);
  type int_arr is array (natural range <>) of integer;

  -----------------------------------------------------------------------------
  -- logs shared between the recorder and the checks
  -----------------------------------------------------------------------------
  type log_t is protected
    procedure add(v : integer);
    impure function count return natural;
    impure function get(i : natural) return integer;
  end protected log_t;

  type log_t is protected body
    variable a : int_arr(0 to 65535) := (others => 0);
    variable n : natural := 0;
    procedure add(v : integer) is
    begin
      assert n <= a'high report "log overflow" severity failure;
      a(n) := v;
      n := n + 1;
    end procedure;
    impure function count return natural is
    begin
      return n;
    end function;
    impure function get(i : natural) return integer is
    begin
      return a(i);
    end function;
  end protected body log_t;

  type wstore_t is protected
    procedure set(i : natural; w : word_t);
    impure function get(i : natural) return word_t;
  end protected wstore_t;

  type wstore_t is protected body
    type warr is array (0 to 4095) of word_t;
    variable a : warr := (others => (others => '0'));
    procedure set(i : natural; w : word_t) is
    begin
      a(i) := w;
    end procedure;
    impure function get(i : natural) return word_t is
    begin
      return a(i);
    end function;
  end protected body wstore_t;

  shared variable fall_log   : log_t;   -- WDATA falling edges
  shared variable width_log  : log_t;   -- WDATA low widths (index = falling edge)
  shared variable gfall_log  : log_t;   -- WGATE assert (pin falls)
  shared variable grise_log  : log_t;   -- WGATE release (pin rises)
  shared variable okrise_log : log_t;   -- wr_ok rises
  shared variable okfall_log : log_t;   -- wr_ok falls
  shared variable ws         : wstore_t; -- words the feeder pushes

  -----------------------------------------------------------------------------
  -- DUT signals
  -----------------------------------------------------------------------------
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal en        : std_logic := '1';
  signal mot       : std_logic := '1';
  signal mr        : std_logic := '1';
  signal side      : std_logic := '0';
  signal wprot     : std_logic := '0';
  signal change    : std_logic := '0';
  signal session   : std_logic;
  signal abort_s   : std_logic := '0';
  signal precomp   : std_logic := '0';
  signal cut       : std_logic := '0';
  signal word      : word_t;
  signal push      : std_logic;
  signal full      : std_logic;
  signal level     : unsigned(2 downto 0);
  signal wdata     : std_logic;
  signal wgate     : std_logic;
  signal busy      : std_logic;
  signal wr_ok     : std_logic;
  signal gate      : std_logic;
  signal d_gate_cyc   : unsigned(31 downto 0);
  signal d_words_last : unsigned(15 downto 0);
  signal d_underrun   : unsigned(15 downto 0);
  signal d_discard    : unsigned(15 downto 0);
  signal d_gateopen   : unsigned(15 downto 0);
  signal d_abort      : unsigned(15 downto 0);
  signal d_reason     : std_logic_vector(7 downto 0);
  signal d_reason_acc : std_logic_vector(7 downto 0);
  signal d_precnt     : unsigned(15 downto 0);
  signal d_pushfull   : unsigned(15 downto 0);
  signal d_flags      : std_logic_vector(4 downto 0);

  signal cyc       : integer := 0;

  -- feeder (controller model) and manual overrides
  signal session_f : std_logic := '0';
  signal push_f    : std_logic := '0';
  signal word_f    : word_t := (others => '0');
  signal session_m : std_logic := '0';
  signal push_m    : std_logic := '0';
  signal word_m    : word_t := (others => '0');
  signal feed_req  : boolean := false;
  signal feed_stop : boolean := false;
  signal feed_rel  : boolean := false;
  signal feed_n    : integer := 0;
  signal feed_hold : boolean := false;

  -----------------------------------------------------------------------------
  -- channel word of a plain MFM byte, stated in time order: the clock cell in
  -- front of a data bit is '1' iff that data bit and the one before are '0'
  -----------------------------------------------------------------------------
  function mfm_w(b : byte_t; p : std_logic) return word_t is
    variable before : std_logic := p;
    variable w      : word_t;
  begin
    for k in 0 to 7 loop
      w(15 - 2 * k) := (not before) and (not b(7 - k));
      w(14 - 2 * k) := b(7 - k);
      before := b(7 - k);
    end loop;
    return w;
  end function;

  function lfsr(x : natural) return natural is
    variable v  : unsigned(15 downto 0) := to_unsigned(x mod 65536, 16);
    variable fb : std_logic;
  begin
    fb := v(15) xor v(13) xor v(12) xor v(10);
    return to_integer(unsigned'(v(14 downto 0) & fb));
  end function;

  function hx(v : std_logic_vector) return string is
  begin
    return to_hstring(v);
  end function;

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  session <= session_f or session_m;
  push    <= push_f or push_m;
  word    <= word_m when push_m = '1' else word_f;

  dut : entity work.physical_1581_writer
    port map (
      clk_i          => clk,
      rst_i          => rst,
      en_i           => en,
      mot_i          => mot,
      media_ready_i  => mr,
      side_i         => side,
      wprot_i        => wprot,
      change_i       => change,
      session_i      => session,
      abort_i        => abort_s,
      precomp_i      => precomp,
      cut_i          => cut,
      word_i         => word,
      word_push_i    => push,
      word_full_o    => full,
      word_level_o   => level,
      f_wdata_o      => wdata,
      f_wgate_o      => wgate,
      busy_o         => busy,
      wr_ok_o        => wr_ok,
      gate_o         => gate,
      d_gate_cyc_o   => d_gate_cyc,
      d_words_last_o => d_words_last,
      d_underrun_o   => d_underrun,
      d_discard_o    => d_discard,
      d_gateopen_o   => d_gateopen,
      d_abort_o      => d_abort,
      d_reason_o     => d_reason,
      d_reason_acc_o => d_reason_acc,
      d_precnt_o     => d_precnt,
      d_pushfull_o   => d_pushfull,
      d_flags_o      => d_flags
    );

  watchdog : process
  begin
    wait for 400 ms;
    report "TIMEOUT" severity failure;
  end process;

  counter : process (clk)
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- flux recorder + the fatal gate check. In delta 0 of an edge, cyc and the
  -- pins still hold the values of the previous edge, so a change seen here is
  -- stamped with the number of the edge that made it.
  -----------------------------------------------------------------------------
  recorder : process (clk)
    variable wd_q, wg_q : std_logic := '1';   -- both pins idle high
    variable ok_q       : std_logic := '0';   -- wr_ok starts unqualified
    variable t_f : integer := 0;
  begin
    if rising_edge(clk) then
      if wdata = '0' and wgate = '1' then
        report "FATAL: WDATA low while WGATE is high (cycle " & integer'image(cyc) & ")"
          severity failure;
      end if;
      if wd_q = '1' and wdata = '0' then
        fall_log.add(cyc);
        t_f := cyc;
      end if;
      if wd_q = '0' and wdata = '1' then
        width_log.add(cyc - t_f);
      end if;
      if wg_q = '1' and wgate = '0' then
        gfall_log.add(cyc);
      end if;
      if wg_q = '0' and wgate = '1' then
        grise_log.add(cyc);
      end if;
      if ok_q = '0' and wr_ok = '1' then
        okrise_log.add(cyc);
      end if;
      if ok_q = '1' and wr_ok = '0' then
        okfall_log.add(cyc);
      end if;
      wd_q := wdata;
      wg_q := wgate;
      ok_q := wr_ok;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- controller model
  -----------------------------------------------------------------------------
  feeder : process
    variable idx     : integer := 0;
    variable running : boolean := false;
    variable eff     : integer;
    variable req_q, stop_q, rel_q : boolean := false;
  begin
    wait until rising_edge(clk);
    if feed_req /= req_q then
      req_q     := feed_req;
      running   := true;
      idx       := 0;
      session_f <= '1';
    end if;
    if feed_rel /= rel_q then
      rel_q     := feed_rel;
      session_f <= '0';
    end if;
    if feed_stop /= stop_q then
      stop_q    := feed_stop;
      running   := false;
      session_f <= '0';
    end if;
    push_f <= '0';
    if running then
      eff := to_integer(level);
      if push_f = '1' then
        eff := eff + 1;                     -- the push the DUT samples now
      end if;
      if idx < feed_n then
        if eff <= 1 then
          push_f <= '1';
          word_f <= ws.get(idx);
          idx    := idx + 1;
        end if;
      else
        running := false;
        if not feed_hold then
          session_f <= '0';                 -- after the last push
        end if;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- main sequence
  -----------------------------------------------------------------------------
  main : process

    variable c, t, g, r, e0, g0, r0, n, n_exp, n_sh, k : integer;
    variable cls   : int_arr(0 to 24) := (others => 0);   -- (before*5 + after)
    variable bits  : std_logic_vector(0 to 16383);
    variable p     : std_logic;
    variable s     : natural;
    variable ab0, dc0, pf0, ur0 : integer;

    procedure tick(nn : natural) is
    begin
      for i in 1 to nn loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    -- resume after an edge; returns the cyc value read there (inputs
    -- assigned now are seen by the DUT at edge c+2)
    procedure edge(cc : out integer) is
    begin
      wait until rising_edge(clk);
      cc := cyc;
    end procedure;

    procedure wait_idle is
    begin
      if busy = '1' then
        wait until busy = '0' for 60 ms;
      end if;
      assert busy = '0' report "writer did not return to idle" severity failure;
      tick(2);                           -- let the recorder stamp the last edges
    end procedure;

    procedure start_session(nn : natural; hold : boolean) is
    begin
      wait_idle;
      feed_n    <= nn;
      feed_hold <= hold;
      wait until rising_edge(clk);
      feed_req  <= not feed_req;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      assert busy = '1' report "session did not bind" severity error;
    end procedure;

    procedure run_session(nn : natural) is
    begin
      start_session(nn, false);
      wait_idle;
      tick(4);
    end procedure;

    procedure qualify is
    begin
      if wr_ok = '0' then
        wait until wr_ok = '1' for 11 ms;
      end if;
      assert wr_ok = '1' report "wr_ok did not qualify" severity failure;
    end procedure;

    -- word builders (carried bit p across every boundary)
    procedure put_byte(b : byte_t; idx : inout natural; pp : inout std_logic) is
    begin
      ws.set(idx, mfm_w(b, pp));
      pp  := b(0);
      idx := idx + 1;
    end procedure;
    procedure put_a1(idx : inout natural; pp : inout std_logic) is
    begin
      ws.set(idx, C_MFM_SYNC_A1);
      pp  := '1';
      idx := idx + 1;
    end procedure;
    -- 12 x 00, 3 x A1, FB, nrand pseudo-random bytes, FF
    procedure build_field(nrand : natural; seed : natural; nn : out natural) is
      variable i  : natural := 0;
      variable pp : std_logic := '0';
      variable x  : natural := seed;
    begin
      for j in 1 to 12 loop put_byte(x"00", i, pp); end loop;
      for j in 1 to 3 loop put_a1(i, pp); end loop;
      put_byte(x"FB", i, pp);
      for j in 1 to nrand loop
        x := lfsr(x);
        put_byte(std_logic_vector(to_unsigned(x mod 256, 8)), i, pp);
      end loop;
      put_byte(x"FF", i, pp);
      nn := i;
    end procedure;

    -- channel bits of the first nn stored words
    procedure load_bits(nn : natural) is
      variable w : word_t;
    begin
      for i in 0 to nn - 1 loop
        w := ws.get(i);
        for j in 0 to 15 loop
          bits(16 * i + j) := w(15 - j);
        end loop;
      end loop;
    end procedure;

    -- independent precomp reference for the transition at channel bit kk of
    -- an ll-bit session: intervals to the previous / next transition
    procedure ref_shift(kk, ll : integer; pc : boolean; sh : out integer;
                        gap_b, gap_a : out integer) is
      variable b4, af : integer := 4;
    begin
      for d in 1 to 3 loop
        if kk - d >= 0 then
          if bits(kk - d) = '1' then b4 := d; exit; end if;
        end if;
      end loop;
      for d in 1 to 3 loop
        if kk + d <= ll - 1 then
          if bits(kk + d) = '1' then af := d; exit; end if;
        end if;
      end loop;
      gap_b  := b4;
      gap_a  := af;
      sh := 0;
      if pc and kk >= 3 and kk <= ll - 4 then
        if b4 = 1 or af = 1 then
          sh := 0;                       -- not MFM: leave it alone
        elsif b4 < af then
          sh := -C_WR_PRECOMP_CYC;       -- closer neighbour before -> early
        elsif b4 > af then
          sh := C_WR_PRECOMP_CYC;        -- closer neighbour after -> late
        end if;
      end if;
    end procedure;

    -- compare the flux log from index ee against the expected edges of the
    -- first nn stored words, gate fall gg; only edges stamped before limit
    procedure check_flux(ee, gg, nn : integer; pc : boolean; limit : integer;
                         name : string; nexp : out integer; nsh : out integer) is
      variable ll, idx, expt, sh, b4, af, w, wmin, wmax : integer;
    begin
      load_bits(nn);
      ll   := 16 * nn;
      idx  := ee;
      nexp := 0;
      nsh  := 0;
      wmin := 999;
      wmax := -1;
      for kk in 0 to ll - 1 loop
        if bits(kk) = '1' then
          ref_shift(kk, ll, pc, sh, b4, af);
          expt := gg + C_WR_CELL_CYC * kk + C_WR_LAUNCH_CYC + sh;
          if expt < limit then
            if idx < fall_log.count then
              assert fall_log.get(idx) = expt
                report name & ": channel bit " & integer'image(kk) & " edge at G+"
                       & integer'image(fall_log.get(idx) - gg) & ", expected G+"
                       & integer'image(expt - gg) severity error;
              if idx < width_log.count then
                w := width_log.get(idx);
                if w < wmin then wmin := w; end if;
                if w > wmax then wmax := w; end if;
              end if;
            else
              report name & ": edge of channel bit " & integer'image(kk) & " missing"
                severity error;
            end if;
            if pc and kk >= 3 and kk <= ll - 4 then
              cls(b4 * 5 + af) := cls(b4 * 5 + af) + 1;
            end if;
            if sh /= 0 then
              nsh := nsh + 1;
            end if;
            idx  := idx + 1;
            nexp := nexp + 1;
          end if;
        end if;
      end loop;
      assert fall_log.count = idx
        report name & ": " & integer'image(fall_log.count - idx)
               & " WDATA edges beyond the expected ones" severity error;
      if nexp > 0 and limit = integer'high then
        assert wmin = C_WR_PULSE_CYC and wmax = C_WR_PULSE_CYC
          report name & ": pulse widths " & integer'image(wmin) & ".."
                 & integer'image(wmax) & " (expected 25)" severity error;
      end if;
    end procedure;

    -- one abort-term case mid-stream
    procedure abort_case(term : integer; rsn : byte_t; filt : boolean; name : string) is
      variable nn, cc, tseen, rise, ab, f0 : integer;
    begin
      build_field(44, 16#A5A5# + term, s);
      nn := s;
      qualify;
      e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
      ab := to_integer(d_abort);
      start_session(nn, false);
      wait until gate = '1' for 2 ms;
      assert gate = '1' report name & ": gate never opened" severity failure;
      tick(16 * 100 * 9 + 37);           -- mid-stream, mid-cell
      edge(cc);
      tseen := cc + 2;
      case term is
        when 0 => mot <= '0';
        when 1 => en <= '0';
        when 2 => mr <= '0';
        when 3 => side <= not side;
        when 4 => abort_s <= '1';
        when 5 => change <= '1';
        when others => wprot <= '1';
      end case;
      tick(1);
      abort_s <= '0';                    -- a one-cycle abort pulse is enough
      tick(12);
      assert grise_log.count = r0 + 1
        report name & ": WGATE did not close" severity failure;
      rise := grise_log.get(r0);
      if filt then
        assert rise = tseen + C_WR_FILT
          report name & ": WGATE closed at t_seen+" & integer'image(rise - tseen)
                 & " (expected +4: four filter samples)" severity error;
      else
        assert rise = tseen
          report name & ": WGATE closed at t_seen+" & integer'image(rise - tseen)
                 & " (expected +0)" severity error;
      end if;
      f0 := fall_log.count;
      -- restore the term after a while: the gate must stay shut
      tick(700);
      case term is
        when 0 => mot <= '1';
        when 1 => en <= '1';
        when 2 => mr <= '1';
        when 5 => change <= '0';
        when 6 => wprot <= '0';
        when others => null;
      end case;
      wait_idle;
      assert gfall_log.count = g0 + 1 and grise_log.count = r0 + 1
        report name & ": WGATE reopened after the abort" severity error;
      assert fall_log.count = f0 and fall_log.get(f0 - 1) < rise
        report name & ": WDATA edges after the abort" severity error;
      assert d_reason = rsn
        report name & ": reason 0x" & hx(d_reason) & " (expected 0x" & hx(rsn) & ")" severity error;
      assert (d_reason_acc and rsn) = rsn
        report name & ": reason not accumulated" severity error;
      assert d_flags(1) = '1' and d_flags(0) = '0'
        report name & ": flags 0x" & hx(d_flags) severity error;
      assert to_integer(d_abort) = ab + 1
        report name & ": d_abort_o not incremented" severity error;
      report "W-d " & name & ": WGATE high at t_seen+" & integer'image(rise - tseen)
             & ", latched until the session fell, reason 0x" & hx(d_reason)
             & ", flags 0x" & hx(d_flags) & " -- OK";
    end procedure;

    variable t_rel, a0, d0, nb, e1, g1, rr : integer;

  begin
    ---------------------------------------------------------------------------
    -- reset; inputs: enabled, motor on, media ready, tab writable
    ---------------------------------------------------------------------------
    rst <= '1';
    tick(10);
    edge(c);
    rst <= '0';
    t_rel := c + 2;                      -- first edge out of reset

    ---------------------------------------------------------------------------
    -- W-a qualifier
    ---------------------------------------------------------------------------
    qualify;
    tick(2);
    assert okrise_log.count = 1 report "W-a: no wr_ok rise logged" severity failure;
    t := okrise_log.get(0) - t_rel;
    assert t = C_WR_SEL_SETTLE_CYC + C_WR_WPROT_QUAL_CYC
      report "W-a: wr_ok after " & integer'image(t) & " cycles (expected "
             & integer'image(C_WR_SEL_SETTLE_CYC + C_WR_WPROT_QUAL_CYC) & ")" severity error;
    report "W-a: wr_ok after " & integer'image(t) & " cycles = 50 us settle + 10 ms -- OK";

    -- a 3-sample protected glitch is ignored
    edge(c);
    wprot <= '1';
    tick(3);
    wprot <= '0';
    tick(20);
    assert wr_ok = '1' and okfall_log.count = 0
      report "W-a: 3-sample glitch revoked wr_ok" severity error;
    -- a 4-sample protected level revokes
    edge(c);
    wprot <= '1';
    tick(10);
    assert okfall_log.count = 1 report "W-a: protected level did not revoke" severity failure;
    t := okfall_log.get(0) - (c + 2);
    assert t = C_WR_FILT
      report "W-a: revoke at t_seen+" & integer'image(t) & " (expected +4)" severity error;
    report "W-a: 3-sample glitch ignored, 4-sample protected level revokes at t_seen+"
           & integer'image(t) & " -- OK";
    -- protected for 30 ms: never qualifies
    wait for 30 ms;
    assert wr_ok = '0' and okrise_log.count = 1
      report "W-a: qualified while protected" severity error;
    edge(c);
    wprot <= '0';
    qualify;
    tick(2);
    t := okrise_log.get(1) - (c + 2);
    assert t = C_WR_WPROT_QUAL_CYC + 1
      report "W-a: re-qualified after " & integer'image(t) & " cycles" severity error;
    report "W-a: 30 ms protected never qualified; writable again -> wr_ok after "
           & integer'image(t) & " cycles -- OK";

    -- a change assert edge revokes; the change stays asserted and the next
    -- 10 ms re-qualify anyway
    edge(c);
    change <= '1';
    tick(10);
    assert okfall_log.count = 2 report "W-a: change edge did not revoke" severity failure;
    t := okfall_log.get(1) - (c + 2);
    assert t = C_WR_FILT
      report "W-a: change revoke at t_seen+" & integer'image(t) severity error;
    qualify;
    tick(2);
    r := okrise_log.get(2) - (c + 2);
    assert r = C_WR_FILT + 1 + C_WR_WPROT_QUAL_CYC
      report "W-a: re-qualified with change held after " & integer'image(r) severity error;
    report "W-a: change edge revokes at t_seen+" & integer'image(t)
           & ", re-qualifies after " & integer'image(r) & " cycles with the change still asserted -- OK";
    -- the change LEVEL is not a write gate: a session now writes
    build_field(2, 16#3C3C#, s);
    g0 := gfall_log.count;
    run_session(s);
    assert gfall_log.count = g0 + 1 and d_flags = "00001"
      report "W-a: a session with the change line still asserted did not write" severity error;
    report "W-a: with the change line still asserted (no new edge) a session writes -- OK";

    -- change falls and rises again: revokes again; then en_i low pauses
    edge(c);
    change <= '0';
    tick(10);
    edge(c);
    change <= '1';
    t := c + 2;                          -- t_seen of the second edge
    tick(10);
    assert okfall_log.count = 3 report "W-a: second change edge did not revoke" severity failure;
    -- accumulate about 5 ms, disable for 3 ms, enable again
    wait until cyc = t + C_WR_FILT + 250_000;
    edge(c);
    en <= '0';
    a0 := c - t - 3;                     -- accumulator increments so far
    tick(150_000);
    edge(d0);
    en <= '1';
    qualify;
    tick(2);
    r  := okrise_log.get(3);
    rr := (d0 + 2) + C_WR_SEL_SETTLE_CYC + 1 + (C_WR_WPROT_QUAL_CYC - a0);
    assert r = rr
      report "W-a: paused qualification completed at " & integer'image(r - rr)
             & " cycles from the prediction" severity error;
    report "W-a: second change edge revokes; en_i low for 3 ms pauses the 10 ms (completed "
           & integer'image(r - rr) & " cycles from the exact prediction) -- OK";
    change <= '0';
    tick(5000);

    ---------------------------------------------------------------------------
    -- W-b one session, precomp off
    ---------------------------------------------------------------------------
    precomp <= '0';
    build_field(24, 16#1D0F#, s);
    n := s;
    e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
    run_session(n);
    assert gfall_log.count = g0 + 1 and grise_log.count = r0 + 1
      report "W-b: WGATE did not open/close exactly once" severity failure;
    g := gfall_log.get(g0);
    r := grise_log.get(r0);
    assert r - g = n * 16 * C_WR_CELL_CYC
      report "W-b: WGATE window " & integer'image(r - g) & " cycles (expected "
             & integer'image(n * 1600) & ")" severity error;
    assert fall_log.get(e0) = g + C_WR_LAUNCH_CYC
      report "W-b: first edge at G+" & integer'image(fall_log.get(e0) - g) severity error;
    check_flux(e0, g, n, false, integer'high, "W-b", n_exp, n_sh);
    assert fall_log.get(fall_log.count - 1) < r
      report "W-b: an edge after the gate closed" severity error;
    assert to_integer(d_gate_cyc) = n * 1600 and to_integer(d_words_last) = n
           and d_flags = "00001" and to_integer(d_precnt) = 0
      report "W-b: diag gate_cyc " & integer'image(to_integer(d_gate_cyc)) & " words "
             & integer'image(to_integer(d_words_last)) & " flags 0x" & hx(d_flags) severity error;
    report "W-b: " & integer'image(n) & " words, WGATE window " & integer'image(r - g)
           & " = N x 1600, first edge G+50, " & integer'image(n_exp)
           & " edges each at cell cycle 50, all pulses 25 cycles, no lead-in/out -- OK";

    ---------------------------------------------------------------------------
    -- W-c precomp on
    ---------------------------------------------------------------------------
    precomp <= '1';
    build_field(200, 16#ACE1#, s);
    n := s;
    e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
    run_session(n);
    g := gfall_log.get(g0);
    r := grise_log.get(r0);
    assert r - g = n * 1600 report "W-c: window" severity error;
    check_flux(e0, g, n, true, integer'high, "W-c", n_exp, n_sh);
    assert to_integer(d_precnt) = n_sh
      report "W-c: d_precnt_o = " & integer'image(to_integer(d_precnt)) & ", reference "
             & integer'image(n_sh) severity error;
    report "W-c: " & integer'image(n) & " words, " & integer'image(n_exp) & " edges, "
           & integer'image(n_sh) & " shifted by exactly 7 cycles, d_precnt_o agrees -- OK";
    -- non-MFM neighbourhoods and the boundaries
    ws.set(0, x"AAAA"); ws.set(1, x"FFFF"); ws.set(2, x"6666"); ws.set(3, x"4489");
    ws.set(4, x"1248"); ws.set(5, x"F0F0"); ws.set(6, x"8001"); ws.set(7, x"AAAA");
    e0 := fall_log.count; g0 := gfall_log.count;
    run_session(8);
    g := gfall_log.get(g0);
    check_flux(e0, g, 8, true, integer'high, "W-c2", n_exp, n_sh);
    assert to_integer(d_precnt) = n_sh report "W-c2: d_precnt_o" severity error;
    -- class coverage
    for b4 in 2 to 4 loop
      for af in 2 to 4 loop
        assert cls(b4 * 5 + af) > 0
          report "W-c: neighbourhood class " & integer'image(b4) & "->" & integer'image(af)
                 & " never exercised" severity error;
      end loop;
    end loop;
    assert cls(1 * 5 + 1) + cls(1 * 5 + 2) + cls(2 * 5 + 1) + cls(1 * 5 + 4) + cls(4 * 5 + 1) > 0
      report "W-c: no invalid-MFM neighbourhood exercised" severity error;
    report "W-c: classes 2->4 " & integer'image(cls(14)) & ", 4->2 " & integer'image(cls(22))
           & ", 2->3 " & integer'image(cls(13)) & ", 3->2 " & integer'image(cls(17))
           & ", 3->4 " & integer'image(cls(19)) & ", 4->3 " & integer'image(cls(23))
           & ", symmetric " & integer'image(cls(12) + cls(18) + cls(24))
           & ", invalid " & integer'image(cls(6) + cls(7) + cls(11) + cls(9) + cls(21))
           & "; boundary bits unshifted -- OK";
    precomp <= '0';

    ---------------------------------------------------------------------------
    -- W-g back-to-back sessions, refused pushes
    ---------------------------------------------------------------------------
    build_field(8, 16#0BAD#, s);
    n := s;
    pf0 := to_integer(d_pushfull);
    g0 := gfall_log.count;
    run_session(n);
    r0 := grise_log.count;
    a0 := grise_log.get(r0 - 1);           -- end of session A
    -- three pushes while idle: refused
    for i in 1 to 3 loop
      edge(c);
      push_m <= '1';
      word_m <= x"FFFF";
    end loop;
    edge(c);
    push_m <= '0';
    tick(2);
    assert to_integer(d_pushfull) = pf0 + 3
      report "W-g: idle pushes not refused/counted" severity error;
    assert level = 0 report "W-g: idle push entered the FIFO" severity error;
    -- session B starts right away, distinct first word
    ws.set(0, x"4489"); ws.set(1, x"4489"); ws.set(2, x"4489");
    for i in 3 to 15 loop
      ws.set(i, mfm_w(std_logic_vector(to_unsigned(i * 29 mod 256, 8)), '0'));
    end loop;
    e0 := fall_log.count;
    g1 := gfall_log.count;
    run_session(16);
    g := gfall_log.get(g1);
    assert g > a0 report "W-g: gate order" severity error;
    check_flux(e0, g, 16, false, integer'high, "W-g B", n_exp, n_sh);
    assert fall_log.get(e0) = g + 1 * C_WR_CELL_CYC + C_WR_LAUNCH_CYC
      report "W-g: B's first edge is not bit 1 of 0x4489" severity error;
    report "W-g: back-to-back session B starts with its own first word (first edge G+150 = bit 1 of 0x4489), 3 idle pushes refused -- OK";
    -- session C: five pushes in a row, the fifth refused while full
    pf0 := to_integer(d_pushfull);
    wait_idle;
    e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
    edge(c);
    session_m <= '1';
    for i in 0 to 4 loop
      push_m <= '1';
      word_m <= mfm_w(std_logic_vector(to_unsigned(16#31# + i, 8)), '1');
      ws.set(i, mfm_w(std_logic_vector(to_unsigned(16#31# + i, 8)), '1'));
      edge(c);
    end loop;
    push_m <= '0';
    session_m <= '0';
    tick(1);
    assert full = '1' and level = 4 report "W-g: FIFO not full after 5 pushes" severity error;
    wait_idle;
    assert to_integer(d_pushfull) = pf0 + 1
      report "W-g: push while full not counted" severity error;
    g := gfall_log.get(g0);
    r := grise_log.get(r0);
    assert r - g = 4 * 1600 report "W-g C: window " & integer'image(r - g) severity error;
    check_flux(e0, g, 4, false, integer'high, "W-g C", n_exp, n_sh);
    report "W-g: push while full refused and counted, only the 4 buffered words written -- OK";

    ---------------------------------------------------------------------------
    -- W-e underrun
    ---------------------------------------------------------------------------
    build_field(4, 16#7777#, s);
    ur0 := to_integer(d_underrun);
    ab0 := to_integer(d_abort);
    e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
    start_session(2, true);
    wait until d_underrun /= ur0 for 3 ms;
    tick(4);
    assert to_integer(d_underrun) = ur0 + 1 report "W-e: no underrun" severity failure;
    g := gfall_log.get(g0);
    r := grise_log.get(r0);
    assert (r - g + 1) mod C_WR_CELL_CYC = 0
      report "W-e: gate closed off a cell boundary" severity error;
    check_flux(e0, g, 2, false, r, "W-e", n_exp, n_sh);
    assert d_reason = x"40" and d_flags(3) = '1' and d_flags(1) = '1'
           and to_integer(d_abort) = ab0 + 1
      report "W-e: reason 0x" & hx(d_reason) & " flags 0x" & hx(d_flags) severity error;
    assert busy = '1' and gate = '0' report "W-e: state after underrun" severity error;
    feed_rel <= not feed_rel;
    wait_idle;
    report "W-e: underrun aborts at the cell boundary (window " & integer'image(r - g)
           & " cycles, " & integer'image(n_exp) & " edges written), reason 0x40, d_underrun_o -- OK";
    -- no words at all: waits in ARM, gate shut, nothing counted
    dc0 := to_integer(d_discard);
    g0 := gfall_log.count;
    start_session(0, true);
    tick(100_000);
    assert busy = '1' and gfall_log.count = g0 and to_integer(d_underrun) = ur0 + 1
      report "W-e: empty session misbehaved" severity error;
    feed_rel <= not feed_rel;
    wait_idle;
    assert to_integer(d_discard) = dc0 and gfall_log.count = g0
      report "W-e: empty session counted or gated" severity error;
    report "W-e: a session without words waits in ARM with the gate shut, ends silently -- OK";

    ---------------------------------------------------------------------------
    -- W-i cut_i at a cell boundary
    ---------------------------------------------------------------------------
    build_field(40, 16#2468#, s);
    n := s;
    ab0 := to_integer(d_abort);
    e0 := fall_log.count; g0 := gfall_log.count; r0 := grise_log.count;
    start_session(n, false);
    wait until gate = '1' for 2 ms;
    tick(1600 * 20 + 1234);
    edge(c);
    feed_stop <= not feed_stop;          -- session falls at c+3 ...
    edge(c);
    cut <= '1';                          -- ... with the cut seen at c+2
    edge(c);
    cut <= '0';
    wait_idle;
    g := gfall_log.get(g0);
    r := grise_log.get(r0);
    t := c + 1;                          -- the edge that sampled cut_i
    assert (r - g + 1) mod C_WR_CELL_CYC = 0 and r >= t and r - t < C_WR_CELL_CYC
      report "W-i: gate closed at G+" & integer'image(r - g) & ", cut seen at G+"
             & integer'image(t - g) severity error;
    check_flux(e0, g, n, false, r, "W-i", n_exp, n_sh);
    assert d_flags = "10001" and to_integer(d_abort) = ab0
      report "W-i: flags 0x" & hx(d_flags) severity error;
    assert to_integer(d_gate_cyc) = r - g report "W-i: d_gate_cyc_o" severity error;
    report "W-i: cut_i closes WGATE at the next cell boundary (" & integer'image(r - t)
           & " cycles after the cut), exact prefix of " & integer'image(n_exp)
           & " edges, completed + cut, no abort -- OK";

    ---------------------------------------------------------------------------
    -- W-d abort terms
    ---------------------------------------------------------------------------
    abort_case(0, x"02", false, "motor off");
    run_session(10);                     -- a new session arms and writes
    abort_case(1, x"02", false, "enable off");
    tick(3000);                          -- settle after re-enable
    abort_case(2, x"02", false, "media_ready off");
    abort_case(3, x"20", false, "side flip");
    abort_case(4, x"80", false, "abort_i");
    g0 := gfall_log.count;
    run_session(10);
    assert gfall_log.count = g0 + 1 report "W-d: no new session after the aborts" severity error;
    report "W-d: after the aborts a new session arms and opens WGATE -- OK";
    abort_case(5, x"08", true, "change edge");
    ---------------------------------------------------------------------------
    -- W-f discard (wr_ok revoked by the change edge)
    ---------------------------------------------------------------------------
    assert wr_ok = '0' report "W-f: wr_ok still set" severity failure;
    dc0 := to_integer(d_discard);
    g0 := gfall_log.count;
    build_field(8, 16#5151#, s);
    n := s;
    start_session(n, false);
    t := cyc;
    wait_idle;
    t := cyc - t;
    assert gfall_log.count = g0 and to_integer(d_discard) = dc0 + 1
           and d_flags(2) = '1' and to_integer(d_words_last) = n
      report "W-f: discard misbehaved" severity error;
    assert t >= (n - 1) * 1600 and t <= (n + 1) * 1600
      report "W-f: discard did not consume at cell pace (" & integer'image(t) & " cycles)" severity error;
    report "W-f: unqualified session never opened WGATE, consumed " & integer'image(n)
           & " words in " & integer'image(t) & " cycles (cell pace), d_discard_o -- OK";
    qualify;
    abort_case(6, x"04", true, "protected level");
    qualify;
    assert d_reason_acc = x"EE"
      report "W-d: d_reason_acc_o = 0x" & hx(d_reason_acc) & " (expected 0xEE: 02|04|08|20|40|80)"
      severity error;
    report "W-d: d_reason_acc_o = 0x" & hx(d_reason_acc) & ", d_abort_o = "
           & integer'image(to_integer(d_abort)) & " -- OK";

    ---------------------------------------------------------------------------
    -- W-h reset mid-session, inside a WDATA pulse
    ---------------------------------------------------------------------------
    build_field(44, 16#9999#, s);
    n := s;
    r0 := grise_log.count;
    e0 := fall_log.count;
    start_session(n, false);
    wait until gate = '1' for 2 ms;
    tick(3000);
    wait until wdata = '0' for 1 ms;
    tick(5);
    edge(c);
    rst <= '1';
    tick(10);
    rst <= '0';
    tick(2);
    assert grise_log.count = r0 + 1 report "W-h: WGATE did not rise" severity failure;
    t := grise_log.get(r0) - (c + 2);
    assert t = 0 report "W-h: WGATE rose at t_seen+" & integer'image(t) severity error;
    e1 := fall_log.count;
    assert width_log.count = e1 and width_log.get(e1 - 1) < C_WR_PULSE_CYC
      report "W-h: the pulse in flight was not cut by the reset" severity error;
    assert wr_ok = '0' report "W-h: wr_ok survived the reset" severity error;
    wait until session = '0' for 5 ms;
    tick(50_000);
    assert grise_log.count = r0 + 1 and fall_log.count = e1 and wgate = '1' and wdata = '1'
      report "W-h: pins moved after the reset" severity error;
    report "W-h: reset inside a WDATA pulse: both pins high at t_seen (pulse cut at "
           & integer'image(width_log.get(e1 - 1)) & " cycles), stay high -- OK";

    report "physical_1581_writer: " & integer'image(fall_log.count) & " flux edges, "
           & integer'image(gfall_log.count) & " gate windows checked -- ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
