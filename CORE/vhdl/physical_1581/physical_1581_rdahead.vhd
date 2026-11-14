-------------------------------------------------------------------------------
-- physical_1581_rdahead.vhd
--
-- Read-ahead buffer of the physical internal 1581 read path (issue #257), on
-- the 50 MHz controller clock.
--
-- The 1581 DOS reads a track side with ten single Read Sector commands in
-- rotational order, and the WD front end presents a sector to the drive CPU
-- at disk pace, only after the controller has checked its data CRC. The
-- request for the next sector therefore arrives one sector time late: the ID
-- of that sector has passed and its data field is on its way. This engine
-- listens to the decoder's record stream between two requests and captures
-- the sector that passes into a 512-byte buffer of its own, so that the
-- controller can serve a matching request from the buffer instead of waiting
-- a whole revolution for the ID to come round again.
--
-- A sector is held only if everything about it is in order: a CRC-valid ID
-- with N = 2, its data mark within the DAM timeout, exactly 512 data bytes
-- and a good data CRC. Whatever else happens leaves nothing held. There is
-- one buffer: the next data mark that starts a capture releases the held
-- sector (hold_v_o falls with that data mark, not earlier). A held sector
-- that no capture replaces is released G_DATA_WD_CYC after its own data mark
-- (24 ms): the buffer never offers a byte that left the disk longer ago than
-- that, however long the engine runs and whatever passes under the head.
--
-- The engine knows nothing about the mechanism. The controller arms it after
-- a clean Read Sector (arm_i) and switches it off with every event after
-- which the flux under the head is no longer the flux the buffer was filled
-- from (kill_i: a step, a side change, a motor stop, a disk change, a write,
-- a decoder reset, ...). kill_i wins over everything else in the same clock.
--
-- States:
--   S_OFF   not armed; nothing is captured, nothing is held.
--   S_HUNT  waiting for a CRC-valid ID with N = 2 (the candidate).
--   S_DAM   candidate latched, waiting for its data mark. Another candidate
--           ID replaces it; any other ID or the DAM timeout returns to S_HUNT.
--           A data mark while busy_i is high is skipped (the controller is
--           reading the buffer out).
--   S_DATA  taking the data field. The capture is abandoned on an ID (the
--           decoder re-anchored in the middle of the field), on a 513th
--           byte, on a second data mark and when G_DATA_WD_CYC have passed
--           since its data mark (a loss of lock ends a field without
--           data_end_i); it becomes the held sector on data_end_i with a
--           good CRC after exactly 512 bytes.
-- cap_v_o is high in S_DAM and S_DATA: the sector cap_c_o / cap_r_o is on its
-- way into the buffer, and a requester may wait for it.
--
-- The buffer is a plain 512 x 8 array with one synchronous write port and one
-- synchronous read port (rd_data_o shows the byte at rd_addr_i one clock
-- later), so that it maps to a block RAM or to distributed RAM. Its contents
-- only mean something while hold_v_o is high.
--
-- C64MEGA65 project, GPLv3.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_rdahead is
  generic (
    G_DAM_TIMEOUT_CYC : natural := 68_800;      -- ID to data mark: 43 decoded byte-times
    -- 24 ms from a data mark: the longest a capture may take (a 512-byte data
    -- field with its CRC at 10 % under speed fits) and the longest a sector
    -- is held
    G_DATA_WD_CYC     : natural := 1_200_000
  );
  port (
    clk_i             : in  std_logic;          -- 50 MHz controller clock
    rst_i             : in  std_logic;

    arm_i             : in  std_logic;          -- 1-cycle pulse: start capturing (ignored unless the engine is off)
    kill_i            : in  std_logic;          -- engine off, buffer invalid; wins over everything in the same clock
    busy_i            : in  std_logic;          -- level: the buffer is being read out, no capture may start to write
    consume_i         : in  std_logic;          -- 1-cycle pulse: the held sector was delivered, forget it

    -- decoder record stream (physical_1581_mfm_decoder)
    id_valid_i        : in  std_logic;
    id_crc_ok_i       : in  std_logic;
    id_c_i            : in  unsigned(7 downto 0);
    id_h_i            : in  unsigned(7 downto 0);
    id_r_i            : in  unsigned(7 downto 0);
    id_n_i            : in  unsigned(7 downto 0);
    data_start_i      : in  std_logic;
    data_byte_i       : in  unsigned(7 downto 0);
    data_byte_valid_i : in  std_logic;
    data_end_i        : in  std_logic;
    data_crc_ok_i     : in  std_logic;          -- valid at data_end_i
    data_deleted_i    : in  std_logic;          -- valid at data_end_i

    -- held sector: complete, data CRC good, exactly 512 bytes
    hold_v_o          : out std_logic;
    hold_c_o          : out unsigned(7 downto 0);
    hold_h_o          : out unsigned(7 downto 0);
    hold_r_o          : out unsigned(7 downto 0);
    hold_n_o          : out unsigned(7 downto 0);
    hold_deleted_o    : out std_logic;

    -- capture in flight: waiting for the data mark of this ID or taking its data
    cap_v_o           : out std_logic;
    cap_c_o           : out unsigned(7 downto 0);
    cap_r_o           : out unsigned(7 downto 0);

    -- buffer read port, synchronous
    rd_addr_i         : in  unsigned(8 downto 0);
    rd_data_o         : out unsigned(7 downto 0) := (others => '0');

    -- observation
    active_o          : out std_logic           -- the engine is armed (not off)
  );
end entity physical_1581_rdahead;

architecture rtl of physical_1581_rdahead is

  constant C_SECTOR_BYTES : natural := 512;

  type st_t is (S_OFF, S_HUNT, S_DAM, S_DATA);
  signal st : st_t := S_OFF;

  -- candidate ID (the capture in flight)
  signal cand_c, cand_h, cand_r, cand_n : unsigned(7 downto 0) := (others => '0');

  -- held sector
  signal hold_v       : std_logic := '0';
  signal hold_c, hold_h, hold_r, hold_n : unsigned(7 downto 0) := (others => '0');
  signal hold_deleted : std_logic := '0';

  signal dam_cnt : natural range 0 to G_DAM_TIMEOUT_CYC := 0;   -- ID to data mark
  signal wd_cnt  : natural range 0 to G_DATA_WD_CYC := 0;       -- clocks left of the 24 ms after the last data mark that started a capture
  signal cnt     : unsigned(9 downto 0) := (others => '0');     -- bytes stored, 0 .. 512

  -- the buffer: no reset, written through one port, read through one port
  type mem_t is array (0 to C_SECTOR_BYTES - 1) of unsigned(7 downto 0);
  signal mem    : mem_t := (others => (others => '0'));
  signal mem_we : std_logic;

begin

  hold_v_o       <= hold_v;
  hold_c_o       <= hold_c;
  hold_h_o       <= hold_h;
  hold_r_o       <= hold_r;
  hold_n_o       <= hold_n;
  hold_deleted_o <= hold_deleted;

  cap_v_o  <= '1' when st = S_DAM or st = S_DATA else '0';
  cap_c_o  <= cand_c;
  cap_r_o  <= cand_r;
  active_o <= '0' when st = S_OFF else '1';

  ---------------------------------------------------------------------------
  -- capture FSM. Priority within one clock: reset / kill, then consume (it
  -- wins over a capture that completes in the same clock), then the state
  -- rules in the order they are written. wd_cnt runs from every data mark
  -- that starts a capture, in every state of the running engine: it ends a
  -- capture that takes too long, and it releases the sector that capture
  -- left in the buffer.
  ---------------------------------------------------------------------------
  fsm_p : process (clk_i)
    variable v_id_cand : boolean;

    -- a CRC-valid ID with N = 2 becomes the candidate; any other ID does not
    procedure take_id is
    begin
      if v_id_cand then
        cand_c  <= id_c_i;
        cand_h  <= id_h_i;
        cand_r  <= id_r_i;
        cand_n  <= id_n_i;
        dam_cnt <= G_DAM_TIMEOUT_CYC;
        st      <= S_DAM;
      else
        st      <= S_HUNT;
      end if;
    end procedure;
  begin
    if rising_edge(clk_i) then
      v_id_cand := id_crc_ok_i = '1' and id_n_i = C_SIZECODE_512;

      -- pragma translate_off
      assert not (busy_i = '1' and st = S_DATA)
        report "physical_1581_rdahead: busy_i while a capture is writing the buffer"
        severity error;
      -- pragma translate_on

      if rst_i = '1' or kill_i = '1' then
        st     <= S_OFF;
        hold_v <= '0';
      else
        if wd_cnt /= 0 then
          wd_cnt <= wd_cnt - 1;
        end if;

        case st is
          when S_OFF =>
            if arm_i = '1' then
              st <= S_HUNT;
            end if;

          when S_HUNT =>
            if id_valid_i = '1' then
              take_id;
            end if;

          when S_DAM =>
            if dam_cnt /= 0 then
              dam_cnt <= dam_cnt - 1;
            end if;
            if data_start_i = '1' then
              if busy_i = '1' then
                st <= S_HUNT;                  -- the buffer is being read out: skip this record
              else
                hold_v <= '0';                 -- the buffer is about to be overwritten
                cnt    <= (others => '0');
                wd_cnt <= G_DATA_WD_CYC;
                st     <= S_DATA;
              end if;
            elsif id_valid_i = '1' then
              take_id;                         -- a new candidate reloads the timer
            elsif dam_cnt = 0 then
              st <= S_HUNT;
            end if;

          when S_DATA =>
            if id_valid_i = '1' then
              take_id;                         -- the field was cut short by an ID
            elsif data_end_i = '1' then
              if data_crc_ok_i = '1' and cnt = C_SECTOR_BYTES then
                hold_v       <= '1';
                hold_c       <= cand_c;
                hold_h       <= cand_h;
                hold_r       <= cand_r;
                hold_n       <= cand_n;
                hold_deleted <= data_deleted_i;
              end if;
              st <= S_HUNT;
            elsif data_byte_valid_i = '1' then
              if cnt /= C_SECTOR_BYTES then
                cnt <= cnt + 1;                -- stored by ram_p in this clock
              else
                st <= S_HUNT;                  -- a 513th byte
              end if;
            elsif data_start_i = '1' then
              st <= S_HUNT;
            elsif wd_cnt = 0 then
              st <= S_HUNT;
            end if;
        end case;

        -- the held sector has become G_DATA_WD_CYC old
        if hold_v = '1' and wd_cnt = 0 then
          hold_v <= '0';
        end if;

        if consume_i = '1' then
          hold_v <= '0';
        end if;
      end if;
    end if;
  end process fsm_p;

  ---------------------------------------------------------------------------
  -- buffer. A byte is written while a capture takes data; every clock in
  -- which the FSM does not count a written byte also ends the capture without
  -- a held sector, so the write enable needs none of the FSM's priorities.
  ---------------------------------------------------------------------------
  mem_we <= '1' when st = S_DATA and data_byte_valid_i = '1' and cnt /= C_SECTOR_BYTES else '0';

  ram_p : process (clk_i)
  begin
    if rising_edge(clk_i) then
      if mem_we = '1' then
        mem(to_integer(cnt(8 downto 0))) <= data_byte_i;
      end if;
      rd_data_o <= mem(to_integer(rd_addr_i));
    end if;
  end process ram_p;

end architecture rtl;
