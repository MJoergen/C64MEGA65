-------------------------------------------------------------------------------
-- tb_physical_1581_controller.vhd
--
-- Closed-loop functional test of physical_1581_controller: controller +
-- physical_1581_rdfifo (read-byte stream) + mech_model_1581 (the mechanism).
-- The controller drives motor/select/side/step to the model; the model spins,
-- moves its head on STEP, and emits real DD-MFM flux for the current cylinder/
-- side. The test issues drive-domain requests over the toggle ABI and checks:
--   * media becomes ready
--   * Read Sector (cyl0,sec1) returns RES_OK and all 512 bytes == golden payload
--   * Read Address returns the current cylinder's C/N and 6 bytes
--   * Verify (cyl0) returns RES_OK
--   * a Type-I Step In moves the head to cyl1; Read Sector (cyl1,sec1) matches
--   * Read Sector for a non-existent sector returns RNF
--
-- Controller timing generics are scaled so only INDEX-paced behavior costs real
-- sim time (flux is emitted at true 2 us MFM timing and cannot be sped up).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.golden_1581_pkg.all;

entity tb_physical_1581_controller is
end entity;

architecture sim of tb_physical_1581_controller is
  signal clk    : std_logic := '0';           -- 50 MHz controller clock
  signal rdclk  : std_logic := '0';           -- ~16 MHz drive-side FIFO read clock
  signal rst    : std_logic := '1';

  -- controller <-> mechanism pins
  signal f_rdata, f_index, f_track0, f_wprot, f_change : std_logic;
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;

  -- controller ABI
  signal phys_active   : std_logic := '0';
  signal cia_motor_on  : std_logic := '0';
  signal cia_side      : std_logic := '0';
  signal step_req      : std_logic := '0';
  signal step_outward  : std_logic := '0';
  signal step_ack      : std_logic;
  signal rd_req        : std_logic := '0';
  signal rd_op         : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_track      : unsigned(7 downto 0) := (others => '0');
  signal rd_side       : std_logic := '0';
  signal rd_sector     : unsigned(7 downto 0) := (others => '0');
  signal rd_cancel     : std_logic := '0';
  signal rd_done       : std_logic;
  signal rd_result     : std_logic_vector(4 downto 0);
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);

  -- controller -> rdfifo -> drain
  signal byte_data : unsigned(7 downto 0);
  signal byte_wr   : std_logic;
  signal fifo_full : std_logic;
  signal rd_en     : std_logic;
  signal rd_data   : unsigned(7 downto 0);
  signal rd_empty  : std_logic;

  signal st_media_ready, st_index, st_track0, st_wprot, st_change : std_logic;
  signal st_motor_on, st_head_settled, st_locked : std_logic;
  signal st_head_cyl : unsigned(7 downto 0);

  signal cur_cyl : integer;

  -- capture
  type arr_t is array (0 to 4095) of unsigned(7 downto 0);
  signal cap     : arr_t := (others => (others => '0'));
  signal cap_idx : integer := 0;

  function hs(v : unsigned) return string is
  begin return to_hstring(std_logic_vector(v)); end function;
