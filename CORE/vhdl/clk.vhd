-------------------------------------------------------------------------------------------------------------
-- Commodore 64 for MEGA65 (C64MEGA65)
--
-- Clock Generator using the Xilinx specific MMCME2_ADV:
--
--   MiSTer's Commodore 64 runs on a single core clock "clk32". The C64 clock is clk32 divided by 32 and
--   the pixel clock enable is clk32 divided by 4 (see main.vhd). MiSTer reconfigures one PLL to switch
--   between PAL and NTSC. We use four MMCMs that run all the time instead, two per standard:
--
--   PAL (VIC-II 6569, 63 cycles x 312 lines x 32 = 628,992 core clock cycles per frame):
--      original      i_clk_c64_orig     31,527,777.778 Hz, C64 985,243 Hz, 50.124291 Hz frame rate
--      flicker-free  i_clk_c64_slow     31,448,992.853 Hz, C64 982,781 Hz, 49.999035 Hz frame rate
--                                       (0.25% slower than the original clock)
--
--   NTSC (VIC-II 6567R8, 65 cycles x 263 lines x 32 = 547,040 core clock cycles per frame):
--      original      i_clk_c64_ntsc     32,727,272.727 Hz, C64 1,022,727 Hz, 59.826105 Hz frame rate
--                                       (exactly 14.31818 MHz x 16 / 7, like a real NTSC C64)
--      flicker-free  i_clk_c64_ntsc_ff  32,789,699.571 Hz, C64 1,024,678 Hz, 59.940223 Hz frame rate
--                                       (0.19% faster than the original clock)
--
--   The MMCM parameters are the output of doc/dev-ntsc/tools/ntsc_clocks.py --final.
--
-- Note about Flicker-Free: The method used here is to seamlessly (i.e. without glitch)
-- switch automatically between two very close clock speeds. The switching is done based
-- on the feedback from the HDMI ascal'er and is done in mega65.vhd. The two clocks of a
-- standard "embrace" the HDMI frame rate of that standard: In PAL the original clock is the
-- faster one and the flicker-free clock is slightly slower than 50 Hz. In NTSC the original
-- clock is the slower one and the flicker-free clock is slightly faster than 59.94 Hz
-- (720x480p59.94 runs at 59.940060 Hz, 1280x720p59.94 at 59.932660 Hz).
--
-- A tree of two levels of glitch-free clock multiplexers (BUFGCTRL) selects one of the four
-- clocks: The first level selects the original or the flicker-free clock of each standard, the
-- second level selects the standard. Since all four MMCMs run continuously, every multiplexer
-- always switches between two running clocks, which is the precondition for glitch-free switching.
-- No MMCM is ever reset or reconfigured at run time.
--
-- However, for PAL there is an alternative method possible, where only a single clock is used and
-- furthermore removes the dependency on the HDMI ascaler. Instead, it uses the "fine
-- phase shift" capability of the MMCM. This makes it possible to dynamically "bend" the
-- clock frequency, but only by a small amount. The calculations are as follows: Starting
-- from the MMCM "i_clk_c64_slow" the actual frequency is 31.44899285 MHz, whereas the
-- desired frequency is 31.449600 MHz.  Since the actual clock is too slow, we need to
-- "insert" extra clock cycles. We do this by occasionally shortening a clock cycle by a
-- small amount.  The number of clock cycles before we "insert" a complete extra clock
-- cycle is: 31.449600 / (31.449600 - 31.44899285) = 51799.  Given the configuration
-- values of the MMCM there is a total of 56*21.375 = 1197 units of "fine phase shift" in
-- each clock cycle.  Therefore, we need to remove one unit of phase shift every
-- 51799/1197 = 43.27 clock cycles.
--
-- An even better alternative is to cascade two MMCM's: To get from 100 MHz to 31.4496 MHz
-- we need a factor of 0.31449600. Written as a fraction that is 4914/15625 = 2*3^3*7*13 / 5^6.
-- We can factor this fraction into two factors: 2*3*13/5^3 = 0.624 and 3^2*7/5^3 = 0.504.
-- These two factors can we implemented as follows:
-- 0.504 : CLKFBOUT_MULT_F = 47.25, DIVCLK_DIVIDE = 5, CLKOUT0_DIVIDE_F = 18.75
-- 0.624 : CLKFBOUT_MULT_F = 19.50, DIVCLK_DIVIDE = 1, CLKOUT0_DIVIDE_F = 31.25
-- Note: It's necessary that the first MMCM is 0.504, to keep f_VCO of the second MMCM
-- within the range of 600 - 1200 MHz.
-- With the above approach we get the exact clock frequency required, and therefore no
-- longer need any dynamic shifting of phase.
--
-- Powered by MiSTer2MEGA65
-- MEGA65 port done by MJoergen and sy2002 in 2023 and licensed under GPL v3
-------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library xpm;
use xpm.vcomponents.all;

