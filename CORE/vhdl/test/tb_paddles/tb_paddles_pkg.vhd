----------------------------------------------------------------------------------------------------
-- Paddle bench (GitHub issue #193): stimuli, expected values and helpers
--
-- The stimulus of a paddle pin in a measuring cycle is a pure function of (part, seed, pin, cycle
-- number), so that two board models that react to two different instances (the reference with its
-- short cycles and the DUT with its long ones) deliver the same stimulus in the same cycle, and the
-- checkers can compute what a cycle should measure.
--
-- Pins: 0 = socket a pin 9 (fa_potx), 1 = socket a pin 5 (fa_poty), 2 = socket b pin 9 (fb_potx),
-- 3 = socket b pin 5 (fb_poty). Socket of pin p: p / 2.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tb_paddles_pkg is

   subtype u32 is unsigned(31 downto 0);

   -- parts of the bench
   constant P_IDENTITY : natural := 0;    -- DUT against the reference, both sockets in C64 mode
   constant P_ATARI    : natural := 1;    -- both sockets in Atari mode: sweep of the charge time
   constant P_MIXED    : natural := 2;    -- one socket in C64 mode, the other one in Atari mode
   constant P_MODES    : natural := 3;    -- the modes change at random clock cycles
   constant P_POWERUP  : natural := 4;    -- the first cycles after power-up
   function part_code(s : string) return natural;

   -- one tick is 50 clock cycles (1 us at 50 MHz)
   constant C_TICK      : natural := 50;
   constant C_SHORT     : natural := 514;   -- ticks of a short cycle
   constant C_LONG      : natural := 769;   -- ticks of a long cycle
   constant C_DRAIN     : natural := 256;   -- ticks of the discharge
   -- the two-stage synchronizer of the DUT: the edge of tick k sees a pin as it was at the
   -- clock edge two cycles (40 ns) earlier
   constant C_SYNC_NS   : natural := 40;

   -- What a pin does in one measuring cycle. All times in ns.
   --   K_NEVER     the capacitor never charges: '0' for the whole cycle
   --   K_CHARGE    '0' during the discharge, '1' from t1 after the end of the discharge on
   --   K_1351      '0' during the discharge, '1' from t1 after the start of the discharge on
   --               (a 1351: t1 = 320 + 2 x p us)
   --   K_CHATTER   like K_CHARGE, but the output toggles at random from t1 - 2 us to t1 + 2 us
   --   K_FALLBACK  '1' at t1, back to '0' at t2, '1' again at t3 (never if t3 < 0), all after the
   --               end of the discharge
   --   K_NOISE     random toggles from the start of the discharge on, also during the discharge
   type kind_t is (K_NEVER, K_CHARGE, K_1351, K_CHATTER, K_FALLBACK, K_NOISE);
   type stim_t is record
      kind : kind_t;
      t1   : integer;
      t2   : integer;
      t3   : integer;
   end record stim_t;

   constant C_NEVER   : integer := -1;   -- charge_ns: the capacitor never charges
   constant C_NONMONO : integer := -2;   -- charge_ns: not a single rising edge
   -- charge time after the end of the discharge of a monotonic stimulus
   function charge_ns(st : stim_t) return integer;
   -- expected results for a charge time t (ns after the end of the discharge, or C_NEVER):
   -- C64 min(255, max(0, floor((t + 40 ns) / 1 us) - 1)), Atari half of
   -- min(510, max(0, floor((t + 40 ns) / 1 us) - 1)), rounded down; never charging 255
   function exp_c64(t : integer) return natural;
   function exp_atari(t : integer) return natural;

   -- random numbers
   function hash32(x : u32) return u32;
   function hash3(a, b, c : natural) return u32;
   procedure rnd(st : inout u32; lo, hi : integer; r : out integer);

   -- stimulus of pin "pin" in measuring cycle n; csock is the socket in C64 mode of P_MIXED
   function get_stim(part, seed, pin, n, csock : natural) return stim_t;

   -- error counter shared by all checkers
   type counter_t is protected
      procedure inc;
      impure function get return natural;
   end protected counter_t;

end package tb_paddles_pkg;

package body tb_paddles_pkg is

   function part_code(s : string) return natural is
   begin
      if s = "identity" then return P_IDENTITY; end if;
      if s = "atari"    then return P_ATARI;    end if;
      if s = "mixed"    then return P_MIXED;    end if;
      if s = "modes"    then return P_MODES;    end if;
      if s = "powerup"  then return P_POWERUP;  end if;
      report "unknown part " & s severity failure;
      return 0;
   end function part_code;

   function charge_ns(st : stim_t) return integer is
   begin
      case st.kind is
         when K_NEVER  => return C_NEVER;
         when K_CHARGE => return st.t1;
         when K_1351   => return st.t1 - integer(C_DRAIN) * 1000;
         when others   => return C_NONMONO;
      end case;
   end function charge_ns;

   function exp_c64(t : integer) return natural is
   begin
      if t < 0 then
         return 255;
      end if;
      return minimum(255, maximum(0, (t + C_SYNC_NS) / 1000 - 1));
   end function exp_c64;

   function exp_atari(t : integer) return natural is
   begin
      if t < 0 then
         return 255;
      end if;
      return minimum(510, maximum(0, (t + C_SYNC_NS) / 1000 - 1)) / 2;
   end function exp_atari;

   -- lowbias32 integer hash
   function hash32(x : u32) return u32 is
      variable h : u32 := x;
   begin
      h := h xor shift_right(h, 16);
      h := resize(h * x"7feb352d", 32);
      h := h xor shift_right(h, 15);
      h := resize(h * x"846ca68b", 32);
      h := h xor shift_right(h, 16);
      return h;
   end function hash32;

   function hash3(a, b, c : natural) return u32 is
   begin
      return hash32(hash32(hash32(to_unsigned(a, 32)) xor to_unsigned(b, 32)) xor to_unsigned(c, 32));
   end function hash3;

   -- next random integer in lo .. hi (counter based: the state advances by the golden ratio)
   procedure rnd(st : inout u32; lo, hi : integer; r : out integer) is
      variable h : u32;
   begin
      st := st + x"9e3779b9";
      h  := hash32(st);
      r  := lo + to_integer(h(30 downto 0)) mod (hi - lo + 1);
   end procedure rnd;

   -- random stimulus: all kinds (mono = false) or only monotonic ones (mono = true)
   function stim_random(seed, pin, n : natural; mono : boolean) return stim_t is
      variable st   : stim_t := (K_NEVER, 0, 0, 0);
      variable h    : u32;
      variable r, x : integer;
   begin
      -- a 1351 on the socket in about 15 % of the cycles
      h := hash3(seed, 100 + pin / 2, n);
      rnd(h, 0, 99, r);
      if r < 15 then
         h := hash3(seed, 200 + pin, n);
         rnd(h, 0, 63, x);
         return (K_1351, (320 + 2 * x) * 1000, 0, 0);
      end if;
      h := hash3(seed, pin, n);
      rnd(h, 0, 99, r);
      if mono and r >= 63 then
         r := 20;                                       -- a plain charge time instead
      end if;
      if r < 8 then
         st := (K_NEVER, 0, 0, 0);                      -- nothing connected
      elsif r < 10 then
         st := (K_CHARGE, 0, 0, 0);                     -- charge time 0
      elsif r < 14 then
         rnd(h, 300, 800, x);                           -- connected to +5 V: 1 kOhm x 1.2 nF
         st := (K_CHARGE, x, 0, 0);
      elsif r < 43 then
         rnd(h, 0, 600_000, x);                         -- anywhere in the window of both modes
         st := (K_CHARGE, x, 0, 0);
      elsif r < 53 then
         rnd(h, 0, 1, x);                               -- around the saturation of either mode
         if x = 0 then
            rnd(h, 254_000, 258_000, x);
         else
            rnd(h, 509_000, 513_000, x);
         end if;
         st := (K_CHARGE, x, 0, 0);
      elsif r < 63 then
         rnd(h, 0, 600, x);                             -- on a sampling point and 1 ns either side
         st.t1 := x * 1000 - C_SYNC_NS;
         rnd(h, -1, 1, x);
         st := (K_CHARGE, maximum(0, st.t1 + x), 0, 0);
      elsif r < 75 then
         rnd(h, 0, 600_000, x);
         st := (K_CHATTER, x, 0, 0);
      elsif r < 87 then
         rnd(h, 0, 500_000, x);
         st.t1 := x;
         rnd(h, 1, 200_000, x);
         st.t2 := st.t1 + x;
         rnd(h, 0, 1, x);
         if x = 0 then
            st.t3 := -1;
         else
            rnd(h, 1, 100_000, x);
            st.t3 := st.t2 + x;
         end if;
         st.kind := K_FALLBACK;
      else
         st := (K_NOISE, 0, 0, 0);
      end if;
      return st;
   end function stim_random;

   -- non-monotonic stimulus for a socket in Atari mode: chatter around a crossing, a signal that
   -- falls back to '0' and possibly rises again, or noise; the times cover the whole Atari window,
   -- before and after tick 512
   function stim_nonmono(seed, pin, n : natural) return stim_t is
      variable h          : u32 := hash3(seed, 400 + pin, n);
      variable x, t1, t2  : integer;
   begin
      case (n + pin) mod 3 is
         when 0 =>
            rnd(h, 0, 600_000, x);
            return (K_CHATTER, x, 0, 0);
         when 1 =>
            rnd(h, 0, 550_000, t1);
            rnd(h, 1, 200_000, x);
            t2 := t1 + x;
            rnd(h, 0, 1, x);
            if x = 0 then
               return (K_FALLBACK, t1, t2, -1);
            end if;
            rnd(h, 1, 100_000, x);
            return (K_FALLBACK, t1, t2, t2 + x);
         when others =>
            return (K_NOISE, 0, 0, 0);
      end case;
   end function stim_nonmono;

   function get_stim(part, seed, pin, n, csock : natural) return stim_t is
      type off_t is array (0 to 5) of integer;
      -- offsets within a microsecond: the sampling point (-40 ns) and 1 ns either side
      constant C_OFF : off_t := (0, -41, -40, -39, 500, 959);
      variable m, v, t : integer;
   begin
      -- cycle 0 is the short C64 cycle after power-up in every part
      if n = 0 then
         return stim_random(seed, pin, n, true);
      end if;
      m := n - 1;
      case part is
         when P_IDENTITY | P_MODES =>
            return stim_random(seed, pin, n, false);

         when P_POWERUP =>
            return stim_random(seed, pin, n, true);

         when P_ATARI =>
            -- 40 cycles of non-monotonic signals on all four pins, then the charge times
            if m < 40 then
               return stim_nonmono(seed, pin, n);
            end if;
            m := m - 40;
            if m <= 300 then
               -- 0 to 600 us in steps of 500 ns over the four pins; the sampling points (whole
               -- microseconds minus 40 ns) alternate between 1 ns early, exact and 1 ns late
               v := 4 * m + pin;
               t := v * 500;
               if v mod 2 = 0 then
                  t := t - C_SYNC_NS + (v / 2) mod 3 - 1;
               end if;
               return (K_CHARGE, maximum(0, t), 0, 0);
            elsif m = 301 then
               return (K_NEVER, 0, 0, 0);
            elsif m = 302 then
               return (K_CHARGE, 0, 0, 0);
            elsif m = 303 then
               -- connected to +5 V: 0.30, 0.45, 0.60, 0.75 us
               return (K_CHARGE, 300 + 150 * pin, 0, 0);
            elsif m = 304 then
               -- the saturation of the Atari mode: 510.959, 510.960, 510.961, 511.960 us
               case pin is
                  when 0      => return (K_CHARGE, 510_959, 0, 0);
                  when 1      => return (K_CHARGE, 510_960, 0, 0);
                  when 2      => return (K_CHARGE, 510_961, 0, 0);
                  when others => return (K_CHARGE, 511_960, 0, 0);
               end case;
            elsif m = 305 then
               -- the saturation of the C64 mode: 255.959, 255.960, 255.961, 256.960 us
               case pin is
                  when 0      => return (K_CHARGE, 255_959, 0, 0);
                  when 1      => return (K_CHARGE, 255_960, 0, 0);
                  when 2      => return (K_CHARGE, 255_961, 0, 0);
                  when others => return (K_CHARGE, 256_960, 0, 0);
               end case;
            else
               return stim_random(seed, pin, n, true);
            end if;

         when P_MIXED =>
            if pin / 2 = csock then
               -- the socket in C64 mode
               if m < 130 then
                  t := m * 1000 + C_OFF(m mod 6);
                  if pin mod 2 = 1 then
                     t := t + 130_000;
                  end if;
                  return (K_CHARGE, maximum(0, t), 0, 0);
               elsif m < 194 then
                  v := m - 130;
                  if pin mod 2 = 1 then
                     v := 63 - v;
                  end if;
                  return (K_1351, (320 + 2 * v) * 1000, 0, 0);
               else
                  return stim_random(seed, pin, n, false);
               end if;
            else
               -- the socket in Atari mode: non-monotonic signals in every other cycle, charge
               -- times from 0 to 600 us in the others
               if m mod 2 = 1 then
                  return stim_nonmono(seed, pin, n);
               end if;
               t := (m mod 234) * 2575 + C_OFF(m mod 6);
               if pin mod 2 = 1 then
                  t := 600_000 - t;
               end if;
               return (K_CHARGE, maximum(0, t), 0, 0);
            end if;

         when others =>
            return stim_random(seed, pin, n, false);
      end case;
   end function get_stim;

   type counter_t is protected body
      variable cnt : natural := 0;
      procedure inc is
      begin
         cnt := cnt + 1;
      end procedure inc;
      impure function get return natural is
      begin
         return cnt;
      end function get;
   end protected body counter_t;

end package body tb_paddles_pkg;
