----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- QNICE streaming device for loading PRG files into the C64's RAM
--
-- done by sy2002 in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use ieee.numeric_std_unsigned.all;

library work;
   use work.globals.all;
   use work.qnice_csr_pkg.all;

entity prg_loader is
   port (
      qnice_clk_i       : in    std_logic;
      qnice_rst_i       : in    std_logic;
      qnice_addr_i      : in    std_logic_vector(27 downto 0);
      qnice_data_i      : in    std_logic_vector(15 downto 0);
      qnice_ce_i        : in    std_logic;
      qnice_we_i        : in    std_logic;
      qnice_data_o      : out   std_logic_vector(15 downto 0);
      qnice_wait_o      : out   std_logic;

      c64ram_we_o       : out   std_logic;
      c64ram_addr_o     : out   std_logic_vector(15 downto 0);
      c64ram_data_i     : in    std_logic_vector(7 downto 0);
      c64ram_data_o     : out   std_logic_vector(7 downto 0);

      core_reset_o      : out   std_logic; -- reset the core when the PRG loading starts
      core_triggerrun_o : out   std_logic  -- trigger program auto starts after loading finished
   );
end entity prg_loader;

architecture beh of prg_loader is

   -- Request and response
   signal   qnice_req_status : std_logic_vector( 3 downto 0);
   signal   qnice_req_length : std_logic_vector(22 downto 0);

   signal   qnice_csr_data : std_logic_vector(15 downto 0);
   signal   qnice_csr_wait : std_logic;
   signal   qnice_csr      : std_logic;

   -- PRG load address
   signal   prg_start : unsigned(15 downto 0);
   signal   prg_end   : unsigned(15 downto 0);

   -- Communication and reset state machine (see comment directly at the state machine below)
   constant C_COMM_DELAY  : natural                  := 50;
   constant C_RESET_DELAY : natural                  := 4 * CORE_CLK_SPEED;  -- 3 seconds

   type     state_type is (
      IDLE_ST,
      RESET_ST,
      RESET_POST_ST,
      WAIT_OK_ST,
      WRITE_END_ST,
      TRIGGER_RUN_ST
   );

   signal   state       : state_type                 := IDLE_ST;
   signal   delay       : natural range 0 to C_RESET_DELAY;
   signal   write_count : natural range 0 to 25;

   constant C_ERROR_STRINGS : string_vector(0 to 15) := (others => "OK                 \n");

