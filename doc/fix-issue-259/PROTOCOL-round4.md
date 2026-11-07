# REU 1764 tests, round 4 (for Joe3f00ff)

Hi Joe, thank you for round 3 and for the stopwatch, that number turned out to be the key to the Bit Fill mystery. What your results told us, in short:

- `9-VALUES` is the decisive one: a verify of `$FF` bytes never faults, every other value faults exactly as often as the VIC-II interrupts it, on Alpha 23 and Alpha 24 alike. So whenever the VIC-II pauses a verify, the REU compares its byte against `$FF`, which is what the MEGA65's cartridge port lines read when nobody drives them (every line has a pull-up resistor).
- `10-AFTER` shows the data in the REU is intact after every fault, and `12-POSITION` shows the fault is always on the first byte after the pause begins. So nothing is lost or damaged; the REU simply judges one byte against an empty bus.
- Alpha 24 handed the REU that byte in the first cycle of the pause and nothing changed. That means the REU keeps reading during the *second and third* cycle of the pause as well, exactly the three cycles in which a real C64 still answers the bus (the VIC-II only takes it over in the fourth). Alpha 24X1 now serves all three cycles.
- Bit Fill: it does fault, in the very first verify of every pattern except `(ff)`. The CMD machine code returns 1 in `SB` and the modified BASIC loop (the one without the error stop) carries on without looking at it. Only the `(ff)` pattern runs all of its 32 transfers, and `$FF` cannot fault on this machine. That is why the line takes about 6 seconds: 15 patterns stop after about 0.1 s each and `(ff)` alone takes the remaining 4 seconds. If you add `:PRINTPEEK(SB);` right after the `SYS ML+15` in your Bit Fill line, it should print `1` for `(00)` to `(ee)` and `0` for `(ff)` on Alpha 24, and `0` sixteen times on Alpha 24X1.

**Disk:** `reu-tests4.d64` (attached) holds two new programs; the round-2 and round-3 disks are needed again as well. Simulated REU **off**, display mode as usual. `LOAD"name",8` and `RUN`, nothing else.

**Part A, still on Alpha 24** (one program, two minutes): `14-FFFF`. It runs verifies with the screen on while the KERNAL ROM is switched off and a chosen byte sits at address `$FFFF`. If the REU reads an empty data bus, the result depends only on the data (`255` passes, `0` faults); if the address bus is empty instead, the result depends on whether the data equals the byte at `$FFFF`. Please photograph the four result lines. On Alpha 24X1 this program should report zero faults in all four lines.

**Part B, on Alpha 24X1** (attached as `C64MEGA65-WIP-V6-A24X1.zip`), please run and photograph the final screen of each:

1. `3-VERIFY` (round-2 disk): expected zero faults in all five lines.
2. `9-VALUES` (round-3 disk): expected `0 FAULTS IN 50` for all eight values.
3. `12-POSITION` (round-3 disk): expected that the line-50 screen now looks like the line-52 screen, i.e. every run `80 255 1`, the cycle count about 43 higher than at line 52 (the pause itself, during which the REU now simply waits), `END` 55 instead of 56.
4. `11-BITFILL` (round-3 disk): expected `R 0 C 0` for variations 0 to 7 and `R 4 C 0` for 8 and 9 (the planted byte must still be found; the fixed-C64 verifies must not fault any more, with the screen on or off).
5. `13-SWAPCHK` (round-4 disk, about four minutes, most of it BASIC checking 16 KB byte by byte): expected `wrong bytes: 0` in all three summary lines. This is the first test that checks swaps with the screen on byte by byte; the earlier swap tests could only report the verify fault.
6. `14-FFFF` (round-4 disk): expected zero faults in all four lines.
7. `1-FETCH` and `2-STASH` (round-2 disk): regression, expected `0 BAD BYTES` as on Alpha 23.
8. The patched CMD REUTEST with the screen on: expected OK in every step, including `Block/Page Addressing`, `Byte Addressing`, `Address Control` and `CBR Refresh Integrity`. With the stopwatch, the Bit Fill line should now take about 64 seconds (all 16 patterns run completely), and with the `PRINTPEEK(SB);` addition it should print `0` sixteen times.

If any of these still faults, the photos of `14-FFFF` (Part A and Part B) and `12-POSITION` tell us where to look next. If something hangs, RUN/STOP+RESTORE or reset; nothing is written to the SD card.

Thanks a lot!
