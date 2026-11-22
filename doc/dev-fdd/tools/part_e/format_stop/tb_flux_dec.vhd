-- tb_flux_dec: feeds absolute flux-edge times (50 MHz cycle numbers, one per
-- line, from tools/mkflux.py) into an unmodified copy of the production
-- physical_1581_mfm_decoder and logs every record event (issue #257, part E).
-- A line "R <cycle>" asserts the decoder reset for 1 clock at that cycle.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use work.physical_1581_pkg.all;

entity tb_flux_dec is
  generic (G_IN : string := "flux.txt"; G_OUT : string := "events.txt");
end entity;

architecture sim of tb_flux_dec is
  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal rdata : std_logic := '1';
  signal cyc   : natural := 0;
  signal done  : boolean := false;

  signal id_valid, id_crc_ok, data_start, data_deleted, data_bv, data_end, data_crc_ok : std_logic;
  signal id_c, id_h, id_r, id_n, data_byte : unsigned(7 downto 0);
  signal id_crc_stored, last_gap, crc_value : unsigned(15 downto 0);
  signal locked, gap_err, runt, a1c, a1rej, a1tr, mfe, mdam, dunarm : std_logic;
  signal est : unsigned(11 downto 0);
begin
  clk <= not clk after 10 ns when not done;

  dut : entity work.physical_1581_mfm_decoder
    port map (
      clk_i => clk, rst_i => rst, f_rdata_i => rdata,
      id_valid_o => id_valid, id_c_o => id_c, id_h_o => id_h, id_r_o => id_r,
      id_n_o => id_n, id_crc_ok_o => id_crc_ok, id_crc_stored_o => id_crc_stored,
      data_start_o => data_start, data_deleted_o => data_deleted,
      data_byte_o => data_byte, data_byte_valid_o => data_bv,
      data_end_o => data_end, data_crc_ok_o => data_crc_ok,
      locked_o => locked, gap_error_o => gap_err, runt_o => runt,
      a1_candidate_o => a1c, a1_span_reject_o => a1rej, a1_train_o => a1tr,
      mark_fe_o => mfe, mark_dam_o => mdam, dam_unarmed_o => dunarm,
      last_gap_o => last_gap, crc_value_o => crc_value, est_o => est);

  -- stimulus: drive RDATA low for 10 clocks at every listed edge cycle
  stim : process
    file fin : text open read_mode is G_IN;
    variable l : line;
    variable k : character;
    variable t : natural;
    variable good : boolean;
    variable now_c : natural := 0;
  begin
    rst <= '1';
    for i in 0 to 3 loop wait until rising_edge(clk); end loop;
    rst <= '0';
    now_c := 4;
    while not endfile(fin) loop
      readline(fin, l);
      if l'length > 0 and l(l'low) = 'R' then
        read(l, k); read(l, t, good);
        while now_c < t loop wait until rising_edge(clk); now_c := now_c + 1; end loop;
        rst <= '1'; wait until rising_edge(clk); now_c := now_c + 1; rst <= '0';
      else
        read(l, t, good);
        if good then
          while now_c < t loop wait until rising_edge(clk); now_c := now_c + 1; end loop;
          rdata <= '0';
          for i in 1 to 10 loop wait until rising_edge(clk); now_c := now_c + 1; end loop;
          rdata <= '1';
        end if;
      end if;
    end loop;
    for i in 1 to 2000 loop wait until rising_edge(clk); end loop;
    done <= true;
    wait;
  end process;

  cnt : process (clk)
  begin
    if rising_edge(clk) then cyc <= cyc + 1; end if;
  end process;

  logp : process (clk)
    file fout : text open write_mode is G_OUT;
    variable l : line;
  begin
    if rising_edge(clk) then
      if id_valid = '1' then
        write(l, string'("ID ")); write(l, cyc); write(l, string'(" "));
        write(l, to_integer(id_c)); write(l, string'(" "));
        write(l, to_integer(id_h)); write(l, string'(" "));
        write(l, to_integer(id_r)); write(l, string'(" "));
        write(l, to_integer(id_n)); write(l, string'(" "));
        write(l, std_logic'image(id_crc_ok)); write(l, string'(" est="));
        write(l, to_integer(est)); writeline(fout, l);
      end if;
      if mfe = '1' then write(l, string'("FE ")); write(l, cyc); writeline(fout, l); end if;
      if mdam = '1' then
        write(l, string'("DAM ")); write(l, cyc); write(l, string'(" unarmed="));
        write(l, std_logic'image(dunarm)); writeline(fout, l);
      end if;
      if data_end = '1' then
        write(l, string'("DEND ")); write(l, cyc); write(l, string'(" crc="));
        write(l, std_logic'image(data_crc_ok)); writeline(fout, l);
      end if;
      if a1c = '1' then write(l, string'("C ")); write(l, cyc); write(l, string'(" est=")); write(l, to_integer(est)); writeline(fout, l); end if;
      if a1rej = '1' then write(l, string'("REJ ")); write(l, cyc); writeline(fout, l); end if;
      if a1tr = '1' then write(l, string'("T ")); write(l, cyc); writeline(fout, l); end if;
      if gap_err = '1' then write(l, string'("GE ")); write(l, cyc); write(l, string'(" gap=")); write(l, to_integer(last_gap)); writeline(fout, l); end if;
      if runt = '1' then write(l, string'("RUNT ")); write(l, cyc); writeline(fout, l); end if;
    end if;
  end process;
end architecture;
