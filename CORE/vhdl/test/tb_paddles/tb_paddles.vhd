----------------------------------------------------------------------------------------------------
-- Paddle bench (GitHub issue #193): the paddle measurement of mouse_input.vhdl with the Atari mode
--
-- DUT: mouse_input (the file under test). REF: mouse_input_ref, the file of the base commit with
-- its entity renamed, which knows only the C64 mode. Both run on 50 MHz (one tick = 50 clock
-- cycles = 1 us). Around them the board model (tb_paddles_board.vhd): one instance reacts to the
-- discharge of the DUT, one to that of the reference, both with the same stimulus per measuring
-- cycle; in the part "identity" the reference gets the pins of the DUT.
--
-- The checker of an instance knows nothing about its internals; it sees the discharge, the four
-- pins and the four results, and the mode inputs of the DUT:
--   * a cycle starts with the rising edge of pot_drain; the discharge lasts exactly 256 ticks; a
--     cycle has 514 ticks if both modes of the cycle are C64 and 769 ticks otherwise; the modes of
--     a cycle are the mode inputs at the latch tick of the previous cycle (the clock cycle one tick
--     before the start of the cycle), C64 for the first cycle after power-up
--   * the results change only at the latch tick and then show the cycle that ends there
--   * the observer samples each pin at the clock edge of every tick k (the edge at which the DUT
--     samples it) and counts the '0' samples in the ticks 258 .. 512 (C64 window) and
--     258 .. 767 (Atari window); the result of a socket in C64 mode must be the C64 count, that
--     of a socket in Atari mode half the Atari count, rounded down; this holds for any stimulus,
--     including chatter, signals that fall back to '0' and noise
--   * for a monotonic stimulus with the charge time t after the end of the discharge, the result
--     must also follow the formula: C64 min(255, max(0, floor(t / 1 us) - 1)), Atari
--     floor(min(510, max(0, floor(t / 1 us) - 1)) / 2), never charging 255
--   * DUT only: a socket in C64 mode delivers in cycle n exactly what the reference delivers in
--     its cycle n with the same stimulus; a socket in Atari mode with a monotonic stimulus
--     delivers half of the C64 result of the reference, rounded down (if that is not saturated)
-- The range of the tick counter and of the four pin counters is their declared range, which GHDL
-- checks at every assignment (a violation stops the simulation without "RESULT PASS").
-- Part "identity" additionally compares every output of DUT and reference at every change of any
-- of them, drives the joystick inputs at random, and the four Amiga inputs as well in its last
-- G_AMIGA cycles (whose results are then not checked against the observer).
-- The checkers and the stimuli are event driven (a tick is a timeout at the time of its clock
-- edge), which keeps the simulation time close to that of the two instances alone.
--
-- Generics: G_PART identity | atari | mixed | modes | powerup; G_MODES "ab" = modes of socket a and
-- b as '0' (C64) or '1' (Atari) from power-up on, or "rn" for random changes at random clock
-- cycles (always in part "modes"); G_CYCLES measuring cycles of the DUT that are checked.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_paddles_pkg.all;

entity tb_paddles is
   generic (
      G_PART   : string  := "identity";
      G_MODES  : string  := "00";
      G_CYCLES : natural := 100;
      G_AMIGA  : natural := 0;
      G_SEED   : natural := 1
   );
end entity tb_paddles;

architecture sim of tb_paddles is

   constant C_PART  : natural := part_code(G_PART);
   -- the reference runs with its own board model and checker in the parts atari and mixed, with
   -- the pins of the DUT in the part identity, and not at all in the parts modes and powerup
   constant C_REF   : boolean := C_PART = P_ATARI or C_PART = P_MIXED;
   constant C_RAND  : boolean := C_PART = P_MODES or G_MODES = "rn";
   constant C_TOTAL : natural := G_CYCLES + G_AMIGA;
   constant C_MAXC  : natural := 2 * C_TOTAL + 8;

   function init_modes(m : string) return std_logic_vector is
      variable v : std_logic_vector(1 downto 0) := "00";
   begin
      if m'length /= 2 then
         report "G_MODES needs two characters" severity failure;
      end if;
      if m(m'left) = '1' then
         v(0) := '1';
      end if;
      if m(m'left + 1) = '1' then
         v(1) := '1';
      end if;
      if C_RAND then
         v := "00";
      end if;
      return v;
   end function init_modes;

   function csock_of(m : string) return natural is
   begin
      if m(m'left) = '1' then
         return 1;
      end if;
      return 0;
   end function csock_of;

   constant C_CSOCK : natural := csock_of(G_MODES);

   type pins_t  is array (0 to 1) of std_logic_vector(3 downto 0);
   type u8x4    is array (0 to 3) of unsigned(7 downto 0);
   type res_t   is array (0 to 1) of u8x4;
   type slv8_t  is array (0 to 1) of std_logic_vector(7 downto 0);
   type u8_t    is array (0 to 1) of unsigned(7 downto 0);
   type nat4    is array (0 to 3) of natural;
   type hist_t  is array (0 to C_MAXC) of nat4;
   type hists_t is array (0 to 1) of hist_t;
   type int2_t  is array (0 to 1) of integer;

   function name_of(i : natural) return string is
   begin
      if i = 0 then
         return "DUT";
      end if;
      return "REF";
   end function name_of;

   function img_t(t : time) return string is
   begin
      if t >= 1 ms or t mod 1 us = 0 ns then
         return integer'image(t / 1 us) & " us";
      end if;
      return integer'image(t / 1 ns) & " ns";
   end function img_t;

   function to_slv(r : u8x4) return std_logic_vector is
   begin
      return std_logic_vector(r(0)) & std_logic_vector(r(1)) & std_logic_vector(r(2)) & std_logic_vector(r(3));
   end function to_slv;

   signal clk      : std_logic := '0';
   signal drain    : std_logic_vector(0 to 1);            -- 0 = DUT, 1 = reference
   signal pins     : pins_t;
   signal res      : res_t;                               -- pota_x, pota_y, potb_x, potb_y
   signal jout     : slv8_t;
   signal dbg      : u8_t;
   signal joy      : std_logic_vector(9 downto 0) := (others => '1');
   signal amg      : std_logic_vector(3 downto 0) := "0000";
   signal atari    : std_logic_vector(1 downto 0) := init_modes(G_MODES);   -- (0) socket a

   signal hist     : hists_t;                             -- results per cycle and instance
   signal cyc_done : int2_t := (-1, -1);                  -- last cycle in hist, per instance
   type bool2_t is array (0 to 1) of boolean;
   signal fin      : bool2_t := (false, false);            -- the checker has finished, per instance
   signal stop_req : std_logic := 'Z';                    -- '1': too many errors
   signal n_mchg   : natural := 0;                        -- changes of the mode inputs
   signal n_mtgt   : natural := 0;                        -- of them aimed at tick 513 or 768

   shared variable errs : counter_t;

begin

   clk <= not clk after 10 ns;

   ---------------------------------------------------------------------------------------------
   -- DUT and reference
   ---------------------------------------------------------------------------------------------

   dut : entity work.mouse_input
      port map (
         clk                  => clk,
         amiga_mouse_enable_a => amg(0),
         amiga_mouse_enable_b => amg(1),
         amiga_mouse_assume_a => amg(2),
         amiga_mouse_assume_b => amg(3),
         atari_paddles_a      => atari(0),
         atari_paddles_b      => atari(1),
         pot_drain            => drain(0),
         fa_potx              => pins(0)(0),
         fa_poty              => pins(0)(1),
         fb_potx              => pins(0)(2),
         fb_poty              => pins(0)(3),
         fa_fire              => joy(0),
         fa_left              => joy(1),
         fa_right             => joy(2),
         fa_up                => joy(3),
         fa_down              => joy(4),
         fb_fire              => joy(5),
         fb_left              => joy(6),
         fb_right             => joy(7),
         fb_up                => joy(8),
         fb_down              => joy(9),
         fa_left_out          => jout(0)(0),
         fa_right_out         => jout(0)(1),
         fa_up_out            => jout(0)(2),
         fa_down_out          => jout(0)(3),
         fb_left_out          => jout(0)(4),
         fb_right_out         => jout(0)(5),
         fb_up_out            => jout(0)(6),
         fb_down_out          => jout(0)(7),
         mouse_debug          => dbg(0),
         pota_x               => res(0)(0),
         pota_y               => res(0)(1),
         potb_x               => res(0)(2),
         potb_y               => res(0)(3)
      );

   gen_ref : if C_REF or C_PART = P_IDENTITY generate
      ref : entity work.mouse_input_ref
         port map (
            clk                  => clk,
            amiga_mouse_enable_a => amg(0),
            amiga_mouse_enable_b => amg(1),
            amiga_mouse_assume_a => amg(2),
            amiga_mouse_assume_b => amg(3),
            pot_drain            => drain(1),
            fa_potx              => pins(1)(0),
            fa_poty              => pins(1)(1),
            fb_potx              => pins(1)(2),
            fb_poty              => pins(1)(3),
            fa_fire              => joy(0),
            fa_left              => joy(1),
            fa_right             => joy(2),
            fa_up                => joy(3),
            fa_down              => joy(4),
            fb_fire              => joy(5),
            fb_left              => joy(6),
            fb_right             => joy(7),
            fb_up                => joy(8),
            fb_down              => joy(9),
            fa_left_out          => jout(1)(0),
            fa_right_out         => jout(1)(1),
            fa_up_out            => jout(1)(2),
            fa_down_out          => jout(1)(3),
            fb_left_out          => jout(1)(4),
            fb_right_out         => jout(1)(5),
            fb_up_out            => jout(1)(6),
            fb_down_out          => jout(1)(7),
            mouse_debug          => dbg(1),
            pota_x               => res(1)(0),
            pota_y               => res(1)(1),
            potb_x               => res(1)(2),
            potb_y               => res(1)(3)
         );
   end generate gen_ref;

   ---------------------------------------------------------------------------------------------
   -- board models
   ---------------------------------------------------------------------------------------------

   i_board_dut : entity work.tb_paddles_board
      generic map (G_PART => C_PART, G_SEED => G_SEED, G_CSOCK => C_CSOCK)
      port map (drain_i => drain(0), pins_o => pins(0));

   gen_board_ref : if C_REF generate
      i_board_ref : entity work.tb_paddles_board
         generic map (G_PART => C_PART, G_SEED => G_SEED, G_CSOCK => C_CSOCK)
         port map (drain_i => drain(1), pins_o => pins(1));
   end generate gen_board_ref;

   gen_share : if C_PART = P_IDENTITY generate
      pins(1) <= pins(0);
   end generate gen_share;

   ---------------------------------------------------------------------------------------------
   -- mode inputs of the DUT: random changes at random clock cycles, a part of them aimed at the
   -- clock edges around tick 513 and tick 768 of the running cycle. A change is made at the time
   -- of a rising clock edge and takes effect a delta cycle later, so the DUT sees it first at the
   -- next edge, as with a clocked process.
   ---------------------------------------------------------------------------------------------

   gen_rand_modes : if C_RAND generate
      p_modes : process
         variable st     : u32  := hash3(G_SEED, 999, 1);
         variable t_rand : time := 30 ns;               -- second rising edge
         variable t_tgt  : time := time'high;
         variable r, g   : integer;
      begin
         loop
            wait until drain(0) = '1' for minimum(t_rand, t_tgt) - now;
            if drain(0)'event then
               -- edge T0 of a new cycle: tick k is at now + k us; aim at the edge T(k) + g
               rnd(st, 0, 3, r);
               rnd(st, -3, 3, g);
               if r = 0 then
                  t_tgt := now + 513 us + (g - 1) * 20 ns;
               elsif r = 1 then
                  t_tgt := now + 768 us + (g - 1) * 20 ns;
               else
                  t_tgt := time'high;
               end if;
            else
               rnd(st, 1, 3, r);
               atari  <= atari xor std_logic_vector(to_unsigned(r, 2));
               n_mchg <= n_mchg + 1;
               if now = t_tgt then
                  n_mtgt <= n_mtgt + 1;
                  t_tgt  := time'high;
               end if;
               if now = t_rand then
                  rnd(st, 0, 9, r);
                  if r = 0 then
                     rnd(st, 1, 20, g);
                  elsif r < 4 then
                     rnd(st, 1, 2000, g);
                  else
                     rnd(st, 1, 60_000, g);
                  end if;
                  t_rand := now + g * 20 ns;
               end if;
            end if;
         end loop;
      end process p_modes;
   end generate gen_rand_modes;

   ---------------------------------------------------------------------------------------------
   -- part "identity": the joystick inputs (tied to '1' in the design) at random, and the four
   -- Amiga inputs at random in the last G_AMIGA cycles; changes at falling clock edges
   ---------------------------------------------------------------------------------------------

   gen_joy : if C_PART = P_IDENTITY generate
      p_joy : process
         variable st   : u32 := hash3(G_SEED, 777, 1);
         variable r, g : integer;
      begin
         wait for 20 ns;
         loop
            rnd(st, 1, 5000, g);
            wait for g * 20 ns;
            rnd(st, 0, 1023, r);
            joy <= std_logic_vector(to_unsigned(r, 10));
         end loop;
      end process p_joy;

      p_amiga : process
         variable st   : u32 := hash3(G_SEED, 778, 1);
         variable r, g : integer;
      begin
         wait until cyc_done(0) >= integer(G_CYCLES) - 1;
         wait until falling_edge(clk);
         loop
            rnd(st, 0, 15, r);
            amg <= std_logic_vector(to_unsigned(r, 4));
            rnd(st, 1, 30_000, g);
            wait for g * 20 ns;
         end loop;
      end process p_amiga;

      -- every output of DUT and reference, at every change of any of them
      p_ident : process
         variable n_cmp : natural := 0;
      begin
         wait on drain, res, jout, dbg, fin;
         if fin(0) then
            report "TB: identity: every output of DUT and reference equal at all " & integer'image(n_cmp) &
                   " changes of an output of either instance up to " & img_t(now);
            wait;
         end if;
         if drain(0) /= drain(1) or to_slv(res(0)) /= to_slv(res(1)) or jout(0) /= jout(1) or
            std_logic_vector(dbg(0)) /= std_logic_vector(dbg(1)) then
            errs.inc;
            if errs.get <= 20 then
               report "TB_ERROR: identity: outputs differ at " & img_t(now) &
                      ": drain " & std_logic'image(drain(0)) & std_logic'image(drain(1)) &
                      " results " & to_hstring(to_slv(res(0))) & " " & to_hstring(to_slv(res(1))) &
                      " joystick " & to_hstring(jout(0)) & " " & to_hstring(jout(1)) &
                      " debug " & to_hstring(dbg(0)) & " " & to_hstring(dbg(1)) severity error;
            end if;
            if errs.get >= 20 then
               stop_req <= '1';
            end if;
         end if;
         n_cmp := n_cmp + 1;
      end process p_ident;
   end generate gen_joy;

   ---------------------------------------------------------------------------------------------
   -- checkers: 0 = DUT, 1 = reference
   ---------------------------------------------------------------------------------------------

   gen_chk : for i in 0 to 1 generate
      gen_on : if i = 0 or C_REF generate

         p_chk : process
            type hit_t is array (0 to 1, 0 to 255) of boolean;
            type cnt4  is array (0 to 3) of natural;

            constant C_NAME : string(1 to 3) := name_of(i);
            constant C_US   : time := C_TICK * 20 ns;

            variable n        : integer := 0;              -- running cycle
            variable t0       : time;                      -- its start: the edge of tick 0
            variable t_nx     : time;                      -- start of the next cycle
            variable tf       : time;                      -- end of its discharge
            variable mode     : std_logic_vector(1 downto 0) := "00";   -- C64 after power-up
            variable mode_nx  : std_logic_vector(1 downto 0);
            variable k, k_end : integer;
            variable n64, nat : nat4;
            variable chg_n    : natural;
            variable t_chg    : time;
            variable got      : nat4;
            variable want, f  : integer;
            variable t, s, r  : integer;
            variable st       : stim_t;
            variable mono     : boolean;
            variable ev_d     : boolean;
            variable ev_r     : boolean;
            variable n_short, n_long, n_obs, n_frm, n_ref, n_half, n_chk : natural := 0;
            variable n_mode   : cnt4 := (others => 0);
            variable hit      : hit_t := (others => (others => false));
            variable hit_all  : boolean;

            procedure err(msg : string) is
            begin
               errs.inc;
               if errs.get <= 20 then
                  report "TB_ERROR: " & C_NAME & " cycle " & integer'image(n) & ": " & msg severity error;
               end if;
               if errs.get >= 20 then
                  stop_req <= '1';
               end if;
            end procedure err;

            function img(v : integer) return string is
            begin
               return integer'image(v);
            end function img;

         begin
            wait until drain(i) = '1' for 2 us;
            if drain(i) /= '1' then
               err("no discharge after power-up");
               stop_req <= '1';
               wait;
            end if;
            t_nx := now;

            loop
               ----------------------------------------------------------------------------------
               -- cycle n starts: now is the time of the clock edge of its tick 0
               ----------------------------------------------------------------------------------
               t0    := t_nx;
               tf    := 0 ns;
               n64   := (others => 0);
               nat   := (others => 0);
               chg_n := 0;
               t_chg := 0 ns;
               if mode = "00" then
                  k_end := C_SHORT - 1;                 -- the latch tick of a short cycle
               else
                  k_end := C_LONG - 1;                  -- the latch tick of a long cycle
               end if;
               mode_nx := "00";
               k := 258;

               -- events until the next cycle starts; a timeout is the clock edge of tick k (delta
               -- cycle 0, the DUT samples its inputs in the same delta cycle)
               loop
                  if k <= k_end then
                     wait on drain(i), res(i) for t0 + k * C_US - now;
                  else
                     wait on drain(i), res(i) for t0 + (C_LONG + 2) * C_US - now;
                  end if;
                  ev_d := drain(i)'event;
                  ev_r := res(i)'event;
                  if ev_r then
                     if chg_n = 0 or t_chg /= now then
                        chg_n := chg_n + 1;
                     end if;
                     t_chg := now;
                  end if;
                  if ev_d then
                     if drain(i) = '1' then
                        t_nx := now;
                        exit;
                     elsif drain(i) = '0' and tf = 0 ns then
                        tf := now;
                        if now - t0 /= C_DRAIN * C_US then
                           err("discharge of " & img_t(now - t0) & " instead of 256 us");
                        end if;
                     else
                        err("pot_drain is " & std_logic'image(drain(i)) & " at " & img_t(now - t0) & " after the start");
                     end if;
                  end if;
                  if not ev_d and not ev_r then
                     if k > k_end then
                        err("no new discharge " & img(C_LONG + 2) & " ticks after the start of the cycle");
                        stop_req <= '1';
                        wait;
                     end if;
                     if k <= 767 then
                        for p in 0 to 3 loop
                           if pins(i)(p) = '0' then
                              nat(p) := nat(p) + 1;
                              if k <= 512 then
                                 n64(p) := n64(p) + 1;
                              end if;
                           end if;
                        end loop;
                     end if;
                     if k = k_end and i = 0 then
                        mode_nx := atari;               -- what the DUT sees at its latch tick
                     end if;
                     k := k + 1;
                  end if;
               end loop;

               ----------------------------------------------------------------------------------
               -- the next cycle starts now: check cycle n
               ----------------------------------------------------------------------------------
               if mode = "00" then
                  n_short := n_short + 1;
                  if t_nx - t0 /= C_SHORT * C_US then
                     err("short cycle of " & img_t(t_nx - t0) & " instead of 514 us");
                  end if;
               else
                  n_long := n_long + 1;
                  if t_nx - t0 /= C_LONG * C_US then
                     err("long cycle of " & img_t(t_nx - t0) & " instead of 769 us");
                  end if;
               end if;
               n_mode(to_integer(unsigned(mode))) := n_mode(to_integer(unsigned(mode))) + 1;
               if tf = 0 ns then
                  err("the discharge did not end");
               end if;

               if n < integer(G_CYCLES) then
                  n_chk := n_chk + 1;
                  -- the latch tick is one tick before the start, the results follow one clock later
                  if chg_n > 1 or (chg_n = 1 and t_chg /= t_nx - 49 * 20 ns) then
                     err("the results changed " & img(chg_n) & " times, last " & img_t(t_nx - t_chg) &
                         " before the start of the next cycle (980 ns is one clock cycle after the latch tick)");
                  end if;
                  for p in 0 to 3 loop
                     s      := p / 2;
                     got(p) := to_integer(res(i)(p));
                     if mode(s) = '1' then
                        want := nat(p) / 2;
                     else
                        want := n64(p);
                     end if;
                     if got(p) /= want then
                        err("pin " & img(p) & " mode " & std_logic'image(mode(s)) & ": result " & img(got(p)) &
                            ", the observer counted " & img(n64(p)) & " (C64 window) and " & img(nat(p)) & " (Atari window)");
                     end if;
                     n_obs := n_obs + 1;
                     st    := get_stim(C_PART, G_SEED, p, n, C_CSOCK);
                     t     := charge_ns(st);
                     if t /= C_NONMONO then
                        if mode(s) = '1' then
                           f := exp_atari(t);
                           hit(s, got(p)) := true;
                        else
                           f := exp_c64(t);
                        end if;
                        if got(p) /= f then
                           err("pin " & img(p) & " mode " & std_logic'image(mode(s)) & ", charge time " & img(t) &
                               " ns: result " & img(got(p)) & ", the formula says " & img(f));
                        end if;
                        n_frm := n_frm + 1;
                     end if;
                  end loop;
                  if n <= integer(C_MAXC) then
                     hist(i)(n)  <= got;
                     cyc_done(i) <= n;
                  end if;

                  -- DUT: compare with cycle n of the reference (it ends at the same time or earlier;
                  -- its checker writes the history in this delta cycle, so look 1 ns later)
                  if i = 0 and C_REF then
                     wait for 1 ns;
                     if cyc_done(1) < n then
                        err("the reference has not finished this cycle");
                     else
                        for p in 0 to 3 loop
                           s    := p / 2;
                           r    := hist(1)(n)(p);
                           st   := get_stim(C_PART, G_SEED, p, n, C_CSOCK);
                           mono := charge_ns(st) /= C_NONMONO;
                           if mode(s) = '0' then
                              if got(p) /= r then
                                 err("pin " & img(p) & " (C64 mode): " & img(got(p)) & ", the reference measured " & img(r));
                              end if;
                              n_ref := n_ref + 1;
                           elsif mono then
                              if (r < 255 and got(p) /= r / 2) or (r = 255 and got(p) < 127) then
                                 err("pin " & img(p) & " (Atari mode): " & img(got(p)) & ", the reference measured " & img(r));
                              end if;
                              n_half := n_half + 1;
                           end if;
                        end loop;
                     end if;
                  end if;
               elsif n <= integer(C_MAXC) then
                  cyc_done(i) <= n;
               end if;

               if n = integer(C_TOTAL) - 1 then
                  report "TB: " & C_NAME & ": " & img(n_short + n_long) & " cycles: " & img(n_short) &
                         " short (514 ticks), " & img(n_long) & " long (769 ticks); modes ab = 00/10/01/11 in " &
                         img(n_mode(0)) & "/" & img(n_mode(1)) & "/" & img(n_mode(2)) & "/" & img(n_mode(3)) &
                         " cycles; discharge 256 ticks from the start of every cycle";
                  report "TB: " & C_NAME & ": " & img(n_chk) & " cycles with checked results (changes only at the latch tick); " &
                         img(n_obs) & " results equal to the observer, " & img(n_frm) & " equal to the formula";
                  if i = 0 and C_REF then
                     report "TB: DUT: " & img(n_ref) & " results of a socket in C64 mode equal to the reference, " &
                            img(n_half) & " results of a socket in Atari mode equal to half the C64 result of the reference";
                  end if;
                  if i = 0 and C_PART = P_ATARI then
                     for sk in 0 to 1 loop
                        hit_all := true;
                        for v in 0 to 255 loop
                           hit_all := hit_all and hit(sk, v);
                        end loop;
                        if hit_all then
                           report "TB: DUT: socket " & img(sk) & " in Atari mode delivered every result from 0 to 255";
                        else
                           err("socket " & img(sk) & " in Atari mode did not deliver every result from 0 to 255");
                        end if;
                     end loop;
                  end if;
                  fin(i) <= true;
               end if;

               -- cycle n + 1: its modes are what the DUT saw at the latch tick of cycle n
               n    := n + 1;
               mode := mode_nx;
               if i = 1 then
                  mode := "00";
               end if;
            end loop;
         end process p_chk;

      end generate gen_on;
   end generate gen_chk;

   ---------------------------------------------------------------------------------------------
   -- end of the bench
   ---------------------------------------------------------------------------------------------

   p_end : process
   begin
      wait until fin(0) or stop_req = '1';
      wait for 2 us;
      if C_RAND then
         report "TB: mode inputs changed " & integer'image(n_mchg) & " times, " & integer'image(n_mtgt) &
                " of them aimed at the clock edges up to 3 clock cycles before and after tick 513 or tick 768";
      end if;
      if stop_req = '1' then
         report "TB: stopped after " & integer'image(errs.get) & " errors";
      end if;
      if errs.get = 0 and fin(0) then
         report "TB: RESULT PASS";
      else
         report "TB: RESULT FAIL (" & integer'image(errs.get) & " errors)";
      end if;
      std.env.stop;
   end process p_end;

end architecture sim;
