library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

-- This module allows the QNICE CPU to access an Avalon Memory Mapped
-- device (normally the HyperRAM device of the MEGA65).
--
-- This module runs in the QNICE clock domain.
--
-- CAUTION - the QNICE CPU is hard-stalled while s_qnice_wait_o is high, so a
-- lost Avalon response would freeze the whole Shell forever. That is not
-- hypothetical: the HyperRAM clock domain is reset on every press of the
-- MEGA65 reset button (hr_rst includes the core reset, see clk_m2m.vhd),
-- while the QNICE domain keeps running - a press during an in-flight access
-- drops the command or its read response. The watchdog below detects a stall
-- that lasts far beyond any legitimate HyperRAM latency and re-issues the
-- latched command. While the other domain is still in reset the retry is
-- dropped again and the watchdog simply fires again; after the reset
-- releases, the first retry completes with correct data, so the CPU never
-- observes wrong data - it just waits out the reset. (Found the hard way
-- while hardware-testing C64MEGA65 issue #93: a reset storm during drive IO
-- froze the on-screen menu.)

entity qnice2hyperram is
   generic (
      G_TIMEOUT_CYCLES : natural := 32768   -- roughly 0.65 ms at 50 MHz; orders of
                                            -- magnitude above worst-case latency
   );
   port (
      -- This is the QNICE clock
      clk_i                 : in  std_logic;
      rst_i                 : in  std_logic;

      -- Connect to QNICE CPU
      -- This is a slave interface
      s_qnice_wait_o        : out std_logic;
      s_qnice_address_i     : in  std_logic_vector(31 downto 0);
      s_qnice_cs_i          : in  std_logic;
      s_qnice_write_i       : in  std_logic;
      s_qnice_writedata_i   : in  std_logic_vector(15 downto 0);
      s_qnice_byteenable_i  : in  std_logic_vector( 1 downto 0);
      s_qnice_readdata_o    : out std_logic_vector(15 downto 0);

      -- Connect to HyperRAM (via avm_fifo)
      -- This is a master interface
      m_avm_write_o         : out std_logic;
      m_avm_read_o          : out std_logic;
      m_avm_address_o       : out std_logic_vector(31 downto 0);
      m_avm_writedata_o     : out std_logic_vector(15 downto 0);
      m_avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      m_avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      m_avm_readdata_i      : in  std_logic_vector(15 downto 0);
      m_avm_readdatavalid_i : in  std_logic;
      m_avm_waitrequest_i   : in  std_logic
   );
end entity qnice2hyperram;

architecture synthesis of qnice2hyperram is

   signal reading               : std_logic;
   signal m_avm_readdatavalid_d : std_logic;
   signal watchdog              : natural range 0 to G_TIMEOUT_CYCLES;

begin

   s_qnice_wait_o <= ((m_avm_write_o or m_avm_read_o) and m_avm_waitrequest_i) or reading;

   convert_proc : process (clk_i)
   begin
      if falling_edge(clk_i) then
         m_avm_readdatavalid_d <= m_avm_readdatavalid_i;

         if m_avm_waitrequest_i = '0' then
            m_avm_write_o <= '0';
            m_avm_read_o  <= '0';
         end if;

         if s_qnice_cs_i = '1' and s_qnice_wait_o = '0' and m_avm_readdatavalid_d = '0' then
            m_avm_write_o      <= s_qnice_write_i;
            m_avm_read_o       <= not s_qnice_write_i;
            m_avm_address_o    <= s_qnice_address_i;
            m_avm_writedata_o  <= s_qnice_writedata_i;
            m_avm_byteenable_o <= s_qnice_byteenable_i;
            m_avm_burstcount_o <= X"01";

            reading <= not s_qnice_write_i;
         end if;

         if m_avm_readdatavalid_i = '1' then
            s_qnice_readdata_o <= m_avm_readdata_i;
            reading       <= '0';
         end if;

         -- Self-healing watchdog: see the CAUTION block in the entity header.
         -- A pending command (write_o/read_o high with waitrequest stuck) needs
         -- no action - it stays asserted and is accepted once the other domain
         -- returns. The dangerous shape is "reading with no pending command":
         -- the read response was dropped, so re-issue the read (address,
         -- byteenable and burstcount are still latched).
         if s_qnice_wait_o = '1' then
            if watchdog = G_TIMEOUT_CYCLES then
               watchdog <= 0;
               if reading = '1' and m_avm_read_o = '0' and m_avm_write_o = '0' then
                  m_avm_read_o <= '1';
               end if;
            else
               watchdog <= watchdog + 1;
            end if;
         else
            watchdog <= 0;
         end if;

         if rst_i = '1' then
            m_avm_write_o <= '0';
            m_avm_read_o  <= '0';
            reading       <= '0';
            watchdog      <= 0;
         end if;
      end if;
   end process convert_proc;

end architecture synthesis;

