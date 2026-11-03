# REU 1764 tests, round 2 (for Joe3f00ff)

Hi Joe, thank you for the A23 runs. They told us something important: the fix in Alpha 23 helps the direction REU-to-C64 (no "err 4" and no `$FF00` error in two runs), but every test that ends with a REU **verify** still fails as soon as the VIC-II interrupts the transfer. We decoded the CMD test program instruction by instruction and found that the one phase that always passes, "Bit Fill", only uses data where every byte is the same, so it cannot see most of the errors the other phases see. To find out what the REU really does at the moment the VIC-II takes the bus, we need measurements that tell us *which* bytes go wrong and *when*, not just OK/error. We wrote seven small BASIC programs for that; they print their own verdicts, so no photos of long listings are needed, only of the final screens.

**Setup for all runs:** Alpha 23 unless stated otherwise; the simulated REU in the core's menu must be **off** (otherwise both REUs answer at `$DF00`); display mode as you normally use it (HDMI 720p is fine). The programs switch the screen off and on themselves, that is intended. Please note the core version on every photo.

**Disk:** `reu-tests.d64` (attached). Mount it, then `LOAD"1-FETCH",8` and `RUN`, and so on for the other six. Each program takes between 30 seconds and 3 minutes. Please photograph the final screen of each one.

1. `1-FETCH` on **A22 and on A23**. It copies 256 bytes from the REU into a buffer that was filled with 255 beforehand, 20 times with the screen on, and prints every byte that is wrong. On A22 we expect lines like `RUN 7 POS 113 GOT 255` (a lost byte); on A23 we expect `OK` on every run.
2. `2-STASH` on A23. The opposite direction: it copies 256 bytes into the REU with the screen on and reads them back with the screen off. Any `POS ... GOT ...` line is a byte that was stored wrongly; the value tells us how.
3. `3-VERIFY` on **A22 and on A23**. Stores known-good data with the screen off, then lets the REU verify it with the screen on, many times, and counts the faults for five kinds of data (256 bytes 0..255, 256 bytes all `$AA`, 4 KB, 64 KB with a fixed C64 address like the CMD refresh test, 16 KB). The 64 KB part takes about one second per verify.
4. `4-LONG` on A23. Reproduces the "CBR Refresh" step of the CMD test with five lengths (256 bytes to 64 KB) and three screen combinations (stash and verify both with screen on, stash off and verify on, stash on and verify off). At the end it checks 12 KB of C64 RAM that no transfer should have touched.
5. `5-SPRITES` on A23. The 64 KB stash+verify with the screen on, five times without sprites and five times with 8 sprites switched on, like the "Bit Fill" step does.
6. `6-IDLE` on A23. Stores 64 KB with the screen off, waits 10 seconds, verifies; the four combinations of screen on/off during the wait and during the verify. Takes about a minute.
7. `7-CHAIN` on A23. 16 KB stash+verify with the screen on, with nothing, a fetch, or a verify in between.

If something hangs, press RUN/STOP+RESTORE or reset; nothing is written to the SD card. When you get hold of the logic analyzer later, we will send a separate capture recipe (signals, trigger, which program to run), that remains the most direct way to see what the REU does in the first microsecond after BA drops.

Thanks a lot!
