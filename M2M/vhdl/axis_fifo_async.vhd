-------------------------------------------------------------
-- Description: An AXI-Stream asynchronous (dual-clock) FIFO.
--
-- Overview
--   * Source side (s_*) and sink side (m_*) run on independent clocks
--     with no defined phase or frequency relationship.
--   * Storage  : 2**G_ADDR_BITS words of G_DATA_BITS bits, held in a
--                simple-dual-port RAM (one write port on s_clk_i, one
--                read port on m_clk_i).
--   * Pointers : Gray-coded, G_ADDR_BITS+1 bits wide. The extra MSB is
--                the wrap bit used to distinguish full from empty
--                (see get_gray_full / C_GRAY_FULL).
--   * Latency  : a word accepted on s_clk_i appears on m_data_o after
--                at least 2 m_clk_i edges (Gray pointer synchroniser)
--                plus 1 m_clk_i edge (registered RAM read).
--
-- Generics
--   * G_ADDR_BITS : log2 of FIFO depth in words. Must be >= 1.
--   * G_DATA_BITS : width of each word in bits. Must be >= 1.
--   * G_RAM_STYLE : passed verbatim to the Xilinx `ram_style` attribute
--                   on the storage array. Typical values: "auto"
--                   (default), "block", "distributed", "ultra",
--                   "registers". On non-Xilinx flows the attribute is
--                   simply ignored. Choose "block"/"ultra" for deep
--                   FIFOs and "distributed" for shallow ones.
--
-- Clock-domain crossings
--   * Pointer CDC: 2-FF synchronisers on the Gray-coded pointers; the
--     constraint file MUST provide a bounded skew constraint so that
--     the synchroniser can resolve metastability before sampling:
--         set_max_delay -datapath_only \
--             -from [get_cells {*/s_proc*/s_gray_wr_reg*}] \
--             -to   [get_cells {*/cdc_block/async_m_proc*/m_gray_wr_meta_reg*}] \
--             <T_max>
--         set_max_delay -datapath_only \
--             -from [get_cells {*/m_proc*/m_gray_rd_reg*}] \
--             -to   [get_cells {*/cdc_block/async_s_proc*/s_gray_rd_meta_reg*}] \
--             <T_max>
--     Choose <T_max> <= min(T_s_clk, T_m_clk) minus the launch/capture
--     setup margins. We deliberately avoid Xilinx XPM_FIFO_ASYNC,
--     which applies set_false_path internally; that is too permissive
--     for our use because it allows arbitrary skew on the Gray bits.
--
-- Reset
--   * async_rst_i is asynchronous-assert, synchronous-deassert. It is
--     synchronised independently into each clock domain using a 2-FF
--     reset synchroniser (s_rst_meta/s_rst and m_rst_meta/m_rst).
--   * Hold async_rst_i high for at least max(2*T_s_clk, 2*T_m_clk) so
--     both domains see the reset; releasing it early leaves the FIFO
--     in an asymmetric state (e.g. read side running while the write
--     side is still in reset).
--   * All reset-chain registers power up to '1', so the FIFO is
--     self-resetting at configuration time even if async_rst_i is
--     tied low.
--   * From the constraint file's point of view async_rst_i is purely
--     asynchronous:
--         set_false_path -from [get_ports async_rst_i] \
--                        -to   [get_cells {*_rst_meta_reg*}]
--
-- Occupancy outputs
--   * s_fill_o is a CONSERVATIVE OVER-estimate (uses the synchronised,
--     and therefore lagging, view of the read pointer). Safe to use
--     for back-pressure / "is there room?" decisions.
--   * m_fill_o is a CONSERVATIVE UNDER-estimate (uses the synchronised,
--     and therefore lagging, view of the write pointer). Safe to use
--     for "is there data?" decisions.
--   * Both outputs are purely combinational over the local domain's
--     view of the pointers and may glitch during pointer advance; if a
--     consumer needs a clean value it should register it locally.
--
-- SPDX-License-Identifier: MIT
-------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity axis_fifo_async is
  generic (
    G_ADDR_BITS : positive;
    G_DATA_BITS : positive;
    G_RAM_STYLE : string := "auto"
  );
  port (
    async_rst_i : in    std_logic;
    -- Input AXI stream
    s_clk_i     : in    std_logic;
    s_ready_o   : out   std_logic := '0';
    s_valid_i   : in    std_logic;
    s_data_i    : in    std_logic_vector(G_DATA_BITS - 1 downto 0);
    -- Conservative HIGH: uses sync'd read ptr; may briefly read full when consumer has
    -- just freed a slot. Safe for back-pressure decisions.
    s_fill_o    : out   natural range 0 to 2 ** G_ADDR_BITS;
    -- Output AXI stream
    m_clk_i     : in    std_logic;
    m_ready_i   : in    std_logic;
    m_valid_o   : out   std_logic := '0';
    m_data_o    : out   std_logic_vector(G_DATA_BITS - 1 downto 0);
    -- Conservative LOW: uses sync'd write ptr; may briefly read empty when producer has
    -- just added a word. Safe for "data available" checks.
    m_fill_o    : out   natural range 0 to 2 ** G_ADDR_BITS
  );
