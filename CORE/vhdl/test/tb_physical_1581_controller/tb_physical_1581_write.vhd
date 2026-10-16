-------------------------------------------------------------------------------
-- tb_physical_1581_write.vhd
--
-- Closed-loop write test of physical_1581_controller (issue #244, WRITE-SPEC
-- 10.1): controller (with its MFM encoder and writer) + physical_1581_rdfifo
-- (read bytes, drive side) + physical_1581_wfifo (write bytes: write side on
-- a 31.5 MHz drive clock, read side on the 50 MHz controller clock) + a
-- drive-side model + mech_model_1581 with G_WRITABLE = true (the live
-- rotating flux store). Everything that reaches the disk goes through the
-- real encoder and writer; everything read back goes through the real
-- decoder.
--
-- Drive-side model: issues WD-style requests over the toggle ABI with 2-bit
-- sequence tags (the done tag is checked per op and monitored for stability)
-- and feeds the write FIFO like the 1581 DOS: wait for DRQ (= feed level,
-- 2-FF synchronized into the drive clock, and FIFO not full, and fewer than
-- 512 bytes accepted for a sector), wait the DRQ service latency, write one
-- byte. A stall mode holds byte k until the drive-side FIFO level reads 0
-- plus an extra delay (W9), a late-first mode delays byte 0 (W8).
--
-- Monitors over the whole run: rd_done_seq only changes with a rd_done
-- toggle; WGATE is low and the feed level is high only while a write op is
-- outstanding (W13: never during a read); the model fatally asserts WDATA low
-- while WGATE is high; the writer's refused-push and underrun counters must
-- stay 0.
--
-- Scenario groups (generic G_GROUP; each group is its own run so they can run
-- in parallel; each one starts from power-up):
--   1  reads on the store model (W13), W1, W10
--   2  W2 (the DOS side flush) with DRQ service latency G_LAT_US
--   3  W4 (write protect), W5 (disk change), W6 (Force Interrupt)
--   4  W7 (drive reset), W8 (first byte late), W9 (one byte 40 us late)
--   5  W3 (Write Track, stock DOS token stream), W12 (index loss)
-- Every writing scenario re-seeds the track with its own seed key (a payload
-- that differs from the one written) and asserts positively that WGATE
-- opened and that no seed edge survives inside the written span.
--
-- Files written into the working directory for wr_twin.py:
--   wr_g<group>_l<lat>_flux_<tag>.txt   track dumps (mech_model_1581)
--   wr_g<group>_l<lat>_stream_<tag>.txt the byte/token streams of the writes
--
-- Run (B = absolute scratch workdir, from a scratch directory; analysis order
-- as in tb_mech_model_1581 plus inputs, rdfifo, wfifo, encoder, writer,
-- controller):
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_write \
--     -gG_GROUP=1 --assert-level=error
--   python3 CORE/vhdl/test/tb_physical_1581_controller/wr_twin.py \
--     --stream wr_g1_l15_stream_1.txt --dump wr_g1_l15_flux_1.txt
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.physical_1581_pkg.all;
use work.golden_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;

entity tb_physical_1581_write is
  generic (
    G_GROUP  : integer := 1;
    G_LAT_US : integer := 15     -- drive-CPU DRQ service latency
  );
end entity;

