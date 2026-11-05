# Turbo modes: research notes

Facts, sources and analysis behind `STATUS.md`. Line numbers refer to `develop` at `55918e6` and the submodule `CORE/C64_MiSTerMEGA65` at `650c6b5`; identifiers are authoritative, numbers are orientation aids.

## 1. Sources

| Source | Content |
|---|---|
| [#87](https://github.com/MJoergen/C64MEGA65/issues/87) | Opened 2023-09-26 by oe3gwu ("1, 2, 4 ... 40 MHz like the MEGA65", motivated by Test Drive II). 6 comments, no images. Renamed 2026-02-21 to "Support non-standard CPU clock frequencies" and 2026-06-07 to "Implement MiSTer-supported turbo modes". Labels `enhancement`, `V6`. Assigned to sy2002 since 2026-11-03. References commits `671a7fa` (main repo) and `b0ddbe6` (submodule). |
| [#242](https://github.com/MJoergen/C64MEGA65/issues/242) | Opened 2026-07-10 by Kugelblitz360 (Boris Schneider-Johne). 1 comment (cross-link to #87), no images. Label `V6`. |
| [#2](https://github.com/MJoergen/C64MEGA65/issues/2) | The 0.25 % flicker-free slowdown broke Input 64 1/1985; fixed in V5. MJoergen asked to keep it in mind for turbo (#87 comment 2). |
| [#181](https://github.com/MJoergen/C64MEGA65/issues/181) | NTSC; implemented in A22, closed 2026-11-03. Comment 3 explains why `clk32_speed` and the 1541 drift logic need exact clock values. |
| [#213](https://github.com/MJoergen/C64MEGA65/issues/213) | SIMREU warning; MJoergen's idea of a non-persistent, auto-resetting option (relevant for decision C). |
| [#232](https://github.com/MJoergen/C64MEGA65/issues/232), [#235](https://github.com/MJoergen/C64MEGA65/issues/235), [#259](https://github.com/MJoergen/C64MEGA65/issues/259) | Turbo Chameleon and TurboMaster V3 hardware cartridges (research, not V6); unrelated to the internal turbo except that a cartridge DMA forces our turbo off. |
| MiSTer `c64.sv`, lines 261-262 and 937-938 | OSM strings and the turbo wiring, including `disk_access` (section 3.4). Unchanged since our fork point `1c6bd48` ("VERSION 5"). |
| [`MiSTer-devel/C64_MiSTer`](https://github.com/MiSTer-devel/C64_MiSTer) | Upstream history of `rtl/fpga64_sid_iec.vhd` and `rtl/video_vicII_656x.vhd` (section 4). |
| [Ultimate 64 turbo settings](https://1541u-documentation.readthedocs.io/en/latest/config/turbo_mode.html) | `$D030` / `$D031` / SuperCPU registers, badline notes, 3 menu screenshots (section 9). |
| [Turbo Chameleon programmer's manual](https://wiki.icomp.de/w/images/b/bd/Chameleon_progmanual.pdf) | Chapter 11 (PDF pages 37-38) and the register summary (page 52): `$D0F3`, Turbo I/O, Auto Speed (section 9). |
| [lemon64 t=89700](https://www.lemon64.com/forum/viewtopic.php?t=89700) | "Tech Demo - Rescue on Fractalus for C64 Ultimate", 53 posts on 4 pages, no images (section 11). |
| [lemon64 t=89707](https://www.lemon64.com/forum/viewtopic.php?t=89707) | "Koronis Rift, Easyflash AND C64 Ultimate", 8 posts, no images (section 11). |
| [icomp wiki: C64 Benchmarks](https://wiki.icomp.de/wiki/C64_Benchmarks) | Benchmark programs for measuring turbo factors (`TEST-PLAN.md`). |

lemon64.com sits behind a Cloudflare browser check: `curl` and WebFetch receive HTTP 403 and there is no archive.org copy. Read it through the Claude-in-Chrome extension.

## 2. The two issues

* **#87** began as "make the CPU much faster". In 2026 sy2002 narrowed it to the turbo the MiSTer core already contains, explained the mechanism, analyzed the hardware-cartridge risk and committed the cartridge protection (comment 3, commits `b0ddbe6` / `671a7fa`, turbo still hardwired off). He asked to implement NTSC first (comment 4). MJoergen asked for careful SIMREU tests, especially on R3, where ascal shares the HyperRAM (comment 5).
* **#242** is the software view: the C128 `$D030` switch, the C64 Ultimate `$D031` speed register, the Turbo Chameleon `$D0F3`, five design questions and two games Boris patched (section 11). Scope decision L1 keeps only what MiSTer offers; the answers are in section 10.

## 3. How the MiSTer turbo works (as present in our core)

### 3.1 The cycle state machine

`fpga64_sid_iec.vhd` runs at `clk_main` (31.527778 MHz PAL, 32.727273 MHz NTSC) and splits each 1 MHz C64 cycle into 32 states (`sysCycleDef`, lines 199-208): `EXT0-3`, `DMA0-3`, `EXT4-7`, `VIC0-3`, `CPU0-CPUF`. The VIC owns `CYCLE_VIC0`; the CPU half is `CPU0` to `CPUF`. In a cycle in which the CPU gets the bus, `cpuHasBus` is 1 from `CPU0` to `CPUF`; it is 0 from `EXT0` to `VIC3` (process at lines 409-423). While it is 0, the VIC asserts `aec` (PHI2 low) and the system address bus, and with it the cartridge port, carries the VIC address (`fpga64_buslogic.vhd`, lines 425-431). The I/O chip selects of `fpga64_buslogic.vhd` (VIC, SID, color RAM, CIA 1 and 2, IO1, IO2) and the cartridge ROM selects of CPU accesses are set only while `cpuHasBus = '1'` (line 345); while the VIC has the bus, only its own fetch selects (RAM, character ROM, Ultimax ROMH) can be set. PHI2 at the cartridge port is high from `CPU1` to `CPUE` (process at lines 467-478). The peripheral enables are decoded from `sysCycle` alone (process at lines 425-448): the CIA register-access enable `phi2_n` (`enableCia_n`, the strobe of every CIA read and write in `mos6526.v`) at `CPUC`, the CIA timer and port enable `phi2_p` (`enableCia_p`) and the SID enable `ce_1m` (`enableSid`) at `CPUF`. They stay at 1 MHz whatever the CPU does.

### 3.2 When the CPU may run

```vhdl
cpu_cyc <= '1' when
            (sysCycle = CYCLE_CPU0 and turbo_m(0) = '1' and cs_turbo_eligible = '1' ) or
            (sysCycle = CYCLE_CPU4 and turbo_m(1) = '1' and cs_turbo_eligible = '1' ) or
            (sysCycle = CYCLE_CPU8 and turbo_m(2) = '1' and cs_turbo_eligible = '1' ) or
            (sysCycle = CYCLE_CPUC and (io_enable = '1'  or cs_ram = '1')) else '0';
```

(lines 907-911; upstream uses `cs_ram` in the first three terms, see section 5.1)

* `enableCpu` is `cpu_cyc` delayed by three clocks (`cpu_cyc_s`, lines 916-917). The T65 advances on that enable and puts its next address out one clock later.
* `io_enable` is set at `EXT0` and cleared by any `enableCpu` in the same cycle (lines 918-921). An I/O access therefore only executes at `CPUC` of a "clean" 1 MHz cycle in which the CPU has not run yet. This keeps every I/O access at C64 timing. `cs_ioE` / `cs_ioF` (IO1/IO2) are gated with `io_enable` as well (`fpga64_buslogic.vhd`).
* `rdy => baLoc` (line 872): badlines and sprite DMA halt the CPU as on a real C64, in turbo too. `enable => enableCpu and not dma_active` (line 868).
* Nominal speeds from `turbo_m` (decoded at lines 929-936): `turbo_speed = "00"` gives `"010"` = `CPU4` + `CPUC` (2x); `"01"` gives `"110"` = `CPU4` + `CPU8` + `CPUC` (3x); `"10"` and `"11"` give `"111"` = `CPU0` + `CPU4` + `CPU8` + `CPUC` (4x). Effective factors are lower: I/O, badlines and sprites keep C64 timing.

### 3.3 The turbo decision and `$D030`

```vhdl
if sysCycle = CYCLE_EXT1 or sysCycle = CYCLE_EXT5 then
   dma_active <= dma_req;
   turbo_en <= turbo_mode(0);
   turbo_m <= "000";
   if dma_req = '0' and ((turbo_mode(0) and turbo_state) = '1' or turbo_mode(1) = '1') then
      case turbo_speed is ...
```

(lines 925-937)

* `turbo_mode(0)` = C128 mode: turbo while `turbo_state` = 1. `turbo_mode(1)` = Smart: turbo always (MiSTer feeds `Smart and not disk_access` into this bit, section 3.4).
* Any DMA request (`dma_req`) forces `turbo_m = "000"`.
* `turbo_state` is the VIC latch `turbo_reg` (`video_vicII_656x.vhd`): a write to `$D030` stores bit 0 (line 1685); reset clears it (line 1566); a read returns `"1111111" & (turbo_reg or not turbo_en)` (line 1750), so `$D030` reads `$FF` unless C128 mode is selected. The VIC decodes 6 address bits, so the register is mirrored every 64 bytes (`$D070`, `$D0B0`, ...). The latch also records writes while C128 mode is off; switching the menu to C128 later honors a previously written 1.

### 3.4 MiSTer's menu and Smart logic (`c64.sv`)

```text
"oEF,Turbo mode,Off,C128,Smart;",
"d6oGH,Turbo speed,2x,3x,4x;",
.turbo_mode({status[47] & ~disk_access, status[46]}),
.turbo_speed(status[49:48]),
```

`d6` shows `Turbo speed` only while a turbo mode is selected (`status_menumask` bit `|status[47:46]`). `disk_access` (lines 1139-1157) goes to 1 on every edge of the C64 IEC clock or of the drive IEC clock (and of the parallel-cable strobes when the parallel cable is enabled) and falls back to 0 after 16,000,000 cycles of `clk_sys`, i.e. 0.5 s at 32 MHz.

## 4. Our fork versus upstream

* **Upstream `d6048db`** (2025-08-27, "Disable turbo while I/O access for better compatibility") is missing in our fork. It adds `cs_io <= cs_vic or cs_sid or cs_color or cs_cia1 or cs_cia2 or ioe_i or iof_i;` and the condition `cs_io = '0'` in front of `dma_req = '0'` in the turbo decision. It is the only turbo-related difference to upstream; the VIC turbo code is identical. The term has no effect, neither in this design nor upstream: the turbo decision samples `cs_io` at `EXT1` and `EXT5`, where `cpuHasBus = '0'`, and all terms of `cs_io` are set only while `cpuHasBus = '1'` (section 3.1), so `cs_io` is always 0 at the sample points. I/O accesses stay at 1 MHz through the `io_enable` rule alone. The port is kept for upstream parity.
* **Our own change** (`b0ddbe6`, 2026-06-07): `cs_turbo_eligible` from `fpga64_buslogic.vhd` (lines 451-467) replaces `cs_ram` in the three turbo terms of `cpu_cyc`, and the port `sim_crt_i` (fed with `c64_exp_port_mode_i(C_SIM_CRT)` at `main.vhd` line 1251) tells the core whether cartridge ROM is the BRAM cache (fast) or the physical slot (slow).
* Later upstream commits on these files (tape control `c49ce2e`, palette `5d748c9`, parallel-cable modes `88354ba` in `c64.sv`) do not touch turbo.

## 5. Hardware cartridges in turbo

### 5.1 The June protection

```vhdl
cs_turbo_eligible_o <= cs_ramLoc or cs_CharLoc or cs_romLoc
                    or (sim_crt_i and (cs_romLLoc or cs_romHLoc or cs_UMAXromHLoc));
```

Real-cartridge ROM (`cs_romLLoc`, `cs_romHLoc`, `cs_UMAXromHLoc`) and the Ultimax unmapped area (`cs_UMAXnomapLoc`, IDE64) can no longer run in the turbo slots `CPU0` / `CPU4` / `CPU8`. `cs_ram` keeps its old meaning for `ramCE` (line 896). IO1/IO2 writes were already safe through `io_enable`.

### 5.2 The remaining gap (finding F2, paper analysis)

In the baseline, the `CPUC` term reads `io_enable = '1' or cs_ram = '1'`, and `cs_ram` includes the cartridge selects. A real-cartridge ROM read can therefore execute at `CPUC` directly after a turbo access in the same 1 MHz cycle; `io_enable` is irrelevant in that case. Timeline after a turbo access at `CPUx`: `enableCpu` three clocks later, new address one clock after that, one more clock through `cart_output_pipeline_proc` (`main.vhd` lines 1397-1409) to the pin. The CPU samples at the `enableCpu` of the `CPUC` access (`CPUF`), and the data needs two clocks through `cart_input_pipeline_proc` (`cart_in_d_q`, line 1432) and `cart_in_data` (line 1601), so the last useful data is the one at the pin during `CPUD`.

In a clean 1 MHz cycle the CPU address is not on the port for the whole cycle either: while PHI2 is low, `aec = '1'` and the port shows the VIC address (section 3.1). The CPU address appears when `cpuHasBus` rises at `CPU0` and reaches the pin at `CPU1`, together with the rising PHI2. Estimated time from the CPU address at the pin to the last useful data at the pin (plus or minus one clock of about 31 ns):

| Preceding CPU access in the same 1 MHz cycle | Address at the pin | Time for the cartridge |
|---|---|---|
| none (clean cycle, the only case with turbo `Off`) | `CPU1` | about 410 ns (`CPU1` to `CPUD`) |
| turbo access at `CPU0` (4x) | `CPU5` | about 280 ns |
| turbo access at `CPU4` (2x, 3x, 4x) | `CPU9` | about 150 ns |
| turbo access at `CPU8` (3x, 4x) | `CPUD` | about 30 ns |

Typical EPROM and flash access times are 70-250 ns plus level-shifter delay, so cartridge code would read wrong bytes from time to time, already in 2x. Any instruction that mixes a RAM access with a cartridge ROM fetch triggers this, for example code in cartridge ROM that reads a zero-page variable.

The rule that closes the gap (`TURBO-SPEC.md` 2.2): in the `CPUC` term, cartridge-slot accesses run only in a clean cycle, the same rule MiSTer uses for I/O: `io_enable = '1' or cs_turbo_eligible = '1'`. A real-cartridge access then always gets the clean-cycle window of about 410 ns, the same as with turbo `Off`. SIMCRT, RAM and the internal ROMs stay at full speed, because `cs_turbo_eligible` includes them.

### 5.3 What else a real cartridge sees in turbo

The clean-cycle rule of 5.2 decides when a cartridge access executes, not what the port shows meanwhile. The port shows every CPU address, as on a real C64, but in turbo up to four per PHI2-high phase, and `cs_romL` / `cs_romH` follow the address without `io_enable` gating (`fpga64_buslogic.vhd` lines 476-479). Without further countermeasures a real cartridge sees three effects:

1. **Doubled writes.** A CPU write to the cartridge area (ROML, ROMH, Ultimax ROMH, Ultimax unmapped area) that becomes pending in a cycle with turbo accesses cannot execute there and waits for the next clean cycle. Its address, R/W low and data are on the port already in the turbo cycle, so the cartridge sees a complete write at that PHI2 falling edge (with `ROML` or `ROMH` asserted, in the Ultimax unmapped area by the address alone); the clean cycle then writes a second time. A plain ROM ignores this, but a cartridge with writable registers or memory in that area sees every such write twice. Flash command sequences (unlock cycles followed by a program or erase command, for example EasyProg writing an EF3) break when one of their writes is doubled.
2. **A missed `$FF00` trigger.** A hardware REU (1764, REU Grande) can start a transfer on a CPU write to `$FF00` (command register bit 4 clear) and recognizes that write at a PHI2 falling edge. `$FF00` lies under the KERNAL ROM, so the write goes to RAM and is turbo-eligible. In a turbo slot (`CPU0`, `CPU4`, `CPU8`) its address is at the port only in the middle of the PHI2-high phase and has changed before PHI2 falls, so the REU never starts the transfer. A write in the regular slot `CPUC` is safe in every cycle: its address stays at the port until after the PHI2 falling edge.
3. **A missed EF3 fingerprint (R3, R3A, R4).** These boards cannot sense a cartridge-driven reset, so `cartridge_heuristics_inst` (`main.vhd` line 1769) recognizes the EF3 from the bus pattern of its menu: writes to `$DE00` and `$DE0E`, then the addresses `$0108`, `$0109`, `$0013` at three consecutive PHI2 falling edges. In turbo several CPU accesses share one PHI2 cycle, the sampled sequence skips addresses, the EF3 is not recognized, its reset request is ignored, and starting a game from the EF3 menu fails. This affects Smart mode; in C128 mode the EF3 menu runs at 1 MHz, because the reset that starts it clears the `$D030` bit.

Countermeasures (requirements, binding in `TURBO-SPEC.md` 2.3, 2.4 and 3.3):

* The cartridge strobes (ROML, ROMH, Ultimax ROMH, IO1, IO2), R/W low and the data drive of a CPU access to the cartridge area appear at the port only in the clean cycle in which the access executes, in the same window as with turbo `Off`.
* `$FF00` writes are never turbo-eligible: they run only in the regular `CPUC` slot, so their address and R/W low are at the port at a PHI2 falling edge in every speed.
* Turbo is off while the EF3 heuristics are armed, that is while a detection is in progress (from the write to `$DE00` until the heuristics have decided), in hardware-cartridge mode and only on the boards that use the heuristics. The menu before and the game after the detection run in turbo.

What stays: `cart_phi2_o` is a 1 MHz clock in all modes, the cartridge never sees a "turbo PHI2"; bus-watching cartridges (freezers, KFF) still see up to four CPU addresses per PHI2-high phase (test items in `TEST-PLAN.md`).

## 6. Smart mode on our hardware (finding F4)

Our IEC clock signals in `main.vhd`: `c64_iec_clk_out` (C64 to bus, line 425), `c64_iec_clk_in` (simulated drives to C64, line 2255), `hw_iec_clk_n_in` (physical IEC port, line 2139); the core receives `c64_iec_clk_in and hw_iec_clk_n_in` (line 1329). There is no parallel cable (`PARPORT => 0`, line 2243). A detector that restarts a 0.5 s timer (`clk_main_speed_i / 2` cycles) on every edge of these lines reproduces MiSTer's Smart behavior for simulated drives and real drives on the IEC port alike. C128 mode gets no detector (as on MiSTer and a real C128).

## 7. Subsystems that are safe by design (finding F3)

* **DMA forces turbo off:** `core_dma_v` (`main.vhd` lines 1626-1680) collects `cartridge_loading_i`, `crt_bank_wait_i` (SIMCRT cache miss), `not cart_in_dma_n` (hardware `/DMA`) and `reu_dma_req` (SIMREU); `core_dma_req <= core_dma` (line 1508) feeds `dma_req` (line 1284), which forces `turbo_m = "000"`. REU transfers, `.crt` bank loads and hardware DMA keep their 1 MHz cadence, so the SIMREU HyperRAM read-ahead timing is unchanged. Still test SIMREU on R3 (MJoergen).
* **DMA latency:** the core samples `dma_req` only at `EXT1` and `EXT5` (section 3.3). A request raised later in a cycle takes effect at the next sample point; the CPU accesses due in the current CPU half still run, up to four in 4x instead of one. In upstream MiSTer, a SIMREU transfer started by a `$FF00` write in the first turbo slot (`CPU0`) therefore follows up to three more CPU accesses. Here `$FF00` writes are never turbo-eligible and run at `CPUC` of a clean cycle (5.3), the last CPU slot, so no other CPU access runs between the trigger and the transfer.
* **Bank bits:** after a write to `$00` or `$01` in a turbo slot, the new LORAM, HIRAM and CHAREN bits of the 6510 port reach the eligibility decision (`cs_turbo_eligible`) one clock later. This affects at most the slot choice for the next access, not the data it reads or writes.
* **Clocks:** turbo only changes which states enable the CPU; `clk_main`, `clk32_speed` (TOD), the flicker-free switching and NTSC are untouched. CIA timers and TOD keep counting at 1 MHz. The #2 drift test and the TOD test are regression checks, not expected failures.
* **SIMCRT:** cartridge ROM comes from the BRAM cache and is turbo-eligible in SIMCRT mode; bank-switch writes are I/O (1 MHz); cache misses pause the CPU through DMA.
* **SIMREU / RR-Net registers, CIA, VIC, SID, color RAM:** I/O, always 1 MHz.
* **Drives:** the simulated 1541/1581 run on their own clock enable; only C64-side timing loops speed up, which Smart covers.

## 8. OSM state (finding F5)

* `config.vhd`: items at lines 458-467 (`Turbo mode` / `Off` / `C128` / `Smart`, `Turbo speed` / `2x` / `3x` / `4x`) inside the `Model: %s` submenu; groups `OPTM_G_TURBO_MODE = 23` and `OPTM_G_TURBO_SPEED = 24` (lines 644-645); `OPTM_GROUPS` entries at lines 725-734, defaults `Off` and `2x`.
* `mega65.vhd`: `C_MENU_TURBO_OFF/C128/SMART` = 43/44/45 and `C_MENU_TURBO_2X/3X/4X` = 48/49/50 (lines 432-437), so far unused.
* `CORE/m2m-rom/m2m-rom.asm` (`SUBMENU_SUMMARY`, lines 55-140): the submenu headline already shows e.g. `Model: PAL C128 2x`; nothing to do.
* Hiding `Turbo speed` while turbo is `Off` (MiSTer `d6`) is possible with `OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2)` (function at lines 667-670, used for the drive menus at line 676); `M2M/rom/tests/menu_test.py` (lines 77, 130-139, 1815-1820) must follow.
* Persistence is global (`SAVE_SETTINGS`, line 290); there is no per-item "do not save" mechanism.

## 9. Other turbo schemes (reference only, out of scope by L1)

* **C128:** `$D030` bit 0 = 2 MHz. The VIC cannot fetch at 2 MHz, so the screen shows garbage; software therefore switches 2 MHz on in the border only (about a third of a PAL frame). Some old C64 programs initialize the VIC with a loop that also writes junk into `$D030`; on a C128 and in our C128 mode they switch turbo on by accident.
* **C64 Ultimate / Ultimate 64:** modes `Off`, `Manual`, `U64 Turbo Registers`, `TurboEnable Bit`. `$D031` bits 0-3 = speed index (0..3 = 1/2/3/4 MHz; up to 48 MHz on the U64 and 64 MHz on the U64E2), bit 7 = badline timing off; `$D030` bit 0 in `TurboEnable Bit` mode; SuperCPU-style `$D07A` / `$D07B` / `$D0BC`. Internal memory runs at the turbo rate, every access to the cartridge bus at 1 MHz and only while BA is high.
* **Turbo Chameleon:** `$D0F3` (bit 7 turbo on, bit 5 mirror to `$D030` bit 0, bit 4 Auto Speed off, bits 3-0 speed limit 2x..6x, fractional and slow-down steps). All `$D000-$DFFF` accesses at 1 MHz except "Turbo I/O" (`$D0A0-$D0AF`, color RAM reads). Auto Speed: 1 MHz for about 10 ms after any CIA register access that can touch the IEC lines.

## 10. Answers to the five questions of #242 (under L1)

1. **Higher CPU speeds:** 2x, 3x, 4x, selectable in the menu; more is not part of the MiSTer design.
2. **Blank screen:** no. The VIC keeps its own state `CYCLE_VIC0`; badlines and sprites still stop the CPU, so the picture stays correct in turbo.
3. **Automatic slowdown for IEC:** yes in Smart (0.5 s at 1 MHz after any IEC clock activity, simulated and real drives); not in C128 mode.
4. **`$D030`:** yes, that is the C128 mode.
5. **C64 Ultimate / Turbo Chameleon register schemes:** not planned.

## 11. Boris's two patched games (lemon64)

* **Rescue on Fractalus** (MagicDesk `.crt`, based on the OneLoad64 cartridge of the PAL tape version; download https://webdrive.commodoregames.net/SHARE_AL9YKJD5OG): key routines are wrapped in `$D030` turbo on/off, only while the raster is in the border, so it stays C128-compatible. On a C128 only about 25 % of the game runs at 2 MHz (small gain); on a C64 Ultimate those parts run up to 64 MHz (about 30 fps). The full game cannot simply be sped up: in an always-on turbo a screen-clear loop overshoots and corrupts the viewport already at 4 MHz. On the C64 Ultimate it needs `TurboEnable Bit`. Works on any standard C64 at normal speed. On our core: C128 mode; expect a gain between C128 and C64 Ultimate; Smart corrupts the screen.
* **Koronis Rift V2.1 beta** (EasyFlash `.crt` with load and save, PAL; download https://webdrive.commodoregames.net/SHARE_BGVKGUOOR4): needs the C64 Ultimate in `U64 Turbo Registers` mode. At the logo it turns turbo on for one frame and counts cycles; if the count says "C64 Ultimate", it uses a code path locked to 4 MHz with physics hooks (enemies, animations and events slowed to a quarter, player speed halved). Holding left SHIFT while the title picture is shown skips the detection. Runs normally on a standard C64 and in VICE. On our core: no `$D031`, so normally the standard version; Smart 4x might pass the speed check (test).
* **Forum notes:** smf recommends `U64 Turbo Registers` on the C64 Ultimate (software sets the speed through `$D031`, `$8F` = full speed). Boris expects the MEGA65 to become one more platform with a sped-up C64 CPU and wishes for one game build that runs on all of them. No C64 emulator emulates these turbo modes (VICE cannot), so real hardware and FPGA cores are the only test platforms. Boris offers technical notes and source code on request.
