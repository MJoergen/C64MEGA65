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
--     not count; an edge that arrives while the head steps does;
--   * READY does not depend on the disk-change latch: on the mechanism they
--     are separate lines, and the ROM reads them separately;
--   * READY stays up without a gap while index edges keep coming, and it
--     falls with the motor request, when the drive is disabled, and when no
--     edge arrived for two maximum periods of settled time: the time in which
--     the step engine works or the head has not settled does not count, and
--     the interval starts anew when the head has settled. A mechanism that
--     withholds its index pulses while it steps (and for a hold time after
--     the last step) therefore keeps READY up;
--   * the disk-change latch is set by the raw line, by reset and by disable,
--     and only a step with the line released clears it;
--   * while READY is still up after a disk was taken out during a train,
--     nothing reaches the drive: a Read Sector ends at once with "disk
--     changed" and without a byte, a Write Sector opens no gate and ends when
--     READY falls;
--   * physical Read Address ignores the F011 formatter's CRC-valid sector-11
--     ID and returns the following stock-compatible sector 1.
--
-- Two controllers run side by side, each on a clock of its own that stops
-- when its part is done:
--   * part 1, dut: the small cases with INDEX and RDATA driven directly and
--     short times. Its step recovery (0.5 ms) is longer than its settle time
--     (2 clocks), so at the end of every step only the step engine holds the
--     interval.
--   * part 2, dut2: every time of the controller at 1/K2 of production (the
--     settle time longer than the step recovery, as in production), with the
--     mechanism model mech_model_1581 and its option G_IDX_HIDE. A motor
--     restart and a disable with a cleared change latch come first, then the
--     disk taken out during a train (with the read and the write above) and
--     at rest, steps without a disk, the first index edge of a motor-on
--     interval during a train, and at the end the table of step trains
--     (C_TRAINS). The comments and the table give
--     times at production scale; p2() converts them. The index pulse of the
--     model is 400 us wide at every scale, because the controller accepts an
--     index pulse only after 200 us.
--   * ready_ref: the READY rule in clocked form, checked in every clock of
--     both controllers (see the entity below). It takes the controller's own
--     enable, motor request, index edge, step phase and head_settled as its
--     inputs, so it checks the logic of the rule in every clock, but a defect
--     in what feeds those inputs (the settle timer, the step engine, the
--     reset branch) would be repeated by it. The checks below do not take
--     them from the controller:
--   * anchored to the pins and the generics, in both parts: head_settled is
--     low at every leading edge of a STEP pulse and rises exactly
--     G_SETTLE_CYC clocks after the trailing edge of the last one (a rise in
--     reset or disable excepted); READY rises only in the clock after a
--     clock in which the controller took an index edge; and wherever READY
--     has to fall by staleness, it falls in the very clock that the rule
--     gives from the last index edge, from the trailing edge of the last
--     STEP pulse plus the step recovery or the settle time, or from a
--     re-enable without a step (part 1: after an edge, after a step, after
--     a re-enable with a side change in between; part 2: a disk taken out
--     during a train and at rest). The windows of expect_ready and
--     expect_idle check the rest of the cases at the level of the stimulus.
--
-- The first failed check ends the run with a failure, so the last line
-- "ALL TESTS PASSED" is only reached when every check held.
-- run_tb_media_contract.sh runs the bench and the mutants of the controller
-- that it has to reject.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- ready_ref: the READY rule of physical_1581_controller in clocked form. Its
-- inputs are what the controller sees in the same clock: reset, its enable,
-- the synchronized motor request (f_motora_o low), the filtered index edge,
-- the phase of the step engine and head_settled. It compares media_ready in
-- every clock with the rule:
--   * READY rises in the clock after a clock with the motor request on and
--     an index edge since the motor request rose (an edge is counted from the
--     clock after it, and the edge itself may come during a step);
--   * READY falls in the clock after: reset, disable, the motor request off,
--     or the clock in which the settled time without an index edge has
--     reached G_LIM clocks; it falls in no other case;
--   * the settled time counts the clocks with the motor request on, the step
--     engine idle and the head settled; an index edge, a step or the settle
--     time after it, and the motor request off start it anew from zero.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity ready_ref is
  generic (
    G_LIM  : natural;
    G_NAME : string
  );
  port (
    clk_i        : in std_logic;
    rst_i        : in std_logic;
    en_i         : in std_logic;
    mot_i        : in std_logic;
    idx_i        : in std_logic;
    step_phase_i : in std_logic_vector(1 downto 0);
    settled_i    : in std_logic;
    ready_i      : in std_logic
  );
