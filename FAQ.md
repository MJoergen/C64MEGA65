# FAQ - Frequently Asked Questions

Please head to: https://c64.mega65.org/faq-and-other-stuff.html 

## 1) Which core should I install? I am confused what R3/R3A/R4/R5/R6 means

Please head to: https://cores.mega65.org/mega65-revisions-and-cores.html

And then read some specifics about the C64 core:
https://c64.mega65.org/installation.html#differences-between-mega65-revisions

## 2) My MEGA65 or the C64 core is behaving somehow weirdly

If you own a MEGA65 that was built in 2024 or later, then you can skip this
section as the underlying hardware bug that haunts older boards is fixed.

**The "HDMI back powering problem" is the root of all evil!**

Please head to: https://c64.mega65.org/faq-and-other-stuff.html#unexplainable-general-weird-behaviour

## 3) The keyboard is not working

Please head to: https://c64.mega65.org/faq-and-other-stuff.html#the-keyboard-is-not-working

## 4) SD card errors

Please head to: Please head to: https://c64.mega65.org/faq-and-other-stuff.html#important-information-about-micro-sd-cards

### Formatting SD cards on a Mac

* Mac OS' GUI tools try to be "smart". Do not use them, as you cannot
  control, if the tool creates FAT16 or FAT32. Use the command line
  version of `diskutil` instead:

  `sudo diskutil eraseDisk FAT32 <name> MBRFormat /dev/<devicename>`

  Find out `<devicename>` using `diskutil list`. `<name>` can be chosen
  arbitrarily.

