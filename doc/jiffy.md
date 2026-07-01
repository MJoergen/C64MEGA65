Using JiffyDOS
==============

The advantage of JiffyDOS is that you can load files from the simulated
1541 disk drive (`*.d64` files) and the simulated 1581 disk drive (`*.d81`
files) significantly faster. It also works with real
hardware disk drives that you attach via the MEGA65's IEC port as long as you
have installed the JiffyDOS ROM on those drives, too.

Learn more about JiffyDOS in the
[C64 Wiki](https://www.c64-wiki.com/wiki/JiffyDOS).
You will also find download links to the user's manual there.
If you want to learn more about JiffyDOS distribution channels and
about licensing information then
[read this article on go4retro.com](https://www.go4retro.com/products/jiffydos/).

Where and what to buy
---------------------

JiffyDOS is commercial software. We recommend, that you either buy from
[Restore-Store (click here)](https://restore-store.de/89-jiffydos)
or from
[RETRO Innovations (click here)](http://store.go4retro.com/search.php?search_query=JiffyDOS&x=0&y=0).

You need to buy and download the C64 ROM image plus at least one drive ROM
image. The C64 image is required; the 1541 and the 1581 drive images are each
optional, but you need at least one of them. Buy the drive image (or images) for
whichever simulated drive you want to accelerate: the 1541, the 1581, or both.
While both shops use the same name for the C64 ROM image, the names for the
drive ROM images differ:

* C64 ROM image: **JiffyDOS 64 KERNAL ROM Overlay Image**

* 1541 ROM image at Restore-Store: **JiffyDOS 1541 DOS ROM Overlay Image**

* 1541 ROM image at RETRO Innovations: **JiffyDOS 1541/1541C/1541II DOS ROM Overlay Image**

* 1581 ROM image (optional): **JiffyDOS 1581 DOS ROM Overlay Image**

Make sure you double-check the name of what you buy, otherwise you might
end up with a ROM variant that is not supported by the C64 core.

The download packages are ZIP archives. Unpack them. For performing the next
steps, you only need the `*.bin` files.

Prepare the files
-----------------

To run JiffyDOS, the C64 for MEGA65 core always needs the C64 Kernal ROM
`jd-c64.bin`, which is exactly `16 kB = 16,384 bytes` in size. In addition you
need at least one drive ROM: the 1541 DOS ROM `jd-c1541.bin` (also exactly
`16 kB = 16,384 bytes`) and/or the 1581 DOS ROM `jd-c1581.bin` (exactly
`32 kB = 32,768 bytes`). Each drive ROM is optional on its own, so you can run
JiffyDOS on the 1541, on the 1581, or on both, depending on which drive ROMs you
provide. If you install `jd-c64.bin` but neither drive ROM, JiffyDOS stays
disabled and the core falls back to the standard Kernal. Perform the following
steps to create these files from the `*.bin` files you purchased.

### C64 Kernal ROM: `jd-c64.bin`

1. Download the C64 BASIC ROM [`basic.901226-01.bin` from zimmers.net](http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/basic.901226-01.bin)
2. Concatenate the C64 BASIC ROM with JiffyDOS: First the BASIC and then
   JiffyDOS
3. Make sure that the resulting file is called `jd-c64.bin`

#### Example for the macOS and Linux terminal

The following commands assume that you are in a folder that is empty with the
exception of one file that is called `JiffyDOS_C64_6.01.bin`.

```bash
wget http://www.zimmers.net/anonftp/pub/cbm/firmware/computers/c64/basic.901226-01.bin
cat basic.901226-01.bin JiffyDOS_C64_6.01.bin > jd-c64.bin
```

#### Example for the Windows command prompt

The following command assumes that you are in a folder that contains the
following two files: `JiffyDOS_C64_6.01.bin` and `basic.901226-01.bin`.

```cmd
copy /b basic.901226-01.bin+JiffyDOS_C64_6.01.bin jd-c64.bin
```

Hint: Do not omit the `/b` (for binary) in the copy command above.

### C1541 DOS ROM: `jd-c1541.bin` (optional)

The JiffyDOS download package contains two `*.bin` files. Take the one that
is exactly `16 kB = 16,384 bytes` in size and rename it to `jd-c1541.bin`.

### C1581 DOS ROM: `jd-c1581.bin` (optional)

The 1581 JiffyDOS download package contains a single ROM image that is exactly
`32 kB = 32,768 bytes` in size. Unlike `jd-c64.bin`, there is no concatenation
step: just rename that file to `jd-c1581.bin`. Make sure the size is exactly
32,768 bytes, otherwise the image will be loaded incorrectly.

You do not have to provide every file. Each simulated drive uses JiffyDOS only
if you installed its drive ROM, and otherwise keeps its standard DOS: with
`jd-c64.bin` plus `jd-c1541.bin` you get JiffyDOS on the C64 and the 1541; with
`jd-c64.bin` plus `jd-c1581.bin` you get JiffyDOS on the C64 and the 1581; with
all three you get JiffyDOS everywhere. Mixing JiffyDOS and standard DOS on the
IEC bus works without problems.

This describes the **simulated** drives. A **real** disk drive that you attach
to the MEGA65 IEC port runs JiffyDOS only if a JiffyDOS ROM is installed in that
physical drive, which is independent of the `jd-*.bin` files on the SD card.

Install and use JiffyDOS
------------------------

* Make sure the core is not started (for example: switch off the MEGA65)

* Make sure you have a `/c64` folder on the SD card that is active, when the
  C64 for MEGA65 core boots. Remember, that the SD card slot on the back of
  the MEGA65 takes precedence over the SD card slot at the bottom.

* Copy `jd-c64.bin` and at least one drive ROM (`jd-c1541.bin` and/or
  `jd-c1581.bin`) to the `/c64` folder of your SD card.

* Start the core with the updated SD card

* Select "JiffyDOS" in the "Kernal" submenu of the core's menu

* The "Kernal" line in the main menu then shows which JiffyDOS drive ROMs are
  installed, for example `Kernal: JiffyDOS 1581`, `Kernal: JiffyDOS 1541` or
  `Kernal: Jiffy 1541+1581` when both drive ROMs are present. This reflects the
  ROM files you installed, not which simulated drive is currently mounted.

* If you want the core to remember that you seleced JiffyDOS next time
  you start the MEGA65, make sure that you that you also have the
  [config file](https://github.com/MJoergen/C64MEGA65/blob/master/README.md#config-file)
  installed in your `/c64` folder. Starting with Version 6, this file's
  name includes the core version (for example `c64mega65-V6`); use whatever
  file came with your release ZIP.
