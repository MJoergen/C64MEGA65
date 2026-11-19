library ieee;
use ieee.std_logic_1164.all;

package video_modes_pkg is

   type video_modes_t is record
      CLK_KHZ     : integer;                       -- Pixel clock frequency in kHz, also the CTS value
                                                   -- of the HDMI audio clock regeneration
      CLK_SEL     : std_logic_vector(3 downto 0);  -- Pixel clock selection (video_out_clock.vhd)
                                                   -- 0000 =  25.200 MHz
                                                   -- 0001 =  27.000 MHz
                                                   -- 0010 =  74.250 MHz
                                                   -- 0011 = 148.500 MHz
                                                   -- 0100 =  25.175 MHz nominal, 25.1786 MHz actual
                                                   -- 0101 =  27.027 MHz nominal, 27.0313 MHz actual
                                                   -- 0110 =  74.176 MHz nominal, 74.1667 MHz actual
                                                   -- 0111 =  40.000 MHz
                                                   -- 1000 =  74.4444 MHz (PAL 720p at the C64 frame rate)
                                                   -- 1001 =  27.0238 MHz (PAL 576p at the C64 frame rate)
                                                   -- 1010 =  74.0625 MHz (NTSC 720p at the C64 frame rate)
                                                   -- 1011 to 1111 = 74.250 MHz (the table of 0010)
      CTS_FRAC_N  : integer;                       -- The pixel clock is CLK_KHZ + CTS_FRAC_N / CTS_FRAC_D kHz
      CTS_FRAC_D  : integer;                       -- (0 <= CTS_FRAC_N < CTS_FRAC_D <= 256); digital_pipeline
                                                   -- sends CLK_KHZ + 1 as CTS in that fraction of the packets
      CEA_CTA_VIC : integer;                       -- CEA/CTA VIC
      ASPECT      : std_logic_vector(1 downto 0);  -- aspect ratio: 01=4:3, 10=16:9
      PIXEL_REP   : std_logic;                     -- 0=no pixel repetition; 1=pixel repetition
      H_PIXELS    : integer;                       -- horizontal display width in pixels
      V_PIXELS    : integer;                       -- vertical display width in rows
      H_PULSE     : integer;                       -- horizontal sync pulse width in pixels
      H_BP        : integer;                       -- horizontal back porch width in pixels
      H_FP        : integer;                       -- horizontal front porch width in pixels
      V_PULSE     : integer;                       -- vertical sync pulse width in rows
      V_BP        : integer;                       -- vertical back porch width in rows
      V_FP        : integer;                       -- vertical front porch width in rows
      H_POL       : std_logic;                     -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       : std_logic;                     -- vertical sync pulse polarity (1 = positive, 0 = negative)
   end record video_modes_t;

   -- In the following, the supported video modes
   -- are sorted according to the CEA-861-D document

   --------------------------------------------------------
   -- 50 Hz modes
   --------------------------------------------------------

   -- PAL 720x576 @ 50 Hz
   -- Taken from section 4.9 in the document CEA-861-D
   constant C_PAL_720_576_50 : video_modes_t := (
      CLK_KHZ     => 27000,      -- 27.000 MHz
      CLK_SEL     => "0001",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 17,         -- CEA/CTA VIC 17=PAL 720x576 @ 50 Hz
      ASPECT      => "01",       -- aspect ratio: 01=4:3, 10=16:9: "01" for PAL
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 720,        -- horizontal display width in pixels
      V_PIXELS    => 576,        -- vertical display width in rows
      H_PULSE     => 64,         -- horizontal sync pulse width in pixels
      H_BP        => 63,         -- horizontal back porch width in pixels
      H_FP        => 17,         -- horizontal front porch width in pixels
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 39,         -- vertical back porch width in rows
      V_FP        => 5,          -- vertical front porch width in rows
      H_POL       => '0',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '0'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- HDMI 576p @ 50 Hz (720x576)
   -- Taken from section 4.9 in the document CEA-861-D
   constant C_HDMI_576p_50 : video_modes_t := (
      CLK_KHZ     => 27000,      -- 27.000 MHz
      CLK_SEL     => "0001",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 17,         -- CEA/CTA VIC: 720x576p, 50 Hz, 4:3
      ASPECT      => "01",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 720,        -- horizontal display width in pixels
      V_PIXELS    => 576,        -- vertical display width in rows
      H_FP        => 12,         -- horizontal front porch width in pixels
      H_PULSE     => 64,         -- horizontal sync pulse width in pixels
      H_BP        => 68,         -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 39,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- HDMI 720p @ 50 Hz (1280x720)
   -- Taken from section 4.7 in the document CEA-861-D
   constant C_HDMI_720p_50 : video_modes_t := (
      CLK_KHZ     => 74250,      -- 74.250 MHz
      CLK_SEL     => "0010",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 19,         -- CEA/CTA VIC: 1280x720p, 50 Hz, 16:9
      ASPECT      => "10",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 1280,       -- horizontal display width in pixels
      V_PIXELS    => 720,        -- vertical display width in rows
      H_FP        => 440,        -- horizontal front porch width in pixels
      H_PULSE     => 40,         -- horizontal sync pulse width in pixels
      H_BP        => 220,        -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 20,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );


   --------------------------------------------------------
   -- 59.94 Hz modes
   --------------------------------------------------------

   -- HDMI 480p @ 59.94 Hz (720x480)
   constant C_HDMI_720x480p_5994 : video_modes_t := (
      CLK_KHZ     => 27000,      -- 27.000 MHz
      CLK_SEL     => "0001",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 2,
      ASPECT      => "01",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 720,        -- horizontal display width in pixels
      V_PIXELS    => 480,        -- vertical display width in rows
      H_FP        => 16,         -- horizontal front porch width in pixels
      H_PULSE     => 62,         -- horizontal sync pulse width in pixels
      H_BP        => 60,         -- horizontal back porch width in pixels
      V_FP        => 9,          -- vertical front porch width in rows
      V_PULSE     => 6,          -- vertical sync pulse width in rows
      V_BP        => 30,         -- vertical back porch width in rows
      H_POL       => '0',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '0'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- HDMI 720p @ 59.94 Hz (1280x720)
   -- Same timing as C_HDMI_720p_60 (section 4.3 in the document CEA-861-D) with the
   -- 59.94 Hz pixel clock. CLK_KHZ is the clock that CLK_SEL "0110" really produces
   -- (74.1667 MHz instead of the nominal 74.25 MHz / 1.001 = 74.176 MHz), because
   -- digital_pipeline uses it as the CTS value of the HDMI audio clock regeneration.
   -- Frame rate: 74.1667 MHz / (1650 x 750) = 59.9327 Hz.
   -- The sync polarity is the one of C_HDMI_720p_50, which is the 720p mode that is
   -- field-proven with this core.
   constant C_HDMI_720p_5994 : video_modes_t := (
      CLK_KHZ     => 74167,      -- 74.1667 MHz (CLKFBOUT_MULT_F 22.25, DIVCLK_DIVIDE 3, CLKOUT1_DIVIDE 10)
      CLK_SEL     => "0110",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 4,          -- CEA/CTA VIC: 1280x720p, 59.94/60 Hz, 16:9
      ASPECT      => "10",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 1280,       -- horizontal display width in pixels
      V_PIXELS    => 720,        -- vertical display width in rows
      H_FP        => 110,        -- horizontal front porch width in pixels
      H_PULSE     => 40,         -- horizontal sync pulse width in pixels
      H_BP        => 220,        -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 20,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );


   --------------------------------------------------------
   -- 60.00 Hz modes
   --------------------------------------------------------

   -- HDMI 480p @ 60 Hz (640x480)
   constant C_HDMI_640x480p_60 : video_modes_t := (
      CLK_KHZ     => 25200,      -- 25.200 MHz
      CLK_SEL     => "0000",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 1,
      ASPECT      => "01",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 640,        -- horizontal display width in pixels
      V_PIXELS    => 480,        -- vertical display width in rows
      H_FP        => 16,         -- horizontal front porch width in pixels
      H_PULSE     => 96,         -- horizontal sync pulse width in pixels
      H_BP        => 48,         -- horizontal back porch width in pixels
      V_FP        => 10,         -- vertical front porch width in rows
      V_PULSE     => 2,          -- vertical sync pulse width in rows
      V_BP        => 33,         -- vertical back porch width in rows
      H_POL       => '0',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '0'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- HDMI 720p @ 60 Hz (1280x720)
   -- Taken from section 4.3 in the document CEA-861-D
   constant C_HDMI_720p_60 : video_modes_t := (
      CLK_KHZ     => 74250,      -- 74.250 MHz
      CLK_SEL     => "0010",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 4,          -- CEA/CTA VIC: 1280x720p, 60 Hz, 16:9
      ASPECT      => "10",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 1280,       -- horizontal display width in pixels
      V_PIXELS    => 720,        -- vertical display width in rows
      H_FP        => 110,        -- horizontal front porch width in pixels
      H_PULSE     => 40,         -- horizontal sync pulse width in pixels
      H_BP        => 220,        -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 20,         -- vertical back porch width in rows
      H_POL       => '0',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '0'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- SVGA 800x600 @ 60 Hz
   -- Taken from this link: http://tinyvga.com/vga-timing/800x600@60Hz
   -- CAUTION: CTA/CTV VIC does not officially support SVGA 800x600; there are some monitors, where it works, though
   constant C_SVGA_800_600_60 : video_modes_t := (
      CLK_KHZ     => 40000,      -- 40.000 MHz
      CLK_SEL     => "0111",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 65,         -- SVGA is not an official mode; "65" taken from here: https://www.raspberrypi.org/documentation/configuration/config-txt/video.md
      ASPECT      => "01",       -- aspect ratio: 01=4:3, 10=16:9: "01" for SVGA
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 800,        -- horizontal display width in pixels
      V_PIXELS    => 600,        -- vertical display width in rows
      H_PULSE     => 128,        -- horizontal sync pulse width in pixels
      H_BP        => 88,         -- horizontal back porch width in pixels
      H_FP        => 40,         -- horizontal front porch width in pixels
      V_PULSE     => 4,          -- vertical sync pulse width in rows
      V_BP        => 23,         -- vertical back porch width in rows
      V_FP        => 1,          -- vertical front porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );


   --------------------------------------------------------
   -- "Raw" modes: HDMI at the frame rate of the C64
   --------------------------------------------------------

   -- Each raw mode has the sync positions, polarities and VIC of the mode it is derived
   -- from. In 720p the totals are the standard ones and the pixel clock is slightly faster
   -- than the one that would give the C64 frame rate; digital_pipeline's genlock
   -- (hdmi_genlock.vhd) adds the missing pixel clocks in the vertical back porch. In 576p
   -- and 480p one line less or more and the pixel clock give exactly the C64 frame rate.
   -- CLK_KHZ + CTS_FRAC_N / CTS_FRAC_D is the exact pixel clock in kHz.

   -- PAL 720p: C_HDMI_720p_50 at 100 MHz x 67 / 90 = 74.444444 MHz (1980 x 750 at 50.131 Hz)
   constant C_HDMI_720p_50_RAW : video_modes_t := (
      CLK_KHZ     => 74444,      -- 74.444444 MHz = 74444 + 4/9 kHz
      CLK_SEL     => "1000",
      CTS_FRAC_N  => 4,
      CTS_FRAC_D  => 9,
      CEA_CTA_VIC => 19,         -- CEA/CTA VIC: 1280x720p, 50 Hz, 16:9
      ASPECT      => "10",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 1280,       -- horizontal display width in pixels
      V_PIXELS    => 720,        -- vertical display width in rows
      H_FP        => 440,        -- horizontal front porch width in pixels
      H_PULSE     => 40,         -- horizontal sync pulse width in pixels
      H_BP        => 220,        -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 20,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- PAL 576p: C_HDMI_576p_50 with 624 instead of 625 lines (V_FP 4 instead of 5) at
   -- 100 MHz x 227 / 840 = 27.023810 MHz: 864 x 624 pixel clocks per frame, exactly the
   -- frame rate of the PAL C64 (50.124291 Hz)
   constant C_HDMI_576p_50_RAW : video_modes_t := (
      CLK_KHZ     => 27023,      -- 27.023810 MHz = 27023 + 17/21 kHz
      CLK_SEL     => "1001",
      CTS_FRAC_N  => 17,
      CTS_FRAC_D  => 21,
      CEA_CTA_VIC => 17,         -- CEA/CTA VIC: 720x576p, 50 Hz, 4:3
      ASPECT      => "01",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 720,        -- horizontal display width in pixels
      V_PIXELS    => 576,        -- vertical display width in rows
      H_FP        => 12,         -- horizontal front porch width in pixels
      H_PULSE     => 64,         -- horizontal sync pulse width in pixels
      H_BP        => 68,         -- horizontal back porch width in pixels
      V_FP        => 4,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 39,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- NTSC 720p: C_HDMI_720p_5994 at 100 MHz x 237 / 320 = 74.062500 MHz (1650 x 750 at 59.848 Hz)
   constant C_HDMI_720p_5994_RAW : video_modes_t := (
      CLK_KHZ     => 74062,      -- 74.062500 MHz = 74062 + 1/2 kHz
      CLK_SEL     => "1010",
      CTS_FRAC_N  => 1,
      CTS_FRAC_D  => 2,
      CEA_CTA_VIC => 4,          -- CEA/CTA VIC: 1280x720p, 59.94/60 Hz, 16:9
      ASPECT      => "10",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 1280,       -- horizontal display width in pixels
      V_PIXELS    => 720,        -- vertical display width in rows
      H_FP        => 110,        -- horizontal front porch width in pixels
      H_PULSE     => 40,         -- horizontal sync pulse width in pixels
      H_BP        => 220,        -- horizontal back porch width in pixels
      V_FP        => 5,          -- vertical front porch width in rows
      V_PULSE     => 5,          -- vertical sync pulse width in rows
      V_BP        => 20,         -- vertical back porch width in rows
      H_POL       => '1',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '1'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   -- NTSC 480p: C_HDMI_720x480p_5994 with 526 instead of 525 lines (V_BP 31 instead of 30)
   -- at 27.000 MHz: 858 x 526 pixel clocks per frame, exactly the frame rate of the NTSC
   -- C64 (59.826105 Hz)
   constant C_HDMI_720x480p_5994_RAW : video_modes_t := (
      CLK_KHZ     => 27000,      -- 27.000 MHz
      CLK_SEL     => "0001",
      CTS_FRAC_N  => 0,          -- audio CTS = CLK_KHZ in every packet
      CTS_FRAC_D  => 1,
      CEA_CTA_VIC => 2,
      ASPECT      => "01",       -- apsect ratio: 01=4:3, 10=16:9
      PIXEL_REP   => '0',        -- no pixel repetition
      H_PIXELS    => 720,        -- horizontal display width in pixels
      V_PIXELS    => 480,        -- vertical display width in rows
      H_FP        => 16,         -- horizontal front porch width in pixels
      H_PULSE     => 62,         -- horizontal sync pulse width in pixels
      H_BP        => 60,         -- horizontal back porch width in pixels
      V_FP        => 9,          -- vertical front porch width in rows
      V_PULSE     => 6,          -- vertical sync pulse width in rows
      V_BP        => 31,         -- vertical back porch width in rows
      H_POL       => '0',        -- horizontal sync pulse polarity (1 = positive, 0 = negative)
      V_POL       => '0'         -- vertical sync pulse polarity (1 = positive, 0 = negative)
   );

   type video_modes_vector is array(natural range<>) of video_modes_t;

   type video_mode_type is (
      C_VIDEO_HDMI_16_9_50  ,  -- HDMI 1280x720    @ 50 Hz
      C_VIDEO_HDMI_16_9_60  ,  -- HDMI 1280x720    @ 60 Hz
      C_VIDEO_HDMI_4_3_50   ,  -- PAL  576p in 4:3 @ 50 Hz
      C_VIDEO_HDMI_5_4_50   ,  -- PAL  576p in 5:4 @ 50 Hz
      C_VIDEO_HDMI_640_60   ,  -- HDMI 640x480     @ 60 Hz
      C_VIDEO_HDMI_720_5994 ,  -- HDMI 720x480     @ 59.94 Hz
      C_VIDEO_SVGA_800_60   ,  -- SVGA 800x600     @ 60 Hz
      -- The NTSC modes are appended so that the encodings of the modes above do not move
      C_VIDEO_HDMI_16_9_5994,  -- NTSC 720p in 16:9 @ 59.94 Hz (1280x720)
      C_VIDEO_HDMI_4_3_5994 ,  -- NTSC 480p in 4:3  @ 59.94 Hz (720x480)
      C_VIDEO_HDMI_5_4_5994 ,  -- NTSC 480p in 5:4  @ 59.94 Hz (720x480)
      -- The raw modes (HDMI at the C64 frame rate) are appended for the same reason; each
      -- one is the mode of the same name without "_RAW" at the C64 frame rate
      C_VIDEO_HDMI_16_9_50_RAW  ,  -- PAL  720p in 16:9 @ 50.13 Hz  (1280x720)
      C_VIDEO_HDMI_4_3_50_RAW   ,  -- PAL  576p in 4:3  @ 50.12 Hz  (720x576)
      C_VIDEO_HDMI_5_4_50_RAW   ,  -- PAL  576p in 5:4  @ 50.12 Hz  (720x576)
      C_VIDEO_HDMI_16_9_5994_RAW,  -- NTSC 720p in 16:9 @ 59.85 Hz  (1280x720)
      C_VIDEO_HDMI_4_3_5994_RAW ,  -- NTSC 480p in 4:3  @ 59.83 Hz  (720x480)
      C_VIDEO_HDMI_5_4_5994_RAW    -- NTSC 480p in 5:4  @ 59.83 Hz  (720x480)
   );

   pure function video_mode_to_slv(video_mode : video_mode_type) return std_logic_vector;

   pure function slv_to_video_mode(video_mode_slv : std_logic_vector) return video_mode_type;

   -- true for the video modes that the C64 core uses while the machine runs in NTSC
   pure function video_mode_is_ntsc(video_mode : video_mode_type) return boolean;

   -- true for the raw modes (HDMI at the frame rate of the C64)
   pure function video_mode_is_raw(video_mode : video_mode_type) return boolean;

end package video_modes_pkg;

package body video_modes_pkg is

   pure function video_mode_to_slv(video_mode : video_mode_type) return std_logic_vector is
   begin
      case video_mode is
         when C_VIDEO_HDMI_16_9_50   => return "0000";
         when C_VIDEO_HDMI_16_9_60   => return "0001";
         when C_VIDEO_HDMI_4_3_50    => return "0010";
         when C_VIDEO_HDMI_5_4_50    => return "0011";
         when C_VIDEO_HDMI_640_60    => return "0100";
         when C_VIDEO_HDMI_720_5994  => return "0101";
         when C_VIDEO_SVGA_800_60    => return "0110";
         when C_VIDEO_HDMI_16_9_5994 => return "0111";
         when C_VIDEO_HDMI_4_3_5994  => return "1000";
         when C_VIDEO_HDMI_5_4_5994  => return "1001";
         when C_VIDEO_HDMI_16_9_50_RAW   => return "1010";
         when C_VIDEO_HDMI_4_3_50_RAW    => return "1011";
         when C_VIDEO_HDMI_5_4_50_RAW    => return "1100";
         when C_VIDEO_HDMI_16_9_5994_RAW => return "1101";
         when C_VIDEO_HDMI_4_3_5994_RAW  => return "1110";
         when C_VIDEO_HDMI_5_4_5994_RAW  => return "1111";
      end case;
   end function video_mode_to_slv;

   pure function slv_to_video_mode(video_mode_slv : std_logic_vector) return video_mode_type is
   begin
      case video_mode_slv is
         when "0000" => return C_VIDEO_HDMI_16_9_50;
         when "0001" => return C_VIDEO_HDMI_16_9_60;
         when "0010" => return C_VIDEO_HDMI_4_3_50;
         when "0011" => return C_VIDEO_HDMI_5_4_50;
         when "0100" => return C_VIDEO_HDMI_640_60;
         when "0101" => return C_VIDEO_HDMI_720_5994;
         when "0110" => return C_VIDEO_SVGA_800_60;
         when "0111" => return C_VIDEO_HDMI_16_9_5994;
         when "1000" => return C_VIDEO_HDMI_4_3_5994;
         when "1001" => return C_VIDEO_HDMI_5_4_5994;
         when "1010" => return C_VIDEO_HDMI_16_9_50_RAW;
         when "1011" => return C_VIDEO_HDMI_4_3_50_RAW;
         when "1100" => return C_VIDEO_HDMI_5_4_50_RAW;
         when "1101" => return C_VIDEO_HDMI_16_9_5994_RAW;
         when "1110" => return C_VIDEO_HDMI_4_3_5994_RAW;
         when "1111" => return C_VIDEO_HDMI_5_4_5994_RAW;
         when others => return C_VIDEO_HDMI_16_9_50;    -- metavalues (simulation only)
      end case;
   end function slv_to_video_mode;

   pure function video_mode_is_ntsc(video_mode : video_mode_type) return boolean is
   begin
      return video_mode = C_VIDEO_HDMI_16_9_5994     or video_mode = C_VIDEO_HDMI_4_3_5994     or
             video_mode = C_VIDEO_HDMI_5_4_5994      or
             video_mode = C_VIDEO_HDMI_16_9_5994_RAW or video_mode = C_VIDEO_HDMI_4_3_5994_RAW or
             video_mode = C_VIDEO_HDMI_5_4_5994_RAW;
   end function video_mode_is_ntsc;

   pure function video_mode_is_raw(video_mode : video_mode_type) return boolean is
   begin
      return video_mode = C_VIDEO_HDMI_16_9_50_RAW   or video_mode = C_VIDEO_HDMI_4_3_50_RAW   or
             video_mode = C_VIDEO_HDMI_5_4_50_RAW    or
             video_mode = C_VIDEO_HDMI_16_9_5994_RAW or video_mode = C_VIDEO_HDMI_4_3_5994_RAW or
             video_mode = C_VIDEO_HDMI_5_4_5994_RAW;
   end function video_mode_is_raw;

end package body video_modes_pkg;

