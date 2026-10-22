-------------------------------------------------------------------------------
-- tb_mode_reset: the PAL/NTSC mode-change reset of CORE/vhdl/main.vhd
--
-- Contains verbatim copies of
--
--   * mode_change_reset_proc and the mode_reset assignment
--   * hard_reset_proc (to show that mode_reset reaches reset_core_int_n
--     and never hard_reset_n)
--   * the cart_soft_reset assignment
--
-- from CORE/vhdl/main.vhd, together with their declarations. run_w3.sh
-- extracts both processes from main.vhd and from this file and fails if
-- the copies differ, so the bench always tests the real code.
--
-- Cases (all counted in main clock cycles, the simulated period is arbitrary):
--
--   1. power-on with c64_ntsc_i = '0' (PAL): no pulse
--   2. one toggle PAL -> NTSC: exactly one mode_reset pulse of
--      C_MODE_RST_LEN cycles; reset_core_int_n low for the same number of
--      cycles, hard_reset_n stays '1', cart_soft_reset pulses with it
--   3. one toggle while prevent_reset = '1': no pulse while prevent_reset
--      is '1', exactly one pulse after it falls
--   4. two toggles inside one prevent_reset window: exactly one pulse
--   5. a toggle during a running pulse: the change is not lost, a second
--      pulse follows the first one
--   G_POWER_ON_NTSC = true: c64_ntsc_i = '1' from the very first cycle
--      (ntsc_d starts as PAL): exactly one pulse
--
-- Prints a final "RESULT: PASS" or "RESULT: FAIL <reason>" line.
-------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

use std.textio.all;

entity tb_mode_reset is
   generic (
      G_POWER_ON_NTSC : boolean := false
   );
end entity tb_mode_reset;

architecture simulation of tb_mode_reset is

   signal   clk_main_i         : std_logic := '0';
   signal   running            : boolean   := true;
   signal   cycle              : natural   := 0;

   -- stimuli
   signal   c64_ntsc_i         : std_logic := '0';
   signal   prevent_reset      : std_logic := '0';
   signal   reset_soft_i       : std_logic := '0';
   signal   reset_hard_i       : std_logic := '0';
   signal   cart_soft_reset_i  : std_logic := '0';

   -- declarations copied from main.vhd
   constant C_EF3_RESET_LEN    : natural                            := 7;
   signal   cart_reset_counter : natural range 0 to C_EF3_RESET_LEN := 0;
   signal   cart_soft_reset    : std_logic;
   signal   reset_core_int_n   : std_logic                          := '1';
   signal   hard_reset_n       : std_logic                          := '1';
   constant C_HARD_RST_DELAY   : natural                            := 100_000;
   signal   hard_rst_counter   : natural                            := 0;

   constant C_MODE_RST_LEN   : natural                              := 1024;
   signal   ntsc_d           : std_logic                            := '0';   -- power-on standard is PAL
   signal   mode_rst_pending : std_logic                            := '0';
   signal   mode_rst_counter : natural range 0 to C_MODE_RST_LEN    := 0;
   signal   mode_reset       : std_logic;

   -- monitor results
   signal   mr_pulses          : natural := 0;   -- number of mode_reset pulses
   signal   mr_last_len        : natural := 0;   -- length of the last completed mode_reset pulse
   signal   mr_last_start      : natural := 0;   -- cycle in which the last mode_reset pulse started
   signal   mr_bad_len         : natural := 0;   -- pulses with a length other than C_MODE_RST_LEN
   signal   mr_last_gap        : natural := 0;   -- cycles between the last two pulses
   signal   rc_pulses          : natural := 0;   -- number of reset_core_int_n low pulses
   signal   rc_last_len        : natural := 0;
   signal   cs_pulses          : natural := 0;   -- number of cart_soft_reset pulses
   signal   cs_last_len        : natural := 0;
   signal   hr_seen            : boolean := false; -- hard_reset_n was ever '0'

