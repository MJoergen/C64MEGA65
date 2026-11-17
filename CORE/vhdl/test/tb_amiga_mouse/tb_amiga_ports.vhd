----------------------------------------------------------------------------------------------------
-- Amiga mouse bench (GitHub issue #190), part 2: M2M/vhdl/debouncer.vhd, the conditioning of the
-- two joystick ports, with the right click with the MEGA key (SPEC.md section 5.1)
--
-- DUT: debouncer (with the two Amiga mice and the right click). Beside it:
-- * debouncer_ref: the entity of commit 6845596 (before the Amiga mice), renamed by run.sh;
--   it gets the same ten lines, port switcher, on/off inputs and reset
-- * debouncer_prev: the entity of commit 756677a (before the right click with the MEGA key),
--   renamed by run.sh; it gets the same inputs as the DUT except the two new ones
-- * sockets: a second debouncer_ref with the port switcher at '0' and both ports on, so that its
--   outputs are the debounced lines of each socket (f of section 5.1 is its fire line)
-- * two instances of amiga_mouse with the same generics as inside the DUT, fed with the raw
--   lines and the true measured values of each socket
--
-- Checks, 1 ps after every event of an input, of an output of the DUT or of a reference, and 1 ps
-- after every clock edge:
-- * while amiga_i is "00": the ten joystick outputs are those of debouncer_ref and the four paddle
--   outputs are the paddle inputs, whatever amiga_rclick_i and mega_key_n_i do
-- * while amiga_rclick_i is "00": all fourteen outputs are those of debouncer_prev
-- * G_MODEL: every output against a model written from SPEC.md sections 5 and 5.1: a flip-flop
--   mq per socket that takes "Amiga and switch on and key held" at every rising clock edge at
--   which f is '1', r = mq and Amiga and switch; for a C64 port connected to a socket in Amiga
--   mode: fire = f or r, up = right button of the reference mouse and (f or not r), down = middle
--   button, left and right '1', paddles = the inverted position of the reference mouse; to a
--   socket in C64 mode: debouncer_ref; switched off: all five lines '1'
-- * always, the two properties of section 5.1 on every C64 port that is on: while the press of
--   the connected socket in Amiga mode is a right click, the fire line is never '0'; while it is
--   a left click, the up line is '0' only if the reference mouse reports its right button. A
--   press is classified when f falls, from the key and the settings at that rising clock edge,
--   and is a right click while that classification holds and the socket is still in Amiga mode
--   with the switch on.
--
-- G_PART = "identity": amiga_i = "00", random activity on all inputs, also on the two new ones.
-- G_PART = "modes": all 32 combinations of flip_joys_i, amiga_i(0), amiga_i(1), joy_1_on and
-- joy_2_on, switched while everything runs; amiga_rclick_i = "00" while mega_key_n_i toggles.
-- G_PART = "rule": G_EPISODES episodes with random settings, of four kinds in turn: a press of
-- socket 0, a press of socket 1, presses of both sockets a few clock cycles apart (both orders of
-- pressing and of releasing), and one socket held for a whole press of the other (each socket in
-- turn); key changes and changes of the settings in the clock cycles around every edge of f (from
-- three before to two after, by rotation), random key and settings changes while buttons are held,
-- the port switcher, the on/off switches, rare resets; the right buttons of the reference mice
-- toggle on their own. The run fails if the observed coverage stays below C_MIN_COV.
-- G_PART = "directed": the cases of SPEC.md section 5.1 one by one, each with explicit checks.
--
-- G_MODEL and G_IDENT switch the comparisons off, so that a mutant can show what the remaining checks
-- catch. G_FREQ is CLK_FREQ of all instances; with a tenth of the clock frequency the debouncer and
-- the mice count a tenth of the clock cycles, and the bench scales all its times with it (C_MS).
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
      G_PART     : string   := "identity";
      G_SEED     : positive := 1;
      G_STOP     : boolean  := false;
      G_FREQ     : positive := 31_527_778;   -- CLK_FREQ of the DUT and of the references
      G_MODEL    : boolean  := true;         -- compare every output with the model
      G_IDENT    : boolean  := true;         -- compare with debouncer_ref and debouncer_prev
      G_EPISODES : positive := 200           -- part "rule": number of presses
   );
end entity tb_amiga_ports;

