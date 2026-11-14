----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- Amiga mouse as a Commodore 1351 in proportional mode (GitHub issue #190)
--
-- One instance per joystick socket, in the clock domain of the core, fed by the raw
-- pins of the socket. An Amiga mouse puts two quadrature signals per axis on the
-- four direction lines: X is the pair (HQ, H) = (right, down) = (pin 4, pin 2),
-- Y is the pair (VQ, V) = (left, up) = (pin 3, pin 1). This entity counts them
-- and presents the position as the two POT values of a 1351, so that every C64
-- program with a 1351 driver works with the mouse. The left button is the fire
-- line and does not pass this entity; the right and the middle button are
-- switches to ground on the paddle pins 9 and 5 and are derived from the
-- measured paddle values (only a mouse with pull-up resistors on these pins can
-- report them).
--
-- 1. Synchronizer and glitch filter: each line passes two flip-flops and then a
--    filter that takes over the synchronized value once it has differed from the
--    filtered value for more than C_FILTER_CYCLES clock cycles in a row. All four
--    lines have the same delay, so the order of the edges is kept. The
--    comparator outputs of the mouse are open collector and the buffer on the
--    board has no Schmitt trigger: the filter removes the chatter of slow edges
--    and short spikes. The shortest legitimate stable time of a line is about
--    25 us (1000 counts per inch at 2 m/s).
--
-- 2. Decoder: every edge counts, four counts per cycle of a pair, like the
--    counters of the Amiga's Denise. X counts +1 for the sequence 11, 10, 00, 01
--    of (right, down) (mouse moves to the right), Y counts +1 for the sequence
--    11, 01, 00, 10 of (left, up) (mouse moves up, away from the user); the
--    reverse sequences count -1. A change of both lines of a pair in the same
--    clock cycle counts nothing, and the decoder continues from the new state.
--
-- 3. Backlog and rate limiter: a 1351 driver computes the movement since its
--    last call as the difference of two POT values modulo 128 and takes 64 to
--    127 as negative, so more than 62 counts between two calls can move the
--    pointer in the wrong direction. The counts of an axis therefore go into a
--    backlog (-G_BACKLOG to +G_BACKLOG; a count that would exceed it is
--    dropped), and a free-running tick every C_STEP_CYCLES clock cycles moves
--    one count from the backlog into the position. The position changes by at
--    most 50 counts in a PAL frame and 44 in an NTSC frame (whose core clock is
--    faster, see below), which leaves a driver that is called once per frame a
--    margin of 12 counts or about 5 ms of delay of its call. While the average
--    count rate stays below one per tick, the backlog stays small: at 2400
--    counts per second and a phase of 60 to 120 degrees between the two lines of
--    a pair it holds at most two counts, and a count reaches the position within
--    0.53 ms (0.41 ms at 90 degrees). After a fast movement the position moves
--    on for at most G_BACKLOG ticks (51 ms).
--
-- 4. Position as POT values: a 7-bit counter per axis that wraps around and
--    starts at 0. The POT value carries its full units only, like a real 1351,
--    whose position sits in bits 6 to 1: pot(7) = position(6),
--    pot(6) = not position(6), pot(5 downto 1) = position(5 downto 1),
--    pot(0) = '0', that is 64 + position with bit 0 cleared, values $40 to $BE.
--    Two counts of the mouse are one position unit of a 1351 driver. The drivers
--    (1351 manual, cc65, GEOS) take over a new value as soon as the difference is
--    one unit and drop the LSB of an odd difference, so a value with half units
--    would make them lose (and, for negative differences, invent) half units.
--
-- 5. Right button (meas_x_i, pin 9) and middle button (meas_y_i, pin 5), each
--    with its own instance of the same logic: a value below 128 means that a
--    pull-up exists and the button is released, and sets the flag "pull-up
--    seen"; a value of 192 or more means that nothing pulls the pin up, which is
--    a pressed button if the flag is set and a mouse without pull-ups if not;
--    values from 128 to 191 change nothing. A change of the reported state needs
--    its condition to hold for C_CONFIRM_TICKS ticks without interruption. A
--    button that is reported as pressed for C_STUCK_TICKS ticks is released and
--    the flag is cleared (a mouse with pull-ups exchanged for one without while
--    the setting stays "Amiga"); the next value below 128 sets it again.
--
-- While enable_i is '0' nothing is counted, the backlog is empty, the position
-- keeps its value, the buttons are released and their flags are cleared.
-- Synchronizers, filters and the decoder state keep following the lines, so
-- that no count is produced at the moment enable_i turns '1'.
--
-- The numbers for G_CLK_FREQ = 31,527,778 Hz (the PAL core clock) and the default
-- generics, in clock cycles and real time:
--    filter     C_FILTER_CYCLES =     63 cycles = 1.998 us: a pulse at a pin of at
--               most 63 clock periods never passes, a level that holds for 64
--               periods (2.030 us) always does
--    step tick  C_STEP_CYCLES   = 12,610 cycles = 399.96 us (2500.2 steps per second)
--    confirm    C_CONFIRM_TICKS =     10 ticks: the condition has to hold for 10 to
--               11 ticks (4.00 to 4.40 ms), because the first tick comes at any time
--               within one tick after the condition starts
--    stuck      C_STUCK_TICKS   = 75,000 ticks = 29.997 s: a press always starts at
--               a tick, so this time is exact to the clock cycle
-- In NTSC mode the core clock is 32,727,273 Hz (3.8 % faster) while G_CLK_FREQ
-- stays at the PAL value: all of these times are 3.7 % shorter.
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity amiga_mouse is
   generic (
      G_CLK_FREQ    : natural;             -- frequency of clk_i in Hz
      G_FILTER_NS   : natural := 2000;     -- a line needs to be stable for this time before a change counts
      G_STEP_US     : natural := 400;      -- shortest time between two steps of the reported position
      G_BACKLOG     : natural := 127;      -- counts that may wait for the rate limiter; further ones are dropped
      G_CONFIRM_US  : natural := 4000;     -- a button on a paddle pin needs to be stable for this time
      G_STUCK_MS    : natural := 30000     -- a button on a paddle pin that is pressed for longer is released
   );
   port (
      clk_i          : in  std_logic;
      enable_i       : in  std_logic;                      -- '1': this socket has an Amiga mouse

      -- the lines of the socket, low active, asynchronous
      up_n_i         : in  std_logic;                      -- pin 1: V
      down_n_i       : in  std_logic;                      -- pin 2: H
      left_n_i       : in  std_logic;                      -- pin 3: VQ
      right_n_i      : in  std_logic;                      -- pin 4: HQ

      -- measured values of the paddle pins of the socket (true values, clk_i domain)
      meas_x_i       : in  std_logic_vector(7 downto 0);   -- pin 9: right button
      meas_y_i       : in  std_logic_vector(7 downto 0);   -- pin 5: middle button

      -- what a 1351 in proportional mode would deliver
      pot_x_o        : out std_logic_vector(7 downto 0);
      pot_y_o        : out std_logic_vector(7 downto 0);
      right_btn_n_o  : out std_logic;                      -- low active
      middle_btn_n_o : out std_logic                       -- low active
   );
end entity amiga_mouse;

architecture synthesis of amiga_mouse is

   function at_least_one(n : integer) return positive is
   begin
      if n < 1 then
         return 1;
      end if;
      return n;
   end function at_least_one;

   -- Derived counts; every intermediate product stays far below 2**31 for clock
   -- frequencies up to 2 GHz and the ranges of the generics that make sense
   constant C_STEP_US       : positive := at_least_one(G_STEP_US);
   constant C_FILTER_CYCLES : positive := at_least_one((G_CLK_FREQ / 1000) * G_FILTER_NS / 1_000_000);
   constant C_STEP_CYCLES   : positive := at_least_one((G_CLK_FREQ / 1000) * G_STEP_US / 1000);
   constant C_CONFIRM_TICKS : positive := at_least_one(G_CONFIRM_US / C_STEP_US);
   constant C_STUCK_TICKS   : positive := at_least_one((G_STUCK_MS / C_STEP_US) * 1000 +
                                                       (G_STUCK_MS mod C_STEP_US) * 1000 / C_STEP_US);

   -- index of the lines in the vectors below
   constant C_UP    : natural := 0;    -- pin 1: V
   constant C_DOWN  : natural := 1;    -- pin 2: H
   constant C_LEFT  : natural := 2;    -- pin 3: VQ
   constant C_RIGHT : natural := 3;    -- pin 4: HQ

   -- Count of a change of the pair (a, b) from (a_old, b_old): +1 for each step of
   -- the sequence 11, 10, 00, 01, 11 of (a, b), -1 for each step of the reverse
   -- sequence, 0 if nothing or both lines changed. X is (a, b) = (right, down);
   -- Y is (a, b) = (up, left), because its sequence 11, 01, 00, 10 of (left, up)
   -- is this sequence with the two lines exchanged.
   function quad_count(a_old, b_old, a, b : std_logic) return integer is
   begin
      if a = a_old and b /= b_old then       -- b changed: 11 -> 10 and 00 -> 01 count +1
         if b /= a then
            return 1;
         else
            return -1;
         end if;
      elsif a /= a_old and b = b_old then    -- a changed: 10 -> 00 and 01 -> 11 count +1
         if a = b then
            return 1;
         else
            return -1;
         end if;
      end if;
      return 0;
   end function quad_count;

   -- The POT value of a position: its full units, presented as 64 + position with bit 0 cleared
   function pot_of(p : unsigned(6 downto 0)) return std_logic_vector is
   begin
      return p(6) & not p(6) & std_logic_vector(p(5 downto 1)) & '0';
   end function pot_of;

   -- synchronizer, filter and decoder state; the lines idle high
   signal lines_d     : std_logic_vector(3 downto 0) := (others => '1');
   signal lines_dd    : std_logic_vector(3 downto 0) := (others => '1');
   signal lines_flt   : std_logic_vector(3 downto 0) := (others => '1');
   signal lines_old   : std_logic_vector(3 downto 0) := (others => '1');

   attribute async_reg             : string;
   attribute async_reg of lines_d  : signal is "true";
   attribute async_reg of lines_dd : signal is "true";

   type filter_cnt_t is array (0 to 3) of natural range 0 to C_FILTER_CYCLES;
   signal filter_cnt  : filter_cnt_t := (others => 0);

   -- step tick of the rate limiter, also the time base of the button timers
   signal tick_cnt    : natural range 0 to C_STEP_CYCLES - 1 := 0;
   signal tick        : std_logic := '0';

   -- per axis: 0 is X, 1 is Y
   type backlog_t  is array (0 to 1) of integer range -G_BACKLOG to G_BACKLOG;
   type position_t is array (0 to 1) of unsigned(6 downto 0);
   type pot_t      is array (0 to 1) of std_logic_vector(7 downto 0);
   signal backlog     : backlog_t  := (others => 0);
   signal position    : position_t := (others => (others => '0'));
   signal pot         : pot_t      := (others => x"40");

   -- per button: 0 is the right button (meas_x_i), 1 is the middle button (meas_y_i)
   type meas_t is array (0 to 1) of std_logic_vector(7 downto 0);
   signal meas        : meas_t;
   signal btn_n       : std_logic_vector(1 downto 0) := "11";

begin

   pot_x_o        <= pot(0);
   pot_y_o        <= pot(1);
   right_btn_n_o  <= btn_n(0);
   middle_btn_n_o <= btn_n(1);

   meas(0)        <= meas_x_i;
   meas(1)        <= meas_y_i;

   filter_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         lines_d  <= right_n_i & left_n_i & down_n_i & up_n_i;
         lines_dd <= lines_d;

         for i in 0 to 3 loop
            if lines_dd(i) = lines_flt(i) then
               filter_cnt(i) <= 0;
            elsif filter_cnt(i) = C_FILTER_CYCLES then
               lines_flt(i)  <= lines_dd(i);
               filter_cnt(i) <= 0;
            else
               filter_cnt(i) <= filter_cnt(i) + 1;
            end if;
         end loop;

         lines_old <= lines_flt;
      end if;
   end process filter_proc;

   tick_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if tick_cnt = C_STEP_CYCLES - 1 then
            tick_cnt <= 0;
            tick     <= '1';
         else
            tick_cnt <= tick_cnt + 1;
            tick     <= '0';
         end if;
      end if;
   end process tick_proc;

   -- Decoder, backlog and rate limiter. A count of the decoder and a step of the
   -- rate limiter in the same clock cycle both take effect; the bound applies to
   -- the result of both.
   position_proc : process (clk_i)
      variable count   : integer range -1 to 1;
      variable step    : integer range -1 to 1;
      variable pending : integer range -G_BACKLOG - 2 to G_BACKLOG + 2;
      variable pos     : unsigned(6 downto 0);
   begin
      if rising_edge(clk_i) then
         for axis in 0 to 1 loop
            if axis = 0 then
               count := quad_count(lines_old(C_RIGHT), lines_old(C_DOWN), lines_flt(C_RIGHT), lines_flt(C_DOWN));
            else
               count := quad_count(lines_old(C_UP), lines_old(C_LEFT), lines_flt(C_UP), lines_flt(C_LEFT));
            end if;

            step := 0;
            if tick = '1' then
               if backlog(axis) > 0 then
                  step := 1;
               elsif backlog(axis) < 0 then
                  step := -1;
               end if;
            end if;

            pending := backlog(axis) - step + count;
            if pending > G_BACKLOG or pending < -G_BACKLOG then
               pending := backlog(axis) - step;                      -- the count is dropped
            end if;

            if enable_i = '0' then
               pending := 0;
               step    := 0;
            end if;

            pos := position(axis);
            if step > 0 then
               pos := pos + 1;
            elsif step < 0 then
               pos := pos - 1;
            end if;

            backlog(axis)  <= pending;
            position(axis) <= pos;
            pot(axis)      <= pot_of(pos);
         end loop;
      end if;
   end process position_proc;

   gen_buttons : for i in 0 to 1 generate
      signal pullup_seen : std_logic := '0';
      signal confirm_cnt : natural range 0 to C_CONFIRM_TICKS   := 0;
      signal stuck_cnt   : natural range 0 to C_STUCK_TICKS - 1 := 0;
   begin

      button_proc : process (clk_i)
         variable released : boolean;     -- below 128: a pull-up exists, the button is released
         variable open_pin : boolean;     -- 192 or more: nothing pulls the pin up
         variable change   : boolean;     -- the condition for a change of the reported state
      begin
         if rising_edge(clk_i) then
            released := meas(i)(7) = '0';
            open_pin := meas(i)(7 downto 6) = "11";
            if btn_n(i) = '1' then
               change := open_pin and pullup_seen = '1';
            else
               change := released;
            end if;

            -- a change needs its condition for C_CONFIRM_TICKS full ticks
            if not change then
               confirm_cnt <= 0;
            elsif tick = '1' then
               if confirm_cnt = C_CONFIRM_TICKS then
                  btn_n(i)    <= not btn_n(i);
                  confirm_cnt <= 0;
               else
                  confirm_cnt <= confirm_cnt + 1;
               end if;
            end if;

            -- a press that lasts C_STUCK_TICKS ticks is released and the flag is cleared
            if btn_n(i) = '1' then
               stuck_cnt <= 0;
            elsif tick = '1' then
               if stuck_cnt = C_STUCK_TICKS - 1 then
                  btn_n(i)    <= '1';
                  pullup_seen <= '0';
                  confirm_cnt <= 0;
                  stuck_cnt   <= 0;
               else
                  stuck_cnt   <= stuck_cnt + 1;
               end if;
            end if;

            if released then
               pullup_seen <= '1';
            end if;

            if enable_i = '0' then
               btn_n(i)    <= '1';
               pullup_seen <= '0';
               confirm_cnt <= 0;
               stuck_cnt   <= 0;
            end if;
         end if;
      end process button_proc;

   end generate gen_buttons;

end architecture synthesis;
