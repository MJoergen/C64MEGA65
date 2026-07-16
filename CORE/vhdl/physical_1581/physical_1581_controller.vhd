-------------------------------------------------------------------------------
-- physical_1581_controller.vhd
--
-- Operation + mechanics FSM for the physical internal 1581 (read-only milestone),
-- on the 50 MHz controller clock. Instantiates the input conditioner and the
-- DD-MFM decoder, drives the mechanism outputs (motor/select/side/step/dir/
-- density), synthesizes media-ready / index / track0 / write-protect / disk-change
-- state, and services three drive-domain request classes over a toggle-handshake
-- ABI:
--   * one acknowledged Type-I STEP (DIR setup, 4 us pulse, recovery, 18 ms settle)
--   * a read operation: Read Sector / Verify / Read Address
--   * a cancel/force
-- Decoded payload bytes are pushed to an external dual-clock read FIFO
-- (physical_1581_rdfifo). The FIFO quarantines one complete sector; the WD
-- front end releases it at DRQ cadence only after this controller reports a
-- clean field CRC, or drains it unseen when this controller reports an error.
--
-- Writes are NOT part of this milestone: f_wgate/f_wdata are never driven here and
-- stay tied inactive at the top level.
--
-- All timing is generic (spec initial values as defaults) so testbenches scale.
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_controller is
  generic (
    G_CAPABLE         : boolean := true;
    -- mechanism/magnetic timing in 50 MHz cycles (production defaults)
    G_READY_WD_CYC    : natural := 55_000_000;  -- 1.10 s
    G_DIR_SETUP_CYC   : natural := 1_200;       -- 24 us
    G_STEP_LOW_CYC    : natural := 200;         -- 4 us
    G_STEP_REC_CYC    : natural := 150_000;     -- 3 ms same-direction
    G_STEP_REV_CYC    : natural := 200_000;     -- 4 ms reversal
    G_SETTLE_CYC      : natural := 900_000;     -- 18 ms final head settle
    G_SIDE_SETTLE_CYC : natural := 5_000;       -- 100 us
    G_DAM_TIMEOUT_CYC : natural := 68_800;      -- 43 decoded byte-times
    G_SEARCH_WD_CYC   : natural := 65_000_000;  -- 1.300 s absolute search watchdog
    G_SEARCH_EDGES    : natural := 5;           -- index-edge search budget
    G_PERIOD_MAX_CYC  : natural := 12_500_000   -- 250 ms (index-staleness eject bound)
  );
  port (
    clk_i            : in  std_logic;            -- 50 MHz (c64_clk_sd_i)
    rst_i            : in  std_logic;

    -- physical mechanism pins
    f_rdata_i        : in  std_logic;
    f_index_i        : in  std_logic;
    f_track0_i       : in  std_logic;
    f_writeprotect_i : in  std_logic;
    f_diskchanged_i  : in  std_logic;
    f_motora_o       : out std_logic := '1';
    f_selecta_o      : out std_logic := '1';
    f_side1_o        : out std_logic := '1';
    f_stepdir_o      : out std_logic := '1';
    f_step_o         : out std_logic := '1';
    f_density_o      : out std_logic := '1';

    -- mode + maintained mechanics requests (from drive domain; synced here)
    phys_active_i    : in  std_logic;
    cia_motor_on_i   : in  std_logic;            -- PA2 positive: '1' = motor on requested
    cia_side_i       : in  std_logic;            -- ~PA0 (fdc1772 floppy_side): '1' = logical side 0 (D81 first half), '0' = logical side 1

    -- Type-I step request (toggle handshake)
    step_req_tgl_i   : in  std_logic;
    step_outward_i   : in  std_logic;            -- '1' = toward track 0
    step_ack_tgl_o   : out std_logic := '0';

    -- read operation request (toggle handshake). rd_seq_i is the request
    -- sequence tag (fdc1772 phys_rd_seq): quasi-static alongside op/track/
    -- sector/side from before the rd_req toggle until the next toggle. The
    -- accepted tag is registered onto rd_done_seq_o on the same cycle as each
    -- rd_done toggle and held until the next one, so it is stable for the
    -- whole inter-done interval; the WD front end ignores a done whose tag
    -- does not match its current operation.
    rd_req_tgl_i     : in  std_logic;
    rd_op_i          : in  std_logic_vector(2 downto 0);  -- RDOP_*
    rd_track_i       : in  unsigned(7 downto 0);
    rd_side_i        : in  std_logic;
    rd_sector_i      : in  unsigned(7 downto 0);
    rd_seq_i         : in  std_logic_vector(1 downto 0) := "00";
    rd_cancel_tgl_i  : in  std_logic;
    rd_done_tgl_o    : out std_logic := '0';
    rd_done_seq_o    : out std_logic_vector(1 downto 0) := "00";
    rd_result_o      : out std_logic_vector(4 downto 0) := RES_OK;
    rd_crc_err_o     : out std_logic := '0';
    rd_rnf_o         : out std_logic := '0';
    rd_deleted_o     : out std_logic := '0';
    rd_c_o           : out unsigned(7 downto 0) := (others => '0');
    rd_h_o           : out unsigned(7 downto 0) := (others => '0');
    rd_r_o           : out unsigned(7 downto 0) := (others => '0');
    rd_n_o           : out unsigned(7 downto 0) := (others => '0');

    -- read-byte stream to the external dual-clock FIFO (50 MHz write side)
    byte_data_o      : out unsigned(7 downto 0) := (others => '0');
    byte_wr_o        : out std_logic := '0';
    byte_ovf_i       : in  std_logic := '0';     -- FIFO full: a write this cycle is DROPPED

    -- live normalized state to the drive domain
    st_media_ready_o : out std_logic := '0';
    st_index_o       : out std_logic := '0';
    st_track0_o      : out std_logic := '0';
    st_wprot_o       : out std_logic := '0';
    st_change_o      : out std_logic := '0';
    st_motor_on_o    : out std_logic := '0';
    st_head_settled_o: out std_logic := '0';
    st_head_cyl_o    : out unsigned(7 downto 0) := (others => '0');  -- diagnostic estimate
    st_locked_o      : out std_logic := '0';

    -------------------------------------------------------------------------
    -- READ-ONLY diagnostics for physical_1581_diag (issue #90).
    --
    -- Every port below is a PURELY ADDITIVE observation tap: it mirrors an
    -- internal signal out to the diagnostic register bank and is never read
    -- back into any behavior. The FSM/timing above is untouched. All of these
    -- live in the same 50 MHz (c64_clk_sd_i == QNICE) clock domain as the
    -- diag bank, so no CDC is needed.
    -------------------------------------------------------------------------
    -- index measurement (forwarded from physical_1581_inputs)
    diag_index_period_o : out unsigned(31 downto 0) := (others => '0');
    diag_index_width_o  : out unsigned(31 downto 0) := (others => '0');
    diag_index_edge_o   : out std_logic := '0';   -- 1-cycle pulse: every filtered index leading edge
    diag_index_qual_o   : out std_logic := '0';   -- 1-cycle pulse: index leading edge while motor on
    -- MFM decoder observation
    diag_last_gap_o     : out unsigned(15 downto 0) := (others => '0');
    diag_calc_crc_o     : out unsigned(15 downto 0) := (others => '0');  -- live CRC residue
    diag_stored_crc_o   : out unsigned(15 downto 0) := (others => '0');  -- last decoded ID stored CRC
    diag_id_valid_o     : out std_logic := '0';   -- 1-cycle pulse: an ID field was decoded
    diag_id_crc_ok_o    : out std_logic := '0';   -- valid at diag_id_valid_o
    diag_data_end_o     : out std_logic := '0';   -- 1-cycle pulse: a data field CRC was checked
    diag_data_crc_ok_o  : out std_logic := '0';   -- valid at diag_data_end_o
    diag_gap_error_o    : out std_logic := '0';   -- 1-cycle pulse: out-of-spec flux gap
    diag_runt_o         : out std_logic := '0';   -- 1-cycle pulse: merged RDATA runt gap
    diag_a1_candidate_o : out std_logic := '0';   -- 1-cycle pulse: coarse A1 candidate
    diag_a1_reject_o    : out std_logic := '0';   -- 1-cycle pulse: bad complete-word span
    diag_a1_train_o     : out std_logic := '0';   -- 1-cycle pulse: qualified 3xA1 train
    diag_mark_fe_o      : out std_logic := '0';   -- 1-cycle pulse: qualified FE mark
    diag_mark_dam_o     : out std_logic := '0';   -- 1-cycle pulse: qualified FB/F8 mark
    diag_dam_unarmed_o  : out std_logic := '0';   -- pulse: DAM ignored (no ID/data lock-up)
    diag_match_id_o     : out std_logic := '0';   -- 1-cycle pulse: requested sector ID matched
    diag_dam_miss_o     : out std_logic := '0';   -- 1-cycle pulse: matched ID had no DAM
    -- adaptive quantiser half-cell estimate (Q8.4; issue #90 round 12)
    diag_est_o          : out unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12);
    -- FSM phases + head estimate
    diag_rd_phase_o     : out std_logic_vector(3 downto 0) := (others => '0');  -- read FSM state code
    diag_step_phase_o   : out std_logic_vector(1 downto 0) := (others => '0');  -- step FSM state code
    diag_head_valid_o   : out std_logic := '0';   -- head cylinder estimate anchored (saw track0)
    diag_head_dir_out_o : out std_logic := '1';   -- last step direction (1 = outward / toward track0)
    -- WD-dialogue trace taps (issue #90 bring-up): a 1-cycle strobe when a read
    -- request is accepted plus the latched request parameters, so the diag bank
    -- can record the exact operation sequence the 1581 DOS issues.
    diag_rd_req_o        : out std_logic := '0';
    diag_rd_req_op_o     : out std_logic_vector(2 downto 0) := (others => '0');
    diag_rd_req_track_o  : out unsigned(7 downto 0) := (others => '0');
    diag_rd_req_sector_o : out unsigned(7 downto 0) := (others => '0');
    diag_rd_req_side_o   : out std_logic := '0';
    -- packed live pin levels: raw async inputs + conditioned inputs (layout in physical_1581_diag.vhd)
    diag_in_bits_o      : out std_logic_vector(15 downto 0) := (others => '0');
    -- packed driven mechanism outputs + enable (layout in physical_1581_diag.vhd)
    diag_out_bits_o     : out std_logic_vector(15 downto 0) := (others => '0')
  );
end entity physical_1581_controller;

architecture rtl of physical_1581_controller is

  -- conditioned inputs
  signal rdata_sync   : std_logic;
  signal index_edge   : std_logic;
  signal index_active : std_logic;
  signal index_period : unsigned(31 downto 0);
  signal index_width  : unsigned(31 downto 0);
  signal track0_c     : std_logic;
  signal wprot_c      : std_logic;
  signal change_c     : std_logic;

  -- decoder record stream
  signal dec_rst        : std_logic := '0';
  signal id_valid       : std_logic;
  signal id_c, id_h, id_r, id_n : unsigned(7 downto 0);
  signal id_crc_ok      : std_logic;
  signal id_crc_stored  : unsigned(15 downto 0);
  signal data_start     : std_logic;
  signal data_deleted   : std_logic;
  signal data_byte      : unsigned(7 downto 0);
  signal data_byte_v    : std_logic;
  signal data_end       : std_logic;
  signal data_crc_ok    : std_logic;
  signal dec_locked     : std_logic;
  signal dec_gap_err    : std_logic;
  signal dec_runt       : std_logic;
  signal dec_last_gap   : unsigned(15 downto 0);
  signal dec_crc_value  : unsigned(15 downto 0);   -- diag tap: live CRC residue
  signal dec_est        : unsigned(11 downto 0);   -- diag tap: quantiser half-cell estimate (Q8.4)

  -- 2FF synchronizers for level inputs
  signal active_m, active_s : std_logic := '0';
  signal motor_m,  motor_s  : std_logic := '0';
  signal side_m,   side_s   : std_logic := '0';
  attribute async_reg : string;
  attribute async_reg of active_m : signal is "true";
  attribute async_reg of motor_m  : signal is "true";
  attribute async_reg of side_m   : signal is "true";

  -- 2FF + edge for toggle requests
  signal stq_m, stq_s, stq_d : std_logic := '0';
  signal rdq_m, rdq_s, rdq_d : std_logic := '0';
  signal cnq_m, cnq_s, cnq_d : std_logic := '0';
  attribute async_reg of stq_m : signal is "true";
  attribute async_reg of rdq_m : signal is "true";
  attribute async_reg of cnq_m : signal is "true";

  -- gating
  signal en : std_logic;   -- capable AND active

  -- maintained state
  signal side_prev     : std_logic := '0';
  signal side_settle   : unsigned(31 downto 0) := (others => '0');
  signal idx_motor_cnt : integer range 0 to 7 := 0;
  signal idx_gap_cnt   : unsigned(31 downto 0) := (others => '0');  -- cycles since the last index edge (motor on)
  signal media_ready   : std_logic := '0';
  -- Sticky proof that this same, unchanged medium previously completed a
  -- two-index rotation qualification.  Preserve it across ordinary motor-off
  -- intervals so a restart may assert RDY after the first fresh index; clear
  -- it on reset/disable, raw disk change, or index staleness while commanded
  -- on.  This closes the stock 1581 ROM's finite PA1 spin-up window without
  -- weakening cold-start/eject qualification.
  signal rotation_confirmed : std_logic := '0';
  signal change_latched: std_logic := '0';
  signal motor_on_act  : std_logic := '0';

  -- head position estimate (diagnostic/safety-lite)
  signal head_cyl      : integer range 0 to 255 := 0;
  signal head_valid    : std_logic := '0';
  signal last_dir_out  : std_logic := '1';   -- 1 = outward
  signal last_dir_vld  : std_logic := '0';

  -- step engine
  type step_st_t is (SI_IDLE, SI_SETUP, SI_LOW, SI_REC);
  signal step_st    : step_st_t := SI_IDLE;
  signal step_cnt   : unsigned(31 downto 0) := (others => '0');
  signal step_dir_o     : std_logic := '1';   -- latched outward direction for the pulse
  signal step_dir_pulse : std_logic := '1';   -- STEP output level (active-low pulse)
  signal step_rev   : std_logic := '0';
  signal settle_cnt : unsigned(31 downto 0) := (others => '0');
  signal head_settled : std_logic := '1';   -- at rest = settled; cleared on step acceptance

  -- read engine
  type rd_st_t is (RD_IDLE, RD_WAIT, RD_SEARCH, RD_DAM, RD_STREAM, RD_ADDR);
  signal rd_st      : rd_st_t := RD_IDLE;
  signal op_r       : std_logic_vector(2 downto 0) := (others => '0');
  signal trk_r      : unsigned(7 downto 0) := (others => '0');
  signal sec_r      : unsigned(7 downto 0) := (others => '0');
  signal seq_r      : std_logic_vector(1 downto 0) := "00";  -- accepted request sequence tag

  -- round 10 hardening (F4): rd_done_seq_o is a register written ONLY on the
  -- cycles that toggle rd_done_tgl_o (capturing seq_r of the op being
  -- completed, in the main process, exactly like rd_result_o and the flag
  -- outputs), so the tag is stable for the whole inter-done interval BY
  -- CONSTRUCTION -- even when a pending request is served (and seq_r
  -- reloaded) one cycle after an abort's done toggle.

  -- round 10 hardening (F5): minimum spacing between rd_done toggles. An
  -- abort-done followed by serving a pending request that immediately aborts
  -- again (persistent change_c) could otherwise produce two done toggles two
  -- source cycles apart, which the fdc-side two-sample agreement synchronizer
  -- can swallow entirely. The down-counter is armed at every done toggle;
  -- while it is nonzero, RD_IDLE neither serves a pending request nor accepts
  -- a live one into an abortable state (a live edge is latched as pending
  -- instead, so it cannot be lost). Strictly decrementing -> always terminates.
  -- At the enforced minimum spacing the fdc side may attribute the first done
  -- to the newer tag (its done-edge delay and the independently synced tag bus
  -- can overlap) -- harmless, because minimum-spaced dones only arise from
  -- back-to-back aborts carrying identical flags. Re-derive this argument
  -- before cloning the done handshake for the write milestone.
  constant C_DONE_GAP   : natural := 8;
  signal   done_gap_cnt : natural range 0 to C_DONE_GAP := 0;

  -- pending-request latch (issue #90 round 10, delivery v2 C2): a rd_req toggle
  -- arriving while the read FSM is busy used to be LOST FOREVER -- the old op's
  -- done and bytes then paired with the new WD command, delivering stale data
  -- with clean status (the audit's one silent desync channel). Now such an edge
  -- is latched here with its parameters resampled at the edge (they are
  -- quasi-static until the NEXT toggle, so this is race-free); the latest edge
  -- wins, a cancel edge clears the latch, and RD_IDLE serves it immediately.
  signal pend_v     : std_logic := '0';
  signal pend_op    : std_logic_vector(2 downto 0) := (others => '0');
  signal pend_trk   : unsigned(7 downto 0) := (others => '0');
  signal pend_sec   : unsigned(7 downto 0) := (others => '0');
  signal pend_seq   : std_logic_vector(1 downto 0) := "00";
  signal wd_cnt     : unsigned(31 downto 0) := (others => '0');  -- absolute search watchdog
  signal rdy_wd_cnt : unsigned(31 downto 0) := (others => '0');  -- readiness watchdog
  signal dam_cnt    : unsigned(31 downto 0) := (others => '0');
  signal edge_cnt   : integer range 0 to 15 := 0;
  signal saw_bad_crc: std_logic := '0';
  signal m_c, m_h, m_r, m_n : unsigned(7 downto 0) := (others => '0');
  signal addr_idx   : integer range 0 to 5 := 0;
  signal deleted_l  : std_logic := '0';
  signal ovf_l      : std_logic := '0';   -- a FIFO write was dropped during this op
  signal rd_req_evt : std_logic := '0';   -- 1-cycle diag strobe: read request accepted
  signal dec_a1_candidate, dec_a1_reject, dec_a1_train : std_logic;
  signal dec_mark_fe, dec_mark_dam, dec_dam_unarmed : std_logic;

begin

  en <= '1' when (G_CAPABLE and active_s = '1') else '0';

  ---------------------------------------------------------------------------
  -- input conditioner + decoder
  ---------------------------------------------------------------------------
  i_inputs : entity work.physical_1581_inputs
    port map (
      clk_i => clk_i, rst_i => rst_i,
      f_index_i => f_index_i, f_track0_i => f_track0_i,
      f_writeprotect_i => f_writeprotect_i, f_diskchanged_i => f_diskchanged_i,
      f_rdata_i => f_rdata_i,
      rdata_sync_o => rdata_sync, index_active_o => index_active,
      index_edge_o => index_edge, index_period_o => index_period,
      index_width_o => index_width, track0_o => track0_c,
      wprot_o => wprot_c, change_o => change_c
    );

  i_dec : entity work.physical_1581_mfm_decoder
    port map (
      clk_i => clk_i, rst_i => dec_rst, f_rdata_i => rdata_sync,
      id_valid_o => id_valid, id_c_o => id_c, id_h_o => id_h, id_r_o => id_r,
      id_n_o => id_n, id_crc_ok_o => id_crc_ok, id_crc_stored_o => id_crc_stored,
      data_start_o => data_start, data_deleted_o => data_deleted,
      data_byte_o => data_byte, data_byte_valid_o => data_byte_v,
      data_end_o => data_end, data_crc_ok_o => data_crc_ok,
      locked_o => dec_locked, gap_error_o => dec_gap_err, runt_o => dec_runt,
      a1_candidate_o => dec_a1_candidate,
      a1_span_reject_o => dec_a1_reject,
      a1_train_o => dec_a1_train,
      mark_fe_o => dec_mark_fe,
      mark_dam_o => dec_mark_dam,
      dam_unarmed_o => dec_dam_unarmed,
      last_gap_o => dec_last_gap,
      crc_value_o => dec_crc_value,
      est_o => dec_est
    );

  ---------------------------------------------------------------------------
  -- physical output drivers (combinational from maintained state)
  ---------------------------------------------------------------------------
  f_selecta_o <= '0' when en = '1' else '1';
  f_motora_o  <= '0' when (en = '1' and motor_s = '1') else '1';
  -- SIDE mapping (issue #90 bring-up, determined EMPIRICALLY from the medium):
  -- on a MEGA65-written 1581 disk the surface selected by f_side1='0' carries
  -- the sector IDs with H=0 -- the D81 first half (header/BAM/directory,
  -- logical sectors 0-19) -- and the f_side1='1' surface carries H=1 (observed
  -- directly via the diag CHRN taps across bring-up rounds: pin '0' -> H=0,
  -- pin '1' -> H=1, same disk). The 1581 DOS requests its logical side 0 with
  -- PA0=0, which arrives here as side_s='1' (fdc1772 floppy_side = ~PA0), so
  -- logical side 0 must drive the pin LOW: f_side1_o = not side_s = PA0. This
  -- mirrors the original 1581, which wires PA0 straight to the mechanism SIDE
  -- line. (Do NOT re-derive this from the F011 register model in mega65-core:
  -- the C65 DOS sets the side REGISTER and the side PIN bit independently
  -- during format, which misleads -- it did once already.)
  f_side1_o   <= (not side_s) when en = '1' else '1';
  f_density_o <= '1';                                    -- DD-safe level
  f_step_o    <= step_dir_pulse when en = '1' else '1';  -- driven by step FSM (see process)
  f_stepdir_o <= step_dir_o when en = '1' else '1';

  -- live state
  st_media_ready_o <= media_ready;
  st_index_o       <= index_active;
  st_track0_o      <= track0_c;
  st_wprot_o       <= wprot_c;
  st_change_o      <= change_latched;
  st_motor_on_o    <= motor_on_act;
  st_head_settled_o<= head_settled;
  st_head_cyl_o    <= to_unsigned(head_cyl, 8);
  st_locked_o      <= dec_locked;

  -- C3 (delivery v2) + round 10 F4: rd_done_seq_o is registered in the main
  -- process, ONLY on the cycles that toggle rd_done_tgl_o (capturing seq_r of
  -- the op being completed), so it holds the completing op's tag for the
  -- whole inter-done interval -- including aborts followed by an
  -- immediately-served pending request. No concurrent assignment here.

  ---------------------------------------------------------------------------
  -- READ-ONLY diagnostic taps (issue #90; purely additive; no behavior change)
  ---------------------------------------------------------------------------
  diag_index_period_o <= index_period;
  diag_index_width_o  <= index_width;
  diag_index_edge_o   <= index_edge;
  diag_index_qual_o   <= index_edge and motor_on_act;   -- edges counted while motor is on
  diag_last_gap_o     <= dec_last_gap;
  diag_calc_crc_o     <= dec_crc_value;
  diag_stored_crc_o   <= id_crc_stored;
  diag_id_valid_o     <= id_valid;
  diag_id_crc_ok_o    <= id_crc_ok;
  diag_data_end_o     <= data_end;
  diag_data_crc_ok_o  <= data_crc_ok;
  diag_gap_error_o    <= dec_gap_err;
  diag_runt_o         <= dec_runt;
  diag_a1_candidate_o <= dec_a1_candidate;
  diag_a1_reject_o    <= dec_a1_reject;
  diag_a1_train_o     <= dec_a1_train;
  diag_mark_fe_o      <= dec_mark_fe;
  diag_mark_dam_o     <= dec_mark_dam;
  diag_dam_unarmed_o  <= dec_dam_unarmed;
  diag_est_o          <= dec_est;
  diag_head_valid_o   <= head_valid;
  diag_head_dir_out_o <= last_dir_out;

  -- WD-dialogue trace taps: op_r/trk_r/sec_r latch on the same clock edge that
  -- sets the (registered) rd_req_evt strobe, so they are stable in the cycle
  -- the diag bank sees the pulse.
  diag_rd_req_o        <= rd_req_evt;
  diag_rd_req_op_o     <= op_r;
  diag_rd_req_track_o  <= trk_r;
  diag_rd_req_sector_o <= sec_r;
  diag_rd_req_side_o   <= side_s;

  -- read FSM state -> 4-bit phase code (see physical_1581_diag.vhd register map)
  with rd_st select diag_rd_phase_o <=
    "0000" when RD_IDLE,
    "0001" when RD_WAIT,
    "0010" when RD_SEARCH,
    "0011" when RD_DAM,
    "0100" when RD_STREAM,
    "0101" when RD_ADDR;

  -- step FSM state -> 2-bit phase code
  with step_st select diag_step_phase_o <=
    "00" when SI_IDLE,
    "01" when SI_SETUP,
    "10" when SI_LOW,
    "11" when SI_REC;

  -- packed raw async connector inputs (bits 4:0) + conditioned levels (bits 9:5)
  diag_in_bits_o <= ( 0 => f_rdata_i,        1 => f_index_i,     2 => f_track0_i,
                      3 => f_writeprotect_i, 4 => f_diskchanged_i,
                      5 => rdata_sync,       6 => index_active,  7 => track0_c,
                      8 => wprot_c,          9 => change_c,
                      others => '0' );

  -- packed driven mechanism output levels (bits 5:0, active-low at the pin) + enable (bit 6)
  diag_out_bits_o <= ( 0 => f_motora_o, 1 => f_selecta_o, 2 => f_side1_o,
                       3 => f_stepdir_o, 4 => f_step_o,   5 => f_density_o,
                       6 => en,
                       others => '0' );

  ---------------------------------------------------------------------------
  -- synchronizers
  ---------------------------------------------------------------------------
  sync_p : process (clk_i)
  begin
    if rising_edge(clk_i) then
      active_m <= phys_active_i;  active_s <= active_m;
      motor_m  <= cia_motor_on_i; motor_s  <= motor_m;
      side_m   <= cia_side_i;     side_s   <= side_m;
      stq_m <= step_req_tgl_i;  stq_s <= stq_m;  stq_d <= stq_s;
      rdq_m <= rd_req_tgl_i;    rdq_s <= rdq_m;  rdq_d <= rdq_s;
      cnq_m <= rd_cancel_tgl_i; cnq_s <= cnq_m;  cnq_d <= cnq_s;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- main FSM
  ---------------------------------------------------------------------------
  main_p : process (clk_i)
    variable step_req_edge   : boolean;
    variable rd_req_edge     : boolean;
    variable cancel_edge     : boolean;
    variable side_changed    : boolean;
  begin
    if rising_edge(clk_i) then
      -- default strobes
      dec_rst  <= '0';
      byte_wr_o <= '0';
      rd_req_evt <= '0';
      diag_match_id_o <= '0';
      diag_dam_miss_o <= '0';

      step_req_edge := (stq_s /= stq_d);
      rd_req_edge   := (rdq_s /= rdq_d);
      cancel_edge   := (cnq_s /= cnq_d);
      side_changed  := (side_s /= side_prev);
      side_prev     <= side_s;

      -- a write strobe while the FIFO reports full means that byte was DROPPED:
      -- remember it so the operation cannot complete "successfully" with a
      -- silently truncated stream (real WD1772: LOST DATA -> the DOS re-reads)
      if byte_wr_o = '1' and byte_ovf_i = '1' then
        ovf_l <= '1';
      end if;

      if rst_i = '1' or en = '0' then
        -- inactive / reset: mechanics safe, state cleared (media presence pending).
        -- KNOWN ACCEPTED HOLE (delivery v2 C5): a QNICE-domain-only reset (rst_i
        -- without the accompanying core reset) mid-operation idles this FSM
        -- WITHOUT toggling rd_done, so the WD front end would wait forever. In
        -- M2M the QNICE reset never occurs without the core reset, which clears
        -- the fdc1772 via floppy_reset -- so the pairing cannot desynchronize in
        -- practice. Documented, not fixed (would need a reset-crossing done).
        step_st       <= SI_IDLE;
        step_dir_pulse <= '1';
        rd_st         <= RD_IDLE;
        pend_v        <= '0';
        done_gap_cnt  <= 0;
        idx_motor_cnt <= 0;
        idx_gap_cnt   <= (others => '0');
        media_ready   <= '0';
        rotation_confirmed <= '0';
        motor_on_act  <= '0';
        -- The head is at rest while we are inactive, so it IS settled: the settle
        -- timer only guards reads against a just-finished step. Starting at '0'
        -- would wedge the WD front end after (re-)enable whenever a Type-I verify
        -- needs zero steps (e.g. Restore with the head already on track 0), because
        -- only a step ever sets head_settled.
        head_settled  <= '1';
        settle_cnt    <= (others => '0');
        side_settle   <= (others => '0');
        -- Re-arm the conservative disk-change latch on reset AND on plain disable:
        -- while the controller is disabled, drive 8 is served from a disk image, so
        -- the medium after a re-enable is never proven to be the one seen before.
        -- The 1581 DOS then revalidates (a step with media present clears the latch),
        -- exactly as after power-up. This makes an image->internal source switch
        -- present as a disk change instead of a silent media swap.
        change_latched <= '1';
        if rst_i = '1' then
          head_valid     <= '0';
          last_dir_vld   <= '0';
          head_cyl       <= 0;
        end if;
      else
        ------------------------------------------------------------------
        -- disk-change sticky latch
        ------------------------------------------------------------------
        if change_c = '1' then
          change_latched <= '1';
          rotation_confirmed <= '0';
        end if;

        ------------------------------------------------------------------
        -- side settle timer + decoder invalidate on side change
        ------------------------------------------------------------------
        if side_changed then
          side_settle <= to_unsigned(G_SIDE_SETTLE_CYC, 32);
          dec_rst     <= '1';
        elsif side_settle /= 0 then
          side_settle <= side_settle - 1;
        end if;

        ------------------------------------------------------------------
        -- motor / readiness
        --
        -- media_ready models the REAL Chinon FB-354 RDY line of an original
        -- 1581: it asserts when the motor has been on long enough AND real
        -- index pulses prove a disk is turning at a plausible speed. It is
        -- deliberately INDEPENDENT of the disk-change latch: on the original
        -- mechanism RDY and /DSKCHG are separate signals, and the stock 1581
        -- ROM waits for RDY (CIA PA1) BEFORE it runs the disk job whose seek
        -- steps would clear the change latch. Gating RDY on the change latch
        -- therefore deadlocks the ROM (head already at track 0 -> Restore
        -- steps zero times -> latch never clears -> RDY never -> the DOS
        -- times out without ever touching the WD). The change latch guards
        -- data validity through CIA PA7 and the read-engine abort instead;
        -- disk removal is caught here by the loss of index pulses.
        ------------------------------------------------------------------
        motor_on_act <= motor_s;

        -- Cold/new media still requires two index edges.  Once two edges have
        -- confirmed a medium and no /DSKCHG assertion has occurred since, a
        -- later motor restart may reassert RDY after its first fresh edge.
        -- Hardware A/B proved why: the stock ROM's finite PA1 window can expire
        -- before a worst-phase second edge, while an immediate warm command
        -- succeeds.  Saving one revolution only for unchanged media preserves
        -- eject/reinsert safety; the raw change and staleness paths below clear
        -- the history.  Speed correctness remains a decode/CRC concern.
        if motor_s = '1' and
           (idx_motor_cnt >= 2 or
            (rotation_confirmed = '1' and change_latched = '0' and
             idx_motor_cnt >= 1)) then
          media_ready <= '1';
        end if;

        -- qualification counters + index-staleness eject detection. These come
        -- AFTER the assert above so their deasserts win within the same cycle.
        if motor_s = '0' then
          idx_motor_cnt <= 0;
          media_ready   <= '0';
          idx_gap_cnt   <= (others => '0');
        else
          if index_edge = '1' then
            idx_gap_cnt <= (others => '0');
            if idx_motor_cnt >= 1 and change_latched = '0' and change_c = '0' then
              rotation_confirmed <= '1';
            end if;
            if idx_motor_cnt < 7 then
              idx_motor_cnt <= idx_motor_cnt + 1;
            end if;
          elsif idx_gap_cnt < to_unsigned(2 * G_PERIOD_MAX_CYC, 32) then
            idx_gap_cnt <= idx_gap_cnt + 1;
          else
            -- no index edge for two maximum periods while the motor is on:
            -- the disk was removed or stopped -- drop readiness and
            -- re-qualify from scratch (spin-up itself is unaffected:
            -- media_ready is still 0 then and the counters restart cleanly)
            media_ready   <= '0';
            idx_motor_cnt <= 0;
            idx_gap_cnt   <= (others => '0');
            rotation_confirmed <= '0';
          end if;
        end if;

        ------------------------------------------------------------------
        -- head-settle timer (independent, loaded on STEP trailing edge)
        ------------------------------------------------------------------
        if settle_cnt /= 0 then
          settle_cnt <= settle_cnt - 1;
          if settle_cnt = 1 then
            head_settled <= '1';
          end if;
        end if;

        ------------------------------------------------------------------
        -- STEP engine
        ------------------------------------------------------------------
        case step_st is
          when SI_IDLE =>
            step_dir_pulse <= '1';
            if step_req_edge then
              step_dir_o   <= step_outward_i;
              step_rev     <= '1' when (last_dir_vld = '1' and step_outward_i /= last_dir_out) else '0';
              head_settled <= '0';           -- clear on acceptance so no read races DIR/setup
              -- also kill a still-running settle timer from the PREVIOUS step: if it
              -- expired mid-flight it would re-assert head_settled while this step is
              -- still in DIR-setup/pulse, silently skipping the 18 ms settle guard
              -- (the trailing edge only reloads the counter, it does not re-clear the flag)
              settle_cnt   <= (others => '0');
              step_cnt     <= to_unsigned(G_DIR_SETUP_CYC, 32);
              step_st      <= SI_SETUP;
            end if;

          when SI_SETUP =>
            if step_cnt /= 0 then
              step_cnt <= step_cnt - 1;
            else
              step_dir_pulse <= '0';         -- assert STEP low
              step_cnt <= to_unsigned(G_STEP_LOW_CYC, 32);
              step_st  <= SI_LOW;
            end if;

          when SI_LOW =>
            if step_cnt /= 0 then
              step_cnt <= step_cnt - 1;
            else
              step_dir_pulse <= '1';         -- STEP trailing edge here
              -- move the head estimate
              if step_dir_o = '1' then       -- outward / toward track0
                if head_cyl > 0 then head_cyl <= head_cyl - 1; end if;
              else
                if head_cyl < 255 then head_cyl <= head_cyl + 1; end if;
              end if;
              last_dir_out <= step_dir_o;
              last_dir_vld <= '1';
              settle_cnt   <= to_unsigned(G_SETTLE_CYC, 32);   -- (re)start 18 ms settle
              if step_rev = '1' then
                step_cnt <= to_unsigned(G_STEP_REV_CYC, 32);
              else
                step_cnt <= to_unsigned(G_STEP_REC_CYC, 32);
              end if;
              step_st <= SI_REC;
            end if;

          when SI_REC =>
            if step_cnt /= 0 then
              step_cnt <= step_cnt - 1;
            else
              -- if we stepped outward onto track 0, anchor the estimate
              if step_dir_o = '1' and track0_c = '1' then
                head_cyl   <= 0;
                head_valid <= '1';
              end if;
              step_ack_tgl_o <= not step_ack_tgl_o;   -- acknowledge (recovery done)
              -- clear a disk-change latch once a real step happened with media present
              if change_c = '0' and change_latched = '1' then
                change_latched <= '0';
              end if;
              step_st <= SI_IDLE;
            end if;
        end case;

        ------------------------------------------------------------------
        -- READ engine
        ------------------------------------------------------------------
        -- F5: done-toggle spacing counter. Every rd_done toggle below arms it
        -- (those later assignments override this decrement in the same cycle).
        if done_gap_cnt /= 0 then
          done_gap_cnt <= done_gap_cnt - 1;
        end if;

        -- global cancel / disk-change abort during an active read
        if rd_st /= RD_IDLE and (cancel_edge or change_c = '1') then
          if change_c = '1' then
            rd_result_o <= RES_DISK_CHANGED; rd_rnf_o <= '1'; rd_crc_err_o <= '0';
          else
            rd_result_o <= RES_CANCELLED; rd_rnf_o <= '0'; rd_crc_err_o <= '0';
          end if;
          rd_done_tgl_o <= not rd_done_tgl_o;
          rd_done_seq_o <= seq_r;              -- F4: tag of the op being completed
          done_gap_cnt  <= C_DONE_GAP;         -- F5: arm the spacing counter
          rd_st <= RD_IDLE;
        else
          case rd_st is
            when RD_IDLE =>
              -- accept a live request, or serve a latched pending one (C2). A
              -- live edge is by definition the LATER request, so it supersedes
              -- (and clears) any pending latch; a coincident cancel edge kills
              -- the pending request but not a live one (the fdc only toggles
              -- cancel BEFORE issuing a new request, never after it).
              -- F5: while the done-spacing counter runs, accept NOTHING into
              -- an abortable state (the next done toggle could otherwise land
              -- too close to the previous one); a live edge arriving in that
              -- window is latched as pending below, so it cannot be lost.
              if done_gap_cnt = 0 then
                if rd_req_edge then
                  op_r   <= rd_op_i;
                  trk_r  <= rd_track_i;
                  sec_r  <= rd_sector_i;
                  seq_r  <= rd_seq_i;
                  pend_v <= '0';
                  saw_bad_crc <= '0';
                  ovf_l  <= '0';
                  edge_cnt <= 0;
                  rdy_wd_cnt <= to_unsigned(G_READY_WD_CYC, 32);
                  rd_req_evt <= '1';             -- trace REQUEST on acceptance
                  rd_st  <= RD_WAIT;
                elsif pend_v = '1' and not cancel_edge then
                  op_r   <= pend_op;
                  trk_r  <= pend_trk;
                  sec_r  <= pend_sec;
                  seq_r  <= pend_seq;
                  pend_v <= '0';
                  saw_bad_crc <= '0';
                  ovf_l  <= '0';
                  edge_cnt <= 0;
                  rdy_wd_cnt <= to_unsigned(G_READY_WD_CYC, 32);
                  rd_req_evt <= '1';             -- a served pending traces here
                  rd_st  <= RD_WAIT;
                end if;
              end if;

            when RD_WAIT =>
              if rdy_wd_cnt /= 0 then rdy_wd_cnt <= rdy_wd_cnt - 1; end if;
              if media_ready = '1' and head_settled = '1' and side_settle = 0 then
                dec_rst  <= '1';                       -- fresh separator for the search
                wd_cnt   <= to_unsigned(G_SEARCH_WD_CYC, 32);
                edge_cnt <= 0;
                rd_st    <= RD_SEARCH;
              elsif rdy_wd_cnt = 0 then
                rd_result_o <= RES_NOT_READY; rd_rnf_o <= '1'; rd_crc_err_o <= '0';
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              end if;

            when RD_SEARCH =>
              if wd_cnt /= 0 then wd_cnt <= wd_cnt - 1; end if;
              if index_edge = '1' then
                edge_cnt <= edge_cnt + 1;
              end if;

              if id_valid = '1' then
                if op_r = RDOP_READ_ADDRESS then
                  -- Present physical media through the stock 1581 contract:
                  -- ten sectors numbered 1..10 per surface.  The MEGA65 F011
                  -- auto-formatter can fit a CRC-valid sector-11 ID before
                  -- index truncates the following record.  A genuine-ROM
                  -- rotational model proves that exposing that ID through
                  -- Read Address can terminate login before any Read Sector.
                  -- Ignore only out-of-range IDs here; Read Sector already
                  -- matches requested 1..10 naturally, and decoder diagnostics
                  -- continue to observe every physical ID.
                  if id_r >= to_unsigned(1, id_r'length) and
                     id_r <= to_unsigned(10, id_r'length) then
                    m_c <= id_c; m_h <= id_h; m_r <= id_r; m_n <= id_n;
                    rd_c_o <= id_c; rd_h_o <= id_h; rd_r_o <= id_r; rd_n_o <= id_n;
                    if id_crc_ok = '1' then
                      rd_result_o <= RES_OK;            rd_crc_err_o <= '0'; rd_rnf_o <= '0';
                    else
                      rd_result_o <= RES_ID_CRC_ERROR;  rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                    end if;
                    addr_idx <= 0;
                    rd_st <= RD_ADDR;
                  end if;
                elsif id_c = trk_r then
                  if id_crc_ok = '1' then
                    m_c <= id_c; m_h <= id_h; m_r <= id_r; m_n <= id_n;
                    if op_r = RDOP_VERIFY then
                      rd_c_o <= id_c; rd_h_o <= id_h; rd_r_o <= id_r; rd_n_o <= id_n;
                      rd_result_o <= RES_OK; rd_crc_err_o <= '0'; rd_rnf_o <= '0';
                      rd_done_tgl_o <= not rd_done_tgl_o;
                      rd_done_seq_o <= seq_r;
                      done_gap_cnt  <= C_DONE_GAP;
                      rd_st <= RD_IDLE;
                    elsif id_r = sec_r then          -- READ_SECTOR match on C and R
                      if id_n /= C_SIZECODE_512 then
                        rd_c_o <= id_c; rd_h_o <= id_h; rd_r_o <= id_r; rd_n_o <= id_n;
                        rd_result_o <= RES_UNSUPPORTED_SIZE; rd_rnf_o <= '1'; rd_crc_err_o <= '0';
                        rd_done_tgl_o <= not rd_done_tgl_o;
                        rd_done_seq_o <= seq_r;
                        done_gap_cnt  <= C_DONE_GAP;
                        rd_st <= RD_IDLE;
                      else
                        diag_match_id_o <= '1';
                        dam_cnt <= to_unsigned(G_DAM_TIMEOUT_CYC, 32);
                        rd_st   <= RD_DAM;
                      end if;
                    end if;
                  else
                    saw_bad_crc <= '1';              -- matching C but bad ID CRC: keep looking
                  end if;
                end if;
              end if;

              -- search exhaustion. The CRC and RNF flags are NEVER set
              -- together: the genuine 318045-02 DOS job epilogue ($CD3F)
              -- indexes its result table $CD5A with (status>>3) AND 0x0B, and
              -- the CRC+RNF combination hits a 0x00 hole = job SUCCESS -- the
              -- DOS would silently ACCEPT the failed operation. CRC-only maps
              -- to job error 5 (DOS error 23) and is retried, which is the
              -- intended self-healing. See doc/dev-issue90/PLAN.md, round-10
              -- entry (proven ROM-in-the-loop).
              if edge_cnt >= G_SEARCH_EDGES or wd_cnt = 0 then
                if saw_bad_crc = '1' then
                  rd_result_o <= RES_ID_CRC_ERROR;     rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                else
                  rd_result_o <= RES_RECORD_NOT_FOUND; rd_crc_err_o <= '0'; rd_rnf_o <= '1';
                end if;
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              end if;

            when RD_DAM =>
              if wd_cnt /= 0 then wd_cnt <= wd_cnt - 1; end if;
              if dam_cnt /= 0 then dam_cnt <= dam_cnt - 1; end if;
              if index_edge = '1' then edge_cnt <= edge_cnt + 1; end if;
              if data_start = '1' then
                deleted_l <= data_deleted;
                rd_st     <= RD_STREAM;
              elsif id_valid = '1' or dam_cnt = 0 then
                -- another ID or local timeout: resume ID search within the budget
                diag_dam_miss_o <= '1';
                rd_st <= RD_SEARCH;
              end if;
              if edge_cnt >= G_SEARCH_EDGES or wd_cnt = 0 then
                rd_result_o <= RES_MISSING_DAM; rd_rnf_o <= '1'; rd_crc_err_o <= '0';
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              end if;

            when RD_STREAM =>
              -- keep the absolute op watchdog running: a flux dropout can stall the
              -- decoder mid-data-field (no data_end, no disk change) and without this
              -- bound the FSM would park here forever with the WD stuck busy. Report
              -- it as a data CRC error, CRC-only: setting RNF as well would hit the
              -- $CD5A success hole (see the search-exhaustion comment above). The
              -- delivery-v2 WD front end completes on done + empty FIFO, so an
              -- incomplete byte stream no longer needs rnf to release busy.
              if wd_cnt /= 0 then wd_cnt <= wd_cnt - 1; end if;
              if wd_cnt = 0 then
                rd_result_o <= RES_DATA_CRC_ERROR; rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              end if;
              if data_byte_v = '1' then
                byte_data_o <= data_byte;
                byte_wr_o   <= '1';
              end if;
              if data_end = '1' then
                rd_c_o <= m_c; rd_h_o <= m_h; rd_r_o <= m_r; rd_n_o <= m_n;
                rd_deleted_o <= deleted_l;
                if ovf_l = '1' or (byte_wr_o = '1' and byte_ovf_i = '1') then
                  -- one or more payload bytes never made it into the FIFO: the
                  -- stream is truncated, so fail the op. CRC-only, never with
                  -- RNF (the $CD5A success hole -- see the search-exhaustion
                  -- comment); the WD completes on done + empty FIFO.
                  rd_result_o <= RES_DATA_CRC_ERROR; rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                elsif data_crc_ok = '1' then
                  rd_result_o <= RES_OK; rd_crc_err_o <= '0'; rd_rnf_o <= '0';
                else
                  rd_result_o <= RES_DATA_CRC_ERROR; rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                end if;
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              end if;

            when RD_ADDR =>
              -- push C,H,R,N,CRC-hi,CRC-lo into the FIFO, one per cycle
              byte_wr_o <= '1';
              case addr_idx is
                when 0 => byte_data_o <= m_c;
                when 1 => byte_data_o <= m_h;
                when 2 => byte_data_o <= m_r;
                when 3 => byte_data_o <= m_n;
                when 4 => byte_data_o <= id_crc_stored(15 downto 8);
                when others => byte_data_o <= id_crc_stored(7 downto 0);
              end case;
              if addr_idx = 5 then
                if ovf_l = '1' or byte_ovf_i = '1' then
                  -- reply bytes were dropped (cannot happen with the 512-deep
                  -- FIFO after the op-start drain, but never complete silently).
                  -- CRC-only, never with RNF ($CD5A success hole -- see the
                  -- search-exhaustion comment).
                  rd_result_o <= RES_DATA_CRC_ERROR; rd_crc_err_o <= '1'; rd_rnf_o <= '0';
                end if;
                rd_done_tgl_o <= not rd_done_tgl_o;
                rd_done_seq_o <= seq_r;
                done_gap_cnt  <= C_DONE_GAP;
                rd_st <= RD_IDLE;
              else
                addr_idx <= addr_idx + 1;
              end if;
          end case;
        end if;

        ------------------------------------------------------------------
        -- pending-request latch maintenance (C2). Ordering inside this
        -- process: the cancel-clear comes first and the busy-edge latch
        -- last, so a cancel and a request edge landing in the same cycle
        -- resolve in favor of the request (the fdc sequence is always
        -- cancel-then-request). The RD_IDLE acceptance above already
        -- cleared pend_v when it consumed the latch this cycle. F5: a live
        -- edge arriving while RD_IDLE is blocked by the done-spacing counter
        -- is latched here as well (it was not accepted above).
        ------------------------------------------------------------------
        if cancel_edge then
          pend_v <= '0';
        end if;
        if (rd_st /= RD_IDLE or done_gap_cnt /= 0) and rd_req_edge then
          pend_v   <= '1';                       -- latest edge wins
          pend_op  <= rd_op_i;
          pend_trk <= rd_track_i;
          pend_sec <= rd_sector_i;
          pend_seq <= rd_seq_i;
        end if;

      end if;
    end if;
  end process;

end architecture rtl;
