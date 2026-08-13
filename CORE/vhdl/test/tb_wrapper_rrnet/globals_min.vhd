-- Minimal stand-in for CORE/vhdl/globals.vhd: eth_wrapper.vhd uses exactly one
-- constant from it. Value copied verbatim from the branch under test.
package globals is
  constant ETH_FIFO_ADDR_BITS : natural := 12;
end package globals;
