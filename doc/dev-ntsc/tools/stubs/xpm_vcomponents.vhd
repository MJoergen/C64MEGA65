-- Analysis stub for the Xilinx XPM library (package xpm.vcomponents).
-- Used by doc/dev-ntsc/tools/analyze.sh so that ghdl can analyze files that
-- instantiate XPM macros as components. Generic and port names, types and
-- defaults follow the Xilinx UltraScale/7 Series XPM documentation (UG974).
-- The CDC macros also get small behavioral entities (a plain shift register
-- synchronizer) so that a testbench can elaborate a design that uses them.
-- These are NOT timing-accurate models of the Xilinx macros.
-- Compile into a library named xpm: ghdl -a --std=08 --work=xpm ...

library ieee;
use ieee.std_logic_1164.all;

package vcomponents is

   component xpm_cdc_async_rst is
      generic (
         DEST_SYNC_FF    : integer := 4;
         INIT_SYNC_FF    : integer := 0;
         RST_ACTIVE_HIGH : integer := 0
      );
      port (
         src_arst  : in  std_logic;
         dest_clk  : in  std_logic;
         dest_arst : out std_logic
      );
   end component xpm_cdc_async_rst;

   component xpm_cdc_sync_rst is
      generic (
         DEST_SYNC_FF   : integer := 4;
         INIT           : integer := 1;
         INIT_SYNC_FF   : integer := 0;
         SIM_ASSERT_CHK : integer := 0
      );
      port (
         src_rst  : in  std_logic;
         dest_clk : in  std_logic;
         dest_rst : out std_logic
      );
   end component xpm_cdc_sync_rst;

   component xpm_cdc_single is
      generic (
         DEST_SYNC_FF   : integer := 4;
         INIT_SYNC_FF   : integer := 0;
         SIM_ASSERT_CHK : integer := 0;
         SRC_INPUT_REG  : integer := 1
      );
      port (
         src_clk  : in  std_logic;
         src_in   : in  std_logic;
         dest_clk : in  std_logic;
         dest_out : out std_logic
      );
   end component xpm_cdc_single;

   component xpm_cdc_array_single is
      generic (
         DEST_SYNC_FF   : integer := 4;
         INIT_SYNC_FF   : integer := 0;
         SIM_ASSERT_CHK : integer := 0;
         SRC_INPUT_REG  : integer := 1;
         WIDTH          : integer := 2
      );
      port (
         src_clk  : in  std_logic;
         src_in   : in  std_logic_vector(WIDTH-1 downto 0);
         dest_clk : in  std_logic;
         dest_out : out std_logic_vector(WIDTH-1 downto 0)
      );
   end component xpm_cdc_array_single;

   component xpm_cdc_pulse is
      generic (
         DEST_SYNC_FF   : integer := 4;
         INIT_SYNC_FF   : integer := 0;
         REG_OUTPUT     : integer := 0;
         RST_USED       : integer := 1;
         SIM_ASSERT_CHK : integer := 0
      );
      port (
         src_clk    : in  std_logic;
         src_pulse  : in  std_logic;
         src_rst    : in  std_logic;
         dest_clk   : in  std_logic;
         dest_rst   : in  std_logic;
         dest_pulse : out std_logic
      );
   end component xpm_cdc_pulse;

   component xpm_cdc_gray is
      generic (
         DEST_SYNC_FF          : integer := 4;
         INIT_SYNC_FF          : integer := 0;
         REG_OUTPUT            : integer := 0;
         SIM_ASSERT_CHK        : integer := 0;
         SIM_LOSSLESS_GRAY_CHK : integer := 0;
         WIDTH                 : integer := 2
      );
      port (
         src_clk      : in  std_logic;
         src_in_bin   : in  std_logic_vector(WIDTH-1 downto 0);
         dest_clk     : in  std_logic;
         dest_out_bin : out std_logic_vector(WIDTH-1 downto 0)
      );
   end component xpm_cdc_gray;

   component xpm_cdc_handshake is
      generic (
         DEST_EXT_HSK   : integer := 1;
         DEST_SYNC_FF   : integer := 4;
         INIT_SYNC_FF   : integer := 0;
         SIM_ASSERT_CHK : integer := 0;
         SRC_SYNC_FF    : integer := 4;
         WIDTH          : integer := 1
      );
      port (
         src_clk  : in  std_logic;
         src_in   : in  std_logic_vector(WIDTH-1 downto 0);
         src_send : in  std_logic;
         src_rcv  : out std_logic;
         dest_clk : in  std_logic;
         dest_req : out std_logic;
         dest_ack : in  std_logic;
         dest_out : out std_logic_vector(WIDTH-1 downto 0)
      );
   end component xpm_cdc_handshake;

