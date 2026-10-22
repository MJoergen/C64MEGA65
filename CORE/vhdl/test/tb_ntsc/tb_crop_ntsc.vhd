-------------------------------------------------------------------------------
-- tb_crop_ntsc: HDMI zoom-in window of crop.vhd in PAL and NTSC (issue #181)
--
-- The real MiSTer VIC-II (rtl/video_vicII_656x.vhd) draws a frame with a
-- known border colour (EC = 14) and background colour (B0C = 6, all character
-- data 0, so the whole 320 x 200 display window shows the background colour;
-- DEN = 1, RSEL = 1, CSEL = 1, scroll registers as after the KERNAL reset).
-- Its hsync / vsync drive rtl/video_sync.vhd as in main.vhd, and the visible
-- stream goes through M2M/vhdl/av_pipeline/crop.vhd with zoom-in on, sampled
-- with the free-running clk / 4 clock enable of main.vhd (video_ce_proc) at
-- the phase G_CE_PHASE. The system state machine and the enables are the ones
-- of tb_video_sync_geometry.vhd (copies of fpga64_sid_iec.vhd).
--
-- Measured per frame:
--   * the position of the display window in the input, in the coordinates of
--     the crop counters (x_count = 0 on the first visible pixel of a line,
--     y_count = 1 on the first visible line): must be LEFT_BORDER_IN /
--     TOP_BORDER_IN of crop.vhd, PAL 33 / 35, NTSC 44 / 26
--   * the crop output (what ascal sees as DE): 348 x 208, with 14 / 14 border
--     pixels left / right and 4 / 4 border lines top / bottom
--   * the visible input size (PAL 382 x 270, NTSC 404 x 250)
--
-- The horizontal result depends on the phase of video_ce relative to the
-- VIC-II pixel grid (sysCycle in fpga64_sid_iec.vhd and video_ce in main.vhd
-- both run free from the configuration on, without reset). In the phases 1
-- and 2 the display window starts at x 33 (PAL) / 44 (NTSC), in the phases
-- 0 and 3 one pixel earlier, at 32 / 43, in both standards alike; the crop
-- output then has 13 / 15 instead of 14 / 14 border pixels. run_w2.sh
-- passes that one-pixel phase offset as G_PHASE_OFS, so the bench proves
-- that the NTSC constants place the window exactly as the PAL constants do,
-- whatever the phase is. The vertical position does not depend on the phase.
--
-- Prints "RESULT: PASS" or "RESULT: FAIL <reason>".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_crop_ntsc is
   generic (
      G_NTSC     : boolean := false;
      G_CE_PHASE : natural := 0;      -- 0 .. 3: phase of video_ce relative to the VIC-II cycle counter
      G_PHASE_OFS : natural := 0;     -- 1 when this phase samples one pixel earlier (see header)
      G_FRAMES   : natural := 2       -- frames to check after the warm-up
   );
end entity tb_crop_ntsc;

architecture sim of tb_crop_ntsc is

   constant C_PERIOD : time := 10 ns;   -- arbitrary, everything is counted in clk32 cycles
   constant C_BORDER : unsigned(3 downto 0) := x"E";
   constant C_BACK   : unsigned(3 downto 0) := x"6";

   signal clk        : std_logic := '0';
   signal running    : boolean := true;
   signal reset_n    : std_logic := '0';
   signal ntsc_sl    : std_logic;

   -- copy of the fpga64_sid_iec.vhd system state machine
   type sysCycleDef is (
      CYCLE_EXT0, CYCLE_EXT1, CYCLE_EXT2, CYCLE_EXT3,
      CYCLE_DMA0, CYCLE_DMA1, CYCLE_DMA2, CYCLE_DMA3,
      CYCLE_EXT4, CYCLE_EXT5, CYCLE_EXT6, CYCLE_EXT7,
      CYCLE_VIC0, CYCLE_VIC1, CYCLE_VIC2, CYCLE_VIC3,
      CYCLE_CPU0, CYCLE_CPU1, CYCLE_CPU2, CYCLE_CPU3,
      CYCLE_CPU4, CYCLE_CPU5, CYCLE_CPU6, CYCLE_CPU7,
      CYCLE_CPU8, CYCLE_CPU9, CYCLE_CPUA, CYCLE_CPUB,
      CYCLE_CPUC, CYCLE_CPUD, CYCLE_CPUE, CYCLE_CPUF
   );
   signal preCycle    : sysCycleDef := sysCycleDef'low;
   signal sysCycle    : sysCycleDef;
   signal sysEnable   : std_logic := '0';
   signal rfsh_cycle  : unsigned(1 downto 0) := "00";
   signal vic_reset   : std_logic := '1';
   signal phi0_cpu    : std_logic := '0';
   signal enableVic   : std_logic := '0';
   signal enablePixel : std_logic := '0';

   -- VIC-II
   signal vic_hsync   : std_logic;
   signal vic_vsync   : std_logic;
   signal vic_color   : unsigned(3 downto 0);
   signal vic_cs      : std_logic := '0';
   signal vic_we      : std_logic := '0';
   signal vic_addr    : unsigned(5 downto 0) := (others => '0');
   signal vic_data    : unsigned(7 downto 0) := (others => '0');
   signal regs_done   : boolean := false;

   -- video_sync
   signal hblank      : std_logic;
   signal vblank      : std_logic;
   signal hsync_out   : std_logic;
   signal vsync_out   : std_logic;

   -- main.vhd video_ce_proc
   signal video_ce_cnt : unsigned(1 downto 0) := to_unsigned(G_CE_PHASE, 2);
   signal video_ce     : std_logic;

   -- crop
   signal video_red    : std_logic_vector(7 downto 0);
   signal crop_ce      : std_logic;
   signal crop_red     : std_logic_vector(7 downto 0);
   signal crop_hblank  : std_logic;
   signal crop_vblank  : std_logic;

begin

   ntsc_sl <= '1' when G_NTSC else '0';

   clk <= not clk after C_PERIOD / 2 when running else '0';

   p_reset : process
   begin
      reset_n <= '0';
      for i in 1 to 200 loop
         wait until rising_edge(clk);
      end loop;
      reset_n <= '1';
      wait;
   end process p_reset;

   sysCycle <= preCycle when sysEnable = '1' else CYCLE_EXT4;

   p_sys : process (clk)
   begin
      if rising_edge(clk) then
         -- The original writes preCycle <= 'succ(preCycle) unconditionally and
         -- overrides it for the last value; ghdl evaluates 'succ of the last
         -- value as a bound error, hence the if/else here (same behavior).
         if preCycle /= sysCycleDef'high then
            preCycle <= sysCycleDef'succ(preCycle);
         end if;
         if preCycle = sysCycleDef'high then
            preCycle <= sysCycleDef'low;
            if sysEnable = '1' then
               rfsh_cycle <= rfsh_cycle + 1;
            end if;
         end if;
         if preCycle = sysCycleDef'pred(CYCLE_EXT4) and rfsh_cycle = "00" then
            sysEnable <= '1';
         end if;
         if preCycle = sysCycleDef'high then
            vic_reset <= not reset_n;
         end if;
      end if;
   end process p_sys;

   p_phi0 : process (clk)
   begin
      if rising_edge(clk) then
         if sysCycle = sysCycleDef'pred(CYCLE_CPU0) then
            phi0_cpu <= '1';
         end if;
         if sysCycle = sysCycleDef'high then
            phi0_cpu <= '0';
         end if;
      end if;
   end process p_phi0;

   p_ena : process (clk)
   begin
      if rising_edge(clk) then
         enableVic <= '0';
         case sysCycle is
            when CYCLE_VIC2 => enableVic <= '1';
            when CYCLE_CPUE => enableVic <= '1';
            when others     => null;
         end case;
      end if;
   end process p_ena;

   p_pixel : process (clk)
   begin
      if rising_edge(clk) then
         enablePixel <= '0';
         if sysCycle = CYCLE_VIC2 or sysCycle = CYCLE_EXT2 or sysCycle = CYCLE_DMA2
            or sysCycle = CYCLE_EXT6 or sysCycle = CYCLE_CPU2 or sysCycle = CYCLE_CPU6
            or sysCycle = CYCLE_CPUA or sysCycle = CYCLE_CPUE then
            enablePixel <= '1';
         end if;
      end if;
   end process p_pixel;

   ---------------------------------------------------------------------------
   -- VIC-II with register writes as the CPU does them (cs / we held for a
   -- whole phi high phase)
   ---------------------------------------------------------------------------

   i_vic : entity work.video_vicii_656x
      generic map (
         registeredAddress => false,
         emulateRefresh    => true,
         emulateLightpen   => true,
         emulateGraphics   => true
      )
      port map (
         clk         => clk,
         phi         => phi0_cpu,
         enaData     => enableVic,
         enaPixel    => enablePixel,
         baSync      => '0',
         ba          => open,
         ba_dma      => open,
         mode6569    => not ntsc_sl,
         mode6567old => '0',
         mode6567R8  => ntsc_sl,
         mode6572    => '0',
         turbo_en    => '0',
         turbo_state => open,
         variant     => "10",           -- as fpga64_sid_iec.vhd
         reset       => vic_reset,
         cs          => vic_cs,
         we          => vic_we,
         lp_n        => '1',
         aRegisters  => vic_addr,
         diRegisters => vic_data,
         di          => (others => '0'),
         diColor     => (others => '0'),
         do          => open,
         vicAddr     => open,
         irq_n       => open,
         hSync       => vic_hsync,
         vSync       => vic_vsync,
         colorIndex  => vic_color,
         debugX      => open,
         debugY      => open,
         vicRefresh  => open,
         addrValid   => open
      );

   p_regs : process
      type reg_t is record
         a : natural;
         d : natural;
      end record reg_t;
      type reg_vector is array (natural range <>) of reg_t;
      constant C_REGS : reg_vector := (
         (16#11#, 16#1B#),             -- DEN = 1, RSEL = 1 (25 rows), YSCROLL = 3
         (16#16#, 16#C8#),             -- CSEL = 1 (40 columns), XSCROLL = 0
         (16#20#, to_integer(C_BORDER)),
         (16#21#, to_integer(C_BACK)));
   begin
      wait until reset_n = '1' and vic_reset = '0';
      for i in C_REGS'range loop
         wait until rising_edge(clk) and phi0_cpu = '0';
         vic_addr <= to_unsigned(C_REGS(i).a, 6);
         vic_data <= to_unsigned(C_REGS(i).d, 8);
         vic_cs   <= '1';
         vic_we   <= '1';
         wait until rising_edge(clk) and phi0_cpu = '1';
         wait until rising_edge(clk) and phi0_cpu = '0';
         vic_cs   <= '0';
         vic_we   <= '0';
      end loop;
      regs_done <= true;
      wait;
   end process p_regs;

   ---------------------------------------------------------------------------
   -- video_sync and the pixel clock enable, as in main.vhd
   ---------------------------------------------------------------------------

   i_video_sync : entity work.video_sync
      port map (
         clk32     => clk,
         pause     => '0',
         hsync     => vic_hsync,
         vsync     => vic_vsync,
         ntsc      => ntsc_sl,
         wide      => '0',
         hsync_out => hsync_out,
         vsync_out => vsync_out,
         hblank    => hblank,
         vblank    => vblank
      );

   p_video_ce : process (clk)
   begin
      if rising_edge(clk) then
         video_ce_cnt <= video_ce_cnt + 1;
      end if;
   end process p_video_ce;
   video_ce <= '1' when video_ce_cnt = 0 else '0';

   video_red <= "0000" & std_logic_vector(vic_color);

   ---------------------------------------------------------------------------
   -- DUT
   ---------------------------------------------------------------------------

   i_crop : entity work.crop
      port map (
         video_crop_mode_i => '1',
         video_ntsc_i      => ntsc_sl,
         video_clk_i       => clk,
         video_rst_i       => '0',
         video_ce_i        => video_ce,
         video_red_i       => video_red,
         video_green_i     => (others => '0'),
         video_blue_i      => (others => '0'),
         video_hs_i        => hsync_out,
         video_vs_i        => vsync_out,
         video_hblank_i    => hblank,
         video_vblank_i    => vblank,
         video_ce_o        => crop_ce,
         video_red_o       => crop_red,
         video_green_o     => open,
         video_blue_o      => open,
         video_hs_o        => open,
         video_vs_o        => open,
         video_hblank_o    => crop_hblank,
         video_vblank_o    => crop_vblank
      );

   ---------------------------------------------------------------------------
   -- Measurement
   ---------------------------------------------------------------------------

   p_measure : process
      -- input side, sampled with video_ce like crop does, in crop counter coordinates
      variable hb_q, vb_q       : std_logic := '1';
      variable x, y             : integer := 0;
      variable in_w, in_h       : integer := 0;
      variable in_line_w        : integer := 0;
      variable bg_x0, bg_x1     : integer;
      variable bg_y0, bg_y1     : integer;
      -- output side (crop_ce, DE = not (hblank or vblank))
      variable de_q             : boolean := false;
      variable ox, oy           : integer := 0;
      variable out_w, out_h     : integer := 0;
      variable out_w_ok         : boolean := true;
      variable line_has_de      : boolean := false;
      variable obg_x0, obg_x1   : integer;
      variable obg_y0, obg_y1   : integer;
      variable other_colour     : boolean := false;
      variable frames           : integer := -3;   -- warm-up frames (register writes, first frame)
      variable checked          : natural := 0;
      variable fail_msg         : line;
      variable l                : line;
      variable exp_left, exp_top : natural;
      variable exp_w, exp_h     : natural;
      variable col              : unsigned(3 downto 0);
      variable pixel_de         : boolean;

      procedure put(s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure;

      procedure fail(s : string) is
      begin
         put("  MISMATCH: " & s);
         if fail_msg = null then
            write(fail_msg, s);
         end if;
      end procedure;

      procedure reset_frame is
      begin
         in_w := 0; in_h := 0;
         bg_x0 := integer'high; bg_x1 := -1; bg_y0 := integer'high; bg_y1 := -1;
         out_w := -1; out_h := 0; out_w_ok := true; oy := 0;
         obg_x0 := integer'high; obg_x1 := -1; obg_y0 := integer'high; obg_y1 := -1;
         other_colour := false;
      end procedure;

   begin
      if G_NTSC then
         exp_left := 44; exp_top := 26; exp_w := 404; exp_h := 250;
      else
         exp_left := 33; exp_top := 35; exp_w := 382; exp_h := 270;
      end if;
      reset_frame;
      wait until regs_done;
      loop
         wait until rising_edge(clk);

         -- input side: mirror of the crop counters for the sample taken at this edge
         if video_ce = '1' then
            if hb_q = '1' and hblank = '0' then
               x := 0;
               y := y + 1;
            else
               x := x + 1;
            end if;
            if vb_q = '1' and vblank = '0' then
               -- start of a visible frame: evaluate the previous one
               if frames >= 0 then
                  checked := checked + 1;
                  put("frame " & integer'image(frames) & ": input visible " & integer'image(in_w) & " x " &
                      integer'image(in_h) & ", display window at x " & integer'image(bg_x0) & ".." &
                      integer'image(bg_x1) & ", y " & integer'image(bg_y0) & ".." & integer'image(bg_y1) &
                      " (crop counters); crop output " & integer'image(out_w) & " x " & integer'image(out_h) &
                      ", window at x " & integer'image(obg_x0) & ".." & integer'image(obg_x1) & ", line " &
                      integer'image(obg_y0) & ".." & integer'image(obg_y1));
                  if in_w /= exp_w or in_h /= exp_h then fail("input visible area"); end if;
                  if bg_x0 /= exp_left - G_PHASE_OFS or bg_x1 /= exp_left - G_PHASE_OFS + 319 then
                     fail("window x in the input");
                  end if;
                  if bg_y0 /= exp_top or bg_y1 /= exp_top + 199 then fail("window y in the input"); end if;
                  if not out_w_ok or out_w /= 348 or out_h /= 208 then fail("crop output is not 348 x 208"); end if;
                  if obg_x0 /= 14 - G_PHASE_OFS or obg_x1 /= 333 - G_PHASE_OFS then
                     fail("output window x is not " & integer'image(14 - G_PHASE_OFS) & " .. " & integer'image(333 - G_PHASE_OFS));
                  end if;
                  if obg_y0 /= 4 or obg_y1 /= 203 then fail("output window line is not 4 .. 203"); end if;
                  if other_colour then fail("unexpected colour in the visible area"); end if;
                  exit when checked >= G_FRAMES;
               end if;
               frames := frames + 1;
               reset_frame;
               y := 0;
            end if;
            if hblank = '0' and vblank = '0' then
               col := unsigned(video_red(3 downto 0));
               if x = 0 then
                  in_h := in_h + 1;
               end if;
               if x + 1 > in_w then
                  in_w := x + 1;
               end if;
               if col = C_BACK then
                  if x < bg_x0 then bg_x0 := x; end if;
                  if x > bg_x1 then bg_x1 := x; end if;
                  if y < bg_y0 then bg_y0 := y; end if;
                  if y > bg_y1 then bg_y1 := y; end if;
               elsif col /= C_BORDER then
                  other_colour := true;
               end if;
            end if;
            hb_q := hblank;
            vb_q := vblank;
         end if;

         -- output side: what ascal samples (crop_ce, DE)
         if crop_ce = '1' then
            pixel_de := crop_hblank = '0' and crop_vblank = '0';
            if pixel_de then
               if not de_q then
                  ox := 0;
               else
                  ox := ox + 1;
               end if;
               if unsigned(crop_red(3 downto 0)) = C_BACK then
                  if ox < obg_x0 then obg_x0 := ox; end if;
                  if ox > obg_x1 then obg_x1 := ox; end if;
                  if oy < obg_y0 then obg_y0 := oy; end if;
                  if oy > obg_y1 then obg_y1 := oy; end if;
               end if;
            elsif de_q then
               -- end of an output line
               if out_w = -1 then
                  out_w := ox + 1;
               elsif out_w /= ox + 1 then
                  out_w_ok := false;
               end if;
               out_h := out_h + 1;
               oy := oy + 1;
            end if;
            de_q := pixel_de;
         end if;
      end loop;

      put("NTSC=" & boolean'image(G_NTSC) & ", video_ce phase " & integer'image(G_CE_PHASE) &
          ": display window starts at x " & integer'image(bg_x0) & ", y " & integer'image(bg_y0) &
          " (crop.vhd constants " & integer'image(exp_left) & " / " & integer'image(exp_top) &
          ", phase offset " & integer'image(G_PHASE_OFS) & ")");
      if fail_msg = null then
         put("RESULT: PASS");
      else
         write(l, string'("RESULT: FAIL "));
         write(l, fail_msg.all);
         writeline(output, l);
      end if;
      running <= false;
      wait;
   end process p_measure;

end architecture sim;
