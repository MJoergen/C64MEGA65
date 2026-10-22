-------------------------------------------------------------------------------
-- tb_window_av: av_pipeline with the 10-entry video mode vector (issue #181)
--
-- Elaborates and runs the real M2M/vhdl/av_pipeline/av_pipeline.vhd (and with
-- it digital_pipeline, analog_pipeline, crop, vga_to_hdmi, ...) with the
-- VIDEO_MODE_VECTOR of framework.vhd. The concurrent assertions of
-- digital_pipeline run at time 0, so a vector that violates them is reported.
--
-- Stimulus: every member of video_mode_type, zoom-in off and on, and with
-- zoom-in off the OSM scaling indices 0 .. 8 (one-hot, as the Shell drives
-- them). Each step holds for 2 us, long enough for the QNICE inputs to cross
-- into the video and HDMI clock domains, and is marked on tb_phase:
--
--   tb_phase = 1000 + 100 * mode + 10 * zoom + scaling index
--
-- run_w2.sh dumps the internal signals of interest into a VCD file and
-- doc/dev-ntsc/tools/w2_checks.py (option --window-vcd) compares them at the
-- end of every step with doc/dev-ntsc/NTSC-SPEC.md sections 6.3, 6.5, 6.7,
-- 6.8 and 7.4. (ghdl 5.1 resolves no VHDL-2008 external names at run time,
-- hence the VCD.)
--
-- ghdl cannot elaborate three sub-entities that are not under test here
-- (ascal, video_overlay, serialiser_10to1_selectio, see
-- doc/dev-ntsc/tools/w2_standin.py); run_w2.sh replaces them with generated
-- stand-ins that keep their entity declarations, and csync (SystemVerilog)
-- with an XOR of the two syncs. The real video_overlay and vga_osm are
-- simulated by tb_osm_place.vhd.
--
-- Prints "SIMULATION DONE" at the end.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.video_modes_pkg.all;

entity tb_window_av is
   generic (
      G_FONT_FILE : string
   );
end entity tb_window_av;

architecture sim of tb_window_av is

   -- copy of framework.vhd VIDEO_MODE_VECTOR
   constant VIDEO_MODE_VECTOR : video_modes_vector(0 to 9) := (
      C_HDMI_720p_50,
      C_HDMI_720p_60,
      C_HDMI_576p_50,
      C_HDMI_576p_50,
      C_HDMI_640x480p_60,
      C_HDMI_720x480p_5994,
      C_SVGA_800_600_60,
      C_HDMI_720p_5994,
      C_HDMI_720x480p_5994,
      C_HDMI_720x480p_5994);

   signal qnice_clk   : std_logic := '0';
   signal video_clk   : std_logic := '0';
   signal hdmi_clk    : std_logic := '0';
   signal hr_clk      : std_logic := '0';
   signal audio_clk   : std_logic := '0';
   signal running     : boolean := true;

   signal video_mode  : std_logic_vector(3 downto 0) := (others => '0');
   signal zoom        : std_logic := '0';
   signal scaling     : std_logic_vector(8 downto 0) := "000000001";
   signal tb_phase    : natural := 0;

begin

   qnice_clk <= not qnice_clk after 10 ns    when running else '0';   -- 50 MHz
   video_clk <= not video_clk after 15.25 ns when running else '0';   -- ~32.8 MHz
   hdmi_clk  <= not hdmi_clk  after 6.75 ns  when running else '0';   -- ~74 MHz
   hr_clk    <= not hr_clk    after 5 ns     when running else '0';   -- 100 MHz
   audio_clk <= not audio_clk after 40.69 ns when running else '0';   -- 12.288 MHz

   i_av : entity work.av_pipeline
      generic map (
         G_VIDEO_MODE_VECTOR => VIDEO_MODE_VECTOR,
         G_AUDIO_CLOCK_RATE  => 12_288_000,
         G_VGA_DX            => 720,
         G_VGA_DY            => 540,
         G_FONT_FILE         => G_FONT_FILE,
         G_FONT_DX           => 16,
         G_FONT_DY           => 16
      )
      port map (
         video_clk_i             => video_clk,
         video_rst_i             => '0',
         video_ce_i              => '0',
         video_ce_ovl_i          => '0',
         video_red_i             => (others => '0'),
         video_green_i           => (others => '0'),
         video_blue_i            => (others => '0'),
         video_vs_i              => '0',
         video_hs_i              => '0',
         video_hblank_i          => '1',
         video_vblank_i          => '1',
         audio_clk_i             => audio_clk,
         audio_rst_i             => '0',
         audio_left_i            => (others => '0'),
         audio_right_i           => (others => '0'),
         qnice_clk_i             => qnice_clk,
         qnice_rst_i             => '0',
         qnice_osm_cfg_scaling_i => scaling,
         qnice_osm_cfg_xy_i      => x"1200",
         qnice_osm_cfg_dxdy_i    => x"1B1F",
         qnice_osm_cfg_enable_i  => '0',
         qnice_retro15kHz_i      => '0',
         qnice_scandoubler_i     => '1',
         qnice_csync_i           => '0',
         qnice_zoom_crop_i       => zoom,
         qnice_audio_filter_i    => '0',
         qnice_audio_mute_i      => '0',
         qnice_video_mode_i      => video_mode,
         qnice_dvi_i             => '0',
         qnice_poly_clk_i        => qnice_clk,
         qnice_poly_dw_i         => (others => '0'),
         qnice_poly_a_i          => (others => '0'),
         qnice_poly_wr_i         => '0',
         qnice_ascal_mode_i      => (others => '0'),
         qnice_hdmax_o           => open,
         qnice_vdmax_o           => open,
         qnice_h_pixels_o        => open,
         qnice_v_pixels_o        => open,
         qnice_h_pulse_o         => open,
         qnice_h_bp_o            => open,
         qnice_h_fp_o            => open,
         qnice_v_pulse_o         => open,
         qnice_v_bp_o            => open,
         qnice_v_fp_o            => open,
         qnice_h_freq_o          => open,
         qnice_address_i         => (others => '0'),
         qnice_data_i            => (others => '0'),
         qnice_wren_i            => '0',
         qnice_byteenable_i      => "00",
         qnice_q_o               => open,
         sys_clk_i               => hr_clk,
         sys_pps_i               => '0',
         hr_clk_i                => hr_clk,
         hr_rst_i                => '0',
         hr_write_o              => open,
         hr_read_o               => open,
         hr_address_o            => open,
         hr_writedata_o          => open,
         hr_byteenable_o         => open,
         hr_burstcount_o         => open,
         hr_readdata_i           => (others => '0'),
         hr_readdatavalid_i      => '0',
         hr_waitrequest_i        => '0',
         hr_high_o               => open,
         hr_low_o                => open,
         VGA_RED                 => open,
         VGA_GREEN               => open,
         VGA_BLUE                => open,
         VGA_HS                  => open,
         VGA_VS                  => open,
         vdac_clk                => open,
         vdac_sync_n             => open,
         vdac_blank_n            => open,
         audio_clk_o             => open,
         audio_reset_o           => open,
         audio_left_o            => open,
         audio_right_o           => open,
         hdmi_clk_i              => hdmi_clk,
         hdmi_rst_i              => '0',
         tmds_clk_i              => '0',
         tmds_data_p_o           => open,
         tmds_data_n_o           => open,
         tmds_clk_p_o            => open,
         tmds_clk_n_o            => open
      ); -- i_av

   p_stim : process
      variable l : line;
   begin
      for m in 0 to 9 loop
         video_mode <= video_mode_to_slv(video_mode_type'val(m));
         for z in 0 to 1 loop
            zoom <= '1' when z = 1 else '0';
            for s in 0 to 8 loop
               next when z = 1 and s > 0;
               scaling    <= (others => '0');
               scaling(s) <= '1';
               tb_phase   <= 1000 + 100 * m + 10 * z + s;
               wait for 2 us;
            end loop;
         end loop;
      end loop;
      tb_phase <= 9999;
      wait for 100 ns;
      write(l, string'("SIMULATION DONE"));
      writeline(output, l);
      running <= false;
      wait;
   end process p_stim;

end architecture sim;
