----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Heuristics engine to detect certain cartridges by looking for a specific
-- behavior. One reason why this is necessary is the fact, that the MEGA65 R3 and
-- R3A boards cannot detect any reset requests made by a cartridge.
--
-- EasyFlash 3:
-- ============
--
-- While:
-- cart_exrom_n = 0
-- cart_game_n = 0
--
-- Detect falling edge of (cart_io1) and then check if c64_ram_we=1 and c64_ram_addr_o=x"DE00" (i.e. writing to DE00)
-- AND less than 200 clk_main_i cycles later (otherwise, if it comes later than 200 cycles, then it is not an EF3)
-- Detect falling edge of (cart_io1) and then check if c64_ram_we=1 and c64_ram_addr_o=x"DE0E" (i.e. writing to DE0E)
-- Detect rising edge of cart_io1 and AFTER that:
-- Detect next falling edge of phi2: System Address needs to be x"0108"
-- Detect next falling edge of phi2: System Address needs to be x"0109"
-- Detect next falling edge of phi2: System Address needs to be x"0013"
-- Now set is_an_EF3_standard to 1 until the next incoming reset
--
-- More details about the EF3:
-- https://github.com/MJoergen/C64MEGA65/issues/60
--
-- Turbo mode (GitHub issue #87):
-- ==============================
--
-- The last three stages expect one CPU access per falling edge of phi2, i.e. a C64 running at
-- 1 MHz. busy_o is '1' while a detection is in progress (from the write to DE00 until the
-- decision), so that main.vhd can pause the turbo mode for these few microseconds.
--
-- done by MJoergen and sy2002 in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cartridge_heuristics is
   port (
      clk_main_i           : in  std_logic;
      reset_core_n_i       : in  std_logic;   -- Active low

      cart_exrom_n_i       : in  std_logic;
      cart_game_n_i        : in  std_logic;
      cart_io1_n_i         : in  std_logic;
      cart_io2_n_i         : in  std_logic;
      c64_ram_we_i         : in  std_logic;
      c64_ram_addr_i       : in  std_logic_vector(15 downto 0);
      phi2_i               : in  std_logic;

      is_an_EF3_o          : out std_logic;
      busy_o               : out std_logic    -- detection in progress: the C64 must run at 1 MHz
   );
end entity cartridge_heuristics;

architecture synthesis of cartridge_heuristics is

   type state_t is (IDLE_ST, STAGE1_ST, STAGE2_ST, STAGE3_ST, STAGE4_ST, STAGE5_ST, DONE_ST);
   signal state_ef3 : state_t := IDLE_ST;

   -- These are for edge detection
   signal cart_io1_n_d : std_logic;
   signal cart_io2_n_d : std_logic;
   signal phi2_d       : std_logic;

   -- This is a gereric down-counter to handle timeouts while waiting for some event.
   signal counter : natural range 0 to 200*32; -- Multiply by 32, because the main clock is 32 MHz.

begin

   -- Turbo mode: a detection is in progress from STAGE1_ST to STAGE5_ST. Neither IDLE_ST nor
   -- DONE_ST (which is left only by a reset or by removing the cartridge) slows down the C64.
   busy_o <= '0' when state_ef3 = IDLE_ST or state_ef3 = DONE_ST else '1';

   p_EasyFlash_3 : process (clk_main_i)
   begin
      if rising_edge(clk_main_i) then
         -- This is for edge detection
         cart_io1_n_d <= cart_io1_n_i;
         cart_io2_n_d <= cart_io2_n_i;
         phi2_d       <= phi2_i;

         if counter > 0 then
            counter <= counter - 1;
         end if;

         case state_ef3 is
            when IDLE_ST =>
               -- Reset all heuristics
               is_an_EF3_o <= '0';

               -- Falling edge of cart_io1: Detect writing to DE00
               if cart_io1_n_d = '1' and cart_io1_n_i = '0' and c64_ram_we_i = '1' and c64_ram_addr_i = X"DE00" then
                  counter <= 200; -- Maximum 200 32 MHz clock cycles waiting time in next stage
                  state_ef3   <= STAGE1_ST;
               end if;

            when STAGE1_ST =>
               -- Falling edge of cart_io1: Detect writing to DE0E
               if cart_io1_n_d = '1' and cart_io1_n_i = '0' and c64_ram_we_i = '1' and c64_ram_addr_i = X"DE0E" then
                  state_ef3 <= STAGE2_ST;
               end if;

               if counter = 0 then
                  state_ef3 <= IDLE_ST;
               end if;

            when STAGE2_ST =>
               -- Detect rising edge of cart_io1
               if cart_io1_n_d = '0' and cart_io1_n_i = '1' then
                  state_ef3 <= STAGE3_ST;
               end if;

            when STAGE3_ST =>
               -- Detect next falling edge of phi2: system address needs to be x"0108"
               if phi2_d = '1' and phi2_i = '0' then
                  if c64_ram_addr_i = X"0108" then
                     state_ef3 <= STAGE4_ST;
                  else
                     state_ef3 <= IDLE_ST;
                  end if;
               end if;

            when STAGE4_ST =>
               -- Detect next falling edge of phi2: system address needs to be x"0109"
               if phi2_d = '1' and phi2_i = '0' then
                  if c64_ram_addr_i = X"0109" then
                     state_ef3 <= STAGE5_ST;
                  else
                     state_ef3 <= IDLE_ST;
                  end if;
               end if;

            when STAGE5_ST =>
               -- Detect next falling edge of phi2: system address needs to be x"0013"                        
               if phi2_d = '1' and phi2_i = '0' then
                  if c64_ram_addr_i = X"0013" then
                     state_ef3                <= DONE_ST;
                     is_an_EF3_o <= '1';
                  else
                     state_ef3 <= IDLE_ST;
                  end if;
               end if;

            when DONE_ST =>
               -- Stay here forever until next reset
               null;

            when others =>

         end case;

         if reset_core_n_i = '0' or cart_exrom_n_i = '1' or cart_game_n_i = '1' then
            state_ef3      <= IDLE_ST;
            is_an_EF3_o    <= '0';
         end if;
      end if;
   end process p_EasyFlash_3;

end architecture synthesis;

