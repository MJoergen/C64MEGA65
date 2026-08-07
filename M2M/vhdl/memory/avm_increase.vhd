--------------------------------------------------------------------------------
-- Description: Up-sizing bridge for the Avalon Memory-Mapped (Avalon-MM) protocol.
--
--   * Slave  side : narrow data path (G_SLAVE_DATA_SIZE bits)
--   * Master side : wide   data path (G_MASTER_DATA_SIZE bits)
--
-- Constraints (checked by assertions):
--   * G_MASTER_DATA_SIZE = C_RATIO * G_SLAVE_DATA_SIZE
--   * C_RATIO must be a power of two and > 1
--   * The total address space (size * 2**address) must match on both sides
--
-- Bursts:
--   * Up to (2**G_BURST_SIZE - 1) slave beats are translated into the
--     minimum number of master beats required to cover the requested range.
--   * Misaligned start addresses are supported; the first master beat may
--     contain fewer than C_RATIO populated sub-slots.
--
-- Write burst handling:
--   * The M2M SDRAM controller (and potentially other strict slaves) requires
--     gap-free write bursts
--   * To guarantee this, slave-side write data is first packed into complete
--     wide master beats and stored in an internal axi_fifo_small.
--   * The master write burst is issued only after the complete slave write
--     burst has been accepted and packed.
--   * During the master write burst, data is streamed from the FIFO without
--     inserting bubbles between accepted beats. If m_avm_waitrequest_i stalls, the
--     current FIFO word remains presented until accepted.
--
-- Limitations:
--   * Reads and writes may not be issued simultaneously (asserted).
--   * Both interfaces share clk_i / rst_i (no CDC).
--   * The internal read FIFO depth is 2**G_BURST_SIZE master words
--     (sized to absorb the worst-case master read burst).
--   * The internal write FIFO depth is also 2**G_BURST_SIZE master words
--     (sized to buffer the complete packed write burst before master emission).
--
-- SPDX-License-Identifier: MIT
--------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity avm_increase is
  generic (
    G_SLAVE_ADDRESS_SIZE  : positive;
    G_SLAVE_DATA_SIZE     : positive;
    G_MASTER_ADDRESS_SIZE : positive;
    G_MASTER_DATA_SIZE    : positive; -- Must be an integer multiple of G_SLAVE_DATA_SIZE
    G_BURST_SIZE          : positive := 8
  );
  port (
    clk_i                 : in    std_logic;
    rst_i                 : in    std_logic;

    -- Slave port (faces upstream master) — narrow side
    s_avm_waitrequest_o   : out   std_logic;
    s_avm_write_i         : in    std_logic;
    s_avm_read_i          : in    std_logic;
    s_avm_address_i       : in    std_logic_vector(G_SLAVE_ADDRESS_SIZE - 1 downto 0);
    s_avm_writedata_i     : in    std_logic_vector(G_SLAVE_DATA_SIZE - 1 downto 0);
    s_avm_byteenable_i    : in    std_logic_vector(G_SLAVE_DATA_SIZE / 8 - 1 downto 0);
    s_avm_burstcount_i    : in    std_logic_vector(G_BURST_SIZE - 1 downto 0);
    s_avm_readdata_o      : out   std_logic_vector(G_SLAVE_DATA_SIZE - 1 downto 0);
    s_avm_readdatavalid_o : out   std_logic;

    -- Master port (faces downstream slave) — wide side
    m_avm_waitrequest_i   : in    std_logic;
    m_avm_write_o         : out   std_logic;
    m_avm_read_o          : out   std_logic;
    m_avm_address_o       : out   std_logic_vector(G_MASTER_ADDRESS_SIZE - 1 downto 0);
    m_avm_writedata_o     : out   std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
    m_avm_byteenable_o    : out   std_logic_vector(G_MASTER_DATA_SIZE / 8 - 1 downto 0);
    m_avm_burstcount_o    : out   std_logic_vector(G_BURST_SIZE - 1 downto 0);
    m_avm_readdata_i      : in    std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
    m_avm_readdatavalid_i : in    std_logic
  );
