----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Bench of c1581_error_led (GitHub issue #257), see README.md
--
-- The window is scaled to C_WIN cycles; the DOS's half period of the blink is
-- half of it (the real ratio: 100 ms against 200 ms).
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use std.env.all;

entity tb_c1581_error_led is
end entity tb_c1581_error_led;

architecture sim of tb_c1581_error_led is

   constant C_WIN  : natural := 200;            -- window in cycles
   constant C_HALF : natural := C_WIN / 2;      -- half period of the blink
   constant C_CLK  : time    := 20 ns;

   signal   clk    : std_logic := '0';
   signal   pwr    : std_logic := '0';
   signal   blink  : std_logic;
   signal   errors : natural   := 0;

begin

   clk <= not clk after C_CLK / 2;

   dut : entity work.c1581_error_led
      generic map (
         G_WINDOW_CYC => C_WIN
      )
      port map (
         clk_i     => clk,
         pwr_led_i => pwr,
         blink_o   => blink
      ); -- dut

   stim_proc : process
      variable err_v : natural := 0;

      procedure cycles (n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
         end loop;
         wait for 1 ns;
      end procedure cycles;

      procedure check (cond : boolean; msg : string) is
      begin
         if not cond then
            err_v := err_v + 1;
            report "TB_ERROR: " & msg;
         end if;
      end procedure check;

      -- blink_o must stay at "level" for n cycles
      procedure hold (level : std_logic; n : natural; msg : string) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk);
            wait for 1 ns;
            if blink /= level then
               err_v := err_v + 1;
               report "TB_ERROR: " & msg & " (cycle " & integer'image(i) & ")";
               exit;
            end if;
         end loop;
      end procedure hold;
   begin
      -- 1. the drive's reset holds the LED off, then releases it: one edge is no blink
      hold('0', 3 * C_WIN, "blink while the power LED is off and steady");
      pwr <= '1';
      hold('0', 3 * C_WIN, "one edge (reset released) taken for a blink");

      -- 2. an error: the DOS toggles every half period. The third toggle starts the blink;
      --    from then on blink_o shows the power LED.
      pwr <= '0';                                    -- toggle 1
      hold('0', C_HALF, "blink after the first toggle");
      pwr <= '1';                                    -- toggle 2
      hold('0', C_HALF, "blink after the second toggle");
      pwr <= '0';                                    -- toggle 3: blinking, LED dark
      hold('0', C_HALF, "blink output lit in a dark phase");
      for i in 1 to 6 loop
         pwr <= '1';
         cycles(2);
         check(blink = '1', "lit phase not shown");
         hold('1', C_HALF - 2, "lit phase interrupted");
         pwr <= '0';
         cycles(2);
         check(blink = '0', "dark phase not shown");
         hold('0', C_HALF - 2, "dark phase interrupted");
      end loop;

      -- 3. the error is cleared while the LED is dark: the DOS leaves it dark. No blink, and
      --    when the window has passed a later single edge is no blink either.
      hold('0', 3 * C_WIN, "blink after the toggling stopped (LED left dark)");
      pwr <= '1';
      hold('0', 3 * C_WIN, "one edge after an error taken for a blink");

      -- 4. an error that starts while the LED is dark (the DOS left it dark after the error
      --    before): the third toggle is the first one that lights the LED, and the output
      --    shows it at once.
      pwr <= '0';
      hold('0', 3 * C_WIN, "blink with a steady dark power LED");
      pwr <= '1';                                    -- toggle 1
      hold('0', C_HALF, "blink after the first toggle (from dark)");
      pwr <= '0';                                    -- toggle 2
      hold('0', C_HALF, "blink after the second toggle (from dark)");
      pwr <= '1';                                    -- toggle 3: blinking, LED lit
      cycles(2);
      check(blink = '1', "the third toggle did not start the blink");
      hold('1', C_HALF - 2, "lit phase after the third toggle interrupted");

      -- 5. ... and it is cleared while the LED is lit: the output stays lit until the window
      --    ends, then it is off although the power LED stays on.
      pwr <= '0'; cycles(C_HALF);
      pwr <= '1';
      cycles(2);
      check(blink = '1', "second error: lit phase not shown");
      hold('1', C_WIN - 4, "the last lit phase ended before the window");
      cycles(8);
      check(blink = '0', "the output stays lit after the toggling stopped (LED left on)");
      hold('0', 3 * C_WIN, "blink with a steady lit power LED");

      -- 6. a short reset of the drive: off and on again within the window. Two edges are no
      --    blink.
      pwr <= '0'; cycles(5);
      pwr <= '1';
      hold('0', 3 * C_WIN, "a short reset pulse taken for a blink");

      -- 7. slow changes (each one after the window of the one before): never a blink
      for i in 1 to 4 loop
         pwr <= not pwr;
         hold('0', C_WIN + 10, "slow changes taken for a blink");
      end loop;

      -- 8. a row that is interrupted for longer than the window starts anew
      pwr <= '0'; cycles(C_HALF);
      pwr <= '1'; cycles(C_WIN + 10);                -- the row ends here
      pwr <= '0'; cycles(C_HALF);                    -- toggle 1 of a new row
      pwr <= '1';                                    -- toggle 2
      hold('0', C_HALF, "an interrupted row was continued");
      pwr <= '0'; cycles(C_HALF);                    -- toggle 3
      pwr <= '1';
      cycles(2);
      check(blink = '1', "the new row did not become a blink");

      errors <= err_v;
      wait for 1 ns;
      if err_v = 0 then
         report "TB: RESULT PASS";
      else
         report "TB: RESULT FAIL, " & integer'image(err_v) & " check(s) failed";
      end if;
      finish;
   end process stim_proc;

end architecture sim;
