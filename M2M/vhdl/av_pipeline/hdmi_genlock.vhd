----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- HDMI genlock for the raw modes (GitHub issues #184 and #148)
--
-- In the raw HDMI modes the core runs on its original clock and the HDMI side
-- runs at the core's frame rate (doc/dev-hdmi-raw/SPEC.md, sections 2 and 5).
-- The scaler (ascal) uses a single frame buffer: the HDMI side reads the picture
-- while the core writes it, so the HDMI picture has to start a little behind the
-- core's picture (at the distance target_i, or later within a band), and the two
-- frame rates have to be equal on average. This entity provides both. It lives in the HDMI clock domain and
-- controls only the line length (htotal) that the scaler gets: it makes up to 16
-- lines of the vertical back porch longer than the nominal htotal_i. Every other
-- line, and every line that carries picture, has the nominal length.
--
-- 1. Distance: a counter counts the clock cycles since the last ref_i (the core
--    starts a picture); it is 1 in the clock cycle after ref_i and saturates at
--    2**22 - 1 (no overflow while the reference is missing). The first rising
--    edge of de_i after a falling edge of vs_i is the start of the HDMI picture;
--    the counter value in that clock cycle is the distance d: the number of
--    clock cycles from the cycle with ref_i = '1' to the cycle in which the edge
--    of de_i is seen. A ref_i in the same cycle as that edge belongs to the next
--    measurement (d is the distance to the previous one), so d is 1 to the
--    length of a core frame. A falling edge of vs_i in the same cycle as a
--    rising edge of de_i arms the measurement for the next edge of de_i.
--    A measurement is valid only if a ref_i came since the previous measurement
--    (or since rst_i or enable_i = '0') and the counter is not saturated;
--    without a new reference the counter holds the distance to an older one.
--
-- 2. Decision, once per frame at the measurement (SPEC section 5.3), the stretch
--    k for the vertical blanking that follows, with band = target_i +
--    target_i / 4 (2.5 ms for the target of 2.0 ms):
--       measurement not valid                the stretch stays while locked, else 0
--       d <= target_i                        k = min(target_i - d, 4080)
--       target_i < d < target_i + band       k = 0
--       otherwise                            k = 4080
--    A frame without stretch is shorter than the core's frame by the surplus of
--    the mode (196.97 or 462.92 clock cycles in 720p, 0 in 576p and 480p), so d
--    falls by the surplus per frame and rises by k. From
--    target_i - 4080 <= d <= target_i the next d is target_i minus the surplus,
--    within the one clock cycle of uncertainty of the crossing of the
--    reference: in 720p k then takes the integers around the surplus, in 576p
--    and 480p k becomes 0 and the timing is static. Further below, d rises by
--    4080 minus the surplus per frame until it is in this range. Inside the band
--    nothing is stretched: in 720p d glides down to target_i by the surplus per
--    frame, in 576p and 480p it stays. Above the band the HDMI picture start
--    falls behind by 4080 minus the surplus per frame until it comes round the
--    frame to the target from below.
--    A measurement that is not valid while the genlock is locked keeps the
--    stretch of the previous frame, so that the HDMI frame keeps its length
--    while the core is paused or a reference is missing (a flywheel); while not
--    locked it gives the stretch 0.
--
-- 3. Stretch lines: the 16 lines that begin with the first rising edge of hs_i
--    at or after a falling edge of vs_i (with the scaler both edges come in the
--    same clock cycle, in the line vsend). Of a stretch k the first k mod 16 of
--    these lines get k / 16 + 1 extra clock cycles, the others k / 16. The extra
--    length of a line is set in the clock cycle in which the rising edge of hs_i
--    is seen and stays until the next one, so htotal_o is stable around the end
--    of every line (the outputs of the scaler are 11 clock cycles behind its
--    counters, and it ends a line more than 100 cycles after the start of its
--    hsync). htotal_o is htotal_i + extra, at most 4095; with enable_i = '0' it
--    is htotal_i in every clock cycle. While htotal_i is constant, a line is
--    therefore never shorter than htotal_i and at most 255 cycles longer. The
--    stretch of a frame comes from the measurement at its own picture start (or
--    from the previous frame, see above); stretch_o shows it (0 while
--    enable_i = '0').
--
-- 4. Lock: locked_o is '1' after 8 valid measurements with
--    target_i - 1024 <= d < target_i + band and no valid measurement outside
--    this window in between, and '0' after a valid measurement outside this
--    window, after rst_i and while enable_i = '0'. A measurement that is not
--    valid leaves the lock counter as it is.
--
-- rst_i (synchronous) and enable_i = '0' clear all state: no new reference,
-- stretch 0, no extra length, not locked, no armed measurement. Clearing the
-- extra length in the middle of a stretch line ends that line early, but never
-- before htotal_i. The edge detectors of hs_i, vs_i and de_i keep running. A
-- single clock cycle with enable_i = '1' between cycles with enable_i = '0'
-- leaves nothing behind: in that cycle the stretch and the extra length are 0,
-- and the next cycle clears what it may have set.
--
-- Limits: htotal_i and target_i may change at any time; a new target_i counts
-- from the next measurement, a new htotal_i at once (htotal_o follows it in
-- every clock cycle). The genlock knows nothing about the mode: the control law
-- assumes that target_i + band is well below the length of a core frame (with
-- the 2.0 ms of the specification the band ends at 4.5 ms). Without rising
-- edges of hs_i there is no stretch, without falling edges of vs_i or rising
-- edges of de_i no measurement (the stretch of the last frame stays). The
-- stretch only lengthens frames, so a picture start that lies beyond the band
-- has to come round the whole frame (SPEC section 5.3, at most 6.8 s in PAL
-- 720p).
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_genlock is
   port (
      clk_i       : in  std_logic;                      -- HDMI pixel clock
      rst_i       : in  std_logic;
      enable_i    : in  std_logic;                      -- '1' in the raw modes
      htotal_i    : in  natural range 0 to 4095;        -- nominal number of pixel clocks per line
      target_i    : in  natural range 0 to 2**21 - 1;   -- wanted distance in pixel clocks, see 5.3
      hs_i        : in  std_logic;                      -- hsync of the scaler, high active
      vs_i        : in  std_logic;                      -- vsync of the scaler, high active
      de_i        : in  std_logic;                      -- data enable of the scaler
      ref_i       : in  std_logic;                      -- one clock cycle high: the core starts a picture (clk_i domain)
      htotal_o    : out natural range 0 to 4095;        -- line length for the scaler
      locked_o    : out std_logic;
      stretch_o   : out natural range 0 to 4095         -- extra pixel clocks of the current frame (for benches)
   );
end entity hdmi_genlock;

architecture synthesis of hdmi_genlock is

   constant C_CNT_MAX     : natural := 2**22 - 1;   -- saturation of the distance counter
   constant C_K_MAX       : natural := 4080;        -- largest stretch of a frame: 16 lines of 255
   constant C_LOCK_BELOW  : natural := 1024;        -- lock window: target_i - C_LOCK_BELOW <= d < target_i + band
   constant C_LOCK_FRAMES : natural := 8;           -- measurements in the window before locked_o
   constant C_LINES       : natural := 16;          -- stretch lines per frame
   constant C_HTOTAL_MAX  : natural := 4095;

   -- edge detectors
   signal hs_d     : std_logic;
   signal vs_d     : std_logic;
   signal de_d     : std_logic;

   -- measurement and decision
   signal cnt      : natural range 0 to C_CNT_MAX;  -- clock cycles since ref_i
   signal ref_new  : std_logic;                     -- a ref_i came since the last measurement
   signal armed    : std_logic;                     -- vs_i fell: the next rising edge of de_i is the picture start
   signal stretch  : natural range 0 to C_K_MAX;    -- stretch k of the current frame
   signal good     : natural range 0 to C_LOCK_FRAMES;

   -- stretch lines
   signal vs_pend  : std_logic;                     -- vs_i fell: the next rising edge of hs_i starts the stretch lines
   signal line_idx : natural range 0 to C_LINES;    -- 0 to 15: index of the current stretch line, C_LINES: none
   signal extra    : natural range 0 to 255;        -- extra clock cycles of the current line

begin

   htotal_o  <= htotal_i                 when enable_i = '0' else
                C_HTOTAL_MAX             when htotal_i + extra > C_HTOTAL_MAX else
                htotal_i + extra;
   locked_o  <= '1' when enable_i = '1' and good = C_LOCK_FRAMES else '0';
   stretch_o <= stretch when enable_i = '1' else 0;

   genlock_proc : process (clk_i)
      variable vs_fall : boolean;
      variable valid   : boolean;
      variable d       : natural range 0 to C_CNT_MAX;
      variable band    : natural range 0 to 2**22;     -- target_i < d < target_i + band: no stretch
      variable idx     : natural range 0 to C_LINES;
   begin
      if rising_edge(clk_i) then
         hs_d    <= hs_i;
         vs_d    <= vs_i;
         de_d    <= de_i;
         vs_fall := vs_i = '0' and vs_d = '1';

         -- distance counter
         if ref_i = '1' then
            cnt     <= 1;
            ref_new <= '1';
         elsif cnt /= C_CNT_MAX then
            cnt <= cnt + 1;
         end if;

         -- measurement at the start of the HDMI picture and the decision
         if vs_fall then
            armed <= '1';
         elsif de_i = '1' and de_d = '0' and armed = '1' then
            armed   <= '0';
            ref_new <= ref_i;               -- a ref_i in this cycle belongs to the next measurement
            d       := cnt;
            valid   := ref_new = '1' and d /= C_CNT_MAX;
            band    := target_i + target_i / 4;
            if not valid then
               if good /= C_LOCK_FRAMES then
                  stretch <= 0;             -- while locked the stretch of the last frame stays
               end if;
            elsif d <= target_i then
               if target_i - d > C_K_MAX then
                  stretch <= C_K_MAX;
               else
                  stretch <= target_i - d;
               end if;
            elsif d < target_i + band then
               stretch <= 0;
            else
               stretch <= C_K_MAX;
            end if;

            -- a measurement that is not valid leaves the lock counter alone
            if valid then
               if d + C_LOCK_BELOW >= target_i and d < target_i + band then
                  if good /= C_LOCK_FRAMES then
                     good <= good + 1;
                  end if;
               else
                  good <= 0;
               end if;
            end if;
         end if;

         -- stretch lines: the extra length of a line is set when its hsync begins
         if hs_i = '1' and hs_d = '0' then
            if vs_pend = '1' or vs_fall then
               idx := 0;
            elsif line_idx /= C_LINES then
               idx := line_idx + 1;
            else
               idx := C_LINES;
            end if;
            vs_pend  <= '0';
            line_idx <= idx;
            if idx = C_LINES then
               extra <= 0;
            elsif idx < stretch mod C_LINES then
               extra <= stretch / C_LINES + 1;
            else
               extra <= stretch / C_LINES;
            end if;
         elsif vs_fall then
            vs_pend <= '1';
         end if;

         if rst_i = '1' or enable_i = '0' then
            cnt      <= C_CNT_MAX;
            ref_new  <= '0';
            armed    <= '0';
            stretch  <= 0;
            good     <= 0;
            vs_pend  <= '0';
            line_idx <= C_LINES;
            extra    <= 0;
         end if;
      end if;
   end process genlock_proc;

end architecture synthesis;
