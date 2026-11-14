# Amiga mouse on the C64 core: research notes (issue #190)

Fact base behind `SPEC.md`. **[S]** means a source states it (file and line, or URL), **[I]** means it is inferred. Local paths are relative to the repository; "upstream" is `src/vhdl/mouse_input.vhdl` of https://github.com/MEGA65/mega65-core, branch `development`, commit `3c0c27fe` (2026-10-31).

## 1. Key findings

1. The experiment of July 2022 (branch `dev-amigamouse`, never merged) did not feed raw lines into the decoder. At that time `debouncer.vhd` ran at the 100 MHz board clock with `stable_time => 5` for the four directions, so a line had to be stable for 5 ms before a change got through [S: `top_mega65-r3.vhd` lines 274 to 307 and `debouncer.vhd` lines 58 to 98 of that branch]. At 200 counts per inch such a filter swallows every edge above about 5 cm/s of hand speed. Hovering the mouse lets the ball turn more slowly than the hand, which is why it "worked only when hovering" [I]. Today's 1 ms filter would still cap a 200 cpi mouse at about 25 cm/s and a 1000 cpi mouse at about 5 cm/s. The decoder has to take the raw pins.
2. The right button (pin 9) and the middle button (pin 5) of an Amiga mouse cannot be read on any MEGA65 board without an external pull-up: the buttons are bare switches to ground, and the POT pins of the board have no pull-up, so "open" and "grounded" both measure 255.
3. The MEGA65 core's module is not a good template: its autodetection gives false positives (mega65-core issue #963, open), raw quadrature leaks into CIA1 and disturbs the keyboard (#779 and #549 open, #303 closed), the right button logic has a copy-and-paste bug for port B, and the lines are neither synchronized by two stages nor filtered.
4. The POT encoding of the MEGA65 module, `value = count + 64` with a 7-bit count, is the format of a real 1351 in proportional mode. VICE uses the same formula.

## 2. The MEGA65 core's implementation

History of the upstream file since the copy in this repository was taken (January 2023) [S: `git log`]:

| Date | Commit | Change | Issue |
|---|---|---|---|
| 2023-04-29 | 9c056ad7 | POT time base from an external phi strobe instead of the "assumes 50 MHz" divider (the CPU clock had become 40.5 MHz, so values only reached about `$60`) | #694 |
| 2023-05-06 | 90281486 | POT time base moved to the NTSC phi strobe, about 1.023 MHz | |
| 2024-01-18 to 27 | 3fc5d40d, 1eb6117c, 829161a8, 2d6563d3, 030430d2 | right button: raw pin, then thresholds on the measured POT X (over 200 is released, under 40 is pressed), polarity flipped twice, then gated by flags | #751 |
| 2024-01-26 | 226eebae (`machine.vhdl`) | all four directions go through the masked outputs; before, only "up" did, so left, down and right of an Amiga mouse reached CIA1 | #751, #779 |
| 2024-01-27/28 | 168cde8b, 4a3e0af4, 975f8456, f2680bb6 | 1351 "de-jitter" hysteresis of 2 on the measured POT values, bypassed in Amiga mode | #775 |
| 2024-01-31 | 0347a55c | edge test relaxed from bits 7..2 to bits 7..4; comment: "22K resistor on Amiga mouse right button gives values of 12 and 255" | #751 |
| 2024-09-06 | 9449ac13 | fix of the vertical de-jitter of port 1 | #828 |

None of these commits changes the quadrature decoder or the detection rules. The copy in this repository (`M2M/vhdl/controllers/M65/mouse_input.vhdl`) is the logic of before 2023; its internal divider `phi_counter < 49` is correct for the 50 MHz QNICE clock (1.000 MHz).

Upstream runs the module on the CPU clock (40.5 MHz) and gives the joystick and POT pins one register stage, no second synchronizer stage, no debouncing and no glitch filter [S: `machine.vhdl:1579`, `mega65r6.vhdl:1462-1471` and `1496-1500`, `mega65r3.vhdl:1208`].

