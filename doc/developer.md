C64 for MEGA65 developer documentation
======================================

Building the core
-----------------

Refer to the
[MiSTer2MEGA65 documentation](https://github.com/sy2002/MiSTer2MEGA65/wiki)
for more details and for operating system specific details: You need a `bash`
or compatible shell, the GCC compiler environment including make, `awk` and
other typical tools.

```bash
git clone https://github.com/MJoergen/C64MEGA65.git
cd C64MEGA65
git submodule update --init --recursive
cd M2M/QNICE/tools/
./make-toolchain.sh 
```

Answer all questions that you are being asked while the QNICE tool chain is
being built by pressing Enter. You can check the success of the process by
checking if the Monitor is available as .rom file:

```bash
ls -l ../monitor/monitor.rom
```

Now build the Shell (firmware for on-screen-menu, mounting `D64` images on
an SD card, etc.):

```bash
cd ../../../CORE/m2m-rom/
./make_rom.sh
ls -l m2m-rom.rom
```

If everything went well, then the last command will generate the expected
output.

Now use Vivado to open `CORE/CORE-R3.xpr` to synthesize, implement and
generate the bitstream.

Making a `.cor` file
--------------------

### Get `bit2core`

* [Linux and Windows binaries](https://builder.mega65.org/job/mega65-tools/job/development/)
* [macOS binaries](https://github.com/MEGA65/mega65-tools/releases/tag/CI-development-latest)
* [GitHub repository](https://github.com/MEGA65/mega65-tools)

### Use `bit2core`

The C64 core can run cartridges that are inserted into the MEGA65's expansion
port. To make sure that the MEGA65's CORE #0 core selection logic knows that
and automatically starts the C64 core if an appropriate C64 cartridge is
inserted, make sure that you use the correct flags for the `bit2core` tool:

```bash
bit2core mega65r3 C64M65-WIP-V5-A23.bit "C64 for MEGA65" "WIP-V5-A23" C64M65-WIP-V5-A23.cor "=default,c64cart+c64cart"
```

Conventions for version info in `*.cor` files:

* Releases are called "V4", "V5", etc.
* Alpha releases are called "WIP-Vx-Ay", where `x` is the upcoming next major
  release that this alpha release works towards and y is the version of the
  alpha release, just counting upwards.

Configuration file
------------------

The FAT32 writing abilities of the M2M framework are currently limited: It
can only change data in existing files such as disk images or configuration
files. This means the current version of the M2M framework is not able to
create new files on an SD card and since it is also not able to change the
length of any file (e.g. append data), you always need to make sure that
there is a valid `c64mega65-<version>` configuration file located in the
`/c64` folder on the SD card, where `<version>` is the value of the
`CORE_VERSION` constant in `CORE/vhdl/config.vhd` (e.g.
`c64mega65-WIP-V6-A15`).

This is how you create a valid configuration file that uses default
settings:

```bash
./make_config.sh c64mega65-WIP-V6-A15 auto
```

The size of the configuration file needs to be equal to the constant
`OPTM_SIZE` in `CORE/vhdl/config.vhd`. The `auto` parameter extracts this
information automatically. The script is located in `M2M/tools`.

The reason the file name carries the version is so that several core
versions can keep their settings side by side on the same SD card; see
[GitHub issue #182](https://github.com/MJoergen/C64MEGA65/issues/182). On
release builds, `make_release.py` generates this file automatically with
the correct version suffix.

Debug mode
----------

If you do not have a
[JTAG adapter](https://files.mega65.org?ar=3c388c8c-bc3f-461b-84bb-e12dfd479ae2),
then you cannot use the debug mode.

The C64 core - like all MEGA65 cores powered by the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65)
framework - has a debug mode that consists of a real-time log of various system
states and an interactive debug console.

To access the log and the console, connect a serial terminal to the MEGA65
using the JTAG adapter while making sure that the serial terminal's parameters
are set to 115,200 baud 8-N-1, no flow control such as XON/XOFF, RTS/CTS,
DTR/DSR. Set any terminal emulation to "None" and if you can configure it,
set the send mode to "Interactive" (instead of things like "Line buffered").

To switch from the real-time log to the interactive mode, press
<kbd>Run/Stop</kbd> + <kbd>Cursor Up</kbd> and then while holding these press
<kbd>Help</kbd>.

Learn more about the debug mode in the MiSTer2MEGA65 Wiki in the "Hello World"
chapter, section
[Understanding the QNICE debug console](https://github.com/sy2002/MiSTer2MEGA65/wiki/3.-%22Hello-World%22-Tutorial#understanding-the-qnice-debug-console).

Main differences compared to the MiSTer core
--------------------------------------------

### Main clock speed

The Intel FPGA (platform for MiSTer) is able to synthesize clock frequencies with an
accuracy of around 1 Hz.  This is not possible on the Xilinx FPGA used by the MEGA65.

For instance, the official C64 clock speed (in PAL mode) is 0.985248 MHz.

On MiSTer the PLL generates a clock with 31.527954 MHz, which after a clock divider by 32
leads to a core clock frequency of 0.985249 MHz. In other words, MiSTer achieves practically
perfect accuracy of clock speed.

Our old core (before the flicker fix) had a PLL clock frequency of 31.527778 MHz, which
after the clock divider leads to C64 core frequency of 0.985243 MHz. So from a practical
point of view, this is still very close.

### Visual artifacts and dynamic HDMI flicker-fix

The official C64 has a frame rate of 985248/312/63 = 50.125 Hz. Since this is not exactly
50 Hz, this will inevitably lead to flickering and/or screen tearing when viewing on a
HDMI monitor. The reason is that HDMI only allows a pre-defined set of screen resolutions
and frame rates. The difference between the C64 frame rate of 50.125 Hz and the monitor
frequency of 50 Hz leads to tearing at a frequency of 0.125 Hz, i.e.  roughly every eight
seconds.

The "Dynamic HDMI flicker-fix" is meant to eliminate this screen tearing. This is done by
slowing down the core by approx 0.125/50.125 = 0.25%. The goal is to have the core
generate a frame rate of exactly 50 Hz. However, this requires a PLL frequency of
50\*63\*312\*32 = 31.449600 MHz, which unfortunately is not synthesizable on the Xilinx FPGA
in the MEGA65 (due to the before-mentioned limitations of the PLL).

The solution chosen is therefore to dynamically alternate the core frame rate between 50.1
Hz and 49.9 Hz. On average the core frame rate will be exactly 50 Hz, and this average is
achieved by continuously monitoring the input and output frame rates. More specifically,
the VGA-to-HDMI conversion is done by MiSTer's `ascal.vhd` module. Here the input frame
data is written to HyperRAM, and the output frame data is read from HyperRAM.

From a "helicopter-perspective", the `ascal.vhd` module acts as a regular FIFO, where the
filling level is determined by the difference between the current scan line generated by the
core, and the current scan line displayed on the HDMI. Whenever there is a FIFO underrun
or overflow, then visual screen tearing occurs.

So the "Dynamic HDMI flicker-free" works by continuously monitoring the FIFO level (i.e.
difference between input and output scan line), and - through a simple hysteresis
mechanism - switches between a "slow" core and a "fast" core. I.e. when the core is
running "slow" the FIFO filling is gradually decreasing, and when the core is running
"fast" the FIFO filling is gradually increasing.

For this to work, the PLL generates two different frequencies, and a glitch-free clock
multiplexer is subsequently used to dynamically switch between the two frequencies.

The M2M framework takes care of the FIFO level monitoring and the hysteresis, and outputs
two signals to the core, indicating when to switch over to the other clock frequency.  The
core may choose to ignore these signals, if the "Dynamic HDMI flicker-free" option is not
wanted.

Even though this "switching between two frame rates" works perfectly on the HDMI output,
it can lead to flickering on some VGA monitors. So for this reason, it is important to
have the option of disabling this feature.

### Keyboard

MiSTer uses a PS/2 keyboard and then translates the PS/2 keystrokes into
signals for the C64's CIA. This is done in `fpga64_keyboard.vhd` (located in
the file `CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd`).

Since the MEGA65 has a built-in keyboard, we routed the CIA signals on the
level of `fpga64_sid_iec` (located in the file
`CORE/C64_MiSTerMEGA65/rtl/fpga64_sid_iec.vhd`)
so that our own `keyboard` entity (located in the file
`CORE/vhdl/keyboard.vhd`) can directly and latency-free generate the
appropriate signals for the C64's CIA.

### PHI2

For supporting hardware cartridges, one needs to output a correct PHI2
signal to the Expansion port. MiSTer did not offer a PHI2 signal. We added
it to `fpga64_sid_iec`. The exact timing of this PHI2 signal is very important (and
fragile), because it directly translates into a hardware signal used by the various
hardware cartridges.

### PLA

The MiSTer C64 core architecture does not "literally" implement a PLA chip
but bundles the PLA together with the ROMs and other logic in a VHDL entity
called `fpga64_buslogic` and located in
`CORE/C64_MiSTerMEGA65/rtl/fpga64_buslogic.vhd`.

We bugfixed and enhanced `fpga64_buslogic` and `fpga64_sid_iec` so that the
simulated PLA behaves according to the [correct logic formulas](PLA.md).

### Simulated cartridges

On the MiSTer platform, the simulated cartridges (`*.crt`) are loaded into SDRAM, and the
C64 CPU executes code directly from there. On the MEGA65 platform, the HyperRAM is shared
between the core and the framework (specifically the `ascal.vhd` VGA-to-HDMI converter).
Due to the behaviour and requirements of the `ascal.vhd`, the HyperRAM can be busy for
extended periods of time. This can lead to considerable latency when the core accesses
HyperRAM, i.e. more than 500 ns, which is the half clock cycle the C64 CPU has the bus.
Currently, the worst-case latency is around 1500 ns. In other words, it's not possible for
the C64 CPU to execute code directly from the HyperRAM, in the same way the MiSTer does.

Instead, we've taken a different approach, where we read the current ROM bank into a local
BRAM cache. In all the existing cartridge types, the switching of banks happen during a
read or write access to `$DExx` or `$DFxx`. If such a bank switching requires updating the
local BRAM cache, then the CPU is momentarily paused (using the DMA signal) while the BRAM
is filled. The maximum data rate available from the HyperRAM is 200 MB/second. The
`ascal.vhd` uses on average 50 % of this bandwidth.  Therefore, the time it takes to fill
one BRAM bank is on average 8192/100 = 82 CPU cycles.

Some cartridges switch banks multiple times each second (or even each frame), and
therefore a caching mechanism has been added, so the last eight banks used are stored in
BRAM.

While the above is not completely cycle accurate, in almost all cases the extra delays
caused by bank loading occur only during game initialization or when changing levels. In
practice, the player does not notice.

Another difference between MiSTer and our core is that the MiSTer decodes the file on the
fly and only stores the actual ROM bank contents in SDRAM. In our implementation we
store the complete CRT file (including all headers) in HyperRAM.

