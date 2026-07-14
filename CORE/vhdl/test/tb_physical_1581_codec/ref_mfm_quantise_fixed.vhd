-------------------------------------------------------------------------------
-- ref_mfm_quantise_fixed.vhd   (SIMULATION / TEST ONLY -- never synthesize)
--
-- Verbatim copy of the pre-round-12 FIXED-WINDOW gap classifier, preserved as
-- the "old" reference side of the A/B margin harness
-- (tb_physical_1581_quantise_ab.vhd). It deliberately reuses the PRODUCTION
-- entity name physical_1581_mfm_quantise so that the unmodified production
-- decoder source can be analyzed against it into a separate GHDL library
-- (q_old) and instantiated next to the adaptive pipeline (q_new):
--
--   ghdl -a --std=08 --work=q_old --workdir=B  physical_1581_pkg.vhd ...
--        ref_mfm_quantise_fixed.vhd  ... physical_1581_mfm_decoder.vhd
--
-- This file must NEVER be added to a Vivado project or analyzed into the same
-- library as the production quantiser -- the entity names collide by design.
--
-- Behavior: classification against the inclusive legacy windows
-- C_GAP_SHORT/MED/LONG_LO/HI from physical_1581_pkg, with hard dead-bands
-- (241..257, 343..354) that classify as "11" loss of lock. The generics and
-- the field_i / est_o ports exist only for shape compatibility with the
-- adaptive production entity (the q_old decoder instantiates them by name):
-- all of them are ignored and est_o is the nominal constant.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_quantise is
  generic (
    G_TOL_ACQ_SHR    : natural := C_QUANT_TOL_SHR;   -- ignored (fixed windows)
    G_TOL_FIELD_SHR  : natural := C_QUANT_TOL_SHR;   -- ignored (fixed windows)
    G_HUNT_ADAPT_ALL : boolean := false              -- ignored (no adaptation)
  );
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;                       -- sync reset
    field_i     : in  std_logic := '0';                -- ignored (fixed windows)
    gap_valid_i : in  std_logic := '0';
    gap_len_i   : in  unsigned(15 downto 0) := (others => '0');
    gap_valid_o : out std_logic := '0';
    gap_class_o : out unsigned(1 downto 0) := "11";
    est_o       : out unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12)
  );
end entity physical_1581_mfm_quantise;

architecture rtl of physical_1581_mfm_quantise is
begin

  -- no adaptation in the fixed-window reference: est is pinned to nominal
  est_o <= to_unsigned(C_QUANT_EST_NOM_Q, 12);

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        gap_valid_o <= '0';
        gap_class_o <= "11";
      else
        -- Classify against the legacy acceptance windows (inclusive).
        if    gap_len_i >= C_GAP_SHORT_LO and gap_len_i <= C_GAP_SHORT_HI then
          gap_class_o <= "00";                          -- short  (1.0)
        elsif gap_len_i >= C_GAP_MED_LO   and gap_len_i <= C_GAP_MED_HI   then
          gap_class_o <= "01";                          -- medium (1.5)
        elsif gap_len_i >= C_GAP_LONG_LO  and gap_len_i <= C_GAP_LONG_HI  then
          gap_class_o <= "10";                          -- long   (2.0)
        else
          gap_class_o <= "11";                          -- invalid / dead-band
        end if;

        gap_valid_o <= gap_valid_i;
      end if;
    end if;
  end process;

end architecture rtl;