Registers [S: `c65uart.vhdl:588-602`, `iomap.txt:555-561`]: `$D61B` bits 0 and 1 enable "Amiga mouse support (1351 emulation)" for port 1 and 2, bits 2 and 3 are the "assume" bits; all four are write only. The Configure utility labels bits 0/1 "joy N mouse mode: normal / amiga to 1351 enabled" and bits 2/3 "joy N 1351 de-jitter: on / off".

Autodetection [S: upstream lines 142 to 244]: Amiga mode is entered when up and down are both low, or left and right are both low, while both measured POT values of the port have an upper nibble of `0000` or `1111`; a resting mouse meets this in 7 of its 16 states [I]. The mode is left after 250,000,000 clocks with all four lines high (about 6 s); the comment admits a chance of 1 in 16 to rest in that state. Edges are only decoded while the mode is on; before the detection and after the timeout they reach the CIA as joystick directions.

Known issues upstream [S: issue search for "amiga mouse" in MEGA65/mega65-core]:

| Issue | State | Content |
|---|---|---|
| #549 (2022) | open | Amiga mice print characters, block the keyboard and only move while the right button is held; a wireless adapter shows the same |
| #303 (2020) | closed | an Amiga mouse makes the keyboard unusable |
| #779 (2024) | open | an Amiga mouse in port 1 disturbs the keyboard and Run/Stop; partly fixed by 226eebae |
| #751 (2023-12 to 2024-08) | closed | the right button toggled with Y movement; after the fix the right button never works, explained by the missing pull-up; a pull-up was requested from the mouSTer project; one vintage tank mouse also lost its left button, one Escom mouse gave no movement at all, both unresolved |
| #775, #828 | closed | jitter of the 1351 on the MEGA65 core |
| #963 (2026-10-30) | open | joysticks are detected as Amiga mice when moved quickly from left to right |

## 3. Algorithm of the module

