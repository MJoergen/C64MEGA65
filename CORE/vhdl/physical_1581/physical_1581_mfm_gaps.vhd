-------------------------------------------------------------------------------
-- physical_1581_mfm_gaps.vhd
--
-- DD-MFM read pipeline, stage 1 of 4: flux edges -> gap interval.
--   A free-running counter increments every controller clock. On the START of
--   an active-low RDATA flux pulse (falling edge of f_rdata_i) it emits the
--   accumulated gap length and pulses gap_valid_o, then restarts the counter.
--   f_rdata_i is assumed already 2-FF synchronized into this clock domain.
--
-- Adapted from mega65-core src/vhdl/mfm_gaps.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/
--   debugtools/TextIO; dropped the sim-only packed_rdata and gap_count debug
--   outputs; renamed ports to the project _i/_o convention; added an explicit
--   synchronous reset. Gap-detection timing (two-stage edge pipeline) kept
--   bit-for-bit.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_gaps is
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;                       -- sync reset: counter + valid
    f_rdata_i   : in  std_logic;                       -- active-low flux, pre-synced
    gap_valid_o : out std_logic := '0';
    gap_len_o   : out unsigned(15 downto 0) := (others => '0')
  );
end entity physical_1581_mfm_gaps;

architecture rtl of physical_1581_mfm_gaps is
  signal counter         : integer range 0 to 65535 := 0;
  signal last_rdata      : std_logic := '1';
  signal last_last_rdata : std_logic := '1';
begin

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        counter         <= 0;
        last_rdata      <= '1';
        last_last_rdata <= '1';
        gap_valid_o     <= '0';
        gap_len_o       <= (others => '0');
      else
        last_rdata      <= f_rdata_i;
        last_last_rdata <= last_rdata;

        if last_rdata = '0' and last_last_rdata = '1' then
          -- Start of flux pulse: emit the gap and restart the counter.
          gap_valid_o <= '1';
          gap_len_o   <= to_unsigned(counter, 16);
          counter     <= 0;
        else
          gap_valid_o <= '0';
          if counter /= 65535 then
            counter <= counter + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
