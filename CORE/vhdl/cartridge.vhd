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
  -- A0..A5 -> D0..D5, A6..A7 -> RS0..RS1, CPU D1 -> D7, D6=0. All six PIA
  -- registers (PRA/DDRA/CRA/PRB/DDRB/CRB) are shadowed; RS=00 selects PRA
  -- vs DDRA based on CRA(2), and RS=10 selects PRB vs DDRB based on CRB(2)
  -- exactly as on real 6821 hardware. Reads return the matching shadow.
  -- CRB(7) is overlaid with the freeze flop on read. CA1/CA2/CB1 handshake
  -- lines are not modeled (VICE doesn't connect them either).
  signal mf_pia_window     : std_logic;                    -- IO2 write hits the PIA
  signal mf_data           : std_logic_vector(7 downto 0); -- reconstructed PIA data byte
  signal mf_pra            : std_logic_vector(7 downto 0);
  signal mf_ddra           : std_logic_vector(7 downto 0);
  signal mf_cra            : std_logic_vector(7 downto 0);
  signal mf_prb            : std_logic_vector(7 downto 0);
  signal mf_ddrb           : std_logic_vector(7 downto 0);
  signal mf_crb            : std_logic_vector(7 downto 0);
  signal mf_cb2            : std_logic;                    -- PIA CB2 line (controls freeze)
  signal mf_cb2state       : std_logic;                    -- CRB STROBE_E mode armed (next PB write strobes CB2)
  signal mf_io1_enabled    : std_logic;                    -- PA4 inverted: IO1 paged SRAM enable
  signal mf_kernal_enabled : std_logic;                    -- PB7: cart visible in Ultimax
  signal mf_freeze_enabled : std_logic;                    -- set on freeze, cleared by CB2=1
  signal mf_ram_page       : std_logic_vector(4 downto 0); -- 5-bit page index into 8 KB SRAM
  -- ROM bank mask: VICE keys off `hwversion` (set by magicformel_crt_attach
  -- from the chip count): hw0 = 64 KiB / 8 banks (`bank & 0x07`); hw1 =
  -- 64+32 KiB / 12 banks; hw2 = 2*64 KiB / 16 banks (both hw1/hw2 use
  -- `bank & 0x0f`). Distinguished here by the staged .crt size.
  signal mf_bank_mask      : std_logic_vector(6 downto 0);
  -- V2 (12-chip / 96 KiB ROM) hardware lacks banks 12-15 physically; chip
  -- selects there read back banks 8-11. VICE replicates this in software
  -- by `memcpy(&rawcart[0x18000], &rawcart[0x10000], 0x8000)` after load.
  -- We don't rearrange HyperRAM, so we instead remap the bank index in
  -- the PA write path: bank N with N>=12 is rewritten to N-4. Active only
  -- when mf_v2_mirror = '1'.
  signal mf_v2_mirror      : std_logic;
  signal mf_bank_remap     : std_logic_vector(3 downto 0);

begin

  freeze_req <= not old_freeze and freeze_key_i;
  freeze_ack <= nmi_o and not old_nmiack and nmi_ack_i;
  freeze_crt <= freeze_ack and freeze_armed and not mod_key_i;

  -- Magic Formel: the PIA sits at IO2 ($DFxx). Writes go through the
  -- address-as-data trick below; reads return the shadowed register values
  -- via io_ext_o/io_data_o (driven inside the when 14 branch).
  mf_pia_window <= iof_i and wr_en_i;
  -- Address-as-data trick (verified vs VICE magicformel_io2_store):
  --   data = (addr & 0x3f) | ((value & 2) << 6); D6 is hard-wired to 0.
  mf_data       <= wr_data_i(1) & '0' & addr_i(5 downto 0);

  -- Expose the SRAM page so the wrapper's ioe_ram can mirror $DExx into the
  -- correct 256-byte window of the 8 KB cart SRAM.
  ram_page_o <= mf_ram_page;

  -- V2 bank-12..15 -> 8..11 mirror. When mf_v2_mirror='1' and PA(3)='1'
  -- (bank >= 8), force PA(2)='0' so 1100..1111 collapse to 1000..1011.
  -- For mf_v2_mirror='0' (V1 / V2E) the bank value passes through unchanged.
  mf_bank_remap <= mf_data(3) &
                   (mf_data(2) and not (mf_data(3) and mf_v2_mirror)) &
                   mf_data(1 downto 0);

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
          -- flop's clear input is the latched CB2 line, so any PIA register
          -- write while CB2=1 re-asserts the clear. We mirror that on every
          -- PRA/CRA/PRB/CRB write.

          if mf_pia_window = '1' then
            case addr_i(7 downto 6) is

              when "00" =>
                -- RS=00 -> PRA (if CRA(2)=1) or DDRA (if CRA(2)=0).
                -- Real 6821 routes the same address to either register
                -- depending on the CR(2) "DDR access" bit. Side effects
                -- (bank, io1_enabled) only apply on PRA writes; firmware
                -- programs DDRA right after reset before raising CRA(2).
                if mf_cra(2) = '1' then
                  mf_pra            <= mf_data;
                  bank_lo_o         <= mf_bank_mask and ("000" & mf_bank_remap);
                  bank_hi_o         <= mf_bank_mask and ("000" & mf_bank_remap);
                  mf_io1_enabled    <= not mf_data(4);
                  -- ioe_ena drives io_rom for $DExx reads (returns cart SRAM
                  -- via main_ioe_ram_data_o); ioe_wr_ena_o gates the matching
                  -- write path in main.vhd. Both follow PA4 inverted.
                  ioe_ena           <= not mf_data(4);
                  ioe_wr_ena_o      <= not mf_data(4);
                else
                  mf_ddra <= mf_data;
                end if;
                if mf_cb2 = '1' then
                  mf_freeze_enabled <= '0';
                end if;

              when "01" =>
                -- RS=01 -> CRA. Per VICE mc6821core_store, CRA writes only
                -- update ctrlA and (in CA2 output mode) drive CA2; they do
                -- NOT call mf_set_pa/pb/cb2, so the freeze flop is left
                -- alone. CA2 has no MF callback registered either, so we
                -- only need to shadow the register.
                mf_cra <= mf_data;

              when "10" =>
                -- RS=10 -> PRB (if CRB(2)=1) or DDRB (if CRB(2)=0).
                if mf_crb(2) = '1' then
                  mf_prb            <= mf_data;
                  mf_ram_page       <= mf_data(4) & mf_data(1) & mf_data(0) &
                                       mf_data(2) & mf_data(3);
                  mf_kernal_enabled <= mf_data(7);
                  -- CRB STROBE_E (mode 01) was armed: a PRB DATA write
                  -- pulses CB2 0 -> 1. Per VICE mc6821core_store, set_cb2
                  -- fires twice (once at 0, once at 1). MF's mf_set_cb2
                  -- calls freeze_flipflop(0,0,CB2), so the rising edge
                  -- clears the freeze flop. Net effect: freeze cleared,
                  -- CB2 ends at 1, strobe disarmed.
                  if mf_cb2state = '1' then
                    mf_cb2            <= '1';
                    mf_freeze_enabled <= '0';
                    mf_cb2state       <= '0';
                  end if;
                else
                  mf_ddrb <= mf_data;
                end if;
                if mf_cb2 = '1' then
                  mf_freeze_enabled <= '0';
                end if;

              when "11" =>
                -- RS=11 -> CRB. Per VICE mc6821core_store, CB2 behavior
                -- depends on CRB(5)/(4)/(3):
                --   bit5=1, bit4=1, bit3=1 -> SET_C2:    CB2 := 1 (freeze cleared)
                --   bit5=1, bit4=1, bit3=0 -> RESET_C2:  CB2 := 0
                --   bit5=1, bit4=0, bit3=1 -> STROBE_E:  arm CB2 strobe on next PB DATA write
                --   bit5=1, bit4=0, bit3=0 -> STROBE_C:  unimplemented in VICE (no-op)
                --   bit5=0                  -> CB2 input: no callback, freeze untouched
                -- mf_set_cb2 fires only on the immediate-update modes.
                mf_crb <= mf_data;
                if mf_data(5) = '1' then
                  if mf_data(4) = '1' then
                    mf_cb2 <= mf_data(3);
                    if mf_data(3) = '1' then
                      mf_freeze_enabled <= '0';
                    end if;
                    mf_cb2state <= '0';
                  elsif mf_data(3) = '1' then
                    mf_cb2state <= '1';
                  end if;
                end if;

              when others =>
                null;

            end case;
          end if;

          -- $DFxx reads: drive the PIA shadow back over the generic
          -- io_ext_o/io_data_o channel. RS=00/RS=10 returns PR or DDR
          -- depending on the matching CR(2) bit (real 6821 behavior).
          -- VICE's mc6821core_read returns
          --     dataX & ddrX | get_pX() & ~ddrX
          -- and Magic Formel does NOT register a get_pa/get_pb callback, so
          -- VICE substitutes 0xFF for the input — i.e. unconnected bits read
          -- back as '1'. The MF firmware checks PA reads to detect itself
          -- and would mis-identify if we returned 0 on the input bits.
          if iof_i = '1' and wr_en_i = '0' then
            io_ext_o <= '1';
            case addr_i(7 downto 6) is
              when "00"   =>
                if mf_cra(2) = '1' then
                  io_data_o <= (mf_pra and mf_ddra) or (not mf_ddra);
                else
                  io_data_o <= mf_ddra;
                end if;
              when "01"   => io_data_o <= mf_cra;
              when "10"   =>
                if mf_crb(2) = '1' then
                  io_data_o <= (mf_prb and mf_ddrb) or (not mf_ddrb);
                else
                  io_data_o <= mf_ddrb;
                end if;
              when others => io_data_o <= mf_crb;
            end case;
          end if;

          -- EXROM/GAME per VICE change_config (mode arg = 2 + bank<<...):
          --   kernal_enabled OR freeze_enabled -> mode 3 = CMODE_ULTIMAX (exrom=1, game=0)
          --   else                             -> mode 2 = CMODE_RAM     (exrom=1, game=1)
          -- The "else" case is "no cartridge visible" — the cart withdraws
          -- itself from the C64 memory map so BASIC ROM ($A000) and KERNAL
          -- ROM ($E000) are restored. (Earlier comment incorrectly labelled
          -- this as CMODE_16KGAME, which would have hidden BASIC and caused
          -- a black screen on first boot.)
          if mf_kernal_enabled = '1' or mf_freeze_enabled = '1' then
            exrom_o <= '1';
            game_o  <= '0';
          else
            exrom_o <= '1';
            game_o  <= '1';
          end if;

          if cart_loading_i = '1' then
            -- Final state after VICE's "attach + first machine reset" chain:
            --   magicformel_config_init: kernal_enabled=1, freeze_flipflop(reset=1)
            --     -> freeze_enabled=1.
            --   magicformel_reset: clears romh_bank/io1/ram_page/kernal, then
            --     mc6821core_reset() zeros all PIA state (incl. CB2=0) and
            --     re-fires the callbacks. mf_set_pa(dataA=0) drives io1=1
            --     (PA4 inverted), mf_set_pb(dataB=0) drives kernal=0. Freeze
            --     is left untouched (CB2=0 holds the clear input low).
            -- Net result: kernal=0, freeze=1, io1=1, CB2=0, PIA regs all 0.
            -- Ultimax is selected via change_config(kernal||freeze).
            mf_pra            <= (others => '0');
            mf_ddra           <= (others => '0');
            mf_cra            <= (others => '0');
            mf_prb            <= (others => '0');
            mf_ddrb           <= (others => '0');
            mf_crb            <= (others => '0');
            mf_cb2            <= '0';
            mf_cb2state       <= '0';
            mf_io1_enabled    <= '1';
            mf_kernal_enabled <= '0';
            mf_freeze_enabled <= '1';
            mf_ram_page       <= (others => '0');
            bank_lo_o         <= (others => '0');
            bank_hi_o         <= (others => '0');
            exrom_o           <= '1';
            game_o            <= '0';
            ioe_ena           <= '1';
            ioe_wr_ena_o      <= '1';
            -- VICE magicformel_crt_attach derives hwversion from the chip
            -- count: 8 chips -> hw0 (bank & 0x07); 12 chips -> hw1; 16
            -- chips -> hw2 (both hw1/hw2 use bank & 0x0f). hw1 also needs
            -- a 12->8 bank mirror for accesses to banks 12..15.
            --
            -- We don't have the chip count here, so we approximate from
            -- the staged .crt file size. Each 8 KiB CHIP packet is 0x10
            -- header + 0x2000 data = 0x2010 bytes; the CRT header is
            -- 0x40 bytes. Expected sizes:
            --   V1  (8 chips): 0x40 + 8*0x2010  = 65728  bytes (64 KiB ROM)
            --   V2  (12 chips): 0x40 + 12*0x2010 = 98656  bytes (96 KiB ROM)
            --   V2E (16 chips): 0x40 + 16*0x2010 = 131584 bytes (128 KiB ROM)
            -- Cleanly separated by thresholds at 80 KiB and 112 KiB.
            if to_integer(unsigned(cart_size_i)) < 80 * 1024 then
              mf_bank_mask <= "0000111";   -- V1
              mf_v2_mirror <= '0';
            elsif to_integer(unsigned(cart_size_i)) < 112 * 1024 then
              mf_bank_mask <= "0001111";   -- V2
              mf_v2_mirror <= '1';
            else
              mf_bank_mask <= "0001111";   -- V2E
              mf_v2_mirror <= '0';
            end if;
          end if;

          if freeze_crt = '1' then
            -- Match VICE magicformel_freeze: bank 1, io1_enabled=1, kernal=1,
            -- and call freeze_flipflop(reset=0, freeze=1, clear=CB2). The flop
            -- has an asynchronous CLEAR wired to CB2, so freeze_enabled only
            -- latches when CB2 is low. ram_page is left unchanged (PB is not
            -- touched here). EXROM/GAME forced to Ultimax via the explicit
            -- cart_config_changed_slotmain(CMODE_ULTIMAX...) in VICE.
            -- Note: VICE does NOT touch the PIA dataA/dataB/ddr registers on
            -- freeze (the firmware reads them back via $DFxx and would see
            -- garbage if we did). It only updates the *side effect* state
            -- variables (romh_bank, io1_enabled, kernal_enabled).
            mf_io1_enabled    <= '1';
            mf_kernal_enabled <= '1';
            if mf_cb2 = '0' then
              mf_freeze_enabled <= '1';
            else
              mf_freeze_enabled <= '0';
            end if;
            bank_lo_o         <= "0000001";
            bank_hi_o         <= "0000001";
            exrom_o           <= '1';
            game_o            <= '0';
            ioe_ena           <= '1';
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
        -- Magic Formel: emulate the VICE magicformel_reset + mc6821core_reset
        -- callback chain. PIA regs zero, CB2=0, io1_enabled=1 (mf_set_pa
        -- with dataA=0 inverts PA4), kernal_enabled=0, ram_page=0. The
        -- freeze flop is intentionally left untouched: VICE's reset path
        -- never calls freeze_flipflop, so a CPU reset does not exit a
        -- pending freeze. ioe_ena / ioe_wr_ena_o follow io1_enabled.
        mf_pra            <= (others => '0');
        mf_ddra           <= (others => '0');
        mf_cra            <= (others => '0');
        mf_prb            <= (others => '0');
        mf_ddrb           <= (others => '0');
        mf_crb            <= (others => '0');
        mf_cb2            <= '0';
        mf_cb2state       <= '0';
        mf_io1_enabled    <= '1';
        mf_kernal_enabled <= '0';
        mf_ram_page       <= (others => '0');
        -- mf_bank_mask / mf_v2_mirror are normally set during
        -- cart_loading_i (which fires before the first PA write); init
        -- here too in case rst_i hits before any cart is staged.
        mf_bank_mask      <= "0001111";
        mf_v2_mirror      <= '0';
        if cart_id_i = x"000E" then
          ioe_ena      <= '1';
          ioe_wr_ena_o <= '1';
          -- Override the global exrom='1', game='1' (NoCart) default: VICE
          -- leaves the freeze flop alone across a CPU reset, and MF firmware
          -- relies on autostarting from the cart's reset vector after pressing
          -- the freeze button (freeze stays asserted -> Ultimax stays selected).
          -- kernal_enabled is reset to 0 above, so kernal||freeze == freeze.
          if mf_freeze_enabled = '1' then
            exrom_o <= '1';
            game_o  <= '0';   -- Ultimax
          else
            exrom_o <= '1';
            game_o  <= '1';   -- NoCart (matches VICE change_config "else" branch)
          end if;
        end if;
      end if;
    end if;
  end process cartridge_proc;

end architecture synthesis;

