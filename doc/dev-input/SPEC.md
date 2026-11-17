# Input devices: Amiga mouse and Atari CX30 paddles

Specification of the two features of GitHub issues [#190](https://github.com/MJoergen/C64MEGA65/issues/190) (Amiga mouse) and [#193](https://github.com/MJoergen/C64MEGA65/issues/193) (Atari CX30 paddles), first shipped in WIP-V6-A26. The facts behind the numbers are in `RESEARCH-amiga-mouse.md` and `RESEARCH-paddles.md`; the state of the work, the verification record and the open points are in `STATUS.md`.

## 1. What the user gets

The submenu "Advanced Settings" has a section "Input Devices" with three submenus: "Keyboard Shortcuts" (unchanged), "Mouse" and "Paddles".

```
 Mouse                        Paddles
 ──────────────────           ──────────────────
 Port 1: C64                  Port 1: C64
 Port 1: Amiga                Port 1: Atari CX30
 #1: MEGA+left = right        ──────────────────
 ──────────────────           Port 2: C64
 Port 2: C64                  Port 2: Atari CX30
 Port 2: Amiga                ──────────────────
 #2: MEGA+left = right        Back
 ──────────────────
 Back
```

The lines "#1: MEGA+left = right" and "#2: MEGA+left = right" are only shown while the mouse setting of their port is "Amiga".

* "Port 1" and "Port 2" are the two sockets of the MEGA65. The setting describes the device that is plugged into that socket and travels with it when "Flip joystick ports" swaps the ports for the C64.
* "C64" is the default for all four settings and behaves exactly as every version before: joysticks, Commodore paddles, the 1351 and compatible mice and adapters.
* "Amiga" (Mouse): the port has an Amiga mouse. The core turns it into a Commodore 1351 in proportional mode, so every program with a 1351 driver works with it (GEOS, for example). The left button is the fire line, as on a 1351. The four direction lines of that port are hidden from the C64 while the setting is active, so the mouse cannot disturb the keyboard.
* "#1: MEGA+left = right" and "#2: MEGA+left = right" (Mouse): a switch per port, off by default. It is the substitute for the right button of the mice whose right button the board cannot read (see the limits below). While it is on, a press of the left mouse button that begins while the MEGA key is held is a right click: for as long as the button stays pressed, the C64 sees the right button of a 1351 (the up line of that port) and not the left one. The key at the moment the button goes down decides; it may be released before the button. The C64 still sees the MEGA key as its Commodore key. A right button that the device itself delivers keeps working. The switch keeps its state while it is hidden and has no effect on a port that is set to "C64".
* "Atari CX30" (Paddles): the port has paddles with 1 MOhm potentiometers (Atari CX30 and CX30+) instead of the 470 kOhm of Commodore paddles. A C64 reaches the highest value 255 at about 250 to 350 kOhm, so a Commodore paddle uses half to three quarters of its rotation and an Atari paddle only a quarter to a third. With this setting the core measures with half the sensitivity: a 1 MOhm paddle then behaves like a 500 kOhm paddle, and the usable part of its rotation doubles.
* The two settings of a port are independent menu items but not independent devices: with "Amiga" selected, the paddle setting of that port has no effect on what the C64 reads.

Limits that come from the hardware:

* The right and the middle button of an Amiga mouse are switches to ground on pins 9 and 5, which are the paddle inputs. The board can only tell a pin that is pulled or driven up to +5 V from one that is not (section 2), so an original Amiga mouse has only its left button (the switch "MEGA+left = right" gives it a right click). Both buttons work with everything that holds the two pins high while the buttons are released: mice and adapters with an active output stage, a mouSTer in Amiga mode with firmware 3.23.5313 or newer and `activepotlines=true`, or any passive mouse behind a straight-through adapter with two resistors of about 2 kOhm from pin 7 to pin 9 and from pin 7 to pin 5. The right button is the up line as on a 1351, the middle button the down line as in the Micromys protocol. This is the experience and the mechanism of the Amiga core for the MEGA65 (AExp), whose documentation lists the devices.
* USB adapters with a polled wheel protocol (Micro Tom, for example) take every discharge of the paddle pins as a request and answer it with a short code on the movement lines. The decoder counts such a code forwards and backwards again, so the position does not drift, but the pointer can twitch. The cure is the one of the Amiga core: an extension cable with wire 5 cut, which costs the middle button and the wheel.
* After a mouse or adapter that provides the right and middle button is unplugged from a port that is set to "Amiga", the C64 sees both buttons pressed for up to five seconds (on port 1 that looks like held keys).
* Everything that is not an Atari paddle needs the paddle setting "C64" for its port: a 1351 (its position is encoded in steps of 2 µs), a KoalaPad, Commodore paddles.
* While at least one port is set to "Atari CX30", the measuring cycle of both ports is longer (section 6), because one signal discharges all four paddle pins. Devices on the other port measure the same values as before. A 1351 on the other port synchronizes itself to the discharge and should not mind the longer cycle; this combination is untested.

## 2. The hardware

Schematics of the Trenz boards TE0765-03 (R3) and TE0765-06 (R6), sheets `JOY.SchDoc` and `B15.SchDoc`; R4 and R5 are the same in these parts.

* Digital lines (pins 1 to 4 and 6 of each port): 4.7 kOhm pull-up to the switched 5 V of the ports, a buffer with 3.3 V supply, the FPGA pin. No RC filter. R5 and R6 can also pull each line low through an open-drain driver; the core never does (`keyboard.vhd` ties all joystick outputs to '1').
* Paddle pins (9 and 5 of each port, `paddle_i(3 downto 0)`): the pin, 1 kOhm in series, a node with 1.2 nF to ground, a 2N7002 that discharges the node while `paddle_drain_o` is '1' (one signal for all four), and a NC7SZ126 at 3.3 V as the comparator. The FPGA sees '0' while the node is below the threshold of the buffer. There is no pull-up: the capacitor only charges through whatever connects the pin to +5 V (pin 7), which is the potentiometer of a paddle or the output stage of a 1351.
* Consequence 1: the time until the comparator output turns '1' is proportional to the resistance plus the series resistor, t = (R + 1 kOhm) x 1.2 nF x ln(5 V / (5 V - Vth)), as long as the leakage at the node is negligible (it is specified with up to 1 µA and is nanoamperes typically; leakage makes a high resistance read higher). A scale factor on the measured time is therefore a scale factor on the resistance.
* Consequence 2: a pin that is open and a pin that is shorted to ground look the same (the capacitor never charges, the value is 255).

## 3. Signal flow

```
 QNICE clock (50 MHz)                               core clock (31.5 MHz PAL, 32.7 MHz NTSC)

 paddle_i(3..0) ──► mouse_input ──► flip, invert ──► cdc_stable ──┐
 paddle_drain_o ◄──┘    ▲          (qnice_wrapper)                 │
                        │                                          ▼
 qnice_paddle_atari ────┘        joystick pins (raw) ────────► debouncer ──► main_pot1_x .. main_pot2_y ──► SID
 (menu, per socket)              main_mouse_amiga ───────────►  2 x amiga_mouse
                                 main_mouse_rclick ──────────►  right click with the MEGA key
                                 (menu, per socket)             flip, on/off ──► main_joy1 / main_joy2 lines ──► CIA1
                                 keyboard ──► m2m_keyb ──────►  (state of the MEGA key)
```

| File | Role |
|---|---|
| `M2M/vhdl/amiga_mouse.vhd` | new: Amiga mouse of one socket as a 1351 (section 4) |
| `M2M/vhdl/debouncer.vhd` | conditioning of the two ports: debouncing, Amiga mice, right click with the MEGA key, port switcher, on/off (section 5) |
| `M2M/vhdl/m2m_keyb.vhd` | keyboard driver; delivers the state of the MEGA key (section 5.1) |
| `M2M/vhdl/controllers/M65/mouse_input.vhdl` | paddle measurement, with the Atari mode (section 6) |
| `M2M/vhdl/qnice_wrapper.vhd`, `M2M/vhdl/framework.vhd`, `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd` | wiring; `framework.vhd` also holds the clock domain crossing of the paddle values (section 7) |
| `CORE/vhdl/mega65.vhd`, `CORE/vhdl/config.vhd` | menu items and the three ports that carry the six settings (section 8) |

## 4. The Amiga mouse: `amiga_mouse.vhd`

One instance per socket, in the core clock domain, fed by the raw pins. The 1 ms debouncer is not in this path: at 200 counts per inch a line of the mouse keeps its level for 1 ms at a hand speed of 25 cm/s and for 0.25 ms at 1 m/s. `G_CLK_FREQ` is the PAL frequency of the core clock, as for the debouncer; in NTSC mode the clock is 3.8 % faster and all times of this section are 3.7 % shorter.

```vhdl
entity amiga_mouse is
   generic (
      G_CLK_FREQ    : natural;             -- frequency of clk_i in Hz
      G_FILTER_NS   : natural := 2000;     -- a line needs to be stable for this time before a change counts
      G_STEP_US     : natural := 400;      -- shortest time between two steps of the reported position
      G_BACKLOG     : natural := 127;      -- counts that may wait for the rate limiter; further ones are dropped
      G_CONFIRM_US  : natural := 4000;     -- a button on a paddle pin needs to be stable for this time
      G_STUCK_MS    : natural := 5000      -- a button on a paddle pin that is pressed for longer is released
   );
   port (
      clk_i          : in  std_logic;
      enable_i       : in  std_logic;                      -- '1': this socket has an Amiga mouse

      -- the lines of the socket, low active, asynchronous
      up_n_i         : in  std_logic;                      -- pin 1: V
      down_n_i       : in  std_logic;                      -- pin 2: H
      left_n_i       : in  std_logic;                      -- pin 3: VQ
      right_n_i      : in  std_logic;                      -- pin 4: HQ

      -- measured values of the paddle pins of the socket (true values, clk_i domain)
      meas_x_i       : in  std_logic_vector(7 downto 0);   -- pin 9: right button
      meas_y_i       : in  std_logic_vector(7 downto 0);   -- pin 5: middle button

      -- what a 1351 in proportional mode would deliver
      pot_x_o        : out std_logic_vector(7 downto 0);
      pot_y_o        : out std_logic_vector(7 downto 0);
      right_btn_n_o  : out std_logic;                      -- low active
      middle_btn_n_o : out std_logic                       -- low active
   );
end entity amiga_mouse;
```

### 4.1 Synchronizer and glitch filter

Each of the four lines passes two flip-flops (attribute `async_reg`) and then a filter: the filtered value takes over the synchronized value once that has been stable for `G_FILTER_NS` (2 µs, 63 clock cycles: a pulse of up to 63 clock periods never passes, a level of 64 periods always does). All four lines have the same delay, so the order of the edges is kept. The shortest legitimate stable time of a line is about 25 µs (an optical mouse with 1000 counts per inch at 2 m/s). The comparator outputs of the mouse are open collector with pull-ups (3.3 kOhm in the mouse, 4.7 kOhm on the board), and the buffer on the board has no Schmitt trigger: the filter removes the chatter of a slow rising edge and short spikes. Synchronizer and filter always run, also while `enable_i` is '0'.

### 4.2 Decoder

Every edge counts, four counts per cycle of a pair, like the counters of the Amiga's Denise.

| Axis | Pair (first, second) | Position +1 for the sequence (and every rotation of it) | Meaning of +1 |
|---|---|---|---|
| X | (HQ, H) = (right, down) = (pin 4, pin 2) | 11, 10, 00, 01, 11 | mouse moves to the right |
| Y | (VQ, V) = (left, up) = (pin 3, pin 1) | 11, 01, 00, 10, 11 | mouse moves up (away from the user) |

The reverse sequence counts -1. A change of both lines of a pair in the same clock cycle counts nothing; the decoder continues from the new state. X to the right and Y upwards are the conventions of the 1351 (its drivers subtract the Y movement from the screen position) and of the Amiga's counters (which count Y downwards, hence the opposite sequence).

While `enable_i` is '0' nothing is counted and the backlog (4.3) is empty; the decoder keeps following the state of the lines, so that no count is produced at the moment `enable_i` turns '1'.

### 4.3 Backlog and rate limiter

A 1351 driver computes the movement since its last call as the difference of two POT values modulo 128 and takes 64 to 127 as negative. A mouse that delivers 63 or more steps between two calls therefore moves the pointer in the wrong direction; with one step per count, a 200 cpi mouse reaches that at 40 cm/s when the driver runs once per PAL frame, and a 1000 cpi mouse at 8 cm/s. The decoder prevents this:

* The counts of an axis go into a backlog, a signed number between -`G_BACKLOG` and +`G_BACKLOG` (127). A count that would exceed the bound is dropped.
* A free-running tick every `G_STEP_US` (400 µs) moves one count from the backlog into the position: position +1 and backlog -1 if the backlog is positive, the reverse if it is negative.

The position therefore never changes by more than 50 steps in a PAL frame of 20 ms (44 in an NTSC frame of 16.7 ms with its faster clock), which leaves a driver that is called once per frame 12 steps, or 4.8 ms of delay of its call, before the difference becomes ambiguous. While the mouse delivers fewer than 2500 counts per second (32 cm/s at 200 cpi), the backlog holds two counts at most and the position follows within 0.53 ms (0.41 ms if the two lines of a pair are exactly 90 degrees apart; measured at 2400 counts per second with phases from 60 to 120 degrees). A faster movement saturates the pointer speed at 2500 steps per second, which is 1250 position units of a 1351 driver per second or a screen width of 320 units in a quarter of a second; after the mouse stops, the pointer moves on for at most 51 ms.

### 4.4 The position as POT values

The position of each axis is a 7-bit counter that wraps around; one count of the mouse is one step. The POT value carries its upper six bits: `pot(7) = position(6)`, `pot(6) = not position(6)`, `pot(5 downto 1) = position(5 downto 1)`, `pot(0) = '0'`. That is 64 plus the position with bit 0 cleared: the even values from `$40` to `$BE`, the range of a real 1351, whose position also sits in bits 6 to 1 (its bit 0 is noise). Two counts of the mouse are one position unit for a 1351 driver, which is the scale of the MEGA65 core and of VICE. Bit 0 stays clear because the drivers halve the difference of two readings and take the new reading as their next reference: an odd difference would cost half a unit at every call, a clear bit 0 makes the driver follow the mouse exactly. The position starts at 0 and keeps its value while `enable_i` is '0'.

### 4.5 Right and middle button

The two buttons are derived from the measured values of the paddle pins of the socket (`meas_x_i` for the right button, `meas_y_i` for the middle button), each with its own instance of the same logic:

* A value below 128 means that something pulls or drives the pin up to +5 V: the button is released, and the device is one whose buttons can be read. Once this has held for the confirmation time, a flag "pull-up seen" is set.
* A value of 192 or more means that nothing pulls the pin up. If the flag is set, the button is pressed. If the flag is not set, the mouse has no pull-up and the button is never reported.
* Values from 128 to 191 change nothing.
* A change of the reported state or of the flag needs its condition to hold for `G_CONFIRM_US` (4 ms, several measuring cycles) without interruption; a value from 128 to 191 is such an interruption.
* A button that is reported as pressed for `G_STUCK_MS` (5 s) without interruption is released and the flag is cleared; it is set again by the next confirmed value below 128. This covers a device that held the pins high and is unplugged or exchanged for one that does not, while the setting stays "Amiga": the open pin looks like a pressed button, and without this rule it would stay pressed forever. The time is short because the two buttons are the up and down lines, which on C64 port 1 are in parallel with the keyboard matrix: for as long as the button is reported, the C64 sees held keys.
* `enable_i` at '0' clears the flag and releases the button.

A pin that is driven high or pulled up with 2 kOhm measures 0 to 3 when the button is released, a 22 kOhm pull-up 11 to 16, and all measure 255 when the button is pressed; the thresholds accept pull-ups up to about 150 kOhm. The Amiga core for the MEGA65 uses the same two rules in the field (a button counts only after its line has been seen high; there, 30 seconds of "pressed" clear that, because an Amiga holds its right button for as long as a menu is open).

## 5. Conditioning of the two ports: `debouncer.vhd`

The entity keeps its name and its existing ports and gets new ones. All vectors with two elements are indexed by socket: 0 is the MEGA65's port 1, 1 is port 2.

```vhdl
   -- Amiga mice (issue #190)
   amiga_i     : in  std_logic_vector(1 downto 0);   -- '1': the socket has an Amiga mouse

   -- right click with the left button of an Amiga mouse while the MEGA key is held (section 5.1)
   amiga_rclick_i : in  std_logic_vector(1 downto 0);   -- '1': the switch of the socket is on
   mega_key_n_i   : in  std_logic;                      -- low active: the MEGA key is pressed

   -- paddle values of the two C64 ports as the core expects them (inverted), behind the port switcher
   pot1_x_i    : in  std_logic_vector(7 downto 0);   -- measured
   pot1_y_i    : in  std_logic_vector(7 downto 0);
   pot2_x_i    : in  std_logic_vector(7 downto 0);
   pot2_y_i    : in  std_logic_vector(7 downto 0);
   pot1_x_o    : out std_logic_vector(7 downto 0);   -- measured, or the position of an Amiga mouse
   pot1_y_o    : out std_logic_vector(7 downto 0);
   pot2_x_o    : out std_logic_vector(7 downto 0);
   pot2_y_o    : out std_logic_vector(7 downto 0)
```

* Two instances of `amiga_mouse`, one per socket, on the raw pins, `enable_i` from `amiga_i`. Its `meas_x_i` and `meas_y_i` are the true measured values of that socket: the measured values arrive already switched to C64 ports and inverted, so socket s takes the values of C64 port s when the ports are not flipped and of the other port when they are, and inverts them.
* For a socket in Amiga mode, the four debounced direction lines are replaced before the port switcher: up is `right_btn_n_o`, down is `middle_btn_n_o`, left and right are '1'. The fire line is the debounced fire line as before (the left button). Section 5.1 turns a press of the left button into a right click on these two lines. The port switcher and the on/off switches of the Shell then work on these lines as on those of a joystick.
* `potN_x_o` and `potN_y_o` of a C64 port are the inverted `pot_x_o` and `pot_y_o` of the `amiga_mouse` of the socket that is connected to that C64 port, if that socket is in Amiga mode; otherwise they are `potN_x_i` and `potN_y_i`, unchanged.
* The paddle outputs do not depend on the on/off switches of the Shell (as before), and `reset_n` resets the debouncers only, not the mice.
* With `amiga_i` at "00" the ten joystick outputs and the four paddle outputs are exactly what they were without the new ports.

### 5.1 Right click with the MEGA key

The key: `m2m_keyb.vhd` has the output `mega_key_n_o` (low active), a register that takes over the state of key number 61, the MEGA key, whenever the scan of the keyboard is at that key (the scan visits every key once per 1.11 ms, about 900 times per second, and debounces it). It is '1' from power-up until the first visit. The output follows a press of the key within 1.6 ms and a release within 2.7 ms: one frame of the serial keyboard link (0.46 ms) plus one scan, and for a release one more scan, because the scanner reports a release only after a whole scan without the key. Like `capslock_n_o` it does not depend on `enable_core_i`. `framework.vhd` connects it to `mega_key_n_i` of the debouncer; both are in the core clock domain. What the core gets from the keyboard (`key_num_o`, `key_pressed_n_o`) does not change: the C64 keeps seeing the key as its Commodore key.

The rule, per socket s: let f be the debounced fire line of the socket (low active, the left button) and q a flip-flop of the socket that starts at '0' and has no reset.

* At every clock edge at which f is '1' (the button is released), q takes the value of `amiga_i(s) and amiga_rclick_i(s) and not mega_key_n_i`. While f is '0', q keeps its value. During a press, q therefore says whether the key was held, with the switch on and the socket in Amiga mode, when the button went down.
* r = `q and amiga_i(s) and amiga_rclick_i(s)`: this press is a right click.
* The fire line of the socket in front of the port switcher is `f or r`.
* The up line of a socket in Amiga mode in front of the port switcher is `right_btn_n_o and (f or not r)`: pressed by the right button of the device or by a press that is a right click.

These are combinational functions of f, q and the settings, so the two lines pass no additional register.

What follows from the rule:

* The key at the moment the button goes down decides for the whole press. Releasing the key before the button does not end the right click with a left click, and pressing the key during a left click does not turn it into a right click.
* In the clock cycle in which f turns '0', q already has the value for this press. The fire line is therefore never low in any clock cycle of a right click, and the up line is never pulled low by a left click; a program that polls the CIA in a loop would catch a pulse of a single clock cycle.
* While `amiga_rclick_i(s)` or `amiga_i(s)` is '0', r is '0' in every clock cycle, and all lines of the socket are exactly what they are without this section, whatever the key does. With `amiga_rclick_i` at "00" the ten joystick outputs and the four paddle outputs are identical, clock cycle by clock cycle, to those of the entity without the two ports.
* The two sockets share the key and nothing else.
* The middle button, the paddle values and the direction lines left and right are not involved.

## 6. Paddles: `mouse_input.vhdl`

The measurement runs in the QNICE clock domain with a tick of 1 µs. A cycle so far: at tick 0 the discharge is switched on, at tick 256 it is switched off, in each of the ticks 258 to 512 the counter of a pin is incremented if the comparator output of that pin is '0', and at tick 513 the four counters are latched as the results and cleared. A cycle has 514 ticks, a result is 0 to 255.

New ports: `atari_paddles_a` and `atari_paddles_b` ('1': the paddles of that socket have 1 MOhm potentiometers; a is port 1, b is port 2).

* At the latch tick of a cycle, the two inputs are taken over as the modes of the next cycle. A cycle is long if at least one mode is Atari, otherwise it is short and exactly as described above.
* A long cycle has the same first 513 ticks; its count window goes on to tick 767 and it latches at tick 768 (769 ticks). A 1351 that sees no new discharge may drive its lines again 832 µs after the last one (section 6 of `RESEARCH-paddles.md`); the long cycle stays below that.
* A pin of a socket in C64 mode is counted in the ticks 258 to 512 in both kinds of cycle. Its result is the same in a long cycle as in a short one.
* A pin of a socket in Atari mode is counted in the ticks 258 to 767 (510 ticks). Its result is half the count, rounded down: 0 to 255, with 2 µs per step instead of 1 µs.
* The four comparator inputs pass a two-stage synchronizer before they are counted. They are asynchronous to the clock, and an edge at the clock edge of a tick could otherwise be taken by some bits of a counter and not by others, which at a carry gives a value that was never measured.
* Nothing else changes: the tick, the discharge time, the Amiga part of the file (it stays switched off by its inputs), and the inversion and port switching of the four results in `qnice_wrapper.vhd`.

The factor 2 is a ratio, not a calibration: the threshold of the comparator, the tolerance of the capacitor and the voltage of the port cancel out. A nominal Atari paddle (1 MOhm) reads like a 500 kOhm paddle within about one count; the units that were measured (790 to 840 kOhm) read like 400 to 420 kOhm, a little below a Commodore paddle (470 kOhm nominal). The exact ratio 1000/470 would bring such a unit closer to the point where it no longer reaches 255 at the end of its rotation, which is worse for a game than a slightly shorter usable rotation.

A pin that never charges inside its window reads 255 in both modes (nothing connected), and a pin that is connected to +5 V reads 0 (the second and third button of some joysticks).

As long as both mode inputs are '0' at every latch tick, the outputs `pot_drain`, `pota_x`, `pota_y`, `potb_x` and `potb_y` are identical, clock cycle by clock cycle, to those of the file before the change with its four comparator inputs delayed by the two clock cycles (40 ns) of the synchronizer.

## 7. Crossing of the paddle values into the core clock domain

The four results (32 bits) change together once per cycle and cross from the QNICE clock to the core clock. They cross through `cdc_stable` (the value is taken over when two consecutive samples are equal), not through the per-bit synchronizers of `xpm_cdc_array_single`: with those, the core clock can sample some bits of a value before and some after a change, and a C64 program that reads the SID register in that clock cycle gets a value that was never measured, for a 1351 a jump of up to 32 units. The other signals of `i_qnice2main` stay where they are (the vector is 32 bits shorter: 839 bits).

Timing: `CORE/CORE.xdc` declares the clock pair QNICE clock and core clock a false path in both directions, and a false path outranks the `set_max_delay` that `M2M/common.xdc` attaches to every `cdc_stable`. The 32 paths of this crossing are therefore not timed, like the per-bit synchronizers before them. `cdc_stable` delivers a consistent value as long as the 32 bits arrive within one core clock period (30 ns) of each other; the routes of a small bus between two neighboring registers differ by a few nanoseconds, and the source holds each value for half a millisecond. A `set_bus_skew` on these paths would turn this margin into a checked property.

## 8. Menu and ports of the core

`CORE/vhdl/config.vhd`: the section "Input Devices" and the submenus "Mouse" and "Paddles" (24 menu lines).

* Four radio groups with two items each: `OPTM_G_MOUSE_P1` (43), `OPTM_G_MOUSE_P2` (44), `OPTM_G_PADDLES_P1` (45), `OPTM_G_PADDLES_P2` (46). "C64" is the default of each group.
* Two single-select items that are off by default: `OPTM_G_MOUSE_P1_RCLICK` (47) with the text ` #1: MEGA+left = right`, directly behind "Port 1: Amiga", and `OPTM_G_MOUSE_P2_RCLICK` (48) with the text ` #2: MEGA+left = right`, directly behind "Port 2: Amiga". Each is a dependent line that is only visible while the Amiga item of its port is selected: `OPTM_DEP(OPTM_G_MOUSE_P1, 1)` and `OPTM_DEP(OPTM_G_MOUSE_P2, 1)`. A hidden item keeps its state, in the menu and in the config file.

`CORE/vhdl/mega65.vhd`: the constants `C_MENU_MOUSE_P1_AMIGA`, `C_MENU_MOUSE_P2_AMIGA`, `C_MENU_PADDLES_P1_ATARI` and `C_MENU_PADDLES_P2_ATARI` are the menu bits of the four items that are not the default, `C_MENU_MOUSE_P1_RCLICK` and `C_MENU_MOUSE_P2_RCLICK` those of the two switches, and three ports of `MEGA65_Core` carry them (index 0 is the MEGA65's port 1, index 1 is port 2):

| Port | Clock domain | '1' means | Goes to |
|---|---|---|---|
| `qnice_paddle_atari_o(1 downto 0)` | QNICE | Atari CX30 paddles | `framework.vhd`, `qnice_wrapper.vhd`, `mouse_input.vhdl` |
| `main_mouse_amiga_o(1 downto 0)` | core | Amiga mouse | `framework.vhd`, `debouncer.vhd` |
| `main_mouse_rclick_o(1 downto 0)` | core | the switch "MEGA+left = right" is on | `framework.vhd` (`main_mouse_rclick_i`), `debouncer.vhd` (`amiga_rclick_i`) |

Each bit of the first two ports is the menu bit of the item that is not the default. The Shell writes the bits of a radio group one after the other; while neither bit of a group is set, the setting therefore reads as "C64". `main_mouse_rclick_o` is the plain menu bit of the switch, also while the switch is hidden; the debouncer combines it with the Amiga setting (section 5.1).

## 9. Verification

Benches under `CORE/vhdl/test/`, each with a `run.sh` that ends with `RESULT: PASS` and with mutants that have to fail:

* `tb_amiga_mouse`: the decoder against a model of the mouse (speeds from single steps to 20,000 counts per second, both directions, both axes, chatter on every edge, pulses shorter than the filter, double transitions) and against the driver of the 1351 manual, called once per PAL frame and once per NTSC frame with jitter: the sum of the driver's results always equals the movement of the reported position, also above the rate limit and when the mouse reverses with a full backlog: no unit is lost or invented and no difference is misread. The buttons on the paddle pins with and without pull-up. The conditioning of the ports in all combinations of the port switcher, the Amiga settings and the on/off switches, and against the entity before the change for the setting "00". The right click with the MEGA key: the key and the button in every order, the key changing during a press and in the clock cycles around its start, both sockets, the right button of the device in parallel, through the port switcher and the on/off switches; a check in every clock cycle that the fire line is never low during a right click and that a left click never pulls the up line low; identity with the entity without the two ports while both switches are off, whatever the key does. The keyboard driver with a model of the keyboard: `mega_key_n_o` follows the MEGA key and no other key, also while the core is decoupled from the keyboard.
* `tb_paddles`: the paddle measurement against a model of the board circuit: identity with the file before the change in C64 mode for random and for non-monotonic comparator signals, the results and the cycle length in Atari mode and in mixed mode, changes of the modes at any time.
* The wiring of the new ports through `framework.vhd`, `qnice_wrapper.vhd` and the four board files, by analysis and elaboration against the real entity declarations as in `tb_capslock`.
* `M2M/rom/tests/menu_test.py`: the menu, the menu bits and the navigation into the two submenus; the two switches of the Mouse submenu are hidden while their port is set to "C64", appear directly behind the Amiga item otherwise and keep their state while they are hidden.