end entity avm_increase;

architecture rtl of avm_increase is

  -- 2**G_BURST_SIZE — the smallest value that is NOT a representable
  -- Avalon-MM burstcount. Used as FIFO depth to cover the worst-case burst.
  constant C_BURST_LIMIT : positive            := 2 ** G_BURST_SIZE;

  -- Number of slave words per master word.
  constant C_RATIO : positive                  := G_MASTER_DATA_SIZE / G_SLAVE_DATA_SIZE;

  -- log2(C_RATIO); also the number of slave-address LSBs selecting the
  -- sub-slot within a master word.
  constant C_ADDR_SHIFT : natural              := G_SLAVE_ADDRESS_SIZE -
                                                  G_MASTER_ADDRESS_SIZE;

  constant C_SLAVE_BYTEENABLE_SIZE  : positive := G_SLAVE_DATA_SIZE / 8;
  constant C_MASTER_BYTEENABLE_SIZE : positive := G_MASTER_DATA_SIZE / 8;

  -- The write FIFO stores one packed master beat:
  --
  --   upper bits : m_avm_writedata_o
  --   lower bits : m_avm_byteenable_o
  --
  constant C_WRITE_FIFO_DATA_SIZE : positive   := G_MASTER_DATA_SIZE + C_MASTER_BYTEENABLE_SIZE;

  type     state_type is (
    IDLE_ST,            -- No transaction in flight; accepting new read or write.
    WRITING_ST,         -- Accepting and packing slave write beats into write FIFO.
    WAIT_WRITE_FIFO_ST, -- Waiting for first packed write FIFO word to appear.
    EMIT_WRITE_ST,      -- Streaming packed write FIFO contents as master write burst.
    READING_ST          -- Master read issued; streaming response beats from FIFO.
  );

  signal   state : state_type                  := IDLE_ST;

  -- Current sub-slot index within a master word.
  signal   offset : std_logic_vector(C_ADDR_SHIFT - 1 downto 0);

  -- Remaining slave beats in the current write/read transaction.
  signal   s_avm_burstcount : std_logic_vector(G_BURST_SIZE - 1 downto 0);

  -- Remaining accepted master write beats in the current emitted master burst.
  signal   m_avm_write_remaining : std_logic_vector(G_BURST_SIZE - 1 downto 0);

  -- Registered master command metadata. For writes, these are held stable while
  -- the buffered write data is emitted from the write FIFO.
  signal   m_avm_read       : std_logic;
  signal   m_avm_address    : std_logic_vector(G_MASTER_ADDRESS_SIZE - 1 downto 0);
  signal   m_avm_burstcount : std_logic_vector(G_BURST_SIZE - 1 downto 0);

  -- Accumulates one packed master write beat while slave write beats are being
  -- accepted. Byte-enables are cleared between packed master words so partial
  -- leading/trailing master words are represented correctly.
  signal   write_pack_data       : std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
  signal   write_pack_byteenable : std_logic_vector(C_MASTER_BYTEENABLE_SIZE - 1 downto 0);

  -- Read FIFO signals.
  signal   rd_fifo_s_ready : std_logic;
  signal   rd_fifo_m_ready : std_logic;
  signal   rd_fifo_m_valid : std_logic;
  signal   rd_fifo_m_data  : std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);

  -- Write FIFO signals.
  signal   wr_fifo_s_ready : std_logic;
  signal   wr_fifo_s_valid : std_logic;
  signal   wr_fifo_s_data  : std_logic_vector(C_WRITE_FIFO_DATA_SIZE - 1 downto 0);
  signal   wr_fifo_m_ready : std_logic;
  signal   wr_fifo_m_valid : std_logic;
  signal   wr_fifo_m_data  : std_logic_vector(C_WRITE_FIFO_DATA_SIZE - 1 downto 0);

  -- High when the slave start address points at the last sub-slot of a master
  -- word, i.e. the first accepted slave beat completes a packed master beat.
  signal   s_last_subslot : std_logic;

  -- Local alias: slave address with the sub-slot bits removed.
  alias    s_avm_master_address : std_logic_vector(G_MASTER_ADDRESS_SIZE - 1 downto 0)
                                is s_avm_address_i(G_SLAVE_ADDRESS_SIZE - 1 downto C_ADDR_SHIFT);

