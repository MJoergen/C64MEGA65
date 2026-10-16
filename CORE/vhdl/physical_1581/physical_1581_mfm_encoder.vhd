-------------------------------------------------------------------------------
-- physical_1581_mfm_encoder.vhd
--
-- DD-MFM byte encoder with CRC for the physical internal 1581 write path
-- (issue #244). Runs on the 50 MHz controller clock. The controller hands it
-- one byte per disk slot (one per 32 us in production); the encoder returns
-- the 16-bit channel word that physical_1581_writer serializes MSB first,
-- and keeps the running CRC-16 of the field being written.
--
-- Channel word of a plain byte d(7..0):
--     word = c7 d7 c6 d6 ... c0 d0        (bit 15 = c7, leaves first)
--     c_i  = not d_(i+1) and not d_i,     with d_8 = p
-- where p is the last data bit of the previous byte, carried across EVERY
-- byte boundary (sync marks and CRC bytes included). A missing clock cell is
-- fatal on media and invisible in a simulation that does not decode the flux
-- independently, so the carry is not optional anywhere.
--
-- Sync marks (mark_i, see enc_mark_t in physical_1581_pkg):
--     ENC_MARK_A1  -> C_MFM_SYNC_A1 = 0x4489 (A1, clock c2 missing), p := '1'
--     ENC_MARK_C2  -> C_MFM_SYNC_C2 = 0x5224 (C2, clock c3 missing), p := '0'
--   byte_i is ignored for a mark; the CRC is fed the mark's byte value (A1
--   or C2) when crc_feed_i is set. "11" is reserved and encodes byte_i as a
--   plain byte (simulation reports an error).
--
-- CRC: an instance of physical_1581_crc (CRC-16/CCITT-FALSE, init 0xFFFF).
--   crc_reset_i presets it to 0xFFFF BEFORE this byte is fed (the first A1 of
--   a sync run in Write Sector; the first F5 of a run in Write Track), and
--   crc_feed_i includes the byte. crc_o is the running value; the controller
--   emits it as two plain bytes, high byte first, with crc_feed_i = '0'.
--   start_i clears the CRC to 0xFFFF and the carried bit p to '0' (session
--   start); it may coincide with a valid_i strobe, which then encodes with
--   p = '0'.
--
-- Timing contract:
--   * word_o / word_valid_o are registered: word_valid_o is high for exactly
--     the one cycle after the clock edge that sampled valid_i, with word_o
--     valid in that cycle (latency 1).
--   * The CRC engine is serial (one bit per clock, one byte of buffering).
--     ready_o falls for C_ENC_CRC_BUSY = 10 cycles after a strobe that feeds
--     or presets the CRC; crc_o is final for every fed byte while
--     ready_o = '1'. A strobe that feeds or presets the CRC while ready_o is
--     '0' is a contract violation (simulation reports an error), and so is
--     start_i while ready_o is '0': the CRC entity's preset freezes but does
--     not cancel a byte that is still shifting (the shift resumes after the
--     preset), and its single buffer drops a byte that arrives in its load
--     cycle. ready_o is also low for C_ENC_CRC_BUSY cycles after rst_i. In
--     production the strobes are 1600 cycles apart.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_encoder is
  port (
    clk_i        : in  std_logic;                      -- 50 MHz controller clock
    rst_i        : in  std_logic;                      -- synchronous reset
    start_i      : in  std_logic;                      -- session start: p := '0', CRC := 0xFFFF
    byte_i       : in  std_logic_vector(7 downto 0);   -- data byte (ignored for a mark)
    mark_i       : in  enc_mark_t;                     -- ENC_MARK_NONE / _A1 / _C2
    crc_feed_i   : in  std_logic;                      -- include this byte in the CRC
    crc_reset_i  : in  std_logic;                      -- preset the CRC before feeding this byte
    valid_i      : in  std_logic;                      -- 1-cycle strobe: encode now
    ready_o      : out std_logic;                      -- CRC idle, crc_o final, next strobe allowed
    word_o       : out std_logic_vector(15 downto 0);  -- channel word, MSB leaves first
    word_valid_o : out std_logic;                      -- 1 cycle, one clock after valid_i
    crc_o        : out std_logic_vector(15 downto 0)   -- running CRC-16
  );
end entity physical_1581_mfm_encoder;

