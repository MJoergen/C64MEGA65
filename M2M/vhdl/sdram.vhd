-- This file contains the complete SDR SDRAM controller.
--
-- It is designed to communicate with an IS42S16320F-6BL.
-- However, the SDR SDRAM protocol is standardized, and this
-- file can easily be adapted to communicate with other SDR SDRAMs.
--
-- This module requires one clock:
-- clk_i          : 166 MHz : This is the main clock used for the Avalon MM
--                            interface as well as controlling the SDRAM
--                            device.
--
-- Addressing scheme:
-- Bank address   : BA0 and BA1 (i.e. 4 banks)
-- Row Address    : A0 - A12 (i.e. 8k)
-- Column Address : A0 - A9 (i.e. 1k)
-- Total : 25 address bits and 16 data bits = 64 MB.
--
-- Read takes 12 clock cycles.
-- Write takes 8 clock cycles.
-- Single cycle access can be achieved at 166/12 = 13.8 MHz.
-- Refresh takes 12 clock cycles, i.e. about 1% of bandwidth.
-- This version does not support burst mode.
--
-- Link to datasheet for "IS42S16320F-6BL":
-- https://www.issi.com/WW/pdf/42-45R-S_86400F-16320F.pdf
--
-- Created by Michael Jørgensen in 2024 (mjoergen.github.io/SDRAM).

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

-- needed for ODDR

library unisim;
   use unisim.vcomponents.all;

entity sdram is
   port (
      clk_i               : in    std_logic;                     -- Main clock = 166 MHz
      rst_i               : in    std_logic;                     -- Synchronous reset

      -- Avalon Memory Map
      avm_waitrequest_o   : out   std_logic;
      avm_write_i         : in    std_logic;
      avm_read_i          : in    std_logic;
      avm_address_i       : in    std_logic_vector(31 downto 0);
      avm_writedata_i     : in    std_logic_vector(15 downto 0);
      avm_byteenable_i    : in    std_logic_vector( 1 downto 0);
      avm_burstcount_i    : in    std_logic_vector( 7 downto 0);
      avm_readdata_o      : out   std_logic_vector(15 downto 0);
      avm_readdatavalid_o : out   std_logic;

      -- SDRAM device interface
      sdram_a_o           : out   std_logic_vector(12 downto 0);
      sdram_ba_o          : out   std_logic_vector(1 downto 0);
      sdram_cas_n_o       : out   std_logic;
      sdram_cke_o         : out   std_logic;
      sdram_clk_o         : out   std_logic;
      sdram_cs_n_o        : out   std_logic;
      sdram_dq_in_i       : in    std_logic_vector(15 downto 0);
      sdram_dqmh_o        : out   std_logic;
      sdram_dqml_o        : out   std_logic;
      sdram_dq_oe_n_o     : out   std_logic_vector(15 downto 0); -- Output enable (inverted) for DQ
      sdram_dq_out_o      : out   std_logic_vector(15 downto 0);
      sdram_ras_n_o       : out   std_logic;
      sdram_we_n_o        : out   std_logic
   );
end entity sdram;