begin

   -- Handle the generic framework CSR registers
   qnice_csr_inst : entity work.qnice_csr
      generic map (
         G_ERROR_STRINGS => C_ERROR_STRINGS
      )
      port map (
         qnice_clk_i          => qnice_clk_i,
         qnice_rst_i          => qnice_rst_i,
         qnice_addr_i         => qnice_addr_i,
         qnice_data_i         => qnice_data_i,
         qnice_ce_i           => qnice_ce_i,
         qnice_we_i           => qnice_we_i,
         qnice_data_o         => qnice_csr_data,
         qnice_wait_o         => qnice_csr_wait,
         qnice_csr_o          => qnice_csr,
         qnice_req_status_o   => qnice_req_status,
         qnice_req_length_o   => qnice_req_length,
         -- for now: hardcoded as we do not really parse anything
         qnice_resp_status_i  => C_CSR_RESP_READY,
         qnice_resp_error_i   => (others => '0'),
         qnice_resp_address_i => (others => '0')
      ); -- qnice_csr_inst



   -- Write to registers
   qnice_write_proc : process (qnice_clk_i)
   begin
      if falling_edge(qnice_clk_i) then
         if qnice_ce_i = '1' and qnice_we_i = '1' then
            -- extract low byte of program start
            if qnice_addr_i(27 downto 0) = X"000000" & "0000" then
               prg_start(7 downto 0) <= unsigned(qnice_data_i(7 downto 0));
            elsif qnice_addr_i(27 downto 0) = X"000000" & "0001" then
               prg_start(15 downto 8) <= unsigned(qnice_data_i(7 downto 0));
            end if;
         end if;

         -- Due to the falling_edge nature of QNICE, one QNICE cycle is not enough to ensure that the core
         -- which runs in another clock domain registers core_reset_o or core_triggerrun_o. Therefore we
         -- hold the signal C_COMM_DELAY QNICE cycles high.
         --
         -- While the C64 resets, it clears some status memory locations so that QNICE needs to wait before
         -- loading the PRG until the reset is done (C_RESET_DELAY), otherwise we have a race condition.
         case state is

            when IDLE_ST =>
               qnice_wait_o      <= '0';
               core_reset_o      <= '0';
               core_triggerrun_o <= '0';
               if qnice_req_status = C_CSR_REQ_LDNG then
                  delay <= C_COMM_DELAY;
                  state <= RESET_ST;
               end if;

            -- In this state, reset is asserted
            when RESET_ST =>
               qnice_wait_o <= '1';
               core_reset_o <= '1';
               if delay = 0 then
                  state <= RESET_POST_ST;
                  delay <= C_RESET_DELAY;
               else
                  delay <= delay - 1;
               end if;

            -- In this state, reset is cleared, and core is booting
            when RESET_POST_ST =>
               core_reset_o <= '0';
               if delay = 0 then
                  state <= WAIT_OK_ST;
               else
                  delay <= delay - 1;
               end if;

            -- In this state, core is ready
            when WAIT_OK_ST =>
               qnice_wait_o <= '0';
               if qnice_req_status = C_CSR_REQ_OK then
                  write_count <= 1;
                  state       <= WRITE_END_ST;
               end if;

            -- In this state, core is ready
            when WRITE_END_ST =>
               write_count <= write_count + 1;
               if write_count = 25 then
                  delay <= C_COMM_DELAY;
                  state <= TRIGGER_RUN_ST;
               end if;

            -- In this state, program is being started
            when TRIGGER_RUN_ST =>
               core_triggerrun_o <= '1';
               if delay = 0 then
                  state <= IDLE_ST;
               else
                  delay <= delay - 1;
               end if;

            when others =>
               null;

         end case;

         if qnice_rst_i = '1' then
            prg_start         <= (others => '0');
            core_reset_o      <= '0';
            core_triggerrun_o <= '0';
            qnice_wait_o      <= '0';
            state             <= IDLE_ST;
         end if;
      end if;
   end process qnice_write_proc;

   -- Handle QNICE read
   qnice_read_proc : process (all)
   begin
      qnice_data_o <= x"0000"; -- By default read back zeros

      if qnice_ce_i = '1' then

         case qnice_csr is

            when '0' =>
               qnice_data_o <= x"00" & c64ram_data_i;

            when '1' =>
               qnice_data_o <= qnice_csr_data;

         end case;

      end if;
   end process qnice_read_proc;

   prg_end <= prg_start + unsigned(qnice_req_length(15 downto 0)) - 2;

   -- Handle the C64 RAM signals
   core_ram_proc : process (all)
   begin
      c64ram_addr_o <= std_logic_vector(prg_start + unsigned(qnice_addr_i(15 downto 0) - 2));
      c64ram_data_o <= qnice_data_i(7 downto 0);
      c64ram_we_o   <= '0';

      -- Handle write to C64 RAM
      if qnice_ce_i = '1' and unsigned(qnice_addr_i(27 downto 0)) > 1 and qnice_csr = '0' then
         c64ram_we_o <= qnice_we_i;
      end if;

      -- Initialize BASIC pointers to simulate the BASIC LOAD command
      case write_count is

         when 1 =>
            c64ram_addr_o <= X"002B";                                                             -- TXT
            c64ram_data_o <= X"01";
            c64ram_we_o   <= '1';

         when 3 =>
            c64ram_addr_o <= X"002C";
            c64ram_data_o <= X"08";
            c64ram_we_o   <= '1';

         when 5 =>
            c64ram_addr_o <= X"00AC";                                                             -- SAVE START
            c64ram_data_o <= X"00";
            c64ram_we_o   <= '1';

         when 7 =>
            c64ram_addr_o <= X"00AD";
            c64ram_data_o <= X"00";
            c64ram_we_o   <= '1';

         when 9 =>
            c64ram_addr_o <= X"002D";                                                             -- VAR
            c64ram_data_o <= std_logic_vector(prg_end(7 downto 0));
            c64ram_we_o   <= '1';

         when 11 =>
            c64ram_addr_o <= X"002E";
            c64ram_data_o <= std_logic_vector(prg_end(15 downto 8));
            c64ram_we_o   <= '1';

         when 13 =>
            c64ram_addr_o <= X"002F";                                                             -- ARY
            c64ram_data_o <= std_logic_vector(prg_end(7 downto 0));
            c64ram_we_o   <= '1';

         when 15 =>
            c64ram_addr_o <= X"0030";
            c64ram_data_o <= std_logic_vector(prg_end(15 downto 8));
            c64ram_we_o   <= '1';

         when 17 =>
            c64ram_addr_o <= X"0031";                                                             -- STR
            c64ram_data_o <= std_logic_vector(prg_end(7 downto 0));
            c64ram_we_o   <= '1';

         when 19 =>
            c64ram_addr_o <= X"0032";
            c64ram_data_o <= std_logic_vector(prg_end(15 downto 8));
            c64ram_we_o   <= '1';

         when 21 =>
            c64ram_addr_o <= X"00AE";                                                             -- LOAD END
            c64ram_data_o <= std_logic_vector(prg_end(7 downto 0));
            c64ram_we_o   <= '1';

         when 23 =>
            c64ram_addr_o <= X"00AF";
            c64ram_data_o <= std_logic_vector(prg_end(15 downto 8));
            c64ram_we_o   <= '1';

         when 25 =>
            c64ram_addr_o <= X"00BA";
            c64ram_data_o <= X"08";
            c64ram_we_o   <= '1';

         when others =>
            null;

      end case;

      null;
   end process core_ram_proc;

end architecture beh;

