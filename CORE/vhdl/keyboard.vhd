---------------------------------------------------------------------------------------------------------
-- Convert MEGA65 keystrokes to the C64 keyboard matrix that the CIA1 can scan
-- and convert the MEGA65 joystick signals to CIA1 signals as well
--
-- Runs in the clock domain of the C64 core
--
-- Interface to the MiSTer C64 core that directly connects to the C64's CIA1 instead of
-- going the detour of converting the MEGA65 keystrokes into PS/2 keystrokes first. 
-- This means, that the "fpga64_keyboard" entity of the original core is not used. Instead,
-- we are modifying the "fpga64_sid_iec" entity so that we can route the CIA1's ports
-- A and B into this keyboard driver which then emulates the behavior of the physical
-- C64 keyboard including the possibility to "scan" via the row, i.e. pull one or more bits of 
-- port A to zero (one by one) and read via the "column" (i.e. from port B) or vice versa.
--
-- This is how MiSTer2MEGA65 provides access to the MEGA65 keyboard: 
--
-- kb_key_num_i is running through the key numbers 0 to 79 with a frequency of 1 kHz, i.e. the whole
-- keyboard is scanned 1000 times per second. kb_key_pressed_n_i is already debounced and signals
-- low active, if a certain key is being pressed right now.
-- 
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
---------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard is
   port (
      clk_main_i           : in std_logic;               -- core clock
      reset_i              : in std_logic;
      
      -- Trigger the sequence RUN<Return> to autostart PRG files
      trigger_run_i        : in std_logic;
         
      -- Interface to the MEGA65 keyboard
      key_num_i            : in integer range 0 to 79;   -- cycles through all MEGA65 keys
      key_pressed_n_i      : in std_logic;               -- low active: debounced feedback: is kb_key_num_i pressed right now?
      
      -- Interface to the MEGA65 joysticks
      joy_1_up_n_i         : in std_logic;
      joy_1_down_n_i       : in std_logic;
      joy_1_left_n_i       : in std_logic;
      joy_1_right_n_i      : in std_logic;
      joy_1_fire_n_i       : in std_logic;

      joy_1_up_n_o         : out std_logic;
      joy_1_down_n_o       : out std_logic;
      joy_1_left_n_o       : out std_logic;
      joy_1_right_n_o      : out std_logic;
      joy_1_fire_n_o       : out std_logic;

      joy_2_up_n_i         : in std_logic;
      joy_2_down_n_i       : in std_logic;
      joy_2_left_n_i       : in std_logic;
      joy_2_right_n_i      : in std_logic;
      joy_2_fire_n_i       : in std_logic;      
      
      joy_2_up_n_o         : out std_logic;
      joy_2_down_n_o       : out std_logic;
      joy_2_left_n_o       : out std_logic;
      joy_2_right_n_o      : out std_logic;
      joy_2_fire_n_o       : out std_logic;

      -- Interface to the C64's CIA1         
      cia1_pai_o           : out std_logic_vector(7 downto 0);
      cia1_pao_i           : in std_logic_vector(7 downto 0);
      cia1_pbi_o           : out std_logic_vector(7 downto 0);
      cia1_pbo_i           : in std_logic_vector(7 downto 0);
      
      -- Restore key = NMI
      restore_n            : out std_logic;
      freeze_n             : out std_logic
   );
end keyboard;

architecture beh of keyboard is

