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

  -- Gap-classification acceptance windows (spec 14.3), inclusive, in cycles.
  -- Intervals in the dead-bands (241..257, 343..354) are loss-of-lock, not
  -- snapped to a neighbouring class.
  constant C_GAP_SHORT_LO : natural := 160;    -- 3.2 us
  constant C_GAP_SHORT_HI : natural := 240;    -- 4.8 us
  constant C_GAP_MED_LO   : natural := 258;    -- 5.16 us
  constant C_GAP_MED_HI   : natural := 342;    -- 6.84 us
  constant C_GAP_LONG_LO  : natural := 355;    -- 7.1 us
  constant C_GAP_LONG_HI  : natural := 445;    -- 8.9 us
  constant C_GAP_GLITCH   : natural := 120;    -- below: electrical glitch/noise

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
