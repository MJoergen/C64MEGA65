----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Conditioning of the two joystick ports, in the clock domain of the core:
--
-- 1) Debouncing: each of the ten lines passes two flip-flops and needs to be
--    stable for 1 ms before a change gets through (debounce.vhd).
--
-- 2) Amiga mice (GitHub issue #190): a socket whose bit of amiga_i is '1' has an
--    Amiga mouse, which amiga_mouse.vhd turns into a Commodore 1351 in
--    proportional mode. Its decoder takes the raw direction lines, because the
--    1 ms debouncer would swallow the quadrature edges. The four debounced
--    direction lines of that socket are replaced before the port switcher: up is
--    the right button, down is the middle button, left and right are released,
--    so that the quadrature signals never reach the C64. The fire line stays the
--    debounced fire line (the left button), except during a right click (3).
--    The paddle values of the C64 port that the socket is connected to are the
--    position of the mouse.
--
-- 3) Right click with the MEGA key (issue #190): for a socket in Amiga mode
--    whose bit of amiga_rclick_i is '1', a press of the left button that begins
--    while the MEGA key is held (mega_key_n_i = '0') is a right click: for the
--    whole press the fire line stays released and the up line is pressed, as
--    the right button of a 1351. A flip-flop per socket (rclick_q, initial
--    value '0', no reset) takes over "Amiga mode and switch on and MEGA key
--    held" at every clock edge at which the debounced fire line is released,
--    and keeps its value while the line is pressed; so the key at the moment
--    the button goes down decides, and in the clock cycle in which the fire
--    line goes low the flip-flop already holds the decision for this press.
--    A press is a right click while that flip-flop is '1' and the socket is
--    still in Amiga mode with the switch on (rclick). Then the fire line is the
--    debounced fire line or rclick, and the up line is the right button of the
--    mouse and (the debounced fire line or not rclick); the right button that
--    the mouse delivers keeps working. Both lines are combinational functions
--    of the debounced fire line, the flip-flop and the settings: they pass no
--    additional register.
--
-- 4) Port switcher: flip_joys_i exchanges the two ports for the C64.
--
-- 5) On/off: joy_1_on and joy_2_on switch the five lines of a C64 port off ('1').
--
-- The paddle values arrive already switched to C64 ports and inverted, as the
-- core expects them. A mouse needs the true values of its own socket for its
-- buttons, so each instance of amiga_mouse takes the values of the C64 port that
-- its socket is connected to and inverts them; its position goes out inverted
-- on the same C64 port.
--
-- All vectors with two elements are indexed by socket: 0 is the MEGA65's port 1,
-- 1 is port 2. With amiga_i at "00" the ten joystick outputs are exactly what
-- they were before the Amiga mice existed, and the four paddle outputs are the
-- four paddle inputs. A socket whose bit of amiga_i or of amiga_rclick_i is '0'
-- has rclick at '0' in every clock cycle: then none of its lines depends on
-- mega_key_n_i or on rclick_q, and with amiga_rclick_i at "00" the fourteen
-- outputs do not depend on them at all. The two sockets share the MEGA key and
-- nothing else.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity debouncer is
generic (
   CLK_FREQ           : in integer
);
port (
   clk                : in std_logic;
   reset_n            : in std_logic;

   flip_joys_i        : in std_logic;
   joy_1_on           : in std_logic;
   joy_2_on           : in std_logic;

   joy_1_up_n         : in std_logic;
   joy_1_down_n       : in std_logic;
   joy_1_left_n       : in std_logic;
   joy_1_right_n      : in std_logic;
   joy_1_fire_n       : in std_logic;

   dbnce_joy1_up_n    : out std_logic;
   dbnce_joy1_down_n  : out std_logic;
   dbnce_joy1_left_n  : out std_logic;
   dbnce_joy1_right_n : out std_logic;
   dbnce_joy1_fire_n  : out std_logic;

   joy_2_up_n         : in std_logic;
   joy_2_down_n       : in std_logic;
   joy_2_left_n       : in std_logic;
   joy_2_right_n      : in std_logic;
   joy_2_fire_n       : in std_logic;

   dbnce_joy2_up_n    : out std_logic;
   dbnce_joy2_down_n  : out std_logic;
   dbnce_joy2_left_n  : out std_logic;
   dbnce_joy2_right_n : out std_logic;
   dbnce_joy2_fire_n  : out std_logic;

   -- Amiga mice (issue #190)
   amiga_i            : in  std_logic_vector(1 downto 0);   -- '1': the socket has an Amiga mouse

   -- right click with the left button of an Amiga mouse while the MEGA key is held
   amiga_rclick_i     : in  std_logic_vector(1 downto 0);   -- '1': the switch of the socket is on
   mega_key_n_i       : in  std_logic;                      -- low active: the MEGA key is pressed

   -- paddle values of the two C64 ports as the core expects them (inverted), behind the port switcher
   pot1_x_i           : in  std_logic_vector(7 downto 0);   -- measured
   pot1_y_i           : in  std_logic_vector(7 downto 0);
   pot2_x_i           : in  std_logic_vector(7 downto 0);
   pot2_y_i           : in  std_logic_vector(7 downto 0);
   pot1_x_o           : out std_logic_vector(7 downto 0);   -- measured, or the position of an Amiga mouse
   pot1_y_o           : out std_logic_vector(7 downto 0);
   pot2_x_o           : out std_logic_vector(7 downto 0);
   pot2_y_o           : out std_logic_vector(7 downto 0)
);
end debouncer;

architecture beh of debouncer is

signal j1_u, j1_d, j1_l, j1_r, j1_f : std_logic;
signal j2_u, j2_d, j2_l, j2_r, j2_f : std_logic;

-- the debounced lines of the two sockets after the Amiga mice, before the port switcher
signal s1_u, s1_d, s1_l, s1_r, s1_f : std_logic;
signal s2_u, s2_d, s2_l, s2_r, s2_f : std_logic;

-- the two Amiga mice, indexed by socket
type pot_t is array (0 to 1) of std_logic_vector(7 downto 0);
signal meas_x, meas_y         : pot_t;    -- true measured values of the socket
signal mouse_x, mouse_y       : pot_t;    -- position as a 1351 delivers it
signal mouse_right_n          : std_logic_vector(1 downto 0);
signal mouse_middle_n         : std_logic_vector(1 downto 0);

-- right click with the MEGA key, indexed by socket
signal rclick_q               : std_logic_vector(1 downto 0) := "00";   -- decision for the current press
signal rclick                 : std_logic_vector(1 downto 0);           -- '1': the current press is a right click
signal mouse_up_n             : std_logic_vector(1 downto 0);           -- up line of a socket in Amiga mode

begin

   -- Right click with the MEGA key: while the debounced fire line (the left button) of a socket is
   -- released, rclick_q takes over whether a press would be a right click; while the line is pressed,
   -- rclick_q keeps the decision of the clock edge at which the press began
   handle_rclick : process(clk)
   begin
      if rising_edge(clk) then
         if j1_f = '1' then
            rclick_q(0) <= amiga_i(0) and amiga_rclick_i(0) and not mega_key_n_i;
         end if;
         if j2_f = '1' then
            rclick_q(1) <= amiga_i(1) and amiga_rclick_i(1) and not mega_key_n_i;
         end if;
      end if;
   end process;

   -- a press is a right click while the socket is still in Amiga mode with the switch on
   rclick(0)     <= rclick_q(0) and amiga_i(0) and amiga_rclick_i(0);
   rclick(1)     <= rclick_q(1) and amiga_i(1) and amiga_rclick_i(1);

   -- up is pressed by the right button of the mouse or by a press that is a right click
   mouse_up_n(0) <= mouse_right_n(0) and (j1_f or not rclick(0));
   mouse_up_n(1) <= mouse_right_n(1) and (j2_f or not rclick(1));

   -- Amiga mice: up is the right button, down is the middle button, left and right are released;
   -- fire is the left button, released during a right click
   s1_u <= mouse_up_n(0)     when amiga_i(0) = '1' else j1_u;
   s1_d <= mouse_middle_n(0) when amiga_i(0) = '1' else j1_d;
   s1_l <= '1'               when amiga_i(0) = '1' else j1_l;
   s1_r <= '1'               when amiga_i(0) = '1' else j1_r;
   s1_f <= j1_f or rclick(0);

   s2_u <= mouse_up_n(1)     when amiga_i(1) = '1' else j2_u;
   s2_d <= mouse_middle_n(1) when amiga_i(1) = '1' else j2_d;
   s2_l <= '1'               when amiga_i(1) = '1' else j2_l;
   s2_r <= '1'               when amiga_i(1) = '1' else j2_r;
   s2_f <= j2_f or rclick(1);

   -- assign output signals and support the flip joystick ports feature and the on/off switches
   handle_outputs: process(all)
   begin
      dbnce_joy1_up_n      <= '1';
      dbnce_joy1_down_n    <= '1';
      dbnce_joy1_left_n    <= '1';
      dbnce_joy1_right_n   <= '1';
      dbnce_joy1_fire_n    <= '1';

      dbnce_joy2_up_n      <= '1';
      dbnce_joy2_down_n    <= '1';
      dbnce_joy2_left_n    <= '1';
      dbnce_joy2_right_n   <= '1';
      dbnce_joy2_fire_n    <= '1';

      if joy_1_on then
         dbnce_joy1_up_n      <= s1_u when flip_joys_i = '0' else s2_u;
         dbnce_joy1_down_n    <= s1_d when flip_joys_i = '0' else s2_d;
         dbnce_joy1_left_n    <= s1_l when flip_joys_i = '0' else s2_l;
         dbnce_joy1_right_n   <= s1_r when flip_joys_i = '0' else s2_r;
         dbnce_joy1_fire_n    <= s1_f when flip_joys_i = '0' else s2_f;
      end if;

      if joy_2_on then
         dbnce_joy2_up_n      <= s2_u when flip_joys_i = '0' else s1_u;
         dbnce_joy2_down_n    <= s2_d when flip_joys_i = '0' else s1_d;
         dbnce_joy2_left_n    <= s2_l when flip_joys_i = '0' else s1_l;
         dbnce_joy2_right_n   <= s2_r when flip_joys_i = '0' else s1_r;
         dbnce_joy2_fire_n    <= s2_f when flip_joys_i = '0' else s1_f;
      end if;
   end process;

   -- The true measured values of each socket: the values of the C64 port that the socket is
   -- connected to, inverted. After a change of "Flip joystick ports", flip_joys_i and the switched
   -- paddle values reach this clock domain through different crossings (framework.vhd), so for a
   -- few clock cycles a mouse sees the measured values of the other socket; that cannot arm
   -- anything, because the flag "pull-up seen" and every change of a button need the confirmation
   -- time of amiga_mouse.vhd
   meas_x(0) <= not pot1_x_i when flip_joys_i = '0' else not pot2_x_i;
   meas_y(0) <= not pot1_y_i when flip_joys_i = '0' else not pot2_y_i;
   meas_x(1) <= not pot2_x_i when flip_joys_i = '0' else not pot1_x_i;
   meas_y(1) <= not pot2_y_i when flip_joys_i = '0' else not pot1_y_i;

   -- The paddle values of each C64 port: the inverted position of the mouse of the socket that is
   -- connected to the port if that socket is in Amiga mode, the measured values otherwise
   handle_paddles : process(all)
      variable s1, s2 : natural range 0 to 1;   -- the sockets connected to C64 port 1 and 2
   begin
      if flip_joys_i = '0' then
         s1 := 0;
         s2 := 1;
      else
         s1 := 1;
         s2 := 0;
      end if;

      pot1_x_o <= pot1_x_i;
      pot1_y_o <= pot1_y_i;
      pot2_x_o <= pot2_x_i;
      pot2_y_o <= pot2_y_i;

      if amiga_i(s1) = '1' then
         pot1_x_o <= not mouse_x(s1);
         pot1_y_o <= not mouse_y(s1);
      end if;

      if amiga_i(s2) = '1' then
         pot2_x_o <= not mouse_x(s2);
         pot2_y_o <= not mouse_y(s2);
      end if;
   end process;

   i_amiga_mouse_1 : entity work.amiga_mouse
      generic map (
         G_CLK_FREQ     => CLK_FREQ
      )
      port map (
         clk_i          => clk,
         enable_i       => amiga_i(0),
         up_n_i         => joy_1_up_n,
         down_n_i       => joy_1_down_n,
         left_n_i       => joy_1_left_n,
         right_n_i      => joy_1_right_n,
         meas_x_i       => meas_x(0),
         meas_y_i       => meas_y(0),
         pot_x_o        => mouse_x(0),
         pot_y_o        => mouse_y(0),
         right_btn_n_o  => mouse_right_n(0),
         middle_btn_n_o => mouse_middle_n(0)
      ); -- i_amiga_mouse_1

   i_amiga_mouse_2 : entity work.amiga_mouse
      generic map (
         G_CLK_FREQ     => CLK_FREQ
      )
      port map (
         clk_i          => clk,
         enable_i       => amiga_i(1),
         up_n_i         => joy_2_up_n,
         down_n_i       => joy_2_down_n,
         left_n_i       => joy_2_left_n,
         right_n_i      => joy_2_right_n,
         meas_x_i       => meas_x(1),
         meas_y_i       => meas_y(1),
         pot_x_o        => mouse_x(1),
         pot_y_o        => mouse_y(1),
         right_btn_n_o  => mouse_right_n(1),
         middle_btn_n_o => mouse_middle_n(1)
      ); -- i_amiga_mouse_2

   -- debouncer settings for the joysticks: 1 ms for all ten lines

   do_dbnce_joy1_up : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_1_up_n, result => j1_u);

   do_dbnce_joy1_down : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_1_down_n, result => j1_d);

   do_dbnce_joy1_left : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_1_left_n, result => j1_l);

   do_dbnce_joy1_right : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_1_right_n, result => j1_r);

   do_dbnce_joy1_fire : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_1_fire_n, result => j1_f);

   do_dbnce_joy2_up : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_2_up_n, result => j2_u);

   do_dbnce_joy2_down : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_2_down_n, result => j2_d);

   do_dbnce_joy2_left : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_2_left_n, result => j2_l);

   do_dbnce_joy2_right : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_2_right_n, result => j2_r);

   do_dbnce_joy2_fire : entity work.debounce
      generic map(initial => '1', clk_freq => CLK_FREQ, stable_time => 1)
      port map (clk => clk, reset_n => reset_n, button => joy_2_fire_n, result => j2_f);
end beh;