-- MEGA65 key codes that kb_key_num_i is using while
-- kb_key_pressed_n_i is signalling (low active) which key is pressed
constant m65_ins_del       : integer := 0;
constant m65_return        : integer := 1;
constant m65_horz_crsr     : integer := 2;   -- means cursor right in C64 terminology
constant m65_f7            : integer := 3;
constant m65_f1            : integer := 4;
constant m65_f3            : integer := 5;
constant m65_f5            : integer := 6;
constant m65_vert_crsr     : integer := 7;   -- means cursor down in C64 terminology
constant m65_3             : integer := 8;
constant m65_w             : integer := 9;
constant m65_a             : integer := 10;
constant m65_4             : integer := 11;
constant m65_z             : integer := 12;
constant m65_s             : integer := 13;
constant m65_e             : integer := 14;
constant m65_left_shift    : integer := 15;
constant m65_5             : integer := 16;
constant m65_r             : integer := 17;
constant m65_d             : integer := 18;
constant m65_6             : integer := 19;
constant m65_c             : integer := 20;
constant m65_f             : integer := 21;
constant m65_t             : integer := 22;
constant m65_x             : integer := 23;
constant m65_7             : integer := 24;
constant m65_y             : integer := 25;
constant m65_g             : integer := 26;
constant m65_8             : integer := 27;
constant m65_b             : integer := 28;
constant m65_h             : integer := 29;
constant m65_u             : integer := 30;
constant m65_v             : integer := 31;
constant m65_9             : integer := 32;
constant m65_i             : integer := 33;
constant m65_j             : integer := 34;
constant m65_0             : integer := 35;
constant m65_m             : integer := 36;
constant m65_k             : integer := 37;
constant m65_o             : integer := 38;
constant m65_n             : integer := 39;
constant m65_plus          : integer := 40;
constant m65_p             : integer := 41; 
constant m65_l             : integer := 42;
constant m65_minus         : integer := 43;
constant m65_dot           : integer := 44;
constant m65_colon         : integer := 45;
constant m65_at            : integer := 46;
constant m65_comma         : integer := 47;
constant m65_gbp           : integer := 48;
constant m65_asterisk      : integer := 49;
constant m65_semicolon     : integer := 50;
constant m65_clr_home      : integer := 51;
constant m65_right_shift   : integer := 52;
constant m65_equal         : integer := 53;
constant m65_arrow_up      : integer := 54;  -- symbol, not cursor
constant m65_slash         : integer := 55;
constant m65_1             : integer := 56;
constant m65_arrow_left    : integer := 57;  -- symbol, not cursor
constant m65_ctrl          : integer := 58;
constant m65_2             : integer := 59;
constant m65_space         : integer := 60;
constant m65_mega          : integer := 61;
constant m65_q             : integer := 62;
constant m65_run_stop      : integer := 63;
constant m65_no_scrl       : integer := 64;
constant m65_tab           : integer := 65;
constant m65_alt           : integer := 66;
constant m65_help          : integer := 67;
constant m65_f9            : integer := 68;
constant m65_f11           : integer := 69;
constant m65_f13           : integer := 70;
constant m65_esc           : integer := 71;
constant m65_capslock      : integer := 72;
constant m65_up_crsr       : integer := 73;  -- cursor up
constant m65_left_crsr     : integer := 74;  -- cursor left
constant m65_restore       : integer := 75;

signal key_pressed_n : std_logic_vector(79 downto 0);

constant C_AK_DELAY : natural := 5_250_000; -- about 1/6 of a second
type t_autokey_state is (IDLE_ST,
                         KEYPRESS_ST,
                         TYPE_R_ST,
                         TYPE_U_ST,
                         TYPE_N_ST,
                         TYPE_RETURN_ST);
signal autokey_state : t_autokey_state := IDLE_ST;
signal autokey_next  : t_autokey_state := IDLE_ST;
signal autokey_key   : natural range 0 to 79;
signal autokey_delay : natural range 0 to C_AK_DELAY;

