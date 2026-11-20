-------------------------------------------------------------------------------
-- tb_hdmi_raw_wiring: the genlock wiring of M2M/vhdl/av_pipeline/digital_pipeline.vhd
-- (issue #184, doc/dev-hdmi-raw/SPEC.md section 5.1)
--
-- Under test: the real digital_pipeline.vhd with the real hdmi_genlock.vhd (or,
-- in the hostile build, a genlock whose line length is always wrong), fed through
-- the real crop.vhd as av_pipeline.vhd wires it. Around them:
--   * a model of the core's syncs and blanking as CORE/C64_MiSTerMEGA65/rtl/
--     video_sync.vhd produces them, one dot per four core clocks: PAL 504 x 312
--     (visible dots 107 to 488, lines 28 to 297, vsync from line 307 to 311),
--     NTSC 520 x 263 (visible dots 112 to 515, lines 13 to 262, vsync from line 0
--     to 4); the model starts at line 300 (PAL) or 0 (NTSC);
--   * the scaler: the cycle-exact output timing generator of ascal_timing.vhd;
--   * stand-ins for video_overlay, vga_to_hdmi and the serializers (not under test).
-- The clock periods are exact multiples (femtoseconds) so that a core frame is
-- exactly as long as in the hardware in pixel clocks of the raw mode: PAL core
-- clock 31.7178 ns with 13.432725 ns (720p) and 37.0041 ns (576p), NTSC core
-- clock 30.569682 ns with 13.508352 ns (720p) and 37.05416 ns (480p). That only
-- scales the time; the ratios are those of the hardware.
--
-- G_SCENARIO selects the stimulus (each one segment after the other, marked in
-- the VCD by tb_seg, tb_kind, tb_mode, tb_period, tb_tcore):
--   A  PAL, zoom off: raw 16:9 50 until locked; to raw 4:3 50 with a change of
--      the clock (hdmi_rst_i pulsed); to standard 4:3 50 (pulse); back to raw
--      4:3 50 (pulse)
--   B  PAL, zoom on: raw 4:3 50 until locked
--   C  PAL, zoom off: raw 5:4 50 until locked
--   D  NTSC, zoom off: raw 16:9 59.94 until locked
--   E  NTSC, zoom on: standard 4:3 59.94 without the core; to raw 4:3 59.94
--      without a change of the clock (no pulse) until locked; back to standard
--      4:3 59.94 without a pulse
--   F  NTSC, zoom on: raw 5:4 59.94 until locked
--   G  PAL core: the ten standard modes one frame each (hdmi_rst_i pulsed where
--      the clock changes), with two one-cycle raw codes between standard modes
--   H  hostile build: the ten standard modes, then raw 16:9 50 for a few lines
-- tb_kind: 0 transition (not checked), 1 standard mode, 2 raw mode that must lock,
-- 3 raw mode after a change (the genlock must act), 4 one-cycle raw code,
-- 5 raw mode right after a pulse of hdmi_rst_i (not locked at first), 6 raw mode
-- in the hostile build. For a lock the bench starts the core model so that the
-- first measurement of the genlock is 600 pixel clocks below its target.
--
-- run.sh dumps the signals into a VCD file and check_wiring.py checks them.
-- (ghdl 5.1 resolves no VHDL-2008 external names at run time, hence the VCD.)
-- Prints "SIMULATION DONE" at the end.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.video_modes_pkg.all;
use work.tb_hdmi_raw_wiring_pkg.all;

entity tb_hdmi_raw_wiring is
   generic (
      G_SCENARIO  : string := "A";
      G_FONT_FILE : string
   );
end entity tb_hdmi_raw_wiring;

architecture sim of tb_hdmi_raw_wiring is

   -- copy of framework.vhd VIDEO_MODE_VECTOR (check_wiring.py compares the two)
   constant VIDEO_MODE_VECTOR : video_modes_vector(0 to 15) := (
      C_HDMI_720p_50,
      C_HDMI_720p_60,
      C_HDMI_576p_50,
      C_HDMI_576p_50,
      C_HDMI_640x480p_60,
      C_HDMI_720x480p_5994,
      C_SVGA_800_600_60,
      C_HDMI_720p_5994,
      C_HDMI_720x480p_5994,
      C_HDMI_720x480p_5994,
      C_HDMI_720p_50_RAW,
      C_HDMI_576p_50_RAW,
      C_HDMI_576p_50_RAW,
      C_HDMI_720p_5994_RAW,
      C_HDMI_720x480p_5994_RAW,
      C_HDMI_720x480p_5994_RAW);

   -- clock periods in fs
   constant C_TCORE_PAL  : natural := 31717800;
   constant C_TCORE_NTSC : natural := 30569682;
   constant C_TBACKUP    : natural := 20000000;      -- 50 MHz backup clock of video_out_clock

   -- pixel clock period of a mode (position in video_mode_type)
   function period_of (m : natural) return natural is
   begin
      case m is
         when 10     => return 13432725;            -- raw PAL 720p
         when 11 | 12 => return 37004100;           -- raw PAL 576p
         when 13     => return 13508352;            -- raw NTSC 720p
         when 14 | 15 => return 37054160;           -- raw NTSC 480p
         when others =>
            case VIDEO_MODE_VECTOR(m).CLK_KHZ is
               when 74250  => return 13468013;
               when 74167  => return 13483146;
               when 27000  => return 37037037;
               when 25200  => return 39682540;
               when 40000  => return 25000000;
               when others => return 13468013;
            end case;
      end case;
   end function period_of;

   function htotal_of (m : natural) return natural is
   begin
      return VIDEO_MODE_VECTOR(m).H_PIXELS + VIDEO_MODE_VECTOR(m).H_FP +
             VIDEO_MODE_VECTOR(m).H_PULSE + VIDEO_MODE_VECTOR(m).H_BP;
   end function htotal_of;

   function vtotal_of (m : natural) return natural is
   begin
      return VIDEO_MODE_VECTOR(m).V_PIXELS + VIDEO_MODE_VECTOR(m).V_FP +
             VIDEO_MODE_VECTOR(m).V_PULSE + VIDEO_MODE_VECTOR(m).V_BP;
   end function vtotal_of;

   signal running     : boolean := true;
   signal video_clk   : std_logic := '0';
   signal hdmi_clk    : std_logic := '0';
   signal tcore       : natural := C_TCORE_PAL;
   signal tpix        : natural := C_TBACKUP;

   -- core model and crop
   signal core_ntsc   : std_logic := '0';
   signal core_run    : boolean := false;
   signal core_ce     : std_logic := '0';
   signal core_hs     : std_logic := '0';
   signal core_vs     : std_logic := '0';
   signal core_hblank : std_logic := '1';
   signal core_vblank : std_logic := '1';
   signal zoom        : std_logic := '0';
   signal crop_ce     : std_logic;
   signal crop_red    : std_logic_vector(7 downto 0);
   signal crop_green  : std_logic_vector(7 downto 0);
   signal crop_blue   : std_logic_vector(7 downto 0);
   signal crop_hs     : std_logic;
   signal crop_vs     : std_logic;
   signal crop_hblank : std_logic;
   signal crop_vblank : std_logic;

   -- HDMI side
   signal hdmi_mode   : video_mode_type := C_VIDEO_HDMI_16_9_50;
   signal hdmi_rst    : std_logic := '1';

   -- picture starts as the genlock sees them: the first rising edge of de after a falling edge of vs
   signal pic_count   : natural := 0;
   signal pic_time    : time := 0 fs;

   -- markers for check_wiring.py
   signal tb_seg      : natural := 0;
   signal tb_kind     : natural := 0;
   signal tb_mode     : natural := 0;
   signal tb_period   : natural := C_TBACKUP;
   signal tb_tcore    : natural := C_TCORE_PAL;

begin

   tb_period <= tpix;
   tb_tcore  <= tcore;

   p_video_clk : process
      variable hi : natural;
   begin
      while running loop
         hi := tcore / 2;
         video_clk <= '1';
         wait for hi * 1 fs;
         video_clk <= '0';
         wait for (tcore - hi) * 1 fs;
      end loop;
      wait;
   end process p_video_clk;

   p_hdmi_clk : process
      variable p, hi : natural;
   begin
      while running loop
         p  := tpix;
         hi := p / 2;
         hdmi_clk <= '1';
         wait for hi * 1 fs;
         hdmi_clk <= '0';
         wait for (p - hi) * 1 fs;
      end loop;
      wait;
   end process p_hdmi_clk;

   -- the core's syncs and blanking (video_sync.vhd), one dot per four clock cycles
   p_core : process (video_clk)
      variable ce_cnt : natural range 0 to 3 := 0;
      variable dot    : natural range 0 to 1023 := 0;
      variable line   : natural range 0 to 1023 := 300;
   begin
      if rising_edge(video_clk) then
         core_ce <= '0';
         if not core_run then
            ce_cnt := 0;
            dot    := 0;
            if core_ntsc = '1' then
               line := 0;
            else
               line := 300;
            end if;
            core_hs     <= '0';
            core_vs     <= '0';
            core_hblank <= '1';
            core_vblank <= '1';
         else
            if ce_cnt = 0 then
               core_ce <= '1';
               if core_ntsc = '1' then
                  if dot = 54 then core_hs <= '0'; end if;
                  if dot = 16 then
                     core_hs <= '1';
                     if line = 0 then core_vs <= '1'; end if;
                     if line = 4 then core_vs <= '0'; end if;
                  end if;
                  if line = 0  then core_vblank <= '1'; end if;
                  if line = 13 then core_vblank <= '0'; end if;
                  if dot = 516 then core_hblank <= '1'; end if;
                  if dot = 112 then core_hblank <= '0'; end if;
                  if dot = 519 then
                     dot := 0;
                     line := (line + 1) mod 263;
                  else
                     dot := dot + 1;
                  end if;
               else
                  if dot = 48 then core_hs <= '0'; end if;
                  if dot = 10 then
                     core_hs <= '1';
                     if line = 307 then core_vs <= '1'; end if;
                     if line = 311 then core_vs <= '0'; end if;
                  end if;
                  if line = 298 then core_vblank <= '1'; end if;
                  if line = 28  then core_vblank <= '0'; end if;
                  if dot = 489 then core_hblank <= '1'; end if;
                  if dot = 107 then core_hblank <= '0'; end if;
                  if dot = 503 then
                     dot := 0;
                     line := (line + 1) mod 312;
                  else
                     dot := dot + 1;
                  end if;
               end if;
            end if;
            ce_cnt := (ce_cnt + 1) mod 4;
         end if;
      end if;
   end process p_core;

   i_crop : entity work.crop
      port map (
         video_crop_mode_i => zoom,
         video_ntsc_i      => core_ntsc,
         video_clk_i       => video_clk,
         video_rst_i       => '0',
         video_ce_i        => core_ce,
         video_red_i       => (others => '0'),
         video_green_i     => (others => '0'),
         video_blue_i      => (others => '0'),
         video_hs_i        => core_hs,
         video_vs_i        => core_vs,
         video_hblank_i    => core_hblank,
         video_vblank_i    => core_vblank,
         video_ce_o        => crop_ce,
         video_red_o       => crop_red,
         video_green_o     => crop_green,
         video_blue_o      => crop_blue,
         video_hs_o        => crop_hs,
         video_vs_o        => crop_vs,
         video_hblank_o    => crop_hblank,
         video_vblank_o    => crop_vblank
      ); -- i_crop

   i_dp : entity work.digital_pipeline
      generic map (
         G_VIDEO_MODE_VECTOR    => VIDEO_MODE_VECTOR,
         G_AUDIO_CLOCK_RATE     => 12_288_000,
         G_VGA_DX               => 720,
         G_VGA_DY               => 540,
         G_FONT_FILE            => G_FONT_FILE,
         G_FONT_DX              => 16,
         G_FONT_DY              => 16
      )
      port map (
         video_clk_i            => video_clk,
         video_rst_i            => '0',
         video_ce_i             => crop_ce,
         video_red_i            => crop_red,
         video_green_i          => crop_green,
         video_blue_i           => crop_blue,
         video_hs_i             => crop_hs,
         video_vs_i             => crop_vs,
         video_hblank_i         => crop_hblank,
         video_vblank_i         => crop_vblank,
         audio_clk_i            => '0',
         audio_rst_i            => '0',
         audio_left_i           => (others => '0'),
         audio_right_i          => (others => '0'),
         hdmi_clk_i             => hdmi_clk,
         hdmi_rst_i             => hdmi_rst,
         tmds_clk_i             => '0',
         tmds_data_p_o          => open,
         tmds_data_n_o          => open,
         tmds_clk_p_o           => open,
         tmds_clk_n_o           => open,
         hdmi_dvi_i             => '0',
         hdmi_video_mode_i      => hdmi_mode,
         hdmi_crop_mode_i       => zoom,
         hdmi_osm_cfg_scaling_i => 0,
         hdmi_osm_cfg_enable_i  => '0',
         hdmi_osm_cfg_xy_i      => (others => '0'),
         hdmi_osm_cfg_dxdy_i    => (others => '0'),
         hdmi_osm_vram_addr_o   => open,
         hdmi_osm_vram_data_i   => (others => '0'),
         sys_info_hdmi_o        => open,
         video_hdmax_o          => open,
         video_vdmax_o          => open,
         qnice_ascal_mode_i     => (others => '0'),
         qnice_poly_clk_i       => '0',
         qnice_poly_dw_i        => (others => '0'),
         qnice_poly_a_i         => (others => '0'),
         qnice_poly_wr_i        => '0',
         hr_clk_i               => '0',
         hr_rst_i               => '0',
         hr_write_o             => open,
         hr_read_o              => open,
         hr_address_o           => open,
         hr_writedata_o         => open,
         hr_byteenable_o        => open,
         hr_burstcount_o        => open,
         hr_readdata_i          => (others => '0'),
         hr_readdatavalid_i     => '0',
         hr_waitrequest_i       => '0'
      ); -- i_dp

   p_pic : process (hdmi_clk)
      variable vs_d  : std_logic := '0';
      variable de_d  : std_logic := '0';
      variable armed : boolean := false;
   begin
      if rising_edge(hdmi_clk) then
         if scaler_vs = '0' and vs_d = '1' then
            armed := true;
         elsif scaler_de = '1' and de_d = '0' and armed then
            armed     := false;
            pic_count <= pic_count + 1;
            pic_time  <= now;
         end if;
         vs_d := scaler_vs;
         de_d := scaler_de;
      end if;
   end process p_pic;

   p_stim : process
      variable l     : line;
      variable seg   : natural := 0;

      procedure put (s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure put;

      procedure edges (n : natural) is
      begin
         for i in 1 to n loop
            wait until rising_edge(hdmi_clk);
         end loop;
      end procedure edges;

      procedure pictures (n : natural) is
         variable c : natural;
      begin
         c := pic_count;
         wait until pic_count = c + n;
      end procedure pictures;

      -- start a segment of the given kind in the given mode; with a change of the clock
      -- selector the change looks as video_out_clock makes it: the mode code changes,
      -- four cycles later the HDMI domain goes into reset and runs on the 50 MHz backup
      -- clock for 25 us, then on the new pixel clock (period_of(m), or period if it is not
      -- 0), and leaves the reset four cycles later; without a change of the clock selector
      -- the pixel clock stays as it is
      procedure segment (m : natural; kind : natural; with_rst : boolean; period : natural := 0) is
      begin
         wait until rising_edge(hdmi_clk);
         seg := seg + 1;
         tb_seg <= seg;
         hdmi_mode <= video_mode_type'val(m);
         tb_mode   <= m;
         if with_rst then
            tb_kind <= 0;
            edges(4);
            hdmi_rst <= '1';
            tpix     <= C_TBACKUP;
            wait for 25 us;
            wait until rising_edge(hdmi_clk);
            if period = 0 then
               tpix <= period_of(m);
            else
               tpix <= period;
            end if;
            edges(4);
            hdmi_rst <= '0';
            tb_kind  <= kind;
         else
            tb_kind <= kind;
         end if;
         put("segment " & integer'image(seg) & ": mode " & integer'image(m) & ", kind " & integer'image(kind) &
             ", reset " & boolean'image(with_rst) & " at " & time'image(now));
      end procedure segment;

      -- one-cycle raw code m between two standard modes: the next call of segment changes
      -- the code at the next clock edge
      procedure glitch (m : natural) is
      begin
         wait until rising_edge(hdmi_clk);
         seg := seg + 1;
         tb_seg    <= seg;
         hdmi_mode <= video_mode_type'val(m);
         tb_mode   <= m;
         tb_kind   <= 4;
         put("segment " & integer'image(seg) & ": one-cycle code of mode " & integer'image(m));
      end procedure glitch;

      -- start the core model so that the first valid measurement of the genlock (raw mode
      -- m, no stretch before it) is 600 pixel clocks below the target
      procedure start_core_for_lock (m : natural) is
         variable frame   : time;
         variable t_ref   : time;
         variable t_start : time;
         variable delay   : time;
         variable p       : time;
      begin
         p     := tpix * 1 fs;
         frame := p * (htotal_of(m) * vtotal_of(m));
         -- core clocks from the start of the model to the first visible pixel after vsync,
         -- plus crop and reference register (5 clocks); with zoom-in the first visible pixel
         -- is the corner of the crop window (crop.vhd: x_min dots right of the first visible
         -- dot, in the line in which y_count reaches y_min)
         if core_ntsc = '1' and zoom = '0' then
            delay := (tcore * 1 fs) * ((13 * 520 + 112) * 4 + 5);
         elsif core_ntsc = '1' then
            delay := (tcore * 1 fs) * (((13 + 22 - 1) * 520 + 112 + 30) * 4 + 5);
         elsif zoom = '0' then
            delay := (tcore * 1 fs) * (((312 - 300 + 28) * 504 + 107) * 4 + 5);
         else
            delay := (tcore * 1 fs) * (((312 - 300 + 28 + 31 - 1) * 504 + 107 + 19) * 4 + 5);
         end if;
         pictures(1);
         t_ref := pic_time - p * (1 + 2 * VIDEO_MODE_VECTOR(m).CLK_KHZ - 600) - p * 3;   -- 3: crossing and edge
         while t_ref - delay < now + 1 us loop
            t_ref := t_ref + frame;
         end loop;
         t_start := t_ref - delay;
         wait for t_start - now;
         wait until rising_edge(video_clk);
         core_run <= true;
         put("core started at " & time'image(now));
      end procedure start_core_for_lock;

   begin
      -- power-on: the HDMI domain in reset for 2 us
      if G_SCENARIO = "D" or G_SCENARIO = "E" or G_SCENARIO = "F" then
         core_ntsc <= '1';
         tcore     <= C_TCORE_NTSC;
      end if;
      if G_SCENARIO = "B" or G_SCENARIO = "E" or G_SCENARIO = "F" then
         zoom <= '1';
      end if;
      wait for 2 us;

      if G_SCENARIO = "A" then
         segment(10, 2, true);
         start_core_for_lock(10);
         pictures(13);
         segment(11, 5, true);
         pictures(2);
         segment(2, 1, true);
         pictures(2);
         segment(11, 3, true);
         pictures(3);
      elsif G_SCENARIO = "B" then
         segment(11, 2, true);
         start_core_for_lock(11);
         pictures(13);
      elsif G_SCENARIO = "C" then
         segment(12, 2, true);
         start_core_for_lock(12);
         pictures(13);
      elsif G_SCENARIO = "D" then
         segment(13, 2, true);
         start_core_for_lock(13);
         pictures(13);
      elsif G_SCENARIO = "E" then
         -- 480p and raw 480p share the 27 MHz clock (CLK_SEL 0001): the period of raw 480p
         -- that is exact for the NTSC core clock of the bench serves both
         segment(8, 1, true, period_of(14));
         pictures(2);
         segment(14, 2, false);
         start_core_for_lock(14);
         pictures(13);
         segment(8, 1, false);
         pictures(2);
      elsif G_SCENARIO = "F" then
         segment(15, 2, true);
         start_core_for_lock(15);
         pictures(13);
      elsif G_SCENARIO = "G" or G_SCENARIO = "H" then
         core_run <= true;
         for m in 0 to 9 loop
            if m = 8 and G_SCENARIO = "G" then
               glitch(10);                    -- 0111 -> 1010 -> 1000
            elsif m = 0 then
               null;
            end if;
            if m = 0 or VIDEO_MODE_VECTOR(m).CLK_SEL /= VIDEO_MODE_VECTOR(m - 1).CLK_SEL then
               segment(m, 1, true);
            else
               segment(m, 1, false);
            end if;
            pictures(2);
         end loop;
         if G_SCENARIO = "G" then
            glitch(13);                       -- 1001 -> 1101 -> 0000
            segment(0, 1, true);
            pictures(2);
         else
            segment(10, 6, true);
            edges(20000);
         end if;
      else
         put("unknown scenario " & G_SCENARIO);
      end if;

      wait until rising_edge(hdmi_clk);
      tb_kind <= 0;
      tb_seg  <= seg + 1;
      wait for 1 us;
      write(l, string'("SIMULATION DONE"));
      writeline(output, l);
      running <= false;
      std.env.finish;
      wait;
   end process p_stim;

end architecture sim;
