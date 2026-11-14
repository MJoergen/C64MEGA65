----------------------------------------------------------------------------------------------------
-- Amiga mouse benches (GitHub issue #190): shared definitions
--
-- * the quadrature sequences of SPEC.md section 4.2, written down from the table of the
--   specification (and not from the decoder)
-- * random numbers
-- * the movement routine of the Commodore 1351 manual (the driver of cc65 and GEOS)
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

package tb_amiga_mouse_pkg is

   -- (first, second) of a pair for the sequence that counts +1: state k is followed by state k+1
   type seq_t is array (0 to 3) of std_logic_vector(1 downto 0);
   constant C_SEQ_X : seq_t := ("11", "10", "00", "01");   -- X: (HQ, H) = (right, down), +1 is to the right
   constant C_SEQ_Y : seq_t := ("11", "01", "00", "10");   -- Y: (VQ, V) = (left, up), +1 is up

   -- index of a state in a sequence
   function seq_index(seq : seq_t; s : std_logic_vector(1 downto 0)) return natural;

   -- random numbers
   type rng_t is record
      s1 : positive;
      s2 : positive;
   end record rng_t;
   function rng_init(seed : positive) return rng_t;
   procedure rand(r : inout rng_t; x : out real);                         -- 0.0 < x < 1.0
   procedure rand_real(r : inout rng_t; lo, hi : real; x : out real);
   procedure rand_int(r : inout rng_t; lo, hi : integer; x : out integer); -- lo <= x <= hi

   -- the movement routine of the 1351 manual for one axis:
   --    d = (new - old) and $7F
   --    d < $40:  u = d / 2; u = 0: return 0, keep old; else old = new, return +u
   --    d >= $40: v = d or $C0 (signed); v = -1: return 0, keep old; else old = new, return v >> 1
   -- res is what the routine returns; acc is the difference that it took over (0 if it kept old),
   -- in LSBs of the POT value
   procedure drv_move(new_v : in natural; old : inout natural; res : out integer; acc : out integer);

   -- the 7-bit position of a POT value (pot = position + 64)
   function pot_pos(pot : std_logic_vector(7 downto 0)) return natural;

   -- floor(n / 2): the position unit of a 1351 driver for a position of n counts
   function fl2(n : integer) return integer;

   -- the POT value of a 1351 for a position of n counts: 64 + (n mod 128) with bit 0 cleared
   function pot_of(n : integer) return std_logic_vector;

   -- a real number with d decimals, and a time in microseconds
   function rstr(x : real; d : natural := 3) return string;
   function to_us(t : time) return real;

   -- error counter shared by all processes of a bench
   type counter_pt is protected
      procedure inc;
      impure function value return natural;
   end protected counter_pt;

end package tb_amiga_mouse_pkg;

package body tb_amiga_mouse_pkg is

   function seq_index(seq : seq_t; s : std_logic_vector(1 downto 0)) return natural is
   begin
      for k in 0 to 3 loop
         if seq(k) = s then
            return k;
         end if;
      end loop;
      report "seq_index: invalid state" severity failure;
      return 0;
   end function seq_index;

   function rng_init(seed : positive) return rng_t is
   begin
      return (s1 => 1 + (seed * 7919) mod 2147483560, s2 => 1 + (seed * 104729 + 12345) mod 2147483390);
   end function rng_init;

   procedure rand(r : inout rng_t; x : out real) is
      variable s1 : positive := r.s1;
      variable s2 : positive := r.s2;
      variable v  : real;
   begin
      uniform(s1, s2, v);
      r := (s1 => s1, s2 => s2);
      x := v;
   end procedure rand;

   procedure rand_real(r : inout rng_t; lo, hi : real; x : out real) is
      variable v : real;
   begin
      rand(r, v);
      x := lo + (hi - lo) * v;
   end procedure rand_real;

   procedure rand_int(r : inout rng_t; lo, hi : integer; x : out integer) is
      variable v : real;
      variable k : integer;
   begin
      rand(r, v);
      k := lo + integer(floor(v * real(hi - lo + 1)));
      if k > hi then
         k := hi;
      end if;
      x := k;
   end procedure rand_int;

   procedure drv_move(new_v : in natural; old : inout natural; res : out integer; acc : out integer) is
      variable d : natural;
      variable v : integer;
   begin
      d := (new_v - old) mod 128;
      if d < 16#40# then
         if d / 2 = 0 then
            res := 0;
            acc := 0;
         else
            old := new_v;
            res := d / 2;
            acc := d;
         end if;
      else
         v := d - 128;                         -- d or $C0 as a signed 8-bit number
         if v = -1 then
            res := 0;
            acc := 0;
         else
            old := new_v;
            res := (v - (v mod 2)) / 2;        -- arithmetic shift right (rounds towards minus infinity)
            acc := v;
         end if;
      end if;
   end procedure drv_move;

   function pot_pos(pot : std_logic_vector(7 downto 0)) return natural is
   begin
      return (to_integer(unsigned(pot)) - 64) mod 128;
   end function pot_pos;

   function fl2(n : integer) return integer is
   begin
      return (n - (n mod 2)) / 2;
   end function fl2;

   function pot_of(n : integer) return std_logic_vector is
   begin
      return std_logic_vector(to_unsigned(64 + 2 * ((n mod 128) / 2), 8));
   end function pot_of;

   function rstr(x : real; d : natural := 3) return string is
      constant C_M : natural := 10 ** d;
      variable ax  : real    := abs(x);
      variable ip  : integer;
      variable fp  : integer;
      variable fs  : string(1 to 12);
   begin
      ip := integer(floor(ax));
      fp := integer(round((ax - floor(ax)) * real(C_M)));
      if fp >= C_M then
         ip := ip + 1;
         fp := fp - C_M;
      end if;
      if d = 0 then
         if x < 0.0 and ip /= 0 then
            return "-" & integer'image(ip);
         end if;
         return integer'image(ip);
      end if;
      for k in d downto 1 loop
         fs(k) := character'val(character'pos('0') + fp mod 10);
         fp := fp / 10;
      end loop;
      if x < 0.0 then
         return "-" & integer'image(ip) & "." & fs(1 to d);
      end if;
      return integer'image(ip) & "." & fs(1 to d);
   end function rstr;

   function to_us(t : time) return real is
   begin
      return real(t / 1 us) + real((t mod 1 us) / 1 ps) * 1.0e-6;
   end function to_us;

   type counter_pt is protected body
      variable n : natural := 0;
      procedure inc is
      begin
         n := n + 1;
      end procedure inc;
      impure function value return natural is
      begin
         return n;
      end function value;
   end protected body counter_pt;

end package body tb_amiga_mouse_pkg;
