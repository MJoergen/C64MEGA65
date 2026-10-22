-------------------------------------------------------------------------------
-- tb_dividers: accumulator dividers that derive fixed rates from the core clock
--
-- Contains verbatim copies (only the signal names of the surrounding design
-- are mapped to testbench signals) of
--
--   * the CIA time-of-day clock divider in rtl/fpga64_sid_iec.vhd
--     (sum := sum + add_value, add_value 100 for PAL and 120 for NTSC,
--     todclk toggles when sum >= clk32_speed, giving 50 or 60 Hz)
--   * iec_drive_ce_proc in CORE/vhdl/main.vhd (16 MHz chip enable for the
--     simulated 1541: nextsum := iec_dce_sum + 16000000, pulse when
--     nextsum >= clk_main_speed_i)
--
-- The modulus (clk32_speed / clk_main_speed_i) is G_MODULUS. The bench runs
-- for G_ACTUAL_HZ clock cycles after reset, which is one second of real time
-- if the clock really runs at G_ACTUAL_HZ (0 means G_ACTUAL_HZ = G_MODULUS).
-- Running with G_ACTUAL_HZ different from G_MODULUS shows what happens when
-- the clock and the modulus disagree (for example the flicker-free slow
-- clock, which deliberately keeps the nominal modulus).
--
-- Everything is counted in clock cycles; the simulated period is arbitrary.
-- Asserts that the TOD frequency and the 1541 enable rate are within
-- G_TOL_PPM (default 100 ppm = 0.01 percent) of 50/60 Hz and 16 MHz scaled by
-- G_ACTUAL_HZ / G_MODULUS (G_EXPECT_SCALED = true) or of the nominal rates
-- (G_EXPECT_SCALED = false).
--
-- Prints a final "RESULT: PASS" or "RESULT: FAIL <reason>" line.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_dividers is
   generic (
      G_MODULUS       : natural := 31527778;
      G_ACTUAL_HZ     : natural := 0;
      G_NTSC          : boolean := false;
      G_TOL_PPM       : natural := 100;
      G_EXPECT_SCALED : boolean := false
   );
end entity tb_dividers;

architecture sim of tb_dividers is

   constant C_PERIOD : time := 2 ns;   -- arbitrary, see header

   signal clk32           : std_logic := '0';
   signal running         : boolean := true;
   signal reset           : std_logic := '1';
   signal reset_core_n    : std_logic;
   signal ntscMode        : std_logic;
   signal clk32_speed     : natural;

   -- fpga64_sid_iec.vhd
   signal todclk          : std_logic := '0';

   -- main.vhd
   signal clk_main_i       : std_logic;
   signal clk_main_speed_i : natural;
   signal iec_drive_ce     : std_logic;
   signal iec_dce_sum      : integer := 0;

