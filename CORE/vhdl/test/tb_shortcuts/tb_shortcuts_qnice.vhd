----------------------------------------------------------------------------------------------------
-- Keyboard shortcuts bench (GitHub issue #142), part 2: the QNICE key bits of M2M/vhdl/m2m_keyb.vhd
--
-- DUT: the unmodified M2M keyboard chain m2m_keyb -> mega65kbd_to_matrix -> matrix_to_keynum
-- (with kb_matrix_ram) at the PAL core clock, driven by the behavioral MEGA65 keyboard of
-- ../tb_capslock/tb_capslock_keyb.vhd (after each sync pulse one bit per kio8 clock on kio10,
-- bit n = key n, low active, bit 72 = Caps Lock).
--
-- Checks: qnice_keys_n_o, low active, equals the expected vector in every step:
--   bit 10 = F9 (key 68), bit 11 = F11 (key 69), bit 12 = F13 (key 70),
--   bit 13 = Shift = left Shift (key 15) or right Shift (key 52) or both;
--   bits 14 and 15 are always '1' (a monitor checks every clock cycle);
--   the existing bits 0 to 9 are spot-checked (Return, F1, F3); the QNICE key bits do not depend
--   on enable_core_i (the Shell reads them while the core is decoupled from the keyboard).
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_shortcuts_qnice is
   generic (
      G_OFFSET   : natural := 1        -- keyboard model: bit index sent after the first kio8 clock
   );
end entity tb_shortcuts_qnice;

architecture sim of tb_shortcuts_qnice is

   constant C_CLK_SPEED : natural := 31_527_778;          -- CORE_CLK_SPEED_PAL
   constant C_PERIOD    : time    := 1 sec / C_CLK_SPEED;
   constant C_CAPS      : natural := 72;                  -- key number of Caps Lock

   -- MEGA65 key numbers
   constant K_RETURN    : natural := 1;
   constant K_F1        : natural := 4;
   constant K_F3        : natural := 5;
   constant K_LSHIFT    : natural := 15;
   constant K_RSHIFT    : natural := 52;
   constant K_F9        : natural := 68;
   constant K_F11       : natural := 69;
   constant K_F13       : natural := 70;

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

   signal unused_err    : natural := 0;
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

   -- Behavioral MEGA65 keyboard (same model as ../tb_capslock/tb_capslock_keyb.vhd, without the
   -- glitch injection, plus the dedicated phases 76 and 77 of Ins/Del and Return): a sync pulse is kio8 being high for much longer than one kio8 clock period;
   -- the first falling kio8 edge after it starts a frame, every further falling edge shifts the next
   -- key bit onto kio10. Before the first sync the model sends '1'.
   keyboard_model : process (clk)
      variable kio8_d      : std_logic := '1';
      variable high_cnt    : natural   := 0;
      variable sync_seen   : boolean   := false;
      variable bitpos      : integer   := -1;      -- -1: not aligned yet
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
         elsif bitpos = C_CAPS then
            kio10 <= '1';                -- Caps Lock off
         elsif bitpos = 76 then
            kio10 <= keys_n(0);          -- Ins/Del and Return also arrive on dedicated late phases,
         elsif bitpos = 77 then          -- which mega65kbd_to_matrix uses for key 0 and key 1
            kio10 <= keys_n(1);
         else
            kio10 <= keys_n(bitpos);
         end if;
      end if;
   end process keyboard_model;

   -- bits 14 and 15 are unused and must stay '1' all the time
   monitor : process (clk)
   begin
      if rising_edge(clk) then
         if qnice_keys_n(15 downto 14) /= "11" then
            unused_err <= unused_err + 1;
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

      -- set the pressed keys, wait until the keyboard chain has seen them, compare all 16 bits;
      -- expected is the list of QNICE bits that must be '0'
      type int_list is array (natural range <>) of integer;
      procedure step(pressed : int_list; expected : int_list; label_s : string) is
         variable k   : std_logic_vector(0 to 127) := (others => '1');
         variable exp : std_logic_vector(15 downto 0) := (others => '1');
      begin
         for i in pressed'range loop
            k(pressed(i)) := '0';
         end loop;
         for i in expected'range loop
            exp(expected(i)) := '0';
         end loop;
         keys_n <= k;
         wait for 4 ms;
         if qnice_keys_n /= exp then
            fail(label_s & ": qnice_keys_n_o = " & to_string(qnice_keys_n) & ", expected " & to_string(exp));
         else
            report "TB: " & label_s & ": qnice_keys_n_o = " & to_string(qnice_keys_n) & " OK";
         end if;
      end procedure;

      constant NONE : int_list(1 to 0) := (others => 0);

   begin
      wait for 2 ms;
      step(NONE,                      NONE,          "no key");
      step((0 => K_F9),               (0 => 10),     "F9");
      step(NONE,                      NONE,          "F9 released");
      step((0 => K_F11),              (0 => 11),     "F11");
      step((0 => K_F13),              (0 => 12),     "F13");
      step((0 => K_LSHIFT),           (0 => 13),     "left Shift");
      step((0 => K_RSHIFT),           (0 => 13),     "right Shift");
      step((K_LSHIFT, K_RSHIFT),      (0 => 13),     "both Shift keys");
      step((0 => K_RSHIFT),           (0 => 13),     "left Shift released, right Shift still held");
      step((K_RSHIFT, K_F9),          (10, 13),      "right Shift + F9 (F10)");
      step((K_LSHIFT, K_F11),         (11, 13),      "left Shift + F11 (F12)");
      step((K_LSHIFT, K_F13),         (12, 13),      "left Shift + F13 (F14)");
      step((K_F9, K_F11, K_F13),      (10, 11, 12),  "F9 + F11 + F13");
      step((K_RETURN, K_F1, K_F3),    (4, 8, 9),     "Return + F1 + F3 (existing bits)");
      enable_core <= '0';            -- on-screen menu open: the Shell still reads the keys
      step((K_LSHIFT, K_F9),          (10, 13),      "decoupled core: Shift + F9");
      step(NONE,                      NONE,          "decoupled core: released");
      enable_core <= '1';

      wait for 0 ns;
      if unused_err /= 0 then
         fail("bit 14 or 15 of qnice_keys_n_o was '0' in " & integer'image(unused_err) & " cycles");
      else
         report "TB: bits 14 and 15 stayed '1' OK";
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
