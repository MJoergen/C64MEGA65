-------------------------------------------------------------------------------
-- physical_1581_mfm_quantise.vhd
--
-- DD-MFM read pipeline, stage 2 of 4: gap interval -> 2-bit gap class.
--   "00" = short  (2 half-cells)   "01" = medium (3 half-cells)
--   "10" = long   (4 half-cells)   "11" = invalid / loss-of-lock
--
-- ADAPTIVE quantiser (issue #90 round 12). The fixed windows of the previous
-- revision (see the LEGACY C_GAP_* constants in physical_1581_pkg) had hard
-- dead-bands between the classes; on real DD media the inner cylinders (60+)
-- show enough peak shift that a sector's gaps landed in a dead-band for
-- revolutions at a time -> class-11 loss of lock -> persistent RNF (hardware
-- evidence 2026-07-14, cyls 61-62). This stage now:
--
--   * tracks the live half-cell length as a fixed-point estimate est
--     (C_QUANT_FRAC = 4 fraction bits; unit 50 MHz cycles; nominal 100.0),
--     seeded to nominal on reset AND on every loss of lock (a rejected gap);
--     the decoder above resets this stage at every operation start, so an
--     idle/re-search also re-seeds;
--   * classifies each gap G to the NEAREST class n in {2,3,4} half-cells by
--     comparing G against the midpoints 2.5*est and 3.5*est;
--   * accepts the class iff |G - n*est| <= est/2**shr (shr selected by
--     field_i, both generics default C_QUANT_TOL_SHR = 1). With shr = 1 the
--     acceptance windows touch at the midpoints:
--     every gap in [1.5*est .. 4.5*est] classifies, there are NO dead-bands,
--     and only gaps outside that span are class "11" (loss of lock), exactly
--     as loud as before. (A stray mid-gap noise edge, e.g. the stable
--     126-cycle artifact measured on the test disk, still rejects: 126 is
--     below 1.5*est for every legal est.);
--   * adapts est on every ACCEPTED gap by a FIXED step of C_QUANT_STEP_Q
--     (1/8 cycle) toward the gap: est += step * sign(G - n*est). This
--     sign-based (median-seeking) update replaces the originally-drafted
--     proportional IIR est += (G/n - est)/8: the A/B margin harness showed
--     the proportional form has a BIASED equilibrium under peak shift (ISI
--     lengthens short gaps and shrinks long gaps systematically, dragging a
--     magnitude-weighted mean to the +10% clamp at S=20 and misclassifying
--     the shrunken longs), while the sign update converges to the MEDIAN of
--     the per-gap error, anchored at true speed by the unshifted majority
--     gaps -- see the C_QUANT_* comment block in physical_1581_pkg;
--   * hard-clamps est to [C_QUANT_EST_MIN .. C_QUANT_EST_MAX] = [90 .. 110]
--     cycles (+/-10% of nominal), bounding any runaway adaptation (real
--     drive speed tolerance is ~+/-3%).
--
-- ROUND-14 ACQUISITION (write-splice regression, see the C_QUANT_SYNC_* comment
-- block in physical_1581_pkg for the full story): production restores round
-- 12's adaptation from every accepted gap. Restricting hunt adaptation to
-- short gaps was part of round 13's 00-preamble assumption; on an F011 4E gap,
-- peak shift biases those shorts and can walk est far enough to lose the next
-- ID train. The exact three-A1 spacing qualifier above this stage now rejects
-- splice false syncs independently of the adaptation policy. The
-- G_HUNT_ADAPT_ALL generic remains so the harness can preserve round 13.
-- The classification tolerance itself stays est/2 in BOTH phases: the A/B
-- harness REFUTED a tight (est/4) acquisition tier, because ISI deviates
-- every gap of the A1 train itself by 2*S (the train alternates long/med),
-- so est/4 rejects the sync train of any record with peak shift S >= 13 and
-- loses the round-12 far-cylinder wins. The G_TOL_ACQ_SHR generic exists so
-- the harness can still instantiate that refuted variant as evidence; both
-- tolerance generics default to the single production C_QUANT_TOL_SHR.
--
-- est_o exposes the estimate (Q8.4) as a read-only diagnostic tap; it is
-- threaded decoder -> controller -> physical_1581_diag word 0x36 and never
-- read back into any behavior.
--
-- Lineage: this stage replaces the fixed-window classifier adapted from
-- mega65-core src/vhdl/mfm_quantise_gaps.vhdl @ a9158930 (Paul
-- Gardner-Stephen / MEGA65, LGPLv3); the upstream cycles_per_interval idea
-- returns here as a tracked estimate with explicit tolerance + clamps. The
-- previous fixed-window architecture is preserved verbatim as the test-only
-- reference entity in CORE/vhdl/test/tb_physical_1581_codec/
-- ref_mfm_quantise_fixed.vhd (the "old" side of the A/B margin harness).
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_quantise is
  generic (
    -- Acceptance half-width = est / 2**shr, selected by field_i:
    -- G_TOL_ACQ_SHR while hunting, G_TOL_FIELD_SHR inside a field. BOTH
    -- default to the single production tolerance C_QUANT_TOL_SHR = 1 (est/2:
    -- windows touch at the midpoints, no dead-bands). A tight acquisition
    -- tier (G_TOL_ACQ_SHR = 2 = est/4) was evaluated for the round-13
    -- write-splice fix and REJECTED -- the A/B harness proves it loses the
    -- peak-shift/combo win rows (see entity header); the generic remains so
    -- the harness can keep demonstrating that.
    G_TOL_ACQ_SHR    : natural := C_QUANT_TOL_SHR;
    G_TOL_FIELD_SHR  : natural := C_QUANT_TOL_SHR;
    -- true is production and the round-12 rule (adapt from EVERY accepted gap,
    -- even while hunting); false preserves the round-13 reference behavior.
    G_HUNT_ADAPT_ALL : boolean := true
  );
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;                       -- sync reset (re-seeds est)
    -- '1' once the decoder has qualified a complete A1 train and while its
    -- field FSM is inside ID/data + CRC. Selects the tolerance tier and, when
    -- G_HUNT_ADAPT_ALL=false, gates hunting-phase adaptation (see header).
    field_i     : in  std_logic := '0';
    gap_valid_i : in  std_logic := '0';
    gap_len_i   : in  unsigned(15 downto 0) := (others => '0');
    gap_valid_o : out std_logic := '0';
    gap_class_o : out unsigned(1 downto 0) := "11";
    -- read-only diagnostic tap: live half-cell estimate, Q8.4 fixed point
    -- (bits 11:4 = integer cycles, bits 3:0 = sixteenths). Never read back.
    est_o       : out unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12)
  );
