----------------------------------------------------------------------------------------------------
-- Amiga mouse bench (GitHub issue #190), part 2: M2M/vhdl/debouncer.vhd, the conditioning of the
-- two joystick ports
--
-- DUT: debouncer (with the two Amiga mice). Beside it:
-- * debouncer_ref: the entity of commit 6845596 (before the Amiga mice), renamed by run.sh;
--   it gets the same ten lines, port switcher, on/off inputs and reset
-- * two instances of amiga_mouse with the same generics as inside the DUT, fed with the raw
--   lines and the true measured values of each socket
--
-- G_PART = "identity": amiga_i = "00" and random stimulus on all inputs: the ten joystick outputs
-- are identical to those of debouncer_ref, the four paddle outputs equal the paddle inputs.
-- G_PART = "modes": all 32 combinations of flip_joys_i, amiga_i(0), amiga_i(1), joy_1_on and
-- joy_2_on, switched while everything runs: for each C64 port, switched off: all five lines '1';
-- connected to a socket with an Amiga mouse: left and right '1', up the right button, down the
-- middle button (from the true measured values of that socket, which the DUT has to recover from
-- the switched and inverted paddle inputs), fire the debounced fire line, the paddle outputs the
-- inverted position of that mouse; connected to a socket in C64 mode: exactly debouncer_ref.
--
-- The outputs are compared 1 ps after every event of an input, of an output of the DUT, of an
-- output of debouncer_ref or of a reference mouse (the expected values derive from these).
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_amiga_mouse_pkg.all;

entity tb_amiga_ports is
   generic (
      G_PART : string   := "identity";
      G_SEED : positive := 1;
      G_STOP : boolean  := false
   );
end entity tb_amiga_ports;

architecture sim of tb_amiga_ports is

   constant C_CLK_HZ : positive := 31_527_778;
   constant C_HALF   : time     := 1 sec / (2 * C_CLK_HZ);
   constant C_PERIOD : time     := 2 * C_HALF;

   signal clk        : std_logic := '0';
   signal running    : boolean   := true;

   signal reset_n    : std_logic := '1';
   signal flip       : std_logic := '0';
   signal on1        : std_logic := '1';
   signal on2        : std_logic := '1';
   signal amiga      : std_logic_vector(1 downto 0) := "00";

   -- raw lines per socket: 0 up, 1 down, 2 left, 3 right, 4 fire
   type lines_t is array (0 to 1) of std_logic_vector(4 downto 0);
   signal ln         : lines_t := (others => "11111");

   -- true measured values per socket, and the paddle inputs as the core delivers them
   type pot2_t is array (0 to 1) of std_logic_vector(7 downto 0);
   signal tv_x       : pot2_t := (others => x"FF");
   signal tv_y       : pot2_t := (others => x"FF");
   signal pin_x      : pot2_t := (others => x"00");    -- C64 port 1 and 2: switched, inverted
   signal pin_y      : pot2_t := (others => x"00");

   -- outputs per C64 port: 0 up, 1 down, 2 left, 3 right, 4 fire
   signal dut_j      : lines_t;
   signal ref_j      : lines_t;
   signal dut_px     : pot2_t;
   signal dut_py     : pot2_t;

   -- reference mice per socket
   signal mr_x       : pot2_t;
   signal mr_y       : pot2_t;
   signal mr_right   : std_logic_vector(1 downto 0);
   signal mr_middle  : std_logic_vector(1 downto 0);

   shared variable errcnt : counter_pt;
   signal checks      : natural := 0;
   signal btn_changes : natural := 0;
   signal pos_changes : natural := 0;

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

   dut : entity work.debouncer
      generic map (
         CLK_FREQ           => C_CLK_HZ
      )
      port map (
         clk                => clk,
         reset_n            => reset_n,
         flip_joys_i        => flip,
         joy_1_on           => on1,
         joy_2_on           => on2,
         joy_1_up_n         => ln(0)(0),
         joy_1_down_n       => ln(0)(1),
         joy_1_left_n       => ln(0)(2),
         joy_1_right_n      => ln(0)(3),
         joy_1_fire_n       => ln(0)(4),
         dbnce_joy1_up_n    => dut_j(0)(0),
         dbnce_joy1_down_n  => dut_j(0)(1),
         dbnce_joy1_left_n  => dut_j(0)(2),
         dbnce_joy1_right_n => dut_j(0)(3),
         dbnce_joy1_fire_n  => dut_j(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => ln(1)(4),
         dbnce_joy2_up_n    => dut_j(1)(0),
         dbnce_joy2_down_n  => dut_j(1)(1),
         dbnce_joy2_left_n  => dut_j(1)(2),
         dbnce_joy2_right_n => dut_j(1)(3),
         dbnce_joy2_fire_n  => dut_j(1)(4),
         amiga_i            => amiga,
         pot1_x_i           => pin_x(0),
         pot1_y_i           => pin_y(0),
         pot2_x_i           => pin_x(1),
         pot2_y_i           => pin_y(1),
         pot1_x_o           => dut_px(0),
         pot1_y_o           => dut_py(0),
         pot2_x_o           => dut_px(1),
         pot2_y_o           => dut_py(1)
      );

   ref : entity work.debouncer_ref
      generic map (
         CLK_FREQ           => C_CLK_HZ
      )
      port map (
         clk                => clk,
         reset_n            => reset_n,
         flip_joys_i        => flip,
         joy_1_on           => on1,
         joy_2_on           => on2,
         joy_1_up_n         => ln(0)(0),
         joy_1_down_n       => ln(0)(1),
         joy_1_left_n       => ln(0)(2),
         joy_1_right_n      => ln(0)(3),
         joy_1_fire_n       => ln(0)(4),
         dbnce_joy1_up_n    => ref_j(0)(0),
         dbnce_joy1_down_n  => ref_j(0)(1),
         dbnce_joy1_left_n  => ref_j(0)(2),
         dbnce_joy1_right_n => ref_j(0)(3),
         dbnce_joy1_fire_n  => ref_j(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => ln(1)(4),
         dbnce_joy2_up_n    => ref_j(1)(0),
         dbnce_joy2_down_n  => ref_j(1)(1),
         dbnce_joy2_left_n  => ref_j(1)(2),
         dbnce_joy2_right_n => ref_j(1)(3),
         dbnce_joy2_fire_n  => ref_j(1)(4)
      );

   gen_mice : for s in 0 to 1 generate
      mouse : entity work.amiga_mouse
         generic map (
            G_CLK_FREQ     => C_CLK_HZ
         )
         port map (
            clk_i          => clk,
            enable_i       => amiga(s),
            up_n_i         => ln(s)(0),
            down_n_i       => ln(s)(1),
            left_n_i       => ln(s)(2),
            right_n_i      => ln(s)(3),
            meas_x_i       => tv_x(s),
            meas_y_i       => tv_y(s),
            pot_x_o        => mr_x(s),
            pot_y_o        => mr_y(s),
            right_btn_n_o  => mr_right(s),
            middle_btn_n_o => mr_middle(s)
         );
   end generate gen_mice;

   -- paddle inputs: C64 port p carries the values of the socket that is connected to it, inverted
   -- (the bench sets them together with flip in the same delta cycle)

   ---------------------------------------------------------------------------------------------
   checker : process
      variable s     : natural;
      variable ex_j  : std_logic_vector(4 downto 0);
      variable ex_px : std_logic_vector(7 downto 0);
      variable ex_py : std_logic_vector(7 downto 0);
      variable n     : natural := 0;
   begin
      wait on dut_j, ref_j, dut_px, dut_py, mr_x, mr_y, mr_right, mr_middle, flip, on1, on2, amiga, pin_x, pin_y,
              reset_n;
      wait for 1 ps;
      for p in 0 to 1 loop
         if flip = '0' then
            s := p;
         else
            s := 1 - p;
         end if;
         ex_px := pin_x(p);
         ex_py := pin_y(p);
         if amiga(s) = '1' then
            ex_px := not mr_x(s);
            ex_py := not mr_y(s);
         end if;
         if (p = 0 and on1 = '0') or (p = 1 and on2 = '0') then
            ex_j := "11111";
         elsif amiga(s) = '1' then
            ex_j := ref_j(p)(4) & "11" & mr_middle(s) & mr_right(s);
         else
            ex_j := ref_j(p);
         end if;
         if dut_j(p) /= ex_j then
            tb_error("C64 port " & integer'image(p + 1) & ": lines " & to_string(dut_j(p)) & ", expected " &
                     to_string(ex_j) & " (flip " & std_logic'image(flip) & ", amiga " & to_string(amiga) &
                     ", on " & std_logic'image(on1) & std_logic'image(on2) & ")");
         end if;
         if dut_px(p) /= ex_px or dut_py(p) /= ex_py then
            tb_error("C64 port " & integer'image(p + 1) & ": paddles " & to_hstring(dut_px(p)) & " / " &
                     to_hstring(dut_py(p)) & ", expected " & to_hstring(ex_px) & " / " & to_hstring(ex_py) &
                     " (flip " & std_logic'image(flip) & ", amiga " & to_string(amiga) & ")");
         end if;
      end loop;
      n := n + 1;
      checks <= n;
   end process checker;

   ---------------------------------------------------------------------------------------------
   -- Socket activity. Each socket: in Amiga mode quadrature on both pairs (about 3000 counts per
   -- second, changing directions), the left button on fire, the right and middle button as
   -- measured values (12 released, 255 pressed, sometimes a value of 128 .. 191); in C64 mode
   -- random joystick lines (mostly long enough for the 1 ms debouncer) and random paddle values.
   ---------------------------------------------------------------------------------------------
   gen_sockets : for s in 0 to 1 generate

      lines_proc : process
         variable r    : rng_t := rng_init(100 + 31 * G_SEED + s);
         variable q    : real;
         variable k    : integer;
         variable st   : integer_vector(0 to 1) := (0, 0);       -- quadrature state per axis
         variable dir  : integer_vector(0 to 1) := (1, -1);
         variable tf   : time := 0 fs;
         type seq2_t is array (0 to 3) of std_logic_vector(1 downto 0);
         -- (first, second) of X = (right, down) and of Y = (left, up), +1 sequences
         constant C_X  : seq2_t := ("11", "10", "00", "01");
         constant C_Y  : seq2_t := ("11", "01", "00", "10");
         variable v    : std_logic_vector(4 downto 0);
      begin
         wait for 1 us;
         loop
            if amiga(s) = '1' then
               rand_real(r, 200.0, 500.0, q);
               wait for q * 1 us;
               rand_int(r, 0, 1, k);
               rand(r, q);
               if q < 0.01 then
                  dir(k) := -dir(k);
               end if;
               st(k) := (st(k) + dir(k)) mod 4;
               v := ln(s);
               if k = 0 then
                  v(3) := C_X(st(0))(1);
                  v(1) := C_X(st(0))(0);
               else
                  v(2) := C_Y(st(1))(1);
                  v(0) := C_Y(st(1))(0);
               end if;
               if now > tf then
                  v(4) := not v(4);
                  rand_real(r, 1.5, 4.0, q);
                  tf := now + q * 1 ms;
               end if;
               ln(s) <= v;
            else
               rand(r, q);
               if q < 0.7 then
                  rand_real(r, 1.2, 4.0, q);
               else
                  rand_real(r, 0.01, 0.9, q);
               end if;
               wait for q * 1 ms;
               rand_int(r, 0, 4, k);
               v := ln(s);
               v(k) := not v(k);
               ln(s) <= v;
               -- keep the quadrature state in line with the lines for a later switch to Amiga mode
               st(0) := 0;
               st(1) := 0;
               for m in 0 to 3 loop
                  if C_X(m) = (v(3) & v(1)) then
                     st(0) := m;
                  end if;
                  if C_Y(m) = (v(2) & v(0)) then
                     st(1) := m;
                  end if;
               end loop;
            end if;
         end loop;
      end process lines_proc;

      meas_proc : process
         variable r  : rng_t := rng_init(200 + 37 * G_SEED + s);
         variable q  : real;
         variable v  : integer;
         variable sx : boolean := false;     -- pressed
         variable sy : boolean := false;
         variable tx : time := 0 fs;         -- next change of the right / middle button
         variable ty : time := 0 fs;
      begin
         wait for 3 us;
         loop
            rand_real(r, 0.3, 0.7, q);
            wait for q * 1 ms;
            if amiga(s) = '1' then
               -- right button every 4.5 (socket 0) / 6.5 ms (socket 1), middle every 5.5 / 7.5 ms
               if now >= tx then
                  sx := not sx;
                  tx := now + (4.5 + 2.0 * real(s)) * 1 ms;
               end if;
               if now >= ty then
                  sy := not sy;
                  ty := now + (5.5 + 2.0 * real(s)) * 1 ms;
               end if;
               rand(r, q);
               if q < 0.05 then
                  rand_int(r, 128, 191, v);
                  tv_x(s) <= std_logic_vector(to_unsigned(v, 8));
               elsif sx then
                  tv_x(s) <= x"FF";
               else
                  tv_x(s) <= x"0C";
               end if;
               if sy then
                  tv_y(s) <= x"FF";
               else
                  rand_int(r, 11, 16, v);
                  tv_y(s) <= std_logic_vector(to_unsigned(v, 8));
               end if;
            else
               rand_int(r, 0, 255, v);
               tv_x(s) <= std_logic_vector(to_unsigned(v, 8));
               rand_int(r, 0, 255, v);
               tv_y(s) <= std_logic_vector(to_unsigned(v, 8));
            end if;
         end loop;
      end process meas_proc;

   end generate gen_sockets;

   -- the paddle inputs follow the true values and the port switcher in the same delta cycle as the
   -- bench changes them (the measurement path of the core: switched to C64 ports, inverted)
   pin_x(0) <= not tv_x(0) when flip = '0' else not tv_x(1);
   pin_y(0) <= not tv_y(0) when flip = '0' else not tv_y(1);
   pin_x(1) <= not tv_x(1) when flip = '0' else not tv_x(0);
   pin_y(1) <= not tv_y(1) when flip = '0' else not tv_y(0);

   -- activity of the reference mice (the bench has to exercise the buttons and the position)
   mouse_act : process (mr_right, mr_middle, mr_x, mr_y)
      variable nb : natural := 0;
      variable np : natural := 0;
   begin
      if mr_right'event or mr_middle'event then
         nb := nb + 1;
      end if;
      if mr_x'event or mr_y'event then
         np := np + 1;
      end if;
      btn_changes <= nb;
      pos_changes <= np;
   end process mouse_act;

   ---------------------------------------------------------------------------------------------
   stim : process
      variable r     : rng_t := rng_init(G_SEED);
      variable q     : real;
      variable c     : std_logic_vector(4 downto 0);
      variable tnext : time;
      variable nerr  : natural;
      variable nsw   : natural := 0;
      variable nrst  : natural := 0;
   begin
      report "TB: part " & G_PART severity note;
      if G_PART = "identity" then
         -- amiga_i stays "00"; random port switcher, on/off and reset
         while now < 300 ms loop
            rand_real(r, 1.0, 15.0, q);
            wait for q * 1 ms + q * 1 ns;
            rand(r, q);
            if q < 0.45 then
               flip <= not flip;
               nsw := nsw + 1;
            elsif q < 0.7 then
               on1 <= not on1;
            elsif q < 0.95 then
               on2 <= not on2;
            else
               reset_n <= '0';
               rand_real(r, 0.1, 50.0, q);
               wait for q * 1 us;
               reset_n <= '1';
               nrst := nrst + 1;
            end if;
         end loop;
         report "TB: 300 ms of random lines, " & integer'image(nsw) & " port switches, on/off changes, " &
                integer'image(nrst) & " resets: the ten joystick outputs were identical to the entity before the " &
                "change and the paddle outputs equal to the paddle inputs at every event" severity note;
      elsif G_PART = "modes" then
         for k in 0 to 31 loop
            -- a random order of the combinations: k * 13 mod 32 visits each one once
            c := std_logic_vector(to_unsigned((k * 13 + 5) mod 32, 5));
            flip    <= c(0);
            amiga   <= c(2 downto 1);
            on1     <= c(3);
            on2     <= c(4);
            rand_real(r, 12.0, 16.0, q);
            wait for q * 1 ms + q * 1 ns;
         end loop;
         -- the switcher and the settings also change in the middle of activity
         for k in 1 to 30 loop
            rand_real(r, 0.0, 32.0, q);
            c := std_logic_vector(to_unsigned(integer(q) mod 32, 5));
            flip  <= c(0);
            amiga <= c(2 downto 1);
            on1   <= c(3);
            on2   <= c(4);
            rand_real(r, 0.5, 5.0, q);
            wait for q * 1 ms + q * 1 ns;
         end loop;
         report "TB: all 32 combinations of flip_joys_i, amiga_i(0), amiga_i(1), joy_1_on, joy_2_on for 12 to 16 ms " &
                "each, then 30 random switches: every C64 port showed what the socket connected to it delivers" severity note;
      else
         tb_error("unknown part " & G_PART);
      end if;
      wait for 1 us;
      report "TB: " & integer'image(checks) & " comparisons; the reference mice changed their buttons " &
             integer'image(btn_changes) & " times and their positions " & integer'image(pos_changes) & " times" severity note;
      if G_PART = "modes" and (btn_changes < 20 or pos_changes < 100) then
         tb_error("the bench did not exercise the Amiga mice");
      end if;
      nerr := errcnt.value;
      if nerr = 0 then
         report "TB: RESULT PASS" severity note;
      else
         report "TB: RESULT FAIL " & integer'image(nerr) & " errors" severity note;
      end if;
      running <= false;
      finish;
   end process stim;

end architecture sim;
