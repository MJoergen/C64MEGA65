----------------------------------------------------------------------------------
-- Model of the output timing generator of the scaler (ascal), for benches
--
-- scaler_step is a cycle-exact copy of what M2M/vhdl/av_pipeline/ascal.vhd does
-- with the output timing, with o_ce = '1' and run = '1' as in our design:
--    * the timing inputs htotal, hsstart, hsend, hdisp, vtotal, vsstart, vsend
--      and vdisp are registered in every clock cycle (o_htotal <= htotal and so
--      on, ascal.vhd lines 1878-1890) and are 0 before the first edge (the
--      initial value of the uint12 signals);
--    * process OSWEEP (lines 2674-2720): o_hcpt wraps when o_hcpt + 1 is not
--      below o_htotal, the vertical lead counter o_vcpt_pre3 wraps when
--      o_vcpt_pre3 + 1 is not below o_vtotal, o_vcpt_pre2, o_vcpt_pre and
--      o_vcpt follow it line by line; o_hsv(0), o_vsv(0) and o_dev(0) are formed
--      from o_hcpt and o_vcpt and shifted through o_hsv(1 to 9) and so on;
--    * the ports o_hs, o_vs and o_de are registers fed by o_hsv(9), o_vsv(9) and
--      o_dev(9) (process VSCAL, lines 2852-2854): 11 clock cycles behind the
--      counters, 10 behind o_hsv(0).
-- One call is one rising edge of the output clock; every right-hand side is the
-- value before the edge, as in the signal assignments of ascal, and the inputs
-- are the values at the ports of ascal before the edge. The step also reports a
-- line that ends at this edge: its number (o_vcpt of that line) and its length
-- (o_hcpt + 1 in the clock cycle of the wrap). The delay lines are packed into
-- integers (stage i is bit i), which makes the model fast in GHDL.
--
-- In our design the inputs come from the selected video_modes_pkg record
-- (digital_pipeline.vhd): htotal = H_PIXELS + H_FP + H_PULSE + H_BP,
-- hsstart = H_PIXELS + H_FP, hsend = hsstart + H_PULSE, hdisp = H_PIXELS, and
-- the same for the vertical values.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

package tb_ascal_timing_pkg is

   subtype uint12 is natural range 0 to 4095;

   -- the timing inputs of ascal except htotal
   type scaler_timing_t is record
      hsstart : uint12;
      hsend   : uint12;
      hdisp   : uint12;
      vtotal  : uint12;
      vsstart : uint12;
      vsend   : uint12;
      vdisp   : uint12;
   end record scaler_timing_t;

   -- state of the output timing generator
   type scaler_t is record
      -- the registered timing inputs
      o_htotal  : uint12;
      o_hsstart : uint12;
      o_hsend   : uint12;
      o_hdisp   : uint12;
      o_vtotal  : uint12;
      o_vsstart : uint12;
      o_vsend   : uint12;
      o_vdisp   : uint12;
      -- the counters
      o_hcpt    : uint12;
      o_vcpt    : uint12;
      o_pre     : uint12;                    -- o_vcpt_pre
      o_pre2    : uint12;                    -- o_vcpt_pre2
      o_pre3    : uint12;                    -- o_vcpt_pre3, the vertical lead counter
      -- the delay lines o_hsv(0 to 9), o_vsv(0 to 9), o_dev(0 to 9): stage i is bit i
      hsv       : natural range 0 to 1023;
      vsv       : natural range 0 to 1023;
      dev       : natural range 0 to 1023;
      -- the ports o_hs, o_vs, o_de
      hs        : natural range 0 to 1;
      vs        : natural range 0 to 1;
      de        : natural range 0 to 1;
      -- a line ended at this edge: its number and its length
      line_end  : boolean;
      line_num  : uint12;
      line_len  : natural range 0 to 4096;
   end record scaler_t;

   constant C_SCALER_INIT : scaler_t := (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, 0, 0);

   -- one rising edge of the output clock; t and htotal are the inputs of ascal before the edge
   procedure scaler_step (variable sc : inout scaler_t; constant t : in scaler_timing_t; constant htotal : in uint12);

end package tb_ascal_timing_pkg;

package body tb_ascal_timing_pkg is

   procedure scaler_step (variable sc : inout scaler_t; constant t : in scaler_timing_t; constant htotal : in uint12) is
      variable hsv0, vsv0, dev0 : natural range 0 to 1;
   begin
      -- VSCAL: the ports take the last stage of the delay lines
      sc.hs := sc.hsv / 512;
      sc.vs := sc.vsv / 512;
      sc.de := sc.dev / 512;

      -- OSWEEP: the delay lines and the sync signals from the counters before the edge
      if sc.o_hcpt < sc.o_hdisp and sc.o_vcpt < sc.o_vdisp then dev0 := 1; else dev0 := 0; end if;
      if sc.o_hcpt >= sc.o_hsstart and sc.o_hcpt < sc.o_hsend then hsv0 := 1; else hsv0 := 0; end if;
      if (sc.o_vcpt = sc.o_vsstart and sc.o_hcpt >= sc.o_hsstart) or
         (sc.o_vcpt > sc.o_vsstart and sc.o_vcpt < sc.o_vsend) or
         (sc.o_vcpt = sc.o_vsend and sc.o_hcpt < sc.o_hsstart) then
         vsv0 := 1;
      else
         vsv0 := 0;
      end if;
      sc.hsv := (sc.hsv * 2) mod 1024 + hsv0;
      sc.vsv := (sc.vsv * 2) mod 1024 + vsv0;
      sc.dev := (sc.dev * 2) mod 1024 + dev0;

      -- OSWEEP: the counters
      sc.line_end := false;
      if sc.o_hcpt + 1 < sc.o_htotal then
         sc.o_hcpt := (sc.o_hcpt + 1) mod 4096;
      else
         sc.line_end := true;
         sc.line_num := sc.o_vcpt;
         sc.line_len := sc.o_hcpt + 1;
         sc.o_hcpt   := 0;
         sc.o_vcpt   := sc.o_pre;
         sc.o_pre    := sc.o_pre2;
         sc.o_pre2   := sc.o_pre3;
         if sc.o_pre3 + 1 >= sc.o_vtotal then
            sc.o_pre3 := 0;
         else
            sc.o_pre3 := (sc.o_pre3 + 1) mod 4096;
         end if;
      end if;

      -- the timing inputs are registered in every clock cycle
      sc.o_htotal  := htotal;
      sc.o_hsstart := t.hsstart;
      sc.o_hsend   := t.hsend;
      sc.o_hdisp   := t.hdisp;
      sc.o_vtotal  := t.vtotal;
      sc.o_vsstart := t.vsstart;
      sc.o_vsend   := t.vsend;
      sc.o_vdisp   := t.vdisp;
   end procedure scaler_step;

end package body tb_ascal_timing_pkg;