* If you prefer a visual/GUI tool, then use the formatting tool that the
  official SD card organization provides:
  [Download it here](https://www.sdcard.org/downloads/formatter/sd-memory-card-formatter-for-mac-download/).

## 5) How compatible is the C64 core?

It is very compatible. Not yet as good as Vice but the
core runs hundreds of
[demanding demos flawlessly](tests/demos.md),
plays thousands of games without a single glitch, including games that need
a REU such as
[Sonic the Hedgehog](https://csdb.dk/release/?id=212523)
and the core offers disk writing abilities for the simulated 1541, so
that you can save your game states or your work in GEOS. The core also
let's you use original Commodore
[hardware cartridges](https://c64.mega65.org/c64-cartridges.html) plugged into the MEGA65
Expansion Port,
[simulate cartridges using CRT files](https://c64.mega65.org/c64-cartridges.html#specific-virtual-cartridge-compatibility) and
[use retro Commodore peripherals](https://c64.mega65.org/working-with-disks-and-drives.html#connecting-an-external-drive)
by plugging them into the MEGA65's IEC port. You can even
[work with retro 15 kHz cathode ray tube monitors](https://c64.mega65.org/hdmi-and-analog-output.html#retro-15-khz-for-cathode-ray-tubes).

## 6) I cannot format a disk image (`*.d64`)

Indeed, the core is not yet able to format disks. We do have this topic on our
[roadmap](ROADMAP.md). What we suggest is that you use tools like the awesome
[DirMaster](https://style64.org/dirmaster) to create a bunch of formatted, empty
`*.d64` disk images and then use these disk images with your C64 for MEGA65 core.

## 7) The screen goes black when I choose JiffyDOS

JiffyDOS is commercial software. The C64 core does not come with
a pre-installed copy of JiffyDOS.
[Learn here](https://c64.mega65.org/C64MEGA65DOCS/jiffydos-and-alternative-kernals.html)
where to buy and how to install it.

## 8) My game or demo crashes

Head to https://c64.mega65.org/faq-and-other-stuff.html#loading-and-running-games
and then scroll down to "A game or demo does not run correctly".

## 9) No image or no sound via HDMI

1. Make sure you are running [Version 6](https://files.mega65.org?id=896a012f-59e4-456c-b91f-7e989b958241)
   of the core.

2. Try everything that is described
   [here](https://c64.mega65.org/hdmi-and-analog-output#hdmi-troubleshooting).

3. [Create an issue](https://github.com/MJoergen/C64MEGA65/issues/new/choose)
   here on the official C64MEGA65 GitHub repository or post your problem in the
   [#c64-core](https://discord.com/channels/719326990221574164/794775503818588200)
   channel on Discord.

## 10) The VGA output looks strange or flickers or I lose VGA sync

Always try the "auto-adjust" (or similarly named feature) of your screen
first. This resolves 90% of all issues.

It is highly recommended to switch off
[HDMI: Flicker-free](https://c64.mega65.org/hdmi-and-analog-output.html#the-hdmi-flicker-free-option)
when using analog VGA monitors or monitors that work with the
[retro 15 kHZ RGB over VGA" signal](https://c64.mega65.org/hdmi-and-analog-output.html#retro-15-khz-for-cathode-ray-tubes).

Otherwise you might encounter strange visual effects that range from a blurry
image over "underwater" blurry movement of your screen to sporadic flickers
and sometimes to a complete loss of VGA sync every few seconds or minutes.

If your monitor supports it, try to use the [retro "15 kHz RGB" mode](https://c64.mega65.org/hdmi-and-analog-output.html#retro-15-khz-for-cathode-ray-tubes).

## 11) My retro monitor does not work with the core

### Analog devices

There is a [dedicated documentation](https://c64.mega65.org/hdmi-and-analog-output.html#retro-15-khz-for-cathode-ray-tubes) that explains you how to
connect retro displays with cathode ray tubes to the MEGA65 using the Commodore 64
for MEGA65 core.

### LCD or TFT devices

Make sure that you have 
[switched-off HDMI: Flicker-free](https://kugelblitz360.github.io/C64MEGA65DOCS/hdmi-and-analog-output.html#the-hdmi-flicker-free-option)
when using retro monitors via the MEGA65's VGA out.

## 12) My mouse does not work

Make sure that you use either a real C64 mouse or
[MouSTer](https://retrohax.net/shop/modulesandparts/mouster/).

The
[C64 mouse "1351"](https://www.c64-wiki.com/wiki/Mouse_1351)
is clearly superior to the C64 mouse "1350" as the latter one does not feature
proportional movements and therefore does not feel right, for example when you
use GEOS.

Caution: AMIGA mice look pretty much like C64 mice but the C64 core does not
support AMIGA mice, yet. The MEGA65 core does support AMIGA mice and this
feature is on our roadmap.

## 13) Can I use cartridges?

Yes, head to https://c64.mega65.org/c64-cartridges.html to learn more.

### Do not do a "hard-reset" when working with cartridges

If you are not sure what the difference between a "hard-reset" (aka
"long-reset") and a "soft-reset" (aka "short-reset") is, then
[please read here](https://c64.mega65.org/resetting-the-core.html).
You will recognize a hard-reset when the power LED of the MEGA65 turns blue.

Do not use hard-reset reset for any hardware cartridge. Instead always use the
soft-reset. Otherwise you will experience very odd behavior.

This is by design: We are masking the "CBM80" signature on "hard-reset". In the
previous core versions (before Version 5.1), there was a bug in our hard-reset
implementation that prevented you from leaving games like Uridium or Eagles
Nest via hard-reset. Now, from Version 5.1 on, hard-reset is fixed that means
each cartridge that relies on the "CBM80" signature will not work properly when
you use hard-reset. Not all cartridges rely on this signature. Learn more
about this signature by
[reading this article](http://tech.guitarsite.de/cbm80.html) and learn more
about how we implemented the hard-reset by
[reading this German C64 Wiki article](https://www.c64-wiki.de/wiki/Reset-Taster ).

### If only very few cartridges are working, you need to update CORE #0

This section is only relevant for machines that have been built before 2024.

If only some original retro cartridges are working but the vast majority
of modern cartridges are not working then it is very likely that you need
a so called "CORE #0 update" or that you need to use a slightly scary,
yet kind-of save workaround.

To check if this is the case: Press the <kbd>Help</kbd> key while you
experience the "not working" situation. If the
[well-known C64 for MEGA65 menu](doc/demopics/c64mega65-1.jpg)
is not being shown after you pressed <kbd>Help</kbd>, then instead of the
dedicated C64 core, the standard MEGA65 core is currently running which
is the reason why your hardware cartridge is not working.

You have two options when you own such a MEGA65:

1. [Update CORE #0 as described here](https://mega65.atlassian.net/l/cp/1fkp5zvQ)

2. Manually boot the C64 for MEGA65 core using the <kbd>No Scroll</kbd>
   mechanism and then insert your cartridge **while the MEGA65 is switched on
   and while the C64 core is running** and then press the reset button.
   While we cannot officially endorse this option - do it at your own risk - 
   the MEGA65's hardware is way more robust than the original C64's hardware
   was, particularly when it comes to the Expansion Port. There are certain
   mechanisms in place that shield the inner guts of the MEGA65 from the
   Expansion Port. A lot of MEGA65 users have used this option for a while
   and until now, no damaged MEGA65 due to this workaround are known.

And if you are interested in the technical details about how your MEGA65
handles the whole multi core functionality during startup, then
[head to this MEGA65 Wiki article](https://mega65.atlassian.net/wiki/spaces/MEGA65/pages/158924822/MEGA65+System+Startup+Flow).

### My hardware freezer or flash cartridge does not work

Head to https://c64.mega65.org/c64-cartridges.html#specific-physical-cartridge-compatibility

### A certain simulated freezer (`*.crt`) does not work

Head to https://c64.mega65.org/c64-cartridges.html#specific-virtual-cartridge-compatibility

[This is a list of known issues](https://github.com/MJoergen/C64MEGA65/issues?q=is%3Aissue+is%3Aopen+simcrt)
when it comes to **simulated** (`*.crt`) freezer cartridges.

### "Homebrew" cartridges: Never insert a barebone PCB

Always make sure that you insert a cartridge that is
[housed in a proper case](https://kugelblitz360.github.io/C64MEGA65DOCS/c64-cartridges.html#important-safety-tips) and never
insert a barebone PCB into the MEGA65's Expansion Port.

### Rare case: Zeta Wing cartridge is not working (maybe also relevant for other Protovision cartridges)

There is [a very detailed story on Discord](https://discord.com/channels/719326990221574164/794775503818588200/1222651625475149834)
written by AmokPhaze101 which has proven evidence, that his Zeta Wing
cartridge by Protovision had a faulty SN74HC02N chip: Replacing this chip lead
to the cartridge working like a charme.

This chip is rather easy to replace if you know how to solder. You can google
something like `buy SN74HC02N`, the chip is roundabout 1 EUR or $1.

There is no evidence that other Protovision cartridges are affected by this,
but just in case you stumble into a non-working Protovision cartridge and
you are already running a proper MEGA65 CORE #0 version on your machine
(see above), then replacing the SN74HC02N might be your next step.

## 14) Can I use IEC devices?

Yes, you can connect floppy drives (such as the original
1541 and 1581), hard disks, printers, plotters or modern devices such as the
SD2IEC and the Ultimate-II+ to your MEGA65. All CBM-Bus/IEEE-488 bus/IEC Bus
compliant devices are supposed to work.

Make sure you
[activate the IEC port](https://kugelblitz360.github.io/C64MEGA65DOCS/the-main-menu.html#iec-use-hardware-port).

### Avoid device number conflicts

The core uses device number #8 for the built-in simulated 1541 that can
mount `*.d64` files. So you need to ensure that no other drive uses #8 and
that all the device numbers you use are correct.
[Learn more here](https://www.c64-wiki.com/wiki/Device_number) and make
sure you activate the feature using the menu item "IEC: Use hardware port"
if you want to use.

### Switch-off HDMI: Flicker-free

The "HDMI: Flicker-free" mode
[very slightly changes the timing of the C64](https://c64.mega65.org/hdmi-and-analog-output.html#the-hdmi-flicker-free-option).
While this is not a problem most of the time, it does lead to timing problems
with certain games (for example Rainbow Arts games on original 5 1/4"
disks) that are loaded via real 1541 floppys connected via the IEC port
to the MEGA65. Just to make sure that there are no misunderstandings: 
We are talking about real 1541 hardware here. Loading games via `*.d64`
disk images is **not** affected by "HDMI: Flicker-free" and also loading
games via an SD2IEC connected to the IEC port of the MEGA65 is also
not affected.

If you encounter incompatibilities when you load via real devices
connected to the IEC port, then switch-off "HDMI: Flicker-free" mode.

But in this case we would advise you heavily to also use an analog
retro monitor, because with "HDMI: Flicker-free" OFF, the output on HDMI
will be slightly jerky due to the misalignment of the C64's retro
output frequency and the frequencies that modern HDMI monitors are
actually able to display.

## 15) How many files in a folder can the file browser handle?

The file browser can handle about 25,000 characters. If we assume an average
length of a filename (including the file extension) of 40 characters then this
means 25,000 / 40 = 625 files.

You might find
[this bash script](https://github.com/MJoergen/C64MEGA65/blob/master/M2M/tools/mover.sh)
helpful. You can run it inside a folder with a lot of files and afterwards you
have a directory structure `a .. z` and the files are moved there by name,
plus you will have a folder called `0` where all the files that start with
digits are. Don't forget to go to the folder `m` and remove `mover.sh`.

## 16) The core is not remembering my settings

Make sure that you have a `/c64` folder on your SD card and make sure that
you copy the C64MEGA65 config file that came with the
[ZIP file that contains Version 6](https://files.mega65.org?id=896a012f-59e4-456c-b91f-7e989b958241)
to this very folder.

Starting with Version 6, the C64MEGA65 config file's name includes the core
version (for the V6 release it is `c64mega65-V6`; alpha builds use names like
`c64mega65-WIP-V6-A15`, matching the version shown at the top of the welcome
screen). This lets you keep the config files of different core versions side
by side on the same SD card, which is handy when you run the latest release
in one MEGA65 core slot and an alpha version in another. As a side effect,
your menu settings from an older core version (e.g. from Version 5.2's
`c64mega65` file) are not migrated automatically: you copy the new config
file from the
[ZIP file](https://files.mega65.org?id=896a012f-59e4-456c-b91f-7e989b958241)
into `/c64` and reconfigure the menu to your liking. The old, unversioned
`c64mega65` file from previous core versions is no longer used by Version 6
and can be deleted.

Important: Even if you have a C64MEGA65 config file on your SD card: The core
will not save any settings in case you switched between SD cards during a
certain session. Next time you power-on the core, it will resume saving the
settings until you switch between SD cards for the next time.
[Learn more details here](https://c64.mega65.org/installation.html#config-file).

Currently, we cannot automate this manual chore and need to ask users to copy
the C64MEGA65 config file.
[Track our efforts](https://github.com/MJoergen/C64MEGA65/issues/16) to change
this by following
[this GitHub issue](https://github.com/MJoergen/C64MEGA65/issues/16).

## 17) How can I work with GEOS?

GEOS works very well on the MEGA65 using Version 6 of the core. AmokPhaze101 wrote
a great step-by-step documentation:

1. Download GEOS [using this download link](https://github.com/MJoergen/C64MEGA65/raw/master/doc/assets/geos.zip)
2. Work with AmokPhaze101's tutorial: [View and download PDF](https://github.com/MJoergen/C64MEGA65/blob/master/doc/GEOS_WITH_THE_C64_CORE.pdf)
3. Learn how to use the [Real Time Clock](doc/RTC.md)

Read the full docs: https://c64.mega65.org/geos-on-the-mega65-c64-core.html

## 18) What do the two LEDs signal?

The MEGA65 has two LEDs above the keyboard. One is labeled "Power" and one is
labeled "Drive":

* Both leds blinking like ambulance lights: The core has a fatal error.
* Power green: Machine is powered on, core is running.
* Power blue: You pressed the reset button long enough to initiate a so
  called "Hard-reset" [(learn more)](https://c64.mega65.org/resetting-the-core.html).
* Drive off: No access to simulated 1541 drive.
* Drive green: The currently running C64 software is reading from or writing
  to the simulated 1541 drive.
* Drive blinking green: The last read/write operation to the simulated 1541
  drive failed.
* Drive yellow: The C64 core is writing changes made by the simulated 1541
  drive to the disk image file (`*.d64`) on the SD card.
  [Learn more](https://c64.mega65.org/working-with-disks-and-drives.html#led-information-of-disk-status--disk-flush)
  about how this mechanism works.

## 19) Which features are on the roadmap?

[Here](ROADMAP.md) is the roadmap for future versions. Additionally, there are also 
[feature requests](https://github.com/MJoergen/C64MEGA65/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement)
that we might consider for future releases.

## 20) Where can I post and discuss my feature request?

[Engage with us on GitHub](https://github.com/MJoergen/C64MEGA65/issues) or in the
[#c64-core](https://discord.com/channels/719326990221574164/794775503818588200) channel
on Discord to discuss feature requests and the future of the C64 for MEGA65 core.

## 21) Are there cores other than the C64 available or in development?

Yes. Please visit this website, it contains a list of MEGA65 cores that
will be constantly updated:

https://cores.mega65.org

If you are interested in making your own core or in porting cores from other
projects such as MiSTer: The website is also sharing additional information
about how to get started with doing this and about the
[MiSTer2MEGA65 framework](https://github.com/sy2002/MiSTer2MEGA65/wiki).

## 22) I am a total newby and want to learn FPGA development and making or porting cores

If you own a MEGA65, then
[this short article](https://files.mega65.org?ar=898d573b-d30d-4438-8893-09455bd16400)
is a smooth start to FPGA development. It uses some of the tutorials of the
[MiSTer2MEGA65 framework](https://github.com/sy2002/MiSTer2MEGA65/wiki)
and some resources from the web to get you started.

Moreover, the
[Learning Resources for FPGA Development](https://discord.com/channels/719326990221574164/1180179132668203118)
post on Discord is a great place to meet likeminded people and to ask questions.

[Download and read](https://github.com/sy2002/MiSTer2MEGA65/blob/master/doc/wiki/assets/FPGAs_VHDL_First_Steps_v2p3.pdf)
Helen DeBlumont's beginner "FPGAs with VHDL: First Steps" or go deep by working through the textbook
[The Designer's Guide to VHDL](https://picture.iczhiku.com/resource/eetop/sYiEyoAUyiEkPBBb.pdf)
by Peter J. Ashenden.
