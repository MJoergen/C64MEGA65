----------------------------------------------------------------------------------
-- Behavioral model of the QNICE SD card controller at its register interface
--
-- This architecture replaces the architecture of M2M/QNICE/vhdl/sdcard.vhd in the
-- simulation: the simulation driver appends it to the unmodified entity declaration
-- of that file. Registers and command codes are those of the real controller:
--
--    0 : low word of the 32-bit block address
--    1 : high word of the 32-bit block address
--    2 : cursor into the 512-byte buffer
--    3 : read/write one byte of the buffer at the cursor
--    4 : error code of the last operation (read only)
--    5 : command (0 = reset, 1 = read block, 2 = write block) and status:
--        bit 15 = busy, bit 14 = error, bits 13..12 = card type (11 = SDHC)
--
-- The card content comes from the text file "sdcard.blk" in the working directory
-- of the simulation run: one line per block that is not all zero,
--
--    <block number, decimal> <1024 hexadecimal digits>
--
-- All other blocks read as zero. The model does not use the SPI pins of the entity,
-- with one exception: the testbench signals via sd_miso whether a card is inserted
-- ('0' = card inserted, '1' = no card), so that a script can insert and remove the
-- card. Without a card, and if the file does not exist, the model behaves like a
-- controller without a card: every command ends with the error flag set and the
-- error code 0xFF07 ("no SD card" of the real controller in the low byte).
-- Every command is logged to "sd.log".
----------------------------------------------------------------------------------

architecture model of sdcard is

   constant C_BUSY_CYCLES : natural := 64;      -- duration of a command
   constant C_BLK_FILE    : string  := "sdcard.blk";
   constant C_MAX_BLOCKS  : natural := 16384;   -- blocks that are not all zero

   signal reg_addr_lo   : std_logic_vector(15 downto 0) := (others => '0');
   signal reg_addr_hi   : std_logic_vector(15 downto 0) := (others => '0');
   signal reg_data_pos  : std_logic_vector(15 downto 0) := (others => '0');
   signal rd_byte       : std_logic_vector(7 downto 0)  := (others => '0');
   signal is_busy       : std_logic := '0';
   signal is_error      : std_logic := '0';
   signal err_code      : std_logic_vector(15 downto 0) := (others => '0');
   signal card_type     : std_logic_vector(1 downto 0)  := "00";

