## Comparison of clock frequencies

The MiSTer C64 core runs on a main clock of 32 times the C64 CPU clock (clock divider 32). The real
machines derive their clock from a crystal: PAL from 17.734475 MHz x 16 / 9, NTSC from the color
burst crystal 14.31818 MHz x 16 / 7.

### PAL (VIC-II 6569)

| Clock                                    | Main clock    | C64 CPU clock (divider 32) | Versus the real C64 |
|------------------------------------------|--------------:|---------------------------:|--------------------:|
| Real PAL C64                             | 31.527956 MHz | 985.249 kHz                |                     |
| MiSTer                                   | 31.527954 MHz | 985.249 kHz                | -0.05 ppm           |
| C64MEGA65 original clock                 | 31.527778 MHz | 985.243 kHz                | -5.6 ppm            |
| C64MEGA65 "HDMI: Flicker-free" clock     | 31.448993 MHz | 982.781 kHz                | -0.25 %             |

### NTSC (VIC-II 6567R8)

| Clock                                    | Main clock    | C64 CPU clock (divider 32) | Versus the real C64 |
|------------------------------------------|--------------:|---------------------------:|--------------------:|
| Real NTSC C64                            | 32.727273 MHz | 1022.727 kHz               |                     |
| MiSTer                                   | 32.727264 MHz | 1022.727 kHz               | -0.27 ppm           |
| C64MEGA65 original clock                 | 32.727273 MHz | 1022.727 kHz               | 0 ppm (exact)       |
| C64MEGA65 "HDMI: Flicker-free" clock     | 32.789700 MHz | 1024.678 kHz               | +0.19 %             |

### What the flicker-free clock does

With "HDMI: Flicker-free" switched on, the core alternates between the original clock and the
flicker-free clock of the active standard so that the C64 produces frames exactly as fast as the
HDMI output consumes them. The flicker-free clock is the one the core runs on almost all the time:

* PAL: the C64 natively runs at 50.124 Hz, the HDMI output at 50.000 Hz. The flicker-free clock
  (49.999 Hz) is the slower one, so in PAL the C64 runs 0.25 % slower than a real PAL C64.
* NTSC: the C64 natively runs at 59.826 Hz, the HDMI output at 59.94 Hz. The flicker-free clock
  (59.940 Hz) is the faster one, so in NTSC the C64 runs 0.19 % faster than a real NTSC C64.

The CIA time-of-day clock, the simulated 1541/1581 drives and the GEOS real-time clock use the
nominal clock of the active standard (31.527778 MHz in PAL, 32.727273 MHz in NTSC) as their
reference, so they move together with the C64 and the C64-to-drive speed ratio stays exact
(see [issue #2](https://github.com/MJoergen/C64MEGA65/issues/2)). Details in [ntsc.md](ntsc.md).
