-------------------------------------------------------------------------------
-- tb_clk_models: behavioral models of the Xilinx primitives used by
-- CORE/vhdl/clk.vhd, for tb_clk only
--
-- The shared analysis stub doc/dev-ntsc/tools/stubs/unisim_vcomponents.vhd
-- declares the components but has no entities behind them. run_w1.sh compiles
-- that stub package and this file into a bench-local library "unisim", so the
-- component instances in clk.vhd bind to the entities below. The stub itself
-- stays unchanged.
--
--   MMCME2_ADV    CLKOUT0 free-runs at
--                 CLKIN1_PERIOD x DIVCLK_DIVIDE x CLKOUT0_DIVIDE_F / CLKFBOUT_MULT_F
--                 once CLKIN1 toggles. LOCKED rises after C_LOCK_EDGES rising
--                 edges of CLKIN1. The model asserts the Artix-7 limits used
--                 by doc/dev-ntsc/tools/ntsc_clocks.py (VCO 600 to 1200 MHz,
--                 PFD 10 to 450 MHz, M and O0 in steps of 0.125) and prints its
--                 configuration. tb_clk_ctrl_pkg.mmcm_hold_unlocked lets the
--                 bench force LOCKED of one of the four core MMCMs to '0'.
--   BUFGMUX_CTRL  Glitch-free model of a BUFGCTRL used as a 2:1 mux: after a
--                 change of S the output follows the old clock until its next
--                 falling edge, then stays low until the next falling edge of
--                 the new clock, then follows the new clock.
--   BUFG          O <= I.
--
-- These are models, not the Xilinx primitives: they check the wiring and the
-- generics of clk.vhd, not the silicon behavior.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package tb_clk_ctrl_pkg is
   -- index 0 = i_clk_c64_orig, 1 = i_clk_c64_slow, 2 = i_clk_c64_ntsc, 3 = i_clk_c64_ntsc_ff
   signal mmcm_hold_unlocked : std_logic_vector(0 to 3) := (others => '0');

   -- index of an instance path in mmcm_hold_unlocked, -1 if it is none of the four
   function mmcm_index(path : string) return integer;
end package tb_clk_ctrl_pkg;

