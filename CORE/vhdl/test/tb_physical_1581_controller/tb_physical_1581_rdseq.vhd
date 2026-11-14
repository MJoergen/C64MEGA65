-------------------------------------------------------------------------------
-- tb_physical_1581_rdseq.vhd
--
-- Sequential-read latency of the physical internal 1581 (issue #257): the
-- controller, the production read FIFO and the mechanism model, driven the way
-- the stock 1581 DOS fills its track cache through the WD1772 front end
-- (fdc1772.v, delivery v2):
--   * Read Address, then Read Sector R+1 .. R, wrapping 10 -> 1 (ROM $C900),
--   * the front end releases a sector only after the controller's clean done
--     (CRC quarantine) and then presents it at disk pace, one byte per
--     byte-time (252 ticks of the 7.88 MHz WD clock enable),
--   * BUSY drops one byte-time after the last byte, and the DOS issues the
--     next Read Sector G_GAP_US later (measured on the genuine ROM: 66 to
--     67.5 us between two Read Sectors, 93.5 us at the wrap from sector 10
--     to sector 1, 2.26 ms after a Read Address).
-- The bench checks every presented byte against the golden disk and reports
-- how long the G_NSEC sectors took, how many of them the controller served
-- from its read-ahead buffer (diag_rd_ahead_o), how many adoptions it gave up
-- (diag_rd_ahead_drop_o) and how many sectors waited for the next revolution.
-- A real 1581 reads a track side in little more than one revolution;
-- G_MAX_MS /= 0 makes the bench fail if the fill takes longer than that many
-- milliseconds.
--
-- G_GAP_US moves the request through every phase of the following record
-- (before its ID, inside the ID, in the gap, inside the data field, after the
-- data field): whatever the phase, the data must be the golden sector.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.golden_1581_pkg.all;

entity tb_physical_1581_rdseq is
  generic (
    G_NSEC   : integer := 10;     -- Read Sectors after the Read Address
    G_GAP_US : integer := 67;     -- BUSY drop -> next Read Sector command
    G_CYL    : integer := 0;      -- cylinder to read (the head starts on 0)
    G_MAX_MS : integer := 0       -- 0 = report only
  );
end entity;

architecture sim of tb_physical_1581_rdseq is
  constant C_PACE : time := 31972 ns;        -- 252 ticks of 31.527778 MHz / 4

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

  signal st_media_ready : std_logic;
  signal idx_edges : integer := 0;

  -- read-ahead observation
  signal d_rd_ahead, d_rd_ahead_drop : std_logic;
  signal n_ahead, n_drop : integer := 0;
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
      st_media_ready_o => st_media_ready,
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
      cfg_present_i => '1', cfg_wprot_i => '0', cfg_change_i => '0',
      f_index_o => f_index, f_track0_o => f_track0, f_writeprotect_o => f_wprot,
      f_diskchanged_o => f_change, f_rdata_o => f_rdata,
      f_wgate_i => f_wgate, f_wdata_i => f_wdata
    );

  idx_cnt : process (f_index)
  begin
    if falling_edge(f_index) then
      idx_edges <= idx_edges + 1;
    end if;
  end process;

  ra_cnt : process (clk)
  begin
    if rising_edge(clk) then
      if d_rd_ahead = '1' then n_ahead <= n_ahead + 1; end if;
      if d_rd_ahead_drop = '1' then n_drop <= n_drop + 1; end if;
    end if;
  end process;

  stim : process
    variable seq_cnt   : unsigned(1 downto 0) := "00";
    variable prev_done : std_logic;
    variable prev_ack  : std_logic;
    variable cur       : integer;       -- sector number under test
    variable t_start, t_req, t_done, t_busy : time;
    variable idx0      : integer;
    variable b         : unsigned(7 downto 0);
    variable bad       : integer := 0;
    variable n_slow    : integer := 0;
    variable a0        : integer;       -- n_ahead before the request

    -- one WD command as fdc1772 issues it: request, wait for the tagged done
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
      assert rd_done_seq = std_logic_vector(seq_cnt) report "FAIL: wrong done tag" severity failure;
      t_done := now;
      wait for 160 ns;                          -- done toggle through the WD's synchronizer
    end procedure;

    -- the WD front end's paced presentation of n bytes; cmp = compare with
    -- the golden sector (cyl, side 0, secn)
    procedure wd_present(n : integer; cmp : boolean; cyl, secn : integer) is
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
        if cmp and b /= golden_payload(cyl, 0, secn, i) then
          bad := bad + 1;
          if bad <= 8 then
            report "FAIL: sector " & integer'image(secn) & " byte " & integer'image(i)
                 & " = " & to_hstring(std_logic_vector(b)) severity error;
          end if;
        end if;
        wait for C_PACE - (now - t0);
      end loop;
      wait for C_PACE;                          -- BUSY outlives the last byte by one byte-time
      t_busy := now;
    end procedure;
  begin
    wait for 200 ns;
    rst <= '0';
    wait for 1 us;
    phys_active  <= '1';
    cia_motor_on <= '1';
    wait until st_media_ready = '1' for 2 sec;
    assert st_media_ready = '1' report "FAIL: media never ready" severity failure;

    -- seek to the cylinder under test (Type-I steps with their own handshake)
    for i in 1 to G_CYL loop
      step_outward <= '0';
      wait until rising_edge(clk);
      prev_ack := step_ack;
      step_req <= not step_req;
      wait until step_ack /= prev_ack for 1 sec;
      assert step_ack /= prev_ack report "TIMEOUT waiting for step_ack" severity failure;
    end loop;
    wait for 19 ms;                             -- the DOS's head settle

    -- Read Address, as the DOS does before every cache fill
    wd_op(RDOP_READ_ADDRESS, G_CYL, 0);
    assert rd_result = RES_OK report "FAIL: Read Address result" severity failure;
    cur := to_integer(rd_r);
    wd_present(6, false, 0, 0);
    report "Read Address found sector " & integer'image(cur);
    wait for 2200 us;                           -- software CRC check of the reply ($DA63)

    t_start := now;
    idx0    := idx_edges;
    for k in 1 to G_NSEC loop
      cur := cur + 1;
      if cur = 11 then cur := 1; end if;
      a0 := n_ahead;
      wd_op(RDOP_READ_SECTOR, G_CYL, cur);
      assert rd_result = RES_OK and rd_crc_err = '0' and rd_rnf = '0'
        report "FAIL: Read Sector " & integer'image(cur) & " result "
             & to_hstring("000" & rd_result) severity failure;
      assert to_integer(rd_r) = cur and to_integer(rd_c) = G_CYL
        report "FAIL: Read Sector reported the wrong ID" severity failure;
      if n_ahead /= a0 then
        report "sector " & integer'image(cur) & ": request -> done "
             & time'image(t_done - t_req) & " (from the read-ahead buffer)";
      else
        report "sector " & integer'image(cur) & ": request -> done "
             & time'image(t_done - t_req) & " (live)";
      end if;
      if t_done - t_req > 100 ms then
        n_slow := n_slow + 1;
      end if;
      wd_present(512, true, G_CYL, cur);
      wait until rising_edge(rdclk);
      assert rd_empty = '1' report "FAIL: residue in the read FIFO after a sector" severity failure;
      wait for G_GAP_US * 1 us;
    end loop;

    report "RDSEQ: " & integer'image(G_NSEC) & " sectors, gap " & integer'image(G_GAP_US)
         & " us: " & time'image(now - t_start) & ", "
         & integer'image(idx_edges - idx0) & " index pulses, "
         & integer'image(n_ahead) & " sectors from the read-ahead buffer, "
         & integer'image(n_drop) & " adoptions given up, "
         & integer'image(n_slow) & " sectors waited for the next revolution, "
         & integer'image(bad) & " wrong bytes";
    assert bad = 0 report "FAIL: wrong data" severity failure;
    if G_MAX_MS /= 0 then
      assert now - t_start <= G_MAX_MS * 1 ms
        report "FAIL: the fill took longer than " & integer'image(G_MAX_MS) & " ms" severity failure;
    end if;
    report "ALL TESTS PASSED";
    finish;
  end process;

end architecture sim;