architecture sim of tb_amiga_ports is

   constant C_CLK_HZ : positive := 31_527_778;
   constant C_HALF   : time     := 1 sec / (2 * C_CLK_HZ);
   constant C_PERIOD : time     := 2 * C_HALF;
   constant C_SCALE  : real     := real(G_FREQ) / real(C_CLK_HZ);
   constant C_MS     : time     := 1 ms * C_SCALE;          -- a millisecond of the instances
   constant C_US     : time     := 1 us * C_SCALE;
   constant C_DB     : natural  := G_FREQ / 1000;            -- the counter limit of debounce.vhd (1 ms)
   -- f changes at the rising edge C_DB + 3 after a change of the raw line at a falling edge
   constant C_DB_LAT : time     := C_HALF + (C_DB + 2) * C_PERIOD;

   constant C_OWN_FIRE : boolean := G_PART = "rule" or G_PART = "directed";  -- stim drives the fire lines
   -- part rule: each of the clock cycles c(-1), c(0) and c(1) around the edges of f needs this many
   -- changes of the key and of the settings at a fall and at a rise of f, per socket; and as many right
   -- clicks, left clicks, presses of each socket first, releases of each socket first and long presses
   constant C_MIN_COV  : natural := 4;
   constant C_BG       : boolean := G_PART = "identity" or G_PART = "modes"; -- random key in the background

   signal clk        : std_logic := '0';
   signal running    : boolean   := true;

   signal reset_n    : std_logic := '1';
   signal flip       : std_logic := '0';
   signal on1        : std_logic := '1';
   signal on2        : std_logic := '1';
   signal amiga      : std_logic_vector(1 downto 0) := "00";
   signal rclick     : std_logic_vector(1 downto 0);       -- amiga_rclick_i
   signal key        : std_logic;                          -- mega_key_n_i
   signal rclick_bg  : std_logic_vector(1 downto 0) := "00";
   signal rclick_st  : std_logic_vector(1 downto 0) := "00";
   signal key_bg     : std_logic := '1';
   signal key_st     : std_logic := '1';

   -- raw lines per socket: 0 up, 1 down, 2 left, 3 right, 4 fire
   type lines_t is array (0 to 1) of std_logic_vector(4 downto 0);
   signal ln         : lines_t := (others => "11111");
   signal rfire      : std_logic_vector(1 downto 0) := "11";  -- raw fire lines of the parts rule and directed
   signal fire_in    : std_logic_vector(1 downto 0);          -- raw fire lines of all instances

   -- true measured values per socket, and the paddle inputs as the core delivers them
   type pot2_t is array (0 to 1) of std_logic_vector(7 downto 0);
   signal tv_x       : pot2_t := (others => x"FF");
   signal tv_y       : pot2_t := (others => x"FF");
   signal pin_x      : pot2_t := (others => x"00");    -- C64 port 1 and 2: switched, inverted
   signal pin_y      : pot2_t := (others => x"00");
   signal want_right : std_logic_vector(1 downto 0) := "00";  -- part directed: '1' presses the right button

   -- outputs per C64 port: 0 up, 1 down, 2 left, 3 right, 4 fire
   signal dut_j      : lines_t;
   signal ref_j      : lines_t;
   signal prev_j     : lines_t;
   signal dut_px     : pot2_t;
   signal dut_py     : pot2_t;
   signal prev_px    : pot2_t;
   signal prev_py    : pot2_t;
   -- debounced lines per socket
   signal sk         : lines_t;

   -- reference mice per socket
   signal mr_x       : pot2_t;
   signal mr_y       : pot2_t;
   signal mr_right   : std_logic_vector(1 downto 0);
   signal mr_middle  : std_logic_vector(1 downto 0);

   -- the model of section 5.1 and the classification of the presses for the two properties
   signal mq         : boolean_vector(0 to 1) := (false, false);
   signal e_rc       : boolean_vector(0 to 1) := (false, false);  -- at the last rising edge
   signal pr_rc      : boolean_vector(0 to 1) := (false, false);  -- the current press
   signal n_rc_press : integer_vector(0 to 1) := (0, 0);
   signal n_lc_press : integer_vector(0 to 1) := (0, 0);

   -- coverage of the changes around the edges of f, per socket: offset -3 .. 3 in clock cycles;
   -- offset 0 is the clock cycle that begins with the rising edge at which f changes
   type hist_t  is array (-3 to 3) of natural;
   type hist4_t is array (0 to 3) of hist_t;     -- key at fall, key at rise, settings at fall, at rise
   type hists_t is array (0 to 1) of hist4_t;
   signal cov        : hists_t := (others => (others => (others => 0)));
   signal fe_t       : time_vector(0 to 1) := (others => 0 fs);   -- time of the last fall of f

   shared variable errcnt : counter_pt;
   signal checks      : natural := 0;
   signal id1_checks  : natural := 0;
   signal id2_checks  : natural := 0;
   signal rc_checks   : natural := 0;
   signal lc_checks   : natural := 0;
   signal btn_changes : natural := 0;
   signal pos_changes : natural := 0;

   procedure tb_error(msg : string) is
   begin
      if errcnt.value < 30 then
         report "TB_ERROR: " & msg & " at " & to_string(now, 1 ns) severity error;
      end if;
      errcnt.inc;
      if G_STOP then
         report "TB: RESULT FAIL (stopped at the first error)" severity note;
         finish;
      end if;
   end procedure tb_error;

   -- the four coverage counts of the part rule
   function cov_name(h : natural) return string is
   begin
      case h is
         when 0      => return "key at a fall of f";
         when 1      => return "key at a rise of f";
         when 2      => return "settings at a fall of f";
         when others => return "settings at a rise of f";
      end case;
   end function cov_name;

   -- floor(dt / C_PERIOD)
   function cyc(dt : time) return integer is
   begin
      if dt >= 0 fs then
         return dt / C_PERIOD;
      end if;
      return -((-dt + C_PERIOD - 1 fs) / C_PERIOD);
   end function cyc;

