-------------------------------------------------------------------------------
-- tb_physical_1581_rdahead_ctl.vhd
--
-- Directed tests of the read-ahead integration of physical_1581_controller
-- (issue #257) on a synthetic record stream: the real controller, the real
-- read-ahead engine (physical_1581_rdahead) and the real read FIFO, with
-- decoder_stub_1581.vhd in place of the MFM decoder. A disk process plays ten
-- records per track side (ID field, data mark, 512 payload bytes, data end),
-- one every C_PITCH clocks, and cuts the record under way, as the real decoder
-- would lose it, on a decoder reset, a motor stop, a step and a side change.
-- Without the flux path every record is placed to the clock, and the
-- simulation spends its time in the controller alone;
-- tb_physical_1581_rdahead_loop covers the same integration end to end at
-- disk speed.
--
-- The record pitch is compressed (48 us instead of about 19 ms): the copy of
-- a sector into the read FIFO (512 pushes 16 clocks apart, 164 us) spans
-- several records here, so the data marks that fall into a copy, and the
-- order of a copy against a capture, differ from a real track. The scenarios
-- that depend on it say so.
--
-- Every Read Sector is checked for its result, its reported ID, every byte
-- the WD front end takes from the FIFO (a fast drain stands in for its paced
-- presentation) and the PATH the controller took, read from its phase code
-- and its two read-ahead strobes:
--   LIVE  RD_WAIT, RD_SEARCH, RD_DAM, RD_STREAM; no strobe
--   BUF   RD_ADOPT, RD_COPY only; diag_rd_ahead_o once
--   DROP  RD_ADOPT, then the live states; diag_rd_ahead_drop_o once
--
-- Scenarios:
--   S1   the sector in flight: the request waits for the capture (BUF)
--   S1b  the request arrives between the ID and the data mark of its sector:
--        the controller must wait for the data, not copy the buffer as it is
--   S2   the held sector: served at once (BUF)
--   S3   the sector that was just served, requested again: LIVE
--   S4   Force Interrupt while idle: the next read is LIVE
--   S5   a step in and back while a sector is on its way: LIVE
--   S6   a side flip and back: LIVE
--   S7   a Read Address in between: the sector after it is LIVE
--   S8   the held sector asked for with another track number: no adoption,
--        record not found
--   S9   Force Interrupt in the middle of the copy: RES_CANCELLED with its own
--        tag at once, the pushed part of the copy is left for the drain, the
--        next read is LIVE
--   S10  a request toggled with the done of a copy waits out the done gap
--   S11  the data mark of the next sector, which releases the held sector,
--        placed to the clock against the acceptance of the request
--   S12  the disk-change line pulsed: LIVE
--   S13  the data CRC of the sector in flight is bad on this pass: DROP, and
--        the live read of the next pass succeeds
--   S14  motor off and on again: LIVE
--   S15  the sector that was just served, requested again before any further
--        data mark could release it: LIVE (only its delivery releases it)
--   S16  the age of a held sector: no record follows it; a request shortly
--        before its data mark is 24 ms old is served from the buffer, a
--        request shortly after that is LIVE
--   S17  a write operation switches the engine off on its own: a Write Sector
--        on a write-protected disk ends in WR_WAIT, without a decoder reset
--        and without a gate; the read of the held sector after it is LIVE
--   S18  the deleted data mark: a live read of the deleted sector reports it,
--        a live read of the normal sector right after it does not, and the
--        buffer reports the flag of the sector it serves
--   S19  a copy into a full read FIFO: every push is dropped, the result is a
--        data CRC error with the CRC flag alone, the FIFO keeps the sector
--        that was in it, and the next read of the sector is LIVE
--
-- A failed check reports "FAIL: <scenario> <what it proves>" with severity
-- error; run with --assert-level=error, so the first failure ends the run.
-- The last line is "ALL TESTS PASSED" only when every check held.
-- run_tb_rdahead_ctl.sh runs the bench and the mutants of the controller that
-- it has to reject.
--
-- Run (B = absolute scratch workdir, from a scratch directory, NEVER in a
-- library that also holds the real physical_1581_mfm_decoder):
--   ghdl -a --std=08 --workdir=B \
--     CORE/vhdl/physical_1581/physical_1581_pkg.vhd \
--     CORE/vhdl/physical_1581/physical_1581_crc.vhd \
--     CORE/vhdl/physical_1581/physical_1581_inputs.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/decoder_stub_1581.vhd \
--     CORE/vhdl/physical_1581/physical_1581_rdfifo.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_encoder.vhd \
--     CORE/vhdl/physical_1581/physical_1581_writer.vhd \
--     CORE/vhdl/physical_1581/physical_1581_rdahead.vhd \
--     CORE/vhdl/physical_1581/physical_1581_controller.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/tb_physical_1581_rdahead_ctl.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_rdahead_ctl --assert-level=error
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.decoder_stub_1581_pkg.all;

entity tb_physical_1581_rdahead_ctl is
end entity;

architecture sim of tb_physical_1581_rdahead_ctl is
  constant C_CLK   : time := 20 ns;

  -- one record per C_PITCH clocks; offsets within a record
  constant C_PITCH : integer := 2400;
  constant C_ID    : integer := 10;                     -- id_valid
  constant C_DS    : integer := 110;                    -- data mark
  constant C_D0    : integer := 114;                    -- first payload byte
  constant C_BG    : integer := 4;                      -- clocks per payload byte
  constant C_DE    : integer := C_D0 + 511 * C_BG + 14; -- data end
  constant C_REV   : integer := 10 * C_PITCH;           -- one revolution

  -- the age at which the engine releases a held sector: G_DATA_WD_CYC of
  -- physical_1581_rdahead, which the controller leaves at its default
  constant C_AGE_CYC : integer := 1_200_000;

  -- read phase codes (diag_rd_phase_o)
  constant PH_WAIT   : integer := 1;
  constant PH_SEARCH : integer := 2;
  constant PH_DAM    : integer := 3;
  constant PH_STREAM : integer := 4;
  constant PH_ADOPT  : integer := 6;
  constant PH_COPY   : integer := 7;

  signal clk   : std_logic := '0';
  signal rdclk : std_logic := '0';
  signal rst   : std_logic := '1';

  signal f_index : std_logic := '1';
  signal f_rdata, f_track0, f_wprot, f_change : std_logic := '1';
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density, f_wgate, f_wdata : std_logic;

  signal phys_active, cia_motor_on : std_logic := '0';
  signal cia_side      : std_logic := '1';   -- '1' = logical side 0 (~PA0)
  signal step_req, step_outward : std_logic := '0';
  signal step_ack      : std_logic;
  signal rd_req        : std_logic := '0';
  signal rd_op         : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_track, rd_sector : unsigned(7 downto 0) := (others => '0');
  signal rd_seq        : std_logic_vector(1 downto 0) := "00";
  signal rd_cancel     : std_logic := '0';
  signal rd_done       : std_logic;
  signal rd_done_seq   : std_logic_vector(1 downto 0);
  signal rd_result     : std_logic_vector(4 downto 0);
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);
  signal byte_data     : unsigned(7 downto 0);
  signal byte_wr, fifo_full : std_logic;
  signal rd_en         : std_logic := '0';
  signal rd_data       : unsigned(7 downto 0);
  signal rd_empty      : std_logic;
  signal st_media_ready, st_head_settled : std_logic;
  signal d_rd_ahead, d_rd_ahead_drop, d_rd_req : std_logic;
  signal d_rd_phase    : std_logic_vector(3 downto 0);

  -- disk model
  signal g_cyl, g_side : integer := 0;          -- under the head (from the step and side pins)
  signal disk_sec, disk_off : integer := 0;     -- record being played and the offset in it
  signal cfg_badcrc    : integer := 0;          -- this sector ends with a bad data CRC
  signal cfg_deleted   : integer := 0;          -- this sector has the deleted data mark
  signal cfg_quiet     : std_logic := '0';      -- no record reaches the decoder
  signal cfg_change    : std_logic := '0';      -- disk-change line
  signal cfg_wprot     : std_logic := '0';      -- write-protect line

  -- monitor
  signal ph_seen   : std_logic_vector(15 downto 0) := (others => '0');  -- phases since the last acceptance
  signal n_ahead, n_drop, n_push : integer := 0;
  signal n_decrst  : integer := 0;              -- clocks with the decoder reset asserted
  signal n_gate    : integer := 0;              -- clocks with WGATE open
  signal t_acc     : time := 0 ns;              -- the clock after the last acceptance
  signal t_ds      : time := 0 ns;              -- the clock of the last data mark
  signal t_mk      : time := 0 ns;              -- the first data mark after mk_arm rose
  signal mk_arm    : std_logic := '0';
  signal mk_done   : boolean := false;

  -- payload byte i of sector (c, s, r)
  function pay(c, s, r, i : integer) return unsigned is
  begin
    return to_unsigned((c * 7 + s * 13 + r * 29 + i * 3 + i / 256) mod 256, 8);
  end function;
