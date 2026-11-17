# Atari CX30 paddles on the C64 core: research notes (issue #193)

Fact base behind `SPEC.md`. Every link of the issue was read. Where a statement is an inference and not the content of a source, it says so.

## 1. Key findings

1. A C64 reaches the highest paddle value 255 long before the end of the rotation, with Commodore paddles too: at 245 to 347 kOhm depending on the SID revision, which is 52 to 74 % of the travel of a 470 kOhm Commodore paddle and 25 to 35 % of the travel of a nominal 1 MOhm Atari paddle. "Does not work properly" means: only a quarter to a third of the rotation is used, the rest reads 255, and the control is very sensitive. The user documentation of this core reports "about a third" for the Atari CX30+ on the core, which fits a real C64.
2. The measurement on the MEGA65 board is one RC charge per pin, so the time is proportional to the resistance. A fixed factor on the time is exactly a factor on the resistance, independent of the threshold, the capacitor tolerance and the port voltage.
3. Both paddle families are pin compatible, have linear potentiometers without a series resistor, and turn in the same direction (clockwise lowers the value; confirmed for Atari, inferred for Commodore).
4. No FPGA core and no emulator that was looked at has a setting for the paddle type.
5. A 1351 encodes its position in steps of 2 µs after the discharge of the SID, so its port must never be scaled, and the measuring window of a port in C64 mode has to stay where it is.

## 2. How the core measures today

* `M2M/vhdl/controllers/M65/mouse_input.vhdl`, lines 348 to 394: a tick of 1 µs (50 MHz divided by 50). Ticks 0 to 255: discharge on. Ticks 258 to 512: the counter of each pin counts the ticks in which its input reads '0'. Tick 513: the counters are latched. One cycle is 514 µs (the SID: 512 cycles of the CPU clock). A reading is about the charge time minus 1.5 µs.
* `M2M/vhdl/qnice_wrapper.vhd`, lines 562 to 625: the instance; the value is inverted (`x"FF" - value`) and the ports are swapped when "Flip joystick ports" is on.
* `M2M/vhdl/framework.vhd`: clock domain crossing to `main_pot1_x_o` and so on.
* `CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd`, lines 742 to 758: `not pot1` undoes the inversion, so the SID register is the tick count. `cia1_pao(6)` selects port 1, `cia1_pao(7)` port 2; with neither the SID reads `$FF`, with both the AND of the two ports. All four pins are measured all the time, so a change of the port selection takes effect immediately.

Board circuit (R3 sheet 6, R6 sheet 8 of the schematics, identical):

| Part | Value |
|---|---|
| Series resistor from the DE-9 pin to the node | 1 kOhm, 1 % |
| Capacitor from the node to ground | 1.2 nF, 50 V (dielectric and tolerance not stated) |
| Discharge | 2N7002 at each node, all four gates on one net ("Pulse-discharge", one FPGA pin) |
| Comparator | NC7SZ126 buffer at 3.3 V: no hysteresis, threshold only bounded by the datasheet (0.99 V to 2.31 V), leakage up to 1 µA at 25 °C |
| Paddle pins of the DE-9 | pin 9 X, pin 5 Y, no resistor; pin 7 is the switched 5 V |

Charge time in µs for three assumed thresholds (5.0 V supply):

| Resistance | Vth 0.99 V | Vth 1.65 V | Vth 2.31 V |
|---|---|---|---|
| 0 | 0.3 | 0.5 | 0.8 |
| 470 kOhm | 125 | 226 | 350 |
| 800 kOhm | 212 | 385 | 596 |
| 1 MOhm | 265 | 481 | 745 |
| 1.2 MOhm | 318 | 577 | 893 |
| resistance that reads 255 today | 962 kOhm | 530 kOhm | 342 kOhm |

The field report of the user documentation ("about a third" of the travel of a CX30+) implies about 330 kOhm for the value 255, close to the right column and to a real C64. Reports about the MEGA65 core (dead zone of a quarter turn; Commodore paddles 0 to 180 or 0 to 255) are not comparable, because that core used other time bases at the time.

## 3. How a real C64 measures

