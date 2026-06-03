-- THIS IS GENERATED VHDL CODE.
-- https://bues.ch/h/crcgen
--
-- This code is Public Domain.
-- Permission to use, copy, modify, and/or distribute this software for any
-- purpose with or without fee is hereby granted.
--
-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
-- WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
-- SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
-- RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
-- NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE
-- USE OR PERFORMANCE OF THIS SOFTWARE.

-- CRC polynomial coefficients: x^16 + x^12 + x^5 + 1
--                              0x1021 (hex)
-- CRC width:                   16 bits
-- CRC shift direction:         left (big endian)
-- Input word width:            8 bits

library ieee;
  use ieee.std_logic_1164.all;

entity crc is
  port (
    crc_i  : in    std_logic_vector(15 downto 0);
    data_i : in    std_logic_vector(7 downto 0);
    crc_o  : out   std_logic_vector(15 downto 0)
  );
end entity crc;

architecture synthesis of crc is

begin

  crc_o(0)  <= crc_i(8) xor crc_i(12) xor data_i(0) xor data_i(4);
  crc_o(1)  <= crc_i(9) xor crc_i(13) xor data_i(1) xor data_i(5);
  crc_o(2)  <= crc_i(10) xor crc_i(14) xor data_i(2) xor data_i(6);
  crc_o(3)  <= crc_i(11) xor crc_i(15) xor data_i(3) xor data_i(7);
  crc_o(4)  <= crc_i(12) xor data_i(4);
  crc_o(5)  <= crc_i(8) xor crc_i(12) xor crc_i(13) xor data_i(0) xor data_i(4) xor data_i(5);
  crc_o(6)  <= crc_i(9) xor crc_i(13) xor crc_i(14) xor data_i(1) xor data_i(5) xor data_i(6);
  crc_o(7)  <= crc_i(10) xor crc_i(14) xor crc_i(15) xor data_i(2) xor data_i(6) xor data_i(7);
  crc_o(8)  <= crc_i(0) xor crc_i(11) xor crc_i(15) xor data_i(3) xor data_i(7);
  crc_o(9)  <= crc_i(1) xor crc_i(12) xor data_i(4);
  crc_o(10) <= crc_i(2) xor crc_i(13) xor data_i(5);
  crc_o(11) <= crc_i(3) xor crc_i(14) xor data_i(6);
  crc_o(12) <= crc_i(4) xor crc_i(8) xor crc_i(12) xor crc_i(15) xor data_i(0) xor data_i(4) xor data_i(7);
  crc_o(13) <= crc_i(5) xor crc_i(9) xor crc_i(13) xor data_i(1) xor data_i(5);
  crc_o(14) <= crc_i(6) xor crc_i(10) xor crc_i(14) xor data_i(2) xor data_i(6);
  crc_o(15) <= crc_i(7) xor crc_i(11) xor crc_i(15) xor data_i(3) xor data_i(7);

end architecture synthesis;

