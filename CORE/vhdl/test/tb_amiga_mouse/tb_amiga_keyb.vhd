----------------------------------------------------------------------------------------------------
-- Amiga mouse bench (GitHub issue #190), part 3: the MEGA key for the right click (SPEC.md
-- section 5.1)
--
-- DUT: the keyboard chain m2m_keyb -> mega65kbd_to_matrix -> matrix_to_keynum (with kb_matrix_ram)
-- at the PAL core clock. Around it the behavioral MEGA65 keyboard of ../tb_capslock: after each
-- sync pulse (kio8 held high) it puts one bit per kio8 clock on kio10, bit n = key n, low active;
-- bit 72 is the Caps Lock state. G_OFFSET aligns the model with the sampling of mega65kbd_to_matrix.
--
-- G_PART = "keyb": beside the DUT runs m2m_keyb_prev, the entity of commit 756677a (before the
-- MEGA key output), renamed by run.sh, with the same inputs; its kio8 is left to the model of the DUT.
-- Checks:
-- * at every event of an output and at every falling clock edge: kio8_o, kio9_o, key_num_o,
--   key_pressed_n_o, capslock_n_o and qnice_keys_n_o of the DUT are those of m2m_keyb_prev
-- * at every rising clock edge: mega_key_n_o is '0' or '1'; it changes only at an edge that ends a
--   clock cycle in which key_num_o is 61; at such an edge with enable_core_i at '1' it takes the
--   value of key_pressed_n_o of that cycle; before the first such edge it is '1'; while
--   enable_core_i is '0', key_pressed_n_o is '1'
-- * the MEGA key in the model, pressed and released at random phases, with enable_core_i at '1'
--   and at '0': mega_key_n_o follows within C_MAX_PRESS and C_MAX_RELEASE (the delays are measured
--   and reported);
--   with enable_core_i at '0' key_pressed_n_o stays '1'
-- * each of the other 79 key bits alone and all of them together: mega_key_n_o stays '1', while
--   the scan reports the pressed key (keys 2 to 79; bits 0 and 1 are not stored, see
--   mega65kbd_to_matrix.vhdl); with all of them held, the MEGA key still works
-- * Caps Lock and the LED inputs change now and then, so that all outputs move
-- G_START = true: the MEGA key is held from power-up.
--
-- G_PART = "e2e": the DUT and the real debouncer connected as in framework.vhd (mega_key_n_o to
-- mega_key_n_i, the same clock), socket 0 in Amiga mode with the switch on, the paddle inputs of an
-- Amiga mouse without pull-ups: the MEGA key is pressed in the keyboard model, then the fire pin of
-- socket 0 is pulled low: the up line of C64 port 1 goes low and its fire line never leaves '1',
-- also when the key is released during the press; a press without the key is a left click.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_amiga_mouse_pkg.all;

entity tb_amiga_keyb is
   generic (
      G_PART   : string   := "keyb";
      G_START  : boolean  := false;    -- the MEGA key is held from power-up
      G_OFFSET : natural  := 1;        -- keyboard model: bit index sent after the first kio8 clock
      G_SEED   : positive := 1;
      G_STOP   : boolean  := false
   );
end entity tb_amiga_keyb;

