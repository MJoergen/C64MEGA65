C64 for MEGA65 Regression Testing
=================================

Before releasing a new version we strive to run all regression tests described
here. Since running through all the [demos](demos.md) takes some serious
effort, it might be that we are not always doing it.

Version WIP-V6-A19 - TBD
------------------------

@TODO: Test the reworked master-volume control (issue #85). The OSM "Volume"
slider went from 10% to 5% steps (21 positions, 100% down to 0%) and is now
actually wired to the audio path with a perceptual, loudness-linear taper: each
5% step is a 5 percentage-point change in *perceived* loudness, so 50% sounds
half as loud as 100% (-10 dB), 25% a quarter (-20 dB) and 0% is silence.

* Confirm the slider attenuates audio identically on **both** outputs: HDMI and
  analog (VGA 3.5 mm line-out). The gain is applied once in `main.vhd` ahead of
  the audio split in the framework, so both paths should track.
* Confirm 100% is bit-transparent (no perceived loss versus earlier releases,
  where the volume was effectively fixed at full scale).
* Confirm 50% is roughly half as loud and 0% is fully muted.
* Regression-check the OSM items whose control bits shifted by +10 when the ten
  extra volume steps were inserted: `CIA: Use 8521`, `OSM Scaling`,
  `RTC for GEOS` and the `VIC-II model`. Their behavior must be unchanged.
* Config file: `OPTM_SIZE` grew from 160 to 170, so any existing saved-settings
  config file must be regenerated with `M2M/tools/make_config.sh` or the
  on-screen settings will no longer persist across reboots.

Version WIP-V6-A18X2 - 2026-07-18
---------------------------------

WIP-V6-A18X2 (`d94fa73`) was released to the community as an explicitly
identified Alpha build.

* Build availability: PASS for R3, R4, R5 and R6; all four artifacts were
  produced and distributed
* R3 reader qualification: PASS in the controlled simulation/hardware campaign,
  with additional positive community reports covering three physical 1581 disks
* R3 JiffyDOS/internal-1581 compatibility: PASS; Mike351 reported JiffyDOS and
  the internal physical 1581 working without issue on WIP-V6-A18X2. The report
  did not state whether `jd-c1581.bin` was loaded, so stock-ROM fallback versus
  accelerated JiffyDOS-1581 remains to be distinguished if that detail matters
* R4/R5/R6 functional reader qualification: PENDING community feedback over the
  following days and weeks; artifact availability alone is not a functional pass
* Physical disk writes remain deliberately unsupported in this Alpha

Version WIP-V6-A18X1 - TBD
--------------------------

@TODO: Test the experimental read-only internal-1581 read path (#90). This is
the first hardware bring-up of the MEGA65's internal 3.5" drive as a physical
Commodore 1581 behind drive 8. Simulation and extensive R3 testing have passed;
on 2026-07-19 Discord tester Mike351 additionally reported a correct directory
and successful PRG load from a test/demo disk originating with his genuine
1581, followed by successful demo execution from a second 1581-formatted
floppy. On 2026-07-20 a second tester, dejavu4u2, independently reported loading
a GEOS 1581 disk from another physical 3.5-inch floppy in the internal drive.
A separate CBM-subpartition concern from nobruinfo was withdrawn after he found
an incorrect Wedge command and a malformed on-disk partition track/sector chain;
the BASIC command-channel test behaved as expected, so this was not a core
defect. Complete the remaining items below and ensure all four board bitstreams
build (R3/R4/R5/R6; functional read testing is on R3):

* Source select: with a DD disk in the internal drive, switch on "Use internal
  1581" in the disk-mount menu and confirm drive 8 now talks to the physical
  drive (motor spins up, drive responds); switch it off again and confirm
  drive 8 is served from the mounted disk image once more (the previously
  mounted image is preserved across the switch)
* Source select WITHOUT a mounted image: from a fresh boot with no disk image
  mounted at all, switch on "Use internal 1581" and confirm drive 8 comes
  alive and reads the physical disk (the drive must NOT stay in the
  held-in-reset state that unmounted image drives normally have); switching it
  off again with nothing mounted returns drive 8 to "device not present"
* Media revalidation on source switch: with a D81 mounted, load the directory
  from the image, switch to the internal drive and `LOAD"$",8` again - the
  REAL disk's directory must appear (not a stale copy of the image's); switch
  back and confirm the image's directory returns likewise
* Read directory: `LOAD"$",8` then `LIST` returns the real disk's directory
* Load a program: `LOAD"<name>",8` (and `,8,1`) loads and runs a program off
  the physical disk
* Record-not-found: reading a file or sector that is not present, or a track
  the head cannot find, fails cleanly with a DOS error instead of hanging, and
  the drive recovers for the next access
* Disk-change and write-protect sensing: ejecting and re-inserting a disk is
  noticed (the next access reads the new disk, not a stale one) and a
  write-protected disk is reported as protected; confirm the assumed pin
  polarities on R3 (see the change_o / write-protect NOTEs in
  physical_1581_inputs.vhd)
* QNICE `0x0108` diagnostic device: follow doc/1581_dd_debug_device.md to read
  the register bank from the QNICE monitor - SIGNATURE reads `0x1581`, the index
  period settles near one revolution while the motor is on, CNT_READOP climbs on
  each load and LAST_RESULT is `0x0000` after a clean read; use CNT_RNF,
  CNT_CRCERR, GAP_MIN and GAP_MAX to triage any read trouble
* Image-mode regression, MUST be unaffected: with "Use internal 1581" OFF, the
  existing `*.d64` (1541) and `*.d81` (1581) disk-image mount / directory / load
  / write / flush / power-cycle behaviour is exactly as before - the physical
  path must be completely transparent when it is not selected. Automated gate:
  `CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_image.sv` holds
  `phys_mode=0`, locks shared WD register behavior to early reference commit
  `88c09d2`, and reads all ten directory-track sectors in ROM order through the
  real image/SD buffer crossing. Reference and fixed transcripts must match;
  the `b2bd629`/unfixed-HEAD negative control must fail the image readback check
* Idle-gate (symmetric): toggling "Use internal 1581" is ignored in BOTH
  directions while drive 8 is busy - switching to image mode is blocked while
  the physical drive reads/steps/spins, and switching to the internal drive is
  blocked while the image drive is active or its write cache is still being
  flushed (yellow drive led); once the drive is quiet the toggle works again
* Not expected to work yet (this is the read-only milestone): writing, saving,
  scratch/rename and formatting to the internal drive - these are the next
  milestone

Version 6.0 - TBD
-----------------

@TODO: Test the new multi-level on-screen-menu (#189, M2M V2.1.0 nested
submenus, see doc/path-to-OSM-submenus.md section 10 for the full plan).
Before any hardware test, run the headless regression suite, which must
pass: `python3 M2M/rom/tests/menu_test.py run` (builder equivalence vs. the old
parser, structure/validation fixtures, scripted navigation of the whole V6
menu in the QNICE emulator) and `python3 M2M/rom/tests/menu_test.py verify`
(config.vhd/mega65.vhd indices vs. the golden model). On hardware:

* Navigate main menu -> Advanced Settings -> OSM Scaling and back twice:
  leaving lands the cursor on " OSM: %s" and then on " Advanced Settings"
* Run/Stop pops exactly one level from a sub-submenu (OSM Scaling /
  VIC-II / HDMI Filter), pops to the main menu from a depth-1 submenu and
  closes the OSM at the main menu
* Close the OSM with Help while inside the VIC-II sub-submenu, reopen:
  still inside that sub-submenu, cursor preserved
* Mount a disk image, write to it, then enter a sub-submenu while
  `<Saving>` shows: the background redraw keeps level and cursor
* All %s summaries show the selected item of their own submenu at every
  level, including both " HDMI: %s" headings (display mode vs. filter)
* All pre-V6 features still react: every entry of Expansion Port, HDMI
  display modes/flicker-free/DVI/filter/zoom, VGA modes, SID settings,
  IEC, Kernal selection, OSM scaling, CIA model, flip joystick, REU,
  improve audio, PRG/CRT/D64 loading (the new Model/Turbo/Volume/RTC/
  VIC-II/NTSC entries are intentionally silent placeholders)
* Settings save/restore across a power cycle with the new 170-byte
  config file `/c64/c64mega65-<CORE_VERSION>.cfg` (re-generate it with
  M2M/tools/make_config.sh)
* Provoke each authoring fatal once in a scratch config.vhd: unbalanced
  brackets (boot fatal with item index), OPTM_G_START inside a submenu
  (boot fatal), oversized submenu view (serial-console warning only)

@TODO: Test the new smart dependencies (#229, M2M V2.1.0 OPTM_DEP, see
doc/path-to-OSM-dependencies.md section 8). The headless suite already covers
the algorithms: `python3 M2M/rom/tests/menu_test.py run` includes the
optm_deps_test testbed (resolution, the five boot fatals, the OPTM_DEP_OK
predicate via the builder and the %s walk) and a dependency navigation
scenario, and `python3 M2M/rom/tests/menu_test.py mutate` proves every
dependency code path is covered (it must report "ALL ... MUTANTS KILLED").
`verify` checks the OPTM_DEP() tags in config.vhd against the model and, when
ghdl is installed, drives the real config.vhd SEL_OPTM_DEPS decoder and checks
its raw output against the model (also available standalone as
`menu_test.py ghdl`). On hardware (the V6 menu wires PAL/NTSC in the Model
submenu as the mother of the HDMI display-mode and flicker-free lines):

* Open the HDMI submenu with PAL selected: only the three PAL display modes
  (16:9/4:3/5:4 50 Hz) and the PAL flicker-free + Raw 50.1 Hz lines show;
  the " HDMI: %s" heading summarizes the selected PAL mode
* Switch to NTSC in the Model submenu, reopen HDMI: now only the three NTSC
  modes (59.94 Hz) and the NTSC flicker-free line show, Raw 50.1 Hz is gone,
  and the heading summarizes the selected NTSC mode
* The menu reflows immediately when the mother changes in a shared view and
  the cursor never lands on a hidden line
* Per-mode memory: a PAL HDMI choice and an NTSC HDMI choice are each
  remembered across PAL<->NTSC switches and across a power cycle (the hidden
  lines keep their config-file byte)
* On the serial console the boot log reports "Smart dependencies (OPTM_DEP):
  ON"; an unmodified other-core config.vhd reports "OFF" and behaves as before
* Provoke each dependency fatal once in a scratch config.vhd: a missing
  mother group, an out-of-range item index, a mixed group, a dependency
  chain and a dependency on a submenu/mount/load/help/start line

Known automated-coverage gaps (adversarial review, June 2026; all inspected
and found correct on the shipped V6 config, but worth a manual eye until a
harness exists): the production boot wiring `HELP_MENU` / `HELP_MENU_INIT`
(heap accounting, the SEL_OPTM_DEPS feature probe, the special-line array the
boot validator is fed, and the error-class to ERR_F_DEP* mapping) is exercised
by no automated testbed - confirm on the serial console that the OSM opens,
the deps log line is correct, and a deliberately broken dependency boot-fatals
with a sensible message. Also note `FATAL` omits the numeric "Error code"
when the offending item is flat index 0 (shared with the pre-existing
ERR_F_MENUSUB / ERR_F_MENUSTRT2 fatals); the message string still identifies
the error class.

@TODO: Update the "Test HDMI modes" sub-checklist. The single "CRT emulation"
toggle from earlier versions has been replaced by an "HDMI: %s" submenu with
six filter pairs (Sharp / Smooth / Lanczos / Scanlines / CRT (S-Video) /
CRT (Composite)); the default selection is "Scanlines", which loads the same
coefficient pair (lanczos2_12 + Scan_Br_110_80) as the V5 CRT emulation, so
existing users see no visual change on upgrade. The V6 HDMI test block
should at minimum:

* Cycle through all six filter options and confirm each renders without
  artifacts on the C64 boot screen and on a known dithered scene (e.g.
  the [demos](demos.md) shadebobs)
* Confirm the default selection is "Scanlines" on first boot (empty or
  missing SD config file)
* Confirm the saved selection persists across power cycles
* Confirm changing the filter at runtime does NOT reset the C64 (the
  running program keeps going; only the picture changes from the next
  frame)
* Confirm that switching to "Sharp" eliminates the uneven-column-width
  artefact reported in issue #223
* Verify the "HDMI: %s" header line correctly reflects the current
  selection (e.g. " HDMI: Sharp", " HDMI: CRT (Composite)") and that
  the longest label fits inside the menu frame without ellipsis

@TODO: Confirm `M2M$LOAD_POLYPHASE` (new V2.1 framework helper in
`M2M/rom/tools.asm`) plays nicely with `LOAD_ASCAL_FLT` for cores that do
NOT override the polyphase loader: those should still get the V1
Lanczos2_12 + Scan_Br_110_80 default at boot, bit-identical to V2.0.

@TODO: D81 / simulated 1581 drive (see doc/path-to-d81.md). The Shell logic
was validated headlessly in the QNICE emulator (D64/D81 size detection, the
.D64/.D81 browser filter, the .crt pool-boundary guard) and the new HyperRAM
mount-buffer VHDL was elaborated with ghdl, but the 1581 RTL and the HyperRAM
buffer relocation MUST be exercised on hardware on all four board revisions:

* Regression FIRST, with NO D81 mounted: D64 mount / run / write / flush /
  power-cycle still works through the new HyperRAM mount buffer (the 1581
  engine is permanently reset and the IEC AND-wiring must be transparent).
  A/B against the previous BRAM-buffer behaviour.
* Mount a D81 (exactly 819,200 bytes), `LOAD"$",8`, load and run a program
* Write to a D81, wait for the drive LED to settle, power-cycle, verify the
  written data persisted (create a `Disk-Write-Test.d81` counterpart to the
  existing D64 asset)
* Wrong-size D81 (e.g. 822,400-byte error-info variant) is rejected with the
  updated message; a 0-byte / tiny file is rejected
* GEOS boot from D81 + work disk via CONFIGURE (highest-value real-world test)
* 1581 partition / sub-directory commands work (handled inside the image)
* JiffyDOS active on C64 + 1541 with a STOCK 1581 (no jd-c1581.bin): mixed
  JD/stock on the IEC bus works (graceful degradation)
* JiffyDOS-1581: with jd-c1581.bin present, the 1581 also uses JiffyDOS;
  toggling "JiffyDOS" in the Kernal submenu flips all three ROMs
* fdc1772 SD clock-domain-crossing: soak on R3 (worst HyperRAM contention)
  with HDMI flicker-free + REU + a `.crt` active while reading/writing the D81
* Oversized `.crt` (> 2,842,624 bytes) is rejected (the SIMCRT pool shrank to
  make room for the D81 buffer)
* Flush duration on a D81 is ~4.7x a D64 (819,200 vs 196,608 bytes); confirm a
  GEOS-style periodically-writing program still completes a flush

@TODO: Test per-drive JiffyDOS, i.e. the 1541 JiffyDOS ROM is now optional too
(#91). Headless FIRST, both must pass: `python3 M2M/rom/tests/jiffy_test.py`
(asserts the boot gate decision, the debug-console status report and the
on-screen Kernal summary for every decision-table row) and
`python3 M2M/rom/tests/menu_test.py verify` (the new C_MENU_KERNAL=101 opener
index). On hardware, with Kernal = JiffyDOS selected:

* Dead-1541 canary: with `jd-c64.bin` + `jd-c1581.bin` but NO `jd-c1541.bin`,
  mount a `.d64` -> a WORKING standard-speed 1541 (not a dead all-`$00` drive),
  and the 1581 runs JiffyDOS for a `.d81` (the case the old boot gate forbade)
* With `jd-c64.bin` + `jd-c1541.bin` but NO `jd-c1581.bin`: 1541 runs JiffyDOS,
  1581 runs stock (the unchanged 1581-optional path)
* With `jd-c64.bin` only (neither drive ROM): boot reverts the live Kernal to
  Standard; the debug console prints "disabled (no drive ROM)"
* With `jd-c1541.bin` present, the 1541 still runs fast JiffyDOS (no
  regression); Standard / Games System / Japanese unchanged in every combination
* The main-menu "Kernal" line reads back the installed drive ROMs as
  "JiffyDOS 1541", "JiffyDOS 1581" or "Jiffy 1541+1581" (24 columns, fits the
  menu width); no JiffyDOS is advertised while `jd-c64.bin` is absent
* Config-orphan awareness: finalizing CORE_VERSION renames the config file, so
  saved settings reset to Standard -- re-select JiffyDOS once (not a gate bug)
* Transient missing `jd-c64.bin`: the live revert is session-only, so a later
  normal boot with the file present restores the saved JiffyDOS choice

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
