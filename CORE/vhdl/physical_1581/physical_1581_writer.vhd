-------------------------------------------------------------------------------
-- physical_1581_writer.vhd
--
-- Write front end of the physical internal 1581 drive (issue #244). Runs on
-- the 50 MHz controller clock, the same clock as the controller and the MFM
-- encoder; the constants are verified on this mechanism at this frequency.
--
--   controller -> physical_1581_mfm_encoder -> word_i/word_push_i
--              -> [this block: 4-word FIFO, serializer, precomp, gate]
--              -> f_wdata_o / f_wgate_o
--
-- A format-agnostic bit pipe: nothing here parses what is written. The block
-- owns the magnetic and safety discipline:
--
--   * Word FIFO: 4 deep, same clock, first-word-fall-through. The controller
--     pushes while word_level_o <= 1 (the AExp admission rule); the
--     serializer pops the head in the cycle the last bit of the previous word
--     leaves (the pop IS the reload, there is no holding register). A push
--     while full is refused and counted (d_pushfull_o, must stay 0), and so
--     is a push while the writer is idle outside the cycle in which a session
--     rises: the FIFO is held empty between sessions, so no word of one
--     session can be written at the start of the next.
--
--   * Serializer: one channel bit per C_WR_CELL_CYC = 100 cycles (2.000 us),
--     MSB first per word.
--
--   * WDATA: idle high, one active-low pulse of C_WR_PULSE_CYC = 25 cycles
--     per '1' channel bit, launched at cycle C_WR_LAUNCH_CYC = 50 of the
--     cell (+/- precomp). Registered, single driver, no combinational path
--     to the pin; additionally gated by WGATE: when the gate closes, WDATA
--     returns high in the same clock (a pulse in flight is cut).
--
--   * Write precompensation: a 7-channel-bit window whose middle bit (3) is
--     the bit being written. A '1' whose gap before is shorter than its gap
--     after launches C_WR_PRECOMP_CYC = 7 cycles (140 ns) early, the mirror
--     case late; symmetric and invalid-MFM neighbourhoods are not shifted. A
--     bit whose window reaches before the first bit of the session or beyond
--     its last one is not shifted. precomp_i is sampled when the session
--     binds (its rising edge) and holds for the whole session.
--
--   * WGATE is defined at the output stage: it opens in the cell in which the
--     first bit of the session reaches the pulse generator and closes at the
--     boundary of the cell in which the last bit left it. The window is
--     words x 16 cells, pin to pin, with no lead-in and no lead-out cells;
--     the controller supplies the 12 x 00 run-up and the trailing FF as data.
--     The gate is the full conjunction of its terms, evaluated every cycle:
--       output-stage bit valid AND state STREAM AND no latched abort AND
--       no live abort term AND en_i AND mot_i AND media_ready_i AND wr_ok
--     so every abort term closes WGATE at the first clock edge that sees it.
--     session_i is NOT a gate term: it is the episode level, and the words
--     already pushed when it falls (the tail: FIFO, shifter, window) are
--     written; busy_o falls once the tail has left the output stage, and
--     that is the instant the controller may report completion. session_i
--     may rise only while busy_o = '0' (a rise during the tail would not
--     bind; simulation reports an error). The protected-level and change
--     terms act after their C_WR_FILT-sample filter, all others in the
--     first clock that sees them.
--
--   * cut_i (Write Track end at the index, WRITE-SPEC 5.3): a 1-cycle strobe
--     while streaming. At the next cell boundary the output stage, the
--     shifter and the FIFO are discarded and WGATE closes (the current word
--     is truncated, like on the real chip). The session ends as completed,
--     not aborted; flag bit 4 records the cut. Words pushed after a cut are
--     consumed with the gate shut until session_i falls.
--
--   * Write-protect qualifier (wr_ok): the 1581 mechanism is selected for as
--     long as the controller is enabled, so "selected" is en_i. The status
--     lines are not sampled during the first C_WR_SEL_SETTLE_CYC (50 us)
--     after en_i rises. wr_ok is set once the tab has read writable for
--     C_WR_WPROT_QUAL_CYC (10 ms) of cumulative enabled-and-settled time. It
--     is cleared by a protected level that persists for C_WR_FILT samples, by
--     the assert EDGE of disk change through the same filter, and by reset;
--     en_i low only pauses the accumulator. The change counts as an event,
--     not a level: the mechanism holds it until the next step.
--
--   * Input polarity: wprot_i and change_i come from physical_1581_inputs
--     with POSITIVE semantics: wprot_i = '1' means write protected,
--     change_i = '1' means disk change asserted. (The AExp writer took the
--     active-low pin levels.)
--
--   * ARM -> STREAM: needs two buffered words and a live re-check: wr_ok,
--     en_i, mot_i, media_ready_i, settle complete, a clean tab sample and no
--     change edge in this very cycle. An unqualified session discards: it
--     consumes its words at cell pace with the gate shut (d_discard_o).
--
--   * Abort latch: a gate term lost while streaming (en_i/mot_i/
--     media_ready_i 0x02, protected level 0x04, change edge 0x08, side change
--     against the side latched at the bind 0x20, abort_i 0x80) or an
--     underrun (0x40, detected at the cell boundary where the serializer
--     finds the FIFO empty while session_i is still high) closes WGATE in
--     that clock and ends the session as aborted. The gate stays shut until
--     session_i has fallen and a new session arms. Aborted sessions keep
--     consuming words at cell pace.
--
--   * Diagnostic taps (WRITE-SPEC 8): all counters cumulative since reset;
--     d_words_last_o / d_gate_cyc_o latch at the end of a session;
--     d_precnt_o, d_reason_o and d_flags_o describe the current session from
--     its bind on (an abort is visible there from the clock it happens) and
--     the last one once the writer is idle.
--       d_flags_o: 0 completed, 1 aborted, 2 discarded, 3 underrun, 4 cut
--
-- Adapted from AExp physical_fdd_writer.vhd (sy2002 2026, GPLv3).
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_writer is
  generic (
    G_WPROT_QUAL_CYC : natural := C_WR_WPROT_QUAL_CYC;  -- 10 ms tab qualifier
    G_SEL_SETTLE_CYC : natural := C_WR_SEL_SETTLE_CYC   -- 50 us settle after en_i rises
  );
  port (
    clk_i          : in  std_logic;                     -- 50 MHz controller clock
    rst_i          : in  std_logic;                     -- synchronous reset

    -- drive context (same clock domain; positive semantics)
    en_i           : in  std_logic;                     -- controller enabled (mechanism selected)
    mot_i          : in  std_logic;                     -- motor request on
    media_ready_i  : in  std_logic;                     -- index-qualified spinning medium
    side_i         : in  std_logic;                     -- head select
    wprot_i        : in  std_logic;                     -- '1' = write protected
    change_i       : in  std_logic;                     -- '1' = disk change asserted

    -- controller levels (same clock domain)
    session_i      : in  std_logic;                     -- write episode level
    abort_i        : in  std_logic;                     -- controller abort level
    precomp_i      : in  std_logic;                     -- precomp for this session (sampled at the bind)
    cut_i          : in  std_logic;                     -- 1-cycle: truncate at the next cell boundary

    -- word FIFO push side (from the encoder / controller)
    word_i         : in  std_logic_vector(15 downto 0);
    word_push_i    : in  std_logic;
    word_full_o    : out std_logic;
    word_level_o   : out unsigned(2 downto 0);          -- 0..4 words buffered

    -- connector pins (registered; both idle high, active low)
    f_wdata_o      : out std_logic := '1';
    f_wgate_o      : out std_logic := '1';

    -- status
    busy_o         : out std_logic;                     -- writer not idle (session or tail)
    wr_ok_o        : out std_logic;                     -- tab qualified writable
    gate_o         : out std_logic;                     -- WGATE level, active high

    -- diagnostics
    d_gate_cyc_o   : out unsigned(31 downto 0) := (others => '0');  -- WGATE cycles, last session
    d_words_last_o : out unsigned(15 downto 0) := (others => '0');  -- words consumed, last session
    d_underrun_o   : out unsigned(15 downto 0) := (others => '0');  -- underruns (must stay 0)
    d_discard_o    : out unsigned(15 downto 0) := (others => '0');  -- sessions discarded at ARM
    d_gateopen_o   : out unsigned(15 downto 0) := (others => '0');  -- sessions in which WGATE opened
    d_abort_o      : out unsigned(15 downto 0) := (others => '0');  -- aborted sessions (all reasons)
    d_reason_o     : out std_logic_vector(7 downto 0);              -- abort reason, current/last session
    d_reason_acc_o : out std_logic_vector(7 downto 0);              -- OR of all abort reasons
    d_precnt_o     : out unsigned(15 downto 0) := (others => '0');  -- shifted pulses, current/last session
    d_pushfull_o   : out unsigned(15 downto 0) := (others => '0');  -- refused pushes (must stay 0)
    d_flags_o      : out std_logic_vector(4 downto 0)               -- see the header
  );
end entity physical_1581_writer;

architecture rtl of physical_1581_writer is

  constant C_CELL : natural := C_WR_CELL_CYC;          -- 100 = 2.000 us

  -- the precomp window: index 0 = oldest bit, index 6 = newest, written bit
  -- = 3. The gap before the written bit is read from indices 2/1/0, the gap
  -- after from 4/5/6 (the orientation of the mega65-core f_write_buf table).
  constant C_WIN : natural := 7;
  constant C_MID : natural := 3;

  type t_state is (ST_IDLE, ST_ARM, ST_STREAM, ST_DISCARD, ST_ABORTED);
  signal state : t_state := ST_IDLE;

  -- word FIFO (same clock, FWFT)
  type t_wmem is array (0 to 3) of std_logic_vector(15 downto 0);
  signal wmem     : t_wmem := (others => (others => '0'));
  signal wr_ptr   : unsigned(1 downto 0) := (others => '0');
  signal rd_ptr   : unsigned(1 downto 0) := (others => '0');
  signal wcount   : natural range 0 to 4 := 0;

  -- episode edge
  signal sess_p   : std_logic := '0';
  signal prec_lat : std_logic := '0';

  -- serializer
  signal cell_cnt  : natural range 0 to C_CELL - 1 := 0;
  signal sh_reg    : std_logic_vector(15 downto 0) := (others => '0');
  signal sh_cnt    : natural range 0 to 16 := 0;      -- bits left in sh_reg
  signal win       : std_logic_vector(C_WIN - 1 downto 0) := (others => '0');
  signal vwin      : std_logic_vector(C_WIN - 1 downto 0) := (others => '0');
  signal pulse_cnt : natural range 0 to C_WR_PULSE_CYC := 0;
  signal gate_r    : std_logic := '0';                 -- WGATE, active high here
  signal cut_pend  : std_logic := '0';

  -- write-protect qualifier
  signal qual_cnt  : natural range 0 to G_WPROT_QUAL_CYC := 0;
  signal settle    : natural range 0 to G_SEL_SETTLE_CYC := 0;
  signal en_p      : std_logic := '0';
  signal wp_lo     : natural range 0 to C_WR_FILT := 0;
  signal chg_lo    : natural range 0 to C_WR_FILT := 0;
  signal chg_armed : std_logic := '1';                 -- change edge detector
  signal wr_ok_r   : std_logic := '0';

  -- episode bookkeeping
  signal side_lat   : std_logic := '0';
  signal abort_lat  : std_logic := '0';
  signal reason     : std_logic_vector(7 downto 0) := (others => '0');
  signal reason_acc : std_logic_vector(7 downto 0) := (others => '0');
  signal words_ep   : unsigned(15 downto 0) := (others => '0');
  signal wg_cyc     : unsigned(31 downto 0) := (others => '0');
  signal completed  : std_logic := '0';
  signal discarded  : std_logic := '0';
  signal was_cut    : std_logic := '0';
  signal did_gate   : std_logic := '0';

begin

  busy_o         <= '0' when state = ST_IDLE else '1';
  wr_ok_o        <= wr_ok_r;
  gate_o         <= gate_r;
  word_full_o    <= '1' when wcount = 4 else '0';
  word_level_o   <= to_unsigned(wcount, 3);
  d_reason_o     <= reason;
  d_reason_acc_o <= reason_acc;
  d_flags_o      <= was_cut & reason(6) & discarded & abort_lat & completed;

  main : process (clk_i)
    variable v_gap_b  : natural range 1 to 4;
    variable v_gap_a  : natural range 1 to 4;
    variable v_bit    : std_logic;
    variable v_shift  : integer range -C_WR_PRECOMP_CYC to C_WR_PRECOMP_CYC;
    variable v_term   : std_logic;
    variable v_rsn    : std_logic_vector(7 downto 0);
    variable v_reload : std_logic;
    variable v_dry    : std_logic;
    variable v_pop    : std_logic;
    variable v_push   : std_logic;
    variable v_flush  : std_logic;
    variable v_gate   : std_logic;
    variable v_bind   : std_logic;
    variable v_cut    : std_logic;
    variable v_empty  : std_logic;
    variable v_idle   : std_logic;   -- the session ends in this clock
  begin
    if rising_edge(clk_i) then
      sess_p  <= session_i;
      v_bind  := '1' when state = ST_IDLE and session_i = '1' and sess_p = '0' else '0';
      v_pop   := '0';
      v_dry   := '0';
      v_cut   := '0';
      v_flush := '0';
      v_empty := '1' when wcount = 0 else '0';
      v_idle  := '0';

      -- pragma translate_off
      assert not (session_i = '1' and sess_p = '0' and state /= ST_IDLE)
        report "physical_1581_writer: session_i rose while busy_o = '1' (the new session is not bound)"
        severity error;
      -- pragma translate_on

      ---------------------------------------------------------------------
      -- write-protect qualifier
      ---------------------------------------------------------------------
      en_p <= en_i;
      if en_i = '0' then
        settle <= 0;                              -- disabled: restart the
      elsif en_p = '0' then                       -- output-enable settle
        settle <= 0;
      elsif settle /= G_SEL_SETTLE_CYC then
        settle <= settle + 1;
      end if;

      -- 4-sample filters, sampled only while enabled and settled
      if en_i = '1' and settle = G_SEL_SETTLE_CYC then
        if wprot_i = '1' then
          if wp_lo /= C_WR_FILT then
            wp_lo <= wp_lo + 1;
          end if;
        else
          wp_lo <= 0;
        end if;
        if change_i = '1' then
          if chg_lo /= C_WR_FILT then
            chg_lo <= chg_lo + 1;
          end if;
        else
          chg_lo    <= 0;
          chg_armed <= '1';                       -- re-arm the edge detector
        end if;
      end if;

      -- accumulate enabled time while the tab reads writable
      if en_i = '1' and settle = G_SEL_SETTLE_CYC and wprot_i = '0'
         and wp_lo = 0 then
        if qual_cnt /= G_WPROT_QUAL_CYC then
          qual_cnt <= qual_cnt + 1;
        else
          wr_ok_r <= '1';
        end if;
      end if;

      -- revocations
      if wp_lo = C_WR_FILT then                   -- qualified protected level
        wr_ok_r  <= '0';
        qual_cnt <= 0;
      end if;
      if chg_lo = C_WR_FILT and chg_armed = '1' then  -- the change assert edge
        chg_armed <= '0';
        wr_ok_r   <= '0';
        qual_cnt  <= 0;
      end if;

      ---------------------------------------------------------------------
      -- live abort terms while streaming (ordered: the first one names the
      -- reason)
      ---------------------------------------------------------------------
      v_term := '0';
      v_rsn  := (others => '0');
      if state = ST_STREAM then
        if mot_i = '0' or en_i = '0' or media_ready_i = '0' then
          v_term := '1'; v_rsn := x"02";
        elsif wp_lo = C_WR_FILT then
          v_term := '1'; v_rsn := x"04";
        elsif chg_lo = C_WR_FILT and chg_armed = '1' then
          v_term := '1'; v_rsn := x"08";
        elsif side_i /= side_lat then
          v_term := '1'; v_rsn := x"20";
        elsif abort_i = '1' then
          v_term := '1'; v_rsn := x"80";
        elsif wr_ok_r = '0' then
          -- defensive: unreachable after the ARM re-check, every revocation
          -- above coincides with its own term
          v_term := '1'; v_rsn := x"04";
        end if;
      end if;

      ---------------------------------------------------------------------
      -- cell engine: one channel bit per C_CELL cycles
      ---------------------------------------------------------------------
      if cut_i = '1' and state = ST_STREAM then
        cut_pend <= '1';
      end if;
      if state = ST_STREAM or state = ST_DISCARD or state = ST_ABORTED then
        if cell_cnt = C_CELL - 1 then
          cell_cnt <= 0;
          if (cut_pend = '1' or cut_i = '1') and state = ST_STREAM then
            -- truncate: drop the output stage, the shifter and the FIFO
            v_cut    := '1';
            cut_pend <= '0';
            win      <= (others => '0');
            vwin     <= (others => '0');
            sh_cnt   <= 0;
            v_flush  := '1';
          else
            -- shift the precomp window: the newest bit enters at the top
            v_reload := '0';
            if sh_cnt /= 0 then
              v_bit  := sh_reg(15);
              sh_reg <= sh_reg(14 downto 0) & '0';
              sh_cnt <= sh_cnt - 1;
              if sh_cnt = 1 then
                v_reload := '1';                  -- last bit leaves now
              end if;
              win  <= v_bit & win(C_WIN - 1 downto 1);
              vwin <= '1' & vwin(C_WIN - 1 downto 1);
            else
              win  <= '0' & win(C_WIN - 1 downto 1);
              vwin <= '0' & vwin(C_WIN - 1 downto 1);
              v_reload := '1';
            end if;

            -- FWFT reload: the pop is the reload (no holding register)
            if v_reload = '1' and v_empty = '0' then
              sh_reg   <= wmem(to_integer(rd_ptr));
              sh_cnt   <= 16;
              v_pop    := '1';
              words_ep <= words_ep + 1;
            elsif v_reload = '1' and session_i = '1' and state = ST_STREAM then
              -- underrun, detected at the cell boundary where it happens
              v_dry := '1';
            end if;
          end if;
        else
          cell_cnt <= cell_cnt + 1;
        end if;
      else
        cell_cnt <= 0;
        cut_pend <= '0';
      end if;

      ---------------------------------------------------------------------
      -- precomp and pulse generation (the output stage, where WGATE is
      -- defined)
      ---------------------------------------------------------------------
      if win(2) = '1' then v_gap_b := 1;
      elsif win(1) = '1' then v_gap_b := 2;
      elsif win(0) = '1' then v_gap_b := 3;
      else v_gap_b := 4; end if;
      if win(4) = '1' then v_gap_a := 1;
      elsif win(5) = '1' then v_gap_a := 2;
      elsif win(6) = '1' then v_gap_a := 3;
      else v_gap_a := 4; end if;

      v_shift := 0;
      if prec_lat = '1' and vwin = (vwin'range => '1')
         and v_gap_b /= 1 and v_gap_a /= 1 and v_gap_b /= v_gap_a then
        -- short before / long after -> early; the mirror -> late
        if v_gap_b < v_gap_a then
          v_shift := -C_WR_PRECOMP_CYC;
        else
          v_shift := C_WR_PRECOMP_CYC;
        end if;
      end if;

      -- the gate conjunction, evaluated every cycle
      if vwin(C_MID) = '1' and abort_lat = '0' and state = ST_STREAM
         and v_term = '0' and v_dry = '0' and v_cut = '0'
         and en_i = '1' and mot_i = '1' and media_ready_i = '1'
         and wr_ok_r = '1' then
        v_gate := '1';
      else
        v_gate := '0';
      end if;

      gate_r    <= v_gate;
      f_wgate_o <= not v_gate;
      if v_gate = '1' then
        wg_cyc <= wg_cyc + 1;
        if did_gate = '0' then
          did_gate     <= '1';
          d_gateopen_o <= d_gateopen_o + 1;
        end if;
      end if;

      -- one active-low pulse per '1' bit, at the (possibly shifted) launch;
      -- WDATA is gated by WGATE
      if v_gate = '0' then
        f_wdata_o <= '1';
        pulse_cnt <= 0;
      else
        if pulse_cnt /= 0 then
          pulse_cnt <= pulse_cnt - 1;
          if pulse_cnt = 1 then
            f_wdata_o <= '1';
          end if;
        end if;
        if win(C_MID) = '1' and cell_cnt = (C_WR_LAUNCH_CYC + v_shift) then
          f_wdata_o <= '0';
          pulse_cnt <= C_WR_PULSE_CYC;
          if v_shift /= 0 then
            d_precnt_o <= d_precnt_o + 1;
          end if;
        end if;
      end if;

      ---------------------------------------------------------------------
      -- episode FSM
      ---------------------------------------------------------------------
      case state is
        when ST_IDLE =>
          if v_bind = '1' then
            -- a new session binds: clear the per-session state
            state      <= ST_ARM;
            abort_lat  <= '0';
            reason     <= (others => '0');
            words_ep   <= (others => '0');
            wg_cyc     <= (others => '0');
            completed  <= '0';
            discarded  <= '0';
            was_cut    <= '0';
            did_gate   <= '0';
            side_lat   <= side_i;
            prec_lat   <= precomp_i;
            win        <= (others => '0');
            vwin       <= (others => '0');
            sh_cnt     <= 0;
            d_precnt_o <= (others => '0');
          else
            v_flush := '1';                       -- no residue between sessions
          end if;

        when ST_ARM =>
          if session_i = '0' then
            -- the session ended before STREAM was reached: leave through
            -- ST_DISCARD so the words already pushed are consumed, not
            -- serialized in front of the next session
            state <= ST_DISCARD;
          elsif wcount >= 2 then
            -- wr_ok_r alone is not enough: streaming also requires the
            -- live terms, a completed settle, a clean tab sample and no
            -- change edge being taken in this very cycle
            if wr_ok_r = '1' and en_i = '1' and mot_i = '1'
               and media_ready_i = '1' and settle = G_SEL_SETTLE_CYC
               and wp_lo = 0
               and not (chg_lo = C_WR_FILT and chg_armed = '1') then
              state <= ST_STREAM;
            else
              state       <= ST_DISCARD;
              discarded   <= '1';
              d_discard_o <= d_discard_o + 1;
            end if;
          end if;

        when ST_STREAM =>
          if v_term = '1' or v_dry = '1' then
            -- abort_lat keeps WGATE shut (the gate expression includes it);
            -- the session stays aborted
            if v_term = '1' then
              reason     <= v_rsn;
              reason_acc <= reason_acc or v_rsn;
            else
              reason       <= x"40";
              reason_acc   <= reason_acc or x"40";
              d_underrun_o <= d_underrun_o + 1;
            end if;
            abort_lat <= '1';
            d_abort_o <= d_abort_o + 1;
            state     <= ST_ABORTED;
          elsif v_cut = '1' then
            was_cut   <= '1';
            completed <= '1';
            if session_i = '0' then
              state  <= ST_IDLE;
              v_idle := '1';
            else
              state <= ST_DISCARD;                -- consume late pushes, gate shut
            end if;
          elsif v_empty = '1' and sh_cnt = 0
                and vwin = (vwin'range => '0') and session_i = '0' then
            completed <= '1';                     -- the normal tail is done
            state     <= ST_IDLE;
            v_idle    := '1';
          end if;

        when ST_DISCARD | ST_ABORTED =>
          -- keep consuming at cell pace; the gate stays shut
          if session_i = '0' and v_empty = '1' and sh_cnt = 0 then
            state  <= ST_IDLE;
            v_idle := '1';
          end if;
      end case;

      -- end-of-session bookkeeping, at the transition to IDLE: the gate is
      -- shut and nothing is popped in that clock, so both values are final
      if v_idle = '1' then
        d_words_last_o <= words_ep;
        d_gate_cyc_o   <= wg_cyc;
      end if;

      ---------------------------------------------------------------------
      -- word FIFO
      ---------------------------------------------------------------------
      v_push := '0';
      if word_push_i = '1' then
        if wcount = 4 or (state = ST_IDLE and v_bind = '0') then
          d_pushfull_o <= d_pushfull_o + 1;       -- refused
        else
          v_push := '1';
        end if;
      end if;
      if v_flush = '1' then
        -- idle (pushes already refused above) or a cut (a push in the cut
        -- clock belongs to the truncated stream and is dropped silently)
        rd_ptr <= (others => '0');
        wr_ptr <= (others => '0');
        wcount <= 0;
      else
        if v_push = '1' then
          wmem(to_integer(wr_ptr)) <= word_i;
          wr_ptr <= wr_ptr + 1;
        end if;
        if v_pop = '1' then
          rd_ptr <= rd_ptr + 1;
        end if;
        if v_push = '1' and v_pop = '0' then
          wcount <= wcount + 1;
        elsif v_push = '0' and v_pop = '1' then
          wcount <= wcount - 1;
        end if;
      end if;

      ---------------------------------------------------------------------
      if rst_i = '1' then
        state      <= ST_IDLE;
        f_wgate_o  <= '1';
        f_wdata_o  <= '1';
        gate_r     <= '0';
        pulse_cnt  <= 0;
        cell_cnt   <= 0;
        sh_cnt     <= 0;
        win        <= (others => '0');
        vwin       <= (others => '0');
        cut_pend   <= '0';
        abort_lat  <= '0';
        wr_ok_r    <= '0';
        qual_cnt   <= 0;
        settle     <= 0;
        wp_lo      <= 0;
        chg_lo     <= 0;
        chg_armed  <= '1';
        reason     <= (others => '0');
        reason_acc <= (others => '0');
        completed  <= '0';
        discarded  <= '0';
        was_cut    <= '0';
        did_gate   <= '0';
        prec_lat   <= '0';
        rd_ptr     <= (others => '0');
        wr_ptr     <= (others => '0');
        wcount     <= 0;
        words_ep   <= (others => '0');
        wg_cyc     <= (others => '0');
        d_gate_cyc_o   <= (others => '0');
        d_words_last_o <= (others => '0');
        d_underrun_o   <= (others => '0');
        d_discard_o    <= (others => '0');
        d_gateopen_o   <= (others => '0');
        d_abort_o      <= (others => '0');
        d_precnt_o     <= (others => '0');
        d_pushfull_o   <= (others => '0');
      end if;
    end if;
  end process main;

end architecture rtl;