* The SID discharges the paddle pins for 256 cycles and then counts until the voltage crosses a threshold, nominally half the supply voltage; the result is updated every 512 cycles [Hedley Davis, comp.sys.cbm, 1987: https://utzoo.superglobalmegacorp.com/usenet/news050f1/b70/comp/sys/cbm/137.txt; SID datasheet: "RC = 4.7E-4 ... recommended values for R and C are 470 KOhms and 1000 pF"]. The capacitor on the C64 board is 1000 pF [1351 patent US4886941].
* Measured (chart "Widerstandsmessung" of https://www.c64-wiki.de/wiki/Paddle, read off at the value 250):

| SID | Resistance at the value 250 | kOhm per count |
|---|---|---|
| 6581 (R2) | about 245 kOhm | 0.98 |
| 6581R3 | about 258 kOhm | 1.03 |
| 6581R4 | about 327 kOhm | 1.31 |
| 6581R4AR | about 347 kOhm | 1.39 |
| 8580R5 | about 341 kOhm | 1.36 |

* Paddles on a real C64 (linear taper and 300 degrees of rotation assumed):

| Paddle | Potentiometer | 255 reached at | Dead travel at the counterclockwise end |
|---|---|---|---|
| Commodore 1311/1312 | 470 kOhm nominal, 465 kOhm measured | 52 to 74 % of the travel | 26 to 48 % |
| VIC-20 paddles | 500 kOhm on the schematic, 625 kOhm measured | 49 to 69 % | 31 to 51 % |
| Atari CX30 | 1 MOhm nominal; units measured: 791 kOhm and 843 kOhm | 25 to 35 % (nominal), 29 to 44 % (measured units) | 65 to 75 % |

* Knob angle for the full screen width of the bat in Arkanoid [https://breadbox64.com/paddle-battle/]: Atari 90 degrees, Commodore 1312 135 degrees, VIC-20 100 degrees.
* Pinout, identical for both families [https://wiki.icomp.de/wiki/DE-9_Paddle, Atari's accessories schematic of 1982]: pin 9 paddle X, pin 5 paddle Y, pin 3 button of paddle X (the "left" line), pin 4 button of paddle Y (the "right" line), pin 7 +5 V, pin 8 ground.

## 4. The paddles

* CX30 is the original Atari paddle pair (2600, also used on the 400/800). CX30+ is the reproduction sold since November 2023 for the Atari 2600+. Nobody has published the resistance of the CX30+; a second revision "with different potentiometer" appeared in 2024 [AtariAge thread "The Paddles", statement of the distributor]. That it is 1 MOhm linear is an assumption.
* What the sources say about Atari paddles on a C64: "the C64 can only utilize about a third of the paddle motion. The leftmost 2/3rds will not give any results ... Inside that third of the range the control is very precise" [https://kugelblitz360.github.io/C64MEGA65DOCS/joysticks-paddles-mice.html]; "extremely sensitive, with a large dead zone" [C64-Wiki]; "can be used on the Commodore 64 without problems, only the usable range is limited ... Sometimes the limited range is an advantage" [https://janderogee.com/projects/paddle/paddle.htm]. Jan Derogee's page has no measurements; his game archive contains a variant of one game that is patched for Atari paddles in three bytes.
* Jitter is a separate matter (wear and the quality of the potentiometer); the MEGA65 core added a hysteresis against it that broke a game with four paddles (mega65-core issue #822). This core has none.

## 5. What others do

| Project | Atari paddles |
|---|---|
| MEGA65 core | same measurement, no scaling, no paddle type |
| MiSTer C64 core | paddles only through USB, no real paddles |
| Ultimate 64 | no paddle type; a request for 1 MOhm support is open (GideonZ/1541ultimate issue #645) |
| VICE, TheC64 | no paddle type |
| A SID replacement (PDsid) | reportedly has a switch "Atari (1M) / Commodore (500k)"; unverified |

## 6. The 1351 and the measuring cycle

From the patent of the 1351 (US4886941) and a description of its controller: the mouse runs from 1 MHz, detects the discharge of the SID on the POT Y line, and drives each line high 320 + 2 x (position modulo 64) µs after that; it releases the lines 480 µs after the discharge. The SID therefore reads about 64 + 2 x position. Consequences (inferred):

* A port with a 1351 must not be scaled.
* A longer cycle is probably harmless for a 1351 on the other port as long as the discharge still starts the cycle and lasts 256 µs, the window of a port in C64 mode stays at the ticks 258 to 512, and the cycle stays below 832 µs: if the counter of the mouse runs on without a new discharge, it would drive the lines again at 512 + 320 µs.

Other devices on the paddle pins: joysticks with a second and third button connect the pin to +5 V (pressed reads 0, released 255: works with any scale); a KoalaPad is made for the range of the SID and belongs on a port in C64 mode.

## 7. Test programs and titles

* Arkanoid (paddle in port 1) and Pinball Spectacular for the full travel to both edges; Space Lords for four paddles and for a 1351 (the existing smoke test); Panic Analogue to judge jitter.
* A monitor for all four paddles and their buttons in BASIC V2. It stops the keyboard scan while it reads (the KERNAL rewrites the port selection in `$DC00` sixty times per second and leaves port 1 selected), selects one port after the other with bits 6 and 7 of `$DC00` and waits a few milliseconds, which a real C64 needs after a change of the selection; on this core the wait is harmless. Do not touch the keyboard while it runs: a key in the column that selects a port shows up as a button.

```
10 REM PADDLE MONITOR: 4 PADDLES, 4 BUTTONS
20 PRINT CHR$(147);
30 POKE 56333,127:POKE 56322,192
40 POKE 56320,64:FOR W=1 TO 2:NEXT
50 A=PEEK(54297):B=PEEK(54298):E=PEEK(56321)
60 POKE 56320,128:FOR W=1 TO 2:NEXT
70 C=PEEK(54297):D=PEEK(54298):F=PEEK(56320)
80 POKE 56320,127:POKE 56322,255:POKE 56333,129
90 PRINT CHR$(19);"PORT 1  X";RIGHT$("   "+STR$(A),4);"  Y";RIGHT$("   "+STR$(B),4)
100 PRINT "  FIRE X";-((E AND 4)=0);" FIRE Y";-((E AND 8)=0)
110 PRINT "PORT 2  X";RIGHT$("   "+STR$(C),4);"  Y";RIGHT$("   "+STR$(D),4)
120 PRINT "  FIRE X";-((F AND 4)=0);" FIRE Y";-((F AND 8)=0)
130 GOTO 30
```

## 8. What only the hardware can settle

1. The count for known resistors (1 % resistors from pin 7 to pin 9 and to pin 5: 0, 100 k, 220 k, 330 k, 470 k, 680 k, 1 M) on R3 and R6, both ports, with the monitor above: this gives the resistance that reads 255 and the linearity.
2. The resistance at both ends and the rotation angle of the paddles at hand: original CX30, CX30+ of both revisions, Commodore 1311/1312.
3. The direction of rotation of each type.
4. Jitter at rest in both modes.
5. A 1351 on one port while the other port is set to Atari CX30.
6. Atari mode in games: Arkanoid and Pinball Spectacular reach both screen edges with a CX30 and a CX30+.
