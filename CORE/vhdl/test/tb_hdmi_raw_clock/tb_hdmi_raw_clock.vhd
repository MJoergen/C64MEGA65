-------------------------------------------------------------------------------
-- tb_hdmi_raw_clock: the DRP loader of M2M/vhdl/controllers/HDMI/video_out_clock.vhd
-- (issue #184, doc/dev-hdmi-raw/SPEC.md section 4.2)
--
-- video_out_clock runs against the models of models.vhd, which print every DRP
-- access, every change of the MMCM reset and of LOCKED. The bench steps the
-- selector through a fixed sequence of codes and prints one line per step:
--
--   LOG <time in ps> SEL <code>                   the selector changes
--   LOG <time in ps> SEL2 <code>                  it changes again during the step
--   LOG <time in ps> DONE <code> <rsto> <period>  at the end of the step: rsto and
--                                                 the measured period of clko in ps
--                                                 (-1: clko does not run)
--
-- G_SEL_WIDTH = 3 runs a version of the file with the 3-bit selector:
--   power-on with 010, then 000, 001, ..., 111
-- G_SEL_WIDTH = 4 runs the version with the 4-bit selector:
--   power-on with 0010, then 0000, 0001, ..., 0111 (the same steps as above),
--   then 1000, 1001, 1010 (the tables of the raw modes), 1011 ... 1111 (codes
--   without a table of their own) and 0001 (from a code without a table back
--   to a valid one); then steps in which the selector changes a second time
--   while the first table is being loaded (or the MMCM is waiting for the lock):
--   old to old, old to new, new to a code without a table, a code without a
--   table back to an old one, and in the lock wait old to new
--
-- check_drp.py compares the logs (see there). Prints "SIMULATION DONE" at the end.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_hdmi_raw_clock is
   generic (
      G_SEL_WIDTH : natural := 4
   );
end entity tb_hdmi_raw_clock;

architecture sim of tb_hdmi_raw_clock is

   type code_list is array (natural range <>) of natural;
   constant C_CODES_3 : code_list := (2, 0, 1, 2, 3, 4, 5, 6, 7);
   constant C_CODES_4 : code_list := (2, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 1,
                                      0, 6, 10, 13, 3);
   -- second code of a step (C_NONE: none) and when it comes after the first, in ns
   constant C_NONE    : natural := 99;
   constant C_SECOND  : code_list := (C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE,
                                      C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE, C_NONE,
                                      5, 9, 12, 2, 8);
   constant C_DELAY   : code_list := (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                                      1000, 1500, 800, 2000, 4500);

   function codes return code_list is
   begin
      if G_SEL_WIDTH = 3 then
         return C_CODES_3;
      end if;
      return C_CODES_4;
   end function codes;

   constant C_CODES : code_list := codes;

   signal running : boolean := true;
   signal clki    : std_logic := '0';
   signal rsti    : std_logic := '1';
   signal sel     : std_logic_vector(G_SEL_WIDTH - 1 downto 0) :=
                    std_logic_vector(to_unsigned(C_CODES(0), G_SEL_WIDTH));
   signal rsto    : std_logic;
   signal clko    : std_logic;
   signal clko_x5 : std_logic;

   procedure log(s : string) is
      variable l : line;
   begin
      write(l, "LOG " & integer'image(integer(now / 1 ps)) & " " & s);
      writeline(output, l);
   end procedure log;

begin

   clki <= not clki after 5 ns when running else '0';     -- 100 MHz

   i_dut : entity work.video_out_clock
      generic map (
         fref    => 100.0
      )
      port map (
         rsti    => rsti,
         clki    => clki,
         sel     => sel,
         rsto    => rsto,
         clko    => clko,
         clko_x5 => clko_x5
      ); -- i_dut

   p_stim : process
      variable t1, t2 : time;
      variable period : integer;
      variable l      : line;
   begin
      for i in C_CODES'range loop
         wait until falling_edge(clki);
         sel <= std_logic_vector(to_unsigned(C_CODES(i), G_SEL_WIDTH));
         log("SEL " & to_string(std_logic_vector(to_unsigned(C_CODES(i), G_SEL_WIDTH))));
         if i = 0 then
            wait for 1 us;                                  -- power-on: M2M reset
            wait until falling_edge(clki);
            rsti <= '0';
         end if;
         if G_SEL_WIDTH = 4 and C_SECOND(i) /= C_NONE then
            wait for C_DELAY(i) * 1 ns;                     -- in the middle of the load
            wait until falling_edge(clki);
            sel <= std_logic_vector(to_unsigned(C_SECOND(i), G_SEL_WIDTH));
            log("SEL2 " & to_string(std_logic_vector(to_unsigned(C_SECOND(i), G_SEL_WIDTH))));
            wait for 14 us;                                 -- the first load ends, then the second
         end if;
         wait for 14 us;                                    -- table load (about 3 us) and lock (3 us)
         -- does clko run on the MMCM output, i.e. has the loader switched back to it?
         period := -1;
         wait until rising_edge(clko) for 100 ns;
         if rising_edge(clko) then
            t1 := now;
            wait until rising_edge(clko) for 100 ns;
            if rising_edge(clko) then
               t2 := now;
               period := integer((t2 - t1) / 1 ps);
            end if;
         end if;
         log("DONE " & to_string(sel) & " " & std_logic'image(rsto) & " " & integer'image(period));
      end loop;
      write(l, string'("SIMULATION DONE"));
      writeline(output, l);
      running <= false;
      std.env.finish;                                       -- the clocks of the MMCM model keep running
      wait;
   end process p_stim;

end architecture sim;