end entity physical_1581_mfm_quantise;

architecture rtl of physical_1581_mfm_quantise is
  -- half-cell estimate, Q8.4 (range clamped to [1440 .. 1760] = 90.0 .. 110.0)
  signal est_q : unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12);
begin

  est_o <= est_q;

  process (clk_i)
    -- all arithmetic in Q4 (sixteenths of a cycle)
    variable g_q      : unsigned(19 downto 0);   -- gap in Q4
    variable c2, c3, c4 : unsigned(14 downto 0); -- n*est, n = 2/3/4
    variable half_est : unsigned(14 downto 0);   -- est/2
    variable mid23    : unsigned(14 downto 0);   -- 2.5*est
    variable mid34    : unsigned(14 downto 0);   -- 3.5*est
    variable center   : unsigned(14 downto 0);   -- n*est of the nearest class
    variable n_cls    : integer range 2 to 4;
    variable e        : signed(21 downto 0);     -- G - n*est (Q4)
    variable tol      : unsigned(14 downto 0);   -- est / 2**(tier shr)
    variable upd      : signed(21 downto 0);     -- adaptation step, +/-C_QUANT_STEP_Q (Q4)
    variable nxt      : signed(21 downto 0);     -- est + upd before clamping
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        gap_valid_o <= '0';
        gap_class_o <= "11";
        est_q       <= to_unsigned(C_QUANT_EST_NOM_Q, est_q'length);
      else
        gap_valid_o <= gap_valid_i;

        if gap_valid_i = '1' then
          g_q      := gap_len_i & "0000";
          c2       := resize(est_q & '0', 15);                    -- 2*est
          c3       := resize(est_q & '0', 15) + resize(est_q, 15);-- 3*est
          c4       := resize(est_q & "00", 15);                   -- 4*est
          half_est := resize(est_q(11 downto 1), 15);             -- est/2
          mid23    := c2 + half_est;                              -- 2.5*est
          mid34    := c3 + half_est;                              -- 3.5*est

          -- nearest class by midpoint comparison
          if g_q < resize(mid23, g_q'length) then
            n_cls := 2; center := c2;
          elsif g_q < resize(mid34, g_q'length) then
            n_cls := 3; center := c3;
          else
            n_cls := 4; center := c4;
          end if;

          e   := signed(resize(g_q, e'length)) - signed(resize(center, e'length));
          if field_i = '1' then
            tol := shift_right(resize(est_q, 15), G_TOL_FIELD_SHR);
          else
            tol := shift_right(resize(est_q, 15), G_TOL_ACQ_SHR);
          end if;

          if abs(e) <= signed(resize(tol, e'length)) then
            -- accepted: emit the class and adapt est by a fixed 1/8-cycle
            -- step toward the gap (sign-based / median-seeking -- see header).
            -- Round 13: while HUNTING only SHORT-class gaps adapt (the 00
            -- preamble); write-splice junk must not walk the estimate.
            gap_class_o <= to_unsigned(n_cls - 2, 2);
            if G_HUNT_ADAPT_ALL or field_i = '1' or n_cls = 2 then
              if e > 0 then
                upd := to_signed(C_QUANT_STEP_Q, upd'length);
              elsif e < 0 then
                upd := to_signed(-C_QUANT_STEP_Q, upd'length);
              else
                upd := (others => '0');
              end if;
              nxt := signed(resize(est_q, nxt'length)) + upd;
              if nxt < to_signed(C_QUANT_EST_MIN_Q, nxt'length) then
                est_q <= to_unsigned(C_QUANT_EST_MIN_Q, est_q'length);
              elsif nxt > to_signed(C_QUANT_EST_MAX_Q, nxt'length) then
                est_q <= to_unsigned(C_QUANT_EST_MAX_Q, est_q'length);
              else
                est_q <= unsigned(nxt(est_q'range));
              end if;
            end if;
          else
            -- out of tolerance: loss of lock, re-seed the estimate
            gap_class_o <= "11";
            est_q       <= to_unsigned(C_QUANT_EST_NOM_Q, est_q'length);
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
