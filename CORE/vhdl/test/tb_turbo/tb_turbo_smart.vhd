----------------------------------------------------------------------------------------------------
-- Turbo-mode bench (issue #87, TURBO-SPEC.md 3.2 and 6): Smart disk-activity detector
--
-- The process between "BEGIN COPY" and "END COPY" is a verbatim copy of the process between the
-- marker lines "-- [turbo_smart_iec_detector begin]" / "-- [turbo_smart_iec_detector end]" in
-- CORE/vhdl/main.vhd; run.sh fails if the two differ (whitespace aside). The wrapper declares the
-- signals the process reads and drives. hw_iec_clk_n_in and hw_iec_clk_n_sync are both driven from
-- the stimulus (the two-flip-flop synchronizer in front of hw_iec_clk_n_sync is outside the
-- markers and adds two clocks of latency for the real pin).
--
-- Checks (G_SPEED = clk_main_speed_i, so the timeout is G_SPEED / 2 clocks):
--   idle      lines idle at '1' from power-up and later idle at '0': turbo_disk_access stays '0'
--   edge      a falling and a rising edge on each of c64_iec_clk_out, c64_iec_clk_in and the hardware
--             IEC clock: turbo_disk_access is '1' from the first clock edge after the line edge on
--             (at the latest one clock later) and stays '1' for G_SPEED / 2 (+1) clocks
--   retrigger edges every 0.6 timeouts keep it '1' without a gap; it falls one timeout after the
--             last edge
--   glitch    a one-clock pulse on one line sets it
--   multiple  edges on all three lines in the same clock set it once
-- Prints "RESULT: PASS" or "RESULT: FAIL ...".
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_turbo_smart is
   generic (
      G_SPEED : natural := 1000
   );
end entity tb_turbo_smart;

architecture sim of tb_turbo_smart is
   constant TCLK : time := 10 ns;

   signal clk_main_i        : std_logic := '0';
   signal clk_main_speed_i  : natural   := G_SPEED;
   signal c64_iec_clk_out   : std_logic := '1';
   signal c64_iec_clk_in    : std_logic := '1';
   signal hw_iec_clk_n_in   : std_logic := '1';
   signal hw_iec_clk_n_sync : std_logic := '1';
   signal turbo_disk_access : std_logic := '0';
   signal running           : boolean := true;

   constant N : natural := G_SPEED / 2;
begin

   clk_main_i <= not clk_main_i after TCLK / 2 when running;

   -- BEGIN COPY
  -- [turbo_smart_iec_detector begin]
  turbo_smart_iec_detector_proc : process (clk_main_i)
    variable clk_out_prev : std_logic := '1';
    variable clk_in_prev  : std_logic := '1';
    variable hw_clk_prev  : std_logic := '1';
    variable timer        : natural range 0 to 2**25 - 1 := 0;
  begin
    if rising_edge(clk_main_i) then
      if c64_iec_clk_out /= clk_out_prev or c64_iec_clk_in /= clk_in_prev or hw_iec_clk_n_sync /= hw_clk_prev then
        turbo_disk_access <= '1';
        timer := clk_main_speed_i / 2;
      elsif timer /= 0 then
        timer := timer - 1;
      else
        turbo_disk_access <= '0';
      end if;
      clk_out_prev := c64_iec_clk_out;
      clk_in_prev  := c64_iec_clk_in;
      hw_clk_prev  := hw_iec_clk_n_sync;
    end if;
  end process turbo_smart_iec_detector_proc;
  -- [turbo_smart_iec_detector end]
   -- END COPY

   stim : process
      variable errors  : natural := 0;
      variable lat     : integer;
      variable hold    : integer;
      variable ok      : boolean;

      procedure tick(n : natural := 1) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk_main_i);
         end loop;
         wait for 1 ns;     -- look after the edge
      end procedure;

      procedure fail(msg : string) is
      begin
         report "FAIL: " & msg severity error;
         errors := errors + 1;
      end procedure;

      -- drive line k (0 = c64_iec_clk_out, 1 = c64_iec_clk_in, 2 = hardware IEC clock) to v
      procedure drive(k : natural; v : std_logic) is
      begin
         case k is
            when 0      => c64_iec_clk_out <= v;
            when 1      => c64_iec_clk_in  <= v;
            when others => hw_iec_clk_n_in <= v; hw_iec_clk_n_sync <= v;
         end case;
      end procedure;

      -- after an edge was applied (just before a clock edge): measure set latency and hold time
      procedure measure(what : string) is
      begin
         lat := -1;
         for i in 0 to 3 loop
            tick;
            if turbo_disk_access = '1' then
               lat := i;
               exit;
            end if;
         end loop;
         if lat < 0 or lat > 1 then
            fail(what & ": turbo_disk_access not set within one clock");
            return;
         end if;
         hold := lat + 1;
         while turbo_disk_access = '1' and hold < N + 10 loop
            tick;
            hold := hold + 1;
         end loop;
         -- hold - 1 = number of clocks turbo_disk_access stayed '1', counted from the clock edge that
         -- registered the line edge
         report what & ": set with the first clock edge after the line edge (+" & integer'image(lat) &
                "), stays 1 for " & integer'image(hold - 1) & " clocks (timeout clk_main_speed_i / 2 = " &
                integer'image(N) & ")" severity note;
         if hold - 1 < N or hold - 1 > N + 1 then
            fail(what & ": stays 1 for " & integer'image(hold - 1) & " clocks, expected " & integer'image(N) &
                 " or " & integer'image(N + 1));
         end if;
      end procedure;

      procedure quiet(what : string; n : natural) is
      begin
         for i in 1 to n loop
            tick;
            if turbo_disk_access /= '0' then
               fail(what & ": turbo_disk_access went to 1 without an edge");
               return;
            end if;
         end loop;
      end procedure;

      type name_arr is array (0 to 2) of string(1 to 15);
      constant LINE_NAME : name_arr := ("c64_iec_clk_out", "c64_iec_clk_in ", "hw IEC clock   ");
   begin
      report "Smart detector bench, clk_main_speed_i = " & integer'image(G_SPEED) &
             ", timeout = " & integer'image(N) & " clocks" severity note;

      -- idle from power-up (lines at '1')
      quiet("idle after power-up", 3 * N);

      -- each line: falling edge, then rising edge
      for k in 0 to 2 loop
         drive(k, '0');
         measure(LINE_NAME(k) & " falling");
         quiet(LINE_NAME(k) & " held low", N + 20);
         drive(k, '1');
         measure(LINE_NAME(k) & " rising");
         quiet(LINE_NAME(k) & " held high", N + 20);
      end loop;

      -- retrigger: edges every 0.6 timeouts on c64_iec_clk_in, no gap
      for j in 1 to 6 loop
         if j mod 2 = 1 then drive(1, '0'); else drive(1, '1'); end if;
         for i in 1 to (6 * N) / 10 loop
            tick;
            if turbo_disk_access /= '1' and not (j = 1 and i = 1) then
               fail("retrigger: gap after edge " & integer'image(j));
               exit;
            end if;
         end loop;
      end loop;
      -- remaining time after the last edge: it falls N (+1) clocks after that edge
      hold := (6 * N) / 10;
      while turbo_disk_access = '1' and hold < N + 10 loop
         tick;
         hold := hold + 1;
      end loop;
      report "retrigger: no gap; stays 1 for " & integer'image(hold - 1) & " clocks after the last edge" severity note;
      if hold - 1 < N or hold - 1 > N + 1 then
         fail("retrigger: stays 1 for " & integer'image(hold - 1) & " clocks after the last edge");
      end if;
      quiet("after retrigger", N + 20);

      -- one-clock glitch on c64_iec_clk_out
      drive(0, '0');
      tick;
      drive(0, '1');
      measure("one-clock glitch");
      quiet("after glitch", N + 20);

      -- all three lines in the same clock
      for k in 0 to 2 loop drive(k, '0'); end loop;
      measure("all lines at once");
      quiet("all lines held low", 3 * N);

      if errors = 0 then
         report "RESULT: PASS" severity note;
      else
         report "RESULT: FAIL " & integer'image(errors) & " check(s) failed" severity note;
      end if;
      running <= false;
      stop;
      wait;
   end process;

end architecture sim;
