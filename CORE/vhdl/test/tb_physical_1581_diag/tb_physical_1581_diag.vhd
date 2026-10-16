-------------------------------------------------------------------------------
-- tb_physical_1581_diag.vhd
--
-- Stand-alone unit test of physical_1581_diag (the QNICE diagnostic register
-- bank, issue #90; map v8 write instruments issue #244). It drives known
-- diagnostic inputs and event
-- strobes, reads every documented register word over the QNICE read interface,
-- and asserts:
--   * the signature (x"1581") and version/capability word,
--   * the packed live-input / live-output words,
--   * the controller-state and head words (bit packing),
--   * the latched last-result + found C/H/R/N,
--   * the latched ID/data CRCs and the CRC-flags word,
--   * the index period / width split words and the last/min/max flux gap, and
--   * every 32-bit saturating counter (index raw / qualified, steps, read ops,
--     RNFs, CRC errors, cancellations, disk changes, decoded IDs, gap errors),
--   * map v8: the WR_CTRL write/readback and its output, the CTRL_STATE write
--     codes, the WR_STATE packing, simulated write ops (sector, write-protect
--     refused, lost, track, aborted) driving the cumulative write counters
--     and the last-op latches, the WD-side toggles, and that write ops leave
--     the read-op counters and the last-read latches alone.
--
-- Purely combinational reads and same-clock counters => no timing subtlety; the
-- whole run is a few microseconds of sim time.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;

entity tb_physical_1581_diag is
end entity;

architecture sim of tb_physical_1581_diag is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- controller state levels
  signal st_media_ready, st_index, st_track0, st_wprot, st_change : std_logic := '0';
  signal st_motor_on, st_head_settled, st_locked : std_logic := '0';
  signal st_head_cyl : unsigned(7 downto 0) := (others => '0');

  -- read result + step handshake
  signal rd_done_tgl : std_logic := '0';
  signal rd_result   : std_logic_vector(4 downto 0) := (others => '0');
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic := '0';
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0) := (others => '0');
  signal step_ack_tgl : std_logic := '0';

  -- diag observation taps
  signal diag_in_bits, diag_out_bits : std_logic_vector(15 downto 0) := (others => '0');
  signal diag_index_period, diag_index_width : unsigned(31 downto 0) := (others => '0');
  signal diag_last_gap, diag_calc_crc, diag_stored_crc : unsigned(15 downto 0) := (others => '0');
  signal diag_index_edge, diag_index_qual, diag_id_valid, diag_id_crc_ok : std_logic := '0';
  signal diag_data_end, diag_data_crc_ok, diag_gap_error : std_logic := '0';
  signal diag_rd_phase : std_logic_vector(3 downto 0) := (others => '0');
  signal diag_step_phase : std_logic_vector(1 downto 0) := (others => '0');
  signal diag_head_valid, diag_head_dir_out : std_logic := '0';

  -- image-drive busy/dirty level (issue #90 symmetric idle-gate)
  signal img_drive_busy : std_logic := '0';

  -- WD-dialogue trace taps
  signal rd_req_evt    : std_logic := '0';
  signal rd_req_op     : std_logic_vector(2 downto 0) := (others => '0');
  signal rd_req_track  : unsigned(7 downto 0) := (others => '0');
  signal rd_req_sector : unsigned(7 downto 0) := (others => '0');
  signal rd_req_side   : std_logic := '0';

  -- map v5 adaptive quantiser estimate (Q8.4)
  signal diag_est      : unsigned(11 downto 0) := (others => '0');

  -- map v4 delivery-v2 observability inputs
  signal dbg_lost      : std_logic := '0';
  signal dbg_drain     : std_logic := '0';
  signal dbg_staledone : std_logic := '0';
  signal dbg_busycmd   : std_logic := '0';
  signal dbg_fin       : std_logic := '0';
  signal dbg_pres_cnt  : unsigned(10 downto 0) := (others => '0');
  signal fifo_level    : unsigned(9 downto 0) := (others => '0');
  signal runt          : std_logic := '0';
  signal a1_candidate, a1_span_reject, a1_train : std_logic := '0';
  signal mark_fe, mark_dam, dam_unarmed, match_id, dam_miss : std_logic := '0';

  -- map v8 write instruments
  signal diag_wr_phase   : std_logic_vector(3 downto 0) := (others => '0');
  signal diag_wr_session, diag_wr_feed, diag_wr_abort, diag_wr_prec : std_logic := '0';
  signal diag_wr_done    : std_logic := '0';
  signal diag_wr_last    : std_logic_vector(7 downto 0) := (others => '0');
  signal diag_wr_bytes   : unsigned(15 downto 0) := (others => '0');
  signal diag_wr_first_margin : unsigned(7 downto 0) := (others => '1');
  signal diag_wr_trk_cyc, diag_wr_gate_cyc : unsigned(31 downto 0) := (others => '0');
  signal diag_wr_gate    : std_logic := '0';
  signal diag_wr_underrun, diag_wr_discard, diag_wr_precnt, diag_wr_pushfull : unsigned(15 downto 0) := (others => '0');
  signal diag_wr_reason, diag_wr_reason_acc : std_logic_vector(7 downto 0) := (others => '0');
  signal diag_wr_wflags  : std_logic_vector(4 downto 0) := (others => '0');
  signal wr_busy, wr_ok  : std_logic := '0';
  signal f_wgate, f_wdata : std_logic := '1';
  signal wr_pop          : std_logic := '0';
  signal wr_fifo_level   : unsigned(2 downto 0) := (others => '0');
  signal dbg_wr_fin, dbg_wr_wp, dbg_wr_drop : std_logic := '0';
  signal wr_precomp_mode : std_logic_vector(1 downto 0);

  -- QNICE interface
  signal q_ce   : std_logic := '0';
  signal q_we   : std_logic := '0';
  signal q_addr : std_logic_vector(7 downto 0) := (others => '0');
  signal q_wdat : std_logic_vector(15 downto 0) := (others => '0');
  signal q_data : std_logic_vector(15 downto 0);

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_diag
    port map (
      clk_i => clk, rst_i => rst,
      st_media_ready_i => st_media_ready, st_index_i => st_index, st_track0_i => st_track0,
      st_wprot_i => st_wprot, st_change_i => st_change, st_motor_on_i => st_motor_on,
      st_head_settled_i => st_head_settled, st_locked_i => st_locked, st_head_cyl_i => st_head_cyl,
      rd_done_tgl_i => rd_done_tgl, rd_result_i => rd_result, rd_crc_err_i => rd_crc_err,
      rd_rnf_i => rd_rnf, rd_deleted_i => rd_deleted,
      rd_c_i => rd_c, rd_h_i => rd_h, rd_r_i => rd_r, rd_n_i => rd_n,
      step_ack_tgl_i => step_ack_tgl,
      diag_in_bits_i => diag_in_bits, diag_out_bits_i => diag_out_bits,
      diag_index_period_i => diag_index_period, diag_index_width_i => diag_index_width,
      diag_last_gap_i => diag_last_gap, diag_calc_crc_i => diag_calc_crc,
      diag_stored_crc_i => diag_stored_crc,
      diag_index_edge_i => diag_index_edge, diag_index_qual_i => diag_index_qual,
      diag_id_valid_i => diag_id_valid, diag_id_crc_ok_i => diag_id_crc_ok,
      diag_data_end_i => diag_data_end, diag_data_crc_ok_i => diag_data_crc_ok,
      diag_gap_error_i => diag_gap_error,
      diag_est_i => diag_est,
      diag_rd_phase_i => diag_rd_phase, diag_step_phase_i => diag_step_phase,
      diag_head_valid_i => diag_head_valid, diag_head_dir_out_i => diag_head_dir_out,
      img_drive_busy_i => '0' & img_drive_busy,   -- 2-bit since issue #93 (bit 0 = drive 8)
      rd_req_evt_i => rd_req_evt, rd_req_op_i => rd_req_op,
      rd_req_track_i => rd_req_track, rd_req_sector_i => rd_req_sector,
      rd_req_side_i => rd_req_side,
      dbg_lost_i => dbg_lost, dbg_drain_i => dbg_drain,
      dbg_staledone_i => dbg_staledone, dbg_busycmd_i => dbg_busycmd,
      dbg_fin_i => dbg_fin, dbg_pres_cnt_i => dbg_pres_cnt,
      fifo_level_i => fifo_level, runt_i => runt,
      a1_candidate_i => a1_candidate,
      a1_span_reject_i => a1_span_reject,
      a1_train_i => a1_train,
      mark_fe_i => mark_fe, mark_dam_i => mark_dam,
      dam_unarmed_i => dam_unarmed, match_id_i => match_id,
      dam_miss_i => dam_miss,
      diag_wr_phase_i => diag_wr_phase, diag_wr_session_i => diag_wr_session,
      diag_wr_feed_i => diag_wr_feed, diag_wr_abort_i => diag_wr_abort,
      diag_wr_prec_i => diag_wr_prec, diag_wr_done_i => diag_wr_done,
      diag_wr_last_i => diag_wr_last, diag_wr_bytes_i => diag_wr_bytes,
      diag_wr_first_margin_i => diag_wr_first_margin, diag_wr_trk_cyc_i => diag_wr_trk_cyc,
      diag_wr_gate_i => diag_wr_gate, diag_wr_gate_cyc_i => diag_wr_gate_cyc,
      diag_wr_underrun_i => diag_wr_underrun, diag_wr_discard_i => diag_wr_discard,
      diag_wr_precnt_i => diag_wr_precnt, diag_wr_pushfull_i => diag_wr_pushfull,
      diag_wr_reason_i => diag_wr_reason, diag_wr_reason_acc_i => diag_wr_reason_acc,
      diag_wr_wflags_i => diag_wr_wflags,
      wr_busy_i => wr_busy, wr_ok_i => wr_ok, f_wgate_i => f_wgate, f_wdata_i => f_wdata,
      wr_pop_i => wr_pop, wr_fifo_level_i => wr_fifo_level,
      dbg_wr_fin_i => dbg_wr_fin, dbg_wr_wp_i => dbg_wr_wp, dbg_wr_drop_i => dbg_wr_drop,
      wr_precomp_mode_o => wr_precomp_mode,
      qnice_ce_i => q_ce, qnice_we_i => q_we, qnice_addr_i => q_addr,
      qnice_data_i => q_wdat, qnice_data_o => q_data
    );

  stim : process
    variable fails : integer := 0;
    variable got   : std_logic_vector(15 downto 0);

    procedure rd_reg(addr : integer) is
    begin
      q_addr <= std_logic_vector(to_unsigned(addr, 8));
      q_ce   <= '1';
      wait for 2 ns;                      -- combinational settle
      got := q_data;
    end procedure;

    procedure expect(addr : integer; exp : std_logic_vector(15 downto 0); name : string) is
    begin
      rd_reg(addr);
      if got /= exp then
        report "FAIL " & name & " @0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8)))
             & ": got " & to_hstring(got) & " exp " & to_hstring(exp) severity error;
        fails := fails + 1;
      else
        report "  OK  " & name & " = 0x" & to_hstring(got);
      end if;
    end procedure;

    -- one-clock strobe on a level signal (counted exactly once)
    procedure pulse1(signal s : out std_logic) is
    begin
      s <= '1';
      wait until rising_edge(clk);
      s <= '0';
      wait until rising_edge(clk);
    end procedure;

    -- toggle a handshake line and let the bank see the edge
    procedure toggle(signal s : inout std_logic) is
    begin
      s <= not s;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
    end procedure;

    -- complete a read op with a given result set, latched on rd_done edge
    procedure do_read(res : std_logic_vector(4 downto 0);
                      crc, rnf, del : std_logic;
                      c, h, r, n : integer) is
    begin
      rd_result  <= res;
      rd_crc_err <= crc;
      rd_rnf     <= rnf;
      rd_deleted <= del;
      rd_c <= to_unsigned(c, 8); rd_h <= to_unsigned(h, 8);
      rd_r <= to_unsigned(r, 8); rd_n <= to_unsigned(n, 8);
      rd_done_tgl <= not rd_done_tgl;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
    end procedure;

    -- map v8: one QNICE write cycle (we implies ce)
    procedure q_write(addr : integer; d : std_logic_vector(15 downto 0)) is
    begin
      q_addr <= std_logic_vector(to_unsigned(addr, 8));
      q_wdat <= d;
      q_ce   <= '1';
      q_we   <= '1';
      wait until rising_edge(clk);
      q_we   <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure expect_mode(exp : std_logic_vector(1 downto 0); name : string) is
    begin
      if wr_precomp_mode /= exp then
        report "FAIL " & name & ": wr_precomp_mode_o = " & to_string(wr_precomp_mode)
             & " exp " & to_string(exp) severity error;
        fails := fails + 1;
      else
        report "  OK  " & name & " = " & to_string(wr_precomp_mode);
      end if;
    end procedure;

    -- map v8: a write op as the controller presents it -- the acceptance
    -- strobe with the latched op/C/R (op_r stays put until the next
    -- acceptance) ...
    procedure wr_accept(op : std_logic_vector(2 downto 0); trk, sec : integer) is
    begin
      rd_req_op     <= op;
      rd_req_track  <= to_unsigned(trk, 8);
      rd_req_sector <= to_unsigned(sec, 8);
      wait until rising_edge(clk);
      pulse1(rd_req_evt);
    end procedure;

    -- ... and its completion: the shared done toggle, then one clock later
    -- the controller strobe diag_wr_done_o with the op flags
    procedure wr_finish(res : std_logic_vector(4 downto 0); flags : std_logic_vector(7 downto 0)) is
    begin
      rd_result  <= res;
      rd_crc_err <= '0';
      rd_rnf     <= '0';
      rd_deleted <= '0';
      rd_done_tgl <= not rd_done_tgl;
      wait until rising_edge(clk);
      diag_wr_last <= flags;
      pulse1(diag_wr_done);
      diag_wr_phase   <= "0000";
      diag_wr_session <= '0';
      diag_wr_gate    <= '0';
      wait until rising_edge(clk);
    end procedure;

    -- one consuming write-FIFO pop at a given level, in the current phase
    procedure wr_pop_at(level : integer) is
    begin
      wr_fifo_level <= to_unsigned(level, 3);
      pulse1(wr_pop);
    end procedure;

    variable v_readop, v_cancel, v_trc, v_chrn : std_logic_vector(15 downto 0);
  begin
    -- ---- reset ----------------------------------------------------------
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- ---- static + reset-state reads ------------------------------------
    expect(16#00#, x"1581", "SIGNATURE");
    expect(16#01#, x"08FE", "VERSION/CAP (map v8, bit0 read-only cleared)");
    expect(16#14#, x"0000", "CNT_IDX_RAW_LO(reset)");
    expect(16#29#, x"0000", "TRC_CNT(reset)");
    expect(16#36#, x"0000", "EST(reset input)");
    expect(16#37#, x"0000", "RNF_CTX(reset)");
    expect(16#38#, x"0000", "CNT_A1_CAND(reset)");
    expect(16#39#, x"0000", "CNT_A1_REJECT(reset)");
    expect(16#3A#, x"0000", "CNT_A1_TRAIN(reset)");
    expect(16#3B#, x"0000", "CNT_MARK_FE(reset)");
    expect(16#3C#, x"0000", "CNT_MARK_DAM(reset)");
    expect(16#3D#, x"0000", "CNT_DAM_UNARMED(reset)");
    expect(16#3E#, x"0000", "CNT_MATCH_ID(reset)");
    expect(16#3F#, x"0000", "CNT_DAM_MISS(reset)");

    -- ---- packed live input / output words ------------------------------
    diag_in_bits  <= x"02AA";
    diag_out_bits <= x"0055";   -- bit6 set => phys_active
    wait until rising_edge(clk);
    expect(16#02#, x"02AA", "LIVE_IN");
    expect(16#03#, x"0055", "LIVE_OUT");

    -- ---- controller-state + head words ---------------------------------
    diag_rd_phase   <= "0010";  -- SEARCH
    diag_step_phase <= "01";    -- SETUP
    st_wprot        <= '1';
    st_track0       <= '0';
    st_index        <= '1';
    diag_head_valid <= '1';
    st_change       <= '0';
    st_motor_on     <= '1';
    st_locked       <= '1';
    st_head_settled <= '1';
    st_media_ready  <= '1';
    st_head_cyl     <= x"2A";
    diag_head_dir_out <= '1';
    wait until rising_edge(clk);
    expect(16#04#, x"26EF", "CTRL_STATE");
    expect(16#05#, x"032A", "HEAD");

    -- clear the state levels that could disturb later counter checks
    st_index <= '0'; st_wprot <= '0'; st_media_ready <= '0'; st_locked <= '0';
    st_head_settled <= '0'; st_motor_on <= '0';
    diag_rd_phase <= "0000"; diag_step_phase <= "00";
    wait until rising_edge(clk);

    -- ---- 32-bit saturating counters: index edges -----------------------
    for i in 1 to 5 loop pulse1(diag_index_edge); end loop;
    expect(16#14#, x"0005", "CNT_IDX_RAW_LO=5");
    expect(16#15#, x"0000", "CNT_IDX_RAW_HI=0");

    for i in 1 to 3 loop pulse1(diag_index_qual); end loop;
    expect(16#16#, x"0003", "CNT_IDX_QUAL_LO=3");
    expect(16#14#, x"0005", "CNT_IDX_RAW unchanged by qual");

    -- ---- steps ---------------------------------------------------------
    for i in 1 to 4 loop toggle(step_ack_tgl); end loop;
    expect(16#18#, x"0004", "CNT_STEP_LO=4");

    -- ---- read ops + result latch ---------------------------------------
    do_read(RES_OK, '0', '0', '1', 16#11#, 16#22#, 16#33#, 16#44#);
    expect(16#1A#, x"0001", "CNT_READOP_LO=1");
    expect(16#06#, x"0080", "LAST_RESULT (deleted)");
    expect(16#07#, x"1133", "CHRN_CR");
    expect(16#08#, x"2244", "CHRN_HN");

    do_read(RES_RECORD_NOT_FOUND, '0', '1', '0', 0, 0, 0, 0);
    do_read(RES_DATA_CRC_ERROR,   '1', '0', '0', 0, 0, 0, 0);
    do_read(RES_CANCELLED,        '0', '0', '0', 0, 0, 0, 0);
    expect(16#1A#, x"0004", "CNT_READOP_LO=4");
    expect(16#1C#, x"0001", "CNT_RNF_LO=1");
    expect(16#1E#, x"0001", "CNT_CRCERR_LO=1");
    expect(16#20#, x"0001", "CNT_CANCEL_LO=1");
    expect(16#06#, x"000D", "LAST_RESULT (cancelled)");

    -- a read with an ODD found H: its trace entry must carry the H LSB in
    -- w0 bit 8 (map v4; checked in the trace-ring section below as entry 8)
    do_read(RES_OK, '0', '0', '0', 16#40#, 16#31#, 16#07#, 16#02#);
    expect(16#1A#, x"0005", "CNT_READOP_LO=5");
    expect(16#08#, x"3102", "CHRN_HN (odd H)");

    -- ---- disk-change latch events --------------------------------------
    st_change <= '1'; wait until rising_edge(clk); wait until rising_edge(clk);
    st_change <= '0'; wait until rising_edge(clk); wait until rising_edge(clk);
    st_change <= '1'; wait until rising_edge(clk); wait until rising_edge(clk);
    st_change <= '0'; wait until rising_edge(clk); wait until rising_edge(clk);
    expect(16#22#, x"0002", "CNT_CHANGE_LO=2");

    -- ---- ID + data CRC latches -----------------------------------------
    diag_stored_crc <= x"ABCD";
    diag_calc_crc   <= x"0000";
    diag_id_crc_ok  <= '1';
    pulse1(diag_id_valid);
    expect(16#09#, x"ABCD", "ID_STORED_CRC");
    expect(16#0A#, x"0000", "ID_CALC_CRC");
    expect(16#24#, x"0001", "CNT_IDDEC_LO=1");

    diag_calc_crc    <= x"1234";
    diag_data_crc_ok <= '0';
    pulse1(diag_data_end);
    expect(16#0B#, x"1234", "DATA_CALC_CRC");
    expect(16#0C#, x"0001", "CRC_FLAGS (id_ok=1,data_ok=0)");

    -- ---- index period / width split words ------------------------------
    diag_index_period <= x"0012_3456";
    diag_index_width  <= x"0000_7F00";
    wait until rising_edge(clk);
    expect(16#0D#, x"3456", "IDX_PERIOD_LO");
    expect(16#0E#, x"0012", "IDX_PERIOD_HI");
    expect(16#0F#, x"7F00", "IDX_WIDTH_LO");
    expect(16#10#, x"0000", "IDX_WIDTH_HI");

    -- ---- flux gap last/min/max -----------------------------------------
    diag_last_gap <= to_unsigned(200, 16); wait until rising_edge(clk); wait until rising_edge(clk);
    diag_last_gap <= to_unsigned(300, 16); wait until rising_edge(clk); wait until rising_edge(clk);
    diag_last_gap <= to_unsigned(150, 16); wait until rising_edge(clk); wait until rising_edge(clk);
    diag_last_gap <= to_unsigned(400, 16); wait until rising_edge(clk); wait until rising_edge(clk);
    expect(16#11#, std_logic_vector(to_unsigned(400, 16)), "GAP_LAST=400");
    expect(16#12#, std_logic_vector(to_unsigned(150, 16)), "GAP_MIN=150");
    expect(16#13#, std_logic_vector(to_unsigned(400, 16)), "GAP_MAX=400");

    -- ---- gap-error counter ---------------------------------------------
    pulse1(diag_gap_error);
    pulse1(diag_gap_error);
    expect(16#26#, x"0002", "CNT_GAPERR_LO=2");

    -- ---- image-drive busy word (issue #90 symmetric idle-gate) ----------
    expect(16#28#, x"0000", "IMG_DRIVE idle");
    img_drive_busy <= '1';
    wait until rising_edge(clk);
    expect(16#28#, x"0001", "IMG_DRIVE busy");
    img_drive_busy <= '0';
    wait until rising_edge(clk);
    expect(16#28#, x"0000", "IMG_DRIVE idle again");

    -- ---- WD-dialogue trace ring -----------------------------------------
    -- The 4 step-acks and 5 rd-dones above produced trace entries 0..8:
    -- steps first (dir=1, cyl=0x2A from the CTRL_STATE test), then the reads
    -- (entry 4 = the deleted-flag RES_OK read with C=0x11/R=0x33, entry 7 =
    -- the cancelled read, result 0x0D, entry 8 = the odd-H read whose w0 must
    -- carry the H LSB in bit 8). Add one REQ event and verify layout.
    expect(16#29#, x"0009", "TRC_CNT=9");
    expect(16#40#, x"112A", "TRC[0].w0 (STEP dir=1 cyl=2A)");
    expect(16#41#, x"0000", "TRC[0].w1");
    expect(16#48#, x"3211", "TRC[4].w0 (DONE deleted C=11)");
    expect(16#49#, x"3300", "TRC[4].w1 (R=33 result=OK)");
    expect(16#4E#, x"3000", "TRC[7].w0 (DONE cancelled)");
    expect(16#4F#, x"000D", "TRC[7].w1 (result=CANCELLED)");
    expect(16#50#, x"3140", "TRC[8].w0 (DONE H-lsb=1 C=40)");
    expect(16#51#, x"0700", "TRC[8].w1 (R=07 result=OK)");

    rd_req_op     <= "000";           -- RDOP_READ_SECTOR
    rd_req_track  <= x"27";           -- cylinder 39
    rd_req_sector <= x"05";
    rd_req_side   <= '1';
    pulse1(rd_req_evt);
    expect(16#29#, x"000A", "TRC_CNT=10 after REQ");
    expect(16#52#, x"2127", "TRC[9].w0 (REQ op=0 side=1 track=27)");
    expect(16#53#, x"0500", "TRC[9].w1 (sector=05)");

    -- ---- map v4: FIFO level (live) ---------------------------------------
    expect(16#2A#, x"0000", "FIFO_LEVEL=0");
    fifo_level <= to_unsigned(37, 10);
    wait until rising_edge(clk);
    expect(16#2A#, x"0025", "FIFO_LEVEL=37 (live)");
    fifo_level <= to_unsigned(512, 10);
    wait until rising_edge(clk);
    expect(16#2A#, x"0200", "FIFO_LEVEL=512 (full sector)");
    fifo_level <= (others => '0');
    wait until rising_edge(clk);

    -- ---- map v4: LAST_PRESENT captured on the fin toggle edge ------------
    expect(16#2B#, x"0000", "LAST_PRESENT(reset)");
    dbg_pres_cnt <= to_unsigned(512, 11);
    wait until rising_edge(clk);
    toggle(dbg_fin);
    expect(16#2B#, x"0200", "LAST_PRESENT=512 after fin");
    dbg_pres_cnt <= to_unsigned(6, 11);
    wait until rising_edge(clk);
    expect(16#2B#, x"0200", "LAST_PRESENT held without fin");
    toggle(dbg_fin);
    expect(16#2B#, x"0006", "LAST_PRESENT=6 after 2nd fin");

    -- ---- map v4: delivery-v2 event counters (toggle-coded) ---------------
    toggle(dbg_lost);
    toggle(dbg_lost);
    expect(16#2C#, x"0002", "CNT_LOST_LO=2");
    expect(16#2D#, x"0000", "CNT_LOST_HI=0");
    toggle(dbg_drain);
    expect(16#2E#, x"0001", "CNT_DRAIN_LO=1");
    toggle(dbg_staledone);
    toggle(dbg_staledone);
    toggle(dbg_staledone);
    expect(16#30#, x"0003", "CNT_STALEDONE_LO=3");
    toggle(dbg_busycmd);
    expect(16#32#, x"0001", "CNT_BUSYCMD_LO=1");
    expect(16#2C#, x"0002", "CNT_LOST unchanged by other events");

    -- ---- map v4: runt counter (pulse-coded) ------------------------------
    pulse1(runt);
    pulse1(runt);
    pulse1(runt);
    expect(16#34#, x"0003", "CNT_RUNT_LO=3");
    expect(16#35#, x"0000", "CNT_RUNT_HI=0");

    -- ---- map v5: adaptive quantiser estimate (live word) -----------------
    diag_est <= to_unsigned(16#64D#, 12);   -- 100 + 13/16 cycles in Q8.4
    wait until rising_edge(clk);
    expect(16#36#, x"064D", "EST live (Q8.4 0x64D)");

    -- ---- map v5: last-RNF context ----------------------------------------
    -- The rnf=1 read earlier latched track 0 / sector 0 (its request inputs
    -- were still zero), so the context reads 0x0000 here; a non-RNF read must
    -- not touch it, an RNF read latches requested track (hi) / sector (lo),
    -- and the value then holds across later non-RNF completions.
    rd_req_track  <= x"27";
    rd_req_sector <= x"05";
    wait until rising_edge(clk);
    do_read(RES_OK, '0', '0', '0', 16#27#, 0, 5, 2);
    expect(16#37#, x"0000", "RNF_CTX untouched by non-RNF read");
    do_read(RES_RECORD_NOT_FOUND, '0', '1', '0', 16#27#, 0, 5, 2);
    expect(16#37#, x"2705", "RNF_CTX=trk27/sec05 after RNF");
    rd_req_track  <= x"3E";
    rd_req_sector <= x"01";
    wait until rising_edge(clk);
    do_read(RES_OK, '0', '0', '0', 16#3E#, 0, 1, 2);
    expect(16#37#, x"2705", "RNF_CTX held across later OK read");

    -- ---- map v6: complete-A1 qualifier counters -------------------------
    for i in 1 to 5 loop pulse1(a1_candidate); end loop;
    for i in 1 to 2 loop pulse1(a1_span_reject); end loop;
    for i in 1 to 3 loop pulse1(a1_train); end loop;
    expect(16#38#, x"0005", "CNT_A1_CAND=5");
    expect(16#39#, x"0002", "CNT_A1_REJECT=2");
    expect(16#3A#, x"0003", "CNT_A1_TRAIN=3");

    -- ---- map v7: record-sequencing/acquisition counters ----------------
    for i in 1 to 4 loop pulse1(mark_fe); end loop;
    for i in 1 to 5 loop pulse1(mark_dam); end loop;
    for i in 1 to 2 loop pulse1(dam_unarmed); end loop;
    for i in 1 to 3 loop pulse1(match_id); end loop;
    pulse1(dam_miss);
    expect(16#3B#, x"0004", "CNT_MARK_FE=4");
    expect(16#3C#, x"0005", "CNT_MARK_DAM=5");
    expect(16#3D#, x"0002", "CNT_DAM_UNARMED=2");
    expect(16#3E#, x"0003", "CNT_MATCH_ID=3");
    expect(16#3F#, x"0001", "CNT_DAM_MISS=1");

    -- ---- map v8: reset state of the write words -------------------------
    expect(16#80#, x"1800", "WR_STATE idle (WGATE/WDATA pins high)");
    expect(16#81#, x"0000", "WR_LAST(reset)");
    expect(16#86#, x"0000", "CNT_WR_SECT(reset)");
    expect(16#88#, x"0000", "CNT_WR_TRACK(reset)");
    expect(16#8A#, x"0000", "CNT_WR_GATE(reset)");
    expect(16#8E#, x"0000", "CNT_WR_WP(reset)");
    expect(16#93#, x"0000", "CNT_WR_FIFO_OVF(reset)");
    expect(16#96#, x"00FF", "WR_FIRST_MARGIN(reset: none)");
    expect(16#97#, x"00FF", "WR_DRQ_MARGIN(reset: none)");
    expect(16#9A#, x"0000", "WR_CTRL(reset)");
    expect(16#9B#, x"0000", "CNT_WR_FIN(reset)");
    expect_mode("00", "precomp mode (reset: follow P)");

    -- ---- map v8: WR_CTRL, the one writable word ---------------------------
    q_write(16#9A#, x"0002");
    expect(16#9A#, x"0002", "WR_CTRL=2 (precomp on)");
    expect_mode("10", "precomp mode after WR_CTRL=2");
    q_write(16#9A#, x"FFFD");
    expect(16#9A#, x"0001", "WR_CTRL keeps bits 1:0 only");
    expect_mode("01", "precomp mode after WR_CTRL=1");
    q_write(16#86#, x"1234");
    expect(16#86#, x"0000", "write to a counter word is ignored");
    expect(16#9A#, x"0001", "WR_CTRL untouched by a write elsewhere");
    q_write(16#9A#, x"0000");
    expect(16#9A#, x"0000", "WR_CTRL=0 (follow P)");
    expect_mode("00", "precomp mode back to follow P");

    -- ---- map v8: CTRL_STATE write codes (bits 15:12) ----------------------
    -- base: head estimate valid (bit 5) and phys_active (bit 6) are still set
    expect(16#04#, x"0060", "CTRL_STATE base");
    diag_rd_phase <= "0010";          -- the controller shows a write search as 0010
    rd_req_op     <= "100";           -- Write Sector
    diag_wr_phase <= "0010";
    wait until rising_edge(clk);
    expect(16#04#, x"9060", "CTRL_STATE write search -> 0x9 (not a read)");
    diag_wr_phase <= "0001"; wait until rising_edge(clk);
    expect(16#04#, x"8060", "CTRL_STATE write wait -> 0x8");
    diag_wr_phase <= "0100"; wait until rising_edge(clk);
    expect(16#04#, x"A060", "CTRL_STATE write stream -> 0xA");
    diag_wr_phase <= "0110"; wait until rising_edge(clk);
    expect(16#04#, x"B060", "CTRL_STATE write abort -> 0xB");
    rd_req_op     <= "101";           -- Write Track
    diag_wr_phase <= "0111"; wait until rising_edge(clk);
    expect(16#04#, x"D060", "CTRL_STATE track arm -> 0xD");
    diag_wr_phase <= "1000"; wait until rising_edge(clk);
    expect(16#04#, x"E060", "CTRL_STATE track stream -> 0xE");
    diag_wr_phase <= "0000"; wr_busy <= '1'; wait until rising_edge(clk);
    expect(16#04#, x"F060", "CTRL_STATE writer still busy after the op -> 0xF");
    wr_busy <= '0'; diag_rd_phase <= "0011"; wait until rising_edge(clk);
    expect(16#04#, x"3060", "CTRL_STATE back to the read phase");
    diag_rd_phase <= "0000"; rd_req_op <= "000";
    wait until rising_edge(clk);

    -- ---- map v8: WR_STATE packing -----------------------------------------
    diag_wr_phase <= "0100"; diag_wr_session <= '1'; diag_wr_feed <= '1';
    diag_wr_prec <= '1'; wr_ok <= '1'; f_wgate <= '0'; f_wdata <= '1';
    wr_busy <= '1'; diag_wr_gate <= '1';
    wait until rising_edge(clk);
    expect(16#80#, x"17A4", "WR_STATE streaming (writer state 2)");
    diag_wr_wflags <= "00100"; wait until rising_edge(clk);
    expect(16#80#, x"17B4", "WR_STATE discarding (writer state 3)");
    diag_wr_wflags <= "00110"; wait until rising_edge(clk);
    expect(16#80#, x"17C4", "WR_STATE aborted (writer state 4)");
    diag_wr_wflags <= "00000"; diag_wr_gate <= '0'; diag_wr_abort <= '1';
    wait until rising_edge(clk);
    expect(16#80#, x"5794", "WR_STATE armed + abort level (writer state 1)");
    diag_wr_phase <= "0000"; diag_wr_session <= '0'; diag_wr_feed <= '0';
    diag_wr_prec <= '0'; wr_ok <= '0'; f_wgate <= '1'; diag_wr_abort <= '0';
    wr_busy <= '0';
    wait until rising_edge(clk);
    expect(16#80#, x"1800", "WR_STATE idle again");

    -- ---- map v8: op 1, a completed Write Sector with WGATE -----------------
    rd_reg(16#1A#); v_readop := got;
    rd_reg(16#20#); v_cancel := got;
    rd_reg(16#29#); v_trc    := got;
    rd_reg(16#07#); v_chrn   := got;
    rd_c <= x"27"; rd_h <= x"01"; rd_r <= x"05"; rd_n <= x"02";   -- found ID (odd H)
    wr_accept("100", 16#27#, 16#05#);
    diag_wr_phase <= "0001"; wait until rising_edge(clk);
    diag_wr_phase <= "0010"; wait until rising_edge(clk);
    diag_wr_phase <= "0011"; diag_wr_first_margin <= to_unsigned(22, 8);
    wait until rising_edge(clk);
    diag_wr_phase <= "0100"; diag_wr_session <= '1'; diag_wr_gate <= '1';
    wait until rising_edge(clk);
    wr_pop_at(3);
    wr_pop_at(2);
    wr_pop_at(4);
    diag_wr_phase <= "0101"; diag_wr_gate <= '0'; diag_wr_session <= '0';
    wr_pop_at(1);                     -- a drain pop in the tail: not a DRQ sample
    diag_wr_gate_cyc <= to_unsigned(849_600, 32);
    diag_wr_precnt   <= to_unsigned(1819, 16);
    diag_wr_bytes    <= to_unsigned(512, 16);
    wr_finish(RES_OK, x"81");         -- completed + precomp
    expect(16#86#, x"0001", "CNT_WR_SECT=1");
    expect(16#88#, x"0000", "CNT_WR_TRACK=0");
    expect(16#8A#, x"0001", "CNT_WR_GATE=1");
    expect(16#83#, x"F6C0", "WR_GATE_CYC_LO (849600)");
    expect(16#84#, x"000C", "WR_GATE_CYC_HI");
    expect(16#81#, x"8100", "WR_LAST (completed, precomp, reason 0)");
    expect(16#82#, x"0527", "WR_LAST_CHR (R=05 C=27)");
    expect(16#85#, x"0200", "WR_BYTES_LAST=512");
    expect(16#95#, x"071B", "WR_PRECOMP_CNT=1819");
    expect(16#96#, x"0016", "WR_FIRST_MARGIN=22");
    expect(16#97#, x"0002", "WR_DRQ_MARGIN=2 (tail drain not sampled)");
    expect(16#80#, x"3800", "WR_STATE idle, H of the last sector op = 1");
    expect(16#1A#, v_readop, "CNT_READOP untouched by a write op");
    expect(16#07#, v_chrn,   "CHRN_CR (last read) untouched by a write op");
    expect(16#29#, std_logic_vector(unsigned(v_trc) + 2), "TRC_CNT +2 (write REQ + DONE traced)");

    -- ---- map v8: write-protect refusals, WD pre-check and controller -------
    toggle(dbg_wr_wp);
    expect(16#8E#, x"0001", "CNT_WR_WP=1 (WD pre-check)");
    wr_accept("100", 16#28#, 16#01#);
    diag_wr_phase <= "0001"; wait until rising_edge(clk);
    wr_finish(RES_WRITE_PROTECTED, x"08");
    expect(16#8E#, x"0002", "CNT_WR_WP=2 (+ controller WR_WAIT refusal)");
    expect(16#86#, x"0002", "CNT_WR_SECT=2 (cumulative)");
    expect(16#8A#, x"0001", "CNT_WR_GATE still 1 (no gate in a refusal)");
    expect(16#83#, x"0000", "WR_GATE_CYC_LO=0 for an op without a gate");
    expect(16#95#, x"0000", "WR_PRECOMP_CNT=0 for an op without a session");
    expect(16#81#, x"0800", "WR_LAST (wp-refused)");
    expect(16#82#, x"0128", "WR_LAST_CHR (R=01 C=28)");
    expect(16#97#, x"00FF", "WR_DRQ_MARGIN reset at the op start (no pop)");
    expect(16#96#, x"0016", "WR_FIRST_MARGIN is a minimum since reset");

    -- ---- map v8: op 3, a sector with a lost byte ----------------------------
    wr_accept("100", 16#28#, 16#02#);
    diag_wr_phase <= "0011"; diag_wr_first_margin <= to_unsigned(19, 8);
    wait until rising_edge(clk);
    diag_wr_phase <= "0100"; diag_wr_session <= '1'; diag_wr_gate <= '1';
    wait until rising_edge(clk);
    wr_pop_at(1);
    wr_finish(RES_OK, x"03");         -- completed + lost
    expect(16#8C#, x"0001", "CNT_WR_LOST=1");
    expect(16#97#, x"0000", "WR_DRQ_MARGIN=0 after a lost byte");
    expect(16#96#, x"0013", "WR_FIRST_MARGIN=19 (new minimum)");
    expect(16#8A#, x"0002", "CNT_WR_GATE=2");
    expect(16#86#, x"0003", "CNT_WR_SECT=3");

    -- ---- map v8: op 4, a Write Track ------------------------------------------
    wr_accept("101", 16#28#, 16#00#);
    diag_wr_phase <= "0111"; wait until rising_edge(clk);
    expect(16#04#, x"D060", "CTRL_STATE track arm during a track op");
    diag_wr_phase <= "1000"; diag_wr_session <= '1'; diag_wr_gate <= '1';
    wait until rising_edge(clk);
    wr_pop_at(4);
    wr_pop_at(3);
    diag_wr_first_margin <= to_unsigned(5, 8);      -- must not count for a track op
    diag_wr_trk_cyc <= to_unsigned(9_990_000, 32);
    wr_finish(RES_OK, x"21");         -- completed + track
    expect(16#88#, x"0001", "CNT_WR_TRACK=1");
    expect(16#86#, x"0003", "CNT_WR_SECT unchanged by a track op");
    expect(16#8A#, x"0003", "CNT_WR_GATE=3");
    expect(16#82#, x"0228", "WR_LAST_CHR unchanged by a track op");
    expect(16#96#, x"0013", "WR_FIRST_MARGIN unchanged by a track op");
    expect(16#97#, x"0003", "WR_DRQ_MARGIN=3 (track stream pops)");
    expect(16#98#, x"6F70", "WR_TRK_CYC_LO (9990000)");
    expect(16#99#, x"0098", "WR_TRK_CYC_HI");

    -- ---- map v8: op 5, an aborted sector (Force Interrupt) ---------------------
    wr_accept("100", 16#10#, 16#03#);
    diag_wr_phase <= "0100"; diag_wr_session <= '1';
    wait until rising_edge(clk);
    diag_wr_phase <= "0110"; diag_wr_reason <= x"80";
    wait until rising_edge(clk);
    wr_finish(RES_CANCELLED, x"04");  -- aborted
    expect(16#90#, x"0001", "CNT_WR_ABORT=1");
    expect(16#81#, x"0480", "WR_LAST (aborted, reason 0x80)");
    expect(16#20#, v_cancel, "CNT_CANCEL (reads) untouched by a cancelled write");
    expect(16#1A#, v_readop, "CNT_READOP still untouched after five write ops");
    expect(16#8E#, x"0002", "CNT_WR_WP unchanged");

    -- ---- map v8: WD-side toggles and writer pass-through words ---------------
    toggle(dbg_wr_drop);
    toggle(dbg_wr_drop);
    expect(16#93#, x"0002", "CNT_WR_FIFO_OVF=2");
    toggle(dbg_wr_fin); toggle(dbg_wr_fin); toggle(dbg_wr_fin);
    expect(16#9B#, x"0003", "CNT_WR_FIN=3");
    diag_wr_underrun <= to_unsigned(5, 16);
    diag_wr_reason_acc <= x"84";
    diag_wr_pushfull <= to_unsigned(7, 16);
    diag_wr_discard  <= to_unsigned(9, 16);
    wait until rising_edge(clk);
    expect(16#94#, x"0005", "CNT_WR_UNDERRUN (writer)");
    expect(16#92#, x"0084", "WR_REASON_ACC (writer)");
    expect(16#9C#, x"0007", "WR_PUSHFULL (writer)");
    expect(16#9D#, x"0009", "WR_DISCARD (writer)");
    expect(16#9E#, x"0000", "reserved word 0x9E reads 0");

    -- ---- verdict -------------------------------------------------------
    if fails = 0 then
      report "physical_1581_diag: ALL TESTS PASSED";
    else
      report "physical_1581_diag: " & integer'image(fails) & " FAILURES" severity failure;
    end if;
    finish;
  end process;

end architecture sim;
