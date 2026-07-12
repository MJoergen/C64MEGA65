-------------------------------------------------------------------------------
-- physical_1581_diag.vhd
--
-- READ-ONLY QNICE diagnostic register bank for the physical internal 1581 drive
-- (issue #90). Exposed to QNICE as device C_DEV_C64_PHYS1581 = 0x0108.
--
-- The MEGA65 has no logic analyzer / oscilloscope on the internal floppy bus, so
-- this bank is the ONLY on-hardware window into the read path. It presents:
--   * a signature + version/capability word,
--   * live raw + conditioned input pin levels and the driven mechanism output
--     levels,
--   * the controller's live state (media-ready / head-settled / locked / motor /
--     disk-change / head estimate / read + step FSM phase),
--   * the last completed read result (result code, CRC-error, RNF, deleted flag,
--     found C/H/R/N) latched at rd_done,
--   * the last decoded CRCs (ID stored + ID calc residue + data calc residue),
--   * the last measured index period / width and the last / min / max RDATA flux
--     gap, and
--   * 32-bit SATURATING event counters (raw index edges, index edges while the
--     motor is on, steps, read operations, RNFs, CRC errors, cancellations, disk
--     changes, decoded ID fields, out-of-spec gaps).
--
-- It runs on clk_i == c64_clk_sd_i, which is the SAME 50 MHz clock as both the
-- physical_1581_controller and the QNICE CPU -> no clock-domain crossing is
-- needed anywhere in this file.
--
-- It is STRICTLY observational: it drives nothing back into the controller and it
-- has NO write side (qnice writes, if any, are simply ignored). Register reads are
-- a purely combinational mux over the register file, with no wait-state.
--
-- Register map: see the RM_* constants below and doc/1581_dd_debug_device.md.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_diag is
  port (
    clk_i               : in  std_logic;    -- 50 MHz (c64_clk_sd_i == QNICE clock)
    rst_i               : in  std_logic;

    -----------------------------------------------------------------------------
    -- live controller state (existing physical_1581_controller st_* outputs)
    -----------------------------------------------------------------------------
    st_media_ready_i    : in  std_logic;
    st_index_i          : in  std_logic;
    st_track0_i         : in  std_logic;
    st_wprot_i          : in  std_logic;
    st_change_i         : in  std_logic;    -- sticky disk-change latch
    st_motor_on_i       : in  std_logic;
    st_head_settled_i   : in  std_logic;
    st_locked_i         : in  std_logic;
    st_head_cyl_i       : in  unsigned(7 downto 0);

    -----------------------------------------------------------------------------
    -- read result (levels; latched here on the rd_done toggle) + step handshake
    -----------------------------------------------------------------------------
    rd_done_tgl_i       : in  std_logic;
    rd_result_i         : in  std_logic_vector(4 downto 0);
    rd_crc_err_i        : in  std_logic;
    rd_rnf_i            : in  std_logic;
    rd_deleted_i        : in  std_logic;
    rd_c_i              : in  unsigned(7 downto 0);
    rd_h_i              : in  unsigned(7 downto 0);
    rd_r_i              : in  unsigned(7 downto 0);
    rd_n_i              : in  unsigned(7 downto 0);
    step_ack_tgl_i      : in  std_logic;

    -----------------------------------------------------------------------------
    -- diagnostic observation taps (physical_1581_controller diag_* outputs)
    -----------------------------------------------------------------------------
    diag_in_bits_i      : in  std_logic_vector(15 downto 0);  -- raw + conditioned inputs
    diag_out_bits_i     : in  std_logic_vector(15 downto 0);  -- driven outputs + enable
    diag_index_period_i : in  unsigned(31 downto 0);
    diag_index_width_i  : in  unsigned(31 downto 0);
    diag_last_gap_i     : in  unsigned(15 downto 0);
    diag_calc_crc_i     : in  unsigned(15 downto 0);
    diag_stored_crc_i   : in  unsigned(15 downto 0);
    diag_index_edge_i   : in  std_logic;    -- 1-cycle: every filtered index edge
    diag_index_qual_i   : in  std_logic;    -- 1-cycle: index edge while motor on
    diag_id_valid_i     : in  std_logic;    -- 1-cycle: an ID field was decoded
    diag_id_crc_ok_i    : in  std_logic;
    diag_data_end_i     : in  std_logic;    -- 1-cycle: a data field CRC was checked
    diag_data_crc_ok_i  : in  std_logic;
    diag_gap_error_i    : in  std_logic;    -- 1-cycle: out-of-spec flux gap
    diag_rd_phase_i     : in  std_logic_vector(3 downto 0);
    diag_step_phase_i   : in  std_logic_vector(1 downto 0);
    diag_head_valid_i   : in  std_logic;
    diag_head_dir_out_i : in  std_logic;

    -----------------------------------------------------------------------------
    -- QNICE read interface (device C_DEV_C64_PHYS1581); read-only, no wait-state
    -----------------------------------------------------------------------------
    qnice_ce_i          : in  std_logic;                     -- chip enable (accepted, unused for reads)
    qnice_addr_i        : in  std_logic_vector(7 downto 0);  -- word offset
    qnice_data_o        : out std_logic_vector(15 downto 0)
  );