end entity;

architecture sim of ready_ref is
  signal exp_ready : std_logic := '0';
begin
  process (clk_i)
    variable seen : std_logic := '0';   -- an index edge since the motor request rose
    variable rdy  : std_logic := '0';
    variable q    : natural   := 0;     -- settled clocks without an index edge
  begin
    if rising_edge(clk_i) then
      assert ready_i = exp_ready
        report G_NAME & ": media_ready is " & std_logic'image(ready_i) &
               " where the READY rule gives " & std_logic'image(exp_ready)
        severity failure;
      if rst_i = '1' or en_i = '0' then
        seen := '0'; rdy := '0'; q := 0;
      else
        if mot_i = '1' and seen = '1' then
          rdy := '1';
        end if;
        if mot_i = '0' then
          seen := '0'; rdy := '0'; q := 0;
        elsif idx_i = '1' then
          seen := '1'; q := 0;
        elsif step_phase_i /= "00" or settled_i = '0' then
          q := 0;
        elsif q < G_LIM then
          q := q + 1;
        else
          seen := '0'; rdy := '0'; q := 0;
        end if;
      end if;
      exp_ready <= rdy;
    end if;
  end process;
end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.physical_1581_pkg.all;
use work.mfm_flux_gen_pkg.all;

entity tb_physical_1581_media_contract is
end entity;

architecture sim of tb_physical_1581_media_contract is
  -------------------------------------------------------------------------
  -- part 1
  -------------------------------------------------------------------------
  constant C1_PERIOD_MAX : natural := 1_000_000;   -- 20 ms: READY falls 40 ms after the last edge
  constant C1_STEP_REC   : natural := 25_000;      -- 0.5 ms, longer than the settle time
  constant C1_SETTLE     : natural := 2;
  constant C1_LIM        : natural := 2 * C1_PERIOD_MAX;

  signal done1 : boolean := false;
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
  signal step_phase : std_logic_vector(1 downto 0);
  signal idx_edge   : std_logic;
  signal out_bits   : std_logic_vector(15 downto 0);
  signal mot1       : std_logic;
  signal last_step_end1 : time := 0 ns;   -- trailing edge of the last STEP pulse of dut
  signal last_idx_edge1 : time := 0 ns;   -- the clock in which dut saw its last index edge

  type byte_arr_t is array (0 to 5) of unsigned(7 downto 0);
  signal cap : byte_arr_t := (others => (others => '0'));
  signal cap_count : integer range 0 to 6 := 0;

  -- per-clock monitors of READY, switched by the stimulus
  signal expect_ready : std_logic := '0';   -- '1': media_ready has to be '1' on every clock
  signal expect_idle  : std_logic := '0';   -- '1': media_ready has to be '0' on every clock

  -------------------------------------------------------------------------
  -- part 2: the times of the controller at 1/K2 of production
  -------------------------------------------------------------------------
  constant K2 : positive := 50;
  constant C2_PERIOD_MAX : natural := 12_500_000 / K2;   -- READY falls 500 ms after the last edge
  constant C2_SETTLE     : natural := 900_000 / K2;      -- 18 ms
  constant C2_LIM        : natural := 2 * C2_PERIOD_MAX;
  constant C_CLK         : time := 20 ns;
  constant C_IDX_FILTER  : time := 200 us;               -- physical_1581_inputs: INDEX low this long
  constant C_PACE_MIN    : time := 3030 us;              -- the pace of the step engine (production)

  -- a time at production scale in part 2
  function p2(t : time) return time is
  begin
    return t / K2;
  end function;

  signal done2 : boolean := false;
  signal clk2  : std_logic := '0';

  signal f_rdata2, f_index2, f_track02, f_wprot2, f_change2 : std_logic;
  signal f_motora2, f_selecta2, f_side12, f_stepdir2, f_step2, f_density2 : std_logic;
  signal f_wgate2, f_wdata2 : std_logic;
  signal motor2        : std_logic := '0';
  signal active2       : std_logic := '1';
  signal step_req2     : std_logic := '0';
  signal step_out2     : std_logic := '0';
  signal step_ack2     : std_logic;
  signal media_ready2, head_settled2 : std_logic;
  signal step_phase2   : std_logic_vector(1 downto 0);
  signal idx_edge2     : std_logic;
  signal out_bits2     : std_logic_vector(15 downto 0);
  signal mot2          : std_logic;
  signal cfg_present2  : std_logic := '1';
  signal cfg_change2   : std_logic := '0';
  signal cfg_hide2     : time := 0 ns;
  signal last_step_end : time := 0 ns;   -- trailing edge of the last STEP pulse of dut2
  signal last_idx_fall : time := 0 ns;   -- leading (falling) edge of the last INDEX pulse at the pin of dut2
  signal last_idx_edge2 : time := 0 ns;  -- the clock in which dut2 saw its last index edge
  -- a read or a write of dut2 after a disk was taken out during a train
  signal rd_req2       : std_logic := '0';
  signal rd_op2        : std_logic_vector(2 downto 0) := RDOP_READ_SECTOR;
  signal rd_done2      : std_logic;
  signal rd_result2    : std_logic_vector(4 downto 0);
  signal rd_rnf2       : std_logic;
  signal byte_wr2      : std_logic;
  signal bytes2        : natural := 0;

  signal expect_ready2 : std_logic := '0';
  signal expect_idle2  : std_logic := '0';

  -- the step trains of part 2: n1 steps, then (if n2 > 0) a pause and n2
  -- steps in the other direction; the pace and the hold time of the
  -- mechanism at production scale
  type train_t is record
    n1, n2 : natural;
    pace   : time;
    hold   : time;
  end record;
  type train_arr_t is array (natural range <>) of train_t;
  constant C_TRAINS : train_arr_t := (
    (39, 0, C_PACE_MIN, 0 ms), (39, 0,  6 ms, 0 ms), (39, 0, 12 ms, 0 ms),
    (80, 0, C_PACE_MIN, 0 ms), (80, 0,  6 ms, 0 ms), (80, 0, 12 ms, 0 ms),
    (39, 0, C_PACE_MIN, 18 ms), (39, 0,  6 ms, 18 ms), (39, 0, 12 ms, 18 ms),
    (80, 0, C_PACE_MIN, 18 ms), (80, 0,  6 ms, 18 ms), (80, 0, 12 ms, 18 ms),
    (39, 0, C_PACE_MIN, 40 ms), (39, 0,  6 ms, 40 ms), (39, 0, 12 ms, 40 ms),
    (80, 0, C_PACE_MIN, 40 ms), (80, 0,  6 ms, 40 ms), (80, 0, 12 ms, 40 ms),
    -- the recalibration of the DOS: Restore, 70 ms, Seek
    (39, 39, C_PACE_MIN, 0 ms), (39, 39,  6 ms, 0 ms), (39, 39, 12 ms, 0 ms),
    (39, 39, C_PACE_MIN, 18 ms), (39, 39,  6 ms, 18 ms), (39, 39, 12 ms, 18 ms),
    (39, 39, C_PACE_MIN, 40 ms), (39, 39,  6 ms, 40 ms), (39, 39, 12 ms, 40 ms)
  );
  constant C_GAP : time := 70 ms;
