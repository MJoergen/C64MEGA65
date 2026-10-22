-------------------------------------------------------------------------------
-- tb_core_speed: the hr_core_speed process of CORE/vhdl/mega65.vhd
--
-- Contains a verbatim copy of the process that selects one of the four core
-- clocks of CORE/vhdl/clk.vhd (between the BEGIN COPY / END COPY markers;
-- run_w1.sh checks that the copy still equals the process in mega65.vhd).
--
--   hr_core_speed  "00" PAL original        "01" PAL flicker-free
--                  "10" NTSC original       "11" NTSC flicker-free
--
-- hr_low_i = '1' means the core is too slow, hr_high_i = '1' means the core
-- is too fast (M2M/vhdl/hdmi_flicker_free.vhd). In PAL the original clock is
-- the faster one, in NTSC the slower one, so the polarity of bit 0 flips.
--
-- Checked:
--   * PAL:  low -> "00", high -> "01"
--   * NTSC: low -> "11", high -> "10"
--   * flicker-free off: "00" in PAL and "10" in NTSC, whatever low and high do
--   * neither low nor high keeps the value
--   * low and high in the same cycle: high wins (same priority as the
--     PAL-only process this one replaces)
--   * a change of the standard flips bit 1 in the next hr_clk cycle
--
-- Prints a final "RESULT: PASS" or "RESULT: FAIL <reason>" line.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_core_speed is
end entity tb_core_speed;

architecture sim of tb_core_speed is

   signal hr_clk_i      : std_logic := '0';
   signal hr_low_i      : std_logic := '0';
   signal hr_high_i     : std_logic := '0';
   signal hr_hdmi_ff    : std_logic := '0';
   signal hr_ntsc       : std_logic := '0';
   -- The FPGA flops power up as '0' (mega65.vhd declares hr_core_speed without an initial value)
   signal hr_core_speed : unsigned(1 downto 0) := "00";

   signal running       : boolean := true;
   signal errors        : natural := 0;
   signal checks        : natural := 0;

