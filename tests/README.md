C64 for MEGA65 Regression Testing
=================================

Before releasing a new version we strive to run all regression tests described
here. Since running through all the [demos](demos.md) takes some serious
effort, it might be that we are not always doing it.

Version 5.2 - April 21, 2025
----------------------------

| Status                 | Test                                                 | Done by                | Date              
|:-----------------------|------------------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark:     | Basic regression tests: Main menu                    | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | Basic regression tests: Additional Smoke Tests       | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | HDMI & VGA                                           | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | SID                                                  | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | C64 Emulator Test Suite V2.15                        | AmokPhaze101           | 04/21/2025 
| :grey_exclamation:     | [Demos](demos.md)                                    | AmokPhaze101           | 04/21/2025 (partial, 20 demos tested)
| :white_check_mark:     | Writing to `*.d64` images                            | AmokPhaze101           | 04/21/2025 
| :grey_exclamation:     | GEOS: REU (sim), GeoRAM (HW), mouse, disk write test | AmokPhaze101           | 04/21/2025 (only GeoRAM HW was not tested)
| :white_check_mark:     | PLA Test                                             | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | Dedicated REU tests                                  | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | Dedicated hardware cartridge tests                   | AmokPhaze101           | 04/21/2025
| :white_check_mark:     | Dedicated simulated cartridge tests                  | AmokPhaze101           | 04/21/2025

### Basic regression tests

All done by AmokPhaze101 on April 2025 (on R3A & R6)

#### Main menu

Work with the main menu and run software that allows to test the following and make sure that
you have a JTAG connection and an **active serial terminal** to observe the debug output of the core:

* Filebrowser
* Mount disk
* Load `*.prg`
* Short reset vs. long reset: Test drive led's behavior
* Stress the OSM ("unexpected" resets, opening closing "all the time" while things that change the OSM are happening in the background, etc.)
* Play with the Expansion Port settings, start a hardware CRT and an emulated CRT (there are more detailed and dedicated cartridge tests later)
* Flip joystick ports
* Save configuration: Switch off/switch, check configuration
* Save configuration: Switch the SD card while the core is running and observe how settings are not saved.
* Save configuration: Omit the config file and use a wrong config file
* CIA: Use 8521 (C64C)
* Kernal: Test all Kernal variants including Jiffy DOS.
* Audio Improvements
* About and Help
* Close Menu

#### Additional Smoke Tests

* Try to mount disk while SD card is empty
* Work with both SD cards (and switch back and forth in file-browser)
* Remove external SD card while menu and file browser are not open;
  reinsert while file browser is open
* Work with large directory trees / game libraries
* Eagle's Nest: Reset-tests: Short reset leads to main screen. Long reset
  resets the whole core (not only the C64).
* Giana Sisters: Joystick and latency
* Space Lords: Support for 4 paddles

### HDMI & VGA

All done by AmokPhaze101 on April 2025 (on R3A & R6)

#### HDMI

Test if the resolutions and frequencies are correct:

```
16:9 720p 50 Hz = 1,280 x 720 pixel
16:9 720p 60 Hz = 1,280 x 720 pixel
4:3  576p 50 Hz =   720 x 576 pixel 
5:4  576p 50 Hz =   720 x 576 pixel 
```

Test HDMI modes:

