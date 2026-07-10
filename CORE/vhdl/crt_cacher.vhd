----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- crt_cacher : Loads and caches the currently-active ROML and ROMH banks of a
--              CRT cartridge image from HyperRAM into two 8 kByte BRAM buffers.
--
-- Clock-domain contract
-- ---------------------
-- All ports on this module are in the HyperRAM clock domain (clk_i).
-- Any clock-domain crossing between the C64 core clock domain and this module
-- (in particular for bank_lo_i, bank_hi_i, bank_wait_o and the PARSER
-- interface) MUST be handled OUTSIDE this module. There are no synchronizers
-- inside this file.
--
-- Interfaces
-- ----------
--  * PARSER (cart_*): a stream of "CHIP" blocks decoded from the CRT file.
--    For each block the parser writes one entry into the bank-address table,
--    mapping (bank_number, load-address) to a byte address in HyperRAM.
--  * CORE (bank_lo_i, bank_hi_i, bank_wait_o, cache_addr_*_o): the core
--    selects the currently-active ROML/ROMH banks by number. This module
--    ensures those banks are resident in BRAM and returns the cache slot
--    index. bank_wait_o is asserted while any load is pending or in flight.
--  * HyperRAM (avm_*): Avalon-MM master; this instance is READ-ONLY.
--  * BRAM: master port to two 8 kByte single-port BRAMs (LO and HI).
--
-- HyperRAM layout
-- ---------------
-- 22 address bits x 16 data bits = 8 MB, word-addressed. Byte addresses stored
-- in the internal bank tables are converted to word addresses by dropping the
-- LSB (bit 0). CRT bank sizes are multiples of 8 kByte, so this is always
-- word-aligned. The CRT file is little-endian: even byte addresses map to
-- data bits 7..0 and odd byte addresses map to bits 15..8.
--
-- Cache
-- -----
-- Two direct-mapped caches (LO and HI) hold 2**G_CACHE_SIZE bank slots each.
-- Replacement policy is round-robin (see next_cache_addr_lo/hi). Note that
-- round-robin can evict a currently-active bank if a cartridge cycles through
-- more banks than the cache can hold; this is intentional and matches the
-- original design.
--
-- Interaction with the HyperRAM controller
-- ----------------------------------------
-- See https://github.com/sy2002/MiSTer2MEGA65/wiki/HyperRAM-for-Beginners
-- Each load transfer is issued as one or more 128-word (256-byte) bursts.
-- A load of a full 8 kByte bank is 32 back-to-back bursts. If the core
-- changes bank while a load is in flight, `restart` is asserted; the FSM then
-- returns to IDLE at the next 128-word burst boundary so the new request can
-- be serviced immediately.
--
-- Done by MJoergen in 2023 and licensed under GPL v3.
----------------------------------------------------------------------------------

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std.all;
   use ieee.numeric_std_unsigned.all;

entity crt_cacher is
   generic (
      G_CACHE_SIZE : natural
   );
   port (
      clk_i               : in  std_logic;
      rst_i               : in  std_logic;

      -- Control interface (PARSER)
      cart_valid_i        : in  std_logic;
      cart_bank_laddr_i   : in  std_logic_vector(15 downto 0);
      cart_bank_size_i    : in  std_logic_vector(15 downto 0);
      cart_bank_num_i     : in  std_logic_vector(15 downto 0);
      cart_bank_raddr_i   : in  std_logic_vector(24 downto 0);     -- Byte address in HyperRAM
      cart_bank_wr_i      : in  std_logic;

      -- Control interface (CORE)
      bank_lo_i           : in  std_logic_vector( 6 downto 0);     -- Requested ROM LO bank number
      bank_hi_i           : in  std_logic_vector( 6 downto 0);     -- Requested ROM HI bank number
      bank_wait_o         : out std_logic;                         -- '1' while any load is pending or in flight
      cache_addr_lo_o     : out std_logic_vector(G_CACHE_SIZE-1 downto 0);
      cache_addr_hi_o     : out std_logic_vector(G_CACHE_SIZE-1 downto 0);

      -- Connect to HyperRAM (Avalon-MM master, read-only)
      avm_write_o         : out std_logic;
      avm_read_o          : out std_logic;
      avm_address_o       : out std_logic_vector(21 downto 0);     -- Word address
      avm_writedata_o     : out std_logic_vector(15 downto 0);
      avm_byteenable_o    : out std_logic_vector( 1 downto 0);
      avm_burstcount_o    : out std_logic_vector( 7 downto 0);
      avm_readdata_i      : in  std_logic_vector(15 downto 0);
      avm_readdatavalid_i : in  std_logic;
      avm_waitrequest_i   : in  std_logic;

      -- Connect to BRAM (two 8 kByte single-port BRAMs)
      bram_address_o      : out std_logic_vector(11 downto 0);
      bram_data_o         : out std_logic_vector(15 downto 0);
      bram_lo_wren_o      : out std_logic;
      bram_lo_q_i         : in  std_logic_vector(15 downto 0);
      bram_hi_wren_o      : out std_logic;
      bram_hi_q_i         : in  std_logic_vector(15 downto 0)
   );
