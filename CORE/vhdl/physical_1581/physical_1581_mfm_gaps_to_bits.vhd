-------------------------------------------------------------------------------
-- physical_1581_mfm_gaps_to_bits.vhd
--
-- DD-MFM read pipeline, stage 3 of 4: gap class -> decoded DATA bit(s) + A1 sync.
--   The decoded data bit(s) per gap depend on the previous emitted bit and the
--   gap class (see the case table below). The A1 missing-clock sync (raw 0x4489)
--   is detected when the four most-recent quantised gaps equal "10011001"
--   (2.0, 1.5, 2.0, 1.5): sync_o pulses, the pending bit queue is flushed, and
--   last_bit is forced to '1' (A1 ends in a 1).
--
-- Adapted from mega65-core src/vhdl/mfm_gaps_to_bits.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/
--   debugtools/TextIO; renamed ports to the project _i/_o convention; added an
--   explicit synchronous reset. DEVIATION FROM UPSTREAM ALGORITHM: an invalid
--   gap class ("11") now drops lock -- it clears recent_gaps and the bit queue
--   instead of silently emitting no bits -- so a loss-of-lock cannot leave a
--   stale partial sync pattern in recent_gaps. The bit-emission table and the
--   sync detection are otherwise kept bit-for-bit.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_gaps_to_bits is
  port (
    clk_i       : in  std_logic;
    rst_i       : in  std_logic;                       -- sync reset
    gap_valid_i : in  std_logic := '0';
    gap_class_i : in  unsigned(1 downto 0) := "11";
    bit_valid_o : out std_logic := '0';
    bit_o       : out std_logic := '0';
    sync_o      : out std_logic := '0'
  );
end entity physical_1581_mfm_gaps_to_bits;

architecture rtl of physical_1581_mfm_gaps_to_bits is
  signal last_bit       : std_logic := '0';
  signal check_sync     : std_logic := '0';
  -- Last four quantised gaps; A1 sync == 2.0,1.5,2.0,1.5 = "10011001".
  signal recent_gaps    : unsigned(7 downto 0) := (others => '0');
  constant sync_gaps    : unsigned(7 downto 0) := "10011001";
  signal bit_queue      : std_logic_vector(1 downto 0) := "00";
  signal bits_queued    : integer range 0 to 2 := 0;
  signal last_gap_valid : std_logic := '0';
begin

  process (clk_i)
    variable state : unsigned(2 downto 0);
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        last_bit       <= '0';
        check_sync     <= '0';
        recent_gaps    <= (others => '0');
        bit_queue      <= "00";
        bits_queued    <= 0;
        last_gap_valid <= '0';
        bit_valid_o    <= '0';
        bit_o          <= '0';
        sync_o         <= '0';
      else
        last_gap_valid <= gap_valid_i;

        if gap_valid_i = '1' and last_gap_valid = '0' then
          if gap_class_i = "11" then
            -- Invalid class: drop lock. Clear the sync history and bit queue.
            recent_gaps <= (others => '0');
            bit_queue   <= "00";
            bits_queued <= 0;
            check_sync  <= '0';
          else
            -- Shift the class into the sync-detection history.
            recent_gaps(7 downto 2) <= recent_gaps(5 downto 0);
            recent_gaps(1 downto 0) <= gap_class_i;
            check_sync              <= '1';

            -- Decode data bit(s): state = last_bit & gap_class.
            state(2)          := last_bit;
            state(1 downto 0) := gap_class_i;
            case state is
              when "000" =>            -- last 0, 1.0 -> 0
                bit_queue <= "00"; bits_queued <= 1;
              when "100" =>            -- last 1, 1.0 -> 1
                bit_queue <= "11"; bits_queued <= 1;
              when "001" =>            -- last 0, 1.5 -> 1
                bit_queue <= "11"; bits_queued <= 1;
              when "101" =>            -- last 1, 1.5 -> 00
                bit_queue <= "00"; bits_queued <= 2;
              when "010" =>            -- last 0, 2.0 -> 01
                bit_queue <= "01"; bits_queued <= 2;
              when "110" =>            -- last 1, 2.0 -> 01
                bit_queue <= "01"; bits_queued <= 2;
              when others =>
                bits_queued <= 0;
            end case;
          end if;
        else
          check_sync <= '0';
        end if;

        -- Output stage: sync mark, or a queued bit, or idle.
        if (check_sync = '1') and (recent_gaps = sync_gaps) then
          sync_o      <= '1';
          bits_queued <= 0;
          bit_valid_o <= '0';
          last_bit    <= '1';         -- sync marks are $A1
        elsif bits_queued /= 0 then
          bit_valid_o  <= '1';
          bit_o        <= bit_queue(1);
          last_bit     <= bit_queue(1);
          bit_queue(1) <= bit_queue(0);
          bits_queued  <= bits_queued - 1;
        else
          sync_o      <= '0';
          bit_valid_o <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
