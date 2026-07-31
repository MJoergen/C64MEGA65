----------------------------------------------------------------------------------
-- MiSTer2MEGA65 Framework
--
-- C64 for MEGA65
-- Configuration data for the Shell
--
-- MiSTer2MEGA65 done by sy2002 and MJoergen in 2024 and licensed under GPL v3
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity config is
port (
   clk_i       : in std_logic;

   -- bits 27 .. 12:    select configuration data block; called "Selector" hereafter
   -- bits 11 downto 0: address the up to 4k the configuration data
   address_i   : in std_logic_vector(27 downto 0);

   -- config data
   data_o      : out std_logic_vector(15 downto 0)
);
end entity config;

architecture beh of config is

--------------------------------------------------------------------------------------------------------------------
-- String and character constants (specific for the Anikki-16x16 font)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant CHR_LINE_1  : character := character'val(196);
constant CHR_LINE_5  : string := CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1 & CHR_LINE_1;
constant CHR_LINE_10 : string := CHR_LINE_5 & CHR_LINE_5;
constant CHR_LINE_50 : string := CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10 & CHR_LINE_10;

--------------------------------------------------------------------------------------------------------------------
-- Welcome and Help Screens (Selectors 0x1000 .. 0x1FFF)
--
-- Learn how to use the Welcome and Help system:
-- https://github.com/sy2002/MiSTer2MEGA65/wiki/Welcome-and-Help-Screens
--------------------------------------------------------------------------------------------------------------------

-- define the amount of WHS array elements: between 1 and 16
constant WHS_RECORDS   : natural := 2;

-- define the maximum amount of pages per WHS array element: between 1 and 256
-- (this is necessary because Vivado does not support unconstrained arrays in a record)
constant WHS_MAX_PAGES : natural := 3;

 -- !!! DO NOT TOUCH !!!
constant SEL_WHS           : std_logic_vector(15 downto 0) := x"1000";
type WHS_INDEX_TYPE is array (0 to WHS_MAX_PAGES - 1) of natural;
type WHS_RECORD_TYPE is record
   page_count  : natural;
   page_start  : WHS_INDEX_TYPE;
   page_length : WHS_INDEX_TYPE;
end record;
type WHS_RECORD_ARRAY_TYPE is array (0 to WHS_RECORDS - 1) of WHS_RECORD_TYPE;

-- START YOUR CONFIGURATION BELOW THIS LINE

-- The core's version string. Single source of truth: this constant is used
-- by SCR_WELCOME, HELP_1, HELP_2 and HELP_3 (the welcome and help screens
-- just below), by CORENAME (the serial-terminal banner further down) and
-- by CFG_FILE (the on-SD-card config filename further down). Update this
-- one line when releasing a new version; make_release.py parses it and
-- uses it as the official version string for that release.
constant CORE_VERSION : string := "WIP-V6-A20";

-- Define all your screens as string constants. They will be synthesized as ROMs.
-- You can name these string constants as you want to, as long as you make them part of the WHS array (see below).
--
-- WHS array position 0 is defined as the "Welcome Screen" as controled by WELCOME_ACTIVE and WELCOME_AT_RESET.
-- If you are not using a Welcome Screen but only Help menu items, then you need to leave WHS array pos. 0 empty.
--
-- WHS array position 1 and onwards is for all the Option Menu items tagged as "Help": The first one in the
-- Options menu is WHS array pos. 1, the second one in the menu is WHS array pos. 2 and so on.
--
-- Maximum 16 WHS array positions: The selector's bits 11 downto 8 select the WHS array position; 0=Welcome Screen
-- That means a maximum of 15 menu items in the Options menu can be tagged as "Help"
-- The selector's bits 7 downto 0 are selecting the page within the WHS array, so maximum 256 pages per Welcome Screen or Help menu item
--
-- Within a selector's address range, address 0 is the beginning of the string itself, while address 0xFFF of the 4k
-- window contains the amount of pages, so each zero-terminated string can be up to 4095 bytes = 4094 characters long.

constant SCR_WELCOME : string :=

   "\n Commodore 64 for MEGA65 Version " & CORE_VERSION & "\n\n" &

   " MiSTer port 2026 by MJoergen & sy2002\n" &
   " Powered by MiSTer2MEGA65\n\n\n" &

   " While the C64 is running: Press HELP\n" &
   " to mount drives & to configure the core.\n\n" &

   " Both SD card slots work: The card in the\n" &
   " back has higher precedence than the\n" &
   " card at the bottom of the MEGA65.\n\n" &

   " While you are in the file browser:\n" &
   "   F1: Switch to internal SD card\n" &
   "   F3: Switch to external SD card\n" &

   "\n\n Press Space to continue.";

constant HELP_1 : string :=

   "\n Commodore 64 for MEGA65 Version " & CORE_VERSION & "\n\n" &

   " MiSTer port 2026 by MJoergen & sy2002\n" &
   " Powered by MiSTer2MEGA65\n\n" &

   " Quickstart:\n\n" &

   " * Create a /c64 folder on your SD card &\n" &
   "   place your D64/D81, CRT and PRG files\n" &
   "   there\n" &
   " * You can work with long file names and\n" &
   "   with arbitrary sub-folders\n" &
   " * Both SD card slots are supported. Back\n" &
   "   slot takes precedence over bottom slot\n" &
   " * Copy the C64MEGA65 config file to your\n" &
   "   /c64 folder so that your menu settings\n" &
   "   are being saved\n" &
   " * If you use any analog display device\n" &
   "   via the VGA port, disable HDMI:\n" &
   "   Flicker-free to avoid glitches\n" &
   " * If you use HDMI, then absolutely make\n" &
   "   sure that you enable HDMI: Flicker-free\n" &
   "   and that you run the core at 50 Hz\n" &
   " * To use hardware cartridges, you need to\n" &
   "   have a MEGA65 core #0 from at least mid\n" &
   "   2023; so you might need to upgrade\n\n" &

   " Cursor right to learn more.       (1 of 3)\n" &
   " Press Space to close the help screen.";

constant HELP_2 : string :=

   "\n Commodore 64 for MEGA65 Version " & CORE_VERSION & "\n\n" &

   " When browsing the menu:\n\n" &

   " Help:               Open/close menu\n" &
   " Run/Stop:           Leave sub-menu\n" &
   " Settings are saved when closing the menu\n\n" &

   " When browsing for D64/D81, CRT and PRG:\n\n" &

   " Cursor up/down:     File up/down\n" &
   " Cursor left/right:  Page up/down\n" &
   " Run/Stop:           Cancel browsing\n" &
   " F1:                 Bottom SD card\n" &
   " F3:                 Back SD card\n" &
   " Enter:              Mount drive\n" &
   "                     Load CRT or PRG\n" &
   " Space:              Unmount drive\n\n" &

   " System reset:\n\n" &

   " Press the reset button shortly to just\n" &
   " reset the C64 core and press the button\n" &
   " longer than 1.5s to reset the MEGA65.\n" &
   " A short reset also restarts cartridges.\n\n" &

   " Crsr left: Prev  Crsr right: Next (2 of 3)\n" &
   " Press Space to close the help screen.";