begin

  ------------------------------
  -- Compile-time consistency checks
  ------------------------------

  assert C_RATIO > 1
    report "C_RATIO must be greater than one (G_MASTER_DATA_SIZE > G_SLAVE_DATA_SIZE required)"
    severity failure;

  assert C_ADDR_SHIFT > 0
    report "C_ADDR_SHIFT must be > 0 (G_SLAVE_ADDRESS_SIZE > G_MASTER_ADDRESS_SIZE required)"
    severity failure;

  assert G_MASTER_DATA_SIZE = C_RATIO * G_SLAVE_DATA_SIZE
    report "G_MASTER_DATA_SIZE must be an integer multiple of G_SLAVE_DATA_SIZE"
    severity failure;

  assert G_MASTER_DATA_SIZE * (2 ** G_MASTER_ADDRESS_SIZE) =
         G_SLAVE_DATA_SIZE * (2 ** G_SLAVE_ADDRESS_SIZE)
    report "Master and slave address spaces must describe the same total storage size"
    severity failure;

  assert C_RATIO = 2 ** C_ADDR_SHIFT
    report "Width ratio must be power-of-two"
    severity failure;

  s_last_subslot        <= and (s_avm_address_i(C_ADDR_SHIFT - 1 downto 0));

  --------------------------------------------------------------------
  -- Master output mapping
  --------------------------------------------------------------------

  m_avm_read_o          <= m_avm_read;
  m_avm_address_o       <= m_avm_address;
  m_avm_burstcount_o    <= m_avm_burstcount;

  -- The master write strobe is driven directly from the write FIFO valid while
  -- EMIT_WRITE_ST is active. Because the complete write burst has already been
  -- packed into the FIFO before EMIT_WRITE_ST starts, the FIFO should not
  -- insert bubbles between accepted master write beats.
  m_avm_write_o         <= wr_fifo_m_valid when state = EMIT_WRITE_ST else
                           '0';

  m_avm_writedata_o     <= wr_fifo_m_data(C_WRITE_FIFO_DATA_SIZE - 1 downto
                                          C_MASTER_BYTEENABLE_SIZE);

  m_avm_byteenable_o    <= (others => '1') when m_avm_read = '1' else
                           wr_fifo_m_data(C_MASTER_BYTEENABLE_SIZE - 1 downto 0)
                           when state = EMIT_WRITE_ST else
                           (others => '0');


  -- Slave-side throttling:
  --
  --   * IDLE_ST            : accept the first beat of a new read/write transaction.
  --   * WRITING_ST         : continue accepting the current slave-side write burst.
  --   * WAIT_WRITE_FIFO_ST : wait until the first packed write FIFO word is visible.
  --   * EMIT_WRITE_ST      : do not accept a new transaction while the buffered
  --                          master write burst is being emitted.
  --   * READING_ST         : do not accept a new transaction while read responses
  --                          are being returned to the slave.
  s_avm_waitrequest_o   <= '0' when state = IDLE_ST or state = WRITING_ST else
                           '1';

  --------------------------------------------------------------------
  -- Sequential control
  --------------------------------------------------------------------

  fsm_proc : process (clk_i)
    ----------------------------------------------------------------------
    -- calc_m_avm_burstcount
    --
    -- Number of master beats needed to cover [address, address + burstcount).
    --
    --   master_beats = floor((address + burstcount - 1) / C_RATIO)
    --                - floor(address                 / C_RATIO) + 1
    --
    -- The two leading zero-bits guarantee no overflow during the intermediate
    -- addition.
    ----------------------------------------------------------------------

    pure function calc_m_avm_burstcount (
      address    : std_logic_vector;
      burstcount : std_logic_vector
    ) return std_logic_vector is
      variable res_v : unsigned(G_SLAVE_ADDRESS_SIZE + 1 downto 0);
    begin
      res_v := (("00" & unsigned(address)) + unsigned(burstcount) - 1) / C_RATIO -
               (("00" & unsigned(address)) / C_RATIO) + 1;

      assert res_v(res_v'high downto G_BURST_SIZE) = 0
        report "avm_increase: calc_m_avm_burstcount overflow; G_BURST_SIZE too small"
        severity failure;

      return std_logic_vector(res_v(G_BURST_SIZE - 1 downto 0));
    end function calc_m_avm_burstcount;

    ----------------------------------------------------------------------
    -- pack_write_slot
    --
    -- Inserts the current narrow slave write beat into the selected sub-slot
    -- of a wide master write word. The caller owns clearing the packing
    -- buffers between master words.
    ----------------------------------------------------------------------

    procedure pack_write_slot (
      pos                   : natural range 0 to C_RATIO - 1;
      variable data_v       : inout std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
      variable byteenable_v : inout std_logic_vector(C_MASTER_BYTEENABLE_SIZE - 1 downto 0)
    ) is
    begin
      data_v(
      G_SLAVE_DATA_SIZE * (pos + 1) - 1 downto
      G_SLAVE_DATA_SIZE * pos
      ) := s_avm_writedata_i;

      byteenable_v(
      C_SLAVE_BYTEENABLE_SIZE * (pos + 1) - 1 downto
      C_SLAVE_BYTEENABLE_SIZE * pos
      ) := s_avm_byteenable_i;
    end procedure pack_write_slot;

    ----------------------------------------------------------------------
    -- push_write_word
    --
    -- Pushes one fully packed, or intentionally partial, master write word
    -- into the write FIFO.
    --
    -- Partial leading/trailing master words are represented by zero byte-enable
    -- bits in unused sub-slots.
    ----------------------------------------------------------------------

    procedure push_write_word (
      variable data_v       : in std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
      variable byteenable_v : in std_logic_vector(C_MASTER_BYTEENABLE_SIZE - 1 downto 0)
    ) is
    begin
      assert wr_fifo_s_ready = '1' or rst_i = '1'
        report "Write FIFO overflow: packed master write word could not be buffered"
        severity failure;

      wr_fifo_s_valid <= '1';
      wr_fifo_s_data  <= data_v & byteenable_v;
    end procedure push_write_word;

    variable pack_data_v       : std_logic_vector(G_MASTER_DATA_SIZE - 1 downto 0);
    variable pack_byteenable_v : std_logic_vector(C_MASTER_BYTEENABLE_SIZE - 1 downto 0);
    variable master_burst_v    : std_logic_vector(G_BURST_SIZE - 1 downto 0);
  begin
    if rising_edge(clk_i) then
      -- Default: no packed write word is pushed this cycle unless explicitly
      -- requested by the write-packing state machine.
      wr_fifo_s_valid <= '0';
      wr_fifo_s_data  <= (others => '0');

      -- A read command remains asserted until it is accepted by the downstream
      -- slave. Write commands are generated from the write FIFO valid signal.
      if m_avm_waitrequest_i = '0' then
        m_avm_read <= '0';
      end if;

      case state is

        --------------------------------------------------------------------
        -- IDLE_ST
        --------------------------------------------------------------------

        when IDLE_ST =>
          if s_avm_write_i = '1' and s_avm_waitrequest_o = '0' then
            assert unsigned(s_avm_burstcount_i) /= 0 or rst_i = '1'
              report "Avalon-MM: write burstcount must be >= 1"
              severity failure;

            assert s_avm_read_i = '0' or rst_i = '1'
              report "Simultaneous read+write not allowed"
              severity failure;

            assert m_avm_read = '0' or rst_i = '1'
              report "Internal error: read command still pending when accepting write"
              severity failure;

            master_burst_v        := calc_m_avm_burstcount(s_avm_address_i, s_avm_burstcount_i);

            m_avm_address         <= s_avm_master_address;
            m_avm_burstcount      <= master_burst_v;
            m_avm_write_remaining <= master_burst_v;

            pack_data_v           := (others => '0');
            pack_byteenable_v     := (others => '0');

            pack_write_slot(
                            to_integer(unsigned(s_avm_address_i(C_ADDR_SHIFT - 1 downto 0))),
                            pack_data_v,
                            pack_byteenable_v
                          );

            -- Push immediately if the first slave beat completes a master word
            -- or if the slave burst contains only this single beat.
            if unsigned(s_avm_burstcount_i) = 1 or s_last_subslot = '1' then
              push_write_word(pack_data_v, pack_byteenable_v);

              write_pack_data       <= (others => '0');
              write_pack_byteenable <= (others => '0');
            else
              write_pack_data       <= pack_data_v;
              write_pack_byteenable <= pack_byteenable_v;
            end if;

            if unsigned(s_avm_burstcount_i) = 1 then
              -- The complete write burst has been packed, but the write FIFO
              -- has two clocks of output latency. Wait until wr_fifo_m_valid is
              -- asserted before starting the Avalon-MM master write burst.
              state <= WAIT_WRITE_FIFO_ST;
            else
              s_avm_burstcount <= std_logic_vector(unsigned(s_avm_burstcount_i) - 1);
              offset           <= std_logic_vector(unsigned(s_avm_address_i(C_ADDR_SHIFT - 1 downto 0)) + 1);
              state            <= WRITING_ST;
            end if;
          elsif s_avm_read_i = '1' and s_avm_waitrequest_o = '0' then
            assert unsigned(s_avm_burstcount_i) /= 0 or rst_i = '1'
              report "Avalon-MM: read burstcount must be >= 1"
              severity failure;

            assert s_avm_write_i = '0' or rst_i = '1'
              report "Simultaneous read+write not allowed"
              severity failure;

            m_avm_read       <= '1';
            m_avm_address    <= s_avm_master_address;
            m_avm_burstcount <= calc_m_avm_burstcount(s_avm_address_i, s_avm_burstcount_i);

            s_avm_burstcount <= s_avm_burstcount_i;
            offset           <= s_avm_address_i(C_ADDR_SHIFT - 1 downto 0);
            state            <= READING_ST;
          end if;

        --------------------------------------------------------------------
        -- WRITING_ST
        --
        -- Accept the remaining slave write beats and pack them into wide
        -- master words. No master write command is emitted in this state.
        -- This is what makes the later master burst capable of being emitted
        -- without inter-beat bubbles.
        --------------------------------------------------------------------

        when WRITING_ST =>
          assert s_avm_read_i = '0' or rst_i = '1'
            report "Read not allowed during burst write"
            severity failure;

          assert unsigned(s_avm_burstcount) > 0 or rst_i = '1'
            report "Internal error: WRITING_ST: s_avm_burstcount must be greater than zero"
            severity failure;

          if s_avm_write_i = '1' and s_avm_waitrequest_o = '0' then
            pack_data_v       := write_pack_data;
            pack_byteenable_v := write_pack_byteenable;

            pack_write_slot(
                            to_integer(unsigned(offset)),
                            pack_data_v,
                            pack_byteenable_v
                          );

            -- A master word is complete either when the last sub-slot has just
            -- been filled or when the slave burst ends mid-master-word.
            if unsigned(offset) = C_RATIO - 1 or unsigned(s_avm_burstcount) = 1 then
              push_write_word(pack_data_v, pack_byteenable_v);

              write_pack_data       <= (others => '0');
              write_pack_byteenable <= (others => '0');
            else
              write_pack_data       <= pack_data_v;
              write_pack_byteenable <= pack_byteenable_v;
            end if;

            s_avm_burstcount <= std_logic_vector(unsigned(s_avm_burstcount) - 1);
            offset           <= std_logic_vector(unsigned(offset) + 1);

            if unsigned(s_avm_burstcount) = 1 then
              -- The complete slave write burst is now packed into the write
              -- FIFO. Do not enter EMIT_WRITE_ST immediately, because
              -- axi_fifo_small has two clocks of latency from s_valid_i to
              -- m_valid_o.
              --
              -- WAIT_WRITE_FIFO_ST prevents the Avalon-MM master write burst
              -- from starting until the first packed master word is actually
              -- available at the FIFO output.
              state <= WAIT_WRITE_FIFO_ST;
            end if;
          end if;


        --------------------------------------------------------------------
        -- WAIT_WRITE_FIFO_ST
        --
        -- The complete slave-side write burst has been packed into the write
        -- FIFO, but axi_fifo_small has registered output latency. Wait here until
        -- the first FIFO output word is valid.
        --
        -- Avalon-MM write burst timing starts only when m_avm_write_o is asserted.
        -- Therefore it is legal and intentional that m_avm_write_o remains low in
        -- this state.
        --------------------------------------------------------------------

        when WAIT_WRITE_FIFO_ST =>
          assert unsigned(m_avm_write_remaining) /= 0 or rst_i = '1'
            report "Internal error: WAIT_WRITE_FIFO_ST entered with no master write beats remaining"
            severity failure;

          if wr_fifo_m_valid = '1' then
            state <= EMIT_WRITE_ST;
          end if;


        --------------------------------------------------------------------
        -- EMIT_WRITE_ST
        --
        -- Stream the already-buffered packed master words to the downstream
        -- Avalon-MM slave. Because the complete burst has been buffered before
        -- entering this state, wr_fifo_m_valid is expected to remain asserted
        -- until the last beat has been accepted.
        --------------------------------------------------------------------

        when EMIT_WRITE_ST =>
          assert wr_fifo_m_valid = '1' or unsigned(m_avm_write_remaining) = 0 or rst_i = '1'
            report "Write FIFO underflow: master write burst would contain a bubble"
            severity failure;

          if wr_fifo_m_valid = '1' and m_avm_waitrequest_i = '0' then
            if unsigned(m_avm_write_remaining) = 1 then
              m_avm_write_remaining <= (others => '0');
              state                 <= IDLE_ST;
            else
              m_avm_write_remaining <= std_logic_vector(unsigned(m_avm_write_remaining) - 1);
            end if;
          end if;

        --------------------------------------------------------------------
        -- READING_ST
        --------------------------------------------------------------------

        when READING_ST =>
          if rd_fifo_m_valid = '1' then
            s_avm_burstcount <= std_logic_vector(unsigned(s_avm_burstcount) - 1);
            offset           <= std_logic_vector(unsigned(offset) + 1);

            -- On the last slave read beat, return to IDLE_ST in the same cycle
            -- that s_avm_readdatavalid_o is asserted.
            if unsigned(s_avm_burstcount) = 1 then
              state <= IDLE_ST;
            end if;
          end if;

      end case;

      if rst_i = '1' then
        m_avm_read            <= '0';
        m_avm_address         <= (others => '0');
        m_avm_burstcount      <= (others => '0');
        m_avm_write_remaining <= (others => '0');

        state                 <= IDLE_ST;
        offset                <= (others => '0');
        s_avm_burstcount      <= (others => '0');

        write_pack_data       <= (others => '0');
        write_pack_byteenable <= (others => '0');

        wr_fifo_s_valid       <= '0';
        wr_fifo_s_data        <= (others => '0');
      end if;
    end if;
  end process fsm_proc;

  --------------------------------------------------------------------
  -- Read response handling
  --------------------------------------------------------------------

  -- s_avm_readdata_o is valid only while s_avm_readdatavalid_o = '1'. Between bursts
  -- it may present a slice of stale FIFO data, which is harmless because the
  -- upstream slave-side master is not allowed to sample it without valid.
  s_avm_readdata_o      <= rd_fifo_m_data(
                                          G_SLAVE_DATA_SIZE * (to_integer(unsigned(offset)) + 1) - 1 downto
                                          G_SLAVE_DATA_SIZE * to_integer(unsigned(offset))
                                        );

  s_avm_readdatavalid_o <= rd_fifo_m_valid when state = READING_ST else
                           '0';

  -- Read FIFO pop strategy:
  --
  --   * READING_ST : pop after the last sub-slot of the current master word has
  --                  been forwarded to the slave.
  --   * IDLE_ST    : drain any residual partial master read word left by the
  --                  previous misaligned read burst before a new transaction.
  --   * write states: not applicable.
  rd_fifo_m_ready       <= '1' when unsigned(offset) = C_RATIO - 1 or state = IDLE_ST else
                           '0';

  -- Write FIFO pop strategy:
  --
  -- Pop exactly when the downstream Avalon-MM slave accepts the current master
  -- write beat. If m_waitrequest_i is high, the FIFO output remains stable and
  -- m_write_o remains asserted.
  wr_fifo_m_ready       <= '1' when state = EMIT_WRITE_ST and
                                    wr_fifo_m_valid = '1' and
                                    m_avm_waitrequest_i = '0' else
                           '0';

  --------------------------------------------------------------------
  -- FIFO safety checks
  --------------------------------------------------------------------

  read_fifo_overflow_check_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      assert m_avm_readdatavalid_i = '0' or rd_fifo_s_ready = '1' or rst_i = '1'
        report "Read FIFO overflow: downstream slave returned data while read FIFO not ready"
        severity failure;
    end if;
  end process read_fifo_overflow_check_proc;

  write_fifo_bubble_check_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if state = EMIT_WRITE_ST and unsigned(m_avm_write_remaining) /= 0 then
        assert wr_fifo_m_valid = '1' or rst_i = '1'
          report "Write FIFO underflow: Avalon-MM write burst would not be consecutive"
          severity failure;
      end if;
    end if;
  end process write_fifo_bubble_check_proc;

  --------------------------------------------------------------------
  -- Instantiate read FIFO
  --------------------------------------------------------------------

  read_axi_fifo_small_inst : entity work.axi_fifo_small
    generic map (
      G_RAM_DEPTH => C_BURST_LIMIT,
      G_RAM_WIDTH => G_MASTER_DATA_SIZE
    )
    port map (
      clk_i     => clk_i,
      rst_i     => rst_i,
      s_ready_o => rd_fifo_s_ready,
      s_valid_i => m_avm_readdatavalid_i,
      s_data_i  => m_avm_readdata_i,
      m_ready_i => rd_fifo_m_ready,
      m_valid_o => rd_fifo_m_valid,
      m_data_o  => rd_fifo_m_data
    ); -- read_axi_fifo_small_inst

  --------------------------------------------------------------------
  -- Instantiate write FIFO
  --------------------------------------------------------------------

  write_axi_fifo_small_inst : entity work.axi_fifo_small
    generic map (
      G_RAM_DEPTH => C_BURST_LIMIT,
      G_RAM_WIDTH => C_WRITE_FIFO_DATA_SIZE
    )
    port map (
      clk_i     => clk_i,
      rst_i     => rst_i,
      s_ready_o => wr_fifo_s_ready,
      s_valid_i => wr_fifo_s_valid,
      s_data_i  => wr_fifo_s_data,
      m_ready_i => wr_fifo_m_ready,
      m_valid_o => wr_fifo_m_valid,
      m_data_o  => wr_fifo_m_data
    ); -- write_axi_fifo_small_inst

end architecture rtl;

