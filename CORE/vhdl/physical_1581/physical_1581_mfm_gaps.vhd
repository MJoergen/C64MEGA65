-------------------------------------------------------------------------------
-- physical_1581_mfm_gaps.vhd
--
-- DD-MFM read pipeline, stage 1 of 4: flux edges -> gap interval.
--   A free-running counter increments every controller clock. On the START of
--   an active-low RDATA flux pulse (falling edge of f_rdata_i) it emits the
--   accumulated gap length and pulses gap_valid_o, then restarts the counter.
--   f_rdata_i is assumed already 2-FF synchronized into this clock domain.
--
-- Runt filter (issue #90 round 10; threshold retuned in round 11): a measured
--   gap shorter than C_GAP_GLITCH (16 cycles = 320 ns) is an electrical
--   glitch, never a legitimate DD flux interval (the shortest valid gap window
--   starts at 160 cycles). Such a gap is NOT emitted; the runt edge is dropped
--   and its length accumulates into the following gap (a runt double-edge
--   collapses into one edge), so downstream stages and the gap statistics see
--   only clean, full-length gaps. Each merged runt pulses runt_o for one cycle
--   (counted by the diagnostics). Hardware evidence for the need: diag
--   GAP_MIN = 0x0001, i.e. two RDATA edges 40 ns apart reached the decoder and
--   killed fields silently near the index write splice. The threshold must
--   stay FAR below the shortest valid window: a larger value (round 10 used
--   120) turns late-in-gap noise into a merge of the FOLLOWING REAL edge,
--   silently corrupting the gap stream -- see C_GAP_GLITCH in the pkg.
--
-- First-edge rule: a gap is the interval between TWO flux edges, so the first
--   edge after reset only STARTS the first gap -- it emits nothing (neither a
--   gap nor a runt). Previously that edge emitted a bogus reset-relative
--   interval, which was harmless for decoding (the decoder idles) but would
--   pollute the runt/gap-error statistics once the filter exists: the decoder
--   is reset at every operation start, frequently within C_GAP_GLITCH of the
--   next real edge.
--
-- Adapted from mega65-core src/vhdl/mfm_gaps.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/
--   debugtools/TextIO; dropped the sim-only packed_rdata and gap_count debug
--   outputs; renamed ports to the project _i/_o convention; added an explicit
--   synchronous reset; added the runt filter and the first-edge rule above.
--   Gap-detection timing (two-stage edge pipeline) kept bit-for-bit.
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
    gap_len_o   : out unsigned(15 downto 0) := (others => '0');
    runt_o      : out std_logic := '0'                 -- 1-cycle pulse per merged runt gap
  );
end entity physical_1581_mfm_gaps;

architecture rtl of physical_1581_mfm_gaps is
  signal counter         : integer range 0 to 65535 := 0;
  signal last_rdata      : std_logic := '1';
  signal last_last_rdata : std_logic := '1';
  signal seen_edge       : std_logic := '0';   -- a flux edge occurred since reset
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
        runt_o          <= '0';
        seen_edge       <= '0';
      else
        last_rdata      <= f_rdata_i;
        last_last_rdata <= last_rdata;

        if last_rdata = '0' and last_last_rdata = '1' then
          if seen_edge = '0' then
            -- First edge after reset: start the first gap (see header comment).
            seen_edge   <= '1';
            counter     <= 0;
            gap_valid_o <= '0';
            runt_o      <= '0';
          elsif counter < C_GAP_GLITCH then
            -- Runt: drop this edge and keep counting, so its length merges
            -- into the following gap (see the runt-filter header comment).
            runt_o      <= '1';
            gap_valid_o <= '0';
            if counter /= 65535 then
              counter <= counter + 1;
            end if;
          else
            -- Start of flux pulse: emit the gap and restart the counter.
            gap_valid_o <= '1';
            gap_len_o   <= to_unsigned(counter, 16);
            counter     <= 0;
            runt_o      <= '0';
          end if;
        else
          gap_valid_o <= '0';
          runt_o      <= '0';
          if counter /= 65535 then
            counter <= counter + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
