---------------------------------------------------------------------------------
-- Description: An AXI-Stream synchronous FIFO with optional frame drop.
--
-- Both input and output streams are frame-based, where end-of-frame is signaled
-- by asserting the s_last_i and m_last_o signals, respectively.
--
-- The input s_drop_i may be asserted anytime during a frame, in which case the
-- entire frame is discarded, and the cnt_drop_o counter is incremented once.
-- Note: s_drop_i is sampled even when s_ready_o is not asserted. It is an
-- out-of-band control and is NOT an AXI-Stream payload sideband, so it is not
-- required to remain stable across a stalled beat.
--
-- Frame commit model: only complete frames are made visible to the reader.
-- The write pointer advances speculatively while a frame is being received, but
-- start_ptr (the reader's upper bound) advances only when an end-of-frame beat
-- is accepted. A dropped or partial frame simply rewinds wr_ptr to start_ptr
-- and is never observed on the output stream.
--
-- Maximum frame size is 2**G_ADDR_BITS - 1 words. A single frame that exceeds
-- this size cannot be committed (the reader can never pass start_ptr), so the
-- writer will back-pressure forever. This is by design; guard against it at the
-- system level or with a formal 'assume' on frame length during verification.
--
-- Drop counter (cnt_drop_o):
--   * Width is set by G_CNT_BITS. The default is 16 bits.
--   * Set G_CNT_BITS = 0 to remove the counter entirely; cnt_drop_o then
--     becomes a null vector and the drop mechanism still works, but no count is
--     produced.
--   * The counter free-runs and wraps on overflow (no saturation). Treat it as
--     rolling telemetry rather than an exact lifetime total.
--
-- Note: This design reads its own 'out' ports internally (s_ready_o in wr_proc
-- and cnt_drop_o in its increment). This is legal only in VHDL-2008; do not
-- "refactor" these into 'buffer' ports or you will break the VHDL-2008 contract
-- expected by the rest of the codebase.
--
-- SPDX-License-Identifier: GPL-3.0-or-later
---------------------------------------------------------------------------------

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std_unsigned.all;

entity axis_dropper is
  generic (
    G_ADDR_BITS : positive;
    G_DATA_BITS : positive := 8;
    G_CNT_BITS  : natural  := 16;
    G_RAM_STYLE : string   := "auto"
  );
  port (
    clk_i      : in    std_logic;
    rst_i      : in    std_logic;
    cnt_drop_o : out   std_logic_vector(G_CNT_BITS - 1 downto 0);
    -- Input AXI stream
    s_ready_o  : out   std_logic;
    s_valid_i  : in    std_logic;
    s_data_i   : in    std_logic_vector(G_DATA_BITS - 1 downto 0);
    s_drop_i   : in    std_logic;
    s_last_i   : in    std_logic;
    -- Output AXI stream
    m_ready_i  : in    std_logic;
    m_valid_o  : out   std_logic := '0';
    m_data_o   : out   std_logic_vector(G_DATA_BITS - 1 downto 0);
    m_last_o   : out   std_logic := '0'
  );
end entity axis_dropper;

architecture rtl of axis_dropper is

  signal   start_ptr : std_logic_vector(G_ADDR_BITS - 1 downto 0);
  signal   wr_ptr    : std_logic_vector(G_ADDR_BITS - 1 downto 0);
  signal   rd_ptr    : std_logic_vector(G_ADDR_BITS - 1 downto 0);

  type     word_array_type is array (natural range <>) of std_logic_vector(G_DATA_BITS downto 0);
  signal   fifo : word_array_type(0 to 2 ** G_ADDR_BITS - 1);

  subtype  R_DATA is natural range G_DATA_BITS - 1 downto 0;

  constant C_LAST : natural         := G_DATA_BITS;

  attribute ram_style : string;
  attribute ram_style of fifo : signal is G_RAM_STYLE;

  type     rx_state_type is (ACCEPT_ST, DROP_ST);
  signal   rx_state : rx_state_type := ACCEPT_ST;

begin

  -- Validate generic at elaboration time. Comment out the assert if you
  -- need to target unusual vendor-specific styles.
  assert G_RAM_STYLE = "auto"
      or G_RAM_STYLE = "block"
      or G_RAM_STYLE = "distributed"
      or G_RAM_STYLE = "ultra"
      or G_RAM_STYLE = "registers"
    report "axis_dropper: G_RAM_STYLE='" & G_RAM_STYLE &
           "' is not a recognised Vivado ram_style value."
    severity failure;


  -- Back-pressure when FIFO is full. Also de-assert during reset so an
  -- upstream master that is not held in the same reset domain never sees
  -- ready asserted mid-reset.
  s_ready_o <= '1' when wr_ptr + 1 /= rd_ptr and rst_i = '0' else
               '0';

  wr_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then

      case rx_state is

        when ACCEPT_ST =>
          if s_valid_i = '1' then
            if s_drop_i = '1' then
              -- Drop wins over accept: discard the whole in-progress frame.
              cnt_drop_o <= cnt_drop_o + 1;
              -- Re-wind pointer to start of this frame
              wr_ptr     <= start_ptr;

              if s_last_i = '0' then
                -- Wait for end-of-frame
                rx_state <= DROP_ST;
              end if;
            elsif s_ready_o = '1' then
              fifo(to_integer(wr_ptr)) <= s_last_i & s_data_i;
              wr_ptr                   <= wr_ptr + 1;

              if s_last_i = '1' then
                -- End-of-frame accepted: commit the frame by advancing the
                -- reader's upper bound to the start of the next frame.
                start_ptr <= wr_ptr + 1;
              end if;
            end if;
          end if;

        when DROP_ST =>
          -- Skip words until end-of-frame
          if s_valid_i = '1' and s_last_i = '1' then
            rx_state <= ACCEPT_ST;
          end if;

      end case;

      if rst_i = '1' then
        cnt_drop_o <= (others => '0');
        start_ptr  <= (others => '0');
        wr_ptr     <= (others => '0');
        rx_state   <= ACCEPT_ST;
      end if;
    end if;
  end process wr_proc;

  rd_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then

      -- Clear the output register once the current word is consumed.
      if m_ready_i = '1' then
        m_valid_o <= '0';
        m_last_o  <= '0';
      end if;

      -- Load the next committed word whenever the output register is empty or
      -- is being drained this cycle. Crucially, m_valid_o is asserted here
      -- independently of m_ready_i, as required by AXI-Stream: a source must
      -- never wait for TREADY before asserting TVALID. The reader stays
      -- strictly behind start_ptr, so it never collides with the writer.
      if (m_valid_o = '0' or m_ready_i = '1') and rd_ptr /= start_ptr then
        m_data_o  <= fifo(to_integer(rd_ptr))(R_DATA);
        m_last_o  <= fifo(to_integer(rd_ptr))(C_LAST);
        m_valid_o <= '1';
        rd_ptr    <= rd_ptr + 1;
      end if;

      if rst_i = '1' then
        m_valid_o <= '0';
        m_last_o  <= '0';
        rd_ptr    <= (others => '0');
      end if;
    end if;
  end process rd_proc;

end architecture rtl;

