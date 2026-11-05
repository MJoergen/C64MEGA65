----------------------------------------------------------------------------------------------------
-- Turbo-mode core bench (issue #87, doc/dev-turbo/TURBO-SPEC.md section 6)
--
-- DUT: rtl/fpga64_sid_iec.vhd of CORE/C64_MiSTerMEGA65 (real T65, VIC-II, PLA/buslogic; CIA and
-- SID are the VHDL stubs of tb_turbo_stubs.vhd). Around it:
--   * a 64 KB RAM with the read-first, one-clock latency of the C64 RAM in mega65.vhd (RAM writes
--     with the combinational ramCE/ramWE/ramDout of the core, as c64_ram_we_o in main.vhd)
--   * a copy of the main.vhd cartridge glue: cpu_data_in_proc (RAM / hardware cart / SIMCRT
--     mux), cart_output_pipeline_proc (one register stage on address, /ROML, /ROMH, /IO1, /IO2,
--     R/W, write data), cart_input_pipeline_proc (one register stage on the data pins, the CPU
--     sampling flip-flop is the second stage) and the read-envelope of
--     handle_hardware_expansion_proc
--   * a cartridge model: 8 KB ROML + 8 KB ROMH (Ultimax boot, image from gen_cart.py),
--     a 256-byte RAM in the Ultimax unmapped area at $1000-$10FF, a pattern in the rest of the
--     unmapped area, an IO1 register and a 256-byte IO2 RAM. Hardware mode: the cart drives
--     valid read data only once the address and strobes at the pins have been stable for the
--     access time T_ACC, before that the inverted byte ("poison"). SIMCRT mode: ROM data from a
--     16-bit BRAM with one clock of latency and live byte select, as the bank cache of
--     sw_cartridge_wrapper.vhd. IO1 register bit 7 switches the cartridge off (normal C64 map).
--   * monitors (VHDL-2008 external names, so: nvc) for every CPU bus access: every read is
--     compared with the reference of its source (stale data from a slow source fails), every
--     RAM write must reach the RAM, plus the timing checks of S1-S8 and F2
--
-- The scenario comes from ./scenario.txt, one line:
--   mode speed simcrt tacc_ps trace maxcycles bios ram_lat crt_lat board
--   mode 0 = Off, 1 = C128, 2 = Smart; speed 0 = 2x, 1 = 3x, 2 = 4x; simcrt 0 = hardware
--   cartridge, 1 = SIMCRT; tacc_ps = cartridge access time (hardware mode); trace 1 = write
--   ./trace.txt (one line per clock); maxcycles = watchdog in 1 MHz cycles; bios 0 = custom
--   Kernal (loaded through the QNICE port), 1 = standard ROM; ram_lat / crt_lat = register stages
--   from the address to the data of the RAM / SIMCRT cache (real port: 1; larger = mutant);
--   board = 3..6 (G_BOARD MEGA65_R3..R6; the EF3 turbo pause of main.vhd exists on R3/R4).
-- Also needed in the working directory: cart.hex (gen_cart.py) and roms/*.mif.hex.
-- The turbo inputs stay "00" until the program reports "booted" (phase 1), so that the boot
-- code in cartridge ROM runs at 1 MHz. In C128 mode the bench finally resets the C64 and checks
-- that the $D030 bit is cleared.
--
-- Output: "TB: key=value" lines that run.sh evaluates, and "TB_ERROR:" lines for bench-level
-- inconsistencies. The verdict per source set (baseline / new) is made by run.sh.
----------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity tb_turbo_core is
end entity tb_turbo_core;

architecture sim of tb_turbo_core is

   constant TCLK      : time    := 31718 ps;   -- clk_main PAL = 31.527778 MHz
   constant CLK_SPEED : natural := 31527778;

   type cfg_t is record
      mode, speed, simcrt, tacc_ps, trace, maxcycles, bios, ram_lat, crt_lat, board : integer;
   end record;

   impure function read_cfg return cfg_t is
      file f     : text;
      variable l : line;
      variable c : cfg_t;
      variable st : file_open_status;
   begin
      file_open(st, f, "scenario.txt", read_mode);
      assert st = open_ok report "scenario.txt missing" severity failure;
      readline(f, l);
      read(l, c.mode); read(l, c.speed); read(l, c.simcrt);
      read(l, c.tacc_ps); read(l, c.trace); read(l, c.maxcycles);
      read(l, c.bios); read(l, c.ram_lat); read(l, c.crt_lat); read(l, c.board);
      file_close(f);
      return c;
   end function;

   constant CFG   : cfg_t := read_cfg;

   function board_name(b : integer) return string is
   begin
      case b is
         when 3      => return "MEGA65_R3";
         when 4      => return "MEGA65_R4";
         when 5      => return "MEGA65_R5";
         when others => return "MEGA65_R6";
      end case;
   end function;

   constant G_BOARD   : string(1 to 9) := board_name(CFG.board);   -- main.vhd generic G_BOARD
   constant C_SIM_CRT : natural := 0;                                -- main.vhd constant
   constant T_ACC : time  := CFG.tacc_ps * 1 ps;

   type mem8_t  is array (natural range <>) of unsigned(7 downto 0);

   impure function read_cart return mem8_t is
      file f     : text;
      variable l : line;
      variable v : std_logic_vector(7 downto 0);
      variable m : mem8_t(0 to 16383);
      variable st : file_open_status;
   begin
      file_open(st, f, "cart.hex", read_mode);
      assert st = open_ok report "cart.hex missing" severity failure;
      for i in m'range loop
         readline(f, l);
         hread(l, v);
         m(i) := unsigned(v);
      end loop;
      file_close(f);
      return m;
   end function;

   constant CART : mem8_t(0 to 16383) := read_cart;   -- 0..8191 ROML, 8192..16383 ROMH

   impure function read_mif(name : string; n : natural) return mem8_t is
      file f     : text;
      variable l : line;
      variable v : std_logic_vector(7 downto 0);
      variable m : mem8_t(0 to n - 1) := (others => (others => '0'));
      variable st : file_open_status;
   begin
      file_open(st, f, name, read_mode);
      assert st = open_ok report name & " missing" severity failure;
      for i in m'range loop
         exit when endfile(f);
         readline(f, l);
         hread(l, v);
         m(i) := unsigned(v);
      end loop;
      file_close(f);
      return m;
   end function;

   -- pattern written into the custom Kernal RAM (BASIC + KERNAL, 16 KB) through the QNICE port
   function kpat(i : natural) return unsigned is
   begin
      return to_unsigned((i * 13 + 7 + i / 256) mod 256, 8);
   end function;

   impure function kernal_ref return mem8_t is
      variable m : mem8_t(0 to 16383);
   begin
      if CFG.bios = 0 then
         for i in m'range loop m(i) := kpat(i); end loop;
      else
         m := read_mif("roms/std_C64.mif.hex", 16384);
      end if;
      return m;
   end function;

   constant KROM    : mem8_t(0 to 16383) := kernal_ref;                          -- index A14 & A12..A0
   constant CHARROM : mem8_t(0 to 4095)  := read_mif("roms/chargen.mif.hex", 4096);

   function hex(v : unsigned) return string is
   begin
      return to_hstring(std_logic_vector(v));
   end function;

   function ns_str(t : time) return string is
   begin
      return integer'image(t / 1 ps / 1000) & "." & integer'image((t / 1 ps / 100) mod 10);
   end function;

   -- clock, reset, turbo inputs
   signal clk          : std_logic := '0';
   signal reset_n      : std_logic := '0';
   signal turbo_mode   : std_logic_vector(1 downto 0) := "00";
   signal turbo_speed  : std_logic_vector(1 downto 0) := "00";
   signal sim_crt      : std_logic := '0';
   signal stop_clk     : boolean := false;

   -- core ports
   signal ram_addr     : unsigned(15 downto 0);
   signal ram_din      : unsigned(7 downto 0);
   signal ram_dout     : unsigned(7 downto 0);
   signal ram_ce       : std_logic;
   signal ram_we_raw   : std_logic;
   signal ext_cycle    : std_logic;
   signal core_game    : std_logic := '1';
   signal core_exrom   : std_logic := '1';
   signal core_io_rom  : std_logic := '0';
   signal core_io_ext  : std_logic;
   signal core_io_data : unsigned(7 downto 0);
   signal core_ba      : std_logic;
   signal core_roml    : std_logic;
   signal core_romh    : std_logic;
   signal core_umax_romh : std_logic;
   signal core_umax_unmapped : std_logic;
   signal core_ioe     : std_logic;
   signal core_iof     : std_logic;
   signal core_phi2    : std_logic;
   signal dma_req      : std_logic := '0';
   signal dma_cycle    : std_logic;
   signal dma_addr     : unsigned(15 downto 0) := x"0E00";
   signal dma_we       : std_logic := '0';

   -- RAM model
   signal ram          : mem8_t(0 to 65535) := (others => (others => '0'));
   signal ram_q        : unsigned(7 downto 0) := (others => '0');
   signal ram_wr       : std_logic;
   signal last_wr_addr : unsigned(15 downto 0) := (others => '0');
   signal last_wr_data : unsigned(7 downto 0) := (others => '0');
   signal last_wr_time : time := 0 ns;
   signal c64rom_we    : std_logic := '0';
   signal c64rom_addr  : std_logic_vector(13 downto 0) := (others => '0');
   signal c64rom_data  : std_logic_vector(7 downto 0) := (others => '0');
   signal bios         : std_logic_vector(1 downto 0);

   -- main.vhd cartridge glue
   signal cart_out_roml_n, cart_out_romh_n, cart_out_io1_n, cart_out_io2_n, cart_out_sel : std_logic;
   signal cart_out_a   : unsigned(15 downto 0);
   signal cart_out_a_q : unsigned(15 downto 0) := (others => '0');
   signal cart_out_roml_n_q, cart_out_romh_n_q, cart_out_io1_n_q, cart_out_io2_n_q : std_logic := '1';
   signal cart_out_rw_q, cart_out_sel_q : std_logic := '1';
   signal cart_out_d_q : unsigned(7 downto 0) := (others => '0');
   signal cart_in_d_q  : unsigned(7 downto 0) := (others => '1');
   signal cart_in_game_n_q, cart_in_exrom_n_q : std_logic := '1';
   signal cpu_strobe_n_q : std_logic := '1';   -- registered CPU-side /ROML or /ROMH (VIC fetches excluded)
   signal cart_in_data : unsigned(7 downto 0);
   signal cart_d_o     : unsigned(7 downto 0);   -- FPGA -> cartridge (writes)
   signal cart_d_i     : unsigned(7 downto 0) := x"FF";   -- cartridge -> FPGA

   -- cartridge model state
   signal pin_change   : time := 0 ns;
   signal io2ram       : mem8_t(0 to 255) := (others => (others => '0'));
   signal uram         : mem8_t(0 to 255) := (others => (others => '0'));
   signal io1reg       : unsigned(7 downto 0) := (others => '0');   -- $DE00: bit 7 = cartridge off
   signal cart_m16     : std_logic := '0';                          -- $DE02 bit 0: 16K mode, else Ultimax
   signal cart_ultimax : boolean;
   signal cart_data_oe : std_logic;                                 -- main.vhd cart_data_oe_o (1 = FPGA drives)
   signal cart_latch_data : unsigned(7 downto 0) := (others => '0');
   signal wr_window_viol  : natural := 0;
   signal is_an_ef3    : std_logic;
   signal heur_exrom_n, heur_game_n : std_logic;
   -- main.vhd signals of the turbo wiring; core_cpu_deferred and cart_heur_busy are driven only by
   -- sources that have the ports cpu_deferred / busy_o (run.sh activates the "--@if_" lines)
   signal core_cpu_deferred : std_logic := '0';
   signal cart_heur_busy    : std_logic := '0';
   signal exp_port_we       : std_logic;
   signal core_turbo_mode   : std_logic_vector(1 downto 0);
   signal turbo_ef3_pause   : std_logic;
   signal turbo_disk_access : std_logic := '0';              -- no IEC activity in this bench
   signal cart_in_dma_n_q   : std_logic := '1';              -- no cartridge DMA in this bench
   signal c64_exp_port_mode_i : std_logic_vector(3 downto 0);
   signal umax_q            : std_logic := '0';
   signal crt_q        : unsigned(7 downto 0);
   signal crt_lo_q, crt_hi_q : unsigned(15 downto 0) := (others => '0');
   signal wr_setup_viol: natural := 0;
   signal cart_latch_cnt : natural := 0;            -- writes the cartridge latched (PHI2 falling)
   signal cart_latch_addr: unsigned(15 downto 0) := (others => '0');

   -- bench-level state
   -- main.vhd names of bench signals, so that the copied main.vhd blocks read as in main.vhd
   alias clk_main_i       is clk;
   alias c64_ram_we       is ram_we_raw;
   alias c64_ram_addr_o   is ram_addr;
   alias c64_ram_data_o   is ram_dout;
   alias c64_ram_data_i   is ram_q;
   alias c64_ram_data     is ram_din;
   alias cart_data_oe_o   is cart_data_oe;
   alias c64_turbo_mode_i is turbo_mode;

   signal cyc          : integer range 0 to 31 := 0;   -- sysCycle index of the current clock
   signal cyc_synced   : boolean := false;
   signal cycle_no     : natural := 0;                 -- 1 MHz cycles since start
   signal phase        : integer := 0;

   function unmapped_pattern(a : unsigned(15 downto 0)) return unsigned is
   begin
      return a(7 downto 0) xor a(15 downto 8) xor x"3C";
   end function;

begin

   clk <= not clk after TCLK / 2 when not stop_clk;
   sim_crt <= '1' when CFG.simcrt = 1 else '0';
   bios    <= std_logic_vector(to_unsigned(CFG.bios, 2));

   ---------------------------------------------------------------------------------------------
   -- DUT
   ---------------------------------------------------------------------------------------------
   dut : entity work.fpga64_sid_iec
      port map (
         clk32       => clk,
         clk32_speed => CLK_SPEED,
         reset_n     => reset_n,
         bios        => bios,
         pause       => '0',
         pause_out   => open,
         cia1_pa_i   => x"FF",
         cia1_pa_o   => open,
         cia1_pb_i   => x"FF",
         cia1_pb_o   => open,
         ramAddr     => ram_addr,
         ramDin      => ram_din,
         ramDout     => ram_dout,
         ramCE       => ram_ce,
         ramWE       => ram_we_raw,
         io_cycle    => open,
         ext_cycle   => ext_cycle,
         refresh     => open,
         cia_mode    => '0',
         turbo_mode  => core_turbo_mode,
         turbo_speed => turbo_speed,
--@if_deferred          cpu_deferred => core_cpu_deferred,
         sim_crt_i   => sim_crt,
         ntscMode    => '0',
         hsync       => open,
         vsync       => open,
         r           => open,
         g           => open,
         b           => open,
         game        => core_game,
         exrom       => core_exrom,
         io_rom      => core_io_rom,
         io_ext      => core_io_ext,
         io_data     => core_io_data,
         irq_n       => '1',
         nmi_n       => '1',
         nmi_ack     => open,
         ba          => core_ba,
         romL        => core_roml,
         romH        => core_romh,
         UMAXromH    => core_umax_romh,
         UMAXnomap   => core_umax_unmapped,
         IOE         => core_ioe,
         IOF         => core_iof,
         dotclk      => open,
         phi2        => core_phi2,
         dma_req     => dma_req,
         dma_cycle   => dma_cycle,
         dma_addr    => dma_addr,
         dma_dout    => x"00",
         dma_din     => open,
         dma_we      => dma_we,
         irq_ext_n   => '1',
         pot1        => x"FF",
         pot2        => x"FF",
         pot3        => x"FF",
         pot4        => x"FF",
         audio_l     => open,
         audio_r     => open,
         sid_filter  => "11",
         sid_ver     => "00",
         sid_mode    => "000",
         sid_cfg     => "0000",
         sid_ld_clk  => '0',
         sid_ld_addr => (others => '0'),
         sid_ld_data => (others => '0'),
         sid_ld_wr   => '0',
         pb_i        => x"FF",
         pb_o        => open,
         pa2_i       => '1',
         pa2_o       => open,
         pc2_n_o     => open,
         flag2_n_i   => '1',
         sp2_i       => '1',
         sp2_o       => open,
         sp1_i       => '1',
         sp1_o       => open,
         cnt2_i      => '1',
         cnt2_o      => open,
         cnt1_i      => '1',
         cnt1_o      => open,
         iec_data_o  => open,
         iec_data_i  => '1',
         iec_clk_o   => open,
         iec_clk_i   => '1',
         iec_atn_o   => open,
         cass_motor  => open,
         cass_write  => open,
         cass_sense  => '1',
         cass_read   => '1',
         c64rom_clk_i  => clk,
         c64rom_we_i   => c64rom_we,
         c64rom_addr_i => c64rom_addr,
         c64rom_data_i => c64rom_data,
         c64rom_data_o => open
      );

   ---------------------------------------------------------------------------------------------
   -- C64 RAM (mega65.vhd: dualport_2clk_ram / tdp_ram, read-first, one clock latency)
   ---------------------------------------------------------------------------------------------
   ram_wr <= ram_ce and ram_we_raw;     -- main.vhd: c64_ram_we_o <= c64_ram_ce and c64_ram_we

   -- CFG.ram_lat = number of register stages from ramAddr to ramDin; the real port has 1
   -- (tdp_ram q_a, then cpu_data_in_proc is combinational). Larger values are mutants.
   ram_proc : process (clk)
      variable pipe : mem8_t(1 to 8);
   begin
      if rising_edge(clk) then
         if ram_wr = '1' then
            ram(to_integer(ram_addr)) <= ram_dout;
            last_wr_addr <= ram_addr;
            last_wr_data <= ram_dout;
            last_wr_time <= now;
         end if;
         for i in 8 downto 2 loop
            pipe(i) := pipe(i - 1);
         end loop;
         pipe(1) := ram(to_integer(ram_addr));
         ram_q <= pipe(CFG.ram_lat);
      end if;
   end process;

   ---------------------------------------------------------------------------------------------
   -- main.vhd glue. Every block between "-- [main.vhd copy begin]" and "-- [main.vhd copy end]" is a
   -- verbatim copy of CORE/vhdl/main.vhd (comments aside); run.sh fails if a block no longer appears
   -- in main.vhd as a contiguous sequence of lines. The aliases above give the bench signals their
   -- main.vhd names. Sources without cpu_deferred / busy_o (baseline) keep core_cpu_deferred and
   -- cart_heur_busy at '0', which turns this glue into the one of the baseline main.vhd
   -- (exp_port_we = c64_ram_we, no EF3 pause).
   ---------------------------------------------------------------------------------------------
   c64_exp_port_mode_i <= "000" & sim_crt;

   -- [main.vhd copy begin]
  cart_out_a <= "11" & c64_ram_addr_o(13 downto 0) when core_umax_romh = '1'
                else c64_ram_addr_o;
   -- [main.vhd copy end]

   -- [main.vhd copy begin]
  cart_out_sel <= '1' when cart_out_roml_n   = '0' or cart_out_romh_n   = '0' or
                            cart_out_io1_n    = '0' or cart_out_io2_n    = '0' or
                            core_umax_unmapped   = '1' else '0';
   -- [main.vhd copy end]

   -- [main.vhd copy begin]
  exp_port_we <= c64_ram_we and not core_cpu_deferred;
   -- [main.vhd copy end]

   -- [main.vhd copy begin]
  core_turbo_mode(0) <= c64_turbo_mode_i(0) and not turbo_ef3_pause;
  core_turbo_mode(1) <= c64_turbo_mode_i(1) and not turbo_disk_access and not turbo_ef3_pause;
   -- [main.vhd copy end]

   -- [main.vhd copy begin]
  turbo_ef3_pause <= cart_heur_busy when (G_BOARD = "MEGA65_R3" or G_BOARD = "MEGA65_R4") and
                                         c64_exp_port_mode_i(C_SIM_CRT) = '0' else '0';
   -- [main.vhd copy end]

   -- [main.vhd copy begin]
  cart_output_pipeline_proc : process (clk_main_i)
  begin
    if rising_edge(clk_main_i) then
      cart_out_a_q      <= cart_out_a;            -- includes Ultimax override
      cart_out_roml_n_q <= cart_out_roml_n;
      cart_out_romh_n_q <= cart_out_romh_n;
      cart_out_io1_n_q  <= cart_out_io1_n;
      cart_out_io2_n_q  <= cart_out_io2_n;
      cart_out_rw_q     <= not exp_port_we;   -- R/W stays high for a waiting turbo-mode access (see exp_port_we)
      cart_out_d_q      <= c64_ram_data_o;
      cart_out_sel_q    <= cart_out_sel;
    end if;
  end process cart_output_pipeline_proc;
   -- [main.vhd copy end]

   -- cart_input_pipeline_proc (data line copied) and the cartridge's /GAME and /EXROM
   cart_input_proc : process (clk)
   begin
      if rising_edge(clk) then
         -- [main.vhd copy begin]
      cart_in_d_q       <= cart_d_i;
         -- [main.vhd copy end]
         cart_in_game_n_q  <= io1reg(7);                   -- off: both high; Ultimax: /GAME low;
         cart_in_exrom_n_q <= io1reg(7) or not cart_m16;   -- 16K: /GAME and /EXROM low
         cpu_strobe_n_q    <= not (core_roml or core_romh); -- CPU-side /ROML, /ROMH as on the pins
         umax_q            <= core_umax_unmapped;           -- Ultimax unmapped access (no strobe)
      end if;
   end process;

   -- handle_hardware_expansion_proc: strobes and the data bus (no cartridge DMA in this bench)
   hw_exp_proc : process (all)
   begin
      cart_in_data   <= x"00";
      cart_data_oe_o <= '0';
      cart_d_o       <= (others => '0');
      -- [main.vhd copy begin]
    cart_out_roml_n     <= not core_roml;
    cart_out_romh_n     <= (not core_romh) and (not core_umax_romh);  -- normal ROMH and Ultimax VIC access ROMH
    cart_out_io1_n      <= not core_ioe;
    cart_out_io2_n      <= not core_iof;
      -- [main.vhd copy end]
      if c64_exp_port_mode_i(C_SIM_CRT) = '0' then
      if cart_in_dma_n_q = '0' then
         null;
      -- [main.vhd copy begin]
      elsif (exp_port_we = '0' and cart_out_sel = '1') or (cart_out_rw_q = '1' and cart_out_sel_q = '1') then
        cart_data_oe_o <= '0';                  -- input (FPGA tri-stated, cart may drive)
        cart_in_data <= cart_in_d_q;
      else
        cart_data_oe_o <= '1';                  -- output (FPGA drives)
        if exp_port_we = '1' and cart_out_sel = '1' then
          cart_d_o <= c64_ram_data_o;           -- live cart write: drive byte early for setup margin
        elsif cart_out_rw_q = '0' and cart_out_sel_q = '1' then
          cart_d_o <= cart_out_d_q;                 -- registered cart write: hold byte through the pin tail
        elsif exp_port_we = '0' then
          cart_d_o <= c64_ram_data_i;           -- preserved non-cart default: mirror C64 read data
        else
          cart_d_o <= c64_ram_data_o;           -- preserved non-cart default: mirror C64 write data
        end if;
      end if;
      -- [main.vhd copy end]
      end if;
   end process;

   -- cpu_data_in_proc (no hard-reset mask, no RR-Net); SIMCRT data from the bank-cache model crt_q
   cpu_data_in_proc : process (all)
   begin
      c64_ram_data <= x"00";
      if false then
         null;
      -- [main.vhd copy begin]
    elsif c64_exp_port_mode_i(C_SIM_CRT) = '0' and (cart_out_roml_n = '0' or cart_out_romh_n = '0' or core_umax_unmapped = '1') then
      c64_ram_data <= cart_in_data;
      -- [main.vhd copy end]
      -- [main.vhd copy begin]
    elsif c64_exp_port_mode_i(C_SIM_CRT) = '1' and (cart_out_roml_n = '0' or cart_out_romh_n = '0' or core_ioe = '1' or core_iof = '1') then
      -- [main.vhd copy end]
      c64_ram_data <= crt_q;
      -- [main.vhd copy begin]
    else
      c64_ram_data <= c64_ram_data_i;
    end if;
      -- [main.vhd copy end]
   end process;

   -- handle_cores_expansion_port_signals_proc
   core_game    <= cart_in_game_n_q  when sim_crt = '0' else io1reg(7);
   core_exrom   <= cart_in_exrom_n_q when sim_crt = '0' else io1reg(7) or not cart_m16;
   cart_ultimax <= io1reg(7) = '0' and cart_m16 = '0';
   core_io_rom  <= '0';
   core_io_ext  <= core_ioe or core_iof;
   core_io_data <= cart_in_data when sim_crt = '0' else
                   io1reg       when core_ioe = '1' else
                   io2ram(to_integer(ram_addr(7 downto 0)));

   ---------------------------------------------------------------------------------------------
   -- SIMCRT: BRAM bank cache with one clock of read latency; IO2 RAM writes
   ---------------------------------------------------------------------------------------------
   -- sw_cartridge_wrapper.vhd: crt_lo_ram / crt_hi_ram are tdp_ram on clk_main, 16 bit wide,
   -- address cache slot & crt_addr_bus_o(12 downto 1); main.vhd cpu_data_in_proc picks lo/hi with
   -- the live /ROML, /ROMH and the byte with the live crt_addr_bus_o(0). CFG.crt_lat = register
   -- stages (real: 1); larger values are mutants.
   simcrt_proc : process (clk)
      type w_t is array (1 to 8) of unsigned(15 downto 0);
      variable plo, phi : w_t;
      variable w : integer;
   begin
      if rising_edge(clk) then
         w := to_integer(ram_addr(12 downto 1)) * 2;
         if core_umax_romh = '1' then
            w := to_integer(ram_addr(12 downto 1)) * 2;     -- "11" & addr(13 downto 0): same low bits
         end if;
         for i in 8 downto 2 loop
            plo(i) := plo(i - 1);
            phi(i) := phi(i - 1);
         end loop;
         plo(1) := CART(w + 1) & CART(w);
         phi(1) := CART(8192 + w + 1) & CART(8192 + w);
         crt_lo_q <= plo(CFG.crt_lat);
         crt_hi_q <= phi(CFG.crt_lat);
      end if;
   end process;
   crt_q <= crt_lo_q(15 downto 8) when cart_out_roml_n = '0' and ram_addr(0) = '1' else
            crt_lo_q( 7 downto 0) when cart_out_roml_n = '0' else
            crt_hi_q(15 downto 8) when ram_addr(0) = '1' else
            crt_hi_q( 7 downto 0);

   ---------------------------------------------------------------------------------------------
   -- Hardware cartridge model at the pins
   ---------------------------------------------------------------------------------------------
   pin_change_proc : process (cart_out_a_q, cart_out_roml_n_q, cart_out_romh_n_q,
                              cart_out_io1_n_q, cart_out_io2_n_q, cart_out_rw_q)
   begin
      pin_change <= now;
   end process;

   cart_read_proc : process (cart_out_a_q, cart_out_roml_n_q, cart_out_romh_n_q,
                             cart_out_io1_n_q, cart_out_io2_n_q, cart_out_rw_q)
      variable a   : unsigned(15 downto 0);
      variable v   : unsigned(7 downto 0);
      variable sel : boolean;
   begin
      a := cart_out_a_q;
      sel := true;
      if cart_out_romh_n_q = '0' then
         v := CART(8192 + to_integer(a(12 downto 0)));
      elsif cart_out_roml_n_q = '0' then
         v := CART(to_integer(a(12 downto 0)));
      elsif cart_out_io2_n_q = '0' then
         v := io2ram(to_integer(a(7 downto 0)));
      elsif cart_out_io1_n_q = '0' then
         v := io1reg;
      elsif cart_ultimax and a(15 downto 8) = x"10" then
         v := uram(to_integer(a(7 downto 0)));
      elsif cart_ultimax and ((a >= x"1000" and a <= x"7FFF") or (a >= x"A000" and a <= x"CFFF")) then
         v := unmapped_pattern(a);
      else
         sel := false;
      end if;
      if CFG.simcrt = 0 and sel and cart_out_rw_q = '1' then
         cart_d_i <= v xor x"FF";
         cart_d_i <= transport v after T_ACC;
      else
         cart_d_i <= x"FF";
      end if;
   end process;

   -- writes are latched by the cartridge when PHI2 falls, i.e. at the edge that ends CYCLE_CPUE
   cart_write_proc : process (clk)
      variable a : unsigned(15 downto 0);
      variable d : unsigned(7 downto 0);
      variable decoded : boolean := false;
      variable last_latch_t : time := -1 ns;
   begin
      if rising_edge(clk) then
         if CFG.simcrt = 1 and ram_we_raw = '1' then  -- SIMCRT: IO1 registers and IO2 RAM in the FPGA
            if core_ioe = '1' then
               if ram_addr(7 downto 0) = x"00" then
                  io1reg <= ram_dout;
               elsif ram_addr(7 downto 0) = x"02" then
                  cart_m16 <= ram_dout(0);
               end if;
            elsif core_iof = '1' then
               io2ram(to_integer(ram_addr(7 downto 0))) <= ram_dout;
            end if;
         end if;
         if CFG.simcrt = 0 and cyc_synced and cyc = 30 and core_phi2 = '1' and cart_out_rw_q = '0' then
            a := cart_out_a_q;
            d := cart_d_o;
            -- writes the cartridge decodes: IO1, IO2, ROML, ROMH (flash on real cartridges) and the
            -- Ultimax unmapped area (IDE64-like)
            decoded := cart_out_io1_n_q = '0' or cart_out_io2_n_q = '0' or cart_out_roml_n_q = '0' or
                       cart_out_romh_n_q = '0' or
                       (cart_ultimax and ((a >= x"1000" and a <= x"7FFF") or (a >= x"A000" and a <= x"CFFF")));
            if decoded then
               cart_latch_cnt  <= cart_latch_cnt + 1;
               cart_latch_addr <= a;
               cart_latch_data <= d;
               if cart_data_oe /= '1' then              -- the FPGA does not drive the data bus
                  wr_window_viol <= wr_window_viol + 1;
                  d := x"FF";
               end if;
               if now - pin_change < T_ACC then
                  d := d xor x"FF";
                  wr_setup_viol <= wr_setup_viol + 1;
               end if;
            end if;
            if cart_out_io1_n_q = '0' then
               if a(7 downto 0) = x"00" then
                  io1reg <= d;
               elsif a(7 downto 0) = x"02" then
                  cart_m16 <= d(0);
               end if;
            elsif cart_out_io2_n_q = '0' then
               io2ram(to_integer(a(7 downto 0))) <= d;
            elsif cart_out_roml_n_q = '1' and cart_out_romh_n_q = '1' and a(15 downto 8) = x"10" and cart_ultimax then
               uram(to_integer(a(7 downto 0))) <= d;
            end if;
         end if;
         -- hold side of the write window: in the clock after PHI2 fell, the pins must still show the
         -- write (address, R/W low, data driven) that the cartridge latched
         if CFG.simcrt = 0 and cyc_synced and cyc = 31 and cart_latch_cnt /= 0 and now - TCLK = last_latch_t then
            if cart_out_rw_q /= '0' or cart_out_a_q /= cart_latch_addr or cart_data_oe /= '1' or
               cart_d_o /= cart_latch_data then
               wr_window_viol <= wr_window_viol + 1;
            end if;
         end if;
         if CFG.simcrt = 0 and cyc_synced and cyc = 30 and core_phi2 = '1' and cart_out_rw_q = '0' and decoded then
            last_latch_t := now;
         end if;
         if reset_n = '0' then                        -- the cartridge sees /RESET
            io1reg   <= x"00";
            cart_m16 <= '0';
         end if;
      end if;
   end process;

   -- the EF3 detection of the R3/R3A/R4 boards (main.vhd cartridge_heuristics_inst), real RTL;
   -- main.vhd feeds it cart_in_exrom_n / cart_in_game_n, which are '1' outside hardware mode
   heur_exrom_n <= cart_in_exrom_n_q when sim_crt = '0' else '1';
   heur_game_n  <= cart_in_game_n_q  when sim_crt = '0' else '1';
   cartridge_heuristics_inst : entity work.cartridge_heuristics
      port map (
         clk_main_i     => clk,
         reset_core_n_i => reset_n,
         cart_exrom_n_i => heur_exrom_n,
         cart_game_n_i  => heur_game_n,
         cart_io1_n_i   => cart_out_io1_n,
         cart_io2_n_i   => cart_out_io2_n,
         c64_ram_we_i   => ram_we_raw,
         c64_ram_addr_i => std_logic_vector(ram_addr),
         phi2_i         => core_phi2,
--@if_busy          busy_o         => cart_heur_busy,
         is_an_EF3_o    => is_an_ef3
      );

   ---------------------------------------------------------------------------------------------
   -- sysCycle index: PHI2 is high from CYCLE_CPU1 to CYCLE_CPUE; the index is resynchronized at
   -- every rising PHI2 and cross-checked against ext_cycle (CYCLE_DMA0..DMA3)
   ---------------------------------------------------------------------------------------------
   cyc_proc : process (clk)
      variable phi2_d : std_logic := '0';
   begin
      if rising_edge(clk) then
         if core_phi2 = '1' and phi2_d = '0' then       -- the clock that ends now was CYCLE_CPU1
            if cyc_synced and cyc /= 17 then
               report "TB_ERROR: sysCycle index lost sync" severity error;
            end if;
            cyc <= 18;
            cyc_synced <= true;
         else
            cyc <= (cyc + 1) mod 32;
            if cyc = 31 then
               cycle_no <= cycle_no + 1;
            end if;
         end if;
         phi2_d := core_phi2;
         if cyc_synced and ((ext_cycle = '1') /= (cyc >= 4 and cyc <= 7)) then
            report "TB_ERROR: ext_cycle does not match the sysCycle index" severity error;
         end if;
      end if;
   end process;

   ---------------------------------------------------------------------------------------------
   -- Monitors (external names into the DUT)
   ---------------------------------------------------------------------------------------------
   mon : block
      alias enableCpu    is <<signal .tb_turbo_core.dut.enableCpu    : std_logic>>;
      alias dma_active   is <<signal .tb_turbo_core.dut.dma_active   : std_logic>>;
      alias cpuAddr      is <<signal .tb_turbo_core.dut.cpuAddr      : unsigned(15 downto 0)>>;
      alias cpuWe        is <<signal .tb_turbo_core.dut.cpuWe        : std_logic>>;
      alias cpuDi        is <<signal .tb_turbo_core.dut.cpuDi        : unsigned(7 downto 0)>>;
      alias cpuDo        is <<signal .tb_turbo_core.dut.cpuDo        : unsigned(7 downto 0)>>;
      alias turbo_m      is <<signal .tb_turbo_core.dut.turbo_m      : std_logic_vector(2 downto 0)>>;
      alias turbo_state  is <<signal .tb_turbo_core.dut.turbo_state  : std_logic>>;
      alias cpuHasBus    is <<signal .tb_turbo_core.dut.cpuHasBus    : std_logic>>;
      alias cs_vic       is <<signal .tb_turbo_core.dut.cs_vic       : std_logic>>;
      alias cs_sid       is <<signal .tb_turbo_core.dut.cs_sid       : std_logic>>;
      alias cs_color     is <<signal .tb_turbo_core.dut.cs_color     : std_logic>>;
      alias cs_cia1      is <<signal .tb_turbo_core.dut.cs_cia1      : std_logic>>;
      alias cs_cia2      is <<signal .tb_turbo_core.dut.cs_cia2      : std_logic>>;
      alias ioe_i        is <<signal .tb_turbo_core.dut.ioe_i        : std_logic>>;
      alias iof_i        is <<signal .tb_turbo_core.dut.iof_i        : std_logic>>;
      alias enableCia_p  is <<signal .tb_turbo_core.dut.enableCia_p  : std_logic>>;
      alias enableCia_n  is <<signal .tb_turbo_core.dut.enableCia_n  : std_logic>>;
      alias enableSid    is <<signal .tb_turbo_core.dut.enableSid    : std_logic>>;
      alias enableVic    is <<signal .tb_turbo_core.dut.enableVic    : std_logic>>;
      alias cs_ramLoc    is <<signal .tb_turbo_core.dut.buslogic.cs_ramLoc       : std_logic>>;
      alias cs_romLoc    is <<signal .tb_turbo_core.dut.buslogic.cs_romLoc       : std_logic>>;
      alias cs_CharLoc   is <<signal .tb_turbo_core.dut.buslogic.cs_CharLoc      : std_logic>>;
      alias cs_romLLoc   is <<signal .tb_turbo_core.dut.buslogic.cs_romLLoc      : std_logic>>;
      alias cs_romHLoc   is <<signal .tb_turbo_core.dut.buslogic.cs_romHLoc      : std_logic>>;
      alias cs_UMAXnomapLoc is <<signal .tb_turbo_core.dut.buslogic.cs_UMAXnomapLoc : std_logic>>;
      alias cs_vicLoc    is <<signal .tb_turbo_core.dut.buslogic.cs_vicLoc       : std_logic>>;
      alias cs_sidLoc    is <<signal .tb_turbo_core.dut.buslogic.cs_sidLoc       : std_logic>>;
      alias cs_colorLoc  is <<signal .tb_turbo_core.dut.buslogic.cs_colorLoc     : std_logic>>;
      alias cs_cia1Loc   is <<signal .tb_turbo_core.dut.buslogic.cs_cia1Loc      : std_logic>>;
      alias cs_cia2Loc   is <<signal .tb_turbo_core.dut.buslogic.cs_cia2Loc      : std_logic>>;
      alias cs_ioELoc    is <<signal .tb_turbo_core.dut.buslogic.cs_ioELoc       : std_logic>>;
      alias cs_ioFLoc    is <<signal .tb_turbo_core.dut.buslogic.cs_ioFLoc       : std_logic>>;

      -- statistics, shared with the stimulus process for the final report
      type nat_arr is array (natural range <>) of natural;
      type time_arr is array (natural range <>) of time;
      signal s1_hist        : nat_arr(0 to 7) := (others => 0);   -- accesses per 1 MHz cycle in phase 2
      signal s1_ok, s1_bad  : natural := 0;                        -- cycles with / without the expected slot set
      signal s1_badmask     : integer := -1;
      signal io_acc, io_viol: natural := 0;
      signal dma_cyc, dma_cpu, dma_turbo, dma_after_turbo : natural := 0;
      signal d030_on_n, d030_on_ok, d030_off_n, d030_off_ok : natural := 0;
      signal cart_acc       : nat_arr(0 to 3) := (others => 0);    -- by preceding slot: none, CPU0, CPU4, CPU8
      signal cart_min       : time_arr(0 to 3) := (others => 1 ms);
      signal cart_rd_err, cart_viol, cart_addr_late, cart_wr : natural := 0;
      signal sim_rd, sim_rd_turbo, sim_rd_err : natural := 0;
      -- every CPU read / RAM write, by data source: 1 RAM, 2 BASIC/KERNAL, 3 char ROM, 4 hardware
      -- cartridge (ROML, ROMH, unmapped, IO1, IO2), 5 SIMCRT (ROML, ROMH, IO1, IO2)
      signal rd_chk, rd_turbo, rd_err : nat_arr(1 to 5) := (others => 0);
      signal phantom_wr     : natural := 0;   -- cartridge write strobes without a CPU write access
      signal missing_wr     : natural := 0;   -- CPU writes to the cartridge the cartridge did not latch
      signal wr_data_err    : natural := 0;   -- latched data differs from the CPU data
      signal ff00_wr, ff00_invisible : natural := 0;
      signal ef3_seen       : boolean := false;
      signal pause_clocks   : natural := 0;   -- clocks with turbo_ef3_pause = '1'
      signal umax_unsampled : natural := 0;   -- Ultimax unmapped accesses on the bus without a CPU access
      signal wr_chk, wr_err, wr_turbo : natural := 0;
      signal strobe_pulses, strobe_unsampled : natural := 0;
      signal csio_dec, hasbus_dec : natural := 0;
      signal en_pattern_err : natural := 0;
      signal turbo_cycles   : natural := 0;
      -- I6 / S5: latency (in 1 MHz cycles) from a change of the turbo inputs to the first cycle
      -- that shows the new behavior; 0 = the same cycle, 1 = the next one
      signal tchg_cycle     : integer := -1;
      signal tchg_on        : boolean := false;
      signal tchg_n, tchg_max : natural := 0;
      signal first_d030_after_reset : integer := -1;
      signal reset_seen     : boolean := false;
   begin

      monitor : process (clk)
         variable en           : boolean;
         variable slot         : integer;
         variable last_slot    : integer := -1;      -- slot of the previous CPU access in this 1 MHz cycle
         variable mask         : integer := 0;       -- bit k set = access in slot CPU(4k)
         variable n_acc        : integer := 0;
         variable is_cart, is_io, is_sim : boolean;
         variable exp_v        : unsigned(7 downto 0);
         variable check_data   : boolean;
         variable avail        : time;
         variable k            : integer;
         variable expmask      : integer;
         variable d030_check   : integer := -1;      -- 1 MHz cycle to check after a $D030 write
         variable d030_val     : std_logic := '0';
         variable dma_dec      : std_logic := '0';
         variable cyc_start    : time := 0 ns;
         variable addr_change  : time := 0 ns;
         variable addr_prev    : unsigned(15 downto 0) := (others => '0');
         variable strobe_prev  : std_logic := '1';
         variable sampled      : boolean := false;
         variable a            : unsigned(15 downto 0);
         variable dma_seen     : boolean := false;
         variable src, cs      : integer;
         variable prev_en      : time := 0 ns;
         variable tchg_done    : integer := -1;
         variable cart_wr_now  : boolean := false;
         variable latch_seen   : natural := 0;
         variable ff00_fall    : boolean := false;   -- pins showed a write to $FF00 when PHI2 fell
         variable ff00_now     : boolean := false;   -- the CPU wrote $FF00 in this cycle
         variable umax_prev    : std_logic := '0';
         variable sampled_u    : boolean := false;
         file     tf           : text;
         variable tl           : line;
         variable topen        : boolean := false;
      begin
         if rising_edge(clk) then
            -- open the trace file on the first clock
            if CFG.trace = 1 and not topen then
               file_open(tf, "trace.txt", write_mode);
               topen := true;
            end if;

            -- time of the last cpuAddr change (pre-edge view)
            if cpuAddr /= addr_prev then
               addr_change := now - TCLK;
               addr_prev := cpuAddr;
            end if;

            -- a strobe (ROML/ROMH/unmapped) pulse at the pins that ends without a CPU sample
            if sim_crt = '0' then
               if cpu_strobe_n_q = '0' and strobe_prev = '1' then
                  strobe_pulses <= strobe_pulses + 1;
                  sampled := false;
               end if;
               if cpu_strobe_n_q = '1' and strobe_prev = '0' and not sampled then
                  strobe_unsampled <= strobe_unsampled + 1;
               end if;
               strobe_prev := cpu_strobe_n_q;
               if umax_q = '1' and umax_prev = '0' then
                  sampled_u := false;
               end if;
               if umax_q = '0' and umax_prev = '1' and not sampled_u then
                  umax_unsampled <= umax_unsampled + 1;
               end if;
               umax_prev := umax_q;
            end if;
            if turbo_ef3_pause = '1' then
               pause_clocks <= pause_clocks + 1;
            end if;

            if cyc_synced and reset_n = '1' then
               -- I5: fixed enables (pre-edge values belong to the clock with index cyc)
               if (enableVic = '1') /= (cyc = 15 or cyc = 31) or
                  (enableCia_n = '1') /= (cyc = 29) or
                  (enableCia_p = '1') /= (cyc = 0) or
                  (enableSid = '1') /= (cyc = 0) then
                  en_pattern_err <= en_pattern_err + 1;
               end if;

               -- decision points of the turbo logic: edges that end CYCLE_EXT1 and CYCLE_EXT5
               if cyc = 1 or cyc = 9 then
                  if (cs_vic or cs_sid or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i) = '1' then
                     csio_dec <= csio_dec + 1;
                  end if;
                  if cpuHasBus = '1' then
                     hasbus_dec <= hasbus_dec + 1;
                  end if;
               end if;
               if cyc = 9 then
                  dma_dec := dma_req;
               end if;
               if cyc = 0 then
                  cyc_start := now - TCLK;
               end if;
               if cyc = 30 then                       -- PHI2 falls at this edge
                  ff00_fall := cart_out_a_q = x"FF00" and cart_out_rw_q = '0';
               end if;
               if is_an_ef3 = '1' then
                  ef3_seen <= true;
               end if;

               -- CPU bus access completing at this edge
               en := enableCpu = '1' and dma_active = '0';
               if en then
                  slot := (cyc - 3) mod 32;
                  a := cpuAddr;
                  is_sim  := sim_crt = '1' and (core_roml = '1' or core_romh = '1');
                  is_cart := sim_crt = '0' and (core_roml = '1' or core_romh = '1' or core_umax_unmapped = '1' or
                                                core_ioe = '1' or core_iof = '1');
                  -- I/O = VIC, SID, color RAM, CIA1, CIA2, IO1, IO2 as decoded by the PLA (not $Dxxx
                  -- character ROM or RAM)
                  is_io   := (cs_vicLoc or cs_sidLoc or cs_colorLoc or cs_cia1Loc or cs_cia2Loc or
                              cs_ioELoc or cs_ioFLoc) = '1';
                  if slot /= 16 and slot /= 20 and slot /= 24 and slot /= 28 then
                     report "TB_ERROR: CPU access in an unexpected state, index " & integer'image(slot) severity error;
                  end if;
                  if dma_dec = '1' then
                     dma_cpu <= dma_cpu + 1;
                  end if;

                  -- S2: every I/O access at CYCLE_CPUC of a clean cycle
                  if is_io then
                     io_acc <= io_acc + 1;
                     if slot /= 28 or last_slot /= -1 then
                        io_viol <= io_viol + 1;
                        report "S2 violation: I/O access to $" & hex(a) & " in state " & integer'image(slot) &
                               " after an access in state " & integer'image(last_slot) severity note;
                     end if;
                  end if;

                  -- expected data of every CPU read, in the dataToCpu priority of fpga64_buslogic;
                  -- a source that delivers stale data (too much latency) fails here
                  src := 0;
                  exp_v := x"00";
                  if cpuWe = '0' then
                     if sim_crt = '0' then cs := 4; else cs := 5; end if;
                     if cs_CharLoc = '1' then
                        src := 3; exp_v := CHARROM(to_integer(a(11 downto 0)));
                     elsif cs_UMAXnomapLoc = '1' then
                        if sim_crt = '0' then
                           src := 4;
                           if a(15 downto 8) = x"10" then
                              exp_v := uram(to_integer(a(7 downto 0)));
                           else
                              exp_v := unmapped_pattern(a);
                           end if;
                        else
                           src := 1; exp_v := ram(to_integer(a));
                        end if;
                     elsif cs_romLoc = '1' then
                        src := 2; exp_v := KROM(to_integer(a(14) & a(12 downto 0)));
                     elsif cs_ramLoc = '1' then
                        if a > 1 then              -- $0000/$0001 are the 6510 port
                           src := 1; exp_v := ram(to_integer(a));
                        end if;
                     elsif cs_romLLoc = '1' then
                        src := cs; exp_v := CART(to_integer(a(12 downto 0)));
                     elsif cs_romHLoc = '1' then
                        src := cs; exp_v := CART(8192 + to_integer(a(12 downto 0)));
                     elsif core_iof = '1' then
                        src := cs; exp_v := io2ram(to_integer(a(7 downto 0)));
                     elsif core_ioe = '1' then
                        src := cs; exp_v := io1reg;
                     end if;
                  end if;
                  check_data := src /= 0;
                  if check_data then
                     rd_chk(src) <= rd_chk(src) + 1;
                     if slot /= 28 then
                        rd_turbo(src) <= rd_turbo(src) + 1;
                     end if;
                     if cpuDi /= exp_v then
                        rd_err(src) <= rd_err(src) + 1;
                        if rd_err(src) < 4 then
                           report "read data error (source " & integer'image(src) & "): $" & hex(a) & " got $" &
                                  hex(cpuDi) & " expected $" & hex(exp_v) & " in state " & integer'image(slot)
                                  severity note;
                        end if;
                     end if;
                  end if;
                  -- every CPU write to RAM must reach the RAM during this access
                  if cpuWe = '1' and cs_ramLoc = '1' then
                     wr_chk <= wr_chk + 1;
                     if slot /= 28 then
                        wr_turbo <= wr_turbo + 1;
                     end if;
                     if not (last_wr_time > prev_en and last_wr_addr = a and last_wr_data = cpuDo) then
                        wr_err <= wr_err + 1;
                        if wr_err < 4 then
                           report "RAM write lost: $" & hex(a) & " <- $" & hex(cpuDo) & " in state " & integer'image(slot)
                                  severity note;
                        end if;
                     end if;
                  end if;
                  prev_en := now;

                  -- F2 / I2: real-cartridge accesses
                  cart_wr_now := is_cart and cpuWe = '1';
                  if cpuWe = '1' and a = x"FF00" then
                     ff00_wr <= ff00_wr + 1;
                     ff00_now := true;
                  end if;
                  if is_cart then
                     sampled := true;
                     if core_umax_unmapped = '1' then
                        sampled_u := true;
                     end if;
                     k := 0;
                     if last_slot = 16 then k := 1; elsif last_slot = 20 then k := 2; elsif last_slot = 24 then k := 3; end if;
                     avail := now - TCLK - pin_change;    -- pins stable until the cart_in_d_q / PHI2-fall edge
                     cart_acc(k) <= cart_acc(k) + 1;
                     if avail < cart_min(k) then
                        cart_min(k) <= avail;
                     end if;
                     if cpuWe = '1' then
                        cart_wr <= cart_wr + 1;
                     end if;
                     if slot /= 28 or last_slot /= -1 then
                        cart_viol <= cart_viol + 1;
                     end if;
                     if addr_change > cyc_start then
                        cart_addr_late <= cart_addr_late + 1;
                     end if;
                     if check_data and src = 4 and cpuDi /= exp_v then
                        cart_rd_err <= cart_rd_err + 1;
                        if cart_rd_err < 8 then
                           report "F2 data error: read $" & hex(a) & " got $" & hex(cpuDi) & " expected $" & hex(exp_v) &
                                  ", pins stable " & ns_str(avail) & " ns, previous access in state " &
                                  integer'image(last_slot) severity note;
                        end if;
                     end if;
                  end if;

                  -- S7: SIMCRT reads
                  if is_sim and cpuWe = '0' then
                     sim_rd <= sim_rd + 1;
                     if slot /= 28 then
                        sim_rd_turbo <= sim_rd_turbo + 1;
                     end if;
                     if src = 5 and cpuDi /= exp_v then
                        sim_rd_err <= sim_rd_err + 1;
                     end if;
                  end if;

                  -- S4: a write to $D030 (or a mirror) decides the next 1 MHz cycle
                  if cpuWe = '1' and a(15 downto 8) = x"D0" and a(5 downto 0) = "110000" then
                     d030_check := cycle_no + 1;
                     d030_val := cpuDo(0);
                  end if;
                  if cpuWe = '0' and a = x"D030" and reset_seen and first_d030_after_reset = -1 then
                     first_d030_after_reset <= to_integer(cpuDi);
                  end if;

                  if slot >= 16 and slot <= 28 then
                     mask := mask + 2 ** ((slot - 16) / 4);
                  end if;
                  n_acc := n_acc + 1;
                  last_slot := slot;
               end if;

               -- end of a 1 MHz cycle: the edge that ends CYCLE_CPUF
               if cyc = 31 then
                  -- the cartridge latched a write when PHI2 fell (previous edge): was it a CPU write?
                  if cart_latch_cnt /= latch_seen then
                     if not (en and cart_wr_now) then
                        phantom_wr <= phantom_wr + 1;
                        if phantom_wr < 4 then
                           report "phantom cartridge write: R/W low at PHI2 fall for $" & hex(cart_latch_addr) &
                                  " without a CPU write in this cycle" severity note;
                        end if;
                     elsif cart_latch_addr /= cpuAddr or cart_latch_data /= cpuDo then
                        wr_data_err <= wr_data_err + 1;
                     end if;
                     latch_seen := cart_latch_cnt;
                  elsif cart_wr_now and sim_crt = '0' then
                     missing_wr <= missing_wr + 1;
                     if missing_wr < 4 then
                        report "cartridge write not latched by the cartridge: $" & hex(cpuAddr) severity note;
                     end if;
                  end if;
                  cart_wr_now := false;
                  -- a CPU write to $FF00 in this cycle must be on the pins when PHI2 falls (REU trigger)
                  if ff00_now and not ff00_fall then
                     ff00_invisible <= ff00_invisible + 1;
                  end if;
                  ff00_now := false;
                  if (mask mod 8) /= 0 then
                     turbo_cycles <= turbo_cycles + 1;
                  end if;
                  if tchg_cycle >= 0 and tchg_cycle /= tchg_done and (((mask mod 8) /= 0) = tchg_on) then
                     tchg_n <= tchg_n + 1;
                     if cycle_no - tchg_cycle > tchg_max then
                        tchg_max <= cycle_no - tchg_cycle;
                     end if;
                     tchg_done := tchg_cycle;
                  end if;
                  -- S1: RAM-only loop
                  if phase = 2 then
                     s1_hist(n_acc) <= s1_hist(n_acc) + 1;
                     if CFG.mode = 0 then
                        expmask := 8;
                     elsif CFG.speed = 0 then
                        expmask := 8 + 2;
                     elsif CFG.speed = 1 then
                        expmask := 8 + 4 + 2;
                     else
                        expmask := 15;
                     end if;
                     if mask = expmask then
                        s1_ok <= s1_ok + 1;
                     else
                        s1_bad <= s1_bad + 1;
                        s1_badmask <= mask;
                     end if;
                  end if;
                  -- S3: DMA
                  if dma_dec = '1' then
                     dma_cyc <= dma_cyc + 1;
                     dma_seen := true;
                     if (mask mod 8) /= 0 or turbo_m /= "000" then
                        dma_turbo <= dma_turbo + 1;
                     end if;
                  elsif dma_seen and phase = 5 and (mask mod 8) /= 0 then
                     dma_after_turbo <= dma_after_turbo + 1;
                  end if;
                  -- S4: turbo state in the cycle after a $D030 write
                  if d030_check = cycle_no then
                     if d030_val = '1' then
                        d030_on_n <= d030_on_n + 1;
                        if (CFG.mode = 1) = ((mask mod 8) /= 0) or CFG.mode = 2 then
                           d030_on_ok <= d030_on_ok + 1;
                        end if;
                     else
                        d030_off_n <= d030_off_n + 1;
                        if (mask mod 8) = 0 or CFG.mode = 2 then
                           d030_off_ok <= d030_off_ok + 1;
                        end if;
                     end if;
                     d030_check := -1;
                  end if;
                  mask := 0;
                  n_acc := 0;
                  last_slot := -1;
               end if;
            end if;

            if CFG.trace = 1 and reset_n = '1' and cyc_synced then
               write(tl, integer'image(cyc) & " " & hex(cpuAddr) & " " & std_logic'image(cpuWe)(2) &
                         std_logic'image(enableCpu)(2) & std_logic'image(dma_active)(2) & " " &
                         hex(ram_addr) & " " & std_logic'image(ram_ce)(2) & std_logic'image(ram_we_raw)(2) & " " &
                         hex(ram_dout) & " " & hex(ram_din) & " " &
                         std_logic'image(core_roml)(2) & std_logic'image(core_romh)(2) &
                         std_logic'image(core_umax_romh)(2) & std_logic'image(core_umax_unmapped)(2) &
                         std_logic'image(core_ioe)(2) & std_logic'image(core_iof)(2) &
                         std_logic'image(core_phi2)(2) & std_logic'image(core_ba)(2) & " " &
                         hex(cart_out_a_q) & " " & std_logic'image(cart_out_roml_n_q)(2) &
                         std_logic'image(cart_out_romh_n_q)(2) & std_logic'image(cart_out_io1_n_q)(2) &
                         std_logic'image(cart_out_io2_n_q)(2) & std_logic'image(cart_out_rw_q)(2) &
                         std_logic'image(cart_out_sel)(2) & std_logic'image(cart_data_oe)(2) & " " &
                         hex(cart_d_o) & " " & hex(cart_in_data) & " " & std_logic'image(is_an_ef3)(2) &
                         std_logic'image(exp_port_we)(2));
               writeline(tf, tl);
            end if;
         end if;
      end process;

      -------------------------------------------------------------------------------------------
      -- Stimulus and final report
      -------------------------------------------------------------------------------------------
      stim : process
         variable t_mode  : std_logic_vector(1 downto 0);
         variable t_speed : std_logic_vector(1 downto 0);
         variable timeout : boolean := false;
         variable last_phase : integer;
         variable v0f     : unsigned(7 downto 0);
         variable p_ok    : boolean;
         variable sum     : natural;
         variable ts_before_reset : std_logic;
         variable results : line;

         procedure kv(key : string; val : string) is
            variable l : line;
         begin
            write(l, "TB: " & key & "=" & val);
            writeline(output, l);
         end procedure;

         procedure wait_cycles(n : natural) is
         begin
            for i in 1 to n loop
               wait until rising_edge(clk) and cyc = 31;
            end loop;
         end procedure;

         procedure wait_phase(p : integer; maxc : natural) is
            variable c0 : natural;
         begin
            c0 := cycle_no;
            while phase /= p loop
               wait until rising_edge(clk);
               if cycle_no - c0 > maxc then
                  timeout := true;
                  return;
               end if;
            end loop;
         end procedure;

         function bool_s(b : boolean) return string is
         begin
            if b then return "yes"; else return "no"; end if;
         end function;
      begin
         case CFG.mode is
            when 1      => t_mode := "01";
            when 2      => t_mode := "10";
            when others => t_mode := "00";
         end case;
         case CFG.speed is
            when 1      => t_speed := "01";
            when 2      => t_speed := "10";
            when others => t_speed := "00";
         end case;

         reset_n <= '0';
         if CFG.bios = 0 then                 -- custom Kernal: load it through the QNICE port
            for i in 0 to 16383 loop
               c64rom_addr <= std_logic_vector(to_unsigned(i, 14));
               c64rom_data <= std_logic_vector(kpat(i));
               c64rom_we   <= '1';
               wait until rising_edge(clk);
            end loop;
            c64rom_we <= '0';
         end if;
         for i in 1 to 300 loop
            wait until rising_edge(clk);
         end loop;
         reset_n <= '1';

         -- phase 1: booted, the program runs from RAM: apply the turbo settings
         wait_phase(1, 20000);
         turbo_mode  <= t_mode;
         turbo_speed <= t_speed;
         if CFG.mode = 2 then
            tchg_cycle <= cycle_no;
            tchg_on <= true;
         end if;
         kv("booted_cycle", integer'image(cycle_no));

         -- phase 5: request DMA for 20 1 MHz cycles, starting in the middle of a cycle
         if not timeout then
            wait_phase(5, CFG.maxcycles);
         end if;
         if not timeout then
            wait_cycles(10);
            for i in 1 to 18 loop
               wait until rising_edge(clk);   -- now in CYCLE_CPU2: the request comes in mid-cycle
            end loop;
            dma_req <= '1';
            for i in 0 to 19 loop
               dma_addr <= x"0E00" + i;
               wait_cycles(1);
            end loop;
            dma_req <= '0';
            -- Smart: switch the turbo off (as turbo_disk_access does) and on again, mid-cycle
            if CFG.mode = 2 then
               for j in 0 to 3 loop
                  wait_cycles(15);
                  for i in 1 to 5 + 7 * j loop
                     wait until rising_edge(clk);
                  end loop;
                  if j mod 2 = 0 then
                     turbo_mode <= "00";
                  else
                     turbo_mode <= t_mode;
                  end if;
                  tchg_cycle <= cycle_no;
                  tchg_on <= j mod 2 = 1;
               end loop;
            end if;
         end if;

         -- end of the program, or watchdog
         if not timeout then
            wait_phase(255, CFG.maxcycles);
         end if;
         last_phase := phase;
         kv("completed", bool_s(phase = 255));
         kv("last_phase", integer'image(last_phase));
         kv("end_cycle", integer'image(cycle_no));
         ts_before_reset := turbo_state;

         -- result area (only for the phases that were reached)
         if last_phase = 255 or last_phase > 3 then
            p_ok := true;
            for y in 1 to 4 loop
               p_ok := p_ok and ram(16#0F10# + y) = to_unsigned(y, 8)
                            and ram(16#0F18# + y) = (to_unsigned(y, 8) xor x"A0");
            end loop;
            kv("io_results_ok", bool_s(p_ok));
         end if;
         if last_phase = 255 or last_phase > 4 then
            kv("d030_reads", hex(ram(16#0F40#)) & "," & hex(ram(16#0F41#)) & "," & hex(ram(16#0F42#)));
         end if;
         if last_phase = 255 or last_phase > 6 then
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(KROM(x)); end loop;
            p_ok := ram(16#0F70#) = to_unsigned(sum mod 256, 8);
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(KROM(8192 + x)); end loop;
            p_ok := p_ok and ram(16#0F71#) = to_unsigned(sum mod 256, 8);
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(CHARROM(x)); end loop;
            p_ok := p_ok and ram(16#0F72#) = to_unsigned(sum mod 256, 8);
            kv("rom_sums_ok", bool_s(p_ok));
         end if;
         if last_phase = 255 or last_phase > 7 then
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(CART(x)); end loop;
            p_ok := ram(16#0F50#) = to_unsigned(sum mod 256, 8);
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(CART(8192 + 16#1000# + x)); end loop;
            p_ok := p_ok and ram(16#0F51#) = to_unsigned(sum mod 256, 8);
            sum := 0;
            if CFG.simcrt = 0 then
               for x in 1 to 64 loop sum := sum + to_integer(to_unsigned(x, 8) xor x"5A"); end loop;
            end if;
            p_ok := p_ok and ram(16#0F52#) = to_unsigned(sum mod 256, 8);
            sum := 0;
            for x in 1 to 64 loop sum := sum + to_integer(CART(16#1100# + x)); end loop;
            p_ok := p_ok and ram(16#0F53#) = to_unsigned(sum mod 256, 8);
            if CFG.simcrt = 0 then
               p_ok := p_ok and ram(16#0F54#) = x"77";
            else
               p_ok := p_ok and ram(16#0F54#) = x"00";
            end if;
            kv("cart_sums_ok", bool_s(p_ok));
            kv("cart_sums", hex(ram(16#0F50#)) & "," & hex(ram(16#0F51#)) & "," & hex(ram(16#0F52#)) & "," &
                            hex(ram(16#0F53#)) & "," & hex(ram(16#0F54#)));
         end if;
         if last_phase = 255 then
            kv("cartcode_ok", bool_s(ram(16#0F60#) = x"A0" and ram(16#0F61#) = x"20"));
         end if;

         -- statistics
         kv("s1_hist", integer'image(s1_hist(0)) & "," & integer'image(s1_hist(1)) & "," & integer'image(s1_hist(2)) & "," &
                       integer'image(s1_hist(3)) & "," & integer'image(s1_hist(4)) & "," & integer'image(s1_hist(5)));
         kv("s1_ok", integer'image(s1_ok));
         kv("s1_bad", integer'image(s1_bad));
         kv("s1_badmask", integer'image(s1_badmask));
         kv("turbo_cycles", integer'image(turbo_cycles));
         kv("io_acc", integer'image(io_acc));
         kv("io_viol", integer'image(io_viol));
         kv("dma_cyc", integer'image(dma_cyc));
         kv("dma_cpu", integer'image(dma_cpu));
         kv("dma_turbo", integer'image(dma_turbo));
         kv("dma_after_turbo", integer'image(dma_after_turbo));
         kv("d030_on", integer'image(d030_on_ok) & "/" & integer'image(d030_on_n));
         kv("d030_off", integer'image(d030_off_ok) & "/" & integer'image(d030_off_n));
         for i in 0 to 3 loop
            kv("cart_acc" & integer'image(i), integer'image(cart_acc(i)));
            if cart_acc(i) > 0 then
               kv("cart_min" & integer'image(i) & "_ns", ns_str(cart_min(i)));
               kv("cart_min" & integer'image(i) & "_clk", integer'image(cart_min(i) / TCLK));
            end if;
         end loop;
         kv("cart_wr", integer'image(cart_wr));
         kv("cart_rd_err", integer'image(cart_rd_err));
         kv("cart_wr_setup_viol", integer'image(wr_setup_viol));
         kv("cart_phantom_wr", integer'image(phantom_wr));
         kv("cart_missing_wr", integer'image(missing_wr));
         kv("cart_wr_data_err", integer'image(wr_data_err));
         kv("cart_wr_window_viol", integer'image(wr_window_viol));
         kv("ff00_wr", integer'image(ff00_wr));
         kv("ff00_invisible", integer'image(ff00_invisible));
         kv("ef3_detected", bool_s(ef3_seen));
         kv("ef3_pause_clocks", integer'image(pause_clocks));
         kv("umax_unsampled", integer'image(umax_unsampled));
         kv("board", G_BOARD);
         kv("cart_viol", integer'image(cart_viol));
         kv("cart_addr_late", integer'image(cart_addr_late));
         kv("strobe_pulses", integer'image(strobe_pulses));
         kv("strobe_unsampled", integer'image(strobe_unsampled));
         kv("sim_rd", integer'image(sim_rd));
         kv("sim_rd_turbo", integer'image(sim_rd_turbo));
         kv("sim_rd_err", integer'image(sim_rd_err));
         for i in 1 to 5 loop
            kv("rd_chk" & integer'image(i), integer'image(rd_chk(i)));
            kv("rd_turbo" & integer'image(i), integer'image(rd_turbo(i)));
            kv("rd_err" & integer'image(i), integer'image(rd_err(i)));
         end loop;
         kv("wr_chk", integer'image(wr_chk));
         kv("wr_turbo", integer'image(wr_turbo));
         kv("wr_err", integer'image(wr_err));
         kv("csio_at_decision", integer'image(csio_dec));
         kv("cpuhasbus_at_decision", integer'image(hasbus_dec));
         kv("en_pattern_err", integer'image(en_pattern_err));
         kv("turbo_switch_n", integer'image(tchg_n));
         kv("turbo_switch_max_latency", integer'image(tchg_max));

         -- C128: a reset clears the $D030 bit
         if CFG.mode = 1 then
            kv("turbo_state_before_reset", std_logic'image(ts_before_reset)(2 to 2));
            reset_n <= '0';
            for i in 1 to 300 loop
               wait until rising_edge(clk);
            end loop;
            kv("turbo_state_in_reset", std_logic'image(turbo_state)(2 to 2));
            reset_seen <= true;
            reset_n <= '1';
            wait until rising_edge(clk);
            timeout := false;
            wait_phase(1, 20000);
            kv("reboot_completed", bool_s(not timeout));
            kv("d030_after_reset", integer'image(first_d030_after_reset));
         end if;

         kv("bench_done", "yes");
         stop_clk <= true;
         wait for 10 * TCLK;
         stop;
         wait;
      end process;

      -- phase marker: RAM write to $0FF0
      phase_proc : process (clk)
      begin
         if rising_edge(clk) then
            if reset_n = '0' then
               phase <= 0;
            elsif ram_wr = '1' and ram_addr = x"0FF0" then
               phase <= to_integer(ram_dout);
            end if;
         end if;
      end process;
   end block mon;

end architecture sim;
