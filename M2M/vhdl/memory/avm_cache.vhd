-------------------------------------------------------------------------------
-- Description: This module implements a single-line read-ahead (prefetch) buffer using the
-- Avalon Memory-Mapped (AVM) bus interface.
--
-- Behaviour:
--   On a read miss, the module fetches G_CACHE_SIZE words starting from the
--   requested address and fills the internal buffer. The first word(s) of the
--   burst are forwarded to the client as they arrive.
--
--   On a read hit, data is served directly from the buffer in a single cycle.
--   Multi-word reads (burstcount > 1) always bypass the cache and trigger a
--   full-line fetch.  As fill data arrives from memory, the first
--   'burstcount' words are forwarded to the client in-order.  If the client's
--   burst spans more than G_CACHE_SIZE words, the module chains additional
--   G_CACHE_SIZE-word fetches (continuation reads) until all requested words
--   have been delivered.
--
--   When the client reads past the midpoint of the buffer, the module performs
--   a sliding-window operation: the upper half of the buffer is shifted into
--   the lower half, the base address advances by G_CACHE_SIZE/2, and a
--   speculative read of G_CACHE_SIZE/2 new words is issued to fill the upper
--   half. This provides seamless sequential read-ahead.
--
--   Writes are passed through to the master bus. If the write address falls
--   within the currently cached region, the buffer is updated (write-through)
--   with byte-enable granularity.
--
--   There is no external mechanism to invalidate the cache on request. In other
--   words, it is assumed that there is no other master writing to the client
--   at any time.
--
-- Bus interfaces:
--   s_* : Avalon-MM slave  (toward the client / upstream master)
--   m_* : Avalon-MM master (toward the memory / downstream slave)
--
-- Created by Michael Jørgensen in 2022 (mjoergen.github.io/HyperRAM).
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity avm_cache is
   generic (
      G_CACHE_SIZE   : natural;      -- Number of words in the buffer (must be even for sliding window)
      G_ADDRESS_SIZE : natural;      -- Address width in bits
      G_DATA_SIZE    : natural;      -- Data word width in bits
      G_BURST_BITS   : natural := 8  -- Number of bits in the *_burstcount_* ports
   );
   port (
      clk_i                 : in    std_logic;
      rst_i                 : in    std_logic;

      -- Avalon-MM slave interface (client-facing)
      s_avm_waitrequest_o   : out   std_logic;
      s_avm_write_i         : in    std_logic;
      s_avm_read_i          : in    std_logic;
      s_avm_address_i       : in    std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
      s_avm_writedata_i     : in    std_logic_vector(G_DATA_SIZE - 1 downto 0);
      s_avm_byteenable_i    : in    std_logic_vector(G_DATA_SIZE / 8 - 1 downto 0);
      s_avm_burstcount_i    : in    std_logic_vector(G_BURST_BITS - 1 downto 0);
      s_avm_readdata_o      : out   std_logic_vector(G_DATA_SIZE - 1 downto 0);
      s_avm_readdatavalid_o : out   std_logic;

      -- Avalon-MM master interface (memory-facing)
      m_avm_waitrequest_i   : in    std_logic;
      m_avm_write_o         : out   std_logic;
      m_avm_read_o          : out   std_logic;
      m_avm_address_o       : out   std_logic_vector(G_ADDRESS_SIZE - 1 downto 0);
      m_avm_writedata_o     : out   std_logic_vector(G_DATA_SIZE - 1 downto 0);
      m_avm_byteenable_o    : out   std_logic_vector(G_DATA_SIZE / 8 - 1 downto 0);
      m_avm_burstcount_o    : out   std_logic_vector(G_BURST_BITS - 1 downto 0);
      m_avm_readdata_i      : in    std_logic_vector(G_DATA_SIZE - 1 downto 0);
      m_avm_readdatavalid_i : in    std_logic
   );
end entity avm_cache;

