----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This module acts as a bridge connection between the RAM Expansion Unit of the C64
-- and the external memory device of the MEGA65.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std_unsigned.all;

entity reu_mapper is
   generic (
      -- Configure base address within the external memory device
      G_BASE_ADDRESS : std_logic_vector(31 downto 0)
   );
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;
      reu_ext_cycle_i     : in  std_logic; -- From C64
      reu_ext_cycle_o     : out std_logic; -- To REU
      reu_addr_i          : in  std_logic_vector(24 downto 0);  -- 32 MB
      reu_dout_i          : in  std_logic_vector(7 downto 0);
      reu_din_o           : out std_logic_vector(7 downto 0);
      reu_we_i            : in  std_logic;
      reu_cs_i            : in  std_logic;

      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(31 downto 0);
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector(1 downto 0);
      avm_burstcount_o    : out std_logic_vector(7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic
   );
end entity reu_mapper;

architecture synthesis of reu_mapper is

   signal reu_addr_d           : std_logic_vector(24 downto 0);
   signal avm_preemptive_s     : std_logic;
   signal avm_preemptive_r     : std_logic;
   signal avm_preemptive_block : std_logic;

   signal reu_cs_d             : std_logic;
   signal avm_valid_s          : std_logic;
   signal avm_write_s          : std_logic;
   signal avm_read_s           : std_logic;
   signal avm_address_s        : std_logic_vector(31 downto 0);
   signal avm_writedata_s      : std_logic_vector(15 downto 0);
   signal avm_byteenable_s     : std_logic_vector(1 downto 0);
   signal avm_burstcount_s     : std_logic_vector(7 downto 0);

   signal avm_write_r          : std_logic;
   signal avm_read_r           : std_logic;
   signal avm_address_r        : std_logic_vector(31 downto 0);
   signal avm_writedata_r      : std_logic_vector(15 downto 0);
   signal avm_byteenable_r     : std_logic_vector(1 downto 0);
   signal avm_burstcount_r     : std_logic_vector(7 downto 0);

   signal reu_ext_cycle_d      : std_logic;

   signal reu_rd_fifo_ready    : std_logic;
   signal reu_rd_fifo_valid    : std_logic;

   signal active_s             : std_logic;
   signal active               : std_logic;

begin

   -- This is a massive hack!
   -- In order to prevent delays when reading from the external memory
   -- this will preemptively read from external memory as soon as the
   -- address changes. This has the effect to "warm up" the cache.
   -- At the same time we must block the read response, so it
   -- doesn't lead to a RAM access.
   p_preemptive : process (clk_i)
   begin
      if rising_edge(clk_i) then
         reu_addr_d         <= reu_addr_i;
         avm_preemptive_r   <= avm_preemptive_s;
         if avm_preemptive_r and not (reu_cs_i and not reu_cs_d) then
            avm_preemptive_block <= '1';
         end if;
         if avm_readdatavalid_i = '1' then
            avm_preemptive_block <= '0';
         end if;
      end if;
   end process p_preemptive;
   avm_preemptive_s <= '1' when (reu_addr_d+1 /= reu_addr_i and reu_addr_d /= reu_addr_i) else '0';

   avm_valid_s      <= '1' when avm_preemptive_r else reu_cs_i and not reu_cs_d;
   avm_write_s      <= '0' when avm_preemptive_r else avm_valid_s and reu_we_i;
   avm_read_s       <= '1' when avm_preemptive_r else avm_valid_s and not reu_we_i;
   avm_address_s    <= (("00000000" & reu_addr_i(24 downto 1)) + G_BASE_ADDRESS) and X"003FFFFF";
   avm_writedata_s  <= reu_dout_i & reu_dout_i;
   avm_byteenable_s <= "01" when reu_addr_i(0) = '0' else "10";
   avm_burstcount_s <= X"01";

   p_avm : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if avm_valid_s = '1' then
            avm_write_r      <= avm_write_s;
            avm_read_r       <= avm_read_s;
            avm_address_r    <= avm_address_s;
            avm_writedata_r  <= avm_writedata_s;
            avm_byteenable_r <= avm_byteenable_s;
            avm_burstcount_r <= avm_burstcount_s;
         end if;
         if avm_waitrequest_i = '0' then
            avm_write_r <= '0';
            avm_read_r  <= '0';
         end if;
         if rst_i = '1' then
            avm_write_r <= '0';
            avm_read_r  <= '0';
         end if;
         reu_cs_d <= reu_cs_i;
      end if;
   end process p_avm;

   avm_write_o      <= avm_write_s      when avm_valid_s = '1' else avm_write_r;
   avm_read_o       <= avm_read_s       when avm_valid_s = '1' else avm_read_r;
   avm_address_o    <= avm_address_s    when avm_valid_s = '1' else avm_address_r;
   avm_writedata_o  <= avm_writedata_s  when avm_valid_s = '1' else avm_writedata_r;
   avm_byteenable_o <= avm_byteenable_s when avm_valid_s = '1' else avm_byteenable_r;
   avm_burstcount_o <= avm_burstcount_s when avm_valid_s = '1' else avm_burstcount_r;


   p_ext_cycle_d : process (clk_i)
   begin
      if rising_edge(clk_i) then
         reu_ext_cycle_d <= reu_ext_cycle_i;
      end if;
   end process p_ext_cycle_d;

   reu_rd_fifo_ready <= active and reu_ext_cycle_d and not reu_ext_cycle_i;

   p_avm_rd_fifo : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if reu_rd_fifo_ready = '1' then
            reu_rd_fifo_valid <= '0';
         end if;
         if avm_readdatavalid_i = '1' then
            reu_rd_fifo_valid <= avm_readdatavalid_i and not avm_preemptive_block;
            if reu_addr_i(0) = '0' then
               reu_din_o <= avm_readdata_i(7 downto 0);
            else
               reu_din_o <= avm_readdata_i(15 downto 8);
            end if;
         end if;
         if rst_i = '1' then
            reu_rd_fifo_valid <= '0';
         end if;
      end if;
   end process p_avm_rd_fifo;


   active_s <= (reu_we_i and not avm_waitrequest_i) or reu_rd_fifo_valid or (avm_readdatavalid_i and not avm_preemptive_block);

   p_active : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if reu_ext_cycle_i = '1' and reu_ext_cycle_d = '0' then
            active <= active_s;
         end if;
      end if;
   end process p_active;

   reu_ext_cycle_o <= (reu_ext_cycle_i and active_s and active) or
                      (reu_ext_cycle_i and active_s and not reu_ext_cycle_d);

end architecture synthesis;

