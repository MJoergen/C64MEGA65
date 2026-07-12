-------------------------------------------------------------------------------
-- physical_1581_inputs.vhd
--
-- Asynchronous input conditioner for the physical internal 1581 drive
-- (issue #90), read-only milestone. Runs entirely on the 50 MHz controller
-- clock (c64_clk_sd_i == QNICE clock).
--
-- All raw connector pins are asynchronous and active-low at the pin. This
-- block:
--   * 2-FF metastability-synchronizes every raw pin into clk_i. The first
--     flop of each synchronizer carries the Xilinx `async_reg` attribute so
--     the tool places the pair tightly and does not absorb it into SRLs.
--   * converts the static status lines (track0/write-protect/disk-change) from
--     active-low connector semantics to positive internal semantics.
--   * qualifies the (active-low) INDEX pulse with a leading-edge glitch filter
--     and measures its period and low-pulse width in clk_i cycles.
--   * passes RDATA through the 2-FF synchronizer with its ACTIVE-LOW sense
--     PRESERVED, because the downstream MFM gap stage (physical_1581_mfm_gaps)
--     detects the falling edge of an active-low flux pulse.
--
-- INDEX qualification (spec 6/8): the pin idles high and pulses low once per
-- revolution. An accepted leading (active-going) edge requires f_index to be
-- seen low continuously for >= G_INDEX_MIN_LOW_CYC cycles; only when the low
-- run first reaches that floor does index_edge_o pulse for exactly one cycle.
-- A low run shorter than the floor (electrical glitch) never pulses. The pin
-- must return high before another edge can be accepted. index_period_o latches
-- the cycle count between the last two accepted leading edges; index_width_o
-- latches the low-run length of the last accepted pulse (measured at
-- return-high); index_active_o is the filtered low level.
--
-- NOTE: change_o polarity assumes the board presents disk-change active-low
-- (change asserted => f_diskchanged_i = '0'). This MUST be confirmed against
-- the actual R3 board wiring; invert here if the sensor is active-high.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_inputs is
  generic (
    G_FDC_HZ            : natural := 50_000_000;
    G_INDEX_MIN_LOW_CYC : natural := 10000        -- 200 us glitch floor (< 1.5 ms valid min)
  );
  port (
    clk_i            : in  std_logic;
    rst_i            : in  std_logic;
    -- raw async connector inputs (active-low at pin)
    f_index_i        : in  std_logic;
    f_track0_i       : in  std_logic;
    f_writeprotect_i : in  std_logic;
    f_diskchanged_i  : in  std_logic;
    f_rdata_i        : in  std_logic;
    -- conditioned outputs (positive semantics unless noted)
    rdata_sync_o     : out std_logic;                  -- 2FF-synced flux, active-low sense PRESERVED (decoder expects active-low)
    index_active_o   : out std_logic;                  -- '1' while a filtered index pulse is asserted
    index_edge_o     : out std_logic;                  -- 1-cycle pulse at an accepted index leading (active-going) edge
    index_period_o   : out unsigned(31 downto 0);      -- cycles between the last two accepted leading edges
    index_width_o    : out unsigned(31 downto 0);      -- cycles of the last accepted low pulse
    track0_o         : out std_logic;                  -- '1' = head at track 0 (f_track0_i low)
    wprot_o          : out std_logic;                  -- '1' = write protected (f_writeprotect_i low)
    change_o         : out std_logic                   -- '1' = disk change indicated (f_diskchanged_i low) [polarity per board]
  );
end entity physical_1581_inputs;

architecture rtl of physical_1581_inputs is

  -- 2-FF metastability synchronizers (idle high = pin deasserted).
  signal f_index_meta  : std_logic := '1';
  signal f_index_sync  : std_logic := '1';
  signal f_track0_meta : std_logic := '1';
  signal f_track0_sync : std_logic := '1';
  signal f_wprot_meta  : std_logic := '1';
  signal f_wprot_sync  : std_logic := '1';
  signal f_chg_meta    : std_logic := '1';
  signal f_chg_sync    : std_logic := '1';
  signal f_rdata_meta  : std_logic := '1';
  signal f_rdata_sync  : std_logic := '1';

  attribute async_reg               : string;
  attribute async_reg of f_index_meta  : signal is "true";
  attribute async_reg of f_track0_meta : signal is "true";
  attribute async_reg of f_wprot_meta  : signal is "true";
  attribute async_reg of f_chg_meta    : signal is "true";
  attribute async_reg of f_rdata_meta  : signal is "true";

  constant C_CNT_MAX  : unsigned(31 downto 0) := (others => '1');

  -- INDEX qualification / measurement state.
  signal idx_low_cnt  : unsigned(31 downto 0) := (others => '0');  -- consecutive low cycles
  signal idx_accepted : std_logic := '0';                         -- current low run accepted
  signal period_cnt   : unsigned(31 downto 0) := (others => '0');  -- free-running interval counter

begin

  -- Positive-semantic static status lines (active-low pin -> '1' when asserted).
  track0_o     <= not f_track0_sync;
  wprot_o      <= not f_wprot_sync;
  change_o     <= not f_chg_sync;             -- board polarity: see header NOTE

  -- RDATA keeps its active-low sense for the downstream gap detector.
  rdata_sync_o <= f_rdata_sync;

  -- Filtered index low level.
  index_active_o <= idx_accepted;

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      -- 2-FF synchronizers (always run).
      f_index_meta  <= f_index_i;   f_index_sync  <= f_index_meta;
      f_track0_meta <= f_track0_i;  f_track0_sync <= f_track0_meta;
      f_wprot_meta  <= f_writeprotect_i; f_wprot_sync <= f_wprot_meta;
      f_chg_meta    <= f_diskchanged_i;  f_chg_sync   <= f_chg_meta;
      f_rdata_meta  <= f_rdata_i;   f_rdata_sync  <= f_rdata_meta;

      if rst_i = '1' then
        idx_low_cnt    <= (others => '0');
        idx_accepted   <= '0';
        period_cnt     <= (others => '0');
        index_edge_o   <= '0';
        index_period_o <= (others => '0');
        index_width_o  <= (others => '0');
      else
        -- Defaults for this cycle.
        index_edge_o <= '0';
        if period_cnt /= C_CNT_MAX then
          period_cnt <= period_cnt + 1;
        end if;

        if f_index_sync = '0' then
          -- INDEX asserted (low). Grow the low-run counter (saturating).
          if idx_low_cnt /= C_CNT_MAX then
            idx_low_cnt <= idx_low_cnt + 1;
          end if;
          -- Accept the leading edge exactly when the low run first reaches the
          -- glitch floor. Compared against the pre-increment value.
          if idx_accepted = '0' and
             idx_low_cnt = to_unsigned(G_INDEX_MIN_LOW_CYC - 1, idx_low_cnt'length) then
            idx_accepted   <= '1';
            index_edge_o   <= '1';
            index_period_o <= period_cnt;              -- cycles since previous accept
            period_cnt     <= to_unsigned(1, period_cnt'length);
          end if;
        else
          -- INDEX deasserted (high). Close an accepted pulse: latch its width.
          if idx_accepted = '1' then
            index_width_o <= idx_low_cnt;
          end if;
          idx_accepted <= '0';
          idx_low_cnt  <= (others => '0');
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
