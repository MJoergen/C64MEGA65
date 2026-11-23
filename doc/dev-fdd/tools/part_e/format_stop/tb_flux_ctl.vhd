-- tb_flux_ctl: end-to-end replay of the failing format verify (issue #257, part E).
-- Unmodified copies of the production controller (with its decoder and
-- read-ahead engine) and read FIFO; the mechanism is replaced by a player of
-- the Greaseweazle flux of cylinder 77, side ID H=1 (tools/mkflux.py edge
-- file, the three captured revolutions looped) with a 2 ms index pulse at the
-- start of every revolution. The WD front end is the paced presentation of
-- tb_physical_1581_rdseq. Sequence as in the dump: Read Address, then Read
-- Sector R+1 ... up to sector 7, then G_EXTRA_REVS revolutions idle with the
-- motor on. Logs every request/result and the decoder counters per phase.
-- G_TOL_OFF = 1 switches the decoder's tolerance for a weak first sync byte
-- off (dec_tol_off_i); "tol" counts diag_tol_hit_o.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use std.textio.all;
use work.physical_1581_pkg.all;

entity tb_flux_ctl is
  generic (G_IN : string := "flux.txt"; G_REV_CYC : natural := 9954550;
           G_LAST : integer := 7; G_EXTRA_REVS : integer := 2;
           G_TOL_OFF : natural := 0);
end entity;

architecture sim of tb_flux_ctl is
  constant C_PACE : time := 31972 ns;
  signal clk    : std_logic := '0';
  signal rdclk  : std_logic := '0';
  signal rst    : std_logic := '1';
  signal cyc    : natural := 0;
  signal f_rdata : std_logic := '1';
  signal f_index : std_logic := '1';
  signal f_track0 : std_logic := '1';
  signal f_wprot  : std_logic := '1';
  signal f_change : std_logic := '1';
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;
  signal f_wgate, f_wdata : std_logic;
  signal phys_active   : std_logic := '0';
  signal cia_motor_on  : std_logic := '0';
  signal cia_side      : std_logic := '0';   -- '0' = logical side 1 = ID H=1
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
  signal st_media_ready : std_logic;
  signal d_rd_ahead, d_rd_ahead_drop, d_idx, d_match, d_dmiss : std_logic;
  signal d_cand, d_rej, d_train, d_fe, d_dam, d_unarm, d_gerr, d_idv : std_logic;
  signal n_ahead, n_drop, n_idx, n_match, n_dmiss : integer := 0;
  signal tol_off, d_tol : std_logic := '0';
  signal n_tol : integer := 0;
  signal n_cand, n_rej, n_train, n_fe, n_dam, n_unarm, n_gerr, n_idv : integer := 0;
begin
  clk   <= not clk   after 10 ns;
  rdclk <= not rdclk after 15859 ps;
  tol_off <= '1' when G_TOL_OFF /= 0 else '0';

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
      st_media_ready_o => st_media_ready,
      diag_rd_ahead_o => d_rd_ahead, diag_rd_ahead_drop_o => d_rd_ahead_drop,
      diag_index_qual_o => d_idx, diag_match_id_o => d_match, diag_dam_miss_o => d_dmiss,
      diag_a1_candidate_o => d_cand, diag_a1_reject_o => d_rej, diag_a1_train_o => d_train,
      diag_mark_fe_o => d_fe, diag_mark_dam_o => d_dam, diag_dam_unarmed_o => d_unarm,
      diag_gap_error_o => d_gerr, diag_id_valid_o => d_idv,
      dec_tol_off_i => tol_off, diag_tol_hit_o => d_tol
    );

  i_fifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 9)
    port map (
      wr_clk_i => clk, wr_rst_i => rst, wr_en_i => byte_wr, wr_data_i => byte_data, wr_full_o => fifo_full,
      rd_clk_i => rdclk, rd_rst_i => rst, rd_en_i => rd_en, rd_data_o => rd_data, rd_empty_o => rd_empty
    );

  cnt : process (clk)
  begin
    if rising_edge(clk) then
      cyc <= cyc + 1;
      if d_rd_ahead = '1' then n_ahead <= n_ahead + 1; end if;
      if d_rd_ahead_drop = '1' then n_drop <= n_drop + 1; end if;
      if d_idx = '1' then n_idx <= n_idx + 1; end if;
      if d_match = '1' then n_match <= n_match + 1; end if;
      if d_dmiss = '1' then n_dmiss <= n_dmiss + 1; end if;
      if d_cand = '1' then n_cand <= n_cand + 1; end if;
      if d_rej = '1' then n_rej <= n_rej + 1; end if;
      if d_train = '1' then n_train <= n_train + 1; end if;
      if d_fe = '1' then n_fe <= n_fe + 1; end if;
      if d_dam = '1' then n_dam <= n_dam + 1; end if;
      if d_unarm = '1' then n_unarm <= n_unarm + 1; end if;
      if d_gerr = '1' then n_gerr <= n_gerr + 1; end if;
      if d_idv = '1' then n_idv <= n_idv + 1; end if;
      if d_tol = '1' then n_tol <= n_tol + 1; end if;
    end if;
  end process;

  -- the disk: flux edges from the file, index pulse every G_REV_CYC cycles
  -- (flux and index share cycle 100 as the start of revolution 0); the disk
  -- turns from the start of the simulation, as a disk that was spinning
  player : process
    file fin : text open read_mode is G_IN;
    variable l : line;
    variable t : natural;
    variable good : boolean;
  begin
    while not endfile(fin) loop
      readline(fin, l);
      read(l, t, good);
      if good then
        while cyc < t loop wait until rising_edge(clk); end loop;
        f_rdata <= '0';
        for i in 1 to 10 loop wait until rising_edge(clk); end loop;
        f_rdata <= '1';
      end if;
    end loop;
    report "flux file exhausted" severity warning;
    wait;
  end process;

  indexp : process
    variable k : natural := 0;
  begin
    loop
      while cyc < 100 + k * G_REV_CYC loop wait until rising_edge(clk); end loop;
      f_index <= '0';
      while cyc < 100 + k * G_REV_CYC + 100000 loop wait until rising_edge(clk); end loop;
      f_index <= '1';
      k := k + 1;
    end loop;
  end process;

  stim : process
    variable seq_cnt   : unsigned(1 downto 0) := "00";
    variable prev_done : std_logic;
    variable cur       : integer;
    variable t_req, t_done : time;
    variable b         : unsigned(7 downto 0);
    variable bad       : integer := 0;
    variable a0, i0    : integer;
    variable l         : line;

    procedure counters(tag : string) is
    begin
      report tag & ": idx=" & integer'image(n_idx) & " cand=" & integer'image(n_cand)
        & " train=" & integer'image(n_train) & " FE=" & integer'image(n_fe)
        & " IDdec=" & integer'image(n_idv) & " DAM=" & integer'image(n_dam)
        & " unarmed=" & integer'image(n_unarm) & " match=" & integer'image(n_match)
        & " dam_miss=" & integer'image(n_dmiss) & " rej=" & integer'image(n_rej)
        & " gaperr=" & integer'image(n_gerr) & " ahead=" & integer'image(n_ahead)
        & " drop=" & integer'image(n_drop) & " tol=" & integer'image(n_tol);
    end procedure;

    procedure wd_op(op : std_logic_vector(2 downto 0); trk, secn : integer) is
    begin
      rd_op     <= op;
      rd_track  <= to_unsigned(trk, 8);
      rd_sector <= to_unsigned(secn, 8);
      seq_cnt   := seq_cnt + 1;
      rd_seq    <= std_logic_vector(seq_cnt);
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      prev_done := rd_done;
      rd_req    <= not rd_req;
      t_req     := now;
      wait until rd_done /= prev_done for 3 sec;
      assert rd_done /= prev_done report "TIMEOUT waiting for rd_done" severity failure;
      t_done := now;
      wait for 160 ns;
    end procedure;

    procedure wd_present(n : integer; cmp : boolean) is
      variable t0 : time;
    begin
      for i in 0 to n - 1 loop
        t0 := now;
        wait until rising_edge(rdclk);
        if rd_empty = '1' then
          wait until rising_edge(rdclk) and rd_empty = '0' for 1 ms;
        end if;
        assert rd_empty = '0' report "FAIL: read FIFO ran dry in a clean sector" severity failure;
        b := rd_data;
        rd_en <= '1';
        wait until rising_edge(rdclk);
        rd_en <= '0';
        if cmp and b /= x"00" then bad := bad + 1; end if;
        wait for C_PACE - (now - t0);
      end loop;
      wait for C_PACE;
    end procedure;
  begin
    wait for 200 ns;
    rst <= '0';
    wait for 1 us;
    phys_active  <= '1';
    cia_motor_on <= '1';
    wait until st_media_ready = '1' for 2 sec;
    assert st_media_ready = '1' report "FAIL: media never ready" severity failure;
    -- the dump: Write Track ended at an index, then Read Address 1.98 ms later
    wait until f_index = '0';
    wait for 1980 us;
    counters("before RA");
    wd_op(RDOP_READ_ADDRESS, 77, 0);
    report "RA result " & to_hstring("000" & rd_result) & " C=" & integer'image(to_integer(rd_c))
      & " H=" & integer'image(to_integer(rd_h)) & " R=" & integer'image(to_integer(rd_r));
    cur := to_integer(rd_r);
    wd_present(6, false);
    wait for 2200 us;
    loop
      cur := cur + 1;
      if cur = 11 then cur := 1; end if;
      a0 := n_ahead; i0 := n_idx;
      wd_op(RDOP_READ_SECTOR, 77, cur);
      report "RS " & integer'image(cur) & ": result " & to_hstring("000" & rd_result)
        & " rnf=" & std_logic'image(rd_rnf) & " crc=" & std_logic'image(rd_crc_err)
        & " CHR=" & integer'image(to_integer(rd_c)) & "/" & integer'image(to_integer(rd_h))
        & "/" & integer'image(to_integer(rd_r))
        & " took " & time'image(t_done - t_req) & ", index edges " & integer'image(n_idx - i0)
        & ", from buffer " & boolean'image(n_ahead /= a0);
      if rd_result = RES_OK then
        wd_present(512, true);
        wait for 67 us;
      else
        exit;
      end if;
      exit when cur = G_LAST;
    end loop;
    counters("after the last Read Sector");
    for k in 1 to G_EXTRA_REVS loop
      wait for 199091 us;
      counters("motor on, one more revolution");
    end loop;
    report "nonzero bytes presented: " & integer'image(bad);
    report "END";
    finish;
  end process;
end architecture sim;
