-------------------------------------------------------------------------------
-- decoder_stub_1581.vhd
--
-- Test-only stand-in for physical_1581_mfm_decoder: the same entity name, the
-- same generics and the same ports, but no flux path. The record stream that
-- the decoder would deliver (ID fields, data marks, payload bytes, data ends)
-- comes from the signals of the package decoder_stub_1581_pkg, which a
-- testbench drives; the stub only passes them on. The controller is analyzed
-- against this entity unchanged, so a bench can place every record to the
-- clock and run the controller's read FSM without simulating the flux path.
--
-- The bench that drives the package has to keep the timing of the real
-- decoder where the controller depends on it: every output is a register
-- (assign it right after a clock edge), id_valid_o, data_start_o,
-- data_byte_valid_o and data_end_o are one-clock pulses that never coincide,
-- the ID fields are valid in the id_valid_o clock, data_crc_ok_o and
-- data_deleted_o in the data_end_o clock (data_deleted_o keeps its value
-- until the next data_end_o, also across a reset), and a reset (rst_i, the
-- controller's dec_rst) ends the record under way without a data_end_o. The
-- stub reports rst_i back through the package (ds_rst) for that purpose.
--
-- NEVER analyze this file into a library together with the real
-- physical_1581_mfm_decoder.vhd: both declare the entity
-- physical_1581_mfm_decoder, and whichever is analyzed last silently
-- replaces the other. Use a library of its own (run_tb_rdahead_ctl.sh does).
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package decoder_stub_1581_pkg is
  -- the record stream, driven by the testbench
  signal ds_id_valid, ds_id_crc_ok : std_logic := '0';
  signal ds_id_c, ds_id_h, ds_id_r, ds_id_n : unsigned(7 downto 0) := (others => '0');
  signal ds_data_start, ds_data_byte_valid, ds_data_end : std_logic := '0';
  signal ds_data_crc_ok, ds_data_deleted : std_logic := '0';
  signal ds_data_byte : unsigned(7 downto 0) := (others => '0');
  -- the decoder reset of the controller (dec_rst), driven by the stub
  signal ds_rst : std_logic := '0';
end package;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;
use work.decoder_stub_1581_pkg.all;

entity physical_1581_mfm_decoder is
  generic (
    G_SYNC_GATE            : boolean := true;
    G_SYNC_PREAMBLE_GATE   : boolean := false;
    G_SYNC_SPAN_GATE       : boolean := true;
    G_RECORD_SEQUENCE_GATE : boolean := true;
    G_QUANT_TOL_ACQ_SHR    : natural := C_QUANT_TOL_SHR;
    G_QUANT_HUNT_ADAPT_ALL : boolean := true
  );
  port (
    clk_i             : in  std_logic;
    rst_i             : in  std_logic;
    f_rdata_i         : in  std_logic;
    tol_off_i         : in  std_logic := '0';   -- as the real decoder; without effect in the stub
    id_valid_o        : out std_logic := '0';
    id_c_o            : out unsigned(7 downto 0) := (others => '0');
    id_h_o            : out unsigned(7 downto 0) := (others => '0');
    id_r_o            : out unsigned(7 downto 0) := (others => '0');
    id_n_o            : out unsigned(7 downto 0) := (others => '0');
    id_crc_ok_o       : out std_logic := '0';
    id_crc_stored_o   : out unsigned(15 downto 0) := (others => '0');
    data_start_o      : out std_logic := '0';
    data_deleted_o    : out std_logic := '0';
    data_byte_o       : out unsigned(7 downto 0) := (others => '0');
    data_byte_valid_o : out std_logic := '0';
    data_end_o        : out std_logic := '0';
    data_crc_ok_o     : out std_logic := '0';
    locked_o          : out std_logic := '0';
    gap_error_o       : out std_logic := '0';
    runt_o            : out std_logic := '0';
    a1_candidate_o    : out std_logic := '0';
    a1_span_reject_o  : out std_logic := '0';
    a1_train_o        : out std_logic := '0';
    mark_fe_o         : out std_logic := '0';
    mark_dam_o        : out std_logic := '0';
    dam_unarmed_o     : out std_logic := '0';
    tol_hit_o         : out std_logic := '0';   -- as the real decoder; never pulses in the stub
    last_gap_o        : out unsigned(15 downto 0) := (others => '0');
    crc_value_o       : out unsigned(15 downto 0) := (others => '0');
    est_o             : out unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12)
  );
end entity physical_1581_mfm_decoder;

architecture stub of physical_1581_mfm_decoder is
begin
  id_valid_o        <= ds_id_valid;
  id_crc_ok_o       <= ds_id_crc_ok;
  id_c_o            <= ds_id_c;
  id_h_o            <= ds_id_h;
  id_r_o            <= ds_id_r;
  id_n_o            <= ds_id_n;
  data_start_o      <= ds_data_start;
  data_deleted_o    <= ds_data_deleted;
  data_byte_o       <= ds_data_byte;
  data_byte_valid_o <= ds_data_byte_valid;
  data_end_o        <= ds_data_end;
  data_crc_ok_o     <= ds_data_crc_ok;
  mark_dam_o        <= ds_data_start;
  locked_o          <= '1';
  ds_rst            <= rst_i;
end architecture stub;
