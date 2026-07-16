-------------------------------------------------------------------------------
-- Focused media-state/Read-Address compatibility regression for issue #90.
--
-- Proves the two hardware- and genuine-ROM-derived repairs together:
--   * cold/new media requires two index edges, but a previously confirmed and
--     unchanged medium becomes ready after the first edge on motor restart;
--   * disk change clears that history, restoring the two-edge requirement;
--   * physical Read Address ignores the F011 formatter's CRC-valid sector-11
--     ID and returns the following stock-compatible sector 1.
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

  stim : process
    variable prev_ack  : std_logic;
    variable prev_done : std_logic;
    variable prev_data : std_logic := '0';

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

    -- A real step with no raw change assertion clears the conservative latch.
    do_step;
    assert change_latched = '0' report "power-up change latch did not clear" severity error;

    -- Cold/new medium: first edge is insufficient, second edge asserts ready.
    pulse_index;
    assert media_ready = '0' report "cold medium became ready after only one index" severity error;
    pulse_index;
    assert media_ready = '1' report "cold medium not ready after two indexes" severity error;

    -- Same unchanged medium: motor restart needs only one fresh edge.
    cia_motor_on <= '0'; wait for 2 us;
    assert media_ready = '0' report "ready remained set with motor off" severity error;
    cia_motor_on <= '1'; wait for 2 us;
    pulse_index;
    assert media_ready = '1'
      report "confirmed unchanged medium did not resume after first index" severity error;

    -- If the motor remains commanded but index disappears, the controller
    -- treats the old rotation proof as stale.  Readiness drops and the next
    -- observed medium must qualify with two edges again.
    wait for 41 ms;
    assert media_ready = '0'
      report "index staleness did not clear ready" severity error;
    pulse_index;
    assert media_ready = '0'
      report "stale rotation history incorrectly allowed one-index resume" severity error;
    pulse_index;
    assert media_ready = '1'
      report "stale medium did not requalify after two indexes" severity error;

    -- A disk-change assertion destroys that history.  A step clears the latch,
    -- but the replacement medium must still earn a fresh two-edge proof.
    cia_motor_on <= '0';
    f_change <= '0'; wait for 2 us;
    assert change_latched = '1' report "disk change did not latch" severity error;
    f_change <= '1'; wait for 2 us;
    do_step;
    assert change_latched = '0' report "step did not clear disk-change latch" severity error;
    cia_motor_on <= '1'; wait for 2 us;
    pulse_index;
    assert media_ready = '0'
      report "changed medium incorrectly reused one-index history" severity error;
    pulse_index;
    assert media_ready = '1' report "changed medium not ready after two indexes" severity error;

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

    assert rd_result = RES_OK and rd_rnf = '0' and rd_crc_err = '0'
      report "Read Address did not complete cleanly" severity error;
    assert rd_r = x"01"
      report "Read Address exposed out-of-range sector " & integer'image(to_integer(rd_r))
      severity error;
    assert cap_count = 6 report "Read Address did not emit six bytes" severity error;
    assert cap(2) = x"01" report "Read Address payload contains sector 11" severity error;

    report "tb_physical_1581_media_contract: ALL TESTS PASSED";
    finish;
  end process;

  guard : process
  begin
    wait for 100 ms;
    report "global timeout" severity failure;
  end process;
end architecture;
