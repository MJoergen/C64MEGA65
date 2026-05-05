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
    clk_i          : in    std_logic;
    rst_i          : in    std_logic;

    -- From CRT file
    cart_loading_i : in    std_logic;
    cart_id_i      : in    std_logic_vector(15 downto 0);
    cart_exrom_i   : in    std_logic_vector( 7 downto 0);
    cart_game_i    : in    std_logic_vector( 7 downto 0);
    cart_size_i    : in    std_logic_vector(22 downto 0);

    -- From C64
    ioe_i          : in    std_logic;
    iof_i          : in    std_logic;
    wr_en_i        : in    std_logic;
    wr_data_i      : in    std_logic_vector( 7 downto 0);
    addr_i         : in    std_logic_vector(15 downto 0);

    -- To crt_cacher
    bank_lo_o      : out   std_logic_vector( 6 downto 0);
    bank_hi_o      : out   std_logic_vector( 6 downto 0);

    -- To C64
    ioe_wr_ena_o   : out   std_logic; -- 1: $DExx contains RAM, 0: $DExx read mirrors $9Exx
    iof_wr_ena_o   : out   std_logic; -- 1: $DFxx contains RAM, 0: $DFxx read mirrors $9Fxx
    io_rom_o       : out   std_logic;
    io_ext_o       : out   std_logic;
    io_data_o      : out   std_logic_vector(7 downto 0);
    exrom_o        : out   std_logic;
    game_o         : out   std_logic;
    roml_we_o      : out   std_logic;
    -- Magic Formel: 5-bit page index into the cart's 8 KB SRAM (32 pages * 256 B
    -- mirrored at $DE00). For all other cart_id values this stays at "00000",
    -- which leaves the wrapper's ioe_ram window pointing at its bottom 256 B
    -- (matching the original Action Replay $9Exx mirror behavior).
    ram_page_o     : out   std_logic_vector(4 downto 0);

    freeze_key_i   : in    std_logic;
    mod_key_i      : in    std_logic;
    nmi_o          : out   std_logic;
    nmi_ack_i      : in    std_logic
  );
end entity cartridge;

architecture synthesis of cartridge is

  signal cart_disable : std_logic;
  signal allow_freeze : std_logic;
  signal saved_d6     : std_logic;
  signal ioe_ena      : std_logic;
  signal iof_ena      : std_logic;
  signal freeze_armed : std_logic; -- FC3: distinguishes freeze-button NMI from $DFFF bit-6 software NMI

  signal old_freeze : std_logic := '0';
  signal old_nmiack : std_logic := '0';
  signal freeze_req : std_logic;
  signal freeze_ack : std_logic;
  signal freeze_crt : std_logic;

  -- Magic Formel (cart_id=14) state. Verified vs VICE magicformel.c.
  -- The cart contains an MC6821 PIA whose address inputs are wired so that
  -- A0..A5 -> D0..D5, A6..A7 -> RS0..RS1, CPU D1 -> D7, D6=0. Only the
  -- minimal subset of the PIA is modeled: PRA (RS=00), PRB (RS=10) and CB2
  -- (controlled via CRB at RS=11 in manual-output mode). DDRA/DDRB and the
  -- handshake lines CA1/CA2/CB1 are not modeled.
  signal mf_pia_window     : std_logic;                    -- IO2 write hits the PIA
  signal mf_data           : std_logic_vector(7 downto 0); -- reconstructed PIA data byte
  signal mf_pra            : std_logic_vector(7 downto 0);
  signal mf_prb            : std_logic_vector(7 downto 0);
  signal mf_cb2            : std_logic;                    -- PIA CB2 line (controls freeze)
  signal mf_io1_enabled    : std_logic;                    -- PA4 inverted: IO1 paged SRAM enable
  signal mf_kernal_enabled : std_logic;                    -- PB7: cart visible in Ultimax
  signal mf_freeze_enabled : std_logic;                    -- set on freeze, cleared by CB2=1
  signal mf_ram_page       : std_logic_vector(4 downto 0); -- 5-bit page index into 8 KB SRAM

