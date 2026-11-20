-------------------------------------------------------------------------------
-- Architecture "timing" of the scaler M2M/vhdl/av_pipeline/ascal.vhd for
-- tb_hdmi_raw_wiring (issue #184)
--
-- run.sh puts this architecture behind the entity declaration of the real
-- ascal.vhd (taken by doc/dev-ntsc/tools/w2_standin.py with --retype-in-ranged,
-- so the timing inputs are of type integer). Inside is only the output timing
-- generator of ascal, cycle exact:
--   * the timing inputs are registered in every clock cycle while the internal
--     reset o_reset_na is '1' (process Scalaire, ascal.vhd lines 1878 to 1890;
--     o_reset_na as on line 1110), 0 before the first edge;
--   * process OSWEEP (lines 2674 to 2720) with its counters and the delay lines
--     o_hsv, o_vsv, o_dev (0 to 9), gated by o_ce and run as there;
--   * the ports o_hs, o_vs, o_de, o_vbl are registers fed by stage 9 (process
--     VSCAL, lines 2852 to 2855), 11 clock cycles behind the counters.
-- The picture path, the input side and the memory interface are not modeled:
-- every other output is a constant. o_vs and o_de are also copied to the signals
-- of tb_hdmi_raw_wiring_pkg for the bench.
-------------------------------------------------------------------------------

library work;
use work.tb_hdmi_raw_wiring_pkg.all;

architecture timing of ascal is

   subtype uint12 is natural range 0 to 4095;

   signal o_reset_na  : std_logic;
   signal o_run       : std_logic;
   signal o_htotal    : uint12;
   signal o_hsstart   : uint12;
   signal o_hsend     : uint12;
   signal o_hdisp     : uint12;
   signal o_vtotal    : uint12;
   signal o_vsstart   : uint12;
   signal o_vsend     : uint12;
   signal o_vdisp     : uint12;
   signal o_hcpt      : uint12;
   signal o_vcpt      : uint12;
   signal o_vcpt_pre  : uint12;
   signal o_vcpt_pre2 : uint12;
   signal o_vcpt_pre3 : uint12;
   signal o_hsv       : unsigned(0 to 9);
   signal o_vsv       : unsigned(0 to 9);
   signal o_dev       : unsigned(0 to 9);
   signal o_end       : unsigned(0 to 9);

   function to_std_logic (b : boolean) return std_logic is
   begin
      if b then
         return '1';
      end if;
      return '0';
   end function to_std_logic;

begin

   o_reset_na <= '0' when reset_na = '0' else '1' when rising_edge(o_clk);

   -- the timing inputs (Scalaire)
   p_regs : process (o_clk, o_reset_na)
   begin
      if o_reset_na = '0' then
         null;
      elsif rising_edge(o_clk) then
         o_run     <= run;
         o_htotal  <= htotal;
         o_hsstart <= hsstart;
         o_hsend   <= hsend;
         o_hdisp   <= hdisp;
         o_vtotal  <= vtotal;
         o_vsstart <= vsstart;
         o_vsend   <= vsend;
         o_vdisp   <= vdisp;
      end if;
   end process p_regs;

   -- OSWEEP
   p_osweep : process (o_clk)
   begin
      if rising_edge(o_clk) then
         if o_ce = '1' then
            if o_hcpt + 1 < o_htotal then
               o_hcpt <= (o_hcpt + 1) mod 4096;
            else
               o_hcpt <= 0;
               if o_vcpt_pre3 + 1 >= o_vtotal then
                  o_vcpt_pre3 <= 0;
               else
                  o_vcpt_pre3 <= (o_vcpt_pre3 + 1) mod 4096;
               end if;
               o_vcpt_pre2 <= o_vcpt_pre3;
               o_vcpt_pre  <= o_vcpt_pre2;
               o_vcpt      <= o_vcpt_pre;
            end if;

            o_end(0) <= to_std_logic(o_vcpt >= o_vdisp);
            o_dev(0) <= to_std_logic(o_hcpt < o_hdisp and o_vcpt < o_vdisp);
            o_hsv(0) <= to_std_logic(o_hcpt >= o_hsstart and o_hcpt < o_hsend);
            o_vsv(0) <= to_std_logic((o_vcpt = o_vsstart and o_hcpt >= o_hsstart) or
                                     (o_vcpt > o_vsstart and o_vcpt < o_vsend) or
                                     (o_vcpt = o_vsend   and o_hcpt < o_hsstart));
            o_hsv(1 to 9) <= o_hsv(0 to 8);
            o_vsv(1 to 9) <= o_vsv(0 to 8);
            o_dev(1 to 9) <= o_dev(0 to 8);
            o_end(1 to 9) <= o_end(0 to 8);

            if o_run = '0' then
               o_hsv(2) <= '0';
               o_vsv(2) <= '0';
               o_dev(2) <= '0';
               o_end(2) <= '0';
            end if;
         end if;
      end if;
   end process p_osweep;

   -- the output registers of VSCAL (cycle 10)
   p_vscal : process (o_clk)
   begin
      if rising_edge(o_clk) then
         if o_ce = '1' then
            o_hs      <= o_hsv(9);
            o_vs      <= o_vsv(9);
            o_de      <= o_dev(9);
            o_vbl     <= o_end(9);
            scaler_vs <= o_vsv(9);
            scaler_de <= o_dev(9);
         end if;
      end if;
   end process p_vscal;

   o_r            <= (others => '0');
   o_g            <= (others => '0');
   o_b            <= (others => '0');
   o_brd          <= '0';
   pal1_dr        <= (others => '0');
   pal2_dr        <= (others => '0');
   o_lltune       <= (others => '0');
   i_hdmax        <= 0;
   i_vdmax        <= 0;
   avl_burstcount <= (others => '0');
   avl_writedata  <= (others => '0');
   avl_address    <= (others => '0');
   avl_write      <= '0';
   avl_read       <= '0';
   avl_byteenable <= (others => '0');

end architecture timing;
