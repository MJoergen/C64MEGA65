----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is the testbench for the MiSTer's reu module.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.numeric_std_unsigned.all;

entity tb_reu is
end entity tb_reu;

architecture simulation of tb_reu is

  signal cnt           : std_logic_vector(4 downto 0) := (others => '0');
  signal clk           : std_logic := '1';
  signal rst           : std_logic := '1';
  signal cfg           : std_logic_vector(1 downto 0);
  signal dma_req       : std_logic;
  signal dma_cycle     : std_logic;
  signal dma_addr      : std_logic_vector(15 downto 0);
  signal dma_dout      : std_logic_vector(7 downto 0);
  signal dma_din       : std_logic_vector(7 downto 0);
  signal dma_we        : std_logic;
  signal ram_cycle     : std_logic;
  signal ram_cycle_reu : std_logic;
  signal ram_addr      : std_logic_vector(24 downto 0);
  signal ram_dout      : std_logic_vector(7 downto 0);
  signal ram_din       : std_logic_vector(7 downto 0);
  signal ram_we        : std_logic;
  signal ram_cs        : std_logic;
  signal cpu_addr      : unsigned(15 downto 0);
  signal cpu_dout      : unsigned(7 downto 0);
  signal cpu_din       : unsigned(7 downto 0);
  signal cpu_we        : std_logic;
  signal cpu_cs        : std_logic;
  signal irq           : std_logic;

  signal avm_write         : std_logic;
  signal avm_read          : std_logic;
  signal avm_address       : std_logic_vector(31 downto 0);
  signal avm_writedata     : std_logic_vector(15 downto 0);
  signal avm_byteenable    : std_logic_vector(1 downto 0);
  signal avm_burstcount    : std_logic_vector(7 downto 0);
  signal avm_readdata      : std_logic_vector(15 downto 0);
  signal avm_readdatavalid : std_logic;
  signal avm_waitrequest   : std_logic;

  signal cache_write         : std_logic;
  signal cache_read          : std_logic;
  signal cache_address       : std_logic_vector(31 downto 0);
  signal cache_writedata     : std_logic_vector(15 downto 0);
  signal cache_byteenable    : std_logic_vector(1 downto 0);
  signal cache_burstcount    : std_logic_vector(7 downto 0);
  signal cache_readdata      : std_logic_vector(15 downto 0);
  signal cache_readdatavalid : std_logic;
  signal cache_waitrequest   : std_logic;

  signal hr_clk           : std_logic := '1';
  signal hr_clk_del       : std_logic := '1';
  signal hr_delay_refclk  : std_logic := '1';
  signal hr_rst           : std_logic := '1';

  signal hr_write         : std_logic;
  signal hr_read          : std_logic;
  signal hr_address       : std_logic_vector(31 downto 0);
  signal hr_writedata     : std_logic_vector(15 downto 0);
  signal hr_byteenable    : std_logic_vector(1 downto 0);
  signal hr_burstcount    : std_logic_vector(7 downto 0);
  signal hr_readdata      : std_logic_vector(15 downto 0);
  signal hr_readdatavalid : std_logic;
  signal hr_waitrequest   : std_logic;

  signal hr_resetn    : std_logic;
  signal hr_csn       : std_logic;
  signal hr_ck        : std_logic;
  signal hr_rwds_in   : std_logic;
  signal hr_rwds_out  : std_logic;
  signal hr_rwds_oe_n : std_logic;                    -- Output enable for RWDS
  signal hr_rwds      : std_logic;
  signal hr_dq_in     : std_logic_vector(7 downto 0);
  signal hr_dq_out    : std_logic_vector(7 downto 0);
  signal hr_dq_oe_n   : std_logic_vector(7 downto 0); -- Output enable for DQ
  signal hr_dq        : std_logic_vector(7 downto 0);

  component reu is
    port (
      clk       : in    std_logic;
      reset     : in    std_logic;
      cfg       : in    std_logic_vector(1 downto 0);
      dma_req   : out   std_logic;
      dma_cycle : in    std_logic;
      dma_addr  : out   std_logic_vector(15 downto 0);
      dma_dout  : out   std_logic_vector(7 downto 0);
      dma_din   : in    std_logic_vector(7 downto 0);
      dma_we    : out   std_logic;
      ram_cycle : in    std_logic;
      ram_addr  : out   std_logic_vector(24 downto 0);
      ram_dout  : out   std_logic_vector(7 downto 0);
      ram_din   : in    std_logic_vector(7 downto 0);
      ram_we    : out   std_logic;
      ram_cs    : out   std_logic;
      cpu_addr  : in    unsigned(15 downto 0);
      cpu_dout  : in    unsigned(7 downto 0);
      cpu_din   : out   unsigned(7 downto 0);
      cpu_we    : in    std_logic;
      cpu_cs    : in    std_logic;
      irq       : out   std_logic
    );
  end component reu;

  component s27kl0642 is
     port (
        dq7      : inout std_logic;
        dq6      : inout std_logic;
        dq5      : inout std_logic;
        dq4      : inout std_logic;
        dq3      : inout std_logic;
        dq2      : inout std_logic;
        dq1      : inout std_logic;
        dq0      : inout std_logic;
        rwds     : inout std_logic;
        csneg    : in    std_logic;
        ck       : in    std_logic;
        ckn      : in    std_logic;
        resetneg : in    std_logic
     );
  end component s27kl0642;


  -- This defines a type containing an array of bytes
  type   ram_type is array (0 to 255) of std_logic_vector(7 downto 0);
  signal ram : ram_type                               := (
                                                           0 => X"11",
                                                          1 => X"22",
                                                          2 => X"33",
                                                          3 => X"44",
                                                          4 => X"55",
                                                          5 => X"66",
                                                          6 => X"77",
                                                          7 => X"88",
                                                          8 => X"99",
                                                          9 => X"AA",
                                                          10 => X"BB",
                                                          11 => X"CC",
                                                          12 => X"DD",
                                                          13 => X"EE",
                                                          14 => X"FF",
                                                          15 => X"0A",
                                                          others => X"UU");