begin

  freeze_req <= not old_freeze and freeze_key_i;
  freeze_ack <= nmi_o and not old_nmiack and nmi_ack_i;
  freeze_crt <= freeze_ack and freeze_armed and not mod_key_i;

  -- Magic Formel: the PIA only sees IO2 ($DFxx) accesses. Per VICE only the
  -- store side matters; reads from $DFxx are not modeled (the firmware never
  -- relies on PIA reads).
  mf_pia_window <= iof_i and wr_en_i;
  -- Address-as-data trick (verified vs VICE magicformel_io2_store):
  --   data = (addr & 0x3f) | ((value & 2) << 6); D6 is hard-wired to 0.
  mf_data       <= wr_data_i(1) & '0' & addr_i(5 downto 0);

  -- Expose the SRAM page so the wrapper's ioe_ram can mirror $DExx into the
  -- correct 256-byte window of the 8 KB cart SRAM.
  ram_page_o <= mf_ram_page;

  cartridge_proc : process (clk_i)
  begin
    if rising_edge(clk_i) then
      io_rom_o   <= (ioe_i and ioe_ena) or
                    (iof_i and iof_ena);
      io_ext_o   <= '0';
      io_data_o  <= X"FF";

      old_freeze <= freeze_key_i;
      if freeze_req = '1' and (allow_freeze = '1' or mod_key_i = '1') then
        nmi_o        <= '1';
        freeze_armed <= '1';
      end if;
      old_nmiack <= nmi_ack_i;
      if freeze_ack = '1' then
        nmi_o        <= '0';
        freeze_armed <= '0';
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
        freeze_armed <= '0';
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
            roml_we_o    <= '0';
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
                roml_we_o    <= wr_data_i(5);
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
            roml_we_o    <= '0';
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
              bank_lo_o <= "00000" & wr_data_i(1 downto 0);
              bank_hi_o <= "00000" & wr_data_i(1 downto 0);
              exrom_o   <= wr_data_i(4);
              game_o    <= wr_data_i(5);
              saved_d6  <= wr_data_i(6);
              if freeze_key_i = '0' and saved_d6 = '1' and wr_data_i(6) = '0' then
                nmi_o <= '1';
              end if;
              if wr_data_i(6) = '1' then
                allow_freeze <= '1';
              end if;
              cart_disable <= wr_data_i(7);
            end if;
          else
            -- cart hidden by $DFFF bit 7: $DExx/$DFxx must stop responding (cf. VICE fc3_reg_enabled)
            ioe_ena <= '0';
            iof_ena <= '0';
          end if;
          if freeze_crt = '1' then
            cart_disable <= '0';
            exrom_o      <= '1';
            game_o       <= '0';
            allow_freeze <= '0';
            ioe_ena      <= '1'; -- freeze re-enables the cart even if hidden via bit 7
            iof_ena      <= '1';
          end if;
          if cart_loading_i = '1' then
            game_o       <= '0';
            exrom_o      <= '0';
            cart_disable <= '0';
            bank_lo_o    <= (others => '0');
            bank_hi_o    <= (others => '0');
            ioe_ena      <= '1';
            iof_ena      <= '1';
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
            if to_integer(unsigned(cart_size_i)) >= 512 * 1024 then
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

        when 14 =>
          -- Magic Formel V2/V2E/Mod3. EPROM (32/64/128 KB in 8 KB banks at $E000)
          -- + 8 KB SRAM (paged at $DExx) + MC6821 PIA + 7430 glue. Mapping logic
          -- transcribed from VICE magicformel.c:
          --
          --   PA(3:0) -> romh_bank      (V2: 2 used, V2E: 3 used, Mod3: 4 used)
          --   PA4 = 0 -> io1_enabled    (paged SRAM visible at $DExx)
          --   PB7      -> kernal_enabled (cart visible -> Ultimax)
          --   PB(4..0) -> ram_page, with bit-remap (see VICE mf_set_pb):
          --       page(0) = PB(3), page(1) = PB(2), page(2) = PB(0),
          --       page(3) = PB(1), page(4) = PB(4)
          --
          -- EXROM/GAME (per VICE change_config):
          --   kernal_enabled OR freeze_enabled  -> Ultimax  (exrom=1, game=0)
          --   else                              -> no cart  (exrom=1, game=1)
          --
          -- Freeze: magicformel_freeze sets kernal_enabled=1, romh_bank=1,
          -- io1_enabled=1, freeze_enabled=1 (via freeze_flipflop). The freeze
          -- is cleared by CB2=1 (manual output mode in CRB), or by any
          -- subsequent PA/PB write while CB2=1.

          if mf_pia_window = '1' then
            case addr_i(7 downto 6) is

              when "00" =>
                -- RS=00 -> PRA
                mf_pra            <= mf_data;
                bank_lo_o         <= "000" & mf_data(3 downto 0);
                bank_hi_o         <= "000" & mf_data(3 downto 0);
                mf_io1_enabled    <= not mf_data(4);
                ioe_wr_ena_o      <= not mf_data(4);
                if mf_cb2 = '1' then
                  mf_freeze_enabled <= '0';
                end if;

              when "10" =>
                -- RS=10 -> PRB
                mf_prb            <= mf_data;
                mf_ram_page       <= mf_data(4) & mf_data(1) & mf_data(0) &
                                     mf_data(2) & mf_data(3);
                mf_kernal_enabled <= mf_data(7);
                if mf_cb2 = '1' then
                  mf_freeze_enabled <= '0';
                end if;

              when "11" =>
                -- RS=11 -> CRB. We only model the bits that drive CB2:
                --   CRB(5)=1 + CRB(4)=1 -> CB2 = CRB(3) (manual output mode)
                --   CRB(5)=0            -> CB2 input mode, default high
                if mf_data(5) = '1' and mf_data(4) = '1' then
                  mf_cb2 <= mf_data(3);
                  if mf_data(3) = '1' then
                    mf_freeze_enabled <= '0';
                  end if;
                elsif mf_data(5) = '0' then
                  mf_cb2 <= '1';
                end if;

              when others =>
                -- RS=01 (CRA): not modeled
                null;

            end case;
          end if;

          -- EXROM/GAME from current kernal_enabled / freeze_enabled state.
          if mf_kernal_enabled = '1' or mf_freeze_enabled = '1' then
            exrom_o <= '1'; -- Ultimax: /EXROM=1
            game_o  <= '0'; -- Ultimax: /GAME=0
          else
            exrom_o <= '1'; -- no cart visible
            game_o  <= '1';
          end if;

          if cart_loading_i = '1' then
            -- Match VICE magicformel_config_init: kernal_enabled=1 (Ultimax)
            mf_pra            <= (others => '0');
            mf_prb            <= (others => '0');
            mf_cb2            <= '1';
            mf_io1_enabled    <= '0';
            mf_kernal_enabled <= '1';
            mf_freeze_enabled <= '0';
            mf_ram_page       <= (others => '0');
            bank_lo_o         <= (others => '0');
            bank_hi_o         <= (others => '0');
            exrom_o           <= '1';
            game_o            <= '0';
            ioe_wr_ena_o      <= '0';
          end if;

          if freeze_crt = '1' then
            -- Match VICE magicformel_freeze: bank 1, io1_enabled=1, kernal=1,
            -- freeze=1. ram_page is left unchanged (PB is not touched here).
            mf_pra            <= x"01";  -- PA4=0 (io1 ena), bank=1
            mf_io1_enabled    <= '1';
            mf_kernal_enabled <= '1';
            mf_freeze_enabled <= '1';
            bank_lo_o         <= "0000001";
            bank_hi_o         <= "0000001";
            exrom_o           <= '1';
            game_o            <= '0';
            ioe_wr_ena_o      <= '1';
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
          -- Magic Desk - (game=1, exrom=0, up to 128 8k banks)
          if ioe_i = '1' and wr_en_i = '1' then
            bank_lo_o <= wr_data_i(6 downto 0);
            exrom_o   <= wr_data_i(7);
          end if;
          if cart_loading_i = '1' then
            game_o    <= '1';
            exrom_o   <= '0';
            bank_lo_o <= (others => '0');
            bank_hi_o <= (others => '0');
          end if;

        when 20 =>
          -- Super Snapshot V5

          -- Following comment copied from VICE:
          -- - 64K ROM,8*8K Banks (4*16k)
          -- - 32K RAM,4*8K Banks (8k stock, 32k optional)
          --
          -- note: apparently the hardware supports 128k ROMs too, but no such dump exists.
          --
          -- io1: (read)
          --     cart ROM mirror from current 9e00-9eff page. RAM can NOT be mirrored here!
          --
          -- io1 (write)
          --
          -- there is one register mirrored from de00-deff (the software uses de00/de01)
          --
          -- bit 6-7  not connected
          -- bit 5    rom/ram bank bit2 (address line 16) (unused, for 128k ROM)
          -- bit 4    rom/ram bank bit1 (address line 15)
          -- bit 3    !rom enable (0: enabled, 1: disabled)
          --          note: disabling ROM also disables this register
          -- bit 2    rom/ram bank bit0 (address line 14)
          -- bit 1    !ram enable (0: enabled, 1: disabled), !EXROM (0: high, 1: low)
          -- bit 0    GAME (0: low, 1: high)

          if ioe_i = '1' and wr_en_i = '1' and cart_disable = '0' and freeze_crt = '0' then
            roml_we_o    <= not wr_data_i(1);
            bank_lo_o    <= "0000" & wr_data_i(5 downto 4) & wr_data_i(2);
            bank_hi_o    <= "0000" & wr_data_i(5 downto 4) & wr_data_i(2);
            game_o       <= wr_data_i(0) or wr_data_i(3);
            exrom_o      <= (not wr_data_i(1)) or wr_data_i(3);
            ioe_wr_ena_o <= wr_data_i(3);
            ioe_ena      <= not wr_data_i(3);
            cart_disable <= wr_data_i(3);
          end if;

          if cart_loading_i = '1' or freeze_crt = '1' then
            -- Start up in ultimax mode
            roml_we_o    <= '1';
            bank_lo_o    <= (others => '0');
            bank_hi_o    <= (others => '0');
            game_o       <= '0';
            exrom_o      <= '1';
            ioe_wr_ena_o <= '0';
            ioe_ena      <= '1';
            cart_disable <= '0';
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
            game_o    <= '1';
            exrom_o   <= '0';
            bank_lo_o <= (others => '0');
            bank_hi_o <= (others => '0');
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

        when 83 =>
          -- BMP-Data Turbo 2000, (game=0, exrom=0, one 16k bank)
          if wr_en_i = '1' then
            if ioe_i = '1' then
              game_o  <= '0';
              exrom_o <= '0';
            elsif iof_i = '1' then
              game_o  <= '1';
              exrom_o <= '1';
            end if;
          end if;
          if cart_loading_i = '1' then
            game_o    <= '0';
            exrom_o   <= '0';
            bank_lo_o <= (others => '0');
            bank_hi_o <= (others => '0');
          end if;

        when 85 =>
          -- Magic Desk 16K / MD2 - (game=0, exrom=0, up to 128 16k banks)
          if ioe_i = '1' and wr_en_i = '1' then
            bank_lo_o <= wr_data_i(6 downto 0);
            bank_hi_o <= wr_data_i(6 downto 0);
            game_o    <= wr_data_i(7);
            exrom_o   <= wr_data_i(7);
          end if;
          if cart_loading_i = '1' then
            game_o    <= '0';
            exrom_o   <= '0';
            bank_lo_o <= (others => '0');
            bank_hi_o <= (others => '0');
          end if;

        when others =>
          null;

      end case;

      if rst_i = '1' then
        ioe_ena           <= '0';
        iof_ena           <= '0';
        game_o            <= '1';
        exrom_o           <= '1';
        bank_lo_o         <= (others => '0');
        bank_hi_o         <= (others => '0');
        nmi_o             <= '0';
        allow_freeze      <= '1'; -- Allow RESTORE key to generate NMI
        saved_d6          <= '0';
        ioe_wr_ena_o      <= '0';
        iof_wr_ena_o      <= '0';
        freeze_armed      <= '0';
        -- Magic Formel: VICE magicformel_reset() values (kernal_enabled=0).
        -- magicformel_config_init() raises kernal_enabled=1, but that runs in
        -- our model from the cart_loading_i path, not from the rst_i path.
        mf_pra            <= (others => '0');
        mf_prb            <= (others => '0');
        mf_cb2            <= '1';
        mf_io1_enabled    <= '0';
        mf_kernal_enabled <= '0';
        mf_freeze_enabled <= '0';
        mf_ram_page       <= (others => '0');
      end if;
    end if;
  end process cartridge_proc;

end architecture synthesis;

