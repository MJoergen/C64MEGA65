-- ---------------------------------------------------------------------------------------
-- Description: Generates a stream of random packets and verifies the response.
--
-- SPDX-License-Identifier: MIT
-- ---------------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity axip_master_sim is
  generic (
    G_SEED       : std_logic_vector(63 downto 0) := x"DEADBEAFC007BABE";
    G_NAME       : string                        := "";
    G_DEBUG      : boolean;
    G_CNT_SIZE   : natural;
    G_DATA_BYTES : natural;
    G_MIN_LENGTH : natural                       := 0;
    G_MAX_LENGTH : natural                       := 255
  );
  port (
    clk_i     : in    std_logic;
    rst_i     : in    std_logic;

    -- AXI packet output
    m_ready_i : in    std_logic;
    m_valid_o : out   std_logic;
    m_data_o  : out   std_logic_vector(G_DATA_BYTES * 8 - 1 downto 0);
    m_last_o  : out   std_logic;
    m_bytes_o : out   natural range 0 to G_DATA_BYTES
  );
end entity axip_master_sim;

architecture simulation of axip_master_sim is

  -- State machine for controlling generation and transmission of AXI packets.
  type    state_type is (IDLE_ST, DATA_ST);
  signal  state : state_type := IDLE_ST;

  signal  stim_cnt   : std_logic_vector(G_CNT_SIZE - 1 downto 0);
  signal  bytes_left : natural range 0 to 255;

  -- Randomness
  signal  rand : std_logic_vector(63 downto 0);

  -- This controls the total length of the packet.

  subtype R_RAND_LENGTH is natural range 20 downto 5;

begin

  assert G_MIN_LENGTH <= G_MAX_LENGTH;
  assert G_MAX_LENGTH <= 255;

  ----------------------------------------------------------
  -- Generate randomness
  ----------------------------------------------------------

  random_inst : entity work.random
    generic map (
      G_SEED => G_SEED
    )
    port map (
      clk_i    => clk_i,
      rst_i    => rst_i,
      update_i => '1',
      output_o => rand
    ); -- random_inst : entity work.random


  ----------------------------------------------------------
  -- Generate AXI packet output
  ----------------------------------------------------------

  fsm_proc : process (clk_i)
    variable length_v : natural range 0 to 255;
    variable first_v  : boolean := true;
  begin
    if rising_edge(clk_i) then
      if rst_i = '0' and first_v then
        report "axip_master_sim " & G_NAME &
               ": Test started";
        first_v := false;
      end if;

      if m_ready_i = '1' then
        m_valid_o <= '0';
      end if;

      case state is

        when IDLE_ST =>
          if (m_ready_i = '1' or m_valid_o = '0') and rst_i = '0' then
            -- First beat of the packet
            length_v := (to_integer(rand(R_RAND_LENGTH)) mod (G_MAX_LENGTH - G_MIN_LENGTH + 1)) + G_MIN_LENGTH;

            if rst_i = '0' and G_DEBUG then
              report "axip_master_sim " & G_NAME &
                     ": STIM length " & to_string(length_v) &
                     ", first byte " & to_hstring(stim_cnt(7 downto 0));
            end if;

            m_data_o(G_DATA_BYTES * 8 - 1 downto G_DATA_BYTES * 8 - 8) <= to_stdlogicvector(length_v, 8);

            for i in 1 to G_DATA_BYTES - 1 loop
              if i < length_v then
                m_data_o((G_DATA_BYTES - 1 - i) * 8 + 7 downto (G_DATA_BYTES - 1 - i) * 8) <= stim_cnt(7 downto 0) + i - 1;
              end if;
            end loop;

            m_valid_o <= '1';

            if length_v <= G_DATA_BYTES - 1 then
              m_bytes_o <= length_v + 1;
              m_last_o  <= '1';
              stim_cnt  <= stim_cnt + length_v;
            else
              m_last_o   <= '0';
              bytes_left <= length_v - (G_DATA_BYTES - 1);
              stim_cnt   <= stim_cnt + (G_DATA_BYTES - 1);
              state      <= DATA_ST;
            end if;
          end if;

        when DATA_ST =>
          if m_ready_i = '1' or m_valid_o = '0' then

            for i in 0 to G_DATA_BYTES - 1 loop
              if i < bytes_left then
                m_data_o((G_DATA_BYTES - 1 - i) * 8 + 7 downto (G_DATA_BYTES - 1 - i) * 8) <= stim_cnt(7 downto 0) + i;
              end if;
            end loop;

            m_valid_o <= '1';

            if bytes_left <= G_DATA_BYTES then
              m_bytes_o <= bytes_left;
              m_last_o  <= '1';
              stim_cnt  <= stim_cnt + bytes_left;
              state     <= IDLE_ST;
            else
              m_last_o   <= '0';
              bytes_left <= bytes_left - G_DATA_BYTES;
              stim_cnt   <= stim_cnt + G_DATA_BYTES;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        stim_cnt  <= (others => '0');
        m_valid_o <= '0';
        state     <= IDLE_ST;
      end if;
    end if;
  end process fsm_proc;

end architecture simulation;

