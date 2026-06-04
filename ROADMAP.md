Roadmap
=======

We are planning to improve this core steadily. The MiSTer core offers some
more features than our current release of the "C64 for MEGA65". Here is a
list of features (in no particular order) that we are planning to deliver
at a later stage:

Feature Roadmap
---------------

* NTSC
* Turbo mode for games such as Zeropaige's Super Mario Bros
* Support two simulated drives: 8 and 9
* Offer an SD2IEC compatible IEC device that browses the SD card and that
  you can for example use to flash the EF1CR cartridge without the need of
  splitting large CRTs into multiple D64 disks using EasySplit
* Use the MEGA65's built-in disk drive as a C1581
* Simulated C1581 via `*.d81` disk images
* GCR encoded disk images (`*.g64`)
* Improved C1541 compatibility due to real internal GCR handling of `*.d64`
  images instead of simulated handling leads to games like "Seven Cities of
  Gold" being able to format/create their non-standard game disks. Also highly
  sophisticated bit nibblers such as the one offered in some freezer cartridges
  will work as soon as we have implemented this.
* Existing C1541 disk images (`*.d64`) can now be formatted
* Support `*.d64` images with error maps (filesizes 175,531 and 197,376)
* Simulated tape drive using `*.t64` tape images
* Sync on Green (RGsB) retro output mode via VGA
* You can use the Amiga mouse as a C64 mouse
* Support autoswap via `*.lst` files
* Support the creation of empty disk images
* Support the creation of empty config files on the SD card so users do not
  need to copy a pre-made config file from the release ZIP.
* Parallel C1541 port for faster (~20x) loading time using DolphinDOS
* Utilize full 16:9 screen real estate for file- and directory browsing and
  core configuration on HDMI while saving screen real estate on 4:3 VGA
* More sophisticated scalers and scandoublers 
* Simulate the blending of colours when ALM and DCM are used
  as described here: https://github.com/MiSTer-devel/C64_MiSTer/issues/104
* Support typing the first letter(s) of files to quickly jump to files
  and folders within the filebrowser: https://github.com/MJoergen/C64MEGA65/issues/14

Technical Roadmap
-----------------

To implement some of the above-mentioned features and also to improve the
robustness, performance, and stability of the whole system, we will need
to implement certain technical improvements in the "backend", again in no
particular order:

* Research MiSTer's SID improvements from November 16 (and newer)
* Maximize compatibility of C1541 by implementing MiSTer's raw GCR mode
  which exclusively uses GCR internally (c1541_direct_gcr.sv instead of
  c1541_gcr.sv). `*.D64` images are converted to/from GCR when reading/writing
  from SD card.
* Clarify: Line 65 in fdc1772.v: back to 2 or work with generic?
* Implement a remote-control mechanism via Serial/JTAG (similar to what
  already works on the MEGA65 core) that allows us to remote-control the
  C64 core so that we can for example run whole test suites remotely.
  If possible we should think about implementing this feature on the
  MiSTer2MEGA65 framework level so that all cores can benefit.
* Add the Vice test suite to our repertoire of tests and use the
  above-mentioned mechanism to execute on it:
  https://sourceforge.net/p/vice-emu/code/HEAD/tree/testprogs/testbench/ 
* Enhance QNICE's FAT32 stack so that it is able to create new files
* Fix visible tearing in Bromance demo (vertical scroll effect), but only,
  when HDMI Zoom is ON: https://csdb.dk/release/?id=205526
* Research if an update to the newest ASCAL version makes sense and if so
  so the update (wait until MiSTer does the same upstream)
* Re-do QNICE's SD Card controller: Go from SPI to native
* Hardware debugger (single-step the CPU via the on-screen-menu)

Roadmap Items on GitHub
-----------------------

* [List of known bugs](https://github.com/MJoergen/C64MEGA65/issues?q=is%3Aopen+is%3Aissue+label%3Abug)
* [Feature requests](https://github.com/MJoergen/C64MEGA65/issues?q=is%3Aopen+is%3Aissue+label%3Aenhancement)
