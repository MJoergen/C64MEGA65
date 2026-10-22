-------------------------------------------------------------------------------
-- tb_clk: CORE/vhdl/clk.vhd with the behavioral models of tb_clk_models.vhd
--
-- Checks the wiring of the four MMCMs, the two-level glitch-free multiplexer
-- tree and the reset generation of clk.vhd:
--
--   * main_rst_o stays '1' until all four MMCMs are locked, and rises again
--     whenever any single one of them loses lock (each one tried in turn)
--   * for each code of core_speed_i the mean period of main_clk_o equals the
--     period of the expected MMCM (doc/dev-ntsc/NTSC-SPEC.md, section 3.5):
--        "00" PAL original      100 MHz x 56.75 / 6 / 30
--        "01" PAL flicker-free  100 MHz x 60.5  / 9 / 21.375
--        "10" NTSC original     100 MHz x 36    / 5 / 22
--        "11" NTSC flicker-free 100 MHz x 47.75 / 5 / 29.125
--     The expected periods are computed here from the table of the spec, not
--     taken from clk.vhd. The codes are visited in an order that contains
--     every one of the twelve possible transitions.
--   * no high or low pulse of main_clk_o is shorter than half the period of
--     the fastest clock (a property of the glitch-free model, i.e. a check that
--     every multiplexer always switches between running clocks)
--
-- Prints a final "RESULT: PASS" or "RESULT: FAIL <reason>" line.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library unisim;
use unisim.tb_clk_ctrl_pkg.all;

entity tb_clk is
end entity tb_clk;

architecture sim of tb_clk is

   type real_vector4 is array (0 to 3) of real;
   -- CLKFBOUT_MULT_F, DIVCLK_DIVIDE, CLKOUT0_DIVIDE_F per code, from NTSC-SPEC.md section 3.3
   constant C_M : real_vector4 := (56.750, 60.500, 36.000, 47.750);
   constant C_D : real_vector4 := ( 6.0,    9.0,    5.0,    5.0  );
   constant C_O : real_vector4 := (30.000, 21.375, 22.000, 29.125);

   type string_vector4 is array (0 to 3) of string(1 to 17);
   constant C_NAME : string_vector4 := ("PAL original     ", "PAL flicker-free ",
                                        "NTSC original    ", "NTSC flicker-free");

   constant C_MEASURE_CYCLES : natural := 256;
   constant C_SETTLE_CYCLES  : natural := 8;

   -- every one of the 12 transitions between the four codes appears at least once
   type code_list_t is array (natural range <>) of natural range 0 to 3;
   constant C_SEQUENCE : code_list_t := (0, 1, 0, 2, 0, 3, 1, 2, 1, 3, 2, 3, 0, 3, 2, 1, 0);

   signal sys_clk      : std_logic := '0';
   signal core_speed   : unsigned(1 downto 0) := "00";
   signal main_clk     : std_logic;
   signal main_rst     : std_logic;
   signal running      : boolean := true;

   signal min_high     : time := 1 sec;
   signal min_low      : time := 1 sec;
   signal pulse_watch  : boolean := false;

   function period_of(code : natural) return time is
   begin
      return 10.0 * C_D(code) * C_O(code) / C_M(code) * 1 ns;
   end function period_of;

