----------------------------------------------------------------------------------------------------
-- Amiga mouse bench (GitHub issue #190), part 1: M2M/vhdl/amiga_mouse.vhd alone
--
-- The bench sees the DUT only through its ports. G_PART selects what runs (see README.md):
--
--   dir          start value 64, every legal transition of both sequences counts exactly +1 / -1,
--                the POT value (full units only) after every count, wrap-around within 64 to 190
--   double       a change of both lines of a pair counts nothing, the decoder stays in step
--   pulse        pulses shorter than the filter never change an output; pulses one clock period
--                longer than the filter always pass (the filter time in clock periods)
--   model        a model of the mouse, asynchronous to the clock, with a speed profile, a phase of
--                60 to 120 degrees between the lines, chatter and slow edges on every edge: the
--                output follows the true position at every clock cycle and ends exactly on it
--   rate_follow  constant speeds up to the rate limit: the delay of every count
--   rate_sat     constant speeds above the rate limit, then stop: one step per tick at most, never
--                against the direction, at most G_BACKLOG steps after the stop, dropped counts
--   rate_tick    a count of the decoder and a step of the rate limiter in the same clock cycle
--   driver       the movement routine of the 1351 manual, called once per frame (G_FRAME_NS)
--                with a jitter of +-1 ms, while the mouse moves up to and above the rate limit:
--                it neither loses nor invents a unit
--   enable       enable_i: nothing counted while '0', no count when it turns '1' in any of the
--                16 line states, the backlog is emptied, the position is kept
--   times        step time and confirmation time at the clock G_CLK_HZ (PAL or NTSC)
--   buttons      the right and middle button on the paddle pins (small time generics)
--   defaults     the default times of the buttons at a slow clock (30 s stuck time)
--
-- Every error is reported as "TB_ERROR: ..."; the last line is "TB: RESULT PASS" or
-- "TB: RESULT FAIL ...". With G_STOP the bench ends at the first error (mutants).
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;
use work.tb_amiga_mouse_pkg.all;

entity tb_amiga_mouse is
   generic (
      G_PART       : string   := "dir";
      G_CLK_HZ     : positive := 31_527_778;   -- frequency of the simulated clock
      G_FREQ       : positive := 31_527_778;   -- G_CLK_FREQ of the DUT
      G_FILTER_NS  : natural  := 2000;         -- generics of the DUT
      G_STEP_US    : natural  := 400;
      G_BACKLOG    : natural  := 127;
      G_CONFIRM_US : natural  := 4000;
      G_STUCK_MS   : natural  := 30000;
      G_SEED       : positive := 1;
      G_PHASE_X    : natural  := 90;           -- phase between the two lines of X in degrees
      G_PHASE_Y    : natural  := 90;           -- ... of Y
      G_FRAME_NS   : natural  := 19_950_400;   -- driver: time between two calls (PAL frame)
      G_PARITY     : natural  := 0;            -- rate_follow: 1 starts with a count that the DUT does
                                               -- not see, so that the other half of the counts
                                               -- changes the POT value
      G_MON_CHECK  : boolean  := true;         -- false: the output checkers report nothing
      G_STOP       : boolean  := false         -- end at the first error
   );
end entity tb_amiga_mouse;

architecture sim of tb_amiga_mouse is

   constant C_HALF     : time := 1 sec / (2 * G_CLK_HZ);
   constant C_PERIOD   : time := 2 * C_HALF;

   function max1(n : integer) return positive is
   begin
      if n < 1 then
         return 1;
      end if;
      return n;
   end function max1;

   -- the numbers of the specification for the generics of the DUT
   constant C_FILTER   : natural  := (G_FREQ / 1000) * G_FILTER_NS / 1_000_000;  -- clock cycles
   constant C_STEP     : positive := max1((G_FREQ / 1000) * G_STEP_US / 1000);    -- clock cycles per tick
   constant C_TICK     : time     := C_STEP * C_PERIOD;
   constant C_CONFIRM  : positive := max1(G_CONFIRM_US / max1(G_STEP_US));        -- ticks
   constant C_STUCK    : positive := max1(G_STUCK_MS * 1000 / max1(G_STEP_US));   -- ticks
   -- latency from a pin to the decoder: chatter (at most 4 us), synchronizer, filter
   constant C_LAT      : time     := 6 us + (C_FILTER + 5) * C_PERIOD;

   -- the lines: index 0 up (V), 1 down (H), 2 left (VQ), 3 right (HQ); per axis (0 is X, 1 is Y)
   -- the first and the second line of the pair of SPEC.md section 4.2
   type nat2_t is array (0 to 1) of natural;
   constant C_FIRST    : nat2_t := (3, 2);
   constant C_SECOND   : nat2_t := (1, 0);
   constant C_AXIS_OF  : integer_vector(0 to 3) := (1, 0, 1, 0);

   function seq_of(a : natural) return seq_t is
   begin
      if a = 0 then
         return C_SEQ_X;
      end if;
      return C_SEQ_Y;
   end function seq_of;

   signal clk          : std_logic := '0';
   signal running      : boolean   := true;

   -- DUT ports
   signal enable       : std_logic := '1';
   signal pin          : std_logic_vector(3 downto 0) := "1111";
   signal meas_x       : std_logic_vector(7 downto 0) := x"FF";
   signal meas_y       : std_logic_vector(7 downto 0) := x"FF";
   signal pot_x        : std_logic_vector(7 downto 0);
   signal pot_y        : std_logic_vector(7 downto 0);
   signal rbtn_n       : std_logic;
   signal mbtn_n       : std_logic;

   -- requested levels of the lines: from the stimulus or from the mouse model
   signal lvl_stim     : std_logic_vector(3 downto 0) := "1111";
   signal lvl_mod      : std_logic_vector(3 downto 0) := "1111";
   signal use_mod      : boolean := false;
   signal lvl          : std_logic_vector(3 downto 0);
   signal chat         : boolean := false;    -- chatter and slow edges on every edge

   -- mouse model: a speed profile per axis
   type seg_t is record
      dur : time;
      cps : real;                             -- counts per second, signed
   end record seg_t;
   type seg_arr_t is array (0 to 255) of seg_t;
   type prof_t is record
      n   : natural;
      seg : seg_arr_t;
   end record prof_t;
   type prof2_t is array (0 to 1) of prof_t;
   signal prof         : prof2_t;
   signal go           : integer_vector(0 to 1) := (0, 0);
   signal done         : integer_vector(0 to 1) := (0, 0);
   signal tru          : integer_vector(0 to 1) := (0, 0);    -- true position in counts
   signal tru_t        : time_vector(0 to 1)    := (0 fs, 0 fs);
   signal p_off        : integer_vector(0 to 1) := (0, 0);    -- position of the DUT = tru - p_off

   -- per-axis checker
   signal mon_rst      : natural := 0;          -- clears the counters of the checkers
   signal fol_on       : boolean := false;      -- follow check: output within the true positions
   signal fol_d        : time    := 10 us;      -- ... of the last fol_d
   signal dly_on       : boolean := false;      -- delay check of a monotonic movement
   signal dly_max      : time    := 1 ms;
   signal pos          : integer_vector(0 to 1) := (0, 0);    -- unwrapped output position
   signal nchg         : integer_vector(0 to 1) := (0, 0);    -- output changes since mon_rst
   signal ups          : integer_vector(0 to 1) := (0, 0);
   signal downs        : integer_vector(0 to 1) := (0, 0);
   signal first_chg    : time_vector(0 to 1)    := (0 fs, 0 fs);
   signal last_chg     : time_vector(0 to 1)    := (0 fs, 0 fs);
   signal max_dly      : time_vector(0 to 1)    := (0 fs, 0 fs);
   signal win_mn       : integer_vector(0 to 1) := (0, 0);
   signal win_mx       : integer_vector(0 to 1) := (0, 0);
   signal fifo_n       : integer_vector(0 to 1) := (0, 0);
   signal bchg         : integer_vector(0 to 1) := (0, 0);    -- button output changes

   -- driver model
   signal drv_on       : boolean := false;
   signal drv_mode     : integer := 0;          -- 0: follow; +1 / -1: direction of X (Y opposite)
   signal drv_calls    : natural := 0;

   -- errors of all processes
   shared variable errcnt : counter_pt;

   procedure tb_error(msg : string) is
   begin
      if errcnt.value < 30 then
         report "TB_ERROR: " & msg severity error;
      end if;
      errcnt.inc;
      if G_STOP then
         report "TB: RESULT FAIL (stopped at the first error)" severity note;
         finish;
      end if;
   end procedure tb_error;

begin

   clk <= not clk after C_HALF when running;

   dut : entity work.amiga_mouse
      generic map (
         G_CLK_FREQ     => G_FREQ,
         G_FILTER_NS    => G_FILTER_NS,
         G_STEP_US      => G_STEP_US,
         G_BACKLOG      => G_BACKLOG,
         G_CONFIRM_US   => G_CONFIRM_US,
         G_STUCK_MS     => G_STUCK_MS
      )
      port map (
         clk_i          => clk,
         enable_i       => enable,
         up_n_i         => pin(0),
         down_n_i       => pin(1),
         left_n_i       => pin(2),
         right_n_i      => pin(3),
         meas_x_i       => meas_x,
         meas_y_i       => meas_y,
         pot_x_o        => pot_x,
         pot_y_o        => pot_y,
         right_btn_n_o  => rbtn_n,
         middle_btn_n_o => mbtn_n
      );

   lvl <= lvl_mod when use_mod else lvl_stim;

   ---------------------------------------------------------------------------------------------
   -- Line drivers: each pin follows its requested level; with chat every edge is a burst that
   -- ends at the new level: either chatter (the new level, then 1 to 4 pulses of 50 to 500 ns
   -- back to the old level) or a slow edge (3 to 7 toggles of 10 to 200 ns while the edge
   -- crosses the threshold). A new request during a burst restarts it.
   ---------------------------------------------------------------------------------------------
   gen_lines : for i in 0 to 3 generate
      line_drv : process
         variable r      : rng_t := rng_init(1000 + 17 * G_SEED + i);
         variable target : std_logic;
         variable cur    : std_logic;
         variable kind   : integer;
         variable n      : integer;
         variable dt     : real;
      begin
         pin(i) <= '1';
         wait on lvl(i);
         loop
            target := lvl(i);
            if not chat then
               pin(i) <= target;
               wait on lvl(i);
            else
               rand_int(r, 0, 1, kind);
               if kind = 0 then
                  rand_int(r, 1, 4, n);
               else
                  rand_int(r, 1, 3, n);
               end if;
               n   := 2 * n + 1;
               cur := target;
               for k in 1 to n loop
                  pin(i) <= cur;
                  exit when k = n;
                  if kind = 0 then
                     rand_real(r, 50.0, 500.0, dt);
                  else
                     rand_real(r, 10.0, 200.0, dt);
                  end if;
                  wait on lvl(i) for dt * 1 ns;
                  exit when lvl(i) /= target;
                  cur := not cur;
               end loop;
               if lvl(i) = target then
                  pin(i) <= target;
                  wait on lvl(i);
               end if;
            end if;
         end loop;
      end process line_drv;
   end generate gen_lines;

   ---------------------------------------------------------------------------------------------
   -- Mouse model, one per axis. The phase theta is measured in counts (a cycle of the pair is
   -- 4.0); the transition from count k to k+1 lies at bpos(k): within a cycle at 0, e1, 2 and
   -- 2 + e1 (plus an offset that puts theta = 0 into the middle of state 0), where e1 = phase / 90
   -- is the phase between the two lines. A speed of v counts per second moves theta by v per
   -- second, so the counts per second are exact on average for every phase. The lines show the
   -- state (count mod 4) of the sequence of the axis.
   ---------------------------------------------------------------------------------------------
   gen_model : for a in 0 to 1 generate
      model : process
         variable e1    : real;
         variable b0    : real;
         variable theta : real    := 0.0;
         variable n     : integer := 0;
         variable v     : real;
         variable dist  : real;
         variable left_t   : time;
         variable tn    : time;

         impure function bpos(k : integer) return real is
            variable m : integer;
            variable q : integer;
            variable o : real;
         begin
            m := k mod 4;
            q := (k - m) / 4;
            case m is
               when 0      => o := 0.0;
               when 1      => o := e1;
               when 2      => o := 2.0;
               when others => o := 2.0 + e1;
            end case;
            return 4.0 * real(q) + b0 + o;
         end function bpos;

         procedure set_lines is
            variable s : std_logic_vector(1 downto 0);
         begin
            s := seq_of(a)(n mod 4);
            lvl_mod(C_FIRST(a))  <= s(1);
            lvl_mod(C_SECOND(a)) <= s(0);
            tru(a)               <= n;
            tru_t(a)             <= now;
         end procedure set_lines;
      begin
         if a = 0 then
            e1 := real(G_PHASE_X) / 90.0;
         else
            e1 := real(G_PHASE_Y) / 90.0;
         end if;
         b0 := (2.0 - e1) / 2.0;
         set_lines;
         loop
            wait on go(a);
            for k in 0 to prof(a).n - 1 loop
               v   := prof(a).seg(k).cps;
               left_t := prof(a).seg(k).dur;
               while left_t > 0 fs loop
                  if v > 0.0 then
                     dist := bpos(n) - theta;
                     tn   := (dist / v) * 1 sec;
                  elsif v < 0.0 then
                     dist := theta - bpos(n - 1);
                     tn   := (dist / (-v)) * 1 sec;
                  else
                     tn   := left_t + 1 fs;
                  end if;
                  if tn <= left_t then
                     wait for tn;
                     left_t := left_t - tn;
                     if v > 0.0 then
                        theta := bpos(n);
                        n     := n + 1;
                     else
                        theta := bpos(n - 1);
                        n     := n - 1;
                     end if;
                     set_lines;
                  else
                     wait for left_t;
                     theta := theta + v * real(left_t / 1 ns) * 1.0e-9;
                     left_t   := 0 fs;
                  end if;
               end loop;
            end loop;
            done(a) <= go(a);
         end loop;
      end process model;
   end generate gen_model;

   ---------------------------------------------------------------------------------------------
   -- Checker per axis, at every falling clock edge. The POT value carries full units only (two
   -- counts); pos is the output in units, unwrapped.
   --  * every change of the POT value is one unit up or down (2 LSB, mod 128), never faster than
   --    one change per tick; the value is 64 + 2 * (pos mod 64): pot(7) = q(6), pot(6) = not q(6),
   --    pot(5 downto 1) = q(5 downto 1), pot(0) = '0' for q = 2 * pos mod 128
   --  * fol_on: pos is floor(n / 2) for a true position n of the last fol_d
   --  * dly_on: monotonic movement; the k-th change of the output belongs to the k-th count of
   --    the mouse that crosses a unit boundary (same direction) and comes at most dly_max after it
   ---------------------------------------------------------------------------------------------
   gen_chk : for a in 0 to 1 generate
      chk : process (clk)
         variable last    : std_logic_vector(7 downto 0) := x"40";
         variable p       : std_logic_vector(7 downto 0);
         variable d       : integer;
         variable r       : integer := 0;
         variable rp      : natural;
         variable tchg    : time;
         variable lastc   : time := 0 fs;
         variable anyc    : boolean := false;
         variable rst_d   : natural := 0;
         variable cnt     : natural := 0;
         variable cu      : natural := 0;
         variable cd      : natural := 0;
         variable started : boolean := false;
         -- history of the true position: (time, value before, value after)
         type hist_t is array (0 to 63) of integer;
         variable h_t     : time_vector(0 to 63);
         variable h_b     : hist_t;
         variable h_a     : hist_t;
         variable h_n     : natural := 0;
         variable cur_n   : integer := 0;
         variable n_eff   : integer;
         variable mn, mx  : integer;
         variable k       : integer;
         -- fifo of counts for the delay check
         type fifo_t is array (0 to 1023) of integer;
         variable f_t     : time_vector(0 to 1023);
         variable f_s     : fifo_t;
         variable f_rd    : natural := 0;
         variable f_wr    : natural := 0;
         variable dl      : time;
         variable mdl     : time := 0 fs;
         variable mn_d    : integer := 0;
         variable mx_d    : integer := 0;
      begin
         if falling_edge(clk) then
            if mon_rst /= rst_d then
               rst_d := mon_rst;
               cnt   := 0;
               cu    := 0;
               cd    := 0;
               anyc  := false;
               mdl   := 0 fs;
               f_rd  := 0;
               f_wr  := 0;
               nchg(a)    <= 0;
               ups(a)     <= 0;
               downs(a)   <= 0;
               max_dly(a) <= 0 fs;
            end if;

            -- true position (in the counts of the DUT: minus the counts it did not see)
            n_eff := tru(a) - p_off(a);
            if n_eff /= cur_n then
               h_t(h_n mod 64) := tru_t(a);
               h_b(h_n mod 64) := cur_n;
               h_a(h_n mod 64) := n_eff;
               h_n := h_n + 1;
               if dly_on and fl2(n_eff) /= fl2(cur_n) then
                  f_t(f_wr mod 1024) := tru_t(a);
                  f_s(f_wr mod 1024) := fl2(n_eff) - fl2(cur_n);
                  f_wr := f_wr + 1;
               end if;
               cur_n := n_eff;
            end if;

            -- output
            if a = 0 then
               p := pot_x;
            else
               p := pot_y;
            end if;
            if not started then
               started := true;
               if p /= x"40" then
                  tb_error("axis " & integer'image(a) & ": start value is " & to_hstring(p) & ", not 40");
               end if;
               last := p;
            end if;
            if p /= last then
               tchg := now - C_HALF;               -- the rising edge that changed the output
               d    := (pot_pos(p) - pot_pos(last)) mod 128;
               if d = 2 then
                  r  := r + 1;
                  cu := cu + 1;
               elsif d = 126 then
                  r  := r - 1;
                  cd := cd + 1;
               elsif G_MON_CHECK then
                  tb_error("axis " & integer'image(a) & ": output jumps from " & to_hstring(last) & " to " &
                           to_hstring(p));
               end if;
               rp := (2 * r) mod 128;
               if G_MON_CHECK and (to_integer(unsigned(p)) /= 64 + rp or p(7) /= to_unsigned(rp, 7)(6) or
                  p(6) = to_unsigned(rp, 7)(6) or p(5 downto 1) /= std_logic_vector(to_unsigned(rp, 7)(5 downto 1)) or
                  p(0) /= '0') then
                  tb_error("axis " & integer'image(a) & ": POT value " & to_hstring(p) & " for " &
                           integer'image(r) & " units");
               end if;
               if G_MON_CHECK and lastc > 0 fs and tchg - lastc < C_TICK then
                  tb_error("axis " & integer'image(a) & ": two changes within " & rstr(to_us(tchg - lastc)) &
                           " us, less than one tick");
               end if;
               if not anyc then
                  first_chg(a) <= tchg;
                  anyc := true;
               end if;
               lastc := tchg;
               cnt   := cnt + 1;
               last  := p;
               pos(a)      <= r;
               nchg(a)     <= cnt;
               ups(a)      <= cu;
               downs(a)    <= cd;
               last_chg(a) <= tchg;

               if dly_on and G_MON_CHECK then
                  if f_rd = f_wr then
                     tb_error("axis " & integer'image(a) & ": output moves without a count of the mouse");
                  else
                     if (d = 2 and f_s(f_rd mod 1024) /= 1) or (d = 126 and f_s(f_rd mod 1024) /= -1) then
                        tb_error("axis " & integer'image(a) & ": output moves against the mouse");
                     end if;
                     dl := tchg - f_t(f_rd mod 1024);
                     if dl > mdl then
                        mdl := dl;
                        max_dly(a) <= dl;
                     end if;
                     if dl > dly_max then
                        tb_error("axis " & integer'image(a) & ": delay of a count " & rstr(to_us(dl)) &
                                 " us, more than " & rstr(to_us(dly_max)) & " us");
                     end if;
                     f_rd := f_rd + 1;
                  end if;
               end if;
            end if;
            fifo_n(a) <= f_wr - f_rd;

            -- the true positions within the last fol_d
            mn := cur_n;
            mx := cur_n;
            k  := h_n - 1;
            while k >= 0 and k > h_n - 64 loop
               exit when h_t(k mod 64) <= now - fol_d;
               mn := minimum(mn, h_b(k mod 64));
               mx := maximum(mx, h_b(k mod 64));
               k  := k - 1;
            end loop;
            if mn /= mn_d then
               win_mn(a) <= mn;
               mn_d := mn;
            end if;
            if mx /= mx_d then
               win_mx(a) <= mx;
               mx_d := mx;
            end if;
            if G_MON_CHECK and fol_on and (r < fl2(mn) or r > fl2(mx)) then
               tb_error("axis " & integer'image(a) & ": output " & integer'image(r) & " units, true positions " &
                        "of the last " & rstr(to_us(fol_d)) & " us " & integer'image(mn) & " .. " & integer'image(mx) &
                        " counts");
            end if;
         end if;
      end process chk;
   end generate gen_chk;

   -- changes of the button outputs
   btn_mon : process (clk)
      variable lr, lm : std_logic := '1';
      variable cr, cm : natural := 0;
   begin
      if falling_edge(clk) then
         if rbtn_n /= lr then
            lr := rbtn_n;
            cr := cr + 1;
            bchg(0) <= cr;
         end if;
         if mbtn_n /= lm then
            lm := mbtn_n;
            cm := cm + 1;
            bchg(1) <= cm;
         end if;
      end if;
   end process btn_mon;

   ---------------------------------------------------------------------------------------------
   -- The movement routine of the 1351 manual, called every G_FRAME_NS with a jitter of +-1 ms.
   -- Exactness: the sum of its results equals the change of the output in units (no unit lost or
   -- invented), in every call and every drv_mode.
   -- drv_mode 0 (within the rate limit): in every call, the sum of the results plus floor(n0 / 2)
   -- is floor(n / 2) for a true position n of the follow window (fol_d), n0 being the true position
   -- at the start; this check does not use the output checker.
   -- drv_mode +1 / -1: X moves in that direction and Y in the opposite one; the driver never
   -- returns a movement against it.
   ---------------------------------------------------------------------------------------------
   driver : process
      variable r       : rng_t := rng_init(3000 + G_SEED);
      variable old     : integer_vector(0 to 1);
      variable sum     : integer_vector(0 to 1);     -- sum of the results (position units)
      variable odd     : integer_vector(0 to 1);     -- calls with an odd difference
      variable pos0    : integer_vector(0 to 1);     -- output in units at the start
      variable n0      : integer_vector(0 to 1);     -- true position at the start
      variable res     : integer;
      variable acc     : integer;
      variable o       : natural;
      variable jit     : real;
      variable t0      : time;
      variable tc      : time;
      variable i       : natural;
      variable calls   : natural;
      variable maxd    : natural;
      variable dir     : integer;
      variable p       : std_logic_vector(7 downto 0);
   begin
      wait until drv_on;
      loop
         t0    := now;
         old   := (pot_pos(pot_x), pot_pos(pot_y));
         pos0  := pos;
         n0    := (tru(0) - p_off(0), tru(1) - p_off(1));
         sum   := (0, 0);
         odd   := (0, 0);
         calls := 0;
         maxd  := 0;
         i     := 1;
         while drv_on loop
            rand_real(r, -1.0, 1.0, jit);
            tc := t0 + i * G_FRAME_NS * 1 ns + jit * 1 ms;
            wait until not drv_on for tc - now;
            exit when not drv_on;
            for a in 0 to 1 loop
               if a = 0 then
                  p := pot_x;
                  dir := drv_mode;
               else
                  p := pot_y;
                  dir := -drv_mode;
               end if;
               o := old(a);
               drv_move(pot_pos(p), o, res, acc);
               old(a) := o;
               sum(a) := sum(a) + res;
               if acc mod 2 /= 0 then
                  odd(a) := odd(a) + 1;
               end if;
               maxd := maximum(maxd, abs(acc));
               if G_MON_CHECK and sum(a) /= pos(a) - pos0(a) then
                  tb_error("driver, axis " & integer'image(a) & ": sum of the results " & integer'image(sum(a)) &
                           ", the output moved by " & integer'image(pos(a) - pos0(a)) & " units");
               end if;
               if drv_mode = 0 then
                  if sum(a) + fl2(n0(a)) < fl2(win_mn(a)) or sum(a) + fl2(n0(a)) > fl2(win_mx(a)) then
                     tb_error("driver, axis " & integer'image(a) & ": sum of the results " & integer'image(sum(a)) &
                              " from " & integer'image(n0(a)) & " counts, true positions " & integer'image(win_mn(a)) &
                              " .. " & integer'image(win_mx(a)) & " counts");
                  end if;
               elsif res * dir < 0 then
                  tb_error("driver, axis " & integer'image(a) & ": movement " & integer'image(res) &
                           " against the direction of the mouse");
               end if;
            end loop;
            calls := calls + 1;
            drv_calls <= calls;
            i := i + 1;
         end loop;
         report "TB: driver: " & integer'image(calls) & " calls, largest difference " & integer'image(maxd) &
                " LSB, odd differences " & integer'image(odd(0) + odd(1)) & "; X: sum of the results " &
                integer'image(sum(0)) & " units for " & integer'image(tru(0) - n0(0)) & " counts; Y: " &
                integer'image(sum(1)) & " units for " & integer'image(tru(1) - n0(1)) & " counts";
         wait until drv_on;
      end loop;
   end process driver;

   ---------------------------------------------------------------------------------------------
   -- Stimulus
   ---------------------------------------------------------------------------------------------
   stim : process
      variable r     : rng_t := rng_init(G_SEED);
      variable pr    : prof2_t;
      variable n0    : integer_vector(0 to 1);
      variable c0    : integer_vector(0 to 1);
      variable x     : real;
      variable t     : time;
      variable t1    : time;
      variable ok    : boolean;
      variable pexp  : integer_vector(0 to 1) := (0, 0);   -- expected position in counts (stimulus)

      procedure err(msg : string) is
      begin
         tb_error(msg);
      end procedure err;

      procedure note(msg : string) is
      begin
         report "TB: " & msg severity note;
      end procedure note;

      procedure reset_mon is
      begin
         mon_rst <= mon_rst + 1;
         wait for 2 * C_PERIOD;
      end procedure reset_mon;

      -- one clean legal transition of axis a in direction dir (+1 / -1), through lvl_stim
      -- one clean legal transition of axis a in direction dir (+1 / -1), through lvl_stim
      procedure step_stim(a : natural; dir : integer) is
         variable s  : std_logic_vector(1 downto 0);
         variable s2 : std_logic_vector(1 downto 0);
      begin
         s  := lvl_stim(C_FIRST(a)) & lvl_stim(C_SECOND(a));
         s2 := seq_of(a)((seq_index(seq_of(a), s) + dir) mod 4);
         lvl_stim(C_FIRST(a))  <= s2(1);
         lvl_stim(C_SECOND(a)) <= s2(0);
         pexp(a) := pexp(a) + dir;
         wait for 0 ns;
      end procedure step_stim;

      -- switch the lines from the model to the stimulus (or back) without an edge
      procedure lines_from_stim is
      begin
         lvl_stim <= lvl_mod;
         wait for 0 ns;
         use_mod  <= false;
         wait for 0 ns;
      end procedure lines_from_stim;

      -- wait until the output position of axis a changed or the time t passed
      procedure wait_pos(a : natural; tmax : time; changed : out boolean) is
         variable p0 : integer;
      begin
         p0 := pos(a);
         wait until pos(a) /= p0 for tmax;
         changed := pos(a) /= p0;
      end procedure wait_pos;

      -- a clean transition must move the output by exactly d, and only axis a
      -- a clean transition moves the position by dir: the POT value of axis a changes by one unit
      -- if that crosses a unit boundary (upwards from odd to even, downwards from even to odd) and
      -- stays otherwise; the other axis does not change
      procedure expect_step(a : natural; dir : integer) is
         variable q0 : std_logic_vector(7 downto 0);
         variable u0 : integer;
         variable ch : boolean;
         variable p  : std_logic_vector(7 downto 0);
      begin
         if a = 0 then
            q0 := pot_y;
         else
            q0 := pot_x;
         end if;
         u0 := fl2(pexp(a));
         step_stim(a, dir);
         if fl2(pexp(a)) /= u0 then
            wait_pos(a, C_TICK + C_LAT + 1 us, ch);
            if not ch then
               err("axis " & integer'image(a) & ": transition " & integer'image(dir) & " to " &
                   integer'image(pexp(a)) & " counts did not change the POT value");
            end if;
         end if;
         wait for 2 * C_TICK + C_LAT;
         if a = 0 then
            p := pot_x;
         else
            p := pot_y;
         end if;
         if p /= pot_of(pexp(a)) or pos(a) /= fl2(pexp(a)) then
            err("axis " & integer'image(a) & ": after a transition " & integer'image(dir) & " to " &
                integer'image(pexp(a)) & " counts the POT value is " & to_hstring(p) & ", expected " &
                to_hstring(pot_of(pexp(a))));
         end if;
         if (a = 0 and pot_y /= q0) or (a = 1 and pot_x /= q0) then
            err("axis " & integer'image(a) & ": transition moved the other axis");
         end if;
      end procedure expect_step;

      procedure const_prof(a : natural; dur : time; cps : real) is
      begin
         pr(a).n := 1;
         pr(a).seg(0) := (dur => dur, cps => cps);
      end procedure const_prof;

      -- n segments of tmin to tmax, speed with a magnitude log-uniform from vmin to vmax and a
      -- random sign (sgn = 0) or the sign sgn; a pause with the probability ppause
      procedure rand_prof(a : natural; n : natural; tmin, tmax : time; vmin, vmax : real; sgn : integer;
                          ppause : real) is
         variable dur : real;
         variable v   : real;
         variable s   : real;
         variable q   : real;
      begin
         pr(a).n := n;
         for k in 0 to n - 1 loop
            rand_real(r, real(tmin / 1 us), real(tmax / 1 us), dur);
            rand(r, q);
            if q < ppause then
               v := 0.0;
            else
               rand_real(r, log(vmin), log(vmax), v);
               v := exp(v);
               if sgn = 0 then
                  rand(r, s);
                  if s < 0.5 then
                     v := -v;
                  end if;
               elsif sgn < 0 then
                  v := -v;
               end if;
            end if;
            pr(a).seg(k) := (dur => dur * 1 us, cps => v);
         end loop;
      end procedure rand_prof;

      procedure run_prof is
         variable g : integer_vector(0 to 1);
      begin
         prof   <= pr;
         use_mod <= true;
         wait for 0 ns;
         g := (go(0) + 1, go(1) + 1);
         go <= g;
         wait until done = g;
      end procedure run_prof;

      -- the output equals the true position (after a pause)
      -- the output equals the true position of the model (after a pause)
      procedure expect_exact(what : string) is
         variable p : std_logic_vector(7 downto 0);
      begin
         for a in 0 to 1 loop
            if a = 0 then
               p := pot_x;
            else
               p := pot_y;
            end if;
            if pos(a) /= fl2(tru(a) - p_off(a)) or p /= pot_of(tru(a) - p_off(a)) then
               err(what & ", axis " & integer'image(a) & ": output " & integer'image(pos(a)) & " units (POT " &
                   to_hstring(p) & "), true position " & integer'image(tru(a) - p_off(a)) & " counts");
            end if;
         end loop;
      end procedure expect_exact;

      procedure set_meas(b : natural; v : natural) is
      begin
         if b = 0 then
            meas_x <= std_logic_vector(to_unsigned(v, 8));
         else
            meas_y <= std_logic_vector(to_unsigned(v, 8));
         end if;
      end procedure set_meas;

      impure function btn(b : natural) return std_logic is
      begin
         if b = 0 then
            return rbtn_n;
         end if;
         return mbtn_n;
      end function btn;

      -- wait for the button output b to become v; returns the time from now
      procedure wait_btn(b : natural; v : std_logic; tmax : time; dt : out time) is
         variable ts : time;
      begin
         ts := now;
         if btn(b) /= v then
            if b = 0 then
               wait until rbtn_n = v for tmax;
            else
               wait until mbtn_n = v for tmax;
            end if;
         end if;
         dt := now - ts;
         wait for C_PERIOD;                     -- the change counters follow at the falling edge
      end procedure wait_btn;

      --------------------------------------------------------------------------------------------
      procedure part_dir is
         variable d : integer;
      begin
         wait for 10 * C_PERIOD;
         if pot_x /= x"40" or pot_y /= x"40" then
            err("start values " & to_hstring(pot_x) & " / " & to_hstring(pot_y) & ", not 40 / 40");
         end if;
         -- all four transitions of each sequence in both directions, from an even and from an odd
         -- position: 0 -> 1 -> 2 -> 3 -> 4 -> 3 -> 2 -> 1 -> 0
         for a in 0 to 1 loop
            for dir in 0 to 1 loop
               for k in 1 to 4 loop
                  expect_step(a, 1 - 2 * dir);
               end loop;
            end loop;
         end loop;
         for a in 0 to 1 loop
            if nchg(a) /= 4 then
               err("axis " & integer'image(a) & ": " & integer'image(nchg(a)) & " changes of the POT value for 8 counts");
            end if;
         end loop;
         note("all four transitions of both sequences, both directions: exactly +1 / -1 count on the own axis; " &
              "the POT value moved by one unit on every second count (upwards from odd to even, downwards from even " &
              "to odd) and stayed on the others");
         -- wrap-around: +200 and -260 counts on both axes (checked after every count when the rate
         -- limiter is fast, else the output checker sees every change)
         for a in 0 to 1 loop
            for k in 1 to 460 loop
               if k <= 200 then
                  d := 1;
               else
                  d := -1;
               end if;
               if C_TICK < 10 us then
                  expect_step(a, d);
               else
                  step_stim(a, d);
                  wait for C_TICK + C_LAT;
               end if;
            end loop;
         end loop;
         wait for 2 * C_TICK + C_LAT;
         for a in 0 to 1 loop
            if pos(a) /= -30 or nchg(a) /= 4 + 100 + 130 then
               err("axis " & integer'image(a) & ": after +200 and -260 counts the output is " &
                   integer'image(pos(a)) & " units after " & integer'image(nchg(a)) & " changes");
            end if;
         end loop;
         if pot_x /= x"84" or pot_y /= x"84" then
            err("POT values after -60 counts: " & to_hstring(pot_x) & " / " & to_hstring(pot_y) & ", not 84");
         end if;
         note("wrap-around: +200 and -260 counts, after every count the POT value was 64 + position with bit 0 " &
              "cleared, within 40 .. BE");
      end procedure part_dir;

      --------------------------------------------------------------------------------------------
      procedure part_double is
         variable s     : std_logic_vector(1 downto 0);
         variable px    : std_logic_vector(7 downto 0);
         variable py    : std_logic_vector(7 downto 0);
         variable mv    : integer;
         variable kind  : integer;
      begin
         wait for 10 us;
         -- every state of each pair, at both parities of the position: the double transition counts
         -- nothing, the next legal transitions count as the new state says
         for a in 0 to 1 loop
            for st in 0 to 7 loop
               for k in 1 to 8 loop
                  s := lvl_stim(C_FIRST(a)) & lvl_stim(C_SECOND(a));
                  exit when seq_index(seq_of(a), s) = st mod 4 and pexp(a) mod 2 = st / 4;
                  expect_step(a, 1);
               end loop;
               px := pot_x;
               py := pot_y;
               lvl_stim(C_FIRST(a))  <= not lvl_stim(C_FIRST(a));
               lvl_stim(C_SECOND(a)) <= not lvl_stim(C_SECOND(a));
               wait for 3 * C_TICK + C_LAT;
               if pot_x /= px or pot_y /= py then
                  err("axis " & integer'image(a) & ": double transition from state " & integer'image(st mod 4) &
                      " changed the output");
               end if;
               expect_step(a, 1);
               expect_step(a, -1);
               expect_step(a, -1);
               expect_step(a, 1);
            end loop;
         end loop;
         note("double transition from each state of each pair, at both parities: no count, the decoder stays in step");
         -- random moves of both axes at the same instants: +1, -1 or a double transition
         for k in 1 to 600 loop
            for a in 0 to 1 loop
               rand_int(r, 0, 2, kind);
               if kind = 0 then
                  lvl_stim(C_FIRST(a))  <= not lvl_stim(C_FIRST(a));
                  lvl_stim(C_SECOND(a)) <= not lvl_stim(C_SECOND(a));
               else
                  mv := 2 * kind - 3;
                  s  := lvl_stim(C_FIRST(a)) & lvl_stim(C_SECOND(a));
                  s  := seq_of(a)((seq_index(seq_of(a), s) + mv) mod 4);
                  lvl_stim(C_FIRST(a))  <= s(1);
                  lvl_stim(C_SECOND(a)) <= s(0);
                  pexp(a) := pexp(a) + mv;
               end if;
            end loop;
            wait for 2 * C_TICK + C_LAT;
            if pot_x /= pot_of(pexp(0)) or pot_y /= pot_of(pexp(1)) then
               err("random moves: POT values " & to_hstring(pot_x) & " / " & to_hstring(pot_y) & ", expected " &
                   to_hstring(pot_of(pexp(0))) & " / " & to_hstring(pot_of(pexp(1))));
            end if;
         end loop;
         note("600 random moves of both axes at the same instants (+1, -1, double): POT values as expected after each");
      end procedure part_double;

      --------------------------------------------------------------------------------------------
      -- the count of a change of the four lines from s0 to s1 for axis a, as SPEC.md section 4.2
      -- defines it: +1 / -1 for a step of the sequence of the pair, 0 for no change or a change of
      -- both lines
      impure function count_of(a : natural; s0, s1 : std_logic_vector(3 downto 0)) return integer is
         variable p0 : std_logic_vector(1 downto 0);
         variable p1 : std_logic_vector(1 downto 0);
         variable d  : integer;
      begin
         p0 := s0(C_FIRST(a)) & s0(C_SECOND(a));
         p1 := s1(C_FIRST(a)) & s1(C_SECOND(a));
         d  := (seq_index(seq_of(a), p1) - seq_index(seq_of(a), p0)) mod 4;
         if d = 1 then
            return 1;
         elsif d = 3 then
            return -1;
         end if;
         return 0;
      end function count_of;

      procedure part_pulse is
         variable s      : std_logic_vector(3 downto 0);
         variable s2     : std_logic_vector(3 downto 0);
         variable i, j   : integer;
         variable w1, w2 : real;
         variable o      : real;
         variable g      : real;
         variable wmax   : real;
         variable npulse : natural := 0;
         variable a      : natural;
         variable d      : integer;
         variable nvis   : natural := 0;
         variable px     : std_logic_vector(7 downto 0);
         variable py     : std_logic_vector(7 downto 0);
         variable expc   : natural;
      begin
         wmax := (real(C_FILTER) - 0.3) * real(C_PERIOD / 1 fs) * 1.0e-6;      -- ns
         for st in 0 to 15 loop
            s := std_logic_vector(to_unsigned(st, 4));
            for ax in 0 to 1 loop
               pexp(ax) := pexp(ax) + count_of(ax, lvl_stim, s);
            end loop;
            lvl_stim <= s;
            wait for 3 * C_TICK + C_LAT;
            if pot_x /= pot_of(pexp(0)) or pot_y /= pot_of(pexp(1)) then
               err("state " & to_string(s) & ": POT values " & to_hstring(pot_x) & " / " & to_hstring(pot_y) &
                   " before the pulses, expected " & to_hstring(pot_of(pexp(0))) & " / " & to_hstring(pot_of(pexp(1))));
            end if;
            reset_mon;
            for k in 1 to 300 loop
               rand_int(r, 0, 3, i);
               rand_real(r, 5.0, wmax, w1);
               rand(r, g);
               if g < 0.3 then
                  -- two overlapping pulses on two lines
                  rand_int(r, 1, 3, j);
                  j := (i + j) mod 4;
                  rand_real(r, 5.0, wmax, w2);
                  rand_real(r, 0.0, w1, o);
                  lvl_stim(i) <= not s(i);
                  wait for o * 1 ns;
                  lvl_stim(j) <= not s(j);
                  if o + w2 < w1 then
                     wait for w2 * 1 ns;
                     lvl_stim(j) <= s(j);
                     wait for (w1 - o - w2) * 1 ns;
                     lvl_stim(i) <= s(i);
                  else
                     wait for (w1 - o) * 1 ns;
                     lvl_stim(i) <= s(i);
                     wait for (o + w2 - w1) * 1 ns;
                     lvl_stim(j) <= s(j);
                  end if;
                  npulse := npulse + 2;
               else
                  lvl_stim(i) <= not s(i);
                  wait for w1 * 1 ns;
                  lvl_stim(i) <= s(i);
                  npulse := npulse + 1;
               end if;
               rand_real(r, 0.0, 3000.0, g);              -- gap: at least two clock periods
               wait for 2 * C_PERIOD + g * 1 ns;
            end loop;
            wait for 3 * C_TICK + C_LAT;
            if nchg(0) /= 0 or nchg(1) /= 0 then
               err("state " & to_string(s) & ": pulses shorter than the filter changed the output " &
                   integer'image(nchg(0)) & " / " & integer'image(nchg(1)) & " times");
            end if;
         end loop;
         note(integer'image(npulse) & " pulses of 5 to " & rstr(wmax, 1) & " ns (" & rstr(real(C_FILTER) - 0.3, 1) &
              " clock periods) in all 16 states: no output changed in any clock cycle");
         -- one clock period longer than the filter: always passes as a count and its reverse, which
         -- is visible if the first of the two crosses a unit boundary
         w1 := (real(C_FILTER) + 1.3) * real(C_PERIOD / 1 fs) * 1.0e-6;
         for k in 1 to 128 loop
            rand_int(r, 0, 3, i);
            if k mod 8 = 0 then
               -- change the parity of the position with a clean step
               step_stim(k mod 16 / 8, 1);
               wait for 2 * C_TICK + C_LAT;
            end if;
            a  := C_AXIS_OF(i);
            s  := lvl_stim;
            s2 := s;
            s2(i) := not s(i);
            d  := count_of(a, s, s2);
            expc := 0;
            if fl2(pexp(a) + d) /= fl2(pexp(a)) then
               expc := 2;
               nvis := nvis + 1;
            end if;
            c0 := nchg;
            px := pot_x;
            py := pot_y;
            lvl_stim(i) <= not s(i);
            wait for w1 * 1 ns;
            lvl_stim(i) <= s(i);
            wait for 3 * C_TICK + C_LAT;
            if nchg(a) /= c0(a) + expc or nchg(1 - a) /= c0(1 - a) or pot_x /= px or pot_y /= py then
               err("a pulse of " & rstr(w1, 1) & " ns on line " & integer'image(i) & " at " & integer'image(pexp(a)) &
                   " counts: " & integer'image(nchg(a) - c0(a)) & " output changes, expected " & integer'image(expc));
            end if;
         end loop;
         note("128 pulses of " & rstr(w1, 1) & " ns (" & rstr(real(C_FILTER) + 1.3, 1) & " clock periods): each " &
              "passed as a count and its reverse (" & integer'image(nvis) & " of them visible because the first " &
              "count crossed a unit boundary)");
      end procedure part_pulse;

      --------------------------------------------------------------------------------------------
      procedure part_model is
         variable edges : integer_vector(0 to 1);
      begin
         chat   <= true;
         fol_d  <= C_LAT + C_TICK + 1 us;
         wait for 10 us;
         fol_on <= true;
         for run in 1 to 2 loop
            for a in 0 to 1 loop
               if run = 1 then
                  rand_prof(a, 40, 2 ms, 12 ms, 3.0, 20000.0, 0, 0.2);    -- all speeds, both directions
               else
                  rand_prof(a, 12, 2 ms, 10 ms, 4000.0, 20000.0, 0, 0.0);  -- fast, both directions
               end if;
            end loop;
            run_prof;
            wait for 3 * C_TICK + C_LAT;
            expect_exact("model run " & integer'image(run));
            note("model run " & integer'image(run) & ": " & integer'image(nchg(0)) & " / " & integer'image(nchg(1)) &
                 " output changes so far, true positions " & integer'image(tru(0)) & " / " & integer'image(tru(1)));
         end loop;
         -- a slow part: single steps with long pauses, both directions
         for a in 0 to 1 loop
            rand_prof(a, 24, 2 ms, 6 ms, 20.0, 400.0, 0, 0.5);
         end loop;
         run_prof;
         wait for 3 * C_TICK + C_LAT;
         expect_exact("single steps");
         fol_on <= false;
         note("phases " & integer'image(G_PHASE_X) & " / " & integer'image(G_PHASE_Y) &
              " degrees, chatter and slow edges on every edge, speeds of 3 to 20000 counts per second: " &
              "the output followed the true position in every clock cycle within " & rstr(to_us(C_LAT + C_TICK + 1 us), 1) &
              " us and ended on it");
      end procedure part_model;

      --------------------------------------------------------------------------------------------
      -- Constant speeds up to the rate limit. The POT value shows full units only, so the delay is
      -- measured for the counts that cross a unit boundary. With G_PARITY = 1 the mouse makes one
      -- count while enable_i is '0', so that the position of the DUT is one less than that of the
      -- mouse and the other half of the counts crosses the unit boundaries.
      -- The last run has clean edges: the delay of a count is then its latency from the pin to the
      -- decoder (C_FILTER + 3 to C_FILTER + 4 clock periods) plus its wait in the backlog, and a
      -- count that finds b counts waiting waits b to b + 1 ticks.
      procedure part_rate_follow is
         type spd_t is array (0 to 3, 0 to 1) of real;
         constant C_SPD : spd_t := ((100.0, -500.0), (-1000.0, 2000.0), (2400.0, -2400.0), (-2400.0, 2400.0));
         type dur_t is array (0 to 3) of time;
         constant C_DUR : dur_t := (120 ms, 60 ms, 100 ms, 100 ms);
         variable dmax  : time;
         variable wmax  : time;
         variable b     : integer;
         variable ph    : natural;
      begin
         chat <= true;
         -- the bound: at 90 degrees the edges are 417 us apart at 2400 counts per second, more than a
         -- tick, so a count never finds another one waiting; at 60 to 120 degrees two edges can be
         -- (2 / 3) / 2400 s = 277.8 us apart, and the second one waits for the tick after the first
         if G_PHASE_X = 90 and G_PHASE_Y = 90 then
            dmax := C_TICK + C_LAT;
         else
            dmax := 2 * C_TICK - 277.8 us + C_LAT;
         end if;
         dly_max <= dmax;
         wait for 10 us;
         if G_PARITY = 1 then
            -- one count that the DUT does not see: exactly one count for every phase of 60 to 120
            -- degrees, while enable_i is '0'
            enable <= '0';
            p_off  <= (1, 1);
            const_prof(0, 10 ms, 100.0);
            const_prof(1, 10 ms, 100.0);
            run_prof;
            wait for C_LAT;
            enable <= '1';
            wait for 2 * C_TICK + C_LAT;
            expect_exact("one count");
         end if;
         for run in 0 to 3 loop
            if run = 3 then
               chat <= false;
            end if;
            reset_mon;
            dly_on <= true;
            for a in 0 to 1 loop
               const_prof(a, C_DUR(run), C_SPD(run, a));
            end loop;
            run_prof;
            wait for 2 * C_TICK + C_LAT;
            dly_on <= false;
            expect_exact("rate_follow run " & integer'image(run));
            for a in 0 to 1 loop
               if a = 0 then
                  ph := G_PHASE_X;
               else
                  ph := G_PHASE_Y;
               end if;
               if fifo_n(a) /= 0 then
                  err("axis " & integer'image(a) & ": " & integer'image(fifo_n(a)) & " counts did not arrive");
               end if;
               if run < 3 then
                  note(rstr(C_SPD(run, a), 0) & " counts per second for " & rstr(to_us(C_DUR(run)) / 1000.0, 0) &
                       " ms, phase " & integer'image(ph) & ", parity " & integer'image(G_PARITY) & ": " &
                       integer'image(nchg(a)) & " unit changes, largest delay " & rstr(to_us(max_dly(a)), 1) & " us");
               else
                  wmax := max_dly(a) - (C_FILTER + 3) * C_PERIOD;
                  b    := wmax / C_TICK;
                  note("clean edges, " & rstr(C_SPD(run, a), 0) & " counts per second, phase " & integer'image(ph) &
                       ", parity " & integer'image(G_PARITY) & ": largest delay " & rstr(to_us(max_dly(a)), 1) &
                       " us, largest wait in the backlog " & rstr(to_us(wmax), 1) & " us: a count found at most " &
                       integer'image(b) & " other counts waiting (backlog at most " & integer'image(b + 1) & ")");
               end if;
            end loop;
         end loop;
         note("every count that crosses a unit boundary reached the output within " & rstr(to_us(dmax), 1) &
              " us (step time " & rstr(to_us(C_TICK), 2) & " us)");
      end procedure part_rate_follow;

      --------------------------------------------------------------------------------------------
      -- Above the rate limit. The position steps once per tick, so the POT value changes by one unit
      -- every second tick, without a gap; after the stop the backlog (G_BACKLOG - 1 or G_BACKLOG
      -- counts) follows: about G_BACKLOG / 2 unit changes.
      procedure part_rate_sat is
         type spd_t is array (0 to 2, 0 to 1) of real;
         constant C_SPD : spd_t := ((4000.0, -20000.0), (-8000.0, 8000.0), (20000.0, -4000.0));
         variable tstop : time;
         variable dir   : integer;
         variable steps : integer;
         variable n_after : integer;
         variable expr  : integer;
         variable span  : time;
      begin
         chat <= true;
         wait for 10 us;
         for run in 0 to 2 loop
            reset_mon;
            n0 := tru;
            for a in 0 to 1 loop
               const_prof(a, 100 ms, C_SPD(run, a));
            end loop;
            run_prof;
            tstop := now;
            wait for C_LAT;
            c0 := nchg;
            wait for real(G_BACKLOG + 30) * C_TICK;
            for a in 0 to 1 loop
               if C_SPD(run, a) > 0.0 then
                  dir := 1;
               else
                  dir := -1;
               end if;
               steps   := nchg(a);
               n_after := nchg(a) - c0(a);
               if (dir = 1 and downs(a) /= 0) or (dir = -1 and ups(a) /= 0) then
                  err("axis " & integer'image(a) & ": the output moved against the mouse");
               end if;
               if n_after > (G_BACKLOG + 1) / 2 or n_after < (G_BACKLOG - 1) / 2 then
                  err("axis " & integer'image(a) & ": " & integer'image(n_after) & " unit changes after the stop, " &
                      "expected " & integer'image((G_BACKLOG - 1) / 2) & " .. " & integer'image((G_BACKLOG + 1) / 2));
               end if;
               span := last_chg(a) - first_chg(a);
               if span /= (steps - 1) * 2 * C_TICK then
                  err("axis " & integer'image(a) & ": " & integer'image(steps) & " unit changes within " &
                      rstr(to_us(span), 2) & " us: not one count per tick without a gap");
               end if;
               -- counts that reached the position: one per tick from the first step to the stop, then
               -- the backlog; the first step comes one tick before the first unit change or with it
               expr := (tstop - first_chg(a)) / C_TICK + 1 + G_BACKLOG;
               if abs(2 * steps - expr) > 3 then
                  err("axis " & integer'image(a) & ": " & integer'image(steps) & " units, the bound implies " &
                      integer'image(expr) & " counts");
               end if;
               note(rstr(C_SPD(run, a), 0) & " counts per second for 100 ms: " & integer'image(abs(tru(a) - n0(a))) &
                    " counts, " & integer'image(steps) & " units (one count per tick), " & integer'image(n_after) &
                    " of them after the stop (" & rstr(to_us(2 * n_after * C_TICK) / 1000.0, 1) & " ms), about " &
                    integer'image(abs(tru(a) - n0(a)) - 2 * steps) & " counts dropped");
            end loop;
         end loop;
      end procedure part_rate_sat;

      --------------------------------------------------------------------------------------------
      -- A count that becomes effective in the clock cycle of a step: the tick grid is learned
      -- from a saturated movement; then, with one count waiting in the backlog, a second count
      -- in the same direction is placed around the predicted cycle of a step (17 positions, one
      -- clock period apart). Both counts must reach the output.
      -- A count that becomes effective in the clock cycle of a step: the tick grid is learned
      -- from a saturated movement; then, with one count waiting in the backlog, a second count
      -- in the same direction is placed around the predicted cycle of a step (17 positions, one
      -- clock period apart). Both counts must reach the output, which then moves by exactly one
      -- unit. Each sweep runs at both parities of the position, because a lost count is visible
      -- only at one of them.
      procedure part_rate_tick is
         variable te   : time;
         variable tk   : time;
         variable tp   : time;
         variable p0   : integer;
         variable dir  : integer;
      begin
         wait for 10 us;
         for k in 1 to 60 loop
            step_stim(0, 1);
            wait for 50 us;
         end loop;
         wait for real(G_BACKLOG + 10) * C_TICK;
         te := last_chg(0);                               -- a rising edge with a step
         for a in 0 to 1 loop
            for parity in 0 to 1 loop
               if pexp(a) mod 2 /= parity then
                  step_stim(a, 1);
                  wait for 2 * C_TICK + C_LAT;
               end if;
               for delta in -8 to 8 loop
                  dir := 1 - 2 * ((delta + 8) mod 2);
                  wait for 3 * C_TICK;
                  p0 := pos(a);
                  tk := te + ((now - te) / C_TICK + 2) * C_TICK;   -- a future step cycle
                  wait for tk - C_TICK / 2 - now;
                  step_stim(a, dir);                               -- first count: waits in the backlog
                  -- second count: becomes effective at tk for delta = 0 (stage 1 samples it C_FILTER + 3
                  -- cycles earlier)
                  tp := tk - (C_FILTER + 3) * C_PERIOD - C_HALF + delta * C_PERIOD;
                  wait for tp - now;
                  step_stim(a, dir);
                  wait for 3 * C_TICK;
                  if pos(a) /= p0 + dir then
                     err("axis " & integer'image(a) & ", parity " & integer'image(parity) & ", offset " &
                         integer'image(delta) & ": two counts moved the output by " & integer'image(pos(a) - p0) &
                         " units");
                  end if;
               end loop;
            end loop;
         end loop;
         note("a count in the clock cycle of a step (17 offsets per axis and parity): both took effect");
      end procedure part_rate_tick;

      --------------------------------------------------------------------------------------------
      procedure part_driver is
      begin
         chat   <= true;
         fol_d  <= 2 * C_TICK + C_LAT;
         wait for 10 us;
         -- up to the rate limit, both directions
         for a in 0 to 1 loop
            rand_prof(a, 14, 20 ms, 90 ms, 20.0, 2400.0, 0, 0.15);
         end loop;
         drv_mode <= 0;
         fol_on   <= true;
         drv_on   <= true;
         run_prof;
         drv_on   <= false;
         fol_on   <= false;
         wait for 2 * C_TICK + C_LAT;
         expect_exact("driver, up to the limit");
         note("driver, frame " & rstr(real(G_FRAME_NS) / 1.0e6, 3) & " ms +-1 ms, up to 2400 counts per second, both " &
              "directions: in every call the sum of the results was floor(n / 2) of a true position n of the last " &
              rstr(to_us(2 * C_TICK + C_LAT), 0) & " us, and exactly the movement of the output in units");
         -- above the rate limit: X to the right / Y down, then the reverse
         for dir in 0 to 1 loop
            for a in 0 to 1 loop
               rand_prof(a, 10, 10 ms, 60 ms, 2500.0, 20000.0, (1 - 2 * dir) * (1 - 2 * a), 0.15);
            end loop;
            drv_mode <= 1 - 2 * dir;
            drv_on   <= true;
            run_prof;
            wait for real(G_BACKLOG + 10) * C_TICK;
            drv_on   <= false;
            wait for 1 us;
            note("driver above the rate limit (2500 to 20000 counts per second), X " & integer'image(1 - 2 * dir) &
                 ": no movement against the mouse, the sum of the results exactly the movement of the output");
         end loop;
      end procedure part_driver;

      --------------------------------------------------------------------------------------------
      procedure part_enable is
         variable p0 : integer_vector(0 to 1);
         variable s  : std_logic_vector(3 downto 0);
         variable dt : time;
      begin
         -- disabled from the start: nothing counts, no button
         enable <= '0';
         meas_x <= x"0C";
         meas_y <= x"0C";
         chat   <= true;
         wait for 10 us;
         const_prof(0, 30 ms, 2000.0);
         const_prof(1, 30 ms, -3000.0);
         run_prof;
         meas_x <= x"FF";
         meas_y <= x"FF";
         wait for 3 * C_TICK + C_LAT + 2 * C_CONFIRM * C_TICK;
         if nchg /= (0, 0) or bchg /= (0, 0) then
            err("disabled: " & integer'image(nchg(0)) & " / " & integer'image(nchg(1)) & " output changes, " &
                integer'image(bchg(0)) & " / " & integer'image(bchg(1)) & " button changes");
         end if;
         note("disabled: " & integer'image(abs(tru(0))) & " / " & integer'image(abs(tru(1))) &
              " counts of the mouse, no output change, no button");
         -- enabling in each of the 16 line states
         chat <= false;
         lines_from_stim;
         for st in 0 to 15 loop
            enable <= '0';
            s := std_logic_vector(to_unsigned((st * 7) mod 16, 4));
            lvl_stim <= s;
            wait for C_LAT;
            p0 := pos;
            enable <= '1';
            wait for 3 * C_TICK + C_LAT;
            if pos /= p0 then
               err("enabling in line state " & to_string(s) & " counted " & integer'image(pos(0) - p0(0)) & " / " &
                   integer'image(pos(1) - p0(1)) & " units");
            end if;
            -- a count of one would be invisible at one parity: walk two counts up and down
            for a in 0 to 1 loop
               expect_step(a, 1);
               expect_step(a, 1);
               expect_step(a, -1);
               expect_step(a, -1);
            end loop;
         end loop;
         note("enabling in each of the 16 line states: no count (the POT values were exact during a walk of two " &
              "counts up and down after each)");
         -- disabling empties the backlog and keeps the position
         enable   <= '0';
         lvl_stim <= "1111";
         wait for C_LAT;
         enable   <= '1';
         wait for 2 * C_PERIOD;
         for k in 1 to 300 loop                              -- 300 counts in 15 ms: backlog full
            step_stim(0, 1);
            step_stim(1, -1);
            wait for 50 us;
         end loop;
         wait for 2 * C_TICK;
         enable <= '0';
         wait for 2 * C_PERIOD;
         p0 := pos;
         wait for 10 ms;
         enable <= '1';
         wait for real(G_BACKLOG + 10) * C_TICK;
         if pos /= p0 then
            err("the backlog survived enable_i = '0': the output moved by " & integer'image(pos(0) - p0(0)) & " / " &
                integer'image(pos(1) - p0(1)));
         end if;
         note("disabling with a full backlog: the position stays, nothing follows after enabling");
         -- disabling during a movement: the counts while disabled are lost, the others count
         for k in 1 to 40 loop
            step_stim(0, 1);
            step_stim(1, 1);
            wait for 1 ms;
            if k = 10 then
               p0 := pos;
               enable <= '0';
            elsif k = 30 then
               enable <= '1';
            end if;
         end loop;
         wait for 2 * C_TICK + C_LAT;
         if pos(0) - p0(0) /= 5 or pos(1) - p0(1) /= 5 then
            err("20 of 30 counts disabled, the output moved by " & integer'image(pos(0) - p0(0)) & " / " &
                integer'image(pos(1) - p0(1)) & " units instead of 5");
         end if;
         note("disabled during a movement: exactly the counts while enabled reached the output");
         -- buttons: released at once by enable_i = '0', the flag is cleared
         meas_x <= x"0C";
         meas_y <= x"0C";
         wait for 2 * C_TICK;
         meas_x <= x"FF";
         meas_y <= x"FF";
         wait_btn(0, '0', (C_CONFIRM + 2) * C_TICK, dt);
         wait_btn(1, '0', (C_CONFIRM + 2) * C_TICK, dt);
         if rbtn_n /= '0' or mbtn_n /= '0' then
            err("buttons not pressed");
         end if;
         enable <= '0';
         wait for 2 * C_PERIOD;
         if rbtn_n /= '1' or mbtn_n /= '1' then
            err("buttons not released one clock cycle after enable_i = '0'");
         end if;
         enable <= '1';
         wait for 3 * C_CONFIRM * C_TICK;
         if rbtn_n /= '1' or mbtn_n /= '1' then
            err("buttons pressed again after enable_i = '1' without a value below 128");
         end if;
         note("enable_i = '0' releases the buttons within one clock cycle and clears the flags");
      end procedure part_enable;

      --------------------------------------------------------------------------------------------
      procedure part_times is
         variable steps : integer;
         variable span  : time;
         variable dt    : time;
         variable lo    : time;
         variable hi    : time;
      begin
         wait for 10 us;
         if G_FREQ = 31_527_778 and G_FILTER_NS = 2000 and G_STEP_US = 400 and G_CONFIRM_US = 4000 and
            G_STUCK_MS = 30000 then
            if C_FILTER /= 63 or C_STEP /= 12_610 or C_CONFIRM /= 10 or C_STUCK /= 75_000 then
               err("derived numbers of the bench are not those of the specification");
            end if;
         end if;
         -- step time: a saturated movement steps once per tick
         reset_mon;
         for k in 1 to 400 loop
            step_stim(0, 1);
            wait for 50 us;
         end loop;
         wait for real(G_BACKLOG + 10) * C_TICK;
         steps := nchg(0);
         span  := last_chg(0) - first_chg(0);
         if span /= (steps - 1) * 2 * C_TICK then
            err("step time: " & integer'image(steps) & " unit changes within " & rstr(to_us(span)) & " us");
         end if;
         note("step time: " & integer'image(steps) & " unit changes exactly 2 x " & integer'image(C_STEP) &
              " clock periods apart: one count per " & rstr(to_us(C_TICK), 2) & " us at " & integer'image(G_CLK_HZ) & " Hz");
         -- confirmation time of both buttons
         lo := C_CONFIRM * C_TICK;
         hi := (C_CONFIRM + 1) * C_TICK + 2 * C_PERIOD;
         for k in 1 to 6 loop
            meas_x <= x"0C";
            meas_y <= x"0C";
            rand_real(r, 0.0, 1.0, x);
            wait for 1 ms + x * C_TICK;
            meas_x <= x"FF";
            meas_y <= x"FF";
            wait_btn(0, '0', 2 * hi, dt);
            if dt < lo or dt > hi then
               err("confirmation of a press: " & rstr(to_us(dt)) & " us");
            end if;
            wait for 1 ms + x * C_TICK;
            meas_x <= x"0C";
            meas_y <= x"0C";
            wait_btn(1, '1', 2 * hi, dt);
            if dt < lo - 2 * C_PERIOD or dt > hi then
               err("confirmation of a release: " & rstr(to_us(dt)) & " us");
            end if;
         end loop;
         note("confirmation: " & integer'image(C_CONFIRM) & " ticks, a change is reported " & rstr(to_us(lo) / 1000.0) &
              " to " & rstr(to_us(hi) / 1000.0) & " ms after it began");
      end procedure part_times;

      --------------------------------------------------------------------------------------------
      -- the scenarios of SPEC.md section 4.5 for button b; the other button keeps a constant
      -- value (released with pull-up for b = 0, no pull-up for b = 1) and must not change
      procedure part_buttons_one(b : natural) is
         variable o      : natural := 1 - b;
         variable c_o    : natural;
         variable dt     : time;
         variable lo     : time;
         variable hi     : time;
         variable v      : integer;
         variable q      : real;
         variable tconf  : time;
      begin
         lo    := C_CONFIRM * C_TICK;
         hi    := (C_CONFIRM + 1) * C_TICK + 2 * C_PERIOD;
         tconf := C_CONFIRM * C_TICK;
         enable <= '0';
         if b = 0 then
            set_meas(o, 12);
         else
            set_meas(o, 255);
         end if;
         set_meas(b, 255);
         wait for 2 * C_PERIOD;
         enable <= '1';
         wait for 2 * C_TICK;
         c_o   := bchg(o);
         c0(b) := bchg(b);

         -- 1. no pull-up: 255, sometimes a single sample of 192 .. 254, for three stuck times
         t1 := now + 3 * C_STUCK * C_TICK;
         while now < t1 loop
            rand_real(r, 20.0, 80.0, q);
            wait for q * 1 us;
            rand_int(r, 192, 254, v);
            set_meas(b, v);
            wait for 10 us;
            set_meas(b, 255);
         end loop;
         if btn(b) /= '1' or bchg(b) /= c0(b) then
            err("button " & integer'image(b) & ": reported without a pull-up (" & integer'image(bchg(b) - c0(b)) &
                " changes)");
         end if;
         note("button " & integer'image(b) & " without pull-up, " & rstr(to_us(3 * C_STUCK * C_TICK) / 1000.0, 1) &
              " ms of 255 with single samples of 192 .. 254: never reported");

         -- 2. pull-up: 12 released, 255 pressed, after the confirmation time
         for k in 1 to 4 loop
            rand_int(r, 11, 16, v);
            set_meas(b, v);
            rand_real(r, 0.0, 1.0, q);
            wait for 3 * tconf + q * C_TICK;
            if btn(b) /= '1' then
               err("button " & integer'image(b) & ": pressed while the value is " & integer'image(v));
            end if;
            set_meas(b, 255);
            wait_btn(b, '0', 2 * hi, dt);
            if dt < lo or dt > hi then
               err("button " & integer'image(b) & ": press reported after " & rstr(to_us(dt)) & " us");
            end if;
            wait for 2 * tconf + q * C_TICK;
            rand_int(r, 11, 16, v);
            set_meas(b, v);
            wait_btn(b, '1', 2 * hi, dt);
            if dt < lo or dt > hi then
               err("button " & integer'image(b) & ": release reported after " & rstr(to_us(dt)) & " us");
            end if;
         end loop;
         note("button " & integer'image(b) & " with pull-up: 11 .. 16 released, 255 pressed, reported " & rstr(to_us(lo)) &
              " to " & rstr(to_us(hi)) & " us after the change");

         -- 3. values from 128 to 191 change nothing, and they interrupt a confirmation
         for pressed in 0 to 1 loop
            if pressed = 1 then
               set_meas(b, 255);
               wait_btn(b, '0', 2 * hi, dt);
            end if;
            c0(b) := bchg(b);
            t1 := now + 3 * tconf;
            while now < t1 loop
               rand_int(r, 128, 191, v);
               set_meas(b, v);
               wait for 10 us;
            end loop;
            for k in 1 to 3 loop
               if pressed = 1 then
                  set_meas(b, 12);
               else
                  set_meas(b, 255);
               end if;
               wait for 0.6 * tconf;
               rand_int(r, 128, 191, v);
               set_meas(b, v);
               wait for 10 us;
            end loop;
            if bchg(b) /= c0(b) then
               err("button " & integer'image(b) & ": values of 128 .. 191 changed the state");
            end if;
            if pressed = 1 then
               set_meas(b, 12);
               wait_btn(b, '1', 2 * hi, dt);
            end if;
         end loop;
         note("button " & integer'image(b) & ": values of 128 .. 191 changed nothing, released or pressed, and " &
              "interrupted a confirmation");

         -- 4. changes shorter than the confirmation time are ignored
         c0(b) := bchg(b);
         for pressed in 0 to 1 loop
            if pressed = 1 then
               set_meas(b, 255);
               wait_btn(b, '0', 2 * hi, dt);
               c0(b) := bchg(b);
            end if;
            for k in 1 to 12 loop
               rand_real(r, 0.3, 0.98, q);
               if k > 6 then
                  q := 0.92 + 0.06 * real(k - 7) / 5.0;
               end if;
               if pressed = 1 then
                  set_meas(b, 12);
               else
                  set_meas(b, 255);
               end if;
               wait for q * tconf;
               if pressed = 1 then
                  set_meas(b, 255);
               else
                  set_meas(b, 12);
               end if;
               wait for 30 us;
            end loop;
            if bchg(b) /= c0(b) then
               err("button " & integer'image(b) & ": a change shorter than the confirmation time was taken over");
            end if;
            if pressed = 1 then
               set_meas(b, 12);
               wait_btn(b, '1', 2 * hi, dt);
            end if;
         end loop;
         note("button " & integer'image(b) & ": 24 changes of 0.30 to 0.98 confirmation times were ignored");

         -- 5. a mouse with pull-ups exchanged for one without: released after the stuck time
         set_meas(b, 12);
         wait for 2 * tconf;
         set_meas(b, 255);
         wait_btn(b, '0', 2 * hi, dt);
         wait_btn(b, '1', C_STUCK * C_TICK + 4 * C_TICK, dt);
         dt := dt + C_PERIOD;                   -- wait_btn of the press returned one period after it
         if btn(b) /= '1' then
            err("button " & integer'image(b) & ": stuck press not released within " & rstr(to_us(dt)) & " us");
         elsif dt /= C_STUCK * C_TICK then
            err("button " & integer'image(b) & ": stuck press released after " & rstr(to_us(dt)) & " us, expected " &
                rstr(to_us(C_STUCK * C_TICK)) & " us");
         end if;
         c0(b) := bchg(b);
         wait for 3 * C_STUCK * C_TICK;
         if bchg(b) /= c0(b) then
            err("button " & integer'image(b) & ": reported again without a value below 128");
         end if;
         set_meas(b, 100);
         wait for 10 us;
         set_meas(b, 255);
         wait_btn(b, '0', 2 * hi, dt);
         if dt < lo or dt > hi then
            err("button " & integer'image(b) & ": after one value below 128 the press came after " & rstr(to_us(dt)) & " us");
         end if;
         set_meas(b, 12);
         wait_btn(b, '1', 2 * hi, dt);
         note("button " & integer'image(b) & ": pull-up gone, the press is released after exactly " & integer'image(C_STUCK) &
              " ticks (" & rstr(to_us(C_STUCK * C_TICK)) & " us); reported again only after a value below 128");

         -- 6. enable_i = '0' releases the button and clears the flag
         set_meas(b, 255);
         wait_btn(b, '0', 2 * hi, dt);
         enable <= '0';
         wait for 2 * C_PERIOD;
         if btn(b) /= '1' then
            err("button " & integer'image(b) & ": not released by enable_i = '0'");
         end if;
         wait for 10 us;
         enable <= '1';
         wait for 3 * tconf;
         if btn(b) /= '1' then
            err("button " & integer'image(b) & ": pressed after enable_i = '1' without a value below 128");
         end if;
         set_meas(b, 12);
         wait for 2 * tconf;
         set_meas(b, 255);
         wait_btn(b, '0', 2 * hi, dt);
         if btn(b) /= '0' then
            err("button " & integer'image(b) & ": not pressed after the flag was set again");
         end if;
         set_meas(b, 12);
         wait_btn(b, '1', 2 * hi, dt);
         note("button " & integer'image(b) & ": enable_i = '0' released it and cleared the flag");

         -- the other button: unchanged except for its own enable toggles (b = 0: pull-up, released)
         if bchg(o) /= c_o then
            err("button " & integer'image(o) & " changed while only button " & integer'image(b) & " was moved");
         end if;
      end procedure part_buttons_one;

      procedure part_buttons is
      begin
         wait for 10 us;
         part_buttons_one(0);
         part_buttons_one(1);
         note("both buttons independent of each other");
      end procedure part_buttons;

      --------------------------------------------------------------------------------------------
      procedure part_defaults is
         variable steps : integer;
         variable span  : time;
         variable dt    : time;
      begin
         wait for 100 us;
         reset_mon;
         for k in 1 to 200 loop
            step_stim(0, 1);
            wait for 50 us;
         end loop;
         wait for 200 * C_TICK;
         steps := nchg(0);
         span  := last_chg(0) - first_chg(0);
         if span /= (steps - 1) * 800 us then
            err("default step time: " & integer'image(steps) & " steps within " & rstr(to_us(span)) & " us");
         end if;
         meas_x <= x"0C";
         wait for 10 ms;
         meas_x <= x"FF";
         wait_btn(0, '0', 10 ms, dt);
         if dt < 4.0 ms or dt > 4.4 ms + 2 * C_PERIOD then
            err("default confirmation time: " & rstr(to_us(dt)) & " us");
         end if;
         note("defaults at " & integer'image(G_CLK_HZ) & " Hz: step 400 us, a press is reported " & rstr(to_us(dt) / 1000.0) &
              " ms after it began (4.0 .. 4.4 ms)");
         wait_btn(0, '1', 31 sec, dt);
         dt := dt + C_PERIOD;                   -- wait_btn of the press returned one period after it
         if dt /= 30 sec then
            err("default stuck time: " & rstr(to_us(dt) / 1.0e6, 6) & " s");
         end if;
         note("defaults: a press without interruption is released after " & rstr(to_us(dt) / 1.0e6, 6) & " s");
      end procedure part_defaults;

      variable nerr : natural;
   begin
      note("part " & G_PART & ", clock " & integer'image(G_CLK_HZ) & " Hz, G_CLK_FREQ " & integer'image(G_FREQ) &
           ", filter " & integer'image(C_FILTER) & " cycles, tick " & integer'image(C_STEP) & " cycles (" &
           rstr(to_us(C_TICK), 2) & " us), confirm " & integer'image(C_CONFIRM) & " ticks, stuck " &
           integer'image(C_STUCK) & " ticks, backlog " & integer'image(G_BACKLOG));
      wait for 1 ns;
      if G_PART = "dir" then
         part_dir;
      elsif G_PART = "double" then
         part_double;
      elsif G_PART = "pulse" then
         part_pulse;
      elsif G_PART = "model" then
         part_model;
      elsif G_PART = "rate_follow" then
         part_rate_follow;
      elsif G_PART = "rate_sat" then
         part_rate_sat;
      elsif G_PART = "rate_tick" then
         part_rate_tick;
      elsif G_PART = "driver" then
         part_driver;
      elsif G_PART = "enable" then
         part_enable;
      elsif G_PART = "times" then
         part_times;
      elsif G_PART = "buttons" then
         part_buttons;
      elsif G_PART = "defaults" then
         part_defaults;
      else
         err("unknown part " & G_PART);
      end if;
      wait for 1 us;
      nerr := errcnt.value;
      if nerr = 0 then
         note("RESULT PASS");
      else
         note("RESULT FAIL " & integer'image(nerr) & " errors");
      end if;
      running <= false;
      finish;
   end process stim;

end architecture sim;