end entity crt_cacher;

architecture synthesis of crt_cacher is

   ---------------------------------------------------------------------------
   -- Local constants
   ---------------------------------------------------------------------------
   -- Each load transfer is issued as bursts of C_BURST_WORDS 16-bit words
   -- (= 256 bytes). One full 8 kByte bank therefore requires
   -- 8192 / 256 = 32 consecutive bursts.
   constant C_BURST_WORDS         : natural := 128;
   constant C_BURST_COUNT         : std_logic_vector(7 downto 0)  := X"80";  -- 128

   -- Boundary detection: the last valid readdata of a 128-word burst arrives
   -- when the pre-increment address is $7E (so the post-increment write to
   -- BRAM happens at $7F, $FF, $17F, ... i.e. every 128th word).
   constant C_BURST_WRAP_MARK     : std_logic_vector(6 downto 0)  := 7X"7E";

   -- The LO and HI BRAMs are each 4 kWord = 8 kByte deep. The final BRAM
   -- write of a full bank load happens at address $FFF; the FSM detects the
   -- burst preceding it by observing the pre-increment address $FFE.
   constant C_BRAM_LAST_MINUS_ONE : std_logic_vector(11 downto 0) := X"FFE";

   -- Increment applied to the HyperRAM word address between bursts of the
   -- same load. Equal to C_BURST_WORDS.
   constant C_BURST_ADDR_INCR     : std_logic_vector(21 downto 0) :=
      std_logic_vector(to_unsigned(C_BURST_WORDS, 22));

   -- Duplication offset when a small (<= 8 kByte) ROML bank is aliased into
   -- the corresponding ROMH slot. 8 kByte = $2000 bytes.
   constant C_ROML_ALIAS_OFFSET   : std_logic_vector(22 downto 0) :=
      "000" & X"02000";

   ---------------------------------------------------------------------------
   -- FSM
   ---------------------------------------------------------------------------
   type t_state is (IDLE_ST,
                    READ_HI_ST,
                    READ_LO_ST);
   signal state : t_state := IDLE_ST;

   ---------------------------------------------------------------------------
   -- Bank tables : map "CRT bank number" -> "byte address in HyperRAM"
   ---------------------------------------------------------------------------
   type mem_t is array (natural range <>) of std_logic_vector(22 downto 0);
   signal lobanks : mem_t(0 to 127) := (others => (others => '0'));
   signal hibanks : mem_t(0 to 127) := (others => (others => '0'));

   ---------------------------------------------------------------------------
   -- Control / edge-detect registers
   ---------------------------------------------------------------------------
   signal cart_valid_d  : std_logic := '0';
   signal bank_lo_d     : std_logic_vector(6 downto 0) := (others => '0');
   signal bank_hi_d     : std_logic_vector(6 downto 0) := (others => '0');
   signal hi_load       : std_logic := '0';
   signal hi_load_done  : std_logic := '0';
   signal lo_load       : std_logic := '0';
   signal lo_load_done  : std_logic := '0';

   -- `restart` is asserted by p_crt_load whenever a new bank is requested
   -- while a load is in flight. It causes p_fsm to return to IDLE at the
   -- next 128-word burst boundary so the new bank can be serviced without
   -- first draining the entire outstanding load.
   signal restart       : std_logic := '0';

   ---------------------------------------------------------------------------
   -- Cache tag arrays (direct-mapped, round-robin replacement)
   ---------------------------------------------------------------------------
   type cache_t is array (natural range <>) of std_logic_vector(6 downto 0);
   signal cache_ram_lo       : cache_t(0 to 2**G_CACHE_SIZE-1) := (others => (others => '0'));
   signal cache_ram_hi       : cache_t(0 to 2**G_CACHE_SIZE-1) := (others => (others => '0'));
   signal next_cache_addr_lo : std_logic_vector(G_CACHE_SIZE-1 downto 0) := (others => '0');
   signal next_cache_addr_hi : std_logic_vector(G_CACHE_SIZE-1 downto 0) := (others => '0');

