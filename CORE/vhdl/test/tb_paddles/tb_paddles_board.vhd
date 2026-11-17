----------------------------------------------------------------------------------------------------
-- Paddle bench (GitHub issue #193): model of the board circuit and of the devices on the four
-- paddle pins
--
-- Per pin: the comparator output (NC7SZ126 behind 1 kOhm and 1.2 nF) is '0' while the discharge
-- (drain_i) is on and until the charge time after the end of the discharge has passed, then '1'
-- until the next discharge. A 1351 sees the start of the discharge and drives its line high
-- 320 + 2 x p us later. What a pin does in measuring cycle n (the n-th discharge that this model
-- sees, counted from 0) is get_stim(G_PART, G_SEED, pin, n, G_CSOCK), see tb_paddles_pkg.vhd; the
-- non-monotonic kinds (chatter, fall back, noise) take their details from a random stream of
-- their own per pin and cycle, so two models with the same generics produce the same waveform
-- relative to the start of their own discharge.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.tb_paddles_pkg.all;

entity tb_paddles_board is
   generic (
      G_PART  : natural;
      G_SEED  : natural;
      G_CSOCK : natural
   );
   port (
      drain_i : in  std_logic;
      pins_o  : out std_logic_vector(3 downto 0)
   );
end entity tb_paddles_board;

architecture sim of tb_paddles_board is
begin

   gen_pin : for i in 0 to 3 generate

      p_pin : process
         variable n       : natural := 0;
         variable st      : stim_t;
         variable rs      : u32;
         variable t_ref   : time;
         variable t_ev    : integer;
         variable lvl     : std_logic;
         variable aborted : boolean;
         variable g       : integer;

         -- wait until t_ref + t ns or until the next discharge starts (then aborted is true)
         procedure wait_rel(t : integer) is
         begin
            if t_ref + t * 1 ns > now then
               wait until drain_i = '1' for t_ref + t * 1 ns - now;
            end if;
            aborted := drain_i'event and drain_i = '1';
         end procedure wait_rel;

         procedure drive(v : std_logic) is
         begin
            lvl := v;
            pins_o(i) <= v;
         end procedure drive;

      begin
         pins_o(i) <= '0';
         wait until drain_i = '1';
         loop
            -- a discharge starts: measuring cycle n
            st      := get_stim(G_PART, G_SEED, i, n, G_CSOCK);
            rs      := hash3(G_SEED, 300 + i, n);
            aborted := false;
            case st.kind is
               when K_NOISE =>
                  rnd(rs, 0, 1, g);
                  if g = 0 then drive('0'); else drive('1'); end if;
                  t_ref := now;
                  t_ev  := 0;
                  loop
                     rnd(rs, 1, 20_000, g);
                     t_ev := t_ev + g;
                     wait_rel(t_ev);
                     exit when aborted;
                     drive(not lvl);
                  end loop;

               when K_1351 =>
                  drive('0');
                  t_ref := now;
                  wait_rel(st.t1);
                  if not aborted then
                     drive('1');
                  end if;

               when others =>
                  -- the capacitor is held at 0 V during the discharge
                  drive('0');
                  wait until drain_i = '0';
                  t_ref := now;
                  case st.kind is
                     when K_CHARGE =>
                        wait_rel(st.t1);
                        if not aborted then
                           drive('1');
                        end if;

                     when K_CHATTER =>
                        t_ev := maximum(0, st.t1 - 2000);
                        while t_ev < st.t1 + 2000 loop
                           wait_rel(t_ev);
                           exit when aborted;
                           drive(not lvl);
                           rnd(rs, 5, 400, g);
                           t_ev := t_ev + g;
                        end loop;
                        if not aborted then
                           wait_rel(t_ev);
                           if not aborted then
                              drive('1');
                           end if;
                        end if;

                     when K_FALLBACK =>
                        wait_rel(st.t1);
                        if not aborted then
                           drive('1');
                           wait_rel(st.t2);
                           if not aborted then
                              drive('0');
                              if st.t3 >= 0 then
                                 wait_rel(st.t3);
                                 if not aborted then
                                    drive('1');
                                 end if;
                              end if;
                           end if;
                        end if;

                     when others =>             -- K_NEVER
                        null;
                  end case;
            end case;
            if not aborted then
               wait until drain_i = '1';
            end if;
            n := n + 1;
         end loop;
      end process p_pin;

   end generate gen_pin;

end architecture sim;
