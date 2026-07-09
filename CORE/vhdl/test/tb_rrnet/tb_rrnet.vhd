----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is the testbench for the rrnet module.
--
-- done by MJoergen in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity tb_rrnet is
  generic (
    G_LOG_FILE : string := "";
    G_ROM_FILE : string := ""
  );
end entity tb_rrnet;

architecture tb of tb_rrnet is

  signal clk : std_logic          := '1';
  signal rst : std_logic          := '1';
  signal ce  : std_logic          := '1';

  signal cpu_addr      : std_logic_vector(15 downto 0);
  signal cpu_wr_en     : std_logic;
  signal cpu_rd_en     : std_logic;
  signal cpu_wr_data   : std_logic_vector(7 downto 0);
  signal cpu_rd_data   : std_logic_vector(7 downto 0);
  signal rrnet_rd_data : std_logic_vector(7 downto 0);
  signal rom_rd_data   : std_logic_vector(7 downto 0);
  signal ram_rd_data   : std_logic_vector(7 downto 0);

  signal rrnet_cs : std_logic;
  signal rom_cs   : std_logic;
  signal ram_cs   : std_logic;

  -- Ethernet interface
  signal eth_rx_valid : std_logic;                    -- One-cycle strobe per received byte
  signal eth_rx_last  : std_logic;                    -- Last byte of frame
  signal eth_rx_ok    : std_logic;                    -- Only meaningful when rx_last_i = '1'
  signal eth_rx_data  : std_logic_vector(7 downto 0); -- Received byte
  signal eth_tx_ready : std_logic := '0';             -- Pulses '1' on the byte-boundary cycle
  signal eth_tx_valid : std_logic;                    -- Client presents a byte
  signal eth_tx_last  : std_logic;                    -- Client marks the last byte
  signal eth_tx_data  : std_logic_vector(7 downto 0); -- Byte to transmit

begin

  -- Clock, reset, and clock enable
  clk         <= not clk after 5 ns;
  rst         <= '1', '0' after 100 ns;
  ce          <= not ce when rising_edge(clk);

  -- Instantiate DUT
  rrnet_inst : entity work.rrnet
    generic map (
      G_DEBUG => true
    )
    port map (
      clk_i          => clk,
      rst_i          => rst,
      cs_i           => rrnet_cs,
      addr_i         => cpu_addr(7 downto 0),
      we_i           => cpu_wr_en,
      wr_data_i      => cpu_wr_data,
      rd_data_o      => rrnet_rd_data,
      eth_rx_valid_i => eth_rx_valid,
      eth_rx_last_i  => eth_rx_last,
      eth_rx_ok_i    => eth_rx_ok,
      eth_rx_data_i  => eth_rx_data,
      eth_tx_ready_i => eth_tx_ready,
      eth_tx_valid_o => eth_tx_valid,
      eth_tx_last_o  => eth_tx_last,
      eth_tx_data_o  => eth_tx_data
    ); -- rrnet_inst

  -- TBD
  eth_rx_valid <= '0';
  eth_rx_last  <= '0';
  eth_rx_ok    <= '0';
  eth_rx_data  <= (others => '0');

  axip_logger_inst : entity work.axip_logger
    generic map (
      G_ENABLE        => true,
      G_LOG_NAME      => "   ",
      G_BYTES_PER_ROW => 1,
      G_DATA_BYTES    => 1
    )
    port map (
      clk_i   => clk,
      rst_i   => rst,
      ready_i => eth_tx_ready,
      valid_i => eth_tx_valid,
      data_i  => eth_tx_data,
      last_i  => eth_tx_last,
      bytes_i => 1
    ); -- axip_logger_inst

  -- eth_tx_ready may only be asserted on every other clock cycle.
  -- This is a baked-in assumption in the rrnet.vhd file.
  eth_tx_ready <= not eth_tx_ready when rising_edge(clk);

  -- Simple address decoding
  rrnet_cs    <= '1' when cpu_addr(15 downto 8) = x"DE" else
                 '0';
  rom_cs      <= '1' when cpu_addr >= x"F800" else
                 '0';
  ram_cs      <= '1' when cpu_addr < x"0800" else
                 '0';

  cpu_rd_data <= rrnet_rd_data when rrnet_cs = '1' else
                 rom_rd_data when rom_cs = '1' else
                 ram_rd_data;


  -- Instantiate RAM @ 0000
  tdp_ram_inst : entity work.tdp_ram
    generic map (
      ADDR_WIDTH   => 11,
      DATA_WIDTH   => 8,
      ROM_PRELOAD  => false,
      ROM_FILE     => "",
      ROM_FILE_HEX => true
    )
    port map (
      clock_a   => clk,
      clen_a    => '1',
      address_a => cpu_addr(10 downto 0),
      data_a    => cpu_wr_data,
      wren_a    => cpu_wr_en,
      q_a       => ram_rd_data,
      clock_b   => '0',
      clen_b    => '0',
      address_b => (others => '0'),
      data_b    => (others => '0'),
      wren_b    => '0',
      q_b       => open
    ); -- tdp_ram_inst

  -- Instantiate writeable ROM @ F800
  -- The ROM is writeable as a hack to allow writing
  -- to the variables 'bufaddr' and 'bufsize', see rrnet.asm.
  tdp_rom_inst : entity work.tdp_ram
    generic map (
      ADDR_WIDTH   => 11,
      DATA_WIDTH   => 8,
      ROM_PRELOAD  => true,
      ROM_FILE     => G_ROM_FILE,
      ROM_FILE_HEX => true
    )
    port map (
      clock_a   => clk,
      clen_a    => '1',
      address_a => cpu_addr(10 downto 0),
      data_a    => cpu_wr_data,
      wren_a    => cpu_wr_en,
      q_a       => rom_rd_data,
      clock_b   => '0',
      clen_b    => '0',
      address_b => (others => '0'),
      data_b    => (others => '0'),
      wren_b    => '0',
      q_b       => open
    ); -- tdp_rom_inst

  -- Instantiate CPU
  cpu_65c02_inst : entity work.cpu_65c02
    generic map (
      G_LOG_NAME => G_LOG_FILE,
      G_SIM      => true,
      G_VERBOSE  => 2,
      G_VARIANT  => "6502"
    )
    port map (
      clk_i       => clk,
      rst_i       => rst,
      ce_i        => ce,
      nmi_i       => '0',
      irq_i       => '0',
      addr_o      => cpu_addr,
      wr_en_o     => cpu_wr_en,
      wr_data_o   => cpu_wr_data,
      rd_en_o     => cpu_rd_en,
      rd_data_i   => cpu_rd_data,
      ioport_in_i => (others => '1'),
      debug_o     => open
    ); -- cpu_65c02_inst

end architecture tb;

