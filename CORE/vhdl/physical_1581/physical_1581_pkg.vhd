-------------------------------------------------------------------------------
-- physical_1581_pkg.vhd
--
-- Constants, result/op codes and cycle-conversion helpers for the physical
-- internal 1581 drive (issue #90), read-only milestone.
--
-- All magnetic timing derives from a single controller clock frequency
-- C_FDC_HZ = 50 MHz (the exact QNICE-domain clock c64_clk_sd_i). The MEGA65
-- native "0x51" divisor is 40.5 MHz-specific and is deliberately NOT used.
--
-- Timing values are the specification's initial/binding figures (there is no
-- hardware instrument to re-measure them); they live here so a future profile
-- freeze touches one file only.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package physical_1581_pkg is

  -- Controller clock (exact; QNICE domain).
  constant C_FDC_HZ     : natural := 50_000_000;
  constant C_PERIOD_NS  : natural := 1_000_000_000 / C_FDC_HZ;   -- 20 ns
  constant C_CYC_PER_US : natural := C_FDC_HZ / 1_000_000;       -- 50

  -- Cycle-conversion helpers.
  --   cyc_us  : microseconds  -> cycles (exact for integral us)
  --   cyc_ns  : nanoseconds    -> cycles (round to nearest)
  function cyc_us(us : natural) return natural;
  function cyc_ns(ns : natural) return natural;

  -----------------------------------------------------------------------------
  -- DD MFM timing @ 50 MHz (250 kbit/s, 300 RPM)
  -----------------------------------------------------------------------------
  constant C_HALF_CELL_CYC : natural := 100;   -- 2 us clock/data half-cell
  constant C_GAP_SHORT_CYC : natural := 200;   -- 4 us nominal flux gap
  constant C_GAP_MED_CYC   : natural := 300;   -- 6 us
  constant C_GAP_LONG_CYC  : natural := 400;   -- 8 us
  constant C_BYTE_CYC      : natural := 1600;  -- 32 us decoded byte time

  -- LEGACY fixed gap-classification windows (spec 14.3), inclusive, in cycles.
  -- UNUSED by production code since round 12: physical_1581_mfm_quantise now
  -- classifies adaptively against a tracked half-cell estimate (see the
  -- C_QUANT_* constants below) with no dead-bands. Kept as documentation of
  -- the original acceptance profile and as the behavior reference for the
  -- test-only fixed-window classifier in
  -- CORE/vhdl/test/tb_physical_1581_codec/ref_mfm_quantise_fixed.vhd (the
  -- "old" side of the A/B margin harness). Hardware motivation for the
  -- change: on real DD media the inner cylinders (60+) show enough peak
  -- shift that gaps smeared into the dead-bands (241..257, 343..354) for
  -- revolutions at a time -> class-11 loss of lock -> persistent RNF.
  constant C_GAP_SHORT_LO : natural := 160;    -- 3.2 us
  constant C_GAP_SHORT_HI : natural := 240;    -- 4.8 us
  constant C_GAP_MED_LO   : natural := 258;    -- 5.16 us
  constant C_GAP_MED_HI   : natural := 342;    -- 6.84 us
  constant C_GAP_LONG_LO  : natural := 355;    -- 7.1 us
  constant C_GAP_LONG_HI  : natural := 445;    -- 8.9 us

  -----------------------------------------------------------------------------
  -- Adaptive gap quantiser (issue #90 round 12)
  --
  -- The quantiser tracks the live half-cell length as a fixed-point estimate
  -- est with C_QUANT_FRAC fraction bits (unit: 50 MHz cycles; nominal 100.0).
  -- Each gap G is classified to the nearest class n in {2,3,4} half-cells via
  -- the midpoints 2.5*est / 3.5*est and ACCEPTED iff
  --     |G - n*est| <= est / 2**C_QUANT_TOL_SHR
  -- With C_QUANT_TOL_SHR = 1 the acceptance windows touch at the midpoints:
  -- every gap in [1.5*est .. 4.5*est] gets a class, there are NO dead-bands,
  -- and everything outside is class "11" (loss of lock), which also re-seeds
  -- est to nominal. On every accepted gap est adapts by a FIXED step of
  -- C_QUANT_STEP_Q toward the gap (sign-based / median-seeking:
  -- est += step * sign(G - n*est)), and is hard-clamped to
  -- [C_QUANT_EST_MIN .. C_QUANT_EST_MAX] cycles (real drive speed tolerance
  -- is ~+/-3%; the +/-10% clamp bounds any runaway adaptation).
  --
  -- WHY sign-based and not the proportional IIR est += (G/n - est)/8: the
  -- A/B margin harness (tb_physical_1581_quantise_ab) showed that under
  -- peak shift (ISI) short gaps only ever lengthen and long gaps only ever
  -- shrink, so a magnitude-weighted mean estimator has a biased equilibrium
  -- and was dragged to the +10% clamp at shift S=20 -- misclassifying the
  -- shrunken long gaps (360 < 3.5*110) as mediums and LOSING to the old
  -- fixed windows. A uniform-step sign update converges to the MEDIAN of
  -- the per-gap error, which the unshifted majority anchors at the true
  -- speed (residual bias about +1 cycle at S=20). Convergence: 1/8 cycle
  -- per accepted gap reaches the clamp from nominal in 80 gaps, well inside
  -- one preamble+lead-in; drift of a few percent per revolution is orders
  -- of magnitude slower than that.
  -----------------------------------------------------------------------------
  constant C_QUANT_FRAC      : natural := 4;   -- fraction bits of est (1/16 cycle)
  constant C_QUANT_EST_MIN   : natural := 90;  -- clamp, integer cycles (-10%)
  constant C_QUANT_EST_MAX   : natural := 110; -- clamp, integer cycles (+10%)
  constant C_QUANT_TOL_SHR   : natural := 1;   -- tolerance = est/2 (windows touch)
  constant C_QUANT_STEP_Q    : natural := 2;   -- adaptation step: 2/16 = 1/8 cycle

  -----------------------------------------------------------------------------
  -- Write-splice sync qualification (issue #90 round 13)
  --
  -- HARDWARE REGRESSION the round-12 quantiser introduced: the sector
  -- immediately after the index write-splice (t39 s1, which holds the D81
  -- header/BAM) became DETERMINISTICALLY unreadable -- 30/30 RNF, its ID never
  -- decoded (CNT_IDDEC stuck at 10/rev), zero CRC errors, and CNT_GAPERR
  -- DROPPED from 20..29/rev to ~16/rev. Mechanism (reproduced gap-exact in
  -- tb_physical_1581_quantise_ab, "junk chain" trials): the splice leaves
  -- garbage flux whose gaps the old fixed windows rejected loudly (dead-bands
  -- 241..257 / 343..354 / >445 -> class 11 -> the whole pipeline re-synced),
  -- but the round-12 no-dead-band acceptance (est/2, span [1.5*est..4.5*est])
  -- swallows as valid 2/3/4-half-cell classes. A junk run that alternates
  -- long/medium-looking gaps (e.g. ~446/~344 cycles) then reads EXACTLY like
  -- the A1 missing-clock pattern (long,med,long,med): the sync detector fires
  -- FALSE A1 syncs every two gaps, three of them arm the decoder (sync_cnt=3),
  -- and eight more junk gaps can then assemble an FB data mark -> the decoder
  -- opens a BOGUS 512-byte data field that consumes the following sector's
  -- real preamble + ID + A1 train every revolution. All observed counter
  -- signatures follow (no id_valid -> IDDEC 10; garbage data CRC is not
  -- counted as an ID CRC error; junk that used to be loud is now accepted ->
  -- GAPERR drop).
  --
  -- WHY NOT a tight acquisition tolerance (the first fix candidate, est/4
  -- while hunting / est/2 in-field): the A/B harness REFUTED it. Under peak
  -- shift (ISI) every gap of the A1 train itself deviates by 2*S (the train
  -- alternates long/med, so both neighbors of every transition differ: longs
  -- shrink 2*S, mediums grow 2*S). est/4 = +/-25 cycles therefore rejects the
  -- sync train of every record with S >= 13 -- killing the round-12 far-
  -- cylinder wins (peak S=15/20/22/24 and the S20+/-3%, S15+5% inner-cylinder
  -- combos) that motivated the adaptive quantiser in the first place. Worse,
  -- the junk deviations (+46..+48) and the legitimate S=22/24 train deviations
  -- (+/-44..48) OVERLAP, so NO per-gap tolerance can separate them.
  --
  -- THE SHIPPED FIX is structural instead, matching what a real data
  -- separator does (a PLL only locks during the lock-up preamble field; the
  -- 1581/WD1772 format writes 12 x 00 before every A1 train for exactly this):
  -- while the decoder is HUNTING (not inside a field), an A1 sync is honored
  -- only if a run of C_QUANT_SYNC_RUN consecutive SHORT-class gaps (the 00
  -- preamble; 12 bytes = 96 short gaps, so 16 = 2 bytes is a generous lower
  -- bound) ended no more than C_QUANT_SYNC_LAT gaps ago. The A1 window itself
  -- consumes exactly 5 gaps after the preamble (the med entry gap + the
  -- long,med,long,med pattern), hence LAT = 6. Splice junk contains no such
  -- run -> false syncs are ignored and a bogus field can never open; every
  -- legitimate field (including freshly written ones -- the WD1772 always
  -- writes its own 12 x 00 preamble after the write splice) passes untouched,
  -- so ALL round-12 stress wins are preserved bit-for-bit. In-field syncs
  -- (A1 #2/#3 of a train) bypass the gate. Additionally, while hunting the
  -- estimate adapts from SHORT-class gaps only (the preamble is all shorts,
  -- which is what legitimate acquisition tracks), so splice junk cannot walk
  -- est; in-field adaptation is unchanged from round 12.
  -----------------------------------------------------------------------------
  constant C_QUANT_SYNC_RUN  : natural := 16;  -- shorts run that banks the gate (2 x 00)
  constant C_QUANT_SYNC_LAT  : natural := 6;   -- gaps allowed between run end and sync
  constant C_QUANT_EST_NOM_Q : natural := C_HALF_CELL_CYC * 2**C_QUANT_FRAC;
  constant C_QUANT_EST_MIN_Q : natural := C_QUANT_EST_MIN * 2**C_QUANT_FRAC;
  constant C_QUANT_EST_MAX_Q : natural := C_QUANT_EST_MAX * 2**C_QUANT_FRAC;
  -- Runt-merge threshold for the gaps stage. Round 11: reduced from 120 to 16
  -- cycles (320 ns). At 120, a noise edge landing LATE in a real gap (more
  -- than 120 cycles after the previous edge but less than 120 before the next
  -- REAL edge) made the gaps stage misclassify the REAL edge as the runt and
  -- merge it away, emitting one wrong-length gap that can land in a VALID
  -- window (e.g. 60+200 = 260 = MED) -- silent decode corruption instead of a
  -- loud class-11 re-sync; observed on hardware as a persistently unreadable
  -- sector (t39 s7 RNF, 2026-07-14). At 16, only true electrical runts (the
  -- GAP_MIN = 0x0001 evidence: edges 20-40 ns apart) merge; everything longer
  -- stays a loud out-of-window gap, exactly as before round 10.
  constant C_GAP_GLITCH   : natural := 16;     -- below: electrical glitch/noise

  -----------------------------------------------------------------------------
  -- Backend result codes (spec 9.6, 5-bit) -- read-path subset
  -----------------------------------------------------------------------------
  subtype result_t is std_logic_vector(4 downto 0);
  constant RES_OK               : result_t := "00000";
  constant RES_NOT_READY        : result_t := "00001";
  constant RES_NO_INDEX         : result_t := "00010";
  constant RES_TRACK0_FAILED    : result_t := "00011";
  constant RES_RECORD_NOT_FOUND : result_t := "00100";
  constant RES_ID_CRC_ERROR     : result_t := "00101";
  constant RES_MISSING_DAM      : result_t := "00110";
  constant RES_DATA_CRC_ERROR   : result_t := "00111";
  constant RES_UNSUPPORTED_SIZE : result_t := "01000";
  constant RES_WRITE_PROTECTED  : result_t := "01001";
  constant RES_DISK_CHANGED     : result_t := "01010";
  constant RES_CANCELLED        : result_t := "01101";
  constant RES_INVALID_REQUEST  : result_t := "01110";
  constant RES_INTERNAL_FAULT   : result_t := "01111";

  -----------------------------------------------------------------------------
  -- Internal read-operation codes (3-bit) presented across the ABI
  -----------------------------------------------------------------------------
  subtype rdop_t is std_logic_vector(2 downto 0);
  constant RDOP_READ_SECTOR  : rdop_t := "000";
  constant RDOP_READ_ADDRESS : rdop_t := "001";
  constant RDOP_VERIFY       : rdop_t := "010";
  constant RDOP_READ_TRACK   : rdop_t := "011";

  -----------------------------------------------------------------------------
  -- MFM address-mark byte values (decoded)
  -----------------------------------------------------------------------------
  constant MARK_A1 : unsigned(7 downto 0) := x"A1";   -- sync (raw 0x4489)
  constant MARK_C2 : unsigned(7 downto 0) := x"C2";   -- index sync (raw 0x5224)
  constant MARK_FE : unsigned(7 downto 0) := x"FE";   -- ID address mark
  constant MARK_FB : unsigned(7 downto 0) := x"FB";   -- data mark (normal)
  constant MARK_F8 : unsigned(7 downto 0) := x"F8";   -- data mark (deleted)

  -- CRC-16/CCITT-FALSE state after feeding A1 A1 A1 (sanity anchor).
  constant C_CRC_AFTER_3XA1 : unsigned(15 downto 0) := x"CDB4";

  -- Standard 1581 sector size code (N=2 => 512 bytes) -- only value supported.
  constant C_SIZECODE_512 : unsigned(7 downto 0) := x"02";

end package physical_1581_pkg;

package body physical_1581_pkg is

  function cyc_us(us : natural) return natural is
  begin
    return us * C_CYC_PER_US;
  end function;

  function cyc_ns(ns : natural) return natural is
  begin
    -- round to nearest cycle: (ns + period/2) / period
    return (ns + C_PERIOD_NS / 2) / C_PERIOD_NS;
  end function;

end package body physical_1581_pkg;