end entity axis_fifo_async;

architecture rtl of axis_fifo_async is

  signal   s_rst      : std_logic                                  := '1';
  signal   m_rst      : std_logic                                  := '1';
  signal   s_rst_meta : std_logic                                  := '1';
  signal   m_rst_meta : std_logic                                  := '1';

  -- Number of words in the FIFO. Pointers are G_ADDR_BITS+1 bits wide;
  -- the extra MSB is the wrap bit used to distinguish full from empty
  -- (see get_gray_full and C_GRAY_FULL).
  constant C_FIFO_SIZE : positive                                  := 2 ** G_ADDR_BITS;

  -- Dual-port RAM holding the FIFO data. The `ram_style` attribute is
  -- forwarded from the generic so the user can pick block/distributed/
  -- ultra/registers at instantiation (see header).
  type     ram_type is array (natural range <>) of std_logic_vector(G_DATA_BITS - 1 downto 0);
  signal   dpram : ram_type(0 to C_FIFO_SIZE - 1) := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of dpram : signal is G_RAM_STYLE;

  -- Combinational read-enable shared by dpram_rd_proc and m_proc.
  -- Asserted when the m-domain is out of reset, the FIFO is non-empty,
  -- and the output register is free to accept the next word. Defining it
  -- once prevents the two consumer processes from drifting apart.
  signal   m_rd_en : std_logic;

  -----------------------------------------------------------
  -- Gray-coded pointers.
  -- Gray code is used so that the CDC synchroniser between domains sees
  -- at most one bit change per pointer advance, eliminating multi-bit
  -- sampling skew.
  -----------------------------------------------------------

  -- Write pointer (gray code) in source clock domain
  signal   s_gray_wr : std_logic_vector(G_ADDR_BITS downto 0)      := (others => '0');

  -- Write pointer (gray code) in destination clock domain
  signal   m_gray_wr : std_logic_vector(G_ADDR_BITS downto 0)      := (others => '0');

  -- Read pointer (gray code) in destination clock domain
  signal   m_gray_rd : std_logic_vector(G_ADDR_BITS downto 0)      := (others => '0');

  -- Read pointer (gray code) in source clock domain
  signal   s_gray_rd : std_logic_vector(G_ADDR_BITS downto 0)      := (others => '0');

  -- 2-FF synchronizers used at two distinct CDC crossings:
  --   (a) Gray-coded write/read pointers between s_clk_i and m_clk_i
  --       (m_gray_wr_meta / m_gray_wr and s_gray_rd_meta / s_gray_rd).
  --   (b) The asynchronous reset async_rst_i into each domain
  --       (s_rst_meta / s_rst and m_rst_meta / m_rst).
  -- All eight stages carry the async_reg attribute so the synthesis tool
  -- packs them adjacent and keeps the metastability margin intact.
  -- The pointer crossings additionally require a set_max_delay
  -- -datapath_only constraint (see header); the reset crossing requires
  -- a set_false_path (also documented in the header).
  signal   m_gray_wr_meta : std_logic_vector(G_ADDR_BITS downto 0) := (others => '0');
  signal   s_gray_rd_meta : std_logic_vector(G_ADDR_BITS downto 0) := (others => '0');
  attribute async_reg : string;
  attribute async_reg of m_gray_wr_meta : signal is "true";
  attribute async_reg of m_gray_wr      : signal is "true";
  attribute async_reg of s_gray_rd_meta : signal is "true";
  attribute async_reg of s_gray_rd      : signal is "true";
  attribute async_reg of s_rst_meta     : signal is "true";
  attribute async_reg of s_rst          : signal is "true";
  attribute async_reg of m_rst_meta     : signal is "true";
  attribute async_reg of m_rst          : signal is "true";


  -----------------------------------------------------------
  -- Pure helper functions (Gray/binary conversion and full-pattern).
  -- All are synthesizable and operate on the descending range convention.
  -----------------------------------------------------------

  -- Binary -> Gray. The argument is interpreted as MSB-first; i.e. b'left is
  -- assumed to be the most significant bit. Behavior is undefined for
  -- ascending ranges.

  pure function unsigned2gray (
    b : unsigned
  ) return std_logic_vector is
    variable g_v : std_logic_vector(b'range);
  begin
    g_v(b'left) := b(b'left);

    for i in b'left - 1 downto b'right loop
      g_v(i) := b(i + 1) xor b(i);
    end loop;

    return g_v;
  end function unsigned2gray;

  -- Gray -> Binary. The argument is interpreted as MSB-first; i.e. g'left is
  -- assumed to be the most significant bit. Behavior is undefined for
  -- ascending ranges. Returns an 'unsigned' with the same (descending) range as g.

  pure function gray2unsigned (
    g : std_logic_vector
  ) return unsigned is
    variable b_v : unsigned(g'range);
  begin
    b_v(g'left) := g(g'left);

    for i in g'left - 1 downto g'right loop
      b_v(i) := b_v(i + 1) xor g(i);
    end loop;

    return b_v;
  end function gray2unsigned;

  -- Returns the XOR pattern that two valid (N+1)-bit Gray pointers exhibit
  -- exactly when the FIFO is full: top two bits set, all lower bits zero.
  -- For G_ADDR_BITS = 3 this returns "1100".

  pure function get_gray_full return std_logic_vector is
    variable res_v : std_logic_vector(G_ADDR_BITS downto 0);
  begin
    res_v                  := (others => '0');
    res_v(G_ADDR_BITS)     := '1';
    res_v(G_ADDR_BITS - 1) := '1';
    return res_v;
  end function get_gray_full;

  constant C_GRAY_FULL : std_logic_vector(G_ADDR_BITS downto 0)    := get_gray_full;

begin

  -- Validate generic at elaboration time. Comment out the assert if you
  -- need to target unusual vendor-specific styles.
  assert G_RAM_STYLE = "auto"
      or G_RAM_STYLE = "block"
      or G_RAM_STYLE = "distributed"
      or G_RAM_STYLE = "ultra"
      or G_RAM_STYLE = "registers"
    report "axis_fifo_async: G_RAM_STYLE='" & G_RAM_STYLE &
           "' is not a recognised Vivado ram_style value."
    severity failure;


  -----------------------------------------------------------
  -- Back-pressure and occupancy outputs (combinational).
  --
  -- Back-pressure: deassert s_ready_o when the FIFO is full, i.e. when the
  -- write and read Gray pointers differ only in the top two bits.
  -- Note: s_gray_rd is the synchronized (delayed) view of the m-domain read
  -- pointer, so s_ready_o may stay low for an extra cycle or two after the
  -- consumer actually frees a slot. This is intentional and safe.
  --
  -- Occupancy: both fill outputs are computed in their *local* domain from
  -- the local pointer and the synchronized remote pointer. See port comments
  -- for the conservative over-/under-estimate guarantee.
  -----------------------------------------------------------

  s_ready_o <= '0' when s_rst = '1' or (s_gray_wr xor s_gray_rd) = C_GRAY_FULL else
               '1';

  s_fill_o  <= to_integer(gray2unsigned(s_gray_wr) - gray2unsigned(s_gray_rd));
  m_fill_o  <= to_integer(gray2unsigned(m_gray_wr) - gray2unsigned(m_gray_rd));

  -----------------------------------------------------------
  -- s_clk_i domain: advance write pointer on accepted handshake.
  -- A handshake is accepted when both s_valid_i and s_ready_o are high.
  -- The pointer is stored in Gray code so the m-domain synchronizer sees
  -- at most one bit transition per advance, eliminating multi-bit skew.
  -----------------------------------------------------------

  s_proc : process (s_clk_i)
  begin
    if rising_edge(s_clk_i) then
      if s_valid_i = '1' and s_ready_o = '1' then
        s_gray_wr <= unsigned2gray(gray2unsigned(s_gray_wr) + 1);
      end if;

      -- NOTE: Synchronous reset is written last so it has priority over the
      -- enable branch (last assignment wins in VHDL signal scheduling).
      if s_rst = '1' then
        s_gray_wr <= (others => '0');
      end if;
    end if;
  end process s_proc;


  -----------------------------------------------------------
  -- Dual port memory: One write port, and one read port.
  -----------------------------------------------------------

  -- s_clk_i domain: write port of the dual-port RAM.
  dpram_wr_proc : process (s_clk_i)
    variable index_v : natural range 0 to C_FIFO_SIZE - 1;
  begin
    -- Write to memory
    if rising_edge(s_clk_i) then
      if s_valid_i = '1' and s_ready_o = '1' then
        index_v        := to_integer(gray2unsigned(s_gray_wr)(G_ADDR_BITS - 1 downto 0));
        dpram(index_v) <= s_data_i;
      end if;
    end if;
  end process dpram_wr_proc;

  -- m_clk_i domain: read port of the dual-port RAM.
  --
  -- No CDC synchroniser is required on the RAM read-data path. Proof:
  --   (1) A read at index i in the m-domain only fires when m_rd_en = '1'.
  --   (2) m_rd_en requires m_gray_wr /= m_gray_rd, i.e. m_gray_wr has
  --       advanced past i.
  --   (3) m_gray_wr is the *output* of the 2-FF Gray pointer synchroniser,
  --       so the corresponding write on s_clk_i happened at least
  --       2 m_clk_i edges in the past.
  --   (4) Therefore the addressed memory cell has been stable for >=
  --       2 m_clk_i cycles before it is sampled. A single output
  --       flip-flop (m_data_o) is sufficient; no metastability resolution
  --       is needed on the data path.
  dpram_rd_proc : process (m_clk_i)
    variable index_v : natural range 0 to C_FIFO_SIZE - 1;
  begin
    -- Read from memory
    if rising_edge(m_clk_i) then
      if m_rd_en = '1' then
        index_v  := to_integer(gray2unsigned(m_gray_rd)(G_ADDR_BITS - 1 downto 0));
        m_data_o <= dpram(index_v);
      end if;
    end if;
  end process dpram_rd_proc;


  -----------------------------------------------------------
  -- All CDC-resolving flip-flops live inside this block:
  --   * Gray-pointer crossings (set_max_delay -datapath_only)
  --   * Reset crossings        (set_false_path)
  -- Both constraint forms are documented in the file header; keeping the
  -- destination FFs under one named scope makes the XDC selectors short
  -- and stable across hierarchy refactors.
  -----------------------------------------------------------

  cdc_block : block is
  begin

    -- Both CDC crossings into the m-domain share a single process so that
    -- synthesis groups all four destination flip-flops together; this
    -- helps placement keep the metastability-resolving FFs adjacent.
    async_m_proc : process (m_clk_i)
    begin
      if rising_edge(m_clk_i) then
        -- Synchronize write pointer
        m_gray_wr_meta <= s_gray_wr;
        m_gray_wr      <= m_gray_wr_meta;
        -- Synchronize reset
        m_rst_meta     <= async_rst_i;
        m_rst          <= m_rst_meta;
      end if;
    end process async_m_proc;

    -- Both CDC crossings into the s-domain share a single process so that
    -- synthesis groups all four destination flip-flops together; this
    -- helps placement keep the metastability-resolving FFs adjacent.
    async_s_proc : process (s_clk_i)
    begin
      if rising_edge(s_clk_i) then
        -- Synchronize read pointer
        s_gray_rd_meta <= m_gray_rd;
        s_gray_rd      <= s_gray_rd_meta;
        -- Synchronize reset
        s_rst_meta     <= async_rst_i;
        s_rst          <= s_rst_meta;
      end if;
    end process async_s_proc;

  end block cdc_block;


  -----------------------------------------------------------
  -- m_clk_i domain: pop one word per accepted handshake.
  -- A pop is issued whenever the FIFO is non-empty (m_gray_wr /= m_gray_rd)
  -- and the output register is free (m_ready_i = '1' or m_valid_o = '0').
  --
  -- m_rd_en is gated by m_rst so that no pop happens while the m-domain
  -- is in reset. After deassertion the two domains can exit reset on
  -- different m_clk_i edges; the first pop after reset can therefore occur
  -- on the very cycle m_rst = '0', against an s-domain that has already
  -- accepted one or more words. This is intentional: the FIFO is allowed
  -- to be productive immediately on reset release.
  -----------------------------------------------------------

  m_rd_en <= '1' when m_rst = '0'
                  and m_gray_wr /= m_gray_rd
                  and (m_ready_i = '1' or m_valid_o = '0')
                  else '0';

  m_proc : process (m_clk_i)
  begin
    if rising_edge(m_clk_i) then
      if m_ready_i = '1' then
        m_valid_o <= '0';
      end if;

      if m_rd_en = '1' then
        m_gray_rd <= unsigned2gray(gray2unsigned(m_gray_rd) + 1);
        m_valid_o <= '1';
      end if;

      -- NOTE: Synchronous reset is written last so it has priority over the
      -- enable branch (last assignment wins in VHDL signal scheduling).
      if m_rst = '1' then
        m_gray_rd <= (others => '0');
        m_valid_o <= '0';
      end if;
    end if;
  end process m_proc;

end architecture rtl;