begin

   sys_clk <= not sys_clk after 5 ns when running;   -- 100 MHz

   dut : entity work.clk
      port map (
         sys_clk_i    => sys_clk,
         core_speed_i => core_speed,
         main_clk_o   => main_clk,
         main_rst_o   => main_rst
      );

   -- shortest high and low pulse of main_clk while pulse_watch is true
   pulse_monitor : process (main_clk)
      variable last_edge : time := 0 ns;
   begin
      if main_clk'event and (main_clk = '0' or main_clk = '1') then
         if pulse_watch and last_edge > 0 ns then
            if main_clk = '0' and now - last_edge < min_high then
               min_high <= now - last_edge;
            elsif main_clk = '1' and now - last_edge < min_low then
               min_low <= now - last_edge;
            end if;
         end if;
         last_edge := now;
      end if;
   end process pulse_monitor;

   stimulus : process
      variable l      : line;
      variable errors : natural := 0;
      variable t0     : time;
      variable meas   : time;
      variable code   : natural;
      variable fastest_half : time;

      procedure fail(msg : string) is
         variable ll : line;
      begin
         write(ll, string'("  ERROR: ") & msg);
         writeline(output, ll);
         errors := errors + 1;
      end procedure fail;

      procedure main_cycles(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(main_clk);
         end loop;
      end procedure main_cycles;

   begin
      write(l, string'("tb_clk: CORE/vhdl/clk.vhd with behavioral MMCM / BUFGMUX_CTRL / BUFG models"));
      writeline(output, l);

      -------------------------------------------------------------------------
      -- power-on: reset until all four MMCMs are locked
      -------------------------------------------------------------------------
      mmcm_hold_unlocked <= "1111";
      wait for 5 us;                               -- far beyond the lock time of the model
      if main_rst /= '1' then
         fail("main_rst_o is not '1' while no MMCM is locked");
      end if;
      for i in 0 to 3 loop
         -- release all but MMCM i
         mmcm_hold_unlocked <= (others => '0');
         mmcm_hold_unlocked(i) <= '1';
         wait for 1 us;
         if main_rst /= '1' then
            fail("main_rst_o released although MMCM " & integer'image(i) & " (" & C_NAME(i) & ") is not locked");
         end if;
         write(l, string'("  only ") & C_NAME(i) & string'(" unlocked: main_rst_o=") & std_logic'image(main_rst));
         writeline(output, l);
         mmcm_hold_unlocked <= "1111";
         wait for 100 ns;
      end loop;
      mmcm_hold_unlocked <= "0000";
      wait for 1 us;
      if main_rst /= '0' then
         fail("main_rst_o still '1' with all four MMCMs locked");
      end if;
      write(l, string'("  all four locked: main_rst_o=") & std_logic'image(main_rst));
      writeline(output, l);

      -------------------------------------------------------------------------
      -- clock selection
      -------------------------------------------------------------------------
      fastest_half := period_of(3) / 2;
      pulse_watch  <= true;
      for k in C_SEQUENCE'range loop
         code := C_SEQUENCE(k);
         core_speed <= to_unsigned(code, 2);
         main_cycles(C_SETTLE_CYCLES);
         t0 := now;
         main_cycles(C_MEASURE_CYCLES);
         meas := (now - t0) / C_MEASURE_CYCLES;
         write(l, string'("  core_speed_i=") & to_string(std_logic_vector(to_unsigned(code, 2))) &
                  string'(" ") & C_NAME(code) & string'(": main_clk_o period ") &
                  time'image(meas) & string'(", expected ") & time'image(period_of(code)));
         if abs(meas - period_of(code)) > 10 fs then
            write(l, string'("  MISMATCH"));
            errors := errors + 1;
         end if;
         writeline(output, l);
      end loop;
      pulse_watch <= false;
      wait for 0 ns;
      write(l, string'("  shortest high pulse ") & time'image(min_high) & string'(", shortest low pulse ") &
               time'image(min_low) & string'(", limit ") & time'image(fastest_half - 1 ps));
      writeline(output, l);
      if min_high < fastest_half - 1 ps or min_low < fastest_half - 1 ps then
         fail("runt pulse on main_clk_o");
      end if;

      -------------------------------------------------------------------------
      -- lock loss after power-on: any single MMCM asserts main_rst_o
      -------------------------------------------------------------------------
      for i in 0 to 3 loop
         mmcm_hold_unlocked(i) <= '1';
         wait for 200 ns;
         if main_rst /= '1' then
            fail("lock loss of MMCM " & integer'image(i) & " (" & C_NAME(i) & ") does not assert main_rst_o");
         end if;
         mmcm_hold_unlocked(i) <= '0';
         wait for 1 us;
         if main_rst /= '0' then
            fail("main_rst_o not released after MMCM " & integer'image(i) & " relocked");
         end if;
      end loop;
      write(l, string'("  single lock loss of each MMCM asserts and releases main_rst_o"));
      writeline(output, l);

      if errors = 0 then
         write(l, string'("RESULT: PASS"));
      else
         write(l, string'("RESULT: FAIL ") & integer'image(errors) & string'(" errors"));
      end if;
      writeline(output, l);
      running <= false;
      std.env.finish;                              -- the MMCM models run forever
      wait;
   end process stimulus;

end architecture sim;
