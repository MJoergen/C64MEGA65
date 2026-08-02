----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65 (C64MEGA65)
--
-- Core-only polyphase filter coefficients as a QNICE-readable block RAM
--
-- The three C64-only HDMI filter blobs used to be #included into the QNICE
-- Shell ROM, where 3 x 256 words of pure data competed with firmware for the
-- 28672-word budget (0x0000-0x6FFF; 0x7000+ is QNICE MMIO) even though the CPU
-- never executes them: they are only ever copied into the ascal polyphase RAM.
--
-- They now live here instead, preloaded from video_filters.rom, which
-- CORE/m2m-rom/make_rom.sh regenerates from the framework blob sources under
-- M2M/video_filters/ on every build. The Shell reads this device through the
-- standard M2M 4K window as C_DEV_C64_VFILTERS (globals.vhd) and stages a blob
-- into RAM before handing it to M2M$LOAD_POLYPHASE - the framework routine
-- takes ordinary memory pointers and claims the 4K window for ascal itself, so
-- a device-resident blob cannot be passed to it directly.
--
-- Slot layout (the contract with HDMI_FLT_TABLE in m2m-rom.asm and with the
-- generator in make_rom.sh - do not reorder):
--
--    slot 0, offset 0x000 : GS_Sharpness_050      ("Smooth")
--    slot 1, offset 0x100 : CRT_Sim_Composite_H   ("CRT Composite")
--    slot 2, offset 0x200 : CRT_Sim_SVideo_H      ("CRT S-Video")
--
-- LANCZOS2_12 and SCAN_BR_110_80 are deliberately NOT here: they arrive
-- through M2M/rom/filters.asm and M2M/rom/gencfg.asm calls LOAD_ASCAL_FLT for
-- them at boot, so they stay in the Shell ROM while the framework is untouched.
--
-- Read-only: QNICE never writes this device.
--
-- done by MJoergen and sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity video_filters is
   port (
      qnice_clk_i    : in  std_logic;
      qnice_addr_i   : in  std_logic_vector(9 downto 0);   -- 768 of 1024 words used
      qnice_data_o   : out std_logic_vector(15 downto 0)
   );
end entity video_filters;

architecture beh of video_filters is

   signal zero_addr  : std_logic_vector(9 downto 0)  := (others => '0');
   signal zero_data  : std_logic_vector(15 downto 0) := (others => '0');

begin

   -- Same primitive and the same QNICE-side timing that the C64 RAM device uses
   -- (FALLING_B: QNICE expects read/write to happen at the falling clock edge),
   -- so no wait-state is needed on the QNICE bus. Port A stays unused: unlike
   -- the other core devices this block is never read by the C64 side.
   i_filter_rom : entity work.dualport_2clk_ram
      generic map (
         ROM_PRELOAD       => true,
         ROM_FILE          => "../../CORE/vhdl/video_filters.rom",
         ROM_FILE_HEX      => false,     -- 16 binary digits per line, as qasm2rom writes
         ADDR_WIDTH        => 10,
         DATA_WIDTH        => 16,
         FALLING_A         => false,
         FALLING_B         => true
      )
      port map (
         -- unused port
         clock_a           => qnice_clk_i,
         address_a         => zero_addr,
         data_a            => zero_data,
         wren_a            => '0',
         q_a               => open,

         -- QNICE
         clock_b           => qnice_clk_i,
         address_b         => qnice_addr_i,
         data_b            => zero_data,
         wren_b            => '0',
         q_b               => qnice_data_o
      ); -- i_filter_rom

end architecture beh;
