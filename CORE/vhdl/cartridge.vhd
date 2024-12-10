----------------------------------------------------------------------------------
-- Commodore 64 for MEGA65
--
-- This is a replacement for MiSTer's cartridge.v file. The reason for the replacement
-- is that we use a different mapping from Bank Number to HyperRAM address.
--
-- done by MJoergen in 2023 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cartridge is
   port (
      clk_i          : in  std_logic;
      rst_i          : in  std_logic;

      -- From CRT file
      cart_loading_i : in  std_logic;
      cart_id_i      : in  std_logic_vector(15 downto 0);
      cart_exrom_i   : in  std_logic_vector( 7 downto 0);
      cart_game_i    : in  std_logic_vector( 7 downto 0);
      cart_size_i    : in  std_logic_vector(22 downto 0);

      -- From C64
      ioe_i          : in  std_logic;
      iof_i          : in  std_logic;
      wr_en_i        : in  std_logic;
      wr_data_i      : in  std_logic_vector( 7 downto 0);
      addr_i         : in  std_logic_vector(15 downto 0);

      -- To crt_cacher
      bank_lo_o      : out std_logic_vector( 6 downto 0);
      bank_hi_o      : out std_logic_vector( 6 downto 0);

      -- To C64
      ioe_wr_ena_o   : out std_logic; -- 1: $DExx contains RAM, 0: $DExx read mirrors $9Exx
      iof_wr_ena_o   : out std_logic; -- 1: $DFxx contains RAM, 0: $DFxx read mirrors $9Fxx
      io_rom_o       : out std_logic;
      io_ext_o       : out std_logic;
      io_data_o      : out std_logic_vector(7 downto 0);
      exrom_o        : out std_logic;
      game_o         : out std_logic;

      freeze_key_i   : in  std_logic;
      mod_key_i      : in  std_logic;
      nmi_o          : out std_logic;
      nmi_ack_i      : in  std_logic
   );
end entity cartridge;

architecture synthesis of cartridge is

   signal cart_disable : std_logic;
   signal allow_freeze : std_logic;
   signal saved_d6     : std_logic;
   signal ioe_ena      : std_logic;
   signal iof_ena      : std_logic;
   signal roml_we      : std_logic; -- TBD

   signal old_freeze   : std_logic := '0';
   signal old_nmiack   : std_logic := '0';
   signal freeze_req   : std_logic;
   signal freeze_ack   : std_logic;
   signal freeze_crt   : std_logic;

