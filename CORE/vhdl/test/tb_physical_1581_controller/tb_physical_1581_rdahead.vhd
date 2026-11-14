-------------------------------------------------------------------------------
-- tb_physical_1581_rdahead.vhd
--
-- Unit test of physical_1581_rdahead, the read-ahead buffer of the physical
-- internal 1581 (issue #257). The engine is driven with a synthetic record
-- stream (the decoder's strobes, no flux), with short timeouts
-- (G_DAM_TIMEOUT_CYC = 40, G_DATA_WD_CYC = 3000), and every rule of the
-- engine has a check that fails when the rule is broken:
--   * off after reset; records are ignored while off; arm_i starts the hunt
--     and is ignored in every other state,
--   * an ID becomes the candidate only with a good CRC and N = 2, and the
--     candidate is latched at id_valid_i,
--   * the DAM timeout to the clock; a second candidate replaces the first and
--     reloads the timer; any other ID drops the candidate,
--   * a data mark while busy_i is high is skipped and leaves the held sector
--     alone; busy_i has no other effect,
--   * the held sector falls with the data mark of the next capture, not with
--     its ID; a capture that fails after that leaves nothing held,
--   * 512 bytes and a good CRC are held with the candidate's C/H/R/N and the
--     deleted flag of the data_end_i clock; 511 bytes, 513 bytes, a bad CRC,
--     an ID inside the field, a second data mark and the data watchdog (to
--     the clock) are not,
--   * a held sector is released G_DATA_WD_CYC after its own data mark, to
--     the clock: the data mark of the next capture starts that time anew, a
--     skipped data mark and a candidate ID do not; the release leaves the
--     candidate, the engine and the bytes of the buffer alone, and busy_i
--     keeps protecting the buffer when nothing is held any more,
--   * consume_i releases the held sector, the engine keeps running, and it
--     wins over a capture that completes in the same clock,
--   * kill_i and rst_i in every state, as a level, together with arm_i and
--     together with a completing capture,
--   * the read port: registered, returns the captured bytes, and keeps them
--     across kill_i (the controller finishes a copy it has started).
-- The data bus and the ID bus carry other values outside their strobes, so an
-- engine that samples them at the wrong time fails as well.
--
-- A failed check reports "FAIL <tag>" and the run goes on, so one run names
-- every check a broken engine violates; the last line is the verdict.
--
-- Run (B = absolute scratch workdir, from a scratch directory):
--   ghdl -a --std=08 --workdir=B \
--     CORE/vhdl/physical_1581/physical_1581_pkg.vhd \
--     CORE/vhdl/physical_1581/physical_1581_rdahead.vhd \
--     CORE/vhdl/test/tb_physical_1581_controller/tb_physical_1581_rdahead.vhd
--   ghdl --elab-run --std=08 --workdir=B tb_physical_1581_rdahead
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_physical_1581_rdahead is
end entity;

architecture sim of tb_physical_1581_rdahead is
  constant C_DAM : natural := 40;       -- G_DAM_TIMEOUT_CYC of the DUT
  -- G_DATA_WD_CYC of the DUT. The sector that check F2 leaves in the buffer
  -- is still needed by check H4, about 2200 clocks after its data mark.
  constant C_WD  : natural := 3000;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal arm, kill, busy, consume : std_logic := '0';
  signal id_valid, id_crc_ok : std_logic := '0';
  signal id_c, id_h, id_r, id_n : unsigned(7 downto 0) := (others => '0');
  signal data_start, data_byte_valid, data_end : std_logic := '0';
  signal data_crc_ok, data_deleted : std_logic := '0';
  signal data_byte : unsigned(7 downto 0) := (others => '0');

  signal hold_v, hold_deleted, cap_v, active : std_logic;
  signal hold_c, hold_h, hold_r, hold_n, cap_c, cap_r : unsigned(7 downto 0);
  signal rd_addr : unsigned(8 downto 0) := (others => '0');
  signal rd_data : unsigned(7 downto 0);

  -- payload byte i of the synthetic sector with this seed
  function pay(seed, i : integer) return unsigned is
  begin
    return to_unsigned((seed * 37 + i * 11 + (i / 256) * 5 + 3) mod 256, 8);
  end function;
begin

  clk <= not clk after 10 ns;

  dut : entity work.physical_1581_rdahead
    generic map (G_DAM_TIMEOUT_CYC => C_DAM, G_DATA_WD_CYC => C_WD)
    port map (
      clk_i => clk, rst_i => rst,
      arm_i => arm, kill_i => kill, busy_i => busy, consume_i => consume,
      id_valid_i => id_valid, id_crc_ok_i => id_crc_ok,
      id_c_i => id_c, id_h_i => id_h, id_r_i => id_r, id_n_i => id_n,
      data_start_i => data_start, data_byte_i => data_byte,
      data_byte_valid_i => data_byte_valid, data_end_i => data_end,
      data_crc_ok_i => data_crc_ok, data_deleted_i => data_deleted,
      hold_v_o => hold_v, hold_c_o => hold_c, hold_h_o => hold_h, hold_r_o => hold_r,
      hold_n_o => hold_n, hold_deleted_o => hold_deleted,
      cap_v_o => cap_v, cap_c_o => cap_c, cap_r_o => cap_r,
      rd_addr_i => rd_addr, rd_data_o => rd_data,
      active_o => active
    );

  stim : process
    variable fails : integer := 0;

    -- n clocks; the DUT has taken the inputs that were set before, and its
    -- outputs show the result
    procedure step(n : natural := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
      end loop;
      wait for 1 ns;
    end procedure;

    procedure chk(ok : boolean; tag : string) is
    begin
      if ok then
        report "  ok   " & tag;
      else
        report "FAIL " & tag severity error;
        fails := fails + 1;
      end if;
    end procedure;

    procedure pulse(signal s : out std_logic) is
    begin
      s <= '1'; step; s <= '0';
    end procedure;

    -- an ID field: one id_valid_i clock; the bus shows something else afterwards
    procedure send_id(c, h, r, n : integer; ok : std_logic) is
    begin
      id_c <= to_unsigned(c, 8); id_h <= to_unsigned(h, 8);
      id_r <= to_unsigned(r, 8); id_n <= to_unsigned(n, 8);
      id_crc_ok <= ok; id_valid <= '1';
      step;
      id_valid <= '0'; id_crc_ok <= not ok;
      id_c <= x"EE"; id_h <= x"EE"; id_r <= x"EE"; id_n <= x"EE";
    end procedure;

    -- n payload bytes of a seed, `gap` idle clocks after each
    procedure send_bytes(n, seed : integer; gap : natural := 0) is
    begin
      for i in 0 to n - 1 loop
        data_byte <= pay(seed, i); data_byte_valid <= '1';
        step;
        data_byte_valid <= '0'; data_byte <= not pay(seed, i);
        if gap /= 0 then step(gap); end if;
      end loop;
    end procedure;

    -- data_end_i with its two flags, which are valid in that clock only
    procedure send_end(ok, del : std_logic) is
    begin
      data_crc_ok <= ok; data_deleted <= del; data_end <= '1';
      step;
      data_end <= '0'; data_crc_ok <= not ok; data_deleted <= not del;
    end procedure;

    -- a complete record: ID, gap, data mark, n bytes, data end
    procedure send_sector(c, h, r, n, seed, nbytes : integer; ok, del : std_logic) is
    begin
      send_id(c, h, r, n, '1');
      step(3);
      pulse(data_start);
      send_bytes(nbytes, seed);
      step(2);
      send_end(ok, del);
    end procedure;

    impure function held(c, h, r, n : integer; del : std_logic) return boolean is
    begin
      return hold_v = '1' and hold_c = c and hold_h = h and hold_r = r and hold_n = n
             and hold_deleted = del;
    end function;

    -- read the whole buffer through the read port
    procedure chk_buf(seed : integer; tag : string) is
      variable bad : integer := 0;
    begin
      for i in 0 to 511 loop
        rd_addr <= to_unsigned(i, 9);
        step;
        if rd_data /= pay(seed, i) then bad := bad + 1; end if;
      end loop;
      chk(bad = 0, tag & " (" & integer'image(bad) & " bytes differ)");
    end procedure;

    procedure do_kill is
    begin
      pulse(kill);
    end procedure;

    -- off -> hunting
    procedure do_arm is
    begin
      pulse(arm);
    end procedure;
  begin
    step(3);
    rst <= '0';
    step;

    ---------------------------------------------------------------------------
    report "--- rule 1/3: reset state, off, arm";
    chk(active = '0' and hold_v = '0' and cap_v = '0', "A1 off after reset");
    send_sector(1, 0, 1, 2, 1, 512, '1', '0');
    chk(active = '0' and hold_v = '0' and cap_v = '0', "A2 a record is ignored while off");
    do_arm;
    chk(active = '1' and hold_v = '0' and cap_v = '0', "A3 arm_i starts the hunt");

    ---------------------------------------------------------------------------
    report "--- rule 4: which ID becomes the candidate";
    send_id(5, 0, 3, 2, '0');
    chk(cap_v = '0', "B1 an ID with a bad CRC is no candidate");
    send_id(5, 0, 3, 1, '1');
    chk(cap_v = '0', "B2 an ID with N = 1 is no candidate");
    send_id(5, 0, 3, 3, '1');
    chk(cap_v = '0', "B3 an ID with N = 3 is no candidate");
    pulse(data_start);
    send_bytes(512, 2);
    send_end('1', '0');
    chk(hold_v = '0' and cap_v = '0', "B4 a data field without a candidate is not captured");
    send_id(5, 1, 3, 2, '1');
    chk(cap_v = '1' and cap_c = 5 and cap_r = 3, "B5 a CRC-valid ID with N = 2 is the candidate");
    step(5);
    chk(cap_v = '1' and cap_c = 5 and cap_r = 3, "B6 the candidate was latched at id_valid_i");
    chk(hold_v = '0', "B7 a candidate alone holds nothing");

    ---------------------------------------------------------------------------
    report "--- rule 3: arm_i is ignored unless the engine is off";
    pulse(arm);
    chk(cap_v = '1' and cap_r = 3, "C1 arm_i in S_DAM leaves the candidate alone");
    pulse(data_start);
    send_bytes(200, 3);
    pulse(arm);
    chk(cap_v = '1', "C2 arm_i in S_DATA leaves the capture alone");
    send_bytes(312, 3);            -- continues the count: bytes 200 .. 511 carry pay(3, 0 .. 311)
    send_end('1', '0');
    chk(held(5, 1, 3, 2, '0'), "C3 the capture completed across arm_i (512 bytes counted)");

    ---------------------------------------------------------------------------
    report "--- rule 6: a clean sector is held, the read port returns it";
    do_kill;
    chk(active = '0' and hold_v = '0' and cap_v = '0', "D0 kill_i switches the engine off");
    do_arm;
    send_sector(39, 1, 7, 2, 4, 512, '1', '1');
    chk(held(39, 1, 7, 2, '1'), "D1 512 bytes and a good CRC are held with C/H/R/N and the deleted flag");
    chk(cap_v = '0' and active = '1', "D2 after a capture the engine hunts again");
    chk_buf(4, "D3 the read port returns the captured bytes");
    rd_addr <= to_unsigned(17, 9);
    step;
    rd_addr <= to_unsigned(300, 9);
    wait for 5 ns;
    chk(rd_data = pay(4, 17), "D4 the read data is registered (address 17 still shown)");
    step;
    chk(rd_data = pay(4, 300), "D5 the read data follows the address one clock later");

    ---------------------------------------------------------------------------
    report "--- rule 5: the held sector falls with the next data mark, not earlier";
    send_id(39, 1, 8, 2, '1');
    chk(hold_v = '1' and hold_r = 7 and cap_v = '1' and cap_r = 8, "E1 held sector and candidate side by side");
    step(10);
    chk(hold_v = '1' and hold_r = 7, "E2 the held sector survives the wait for the data mark");
    pulse(data_start);
    chk(hold_v = '0' and cap_v = '1', "E3 the data mark of the next capture releases the held sector");
    send_bytes(100, 5);
    send_id(39, 1, 9, 1, '1');     -- the field is cut short by an ID that is no candidate
    chk(hold_v = '0' and cap_v = '0', "E4 a capture that fails after the data mark leaves nothing held");

    ---------------------------------------------------------------------------
    report "--- rule 5: DAM timeout, to the clock";
    -- after the ID's clock the data mark is accepted for C_DAM + 1 more clocks
    send_id(1, 0, 1, 2, '1');
    step(C_DAM);
    chk(cap_v = '1', "F1 candidate alive after C_DAM clocks");
    pulse(data_start);             -- taken in clock C_DAM + 1
    send_bytes(512, 6);
    send_end('1', '0');
    chk(held(1, 0, 1, 2, '0'), "F2 a data mark in the last clock of the DAM timeout is taken");
    send_id(1, 0, 2, 2, '1');
    step(C_DAM + 1);
    chk(cap_v = '0', "F3 the candidate is dropped after the DAM timeout");
    chk(hold_v = '1' and hold_r = 1, "F4 the DAM timeout leaves the held sector alone");
    pulse(data_start);
    chk(hold_v = '1' and cap_v = '0', "F5 a data mark after the timeout starts nothing");
    send_bytes(512, 7);
    send_end('1', '0');
    chk(held(1, 0, 1, 2, '0'), "F6 a data field after the timeout is not captured");
    chk_buf(6, "F7 the buffer still holds the sector of F2");

    ---------------------------------------------------------------------------
    report "--- rule 5: another ID while waiting for the data mark";
    send_id(1, 0, 3, 2, '1');
    step(C_DAM - 5);
    send_id(1, 0, 4, 2, '1');      -- a second candidate replaces the first ...
    chk(cap_v = '1' and cap_r = 4, "G1 a second candidate replaces the first");
    step(C_DAM);                   -- ... and reloads the timer
    chk(cap_v = '1' and cap_r = 4, "G2 the second candidate reloaded the DAM timer");
    send_id(1, 0, 5, 2, '1');
    send_id(1, 0, 5, 2, '0');      -- long before the timeout of the candidate
    chk(cap_v = '0', "G3 an ID with a bad CRC drops the candidate");
    send_id(1, 0, 6, 2, '1');
    send_id(1, 0, 7, 0, '1');
    chk(cap_v = '0', "G4 an ID with N /= 2 drops the candidate");
    chk(hold_v = '1' and hold_r = 1, "G5 IDs alone never touch the held sector");

    ---------------------------------------------------------------------------
    report "--- rule 5: busy_i";
    busy <= '1';
    send_id(1, 0, 8, 2, '1');
    chk(cap_v = '1' and cap_r = 8, "H1 busy_i does not keep an ID from becoming the candidate");
    pulse(data_start);
    chk(cap_v = '0', "H2 a data mark while busy_i is high is skipped");
    chk(hold_v = '1' and hold_r = 1, "H3 the skipped data mark leaves the held sector alone");
    busy <= '0';
    send_bytes(512, 8);
    send_end('1', '0');
    chk(held(1, 0, 1, 2, '0'), "H4 the skipped record is not captured");
    chk_buf(6, "H5 the buffer was not written while busy_i was high");
    send_id(1, 0, 9, 2, '1');
    busy <= '1'; step(3); busy <= '0';
    pulse(data_start);
    send_bytes(512, 9);
    send_end('1', '0');
    chk(held(1, 0, 9, 2, '0'), "H6 busy_i before the data mark does not matter");
    chk_buf(9, "H7 the second capture overwrote the buffer");

    ---------------------------------------------------------------------------
    report "--- rule 6: what is not held";
    send_sector(2, 0, 1, 2, 10, 511, '1', '0');
    chk(hold_v = '0' and cap_v = '0', "I1 511 bytes are not held");
    send_id(2, 0, 2, 2, '1');
    pulse(data_start);
    send_bytes(512, 11);
    chk(cap_v = '1', "I2 512 bytes: the capture waits for the data end");
    send_bytes(1, 11);
    chk(cap_v = '0', "I3 the 513th byte ends the capture");
    send_end('1', '0');
    chk(hold_v = '0', "I4 513 bytes are not held");
    send_sector(2, 0, 3, 2, 12, 512, '0', '0');
    chk(hold_v = '0' and cap_v = '0', "I5 a bad data CRC is not held");
    send_sector(2, 0, 4, 2, 13, 512, '1', '0');
    chk(held(2, 0, 4, 2, '0'), "I6 the next clean sector is held (the engine kept running)");

    ---------------------------------------------------------------------------
    report "--- rule 6: an ID in the middle of the data field";
    send_id(2, 0, 5, 2, '1');
    pulse(data_start);
    send_bytes(300, 14);
    send_id(2, 0, 6, 2, '1');      -- the decoder re-anchored on a valid ID
    chk(cap_v = '1' and cap_r = 6 and hold_v = '0', "J1 a candidate ID inside the field replaces the capture");
    send_bytes(20, 14);            -- no data mark was seen for sector 6: these are nobody's bytes
    send_end('1', '0');
    chk(hold_v = '0' and cap_v = '1' and cap_r = 6, "J2 the cut field is not held, the new candidate waits");
    pulse(data_start);
    send_bytes(512, 15);
    send_end('1', '0');
    chk(held(2, 0, 6, 2, '0'), "J3 the sector of the new candidate is held");
    chk_buf(15, "J4 with its own bytes from address 0");
    send_id(2, 0, 7, 2, '1');
    pulse(data_start);
    send_bytes(300, 16);
    send_id(2, 0, 8, 2, '0');      -- an ID that is no candidate
    chk(cap_v = '0' and hold_v = '0', "J5 any other ID inside the field ends the capture");
    send_bytes(212, 16);
    send_end('1', '0');
    chk(hold_v = '0', "J6 and its field is not held");

    ---------------------------------------------------------------------------
    report "--- rule 6: a second data mark";
    send_id(2, 0, 9, 2, '1');
    pulse(data_start);
    send_bytes(10, 17);
    pulse(data_start);
    chk(cap_v = '0', "K1 a second data mark ends the capture");
    send_bytes(512, 17);
    send_end('1', '0');
    chk(hold_v = '0', "K2 and nothing is held");

    ---------------------------------------------------------------------------
    report "--- rule 6: data watchdog, to the clock";
    -- after the data mark's clock, data_end_i is taken for C_WD + 1 more clocks
    send_id(3, 0, 1, 2, '1');
    pulse(data_start);
    send_bytes(512, 18, 1);                        -- 1024 clocks
    step(C_WD - 1024);
    chk(cap_v = '1', "L1 capture alive after C_WD clocks");
    send_end('1', '0');                            -- taken in clock C_WD + 1
    chk(held(3, 0, 1, 2, '0'), "L2 a data end in the last clock of the watchdog is taken");
    step;
    chk(hold_v = '0', "L2b a sector that was completed in that clock is released in the next");
    send_id(3, 0, 2, 2, '1');
    pulse(data_start);
    send_bytes(512, 19, 1);
    step(C_WD - 1024 + 1);
    chk(cap_v = '0', "L3 the watchdog ends a capture without a data end");
    send_end('1', '0');
    chk(hold_v = '0', "L4 a data end after the watchdog holds nothing");

    ---------------------------------------------------------------------------
    report "--- rule 6: the deleted flag is the one of the data end";
    send_sector(3, 0, 3, 2, 20, 512, '1', '0');
    chk(held(3, 0, 3, 2, '0'), "M1 normal data mark");
    send_sector(3, 0, 4, 2, 21, 512, '1', '1');
    chk(held(3, 0, 4, 2, '1'), "M2 deleted data mark");
    step(4);
    chk(held(3, 0, 4, 2, '1'), "M3 the flag was latched at data_end_i");

    ---------------------------------------------------------------------------
    report "--- a held sector lives for C_WD clocks after its data mark, to the clock";
    -- clock 0 is the clock of the data mark: the sector is held up to and
    -- including clock C_WD and released in clock C_WD + 1
    send_id(5, 0, 1, 2, '1');
    pulse(data_start);                             -- clock 0
    send_bytes(512, 31);                           -- clocks 1 .. 512
    send_end('1', '0');                            -- clock 513
    chk(held(5, 0, 1, 2, '0'), "P1 held after the data end");
    step(C_WD - 513 - 10);                         -- clock C_WD - 10
    send_id(5, 0, 2, 2, '1');                      -- clock C_WD - 9: a candidate that waits while the sector is released
    step(9);                                       -- clock C_WD
    chk(held(5, 0, 1, 2, '0') and cap_v = '1' and cap_r = 2, "P2 still held C_WD clocks after the data mark");
    step;                                          -- clock C_WD + 1
    chk(hold_v = '0', "P3 released in the next clock");
    chk(cap_v = '1' and cap_r = 2 and active = '1', "P4 the release leaves the candidate and the engine alone");
    chk_buf(31, "P5 the buffer keeps its bytes when the sector is released");
    -- The time belongs to the data mark that filled the buffer: the data mark
    -- of the next capture starts it anew, a skipped data mark (busy_i) does
    -- not. Sector 3, and 1115 clocks after its data mark the one of sector 4.
    send_id(5, 0, 3, 2, '1');
    pulse(data_start);                             -- clock 0 of sector 3
    send_bytes(512, 32);
    send_end('1', '0');                            -- clock 513
    step(600);                                     -- clock 1113
    send_id(5, 0, 4, 2, '1');                      -- clock 1114
    pulse(data_start);                             -- clock 1115 of sector 3 = clock 0 of sector 4
    send_bytes(512, 33);
    send_end('1', '0');                            -- clock 513 of sector 4
    chk(held(5, 0, 4, 2, '0'), "P6 the next sector is held");
    busy <= '1';
    send_id(5, 0, 5, 2, '1');                      -- clock 514 of sector 4
    pulse(data_start);                             -- clock 515 of sector 4: skipped
    busy <= '0';
    chk(held(5, 0, 4, 2, '0') and cap_v = '0', "P7 a skipped data mark leaves the sector held");
    step(C_WD + 1 - 1115 - 515);                   -- clock C_WD + 1 of sector 3 = clock C_WD - 1114 of sector 4
    chk(held(5, 0, 4, 2, '0'), "P8 the time of the sector before does not release it");
    step(1114);                                    -- clock C_WD of sector 4
    chk(held(5, 0, 4, 2, '0'), "P9 held C_WD clocks after its own data mark");
    step;                                          -- clock C_WD + 1 of sector 4
    chk(hold_v = '0', "P10 released in the next clock (the skipped data mark did not start the time anew)");
    -- busy_i protects the buffer also when nothing is held any more: the time
    -- of a sector can run out while the controller copies it
    busy <= '1';
    send_id(5, 0, 7, 2, '1');
    pulse(data_start);
    chk(cap_v = '0' and hold_v = '0', "P11 a data mark while busy_i is high is skipped also when nothing is held");
    send_bytes(512, 35);
    send_end('1', '0');
    busy <= '0';
    chk(hold_v = '0', "P12 the skipped record is not held");
    chk_buf(33, "P13 and the buffer was not written");
    send_sector(5, 0, 6, 2, 34, 512, '1', '0');
    chk(held(5, 0, 6, 2, '0'), "P14 the next sector is captured without a new arm_i");

    ---------------------------------------------------------------------------
    report "--- rule 2: consume_i";
    pulse(consume);
    chk(hold_v = '0', "N1 consume_i releases the held sector");
    chk(active = '1', "N2 the engine keeps running after consume_i");
    send_sector(3, 0, 5, 2, 22, 512, '1', '0');
    chk(held(3, 0, 5, 2, '0'), "N3 the next sector is captured without a new arm_i");
    send_id(3, 0, 6, 2, '1');
    pulse(consume);
    chk(hold_v = '0' and cap_v = '1' and cap_r = 6, "N4 consume_i leaves the candidate alone");
    pulse(data_start);
    send_bytes(256, 23);
    pulse(consume);
    send_bytes(256, 23);           -- continues the count: bytes 256 .. 511 carry pay(23, 0 .. 255)
    send_end('1', '0');
    chk(held(3, 0, 6, 2, '0'), "N5 consume_i during a capture does not disturb it");
    -- consume_i in the clock of a completing capture: consume wins
    send_id(3, 0, 7, 2, '1');
    pulse(data_start);
    send_bytes(512, 24);
    consume <= '1';
    send_end('1', '0');
    consume <= '0';
    chk(hold_v = '0' and cap_v = '0', "N6 consume_i wins over a capture that completes in the same clock");

    ---------------------------------------------------------------------------
    report "--- rule 1: kill_i and rst_i";
    do_kill;
    chk(active = '0', "O1 kill_i while hunting");
    do_arm;
    send_id(4, 0, 1, 2, '1');
    do_kill;
    chk(active = '0' and cap_v = '0', "O2 kill_i with a candidate");
    pulse(data_start);
    send_bytes(512, 25);
    send_end('1', '0');
    chk(hold_v = '0' and active = '0', "O3 the record of a killed candidate is not captured");
    do_arm;
    send_id(4, 0, 2, 2, '1');
    pulse(data_start);
    send_bytes(300, 26);
    do_kill;
    chk(active = '0' and cap_v = '0', "O4 kill_i during a capture");
    send_bytes(212, 26);
    send_end('1', '0');
    chk(hold_v = '0', "O5 a killed capture holds nothing");
    do_arm;
    send_sector(4, 0, 3, 2, 27, 512, '1', '0');
    chk(held(4, 0, 3, 2, '0'), "O6 held again after a new arm_i");
    do_kill;
    chk(hold_v = '0' and active = '0', "O7 kill_i releases the held sector");
    chk_buf(27, "O8 the buffer keeps its bytes across kill_i");
    -- kill together with arm
    kill <= '1'; arm <= '1'; step; kill <= '0'; arm <= '0';
    chk(active = '0', "O9 kill_i wins over arm_i in the same clock");
    -- kill together with a completing capture
    do_arm;
    send_id(4, 0, 4, 2, '1');
    pulse(data_start);
    send_bytes(512, 28);
    kill <= '1';
    send_end('1', '0');
    kill <= '0';
    chk(hold_v = '0' and active = '0', "O10 kill_i wins over a capture that completes in the same clock");
    -- kill as a level
    kill <= '1';
    pulse(arm);
    send_sector(4, 0, 5, 2, 29, 512, '1', '0');
    chk(hold_v = '0' and active = '0' and cap_v = '0', "O11 nothing happens while kill_i is high");
    kill <= '0';
    step;
    chk(active = '0', "O12 the engine stays off after kill_i until arm_i");
    -- rst_i with a held sector and a candidate
    do_arm;
    send_sector(4, 0, 6, 2, 30, 512, '1', '0');
    chk(hold_v = '1', "O13 held before the reset");
    send_id(4, 0, 7, 2, '1');
    pulse(rst);
    chk(hold_v = '0' and active = '0' and cap_v = '0', "O14 rst_i acts like kill_i");
    -- kill together with consume: the sector is released and the engine is off
    do_arm;
    send_sector(4, 0, 8, 2, 36, 512, '1', '0');
    chk(hold_v = '1' and active = '1', "O15 held before kill_i and consume_i");
    kill <= '1'; consume <= '1'; step; kill <= '0'; consume <= '0';
    chk(hold_v = '0' and active = '0', "O16 kill_i together with consume_i: released and off");

    ---------------------------------------------------------------------------
    if fails = 0 then
      report "tb_physical_1581_rdahead: ALL TESTS PASSED";
    else
      report "tb_physical_1581_rdahead: " & integer'image(fails) & " CHECKS FAILED" severity failure;
    end if;
    finish;
  end process;

end architecture sim;
