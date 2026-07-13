-------------------------------------------------------------------------------
-- tb_physical_1581_ovf.vhd
--
-- Regression test for the silent-FIFO-overflow bug (issue #90 bring-up): a
-- READ SECTOR is issued against a deliberately tiny (4-entry) read FIFO whose
-- consumer NEVER drains -- modeling the drive CPU being stolen away by IEC/IRQ
-- work mid-sector. The controller MUST NOT complete the operation as OK with a
-- silently truncated stream: it must report RES_DATA_CRC_ERROR with both the
-- CRC and RNF flags set (RNF releases the WD front end, CRC makes the DOS
-- re-read, mirroring a real WD1772 LOST DATA situation). On hardware, the old
-- silent drop produced shifted directory names and programs that loaded but
-- did not run.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;

entity tb_physical_1581_ovf is
end entity;

architecture sim of tb_physical_1581_ovf is
  signal clk   : std_logic := '0';
  signal rdclk : std_logic := '0';
  signal rst   : std_logic := '1';

  signal f_rdata, f_index, f_track0, f_wprot, f_change : std_logic;
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;

  signal phys_active  : std_logic := '0';
  signal cia_motor_on : std_logic := '0';
  signal cia_side     : std_logic := '1';          -- logical side 0
  signal step_req     : std_logic := '0';
  signal step_outward : std_logic := '1';
  signal step_ack     : std_logic;
  signal rd_req       : std_logic := '0';
  signal rd_op        : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_track     : unsigned(7 downto 0) := (others => '0');
  signal rd_side      : std_logic := '1';
  signal rd_sector    : unsigned(7 downto 0) := to_unsigned(1, 8);
  signal rd_cancel    : std_logic := '0';
  signal rd_done      : std_logic;
  signal rd_result    : std_logic_vector(4 downto 0);
  signal rd_crc_err, rd_rnf, rd_deleted : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);

  signal byte_data : unsigned(7 downto 0);
  signal byte_wr   : std_logic;
  signal fifo_full : std_logic;
  signal rd_data   : unsigned(7 downto 0);
  signal rd_empty  : std_logic;

  signal st_media_ready, st_index, st_track0, st_wprot, st_change : std_logic;
  signal st_motor_on, st_head_settled, st_locked : std_logic;
  signal st_head_cyl : unsigned(7 downto 0);
  signal cur_cyl : integer;
begin

  clk   <= not clk   after 10 ns;
  rdclk <= not rdclk after 30 ns;

  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE => true,
      G_MOTOR_READY_CYC => 5_000,
      G_READY_WD_CYC    => 150_000_000,
      G_SEARCH_EDGES    => 3,
      G_PERIOD_MIN_CYC  => 7_500_000,
      G_PERIOD_MAX_CYC  => 12_500_000
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

  -- deliberately tiny FIFO, and nobody ever pops it
  i_fifo : entity work.physical_1581_rdfifo
    generic map (G_AW => 2)
    port map (
      wr_clk_i => clk, wr_rst_i => rst, wr_en_i => byte_wr, wr_data_i => byte_data, wr_full_o => fifo_full,
      rd_clk_i => rdclk, rd_rst_i => rst, rd_en_i => '0', rd_data_o => rd_data, rd_empty_o => rd_empty
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

  stim : process
    variable prev_done : std_logic;
    variable prev_ack  : std_logic;
  begin
    rst <= '1'; wait for 500 ns; rst <= '0'; wait for 500 ns;
    phys_active <= '1'; cia_motor_on <= '1';
    wait for 50 us;

    -- one step to clear the conservative power-up disk-change latch
    prev_ack := step_ack;
    step_req <= not step_req;
    wait until step_ack /= prev_ack for 1 sec;
    assert step_ack /= prev_ack report "TIMEOUT waiting for step ack" severity failure;

    wait until st_media_ready = '1' for 2 sec;
    assert st_media_ready = '1' report "media never ready" severity failure;

    -- read a sector into the 4-deep FIFO that nobody drains
    prev_done := rd_done;
    rd_req <= not rd_req;
    wait until rd_done /= prev_done for 3 sec;
    assert rd_done /= prev_done report "TIMEOUT waiting for rd_done" severity failure;

    assert rd_rnf = '1'
      report "FAIL: overflowed read completed without RNF (silent truncation!)" severity error;
    assert rd_crc_err = '1'
      report "FAIL: overflowed read completed without CRC error flag" severity error;
    assert rd_result = RES_DATA_CRC_ERROR
      report "FAIL: overflowed read result /= RES_DATA_CRC_ERROR" severity error;

    if rd_rnf = '1' and rd_crc_err = '1' and rd_result = RES_DATA_CRC_ERROR then
      report "tb_physical_1581_ovf: ALL TESTS PASSED (overflow reported, not silent)";
    end if;
    finish;
  end process;

end architecture sim;
