----------------------------------------------------------------------------------
-- Issue #266: "Amiga/C64 Mouse port switch does not follow Flip Joystick"
--
-- End-to-end bench from the pins of the two MEGA65 joystick sockets to what a C64
-- program reads on CIA 1 ($DC00 = port A = C64 control port 2, $DC01 = port B =
-- C64 control port 1) and on the SID POT registers ($D419/$D41A) with the analog
-- port selection by $DC00 bits 6 and 7.
--
-- Real, unmodified sources: mouse_input.vhdl (QNICE clock, 50 MHz), cdc_stable.vhd,
-- debouncer.vhd with its two amiga_mouse.vhd and ten debounce.vhd (core clock
-- 31,527,778 Hz), keyboard.vhd (joystick merge into CIA 1).
-- Verbatim copies: process correct_and_flip_paddles (qnice_wrapper.vhd) and the
-- pot selection lines of fpga64_sid_iec.vhd (pot_x1 .. pot_y2, pot_x_l/pot_y_l).
-- Models: xpm_cdc_array_single (SRC_INPUT_REG = 1, DEST_SYNC_FF = 2) for the flip
-- bit and the menu bits; the analog paddle pins (comparator output '1' once the
-- pin has charged after the discharge transistor released it).
--
-- G_VARIANT = 1: socket 1 has an Amiga tank mouse (pins 5/9 open, measured 255),
--                socket 2 a joystick (pins 5/9 open); Mouse: Port 1 Amiga, Port 2 C64
-- G_VARIANT = 2: like 1, but the mouse holds pins 5/9 high (active pot lines, small
--                measured values), right and middle button; also the switch
--                "#1: MEGA+left = right"
-- G_VARIANT = 3: no mouse; socket 1 has Commodore paddles, socket 2 Atari CX30
--                paddles; Paddles: Port 1 C64, Port 2 Atari CX30
-- G_VARIANT = 4: like 1, but "Port 2: Amiga" (wrong socket) to show that the
--                setting is per socket (the joystick gets masked, the mouse not)
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_issue266 is
   generic (
      G_VARIANT : natural := 1
   );
end entity tb_issue266;

architecture sim of tb_issue266 is

   constant C_QCLK_PERIOD : time := 20 ns;          -- QNICE, 50 MHz
   constant C_MCLK_PERIOD : time := 31718 ps;       -- core, 31,527,778 Hz
   constant C_NEVER       : integer := integer'high;

   signal qclk : std_logic := '0';
   signal mclk : std_logic := '0';
   signal sim_done : boolean := false;

   -- settings, QNICE clock domain (as the Shell writes them into M2M$CFM_DATA)
   signal q_flip   : std_logic := '0';
   signal q_amiga  : std_logic_vector(1 downto 0) := "00";
   signal q_rclick : std_logic_vector(1 downto 0) := "00";
   signal q_atari  : std_logic_vector(1 downto 0) := "00";

   -- model of xpm_cdc_array_single: source register, two destination flip-flops
   signal x_src, x_d, x_dd : std_logic_vector(4 downto 0) := (others => '0');
   signal main_flip_joyports : std_logic;
   signal main_mouse_amiga   : std_logic_vector(1 downto 0);
   signal main_mouse_rclick  : std_logic_vector(1 downto 0);

   -- socket pins, low active
   signal fa_up, fa_down, fa_left, fa_right, fa_fire : std_logic := '1';
   signal fb_up, fb_down, fb_left, fb_right, fb_fire : std_logic := '1';
   signal mega_key_n : std_logic := '1';

   -- paddle pins: charge time after release of the discharge transistor, in QNICE clock cycles
   type int4_t is array (0 to 3) of integer;
   signal pin_tc      : int4_t := (others => C_NEVER);   -- 0 = fa_potx (pin 9), 1 = fa_poty (pin 5), 2/3 = fb
   signal paddle_i    : std_logic_vector(3 downto 0) := "0000";
   signal paddle_drain: std_logic;
   signal since_rel   : integer := 0;

   -- mouse_input outputs and qnice_wrapper names
   signal qnice_pot1_x, qnice_pot1_y, qnice_pot2_x, qnice_pot2_y : unsigned(7 downto 0);
   signal qnice_flip_joyports_i : std_logic;
   signal qnice_pot1_x_n_o, qnice_pot1_y_n_o, qnice_pot2_x_n_o, qnice_pot2_y_n_o : unsigned(7 downto 0);

   -- core clock domain
   signal main_rst : std_logic := '1';
   signal main_pot1_x_n, main_pot1_y_n, main_pot2_x_n, main_pot2_y_n : std_logic_vector(7 downto 0);
   signal pot1_x_i, pot1_y_i, pot2_x_i, pot2_y_i : std_logic_vector(7 downto 0);   -- names of main.vhd
   signal j1_u, j1_d, j1_l, j1_r, j1_f : std_logic;   -- C64 control port 1 (debouncer outputs)
   signal j2_u, j2_d, j2_l, j2_r, j2_f : std_logic;   -- C64 control port 2

   -- C64 side
   signal key_num      : integer range 0 to 79 := 0;
   signal cia1_pao     : std_logic_vector(7 downto 0) := x"FF";
   signal cia1_pbo     : std_logic_vector(7 downto 0) := x"FF";
   signal cia1_pai     : std_logic_vector(7 downto 0);
   signal cia1_pbi     : std_logic_vector(7 downto 0);
   signal pot1, pot2, pot3, pot4 : std_logic_vector(7 downto 0);   -- names of fpga64_sid_iec.vhd
   signal pot_x1, pot_y1, pot_x2, pot_y2 : std_logic_vector(7 downto 0);
   signal sid_pot_x, sid_pot_y : std_logic_vector(7 downto 0);

   -- monitors
   signal mon_dirs_quiet  : boolean := false;   -- no direction line of either C64 port may be low
   signal mon_btns_quiet  : boolean := false;   -- additionally up/down (mouse buttons) and fire may not be low
   signal mon_fail        : natural := 0;

