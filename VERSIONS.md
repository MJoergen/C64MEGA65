WIP Version 5.2 - MONTH DAY, YEAR
=================================

This is a maintenance release with the main purpose of stabilizing the HDMI
output by fixing the "Jail Bars" problem that mainly happened on R6 boards and
occasionally also on R3 boards. Moreover it contains a few bug fixes and minor
enhancements.

WIP List of things that have been already done for V5.2:

## New Features

* Simulated cartridges (`*.crt`) are now also supporting COMAL 80 and
  Simons BASIC
  (GitHub Pull Requests https://github.com/MJoergen/C64MEGA65/pull/168 and
   https://github.com/MJoergen/C64MEGA65/pull/169)

@TODO: MJoergen accepted more of them into the V5.2, add description here
in release notes and tag them with V5.2 in GitHub

## Bugfixes

* Fixed the "Jail Bars" HDMI problem aka vertical bars over HDMI. The root
  cause was a problem with our HyperRAM controller.
  (Fixed GitHub issues https://github.com/MJoergen/C64MEGA65/issues/145 and
   https://github.com/MJoergen/C64MEGA65/issues/166)

Version 5.1 - June 28, 2024
===========================

The main purpose of this release is to support the new 2024 version of the
MEGA65 (aka "R6") which sports enhanced hardware and better compatibility for
Commodore 64 cartridges. Moreover, this release also delivers improvements
for all MEGA65 models such as improved sound-over-HDMI compatibility,
bugfixes such as the "long-reset bug" and it improves the compatibility of
the core with demanding demos. Last but not least it makes the MEGA65's
Real-Time-Clock (RTC) available in GEOS.

## New Features: 2024 MEGA65 only

* Heavily improved quality of the analog audio output via the 3.1mm audio jack
  thanks to utilizing MEGA65's new audio DAC.

* The hardware of the MEGA65's Expansion Port (aka cartridge port) is now 100%
  compatible to the C64's hardware as it has bi-directional signals for RESET,
  IRQ and NMI. The C64 core is currently only leveraging the bi-directional
  signals for RESET, but this allowed us to make the core compatible with even
  more cartridges. Three examples that stand out are: (1) You do not need the
  "reset workaround" for the Kung Fu Flash (KFF) any more that is documented
  for the R3 board in doc/cartridges.md. (2) Reset buttons and "special"
  buttons at most freezer cartridges are working now. (3) MSSIAH works.

## New Features: All MEGA65

* The MEGA65's Real Time Clock (RTC) is now able to power the date/time in
  GEOS as soon as the appropriate [GEOS driver is installed](doc/RTC.md).
  From a technical perspective, we are simulating the "CP-Uhr F83" by
  Jörg Sproß which uses a PCF8583 chip that is connected via the tape port.

* You can now close the "About & Help" screens also by pressing Run/Stop.

## Improved HDMI Compatibility: All MEGA65

* Some monitors (e.g. the Philips S-line 275S1AE) did not output audio when
  displaying HDMI. The problem was related to a parity error in the IEC60958
  channel which is fixed now.

* Fixed random micro cuts of sound that occured on on some HDMI displays.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/13)

## Improved C64 Accuracy & Compatibility: All MEGA65

* Added VIC-II compatibility fix from MiSTer by gyurco which improves the
  core's compatibility with several demos
  (Fixes GitHub issue https://github.com/MiSTer-devel/C64_MiSTer/issues/160)

* Improved disk change detection for multi-disk demos. This fixes for
  example Royal Arte/Booze Design.
  (MiSTer's GitHub issue 160 was "re-used" for this fix which is completely
  independent from the above-mentioned one, this is why we are linking to
  a specific comment: https://github.com/MiSTer-devel/C64_MiSTer/issues/160#issuecomment-1874613523)

## Bugfixes: 2024 MEGA65 only

* HDMI backpower is no issue any more

## Bugfixes: All MEGA65

* The "long-reset" feature was broken in V5.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/79)

* Fixed missing ".." in folders created with certain macOS versions
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/111)

* Fixed a crash in the file browser.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/95)

