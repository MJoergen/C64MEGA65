library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity sweeper is
  generic (
    G_ADDR_SIZE : natural;
    G_DATA_SIZE : natural
  );
  port (
    clk_i        : in    std_logic;
    rst_i        : in    std_logic;

    start_i      : in    std_logic;
    busy_o       : out   std_logic;
    crc_o        : out   std_logic_vector(31 downto 0);

    -- Wishbone bus Master interface
    wbus_cyc_o   : out   std_logic;                                  -- Valid bus cycle
    wbus_stall_i : in    std_logic;
    wbus_stb_o   : out   std_logic;                                  -- Strobe signals / core select signal
    wbus_addr_o  : out   std_logic_vector(G_ADDR_SIZE - 1 downto 0); -- lower address bits
    wbus_we_o    : out   std_logic;                                  -- Write enable
    wbus_wrdat_o : out   std_logic_vector(G_DATA_SIZE - 1 downto 0); -- Write Databus
    wbus_ack_i   : in    std_logic;                                  -- Bus cycle acknowledge
    wbus_rddat_i : in    std_logic_vector(G_DATA_SIZE - 1 downto 0)  -- Read Databus
  );
end entity sweeper;

architecture synthesis of sweeper is

  type   state_type is (IDLE_ST, BUSY_ST);
  signal state : state_type := IDLE_ST;

  signal crc_cur  : std_logic_vector(31 downto 0);
  signal crc_data : std_logic_vector(7 downto 0);
  signal crc_new  : std_logic_vector(31 downto 0);

  signal data_start   : std_logic;
  signal data_valid   : std_logic;
  signal data_final   : std_logic;
  signal data_final_d : std_logic;

begin

  -- Only does read
  wbus_we_o    <= '0';
  wbus_wrdat_o <= (others => '0');

  busy_o       <= '0' when state = IDLE_ST else
                  '1';

  wbus_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if wbus_stall_i = '0' then
        wbus_stb_o <= '0';
      end if;

      if wbus_ack_i = '1' then
        wbus_cyc_o <= '0';
      end if;

      data_start <= '0';
      data_final <= '0';

      case state is

        when IDLE_ST =>
          if start_i = '1' then
            data_start  <= '1';
            wbus_cyc_o  <= '1';
            wbus_stb_o  <= '1';
            wbus_addr_o <= (others => '0');
            state       <= BUSY_ST;
          end if;

        when BUSY_ST =>
          if wbus_stall_i = '0' or wbus_stb_o = '0' then
            if and (wbus_addr_o) = '1' then
              data_final <= '1';
              state      <= IDLE_ST;
            else
              wbus_addr_o <= std_logic_vector(unsigned(wbus_addr_o) + 1);
              wbus_cyc_o  <= '1';
              wbus_stb_o  <= '1';
            end if;
          end if;

      end case;

      if rst_i = '1' then
        data_start  <= '1';
        data_final  <= '1';
        wbus_cyc_o  <= '0';
        wbus_stb_o  <= '0';
        wbus_addr_o <= (others => '0');
        state       <= IDLE_ST;
      end if;
    end if;
  end process wbus_proc;

  data_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      data_final_d <= data_final;
      data_valid   <= '0';
      if wbus_ack_i = '1' then
        crc_data   <= wbus_rddat_i;
        data_valid <= '1';
      end if;
    end if;
  end process data_proc;

  crc_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if data_valid = '1' then
        crc_cur <= crc_new;
        if data_final_d = '1' then
          crc_o <= crc_new;
        end if;
      end if;

      if data_start = '1' then
        crc_cur <= (others => '1');
      end if;
    end if;
  end process crc_proc;


  --------------------------------
  -- Instantiate CRC calculation
  --------------------------------

  crc_inst : entity work.crc
    port map (
      crc_i  => crc_cur,
      data_i => crc_data,
      crc_o  => crc_new
    ); -- crc_inst : entity work.crc

end architecture synthesis;

