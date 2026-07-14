-------------------------------------------------------------------------------
-- tb_physical_1581_diag.vhd
--
-- Stand-alone unit test of physical_1581_diag (the read-only QNICE diagnostic
-- register bank, issue #90). It drives known diagnostic inputs and event
-- strobes, reads every documented register word over the QNICE read interface,
-- and asserts:
--   * the signature (x"1581") and version/capability word,
--   * the packed live-input / live-output words,
--   * the controller-state and head words (bit packing),
--   * the latched last-result + found C/H/R/N,
--   * the latched ID/data CRCs and the CRC-flags word,
--   * the index period / width split words and the last/min/max flux gap, and
--   * every 32-bit saturating counter (index raw / qualified, steps, read ops,
--     RNFs, CRC errors, cancellations, disk changes, decoded IDs, gap errors).
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

  -- map v4 delivery-v2 observability inputs
  signal dbg_lost      : std_logic := '0';
  signal dbg_drain     : std_logic := '0';
  signal dbg_staledone : std_logic := '0';
  signal dbg_busycmd   : std_logic := '0';
  signal dbg_fin       : std_logic := '0';
  signal dbg_pres_cnt  : unsigned(10 downto 0) := (others => '0');
  signal fifo_level    : unsigned(9 downto 0) := (others => '0');
  signal runt          : std_logic := '0';

  -- QNICE read interface
  signal q_ce   : std_logic := '0';
  signal q_addr : std_logic_vector(7 downto 0) := (others => '0');
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
      diag_rd_phase_i => diag_rd_phase, diag_step_phase_i => diag_step_phase,
      diag_head_valid_i => diag_head_valid, diag_head_dir_out_i => diag_head_dir_out,
      img_drive_busy_i => img_drive_busy,
      rd_req_evt_i => rd_req_evt, rd_req_op_i => rd_req_op,
      rd_req_track_i => rd_req_track, rd_req_sector_i => rd_req_sector,
      rd_req_side_i => rd_req_side,
      dbg_lost_i => dbg_lost, dbg_drain_i => dbg_drain,
      dbg_staledone_i => dbg_staledone, dbg_busycmd_i => dbg_busycmd,
      dbg_fin_i => dbg_fin, dbg_pres_cnt_i => dbg_pres_cnt,
      fifo_level_i => fifo_level, runt_i => runt,
      qnice_ce_i => q_ce, qnice_addr_i => q_addr, qnice_data_o => q_data
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
  begin
    -- ---- reset ----------------------------------------------------------
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- ---- static + reset-state reads ------------------------------------
    expect(16#00#, x"1581", "SIGNATURE");
    expect(16#01#, x"043F", "VERSION/CAP");
    expect(16#14#, x"0000", "CNT_IDX_RAW_LO(reset)");
    expect(16#29#, x"0000", "TRC_CNT(reset)");
    expect(16#36#, x"0000", "RESERVED");

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

    -- ---- verdict -------------------------------------------------------
    if fails = 0 then
      report "physical_1581_diag: ALL TESTS PASSED";
    else
      report "physical_1581_diag: " & integer'image(fails) & " FAILURES" severity failure;
    end if;
    finish;
  end process;

end architecture sim;
