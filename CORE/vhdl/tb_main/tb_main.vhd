library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity tb_main is
end entity tb_main;

architecture simulation of tb_main is

  signal clk_main   : std_logic := '1';
  signal reset_soft : std_logic := '1';
  signal reset_hard : std_logic := '1';

  signal c64_ram_addr      : unsigned(15 downto 0);
  signal c64_ram_data_out  : unsigned( 7 downto 0);
  signal c64_ram_we        : std_logic;
  signal c64_ram_data_in   : unsigned( 7 downto 0);

  signal avm_waitrequest   : std_logic;
  signal avm_write         : std_logic;
  signal avm_read          : std_logic;
  signal avm_address       : std_logic_vector(31 downto 0);
  signal avm_writedata     : std_logic_vector(15 downto 0);
  signal avm_byteenable    : std_logic_vector( 1 downto 0);
  signal avm_burstcount    : std_logic_vector( 7 downto 0);
  signal avm_readdata      : std_logic_vector(15 downto 0);
  signal avm_readdatavalid : std_logic;

begin

  clk_main   <= not clk_main after 16 ns; -- Approx 31 MHz
  reset_soft <= '1', '0' after 200 ns;
  reset_hard <= '1', '0' after 200 ns;


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
      reset_soft_i           => reset_soft,
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
      c64_exp_port_mode_i    => 1,
      kb_key_num_i           => 0,
      kb_key_pressed_n_i     => '1',
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
      video_ce_o             => open,
      video_ce_ovl_o         => open,
      video_red_o            => open,
      video_green_o          => open,
      video_blue_o           => open,
      video_vs_o             => open,
      video_hs_o             => open,
      video_hblank_o         => open,
      video_vblank_o         => open,
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
      cartridge_loading_i    => '0',
      cartridge_id_i         => X"0000",
      cartridge_exrom_i      => X"00",
      cartridge_game_i       => X"00",
      cartridge_size_i       => (others => '0'),
      cartridge_bank_laddr_i => X"0000",
      cartridge_bank_size_i  => X"0000",
      cartridge_bank_num_i   => X"0000",
      cartridge_bank_raddr_i => (others => '0'),
      cartridge_bank_wr_i    => '0',
      crt_bank_wait_i        => '0',
      crt_lo_ram_data_i      => X"0000",
      crt_hi_ram_data_i      => X"0000",
      crt_ioe_ram_data_i     => X"00",
      crt_iof_ram_data_i     => X"00",
      crt_addr_bus_o         => open,
      crt_ioe_we_o           => open,
      crt_iof_we_o           => open,
      crt_bank_lo_o          => open,
      crt_bank_hi_o          => open,
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
    type     ram_type is array (natural range 0 to 65535) of unsigned(7 downto 0);
    variable ram_v : ram_type := (others => x"EE");
    variable first_v : boolean := true;
  begin
    if rising_edge(clk_main) then
      if first_v and c64_ram_we = '0' and c64_ram_addr = X"E5CD" then
        report "INJECT!!!";
        -- Inject LOAD"*",8 RUN
        ram_v(16#0277#) := X"4C";
        ram_v(16#0278#) := X"4F";
        ram_v(16#0279#) := X"41";
        ram_v(16#027A#) := X"44";
        ram_v(16#027B#) := X"22";
        ram_v(16#027C#) := X"2A";
        ram_v(16#027D#) := X"22";
        ram_v(16#027E#) := X"2C";
        ram_v(16#027F#) := X"38";
        ram_v(16#0280#) := X"0D";
        ram_v(16#0281#) := X"52";
        ram_v(16#0282#) := X"55";
        ram_v(16#0283#) := X"4E";
        ram_v(16#0284#) := X"0D";
        ram_v(16#00C6#) := X"0E";
        first_v := false;
      end if;
      if c64_ram_we = '1' then
        ram_v(to_integer(c64_ram_addr)) := c64_ram_data_out;
      end if;
      c64_ram_data_in <= ram_v(to_integer(c64_ram_addr));
    end if;
  end process c64_ram_proc;


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

end architecture simulation;

