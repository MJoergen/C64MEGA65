----------------------------------------------------------------------------------------------------
-- Caps Lock bench (GitHub issue #261), part 1: the M2M keyboard chain
--
-- DUT: the unmodified M2M keyboard chain m2m_keyb -> mega65kbd_to_matrix -> matrix_to_keynum
-- (with kb_matrix_ram) at the PAL core clock. Around it a behavioral MEGA65 keyboard answers the
-- serial scan of the keyboard controller on kio10: after each sync pulse (kio8 held high) it puts
-- one bit per kio8 clock on the line, bit n = key n, low active; bit 72 is the Caps Lock state
-- that also drives the Caps Lock LED. G_OFFSET aligns the model with the sampling of
-- mega65kbd_to_matrix; the calibration step proves the alignment with an ordinary key.
--
-- Checks (G_START_ON = false):
--   * capslock_n_o stays '1' while Caps Lock is off, from power-on
--   * calibration: the key scan reports exactly the pressed key
--   * Caps Lock on: capslock_n_o goes '0' 4.0 .. 4.5 ms later (filter plus at most one frame)
--   * with the core decoupled from the keyboard (enable_core_i = '0', on-screen menu open):
--     capslock_n_o keeps following the keyboard, while key_pressed_n_o stays '1' for every key
--   * Caps Lock bit inverted for 1 frame and for 8 frames (3.7 ms): capslock_n_o does not move
--   * Caps Lock off while decoupled: capslock_n_o goes '1' 4.0 .. 4.5 ms later
--   * coupled again: the key scan reports key 72 as before (unchanged scan behavior)
-- Checks (G_START_ON = true, the LED is already on when the core starts):
--   * capslock_n_o goes '0' within 5.5 ms after power-on, once, and follows a later Caps Lock off
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_capslock_keyb is
   generic (
      G_START_ON : boolean := false;   -- Caps Lock already engaged (LED on) at power-on
      G_OFFSET   : natural := 1        -- keyboard model: bit index sent after the first kio8 clock
   );
end entity tb_capslock_keyb;

architecture sim of tb_capslock_keyb is

   constant C_CLK_SPEED : natural := 31_527_778;          -- CORE_CLK_SPEED_PAL
   constant C_PERIOD    : time    := 1 sec / C_CLK_SPEED;
   constant C_CAPS      : natural := 72;                  -- key number of Caps Lock
   constant C_CAL_KEY   : natural := 33;                  -- an ordinary key for the calibration

   signal clk           : std_logic := '0';
   signal running       : boolean   := true;

   -- DUT ports
   signal kio8          : std_logic;
   signal kio9          : std_logic;
   signal kio10         : std_logic := '1';
   signal enable_core   : std_logic := '1';
   signal key_num       : integer range 0 to 79;
   signal key_pressed_n : std_logic;
   signal capslock_n    : std_logic;
   signal qnice_keys_n  : std_logic_vector(15 downto 0);

   -- keyboard model state, driven by the stimulus
   signal keys_n        : std_logic_vector(0 to 127) := (others => '1');  -- low active
   signal caps_n        : std_logic := '1';                               -- low active: engaged
   signal glitch_frames : natural   := 0;      -- invert the Caps Lock bit in this many frames ...
   signal glitch_req    : boolean   := false;  -- ... starting with the next frame (toggle to request)

   -- monitors
   signal caps_changes  : natural := 0;
   signal caps_last_chg : time    := 0 ns;
   signal scan_on       : boolean := false;
   type pressed_t is array (0 to 79) of boolean;
   signal scan_seen     : pressed_t := (others => false);
   signal decoupled_err : natural := 0;

   signal errors        : natural := 0;

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
         power_led_i      => '1',
         power_led_col_i  => x"00FF00",
         drive_led_i      => '0',
         drive_led_col_i  => x"FFFF00",
         qnice_keys_n_o   => qnice_keys_n
      );

   -- Behavioral MEGA65 keyboard: a sync pulse is kio8 being high for much longer than one kio8 clock
   -- period (about 100 clk cycles); the first falling kio8 edge after it starts a frame. From then on
   -- every falling edge shifts the next key bit onto kio10. Before the first sync the model sends '1'.
   keyboard_model : process (clk)
      variable kio8_d      : std_logic := '1';
      variable high_cnt    : natural   := 0;
      variable sync_seen   : boolean   := false;
      variable bitpos      : integer   := -1;      -- -1: not aligned yet
      variable req_d       : boolean   := false;
      variable glitch_left : natural   := 0;
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
               if glitch_req /= req_d then
                  req_d       := glitch_req;
                  glitch_left := glitch_frames;
               elsif glitch_left > 0 then
                  glitch_left := glitch_left - 1;
               end if;
            elsif bitpos >= 0 and bitpos < 127 then
               bitpos := bitpos + 1;
            end if;
         end if;
         kio8_d := kio8;

         if bitpos < 0 then
            kio10 <= '1';
         elsif bitpos = C_CAPS then
            if glitch_left > 0 then
               kio10 <= not caps_n;
            else
               kio10 <= caps_n;
            end if;
         else
            kio10 <= keys_n(bitpos);
         end if;
      end if;
   end process keyboard_model;

   monitor : process (clk)
      variable caps_d    : std_logic := '1';
      variable scan_on_d : boolean   := false;
   begin
      if rising_edge(clk) then
         if capslock_n /= caps_d then
            caps_changes  <= caps_changes + 1;
            caps_last_chg <= now;
            report "capslock_n_o -> " & std_logic'image(capslock_n) & " at " & to_string(now, 1 us);
         end if;
         caps_d := capslock_n;

         if scan_on and not scan_on_d then
            scan_seen <= (others => false);   -- a new scan window starts
         elsif scan_on and key_pressed_n = '0' then
            scan_seen(key_num) <= true;
         end if;
         scan_on_d := scan_on;

         if enable_core = '0' and key_pressed_n = '0' then
            decoupled_err <= decoupled_err + 1;
         end if;
      end if;
   end process monitor;

   stimulus : process

      procedure fail(msg : string) is
      begin
         report "TB_ERROR: " & msg severity error;
         errors <= errors + 1;
         wait for 0 ns;
      end procedure;

      procedure wait_until(t : time) is
      begin
         if now < t then
            wait for t - now;
         end if;
      end procedure;

      procedure check_caps(expected : std_logic; label_s : string) is
      begin
         if capslock_n /= expected then
            fail(label_s & ": capslock_n_o = " & std_logic'image(capslock_n) & ", expected " & std_logic'image(expected));
         else
            report "TB: " & label_s & ": capslock_n_o = " & std_logic'image(capslock_n) & " OK";
         end if;
      end procedure;

      procedure check_changes(n : natural; label_s : string) is
      begin
         if caps_changes /= n then
            fail(label_s & ": " & integer'image(caps_changes) & " changes of capslock_n_o, expected " & integer'image(n));
         end if;
      end procedure;

      procedure check_change_time(t_lo, t_hi : time; label_s : string) is
      begin
         if caps_last_chg < t_lo or caps_last_chg > t_hi then
            fail(label_s & ": change at " & to_string(caps_last_chg, 1 us) & ", expected within " &
                 to_string(t_lo, 1 us) & " .. " & to_string(t_hi, 1 us));
         else
            report "TB: " & label_s & ": change at " & to_string(caps_last_chg, 1 us) & " OK";
         end if;
      end procedure;

      procedure scan(t_from, t_to : time; expected_key : integer; label_s : string) is
         variable n : natural := 0;
      begin
         wait_until(t_from);
         scan_on   <= true;
         wait_until(t_to);
         scan_on   <= false;
         wait for 0 ns;
         for k in 0 to 79 loop
            if scan_seen(k) then
               n := n + 1;
               if k /= expected_key then
                  fail(label_s & ": key " & integer'image(k) & " reported as pressed");
               end if;
            end if;
         end loop;
         if expected_key >= 0 and not scan_seen(expected_key) then
            fail(label_s & ": key " & integer'image(expected_key) & " not reported");
         elsif n > 0 or expected_key < 0 then
            report "TB: " & label_s & ": scan OK (" & integer'image(n) & " key(s) pressed)";
         end if;
      end procedure;

      procedure glitch(frames : natural) is
      begin
         glitch_frames <= frames;
         glitch_req    <= not glitch_req;
         wait for 0 ns;
      end procedure;

   begin
      if not G_START_ON then
         -- Caps Lock off from power-on
         wait_until(2 ms);
         keys_n(C_CAL_KEY) <= '0';
         scan(3.5 ms, 5 ms, C_CAL_KEY, "calibration");
         keys_n(C_CAL_KEY) <= '1';
         wait_until(10 ms);
         check_caps('1', "Caps Lock off since power-on");
         check_changes(0, "Caps Lock off since power-on");

         -- Caps Lock on; the on-screen menu opens while the filter is still running
         caps_n <= '0';
         wait_until(12 ms);
         enable_core <= '0';
         wait_until(13.95 ms);
         check_caps('1', "Caps Lock on, filter still running");
         wait_until(15 ms);
         check_caps('0', "Caps Lock on, menu open");
         check_changes(1, "Caps Lock on");
         check_change_time(14.0 ms, 14.5 ms, "Caps Lock on");

         -- corrupted frames on the serial keyboard link
         wait_until(20 ms);
         glitch(1);
         wait_until(30 ms);
         check_changes(1, "glitch of 1 frame");
         glitch(8);
         wait_until(40 ms);
         check_changes(1, "glitch of 8 frames");
         check_caps('0', "after the glitches");

         -- Caps Lock off while the menu is still open
         caps_n <= '1';
         wait_until(45 ms);
         check_caps('1', "Caps Lock off, menu open");
         check_changes(2, "Caps Lock off");
         check_change_time(44.0 ms, 44.5 ms, "Caps Lock off");

         -- menu closed again, Caps Lock on: the key scan still reports key 72 (unchanged behavior)
         wait_until(46 ms);
         enable_core <= '1';
         caps_n      <= '0';
         scan(47.5 ms, 50 ms, C_CAPS, "scan with Caps Lock on");
         wait_until(51 ms);
         check_caps('0', "Caps Lock on again");
         check_changes(3, "Caps Lock on again");

         if decoupled_err /= 0 then
            fail("key_pressed_n_o was '0' while the core was decoupled (" & integer'image(decoupled_err) & " cycles)");
         else
            report "TB: decoupled keyboard: key_pressed_n_o stayed '1' OK";
         end if;
      else
         -- the Caps Lock LED is already on at power-on
         caps_n <= '0';
         wait_until(3.9 ms);
         check_caps('1', "LED on at power-on, filter still running");
         wait_until(5.5 ms);
         check_caps('0', "LED on at power-on");
         check_changes(1, "LED on at power-on");
         caps_n <= '1';
         wait_until(11 ms);
         check_caps('1', "Caps Lock off after start with LED on");
         check_changes(2, "Caps Lock off after start with LED on");
         check_change_time(9.5 ms, 10.0 ms, "Caps Lock off after start with LED on");
      end if;

      wait for 0 ns;
      if errors = 0 then
         report "TB: RESULT PASS";
      else
         report "TB: RESULT FAIL (" & integer'image(errors) & " errors)";
      end if;
      running <= false;
      wait;
   end process stimulus;

end architecture sim;
