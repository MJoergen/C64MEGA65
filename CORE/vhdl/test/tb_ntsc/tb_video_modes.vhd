-------------------------------------------------------------------------------
-- tb_video_modes: M2M/vhdl/av_pipeline/video_modes_pkg.vhd (issues #181, #184)
--
-- doc/dev-ntsc/NTSC-SPEC.md section 10.2 items 2 and 7, doc/dev-hdmi-raw/SPEC.md
-- section 4.1:
--
--   * slv_to_video_mode(video_mode_to_slv(m)) = m for every member
--   * the codes of all 16 members: the old ones unchanged, the three NTSC ones
--     "0111", "1000", "1001", the six raw ones "1010" to "1111"; every 4-bit
--     code belongs to exactly one member
--   * video_mode_is_ntsc is true for exactly the three NTSC members and their
--     raw members, video_mode_is_raw for exactly the six raw members
--   * C_HDMI_720p_5994: htotal x vtotal = 1650 x 750, CLK_KHZ = 74167,
--     CLK_SEL "0110", VIC 4, 16:9, the sync polarity of C_HDMI_720p_50
--   * every record that is not a raw record: CTS_FRAC_N / CTS_FRAC_D = 0 / 1
--   * the four raw records: equal to the record they are derived from except
--     CLK_KHZ, CLK_SEL, CTS_FRAC_N, CTS_FRAC_D and the one line of 576p
--     (V_FP 4) and 480p (V_BP 31); their totals, clocks and fractions
--     (the exact frame rates are checked by doc/dev-ntsc/tools/w2_checks.py)
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
         C_VIDEO_HDMI_16_9_50       => "0000",
         C_VIDEO_HDMI_16_9_60       => "0001",
         C_VIDEO_HDMI_4_3_50        => "0010",
         C_VIDEO_HDMI_5_4_50        => "0011",
         C_VIDEO_HDMI_640_60        => "0100",
         C_VIDEO_HDMI_720_5994      => "0101",
         C_VIDEO_SVGA_800_60        => "0110",
         C_VIDEO_HDMI_16_9_5994     => "0111",
         C_VIDEO_HDMI_4_3_5994      => "1000",
         C_VIDEO_HDMI_5_4_5994      => "1001",
         C_VIDEO_HDMI_16_9_50_RAW   => "1010",
         C_VIDEO_HDMI_4_3_50_RAW    => "1011",
         C_VIDEO_HDMI_5_4_50_RAW    => "1100",
         C_VIDEO_HDMI_16_9_5994_RAW => "1101",
         C_VIDEO_HDMI_4_3_5994_RAW  => "1110",
         C_VIDEO_HDMI_5_4_5994_RAW  => "1111");

      type record_vector is array (natural range <>) of video_modes_t;
      constant C_OLD_RECORDS : record_vector := (C_PAL_720_576_50, C_HDMI_576p_50, C_HDMI_720p_50,
         C_HDMI_720x480p_5994, C_HDMI_720p_5994, C_HDMI_640x480p_60, C_HDMI_720p_60, C_SVGA_800_600_60);

      variable errors : natural := 0;
      variable ntsc   : natural := 0;
      variable raw    : natural := 0;
      variable r      : video_modes_t;
      variable code   : std_logic_vector(3 downto 0);
      variable seen   : std_logic_vector(15 downto 0) := (others => '0');

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

      function htotal(m : video_modes_t) return integer is
      begin
         return m.H_PIXELS + m.H_FP + m.H_PULSE + m.H_BP;
      end function;

      function vtotal(m : video_modes_t) return integer is
      begin
         return m.V_PIXELS + m.V_FP + m.V_PULSE + m.V_BP;
      end function;

      -- a raw record against the record it is derived from; v_fp and v_bp are the expected
      -- vertical porches of the raw record, the remaining arguments its clock fields
      procedure check_raw(name : string; rr, base : video_modes_t; v_fp, v_bp : integer;
                          clk_khz : integer; clk_sel : std_logic_vector(3 downto 0);
                          frac_n, frac_d, ht, vt : integer) is
      begin
         put(name & ": " & integer'image(htotal(rr)) & " x " & integer'image(vtotal(rr)) & " total, CLK_KHZ " &
             integer'image(rr.CLK_KHZ) & " + " & integer'image(rr.CTS_FRAC_N) & "/" & integer'image(rr.CTS_FRAC_D) &
             ", CLK_SEL " & to_string(rr.CLK_SEL) & ", VIC " & integer'image(rr.CEA_CTA_VIC) & ", V_FP " &
             integer'image(rr.V_FP) & ", V_BP " & integer'image(rr.V_BP));
         check(rr.CEA_CTA_VIC = base.CEA_CTA_VIC and rr.ASPECT = base.ASPECT and rr.PIXEL_REP = base.PIXEL_REP,
               name & " VIC / ASPECT / PIXEL_REP differ from the base record");
         check(rr.H_PIXELS = base.H_PIXELS and rr.V_PIXELS = base.V_PIXELS and rr.H_PULSE = base.H_PULSE and
               rr.H_BP = base.H_BP and rr.H_FP = base.H_FP and rr.V_PULSE = base.V_PULSE,
               name & " horizontal timing, picture or vsync width differ from the base record");
         check(rr.H_POL = base.H_POL and rr.V_POL = base.V_POL, name & " sync polarity differs from the base record");
         check(rr.V_FP = v_fp and rr.V_BP = v_bp, name & " V_FP / V_BP");
         check(rr.CLK_KHZ = clk_khz and rr.CLK_SEL = clk_sel, name & " CLK_KHZ / CLK_SEL");
         check(rr.CTS_FRAC_N = frac_n and rr.CTS_FRAC_D = frac_d, name & " CTS_FRAC_N / CTS_FRAC_D");
         check(htotal(rr) = ht and vtotal(rr) = vt, name & " totals");
      end procedure;

   begin
      check(video_mode_type'pos(video_mode_type'high) = 15, "video_mode_type does not have 16 members");
      check(video_mode_type'val(7) = C_VIDEO_HDMI_16_9_5994 and video_mode_type'val(8) = C_VIDEO_HDMI_4_3_5994 and
            video_mode_type'val(9) = C_VIDEO_HDMI_5_4_5994, "NTSC members are not appended at positions 7, 8, 9");
      check(video_mode_type'val(10) = C_VIDEO_HDMI_16_9_50_RAW   and video_mode_type'val(11) = C_VIDEO_HDMI_4_3_50_RAW   and
            video_mode_type'val(12) = C_VIDEO_HDMI_5_4_50_RAW    and video_mode_type'val(13) = C_VIDEO_HDMI_16_9_5994_RAW and
            video_mode_type'val(14) = C_VIDEO_HDMI_4_3_5994_RAW  and video_mode_type'val(15) = C_VIDEO_HDMI_5_4_5994_RAW,
            "raw members are not appended at positions 10 to 15");

      for m in video_mode_type loop
         code := video_mode_to_slv(m);
         put(video_mode_type'image(m) & " -> """ & to_string(code) & """ -> " &
             video_mode_type'image(slv_to_video_mode(code)) & ", video_mode_is_ntsc = " &
             boolean'image(video_mode_is_ntsc(m)) & ", video_mode_is_raw = " & boolean'image(video_mode_is_raw(m)));
         check(code = C_CODES(m), video_mode_type'image(m) & " has code " & to_string(code));
         check(slv_to_video_mode(code) = m, video_mode_type'image(m) & " does not round-trip");
         check(seen(to_integer(unsigned(code))) = '0', "code " & to_string(code) & " used twice");
         seen(to_integer(unsigned(code))) := '1';
         check(video_mode_is_ntsc(m) = (m = C_VIDEO_HDMI_16_9_5994     or m = C_VIDEO_HDMI_4_3_5994     or
                                        m = C_VIDEO_HDMI_5_4_5994      or m = C_VIDEO_HDMI_16_9_5994_RAW or
                                        m = C_VIDEO_HDMI_4_3_5994_RAW  or m = C_VIDEO_HDMI_5_4_5994_RAW),
               "video_mode_is_ntsc(" & video_mode_type'image(m) & ")");
         check(video_mode_is_raw(m) = (video_mode_type'pos(m) >= 10),
               "video_mode_is_raw(" & video_mode_type'image(m) & ")");
         if video_mode_is_ntsc(m) then
            ntsc := ntsc + 1;
         end if;
         if video_mode_is_raw(m) then
            raw := raw + 1;
         end if;
      end loop;
      check(ntsc = 6, "video_mode_is_ntsc is true for " & integer'image(ntsc) & " members");
      check(raw = 6, "video_mode_is_raw is true for " & integer'image(raw) & " members");
      check(seen = x"FFFF", "not every 4-bit code belongs to a member: " & to_string(seen));
      -- every code maps to the member that has it
      for i in 0 to 15 loop
         code := std_logic_vector(to_unsigned(i, 4));
         check(video_mode_to_slv(slv_to_video_mode(code)) = code, "code " & to_string(code) & " does not round-trip");
      end loop;
      check(slv_to_video_mode("UUUU") = C_VIDEO_HDMI_16_9_50, "metavalue code does not fall back");

      r := C_HDMI_720p_5994;
      put("C_HDMI_720p_5994: " & integer'image(htotal(r)) & " x " & integer'image(vtotal(r)) & " total, CLK_KHZ " &
          integer'image(r.CLK_KHZ) & ", CLK_SEL " & to_string(r.CLK_SEL) & ", VIC " & integer'image(r.CEA_CTA_VIC));
      check(r.H_PIXELS = 1280 and r.V_PIXELS = 720, "C_HDMI_720p_5994 is not 1280 x 720");
      check(htotal(r) = 1650, "C_HDMI_720p_5994 htotal is not 1650");
      check(vtotal(r) = 750, "C_HDMI_720p_5994 vtotal is not 750");
      check(r.CLK_KHZ = 74167 and r.CLK_SEL = "0110", "C_HDMI_720p_5994 CLK_KHZ / CLK_SEL");
      check(r.CEA_CTA_VIC = 4 and r.ASPECT = "10" and r.PIXEL_REP = '0', "C_HDMI_720p_5994 VIC / ASPECT / PIXEL_REP");
      check(r.H_POL = C_HDMI_720p_50.H_POL and r.V_POL = C_HDMI_720p_50.V_POL, "C_HDMI_720p_5994 sync polarity");
      -- the same timing as C_HDMI_720p_60 except clock and polarity
      check(r.H_FP = C_HDMI_720p_60.H_FP and r.H_PULSE = C_HDMI_720p_60.H_PULSE and r.H_BP = C_HDMI_720p_60.H_BP and
            r.V_FP = C_HDMI_720p_60.V_FP and r.V_PULSE = C_HDMI_720p_60.V_PULSE and r.V_BP = C_HDMI_720p_60.V_BP,
            "C_HDMI_720p_5994 porches differ from C_HDMI_720p_60");

      for i in C_OLD_RECORDS'range loop
         check(C_OLD_RECORDS(i).CTS_FRAC_N = 0 and C_OLD_RECORDS(i).CTS_FRAC_D = 1,
               "record " & integer'image(i) & " that is not a raw record: CTS_FRAC_N / CTS_FRAC_D is not 0 / 1");
         check(C_OLD_RECORDS(i).CLK_SEL(3) = '0', "record " & integer'image(i) & " uses a CLK_SEL of a raw table");
      end loop;

      check_raw("C_HDMI_720p_50_RAW",       C_HDMI_720p_50_RAW,       C_HDMI_720p_50,       5, 20, 74444, "1000",  4,  9, 1980, 750);
      check_raw("C_HDMI_576p_50_RAW",       C_HDMI_576p_50_RAW,       C_HDMI_576p_50,       4, 39, 27023, "1001", 17, 21,  864, 624);
      check_raw("C_HDMI_720p_5994_RAW",     C_HDMI_720p_5994_RAW,     C_HDMI_720p_5994,     5, 20, 74062, "1010",  1,  2, 1650, 750);
      check_raw("C_HDMI_720x480p_5994_RAW", C_HDMI_720x480p_5994_RAW, C_HDMI_720x480p_5994, 9, 31, 27000, "0001",  0,  1,  858, 526);

      if errors = 0 then
         put("RESULT: PASS");
      else
         put("RESULT: FAIL " & integer'image(errors) & " mismatches");
      end if;
      wait;
   end process p_test;

end architecture sim;