architecture synthesis of avm_cache is

   type mem_t is array (0 to G_CACHE_SIZE-1) of std_logic_vector(G_DATA_SIZE-1 downto 0);
   type t_state is (IDLE_ST, READING_ST);

   ---------------------------------------------------------------------------
   -- Registers
   ---------------------------------------------------------------------------
   signal cache_data    : mem_t;                                        -- Buffer storage (one contiguous line of G_CACHE_SIZE words)
   signal cache_addr    : std_logic_vector(G_ADDRESS_SIZE-1 downto 0);  -- Base address of the currently cached region
   signal cache_count   : natural range 0 to G_CACHE_SIZE;              -- Number of valid words received so far (0 = empty, G_CACHE_SIZE = full)
   signal rd_burstcount : std_logic_vector(G_BURST_BITS-1 downto 0);    -- Remaining words to forward to the client for the current read burst.
   -- Loaded from s_avm_burstcount_i on a read miss.  Decremented each
   -- cycle a word is forwarded via s_avm_readdatavalid_o.  When a cache
   -- fill completes and rd_burstcount > 1 (accounting for the word
   -- forwarded in the same cycle), a continuation read is issued to
   -- fetch the next G_CACHE_SIZE words.

   signal state : t_state := IDLE_ST;

   ---------------------------------------------------------------------------
   -- Combinatorial signals
   ---------------------------------------------------------------------------
   signal cache_offset_s : std_logic_vector(G_ADDRESS_SIZE-1 downto 0); -- Offset of the requested address relative to cache_addr
   signal cache_rd_hit_s : std_logic;                                   -- Read hit indicator
   signal cache_wr_hit_s : std_logic;                                   -- Write hit indicator (for write-through update)
   signal cache_filled_s : std_logic;                                   -- Pulses high for one cycle when the last fill word arrives