begin

   freeze_req <= not old_freeze and freeze_key_i;
   freeze_ack <= nmi_o and not old_nmiack and nmi_ack_i;
   freeze_crt <= freeze_ack and not mod_key_i;

   process (clk_i)
   begin
      if rising_edge(clk_i) then

         io_rom_o  <= (ioe_i and ioe_ena) or
                      (iof_i and iof_ena);
         io_ext_o  <= '0';
         io_data_o <= X"FF";

         old_freeze <= freeze_key_i;
         if freeze_req = '1' and (allow_freeze = '1' or mod_key_i = '1' ) then
            nmi_o <= '1';
         end if;
         old_nmiack <= nmi_ack_i;
         if freeze_ack = '1' then
            nmi_o <= '0';
         end if;

         if cart_loading_i = '1' then
            ioe_ena      <= '0';
            iof_ena      <= '0';
            game_o       <= '1';
            exrom_o      <= '1';
            bank_lo_o    <= (others => '0');
            bank_hi_o    <= (others => '0');
            nmi_o        <= '0';
            allow_freeze <= '1';
            saved_d6     <= '0';
            ioe_wr_ena_o <= '0';
            iof_wr_ena_o <= '0';
         end if;

         case to_integer(unsigned(cart_id_i)) is
            when 0 =>
               -- Generic 8k, 16k, or ultimax cartridge
               -- No bank swapping
               game_o    <= cart_game_i(0);
               exrom_o   <= cart_exrom_i(0);
               bank_lo_o <= (others => '0');
               bank_hi_o <= (others => '0');

            when 1 =>
               -- Action Replay v4+ - (32k 4x8k banks + 8K RAM)
               -- controlled by DE00
               if nmi_o = '1' then
                  allow_freeze <= '0';
               end if;
               if cart_disable = '1' then
                  exrom_o      <= '1';
                  game_o       <= '1';
                  iof_ena      <= '0';
                  iof_wr_ena_o <= '0';
                  roml_we      <= '0';
                  allow_freeze <= '1';
               else
                  if ioe_i = '1' and wr_en_i = '1' then
                     cart_disable <= wr_data_i(2);
                     bank_lo_o    <= "00000" & wr_data_i(4 downto 3);
                     bank_hi_o    <= "00000" & wr_data_i(4 downto 3);

                     if wr_data_i(6) or allow_freeze then
                        allow_freeze <= '1';
                        game_o       <= not wr_data_i(0);
                        exrom_o      <= wr_data_i(1);
                        iof_wr_ena_o <= wr_data_i(5);
                        roml_we      <= wr_data_i(5);
                        if wr_data_i(5) then
                           bank_lo_o <= (others => '0');
                        end if;
                     end if;
                  end if;
               end if;
               if cart_loading_i = '1' or freeze_crt = '1' then
                  cart_disable <= '0';
                  exrom_o      <= '1';
                  game_o       <= '0';
                  roml_we      <= '0';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
                  iof_wr_ena_o <= '0';
                  iof_ena      <= '1';
                  if cart_loading_i = '1' then
                     exrom_o <= '0';
                     game_o  <= '1';
                  end if;
               end if;

            when 3 =>
               -- Final Cart III - (64k 4x16k banks)
               -- all banks @ $8000-$BFFF - switching by $DFFF
               if cart_disable = '0' then
                  if iof_i = '1' and wr_en_i = '1' and addr_i(7 downto 0) = X"FF" then
                     bank_lo_o  <= "00000" & wr_data_i(1 downto 0);
                     bank_hi_o  <= "00000" & wr_data_i(1 downto 0);
                     exrom_o    <= wr_data_i(4);
                     game_o     <= wr_data_i(5);
                     saved_d6   <= wr_data_i(6);
                     if freeze_key_i = '0' and saved_d6 = '1' and wr_data_i(6) = '0' then
                        nmi_o <= '1';
                     end if;
                     if wr_data_i(6) = '1' then
                        allow_freeze <= '1';
                     end if;
                     cart_disable <= wr_data_i(7);
                  end if;
               end if;
               if freeze_crt = '1' then
                  cart_disable <= '0';
                  exrom_o      <= '1';
                  game_o       <= '0';
                  allow_freeze <= '0';
               end if;
               if cart_loading_i = '1' then
                  game_o     <= '0';
                  exrom_o    <= '0';
                  cart_disable <= '0';
                  bank_lo_o  <= (others => '0');
                  bank_hi_o  <= (others => '0');
                  ioe_ena    <= '1';
                  iof_ena    <= '1';
               end if;

            when 4 =>
               -- Simons BASIC
               -- One low 8k bank, one upper 8k bank which is enabled or disabled
               -- by reading or writing the IO area respectively
               if ioe_i = '1' then
                  game_o <= not wr_en_i;
               end if;
               if cart_loading_i = '1' then
                  game_o    <= '0';
                  exrom_o   <= '0';
                  bank_lo_o <= (others => '0');
                  bank_hi_o <= (others => '0');
               end if;
               
            when 5 =>
               -- Ocean Type 1 - (game=0, exrom=0, 128k,256k or 512k in 8k banks)
               -- BANK is written to lower 6 bits of $DE00 - bit 8 is always set
               -- best to mirror banks at $8000 and $A000
               if ioe_i = '1' and wr_en_i = '1' then
                  bank_lo_o <= "0" & wr_data_i(5 downto 0);
                  -- ROMH is only used for Ocean Type A
                  if game_o = '0' then
                     bank_hi_o <= "0" & wr_data_i(5 downto 0);
                  end if;
               end if;
               -- Autodetect Ocean Type B (512k)
               -- Only $8000 is used, while $A000 is RAM
               if cart_loading_i = '1' then
                  if to_integer(unsigned(cart_size_i)) >= 512*1024 then
                     game_o <= '1';
                  else
                     game_o <= '0';
                  end if;
                  exrom_o   <= '0';
                  bank_lo_o <= (others => '0');
                  bank_hi_o <= (others => '0');
               end if;

            when 7 =>
               -- PowerPlay, FunPlay
               if ioe_i = '1' and wr_en_i = '1' then
                  bank_lo_o <= "0" & wr_data_i(5 downto 0);
                  if wr_data_i(7 downto 6) & wr_data_i(2 downto 1) = "1011" then
                     exrom_o <= '1';
                  end if;
                  if wr_data_i(7 downto 6) & wr_data_i(2 downto 1) = "0000" then
                     exrom_o <= '0';
                  end if;
               end if;
               if cart_loading_i = '1' then
                  game_o  <= '1';
                  exrom_o <= '0';
               end if;

            when 8 =>
               -- "Super Games"
               if iof_i = '1' and wr_en_i = '1' and cart_disable = '0' then
                  bank_lo_o    <= "00000" & wr_data_i(1 downto 0);
                  bank_hi_o    <= "00000" & wr_data_i(1 downto 0);
                  game_o       <= wr_data_i(2);
                  exrom_o      <= wr_data_i(2);
                  cart_disable <= wr_data_i(3);
               end if;
               if cart_loading_i = '1' then
                  cart_disable <= '0';
                  exrom_o      <= '0';
                  game_o       <= '0';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
               end if;

            when 15 =>
               -- C64GS - (game=1, exrom=0, 64 banks by 8k)
               -- 8k config
               -- Reading from IOE ($DE00 $DEFF) switches to bank 0
               game_o  <= '1';
               exrom_o <= '0';
               if ioe_i = '1' and wr_en_i = '0' then
                  bank_lo_o <= (others => '0');
               end if;
               if ioe_i = '1' and wr_en_i = '1' then
                  bank_lo_o <= "0" & addr_i(5 downto 0);
               end if;

            when 17 =>
               -- Dinamic - (game=1, exrom=0, 16 banks by 8k)
               game_o  <= '1';
               exrom_o <= '0';
               if ioe_i = '1' and wr_en_i = '0' then
                  bank_lo_o <= "000" & addr_i(3 downto 0);
               end if;

            when 19 =>
               -- Magic Desk - (game=1, exrom=0 = 4/8/16 8k banks)
               if ioe_i = '1' and wr_en_i = '1' then
                  bank_lo_o <= "000" & wr_data_i(3 downto 0);
                  exrom_o   <= wr_data_i(7);
               end if;
               if cart_loading_i = '1' then
                  game_o    <= '1';
                  exrom_o   <= '0';
                  bank_lo_o <= (others => '0');
                  bank_hi_o <= (others => '0');
               end if;

            when 21 =>
               -- COMAL 80 - (game=0, exrom=0 = 4 16k banks)
               if ioe_i = '1' and wr_en_i = '1' then
                  bank_lo_o <= "00000" & wr_data_i(1 downto 0);
                  bank_hi_o <= "00000" & wr_data_i(1 downto 0);
                  exrom_o   <= wr_data_i(6);
                  game_o    <= wr_data_i(6);
               end if;
               if cart_loading_i = '1' then
                  game_o       <= '0';
                  exrom_o      <= '0';
                  cart_disable <= '0';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
               end if;

            when 22 =>
               -- Waterloo Structured BASIC (game=1, exrom=0, two 8k banks)
               if ioe_i = '1' then
                  bank_lo_o <= "000000" & addr_i(1);
                  exrom_o   <= addr_i(0);
               end if;
               if cart_loading_i = '1' then
                  game_o       <= '1';
                  exrom_o      <= '0';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
               end if;

            when 28 =>
               -- Mikro Assembler - (game=1, exrom=0, one 8k bank, $9e00-$9fff
               -- mirrored at $de00-$dfff)
               if cart_loading_i = '1' then
                  game_o       <= '1';
                  exrom_o      <= '0';
                  cart_disable <= '0';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
                  ioe_wr_ena_o <= '0';
                  iof_wr_ena_o <= '0';
                  ioe_ena      <= '1';
                  iof_ena      <= '1';
               end if;

            when 32 =>
               -- EASYFLASH - 1mb 128x8k/64x16k, XBank format(33) looks the same
               -- upd: original Easyflash(32) boots in ultimax mode.
               if ioe_i = '1' and wr_en_i = '1' then
                  if addr_i(1) = '1' then
                     game_o  <= (not wr_data_i(0)) and wr_data_i(2); -- assume jumper in boot position bit2=0 -> game=0
                     exrom_o <= not wr_data_i(1);
                  else
                     bank_lo_o <= "0" & wr_data_i(5 downto 0);
                     bank_hi_o <= "0" & wr_data_i(5 downto 0);
                  end if;
               end if;
               if cart_loading_i = '1' then
                  iof_ena      <= '1';
                  game_o       <= '0';
                  exrom_o      <= '1';
                  bank_lo_o    <= (others => '0');
                  bank_hi_o    <= (others => '0');
                  iof_wr_ena_o <= '1';
               end if;

            when 60 =>
               -- GMod2
               -- Access to EEPROM just gives 'ready' back.
               -- This is a hack to allow games to proceed when they access the EEPROM.
               io_ext_o  <= ioe_i and not wr_en_i;
               io_data_o <= X"80";
               if ioe_i = '1' and wr_en_i = '1' then
                  exrom_o   <= wr_data_i(6);
                  bank_lo_o <= "0" & wr_data_i(5 downto 0);
               end if;
               if cart_loading_i = '1' then
                  game_o    <= '1';
                  exrom_o   <= '0';
                  bank_lo_o <= (others => '0');
               end if;

            when others =>
               null;
         end case;

         if rst_i = '1' then
            ioe_ena   <= '0';
            iof_ena   <= '0';
            game_o    <= '1';
            exrom_o   <= '1';
            bank_lo_o <= (others => '0');
            bank_hi_o <= (others => '0');
         end if;
      end if;
   end process;

end architecture synthesis;

