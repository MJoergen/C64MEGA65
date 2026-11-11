----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Bench for unloading ("ejecting") a simulated cartridge (GitHub issue #153), see README.md.
--
-- Device under test: the real CORE/vhdl/sw_cartridge_wrapper.vhd (QNICE CSR, clock domain
-- crossings, crt_loader with parser and bank cacher) plus the real CORE/vhdl/cartridge.vhd, wired
-- like in main.vhd. A HyperRAM model with random wait states serves the .crt images. The bench
-- drives the QNICE bus like the Shell does (CSR status, file size, parse status) and the C64 side
-- like main.vhd does (soft reset into cart_loading_i and main_cart_soft_reset_i, CPU writes and
-- reads in $DExx/$DFxx). Three different clocks exercise the clock domain crossings.
--
-- Prints one line per check and ends with "RESULT ERRORS=<n>".
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;

entity tb_crt_eject is
   generic (
      G_SEED : natural := 44257   -- seed of the random HyperRAM wait states
   );
end entity tb_crt_eject;

architecture simulation of tb_crt_eject is

   -- HyperRAM word address of the SIMCRT pool, as in mega65.vhd: C_HMAP_CRT(9 downto 0) & X"000"
   constant C_BASE      : std_logic_vector(21 downto 0) := "10" & X"00000";
   constant C_MEM_WORDS : natural := 65536;

   -- QNICE CSR registers of the device (4k window 0xFFFF), see qnice_csr.vhd
   constant C_CSR_STATUS  : natural := 16#FFFF000#;
   constant C_CSR_FS_LO   : natural := 16#FFFF001#;
   constant C_CSR_FS_HI   : natural := 16#FFFF002#;
   constant C_CSR_PARSEST : natural := 16#FFFF010#;

   -- CSR status written by QNICE (CRTROM_CSR_ST_* in sysdef.asm) and parse status read back
   constant C_ST_IDLE : natural := 0;
   constant C_ST_LDNG : natural := 1;
   constant C_ST_ERR  : natural := 2;
   constant C_ST_OK   : natural := 3;
   constant C_PT_IDLE : natural := 0;
   constant C_PT_OK   : natural := 2;
   constant C_PT_ERR  : natural := 3;

   type mem_t is array (0 to C_MEM_WORDS - 1) of std_logic_vector(15 downto 0);
   type byte_vector is array (natural range <>) of std_logic_vector(7 downto 0);

   -- clocks: QNICE 50 MHz, HyperRAM 100 MHz, C64 core about 31.5 MHz
   signal qnice_clk : std_logic := '0';
   signal hr_clk    : std_logic := '0';
   signal main_clk  : std_logic := '0';
   signal running   : boolean   := true;

   signal qnice_rst : std_logic := '1';
   signal hr_rst    : std_logic := '1';
   signal main_rst  : std_logic := '1';   -- M2M reset (long reset button): hard reset

   -- QNICE bus
   signal qnice_addr   : std_logic_vector(27 downto 0) := (others => '0');
   signal qnice_wdata  : std_logic_vector(15 downto 0) := (others => '0');
   signal qnice_ce     : std_logic := '0';
   signal qnice_we     : std_logic := '0';
   signal qnice_rdata  : std_logic_vector(15 downto 0);
   signal qnice_wait   : std_logic;

   -- main clock domain
   signal main_reset_core : std_logic;
   signal main_loading    : std_logic;
   signal main_id         : std_logic_vector(15 downto 0);
   signal main_exrom      : std_logic_vector( 7 downto 0);
   signal main_game       : std_logic_vector( 7 downto 0);
   signal main_size       : std_logic_vector(22 downto 0);
   signal main_bank_wait  : std_logic;
   signal soft_rst        : std_logic := '0';   -- main.vhd cart_soft_reset (OSM soft reset)

   -- C64 side of cartridge.vhd
   signal cpu_addr     : std_logic_vector(15 downto 0) := (others => '0');
   signal cpu_wdata    : std_logic_vector( 7 downto 0) := (others => '0');
   signal cpu_we       : std_logic := '0';
   signal cpu_ioe      : std_logic := '0';
   signal cpu_iof      : std_logic := '0';
   signal crt_bank_lo  : std_logic_vector( 6 downto 0);
   signal crt_bank_hi  : std_logic_vector( 6 downto 0);
   signal crt_exrom    : std_logic;
   signal crt_game     : std_logic;
   signal crt_io_rom   : std_logic;
   signal crt_ioe_wena : std_logic;
   signal crt_iof_wena : std_logic;
   signal crt_roml_we  : std_logic;
   signal crt_nmi      : std_logic;

   -- HyperRAM
   signal hr_write         : std_logic;
   signal hr_read          : std_logic;
   signal hr_address       : std_logic_vector(31 downto 0);
   signal hr_writedata     : std_logic_vector(15 downto 0);
   signal hr_byteenable    : std_logic_vector( 1 downto 0);
   signal hr_burstcount    : std_logic_vector( 7 downto 0);
   signal hr_readdata      : std_logic_vector(15 downto 0) := (others => '0');
   signal hr_readdatavalid : std_logic := '0';
   signal hr_waitrequest   : std_logic;
   signal hr_busy          : std_logic := '0';
   signal hr_rnd_wait      : std_logic := '0';
   signal hr_bad_write     : natural := 0;

   signal mem : mem_t := (others => (others => '0'));   -- driven by the stimulus process only

   signal reset_pulses : natural := 0;   -- rising edges of main_reset_core (wrapper resets the C64)

   -- ------------------------------------------------------------------------------------------
   -- .crt image builder: header + CHIP packets, all multi-byte fields big-endian
   -- ------------------------------------------------------------------------------------------
   function be16(v : natural) return byte_vector is
   begin
      return (std_logic_vector(to_unsigned(v / 256, 8)), std_logic_vector(to_unsigned(v mod 256, 8)));
   end function be16;

   function str(s : string) return byte_vector is
      variable r : byte_vector(0 to s'length - 1);
   begin
      for i in 0 to s'length - 1 loop
         r(i) := std_logic_vector(to_unsigned(character'pos(s(s'low + i)), 8));
      end loop;
      return r;
   end function str;

   function crt_header(id, exrom, game : natural) return byte_vector is
      variable r : byte_vector(0 to 63) := (others => X"00");
   begin
      r(0 to 15)  := str("C64 CARTRIDGE   ");
      r(16 to 19) := (X"00", X"00", X"00", X"40");
      r(20 to 21) := be16(16#0100#);
      r(22 to 23) := be16(id);
      r(24)       := std_logic_vector(to_unsigned(exrom, 8));
      r(25)       := std_logic_vector(to_unsigned(game, 8));
      r(32 to 41) := str("EJECT TEST");
      return r;
   end function crt_header;

   -- 8 kB CHIP packet; sig = "CHIP" for a valid packet
   function chip(bank, laddr : natural; sig : string) return byte_vector is
      variable r : byte_vector(0 to 16 + 8192 - 1);
   begin
      r(0 to 3)   := str(sig);
      r(4 to 7)   := (X"00", X"00", X"20", X"10");
      r(8 to 9)   := be16(0);
      r(10 to 11) := be16(bank);
      r(12 to 13) := be16(laddr);
      r(14 to 15) := be16(16#2000#);
      for i in 0 to 8191 loop
         r(16 + i) := std_logic_vector(to_unsigned((i + 37 * bank + laddr / 256) mod 256, 8));
      end loop;
      return r;
   end function chip;

   -- Generic 8K cartridge (id 0): EXROM low, GAME high, one bank at $8000
   constant C_CRT_8K    : byte_vector := crt_header(0, 0, 1) & chip(0, 16#8000#, "CHIP");
   -- EasyFlash (id 32): boots in Ultimax mode (EXROM high, GAME low), RAM at $DF00
   constant C_CRT_EF    : byte_vector := crt_header(32, 1, 0) &
                                         chip(0, 16#8000#, "CHIP") & chip(0, 16#A000#, "CHIP") &
                                         chip(1, 16#8000#, "CHIP") & chip(1, 16#A000#, "CHIP");
   -- Super Snapshot V5 (id 20): starts with its RAM writable at ROML ($8000-$9FFF)
   constant C_CRT_SS5   : byte_vector := crt_header(20, 0, 0) &
                                         chip(0, 16#8000#, "CHIP") & chip(0, 16#A000#, "CHIP");
   -- Broken file: valid header, damaged CHIP signature (parse error "Wrong CHIP header")
   constant C_CRT_BAD   : byte_vector := crt_header(19, 0, 1) & chip(0, 16#8000#, "CHIQ");

   function hex(v : std_logic_vector) return string is
   begin
      return to_hstring(v);
   end function hex;

begin

   qnice_clk <= not qnice_clk after 10 ns when running;
   hr_clk    <= not hr_clk    after  5 ns when running;
   main_clk  <= not main_clk  after 15.86 ns when running;

   ------------------------------------------------------------------------------------------------
   -- Devices under test
   ------------------------------------------------------------------------------------------------

   i_dut : entity work.sw_cartridge_wrapper
      generic map (
         G_BASE_ADDRESS => C_BASE
      )
      port map (
         qnice_clk_i            => qnice_clk,
         qnice_rst_i            => qnice_rst,
         qnice_addr_i           => qnice_addr,
         qnice_data_i           => qnice_wdata,
         qnice_ce_i             => qnice_ce,
         qnice_we_i             => qnice_we,
         qnice_data_o           => qnice_rdata,
         qnice_wait_o           => qnice_wait,
         main_clk_i             => main_clk,
         main_rst_i             => main_rst,
         main_reset_core_o      => main_reset_core,
         main_loading_o         => main_loading,
         main_id_o              => main_id,
         main_exrom_o           => main_exrom,
         main_game_o            => main_game,
         main_size_o            => main_size,
         main_bank_laddr_o      => open,
         main_bank_size_o       => open,
         main_bank_num_o        => open,
         main_bank_raddr_o      => open,
         main_bank_wr_o         => open,
         main_bank_lo_i         => crt_bank_lo,
         main_bank_hi_i         => crt_bank_hi,
         main_bank_wait_o       => main_bank_wait,
         main_ram_addr_i        => cpu_addr,
         main_ram_data_i        => cpu_wdata,
         main_ioe_we_i          => '0',
         main_iof_we_i          => '0',
         main_lo_ram_data_o     => open,
         main_hi_ram_data_o     => open,
         main_ioe_ram_data_o    => open,
         main_iof_ram_data_o    => open,
         main_crt_we_i          => '0',
         main_crt_ram_data_o    => open,
         main_cart_soft_reset_i => soft_rst,
         hr_clk_i               => hr_clk,
         hr_rst_i               => hr_rst,
         hr_write_o             => hr_write,
         hr_read_o              => hr_read,
         hr_address_o           => hr_address,
         hr_writedata_o         => hr_writedata,
         hr_byteenable_o        => hr_byteenable,
         hr_burstcount_o        => hr_burstcount,
         hr_readdata_i          => hr_readdata,
         hr_readdatavalid_i     => hr_readdatavalid,
         hr_waitrequest_i       => hr_waitrequest
      ); -- i_dut

   -- like cartridge_inst in main.vhd: hard reset into rst_i, soft reset into cart_loading_i
   i_cartridge : entity work.cartridge
      port map (
         clk_i             => main_clk,
         rst_i             => main_rst,
         cart_loading_i    => main_loading or soft_rst,
         cart_id_i         => main_id,
         cart_exrom_i      => main_exrom,
         cart_game_i       => main_game,
         cart_size_i       => main_size,
         ioe_i             => cpu_ioe,
         iof_i             => cpu_iof,
         wr_en_i           => cpu_we,
         wr_data_i         => cpu_wdata,
         addr_i            => cpu_addr,
         bank_lo_o         => crt_bank_lo,
         bank_hi_o         => crt_bank_hi,
         ioe_wr_ena_o      => crt_ioe_wena,
         iof_wr_ena_o      => crt_iof_wena,
         io_rom_o          => crt_io_rom,
         io_ext_o          => open,
         io_data_o         => open,
         exrom_o           => crt_exrom,
         game_o            => crt_game,
         roml_we_o         => crt_roml_we,
         freeze_key_i      => '0',
         suppress_freeze_i => '0',
         nmi_o             => crt_nmi,
         nmi_ack_i         => '0'
      ); -- i_cartridge

   ------------------------------------------------------------------------------------------------
   -- HyperRAM model: one burst at a time, random wait states, random latency and data gaps
   ------------------------------------------------------------------------------------------------

   hr_waitrequest <= '1' when hr_busy = '1' or hr_rnd_wait = '1' else '0';

   p_hram : process (hr_clk)
      variable lfsr : unsigned(15 downto 0) := to_unsigned(G_SEED mod 65535 + 1, 16);
      variable busy : boolean := false;
      variable addr : integer;
      variable cnt  : natural;
      variable lat  : natural;
   begin
      if rising_edge(hr_clk) then
         lfsr := lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));
         hr_readdatavalid <= '0';
         if busy then
            if lat > 0 then
               lat := lat - 1;
            elsif lfsr(2) = '1' or lfsr(5) = '1' then   -- a gap now and then
               if addr >= 0 and addr < C_MEM_WORDS then
                  hr_readdata <= mem(addr);
               else
                  hr_readdata <= X"FFFF";
               end if;
               hr_readdatavalid <= '1';
               addr := addr + 1;
               cnt  := cnt - 1;
               if cnt = 0 then
                  busy := false;
               end if;
            end if;
         elsif hr_waitrequest = '0' and hr_read = '1' then
            busy := true;
            addr := to_integer(unsigned(hr_address(21 downto 0))) - to_integer(unsigned(C_BASE));
            cnt  := to_integer(unsigned(hr_burstcount));
            lat  := 4 + to_integer(lfsr(11 downto 9));
         elsif hr_waitrequest = '0' and hr_write = '1' then
            hr_bad_write <= hr_bad_write + 1;   -- nothing in this bench writes the HyperRAM
         end if;
         hr_busy     <= '1' when busy else '0';
         hr_rnd_wait <= lfsr(3) and lfsr(8);
         if hr_rst = '1' then
            busy := false;
            hr_busy <= '0';
         end if;
      end if;
   end process p_hram;

   p_pulses : process (main_clk)
      variable prev : std_logic := '0';
   begin
      if rising_edge(main_clk) then
         if main_reset_core = '1' and prev /= '1' then
            reset_pulses <= reset_pulses + 1;
         end if;
         prev := main_reset_core;
      end if;
   end process p_pulses;

   ------------------------------------------------------------------------------------------------
   -- Stimulus and checks
   ------------------------------------------------------------------------------------------------

   p_stim : process
      variable errors : natural := 0;
      variable rd     : std_logic_vector(15 downto 0);
      variable pulses : natural;

      procedure check(ok : boolean; what : string) is
      begin
         if ok then
            report "  ok    " & what;
         else
            report "  ERROR " & what severity warning;
            errors := errors + 1;
         end if;
      end procedure check;

      -- QNICE bus write; the CSR registers latch on the falling edge
      procedure qwrite(a : natural; d : natural) is
      begin
         wait until rising_edge(qnice_clk);
         qnice_addr  <= std_logic_vector(to_unsigned(a, 28));
         qnice_wdata <= std_logic_vector(to_unsigned(d, 16));
         qnice_ce    <= '1';
         qnice_we    <= '1';
         wait until rising_edge(qnice_clk);
         qnice_ce    <= '0';
         qnice_we    <= '0';
      end procedure qwrite;

      procedure qread(a : natural; d : out std_logic_vector(15 downto 0)) is
      begin
         wait until rising_edge(qnice_clk);
         qnice_addr <= std_logic_vector(to_unsigned(a, 28));
         qnice_ce   <= '1';
         qnice_we   <= '0';
         wait until falling_edge(qnice_clk);
         d := qnice_rdata;
         wait until rising_edge(qnice_clk);
         qnice_ce   <= '0';
      end procedure qread;

      -- poll the parse status like HANDLE_CRTROM_M / CRTROM_M_UNLD do; 2 ms time limit
      procedure wait_parsest(want : natural; what : string) is
         variable v : std_logic_vector(15 downto 0);
      begin
         for i in 0 to 100000 loop
            qread(C_CSR_PARSEST, v);
            if to_integer(unsigned(v)) = want then
               check(true, what & ": parse status " & integer'image(want));
               return;
            end if;
         end loop;
         check(false, what & ": parse status " & integer'image(want) & " never seen, last " & hex(v));
      end procedure wait_parsest;

      -- let every clock domain crossing settle and wait until a running bank cache load is done and
      -- the wrapper has released its reset (the C64 CPU is paused until then); 5 ms time limit
      procedure settle is
      begin
         wait for 2 us;
         for i in 0 to 5000 loop
            exit when main_bank_wait = '0' and main_reset_core = '0';
            wait for 1 us;
         end loop;
         check(main_bank_wait = '0' and main_reset_core = '0', "bank cache load done, C64 released");
         wait for 1 us;
         wait until rising_edge(main_clk);
      end procedure settle;

      procedure put_crt(img : byte_vector) is
         variable m : mem_t := (others => X"5A5A");
      begin
         for i in 0 to img'length / 2 - 1 loop
            m(i) := img(img'low + 2 * i + 1) & img(img'low + 2 * i);   -- little-endian words
         end loop;
         if img'length mod 2 = 1 then
            m(img'length / 2) := X"00" & img(img'high);
         end if;
         mem <= m;
         wait for 0 ns;
      end procedure put_crt;

      -- load a .crt like the Shell does (LOAD_IMAGE + HANDLE_CRTROM_M): status "loading", copy,
      -- file size, status "OK", poll the parse status
      procedure load(img : byte_vector; want : natural; what : string) is
      begin
         qwrite(C_CSR_STATUS, C_ST_LDNG);
         put_crt(img);
         qwrite(C_CSR_FS_LO, img'length mod 65536);
         qwrite(C_CSR_FS_HI, img'length / 65536);
         qwrite(C_CSR_STATUS, C_ST_OK);
         wait_parsest(want, what);
         settle;
      end procedure load;

      -- the C64 is held in (soft) reset while QNICE ejects, like UNLOAD_CRTROM does
      procedure eject_in_reset(what : string) is
      begin
         wait until rising_edge(main_clk);
         soft_rst <= '1';
         qwrite(C_CSR_STATUS, C_ST_IDLE);
         wait_parsest(C_PT_IDLE, what);
         -- RESET_CORE keeps the reset for at least 64 main clock cycles after this point; the C64
         -- side must see the neutral cartridge long before that
         for i in 1 to 8 loop
            wait until rising_edge(main_clk);
         end loop;
         check(to_integer(unsigned(main_id)) = 0 and main_exrom = X"FF" and main_game = X"FF",
               what & ": C64 side neutral 8 cycles after the parse status reads idle");
         wait for 1.9 us;
         wait until rising_edge(main_clk);
         soft_rst <= '0';
         settle;
      end procedure eject_in_reset;

      procedure soft_reset_pulse is
      begin
         wait until rising_edge(main_clk);
         soft_rst <= '1';
         wait for 2.1 us;
         wait until rising_edge(main_clk);
         soft_rst <= '0';
         settle;
      end procedure soft_reset_pulse;

      -- one CPU cycle on the C64 side; a = address, w = write
      procedure cpu(a : natural; w : boolean; d : natural) is
      begin
         wait until rising_edge(main_clk);
         cpu_addr  <= std_logic_vector(to_unsigned(a, 16));
         cpu_wdata <= std_logic_vector(to_unsigned(d, 8));
         cpu_we    <= '1' when w else '0';
         cpu_ioe   <= '1' when a / 256 = 16#DE# else '0';
         cpu_iof   <= '1' when a / 256 = 16#DF# else '0';
         wait until rising_edge(main_clk);
         cpu_we    <= '0';
         cpu_ioe   <= '0';
         cpu_iof   <= '0';
         wait until rising_edge(main_clk);
         wait until rising_edge(main_clk);
      end procedure cpu;

      -- $DFxx read: does the cartridge answer (io_rom = it drives the data bus)?
      procedure probe_df(want : std_logic; what : string) is
      begin
         wait until rising_edge(main_clk);
         cpu_addr <= X"DF00";
         cpu_iof  <= '1';
         wait until rising_edge(main_clk);
         cpu_iof  <= '0';
         wait until falling_edge(main_clk);
         check(crt_io_rom = want, what & ": $DF00 answered by the cartridge = " & std_logic'image(crt_io_rom));
         wait until rising_edge(main_clk);
      end procedure probe_df;

      procedure expect_cart(id, exrom, game : natural; c_exrom, c_game : std_logic; what : string) is
      begin
         check(to_integer(unsigned(main_id)) = id and to_integer(unsigned(main_exrom)) = exrom and
               to_integer(unsigned(main_game)) = game,
               what & ": wrapper id/exrom/game = " & hex(main_id) & "/" & hex(main_exrom) & "/" & hex(main_game));
         check(crt_exrom = c_exrom and crt_game = c_game,
               what & ": C64 sees EXROM/GAME = " & std_logic'image(crt_exrom) & "/" & std_logic'image(crt_game));
      end procedure expect_cart;

      procedure expect_neutral(what : string) is
      begin
         expect_cart(0, 255, 255, '1', '1', what);
         check(main_size = (main_size'range => '0'), what & ": wrapper size = 0");
         check(crt_bank_lo = "0000000" and crt_bank_hi = "0000000", what & ": banks 0");
         check(crt_ioe_wena = '0' and crt_iof_wena = '0' and crt_roml_we = '0',
               what & ": no cartridge RAM in $DExx/$DFxx/ROML");
         check(crt_nmi = '0', what & ": no NMI");
         check(main_loading = '0' and main_bank_wait = '0', what & ": no loading, no bank wait (" &
               std_logic'image(main_loading) & std_logic'image(main_bank_wait) & ")");
      end procedure expect_neutral;

   begin
      report "tb_crt_eject: seed " & integer'image(G_SEED);
      wait for 200 ns;
      qnice_rst <= '0';
      hr_rst    <= '0';
      main_rst  <= '0';
      settle;

      report "T0 power-on: status idle means no cartridge";
      qread(C_CSR_STATUS, rd);
      check(to_integer(unsigned(rd)) = C_ST_IDLE, "T0: CSR status after reset is idle");
      wait_parsest(C_PT_IDLE, "T0");
      expect_neutral("T0");
      check(reset_pulses = 1, "T0: one wrapper reset (main_rst) so far, got " & integer'image(reset_pulses));

      report "T1 load a generic 8K cartridge";
      pulses := reset_pulses;
      load(C_CRT_8K, C_PT_OK, "T1");
      expect_cart(0, 0, 1, '0', '1', "T1");
      check(reset_pulses = pulses + 1, "T1: the wrapper resets the C64 once after the parse");

      report "T2 eject it while the C64 is held in reset";
      pulses := reset_pulses;
      eject_in_reset("T2");
      expect_neutral("T2");
      check(reset_pulses = pulses, "T2: the eject itself does not reset (the Shell does)");

      report "T3 load an EasyFlash (Ultimax, RAM at $DF00) and switch to bank 1";
      pulses := reset_pulses;
      load(C_CRT_EF, C_PT_OK, "T3");
      expect_cart(32, 1, 0, '1', '0', "T3");
      check(reset_pulses = pulses + 1, "T3: the wrapper resets the C64 once after the parse");
      probe_df('1', "T3");
      cpu(16#DE00#, true, 1);       -- bank 1
      cpu(16#DE02#, true, 16#07#);  -- 16K mode: EXROM low, GAME low
      settle;
      check(crt_bank_lo = "0000001" and crt_exrom = '0' and crt_game = '0', "T3: bank 1 and 16K mode");

      report "T4 status loading and error keep the current cartridge (a new file is copied)";
      qwrite(C_CSR_STATUS, C_ST_LDNG);
      wait_parsest(C_PT_IDLE, "T4 loading");
      settle;
      expect_cart(32, 1, 0, '0', '0', "T4 loading");
      probe_df('1', "T4 loading");
      qwrite(C_CSR_STATUS, C_ST_ERR);
      settle;
      expect_cart(32, 1, 0, '0', '0', "T4 error");
      qwrite(C_CSR_STATUS, C_ST_OK);   -- back to "loaded": the file is still in the HyperRAM
      wait_parsest(C_PT_OK, "T4 re-parse");
      settle;

      report "T5 eject the EasyFlash while the C64 is held in reset";
      pulses := reset_pulses;
      eject_in_reset("T5");
      expect_neutral("T5");
      probe_df('0', "T5");
      check(reset_pulses = pulses, "T5: no wrapper reset");

      report "T5b eject while a bank cache load is in flight";
      load(C_CRT_EF, C_PT_OK, "T5b");
      cpu(16#DE00#, true, 1);       -- bank 1: the cacher starts loading it
      wait for 3 us;
      check(main_bank_wait = '1', "T5b: bank cache load running");
      eject_in_reset("T5b");
      expect_neutral("T5b");
      probe_df('0', "T5b");

      report "T6 short reset button after the eject: nothing comes back";
      pulses := reset_pulses;
      wait until rising_edge(hr_clk);
      hr_rst <= '1';
      wait for 200 ns;
      wait until rising_edge(hr_clk);
      hr_rst <= '0';
      soft_reset_pulse;
      wait_parsest(C_PT_IDLE, "T6");
      expect_neutral("T6");
      check(reset_pulses = pulses, "T6: no wrapper reset");

      report "T7 eject twice in a row (idempotent)";
      eject_in_reset("T7");
      expect_neutral("T7");

      report "T8 load again after the eject; a short reset keeps the cartridge";
      load(C_CRT_8K, C_PT_OK, "T8");
      expect_cart(0, 0, 1, '0', '1', "T8");
      pulses := reset_pulses;
      wait until rising_edge(hr_clk);
      hr_rst <= '1';
      wait for 200 ns;
      wait until rising_edge(hr_clk);
      hr_rst <= '0';
      soft_reset_pulse;
      wait_parsest(C_PT_OK, "T8 after the short reset");
      settle;
      expect_cart(0, 0, 1, '0', '1', "T8 after the short reset");
      check(reset_pulses = pulses + 1, "T8: re-parse resets the C64 once");

      report "T9 a .crt with a parse error can be ejected, too";
      load(C_CRT_BAD, C_PT_ERR, "T9");
      eject_in_reset("T9");
      expect_neutral("T9");

      report "T10 eject without reset (Use hardware slot), reset later (Expansion Port change)";
      load(C_CRT_EF, C_PT_OK, "T10");
      probe_df('1', "T10 loaded");
      qwrite(C_CSR_STATUS, C_ST_IDLE);
      wait_parsest(C_PT_IDLE, "T10");
      settle;
      expect_cart(0, 255, 255, '1', '1', "T10 ejected");
      probe_df('1', "T10 ejected, no reset yet (why UNLOAD_CRTROM resets)");
      soft_reset_pulse;
      expect_neutral("T10 after the soft reset");
      probe_df('0', "T10 after the soft reset");

      report "T11 the long reset button (M2M reset) also leaves no cartridge";
      load(C_CRT_8K, C_PT_OK, "T11");
      wait until rising_edge(main_clk);
      qnice_rst <= '1';
      hr_rst    <= '1';
      main_rst  <= '1';
      wait for 200 ns;
      qnice_rst <= '0';
      hr_rst    <= '0';
      main_rst  <= '0';
      settle;
      expect_neutral("T11");

      report "T12 Super Snapshot V5 (writable ROML RAM), unload, then a generic 8K cartridge";
      load(C_CRT_SS5, C_PT_OK, "T12");
      check(crt_roml_we = '1' and crt_game = '0' and crt_exrom = '1', "T12: SS5 starts in Ultimax with ROML RAM");
      eject_in_reset("T12");
      expect_neutral("T12");
      load(C_CRT_8K, C_PT_OK, "T12 next");
      expect_cart(0, 0, 1, '0', '1', "T12 next");
      check(crt_roml_we = '0', "T12 next: ROML is ROM again (CBM80 visible, the cartridge starts)");

      check(hr_bad_write = 0, "no HyperRAM writes");

      report "RESULT ERRORS=" & integer'image(errors);
      running <= false;
      wait;
   end process p_stim;

end architecture simulation;
