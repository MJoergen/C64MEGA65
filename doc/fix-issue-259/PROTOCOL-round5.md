# REU 1764 tests, round 5 (for Joe3f00ff)

Hi Joe, thank you for round 4, and all the best to your family. Your report was more valuable than it probably felt while you were producing it. What it told us:

- **The main fix works.** In your CMD run after the cold start, `Block/Page Addressing`, `Byte Addressing`, `Address Control` and `CBR Refresh Integrity` are all OK with the screen on. Those steps failed in every run with the screen on from Alpha 22 to Alpha 24, and they are exactly what Alpha 24X1 was built for.
- **`13-SWAPCHK` found a real bug of ours.** After a swap, one byte per VIC-II pause arrived in the REU as 255 while the C64 received the correct byte. Your photo even shows why: positions 16 and 247 in run 20 are exactly one VIC-II pause apart. When the pause begins right after the REU has written a byte, the REU reads the next byte and keeps reading it for two more cycles; Alpha 24X1 answered only the first of those three cycles for swaps. Alpha 24X2 answers all three.
- **In most of the other photos the REU did not answer at all.** `12-POSITION` shows it best: the cycle count is 19, so no transfer ever ran, and the registers still hold old values although the program writes them before every run. The CMD test said "REU not found" for the same reason. In that state a test result says nothing about the core. Several of my programs could not tell "no fault" from "nothing happened", which is my mistake and is fixed in this round: every program now prints whether the REU is awake.
- As far as I can see, the change in Alpha 24X1 cannot put the REU into that state (it only acts during a transfer that the VIC-II interrupts, and your REU seems to have been silent from the first program on). So I would like to find out where it comes from: the REU itself (warming up, contacts, power), the way the core starts, or one particular build.

## Three questions (from memory is fine)

1. In round 4, was the REU already silent in the very first program after you had started Alpha 24X1, or did it stop later? And Part A on Alpha 24: was that right after switching on, and did the About screen say Alpha 24? (All seven lines showing 0 is what a silent REU produces.)
2. When the REU was silent: did you try the reset button, or switching off and on again quickly? Did only the long wait help, and roughly how long is "long"?
3. How do you start the C64 core (core menu after power-on, or does the MEGA65 start it directly)? Did anything change in your setup between round 3 and round 4 (REU taken out and put back, another power supply, other devices connected)?

## The disk

`reu-tests5.d64` (attached) holds **everything**; the older disks are not needed any more. Simulated REU **off**, display mode as usual, `LOAD"name",8` and `RUN`.

Every program prints `REU CHECK OK` at its start and at its end. If you ever see `REU CHECK FAILED` followed by some numbers, the REU has stopped answering: that photo is as valuable as a good one, please see "If a check fails" below.

## Part A, on Alpha 24X2 (about 15 minutes)

Please start from a cold start with your long wait and check once in the core's About screen that it says `WIP-V6-A24X2`. Then run these in this order without resetting in between, and photograph the final screen of each:

1. `15-HEALTH` (30 seconds): expected `RESULT: REU AWAKE`, and nine lines that end in `0 0`.
2. `3-VERIFY` (2 minutes): expected `0 FAULTS` in all five lines.
3. `9-VALUES` (1 minute): expected `0 FAULTS IN 50` for all eight values.
4. `12-POSITION` (10 seconds, two screens, a photo of each): expected `80 255 1` at the start of every line; the fourth number about 318 on the first screen and about 275 on the second.
5. `13-SWAPCHK` (2 minutes, the first of them with the screen showing "preparing"): expected `RUNS OK: 20 OF 20, WRONG C64: 0 REU: 0`. This is the test for the swap fix: on Alpha 24X1 it would report about 200 wrong REU bytes.
6. `1-FETCH` (2 minutes): expected `RUNS OK: 20 OF 20, BAD BYTES: 0`.
7. `2-STASH` (2 minutes): expected `RUNS OK: 20 OF 20, BAD BYTES: 0`.
8. `15-HEALTH` once more.
9. The patched CMD REUTEST with the screen on, twice if you have the patience: expected OK in every step, and the Bit Fill line should now take about a minute instead of six seconds (all 16 patterns run completely). I am curious how often `Interrupt Register: err 1` shows up.

## If a check fails

Please photograph the screen and note which program it was. Then, each step followed by `15-HEALTH` and a photo:

1. nothing in between (just `15-HEALTH`),
2. the reset button (a short press),
3. switch off, wait about five seconds, switch on,
4. switch off, your long wait, switch on.

This tells us what brings the REU back, which is the most important clue we can get. Afterwards please continue the list of Part A where you were.

## Part B, the soak test (30 minutes, runs on its own)

`16-SOAK`, once on Alpha 24X2, started right after a cold start and before any other program. It only writes and reads the REU's registers, it never starts a transfer, and it prints one line every three minutes. Expected: the last two numbers of every line are 0, and `DONE: 0 WRONG OF ...` after 30 minutes. One photo at the end is enough. If it does show wrong writes, the same run on Alpha 23 would be very interesting.

## Part C, only if the REU went silent in Part A

The same list as Part A on Alpha 24, from a cold start, up to the program at which it failed on Alpha 24X2. If it stays awake there, we know the build matters; if it goes silent as well, we know it does not.

If something hangs: RUN/STOP+RESTORE or reset; nothing is written to the SD card.

Thanks a lot!
