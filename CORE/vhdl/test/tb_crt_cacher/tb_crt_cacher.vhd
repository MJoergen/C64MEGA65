----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- Self-checking bench for the bank cache of simulated cartridges (crt_cacher.vhd),
-- see README.md. GitHub issue #255.
--
-- The real crt_cacher is connected to the real HyperRAM controller state machine
-- (hyperram_ctrl.vhd). A small model stands in for the HyperRAM device and the
-- receive path: every word it returns is a function of its word address, so the
-- bench knows what each cache slot has to contain.
--
-- For a random sequence of bank selections the bench checks after each selection:
--   * hit or miss: bank_wait_o must be asserted exactly when a reference model of the
--     cache (2**G_CACHE_SIZE slots, round-robin replacement, slot 0 preloaded with the
--     bank that is selected when the cartridge becomes valid) predicts a miss
--   * data: all 4096 words of the selected ROML slot and of the selected ROMH slot
--     must be the words of the selected bank
--
-- G_EF = true selects the same bank number for ROML and ROMH with every step, as an
-- EasyFlash does; G_EF = false changes the two bank numbers independently.
--
-- done by sy2002 in 2026 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use ieee.math_real.all;

entity tb_crt_cacher is
   generic (
      G_CACHE_SIZE : natural := 5;
      G_STEPS      : natural := 300;
      G_SEED       : natural := 1;
      G_NBANKS     : natural := 64;
      G_EF         : boolean := true
   );
end entity tb_crt_cacher;

architecture simulation of tb_crt_cacher is

   constant C_SLOTS : natural := 2 ** G_CACHE_SIZE;

   signal   clk     : std_logic := '0';
   signal   rst     : std_logic := '1';
   signal   running : boolean   := true;
   signal   cnt     : integer   := 0;

   -- PARSER side of the cacher
   signal   cart_valid      : std_logic                     := '0';
   signal   cart_bank_laddr : std_logic_vector(15 downto 0) := (others => '0');
   signal   cart_bank_num   : std_logic_vector(15 downto 0) := (others => '0');
   signal   cart_bank_raddr : std_logic_vector(24 downto 0) := (others => '0');
   signal   cart_bank_wr    : std_logic                     := '0';

   -- CORE side of the cacher
   signal   bank_lo       : std_logic_vector(6 downto 0) := (others => '0');
   signal   bank_hi       : std_logic_vector(6 downto 0) := (others => '0');
   signal   bank_wait     : std_logic;
   signal   cache_addr_lo : std_logic_vector(G_CACHE_SIZE - 1 downto 0);
   signal   cache_addr_hi : std_logic_vector(G_CACHE_SIZE - 1 downto 0);

   -- Avalon-MM between the cacher and the HyperRAM controller
   signal   c_write   : std_logic;
   signal   c_read    : std_logic;
   signal   c_valid   : std_logic;
   signal   c_wait    : std_logic;
   signal   c_addr    : std_logic_vector(21 downto 0);
   signal   c_addr32  : std_logic_vector(31 downto 0);
   signal   c_wdata   : std_logic_vector(15 downto 0);
   signal   c_rdata   : std_logic_vector(15 downto 0);
   signal   c_be      : std_logic_vector(1 downto 0);
   signal   c_bc      : std_logic_vector(7 downto 0);

   -- One dummy transaction after reset stands in for the configuration write that
   -- hyperram_config.vhd issues in the real design (it brings avm_waitrequest_o to '0').
   signal   init_read : std_logic := '0';
   signal   h_read    : std_logic;
   signal   h_bc      : std_logic_vector(7 downto 0);

   -- HyperRAM device and receive path model
   signal   hb_read   : std_logic;
   signal   hb_dq_ie  : std_logic;
   signal   hb_csn    : std_logic;
   signal   dq_in     : std_logic_vector(15 downto 0);
   signal   rd_pipe   : std_logic_vector(2 downto 0) := (others => '0');
   signal   dev_addr  : unsigned(21 downto 0)        := (others => '0');

   -- BRAM model, addressed with slot & word address as in sw_cartridge_wrapper.vhd
   signal   bram_addr : std_logic_vector(11 downto 0);
   signal   bram_data : std_logic_vector(15 downto 0);
   signal   lo_wren   : std_logic;
   signal   hi_wren   : std_logic;

   type     ram_t is array (0 to C_SLOTS * 4096 - 1) of std_logic_vector(15 downto 0);
   signal   lo_ram    : ram_t := (others => (others => 'U'));
   signal   hi_ram    : ram_t := (others => (others => 'U'));

   -- The word that the HyperRAM model stores at word address a. Bank b has its ROML half
   -- at word address b * 8192 and its ROMH half at b * 8192 + 4096, so the word differs
   -- between any two halves at the same offset.
   pure function f_data (a : unsigned(21 downto 0)) return std_logic_vector is
   begin
      return std_logic_vector(a(15 downto 0) xor ("0000000000" & a(21 downto 16)));
   end function f_data;