begin
  clk   <= not clk after C_CLK / 2;
  rdclk <= not rdclk after 15859 ps;            -- 31.5 MHz drive clock (FIFO read side)
  f_change <= not cfg_change;
  f_wprot  <= not cfg_wprot;

  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE => true, G_READY_WD_CYC => 50_000, G_DIR_SETUP_CYC => 10,
      G_STEP_LOW_CYC => 10, G_STEP_REC_CYC => 100, G_STEP_REV_CYC => 100,
      G_SETTLE_CYC => 2000, G_SIDE_SETTLE_CYC => 50, G_DAM_TIMEOUT_CYC => 200,
      G_SEARCH_WD_CYC => 400_000,
      G_PERIOD_MAX_CYC => 50_000_000)           -- one index edge per motor start keeps READY up
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
      diag_rd_phase_o => d_rd_phase, diag_rd_req_o => d_rd_req,
      diag_rd_ahead_o => d_rd_ahead, diag_rd_ahead_drop_o => d_rd_ahead_drop
    );

  i_fifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 9)                     -- the production depth
    port map (wr_clk_i => clk, wr_rst_i => rst, wr_en_i => byte_wr, wr_data_i => byte_data,
              wr_full_o => fifo_full, rd_clk_i => rdclk, rd_rst_i => rst, rd_en_i => rd_en,
              rd_data_o => rd_data, rd_empty_o => rd_empty);

  -- the head follows the step pulses (trailing edge) and the side pin
  geo : process (f_step, f_side1)
  begin
    if rising_edge(f_step) then
      if f_stepdir = '1' then g_cyl <= g_cyl - 1; else g_cyl <= g_cyl + 1; end if;
    end if;
    if f_side1 = '1' then g_side <= 1; else g_side <= 0; end if;
  end process;
  f_track0 <= '0' when g_cyl = 0 else '1';

  -- the disk: sectors 1 .. 10 in turn, one record per C_PITCH clocks. Every
  -- output is assigned right after a clock edge, like a decoder register.
  -- The geometry is sampled at the start of a record; a decoder reset, a
  -- motor stop, a step, a side change or a quiet disk cuts the record without
  -- a data end. ds_data_deleted changes only with a data end and keeps its
  -- value otherwise, as the decoder does.
  disk : process
    variable sec : integer := 1;
    variable gc, gs : integer;
    variable cut : boolean;
  begin
    wait until rising_edge(clk);
    if f_motora = '1' then
      wait until rising_edge(clk) and f_motora = '0';
    end if;
    gc := g_cyl; gs := g_side; cut := false;
    for off in 0 to C_PITCH - 1 loop
      wait until rising_edge(clk);
      disk_sec <= sec; disk_off <= off;
      ds_id_valid <= '0'; ds_data_start <= '0'; ds_data_byte_valid <= '0'; ds_data_end <= '0';
      ds_id_c <= x"EE"; ds_id_h <= x"EE"; ds_id_r <= x"EE"; ds_id_n <= x"EE"; ds_id_crc_ok <= '0';
      ds_data_byte <= x"EE"; ds_data_crc_ok <= '0';
      if ds_rst = '1' or f_motora = '1' or g_cyl /= gc or g_side /= gs or cfg_quiet = '1' then
        cut := true;
      end if;
      if not cut then
        if off = C_ID then
          ds_id_valid <= '1'; ds_id_crc_ok <= '1';
          ds_id_c <= to_unsigned(gc, 8); ds_id_h <= to_unsigned(gs, 8);
          ds_id_r <= to_unsigned(sec, 8); ds_id_n <= x"02";
        elsif off = C_DS then
          ds_data_start <= '1';
        elsif off >= C_D0 and (off - C_D0) mod C_BG = 0 and (off - C_D0) / C_BG < 512 then
          ds_data_byte <= pay(gc, gs, sec, (off - C_D0) / C_BG);
          ds_data_byte_valid <= '1';
        elsif off = C_DE then
          ds_data_end <= '1';
          if cfg_badcrc = sec then ds_data_crc_ok <= '0'; else ds_data_crc_ok <= '1'; end if;
          if cfg_deleted = sec then ds_data_deleted <= '1'; else ds_data_deleted <= '0'; end if;
        end if;
      end if;
    end loop;
    sec := (sec mod 10) + 1;
  end process;

  mon : process (clk)
    variable v : std_logic_vector(15 downto 0);
  begin
    if rising_edge(clk) then
      v := ph_seen;
      if d_rd_req = '1' then
        v := (others => '0'); t_acc <= now; n_push <= 0;
      elsif byte_wr = '1' then
        n_push <= n_push + 1;
      end if;
      v(to_integer(unsigned(d_rd_phase))) := '1';
      ph_seen <= v;
      if d_rd_ahead = '1' then n_ahead <= n_ahead + 1; end if;
      if d_rd_ahead_drop = '1' then n_drop <= n_drop + 1; end if;
      if ds_rst = '1' then n_decrst <= n_decrst + 1; end if;
      if f_wgate = '0' then n_gate <= n_gate + 1; end if;
      if ds_data_start = '1' then t_ds <= now; end if;
      if mk_arm = '0' then
        mk_done <= false;
      elsif ds_data_start = '1' and not mk_done then
        t_mk <= now; mk_done <= true;
      end if;
    end if;
  end process;

  stim : process
    type path_t is (P_LIVE, P_BUF, P_DROP, P_NOADOPT, P_ANY);
    variable seq   : unsigned(1 downto 0) := "00";
    variable pd    : std_logic;
    variable a0, d0, fails, nb, bad, k, r1, s, dd, r0c, r0d : integer := 0;
    variable t_done, t_req, t_mark : time;

    procedure chk(ok : boolean; what : string) is
    begin
      if not ok then
        report "FAIL: " & what severity error;
        fails := fails + 1;
      end if;
    end procedure;

    procedure clkw(n : natural) is
    begin
      for i in 1 to n loop wait until rising_edge(clk); end loop;
    end procedure;

    -- request parameters, stable two clocks before the toggle (fdc1772 sets
    -- them before it toggles the request)
    procedure set_req(op : std_logic_vector(2 downto 0); trk, sec : integer) is
    begin
      rd_op <= op; rd_track <= to_unsigned(trk, 8); rd_sector <= to_unsigned(sec, 8);
      seq := seq + 1; rd_seq <= std_logic_vector(seq);
      clkw(2);
    end procedure;

    procedure fire is
    begin
      pd := rd_done; a0 := n_ahead; d0 := n_drop;
      rd_req <= not rd_req; t_req := now;
    end procedure;

    procedure wait_done(tmo : time; what : string) is
    begin
      wait until rd_done /= pd for tmo;
      assert rd_done /= pd report "FAIL: " & what & ": no done within " & time'image(tmo) severity failure;
      chk(rd_done_seq = std_logic_vector(seq), what & ": the done carries the tag of its request");
      t_done := now;
      wait for 200 ns;                          -- the done through the WD's synchronizer
    end procedure;

    -- the WD front end takes the FIFO until it has been empty for 64 read
    -- clocks; with c >= 0 every byte is compared with sector (c, s, r)
    procedure drain(c, sd, r : integer; n : out integer; b : out integer) is
      variable idle, cnt, wrong : integer := 0;
    begin
      while idle < 64 loop
        wait until rising_edge(rdclk);
        if rd_empty = '0' then
          if c >= 0 and (cnt > 511 or rd_data /= pay(c, sd, r, cnt)) then wrong := wrong + 1; end if;
          rd_en <= '1'; cnt := cnt + 1; idle := 0;
          wait until rising_edge(rdclk); rd_en <= '0';
        else
          idle := idle + 1;
        end if;
      end loop;
      n := cnt; b := wrong;
    end procedure;

    impure function path_ok(p : path_t) return boolean is
      variable live : boolean;
    begin
      live := ph_seen(PH_WAIT) = '1' and ph_seen(PH_SEARCH) = '1' and
              ph_seen(PH_DAM) = '1' and ph_seen(PH_STREAM) = '1';
      case p is
        when P_LIVE    => return live and ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0'
                                 and n_ahead = a0 and n_drop = d0;
        when P_BUF     => return ph_seen(PH_WAIT) = '0' and ph_seen(PH_SEARCH) = '0' and
                                 ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '1'
                                 and n_ahead = a0 + 1 and n_drop = d0;
        when P_DROP    => return live and ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '0'
                                 and n_ahead = a0 and n_drop = d0 + 1;
        when P_NOADOPT => return ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0'
                                 and n_ahead = a0 and n_drop = d0;
        when P_ANY     => return true;
      end case;
    end function;

    impure function seen return string is
    begin
      return "phases " & to_hstring(ph_seen) & ", served " & integer'image(n_ahead - a0)
             & ", dropped " & integer'image(n_drop - d0);
    end function;

    -- the checks of a completed Read Sector of sector sec on the current
    -- geometry: result, ID, path, every byte
    procedure rs_check(sec : integer; p : path_t; what : string) is
    begin
      chk(rd_result = RES_OK and rd_crc_err = '0' and rd_rnf = '0',
          what & ": result OK, got " & to_hstring(rd_result));
      chk(to_integer(rd_c) = g_cyl and to_integer(rd_h) = g_side and to_integer(rd_r) = sec and rd_n = 2,
          what & ": the ID of the requested sector is reported, got R "
          & integer'image(to_integer(rd_r)));
      chk(path_ok(p), what & ": path " & path_t'image(p) & ", " & seen);
      drain(g_cyl, g_side, sec, nb, bad);
      chk(nb = 512 and bad = 0, what & ": the 512 bytes of the requested sector, got "
          & integer'image(nb) & " bytes, " & integer'image(bad) & " wrong");
    end procedure;

    -- a complete Read Sector with every check
    procedure rs(sec : integer; p : path_t; what : string) is
    begin
      set_req(RDOP_READ_SECTOR, g_cyl, sec);
      fire;
      wait_done(50 ms, what);
      rs_check(sec, p, what);
    end procedure;

    -- wait for a place on the disk: sector sec, offset off
    procedure at(sec, off : integer) is
    begin
      wait until rising_edge(clk) and disk_sec = sec and disk_off = off for 20 ms;
      assert disk_sec = sec and disk_off = off report "FAIL: the disk never reached sector "
        & integer'image(sec) & " offset " & integer'image(off) severity failure;
    end procedure;

    function nxt(sec : integer) return integer is
    begin
      return (sec mod 10) + 1;
    end function;

    procedure do_step(outward : std_logic) is
      variable a : std_logic;
    begin
      step_outward <= outward; clkw(2); a := step_ack; step_req <= not step_req;
      wait until step_ack /= a for 10 ms;
      assert step_ack /= a report "FAIL: no step acknowledge" severity failure;
      if st_head_settled /= '1' then wait until st_head_settled = '1' for 10 ms; end if;
    end procedure;

    procedure index_pulse is
    begin
      f_index <= '0'; wait for 210 us; f_index <= '1';   -- above the 200 us glitch floor
    end procedure;

    -- a live Read Sector two records ahead: it arms the read-ahead engine,
    -- which then captures the sectors that follow it
    procedure prime(sec : out integer; what : string) is
      variable q : integer;
    begin
      wait until rising_edge(clk) and disk_off = 0;
      q := nxt(nxt(disk_sec));
      rs(q, P_ANY, what & " (priming read)");
      sec := q;
    end procedure;

    procedure scen(name : string) is
    begin
      report "=== " & name;
    end procedure;
  begin
    wait for 100 ns; rst <= '0'; wait for 100 ns;
    phys_active <= '1'; cia_motor_on <= '1';
    wait for 2 us;
    index_pulse;
    wait until st_media_ready = '1' for 1 ms;
    assert st_media_ready = '1' report "FAIL: the drive never became ready" severity failure;

    ---------------------------------------------------------------------------
    scen("S1 the sector in flight");
    prime(k, "S1");
    at(nxt(k), C_DS + 400);                     -- its data field is on its way into the buffer
    rs(nxt(k), P_BUF, "S1 a request for the sector in flight waits for its capture");
    k := nxt(k);

    scen("S1b the request between the ID and the data mark");
    -- the capture has only its candidate ID: the buffer still holds older bytes
    at(nxt(nxt(k)), C_ID + 20);
    rs(nxt(nxt(k)), P_BUF, "S1b the controller waits for the data of the candidate");
    k := nxt(nxt(k));

    scen("S2 the held sector");
    at(nxt(k), C_DE + 20);
    rs(nxt(k), P_BUF, "S2 the held sector is served from the buffer");
    chk(t_done - t_req < 8400 * C_CLK, "S2 the held sector is served at once (one copy), took "
        & time'image(t_done - t_req));
    k := nxt(k);

    scen("S3 the sector just served, requested again");
    -- no longer held: delivered, and the next data mark has come as well
    -- (S15 isolates the release by the delivery)
    rs(k, P_LIVE, "S3 a sector that was served is read live when asked for again");

    ---------------------------------------------------------------------------
    scen("S4 Force Interrupt while idle");
    prime(k, "S4");
    at(nxt(k), C_DS + 400);
    rd_cancel <= not rd_cancel; clkw(10);
    rs(nxt(k), P_LIVE, "S4 a Force Interrupt switches the engine off");

    scen("S5 a step in and back");
    prime(k, "S5");
    at(nxt(k), C_DS + 100);
    do_step('0'); do_step('1');
    chk(g_cyl = 0, "S5 the head is back on cylinder 0");
    wait until rising_edge(clk) and disk_off = C_DE + 20;
    rs(disk_sec, P_LIVE, "S5 a step switches the engine off");

    scen("S6 a side flip and back");
    prime(k, "S6");
    at(nxt(k), C_DS + 100);
    cia_side <= '0'; clkw(3); cia_side <= '1';
    wait until rising_edge(clk) and disk_off = C_DE + 20;
    rs(disk_sec, P_LIVE, "S6 a side change switches the engine off");

    scen("S7 a Read Address in between");
    prime(k, "S7");
    set_req(RDOP_READ_ADDRESS, 0, 0); fire; wait_done(10 ms, "S7 Read Address");
    drain(-1, 0, 0, nb, bad);
    r1 := to_integer(rd_r);
    at(r1, C_DS + 400);
    rs(r1, P_LIVE, "S7 a Read Address switches the engine off");

    ---------------------------------------------------------------------------
    scen("S8 the held sector asked for with another track number");
    prime(k, "S8");
    at(nxt(k), C_DE + 20);                      -- C = 0, R = nxt(k) is held
    set_req(RDOP_READ_SECTOR, 1, nxt(k)); fire; wait_done(50 ms, "S8");
    chk(path_ok(P_NOADOPT), "S8 a held sector of another cylinder is not adopted, " & seen);
    chk(rd_result = RES_RECORD_NOT_FOUND, "S8 the request for track 1 ends with record not found, got "
        & to_hstring(rd_result) & " with C " & integer'image(to_integer(rd_c)));
    drain(-1, 0, 0, nb, bad);
    chk(nb = 0, "S8 nothing was pushed for the unmatched request");

    scen("S9 Force Interrupt in the middle of the copy");
    prime(k, "S9");
    at(nxt(k), C_DE + 20);
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    wait until rising_edge(clk) and n_push = 100 for 1 ms;
    chk(n_push = 100, "S9 the copy has begun");
    rd_cancel <= not rd_cancel;
    wait until rd_done /= pd for 1 us;
    chk(rd_done /= pd, "S9 the Force Interrupt ends the copy at once");
    if rd_done = pd then
      wait until rd_done /= pd for 10 ms;
    end if;
    wait for 200 ns;
    chk(rd_result = RES_CANCELLED and rd_rnf = '0' and rd_crc_err = '0' and
        rd_done_seq = std_logic_vector(seq), "S9 the cancelled copy reports RES_CANCELLED with its own tag, got "
        & to_hstring(rd_result));
    chk(n_ahead = a0 and n_drop = d0, "S9 a cancelled copy is neither served nor dropped");
    drain(-1, 0, 0, nb, bad);
    chk(nb = 100 or nb = 101, "S9 the pushes stop with the cancel: " & integer'image(nb) & " bytes drained");
    at(nxt(nxt(k)), C_DS + 400);
    rs(nxt(nxt(k)), P_LIVE, "S9 the engine is off after a Force Interrupt in the copy");

    scen("S10 the done gap after a copy");
    prime(k, "S10");
    at(nxt(k), C_DE + 20);
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    wait until rd_done /= pd for 5 ms;
    t_done := now;
    chk(rd_result = RES_OK, "S10 the first request is served");
    -- the next request, toggled in the clock that shows the done
    rd_sector <= to_unsigned(nxt(nxt(nxt(k))), 8);
    seq := seq + 1; rd_seq <= std_logic_vector(seq);
    pd := rd_done; a0 := n_ahead; d0 := n_drop;
    rd_req <= not rd_req;
    drain(0, 0, nxt(k), nb, bad);
    chk(nb = 512 and bad = 0, "S10 the first sector is delivered whole");
    -- the monitor sees an acceptance one clock after it; C_DONE_GAP is 8
    chk(t_acc - t_done >= 9 * C_CLK, "S10 a request toggled with the done is accepted only after the done gap, after "
        & time'image(t_acc - t_done));
    wait_done(50 ms, "S10 second request");
    drain(-1, 0, 0, nb, bad);

    ---------------------------------------------------------------------------
    scen("S11 the next data mark against the acceptance");
    -- The request for the held sector is toggled x clocks after the data mark
    -- of the following sector would be due; dd is the clock of that data mark
    -- minus the clock of the acceptance, measured:
    --   dd >= 2  the mark falls into the copy: it is skipped, the sector is
    --            served from the buffer, and the sector of the skipped mark is
    --            read live afterwards
    --   dd = 1   the mark falls into the clock in which RD_ADOPT commits: the
    --            buffer belongs to the copy already, same as above
    --   dd = 0   the mark falls into the acceptance clock: the engine releases
    --            the sector there, the adoption finds it gone (DROP)
    --   dd <= -1 the sector was released before the acceptance (LIVE)
    -- In this compressed track a capture writes the buffer four times as fast
    -- as the copy reads it, so a capture that starts during the copy would be
    -- seen in the bytes of the served sector.
    for x in -6 to 0 loop
      prime(k, "S11");
      at(nxt(k), C_DE + 20);                    -- nxt(k) is held
      mk_arm <= '1';
      rd_op <= RDOP_READ_SECTOR; rd_track <= to_unsigned(0, 8); rd_sector <= to_unsigned(nxt(k), 8);
      seq := seq + 1; rd_seq <= std_logic_vector(seq);
      at(nxt(nxt(k)), C_DS + x);
      fire;
      wait_done(50 ms, "S11");
      dd := (t_mk - t_acc) / C_CLK + 1;
      mk_arm <= '0';
      report "  S11 x=" & integer'image(x) & ": dd=" & integer'image(dd) & ", " & seen;
      if dd >= 1 then
        rs_check(nxt(k), P_BUF, "S11 dd=" & integer'image(dd) & ": the buffer belongs to the copy");
        rs(nxt(nxt(k)), P_LIVE, "S11 dd=" & integer'image(dd) & ": the sector of the skipped mark");
      elsif dd = 0 then
        rs_check(nxt(k), P_DROP, "S11 dd=0: the mark of the acceptance clock releases the sector");
      else
        rs_check(nxt(k), P_LIVE, "S11 dd=" & integer'image(dd) & ": released before the acceptance");
      end if;
    end loop;

    ---------------------------------------------------------------------------
    scen("S12 the disk-change line pulsed");
    prime(k, "S12");
    at(nxt(k), C_DS + 100);
    cfg_change <= '1'; clkw(20); cfg_change <= '0'; clkw(20);
    wait until rising_edge(clk) and disk_off = C_DE + 20;
    rs(disk_sec, P_LIVE, "S12 a disk change switches the engine off");

    scen("S13 the data CRC of the sector in flight is bad once");
    prime(k, "S13");
    cfg_badcrc <= nxt(k);
    at(nxt(k), C_DS + 400);
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    at(nxt(k), C_DE + 2);
    cfg_badcrc <= 0;
    wait_done(50 ms, "S13");
    rs_check(nxt(k), P_DROP, "S13 a capture with a bad CRC hands the request to the live path");
    chk(t_done - t_req > C_REV * C_CLK, "S13 the live read took the next pass");

    scen("S14 motor off and on again");
    prime(k, "S14");
    at(nxt(k), C_DS + 100);
    cia_motor_on <= '0'; clkw(10); cia_motor_on <= '1';
    index_pulse;
    wait until st_media_ready = '1' for 1 ms;
    chk(st_media_ready = '1', "S14 ready again after the index");
    wait until rising_edge(clk) and disk_off = C_DE + 20;
    rs(disk_sec, P_LIVE, "S14 a motor stop switches the engine off");

    ---------------------------------------------------------------------------
    scen("S15 the sector just served, requested again before any data mark");
    prime(k, "S15");
    at(nxt(k), C_DE + 20);
    cfg_quiet <= '1';                           -- no further record reaches the decoder
    rs(nxt(k), P_BUF, "S15 the held sector is served");
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    clkw(60);
    chk(ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0',
        "S15 the delivery releases the sector: it is not served a second time, " & seen);
    cfg_quiet <= '0';
    wait_done(50 ms, "S15 second request");
    rs_check(nxt(k), P_LIVE, "S15 the second request");

    scen("S16 the age of a held sector");
    -- The engine holds a sector up to and including the clock C_AGE_CYC after
    -- its data mark and releases it in the next one. The requests are toggled
    -- 1000 clocks before and 1000 clocks after that point: the acceptance
    -- follows the toggle within four clocks (two synchronizer stages, the edge
    -- detector, the acceptance), and the commit one clock later, far inside
    -- both margins.
    prime(k, "S16");
    at(nxt(k), C_DE + 1);
    cfg_quiet <= '1';                           -- nothing replaces the held sector
    t_mark := t_ds;                             -- the data mark of nxt(k)
    set_req(RDOP_READ_SECTOR, 0, nxt(k));
    wait for t_mark + (C_AGE_CYC - 1000) * C_CLK - now;
    wait until rising_edge(clk);
    fire;
    wait_done(5 ms, "S16 before");
    -- the age limit falls into this copy: the copy goes on, and the buffer
    -- stays the copy's although nothing is held any more
    rs_check(nxt(k), P_BUF, "S16 a sector 24 ms old less 1000 clocks is still served from the buffer");
    cfg_quiet <= '0';
    prime(k, "S16");
    at(nxt(k), C_DE + 1);
    cfg_quiet <= '1';
    t_mark := t_ds;
    set_req(RDOP_READ_SECTOR, 0, nxt(k));
    wait for t_mark + (C_AGE_CYC + 1000) * C_CLK - now;
    wait until rising_edge(clk);
    fire;
    clkw(60);
    chk(ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0',
        "S16 a sector 24 ms old plus 1000 clocks is no longer offered, " & seen);
    cfg_quiet <= '0';
    wait_done(50 ms, "S16 after");
    rs_check(nxt(k), P_LIVE, "S16 the request after the age limit");

    scen("S17 a write operation switches the engine off");
    -- WR_WAIT refuses the Write Sector on a write-protected disk in its first
    -- clock: no decoder reset, no gate, no data mark (the disk is quiet), so
    -- only the write operation itself can switch the engine off.
    prime(k, "S17");
    at(nxt(k), C_DE + 1);
    cfg_quiet <= '1';
    cfg_wprot <= '1';
    clkw(10);
    r0c := n_decrst; r0d := n_gate;
    set_req(WROP_WRITE_SECTOR, 0, nxt(k)); fire;
    wait_done(1 ms, "S17 Write Sector");
    chk(rd_result = RES_WRITE_PROTECTED, "S17 the Write Sector is refused as write protected, got "
        & to_hstring(rd_result));
    chk(n_decrst = r0c, "S17 the refused write did not reset the decoder");
    chk(n_gate = r0d, "S17 the refused write did not open the gate");
    cfg_wprot <= '0';
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    clkw(60);
    chk(ph_seen(PH_ADOPT) = '0' and ph_seen(PH_COPY) = '0',
        "S17 after a write operation the held sector is not offered, " & seen);
    cfg_quiet <= '0';
    wait_done(50 ms, "S17 read");
    rs_check(nxt(k), P_LIVE, "S17 the read after the write operation");

    ---------------------------------------------------------------------------
    scen("S18 the deleted data mark");
    -- live: the decoder shows the mark of a field with its data end, so the
    -- flag of the field before is still visible at the data mark
    wait until rising_edge(clk) and disk_off = 0;
    s := nxt(nxt(nxt(disk_sec)));
    cfg_deleted <= s;
    rd_cancel <= not rd_cancel; clkw(10);       -- the engine is off: the reads below are live
    rs(s, P_LIVE, "S18 a live read of the sector with the deleted mark");
    chk(rd_deleted = '1', "S18 a live read reports the deleted mark of its sector");
    rd_cancel <= not rd_cancel; clkw(10);
    rs(nxt(s), P_LIVE, "S18 a live read of the normal sector after the deleted one");
    chk(rd_deleted = '0', "S18 a live read of a normal sector right after a deleted one reports no deleted mark");
    -- buffer: the flag of the held sector, taken at its data end
    prime(k, "S18");
    cfg_deleted <= nxt(k);
    at(nxt(k), C_DS + 400);
    rs(nxt(k), P_BUF, "S18 the deleted sector from the buffer");
    chk(rd_deleted = '1', "S18 the buffer reports the deleted mark of the sector it serves");
    cfg_deleted <= 0;
    wait until rising_edge(clk) and disk_off = 0;
    s := nxt(disk_sec);
    at(s, C_DS + 400);
    rs(s, P_BUF, "S18 the next normal sector from the buffer");
    chk(rd_deleted = '0', "S18 the buffer reports no deleted mark for a normal sector");

    scen("S19 a copy into a full read FIFO");
    prime(k, "S19");
    at(nxt(k), C_DE + 20);
    set_req(RDOP_READ_SECTOR, 0, nxt(k)); fire;
    wait_done(5 ms, "S19 first copy");
    chk(rd_result = RES_OK, "S19 the first copy is served");
    -- the WD front end has not taken it: the FIFO holds 512 bytes. The next
    -- sector the engine captures after the copy:
    wait until rising_edge(clk) and ds_data_start = '1' for 1 ms;
    s := disk_sec;
    at(s, C_DE + 20);
    set_req(RDOP_READ_SECTOR, 0, s); fire;
    wait_done(5 ms, "S19 second copy");
    chk(rd_result = RES_DATA_CRC_ERROR and rd_crc_err = '1' and rd_rnf = '0',
        "S19 a copy into a full FIFO ends with the CRC flag alone, got " & to_hstring(rd_result));
    chk(ph_seen(PH_ADOPT) = '1' and ph_seen(PH_COPY) = '1' and ph_seen(PH_WAIT) = '0' and
        n_ahead = a0 and n_drop = d0, "S19 the failed copy is not counted as served, " & seen);
    drain(0, 0, nxt(k), nb, bad);
    chk(nb = 512 and bad = 0, "S19 the FIFO holds the first sector, untouched by the failed copy: "
        & integer'image(nb) & " bytes, " & integer'image(bad) & " wrong");
    rs(s, P_LIVE, "S19 the sector of the failed copy is read live");

    ---------------------------------------------------------------------------
    wait for 1 us;
    if fails = 0 then
      report "tb_physical_1581_rdahead_ctl: ALL TESTS PASSED; " & integer'image(n_ahead)
           & " sectors from the read-ahead buffer, " & integer'image(n_drop) & " adoptions given up";
    else
      report "tb_physical_1581_rdahead_ctl: " & integer'image(fails) & " CHECKS FAILED" severity failure;
    end if;
    finish;
  end process;

  guard : process
  begin
    wait for 500 ms;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
