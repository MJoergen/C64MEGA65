-- ---------------------------------------------------------------------------------------
-- Description: Verifies the contents of a stream of packets
--
-- Each packet is expected to begin with a one-byte length field, followed
-- by an increasing sequence of byte-values. The length field does not include itself.
--
-- SPDX-License-Identifier: MIT
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

library std;
  use std.env.stop;

entity axip_slave_sim is
  generic (
    G_NAME       : string := "";
    G_DEBUG      : boolean;
    G_CNT_SIZE   : positive;
    G_DATA_BYTES : positive
  );
  port (
    clk_i     : in    std_logic;
    rst_i     : in    std_logic;

    -- AXI packet input
    s_ready_o : out   std_logic;
    s_valid_i : in    std_logic;
    s_data_i  : in    std_logic_vector(G_DATA_BYTES * 8 - 1 downto 0);
    s_last_i  : in    std_logic;
    s_bytes_i : in    natural range 0 to G_DATA_BYTES
  );
end entity axip_slave_sim;

architecture simulation of axip_slave_sim is

  -- State machine for controlling reception and verification of AXI packets.
  type   state_type is (IDLE_ST, DATA_ST);
  signal state : state_type := IDLE_ST;

  signal verf_cnt   : std_logic_vector(G_CNT_SIZE - 1 downto 0);
  signal bytes_left : natural range 0 to 255;

begin

  ----------------------------------------------------------
  -- Verify AXI packet input
  -- First byte in packet is total packet length
  ----------------------------------------------------------

  s_ready_o <= '1';

  fsm_proc : process (clk_i)
    variable length_v : natural range 0 to 255;
    variable data_v   : std_logic_vector(7 downto 0);
  begin
    if rising_edge(clk_i) then

      case state is

        when IDLE_ST =>
          if s_valid_i = '1' then
            -- First beat of the packet
            length_v := to_integer(s_data_i(G_DATA_BYTES * 8 - 1 downto G_DATA_BYTES * 8 - 8));

            if G_DEBUG then
              report "axip_slave_sim " & G_NAME &
                     ": VERF length " & to_string(length_v) &
                     ", first byte " & to_hstring(verf_cnt(7 downto 0));
            end if;

            for i in 1 to G_DATA_BYTES - 1 loop
              if i < length_v then
                data_v := s_data_i((G_DATA_BYTES - 1 - i) * 8 + 7 downto (G_DATA_BYTES - 1 - i) * 8);
                assert data_v = verf_cnt(7 downto 0) + (i - 1)
                  report "axip_sim " & G_NAME &
                         ": Verify byte " & to_string(i) &
                         ". Received " & to_hstring(data_v) &
                         ", expected " & to_hstring(verf_cnt(7 downto 0) + i);
              end if;
            end loop;

            if s_last_i = '1' then
              verf_cnt <= verf_cnt + s_bytes_i - 1;
            else
              verf_cnt   <= verf_cnt + G_DATA_BYTES - 1;
              bytes_left <= length_v - (G_DATA_BYTES - 1);
              state      <= DATA_ST;
            end if;
          end if;

        when DATA_ST =>
          if s_valid_i = '1' then

            for i in 0 to G_DATA_BYTES - 1 loop
              if i < bytes_left then
                data_v := s_data_i((G_DATA_BYTES - 1 - i) * 8 + 7 downto (G_DATA_BYTES - 1 - i) * 8);
                assert data_v = verf_cnt(7 downto 0) + i
                  report "axip_sim " & G_NAME &
                         ": Verify byte " & to_string(i) &
                         ". Received " & to_hstring(data_v) &
                         ", expected " & to_hstring(verf_cnt(7 downto 0) + i);
              end if;
            end loop;

            if s_last_i = '1' then
              verf_cnt <= verf_cnt + s_bytes_i;
              state    <= IDLE_ST;
            else
              verf_cnt   <= verf_cnt + G_DATA_BYTES;
              bytes_left <= bytes_left - G_DATA_BYTES;
            end if;

            -- Check for wrap-around
            if verf_cnt > verf_cnt + s_bytes_i then
              report "axip_sim " & G_NAME &
                     ": Test finished";
              stop;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        verf_cnt <= (others => '0');
        state    <= IDLE_ST;
      end if;
    end if;
  end process fsm_proc;

end architecture simulation;

