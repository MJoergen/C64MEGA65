-------------------------------------------------------------------------------
-- tb_mech_model_1581.vhd
--
-- Self-test of the behavioural floppy-mechanism model (mech_model_1581) against
-- the real DD-MFM read decoder (physical_1581_mfm_decoder). It proves two
-- things end-to-end, with no hardware:
--
--   1. With the disk spinning at cylinder 0 / side 0, the decoder recovers a
--      well-formed record: cyl = 0, side = 0, some sector 1..10, id_crc_ok = 1,
--      data_crc_ok = 1, and all 512 payload bytes equal golden_payload(0,0,sec,off).
--   2. A single active-low step pulse with direction "toward higher cylinder"
--      (f_stepdir = '0') advances the head: cur_cyl_o becomes 1 and the decoder
--      then yields cyl = 1 records (payload against golden_payload(1,0,sec,off)).
--
-- A small G_INDEX_PERIOD (20 ms) is used purely to keep the run brief; the flux
-- cell timing is fixed by the decoder and cannot be sped up.
--
-- Run (from repo root, B = abs temp workdir):
--   ghdl -a --std=08 --workdir=B \
--     CORE/vhdl/physical_1581/physical_1581_pkg.vhd \
--     CORE/vhdl/physical_1581/physical_1581_crc.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_gaps.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_quantise.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_gaps_to_bits.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_bits_to_bytes.vhd \
--     CORE/vhdl/physical_1581/physical_1581_mfm_decoder.vhd \
--     CORE/vhdl/test/tb_physical_1581_codec/mfm_flux_gen_pkg.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/golden_1581_pkg.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/mech_model_1581.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/tb_mech_model_1581.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_mech_model_1581 --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.golden_1581_pkg.all;

entity tb_mech_model_1581 is
end entity;

architecture sim of tb_mech_model_1581 is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- controller-driven mechanism inputs (this TB stands in for the controller)
  signal f_motora   : std_logic := '0';   -- motor on   (active-low)
  signal f_selecta  : std_logic := '0';   -- selected   (active-low)
  signal f_side1    : std_logic := '1';   -- side 0
  signal f_stepdir  : std_logic := '0';   -- toward higher cyl
  signal f_step     : std_logic := '1';   -- idle high  (active-low pulse)
  signal f_density  : std_logic := '1';

  signal cfg_present : std_logic := '1';
  signal cfg_wprot   : std_logic := '0';
  signal cfg_change  : std_logic := '0';

  -- mechanism outputs
  signal f_index        : std_logic;
  signal f_track0       : std_logic;
  signal f_writeprotect : std_logic;
  signal f_diskchanged  : std_logic;
  signal f_rdata        : std_logic;
  signal cur_cyl        : integer;

  -- decoder outputs
  signal id_valid        : std_logic;
  signal id_c, id_h, id_r, id_n : unsigned(7 downto 0);
  signal id_crc_ok       : std_logic;
  signal id_crc_stored   : unsigned(15 downto 0);
  signal data_start      : std_logic;
  signal data_deleted    : std_logic;
  signal data_byte       : unsigned(7 downto 0);
  signal data_byte_valid : std_logic;
  signal data_end        : std_logic;
  signal data_crc_ok     : std_logic;
  signal locked          : std_logic;
  signal gap_error       : std_logic;
  signal last_gap        : unsigned(15 downto 0);

  -- captured / snapshotted record
  type arr_t is array (0 to 511) of unsigned(7 downto 0);
  signal cap      : arr_t := (others => (others => '0'));
  signal cap_idx  : integer := 0;
  signal pend_c   : integer := 0;
  signal pend_sec : integer := 0;
  signal pend_id_ok : std_logic := '0';

  -- one completed record, stable until the next record completes
  signal rec_cap     : arr_t := (others => (others => '0'));
  signal rec_c       : integer := -1;
  signal rec_sec     : integer := 0;
  signal rec_id_ok   : std_logic := '0';
  signal rec_data_ok : std_logic := '0';
  signal rec_done    : integer := 0;      -- bumps once per completed data field

  function hs(v : unsigned) return string is
  begin
    return to_hstring(std_logic_vector(v));
  end function;