entity clk is
   port (
      sys_clk_i       : in  std_logic;   -- expects 100 MHz

      -- switchable clock for the C64 core
      -- Bit 1 selects the standard (0 = PAL, 1 = NTSC), bit 0 selects the flicker-free clock of
      -- that standard:
      --
      -- 00 = PAL original, as close as possible to the C64's original clock:
      --      31,527,777.778 Hz core clock, C64 clock 985,243 Hz, 50.124291 Hz frame rate
      --
      -- 01 = PAL HDMI flicker-free clock that makes sure the C64 can follow the 50 Hz HDMI frame rate:
      --      31,448,992.853 Hz core clock, C64 clock 982,781 Hz, 49.999035 Hz frame rate
      --      This is 99.75% of the original system speed.
      --
      -- 10 = NTSC original, exactly the clock of a real NTSC C64:
      --      32,727,272.727 Hz core clock, C64 clock 1,022,727 Hz, 59.826105 Hz frame rate
      --
      -- 11 = NTSC HDMI flicker-free clock that makes sure the C64 can follow the 59.94 Hz HDMI frame rate:
      --      32,789,699.571 Hz core clock, C64 clock 1,024,678 Hz, 59.940223 Hz frame rate
      --      This is 100.19% of the original system speed.
      core_speed_i      : unsigned(1 downto 0); -- asynchronous

      main_clk_o        : out std_logic;
      main_rst_o        : out std_logic
   );
end entity clk;

architecture rtl of clk is

-- MMCM signals
signal main_fb_mmcm_orig  : std_logic;
signal main_clk_mmcm_orig : std_logic;
signal main_locked_orig   : std_logic;

signal main_fb_mmcm_slow  : std_logic;
signal main_clk_mmcm_slow : std_logic;
signal main_locked_slow   : std_logic;

signal main_fb_mmcm_ntsc     : std_logic;
signal main_clk_mmcm_ntsc    : std_logic;
signal main_locked_ntsc      : std_logic;

signal main_fb_mmcm_ntsc_ff  : std_logic;
signal main_clk_mmcm_ntsc_ff : std_logic;
signal main_locked_ntsc_ff   : std_logic;

-- Outputs of the first level of the glitch-free multiplexer tree (one per standard)
signal main_clk_pal       : std_logic;
signal main_clk_ntsc      : std_logic;

-- Output of the second level of the glitch-free multiplexer tree (selects the standard)
signal main_clk_mmcm      : std_logic;