begin

   clk <= not clk after C_HALF when running;

   key       <= key_bg    when C_BG else key_st;
   rclick    <= rclick_bg when C_BG else rclick_st;
   fire_in(0) <= rfire(0) when C_OWN_FIRE else ln(0)(4);
   fire_in(1) <= rfire(1) when C_OWN_FIRE else ln(1)(4);

   dut : entity work.debouncer
      generic map (
         CLK_FREQ           => G_FREQ
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
         joy_1_fire_n       => fire_in(0),
         dbnce_joy1_up_n    => dut_j(0)(0),
         dbnce_joy1_down_n  => dut_j(0)(1),
         dbnce_joy1_left_n  => dut_j(0)(2),
         dbnce_joy1_right_n => dut_j(0)(3),
         dbnce_joy1_fire_n  => dut_j(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => fire_in(1),
         dbnce_joy2_up_n    => dut_j(1)(0),
         dbnce_joy2_down_n  => dut_j(1)(1),
         dbnce_joy2_left_n  => dut_j(1)(2),
         dbnce_joy2_right_n => dut_j(1)(3),
         dbnce_joy2_fire_n  => dut_j(1)(4),
         amiga_i            => amiga,
         amiga_rclick_i     => rclick,
         mega_key_n_i       => key,
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
         CLK_FREQ           => G_FREQ
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
         joy_1_fire_n       => fire_in(0),
         dbnce_joy1_up_n    => ref_j(0)(0),
         dbnce_joy1_down_n  => ref_j(0)(1),
         dbnce_joy1_left_n  => ref_j(0)(2),
         dbnce_joy1_right_n => ref_j(0)(3),
         dbnce_joy1_fire_n  => ref_j(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => fire_in(1),
         dbnce_joy2_up_n    => ref_j(1)(0),
         dbnce_joy2_down_n  => ref_j(1)(1),
         dbnce_joy2_left_n  => ref_j(1)(2),
         dbnce_joy2_right_n => ref_j(1)(3),
         dbnce_joy2_fire_n  => ref_j(1)(4)
      );

   sockets : entity work.debouncer_ref
      generic map (
         CLK_FREQ           => G_FREQ
      )
      port map (
         clk                => clk,
         reset_n            => reset_n,
         flip_joys_i        => '0',
         joy_1_on           => '1',
         joy_2_on           => '1',
         joy_1_up_n         => ln(0)(0),
         joy_1_down_n       => ln(0)(1),
         joy_1_left_n       => ln(0)(2),
         joy_1_right_n      => ln(0)(3),
         joy_1_fire_n       => fire_in(0),
         dbnce_joy1_up_n    => sk(0)(0),
         dbnce_joy1_down_n  => sk(0)(1),
         dbnce_joy1_left_n  => sk(0)(2),
         dbnce_joy1_right_n => sk(0)(3),
         dbnce_joy1_fire_n  => sk(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => fire_in(1),
         dbnce_joy2_up_n    => sk(1)(0),
         dbnce_joy2_down_n  => sk(1)(1),
         dbnce_joy2_left_n  => sk(1)(2),
         dbnce_joy2_right_n => sk(1)(3),
         dbnce_joy2_fire_n  => sk(1)(4)
      );

   prev : entity work.debouncer_prev
      generic map (
         CLK_FREQ           => G_FREQ
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
         joy_1_fire_n       => fire_in(0),
         dbnce_joy1_up_n    => prev_j(0)(0),
         dbnce_joy1_down_n  => prev_j(0)(1),
         dbnce_joy1_left_n  => prev_j(0)(2),
         dbnce_joy1_right_n => prev_j(0)(3),
         dbnce_joy1_fire_n  => prev_j(0)(4),
         joy_2_up_n         => ln(1)(0),
         joy_2_down_n       => ln(1)(1),
         joy_2_left_n       => ln(1)(2),
         joy_2_right_n      => ln(1)(3),
         joy_2_fire_n       => fire_in(1),
         dbnce_joy2_up_n    => prev_j(1)(0),
         dbnce_joy2_down_n  => prev_j(1)(1),
         dbnce_joy2_left_n  => prev_j(1)(2),
         dbnce_joy2_right_n => prev_j(1)(3),
         dbnce_joy2_fire_n  => prev_j(1)(4),
         amiga_i            => amiga,
         pot1_x_i           => pin_x(0),
         pot1_y_i           => pin_y(0),
         pot2_x_i           => pin_x(1),
         pot2_y_i           => pin_y(1),
         pot1_x_o           => prev_px(0),
         pot1_y_o           => prev_py(0),
         pot2_x_o           => prev_px(1),
         pot2_y_o           => prev_py(1)
      );

   gen_mice : for s in 0 to 1 generate
      mouse : entity work.amiga_mouse
         generic map (
            G_CLK_FREQ     => G_FREQ
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

   ---------------------------------------------------------------------------------------------
   -- The model of SPEC.md section 5.1: "At every clock edge at which f is '1', q takes the value
   -- of amiga_i(s) and amiga_rclick_i(s) and not mega_key_n_i. While f is '0', q keeps its value."
   ---------------------------------------------------------------------------------------------
   model_q : process (clk)
   begin
      if rising_edge(clk) then
         for s in 0 to 1 loop
            if sk(s)(4) = '1' then
               mq(s) <= amiga(s) = '1' and rclick(s) = '1' and key = '0';
            end if;
         end loop;
      end if;
   end process model_q;

   -- For the two properties: what a press would be that begins at this rising edge (key, setting
   -- and switch as they are when the edge comes), and what the current press is
   classify_edge : process (clk)
   begin
      if rising_edge(clk) then
         for s in 0 to 1 loop
            e_rc(s) <= key = '0' and amiga(s) = '1' and rclick(s) = '1';
         end loop;
      end if;
   end process classify_edge;

   gen_press : for s in 0 to 1 generate
      classify_press : process
      begin
         wait until sk(s)(4)'event and sk(s)(4) = '0' and sk(s)(4)'last_value = '1';
         pr_rc(s) <= e_rc(s);
         if e_rc(s) then
            n_rc_press(s) <= n_rc_press(s) + 1;
         else
            n_lc_press(s) <= n_lc_press(s) + 1;
         end if;
      end process classify_press;
   end generate gen_press;

   ---------------------------------------------------------------------------------------------
   checker : process
      variable s     : natural;
      variable on_p  : boolean;
      variable r     : std_logic;
      variable f     : std_logic;
      variable ex_j  : std_logic_vector(4 downto 0);
      variable ex_px : std_logic_vector(7 downto 0);
      variable ex_py : std_logic_vector(7 downto 0);
      variable n     : natural := 0;
      variable nid1  : natural := 0;
      variable nid2  : natural := 0;
      variable nrc   : natural := 0;
      variable nlc   : natural := 0;
   begin
      wait on clk, dut_j, ref_j, prev_j, sk, dut_px, dut_py, prev_px, prev_py, mr_x, mr_y, mr_right,
              mr_middle, flip, on1, on2, amiga, rclick, key, pin_x, pin_y, reset_n, mq, pr_rc;
      wait for 1 ps;
      for p in 0 to 1 loop
         if flip = '0' then
            s := p;
         else
            s := 1 - p;
         end if;
         on_p := (p = 0 and on1 = '1') or (p = 1 and on2 = '1');

         -- identity with the entity before the Amiga mice
         if G_IDENT and amiga = "00" then
            nid1 := nid1 + 1;
            if dut_j(p) /= ref_j(p) or dut_px(p) /= pin_x(p) or dut_py(p) /= pin_y(p) then
               tb_error("amiga_i = 00, C64 port " & integer'image(p + 1) & ": lines " & to_string(dut_j(p)) &
                        ", paddles " & to_hstring(dut_px(p)) & " / " & to_hstring(dut_py(p)) &
                        "; debouncer_ref: lines " & to_string(ref_j(p)) & ", paddle inputs " &
                        to_hstring(pin_x(p)) & " / " & to_hstring(pin_y(p)) & " (amiga_rclick_i " &
                        to_string(rclick) & ", key " & std_logic'image(key) & ")");
            end if;
         end if;

         -- identity with the entity before the right click
         if G_IDENT and rclick = "00" then
            nid2 := nid2 + 1;
            if dut_j(p) /= prev_j(p) or dut_px(p) /= prev_px(p) or dut_py(p) /= prev_py(p) then
               tb_error("amiga_rclick_i = 00, C64 port " & integer'image(p + 1) & ": lines " & to_string(dut_j(p)) &
                        ", paddles " & to_hstring(dut_px(p)) & " / " & to_hstring(dut_py(p)) &
                        "; debouncer_prev: lines " & to_string(prev_j(p)) & ", paddles " &
                        to_hstring(prev_px(p)) & " / " & to_hstring(prev_py(p)) & " (amiga " &
                        to_string(amiga) & ", flip " & std_logic'image(flip) & ", key " & std_logic'image(key) & ")");
            end if;
         end if;

         -- the model of sections 5 and 5.1
         if G_MODEL then
            f := sk(s)(4);
            if mq(s) and amiga(s) = '1' and rclick(s) = '1' then
               r := '1';
            else
               r := '0';
            end if;
            ex_px := pin_x(p);
            ex_py := pin_y(p);
            if amiga(s) = '1' then
               ex_px := not mr_x(s);
               ex_py := not mr_y(s);
            end if;
            if not on_p then
               ex_j := "11111";
            elsif amiga(s) = '1' then
               ex_j := (f or r) & "11" & mr_middle(s) & (mr_right(s) and (f or not r));
            else
               ex_j := ref_j(p);
            end if;
            if dut_j(p) /= ex_j then
               tb_error("C64 port " & integer'image(p + 1) & ": lines " & to_string(dut_j(p)) & ", expected " &
                        to_string(ex_j) & " (flip " & std_logic'image(flip) & ", amiga " & to_string(amiga) &
                        ", amiga_rclick_i " & to_string(rclick) & ", key " & std_logic'image(key) &
                        ", f " & std_logic'image(f) & ", r " & std_logic'image(r) &
                        ", on " & std_logic'image(on1) & std_logic'image(on2) & ")");
            end if;
            if dut_px(p) /= ex_px or dut_py(p) /= ex_py then
               tb_error("C64 port " & integer'image(p + 1) & ": paddles " & to_hstring(dut_px(p)) & " / " &
                        to_hstring(dut_py(p)) & ", expected " & to_hstring(ex_px) & " / " & to_hstring(ex_py) &
                        " (flip " & std_logic'image(flip) & ", amiga " & to_string(amiga) & ")");
            end if;
         end if;

         -- the two properties of section 5.1
         if on_p and amiga(s) = '1' and sk(s)(4) = '0' then
            if pr_rc(s) and rclick(s) = '1' then
               nrc := nrc + 1;
               if dut_j(p)(4) = '0' then
                  tb_error("C64 port " & integer'image(p + 1) & ": fire line low during a right click of socket " &
                           integer'image(s));
               end if;
            else
               nlc := nlc + 1;
               if dut_j(p)(0) = '0' and mr_right(s) /= '0' then
                  tb_error("C64 port " & integer'image(p + 1) & ": up line low during a left click of socket " &
                           integer'image(s) & " while the mouse does not report its right button");
               end if;
            end if;
         end if;
      end loop;
      n := n + 1;
      checks     <= n;
      id1_checks <= nid1;
      id2_checks <= nid2;
      rc_checks  <= nrc;
      lc_checks  <= nlc;
   end process checker;

   ---------------------------------------------------------------------------------------------
   -- Coverage: the key and the settings of each socket changing around the edges of f
   ---------------------------------------------------------------------------------------------
   gen_cover : for s in 0 to 1 generate
      coverage : process
         variable tf     : time    := 0 fs;    -- the last edge of f
         variable fk     : natural := 0;       -- 0: it was a fall, 1: a rise
         variable have_f : boolean := false;
         variable tk     : time    := 0 fs;    -- the last change of the key
         variable have_k : boolean := false;
         variable ts     : time    := 0 fs;    -- the last change of a setting of this socket
         variable have_s : boolean := false;
         variable d      : integer;
         variable h      : hist4_t := (others => (others => 0));
      begin
         wait on sk(s)(4), key, amiga(s), rclick(s);
         if sk(s)(4)'event and (sk(s)(4) = '0' or sk(s)(4) = '1') and
            (sk(s)(4)'last_value = '0' or sk(s)(4)'last_value = '1') then
            tf     := now;
            have_f := true;
            if sk(s)(4) = '0' then
               fk := 0;
               fe_t(s) <= now;
            else
               fk := 1;
            end if;
            if have_k then
               d := cyc(tk - tf);
               if d >= -3 then
                  h(fk)(d) := h(fk)(d) + 1;
               end if;
            end if;
            if have_s then
               d := cyc(ts - tf);
               if d >= -3 then
                  h(2 + fk)(d) := h(2 + fk)(d) + 1;
               end if;
            end if;
         end if;
         if key'event then
            tk     := now;
            have_k := true;
            if have_f then
               d := cyc(tk - tf);
               if d <= 3 then
                  h(fk)(d) := h(fk)(d) + 1;
               end if;
            end if;
         end if;
         if amiga(s)'event or rclick(s)'event then
            ts     := now;
            have_s := true;
            if have_f then
               d := cyc(ts - tf);
               if d <= 3 then
                  h(2 + fk)(d) := h(2 + fk)(d) + 1;
               end if;
            end if;
         end if;
         cov(s) <= h;
      end process coverage;
   end generate gen_cover;

   ---------------------------------------------------------------------------------------------
   -- Socket activity. Each socket: in Amiga mode quadrature on both pairs (about 3000 counts per
   -- second, changing directions), the left button on fire, the right and middle button as
   -- measured values (12 released, 255 pressed, sometimes a value of 128 .. 191); in C64 mode
   -- random joystick lines (mostly long enough for the 1 ms debouncer) and random paddle values.
   -- In the parts rule and directed the stimulus drives the fire lines; in the part directed the
   -- direction lines stay released and the right button follows want_right.
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
         if G_PART = "directed" then
            wait;
         end if;
         wait for 1 us;
         loop
            if amiga(s) = '1' then
               rand_real(r, 200.0, 500.0, q);
               wait for q * C_US;
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
                  tf := now + q * C_MS;
               end if;
               ln(s) <= v;
            else
               rand(r, q);
               if q < 0.7 then
                  rand_real(r, 1.2, 4.0, q);
               else
                  rand_real(r, 0.01, 0.9, q);
               end if;
               wait for q * C_MS;
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
            if G_PART = "directed" then
               rand_real(r, 0.05, 0.1, q);
            else
               rand_real(r, 0.3, 0.7, q);
            end if;
            wait for q * C_MS;
            if G_PART = "directed" then
               if want_right(s) = '1' then
                  tv_x(s) <= x"FF";
               else
                  tv_x(s) <= x"0C";
               end if;
               tv_y(s) <= x"0D";
            elsif amiga(s) = '1' then
               -- right button every 4.5 (socket 0) / 6.5 ms (socket 1), middle every 5.5 / 7.5 ms
               if now >= tx then
                  sx := not sx;
                  tx := now + (4.5 + 2.0 * real(s)) * C_MS;
               end if;
               if now >= ty then
                  sy := not sy;
                  ty := now + (5.5 + 2.0 * real(s)) * C_MS;
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

   -- the key and the switches outside of the parts rule and directed: the key toggles at random,
   -- in the part identity also the two switches
   background : process
      variable r : rng_t := rng_init(300 + G_SEED);
      variable q : real;
      variable k : integer;
   begin
      if not C_BG then
         wait;
      end if;
      loop
         rand(r, q);
         if q < 0.5 then
            rand_real(r, 0.02, 0.5, q);
         else
            rand_real(r, 0.5, 4.0, q);
         end if;
         wait for q * C_MS + q * 1 ns;
         rand(r, q);
         if G_PART = "identity" and q < 0.3 then
            rand_int(r, 0, 1, k);
            rclick_bg(k) <= not rclick_bg(k);
         else
            key_bg <= not key_bg;
         end if;
      end loop;
   end process background;

   ---------------------------------------------------------------------------------------------
   stim : process
      variable r     : rng_t := rng_init(G_SEED);
      variable q     : real;
      variable c     : std_logic_vector(4 downto 0);
      variable nerr  : natural;
      variable nsw   : natural := 0;
      variable nrst  : natural := 0;
      variable nlong : integer_vector(0 to 1) := (0, 0);   -- part rule: episodes with socket s held
      variable nboth : integer_vector(0 to 1) := (0, 0);   -- part rule: both pressed, socket s first
      variable nrelf : integer_vector(0 to 1) := (0, 0);   -- part rule: both pressed, socket s released first
      variable ncase : natural := 0;
      variable nexp  : natural := 0;
      variable te    : time_vector(0 to 1) := (others => 0 fs);   -- predicted fall of f per socket

      -- events of an episode of the part rule, sorted by time
      type ev_t is record
         t : time;
         k : natural;        -- 0 key, 1 switch, 2 Amiga setting, 3 fire low, 4 fire high, 5 flip, 6 on/off
         s : natural;
      end record;
      type evs_t is array (1 to 24) of ev_t;
      variable evs : evs_t;
      variable nev : natural := 0;

      procedure ev_add(t : time; k, s : natural) is
         variable i : natural;
      begin
         if nev = evs'high then
            return;
         end if;
         nev := nev + 1;
         i := nev;
         while i > 1 and evs(i - 1).t > t loop
            evs(i) := evs(i - 1);
            i := i - 1;
         end loop;
         evs(i) := (t, k, s);
      end procedure ev_add;

      procedure ev_run is
      begin
         for i in 1 to nev loop
            if evs(i).t > now then
               wait for evs(i).t - now;
            end if;
            case evs(i).k is
               when 0 => key_st <= not key_st;
               when 1 => rclick_st(evs(i).s) <= not rclick_st(evs(i).s);
               when 2 => amiga(evs(i).s) <= not amiga(evs(i).s);
               when 3 => rfire(evs(i).s) <= '0';
               when 4 => rfire(evs(i).s) <= '1';
               when 5 => flip <= not flip;
               when others =>
                  if evs(i).s = 0 then
                     on1 <= not on1;
                  else
                     on2 <= not on2;
                  end if;
            end case;
            wait for 0 ns;
         end loop;
         nev := 0;
      end procedure ev_run;

      -- the raw fire line of socket s goes low at the next falling clock edge; te(s) is the
      -- rising edge at which f falls
      procedure press_fire(s : natural) is
      begin
         wait until falling_edge(clk);
         rfire(s) <= '0';
         te(s) := now + C_DB_LAT;
      end procedure press_fire;

      procedure release_fire(s : natural) is
      begin
         wait until falling_edge(clk);
         rfire(s) <= '1';
      end procedure release_fire;

      -- wait until f of socket s is v; after a press, it has to fall exactly at the predicted edge
      procedure wait_f(s : natural; v : std_logic) is
      begin
         if sk(s)(4) /= v then
            wait until sk(s)(4) = v for 3 * C_MS;
         end if;
         wait for 1 ps;
         if sk(s)(4) /= v then
            tb_error("socket " & integer'image(s) & ": f did not become " & std_logic'image(v));
         elsif v = '0' and fe_t(s) /= te(s) then
            tb_error("socket " & integer'image(s) & ": f fell at " & to_string(fe_t(s), 1 ns) &
                     ", the bench predicted " & to_string(te(s), 1 ns));
         end if;
      end procedure wait_f;

      procedure expect(p : natural; up, fire : std_logic; what : string) is
      begin
         nexp := nexp + 1;
         if dut_j(p)(0) /= up or dut_j(p)(4) /= fire then
            tb_error(what & ": C64 port " & integer'image(p + 1) & " up " & std_logic'image(dut_j(p)(0)) &
                     " fire " & std_logic'image(dut_j(p)(4)) & ", expected up " & std_logic'image(up) &
                     " fire " & std_logic'image(fire));
         end if;
      end procedure expect;

      -- the right button of the mouse of socket s (directed): wait until the reference mouse reports it
      procedure dev_right(s : natural; v : std_logic) is
      begin
         want_right(s) <= v;
         if mr_right(s) /= not v then
            wait until mr_right(s) = not v for 10 * C_MS;
         end if;
         if mr_right(s) /= not v then
            tb_error("socket " & integer'image(s) & ": the reference mouse does not follow want_right");
         end if;
         wait for 10 * C_PERIOD;
      end procedure dev_right;

      procedure settings(am, rc : std_logic_vector(1 downto 0); fl, o1, o2 : std_logic) is
      begin
         amiga     <= am;
         rclick_st <= rc;
         flip      <= fl;
         on1       <= o1;
         on2       <= o2;
         wait for 0 ns;
      end procedure settings;

      procedure begin_case(name : string) is
      begin
         ncase := ncase + 1;
         report "TB: case " & integer'image(ncase) & ": " & name severity note;
      end procedure begin_case;

      -- part directed, case 3: the key changes in clock cycle c(d), where c(0) begins with the
      -- rising edge at which f falls; the key at that edge decides
      procedure key_at(d : integer; press_key : boolean) is
         variable rc : boolean;
      begin
         if press_key then
            key_st <= '1';
            rc := d < 0;      -- pressed before the edge: right click
         else
            key_st <= '0';
            rc := d >= 0;     -- released after the edge: right click
         end if;
         wait for 0.3 * C_MS;
         press_fire(0);
         if d < 0 then
            wait for te(0) + d * C_PERIOD + C_HALF - now;
            key_st <= not key_st;
         end if;
         -- in c(0), the first clock cycle of the press
         wait for te(0) + C_HALF / 2 - now;
         if rc then
            expect(0, '0', '1', "key changed in c(" & integer'image(d) & "): right click in c(0)");
         else
            expect(0, '1', '0', "key changed in c(" & integer'image(d) & "): left click in c(0)");
         end if;
         if d >= 0 then
            wait for te(0) + d * C_PERIOD + C_HALF - now;
            key_st <= not key_st;
         end if;
         wait_f(0, '0');
         wait for 0.3 * C_MS;
         if rc then
            expect(0, '0', '1', "key changed in c(" & integer'image(d) & "): right click, later");
         else
            expect(0, '1', '0', "key changed in c(" & integer'image(d) & "): left click, later");
         end if;
         release_fire(0);
         key_st <= '1';
         wait_f(0, '1');
         wait for 0.3 * C_MS;
         expect(0, '1', '1', "after the press");
      end procedure key_at;

      -- part rule: rotations per socket (index 4 * socket + kind; kinds 0 and 1: the key at a fall
      -- and at a rise of f, 2 and 3: a setting at a fall and at a rise)
      variable rot : integer_vector(0 to 7) := (others => 0);

      -- part rule: changes around an edge of f of socket s at t_e (e = 0: fall, e = 1: rise): the key in
      -- the clock cycle c(-3) .. c(2) that the rotation of the socket chooses, so that every one of
      -- them is hit in turn, with a probability of 0.5 a second key change in a random one of these
      -- cycles, and a change of the switch (with a probability of 0.2 of the Amiga setting instead) of
      -- socket s in the clock cycle of a second rotation that runs the other way round
      procedure around(s : natural; t_e : time; e : natural) is
         variable dk : integer;
         variable qq : real;
      begin
         dk := -3 + rot(4 * s + e) mod 6;
         rot(4 * s + e) := rot(4 * s + e) + 1;
         rand_real(r, 0.1, 0.9, qq);
         ev_add(t_e + dk * C_PERIOD + qq * C_PERIOD, 0, 0);
         rand(r, qq);
         if qq < 0.5 then
            rand_int(r, -3, 2, dk);
            rand_real(r, 0.1, 0.9, qq);
            ev_add(t_e + dk * C_PERIOD + qq * C_PERIOD, 0, 0);
         end if;
         dk := -3 + (5 * rot(4 * s + 2 + e)) mod 6;
         rot(4 * s + 2 + e) := rot(4 * s + 2 + e) + 1;
         rand(r, qq);
         if qq < 0.8 then
            ev_add(t_e + dk * C_PERIOD + C_HALF, 1, s);
         else
            ev_add(t_e + dk * C_PERIOD + C_HALF, 2, s);
         end if;
      end procedure around;

      -- part rule: activity while buttons are held, for lo to hi milliseconds of the instances: the
      -- key, rarely a setting, the port switcher, on/off, and if allowed a short reset
      procedure hold(lo, hi : real; allow_reset : boolean) is
         variable qq : real;
         variable mm : integer;
         variable te_hold : time;
      begin
         rand_real(r, lo, hi, qq);
         te_hold := now + qq * C_MS;
         while now < te_hold loop
            rand_real(r, 0.05, 0.6, qq);
            wait for qq * C_MS + qq * 1 ns;
            rand(r, qq);
            if qq < 0.6 then
               key_st <= not key_st;
            elsif qq < 0.7 then
               rand_int(r, 0, 1, mm);
               rclick_st(mm) <= not rclick_st(mm);
            elsif qq < 0.75 then
               rand_int(r, 0, 1, mm);
               amiga(mm) <= not amiga(mm);
            elsif qq < 0.78 then
               flip <= not flip;
            elsif qq < 0.81 then
               on1 <= not on1;
            elsif qq < 0.84 then
               on2 <= not on2;
            elsif qq < 0.85 and allow_reset then
               reset_n <= '0';
               rand_int(r, 2, 50, mm);
               wait for mm * C_PERIOD;
               reset_n <= '1';
               nrst := nrst + 1;
            end if;
         end loop;
      end procedure hold;

      -- part rule: press the fire line of socket s with the changes around the fall of f
      procedure rule_press(s : natural) is
      begin
         press_fire(s);
         around(s, te(s), 0);
         ev_run;
         if te(s) + 4 * C_PERIOD > now then
            wait for te(s) + 4 * C_PERIOD - now;
         end if;
         wait_f(s, '0');
      end procedure rule_press;

      -- part rule: release the fire line of socket s with the changes around the rise of f
      procedure rule_release(s : natural) is
      begin
         release_fire(s);
         around(s, now + C_DB_LAT, 1);
         ev_run;
      end procedure rule_release;

      -- part directed: socket h is held while the key changes, then socket o is pressed; the decision for
      -- o follows the key at its own press, whatever h does (flip_joys_i at '0': C64 port p is socket p)
      procedure held_then_other(h, o : natural) is
      begin
         key_st <= '1';
         wait for 0.3 * C_MS;
         press_fire(h);
         wait_f(h, '0');
         expect(h, '1', '0', "socket " & integer'image(h) & " pressed without the key: left click");
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(o);
         wait_f(o, '0');
         expect(o, '0', '1', "socket " & integer'image(o) & " pressed with the key while socket " &
                integer'image(h) & " is held: right click");
         expect(h, '1', '0', "socket " & integer'image(h) & " still a left click");
         key_st <= '1';
         wait for 0.3 * C_MS;
         release_fire(o);
         wait_f(o, '1');
         release_fire(h);
         wait_f(h, '1');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(h);
         wait_f(h, '0');
         expect(h, '0', '1', "socket " & integer'image(h) & " pressed with the key: right click");
         key_st <= '1';
         wait for 0.3 * C_MS;
         press_fire(o);
         wait_f(o, '0');
         expect(o, '1', '0', "socket " & integer'image(o) & " pressed without the key while socket " &
                integer'image(h) & " is held: left click");
         expect(h, '0', '1', "socket " & integer'image(h) & " still a right click");
         release_fire(o);
         wait_f(o, '1');
         release_fire(h);
         wait_f(h, '1');
         wait for 0.3 * C_MS;
         expect(0, '1', '1', "all released");
         expect(1, '1', '1', "all released");
      end procedure held_then_other;

      variable k, d, m, dd : integer;
      variable sa          : natural;
      variable sb          : natural;
      variable both        : boolean;
      variable tl          : time;
      variable t1          : time;

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
                integer'image(nrst) & " resets, random amiga_rclick_i and mega_key_n_i: the ten joystick outputs " &
                "were identical to the entity before the Amiga mice and the paddle outputs equal to the paddle " &
                "inputs at every event" severity note;
      elsif G_PART = "modes" then
         for i in 0 to 31 loop
            -- a random order of the combinations: i * 13 mod 32 visits each one once
            c := std_logic_vector(to_unsigned((i * 13 + 5) mod 32, 5));
            flip    <= c(0);
            amiga   <= c(2 downto 1);
            on1     <= c(3);
            on2     <= c(4);
            rand_real(r, 12.0, 16.0, q);
            wait for q * 1 ms + q * 1 ns;
         end loop;
         -- the switcher and the settings also change in the middle of activity
         for i in 1 to 30 loop
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
                "each, then 30 random switches, mega_key_n_i toggling: every C64 port showed what the socket " &
                "connected to it delivers, and all outputs were those of the entity before the right click"
                severity note;
      elsif G_PART = "rule" then
         wait for 2 * C_MS;
         for ep in 1 to G_EPISODES loop
            -- settings of the episode: mostly Amiga mode with the switch on
            for s in 0 to 1 loop
               rand(r, q);
               if q < 0.85 then amiga(s) <= '1'; else amiga(s) <= '0'; end if;
               rand(r, q);
               if q < 0.75 then rclick_st(s) <= '1'; else rclick_st(s) <= '0'; end if;
            end loop;
            rand(r, q);
            if q < 0.5 then flip <= '0'; else flip <= '1'; end if;
            rand(r, q);
            if q < 0.9 then on1 <= '1'; else on1 <= '0'; end if;
            rand(r, q);
            if q < 0.9 then on2 <= '1'; else on2 <= '0'; end if;
            rand(r, q);
            if q < 0.5 then key_st <= '0'; else key_st <= '1'; end if;
            rand_real(r, 0.3, 1.0, q);
            wait for q * C_MS + q * 1 ns;

            -- the four kinds of episode in turn: k = 0 or 1: a press of socket k alone; k = 2: both
            -- sockets, pressed 0 to 4 clock cycles apart and released 0 to 4 clock cycles apart, the
            -- socket pressed first and the one released first in all four combinations in turn; k = 3:
            -- one socket held for a whole press of the other, with the key changing in between, the held
            -- socket alternating
            k := (ep - 1) mod 4;
            if k <= 1 then
               sa := k;
            else
               sa := ((ep - 1) / 4) mod 2;     -- the socket that is pressed first, or held
            end if;
            sb   := 1 - sa;
            both := k = 2;
            if k <= 2 then
               rand_int(r, 0, 4, dd);
               press_fire(sa);
               around(sa, te(sa), 0);
               if both then
                  ev_add(now + dd * C_PERIOD, 3, sb);
                  te(sb) := te(sa) + dd * C_PERIOD;
                  around(sb, te(sb), 0);
               end if;
               ev_run;
               tl := te(sa);
               if both and te(sb) > tl then
                  tl := te(sb);
               end if;
               if tl + 4 * C_PERIOD > now then
                  wait for tl + 4 * C_PERIOD - now;
               end if;
               wait_f(sa, '0');
               if both then
                  wait_f(sb, '0');
               end if;
               hold(0.2, 3.0, true);
               -- the release, with changes around the rise of f
               if both then
                  m := ((ep - 1) / 8) mod 2;      -- the socket that is released first
                  rand_int(r, 0, 4, dd);
                  nrelf(m) := nrelf(m) + 1;
                  release_fire(m);
                  t1 := now;
                  around(m, t1 + C_DB_LAT, 1);
                  ev_add(t1 + dd * C_PERIOD, 4, 1 - m);
                  around(1 - m, t1 + dd * C_PERIOD + C_DB_LAT, 1);
                  ev_run;
               else
                  rule_release(sa);
               end if;
            else
               -- socket sa held for a whole press of socket sb
               rule_press(sa);
               hold(0.1, 0.6, false);
               key_st <= not key_st;
               wait for 0.05 * C_MS;
               rule_press(sb);
               hold(0.2, 1.5, false);
               rule_release(sb);
               hold(1.2, 2.0, false);
               rule_release(sa);
               nlong(sa) := nlong(sa) + 1;
            end if;
            if both then
               nboth(sa) := nboth(sa) + 1;
            end if;
            rand_real(r, 1.3, 2.5, q);
            wait for q * C_MS + q * 1 ns;
            rfire <= "11";
         end loop;
         wait for 2 * C_MS;
         for s in 0 to 1 loop
            report "TB: socket " & integer'image(s) & ": " & integer'image(n_rc_press(s)) & " presses began as right clicks, " &
                   integer'image(n_lc_press(s)) & " as left clicks" severity note;
            report "TB: socket " & integer'image(s) & ", key changes in c(-3) .. c(3) around a fall of f: " &
                   integer'image(cov(s)(0)(-3)) & " " & integer'image(cov(s)(0)(-2)) & " " & integer'image(cov(s)(0)(-1)) & " " &
                   integer'image(cov(s)(0)(0)) & " " & integer'image(cov(s)(0)(1)) & " " & integer'image(cov(s)(0)(2)) & " " &
                   integer'image(cov(s)(0)(3)) & "; around a rise: " &
                   integer'image(cov(s)(1)(-3)) & " " & integer'image(cov(s)(1)(-2)) & " " & integer'image(cov(s)(1)(-1)) & " " &
                   integer'image(cov(s)(1)(0)) & " " & integer'image(cov(s)(1)(1)) & " " & integer'image(cov(s)(1)(2)) & " " &
                   integer'image(cov(s)(1)(3)) severity note;
            report "TB: socket " & integer'image(s) & ", setting changes in c(-3) .. c(3) around a fall of f: " &
                   integer'image(cov(s)(2)(-3)) & " " & integer'image(cov(s)(2)(-2)) & " " & integer'image(cov(s)(2)(-1)) & " " &
                   integer'image(cov(s)(2)(0)) & " " & integer'image(cov(s)(2)(1)) & " " & integer'image(cov(s)(2)(2)) & " " &
                   integer'image(cov(s)(2)(3)) & "; around a rise: " &
                   integer'image(cov(s)(3)(-3)) & " " & integer'image(cov(s)(3)(-2)) & " " & integer'image(cov(s)(3)(-1)) & " " &
                   integer'image(cov(s)(3)(0)) & " " & integer'image(cov(s)(3)(1)) & " " & integer'image(cov(s)(3)(2)) & " " &
                   integer'image(cov(s)(3)(3)) severity note;
            for h in 0 to 3 loop
               for dk in -1 to 1 loop
                  if cov(s)(h)(dk) < C_MIN_COV then
                     tb_error("socket " & integer'image(s) & ": " & integer'image(cov(s)(h)(dk)) & " changes of the " &
                              cov_name(h) & " in c(" & integer'image(dk) & "), at least " &
                              integer'image(C_MIN_COV) & " required");
                  end if;
               end loop;
            end loop;
            if n_rc_press(s) < C_MIN_COV or n_lc_press(s) < C_MIN_COV or nboth(s) < C_MIN_COV or
               nrelf(s) < C_MIN_COV or nlong(s) < C_MIN_COV then
               tb_error("socket " & integer'image(s) & ": too few right clicks, left clicks, first presses, first " &
                        "releases or long presses (at least " & integer'image(C_MIN_COV) & " each)");
            end if;
         end loop;
         report "TB: " & integer'image(G_EPISODES) & " episodes with " & integer'image(nrst) & " resets; both sockets " &
                "pressed: socket 0 first " & integer'image(nboth(0)) & " times, socket 1 first " & integer'image(nboth(1)) &
                " times, socket 0 released first " & integer'image(nrelf(0)) & " times, socket 1 first " &
                integer'image(nrelf(1)) & " times; socket 0 held for a whole press of socket 1 " & integer'image(nlong(0)) &
                " times, the other way round " & integer'image(nlong(1)) & " times" severity note;
      elsif G_PART = "directed" then
         -- both sockets in Amiga mode with the switch on from power-up: nothing happens before a press
         settings("11", "11", '0', '1', '1');
         wait for 6 * C_MS;     -- the mice see the pull-ups of their right buttons
         expect(0, '1', '1', "power-up with both switches on");
         expect(1, '1', '1', "power-up with both switches on");

         begin_case("key first, then the button: a right click for the whole press, also when the key is " &
                    "released and pressed again during the press");
         settings("11", "11", '0', '1', '1');
         key_st <= '0';
         wait for 0.2 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(0, '0', '1', "right click");
         expect(1, '1', '1', "the other port");
         wait for 0.3 * C_MS;
         key_st <= '1';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "key released during the right click");
         key_st <= '0';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "key pressed again during the right click");
         key_st <= '1';
         wait for 0.3 * C_MS;
         release_fire(0);
         wait_f(0, '1');
         expect(0, '1', '1', "after the right click");

         begin_case("button first, then the key: a left click for the whole press");
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(0, '1', '0', "left click");
         wait for 0.3 * C_MS;
         key_st <= '0';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "key pressed during the left click");
         key_st <= '1';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "key released during the left click");
         release_fire(0);
         wait_f(0, '1');
         expect(0, '1', '1', "after the left click");

         begin_case("the key released or pressed in the clock cycles c(-2) .. c(2) around the fall of f; c(0) " &
                    "begins with the rising edge at which f falls");
         for dk in -2 to 2 loop
            key_at(dk, false);
            key_at(dk, true);
         end loop;

         begin_case("the right button of the mouse pressed before, during and after a right click");
         settings("11", "11", '0', '1', '1');
         wait for 0.3 * C_MS;
         dev_right(0, '1');
         expect(0, '0', '1', "right button of the mouse, no key");
         key_st <= '0';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "right button of the mouse, key held");
         press_fire(0);
         wait_f(0, '0');
         expect(0, '0', '1', "right click while the mouse reports its right button");
         dev_right(0, '0');
         expect(0, '0', '1', "right click, right button of the mouse released");
         release_fire(0);
         wait_f(0, '1');
         wait for 0.3 * C_MS;
         expect(0, '1', '1', "key still held, no press");
         dev_right(0, '1');
         expect(0, '0', '1', "key still held, right button of the mouse");
         press_fire(0);
         wait_f(0, '0');
         expect(0, '0', '1', "right click and right button of the mouse");
         release_fire(0);
         wait_f(0, '1');
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "right click over, right button of the mouse still pressed, key held");
         key_st <= '1';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "right button of the mouse still pressed, key released");
         dev_right(0, '0');
         expect(0, '1', '1', "all released");
         dev_right(0, '1');
         expect(0, '0', '1', "right button of the mouse after the right click, switch on");
         dev_right(0, '0');
         expect(0, '1', '1', "all released");

         begin_case("both sockets at once with different settings");
         settings("11", "01", '0', '1', '1');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         press_fire(1);
         wait_f(0, '0');
         wait_f(1, '0');
         expect(0, '0', '1', "socket 0 with the switch on: right click");
         expect(1, '1', '0', "socket 1 with the switch off: left click");
         release_fire(0);
         release_fire(1);
         key_st <= '1';
         wait_f(0, '1');
         wait_f(1, '1');
         settings("11", "11", '0', '1', '1');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         key_st <= '1';
         wait for 0.3 * C_MS;
         press_fire(1);
         wait_f(1, '0');
         expect(0, '0', '1', "socket 0 pressed with the key: right click");
         expect(1, '1', '0', "socket 1 pressed without the key: left click");
         key_st <= '0';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "socket 0, key pressed again: right click");
         expect(1, '1', '0', "socket 1, key pressed again: left click");
         release_fire(0);
         release_fire(1);
         key_st <= '1';
         wait_f(0, '1');
         wait_f(1, '1');
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(1);
         wait_f(1, '0');
         expect(0, '1', '0', "socket 0 pressed without the key: left click");
         expect(1, '0', '1', "socket 1 pressed with the key: right click");
         release_fire(0);
         release_fire(1);
         key_st <= '1';
         wait_f(0, '1');
         wait_f(1, '1');

         begin_case("socket 1 held, the key changed, then socket 0 pressed; and the other way round");
         settings("11", "11", '0', '1', '1');
         held_then_other(1, 0);
         held_then_other(0, 1);

         begin_case("a socket in C64 mode with the switch on: a joystick fire stays a fire");
         settings("01", "11", '0', '1', '1');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         press_fire(1);
         wait_f(0, '0');
         wait_f(1, '0');
         expect(0, '0', '1', "socket 0 in Amiga mode: right click");
         expect(1, '1', '0', "socket 1 in C64 mode: fire");
         release_fire(0);
         release_fire(1);
         wait_f(0, '1');
         wait_f(1, '1');
         settings("00", "11", '0', '1', '1');
         wait for 0.3 * C_MS;
         press_fire(0);
         press_fire(1);
         wait_f(0, '0');
         wait_f(1, '0');
         expect(0, '1', '0', "both sockets in C64 mode: fire");
         expect(1, '1', '0', "both sockets in C64 mode: fire");
         release_fire(0);
         release_fire(1);
         key_st <= '1';
         wait_f(0, '1');
         wait_f(1, '1');
         settings("11", "11", '0', '1', '1');
         wait for 6 * C_MS;

         begin_case("the switch or the Amiga setting changing during a press");
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(0, '0', '1', "right click");
         rclick_st(0) <= '0';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "switch off during the right click: the press is a left click");
         rclick_st(0) <= '1';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "switch on again: the press is a right click again");
         amiga(0) <= '0';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "Amiga setting off: the socket is a joystick, fire pressed");
         amiga(0) <= '1';
         wait for 0.3 * C_MS;
         expect(0, '0', '1', "Amiga setting on again: right click");
         release_fire(0);
         wait_f(0, '1');
         rclick_st(0) <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(0, '1', '0', "key held, switch off at the start: left click");
         rclick_st(0) <= '1';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "switch on during the press: still a left click");
         release_fire(0);
         wait_f(0, '1');
         amiga(0) <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(0, '1', '0', "key held, switch on, C64 mode at the start: fire");
         amiga(0) <= '1';
         wait for 0.3 * C_MS;
         expect(0, '1', '0', "Amiga setting on during the press: a left click");
         release_fire(0);
         key_st <= '1';
         wait_f(0, '1');
         wait for 6 * C_MS;

         begin_case("through the port switcher and with a port switched off");
         settings("11", "11", '1', '1', '1');
         key_st <= '0';
         wait for 0.3 * C_MS;
         press_fire(0);
         wait_f(0, '0');
         expect(1, '0', '1', "flipped: socket 0 right click on C64 port 2");
         expect(0, '1', '1', "flipped: socket 1 idle on C64 port 1");
         on2 <= '0';
         wait for 0.3 * C_MS;
         expect(1, '1', '1', "C64 port 2 off");
         on2 <= '1';
         wait for 0.3 * C_MS;
         expect(1, '0', '1', "C64 port 2 on again");
         key_st <= '1';
         wait for 0.3 * C_MS;
         press_fire(1);
         wait_f(1, '0');
         expect(0, '1', '0', "flipped: socket 1 left click on C64 port 1");
         on1 <= '0';
         wait for 0.3 * C_MS;
         expect(0, '1', '1', "C64 port 1 off");
         expect(1, '0', '1', "C64 port 2 still the right click");
         on1 <= '1';
         release_fire(0);
         release_fire(1);
         wait_f(0, '1');
         wait_f(1, '1');
         wait for 0.3 * C_MS;
         expect(0, '1', '1', "all released");
         expect(1, '1', '1', "all released");
         report "TB: " & integer'image(ncase) & " directed cases with " & integer'image(nexp) & " explicit checks" severity note;
      else
         tb_error("unknown part " & G_PART);
      end if;
      wait for 1 us;
      report "TB: " & integer'image(checks) & " comparisons; the reference mice changed their buttons " &
             integer'image(btn_changes) & " times and their positions " & integer'image(pos_changes) & " times" severity note;
      report "TB: identity with debouncer_ref checked " & integer'image(id1_checks) & " times, with debouncer_prev " &
             integer'image(id2_checks) & " times; the properties in " & integer'image(rc_checks) &
             " checks during right clicks and " & integer'image(lc_checks) & " during left clicks" severity note;
      if G_PART = "modes" and (btn_changes < 20 or pos_changes < 100) then
         tb_error("the bench did not exercise the Amiga mice");
      end if;
      if (G_PART = "identity" and id1_checks < 1000) or (G_PART = "modes" and id2_checks < 1000) or
         ((G_PART = "rule" or G_PART = "directed") and (rc_checks < 1000 or lc_checks < 1000)) then
         tb_error("the bench did not exercise its checks");
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