begin

  -------------------
  -- Clock and reset
  -------------------

  clk <= not clk after 15 ns;
  rst <= '1', '0' after 1000 ns;

  hr_clk <= not hr_clk after 5 ns;
  hr_rst <= '1', '0' after 500 ns;
  hr_clk_del <= transport hr_clk after 2.5 ns;
  hr_delay_refclk <= not hr_delay_refclk after 2.5 ns;


  -----------------------
  -- CPU synchronization
  -----------------------

  cnt_proc : process (clk)
  begin
    if rising_edge(clk) then
      cnt <= cnt + 1;
    end if;
  end process cnt_proc;

  --                     1         2         3
  --           01234567890123456789012345678901
  -- dma_cycle ________________****************
  -- ram_cycle ____****________________________
  -- cpu_cs    ________________****************

  ram_cycle <= '1' when cnt >=  4 and cnt <=  7 else
               '0';
  dma_cycle <= '1' when cnt >= 16 and cnt <= 31 else
               '0';


  -----------------------
  -- Main test procedure
  -----------------------

  test_proc : process
    --

    procedure cpu_write (
      addr : std_logic_vector(15 downto 0);
      data : std_logic_vector(7 downto 0)
    ) is
    begin
      wait until dma_cycle = '1';
      cpu_addr <= unsigned(addr);
      cpu_dout <= unsigned(data);
      cpu_we   <= '1';
      cpu_cs   <= '1';
      wait until dma_cycle = '0';
      cpu_we   <= '0';
      cpu_cs   <= '0';
    end procedure cpu_write;

    procedure write_to_hr (
      ram_addr : std_logic_vector(15 downto 0);
      hr_addr  : std_logic_vector(23 downto 0);
      length   : std_logic_vector(15 downto 0)
    ) is
    begin
      cpu_write(X"DF02", ram_addr( 7 downto  0));
      cpu_write(X"DF03", ram_addr(15 downto  8));
      cpu_write(X"DF04",  hr_addr( 7 downto  0));
      cpu_write(X"DF05",  hr_addr(15 downto  8));
      cpu_write(X"DF06",  hr_addr(23 downto 16));
      cpu_write(X"DF07",   length( 7 downto  0));
      cpu_write(X"DF08",   length(15 downto  8));
      cpu_write(X"DF01", X"90"); -- Write to HyperRAM
    end procedure write_to_hr;

    procedure read_from_hr (
      ram_addr : std_logic_vector(15 downto 0);
      hr_addr  : std_logic_vector(23 downto 0);
      length   : std_logic_vector(15 downto 0)
    ) is
    begin
      cpu_write(X"DF02", ram_addr( 7 downto  0));
      cpu_write(X"DF03", ram_addr(15 downto  8));
      cpu_write(X"DF04",  hr_addr( 7 downto  0));
      cpu_write(X"DF05",  hr_addr(15 downto  8));
      cpu_write(X"DF06",  hr_addr(23 downto 16));
      cpu_write(X"DF07",   length( 7 downto  0));
      cpu_write(X"DF08",   length(15 downto  8));
      cpu_write(X"DF01", X"91"); -- Read from HyperRAM
    end procedure read_from_hr;

  begin
    cpu_cs <= '0';
    wait for 200 us;
    wait until clk = '1';

    assert ram( 0) = X"11";
    assert ram( 1) = X"22";
    assert ram( 2) = X"33";
    assert ram( 3) = X"44";
    assert ram( 4) = X"55";
    assert ram( 5) = X"66";
    assert ram( 6) = X"77";
    assert ram( 7) = X"88";
    assert ram( 8) = X"99";
    assert ram( 9) = X"AA";
    assert ram(10) = X"BB";
    assert ram(11) = X"CC";
    assert ram(12) = X"DD";
    assert ram(13) = X"EE";
    assert ram(14) = X"FF";
    assert ram(15) = X"0A";

    write_to_hr(X"0000", X"07FFF0", X"0010");
    wait until dma_req = '0';
    wait until clk = '1';

    read_from_hr(X"0000", X"07FFF1", X"000F");
    wait until dma_req = '0';
    wait until clk = '1';

    assert ram( 0) = X"22";
    assert ram( 1) = X"33";
    assert ram( 2) = X"44";
    assert ram( 3) = X"55";
    assert ram( 4) = X"66";
    assert ram( 5) = X"77";
    assert ram( 6) = X"88";
    assert ram( 7) = X"99";
    assert ram( 8) = X"AA";
    assert ram( 9) = X"BB";
    assert ram(10) = X"CC";
    assert ram(11) = X"DD";
    assert ram(12) = X"EE";
    assert ram(13) = X"FF";
    assert ram(14) = X"0A";

    report "Test finished";
    wait;
  end process test_proc;


  -------------------
  -- Instantiate DUT
  -------------------

  reu_inst : component reu
    port map (
      clk       => clk,           -- in
      reset     => rst,           -- in
      cfg       => "10",          -- in
      dma_req   => dma_req,       -- out
      dma_cycle => dma_cycle,     -- in
      dma_addr  => dma_addr,      -- out
      dma_dout  => dma_dout,      -- out
      dma_din   => dma_din,       -- in
      dma_we    => dma_we,        -- out
      ram_cycle => ram_cycle_reu, -- in
      ram_addr  => ram_addr,      -- out
      ram_dout  => ram_dout,      -- out
      ram_din   => ram_din,       -- in
      ram_we    => ram_we,        -- out
      ram_cs    => ram_cs,        -- out
      cpu_addr  => cpu_addr,      -- in
      cpu_dout  => cpu_dout,      -- in
      cpu_din   => cpu_din,       -- out
      cpu_we    => cpu_we,        -- in
      cpu_cs    => cpu_cs,        -- in
      irq       => irq            -- out
    ); -- reu_inst

  ram_proc : process (clk)
  begin
    if rising_edge(clk) then
      if dma_we = '1' then
        ram(to_integer(dma_addr(7 downto 0))) <= dma_dout;
      end if;
      dma_din <= ram(to_integer(dma_addr(7 downto 0)));
    end if;
  end process ram_proc;


  reu_mapper_inst : entity work.reu_mapper
    generic map (
      G_BASE_ADDRESS => X"003C_0000"
    )
    port map (
      clk_i               => clk,
      rst_i               => rst,
      reu_ext_cycle_i     => ram_cycle,
      reu_ext_cycle_o     => ram_cycle_reu,
      reu_addr_i          => ram_addr,
      reu_dout_i          => ram_dout,
      reu_din_o           => ram_din,
      reu_we_i            => ram_we,
      reu_cs_i            => ram_cs,
      avm_write_o         => avm_write,
      avm_read_o          => avm_read,
      avm_address_o       => avm_address,
      avm_writedata_o     => avm_writedata,
      avm_byteenable_o    => avm_byteenable,
      avm_burstcount_o    => avm_burstcount,
      avm_readdata_i      => avm_readdata,
      avm_readdatavalid_i => avm_readdatavalid,
      avm_waitrequest_i   => avm_waitrequest
    ); -- reu_mapper_inst

  avm_cache_inst : entity work.avm_cache
    generic map (
      G_CACHE_SIZE   => 8,
      G_ADDRESS_SIZE => 32,
      G_DATA_SIZE    => 16
    )
    port map (
      clk_i                 => clk,
      rst_i                 => rst,
      s_avm_waitrequest_o   => avm_waitrequest,
      s_avm_write_i         => avm_write,
      s_avm_read_i          => avm_read,
      s_avm_address_i       => avm_address,
      s_avm_writedata_i     => avm_writedata,
      s_avm_byteenable_i    => avm_byteenable,
      s_avm_burstcount_i    => avm_burstcount,
      s_avm_readdata_o      => avm_readdata,
      s_avm_readdatavalid_o => avm_readdatavalid,
      m_avm_waitrequest_i   => cache_waitrequest,
      m_avm_write_o         => cache_write,
      m_avm_read_o          => cache_read,
      m_avm_address_o       => cache_address,
      m_avm_writedata_o     => cache_writedata,
      m_avm_byteenable_o    => cache_byteenable,
      m_avm_burstcount_o    => cache_burstcount,
      m_avm_readdata_i      => cache_readdata,
      m_avm_readdatavalid_i => cache_readdatavalid
    ); -- avm_cache_inst


   main2hr_avm_fifo : entity work.avm_fifo
      generic map (
         G_WR_DEPTH     => 16,
         G_RD_DEPTH     => 16,
         G_FILL_SIZE    => 1,
         G_ADDRESS_SIZE => 32,
         G_DATA_SIZE    => 16
      )
      port map (
         s_clk_i               => clk,
         s_rst_i               => rst,
         s_avm_waitrequest_o   => cache_waitrequest,
         s_avm_write_i         => cache_write,
         s_avm_read_i          => cache_read,
         s_avm_address_i       => cache_address,
         s_avm_writedata_i     => cache_writedata,
         s_avm_byteenable_i    => cache_byteenable,
         s_avm_burstcount_i    => cache_burstcount,
         s_avm_readdata_o      => cache_readdata,
         s_avm_readdatavalid_o => cache_readdatavalid,
         m_clk_i               => hr_clk,
         m_rst_i               => hr_rst,
         m_avm_waitrequest_i   => hr_waitrequest,
         m_avm_write_o         => hr_write,
         m_avm_read_o          => hr_read,
         m_avm_address_o       => hr_address,
         m_avm_writedata_o     => hr_writedata,
         m_avm_byteenable_o    => hr_byteenable,
         m_avm_burstcount_o    => hr_burstcount,
         m_avm_readdata_i      => hr_readdata,
         m_avm_readdatavalid_i => hr_readdatavalid
      ); -- main2hr_avm_fifo


  ---------------------------------------------------------
  -- Instantiate HyperRAM controller
  ---------------------------------------------------------

  hyperram_inst : entity work.hyperram
    generic map (
      G_ERRATA_ISSI_D_FIX => true
    )
    port map (
      clk_i               => hr_clk,
      clk_del_i           => hr_clk_del,
      delay_refclk_i      => hr_delay_refclk,
      rst_i               => hr_rst,
      avm_write_i         => hr_write,
      avm_read_i          => hr_read,
      avm_address_i       => hr_address,
      avm_writedata_i     => hr_writedata,
      avm_byteenable_i    => hr_byteenable,
      avm_burstcount_i    => hr_burstcount,
      avm_readdata_o      => hr_readdata,
      avm_readdatavalid_o => hr_readdatavalid,
      avm_waitrequest_o   => hr_waitrequest,
      count_long_o        => open,
      count_short_o       => open,
      hr_resetn_o         => hr_resetn,
      hr_csn_o            => hr_csn,
      hr_ck_o             => hr_ck,
      hr_rwds_in_i        => hr_rwds_in,
      hr_rwds_out_o       => hr_rwds_out,
      hr_rwds_oe_n_o      => hr_rwds_oe_n,
      hr_dq_in_i          => hr_dq_in,
      hr_dq_out_o         => hr_dq_out,
      hr_dq_oe_n_o        => hr_dq_oe_n
    ); -- hyperram_inst : entity work.hyperram


  ----------------------------------
  -- Tri-state buffers for HyperRAM
  ----------------------------------

  hr_rwds <= hr_rwds_out when hr_rwds_oe_n = '0' else
              'Z';

  hr_dq_gen : for i in 0 to 7 generate
     hr_dq(i) <= hr_dq_out(i) when hr_dq_oe_n(i) = '0' else
                  'Z';
  end generate hr_dq_gen;

  hr_rwds_in <= hr_rwds;
  hr_dq_in   <= hr_dq;



  ---------------------------------------------------------
  -- Instantiate HyperRAM simulation model
  ---------------------------------------------------------

  s27kl0642_inst : component s27kl0642
     port map (
        dq7      => hr_dq(7),
        dq6      => hr_dq(6),
        dq5      => hr_dq(5),
        dq4      => hr_dq(4),
        dq3      => hr_dq(3),
        dq2      => hr_dq(2),
        dq1      => hr_dq(1),
        dq0      => hr_dq(0),
        rwds     => hr_rwds,
        csneg    => hr_csn,
        ck       => hr_ck,
        ckn      => not hr_ck,
        resetneg => hr_resetn
     ); -- s27kl0642_inst

end architecture simulation;