begin

   ---------------------------------------------------------------------------------------
   -- Generate as-close-as-possible-to-the-original version of the C64 clock
   -- This has a frame rate of 31527777/(312*63*32) = 50.124 Hz
   ---------------------------------------------------------------------------------------

   i_clk_c64_orig : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 6,
         CLKFBOUT_MULT_F      => 56.750,     -- 945.833 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 30.000,     -- 31.5277777778 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => main_fb_mmcm_orig,
         CLKOUT0             => main_clk_mmcm_orig,
         -- Input clock control
         CLKFBIN             => main_fb_mmcm_orig,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked_orig,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_c64_orig

   ---------------------------------------------------------------------------------------
   -- Generate a slightly slower version of the C64 clock
   -- This has a frame rate of 31448993/(312*63*32) = 49.999 Hz
   -- It's important that this rate is slightly *slower* than 50 Hz.
   ---------------------------------------------------------------------------------------

   i_clk_c64_slow : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 9,
         CLKFBOUT_MULT_F      => 60.500,     -- 672.222 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 21.375,     -- 31.448993 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => main_fb_mmcm_slow,
         CLKOUT0             => main_clk_mmcm_slow,
         -- Input clock control
         CLKFBIN             => main_fb_mmcm_slow,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked_slow,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_c64_slow

   ---------------------------------------------------------------------------------------
   -- Generate the NTSC C64 clock: exactly 14.31818 MHz x 16 / 7 = 32.7272727 MHz
   -- This has a frame rate of 32727273/(263*65*32) = 59.826 Hz
   -- Only integer dividers are used here, so there is no fractional-divider jitter.
   ---------------------------------------------------------------------------------------

   i_clk_c64_ntsc : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 5,
         CLKFBOUT_MULT_F      => 36.000,     -- 720.000 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 22.000,     -- 32.727273 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => main_fb_mmcm_ntsc,
         CLKOUT0             => main_clk_mmcm_ntsc,
         -- Input clock control
         CLKFBIN             => main_fb_mmcm_ntsc,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked_ntsc,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_c64_ntsc

   ---------------------------------------------------------------------------------------
   -- Generate a slightly faster version of the NTSC C64 clock
   -- This has a frame rate of 32789700/(263*65*32) = 59.940223 Hz
   -- It's important that this rate is slightly *faster* than both NTSC HDMI frame rates:
   -- 720x480p59.94 runs at 59.940060 Hz and 1280x720p59.94 at 59.932660 Hz.
   -- This is the legal MMCM output closest above 59.940060 Hz (+2.72 ppm).
   ---------------------------------------------------------------------------------------

   i_clk_c64_ntsc_ff : MMCME2_ADV
      generic map (
         BANDWIDTH            => "OPTIMIZED",
         CLKOUT4_CASCADE      => FALSE,
         COMPENSATION         => "ZHOLD",
         STARTUP_WAIT         => FALSE,
         CLKIN1_PERIOD        => 10.0,       -- INPUT @ 100 MHz
         REF_JITTER1          => 0.010,
         DIVCLK_DIVIDE        => 5,
         CLKFBOUT_MULT_F      => 47.750,     -- 955.000 MHz
         CLKFBOUT_PHASE       => 0.000,
         CLKFBOUT_USE_FINE_PS => FALSE,
         CLKOUT0_DIVIDE_F     => 29.125,     -- 32.789700 MHz
         CLKOUT0_PHASE        => 0.000,
         CLKOUT0_DUTY_CYCLE   => 0.500,
         CLKOUT0_USE_FINE_PS  => FALSE
      )
      port map (
         -- Output clocks
         CLKFBOUT            => main_fb_mmcm_ntsc_ff,
         CLKOUT0             => main_clk_mmcm_ntsc_ff,
         -- Input clock control
         CLKFBIN             => main_fb_mmcm_ntsc_ff,
         CLKIN1              => sys_clk_i,
         CLKIN2              => '0',
         -- Tied to always select the primary input clock
         CLKINSEL            => '1',
         -- Ports for dynamic reconfiguration
         DADDR               => (others => '0'),
         DCLK                => '0',
         DEN                 => '0',
         DI                  => (others => '0'),
         DO                  => open,
         DRDY                => open,
         DWE                 => '0',
         -- Ports for dynamic phase shift
         PSCLK               => '0',
         PSEN                => '0',
         PSINCDEC            => '0',
         PSDONE              => open,
         -- Other control and status signals
         LOCKED              => main_locked_ntsc_ff,
         CLKINSTOPPED        => open,
         CLKFBSTOPPED        => open,
         PWRDWN              => '0',
         RST                 => '0'
      ); -- i_clk_c64_ntsc_ff

   -------------------------------------------------------------------------------------
   -- Glitch-free multiplexer tree
   --
   -- First level: select the original (s=0) or the flicker-free clock (s=1) of each standard.
   -- Second level: select the standard: PAL (s=0) or NTSC (s=1).
   -- The select signals are treated asynchronously to the input clocks. All four MMCMs run
   -- continuously, so each BUFGCTRL always switches between two running clocks.
   -------------------------------------------------------------------------------------

   bufgmux_pal_inst : bufgmux_ctrl
      port map (
         i0 => main_clk_mmcm_orig,     -- 1-bit input: clock input (s=0)
         i1 => main_clk_mmcm_slow,     -- 1-bit input: clock input (s=1)
         s  => core_speed_i(0),        -- 1-bit input: clock select
         o  => main_clk_pal            -- 1-bit output: clock output
      );

   bufgmux_ntsc_inst : bufgmux_ctrl
      port map (
         i0 => main_clk_mmcm_ntsc,     -- 1-bit input: clock input (s=0)
         i1 => main_clk_mmcm_ntsc_ff,  -- 1-bit input: clock input (s=1)
         s  => core_speed_i(0),        -- 1-bit input: clock select
         o  => main_clk_ntsc           -- 1-bit output: clock output
      );

   bufgmux_mode_inst : bufgmux_ctrl
      port map (
         i0 => main_clk_pal,           -- 1-bit input: clock input (s=0)
         i1 => main_clk_ntsc,          -- 1-bit input: clock input (s=1)
         s  => core_speed_i(1),        -- 1-bit input: clock select
         o  => main_clk_mmcm           -- 1-bit output: clock output
      );

   -------------------------------------------------------------------------------------
   -- Output buffering
   -------------------------------------------------------------------------------------

   main_clk_bufg : BUFG
      port map (
         I => main_clk_mmcm,
         O => main_clk_o
      );

   -------------------------------------
   -- Reset generation
   -------------------------------------

   i_xpm_cdc_async_rst_main : xpm_cdc_async_rst
      generic map (
         RST_ACTIVE_HIGH => 1,
         DEST_SYNC_FF    => 6
      )
      port map (
         src_arst  => not (main_locked_orig and main_locked_slow and           -- 1-bit input: Source reset signal.
                           main_locked_ntsc and main_locked_ntsc_ff),
         dest_clk  => main_clk_o,       -- 1-bit input: Destination clock.
         dest_arst => main_rst_o        -- 1-bit output: src_arst synchronized to the destination clock domain.
                                        -- This output is registered.
      );

end architecture rtl;