constant HELP_3 : string :=

   "\n Commodore 64 for MEGA65 Version " & CORE_VERSION & "\n\n" &

   " SID:\n\n" &

   " * For older productions choose 6581 and\n" &
   "   for newer productions choose 8580.\n" &
   " * Stick to Mono SID unless you know what\n" &
   "   you are doing.\n" &
   " * ""Pseudo-stereo"" is an exception to\n" &
   "   this. Enable it by choosing ""Same as\n" &
   "   left SID port"" in the configuration for\n" &
   "   the right SID port and by choosing\n" &
   "   different SID models for the left and\n" &
   "   right speaker.\n\n" &

   " IEC:\n\n" &

   " Never run an external device that has the\n" &
   " drive id #8. Always use #9 or higher.\n\n" &

   " Writing to disk images:\n\n" &

   " Wait until the drive led is done turning\n" &
   " from green to yellow back and forth and\n" &
   " is off again before unmount, reset or OFF.\n\n" &

   " Cursor left to go back.           (3 of 3)\n" &
   " Press Space to close the help screen.";

-- Concatenate all your Welcome and Help screens into one large string, so that during synthesis one large string ROM can be build.
constant WHS_DATA : string := SCR_WELCOME & HELP_1 & HELP_2 & HELP_3;

-- The WHS array needs the start address of each page. As a best practice: Just define some constants, that you can name for example
-- just like you named the string constants and then add _START. Use the 'length attribute of VHDL to add up all previous strings
-- so that the Synthesis tool can calculate the start addresses: Your first string starts at zero, your next one at the address which
-- is equal to the length of the first one, your next one at the address which is equal to the sum of the previous ones, and so on.
constant SCR_WELCOME_START : natural := 0;
constant HELP_1_START      : natural := SCR_WELCOME'length;
constant HELP_2_START      : natural := HELP_1_START + HELP_1'length;
constant HELP_3_START      : natural := HELP_2_START + HELP_2'length;