end entity physical_1581_diag;

architecture rtl of physical_1581_diag is

  ---------------------------------------------------------------------------
  -- register map (16-bit word offsets). Reserved offsets read x"0000".
  ---------------------------------------------------------------------------
  constant RM_SIGNATURE      : integer := 16#00#;   -- x"1581"
  constant RM_VERSION        : integer := 16#01#;   -- map version (hi) / capabilities (lo)
  constant RM_LIVE_IN        : integer := 16#02#;   -- raw + conditioned input levels
  constant RM_LIVE_OUT       : integer := 16#03#;   -- driven mechanism output levels
  constant RM_CTRL_STATE     : integer := 16#04#;   -- state flags + FSM phases
  constant RM_HEAD           : integer := 16#05#;   -- head cyl estimate + valid + dir
  constant RM_LAST_RESULT    : integer := 16#06#;   -- last read result / crc_err / rnf / deleted
  constant RM_CHRN_CR        : integer := 16#07#;   -- found C (hi) / R (lo)
  constant RM_CHRN_HN        : integer := 16#08#;   -- found H (hi) / N (lo)
  constant RM_ID_STORED_CRC  : integer := 16#09#;   -- last decoded ID stored CRC
  constant RM_ID_CALC_CRC    : integer := 16#0A#;   -- last decoded ID CRC residue (0 == good)
  constant RM_DATA_CALC_CRC  : integer := 16#0B#;   -- last decoded data CRC residue (0 == good)
  constant RM_CRC_FLAGS      : integer := 16#0C#;   -- bit0 last id_crc_ok, bit1 last data_crc_ok
  constant RM_IDX_PERIOD_LO  : integer := 16#0D#;
  constant RM_IDX_PERIOD_HI  : integer := 16#0E#;
  constant RM_IDX_WIDTH_LO   : integer := 16#0F#;
  constant RM_IDX_WIDTH_HI   : integer := 16#10#;
  constant RM_GAP_LAST       : integer := 16#11#;   -- last RDATA flux gap (50 MHz cycles)
  constant RM_GAP_MIN        : integer := 16#12#;   -- min observed gap
  constant RM_GAP_MAX        : integer := 16#13#;   -- max observed gap
  constant RM_CNT_IDX_RAW_LO : integer := 16#14#;   -- counter: filtered index leading edges
  constant RM_CNT_IDX_RAW_HI : integer := 16#15#;
  constant RM_CNT_IDX_QUAL_LO: integer := 16#16#;   -- counter: index edges while motor on
  constant RM_CNT_IDX_QUAL_HI: integer := 16#17#;
  constant RM_CNT_STEP_LO    : integer := 16#18#;   -- counter: completed Type-I steps
  constant RM_CNT_STEP_HI    : integer := 16#19#;
  constant RM_CNT_READOP_LO  : integer := 16#1A#;   -- counter: completed read operations
  constant RM_CNT_READOP_HI  : integer := 16#1B#;
  constant RM_CNT_RNF_LO     : integer := 16#1C#;   -- counter: read ops ending RNF
  constant RM_CNT_RNF_HI     : integer := 16#1D#;
  constant RM_CNT_CRCERR_LO  : integer := 16#1E#;   -- counter: read ops ending CRC error
  constant RM_CNT_CRCERR_HI  : integer := 16#1F#;
  constant RM_CNT_CANCEL_LO  : integer := 16#20#;   -- counter: read ops cancelled
  constant RM_CNT_CANCEL_HI  : integer := 16#21#;
  constant RM_CNT_CHANGE_LO  : integer := 16#22#;   -- counter: disk-change latch events
  constant RM_CNT_CHANGE_HI  : integer := 16#23#;
  constant RM_CNT_IDDEC_LO   : integer := 16#24#;   -- counter: decoded ID fields
  constant RM_CNT_IDDEC_HI   : integer := 16#25#;
  constant RM_CNT_GAPERR_LO  : integer := 16#26#;   -- counter: out-of-spec gap events
  constant RM_CNT_GAPERR_HI  : integer := 16#27#;

  constant C_MAP_VERSION : std_logic_vector(7 downto 0) := x"01";
  -- capability flags: bit0 = read-only, bit1 = counters present, bit2 = CRC taps present
  constant C_CAPABILITY  : std_logic_vector(7 downto 0) := x"07";

  constant C_ONES32 : unsigned(31 downto 0) := (others => '1');

  ---------------------------------------------------------------------------
  -- 32-bit saturating event counters
  ---------------------------------------------------------------------------
  signal cnt_idx_raw  : unsigned(31 downto 0) := (others => '0');
  signal cnt_idx_qual : unsigned(31 downto 0) := (others => '0');
  signal cnt_step     : unsigned(31 downto 0) := (others => '0');
  signal cnt_readop   : unsigned(31 downto 0) := (others => '0');
  signal cnt_rnf      : unsigned(31 downto 0) := (others => '0');
  signal cnt_crcerr   : unsigned(31 downto 0) := (others => '0');
  signal cnt_cancel   : unsigned(31 downto 0) := (others => '0');
  signal cnt_change   : unsigned(31 downto 0) := (others => '0');
  signal cnt_iddec    : unsigned(31 downto 0) := (others => '0');
  signal cnt_gaperr   : unsigned(31 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- latched "last" values + edge-detect history
  ---------------------------------------------------------------------------
  signal last_result   : std_logic_vector(4 downto 0) := (others => '0');
  signal last_crc_err  : std_logic := '0';
  signal last_rnf      : std_logic := '0';
  signal last_deleted  : std_logic := '0';
  signal last_c        : unsigned(7 downto 0) := (others => '0');
  signal last_h        : unsigned(7 downto 0) := (others => '0');
  signal last_r        : unsigned(7 downto 0) := (others => '0');
  signal last_n        : unsigned(7 downto 0) := (others => '0');

  signal id_stored_crc : unsigned(15 downto 0) := (others => '0');
  signal id_calc_crc   : unsigned(15 downto 0) := (others => '0');
  signal data_calc_crc : unsigned(15 downto 0) := (others => '0');
  signal last_id_ok    : std_logic := '0';
  signal last_data_ok  : std_logic := '0';

  signal gap_min       : unsigned(15 downto 0) := (others => '1');
  signal gap_max       : unsigned(15 downto 0) := (others => '0');

  signal prev_rd_done  : std_logic := '0';
  signal prev_step_ack : std_logic := '0';
  signal prev_change   : std_logic := '0';

  ---------------------------------------------------------------------------
  -- saturating +1 helper (increments only on 'ev')
  ---------------------------------------------------------------------------
  function sat_inc(v : unsigned(31 downto 0); ev : std_logic) return unsigned is
  begin
    if ev = '1' and v /= C_ONES32 then
      return v + 1;
    else
      return v;
    end if;
  end function;

  function lo16(v : unsigned(31 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(v(15 downto 0));
  end function;

  function hi16(v : unsigned(31 downto 0)) return std_logic_vector is
  begin
    return std_logic_vector(v(31 downto 16));
  end function;

begin

  ---------------------------------------------------------------------------
  -- counters, latches and min/max tracking
  ---------------------------------------------------------------------------
  update_p : process (clk_i)
    variable rddone_evt : std_logic;
    variable step_evt   : std_logic;
    variable change_evt : std_logic;
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        cnt_idx_raw   <= (others => '0');
        cnt_idx_qual  <= (others => '0');
        cnt_step      <= (others => '0');
        cnt_readop    <= (others => '0');
        cnt_rnf       <= (others => '0');
        cnt_crcerr    <= (others => '0');
        cnt_cancel    <= (others => '0');
        cnt_change    <= (others => '0');
        cnt_iddec     <= (others => '0');
        cnt_gaperr    <= (others => '0');
        last_result   <= (others => '0');
        last_crc_err  <= '0';
        last_rnf      <= '0';
        last_deleted  <= '0';
        last_c        <= (others => '0');
        last_h        <= (others => '0');
        last_r        <= (others => '0');
        last_n        <= (others => '0');
        id_stored_crc <= (others => '0');
        id_calc_crc   <= (others => '0');
        data_calc_crc <= (others => '0');
        last_id_ok    <= '0';
        last_data_ok  <= '0';
        gap_min       <= (others => '1');
        gap_max       <= (others => '0');
        prev_rd_done  <= rd_done_tgl_i;
        prev_step_ack <= step_ack_tgl_i;
        prev_change   <= st_change_i;
      else
        -- derived event pulses
        rddone_evt := rd_done_tgl_i  xor prev_rd_done;
        step_evt   := step_ack_tgl_i xor prev_step_ack;
        change_evt := st_change_i and (not prev_change);
        prev_rd_done  <= rd_done_tgl_i;
        prev_step_ack <= step_ack_tgl_i;
        prev_change   <= st_change_i;

        -- saturating counters
        cnt_idx_raw  <= sat_inc(cnt_idx_raw,  diag_index_edge_i);
        cnt_idx_qual <= sat_inc(cnt_idx_qual, diag_index_qual_i);
        cnt_step     <= sat_inc(cnt_step,     step_evt);
        cnt_readop   <= sat_inc(cnt_readop,   rddone_evt);
        cnt_iddec    <= sat_inc(cnt_iddec,    diag_id_valid_i);
        cnt_gaperr   <= sat_inc(cnt_gaperr,   diag_gap_error_i);
        cnt_change   <= sat_inc(cnt_change,   change_evt);
        cnt_rnf      <= sat_inc(cnt_rnf,      rddone_evt and rd_rnf_i);
        cnt_crcerr   <= sat_inc(cnt_crcerr,   rddone_evt and rd_crc_err_i);
        if rddone_evt = '1' and rd_result_i = RES_CANCELLED then
          cnt_cancel <= sat_inc(cnt_cancel, '1');
        end if;

        -- latch the last completed read result + found CHRN
        if rddone_evt = '1' then
          last_result  <= rd_result_i;
          last_crc_err <= rd_crc_err_i;
          last_rnf     <= rd_rnf_i;
          last_deleted <= rd_deleted_i;
          last_c       <= rd_c_i;
          last_h       <= rd_h_i;
          last_r       <= rd_r_i;
          last_n       <= rd_n_i;
        end if;

        -- latch CRCs on the decoder's field-complete pulses
        if diag_id_valid_i = '1' then
          id_stored_crc <= diag_stored_crc_i;
          id_calc_crc   <= diag_calc_crc_i;
          last_id_ok    <= diag_id_crc_ok_i;
        end if;
        if diag_data_end_i = '1' then
          data_calc_crc <= diag_calc_crc_i;
          last_data_ok  <= diag_data_crc_ok_i;
        end if;

        -- last / min / max RDATA gap (fold only over meaningful, non-zero gaps)
        if diag_last_gap_i /= x"0000" then
          if diag_last_gap_i < gap_min then
            gap_min <= diag_last_gap_i;
          end if;
          if diag_last_gap_i > gap_max then
            gap_max <= diag_last_gap_i;
          end if;
        end if;
      end if;
    end if;
  end process update_p;

  ---------------------------------------------------------------------------
  -- combinational read mux (no wait-state). Writes are ignored.
  ---------------------------------------------------------------------------
  read_p : process (all)
    variable a : integer;
  begin
    a := to_integer(unsigned(qnice_addr_i));
    case a is
      when RM_SIGNATURE       => qnice_data_o <= x"1581";
      when RM_VERSION         => qnice_data_o <= C_MAP_VERSION & C_CAPABILITY;

      when RM_LIVE_IN         => qnice_data_o <= diag_in_bits_i;
      when RM_LIVE_OUT        => qnice_data_o <= diag_out_bits_i;

      when RM_CTRL_STATE      =>
        qnice_data_o <= diag_rd_phase_i           -- bits 15..12
                      & diag_step_phase_i         -- bits 11..10
                      & st_wprot_i                -- bit  9
                      & st_track0_i               -- bit  8
                      & st_index_i                -- bit  7
                      & diag_out_bits_i(6)        -- bit  6 = phys_active (enable)
                      & diag_head_valid_i         -- bit  5
                      & st_change_i               -- bit  4
                      & st_motor_on_i             -- bit  3
                      & st_locked_i               -- bit  2
                      & st_head_settled_i         -- bit  1
                      & st_media_ready_i;         -- bit  0

      when RM_HEAD            =>
        qnice_data_o <= "00000" & st_track0_i & diag_head_dir_out_i & diag_head_valid_i
                      & std_logic_vector(st_head_cyl_i);

      when RM_LAST_RESULT     =>
        qnice_data_o <= x"00" & last_deleted & last_rnf & last_crc_err & last_result;

      when RM_CHRN_CR         => qnice_data_o <= std_logic_vector(last_c) & std_logic_vector(last_r);
      when RM_CHRN_HN         => qnice_data_o <= std_logic_vector(last_h) & std_logic_vector(last_n);
      when RM_ID_STORED_CRC   => qnice_data_o <= std_logic_vector(id_stored_crc);
      when RM_ID_CALC_CRC     => qnice_data_o <= std_logic_vector(id_calc_crc);
      when RM_DATA_CALC_CRC   => qnice_data_o <= std_logic_vector(data_calc_crc);
      when RM_CRC_FLAGS       => qnice_data_o <= x"000" & "00" & last_data_ok & last_id_ok;

      when RM_IDX_PERIOD_LO   => qnice_data_o <= std_logic_vector(diag_index_period_i(15 downto 0));
      when RM_IDX_PERIOD_HI   => qnice_data_o <= std_logic_vector(diag_index_period_i(31 downto 16));
      when RM_IDX_WIDTH_LO    => qnice_data_o <= std_logic_vector(diag_index_width_i(15 downto 0));
      when RM_IDX_WIDTH_HI    => qnice_data_o <= std_logic_vector(diag_index_width_i(31 downto 16));

      when RM_GAP_LAST        => qnice_data_o <= std_logic_vector(diag_last_gap_i);
      when RM_GAP_MIN         => qnice_data_o <= std_logic_vector(gap_min);
      when RM_GAP_MAX         => qnice_data_o <= std_logic_vector(gap_max);

      when RM_CNT_IDX_RAW_LO  => qnice_data_o <= lo16(cnt_idx_raw);
      when RM_CNT_IDX_RAW_HI  => qnice_data_o <= hi16(cnt_idx_raw);
      when RM_CNT_IDX_QUAL_LO => qnice_data_o <= lo16(cnt_idx_qual);
      when RM_CNT_IDX_QUAL_HI => qnice_data_o <= hi16(cnt_idx_qual);
      when RM_CNT_STEP_LO     => qnice_data_o <= lo16(cnt_step);
      when RM_CNT_STEP_HI     => qnice_data_o <= hi16(cnt_step);
      when RM_CNT_READOP_LO   => qnice_data_o <= lo16(cnt_readop);
      when RM_CNT_READOP_HI   => qnice_data_o <= hi16(cnt_readop);
      when RM_CNT_RNF_LO      => qnice_data_o <= lo16(cnt_rnf);
      when RM_CNT_RNF_HI      => qnice_data_o <= hi16(cnt_rnf);
      when RM_CNT_CRCERR_LO   => qnice_data_o <= lo16(cnt_crcerr);
      when RM_CNT_CRCERR_HI   => qnice_data_o <= hi16(cnt_crcerr);
      when RM_CNT_CANCEL_LO   => qnice_data_o <= lo16(cnt_cancel);
      when RM_CNT_CANCEL_HI   => qnice_data_o <= hi16(cnt_cancel);
      when RM_CNT_CHANGE_LO   => qnice_data_o <= lo16(cnt_change);
      when RM_CNT_CHANGE_HI   => qnice_data_o <= hi16(cnt_change);
      when RM_CNT_IDDEC_LO    => qnice_data_o <= lo16(cnt_iddec);
      when RM_CNT_IDDEC_HI    => qnice_data_o <= hi16(cnt_iddec);
      when RM_CNT_GAPERR_LO   => qnice_data_o <= lo16(cnt_gaperr);
      when RM_CNT_GAPERR_HI   => qnice_data_o <= hi16(cnt_gaperr);

      when others             => qnice_data_o <= x"0000";
    end case;
  end process read_p;

end architecture rtl;
