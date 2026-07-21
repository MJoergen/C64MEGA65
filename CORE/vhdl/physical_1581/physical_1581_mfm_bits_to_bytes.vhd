-------------------------------------------------------------------------------
-- physical_1581_mfm_bits_to_bytes.vhd
--
-- DD-MFM read pipeline, stage 4 of 4: bit stream -> byte framing.
--   On sync_i the decoded byte 0xA1 is emitted with sync_o and the bit counter
--   is re-aligned to the sync byte boundary. Otherwise bit_i is shifted in
--   MSB-first; on the 8th bit the assembled byte is emitted with byte_valid_o.
--
-- Adapted from mega65-core src/vhdl/mfm_bits_to_bytes.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/
--   debugtools/TextIO; renamed ports to the project _i/_o convention; added an
--   explicit synchronous reset. Framing logic kept bit-for-bit.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_bits_to_bytes is
  port (
    clk_i        : in  std_logic;
    rst_i        : in  std_logic;                      -- sync reset
    sync_i       : in  std_logic;
    bit_i        : in  std_logic;
    bit_valid_i  : in  std_logic;
    sync_o       : out std_logic := '0';
    byte_o       : out unsigned(7 downto 0) := (others => '0');
    byte_valid_o : out std_logic := '0'
  );
end entity physical_1581_mfm_bits_to_bytes;

architecture rtl of physical_1581_mfm_bits_to_bytes is
  signal partial_byte : unsigned(6 downto 0) := (others => '0');
  signal bit_count    : integer range 0 to 7 := 0;
begin

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      if rst_i = '1' then
        partial_byte <= (others => '0');
        bit_count    <= 0;
        sync_o       <= '0';
        byte_o       <= (others => '0');
        byte_valid_o <= '0';
      elsif sync_i = '1' then
        -- $A1 sync: emit it and re-align the byte boundary.
        sync_o    <= '1';
        byte_o    <= x"A1";
        bit_count <= 0;
      elsif bit_valid_i = '1' then
        if bit_count = 7 then
          -- Complete byte assembled: output it.
          byte_o(7 downto 1) <= partial_byte;
          byte_o(0)          <= bit_i;
          byte_valid_o       <= '1';
          bit_count          <= 0;
        else
          -- Shift the next bit in, MSB-first.
          byte_valid_o           <= '0';
          bit_count              <= bit_count + 1;
          partial_byte(6 downto 1) <= partial_byte(5 downto 0);
          partial_byte(0)          <= bit_i;
        end if;
      else
        byte_valid_o <= '0';
        sync_o       <= '0';
      end if;
    end if;
  end process;

end architecture rtl;