begin
  clk  <= not clk  after 10 ns when not done1 else clk;
  clk2 <= not clk2 after 10 ns when not done2 else clk2;

  -------------------------------------------------------------------------
  -- part 1: the controller with INDEX and RDATA driven directly
  -------------------------------------------------------------------------
  dut : entity work.physical_1581_controller
    generic map (
      G_CAPABLE         => true,
      G_READY_WD_CYC    => 5_000_000,
      G_DIR_SETUP_CYC   => 2,
      G_STEP_LOW_CYC    => 2,
      G_STEP_REC_CYC    => C1_STEP_REC,
      G_STEP_REV_CYC    => C1_STEP_REC,
      G_SETTLE_CYC      => C1_SETTLE,
      G_SIDE_SETTLE_CYC => 2,
      G_SEARCH_WD_CYC   => 10_000_000,
      G_SEARCH_EDGES    => 3,
      G_PERIOD_MAX_CYC  => C1_PERIOD_MAX
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
      diag_index_edge_o => idx_edge,
      diag_rd_phase_o => rd_phase,
      diag_step_phase_o => step_phase,
      diag_out_bits_o => out_bits
    );

  mot1 <= not f_motora;
  ref1 : entity work.ready_ref
    generic map (G_LIM => C1_LIM, G_NAME => "part 1")
    port map (
      clk_i => clk, rst_i => rst, en_i => out_bits(6), mot_i => mot1,
      idx_i => idx_edge, step_phase_i => step_phase, settled_i => head_settled,
      ready_i => media_ready
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
        report "part 1: ready dropped where it has to stay up" severity failure;
      assert not (expect_idle = '1' and media_ready /= '0')
        report "part 1: ready asserted where it has to stay down" severity failure;
    end if;
  end process;

  -- Checks anchored to the pins and the generics, independent of the rule's
  -- inputs that ready_ref takes from the controller: head_settled is low at
  -- every leading edge of a STEP pulse and rises exactly G_SETTLE_CYC clocks
  -- after the trailing edge of the last one (a rise in reset or disable
  -- excepted), and READY rises only in the clock after a clock with an index
  -- edge.
  pins1_p : process (f_step, head_settled, media_ready)
  begin
    if rising_edge(f_step) then
      last_step_end1 <= now;
    end if;
    if falling_edge(f_step) then
      assert head_settled = '0'
        report "part 1: head_settled is up at the leading edge of a STEP pulse" severity failure;
    end if;
    if rising_edge(head_settled) and now > 0 ns and rst = '0' and out_bits(6) = '1' then
      assert now - last_step_end1 = C1_SETTLE * C_CLK
        report "part 1: head_settled rose " & integer'image((now - last_step_end1) / 1 ns) & " ns" &
               " after the trailing edge of the last STEP pulse" severity failure;
    end if;
    if rising_edge(media_ready) then
      assert now = last_idx_edge1 + C_CLK
        report "part 1: READY rose " & integer'image((now - last_idx_edge1) / 1 ns) & " ns" &
               " after the last index edge, not one clock" severity failure;
    end if;
  end process;

  idx1_p : process (clk)
  begin
    if rising_edge(clk) and idx_edge = '1' then
      last_idx_edge1 <= now;
    end if;
  end process;

  stim : process
    variable prev_ack  : std_logic;
    variable prev_done : std_logic;
    variable prev_data : std_logic := '0';
    variable t_ack     : time;
    variable t_exp     : time;

    -- a failed check ends the run
    procedure check (cond : boolean; msg : string) is
    begin
      assert cond report "part 1: " & msg severity failure;
    end procedure;

    procedure pulse_index is
    begin
      -- physical_1581_inputs accepts INDEX after 200 us continuously low.
      f_index <= '0';
      wait for 300 us;
      f_index <= '1';
      wait for 100 us;
    end procedure;

    -- READY is up and has to fall in the clock that ends at t_fall, exactly
    -- (t_fall is a rising edge of clk)
    procedure fall_at (t_fall : time; msg : string) is
    begin
      expect_ready <= '1';
      wait for t_fall - now - 5 ns;
      check(media_ready = '1', msg & ": READY fell before " & integer'image((t_fall) / 1 ns) & " ns");
      expect_ready <= '0';
      wait until media_ready = '0' for 10 ns;
      check(media_ready = '0' and now = t_fall,
            msg & ": READY did not fall at " & integer'image((t_fall) / 1 ns) & " ns");
    end procedure;

    procedure do_step is
    begin
      prev_ack := step_ack;
      wait until rising_edge(clk);
      step_req <= not step_req;
      wait until step_ack /= prev_ack for 1 ms;
      assert step_ack /= prev_ack report "part 1: step acknowledgement timeout" severity failure;
      t_ack := now;
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

    -- The staleness interval counts settled time only: a step 10 ms after
    -- the last edge starts it anew when the step engine has finished (here
    -- the recovery of 0.5 ms outlasts the settle time). Taken from the pin
    -- and the generics: the engine acknowledges G_STEP_REC_CYC + 1 clocks
    -- after the trailing edge of the STEP pulse, the count runs from the
    -- clock after that, and ready falls when it has reached the limit.
    pulse_index;
    wait for 10 ms;
    do_step;
    fall_at(last_step_end1 + (C1_STEP_REC + 2 + C1_LIM) * C_CLK, "staleness after a step");
    pulse_index;
    check(media_ready = '1', "medium not ready again after the staleness that followed a step");

    -- An index edge counts while the step engine works: the first edge of a
    -- motor-on interval that the filter accepts during a step makes the drive
    -- ready at once, not when the head has settled.
    cia_motor_on <= '0'; wait for 2 us;
    cia_motor_on <= '1'; wait for 2 us;
    check(media_ready = '0', "ready survived a motor restart");
    f_index <= '0';                          -- the filter accepts it 200 us later
    wait for 50 us;
    prev_ack := step_ack;
    wait until rising_edge(clk);
    step_req <= not step_req;                -- the step runs from about 50 us to 550 us
    wait for 200 us;
    check(step_ack = prev_ack, "the step ended before the index edge");
    check(media_ready = '1', "an index edge during a step did not make the drive ready");
    wait for 50 us;
    f_index <= '1';
    wait until step_ack /= prev_ack for 1 ms;
    check(step_ack /= prev_ack, "step acknowledgement timeout (index during a step)");
    wait for 1 us;
    check(media_ready = '1', "ready fell at the end of the step");
    expect_ready <= '1';

    -- Ready stays up, without a gap, while index edges keep coming: every
    -- edge restarts the staleness interval (2 x 20 ms in this bench).
    wait for 37 ms;
    pulse_index;
    wait for 37600 us;
    pulse_index;

    -- If the motor remains commanded but index disappears, readiness drops
    -- (disk removed or stalled) two maximum periods after the last edge, to
    -- the clock; the next edge brings it back.
    fall_at(last_idx_edge1 + (C1_LIM + 1) * C_CLK, "index staleness");
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
    -- No step since the re-enable: the head counts as settled, and ready
    -- falls two maximum periods after the edge, to the clock. A side change
    -- in between does not hold the interval.
    wait for 5 ms;
    cia_side <= '0';
    wait for 1 ms;
    cia_side <= '1';
    fall_at(last_idx_edge1 + (C1_LIM + 1) * C_CLK, "staleness after the re-enable, no step");
    pulse_index;
    check(media_ready = '1', "not ready again after the staleness that followed the re-enable");
    do_step;
    check(change_latched = '0', "step did not clear re-enable change latch");

    -- Issue Read Address, then put a valid F011 sector-11 ID followed by a
    -- normal sector-1 ID on the wire.  Production must ignore 11 and return 1.
    prev_done := rd_done;
    wait until rising_edge(clk);
    rd_req <= not rd_req;
    wait until rd_phase = "0010" for 1 ms;          -- RD_SEARCH
    assert rd_phase = "0010" report "part 1: Read Address never entered search" severity failure;
    emit_id(11, prev_data);
    mfm_bytes(f_rdata, x"4E", 8, prev_data);
    emit_id(1, prev_data);
    wait until rd_done /= prev_done for 10 ms;
    assert rd_done /= prev_done report "part 1: Read Address completion timeout" severity failure;
    wait for 1 us;

    check(rd_result = RES_OK and rd_rnf = '0' and rd_crc_err = '0',
          "Read Address did not complete cleanly");
    check(rd_r = x"01",
          "Read Address exposed out-of-range sector " & integer'image(to_integer(rd_r)));
    check(cap_count = 6, "Read Address did not emit six bytes");
    check(cap(2) = x"01", "Read Address payload contains sector 11");

    report "part 1 done";
    done1 <= true;
    wait;
  end process;

  -------------------------------------------------------------------------
  -- part 2: the controller at 1/K2 of production with the mechanism model
  -------------------------------------------------------------------------
  dut2 : entity work.physical_1581_controller
    generic map (
      G_CAPABLE         => true,
      G_DIR_SETUP_CYC   => 1_200 / K2,
      G_STEP_LOW_CYC    => 200 / K2,
      G_STEP_REC_CYC    => 150_000 / K2,
      G_STEP_REV_CYC    => 200_000 / K2,
      G_SETTLE_CYC      => C2_SETTLE,
      G_SIDE_SETTLE_CYC => 5_000 / K2,
      G_PERIOD_MAX_CYC  => C2_PERIOD_MAX
    )
    port map (
      clk_i => clk2, rst_i => rst,
      f_rdata_i => f_rdata2, f_index_i => f_index2, f_track0_i => f_track02,
      f_writeprotect_i => f_wprot2, f_diskchanged_i => f_change2,
      f_motora_o => f_motora2, f_selecta_o => f_selecta2, f_side1_o => f_side12,
      f_stepdir_o => f_stepdir2, f_step_o => f_step2, f_density_o => f_density2,
      f_wgate_o => f_wgate2, f_wdata_o => f_wdata2,
      phys_active_i => active2, cia_motor_on_i => motor2,
      cia_side_i => '1',
      step_req_tgl_i => step_req2, step_outward_i => step_out2,
      step_ack_tgl_o => step_ack2,
      rd_req_tgl_i => rd_req2, rd_op_i => rd_op2,
      rd_track_i => to_unsigned(10, 8), rd_side_i => '1',
      rd_sector_i => to_unsigned(1, 8), rd_seq_i => "01",
      rd_cancel_tgl_i => '0', rd_done_tgl_o => rd_done2,
      rd_done_seq_o => open, rd_result_o => rd_result2,
      rd_crc_err_o => open, rd_rnf_o => rd_rnf2,
      rd_deleted_o => open, rd_c_o => open, rd_h_o => open,
      rd_r_o => open, rd_n_o => open,
      byte_data_o => open, byte_wr_o => byte_wr2, byte_ovf_i => '0',
      st_media_ready_o => media_ready2, st_head_settled_o => head_settled2,
      diag_index_edge_o => idx_edge2,
      diag_step_phase_o => step_phase2,
      diag_out_bits_o => out_bits2
    );

  mech2 : entity work.mech_model_1581
    generic map (
      G_INDEX_PERIOD => 200 ms / K2,
      G_INDEX_LOW    => 400 us,
      G_IDX_HIDE     => true
    )
    port map (
      f_motora_i => f_motora2, f_selecta_i => f_selecta2, f_side1_i => f_side12,
      f_stepdir_i => f_stepdir2, f_step_i => f_step2, f_density_i => f_density2,
      cfg_present_i => cfg_present2, cfg_wprot_i => '0', cfg_change_i => cfg_change2,
      cfg_idx_hide_i => cfg_hide2,
      f_index_o => f_index2, f_track0_o => f_track02, f_writeprotect_o => f_wprot2,
      f_diskchanged_o => f_change2, f_rdata_o => f_rdata2,
      f_wgate_i => f_wgate2, f_wdata_i => f_wdata2
    );

  mot2 <= not f_motora2;
  ref2 : entity work.ready_ref
    generic map (G_LIM => C2_LIM, G_NAME => "part 2")
    port map (
      clk_i => clk2, rst_i => rst, en_i => out_bits2(6), mot_i => mot2,
      idx_i => idx_edge2, step_phase_i => step_phase2, settled_i => head_settled2,
      ready_i => media_ready2
    );

  monitor2_p : process (clk2)
  begin
    if rising_edge(clk2) then
      assert not (expect_ready2 = '1' and media_ready2 /= '1')
        report "part 2: ready dropped where it has to stay up" severity failure;
      assert not (expect_idle2 = '1' and media_ready2 /= '0')
        report "part 2: ready asserted where it has to stay down" severity failure;
    end if;
  end process;

  -- the checks of pins1_p for dut2, and the write gate: it never opens in
  -- part 2 (the read-only model fails the run as well if it did)
  pins2_p : process (f_step2, f_index2, head_settled2, media_ready2, f_wgate2)
  begin
    if rising_edge(f_step2) then
      last_step_end <= now;
    end if;
    if falling_edge(f_step2) then
      assert head_settled2 = '0'
        report "part 2: head_settled is up at the leading edge of a STEP pulse" severity failure;
    end if;
    if falling_edge(f_index2) then
      last_idx_fall <= now;
    end if;
    if rising_edge(head_settled2) and now > 0 ns and rst = '0' and out_bits2(6) = '1' then
      assert now - last_step_end = C2_SETTLE * C_CLK
        report "part 2: head_settled rose " & integer'image((now - last_step_end) / 1 ns) & " ns" &
               " after the trailing edge of the last STEP pulse" severity failure;
    end if;
    if rising_edge(media_ready2) then
      assert now = last_idx_edge2 + C_CLK
        report "part 2: READY rose " & integer'image((now - last_idx_edge2) / 1 ns) & " ns" &
               " after the last index edge, not one clock" severity failure;
    end if;
    assert f_wgate2 /= '0'
      report "part 2: the write gate opened" severity failure;
  end process;

  idx2_p : process (clk2)
  begin
    if rising_edge(clk2) then
      if idx_edge2 = '1' then
        last_idx_edge2 <= now;
      end if;
      if byte_wr2 = '1' then
        bytes2 <= bytes2 + 1;
      end if;
    end if;
  end process;

  stim2 : process
    variable dir   : std_logic := '0';   -- the next train goes inward
    variable t_exp : time;
    variable prev_done : std_logic;
    variable phase : time := 0 ms;

    procedure check (cond : boolean; msg : string) is
    begin
      assert cond report "part 2: " & msg severity failure;
    end procedure;

    -- one step; the next request comes pace after this one (part 2 time)
    procedure step2 (outward : std_logic; pace : time) is
      variable t0   : time;
      variable prev : std_logic;
    begin
      t0 := now;
      prev := step_ack2;
      step_out2 <= outward;
      wait until rising_edge(clk2);
      step_req2 <= not step_req2;
      wait until step_ack2 /= prev for p2(20 ms);
      check(step_ack2 /= prev, "step acknowledgement timeout");
      if now < t0 + pace then
        wait for t0 + pace - now;
      end if;
    end procedure;

    -- n steps at the pace, on a mechanism that withholds its index pulses
    -- until pace + hold after every step pulse (production times)
    procedure train2 (n : natural; outward : std_logic; pace, hold : time) is
    begin
      cfg_hide2 <= p2(pace + hold);
      for i in 1 to n loop
        step2(outward, p2(pace));
      end loop;
    end procedure;

    -- READY is up and has to fall in the clock that ends at t_fall, exactly
    procedure fall_at2 (t_fall : time; msg : string) is
    begin
      expect_ready2 <= '1';
      wait for t_fall - now - 5 ns;
      check(media_ready2 = '1', msg & ": READY fell before " & integer'image((t_fall) / 1 ns) & " ns");
      expect_ready2 <= '0';
      wait until media_ready2 = '0' for 10 ns;
      check(media_ready2 = '0' and now = t_fall,
            msg & ": READY did not fall at " & integer'image((t_fall) / 1 ns) & " ns");
    end procedure;

    -- wait for the next index edge the controller accepts
    procedure wait_idx2 (timeout : time; msg : string) is
    begin
      wait until rising_edge(clk2) and idx_edge2 = '1' for timeout;
      check(idx_edge2 = '1', "no index edge: " & msg);
      wait for 1 us;
    end procedure;
  begin
    wait until rst = '0';
    motor2 <= '1';
    wait_idx2(p2(450 ms), "first index edge after motor-on");
    check(media_ready2 = '1', "not ready after the first index edge");
    expect_ready2 <= '1';

    -- The motor request and the enable, with the change latch cleared by a
    -- step: READY falls with either, and after a restart or a re-enable it
    -- needs a fresh index edge.
    step2('0', p2(6 ms));
    wait_idx2(p2(450 ms), "after the first step");
    expect_ready2 <= '0';
    motor2 <= '0';
    wait for 1 us;
    check(media_ready2 = '0', "READY stayed up with the motor off");
    wait for p2(100 ms);
    motor2 <= '1';
    wait for 100 us;
    check(media_ready2 = '0', "READY rose with the motor restart alone");
    wait_idx2(p2(450 ms), "after the motor restart");
    check(media_ready2 = '1', "not ready after the first index edge of the restart");
    active2 <= '0';
    wait for 1 us;
    check(media_ready2 = '0', "READY stayed up while disabled");
    active2 <= '1';
    wait for 100 us;
    check(media_ready2 = '0', "READY rose with the re-enable alone");
    wait_idx2(p2(450 ms), "after the re-enable");
    check(media_ready2 = '1', "not ready after the first index edge of the re-enable");
    step2('1', p2(6 ms));
    expect_ready2 <= '1';

    -- A disk taken out during a train (100 ms after the last index edge, 10
    -- of 39 steps at 6 ms done): READY stays up until 500 ms after the head
    -- has settled (18 ms after the trailing edge of the last step pulse) and
    -- falls then, not earlier and not later.
    wait_idx2(p2(450 ms), "before the pull during a train");
    wait for p2(100 ms);
    cfg_hide2 <= p2(6 ms + 18 ms);
    for i in 1 to 39 loop
      if i = 11 then
        cfg_present2 <= '0'; cfg_change2 <= '1';
      end if;
      step2(dir, p2(6 ms));
    end loop;
    dir := not dir;
    -- the count starts in the clock after head_settled rose, G_SETTLE_CYC
    -- clocks after the trailing edge (the step engine is idle long before)
    t_exp := last_step_end + (C2_SETTLE + 1 + C2_LIM) * C_CLK;
    -- While READY is still up, nothing reaches the drive: a Read Sector ends
    -- at once with "disk changed" and without a byte (the read engine aborts
    -- on the level of the change line), and a Write Sector opens no gate (no
    -- sector header without a disk) and ends when READY falls.
    wait for last_step_end + (C2_SETTLE + 10) * C_CLK - now;
    check(media_ready2 = '1' and head_settled2 = '1', "READY not up after the head settled (pull during a train)");
    prev_done := rd_done2;
    rd_op2 <= RDOP_READ_SECTOR;
    wait until rising_edge(clk2);
    rd_req2 <= not rd_req2;
    wait until rd_done2 /= prev_done for 10 * C_CLK;
    check(rd_done2 /= prev_done, "a Read Sector after a pull during a train did not end at once");
    wait for 1 us;
    check(rd_result2 = RES_DISK_CHANGED and rd_rnf2 = '1',
          "a Read Sector after a pull during a train did not end with 'disk changed'");
    check(bytes2 = 0, "a byte reached the FIFO after a pull during a train");
    prev_done := rd_done2;
    rd_op2 <= WROP_WRITE_SECTOR;
    wait until rising_edge(clk2);
    rd_req2 <= not rd_req2;
    fall_at2(t_exp, "a disk taken out during a train, 500 ms after the head settled");
    wait until rd_done2 /= prev_done for 1 us;
    check(rd_done2 /= prev_done, "a Write Sector after a pull during a train did not end when READY fell");
    wait for 100 ns;
    check(rd_result2 /= RES_OK, "a Write Sector after a pull during a train ended with OK");
    -- the disk comes back: ready with its first index edge
    cfg_present2 <= '1';
    wait_idx2(p2(450 ms), "after the disk came back");
    check(media_ready2 = '1', "not ready after the disk came back");
    cfg_change2 <= '0';
    step2(dir, p2(6 ms));
    expect_ready2 <= '1';

    -- A disk taken out while the head rests: READY falls 500 ms after the
    -- last index edge (the controller accepts an edge 200 us after INDEX
    -- went low).
    wait_idx2(p2(450 ms), "before the pull at rest");
    wait for p2(50 ms);
    cfg_present2 <= '0'; cfg_change2 <= '1';
    check(last_idx_edge2 - last_idx_fall >= C_IDX_FILTER and last_idx_edge2 - last_idx_fall < C_IDX_FILTER + 200 ns,
          "the last index edge was not accepted 200 us after INDEX went low");
    fall_at2(last_idx_edge2 + (C2_LIM + 1) * C_CLK, "a disk taken out at rest, 500 ms after the last index edge");

    -- Steps with the motor on and no disk: READY stays down, also after the
    -- head has settled.
    expect_idle2 <= '1';
    train2(39, dir, 6 ms, 18 ms);
    dir := not dir;
    wait for p2(18 ms + 600 ms);
    expect_idle2 <= '0';

    -- The disk comes back; then, on a mechanism that delivers its index
    -- pulses while it steps, the first index edge after a motor restart
    -- comes during a train of 80 steps at 12 ms and makes the drive ready at
    -- once.
    cfg_present2 <= '1'; cfg_change2 <= '0';
    wait_idx2(p2(450 ms), "after the second return of the disk");
    motor2 <= '0';
    wait for 1 us;
    check(media_ready2 = '0', "READY stayed up with the motor off");
    motor2 <= '1';
    cfg_hide2 <= 0 ns;
    for i in 1 to 80 loop
      step2(dir, p2(12 ms));
      if i = 40 then
        check(media_ready2 = '1', "an index edge during a train did not make the drive ready");
        expect_ready2 <= '1';
      end if;
    end loop;
    dir := not dir;
    wait_idx2(p2(450 ms), "after the last train");

    -- Step trains on a mechanism that withholds its index pulses while the
    -- head steps and for the hold time after the last step: READY stays up
    -- in every one. Each train starts at another phase of the revolution.
    for c in C_TRAINS'range loop
      wait_idx2(p2(450 ms), "before train " & integer'image(c));
      phase := (phase + 70 ms) mod 200 ms;
      wait for p2(phase);
      train2(C_TRAINS(c).n1, dir, C_TRAINS(c).pace, C_TRAINS(c).hold);
      dir := not dir;
      if C_TRAINS(c).n2 > 0 then
        wait for p2(C_GAP);
        train2(C_TRAINS(c).n2, dir, C_TRAINS(c).pace, C_TRAINS(c).hold);
        dir := not dir;
      end if;
      wait_idx2(p2(C_TRAINS(c).hold + 450 ms), "after train " & integer'image(c));
    end loop;
    report "part 2: READY stayed up through " & integer'image(C_TRAINS'length) & " step trains";

    report "part 2 done";
    done2 <= true;
    wait;
  end process;

  final_p : process
  begin
    wait until done1 and done2;
    report "tb_physical_1581_media_contract: ALL TESTS PASSED";
    finish;
  end process;

  guard : process
  begin
    wait for 900 ms;
    report "global timeout" severity failure;
  end process;
end architecture;