* Flicker-free: Use the [Testcase from README.md](../README.md#flicker-free-hdmi)
* DVI (no sound)
* CRT emulation
* Zoom-in

#### VGA

Switch-off "HDMI: Flicker-free" before performing the following VGA tests and
check for each VGA mode if the **OSM completely fits on the screen**:

* Standard
* Retro 15 kHz with HS/VS
* Retro 15 kHz with CSYNC

Make sure that the Retro 15 kHz tests are performed on real analog retro CRTs.

### SID

All done by AmokPhaze101 on April 2025 (on R3A & R6)

Identical to V5.1 on both R3A & R6 

* Check 6581 vs 8580 detection using the [Mathematica demo](https://csdb.dk/release/?id=11611)
* Check the 8580 filters using the [Smile to the Sky demo](https://csdb.dk/release/?id=172574)
* Check true stereo SID using the [Game of Thrones demo](https://csdb.dk/release/?id=157533)
* Use [Sidplay64](https://csdb.dk/release/?id=161475) and dedicated stereo SID files to
  test the various "Right SID port" settings: `D420.d64` and `D500.d64`

The folder [sidtests](sidtests) in this repo contains all the test files including `D420.d64` and `D500.d64`.

### Writing to `*.d64` images

All done by AmokPhaze101 on April 2025 (on R3A & R6)

Identical to Version 5.1 on both R3A & R6 - so we consider this as a success.

* Work with `Disk-Write-Test.d64` and create some files and re-load them
* Try to interrupt the saving by pressing <kbd>Reset</kbd> while the yellow light is on.
  Do this with the OSM open and also with the OSM closed. Watch if the `<Saving>` is
  being influenced by the reset attempt.
* Katakis: High score saving/loading

### C64 Emulator Test Suite V2.15

All done by AmokPhaze101 on March 2025 (on R3A & R6)

Identical to V5.1 on both R3A & R6 

As a reminder, with 5.1 on R3A we identified a difference with V5.0 and V4.0 :
This was investigated [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133) and since at that time the involved change had no impact on the core behaviour, we considered it as a success.
However, later, we have identified and investigated two issue directly related to it : 
[GitHub issue #135](https://github.com/MJoergen/C64MEGA65/issues/135) 
[GitHub issue #164](https://github.com/MJoergen/C64MEGA65/issues/164).

This issue is planned to be fixed in V5.3/v6.0 as it impacts the behaviour of a few demos only.


| Status             | Detail                                      | Done by                |  Comment      
|:-------------------|---------------------------------------------|:-----------------------|:--------------
| :white_check_mark: | Disc 1: Complete                            | AmokPhaze101           |
| :white_check_mark: | Disc 2: From start to and incl. "Trap15"    | AmokPhaze101           |
| :x:                | Disc 2: "Trap16"                            | AmokPhaze101           | [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133)
| :x:                | Disc 2: "Trap17"                            | AmokPhaze101           | [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133) 
| :white_check_mark: | Disc 2: "Branchwrap" to  "MMU"              | AmokPhaze101           |
| :x:                | Disc 2: "CPUPort"                           | AmokPhaze101           |
| :white_check_mark: | Disc 2: "CPUTiming" to  "Cntdef"            | AmokPhaze101           |
| :x:                | Disc 2: "CIA1TA"                            | AmokPhaze101           |
| :x:                | Disc 2: "CIA1TB"                            | AmokPhaze101           |
| :x:                | Disc 3: "CIA2TA"                            | AmokPhaze101           |
| :x:                | Disc 3: "CIA2TB"                            | AmokPhaze101           |

### Dedicated REU tests

All done by AmokPhaze101 on April 2025 (on R3A & R6)

Identical to Version 5.1 on R6 & R3A - so we consider this as a success.

#### Demos

All done by AmokPhaze101 on April 2025 (on R3A & R6)

| Status             | Demo                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Dark Mights - Movie 32                      | [CSDB](https://csdb.dk/release/?id=5903)   be sure to enable REU : the demo will not complain if REU is disabled but won't display anything !
| :white_check_mark: | Expand by Bonzai                            | [CSDB](https://csdb.dk/release/?id=192886)
| :x:                | fREUd                                       | [CSDB](https://csdb.dk/release/?id=149560) In the part with boucing balls all the backgrounds are screwed up. Same issue on MiSTer C64_20221117.rbf. Perfectly runs on real Commodore C64 with Ultimate Cartridge.
| :white_check_mark: | Frontier                                    | [CSDB](https://csdb.dk/release/?id=120458)
| :white_check_mark: | Globe 2016                                  | [CSDB](https://csdb.dk/release/?id=152053) Takes a few minutes to be fully rendered
| :white_check_mark: | Life will never be the same Digidemo 286K_1 | [CSDB](https://csdb.dk/release/?id=3736)
| :white_check_mark: | Qi                                          | [CSDB](https://csdb.dk/release/?id=139711) if loading disk 2 does not result in demo moving forward, reload disk2 again
| :white_check_mark: | REU demo Zelda                              | [CSDB](https://csdb.dk/release/?id=68189)
| :white_check_mark: | Treu Love                                   | [CSDB](https://csdb.dk/release/?id=144105) Ensure to use this file: `TreuLove_ForReal1750Reu.d64`

#### Games

All done by AmokPhaze101 on April 2025 (on R3A & R6)

| Status             | Game                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Sonic The Hedgehog v1.2+5                   | [CSDB](https://csdb.dk/release/?id=212617)
| :white_check_mark: | Creatures II +9Hi - Mystic                  | [CSDB](https://csdb.dk/release/?id=41884)
| :white_check_mark: | Exterminator_1991_Audiogenic_(REU)          | [CSDB](https://csdb.dk/release/?id=168549)
| :white_check_mark: | From the West                               | [CSDB](https://csdb.dk/release/?id=185613)
| :white_check_mark: | Ski_or_Die_1990_Electronic_Arts_REU         | [CSDB](https://csdb.dk/release/?id=161436) Takes ages to load but it's ok
| :white_check_mark: | Walkerz +3                                  | [CSDB](https://csdb.dk/release/?id=43006)

### Dedicated hardware cartridge tests

All done by AmokPhaze101 on April 2025 (on R6 only)

Identical to Version 5.1 on R6 - so we consider this as a success.

| Status             | Test                                                                                                                        | Comment
|:-------------------|-----------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------
| :white_check_mark: | Using a correct core #0: Test if we can directly boot to a hardware cartridge                                               |
| :white_check_mark: | Using a correct core #0: Test if the hardware cartridge is ignored in case simulated REU or simulated cartridge is selected |
| :white_check_mark: | Test a bunch of original old game cartridges                                                                                | Tested Grid Runner, Avenger
| :white_check_mark: | Test an old Ultimax game                                                                                                    | Tested Pinball Spectacular, SeaWolves 
| :white_check_mark: | Test a bunch of new game cartridges                                                                                         | Tested A pig quest, ZetaWing, Sam's Journey, Galencia, Soul Force, Robot Jet Action, Super Bread Box  
| :white_check_mark: | Save game and load game to/from the original Sam's Journey cartridge                                                        |
| :white_check_mark: | Final Cartridge III                                                                                                         |
| :white_check_mark: | Action Replay Professional 6.0                                                                                              |
| :white_check_mark: | Power Cartridge                                                                                                             | 
| :white_check_mark: | Flash the EasyFlash **1CR** with a small (<64k) and large (>512k) game and playtest these games                             | Flashed and successfully run many small and big cartridges to EF1 "all through all" and smd versions (flashed 6 different EF1 devices)
| :white_check_mark: | Flash the EasyFlash **3** with a small (<64k) and large (>512k) game and playtest these games                               | Flashed and successfully run many small and big cartridges to 3 different EF3 devices
| :white_check_mark: | EasyFlash **3**: Test all freezers that the EF3 supports as described in [cartridges.md](../doc/cartridges.md)              | Only tested with Super Snapshot V5 and could trigger the monitor after having started a demo.
| :white_check_mark: | Kung Fu Flash                                                                                                               | Success: No workaround needed on R6 in contrast to R3A
| :grey_exclamation: | Work with GEOS and GeoRAM                                                                                                   | Not tested this time (last test: Version 5.0)
| :grey_exclamation: | Xpander 3 with Datel Midi interface, Cynth Cart 64 and Midi Keyboard                                                        | Not tested this time (last test: Version 5.1)

### Dedicated simulated cartridge tests

All done by AmokPhaze101 on April 2025 (on R3A & R6)

5 new cartridge types supported and all previously supported formats are ok on both R6 & R3A - so we consider this as a success.

| Status             | Game Name                                                                     | Cartridge Type                             | Comment
|:-------------------|:------------------------------------------------------------------------------|:-------------------------------------------|:---------------------------------------------------------------------
| :white_check_mark: | Beamrider                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Centipede                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Gridrunner                                                                    | 0 - generic cartridge                      |
| :white_check_mark: | Gyruss                                                                        | 0 - generic cartridge                      |
| :white_check_mark: | Pac-Man                                                                       | 0 - generic cartridge                      |
| :x:                | Action Replay v6.0 Professional                                               | 1 - Action Replay                          | [GitHub issue #69](https://github.com/MJoergen/C64MEGA65/issues/69)                      
| :white_check_mark: | Black Box V8                                                                  | 3 - Final Cartridge III                    |
| :x:                | Final Cartridge III                                                           | 3 - Final Cartridge III                    | [GitHub issue #71](https://github.com/MJoergen/C64MEGA65/issues/71)
| :white_check_mark: | Simon BASIC                                                                   | 4 - Simon BASIC                            |
| :white_check_mark: | Kung Fu Master                                                                | 5 - Ocean type 1                           |
| :white_check_mark: | Ghostbusters                                                                  | 5 - Ocean type 1                           |
| :white_check_mark: | Batman The Movie                                                              | 5 - Ocean type 1                           |
| :white_check_mark: | Robocop 2                                                                     | 5 - Ocean type 1                           |
| :white_check_mark: | Soul Force                                                                    | 5 - Ocean type 1                           |
| :white_check_mark: | Codemasters - Fast Food, Pro Skateboard, Pro Tennis                           | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Microprose  - Soccer, Rick Dangerous & Stunt Car Racer                        | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Colossus Chess, International Football & Silicon Syborgs                      | 8 - Super Games                            |
| :white_check_mark: | Vegetables Deluxe                                                             | 8 - Super Games                            |
| :white_check_mark: | Fiendish Freddy's Big Top o' Fun, Flimbo’s Quest, Klax & International Soccer | 15 - C64 Game System, System 3             |
| :white_check_mark: | Last Ninja Remix                                                              | 15 - C64 Game System, System 3             |
| :white_check_mark: | Myth - History in the Making                                                  | 15 - C64 Game System, System 3             |
| :white_check_mark: | After the War                                                                 | 17 - Dinamic                               |
| :white_check_mark: | Astro Marine Corps                                                            | 17 - Dinamic                               |
| :white_check_mark: | Narco Police                                                                  | 17 - Dinamic                               |
| :white_check_mark: | L'Abbaye Des Morts                                                            | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Archon II - Adept                                                             | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Arkanoid - Revenge of Doh                                                     | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Park Patrol                                                                   | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Super Bread Box                                                               | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Comal 80                                                                      | 21 - Comal 80                              |
| :white_check_mark: | Structured BASIC Waterloo 1984                                                | 22 - Structured Basic                      |
| :white_check_mark: | Mikro Assembler                                                               | 28 - Mikro Assembler                       |
| :white_check_mark: | A Pig Quest                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | Bruce Lee II                                                                  | 32 - EasyFlash                             |
| :white_check_mark: | Monstro Giganto                                                               | 32 - EasyFlash                             |
| :white_check_mark: | Muddy Racer                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | ZetaWing                                                                      | 32 - EasyFlash                             |
| :white_check_mark: | Freaky Fish DX                                                                | 60 - GMod2                                 |
| :white_check_mark: | Metal Warrior Ultra                                                           | 60 - GMod2                                 |
| :white_check_mark: | Outrage                                                                       | 60 - GMod2                                 |
| :white_check_mark: | Polar Bear                                                                    | 60 - GMod2                                 |
| :white_check_mark: | Sam's Journey                                                                 | 60 - GMod2                                 |
| :white_check_mark: | BMP data turbo 2000                                                           | 83 - BMP data turbo 2000                   |

### Demos 

All done by AmokPhaze101 on April 2025 (on R3A & R6)

Since running through all the [demos](demos.md) takes some serious
effort, we only tested 20 of the most demanding demos for this V5.2 minor release. 

| Group                                                                                                            | Year      | Demo                                                                  | Download                                                  | Instructions                                                                                                                                        | V4.0 status        | V5.0 status        | V5.1 status        | V5.2 status        | Issue description                                                                                                                                                                                                                                                                                                                                                                                                                                                    |Comment                                                        
|:-----------------------------------------------------------------------------------------------------------------|:----------|:----------------------------------------------------------------------|:----------------------------------------------------------|:----------------------------------------------------------------------------------------------------------------------------------------------------|:-------------------|:-------------------|:-------------------|:-------------------|:---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:--------------------------------------------------------------
| Arise                                                                                                            | 2022      | E2IRA                                                                 | [Download on csdb.dk](https://csdb.dk/release/?id=218343) | Use [Use this specific version](https://csdb.dk/release/download.php?id=269249)                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |                                                               
| Arise                                                                                                            | 2024      | 3SIRA                                                                 | [Download on csdb.dk](https://csdb.dk/release/?id=245148) |                                                                                                                                                     |                    |                    |                    | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |                                                               
| Bonzai                                                                                                           | 2021      | Bromance                                                              | [Download on csdb.dk](https://csdb.dk/release/?id=205526) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Bonzai                                                                                                           | 2022      | All Hallows' Eve (coop demo)                                          | [Download on csdb.dk](https://csdb.dk/release/?id=225023) | Requires joystick in port 2 to play the game at the end.                                                                                            | :x:                | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Booze Design                                                                                                     | 2008      | Edge of Disgrace                                                      | [Download on csdb.dk](https://csdb.dk/release/?id=72550)  |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |  there are glitches but observables on both core and true c64. 
| Booze Design                                                                                                     | 2008      | Codeboys & Endians                                                    | [Download on csdb.dk](https://csdb.dk/release/?id=249805) |                                                                                                                                                     |                    |                    |                    | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |  there are glitches but observables on both core and true c64. 
| Censor Design                                                                                                    | 2015      | ComaLand 100%                                                         | [Download on csdb.dk](https://csdb.dk/release/?id=139278) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |  there are glitches but observables on both core and true c64 
| Censor Design                                                                                                    | 2023      | Wonderland XIV                                                        | [Download on csdb.dk](https://csdb.dk/release/?id=232980) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Censor Design                                                                                                    | 2024      | What is the matrix 2                                                  | [Download on csdb.dk](https://csdb.dk/release/?id=247796) |                                                                                                                                                     |                    |                    |                    | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Censor Design, Fairlight, Offence                                                                                | 2018      | We come in Peace (coop demo)                                          | [Download on csdb.dk](https://csdb.dk/release/?id=163427) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Fairlight                                                                                                        | 2024      | 13:37                                                                 | [Download on csdb.dk](https://csdb.dk/release/?id=242855) |                                                                                                                                                     |                    |                    | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Fairlight                                                                                                        | 2024      | The Demo Coder                                                        | [Download on csdb.dk](https://csdb.dk/release/?id=247776) |                                                                                                                                                     |                    |                    |                    | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Genesis Project                                                                                                  | 2020      | Memento Mori                                                          | [Download on csdb.dk](https://csdb.dk/release/?id=195841) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Genesis Project                                                                                                  | 2023      | No Bounds                                                             | [Download on csdb.dk](https://csdb.dk/release/?id=232957) |                                                                                                                                                     |                    | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Kryo                                                                                                             | 2025      | Nine                                                                  | [Download on csdb.dk](https://csdb.dk/release/?id=249713) |                                                                                                                                                     |                    |                    |                    | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Lethargy                                                                                                         | 2020      | Gamertro                                                              | [Download on csdb.dk](https://csdb.dk/release/?id=195843) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Lft                                                                                                              | 2016      | Lunatico                                                              | [Download on csdb.dk](https://csdb.dk/release/?id=151273) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Nah-Kolor                                                                                                        | 2024      | Multiverse 100%                                                       | [Download on csdb.dk](https://csdb.dk/release/?id=242830) |                                                                                                                                                     |                    |                    | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |  there are glitches but observables on both core and true c64                                                                
| Performers                                                                                                       | 2018      | C=BIT18                                                               | [Download on csdb.dk](https://csdb.dk/release/?id=170950) |                                                                                                                                                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               
| Performers                                                                                                       | 2023      | Next Level                                                            | [Download on csdb.dk](https://csdb.dk/release/?id=232976) |                                                                                                                                                     |                    | :white_check_mark: | :white_check_mark: | :white_check_mark: |                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |                                                               

Version 5.1 - June 28, 2024
---------------------------

| Status                 | Test                                                 | Done by                | Date              
|:-----------------------|------------------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark:     | Basic regression tests: Main menu                    | AmokPhaze101           | 6/25/24
| :white_check_mark:     | Basic regression tests: Additional Smoke Tests       | AmokPhaze101           | 6/25/24
| :white_check_mark:     | HDMI & VGA                                           | AmokPhaze101           | 6/25/24
| :white_check_mark:     | SID                                                  | AmokPhaze101           | 6/25/24
| :white_check_mark:     | C64 Emulator Test Suite V2.15                        | AmokPhaze101           | 6/25/24
| :white_check_mark:     | [Demos](demos.md)                                    | AmokPhaze101           | 6/25/24
| :white_check_mark:     | Writing to `*.d64` images                            | AmokPhaze101           | 6/25/24
| :white_check_mark:     | GEOS: REU (sim), GeoRAM (HW), mouse, disk write test | AmokPhaze101           | 6/25/24
| :white_check_mark:     | PLA Test                                             | AmokPhaze101           | 6/25/24
| :white_check_mark:     | Dedicated REU tests                                  | AmokPhaze101           | 6/25/24
| :white_check_mark:     | Dedicated hardware cartridge tests                   | AmokPhaze101           | 6/25/24
| :white_check_mark:     | Dedicated simulated cartridge tests                  | AmokPhaze101           | 6/25/24

### Basic regression tests

All done by AmokPhaze101 on June 2024 (on R3A & R6)

#### Main menu

Work with the main menu and run software that allows to test the following and make sure that
you have a JTAG connection and an **active serial terminal** to observe the debug output of the core:

* Filebrowser
* Mount disk
* Load `*.prg`
* Short reset vs. long reset: Test drive led's behavior
* Stress the OSM ("unexpected" resets, opening closing "all the time" while things that change the OSM are happening in the background, etc.)
* Play with the Expansion Port settings, start a hardware CRT and an emulated CRT (there are more detailed and dedicated cartridge tests later)
* Flip joystick ports
* Save configuration: Switch off/switch, check configuration
* Save configuration: Switch the SD card while the core is running and observe how settings are not saved.
* Save configuration: Omit the config file and use a wrong config file
* CIA: Use 8521 (C64C)
* Kernal: Test all Kernal variants including Jiffy DOS.
* Audio Improvements
* About and Help
* Close Menu

#### Additional Smoke Tests

* Try to mount disk while SD card is empty
* Work with both SD cards (and switch back and forth in file-browser)
* Remove external SD card while menu and file browser are not open;
  reinsert while file browser is open
* Work with large directory trees / game libraries
* Eagle's Nest: Reset-tests: Short reset leads to main screen. Long reset
  resets the whole core (not only the C64).
* Giana Sisters: Joystick and latency
* Space Lords: Support for 4 paddles

### HDMI & VGA

All done by AmokPhaze101 on June 2024 (on R3A & R6)

#### HDMI

Test if the resolutions and frequencies are correct:

```
16:9 720p 50 Hz = 1,280 x 720 pixel
16:9 720p 60 Hz = 1,280 x 720 pixel
4:3  576p 50 Hz =   720 x 576 pixel 
5:4  576p 50 Hz =   720 x 576 pixel 
```

Test HDMI modes:

* Flicker-free: Use the [Testcase from README.md](../README.md#flicker-free-hdmi)
* DVI (no sound)
* CRT emulation
* Zoom-in

#### VGA

Switch-off "HDMI: Flicker-free" before performing the following VGA tests and
check for each VGA mode if the **OSM completely fits on the screen**:

* Standard
* Retro 15 kHz with HS/VS
* Retro 15 kHz with CSYNC

Make sure that the Retro 15 kHz tests are performed on real analog retro CRTs.

### SID

All done by AmokPhaze101 on June 2024 (on R3A & R6)

Identical to Version 5.0 on R3A - so we consider this as a success.

* Check 6581 vs 8580 detection using the [Mathematica demo](https://csdb.dk/release/?id=11611)
* Check the 8580 filters using the [Smile to the Sky demo](https://csdb.dk/release/?id=172574)
* Check true stereo SID using the [Game of Thrones demo](https://csdb.dk/release/?id=157533)
* Use [Sidplay64](https://csdb.dk/release/?id=161475) and dedicated stereo SID files to
  test the various "Right SID port" settings: `D420.d64` and `D500.d64`

The folder [sidtests](sidtests) in this repo contains all the test files including `D420.d64` and `D500.d64`.

### Writing to `*.d64` images

All done by AmokPhaze101 on June 2024 (on R3A & R6)

Identical to Version 5.0 on R3A - so we consider this as a success.

* Work with `Disk-Write-Test.d64` and create some files and re-load them
* Try to interrupt the saving by pressing <kbd>Reset</kbd> while the yellow light is on.
  Do this with the OSM open and also with the OSM closed. Watch if the `<Saving>` is
  being influenced by the reset attempt.
* Katakis: High score saving/loading

### C64 Emulator Test Suite V2.15

All done by AmokPhaze101 on June 2024 (on R3A & R6)

Different from V5.0 and V4.0 on R3A  - However this was investigated [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133) and since the involved change has no impact on the core behaviour, we consider this as a success.

| Status             | Detail                                      | Done by                |  Comment      
|:-------------------|---------------------------------------------|:-----------------------|:--------------
| :white_check_mark: | Disc 1: Complete                            | AmokPhaze101           |
| :white_check_mark: | Disc 2: From start to and incl. "Trap15"    | AmokPhaze101           |
| :x:                | Disc 2: "Trap16"                            | AmokPhaze101           | [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133)
| :x:                | Disc 2: "Trap17"                            | AmokPhaze101           | [GitHub issue #133](https://github.com/MJoergen/C64MEGA65/issues/133) 
| :white_check_mark: | Disc 2: "Branchwrap" to  "MMU"              | AmokPhaze101           |
| :x:                | Disc 2: "CPUPort"                           | AmokPhaze101           |
| :white_check_mark: | Disc 2: "CPUTiming" to  "Cntdef"            | AmokPhaze101           |
| :x:                | Disc 2: "CIA1TA"                            | AmokPhaze101           |
| :x:                | Disc 2: "CIA1TB"                            | AmokPhaze101           |
| :x:                | Disc 3: "CIA2TA"                            | AmokPhaze101           |
| :x:                | Disc 3: "CIA2TB"                            | AmokPhaze101           |

### Dedicated REU tests

All done by AmokPhaze101 on June 2024 (on R3A & R6)

Identical to Version 5.0 on R3A - so we consider this as a success.

#### Demos

All done by AmokPhaze101 on June 2024 (on R3A & R6)

| Status             | Demo                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Dark Mights - Movie 32                      | [CSDB](https://csdb.dk/release/?id=5903)
| :white_check_mark: | Expand by Bonzai                            | [CSDB](https://csdb.dk/release/?id=192886)
| :x:                | fREUd                                       | [CSDB](https://csdb.dk/release/?id=149560) In the part with boucing balls all the backgrounds are screwed up. Same issue on MiSTer C64_20221117.rbf. Perfectly runs on real Commodore C64 with Ultimate Cartridge.
| :white_check_mark: | Frontier                                    | [CSDB](https://csdb.dk/release/?id=120458)
| :white_check_mark: | Globe 2016                                  | [CSDB](https://csdb.dk/release/?id=152053) Takes a few minutes to be fully rendered
| :white_check_mark: | Life will never be the same Digidemo 286K_1 | [CSDB](https://csdb.dk/release/?id=3736)
| :white_check_mark: | Qi                                          | [CSDB](https://csdb.dk/release/?id=139711)
| :white_check_mark: | REU demo Zelda                              | [CSDB](https://csdb.dk/release/?id=68189)
| :white_check_mark: | Treu Love                                   | [CSDB](https://csdb.dk/release/?id=144105) Ensure to use this file: `TreuLove_ForReal1750Reu.d64`

#### Games

All done by AmokPhaze101 on June 2024 (on R3A & R6)

| Status             | Game                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Sonic The Hedgehog v1.2+5                   | [CSDB](https://csdb.dk/release/?id=212617)
| :white_check_mark: | Creatures II +9Hi - Mystic                  | [CSDB](https://csdb.dk/release/?id=41884)
| :white_check_mark: | Exterminator_1991_Audiogenic_(REU)          | [CSDB](https://csdb.dk/release/?id=168549)
| :white_check_mark: | From the West                               | [CSDB](https://csdb.dk/release/?id=185613)
| :white_check_mark: | Ski_or_Die_1990_Electronic_Arts_REU         | [CSDB](https://csdb.dk/release/?id=161436) Takes ages to load but it's ok
| :white_check_mark: | Walkerz +3                                  | [CSDB](https://csdb.dk/release/?id=43006)

### Dedicated hardware cartridge tests

All done by AmokPhaze101 on June 2024 (on R6 only)

Better than Version 5.0 on R3A - so we consider this as a success.

| Status             | Test                                                                                                                        | Comment
|:-------------------|-----------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------
| :white_check_mark: | Using a correct core #0: Test if we can directly boot to a hardware cartridge                                               |
| :white_check_mark: | Using a correct core #0: Test if the hardware cartridge is ignored in case simulated REU or simulated cartridge is selected |
| :white_check_mark: | Test a bunch of original old game cartridges                                                                                | Tested Grid Runner, Avenger
| :white_check_mark: | Test an old Ultimax game                                                                                                    | Tested Pinball Spectacular, SeaWolves 
| :white_check_mark: | Test a bunch of new game cartridges                                                                                         | Tested ZetaWing, Sam's Journey, Galencia, Soul Force, Robot Jet Action, Super Bread Box  
| :white_check_mark: | Save game and load game to/from the original Sam's Journey cartridge                                                        |
| :grey_exclamation: | Final Cartridge III                                                                                                         | Not tested this time (last test: Version 5.0)  
| :grey_exclamation: | Action Replay Professional 6.0                                                                                              | Not tested this time (last test: Version 5.0)
| :white_check_mark: | Power Cartridge                                                                                                             |
| :white_check_mark: | Flash the EasyFlash **1CR** with a small (<64k) and large (>512k) game and playtest these games                             |
| :white_check_mark: | Flash the EasyFlash **3** with a small (<64k) and large (>512k) game and playtest these games                               |
| :white_check_mark: | EasyFlash **3**: Test all freezers that the EF3 supports as described in [cartridges.md](../doc/cartridges.md)              | 
| :white_check_mark: | Kung Fu Flash                                                                                                               | Success: No workaround needed on R6 in contrast to R3A
| :grey_exclamation: | Work with GEOS and GeoRAM                                                                                                   | Not tested this time (last test: Version 5.0)
| :white_check_mark: | Xpander 3 with Datel Midi interface, Cynth Cart 64 and Midi Keyboard                                                        |

### Dedicated simulated cartridge tests

All done by AmokPhaze101 on June 2024 (on R3A & R6)

Identical to Version 5.0 on R3A - so we consider this as a success.

| Status             | Game Name                                                                     | Cartridge Type                             | Comment
|:-------------------|:------------------------------------------------------------------------------|:-------------------------------------------|:---------------------------------------------------------------------
| :white_check_mark: | Beamrider                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Centipede                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Gridrunner                                                                    | 0 - generic cartridge                      |
| :white_check_mark: | Gyruss                                                                        | 0 - generic cartridge                      |
| :white_check_mark: | Pac-Man                                                                       | 0 - generic cartridge                      |
| :x:                | Action Replay v6.0 Professional                                               | 1 - Action Replay                          | [GitHub issue #69](https://github.com/MJoergen/C64MEGA65/issues/69)                      
| :x:                | Black Box V8                                                                  | 3 - Final Cartridge III                    |
| :x:                | Final Cartridge III                                                           | 3 - Final Cartridge III                    | [GitHub issue #71](https://github.com/MJoergen/C64MEGA65/issues/71)
| :white_check_mark: | Kung Fu Master                                                                | 5 - Ocean type 1                           |
| :white_check_mark: | Ghostbusters                                                                  | 5 - Ocean type 1                           |
| :white_check_mark: | Batman The Movie                                                              | 5 - Ocean type 1                           |
| :white_check_mark: | Robocop 2                                                                     | 5 - Ocean type 1                           |
| :white_check_mark: | Soul Force                                                                    | 5 - Ocean type 1                           |
| :white_check_mark: | Codemasters - Fast Food, Pro Skateboard, Pro Tennis                           | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Microprose  - Soccer, Rick Dangerous & Stunt Car Racer                        | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Colossus Chess, International Football & Silicon Syborgs                      | 8 - Super Games                            |
| :white_check_mark: | Vegetables Deluxe                                                             | 8 - Super Games                            |
| :white_check_mark: | Fiendish Freddy's Big Top o' Fun, Flimbo’s Quest, Klax & International Soccer | 15 - C64 Game System, System 3             |
| :white_check_mark: | Last Ninja Remix                                                              | 15 - C64 Game System, System 3             |
| :white_check_mark: | Myth - History in the Making                                                  | 15 - C64 Game System, System 3             |
| :white_check_mark: | After the War                                                                 | 17 - Dinamic                               |
| :white_check_mark: | Astro Marine Corps                                                            | 17 - Dinamic                               |
| :white_check_mark: | Narco Police                                                                  | 17 - Dinamic                               |
| :white_check_mark: | L'Abbaye Des Morts                                                            | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Archon II - Adept                                                             | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Arkanoid - Revenge of Doh                                                     | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Park Patrol                                                                   | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Super Bread Box                                                               | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | A Pig Quest                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | Bruce Lee II                                                                  | 32 - EasyFlash                             |
| :white_check_mark: | Monstro Giganto                                                               | 32 - EasyFlash                             |
| :white_check_mark: | Muddy Racer                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | ZetaWing                                                                      | 32 - EasyFlash                             |
| :white_check_mark: | Freaky Fish DX                                                                | 60 - GMod2                                 |
| :white_check_mark: | Metal Warrior Ultra                                                           | 60 - GMod2                                 |
| :white_check_mark: | Outrage                                                                       | 60 - GMod2                                 |
| :white_check_mark: | Polar Bear                                                                    | 60 - GMod2                                 |
| :white_check_mark: | Sam's Journey                                                                 | 60 - GMod2                                 |

Version 5 - June 23, 2023
-------------------------

| Status                 | Test                                                 | Done by                | Date              
|:-----------------------|------------------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark:     | Basic regression tests: Main menu                    | AmokPhaze101           | 6/4/23
| :bangbang:             | Basic regression tests: Additional Smoke Tests       | sy2002                 | 6/19/23
| :white_check_mark:     | HDMI & VGA                                           | AmokPhaze101           | 6/3/23
| :white_check_mark:     | SID                                                  | AmokPhaze101           | 6/3/23
| :white_check_mark:     | C64 Emulator Test Suite V2.15                        | AmokPhaze101           | 6/4/23
| :white_check_mark:     | [Demos](demos.md)                                    | AmokPhaze101           | 6/19/23
| :white_check_mark:     | Writing to `*.d64` images                            | sy2002                 | 6/19/23
| :white_check_mark:     | GEOS: REU (sim), GeoRAM (HW), mouse, disk write test | sy2002                 | 6/19/23
| :white_check_mark:     | PLA Test                                             | sy2002                 | 6/19/23
| :white_check_mark:     | Dedicated REU tests                                  | AmokPhaze101           | 6/3/23
| :white_check_mark:     | Dedicated hardware cartridge tests                   | sy2002                 | 6/19/23
| :white_check_mark:     | Dedicated simulated cartridge tests                  | AmokPhaze101           | 6/7/23

### Basic regression tests

#### Main menu

Work with the main menu and run software that allows to test the following and make sure that
you have a JTAG connection and an **active serial terminal** to observe the debug output of the core:

* Filebrowser
* Mount disk
* Load `*.prg`
* Short reset vs. long reset: Test drive led's behavior
* Stress the OSM ("unexpected" resets, opening closing "all the time" while things that change the OSM are happening in the background, etc.)
* Play with the Expansion Port settings, start a hardware CRT and an emulated CRT (there are more detailed and dedicated cartridge tests later)
* Flip joystick ports
* Save configuration: Switch off/switch, check configuration
* Save configuration: Switch the SD card while the core is running and observe how settings are not saved.
* Save configuration: Omit the config file and use a wrong config file
* CIA: Use 8521 (C64C)
* Kernal: Test all Kernal variants including Jiffy DOS.
* Audio Improvements
* About and Help
* Close Menu

#### Additional Smoke Tests

* Try to mount disk while SD card is empty
* Work with both SD cards (and switch back and forth in file-browser)
* Remove external SD card while menu and file browser are not open;
  reinsert while file browser is open
* Work with large directory trees / game libraries
* Eagle's Nest: Reset-tests: Short reset leads to main screen. Long reset
  resets the whole core (not only the C64).
* Giana Sisters: Joystick and latency
* Space Lords: Support for 4 paddles

##### Regression

:bangbang: Long reset does not reset Eagle's Nest any more: [GitHub issue #79](https://github.com/MJoergen/C64MEGA65/issues/79)

### HDMI & VGA

#### HDMI

Test if the resolutions and frequencies are correct:

```
16:9 720p 50 Hz = 1,280 x 720 pixel
16:9 720p 60 Hz = 1,280 x 720 pixel
4:3  576p 50 Hz =   720 x 576 pixel
5:4  576p 50 Hz =   720 x 576 pixel
```

Test HDMI modes:

* Flicker-free: Use the [Testcase from README.md](../README.md#flicker-free-hdmi)
* DVI (no sound)
* CRT emulation
* Zoom-in

#### VGA

Switch-off "HDMI: Flicker-free" before performing the following VGA tests and
check for each VGA mode if the **OSM completely fits on the screen**:

* Standard
* Retro 15 kHz with HS/VS
* Retro 15 kHz with CSYNC

Make sure that the Retro 15 kHz tests are performed on real analog retro CRTs.

### SID

* Check 6581 vs 8580 detection using the [Mathematica demo](https://csdb.dk/release/?id=11611)
* Check the 8580 filters using the [Smile to the Sky demo](https://csdb.dk/release/?id=172574)
* Check true stereo SID using the [Game of Thrones demo](https://csdb.dk/release/?id=157533)
* Use [Sidplay64](https://csdb.dk/release/?id=161475) and dedicated stereo SID files to
  test the various "Right SID port" settings: `D420.d64` and `D500.d64`

The folder [sidtests](sidtests) in this repo contains all the test files including `D420.d64` and `D500.d64`.

### Writing to `*.d64` images

* Work with `Disk-Write-Test.d64` and create some files and re-load them
* Try to interrupt the saving by pressing <kbd>Reset</kbd> while the yellow light is on.
  Do this with the OSM open and also with the OSM closed. Watch if the `<Saving>` is
  being influenced by the reset attempt.
* Katakis: High score saving/loading

### C64 Emulator Test Suite V2.15

Identical to Version 4 - so we consider this as a success.

| Status             | Detail                                      | Done by                | Date              
|:-------------------|---------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark: | Disc 1: Complete                            | AmokPhaze101           | 06/04/23
| :white_check_mark: | Disc 2: From start to and incl. "Trap16"    | AmokPhaze101           | 06/04/23
| :x:                | Disc 2: "Trap17"                            | AmokPhaze101           | 06/04/23
| :white_check_mark: | Disc 2: "Branchwrap" to  "MMU"              | AmokPhaze101           | 06/04/23
| :x:                | Disc 2: "CPUPort"                           | AmokPhaze101           | 06/04/23
| :white_check_mark: | Disc 2: "CPUTiming" to  "Cntdef"            | AmokPhaze101           | 06/04/23
| :x:                | Disc 2: "CIA1TA"                            | AmokPhaze101           | 06/04/23
| :x:                | Disc 2: "CIA1TB"                            | AmokPhaze101           | 06/04/23
| :x:                | Disc 3: "CIA2TA"                            | AmokPhaze101           | 06/04/23
| :x:                | Disc 3: "CIA2TB"                            | AmokPhaze101           | 06/04/23

### Dedicated REU tests

All done by AmokPhaze101 on 6/3/23

#### Demos

| Status             | Demo                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Dark Mights - Movie 32                      | [CSDB](https://csdb.dk/release/?id=5903)
| :white_check_mark: | Expand by Bonzai                            | [CSDB](https://csdb.dk/release/?id=192886)
| :x:                | fREUd                                       | [CSDB](https://csdb.dk/release/?id=149560) In the part with boucing balls all the backgrounds are screwed up. Same issue on MiSTer C64_20221117.rbf. Perfectly runs on real Commodore C64 with Ultimate Cartridge.
| :white_check_mark: | Frontier                                    | [CSDB](https://csdb.dk/release/?id=120458)
| :white_check_mark: | Globe 2016                                  | [CSDB](https://csdb.dk/release/?id=152053) Takes a few minutes to be fully rendered
| :white_check_mark: | Life will never be the same Digidemo 286K_1 | [CSDB](https://csdb.dk/release/?id=3736)
| :white_check_mark: | Qi                                          | [CSDB](https://csdb.dk/release/?id=139711)
| :white_check_mark: | REU demo Zelda                              | [CSDB](https://csdb.dk/release/?id=68189)
| :white_check_mark: | Treu Love                                   | [CSDB](https://csdb.dk/release/?id=144105) Ensure to use this file: `TreuLove_ForReal1750Reu.d64`

#### Games

| Status             | Game                                        | Comment
|:-------------------|---------------------------------------------|----------------------------------------------------
| :white_check_mark: | Sonic The Hedgehog v1.2+5                   | [CSDB](https://csdb.dk/release/?id=212617)
| :white_check_mark: | Creatures II +9Hi - Mystic                  | [CSDB](https://csdb.dk/release/?id=41884)
| :white_check_mark: | Exterminator_1991_Audiogenic_(REU)          | [CSDB](https://csdb.dk/release/?id=168549)
| :white_check_mark: | From the West                               | [CSDB](https://csdb.dk/release/?id=185613)
| :white_check_mark: | Ski_or_Die_1990_Electronic_Arts_REU         | [CSDB](https://csdb.dk/release/?id=161436) Takes ages to load but it's ok
| :white_check_mark: | Walkerz +3                                  | [CSDB](https://csdb.dk/release/?id=43006)

### Dedicated hardware cartridge tests

All done by sy2002 on 6/19/23

| Status             | Test                                                                                                                        | Comment
|:-------------------|-----------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------
| :white_check_mark: | Using a correct core #0: Test if we can directly boot to a hardware cartridge                                               |
| :white_check_mark: | Using a correct core #0: Test if the hardware cartridge is ignored in case simulated REU or simulated cartridge is selected |
| :white_check_mark: | Test a bunch of original old game cartridges                                                                                | Tested Last Ninja Remix, Super Games, Wizard of Wor
| :white_check_mark: | Test an old Ultimax game                                                                                                    | Tested Pinball Spectacular
| :white_check_mark: | Test a bunch of new game cartridges                                                                                         | Tested Muddy Racers, Sam's Journey, Soul Force, The Curse of Rabenstein, Wormhole
| :white_check_mark: | Save game and load game to/from the original Sam's Journey cartridge                                                        |
| :white_check_mark: | Final Cartridge III                                                                                                         | [Works with workarounds](../doc/cartridges.md#final-cartridge-iii)
| :white_check_mark: | Action Replay Professional 6.0                                                                                              |
| :white_check_mark: | Power Cartridge                                                                                                             |
| :white_check_mark: | Flash the EasyFlash **1CR** with a small (<64k) and large (>512k) game and playtest these games                             |
| :white_check_mark: | Flash the EasyFlash **3** with a small (<64k) and large (>512k) game and playtest these games                               |
| :white_check_mark: | EasyFlash **3**: Test all freezers that the EF3 supports as described in [cartridges.md](../doc/cartridges.md)              |
| :white_check_mark: | Kung Fu Flash using the workaround described in [cartridges.md](../doc/cartridges.md)                                       |
| :white_check_mark: | Work with GEOS and GeoRAM                                                                                                   |

### Dedicated simulated cartridge tests

All done by AmokPhaze101 on 6/7/23

| Status             | Game Name                                                                     | Cartridge Type                             | Comment
|:-------------------|:------------------------------------------------------------------------------|:-------------------------------------------|:---------------------------------------------------------------------
| :white_check_mark: | Beamrider                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Centipede                                                                     | 0 - generic cartridge                      |
| :white_check_mark: | Gridrunner                                                                    | 0 - generic cartridge                      |
| :white_check_mark: | Gyruss                                                                        | 0 - generic cartridge                      |
| :white_check_mark: | Pac-Man                                                                       | 0 - generic cartridge                      |
| :x:                | Action Replay v6.0 Professional                                               | 1 - Action Replay                          | [GitHub issue #69](https://github.com/MJoergen/C64MEGA65/issues/69)                      
| :x:                | Black Box V8                                                                  | 3 - Final Cartridge III                    |
| :x:                | Final Cartridge III                                                           | 3 - Final Cartridge III                    | [GitHub issue #71](https://github.com/MJoergen/C64MEGA65/issues/71)
| :white_check_mark: | Kung Fu Master                                                                | 5 - Ocean type 1                           |
| :white_check_mark: | Ghostbusters                                                                  | 5 - Ocean type 1                           |
| :white_check_mark: | Batman The Movie                                                              | 5 - Ocean type 1                           |
| :white_check_mark: | Robocop 2                                                                     | 5 - Ocean type 1                           |
| :white_check_mark: | Soul Force                                                                    | 5 - Ocean type 1                           |
| :white_check_mark: | Codemasters - Fast Food, Pro Skateboard, Pro Tennis                           | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Microprose  - Soccer, Rick Dangerous & Stunt Car Racer                        | 7 - Fun Play, Power Play                   |
| :white_check_mark: | Colossus Chess, International Football & Silicon Syborgs                      | 8 - Super Games                            |
| :white_check_mark: | Vegetables Deluxe                                                             | 8 - Super Games                            |
| :white_check_mark: | Fiendish Freddy's Big Top o' Fun, Flimbo’s Quest, Klax & International Soccer | 15 - C64 Game System, System 3             |
| :white_check_mark: | Last Ninja Remix                                                              | 15 - C64 Game System, System 3             |
| :white_check_mark: | Myth - History in the Making                                                  | 15 - C64 Game System, System 3             |
| :white_check_mark: | After the War                                                                 | 17 - Dinamic                               |
| :white_check_mark: | Astro Marine Corps                                                            | 17 - Dinamic                               |
| :white_check_mark: | Narco Police                                                                  | 17 - Dinamic                               |
| :white_check_mark: | L'Abbaye Des Morts                                                            | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Archon II - Adept                                                             | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Arkanoid - Revenge of Doh                                                     | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Park Patrol                                                                   | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | Super Bread Box                                                               | 19 - Magic Desk, Domark, HES Australia     |
| :white_check_mark: | A Pig Quest                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | Bruce Lee II                                                                  | 32 - EasyFlash                             |
| :white_check_mark: | Monstro Giganto                                                               | 32 - EasyFlash                             |
| :white_check_mark: | Muddy Racer                                                                   | 32 - EasyFlash                             |
| :white_check_mark: | ZetaWing                                                                      | 32 - EasyFlash                             |
| :white_check_mark: | Freaky Fish DX                                                                | 60 - GMod2                                 |
| :white_check_mark: | Metal Warrior Ultra                                                           | 60 - GMod2                                 |
| :white_check_mark: | Outrage                                                                       | 60 - GMod2                                 |
| :white_check_mark: | Polar Bear                                                                    | 60 - GMod2                                 |
| :white_check_mark: | Sam's Journey                                                                 | 60 - GMod2                                 |

Additional tests of [cartridge releases](carts.md) have been performed by AmokPhaze101 in May 2023.

Version 4 - November 25, 2022
-----------------------------

| Status             | Test                                        | Done by                | Date              
|:-------------------|---------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark: | Basic regression tests                      | sy2002                 | 11/24/22
| :white_check_mark: | C64 Emulator Test Suite V2.15               | sy2002                 | 11/19/22
| :white_check_mark: | [Demos](demos.md)                           | AmokPhaze101           | October & November 2022
| :white_check_mark: | Disk-Write-Test.d64                         | sy2002                 | 11/24/22
| :white_check_mark: | Dedicated REU tests                         | AmokPhaze101           | 11/19/22
| :white_check_mark: | GEOS: REU, mouse, disk write test           | sy2002                 | 11/24/22

### How to interpret the test results

We consider the pattern of success (:white_check_mark:) and failure (:x:) in
the [Demos](demos.md), the C64 Emulator Test suite and the dedicated REU tests
(scroll down, see below) as the baseline for Version 4 and therefore as
"success". Future versions must deliver the same - or better.

### Basic regression tests

#### Main menu

Work with the main menu and run software that allows to test the following:

* Mount disk
* Filebrowser
* Save configuration, switch off/switch, check configuration
* Flip joystick ports
* SID: 6581 and 8580
* REU: 1750 with 512KB
* HDMI: CRT emulation
* HDMI: Zoom-in
* HDMI: 16:9 50 Hz
* HDMI: 16:9 60 Hz
* HDMI:  4:3 50 Hz
* HDMI:  5:4 50 Hz
* HDMI: Flicker-free
* HDMI: DVI (no sound)
* VGA: Retro 15Khz RGB
* CIA: Use 8521 (C64C)
* Audio Improvements
* About and Help
* Close Menu

#### Additional Smoke Tests

* Try to mount disk while SD card is empty
* Work with both SD cards (and switch back and forth in file-browser)
* Remove external SD card while menu and file browser are not open;
  reinsert while file browser is open
* Work with large directory trees / game libraries
* Eagle's Nest: Reset-tests: Short reset leads to main screen. Long reset
  resets the whole core (not only the C64).
* Giana Sisters: Scrolling while flicker-free is ON/OFF, joystick, latency
* Katakis: High score saving/loading
* Smile to the Sky (demo): SID 8580 filters
* Sonic the Hedgehog: REU
* Space Lords: Support for 4 paddles

### C64 Emulator Test Suite V2.15

Tested with 6526 CIA. We consider the following test pattern, i.e. "Disc 1
Complete" and Disc 2 "everything works but the below-mentioned exceptions" as
"success" and our baseline for Release 4.

| Status             | Detail                                      | Done by                | Date              
|:-------------------|---------------------------------------------|:-----------------------|:--------------------------
| :white_check_mark: | Disc 1: Complete                            | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: From start to and incl. "Trap16"    | sy2002                 | 11/19/22
| :x:                | Disc 2: "Trap17"                            | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: "Branchwrap" to  "MMU"              | sy2002                 | 11/19/22
| :x:                | Disc 2: "CPUPort"                           | sy2002                 | 11/19/22
| :white_check_mark: | Disc 2: "CPUTiming" to  "Cntdef"            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA1TA"                            | sy2002                 | 11/19/22
| :x:                | Disc 2: "CIA1TB"                            | sy2002                 | 11/19/22
| :x:                | Disc 3: "CIA2TA"                            | sy2002                 | 11/19/22
| :x:                | Disc 3: "CIA2TB"                            | sy2002                 | 11/19/22

### Dedicated REU tests

All done by AmokPhaze101 on 11/19/22

#### Demos

| Status             | Demo                                        | Comment
|:-------------------|---------------------------------------------|:---------------------------------------------------
| :white_check_mark: | Dark Mights - Movie 32                      | 
| :white_check_mark: | Expand by Bonzai                            | 
| :x:                | fREUd                                       | In the part with boucing balls all the backgrounds are screwed up. Same issue on MiSTer C64_20221117.rbf. Perfectly runs on real Commodore C64 with Ultimate Cartridge.
| :white_check_mark: | Globe 2016                                  | Wait 7 minutes before rendering starts
| :white_check_mark: | Life will never be the same Digidemo 286K_1 | Press SPACE after having swapped disk
| :white_check_mark: | Qi                                          | 
| :white_check_mark: | REU demo Zelda                              | Just scroll the map with joystick in port 2
| :white_check_mark: | Treu Love                                   | OK but not 100%: In the main first scroller sprites have horizontal white pixel lines when on left and right borders, while they should not. Same issue on MiSTer C64_20221117.rbf. Perfectly runs on real Commodore C64 with Ultimate Cartridge.

#### Games

| Status             | Game                                        | Comment
|:-------------------|---------------------------------------------|:---------------------------------------------------
| :white_check_mark: | Sonic The Hedgehog v1.2+5                   | Joystick in port 2, choose options with ARROWS and RETURN, accept to load full game into the REU when asked
| :x:                | Creatures II +9Hi - Mystic                  | Impossible to load the game until the end. Same issues on MiSTer C64_20221117.rbf and real C64+Ultimate Cartridge.
| :white_check_mark: | Exterminator_1991_Audiogenic_(REU)          | 
| :white_check_mark: | from_the_west[r]                            | All is happening in REU (no disk access) but interraction is quite slow
| :white_check_mark: | Ski_or_Die_1990_Electronic_Arts_REU         | Joystick in port 2. Takes ages to load from disk to the REU on our core as well as on MiSTer and a real C64.
| :white_check_mark: | Walkerz +3                                  | Joystick in port 2