* Stabilized the REU simulation. This fixes a known glitch plus it ensures
  that the REU simulation will run more stable also on the newer
  HyperRAM revisions that are built into 2023 and 2024 batches of the MEGA65:
  Treu Love demo: Fixed very rare REU/HyperRAM issues
  (GitHub issue https://github.com/MJoergen/C64MEGA65/issues/55)

* In V5 we introduced a new feature: You can go one menu-level up (from a sub-
  menu to the main-menu) by pressing Run/Stop. Subsequently you can also close
  then the main menu via Run/Stop (additionally to via Help). But if you did
  so, the Run/Stop keypress that happens to close the OSM was propagated to
  the C64.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/80)

* The "Audio improvements" feature only worked with analog audio (3.5mm jack)
  but not with digital audio via HDMI.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/100)

* MEGA65's internal floppy drive kepts spinning when a floppy was inserted.
  (Fixed GitHub issue https://github.com/MJoergen/C64MEGA65/issues/110)

Version 5 - June 23, 2023
=========================

Hardware support release: Insert hardware cartridges into the MEGA65's
Expansion Port or simulate cartridges via `*.crt` files. Connect IEC devices
such as drives and printers and enjoy Stereo SID sound. For an authentic
retro feeling, feed a 15 kHz CSYNC video signal into your monitor or use the
MiSTer VGA to RGB SCART cable to connect an old TV. Load faster using JiffyDOS
or by directly loading `*.prg` files.

## New Features

* Hardware cartridges can be used in the MEGA65's Expansion Port. Most game
  cartridges are supported and also many Flash Cartridges (e.g. EF1, EF3, KFF)
  and some more sophisticated utility cartridges and freezers are supported
  (see [cartridge documentation](doc/cartridges.md)).

* Run simulated cartridges by loading `*.crt` files from your SD card. Most
  cartridge types are supported. Saving data on the cartridge is not yet
  supported.

* Ability to directly load `*.prg` files.

* Ability to switch Kernal versions: Standard, C64 Games System, Japanese
  Revision and [JiffyDOS](doc/jiffy.md).

* Stereo SID support: You can choose from multiple real dual SID combinations
  and enjoy stereo SID tunes and demos. And you can also use "pseudo stereo"
  by running the two different SID models 6581 and 8050 at the same (one left
  and one right) while they play the same mono tune.

* Hardware IEC port: Attach real 1541 & 1581 drives as well as printers,
  plotters or modern devices such as the SD2IEC and the Ultimate-II+.

* Support for three VGA output modes: Standard VGA, 15 kHz retro RGB output
  with either horizontal & vertical sync signals or with a composite sync
  (CSYNC) signal. The latter one allows you for example to connect the MEGA65
  to an old SCART TV using the [MiSTer VGA to RGB SCART cable](https://ultimatemister.com/product/rgb-scart-cable/)
  or to connect it to an old monitor using a standard VGA to BNC cable.

* More clearly arranged menu system using submenus.

* Possibility to scale-down the On-Screen-Menu (OSM). Use-case: Compensate
  for large overscans of certain retro Cathode Ray Tubes.

* File browser's page up/down (cursor left/right) now jumps to the very first
  item when you press cursor left one (more) time while you are on the first
  page and to the very last item when you press cursor right one (more) time
  while you are on the last page.

* A long reset is now visualized: The power led is glowing blue as long as the
  user keeps the reset button pressed during a long reset.

## Improved C64 and C1541 Accuracy & Compatibility

* Improved the 6510 CPU's interrupt dispatching which results in more demos
  working flawlessly (for example "All Hallows' Eve", this fixes
  https://github.com/MJoergen/C64MEGA65/issues/9).

* Improved accuracy of the frequency ratio between the C64's CPU and the C1541
  floppy's CPU which results in more demos working flawlessly (for example
  "Unbounded" by Demotion and "Ice Cream Castle" by Crest). It also fixes an
  issue with the diskmag "Input 64"
  (https://github.com/MJoergen/C64MEGA65/issues/2).

* Merge MiSTer upstream fixes to improve simulation accuracy and compatibility
  with real hardware:
  - CIA: Disk parport: Ignore inputs on pins configured as output
    (MiSTer commit 4da804c, fix by sorgelig)
  - CIA: Fix timer reset values: Game "Arctic Shipwreck" works now and
    therefore this fixes https://github.com/MiSTer-devel/C64_MiSTer/issues/107
    (MiSTer commit 7eca7e3, fix by gyurco)
  - VIC: Change xscroll and turbo latch time
    (MiSTer commit f3a137b, fix by sorgelig)

## Improved HDMI Compatibility

* Works with more HDMI monitors, frame grabbers, HDMI switches, etc.
  The core was not compliant to section 4.2.7 of the HDMI specification
  version 1.4b: It did not assert the +5V power signal. Now it does
  assert the +5 power signal via the FPGA pin `ct_hpd`.

* Fully dynamic flicker-free HDMI, which reduces our output latency on
  HDMI to less than 1ms and also eliminates the artifact, that moved from
  the top to the bottom of the screen every once in a while.

## Bugfixes

* Fixed a bug in the REU simulation that affected some owners of the newest
  MEGA65 batches who have a so called "Revision D HyperRAM". One effect of the
  bug was that these users were not able to play Sonic the Hedgehog.

* Fixed the possibility of corrupting currently mounted D64 images: If the
  user changed menu settings while the core was writing to a D64 disk image
  (yellow MEGA65 drive led), then there was the possibility that this very D64
  disk image would be corrupted.

## Under the Hood

* Updated to Vivado 2022.2 which will result in higher quality bitstreams.

* Migrated to the newest version of the MiSTer2MEGA65 framework. The C64
  core will benefit from an easier and faster workflow when it comes to
  migrating new framework features to the core.

* Now using glitch-free clock multiplexers: The user can switch the
  "HDMI: Flicker-free" mode ON/OFF without the system performing a reset.

Version 4 - November 25, 2022
=============================

Productivity release: Write support for the virtual C1541 and a 512 KB RAM
Expansion Unit (1750 REU) are the main features: Save your high-scores and
your gaming progress to disk (D64) and work productively with GEOS by speeding
up 10x using the REU and by saving your work persistently to disk.
Demo fans can now enjoy all the awesome REU releases on CSDB and gamers can
play the fantastic Sonic the Hedgehog for REU.

## New Features

* C1541 write support using D64 image files on the SD card.

* Read/write support for non-standard D64 images with 40 tracks and no error
  bytes, i.e. additionally to D64 files that are exactly 174,848 bytes in size
  you can now also use files that are 196,608 bytes in size.

* 1750 REU support: The REU is as close to cycle accurate as it can go. It is
  not perfect, but 99.9% perfect - it even runs the picky
  [TreuLove_ForReal1750Reu.d64](http://csdb.dk/getinternalfile.php/144854/TreuLove_ForReal1750Reu.d64)
  version of Booze Design's Treu Love demo
  ([see CSDB page](https://csdb.dk/release/?id=144105))
  that is supposed to only run on real hardware. The REU also works perfectly
  with GEOS. You can switch the REU on/off using the options menu.

* Choice between 16:9 or 4:3 HDMI output resolutions: By default the core
  outputs 720p on HDMI which is a 16:9 resolution (even though the actual
  C64's output is pixel-perfect 4:3 as we are adding black bars left and
  right). With this new feature you can switch from 720p to 576p aka
  PAL over HDMI (720x576 pixels) and then select if you have a 4:3 monitor
  or a 5:4 monitor and then enjoy the best possible image.

* Ability to save the configuration settings of the core. You need to copy
  the file c64mega65 to the folder /c64 to activate this feature.

* CIA: New option to configure CIA version (6526 or 8521): There is at least
  one demo known - XXX from Lethargy - where the demo only runs flawlessly if
  the CIA is a 8521.

* Mouse: Support for C64 mice and MouSTer

* Reduced joystick latency from 5ms to 1ms by decreasing the stable time of
  the signal debouncer.

## Bugfixes

* The drive led is not blinking any more during normal read/write operations.
  It behaves now like the real drive led and only blinks on errors.

* Fixed a small (probably inaudible) SID bug by merging
  [this](https://github.com/MiSTer-devel/C64_MiSTer/commit/711dffbddf0b591fadfe81e4e3ed4dd3af6be143)
  an upstream fix from MiSTer.

* Fixed several bugs in the file browser that you use for mounting D64 files:

  - The file browser was not able to display the "+" sign due to a bug
    in the font. Instead, a space (empty character, " ") was printed, for
    example the file name "C64+" was shown as "C64 ".

  - Directories where not always being sorted in proper alphabetical order and
    ascending numbers.

  - While browsing directories with a large amount of subdirectories (e.g.
    large game libraries): When you entered a subdirectory located on a page
    other than page one (e.g. by scrolling down quite a bit) and then left
    this very subdirectory (one level up), then the selection cursor jumped
    back to page one.

  - Fixed file browsing bug that still displayed the old SD card's
    directory when you changed the SD card while the file browser was *not*
    open. (The bug did not occur when you changed the SD card while the file
    *was* open.)

## Known problems that we plan to fix in Version 5

* Formatting disks does not work. We know how to fix it but this will need a
  larger refactoring (see "Technical Roadmap" in `ROADMAP.md`).

* The demo "All Hallows' Eve" (https://demozoo.org/productions/314618/) is
  crashing towards the end of disk 2. We fixed the issue in an experimental
  core that you can download here on GitHub:
  https://github.com/MJoergen/C64MEGA65/issues/9

* There is a compatibility issue due to the "HDMI: Flicker-free" mode. We only
  saw it occur at the German disk magazine "Input 64 Issue 1/85" and at the
  1991 demo Unbounded by Demotion (https://csdb.dk/release/?id=2464). We fixed
  the issue in an experimental core that you can download here on GitHub:
  https://github.com/MJoergen/C64MEGA65/issues/2

Version 3 - June 27, 2022
=========================

This version is mainly a bugfix & compatibility release that is meant to
heavily increase the C64 compatibility of the core. It also adds support
for Paddles.

## New Feature

* Support for Paddles added: Connect compatible paddles to the joystick ports.

## Bugfixes

* CIA Bug fixed: The bug prevented demos like Comalight and Apparatus to run
  and in games like Commando, the joystick's fire button did not work.

* CIA Bug fixed: "icr3 set priority over clear", merged from from MiSTer to
  our codebase. This bug prevented games like Arkanoid to run.

* User Port "low active" bug fixed: The bug prevented games like
  Bomberman C64, that support a Multiplayer Joystick Interface
  (https://www.c64-wiki.com/wiki/Multiplayer_Interface), to work. Reason is,
  that due to the low-active nature of the User Port these games detected
  "ghost activities" on the (not existent) joystick connected via User Port.

* Zero Page register $01 has the correct default value $37 now. It had the
  wrong value $C7 due to two bugs that have been fixed:
  (a) The Cassette Port's s SENSE and READ input are low active.
  (b) The wrapper code that turns the 6502 into a 6510 contained a bug.

Version 2 - June 18, 2022
=========================

This version is mainly a bugfix & stability release: The focus was not to add
a lot of new features, but to make sure that the C64 core works flawlessly
with more MEGA65 machines than version 1 did. We also added a DVI option
(see below) to increase the amount of displays that work with the core.

## Bugfixes

* MAX10 reset bug fixed: Fixes the "ambulance lights" problem when starting
  the core and fixes non-working reset buttons
* SD card problem fixed: When neither any D64 file was present on the SD card
  and additionally, there was not a single subdirectory, then the core
  crashed with "Corrupt memory structure: Linked-list boundary" when one tried
  to mount a disk.
* Fixed distorted On-Screen-Menu in "VGA Retro 15KHz RGB" mode

## DVI Option

* The DVI option is meant to improve the compatibility with certain monitors.
  Choosing "HDMI: DVI (no sound)" in the On-Screen-Menu will activate it and
  thus stop sending sound packages within the HDMI data stream.

Version 1 - April 26, 2022
==========================

Experience the Commodore 64 with great accuracy and sublime compatibility
on your MEGA65! It can run a ton of games and demos and it offers convenient
features.

## Features

* PAL standard C64 (running standard KERNAL and standard C1541 DOS)
* PAL 720 x 576 pixels (4:3) @ 50 Hz via VGA: for a true retro feeling
* 720p @ 50 Hz or 60 Hz (16:9) via HDMI: for convenience
* Sound output via 3.5mm jack and via HDMI
* SID 6581 and 8580
* MEGA65 keyboard support (including cursor keys)
* Joystick support
* On-Screen-Menu via Help button to mount drives and to configure options
* C1541 read-only support: Mount standard `*.D64` via SD card to drive 8
* Drive led during virtual disk access
* CRT filter: Optional visual scanlines on HDMI so that the output looks more
  like an old monitor or TV
* Crop/Zoom: On HDMI, you can optionally crop the top and bottom border of
  the C64's output and zoom in, so that the 16:9 screen real-estate is
  utilized more efficiently. Great for games.
* Audio processing: Optionally improve the raw audio output of the system
* Smart reset: Press the reset button briefly and only the C64 core is being
  reset; press it longer than 1.5 seconds and the whole machine is reset.