begin

   clk_main_i <= not clk_main_i after 5 ns when running else '0';

   ---------------------------------------------------------------------------
   -- copies from CORE/vhdl/main.vhd (keep verbatim, run_w3.sh diffs them)
   ---------------------------------------------------------------------------

  cart_soft_reset   <= (cart_soft_reset_i or mode_reset) and not prevent_reset;

  hard_reset_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      -- mode_reset is a soft reset: it reaches reset_core_n (protected by prevent_reset) but never
      -- hard_reset_n; mode_change_reset_proc only raises it while prevent_reset = '0'
      if reset_soft_i = '1' or reset_hard_i = '1' or cart_reset_counter /= 0 or mode_reset = '1' then
        -- Due to sw_cartridge_wrapper's logic, reset_soft_i stays high longer than reset_hard_i.
        -- We need to make sure that this is not interfering with hard_reset_n
        if reset_hard_i = '1' then
          hard_rst_counter <= C_HARD_RST_DELAY;
          hard_reset_n     <= '0';
        end if;

        -- reset_core_n is low-active, so prevent_reset = 0 means execute reset
        -- but a hard reset can override
        reset_core_int_n <= prevent_reset and (not reset_hard_i);
      else
        -- The idea of the hard reset is, that while reset_core_n is back at '1' and therefore the core is
        -- running (not being reset any more), hard_reset_n stays low for C_HARD_RST_DELAY clock cycles.
        -- Reason: We need to give the KERNAL time to execute the routine $FD02 where it checks for the
        -- cartridge signature "CBM80" in $8003 onwards. In case reset_n = '0' during these tests (i.e. hard
        -- reset active) we will return zero instead of "CBM80" and therefore perform a hard reset.
        reset_core_int_n <= '1';
        if hard_rst_counter = 0 then
          hard_reset_n <= '1';
        else
          hard_rst_counter <= hard_rst_counter - 1;
        end if;
      end if;
    end if;
  end process hard_reset_proc;

  -- Mode-change reset: soft-reset the C64 once per change of c64_ntsc_i, so that the KERNAL re-detects
  -- PAL/NTSC. MiSTer resets while its PLL relocks; we have four permanently running MMCMs instead, so
  -- the reset is generated here. A change that arrives while prevent_reset = '1' (a virtual drive still
  -- writes back) stays pending and fires afterwards; several changes inside that window give one reset.
  -- c64_ntsc_i is a registered OSM bit, so no synchronizer is needed. ntsc_d starts as PAL, which makes
  -- the restore of a saved NTSC setting after power-on an ordinary mode change.
  mode_change_reset_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      ntsc_d <= c64_ntsc_i;
      if ntsc_d /= c64_ntsc_i then
        mode_rst_pending <= '1';
      end if;

      if mode_rst_counter /= 0 then
        mode_rst_counter <= mode_rst_counter - 1;
      elsif mode_rst_pending = '1' and prevent_reset = '0' then
        mode_rst_counter <= C_MODE_RST_LEN;
        mode_rst_pending <= '0';
      end if;
    end if;
  end process mode_change_reset_proc;

  mode_reset <= '1' when mode_rst_counter /= 0 else '0';

   ---------------------------------------------------------------------------
   -- monitor: count pulses and their lengths, sampled on the rising edge
   ---------------------------------------------------------------------------

   monitor_proc : process (clk_main_i)
      variable mr_prev  : std_logic := '0';
      variable mr_len   : natural   := 0;
      variable mr_end   : natural   := 0;
      variable rc_prev  : std_logic := '1';
      variable rc_len   : natural   := 0;
      variable cs_prev  : std_logic := '0';
      variable cs_len   : natural   := 0;
   begin
      if rising_edge(clk_main_i) then
         cycle <= cycle + 1;

         -- mode_reset
         if mode_reset = '1' then
            if mr_prev = '0' then
               mr_pulses     <= mr_pulses + 1;
               mr_last_start <= cycle;
               if mr_pulses > 0 then
                  mr_last_gap <= cycle - mr_end;
               end if;
               mr_len := 0;
            end if;
            mr_len := mr_len + 1;
         elsif mr_prev = '1' then
            mr_last_len <= mr_len;
            mr_end      := cycle;
            if mr_len /= C_MODE_RST_LEN then
               mr_bad_len <= mr_bad_len + 1;
            end if;
         end if;
         mr_prev := mode_reset;

         -- reset_core_int_n (low active)
         if reset_core_int_n = '0' then
            if rc_prev = '1' then
               rc_pulses <= rc_pulses + 1;
               rc_len    := 0;
            end if;
            rc_len := rc_len + 1;
         elsif rc_prev = '0' then
            rc_last_len <= rc_len;
         end if;
         rc_prev := reset_core_int_n;

         -- cart_soft_reset
         if cart_soft_reset = '1' then
            if cs_prev = '0' then
               cs_pulses <= cs_pulses + 1;
               cs_len    := 0;
            end if;
            cs_len := cs_len + 1;
         elsif cs_prev = '1' then
            cs_last_len <= cs_len;
         end if;
         cs_prev := cart_soft_reset;

         if hard_reset_n = '0' then
            hr_seen <= true;
         end if;
      end if;
   end process monitor_proc;

   ---------------------------------------------------------------------------
   -- stimulus and checks
   ---------------------------------------------------------------------------

   stim_proc : process
      variable errors : natural := 0;
      variable p0     : natural;

      procedure put(msg : string) is
         variable ll : line;
      begin
         write(ll, msg);
         writeline(output, ll);
      end procedure put;

      procedure wait_cycles(n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(clk_main_i);
         end loop;
         wait for 1 ns;   -- let the monitor signals settle
      end procedure wait_cycles;

      procedure check(cond : boolean; msg : string) is
      begin
         if cond then
            put("ok   : " & msg);
         else
            put("FAIL : " & msg);
            errors := errors + 1;
         end if;
      end procedure check;

   begin
      if G_POWER_ON_NTSC then
         ------------------------------------------------------------------
         -- the standard is NTSC from the first cycle on
         ------------------------------------------------------------------
         c64_ntsc_i <= '1';
         wait_cycles(5000);
         check(mr_pulses = 1, "power-on NTSC: one pulse (got " & natural'image(mr_pulses) & ")");
         check(mr_last_len = C_MODE_RST_LEN, "power-on NTSC: pulse length " & natural'image(mr_last_len));
         check(mr_last_start <= 3, "power-on NTSC: pulse starts in cycle " & natural'image(mr_last_start));
      else
         ------------------------------------------------------------------
         -- case 1: power-on in PAL
         ------------------------------------------------------------------
         wait_cycles(5000);
         check(mr_pulses = 0, "case 1: no pulse at power-on in PAL (got " & natural'image(mr_pulses) & ")");
         check(rc_pulses = 0, "case 1: reset_core_int_n stays high");

         ------------------------------------------------------------------
         -- case 2: one toggle PAL -> NTSC
         ------------------------------------------------------------------
         p0 := cycle;
         c64_ntsc_i <= '1';
         wait_cycles(3000);
         check(mr_pulses = 1, "case 2: one pulse after one toggle (got " & natural'image(mr_pulses) & ")");
         check(mr_last_len = C_MODE_RST_LEN, "case 2: pulse length " & natural'image(mr_last_len) & " cycles");
         check(mr_last_start - p0 <= 3, "case 2: pulse starts " & natural'image(mr_last_start - p0) & " cycles after the toggle");
         check(rc_pulses = 1 and rc_last_len = C_MODE_RST_LEN,
               "case 2: reset_core_int_n low once for " & natural'image(rc_last_len) & " cycles");
         check(cs_pulses = 1 and cs_last_len = C_MODE_RST_LEN,
               "case 2: cart_soft_reset high once for " & natural'image(cs_last_len) & " cycles");
         check(not hr_seen, "case 2: hard_reset_n stays '1'");

         ------------------------------------------------------------------
         -- case 3: toggle NTSC -> PAL while prevent_reset = '1'
         ------------------------------------------------------------------
         prevent_reset <= '1';
         wait_cycles(100);
         c64_ntsc_i    <= '0';
         wait_cycles(5000);
         check(mr_pulses = 1, "case 3: no pulse while prevent_reset = '1' (pulses " & natural'image(mr_pulses) & ")");
         check(mode_rst_pending = '1', "case 3: the reset is pending");
         p0 := cycle;
         prevent_reset <= '0';
         wait_cycles(3000);
         check(mr_pulses = 2, "case 3: one pulse after prevent_reset fell (pulses " & natural'image(mr_pulses) & ")");
         check(mr_last_len = C_MODE_RST_LEN, "case 3: pulse length " & natural'image(mr_last_len));
         check(mr_last_start - p0 <= 3, "case 3: pulse starts " & natural'image(mr_last_start - p0) & " cycles after prevent_reset fell");
         check(rc_pulses = 2 and rc_last_len = C_MODE_RST_LEN, "case 3: reset_core_int_n low for " & natural'image(rc_last_len));

         ------------------------------------------------------------------
         -- case 4: two toggles inside one prevent_reset window
         ------------------------------------------------------------------
         prevent_reset <= '1';
         wait_cycles(100);
         c64_ntsc_i    <= '1';
         wait_cycles(2000);
         c64_ntsc_i    <= '0';
         wait_cycles(2000);
         check(mr_pulses = 2, "case 4: no pulse while prevent_reset = '1' (pulses " & natural'image(mr_pulses) & ")");
         prevent_reset <= '0';
         wait_cycles(5000);
         check(mr_pulses = 3, "case 4: exactly one pulse for two toggles (pulses " & natural'image(mr_pulses) & ")");
         check(mr_last_len = C_MODE_RST_LEN, "case 4: pulse length " & natural'image(mr_last_len));

         ------------------------------------------------------------------
         -- case 5: a toggle during a running pulse is not lost
         ------------------------------------------------------------------
         c64_ntsc_i <= '1';
         wait_cycles(500);
         check(mode_reset = '1', "case 5: first pulse running");
         c64_ntsc_i <= '0';
         wait_cycles(5000);
         check(mr_pulses = 5, "case 5: two pulses for two toggles (pulses " & natural'image(mr_pulses) & ")");
         check(mr_last_len = C_MODE_RST_LEN, "case 5: second pulse length " & natural'image(mr_last_len));
         put("info : case 5: gap between the two pulses " & natural'image(mr_last_gap) & " cycle(s)");

         check(mr_bad_len = 0, "all pulses are " & natural'image(C_MODE_RST_LEN) & " cycles long");
         check(not hr_seen, "hard_reset_n never asserted");
      end if;

      if errors = 0 then
         put("RESULT: PASS");
      else
         put("RESULT: FAIL " & natural'image(errors) & " check(s) failed");
      end if;
      running <= false;
      wait;
   end process stim_proc;

end architecture simulation;
