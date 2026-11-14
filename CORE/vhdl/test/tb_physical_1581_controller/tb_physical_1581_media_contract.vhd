-------------------------------------------------------------------------------
-- Focused media-state/Read-Address compatibility regression (issues #90, #257).
--
-- Proves the media-state contract of the controller and one Read Address rule:
--   * READY (media_ready) asserts with the first index edge of a motor-on
--     interval, for every medium: cold, restarted, changed, re-enabled. The
--     stock 1581 ROM examines READY 0.80 to 0.83 s after it switched the motor
--     on, and the mechanism can take more than 0.6 s to its first index pulse
--     (0.63 to 0.67 s on an R6, issue #257); a second edge 0.2 s later can
--     come after the exam. An edge that arrives while the motor is off does
--     not count;
--   * READY does not depend on the disk-change latch: on the mechanism they
--     are separate lines, and the ROM reads them separately;
--   * READY stays up without a gap while index edges keep coming, and it
--     falls with the motor request, when the edges stop for two maximum
--     periods, and when the drive is disabled;
--   * the disk-change latch is set by the raw line, by reset and by disable,
--     and only a step with the line released clears it;
--   * physical Read Address ignores the F011 formatter's CRC-valid sector-11
--     ID and returns the following stock-compatible sector 1.
--
-- The first failed check ends the run with a failure, so the last line
-- "ALL TESTS PASSED" is only reached when every check held.
-- run_tb_media_contract.sh runs the bench and the mutants of the controller
-- that it has to reject.
--
-- This test is intentionally small and drives INDEX/RDATA directly.  The long
-- closed-loop controller/mechanism test remains the end-to-end data-path proof.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;

entity tb_physical_1581_media_contract is
end entity;

architecture sim of tb_physical_1581_media_contract is
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal f_rdata : std_logic := '1';
  signal f_index : std_logic := '1';
  signal f_change : std_logic := '1';
  signal f_motora, f_selecta, f_side1, f_stepdir, f_step, f_density : std_logic;

  signal phys_active  : std_logic := '0';
  signal cia_motor_on : std_logic := '0';
  signal cia_side     : std_logic := '1';
  signal step_req     : std_logic := '0';
  signal step_outward : std_logic := '1';
  signal step_ack     : std_logic;
  signal rd_req       : std_logic := '0';
  signal rd_done      : std_logic;
  signal rd_result    : std_logic_vector(4 downto 0);
  signal rd_rnf, rd_crc_err : std_logic;
  signal rd_c, rd_h, rd_r, rd_n : unsigned(7 downto 0);
  signal byte_data : unsigned(7 downto 0);
  signal byte_wr   : std_logic;
  signal media_ready, change_latched, head_settled : std_logic;
  signal rd_phase : std_logic_vector(3 downto 0);

  type byte_arr_t is array (0 to 5) of unsigned(7 downto 0);
  signal cap : byte_arr_t := (others => (others => '0'));
  signal cap_count : integer range 0 to 6 := 0;

  -- per-clock monitors of READY, switched by the stimulus
  signal expect_ready : std_logic := '0';   -- '1': media_ready has to be '1' on every clock
  signal expect_idle  : std_logic := '0';   -- '1': media_ready has to be '0' on every clock
begin
  clk <= not clk after 10 ns;

  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE         => true,
      G_READY_WD_CYC    => 5_000_000,
      G_DIR_SETUP_CYC   => 2,
      G_STEP_LOW_CYC    => 2,
      G_STEP_REC_CYC    => 2,
      G_STEP_REV_CYC    => 2,
      G_SETTLE_CYC      => 2,
      G_SIDE_SETTLE_CYC => 2,
      G_SEARCH_WD_CYC   => 10_000_000,
      G_SEARCH_EDGES    => 3,
      G_PERIOD_MAX_CYC  => 1_000_000
    )
    port map (
      clk_i => clk, rst_i => rst,
      f_rdata_i => f_rdata, f_index_i => f_index, f_track0_i => '0',
      f_writeprotect_i => '1', f_diskchanged_i => f_change,
      f_motora_o => f_motora, f_selecta_o => f_selecta, f_side1_o => f_side1,
      f_stepdir_o => f_stepdir, f_step_o => f_step, f_density_o => f_density,
      phys_active_i => phys_active, cia_motor_on_i => cia_motor_on,
      cia_side_i => cia_side,
      step_req_tgl_i => step_req, step_outward_i => step_outward,
      step_ack_tgl_o => step_ack,
      rd_req_tgl_i => rd_req, rd_op_i => RDOP_READ_ADDRESS,
      rd_track_i => (others => '0'), rd_side_i => '1',
      rd_sector_i => (others => '0'), rd_seq_i => "01",
      rd_cancel_tgl_i => '0', rd_done_tgl_o => rd_done,
      rd_done_seq_o => open, rd_result_o => rd_result,
      rd_crc_err_o => rd_crc_err, rd_rnf_o => rd_rnf,
      rd_deleted_o => open, rd_c_o => rd_c, rd_h_o => rd_h,
      rd_r_o => rd_r, rd_n_o => rd_n,
      byte_data_o => byte_data, byte_wr_o => byte_wr, byte_ovf_i => '0',
      st_media_ready_o => media_ready, st_index_o => open,
      st_track0_o => open, st_wprot_o => open, st_change_o => change_latched,
      st_motor_on_o => open, st_head_settled_o => head_settled,
      st_head_cyl_o => open, st_locked_o => open,
      diag_rd_phase_o => rd_phase
    );

  capture_p : process (clk)
  begin
    if rising_edge(clk) then
      if byte_wr = '1' and cap_count < 6 then
        cap(cap_count) <= byte_data;
        cap_count <= cap_count + 1;
      end if;
    end if;
  end process;

  monitor_p : process (clk)
  begin
    if rising_edge(clk) then
      assert not (expect_ready = '1' and media_ready /= '1')
        report "ready dropped where it has to stay up" severity failure;
      assert not (expect_idle = '1' and media_ready /= '0')
        report "ready asserted where it has to stay down" severity failure;
    end if;
  end process;

  stim : process
    variable prev_ack  : std_logic;
    variable prev_done : std_logic;
    variable prev_data : std_logic := '0';

    -- a failed check ends the run
    procedure check (cond : boolean; msg : string) is
    begin
      assert cond report msg severity failure;
    end procedure;

    procedure pulse_index is
    begin
      -- physical_1581_inputs accepts INDEX after 200 us continuously low.
      f_index <= '0';
      wait for 300 us;
      f_index <= '1';
      wait for 100 us;
    end procedure;

    procedure do_step is
    begin
      prev_ack := step_ack;
      wait until rising_edge(clk);
      step_req <= not step_req;
      wait until step_ack /= prev_ack for 1 ms;
      assert step_ack /= prev_ack report "step acknowledgement timeout" severity failure;
      wait for 1 us;
    end procedure;

    procedure emit_id(sector : natural; variable prev : inout std_logic) is
      variable crc : unsigned(15 downto 0) := x"FFFF";
      constant c : unsigned(7 downto 0) := x"00";
      constant h : unsigned(7 downto 0) := x"00";
      constant n : unsigned(7 downto 0) := x"02";
      variable r : unsigned(7 downto 0);
    begin
      r := to_unsigned(sector, 8);
      mfm_bytes(f_rdata, x"00", 12, prev);
      mfm_a1(f_rdata, prev); crc := crc16_update(crc, x"A1");
      mfm_a1(f_rdata, prev); crc := crc16_update(crc, x"A1");
      mfm_a1(f_rdata, prev); crc := crc16_update(crc, x"A1");
      mfm_byte(f_rdata, x"FE", prev); crc := crc16_update(crc, x"FE");
      mfm_byte(f_rdata, c, prev); crc := crc16_update(crc, c);
      mfm_byte(f_rdata, h, prev); crc := crc16_update(crc, h);
      mfm_byte(f_rdata, r, prev); crc := crc16_update(crc, r);
      mfm_byte(f_rdata, n, prev); crc := crc16_update(crc, n);
      mfm_byte(f_rdata, crc(15 downto 8), prev);
      mfm_byte(f_rdata, crc(7 downto 0), prev);
    end procedure;
  begin
    rst <= '1'; wait for 500 ns;
    rst <= '0'; phys_active <= '1'; cia_motor_on <= '1';
    wait for 2 us;

    -- Power-up: the latch is armed, nothing is ready, and the motor request
    -- alone does not make the drive ready.
    check(change_latched = '1', "power-up change latch is not set");
    expect_idle <= '1';
    wait for 5 ms;
    expect_idle <= '0';

    -- Cold medium, latch still set: the first index edge asserts ready, and
    -- an index edge does not touch the latch.
    pulse_index;
    check(media_ready = '1', "cold medium not ready after the first index");
    check(change_latched = '1', "an index edge cleared the change latch");

    -- A real step with no raw change assertion clears the conservative latch
    -- and leaves ready alone.
    expect_ready <= '1';
    do_step;
    check(change_latched = '0', "power-up change latch did not clear");

    -- Ready stays up, without a gap, while index edges keep coming: every
    -- edge restarts the staleness interval (2 x 20 ms in this bench).
    wait for 37 ms;
    pulse_index;
    wait for 37600 us;
    pulse_index;

    -- If the motor remains commanded but index disappears, readiness drops
    -- (disk removed or stalled) two maximum periods after the last edge, not
    -- earlier and not later; the next edge brings it back.
    wait for 39 ms;
    expect_ready <= '0';
    wait for 1200 us;
    check(media_ready = '0', "index staleness did not clear ready");
    pulse_index;
    check(media_ready = '1', "medium not ready again after the pulses returned");

    -- Motor restart: ready falls with the motor request. An index edge that
    -- arrives while the motor is off does not count, the restart alone does
    -- not make the drive ready, and the first fresh edge does, even if
    -- spindle acceleration delays that edge beyond the staleness interval.
    cia_motor_on <= '0'; wait for 2 us;
    check(media_ready = '0', "ready remained set with motor off");
    expect_idle <= '1';
    pulse_index;
    cia_motor_on <= '1';
    wait for 41 ms;
    expect_idle <= '0';
    pulse_index;
    check(media_ready = '1', "restarted medium not ready after its delayed first index");

    -- Disk change with the motor off (the case of issue #257: a disk is
    -- inserted while the drive is idle). The raw line sets the latch and
    -- holds it; the replacement medium is ready with its first index edge
    -- while the latch is still set, and only the step with the line released
    -- clears the latch.
    cia_motor_on <= '0';
    f_change <= '0'; wait for 2 us;
    check(change_latched = '1', "disk change did not latch");
    check(media_ready = '0', "ready remained set with motor off (change)");
    expect_idle <= '1';
    cia_motor_on <= '1'; wait for 1 ms;
    expect_idle <= '0';
    pulse_index;
    check(media_ready = '1', "changed medium not ready after its first index");
    expect_ready <= '1';
    do_step;
    check(change_latched = '1', "a step cleared the latch although the raw line is still asserted");
    f_change <= '1'; wait for 2 us;
    check(change_latched = '1', "the latch fell without a step");
    do_step;
    check(change_latched = '0', "step did not clear disk-change latch");

    -- A raw change while the motor runs does not touch ready by itself (the
    -- loss of index does), but it sets the latch again.
    f_change <= '0'; wait for 2 us;
    check(change_latched = '1', "disk change with running motor did not latch");
    f_change <= '1'; wait for 2 us;
    do_step;
    check(change_latched = '0', "step did not clear the second latch");
    wait for 2 us;
    expect_ready <= '0';

    -- Disabling the physical path re-arms the latch (an image/internal source
    -- switch presents as a disk change) and drops ready; after the re-enable
    -- the first index edge makes the drive ready again.
    phys_active <= '0'; wait for 2 us;
    check(media_ready = '0', "ready remained set while disabled");
    check(change_latched = '1', "disable did not re-arm disk change");
    expect_idle <= '1';
    phys_active <= '1'; wait for 1 ms;
    expect_idle <= '0';
    pulse_index;
    check(media_ready = '1', "re-enabled controller not ready after its first index");
    do_step;
    check(change_latched = '0', "step did not clear re-enable change latch");

    -- Issue Read Address, then put a valid F011 sector-11 ID followed by a
    -- normal sector-1 ID on the wire.  Production must ignore 11 and return 1.
    prev_done := rd_done;
    wait until rising_edge(clk);
    rd_req <= not rd_req;
    wait until rd_phase = "0010" for 1 ms;          -- RD_SEARCH
    assert rd_phase = "0010" report "Read Address never entered search" severity failure;
    emit_id(11, prev_data);
    mfm_bytes(f_rdata, x"4E", 8, prev_data);
    emit_id(1, prev_data);
    wait until rd_done /= prev_done for 10 ms;
    assert rd_done /= prev_done report "Read Address completion timeout" severity failure;
    wait for 1 us;

    check(rd_result = RES_OK and rd_rnf = '0' and rd_crc_err = '0',
          "Read Address did not complete cleanly");
    check(rd_r = x"01",
          "Read Address exposed out-of-range sector " & integer'image(to_integer(rd_r)));
    check(cap_count = 6, "Read Address did not emit six bytes");
    check(cap(2) = x"01", "Read Address payload contains sector 11");

    report "tb_physical_1581_media_contract: ALL TESTS PASSED";
    finish;
  end process;

  guard : process
  begin
    wait for 600 ms;
    report "global timeout" severity failure;
  end process;
end architecture;
