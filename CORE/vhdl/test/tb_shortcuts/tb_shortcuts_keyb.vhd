----------------------------------------------------------------------------------------------------
-- Keyboard shortcuts bench (GitHub issue #142), part 1: CORE/vhdl/keyboard.vhd
--
-- DUT: the unmodified keyboard.vhd. The bench plays the M2M keyboard scan (key_num_i cycles
-- through 0 .. 79, one key per clock cycle, key_pressed_n_i reports the state of that key) and the
-- C64's CIA1 (it scans the C64 matrix via cia1_pao_i / cia1_pbo_i in both directions).
--
-- Checks:
--   * F9 configured as Freeze: freeze_n is '0' while F9 is held and '1' after the release
--   * Shift+F9 = F10: no freeze unless F10 is configured as Freeze; then freeze_n follows F9
--   * Shift is sampled when the function key goes down: pressing or releasing Shift while the
--     function key is held does not change the resolved key (F9 stays F9, F10 stays F10)
--   * the same for F11/F12 and F13/F14, left and right Shift
--   * while F9, F11 or F13 is held, the CIA does not see the physical left or right Shift key;
--     after the release it sees them again; the Shift that cursor up and cursor left synthesize
--     stays visible while F9 is held
--   * with no function key configured as Freeze, freeze_n never goes '0'
--   * a monitor counts every falling edge of freeze_n: no extra pulses anywhere
--   * the RUN<Return> autostart (trigger_run_i) still types its first key
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_shortcuts_keyb is
end entity tb_shortcuts_keyb;

architecture sim of tb_shortcuts_keyb is

   constant C_PERIOD    : time := 10 ns;
   constant C_SCAN      : time := 80 * C_PERIOD;   -- one full scan of all 80 keys

   -- MEGA65 key numbers
   constant K_LSHIFT    : natural := 15;
   constant K_RSHIFT    : natural := 52;
   constant K_F9        : natural := 68;
   constant K_F11       : natural := 69;
   constant K_F13       : natural := 70;
   constant K_UP_CRSR   : natural := 73;
   constant K_LEFT_CRSR : natural := 74;

   -- position of keys in the C64 matrix: (row = port A bit, column = port B bit)
   constant R_LSHIFT    : natural := 1;
   constant C_LSHIFT    : natural := 7;
   constant R_RSHIFT    : natural := 6;
   constant C_RSHIFT    : natural := 4;
   constant R_R         : natural := 2;   -- the letter R (autostart)
   constant C_R         : natural := 1;

   signal clk           : std_logic := '0';
   signal running       : boolean   := true;

   signal reset         : std_logic := '1';   -- like reset_core_n at power-up (initializes the autostart)
   signal trigger_run   : std_logic := '0';
   signal key_num       : integer range 0 to 79 := 0;
   signal key_pressed_n : std_logic;
   signal sc_freeze     : std_logic_vector(5 downto 0) := "000001";
   signal pai           : std_logic_vector(7 downto 0);
   signal pao           : std_logic_vector(7 downto 0) := (others => '1');
   signal pbi           : std_logic_vector(7 downto 0);
   signal pbo           : std_logic_vector(7 downto 0) := (others => '1');
   signal restore_n     : std_logic;
   signal freeze_n      : std_logic;

   signal keys_n        : std_logic_vector(0 to 79) := (others => '1');   -- low active

   signal freeze_falls  : natural := 0;
   signal errors        : natural := 0;

begin

   clk <= not clk after C_PERIOD / 2 when running;

   dut : entity work.keyboard
      port map (
         clk_main_i      => clk,
         reset_i         => reset,
         trigger_run_i   => trigger_run,
         key_num_i       => key_num,
         key_pressed_n_i => key_pressed_n,
         sc_freeze_i     => sc_freeze,
         joy_1_up_n_i    => '1',
         joy_1_down_n_i  => '1',
         joy_1_left_n_i  => '1',
         joy_1_right_n_i => '1',
         joy_1_fire_n_i  => '1',
         joy_1_up_n_o    => open,
         joy_1_down_n_o  => open,
         joy_1_left_n_o  => open,
         joy_1_right_n_o => open,
         joy_1_fire_n_o  => open,
         joy_2_up_n_i    => '1',
         joy_2_down_n_i  => '1',
         joy_2_left_n_i  => '1',
         joy_2_right_n_i => '1',
         joy_2_fire_n_i  => '1',
         joy_2_up_n_o    => open,
         joy_2_down_n_o  => open,
         joy_2_left_n_o  => open,
         joy_2_right_n_o => open,
         joy_2_fire_n_o  => open,
         cia1_pai_o      => pai,
         cia1_pao_i      => pao,
         cia1_pbi_o      => pbi,
         cia1_pbo_i      => pbo,
         restore_n       => restore_n,
         freeze_n        => freeze_n
      );

   -- the M2M keyboard scan: one key per clock cycle
   scan_proc : process (clk)
   begin
      if rising_edge(clk) then
         if key_num = 79 then
            key_num <= 0;
         else
            key_num <= key_num + 1;
         end if;
      end if;
   end process scan_proc;
   key_pressed_n <= keys_n(key_num);

   monitor : process (clk)
      variable freeze_d : std_logic := '1';
   begin
      if rising_edge(clk) then
         if freeze_d = '1' and freeze_n = '0' then
            freeze_falls <= freeze_falls + 1;
         end if;
         freeze_d := freeze_n;
      end if;
   end process monitor;

   stimulus : process

      procedure fail(msg : string) is
      begin
         report "TB_ERROR: " & msg severity error;
         errors <= errors + 1;
         wait for 0 ns;
      end procedure;

      -- press or release keys; then wait for two full scans plus the register stages
      procedure key(k : natural; pressed : boolean) is
      begin
         if pressed then
            keys_n(k) <= '0';
         else
            keys_n(k) <= '1';
         end if;
         wait for 2 * C_SCAN + 4 * C_PERIOD;
      end procedure;

      procedure check_freeze(expected : std_logic; label_s : string) is
      begin
         if freeze_n /= expected then
            fail(label_s & ": freeze_n = " & std_logic'image(freeze_n) & ", expected " & std_logic'image(expected));
         else
            report "TB: " & label_s & ": freeze_n = " & std_logic'image(freeze_n) & " OK";
         end if;
      end procedure;

      procedure check_falls(expected : natural; label_s : string) is
      begin
         if freeze_falls /= expected then
            fail(label_s & ": " & integer'image(freeze_falls) & " falling edges of freeze_n, expected " &
                 integer'image(expected));
         end if;
      end procedure;

      -- scan the matrix position (row, col) in both directions like the CIA would
      impure function matrix_pressed(row, col : natural; dir : natural) return std_logic is
      begin
         if dir = 0 then
            return pai(row);      -- port B column driven low, read port A
         else
            return pbi(col);      -- port A row driven low, read port B
         end if;
      end function;

      procedure check_matrix(row, col : natural; expected : boolean; label_s : string) is
         variable seen : std_logic;
      begin
         for dir in 0 to 1 loop
            pao <= (others => '1');
            pbo <= (others => '1');
            if dir = 0 then
               pbo(col) <= '0';
            else
               pao(row) <= '0';
            end if;
            wait for 1 ns;
            seen := matrix_pressed(row, col, dir);
            if (seen = '0') /= expected then
               fail(label_s & ": matrix row " & integer'image(row) & " column " & integer'image(col) &
                    " reads " & std_logic'image(seen) & " (direction " & integer'image(dir) & "), expected " &
                    boolean'image(expected));
            end if;
         end loop;
         pao <= (others => '1');
         pbo <= (others => '1');
         wait for 1 ns;
         report "TB: " & label_s & ": matrix checked";
      end procedure;

      variable falls : natural;

   begin
      wait for 10 * C_PERIOD;
      reset <= '0';
      wait for 3 * C_SCAN;
      check_freeze('1', "idle");
      check_matrix(R_LSHIFT, C_LSHIFT, false, "idle, left Shift");
      check_matrix(R_RSHIFT, C_RSHIFT, false, "idle, right Shift");

      ------------------------------------------------------------------------------------------------
      -- F9 = Freeze (default)
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "000001";
      key(K_F9, true);
      check_freeze('0', "F9 = Freeze, F9 held");
      key(K_F9, false);
      check_freeze('1', "F9 = Freeze, F9 released");
      check_falls(1, "F9 = Freeze");

      -- Shift+F9 = F10 is not Freeze; the CIA sees left Shift before and after F9, not while F9 is held
      key(K_LSHIFT, true);
      check_matrix(R_LSHIFT, C_LSHIFT, true, "left Shift alone");
      check_freeze('1', "left Shift alone");
      key(K_F9, true);
      check_freeze('1', "F9 = Freeze, Shift+F9 (F10) held");
      check_matrix(R_LSHIFT, C_LSHIFT, false, "Shift+F9 held: left Shift masked");
      check_matrix(R_RSHIFT, C_RSHIFT, false, "Shift+F9 held: right Shift not seen");
      key(K_F9, false);
      check_matrix(R_LSHIFT, C_LSHIFT, true, "F9 released, left Shift still held: visible again");
      key(K_LSHIFT, false);
      check_matrix(R_LSHIFT, C_LSHIFT, false, "left Shift released");
      check_falls(1, "Shift+F9 with only F9 = Freeze");

      -- F9 goes down first, then Shift: still F9 (Freeze); Shift is masked; release F9 first
      key(K_F9, true);
      check_freeze('0', "F9 held");
      key(K_RSHIFT, true);
      check_freeze('0', "F9 held, then right Shift: still F9");
      check_matrix(R_RSHIFT, C_RSHIFT, false, "F9 held, then right Shift: right Shift masked");
      key(K_F9, false);
      check_freeze('1', "F9 released while right Shift is held");
      check_matrix(R_RSHIFT, C_RSHIFT, true, "F9 released, right Shift held: visible again");
      key(K_RSHIFT, false);
      check_falls(2, "F9 then Shift");

      ------------------------------------------------------------------------------------------------
      -- F10 = Freeze only
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "000010";
      key(K_F9, true);
      check_freeze('1', "F10 = Freeze, plain F9 held");
      key(K_LSHIFT, true);
      check_freeze('1', "F10 = Freeze, plain F9 held, then Shift: still F9");
      key(K_F9, false);
      key(K_LSHIFT, false);
      check_falls(2, "F10 = Freeze, plain F9");

      key(K_RSHIFT, true);
      key(K_F9, true);
      check_freeze('0', "F10 = Freeze, right Shift+F9 held");
      check_matrix(R_RSHIFT, C_RSHIFT, false, "right Shift+F9 held: right Shift masked");
      key(K_RSHIFT, false);
      check_freeze('0', "F10 = Freeze, Shift released while F9 is held: still F10");
      key(K_F9, false);
      check_freeze('1', "F10 = Freeze, F9 released");
      check_falls(3, "F10 = Freeze, Shift+F9");

      key(K_LSHIFT, true);
      key(K_F9, true);
      check_freeze('0', "F10 = Freeze, left Shift+F9 held");
      key(K_F9, false);
      key(K_LSHIFT, false);
      check_falls(4, "F10 = Freeze, left Shift+F9");

      ------------------------------------------------------------------------------------------------
      -- F11 / F12
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "000100";
      key(K_F11, true);
      check_freeze('0', "F11 = Freeze, F11 held");
      check_matrix(R_LSHIFT, C_LSHIFT, false, "F11 held, no Shift");
      key(K_F11, false);
      check_freeze('1', "F11 = Freeze, F11 released");
      key(K_LSHIFT, true);
      key(K_F11, true);
      check_freeze('1', "F11 = Freeze, Shift+F11 (F12) held");
      check_matrix(R_LSHIFT, C_LSHIFT, false, "Shift+F11 held: left Shift masked");
      key(K_F11, false);
      key(K_LSHIFT, false);
      check_falls(5, "F11 = Freeze");

      sc_freeze <= "001000";
      key(K_F11, true);
      check_freeze('1', "F12 = Freeze, plain F11 held");
      key(K_F11, false);
      key(K_RSHIFT, true);
      key(K_F11, true);
      check_freeze('0', "F12 = Freeze, Shift+F11 held");
      key(K_F11, false);
      check_freeze('1', "F12 = Freeze, F11 released");
      key(K_RSHIFT, false);
      check_falls(6, "F12 = Freeze");

      ------------------------------------------------------------------------------------------------
      -- F13 / F14
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "010000";
      key(K_F13, true);
      check_freeze('0', "F13 = Freeze, F13 held");
      key(K_F13, false);
      key(K_LSHIFT, true);
      key(K_F13, true);
      check_freeze('1', "F13 = Freeze, Shift+F13 (F14) held");
      check_matrix(R_LSHIFT, C_LSHIFT, false, "Shift+F13 held: left Shift masked");
      key(K_F13, false);
      check_matrix(R_LSHIFT, C_LSHIFT, true, "F13 released, left Shift held: visible again");
      key(K_LSHIFT, false);
      check_falls(7, "F13 = Freeze");

      sc_freeze <= "100000";
      key(K_F13, true);
      check_freeze('1', "F14 = Freeze, plain F13 held");
      key(K_F13, false);
      key(K_LSHIFT, true);
      key(K_F13, true);
      check_freeze('0', "F14 = Freeze, Shift+F13 held");
      key(K_F13, false);
      key(K_LSHIFT, false);
      check_freeze('1', "F14 = Freeze, released");
      check_falls(8, "F14 = Freeze");

      ------------------------------------------------------------------------------------------------
      -- two shortcut keys at once: F9 (Freeze) held, F11 (not Freeze) pressed and released
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "000001";
      key(K_F9, true);
      key(K_F11, true);
      check_freeze('0', "F9 = Freeze held, F11 pressed as well");
      key(K_F11, false);
      check_freeze('0', "F9 = Freeze held, F11 released");
      key(K_F9, false);
      check_falls(9, "F9 and F11");

      ------------------------------------------------------------------------------------------------
      -- cursor up / cursor left synthesize right Shift in the matrix: not masked
      ------------------------------------------------------------------------------------------------
      key(K_F9, true);
      key(K_UP_CRSR, true);
      check_matrix(R_RSHIFT, C_RSHIFT, true, "F9 held, cursor up: synthesized Shift visible");
      key(K_UP_CRSR, false);
      key(K_LEFT_CRSR, true);
      check_matrix(R_RSHIFT, C_RSHIFT, true, "F9 held, cursor left: synthesized Shift visible");
      key(K_RSHIFT, true);
      check_matrix(R_RSHIFT, C_RSHIFT, true, "F9 held, cursor left and right Shift: visible");
      key(K_LEFT_CRSR, false);
      check_matrix(R_RSHIFT, C_RSHIFT, false, "F9 held, right Shift only: masked");
      key(K_RSHIFT, false);
      key(K_F9, false);
      check_falls(10, "cursor keys");
      key(K_UP_CRSR, true);
      check_matrix(R_RSHIFT, C_RSHIFT, true, "cursor up alone: synthesized Shift visible");
      key(K_UP_CRSR, false);

      ------------------------------------------------------------------------------------------------
      -- no key configured as Freeze: freeze_n never goes '0'
      ------------------------------------------------------------------------------------------------
      sc_freeze <= "000000";
      falls := freeze_falls;
      for k in 0 to 2 loop
         for sh in 0 to 1 loop
            if sh = 1 then
               key(K_LSHIFT, true);
            end if;
            case k is
               when 0      => key(K_F9, true);  check_freeze('1', "no Freeze key, F9/F10");  key(K_F9, false);
               when 1      => key(K_F11, true); check_freeze('1', "no Freeze key, F11/F12"); key(K_F11, false);
               when others => key(K_F13, true); check_freeze('1', "no Freeze key, F13/F14"); key(K_F13, false);
            end case;
            if sh = 1 then
               key(K_LSHIFT, false);
            end if;
         end loop;
      end loop;
      check_falls(falls, "no key configured as Freeze");

      ------------------------------------------------------------------------------------------------
      -- RUN<Return> autostart: the first key (R) appears in the matrix
      ------------------------------------------------------------------------------------------------
      check_matrix(R_R, C_R, false, "before trigger_run: R not pressed");
      wait until rising_edge(clk);
      trigger_run <= '1';
      wait until rising_edge(clk);
      trigger_run <= '0';
      wait for 10 * C_PERIOD;
      check_matrix(R_R, C_R, true, "trigger_run: R typed");

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
