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

entity tb_sweeper is
end entity tb_sweeper;

architecture simulation of tb_sweeper is

  constant C_ADDR_SIZE : natural := 4;

  signal   clk     : std_logic   := '1';
  signal   rst     : std_logic   := '1';
  signal   running : std_logic   := '1';

  signal   start      : std_logic;
  signal   busy       : std_logic;
  signal   wbus_cyc   : std_logic;
  signal   wbus_stall : std_logic;
  signal   wbus_stb   : std_logic;
  signal   wbus_addr  : std_logic_vector(C_ADDR_SIZE - 1 downto 0);
  signal   wbus_we    : std_logic;
  signal   wbus_wrdat : std_logic_vector(31 downto 0);
  signal   wbus_ack   : std_logic;
  signal   wbus_rddat : std_logic_vector(31 downto 0) := (others => '0');

begin

  rst <= '1', '0' after 100 ns;
  clk <= running and not clk after 5 ns;

  sweeper_inst : entity work.sweeper
    generic map (
      G_ADDR_SIZE => C_ADDR_SIZE
    )
    port map (
      clk_i        => clk,
      rst_i        => rst,
      start_i      => start,
      busy_o       => busy,
      wbus_cyc_o   => wbus_cyc,
      wbus_stall_i => wbus_stall,
      wbus_stb_o   => wbus_stb,
      wbus_addr_o  => wbus_addr,
      wbus_we_o    => wbus_we,
      wbus_wrdat_o => wbus_wrdat,
      wbus_ack_i   => wbus_ack,
      wbus_rddat_i => wbus_rddat
    ); -- sweeper_inst : entity work.sweeper

  wbus_mem_inst : entity work.wbus_mem
    generic map (
      G_ADDR_SIZE => C_ADDR_SIZE,
      G_DATA_SIZE => 8
    )
    port map (
      clk_i     => clk,
      rst_i     => rst,
      s_cyc_i   => wbus_cyc,
      s_stall_o => wbus_stall,
      s_stb_i   => wbus_stb,
      s_addr_i  => wbus_addr,
      s_we_i    => wbus_we,
      s_wrdat_i => wbus_wrdat(7 downto 0),
      s_ack_o   => wbus_ack,
      s_rddat_o => wbus_rddat(7 downto 0),
      s_int_o   => open
    ); -- wbus_mem_inst : entity work.wbus_mem

  test_proc : process
  begin
    start <= '0';
    wait until rst = '0';
    wait for 100 ns;
    wait until rising_edge(clk);

    report "Test started";
    start <= '1';
    wait until rising_edge(clk);
    start <= '0';
    wait until rising_edge(clk);

    wait for 10 us;
    report "Test stopped";
    running <= '0';
    wait;

  end process test_proc;

end architecture simulation;

