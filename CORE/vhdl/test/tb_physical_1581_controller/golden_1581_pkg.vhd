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

end package body golden_1581_pkg;
