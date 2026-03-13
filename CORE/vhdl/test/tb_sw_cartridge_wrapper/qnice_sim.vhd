----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is part of the testbench for the sw_cartridge_wrapper module.
--
-- It provides the stimulus to run the simulation.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity qnice_sim is
   port (
      qnice_clk_i       : in  std_logic;
      qnice_rst_i       : in  std_logic;
      -- Interface to QNICE CPU
      qnice_addr_o      : out std_logic_vector(27 downto 0);
      qnice_writedata_o : out std_logic_vector(15 downto 0);
      qnice_ce_o        : out std_logic;
      qnice_we_o        : out std_logic;
      qnice_readdata_i  : in  std_logic_vector(15 downto 0);
      qnice_wait_i      : in  std_logic;
      -- TB signals
      qnice_length_i    : in  std_logic_vector(31 downto 0);
      qnice_running_o   : out std_logic := '1'
   );
end entity qnice_sim;

architecture simulation of qnice_sim is

begin

   p_test : process

      procedure qnice_cpu_write(addr : std_logic_vector(27 downto 0);
                                data : std_logic_vector(15 downto 0)) is
      begin
         qnice_addr_o      <= addr;
         qnice_writedata_o <= data;
         qnice_we_o        <= '1';
         qnice_ce_o        <= '1';
         wait until falling_edge(qnice_clk_i);
         while qnice_wait_i = '1' loop
            wait until falling_edge(qnice_clk_i);
         end loop;
         qnice_ce_o        <= '0';
      end procedure qnice_cpu_write;

      procedure qnice_cpu_read(addr : std_logic_vector(27 downto 0);
                               data : out std_logic_vector(15 downto 0)) is
      begin
         qnice_addr_o      <= addr;
         qnice_we_o        <= '0';
         qnice_ce_o        <= '1';
         wait until falling_edge(qnice_clk_i);
         while qnice_wait_i = '1' loop
            wait until falling_edge(qnice_clk_i);
         end loop;
         data              := qnice_readdata_i;
         qnice_ce_o        <= '0';
      end procedure qnice_cpu_read;

      procedure qnice_cpu_verify(addr : std_logic_vector(27 downto 0);
                                 data : std_logic_vector(15 downto 0)) is
         variable read_data_v : std_logic_vector(15 downto 0);
      begin
         qnice_cpu_read(addr, read_data_v);
         assert read_data_v = data
            report "ERROR: QNICE Reading from address " & to_hstring(addr) &
               " returned " & to_hstring(read_data_v) & ", but expected " &
               to_hstring(data)
            severity error;
      end procedure qnice_cpu_verify;

      constant C_CRT_STATUS    : std_logic_vector(27 downto 0) := X"FFFF000";
      constant C_CRT_FS_LO     : std_logic_vector(27 downto 0) := X"FFFF001";
      constant C_CRT_FS_HI     : std_logic_vector(27 downto 0) := X"FFFF002";
      constant C_CRT_PARSEST   : std_logic_vector(27 downto 0) := X"FFFF010";
      constant C_CRT_PARSEE1   : std_logic_vector(27 downto 0) := X"FFFF011";
      constant C_CRT_ADDR_LO   : std_logic_vector(27 downto 0) := X"FFFF012";
      constant C_CRT_ADDR_HI   : std_logic_vector(27 downto 0) := X"FFFF013";
      constant C_CRT_ERR_START : std_logic_vector(27 downto 0) := X"FFFF100";
      constant C_CRT_ERR_END   : std_logic_vector(27 downto 0) := X"FFFF1FF";

      -- Values for C_CRT_STATUS
      constant C_CRT_ST_IDLE   : std_logic_vector(15 downto 0) := X"0000";
      constant C_CRT_ST_LDNG   : std_logic_vector(15 downto 0) := X"0001";
      constant C_CRT_ST_ERR    : std_logic_vector(15 downto 0) := X"0002";
      constant C_CRT_ST_OK     : std_logic_vector(15 downto 0) := X"0003";

      -- Values for C_CRT_PARSEST
      constant C_STAT_IDLE     : std_logic_vector(15 downto 0) := X"0000";
      constant C_STAT_PARSING  : std_logic_vector(15 downto 0) := X"0001";
      constant C_STAT_READY    : std_logic_vector(15 downto 0) := X"0002"; -- Successfully parsed CRT file
      constant C_STAT_ERROR    : std_logic_vector(15 downto 0) := X"0003"; -- Error parsing CRT file

      constant C_ERROR_NONE           : std_logic_vector(3 downto 0) := "0000";
      constant C_ERROR_NO_CRT_HDR     : std_logic_vector(3 downto 0) := "0001"; -- Missing CRT header
      constant C_ERROR_NO_CHIP_HDR    : std_logic_vector(3 downto 0) := "0010"; -- Missing CHIP header
      constant C_ERROR_WRONG_CRT_HDR  : std_logic_vector(3 downto 0) := "0011"; -- Wrong CRT header
      constant C_ERROR_WRONG_CHIP_HDR : std_logic_vector(3 downto 0) := "0100"; -- Wrong CHIP header
      constant C_ERROR_TRUNCATED_CHIP : std_logic_vector(3 downto 0) := "0101"; -- Truncated CHIP

      variable tmp             : std_logic_vector(15 downto 0);
      variable tmp2            : std_logic_vector(15 downto 0);
      variable error_address   : std_logic_vector(31 downto 0);
      variable s               : string(1 to 256);

   begin

      qnice_ce_o <= '0';
      wait until qnice_rst_i = '0';
      wait until falling_edge(qnice_clk_i);
      qnice_cpu_verify(C_CRT_PARSEST, C_STAT_IDLE);

      qnice_cpu_write(C_CRT_STATUS, C_CRT_ST_IDLE);
      qnice_cpu_write(C_CRT_FS_LO,  qnice_length_i(15 downto  0));
      qnice_cpu_write(C_CRT_FS_HI,  qnice_length_i(31 downto 16));
      qnice_cpu_write(C_CRT_STATUS, C_CRT_ST_OK);
      wait for 100 ns;
      wait until falling_edge(qnice_clk_i);

      qnice_cpu_verify(C_CRT_PARSEST, C_STAT_PARSING);

      for i in 1 to 100 loop
         qnice_cpu_read(C_CRT_PARSEST, tmp);
         if tmp = C_STAT_READY then
            report "Finished parsing CRT file";
            exit;
         end if;
         if tmp = C_STAT_ERROR then
            report "ERROR while parsing CRT file";
            qnice_cpu_read(C_CRT_PARSEE1, tmp2);
            report "CODE: " & to_hstring(tmp2);
            for j in 0 to 255 loop
               qnice_cpu_read(std_logic_vector(unsigned(C_CRT_ERR_START) + j), tmp2);
               s(j+1) := character'val(to_integer(unsigned(tmp2(7 downto 0))));
               if s(j+1) = '\' then
                  s(j+1) := character'val(0);
                  exit;
               end if;
            end loop;
            report "STRING: " & s;
            qnice_cpu_read(C_CRT_ADDR_LO, error_address(15 downto  0));
            qnice_cpu_read(C_CRT_ADDR_HI, error_address(31 downto 16));
            report "ADDRESS: " & to_hstring(error_address);
            exit;
         end if;
         wait for 100 ns;
      end loop;

      if tmp /= C_STAT_READY and tmp /= C_STAT_ERROR then
         report "ERROR: Timeout waiting for CRT file parsing to complete";
      end if;

      qnice_running_o <= '0';
      report "QNICE finished";
      wait;
   end process p_test;

end architecture simulation;

