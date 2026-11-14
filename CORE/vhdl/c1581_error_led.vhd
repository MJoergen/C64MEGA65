----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Error indication of a 1581 on the single drive LED of the MEGA65
--
-- A 1581 has two LEDs: the activity LED (CIA PA6) and the power LED (CIA PA5).
-- The 1581 DOS reports an error by blinking the POWER LED: while an error is
-- pending (and while it retries a failing job) it toggles PA5 every 100 ms
-- (ROM 318045-02, $CE11: every tenth 10 ms tick). When the error is cleared, the
-- DOS just stops toggling and leaves the LED wherever the last toggle put it, on
-- or off. So the level of PA5 says nothing; only the toggling does.
--
-- This module watches the power LED of one 1581 and tells when it blinks:
-- blink_o is '1' in the lit phases of the power LED while it blinks, and '0'
-- otherwise. "Blinking" starts with the third toggle of a row in which each
-- toggle follows the one before within G_WINDOW_CYC, and it ends when no toggle
-- arrived for G_WINDOW_CYC. One or two edges are not a blink: the drive's reset
-- forces the LED off and releases it again.
--
-- main.vhd lights the drive LED for the activity of the drives or for blink_o:
-- an error flashes the LED of an idle drive, which is the state a failed
-- command leaves the drive in. The LED of a busy drive stays lit.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity c1581_error_led is
   generic (
      -- Two half periods of the DOS's blink (2 x 100 ms) in cycles of clk_i. The
      -- default suits every core clock (31.4 to 32.8 MHz): 195 to 204 ms.
      G_WINDOW_CYC : natural := 6_400_000
   );
   port (
      clk_i     : in    std_logic;
      pwr_led_i : in    std_logic;   -- power LED of the 1581 (CIA PA5), '1' = lit
      blink_o   : out   std_logic    -- '1' = the power LED blinks and is lit right now
   );
end entity c1581_error_led;

architecture synthesis of c1581_error_led is

   constant C_BLINK_TOGGLES : natural := 3;                                -- toggles in a row that make a blink

   signal   pwr_d   : std_logic                          := '0';
   signal   window  : natural range 0 to G_WINDOW_CYC    := 0;             -- cycles left since the last toggle
   signal   toggles : natural range 0 to C_BLINK_TOGGLES := 0;             -- toggles in the current row (saturating)

begin

   blink_o <= pwr_led_i when toggles = C_BLINK_TOGGLES else
              '0';

   detect_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         pwr_d <= pwr_led_i;

         if pwr_led_i /= pwr_d then
            -- a toggle: it continues the row if the window of the previous one is still open
            if window = 0 then
               toggles <= 1;
            elsif toggles /= C_BLINK_TOGGLES then
               toggles <= toggles + 1;
            end if;
            window <= G_WINDOW_CYC;
         elsif window /= 0 then
            window <= window - 1;
         else
            toggles <= 0;
         end if;
      end if;
   end process detect_proc;

end architecture synthesis;