architecture sim of tb_amiga_keyb is

   constant C_CLK_SPEED : natural := 31_527_778;          -- CORE_CLK_SPEED_PAL
   constant C_PERIOD    : time    := 1 sec / C_CLK_SPEED;
   constant C_MEGA      : natural := 61;                  -- key number of the MEGA key
   constant C_CAPS      : natural := 72;                  -- key number of Caps Lock
   -- A change in the model reaches the matrix within one keyboard frame (141 x 102 clock cycles,
   -- 0.456 ms) and the register at a visit of the scan (one scan: 80 x 438 clock cycles, 1.111 ms).
   -- matrix_to_keynum reports a press at the next visit, a release only at a visit that follows a
   -- whole scan without the key: a press takes at most 1.567 ms, a release 2.678 ms.
   constant C_MAX_PRESS   : time  := 1.6 ms;
   constant C_MAX_RELEASE : time  := 2.7 ms;

   signal clk           : std_logic := '0';
   signal running       : boolean   := true;

   -- DUT and reference
   signal kio8, kio9           : std_logic;
   signal kio10                : std_logic := '1';
   signal enable_core          : std_logic := '1';
   signal key_num              : integer range 0 to 79;
   signal key_pressed_n        : std_logic;
   signal capslock_n           : std_logic;
   signal mega_n               : std_logic;
   signal qnice_keys_n         : std_logic_vector(15 downto 0);
   signal p_kio8, p_kio9       : std_logic;
   signal p_key_num            : integer range 0 to 79;
   signal p_key_pressed_n      : std_logic;
   signal p_capslock_n         : std_logic;
   signal p_qnice_keys_n       : std_logic_vector(15 downto 0);
   signal drive_led            : std_logic := '0';
   signal drive_led_col        : std_logic_vector(23 downto 0) := x"FFFF00";
   signal power_led_col        : std_logic_vector(23 downto 0) := x"00FF00";

   -- keyboard model state, driven by the stimulus: bit n = key n, low active; bit 72 = Caps Lock
   signal keys_n        : std_logic_vector(0 to 127) := (others => '1');

   -- e2e: the debouncer
   type lines_t is array (0 to 1) of std_logic_vector(4 downto 0);
   signal ln            : lines_t := (others => "11111");
   signal dj            : lines_t;
   signal pot_n         : std_logic_vector(7 downto 0) := x"00";   -- measured 255: no pull-up
   signal unused_pot    : std_logic_vector(31 downto 0);

   -- monitors
   signal visited       : boolean := false;    -- the scan was at key 61 at a rising clock edge
   signal t_change      : time    := 0 fs;     -- last change of the MEGA key in the model
   signal pending       : boolean := false;    -- that change has not reached mega_key_n_o yet
   signal d_min         : time_vector(0 to 1) := (others => 1 sec);   -- index 0: press, 1: release
   signal d_max         : time_vector(0 to 1) := (others => 0 fs);
   signal n_delays      : integer_vector(0 to 1) := (0, 0);
   signal scan_seen     : boolean_vector(0 to 79) := (others => false);
   signal scan_clear    : boolean := false;
   signal n_ident       : natural := 0;
   signal n_visits      : natural := 0;
   signal rc_low_fire   : natural := 0;        -- e2e: clock cycles with fire low during the right click
   signal in_rc         : boolean := false;

   shared variable errcnt : counter_pt;

   procedure tb_error(msg : string) is
   begin
      if errcnt.value < 30 then
         report "TB_ERROR: " & msg & " at " & to_string(now, 1 us) severity error;
      end if;
      errcnt.inc;
      if G_STOP then
         report "TB: RESULT FAIL (stopped at the first error)" severity note;
         finish;
      end if;
   end procedure tb_error;

