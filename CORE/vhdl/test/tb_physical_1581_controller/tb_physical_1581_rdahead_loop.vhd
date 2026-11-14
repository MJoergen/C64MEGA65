-------------------------------------------------------------------------------
-- tb_physical_1581_rdahead_loop.vhd
--
-- Directed closed-loop tests of the read-ahead of the physical internal 1581
-- (issue #257): the controller, the production read FIFO and the mechanism
-- model, driven through a model of the WD1772 front end (fdc1772.v, delivery
-- v2: a sector is presented only after the tagged clean done; an error done
-- and a Force Interrupt drain the FIFO unseen).
--
-- Every Read Sector is checked three ways: the result, every presented byte
-- against the golden disk, and the PATH the controller took, read from its
-- phase code and its two read-ahead strobes:
--   LIVE  RD_WAIT, RD_SEARCH, RD_DAM, RD_STREAM; no strobe
--   BUF   RD_ADOPT, RD_COPY only; diag_rd_ahead_o once
--   DROP  RD_ADOPT, then the live states; diag_rd_ahead_drop_o once
-- A scenario that expects LIVE asks for the very sector a read-ahead engine
-- that had survived the event would hold or be taking, so an engine that is
-- not switched off by the event turns the check red (BUF instead of LIVE).
--
-- Scenario groups (generic G_GROUP; each group is its own run from power-up,
-- so that they can run in parallel):
--   1  the sector in flight is adopted (the request waits for the capture);
--      the held sector is served at once; the same sector twice (the second
--      read is live); a request through the pending latch (toggled inside the
--      done gap) that adopts; a full read FIFO during the copy (CRC error,
--      CRC flag alone, no residue of the copy); the deleted data mark
--   2  a step in and back; a step to another cylinder and the sequence there;
--      a side flip and back; a side change and the sequence there; motor off
--      and on; the disk-change line pulsed
--   3  Force Interrupt while idle, during RD_ADOPT and during RD_COPY (done
--      with RES_CANCELLED and its own tag, the FIFO drained, the next read
--      live); Read Address and Verify between two Read Sectors
--   4  the data CRC of the sector in flight is bad once (the adoption is
--      dropped, the live read of the next pass succeeds) and on every pass
--      (RES_DATA_CRC_ERROR, CRC flag alone)
--   5  the request for the held sector against the data mark of the next
--      sector, which releases it, placed to the clock: the mark in the first
--      clock of the copy, in the very clock in which RD_ADOPT commits, in the
--      acceptance clock, and one clock before the acceptance
--
-- Run (B = absolute scratch workdir, from a scratch directory; analysis order
-- as in run_tb_write.sh):
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_rdahead_loop \
--     -gG_GROUP=1 --assert-level=error
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.golden_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;

entity tb_physical_1581_rdahead_loop is
  generic (
    G_GROUP : integer := 1
  );
end entity;

architecture sim of tb_physical_1581_rdahead_loop is
  constant C_PACE : time := 31972 ns;        -- 252 ticks of 31.527778 MHz / 4

  -- read phase codes (diag_rd_phase_o)
  constant PH_WAIT   : integer := 1;
  constant PH_SEARCH : integer := 2;
  constant PH_DAM    : integer := 3;
  constant PH_STREAM : integer := 4;
  constant PH_ADDR   : integer := 5;
  constant PH_ADOPT  : integer := 6;
  constant PH_COPY   : integer := 7;

  signal clk    : std_logic := '0';          -- 50 MHz controller clock
  signal rdclk  : std_logic := '0';          -- 31.5 MHz drive clock (FIFO read side)
  signal rst    : std_logic := '1';

  signal f_rdata, f_index, f_track0, f_wprot, f_change : std_logic;
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;
  signal f_wgate, f_wdata : std_logic;

  signal phys_active   : std_logic := '0';
  signal cia_motor_on  : std_logic := '0';
  signal cia_side      : std_logic := '1';   -- '1' = logical side 0 (~PA0)
  signal step_req      : std_logic := '0';
  signal step_outward  : std_logic := '0';
  signal step_ack      : std_logic;
  signal rd_req        : std_logic := '0';
  signal rd_op         : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_track      : unsigned(7 downto 0) := (others => '0');
  signal rd_sector     : unsigned(7 downto 0) := (others => '0');
  signal rd_seq        : std_logic_vector(1 downto 0) := "00";
  signal rd_cancel     : std_logic := '0';
  signal rd_done       : std_logic;
  signal rd_done_seq   : std_logic_vector(1 downto 0);
  signal rd_result     : std_logic_vector(4 downto 0);
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);

  signal byte_data : unsigned(7 downto 0);
  signal byte_wr   : std_logic;
  signal fifo_full : std_logic;
  signal rd_en     : std_logic := '0';
  signal rd_data   : unsigned(7 downto 0);
  signal rd_empty  : std_logic;

  signal st_media_ready, st_head_settled, st_change : std_logic;

  -- mechanism model options
  signal cfg_change  : std_logic := '0';
  signal cfg_badcrc  : integer := 0;
  signal cfg_deleted : integer := 0;
  signal cur_cyl     : integer;

  -- controller taps
  signal d_rd_ahead, d_rd_ahead_drop, d_rd_req : std_logic;
  signal d_rd_phase   : std_logic_vector(3 downto 0);
  signal d_id_valid, d_id_crc_ok, d_data_end, d_data_crc_ok, d_mark_dam : std_logic;
  signal d_stored_crc : unsigned(15 downto 0);

  -- monitor state
  signal g_cyl, g_side : integer := 0;       -- geometry the stimulus expects under the head
  signal n_ahead, n_drop : integer := 0;     -- read-ahead strobes since power-up
  signal ph_seen   : std_logic_vector(15 downto 0) := (others => '0');  -- phases since the last acceptance
  signal n_push    : integer := 0;           -- FIFO pushes since the last acceptance
  signal t_acc     : time := 0 ns;           -- time of the last acceptance strobe
  signal n_id      : integer := 0;           -- decoded IDs
  signal last_r    : integer := 0;           -- R of the last ID (0: not an ID of g_cyl / g_side)
  signal n_dend    : integer := 0;           -- data fields ended
  signal last_dend_ok : std_logic := '0';
  signal n_dam     : integer := 0;           -- data marks
  signal n_dam_in_adopt : integer := 0;      -- data marks in a clock in which the read FSM is in RD_ADOPT

  -- stored CRC of the ID field (c, h, r, N = 2) as the mechanism model writes it
  function id_crc(c, h, r : integer) return unsigned is
    variable v : unsigned(15 downto 0) := x"FFFF";
  begin
    v := crc16_update(v, x"A1");
    v := crc16_update(v, x"A1");
    v := crc16_update(v, x"A1");
    v := crc16_update(v, x"FE");
    v := crc16_update(v, to_unsigned(c mod 256, 8));
    v := crc16_update(v, to_unsigned(h, 8));
    v := crc16_update(v, to_unsigned(r, 8));
    v := crc16_update(v, x"02");
    return v;
  end function;
