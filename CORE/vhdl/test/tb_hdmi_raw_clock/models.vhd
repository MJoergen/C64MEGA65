-------------------------------------------------------------------------------
-- Simulation models of the Xilinx primitives that video_out_clock.vhd
-- instantiates (MMCME2_ADV, BUFG, BUFGMUX_CTRL), for tb_hdmi_raw_clock.
--
-- They are compiled into the work library, so the component instances of
-- video_out_clock.vhd (declared in the analysis stub of unisim.vcomponents,
-- doc/dev-ntsc/tools/stubs) bind to them by default. The generic and port lists
-- of MMCME2_ADV are those of the stub.
--
-- MMCME2_ADV is a model of the DRP port and of reset and lock only:
--   * 128 DRP registers of 16 bits with a fixed start pattern (so that the
--     read-modify-write of the loader is visible in the written values)
--   * DRDY three DCLK cycles after DEN; DO holds the register value with DRDY
--   * LOCKED rises C_LOCK_TIME after RST falls and falls with RST
--   * CLKOUT1 runs with C_CLKOUT1_PERIOD, CLKOUT0 five times faster, both only
--     while LOCKED (the generics and the register contents do not change them)
-- Every DRP access, every change of RST and LOCKED is printed as a line
--   LOG <time in ps> RD <address> <data> | WR <address> <data> | RST <v> | LOCKED <v>
-- and a DRP access while RST is not '1' prints "LOG <time> ERROR ...".
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

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

architecture model of MMCME2_ADV is

   constant C_LOCK_TIME      : time := 3 us;
   constant C_CLKOUT1_PERIOD : time := 13 ns;

   signal locked_i : std_ulogic := '0';
   signal clk1     : std_ulogic := '0';
   signal clk0     : std_ulogic := '0';

   procedure log(s : string) is
      variable l : line;
   begin
      write(l, "LOG " & integer'image(integer(now / 1 ps)) & " " & s);
      writeline(output, l);
   end procedure log;

   function hex(v : std_logic_vector) return string is
   begin
      return to_hstring(v);
   end function hex;

begin

   p_drp : process (DCLK)
      type regs_t is array (0 to 127) of std_logic_vector(15 downto 0);
      function start_pattern return regs_t is
         variable r : regs_t;
      begin
         for i in r'range loop
            r(i) := std_logic_vector(to_unsigned((i * 40503 + 12345) mod 65536, 16));
         end loop;
         return r;
      end function start_pattern;
      variable regs : regs_t := start_pattern;
      variable cnt  : integer := -1;
      variable a    : natural;
      variable we   : std_ulogic;
      variable d    : std_logic_vector(15 downto 0);
   begin
      if rising_edge(DCLK) then
         DRDY <= '0';
         if cnt > 0 then
            cnt := cnt - 1;
         end if;
         if cnt = 0 then
            if we = '1' then
               regs(a) := d;
               log("WR " & hex(std_logic_vector(to_unsigned(a, 8))) & " " & hex(d));
            else
               DO <= regs(a);
               log("RD " & hex(std_logic_vector(to_unsigned(a, 8))) & " " & hex(regs(a)));
            end if;
            DRDY <= '1';
            cnt  := -1;
         end if;
         if DEN = '1' then
            if cnt /= -1 then
               log("ERROR DEN while a DRP access is in progress");
            end if;
            if RST /= '1' then
               log("ERROR DRP access while RST is not '1'");
            end if;
            a   := to_integer(unsigned(DADDR));
            we  := DWE;
            d   := DI;
            cnt := 3;
         end if;
      end if;
   end process p_drp;

   p_lock : process
   begin
      loop
         if RST /= '0' then
            locked_i <= '0';
            wait until RST = '0';
         end if;
         wait until RST /= '0' for C_LOCK_TIME;
         if RST = '0' then
            locked_i <= '1';
            wait until RST /= '0';
         end if;
      end loop;
   end process p_lock;

   p_log_rst : process (RST)
   begin
      log("RST " & std_ulogic'image(RST));
   end process p_log_rst;

   p_log_locked : process (locked_i)
   begin
      log("LOCKED " & std_ulogic'image(locked_i));
   end process p_log_locked;

   LOCKED <= locked_i;

   clk1 <= not clk1 after C_CLKOUT1_PERIOD / 2 when locked_i = '1' else '0';
   clk0 <= not clk0 after C_CLKOUT1_PERIOD / 10 when locked_i = '1' else '0';

   CLKOUT1      <= clk1;
   CLKOUT0      <= clk0;
   CLKFBOUT     <= clk1;
   CLKFBOUTB    <= '0';
   CLKFBSTOPPED <= '0';
   CLKINSTOPPED <= '0';
   CLKOUT2      <= '0';
   CLKOUT3      <= '0';
   CLKOUT4      <= '0';
   CLKOUT5      <= '0';
   CLKOUT6      <= '0';
   CLKOUT0B     <= '0';
   CLKOUT1B     <= '0';
   CLKOUT2B     <= '0';
   CLKOUT3B     <= '0';
   PSDONE       <= '0';

end architecture model;

library ieee;
use ieee.std_logic_1164.all;

entity BUFG is
   port (
      O : out std_ulogic;
      I : in  std_ulogic
   );
end entity BUFG;

architecture model of BUFG is
begin
   O <= I;
end architecture model;

library ieee;
use ieee.std_logic_1164.all;

entity BUFGMUX_CTRL is
   port (
      O  : out std_ulogic;
      I0 : in  std_ulogic;
      I1 : in  std_ulogic;
      S  : in  std_ulogic
   );
end entity BUFGMUX_CTRL;

architecture model of BUFGMUX_CTRL is
begin
   O <= I1 when S = '1' else I0;
end architecture model;