architecture synthesis of sdram is

   constant C_CLOCK_SPEED_MHZ : natural                     := 166;

   -- The below constants are taken from the datasheet.

   -- Power-on time set to 102 us (rather than 100 us), to allow some extra margin, and
   -- account for possible inaccuracies in clock frequency.
   constant C_TIME_INIT_POWER_ON : natural                  := 102 * C_CLOCK_SPEED_MHZ;

   -- CAS# latency
   constant C_TIME_CAC : natural                            := 3;

   -- Active Command to Read/Write Command Delay Time
   constant C_TIME_RCD : natural                            := 3;

   -- RAS# latency (t_RCD + t_CAC)
   -- Not used.
   constant C_TIME_RAC : natural                            := 6;

   -- Command Period (REF to REF / ACT to ACT)
   constant C_TIME_RC : natural                             := 10;

   -- Command Period (ACT to PRE)
   -- Not used.
   constant C_TIME_RAS : natural                            := 7;

   -- Command Period (PRE to ACT)
   constant C_TIME_RP : natural                             := 3;

   -- Command Period (ACT[0] to ACT[1])
   -- Not used.
   constant C_TIME_RRD : natural                            := 2;

   -- Column Command Delay Time (READ, WRITE)
   -- Not used.
   constant C_TIME_CCD : natural                            := 1;

   -- Input Data to Precharge Command Delay Time
   -- Not used.
   constant C_TIME_DPL : natural                            := 2;

   -- Input Data to Active/Refresh Command Delay Time
   -- Not used.
   constant C_TIME_DAL : natural                            := 5;

   -- Burst Stop Command to Output in High-Z Delay Time (Read)
   -- Not used.
   constant C_TIME_RBD : natural                            := 3;

   -- Burst Stop Command to Input in Invalid Delay Time (Write)
   -- Not used.
   constant C_TIME_WBD : natural                            := 0;

   -- Precharge Command to Output in High-Z Delay Time (Read)
   -- Not used.
   constant C_TIME_RQL : natural                            := 3;

   -- Precharge Command to Input in Invalid Delay Time (Write)
   -- Not used.
   constant C_TIME_WDL : natural                            := 0;

   -- Last Output to Auto-Precharge Start Time (Read)
   -- Not used.
   constant C_TIME_PQL : integer                            := -2;

   -- DQM to Output Delay Time (Read)
   constant C_TIME_QMD : natural                            := 2;

   -- DQM to Input Delay Time (Write
   constant C_TIME_DMD : natural                            := 0;

   -- Mode Register Set to Command Delay Time
   constant C_TIME_MRD : natural                            := 2;

   -- Interval between refresh commands (in clock cycles):
   -- We must send 8192 refresh commands in the span of 64 ms.
   -- Subtract small value to compensate for time spent in previous command
   constant C_TIME_REFRESH : natural                        := C_CLOCK_SPEED_MHZ * 1000 * 64 / 8192 - 12;

   -- Device commands:
   -- bit 2 : RAS#
   -- bit 1 : CAS#
   -- bit 0 : WE#
   constant C_NO_OPERATION   : std_logic_vector(2 downto 0) := "111";
   constant C_BURST_STOP     : std_logic_vector(2 downto 0) := "110";
   constant C_READ           : std_logic_vector(2 downto 0) := "101";
   constant C_WRITE          : std_logic_vector(2 downto 0) := "100";
   constant C_BANK_ACTIVATE  : std_logic_vector(2 downto 0) := "011";
   constant C_PRECHARGE_BANK : std_logic_vector(2 downto 0) := "010"; -- Same as de-activate
   constant C_AUTO_REFRESH   : std_logic_vector(2 downto 0) := "001";
   constant C_MODE_SET       : std_logic_vector(2 downto 0) := "000";

   type     state_type is (
      INIT_POWER_ON_ST,
      INIT_PRECHARGE_ST,
      INIT_REFRESH_1_ST,
      INIT_REFRESH_2_ST,
      INIT_SET_MODE_ST,
      IDLE_ST,
      ACTIVE_ST,
      WRITE_ST,
      READ_ST,
      PRECHARGE_ST,
      REFRESH_ST
   );
   signal   state         : state_type;
   signal   timer_cmd     : natural range 0 to C_TIME_INIT_POWER_ON - 1;
   signal   timer_refresh : natural range 0 to C_TIME_REFRESH - 1;

   signal   avm_address_debug : std_logic_vector(24 downto 2);

   signal   avm_write      : std_logic;
   signal   avm_read       : std_logic;
   signal   avm_address    : std_logic_vector(31 downto 0);
   signal   avm_writedata  : std_logic_vector(15 downto 0);
   signal   avm_byteenable : std_logic_vector( 1 downto 0);
   signal   avm_burstcount : std_logic_vector( 7 downto 0);

   signal   afs_s_ready : std_logic;
   signal   afs_s_valid : std_logic;
   signal   afs_s_data  : std_logic_vector(17 downto 0);
   signal   afs_m_ready : std_logic;
   signal   afs_m_valid : std_logic;
   signal   afs_m_data  : std_logic_vector(17 downto 0);

   -- SDRAM device output interface
   signal   sdram_a       : std_logic_vector(12 downto 0)   := (others => '0');
   signal   sdram_ba      : std_logic_vector(1 downto 0)    := (others => '0');
   signal   sdram_cas_n   : std_logic                       := '1';
   signal   sdram_cke     : std_logic                       := '1';
   signal   sdram_cs_n    : std_logic                       := '1';
   signal   sdram_dqmh    : std_logic                       := '1';
   signal   sdram_dqml    : std_logic                       := '1';
   signal   sdram_dq_oe_n : std_logic_vector(15 downto 0)   := (others => '1');
   signal   sdram_dq_out  : std_logic_vector(15 downto 0)   := (others => '1');
   signal   sdram_ras_n   : std_logic                       := '1';
   signal   sdram_we_n    : std_logic                       := '1';

   -- SDRAM device input interface
   signal   sdram_dq_in : std_logic_vector(15 downto 0);

   -- Make sure all sixteen flip-flops are preserved, even though
   -- they have identical inputs. This is necessary for the
   -- set_property IOB TRUE constraint to have effect.
   attribute dont_touch : string;
   attribute dont_touch of sdram_dq_oe_n : signal is "true";

   attribute IOB : string;
   attribute IOB of sdram_a_o       : signal is "TRUE";
   attribute IOB of sdram_ba_o      : signal is "TRUE";
   attribute IOB of sdram_cas_n_o   : signal is "TRUE";
   attribute IOB of sdram_cs_n_o    : signal is "TRUE";
   attribute IOB of sdram_dqmh_o    : signal is "TRUE";
   attribute IOB of sdram_dqml_o    : signal is "TRUE";
   attribute IOB of sdram_dq_oe_n_o : signal is "TRUE";
   attribute IOB of sdram_dq_out_o  : signal is "TRUE";
   attribute IOB of sdram_ras_n_o   : signal is "TRUE";
   attribute IOB of sdram_we_n_o    : signal is "TRUE";
   attribute IOB of sdram_dq_in     : signal is "TRUE";

   constant C_OUTPUT_REG : boolean := false;

--   attribute mark_debug : string;
--   attribute mark_debug of sdram_a       : signal is "true";
--   attribute mark_debug of sdram_ba      : signal is "true";
--   attribute mark_debug of sdram_cas_n   : signal is "true";
--   attribute mark_debug of sdram_cke     : signal is "true";
--   attribute mark_debug of sdram_cs_n    : signal is "true";
--   attribute mark_debug of sdram_dq_in   : signal is "true";
--   attribute mark_debug of sdram_dqmh    : signal is "true";
--   attribute mark_debug of sdram_dqml    : signal is "true";
--   attribute mark_debug of sdram_dq_oe_n : signal is "true";
--   attribute mark_debug of sdram_dq_out  : signal is "true";
--   attribute mark_debug of sdram_ras_n   : signal is "true";
--   attribute mark_debug of sdram_we_n    : signal is "true";

--   attribute mark_debug of avm_address_debug   : signal is "true";
--   attribute mark_debug of avm_byteenable_i    : signal is "true";
--   attribute mark_debug of avm_readdata_o      : signal is "true";
--   attribute mark_debug of avm_readdatavalid_o : signal is "true";
--   attribute mark_debug of avm_read_i          : signal is "true";
--   attribute mark_debug of avm_waitrequest_o   : signal is "true";
--   attribute mark_debug of avm_writedata_i     : signal is "true";
--   attribute mark_debug of avm_write_i         : signal is "true";

begin

   avm_address_debug <= avm_address_i(24 downto 2);

   avm_waitrequest_o <= '0' when state = IDLE_ST and timer_refresh /= 0 else
                        '0' when avm_write = '1' and avm_burstcount > 1 else
                        '1';

   output_reg_gen : if C_OUTPUT_REG generate
      process (clk_i)
      begin
         if rising_edge(clk_i) then
            sdram_a_o         <= sdram_a;
            sdram_ba_o        <= sdram_ba;
            sdram_cas_n_o     <= sdram_cas_n;
            sdram_cke_o       <= sdram_cke;
            sdram_cs_n_o      <= sdram_cs_n;
            sdram_dqmh_o      <= sdram_dqmh;
            sdram_dqml_o      <= sdram_dqml;
            sdram_dq_oe_n_o   <= sdram_dq_oe_n;
            sdram_dq_out_o    <= sdram_dq_out;
            sdram_ras_n_o     <= sdram_ras_n;
            sdram_we_n_o      <= sdram_we_n;
         end if;
      end process;
   else generate
      sdram_a_o         <= sdram_a;
      sdram_ba_o        <= sdram_ba;
      sdram_cas_n_o     <= sdram_cas_n;
      sdram_cke_o       <= sdram_cke;
      sdram_cs_n_o      <= sdram_cs_n;
      sdram_dqmh_o      <= sdram_dqmh;
      sdram_dqml_o      <= sdram_dqml;
      sdram_dq_oe_n_o   <= sdram_dq_oe_n;
      sdram_dq_out_o    <= sdram_dq_out;
      sdram_ras_n_o     <= sdram_ras_n;
      sdram_we_n_o      <= sdram_we_n;
   end generate;

   axi_fifo_small_inst : entity work.axi_fifo_small
      generic map (
         G_RAM_WIDTH => 16 + 2,
         G_RAM_DEPTH => C_TIME_RCD + 2
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst_i,
         s_ready_o => afs_s_ready,
         s_valid_i => afs_s_valid,
         s_data_i  => afs_s_data,
         m_ready_i => afs_m_ready,
         m_valid_o => afs_m_valid,
         m_data_o  => afs_m_data
      ); -- axi_fifo_small_inst

   afs_s_valid                     <= avm_write_i and not avm_waitrequest_o;
   afs_s_data                      <= avm_byteenable_i & avm_writedata_i;
   afs_m_ready                     <= '1' when state = ACTIVE_ST and timer_cmd = 0 and avm_write = '1' else
                                      '1' when state = WRITE_ST else
                                      '0';
   (avm_byteenable, avm_writedata) <= afs_m_data;

   avm_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         avm_readdatavalid_o <= '0';

         -- Data lines are high-Z by default
         sdram_dq_oe_n       <= (others => '1');
         sdram_dqmh          <= '1';
         sdram_dqml          <= '1';

         if timer_cmd > 0 then
            timer_cmd <= timer_cmd - 1;
         end if;

         if timer_refresh > 0 then
            timer_refresh <= timer_refresh - 1;
         end if;

         if avm_write = '1' and avm_burstcount > 1 then
            avm_burstcount <= avm_burstcount - 1;
         end if;

         -- Default command is NOP
         sdram_cs_n  <= '1';
         sdram_ras_n <= C_NO_OPERATION(2);
         sdram_cas_n <= C_NO_OPERATION(1);
         sdram_we_n  <= C_NO_OPERATION(0);

         case state is

            when INIT_POWER_ON_ST =>
               -- A 100µs delay is required prior to issuing any command other than a
               -- COMMAND INHIBIT or a NOP.

               if timer_cmd = 0 then
                  sdram_cs_n  <= '0';
                  sdram_ras_n <= C_PRECHARGE_BANK(2);
                  sdram_cas_n <= C_PRECHARGE_BANK(1);
                  sdram_we_n  <= C_PRECHARGE_BANK(0);
                  -- precharge all banks
                  sdram_a(10) <= '1';

                  timer_cmd   <= C_TIME_RP - 1;
                  state       <= INIT_PRECHARGE_ST;
               end if;

            when INIT_PRECHARGE_ST =>
               if timer_cmd = 0 then
                  sdram_cs_n  <= '0';
                  sdram_ras_n <= C_AUTO_REFRESH(2);
                  sdram_cas_n <= C_AUTO_REFRESH(1);
                  sdram_we_n  <= C_AUTO_REFRESH(0);
                  timer_cmd   <= C_TIME_RC - 1;
                  state       <= INIT_REFRESH_1_ST;
               end if;

            when INIT_REFRESH_1_ST =>
               if timer_cmd = 0 then
                  sdram_cs_n    <= '0';
                  sdram_ras_n   <= C_AUTO_REFRESH(2);
                  sdram_cas_n   <= C_AUTO_REFRESH(1);
                  sdram_we_n    <= C_AUTO_REFRESH(0);
                  timer_refresh <= C_TIME_REFRESH - 1;
                  timer_cmd     <= C_TIME_RC - 1;
                  state         <= INIT_REFRESH_2_ST;
               end if;

            when INIT_REFRESH_2_ST =>
               if timer_cmd = 0 then
                  sdram_cs_n          <= '0';
                  sdram_a             <= (others => '0');                               -- Clear all reserved bits
                  sdram_a(9)          <= '0';                                           -- Write burst mode = Read burst mode
                  sdram_a(8 downto 7) <= "00";                                          -- standard operating mode
                  sdram_a(6 downto 4) <= "011";                                         -- CAS latency = 3 (i.e. 166 MHz)
                  sdram_a(3)          <= '0';                                           -- burst type = sequential
                  sdram_a(2 downto 0) <= "111";                                         -- burst length = full page
                  sdram_ras_n         <= C_MODE_SET(2);
                  sdram_cas_n         <= C_MODE_SET(1);
                  sdram_we_n          <= C_MODE_SET(0);
                  timer_cmd           <= C_TIME_MRD - 1;
                  state               <= INIT_SET_MODE_ST;
               end if;

            when INIT_SET_MODE_ST =>
               if timer_cmd = 0 then
                  state <= IDLE_ST;
               end if;

            when IDLE_ST =>
               if timer_refresh = 0 then
                  timer_refresh <= C_TIME_REFRESH - 1;
                  timer_cmd     <= C_TIME_RC;
                  sdram_cs_n    <= '0';
                  sdram_ras_n   <= C_AUTO_REFRESH(2);
                  sdram_cas_n   <= C_AUTO_REFRESH(1);
                  sdram_we_n    <= C_AUTO_REFRESH(0);
                  state         <= REFRESH_ST;
               elsif avm_read_i = '1' or avm_write_i = '1' then
                  assert avm_read_i = '0' or avm_write_i = '0'
                     report "Simultaneous READ and WRITE not allowed";
                  avm_read       <= avm_read_i;
                  avm_write      <= avm_write_i;
                  avm_address    <= avm_address_i;
                  avm_burstcount <= avm_burstcount_i;
                  sdram_cs_n     <= '0';
                  sdram_ras_n    <= C_BANK_ACTIVATE(2);
                  sdram_cas_n    <= C_BANK_ACTIVATE(1);
                  sdram_we_n     <= C_BANK_ACTIVATE(0);
                  sdram_a        <= avm_address_i(22 downto 10);                        -- row address
                  sdram_ba       <= avm_address_i(24 downto 23);                        -- bank address
                  timer_cmd      <= C_TIME_RCD - 1;
                  state          <= ACTIVE_ST;
               end if;

            when ACTIVE_ST =>
               if timer_cmd = 0 then
                  if avm_read = '1' then
                     sdram_cs_n          <= '0';
                     sdram_ras_n         <= C_READ(2);
                     sdram_cas_n         <= C_READ(1);
                     sdram_we_n          <= C_READ(0);
                     sdram_a             <= (others => '0');                            -- Clear all reserved bits
                     sdram_a(9 downto 0) <= avm_address(9 downto 0);                    -- column address
                     sdram_a(10)         <= '0';                                        -- no automatic precharge
                     sdram_ba            <= avm_address(24 downto 23);                  -- bank address
                     if C_OUTPUT_REG then
                        timer_cmd           <= C_TIME_CAC + to_integer(avm_burstcount) + 1;
                     else
                        timer_cmd           <= C_TIME_CAC + to_integer(avm_burstcount);
                     end if;
                     state               <= READ_ST;
                  end if;
                  if avm_write = '1' then
                     sdram_cs_n          <= '0';
                     sdram_ras_n         <= C_WRITE(2);
                     sdram_cas_n         <= C_WRITE(1);
                     sdram_we_n          <= C_WRITE(0);
                     sdram_a             <= (others => '0');                            -- Clear all reserved bits
                     sdram_a(9 downto 0) <= avm_address(9 downto 0);                    -- column address
                     sdram_a(10)         <= '0';                                        -- no automatic precharge
                     sdram_ba            <= avm_address(24 downto 23);                  -- bank address
                     if C_TIME_DMD = 0 then
                        sdram_dqmh    <= not avm_byteenable(1);
                        sdram_dqml    <= not avm_byteenable(0);
                        sdram_dq_out  <= avm_writedata;
                        sdram_dq_oe_n <= (others => '0');
                     end if;
                     state <= WRITE_ST;
                  end if;
               end if;

            when WRITE_ST =>
               if afs_m_valid then
                  sdram_dqmh    <= not avm_byteenable(1);
                  sdram_dqml    <= not avm_byteenable(0);
                  sdram_dq_out  <= avm_writedata;
                  sdram_dq_oe_n <= (others => '0');
               else
                  avm_write   <= '0';
                  sdram_cs_n  <= '0';
                  sdram_ras_n <= C_PRECHARGE_BANK(2);
                  sdram_cas_n <= C_PRECHARGE_BANK(1);
                  sdram_we_n  <= C_PRECHARGE_BANK(0);
                  sdram_a(10) <= '1';                                                   -- precharge all banks
                  timer_cmd   <= C_TIME_RP - 1;
                  state       <= PRECHARGE_ST;
               end if;

            when READ_ST =>
               if C_OUTPUT_REG then
                  if timer_cmd >= C_TIME_QMD + 3 and
                     timer_cmd <= C_TIME_QMD + 2 + avm_burstcount then
                     sdram_dqmh <= '0';
                     sdram_dqml <= '0';
                  end if;
               else
                  if timer_cmd >= C_TIME_QMD + 2 and
                     timer_cmd <= C_TIME_QMD + 1 + avm_burstcount then
                     sdram_dqmh <= '0';
                     sdram_dqml <= '0';
                  end if;
               end if;
               if timer_cmd + 1 <= avm_burstcount then
                  avm_readdata_o      <= sdram_dq_in;
                  avm_readdatavalid_o <= '1';
               end if;
               if timer_cmd = C_TIME_CAC + 1 then
                  sdram_cs_n  <= '0';
                  sdram_ras_n <= C_BURST_STOP(2);
                  sdram_cas_n <= C_BURST_STOP(1);
                  sdram_we_n  <= C_BURST_STOP(0);
               end if;
               if timer_cmd = 0 then
                  sdram_cs_n  <= '0';
                  sdram_ras_n <= C_PRECHARGE_BANK(2);
                  sdram_cas_n <= C_PRECHARGE_BANK(1);
                  sdram_we_n  <= C_PRECHARGE_BANK(0);
                  sdram_a(10) <= '1';                                                   -- precharge all banks
                  timer_cmd   <= C_TIME_RP - 1;
                  state       <= PRECHARGE_ST;
               end if;

            when PRECHARGE_ST =>
               if timer_cmd = 0 then
                  state <= IDLE_ST;
               end if;

            when REFRESH_ST =>
               if timer_cmd = 0 then
                  state <= IDLE_ST;
               end if;

            when others =>
               state <= IDLE_ST;

         end case;

         if rst_i = '1' then
            avm_readdata_o      <= (others => '0');
            avm_readdatavalid_o <= '0';
            -- Keep clock-enable high all the time
            sdram_cke           <= '1';
            -- Disable SDRAM chip-select by default
            sdram_cs_n          <= '1';
            -- By default, send NOP command
            sdram_ras_n         <= C_NO_OPERATION(2);
            sdram_cas_n         <= C_NO_OPERATION(1);
            sdram_we_n          <= C_NO_OPERATION(0);
            sdram_a             <= (others => '0');
            sdram_ba            <= (others => '0');
            sdram_dqmh          <= '1';
            sdram_dqml          <= '1';
            sdram_dq_oe_n       <= (others => '1');
            sdram_dq_out        <= (others => '1');
            timer_cmd           <= C_TIME_INIT_POWER_ON - 1;
            state               <= INIT_POWER_ON_ST;
         end if;
      end if;
   end process avm_proc;

   -- Sample data from SDRAM directly into register
   read_proc : process (clk_i)
   begin
      if rising_edge(clk_i) then
         sdram_dq_in <= sdram_dq_in_i;
      end if;
   end process read_proc;


   --------------------------------------------------------------------------
   -- Generate SDRAM clock equal to inverted clk_i.
   -- This forces the output clock register to be placed at the I/O pad.
   --------------------------------------------------------------------------

   oddr_inst : component oddr
      generic map (
         DDR_CLK_EDGE => "SAME_EDGE"
      )
      port map (
         d1 => '1',
         d2 => '0',
         ce => '1',
         q  => sdram_clk_o,
         c  => not clk_i
      ); -- oddr_inst

end architecture synthesis;

