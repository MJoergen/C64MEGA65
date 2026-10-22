-------------------------------------------------------------------------------
-- tb_video_sync_geometry: PAL / NTSC raster geometry of the C64 core video
--
-- Drives the real MiSTer VIC-II (rtl/video_vicII_656x.vhd) with the enaPixel,
-- enaData and phi strobes generated exactly as fpga64_sid_iec.vhd does (its
-- sysCycle state machine, 32 clk32 cycles per C64 cycle), feeds the VIC hSync
-- and vSync into rtl/video_sync.vhd as main.vhd does, and measures:
--
--   * C64 cycles and dots per line, lines per frame, frame period in clk32
--     cycles and the frame rate at G_CLK_HZ
--   * the visible window that the scaler sees (hblank low and vblank low)
--   * hsync_out and vsync_out pulse widths and positions
--
-- With G_USE_VIC = false a simple stimulus model replaces the VIC-II (hsync
-- high for rasterX 396 .. 495, vsync high for one line); this is only a cheap
-- fallback and is not used by run.sh.
--
-- Everything is counted in clk32 cycles, so the simulated clock period does
-- not matter; G_CLK_HZ only converts cycle counts into Hz and microseconds.
-- G_CHECK_PAL = true asserts today's PAL figures (382 x 270 visible).
--
-- Prints a final "RESULT: PASS" or "RESULT: FAIL <reason>" line.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library std;
use std.textio.all;

entity tb_video_sync_geometry is
   generic (
      G_NTSC      : boolean := false;
      G_WIDE      : boolean := false;
      G_CLK_HZ    : natural := 31527778;
      G_USE_VIC   : boolean := true;
      G_CHECK_PAL : boolean := true;
      G_FRAMES    : natural := 3      -- frames to measure after the first full one
   );
end entity tb_video_sync_geometry;

architecture sim of tb_video_sync_geometry is

   constant C_PERIOD : time := 10 ns;   -- arbitrary, see header

   signal clk        : std_logic := '0';
   signal running    : boolean := true;
   signal reset_n    : std_logic := '0';
   signal ntsc_sl    : std_logic;
   signal wide_sl    : std_logic;

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

   -- VIC-II outputs
   signal vic_hsync   : std_logic;
   signal vic_vsync   : std_logic;
   signal dbg_x       : unsigned(9 downto 0) := (others => '0');  -- VIC rasterXDelay
   signal dbg_y       : unsigned(8 downto 0) := (others => '0');  -- VIC rasterY

   -- video_sync outputs
   signal hsync_out   : std_logic;
   signal vsync_out   : std_logic;
   signal hblank      : std_logic;
   signal vblank      : std_logic;

   -- stimulus-model state
   signal stim_x      : natural := 0;
   signal stim_y      : natural := 0;
   signal stim_hs     : std_logic := '0';
   signal stim_vs     : std_logic := '0';

   function cycles_per_line return natural is
   begin
      if G_NTSC then return 65; else return 63; end if;
   end function;

   function lines_per_frame return natural is
   begin
      if G_NTSC then return 263; else return 312; end if;
   end function;

