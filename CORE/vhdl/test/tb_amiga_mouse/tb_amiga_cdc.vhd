----------------------------------------------------------------------------------------------------
-- Amiga mouse benches (GitHub issues #190, #193), part 3: the clock domain crossing of the four
-- paddle values (framework.vhd, i_qnice2main_paddles) into debouncer.vhd
--
-- Source domain: 50 MHz (QNICE). A register holds the four paddle bytes and takes a new random
-- value at random intervals of 150 ns to 1.5 us (the measuring cycle is 514 us; what matters for
-- the crossing is only that every value holds for more than a few periods of the destination
-- clock). Between the register and the destination flip-flops every bit has its own routing delay
-- of 0 to 3 ns, and a bit that changes within 0.2 ns before an edge of the destination clock is
-- sampled with a random value (metastability, resolved within the cycle).
-- Destination domain: 31,527,778 Hz (the core clock), with no relation to the source clock.
--
-- Path under test, as in framework.vhd: cdc_stable (32 bits; its source register is the register
-- of this bench, followed by the routing delay) -> debouncer (two amiga_mouse, amiga_i = "00") ->
-- pot1_x_o .. pot2_y_o. Every value at the outputs has to be a value that the source held, and the
-- outputs show every source value, in order.
-- For comparison, the same delayed bits pass two flip-flops per bit (the model of the per-bit
-- synchronizers of xpm_cdc_array_single); the bench counts the clock cycles in which that model
-- shows a value that the source never held (torn values), which must occur.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_amiga_mouse_pkg.all;

entity tb_amiga_cdc is
   generic (
      G_CHANGES : natural  := 100_000;
      G_SEED    : positive := 1;
      G_STOP    : boolean  := false
   );
end entity tb_amiga_cdc;

architecture sim of tb_amiga_cdc is

   constant C_CORE_HZ  : positive := 31_527_778;
   constant C_SRC_HALF : time     := 10 ns;                        -- 50 MHz
   constant C_DST_HALF : time     := 1 sec / (2 * C_CORE_HZ);
   constant C_META     : time     := 200 ps;

   type delays_t is array (0 to 31) of time;
   function route_delays return delays_t is
      variable d : delays_t;
   begin
      for i in 0 to 31 loop
         d(i) := ((i * 37 + 11) mod 31) * 100 ps;                 -- 0 to 3 ns, fixed per bit
      end loop;
      return d;
   end function route_delays;
   constant C_ROUTE    : delays_t := route_delays;

   signal src_clk      : std_logic := '0';
   signal dst_clk      : std_logic := '0';
   signal running      : boolean   := true;

   signal src_val      : std_logic_vector(31 downto 0) := (others => '0');   -- source register
   signal src_dly      : std_logic_vector(31 downto 0) := (others => '0');   -- at the destination
   signal src_seq      : natural := 0;                                       -- number of the value
   signal last_chg     : time_vector(0 to 31) := (others => 0 fs);           -- of each delayed bit
   signal dst_smp      : std_logic_vector(31 downto 0) := (others => '0');   -- with metastability

   signal cdc_out      : std_logic_vector(31 downto 0);
   signal pot_out      : std_logic_vector(31 downto 0);
   signal pb_ff2       : std_logic_vector(31 downto 0) := (others => '0');

   signal done         : boolean := false;

   -- the sequence of source values: a pure function of the seed and the number of the value, so
   -- that the checkers can follow it without storing it
   function value_of(k : natural) return std_logic_vector is
      variable x : unsigned(31 downto 0);
   begin
      if k = 0 then
         return (31 downto 0 => '0');
      end if;
      x := to_unsigned(k, 32) xor to_unsigned(G_SEED * 7919, 32);
      for i in 1 to 2 loop                                          -- a hash with full avalanche
         x := x xor shift_right(x, 16);
         x := resize(x * unsigned'(x"7FEB352D"), 32);
         x := x xor shift_right(x, 15);
         x := resize(x * unsigned'(x"846CA68B"), 32);
      end loop;
      return std_logic_vector(x xor shift_right(x, 16));
   end function value_of;

   shared variable errcnt : counter_pt;

   procedure tb_error(msg : string) is
   begin
      if errcnt.value < 30 then
         report "TB_ERROR: " & msg severity error;
      end if;
      errcnt.inc;
      if G_STOP then
         report "TB: RESULT FAIL (stopped at the first error)" severity note;
         finish;
      end if;
   end procedure tb_error;

begin

   src_clk <= not src_clk after C_SRC_HALF when running;

   dst_clk_proc : process
   begin
      wait for 3.7 ns;                                              -- no relation to the source
      while running loop
         dst_clk <= not dst_clk;
         wait for C_DST_HALF;
      end loop;
      wait;
   end process dst_clk_proc;

   -- the source register takes a new value at random intervals
   source : process
      variable r : rng_t := rng_init(5000 + G_SEED);
      variable n : integer;
   begin
      wait until rising_edge(src_clk);
      for k in 1 to G_CHANGES loop
         rand_int(r, 8, 75, n);                                     -- 160 ns to 1.5 us
         for c in 1 to n loop
            wait until rising_edge(src_clk);
         end loop;
         src_val <= value_of(k);
         src_seq <= k;
      end loop;
      for c in 1 to 100 loop
         wait until rising_edge(src_clk);
      end loop;
      done <= true;
      wait;
   end process source;

   -- routing delay per bit, and the time of the last change of each delayed bit
   gen_route : for i in 0 to 31 generate
      src_dly(i) <= transport src_val(i) after C_ROUTE(i);
      process (src_dly(i))
      begin
         last_chg(i) <= now;
      end process;
   end generate gen_route;

   -- what the first flip-flop of the destination samples: a bit that changed within C_META before
   -- the edge takes a random value
   meta : process (dst_clk)
      variable r : rng_t := rng_init(6000 + G_SEED);
      variable q : real;
   begin
      if rising_edge(dst_clk) then
         for i in 0 to 31 loop
            if now - last_chg(i) < C_META then
               rand(r, q);
               if q < 0.5 then
                  dst_smp(i) <= '0';
               else
                  dst_smp(i) <= '1';
               end if;
            else
               dst_smp(i) <= src_dly(i);
            end if;
         end loop;
      end if;
   end process meta;

   -- path under test: cdc_stable without its own source register (the register of this bench is it)
   i_cdc : entity work.cdc_stable
      generic map (
         G_DATA_SIZE    => 32,
         G_REGISTER_SRC => false
      )
      port map (
         src_clk_i  => src_clk,
         src_data_i => src_dly,
         dst_clk_i  => dst_clk,
         dst_data_o => cdc_out
      );

   i_debouncer : entity work.debouncer
      generic map (
         CLK_FREQ           => C_CORE_HZ
      )
      port map (
         clk                => dst_clk,
         reset_n            => '1',
         flip_joys_i        => '0',
         joy_1_on           => '1',
         joy_2_on           => '1',
         joy_1_up_n         => '1',
         joy_1_down_n       => '1',
         joy_1_left_n       => '1',
         joy_1_right_n      => '1',
         joy_1_fire_n       => '1',
         dbnce_joy1_up_n    => open,
         dbnce_joy1_down_n  => open,
         dbnce_joy1_left_n  => open,
         dbnce_joy1_right_n => open,
         dbnce_joy1_fire_n  => open,
         joy_2_up_n         => '1',
         joy_2_down_n       => '1',
         joy_2_left_n       => '1',
         joy_2_right_n      => '1',
         joy_2_fire_n       => '1',
         dbnce_joy2_up_n    => open,
         dbnce_joy2_down_n  => open,
         dbnce_joy2_left_n  => open,
         dbnce_joy2_right_n => open,
         dbnce_joy2_fire_n  => open,
         amiga_i            => "00",
         amiga_rclick_i     => "00",
         mega_key_n_i       => '1',
         pot1_x_i           => cdc_out( 7 downto  0),
         pot1_y_i           => cdc_out(15 downto  8),
         pot2_x_i           => cdc_out(23 downto 16),
         pot2_y_i           => cdc_out(31 downto 24),
         pot1_x_o           => pot_out( 7 downto  0),
         pot1_y_o           => pot_out(15 downto  8),
         pot2_x_o           => pot_out(23 downto 16),
         pot2_y_o           => pot_out(31 downto 24)
      );

   -- model of the per-bit synchronizers: two flip-flops per bit on the same delayed bits; the first
   -- one is dst_smp, which includes the metastability, the second one pb_ff2. cdc_stable samples the
   -- delayed bits with its own first flip-flop: the routing delays give it torn first samples in the
   -- same way (an edge between the arrivals of two bits), which it has to reject
   per_bit : process (dst_clk)
   begin
      if rising_edge(dst_clk) then
         pb_ff2 <= dst_smp;
      end if;
   end process per_bit;

   -- checkers, at every falling edge of the destination clock. Each one follows the sequence of
   -- source values: the output is the current one or the next one (then that becomes current);
   -- anything else is a torn value
   check : process
      variable cur_c, nxt_c : natural := 0;       -- numbers of the values, path under test
      variable cur_p, nxt_p : natural := 0;       -- per-bit model
      variable torn_c       : natural := 0;
      variable torn_p       : natural := 0;
      variable cycles       : natural := 0;
      variable v_cur_c, v_nxt_c, v_cur_p, v_nxt_p : std_logic_vector(31 downto 0);
   begin
      v_cur_c := value_of(0);
      v_nxt_c := value_of(1);
      v_cur_p := value_of(0);
      v_nxt_p := value_of(1);
      -- the output register of cdc_stable has no initial value (on the FPGA it starts at 0): the
      -- check begins with the first defined value
      wait until falling_edge(dst_clk) and not is_x(pot_out);
      loop
         wait until falling_edge(dst_clk) or done;
         exit when done;
         cycles := cycles + 1;
         if pot_out /= v_cur_c then
            if pot_out = v_nxt_c then
               cur_c   := cur_c + 1;
               v_cur_c := v_nxt_c;
               v_nxt_c := value_of(cur_c + 1);
            else
               torn_c := torn_c + 1;
               tb_error("the paddle outputs show " & to_hstring(pot_out) & ", which the source never held (value " &
                        integer'image(cur_c) & " is " & to_hstring(v_cur_c) & ", value " & integer'image(cur_c + 1) &
                        " is " & to_hstring(v_nxt_c) & ")");
            end if;
         end if;
         if pb_ff2 /= v_cur_p then
            if pb_ff2 = v_nxt_p then
               cur_p   := cur_p + 1;
               v_cur_p := v_nxt_p;
               v_nxt_p := value_of(cur_p + 1);
            else
               torn_p := torn_p + 1;
            end if;
         end if;
      end loop;
      wait for 1 us;
      if cur_c /= G_CHANGES then
         tb_error("the paddle outputs showed " & integer'image(cur_c) & " of " & integer'image(G_CHANGES) & " values");
      end if;
      if cur_p /= G_CHANGES then
         tb_error("the per-bit model lost values: " & integer'image(cur_p) & " of " & integer'image(G_CHANGES));
      end if;
      report "TB: " & integer'image(G_CHANGES) & " changes of the four paddle bytes from 50 MHz to 31,527,778 Hz, " &
             integer'image(cycles) & " clock cycles: cdc_stable and debouncer showed " & integer'image(cur_c) &
             " values in order and " & integer'image(torn_c) & " torn values" severity note;
      report "TB: per-bit synchronizers (two flip-flops per bit, the same routing delays of 0 to 3 ns and " &
             "metastability): " & integer'image(torn_p) & " clock cycles with a torn value" severity note;
      if torn_p = 0 then
         tb_error("the per-bit model shows no torn value: the comparison does not demonstrate anything");
      end if;
      if errcnt.value = 0 then
         report "TB: RESULT PASS" severity note;
      else
         report "TB: RESULT FAIL " & integer'image(errcnt.value) & " errors" severity note;
      end if;
      running <= false;
      finish;
   end process check;

end architecture sim;
