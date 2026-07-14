-------------------------------------------------------------------------------
-- physical_1581_mfm_decoder.vhd
--
-- DD-only, MFM-only sector/ID decoder for the physical internal 1581 read path.
-- Instantiates the adapted read pipeline (gaps -> quantise -> gaps_to_bits ->
-- bits_to_bytes) and a CRC-16 engine, and runs a clean field FSM that recognizes
-- exactly three missing-clock A1 syncs followed by FE (ID), FB (normal data) or
-- F8 (deleted data). It exposes each decoded ID (C/H/R/N + stored/OK CRC) and
-- each decoded data field (streamed bytes + deleted flag + OK CRC). The operation
-- FSM above it does all matching, timing and sequencing.
--
-- Fresh project logic (C64MEGA65); the pipeline sub-stages and CRC it wires are
-- adapted from mega65-core @ a9158930 (Paul Gardner-Stephen / MEGA65).
--
-- CRC coverage: reset at the first of the three A1 syncs, then A1,A1,A1 are fed
-- synthetically (bits_to_bytes signals A1 via sync_o, not a byte), then the mark
-- byte and every field/data byte and the two stored CRC bytes; residue 0 == good.
--
-- SYNC-TRAIN QUALIFIER (issue #90 round 14): the adaptive quantiser remains
-- deliberately tolerant, but a field boundary is accepted only after three
-- non-overlapping missing-clock A1 candidates at their exact MFM spacing.
-- Consecutive A1 bytes produce candidates five quantised gaps apart. The
-- round-12 write-splice junk produced overlapping candidates two gaps apart,
-- so it cannot open a field. Unlike round 13's 00-preamble gate, this tests
-- the address-mark train itself and is formatter-independent: stock 1581
-- media have 12 x 00 before an ID, while the MEGA65 F011 formatter writes an
-- ID immediately after 4E gap bytes. Both still contain the same A1 train.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.physical_1581_pkg.all;

entity physical_1581_mfm_decoder is
  generic (
    -- Test-only knobs for the A/B margin harness (production keeps defaults):
    -- G_SYNC_GATE false + G_QUANT_HUNT_ADAPT_ALL true restores the exact
    -- round-12 behavior. G_SYNC_PREAMBLE_GATE true plus
    -- G_QUANT_HUNT_ADAPT_ALL false selects the superseded round-13 rule for
    -- the permanent A/B regression column. G_QUANT_TOL_ACQ_SHR = 2 selects
    -- the refuted tight-
    -- acquisition variant (see the quantiser entity header).
    G_SYNC_GATE          : boolean := true;
    G_SYNC_PREAMBLE_GATE : boolean := false;
    G_QUANT_TOL_ACQ_SHR  : natural := C_QUANT_TOL_SHR;
    G_QUANT_HUNT_ADAPT_ALL : boolean := true
  );
  port (
    clk_i             : in  std_logic;
    rst_i             : in  std_logic;                    -- sync reset / invalidate
    f_rdata_i         : in  std_logic;                    -- pre-synchronized active-low flux

    -- decoded ID (address-mark) field
    id_valid_o        : out std_logic := '0';             -- 1-cycle pulse at end of ID
    id_c_o            : out unsigned(7 downto 0) := (others => '0');
    id_h_o            : out unsigned(7 downto 0) := (others => '0');
    id_r_o            : out unsigned(7 downto 0) := (others => '0');
    id_n_o            : out unsigned(7 downto 0) := (others => '0');
    id_crc_ok_o       : out std_logic := '0';             -- valid at id_valid_o
    id_crc_stored_o   : out unsigned(15 downto 0) := (others => '0');

    -- decoded data field
    data_start_o      : out std_logic := '0';             -- pulse when DAM recognized
    data_deleted_o    : out std_logic := '0';             -- F8 (valid data_start..data_end)
    data_byte_o       : out unsigned(7 downto 0) := (others => '0');
    data_byte_valid_o : out std_logic := '0';             -- pulse per payload byte
    data_end_o        : out std_logic := '0';             -- pulse after data CRC checked
    data_crc_ok_o     : out std_logic := '0';             -- valid at data_end_o

    -- status / diagnostics
    locked_o          : out std_logic := '0';             -- separator locked
    gap_error_o       : out std_logic := '0';             -- pulse on invalid gap class
    runt_o            : out std_logic := '0';             -- pulse per merged RDATA runt gap
    last_gap_o        : out unsigned(15 downto 0) := (others => '0');
    -- read-only diagnostic tap (issue #90): the live CRC-16 running value. At an
    -- id_valid_o / data_end_o pulse this is the CRC residue of the just-checked
    -- field (x"0000" == good). Purely additive; does not affect decoding.
    crc_value_o       : out unsigned(15 downto 0) := (others => '0');
    -- read-only diagnostic tap (issue #90 round 12): the adaptive quantiser's
    -- live half-cell estimate, Q8.4 (bits 11:4 integer cycles, 3:0 sixteenths).
    -- Purely additive; does not affect decoding.
    est_o             : out unsigned(11 downto 0) := to_unsigned(C_QUANT_EST_NOM_Q, 12)
  );
end entity physical_1581_mfm_decoder;

architecture rtl of physical_1581_mfm_decoder is

  -- pipeline nets
  signal gap_valid   : std_logic;
  signal gap_len     : unsigned(15 downto 0);
  signal q_valid     : std_logic;
  signal q_class     : unsigned(1 downto 0);
  signal bit_valid   : std_logic;
  signal bit_d       : std_logic;
  signal gtb_sync    : std_logic;
  signal byte_sync   : std_logic;
  signal byte_v      : std_logic;
  signal byte_d      : unsigned(7 downto 0);

  -- CRC engine
  signal crc_reset : std_logic := '0';
  signal crc_feed  : std_logic := '0';
  signal crc_byte  : unsigned(7 downto 0) := (others => '0');
  signal crc_ready : std_logic;
  signal crc_value : unsigned(15 downto 0);

  type state_t is (S_IDLE,
                   S_ID_C, S_ID_H, S_ID_R, S_ID_N, S_ID_CRC1, S_ID_CRC2, S_ID_CHECK,
                   S_DATA, S_DATA_CRC1, S_DATA_CRC2, S_DATA_CHECK);
  signal state     : state_t := S_IDLE;
  signal sync_cnt  : integer range 0 to 3 := 0;
  signal data_cnt  : integer range 0 to 2048 := 0;
  signal chk_cnt   : integer range 0 to 15 := 0;
  signal last_n    : unsigned(7 downto 0) := x"02";

  signal id_c_r, id_h_r, id_r_r, id_n_r : unsigned(7 downto 0) := (others => '0');
  signal crc_stored_r : unsigned(15 downto 0) := (others => '0');
  signal deleted_r    : std_logic := '0';

  -- Sync qualification state. The round-13 preamble counters remain only for
  -- the test-selectable historical column; production uses sync_gap_age.
  signal field_active : std_logic;
  signal short_run    : integer range 0 to 255 := 0;  -- consecutive short-class gaps
  -- gaps since a >= C_QUANT_SYNC_RUN shorts run last ended; saturates at 15
  -- (= gate closed; C_QUANT_SYNC_LAT < 15). Reset value = closed.
  signal run_age      : integer range 0 to 15 := 15;
  -- Quantised gaps since the previous A1 candidate, saturating above the
  -- exact spacing. Reset value means "no preceding candidate".
  signal sync_gap_age : integer range 0 to 15 := 15;

  -- N -> payload length in bytes
  function data_len(n : unsigned(7 downto 0)) return integer is
  begin
    case to_integer(n) is
      when 0      => return 128;
      when 1      => return 256;
      when 2      => return 512;
      when 3      => return 1024;
      when 4      => return 2048;
      when others => return 512;
    end case;
  end function;

begin

  ------------------------------------------------------------------------------
  -- read pipeline: RDATA -> gaps -> quantise -> gaps_to_bits -> bits_to_bytes
  ------------------------------------------------------------------------------
  i_gaps : entity work.physical_1581_mfm_gaps
    port map (clk_i => clk_i, rst_i => rst_i, f_rdata_i => f_rdata_i,
              gap_valid_o => gap_valid, gap_len_o => gap_len,
              runt_o => runt_o);

  i_quant : entity work.physical_1581_mfm_quantise
    generic map (G_TOL_ACQ_SHR    => G_QUANT_TOL_ACQ_SHR,
                 G_HUNT_ADAPT_ALL => G_QUANT_HUNT_ADAPT_ALL)
    port map (clk_i => clk_i, rst_i => rst_i, field_i => field_active,
              gap_valid_i => gap_valid, gap_len_i => gap_len,
              gap_valid_o => q_valid, gap_class_o => q_class,
              est_o => est_o);

  i_g2b : entity work.physical_1581_mfm_gaps_to_bits
    port map (clk_i => clk_i, rst_i => rst_i,
              gap_valid_i => q_valid, gap_class_i => q_class,
              bit_valid_o => bit_valid, bit_o => bit_d, sync_o => gtb_sync);

  i_b2b : entity work.physical_1581_mfm_bits_to_bytes
    port map (clk_i => clk_i, rst_i => rst_i,
              sync_i => gtb_sync, bit_i => bit_d, bit_valid_i => bit_valid,
              sync_o => byte_sync, byte_o => byte_d, byte_valid_o => byte_v);

  i_crc : entity work.physical_1581_crc
    port map (clk_i => clk_i, crc_byte_i => crc_byte, crc_feed_i => crc_feed,
              crc_reset_i => crc_reset, crc_ready_o => crc_ready, crc_value_o => crc_value);

  -- read-only diagnostic tap: expose the running CRC value (see port comment)
  crc_value_o <= crc_value;

  -- Production does not switch to in-field adaptation on a provisional A1:
  -- only a complete train or an open field can do that. Historical A/B modes
  -- retain their original first-A1 behavior.
  field_active <= '1' when state /= S_IDLE or
                    ((not G_SYNC_GATE or G_SYNC_PREAMBLE_GATE) and sync_cnt /= 0) or
                    (G_SYNC_GATE and not G_SYNC_PREAMBLE_GATE and sync_cnt = 3)
                  else '0';

  ------------------------------------------------------------------------------
  -- field FSM
  ------------------------------------------------------------------------------
  process (clk_i)
  begin
    if rising_edge(clk_i) then
      -- default: deassert one-cycle strobes
      crc_reset         <= '0';
      crc_feed          <= '0';
      id_valid_o        <= '0';
      data_start_o      <= '0';
      data_byte_valid_o <= '0';
      data_end_o        <= '0';
      gap_error_o       <= '0';

      if rst_i = '1' then
        state     <= S_IDLE;
        sync_cnt  <= 0;
        locked_o  <= '0';
        last_n    <= x"02";
        chk_cnt   <= 0;
        short_run <= 0;
        run_age   <= 15;                -- gate closed until a preamble run
        sync_gap_age <= 15;
      else
        -- diagnostics + loss of lock on an out-of-spec gap; also the
        -- preamble-run bookkeeping for the write-splice sync gate
        if q_valid = '1' then
          last_gap_o <= gap_len;
          if sync_gap_age < 15 then
            sync_gap_age <= sync_gap_age + 1;
          end if;
          if q_class = "11" then
            gap_error_o <= '1';
            locked_o    <= '0';
            state       <= S_IDLE;
            sync_cnt    <= 0;
            short_run   <= 0;
            run_age     <= 15;          -- loud loss of lock: close the gate
            sync_gap_age <= 15;
          elsif q_class = "00" then
            if short_run >= C_QUANT_SYNC_RUN - 1 then
              run_age <= 0;             -- preamble run complete/continuing
            elsif run_age < 15 then
              run_age <= run_age + 1;
            end if;
            if short_run < 255 then
              short_run <= short_run + 1;
            end if;
          else                          -- medium/long: run over, gate ages
            short_run <= 0;
            if run_age < 15 then
              run_age <= run_age + 1;
            end if;
          end if;
        end if;

        -- Feed exactly three A1 bytes into the CRC. Production qualifies the
        -- train by candidate spacing; a wrong-spacing candidate becomes a
        -- new provisional first A1. The two generic branches retain rounds
        -- 12 and 13 exactly for the regression matrix.
        if gtb_sync = '1' then
          if not G_SYNC_GATE then
            locked_o <= '1';
            if sync_cnt = 0 then
              crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
              sync_cnt <= 1;
            elsif sync_cnt < 3 then
              crc_feed <= '1'; crc_byte <= MARK_A1; sync_cnt <= sync_cnt + 1;
            end if;
          elsif G_SYNC_PREAMBLE_GATE then
            if field_active = '1' or run_age <= C_QUANT_SYNC_LAT then
              locked_o <= '1';
              if sync_cnt = 0 then
                crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
                sync_cnt <= 1;
              elsif sync_cnt < 3 then
                crc_feed <= '1'; crc_byte <= MARK_A1; sync_cnt <= sync_cnt + 1;
              end if;
            end if;
          else
            if sync_cnt = 0 then
              -- First candidate is provisional: prime the CRC, but do not
              -- claim separator lock until the complete train is proven.
              crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
              sync_cnt <= 1;
              locked_o <= '0';
            elsif sync_gap_age = C_QUANT_A1_SPACING then
              if sync_cnt < 3 then
                crc_feed <= '1'; crc_byte <= MARK_A1;
                sync_cnt <= sync_cnt + 1;
                if sync_cnt = 2 then
                  locked_o <= '1';
                end if;
              end if;
            else
              -- Overlap or wrong spacing: restart at this candidate.
              crc_reset <= '1'; crc_feed <= '1'; crc_byte <= MARK_A1;
              sync_cnt <= 1;
              locked_o <= '0';
            end if;
          end if;
          sync_gap_age <= 0;
        end if;

        -- decoded byte events
        if byte_v = '1' then
          case state is
            when S_IDLE =>
              if sync_cnt = 3 then          -- this byte is the address mark
                crc_feed <= '1';
                crc_byte <= byte_d;
                case byte_d is
                  when MARK_FE =>
                    state <= S_ID_C;
                  when MARK_FB =>
                    deleted_r    <= '0';
                    data_start_o <= '1';
                    data_cnt     <= data_len(last_n);
                    state        <= S_DATA;
                  when MARK_F8 =>
                    deleted_r    <= '1';
                    data_start_o <= '1';
                    data_cnt     <= data_len(last_n);
                    state        <= S_DATA;
                  when others =>
                    null;                   -- unsupported mark: ignore
                end case;
              end if;
              sync_cnt <= 0;

            when S_ID_C =>
              crc_feed <= '1'; crc_byte <= byte_d; id_c_r <= byte_d; state <= S_ID_H; sync_cnt <= 0;
            when S_ID_H =>
              crc_feed <= '1'; crc_byte <= byte_d; id_h_r <= byte_d; state <= S_ID_R; sync_cnt <= 0;
            when S_ID_R =>
              crc_feed <= '1'; crc_byte <= byte_d; id_r_r <= byte_d; state <= S_ID_N; sync_cnt <= 0;
            when S_ID_N =>
              crc_feed <= '1'; crc_byte <= byte_d; id_n_r <= byte_d; last_n <= byte_d;
              state <= S_ID_CRC1; sync_cnt <= 0;
            when S_ID_CRC1 =>
              crc_feed <= '1'; crc_byte <= byte_d; crc_stored_r(15 downto 8) <= byte_d;
              state <= S_ID_CRC2; sync_cnt <= 0;
            when S_ID_CRC2 =>
              crc_feed <= '1'; crc_byte <= byte_d; crc_stored_r(7 downto 0) <= byte_d;
              state <= S_ID_CHECK; chk_cnt <= 12; sync_cnt <= 0;

            when S_DATA =>
              crc_feed          <= '1'; crc_byte <= byte_d;
              data_byte_o       <= byte_d;
              data_byte_valid_o <= '1';
              if data_cnt <= 1 then
                state <= S_DATA_CRC1;
              end if;
              data_cnt <= data_cnt - 1;
              sync_cnt <= 0;
            when S_DATA_CRC1 =>
              crc_feed <= '1'; crc_byte <= byte_d; state <= S_DATA_CRC2; sync_cnt <= 0;
            when S_DATA_CRC2 =>
              crc_feed <= '1'; crc_byte <= byte_d; state <= S_DATA_CHECK; chk_cnt <= 12; sync_cnt <= 0;

            when others =>
              sync_cnt <= 0;                -- CHECK states: ignore stray bytes
          end case;
        end if;

        -- CRC settle + evaluate (counter guarantees the last fed byte is shifted)
        if state = S_ID_CHECK then
          if chk_cnt = 0 then
            id_c_o          <= id_c_r;
            id_h_o          <= id_h_r;
            id_r_o          <= id_r_r;
            id_n_o          <= id_n_r;
            id_crc_stored_o <= crc_stored_r;
            if crc_value = x"0000" then id_crc_ok_o <= '1'; else id_crc_ok_o <= '0'; end if;
            id_valid_o      <= '1';
            state           <= S_IDLE;
          else
            chk_cnt <= chk_cnt - 1;
          end if;
        elsif state = S_DATA_CHECK then
          if chk_cnt = 0 then
            data_deleted_o <= deleted_r;
            if crc_value = x"0000" then data_crc_ok_o <= '1'; else data_crc_ok_o <= '0'; end if;
            data_end_o     <= '1';
            state          <= S_IDLE;
          else
            chk_cnt <= chk_cnt - 1;
          end if;
        end if;

      end if;
    end if;
  end process;

end architecture rtl;