begin

   -- Compile-Time Validation of G_CACHE_SIZE
   assert G_CACHE_SIZE >= 2 and G_CACHE_SIZE mod 2 = 0
      report "G_CACHE_SIZE must be even and >= 2"
      severity failure;
   assert real(G_CACHE_SIZE) < 2.0 ** G_ADDRESS_SIZE
      report "G_CACHE_SIZE must be < 2**G_ADDRESS_SIZE"
      severity failure;
   assert G_CACHE_SIZE < 2 ** G_BURST_BITS
      report "G_CACHE_SIZE must be < 2**G_BURST_BITS"
      severity failure;

   -- Compile-Time Validation of G_DATA_SIZE
   assert G_DATA_SIZE >= 8
      report "G_DATA_SIZE must be >= 8"
      severity failure;
   assert G_DATA_SIZE mod 8 = 0
      report "G_DATA_SIZE must be a multiple of 8"
      severity failure;


   ---------------------------------------------------------------------------
   -- cache_filled_s: Asserted for exactly one cycle when the final word of
   -- a cache fill burst is received from the master bus.
   ---------------------------------------------------------------------------
   cache_filled_s      <= '1' when state = READING_ST and m_avm_readdatavalid_i = '1' and cache_count = G_CACHE_SIZE - 1 else
                          '0';

   ---------------------------------------------------------------------------
   -- Read hit detection (single-word reads only; burst reads always miss):
   --   Case 1: The requested word is already stored in the buffer
   --           (offset < count, i.e. it was received in a previous cycle).
   --   Case 2: The requested word is arriving from memory this very cycle
   --           (offset = count and readdatavalid is asserted now).
   --           This is a same-cycle forwarding optimisation.
   ---------------------------------------------------------------------------
   cache_rd_hit_s      <= '1' when s_avm_read_i = '1' and unsigned(s_avm_burstcount_i) = 1 and unsigned(cache_offset_s) < cache_count else
                          '1' when s_avm_read_i = '1' and unsigned(s_avm_burstcount_i) = 1 and unsigned(cache_offset_s) = cache_count and
                                   cache_count < G_CACHE_SIZE and m_avm_readdatavalid_i = '1' else
                          '0';

   ---------------------------------------------------------------------------
   -- Write hit detection (single-word writes only):
   --   The write address falls within the currently valid cached region.
   --   Used to perform a write-through update of the buffer contents.
   ---------------------------------------------------------------------------
   cache_wr_hit_s      <= '1' when s_avm_write_i = '1' and unsigned(s_avm_burstcount_i) = 1 and unsigned(cache_offset_s) < cache_count else
                          '1' when s_avm_write_i = '1' and unsigned(s_avm_burstcount_i) = 1 and unsigned(cache_offset_s) = cache_count and
                                   cache_count < G_CACHE_SIZE and m_avm_readdatavalid_i = '1' else
                          '0';

   ---------------------------------------------------------------------------
   -- Slave waitrequest logic (active-high; deasserted = slave is ready):
   --   Condition 1: Cache fill just completed, no pending write, and no
   --                outstanding client burst words — ready to accept.
   --   Condition 2: Read hit during READING_ST with no pending write — serve
   --                directly from the buffer.
   --   Condition 3: IDLE_ST — pass through the master's waitrequest when a
   --                bus transaction (read or write) is active on the master.
   --   Condition 4: READING_ST with outstanding client burst (rd_burstcount
   --                > 0) — must wait until burst data is forwarded.
   --   Condition 5: Cache is full (all data received) — ready.
   --   Condition 6: Otherwise — wait (fill in progress, no hit).
   ---------------------------------------------------------------------------
   s_avm_waitrequest_o <= '0' when cache_filled_s = '1' and unsigned(rd_burstcount) = 0 else
                          '0' when cache_rd_hit_s = '1' and s_avm_write_i = '0' and unsigned(rd_burstcount) = 0 and state = READING_ST else
                          m_avm_waitrequest_i and (m_avm_write_o or m_avm_read_o) when state = IDLE_ST else
                          '1' when unsigned(rd_burstcount) /= 0 else
                          '0' when cache_count = G_CACHE_SIZE else
                          '1';

   ---------------------------------------------------------------------------
   -- Compute the offset of the requested address relative to the cache base.
   -- Unsigned modular subtraction with natural wrap-around on G_ADDRESS_SIZE bits.
   ---------------------------------------------------------------------------
   cache_offset_s      <= std_logic_vector(unsigned(s_avm_address_i) - unsigned(cache_addr));


   ---------------------------------------------------------------------------
   -- Main FSM
   ---------------------------------------------------------------------------
   p_fsm : process (clk_i)
      -----------------------------------------------------------------
      -- Procedure: Pass a write through to the master bus and perform
      -- an optional write-through update of cached data using
      -- byte-enables.  Sets state <= IDLE_ST.
      --
      -- Called from both IDLE_ST and the READING_ST fill-completion
      -- overlap section.
      -----------------------------------------------------------------

      procedure proc_write_passthrough is
      begin
         m_avm_write_o      <= '1';
         m_avm_read_o       <= '0';
         m_avm_address_o    <= s_avm_address_i;
         m_avm_writedata_o  <= s_avm_writedata_i;
         m_avm_byteenable_o <= s_avm_byteenable_i;
         m_avm_burstcount_o <= s_avm_burstcount_i;
         if cache_wr_hit_s = '1' then
            for i in 0 to G_DATA_SIZE / 8 - 1 loop
               if s_avm_byteenable_i(i) = '1' then
                  cache_data(to_integer(unsigned(cache_offset_s)))(8 * i + 7 downto 8 * i) <= s_avm_writedata_i(8 * i + 7 downto 8 * i);
               end if;
            end loop;
         end if;
         state <= IDLE_ST;
      end procedure proc_write_passthrough;

      -----------------------------------------------------------------
      -- Procedure: Initiate a full-line cache read from the client's
      -- requested address on a cache miss.  Resets cache_addr and
      -- cache_count, and enters READING_ST.
      --
      -- Called from both IDLE_ST and the READING_ST fill-completion
      -- overlap section.
      -----------------------------------------------------------------

      procedure proc_read_miss is
      begin
         m_avm_write_o      <= '0';
         m_avm_read_o       <= '1';
         m_avm_byteenable_o <= (others => '1');
         m_avm_address_o    <= s_avm_address_i;
         m_avm_burstcount_o <= std_logic_vector(to_unsigned(G_CACHE_SIZE, G_BURST_BITS));
         rd_burstcount      <= s_avm_burstcount_i;
         cache_count        <= 0;
         cache_addr         <= s_avm_address_i;
         state              <= READING_ST;
      end procedure proc_read_miss;

   begin
      if rising_edge(clk_i) then
         if rst_i = '0' then
            assert not (s_avm_write_i = '1' and s_avm_read_i = '1')
               report "Simultaneous read and write not supported"
               severity failure;
         end if;

         -- Default: clear slave read outputs every cycle (overridden below on hit/valid)
         s_avm_readdata_o      <= (others => '0');
         s_avm_readdatavalid_o <= '0';

         -- Default: deassert master bus request once accepted by the slave
         if m_avm_waitrequest_i = '0' then
            m_avm_write_o      <= '0';
            m_avm_read_o       <= '0';
         end if;

         case state is

            ------------------------------------------------------------------
            -- IDLE_ST: No fill in progress. Accept new read or write requests.
            ------------------------------------------------------------------
            when IDLE_ST =>
               -----------------------------------------------------------------
               -- Write handling: pass through to master bus, with optional
               -- write-through update of cached data using byte-enables.
               -----------------------------------------------------------------
               if s_avm_write_i = '1' and s_avm_waitrequest_o = '0' then
                  proc_write_passthrough;
               end if;

               -----------------------------------------------------------------
               -- Read handling
               -----------------------------------------------------------------
               if s_avm_read_i = '1' and s_avm_waitrequest_o = '0' then
                  if cache_rd_hit_s = '1' then
                     -- Cache hit: return data from the buffer immediately
                     s_avm_readdata_o      <= cache_data(to_integer(unsigned(cache_offset_s)));
                     s_avm_readdatavalid_o <= '1';

                     --------------------------------------------------------
                     -- Read-ahead trigger (threshold check):
                     --
                     -- When the client reads a word at or past the midpoint
                     -- (offset >= G_CACHE_SIZE/2 - 1), slide the buffer
                     -- window forward.
                     --
                     -- A threshold (>=) is used instead of an equality (=)
                     -- to handle the case where the client skips past the
                     -- exact midpoint.  This can happen when:
                     --   (a) A speculative fill is in progress (READING_ST)
                     --       and the client issues hits that advance past the
                     --       midpoint before the fill completes.  Since no
                     --       slide fires during READING_ST, the first read
                     --       hit after returning to IDLE_ST may already be
                     --       beyond the midpoint.
                     --   (b) The fill-completion overlap path serves a read
                     --       hit at or past the midpoint but intentionally
                     --       does not slide (see NOTE below).  On the next
                     --       cycle in IDLE_ST, the client's offset is past
                     --       the midpoint.
                     --
                     -- The threshold is safe because cache_rd_hit_s
                     -- guarantees cache_offset_s is in [0, cache_count - 1],
                     -- i.e. within the valid buffer range.  The speculative
                     -- read address and burstcount are independent of the
                     -- triggering offset — they always fill the upper half
                     -- of the new window.
                     --
                     -- Trade-off: when the slide fires late (offset close to
                     -- G_CACHE_SIZE - 1), the prefetched data covers less
                     -- look-ahead.  This degrades gracefully — the client
                     -- may stall briefly waiting for the speculative fill —
                     -- but is always better than missing the slide entirely.
                     --
                     -- NOTE: The sliding-window logic is intentionally NOT
                     -- duplicated in the READING_ST fill-completion read-hit
                     -- path.  At fill completion the last word has just been
                     -- received via m_avm_readdata_i but the corresponding
                     -- cache_data entry has not yet been committed (VHDL
                     -- deferred signal update).  A slide at that instant
                     -- would copy the stale pre-fill value of
                     -- cache_data(G_CACHE_SIZE-1) into the lower half,
                     -- corrupting the buffer.  The threshold check here
                     -- ensures the slide fires on the very next cycle
                     -- instead, once the buffer is fully committed.
                     --
                     -- HACK: We need the extra condition on
                     -- "s_avm_byteenable_i(G_DATA_SIZE / 8 - 1) = '1'"
                     -- because we should only slide the window when the *entire*
                     -- current word has been read. We are here *assuming* that
                     -- reads are byte-sized and sequential (starting from LSB
                     -- to MSB). The extra guard therefore assumes when
                     -- reading the MSB that all the other bytes have been (or
                     -- are being) read. Without the guard, single byte reads
                     -- would slide the window before the entire word has been
                     -- read.
                     --------------------------------------------------------
                     if unsigned(cache_offset_s) >= G_CACHE_SIZE / 2 - 1
                        and s_avm_byteenable_i(G_DATA_SIZE / 8 - 1) = '1' then
                        -- Slide the window: shift the upper half into the lower half
                        cache_data(0 to G_CACHE_SIZE / 2 - 1) <= cache_data(G_CACHE_SIZE / 2 to G_CACHE_SIZE - 1);
                        -- Advance the base address by half the buffer size
                        cache_addr                            <= std_logic_vector(unsigned(cache_addr) + G_CACHE_SIZE / 2);
                        -- Half the data is preserved; the upper half will be filled
                        cache_count                           <= G_CACHE_SIZE / 2;
                        -- Issue speculative read for the next G_CACHE_SIZE/2 words
                        m_avm_write_o                         <= '0';
                        m_avm_read_o                          <= '1';
                        m_avm_byteenable_o                    <= (others => '1');
                        m_avm_address_o                       <= std_logic_vector(unsigned(cache_addr) + G_CACHE_SIZE);
                        m_avm_burstcount_o                    <= std_logic_vector(to_unsigned(G_CACHE_SIZE / 2, G_BURST_BITS));
                        -- Speculative prefetch: no client burst to forward data to
                        rd_burstcount                         <= (others => '0');
                        state                                 <= READING_ST;
                     end if;
                  else
                     -- Cache miss: initiate a full-line read from the requested address
                     proc_read_miss;
                  end if;
               end if;

            ------------------------------------------------------------------
            -- READING_ST: Cache fill is in progress.
            --   - Incoming master data is stored into cache_data.
            --   - If a client burst is pending (rd_burstcount > 0), data is
            --     forwarded to the slave as it arrives.
            --   - On fill completion, new slave requests can be accepted in
            --     the same cycle (overlapping transaction handling).
            --   - Read hits against already-filled entries are served even
            --     while more data is still arriving.
            ------------------------------------------------------------------
            when READING_ST =>
               if m_avm_readdatavalid_i = '1' then
                  -- Store the incoming word in the buffer
                  cache_data(cache_count) <= m_avm_readdata_i;

                  -- Forward to client if there are outstanding burst words
                  if unsigned(rd_burstcount) /= 0 then
                     s_avm_readdata_o      <= m_avm_readdata_i;
                     s_avm_readdatavalid_o <= '1';
                     rd_burstcount         <= std_logic_vector(unsigned(rd_burstcount) - 1);
                  end if;

                  if cache_count >= G_CACHE_SIZE - 1 then
                     -----------------------------------------------------------
                     -- Cache fill complete: mark buffer as full and return to
                     -- IDLE.  Then check for overlapping requests that can be
                     -- accepted in this same cycle.
                     --
                     -- Priority is explicit via if/elsif ordering (highest
                     -- priority first).  The default assignments above this
                     -- chain (cache_count, state) are overridden by whichever
                     -- branch fires.
                     -----------------------------------------------------------
                     cache_count <= G_CACHE_SIZE;
                     state       <= IDLE_ST;

                     if unsigned(rd_burstcount) > 1 then
                        ---------------------------------------------------------
                        -- (Highest priority) Continuation read: the client's
                        -- burst spans more than G_CACHE_SIZE words and data is
                        -- still owed.  Fetch the next G_CACHE_SIZE words from
                        -- the next sequential address.  The cache base advances
                        -- so that subsequent continuation reads chain correctly.
                        -- rd_burstcount is not modified here; it continues to
                        -- be decremented by the forwarding logic as new fill
                        -- data arrives.
                        --
                        -- The threshold is > 1 (not > 0) because the forwarding
                        -- block earlier in this cycle already scheduled a
                        -- decrement.  An old value of 2 means one word was just
                        -- forwarded and one still remains — requiring more data.
                        --------------------------------------------------
                        m_avm_write_o      <= '0';
                        m_avm_read_o       <= '1';
                        m_avm_byteenable_o <= (others => '1');
                        m_avm_address_o    <= std_logic_vector(unsigned(cache_addr) + G_CACHE_SIZE);
                        m_avm_burstcount_o <= std_logic_vector(to_unsigned(G_CACHE_SIZE, G_BURST_BITS));
                        cache_count        <= 0;
                        cache_addr         <= std_logic_vector(unsigned(cache_addr) + G_CACHE_SIZE);
                        state              <= READING_ST;
                     elsif s_avm_read_i = '1' and s_avm_waitrequest_o = '0' then
                        ---------------------------------------------------------
                        -- (Medium priority) Accept a new read immediately.
                        -- No sliding-window check here; see the NOTE in the
                        -- IDLE_ST read-ahead trigger block for the rationale.
                        -- The >= threshold there guarantees the slide fires on
                        -- the very next cycle if the offset is past the midpoint.
                        ---------------------------------------------------------
                        if cache_rd_hit_s = '1' then
                           -- Hit: serve from buffer
                           s_avm_readdata_o      <= cache_data(to_integer(unsigned(cache_offset_s)));
                           s_avm_readdatavalid_o <= '1';
                        else
                           -- Miss: initiate new full-line read
                           proc_read_miss;
                        end if;
                     elsif s_avm_write_i = '1' and s_avm_waitrequest_o = '0' then
                        ---------------------------------------------------------
                        -- (Lowest priority) Accept a new write immediately.
                        ---------------------------------------------------------
                        proc_write_passthrough;
                     end if;
                  else
                     -- Fill still in progress: advance the word counter
                     cache_count <= cache_count + 1;
                  end if;
               end if;

               -----------------------------------------------------------------
               -- Serve read hits during the fill, even before fill completion.
               -- If the hit targets the word being received this very cycle
               -- (offset = count), forward directly from the master bus since
               -- cache_data hasn't been updated yet in this delta cycle.
               -----------------------------------------------------------------
               if cache_rd_hit_s = '1' and s_avm_waitrequest_o = '0' then
                  s_avm_readdata_o      <= cache_data(to_integer(unsigned(cache_offset_s)));
                  s_avm_readdatavalid_o <= '1';

                  if unsigned(cache_offset_s) = cache_count then
                     -- Same-cycle forwarding: data not yet in cache_data
                     s_avm_readdata_o <= m_avm_readdata_i;
                  end if;
               end if;

            when others =>
               null;

         end case;

         -----------------------------------------------------------------
         -- Synchronous reset: clear all outputs and return to IDLE
         -----------------------------------------------------------------
         if rst_i = '1' then
            s_avm_readdatavalid_o <= '0';
            m_avm_write_o         <= '0';
            m_avm_read_o          <= '0';
            m_avm_address_o       <= (others => '0');
            m_avm_writedata_o     <= (others => '0');
            m_avm_byteenable_o    <= (others => '1');
            m_avm_burstcount_o    <= (others => '0');
            cache_count           <= 0;
            cache_addr            <= (others => '0');
            rd_burstcount         <= (others => '0');
            state                 <= IDLE_ST;
         end if;
      end if;
   end process p_fsm;

end architecture synthesis;