-- Fill the WHS array with page start addresses and the length of each page.
-- Make sure that array element 0 is always your Welcome page. If you don't use a welcome page, fill everything with zeros.
constant WHS : WHS_RECORD_ARRAY_TYPE := (
   --- Welcome Screen
   (page_count    => 1,
    page_start    => (SCR_WELCOME_START,  0, 0),
    page_length   => (SCR_WELCOME'length, 0, 0)),

   --- Help pages
   (page_count    => 3,
    page_start    => (HELP_1_START,  HELP_2_START,  HELP_3_START),
    page_length   => (HELP_1'length, HELP_2'length, HELP_3'length))
);

--------------------------------------------------------------------------------------------------------------------
-- Set start folder for file browser and specify config file for menu persistence (Selectors 0x0100 and 0x0101)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_DIR_START     : std_logic_vector(15 downto 0) := x"0100";
constant SEL_CFG_FILE      : std_logic_vector(15 downto 0) := x"0101";

-- START YOUR CONFIGURATION BELOW THIS LINE

constant DIR_START         : string := "/c64";
constant CFG_FILE          : string := "/c64/c64mega65-" & CORE_VERSION & ".cfg";

--------------------------------------------------------------------------------------------------------------------
-- General configuration settings: Reset, Pause, OSD behavior, Ascal, etc. (Selector 0x0110)
--
-- Learn how to work with these settings:
-- https://github.com/sy2002/MiSTer2MEGA65/wiki/config.vhd-Switches-and-Settings
--------------------------------------------------------------------------------------------------------------------

constant SEL_GENERAL       : std_logic_vector(15 downto 0) := x"0110";  -- !!! DO NOT TOUCH !!!

-- START YOUR CONFIGURATION BELOW THIS LINE

-- at a minimum, keep the reset line active for this amount of "QNICE loops" (see gencfg.asm).
-- "0" means: deactivate this feature
constant RESET_COUNTER     : natural := 100;

-- put the core in PAUSE state if any OSD opens
constant OPTM_PAUSE        : boolean := false;

-- show the welcome screen in general
constant WELCOME_ACTIVE    : boolean := false;

-- shall the welcome screen also be shown after the core is reset?
-- (only relevant if WELCOME_ACTIVE is true)
constant WELCOME_AT_RESET  : boolean := false;

-- keyboard and joystick connection during reset and OSD
constant KEYBOARD_AT_RESET : boolean := false;
constant JOY_1_AT_RESET    : boolean := false;
constant JOY_2_AT_RESET    : boolean := false;

constant KEYBOARD_AT_OSD   : boolean := false;
constant JOY_1_AT_OSD      : boolean := false;
constant JOY_2_AT_OSD      : boolean := false;

-- Avalon Scaler settings (see ascal.vhd, used for HDMI output only)
-- 0=set ascal mode (via QNICE's ascal_mode_o) to the value of the config.vhd constant ASCAL_MODE
-- 1=do nothing, leave ascal mode alone, custom QNICE assembly code can still change it via M2M$ASCAL_MODE
--               and QNICE's CSR will be set to not automatically sync ascal_mode_i
-- 2=keep ascal mode in sync with the QNICE input register ascal_mode_i:
--   use this if you want to control the ascal mode for example via the Options menu
--   where you would wire the output of certain options menu bits with ascal_mode_i
constant ASCAL_USAGE       : natural := 1;   -- V6: AUSE_CUSTOM. ASCAL_INIT clears M2M$CSR bit 11; m2m-rom (HDMI Filter dispatcher) writes M2M$ASCAL_MODE directly.
constant ASCAL_MODE        : natural := 0;   -- ignored when ASCAL_USAGE=1; m2m-rom sets the mode per HDMI Filter selection (No Filter/Sharp Bilinear/Bicubic -> native NEAREST/SBILINEAR/BICUBIC, the other 5 -> POLYPHASE)

-- Save on-screen-display settings if the file specified by CFG_FILE exists and if it has
-- the length of OPTM_SIZE bytes. If the first byte of the file has the value 0xFF then it
-- is considered as "default", i.e. the menu items specified by OPTM_G_STDSEL are selected.
-- If the file does not exists, then settings are not saved and OPTM_G_STDSEL always denotes the standard settings.
constant SAVE_SETTINGS     : boolean := true;

-- Delay in ms between the last write request to a virtual drive from the core and the start of the
-- cache flushing (i.e. writing to the SD card). Since every new write from the core invalidates the cache,
-- and therefore leads to a completely new writing of the cache (flushing), this constant prevents thrashing.
-- The default is 2 seconds (2000 ms). Should be reasonable for many systems, but if you have a very fast
-- or very slow system, you might need to change this constant.
--
-- Constraint (@TODO): Currently we have only one constant for all virtual drives, i.e. the delay is
-- the same for all virtual drives. This might be absolutely OK; future will tell. If we need to have
-- more flexibility: vdrives.vhd already supports one delay per virtual drive. All what would need
-- to be done in such a case is: Enhance config.vhd to have more constants plus enhance the initialization
-- routine VD_INIT in vdrives.asm (tagged by @TODO) to store different values in the appropriate registers.
constant VD_ANTI_THRASHING_DELAY : natural := 2000;

-- Amount of bytes saved in one iteration of the background saving (buffer flushing) process
-- Constraint (@TODO): Similar constraint as in VD_ANTI_THRASHING_DELAY: Only one value for all drives.
-- shell.asm and shell_vars.asm already supports distinct values per drive; config.vhd and VD_INIT would
-- needs to be updated in case we would need this feature in future
constant VD_ITERATION_SIZE       : natural := 100;

--------------------------------------------------------------------------------------------------------------------
-- Name and version of the core  (Selector 0x0200)
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!!
constant SEL_CORENAME      : std_logic_vector(15 downto 0) := x"0200";

-- START YOUR CONFIGURATION BELOW THIS LINE

-- Currently this is only used in the debug console. Use the welcome screen and the
-- help system to display the name and version of your core to the end user
constant CORENAME          : string := "Commodore 64 for MEGA65 Version " & CORE_VERSION;

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu  (Selectors 0x0300 .. 0x0312): DO NOT TOUCH
--------------------------------------------------------------------------------------------------------------------

-- !!! DO NOT TOUCH !!! Selectors for accessing the menu configuration data
constant SEL_OPTM_ITEMS       : std_logic_vector(15 downto 0) := x"0300";
constant SEL_OPTM_GROUPS      : std_logic_vector(15 downto 0) := x"0301";
constant SEL_OPTM_STDSEL      : std_logic_vector(15 downto 0) := x"0302";
constant SEL_OPTM_LINES       : std_logic_vector(15 downto 0) := x"0303";
constant SEL_OPTM_START       : std_logic_vector(15 downto 0) := x"0304";
constant SEL_OPTM_ICOUNT      : std_logic_vector(15 downto 0) := x"0305";
constant SEL_OPTM_MOUNT_DRV   : std_logic_vector(15 downto 0) := x"0306";
constant SEL_OPTM_SINGLESEL   : std_logic_vector(15 downto 0) := x"0307";
constant SEL_OPTM_MOUNT_STR   : std_logic_vector(15 downto 0) := x"0308";
constant SEL_OPTM_DIMENSIONS  : std_logic_vector(15 downto 0) := x"0309";
constant SEL_OPTM_SAVING_STR  : std_logic_vector(15 downto 0) := x"030A";
constant SEL_OPTM_HELP        : std_logic_vector(15 downto 0) := x"0310";
constant SEL_OPTM_CRTROM      : std_logic_vector(15 downto 0) := x"0311";
constant SEL_OPTM_CRTROM_STR  : std_logic_vector(15 downto 0) := x"0312";
constant SEL_OPTM_DEPS        : std_logic_vector(15 downto 0) := x"0313";

-- !!! DO NOT TOUCH !!! Configuration constants for OPTM_GROUPS (shell.asm and menu.asm expect them to be like this)
constant OPTM_G_TEXT       : integer := 16#00000#;         -- text that cannot be selected
constant OPTM_G_CLOSE      : integer := 16#000FF#;         -- menu items that closes menu
constant OPTM_G_STDSEL     : integer := 16#00100#;         -- item within a group that is selected by default
constant OPTM_G_LINE       : integer := 16#00200#;         -- draw a line at this position
constant OPTM_G_START      : integer := 16#00400#;         -- selector / cursor position after startup (only use once!)
                                                           -- 16#00800# is used in OPTM_G_MOUNT_DRV (OPTM_G_SINGLESEL)
constant OPTM_G_HEADLINE   : integer := 16#01000#;         -- like OPTM_G_TEXT but will be shown in a brigher color
                                                           -- 16#02000# is used in OPTM_G_HELP (plus OPTM_G_SINGLESEL)
                                                           -- 16#04000# is used in OPTM_G_SUBMENU
constant OPTM_G_SINGLESEL  : integer := 16#08000#;         -- single select item
constant OPTM_G_MOUNT_DRV  : integer := 16#08800#;         -- line item means: mount drive; first occurance = drive 0, second = drive 1, ...
constant OPTM_G_HELP       : integer := 16#0A000#;         -- line item means: help screen; first occurance = WHS(1), second = WHS(2), ...
constant OPTM_G_SUBMENU    : integer := 16#0C000#;         -- starts/ends a section that is treated as submenu:
                                                           -- the line that starts a submenu doubles as its label in the
                                                           -- parent menu; submenus nest to arbitrary depth (M2M V2.1.0+):
                                                           -- put a complete OPTM_G_SUBMENU .. OPTM_G_SUBMENU+OPTM_G_CLOSE
                                                           -- block inside another one
constant OPTM_G_LOAD_ROM   : integer := 16#18000#;         -- line item means: load ROM; first occurance = rom 0, second = rom 1, ...
constant OPTM_G_DEPENDENT  : integer := 16#20000000#;      -- dependent line (smart dependencies, see OPTM_DEP below): visible only
                                                           -- while one of the mother-group items in a 4-bit item mask is selected (bit 29)

constant OPTM_GTC          : natural := 30;                -- Amount of significant bits in OPTM_G_* constants (max 30: 2**31 overflows
                                                           -- the integer range expression below); was 17 before the smart-dependencies feature

-- @TODO/REMINDER: If we added in future more configuration constants that are not meant to be saved in the
-- configuration file, such as OPTM_G_MOUNT_DRV and OPTM_G_LOAD_ROM, then we need to make sure that we
-- also extend _ROSMS_4A and _ROSMC_NEXTBIT in options.asm accordingly.
-- Also: Right now OPTM_G_SUBMENU cannot have a "selected" state (and therefore cannot be saved in the config file)
-- and therefore _ROSMS_4A and _ROSMC_NEXTBIT are not yet handling the situation. If we decided to change that in future,
-- we would need to define the right semantics everywhere.

--------------------------------------------------------------------------------------------------------------------
-- "Help" menu / Options menu: START YOUR CONFIGURATION BELOW THIS LINE
--
-- Learn how to build your own OSM:
-- https://github.com/sy2002/MiSTer2MEGA65/wiki/On%E2%80%90Screen%E2%80%90Menu-%28OSM%29
--------------------------------------------------------------------------------------------------------------------

-- Strings with which %s will be replaced in case the menu item is of type OPTM_G_MOUNT_DRV
constant OPTM_S_MOUNT      : string := "<Mount Drive>";     -- no disk image mounted, yet
constant OPTM_S_CRTROM     : string := "<Load>";            -- no ROM/CRT loaded, yet
constant OPTM_S_SAVING     : string := "<Saving>";          -- the internal write cache is dirty and not yet written back to the SD card

-- Size of menu and menu items
-- CAUTION: 1. End each line (also the last one) with a \n and make sure empty lines / separator lines are only consisting of a "\n"
--             Do use a lower case \n. If you forget one of them or if you use upper case, you will run into undefined behavior.
--          2. Start each line that contains an actual menu item (multi- or single-select) with a Space character,
--             otherwise you will experience visual glitches.
constant OPTM_SIZE         : natural := 190; -- amount of items including empty lines:
                                             -- needs to be equal to the number of lines in OPTM_ITEMS and amount of items in OPTM_GROUPS
                                             -- IMPORTANT: If SAVE_SETTINGS is true and OPTM_SIZE changes: Make sure to re-generate and
                                             -- and re-distribute the config file. You can make a new one using M2M/tools/make_config.sh

-- Net size of the Options menu on the screen in characters (excluding the frame, which is hardcoded to two characters)
-- Without submenus: Use OPTM_SIZE as height, otherwise use the height of the largest menu view (usually the main menu):
-- count one line per item that is visible at that level, including one line per submenu label, excluding the contents
-- of submenus. Cross-check with "python3 M2M/rom/tests/menu_test.py verify".
constant OPTM_DX           : natural := 25;
constant OPTM_DY           : natural := 31;

-- !!! DO NOT TOUCH THE TYPE DEFINITION IN THE NEXT LINE AND CONTINUE YOUR CONFIGURATION ONE LINE LATER
type OPTM_GTYPE is array (0 to OPTM_SIZE - 1) of integer range 0 to 2**OPTM_GTC - 1;

-- CONTINUE YOUR CONFIGURATION FROM HERE ON
constant OPTM_ITEMS        : string :=

   " C64 for MEGA65\n"          &
   "\n"                         &
   " 8:%s\n"                    &  -- %s will be replaced by OPTM_S_MOUNT when not mounted and by the filename when mounted
   " 8:Internal 1581        \n" &  -- fixed-width label: HANDLE_CORE_IO shows live physical-drive status in the trailing field
   " 9:%s\n"                    &  -- second virtual drive (issue #93); visible only in the "Disk Image" modes
   " 9:Internal 1581        \n" &  -- fixed-width label, see "8:Internal 1581" above
   " PRG:%s\n"                  &

   " Drive Settings\n"          &  -- Drive Settings submenu (issue #93)
   " Drive 8\n"                 &
   "\n"                         &
   " Disk Image: If mounted\n"  &  -- drive answers on the IEC bus only while a disk image is mounted
   " Disk Image: Always\n"      &  -- drive answers on the IEC bus even without a mounted image ("no disk in drive")
   " Internal 1581\n"           &  -- MEGA65's built-in physical drive backs this IEC device (only on one drive at a time)
   " Off\n"                     &  -- IEC device fully off, e.g. to use this device number on the hardware IEC port
   " Unmount on reset\n"        &  -- on = unmount the disk image on a soft core reset (pre-V6 behavior)
   "\n"                         &
   " Drive 9\n"                 &
   "\n"                         &
   " Disk Image: If mounted\n"  &
   " Disk Image: Always\n"      &
   " Internal 1581\n"           &
   " Off\n"                     &
   " Unmount on reset\n"        &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   "\n"                         &
   " Expansion Port\n"          &
   "\n"                         &
   " Use hardware slot\n"       &
   " Simulate cartridge:\n"     &
   " CRT:%s\n"                  &  -- %s will be replaced by OPTM_S_CRTROM when no cartridge is loaded, otherwise by the filename of the cartridge
   " Simulate 1750 REU 512KB\n" &
   "\n"                         &
   " C64 Configuration\n"       &
   "\n"                         &

   " Model: %s\n"               &  -- Model submenu
   " Model\n"                   &
   "\n"                         &
   " PAL\n"                     &
   " NTSC\n"                    &  -- not yet wired in mega65.vhd, see #181
   "\n"                         &
   " Turbo mode\n"              &
   "\n"                         &
   " Off\n"                     &  -- the whole turbo block is not yet wired in mega65.vhd
   " C128\n"                    &
   " Smart\n"                   &
   "\n"                         &
   " Turbo speed\n"             &
   " 2x\n"                      &
   " 3x\n"                      &
   " 4x\n"                      &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " Flip joystick ports\n"     &

   " HDMI: %s\n"                &  -- HDMI submenu
   " HDMI Display Mode\n"       &
   "\n"                         &
   " 16:9 720p 50 Hz\n"         &  -- PAL modes; with the dependencies feature (#229) only the matching
   " 16:9 720p 59.94 Hz\n"      &  -- machine-mode variants will be shown, hence no (PAL)/(NTSC) suffixes
   " 4:3  576p 50 Hz\n"         &  -- the NTSC display modes (59.94 Hz) are not yet wired in mega65.vhd,
   " 4:3  480p 59.94 Hz\n"      &  -- see #181/#105
   " 5:4  576p 50 Hz\n"         &
   " 5:4  480p 59.94 Hz\n"      &
   "\n"                         &
   " HDMI: Flicker-free\n"      &
   " HDMI: Flicker-free\n"      &  -- NTSC twin of the line above; not yet wired, see #181 and path-to-OSM-dependencies.md
   " HDMI: DVI (no sound)\n"    &

   " HDMI: %s\n"                &  -- HDMI Filter submenu, nested inside the HDMI submenu
   " HDMI Filter\n"             &
   "\n"                         &
   " No Filter\n"               &
   " Sharp Bilinear\n"          &
   " Bicubic\n"                 &
   " Smooth\n"                  &
   " Lanczos\n"                 &
   " Scanlines\n"               &  -- default: bit-identical to V5's CRT emulation look
   " CRT (S-Video)\n"           &
   " CRT (Composite)\n"         &
   "\n"                         &
   " Back\n"                    &  -- returns to the HDMI submenu

   " HDMI: Zoom-in\n"           &
   " HDMI: Raw 50.1 Hz\n"       &  -- not yet wired in mega65.vhd
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " VGA: %s\n"                 &  -- VGA submenu
   " VGA Display Mode\n"        &
   "\n"                         &
   " Standard\n"                &
   "\n"                         &
   " Retro 15 kHz mode\n"       &
   "\n"                         &
   " 15 kHz with HS/VS\n"       &
   " 15 kHz with CSYNC\n"       &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " SID: %s\n"                 &  -- SID submenu
   " SID Settings\n"            &
   "\n"                         &
   " Mono SID\n"                &
   "\n"                         &
   " 6581\n"                    &
   " 8580\n"                    &
   "\n"                         &
   " Stereo SID\n"              &
   "\n"                         &
   " L: 6581 R: 6581\n"         &
   " L: 6581 R: 8580\n"         &
   " L: 8580 R: 6581\n"         &
   " L: 8580 R: 8580\n"         &
   "\n"                         &
   " Right SID Port\n"          &
   "\n"                         &
   " D420\n"                    &
   " D500\n"                    &
   " DE00\n"                    &
   " DF00\n"                    &
   " Same as left SID port\n"   &
   "\n"                         &
   " Audio improvements\n"      &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " IEC: Use hardware port\n"  &

   " Kernal: %s\n"              &  -- Kernal submenu
   " Kernal Selection\n"        &
   "\n"                         &
   " Standard\n"                &
   " Games System\n"            &
   " Japanese\n"                &
   " JiffyDOS\n"                &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " Volume: %s\n"              &  -- Volume submenu
   " Volume Control\n"          &
   "\n"                         &
   " 100%\n"                    &  -- master volume, 5% steps, perceptual: decoded in mega65.vhd, attenuated in main.vhd (C_VOL_LUT)
   " 95%\n"                     &
   " 90%\n"                     &
   " 85%\n"                     &
   " 80%\n"                     &
   " 75%\n"                     &
   " 70%\n"                     &
   " 65%\n"                     &
   " 60%\n"                     &
   " 55%\n"                     &
   " 50%\n"                     &
   " 45%\n"                     &
   " 40%\n"                     &
   " 35%\n"                     &
   " 30%\n"                     &
   " 25%\n"                     &
   " 20%\n"                     &
   " 15%\n"                     &
   " 10%\n"                     &
   " 5%\n"                      &
   " 0%\n"                      &
   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   " Advanced Settings\n"       &  -- Advanced Settings submenu
   " Advanced Settings\n"       &
   "\n"                         &
   " GEOS Real-Time-Clock\n"    &  -- emulated PCF8583 on the tape port, see #133, #164 and #187

   " OSM: %s\n"                 &  -- OSM Scaling submenu, nested inside Advanced Settings
   " OSM Scaling\n"             &
   "\n"                         &
   " 100%\n"                    &
   " 89%\n"                     &
   " 80%\n"                     &
   " 73%\n"                     &
   " 67%\n"                     &
   " 62%\n"                     &
   " 57%\n"                     &
   " 53%\n"                     &
   " 50%\n"                     &
   "\n"                         &
   " Back\n"                    &  -- returns to Advanced Settings

   " CIA: Use 8521 (C64C)\n"    &

   " VIC-II: %s\n"              &  -- VIC-II submenu, nested inside Advanced Settings
   " VIC-II model\n"            &
   "\n"                         &
   " 656x/NMOS\n"               &  -- not yet wired in mega65.vhd
   " 856x/HMOS\n"               &
   " 856x/old HMOS\n"           &
   "\n"                         &
   " Back\n"                    &  -- returns to Advanced Settings

   "\n"                         &
   " Back\n"                    &  -- returns to the main menu

   "\n"                         &
   " About & Help\n"            &
   "\n"                         &
   " Close Menu\n";

constant OPTM_G_MOUNT_8       : integer := 1;
constant OPTM_G_MOUNT_9       : integer := 2;   -- each drive needs a unique group ID
constant OPTM_G_LOAD_PRG      : integer := 3;
constant OPTM_G_EXP_PORT      : integer := 4;
constant OPTM_G_MOUNT_CRT     : integer := 5;
constant OPTM_G_FLIP_JOYS     : integer := 6;
constant OPTM_G_SID_SETUP     : integer := 7;
constant OPTM_G_SID_PORT      : integer := 8;
constant OPTM_G_IMPROVE_AUDIO : integer := 9;
constant OPTM_G_CIA_8521      : integer := 10;
constant OPTM_G_IEC           : integer := 11;
constant OPTM_G_KERNAL_MODES  : integer := 12;
constant OPTM_G_HDMI_MODES_PAL : integer := 13; -- PAL HDMI display modes (the NTSC modes are a group of their own, see below)
constant OPTM_G_HDMI_FF       : integer := 14;
constant OPTM_G_HDMI_DVI      : integer := 15;
constant OPTM_G_HDMI_FILTER   : integer := 16;
constant OPTM_G_HDMI_ZOOM     : integer := 17;
constant OPTM_G_VGA_MODES     : integer := 18;
constant OPTM_G_OSM_MODE      : integer := 19;
constant OPTM_G_ABOUT_HELP    : integer := 20;
constant OPTM_G_REU           : integer := 21;
constant OPTM_G_MACHINE_MODE  : integer := 22;  -- PAL/NTSC; the C64 core itself is not yet wired, see #181
constant OPTM_G_TURBO_MODE    : integer := 23;  -- not yet wired
constant OPTM_G_TURBO_SPEED   : integer := 24;  -- not yet wired
constant OPTM_G_HDMI_MODES_NTSC : integer := 25; -- NTSC HDMI display modes; not yet wired, see #181/#105
constant OPTM_G_HDMI_FF_NTSC  : integer := 26;  -- NTSC twin of OPTM_G_HDMI_FF; not yet wired
constant OPTM_G_HDMI_RAW50    : integer := 27;  -- not yet wired
constant OPTM_G_VOLUME        : integer := 28;  -- not yet wired, see #85
constant OPTM_G_RTC_GEOS      : integer := 29;  -- GEOS Real-Time-Clock; off by default, see #133, #164 and #187
constant OPTM_G_VICII_MODEL   : integer := 30;  -- not yet wired
constant OPTM_G_DRV8_MODE     : integer := 31;  -- drive 8 mode: Disk Image (If mounted/Always), Internal 1581, Off (issue #93)
constant OPTM_G_DRV8_UNMOUNT  : integer := 32;  -- drive 8: unmount the disk image on a soft core reset (on = pre-V6 behavior)
constant OPTM_G_DRV9_MODE     : integer := 33;  -- drive 9 mode; "Internal 1581" is the factory default here (issue #93)
constant OPTM_G_DRV9_UNMOUNT  : integer := 34;  -- drive 9: unmount the disk image on a soft core reset

-- !!! DO NOT TOUCH THE FUNCTION DEFINITIONS IN THE NEXT NINE LINES
-- Dependency format 2 (magic 0x2DEF): bits 28..25 are a 4-bit mask of mother-group items, so a line
-- can be visible for MORE than one selected item of its mother group: OPTM_DEP(m, i) = visible while
-- item i is selected; OPTM_DEP2(m, i, j) = visible while item i OR item j is selected. Items 0..3 only.
function OPTM_DEP(mother : natural; item : natural) return natural is
begin
   return OPTM_G_DEPENDENT + ((2 ** item) * 16#02000000#) + (mother * 16#00020000#);
end function OPTM_DEP;
function OPTM_DEP2(mother : natural; item_a : natural; item_b : natural) return natural is
begin
   return OPTM_G_DEPENDENT + ((2 ** item_a + 2 ** item_b) * 16#02000000#) + (mother * 16#00020000#);
end function OPTM_DEP2;

-- CONTINUE YOUR CONFIGURATION FROM HERE ON
constant OPTM_GROUPS       : OPTM_GTYPE := ( OPTM_G_HEADLINE,                        -- C64 for MEGA65
                                             OPTM_G_LINE,
                                             OPTM_G_MOUNT_8       + OPTM_G_MOUNT_DRV   + OPTM_G_START
                                                                  + OPTM_DEP2(OPTM_G_DRV8_MODE, 0, 1), -- 8:%s (only in the Disk Image modes)
                                             OPTM_G_TEXT          + OPTM_DEP(OPTM_G_DRV8_MODE, 2),     -- 8:Internal 1581 (live status line)
                                             OPTM_G_MOUNT_9       + OPTM_G_MOUNT_DRV
                                                                  + OPTM_DEP2(OPTM_G_DRV9_MODE, 0, 1), -- 9:%s (only in the Disk Image modes)
                                             OPTM_G_TEXT          + OPTM_DEP(OPTM_G_DRV9_MODE, 2),     -- 9:Internal 1581 (live status line)
                                             OPTM_G_LOAD_PRG      + OPTM_G_LOAD_ROM,

                                             OPTM_G_SUBMENU,                          -- open "Drive Settings"
                                             OPTM_G_HEADLINE,                         -- Drive 8
                                             OPTM_G_LINE,
                                             OPTM_G_DRV8_MODE     + OPTM_G_STDSEL,    -- Disk Image: If mounted (default for drive 8)
                                             OPTM_G_DRV8_MODE,                        -- Disk Image: Always
                                             OPTM_G_DRV8_MODE,                        -- Internal 1581
                                             OPTM_G_DRV8_MODE,                        -- Off
                                             OPTM_G_DRV8_UNMOUNT  + OPTM_G_SINGLESEL + OPTM_G_STDSEL, -- Unmount on reset (default: on)
                                             OPTM_G_LINE,
                                             OPTM_G_HEADLINE,                         -- Drive 9
                                             OPTM_G_LINE,
                                             OPTM_G_DRV9_MODE,                        -- Disk Image: If mounted
                                             OPTM_G_DRV9_MODE,                        -- Disk Image: Always
                                             OPTM_G_DRV9_MODE     + OPTM_G_STDSEL,    -- Internal 1581 (default for drive 9)
                                             OPTM_G_DRV9_MODE,                        -- Off
                                             OPTM_G_DRV9_UNMOUNT  + OPTM_G_SINGLESEL + OPTM_G_STDSEL, -- Unmount on reset (default: on)
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Drive Settings"

                                             OPTM_G_LINE,
                                             OPTM_G_HEADLINE,                         -- Expansion Port
                                             OPTM_G_LINE,
                                             OPTM_G_EXP_PORT      + OPTM_G_STDSEL,    -- Use hardware slot
                                             OPTM_G_EXP_PORT,                         -- Simulate cartridge:
                                             OPTM_G_MOUNT_CRT     + OPTM_G_LOAD_ROM,  -- CRT:%s
                                             OPTM_G_REU           + OPTM_G_SINGLESEL, -- Simulate 1750 REU 512 kB
                                             OPTM_G_LINE,
                                             OPTM_G_HEADLINE,                         -- C64 Configuration
                                             OPTM_G_LINE,

                                             OPTM_G_SUBMENU,                          -- open "Model: %s"
                                             OPTM_G_HEADLINE,                         -- Model
                                             OPTM_G_LINE,
                                             OPTM_G_MACHINE_MODE  + OPTM_G_STDSEL,    -- PAL
                                             OPTM_G_MACHINE_MODE,                     -- NTSC
                                             OPTM_G_LINE,
                                             OPTM_G_HEADLINE,                         -- Turbo mode
                                             OPTM_G_LINE,
                                             OPTM_G_TURBO_MODE    + OPTM_G_STDSEL,    -- Off
                                             OPTM_G_TURBO_MODE,                       -- C128
                                             OPTM_G_TURBO_MODE,                       -- Smart
                                             OPTM_G_LINE,
                                             OPTM_G_HEADLINE,                         -- Turbo speed
                                             OPTM_G_TURBO_SPEED   + OPTM_G_STDSEL,    -- 2x
                                             OPTM_G_TURBO_SPEED,                      -- 3x
                                             OPTM_G_TURBO_SPEED,                      -- 4x
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Model: %s"

                                             OPTM_G_FLIP_JOYS     + OPTM_G_SINGLESEL,

                                             OPTM_G_SUBMENU,                          -- open "HDMI: %s" (settings)
                                             OPTM_G_HEADLINE,                         -- HDMI Display Mode
                                             OPTM_G_LINE,
                                             OPTM_G_HDMI_MODES_PAL  + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0), -- 16:9 720p 50 Hz
                                             OPTM_G_HDMI_MODES_NTSC + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1), -- 16:9 720p 59.94 Hz
                                             OPTM_G_HDMI_MODES_PAL                  + OPTM_DEP(OPTM_G_MACHINE_MODE, 0), -- 4:3  576p 50 Hz
                                             OPTM_G_HDMI_MODES_NTSC                 + OPTM_DEP(OPTM_G_MACHINE_MODE, 1), -- 4:3  480p 59.94 Hz
                                             OPTM_G_HDMI_MODES_PAL                  + OPTM_DEP(OPTM_G_MACHINE_MODE, 0), -- 5:4  576p 50 Hz
                                             OPTM_G_HDMI_MODES_NTSC                 + OPTM_DEP(OPTM_G_MACHINE_MODE, 1), -- 5:4  480p 59.94 Hz
                                             OPTM_G_LINE,
                                             OPTM_G_HDMI_FF       + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0), -- Flicker-free (PAL)
                                             OPTM_G_HDMI_FF_NTSC  + OPTM_G_SINGLESEL + OPTM_G_STDSEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 1), -- Flicker-free (NTSC)
                                             OPTM_G_HDMI_DVI      + OPTM_G_SINGLESEL,

                                             OPTM_G_SUBMENU,                          -- open "HDMI: %s" (filter), nested
                                             OPTM_G_HEADLINE,                         -- HDMI Filter
                                             OPTM_G_LINE,
                                             OPTM_G_HDMI_FILTER,                      -- No Filter
                                             OPTM_G_HDMI_FILTER,                      -- Sharp Bilinear
                                             OPTM_G_HDMI_FILTER,                      -- Bicubic
                                             OPTM_G_HDMI_FILTER,                      -- Smooth
                                             OPTM_G_HDMI_FILTER,                      -- Lanczos
                                             OPTM_G_HDMI_FILTER   + OPTM_G_STDSEL,    -- Scanlines (default; bit-identical to V5's CRT emulation look)
                                             OPTM_G_HDMI_FILTER,                      -- CRT (S-Video)
                                             OPTM_G_HDMI_FILTER,                      -- CRT (Composite)
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "HDMI: %s" (filter)

                                             OPTM_G_HDMI_ZOOM     + OPTM_G_SINGLESEL,
                                             OPTM_G_HDMI_RAW50    + OPTM_G_SINGLESEL + OPTM_DEP(OPTM_G_MACHINE_MODE, 0), -- Raw 50.1 Hz (PAL only)
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "HDMI: %s" (settings)

                                             OPTM_G_SUBMENU,                          -- open "VGA: %s"
                                             OPTM_G_HEADLINE,                         -- VGA Display Mode
                                             OPTM_G_LINE,
                                             OPTM_G_VGA_MODES     + OPTM_G_STDSEL,    -- Standard
                                             OPTM_G_LINE,
                                             OPTM_G_TEXT,                             -- Retro 15 kHz mode
                                             OPTM_G_LINE,
                                             OPTM_G_VGA_MODES,                        -- 15 kHz with HS/VS
                                             OPTM_G_VGA_MODES,                        -- 15 kHz with CSYNC
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "VGA: %s"

                                             OPTM_G_SUBMENU,                          -- open "SID: %s"
                                             OPTM_G_HEADLINE,                         -- SID Settings
                                             OPTM_G_LINE,
                                             OPTM_G_TEXT,                             -- Mono SID
                                             OPTM_G_LINE,
                                             OPTM_G_SID_SETUP     + OPTM_G_STDSEL,    -- 6581 (default, as in all releases so far)
                                             OPTM_G_SID_SETUP,                        -- 8580
                                             OPTM_G_LINE,
                                             OPTM_G_TEXT,                             -- Stereo SID
                                             OPTM_G_LINE,
                                             OPTM_G_SID_SETUP,                        -- L: 6581 R: 6581
                                             OPTM_G_SID_SETUP,                        -- L: 6581 R: 8580
                                             OPTM_G_SID_SETUP,                        -- L: 8580 R: 6581
                                             OPTM_G_SID_SETUP,                        -- L: 8580 R: 8580
                                             OPTM_G_LINE,
                                             OPTM_G_TEXT,                             -- Right SID Port
                                             OPTM_G_LINE,
                                             OPTM_G_SID_PORT      + OPTM_G_STDSEL,    -- D420
                                             OPTM_G_SID_PORT,                         -- D500
                                             OPTM_G_SID_PORT,                         -- DE00
                                             OPTM_G_SID_PORT,                         -- DF00
                                             OPTM_G_SID_PORT,                         -- Same as left SID port
                                             OPTM_G_LINE,
                                             OPTM_G_IMPROVE_AUDIO + OPTM_G_SINGLESEL + OPTM_G_STDSEL,
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "SID: %s"

                                             OPTM_G_IEC           + OPTM_G_SINGLESEL,

                                             OPTM_G_SUBMENU,                          -- open "Kernal: %s"
                                             OPTM_G_HEADLINE,                         -- Kernal Selection
                                             OPTM_G_LINE,
                                             OPTM_G_KERNAL_MODES  + OPTM_G_STDSEL,    -- Standard
                                             OPTM_G_KERNAL_MODES,                     -- Games System
                                             OPTM_G_KERNAL_MODES,                     -- Japanese
                                             OPTM_G_KERNAL_MODES,                     -- JiffyDOS
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Kernal: %s"

                                             OPTM_G_SUBMENU,                          -- open "Volume: %s"
                                             OPTM_G_HEADLINE,                         -- Volume Control
                                             OPTM_G_LINE,
                                             OPTM_G_VOLUME        + OPTM_G_STDSEL,    -- 100%
                                             OPTM_G_VOLUME,                           -- 95%
                                             OPTM_G_VOLUME,                           -- 90%
                                             OPTM_G_VOLUME,                           -- 85%
                                             OPTM_G_VOLUME,                           -- 80%
                                             OPTM_G_VOLUME,                           -- 75%
                                             OPTM_G_VOLUME,                           -- 70%
                                             OPTM_G_VOLUME,                           -- 65%
                                             OPTM_G_VOLUME,                           -- 60%
                                             OPTM_G_VOLUME,                           -- 55%
                                             OPTM_G_VOLUME,                           -- 50%
                                             OPTM_G_VOLUME,                           -- 45%
                                             OPTM_G_VOLUME,                           -- 40%
                                             OPTM_G_VOLUME,                           -- 35%
                                             OPTM_G_VOLUME,                           -- 30%
                                             OPTM_G_VOLUME,                           -- 25%
                                             OPTM_G_VOLUME,                           -- 20%
                                             OPTM_G_VOLUME,                           -- 15%
                                             OPTM_G_VOLUME,                           -- 10%
                                             OPTM_G_VOLUME,                           -- 5%
                                             OPTM_G_VOLUME,                           -- 0%
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Volume: %s"

                                             OPTM_G_SUBMENU,                          -- open "Advanced Settings"
                                             OPTM_G_HEADLINE,                         -- Advanced Settings
                                             OPTM_G_LINE,
                                             OPTM_G_RTC_GEOS      + OPTM_G_SINGLESEL, -- GEOS Real-Time-Clock

                                             OPTM_G_SUBMENU,                          -- open "OSM: %s", nested
                                             OPTM_G_HEADLINE,                         -- OSM Scaling
                                             OPTM_G_LINE,
                                             OPTM_G_OSM_MODE      + OPTM_G_STDSEL,    -- 100%
                                             OPTM_G_OSM_MODE,                         -- 89%
                                             OPTM_G_OSM_MODE,                         -- 80%
                                             OPTM_G_OSM_MODE,                         -- 73%
                                             OPTM_G_OSM_MODE,                         -- 67%
                                             OPTM_G_OSM_MODE,                         -- 62%
                                             OPTM_G_OSM_MODE,                         -- 57%
                                             OPTM_G_OSM_MODE,                         -- 53%
                                             OPTM_G_OSM_MODE,                         -- 50%
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "OSM: %s"

                                             OPTM_G_CIA_8521      + OPTM_G_SINGLESEL,

                                             OPTM_G_SUBMENU,                          -- open "VIC-II: %s", nested
                                             OPTM_G_HEADLINE,                         -- VIC-II model
                                             OPTM_G_LINE,
                                             OPTM_G_VICII_MODEL   + OPTM_G_STDSEL,    -- 656x/NMOS
                                             OPTM_G_VICII_MODEL,                      -- 856x/HMOS
                                             OPTM_G_VICII_MODEL,                      -- 856x/old HMOS
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "VIC-II: %s"

                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE         + OPTM_G_SUBMENU,   -- close "Advanced Settings"

                                             OPTM_G_LINE,
                                             OPTM_G_ABOUT_HELP    + OPTM_G_HELP,
                                             OPTM_G_LINE,
                                             OPTM_G_CLOSE
                                           );

--------------------------------------------------------------------------------------------------------------------
-- !!! CAUTION: M2M FRAMEWORK CODE !!! DO NOT TOUCH ANYTHING BELOW THIS LINE !!!
--------------------------------------------------------------------------------------------------------------------

--------------------------------------------------------------------------------------------------------------------
-- Address Decoding
--------------------------------------------------------------------------------------------------------------------

begin

addr_decode : process(clk_i)
   -- return ASCII value of given string at the position defined by index (zero-based)
   pure function str2data(str : string; index : integer) return std_logic_vector is
   variable strpos : integer;
   begin
      strpos := index + 1;
      if strpos <= str'length then
         return std_logic_vector(to_unsigned(character'pos(str(strpos)), 16));
      else
         return X"0000"; -- zero terminated strings
      end if;
   end function str2data;

   -- return the dimensions of the Options menu
   pure function getDXDY(dx, dy, index: natural) return std_logic_vector is
   begin
      case index is
         when 0 => return std_logic_vector(to_unsigned(dx + 2, 16));
         when 1 => return std_logic_vector(to_unsigned(dy + 2, 16));
         when others => return X"0000";
      end case;
   end function getDXDY;

   -- convert bool to std_logic_vector
   pure function bool2slv(b: boolean) return std_logic_vector is
   begin
      if b then
         return x"0001";
      else
         return x"0000";
      end if;
   end function bool2slv;

   -- return the General Configuration settings
   function getGenConf(index: natural) return std_logic_vector is
   begin
      case index is
         when 1      => return std_logic_vector(to_unsigned(RESET_COUNTER, 16));
         when 2      => return bool2slv(OPTM_PAUSE);
         when 3      => return bool2slv(WELCOME_ACTIVE);
         when 4      => return bool2slv(WELCOME_AT_RESET);
         when 5      => return bool2slv(KEYBOARD_AT_RESET);
         when 6      => return bool2slv(JOY_1_AT_RESET);
         when 7      => return bool2slv(JOY_2_AT_RESET);
         when 8      => return bool2slv(KEYBOARD_AT_OSD);
         when 9      => return bool2slv(JOY_1_AT_OSD);
         when 10     => return bool2slv(JOY_2_AT_OSD);
         when 11     => return std_logic_vector(to_unsigned(ASCAL_USAGE, 16));
         when 12     => return std_logic_vector(to_unsigned(ASCAL_MODE, 16));
         when 13     => return std_logic_vector(to_unsigned(VD_ANTI_THRASHING_DELAY, 16));
         when 14     => return std_logic_vector(to_unsigned(VD_ITERATION_SIZE, 16));
         when 15     => return bool2slv(SAVE_SETTINGS);
         when others => return x"0000";
      end case;
   end function getGenConf;

   variable index           : integer;
   variable whs_page_index  : integer;
   variable whs_array_index : integer;

begin

   if falling_edge(clk_i) then

      index           := to_integer(unsigned(address_i(11 downto  0)));
      whs_page_index  := to_integer(unsigned(address_i(19 downto 12)));
      whs_array_index := to_integer(unsigned(address_i(23 downto 20)));

      data_o <= x"EEEE";

      -----------------------------------------------------------------------------------
      -- Welcome & Help System: upper 4 bits of address equal SEL_WHS' upper 4 bits
      -----------------------------------------------------------------------------------

      if address_i(27 downto 24) = SEL_WHS(15 downto 12) then

         if  whs_array_index < WHS_RECORDS then
            if index = 4095 then
               data_o <= std_logic_vector(to_unsigned(WHS(whs_array_index).page_count, 16));
            else
               if index < WHS(whs_array_index).page_length(whs_page_index) then
                  data_o <= str2data(WHS_DATA, WHS(whs_array_index).page_start(whs_page_index) + index);
               else
                  data_o <= (others => '0'); -- zero-terminated strings
               end if;
            end if;
         end if;

      -----------------------------------------------------------------------------------
      -- All other selectors, which are 16-bit values
      -----------------------------------------------------------------------------------

      else

         case address_i(27 downto 12) is
            when SEL_GENERAL           => data_o <= getGenConf(index);
            when SEL_DIR_START         => data_o <= str2data(DIR_START, index);
            when SEL_CFG_FILE          => data_o <= str2data(CFG_FILE, index);
            when SEL_CORENAME          => data_o <= str2data(CORENAME, index);
            when SEL_OPTM_ITEMS        => data_o <= str2data(OPTM_ITEMS, index);
            when SEL_OPTM_MOUNT_STR    => data_o <= str2data(OPTM_S_MOUNT, index);
            when SEL_OPTM_CRTROM_STR   => data_o <= str2data(OPTM_S_CRTROM, index);
            when SEL_OPTM_SAVING_STR   => data_o <= str2data(OPTM_S_SAVING, index);
            when SEL_OPTM_GROUPS       => data_o <= std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15)) &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(14)) & "0" &
                                                    std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(12)) & "0000" &
                                                    std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(7 downto 0));
            when SEL_OPTM_STDSEL       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(8));
            when SEL_OPTM_LINES        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(9));
            when SEL_OPTM_START        => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(10));
            when SEL_OPTM_MOUNT_DRV    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(11));
            when SEL_OPTM_HELP         => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(13));
            when SEL_OPTM_SINGLESEL    => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(15));
            when SEL_OPTM_CRTROM       => data_o <= x"000" & "000" & std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(16));
            when SEL_OPTM_ICOUNT       => data_o <= x"00" & std_logic_vector(to_unsigned(OPTM_SIZE, 8));
            when SEL_OPTM_DIMENSIONS   => data_o <= getDXDY(OPTM_DX, OPTM_DY, index);
            when SEL_OPTM_DEPS         => if index = 4095 then               -- smart dependencies (OPTM_DEP):
                                            data_o <= x"2DEF";               -- magic "DEPendency Format 2" feature probe (item mask)
                                          else                               -- per line: {000, flag(b29), item mask(b28..25), mother(b24..17)}
                                            data_o <= "000" &
                                                      std_logic(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(29)) &
                                                      std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(28 downto 25)) &
                                                      std_logic_vector(to_unsigned(OPTM_GROUPS(index), OPTM_GTC)(24 downto 17));
                                          end if;

            when others                => null;
         end case;
      end if;
   end if;
end process;

end architecture beh;