begin

   clk32 <= not clk32 after C_PERIOD / 2 when running else '0';
   ntscMode         <= '1' when G_NTSC else '0';
   clk32_speed      <= G_MODULUS;
   clk_main_i       <= clk32;
   clk_main_speed_i <= G_MODULUS;
   reset_core_n     <= not reset;

   ---------------------------------------------------------------------------
   -- Copy of the TOD divider process in rtl/fpga64_sid_iec.vhd
   ---------------------------------------------------------------------------
   process(all)
      variable sum       : natural;
      variable sum_max   : natural;
      variable add_value : natural;
   begin
      sum_max   := clk32_speed;
      add_value := 120 when ntscMode = '1' else 100;

      if rising_edge(clk32) then
         if reset = '1' then
            todclk <= '0';
            sum := 0;
         else
            sum := sum + add_value;
            if sum >= sum_max then
               sum := sum - sum_max;
               todclk <= not todclk;
            end if;
         end if;
      end if;
   end process;

   ---------------------------------------------------------------------------
   -- Copy of iec_drive_ce_proc in CORE/vhdl/main.vhd
   ---------------------------------------------------------------------------
   iec_drive_ce_proc : process (all)
      variable msum, nextsum : integer;
   begin
      msum    := clk_main_speed_i;
      nextsum := iec_dce_sum + 16000000;

      if rising_edge(clk_main_i) then
         iec_drive_ce <= '0';
         if reset_core_n = '0' then
            iec_dce_sum <= 0;
         else
            iec_dce_sum <= nextsum;
            if nextsum >= msum then
               iec_dce_sum  <= nextsum - msum;
               iec_drive_ce <= '1';
            end if;
         end if;
      end if;
   end process iec_drive_ce_proc;

   ---------------------------------------------------------------------------
   -- Measurement
   ---------------------------------------------------------------------------
   p_measure : process
      variable n_cycles   : natural;
      variable tod_toggle : natural := 0;
      variable ce_count   : natural := 0;
      variable max_gap    : natural := 0;
      variable min_gap    : natural := natural'high;
      variable gap        : natural := 0;
      variable seen_ce    : boolean := false;
      variable todq       : std_logic := '0';
      variable t_first    : natural := 0;   -- cycle of the first / last TOD toggle
      variable t_last     : natural := 0;
      variable tod_hz     : real;
      variable ce_hz      : real;
      variable tod_ref    : real;
      variable ce_ref     : real;
      variable tod_err    : real;
      variable ce_err     : real;
      variable scale      : real;
      variable ok         : boolean := true;
      variable msg        : line;
      variable l          : line;

      procedure put(s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure;

      function fixed(x : real; decimals : natural) return string is
         variable scl : real := 10.0 ** decimals;
         variable a   : real := abs(x);
         variable n   : integer := integer(a * scl);
         variable fr  : string(1 to decimals);
         variable r   : integer;
         variable sg  : string(1 to 1) := " ";
      begin
         if x < 0.0 and n /= 0 then sg := "-"; end if;
         r := n mod integer(scl);
         for i in decimals downto 1 loop
            fr(i) := character'val(character'pos('0') + (r mod 10));
            r := r / 10;
         end loop;
         return sg & integer'image(n / integer(scl)) & "." & fr;
      end function;

   begin
      if G_ACTUAL_HZ = 0 then
         n_cycles := G_MODULUS;
      else
         n_cycles := G_ACTUAL_HZ;
      end if;
      for i in 1 to 4 loop
         wait until rising_edge(clk32);
      end loop;
      reset <= '0';
      wait until rising_edge(clk32);   -- reset is low from this edge on
      todq := todclk;
      for i in 1 to n_cycles loop
         wait until rising_edge(clk32);
         -- sample the outputs that the previous edge produced
         if todclk /= todq then
            tod_toggle := tod_toggle + 1;
            if tod_toggle = 1 then t_first := i; end if;
            t_last := i;
         end if;
         todq := todclk;
         gap := gap + 1;
         if iec_drive_ce = '1' then
            ce_count := ce_count + 1;
            if seen_ce then
               if gap > max_gap then max_gap := gap; end if;
               if gap < min_gap then min_gap := gap; end if;
            end if;
            seen_ce := true;
            gap := 0;
         end if;
      end loop;

      scale   := real(n_cycles) / real(G_MODULUS);
      -- average rate between the first and the last toggle (two toggles per
      -- period); this avoids the quantization of counting whole toggles
      if tod_toggle >= 2 then
         tod_hz := real(tod_toggle - 1) / 2.0 * real(n_cycles) / real(t_last - t_first);
      else
         tod_hz := 0.0;
      end if;
      ce_hz   := real(ce_count);
      if G_NTSC then tod_ref := 60.0; else tod_ref := 50.0; end if;
      ce_ref  := 16.0e6;
      if G_EXPECT_SCALED then
         tod_ref := tod_ref * scale;
         ce_ref  := ce_ref * scale;
      end if;
      tod_err := (tod_hz - tod_ref) / tod_ref * 1.0e6;
      ce_err  := (ce_hz - ce_ref) / ce_ref * 1.0e6;

      if G_NTSC then put("mode              : NTSC (add_value 120)"); else put("mode              : PAL (add_value 100)"); end if;
      put("modulus           : " & integer'image(G_MODULUS));
      put("cycles simulated  : " & integer'image(n_cycles) & " (one second at " & integer'image(n_cycles) & " Hz)");
      put("TOD toggles       : " & integer'image(tod_toggle) & " in one second -> TOD clock " & fixed(tod_hz, 4) &
          " Hz, reference " & fixed(tod_ref, 4) & " Hz, error " & fixed(tod_err, 2) & " ppm");
      put("1541 CE pulses    : " & integer'image(ce_count) & " per second, reference " & fixed(ce_ref, 1) &
          ", error " & fixed(ce_err, 2) & " ppm, gap between pulses " & integer'image(min_gap) & " .. " &
          integer'image(max_gap) & " clk");

      if abs(tod_err) > real(G_TOL_PPM) then
         ok := false;
         write(msg, string'("TOD error exceeds tolerance; "));
      end if;
      if abs(ce_err) > real(G_TOL_PPM) then
         ok := false;
         write(msg, string'("1541 CE error exceeds tolerance; "));
      end if;
      if ok then
         put("RESULT: PASS");
      else
         write(l, string'("RESULT: FAIL "));
         write(l, msg.all);
         writeline(output, l);
      end if;
      running <= false;
      wait;
   end process p_measure;

end architecture sim;
