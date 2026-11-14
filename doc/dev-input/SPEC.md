# Input devices: Amiga mouse and Atari CX30 paddles

Specification of the two features of GitHub issues [#190](https://github.com/MJoergen/C64MEGA65/issues/190) (Amiga mouse) and [#193](https://github.com/MJoergen/C64MEGA65/issues/193) (Atari CX30 paddles), first shipped in WIP-V6-A26. The facts behind the numbers are in `RESEARCH-amiga-mouse.md` and `RESEARCH-paddles.md`; the state of the work, the verification record and the open points are in `STATUS.md`.

## 1. What the user gets

The submenu "Advanced Settings" has a section "Input Devices" with three submenus: "Keyboard Shortcuts" (unchanged), "Mouse" and "Paddles".

```
 Mouse                        Paddles
 ──────────────────           ──────────────────
 Port 1: C64                  Port 1: C64
 Port 1: Amiga                Port 1: Atari CX30
 ──────────────────           ──────────────────
 Port 2: C64                  Port 2: C64
 Port 2: Amiga                Port 2: Atari CX30
 ──────────────────           ──────────────────
 Back                         Back
```

* "Port 1" and "Port 2" are the two sockets of the MEGA65. The setting describes the device that is plugged into that socket and travels with it when "Flip joystick ports" swaps the ports for the C64.
* "C64" is the default for all four settings and behaves exactly as every version before: joysticks, Commodore paddles, the 1351 and compatible mice and adapters.
* "Amiga" (Mouse): the port has an Amiga mouse. The core turns it into a Commodore 1351 in proportional mode, so every program with a 1351 driver works with it (GEOS, for example). The left button is the fire line, as on a 1351. The four direction lines of that port are hidden from the C64 while the setting is active, so the mouse cannot disturb the keyboard.
* "Atari CX30" (Paddles): the port has paddles with 1 MOhm potentiometers (Atari CX30 and CX30+) instead of the 470 kOhm of Commodore paddles. A C64 reaches the highest value 255 at about 250 to 350 kOhm, so a Commodore paddle uses half to three quarters of its rotation and an Atari paddle only a quarter to a third. With this setting the core measures with half the sensitivity: a 1 MOhm paddle then behaves like a 500 kOhm paddle, and the usable part of its rotation doubles.
* The two settings of a port are independent menu items but not independent devices: with "Amiga" selected, the paddle setting of that port has no effect on what the C64 reads.

Limits that come from the hardware:

* The right and the middle button of an Amiga mouse are switches to ground on pins 9 and 5, which are the paddle inputs. The board can only tell a pin that is pulled or driven up to +5 V from one that is not (section 2), so an original Amiga mouse has only its left button. Both buttons work with everything that holds the two pins high while the buttons are released: mice and adapters with an active output stage, a mouSTer in Amiga mode with firmware 3.23.5313 or newer and `activepotlines=true`, or any passive mouse behind a straight-through adapter with two resistors of about 2 kOhm from pin 7 to pin 9 and from pin 7 to pin 5. The right button is the up line as on a 1351, the middle button the down line as in the Micromys protocol. This is the experience and the mechanism of the Amiga core for the MEGA65 (AExp), whose documentation lists the devices.
* USB adapters with a polled wheel protocol (Micro Tom, for example) take every discharge of the paddle pins as a request and answer it with a short code on the movement lines. The decoder counts such a code forwards and backwards again, so the position does not drift, but the pointer can twitch. The cure is the one of the Amiga core: an extension cable with wire 5 cut, which costs the middle button and the wheel.
* Everything that is not an Atari paddle needs the paddle setting "C64" for its port: a 1351 (its position is encoded in steps of 2 µs), a KoalaPad, Commodore paddles.
* While at least one port is set to "Atari CX30", the measuring cycle of both ports is longer (section 6), because one signal discharges all four paddle pins. Devices on the other port measure the same values as before. A 1351 on the other port synchronizes itself to the discharge and should not mind the longer cycle; this combination is untested.

## 2. The hardware

Schematics of the Trenz boards TE0765-03 (R3) and TE0765-06 (R6), sheets `JOY.SchDoc` and `B15.SchDoc`; R4 and R5 are the same in these parts.

* Digital lines (pins 1 to 4 and 6 of each port): 4.7 kOhm pull-up to the switched 5 V of the ports, a buffer with 3.3 V supply, the FPGA pin. No RC filter. R5 and R6 can also pull each line low through an open-drain driver; the core never does (`keyboard.vhd` ties all joystick outputs to '1').
* Paddle pins (9 and 5 of each port, `paddle_i(3 downto 0)`): the pin, 1 kOhm in series, a node with 1.2 nF to ground, a 2N7002 that discharges the node while `paddle_drain_o` is '1' (one signal for all four), and a NC7SZ126 at 3.3 V as the comparator. The FPGA sees '0' while the node is below the threshold of the buffer. There is no pull-up: the capacitor only charges through whatever connects the pin to +5 V (pin 7), which is the potentiometer of a paddle or the output stage of a 1351.
* Consequence 1: the time until the comparator output turns '1' is proportional to the resistance, t = (R + 1 kOhm) x 1.2 nF x ln(5 V / (5 V - Vth)). A scale factor on the measured time is therefore exactly a scale factor on the resistance.
* Consequence 2: a pin that is open and a pin that is shorted to ground look the same (the capacitor never charges, the value is 255).

## 3. Signal flow

```
 QNICE clock (50 MHz)                               core clock (31.5 MHz PAL, 32.7 MHz NTSC)

 paddle_i(3..0) ──► mouse_input ──► flip, invert ──► cdc_stable ──┐
 paddle_drain_o ◄──┘    ▲          (qnice_wrapper)                 │
                        │                                          ▼
 qnice_paddle_atari ────┘        joystick pins (raw) ────────► debouncer ──► main_pot1_x .. main_pot2_y ──► SID
 (menu, per socket)              main_mouse_amiga ───────────►  2 x amiga_mouse
                                 (menu, per socket)             flip, on/off ──► main_joy1 / main_joy2 lines ──► CIA1
```

| File | Role |
|---|---|
| `M2M/vhdl/amiga_mouse.vhd` | new: Amiga mouse of one socket as a 1351 (section 4) |
| `M2M/vhdl/debouncer.vhd` | conditioning of the two ports: debouncing, Amiga mice, port switcher, on/off (section 5) |
| `M2M/vhdl/controllers/M65/mouse_input.vhdl` | paddle measurement, with the Atari mode (section 6) |
| `M2M/vhdl/qnice_wrapper.vhd`, `M2M/vhdl/framework.vhd`, `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd` | wiring; `framework.vhd` also holds the clock domain crossing of the paddle values (section 7) |
| `CORE/vhdl/mega65.vhd`, `CORE/vhdl/config.vhd` | menu items and the two ports that carry the four settings (section 8) |

## 4. The Amiga mouse: `amiga_mouse.vhd`

One instance per socket, in the core clock domain, fed by the raw pins. The 1 ms debouncer is not in this path: at 200 counts per inch a line of the mouse keeps its level for 1 ms at a hand speed of 25 cm/s and for 0.25 ms at 1 m/s. `G_CLK_FREQ` is the PAL frequency of the core clock, as for the debouncer; in NTSC mode the clock is 3.8 % faster and all times of this section are that much shorter.

```vhdl
entity amiga_mouse is
   generic (
      G_CLK_FREQ    : natural;             -- frequency of clk_i in Hz
      G_FILTER_NS   : natural := 2000;     -- a line needs to be stable for this time before a change counts
      G_STEP_US     : natural := 400;      -- shortest time between two steps of the reported position
      G_BACKLOG     : natural := 127;      -- counts that may wait for the rate limiter; further ones are dropped
      G_CONFIRM_US  : natural := 4000;     -- a button on a paddle pin needs to be stable for this time
      G_STUCK_MS    : natural := 30000     -- a button on a paddle pin that is pressed for longer is released
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

Each of the four lines passes two flip-flops (attribute `async_reg`) and then a filter: the filtered value takes over the synchronized value once that has been stable for `G_FILTER_NS` (2 µs, 64 clock cycles). All four lines have the same delay, so the order of the edges is kept. The shortest legitimate stable time of a line is about 25 µs (an optical mouse with 1000 counts per inch at 2 m/s). The comparator outputs of the mouse are open collector with pull-ups (3.3 kOhm in the mouse, 4.7 kOhm on the board), and the buffer on the board has no Schmitt trigger: the filter removes the chatter of a slow rising edge and short spikes. Synchronizer and filter always run, also while `enable_i` is '0'.

### 4.2 Decoder

Every edge counts, four counts per cycle of a pair, like the counters of the Amiga's Denise.

| Axis | Pair (first, second) | Position +1 for the sequence (and every rotation of it) | Meaning of +1 |
|---|---|---|---|
| X | (HQ, H) = (right, down) = (pin 4, pin 2) | 11, 10, 00, 01, 11 | mouse moves to the right |
| Y | (VQ, V) = (left, up) = (pin 3, pin 1) | 11, 01, 00, 10, 11 | mouse moves up (away from the user) |

The reverse sequence counts -1. A change of both lines of a pair in the same clock cycle counts nothing; the decoder continues from the new state. X to the right and Y upwards are the conventions of the 1351 (its drivers subtract the Y movement from the screen position) and of the Amiga's counters (which count Y downwards, hence the opposite sequence).

While `enable_i` is '0' nothing is counted and the backlog (4.3) is empty; the decoder keeps following the state of the lines, so that no count is produced at the moment `enable_i` turns '1'.

### 4.3 Backlog and rate limiter

A 1351 driver computes the movement since its last call as the difference of two POT values modulo 128 and takes 64 to 127 as negative. A mouse that delivers more than 63 steps between two calls therefore moves the pointer in the wrong direction; with one step per count, a 200 cpi mouse reaches that at 40 cm/s when the driver runs once per PAL frame, and a 1000 cpi mouse at 8 cm/s. The decoder prevents this:

* The counts of an axis go into a backlog, a signed number between -`G_BACKLOG` and +`G_BACKLOG` (127). A count that would exceed the bound is dropped.
* A free-running tick every `G_STEP_US` (400 µs) moves one count from the backlog into the position: position +1 and backlog -1 if the backlog is positive, the reverse if it is negative.

The position therefore never changes by more than 50 steps in 20 ms (42 in an NTSC frame), which leaves a driver that is called once per frame 13 steps, or 5 ms of delay of its call, before the difference becomes ambiguous. While the mouse delivers fewer than 2500 counts per second (32 cm/s at 200 cpi), the backlog stays nearly empty and the position follows within about a millisecond. A faster movement saturates the pointer speed at 2500 steps per second, which is 1250 position units of a 1351 driver per second or a screen width of 320 units in a quarter of a second; after the mouse stops, the pointer moves on for at most 51 ms.

### 4.4 The position as POT values

The position of each axis is a 7-bit counter that wraps around; one count of the mouse is one step. The POT value carries its upper six bits: `pot(7) = position(6)`, `pot(6) = not position(6)`, `pot(5 downto 1) = position(5 downto 1)`, `pot(0) = '0'`. That is 64 plus the position with bit 0 cleared: the even values from `$40` to `$BE`, the range of a real 1351, whose position also sits in bits 6 to 1 (its bit 0 is noise). Two counts of the mouse are one position unit for a 1351 driver, which is the scale of the MEGA65 core and of VICE. Bit 0 stays clear because the drivers halve the difference of two readings and take the new reading as their next reference: an odd difference would cost half a unit at every call, a clear bit 0 makes the driver follow the mouse exactly. The position starts at 0 and keeps its value while `enable_i` is '0'.

### 4.5 Right and middle button

The two buttons are derived from the measured values of the paddle pins of the socket (`meas_x_i` for the right button, `meas_y_i` for the middle button), each with its own instance of the same logic:

* A value below 128 means that something pulls the pin up to +5 V: a pull-up resistor exists and the button is released. This sets a flag "pull-up seen".
* A value of 192 or more means that nothing pulls the pin up. If the flag is set, the button is pressed. If the flag is not set, the mouse has no pull-up and the button is never reported.
* Values from 128 to 191 change nothing.
* A change of the reported state needs its condition to hold for `G_CONFIRM_US` (4 ms, several measuring cycles) without interruption.
* A button that is reported as pressed for `G_STUCK_MS` (30 s) without interruption is released and the flag is cleared; it is set again by the next value below 128. This covers the exchange of a mouse with pull-ups for one without while the setting stays "Amiga": without this rule the right button of the second mouse would be pressed forever.
* `enable_i` at '0' clears the flag and releases the button.

A pin that is driven high or pulled up with 2 kOhm measures 0 to 3 when the button is released, a 22 kOhm pull-up 11 to 16, and all measure 255 when the button is pressed; the thresholds accept pull-ups up to about 150 kOhm. The Amiga core for the MEGA65 uses the same two rules (a button counts only after its line has been seen high; 30 seconds of "pressed" clear that) in the field.

## 5. Conditioning of the two ports: `debouncer.vhd`

The entity keeps its name and its existing ports and gets new ones. All vectors with two elements are indexed by socket: 0 is the MEGA65's port 1, 1 is port 2.

```vhdl
   -- Amiga mice (issue #190)
   amiga_i     : in  std_logic_vector(1 downto 0);   -- '1': the socket has an Amiga mouse

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
* For a socket in Amiga mode, the four debounced direction lines are replaced before the port switcher: up is `right_btn_n_o`, down is `middle_btn_n_o`, left and right are '1'. The fire line is the debounced fire line as before (the left button). The port switcher and the on/off switches of the Shell then work on these lines as on those of a joystick.
* `potN_x_o` and `potN_y_o` of a C64 port are the inverted `pot_x_o` and `pot_y_o` of the `amiga_mouse` of the socket that is connected to that C64 port, if that socket is in Amiga mode; otherwise they are `potN_x_i` and `potN_y_i`, unchanged.
* With `amiga_i` at "00" the ten joystick outputs and the four paddle outputs are exactly what they were without the new ports.

## 6. Paddles: `mouse_input.vhdl`

The measurement runs in the QNICE clock domain with a tick of 1 µs. A cycle so far: at tick 0 the discharge is switched on, at tick 256 it is switched off, in each of the ticks 258 to 512 the counter of a pin is incremented if the comparator output of that pin is '0', and at tick 513 the four counters are latched as the results and cleared. A cycle has 514 ticks, a result is 0 to 255.

New ports: `atari_paddles_a` and `atari_paddles_b` ('1': the paddles of that socket have 1 MOhm potentiometers; a is port 1, b is port 2).

* At the latch tick of a cycle, the two inputs are taken over as the modes of the next cycle. A cycle is long if at least one mode is Atari, otherwise it is short and exactly as described above.
* A long cycle has the same first 513 ticks; its count window goes on to tick 767 and it latches at tick 768 (769 ticks). A 1351 that sees no new discharge may drive its lines again 832 µs after the last one (section 6 of `RESEARCH-paddles.md`); the long cycle stays below that.
* A pin of a socket in C64 mode is counted in the ticks 258 to 512 in both kinds of cycle. Its result is the same in a long cycle as in a short one.
* A pin of a socket in Atari mode is counted in the ticks 258 to 767 (510 ticks). Its result is half the count, rounded down: 0 to 255, with 2 µs per step instead of 1 µs.
* The four comparator inputs pass a two-stage synchronizer before they are counted. They are asynchronous to the clock, and an edge at the clock edge of a tick could otherwise be taken by some bits of a counter and not by others, which at a carry gives a value that was never measured.
* Nothing else changes: the tick, the discharge time, the Amiga part of the file (it stays switched off by its inputs), and the inversion and port switching of the four results in `qnice_wrapper.vhd`.

The factor 2 is a ratio, not a calibration: the threshold of the comparator, the tolerance of the capacitor and the voltage of the port cancel out, so it is right on every board. A nominal Atari paddle (1 MOhm) reads like a 500 kOhm paddle; the units that were measured (790 to 840 kOhm) read like 400 to 420 kOhm, a little below a Commodore paddle (470 kOhm nominal). The exact ratio 1000/470 would bring such a unit closer to the point where it no longer reaches 255 at the end of its rotation, which is worse for a game than a slightly shorter usable rotation.

A pin that never charges inside its window reads 255 in both modes (nothing connected), and a pin that is connected to +5 V reads 0 (the second and third button of some joysticks).

As long as both mode inputs are '0' at every latch tick, the outputs `pot_drain`, `pota_x`, `pota_y`, `potb_x` and `potb_y` are identical, clock cycle by clock cycle, to those of the file before the change with its four comparator inputs delayed by the two clock cycles (40 ns) of the synchronizer.

## 7. Crossing of the paddle values into the core clock domain

The four results (32 bits) change together once per cycle and cross from the QNICE clock to the core clock. They cross through `cdc_stable` (the value is taken over when two consecutive samples are equal), not through the per-bit synchronizers of `xpm_cdc_array_single`: with those, the core clock can sample some bits of a value before and some after a change, and a C64 program that reads the SID register in that clock cycle gets a value that was never measured, for a 1351 a jump of up to 32 units. The other signals of `i_qnice2main` stay where they are. The constraint for `cdc_stable` in `M2M/common.xdc` covers the new instance.

## 8. Menu and ports of the core

`CORE/vhdl/config.vhd`: the section "Input Devices" and the submenus "Mouse" and "Paddles" (22 menu lines), four radio groups with two items each: `OPTM_G_MOUSE_P1` (43), `OPTM_G_MOUSE_P2` (44), `OPTM_G_PADDLES_P1` (45), `OPTM_G_PADDLES_P2` (46). "C64" is the default of each group.

`CORE/vhdl/mega65.vhd`: the constants `C_MENU_MOUSE_P1_AMIGA`, `C_MENU_MOUSE_P2_AMIGA`, `C_MENU_PADDLES_P1_ATARI` and `C_MENU_PADDLES_P2_ATARI` are the menu bits of the four items that are not the default, and two ports of `MEGA65_Core` carry them (index 0 is the MEGA65's port 1, index 1 is port 2):

| Port | Clock domain | '1' means | Goes to |
|---|---|---|---|
| `qnice_paddle_atari_o(1 downto 0)` | QNICE | Atari CX30 paddles | `framework.vhd`, `qnice_wrapper.vhd`, `mouse_input.vhdl` |
| `main_mouse_amiga_o(1 downto 0)` | core | Amiga mouse | `framework.vhd`, `debouncer.vhd` |

Each bit is the menu bit of the item that is not the default. The Shell writes the bits of a radio group one after the other; while neither bit of a group is set, the setting therefore reads as "C64".

## 9. Verification

Benches under `CORE/vhdl/test/`, each with a `run.sh` that ends with `RESULT: PASS` and with mutants that have to fail:

* `tb_amiga_mouse`: the decoder against a model of the mouse (speeds from single steps to 20,000 counts per second, both directions, both axes, chatter on every edge, pulses shorter than the filter, double transitions) and against the driver of the 1351 manual, called once per PAL frame and once per NTSC frame with jitter: up to the rate limit the driver follows the mouse exactly, above it the driver never sees a movement in the wrong direction. The buttons on the paddle pins with and without pull-up. The conditioning of the ports in all combinations of the port switcher, the Amiga settings and the on/off switches, and against the entity before the change for the setting "00".
* `tb_paddles`: the paddle measurement against a model of the board circuit: identity with the file before the change in C64 mode for random and for non-monotonic comparator signals, the results and the cycle length in Atari mode and in mixed mode, changes of the modes at any time.
* The wiring of the new ports through `framework.vhd`, `qnice_wrapper.vhd` and the four board files, by analysis and elaboration against the real entity declarations as in `tb_capslock`.
* `M2M/rom/tests/menu_test.py`: the menu, the menu bits and the navigation into the two submenus.
