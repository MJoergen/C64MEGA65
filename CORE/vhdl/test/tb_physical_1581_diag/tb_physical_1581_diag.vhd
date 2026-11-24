-------------------------------------------------------------------------------
-- tb_physical_1581_diag.vhd
--
-- Stand-alone unit test of physical_1581_diag (the QNICE diagnostic register
-- bank, issue #90; map v8 write instruments issue #244; map v9 read-ahead
-- counters and spin-up time issue #257; map v10 index gap, stale READY and
-- decoder tolerance, issue #257 part E). It drives known
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
--     the read-op counters and the last-read latches alone,
--   * map v9: the two read-ahead counters (count, saturate, leave each other
--     alone) and the spin-up time: reset values, the measurement from the last
--     rising edge of the motor-on level to the first index edge after it, the
--     previous value while a measurement runs, later index edges ignored, the
--     maximum, the saturation at FFFE and an index edge in the clock of the
--     motor edge. The main instance counts 10 clocks per millisecond
--     (G_MS_CYC) so that the saturation is reachable; a second instance with
--     the production default checks the real scale of 50,000 clocks.
--   * map v10 (issue #257 part E): IDX_GAP_MAX_MS (the largest time between
--     two motor-qualified index edges with the motor-on level high in every
--     clock between them: truncated milliseconds, the maximum kept, no result
--     across a motor-off clock, saturation at FFFF, both scales, and a
--     measurement during which READY rises and falls: the word does not
--     depend on READY), CNT_RDY_STALE (a fall of READY with the motor-on
--     level high counts; a fall together with the motor-on level, as the
--     controller makes it on reset, disable and motor off, does not;
--     saturation; a write to it is ignored), CNT_TOL_HIT (count, saturation;
--     the strobe changes no other word of the map), RD_CTRL (bit 0 only, its
--     output, independent of WR_CTRL; its write decode: a read cycle with any
--     data on the bus does not write it, nor do writes to its neighbours and
--     to the eight addresses one bit away, and a write to it leaves WR_CTRL
--     and the precompensation mode alone), the unused words 0xA6 to 0xFF
--     read 0 while the words of map v10 are not 0, and that a reset clears
--     all four words.
--
-- Purely combinational reads and same-clock counters => no timing subtlety; the
-- whole run is a few tens of milliseconds of sim time.
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

  -- map v9 read-ahead strobes
  signal diag_rd_ahead, diag_rd_ahead_drop : std_logic := '0';

  -- map v10: decoder tolerance strobe and switch
  signal tol_hit     : std_logic := '0';
  signal dec_tol_off : std_logic;

  -- QNICE interface
  signal q_ce   : std_logic := '0';
  signal q_we   : std_logic := '0';
  signal q_addr : std_logic_vector(7 downto 0) := (others => '0');
  signal q_wdat : std_logic_vector(15 downto 0) := (others => '0');
  signal q_data : std_logic_vector(15 downto 0);

  -- second instance (production G_MS_CYC): its own read port
  signal q2_addr : std_logic_vector(7 downto 0) := (others => '0');
  signal q2_data : std_logic_vector(15 downto 0);

begin

  clk <= not clk after 10 ns;   -- 50 MHz

  dut : entity work.physical_1581_diag
    generic map (G_MS_CYC => 10)        -- 10 clocks per "millisecond": the spin-up saturation is reachable
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
      dam_miss_i => dam_miss, tol_hit_i => tol_hit,
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
      diag_rd_ahead_i => diag_rd_ahead, diag_rd_ahead_drop_i => diag_rd_ahead_drop,
      wr_precomp_mode_o => wr_precomp_mode, dec_tol_off_o => dec_tol_off,
      qnice_ce_i => q_ce, qnice_we_i => q_we, qnice_addr_i => q_addr,
      qnice_data_i => q_wdat, qnice_data_o => q_data
    );

  -- The production scale of the spin-up time (G_MS_CYC default = 50,000
  -- clocks per millisecond): a second bank on the same motor and index
  -- inputs. Only its spin-up words are read.
  dut_ms : entity work.physical_1581_diag
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
      wr_precomp_mode_o => open,
      qnice_ce_i => '1', qnice_addr_i => q2_addr, qnice_data_o => q2_data
    );

  stim : process
    type word_arr_t is array (0 to 255) of std_logic_vector(15 downto 0);
    type int_arr_t is array (natural range <>) of integer;
    -- map v10: the neighbours of RD_CTRL (0xA5) and the addresses one bit away from it (bits 0 to 7)
    constant C_RD_CTRL_NEAR : int_arr_t := (16#A3#, 16#A4#, 16#A6#, 16#A7#,
                                            16#A1#, 16#AD#, 16#B5#, 16#85#, 16#E5#, 16#25#);
    variable fails : integer := 0;
    variable got   : std_logic_vector(15 downto 0);
    variable snap  : word_arr_t;          -- map v10: every word of the map, for "nothing else changed"

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

    -- map v9: read a word of the second instance (production G_MS_CYC)
    procedure expect2(addr : integer; exp : std_logic_vector(15 downto 0); name : string) is
    begin
      q2_addr <= std_logic_vector(to_unsigned(addr, 8));
      wait for 2 ns;
      if q2_data /= exp then
        report "FAIL " & name & " @0x" & to_hstring(std_logic_vector(to_unsigned(addr, 8)))
             & ": got " & to_hstring(q2_data) & " exp " & to_hstring(exp) severity error;
        fails := fails + 1;
      else
        report "  OK  " & name & " = 0x" & to_hstring(q2_data);
      end if;
    end procedure;

    procedure clkw(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    -- map v9: the motor-on level rises; the first motor-qualified index edge
    -- is sampled n clocks after the clock that sampled the motor edge, so the
    -- bank has counted n - 1 full clocks: (n - 1) / G_MS_CYC milliseconds
    procedure spin_up(n : natural) is
    begin
      st_motor_on <= '0';
      clkw(2);
      st_motor_on <= '1';
      clkw(n);
      pulse1(diag_index_qual);
    end procedure;

    -- map v10: the next motor-qualified index edge, sampled n clocks after the
    -- previous one (which pulse1 sampled one clock before it returned): the
    -- bank has counted n - 1 full clocks, (n - 1) / G_MS_CYC milliseconds
    procedure idx_gap(n : natural) is
    begin
      clkw(n - 2);
      pulse1(diag_index_qual);
    end procedure;

    procedure expect_tol(exp : std_logic; name : string) is
    begin
      if dec_tol_off /= exp then
        report "FAIL " & name & ": dec_tol_off_o = " & std_logic'image(dec_tol_off)
             & " exp " & std_logic'image(exp) severity error;
        fails := fails + 1;
      else
        report "  OK  " & name & " = " & std_logic'image(dec_tol_off);
      end if;
    end procedure;

    -- map v10: a QNICE read cycle of n clocks (ce high, we low) with the
    -- given value on the write data bus
    procedure q_read_cycle(addr : integer; d : std_logic_vector(15 downto 0); n : natural) is
    begin
      q_addr <= std_logic_vector(to_unsigned(addr, 8));
      q_wdat <= d;
      q_ce   <= '1';
      q_we   <= '0';
      clkw(n);
    end procedure;

    -- map v10: every word of the map into snap ...
    procedure take_snap is
    begin
      for a in 0 to 255 loop
        rd_reg(a);
        snap(a) := got;
      end loop;
    end procedure;

    -- ... and every word but one compared with it
    procedure expect_snap(skip : integer; name : string) is
      variable bad : integer := 0;
    begin
      for a in 0 to 255 loop
        if a /= skip then
          rd_reg(a);
          if got /= snap(a) then
            report "FAIL " & name & " @0x" & to_hstring(std_logic_vector(to_unsigned(a, 8)))
                 & ": got " & to_hstring(got) & " exp " & to_hstring(snap(a)) severity error;
            fails := fails + 1;
            bad   := bad + 1;
          end if;
        end if;
      end loop;
      if bad = 0 then
        report "  OK  " & name & " (255 words)";
      end if;
    end procedure;

    -- map v10: every word of an address range reads 0
    procedure expect_zero(lo, hi : integer; name : string) is
      variable bad : integer := 0;
    begin
      for a in lo to hi loop
        rd_reg(a);
        if got /= x"0000" then
          report "FAIL " & name & " @0x" & to_hstring(std_logic_vector(to_unsigned(a, 8)))
               & ": got " & to_hstring(got) & " exp 0000" severity error;
          fails := fails + 1;
          bad   := bad + 1;
        end if;
      end loop;
      if bad = 0 then
        report "  OK  " & name;
      end if;
    end procedure;

    variable v_readop, v_cancel, v_trc, v_chrn : std_logic_vector(15 downto 0);
    variable v_keep, v_other : std_logic_vector(15 downto 0);
  begin
    -- ---- reset ----------------------------------------------------------
    rst <= '1';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- ---- static + reset-state reads ------------------------------------
    expect(16#00#, x"1581", "SIGNATURE");
    expect(16#01#, x"0AFE", "VERSION/CAP (map v10, bit0 read-only cleared)");
    expect(16#9E#, x"0000", "CNT_RD_AHEAD(reset)");
    expect(16#9F#, x"0000", "CNT_RD_AHEAD_DROP(reset)");
    expect(16#A0#, x"FFFF", "SPINUP_LAST_MS(reset: no measurement yet)");
    expect(16#A1#, x"0000", "SPINUP_MAX_MS(reset)");
    expect(16#A2#, x"0000", "IDX_GAP_MAX_MS(reset: no measurement yet)");
    expect(16#A3#, x"0000", "CNT_RDY_STALE(reset)");
    expect(16#A4#, x"0000", "CNT_TOL_HIT(reset)");
    expect(16#A5#, x"0000", "RD_CTRL(reset)");
    expect_tol('0', "decoder tolerance on after reset");
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

    -- ---- map v9: read-ahead counters --------------------------------------
    for i in 1 to 9 loop pulse1(diag_rd_ahead); end loop;
    for i in 1 to 2 loop pulse1(diag_rd_ahead_drop); end loop;
    expect(16#9E#, x"0009", "CNT_RD_AHEAD=9");
    expect(16#9F#, x"0002", "CNT_RD_AHEAD_DROP=2");
    diag_rd_ahead <= '1';               -- one count per clock: past the 16-bit range
    clkw(65_540);
    diag_rd_ahead <= '0';
    wait until rising_edge(clk);
    expect(16#9E#, x"FFFF", "CNT_RD_AHEAD saturates at FFFF");
    expect(16#9F#, x"0002", "CNT_RD_AHEAD_DROP untouched by the other counter");
    diag_rd_ahead_drop <= '1';
    clkw(65_540);
    diag_rd_ahead_drop <= '0';
    wait until rising_edge(clk);
    expect(16#9F#, x"FFFF", "CNT_RD_AHEAD_DROP saturates at FFFF");

    -- ---- map v9: spin-up time (10 clocks per millisecond in this bank) -----
    spin_up(535);
    expect(16#A0#, x"0035", "SPINUP_LAST_MS=53 (534 full clocks)");
    expect(16#A1#, x"0035", "SPINUP_MAX_MS=53");
    for i in 1 to 3 loop               -- the index edges of the following revolutions
      clkw(25);
      pulse1(diag_index_qual);
    end loop;
    clkw(40);
    expect(16#A0#, x"0035", "SPINUP_LAST_MS: only the first index edge counts");
    expect(16#A1#, x"0035", "SPINUP_MAX_MS: only the first index edge counts");
    st_motor_on <= '0';
    clkw(30);
    expect(16#A0#, x"0035", "SPINUP_LAST_MS held with the motor off");
    st_motor_on <= '1';
    clkw(60);
    expect(16#A0#, x"0035", "SPINUP_LAST_MS shows the previous value while a measurement runs");
    clkw(65);
    pulse1(diag_index_qual);            -- sampled 125 clocks after the motor edge: 124 full clocks
    expect(16#A0#, x"000C", "SPINUP_LAST_MS=12");
    expect(16#A1#, x"0035", "SPINUP_MAX_MS keeps the larger value");
    -- the time counts from the LAST rising edge of the motor level
    st_motor_on <= '0';
    clkw(2);
    st_motor_on <= '1';
    clkw(300);
    spin_up(51);
    expect(16#A0#, x"0005", "SPINUP_LAST_MS=5 from the last motor edge, not 35");
    spin_up(7005);
    expect(16#A0#, x"02BC", "SPINUP_LAST_MS=700");
    expect(16#A1#, x"02BC", "SPINUP_MAX_MS=700");
    -- saturation: no index edge for more than 0xFFFE milliseconds
    spin_up(655_500);
    expect(16#A0#, x"FFFE", "SPINUP_LAST_MS saturates at FFFE");
    expect(16#A1#, x"FFFE", "SPINUP_MAX_MS saturates with it");
    -- an index edge in the clock of the motor edge itself: 0 ms
    st_motor_on <= '0';
    clkw(2);
    st_motor_on <= '1';
    pulse1(diag_index_qual);
    expect(16#A0#, x"0000", "SPINUP_LAST_MS=0 for an index edge in the clock of the motor edge");
    expect(16#A1#, x"FFFE", "SPINUP_MAX_MS unchanged by a shorter measurement");
    -- the production scale (second instance, 50,000 clocks per millisecond):
    -- 125,009 full clocks are 2 ms there and 12,500 ms in the scaled bank; the
    -- 655,499 clocks of the saturation run were 13 ms
    spin_up(125_010);
    expect(16#A0#, x"30D4", "SPINUP_LAST_MS=12500 (scaled bank)");
    expect2(16#A0#, x"0002", "SPINUP_LAST_MS=2 at 50,000 clocks per millisecond");
    expect2(16#A1#, x"000D", "SPINUP_MAX_MS=13 at 50,000 clocks per millisecond");
    expect2(16#01#, x"0AFE", "VERSION of the second instance");
    st_motor_on <= '0';
    wait until rising_edge(clk);

    -- ---- map v10: IDX_GAP_MAX_MS (10 clocks per millisecond in this bank) --
    -- the index edges after the first spin-up of the v9 section came 27
    -- clocks apart with the motor on: 26 full clocks, 2 ms
    expect(16#A2#, x"0002", "IDX_GAP_MAX_MS=2 from the index edges of the v9 section");
    st_motor_on <= '1';
    clkw(3);
    pulse1(diag_index_qual);            -- starts a measurement
    idx_gap(400);
    expect(16#A2#, x"0027", "IDX_GAP_MAX_MS=39 (399 full clocks)");
    idx_gap(201);
    expect(16#A2#, x"0027", "IDX_GAP_MAX_MS keeps the larger value (20 ms measured)");
    idx_gap(1001);
    expect(16#A2#, x"0064", "IDX_GAP_MAX_MS=100");
    -- the motor-on level low in one clock between two edges: neither the
    -- 200 ms across it nor the 150 ms before it are a result, and the edge
    -- after it starts a measurement
    clkw(1500);
    st_motor_on <= '0';
    wait until rising_edge(clk);
    st_motor_on <= '1';
    clkw(500);
    pulse1(diag_index_qual);
    expect(16#A2#, x"0064", "IDX_GAP_MAX_MS: no result across a motor-off clock");
    idx_gap(1801);
    expect(16#A2#, x"00B4", "IDX_GAP_MAX_MS=180 from the edge after the motor-off clock");
    -- saturation, and the production scale of the second instance: 655,399
    -- full clocks are 65,539 ms here and 13 ms there
    idx_gap(655_400);
    expect(16#A2#, x"FFFF", "IDX_GAP_MAX_MS saturates at FFFF");
    expect2(16#A2#, x"000D", "IDX_GAP_MAX_MS=13 at 50,000 clocks per millisecond");
    st_motor_on <= '0';
    wait until rising_edge(clk);

    -- ---- map v10: CNT_RDY_STALE --------------------------------------------
    -- READY and the motor-on level fell in the same clock in the state-word
    -- section above (as the controller lowers them on reset, disable and
    -- with the motor request): no count
    expect(16#A3#, x"0000", "CNT_RDY_STALE: a fall together with the motor-on level");
    st_motor_on <= '1'; st_media_ready <= '1';
    clkw(3);
    st_media_ready <= '0';              -- the 500 ms rule: READY falls, the motor stays on
    clkw(3);
    expect(16#A3#, x"0001", "CNT_RDY_STALE=1 (READY fell with the motor on)");
    st_media_ready <= '1';
    clkw(3);
    st_media_ready <= '0'; st_motor_on <= '0';
    clkw(3);
    expect(16#A3#, x"0001", "CNT_RDY_STALE: READY fell together with the motor-on level");
    st_media_ready <= '1';
    clkw(3);
    st_media_ready <= '0';              -- READY falls while the motor is off
    clkw(3);
    st_motor_on <= '1';                 -- a rise of the motor-on level alone
    clkw(3);
    expect(16#A3#, x"0001", "CNT_RDY_STALE: a fall with the motor off, a motor edge");
    for i in 1 to 65_540 loop           -- one fall every two clocks: past the 16-bit range
      st_media_ready <= '1';
      wait until rising_edge(clk);
      st_media_ready <= '0';
      wait until rising_edge(clk);
    end loop;
    clkw(2);
    expect(16#A3#, x"FFFF", "CNT_RDY_STALE saturates at FFFF");
    st_motor_on <= '0';
    wait until rising_edge(clk);

    -- ---- map v10: CNT_TOL_HIT -----------------------------------------------
    -- the strobe counts here and nowhere else (CNT_IDDEC, CNT_A1_TRAIN and
    -- CNT_MARK_FE keep their meaning): every other word is compared after
    -- the saturation run below
    take_snap;
    for i in 1 to 7 loop pulse1(tol_hit); end loop;
    expect(16#A4#, x"0007", "CNT_TOL_HIT=7");
    expect(16#A3#, x"FFFF", "CNT_RDY_STALE untouched by the tolerance strobe");
    tol_hit <= '1';                     -- one count per clock: past the 16-bit range
    clkw(65_540);
    tol_hit <= '0';
    wait until rising_edge(clk);
    expect(16#A4#, x"FFFF", "CNT_TOL_HIT saturates at FFFF");
    expect_snap(16#A4#, "every other word unchanged by 65,547 tolerance strobes");

    -- ---- map v10: RD_CTRL, the second writable word ------------------------
    expect(16#A5#, x"0000", "RD_CTRL still 0");
    q_write(16#A5#, x"0001");
    expect(16#A5#, x"0001", "RD_CTRL=1 (tolerance off)");
    expect_tol('1', "decoder tolerance off after RD_CTRL=1");
    q_write(16#9A#, x"0002");
    expect(16#A5#, x"0001", "RD_CTRL untouched by a write to WR_CTRL");
    expect_tol('1', "decoder tolerance still off after a write to WR_CTRL");
    q_write(16#A5#, x"FFFE");
    expect(16#A5#, x"0000", "RD_CTRL keeps bit 0 only");
    expect_tol('0', "decoder tolerance on after RD_CTRL=FFFE");
    expect(16#9A#, x"0002", "WR_CTRL untouched by a write to RD_CTRL");
    expect_mode("10", "precomp mode untouched by a write to RD_CTRL");
    q_write(16#A5#, x"0003");
    expect(16#A5#, x"0001", "RD_CTRL=1 again");
    -- a write to RD_CTRL leaves WR_CTRL and the precompensation mode alone,
    -- with data whose bits 1:0 differ from WR_CTRL
    q_write(16#9A#, x"0002");
    q_write(16#A5#, x"0001");
    expect(16#A5#, x"0001", "RD_CTRL=1 written with bits 1:0 = 01");
    expect(16#9A#, x"0002", "WR_CTRL=2 untouched by a write of 0001 to RD_CTRL");
    expect_mode("10", "precomp mode 10 untouched by a write of 0001 to RD_CTRL");
    q_write(16#9A#, x"0001");
    q_write(16#A5#, x"0002");
    expect(16#A5#, x"0000", "RD_CTRL=0 written with bits 1:0 = 10");
    expect(16#9A#, x"0001", "WR_CTRL=1 untouched by a write of 0002 to RD_CTRL");
    expect_mode("01", "precomp mode 01 untouched by a write of 0002 to RD_CTRL");
    q_write(16#9A#, x"0000");
    -- a read cycle of RD_CTRL does not write it, whatever is on the data bus
    q_write(16#A5#, x"0001");
    q_read_cycle(16#A5#, x"0000", 8);
    expect(16#A5#, x"0001", "RD_CTRL=1 kept through a read cycle with 0000 on the data bus");
    expect_tol('1', "decoder tolerance still off after a read cycle of RD_CTRL");
    q_write(16#A5#, x"0000");
    q_read_cycle(16#A5#, x"FFFF", 8);
    expect(16#A5#, x"0000", "RD_CTRL=0 kept through a read cycle with FFFF on the data bus");
    expect_tol('0', "decoder tolerance still on after a read cycle of RD_CTRL");
    -- the write decode compares all eight address bits: writes of the other
    -- value to the neighbours 0xA3 to 0xA7 and to the eight addresses one
    -- bit away from 0xA5 leave RD_CTRL and WR_CTRL alone
    for v in 0 to 1 loop                -- RD_CTRL at 1, then at 0; each write carries the other bit 0
      if v = 0 then
        v_keep := x"0001"; v_other := x"0000";
      else
        v_keep := x"0000"; v_other := x"FFFF";
      end if;
      for i in C_RD_CTRL_NEAR'range loop
        q_write(16#A5#, v_keep);
        q_write(C_RD_CTRL_NEAR(i), v_other);
        expect(16#A5#, v_keep, "RD_CTRL=" & to_hstring(v_keep) & " untouched by a write of "
               & to_hstring(v_other) & " to 0x"
               & to_hstring(std_logic_vector(to_unsigned(C_RD_CTRL_NEAR(i), 8))));
      end loop;
    end loop;
    expect(16#9A#, x"0000", "WR_CTRL untouched by the writes around RD_CTRL");
    q_write(16#A5#, x"0001");
    q_write(16#A4#, x"1234");
    expect(16#A4#, x"FFFF", "a write to CNT_TOL_HIT is ignored");
    q_write(16#A2#, x"0000");
    expect(16#A2#, x"FFFF", "a write to IDX_GAP_MAX_MS is ignored");
    q_write(16#A3#, x"0000");
    expect(16#A3#, x"FFFF", "a write to CNT_RDY_STALE is ignored");
    -- the unused words after the map read 0 while the four words are not 0
    expect_zero(16#A6#, 16#FF#, "unused words 0xA6 to 0xFF read 0 with the words of map v10 at FFFF, FFFF, FFFF, 0001");
    q_write(16#9A#, x"0000");

    -- ---- map v10: a reset clears the four words ----------------------------
    rst <= '1';
    clkw(2);
    rst <= '0';
    wait until rising_edge(clk);
    expect(16#A2#, x"0000", "IDX_GAP_MAX_MS cleared by reset");
    expect(16#A3#, x"0000", "CNT_RDY_STALE cleared by reset");
    expect(16#A4#, x"0000", "CNT_TOL_HIT cleared by reset");
    expect(16#A5#, x"0000", "RD_CTRL cleared by reset");
    expect_tol('0', "decoder tolerance on after a reset");
    expect2(16#A2#, x"0000", "IDX_GAP_MAX_MS of the second instance cleared by reset");

    -- ---- map v10: the index gap does not depend on READY -------------------
    -- READY low at the start edge, high from 50 ms, low again from 150 ms
    -- (the 500 ms rule: the motor stays on), the end edge 2501 clocks after
    -- the start edge: 250 ms, and the fall counts as a stale READY
    st_media_ready <= '0';
    st_motor_on    <= '1';
    clkw(3);
    pulse1(diag_index_qual);            -- starts a measurement
    clkw(500);
    st_media_ready <= '1';
    clkw(1000);
    st_media_ready <= '0';
    idx_gap(1001);
    expect(16#A2#, x"00FA", "IDX_GAP_MAX_MS=250 although READY rose and fell during the measurement");
    expect(16#A3#, x"0001", "CNT_RDY_STALE=1: the fall of READY during the measurement");
    st_motor_on <= '0';
    wait until rising_edge(clk);

    expect(16#A6#, x"0000", "reserved word 0xA6 reads 0");

    -- ---- verdict -------------------------------------------------------
    if fails = 0 then
      report "physical_1581_diag: ALL TESTS PASSED";
    else
      report "physical_1581_diag: " & integer'image(fails) & " FAILURES" severity failure;
    end if;
    finish;
  end process;

end architecture sim;
