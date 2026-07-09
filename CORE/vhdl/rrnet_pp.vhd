-- ----------------------------------------------------------
-- Description: Packet Page memory of the CS8900A chip
-- ----------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity rrnet_pp is
  generic (
    G_INIT : std_logic_vector(4096 * 8 - 1 downto 0) := (others => '0')
  );
  port (
    clk_i      : in    std_logic;
    a_addr_i   : in    unsigned(11 downto 0); -- Byte address
    a_wren_i   : in    std_logic_vector(1 downto 0);
    a_wrdata_i : in    std_logic_vector(15 downto 0);
    a_rddata_o : out   std_logic_vector(15 downto 0);
    b_addr_i   : in    unsigned(11 downto 0); -- Byte address
    b_wren_i   : in    std_logic_vector(1 downto 0);
    b_wrdata_i : in    std_logic_vector(15 downto 0);
    b_rddata_o : out   std_logic_vector(15 downto 0)
  );
end entity rrnet_pp;

architecture rtl of rrnet_pp is

  -- This holds the entire 2k words of PacketPage memory.
  type   byte_array_type is array (natural range <>) of std_logic_vector(15 downto 0);

  -- This generates the reset-value of the 2k words PacketPage memory.

  pure function get_packet_page_init return byte_array_type is
    variable ret_v : byte_array_type(0 to 2047) := (others => (others => '0'));
  begin
    for i in 0 to 2047 loop
      ret_v(i) := G_INIT(16 * i + 15 downto 16 * i);
    end loop;
    return ret_v;
  end function get_packet_page_init;

  signal packet_page : byte_array_type(0 to 2047) := get_packet_page_init;

begin

  dual_port_ram_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      assert a_addr_i(0) = '0'
        report "a_addr_i(0) should be zero"
        severity failure;
      if a_wren_i(0) = '1' then
        report "PP: WRITE " & to_hstring(a_wrdata_i(7 downto 0)) & " TO $" & to_hstring(a_addr_i);
        packet_page(to_integer(a_addr_i(11 downto 1)))(7 downto 0) <= a_wrdata_i(7 downto 0);
      end if;
      if a_wren_i(1) = '1' then
        report "PP: WRITE " & to_hstring(a_wrdata_i(15 downto 8)) & " TO $" & to_hstring(a_addr_i + 1);
        packet_page(to_integer(a_addr_i(11 downto 1)))(15 downto 8) <= a_wrdata_i(15 downto 8);
      end if;
      a_rddata_o <= packet_page(to_integer(a_addr_i(11 downto 1)));

      assert b_addr_i(0) = '0'
        report "b_addr_i(0) should be zero"
        severity failure;
      if b_wren_i(0) = '1' then
        report "PP: WRITE " & to_hstring(b_wrdata_i(7 downto 0)) & " TO $" & to_hstring(b_addr_i);
        packet_page(to_integer(b_addr_i(11 downto 1)))(7 downto 0) <= b_wrdata_i(7 downto 0);
      end if;
      if b_wren_i(1) = '1' then
        report "PP: WRITE " & to_hstring(b_wrdata_i(15 downto 8)) & " TO $" & to_hstring(b_addr_i + 1);
        packet_page(to_integer(b_addr_i(11 downto 1)))(15 downto 8) <= b_wrdata_i(15 downto 8);
      end if;
      b_rddata_o <= packet_page(to_integer(b_addr_i(11 downto 1)));
    end if;
  end process dual_port_ram_proc;

end architecture rtl;

