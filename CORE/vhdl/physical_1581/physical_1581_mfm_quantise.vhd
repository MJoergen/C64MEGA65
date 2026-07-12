-------------------------------------------------------------------------------
-- physical_1581_mfm_quantise.vhd
--
-- DD-MFM read pipeline, stage 2 of 4: gap interval -> 2-bit gap class.
--   "00" = short  (1.0 interval)   "01" = medium (1.5 interval)
--   "10" = long   (2.0 interval)   "11" = invalid / loss-of-lock
--
-- Adapted from mega65-core src/vhdl/mfm_quantise_gaps.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/
--   debugtools/TextIO; renamed ports to the project _i/_o convention; added an
--   explicit synchronous reset. DEVIATION FROM UPSTREAM ALGORITHM: the upstream
--   cycles_per_interval / 0x51-cpi midpoint thresholds are replaced by the spec
--   acceptance windows from physical_1581_pkg (50 MHz). A gap below C_GAP_SHORT_LO,
--   above C_GAP_LONG_HI, or in a dead-band between windows classifies as "11"
--   invalid rather than snapping to a neighbouring class.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_quantise is
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;                       -- sync reset
    gap_valid_i : in  std_logic := '0';
    gap_len_i   : in  unsigned(15 downto 0) := (others => '0');
    gap_valid_o : out std_logic := '0';
    gap_class_o : out unsigned(1 downto 0) := "11"
  );
end entity physical_1581_mfm_quantise;

architecture rtl of physical_1581_mfm_quantise is
begin

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        gap_valid_o <= '0';
        gap_class_o <= "11";
      else
        -- Classify against the spec acceptance windows (inclusive).
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
