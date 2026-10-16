-------------------------------------------------------------------------------
-- physical_1581_wfifo.vhd
--
-- Dual-clock asynchronous FIFO for the physical internal 1581 write-byte
-- stream (issue #244). Write side runs on the drive clock (fdc1772 pushes one
-- byte per data-register write while the controller asks to be fed); read
-- side runs on the 50 MHz controller clock, which pops one byte per 32 us
-- disk slot. Default depth is 4 (G_AW = 2): the DOS can run at most three
-- bytes ahead of the disk, and nothing is left in flight when an op ends.
--
-- Textbook Gray-code async FIFO (Cummings, SNUG 2002):
--   * Binary and Gray write/read pointers, each G_AW+1 bits wide (the extra
--     MSB distinguishes full from empty).
--   * The Gray pointer of each domain is 2-FF synchronized into the opposite
--     domain (the first flop carries the Xilinx `async_reg` attribute).
--   * FULL  when the next write-Gray equals the synced read-Gray with the top
--     two bits inverted.
--   * EMPTY when the next read-Gray equals the synced write-Gray.
--   * Storage is a shared dual-port array in distributed LUTRAM: clocked
--     write port, asynchronous read of the current head (first-word-fall-
--     through: rd_data_o always shows the head; rd_en_i pops it).
--
-- Occupancy taps, one per side, each native to its own domain so that no
-- level ever has to cross:
--   * wr_level_o (write domain) is conservative-high: pops show up only
--     after their Gray pointer has crossed the 2-FF sync. It is the DRQ
--     source of the drive ("is there room?") and never claims room that is
--     not there.
--   * rd_level_o (read domain) is conservative-low: pushes show up only after
--     their Gray pointer has crossed. A consumer that waits for a threshold
--     is never told there is more than there really is.
--   At every instant: wr_level_o >= true occupancy >= rd_level_o.
--
-- Reset discipline: both sides must reset from the same event, each reset
-- synchronized into its own domain, with the two reset windows overlapping.
-- A one-sided reset permanently desynchronizes the Gray pointers and
-- corrupts data silently (the lesson of the read milestone). The pointer
-- synchronizers are cleared by the reset of the domain they belong to, so
-- the occupancy taps read 0 from the first reset cycle on instead of
-- carrying the pre-reset pointer of the other side for two cycles.
--
-- Depth = 2**G_AW. G_AW must be >= 2.
--
-- Adapted from AExp physical_fdd_wfifo.vhd (sy2002 2026, GPLv3), which in
-- turn is physical_1581_rdfifo.vhd with the read-side level tap; changes:
-- generic data width G_DW, synchronizers cleared by their domain's reset.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity physical_1581_wfifo is
  generic (
    G_DW : natural := 8;   -- data width
    G_AW : natural := 2    -- depth = 2**G_AW = 4 entries
  );
  port (
    wr_clk_i   : in  std_logic;
    wr_rst_i   : in  std_logic;
    wr_en_i    : in  std_logic;
    wr_data_i  : in  std_logic_vector(G_DW - 1 downto 0);
    wr_full_o  : out std_logic;
    -- Write-side occupancy: binary write pointer minus the Gray-synced
    -- (decoded) read pointer, in the wr_clk_i domain. Conservative-high.
    wr_level_o : out unsigned(G_AW downto 0);
    rd_clk_i   : in  std_logic;
    rd_rst_i   : in  std_logic;
    rd_en_i    : in  std_logic;
    rd_data_o  : out std_logic_vector(G_DW - 1 downto 0);
    rd_empty_o : out std_logic;
    -- Read-side occupancy: Gray-synced (decoded) write pointer minus the
    -- binary read pointer, in the rd_clk_i domain. Conservative-low.
    rd_level_o : out unsigned(G_AW downto 0)
  );
end entity physical_1581_wfifo;

architecture rtl of physical_1581_wfifo is

  -- Binary -> Gray (g = (b srl 1) xor b).
  function bin2gray(b : unsigned) return unsigned is
  begin
    return shift_right(b, 1) xor b;
  end function;

  -- Gray -> binary (b(i) = xor of g(high downto i)).
  function gray2bin(g : unsigned) return unsigned is
    variable b : unsigned(g'range);
  begin
    b(g'high) := g(g'high);
    for i in g'high - 1 downto g'low loop
      b(i) := b(i + 1) xor g(i);
    end loop;
    return b;
  end function;

  type mem_t is array (0 to 2**G_AW - 1) of std_logic_vector(G_DW - 1 downto 0);
  signal mem : mem_t := (others => (others => '0'));
  attribute ram_style : string;
  attribute ram_style of mem : signal is "distributed";

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
  attribute async_reg of rq2_wgray : signal is "true";
  attribute async_reg of wq1_rgray : signal is "true";
  attribute async_reg of wq2_rgray : signal is "true";

begin

  -----------------------------------------------------------------------------
  -- Write domain (wr_clk_i)
  -----------------------------------------------------------------------------
  w_do_write <= wr_en_i and not full_q;
  wbin_next  <= wbin + 1 when w_do_write = '1' else wbin;
  wgray_next <= bin2gray(wbin_next);

  wr_full_o <= full_q;

  -- Write-side occupancy tap. The pointer difference is taken modulo
  -- 2**(G_AW+1), which is exact for any fill level 0..2**G_AW.
  wr_level_o <= wbin - gray2bin(wq2_rgray);

  wr_domain : process (wr_clk_i)
  begin
    if rising_edge(wr_clk_i) then
      if wr_rst_i = '1' then
        wq1_rgray <= (others => '0');
        wq2_rgray <= (others => '0');
        wbin      <= (others => '0');
        wgray     <= (others => '0');
        full_q    <= '0';
      else
        -- Synchronize the read Gray pointer into the write domain.
        wq1_rgray <= rgray;
        wq2_rgray <= wq1_rgray;
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

  -- Read-side occupancy tap (the mirror of wr_level_o).
  rd_level_o <= gray2bin(rq2_wgray) - rbin;

  rd_domain : process (rd_clk_i)
  begin
    if rising_edge(rd_clk_i) then
      if rd_rst_i = '1' then
        rq1_wgray <= (others => '0');
        rq2_wgray <= (others => '0');
        rbin      <= (others => '0');
        rgray     <= (others => '0');
        empty_q   <= '1';
      else
        -- Synchronize the write Gray pointer into the read domain.
        rq1_wgray <= wgray;
        rq2_wgray <= rq1_wgray;
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
