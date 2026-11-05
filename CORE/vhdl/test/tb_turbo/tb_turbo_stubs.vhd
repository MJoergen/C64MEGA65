----------------------------------------------------------------------------------------------------
-- Turbo-mode benches (issue #87): VHDL stand-ins for the Verilog/SystemVerilog components that
-- fpga64_sid_iec.vhd declares (mos6526, sid_top), so that the C64 core can be simulated with a
-- pure-VHDL simulator.
--
-- mos6526: register-level model with the bus timing of rtl/mos6526.v: reads and writes happen at
--          phi2_n (the clock after CYCLE_CPUC), db_out is registered, port outputs update at
--          phi2_p. Registers 0..F are plain storage except PRA/PRB/DDRA/DDRB; no timers, no IRQ.
-- sid_top: 32 plain registers per SID, written on "we" (pulseWr_io) while selected; data_out is
--          the register selected by addr; silent audio.
--
-- These stubs only have to give the CPU deterministic bus behavior; the benches check WHEN the
-- CPU accesses I/O, not what the chips do with the access.
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mos6526 is
   port (
      clk     : in  std_logic;
      mode    : in  std_logic := '0';
      phi2_p  : in  std_logic;
      phi2_n  : in  std_logic;
      res_n   : in  std_logic;
      cs_n    : in  std_logic;
      rw      : in  std_logic;
      rs      : in  unsigned(3 downto 0);
      db_in   : in  unsigned(7 downto 0);
      db_out  : out unsigned(7 downto 0);
      pa_in   : in  unsigned(7 downto 0);
      pa_out  : out unsigned(7 downto 0);
      pa_oe   : out unsigned(7 downto 0);
      pb_in   : in  unsigned(7 downto 0);
      pb_out  : out unsigned(7 downto 0);
      pb_oe   : out unsigned(7 downto 0);
      flag_n  : in  std_logic;
      pc_n    : out std_logic;
      tod     : in  std_logic;
      sp_in   : in  std_logic;
      sp_out  : out std_logic;
      cnt_in  : in  std_logic;
      cnt_out : out std_logic;
      irq_n   : out std_logic
   );
end entity mos6526;

architecture stub of mos6526 is
   type regs_t is array (0 to 15) of unsigned(7 downto 0);
   signal regs : regs_t := (others => (others => '0'));
begin
   pa_oe   <= regs(2);
   pb_oe   <= regs(3);
   pc_n    <= '1';
   sp_out  <= '1';
   cnt_out <= '1';
   irq_n   <= '1';

   process (clk)
      variable r : integer;
   begin
      if rising_edge(clk) then
         r := to_integer(rs);
         if res_n = '0' then
            regs   <= (others => (others => '0'));
            db_out <= (others => '0');
         elsif phi2_n = '1' and cs_n = '0' then
            if rw = '1' then
               case r is
                  when 0      => db_out <= pa_in;
                  when 1      => db_out <= pb_in;
                  when others => db_out <= regs(r);
               end case;
            else
               regs(r) <= db_in;
            end if;
         end if;
         if phi2_p = '1' then
            pa_out <= regs(0) or not regs(2);
            pb_out <= regs(1) or not regs(3);
         end if;
      end if;
   end process;
end architecture stub;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sid_top is
   port (
      reset    : in  std_logic;
      clk      : in  std_logic;
      ce_1m    : in  std_logic;
      cs       : in  std_logic_vector(1 downto 0);
      we       : in  std_logic;
      addr     : in  unsigned(4 downto 0);
      data_in  : in  unsigned(7 downto 0);
      data_out : out unsigned(7 downto 0);
      pot_x_l  : in  std_logic_vector(7 downto 0) := (others => '0');
      pot_y_l  : in  std_logic_vector(7 downto 0) := (others => '0');
      pot_x_r  : in  std_logic_vector(7 downto 0) := (others => '0');
      pot_y_r  : in  std_logic_vector(7 downto 0) := (others => '0');
      audio_l  : out std_logic_vector(17 downto 0);
      audio_r  : out std_logic_vector(17 downto 0);
      filter_en: in  std_logic_vector(1 downto 0);
      mode     : in  std_logic_vector(1 downto 0);
      cfg      : in  std_logic_vector(3 downto 0);
      ld_clk   : in  std_logic;
      ld_addr  : in  std_logic_vector(11 downto 0);
      ld_data  : in  std_logic_vector(15 downto 0);
      ld_wr    : in  std_logic
   );
end entity sid_top;

architecture stub of sid_top is
   type regs_t is array (0 to 31) of unsigned(7 downto 0);
   signal regs_l : regs_t := (others => (others => '0'));
   signal regs_r : regs_t := (others => (others => '0'));
begin
   audio_l  <= (others => '0');
   audio_r  <= (others => '0');
   data_out <= regs_r(to_integer(addr)) when cs(1) = '1' else regs_l(to_integer(addr));

   process (clk)
   begin
      if rising_edge(clk) then
         if reset = '1' then
            regs_l <= (others => (others => '0'));
            regs_r <= (others => (others => '0'));
         elsif we = '1' then
            if cs(0) = '1' then
               regs_l(to_integer(addr)) <= data_in;
            end if;
            if cs(1) = '1' then
               regs_r(to_integer(addr)) <= data_in;
            end if;
         end if;
      end if;
   end process;
end architecture stub;
