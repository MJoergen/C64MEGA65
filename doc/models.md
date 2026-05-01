C64 for MEGA65 on different MEGA65 models
=========================================

Choose the right core variant for your hardware
-----------------------------------------------

### TL;DR

If your MEGA65 was manufactured before 2024, then choose
`C64MEGA65-V6.0-R3.cor` otherwise choose `C64MEGA65-V6.0-R6.cor`.

### Details

We are supporting these MEGA65 models: R3/R3A, R4, R5 and R6/R6A. Use
the following table to ensure that you select and flash the correct `.cor`
from the [ZIP file](https://files.mega65.org?id=896a012f-59e4-456c-b91f-7e989b958241).

| MEGA65 model   |   Years   | File name             | Comment
|:--------------:|:---------:|:---------------------:|-------------------------
| R2             | 2019-2020 | &lt;none&gt;          | R2 is a very rare pre-series model, only 20 of them were built. The C64 for MEGA65 core does not run on R2 machines.
| R3/R3A         | 2020-2023 | C64MEGA65-V6.0-R3.cor | R3 is the "DevKit" (100 were built) and R3A are batches 1 and 2. If your MEGA65 was manufactured before 2024 then you have an R3 or R3A machine.
| R4             | 2023      | C64MEGA65-V6.0-R4.cor | Development board on our way to the R6. Only 10 of them were manufactured (board only, no complete machines).
| R5             | 2023      | C64MEGA65-V6.0-R5.cor | Upgraded version of R4 that contains new circuits for the expansion port. Only 10 of them were manufactured (board only, no complete machines).
| R6/R6A         | 2024+     | C64MEGA65-V6.0-R6.cor | Latest and greatest MEGA65. Manufactured from 2024 on.  The R6A revision, first shipped on December 11, 2025, uses the same R6 core variant, replaces some EOL components and improves the overall electrical robustness of the board.

Navigate to the [MEGA65 Filehost and read this article](https://files.mega65.org/html/main.php?ar=2f4f0571-9bb3-4ada-9959-5a7231574666),
if you are interested in more details about the MEGA65 model history.
Also contains technicals specifications and photos.

Only use `*.bit` files if you know what you are doing.

Differences in the C64 for MEGA65 core on different MEGA65 models
-----------------------------------------------------------------

| Number | Topic                                                      | Details                                                                                                                                                                                                                                                                | R3/R3A   |   R4   | R5   | R6   |
|:------:|:----------------------------------------------------------:|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|:--------:|:------:|:----:|:----:|
| 1      | Bug: HDMI backpower issues                                 | [Learn more](../FAQ.md#2-my-mega65-or-the-c64-core-is-behaving-somehow-weirdly), what wide range of problems and strange effects HDMI backpower issues are creating and how to avoid these issues.                                                                     | yes      | no     | no   | no   |
| 2      | DAC for analog 3.5mm audio jack                            | While on R3/R3A machines the analog audio that comes out from the 3.5mm audio jack is "OK" and sometimes is plagued by hissing and humming, the newer machines feature a high-quality audio digital to analog converter (DAC) that leads to a crystal clear output.    | standard | DAC    | DAC  | DAC  |
| 3      | Hardware cartridges: Bi-directional reset signal           | Makes the core compatible with even more cartridges. Two examples that stand out are: (1) You do not need the "reset workaround" for the Kung Fu Flash (KFF) any more (2) Reset buttons and "special" buttons at most freezer cartridges are working now.              | no       | no     | yes  | yes  |
| 4      | Supercapacitor for Real-Time-Clock (RTC)                   | Ensures that the MEGA65 remembers the date/time even if you did not install a CR2032 battery.                                                                                                                                                                          | no       | yes    | yes  | yes  |
| 5      | Bug: Limited ability to pull Expansion Port's RESET to GND | R5 boards contain a bug that reduces compatibility as described here: https://github.com/MJoergen/C64MEGA65/issues/118. Can be fixed by "modding" the board. Needs some soldering skills.                                                                              | no       | no     | yes  | no   |
| 6      | Simulated REU uses SDRAM                                   | Using SDRAM for the simulated REU leads to higher accuracy and compatibility and a lesser amount of timing glitches (like flickering, Sprite bugs, etc.) when using the simulated REU *in parallel* with *simulated* cartridges. There is no observable advantage of this feature when using the simulated REU in parallel with hardware cartridges. Details: https://github.com/MJoergen/C64MEGA65/issues/206 | no | yes | yes | yes |