architecture sim of tb_physical_1581_write is
  constant C_DCLK_HALF : time := 15_859 ps;    -- 31.527 MHz drive clock
  constant C_PREFIX    : string := "wr_g" & integer'image(G_GROUP) & "_l" & integer'image(G_LAT_US) & "_";

  signal clk    : std_logic := '0';
  signal dclk   : std_logic := '0';
  signal rst    : std_logic := '1';

  -- controller <-> mechanism pins
  signal f_rdata, f_index, f_track0, f_wprot, f_change : std_logic;
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;
  signal f_wgate, f_wdata : std_logic;

  -- controller ABI
  signal phys_active   : std_logic := '0';
  signal cia_motor_on  : std_logic := '0';
  signal cia_side      : std_logic := '1';     -- '1' = logical side 0
  signal step_req      : std_logic := '0';
  signal step_outward  : std_logic := '0';
  signal step_ack      : std_logic;
  signal rd_req        : std_logic := '0';
  signal rd_op         : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_track      : unsigned(7 downto 0) := (others => '0');
  signal rd_side       : std_logic := '1';
  signal rd_sector     : unsigned(7 downto 0) := (others => '0');
  signal rd_seq        : std_logic_vector(1 downto 0) := "00";
  signal rd_cancel     : std_logic := '0';
  signal rd_done       : std_logic;
  signal rd_done_seq   : std_logic_vector(1 downto 0);
  signal rd_result     : std_logic_vector(4 downto 0);
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);
  signal wr_deleted    : std_logic := '0';
  signal wr_precomp    : std_logic := '0';
  signal wr_pmode      : std_logic_vector(1 downto 0) := "00";
  signal wr_feed, wr_lost, wr_busy, wr_ok : std_logic;

  -- read bytes: controller -> rdfifo -> drive-side capture
  signal byte_data : unsigned(7 downto 0);
  signal byte_wr   : std_logic;
  signal rf_full   : std_logic;
  signal rf_rd     : std_logic;
  signal rf_data   : unsigned(7 downto 0);
  signal rf_empty  : std_logic;

  -- write bytes: drive-side feeder -> wfifo -> controller
  signal wf_wr     : std_logic := '0';
  signal wf_din    : std_logic_vector(7 downto 0) := (others => '0');
  signal wf_full   : std_logic;
  signal wf_wlevel : unsigned(2 downto 0);
  signal wf_rd     : std_logic;
  signal wf_dout   : std_logic_vector(7 downto 0);
  signal wf_empty  : std_logic;
  signal wf_rlevel : unsigned(2 downto 0);

  signal st_media_ready, st_index, st_track0, st_wprot, st_change : std_logic;
  signal st_motor_on, st_head_settled, st_locked : std_logic;
  signal st_head_cyl : unsigned(7 downto 0);

  -- controller diag taps used here
  signal d_id_valid, d_match_id : std_logic;
  signal d_wr_phase   : std_logic_vector(3 downto 0);
  signal d_wr_session, d_wr_done, d_wr_gate : std_logic;
  signal d_wr_last    : std_logic_vector(7 downto 0);
  signal d_wr_bytes   : unsigned(15 downto 0);
  signal d_wr_margin  : unsigned(7 downto 0);
  signal d_wr_trk_cyc : unsigned(31 downto 0);
  signal d_wr_gate_cyc: unsigned(31 downto 0);
  signal d_wr_words   : unsigned(15 downto 0);
  signal d_wr_underrun, d_wr_discard, d_wr_gateopen, d_wr_wabort : unsigned(15 downto 0);
  signal d_wr_precnt, d_wr_pushfull : unsigned(15 downto 0);
  signal d_wr_reason, d_wr_reason_acc : std_logic_vector(7 downto 0);
  signal d_wr_wflags  : std_logic_vector(4 downto 0);

  -- mechanism model
  signal cfg_wprot   : std_logic := '0';
  signal cfg_change  : std_logic := '0';
  signal cfg_present : std_logic := '1';
  signal cur_cyl     : integer;
  signal m_trk_cyl, m_trk_side : integer := 0;
  signal m_seed_req, m_dump_req, m_q_req : std_logic := '0';
  signal m_seed_key, m_dump_tag, m_q_from, m_q_len : integer := 0;
  signal m_q_ack     : std_logic;
  signal m_q_seed, m_q_new : integer;
  signal m_pos, m_trev, m_wg_opens, m_wg_open_pos, m_wg_len, m_wg_closed : integer;
  signal m_pw_min, m_pw_max, m_pw_count : integer;

  -- read capture (drive side)
  type cap_t is array (0 to 16383) of unsigned(7 downto 0);
  signal cap     : cap_t := (others => (others => '0'));
  signal cap_idx : integer := 0;

  -- feeder control (written by stim, read by the drive-side feeder)
  type buf_t is array (0 to 8191) of std_logic_vector(7 downto 0);
  signal fd_buf     : buf_t := (others => (others => '0'));
  signal fd_go      : natural := 0;          -- bump: start a new op
  signal fd_n       : natural := 512;        -- bytes to deliver (DRQ count)
  signal fd_lat     : natural := 0;          -- drive clocks from DRQ to the write
  signal fd_lat0    : natural := 0;          -- the same for byte 0
  signal fd_stall_k : natural := 99999;      -- byte held until the FIFO level is 0
  signal fd_stall_x : natural := 0;          -- extra drive clocks after that
  signal fd_force   : boolean := false;      -- write even if the feed fell meanwhile
  signal fd_sent    : natural := 0;          -- bytes written so far (this op)
  signal feed_m, feed_s : std_logic := '0';  -- 2-FF sync of wr_feed into dclk

  -- monitors
  signal wr_outstanding : boolean := false;  -- a write op is between request and done
  signal gate_falls     : natural := 0;
  signal gate_fall_t    : time := 0 ns;
  signal gate_rise_t    : time := 0 ns;
  signal idv_pos        : integer := 0;      -- model position at the last id_valid
  signal match_pos      : integer := 0;      -- model position at the last ID match
  signal fails          : natural := 0;

  function hs(v : unsigned) return string is
  begin return to_hstring(std_logic_vector(v)); end function;
  function hs(v : std_logic_vector) return string is
  begin return to_hstring(v); end function;

  -- payload written by the bench: differs from every seed payload
  function wpay(tag, secn, off : integer) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned((tag * 53 + secn * 17 + off * 11 + 16#A5#) mod 256, 8));
  end function;
begin

  clk  <= not clk  after 10 ns;          -- 50 MHz, phase-aligned with the model timebase
  dclk <= not dclk after C_DCLK_HALF;

  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE        => true,
      G_READY_WD_CYC   => 150_000_000,     -- 3 s
      G_SEARCH_EDGES   => 3,
      G_PERIOD_MAX_CYC => 12_500_000
    )
    port map (
      clk_i => clk, rst_i => rst,
      f_rdata_i => f_rdata, f_index_i => f_index, f_track0_i => f_track0,
      f_writeprotect_i => f_wprot, f_diskchanged_i => f_change,
      f_motora_o => f_motora, f_selecta_o => f_selecta, f_side1_o => f_side1,
      f_stepdir_o => f_stepdir, f_step_o => f_step, f_density_o => f_density,
      f_wgate_o => f_wgate, f_wdata_o => f_wdata,
      phys_active_i => phys_active, cia_motor_on_i => cia_motor_on, cia_side_i => cia_side,
      step_req_tgl_i => step_req, step_outward_i => step_outward, step_ack_tgl_o => step_ack,
      rd_req_tgl_i => rd_req, rd_op_i => rd_op, rd_track_i => rd_track, rd_side_i => rd_side,
      rd_sector_i => rd_sector, rd_seq_i => rd_seq, rd_cancel_tgl_i => rd_cancel,
      rd_done_tgl_o => rd_done, rd_done_seq_o => rd_done_seq,
      rd_result_o => rd_result, rd_crc_err_o => rd_crc_err, rd_rnf_o => rd_rnf,
      rd_deleted_o => rd_deleted, rd_c_o => rd_c, rd_h_o => rd_h, rd_r_o => rd_r, rd_n_o => rd_n,
      byte_data_o => byte_data, byte_wr_o => byte_wr, byte_ovf_i => rf_full,
      wr_deleted_i => wr_deleted, wr_precomp_i => wr_precomp, wr_precomp_mode_i => wr_pmode,
      wbyte_data_i => wf_dout, wbyte_empty_i => wf_empty, wbyte_rd_o => wf_rd,
      wr_feed_o => wr_feed, wr_lost_o => wr_lost, wr_busy_o => wr_busy, wr_ok_o => wr_ok,
      st_media_ready_o => st_media_ready, st_index_o => st_index, st_track0_o => st_track0,
      st_wprot_o => st_wprot, st_change_o => st_change, st_motor_on_o => st_motor_on,
      st_head_settled_o => st_head_settled, st_head_cyl_o => st_head_cyl, st_locked_o => st_locked,
      diag_id_valid_o => d_id_valid, diag_match_id_o => d_match_id,
      diag_wr_phase_o => d_wr_phase, diag_wr_session_o => d_wr_session,
      diag_wr_done_o => d_wr_done, diag_wr_last_o => d_wr_last, diag_wr_bytes_o => d_wr_bytes,
      diag_wr_first_margin_o => d_wr_margin, diag_wr_trk_cyc_o => d_wr_trk_cyc,
      diag_wr_gate_o => d_wr_gate, diag_wr_gate_cyc_o => d_wr_gate_cyc,
      diag_wr_words_last_o => d_wr_words, diag_wr_underrun_o => d_wr_underrun,
      diag_wr_discard_o => d_wr_discard, diag_wr_gateopen_o => d_wr_gateopen,
      diag_wr_wabort_o => d_wr_wabort, diag_wr_precnt_o => d_wr_precnt,
      diag_wr_pushfull_o => d_wr_pushfull, diag_wr_reason_o => d_wr_reason,
      diag_wr_reason_acc_o => d_wr_reason_acc, diag_wr_wflags_o => d_wr_wflags
    );

  i_rfifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 6)
    port map (
      wr_clk_i => clk, wr_rst_i => rst, wr_en_i => byte_wr, wr_data_i => byte_data, wr_full_o => rf_full,
      rd_clk_i => dclk, rd_rst_i => rst, rd_en_i => rf_rd, rd_data_o => rf_data, rd_empty_o => rf_empty
    );

  i_wfifo : entity work.physical_1581_wfifo
    generic map (G_DW => 8, G_AW => 2)
    port map (
      wr_clk_i => dclk, wr_rst_i => rst, wr_en_i => wf_wr, wr_data_i => wf_din,
      wr_full_o => wf_full, wr_level_o => wf_wlevel,
      rd_clk_i => clk, rd_rst_i => rst, rd_en_i => wf_rd, rd_data_o => wf_dout,
      rd_empty_o => wf_empty, rd_level_o => wf_rlevel
    );

  i_mech : entity work.mech_model_1581
    generic map (G_INDEX_PERIOD => 200 ms, G_INDEX_LOW => 2 ms, G_NUM_CYL => 80,
                 G_WRITABLE => true, G_DUMP_PREFIX => C_PREFIX & "flux_")
    port map (
      f_motora_i => f_motora, f_selecta_i => f_selecta, f_side1_i => f_side1,
      f_stepdir_i => f_stepdir, f_step_i => f_step, f_density_i => f_density,
      cfg_present_i => cfg_present, cfg_wprot_i => cfg_wprot, cfg_change_i => cfg_change,
      f_index_o => f_index, f_track0_o => f_track0, f_writeprotect_o => f_wprot,
      f_diskchanged_o => f_change, f_rdata_o => f_rdata,
      f_wgate_i => f_wgate, f_wdata_i => f_wdata,
      trk_cyl_i => m_trk_cyl, trk_side_i => m_trk_side,
      seed_req_i => m_seed_req, seed_key_i => m_seed_key,
      dump_req_i => m_dump_req, dump_tag_i => m_dump_tag,
      q_req_i => m_q_req, q_from_i => m_q_from, q_len_i => m_q_len,
      q_ack_o => m_q_ack, q_seed_o => m_q_seed, q_new_o => m_q_new,
      cur_cyl_o => cur_cyl, pos_o => m_pos, t_rev_o => m_trev,
      wg_opens_o => m_wg_opens, wg_open_pos_o => m_wg_open_pos, wg_len_o => m_wg_len,
      wg_closed_o => m_wg_closed,
      pw_min_o => m_pw_min, pw_max_o => m_pw_max, pw_count_o => m_pw_count
    );

  -- rd_done_seq may only change on a clock edge where rd_done toggles too
  tag_mon : process (clk)
    variable prev_tag  : std_logic_vector(1 downto 0) := "00";
    variable prev_done : std_logic := '0';
  begin
    if rising_edge(clk) then
      assert (rd_done_seq = prev_tag) or (rd_done /= prev_done)
        report "FAIL: rd_done_seq changed without a rd_done toggle" severity error;
      prev_tag  := rd_done_seq;
      prev_done := rd_done;
    end if;
  end process;

  -- W13: WGATE and the feed level only while a write op is outstanding
  gate_mon : process (clk)
    variable g_p : std_logic := '1';
  begin
    if rising_edge(clk) then
      if f_wgate = '0' and g_p = '1' then
        gate_falls  <= gate_falls + 1;
        gate_fall_t <= now;
        assert wr_outstanding report "FAIL: WGATE opened outside a write op" severity error;
      elsif f_wgate = '1' and g_p = '0' then
        gate_rise_t <= now;
      end if;
      g_p := f_wgate;
      assert wr_feed = '0' or wr_outstanding
        report "FAIL: wr_feed high outside a write op" severity error;
      if d_id_valid = '1' then idv_pos <= m_pos; end if;
      if d_match_id = '1' then match_pos <= m_pos; end if;
    end if;
  end process;

  -- greedy drive-side drain of the read FIFO into cap[]
  rf_rd <= not rf_empty;
  drain : process (dclk)
  begin
    if rising_edge(dclk) then
      if rf_empty = '0' then
        cap(cap_idx) <= rf_data;
        cap_idx <= cap_idx + 1;
      end if;
    end if;
  end process;

  -- drive-side feeder: the 1581 DOS transfer loop over DRQ
  feed_sync : process (dclk)
  begin
    if rising_edge(dclk) then
      feed_m <= wr_feed; feed_s <= feed_m;
    end if;
  end process;

  feeder : process
    variable go_seen : natural := 0;
    variable idx     : natural;
    variable lat     : natural;
    variable stop    : boolean;
  begin
    wf_wr <= '0';
    wait until rising_edge(dclk);
    if fd_go /= go_seen then
      go_seen := fd_go;
      idx  := 0;
      stop := false;
      fd_sent <= 0;
      while idx < fd_n and not stop loop
        -- DRQ: feed level, FIFO room
        loop
          wait until rising_edge(dclk);
          if fd_go /= go_seen then stop := true; exit; end if;
          exit when feed_s = '1' and wf_full = '0';
        end loop;
        exit when stop;
        if idx = fd_stall_k then
          -- W9: the byte is held until the FIFO has run dry, then later still
          loop
            wait until rising_edge(dclk);
            exit when wf_wlevel = 0;
          end loop;
          for i in 1 to fd_stall_x loop wait until rising_edge(dclk); end loop;
        end if;
        if idx = 0 then lat := fd_lat0; else lat := fd_lat; end if;
        for i in 1 to lat loop
          wait until rising_edge(dclk);
          if fd_go /= go_seen then stop := true; exit; end if;
        end loop;
        exit when stop;
        if feed_s = '1' or fd_force then
          wf_din <= fd_buf(idx);
          wf_wr  <= '1';
          wait until rising_edge(dclk);
          wf_wr  <= '0';
          idx := idx + 1;
          fd_sent <= idx;
        end if;
        if fd_force and feed_s = '0' then stop := true; end if;
      end loop;
    end if;
  end process;

  stim : process
    variable seq_cnt   : unsigned(1 downto 0) := "00";
    variable prev_done : std_logic := '0';
    variable prev_ack  : std_logic;
    variable base      : integer;
    variable exp       : buf_t;
    variable r0, s, s1 : integer;
    variable g0, n0    : integer;
    variable t0, t1    : time;
    variable lat_cyc   : integer;
    variable splice, declat, len : integer;
    variable wopen     : integer;
    file     sf        : text;
    variable sl        : line;

    procedure clkw(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    function nxt(r : integer) return integer is      -- sector after r (1..10)
    begin
      return (r mod 10) + 1;
    end function;

    function us2d(us : natural) return natural is    -- microseconds -> drive clocks
    begin
      return us * 31527 / 1000;
    end function;

    -- model store requests -------------------------------------------------
    procedure m_ack(a : std_logic) is
    begin
      wait until m_q_ack /= a for 10 ms;
      assert m_q_ack /= a report "FAIL: model request not acknowledged" severity failure;
    end procedure;
    procedure m_seed(c, sd, key : integer) is
      variable a : std_logic;
    begin
      m_trk_cyl <= c; m_trk_side <= sd; m_seed_key <= key;
      wait until rising_edge(clk);
      a := m_q_ack; m_seed_req <= not m_seed_req; m_ack(a);
    end procedure;
    procedure m_dump(c, sd, tag : integer) is
      variable a : std_logic;
    begin
      m_trk_cyl <= c; m_trk_side <= sd; m_dump_tag <= tag;
      wait until rising_edge(clk);
      a := m_q_ack; m_dump_req <= not m_dump_req; m_ack(a);
    end procedure;
    procedure m_query(c, sd, from, n : integer) is
      variable a : std_logic;
    begin
      m_trk_cyl <= c; m_trk_side <= sd; m_q_from <= from; m_q_len <= n;
      wait until rising_edge(clk);
      a := m_q_ack; m_q_req <= not m_q_req; m_ack(a);
      wait until rising_edge(clk);
    end procedure;

    -- requests over the toggle ABI --------------------------------------
    procedure req(op : std_logic_vector(2 downto 0); trk, secn : integer;
                  del, prec : std_logic) is
    begin
      rd_op <= op; rd_track <= to_unsigned(trk, 8); rd_sector <= to_unsigned(secn, 8);
      rd_side <= '1'; wr_deleted <= del; wr_precomp <= prec;
      seq_cnt := seq_cnt + 1;
      rd_seq  <= std_logic_vector(seq_cnt);
      if op = WROP_WRITE_SECTOR or op = WROP_WRITE_TRACK then
        wr_outstanding <= true;
      end if;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      prev_done := rd_done;
      rd_req <= not rd_req;
    end procedure;
    procedure wait_done(tmo : time) is
    begin
      wait until rd_done /= prev_done for tmo;
      assert rd_done /= prev_done report "FAIL: TIMEOUT waiting for rd_done" severity failure;
      assert rd_done_seq = std_logic_vector(seq_cnt)
        report "FAIL: done tag " & to_hstring("00" & unsigned(rd_done_seq)) & " expected "
             & to_hstring("00" & seq_cnt) severity error;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      wr_outstanding <= false;
    end procedure;
    procedure expect(res : std_logic_vector(4 downto 0); what : string) is
    begin
      assert rd_result = res
        report "FAIL: " & what & ": result " & hs(rd_result) & " expected " & hs(res) severity error;
    end procedure;

    procedure do_step(outward : std_logic) is
    begin
      step_outward <= outward;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      prev_ack := step_ack;
      step_req <= not step_req;
      wait until step_ack /= prev_ack for 1 sec;
      assert step_ack /= prev_ack report "FAIL: TIMEOUT waiting for step_ack" severity failure;
    end procedure;

    -- Read Address: returns the R of the next ID under the head
    procedure read_addr(trk : integer; r : out integer) is
    begin
      base := cap_idx;
      req(RDOP_READ_ADDRESS, trk, 0, '0', '0');
      wait_done(1 sec);
      expect(RES_OK, "Read Address");
      wait for 20 us;                              -- the 6 reply bytes cross the read FIFO
      assert cap_idx - base = 6
        report "FAIL: Read Address delivered " & integer'image(cap_idx - base) & " bytes" severity error;
      assert rd_c = to_unsigned(trk, 8) and rd_n = x"02"
        report "FAIL: Read Address C/N = " & hs(rd_c) & "/" & hs(rd_n) severity error;
      r := to_integer(rd_r);
    end procedure;

    -- Read Sector and compare 512 bytes against exp
    procedure read_check(trk, secn : integer; what : string) is
      variable bad : integer := 0;
    begin
      base := cap_idx;
      req(RDOP_READ_SECTOR, trk, secn, '0', '0');
      wait_done(1 sec);
      expect(RES_OK, what & " read-back");
      wait for 200 us;
      assert cap_idx - base = 512
        report "FAIL: " & what & ": " & integer'image(cap_idx - base) & " bytes read" severity error;
      for i in 0 to 511 loop
        if std_logic_vector(cap(base + i)) /= exp(i) then
          if bad < 4 then
            report "FAIL: " & what & ": byte " & integer'image(i) & " = " & hs(cap(base + i))
                 & " expected " & hs(exp(i)) severity error;
          end if;
          bad := bad + 1;
        end if;
      end loop;
      assert bad = 0 report "FAIL: " & what & ": " & integer'image(bad) & " bytes differ" severity error;
      report "  " & what & ": sector " & integer'image(secn) & " read back byte-exact (512 bytes, CRC ok)";
    end procedure;

    procedure exp_wpay(tag, secn : integer) is
    begin
      for i in 0 to 511 loop exp(i) := wpay(tag, secn, i); end loop;
    end procedure;
    procedure exp_seed(key, c, sd, secn : integer) is
    begin
      for i in 0 to 511 loop exp(i) := std_logic_vector(seed_payload(key, c, sd, secn, i)); end loop;
    end procedure;

    -- start a Write Sector with the feeder loaded from exp
    procedure write_start(trk, secn : integer; del, prec : std_logic; lat_us : natural) is
    begin
      for i in 0 to 511 loop fd_buf(i) <= exp(i); end loop;
      fd_n <= 512; fd_lat <= us2d(lat_us); fd_lat0 <= us2d(lat_us);
      wait until rising_edge(clk);
      fd_go <= fd_go + 1;
      wait until rising_edge(clk);
      req(WROP_WRITE_SECTOR, trk, secn, del, prec);
    end procedure;

    -- the stream section of the last write for wr_twin.py
    procedure stream_sector(tag : integer; prec : std_logic; dam : string) is
    begin
      file_open(sf, C_PREFIX & "stream_" & integer'image(tag) & ".txt", append_mode);
      write(sl, string'("S gen=") & integer'image(m_wg_opens) & " kind=sector precomp="
            & std_logic'image(prec)(2) & " dam=" & dam);
      writeline(sf, sl);
      write(sl, string'("D "));
      for i in 0 to 511 loop write(sl, to_hstring(exp(i))); end loop;
      writeline(sf, sl);
      file_close(sf);
    end procedure;

    -- the common write checks: the gate opened once, the window, no seed edge
    -- survives inside it, edges were written
    procedure check_window(what : string; full : boolean) is
    begin
      assert gate_falls = g0 + 1
        report "FAIL: " & what & ": WGATE opened " & integer'image(gate_falls - g0) & " times" severity error;
      if full then
        assert abs (m_wg_len - 849_600) <= 100
          report "FAIL: " & what & ": WGATE window " & integer'image(m_wg_len) & " cycles" severity error;
        assert to_integer(d_wr_gate_cyc) = 849_600
          report "FAIL: " & what & ": writer gate cycles " & integer'image(to_integer(d_wr_gate_cyc)) severity error;
      end if;
      m_query(m_trk_cyl, 0, m_wg_open_pos, m_wg_len);
      assert m_q_seed = 0
        report "FAIL: " & what & ": " & integer'image(m_q_seed) & " seed edges survive in the written span" severity error;
      assert m_q_new > 0
        report "FAIL: " & what & ": no written edges in the span" severity error;
      report "  " & what & ": WGATE window " & integer'image(m_wg_len) & " cycles at pos "
           & integer'image(m_wg_open_pos) & ", " & integer'image(m_q_new) & " new edges, 0 seed edges in the span";
    end procedure;

    procedure startup is
    begin
      rst <= '1'; wait for 500 ns; rst <= '0'; wait for 500 ns;
      phys_active <= '1'; cia_motor_on <= '1'; cia_side <= '1';
      wait for 50 us;
      do_step('1');                                -- Restore: head at track 0
      wait until st_media_ready = '1' for 2 sec;
      assert st_media_ready = '1' report "FAIL: media never ready" severity failure;
      wait until st_head_settled = '1' for 100 ms;
      if wr_ok /= '1' then wait until wr_ok = '1' for 100 ms; end if;
      assert wr_ok = '1' report "FAIL: tab never qualified" severity failure;
      report "startup: media ready, head settled, tab qualified at " & time'image(now);
    end procedure;

    -- mid-sector abort helper: start a write of the next sector, wait until
    -- the gate has been open for `into`
    procedure write_next_and_wait_gate(trk, key, tag : integer; into : time) is
    begin
      m_seed(trk, 0, key);
      read_addr(trk, r0);
      s := nxt(r0);
      exp_wpay(tag, s);
      g0 := gate_falls;
      write_start(trk, s, '0', '0', G_LAT_US);
      wait until f_wgate = '0' for 400 ms;
      assert f_wgate = '0' report "FAIL: WGATE never opened" severity failure;
      wait for into;
    end procedure;

    procedure check_truncated(what : string; wopen_p, len_p : integer) is
    begin
      assert len_p > 1600 and len_p < 849_600
        report "FAIL: " & what & ": window " & integer'image(len_p) & " not truncated" severity error;
      m_query(m_trk_cyl, 0, wopen_p, len_p);
      assert m_q_seed = 0 and m_q_new > 0
        report "FAIL: " & what & ": span seed/new " & integer'image(m_q_seed) & "/" & integer'image(m_q_new) severity error;
      -- the rest of the old data field after the cut is untouched
      m_query(m_trk_cyl, 0, wopen_p + len_p + 100, 849_600 - len_p - 200);
      assert m_q_new = 0 and m_q_seed > 0
        report "FAIL: " & what & ": after the cut seed/new " & integer'image(m_q_seed) & "/" & integer'image(m_q_new) severity error;
      report "  " & what & ": truncated window " & integer'image(len_p) & " cycles; old flux intact after the cut ("
           & integer'image(m_q_seed) & " seed edges)";
    end procedure;
  begin
    startup;
    lat_cyc := us2d(G_LAT_US);

    -------------------------------------------------------------------------
    if G_GROUP = 1 then
    -------------------------------------------------------------------------
      -- W13 on the store model: reads only, WGATE must stay high (gate_mon)
      read_addr(0, r0);
      s := nxt(r0);
      exp_seed(0, 0, 0, s);
      read_check(0, s, "W13 golden seed");
      assert gate_falls = 0 report "FAIL: W13: WGATE moved during reads" severity error;

      -- W1: one Write Sector, then read it back through the real decoder
      m_seed(0, 0, 3);
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(1, s);
      g0 := gate_falls;
      write_start(0, s, '0', '0', G_LAT_US);
      wait_done(1 sec);
      expect(RES_OK, "W1 write");
      assert wr_lost = '0' report "FAIL: W1: LOST flag" severity error;
      check_window("W1", true);
      stream_sector(1, '0', "FB");
      splice := (m_wg_open_pos - seed_id_crc_end(s)) mod m_trev;
      declat := (match_pos - 1 - seed_id_crc_end(s)) mod m_trev;
      report "  W1: ID CRC end -> id_valid " & integer'image(declat) & " cycles; ID CRC end -> WGATE "
           & integer'image(splice) & " cycles = " & integer'image(splice / 1600) & " byte-times + "
           & integer'image(splice mod 1600) & " cycles (target 35200)";
      assert abs (splice - 22 * 1600) <= 1600
        report "FAIL: W1: splice " & integer'image(splice) & " cycles after the ID CRC" severity error;
      assert m_pw_min = 25 and m_pw_max = 25
        report "FAIL: W1: WDATA pulse widths " & integer'image(m_pw_min) & ".." & integer'image(m_pw_max) severity error;
      assert to_integer(d_wr_margin) >= 18
        report "FAIL: W1: first-byte margin " & integer'image(to_integer(d_wr_margin)) severity error;
      report "  W1: first-byte margin " & integer'image(to_integer(d_wr_margin)) & " byte-times, "
           & integer'image(m_pw_count) & " WDATA pulses of 25 cycles";
      -- the following ID is intact
      read_addr(0, r0);
      assert r0 = nxt(s) report "FAIL: W1: Read Address after the write found R=" & integer'image(r0) severity error;
      report "  W1: following ID (R=" & integer'image(r0) & ") intact";
      read_check(0, s, "W1");
      exp_seed(3, 0, 0, nxt(s));
      read_check(0, nxt(s), "W1 neighbour");
      m_dump(0, 0, 1);

      -- W10: precomp off / on / follow-P (P set) / follow-P (P clear)
      for i in 1 to 10 loop do_step('0'); end loop;
      wait until st_head_settled = '1' for 100 ms;
      assert cur_cyl = 10 report "FAIL: W10: head at " & integer'image(cur_cyl) severity failure;
      m_seed(10, 0, 5);
      read_addr(10, r0);
      s1 := nxt(r0);
      s  := s1;
      for k in 1 to 4 loop
        case k is
          when 1      => wr_pmode <= "01";               -- forced off, P requests on
          when 2      => wr_pmode <= "10";               -- forced on, P requests off
          when others => wr_pmode <= "00";               -- follow P
        end case;
        exp_wpay(10 + k, s);
        g0 := gate_falls;
        if k = 1 or k = 3 then
          write_start(10, s, '0', '1', G_LAT_US);
        else
          write_start(10, s, '0', '0', G_LAT_US);
        end if;
        wait_done(1 sec);
        expect(RES_OK, "W10 write " & integer'image(k));
        check_window("W10." & integer'image(k), true);
        if k = 2 or k = 3 then
          assert d_wr_last(7) = '1' and d_wr_precnt > 0
            report "FAIL: W10." & integer'image(k) & ": precomp not active" severity error;
          stream_sector(2, '1', "FB");
        else
          assert d_wr_last(7) = '0' and d_wr_precnt = 0
            report "FAIL: W10." & integer'image(k) & ": precomp active" severity error;
          stream_sector(2, '0', "FB");
        end if;
        report "  W10." & integer'image(k) & ": sector " & integer'image(s) & " precomp=" & std_logic'image(d_wr_last(7))
             & " shifted pulses=" & integer'image(to_integer(d_wr_precnt));
        s := nxt(s);
        wait for 70 us;
      end loop;
      wr_pmode <= "00";
      s := s1;
      for k in 1 to 4 loop
        exp_wpay(10 + k, s);
        read_check(10, s, "W10." & integer'image(k));
        s := nxt(s);
      end loop;
      m_dump(10, 0, 2);

    -------------------------------------------------------------------------
    elsif G_GROUP = 2 then
    -------------------------------------------------------------------------
      -- W2: the DOS side flush -- ten single-sector writes k+1 .. 10, 1 .. k,
      -- the next command ~70 us after each done, then read all ten back
      m_seed(0, 0, 20 + G_LAT_US);
      read_addr(0, r0);
      s := r0;
      t0 := now;
      for k in 1 to 10 loop
        s := nxt(s);
        exp_wpay(40 + G_LAT_US, s);
        g0 := gate_falls;
        write_start(0, s, '0', '0', G_LAT_US);
        wait_done(1 sec);
        expect(RES_OK, "W2 write " & integer'image(k));
        assert wr_lost = '0' report "FAIL: W2: LOST flag on sector " & integer'image(s) severity error;
        check_window("W2." & integer'image(k) & " sector " & integer'image(s), true);
        assert to_integer(d_wr_margin) >= 18
          report "FAIL: W2: first-byte margin " & integer'image(to_integer(d_wr_margin)) severity error;
        stream_sector(1, '0', "FB");
        if s = 10 then wait for 95 us; else wait for 70 us; end if;
      end loop;
      t1 := now;
      report "  W2 (DRQ latency " & integer'image(G_LAT_US) & " us): ten writes in " & time'image(t1 - t0)
           & ", first-byte margin of the last " & integer'image(to_integer(d_wr_margin)) & " byte-times";
      assert t1 - t0 < 235 ms
        report "FAIL: W2: the flush took more than one revolution per side" severity error;
      wait for 1650 us;
      read_addr(0, r0);
      s := r0;
      for k in 1 to 10 loop
        exp_wpay(40 + G_LAT_US, s);
        read_check(0, s, "W2 verify");
        s := nxt(s);
      end loop;
      m_dump(0, 0, 1);

    -------------------------------------------------------------------------
    elsif G_GROUP = 3 then
    -------------------------------------------------------------------------
      -- W4a: protected tab: refused before the gate, no feed
      cfg_wprot <= '1';
      wait for 100 us;
      exp_wpay(4, 1);
      g0 := gate_falls;
      t0 := now;
      write_start(0, 1, '0', '0', G_LAT_US);
      wait_done(1 sec);
      expect(RES_WRITE_PROTECTED, "W4a");
      assert gate_falls = g0 and fd_sent = 0
        report "FAIL: W4a: gate or feed moved on a protected disk" severity error;
      assert d_wr_last(3) = '1' report "FAIL: W4a: wp-refused flag" severity error;
      report "  W4a: protected disk refused in " & time'image(now - t0) & ", no gate, no byte fed";
      cfg_wprot <= '0';
      wait for 100 us;
      wait until wr_ok = '1' for 100 ms;

      -- W4b: the tab is set mid-sector
      write_next_and_wait_gate(0, 8, 41, 3 ms);
      t0 := now;
      cfg_wprot <= '1';
      wait until f_wgate = '1' for 1 ms;
      t1 := now;
      report "  W4b: tab asserted mid-sector, WGATE closed " & integer'image((t1 - t0) / 20 ns) & " cycles later";
      assert (t1 - t0) / 20 ns <= 8
        report "FAIL: W4b: gate closed only after " & integer'image((t1 - t0) / 20 ns) & " cycles" severity error;
      wait_done(1 sec);
      expect(RES_WRITE_PROTECTED, "W4b");
      assert d_wr_reason = x"04" report "FAIL: W4b: writer reason " & hs(d_wr_reason) severity error;
      check_truncated("W4b", m_wg_open_pos, m_wg_len);
      cfg_wprot <= '0';
      wait for 100 us;
      wait until wr_ok = '1' for 100 ms;

      -- W5: disk change mid-sector
      write_next_and_wait_gate(0, 9, 51, 3 ms);
      t0 := now;
      cfg_change <= '1';
      wait until f_wgate = '1' for 1 ms;
      t1 := now;
      report "  W5: disk change mid-sector, WGATE closed " & integer'image((t1 - t0) / 20 ns) & " cycles later";
      assert (t1 - t0) / 20 ns <= 8
        report "FAIL: W5: gate closed only after " & integer'image((t1 - t0) / 20 ns) & " cycles" severity error;
      wait_done(1 sec);
      expect(RES_DISK_CHANGED, "W5");
      assert rd_rnf = '1' report "FAIL: W5: rnf not set" severity error;
      assert d_wr_reason = x"08" report "FAIL: W5: writer reason " & hs(d_wr_reason) severity error;
      check_truncated("W5", m_wg_open_pos, m_wg_len);
      cfg_change <= '0';
      wait for 100 us;
      -- W5b: a write after the change, without a step (the latch is not a gate)
      wait until wr_ok = '1' for 100 ms;
      assert st_change = '1' report "FAIL: W5b: change latch not set" severity error;
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(52, s);
      g0 := gate_falls;
      write_start(0, s, '0', '0', G_LAT_US);
      wait_done(1 sec);
      expect(RES_OK, "W5b write after a change without a step");
      check_window("W5b", true);
      read_check(0, s, "W5b");

      -- W6: Force Interrupt mid-sector, then a clean op
      write_next_and_wait_gate(0, 10, 61, 3 ms);
      t0 := now;
      rd_cancel <= not rd_cancel;
      wait until f_wgate = '1' for 1 ms;
      t1 := now;
      report "  W6: cancel mid-sector, WGATE closed " & integer'image((t1 - t0) / 20 ns) & " cycles later";
      assert (t1 - t0) / 20 ns <= 8
        report "FAIL: W6: gate closed only after " & integer'image((t1 - t0) / 20 ns) & " cycles" severity error;
      wait_done(1 sec);
      expect(RES_CANCELLED, "W6");
      assert d_wr_reason = x"80" report "FAIL: W6: writer reason " & hs(d_wr_reason) severity error;
      check_truncated("W6", m_wg_open_pos, m_wg_len);
      wait for 20 us;
      assert wf_empty = '1' and wf_wlevel = 0 report "FAIL: W6: write FIFO not empty after the abort" severity error;
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(62, s);
      g0 := gate_falls;
      write_start(0, s, '0', '0', G_LAT_US);
      wait_done(1 sec);
      expect(RES_OK, "W6 next op");
      check_window("W6 next op", true);
      read_check(0, s, "W6 next op");

    -------------------------------------------------------------------------
    elsif G_GROUP = 4 then
    -------------------------------------------------------------------------
      -- W7: drive reset mid-write
      write_next_and_wait_gate(0, 12, 71, 3 ms);
      t0 := now;
      phys_active <= '0';
      wait until f_wgate = '1' for 1 ms;
      t1 := now;
      report "  W7: drive reset mid-sector, WGATE closed " & integer'image((t1 - t0) / 20 ns) & " cycles later";
      assert (t1 - t0) / 20 ns <= 4
        report "FAIL: W7: gate closed only after " & integer'image((t1 - t0) / 20 ns) & " cycles" severity error;
      fd_n <= 0; fd_go <= fd_go + 1;                 -- the drive is gone: the feeder stops
      wait for 1 ms;
      assert rd_done = prev_done report "FAIL: W7: a done toggled for a reset drive" severity error;
      wr_outstanding <= false;
      wopen := m_wg_open_pos; len := m_wg_len;
      check_truncated("W7", wopen, len);
      phys_active <= '1';
      wait for 20 us;
      assert wf_empty = '1' and wf_wlevel = 0 report "FAIL: W7: write FIFO not empty after re-enable" severity error;
      assert st_change = '1' report "FAIL: W7: change latch not armed after re-enable" severity error;
      report "  W7: re-enabled: write FIFO empty, change latch armed";
      wait until st_media_ready = '1' for 2 sec;
      if wr_ok /= '1' then wait until wr_ok = '1' for 100 ms; end if;
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(72, s);
      g0 := gate_falls;
      write_start(0, s, '0', '0', G_LAT_US);
      wait_done(1 sec);
      expect(RES_OK, "W7 recovery write");
      check_window("W7 recovery", true);

      -- W8: the first byte is late: LOST DATA, the gate never opens
      m_seed(0, 0, 13);
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(81, s);
      for i in 0 to 511 loop fd_buf(i) <= exp(i); end loop;
      fd_n <= 512; fd_lat <= lat_cyc; fd_lat0 <= us2d(1000); fd_force <= true;
      wait until rising_edge(clk);
      fd_go <= fd_go + 1;
      g0 := gate_falls;
      wait until rising_edge(clk);
      req(WROP_WRITE_SECTOR, 0, s, '0', '0');
      wait_done(1 sec);
      expect(RES_LOST_DATA, "W8");
      assert gate_falls = g0 report "FAIL: W8: WGATE opened" severity error;
      assert d_wr_last(4) = '1' report "FAIL: W8: first-byte-abort flag" severity error;
      wait for 1500 us;
      assert fd_sent = 1 report "FAIL: W8: the late byte was not written" severity error;
      assert wf_empty = '1' and wf_wlevel = 0 report "FAIL: W8: the late byte was not drained" severity error;
      m_query(0, 0, 0, m_trev);
      assert m_q_new = 0 report "FAIL: W8: written edges on the track" severity error;
      report "  W8: LOST DATA, WGATE never opened, flux untouched (" & integer'image(m_q_seed)
           & " seed edges), the late byte drained";
      fd_force <= false;

      -- W9: one byte 40 us late mid-sector
      m_seed(0, 0, 14);
      read_addr(0, r0);
      s := nxt(r0);
      exp_wpay(91, s);
      for i in 0 to 511 loop fd_buf(i) <= exp(i); end loop;
      fd_n <= 512; fd_lat <= lat_cyc; fd_lat0 <= lat_cyc;
      fd_stall_k <= 200; fd_stall_x <= us2d(40);
      wait until rising_edge(clk);
      fd_go <= fd_go + 1;
      g0 := gate_falls;
      wait until rising_edge(clk);
      req(WROP_WRITE_SECTOR, 0, s, '0', '0');
      wait_done(1 sec);
      fd_stall_k <= 99999;
      expect(RES_OK, "W9");
      assert wr_lost = '1' report "FAIL: W9: LOST flag not set" severity error;
      check_window("W9", true);
      wait for 20 us;
      assert wf_empty = '1' and wf_wlevel = 0 report "FAIL: W9: write FIFO not empty" severity error;
      read_addr(0, r0);
      assert r0 = nxt(s) report "FAIL: W9: following ID not found" severity error;
      for i in 511 downto 201 loop exp(i) := exp(i - 1); end loop;
      exp(200) := x"00";
      read_check(0, s, "W9 (00 at slot 200, the rest one slot late)");
    end if;

    -------------------------------------------------------------------------
    assert d_wr_pushfull = 0 and d_wr_underrun = 0
      report "FAIL: writer refused pushes " & integer'image(to_integer(d_wr_pushfull))
           & ", underruns " & integer'image(to_integer(d_wr_underrun)) severity error;
    report "tb_physical_1581_write group " & integer'image(G_GROUP) & " (DRQ latency "
         & integer'image(G_LAT_US) & " us): ALL TESTS PASSED; " & integer'image(gate_falls)
         & " WGATE windows, writer pushfull=0 underrun=0";
    finish;
  end process;

  guard : process
  begin
    wait for 6 sec;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
