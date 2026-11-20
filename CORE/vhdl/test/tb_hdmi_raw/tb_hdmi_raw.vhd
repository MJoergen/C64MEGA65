----------------------------------------------------------------------------------------------------
-- Bench for the "Raw" HDMI modes (issue #184): the real scaler ascal.vhd in direct mode, the real
-- crop.vhd, the genlock hdmi_genlock.vhd with the wiring of SPEC.md section 5.1, a memory model on
-- the Avalon port and a model of the core's picture. See README.md.
--
-- Every pixel of the core carries its frame number (red), its visible line (green) and its visible
-- column (blue), each modulo 256. The checker looks at every pixel of the HDMI picture.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_hdmi_raw is
   generic (
      -- core picture
      G_NTSC          : boolean := false;
      G_CROP          : boolean := false;      -- zoom-in (crop.vhd) at the start
      G_CROP_FLIP1    : integer := -1;         -- toggle zoom-in after this HDMI frame (-1 = never) ...
      G_CROP_FLIP2    : integer := -1;         -- ... and again after this one
      G_CORE_NUM_PS   : natural := 3600000;    -- half period of the core clock = NUM / DEN ps
      G_CORE_DEN      : natural := 227;
      G_CORE_LINE0    : natural := 300;        -- raster line in which the core picture starts
      -- HDMI timing (as ascal gets it)
      G_HTOTAL        : natural := 864;
      G_HSSTART       : natural := 732;
      G_HSEND         : natural := 796;
      G_HDISP         : natural := 720;
      G_VTOTAL        : natural := 624;
      G_VSSTART       : natural := 580;
      G_VSEND         : natural := 585;
      G_VDISP         : natural := 576;
      G_HMIN          : natural := 0;
      G_HMAX          : natural := 719;
      G_VMIN          : natural := 0;
      G_VMAX          : natural := 575;
      G_HDMI_NUM_PS   : natural := 4200000;    -- half period of the HDMI clock = NUM / DEN ps
      G_HDMI_DEN      : natural := 227;
      G_HDMI_START_NS : natural := 0;          -- the HDMI clock starts this late (ns)
      G_START_LINES   : natural := 40;         -- length of the short first pass of the HDMI timing (0 = none)
      -- genlock
      G_RAW           : boolean := true;       -- raw mode: genlock enabled and selected by the multiplexer
      G_NO_GENLOCK    : boolean := false;      -- reference design: no genlock, no multiplexer
      G_TARGET        : natural := 54046;      -- target_i in HDMI clocks
      G_REF_OLD       : boolean := false;      -- mutant: reference from the falling edge of the cropped vblank
      -- memory model (clocks of the 100 MHz Avalon clock)
      G_MEM_CMD       : natural := 12;         -- command latency (arbiter, controller) before a burst is accepted
      G_MEM_BEAT      : natural := 8;          -- clocks per 128-bit beat (eight 16-bit words)
      G_MEM_RLAT      : natural := 28;         -- read: first 128-bit beat after acceptance
      G_MEM_EXTRA     : natural := 0;          -- contention: random extra latency 0 .. G_MEM_EXTRA per burst
      G_MEM_PAUSE     : natural := 0;          -- contention: pause of this length ...
      G_MEM_PAUSE_ONE : natural := 0;          -- ... before one burst in G_MEM_PAUSE_ONE (0 = never)
      G_SEED          : natural := 1;
      G_TCORE         : natural := 1995040;    -- core frame in clocks of the Avalon clock (10 ns)
      -- run and checks
      G_FRAMES        : natural := 4;          -- HDMI frames (counted at the rising edge of o_vs)
      G_CHECK_FROM    : natural := 0;          -- first checked frame
      G_SETTLE        : natural := 0;          -- frames before G_SETTLE may tear (pull-in)
      G_D_LO          : integer := -1;         -- from frame G_SETTLE on: G_D_LO <= d <= G_D_HI (-1 = no check)
      G_D_HI          : integer := -1;
      G_D_STEP        : integer := 600;        -- after frame G_SETTLE: |d - d of the previous frame| <= this
      G_STRETCH_MAX   : natural := 256;        -- longest allowed extra length of a line
      G_DUMP          : integer := -1          -- frame whose picture lines are reported (-1 = none)
   );
end entity tb_hdmi_raw;

architecture sim of tb_hdmi_raw is

   ----------------------------------------------------------------------------------------------
   -- core geometry (video_sync.vhd, wide = '0')
   ----------------------------------------------------------------------------------------------
   function sel(c : boolean; a, b : natural) return natural is
   begin
      if c then return a; else return b; end if;
   end function;
   constant C_DOTS    : natural := sel(G_NTSC, 520, 504);
   constant C_LINES   : natural := sel(G_NTSC, 263, 312);
   constant C_HB_OFF  : natural := sel(G_NTSC, 112, 107);   -- hblank '0' from this dot
   constant C_HB_ON   : natural := sel(G_NTSC, 516, 489);   -- hblank '1' from this dot
   constant C_VB_OFF  : natural := sel(G_NTSC, 13, 28);     -- vblank '0' from this line
   constant C_VB_ON   : natural := sel(G_NTSC, 0, 298);     -- vblank '1' from this line
   constant C_HS_ON   : natural := sel(G_NTSC, 16, 10);
   constant C_HS_OFF  : natural := sel(G_NTSC, 54, 48);
   constant C_VS_ON   : natural := sel(G_NTSC, 0, 307);     -- vsync rises at dot C_HS_ON of this line
   constant C_VS_OFF  : natural := sel(G_NTSC, 4, 311);
   constant C_VIS_W   : natural := C_HB_ON - C_HB_OFF;      -- 382 / 404
   constant C_VIS_H   : natural := sel(G_NTSC, 250, 270);
   -- what the scaler gets (crop.vhd with zoom-in: 348 x 208 out of the visible area; its y_count is
   -- 1 on the first visible line)
   function in_x0(c : boolean) return natural is begin return sel(c, sel(G_NTSC, 30, 19), 0); end function;
   function in_y0(c : boolean) return natural is begin return sel(c, sel(G_NTSC, 21, 30), 0); end function;
   function in_w(c : boolean) return natural is begin return sel(c, 348, C_VIS_W); end function;
   function in_h(c : boolean) return natural is begin return sel(c, 208, C_VIS_H); end function;
   -- the Avalon monitor interprets addresses with the geometry of the start
   constant C_IN_H    : natural := in_h(G_CROP);
   constant C_STRIDE  : natural := ((in_w(G_CROP) * 3 + 127) / 128) * 128;  -- bytes per line in the frame buffer

   constant C_TA      : time := 5 ns;                       -- half period of the 100 MHz Avalon clock
   constant C_HDMI_PRE : natural := 16;                     -- HDMI clock periods before the pause

   signal done        : boolean := false;
   signal crop_sl     : std_logic := '0';
   signal crop_req    : natural := 0;                       -- toggles of zoom-in requested by the checker
   signal core_clk    : std_logic := '0';
   signal hdmi_clk    : std_logic := '0';
   signal avl_clk     : std_logic := '0';

   -- core picture
   signal c_ce        : std_logic := '0';
   signal c_r, c_g, c_b : std_logic_vector(7 downto 0) := (others => '0');
   signal c_hs, c_vs, c_hblank, c_vblank : std_logic := '0';
   -- after crop.vhd
   signal v_ce        : std_logic;
   signal v_r, v_g, v_b : std_logic_vector(7 downto 0);
   signal v_hs, v_vs, v_hblank, v_vblank : std_logic;
   signal v_de        : std_logic;

   -- reference (SPEC 5.1)
   signal ref_level   : std_logic := '0';
   signal ref_sync    : std_logic_vector(1 downto 0) := "00";
   signal ref_sync_d  : std_logic := '0';
   signal ref_pulse   : std_logic := '0';
   signal refo_level  : std_logic := '0';
   signal ref_true    : std_logic := '0';                   -- correct reference, for the bench's own d
   signal t_sync_s, t_sync_d : std_logic := '0';

   -- HDMI side
   signal hdmi_rst    : std_logic := '1';
   signal reset_na    : std_logic := '0';
   signal o_r, o_g, o_b : unsigned(7 downto 0);
   signal o_hs, o_vs, o_de, o_vbl, o_brd : std_logic;
   signal raw         : std_logic;
   signal gl_htotal   : natural range 0 to 4095 := G_HTOTAL;
   signal gl_locked   : std_logic := '0';
   signal gl_stretch  : natural range 0 to 4095 := 0;
   signal htotal_sc   : natural range 0 to 4095;
   signal hdmax, vdmax : natural range 0 to 4095;
   signal mon_reported : natural := 0;                      -- passes reported by the Avalon monitor
   signal vtotal_sc   : natural range 0 to 4095 := G_START_LINES;
   signal vsstart_sc  : natural range 0 to 4095 := G_START_LINES - 8;
   signal vsend_sc    : natural range 0 to 4095 := G_START_LINES - 6;
   signal vdisp_sc    : natural range 0 to 4095 := 0;
   signal vmin_sc     : natural range 0 to 4095 := 4000;
   signal vmax_sc     : natural range 0 to 4095 := 4001;
   signal lltune      : unsigned(15 downto 0);

   -- Avalon
   signal avl_waitrequest   : std_logic := '1';
   signal avl_readdata      : std_logic_vector(127 downto 0) := (others => '0');
   signal avl_readdatavalid : std_logic := '0';
   signal avl_burstcount    : std_logic_vector(7 downto 0);
   signal avl_writedata     : std_logic_vector(127 downto 0);
   signal avl_address       : std_logic_vector(18 downto 0);
   signal avl_write         : std_logic;
   signal avl_read          : std_logic;
   signal avl_byteenable    : std_logic_vector(15 downto 0);

   function to_sl(c : boolean) return std_logic is
   begin
      if c then return '1'; else return '0'; end if;
   end function;

begin

   ----------------------------------------------------------------------------------------------
   -- Clocks: edge n of a clock lies at floor(n * NUM / DEN) ps after its start, so that the
   -- long-term frequency is exact (100 MHz x M / D of the MMCMs).
   ----------------------------------------------------------------------------------------------
   p_core_clk : process
      variable n : natural := 0;
   begin
      while not done loop
         n := n + 1;
         wait for ((G_CORE_NUM_PS * 1 ps) * n) / G_CORE_DEN - now;
         core_clk <= not core_clk;
      end loop;
      wait;
   end process;

   -- The HDMI clock runs C_HDMI_PRE periods from the start (through the reset of the scaler, whose
   -- output side takes its reset with this clock), pauses, and resumes at G_HDMI_START_NS.
   p_hdmi_clk : process
      variable n : natural := 0;
   begin
      for i in 1 to 2 * C_HDMI_PRE loop
         wait for ((G_HDMI_NUM_PS * 1 ps) * i) / G_HDMI_DEN - now;
         hdmi_clk <= not hdmi_clk;
      end loop;
      wait for G_HDMI_START_NS * 1 ns - now;
      while not done loop
         n := n + 1;
         wait for G_HDMI_START_NS * 1 ns + ((G_HDMI_NUM_PS * 1 ps) * n) / G_HDMI_DEN - now;
         hdmi_clk <= not hdmi_clk;
      end loop;
      wait;
   end process;

   avl_clk <= not avl_clk after C_TA when not done;

   ----------------------------------------------------------------------------------------------
   -- Core picture as video_sync.vhd delivers it: pixel enable = core clock / 4
   ----------------------------------------------------------------------------------------------
   p_core : process (core_clk)
      variable div   : natural range 0 to 3 := 0;
      variable dot   : natural range 0 to 1023 := 0;
      -- The model starts a few lines before its vsync, as a C64 that has been running: the scaler
      -- delimits its first input picture only by a vsync before it.
      variable line  : natural range 0 to 511 := G_CORE_LINE0;
      variable frame : natural := 0;
      variable hb, vb : std_logic := '1';
      variable crop   : std_logic := to_sl(G_CROP);
      variable flips  : natural := 0;
   begin
      if rising_edge(core_clk) then
         crop_sl <= crop;
         c_ce <= '0';
         if div = 3 then
            div := 0;
            c_ce <= '1';
            if dot = C_DOTS - 1 then
               dot := 0;
               if line = C_LINES - 1 then
                  line := 0;
                  frame := frame + 1;
               else
                  line := line + 1;
               end if;
            else
               dot := dot + 1;
            end if;
            if dot = C_HB_ON then hb := '1'; elsif dot = C_HB_OFF then hb := '0'; end if;
            if line = C_VB_ON then vb := '1'; elsif line = C_VB_OFF then vb := '0'; end if;
            if dot = C_HS_ON then
               c_hs <= '1';
               if line = C_VS_ON then
                  c_vs <= '1';
                  -- a requested toggle of zoom-in takes effect at the vsync: no core frame is mixed
                  if flips < crop_req then
                     crop  := not crop;
                     flips := flips + 1;
                  end if;
               elsif line = C_VS_OFF then
                  c_vs <= '0';
               end if;
            elsif dot = C_HS_OFF then
               c_hs <= '0';
            end if;
            c_hblank <= hb;
            c_vblank <= vb;
            -- the code is present also in the blanking: crop.vhd delays the blanking by one
            -- pixel enable but the colors by one clock, so the scaler takes one pixel after hblank
            c_r <= std_logic_vector(to_unsigned(frame mod 256, 8));
            c_g <= std_logic_vector(to_unsigned((line + 512 - C_VB_OFF) mod 256, 8));
            c_b <= std_logic_vector(to_unsigned((dot + 1024 - C_HB_OFF) mod 256, 8));
         else
            div := div + 1;
         end if;
      end if;
   end process;

   i_crop : entity work.crop
      port map (
         video_crop_mode_i => crop_sl,
         video_ntsc_i      => to_sl(G_NTSC),
         video_clk_i       => core_clk,
         video_rst_i       => '0',
         video_ce_i        => c_ce,
         video_red_i       => c_r,
         video_green_i     => c_g,
         video_blue_i      => c_b,
         video_hs_i        => c_hs,
         video_vs_i        => c_vs,
         video_hblank_i    => c_hblank,
         video_vblank_i    => c_vblank,
         video_ce_o        => v_ce,
         video_red_o       => v_r,
         video_green_o     => v_g,
         video_blue_o      => v_b,
         video_hs_o        => v_hs,
         video_vs_o        => v_vs,
         video_hblank_o    => v_hblank,
         video_vblank_o    => v_vblank
      );

   v_de <= not (v_hblank or v_vblank);

   ----------------------------------------------------------------------------------------------
   -- Reference of the genlock as in digital_pipeline.vhd (SPEC 5.1): a register in the core clock
   -- domain, cleared by the rising edge of video_vs_i and set by the first visible pixel after it;
   -- two flip-flops into the HDMI clock domain (xpm_cdc_single with DEST_SYNC_FF = 2); the pulse
   -- is the synchronized level and not its value one clock earlier.
   -- G_REF_OLD: the former wiring, the falling edge of video_vblank_i (after the crop).
   ----------------------------------------------------------------------------------------------
   p_ref_core : process (core_clk)
      variable vs_d, de_d : std_logic := '0';
   begin
      if rising_edge(core_clk) then
         if v_vs = '1' and vs_d = '0' then
            ref_level <= '0';
         elsif v_de = '1' and de_d = '0' then
            ref_level <= '1';
         end if;
         refo_level <= not v_vblank;
         vs_d := v_vs;
         de_d := v_de;
      end if;
   end process;

   p_ref_hdmi : process (hdmi_clk)
      variable t_sync : std_logic_vector(1 downto 0) := "00";
   begin
      if rising_edge(hdmi_clk) then
         if G_REF_OLD then
            ref_sync <= ref_sync(0) & refo_level;
         else
            ref_sync <= ref_sync(0) & ref_level;
         end if;
         ref_sync_d <= ref_sync(1);
         -- the correct reference, independent of G_REF_OLD, for the bench's own measurement of d
         t_sync := t_sync(0) & ref_level;
         t_sync_s <= t_sync(1);
         t_sync_d <= t_sync_s;
      end if;
   end process;

   ref_pulse <= ref_sync(1) and not ref_sync_d;
   ref_true  <= t_sync_s and not t_sync_d;

   ----------------------------------------------------------------------------------------------
   -- Genlock and the multiplexer in front of htotal (SPEC 5.1)
   ----------------------------------------------------------------------------------------------
   raw <= '1' when G_RAW else '0';

   gen_genlock : if not G_NO_GENLOCK generate
      i_genlock : entity work.hdmi_genlock
         port map (
            clk_i     => hdmi_clk,
            rst_i     => hdmi_rst,
            enable_i  => raw,
            htotal_i  => G_HTOTAL,
            target_i  => G_TARGET,
            hs_i      => o_hs,
            vs_i      => o_vs,
            de_i      => o_de,
            ref_i     => ref_pulse,
            htotal_o  => gl_htotal,
            locked_o  => gl_locked,
            stretch_o => gl_stretch
         );
      htotal_sc <= gl_htotal when raw = '1' else G_HTOTAL;
   end generate gen_genlock;

   gen_reference : if G_NO_GENLOCK generate
      htotal_sc <= G_HTOTAL;
   end generate gen_reference;

   p_hdmi_rst : process (hdmi_clk)
      variable n : natural := 0;
   begin
      if rising_edge(hdmi_clk) then
         if n < 16 then n := n + 1; else hdmi_rst <= '0'; end if;
      end if;
   end process;

   reset_na <= '1' after 100 ns;

   ----------------------------------------------------------------------------------------------
   -- Startup: the scaler takes over the size of the input picture only at a falling edge of its
   -- output vsync after a complete input picture, so the first pass of its counters never shows a
   -- picture. To save that frame, the first pass is G_START_LINES lines short, without data enable
   -- and with a vsync that ends three lines before the scaler preloads the first two lines of the
   -- picture (at the wrap of its lead counter, three lines before its output counters wrap). During
   -- the first pass the vertical window lies out of reach (vmin 4000), so that the scaler fetches
   -- nothing before it knows the size of its input picture (a preload with size 0 leaves its read
   -- FIFO misaligned for a frame); the real window is applied in the horizontal blanking one line
   -- before the lead counter wraps, the real vertical timing in the horizontal blanking of the last
   -- line before the first picture (the scaler takes these inputs over in every clock).
   ----------------------------------------------------------------------------------------------
   p_start : process (hdmi_clk)
      variable n : natural := 0;
      constant C_SWITCH : natural := (G_START_LINES + 2) * G_HTOTAL + (G_HDISP + G_HTOTAL) / 2;
      constant C_WINDOW : natural := (G_START_LINES - 1) * G_HTOTAL + (G_HDISP + G_HTOTAL) / 2;
   begin
      if rising_edge(hdmi_clk) then
         if G_START_LINES > 0 and n < C_WINDOW then
            vmin_sc <= 4000;
            vmax_sc <= 4001;
         else
            vmin_sc <= G_VMIN;
            vmax_sc <= G_VMAX;
         end if;
         if G_START_LINES > 0 and n < C_SWITCH then
            vtotal_sc  <= G_START_LINES;
            vsstart_sc <= G_START_LINES - 8;
            vsend_sc   <= G_START_LINES - 6;
            vdisp_sc   <= 0;
            n := n + 1;
         else
            vtotal_sc  <= G_VTOTAL;
            vsstart_sc <= G_VSSTART;
            vsend_sc   <= G_VSEND;
            vdisp_sc   <= G_VDISP;
         end if;
      end if;
   end process;

   ----------------------------------------------------------------------------------------------
   -- The scaler, configured as in M2M/vhdl/av_pipeline/digital_pipeline.vhd
   ----------------------------------------------------------------------------------------------
   i_ascal : entity work.ascal
      generic map (
         MASK         => x"ff",
         RAMBASE      => (others => '0'),
         RAMSIZE      => to_unsigned(2**21, 32),      -- 2**f_log2(720 * 540 * 3)
         INTER        => false,
         HEADER       => false,
         DOWNSCALE    => false,
         DOWNSCALE_NN => true,
         BYTESWAP     => true,
         ADAPTIVE     => true,
         PALETTE      => false,
         PALETTE2     => false,
         FRAC         => 6,
         OHRES        => 2048,
         IHRES        => 1024,
         N_DW         => 128,
         N_AW         => 19,
         N_BURST      => 128
      )
      port map (
         i_r => unsigned(v_r), i_g => unsigned(v_g), i_b => unsigned(v_b),
         i_hs => v_hs, i_vs => v_vs, i_fl => '0', i_de => v_de, i_ce => v_ce, i_clk => core_clk,
         o_r => o_r, o_g => o_g, o_b => o_b, o_hs => o_hs, o_vs => o_vs, o_de => o_de,
         o_vbl => o_vbl, o_brd => o_brd, o_ce => '1', o_clk => hdmi_clk,
         o_border => x"000000",
         o_fb_ena => '0', o_fb_hsize => 0, o_fb_vsize => 0, o_fb_format => "000101",
         o_fb_base => x"0000_0000", o_fb_stride => (others => '0'),
         pal1_clk => '0', pal1_dw => x"000000000000", pal1_dr => open, pal1_a => "0000000", pal1_wr => '0',
         pal_n => '0',
         pal2_clk => '0', pal2_dw => x"000000", pal2_dr => open, pal2_a => "00000000", pal2_wr => '0',
         o_lltune => lltune,
         iauto => '1', himin => 0, himax => 0, vimin => 0, vimax => 0,
         i_hdmax => hdmax, i_vdmax => vdmax,
         run => '1', freeze => '0',
         mode => "00000",                              -- nearest ("No Filter"), no triple buffering
         htotal => htotal_sc, hsstart => G_HSSTART, hsend => G_HSEND, hdisp => G_HDISP,
         vtotal => vtotal_sc, vsstart => vsstart_sc, vsend => vsend_sc, vdisp => vdisp_sc,
         hmin => G_HMIN, hmax => G_HMAX, vmin => vmin_sc, vmax => vmax_sc,
         format => "01",
         poly_clk => '0', poly_dw => (others => '0'), poly_a => (others => '0'), poly_wr => '0',
         avl_clk => avl_clk, avl_waitrequest => avl_waitrequest, avl_readdata => avl_readdata,
         avl_readdatavalid => avl_readdatavalid, avl_burstcount => avl_burstcount,
         avl_writedata => avl_writedata, avl_address => avl_address, avl_write => avl_write,
         avl_read => avl_read, avl_byteenable => avl_byteenable,
         reset_na => reset_na
      );

   ----------------------------------------------------------------------------------------------
   -- Memory model on the 128-bit Avalon port, in order: a burst is accepted after the command
   -- latency (plus contention), a write beat every G_MEM_BEAT clocks, read data G_MEM_RLAT clocks
   -- after acceptance and then every G_MEM_BEAT clocks; the next burst waits until the previous
   -- one has left the memory. Reads see every write accepted before them.
   --
   -- The monitor in the same process measures, per line of the frame buffer: when its last write
   -- burst was accepted (the line is in memory) and when its first read burst was accepted (the
   -- scaler fetches it); distance = fetch - written, margin = next write of the line - last fetch.
   ----------------------------------------------------------------------------------------------
   p_mem : process (avl_clk)
      constant C_WORDS : natural := 32768;   -- 512 kB, enough for one picture of 404 x 250
      type mem_t is array (0 to C_WORDS - 1) of std_logic_vector(127 downto 0);
      variable mem     : mem_t;
      type rq_t is array (0 to 7) of natural;
      variable rq_adr  : rq_t;
      variable rq_time : rq_t;
      variable rq_n    : natural := 0;
      variable rbeat   : natural := 0;
      variable clk_n   : natural := 0;
      variable ready   : natural := 0;       -- clock from which the next burst may start
      variable cmd     : boolean := false;   -- a burst waits for its command latency
      variable go      : natural := 0;       -- clock at which the next beat or burst is accepted
      variable wbeat   : natural := 0;
      variable waddr   : natural := 0;
      variable lfsr    : unsigned(31 downto 0) := to_unsigned(G_SEED * 7919 + 12345, 32);
      variable acc     : boolean;
      variable extra   : natural;
      variable radr    : natural;
      -- monitor (times in clocks of the 100 MHz Avalon clock)
      type tl_t is array (0 to 511) of integer;
      variable w_done  : tl_t := (others => -1);   -- last write burst of the line accepted
      variable w_first : tl_t := (others => -1);   -- first write burst of the line accepted
      variable r_seen  : tl_t := (others => -1);   -- pass in which the line was fetched last
      variable r_last  : tl_t := (others => -1);   -- last read burst of the line accepted
      variable lin, bur : natural;
      variable dist    : integer;
      variable dtop, dbot, dmin, dmax, mmin : integer;
      variable fstart  : natural := 0;              -- first read burst of the line being fetched
      variable fmax    : natural := 0;              -- longest fetch of a line (first to last burst)
      variable pass    : natural := 0;
      variable last_w  : natural := 0;              -- 16-bit word address of the last write burst
      variable ff      : natural := 0;              -- last_w at the read of address 0 (hdmi_flicker_free)
      constant C_BPL   : natural := C_STRIDE / 128;  -- bursts per line

      impure function rnd(maxv : natural) return natural is
      begin
         lfsr := lfsr(30 downto 0) & (lfsr(31) xor lfsr(21) xor lfsr(1) xor lfsr(0));
         if maxv = 0 then return 0; end if;
         return to_integer(lfsr(15 downto 0)) mod (maxv + 1);
      end function;
   begin
      if rising_edge(avl_clk) then
         clk_n := clk_n + 1;
         avl_readdatavalid <= '0';
         acc := false;

         if avl_waitrequest = '0' and avl_write = '1' then
            acc := true;
            if wbeat = 0 then
               waddr := to_integer(unsigned(avl_address));
               assert waddr + 8 <= C_WORDS report "write outside the memory model" severity failure;
               lin := (waddr * 16) / C_STRIDE;
               bur := ((waddr * 16) mod C_STRIDE) / 128;
               -- monitor: a new core frame begins to write the line
               if bur = 0 and lin < 512 then
                  w_first(lin) := clk_n;
               end if;
            end if;
            mem(waddr + wbeat) := avl_writedata;
            last_w := waddr * 8;
            if G_DUMP = -2 and wbeat = 0 and (waddr * 16) / C_STRIDE + 3 >= C_IN_H then
               report "WRITE line=" & integer'image((waddr * 16) / C_STRIDE) & " burst=" &
                      integer'image(((waddr * 16) mod C_STRIDE) / 128) & " now=" & integer'image(clk_n) &
                      " data=" & to_hstring(avl_writedata) severity note;
            end if;
            if wbeat = 7 then
               wbeat := 0;
               ready := clk_n + 2;
               lin := (waddr * 16) / C_STRIDE;
               bur := ((waddr * 16) mod C_STRIDE) / 128;
               if lin < 512 and bur = C_BPL - 1 then
                  w_done(lin) := clk_n;     -- the line is in memory
               end if;
            else
               wbeat := wbeat + 1;
               go := clk_n + G_MEM_BEAT;
            end if;
         elsif avl_waitrequest = '0' and avl_read = '1' then
            acc  := true;
            radr := to_integer(unsigned(avl_address));
            assert rq_n < 7 report "read queue overflow" severity failure;
            rq_adr(rq_n)  := radr;
            rq_time(rq_n) := clk_n + G_MEM_RLAT;
            rq_n  := rq_n + 1;
            ready := clk_n + G_MEM_RLAT + 8 * G_MEM_BEAT;
            -- monitor: a read of address 0 begins a new pass (an HDMI frame)
            if radr = 0 then
               if pass > 0 then
                  report "MEM pass=" & integer'image(pass) & " dist_top=" & integer'image(dtop) &
                         " dist_bot=" & integer'image(dbot) & " dist_min=" & integer'image(dmin) &
                         " dist_max=" & integer'image(dmax) & " margin_min=" & integer'image(mmin) &
                         " ff_words=" & integer'image(ff) & " fetch_max=" & integer'image(fmax) &
                         " (clocks of 10 ns)" severity note;
                  mon_reported <= pass;
               end if;
               pass := pass + 1;
               ff   := last_w;
               dtop := -1; dbot := -1; dmin := 99999999; dmax := -1; mmin := 99999999; fmax := 0;
            end if;
            lin := (radr * 16) / C_STRIDE;
            bur := ((radr * 16) mod C_STRIDE) / 128;
            if bur = 0 then fstart := clk_n; end if;
            if bur = C_BPL - 1 and clk_n - fstart > fmax then fmax := clk_n - fstart; end if;
            if lin < 512 then
               if bur = 0 and r_seen(lin) /= pass and lin < C_IN_H and w_done(lin) >= 0 then
                  r_seen(lin) := pass;
                  dist := clk_n - w_done(lin);
                  if lin = 0 then dtop := dist; end if;
                  if lin = C_IN_H - 1 then dbot := dist; end if;
                  if dist < dmin then dmin := dist; end if;
                  if dist > dmax then dmax := dist; end if;
               end if;
               r_last(lin) := clk_n;
               -- margin: the core writes strictly periodically, its next frame begins to overwrite
               -- this line one core frame after it began to write it
               if lin < C_IN_H and w_first(lin) >= 0 then
                  dist := w_first(lin) + G_TCORE - clk_n;
                  if dist < mmin then mmin := dist; end if;
               end if;
               if G_DUMP >= 0 and lin + 3 >= C_IN_H and bur = 0 then
                  report "FETCH pass=" & integer'image(pass) & " line=" & integer'image(lin) &
                         " written_at=" & integer'image(w_done(lin)) & " now=" & integer'image(clk_n) severity note;
               end if;
            end if;
         end if;

         -- read data, in order
         if rq_n > 0 and clk_n >= rq_time(0) then
            avl_readdata      <= mem((rq_adr(0) + rbeat) mod C_WORDS);
            avl_readdatavalid <= '1';
            if rbeat = 7 then
               rbeat := 0;
               for i in 0 to 6 loop rq_adr(i) := rq_adr(i + 1); rq_time(i) := rq_time(i + 1); end loop;
               rq_n := rq_n - 1;
            else
               rbeat := rbeat + 1;
               rq_time(0) := rq_time(0) + G_MEM_BEAT;
            end if;
         end if;

         -- waitrequest for the next clock
         avl_waitrequest <= '1';
         if wbeat /= 0 then
            if clk_n + 1 >= go then avl_waitrequest <= '0'; end if;      -- next beat of a write burst
         elsif not acc and (avl_write = '1' or avl_read = '1') then
            if not cmd then                                               -- a new burst
               cmd   := true;
               extra := rnd(G_MEM_EXTRA);
               if G_MEM_PAUSE_ONE > 0 then
                  if rnd(G_MEM_PAUSE_ONE - 1) = 0 then extra := extra + G_MEM_PAUSE; end if;
               end if;
               if ready > clk_n then go := ready; else go := clk_n; end if;
               go := go + G_MEM_CMD + extra;
            end if;
            if clk_n + 1 >= go then
               avl_waitrequest <= '0';
               cmd := false;
            end if;
         end if;
      end if;
   end process;

   ----------------------------------------------------------------------------------------------
   -- Checker of the HDMI picture and of the HDMI timing
   ----------------------------------------------------------------------------------------------
   p_check : process (hdmi_clk)
      constant C_PW : natural := G_HMAX - G_HMIN + 1;       -- picture pixels per line
      constant C_PH : natural := G_VMAX - G_VMIN + 1;       -- picture lines
      variable crop_exp : boolean := G_CROP;                -- zoom-in of the current frame's picture
      variable geo_chk  : boolean := true;                  -- geometry checked in this frame
      variable C_G0, C_GL, C_B0, C_BL : natural;            -- first and last input line and column
      variable hs_d, vs_d, de_d : std_logic := '0';
      variable frame    : integer := -1;
      variable clk_f    : natural := 0;       -- clocks of the current frame
      variable clk_l    : natural := 0;       -- clocks of the current line
      variable lines_f  : natural := 0;
      variable picl     : natural := 0;       -- picture lines of this frame
      variable px       : natural := 0;       -- picture pixels of this line
      variable fr       : integer := -1;      -- frame number of the first picture pixel
      variable fr_prev  : integer := -1;
      variable tear     : integer := -1;
      variable lg, lb, lb0 : integer := -1;   -- green / blue of the line, blue of the previous pixel
      variable pg       : integer := -1;      -- green of the previous picture line
      variable geo      : natural := 0;       -- geometry errors of this frame
      variable sig      : natural := 0;
      variable sig_ref  : integer := -1;
      variable errors   : natural := 0;
      variable checked  : natural := 0;
      variable tears, steps : natural := 0;
      variable lock_frame : integer := -1;
      variable dcnt     : natural := 0;
      variable d        : integer := -1;
      variable d_prev   : integer := -1;
      variable d_armed  : boolean := false;
      variable dmin_f, dmax_f : integer := -1;
      variable longest, shortest : natural := 0;
      variable chk      : boolean;
      variable hsh      : natural := 0;       -- hash of all outputs, clock by clock
      variable pix      : natural;
      variable step     : integer;
      variable init     : boolean := true;

      procedure err(s : string) is
      begin
         errors := errors + 1;
         if errors <= 40 then
            report "ERROR frame " & integer'image(frame) & ": " & s severity warning;
         end if;
      end procedure;
   begin
      if rising_edge(hdmi_clk) then
         chk := frame >= G_CHECK_FROM;
         if init then
            init := false;
            C_G0 := in_y0(crop_exp) mod 256;
            C_GL := (in_y0(crop_exp) + in_h(crop_exp) - 1) mod 256;
            C_B0 := in_x0(crop_exp) mod 256;
            C_BL := (in_x0(crop_exp) + in_w(crop_exp) - 1) mod 256;
         end if;

         -- hash of the scaler outputs, clock by clock (check of identity between two runs)
         pix := to_integer(o_r) * 65536 + to_integer(o_g) * 256 + to_integer(o_b);
         if o_hs = '1' then pix := pix + 16777216; end if;
         if o_vs = '1' then pix := pix + 33554432; end if;
         if o_de = '1' then pix := pix + 67108864; end if;
         hsh := ((hsh mod 16777216) * 97 + pix) mod 1073741789;

         -- d: HDMI clocks from the core's picture start to the HDMI picture start
         if ref_true = '1' then dcnt := 0; elsif dcnt < 4194303 then dcnt := dcnt + 1; end if;
         if vs_d = '1' and o_vs = '0' then d_armed := true; end if;
         if d_armed and de_d = '0' and o_de = '1' then
            d_armed := false;
            d := dcnt;
         end if;

         -- lines
         clk_f := clk_f + 1;
         clk_l := clk_l + 1;
         if hs_d = '0' and o_hs = '1' then
            if frame >= 0 and lines_f > 0 then
               if clk_l < G_HTOTAL then err("line shorter than htotal: " & integer'image(clk_l)); end if;
               if clk_l > G_HTOTAL + G_STRETCH_MAX then err("line too long: " & integer'image(clk_l)); end if;
               if clk_l > longest then longest := clk_l; end if;
               if shortest = 0 or clk_l < shortest then shortest := clk_l; end if;
            end if;
            clk_l := 0;
            lines_f := lines_f + 1;
         end if;

         -- picture pixels
         if o_de = '1' and o_brd = '0' then
            if px = 0 then
               lg := to_integer(o_g);
               if picl = 0 then
                  fr := to_integer(o_r);
                  if lg /= C_G0 then geo := geo + 1; end if;
               else
                  step := (lg - pg + 256) mod 256;
                  if step > 1 then geo := geo + 1; end if;
               end if;
               if to_integer(o_b) /= C_B0 then geo := geo + 1; end if;
               if frame = G_DUMP then
                  report "LINE_START " & integer'image(picl) & " r=" & integer'image(to_integer(o_r)) &
                         " g=" & integer'image(lg) & " b=" & integer'image(to_integer(o_b)) severity note;
               end if;
            else
               if to_integer(o_g) /= lg then geo := geo + 1; end if;
               step := (to_integer(o_b) - lb + 256) mod 256;
               if step > 1 then geo := geo + 1; end if;
            end if;
            if to_integer(o_r) /= fr and tear < 0 then tear := picl; end if;
            lb := to_integer(o_b);
            sig := ((sig mod 16777216) * 31 + to_integer(o_g) * 256 + to_integer(o_b)) mod 1073741789;
            px := px + 1;
         end if;
         if de_d = '1' and o_de = '0' then
            if px > 0 and frame = G_DUMP then
               report "LINE " & integer'image(picl) & " r=" & integer'image(fr) & " g=" & integer'image(lg) &
                      " b_last=" & integer'image(lb) & " px=" & integer'image(px) & " tear=" & integer'image(tear)
                  severity note;
            end if;
            if px > 0 then
               if px /= C_PW then geo := geo + 1; end if;
               if lb /= C_BL then geo := geo + 1; end if;
               pg := lg;
               picl := picl + 1;
            end if;
            px := 0;
         end if;

         -- end of an HDMI frame at the rising edge of o_vs
         if vs_d = '0' and o_vs = '1' then
            if frame >= 0 then
               if picl /= C_PH then geo := geo + 1; end if;
               if picl > 0 and pg /= C_GL then geo := geo + 1; end if;
               if frame >= G_CHECK_FROM then
                  checked := checked + 1;
                  if geo_chk then
                     if geo > 0 then err("picture geometry, " & integer'image(geo) & " deviations"); end if;
                     if sig_ref < 0 then sig_ref := sig;
                     elsif sig /= sig_ref then err("picture signature changed"); end if;
                  end if;
                  if frame >= G_SETTLE then
                     if tear >= 0 then
                        tears := tears + 1;
                        err("tear: picture line " & integer'image(tear) & " shows another core frame");
                     end if;
                     if fr_prev >= 0 and (fr - fr_prev + 256) mod 256 /= 1 then
                        steps := steps + 1;
                        err("core frame " & integer'image(fr) & " after " & integer'image(fr_prev));
                     end if;
                     if G_D_STEP >= 0 and frame > G_SETTLE and d_prev >= 0 and abs(d - d_prev) > G_D_STEP and
                        not (G_CROP_FLIP1 >= 0 and frame > G_CROP_FLIP1 and frame <= G_CROP_FLIP1 + 3) and
                        not (G_CROP_FLIP2 >= 0 and frame > G_CROP_FLIP2 and frame <= G_CROP_FLIP2 + 3) then
                        err("d changed by " & integer'image(d - d_prev) & " from the previous frame");
                     end if;
                     if G_D_LO >= 0 and (d < G_D_LO or d > G_D_HI) then
                        err("d = " & integer'image(d) & " outside " & integer'image(G_D_LO) & " .. " &
                            integer'image(G_D_HI));
                     end if;
                  end if;
                  if gl_locked = '1' and lock_frame < 0 then lock_frame := frame; end if;
               end if;
               report "FRAME " & integer'image(frame) & " core_frame=" & integer'image(fr) &
                      " tear_line=" & integer'image(tear) & " picture_lines=" & integer'image(picl) &
                      " lines=" & integer'image(lines_f) & " clocks=" & integer'image(clk_f) &
                      " d=" & integer'image(d) & " stretch=" & integer'image(gl_stretch) &
                      " locked=" & std_logic'image(gl_locked) & " geo=" & integer'image(geo) &
                      " zoom=" & boolean'image(crop_exp) & " geo_checked=" & boolean'image(geo_chk) &
                      " sig=" & integer'image(sig) & " hash=" & integer'image(hsh) &
                      " in_size=" & integer'image(hdmax) & "x" & integer'image(vdmax)
                  severity note;
               if frame >= G_CHECK_FROM then
                  fr_prev := fr;
               end if;
               d_prev := d;
            end if;
            -- zoom-in toggled after this frame: the next two HDMI frames show the old geometry or
            -- the new picture with the old size; geometry and signature count again from the third
            if (G_CROP_FLIP1 >= 0 and frame = G_CROP_FLIP1) or (G_CROP_FLIP2 >= 0 and frame = G_CROP_FLIP2) then
               crop_req <= crop_req + 1;
            end if;
            geo_chk := true;
            if (G_CROP_FLIP1 >= 0 and frame + 1 > G_CROP_FLIP1 and frame + 1 <= G_CROP_FLIP1 + 2) or
               (G_CROP_FLIP2 >= 0 and frame + 1 > G_CROP_FLIP2 and frame + 1 <= G_CROP_FLIP2 + 2) then
               geo_chk := false;
            end if;
            if (G_CROP_FLIP1 >= 0 and frame + 1 = G_CROP_FLIP1 + 3) or
               (G_CROP_FLIP2 >= 0 and frame + 1 = G_CROP_FLIP2 + 3) then
               crop_exp := not crop_exp;
               sig_ref  := -1;
               C_G0 := in_y0(crop_exp) mod 256;
               C_GL := (in_y0(crop_exp) + in_h(crop_exp) - 1) mod 256;
               C_B0 := in_x0(crop_exp) mod 256;
               C_BL := (in_x0(crop_exp) + in_w(crop_exp) - 1) mod 256;
            end if;
            frame := frame + 1;
            clk_f := 0; lines_f := 0; picl := 0; px := 0; tear := -1; geo := 0; sig := 0; fr := -1;
         end if;

         -- the end: after the last frame, and after the Avalon monitor has reported its fetches
         -- (it reports a frame when the fetches of the next one begin)
         if frame >= G_FRAMES and mon_reported >= G_FRAMES and not done then
            report "RESULT frames=" & integer'image(frame) & " checked=" & integer'image(checked) &
                   " tears=" & integer'image(tears) & " bad_steps=" & integer'image(steps) &
                   " sig=" & integer'image(sig_ref) & " hash=" & integer'image(hsh) &
                   " lock_frame=" & integer'image(lock_frame) &
                   " line_min=" & integer'image(shortest) & " line_max=" & integer'image(longest) &
                   " ERRORS=" & integer'image(errors)
               severity note;
            done <= true;
         end if;

         hs_d := o_hs; vs_d := o_vs; de_d := o_de;
      end if;
   end process;

end architecture sim;