begin

   -- TBD: These output signals should be connected to the CIA.
   -- For now, the safe value is 1.
   joy_1_up_n_o    <= '1';
   joy_1_down_n_o  <= '1';
   joy_1_left_n_o  <= '1';
   joy_1_right_n_o <= '1';
   joy_1_fire_n_o  <= '1';
   joy_2_up_n_o    <= '1';
   joy_2_down_n_o  <= '1';
   joy_2_left_n_o  <= '1';
   joy_2_right_n_o <= '1';
   joy_2_fire_n_o  <= '1';

   restore_n   <= key_pressed_n(m65_restore);
   freeze_n    <= key_pressed_n(m65_f9);
   
   keyboard_state : process(clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         -- store currently pressed key in register
         key_pressed_n(key_num_i) <= key_pressed_n_i;
     
         if reset_i = '1' then
            autokey_state <= IDLE_ST;
            autokey_next  <= IDLE_ST;
            autokey_delay <= C_AK_DELAY;
            autokey_key   <= 1;
         end if;
         
         -- state machine to automatically type run<Return> for autostarting PRG files
         case autokey_state is
            when IDLE_ST =>
               if trigger_run_i = '1' then
                  autokey_state <= TYPE_R_ST;
               else
                  autokey_state <= IDLE_ST;
               end if;

            when KEYPRESS_ST =>
               if autokey_delay = 0 then
                  autokey_state <= autokey_next;
                  autokey_next  <= IDLE_ST;
                  autokey_delay <= C_AK_DELAY;
               else
                  key_pressed_n(autokey_key) <= '0';
                  autokey_delay <= autokey_delay - 1;
               end if;

            when TYPE_R_ST =>
               autokey_key    <= m65_r;
               autokey_next   <= TYPE_U_ST;
               autokey_state  <= KEYPRESS_ST;

            when TYPE_U_ST =>
               autokey_key    <= m65_u;
               autokey_next   <= TYPE_N_ST;
               autokey_state  <= KEYPRESS_ST;

            when TYPE_N_ST =>
               autokey_key    <= m65_n;
               autokey_next   <= TYPE_RETURN_ST;
               autokey_state  <= KEYPRESS_ST;

            when TYPE_RETURN_ST =>
               autokey_key    <= m65_return;
               autokey_next   <= IDLE_ST;
               autokey_state  <= KEYPRESS_ST;

            when others =>
               null;
         end case;
      end if;
   end process;

   ------------------------------------------------------------------------------
   -- Reading via port A and scanning (by setting bits to 0) on port B
   --
   -- This code is very similar as fpga64_keyboard.vhd. The fact that the order
   -- of the MEGA65 scancodes (constants above) and the order how they are
   -- scanned here is identical is no coincidence.
   --
   -- See also: https://www.c64-wiki.com/wiki/Keyboard#Keyboard_Matrix
   ------------------------------------------------------------------------------
    
   cia1_pai_o(0) <=  cia1_pao_i(0)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_ins_del))      and
                     (cia1_pbo_i(1) or key_pressed_n(m65_return))       and
                     
                     -- right cursor is "natural" for the C64, left cursor is emulated with RIGHT SHIFT + HORZ CRSR
                     (cia1_pbo_i(2) or (key_pressed_n(m65_horz_crsr)
                                    and key_pressed_n(m65_left_crsr)))  and
                     
                     (cia1_pbo_i(3) or key_pressed_n(m65_f7))           and
                     (cia1_pbo_i(4) or key_pressed_n(m65_f1))           and
                     (cia1_pbo_i(5) or key_pressed_n(m65_f3))           and
                     (cia1_pbo_i(6) or key_pressed_n(m65_f5))           and
                     
                     -- down cursor is "natural" for the C64, up cursor is emulated with RIGHT SHIFT + VERT CRSR
                     (cia1_pbo_i(7) or (key_pressed_n(m65_vert_crsr)    
                                    and key_pressed_n(m65_up_crsr)))    and
                     joy_2_up_n_i;

   cia1_pai_o(1) <=  cia1_pao_i(1)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_3))            and
                     (cia1_pbo_i(1) or key_pressed_n(m65_w))            and
                     (cia1_pbo_i(2) or key_pressed_n(m65_a))            and
                     (cia1_pbo_i(3) or key_pressed_n(m65_4))            and
                     (cia1_pbo_i(4) or key_pressed_n(m65_z))            and
                     (cia1_pbo_i(5) or key_pressed_n(m65_s))            and
                     (cia1_pbo_i(6) or key_pressed_n(m65_e))            and                  
                     (cia1_pbo_i(7) or key_pressed_n(m65_left_shift))   and
                     joy_2_down_n_i;

   cia1_pai_o(2) <=  cia1_pao_i(2)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_5))            and
                     (cia1_pbo_i(1) or key_pressed_n(m65_r))            and
                     (cia1_pbo_i(2) or key_pressed_n(m65_d))            and
                     (cia1_pbo_i(3) or key_pressed_n(m65_6))            and
                     (cia1_pbo_i(4) or key_pressed_n(m65_c))            and
                     (cia1_pbo_i(5) or key_pressed_n(m65_f))            and
                     (cia1_pbo_i(6) or key_pressed_n(m65_t))            and
                     (cia1_pbo_i(7) or key_pressed_n(m65_x))            and
                     joy_2_left_n_i;
                     
   cia1_pai_o(3) <=  cia1_pao_i(3)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_7))            and
                     (cia1_pbo_i(1) or key_pressed_n(m65_y))            and
                     (cia1_pbo_i(2) or key_pressed_n(m65_g))            and
                     (cia1_pbo_i(3) or key_pressed_n(m65_8))            and
                     (cia1_pbo_i(4) or key_pressed_n(m65_b))            and
                     (cia1_pbo_i(5) or key_pressed_n(m65_h))            and
                     (cia1_pbo_i(6) or key_pressed_n(m65_u))            and
                     (cia1_pbo_i(7) or key_pressed_n(m65_v))            and
                     joy_2_right_n_i;
                     
   cia1_pai_o(4) <=  cia1_pao_i(4)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_9))            and
                     (cia1_pbo_i(1) or key_pressed_n(m65_i))            and
                     (cia1_pbo_i(2) or key_pressed_n(m65_j))            and
                     (cia1_pbo_i(3) or key_pressed_n(m65_0))            and
                     (cia1_pbo_i(4) or key_pressed_n(m65_m))            and
                     (cia1_pbo_i(5) or key_pressed_n(m65_k))            and
                     (cia1_pbo_i(6) or key_pressed_n(m65_o))            and
                     (cia1_pbo_i(7) or key_pressed_n(m65_n))            and
                     joy_2_fire_n_i;
                     
   cia1_pai_o(5) <=  cia1_pao_i(5)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_plus))         and
                     (cia1_pbo_i(1) or key_pressed_n(m65_p))            and
                     (cia1_pbo_i(2) or key_pressed_n(m65_l))            and
                     (cia1_pbo_i(3) or key_pressed_n(m65_minus))        and
                     (cia1_pbo_i(4) or key_pressed_n(m65_dot))          and
                     (cia1_pbo_i(5) or key_pressed_n(m65_colon))        and
                     (cia1_pbo_i(6) or key_pressed_n(m65_at))           and
                     (cia1_pbo_i(7) or key_pressed_n(m65_comma));
                     
   cia1_pai_o(6) <=  cia1_pao_i(6)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_gbp))          and
                     (cia1_pbo_i(1) or key_pressed_n(m65_asterisk))     and
                     (cia1_pbo_i(2) or key_pressed_n(m65_semicolon))    and
                     (cia1_pbo_i(3) or key_pressed_n(m65_clr_home))     and
                     
                     -- right shift pressed or one of the "extended" arrow keys "up" and "left" of the MEGA65
                     (cia1_pbo_i(4) or (key_pressed_n(m65_right_shift)
                                    and key_pressed_n(m65_up_crsr)
                                    and key_pressed_n(m65_left_crsr)))  and
                                                               
                     (cia1_pbo_i(5) or key_pressed_n(m65_equal))        and
                     (cia1_pbo_i(6) or key_pressed_n(m65_arrow_up))     and
                     (cia1_pbo_i(7) or key_pressed_n(m65_slash));

   cia1_pai_o(7) <=  cia1_pao_i(7)                                      and
                     (cia1_pbo_i(0) or key_pressed_n(m65_1))            and
                     (cia1_pbo_i(1) or key_pressed_n(m65_arrow_left))   and
                     (cia1_pbo_i(2) or key_pressed_n(m65_ctrl))         and
                     (cia1_pbo_i(3) or key_pressed_n(m65_2))            and
                     (cia1_pbo_i(4) or key_pressed_n(m65_space))        and
                     (cia1_pbo_i(5) or key_pressed_n(m65_mega))         and
                     (cia1_pbo_i(6) or key_pressed_n(m65_q))            and
                     (cia1_pbo_i(7) or key_pressed_n(m65_run_stop));

   ------------------------------------------------------------------------------
   -- Reading via port B and scanning (by setting bits to 0) on port A
   ------------------------------------------------------------------------------
    
   cia1_pbi_o(0) <=  cia1_pbo_i(0)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_ins_del))      and
                     (cia1_pao_i(1) or key_pressed_n(m65_3))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_5))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_7))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_9))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_plus))         and
                     (cia1_pao_i(6) or key_pressed_n(m65_gbp))          and
                     (cia1_pao_i(7) or key_pressed_n(m65_1))            and
                     joy_1_up_n_i;

   cia1_pbi_o(1) <=  cia1_pbo_i(1)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_return))       and
                     (cia1_pao_i(1) or key_pressed_n(m65_w))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_r))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_y))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_i))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_p))            and
                     (cia1_pao_i(6) or key_pressed_n(m65_asterisk))     and
                     (cia1_pao_i(7) or key_pressed_n(m65_arrow_left))   and
                     joy_1_down_n_i;
                                          
                     -- right cursor is "natural" for the C64, left cursor is emulated with RIGHT SHIFT + HORZ CRSR
   cia1_pbi_o(2) <=  cia1_pbo_i(2)                                      and
                     (cia1_pao_i(0) or (key_pressed_n(m65_horz_crsr)
                                    and key_pressed_n(m65_left_crsr)))  and
                                    
                     (cia1_pao_i(1) or key_pressed_n(m65_a))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_d))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_g))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_j))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_l))            and
                     (cia1_pao_i(6) or key_pressed_n(m65_semicolon))    and
                     (cia1_pao_i(7) or key_pressed_n(m65_ctrl))         and
                     joy_1_left_n_i;
                     
   cia1_pbi_o(3) <=  cia1_pbo_i(3)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_f7))           and
                     (cia1_pao_i(1) or key_pressed_n(m65_4))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_6))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_8))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_0))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_minus))        and
                     (cia1_pao_i(6) or key_pressed_n(m65_clr_home))     and
                     (cia1_pao_i(7) or key_pressed_n(m65_2))            and
                     joy_1_right_n_i;
                     
   cia1_pbi_o(4) <=  cia1_pbo_i(4)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_f1))           and
                     (cia1_pao_i(1) or key_pressed_n(m65_z))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_c))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_b))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_m))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_dot))          and

                     -- right shift pressed or one of the "extended" arrow keys "up" and "left" of the MEGA65                     
                     (cia1_pao_i(6) or (key_pressed_n(m65_right_shift)
                                    and key_pressed_n(m65_up_crsr)
                                    and key_pressed_n(m65_left_crsr)))  and
                                          
                     (cia1_pao_i(7) or key_pressed_n(m65_space))        and
                     joy_1_fire_n_i;
                     
   cia1_pbi_o(5) <=  cia1_pbo_i(5)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_f3))           and
                     (cia1_pao_i(1) or key_pressed_n(m65_s))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_f))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_h))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_k))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_colon))        and
                     (cia1_pao_i(6) or key_pressed_n(m65_equal))        and
                     (cia1_pao_i(7) or key_pressed_n(m65_mega));
                     
   cia1_pbi_o(6) <=  cia1_pbo_i(6)                                      and
                     (cia1_pao_i(0) or key_pressed_n(m65_f5))           and
                     (cia1_pao_i(1) or key_pressed_n(m65_e))            and
                     (cia1_pao_i(2) or key_pressed_n(m65_t))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_u))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_o))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_at))           and
                     (cia1_pao_i(6) or key_pressed_n(m65_arrow_up))     and
                     (cia1_pao_i(7) or key_pressed_n(m65_q));

                     -- down cursor is "natural" for the C64, up cursor is emulated with RIGHT SHIFT + VERT CRSR
   cia1_pbi_o(7) <=  cia1_pbo_i(7)                                      and
                     (cia1_pao_i(0) or (key_pressed_n(m65_vert_crsr)
                                    and key_pressed_n(m65_up_crsr)))    and
                                    
                     (cia1_pao_i(1) or key_pressed_n(m65_left_shift))   and
                     (cia1_pao_i(2) or key_pressed_n(m65_x))            and
                     (cia1_pao_i(3) or key_pressed_n(m65_v))            and
                     (cia1_pao_i(4) or key_pressed_n(m65_n))            and
                     (cia1_pao_i(5) or key_pressed_n(m65_comma))        and
                     (cia1_pao_i(6) or key_pressed_n(m65_slash))        and
                     (cia1_pao_i(7) or key_pressed_n(m65_run_stop));                    

end architecture beh;

