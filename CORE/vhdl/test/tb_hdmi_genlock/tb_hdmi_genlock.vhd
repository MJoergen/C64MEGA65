----------------------------------------------------------------------------------
-- Genlock bench (GitHub issue #184): hdmi_genlock in one raw mode, see README.md
--
-- Many instances of hdmi_genlock run side by side on the pixel clock of the mode
-- G_MODE, each with its own model of the scaler's output timing
-- (tb_ascal_timing_pkg.scaler_step, fed by the htotal_o of its instance) and its
-- own core reference. The core reference of an instance is a level that rises
-- once per core frame (exact period core_n / core_d pixel clocks) and falls 7/8
-- of a frame later, at times computed in femtoseconds; in the pixel clock domain
-- it passes two flip-flops, and a third flip-flop forms the one-cycle pulse
-- ref_i from its rising edge. A change of the level less than C_APERTURE before
-- a clock edge is taken over at that edge or at the next one, at random: this is
-- the one-cycle uncertainty of the real crossing.
--
-- Each instance starts in reset; the reset ends right after the first falling
-- edge of vsync, so that the first measurement is the picture start of the
-- second frame, and its reference is placed so that this first measurement is
-- the distance d0 of the instance. A start instance then runs until it is
-- locked and has been locked for its number of frames; a disturbance instance
-- (start at target_i - 2000) executes its list of disturbances, each after the
-- previous one (when it is locked again, if the list says so).
--
-- One process does everything that happens at a clock edge (clock, scaler
-- models, references, checks), so that the simulator wakes only this process
-- and the instances at each edge; an instance that is done gets no further
-- clock edges. The bench reads the outputs of the instances in the delta cycle
-- of the edge (the values before the edge) and drives their inputs in the next
-- delta cycle, as registers do.
--
-- The bench steps an instance (procedure step) only at the edges at which
-- something can change: one of its outputs changed, an input changed at one of
-- the last three edges, the horizontal counter of its scaler reaches a
-- threshold of the enable or sync conditions (hdisp, hsstart, hsend) or the end
-- of the line, the conditions for the next edge differ from stage 0 of the delay
-- lines, a delay line or a port has not settled, the reference level changes or
-- is in the synchronizer, or a disturbance acts. At the other edges only the
-- horizontal counter advances, which step catches up. Between two steps the
-- inputs and outputs of the instance are constant, so a check of the outputs
-- that holds at a step holds at every edge until the next one. G_XCHECK steps a
-- second copy of each scaler model at every edge and compares it with the
-- stepped one at every edge (ports, counters, line ends).
--
-- Checks at every edge: htotal_i <= htotal_o <= htotal_i + 256; with
-- enable_i = '0' htotal_o = htotal_i, locked_o = '0', stretch_o = 0; after a
-- clock edge with rst_i = '1' htotal_o = htotal_i; htotal_o changes only after
-- a rising edge of hs_i, after rst_i or with htotal_i or enable_i;
-- stretch_o and locked_o equal those of a model of SPEC section 5.3 (the
-- counter, a new ref_i since the last measurement, the measurement at the first
-- rising edge of de_i after a falling edge of vs_i, the table of the stretch, the
-- lock rule).
-- Checks at every line end: the line is exactly htotal_i long, except the
-- lines vsend to vsend + 15, which carry the stretch k of the frame as in SPEC
-- section 5.2; a line during which rst_i, enable_i or htotal_i changed is only
-- checked against the range.
-- Checks at every valid measurement: the step of d from frame to frame is the
-- one of the control law (d + k - surplus, modulo a core frame, within the
-- uncertainty of the crossing); after lock d stays in the lock window; in 720p
-- after the arrival |d - (target_i - surplus)| and |k - surplus| stay below the
-- uncertainty, in 576p and 480p k is 0 (at most one frame with k = 1 when the
-- reference sits in the aperture). Every lock comes within the bound of SPEC
-- section 5.3; an instance marked keep (references missing at an unchanged
-- phase) stays locked, and after a single missing reference d is within twice
-- the uncertainty of target_i - surplus; the sum of the HDMI frame lengths over
-- G_LOCKED - 11 locked frames differs from the same number of core frames by
-- less than 1 + C_APERTURE / P pixel clocks.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;
use std.env.all;

use work.tb_ascal_timing_pkg.all;
use work.tb_hdmi_genlock_pkg.all;

entity tb_hdmi_genlock is
   generic (
      G_MODE     : natural  := 0;       -- 0 PAL 720p, 1 PAL 576p, 2 NTSC 720p, 3 NTSC 480p
      G_SET      : string   := "all";   -- "starts", "disturb", "all" or "near" (the quick set, see make_descs)
      G_LOCKED   : natural  := 311;     -- frames that the long start instances run after lock
      G_SEED     : positive := 1;
      G_FAILFAST : boolean  := false;   -- stop at the first error (mutants)
      G_FRAMES   : natural  := 0;       -- > 0: stop after so many frames (cross-check)
      G_XCHECK   : boolean  := false    -- compare the stepped scaler with one that is stepped at every edge
   );
end entity tb_hdmi_genlock;

architecture sim of tb_hdmi_genlock is

   constant M          : mode_t   := C_MODES(G_MODE);
   constant MT         : scaler_timing_t := timing_of(M);
   constant P          : time     := M.period;
   constant TF         : time     := M.core_n * (P / M.core_d);   -- a core frame, exact in fs
   constant TF_HI      : time     := (TF / 8) * 7;                -- high time of the reference level
   constant C_APERTURE : time     := 500 ps;
   constant TGT        : natural  := 2 * M.clk_khz;               -- target_i
   constant TC         : real     := real(M.core_n) / real(M.core_d);
   constant TCI        : natural  := M.core_n / M.core_d;         -- core frame, whole pixel clocks
   constant TH         : natural  := M.htotal * M.vtotal;
   constant SUR        : real     := TC - real(TH);               -- surplus per frame
   constant TOL        : real     := 1.0 + real(C_APERTURE / 1 fs) / real(P / 1 fs);
   constant BOUND      : natural  := integer(floor(real(M.bound_s) * M.rate));
   constant CMAX       : natural  := 2**22 - 1;
   constant EXACT      : boolean  := M.core_d = 1 and M.core_n = TH;
   constant D_SS       : integer  := TGT - integer(round(SUR));   -- d in the steady state
   constant BAND       : natural  := TGT + TGT / 4;               -- no stretch for TGT < d < TGT + BAND

   ------------------------------------------------------------------------------
   -- the instances
   ------------------------------------------------------------------------------
   type op_kind_t is (OP_NONE, OP_STOP, OP_JUMP, OP_EN, OP_RST, OP_HTOT, OP_TARGET, OP_PULSE);
   -- An op becomes due gap frames after the previous op (or after the start) and,
   -- if lock is set, once the instance has been locked for 3 frames; it acts
   -- delay clock cycles after the start of the next line number line.
   --    OP_STOP   a reference pulses are missing, the following ones come b clock cycles later
   --    OP_JUMP   the reference moves a clock cycles later (negative: earlier)
   --    OP_EN     enable_i := a
   --    OP_RST    rst_i = '1' for a clock cycles
   --    OP_HTOT   htotal_i := a (0: the htotal of the mode)
   --    OP_TARGET target_i := target_i + a
   --    OP_PULSE  enable_i = '1' for one clock cycle (enable_i is '0' before and after): the cycle in
   --              which the instance takes the next falling edge of vs_i (a = 0), rising edge of hs_i
   --              (1), rising edge of de_i (2), ref_i (3), or the cycle after the delay (4)
   type op_t is record
      kind  : op_kind_t;
      gap   : natural;
      lock  : boolean;
      line  : natural;
      delay : natural;
      a     : integer;
      b     : integer;
   end record op_t;
   constant C_NOP : op_t := (OP_NONE, 0, false, 0, 0, 0, 0);
   type ops_t is array (0 to 7) of op_t;
   constant C_NOOPS : ops_t := (others => C_NOP);

   type desc_t is record
      name   : string(1 to 30);
      d0     : integer;          -- the first measured distance
      aper   : boolean;          -- the reference sits in the aperture of the synchronizer
      locked : natural;          -- frames to run after the last lock
      start  : boolean;          -- a pull-in start (its trajectory counts for the coverage)
      keep   : boolean;          -- the instance stays locked through its ops (a missing reference)
      ops    : ops_t;
   end record desc_t;

   constant C_MAXI : natural := 40;
   type descs_t is array (0 to C_MAXI - 1) of desc_t;

   function pad(s : string) return string is
      variable r : string(1 to 30) := (others => ' ');
   begin
      r(1 to s'length) := s;
      return r;
   end function pad;

   function op(kind : op_kind_t; gap : natural; lock : boolean; line, delay : natural;
               a : integer; b : integer := 0) return op_t is
   begin
      return (kind, gap, lock, line, delay, a, b);
   end function op;

   -- the instances of a set; n_descs returns their number
   function make_descs(set : string) return descs_t is
      variable r     : descs_t;
      variable n     : natural := 0;
      variable ops   : ops_t;
      variable nlin  : natural;
      variable pause : natural;
      variable full  : boolean;
      constant LONG  : natural := G_LOCKED;
      constant SHORT : natural := 10;
      procedure add(name : string; d0 : integer; aper : boolean; locked : natural; start : boolean; o : ops_t;
                    keep : boolean := false) is
      begin
         r(n) := (pad(name), d0, aper, locked, start, keep, o);
         n    := n + 1;
      end procedure add;
   begin
      -- "near" (the quick set): the starts whose pull-in is short and the disturbances whose
      -- recovery is short; in 576p and 480p also the starts at the end of the frame
      if set = "near" then
         add("start d0 = target - 4081",    TGT - 4081,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 1025",    TGT - 1025,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 1",       TGT - 1,        false, LONG,  true, C_NOOPS);
         add("start d0 = target",           TGT,            false, SHORT, true, C_NOOPS);
         add("start d0 = target + 4095",    TGT + 4095,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 300 (A)", TGT - 300,      true,  LONG,  true, C_NOOPS);
         if EXACT then
            add("start d0 = 1",                1,              false, SHORT, true, C_NOOPS);
            add("start d0 = frame - 1",        TCI - 1,        false, SHORT, true, C_NOOPS);
            add("start d0 = frame",            TCI,            false, SHORT, true, C_NOOPS);
            add("start d0 = 0 (no reference)",  0,              false, SHORT, true, C_NOOPS);
         end if;
      end if;
      if set = "all" or set = "starts" then
         add("start d0 = 1",                1,              false, SHORT, true, C_NOOPS);
         add("start d0 = target / 2",       TGT / 2,        false, SHORT, true, C_NOOPS);
         add("start d0 = target - 4081",    TGT - 4081,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 4080",    TGT - 4080,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 1025",    TGT - 1025,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 1024",    TGT - 1024,     false, SHORT, true, C_NOOPS);
         add("start d0 = target - 1",       TGT - 1,        false, LONG,  true, C_NOOPS);
         add("start d0 = target",           TGT,            false, SHORT, true, C_NOOPS);
         add("start d0 = target + 1",       TGT + 1,        false, SHORT, true, C_NOOPS);
         add("start d0 = target + 4096",    TGT + 4096,     false, SHORT, true, C_NOOPS);
         add("start d0 = target + band - 1", TGT + BAND - 1, false, SHORT, true, C_NOOPS);
         add("start d0 = target + band",    TGT + BAND,     false, SHORT, true, C_NOOPS);
         add("start d0 = frame / 4",        TCI / 4,        false, SHORT, true, C_NOOPS);
         add("start d0 = frame / 2",        TCI / 2,        false, SHORT, true, C_NOOPS);
         add("start d0 = frame * 3 / 4",    TCI / 4 * 3,    false, SHORT, true, C_NOOPS);
         add("start d0 = frame - 4000",     TCI - 4000,     false, SHORT, true, C_NOOPS);
         add("start d0 = frame - 1",        TCI - 1,        false, SHORT, true, C_NOOPS);
         -- 576p, 480p: the next reference comes in the clock cycle of the measurement
         add("start d0 = frame",            TCI,            false, SHORT, true, C_NOOPS);
         -- no reference before the first measurement, the first one in its clock cycle
         add("start d0 = 0 (no reference)",  0,              false, SHORT, true, C_NOOPS);
         -- the reference in the aperture of the synchronizer: in 720p the phase of the reference
         -- walks through the clock period, so every long run sees the aperture there
         if EXACT then
            add("start d0 = target - 300 (A)", TGT - 300,   true,  LONG,  true, C_NOOPS);
         else
            add("start d0 = target - 300 (A)", TGT - 300,   true,  SHORT, true, C_NOOPS);
         end if;
      end if;
      if set = "all" or set = "disturb" or set = "near" then
         -- a pause of the core: 150 frames (3 s in PAL, 2.5 s in NTSC), 12 in the quick set
         if set = "near" then pause := 12; else pause := 150; end if;
         ops := C_NOOPS;
         -- quick set in 720p: only the disturbances marked "720p quick"
         full := set /= "near" or EXACT;
         if full then
            ops(0) := op(OP_STOP, 3, true, 100, 7, 3, 30000);
            add("3 refs missing, new phase",   TGT - 2000, false, SHORT, false, ops);
         end if;
         if set /= "near" then
            ops(0) := op(OP_STOP, 3, true, 100, 7, pause, D_SS - (TCI - 5000));
            add("pause, back at another phase", TGT - 2000, false, SHORT, false, ops);
         end if;
         ops(0) := op(OP_STOP, 3, true, 100, 7, pause, 0);     -- 720p quick
         add("pause, back at the same phase", TGT - 2000, false, SHORT, false, ops, true);
         ops(0) := op(OP_STOP, 3, true, 100, 7, 1, 0);         -- 720p quick
         add("1 ref missing",               TGT - 2000, false, SHORT, false, ops, true);
         if full then
            ops(0) := op(OP_STOP, 3, true, 100, 7, 2, 0);
            add("2 refs missing",              TGT - 2000, false, SHORT, false, ops, true);
         end if;
         -- a missing reference while not locked: no stretch in that frame
         ops(0) := op(OP_STOP, 1, false, 100, 7, 1, 0);        -- 720p quick
         add("1 ref missing in the pull-in", TGT - 20000, false, SHORT, false, ops);
         if full then
            ops(0) := op(OP_JUMP, 3, true, 300, 7, 40000);
            add("ref jumps 40000 later",       TGT - 2000, false, SHORT, false, ops);
         end if;
         if set /= "near" then
            ops(0) := op(OP_JUMP, 3, true, 300, 7, D_SS - (TCI - 3000));
            add("ref jumps to frame end",      TGT - 2000, false, SHORT, false, ops);
         end if;
         if full then
            ops    := C_NOOPS;
            ops(0) := op(OP_JUMP, 3, true, 300, 7, 40000);
            ops(1) := op(OP_EN, 1, false, M.vsend + 2, M.htotal + 100, 0);
            ops(2) := op(OP_EN, 3, false, 200, 7, 1);
            add("enable off in a long line",   TGT - 2000, false, SHORT, false, ops);
         end if;
         ops    := C_NOOPS;
         ops(0) := op(OP_JUMP, 3, true, 300, 7, 40000);
         ops(1) := op(OP_RST, 1, false, M.vsend + 2, M.htotal + 100, 5);
         ops(2) := op(OP_RST, 3, true, 200, 7, 1);
         ops(3) := op(OP_RST, 3, true, 0, 11, 1);
         add("rst in a long line, mid, at d", TGT - 2000, false, SHORT, false, ops);    -- 720p quick
         nlin   := 30000 / (M.htotal - M.hsstart + 200);
         ops(0) := op(OP_HTOT, 3, true, 100, 7, M.hsstart - 200);
         ops(1) := op(OP_HTOT, 0, false, 100 + nlin, 7, 0);
         ops(2) := op(OP_HTOT, 1, false, M.vsend + 1, 10, 4045);
         ops(3) := op(OP_HTOT, 0, false, M.vsend + 4, 10, 0);
         add("htotal_i short, then 4045",   TGT - 2000, false, SHORT, false, ops);      -- 720p quick
         if full then
            ops    := C_NOOPS;
            ops(0) := op(OP_TARGET, 3, true, 300, 7, 30000);
            ops(1) := op(OP_TARGET, 3, true, 300, 7, -2000);
            add("target_i + 30000, - 2000",    TGT - 2000, false, SHORT, false, ops);
         end if;
         -- one-cycle pulses of enable_i while it is '0': with the reference after the falling edge of
         -- vsync (d = 6000), so that a measurement armed by the pulse would show at the next picture
         -- start after the real enable, which comes in the line after that falling edge
         if set /= "near" or EXACT then
            ops    := C_NOOPS;
            ops(0) := op(OP_JUMP, 3, true, 300, 7, D_SS - 6000);
            ops(1) := op(OP_EN, 0, false, 400, 7, 0);
            ops(2) := op(OP_PULSE, 1, false, 100, 7, 1);
            ops(3) := op(OP_PULSE, 1, false, 100, 7, 2);
            ops(4) := op(OP_PULSE, 1, false, 100, 7, 3);
            ops(5) := op(OP_PULSE, 1, false, 100, 333, 4);
            ops(6) := op(OP_PULSE, 1, false, 100, 7, 0);
            ops(7) := op(OP_EN, 0, false, M.vsend + 2, 7, 1);
            add("enable_i one-cycle pulses",  TGT - 2000, false, SHORT, false, ops);
         end if;
      end if;
      return r;
   end function make_descs;

   -- the number of instances in a list (the unused entries have an empty name)
   function n_of(ds : descs_t) return natural is
   begin
      for i in ds'range loop
         if ds(i).name(1) = character'val(0) then
            return i;
         end if;
      end loop;
      return ds'length;
   end function n_of;

   constant DESCS : descs_t := make_descs(G_SET);
   constant NI    : natural := n_of(DESCS);

   ------------------------------------------------------------------------------
   -- signals of the instances
   ------------------------------------------------------------------------------
   type nat_arr_t is array (0 to C_MAXI - 1) of natural;
   type u12_arr_t is array (0 to C_MAXI - 1) of uint12;
   type tgt_arr_t is array (0 to C_MAXI - 1) of natural range 0 to 2**21 - 1;
   subtype sl_vec_t is std_logic_vector(0 to C_MAXI - 1);
   subtype su_vec_t is std_ulogic_vector(0 to C_MAXI - 1);    -- unresolved: no resolution function

   signal clks      : su_vec_t := (others => '0');
   signal rst_s     : su_vec_t := (others => '1');
   signal en_s      : su_vec_t := (others => '1');
   signal hs_s      : su_vec_t := (others => '0');
   signal vs_s      : su_vec_t := (others => '0');
   signal de_s      : su_vec_t := (others => '0');
   signal ref_s     : su_vec_t := (others => '0');
   signal locked_s  : sl_vec_t;
   signal htot_in_s : u12_arr_t := (others => M.htotal);
   signal target_s  : tgt_arr_t := (others => TGT);
   signal htot_o_s  : u12_arr_t;
   signal stretch_s : u12_arr_t;

begin

   gen_dut : for i in 0 to NI - 1 generate
      signal ht_o, st_o : natural range 0 to 4095;
   begin
      i_dut : entity work.hdmi_genlock
         port map (
            clk_i     => clks(i),
            rst_i     => rst_s(i),
            enable_i  => en_s(i),
            htotal_i  => htot_in_s(i),
            target_i  => target_s(i),
            hs_i      => hs_s(i),
            vs_i      => vs_s(i),
            de_i      => de_s(i),
            ref_i     => ref_s(i),
            htotal_o  => ht_o,
            locked_o  => locked_s(i),
            stretch_o => st_o
         );
      htot_o_s(i)  <= ht_o;
      stretch_s(i) <= st_o;
   end generate gen_dut;

   bench_proc : process
      type ist_t is record
         sc        : scaler_t;
         xs        : scaler_t;     -- G_XCHECK: the same model, stepped at every edge
         last_step : integer;      -- edge of the last step
         nxt       : natural;      -- next edge at which the instance has to be stepped
         busy      : natural;      -- edges to step after a change of an input
         -- inputs of the instance: as driven now (taken at the next edge) and as taken at the last edge
         hs, vs, de, ref, rst, en             : natural range 0 to 1;
         hs_d, vs_d, de_d, ref_d, rst_d, en_d : natural range 0 to 1;
         htot, htot_d                         : uint12;
         target, target_d                     : natural;
         hs_rise_d : boolean;      -- the instance saw a rising edge of hs_i at the last edge
         -- outputs read at the last step
         ht_last   : uint12;
         st_last   : natural;
         lk_last   : std_logic;
         -- the core reference
         ref_on    : boolean;      -- the reference level runs
         lvl       : natural range 0 to 1;
         next_rise : time;
         cur_fall  : time;
         last_chg  : time;
         skip      : natural;      -- reference pulses still to be dropped
         shift     : integer;      -- shift of the pulses after the dropped ones, in clock cycles
         ff1, ff2, ff3 : natural range 0 to 1;
         -- model of SPEC 5.3
         ref_edge  : natural;      -- edge at which the instance took the last ref_i
         ref_valid : boolean;      -- false: no ref_i since rst_i or enable_i = '0' (counter saturated)
         ref_new   : boolean;      -- a ref_i came since the last measurement
         armed     : boolean;
         k         : natural;
         good      : natural range 0 to 8;
         -- frames as the bench sees them (independent of rst_i and enable_i)
         f_armed   : boolean;
         frame     : natural;      -- picture starts seen so far
         meas      : natural;      -- measurements of the model so far
         d_last    : integer;      -- -1: no valid last measurement
         k_last    : natural;
         clean     : boolean;      -- no op since the last measurement
         -- lines
         dirty     : boolean;      -- rst_i, enable_i or htotal_i changed during the current line
         ht_min, ht_max : uint12;
         -- scenario
         active    : boolean;
         opi       : natural;      -- next op
         op_frame  : natural;      -- frame of the last op (or of the start)
         op_allow  : natural;      -- frames of the last op that do not count for the pull-in
         op_due    : boolean;      -- the next op waits for its line
         op_edge   : integer;      -- -1, or the edge at which the next op acts
         rst_end   : natural;      -- the last edge with rst_i = '1' of an OP_RST (natural'high: none)
         pulse_wait : natural range 0 to 5;   -- an OP_PULSE waits for its event (kind + 1), 0: none
         pulse_on  : boolean;      -- enable_i = '1' is driven for one clock cycle
         pulse_chk : boolean;      -- the outputs of the pulse cycle are read at this edge
         -- lock bookkeeping
         was_locked  : boolean;
         lock_since  : natural;    -- measurement at which the instance locked
         locks       : natural;    -- lock episodes
         max_pull    : natural;    -- longest pull-in (measurements)
         first_pull  : natural;
         arrived     : boolean;    -- 720p: d came to target_i - surplus
         k1_frames   : natural;    -- frames with k = 1 after lock in 576p/480p
         kmin, kmax  : integer;    -- k after arrival
         dmin, dmax  : integer;    -- d after lock
         locked_frames : natural;  -- frames locked since the last lock
         -- equal rates
         er_n      : natural;
         er_t0     : time;
         er_max    : real;
         idx       : natural;
         ret_chk   : boolean;      -- check the first valid measurement after the op
         ret_max   : real;         -- the largest deviation found there
      end record ist_t;
      type ist_arr_t is array (0 to C_MAXI - 1) of ist_t;
      variable st      : ist_arr_t;

      -- copies for the decision whether an instance has to be stepped at an edge
      type nat_v_t is array (0 to C_MAXI - 1) of natural;
      variable nxt_a   : nat_v_t;
      variable htl_a   : nat_v_t;
      variable stl_a   : nat_v_t;
      variable lkl_a   : std_logic_vector(0 to C_MAXI - 1);

      variable errors    : natural := 0;
      variable cur_frame : natural := 0;
      variable edge      : natural := 0;
      variable t_now     : time;
      variable act       : sl_vec_t := (others => '0');
      variable alist     : nat_v_t;            -- the active instances
      variable na        : natural := 0;
      variable retired   : boolean := false;
      variable seed1     : positive := G_SEED;
      variable seed2     : positive := 7;
      variable v0_seen   : boolean := false;
      variable v0_now    : boolean := false;
      variable e2        : natural := 0;       -- edge of the first measurement
      variable r_e       : natural;            -- edge at which the reference has to be taken
      variable cov       : bit_vector(0 to TCI / 4096) := (others => '0');
      variable cov_n     : natural;
      variable worst     : natural := 0;
      variable worst_i   : natural := 0;
      variable steps     : natural := 0;
      constant C_SL      : std_logic_vector(0 to 1) := "01";

      procedure err(i : natural; msg : string) is
      begin
         errors := errors + 1;
         report "TB_ERROR " & M.name & " inst " & integer'image(i) & " (" & DESCS(i).name & ") frame "
                & integer'image(cur_frame) & ": " & msg severity error;
         if G_FAILFAST or errors >= 20 then
            report "TB: RESULT FAIL (" & integer'image(errors) & " errors)";
            finish;
         end if;
      end procedure err;

      -- x with the given number of decimals
      function img(x : real; digits : natural := 3) return string is
         variable sc : integer := 10**digits;
         variable v  : integer := integer(round(abs(x) * real(sc)));
         variable f  : string(1 to digits);
         variable fr : integer := v mod sc;
      begin
         for j in digits downto 1 loop
            f(j) := character'val(character'pos('0') + fr mod 10);
            fr   := fr / 10;
         end loop;
         if x < 0.0 then
            return "-" & integer'image(v / sc) & "." & f;
         end if;
         return integer'image(v / sc) & "." & f;
      end function img;

      function secs(frames : natural) return string is
      begin
         return img(real(frames) / M.rate, 2) & " s";
      end function secs;

      -- the stretch table of SPEC 5.3 for a valid measurement
      function law(dd : natural; tg : natural) return natural is
      begin
         if dd <= tg then
            if tg - dd > 4080 then return 4080; else return tg - dd; end if;
         elsif dd < tg + tg + tg / 4 then
            return 0;
         else
            return 4080;
         end if;
      end function law;

      -- the extra length of stretch line j (0 to 15) for the stretch k (SPEC 5.2)
      function extra_of(kk : natural; j : natural) return natural is
      begin
         if j < kk mod 16 then
            return kk / 16 + 1;
         else
            return kk / 16;
         end if;
      end function extra_of;

      -- x reduced to a half frame around 0
      function wrap(x : real) return real is
         variable y : real := x;
      begin
         while y > TC / 2.0 loop y := y - TC; end loop;
         while y <= -TC / 2.0 loop y := y + TC; end loop;
         return y;
      end function wrap;

      -- the first edge at or after the time t
      function edge_of(t : time) return natural is
      begin
         if t <= 0 fs then
            return 0;
         end if;
         return (t + P - 1 fs) / P;
      end function edge_of;

      -- the next op of an instance becomes due: gap frames after the last op, and locked for 3 frames if required
      procedure check_due(variable s : inout ist_t) is
         variable oo : op_t;
      begin
         if v0_seen and s.opi <= ops_t'high and not s.op_due then
            oo := DESCS(s.idx).ops(s.opi);
            if oo.kind /= OP_NONE and s.frame >= s.op_frame + oo.gap and
               (not oo.lock or (s.was_locked and s.meas >= s.lock_since + 3)) then
               s.op_due := true;
            end if;
         end if;
      end procedure check_due;

      -- "lo to hi", or "none" if nothing was recorded
      function range_img(lo, hi, offset : integer) return string is
      begin
         if lo > hi then
            return "none";
         end if;
         return integer'image(lo - offset) & " to " & integer'image(hi - offset);
      end function range_img;

      procedure summary(variable s : in ist_t; constant i : natural) is
      begin
         report "TB: " & M.name & " inst " & integer'image(i) & " " & DESCS(i).name
                & " first pull-in " & integer'image(s.first_pull) & " (" & secs(s.first_pull)
                & "), longest " & integer'image(s.max_pull) & ", locks " & integer'image(s.locks)
                & ", d after lock " & range_img(s.dmin, s.dmax, TGT)
                & " (rel. target), k after arrival " & range_img(s.kmin, s.kmax, 0)
                & ", locked frames " & integer'image(s.locked_frames);
         if DESCS(i).keep and DESCS(i).ops(0).a = 1 then
            report "TB: " & M.name & " inst " & integer'image(i) & " first valid d after the missing reference: "
                   & img(s.ret_max, 3) & " from target - surplus (bound " & img(2.0 * TOL, 3) & ")";
         end if;
         if s.er_n > 0 then
            report "TB: " & M.name & " inst " & integer'image(i) & " equal rates over " & integer'image(s.er_n - 1)
                   & " locked frames: largest difference between the HDMI frames and as many core frames "
                   & img(s.er_max, 4) & " pixel clocks (bound " & img(TOL, 4) & ")";
         end if;
      end procedure summary;

      -- drive the inputs of instance i that changed, and decide the next edge at which it has to be stepped
      procedure drive(variable s : inout ist_t; constant i : natural) is
         variable changed : boolean := false;
         variable nx      : natural;
         variable h       : natural;
         variable t       : time;
      begin
         if s.hs  /= s.hs_d  then hs_s(i)  <= C_SL(s.hs);  changed := true; end if;
         if s.vs  /= s.vs_d  then vs_s(i)  <= C_SL(s.vs);  changed := true; end if;
         if s.de  /= s.de_d  then de_s(i)  <= C_SL(s.de);  changed := true; end if;
         if s.ref /= s.ref_d then ref_s(i) <= C_SL(s.ref); changed := true; end if;
         if s.rst /= s.rst_d then rst_s(i) <= C_SL(s.rst); changed := true; end if;
         if s.en  /= s.en_d  then en_s(i)  <= C_SL(s.en);  changed := true; end if;
         if s.htot /= s.htot_d then htot_in_s(i) <= s.htot; changed := true; end if;
         if s.target /= s.target_d then target_s(i) <= s.target; changed := true; end if;
         if changed then
            s.busy := 3;
         end if;

         -- the next edge at which something can change
         if s.busy > 0 then
            s.busy := s.busy - 1;
            nx := edge + 1;
         elsif s.rst_end /= natural'high or
               not ((s.sc.hsv = 0 and s.sc.hs = 0) or (s.sc.hsv = 1023 and s.sc.hs = 1)) or
               not ((s.sc.vsv = 0 and s.sc.vs = 0) or (s.sc.vsv = 1023 and s.sc.vs = 1)) or
               not ((s.sc.dev = 0 and s.sc.de = 0) or (s.sc.dev = 1023 and s.sc.de = 1)) or
               not scaler_conds_same(s.sc) or
               s.ff1 /= s.lvl or s.ff2 /= s.lvl or s.ff3 /= s.lvl or
               t_now - s.last_chg < C_APERTURE then
            nx := edge + 1;
         else
            -- the horizontal counter reaches a threshold of the sync and enable conditions, or the
            -- line ends (o_hcpt + 1 reaches o_htotal)
            h  := s.sc.o_hcpt;
            nx := natural'high;
            if s.sc.o_hdisp   > h and edge + 1 + s.sc.o_hdisp   - h < nx then nx := edge + 1 + s.sc.o_hdisp   - h; end if;
            if s.sc.o_hsstart > h and edge + 1 + s.sc.o_hsstart - h < nx then nx := edge + 1 + s.sc.o_hsstart - h; end if;
            if s.sc.o_hsend   > h and edge + 1 + s.sc.o_hsend   - h < nx then nx := edge + 1 + s.sc.o_hsend   - h; end if;
            if s.sc.o_htotal >= h + 1 then
               if edge + s.sc.o_htotal - h < nx then nx := edge + s.sc.o_htotal - h; end if;
            else
               nx := edge + 1;
            end if;
            -- the reference level changes
            if s.ref_on and s.lvl = 0 then
               t := s.next_rise;
            else
               t := s.cur_fall;
            end if;
            if s.ref_on or s.lvl = 1 then
               if edge_of(t) < nx then nx := edge_of(t); end if;
            end if;
            -- an op acts
            if s.op_edge >= 0 and s.op_edge < nx then
               nx := s.op_edge;
            end if;
            if nx <= edge then
               nx := edge + 1;
            end if;
         end if;
         s.nxt       := nx;
         s.last_step := edge;
      end procedure drive;

      ------------------------------------------------------------------------------
      -- one edge of instance i; called at every edge at which something can change
      ------------------------------------------------------------------------------
      procedure step(variable s : inout ist_t; constant i : natural) is
         variable ht_o    : uint12;
         variable st_o    : natural;
         variable lk_o    : std_logic;
         variable vs_fall : boolean;
         variable de_rise : boolean;
         variable hs_rise : boolean;
         variable smp     : natural range 0 to 1;
         variable rnd     : real;
         variable d       : integer;
         variable valid   : boolean;
         variable xr      : real;
         variable li      : integer;
         variable ex      : natural;
         variable exp_len : natural;
         variable o       : op_t;
      begin
         cur_frame := s.frame;
         steps     := steps + 1;
         ht_o      := htot_o_s(i);
         st_o      := stretch_s(i);
         lk_o      := locked_s(i);

         -- skipped edges: nothing but the horizontal counter of the scaler changed in them, and the
         -- instance took the same inputs at the last edge as at this one
         if edge > s.last_step + 1 then
            s.sc.o_hcpt  := s.sc.o_hcpt + (edge - s.last_step - 1);
            s.hs_d       := s.hs;  s.vs_d := s.vs; s.de_d := s.de; s.ref_d := s.ref;
            s.rst_d      := s.rst; s.en_d := s.en; s.htot_d := s.htot; s.target_d := s.target;
            s.hs_rise_d  := false;
         end if;

         -- what the instance takes at this edge: s.x; at the last edge: s.x_d
         vs_fall := s.vs = 0 and s.vs_d = 1;
         de_rise := s.de = 1 and s.de_d = 0;
         hs_rise := s.hs = 1 and s.hs_d = 0;
         -- (the registered timing inputs of the scaler are 0 at the first edge, which gives a short
         -- vsync pulse at the start: the first falling edge of vsync after four lines is the real one)
         if i = 0 and vs_fall and not v0_seen and edge > 4 * M.htotal then
            v0_now := true;
         end if;

         ---------------------------------------------------------------------------
         -- outputs (values after the last edge, with the inputs as driven now); from the second
         -- edge on, at time 0 the outputs have not been computed yet
         ---------------------------------------------------------------------------
         if edge > 0 then
            if ht_o < s.htot or ht_o > s.htot + 256 then
               err(i, "htotal_o " & integer'image(ht_o) & " outside htotal_i " & integer'image(s.htot) & " + 0 to 256");
            end if;
            if s.en = 0 and (ht_o /= s.htot or lk_o /= '0' or st_o /= 0) then
               err(i, "enable_i = '0' but htotal_o " & integer'image(ht_o) & ", locked_o " & std_logic'image(lk_o)
                      & ", stretch_o " & integer'image(st_o));
            end if;
            if s.rst_d = 1 and ht_o /= s.htot then
               err(i, "htotal_o " & integer'image(ht_o) & " after rst_i, htotal_i " & integer'image(s.htot));
            end if;
         end if;
         if edge > 1 and ht_o /= s.ht_last and s.htot = s.htot_d and s.en = s.en_d and
            not s.hs_rise_d and s.rst_d = 0 then
            err(i, "htotal_o changed from " & integer'image(s.ht_last) & " to " & integer'image(ht_o)
                   & " without a rising edge of hs_i, rst_i or a change of htotal_i or enable_i");
         end if;
         -- the clock cycle of a one-cycle pulse of enable_i: nothing may show
         if s.pulse_chk then
            s.pulse_chk := false;
            if ht_o /= s.htot or st_o /= 0 or lk_o /= '0' then
               err(i, "one-cycle pulse of enable_i: htotal_o " & integer'image(ht_o) & ", stretch_o "
                      & integer'image(st_o) & ", locked_o " & std_logic'image(lk_o));
            end if;
         end if;
         if s.en = 1 then
            if st_o /= s.k then
               err(i, "stretch_o " & integer'image(st_o) & ", expected " & integer'image(s.k));
            end if;
            if (lk_o = '1') /= (s.good = 8) then
               err(i, "locked_o " & std_logic'image(lk_o) & ", expected the opposite (" & integer'image(s.good) & " good frames)");
            end if;
         end if;

         ---------------------------------------------------------------------------
         -- model of SPEC 5.3 at this edge
         ---------------------------------------------------------------------------
         if vs_fall then
            s.armed := true;
         elsif de_rise and s.armed then
            s.armed := false;
            -- the counter before this edge: 1 in the cycle after the edge that took ref_i, saturating
            if not s.ref_valid or edge - s.ref_edge >= CMAX then
               d := CMAX;
            else
               d := edge - s.ref_edge;
            end if;
            -- valid only with a ref_i since the last measurement (a ref_i at this edge counts for the next one)
            valid     := s.ref_new and d /= CMAX;
            s.ref_new := false;
            -- not valid: the stretch stays while locked (else 0), the lock counter stays
            if valid then
               s.k := law(d, s.target);
               if d + 1024 >= s.target and d < s.target + s.target + s.target / 4 then
                  if s.good < 8 then s.good := s.good + 1; end if;
               else
                  s.good := 0;
               end if;
            elsif s.good /= 8 then
               s.k := 0;
            end if;
            s.meas := s.meas + 1;

            -- start: the first measurement is d0 (or d0 - 1 when the reference sits in the aperture);
            -- d0 = 0: no reference before it (the first one comes in its clock cycle)
            if s.meas = 1 then
               if edge /= e2 or not (d = DESCS(i).d0 or (DESCS(i).aper and d = DESCS(i).d0 - 1) or
                                     (DESCS(i).d0 = 0 and d = CMAX)) then
                  err(i, "first measurement " & integer'image(d) & " at edge " & integer'image(edge)
                         & " instead of d0 " & integer'image(DESCS(i).d0) & " at edge " & integer'image(e2));
               end if;
            end if;

            -- the step of d from the last measurement: d + k - surplus, modulo a core frame
            if valid and s.clean and s.d_last >= 0 and s.d_last < TCI and d < TCI then
               xr := wrap(real(d) - real(s.d_last) - real(s.k_last) + SUR);
               if abs(xr) >= TOL then
                  err(i, "step of d: " & integer'image(s.d_last) & " + k " & integer'image(s.k_last)
                         & " - surplus gave " & integer'image(d) & " (error " & img(xr) & ")");
               end if;
            end if;

            -- coverage of the pull-in trajectories
            if valid and DESCS(i).start and s.good < 8 and d < TCI then
               cov(d / 4096) := '1';
            end if;

            -- lock bookkeeping; this measurement is in frame s.frame + 1
            if s.good = 8 and not s.was_locked then
               s.was_locked    := true;
               s.locks         := s.locks + 1;
               s.lock_since    := s.meas;
               s.locked_frames := 0;
               li := s.frame + 1 - s.op_frame - s.op_allow;
               if s.locks = 1 then
                  s.first_pull := li;
               end if;
               if li > s.max_pull then s.max_pull := li; end if;
               if li > BOUND then
                  err(i, "lock after " & integer'image(li) & " frames (" & secs(li) & "), bound " & integer'image(BOUND));
               end if;
               if DESCS(i).keep and s.locks > 1 then
                  err(i, "locked again: the lock should have stayed");
               end if;
               if DESCS(i).start and li > worst then worst := li; worst_i := i; end if;
            elsif s.good < 8 and s.was_locked then
               s.was_locked := false;
               if s.clean then
                  err(i, "lock lost without a disturbance, d " & integer'image(d));
               end if;
            end if;

            -- an instance that keeps its lock through a missing reference
            if DESCS(i).keep and s.opi > 0 and s.locks > 0 and s.good < 8 then
               err(i, "lock lost after a missing reference at the same phase, d " & integer'image(d));
            end if;
            -- the first valid measurement after a single missing reference: d moved by at most the
            -- uncertainty of the crossing in two frames
            if DESCS(i).keep and DESCS(i).ops(0).a = 1 and valid and s.ret_chk then
               s.ret_chk := false;
               xr := real(d) - (real(s.target) - SUR);
               if abs(xr) > s.ret_max then s.ret_max := abs(xr); end if;
               if abs(xr) >= 2.0 * TOL then
                  err(i, "a missing reference moved d to " & integer'image(d) & " (target - surplus "
                         & img(real(s.target) - SUR) & ")");
               end if;
            end if;

            -- after lock
            if valid and s.good = 8 and s.clean then
               s.locked_frames := s.locked_frames + 1;
               if d < s.dmin then s.dmin := d; end if;
               if d > s.dmax then s.dmax := d; end if;
               if not EXACT then
                  if s.arrived then
                     if abs(real(d) - (real(s.target) - SUR)) >= TOL or abs(real(s.k) - SUR) >= TOL then
                        err(i, "steady state left: d " & integer'image(d) & ", k " & integer'image(s.k));
                     end if;
                     if s.k < s.kmin then s.kmin := s.k; end if;
                     if s.k > s.kmax then s.kmax := s.k; end if;
                  end if;
                  if d <= s.target then s.arrived := true; end if;
               else
                  if s.k < s.kmin then s.kmin := s.k; end if;
                  if s.k > s.kmax then s.kmax := s.k; end if;
                  if s.k = 1 then
                     s.k1_frames := s.k1_frames + 1;
                     if not DESCS(i).aper or s.k1_frames > 1 then
                        err(i, "stretch 1 after lock in an exact mode");
                     end if;
                  elsif s.k /= 0 then
                     err(i, "stretch " & integer'image(s.k) & " after lock in an exact mode");
                  end if;
               end if;
            end if;

            -- an op is behind us once a valid measurement came after it
            if valid then
               s.d_last := d;
               s.clean  := true;
            else
               s.d_last := -1;
            end if;
            s.k_last := s.k;
         end if;
         if s.ref = 1 then
            s.ref_edge  := edge;
            s.ref_valid := true;
            s.ref_new   := true;
         end if;
         if s.rst = 1 or s.en = 0 then
            s.ref_valid  := false;
            s.ref_new    := false;
            s.armed      := false;
            s.k          := 0;
            s.good       := 0;
            s.d_last     := -1;
            s.was_locked := false;
            s.arrived    := false;
            s.k1_frames  := 0;
         end if;

         ---------------------------------------------------------------------------
         -- frames as the bench sees them
         ---------------------------------------------------------------------------
         if vs_fall then
            s.f_armed := true;
         elsif de_rise and s.f_armed then
            s.f_armed := false;
            -- equal rates over the locked frames of the long instances
            if s.good = 8 and s.clean and s.meas >= s.lock_since + 10 and DESCS(i).locked >= 20 then
               if s.er_n = 0 then
                  s.er_t0 := t_now;
               end if;
               s.er_n := s.er_n + 1;
               xr := abs(real((t_now - s.er_t0 - (s.er_n - 1) * TF) / 1 fs)) / real(P / 1 fs);
               if xr > s.er_max then s.er_max := xr; end if;
               if xr >= TOL then
                  err(i, "sum of " & integer'image(s.er_n - 1) & " HDMI frames differs from the core frames by "
                         & img(xr, 4) & " pixel clocks");
               end if;
            end if;
            s.frame := s.frame + 1;
            check_due(s);
            -- done?
            if (s.opi > ops_t'high or DESCS(i).ops(s.opi).kind = OP_NONE) and s.was_locked and
               s.locked_frames >= DESCS(i).locked then
               s.active := false;
               act(i)   := '0';
               retired  := true;
               summary(s, i);
            end if;
         end if;

         ---------------------------------------------------------------------------
         -- the scaler (its htotal port is htotal_o as it was before this edge)
         ---------------------------------------------------------------------------
         scaler_step(s.sc, MT, ht_o);

         if s.sc.line_end and v0_seen then
            if not s.dirty then
               li := s.sc.line_num - M.vsend;
               if li >= 0 and li < 16 then
                  ex := extra_of(s.k, li);
               else
                  ex := 0;
               end if;
               exp_len := s.htot + ex;
               if exp_len > 4095 then exp_len := 4095; end if;
               if s.sc.line_len /= exp_len then
                  err(i, "line " & integer'image(s.sc.line_num) & " is " & integer'image(s.sc.line_len)
                         & " long, expected " & integer'image(exp_len) & " (stretch " & integer'image(s.k) & ")");
               end if;
            elsif s.sc.line_len < s.ht_min or s.sc.line_len > s.ht_max + 256 then
               err(i, "line " & integer'image(s.sc.line_num) & " is " & integer'image(s.sc.line_len)
                      & " long, htotal_i was " & integer'image(s.ht_min) & " to " & integer'image(s.ht_max));
            end if;
            s.dirty  := false;
            s.ht_min := s.htot;
            s.ht_max := s.htot;
            -- an op that is due acts delay clock cycles after the start of its line
            if s.op_due and s.op_edge < 0 then
               o := DESCS(i).ops(s.opi);
               if (s.sc.line_num + 1) mod M.vtotal = o.line then
                  s.op_edge := edge + o.delay;
               end if;
            end if;
         end if;
         if s.rst = 1 or s.en /= s.en_d or s.htot /= s.htot_d then
            s.dirty := true;
         end if;

         ---------------------------------------------------------------------------
         -- the core reference and the synchronizer
         ---------------------------------------------------------------------------
         if s.lvl = 0 and s.ref_on and s.next_rise <= t_now then
            if s.skip > 0 then
               s.skip      := s.skip - 1;
               s.next_rise := s.next_rise + TF;
               if s.skip = 0 then
                  s.next_rise := s.next_rise + s.shift * P;
                  while s.next_rise <= t_now loop
                     s.next_rise := s.next_rise + TF;
                  end loop;
               end if;
            else
               s.lvl       := 1;
               s.last_chg  := s.next_rise;
               s.cur_fall  := s.next_rise + TF_HI;
               s.next_rise := s.next_rise + TF;
            end if;
         elsif s.lvl = 1 and s.cur_fall <= t_now then
            s.lvl      := 0;
            s.last_chg := s.cur_fall;
         end if;
         smp := s.lvl;
         if t_now - s.last_chg < C_APERTURE and s.ref_on then
            uniform(seed1, seed2, rnd);
            if rnd < 0.5 then
               smp := 1 - s.lvl;
            end if;
         end if;
         s.ff3 := s.ff2;
         s.ff2 := s.ff1;
         s.ff1 := smp;

         ---------------------------------------------------------------------------
         -- the scenario
         ---------------------------------------------------------------------------
         s.hs_rise_d := hs_rise;
         s.hs_d   := s.hs;  s.vs_d := s.vs; s.de_d := s.de; s.ref_d := s.ref;
         s.rst_d  := s.rst; s.en_d := s.en; s.htot_d := s.htot; s.target_d := s.target;

         if s.rst = 1 and edge >= s.rst_end then
            s.rst     := 0;
            s.rst_end := natural'high;
         end if;

         if s.pulse_on then
            -- the cycle after a pulse: enable_i back to '0'
            s.pulse_on  := false;
            s.en        := 0;
         end if;
         if s.op_edge = edge and DESCS(i).ops(s.opi).kind = OP_PULSE then
            s.pulse_wait := DESCS(i).ops(s.opi).a + 1;
            s.op_edge    := -1;
         end if;
         -- a pulse waits for the clock cycle in which the instance takes its event
         if s.pulse_wait > 0 then
            if (s.pulse_wait = 1 and s.sc.vs = 0 and s.vs = 1) or
               (s.pulse_wait = 2 and s.sc.hs = 1 and s.hs = 0) or
               (s.pulse_wait = 3 and s.sc.de = 1 and s.de = 0) or
               (s.pulse_wait = 4 and s.ff2 = 1 and s.ff3 = 0 and s.ref = 0) or
               s.pulse_wait = 5 then
               s.pulse_wait := 0;
               s.pulse_on   := true;
               s.pulse_chk  := true;         -- the next edge reads the outputs of the pulse cycle
               s.en         := 1;
               s.op_edge    := edge;          -- completes the op below
            end if;
         end if;
         if s.op_edge = edge then
            o := DESCS(i).ops(s.opi);
            s.op_allow := 0;
            case o.kind is
               when OP_STOP =>
                  s.skip     := o.a;
                  s.shift    := o.b;
                  s.op_allow := o.a;
               when OP_JUMP =>
                  s.next_rise := s.next_rise + o.a * P;
                  while s.next_rise <= t_now loop
                     s.next_rise := s.next_rise + TF;
                  end loop;
               when OP_EN =>
                  s.en := o.a;
               when OP_RST =>
                  s.rst     := 1;
                  s.rst_end := edge + o.a;
               when OP_HTOT =>
                  if o.a = 0 then s.htot := M.htotal; else s.htot := o.a; end if;
               when OP_TARGET =>
                  s.target := s.target + o.a;
               when OP_PULSE | OP_NONE =>
                  null;
            end case;
            s.clean     := false;
            s.arrived   := false;
            s.k1_frames := 0;
            s.ret_chk   := true;
            s.op_frame  := s.frame;
            s.op_due    := false;
            s.op_edge   := -1;
            s.opi       := s.opi + 1;
            check_due(s);
         end if;
         if s.htot < s.ht_min then s.ht_min := s.htot; end if;
         if s.htot > s.ht_max then s.ht_max := s.htot; end if;

         ---------------------------------------------------------------------------
         -- the inputs for the next edge
         ---------------------------------------------------------------------------
         s.hs  := s.sc.hs;
         s.vs  := s.sc.vs;
         s.de  := s.sc.de;
         if s.ff2 = 1 and s.ff3 = 0 then s.ref := 1; else s.ref := 0; end if;
         drive(s, i);
      end procedure step;


      -- the work of instance i at an edge: step it if something can change
      procedure visit(constant i : natural) is
      begin
         if edge >= nxt_a(i) or htot_o_s(i) /= htl_a(i) or stretch_s(i) /= stl_a(i) or
            locked_s(i) /= lkl_a(i) then
            step(st(i), i);
            st(i).ht_last := htot_o_s(i);
            st(i).st_last := stretch_s(i);
            st(i).lk_last := locked_s(i);
            nxt_a(i) := st(i).nxt;
            htl_a(i) := st(i).ht_last;
            stl_a(i) := st(i).st_last;
            lkl_a(i) := st(i).lk_last;
         end if;
         -- the stepping must give the same scaler as a model that is stepped at every edge
         if G_XCHECK and st(i).active then
            scaler_step(st(i).xs, MT, htot_o_s(i));
            if st(i).xs.hs /= st(i).hs or st(i).xs.vs /= st(i).vs or st(i).xs.de /= st(i).de or
               st(i).xs.o_hcpt /= st(i).sc.o_hcpt + (edge - st(i).last_step) or
               st(i).xs.o_vcpt /= st(i).sc.o_vcpt or
               (st(i).xs.line_end and not (st(i).last_step = edge and st(i).sc.line_end and
                                           st(i).sc.line_len = st(i).xs.line_len)) then
               err(i, "the stepped scaler differs from the scaler stepped at every edge at edge " & integer'image(edge)
                      & ": hs/vs/de " & integer'image(st(i).xs.hs) & integer'image(st(i).xs.vs) & integer'image(st(i).xs.de)
                      & " against " & integer'image(st(i).hs) & integer'image(st(i).vs) & integer'image(st(i).de)
                      & ", hcpt " & integer'image(st(i).xs.o_hcpt) & " against " & integer'image(st(i).sc.o_hcpt)
                      & " + " & integer'image(edge - st(i).last_step) & ", vcpt " & integer'image(st(i).xs.o_vcpt)
                      & " against " & integer'image(st(i).sc.o_vcpt) & ", line end " & boolean'image(st(i).xs.line_end)
                      & " " & integer'image(st(i).xs.line_len) & " against " & boolean'image(st(i).sc.line_end)
                      & " " & integer'image(st(i).sc.line_len) & ", last step " & integer'image(st(i).last_step));
            end if;
         end if;
      end procedure visit;

   begin
      report "TB: " & M.name & ": " & integer'image(NI) & " instances, target " & integer'image(TGT)
             & ", core frame " & img(TC, 3) & " pixel clocks, surplus " & img(SUR, 3)
             & ", bound " & integer'image(BOUND) & " frames (" & integer'image(M.bound_s) & " s), uncertainty "
             & img(TOL, 4);

      for i in 0 to NI - 1 loop
         st(i).sc        := C_SCALER_INIT;
         st(i).xs        := C_SCALER_INIT;
         st(i).last_step := -1;
         st(i).nxt       := 0;
         st(i).busy      := 0;
         st(i).hs        := 0; st(i).vs := 0; st(i).de := 0; st(i).ref := 0; st(i).rst := 1; st(i).en := 1;
         st(i).hs_d      := 0; st(i).vs_d := 0; st(i).de_d := 0; st(i).ref_d := 0; st(i).rst_d := 1; st(i).en_d := 1;
         st(i).htot      := M.htotal; st(i).htot_d := M.htotal; st(i).target := TGT; st(i).target_d := TGT;
         st(i).hs_rise_d := false;
         st(i).ht_last   := M.htotal; st(i).st_last := 0; st(i).lk_last := '0';
         st(i).ref_on    := false; st(i).lvl := 0; st(i).next_rise := 0 fs; st(i).cur_fall := 0 fs;
         st(i).last_chg  := -1 sec; st(i).skip := 0; st(i).shift := 0;
         st(i).ff1 := 0; st(i).ff2 := 0; st(i).ff3 := 0;
         st(i).ref_edge  := 0; st(i).ref_valid := false; st(i).ref_new := false; st(i).armed := false; st(i).k := 0; st(i).good := 0;
         st(i).f_armed   := false; st(i).frame := 0; st(i).meas := 0;
         st(i).d_last    := -1; st(i).k_last := 0; st(i).clean := false;
         st(i).dirty     := true; st(i).ht_min := M.htotal; st(i).ht_max := M.htotal;
         st(i).active    := true; st(i).opi := 0; st(i).op_frame := 0; st(i).op_allow := 0;
         st(i).op_due    := false; st(i).op_edge := -1; st(i).rst_end := natural'high;
         st(i).pulse_wait := 0; st(i).pulse_on := false; st(i).pulse_chk := false;
         st(i).was_locked := false; st(i).lock_since := 0; st(i).locks := 0; st(i).max_pull := 0;
         st(i).first_pull := 0; st(i).arrived := false; st(i).k1_frames := 0;
         st(i).kmin := integer'high; st(i).kmax := integer'low;
         st(i).dmin := integer'high; st(i).dmax := integer'low; st(i).locked_frames := 0;
         st(i).er_n := 0; st(i).er_t0 := 0 fs; st(i).er_max := 0.0;
         st(i).idx := i;
         st(i).ret_chk := false; st(i).ret_max := 0.0;
         nxt_a(i) := 0; htl_a(i) := M.htotal; stl_a(i) := 0; lkl_a(i) := '0';
         act(i) := '1';
         alist(i) := i;
         na := i + 1;
      end loop;

      loop
         ---------------------------------------------------------------------------
         -- rising edge of the clocks of the active instances
         ---------------------------------------------------------------------------
         for j in 0 to na - 1 loop
            clks(alist(j)) <= '1';
         end loop;
         wait for 0 fs;
         t_now := now;

         for j in 0 to na - 1 loop
            visit(alist(j));
         end loop;

         ---------------------------------------------------------------------------
         -- start: release the reset after the first falling edge of vsync and place
         -- the references (all instances have the same timing until then)
         ---------------------------------------------------------------------------
         if v0_now and not v0_seen then
            v0_seen := true;
            -- the first measurement: the picture start after the next falling edge of vsync
            e2 := edge + TH + (M.vtotal - M.vsend) * M.htotal - M.hsstart;
            for i in 0 to NI - 1 loop
               st(i).rst := 0;
               rst_s(i)  <= '0';
               st(i).busy := 3;
               -- the reference is taken at edge r_e: the level rises within the clock period
               -- before edge r_e - 2 (in the middle, or within the aperture)
               r_e := e2 - DESCS(i).d0;
               st(i).ref_on := true;
               if DESCS(i).aper then
                  st(i).next_rise := (r_e - 2) * P - C_APERTURE / 2;
               else
                  st(i).next_rise := (r_e - 2) * P - P / 2;
               end if;
               st(i).frame    := 0;          -- frames are counted from here: the next picture start is frame 1,
               st(i).f_armed  := true;       -- the first measurement comes with frame 2
               st(i).op_frame := 1;
               nxt_a(i)       := edge + 1;
            end loop;
         end if;
         for j in 0 to na - 1 loop
            clks(alist(j)) <= '0';
         end loop;
         -- the list of the active instances
         if retired then
            retired := false;
            na      := 0;
            for i in 0 to NI - 1 loop
               if act(i) = '1' then
                  alist(na) := i;
                  na        := na + 1;
               end if;
            end loop;
         end if;

         if na = 0 then
            exit;
         end if;
         if v0_seen and edge > e2 + (2 * BOUND + G_LOCKED + 200) * (TH + 4080) then
            for i in 0 to NI - 1 loop
               if st(i).active then
                  err(i, "did not finish (op " & integer'image(st(i).opi) & ", locked " & boolean'image(st(i).was_locked) & ")");
               end if;
            end loop;
            exit;
         end if;
         if G_FRAMES > 0 and v0_seen and edge > e2 + G_FRAMES * TH then
            report "TB: " & M.name & " stopped after " & integer'image(G_FRAMES) & " frames as requested";
            exit;
         end if;

         edge := edge + 1;
         wait for P;
      end loop;

      -- coverage of the pull-in trajectories in sections of 4096 pixel clocks
      if (G_SET = "all" or G_SET = "starts" or G_SET = "near") and G_FRAMES = 0 then
         cov_n := 0;
         for j in cov'range loop
            if cov(j) = '1' then cov_n := cov_n + 1; end if;
         end loop;
         report "TB: " & M.name & " the pull-in trajectories measured d in " & integer'image(cov_n) & " of "
                & integer'image(cov'length) & " sections of 4096 pixel clocks of the frame";
         report "TB: " & M.name & " longest pull-in of a start: " & integer'image(worst) & " frames ("
                & secs(worst) & ", bound " & integer'image(M.bound_s) & " s) from " & DESCS(worst_i).name;
      end if;
      report "TB: " & M.name & " " & integer'image(edge) & " clock edges, " & integer'image(steps) & " instance steps";

      if errors = 0 then
         report "TB: RESULT PASS";
      else
         report "TB: RESULT FAIL (" & integer'image(errors) & " errors)";
      end if;
      finish;
   end process bench_proc;

end architecture sim;