begin

   qclk <= not qclk after C_QCLK_PERIOD / 2 when not sim_done;
   mclk <= not mclk after C_MCLK_PERIOD / 2 when not sim_done;

   ---------------------------------------------------------------------------
   -- QNICE side
   ---------------------------------------------------------------------------

   -- analog paddle pins
   pin_model : process (qclk)
   begin
      if rising_edge(qclk) then
         if paddle_drain = '1' then
            since_rel <= 0;
         elsif since_rel < 1_000_000 then
            since_rel <= since_rel + 1;
         end if;
      end if;
   end process pin_model;

   gen_pins : for i in 0 to 3 generate
      paddle_i(i) <= '1' when paddle_drain = '0' and pin_tc(i) /= C_NEVER and since_rel >= pin_tc(i) else '0';
   end generate gen_pins;

   -- the instance of qnice_wrapper.vhd, same port map
   i_mouse_paddles: entity work.mouse_input
      port map (
         clk                     => qclk,
         mouse_debug             => open,
         amiga_mouse_enable_a    => '0',
         amiga_mouse_enable_b    => '0',
         amiga_mouse_assume_a    => '0',
         amiga_mouse_assume_b    => '0',
         atari_paddles_a         => q_atari(0),
         atari_paddles_b         => q_atari(1),
         fa_potx                 => paddle_i(0),
         fa_poty                 => paddle_i(1),
         fb_potx                 => paddle_i(2),
         fb_poty                 => paddle_i(3),
         pot_drain               => paddle_drain,
         fa_fire                 => '1',
         fa_left                 => '1',
         fa_right                => '1',
         fa_up                   => '1',
         fa_down                 => '1',
         fb_fire                 => '1',
         fb_left                 => '1',
         fb_right                => '1',
         fb_up                   => '1',
         fb_down                 => '1',
         fa_up_out               => open,
         fa_down_out             => open,
         fa_left_out             => open,
         fa_right_out            => open,
         fb_up_out               => open,
         fb_down_out             => open,
         fb_left_out             => open,
         fb_right_out            => open,
         pota_x                  => qnice_pot1_x,
         pota_y                  => qnice_pot1_y,
         potb_x                  => qnice_pot2_x,
         potb_y                  => qnice_pot2_y
      );

   qnice_flip_joyports_i <= q_flip;

   --VERBATIM-BEGIN qnice_wrapper.vhd
    -- We need to invert the values that we get from i_mouse_paddles
   correct_and_flip_paddles : process(all)
   begin
      if qnice_flip_joyports_i = '0' then
         qnice_pot1_x_n_o <= x"FF" - qnice_pot1_x;
         qnice_pot1_y_n_o <= x"FF" - qnice_pot1_y;
         qnice_pot2_x_n_o <= x"FF" - qnice_pot2_x;
         qnice_pot2_y_n_o <= x"FF" - qnice_pot2_y;
      else
         qnice_pot2_x_n_o <= x"FF" - qnice_pot1_x;
         qnice_pot2_y_n_o <= x"FF" - qnice_pot1_y;
         qnice_pot1_x_n_o <= x"FF" - qnice_pot2_x;
         qnice_pot1_y_n_o <= x"FF" - qnice_pot2_y;
      end if;
   end process correct_and_flip_paddles;
   --VERBATIM-END

   ---------------------------------------------------------------------------
   -- Clock domain crossings (framework.vhd)
   ---------------------------------------------------------------------------

   xpm_src : process (qclk)
   begin
      if rising_edge(qclk) then
         x_src <= q_flip & q_amiga & q_rclick;
      end if;
   end process xpm_src;

   xpm_dst : process (mclk)
   begin
      if rising_edge(mclk) then
         x_d  <= x_src;
         x_dd <= x_d;
      end if;
   end process xpm_dst;

   main_flip_joyports <= x_dd(4);
   main_mouse_amiga   <= x_dd(3 downto 2);
   main_mouse_rclick  <= x_dd(1 downto 0);

   i_qnice2main_paddles: entity work.cdc_stable
      generic map (
         G_REGISTER_SRC => true,
         G_DATA_SIZE    => 32
      )
      port map (
         src_clk_i                => qclk,
         src_data_i( 7 downto  0) => std_logic_vector(qnice_pot1_x_n_o),
         src_data_i(15 downto  8) => std_logic_vector(qnice_pot1_y_n_o),
         src_data_i(23 downto 16) => std_logic_vector(qnice_pot2_x_n_o),
         src_data_i(31 downto 24) => std_logic_vector(qnice_pot2_y_n_o),
         dst_clk_i                => mclk,
         dst_data_o( 7 downto  0) => main_pot1_x_n,
         dst_data_o(15 downto  8) => main_pot1_y_n,
         dst_data_o(23 downto 16) => main_pot2_x_n,
         dst_data_o(31 downto 24) => main_pot2_y_n
      );

   ---------------------------------------------------------------------------
   -- Core clock domain: the instance of framework.vhd
   ---------------------------------------------------------------------------

   i_joy_debouncer : entity work.debouncer
      generic map (
         CLK_FREQ             => 31_527_778
      )
      port map (
         clk                  => mclk,
         reset_n              => not main_rst,
         flip_joys_i          => main_flip_joyports,
         joy_1_on             => '1',
         joy_2_on             => '1',
         joy_1_up_n           => fa_up,
         joy_1_down_n         => fa_down,
         joy_1_left_n         => fa_left,
         joy_1_right_n        => fa_right,
         joy_1_fire_n         => fa_fire,
         dbnce_joy1_up_n      => j1_u,
         dbnce_joy1_down_n    => j1_d,
         dbnce_joy1_left_n    => j1_l,
         dbnce_joy1_right_n   => j1_r,
         dbnce_joy1_fire_n    => j1_f,
         joy_2_up_n           => fb_up,
         joy_2_down_n         => fb_down,
         joy_2_left_n         => fb_left,
         joy_2_right_n        => fb_right,
         joy_2_fire_n         => fb_fire,
         dbnce_joy2_up_n      => j2_u,
         dbnce_joy2_down_n    => j2_d,
         dbnce_joy2_left_n    => j2_l,
         dbnce_joy2_right_n   => j2_r,
         dbnce_joy2_fire_n    => j2_f,
         amiga_i              => main_mouse_amiga,
         amiga_rclick_i       => main_mouse_rclick,
         mega_key_n_i         => mega_key_n,
         pot1_x_i             => main_pot1_x_n,
         pot1_y_i             => main_pot1_y_n,
         pot2_x_i             => main_pot2_x_n,
         pot2_y_i             => main_pot2_y_n,
         pot1_x_o             => pot1_x_i,
         pot1_y_o             => pot1_y_i,
         pot2_x_o             => pot2_x_i,
         pot2_y_o             => pot2_y_i
      );

   ---------------------------------------------------------------------------
   -- C64: keyboard.vhd (joystick merge into CIA 1) and the SID pot selection
   ---------------------------------------------------------------------------

   key_scan : process (mclk)
   begin
      if rising_edge(mclk) then
         key_num <= (key_num + 1) mod 80;
      end if;
   end process key_scan;

   keyboard_inst : entity work.keyboard
      port map (
         clk_main_i      => mclk,
         reset_i         => main_rst,
         trigger_run_i   => '0',
         key_num_i       => key_num,
         key_pressed_n_i => '1',
         sc_freeze_i     => "000000",
         joy_1_up_n_i    => j1_u,
         joy_1_down_n_i  => j1_d,
         joy_1_left_n_i  => j1_l,
         joy_1_right_n_i => j1_r,
         joy_1_fire_n_i  => j1_f,
         joy_1_up_n_o    => open,
         joy_1_down_n_o  => open,
         joy_1_left_n_o  => open,
         joy_1_right_n_o => open,
         joy_1_fire_n_o  => open,
         joy_2_up_n_i    => j2_u,
         joy_2_down_n_i  => j2_d,
         joy_2_left_n_i  => j2_l,
         joy_2_right_n_i => j2_r,
         joy_2_fire_n_i  => j2_f,
         joy_2_up_n_o    => open,
         joy_2_down_n_o  => open,
         joy_2_left_n_o  => open,
         joy_2_right_n_o => open,
         joy_2_fire_n_o  => open,
         cia1_pai_o      => cia1_pai,
         cia1_pao_i      => cia1_pao,
         cia1_pbi_o      => cia1_pbi,
         cia1_pbo_i      => cia1_pbo,
         restore_n       => open,
         freeze_n        => open
      );

   -- main.vhd: pot1 => pot1_x_i, pot2 => pot1_y_i, pot3 => pot2_x_i, pot4 => pot2_y_i
   pot1 <= pot1_x_i;
   pot2 <= pot1_y_i;
   pot3 <= pot2_x_i;
   pot4 <= pot2_y_i;

   --VERBATIM-BEGIN fpga64_sid_iec.vhd
