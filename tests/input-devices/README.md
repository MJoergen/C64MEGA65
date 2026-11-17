# Input monitor for both control ports

`inputmon.prg` is a small BASIC V2 program that shows what the C64 sees on its two control ports: the two paddle values (POT X and POT Y) and the five digital lines of each port. It is meant for testing joysticks, paddles (Commodore and Atari CX30), a Commodore 1351 mouse and an Amiga mouse on the C64MEGA65 core and on a real C64. `inputmon.bas` is its source.

## What it shows

```
INPUT MONITOR, STOP ENDS IT
TOUCH NO OTHER KEY WHILE IT RUNS

PORT 1  X 255  Y 255  LINES  0
PORT 2  X 255  Y 255  LINES  0
```

`X` is the paddle value of pin 9 (SID register `$D419`), `Y` the one of pin 5 (`$D41A`), both 0 to 255; a pin with nothing connected reads 255. `LINES` is the sum of the digital lines of the port that are low (active):

| Value | Line | Pin | Joystick | Paddles | 1351 or Amiga mouse |
|---|---|---|---|---|---|
| 1 | up | 1 | up | | right button |
| 2 | down | 2 | down | | middle button |
| 4 | left | 3 | left | button of paddle X | |
| 8 | right | 4 | right | button of paddle Y | |
| 16 | fire | 6 | fire | | left button |

For example, a joystick pushed up and to the left with the fire button pressed shows `LINES 21` (1 + 4 + 16).

* **Joystick:** only `LINES` changes; X and Y stay at 255 unless the joystick has extra buttons on pins 5 and 9.
* **Paddles:** X is the paddle on pin 9, Y the one on pin 5, from 0 to 255; turning clockwise lowers the value (known for Atari CX30 paddles, expected for Commodore paddles). Their buttons are 4 (paddle X) and 8 (paddle Y). On the core, Atari CX30 paddles need the setting "Atari CX30" for their port in the on-screen menu (Advanced Settings, Input Devices, Paddles); with "C64" they read 255 over a large part of their travel.
* **1351 mouse**, and an **Amiga mouse** on a port that is set to "Amiga" in the on-screen menu (Advanced Settings, Input Devices, Mouse): X rises when the mouse moves to the right and Y rises when it moves away from the user. Both values stay between 64 and 191 and wrap around (the highest value is followed by 64 and the other way round); an Amiga mouse on the core delivers the even values from 64 to 190, two counts of the mouse for each step of 2. The buttons are 16 (left), 1 (right) and 2 (middle). On a port set to "Amiga" the direction lines of the mouse are hidden from the C64, so moving the mouse must not change `LINES`; the right and middle button of an Amiga mouse only work with a mouse or adapter that holds pins 9 and 5 high while the buttons are released (an active output stage, or pull-up resistors of about 2 kOhm from pin 7).

"Port 1" and "Port 2" in the two submenus of the core are the sockets of the MEGA65, while the monitor shows the ports of the C64: with "Flip joystick ports" switched on, a device in the MEGA65's port 1 shows up as port 2.

The display is updated about four times per second (one pass of the loop takes about a quarter of a second).

## Do not touch the keyboard

Touch no key while the program runs, except STOP. The keyboard shares its lines with the control ports: while port 1 is read, `$DC00` = 64 drives column 7 of the keyboard low (its bit 7 is 0), and a key of that column shows up as a line of port 1 (SPACE as 16, the key 1 as 1, the key 2 as 8, CTRL as 4, the left arrow as 2). The Commodore key (the MEGA key of the MEGA65) is in that column too, but on a line that is not one of the five lines of a control port, so it does not show up: the test of the core's switch "MEGA+left = right" (Advanced Settings, Input Devices, Mouse) holds it on purpose.

To end the program, press STOP and hold it until `BREAK` appears, which takes at most a quarter of a second. The KERNAL does not see STOP while a line of port 1 is low (it takes that for a second key in the same column), so release the joystick or the buttons of port 1 first, and the Commodore key too (it is a key of that column). After STOP the keyboard works as usual; RUN starts the program again.

## Loading it

* **C64MEGA65 core:** copy `inputmon.prg` to the SD card and load it with the `PRG:` line of the on-screen menu (Help key). The core resets the C64, loads the program and starts it.
* **Real C64:** put `inputmon.prg` on a disk or an SD card adapter and start it with `LOAD"INPUTMON",8` and `RUN`, or type in the listing below. The longest line has 74 characters, so every line fits into the 80 characters (two screen lines) that the C64 accepts for a program line.