begin

  clk   <= not clk   after 10 ns;   -- 50 MHz
  rdclk <= not rdclk after 30 ns;   -- ~16.7 MHz

  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE => true,
      G_MOTOR_READY_CYC => 5_000,          -- 100 us (index-edge gate dominates)
      G_READY_WD_CYC    => 150_000_000,    -- 3 s
      G_SEARCH_EDGES    => 3,              -- keep RNF bounded (~ up to 3 index periods)
      G_PERIOD_MIN_CYC  => 7_500_000,      -- 150 ms
      G_PERIOD_MAX_CYC  => 12_500_000      -- 250 ms
    )
    port map (
      clk_i => clk, rst_i => rst,
      f_rdata_i => f_rdata, f_index_i => f_index, f_track0_i => f_track0,
      f_writeprotect_i => f_wprot, f_diskchanged_i => f_change,
      f_motora_o => f_motora, f_selecta_o => f_selecta, f_side1_o => f_side1,
      f_stepdir_o => f_stepdir, f_step_o => f_step, f_density_o => f_density,
      phys_active_i => phys_active, cia_motor_on_i => cia_motor_on, cia_side_i => cia_side,
      step_req_tgl_i => step_req, step_outward_i => step_outward, step_ack_tgl_o => step_ack,
      rd_req_tgl_i => rd_req, rd_op_i => rd_op, rd_track_i => rd_track, rd_side_i => rd_side,
      rd_sector_i => rd_sector, rd_cancel_tgl_i => rd_cancel, rd_done_tgl_o => rd_done,
      rd_result_o => rd_result, rd_crc_err_o => rd_crc_err, rd_rnf_o => rd_rnf,
      rd_deleted_o => rd_deleted, rd_c_o => rd_c, rd_h_o => rd_h, rd_r_o => rd_r, rd_n_o => rd_n,
      byte_data_o => byte_data, byte_wr_o => byte_wr, byte_ovf_i => fifo_full,
      st_media_ready_o => st_media_ready, st_index_o => st_index, st_track0_o => st_track0,
      st_wprot_o => st_wprot, st_change_o => st_change, st_motor_on_o => st_motor_on,
      st_head_settled_o => st_head_settled, st_head_cyl_o => st_head_cyl, st_locked_o => st_locked
    );

  i_fifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 6)
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
      f_diskchanged_o => f_change, f_rdata_o => f_rdata, cur_cyl_o => cur_cyl
    );

  -- greedily drain the read FIFO into cap[]
  rd_en <= not rd_empty;
  drain : process (rdclk)
  begin
    if rising_edge(rdclk) then
      if rd_empty = '0' then
        cap(cap_idx) <= rd_data;
        cap_idx <= cap_idx + 1;
      end if;
    end if;
  end process;

  stim : process
    variable prev_done : std_logic;
    variable prev_ack  : std_logic;
    variable base      : integer;

    procedure do_read(op : std_logic_vector(2 downto 0); trk, secn : integer) is
    begin
      rd_op     <= op;
      rd_track  <= to_unsigned(trk, 8);
      rd_sector <= to_unsigned(secn, 8);
      rd_side   <= '0';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      prev_done := rd_done;
      rd_req <= not rd_req;                        -- fire request
      wait until rd_done /= prev_done for 2 sec;
      assert rd_done /= prev_done report "TIMEOUT waiting for rd_done" severity failure;
    end procedure;

    procedure do_step(outward : std_logic) is
    begin
      step_outward <= outward;
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      prev_ack := step_ack;
      step_req <= not step_req;
      wait until step_ack /= prev_ack for 1 sec;
      assert step_ack /= prev_ack report "TIMEOUT waiting for step_ack" severity failure;
    end procedure;

    procedure check_payload(cyl, side, secn : integer) is
    begin
      wait for 200 us;                              -- let the FIFO fully drain
      assert (cap_idx - base) = 512
        report "FAIL: got " & integer'image(cap_idx - base) & " bytes, expected 512" severity error;
      for off in 0 to 511 loop
        assert cap(base + off) = golden_payload(cyl, side, secn, off)
          report "FAIL: payload["&integer'image(off)&"]="&hs(cap(base+off))
               & " exp "&hs(golden_payload(cyl,side,secn,off)) severity error;
      end loop;
      report "  payload cyl="&integer'image(cyl)&" sec="&integer'image(secn)&" MATCH (512 bytes)";
    end procedure;
  begin
    rst <= '1'; wait for 500 ns; rst <= '0'; wait for 500 ns;
    phys_active <= '1'; cia_motor_on <= '1'; cia_side <= '0';
    wait for 50 us;                                 -- let active/motor synchronize

    -- Restore: one outward STEP clears the conservative power-up disk-change latch
    -- and anchors the head at track 0. The real 1581 ROM restores at init; the
    -- controller permits Type-I stepping while media_ready is still false (spec 13.2).
    do_step('1');
    report "Restore step done (clears power-up disk-change latch); cur_cyl=" & integer'image(cur_cyl);

    -- wait for media ready
    wait until st_media_ready = '1' for 2 sec;
    assert st_media_ready = '1' report "FAIL: media never ready" severity failure;
    report "media_ready asserted, head_settled=" & std_logic'image(st_head_settled);
    wait until st_head_settled = '1' for 100 ms;

    -- === Read Sector cyl0 sec1 =============================================
    base := cap_idx;
    do_read(RDOP_READ_SECTOR, 0, 1);
    assert rd_result = RES_OK report "FAIL: read0 result=" & hs("000" & unsigned(rd_result)) severity error;
    report "Read Sector cyl0 sec1: result OK, R=" & hs(rd_r) & " N=" & hs(rd_n) & " deleted=" & std_logic'image(rd_deleted);
    check_payload(0, 0, 1);

    -- === Read Address (current cyl) ========================================
    base := cap_idx;
    do_read(RDOP_READ_ADDRESS, 0, 0);
    assert rd_c = x"00" report "FAIL: read-address C=" & hs(rd_c) & " expected 00" severity error;
    assert rd_n = x"02" report "FAIL: read-address N=" & hs(rd_n) & " expected 02" severity error;
    wait for 50 us;
    assert (cap_idx - base) = 6 report "FAIL: read-address produced " & integer'image(cap_idx-base) & " bytes, expected 6" severity error;
    assert cap(base) = x"00" report "FAIL: read-address byte0 (C) = " & hs(cap(base)) severity error;
    assert cap(base+3) = x"02" report "FAIL: read-address byte3 (N) = " & hs(cap(base+3)) severity error;
    report "Read Address: C=" & hs(rd_c) & " R=" & hs(rd_r) & " N=" & hs(rd_n) & " (6 bytes)";

    -- === Verify cyl0 =======================================================
    do_read(RDOP_VERIFY, 0, 0);
    assert rd_result = RES_OK report "FAIL: verify result=" & hs("000" & unsigned(rd_result)) severity error;
    report "Verify cyl0: OK";

    -- === Step In to cyl1, then Read Sector cyl1 sec1 =======================
    do_step('0');                                   -- outward='0' -> toward higher cylinder
    wait for 100 us;
    assert cur_cyl = 1 report "FAIL: after step, model cur_cyl=" & integer'image(cur_cyl) & " expected 1" severity error;
    report "Step In: head now at cyl " & integer'image(cur_cyl) & " (estimate " & hs(st_head_cyl) & ")";
    -- wait for head settle after the step
    wait until st_head_settled = '1' for 100 ms;
    base := cap_idx;
    do_read(RDOP_READ_SECTOR, 1, 1);
    assert rd_result = RES_OK report "FAIL: read1 result=" & hs("000" & unsigned(rd_result)) severity error;
    report "Read Sector cyl1 sec1: OK";
    check_payload(1, 0, 1);

    -- === Read a non-existent sector -> RNF =================================
    do_read(RDOP_READ_SECTOR, 1, 11);
    assert rd_result = RES_RECORD_NOT_FOUND report "FAIL: bad-sector result=" & hs("000" & unsigned(rd_result)) & " expected RNF" severity error;
    assert rd_rnf = '1' report "FAIL: bad-sector rnf not set" severity error;
    report "Read Sector cyl1 sec11 (absent): RNF as expected";

    report "physical_1581_controller: ALL TESTS PASSED";
    finish;
  end process;

  guard : process
  begin
    wait for 6 sec;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
