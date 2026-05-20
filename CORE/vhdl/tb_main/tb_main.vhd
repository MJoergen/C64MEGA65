library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use work.fmt.f;
  use std.textio.all;

entity tb_main is
  generic (
    G_CRT_FILE_NAME : string := ""
  );
end entity tb_main;

architecture simulation of tb_main is

  signal   clk_main   : std_logic       := '1';
  signal   reset_soft : std_logic       := '1';
  signal   reset_hard : std_logic       := '1';

  signal   c64_ram_addr     : unsigned(15 downto 0);
  signal   c64_ram_data_out : unsigned( 7 downto 0);
  signal   c64_ram_we       : std_logic;
  signal   c64_ram_data_in  : unsigned( 7 downto 0);

  signal   avm_waitrequest   : std_logic;
  signal   avm_write         : std_logic;
  signal   avm_read          : std_logic;
  signal   avm_address       : std_logic_vector(31 downto 0);
  signal   avm_writedata     : std_logic_vector(15 downto 0);
  signal   avm_byteenable    : std_logic_vector( 1 downto 0);
  signal   avm_burstcount    : std_logic_vector( 7 downto 0);
  signal   avm_readdata      : std_logic_vector(15 downto 0);
  signal   avm_readdatavalid : std_logic;

  signal   video_ce     : std_logic;
  signal   video_ce_ovl : std_logic;
  signal   video_red    : std_logic_vector(7 downto 0);
  signal   video_green  : std_logic_vector(7 downto 0);
  signal   video_blue   : std_logic_vector(7 downto 0);
  signal   video_vs     : std_logic;
  signal   video_hs     : std_logic;
  signal   video_hblank : std_logic;
  signal   video_vblank : std_logic;

  signal   kb_key_num       : integer range 0 to 79; -- cycles through all MEGA65 keys
  signal   kb_key_pressed_n : std_logic := '1';      -- active low
  constant M65_1            : integer   := 56;
  constant M65_F7           : integer   := 3;
  constant M65_M            : integer   := 36;
  constant M65_RESTORE      : integer   := 75;
  constant M65_F9           : integer   := 68; -- FREEZE
  constant M65_7            : integer   := 24;

  signal   main_reset_core       : std_logic;
  signal   main_crt_loading      : std_logic;
  signal   main_crt_id           : std_logic_vector(15 downto 0);
  signal   main_crt_exrom        : std_logic_vector( 7 downto 0);
  signal   main_crt_game         : std_logic_vector( 7 downto 0);
  signal   main_crt_size         : std_logic_vector(22 downto 0);
  signal   main_crt_bank_laddr   : std_logic_vector(15 downto 0);
  signal   main_crt_bank_size    : std_logic_vector(15 downto 0);
  signal   main_crt_bank_num     : std_logic_vector(15 downto 0);
  signal   main_crt_bank_raddr   : std_logic_vector(24 downto 0);
  signal   main_crt_bank_wr      : std_logic;
  signal   main_crt_bank_wait    : std_logic;
  signal   main_crt_lo_ram_data  : std_logic_vector(15 downto 0);
  signal   main_crt_hi_ram_data  : std_logic_vector(15 downto 0);
  signal   main_crt_ioe_ram_data : std_logic_vector( 7 downto 0);
  signal   main_crt_iof_ram_data : std_logic_vector( 7 downto 0);
  signal   main_crt_addr_bus     : unsigned(15 downto 0);
  signal   main_crt_ioe_we       : std_logic;
  signal   main_crt_iof_we       : std_logic;
  signal   main_crt_bank_lo      : std_logic_vector( 6 downto 0);
  signal   main_crt_bank_hi      : std_logic_vector( 6 downto 0);
  signal   main_crt_we           : std_logic;
  signal   main_crt_ram_data     : std_logic_vector( 7 downto 0);

  signal   hr_clk           : std_logic := '1';
  signal   hr_rst           : std_logic := '1';
  signal   hr_write         : std_logic;
  signal   hr_read          : std_logic;
  signal   hr_address       : std_logic_vector(31 downto 0);
  signal   hr_writedata     : std_logic_vector(15 downto 0);
  signal   hr_byteenable    : std_logic_vector( 1 downto 0);
  signal   hr_burstcount    : std_logic_vector( 7 downto 0);
  signal   hr_readdata      : std_logic_vector(15 downto 0);
  signal   hr_readdatavalid : std_logic;
  signal   hr_waitrequest   : std_logic;
  signal   hr_length        : natural;

  signal   qnice_clk       : std_logic := '1';
  signal   qnice_rst       : std_logic := '1';
  signal   qnice_running   : std_logic;
  signal   qnice_addr      : std_logic_vector(27 downto 0);
  signal   qnice_writedata : std_logic_vector(15 downto 0);
  signal   qnice_readdata  : std_logic_vector(15 downto 0);
  signal   qnice_ce        : std_logic;
  signal   qnice_we        : std_logic;
  signal   qnice_wait      : std_logic;