begin

   sd_reset <= '1';
   sd_clk   <= '0';
   sd_mosi  <= '1';

   read_registers : process (all)
   begin
      data_out <= (others => '0');
      if en = '1' and we = '0' then
         case reg is
            when "000"  => data_out <= reg_addr_lo;
            when "001"  => data_out <= reg_addr_hi;
            when "010"  => data_out <= reg_data_pos;
            when "011"  => data_out <= x"00" & rd_byte;
            when "100"  => data_out <= err_code;
            when "101"  => data_out <= is_busy & is_error & card_type & x"000";
            when others => data_out <= (others => '0');
         end case;
      end if;
   end process read_registers;

   -- like the real controller, the registers are written at the falling clock edge
   main : process (clk)
      type     blk_t     is array (0 to 511) of natural range 0 to 255;
      type     blk_ptr   is access blk_t;
      type     lba_arr_t is array (0 to C_MAX_BLOCKS - 1) of integer;
      type     ptr_arr_t is array (0 to C_MAX_BLOCKS - 1) of blk_ptr;
      variable lbas      : lba_arr_t := (others => -1);
      variable ptrs      : ptr_arr_t;
      variable n_blk     : natural := 0;
      variable loaded    : boolean := false;
      variable has_card  : boolean := false;
      variable buf       : blk_t := (others => 0);
      variable busy_cnt  : natural := 0;
      variable pend_cmd  : natural := 0;                -- 1 = reset, 2 = read, 3 = write
      variable lba       : integer;
      variable idx       : integer;
      variable pos       : natural;
      variable sum       : natural;
      file     logf      : text;
      variable l         : line;
      file     wlogf     : text;
      variable wl        : line;

      function hexval(c : character) return natural is
      begin
         case c is
            when '0' to '9' => return character'pos(c) - character'pos('0');
            when 'a' to 'f' => return character'pos(c) - character'pos('a') + 10;
            when 'A' to 'F' => return character'pos(c) - character'pos('A') + 10;
            when others     => return 0;
         end case;
      end function;

      impure function find(b : integer) return integer is
      begin
         for i in 0 to n_blk - 1 loop
            if lbas(i) = b then
               return i;
            end if;
         end loop;
         return -1;
      end function;

      procedure load_image is
         file     f      : text;
         variable st     : file_open_status;
         variable fl     : line;
         variable n      : integer;
         variable hex    : string(1 to 1024);
         variable p      : blk_ptr;
      begin
         file_open(st, f, C_BLK_FILE, read_mode);
         if st /= open_ok then
            has_card := false;
            return;
         end if;
         has_card := true;
         while not endfile(f) loop
            readline(f, fl);
            next when fl'length < 1026;
            read(fl, n);
            read(fl, hex(1 to 1));                       -- the blank
            read(fl, hex);
            p := new blk_t;
            for i in 0 to 511 loop
               p(i) := hexval(hex(2 * i + 1)) * 16 + hexval(hex(2 * i + 2));
            end loop;
            assert n_blk < C_MAX_BLOCKS report "sdcard model: too many blocks" severity failure;
            lbas(n_blk) := n;
            ptrs(n_blk) := p;
            n_blk := n_blk + 1;
         end loop;
         file_close(f);
      end procedure;

      procedure log(s : string) is
         constant t_us : natural := now / 1 us;
      begin
         write(l, integer'image(t_us) & " " & s);
         writeline(logf, l);
         flush(logf);
      end procedure;
   begin
      if falling_edge(clk) then
         if not loaded then
            loaded := true;
            file_open(logf, "sd.log", write_mode);
            file_open(wlogf, "sdwrites.log", write_mode);
            load_image;
            if has_card then
               log("card image loaded, non-zero blocks: " & integer'image(n_blk));
            else
               log("no card image (" & C_BLK_FILE & " not found): controller reports errors");
            end if;
         end if;

         -- running command
         if busy_cnt > 0 then
            busy_cnt := busy_cnt - 1;
            if busy_cnt = 0 then
               is_busy <= '0';
               lba := to_integer(unsigned(reg_addr_hi(14 downto 0)) & unsigned(reg_addr_lo));
               if not has_card or sd_miso /= '0' then
                  is_error  <= '1';
                  err_code  <= x"FF07";
                  card_type <= "00";
                  log("cmd " & integer'image(pend_cmd) & " failed: no card");
               else
                  is_error  <= '0';
                  err_code  <= x"0000";
                  card_type <= "11";
                  case pend_cmd is
                     when 1 =>
                        log("reset");
                     when 2 =>
                        idx := find(lba);
                        if idx < 0 then
                           buf := (others => 0);
                        else
                           buf := ptrs(idx).all;
                        end if;
                        log("read  " & integer'image(lba));
                     when 3 =>
                        idx := find(lba);
                        if idx < 0 then
                           assert n_blk < C_MAX_BLOCKS report "sdcard model: too many blocks" severity failure;
                           idx := n_blk;
                           lbas(idx) := lba;
                           ptrs(idx) := new blk_t;
                           n_blk := n_blk + 1;
                        end if;
                        ptrs(idx).all := buf;
                        sum := 0;
                        for i in 0 to 511 loop
                           sum := (sum * 31 + buf(i)) mod 16777216;
                        end loop;
                        log("write " & integer'image(lba) & " hash " & integer'image(sum));
                        -- simulation tools: the written data as hexadecimal digits (sdwrites.log)
                        write(wl, integer'image(lba) & " ");
                        wdump : for i in 0 to 511 loop
                           write(wl, to_hstring(to_unsigned(buf(i), 8)));
                        end loop;
                        writeline(wlogf, wl);
                        flush(wlogf);
                     when others => null;
                  end case;
               end if;
            end if;
         end if;

         -- register writes
         if en = '1' and we = '1' then
            case reg is
               when "000" => reg_addr_lo  <= data_in;
               when "001" => reg_addr_hi  <= data_in;
               when "010" => reg_data_pos <= data_in;
               when "011" =>
                  if busy_cnt = 0 then
                     buf(to_integer(unsigned(reg_data_pos(8 downto 0)))) := to_integer(unsigned(data_in(7 downto 0)));
                  end if;
               when "101" =>
                  if data_in = x"0000" then
                     pend_cmd := 1;
                     busy_cnt := C_BUSY_CYCLES;
                     is_busy  <= '1';
                     is_error <= '0';
                  elsif data_in = x"0001" and busy_cnt = 0 then
                     pend_cmd := 2;
                     busy_cnt := C_BUSY_CYCLES;
                     is_busy  <= '1';
                  elsif data_in = x"0002" and busy_cnt = 0 then
                     pend_cmd := 3;
                     busy_cnt := C_BUSY_CYCLES;
                     is_busy  <= '1';
                  end if;
               when others => null;
            end case;
         end if;

         -- the buffer is read at the falling clock edge (byte_bram of the real controller)
         if en = '1' and we = '1' and reg = "010" then
            pos := to_integer(unsigned(data_in(8 downto 0)));
         else
            pos := to_integer(unsigned(reg_data_pos(8 downto 0)));
         end if;
         rd_byte <= std_logic_vector(to_unsigned(buf(pos), 8));

         -- reset by the SD card multiplexer: the controller initializes the card
         if reset = '1' then
            reg_addr_lo  <= (others => '0');
            reg_addr_hi  <= (others => '0');
            reg_data_pos <= (others => '0');
            pend_cmd     := 1;
            busy_cnt     := C_BUSY_CYCLES;
            is_busy      <= '1';
            is_error     <= '0';
         end if;
      end if;
   end process main;

end architecture model;
