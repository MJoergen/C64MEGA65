-------------------------------------------------------------------------------
-- tb_video_modes: M2M/vhdl/av_pipeline/video_modes_pkg.vhd (issue #181)
--
-- doc/dev-ntsc/NTSC-SPEC.md section 10.2 items 2 and 7:
--
--   * slv_to_video_mode(video_mode_to_slv(m)) = m for every member
--   * the codes of all members, the old ones unchanged, the three NTSC ones
--     "0111", "1000", "1001", and the six unused codes falling back to
--     C_VIDEO_HDMI_16_9_50
--   * video_mode_is_ntsc is true for exactly the three NTSC members
--   * C_HDMI_720p_5994: htotal x vtotal = 1650 x 750, CLK_KHZ = 74167,
--     CLK_SEL "110", VIC 4, 16:9, the sync polarity of C_HDMI_720p_50
--
-- Prints "RESULT: PASS" or "RESULT: FAIL <n> mismatches".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

library work;
use work.video_modes_pkg.all;

entity tb_video_modes is
end entity tb_video_modes;

architecture sim of tb_video_modes is
begin

   p_test : process
      type code_vector is array (video_mode_type) of std_logic_vector(3 downto 0);
      constant C_CODES : code_vector := (
         C_VIDEO_HDMI_16_9_50   => "0000",
         C_VIDEO_HDMI_16_9_60   => "0001",
         C_VIDEO_HDMI_4_3_50    => "0010",
         C_VIDEO_HDMI_5_4_50    => "0011",
         C_VIDEO_HDMI_640_60    => "0100",
         C_VIDEO_HDMI_720_5994  => "0101",
         C_VIDEO_SVGA_800_60    => "0110",
         C_VIDEO_HDMI_16_9_5994 => "0111",
         C_VIDEO_HDMI_4_3_5994  => "1000",
         C_VIDEO_HDMI_5_4_5994  => "1001");

      variable errors : natural := 0;
      variable ntsc   : natural := 0;
      variable r      : video_modes_t;
      variable code   : std_logic_vector(3 downto 0);

      procedure put(s : string) is
         variable l : line;
      begin
         write(l, s);
         writeline(output, l);
      end procedure;

      procedure check(cond : boolean; what : string) is
      begin
         if not cond then
            put("  MISMATCH: " & what);
            errors := errors + 1;
         end if;
      end procedure;

   begin
      check(video_mode_type'pos(video_mode_type'high) = 9, "video_mode_type does not have 10 members");
      check(video_mode_type'val(7) = C_VIDEO_HDMI_16_9_5994 and video_mode_type'val(8) = C_VIDEO_HDMI_4_3_5994 and
            video_mode_type'val(9) = C_VIDEO_HDMI_5_4_5994, "NTSC members are not appended at positions 7, 8, 9");

      for m in video_mode_type loop
         code := video_mode_to_slv(m);
         put(video_mode_type'image(m) & " -> """ & to_string(code) & """ -> " &
             video_mode_type'image(slv_to_video_mode(code)) & ", video_mode_is_ntsc = " &
             boolean'image(video_mode_is_ntsc(m)));
         check(code = C_CODES(m), video_mode_type'image(m) & " has code " & to_string(code));
         check(slv_to_video_mode(code) = m, video_mode_type'image(m) & " does not round-trip");
         check(video_mode_is_ntsc(m) = (m = C_VIDEO_HDMI_16_9_5994 or m = C_VIDEO_HDMI_4_3_5994 or
                                        m = C_VIDEO_HDMI_5_4_5994), "video_mode_is_ntsc(" & video_mode_type'image(m) & ")");
         if video_mode_is_ntsc(m) then
            ntsc := ntsc + 1;
         end if;
      end loop;
      check(ntsc = 3, "video_mode_is_ntsc is true for " & integer'image(ntsc) & " members");

      for i in 10 to 15 loop
         code := std_logic_vector(to_unsigned(i, 4));
         check(slv_to_video_mode(code) = C_VIDEO_HDMI_16_9_50, "unused code " & to_string(code) & " does not fall back");
      end loop;

      r := C_HDMI_720p_5994;
      put("C_HDMI_720p_5994: " & integer'image(r.H_PIXELS + r.H_FP + r.H_PULSE + r.H_BP) & " x " &
          integer'image(r.V_PIXELS + r.V_FP + r.V_PULSE + r.V_BP) & " total, CLK_KHZ " & integer'image(r.CLK_KHZ) &
          ", CLK_SEL " & to_string(r.CLK_SEL) & ", VIC " & integer'image(r.CEA_CTA_VIC));
      check(r.H_PIXELS = 1280 and r.V_PIXELS = 720, "C_HDMI_720p_5994 is not 1280 x 720");
      check(r.H_PIXELS + r.H_FP + r.H_PULSE + r.H_BP = 1650, "C_HDMI_720p_5994 htotal is not 1650");
      check(r.V_PIXELS + r.V_FP + r.V_PULSE + r.V_BP = 750, "C_HDMI_720p_5994 vtotal is not 750");
      check(r.CLK_KHZ = 74167 and r.CLK_SEL = "110", "C_HDMI_720p_5994 CLK_KHZ / CLK_SEL");
      check(r.CEA_CTA_VIC = 4 and r.ASPECT = "10" and r.PIXEL_REP = '0', "C_HDMI_720p_5994 VIC / ASPECT / PIXEL_REP");
      check(r.H_POL = C_HDMI_720p_50.H_POL and r.V_POL = C_HDMI_720p_50.V_POL, "C_HDMI_720p_5994 sync polarity");
      -- the same timing as C_HDMI_720p_60 except clock and polarity
      check(r.H_FP = C_HDMI_720p_60.H_FP and r.H_PULSE = C_HDMI_720p_60.H_PULSE and r.H_BP = C_HDMI_720p_60.H_BP and
            r.V_FP = C_HDMI_720p_60.V_FP and r.V_PULSE = C_HDMI_720p_60.V_PULSE and r.V_BP = C_HDMI_720p_60.V_BP,
            "C_HDMI_720p_5994 porches differ from C_HDMI_720p_60");

      if errors = 0 then
         put("RESULT: PASS");
      else
         put("RESULT: FAIL " & integer'image(errors) & " mismatches");
      end if;
      wait;
   end process p_test;

end architecture sim;