end package vcomponents;

-------------------------------------------------------------------------------
-- Behavioral entities (plain synchronizer chains)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity xpm_cdc_async_rst is
   generic (
      DEST_SYNC_FF    : integer := 4;
      INIT_SYNC_FF    : integer := 0;
      RST_ACTIVE_HIGH : integer := 0
   );
   port (
      src_arst  : in  std_logic;
      dest_clk  : in  std_logic;
      dest_arst : out std_logic
   );
end entity xpm_cdc_async_rst;

architecture behav of xpm_cdc_async_rst is
   function act return std_logic is
   begin
      if RST_ACTIVE_HIGH = 1 then return '1'; else return '0'; end if;
   end function act;
   signal chain : std_logic_vector(DEST_SYNC_FF-1 downto 0) := (others => act);
begin
   process (dest_clk, src_arst)
   begin
      if src_arst = act then
         chain <= (others => act);
      elsif rising_edge(dest_clk) then
         chain <= chain(DEST_SYNC_FF-2 downto 0) & (not act);
      end if;
   end process;
   dest_arst <= chain(DEST_SYNC_FF-1);
end architecture behav;

library ieee;
use ieee.std_logic_1164.all;

entity xpm_cdc_single is
   generic (
      DEST_SYNC_FF   : integer := 4;
      INIT_SYNC_FF   : integer := 0;
      SIM_ASSERT_CHK : integer := 0;
      SRC_INPUT_REG  : integer := 1
   );
   port (
      src_clk  : in  std_logic;
      src_in   : in  std_logic;
      dest_clk : in  std_logic;
      dest_out : out std_logic
   );
end entity xpm_cdc_single;

architecture behav of xpm_cdc_single is
   signal chain : std_logic_vector(DEST_SYNC_FF-1 downto 0) := (others => '0');
begin
   process (dest_clk)
   begin
      if rising_edge(dest_clk) then
         chain <= chain(DEST_SYNC_FF-2 downto 0) & src_in;
      end if;
   end process;
   dest_out <= chain(DEST_SYNC_FF-1);
end architecture behav;

library ieee;
use ieee.std_logic_1164.all;

entity xpm_cdc_array_single is
   generic (
      DEST_SYNC_FF   : integer := 4;
      INIT_SYNC_FF   : integer := 0;
      SIM_ASSERT_CHK : integer := 0;
      SRC_INPUT_REG  : integer := 1;
      WIDTH          : integer := 2
   );
   port (
      src_clk  : in  std_logic;
      src_in   : in  std_logic_vector(WIDTH-1 downto 0);
      dest_clk : in  std_logic;
      dest_out : out std_logic_vector(WIDTH-1 downto 0)
   );
end entity xpm_cdc_array_single;

architecture behav of xpm_cdc_array_single is
   type chain_t is array (0 to DEST_SYNC_FF-1) of std_logic_vector(WIDTH-1 downto 0);
   signal chain : chain_t := (others => (others => '0'));
begin
   process (dest_clk)
   begin
      if rising_edge(dest_clk) then
         chain(0) <= src_in;
         for i in 1 to DEST_SYNC_FF-1 loop
            chain(i) <= chain(i-1);
         end loop;
      end if;
   end process;
   dest_out <= chain(DEST_SYNC_FF-1);
end architecture behav;