pot_x1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot1;
pot_y1 <= (others => '1' ) when cia1_pao(6) = '0' else not pot2;
pot_x2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot3;
pot_y2 <= (others => '1' ) when cia1_pao(7) = '0' else not pot4;
   --VERBATIM-END

   -- sid_top port map: pot_x_l => pot_x1 and pot_x2, pot_y_l => pot_y1 and pot_y2;
   -- sid_top.sv: 5'h19: data_out = pot_x_l (combinational read)
   sid_pot_x <= pot_x1 and pot_x2;
   sid_pot_y <= pot_y1 and pot_y2;

   ---------------------------------------------------------------------------
   -- Monitor: lines that must stay released while the mouse moves or the ports flip
   ---------------------------------------------------------------------------

   line_monitor : process (mclk)
      variable l : line;
   begin
      if rising_edge(mclk) then
         if mon_dirs_quiet then
            -- left/right of both ports are never mouse buttons: they must stay high
            -- up/down of the joystick port must stay high (nobody touches the joystick)
            -- up/down of the mouse port must stay high unless a button is pressed (not in these windows)
            if (j1_u and j1_d and j1_l and j1_r and j2_u and j2_d and j2_l and j2_r) /= '1' then
               write(l, string'("FAIL monitor: a direction line went low at ") & time'image(now) &
                        " port1 udlr=" & std_logic'image(j1_u) & std_logic'image(j1_d) & std_logic'image(j1_l) & std_logic'image(j1_r) &
                        " port2 udlr=" & std_logic'image(j2_u) & std_logic'image(j2_d) & std_logic'image(j2_l) & std_logic'image(j2_r));
               writeline(output, l);
               mon_fail <= mon_fail + 1;
            end if;
         end if;
         if mon_btns_quiet then
            if (j1_f and j2_f) /= '1' then
               write(l, string'("FAIL monitor: a fire line went low at ") & time'image(now));
               writeline(output, l);
               mon_fail <= mon_fail + 1;
            end if;
         end if;
      end if;
   end process line_monitor;

   ---------------------------------------------------------------------------
   -- Stimulus and checks
   ---------------------------------------------------------------------------

   stim : process
      variable fails  : natural := 0;
      variable passes : natural := 0;
      variable l      : line;
      -- quadrature state: index 0..3 per axis
      variable qx, qy : natural := 0;
      variable posx, posy : integer := 0;   -- expected mouse position (counts)

      type sl2_arr is array (0 to 3) of std_logic_vector(1 downto 0);
      -- X: (right, down) sequence 11, 10, 00, 01 counts +1 (mouse moves right)
      constant C_QX : sl2_arr := ("11", "10", "00", "01");
      -- Y: (left, up) sequence 11, 01, 00, 10 counts +1 (mouse moves away from the user)
      constant C_QY : sl2_arr := ("11", "01", "00", "10");

      procedure say(s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure;

      procedure chk(name : string; got, exp : integer) is
         variable ll : line;
      begin
         if got = exp then
            passes := passes + 1;
            write(ll, "PASS " & name & " = " & integer'image(got));
         else
            fails := fails + 1;
            write(ll, "FAIL " & name & " = " & integer'image(got) & ", expected " & integer'image(exp));
         end if;
         writeline(output, ll);
      end procedure;

      procedure chk_range(name : string; got, lo, hi : integer) is
         variable ll : line;
      begin
         if got >= lo and got <= hi then
            passes := passes + 1;
            write(ll, "PASS " & name & " = " & integer'image(got) & " (expected " & integer'image(lo) & ".." & integer'image(hi) & ")");
         else
            fails := fails + 1;
            write(ll, "FAIL " & name & " = " & integer'image(got) & ", expected " & integer'image(lo) & ".." & integer'image(hi));
         end if;
         writeline(output, ll);
      end procedure;

      -- POT value of a 1351 position as amiga_mouse.vhd presents it
      function pot_of(p : integer) return integer is
         variable u : unsigned(6 downto 0);
         variable r : unsigned(7 downto 0);
      begin
         u := to_unsigned(p mod 128, 7);
         r(7) := u(6);
         r(6) := not u(6);
         r(5 downto 1) := u(5 downto 1);
         r(0) := '0';
         return to_integer(r);
      end function;

      -- a C64 program reads: $DC00 = sel (pa_out as the CIA drives it: pra or not ddra), $DC01 with
      -- port B all inputs; LINES like inputmon: sum of the active lines (up 1, down 2, left 4, right 8, fire 16)
      procedure c64_read(sel : std_logic_vector(7 downto 0);
                         variable lines1, lines2, px, py : out integer) is
      begin
         cia1_pao <= sel;
         cia1_pbo <= x"FF";
         wait for 300 ns;
         wait until rising_edge(mclk);
         lines1 := 31 - to_integer(unsigned(cia1_pbi(4 downto 0)));
         lines2 := 31 - to_integer(unsigned(cia1_pai(4 downto 0)));
         px     := to_integer(unsigned(sid_pot_x));
         py     := to_integer(unsigned(sid_pot_y));
         cia1_pao <= x"7F";   -- the KERNAL default after its keyboard scan
      end procedure;

      -- read both ports as inputmon.prg does and check everything
      procedure check_ports(tag : string; l1, x1, y1, l2, x2, y2 : integer) is
         variable a, b, c, d : integer;
         variable ll : line;
      begin
         -- port 1 selected ($DC00 = 64 with DDR A = 192 -> pa_out = $7F)
         c64_read(x"7F", a, b, c, d);
         chk(tag & " C64 port 1 LINES ($DC01)", a, l1);
         chk(tag & " C64 port 1 POT X ($D419, $DC00 bit 6)", c, x1);
         chk(tag & " C64 port 1 POT Y ($D41A, $DC00 bit 6)", d, y1);
         write(ll, "INFO " & tag & " C64 port 1: a 3-button tester (pressed = low POT, MiSTer convention) shows fire2=" &
                   boolean'image(c < 128) & " fire3=" & boolean'image(d < 128));
         writeline(output, ll);
         -- port 2 selected ($DC00 = 128 with DDR A = 192 -> pa_out = $BF)
         c64_read(x"BF", a, b, c, d);
         chk(tag & " C64 port 2 LINES ($DC00)", b, l2);
         chk(tag & " C64 port 2 POT X ($D419, $DC00 bit 7)", c, x2);
         chk(tag & " C64 port 2 POT Y ($D41A, $DC00 bit 7)", d, y2);
         write(ll, "INFO " & tag & " C64 port 2: a 3-button tester (pressed = low POT, MiSTer convention) shows fire2=" &
                   boolean'image(c < 128) & " fire3=" & boolean'image(d < 128));
         writeline(output, ll);
         -- both selected (bits 6 and 7 high, e.g. DDR A = 0): the SID sees the AND of both ports
         c64_read(x"FF", a, b, c, d);
         chk(tag & " both selected POT X", c, to_integer(to_unsigned(x1, 8) and to_unsigned(x2, 8)));
         chk(tag & " both selected POT Y", d, to_integer(to_unsigned(y1, 8) and to_unsigned(y2, 8)));
         -- none selected
         c64_read(x"3F", a, b, c, d);
         chk(tag & " none selected POT X", c, 255);
         chk(tag & " none selected POT Y", d, 255);
      end procedure;

      -- read both ports with a tolerance on the POT values (paddles)
      procedure check_paddles(tag : string; x1lo, x1hi, y1lo, y1hi, x2lo, x2hi, y2lo, y2hi : integer) is
         variable a, b, c, d : integer;
      begin
         c64_read(x"7F", a, b, c, d);
         chk_range(tag & " C64 port 1 POT X", c, x1lo, x1hi);
         chk_range(tag & " C64 port 1 POT Y", d, y1lo, y1hi);
         c64_read(x"BF", a, b, c, d);
         chk_range(tag & " C64 port 2 POT X", c, x2lo, x2hi);
         chk_range(tag & " C64 port 2 POT Y", d, y2lo, y2hi);
      end procedure;

      procedure mouse_x(n : integer; gap : time) is
      begin
         for i in 1 to abs(n) loop
            if n > 0 then qx := (qx + 1) mod 4; else qx := (qx + 3) mod 4; end if;
            fa_right <= C_QX(qx)(1);
            fa_down  <= C_QX(qx)(0);
            wait for gap;
         end loop;
         posx := posx + n;
      end procedure;

      procedure mouse_y(n : integer; gap : time) is
      begin
         for i in 1 to abs(n) loop
            if n > 0 then qy := (qy + 1) mod 4; else qy := (qy + 3) mod 4; end if;
            fa_left <= C_QY(qy)(1);
            fa_up   <= C_QY(qy)(0);
            wait for gap;
         end loop;
         posy := posy + n;
      end procedure;

      -- interleaved movement of both axes, one edge per axis every 2 * gap
      procedure mouse_xy(nx, ny : integer; gap : time) is
         variable ix, iy : integer := 0;
      begin
         while ix < abs(nx) or iy < abs(ny) loop
            if ix < abs(nx) then
               if nx > 0 then qx := (qx + 1) mod 4; else qx := (qx + 3) mod 4; end if;
               fa_right <= C_QX(qx)(1);
               fa_down  <= C_QX(qx)(0);
               ix := ix + 1;
            end if;
            wait for gap;
            if iy < abs(ny) then
               if ny > 0 then qy := (qy + 1) mod 4; else qy := (qy + 3) mod 4; end if;
               fa_left <= C_QY(qy)(1);
               fa_up   <= C_QY(qy)(0);
               iy := iy + 1;
            end if;
            wait for gap;
         end loop;
         posx := posx + nx;
         posy := posy + ny;
      end procedure;

      procedure set_flip(v : std_logic) is
      begin
         wait until rising_edge(qclk);
         q_flip <= v;
         say("INFO " & time'image(now) & ": Flip joystick ports := " & std_logic'image(v));
      end procedure;

      -- watch the four POT values of the C64 ports (as the SID would see them with one port selected)
      -- after a flip: report the settle time and the number of distinct intermediate values
      procedure watch_transition(tag : string; x1e, y1e, x2e, y2e : integer; dur : time) is
         variable t0, tlast : time;
         variable v, vold : std_logic_vector(31 downto 0);
         variable changes : natural := 0;
         variable ll : line;
      begin
         t0 := now;
         tlast := now;
         vold := not pot1 & not pot2 & not pot3 & not pot4;
         while now - t0 < dur loop
            wait until rising_edge(mclk);
            v := not pot1 & not pot2 & not pot3 & not pot4;
            if v /= vold then
               changes := changes + 1;
               tlast := now;
               write(ll, "INFO " & tag & " transition at +" & time'image(now - t0) & ": C64 port 1 X/Y = " &
                         integer'image(to_integer(unsigned(v(31 downto 24)))) & "/" &
                         integer'image(to_integer(unsigned(v(23 downto 16)))) & ", C64 port 2 X/Y = " &
                         integer'image(to_integer(unsigned(v(15 downto 8)))) & "/" &
                         integer'image(to_integer(unsigned(v(7 downto 0)))));
               writeline(output, ll);
               vold := v;
            end if;
         end loop;
         write(ll, "INFO " & tag & ": " & integer'image(changes) & " changes of the POT inputs, last at +" & time'image(tlast - t0));
         writeline(output, ll);
         chk(tag & " settled C64 port 1 POT X input", to_integer(unsigned(v(31 downto 24))), x1e);
         chk(tag & " settled C64 port 1 POT Y input", to_integer(unsigned(v(23 downto 16))), y1e);
         chk(tag & " settled C64 port 2 POT X input", to_integer(unsigned(v(15 downto 8))), x2e);
         chk(tag & " settled C64 port 2 POT Y input", to_integer(unsigned(v(7 downto 0))), y2e);
      end procedure;

   begin
      say("INFO variant " & integer'image(G_VARIANT));

      -- menu state: written by the Shell before the core leaves reset
      case G_VARIANT is
         when 1 | 2 => q_amiga <= "01";        -- Port 1: Amiga, Port 2: C64
         when 4     => q_amiga <= "10";        -- Port 1: C64, Port 2: Amiga
         when others => q_amiga <= "00";
      end case;
      if G_VARIANT = 3 then
         q_atari <= "10";                      -- Paddles: Port 1 C64, Port 2 Atari CX30
      end if;
      if G_VARIANT = 2 then
         -- the mouse holds pins 9 and 5 high: charged 1 us after the release
         pin_tc(0) <= 50;
         pin_tc(1) <= 50;
      end if;
      if G_VARIANT = 3 then
         -- Commodore paddles at socket 1: 100 us and 50 us; Atari CX30 at socket 2: 400 us and 300 us
         pin_tc(0) <= 100 * 50;
         pin_tc(1) <=  50 * 50;
         pin_tc(2) <= 400 * 50;
         pin_tc(3) <= 300 * 50;
      end if;

      main_rst <= '1';
      wait for 2 us;
      wait until rising_edge(mclk);
      main_rst <= '0';
      -- debounce 1 ms, a few measuring cycles, the confirmation of the flag "pull-up seen" (4.4 ms)
      wait for 8 ms;

      ------------------------------------------------------------------------
      if G_VARIANT = 1 or G_VARIANT = 2 then
      ------------------------------------------------------------------------
         say("=== phase A: Flip joystick ports = Off");
         check_ports("A0", 0, pot_of(posx), pot_of(posy), 0, 255, 255);

         -- the mouse moves right and away from the user; no direction line may react
         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         mouse_xy(20, 12, 250 us);
         wait for 4 ms;
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("A1 after mouse moves +20/+12", 0, pot_of(posx), pot_of(posy), 0, 255, 255);

         -- joystick at socket 2: up + left + fire
         fb_up <= '0'; fb_left <= '0'; fb_fire <= '0';
         wait for 1.5 ms;
         check_ports("A2 joystick up+left+fire", 0, pot_of(posx), pot_of(posy), 21, 255, 255);
         fb_up <= '1'; fb_left <= '1'; fb_fire <= '1';
         wait for 1.5 ms;

         -- left mouse button
         fa_fire <= '0';
         wait for 1.5 ms;
         check_ports("A3 mouse left button", 16, pot_of(posx), pot_of(posy), 0, 255, 255);
         fa_fire <= '1';
         wait for 1.5 ms;

         if G_VARIANT = 2 then
            -- right button: pin 9 grounded
            pin_tc(0) <= C_NEVER;
            wait for 6 ms;
            check_ports("A4 mouse right button", 1, pot_of(posx), pot_of(posy), 0, 255, 255);
            pin_tc(0) <= 50;
            wait for 6 ms;
            -- middle button: pin 5 grounded
            pin_tc(1) <= C_NEVER;
            wait for 6 ms;
            check_ports("A5 mouse middle button", 2, pot_of(posx), pot_of(posy), 0, 255, 255);
            pin_tc(1) <= 50;
            wait for 6 ms;
            check_ports("A6 buttons released", 0, pot_of(posx), pot_of(posy), 0, 255, 255);
         end if;

         say("=== phase B: Flip joystick ports = On");
         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         set_flip('1');
         watch_transition("B transition", 255, 255, pot_of(posx), pot_of(posy), 8 ms);
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("B0", 0, 255, 255, 0, pot_of(posx), pot_of(posy));

         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         mouse_xy(-30, -8, 250 us);
         wait for 4 ms;
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("B1 after mouse moves -30/-8", 0, 255, 255, 0, pot_of(posx), pot_of(posy));

         fb_up <= '0'; fb_right <= '0'; fb_fire <= '0';
         wait for 1.5 ms;
         check_ports("B2 joystick up+right+fire", 25, 255, 255, 0, pot_of(posx), pot_of(posy));
         fb_up <= '1'; fb_right <= '1'; fb_fire <= '1';
         wait for 1.5 ms;
         fb_down <= '0';
         wait for 1.5 ms;
         check_ports("B3 joystick down", 2, 255, 255, 0, pot_of(posx), pot_of(posy));
         fb_down <= '1';
         wait for 1.5 ms;

         fa_fire <= '0';
         wait for 1.5 ms;
         check_ports("B4 mouse left button", 0, 255, 255, 16, pot_of(posx), pot_of(posy));
         fa_fire <= '1';
         wait for 1.5 ms;

         if G_VARIANT = 2 then
            pin_tc(0) <= C_NEVER;
            wait for 6 ms;
            check_ports("B5 mouse right button", 0, 255, 255, 1, pot_of(posx), pot_of(posy));
            pin_tc(0) <= 50;
            wait for 6 ms;
            pin_tc(1) <= C_NEVER;
            wait for 6 ms;
            check_ports("B6 mouse middle button", 0, 255, 255, 2, pot_of(posx), pot_of(posy));
            pin_tc(1) <= 50;
            wait for 6 ms;
            check_ports("B7 buttons released", 0, 255, 255, 0, pot_of(posx), pot_of(posy));

            -- right click with the MEGA key, switch "#1: MEGA+left = right" on
            q_rclick <= "01";
            wait for 100 us;
            mega_key_n <= '0';
            wait for 100 us;
            fa_fire <= '0';
            wait for 1.5 ms;
            check_ports("B8 MEGA+left (switch #1 on)", 0, 255, 255, 1, pot_of(posx), pot_of(posy));
            fa_fire <= '1';
            wait for 1.5 ms;
            mega_key_n <= '1';
            -- the joystick fire with the MEGA key held stays a fire press (socket 2 has no switch)
            mega_key_n <= '0';
            wait for 100 us;
            fb_fire <= '0';
            wait for 1.5 ms;
            check_ports("B9 MEGA held + joystick fire", 16, 255, 255, 0, pot_of(posx), pot_of(posy));
            fb_fire <= '1';
            wait for 1.5 ms;
            mega_key_n <= '1';
         end if;

         say("=== phase C: Flip joystick ports = Off again");
         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         set_flip('0');
         watch_transition("C transition", pot_of(posx), pot_of(posy), 255, 255, 8 ms);
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("C0", 0, pot_of(posx), pot_of(posy), 0, 255, 255);

         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         mouse_xy(6, 6, 250 us);
         wait for 4 ms;
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("C1 after mouse moves +6/+6", 0, pot_of(posx), pot_of(posy), 0, 255, 255);

         fb_left <= '0';
         wait for 1.5 ms;
         check_ports("C2 joystick left", 0, pot_of(posx), pot_of(posy), 4, 255, 255);
         fb_left <= '1';
         wait for 1.5 ms;

         fa_fire <= '0';
         wait for 1.5 ms;
         check_ports("C3 mouse left button", 16, pot_of(posx), pot_of(posy), 0, 255, 255);
         fa_fire <= '1';
         wait for 1.5 ms;

         if G_VARIANT = 2 then
            mega_key_n <= '0';
            wait for 100 us;
            fa_fire <= '0';
            wait for 1.5 ms;
            check_ports("C4 MEGA+left (switch #1 on)", 1, pot_of(posx), pot_of(posy), 0, 255, 255);
            fa_fire <= '1';
            wait for 1.5 ms;
            mega_key_n <= '1';
         end if;

         -- toggle the flip while the mouse moves: the pointer must keep its position
         -- and no direction line may react
         say("=== phase D: flip toggled while the mouse moves");
         mon_dirs_quiet <= true;
         mon_btns_quiet <= true;
         mouse_x(4, 500 us);
         set_flip('1');
         mouse_x(4, 500 us);
         wait for 4 ms;
         mon_dirs_quiet <= false;
         mon_btns_quiet <= false;
         check_ports("D0 flipped after moving +8/0", 0, 255, 255, 0, pot_of(posx), pot_of(posy));

      ------------------------------------------------------------------------
      elsif G_VARIANT = 4 then
      ------------------------------------------------------------------------
         -- wrong socket set to Amiga: the joystick of socket 2 is masked, the mouse of socket 1 is not
         say("=== variant 4: Port 2: Amiga (the socket with the joystick)");
         check_ports("W0", 0, 255, 255, 0, 64, 64);
         fb_up <= '0'; fb_left <= '0'; fb_fire <= '0';
         wait for 1.5 ms;
         -- up of an Amiga socket is the right button (released), left is masked: only fire passes
         check_ports("W1 joystick up+left+fire at socket 2 (Amiga)", 0, 255, 255, 16, 64, 64);
         fb_up <= '1'; fb_left <= '1'; fb_fire <= '1';
         wait for 1.5 ms;
         -- the Amiga mouse at socket 1 in C64 mode: its quadrature reaches the direction lines
         -- first step of X: (right, down) = "10", the down line goes low
         fa_right <= C_QX(1)(1);
         fa_down  <= C_QX(1)(0);
         wait for 1.5 ms;
         check_ports("W2 mouse at socket 1 (C64) after one X step", 2, 255, 255, 0, 64, 64);
         set_flip('1');
         wait for 3 ms;
         check_ports("W3 flipped: mouse lines now on C64 port 2, masked joystick on port 1", 0, 64, 64, 2, 255, 255);
         fb_up <= '0'; fb_right <= '0';
         wait for 1.5 ms;
         -- the joystick lines are decoded as quadrature: up+right = one step -1 on each axis -> position 127 -> 190
         check_ports("W4 flipped: joystick up+right at socket 2 (Amiga) on C64 port 1", 0, 190, 190, 2, 255, 255);
         fb_up <= '1'; fb_right <= '1';
         wait for 1.5 ms;

      ------------------------------------------------------------------------
      else  -- G_VARIANT = 3: paddles
      ------------------------------------------------------------------------
         say("=== phase A: Flip joystick ports = Off; Paddles Port 1 C64, Port 2 Atari CX30");
         -- socket 1 (C64): about 98 and 48; socket 2 (Atari): about 398/2 = 199 and 298/2 = 149
         check_paddles("PA", 95, 100, 45, 50, 196, 201, 146, 151);
         set_flip('1');
         wait for 3 ms;
         say("=== phase B: Flip joystick ports = On");
         check_paddles("PB", 196, 201, 146, 151, 95, 100, 45, 50);
         -- the Atari setting belongs to the socket: switching it to port 1 halves the C64 paddles
         -- at socket 1 and leaves socket 2 at its full (saturated) C64 reading
         q_atari <= "01";
         wait for 3 ms;
         say("=== phase C: Flip On; Paddles Port 1 Atari CX30, Port 2 C64 (deliberately wrong)");
         check_paddles("PC", 255, 255, 255, 255, 46, 51, 21, 26);
         set_flip('0');
         wait for 3 ms;
         say("=== phase D: Flip Off; Paddles Port 1 Atari CX30, Port 2 C64 (deliberately wrong)");
         check_paddles("PD", 46, 51, 21, 26, 255, 255, 255, 255);
      end if;

      wait for 10 us;
      fails := fails + mon_fail;
      if mon_fail /= 0 then
         say("FAIL monitor reported " & integer'image(mon_fail) & " violations");
      end if;
      if fails = 0 then
         say("RESULT variant " & integer'image(G_VARIANT) & ": PASS (" & integer'image(passes) & " checks)");
      else
         say("RESULT variant " & integer'image(G_VARIANT) & ": FAIL (" & integer'image(fails) & " failures, " &
             integer'image(passes) & " passes)");
      end if;
      sim_done <= true;
      wait;
   end process stim;

end architecture sim;