begin

  clk_main   <= not clk_main  after 16 ns;                   --  31.25 MHz
  reset_soft <= '1', '0' after 200 ns;
  reset_hard <= '1', '0' after 200 ns;
  hr_clk     <= not hr_clk    after  5 ns;                   -- 100 MHz
  hr_rst     <= '1', '0' after 200 ns;
  qnice_clk  <= qnice_running and not qnice_clk after 10 ns; --  50 MHz
  qnice_rst  <= '1', '0' after 200 ns;


  ---------------------------------------
  -- Instantiate main
  ---------------------------------------

  main_inst : entity work.main
    generic map (
      G_BOARD => "MEGA65_R6",
      G_VDNUM => 1
    )
    port map (
      clk_main_i             => clk_main,
      reset_soft_i           => reset_soft or main_reset_core,
      reset_hard_i           => reset_hard,
      pause_i                => '0',
      trigger_run_i          => '0',
      c64_rom_i              => "01",
      c64_ntsc_i             => '0',
      clk_main_speed_i       => 1_000_000_000 / 32,
      video_retro15khz_i     => '0',
      c64_sid_ver_i          => "00",
      c64_sid_port_i         => "000",
      c64_cia_ver_i          => '0',
      c64_exp_port_mode_i    => "01", -- Disable SIM_REU, Enable SIM_CRT.
      kb_key_num_i           => kb_key_num,
      kb_key_pressed_n_i     => kb_key_pressed_n,
      joy_1_up_n_i           => '1',
      joy_1_down_n_i         => '1',
      joy_1_left_n_i         => '1',
      joy_1_right_n_i        => '1',
      joy_1_fire_n_i         => '1',
      joy_1_up_n_o           => open,
      joy_1_down_n_o         => open,
      joy_1_left_n_o         => open,
      joy_1_right_n_o        => open,
      joy_1_fire_n_o         => open,
      joy_2_up_n_i           => '1',
      joy_2_down_n_i         => '1',
      joy_2_left_n_i         => '1',
      joy_2_right_n_i        => '1',
      joy_2_fire_n_i         => '1',
      joy_2_up_n_o           => open,
      joy_2_down_n_o         => open,
      joy_2_left_n_o         => open,
      joy_2_right_n_o        => open,
      joy_2_fire_n_o         => open,
      pot1_x_i               => X"FF",
      pot1_y_i               => X"FF",
      pot2_x_i               => X"FF",
      pot2_y_i               => X"FF",
      video_ce_o             => video_ce,
      video_ce_ovl_o         => video_ce_ovl,
      video_red_o            => video_red,
      video_green_o          => video_green,
      video_blue_o           => video_blue,
      video_vs_o             => video_vs,
      video_hs_o             => video_hs,
      video_hblank_o         => video_hblank,
      video_vblank_o         => video_vblank,
      audio_left_o           => open,
      audio_right_o          => open,
      drive_led_o            => open,
      drive_led_col_o        => open,
      c64_ram_addr_o         => c64_ram_addr,
      c64_ram_data_o         => c64_ram_data_out,
      c64_ram_we_o           => c64_ram_we,
      c64_ram_data_i         => c64_ram_data_in,
      c64_clk_sd_i           => clk_main,
      c64_qnice_addr_i       => (others => '0'),
      c64_qnice_data_i       => X"0000",
      c64_qnice_data_o       => open,
      c64_qnice_ce_i         => '0',
      c64_qnice_we_i         => '0',
      iec_hardware_port_en_i => '0',
      iec_reset_n_o          => open,
      iec_atn_n_o            => open,
      iec_clk_en_o           => open,
      iec_clk_n_i            => '0',
      iec_clk_n_o            => open,
      iec_data_en_o          => open,
      iec_data_n_i           => '0',
      iec_data_n_o           => open,
      iec_srq_en_o           => open,
      iec_srq_n_i            => '0',
      iec_srq_n_o            => open,
      cart_en_o              => open,
      cart_phi2_o            => open,
      cart_dotclock_o        => open,
      cart_dma_i             => '0',
      cart_reset_oe_o        => open,
      cart_reset_i           => '1',
      cart_reset_o           => open,
      cart_game_oe_o         => open,
      cart_game_i            => '1',
      cart_game_o            => open,
      cart_exrom_oe_o        => open,
      cart_exrom_i           => '1',
      cart_exrom_o           => open,
      cart_nmi_oe_o          => open,
      cart_nmi_i             => '1',
      cart_nmi_o             => open,
      cart_irq_oe_o          => open,
      cart_irq_i             => '1',
      cart_irq_o             => open,
      cart_roml_oe_o         => open,
      cart_roml_i            => '0',
      cart_roml_o            => open,
      cart_romh_oe_o         => open,
      cart_romh_i            => '0',
      cart_romh_o            => open,
      cart_ctrl_oe_o         => open,
      cart_ba_i              => '0',
      cart_rw_i              => '0',
      cart_io1_i             => '0',
      cart_io2_i             => '0',
      cart_ba_o              => open,
      cart_rw_o              => open,
      cart_io1_o             => open,
      cart_io2_o             => open,
      cart_addr_oe_o         => open,
      cart_a_i               => X"0000",
      cart_a_o               => open,
      cart_data_oe_o         => open,
      cart_d_i               => X"00",
      cart_d_o               => open,
      avm_waitrequest_i      => avm_waitrequest,
      avm_write_o            => avm_write,
      avm_read_o             => avm_read,
      avm_address_o          => avm_address,
      avm_writedata_o        => avm_writedata,
      avm_byteenable_o       => avm_byteenable,
      avm_burstcount_o       => avm_burstcount,
      avm_readdata_i         => avm_readdata,
      avm_readdatavalid_i    => avm_readdatavalid,
      cartridge_loading_i    => main_crt_loading,
      cartridge_id_i         => main_crt_id,
      cartridge_exrom_i      => main_crt_exrom,
      cartridge_game_i       => main_crt_game,
      cartridge_size_i       => main_crt_size,
      cartridge_bank_laddr_i => main_crt_bank_laddr,
      cartridge_bank_size_i  => main_crt_bank_size,
      cartridge_bank_num_i   => main_crt_bank_num,
      cartridge_bank_raddr_i => main_crt_bank_raddr,
      cartridge_bank_wr_i    => main_crt_bank_wr,
      crt_bank_wait_i        => main_crt_bank_wait,
      crt_lo_ram_data_i      => main_crt_lo_ram_data,
      crt_hi_ram_data_i      => main_crt_hi_ram_data,
      crt_ioe_ram_data_i     => main_crt_ioe_ram_data,
      crt_iof_ram_data_i     => main_crt_iof_ram_data,
      crt_addr_bus_o         => main_crt_addr_bus,
      crt_ioe_we_o           => main_crt_ioe_we,
      crt_iof_we_o           => main_crt_iof_we,
      crt_bank_lo_o          => main_crt_bank_lo,
      crt_bank_hi_o          => main_crt_bank_hi,
      crt_we_o               => main_crt_we,
      crt_ram_data_i         => main_crt_ram_data,
      c64rom_we_i            => '0',
      c64rom_addr_i          => (others => '0'),
      c64rom_data_i          => X"00",
      c64rom_data_o          => open,
      c1541rom_we_i          => '0',
      c1541rom_addr_i        => X"0000",
      c1541rom_data_i        => X"00",
      c1541rom_data_o        => open,
      rtc_i                  => (others => '0')
    ); -- main_inst : entity work.main


  ---------------------------------------
  -- This holds the C64 RAM (64kB)
  ---------------------------------------

  c64_ram_proc : process (clk_main)
    --

    type     ram_type is array (natural range 0 to 65535) of unsigned(7 downto 0);
    variable ram_v   : ram_type := (others => x"EE");
  begin
    if rising_edge(clk_main) then
      if c64_ram_we = '1' then
        ram_v(to_integer(c64_ram_addr)) := c64_ram_data_out;
      end if;
      c64_ram_data_in <= ram_v(to_integer(c64_ram_addr));
    end if;
  end process c64_ram_proc;


  ---------------------------------------
  -- This injects key-presses
  ---------------------------------------

  keyboard_proc : process
  begin
    kb_key_pressed_n <= '1';

    wait for 700 ms;
    kb_key_num       <= M65_F7;
    kb_key_pressed_n <= '0';
    wait for 50 ms;
    kb_key_pressed_n <= '1';

    wait for 7500 ms;
    kb_key_num       <= M65_F9;
    kb_key_pressed_n <= '0';
    wait for 50 ms;
    kb_key_pressed_n <= '1';

    wait for 3000 ms;
    kb_key_num       <= M65_7;
    kb_key_pressed_n <= '0';
    wait for 50 ms;
    kb_key_pressed_n <= '1';

    wait;
  end process keyboard_proc;


  ---------------------------------------
  -- This holds the REU memory (512 kB)
  ---------------------------------------

  avm_memory_pause_inst : entity work.avm_memory_pause
    generic map (
      G_REQ_PAUSE    => 0, -- 10,
      G_RESP_PAUSE   => 0, -- 20,
      G_ADDRESS_SIZE => 18,
      G_DATA_SIZE    => 16
    )
    port map (
      clk_i               => clk_main,
      rst_i               => reset_soft,
      avm_write_i         => avm_write,
      avm_read_i          => avm_read,
      avm_address_i       => avm_address(17 downto 0),
      avm_writedata_i     => avm_writedata,
      avm_byteenable_i    => avm_byteenable,
      avm_burstcount_i    => avm_burstcount,
      avm_readdata_o      => avm_readdata,
      avm_readdatavalid_o => avm_readdatavalid,
      avm_waitrequest_o   => avm_waitrequest
    ); -- avm_memory_pause_inst : entity work.avm_memory_pause

  video_proc : process
    --

    type     char_file_type is file of character;
    file     video_file : char_file_type;
    variable b_v        : std_logic_vector(7 downto 0);
    variable x_v        : natural := 0;
    variable last_x_v   : natural;
    variable y_v        : natural := 0;
    variable last_y_v   : natural;
    variable f_v        : natural := 0;
  begin
    file_open(video_file, "frames/frame_" & f(f_v, "0>4u") & ".bin", write_mode);
    main_loop : loop
      wait until rising_edge(clk_main);
      if video_ce then
        if not video_hblank and not video_vblank then
          b_v := video_red(7 downto 5) & video_green(7 downto 5) & video_blue(7 downto 6);
          write(video_file, character'val(to_integer(unsigned(b_v))));
          x_v := x_v + 1;
        end if;

        if video_hs then
          if x_v > 0 then
            last_x_v := x_v;
            x_v      := 0;
            y_v      := y_v + 1;
          end if;
        end if;

        if video_vs then
          if y_v > 0 then
            last_y_v := y_v;
            y_v      := 0;
            f_v      := f_v + 1;

            file_close(video_file);
            file_open(video_file, "frames/frame_" & f(f_v, "0>4u") & ".bin", write_mode);
          end if;
          y_v := 0;
        end if;
      end if;
    end loop;

    wait;
  end process video_proc;


  ---------------------------------
  -- Simulated cartridge handling
  ---------------------------------

  sw_cartridge_wrapper_inst : entity work.sw_cartridge_wrapper
    generic map (
      G_BASE_ADDRESS => (others => '0')
    )
    port map (
      qnice_clk_i         => qnice_clk,
      qnice_rst_i         => qnice_rst,
      qnice_addr_i        => qnice_addr,
      qnice_data_i        => qnice_writedata,
      qnice_ce_i          => qnice_ce,
      qnice_we_i          => qnice_we,
      qnice_data_o        => qnice_readdata,
      qnice_wait_o        => qnice_wait,
      main_clk_i          => clk_main,
      main_rst_i          => reset_hard,
      main_reset_core_o   => main_reset_core,
      main_loading_o      => main_crt_loading,
      main_id_o           => main_crt_id,
      main_exrom_o        => main_crt_exrom,
      main_game_o         => main_crt_game,
      main_size_o         => main_crt_size,
      main_bank_laddr_o   => main_crt_bank_laddr,
      main_bank_size_o    => main_crt_bank_size,
      main_bank_num_o     => main_crt_bank_num,
      main_bank_raddr_o   => main_crt_bank_raddr,
      main_bank_wr_o      => main_crt_bank_wr,
      main_bank_lo_i      => main_crt_bank_lo,
      main_bank_hi_i      => main_crt_bank_hi,
      main_bank_wait_o    => main_crt_bank_wait,
      main_ram_addr_i     => std_logic_vector(main_crt_addr_bus),
      main_ram_data_i     => std_logic_vector(c64_ram_data_out),
      main_ioe_we_i       => main_crt_ioe_we,
      main_iof_we_i       => main_crt_iof_we,
      main_lo_ram_data_o  => main_crt_lo_ram_data,
      main_hi_ram_data_o  => main_crt_hi_ram_data,
      main_ioe_ram_data_o => main_crt_ioe_ram_data,
      main_iof_ram_data_o => main_crt_iof_ram_data,
      main_crt_we_i       => main_crt_we,
      main_crt_ram_data_o => main_crt_ram_data,
      hr_clk_i            => hr_clk,
      hr_rst_i            => hr_rst,
      hr_write_o          => hr_write,
      hr_read_o           => hr_read,
      hr_address_o        => hr_address,
      hr_writedata_o      => hr_writedata,
      hr_byteenable_o     => hr_byteenable,
      hr_burstcount_o     => hr_burstcount,
      hr_readdata_i       => hr_readdata,
      hr_readdatavalid_i  => hr_readdatavalid,
      hr_waitrequest_i    => hr_waitrequest
    ); -- sw_cartridge_wrapper_inst

  qnice_sim_inst : entity work.qnice_sim
    port map (
      qnice_clk_i       => qnice_clk,
      qnice_rst_i       => qnice_rst,
      qnice_addr_o      => qnice_addr,
      qnice_writedata_o => qnice_writedata,
      qnice_ce_o        => qnice_ce,
      qnice_we_o        => qnice_we,
      qnice_readdata_i  => qnice_readdata,
      qnice_wait_i      => qnice_wait,
      qnice_length_i    => std_logic_vector(to_unsigned(hr_length * 2, 32)),
      qnice_running_o   => qnice_running
    ); -- qnice_sim_inst

  avm_rom_inst : entity work.avm_rom
    generic map (
      G_INIT_FILE    => G_CRT_FILE_NAME,
      G_ADDRESS_SIZE => 20,
      G_DATA_SIZE    => 16
    )
    port map (
      clk_i               => hr_clk,
      rst_i               => hr_rst,
      avm_write_i         => hr_write,
      avm_read_i          => hr_read,
      avm_address_i       => hr_address(19 downto 0),
      avm_writedata_i     => hr_writedata,
      avm_byteenable_i    => hr_byteenable,
      avm_burstcount_i    => hr_burstcount,
      avm_readdata_o      => hr_readdata,
      avm_readdatavalid_o => hr_readdatavalid,
      avm_waitrequest_o   => hr_waitrequest,
      length_o            => hr_length
    ); -- avm_rom_inst

end architecture simulation;

