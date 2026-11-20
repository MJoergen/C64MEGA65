-------------------------------------------------------------------------------
-- tb_hdmi_raw_wiring_pkg: signals that the stand-in of the scaler
-- (ascal_timing.vhd) exports to the bench (issue #184)
--
-- The bench times the start of its core model relative to the start of an HDMI
-- picture; it sees the output syncs of the scaler through these two signals.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package tb_hdmi_raw_wiring_pkg is
   signal scaler_vs : std_logic := '0';    -- o_vs of the scaler
   signal scaler_de : std_logic := '0';    -- o_de of the scaler
end package tb_hdmi_raw_wiring_pkg;
