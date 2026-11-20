----------------------------------------------------------------------------------
-- Genlock bench (GitHub issue #184): the raw modes
--
-- The four raw modes of doc/dev-hdmi-raw/SPEC.md, section 4, with the exact
-- length of a core frame in pixel clocks (core_n / core_d, from the clock
-- settings: core clock 100 MHz x 227 / 720 (PAL) or 100 MHz x 36 / 110 (NTSC),
-- 312 x 63 x 32 or 263 x 65 x 32 core clocks per frame; pixel clock
-- 100 MHz x 67 / 90, 100 MHz x 227 / 840, 100 MHz x 237 / 320, 27 MHz). The
-- simulated pixel clock period is a multiple of core_d femtoseconds, so a core
-- frame is an exact whole number of femtoseconds: the ratio between the two
-- clocks is exact and does not drift. The simulated period differs from the
-- true one by at most 8.3 ppm, which changes only the time scale of the reports.
--
-- The model of the scaler's output timing is tb_ascal_timing_pkg.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

use work.tb_ascal_timing_pkg.all;

package tb_hdmi_genlock_pkg is

   type mode_t is record
      name      : string(1 to 9);
      htotal    : natural;           -- H_PIXELS + H_FP + H_PULSE + H_BP
      hsstart   : natural;           -- H_PIXELS + H_FP
      hsend     : natural;           -- hsstart + H_PULSE
      hdisp     : natural;           -- H_PIXELS
      vtotal    : natural;
      vsstart   : natural;
      vsend     : natural;
      vdisp     : natural;
      clk_khz   : natural;           -- CLK_KHZ of the record: target_i = 2 * clk_khz
      core_n    : natural;           -- a core frame is core_n / core_d pixel clocks
      core_d    : positive;
      period    : time;              -- simulated pixel clock period, a multiple of core_d fs
      rate      : real;              -- core frame rate in Hz (for the reports)
      bound_s   : natural;           -- SPEC 5.3: pull-in "at most about" bound_s seconds
   end record mode_t;

   type modes_t is array (0 to 3) of mode_t;

   constant C_MODES : modes_t := (
      -- C_HDMI_720p_50_RAW: 1980 x 750, 74.444444 MHz
      0 => (name => "PAL 720p ", htotal => 1980, hsstart => 1720, hsend => 1760, hdisp => 1280,
            vtotal => 750, vsstart => 725, vsend => 730, vdisp => 720, clk_khz => 74444,
            core_n => 337139712, core_d => 227, period => 13432725 fs, rate => 50.124291, bound_s => 8),
      -- C_HDMI_576p_50_RAW: 864 x 624 (V_FP 4), 27.023810 MHz
      1 => (name => "PAL 576p ", htotal => 864, hsstart => 732, hsend => 796, hdisp => 720,
            vtotal => 624, vsstart => 580, vsend => 585, vdisp => 576, clk_khz => 27023,
            core_n => 539136, core_d => 1, period => 37004405 fs, rate => 50.124291, bound_s => 3),
      -- C_HDMI_720p_5994_RAW: 1650 x 750, 74.0625 MHz
      2 => (name => "NTSC 720p", htotal => 1650, hsstart => 1390, hsend => 1430, hdisp => 1280,
            vtotal => 750, vsstart => 725, vsend => 730, vdisp => 720, clk_khz => 74062,
            core_n => 14855555, core_d => 12, period => 13502112 fs, rate => 59.826105, bound_s => 6),
      -- C_HDMI_720x480p_5994_RAW: 858 x 526 (V_BP 31), 27.000 MHz
      3 => (name => "NTSC 480p", htotal => 858, hsstart => 736, hsend => 798, hdisp => 720,
            vtotal => 526, vsstart => 489, vsend => 495, vdisp => 480, clk_khz => 27000,
            core_n => 451308, core_d => 1, period => 37037037 fs, rate => 59.826105, bound_s => 2)
   );

   -- the timing inputs of the scaler for a mode (except htotal)
   function timing_of (m : mode_t) return scaler_timing_t;

   -- true if the next edge of the scaler model takes into stage 0 of its delay lines what is
   -- there now (the conditions of o_dev(0), o_hsv(0) and o_vsv(0) for the counters and the
   -- registered inputs as they are)
   function scaler_conds_same (sc : scaler_t) return boolean;

end package tb_hdmi_genlock_pkg;

package body tb_hdmi_genlock_pkg is

   function timing_of (m : mode_t) return scaler_timing_t is
   begin
      return (hsstart => m.hsstart, hsend => m.hsend, hdisp => m.hdisp,
              vtotal => m.vtotal, vsstart => m.vsstart, vsend => m.vsend, vdisp => m.vdisp);
   end function timing_of;

   function scaler_conds_same (sc : scaler_t) return boolean is
      variable hsv0, vsv0, dev0 : natural range 0 to 1;
   begin
      if sc.o_hcpt < sc.o_hdisp and sc.o_vcpt < sc.o_vdisp then dev0 := 1; else dev0 := 0; end if;
      if sc.o_hcpt >= sc.o_hsstart and sc.o_hcpt < sc.o_hsend then hsv0 := 1; else hsv0 := 0; end if;
      if (sc.o_vcpt = sc.o_vsstart and sc.o_hcpt >= sc.o_hsstart) or
         (sc.o_vcpt > sc.o_vsstart and sc.o_vcpt < sc.o_vsend) or
         (sc.o_vcpt = sc.o_vsend and sc.o_hcpt < sc.o_hsstart) then
         vsv0 := 1;
      else
         vsv0 := 0;
      end if;
      return dev0 = sc.dev mod 2 and hsv0 = sc.hsv mod 2 and vsv0 = sc.vsv mod 2;
   end function scaler_conds_same;

end package body tb_hdmi_genlock_pkg;
