-------------------------------------------------------------------------------
-- mech_model_1581.vhd   (simulation only -- NOT synthesizable, NOT for the core)
--
-- Behavioural model of the "other side" of the MEGA65's internal 34-pin floppy
-- connector: a PC-style 3.5" DD mechanism plus a formatted DD-MFM disk. It is
-- driven by the physical_1581 controller's Shugart-style control pins and it
-- talks back with the sensor lines and a continuous stream of active-low RDATA
-- flux. Its only purpose is to exercise the controller and the read decoder in
-- GHDL without hardware.
--
-- It NEVER touches the connector outside the documented polarity (recon_map.md
-- sec 6 / DESIGN.md sec 9):
--   * f_motora_i / f_selecta_i / f_step_i : active-low  ('0' = on / selected / step)
--   * f_stepdir_i : '1' = toward track 0 (decrement cyl); '0' = toward higher cyl
--   * f_side1_i   : '0' = side 0 ; '1' = side 1  (empirical, from real media:
--     the pin-LOW surface carries the H=0 IDs = the D81 first half; the 1581
--     wires PA0 straight to this line and PA0=0 selects logical side 0)
--   * f_index_o / f_track0_o / f_writeprotect_o / f_diskchanged_o : active-low
--   * f_rdata_o   : active-low flux (one low pulse per MFM channel-bit "1")
--
-- Disk contents come from golden_1581_pkg so the read path can be checked
-- byte-for-byte. DD only (250 kbit/s, MFM 2 us half-cell) -- f_density_i is
-- observed but has no effect.
--
-- Two modes (generic G_WRITABLE):
--   false (default): the procedural read-only generator -- RDATA is
--     regenerated every 193.28 ms from golden_1581_pkg, the index free-runs
--     independently. Unchanged; f_wgate_i must stay '1' (fatal otherwise).
--   true: a LIVE ROTATING FLUX STORE (the AExp tb_fdd_write p_disk model,
--     ported). An internal 50 MHz timebase (20 ns, phase-aligned with a
--     testbench clock started at '0' with a 10 ns half period) turns the
--     spindle: pos = cycles since the index, period G_INDEX_PERIOD; the index
--     is low for G_INDEX_LOW at pos 0 while spinning. Per (cylinder, side) a
--     track holds one slot per 50 cycles, each with at most one flux edge
--     (its exact cycle position) and a generation stamp (0 = seed, n = the
--     n-th WGATE window). A track is seeded lazily, the first time it is under
--     the spinning head, from seed_payload(0, ...) = golden_payload in the
--     C_SEED_* layout of golden_1581_pkg (seed_req_i re-seeds with any key).
--     Playback: one active-low RDATA pulse of 400 ns (the generator's width)
--     per stored edge passing the head while WGATE is high. Writing: while
--     WGATE is low the erase sweeps at cycle granularity (an edge exactly
--     under the head is wiped) and every WDATA falling edge is stored with the
--     window's generation; meanwhile RDATA echoes WDATA (a head reading its
--     own write current, the worst case for the controller's decoder hold).
--     Instruments: WGATE windows (open position, length
--     in cycles, generation), a WDATA pulse-width census inside WGATE, a fatal
--     assert on WDATA low while WGATE is high, span queries (seed / new edge
--     counts) and a text dump of a track's edge list for wr_twin.py.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mfm_flux_gen_pkg.all;
use work.golden_1581_pkg.all;
use std.textio.all;

entity mech_model_1581 is
  generic (
    G_INDEX_PERIOD : time    := 200 ms;   -- index-to-index period (300 RPM)
    G_INDEX_LOW    : time    := 2 ms;     -- index active-low pulse width
    G_NUM_CYL      : integer := 80;       -- cylinders 0 .. G_NUM_CYL-1
    G_WRITABLE     : boolean := false;    -- true: live rotating flux store (see header)
    G_DUMP_PREFIX  : string  := "flux_"   -- dump file name prefix (G_WRITABLE)
  );
  port (
    -- driven BY the controller (we only observe these) ----------------------
    f_motora_i        : in  std_logic;    -- active-low: '0' = motor on
    f_selecta_i       : in  std_logic;    -- active-low: '0' = drive selected
    f_side1_i         : in  std_logic;    -- '1' = side 0, '0' = side 1
    f_stepdir_i       : in  std_logic;    -- '1' = toward trk0, '0' = toward higher cyl
    f_step_i          : in  std_logic;    -- active-low step pulse (move on the pulse)
    f_density_i       : in  std_logic;    -- observed only (DD fixed)

    -- static disk/mechanism configuration ('1' = active) --------------------
    cfg_present_i     : in  std_logic;    -- a disk is in the drive
    cfg_wprot_i       : in  std_logic;    -- disk is write protected
    cfg_change_i      : in  std_logic;    -- disk-changed line asserted
    cfg_noindex_i     : in  std_logic := '0';  -- G_WRITABLE: suppress the index pulse (sensor fault)

    -- driven TO the controller ----------------------------------------------
    f_index_o         : out std_logic := '1';   -- active-low index
    f_track0_o        : out std_logic := '1';   -- active-low track-0 sensor
    f_writeprotect_o  : out std_logic := '1';   -- active-low write protect
    f_diskchanged_o   : out std_logic := '1';   -- active-low disk changed
    f_rdata_o         : out std_logic := '1';   -- active-low read flux

    -- write pins from the controller (active low) ---------------------------
    f_wgate_i         : in  std_logic := '1';
    f_wdata_i         : in  std_logic := '1';

    -- flux store control (G_WRITABLE only). Each request is a toggle; q_ack_o
    -- toggles once it has been served (all in the same model clock).
    trk_cyl_i         : in  integer := 0;        -- track addressed by seed/dump/query
    trk_side_i        : in  integer := 0;
    seed_req_i        : in  std_logic := '0';    -- (re)seed the track with seed_key_i
    seed_key_i        : in  integer := 0;
    dump_req_i        : in  std_logic := '0';    -- dump the track to G_DUMP_PREFIX & dump_tag_i & ".txt"
    dump_tag_i        : in  integer := 0;
    q_req_i           : in  std_logic := '0';    -- count the edges in [q_from_i, q_from_i + q_len_i)
    q_from_i          : in  integer := 0;
    q_len_i           : in  integer := 0;
    q_ack_o           : out std_logic := '0';
    q_seed_o          : out integer := 0;        -- edges with generation 0 (seed) in the span
    q_new_o           : out integer := 0;        -- edges with generation > 0 in the span

    -- observability for testbenches -----------------------------------------
    cur_cyl_o         : out integer := 0;        -- current head cylinder
    pos_o             : out integer := 0;        -- rotational position (G_WRITABLE)
    t_rev_o           : out integer := 0;        -- cycles per revolution (G_WRITABLE)
    wg_opens_o        : out integer := 0;        -- WGATE windows so far
    wg_open_pos_o     : out integer := 0;        -- position of the last WGATE fall
    wg_len_o          : out integer := 0;        -- cycles of the last closed window
    wg_closed_o       : out integer := 0;        -- windows closed so far
    pw_min_o          : out integer := 0;        -- WDATA low-pulse census (inside WGATE)
    pw_max_o          : out integer := 0;
    pw_count_o        : out integer := 0
  );
end entity mech_model_1581;

architecture sim of mech_model_1581 is

  -- Current head cylinder. The step process is the sole writer.
  signal cyl_r : integer range 0 to G_NUM_CYL - 1 := 0;

  -- True while the disk is actually spinning under the (selected) head.
  function spinning(mot, sel, pres : std_logic) return boolean is
  begin
    return mot = '0' and sel = '0' and pres = '1';
  end function;

begin

  ---------------------------------------------------------------------------
  -- Head position: observability + track-0 sensor derive from cyl_r.
  ---------------------------------------------------------------------------
  cur_cyl_o  <= cyl_r;
  f_track0_o <= '0' when cyl_r = 0 else '1';          -- active-low

  ---------------------------------------------------------------------------
  -- Step tracking. A step is an active-low pulse on f_step_i; direction is
  -- latched at the falling edge (as on real hardware DIR is set up first),
  -- and the head moves one cylinder once the pulse completes.
  ---------------------------------------------------------------------------
  step_proc : process
    variable dir : std_logic;
  begin
    wait until falling_edge(f_step_i);      -- pulse start
    dir := f_stepdir_i;                     -- latch direction
    wait until rising_edge(f_step_i);       -- pulse complete -> move now
    if dir = '1' then                       -- toward track 0
      if cyl_r > 0 then
        cyl_r <= cyl_r - 1;
      end if;
    else                                    -- toward higher cylinder
      if cyl_r < G_NUM_CYL - 1 then
        cyl_r <= cyl_r + 1;
      end if;
    end if;
  end process step_proc;

  ---------------------------------------------------------------------------
  -- Static sensor levels (active-low).
  ---------------------------------------------------------------------------
  config_proc : process (cfg_wprot_i, cfg_change_i)
  begin
    if cfg_wprot_i = '1' then
      f_writeprotect_o <= '0';
    else
      f_writeprotect_o <= '1';
    end if;
    if cfg_change_i = '1' then
      f_diskchanged_o <= '0';
    else
      f_diskchanged_o <= '1';
    end if;
  end process config_proc;

  ---------------------------------------------------------------------------
  -- G_WRITABLE = false: the procedural read-only generator (unchanged).
  ---------------------------------------------------------------------------
  g_ro : if not G_WRITABLE generate
  ---------------------------------------------------------------------------
  -- Index. Constant G_INDEX_PERIOD period; a G_INDEX_LOW active-low pulse is
  -- emitted only while the disk is spinning (checked at the pulse instant).
  -- Free-runs independently of the flux -- exact alignment is not required.
  ---------------------------------------------------------------------------
  index_proc : process
  begin
    f_index_o <= '1';
    wait for G_INDEX_PERIOD - G_INDEX_LOW;
    if spinning(f_motora_i, f_selecta_i, cfg_present_i) then
      f_index_o <= '0';
      wait for G_INDEX_LOW;
      f_index_o <= '1';
    else
      wait for G_INDEX_LOW;               -- keep the period constant, stay high
    end if;
  end process index_proc;

  ---------------------------------------------------------------------------
  -- Read flux. While spinning, continuously emit the current track: ten
  -- standard DD-MFM records (ID + 512-byte data), geometry re-sampled at the
  -- top of every revolution so a step between revolutions takes effect. When
  -- not spinning, RDATA idles high.
  ---------------------------------------------------------------------------
  flux_proc : process
    variable prev : std_logic := '0';     -- MFM previous-data-bit state
    variable c    : integer;              -- cylinder sampled for this revolution
    variable s    : integer;              -- side    sampled for this revolution
    variable v    : unsigned(15 downto 0);
    variable pl   : unsigned(7 downto 0);
  begin
    if spinning(f_motora_i, f_selecta_i, cfg_present_i) then
      -- sample geometry once per revolution
      c := cyl_r;
      if f_side1_i = '0' then
        s := 0;
      else
        s := 1;
      end if;

      for sec in 1 to 10 loop
        -- ---- ID field -----------------------------------------------------
        mfm_bytes(f_rdata_o, x"00", 12, prev);           -- preamble
        mfm_a1(f_rdata_o, prev);                          -- 3 x A1 (sync)
        mfm_a1(f_rdata_o, prev);
        mfm_a1(f_rdata_o, prev);
        mfm_byte(f_rdata_o, x"FE", prev);                 -- ID address mark
        mfm_byte(f_rdata_o, to_unsigned(c   mod 256, 8), prev);  -- C
        mfm_byte(f_rdata_o, to_unsigned(s,          8), prev);   -- H (side)
        mfm_byte(f_rdata_o, to_unsigned(sec,        8), prev);   -- R (sector)
        mfm_byte(f_rdata_o, x"02", prev);                 -- N (512-byte code)
        v := x"FFFF";
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"FE");
        v := crc16_update(v, to_unsigned(c mod 256, 8));
        v := crc16_update(v, to_unsigned(s,        8));
        v := crc16_update(v, to_unsigned(sec,      8));
        v := crc16_update(v, x"02");
        mfm_byte(f_rdata_o, v(15 downto 8), prev);        -- ID CRC hi
        mfm_byte(f_rdata_o, v(7 downto 0),  prev);        -- ID CRC lo

        -- ---- gap ----------------------------------------------------------
        mfm_bytes(f_rdata_o, x"4E", 22, prev);

        -- ---- DATA field ---------------------------------------------------
        mfm_bytes(f_rdata_o, x"00", 12, prev);           -- preamble
        mfm_a1(f_rdata_o, prev);                          -- 3 x A1 (sync)
        mfm_a1(f_rdata_o, prev);
        mfm_a1(f_rdata_o, prev);
        mfm_byte(f_rdata_o, x"FB", prev);                 -- data address mark
        v := x"FFFF";
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"A1");
        v := crc16_update(v, x"FB");
        for off in 0 to 511 loop
          pl := golden_payload(c, s, sec, off);
          mfm_byte(f_rdata_o, pl, prev);
          v := crc16_update(v, pl);
        end loop;
        mfm_byte(f_rdata_o, v(15 downto 8), prev);        -- data CRC hi
        mfm_byte(f_rdata_o, v(7 downto 0),  prev);        -- data CRC lo

        -- ---- trailing gap -------------------------------------------------
        mfm_bytes(f_rdata_o, x"4E", 30, prev);
      end loop;
    else
      f_rdata_o <= '1';                    -- idle high, no flux
      wait for 100 us;                     -- poll for spin-up
    end if;
  end process flux_proc;

  -- a write into the read-only model is a testbench or DUT defect
  ro_guard : process (f_wgate_i, f_wdata_i)
  begin
    assert f_wgate_i /= '0'
      report "mech_model_1581: WGATE asserted on the read-only model (G_WRITABLE = false)"
      severity failure;
    assert f_wdata_i /= '0'
      report "mech_model_1581: WDATA asserted on the read-only model (G_WRITABLE = false)"
      severity failure;
  end process ro_guard;
  end generate g_ro;

  ---------------------------------------------------------------------------
  -- G_WRITABLE = true: the live rotating flux store.
  ---------------------------------------------------------------------------
  g_rw : if G_WRITABLE generate
    constant C_CYC    : time    := 20 ns;                    -- model timebase
    constant C_TREV   : integer := G_INDEX_PERIOD / C_CYC;   -- cycles per revolution
    constant C_IDXL   : integer := G_INDEX_LOW / C_CYC;
    constant C_SLOT   : integer := 50;                       -- cycles per slot
    constant C_NSLOT  : integer := (C_TREV + C_SLOT - 1) / C_SLOT;
    constant C_CELL   : integer := 100;                      -- channel cell (2 us)
    constant C_RDPW   : integer := MFM_LOW_WIDTH / C_CYC;    -- RDATA pulse (400 ns)
    constant C_NTRK   : integer := 2 * G_NUM_CYL;
    constant C_NWIN   : integer := 256;                      -- window log entries
    signal mclk : std_logic := '0';
  begin
    mclk <= not mclk after C_CYC / 2;
    t_rev_o <= C_TREV;

    p_disk : process (mclk)
      type t_slots is array (natural range <>) of integer;
      type t_slots_ptr is access t_slots;
      type t_trk is record
        flux : t_slots_ptr;     -- edge position (cycles after the index) or -1
        gen  : t_slots_ptr;     -- 0 = seed, n = written in WGATE window n
        key  : integer;         -- seed key of the current seed
      end record;
      type t_trks is array (0 to C_NTRK - 1) of t_trk;
      variable trks : t_trks;

      type t_win is record
        tix, gen, pos, len : integer;   -- track, generation, open position, cycles
      end record;
      type t_wins is array (0 to C_NWIN - 1) of t_win;
      variable wins  : t_wins;
      variable nwin  : integer := 0;

      variable pos     : integer := C_TREV - 1;   -- the first clock moves to 0
      variable sl      : integer;
      variable tix     : integer;
      variable spin    : boolean;
      variable gen     : integer := 0;
      variable wg_prev : std_logic := '1';
      variable wd_prev : std_logic := '1';
      variable wg_prev_rd : std_logic := '1';
      variable wgcyc   : integer := 0;
      variable pulse   : integer := 0;
      variable pw_run  : integer := 0;
      variable pwmin   : integer := integer'high;
      variable pwmax   : integer := 0;
      variable pwcnt   : integer := 0;
      variable seq_p, dmp_p, qry_p : std_logic := '0';
      variable cnt_s, cnt_n : integer;
      variable p, s    : integer;

      -- MFM channel word of a byte after carried bit prev (independent of the
      -- DUT encoder: the seed is built here from first principles)
      procedure lay_byte(variable fl, gn : inout t_slots_ptr; variable k : inout integer;
                         b : in integer; variable prev : inout integer) is
        variable d, c : integer;
      begin
        for i in 7 downto 0 loop
          d := (b / 2**i) mod 2;
          if prev = 0 and d = 0 then c := 1; else c := 0; end if;
          if c = 1 then
            fl((k * C_CELL + 50) / C_SLOT) := k * C_CELL + 50; gn((k * C_CELL + 50) / C_SLOT) := 0;
          end if;
          k := k + 1;
          if d = 1 then
            fl((k * C_CELL + 50) / C_SLOT) := k * C_CELL + 50; gn((k * C_CELL + 50) / C_SLOT) := 0;
          end if;
          k := k + 1;
          prev := d;
        end loop;
      end procedure;

      procedure lay_a1(variable fl, gn : inout t_slots_ptr; variable k : inout integer;
                       variable prev : inout integer) is
        constant RAW : std_logic_vector(15 downto 0) := x"4489";
      begin
        for i in 15 downto 0 loop
          if RAW(i) = '1' then
            fl((k * C_CELL + 50) / C_SLOT) := k * C_CELL + 50; gn((k * C_CELL + 50) / C_SLOT) := 0;
          end if;
          k := k + 1;
        end loop;
        prev := 1;
      end procedure;

      -- lay a complete seed track: C_SEED_LEAD x 4E, ten records, 4E fill
      procedure lay(variable fl, gn : inout t_slots_ptr; cyl, side, key : in integer) is
        variable k    : integer := 0;     -- channel bit index from the index
        variable prev : integer := 0;
        variable v    : unsigned(15 downto 0);
        variable pl   : unsigned(7 downto 0);
      begin
        for i in 0 to C_NSLOT - 1 loop fl(i) := -1; gn(i) := -1; end loop;
        for i in 1 to C_SEED_LEAD loop lay_byte(fl, gn, k, 16#4E#, prev); end loop;
        for sec in 1 to 10 loop
          for i in 1 to 12 loop lay_byte(fl, gn, k, 0, prev); end loop;
          lay_a1(fl, gn, k, prev); lay_a1(fl, gn, k, prev); lay_a1(fl, gn, k, prev);
          lay_byte(fl, gn, k, 16#FE#, prev);
          lay_byte(fl, gn, k, cyl mod 256, prev);
          lay_byte(fl, gn, k, side, prev);
          lay_byte(fl, gn, k, sec, prev);
          lay_byte(fl, gn, k, 2, prev);
          v := x"FFFF";
          v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
          v := crc16_update(v, x"FE");
          v := crc16_update(v, to_unsigned(cyl mod 256, 8));
          v := crc16_update(v, to_unsigned(side, 8));
          v := crc16_update(v, to_unsigned(sec, 8));
          v := crc16_update(v, x"02");
          lay_byte(fl, gn, k, to_integer(v(15 downto 8)), prev);
          lay_byte(fl, gn, k, to_integer(v(7 downto 0)), prev);
          for i in 1 to 22 loop lay_byte(fl, gn, k, 16#4E#, prev); end loop;
          for i in 1 to 12 loop lay_byte(fl, gn, k, 0, prev); end loop;
          lay_a1(fl, gn, k, prev); lay_a1(fl, gn, k, prev); lay_a1(fl, gn, k, prev);
          lay_byte(fl, gn, k, 16#FB#, prev);
          v := x"FFFF";
          v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1"); v := crc16_update(v, x"A1");
          v := crc16_update(v, x"FB");
          for off in 0 to 511 loop
            pl := seed_payload(key, cyl, side, sec, off);
            lay_byte(fl, gn, k, to_integer(pl), prev);
            v := crc16_update(v, pl);
          end loop;
          lay_byte(fl, gn, k, to_integer(v(15 downto 8)), prev);
          lay_byte(fl, gn, k, to_integer(v(7 downto 0)), prev);
          for i in 1 to 30 loop lay_byte(fl, gn, k, 16#4E#, prev); end loop;
        end loop;
        while (k + 16) * C_CELL <= C_TREV loop
          lay_byte(fl, gn, k, 16#4E#, prev);
        end loop;
      end procedure;

      procedure seed(t, key : in integer) is
      begin
        if trks(t).flux = null then
          trks(t).flux := new t_slots(0 to C_NSLOT - 1);
          trks(t).gen  := new t_slots(0 to C_NSLOT - 1);
        end if;
        lay(trks(t).flux, trks(t).gen, t / 2, t mod 2, key);
        trks(t).key := key;
        for i in 0 to nwin - 1 loop          -- forget the windows of this track
          if wins(i).tix = t then wins(i).tix := -1; end if;
        end loop;
      end procedure;

      procedure dump(t, tag : in integer) is
        file     f   : text;
        variable l   : line;
        variable tf, tg : t_slots_ptr;
        variable nw  : integer := 0;
      begin
        if trks(t).flux = null then seed(t, 0); end if;
        file_open(f, G_DUMP_PREFIX & integer'image(tag) & ".txt", write_mode);
        for i in 0 to nwin - 1 loop
          if wins(i).tix = t then nw := nw + 1; end if;
        end loop;
        write(l, string'("# meta t_rev=") & integer'image(C_TREV) & " cell=" & integer'image(C_CELL)
              & " slot=" & integer'image(C_SLOT) & " cyl=" & integer'image(t / 2)
              & " side=" & integer'image(t mod 2) & " seed_key=" & integer'image(trks(t).key)
              & " windows=" & integer'image(nw));
        writeline(f, l);
        for i in 0 to nwin - 1 loop
          if wins(i).tix = t then
            write(l, string'("G ") & integer'image(wins(i).gen) & " " & integer'image(wins(i).pos)
                  & " " & integer'image(wins(i).len));
            writeline(f, l);
          end if;
        end loop;
        for i in 0 to C_NSLOT - 1 loop
          if trks(t).flux(i) >= 0 then
            write(l, string'("E ") & integer'image(trks(t).flux(i)) & " " & integer'image(trks(t).gen(i)));
            writeline(f, l);
          end if;
        end loop;
        -- the pre-seed, laid afresh (what the track held before any window)
        tf := new t_slots(0 to C_NSLOT - 1);
        tg := new t_slots(0 to C_NSLOT - 1);
        lay(tf, tg, t / 2, t mod 2, trks(t).key);
        for i in 0 to C_NSLOT - 1 loop
          if tf(i) >= 0 then
            write(l, string'("P ") & integer'image(tf(i)));
            writeline(f, l);
          end if;
        end loop;
        deallocate(tf); deallocate(tg);
        file_close(f);
      end procedure;
    begin
      if rising_edge(mclk) then
        pos  := (pos + 1) mod C_TREV;
        sl   := pos / C_SLOT;
        spin := spinning(f_motora_i, f_selecta_i, cfg_present_i);
        if f_side1_i = '0' then tix := 2 * cyl_r; else tix := 2 * cyl_r + 1; end if;
        pos_o <= pos;

        if pos < C_IDXL and spin and cfg_noindex_i = '0' then
          f_index_o <= '0';
        else
          f_index_o <= '1';
        end if;

        -- lazy seed: the first time a track is under the spinning head
        if spin and trks(tix).flux = null then
          seed(tix, 0);
        end if;

        assert not (f_wdata_i = '0' and f_wgate_i = '1')
          report "mech_model_1581: WDATA low while WGATE is high (edge outside WGATE)"
          severity failure;

        -- WGATE windows, measured in cycles
        if f_wgate_i = '0' and wg_prev = '1' then
          gen   := gen + 1;
          wgcyc := 0;
          wg_open_pos_o <= pos;
          wg_opens_o    <= gen;
          assert spin report "mech_model_1581: WGATE opened while the disk is not spinning" severity error;
          if nwin < C_NWIN then
            wins(nwin) := (tix => tix, gen => gen, pos => pos, len => -1);
            nwin := nwin + 1;
          else
            report "mech_model_1581: window log full" severity warning;
          end if;
        elsif f_wgate_i = '1' and wg_prev = '0' then
          wg_len_o    <= wgcyc;
          wg_closed_o <= gen;
          for i in 0 to nwin - 1 loop
            if wins(i).gen = gen then wins(i).len := wgcyc; end if;
          end loop;
        end if;
        wg_prev := f_wgate_i;

        -- WDATA pulse-width census (the pin is high outside WGATE by the assert)
        if f_wdata_i = '0' then
          if wd_prev = '1' then pw_run := 1; else pw_run := pw_run + 1; end if;
        elsif wd_prev = '0' and pw_run > 0 then
          if pw_run < pwmin then pwmin := pw_run; end if;
          if pw_run > pwmax then pwmax := pw_run; end if;
          pwcnt  := pwcnt + 1;
          pw_run := 0;
          pw_min_o <= pwmin; pw_max_o <= pwmax; pw_count_o <= pwcnt;
        end if;

        -- erase (cycle granularity) and write under WGATE
        if f_wgate_i = '0' and spin and trks(tix).flux /= null then
          wgcyc := wgcyc + 1;
          if trks(tix).flux(sl) = pos then
            trks(tix).flux(sl) := -1;
          end if;
          if f_wdata_i = '0' and wd_prev = '1' then
            trks(tix).flux(sl) := pos;
            trks(tix).gen(sl)  := gen;
          end if;
        elsif f_wgate_i = '0' then
          wgcyc := wgcyc + 1;
        end if;
        wd_prev := f_wdata_i;

        -- playback: one RDATA pulse per stored edge while reading. While
        -- WGATE is low the head echoes the write current onto RDATA (the
        -- worst case for the controller's decoder hold, WRITE-SPEC 6.4)
        if f_wgate_i = '0' then
          f_rdata_o <= f_wdata_i;
          pulse     := 0;
        elsif wg_prev_rd = '0' then
          f_rdata_o <= '1';                    -- the gate just closed
        elsif pulse /= 0 then
          pulse := pulse - 1;
          if pulse = 0 then f_rdata_o <= '1'; end if;
        elsif spin and f_wgate_i = '1' and trks(tix).flux /= null then
          if trks(tix).flux(sl) = pos then
            f_rdata_o <= '0';
            pulse     := C_RDPW;
          end if;
        end if;
        if not spin and pulse = 0 and f_wgate_i = '1' then f_rdata_o <= '1'; end if;
        wg_prev_rd := f_wgate_i;

        -- store requests from the testbench
        if seed_req_i /= seq_p then
          seq_p := seed_req_i;
          seed(2 * trk_cyl_i + trk_side_i, seed_key_i);
          q_ack_o <= not q_ack_o;
        end if;
        if dump_req_i /= dmp_p then
          dmp_p := dump_req_i;
          dump(2 * trk_cyl_i + trk_side_i, dump_tag_i);
          q_ack_o <= not q_ack_o;
        end if;
        if q_req_i /= qry_p then
          qry_p := q_req_i;
          cnt_s := 0; cnt_n := 0;
          t_q : if trks(2 * trk_cyl_i + trk_side_i).flux /= null then
            for i in 0 to C_NSLOT - 1 loop
              p := trks(2 * trk_cyl_i + trk_side_i).flux(i);
              if p >= 0 then
                s := (p - q_from_i) mod C_TREV;    -- offset into the span
                if s < q_len_i then
                  if trks(2 * trk_cyl_i + trk_side_i).gen(i) = 0 then
                    cnt_s := cnt_s + 1;
                  else
                    cnt_n := cnt_n + 1;
                  end if;
                end if;
              end if;
            end loop;
          end if t_q;
          q_seed_o <= cnt_s; q_new_o <= cnt_n;
          q_ack_o  <= not q_ack_o;
        end if;
      end if;
    end process p_disk;
  end generate g_rw;

end architecture sim;