package body tb_clk_ctrl_pkg is

   function contains(s, sub : string) return boolean is
   begin
      if sub'length > s'length then
         return false;
      end if;
      for i in s'low to s'high - sub'length + 1 loop
         if s(i to i + sub'length - 1) = sub then
            return true;
         end if;
      end loop;
      return false;
   end function contains;

   function mmcm_index(path : string) return integer is
   begin
      if    contains(path, ":i_clk_c64_orig")    then return 0;
      elsif contains(path, ":i_clk_c64_slow")    then return 1;
      elsif contains(path, ":i_clk_c64_ntsc_ff") then return 3;
      elsif contains(path, ":i_clk_c64_ntsc")    then return 2;
      end if;
      return -1;
   end function mmcm_index;

end package body tb_clk_ctrl_pkg;

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library std;
use std.textio.all;

use work.tb_clk_ctrl_pkg.all;

entity MMCME2_ADV is
   generic (
      BANDWIDTH             : string  := "OPTIMIZED";
      CLKFBOUT_MULT_F       : real    := 5.000;
      CLKFBOUT_PHASE        : real    := 0.000;
      CLKFBOUT_USE_FINE_PS  : boolean := FALSE;
      CLKIN1_PERIOD         : real    := 0.000;
      CLKIN2_PERIOD         : real    := 0.000;
      CLKOUT0_DIVIDE_F      : real    := 1.000;
      CLKOUT0_DUTY_CYCLE    : real    := 0.500;
      CLKOUT0_PHASE         : real    := 0.000;
      CLKOUT0_USE_FINE_PS   : boolean := FALSE;
      CLKOUT1_DIVIDE        : integer := 1;
      CLKOUT1_DUTY_CYCLE    : real    := 0.500;
      CLKOUT1_PHASE         : real    := 0.000;
      CLKOUT1_USE_FINE_PS   : boolean := FALSE;
      CLKOUT2_DIVIDE        : integer := 1;
      CLKOUT2_DUTY_CYCLE    : real    := 0.500;
      CLKOUT2_PHASE         : real    := 0.000;
      CLKOUT2_USE_FINE_PS   : boolean := FALSE;
      CLKOUT3_DIVIDE        : integer := 1;
      CLKOUT3_DUTY_CYCLE    : real    := 0.500;
      CLKOUT3_PHASE         : real    := 0.000;
      CLKOUT3_USE_FINE_PS   : boolean := FALSE;
      CLKOUT4_DIVIDE        : integer := 1;
      CLKOUT4_DUTY_CYCLE    : real    := 0.500;
      CLKOUT4_PHASE         : real    := 0.000;
      CLKOUT4_USE_FINE_PS   : boolean := FALSE;
      CLKOUT5_DIVIDE        : integer := 1;
      CLKOUT5_DUTY_CYCLE    : real    := 0.500;
      CLKOUT5_PHASE         : real    := 0.000;
      CLKOUT5_USE_FINE_PS   : boolean := FALSE;
      CLKOUT6_DIVIDE        : integer := 1;
      CLKOUT6_DUTY_CYCLE    : real    := 0.500;
      CLKOUT6_PHASE         : real    := 0.000;
      CLKOUT6_USE_FINE_PS   : boolean := FALSE;
      CLKOUT4_CASCADE       : boolean := FALSE;
      COMPENSATION          : string  := "ZHOLD";
      DIVCLK_DIVIDE         : integer := 1;
      IS_CLKINSEL_INVERTED  : bit     := '0';
      IS_PSEN_INVERTED      : bit     := '0';
      IS_PSINCDEC_INVERTED  : bit     := '0';
      IS_PWRDWN_INVERTED    : bit     := '0';
      IS_RST_INVERTED       : bit     := '0';
      REF_JITTER1           : real    := 0.010;
      REF_JITTER2           : real    := 0.010;
      SS_EN                 : string  := "FALSE";
      SS_MODE               : string  := "CENTER_HIGH";
      SS_MOD_PERIOD         : integer := 10000;
      STARTUP_WAIT          : boolean := FALSE
   );
   port (
      CLKFBOUT              : out std_ulogic;
      CLKFBOUTB             : out std_ulogic;
      CLKFBSTOPPED          : out std_ulogic;
      CLKINSTOPPED          : out std_ulogic;
      CLKOUT0               : out std_ulogic;
      CLKOUT1               : out std_ulogic;
      CLKOUT2               : out std_ulogic;
      CLKOUT3               : out std_ulogic;
      CLKOUT4               : out std_ulogic;
      CLKOUT5               : out std_ulogic;
      CLKOUT6               : out std_ulogic;
      CLKOUT0B              : out std_ulogic;
      CLKOUT1B              : out std_ulogic;
      CLKOUT2B              : out std_ulogic;
      CLKOUT3B              : out std_ulogic;
      DRDY                  : out std_ulogic;
      LOCKED                : out std_ulogic;
      PSDONE                : out std_ulogic;
      DO                    : out std_logic_vector(15 downto 0);
      CLKFBIN               : in  std_ulogic;
      CLKIN1                : in  std_ulogic;
      CLKIN2                : in  std_ulogic;
      CLKINSEL              : in  std_ulogic;
      DCLK                  : in  std_ulogic;
      DEN                   : in  std_ulogic;
      DWE                   : in  std_ulogic;
      PSCLK                 : in  std_ulogic;
      PSEN                  : in  std_ulogic;
      PSINCDEC              : in  std_ulogic;
      PWRDWN                : in  std_ulogic;
      RST                   : in  std_ulogic;
      DADDR                 : in  std_logic_vector(6 downto 0);
      DI                    : in  std_logic_vector(15 downto 0)
   );
end entity MMCME2_ADV;

architecture behav of MMCME2_ADV is

   constant C_LOCK_EDGES : natural := 200;   -- 2 us at 100 MHz

   constant C_PATH       : string  := MMCME2_ADV'path_name;
   constant C_INDEX      : integer := mmcm_index(C_PATH);
   constant C_VCO_MHZ    : real    := 1000.0 / CLKIN1_PERIOD * CLKFBOUT_MULT_F / real(DIVCLK_DIVIDE);
   constant C_PFD_MHZ    : real    := 1000.0 / CLKIN1_PERIOD / real(DIVCLK_DIVIDE);
   constant C_OUT_HZ     : real    := C_VCO_MHZ * 1.0e6 / CLKOUT0_DIVIDE_F;
   constant C_PERIOD     : time    := CLKIN1_PERIOD * real(DIVCLK_DIVIDE) * CLKOUT0_DIVIDE_F /
                                      CLKFBOUT_MULT_F * 1 ns;

   signal clkin_edges    : natural := 0;
   signal clkout         : std_ulogic := '0';

   function is_eighth(x : real) return boolean is
   begin
      return abs(x * 8.0 - round(x * 8.0)) < 1.0e-9;
   end function is_eighth;

begin

   config_check : process
      variable l : line;
   begin
      write(l, string'("MMCME2_ADV model ") & C_PATH & string'(": M=") & real'image(CLKFBOUT_MULT_F) &
               string'(" D=") & integer'image(DIVCLK_DIVIDE) & string'(" O0=") &
               real'image(CLKOUT0_DIVIDE_F) & string'(" VCO=") & real'image(C_VCO_MHZ) &
               string'(" MHz CLKOUT0=") & real'image(C_OUT_HZ) & string'(" Hz"));
      writeline(output, l);
      assert C_VCO_MHZ >= 600.0 and C_VCO_MHZ <= 1200.0
         report "MMCME2_ADV model " & C_PATH & ": VCO out of range (600 to 1200 MHz)" severity error;
      assert C_PFD_MHZ >= 10.0 and C_PFD_MHZ <= 450.0
         report "MMCME2_ADV model " & C_PATH & ": PFD out of range (10 to 450 MHz)" severity error;
      assert CLKFBOUT_MULT_F >= 2.0 and CLKFBOUT_MULT_F <= 64.0 and is_eighth(CLKFBOUT_MULT_F)
         report "MMCME2_ADV model " & C_PATH & ": illegal CLKFBOUT_MULT_F" severity error;
      assert CLKOUT0_DIVIDE_F >= 2.0 and CLKOUT0_DIVIDE_F <= 128.0 and is_eighth(CLKOUT0_DIVIDE_F)
         report "MMCME2_ADV model " & C_PATH & ": illegal CLKOUT0_DIVIDE_F" severity error;
      assert DIVCLK_DIVIDE >= 1 and DIVCLK_DIVIDE <= 106
         report "MMCME2_ADV model " & C_PATH & ": illegal DIVCLK_DIVIDE" severity error;
      assert C_INDEX >= 0
         report "MMCME2_ADV model " & C_PATH & ": not one of the four core MMCMs" severity error;
      wait;
   end process config_check;

   count_clkin : process (CLKIN1)
   begin
      if rising_edge(CLKIN1) and clkin_edges < C_LOCK_EDGES then
         clkin_edges <= clkin_edges + 1;
      end if;
   end process count_clkin;

   gen_clkout : process
   begin
      wait until rising_edge(CLKIN1);
      loop
         clkout <= '1';
         wait for C_PERIOD / 2;
         clkout <= '0';
         wait for C_PERIOD - C_PERIOD / 2;
      end loop;
   end process gen_clkout;

   CLKOUT0      <= clkout;
   LOCKED       <= '1' when clkin_edges >= C_LOCK_EDGES and
                            (C_INDEX < 0 or mmcm_hold_unlocked(C_INDEX) = '0') else '0';
   CLKFBOUT     <= '0';
   CLKFBOUTB    <= '1';
   CLKFBSTOPPED <= '0';
   CLKINSTOPPED <= '0';
   CLKOUT1      <= '0';
   CLKOUT2      <= '0';
   CLKOUT3      <= '0';
   CLKOUT4      <= '0';
   CLKOUT5      <= '0';
   CLKOUT6      <= '0';
   CLKOUT0B     <= not clkout;
   CLKOUT1B     <= '1';
   CLKOUT2B     <= '1';
   CLKOUT3B     <= '1';
   DRDY         <= '0';
   PSDONE       <= '0';
   DO           <= (others => '0');

end architecture behav;

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity BUFGMUX_CTRL is
   port (
      O                     : out std_ulogic;
      I0                    : in  std_ulogic;
      I1                    : in  std_ulogic;
      S                     : in  std_ulogic
   );
end entity BUFGMUX_CTRL;

architecture behav of BUFGMUX_CTRL is
   signal cur_sel : std_ulogic := '0';   -- input that drives O while en = '1'
   signal tgt_sel : std_ulogic := '0';   -- input to switch to while en = '0'
   signal en      : std_ulogic := '1';
begin

   process (I0, I1)
   begin
      if en = '1' then
         if S /= cur_sel and (S = '0' or S = '1') then
            if (cur_sel = '0' and falling_edge(I0)) or (cur_sel = '1' and falling_edge(I1)) then
               en      <= '0';           -- old clock just went low: hold O low
               tgt_sel <= S;
            end if;
         end if;
      else
         if (tgt_sel = '0' and falling_edge(I0)) or (tgt_sel = '1' and falling_edge(I1)) then
            cur_sel <= tgt_sel;          -- new clock is low now: follow it from its next rising edge
            en      <= '1';
         end if;
      end if;
   end process;

   O <= '0' when en = '0' else I0 when cur_sel = '0' else I1;

end architecture behav;

-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity BUFG is
   port (
      O                     : out std_ulogic;
      I                     : in  std_ulogic
   );
end entity BUFG;

architecture behav of BUFG is
begin
   O <= I;
end architecture behav;
