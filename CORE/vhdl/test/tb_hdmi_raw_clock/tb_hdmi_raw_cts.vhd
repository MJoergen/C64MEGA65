-------------------------------------------------------------------------------
-- tb_hdmi_raw_cts: the CTS value of the HDMI audio clock regeneration packets
-- (issue #184, doc/dev-hdmi-raw/SPEC.md section 6)
--
-- Runs the real M2M/vhdl/av_pipeline/digital_pipeline.vhd with the VIDEO_MODE_VECTOR
-- of framework.vhd. Only the audio clock runs (12.288 MHz): the process p_pcm_acr
-- (1 kHz packet strobe and CTS accumulator) and the 48 kHz enable live in that clock
-- domain, the mode record is combinational from hdmi_video_mode_i, and with the
-- HDMI, video and memory clocks stopped a run of a second of audio time is cheap.
--
-- Stimulus: the modes of C_STEPS one after the other, each for the number of
-- packets given there (the raw modes 252 packets = 2 x the least common multiple
-- of their CTS_FRAC_D 9, 21 and 2; the others 20), marked on tb_phase (position of
-- the member in video_mode_type). The raw modes alternate with the modes they are
-- derived from, so every change between a raw mode and a standard mode is covered;
-- at the end the raw modes follow each other (an accumulator value above the
-- CTS_FRAC_D of the next mode is cleared).
--
-- run.sh dumps audio_pcm_acr, audio_pcm_cts and tb_phase into a VCD file and
-- check_cts.py takes the CTS of every packet at the rising edge of the strobe.
-- (ghdl 5.1 resolves no VHDL-2008 external names at run time, hence the VCD.)
--
-- ghdl cannot elaborate some sub-entities that are not under test (ascal,
-- video_overlay, serialiser_10to1_selectio, see doc/dev-ntsc/tools/w2_standin.py);
-- run.sh replaces them with stand-ins. The genlock is the real hdmi_genlock.vhd.
--
-- G_PACKET = true: the CTS inside the regeneration packet. The HDMI clock runs
-- (the period of raw 576p), the HDMI domain leaves its reset after 2 us, and the
-- stimulus is raw 576p (CTS_FRAC 17 / 21) for 63 packets, then 576p for 5. run.sh
-- builds this variant with the output timing generator of the scaler
-- (CORE/vhdl/test/tb_hdmi_raw_wiring/ascal_timing.vhd) and a video_overlay that
-- passes the syncs through (video_overlay_passthrough.vhd), so that the real
-- vga_to_hdmi gets syncs and sends its data islands;
-- check_cts.py --packet takes the CTS of every ACR packet from pcm_cts_s of
-- vga_to_hdmi, the register whose bytes are copied into the packet when it is
-- sent (data_ack(1)).
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

entity tb_hdmi_raw_cts is
   generic (
      G_FONT_FILE : string;
      G_PACKET    : boolean := false
   );
end entity tb_hdmi_raw_cts;

architecture sim of tb_hdmi_raw_cts is

   -- copy of framework.vhd VIDEO_MODE_VECTOR (check_cts.py compares the two)
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

   type step_t is record
      mode    : natural;      -- position in video_mode_type
      packets : natural;
   end record step_t;
   type step_vector is array (natural range <>) of step_t;
   constant C_STEPS : step_vector := (
      (0, 20), (10, 252), (0, 20), (1, 20), (2, 20), (11, 252), (2, 20), (3, 20), (12, 252), (3, 20),
      (4, 20), (5, 20), (6, 20), (7, 20), (13, 252), (7, 20), (8, 20), (14, 20), (8, 20), (9, 20),
      (15, 20), (9, 20), (13, 20), (10, 20), (11, 60), (10, 20), (13, 20), (11, 60), (0, 20));
   constant C_STEPS_PACKET : step_vector := ((11, 63), (2, 5));

   function steps return step_vector is
   begin
      if G_PACKET then
         return C_STEPS_PACKET;
      end if;
      return C_STEPS;
   end function steps;

   constant C_RUN : step_vector := steps;

   signal audio_clk  : std_logic := '0';
   signal running    : boolean := true;
   signal video_mode : video_mode_type := C_VIDEO_HDMI_16_9_50;
   signal tb_phase   : natural := 0;
   signal hdmi_clk   : std_logic := '0';
   signal hdmi_rst   : std_logic := '1';

begin

   audio_clk <= not audio_clk after 40.69 ns when running else '0';   -- 12.288 MHz

   -- G_PACKET: the HDMI clock of raw 576p (37.0041 ns) and the end of the HDMI reset after 2 us
   g_hdmi_clock : if G_PACKET generate
      hdmi_clk <= not hdmi_clk after 18502050 fs when running else '0';
      hdmi_rst <= '0' after 2 us;
   end generate g_hdmi_clock;

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
         video_clk_i            => '0',
         video_rst_i            => '0',
         video_ce_i             => '0',
         video_red_i            => (others => '0'),
         video_green_i          => (others => '0'),
         video_blue_i           => (others => '0'),
         video_hs_i             => '0',
         video_vs_i             => '0',
         video_hblank_i         => '1',
         video_vblank_i         => '1',
         audio_clk_i            => audio_clk,
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
         hdmi_video_mode_i      => video_mode,
         hdmi_crop_mode_i       => '0',
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

   p_stim : process
      variable l : line;
   begin
      for i in C_RUN'range loop
         video_mode <= video_mode_type'val(C_RUN(i).mode);
         tb_phase   <= C_RUN(i).mode;
         wait for C_RUN(i).packets * 1 ms;
      end loop;
      tb_phase <= 99;
      wait for 200 us;                                       -- the last request is sent within a line
      write(l, string'("SIMULATION DONE"));
      writeline(output, l);
      running <= false;
      wait;
   end process p_stim;

end architecture sim;
