----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Optional crop/zoom feature used by the digital pipeline.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2022 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity crop is
   port (
      video_crop_mode_i : in  std_logic;
      video_ntsc_i      : in  std_logic;  -- 0 = PAL input stream, 1 = NTSC input stream

      -- Input video stream
      video_clk_i       : in  std_logic;
      video_rst_i       : in  std_logic;
      video_ce_i        : in  std_logic;
      video_red_i       : in  std_logic_vector(7 downto 0);
      video_green_i     : in  std_logic_vector(7 downto 0);
      video_blue_i      : in  std_logic_vector(7 downto 0);
      video_hs_i        : in  std_logic;
      video_vs_i        : in  std_logic;
      video_hblank_i    : in  std_logic;
      video_vblank_i    : in  std_logic;

      -- Output video stream
      video_ce_o        : out std_logic;
      video_red_o       : out std_logic_vector(7 downto 0);
      video_green_o     : out std_logic_vector(7 downto 0);
      video_blue_o      : out std_logic_vector(7 downto 0);
      video_hs_o        : out std_logic;
      video_vs_o        : out std_logic;
      video_hblank_o    : out std_logic;
      video_vblank_o    : out std_logic
   );
end entity crop;

architecture synthesis of crop is

   -- These constants are properties of the input stream: the position of the 320x200
   -- display window of the C64 inside the visible area that the MiSTer video_sync.vhd
   -- produces (PAL 382x270, NTSC 404x250). x_count is 0 on the first visible pixel of a
   -- line, y_count is 1 on the first visible line of a frame.
   -- PAL:  33 + 320 + 29 = 382, 35 + 200 + 35 = 270
   -- NTSC: 44 + 320 + 40 = 404, 26 + 200 + 24 = 250. The VIC-II 6567R8 line is 16 dots
   -- longer, which moves the window 11 dots to the right relative to the end of hblank,
   -- and video_sync starts the visible area 9 lines closer to the window (measured with
   -- the real VIC-II in CORE/vhdl/test/tb_ntsc/tb_crop_ntsc.vhd). Depending on the phase
   -- of the core video clock enable relative to the VIC-II pixel grid, the window can
   -- start one pixel earlier; that applies to both standards alike.
   constant LEFT_BORDER_IN_PAL  : natural := 33;
   constant TOP_BORDER_IN_PAL   : natural := 35;
   constant LEFT_BORDER_IN_NTSC : natural := 44;
   constant TOP_BORDER_IN_NTSC  : natural := 26;
   constant IMAGE_SIZE_X        : natural := 320;
   constant IMAGE_SIZE_Y        : natural := 200;

   -- These are the new desired borders (348x208 output in both standards).
   -- MiSTer has no equivalent of this zoom: its vertical crop (vcrop/video_freak in c64.sv)
   -- crops to an integer scale of the HDMI height instead.
   constant LEFT_BORDER_NEW   : natural := 14;
   constant RIGHT_BORDER_NEW  : natural := 14;
   constant TOP_BORDER_NEW    : natural := 4;
   constant BOTTOM_BORDER_NEW : natural := 4;

   constant X_MIN_PAL  : natural := LEFT_BORDER_IN_PAL-LEFT_BORDER_NEW;
   constant X_MAX_PAL  : natural := LEFT_BORDER_IN_PAL+IMAGE_SIZE_X+RIGHT_BORDER_NEW-1;
   constant Y_MIN_PAL  : natural := TOP_BORDER_IN_PAL-TOP_BORDER_NEW;
   constant Y_MAX_PAL  : natural := TOP_BORDER_IN_PAL+IMAGE_SIZE_Y+BOTTOM_BORDER_NEW-1;
   constant X_MIN_NTSC : natural := LEFT_BORDER_IN_NTSC-LEFT_BORDER_NEW;
   constant X_MAX_NTSC : natural := LEFT_BORDER_IN_NTSC+IMAGE_SIZE_X+RIGHT_BORDER_NEW-1;
   constant Y_MIN_NTSC : natural := TOP_BORDER_IN_NTSC-TOP_BORDER_NEW;
   constant Y_MAX_NTSC : natural := TOP_BORDER_IN_NTSC+IMAGE_SIZE_Y+BOTTOM_BORDER_NEW-1;

   signal x_min : natural range 0 to 2047;
   signal x_max : natural range 0 to 2047;
   signal y_min : natural range 0 to 1023;
   signal y_max : natural range 0 to 1023;

   signal video_hblank_d : std_logic;
   signal video_vblank_d : std_logic;
   signal x_count : natural range 0 to 2047;
   signal y_count : natural range 0 to 1023;

   signal crop_active : std_logic;

begin

   p_count : process (video_clk_i)
   begin
      if rising_edge(video_clk_i) then
         if video_ce_i = '1' then
            video_hblank_d <= video_hblank_i;
            video_vblank_d <= video_vblank_i;

            x_count <= x_count + 1;
            if video_hblank_d = '1' and video_hblank_i = '0' then
               x_count <= 0;
               y_count <= y_count + 1;
            end if;

            if video_vblank_d = '1' and video_vblank_i = '0' then
               y_count <= 0;
            end if;
         end if;

         video_ce_o    <= video_ce_i;
         video_red_o   <= video_red_i;
         video_green_o <= video_green_i;
         video_blue_o  <= video_blue_i;
         video_hs_o    <= video_hs_i;
         video_vs_o    <= video_vs_i;
      end if;
   end process p_count;

   x_min <= X_MIN_NTSC when video_ntsc_i = '1' else X_MIN_PAL;
   x_max <= X_MAX_NTSC when video_ntsc_i = '1' else X_MAX_PAL;
   y_min <= Y_MIN_NTSC when video_ntsc_i = '1' else Y_MIN_PAL;
   y_max <= Y_MAX_NTSC when video_ntsc_i = '1' else Y_MAX_PAL;

   crop_active <= video_crop_mode_i when x_count < x_min or x_count > x_max or
                                         y_count < y_min or y_count > y_max else '0';

   video_hblank_o <= video_hblank_d or crop_active;
   video_vblank_o <= video_vblank_d or crop_active;

end architecture synthesis;

