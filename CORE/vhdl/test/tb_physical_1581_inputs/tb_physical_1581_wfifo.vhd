-------------------------------------------------------------------------------
-- tb_physical_1581_wfifo.vhd
--
-- Self-checking GHDL testbench for physical_1581_wfifo (production shape:
-- G_DW = 8, G_AW = 2, depth 4). Two unrelated clocks: 31.5 MHz write side
-- (the drive clock) and 50 MHz read side (the controller clock).
--
-- Phase 1  fill to full with the reader stalled: exactly 4 pushes accepted,
--          further pushes refused (wr_full_o), both level taps reach 4.
-- Phase 2  drain to empty: the 4 words come out in order (the refused pushes
--          did not overwrite anything), both taps return to 0.
-- Phase 3  interleaved traffic: both sides paced by independent LFSRs, the
--          writer sometimes faster, sometimes slower than the reader; data is
--          an LFSR sequence the reader regenerates independently, so a lost,
--          duplicated or reordered word fails at once. 12,000 words.
-- Phase 4  reset in the middle of traffic: both sides reset from one event,
--          each reset asserted and released at its own clock edge (read side
--          first in, write side last out, overlapping); afterwards the FIFO
--          is empty, both taps read 0, no pre-reset word ever comes out, and
--          a fresh 3,000-word stream passes.
--
-- Throughout (outside the reset windows), checked 1 ns after every edge of
-- either clock:  wr_level_o >= true occupancy >= rd_level_o, and
-- wr_level_o <= depth. True occupancy is counted from the handshakes.
--
-- Run (B = absolute scratch workdir; run from the scratch directory):
--   ghdl -a --std=08 --workdir=B CORE/vhdl/physical_1581/physical_1581_wfifo.vhd \
--        CORE/vhdl/test/tb_physical_1581_inputs/tb_physical_1581_wfifo.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_wfifo --assert-level=error
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_physical_1581_wfifo is
end entity;