begin

   ntsc_sl <= '1' when G_NTSC else '0';
   wide_sl <= '1' when G_WIDE else '0';

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

   ---------------------------------------------------------------------------
   -- fpga64_sid_iec.vhd: system state machine and enables (pause = '0')
   ---------------------------------------------------------------------------

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
   -- Video source: real VIC-II or stimulus model
   ---------------------------------------------------------------------------

   g_vic : if G_USE_VIC generate
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
            variant     => "10",
            reset       => vic_reset,
            cs          => '0',
            we          => '0',
            lp_n        => '1',
            aRegisters  => (others => '0'),
            diRegisters => (others => '0'),
            di          => (others => '0'),
            diColor     => (others => '0'),
            do          => open,
            vicAddr     => open,
            irq_n       => open,
            hSync       => vic_hsync,
            vSync       => vic_vsync,
            colorIndex  => open,
            debugX      => dbg_x,
            debugY      => dbg_y,
            vicRefresh  => open,
            addrValid   => open
         );
   end generate g_vic;

   g_stim : if not G_USE_VIC generate
      p_stim : process (clk)
      begin
         if rising_edge(clk) then
            if enablePixel = '1' then
               if stim_x = cycles_per_line * 8 - 1 then
                  stim_x <= 0;
                  if stim_y = lines_per_frame - 1 then
                     stim_y <= 0;
                  else
                     stim_y <= stim_y + 1;
                  end if;
               else
                  stim_x <= stim_x + 1;
               end if;
               if stim_x = 396 then stim_hs <= '1'; elsif stim_x = 496 then stim_hs <= '0'; end if;
               if stim_x = 0 then
                  if stim_y = 300 mod lines_per_frame then stim_vs <= '1'; else stim_vs <= '0'; end if;
               end if;
            end if;
         end if;
      end process p_stim;
      vic_hsync <= stim_hs;
      vic_vsync <= stim_vs;
      dbg_x     <= to_unsigned(stim_x, 10);
      dbg_y     <= to_unsigned(stim_y, 9);
   end generate g_stim;

   ---------------------------------------------------------------------------
   -- DUT: video_sync as instantiated by main.vhd
   ---------------------------------------------------------------------------

   i_video_sync : entity work.video_sync
      port map (
         clk32     => clk,
         pause     => '0',
         hsync     => vic_hsync,
         vsync     => vic_vsync,
         ntsc      => ntsc_sl,
         wide      => wide_sl,
         hsync_out => hsync_out,
         vsync_out => vsync_out,
         hblank    => hblank,
         vblank    => vblank
      );

   ---------------------------------------------------------------------------
   -- Measurement
   ---------------------------------------------------------------------------

   p_measure : process
      variable cyc            : natural := 0;    -- clk32 cycle counter
      variable hs_q, vs_q     : std_logic := '0';
      variable hb_q, vb_q     : std_logic := '1';
      variable hso_q, vso_q   : std_logic := '0';
      variable last_hs        : natural := 0;
      variable last_vs        : natural := 0;
      variable frames_seen    : integer := -2;   -- first two vsyncs: warm-up
      variable line_period    : natural := 0;
      variable line_period_ok : boolean := true;
      variable lines_in_frame : natural := 0;
      variable frame_lines    : natural := 0;
      variable frame_cycles   : natural := 0;
      variable frame_ok       : boolean := true;
      variable hb_fall        : natural := 0;
      variable hb_low_len     : natural := 0;
      variable hso_rise       : natural := 0;
      variable hso_len        : natural := 0;
      variable hb_fall_ofs    : natural := 0;    -- hblank fall relative to VIC hsync rise
      variable hb_rise_ofs    : natural := 0;
      variable hso_rise_ofs   : natural := 0;
      variable vis_lines      : natural := 0;    -- lines with vblank low at hblank fall
      variable vis_lines_last : natural := 0;
      variable vb_fall_line   : natural := 0;    -- line index (since VIC vsync) of vblank fall
      variable vb_rise_line   : natural := 0;
      variable vso_rise_line  : natural := 0;
      variable vso_lines      : natural := 0;
      variable vso_on         : boolean := false;
      variable total_lines    : natural := 0;    -- running line counter
      variable vso_rise_total : natural := 0;
      variable active_cyc     : natural := 0;
      variable active_last    : natural := 0;
      variable x_first, x_last : natural := 0;   -- VIC raster X of first / last visible pixel
      variable y_first, y_last : natural := 0;   -- VIC raster Y of first / last visible line
      variable first_vis_line  : boolean := false;
      variable y_last_done     : natural := 0;   -- y_last of the last completed visible region
      variable prev_x          : natural := 0;
      variable fail_msg       : line;
      variable l              : line;
      variable fr_mhz         : real;

      procedure fail(s : string) is
      begin
         if fail_msg = null then
            write(fail_msg, s);
         end if;
      end procedure;

      procedure put(s : string) is
         variable ll : line;
      begin
         write(ll, s);
         writeline(output, ll);
      end procedure;

      function dots(c : natural) return string is
      begin
         return integer'image(c / 4) & " dots (" & integer'image(c) & " clk)";
      end function;

      function us(c : natural) return string is
         variable x : real := real(c) * 1.0e6 / real(G_CLK_HZ);
      begin
         return integer'image(integer(x * 1000.0) / 1000) & "." &
                integer'image((integer(x * 1000.0) mod 1000) / 100) &
                integer'image((integer(x * 1000.0) mod 100) / 10) &
                integer'image(integer(x * 1000.0) mod 10) & " us";
      end function;

      function fixed(x : real; decimals : natural) return string is
         variable scale : real := 10.0 ** decimals;
         variable n     : integer := integer(x * scale);
         variable fr    : string(1 to decimals);
         variable r     : integer;
      begin
         r := n mod integer(scale);
         for i in decimals downto 1 loop
            fr(i) := character'val(character'pos('0') + (r mod 10));
            r := r / 10;
         end loop;
         return integer'image(n / integer(scale)) & "." & fr;
      end function;

   begin
      wait until reset_n = '1';
      loop
         wait until rising_edge(clk);
         cyc := cyc + 1;

         -- VIC hsync rising edge: start of a line
         if vic_hsync = '1' and hs_q = '0' then
            if frames_seen >= 0 then
               if line_period /= 0 and line_period /= cyc - last_hs then
                  line_period_ok := false;
               end if;
            end if;
            line_period := cyc - last_hs;
            last_hs := cyc;
            lines_in_frame := lines_in_frame + 1;
            total_lines := total_lines + 1;
         end if;

         -- VIC vsync rising edge: start of a frame
         if vic_vsync = '1' and vs_q = '0' then
            if frames_seen >= 0 then
               if frame_cycles /= 0 and frame_cycles /= cyc - last_vs then
                  frame_ok := false;
               end if;
               frame_cycles := cyc - last_vs;
               if frame_lines /= 0 and frame_lines /= lines_in_frame then
                  frame_ok := false;
               end if;
               frame_lines := lines_in_frame;
               if vis_lines_last /= 0 and vis_lines_last /= vis_lines then
                  frame_ok := false;
               end if;
               vis_lines_last := vis_lines;
               active_last := active_cyc;
            end if;
            frames_seen := frames_seen + 1;
            last_vs := cyc;
            lines_in_frame := 0;
            vis_lines := 0;
            active_cyc := 0;
            exit when frames_seen > integer(G_FRAMES);
         end if;

         -- hblank edges
         if hblank = '0' and hb_q = '1' then
            hb_fall := cyc;
            hb_fall_ofs := cyc - last_hs;
            x_first := to_integer(dbg_x);
            if vblank = '0' then
               vis_lines := vis_lines + 1;
               if first_vis_line then
                  y_first := to_integer(dbg_y);
                  first_vis_line := false;
               end if;
               y_last := to_integer(dbg_y);
            end if;
         end if;
         if hblank = '1' and hb_q = '0' then
            hb_low_len := cyc - hb_fall;
            x_last := prev_x;
            hb_rise_ofs := cyc - last_hs;
         end if;

         -- vblank edges (line index counted since the VIC vsync rising edge)
         if vblank = '0' and vb_q = '1' then
            vb_fall_line := lines_in_frame;
            first_vis_line := true;
         end if;
         if vblank = '1' and vb_q = '0' then
            vb_rise_line := lines_in_frame;
            y_last_done := y_last;
         end if;

         -- hsync_out pulse (active high)
         if hsync_out = '1' and hso_q = '0' then
            hso_rise := cyc;
            hso_rise_ofs := cyc - last_hs;
         end if;
         if hsync_out = '0' and hso_q = '1' then
            hso_len := cyc - hso_rise;
         end if;

         -- vsync_out pulse (active high) in lines
         if vsync_out = '1' and vso_q = '0' then
            vso_rise_line := lines_in_frame;
            vso_rise_total := total_lines;
            vso_on := true;
         end if;
         if vsync_out = '0' and vso_q = '1' then
            vso_on := false;
            vso_lines := total_lines - vso_rise_total;
         end if;

         if hblank = '0' and vblank = '0' then
            active_cyc := active_cyc + 1;
         end if;

         prev_x := to_integer(dbg_x);
         hs_q := vic_hsync; vs_q := vic_vsync;
         hb_q := hblank; vb_q := vblank;
         hso_q := hsync_out; vso_q := vsync_out;
      end loop;

      -- report
      if G_NTSC then put("mode               : NTSC (VIC-II 6567R8)"); else put("mode               : PAL (VIC-II 6569)"); end if;
      if G_USE_VIC then put("video source       : real VIC-II video_vicii_656x"); else put("video source       : stimulus model"); end if;
      put("clk32 frequency    : " & integer'image(G_CLK_HZ) & " Hz");
      put("line period        : " & integer'image(line_period) & " clk = " &
          integer'image(line_period / 32) & " C64 cycles = " & integer'image(line_period / 4) & " dots = " & us(line_period));
      put("lines per frame    : " & integer'image(frame_lines));
      put("frame period       : " & integer'image(frame_cycles) & " clk");
      fr_mhz := real(G_CLK_HZ) / real(frame_cycles);
      put("frame rate         : " & fixed(fr_mhz, 6) & " Hz");
      put("hblank low (visible): " & dots(hb_low_len) & " from dot " & integer'image(hb_fall_ofs / 4) &
          " to dot " & integer'image(hb_rise_ofs / 4) & " after VIC hsync rise");
      put("vblank low (visible): " & integer'image(vis_lines_last) & " lines, from line " &
          integer'image(vb_fall_line) & " to line " & integer'image(vb_rise_line) &
          " counted from the VIC vsync rise (wraps at lines per frame)");
      put("visible raster box : VIC rasterY " & integer'image(y_first) & " .. " & integer'image(y_last_done) &
          ", VIC rasterX (debugX, pixel-delayed) " & integer'image(x_first) & " .. " & integer'image(x_last));
      put("active area        : " & integer'image(active_last / 4) & " dots = " &
          integer'image(hb_low_len / 4) & " x " & integer'image(vis_lines_last));
      put("hsync_out pulse    : " & dots(hso_len) & " = " & us(hso_len) & ", starts at dot " &
          integer'image(hso_rise_ofs / 4) & " after VIC hsync rise");
      put("vsync_out pulse    : " & integer'image(vso_lines) & " lines (last completed pulse), starts at line " &
          integer'image(vso_rise_line) & " after VIC vsync rise");

      if not line_period_ok then fail("line period not constant"); end if;
      if not frame_ok then fail("frame period / lines / visible lines not constant"); end if;
      if line_period /= cycles_per_line * 32 then fail("line period is not " & integer'image(cycles_per_line) & " C64 cycles"); end if;
      if frame_lines /= lines_per_frame then fail("lines per frame is not " & integer'image(lines_per_frame)); end if;
      if frame_cycles /= cycles_per_line * lines_per_frame * 32 then fail("frame period mismatch"); end if;
      if active_last /= hb_low_len * vis_lines_last then fail("active area is not rectangular"); end if;
      if G_CHECK_PAL and not G_NTSC and not G_WIDE then
         if hb_low_len /= 382 * 4 then fail("PAL visible width is not 382"); end if;
         if vis_lines_last /= 270 then fail("PAL visible height is not 270"); end if;
      end if;

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
