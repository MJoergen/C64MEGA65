-------------------------------------------------------------------------------
-- physical_1581_diag.vhd
--
-- QNICE diagnostic register bank for the physical internal 1581 drive (issue
-- #90; write instruments issue #244). Exposed to QNICE as device
-- C_DEV_C64_PHYS1581 = 0x0108.
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
--     gap,
--   * 32-bit SATURATING event counters (raw index edges, index edges while the
--     motor is on, steps, read operations, RNFs, CRC errors, cancellations, disk
--     changes, decoded ID fields, out-of-spec gaps), and
--   * (map v4, issue #90 round 10) delivery-v2 observability: the live read-FIFO
--     write-side occupancy, the presented-byte count of the last finalized WD
--     operation, and counters for LOST DATA events, between-ops drain episodes,
--     stale (seq-mismatched) done edges, command writes ignored while busy, and
--     merged RDATA runt gaps, and
--   * (map v5, issue #90 round 12) the adaptive quantiser's live half-cell
--     estimate (word 0x36, Q8.4) and the last-RNF context word 0x37 (requested
--     track / requested sector, latched whenever a read op completes with rnf).
--   * (map v6) 16-bit saturating counters for coarse A1 candidates, candidates
--     rejected by the complete-word span check, and qualified 3xA1 trains.
--   * (map v7) record-level counters for FE/DAM marks, unsolicited DAMs,
--     requested-ID matches and matched IDs whose DAM was not found.
--   * (map v8, issue #244) the write instruments of WRITE-SPEC section 8
--     (words 0x80-0x9D): live write/writer state, the last write op (flags,
--     abort reason, C/H/R, WGATE window, bytes, precomp pulses), cumulative
--     write counters, first-byte and DRQ margins, the Write Track revolution,
--     and WR_CTRL (0x9A), the one writable word (precomp override).
--     Since v8 the read-op counters and the last-read latches (0x06-0x08,
--     0x1A-0x21, 0x37) count and latch read ops only; write ops share the
--     done channel and are counted in the v8 words instead. The trace ring
--     records both.
--
-- It runs on clk_i == c64_clk_sd_i, which is the SAME 50 MHz clock as both the
-- physical_1581_controller and the QNICE CPU -> no clock-domain crossing is
-- needed anywhere in this file. The exceptions all arrive PRE-CONDITIONED from
-- main.vhd: img_drive_busy_i (the "image drive 8 busy or dirty" level for the
-- symmetric source-toggle idle-gate) and the eight dbg_*_i toggles (fdc1772
-- drive-clock events) are 2-FF-synchronized there; dbg_pres_cnt_i crosses
-- unsynchronized as a quasi-static bus (latched at the fdc finalize, i.e. at
-- least two 50 MHz cycles before the synced dbg_fin_i edge that samples it).
--
-- It is observational with ONE exception: WR_CTRL (word 0x9A, map v8) is
-- writable from QNICE and drives wr_precomp_mode_o, the controller's precomp
-- override (0/3 follow the WD P bit, 1 off, 2 on; reset 0). QNICE writes to
-- every other word are ignored. Register reads are a purely combinational mux
-- over the register file, with no wait-state.
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
    -- adaptive quantiser half-cell estimate (map v5, issue #90 round 12):
    -- Q8.4, bits 11:4 = integer cycles, 3:0 = sixteenths. Same clock domain
    -- (controller tap). Defaulted so older testbenches keep building.
    diag_est_i          : in  unsigned(11 downto 0) := (others => '0');
    diag_rd_phase_i     : in  std_logic_vector(3 downto 0);
    diag_step_phase_i   : in  std_logic_vector(1 downto 0);
    diag_head_valid_i   : in  std_logic;
    diag_head_dir_out_i : in  std_logic;

    -----------------------------------------------------------------------------
    -- image (simulated D64/D81) drive-8 busy-or-dirty level for the symmetric
    -- source-toggle idle-gate (issue #90). Already synchronized into clk_i by
    -- the instantiating main.vhd; defaulted so older testbenches keep building.
    -----------------------------------------------------------------------------
    img_drive_busy_i    : in  std_logic_vector(1 downto 0) := "00";  -- per drive: bit 0 = drive 8, bit 1 = drive 9 (issue #93)

    -----------------------------------------------------------------------------
    -- WD-dialogue trace taps (issue #90 bring-up): read-request accept strobe +
    -- latched request parameters from the controller. Together with the existing
    -- step-ack and rd-done taps these feed a 32-entry trace ring that records
    -- the exact operation sequence the 1581 DOS issues. Defaulted for older tbs.
    -----------------------------------------------------------------------------
    rd_req_evt_i        : in  std_logic := '0';
    rd_req_op_i         : in  std_logic_vector(2 downto 0) := (others => '0');
    rd_req_track_i      : in  unsigned(7 downto 0) := (others => '0');
    rd_req_sector_i     : in  unsigned(7 downto 0) := (others => '0');
    rd_req_side_i       : in  std_logic := '0';

    -----------------------------------------------------------------------------
    -- Delivery-v2 observability (map v4, issue #90 round 10). The five dbg_*_i
    -- inputs are fdc1772 drive-clock event TOGGLES, already 2-FF-synchronized
    -- into clk_i by main.vhd; the edge detection and counting happen here.
    -- dbg_pres_cnt_i is the presented-byte count of the last finalized WD op,
    -- quasi-static after finalize (sampled on the dbg_fin_i edge). fifo_level_i
    -- is the live read-FIFO write-side occupancy (same clock domain). runt_i is
    -- a 1-cycle 50 MHz pulse per merged RDATA runt gap. Defaulted for older tbs.
    -----------------------------------------------------------------------------
    dbg_lost_i          : in  std_logic := '0';   -- toggle: LOST DATA (unconsumed byte overwritten)
    dbg_drain_i         : in  std_logic := '0';   -- toggle: between-ops FIFO drain episode
    dbg_staledone_i     : in  std_logic := '0';   -- toggle: seq-mismatched done ignored
    dbg_busycmd_i       : in  std_logic := '0';   -- toggle: WD command write ignored while busy
    dbg_fin_i           : in  std_logic := '0';   -- toggle: a phys WD op finalized
    dbg_pres_cnt_i      : in  unsigned(10 downto 0) := (others => '0');
    fifo_level_i        : in  unsigned(9 downto 0) := (others => '0');
    runt_i              : in  std_logic := '0';
    a1_candidate_i      : in  std_logic := '0';
    a1_span_reject_i    : in  std_logic := '0';
    a1_train_i          : in  std_logic := '0';
    mark_fe_i           : in  std_logic := '0';
    mark_dam_i          : in  std_logic := '0';
    dam_unarmed_i       : in  std_logic := '0';
    match_id_i          : in  std_logic := '0';
    dam_miss_i          : in  std_logic := '0';

    -----------------------------------------------------------------------------
    -- map v8 write instruments (issue #244, WRITE-SPEC 8). The controller taps
    -- are 50 MHz levels/strobes (same clock). dbg_wr_*_i are fdc1772 drive-
    -- clock event TOGGLES, 2-FF-synchronized by main.vhd like the map v4 ones.
    -- wr_pop_i is the controller's write-FIFO pop (wbyte_rd_o) and
    -- wr_fifo_level_i the wfifo read-side occupancy (rd_level_o), both on this
    -- clock. f_wgate_i / f_wdata_i are the pin levels as driven (active low).
    -- Defaulted so older testbenches keep building.
    -----------------------------------------------------------------------------
    diag_wr_phase_i        : in  std_logic_vector(3 downto 0) := (others => '0');  -- 0 idle,1 wait,2 search,3 gap,4 stream,5 tail,6 abort,7 trk-arm,8 trk-stream
    diag_wr_session_i      : in  std_logic := '0';
    diag_wr_feed_i         : in  std_logic := '0';
    diag_wr_abort_i        : in  std_logic := '0';
    diag_wr_prec_i         : in  std_logic := '0';
    diag_wr_done_i         : in  std_logic := '0';                      -- 1-cycle: a write op completed
    diag_wr_last_i         : in  std_logic_vector(7 downto 0) := (others => '0');  -- flags of that op
    diag_wr_bytes_i        : in  unsigned(15 downto 0) := (others => '0');
    diag_wr_first_margin_i : in  unsigned(7 downto 0) := (others => '1');
    diag_wr_trk_cyc_i      : in  unsigned(31 downto 0) := (others => '0');
    diag_wr_gate_i         : in  std_logic := '0';                      -- WGATE, active high
    diag_wr_gate_cyc_i     : in  unsigned(31 downto 0) := (others => '0');
    diag_wr_underrun_i     : in  unsigned(15 downto 0) := (others => '0');
    diag_wr_discard_i      : in  unsigned(15 downto 0) := (others => '0');
    diag_wr_precnt_i       : in  unsigned(15 downto 0) := (others => '0');
    diag_wr_pushfull_i     : in  unsigned(15 downto 0) := (others => '0');
    diag_wr_reason_i       : in  std_logic_vector(7 downto 0) := (others => '0');
    diag_wr_reason_acc_i   : in  std_logic_vector(7 downto 0) := (others => '0');
    diag_wr_wflags_i       : in  std_logic_vector(4 downto 0) := (others => '0');  -- 0 completed 1 aborted 2 discarded 3 underrun 4 cut
    wr_busy_i              : in  std_logic := '0';                      -- writer not idle
    wr_ok_i                : in  std_logic := '0';                      -- tab qualified writable
    f_wgate_i              : in  std_logic := '1';
    f_wdata_i              : in  std_logic := '1';
    wr_pop_i               : in  std_logic := '0';
    wr_fifo_level_i        : in  unsigned(2 downto 0) := (others => '0');
    dbg_wr_fin_i           : in  std_logic := '0';   -- toggle: a physical write op finalized in the WD
    dbg_wr_wp_i            : in  std_logic := '0';   -- toggle: a write refused by the WD write-protect pre-check
    dbg_wr_drop_i          : in  std_logic := '0';   -- toggle: a data-register write was dropped

    -- WR_CTRL (0x9A) -> controller wr_precomp_mode_i
    wr_precomp_mode_o      : out std_logic_vector(1 downto 0);

    -----------------------------------------------------------------------------
    -- QNICE interface (device C_DEV_C64_PHYS1581), no wait-state. Reads are a
    -- combinational mux; the only write is WR_CTRL (word 0x9A).
    -----------------------------------------------------------------------------
    qnice_ce_i          : in  std_logic;                     -- chip enable
    qnice_we_i          : in  std_logic := '0';              -- write strobe (implies ce)
    qnice_addr_i        : in  std_logic_vector(7 downto 0);  -- word offset
    qnice_data_i        : in  std_logic_vector(15 downto 0) := (others => '0');
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
  constant RM_IMG_DRIVE      : integer := 16#28#;   -- bit0: image drive 8 busy or dirty
  constant RM_TRC_CNT        : integer := 16#29#;   -- total trace events since reset (ring wraps at 32)
  -- map v4 (delivery v2 observability, issue #90 round 10)
  constant RM_FIFO_LEVEL     : integer := 16#2A#;   -- live read-FIFO write-side occupancy
  constant RM_LAST_PRESENT   : integer := 16#2B#;   -- presented bytes of the last finalized WD op
  constant RM_CNT_LOST_LO    : integer := 16#2C#;   -- counter: LOST DATA events
  constant RM_CNT_LOST_HI    : integer := 16#2D#;
  constant RM_CNT_DRAIN_LO   : integer := 16#2E#;   -- counter: between-ops drain episodes
  constant RM_CNT_DRAIN_HI   : integer := 16#2F#;
  constant RM_CNT_STALEDONE_LO : integer := 16#30#; -- counter: seq-mismatched done edges ignored
  constant RM_CNT_STALEDONE_HI : integer := 16#31#;
  constant RM_CNT_BUSYCMD_LO : integer := 16#32#;   -- counter: command writes ignored while busy
  constant RM_CNT_BUSYCMD_HI : integer := 16#33#;
  constant RM_CNT_RUNT_LO    : integer := 16#34#;   -- counter: merged RDATA runt gaps
  constant RM_CNT_RUNT_HI    : integer := 16#35#;
  -- map v5 (adaptive quantiser, issue #90 round 12)
  constant RM_EST            : integer := 16#36#;   -- live half-cell estimate (Q8.4)
  constant RM_RNF_CTX        : integer := 16#37#;   -- last-RNF context: req track (hi) / req sector (lo)
  -- map v6 (complete-A1 timing qualifier)
  constant RM_CNT_A1_CAND    : integer := 16#38#;   -- 16-bit saturating coarse candidates
  constant RM_CNT_A1_REJECT  : integer := 16#39#;   -- 16-bit saturating span rejects
  constant RM_CNT_A1_TRAIN   : integer := 16#3A#;   -- 16-bit saturating qualified trains
  -- map v7 (record sequencing + sector-read acquisition forensics)
  constant RM_CNT_MARK_FE     : integer := 16#3B#;   -- qualified train followed by FE
  constant RM_CNT_MARK_DAM    : integer := 16#3C#;   -- qualified train followed by FB/F8
  constant RM_CNT_DAM_UNARMED : integer := 16#3D#;   -- DAM ignored without valid ID/data lock-up
  constant RM_CNT_MATCH_ID    : integer := 16#3E#;   -- requested sector ID matched
  constant RM_CNT_DAM_MISS    : integer := 16#3F#;   -- matched ID followed by no DAM
  constant RM_TRC_BASE       : integer := 16#40#;   -- trace ring: entry k at 0x40+2k (w0) / 0x41+2k (w1)
  constant RM_TRC_END        : integer := 16#7F#;
  -- map v8 (write instruments, issue #244, WRITE-SPEC 8)
  constant RM_WR_STATE       : integer := 16#80#;   -- live write FSM / writer state (bit layout at the read mux)
  constant RM_WR_LAST        : integer := 16#81#;   -- last write op: flags (hi) / abort reason (lo)
  constant RM_WR_LAST_CHR    : integer := 16#82#;   -- last sector op: R (hi) / C (lo); H in WR_STATE bit 13
  constant RM_WR_GATE_CYC_LO : integer := 16#83#;   -- WGATE window of the last op (cycles)
  constant RM_WR_GATE_CYC_HI : integer := 16#84#;
  constant RM_WR_BYTES_LAST  : integer := 16#85#;   -- bytes/tokens consumed, current/last op
  constant RM_CNT_WR_SECT_LO : integer := 16#86#;   -- counter: Write Sector ops
  constant RM_CNT_WR_SECT_HI : integer := 16#87#;
  constant RM_CNT_WR_TRK_LO  : integer := 16#88#;   -- counter: Write Track ops
  constant RM_CNT_WR_TRK_HI  : integer := 16#89#;
  constant RM_CNT_WR_GATE_LO : integer := 16#8A#;   -- counter: ops in which WGATE opened
  constant RM_CNT_WR_GATE_HI : integer := 16#8B#;
  constant RM_CNT_WR_LOST_LO : integer := 16#8C#;   -- counter: ops with LOST DATA
  constant RM_CNT_WR_LOST_HI : integer := 16#8D#;
  constant RM_CNT_WR_WP_LO   : integer := 16#8E#;   -- counter: write-protect refusals (all stages)
  constant RM_CNT_WR_WP_HI   : integer := 16#8F#;
  constant RM_CNT_WR_ABORT_LO: integer := 16#90#;   -- counter: aborted ops
  constant RM_CNT_WR_ABORT_HI: integer := 16#91#;
  constant RM_WR_REASON_ACC  : integer := 16#92#;   -- OR of all writer abort reasons
  constant RM_CNT_WR_FIFO_OVF: integer := 16#93#;   -- 16-bit: data-register writes dropped by the WD
  constant RM_CNT_WR_UNDERRUN: integer := 16#94#;   -- 16-bit: writer word underruns
  constant RM_WR_PRECOMP_CNT : integer := 16#95#;   -- precompensated pulses, last op
  constant RM_WR_FIRST_MARGIN: integer := 16#96#;   -- minimum first-byte margin (byte-times), FF = none
  constant RM_WR_DRQ_MARGIN  : integer := 16#97#;   -- minimum write-FIFO level at a pop, last op, FF = none
  constant RM_WR_TRK_CYC_LO  : integer := 16#98#;   -- index-to-index cycles, last track op
  constant RM_WR_TRK_CYC_HI  : integer := 16#99#;
  constant RM_WR_CTRL        : integer := 16#9A#;   -- WRITABLE: bits 1:0 precomp mode
  constant RM_CNT_WR_FIN     : integer := 16#9B#;   -- 16-bit: write ops finalized in the WD front end
  constant RM_WR_PUSHFULL    : integer := 16#9C#;   -- 16-bit: words refused by a full writer FIFO
  constant RM_WR_DISCARD     : integer := 16#9D#;   -- 16-bit: writer sessions discarded at ARM

  constant C_MAP_VERSION : std_logic_vector(7 downto 0) := x"08";
  -- capability flags: bit0 = read-only (cleared since map v8: WR_CTRL is writable),
  --                   bit1 = counters present, bit2 = CRC taps present,
  --                   bit3 = image-drive busy word (RM_IMG_DRIVE) present,
  --                   bit4 = WD-dialogue trace ring (RM_TRC_*) present,
  --                   bit5 = delivery-v2 observability words (0x2A-0x35) present,
  --                   bit6 = complete-A1 qualifier counters (0x38-0x3A) present,
  --                   bit7 = record-sequencing counters (0x3B-0x3F) present
  constant C_CAPABILITY  : std_logic_vector(7 downto 0) := x"FE";

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
  -- map v4 delivery-v2 counters
  signal cnt_lost      : unsigned(31 downto 0) := (others => '0');
  signal cnt_drain     : unsigned(31 downto 0) := (others => '0');
  signal cnt_staledone : unsigned(31 downto 0) := (others => '0');
  signal cnt_busycmd   : unsigned(31 downto 0) := (others => '0');
  signal cnt_runt      : unsigned(31 downto 0) := (others => '0');
  signal cnt_a1_cand, cnt_a1_reject, cnt_a1_train : unsigned(15 downto 0) := (others => '0');
  signal cnt_mark_fe, cnt_mark_dam, cnt_dam_unarmed : unsigned(15 downto 0) := (others => '0');
  signal cnt_match_id, cnt_dam_miss : unsigned(15 downto 0) := (others => '0');

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
  -- map v4: edge-detect history for the synced fdc1772 event toggles
  signal prev_lost      : std_logic := '0';
  signal prev_drain     : std_logic := '0';
  signal prev_staledone : std_logic := '0';
  signal prev_busycmd   : std_logic := '0';
  signal prev_fin       : std_logic := '0';
  -- presented-byte count of the last finalized WD op (sampled on the fin edge)
  signal last_present   : unsigned(10 downto 0) := (others => '0');
  -- map v5: last-RNF context, latched at every read completion with rnf = 1:
  -- requested track (high byte) / requested sector (low byte). The controller
  -- holds its latched request parameters stable for at least C_DONE_GAP cycles
  -- after every done toggle, so sampling them one cycle after the toggle
  -- (rddone_evt) is race-free.
  signal rnf_ctx        : std_logic_vector(15 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- WD-dialogue trace ring: 32 entries x 32 bits (one write per event). Entry
  -- layout, split into two QNICE words w0 = bits 31:16 / w1 = bits 15:0:
  --   STEP    w0 = 0x1000 | dir_out<<8 | head_cyl_estimate
  --           w1 = track0 (bit 0)
  --   RD REQ  w0 = 0x2000 | op<<9 | side<<8 | requested track
  --           w1 = requested sector << 8
  --   RD DONE w0 = 0x3000 | rnf<<11 | crc<<10 | deleted<<9 | found_H_lsb<<8 | found C
  --           w1 = found R << 8 | result code
  -- On the rare coincidence of two events in one clock, priority is
  -- DONE > REQ > STEP and the lower-priority event of that cycle is dropped.
  ---------------------------------------------------------------------------
  type trc_ram_t is array (0 to 31) of std_logic_vector(31 downto 0);
  signal trc_ram : trc_ram_t := (others => (others => '0'));
  signal trc_cnt : unsigned(15 downto 0) := (others => '0');

  ---------------------------------------------------------------------------
  -- map v8 write instruments. Counters are cumulative since reset; the "last
  -- op" registers latch on diag_wr_done_i (one clock after the controller saw
  -- its own done toggle; its request parameters stay put for C_DONE_GAP = 8
  -- cycles after the toggle, so sampling rd_req_* here is race-free).
  ---------------------------------------------------------------------------
  signal cnt_wr_sect, cnt_wr_track, cnt_wr_gate : unsigned(31 downto 0) := (others => '0');
  signal cnt_wr_lost, cnt_wr_wp, cnt_wr_abort   : unsigned(31 downto 0) := (others => '0');
  signal cnt_wr_fifo_ovf, cnt_wr_fin            : unsigned(15 downto 0) := (others => '0');
  signal wr_last_flags  : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_last_reason : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_last_c      : unsigned(7 downto 0) := (others => '0');
  signal wr_last_r      : unsigned(7 downto 0) := (others => '0');
  signal wr_last_h      : std_logic := '0';
  signal wr_gate_cyc_l  : unsigned(31 downto 0) := (others => '0');
  signal wr_precnt_l    : unsigned(15 downto 0) := (others => '0');
  signal wr_first_min   : unsigned(7 downto 0) := (others => '1');
  signal wr_drq_min     : unsigned(7 downto 0) := (others => '1');
  signal wr_gate_seen   : std_logic := '0';   -- WGATE opened in the current/last write op
  signal wr_sess_seen   : std_logic := '0';   -- the writer session rose in the current/last write op
  signal wr_ctrl        : std_logic_vector(1 downto 0) := "00";
  signal prev_wr_fin    : std_logic := '0';
  signal prev_wr_wp     : std_logic := '0';
  signal prev_wr_drop   : std_logic := '0';
  signal ctrl_phase     : std_logic_vector(3 downto 0);   -- CTRL_STATE bits 15:12
  signal wr_wstate      : std_logic_vector(2 downto 0);   -- WR_STATE bits 6:4

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

  function sat_inc16(v : unsigned(15 downto 0); ev : std_logic) return unsigned is
  begin
    if ev = '1' and v /= x"FFFF" then return v + 1; else return v; end if;
  end function;

  -- '1' for the write op codes on the shared request/done channel
  function is_wr_op(op : std_logic_vector(2 downto 0)) return std_logic is
  begin
    if op = WROP_WRITE_SECTOR or op = WROP_WRITE_TRACK then return '1'; else return '0'; end if;
  end function;

begin

  ---------------------------------------------------------------------------
  -- counters, latches and min/max tracking
  ---------------------------------------------------------------------------
  update_p : process (clk_i)
    variable rddone_evt : std_logic;
    variable step_evt   : std_logic;
    variable change_evt : std_logic;
    variable lost_evt      : std_logic;
    variable drain_evt     : std_logic;
    variable staledone_evt : std_logic;
    variable busycmd_evt   : std_logic;
    variable fin_evt       : std_logic;
    variable rddone_rd     : std_logic;   -- rddone_evt of a READ op (v8: write ops excluded)
    variable wr_fin_evt    : std_logic;
    variable wr_wp_evt     : std_logic;
    variable wr_drop_evt   : std_logic;
    variable wr_trk        : std_logic;
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
        trc_cnt       <= (others => '0');
        cnt_lost       <= (others => '0');
        cnt_drain      <= (others => '0');
        cnt_staledone  <= (others => '0');
        cnt_busycmd    <= (others => '0');
        cnt_runt       <= (others => '0');
        cnt_a1_cand    <= (others => '0');
        cnt_a1_reject  <= (others => '0');
        cnt_a1_train   <= (others => '0');
        cnt_mark_fe     <= (others => '0');
        cnt_mark_dam    <= (others => '0');
        cnt_dam_unarmed <= (others => '0');
        cnt_match_id    <= (others => '0');
        cnt_dam_miss    <= (others => '0');
        last_present   <= (others => '0');
        rnf_ctx        <= (others => '0');
        prev_lost      <= dbg_lost_i;
        prev_drain     <= dbg_drain_i;
        prev_staledone <= dbg_staledone_i;
        prev_busycmd   <= dbg_busycmd_i;
        prev_fin       <= dbg_fin_i;
        -- map v8
        cnt_wr_sect     <= (others => '0');
        cnt_wr_track    <= (others => '0');
        cnt_wr_gate     <= (others => '0');
        cnt_wr_lost     <= (others => '0');
        cnt_wr_wp       <= (others => '0');
        cnt_wr_abort    <= (others => '0');
        cnt_wr_fifo_ovf <= (others => '0');
        cnt_wr_fin      <= (others => '0');
        wr_last_flags   <= (others => '0');
        wr_last_reason  <= (others => '0');
        wr_last_c       <= (others => '0');
        wr_last_r       <= (others => '0');
        wr_last_h       <= '0';
        wr_gate_cyc_l   <= (others => '0');
        wr_precnt_l     <= (others => '0');
        wr_first_min    <= (others => '1');
        wr_drq_min      <= (others => '1');
        wr_gate_seen    <= '0';
        wr_sess_seen    <= '0';
        wr_ctrl         <= "00";
        prev_wr_fin     <= dbg_wr_fin_i;
        prev_wr_wp      <= dbg_wr_wp_i;
        prev_wr_drop    <= dbg_wr_drop_i;
      else
        -- derived event pulses
        rddone_evt := rd_done_tgl_i  xor prev_rd_done;
        step_evt   := step_ack_tgl_i xor prev_step_ack;
        change_evt := st_change_i and (not prev_change);
        prev_rd_done  <= rd_done_tgl_i;
        prev_step_ack <= step_ack_tgl_i;
        prev_change   <= st_change_i;
        lost_evt      := dbg_lost_i      xor prev_lost;
        drain_evt     := dbg_drain_i     xor prev_drain;
        staledone_evt := dbg_staledone_i xor prev_staledone;
        busycmd_evt   := dbg_busycmd_i   xor prev_busycmd;
        fin_evt       := dbg_fin_i       xor prev_fin;
        prev_lost      <= dbg_lost_i;
        prev_drain     <= dbg_drain_i;
        prev_staledone <= dbg_staledone_i;
        prev_busycmd   <= dbg_busycmd_i;
        prev_fin       <= dbg_fin_i;
        wr_fin_evt    := dbg_wr_fin_i  xor prev_wr_fin;
        wr_wp_evt     := dbg_wr_wp_i   xor prev_wr_wp;
        wr_drop_evt   := dbg_wr_drop_i xor prev_wr_drop;
        prev_wr_fin   <= dbg_wr_fin_i;
        prev_wr_wp    <= dbg_wr_wp_i;
        prev_wr_drop  <= dbg_wr_drop_i;
        -- the done channel is shared by reads and writes (map v8): rd_req_op_i
        -- is the controller's latched op of the op just completed (it changes
        -- C_DONE_GAP cycles after the done toggle at the earliest)
        rddone_rd := rddone_evt and not is_wr_op(rd_req_op_i);

        -- WD-dialogue trace ring (see layout comment at the declaration)
        if rddone_evt = '1' then
          trc_ram(to_integer(trc_cnt(4 downto 0))) <=
            "0011" & rd_rnf_i & rd_crc_err_i & rd_deleted_i & rd_h_i(0) & std_logic_vector(rd_c_i) &
            std_logic_vector(rd_r_i) & "000" & rd_result_i;
          trc_cnt <= trc_cnt + 1;
        elsif rd_req_evt_i = '1' then
          trc_ram(to_integer(trc_cnt(4 downto 0))) <=
            "0010" & rd_req_op_i & rd_req_side_i & std_logic_vector(rd_req_track_i) &
            std_logic_vector(rd_req_sector_i) & x"00";
          trc_cnt <= trc_cnt + 1;
        elsif step_evt = '1' then
          trc_ram(to_integer(trc_cnt(4 downto 0))) <=
            "0001" & "000" & diag_head_dir_out_i & std_logic_vector(st_head_cyl_i) &
            x"00" & "0000000" & st_track0_i;
          trc_cnt <= trc_cnt + 1;
        end if;

        -- saturating counters
        cnt_idx_raw  <= sat_inc(cnt_idx_raw,  diag_index_edge_i);
        cnt_idx_qual <= sat_inc(cnt_idx_qual, diag_index_qual_i);
        cnt_step     <= sat_inc(cnt_step,     step_evt);
        cnt_readop   <= sat_inc(cnt_readop,   rddone_rd);
        cnt_iddec    <= sat_inc(cnt_iddec,    diag_id_valid_i);
        cnt_gaperr   <= sat_inc(cnt_gaperr,   diag_gap_error_i);
        cnt_change   <= sat_inc(cnt_change,   change_evt);
        cnt_rnf      <= sat_inc(cnt_rnf,      rddone_rd and rd_rnf_i);
        cnt_crcerr   <= sat_inc(cnt_crcerr,   rddone_rd and rd_crc_err_i);
        if rddone_rd = '1' and rd_result_i = RES_CANCELLED then
          cnt_cancel <= sat_inc(cnt_cancel, '1');
        end if;

        -- map v4 delivery-v2 counters + last-presented capture
        cnt_lost      <= sat_inc(cnt_lost,      lost_evt);
        cnt_drain     <= sat_inc(cnt_drain,     drain_evt);
        cnt_staledone <= sat_inc(cnt_staledone, staledone_evt);
        cnt_busycmd   <= sat_inc(cnt_busycmd,   busycmd_evt);
        cnt_runt      <= sat_inc(cnt_runt,      runt_i);
        cnt_a1_cand   <= sat_inc16(cnt_a1_cand,   a1_candidate_i);
        cnt_a1_reject <= sat_inc16(cnt_a1_reject, a1_span_reject_i);
        cnt_a1_train  <= sat_inc16(cnt_a1_train,  a1_train_i);
        cnt_mark_fe     <= sat_inc16(cnt_mark_fe,     mark_fe_i);
        cnt_mark_dam    <= sat_inc16(cnt_mark_dam,    mark_dam_i);
        cnt_dam_unarmed <= sat_inc16(cnt_dam_unarmed, dam_unarmed_i);
        cnt_match_id    <= sat_inc16(cnt_match_id,    match_id_i);
        cnt_dam_miss    <= sat_inc16(cnt_dam_miss,    dam_miss_i);
        if fin_evt = '1' then
          last_present <= dbg_pres_cnt_i;
        end if;

        -- map v5: last-RNF context (see the rnf_ctx declaration comment)
        if rddone_rd = '1' and rd_rnf_i = '1' then
          rnf_ctx <= std_logic_vector(rd_req_track_i) & std_logic_vector(rd_req_sector_i);
        end if;

        -- latch the last completed read result + found CHRN
        if rddone_rd = '1' then
          last_result  <= rd_result_i;
          last_crc_err <= rd_crc_err_i;
          last_rnf     <= rd_rnf_i;
          last_deleted <= rd_deleted_i;
          last_c       <= rd_c_i;
          last_h       <= rd_h_i;
          last_r       <= rd_r_i;
          last_n       <= rd_n_i;
        end if;

        -- map v8: write instruments (WRITE-SPEC 8) ---------------------------
        cnt_wr_fifo_ovf <= sat_inc16(cnt_wr_fifo_ovf, wr_drop_evt);
        cnt_wr_fin      <= sat_inc16(cnt_wr_fin,      wr_fin_evt);
        -- write-protect refusals: the WD pre-check (no request reaches the
        -- controller) plus every controller-side RES_WRITE_PROTECTED (WR_WAIT
        -- refusal, ARM discard, live tab abort)
        cnt_wr_wp <= sat_inc(sat_inc(cnt_wr_wp, wr_wp_evt), diag_wr_done_i and diag_wr_last_i(3));

        if diag_wr_gate_i = '1' then
          wr_gate_seen <= '1';
        end if;
        if diag_wr_session_i = '1' then
          wr_sess_seen <= '1';
        end if;
        -- WR_DRQ_MARGIN: the write-FIFO level at every consuming pop (stream
        -- phases only; the drains in the other phases do not count)
        if wr_pop_i = '1' and (diag_wr_phase_i = "0100" or diag_wr_phase_i = "1000") and
           resize(wr_fifo_level_i, 8) < wr_drq_min then
          wr_drq_min <= resize(wr_fifo_level_i, 8);
        end if;

        if diag_wr_done_i = '1' then
          wr_trk := diag_wr_last_i(5);
          cnt_wr_sect  <= sat_inc(cnt_wr_sect,  not wr_trk);
          cnt_wr_track <= sat_inc(cnt_wr_track, wr_trk);
          cnt_wr_gate  <= sat_inc(cnt_wr_gate,  wr_gate_seen);
          cnt_wr_lost  <= sat_inc(cnt_wr_lost,  diag_wr_last_i(1));
          cnt_wr_abort <= sat_inc(cnt_wr_abort, diag_wr_last_i(2));
          wr_last_flags <= diag_wr_last_i;
          -- the writer describes its last SESSION; an op without one (refused,
          -- or aborted before the gap expired) reports 0 here
          if wr_sess_seen = '1' then
            wr_last_reason <= diag_wr_reason_i;
            wr_precnt_l    <= diag_wr_precnt_i;
          else
            wr_last_reason <= (others => '0');
            wr_precnt_l    <= (others => '0');
          end if;
          if wr_gate_seen = '1' then
            wr_gate_cyc_l <= diag_wr_gate_cyc_i;
          else
            wr_gate_cyc_l <= (others => '0');
          end if;
          if wr_trk = '0' then
            wr_last_c <= rd_req_track_i;
            wr_last_r <= rd_req_sector_i;
            wr_last_h <= rd_h_i(0);
            if diag_wr_first_margin_i /= x"FF" and diag_wr_first_margin_i < wr_first_min then
              wr_first_min <= diag_wr_first_margin_i;
            end if;
          end if;
          -- an op that lost a byte (first-byte abort or a mid-op underrun) had
          -- no slack at some slot
          if diag_wr_last_i(1) = '1' then
            wr_drq_min <= (others => '0');
          end if;
        end if;

        -- write-op acceptance starts the per-op registers (after the done
        -- block, so it wins on a coincidence)
        if rd_req_evt_i = '1' and is_wr_op(rd_req_op_i) = '1' then
          wr_gate_seen <= '0';
          wr_sess_seen <= '0';
          wr_drq_min   <= (others => '1');
        end if;

        -- WR_CTRL (0x9A): the only QNICE-writable word
        if qnice_ce_i = '1' and qnice_we_i = '1' and
           to_integer(unsigned(qnice_addr_i)) = RM_WR_CTRL then
          wr_ctrl <= qnice_data_i(1 downto 0);
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

  wr_precomp_mode_o <= wr_ctrl;

  ---------------------------------------------------------------------------
  -- CTRL_STATE bits 15:12 (map v8): the read FSM phase, or -- while a write op
  -- is active or the writer is still busy -- a write code with bit 15 set,
  -- bit 14 = Write Track (format) op, bits 13:12 = coarse write phase:
  --   00 waiting for ready, 01 positioning (ID search, 22-byte gap, waiting
  --   for the index of a Write Track), 10 streaming (WGATE open), 11 ending
  --   (tail, abort or the writer still draining).
  -- So the Shell classifies Writing (8..B) / Format (C..F) / Reading (1..5)
  -- from this one word, and its idle-gate mask over bits 15:10 and 3 covers
  -- writes unchanged. The full write phase is in WR_STATE (0x80).
  ---------------------------------------------------------------------------
  ctrl_phase_p : process (all)
    variable coarse : std_logic_vector(1 downto 0);
  begin
    case diag_wr_phase_i is
      when "0001"                   => coarse := "00";   -- wait
      when "0010" | "0011" | "0111" => coarse := "01";   -- search, gap, track arm
      when "0100" | "1000"          => coarse := "10";   -- stream, track stream
      when others                   => coarse := "11";   -- tail, abort, writer busy
    end case;
    if diag_wr_phase_i /= "0000" or wr_busy_i = '1' then
      if rd_req_op_i = WROP_WRITE_TRACK then
        ctrl_phase <= "11" & coarse;
      else
        ctrl_phase <= "10" & coarse;
      end if;
    else
      ctrl_phase <= diag_rd_phase_i;
    end if;
  end process ctrl_phase_p;

  ---------------------------------------------------------------------------
  -- writer state for WR_STATE bits 6:4, derived from the writer taps (the
  -- writer FSM register itself is not exported): 0 idle, 1 armed or draining
  -- with WGATE shut, 2 streaming with WGATE open, 3 discarding (tab not
  -- qualified at ARM), 4 aborted (gate shut until the session falls)
  ---------------------------------------------------------------------------
  wr_wstate <= "000" when wr_busy_i = '0' else
               "100" when diag_wr_wflags_i(1) = '1' else
               "011" when diag_wr_wflags_i(2) = '1' else
               "010" when diag_wr_gate_i = '1' else
               "001";

  ---------------------------------------------------------------------------
  -- combinational read mux (no wait-state). Writes other than WR_CTRL are
  -- ignored.
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
        qnice_data_o <= ctrl_phase                -- bits 15..12 (read phase, or a write code, see ctrl_phase_p)
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

      when RM_IMG_DRIVE       => qnice_data_o <= x"000" & "00" & img_drive_busy_i;
      when RM_TRC_CNT         => qnice_data_o <= std_logic_vector(trc_cnt);

      when RM_FIFO_LEVEL      => qnice_data_o <= "000000" & std_logic_vector(fifo_level_i);
      when RM_LAST_PRESENT    => qnice_data_o <= "00000" & std_logic_vector(last_present);
      when RM_CNT_LOST_LO     => qnice_data_o <= lo16(cnt_lost);
      when RM_CNT_LOST_HI     => qnice_data_o <= hi16(cnt_lost);
      when RM_CNT_DRAIN_LO    => qnice_data_o <= lo16(cnt_drain);
      when RM_CNT_DRAIN_HI    => qnice_data_o <= hi16(cnt_drain);
      when RM_CNT_STALEDONE_LO => qnice_data_o <= lo16(cnt_staledone);
      when RM_CNT_STALEDONE_HI => qnice_data_o <= hi16(cnt_staledone);
      when RM_CNT_BUSYCMD_LO  => qnice_data_o <= lo16(cnt_busycmd);
      when RM_CNT_BUSYCMD_HI  => qnice_data_o <= hi16(cnt_busycmd);
      when RM_CNT_RUNT_LO     => qnice_data_o <= lo16(cnt_runt);
      when RM_CNT_RUNT_HI     => qnice_data_o <= hi16(cnt_runt);

      when RM_EST             => qnice_data_o <= "0000" & std_logic_vector(diag_est_i);
      when RM_RNF_CTX         => qnice_data_o <= rnf_ctx;
      when RM_CNT_A1_CAND     => qnice_data_o <= std_logic_vector(cnt_a1_cand);
      when RM_CNT_A1_REJECT   => qnice_data_o <= std_logic_vector(cnt_a1_reject);
      when RM_CNT_A1_TRAIN    => qnice_data_o <= std_logic_vector(cnt_a1_train);
      when RM_CNT_MARK_FE     => qnice_data_o <= std_logic_vector(cnt_mark_fe);
      when RM_CNT_MARK_DAM    => qnice_data_o <= std_logic_vector(cnt_mark_dam);
      when RM_CNT_DAM_UNARMED => qnice_data_o <= std_logic_vector(cnt_dam_unarmed);
      when RM_CNT_MATCH_ID    => qnice_data_o <= std_logic_vector(cnt_match_id);
      when RM_CNT_DAM_MISS    => qnice_data_o <= std_logic_vector(cnt_dam_miss);

      -- map v8: write instruments
      when RM_WR_STATE        =>
        qnice_data_o <= '0'                       -- bit  15 reserved
                      & diag_wr_abort_i           -- bit  14 abort level to the writer
                      & wr_last_h                 -- bit  13 H of the last sector op (found ID)
                      & f_wdata_i                 -- bit  12 WDATA pin level
                      & f_wgate_i                 -- bit  11 WGATE pin level (0 = writing)
                      & diag_wr_prec_i            -- bit  10 precomp active (current/last op)
                      & diag_wr_feed_i            -- bit   9 feed (DRQ enable to the WD)
                      & diag_wr_session_i         -- bit   8 writer session
                      & wr_ok_i                   -- bit   7 tab qualified writable
                      & wr_wstate                 -- bits 6..4 writer state (derived)
                      & diag_wr_phase_i;          -- bits 3..0 write FSM phase
      when RM_WR_LAST         => qnice_data_o <= wr_last_flags & wr_last_reason;
      when RM_WR_LAST_CHR     => qnice_data_o <= std_logic_vector(wr_last_r) & std_logic_vector(wr_last_c);
      when RM_WR_GATE_CYC_LO  => qnice_data_o <= lo16(wr_gate_cyc_l);
      when RM_WR_GATE_CYC_HI  => qnice_data_o <= hi16(wr_gate_cyc_l);
      when RM_WR_BYTES_LAST   => qnice_data_o <= std_logic_vector(diag_wr_bytes_i);
      when RM_CNT_WR_SECT_LO  => qnice_data_o <= lo16(cnt_wr_sect);
      when RM_CNT_WR_SECT_HI  => qnice_data_o <= hi16(cnt_wr_sect);
      when RM_CNT_WR_TRK_LO   => qnice_data_o <= lo16(cnt_wr_track);
      when RM_CNT_WR_TRK_HI   => qnice_data_o <= hi16(cnt_wr_track);
      when RM_CNT_WR_GATE_LO  => qnice_data_o <= lo16(cnt_wr_gate);
      when RM_CNT_WR_GATE_HI  => qnice_data_o <= hi16(cnt_wr_gate);
      when RM_CNT_WR_LOST_LO  => qnice_data_o <= lo16(cnt_wr_lost);
      when RM_CNT_WR_LOST_HI  => qnice_data_o <= hi16(cnt_wr_lost);
      when RM_CNT_WR_WP_LO    => qnice_data_o <= lo16(cnt_wr_wp);
      when RM_CNT_WR_WP_HI    => qnice_data_o <= hi16(cnt_wr_wp);
      when RM_CNT_WR_ABORT_LO => qnice_data_o <= lo16(cnt_wr_abort);
      when RM_CNT_WR_ABORT_HI => qnice_data_o <= hi16(cnt_wr_abort);
      when RM_WR_REASON_ACC   => qnice_data_o <= x"00" & diag_wr_reason_acc_i;
      when RM_CNT_WR_FIFO_OVF => qnice_data_o <= std_logic_vector(cnt_wr_fifo_ovf);
      when RM_CNT_WR_UNDERRUN => qnice_data_o <= std_logic_vector(diag_wr_underrun_i);
      when RM_WR_PRECOMP_CNT  => qnice_data_o <= std_logic_vector(wr_precnt_l);
      when RM_WR_FIRST_MARGIN => qnice_data_o <= x"00" & std_logic_vector(wr_first_min);
      when RM_WR_DRQ_MARGIN   => qnice_data_o <= x"00" & std_logic_vector(wr_drq_min);
      when RM_WR_TRK_CYC_LO   => qnice_data_o <= std_logic_vector(diag_wr_trk_cyc_i(15 downto 0));
      when RM_WR_TRK_CYC_HI   => qnice_data_o <= std_logic_vector(diag_wr_trk_cyc_i(31 downto 16));
      when RM_WR_CTRL         => qnice_data_o <= x"000" & "00" & wr_ctrl;
      when RM_CNT_WR_FIN      => qnice_data_o <= std_logic_vector(cnt_wr_fin);
      when RM_WR_PUSHFULL     => qnice_data_o <= std_logic_vector(diag_wr_pushfull_i);
      when RM_WR_DISCARD      => qnice_data_o <= std_logic_vector(diag_wr_discard_i);

      when others             =>
        if a >= RM_TRC_BASE and a <= RM_TRC_END then
          -- trace ring: even offset = w0 (bits 31:16), odd offset = w1 (bits 15:0)
          if (a mod 2) = 0 then
            qnice_data_o <= trc_ram((a - RM_TRC_BASE) / 2)(31 downto 16);
          else
            qnice_data_o <= trc_ram((a - RM_TRC_BASE) / 2)(15 downto 0);
          end if;
        else
          qnice_data_o <= x"0000";
        end if;
    end case;
  end process read_p;

end architecture rtl;