begin

  clk   <= not clk   after 10 ns;
  rdclk <= not rdclk after 15859 ps;

  dut : entity work.physical_1581_controller
    generic map (G_CAPABLE => true)
    port map (
      clk_i => clk, rst_i => rst,
      f_rdata_i => f_rdata, f_index_i => f_index, f_track0_i => f_track0,
      f_writeprotect_i => f_wprot, f_diskchanged_i => f_change,
      f_motora_o => f_motora, f_selecta_o => f_selecta, f_side1_o => f_side1,
      f_stepdir_o => f_stepdir, f_step_o => f_step, f_density_o => f_density,
      f_wgate_o => f_wgate, f_wdata_o => f_wdata,
      phys_active_i => phys_active, cia_motor_on_i => cia_motor_on, cia_side_i => cia_side,
      step_req_tgl_i => step_req, step_outward_i => step_outward, step_ack_tgl_o => step_ack,
      rd_req_tgl_i => rd_req, rd_op_i => rd_op, rd_track_i => rd_track, rd_side_i => cia_side,
      rd_sector_i => rd_sector, rd_seq_i => rd_seq, rd_cancel_tgl_i => rd_cancel,
      rd_done_tgl_o => rd_done, rd_done_seq_o => rd_done_seq,
      rd_result_o => rd_result, rd_crc_err_o => rd_crc_err, rd_rnf_o => rd_rnf,
      rd_deleted_o => rd_deleted, rd_c_o => rd_c, rd_h_o => rd_h, rd_r_o => rd_r, rd_n_o => rd_n,
      byte_data_o => byte_data, byte_wr_o => byte_wr, byte_ovf_i => fifo_full,
      st_media_ready_o => st_media_ready, st_head_settled_o => st_head_settled,
      st_change_o => st_change,
      diag_id_valid_o => d_id_valid, diag_id_crc_ok_o => d_id_crc_ok,
      diag_stored_crc_o => d_stored_crc,
      diag_data_end_o => d_data_end, diag_data_crc_ok_o => d_data_crc_ok,
      diag_mark_dam_o => d_mark_dam,
      diag_rd_phase_o => d_rd_phase, diag_rd_req_o => d_rd_req,
      diag_rd_ahead_o => d_rd_ahead, diag_rd_ahead_drop_o => d_rd_ahead_drop
    );

  i_fifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 9)                    -- the production depth
    port map (
      wr_clk_i => clk, wr_rst_i => rst, wr_en_i => byte_wr, wr_data_i => byte_data, wr_full_o => fifo_full,
      rd_clk_i => rdclk, rd_rst_i => rst, rd_en_i => rd_en, rd_data_o => rd_data, rd_empty_o => rd_empty
    );

  i_mech : entity work.mech_model_1581
    generic map (G_INDEX_PERIOD => 200 ms, G_INDEX_LOW => 2 ms, G_NUM_CYL => 80)
    port map (
      f_motora_i => f_motora, f_selecta_i => f_selecta, f_side1_i => f_side1,
      f_stepdir_i => f_stepdir, f_step_i => f_step, f_density_i => f_density,
      cfg_present_i => '1', cfg_wprot_i => '0', cfg_change_i => cfg_change,
      cfg_badcrc_sec_i => cfg_badcrc, cfg_deleted_sec_i => cfg_deleted,
      f_index_o => f_index, f_track0_o => f_track0, f_writeprotect_o => f_wprot,
      f_diskchanged_o => f_change, f_rdata_o => f_rdata,
      f_wgate_i => f_wgate, f_wdata_i => f_wdata,
      cur_cyl_o => cur_cyl
    );

  -- rd_done_seq may only change on a clock edge where rd_done toggles too
  tag_mon : process (clk)
    variable prev_tag  : std_logic_vector(1 downto 0) := "00";
    variable prev_done : std_logic := '0';
  begin
    if rising_edge(clk) then
      assert (rd_done_seq = prev_tag) or (rd_done /= prev_done)
        report "FAIL: rd_done_seq changed without a rd_done toggle" severity failure;
      prev_tag  := rd_done_seq;
      prev_done := rd_done;
    end if;
  end process;

  -- path, strobe and record monitor
  mon : process (clk)
    variable v : std_logic_vector(15 downto 0);
    variable r : integer;
  begin
    if rising_edge(clk) then
      v := ph_seen;
      if d_rd_req = '1' then
        v := (others => '0');
        n_push <= 0;
        t_acc  <= now;
      elsif byte_wr = '1' then
        n_push <= n_push + 1;
      end if;
      v(to_integer(unsigned(d_rd_phase))) := '1';
      ph_seen <= v;
      if d_rd_ahead = '1' then n_ahead <= n_ahead + 1; end if;
      if d_rd_ahead_drop = '1' then n_drop <= n_drop + 1; end if;
      if d_id_valid = '1' then
        r := 0;
        if d_id_crc_ok = '1' then
          for k in 1 to 10 loop
            if d_stored_crc = id_crc(g_cyl, g_side, k) then r := k; end if;
          end loop;
        end if;
        last_r <= r;
        n_id   <= n_id + 1;
      end if;
      if d_data_end = '1' then
        n_dend <= n_dend + 1;
        last_dend_ok <= d_data_crc_ok;
      end if;
      if d_mark_dam = '1' then
        n_dam <= n_dam + 1;
        if d_rd_phase = "0110" then n_dam_in_adopt <= n_dam_in_adopt + 1; end if;
      end if;
    end if;
  end process;

  stim : process
    type path_t is (P_LIVE, P_BUF, P_DROP);

    variable seq_cnt   : unsigned(1 downto 0) := "00";
    variable prev_done : std_logic;
    variable t_req, t_done, t_d1 : time;
    variable a0, d0, n0 : integer;       -- strobe counts before a request
    variable s, r1, r2, r, n : integer;
    variable pd        : std_logic;
    variable lat       : integer;        -- clocks from a request toggle to its acceptance
    variable dper      : integer;        -- clocks from a data mark to the next one
    variable dm        : integer;        -- data mark clock minus acceptance clock, measured
    variable t_mk      : time;
    variable na0       : integer;
    variable fails     : integer := 0;

    procedure chk(ok : boolean; what : string) is
    begin
      if not ok then
        report "FAIL: " & what severity error;
        fails := fails + 1;
      end if;
    end procedure;

    procedure clkw(k : natural) is
    begin
      for i in 1 to k loop wait until rising_edge(clk); end loop;
    end procedure;

    function nxt(k : integer) return integer is      -- sector after k (1..10)
    begin
      return (k mod 10) + 1;
    end function;

    impure function path_str return string is
      constant names : string := "IDLE   WAIT   SEARCH DAM    STREAM ADDR   ADOPT  COPY   ";
      variable res : string(1 to 56) := (others => ' ');
      variable p   : integer := 1;
    begin
      for i in 1 to 7 loop
        if ph_seen(i) = '1' then
          res(p to p + 6) := names(i * 7 + 1 to i * 7 + 7);
          p := p + 7;
        end if;
      end loop;
      return res(1 to p - 1);
    end function;

    -- one WD command as fdc1772 issues it: the request ...
    procedure wd_req(op : std_logic_vector(2 downto 0); trk, secn : integer) is
    begin
      rd_op     <= op;
      rd_track  <= to_unsigned(trk, 8);
      rd_sector <= to_unsigned(secn, 8);
      seq_cnt   := seq_cnt + 1;
      rd_seq    <= std_logic_vector(seq_cnt);
      clkw(2);
      prev_done := rd_done;
      a0 := n_ahead; d0 := n_drop;
      rd_req    <= not rd_req;
      t_req     := now;
    end procedure;

    -- ... and its tagged done
    procedure wd_done(tmo : time) is
    begin
      wait until rd_done /= prev_done for tmo;
      assert rd_done /= prev_done report "FAIL: TIMEOUT waiting for rd_done" severity failure;
      assert rd_done_seq = std_logic_vector(seq_cnt) report "FAIL: wrong done tag" severity failure;
      t_done := now;
      wait for 160 ns;                          -- done toggle through the WD's synchronizer
    end procedure;

    -- the WD front end presents n bytes after a clean done: at disk pace, or as
    -- fast as the FIFO's read side allows where the pace does not matter; a
    -- sector (n = 512) is compared with the golden one, and nothing may be
    -- left in the FIFO
    procedure wd_present(nb, cyl, side, secn : integer; paced : boolean; what : string) is
      variable t0  : time;
      variable b   : unsigned(7 downto 0);
      variable bad : integer := 0;
    begin
      for i in 0 to nb - 1 loop
        t0 := now;
        wait until rising_edge(rdclk);
        if rd_empty = '1' then
          wait until rising_edge(rdclk) and rd_empty = '0' for 1 ms;
        end if;
        if rd_empty /= '0' then
          chk(false, what & ": the read FIFO ran dry after " & integer'image(i) & " bytes");
          exit;
        end if;
        b := rd_data;
        rd_en <= '1';
        wait until rising_edge(rdclk);
        rd_en <= '0';
        if nb = 512 and b /= golden_payload(cyl, side, secn, i) then
          bad := bad + 1;
        end if;
        if paced then wait for C_PACE - (now - t0); end if;
      end loop;
      if paced then wait for C_PACE; end if;    -- BUSY outlives the last byte by one byte-time
      wait until rising_edge(rdclk);
      wait until rising_edge(rdclk);
      chk(rd_empty = '1', what & ": residue in the read FIFO");
      chk(bad = 0, what & ": " & integer'image(bad) & " wrong bytes");
    end procedure;

    -- the WD front end's residue drain after an error done or a Force
    -- Interrupt: pop until the FIFO has been empty for 2 us
    procedure wd_drain(cnt : out integer) is
      variable k    : integer := 0;
      variable idle : integer := 0;
    begin
      while idle < 64 loop
        wait until rising_edge(rdclk);
        if rd_empty = '0' then
          rd_en <= '1';
          k := k + 1;
          idle := 0;
          wait until rising_edge(rdclk);
          rd_en <= '0';
        else
          idle := idle + 1;
        end if;
      end loop;
      cnt := k;
    end procedure;

    -- the path of the op that just completed (strobe counts against wd_req's)
    procedure chk_path(p : path_t; what : string) is
      variable live_all, live_any, ok : boolean;
    begin
      live_all := ph_seen(PH_WAIT) = '1' and ph_seen(PH_SEARCH) = '1' and
                  ph_seen(PH_DAM) = '1' and ph_seen(PH_STREAM) = '1';
      live_any := ph_seen(PH_WAIT) = '1' or ph_seen(PH_SEARCH) = '1' or
                  ph_seen(PH_DAM) = '1' or ph_seen(PH_STREAM) = '1';
      case p is
        when P_LIVE => ok := live_all and ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0'
                             and n_ahead = a0 and n_drop = d0;
        when P_BUF  => ok := not live_any and ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '1'
                             and n_ahead = a0 + 1 and n_drop = d0;
        when P_DROP => ok := live_all and ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '0'
                             and n_ahead = a0 and n_drop = d0 + 1;
      end case;
      chk(ok, what & ": expected path " & path_t'image(p) & ", saw " & path_str
              & ", served " & integer'image(n_ahead - a0) & ", dropped " & integer'image(n_drop - d0));
    end procedure;

    -- Read Sector with every check: result, reported ID, path, 512 golden bytes
    procedure rd_chk(secn : integer; p : path_t; paced : boolean; what : string) is
    begin
      wd_req(RDOP_READ_SECTOR, g_cyl, secn);
      wd_done(1 sec);
      chk(rd_result = RES_OK and rd_crc_err = '0' and rd_rnf = '0',
          what & ": result " & to_hstring("000" & rd_result));
      chk(to_integer(rd_c) = g_cyl and to_integer(rd_h) = g_side and to_integer(rd_r) = secn and rd_n = 2,
          what & ": reported ID C/H/R " & integer'image(to_integer(rd_c)) & "/"
          & integer'image(to_integer(rd_h)) & "/" & integer'image(to_integer(rd_r)));
      chk_path(p, what);
      report "  " & what & ": sector " & integer'image(secn) & " request -> done "
           & time'image(t_done - t_req) & ", path " & path_str;
      wd_present(512, g_cyl, to_integer(rd_h), secn, paced, what);
    end procedure;

    procedure do_step(outward : std_logic) is
      variable a : std_logic;
    begin
      step_outward <= outward;
      clkw(2);
      a := step_ack;
      step_req <= not step_req;
      wait until step_ack /= a for 1 sec;
      assert step_ack /= a report "FAIL: TIMEOUT waiting for step_ack" severity failure;
    end procedure;

    -- the next ID of the expected geometry that the decoder delivers
    procedure next_id(k : out integer) is
      variable c : integer;
    begin
      loop
        c := n_id;
        wait until n_id /= c for 450 ms;
        assert n_id /= c report "FAIL: no ID decoded" severity failure;
        exit when last_r /= 0;
      end loop;
      k := last_r;
    end procedure;

    -- with the engine armed: wait for the next ID and 3 ms into its record, so
    -- that the data field of sector k is on its way into the buffer
    procedure in_flight(k : out integer) is
    begin
      next_id(k);
      wait for 3 ms;
    end procedure;

    procedure next_dend is
      variable c : integer;
    begin
      c := n_dend;
      wait until n_dend /= c for 450 ms;
      assert n_dend /= c report "FAIL: no data field ended" severity failure;
    end procedure;

    procedure next_dam is
      variable c : integer;
    begin
      c := n_dam;
      wait until n_dam /= c for 450 ms;
      assert n_dam /= c report "FAIL: no data mark" severity failure;
    end procedure;

    -- Read Address until the head reads the expected geometry (the model lays
    -- a new cylinder or side from the top of its next revolution), then a
    -- live Read Sector of the following sector, which arms the engine
    procedure prime(cyl, side : integer; k : out integer) is
      variable tries : integer := 0;
      variable q     : integer;
    begin
      g_cyl <= cyl; g_side <= side;
      wait for 1 ns;
      loop
        wd_req(RDOP_READ_ADDRESS, cyl, 0);
        wd_done(1 sec);
        chk(rd_result = RES_OK, "Read Address result");
        wd_present(6, 0, 0, 0, false, "Read Address");
        exit when to_integer(rd_c) = cyl and to_integer(rd_h) = side;
        tries := tries + 1;
        assert tries < 40 report "FAIL: Read Address never saw the expected geometry" severity failure;
      end loop;
      q := nxt(to_integer(rd_r));
      wait for 2200 us;                         -- software CRC check of the reply ($DA63)
      rd_chk(q, P_LIVE, false, "prime");
      k := q;
    end procedure;
  begin
    wait for 200 ns;
    rst <= '0';
    wait for 1 us;
    phys_active  <= '1';
    cia_motor_on <= '1';
    wait until st_media_ready = '1' for 2 sec;
    assert st_media_ready = '1' report "FAIL: media never ready" severity failure;

    ---------------------------------------------------------------------------
    if G_GROUP = 1 then
    ---------------------------------------------------------------------------
      report "=== group 1: adoption";
      prime(0, 0, s);

      -- 1.1 the sector in flight: the request waits for the capture
      in_flight(r1);
      chk(r1 = nxt(s), "1.1: the sector in flight is the next one");
      rd_chk(r1, P_BUF, true, "1.1 in flight");
      chk(t_done - t_req > 5 ms and t_done - t_req < 20 ms, "1.1: the request waited for the capture");
      chk(rd_deleted = '0', "1.1: deleted flag of a normal sector");

      -- 1.2 the held sector: served at once
      next_dend;
      wait for 200 us;
      r2 := nxt(r1);
      rd_chk(r2, P_BUF, true, "1.2 held");
      chk(t_done - t_req < 300 us, "1.2: a held sector is served within 300 us");

      -- 1.3 the same sector again: it was consumed, the second read is live
      rd_chk(r2, P_LIVE, false, "1.3 same sector twice");
      chk(t_done - t_req > 100 ms, "1.3: the second read waited for the sector to come round");

      -- 1.4 a request toggled inside the done gap is latched, served when the
      -- gap has expired, and adopts the capture in flight
      next_id(r1);
      chk(r1 = nxt(r2), "1.4: next ID");
      next_id(r);
      chk(r = nxt(r1), "1.4: ID after next");
      wait for 100 us;                          -- r1 is held, r is the candidate
      n0 := n_ahead;
      wd_req(RDOP_READ_SECTOR, 0, r1);
      wait until rd_done /= prev_done for 5 ms;
      assert rd_done /= prev_done report "FAIL: 1.4: TIMEOUT waiting for rd_done" severity failure;
      t_d1 := now;
      chk(rd_done_seq = std_logic_vector(seq_cnt) and rd_result = RES_OK, "1.4: first done");
      rd_sector <= to_unsigned(r, 8);           -- the next request, in the same clock as the done
      seq_cnt   := seq_cnt + 1;
      rd_seq    <= std_logic_vector(seq_cnt);
      prev_done := rd_done;
      rd_req    <= not rd_req;
      t_req     := now;
      wd_present(512, 0, 0, r1, false, "1.4 first sector");
      chk(n_ahead = n0 + 1 and n_drop = d0, "1.4: the first sector came from the buffer");
      wd_done(1 sec);
      chk(rd_result = RES_OK and to_integer(rd_r) = r, "1.4: second done");
      chk(t_acc - t_d1 >= 180 ns and t_acc - t_d1 <= 220 ns,
          "1.4: the latched request was accepted " & time'image(t_acc - t_d1) & " after the done (done gap)");
      chk(ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '1' and ph_seen(PH_WAIT) = '0' and
          n_ahead = n0 + 2 and n_drop = d0, "1.4: the latched request was served from the buffer, saw " & path_str);
      report "  1.4 pending latch: accepted " & time'image(t_acc - t_d1) & " after the done, request -> done "
           & time'image(t_done - t_req) & ", path " & path_str;

      -- 1.5 the WD has not taken the sector of 1.4 yet (512 bytes in the
      -- FIFO): every push of the next copy is dropped, and the op fails with
      -- the CRC flag alone. The FIFO still holds the sector of 1.4, untouched.
      in_flight(r1);
      chk(r1 = nxt(r), "1.5: the sector in flight");
      wd_req(RDOP_READ_SECTOR, 0, r1);
      wd_done(1 sec);
      chk(rd_result = RES_DATA_CRC_ERROR and rd_crc_err = '1' and rd_rnf = '0',
          "1.5: a copy into a full FIFO ends with the CRC flag alone, result " & to_hstring("000" & rd_result));
      chk(ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '1' and ph_seen(PH_WAIT) = '0' and
          n_ahead = a0 and n_drop = d0, "1.5: path ADOPT COPY without a served strobe, saw " & path_str);
      wd_present(512, 0, 0, r, false, "1.5 the sector of 1.4");
      rd_chk(r1, P_LIVE, false, "1.5 the failed sector again");

      -- 1.6 a deleted data mark is reported with the sector it belongs to
      cfg_deleted <= nxt(r1);
      in_flight(r);
      chk(r = nxt(r1), "1.6: the sector in flight");
      rd_chk(r, P_BUF, false, "1.6 deleted data mark");
      chk(rd_deleted = '1', "1.6: deleted flag of the sector with the F8 mark");
      cfg_deleted <= 0;
      in_flight(r1);
      rd_chk(r1, P_BUF, false, "1.6 normal sector after it");
      chk(rd_deleted = '0', "1.6: deleted flag of the following normal sector");

    ---------------------------------------------------------------------------
    elsif G_GROUP = 2 then
    ---------------------------------------------------------------------------
      report "=== group 2: mechanics";
      prime(0, 0, s);

      -- 2.1 a step in and back while a sector is in flight; after the settle
      -- time the sector under the head is read live
      in_flight(r1);
      do_step('0');
      do_step('1');
      chk(cur_cyl = 0, "2.1: the head is back on cylinder 0");
      wait until st_head_settled = '1' for 100 ms;
      chk(st_head_settled = '1', "2.1: head settled");
      in_flight(r);
      rd_chk(r, P_LIVE, false, "2.1 after a step in and back");

      -- 2.2 a step to cylinder 1 and the DOS's sequence there
      in_flight(r1);
      do_step('0');
      chk(cur_cyl = 1, "2.2: the head is on cylinder 1");
      wait until st_head_settled = '1' for 100 ms;
      wait for 19 ms;
      prime(1, 0, s);
      wait for 16500 us;                        -- the WD's presentation of that sector
      rd_chk(nxt(s), P_BUF, true, "2.2 cylinder 1, next sector");
      wait for 67 us;
      rd_chk(nxt(nxt(s)), P_BUF, true, "2.2 cylinder 1, sector after next");

      -- 2.3 the side select flips to the other side and back while a sector
      -- is in flight
      in_flight(r1);
      cia_side <= '0';
      wait for 1 ms;
      cia_side <= '1';
      wait for 200 us;
      rd_chk(r1, P_LIVE, false, "2.3 after a side flip and back");

      -- 2.4 a side change and the sequence on the other side
      in_flight(r1);
      cia_side <= '0';
      wait for 200 us;
      prime(1, 1, s);
      wait for 16500 us;
      rd_chk(nxt(s), P_BUF, true, "2.4 side 1, next sector");
      cia_side <= '1';
      wait for 200 us;

      -- 2.5 motor off and on again while a sector is in flight
      prime(1, 0, s);
      in_flight(r1);
      cia_motor_on <= '0';
      wait for 1 ms;
      chk(st_media_ready = '0', "2.5: not ready with the motor off");
      cia_motor_on <= '1';
      wait until st_media_ready = '1' for 500 ms;
      chk(st_media_ready = '1', "2.5: ready again");
      in_flight(r);
      rd_chk(r, P_LIVE, false, "2.5 after motor off and on");

      -- 2.6 the disk-change line pulses while a sector is in flight
      in_flight(r1);
      cfg_change <= '1';
      wait for 100 us;
      cfg_change <= '0';
      wait for 100 us;
      chk(st_change = '1', "2.6: the change latch is set");
      rd_chk(r1, P_LIVE, false, "2.6 after a disk-change pulse");

    ---------------------------------------------------------------------------
    elsif G_GROUP = 3 then
    ---------------------------------------------------------------------------
      report "=== group 3: Force Interrupt, Read Address, Verify";
      prime(0, 0, s);

      -- 3.1 Force Interrupt while idle
      in_flight(r1);
      pd := rd_done;
      rd_cancel <= not rd_cancel;
      wait for 1 ms;
      chk(rd_done = pd, "3.1: a cancel while idle toggles no done");
      rd_chk(r1, P_LIVE, false, "3.1 after a Force Interrupt while idle");

      -- 3.2 Force Interrupt while the request waits in RD_ADOPT
      in_flight(r1);
      wd_req(RDOP_READ_SECTOR, 0, r1);
      wait for 1 ms;
      chk(d_rd_phase = "0110", "3.2: the request waits in RD_ADOPT");
      rd_cancel <= not rd_cancel;
      wd_done(1 ms);
      chk(rd_result = RES_CANCELLED and rd_rnf = '0' and rd_crc_err = '0',
          "3.2: cancelled, result " & to_hstring("000" & rd_result));
      chk(n_ahead = a0 and n_drop = d0 and n_push = 0, "3.2: no strobe, no byte pushed");
      wd_drain(n);
      chk(n = 0, "3.2: nothing to drain");
      rd_chk(r1, P_LIVE, false, "3.2 after a Force Interrupt in RD_ADOPT");

      -- 3.3 Force Interrupt in the middle of the copy; the WD drains the
      -- bytes that were pushed, and the next read delivers exactly one sector
      in_flight(r1);
      wd_req(RDOP_READ_SECTOR, 0, r1);
      wait until d_rd_phase = "0111" for 25 ms;
      chk(d_rd_phase = "0111", "3.3: the copy started");
      wait for 50 us;
      rd_cancel <= not rd_cancel;
      wd_done(1 ms);
      chk(rd_result = RES_CANCELLED and rd_rnf = '0' and rd_crc_err = '0',
          "3.3: cancelled, result " & to_hstring("000" & rd_result));
      chk(n_ahead = a0 and n_drop = d0, "3.3: no strobe");
      wd_drain(n);
      chk(n > 100 and n < 300, "3.3: the WD drained the bytes of the cut copy");
      report "  3.3 Force Interrupt in RD_COPY: " & integer'image(n) & " bytes drained";
      rd_chk(r1, P_LIVE, false, "3.3 after a Force Interrupt in RD_COPY");

      -- 3.4 Read Address between two Read Sectors: it returns the ID that
      -- follows the sector in flight; that sector is then read live
      in_flight(r1);
      wd_req(RDOP_READ_ADDRESS, 0, 0);
      wd_done(1 sec);
      chk(rd_result = RES_OK and to_integer(rd_r) = nxt(r1), "3.4: Read Address found the next ID");
      r := to_integer(rd_r);
      wd_present(6, 0, 0, 0, false, "3.4 Read Address");
      rd_chk(r, P_LIVE, false, "3.4 after a Read Address");

      -- 3.5 Verify between two Read Sectors
      in_flight(r1);
      wd_req(RDOP_VERIFY, 0, 0);
      wd_done(1 sec);
      chk(rd_result = RES_OK and to_integer(rd_r) = nxt(r1), "3.5: Verify matched the next ID");
      r := to_integer(rd_r);
      wd_drain(n);
      chk(n = 0, "3.5: a Verify pushes nothing");
      rd_chk(r, P_LIVE, false, "3.5 after a Verify");

    ---------------------------------------------------------------------------
    elsif G_GROUP = 4 then
    ---------------------------------------------------------------------------
      report "=== group 4: bad data CRC";
      prime(0, 0, s);

      -- 4.1 the data CRC of the sector in flight is bad on this pass only
      cfg_badcrc <= nxt(s);
      in_flight(r1);
      chk(r1 = nxt(s), "4.1: the sector in flight");
      wd_req(RDOP_READ_SECTOR, 0, r1);
      next_dend;
      chk(last_dend_ok = '0', "4.1: the capture in flight ended with a bad CRC");
      cfg_badcrc <= 0;
      wd_done(1 sec);
      chk(rd_result = RES_OK and rd_crc_err = '0' and rd_rnf = '0' and to_integer(rd_r) = r1,
          "4.1: result " & to_hstring("000" & rd_result));
      chk_path(P_DROP, "4.1 bad CRC once");
      chk(t_done - t_req > 150 ms, "4.1: the live read took the next pass");
      report "  4.1 bad CRC once: request -> done " & time'image(t_done - t_req) & ", path " & path_str;
      wd_present(512, 0, 0, r1, false, "4.1 bad CRC once");

      -- 4.2 the data CRC is bad on every pass
      next_id(r1);
      cfg_badcrc <= r1;
      wait for 3 ms;
      wd_req(RDOP_READ_SECTOR, 0, r1);
      wd_done(1 sec);
      chk(rd_result = RES_DATA_CRC_ERROR and rd_crc_err = '1' and rd_rnf = '0',
          "4.2: CRC flag alone, result " & to_hstring("000" & rd_result));
      chk(ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '0' and ph_seen(PH_STREAM) = '1' and
          n_ahead = a0 and n_drop = d0 + 1, "4.2: path ADOPT, then live, one drop strobe, saw " & path_str);
      wd_drain(n);
      chk(n = 512, "4.2: the WD drained the quarantined sector (" & integer'image(n) & " bytes)");
      cfg_badcrc <= 0;
      rd_chk(r1, P_LIVE, false, "4.2 the sector once its CRC is good");

    ---------------------------------------------------------------------------
    elsif G_GROUP = 5 then
    ---------------------------------------------------------------------------
      report "=== group 5: commit against the next data mark";
      prime(0, 0, s);

      -- A request for the held sector is accepted in clock A and commits to
      -- the copy one clock later; the data mark of the following sector, which
      -- releases the held sector, comes in clock M. The request is placed so
      -- that d = M - A runs through 1, 0, -1, -2:
      --   d >= 0  the mark comes when the buffer already belongs to the copy
      --           (d = 0: in the very clock in which RD_ADOPT commits): it is
      --           skipped, the sector is served from the buffer (BUF), and the
      --           sector whose mark was skipped is read live afterwards
      --   d = -1  the engine takes the mark in the acceptance clock: the
      --           adoption finds the sector gone and drops (DROP)
      --   d <= -2 the held sector was released before the acceptance (LIVE)
      -- The data marks are exactly one record apart, so the bench places the
      -- request from the mark before; the latency from the request toggle to
      -- the acceptance is taken from the request of the prime (the monitor
      -- sees an acceptance strobe one clock after the acceptance).
      lat := (t_acc - t_req) / 20 ns - 1;
      next_dam;
      t_d1 := now;
      next_dam;
      dper := (now - t_d1) / 20 ns;
      report "  5: request toggle -> acceptance " & integer'image(lat) & " clocks, data mark -> data mark "
           & integer'image(dper) & " clocks";
      for d in 1 downto -2 loop
        next_dam;                               -- the engine takes this sector; it is held when the next mark comes
        r1 := last_r;
        na0 := n_dam_in_adopt;
        rd_op     <= RDOP_READ_SECTOR;
        rd_track  <= to_unsigned(0, 8);
        rd_sector <= to_unsigned(r1, 8);
        seq_cnt   := seq_cnt + 1;
        rd_seq    <= std_logic_vector(seq_cnt);
        clkw(dper - 1 - d - lat);               -- the bench woke one clock after the mark
        prev_done := rd_done;
        a0 := n_ahead; d0 := n_drop;
        rd_req    <= not rd_req;
        t_req     := now;
        n := n_dam;
        wait until n_dam /= n for 1 ms;
        chk(n_dam /= n, "5 d=" & integer'image(d) & ": the next data mark came");
        t_mk := now;
        wd_done(1 sec);
        dm := (t_mk - t_acc) / 20 ns;
        chk(dm = d, "5 d=" & integer'image(d) & ": the data mark came " & integer'image(dm)
                    & " clocks after the acceptance");
        chk(rd_result = RES_OK and to_integer(rd_r) = r1, "5 d=" & integer'image(d) & ": result");
        if d >= 0 then
          chk_path(P_BUF, "5 d=" & integer'image(d) & " (mark while the buffer belongs to the copy)");
        elsif d = -1 then
          chk_path(P_DROP, "5 d=-1 (mark in the acceptance clock)");
        else
          chk_path(P_LIVE, "5 d=" & integer'image(d) & " (mark before the acceptance)");
        end if;
        if d = 0 then
          chk(n_dam_in_adopt = na0 + 1, "5 d=0: the data mark fell into the commit clock of RD_ADOPT");
        else
          chk(n_dam_in_adopt = na0, "5 d=" & integer'image(d) & ": no data mark in an RD_ADOPT clock");
        end if;
        report "  5 d=" & integer'image(d) & ": sector " & integer'image(r1) & " request -> done "
             & time'image(t_done - t_req) & ", path " & path_str;
        wd_present(512, 0, 0, r1, false, "5 d=" & integer'image(d));
        if d >= 0 then
          rd_chk(nxt(r1), P_LIVE, false, "5 d=" & integer'image(d) & ": the sector whose mark was skipped");
        end if;
      end loop;

    else
      report "FAIL: unknown G_GROUP " & integer'image(G_GROUP) severity failure;
    end if;

    ---------------------------------------------------------------------------
    wait for 1 us;
    if fails = 0 then
      report "tb_physical_1581_rdahead_loop group " & integer'image(G_GROUP) & ": ALL TESTS PASSED; "
           & integer'image(n_ahead) & " sectors from the read-ahead buffer, "
           & integer'image(n_drop) & " adoptions given up";
    else
      report "tb_physical_1581_rdahead_loop group " & integer'image(G_GROUP) & ": "
           & integer'image(fails) & " CHECKS FAILED" severity failure;
    end if;
    finish;
  end process;

  guard : process
  begin
    wait for 20 sec;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
