-------------------------------------------------------------------------------
-- physical_1581_rdfifo.vhd
--
-- Dual-clock asynchronous byte FIFO for the physical internal 1581 read-byte
-- stream (issue #90). Write side runs on the 50 MHz controller clock; read
-- side runs on the ~16 MHz drive clock (fdc1772 drains it with its existing
-- DRQ pacing). This is the elastic queue that absorbs CDC latency between the
-- two async, non-integer-ratio clock domains.
--
-- Textbook Gray-code async FIFO (Cummings, SNUG 2002):
--   * Binary and Gray write/read pointers, each G_AW+1 bits wide (the extra
--     MSB distinguishes full from empty).
--   * The Gray pointer of each domain is 2-FF synchronized into the opposite
--     domain (the first flop carries the Xilinx `async_reg` attribute).
--   * FULL  when the next write-Gray equals the synced read-Gray with the top
--     two bits inverted.
--   * EMPTY when the next read-Gray equals the synced write-Gray.
--   * Storage is a shared dual-port array: clocked write port, asynchronous
--     read of the current head (first-word-fall-through: rd_data_o always
--     shows the head; rd_en_i pops it).
--
-- Depth = 2**G_AW (default 32). G_AW must be >= 2.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity physical_1581_rdfifo is
  generic (
    G_AW : natural := 5   -- depth = 2**G_AW = 32
  );
  port (
    wr_clk_i   : in  std_logic;
    wr_rst_i   : in  std_logic;
    wr_en_i    : in  std_logic;
    wr_data_i  : in  unsigned(7 downto 0);
    wr_full_o  : out std_logic;
    rd_clk_i   : in  std_logic;
    rd_rst_i   : in  std_logic;
    rd_en_i    : in  std_logic;
    rd_data_o  : out unsigned(7 downto 0);
    rd_empty_o : out std_logic
  );
end entity physical_1581_rdfifo;

architecture rtl of physical_1581_rdfifo is

  -- Binary -> Gray (g = (b srl 1) xor b).
  function bin2gray(b : unsigned) return unsigned is
  begin
    return shift_right(b, 1) xor b;
  end function;

  type mem_t is array (0 to 2**G_AW - 1) of unsigned(7 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  -- Write domain.
  signal wbin       : unsigned(G_AW downto 0) := (others => '0');
  signal wgray      : unsigned(G_AW downto 0) := (others => '0');
  signal wbin_next  : unsigned(G_AW downto 0);
  signal wgray_next : unsigned(G_AW downto 0);
  signal w_do_write : std_logic;
  signal full_q     : std_logic := '0';

  -- Read domain.
  signal rbin       : unsigned(G_AW downto 0) := (others => '0');
  signal rgray      : unsigned(G_AW downto 0) := (others => '0');
  signal rbin_next  : unsigned(G_AW downto 0);
  signal rgray_next : unsigned(G_AW downto 0);
  signal r_do_read  : std_logic;
  signal empty_q    : std_logic := '1';

  -- Cross-domain 2-FF synchronizers.
  signal rq1_wgray  : unsigned(G_AW downto 0) := (others => '0');  -- write-Gray into read domain
  signal rq2_wgray  : unsigned(G_AW downto 0) := (others => '0');
  signal wq1_rgray  : unsigned(G_AW downto 0) := (others => '0');  -- read-Gray into write domain
  signal wq2_rgray  : unsigned(G_AW downto 0) := (others => '0');

  attribute async_reg              : string;
  attribute async_reg of rq1_wgray : signal is "true";
  attribute async_reg of wq1_rgray : signal is "true";

begin

  -----------------------------------------------------------------------------
  -- Write domain (wr_clk_i)
  -----------------------------------------------------------------------------
  w_do_write <= wr_en_i and not full_q;
  wbin_next  <= wbin + 1 when w_do_write = '1' else wbin;
  wgray_next <= bin2gray(wbin_next);

  wr_full_o <= full_q;

  wr_domain : process (wr_clk_i)
  begin
    if rising_edge(wr_clk_i) then
      -- Synchronize the read Gray pointer into the write domain.
      wq1_rgray <= rgray;
      wq2_rgray <= wq1_rgray;

      if wr_rst_i = '1' then
        wbin   <= (others => '0');
        wgray  <= (others => '0');
        full_q <= '0';
      else
        if w_do_write = '1' then
          mem(to_integer(wbin(G_AW - 1 downto 0))) <= wr_data_i;
        end if;
        wbin  <= wbin_next;
        wgray <= wgray_next;
        -- FULL: next write-Gray equals synced read-Gray with top two bits flipped.
        if wgray_next =
             ((not wq2_rgray(G_AW)) & (not wq2_rgray(G_AW - 1)) &
              wq2_rgray(G_AW - 2 downto 0)) then
          full_q <= '1';
        else
          full_q <= '0';
        end if;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Read domain (rd_clk_i)
  -----------------------------------------------------------------------------
  r_do_read  <= rd_en_i and not empty_q;
  rbin_next  <= rbin + 1 when r_do_read = '1' else rbin;
  rgray_next <= bin2gray(rbin_next);

  rd_empty_o <= empty_q;
  -- Asynchronous head read (first-word-fall-through).
  rd_data_o  <= mem(to_integer(rbin(G_AW - 1 downto 0)));

  rd_domain : process (rd_clk_i)
  begin
    if rising_edge(rd_clk_i) then
      -- Synchronize the write Gray pointer into the read domain.
      rq1_wgray <= wgray;
      rq2_wgray <= rq1_wgray;

      if rd_rst_i = '1' then
        rbin    <= (others => '0');
        rgray   <= (others => '0');
        empty_q <= '1';
      else
        rbin  <= rbin_next;
        rgray <= rgray_next;
        -- EMPTY: next read-Gray equals synced write-Gray.
        if rgray_next = rq2_wgray then
          empty_q <= '1';
        else
          empty_q <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
