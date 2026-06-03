library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

-- This allows a Wishbone Slave to be connected to an Avalon Master

entity wbus_mem is
  generic (
    G_ADDR_SIZE : natural;
    G_DATA_SIZE : natural
  );
  port (
    clk_i     : in    std_logic;
    rst_i     : in    std_logic;
    s_cyc_i   : in    std_logic;
    s_stall_o : out   std_logic;
    s_stb_i   : in    std_logic;
    s_addr_i  : in    std_logic_vector(G_ADDR_SIZE - 1 downto 0);
    s_we_i    : in    std_logic;
    s_wrdat_i : in    std_logic_vector(G_DATA_SIZE - 1 downto 0);
    s_ack_o   : out   std_logic;
    s_rddat_o : out   std_logic_vector(G_DATA_SIZE - 1 downto 0);
    s_int_o   : out   std_logic
  );
end entity wbus_mem;

architecture synthesis of wbus_mem is

  type   ram_type is array (natural range <>) of std_logic_vector(G_DATA_SIZE - 1 downto 0);

  pure function init_mem return ram_type is
    variable res_v    : ram_type(0 to 2 ** G_ADDR_SIZE - 1);
    variable addr_v   : std_logic_vector(G_ADDR_SIZE - 1 downto 0);
    variable concat_v : std_logic_vector(4 * G_ADDR_SIZE - 1 downto 0);
    variable data_v   : std_logic_vector(G_DATA_SIZE - 1 downto 0);
  begin

    for i in 0 to 2 ** G_ADDR_SIZE - 1 loop
      addr_v   := to_stdlogicvector(i, G_ADDR_SIZE);
      concat_v := addr_v & addr_v & addr_v & addr_v;
      data_v   := concat_v(G_DATA_SIZE downto 1) + concat_v(G_DATA_SIZE - 1 downto 0);
      data_v   := concat_v(G_DATA_SIZE - 1 downto 0);
      res_v(i) := data_v;
    end loop;

    return res_v;
  end function init_mem;

  signal ram : ram_type(0 to 2 ** G_ADDR_SIZE - 1) := init_mem;

begin

  s_int_o   <= '0';

  s_stall_o <= '0';

  ram_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      s_ack_o <= '0';
      if s_cyc_i = '1' and s_stall_o = '0' and s_stb_i = '1' and s_we_i = '1' then
        ram(to_integer(s_addr_i)) <= s_wrdat_i;
        s_ack_o                   <= '1';
      end if;
      if s_cyc_i = '1' and s_stall_o = '0' and s_stb_i = '1' and s_we_i = '0' then
        s_ack_o   <= '1';
        s_rddat_o <= ram(to_integer(s_addr_i));
      end if;
    end if;
  end process ram_proc;

end architecture synthesis;