```
10 REM INPUT MONITOR FOR BOTH CONTROL PORTS
20 PRINT CHR$(147);"INPUT MONITOR, STOP ENDS IT"
25 PRINT "TOUCH NO OTHER KEY WHILE IT RUNS"
30 POKE 56320,255:POKE 56333,127:POKE 56322,192
40 POKE 56320,64:FOR W=1 TO 2:NEXT
50 A=PEEK(54297):B=PEEK(54298):E=PEEK(56321)
60 POKE 56320,128:FOR W=1 TO 2:NEXT
70 C=PEEK(54297):D=PEEK(54298):F=PEEK(56320)
80 POKE 56320,127:POKE 56322,255:POKE 56333,129
90 PRINT CHR$(19);CHR$(17);CHR$(17)
100 PRINT "PORT 1  X";RIGHT$("  "+STR$(A),4);"  Y";RIGHT$("  "+STR$(B),4);
110 PRINT "  LINES";RIGHT$(" "+STR$(31-(E AND 31)),3)
120 PRINT "PORT 2  X";RIGHT$("  "+STR$(C),4);"  Y";RIGHT$("  "+STR$(D),4);
130 PRINT "  LINES";RIGHT$(" "+STR$(31-(F AND 31)),3)
140 GOTO 30
```

## How it works

* Line 30 switches off the timer interrupt of CIA 1 (writing 127 to `$DC0D` clears all bits of its interrupt mask). The interrupt runs the keyboard scan of the KERNAL sixty times per second, and the scan rewrites `$DC00` and leaves port 1 selected. `POKE 56322,192` then makes only bits 6 and 7 of port A (`$DC00`) outputs, so that bits 0 to 4 can be read as the lines of port 2.
* Lines 40 and 60 select port 1 (`$DC00` = 64, bit 6) and port 2 (128, bit 7) for the two analog inputs of the SID, and lines 50 and 70 read the paddle values and the digital lines: port 1 on `$DC01`, port 2 on `$DC00`, low active, so `31-(E AND 31)` is the sum of the active lines. A real C64 needs more than 1.6 ms after a change of the selection before the SID shows the new port; from the `POKE` to the first `PEEK` of the SID the program takes at least 11289 cycles, 11.5 ms on a PAL and 11.0 ms on an NTSC machine (the `FOR` loop alone takes about 5000 cycles). On the core the SID shows the selected port at once, so the wait does not matter there, also not in a turbo mode.
* Line 80 restores the state of the KERNAL: `$DC00` = 127, all bits of port A outputs, and the timer interrupt on again (129 sets bit 0 of the mask).
* The numbers are printed right-aligned with `RIGHT$` and `STR$`, so each value stays at its place and a shorter value overwrites all digits of a longer one (a number printed directly would be followed by a cursor step that leaves the old digit there). `CHR$(19)` moves the cursor home, so the screen never scrolls.
* STOP: BASIC polls STOP before every statement, but only the interrupt routine of the KERNAL writes the state of the key into `$91`. Between lines 30 and 80 the interrupt is off, so `$91` does not change there; a poll sees STOP only if `$91` already had that value when the interrupt was switched off. `POKE 56320,255` in front of `POKE 56333,127` excludes that: with `$DC00` = 255 no keyboard column is driven, so an interrupt that comes between these two statements cannot see STOP, and there is only room for one, because they take less than one interrupt period (at most 11174 cycles, while the interrupt comes every 16422 cycles on a PAL and every 17046 cycles on an NTSC machine). An interrupt before them is followed by the poll in front of `POKE 56333,127`, while the interrupt is still on. So the program stops only at polls that run with the interrupt on and with `$DC02` = 255, and the keyboard works afterwards. Without this guard, a STOP that the interrupt sees during `POKE 56333,127` ends the program with the interrupt off and the keyboard dead (until STOP and RESTORE).

## Check without hardware

`check_inputmon.py` runs `inputmon.prg` headlessly on py65 with the BASIC and KERNAL ROMs of a local VICE installation, against a model of CIA 1 (both ports, data direction registers, interrupt mask, timer A interrupt that runs the KERNAL's scan), the keyboard matrix, the joystick lines and the paddle values of both ports, and a SID whose port selection settles after 1.6 ms. It checks the values on the screen for many inputs, that no stale digits remain, that the screen does not scroll, the wait after each port switch, STOP at every moment of the loop and the state of CIA 1 and the keyboard afterwards, the petcat round trip and the line length; two controls show that the checks fail for a program without the guard in line 30 and for a SID that settles too slowly.

```
python3 tests/input-devices/check_inputmon.py           # about four and a half minutes
python3 tests/input-devices/check_inputmon.py --quick   # coarser steps, about two minutes
```

It needs python3 with py65 (`pip install py65`), the ROM folder of VICE (environment variable `VICE_ROMS`, default `/Applications/Vice/VICE.app/Contents/Resources/share/vice/C64`) and petcat (`PETCAT`, default `/Applications/Vice/bin/petcat`). It prints one line per check and `RESULT: PASS` or `RESULT: FAIL`.

`build.sh` rebuilds `inputmon.prg` from `inputmon.bas` with petcat.
