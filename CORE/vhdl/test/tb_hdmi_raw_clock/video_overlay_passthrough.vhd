-------------------------------------------------------------------------------
-- Architecture "passthrough" of video_overlay for the packet run of
-- tb_hdmi_raw_cts (issue #184)
--
-- run.sh puts it behind the entity declaration of the real video_overlay.vhd
-- (taken by doc/dev-ntsc/tools/w2_standin.py with vga_cfg_shift_i retyped to
-- integer: ghdl does not associate the integer hdmi_shift of digital_pipeline
-- with the natural port of the real entity). With the OSM off the real entity
-- passes the picture and the syncs through; here they pass through one register,
-- which is all that vga_to_hdmi needs for its data islands.
-------------------------------------------------------------------------------

architecture passthrough of video_overlay is
begin

   p_pass : process (vga_clk_i)
   begin
      if rising_edge(vga_clk_i) then
         vga_ce_o    <= vga_ce_i;
         vga_red_o   <= vga_red_i;
         vga_green_o <= vga_green_i;
         vga_blue_o  <= vga_blue_i;
         vga_hs_o    <= vga_hs_i;
         vga_vs_o    <= vga_vs_i;
         vga_de_o    <= vga_de_i;
      end if;
   end process p_pass;

   vga_vram_addr_o <= (others => '0');

end architecture passthrough;
