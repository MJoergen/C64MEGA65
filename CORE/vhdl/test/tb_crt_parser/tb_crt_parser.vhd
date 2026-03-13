----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is the testbench for the crt_parser module.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.numeric_std_unsigned.all;

entity tb_crt_parser is
end entity tb_crt_parser;

architecture simulation of tb_crt_parser is

   constant C_NAME_LEN : natural :=  44;

   type word_vector is array (natural range <>) of std_logic_vector(15 downto 0);

   type test_type is record
      name        : string(1 to C_NAME_LEN);
      data        : word_vector(0 to 1023);
      length      : integer;
      exp_status  : integer;
      exp_error   : integer;
      exp_address : integer;
   end record;

   type test_vector is array (natural range <>) of test_type;

   function pad(s: string; n: positive) return string is
      variable ps: string(1 to n) := (others => ' ');
   begin
      if s'length >= n then
         ps := s(1 to n); --- truncate the source string
      else
         ps(1 to s'length) := s;
         ps(s'length+1 to n) := (others => ' ');
      end if;
      return ps;
   end;

   constant C_TESTS : test_vector := (
      (pad("Testing missing CRT header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045",
         others => X"0000"),
        14, 3, 1, 0),

      (pad("Testing unrecognized CRT header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2120",
         X"0000", X"4000", X"0001", X"1300",
         others => X"0000"),
        64, 3, 3, 0),

      (pad("Testing missing CRT header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300",
         others => X"0000"),
        62, 3, 1, 0),

      (pad("Testing missing CHIP header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300",
         others => X"0000"),
        64, 3, 2, 0),

      (pad("Testing missing CHIP header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4001", X"0001", X"1300", X"0100", X"0000", X"0000", X"0000",
         others => X"0000"),
        80, 3, 2, 0),

      (pad("Testing unrecognized CHIP header", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300", X"0100", X"0000", X"0000", X"0000",
         X"4956", X"4545", X"4320", X"5241", X"0054", X"0000", X"0000", X"0000",
         others => X"0000"),
        96, 3, 4, 64),

      (pad("Testing truncated CHIP data", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300", X"0100", X"0000", X"0000", X"0000",
         X"4956", X"4543", X"4320", X"5241", X"0054", X"0000", X"0000", X"0000",
         X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
         X"4843", X"5049", X"0000", X"1020", X"0000", X"0000", X"0080", X"0020",
         X"8009", X"8009", X"c2c3", X"38cd", X"8e30", X"d016", X"2078", X"fda3",
         others => X"0000"),
        96, 3, 5, 64),

      (pad("Testing 16k CHIP data", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300", X"0100", X"0000", X"0000", X"0000",
         X"4956", X"4543", X"4320", X"5241", X"0054", X"0000", X"0000", X"0000",
         X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
         X"4843", X"5049", X"0000", X"1040", X"0000", X"0000", X"0080", X"0040",
         X"8009", X"8009", X"c2c3", X"38cd", X"8e30", X"d016", X"2078", X"fda3",
         others => X"0000"),
        80+16384, 2, 0, 0),

      (pad("Testing no errors", C_NAME_LEN),
        (X"3643", X"2034", X"4143", X"5452", X"4952", X"4744", X"2045", X"2020",
         X"0000", X"4000", X"0001", X"1300", X"0100", X"0000", X"0000", X"0000",
         X"4956", X"4543", X"4320", X"5241", X"0054", X"0000", X"0000", X"0000",
         X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000", X"0000",
         X"4843", X"5049", X"0000", X"1020", X"0000", X"0000", X"0080", X"0020",
         X"8009", X"8009", X"c2c3", X"38cd", X"8e30", X"d016", X"2078", X"fda3",
         others => X"0000"),
        80+8192, 2, 0, 0)
   ); -- C_TESTS

   type bank_t is array (natural range 0 to 255) of std_logic_vector(6 downto 0);
   signal lobank : bank_t := (others => (others => '0'));
   signal hibank : bank_t := (others => (others => '0'));

   signal clk               : std_logic := '0';
   signal rst               : std_logic := '1';
   signal req_start         : std_logic;
   signal req_address       : std_logic_vector(21 downto 0);
   signal req_length        : std_logic_vector(22 downto 0);
   signal resp_status       : std_logic_vector( 3 downto 0);
   signal resp_error        : std_logic_vector( 3 downto 0);
   signal resp_address      : std_logic_vector(22 downto 0);
   signal avm_write         : std_logic;
   signal avm_read          : std_logic;
   signal avm_address       : std_logic_vector(21 downto 0);
   signal avm_writedata     : std_logic_vector(15 downto 0);
   signal avm_byteenable    : std_logic_vector( 1 downto 0);
   signal avm_burstcount    : std_logic_vector( 7 downto 0);
   signal avm_readdata      : std_logic_vector(15 downto 0);
   signal avm_readdatavalid : std_logic;
   signal avm_waitrequest   : std_logic;
   signal cart_bank_laddr   : std_logic_vector(15 downto 0);
   signal cart_bank_size    : std_logic_vector(15 downto 0);
   signal cart_bank_num     : std_logic_vector(15 downto 0);
   signal cart_bank_raddr   : std_logic_vector(24 downto 0);
   signal cart_bank_wr      : std_logic;
   signal cart_loading      : std_logic;
   signal cart_id           : std_logic_vector(15 downto 0);
   signal cart_exrom        : std_logic_vector( 7 downto 0);
   signal cart_game         : std_logic_vector( 7 downto 0);
   signal test_num          : integer := 0;
   signal running           : std_logic := '1';
   signal burst             : integer;
   signal offset            : integer := 0;

begin

   clk <= running and not clk after 5 ns;

   i_crt_parser : entity work.crt_parser
      port map (
         clk_i               => clk,
         rst_i               => rst,
         req_start_i         => req_start,
         req_length_i        => req_length,
         req_address_i       => req_address,
         resp_status_o       => resp_status,
         resp_error_o        => resp_error,
         resp_address_o      => resp_address,
         avm_write_o         => avm_write,
         avm_read_o          => avm_read,
         avm_address_o       => avm_address,
         avm_writedata_o     => avm_writedata,
         avm_byteenable_o    => avm_byteenable,
         avm_burstcount_o    => avm_burstcount,
         avm_readdata_i      => avm_readdata,
         avm_readdatavalid_i => avm_readdatavalid,
         avm_waitrequest_i   => avm_waitrequest,
         cart_bank_laddr_o   => cart_bank_laddr,
         cart_bank_size_o    => cart_bank_size,
         cart_bank_num_o     => cart_bank_num,
         cart_bank_raddr_o   => cart_bank_raddr,
         cart_bank_wr_o      => cart_bank_wr,
         cart_loading_o      => cart_loading,
         cart_id_o           => cart_id,
         cart_exrom_o        => cart_exrom,
         cart_game_o         => cart_game
      ); -- i_crt_parser

   process (clk)
   begin
      if rising_edge(clk) then
         avm_waitrequest   <= '0';
         if avm_read = '1' then
            burst  <= to_integer(avm_burstcount);
            offset <= 1;
            avm_readdata   <= C_TESTS(test_num).data(to_integer(avm_address(7 downto 0)));
            avm_readdatavalid <= '1';
         elsif offset < burst then
            offset <= offset + 1;
            avm_readdata      <= C_TESTS(test_num).data(to_integer(avm_address(7 downto 0)) + offset);
            avm_readdatavalid <= '1';
         else
            avm_readdatavalid <= '0';
         end if;
      end if;
   end process;

   process
   begin
      rst <= '1';
      req_start <= '0';
      wait for 100 ns;
      rst <= '0';
      wait until falling_edge(clk);

      for i in 0 to C_TESTS'length-1 loop
         report "Test #" & to_string(i) & ": " & C_TESTS(i).name;
         test_num    <= i;
         req_address <= "01" & X"00000";
         req_length  <= std_logic_vector(to_unsigned(C_TESTS(i).length, 23));
         req_start   <= '1';
         wait until falling_edge(clk);
         while cart_loading = '1' and resp_status /= 3 loop
            wait until falling_edge(clk);
         end loop;
         if resp_status /= C_TESTS(test_num).exp_status then
            report "Status is " & to_string(resp_status) & ", but expected " &
               to_string(C_TESTS(test_num).exp_status);
            wait until falling_edge(clk);
            running <= '0';
         end if;

         if resp_error /= C_TESTS(test_num).exp_error then
            report "Error is " & to_string(resp_error) & ", but expected " &
               to_string(C_TESTS(test_num).exp_error);
            wait until falling_edge(clk);
            running <= '0';
         end if;

         if resp_address /= C_TESTS(test_num).exp_address then
            report "Address is " & to_hstring(resp_address) & ", but expected " &
               to_hstring(to_unsigned(C_TESTS(test_num).exp_address, 22));
            wait until falling_edge(clk);
            running <= '0';
         end if;

         req_start   <= '0';
         wait until falling_edge(clk);
         rst <= '1';
         wait for 100 ns;
         rst <= '0';
         wait until falling_edge(clk);
      end loop;

      running <= '0';
      report "Finished";
      wait;
   end process;

end architecture simulation;