begin

   clk <= not clk after 5 ns when running else '0';   -- 100 MHz HyperRAM clock
   cnt <= cnt + 1 when rising_edge(clk);

   crt_cacher_inst : entity work.crt_cacher
      generic map (
         G_CACHE_SIZE => G_CACHE_SIZE
      )
      port map (
         clk_i               => clk,
         rst_i               => rst,
         cart_valid_i        => cart_valid,
         cart_bank_laddr_i   => cart_bank_laddr,
         cart_bank_size_i    => X"2000",
         cart_bank_num_i     => cart_bank_num,
         cart_bank_raddr_i   => cart_bank_raddr,
         cart_bank_wr_i      => cart_bank_wr,
         bank_lo_i           => bank_lo,
         bank_hi_i           => bank_hi,
         bank_wait_o         => bank_wait,
         cache_addr_lo_o     => cache_addr_lo,
         cache_addr_hi_o     => cache_addr_hi,
         avm_write_o         => c_write,
         avm_read_o          => c_read,
         avm_address_o       => c_addr,
         avm_writedata_o     => c_wdata,
         avm_byteenable_o    => c_be,
         avm_burstcount_o    => c_bc,
         avm_readdata_i      => c_rdata,
         avm_readdatavalid_i => c_valid,
         avm_waitrequest_i   => c_wait,
         bram_address_o      => bram_addr,
         bram_data_o         => bram_data,
         bram_lo_wren_o      => lo_wren,
         bram_lo_q_i         => (others => '0'),
         bram_hi_wren_o      => hi_wren,
         bram_hi_q_i         => (others => '0')
      ); -- crt_cacher_inst

   c_addr32 <= "0000000000" & c_addr;
   h_read   <= c_read or init_read;
   h_bc     <= X"01" when init_read = '1' else c_bc;

   hyperram_ctrl_inst : entity work.hyperram_ctrl
      generic map (
         G_LATENCY => 4
      )
      port map (
         clk_i               => clk,
         rst_i               => rst,
         avm_write_i         => c_write,
         avm_read_i          => h_read,
         avm_address_i       => c_addr32,
         avm_writedata_i     => c_wdata,
         avm_byteenable_i    => c_be,
         avm_burstcount_i    => h_bc,
         avm_readdata_o      => c_rdata,
         avm_readdatavalid_o => c_valid,
         avm_waitrequest_o   => c_wait,
         count_long_o        => open,
         count_short_o       => open,
         hb_rstn_o           => open,
         hb_csn_o            => hb_csn,
         hb_ck_ddr_o         => open,
         hb_dq_ddr_in_i      => dq_in,
         hb_dq_ddr_out_o     => open,
         hb_dq_oe_o          => open,
         hb_dq_ie_i          => hb_dq_ie,
         hb_rwds_ddr_out_o   => open,
         hb_rwds_oe_o        => open,
         hb_rwds_in_i        => '0',        -- the device never asks for the double latency
         hb_read_o           => hb_read
      ); -- hyperram_ctrl_inst

   -- Device and receive path: the first word of a burst is valid three clocks after the
   -- controller starts reading, then one word per clock until chip select goes high.
   device_proc : process (clk)
   begin
      if rising_edge(clk) then
         rd_pipe <= rd_pipe(1 downto 0) & (hb_read and not hb_csn);
         if c_read = '1' and c_wait = '0' then
            dev_addr <= unsigned(c_addr);
         elsif hb_dq_ie = '1' then
            dev_addr <= dev_addr + 1;
         end if;
      end if;
   end process device_proc;

   hb_dq_ie <= rd_pipe(2) and hb_read and not hb_csn;
   dq_in    <= f_data(dev_addr);

   bram_proc : process (clk)
   begin
      if rising_edge(clk) then
         if lo_wren = '1' then
            lo_ram(to_integer(unsigned(cache_addr_lo)) * 4096 + to_integer(unsigned(bram_addr))) <= bram_data;
         end if;
         if hi_wren = '1' then
            hi_ram(to_integer(unsigned(cache_addr_hi)) * 4096 + to_integer(unsigned(bram_addr))) <= bram_data;
         end if;
      end if;
   end process bram_proc;

   test_proc : process
      variable seed1_v : positive := 17 + G_SEED;
      variable seed2_v : positive := 4711 + 3 * G_SEED;
      variable r_v     : real;

      -- Reference model: tags per slot (-1 = never loaded) and the round-robin pointer
      type     tag_t is array (0 to C_SLOTS - 1) of integer;
      variable ref_tag_lo_v : tag_t   := (others => -1);
      variable ref_tag_hi_v : tag_t   := (others => -1);
      variable ref_ptr_lo_v : integer := 1;
      variable ref_ptr_hi_v : integer := 1;
      variable hot_v        : tag_t;

      variable cur_lo_v   : integer := 0;
      variable cur_hi_v   : integer := 0;
      variable new_lo_v   : integer;
      variable new_hi_v   : integer;
      variable miss_lo_v  : boolean;
      variable miss_hi_v  : boolean;
      variable waited_v   : boolean;
      variable t0_v       : integer;
      variable n_miss_v   : integer := 0;
      variable n_hit_v    : integer := 0;
      variable n_err_v    : integer := 0;
      variable min_wait_v : integer := integer'high;
      variable max_wait_v : integer := 0;

      procedure ref_select (
         bank          : integer;
         variable tag  : inout tag_t;
         variable ptr  : inout integer;
         variable miss : out boolean
      ) is
      begin
         for i in 0 to C_SLOTS - 1 loop
            if tag(i) = bank then
               miss := false;
               return;
            end if;
         end loop;
         miss     := true;
         tag(ptr) := bank;
         ptr      := (ptr + 1) mod C_SLOTS;
      end procedure ref_select;

      procedure check_slot (
         bank  : integer;
         is_hi : boolean
      ) is
         variable base_v : unsigned(21 downto 0);
         variable slot_v : integer;
         variable got_v  : std_logic_vector(15 downto 0);
      begin
         if is_hi then
            base_v := to_unsigned(bank * 8192 + 4096, 22);
            slot_v := to_integer(unsigned(cache_addr_hi));
         else
            base_v := to_unsigned(bank * 8192, 22);
            slot_v := to_integer(unsigned(cache_addr_lo));
         end if;
         for w in 0 to 4095 loop
            if is_hi then
               got_v := hi_ram(slot_v * 4096 + w);
            else
               got_v := lo_ram(slot_v * 4096 + w);
            end if;
            if got_v /= f_data(base_v + w) then
               n_err_v := n_err_v + 1;
               if n_err_v < 10 then
                  report "DATA MISMATCH: bank " & integer'image(bank) & ", ROMH " & boolean'image(is_hi) &
                         ", slot " & integer'image(slot_v) & ", word " & integer'image(w)
                     severity warning;
               end if;
               exit;
            end if;
         end loop;
      end procedure check_slot;

      impure function random_bank return integer is
      begin
         uniform(seed1_v, seed2_v, r_v);
         return integer(floor(r_v * real(G_NBANKS))) mod G_NBANKS;
      end function random_bank;

   begin
      for i in 1 to 10 loop
         wait until rising_edge(clk);
      end loop;
      rst <= '0';
      for i in 1 to 10 loop
         wait until rising_edge(clk);
      end loop;

      init_read <= '1';
      wait until rising_edge(clk);
      wait until rising_edge(clk);
      init_read <= '0';
      wait until c_wait = '0' and rising_edge(clk);
      for i in 1 to 10 loop
         wait until rising_edge(clk);
      end loop;

      -- What crt_parser.vhd reports for a 1 MB EasyFlash image: 64 ROML and 64 ROMH chips
      for b in 0 to 63 loop
         cart_bank_num   <= std_logic_vector(to_unsigned(b, 16));
         cart_bank_laddr <= X"8000";
         cart_bank_raddr <= std_logic_vector(to_unsigned(b * 16384, 25));
         cart_bank_wr    <= '1';
         wait until rising_edge(clk);
         cart_bank_laddr <= X"A000";
         cart_bank_raddr <= std_logic_vector(to_unsigned(b * 16384 + 8192, 25));
         wait until rising_edge(clk);
      end loop;
      cart_bank_wr <= '0';
      wait until rising_edge(clk);

      -- New cartridge: the cacher loads bank 0 into slot 0 of both caches
      cart_valid <= '1';
      for i in 1 to 4 loop
         wait until rising_edge(clk);
      end loop;
      wait until bank_wait = '0' and rising_edge(clk);
      ref_tag_lo_v(0) := 0;
      ref_tag_hi_v(0) := 0;
      check_slot(0, false);
      check_slot(0, true);

      -- A set of frequently selected banks plus random others gives a mix of hits and misses
      for i in 0 to C_SLOTS - 1 loop
         hot_v(i) := random_bank;
      end loop;

      for step in 1 to G_STEPS loop
         uniform(seed1_v, seed2_v, r_v);
         if r_v < 0.55 then
            uniform(seed1_v, seed2_v, r_v);
            new_lo_v := hot_v(integer(floor(r_v * real(C_SLOTS))) mod C_SLOTS);
         else
            new_lo_v := random_bank;
         end if;
         if G_EF then
            new_hi_v := new_lo_v;
         else
            uniform(seed1_v, seed2_v, r_v);
            if r_v < 0.5 then
               new_hi_v := cur_hi_v;
            else
               new_hi_v := random_bank;
            end if;
            uniform(seed1_v, seed2_v, r_v);
            if r_v < 0.3 then
               new_lo_v := cur_lo_v;
            end if;
         end if;

         miss_lo_v := false;
         miss_hi_v := false;
         if new_lo_v /= cur_lo_v then
            ref_select(new_lo_v, ref_tag_lo_v, ref_ptr_lo_v, miss_lo_v);
         end if;
         if new_hi_v /= cur_hi_v then
            ref_select(new_hi_v, ref_tag_hi_v, ref_ptr_hi_v, miss_hi_v);
         end if;
         cur_lo_v := new_lo_v;
         cur_hi_v := new_hi_v;

         bank_lo <= std_logic_vector(to_unsigned(new_lo_v, 7));
         bank_hi <= std_logic_vector(to_unsigned(new_hi_v, 7));
         t0_v    := cnt;
         for i in 1 to 4 loop
            wait until rising_edge(clk);
         end loop;
         waited_v := bank_wait = '1';
         if waited_v then
            wait until bank_wait = '0' and rising_edge(clk);
            if miss_lo_v and miss_hi_v then
               -- both halves loaded: the case of an EasyFlash bank switch
               if cnt - t0_v > max_wait_v then
                  max_wait_v := cnt - t0_v;
               end if;
               if cnt - t0_v < min_wait_v then
                  min_wait_v := cnt - t0_v;
               end if;
            end if;
            n_miss_v := n_miss_v + 1;
         else
            n_hit_v := n_hit_v + 1;
         end if;
         if waited_v /= (miss_lo_v or miss_hi_v) then
            n_err_v := n_err_v + 1;
            if n_err_v < 10 then
               report "HIT/MISS MISMATCH at step " & integer'image(step) & ": ROML bank " & integer'image(new_lo_v) &
                      ", ROMH bank " & integer'image(new_hi_v) & ", bank_wait " & boolean'image(waited_v) &
                      ", reference miss " & boolean'image(miss_lo_v or miss_hi_v)
                  severity warning;
            end if;
         end if;
         wait until rising_edge(clk);
         check_slot(cur_lo_v, false);
         check_slot(cur_hi_v, true);

         uniform(seed1_v, seed2_v, r_v);
         for i in 1 to integer(floor(r_v * 20.0)) loop
            wait until rising_edge(clk);
         end loop;
      end loop;

      if max_wait_v = 0 then
         min_wait_v := 0;
      end if;
      report "RESULT slots=" & integer'image(C_SLOTS) & " ef=" & boolean'image(G_EF) &
             " seed=" & integer'image(G_SEED) & " banks=" & integer'image(G_NBANKS) &
             " steps=" & integer'image(G_STEPS) & " misses=" & integer'image(n_miss_v) &
             " hits=" & integer'image(n_hit_v) &
             " full_miss_clocks=" & integer'image(min_wait_v) & ".." & integer'image(max_wait_v) &
             " ERRORS=" & integer'image(n_err_v);
      running <= false;
      wait;
   end process test_proc;

end architecture simulation;
