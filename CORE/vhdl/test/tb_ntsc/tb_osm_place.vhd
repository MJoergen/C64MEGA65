-------------------------------------------------------------------------------
-- tb_osm_place: OSM rows of the real video_overlay on the NTSC outputs
-- (issue #181, doc/dev-ntsc/NTSC-SPEC.md section 7)
--
-- Drives M2M/vhdl/av_pipeline/video_overlay.vhd (with vga_recover_counters,
-- vga_osm and the font ROM) with a synthetic 720-pixel-wide signal of G_ROWS
-- visible rows, OSM scaling index 0, the vertical shift G_VSHIFT and the
-- 15 kHz row doubling G_R15KHZ, and the OSM box of the options menu
-- (G_BOX = 0: 27 x 31 characters at character 18 / 0) or of the main screen
-- (G_BOX = 1: 45 x 33 at 0 / 0). Every VRAM cell returns attribute 0x3F, so
-- every OSM pixel is white on the black input.
--
-- For every visible screen row r it compares the real RTL with the integer
-- transcription of doc/dev-ntsc/tools/w2_checks.py at s = 0:
--   vga_row = r + G_VSHIFT (or 2 r + G_VSHIFT at 15 kHz), character row
--   vga_row / 16, OSM on exactly for the character rows of the box,
-- using the VRAM address that vga_osm requests (character row = address / 45)
-- and the colour of the output pixel. It then prints which screen rows show
-- the box and which character rows are cut off.
--
-- Only s = 0 can be simulated: for s > 0, vga_osm.vhd computes negative rows
-- above the scaling center (row + s * (row - DY * 8) / 8), which synthesis
-- wraps in 11 bits and ghdl stops on as a bound check failure. The scaled
-- rows (s = 1 .. 8) are covered by the transcription in w2_checks.py, which
-- this bench validates at s = 0.
--
-- Prints "RESULT: PASS" or "RESULT: FAIL <reason>".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_osm_place is
   generic (
      G_FONT_FILE : string;
      G_ROWS      : natural := 480;
      G_R15KHZ    : boolean := false;
      G_VSHIFT    : natural := 0;
      G_BOX       : natural := 0
   );
end entity tb_osm_place;

architecture sim of tb_osm_place is

   constant C_H_VIS    : natural := 720;
   constant C_H_TOT    : natural := 800;
   constant C_V_TOT    : natural := G_ROWS + 10;
   constant C_COL_ADDR : natural := 410;   -- sample the VRAM address here
   constant C_COL_RGB  : natural := 420;   -- and the output pixel here (pipeline delay 9)

   function box_x  return natural is begin if G_BOX = 0 then return 18; else return 0;  end if; end function;
   function box_dx return natural is begin if G_BOX = 0 then return 27; else return 45; end if; end function;
   function box_dy return natural is begin if G_BOX = 0 then return 31; else return 33; end if; end function;

   signal clk       : std_logic := '0';
   signal running   : boolean := true;
   signal col       : natural := 0;
   signal row       : natural := 0;
   signal frame     : natural := 0;
   signal de, hs, vs : std_logic := '0';
   signal vram_addr : std_logic_vector(15 downto 0);
   signal red_out   : std_logic_vector(7 downto 0);
   signal r15khz    : std_logic;

begin

   clk <= not clk after 5 ns when running else '0';

   p_timing : process (clk)
   begin
      if rising_edge(clk) then
         if col = C_H_TOT - 1 then
            col <= 0;
            if row = C_V_TOT - 1 then
               row   <= 0;
               frame <= frame + 1;
            else
               row <= row + 1;
            end if;
         else
            col <= col + 1;
         end if;
      end if;
   end process p_timing;

   r15khz <= '1' when G_R15KHZ else '0';

   de <= '1' when col < C_H_VIS and row < G_ROWS else '0';
   hs <= '1' when col >= 740 and col < 760 else '0';
   vs <= '1' when row >= G_ROWS + 2 and row < G_ROWS + 5 else '0';

   i_dut : entity work.video_overlay
      generic map (
         G_VGA_DX          => 720,
         G_VGA_DY          => 540,
         G_FONT_FILE       => G_FONT_FILE,
         G_FONT_DX         => 16,
         G_FONT_DY         => 16
      )
      port map (
         vga_clk_i         => clk,
         vga_ce_i          => '1',
         vga_red_i         => (others => '0'),
         vga_green_i       => (others => '0'),
         vga_blue_i        => (others => '0'),
         vga_hs_i          => hs,
         vga_vs_i          => vs,
         vga_de_i          => de,
         vga_cfg_scaling_i => 0,
         vga_cfg_shift_i   => 0,
         vga_cfg_vshift_i  => G_VSHIFT,
         vga_cfg_enable_i  => '1',
         vga_cfg_r15kHz_i  => r15khz,
         vga_cfg_xy_i      => std_logic_vector(to_unsigned(box_x * 256, 16)),
         vga_cfg_dxdy_i    => std_logic_vector(to_unsigned(box_dx * 256 + box_dy, 16)),
         vga_vram_addr_o   => vram_addr,
         vga_vram_data_i   => x"3F41",      -- attribute 0x3F (white on white), character 'A'
         vga_ce_o          => open,
         vga_red_o         => red_out,
         vga_green_o       => open,
         vga_blue_o        => open,
         vga_hs_o          => open,
         vga_vs_o          => open,
         vga_de_o          => open
      ); -- i_dut

   p_check : process
      type int_vector is array (natural range <>) of integer;
      variable row_min   : int_vector(0 to 63) := (others => integer'high);   -- OSM rows shown per character row
      variable row_max   : int_vector(0 to 63) := (others => -1);
      variable step      : natural;
      variable addr_row  : integer;
      variable vga_row   : natural;
      variable exp_c     : natural;
      variable exp_on    : boolean;
      variable is_on     : boolean;
      variable first_on  : integer := -1;
      variable last_on   : integer := -1;
      variable errors    : natural := 0;
      variable lost      : line;
      variable nlost     : natural := 0;
      variable l         : line;

      procedure put(s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure;

   begin
      -- frame 0 starts with unknown counters; check frame 1
      wait until rising_edge(clk) and frame = 1 and row = 0 and col = 0;
      for r in 0 to G_ROWS - 1 loop
         if G_R15KHZ then vga_row := 2 * r + G_VSHIFT; else vga_row := r + G_VSHIFT; end if;
         exp_c  := vga_row / 16;
         exp_on := exp_c < box_dy;                -- the box starts at character row 0
         wait until rising_edge(clk) and row = r and col = C_COL_ADDR;
         addr_row := to_integer(unsigned(vram_addr)) / 45;
         wait until rising_edge(clk) and row = r and col = C_COL_RGB;
         is_on := red_out = x"FF";
         if addr_row /= exp_c or is_on /= exp_on then
            if errors < 10 then
               put("  MISMATCH row " & integer'image(r) & ": character row " & integer'image(addr_row) &
                   " (expected " & integer'image(exp_c) & "), OSM " & boolean'image(is_on) &
                   " (expected " & boolean'image(exp_on) & ")");
            end if;
            errors := errors + 1;
         end if;
         if is_on then
            if first_on < 0 then first_on := r; end if;
            last_on := r;
            if addr_row >= 0 and addr_row <= 63 then
               if vga_row < row_min(addr_row) then row_min(addr_row) := vga_row; end if;
               if vga_row > row_max(addr_row) then row_max(addr_row) := vga_row; end if;
            end if;
         end if;
      end loop;

      -- a character row is cut off unless both its first and its last font row reach the
      -- screen (at 15 kHz only every other OSM row is shown)
      if G_R15KHZ then step := 2; else step := 1; end if;
      for c in 0 to box_dy - 1 loop
         if row_min(c) > 16 * c + step - 1 or row_max(c) < 16 * c + 16 - step then
            if nlost > 0 then write(lost, string'(",")); end if;
            write(lost, integer'image(c));
            nlost := nlost + 1;
         end if;
      end loop;
      if nlost = 0 then write(lost, string'("none")); end if;
      put("rows " & integer'image(G_ROWS) & ", 15 kHz " & boolean'image(G_R15KHZ) & ", vshift " &
          integer'image(G_VSHIFT) & ", box " & integer'image(box_dx) & "x" & integer'image(box_dy) &
          ", s = 0: OSM on screen rows " & integer'image(first_on) & " .. " & integer'image(last_on) &
          ", character rows cut off: " & lost.all);

      if errors = 0 then
         put("RESULT: PASS");
      else
         put("RESULT: FAIL " & integer'image(errors) & " rows differ from the transcription");
      end if;
      running <= false;
      wait;
   end process p_check;

end architecture sim;
