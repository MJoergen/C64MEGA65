-------------------------------------------------------------------------------
-- tb_video_filters.vhd
--
-- Stand-alone unit test of video_filters (the read-only QNICE block RAM that
-- holds the three C64-only polyphase coefficient blobs). It reads all 768
-- words back the way QNICE does -- falling-edge port B, one address per cycle
-- -- and prints them as "<index> <value>", so the whole data path can be
-- checked without a bitstream:
--   * video_filters.rom is serialized in the format the preload expects,
--   * the bit order survives the textio read into the BRAM,
--   * every slot sits at slot * 256, and
--   * the registered port-B read returns the right word.
--
-- Slot 0 = GS_Sharpness_050, slot 1 = CRT_Sim_Composite_H,
-- slot 2 = CRT_Sim_SVideo_H. Each block of 256 words must equal the .DW rows
-- of the matching file in M2M/video_filters/.
--
-- Run it from CORE/vhdl, NOT from this directory: the ROM_FILE path inside
-- video_filters.vhd is relative and has to resolve the way it does during
-- synthesis.
--
--   cd CORE/vhdl
--   W=$(mktemp -d)
--   ghdl -a --std=08 --workdir=$W ../../M2M/vhdl/tdp_ram.vhd \
--        ../../M2M/vhdl/2port2clk_ram.vhd video_filters.vhd \
--        test/tb_video_filters/tb_video_filters.vhd
--   ghdl --elab-run --std=08 --workdir=$W tb_video_filters --stop-time=100us
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_video_filters is
end entity tb_video_filters;

architecture sim of tb_video_filters is
   signal clk   : std_logic := '0';
   signal addr  : std_logic_vector(9 downto 0) := (others => '0');
   signal data  : std_logic_vector(15 downto 0);
   signal done  : boolean := false;
begin

   clk <= not clk after 5 ns when not done else '0';

   dut : entity work.video_filters
      port map (
         qnice_clk_i  => clk,
         qnice_addr_i => addr,
         qnice_data_o => data
      );

   stim : process
      variable l : line;
      variable v : integer;
   begin
      -- port B is a falling-edge read, so present the address, wait for the
      -- falling edge to latch it, then sample after the output register settles
      for i in 0 to 767 loop
         addr <= std_logic_vector(to_unsigned(i, 10));
         wait until falling_edge(clk);
         wait for 1 ns;
         v := to_integer(unsigned(data));
         write(l, i);
         write(l, string'(" "));
         write(l, v);
         writeline(output, l);
      end loop;
      done <= true;
      wait;
   end process stim;

end architecture sim;
