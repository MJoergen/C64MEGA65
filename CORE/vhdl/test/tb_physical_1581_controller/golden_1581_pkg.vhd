-------------------------------------------------------------------------------
-- golden_1581_pkg.vhd   (simulation only)
--
-- Deterministic "golden" disk contents for the physical internal 1581
-- controller testbenches. Both the behavioural floppy-mechanism model
-- (mech_model_1581) and the controller test call these two pure functions, so
-- the flux that goes onto the wire and the bytes the test expects back are
-- generated from the SAME source of truth -- no shared file, no state.
--
--   lba1581(cyl, side, sec)          -> logical block number (sec is 1..10)
--   golden_payload(cyl, side, sec, off) -> the byte at data offset `off`
--
-- golden_payload embeds a small self-describing identity at the head of every
-- sector (cyl / side / sector / lba-lo / lba-hi) so a captured sector can be
-- eyeballed, then a mixed PRBS-like value for the remaining bytes so that a
-- wrong-sector read is caught byte-for-byte. Both functions are total and
-- side-effect free; feeding them the same arguments always yields the same
-- result.
--
-- The writable mechanism model (mech_model_1581, G_WRITABLE) lays its seed
-- tracks with seed_payload (key 0 = golden_payload, any other key a different
-- deterministic payload, so a write scenario can overwrite a track whose old
-- content differs from what it writes) in the layout described by the
-- C_SEED_* constants: C_SEED_LEAD x 4E after the index, then ten records of
-- C_SEED_REC byte-times, 4E up to the end of the revolution. seed_id_crc_end
-- gives the rotational position (50 MHz cycles after the index) of the end of
-- the last channel cell of record r's ID CRC.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package golden_1581_pkg is

  -- Logical block address. Physical 1581 geometry: 2 sides, 10 sectors/track,
  -- sector numbers 1..10. side is 0 or 1.
  function lba1581(cyl, side, sec : integer) return integer;

  -- Deterministic byte for a given cylinder / side / sector / data offset.
  -- Returns an 8-bit value. Pure: no signals, no shared state.
  function golden_payload(cyl, side, sec, off : integer) return unsigned;

  -- Seed payload of the writable model; key 0 is golden_payload.
  function seed_payload(key, cyl, side, sec, off : integer) return unsigned;

  -- seed track layout of the writable model (byte-times of 1600 cycles)
  constant C_SEED_LEAD   : integer := 32;    -- 4E after the index
  constant C_SEED_REC    : integer := 604;   -- 12+3+1+4+2 + 22 + 12+3+1+512+2 + 30
  constant C_SEED_ID_END : integer := 22;    -- ID CRC end, bytes into a record
  constant C_SEED_BYTE_CYC : integer := 1600;
  function seed_id_crc_end(r : integer) return integer;   -- r = 1..10

end package golden_1581_pkg;

package body golden_1581_pkg is

  function lba1581(cyl, side, sec : integer) return integer is
  begin
    return cyl * 20 + side * 10 + sec - 1;
  end function;

  function golden_payload(cyl, side, sec, off : integer) return unsigned is
    variable lba : integer;
  begin
    lba := lba1581(cyl, side, sec);
    case off is
      when 0      => return to_unsigned(cyl  mod 256, 8);         -- cylinder
      when 1      => return to_unsigned(side mod 256, 8);         -- side
      when 2      => return to_unsigned(sec  mod 256, 8);         -- sector
      when 3      => return to_unsigned(lba  mod 256, 8);         -- lba low
      when 4      => return to_unsigned((lba / 256) mod 256, 8);  -- lba high
      when others =>
        return to_unsigned(
          (cyl * 31 + side * 17 + sec * 7 + off * 13 + 16#5A#) mod 256, 8);
    end case;
  end function;

  function seed_payload(key, cyl, side, sec, off : integer) return unsigned is
  begin
    if key = 0 then
      return golden_payload(cyl, side, sec, off);
    end if;
    return to_unsigned((to_integer(golden_payload(cyl, side, sec, off))
                        + key * 41 + off * (2 * key + 1) + sec * 3) mod 256, 8);
  end function;

  function seed_id_crc_end(r : integer) return integer is
  begin
    return (C_SEED_LEAD + (r - 1) * C_SEED_REC + C_SEED_ID_END) * C_SEED_BYTE_CYC;
  end function;

end package body golden_1581_pkg;
