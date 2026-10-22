-- Analysis stub for the Xilinx UNISIM library (package unisim.vcomponents).
-- Used only by doc/dev-ntsc/tools/analyze.sh so that ghdl can analyze files that
-- instantiate Xilinx primitives as components. Generic and port names, types and
-- defaults follow the Xilinx 7 Series Libraries Guide (UG953). This is NOT a
-- simulation model: there are no entities behind these components.
-- Compile into a library named unisim: ghdl -a --std=08 --work=unisim ...

library ieee;
use ieee.std_logic_1164.all;

package vcomponents is

   component MMCME2_ADV is
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
   end component MMCME2_ADV;

   component MMCME2_BASE is
      generic (
         BANDWIDTH             : string  := "OPTIMIZED";
         CLKFBOUT_MULT_F       : real    := 5.000;
         CLKFBOUT_PHASE        : real    := 0.000;
         CLKIN1_PERIOD         : real    := 0.000;
         CLKOUT0_DIVIDE_F      : real    := 1.000;
         CLKOUT0_DUTY_CYCLE    : real    := 0.500;
         CLKOUT0_PHASE         : real    := 0.000;
         CLKOUT1_DIVIDE        : integer := 1;
         CLKOUT1_DUTY_CYCLE    : real    := 0.500;
         CLKOUT1_PHASE         : real    := 0.000;
         CLKOUT2_DIVIDE        : integer := 1;
         CLKOUT2_DUTY_CYCLE    : real    := 0.500;
         CLKOUT2_PHASE         : real    := 0.000;
         CLKOUT3_DIVIDE        : integer := 1;
         CLKOUT3_DUTY_CYCLE    : real    := 0.500;
         CLKOUT3_PHASE         : real    := 0.000;
         CLKOUT4_DIVIDE        : integer := 1;
         CLKOUT4_DUTY_CYCLE    : real    := 0.500;
         CLKOUT4_PHASE         : real    := 0.000;
         CLKOUT5_DIVIDE        : integer := 1;
         CLKOUT5_DUTY_CYCLE    : real    := 0.500;
         CLKOUT5_PHASE         : real    := 0.000;
         CLKOUT6_DIVIDE        : integer := 1;
         CLKOUT6_DUTY_CYCLE    : real    := 0.500;
         CLKOUT6_PHASE         : real    := 0.000;
         CLKOUT4_CASCADE       : boolean := FALSE;
         DIVCLK_DIVIDE         : integer := 1;
         REF_JITTER1           : real    := 0.010;
         STARTUP_WAIT          : boolean := FALSE
      );
      port (
         CLKFBOUT              : out std_ulogic;
         CLKFBOUTB             : out std_ulogic;
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
         LOCKED                : out std_ulogic;
         CLKFBIN               : in  std_ulogic;
         CLKIN1                : in  std_ulogic;
         PWRDWN                : in  std_ulogic;
         RST                   : in  std_ulogic
      );
   end component MMCME2_BASE;

   component PLLE2_BASE is
      generic (
         BANDWIDTH             : string  := "OPTIMIZED";
         CLKFBOUT_MULT         : integer := 5;
         CLKFBOUT_PHASE        : real    := 0.000;
         CLKIN1_PERIOD         : real    := 0.000;
         CLKOUT0_DIVIDE        : integer := 1;
         CLKOUT0_DUTY_CYCLE    : real    := 0.500;
         CLKOUT0_PHASE         : real    := 0.000;
         CLKOUT1_DIVIDE        : integer := 1;
         CLKOUT1_DUTY_CYCLE    : real    := 0.500;
         CLKOUT1_PHASE         : real    := 0.000;
         CLKOUT2_DIVIDE        : integer := 1;
         CLKOUT2_DUTY_CYCLE    : real    := 0.500;
         CLKOUT2_PHASE         : real    := 0.000;
         CLKOUT3_DIVIDE        : integer := 1;
         CLKOUT3_DUTY_CYCLE    : real    := 0.500;
         CLKOUT3_PHASE         : real    := 0.000;
         CLKOUT4_DIVIDE        : integer := 1;
         CLKOUT4_DUTY_CYCLE    : real    := 0.500;
         CLKOUT4_PHASE         : real    := 0.000;
         CLKOUT5_DIVIDE        : integer := 1;
         CLKOUT5_DUTY_CYCLE    : real    := 0.500;
         CLKOUT5_PHASE         : real    := 0.000;
         DIVCLK_DIVIDE         : integer := 1;
         REF_JITTER1           : real    := 0.010;
         STARTUP_WAIT          : string  := "FALSE"
      );
      port (
         CLKFBOUT              : out std_ulogic;
         CLKOUT0               : out std_ulogic;
         CLKOUT1               : out std_ulogic;
         CLKOUT2               : out std_ulogic;
         CLKOUT3               : out std_ulogic;
         CLKOUT4               : out std_ulogic;
         CLKOUT5               : out std_ulogic;
         LOCKED                : out std_ulogic;
         CLKFBIN               : in  std_ulogic;
         CLKIN1                : in  std_ulogic;
         PWRDWN                : in  std_ulogic;
         RST                   : in  std_ulogic
      );
   end component PLLE2_BASE;

   component PLLE2_ADV is
      generic (
         BANDWIDTH             : string  := "OPTIMIZED";
         CLKFBOUT_MULT         : integer := 5;
         CLKFBOUT_PHASE        : real    := 0.000;
         CLKIN1_PERIOD         : real    := 0.000;
         CLKIN2_PERIOD         : real    := 0.000;
         CLKOUT0_DIVIDE        : integer := 1;
         CLKOUT0_DUTY_CYCLE    : real    := 0.500;
         CLKOUT0_PHASE         : real    := 0.000;
         CLKOUT1_DIVIDE        : integer := 1;
         CLKOUT1_DUTY_CYCLE    : real    := 0.500;
         CLKOUT1_PHASE         : real    := 0.000;
         CLKOUT2_DIVIDE        : integer := 1;
         CLKOUT2_DUTY_CYCLE    : real    := 0.500;
         CLKOUT2_PHASE         : real    := 0.000;
         CLKOUT3_DIVIDE        : integer := 1;
         CLKOUT3_DUTY_CYCLE    : real    := 0.500;
         CLKOUT3_PHASE         : real    := 0.000;
         CLKOUT4_DIVIDE        : integer := 1;
         CLKOUT4_DUTY_CYCLE    : real    := 0.500;
         CLKOUT4_PHASE         : real    := 0.000;
         CLKOUT5_DIVIDE        : integer := 1;
         CLKOUT5_DUTY_CYCLE    : real    := 0.500;
         CLKOUT5_PHASE         : real    := 0.000;
         COMPENSATION          : string  := "ZHOLD";
         DIVCLK_DIVIDE         : integer := 1;
         IS_CLKINSEL_INVERTED  : bit     := '0';
         IS_PWRDWN_INVERTED    : bit     := '0';
         IS_RST_INVERTED       : bit     := '0';
         REF_JITTER1           : real    := 0.010;
         REF_JITTER2           : real    := 0.010;
         STARTUP_WAIT          : string  := "FALSE"
      );
      port (
         CLKFBOUT              : out std_ulogic;
         CLKOUT0               : out std_ulogic;
         CLKOUT1               : out std_ulogic;
         CLKOUT2               : out std_ulogic;
         CLKOUT3               : out std_ulogic;
         CLKOUT4               : out std_ulogic;
         CLKOUT5               : out std_ulogic;
         LOCKED                : out std_ulogic;
         DRDY                  : out std_ulogic;
         DO                    : out std_logic_vector(15 downto 0);
         CLKFBIN               : in  std_ulogic;
         CLKIN1                : in  std_ulogic;
         CLKIN2                : in  std_ulogic;
         CLKINSEL              : in  std_ulogic;
         DCLK                  : in  std_ulogic;
         DEN                   : in  std_ulogic;
         DWE                   : in  std_ulogic;
         PWRDWN                : in  std_ulogic;
         RST                   : in  std_ulogic;
         DADDR                 : in  std_logic_vector(6 downto 0);
         DI                    : in  std_logic_vector(15 downto 0)
      );
   end component PLLE2_ADV;

   component BUFG is
      port (
         O                     : out std_ulogic;
         I                     : in  std_ulogic
      );
   end component BUFG;

   component BUFH is
      port (
         O                     : out std_ulogic;
         I                     : in  std_ulogic
      );
   end component BUFH;

   component BUFGCE is
      port (
         O                     : out std_ulogic;
         CE                    : in  std_ulogic;
         I                     : in  std_ulogic
      );
   end component BUFGCE;

   component BUFGMUX is
      generic (
         CLK_SEL_TYPE          : string  := "SYNC"
      );
      port (
         O                     : out std_ulogic;
         I0                    : in  std_ulogic;
         I1                    : in  std_ulogic;
         S                     : in  std_ulogic
      );
   end component BUFGMUX;

   component BUFGMUX_CTRL is
      port (
         O                     : out std_ulogic;
         I0                    : in  std_ulogic;
         I1                    : in  std_ulogic;
         S                     : in  std_ulogic
      );
   end component BUFGMUX_CTRL;

   component BUFGCTRL is
      generic (
         INIT_OUT              : integer := 0;
         PRESELECT_I0          : boolean := FALSE;
         PRESELECT_I1          : boolean := FALSE
      );
      port (
         O                     : out std_ulogic;
         CE0                   : in  std_ulogic;
         CE1                   : in  std_ulogic;
         I0                    : in  std_ulogic;
         I1                    : in  std_ulogic;
         IGNORE0               : in  std_ulogic;
         IGNORE1               : in  std_ulogic;
         S0                    : in  std_ulogic;
         S1                    : in  std_ulogic
      );
   end component BUFGCTRL;

   component IBUF is
      generic (
         CAPACITANCE           : string  := "DONT_CARE";
         IBUF_DELAY_VALUE      : string  := "0";
         IBUF_LOW_PWR          : boolean := TRUE;
         IFD_DELAY_VALUE       : string  := "AUTO";
         IOSTANDARD            : string  := "DEFAULT"
      );
      port (
         O                     : out std_ulogic;
         I                     : in  std_ulogic
      );
   end component IBUF;

   component OBUF is
      generic (
         CAPACITANCE           : string  := "DONT_CARE";
         DRIVE                 : integer := 12;
         IOSTANDARD            : string  := "DEFAULT";
         SLEW                  : string  := "SLOW"
      );
      port (
         O                     : out std_ulogic;
         I                     : in  std_ulogic
      );
   end component OBUF;

   component IBUFDS is
      generic (
         DIFF_TERM             : boolean := FALSE;
         IBUF_LOW_PWR          : boolean := TRUE;
         IOSTANDARD            : string  := "DEFAULT"
      );
      port (
         O                     : out std_ulogic;
         I                     : in  std_ulogic;
         IB                    : in  std_ulogic
      );
   end component IBUFDS;

   component OBUFDS is
      generic (
         IOSTANDARD            : string  := "DEFAULT";
         SLEW                  : string  := "SLOW"
      );
      port (
         O                     : out std_ulogic;
         OB                    : out std_ulogic;
         I                     : in  std_ulogic
      );
   end component OBUFDS;

   component ODDR is
      generic (
         DDR_CLK_EDGE          : string  := "OPPOSITE_EDGE";
         INIT                  : bit     := '0';
         SRTYPE                : string  := "SYNC"
      );
      port (
         Q                     : out std_ulogic;
         C                     : in  std_ulogic;
         CE                    : in  std_ulogic;
         D1                    : in  std_ulogic;
         D2                    : in  std_ulogic;
         R                     : in  std_ulogic;
         S                     : in  std_ulogic
      );
   end component ODDR;
end package vcomponents;