architecture sim of tb_physical_1581_wfifo is

  constant C_DEPTH  : integer := 4;
  constant C_N_MAIN : integer := 12_000;   -- phase 3 words
  constant C_N_PRE  : integer := 1_500;    -- phase 4 words before the reset
  constant C_N_POST : integer := 3_000;    -- phase 4 words after the reset

  signal wr_clk   : std_logic := '0';
  signal rd_clk   : std_logic := '0';
  signal wr_rst   : std_logic := '1';
  signal rd_rst   : std_logic := '1';

  signal wr_en    : std_logic := '0';
  signal wr_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal wr_full  : std_logic;
  signal wr_level : unsigned(2 downto 0);

  signal rd_en    : std_logic := '0';
  signal rd_data  : std_logic_vector(7 downto 0);
  signal rd_empty : std_logic;
  signal rd_level : unsigned(2 downto 0);

  -- handshake-derived true occupancy
  signal n_w : integer := 0;
  signal n_r : integer := 0;

  -- phase control (main process -> agents)
  --   wr_mode: 0 idle, 1 push until full (phase 1), 2 paced stream
  --   rd_mode: 0 idle, 1 drain until empty (phase 2), 2 paced stream
  signal wr_mode   : integer := 0;
  signal rd_mode   : integer := 0;
  signal wr_quota  : integer := 0;      -- words to push in mode 2
  signal rd_quota  : integer := 0;      -- words to pop in mode 2
  signal wr_seed   : integer := 1;      -- data LFSR seed of the stream
  signal wr_count  : integer := 0;      -- words accepted in the current mode
  signal rd_count  : integer := 0;      -- words popped in the current mode
  signal rd_errors : integer := 0;
  signal chk_en    : boolean := false;
  signal cov_full  : integer := 0;      -- write edges seen with wr_full_o = '1'
  signal cov_empty : integer := 0;      -- read edges seen with rd_empty_o = '1'

  -- 16-bit maximal Fibonacci LFSR (x^16 + x^14 + x^13 + x^11 + 1)
  function lfsr(x : natural) return natural is
    variable v  : unsigned(15 downto 0) := to_unsigned(x mod 65536, 16);
    variable fb : std_logic;
  begin
    fb := v(15) xor v(13) xor v(12) xor v(10);
    return to_integer(unsigned'(v(14 downto 0) & fb));
  end function;

  function byte_of(x : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(x mod 256, 8));
  end function;

begin

  wr_clk <= not wr_clk after 15.873 ns;   -- 31.5 MHz
  rd_clk <= not rd_clk after 10 ns;       -- 50 MHz

  dut : entity work.physical_1581_wfifo
    generic map (G_DW => 8, G_AW => 2)
    port map (
      wr_clk_i   => wr_clk,
      wr_rst_i   => wr_rst,
      wr_en_i    => wr_en,
      wr_data_i  => wr_data,
      wr_full_o  => wr_full,
      wr_level_o => wr_level,
      rd_clk_i   => rd_clk,
      rd_rst_i   => rd_rst,
      rd_en_i    => rd_en,
      rd_data_o  => rd_data,
      rd_empty_o => rd_empty,
      rd_level_o => rd_level
    );

  watchdog : process
  begin
    wait for 20 ms;
    report "TIMEOUT" severity failure;
  end process;

  ---------------------------------------------------------------------------
  -- Level invariant checker
  ---------------------------------------------------------------------------
  checker : process
    variable occ : integer;
  begin
    wait until rising_edge(wr_clk) or rising_edge(rd_clk);
    wait for 1 ns;
    if chk_en and wr_rst = '0' and rd_rst = '0' then
      occ := n_w - n_r;
      assert occ >= 0 and occ <= C_DEPTH
        report "true occupancy out of range: " & integer'image(occ) severity error;
      assert to_integer(wr_level) >= occ
        report "wr_level_o = " & integer'image(to_integer(wr_level))
               & " below true occupancy " & integer'image(occ) severity error;
      assert to_integer(rd_level) <= occ
        report "rd_level_o = " & integer'image(to_integer(rd_level))
               & " above true occupancy " & integer'image(occ) severity error;
      assert to_integer(wr_level) <= C_DEPTH
        report "wr_level_o exceeds depth" severity error;
    end if;
  end process;

  coverage : process
  begin
    wait until rising_edge(wr_clk) or rising_edge(rd_clk);
    if wr_mode = 2 and rd_mode = 2 then
      if rising_edge(wr_clk) and wr_full = '1' then
        cov_full <= cov_full + 1;
      end if;
      if rising_edge(rd_clk) and rd_empty = '1' then
        cov_empty <= cov_empty + 1;
      end if;
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Write agent (wr_clk). Resumes in delta 0 of every edge, so it sees the
  -- pre-edge values: wr_en = '1' and wr_full = '0' now means the DUT accepts
  -- the current wr_data at this very edge.
  ---------------------------------------------------------------------------
  writer : process
    variable dat  : natural := 1;   -- data LFSR state (value of the next word)
    variable pace : natural := 16#ACE1#;
    variable mode : integer := 0;
    variable cnt  : integer := 0;
    variable go   : boolean;
  begin
    wait until rising_edge(wr_clk);
    if wr_rst = '1' then
      n_w <= 0;
    elsif wr_en = '1' and wr_full = '0' then
      n_w <= n_w + 1;
      cnt := cnt + 1;
      dat := lfsr(dat);
    end if;
    if wr_mode /= mode then           -- mode change: restart the stream
      mode := wr_mode;
      cnt  := 0;
      dat  := wr_seed;
    end if;
    wr_count <= cnt;
    pace := lfsr(pace);
    case mode is
      when 1 =>       go := true;                       -- hammer, also while full
      when 2 =>       go := cnt < wr_quota and
                            ((pace mod 8) < 5);          -- ~5/8 duty
      when others =>  go := false;
    end case;
    if wr_rst = '1' then
      go := false;
    end if;
    if go then
      wr_en   <= '1';
      wr_data <= byte_of(dat);
    else
      wr_en   <= '0';
      wr_data <= (others => 'X');
    end if;
  end process;

  ---------------------------------------------------------------------------
  -- Read agent (rd_clk), same delta-0 convention: rd_en = '1' and
  -- rd_empty = '0' now means the head rd_data is popped at this edge.
  ---------------------------------------------------------------------------
  reader : process
    variable dat  : natural := 1;   -- expected data LFSR state
    variable pace : natural := 16#1D0F#;
    variable mode : integer := 0;
    variable cnt  : integer := 0;
    variable errs : integer := 0;
    variable go   : boolean;
    variable burst : integer := 0;
  begin
    wait until rising_edge(rd_clk);
    if rd_rst = '1' then
      n_r <= 0;
    elsif rd_en = '1' and rd_empty = '0' then
      if rd_data /= byte_of(dat) then
        errs := errs + 1;
        report "DATA MISMATCH at word " & integer'image(cnt) & " (mode "
               & integer'image(mode) & "): got 0x" & to_hstring(rd_data)
               & " expected 0x" & to_hstring(byte_of(dat)) severity error;
      end if;
      n_r <= n_r + 1;
      cnt := cnt + 1;
      dat := lfsr(dat);
    end if;
    if rd_mode /= mode then
      mode := rd_mode;
      cnt  := 0;
      dat  := wr_seed;
    end if;
    rd_count  <= cnt;
    rd_errors <= errs;
    pace := lfsr(pace);
    case mode is
      when 1 =>
        go := true;
      when 2 =>
        -- alternate fast and slow stretches so the FIFO runs both full and
        -- empty: 256-cycle windows of ~3/4 vs ~1/8 duty
        burst := (burst + 1) mod 512;
        if burst < 256 then
          go := (pace mod 4) /= 0;
        else
          go := (pace mod 8) = 0;
        end if;
        go := go and cnt < rd_quota;
      when others =>
        go := false;
    end case;
    if rd_rst = '1' then
      go := false;
    end if;
    rd_en <= '1' when go else '0';
  end process;

  ---------------------------------------------------------------------------
  -- Main sequence
  ---------------------------------------------------------------------------
  main : process
    procedure wr_cycles(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(wr_clk);
      end loop;
    end procedure;
    procedure rd_cycles(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(rd_clk);
      end loop;
    end procedure;
    variable t0 : time;
  begin
    -- common power-on reset, then release each side at its own edge
    wr_rst <= '1';
    rd_rst <= '1';
    wr_cycles(8);
    wr_rst <= '0';
    rd_cycles(3);
    rd_rst <= '0';
    rd_cycles(10);
    chk_en <= true;

    assert rd_empty = '1' and wr_full = '0' and wr_level = 0 and rd_level = 0
      report "FIFO not empty after power-on reset" severity error;

    -------------------------------------------------------------------------
    -- Phase 1: fill to full, reader stalled; keep pushing while full.
    -------------------------------------------------------------------------
    wr_seed <= 16#0101#;
    wr_mode <= 1;
    wr_cycles(40);                      -- 40 push attempts, only 4 may land
    wr_mode <= 0;
    wr_cycles(4);
    rd_cycles(8);                       -- let the write pointer cross over
    assert n_w = C_DEPTH
      report "phase 1: " & integer'image(n_w) & " pushes accepted, expected 4"
      severity error;
    assert wr_full = '1' report "phase 1: wr_full_o not set when full" severity error;
    assert to_integer(wr_level) = C_DEPTH
      report "phase 1: wr_level_o = " & integer'image(to_integer(wr_level)) severity error;
    assert to_integer(rd_level) = C_DEPTH
      report "phase 1: rd_level_o = " & integer'image(to_integer(rd_level)) severity error;
    assert rd_empty = '0' report "phase 1: rd_empty_o set while full" severity error;
    report "phase 1: full after exactly 4 pushes, 36 refused, both taps = 4 -- OK";

    -------------------------------------------------------------------------
    -- Phase 2: drain to empty.
    -------------------------------------------------------------------------
    rd_mode <= 1;
    rd_cycles(20);
    rd_mode <= 0;
    rd_cycles(2);
    wr_cycles(6);                       -- let the read pointer cross over
    assert n_r = C_DEPTH
      report "phase 2: " & integer'image(n_r) & " pops, expected 4" severity error;
    assert rd_empty = '1' report "phase 2: not empty after drain" severity error;
    assert wr_level = 0 and rd_level = 0 and wr_full = '0'
      report "phase 2: taps not 0 after drain" severity error;
    assert rd_errors = 0 report "phase 2: data errors" severity error;
    report "phase 2: 4 words in order, empty, both taps = 0 -- OK";

    -------------------------------------------------------------------------
    -- Phase 3: interleaved paced traffic.
    -------------------------------------------------------------------------
    wr_seed  <= 16#BEEF#;
    wr_quota <= C_N_MAIN;
    rd_quota <= C_N_MAIN;
    wr_mode  <= 2;
    rd_mode  <= 2;
    t0 := now;
    wait until rd_count = C_N_MAIN for 15 ms;
    assert rd_count = C_N_MAIN
      report "phase 3: only " & integer'image(rd_count) & " words arrived" severity failure;
    wr_mode <= 0;
    rd_mode <= 0;
    rd_cycles(4);
    wr_cycles(6);
    assert rd_errors = 0 report "phase 3: data errors" severity error;
    assert cov_full > 100 and cov_empty > 100
      report "phase 3: coverage hole, full seen " & integer'image(cov_full)
             & "x, empty seen " & integer'image(cov_empty) & "x" severity error;
    assert rd_empty = '1' and wr_level = 0 and rd_level = 0
      report "phase 3: FIFO not empty after the stream" severity error;
    report "phase 3: " & integer'image(C_N_MAIN) & " interleaved words in order in "
           & integer'image((now - t0) / 1 us) & " us (FIFO full at "
           & integer'image(cov_full) & " write edges, empty at "
           & integer'image(cov_empty) & " read edges) -- OK";

    -------------------------------------------------------------------------
    -- Phase 4: reset in the middle of traffic, both sides.
    -------------------------------------------------------------------------
    wr_seed  <= 16#1234#;
    wr_quota <= 1_000_000;              -- never runs out before the reset
    rd_quota <= 1_000_000;
    wr_mode  <= 2;
    rd_mode  <= 2;
    wait until rd_count >= C_N_PRE for 5 ms;
    assert rd_count >= C_N_PRE report "phase 4: pre-reset stream stalled" severity failure;
    -- one reset event: read side first in, write side 2 write cycles later,
    -- write side released first, read side 5 read cycles after it
    wait until rising_edge(rd_clk);
    rd_rst <= '1';
    wr_cycles(2);
    wr_rst <= '1';
    -- both agents stop driving traffic while their side is in reset; switch
    -- them to idle so the post-reset stream restarts from a fresh seed
    wr_mode <= 0;
    rd_mode <= 0;
    wr_cycles(12);
    rd_cycles(12);
    wr_seed <= 16#4321#;
    wait until rising_edge(wr_clk);
    wr_rst <= '0';
    rd_cycles(5);
    rd_rst <= '0';
    rd_cycles(6);
    wr_cycles(6);
    assert rd_empty = '1' and wr_full = '0' and wr_level = 0 and rd_level = 0
      report "phase 4: FIFO not empty after the mid-traffic reset" severity error;
    assert n_w = 0 and n_r = 0
      report "phase 4: occupancy counters not cleared" severity error;
    report "phase 4: mid-traffic reset leaves the FIFO empty, taps 0 -- OK";
    -- fresh stream: any pre-reset residue would break the LFSR sequence
    wr_quota <= C_N_POST;
    rd_quota <= C_N_POST;
    wr_mode  <= 2;
    rd_mode  <= 2;
    wait until rd_count = C_N_POST for 5 ms;
    assert rd_count = C_N_POST
      report "phase 4: post-reset stream stalled at " & integer'image(rd_count)
      severity failure;
    wr_mode <= 0;
    rd_mode <= 0;
    rd_cycles(4);
    wr_cycles(6);
    assert rd_errors = 0 report "phase 4: data errors after reset" severity error;
    assert rd_empty = '1' and wr_level = 0 and rd_level = 0
      report "phase 4: FIFO not empty after the post-reset stream" severity error;
    report "phase 4: " & integer'image(C_N_POST) & " post-reset words in order -- OK";

    report "physical_1581_wfifo: " & integer'image(4 + C_N_MAIN + C_N_POST)
           & "+ words checked, level taps bounded -- TEST PASSED";
    finish;
  end process;

end architecture sim;