begin

   ---------------------------------------------------------------------------
   -- Static tie-offs
   ---------------------------------------------------------------------------
   -- This master never writes to HyperRAM.
   avm_writedata_o  <= (others => '0');
   avm_byteenable_o <= (others => '1');

   ---------------------------------------------------------------------------
   -- bank_wait_o : asserted whenever a load is pending or in flight, i.e.
   -- while the currently-requested bank contents are not yet valid in BRAM.
   ---------------------------------------------------------------------------
   bank_wait_o <= '1' when state   = READ_HI_ST
                        or state   = READ_LO_ST
                        or hi_load = '1'
                        or lo_load = '1'
             else '0';

   ---------------------------------------------------------------------------
   -- p_banks : populate the bank-number -> HyperRAM-byte-address tables
   -- as CHIP blocks arrive from the parser.
   --
   -- The CRT file's CHIP "Load address" field (cart_bank_laddr_i) indicates
   -- whether the block is destined for ROML ($8000) or ROMH ($A000/$E000).
   -- For CHIP blocks larger than 8 kByte, the second half (offset $2000)
   -- represents the ROMH image; this is the "duplicate ROML -> ROMH" case.
   ---------------------------------------------------------------------------
   p_banks : process (clk_i)
      variable v_bank : natural range 0 to 127;
   begin
      if rising_edge(clk_i) then
         if cart_bank_wr_i = '1' then
            v_bank := to_integer(cart_bank_num_i(6 downto 0));

            if cart_bank_laddr_i <= X"8000" then
               -- ROML CHIP block. Register the byte address for LO...
               lobanks(v_bank) <= cart_bank_raddr_i(22 downto 0);

               -- ...and default HI to the same address (used when the
               -- cartridge maps the same ROML image at both $8000 and
               -- $A000/$E000, as some 8 kByte carts do).
               hibanks(v_bank) <= cart_bank_raddr_i(22 downto 0);

               -- If this CHIP block is larger than 8 kByte, the CRT layout
               -- puts ROML in the first $2000 bytes and ROMH in the next
               -- $2000 bytes. Retarget HI accordingly.
               if cart_bank_size_i > X"2000" then
                  hibanks(v_bank) <= cart_bank_raddr_i(22 downto 0)
                                     + C_ROML_ALIAS_OFFSET;
               end if;
            else
               -- Pure ROMH CHIP block (typical load address $A000 or $E000).
               hibanks(v_bank) <= cart_bank_raddr_i(22 downto 0);
            end if;
         end if;
      end if;
   end process p_banks;

   ---------------------------------------------------------------------------
   -- p_fsm : issues read bursts to HyperRAM and streams the returned data
   -- into the LO or HI BRAM. One full bank load is 32 x 128-word bursts.
   ---------------------------------------------------------------------------
   p_fsm : process (clk_i)
   begin
      if rising_edge(clk_i) then
         -- Default assignments (single-cycle strobes)
         bram_lo_wren_o <= '0';
         bram_hi_wren_o <= '0';
         hi_load_done   <= '0';
         lo_load_done   <= '0';

         -- Once an Avalon-MM command has been accepted, deassert the request.
         if avm_waitrequest_i = '0' then
            avm_write_o <= '0';
            avm_read_o  <= '0';
         end if;

         case state is
            when IDLE_ST =>
               if hi_load = '1' and hi_load_done = '0' then
                  -- Start loading the HI bank. Convert the stored byte
                  -- address to the word address used by HyperRAM by
                  -- dropping bit 0 (bank starts are 8 kByte-aligned).
                  avm_write_o      <= '0';
                  avm_read_o       <= '1';
                  avm_address_o    <= hibanks(to_integer(bank_hi_i))(22 downto 1);
                  avm_burstcount_o <= C_BURST_COUNT;
                  -- BRAM address is pre-incremented; start at all-ones so
                  -- the first BRAM write lands at address $000.
                  bram_address_o   <= (others => '1');
                  state            <= READ_HI_ST;

               elsif lo_load = '1' and lo_load_done = '0' then
                  -- Start loading the LO bank.
                  avm_write_o      <= '0';
                  avm_read_o       <= '1';
                  avm_address_o    <= lobanks(to_integer(bank_lo_i))(22 downto 1);
                  avm_burstcount_o <= C_BURST_COUNT;
                  bram_address_o   <= (others => '1');
                  state            <= READ_LO_ST;
               end if;

            when READ_HI_ST =>
               if avm_readdatavalid_i = '1' then
                  bram_data_o    <= avm_readdata_i;
                  bram_hi_wren_o <= '1';
                  bram_address_o <= bram_address_o + 1;

                  if bram_address_o = C_BRAM_LAST_MINUS_ONE then
                     -- Final word of the entire 8 kByte bank has just been
                     -- written; signal completion and return to idle.
                     hi_load_done <= '1';
                     state        <= IDLE_ST;
                  elsif bram_address_o(6 downto 0) = C_BURST_WRAP_MARK then
                     -- End of the current 128-word burst.
                     if restart = '1' then
                        -- A new bank was requested mid-transfer. Abort the
                        -- remaining bursts and let IDLE_ST dispatch the new
                        -- request.
                        state <= IDLE_ST;
                     else
                        -- Chain the next 128-word burst back-to-back.
                        avm_write_o      <= '0';
                        avm_read_o       <= '1';
                        avm_address_o    <= avm_address_o + C_BURST_ADDR_INCR;
                        avm_burstcount_o <= C_BURST_COUNT;
                     end if;
                  end if;
               end if;

            when READ_LO_ST =>
               if avm_readdatavalid_i = '1' then
                  bram_data_o    <= avm_readdata_i;
                  bram_lo_wren_o <= '1';
                  bram_address_o <= bram_address_o + 1;

                  if bram_address_o = C_BRAM_LAST_MINUS_ONE then
                     lo_load_done <= '1';
                     state        <= IDLE_ST;
                  elsif bram_address_o(6 downto 0) = C_BURST_WRAP_MARK then
                     if restart = '1' then
                        state <= IDLE_ST;
                     else
                        avm_write_o      <= '0';
                        avm_read_o       <= '1';
                        avm_address_o    <= avm_address_o + C_BURST_ADDR_INCR;
                        avm_burstcount_o <= C_BURST_COUNT;
                     end if;
                  end if;
               end if;
         end case;

         if rst_i = '1' then
            avm_write_o      <= '0';
            avm_read_o       <= '0';
            avm_address_o    <= (others => '0');
            avm_burstcount_o <= (others => '0');
            bram_address_o   <= (others => '0');
            bram_data_o      <= (others => '0');
            bram_lo_wren_o   <= '0';
            bram_hi_wren_o   <= '0';
            state            <= IDLE_ST;
         end if;
      end if;
   end process p_fsm;

   ---------------------------------------------------------------------------
   -- p_crt_load : cache lookup and load scheduling.
   --
   -- On every change of bank_lo_i / bank_hi_i:
   --   * If the requested bank is already resident in the cache, drive the
   --     matching cache slot on cache_addr_*_o.
   --   * Otherwise pick the round-robin replacement slot, update the tag,
   --     drive the slot on cache_addr_*_o, request a load (lo_load/hi_load)
   --     and assert `restart` so any in-flight burst returns to IDLE at
   --     the next 128-word boundary.
   --
   -- On the rising edge of cart_valid_i (new cartridge inserted): reset
   -- both caches, capture the initial LO/HI bank numbers into slot 0 of
   -- each cache and trigger initial loads.
   ---------------------------------------------------------------------------
   p_crt_load : process (clk_i)
      variable found_v : boolean;
   begin
      if rising_edge(clk_i) then
         cart_valid_d <= cart_valid_i;
         bank_lo_d    <= bank_lo_i;
         bank_hi_d    <= bank_hi_i;

         if lo_load_done = '1' then
            lo_load <= '0';
         end if;
         if hi_load_done = '1' then
            hi_load <= '0';
         end if;

         if cart_valid_i = '1' then
            ------------------------------------------------------------------
            -- LO bank change detection
            ------------------------------------------------------------------
            if bank_lo_d /= bank_lo_i then
               found_v := false;
               for i in 0 to 2**G_CACHE_SIZE-1 loop
                  if cache_ram_lo(i) = bank_lo_i then
                     found_v         := true;
                     cache_addr_lo_o <= std_logic_vector(to_unsigned(i, G_CACHE_SIZE));
                     exit;
                  end if;
               end loop;
               if not found_v then
                  -- Miss: allocate the round-robin slot, update the tag and
                  -- schedule a HyperRAM load into that slot.
                  cache_addr_lo_o                              <= next_cache_addr_lo;
                  cache_ram_lo(to_integer(next_cache_addr_lo)) <= bank_lo_i;
                  next_cache_addr_lo                           <= next_cache_addr_lo + 1;
                  lo_load                                      <= '1';
                  restart                                      <= '1';
               end if;
            end if;

            ------------------------------------------------------------------
            -- HI bank change detection
            ------------------------------------------------------------------
            if bank_hi_d /= bank_hi_i then
               found_v := false;
               for i in 0 to 2**G_CACHE_SIZE-1 loop
                  if cache_ram_hi(i) = bank_hi_i then
                     found_v         := true;
                     cache_addr_hi_o <= std_logic_vector(to_unsigned(i, G_CACHE_SIZE));
                     exit;
                  end if;
               end loop;
               if not found_v then
                  cache_addr_hi_o                              <= next_cache_addr_hi;
                  cache_ram_hi(to_integer(next_cache_addr_hi)) <= bank_hi_i;
                  next_cache_addr_hi                           <= next_cache_addr_hi + 1;
                  hi_load                                      <= '1';
                  restart                                      <= '1';
               end if;
            end if;
         end if;

         ---------------------------------------------------------------------
         -- New cartridge inserted: invalidate everything and pre-load slot 0
         -- of both caches with the currently-selected bank numbers.
         ---------------------------------------------------------------------
         if cart_valid_d = '0' and cart_valid_i = '1' then
            cache_addr_lo_o    <= (others => '0');
            cache_addr_hi_o    <= (others => '0');
            cache_ram_lo       <= (others => (others => '0'));
            cache_ram_hi       <= (others => (others => '0'));

            -- Tag slot 0 with the initial bank numbers so that a subsequent
            -- request for the same bank hits, and a request for bank 0 (if
            -- different) correctly misses.
            cache_ram_lo(0)    <= bank_lo_i;
            cache_ram_hi(0)    <= bank_hi_i;

            -- Round-robin cursor starts at 1, i.e. the next miss will
            -- allocate slot 1 (slot 0 is now owned by the initial bank).
            next_cache_addr_lo <= std_logic_vector(to_unsigned(1, G_CACHE_SIZE));
            next_cache_addr_hi <= std_logic_vector(to_unsigned(1, G_CACHE_SIZE));

            -- Kick off the initial loads.
            lo_load            <= '1';
            hi_load            <= '1';
         end if;

         -- Clear the restart flag once the FSM has actually observed it.
         if state = IDLE_ST then
            restart <= '0';
         end if;

         if rst_i = '1' then
            cart_valid_d    <= '0';
            cache_addr_lo_o <= (others => '0');
            cache_addr_hi_o <= (others => '0');
            lo_load         <= '0';
            hi_load         <= '0';
            restart         <= '0';
         end if;
      end if;
   end process p_crt_load;

end architecture synthesis;