architecture rtl of physical_1581_mfm_encoder is

  -- Cycles the serial CRC needs from a feed until crc_value_o is final:
  -- 1 load + 8 shifts + 1 output register.
  constant C_ENC_CRC_BUSY : natural := 10;

  signal p_r        : std_logic := '0';                -- carried previous data bit
  signal word_r     : std_logic_vector(15 downto 0) := (others => '0');
  signal wvalid_r   : std_logic := '0';
  signal busy_cnt   : natural range 0 to C_ENC_CRC_BUSY := 0;

  signal crc_byte   : unsigned(7 downto 0);
  signal crc_feed   : std_logic;
  signal crc_reset  : std_logic;
  signal crc_value  : unsigned(15 downto 0);
  signal crc_ready  : std_logic;

  -- MFM channel word of a plain byte after carried bit p.
  function mfm_word(b : std_logic_vector(7 downto 0); p : std_logic)
    return std_logic_vector is
    variable d : std_logic_vector(8 downto 0);
    variable w : std_logic_vector(15 downto 0);
  begin
    d := p & b;
    for i in 7 downto 0 loop
      w(2 * i + 1) := (not d(i + 1)) and (not d(i));   -- clock cell c_i
      w(2 * i)     := d(i);                            -- data cell d_i
    end loop;
    return w;
  end function;

begin

  -----------------------------------------------------------------------------
  -- CRC engine (combinational strobes, same clock)
  -----------------------------------------------------------------------------
  crc_byte  <= x"A1" when mark_i = ENC_MARK_A1 else
               x"C2" when mark_i = ENC_MARK_C2 else
               unsigned(byte_i);
  crc_feed  <= valid_i and crc_feed_i and not rst_i;
  crc_reset <= rst_i or start_i or (valid_i and crc_reset_i);

  i_crc : entity work.physical_1581_crc
    port map (
      clk_i       => clk_i,
      crc_byte_i  => crc_byte,
      crc_feed_i  => crc_feed,
      crc_reset_i => crc_reset,
      crc_ready_o => crc_ready,
      crc_value_o => crc_value
    );

  ready_o      <= '1' when busy_cnt = 0 else '0';
  word_o       <= word_r;
  word_valid_o <= wvalid_r;
  crc_o        <= std_logic_vector(crc_value);

  -----------------------------------------------------------------------------
  -- Encoder
  -----------------------------------------------------------------------------
  enc_proc : process (clk_i)
    variable v_p : std_logic;
  begin
    if rising_edge(clk_i) then
      wvalid_r <= '0';
      if busy_cnt /= 0 then
        busy_cnt <= busy_cnt - 1;
      end if;

      v_p := p_r;
      if start_i = '1' then
        -- pragma translate_off
        assert busy_cnt = 0
          report "physical_1581_mfm_encoder: start_i while ready_o = '0'"
          severity error;
        -- pragma translate_on
        v_p := '0';
        p_r <= '0';
        if busy_cnt = 0 then
          busy_cnt <= 1;                        -- crc_o shows 0xFFFF one clock later
        end if;
      end if;

      if valid_i = '1' then
        -- pragma translate_off
        assert not ((crc_feed_i = '1' or crc_reset_i = '1') and busy_cnt /= 0)
          report "physical_1581_mfm_encoder: CRC strobe while ready_o = '0'"
          severity error;
        assert mark_i /= "11"
          report "physical_1581_mfm_encoder: reserved mark code 11"
          severity error;
        -- pragma translate_on
        case mark_i is
          when ENC_MARK_A1 =>
            word_r <= C_MFM_SYNC_A1;
            p_r    <= '1';                      -- bit 0 of A1
          when ENC_MARK_C2 =>
            word_r <= C_MFM_SYNC_C2;
            p_r    <= '0';                      -- bit 0 of C2
          when others =>
            word_r <= mfm_word(byte_i, v_p);
            p_r    <= byte_i(0);
        end case;
        wvalid_r <= '1';
        if crc_feed_i = '1' or crc_reset_i = '1' then
          busy_cnt <= C_ENC_CRC_BUSY;
        end if;
      end if;

      if rst_i = '1' then
        -- A byte that was shifting when the reset came resumes after it (the
        -- CRC entity's preset freezes but does not cancel a shift), so
        -- ready_o stays low until that shift has certainly finished.
        p_r      <= '0';
        wvalid_r <= '0';
        busy_cnt <= C_ENC_CRC_BUSY;
      end if;
    end if;
  end process enc_proc;

end architecture rtl;
