-------------------------------------------------------------------------------
-- physical_1581_crc.vhd
--
-- CRC-16/CCITT-FALSE generator/checker for DD-MFM address-mark and data fields.
--   polynomial 0x1021, init 0xFFFF, MSB-first, no reflection, no final XOR.
--   "CRC good" == crc_value_o = 0x0000 after the two stored CRC bytes are fed.
--   State after A1 A1 A1 == 0xCDB4.
--
-- Adapted from mega65-core src/vhdl/crc1581.vhdl @ a9158930
--   (Paul Gardner-Stephen / MEGA65, LGPLv3). Changes: removed report/debugtools/
--   TextIO and the sim-only `id` generic; renamed ports to the project _i/_o
--   convention; kept the bit-exact tap logic and the reset-and-feed-same-cycle
--   fix. Feed one byte per crc_feed_i pulse; the engine buffers one pending byte
--   and clears crc_ready_o for 8 clocks while it shifts.
--
-- C64MEGA65 project.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity physical_1581_crc is
  port (
    clk_i       : in  std_logic;
    crc_byte_i  : in  unsigned(7 downto 0);
    crc_feed_i  : in  std_logic;                       -- pulse to feed crc_byte_i
    crc_reset_i : in  std_logic;                       -- preset to 0xFFFF
    crc_ready_o : out std_logic := '1';                -- '1' == idle, value valid
    crc_value_o : out unsigned(15 downto 0) := x"FFFF"
  );
end entity physical_1581_crc;

architecture rtl of physical_1581_crc is
  constant crc_init : unsigned(15 downto 0) := x"FFFF";
  signal value         : unsigned(15 downto 0) := crc_init;
  signal ready         : std_logic := '1';
  signal bits_left     : integer range 0 to 8 := 0;
  signal shreg         : unsigned(7 downto 0) := x"00";
  signal byte_buffered : std_logic := '0';
  signal buffered_byte : unsigned(7 downto 0) := x"00";
begin

  process (clk_i)
  begin
    if rising_edge(clk_i) then
      -- registered outputs (mirror upstream one-cycle output register)
      crc_ready_o <= ready;
      crc_value_o <= value;

      -- accept a byte to buffer (one deep)
      if crc_feed_i = '1' then
        byte_buffered <= '1';
        buffered_byte <= crc_byte_i;
      end if;

      if crc_reset_i = '1' then
        value         <= crc_init;
        ready         <= '1';
        -- clear the buffered byte unless one is being fed the same cycle
        byte_buffered <= crc_feed_i;
      elsif bits_left /= 0 then
        ready <= '0';
        -- shift one bit through the CRC (feedback = incoming MSB xor value(15))
        value(15 downto 1) <= value(14 downto 0);
        value(12)          <= value(11) xor (shreg(7) xor value(15));
        value(5)           <= value(4)  xor (shreg(7) xor value(15));
        value(0)           <= (shreg(7) xor value(15));
        shreg(7 downto 1)  <= shreg(6 downto 0);
        bits_left          <= bits_left - 1;
      else
        if byte_buffered = '1' then
          bits_left     <= 8;
          shreg         <= buffered_byte;
          ready         <= '0';
          byte_buffered <= '0';
        else
          ready <= '1';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
