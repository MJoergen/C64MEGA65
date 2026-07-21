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
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.mfm_flux_gen_pkg.all;
use work.golden_1581_pkg.all;

entity mech_model_1581 is
  generic (
    G_INDEX_PERIOD : time    := 200 ms;   -- index-to-index period (300 RPM)
    G_INDEX_LOW    : time    := 2 ms;     -- index active-low pulse width
    G_NUM_CYL      : integer := 80        -- cylinders 0 .. G_NUM_CYL-1
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

    -- driven TO the controller ----------------------------------------------
    f_index_o         : out std_logic := '1';   -- active-low index
    f_track0_o        : out std_logic := '1';   -- active-low track-0 sensor
    f_writeprotect_o  : out std_logic := '1';   -- active-low write protect
    f_diskchanged_o   : out std_logic := '1';   -- active-low disk changed
    f_rdata_o         : out std_logic := '1';   -- active-low read flux

    -- observability for testbenches -----------------------------------------
    cur_cyl_o         : out integer := 0         -- current head cylinder
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

end architecture sim;