begin

   hr_clk_i <= not hr_clk_i after 5 ns when running;

   -- BEGIN COPY of the hr_core_speed process in CORE/vhdl/mega65.vhd
   process (hr_clk_i)
   begin
      if rising_edge(hr_clk_i) then
         hr_core_speed(1) <= hr_ntsc;                 -- 0 = PAL clocks, 1 = NTSC clocks
         if hr_low_i = '1' then                       -- the core is too slow ...
            hr_core_speed(0) <= hr_ntsc;              -- ... PAL: original (00), NTSC: flicker-free (11)
         end if;
         if hr_high_i = '1' then                      -- the core is too fast ...
            hr_core_speed(0) <= not hr_ntsc;          -- ... PAL: flicker-free (01), NTSC: original (10)
         end if;
         if hr_hdmi_ff = '0' then
            hr_core_speed(0) <= '0';                  -- flicker-free off: original clock of the standard
         end if;
      end if;
   end process;
   -- END COPY

   stimulus : process

      -- apply the inputs for n hr_clk cycles, then check the selector
      procedure step(ntsc, ff, low, high : std_logic; n : positive;
                     expected : std_logic_vector(1 downto 0); what : string) is
         variable l : line;
      begin
         hr_ntsc    <= ntsc;
         hr_hdmi_ff <= ff;
         hr_low_i   <= low;
         hr_high_i  <= high;
         for i in 1 to n loop
            wait until rising_edge(hr_clk_i);
         end loop;
         wait for 1 ns;
         checks <= checks + 1;
         write(l, string'("  ") & what & string'(": ntsc=") & std_logic'image(ntsc) &
                  string'(" ff=") & std_logic'image(ff) & string'(" low=") & std_logic'image(low) &
                  string'(" high=") & std_logic'image(high) & string'(" -> hr_core_speed=") &
                  to_string(std_logic_vector(hr_core_speed)) & string'(" (expected ") &
                  to_string(expected) & string'(")"));
         if std_logic_vector(hr_core_speed) /= expected then
            write(l, string'("  MISMATCH"));
            errors <= errors + 1;
         end if;
         writeline(output, l);
         wait for 0 ns;
      end procedure step;

      variable l : line;

   begin
      write(l, string'("tb_core_speed: hr_core_speed process of mega65.vhd"));
      writeline(output, l);

      -- PAL, flicker-free on
      step('0', '1', '0', '0', 2, "00", "PAL  idle (power-on state)");
      step('0', '1', '0', '1', 1, "01", "PAL  too fast -> PAL flicker-free");
      step('0', '1', '0', '0', 20, "01", "PAL  neither  -> keeps");
      step('0', '1', '1', '0', 1, "00", "PAL  too slow -> PAL original");
      step('0', '1', '0', '0', 20, "00", "PAL  neither  -> keeps");
      step('0', '1', '0', '1', 1, "01", "PAL  too fast -> PAL flicker-free");
      step('0', '1', '1', '1', 1, "01", "PAL  both     -> high wins");

      -- PAL, flicker-free off
      step('0', '0', '0', '0', 1, "00", "PAL  ff off   -> PAL original");
      step('0', '0', '0', '1', 3, "00", "PAL  ff off, too fast -> stays original");
      step('0', '0', '1', '0', 3, "00", "PAL  ff off, too slow -> stays original");

      -- change of the standard: bit 1 follows hr_ntsc in the next cycle
      step('1', '0', '0', '0', 1, "10", "NTSC ff off   -> NTSC original");

      -- NTSC, flicker-free off
      step('1', '0', '1', '0', 3, "10", "NTSC ff off, too slow -> stays original");
      step('1', '0', '0', '1', 3, "10", "NTSC ff off, too fast -> stays original");

      -- NTSC, flicker-free on
      step('1', '1', '0', '0', 5, "10", "NTSC ff on, neither -> keeps original");
      step('1', '1', '1', '0', 1, "11", "NTSC too slow -> NTSC flicker-free");
      step('1', '1', '0', '0', 20, "11", "NTSC neither  -> keeps");
      step('1', '1', '0', '1', 1, "10", "NTSC too fast -> NTSC original");
      step('1', '1', '0', '0', 20, "10", "NTSC neither  -> keeps");
      step('1', '1', '1', '0', 1, "11", "NTSC too slow -> NTSC flicker-free");
      step('1', '1', '1', '1', 1, "10", "NTSC both     -> high wins");

      -- standard changes while flicker-free is on: bit 1 follows at once,
      -- bit 0 is corrected by the next low/high pulse of the new standard
      step('1', '1', '1', '0', 1, "11", "NTSC too slow -> NTSC flicker-free");
      step('0', '1', '0', '0', 1, "01", "PAL  switch   -> bit 1 cleared, bit 0 kept");
      step('0', '1', '1', '0', 1, "00", "PAL  too slow -> PAL original");
      step('1', '1', '0', '0', 1, "10", "NTSC switch   -> bit 1 set, bit 0 kept");
      step('1', '1', '1', '0', 1, "11", "NTSC too slow -> NTSC flicker-free");

      -- flicker-free switched off while on the flicker-free leg
      step('1', '0', '0', '0', 1, "10", "NTSC ff off   -> NTSC original");
      step('0', '1', '0', '1', 1, "01", "PAL  too fast -> PAL flicker-free");
      step('0', '0', '0', '0', 1, "00", "PAL  ff off   -> PAL original");

      wait for 0 ns;
      write(l, string'("checks: ") & integer'image(checks) & string'(", mismatches: ") &
               integer'image(errors));
      writeline(output, l);
      if errors = 0 then
         write(l, string'("RESULT: PASS"));
      else
         write(l, string'("RESULT: FAIL ") & integer'image(errors) & string'(" mismatches"));
      end if;
      writeline(output, l);
      running <= false;
      wait;
   end process stimulus;

end architecture sim;