* Pairs: X is (right, down), that is DE-9 pins 4 (HQ) and 2 (H). Y is (left, up), pins 3 (VQ) and 1 (V).
* Direction [S: local lines 243 to 274]: X increments for (right, down) going 00, 01, 11, 10; Y increments for (left, up) going 00, 10, 11, 01. With the counter bits of Denise (right is X1, back is X1 xor X0) [S: https://docs.kernel.org/input/devices/amijoy.html] this means: X increments when the mouse moves right, Y increments when it moves up [I]. That is the convention of the 1351 (the driver of cc65, `c64-1351.s` lines 391 to 397, subtracts the Y delta from the screen position).
* One count per edge, four per quadrature cycle, like Denise.
* POT value: `pot(5..0) = count(5..0)`, `pot(6) = not count(6)`, `pot(7) = count(6)`, which equals `count + 64` for a 7-bit count, range `$40` to `$BF`. Same as VICE `(pos & 0x7f) + 0x40` (`mouse_1351.c:130`). One Amiga count is one POT LSB, half a position step of a 1351.
* Right button in the local copy: `fa_up_out <= pota_x_internal(7)`. Without a pull-up the value is always 255, so the button never reads as pressed; with a 22 kOhm pull-up the released button measures about 12 and reads as pressed: inverted.
* Ways to lose or miscount steps: edges before the detection and after the timeout are not counted; illegal double transitions are ignored (harmless at 50 MHz sampling); single-line chatter is harmless for per-edge decoding because every glitch counts +1 and then -1 [I].

## 4. Amiga mouse: electrical and timing facts

Pinout [S: kernel `amijoy` documentation; VICE `mouse_quadrature.c:33-43`]:

| DE-9 pin | Amiga mouse | C64 line | CIA bit |
|---|---|---|---|
| 1 | V pulse | up | 0 |
| 2 | H pulse | down | 1 |
| 3 | VQ pulse | left | 2 |
| 4 | HQ pulse | right | 3 |
| 5 | middle button | POT Y | |
| 6 | left button | fire | 4 |
| 7 | +5 V | +5 V | |
| 8 | GND | GND | |
| 9 | right button | POT X | |

* Output stage: the encoders feed a quad comparator (LM339 or HA17339, open collector) with 3.3 kOhm to +5 V on each output inside the mouse [S: https://ftp.fau.de/aminet/docs/hard/mousehack.txt; https://c65gs.blogspot.com/2018/01/repairing-amiga-mouse-and-then-using-it.html]. The buttons are bare switches to ground without pull-up [S: mousehack.txt "pull-up resistors must be inside the Amiga"; VICE `mouse_quadrature.c:50-52`].
* Board side, digital lines [S: schematics, sheet `JOY.SchDoc`]: all five lines of both ports have 4.7 kOhm pull-ups to the switched 5 V of the joystick ports, no RC filter, no series resistor. R3: port A through single NC7SZ126 buffers (3.3 V), port B through a SN74LVCH16T245 with bus hold; R3 cannot drive a joystick line. R5 and R6 add 74AHCT1G125 drivers as open-drain pull-downs. This core never drives the lines: `keyboard.vhd` ties all joystick outputs to '1'.
* Board side, POT pins, all boards [S: schematics, sheet `B15.SchDoc`]: pin, 1 kOhm in series, 1.2 nF to ground with a 2N7002 for the discharge, NC7SZ126 at 3.3 V as the comparator. No pull-up. With an external pull-up R to 5 V the charge time is about R x 1.2 nF x ln(5 / (5 - Vth)); for 22 kOhm that is 11 to 16 µs, which matches the "12" in the upstream comment [I].
* Resolution: "200 count-per-inch mouse" [S: Amiga Hardware Reference Manual]; about 204 measured on two Commodore models [S: Deskthority wiki]. Later optical Amiga mice: 400 to 1000.
* How long one line keeps its level (50 % duty assumed; each line toggles every second count) [I]:

| counts per inch | 5 cm/s | 10 cm/s | 25 cm/s | 50 cm/s | 100 cm/s |
|---|---|---|---|---|---|
| 200: counts per second | 394 | 787 | 1969 | 3937 | 7874 |
| 200: stable time of a line | 5.08 ms | 2.54 ms | 1.02 ms | 0.51 ms | 0.25 ms |
| 400: stable time of a line | 2.54 ms | 1.27 ms | 0.51 ms | 0.25 ms | 0.13 ms |
| 1000: stable time of a line | 1.02 ms | 0.51 ms | 0.20 ms | 0.10 ms | 51 µs |

* The Amiga itself: Denise samples the pins at the color clock and keeps two 8-bit counters per port that software reads in the vertical blank; no filtering is described [S: Hardware Reference Manual].
* A glitch filter of 2 to 4 µs per line (after a two-stage synchronizer) leaves a margin of more than six against the shortest legitimate stable time (about 25 µs for 1000 cpi at 2 m/s) [I].
* Atari ST mouse [S: VICE `mouse_quadrature.c:69-85`]: pin 1 XB, 2 XA, 3 YA, 4 YB, 6 left, 9 right. Supporting it would only be another assignment of the pin pairs.

## 5. The 1351 side

* POT format [S: 1351 manual; https://www.c64-wiki.com/wiki/1351]: bit 7 "don't care", bits 6 to 1 the position modulo 64, bit 0 noise.
* How the 1351 produces it [S: https://github.com/MartinEmrich/5717emu]: it synchronizes on POT Y going low (the discharge of the SID), counts 256 µs, waits another 64 µs and then pulls the line high after counter x 2 µs, so the SID reads about 64 + 2 x position [I].
* SID [S: Hedley Davis, comp.sys.cbm 1987]: the cycle is 512 CPU cycles, 256 to discharge and up to 256 to count; polling at 60 Hz is enough.
* Drivers [S: cc65 `c64-1351.s:439-466`; GEOS `input/mse1351.s` in https://github.com/mist64/geos]: delta is `(new - old) & $7F`; below `$40` it is halved, otherwise it is sign-extended, skipped if it is -1, and halved. When the delta is 0 or one LSB the old value is not updated, so half steps accumulate. Usable window: +31 to -32 position steps (63 LSBs) per read. GEOS adds an acceleration table (1 to 31 steps become 1 to 100 pixels) and reads only the left button.
* Speed before a driver's delta wraps, read once per frame at 50 Hz / 60 Hz [I]:

| Scale | 200 cpi | 400 cpi | 1000 cpi |
|---|---|---|---|
| 1 count is 1 LSB (MEGA65 core, VICE) | 40 / 48 cm/s | 20 / 24 | 8 / 10 |
| 1 count is 2 LSB | 20 / 24 | 10 / 12 | 4 / 5 |

* No published figure for the counts per inch of a 1351 was found.
* Buttons [S: 1351 manual; VICE `mouse_1351.c:31-40`]: left is the fire line (pin 6), right is the up line (pin 1) in proportional mode. In joystick mode the 1351 sends direction pulses of 20 ms.
* Micromys protocol [S: https://wiki.icomp.de/wiki/Micromys_Protocol]: right button on the up line, middle button on the down line, wheel as pulses of about 50 ms on the left and right lines.
* The SID of this core returns the POT inputs combinationally (`sid_top.sv:325-326`); no driver depends on the once-per-512-cycles latch of the real chip [I]. MiSTer's own 1351 emulation (`c1351.v`) uses a 6-bit position in bits 6 to 1, noise in bit 0 and bit 7 clear.
* GEOS also has a native Amiga mouse driver (`input/amigamse.s`) that polls the quadrature lines through `$DC01`; it is not needed with the 1351 emulation.

## 6. The 1 ms debouncer and other devices

All ten joystick lines pass `debounce.vhd` (two flip-flops and "stable for 1 ms") in the core clock domain.

| Device | What travels over the digital lines | Verdict |
|---|---|---|
| 1351 in proportional mode | only the buttons | unaffected (1 ms of latency) |
| 1351 and 1350 in joystick mode | pulses of 20 ms | unaffected |
| Micromys, mouSTer (wheel, middle button) | pulses and gaps of about 50 ms | unaffected |
| Joysticks with autofire | 5 to 30 Hz | unaffected |
| Paddle buttons, Koala Pad, tablets | mechanical switches | unaffected |
| Amiga and Atari ST mice, decoded behind the filter | quadrature | degraded (200 cpi: cap at about 25 cm/s), broken for optical mice with 1000 cpi |
| NEOS mouse | the C64 drives a strobe on pin 6 and reads nibbles within 0.2 ms | broken; it also needs a core that drives the port lines |
| Light pen, light gun on port 1 | pulses of microseconds on the fire line (the LP input of the VIC-II is the debounced fire line of port 1 in this core) | broken; the latency of a scaler breaks pens anyway |
| Protocols in which the C64 drives a line and reads the answer within microseconds (Inception, SNES pad adapters, Protopad, real-time clocks on the port) | | broken on every board today: they need the open-drain drivers of R5/R6, the CIA outputs wired to them and a read path around the filter |

## 7. What only a real mouse on the hardware can settle

* Whether the right and middle button work with a pull-up, and the measured values (expected about 11 to 16 for 22 kOhm).
* Signal quality of the comparator outputs (3.3 kOhm in the mouse in parallel with 4.7 kOhm on the board, cable capacitance) and whether the filter length is right.
* Scale and feel in GEOS and other software.
* The direction of both axes on the screen.
* The oddities of mega65-core issue #751: a vintage mouse without a working left button, an Escom mouse without movement.