begin

   clk <= not clk after C_PERIOD / 2 when running;

   dut : entity work.m2m_keyb
      port map (
         clk_main_i       => clk,
         clk_main_speed_i => C_CLK_SPEED,
         kio8_o           => kio8,
         kio9_o           => kio9,
         kio10_i          => kio10,
         enable_core_i    => enable_core,
         key_num_o        => key_num,
         key_pressed_n_o  => key_pressed_n,
         capslock_n_o     => capslock_n,
         mega_key_n_o     => mega_n,
         power_led_i      => '1',
         power_led_col_i  => power_led_col,
         drive_led_i      => drive_led,
         drive_led_col_i  => drive_led_col,
         qnice_keys_n_o   => qnice_keys_n
      );

   gen_keyb : if G_PART = "keyb" generate
      prev : entity work.m2m_keyb_prev
         port map (
            clk_main_i       => clk,
            clk_main_speed_i => C_CLK_SPEED,
            kio8_o           => p_kio8,
            kio9_o           => p_kio9,
            kio10_i          => kio10,
            enable_core_i    => enable_core,
            key_num_o        => p_key_num,
            key_pressed_n_o  => p_key_pressed_n,
            capslock_n_o     => p_capslock_n,
            power_led_i      => '1',
            power_led_col_i  => power_led_col,
            drive_led_i      => drive_led,
            drive_led_col_i  => drive_led_col,
            qnice_keys_n_o   => p_qnice_keys_n
         );

      identity : process
         variable n : natural := 0;
      begin
         wait on clk, kio8, kio9, key_num, key_pressed_n, capslock_n, qnice_keys_n, p_kio8, p_kio9, p_key_num,
                 p_key_pressed_n, p_capslock_n, p_qnice_keys_n;
         if not (clk'event and clk = '1') then
         wait for 1 ps;
         if kio8 /= p_kio8 or kio9 /= p_kio9 or key_num /= p_key_num or key_pressed_n /= p_key_pressed_n or
            capslock_n /= p_capslock_n or qnice_keys_n /= p_qnice_keys_n then
            tb_error("the outputs differ from m2m_keyb of 756677a: kio8 " & std_logic'image(kio8) & "/" &
                     std_logic'image(p_kio8) & ", kio9 " & std_logic'image(kio9) & "/" & std_logic'image(p_kio9) &
                     ", key_num " & integer'image(key_num) & "/" & integer'image(p_key_num) & ", key_pressed_n " &
                     std_logic'image(key_pressed_n) & "/" & std_logic'image(p_key_pressed_n) & ", capslock_n " &
                     std_logic'image(capslock_n) & "/" & std_logic'image(p_capslock_n) & ", qnice_keys_n " &
                     to_hstring(qnice_keys_n) & "/" & to_hstring(p_qnice_keys_n));
         end if;
         n := n + 1;
         n_ident <= n;
         end if;
      end process identity;
   end generate gen_keyb;

   gen_e2e : if G_PART = "e2e" generate
      i_debouncer : entity work.debouncer
         generic map (
            CLK_FREQ           => C_CLK_SPEED
         )
         port map (
            clk                => clk,
            reset_n            => '1',
            flip_joys_i        => '0',
            joy_1_on           => '1',
            joy_2_on           => '1',
            joy_1_up_n         => ln(0)(0),
            joy_1_down_n       => ln(0)(1),
            joy_1_left_n       => ln(0)(2),
            joy_1_right_n      => ln(0)(3),
            joy_1_fire_n       => ln(0)(4),
            dbnce_joy1_up_n    => dj(0)(0),
            dbnce_joy1_down_n  => dj(0)(1),
            dbnce_joy1_left_n  => dj(0)(2),
            dbnce_joy1_right_n => dj(0)(3),
            dbnce_joy1_fire_n  => dj(0)(4),
            joy_2_up_n         => ln(1)(0),
            joy_2_down_n       => ln(1)(1),
            joy_2_left_n       => ln(1)(2),
            joy_2_right_n      => ln(1)(3),
            joy_2_fire_n       => ln(1)(4),
            dbnce_joy2_up_n    => dj(1)(0),
            dbnce_joy2_down_n  => dj(1)(1),
            dbnce_joy2_left_n  => dj(1)(2),
            dbnce_joy2_right_n => dj(1)(3),
            dbnce_joy2_fire_n  => dj(1)(4),
            amiga_i            => "01",
            amiga_rclick_i     => "01",
            mega_key_n_i       => mega_n,
            pot1_x_i           => pot_n,
            pot1_y_i           => pot_n,
            pot2_x_i           => pot_n,
            pot2_y_i           => pot_n,
            pot1_x_o           => unused_pot(7 downto 0),
            pot1_y_o           => unused_pot(15 downto 8),
            pot2_x_o           => unused_pot(23 downto 16),
            pot2_y_o           => unused_pot(31 downto 24)
         );

      fire_monitor : process (clk)
      begin
         if falling_edge(clk) then
            if in_rc and dj(0)(4) /= '1' then
               rc_low_fire <= rc_low_fire + 1;
            end if;
         end if;
      end process fire_monitor;
   end generate gen_e2e;

   -- Behavioral MEGA65 keyboard of ../tb_capslock/tb_capslock_keyb.vhd: a sync pulse is kio8 being high
   -- for much longer than one kio8 clock period (about 100 clk cycles); the first falling kio8 edge after
   -- it starts a frame. From then on every falling edge shifts the next key bit onto kio10. Before the
   -- first sync the model sends '1'.
   keyboard_model : process (clk)
      variable kio8_d    : std_logic := '1';
      variable high_cnt  : natural   := 0;
      variable sync_seen : boolean   := false;
      variable bitpos    : integer   := -1;      -- -1: not aligned yet
   begin
      if rising_edge(clk) then
         if kio8 = '1' then
            high_cnt := high_cnt + 1;
         else
            high_cnt := 0;
         end if;
         if high_cnt = 300 then
            sync_seen := true;
         end if;
         if kio8_d = '1' and kio8 = '0' then
            if sync_seen then
               sync_seen := false;
               bitpos    := G_OFFSET;
            elsif bitpos >= 0 and bitpos < 127 then
               bitpos := bitpos + 1;
            end if;
         end if;
         kio8_d := kio8;

         if bitpos < 0 then
            kio10 <= '1';
         else
            kio10 <= keys_n(bitpos);
         end if;
      end if;
   end process keyboard_model;

   -- the register: at every rising edge, what the cycle before it showed
   mega_check : process
      variable kn    : integer;
      variable kp    : std_logic;
      variable en    : std_logic;
      variable m0    : std_logic;
      variable seen  : boolean := false;
      variable nv    : natural := 0;
   begin
      wait until rising_edge(clk);
      kn := key_num;
      kp := key_pressed_n;
      en := enable_core;
      m0 := mega_n;
      wait for 1 ps;
      if mega_n /= '0' and mega_n /= '1' then
         tb_error("mega_key_n_o is " & std_logic'image(mega_n));
      elsif kn /= C_MEGA and mega_n /= m0 then
         tb_error("mega_key_n_o changed at an edge after a cycle in which key_num_o was " & integer'image(kn));
      elsif kn = C_MEGA and en = '1' and mega_n /= kp then
         tb_error("mega_key_n_o is " & std_logic'image(mega_n) & " after the scan reported key 61 with " &
                  std_logic'image(kp));
      elsif not seen and kn /= C_MEGA and mega_n /= '1' then
         tb_error("mega_key_n_o is not '1' before the first visit of the scan at key 61");
      end if;
      if en = '0' and kp /= '1' then
         tb_error("key_pressed_n_o is " & std_logic'image(kp) & " while the core is decoupled");
      end if;
      if kn = C_MEGA then
         if not seen then
            report "TB: first visit of the scan at key 61 at " & to_string(now, 1 us) & ", mega_key_n_o '1' until then"
               severity note;
         end if;
         seen := true;
         nv   := nv + 1;
      end if;
      visited  <= seen;
      n_visits <= nv;
   end process mega_check;

   -- the delay from a change of the MEGA key in the model to the change of mega_key_n_o
   delay_monitor : process (mega_n)
      variable d : time;
      variable i : natural;
   begin
      if mega_n'event and (mega_n'last_value = '0' or mega_n'last_value = '1') and pending then
         d := now - t_change;
         if mega_n = '0' then
            i := 0;
         else
            i := 1;
         end if;
         if d < d_min(i) then
            d_min(i) <= d;
         end if;
         if d > d_max(i) then
            d_max(i) <= d;
         end if;
         n_delays(i) <= n_delays(i) + 1;
      end if;
   end process delay_monitor;

   -- which keys the scan reports (while the core is coupled)
   scan_monitor : process (clk)
   begin
      if rising_edge(clk) then
         if scan_clear then
            scan_seen <= (others => false);
         elsif key_pressed_n = '0' then
            scan_seen(key_num) <= true;
         end if;
      end if;
   end process scan_monitor;

   -- the LED inputs and the color change now and then, so that kio9_o carries different data
   leds : process
      variable r : rng_t := rng_init(500 + G_SEED);
      variable q : real;
      variable v : integer;
   begin
      loop
         rand_real(r, 1.0, 7.0, q);
         wait for q * 1 ms + q * 1 ns;
         drive_led <= not drive_led;
         rand_int(r, 0, 2**24 - 1, v);
         drive_led_col <= std_logic_vector(to_unsigned(v, 24));
         rand_int(r, 0, 2**24 - 1, v);
         power_led_col <= std_logic_vector(to_unsigned(v, 24));
      end loop;
   end process leds;

   ---------------------------------------------------------------------------------------------
   stimulus : process
      variable r     : rng_t := rng_init(G_SEED);
      variable q     : real;
      variable nrep  : natural := 0;

      procedure wait_until(t : time) is
      begin
         if now < t then
            wait for t - now;
         end if;
      end procedure;

      -- set the MEGA key in the model and wait until mega_key_n_o follows (or the bound passed)
      procedure mega(v : std_logic; what : string) is
         variable bound : time;
      begin
         if v = '0' then
            bound := C_MAX_PRESS;
         else
            bound := C_MAX_RELEASE;
         end if;
         if keys_n(C_MEGA) /= v then
            keys_n(C_MEGA) <= v;
            t_change <= now;
            pending  <= true;
            wait for 0 ns;
         end if;
         if mega_n /= v then
            wait until mega_n = v for bound;
         end if;
         pending <= false;
         if mega_n /= v then
            tb_error(what & ": mega_key_n_o did not become " & std_logic'image(v) & " within " &
                     to_string(bound, 1 us));
         end if;
         wait for 0 ns;
      end procedure mega;

      -- press one key or a set of keys for a while: mega_key_n_o must stay as it is
      procedure hold(mask : std_logic_vector(0 to 127); t : time; what : string) is
         variable m : std_logic;
      begin
         m := mega_n;
         keys_n <= mask;
         wait for t;
         if mega_n /= m then
            tb_error(what & ": mega_key_n_o changed to " & std_logic'image(mega_n));
         end if;
      end procedure hold;

      procedure fire(v : std_logic) is
      begin
         wait until falling_edge(clk);
         ln(0)(4) <= v;
      end procedure fire;

      variable mask  : std_logic_vector(0 to 127);
      variable nrep2 : natural := 0;
      variable nmiss : natural := 0;
   begin
      report "TB: part " & G_PART severity note;
      if G_PART = "keyb" then
         if G_START then
            keys_n(C_MEGA) <= '0';
            t_change <= 0 fs;
            pending  <= true;
            wait for 0 ns;
            wait until mega_n = '0' for 5 ms;
            if mega_n /= '0' then
               tb_error("held from power-up: mega_key_n_o did not become '0'");
            else
               report "TB: MEGA key held from power-up: mega_key_n_o '0' at " & to_string(now, 1 us) severity note;
            end if;
            pending <= false;
            wait for 1 ms;
            mega('1', "released after power-up");
         else
            wait_until(4 ms);
            if mega_n /= '1' then
               tb_error("mega_key_n_o is not '1' after power-up");
            end if;
         end if;

         -- the MEGA key at random phases, with the core coupled and decoupled
         for i in 1 to 24 loop
            if i mod 2 = 0 then
               enable_core <= '0';
            else
               enable_core <= '1';
            end if;
            rand_real(r, 0.3, 2.0, q);
            wait for q * 1 ms + q * 1 ns;
            mega('0', "MEGA key pressed");
            rand_real(r, 0.2, 2.0, q);
            wait for q * 1 ms + q * 1 ns;
            mega('1', "MEGA key released");
            nrep := nrep + 1;
            if i = 12 then
               keys_n(C_CAPS) <= '0';     -- Caps Lock on
            end if;
         end loop;
         enable_core <= '1';
         keys_n(C_CAPS) <= '1';
         wait for 3 ms;

         -- every other key alone; enable_core_i at '1', so that the scan shows that the key arrived
         for k in 0 to 79 loop
            if k /= C_MEGA then
               mask := (others => '1');
               mask(k) := '0';
               scan_clear <= true;
               wait for 2 * C_PERIOD;
               scan_clear <= false;
               hold(mask, 3 ms, "key " & integer'image(k) & " alone");
               if k >= 2 and not scan_seen(k) then
                  tb_error("key " & integer'image(k) & " was not reported by the scan");
                  nmiss := nmiss + 1;
               end if;
               if k <= 1 and scan_seen(k) then
                  report "TB: bit " & integer'image(k) & " of the keyboard frame is reported by the scan" severity note;
               end if;
               hold((others => '1'), 0.5 ms, "after key " & integer'image(k));
               nrep2 := nrep2 + 1;
            end if;
         end loop;
         report "TB: each of the other 79 key bits alone for 3 ms: mega_key_n_o stayed '1', the scan reported " &
                "each key from 2 to 79" severity note;

         -- all other keys together, then the MEGA key on top of them, coupled and decoupled
         mask := (others => '1');
         for k in 0 to 79 loop
            if k /= C_MEGA then
               mask(k) := '0';
            end if;
         end loop;
         hold(mask, 6 ms, "all other keys together");
         mega('0', "MEGA key on top of all other keys");
         wait for 1 ms;
         mega('1', "MEGA key released, all other keys held");
         enable_core <= '0';
         wait for 1 ms;
         hold(mask, 4 ms, "all other keys together, core decoupled");
         mega('0', "MEGA key on top of all other keys, core decoupled");
         wait for 1 ms;
         mega('1', "MEGA key released, all other keys held, core decoupled");
         enable_core <= '1';
         keys_n <= (others => '1');
         wait for 4 ms;
         if mega_n /= '1' then
            tb_error("mega_key_n_o is not '1' at the end");
         end if;
         report "TB: all other keys together, coupled and decoupled: mega_key_n_o stayed '1' and followed the MEGA key "
            severity note;
         report "TB: " & integer'image(n_delays(0)) & " presses of the MEGA key: mega_key_n_o followed after " &
                to_string(d_min(0), 1 us) & " to " & to_string(d_max(0), 1 us) & " (bound " &
                to_string(C_MAX_PRESS, 1 us) & "); " & integer'image(n_delays(1)) & " releases: after " &
                to_string(d_min(1), 1 us) & " to " & to_string(d_max(1), 1 us) & " (bound " &
                to_string(C_MAX_RELEASE, 1 us) & ")" severity note;
         report "TB: " & integer'image(n_visits) & " clock cycles with key_num_o at 61; " & integer'image(n_ident) &
                " comparisons with m2m_keyb of 756677a" severity note;
         if n_delays(0) < 25 or n_delays(1) < 25 then
            tb_error("too few changes of the MEGA key were measured");
         end if;
      elsif G_PART = "e2e" then
         wait_until(6 ms);    -- the debouncer and the mice settle
         if dj(0) /= "11111" then
            tb_error("C64 port 1 is not idle: " & to_string(dj(0)));
         end if;
         mega('0', "MEGA key pressed in the keyboard model");
         wait for 0.5 ms;
         in_rc <= true;
         fire('0');
         wait for 1.1 ms;
         if dj(0)(0) /= '0' or dj(0)(4) /= '1' then
            tb_error("MEGA key held, fire pin low: up " & std_logic'image(dj(0)(0)) & " fire " &
                     std_logic'image(dj(0)(4)) & ", expected a right click: up '0' fire '1'");
         else
            report "TB: MEGA key in the model, fire pin of socket 0 low: up line of C64 port 1 '0', fire line '1'"
               severity note;
         end if;
         mega('1', "MEGA key released during the press");
         wait for 1 ms;
         if dj(0)(0) /= '0' or dj(0)(4) /= '1' then
            tb_error("MEGA key released during the press: up " & std_logic'image(dj(0)(0)) & " fire " &
                     std_logic'image(dj(0)(4)) & ", expected the right click to go on");
         end if;
         fire('1');
         wait for 1.1 ms;
         in_rc <= false;
         if dj(0) /= "11111" then
            tb_error("after the right click: C64 port 1 " & to_string(dj(0)));
         end if;
         fire('0');
         wait for 1.1 ms;
         if dj(0)(0) /= '1' or dj(0)(4) /= '0' then
            tb_error("fire pin low without the MEGA key: up " & std_logic'image(dj(0)(0)) & " fire " &
                     std_logic'image(dj(0)(4)) & ", expected a left click");
         else
            report "TB: without the MEGA key: a left click (fire '0', up '1')" severity note;
         end if;
         fire('1');
         wait for 1.1 ms;
         if rc_low_fire /= 0 then
            tb_error("the fire line of C64 port 1 was low in " & integer'image(rc_low_fire) &
                     " clock cycles of the right click");
         end if;
      else
         tb_error("unknown part " & G_PART);
      end if;

      wait for 0 ns;
      if errcnt.value = 0 then
         report "TB: RESULT PASS" severity note;
      else
         report "TB: RESULT FAIL " & integer'image(errcnt.value) & " errors" severity note;
      end if;
      running <= false;
      finish;
   end process stimulus;

end architecture sim;