begin

  clk <= not clk after 10 ns;             -- 50 MHz controller clock

  ---------------------------------------------------------------------------
  -- device under test: mechanism model + real read decoder, RDATA wired across
  ---------------------------------------------------------------------------
  i_mech : entity work.mech_model_1581
    generic map (
      G_INDEX_PERIOD => 20 ms,
      G_INDEX_LOW    => 2 ms,
      G_NUM_CYL      => 80
    )
    port map (
      f_motora_i       => f_motora,
      f_selecta_i      => f_selecta,
      f_side1_i        => f_side1,
      f_stepdir_i      => f_stepdir,
      f_step_i         => f_step,
      f_density_i      => f_density,
      cfg_present_i    => cfg_present,
      cfg_wprot_i      => cfg_wprot,
      cfg_change_i     => cfg_change,
      f_index_o        => f_index,
      f_track0_o       => f_track0,
      f_writeprotect_o => f_writeprotect,
      f_diskchanged_o  => f_diskchanged,
      f_rdata_o        => f_rdata,
      cur_cyl_o        => cur_cyl
    );

  i_dec : entity work.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => f_rdata,
      id_valid_o => id_valid, id_c_o => id_c, id_h_o => id_h, id_r_o => id_r,
      id_n_o => id_n, id_crc_ok_o => id_crc_ok, id_crc_stored_o => id_crc_stored,
      data_start_o => data_start, data_deleted_o => data_deleted,
      data_byte_o => data_byte, data_byte_valid_o => data_byte_valid,
      data_end_o => data_end, data_crc_ok_o => data_crc_ok,
      locked_o => locked, gap_error_o => gap_error, last_gap_o => last_gap
    );

  ---------------------------------------------------------------------------
  -- capture: latch ID at id_valid, accumulate the following data field, and
  -- snapshot a complete record at data_end (stable for the checker to read).
  ---------------------------------------------------------------------------
  capture : process (clk)
  begin
    if rising_edge(clk) then
      if id_valid = '1' then
        pend_c     <= to_integer(id_c);
        pend_sec   <= to_integer(id_r);
        pend_id_ok <= id_crc_ok;
      end if;

      if data_start = '1' then
        cap_idx <= 0;
      elsif data_byte_valid = '1' then
        cap(cap_idx) <= data_byte;
        cap_idx <= cap_idx + 1;
      end if;

      if data_end = '1' then
        rec_cap     <= cap;               -- snapshot the 512 bytes
        rec_c       <= pend_c;
        rec_sec     <= pend_sec;
        rec_id_ok   <= pend_id_ok;
        rec_data_ok <= data_crc_ok;
        rec_done    <= rec_done + 1;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- stimulus + self-checks
  ---------------------------------------------------------------------------
  stim : process

    -- Block until a completed record matches (cyl, side 0), then verify all
    -- 512 payload bytes against the golden source.
    procedure expect_track(exp_cyl : integer) is
    begin
      loop
        wait on rec_done;                 -- a new record has completed
        if rec_c = exp_cyl and rec_id_ok = '1' and rec_data_ok = '1' then
          report "record: cyl=" & integer'image(rec_c)
               & " sec=" & integer'image(rec_sec)
               & " id_crc_ok=1 data_crc_ok=1";
          for off in 0 to 511 loop
            assert rec_cap(off) = golden_payload(exp_cyl, 0, rec_sec, off)
              report "FAIL: cyl " & integer'image(exp_cyl)
                   & " sec " & integer'image(rec_sec)
                   & " byte[" & integer'image(off) & "] = " & hs(rec_cap(off))
                   & " expected " & hs(golden_payload(exp_cyl, 0, rec_sec, off))
              severity error;
          end loop;
          assert rec_sec >= 1 and rec_sec <= 10
            report "FAIL: decoded sector out of range: " & integer'image(rec_sec)
            severity error;
          report "cyl " & integer'image(exp_cyl)
               & " payload byte-for-byte MATCH (512 bytes, sec "
               & integer'image(rec_sec) & ")";
          exit;
        end if;
      end loop;
    end procedure;

  begin
    -- static sensor sanity (active-low levels)
    rst <= '1';
    wait for 400 ns;
    rst <= '0';
    wait for 400 ns;
    assert f_writeprotect = '1'
      report "FAIL: write-protect asserted with cfg_wprot=0" severity error;
    assert f_diskchanged = '1'
      report "FAIL: disk-changed asserted with cfg_change=0" severity error;
    assert cur_cyl = 0
      report "FAIL: head not at cylinder 0 at start" severity error;
    assert f_track0 = '0'
      report "FAIL: track-0 sensor not active at cylinder 0" severity error;

    ------------------------------------------------------------------ phase 1
    report "PHASE 1: expecting cyl=0 records from the spinning disk";
    expect_track(0);

    ------------------------------------------------------------------ step
    -- one active-low step pulse, direction = toward higher cylinder
    f_stepdir <= '0';
    wait for 1 us;                        -- DIR setup
    f_step <= '0';
    wait for 4 us;                        -- active-low step pulse
    f_step <= '1';
    wait for 100 us;                      -- let the head settle
    assert cur_cyl = 1
      report "FAIL: head did not advance to cylinder 1 (cur_cyl="
           & integer'image(cur_cyl) & ")" severity error;
    assert f_track0 = '1'
      report "FAIL: track-0 sensor still active after stepping off track 0"
      severity error;
    report "STEP OK: head advanced to cylinder " & integer'image(cur_cyl);

    ------------------------------------------------------------------ phase 2
    report "PHASE 2: expecting cyl=1 records after the step";
    expect_track(1);

    report "tb_mech_model_1581: ALL TESTS PASSED";
    finish;
  end process;

  ---------------------------------------------------------------------------
  -- diagnostics
  ---------------------------------------------------------------------------
  dbg : process (clk)
    variable plock : std_logic := '0';
  begin
    if rising_edge(clk) then
      if locked = '1' and plock = '0' then
        report "decoder LOCKED";
      end if;
      plock := locked;
      if id_valid = '1' then
        report "ID_VALID C=" & hs(id_c) & " H=" & hs(id_h) & " R=" & hs(id_r)
             & " N=" & hs(id_n) & " crc_ok=" & std_logic'image(id_crc_ok);
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- global timeout guard (roughly two full 10-sector revolutions worst case)
  ---------------------------------------------------------------------------
  guard : process
  begin
    wait for 1 sec;
    report "FAIL: global timeout" severity failure;
  end process;

end architecture sim;
