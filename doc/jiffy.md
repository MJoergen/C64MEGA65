Using JiffyDOS
==============

The advantage of JiffyDOS is that you can load files from the simulated
1541 disk drive (`*.d64` files) significantly faster. It also works with real
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

You need to buy and download two ROM images, one for the C64 and one for the
1541. While both shops use the same name for the C64 ROM image, the name for
the 1541 ROM image differs:

* C64 ROM image: **JiffyDOS 64 KERNAL ROM Overlay Image**

* 1541 ROM image at Restore-Store: **JiffyDOS 1541 DOS ROM Overlay Image**

* 1541 ROM image at RETRO Innovations: **JiffyDOS 1541/1541C/1541II DOS ROM Overlay Image**

Make sure you double-check the name of what you buy, otherwise you might
end up with a ROM variant that is not supported by the C64 core.

The download packages are ZIP archives. Unpack them. For performing the next
steps, you only need the `*.bin` files.

Prepare the files
-----------------

The C64 for MEGA65 core needs two files to run JiffyDOS and each of them needs
to be exactly `16 kB = 16,384 bytes` in size. One file is the C64 Kernal ROM
`jd-c64.bin` and one file is the 1541 DOS ROM `jd-c1541.bin`. Perform the
following steps to create these files from the `*.bin` files you purchased.

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

### C1541 DOS ROM: `jd-c1541.bin`

The JiffyDOS download package contains two `*.bin` files. Take the one that
is exactly `16 kB = 16,384 bytes` in size and rename it to `jd-c1541.bin`.

Install and use JiffyDOS
------------------------

* Make sure the core is not started (for example: switch off the MEGA65)

* Make sure you have a `/c64` folder on the SD card that is active, when the
  C64 for MEGA65 core boots. Remember, that the SD card slot on the back of
  the MEGA65 takes precedence over the SD card slot at the bottom.

* Copy `jd-c64.bin` and `jd-c1541.bin` to the `/c64` folder of your SD card.

* Start the core with the updated SD card

* Select "JiffyDOS" in the "Kernal" submenu of the core's menu

* If you want the core to remember that you seleced JiffyDOS next time
  you start the MEGA65, make sure that you that you also have the
  [config file](https://github.com/MJoergen/C64MEGA65/blob/master/README.md#config-file)
  installed in your `/c64` folder. Starting with Version 6, this file's
  name includes the core version (for example `c64mega65-V6`); use whatever
  file came with your release ZIP.
