# The Path to D81 — Enabling Simulated 1581 Drives (D64/G64/D81 + JiffyDOS-1581) in C64MEGA65

> **Document standard:** this is an *implementation-ready specification*, written so that a future coding-agent session can execute the work without re-research: every change carries file:line anchors, exact signal/register/constant names and widths, code-level sketches where wiring is non-obvious, an explicit dependency ordering between changes, build commands, and per-phase verification steps.
>
> **Provenance:** assembled 2026-06-11 from a 24-agent deep analysis (9 parallel subsystem dives, 14 adversarially verified claims, 1 completeness pass) plus direct verification of the Vivado utilization/timing reports checked into the repo. Every file:line citation was read from the actual sources. Claims that could not be fully verified are explicitly tagged *(to be confirmed)*.

---

## 0. How to use this document

**Read-these-files-first list** for the implementing session (in this order, with this doc open):

1. `CORE/C64_MiSTerMEGA65/rtl/iec_drive/iec_drive.sv` (183 lines — the 1541/1581 selector; the commented-out block at 140–182 is the heart of the work)
2. `CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1581_multi.sv` (the 1581 multi-drive wrapper; ROM section 94–148)
3. `CORE/C64_MiSTerMEGA65/rtl/iec_drive/c1541_multi.sv` lines 58–230 (the **proven adaptation template** for everything that must be done to the 1581)
4. `CORE/vhdl/main.vhd` lines 1330–1580 (IEC drives + vdrives instantiation) and the RESET SEMANTICS block at ~325
5. `CORE/vhdl/mega65.vhd` lines 780–900 (QNICE device decode incl. `mount_buf_ram` and the kernal ROM devices)
6. `M2M/rom/vdrives.asm` (especially `VD_STROBE_IM` at 413–460) and `M2M/rom/shell.asm` `LOAD_IMAGE`/`HANDLE_IO`/`FLUSH_CACHE` (668–1348)
7. `CORE/m2m-rom/m2m-rom.asm` (the C64-specific callbacks; the entire firmware-side D81 gap is here)
8. `CORE/vhdl/sw_cartridge_csr.vhd` + `sw_cartridge_wrapper.vhd` (the in-tree blueprint for the HyperRAM-backed mount buffer)

**Binding decisions already made** (by sy2002, 2026-06-11):

1. **No upstream sync.** Upstream `C64_MiSTer` has diverged substantially (DDRAM image loading, RPM/wobble, fdc1772 `IMG_TYPE` refactor); the local snapshot (2023-06-21 vintage) is authoritative. Upstream sources were consulted only to reconstruct the intended "enabled" wiring of our commented-out 1581 block; deliberately skipped upstream fixes are listed in Appendix A.
2. **The mount buffer moves to HyperRAM.** BRAM is quantitatively impossible (section 3); the HyperRAM design in section 7 is the committed direction.
3. **Drive 8 only.** No simulated drive 9 — one virtual drive that mounts D64 *or* D81. (What drive 9 would have taken is preserved in compressed form in section 9.2 for future reference.)
4. **Exact-size images only at step one.** Like today's D64 handling, the size tables stay hardcoded and minimal: D64 = 174,848 / 196,608 bytes (no error-info variants), D81 = exactly 819,200 bytes (no error-info variant). Wrongly sized disks are rejected with a clear message. This also keeps the Shell ROM footprint minimal (see 8.5).
5. **The cartridge staging pool must keep ≥ 2 MB.** Verified against both the market and our own RTL in section 7.3 — satisfied with margin (2.71 MB).

---

## 1. Goal and scope

Extend the Disk Mount feature so that **virtual drive 8** can mount **D81 images on a simulated Commodore 1581** (WD1772-based 3.5" drive) in addition to D64, with **JiffyDOS-1581** as the third user-supplied custom DOS ROM (next to JiffyDOS C64 Kernal and JiffyDOS 1541). **G64 is explicitly out of scope** (section 12 explains why it is a much larger, separate project despite looking adjacent), and **a second virtual drive ("9:") was considered and decided against** (section 9.2).

---

## 2. What already exists — the surprising amount of groundwork

The 1581 was clearly anticipated by the original port. Inventory:

| Layer | What exists | Where |
| --- | --- | --- |
| 1581 drive engine | Complete MiSTer RTL: `c1581_multi.sv`, `c1581_drv.sv` (T65 CPU @2 MHz, CIA 8520, VIA 6522), `fdc1772.v` (WD1772), `floppy.v` | `CORE/C64_MiSTerMEGA65/rtl/iec_drive/` |
| 1581 DOS ROM | `c1581_rom.mif.hex` is in the repo (32,768 hex lines = exactly 32 KB), and `c1581_multi.sv:115-129` already references it via the Vivado-compatible `iecdrv_mem_rom`/`INITFILE`/`FALLING_A(1)` mechanism — half the ROM adaptation is done | `c1581_rom.mif.hex` |
| Partial Vivado port | `c1581_drv.sv` already has the T65 `din`/`dout` port fix; `iecdrv_mos8520.v` differs from upstream only by Vivado-required named always-blocks (already Vivado-ready) | dive comparison vs. upstream |
| Drive-type selector | `iec_drive.sv` defines `img_type` (00 = 1541 emulated GCR/D64, 01 = 1541 real GCR/G64, 10 = 1581/D81), latches it per drive into `dtype` (`iec_drive.sv:63-64`), and the *active* output muxes already translate the 1581's 512-byte sectors: `sd_lba = c1581_sd_lba << 1`, `sd_blk_cnt` forced to `6'd1`, `sd_buff_addr[8:0]` (`iec_drive.sv:72-78`) | `iec_drive.sv` |
| ROM bank-select convention | The 64 KB QNICE ROM window split on `rom_addr_i[15]` is already half-implemented: the c1541 write gate is `~rom_addr_i[15] & rom_wr_i` (`iec_drive.sv:115`); the commented 1581 side uses `rom_addr[15] & rom_wr` (`iec_drive.sv:166`). All carriers are already 16 bits wide end-to-end: `qnice_c1541rom_addr` (`mega65.vhd:379`), port `c1541rom_addr_i` (`main.vhd:237`), `rom_addr_i[15:0]` (`iec_drive.sv:53`) | — |
| img_type plumbing, hardware | `vdrives.vhd` register 0x0004 → 2-bit CDC (`vdrives.vhd:253-267`) → `img_type_o` → `main.vhd:1519` → `iec_drive` (`main.vhd:1443`), ungated | `M2M/vhdl/vdrives.vhd` |
| img_type plumbing, firmware | **Already complete in the framework**: `VD_STROBE_IM` writes `VD_SIZE_L/H`, `VD_RO`, then `VD_TYPE` (= reg 0x7004, `sysdef.asm:331`), *then* strobes `VD_IMG_MOUNT` — exactly the order the hardware contract requires (`vdrives.asm:413-460`, writes at 423–434); `shell.asm:557` passes the type returned by the core's `PREP_LOAD_IMAGE` callback | `M2M/rom/vdrives.asm` |
| Shell constants | `C64_IMGFILE_G64`/`C64_IMGFILE_D81` extension strings and `C64_IMGTYPE_G64=1`/`C64_IMGTYPE_D81=2` defined, unused (`m2m-rom.asm:430-439`) | `CORE/m2m-rom/m2m-rom.asm` |
| Menu group ID | `OPTM_G_MOUNT_9 := 2` is already reserved ("not used, yet") in `config.vhd:515` and auto-generated as `C64_OPTM_G_MOUNT_9` in `osm_const.asm:55` | `CORE/vhdl/config.vhd` |
| Clocking | The 16 MHz fractional-accumulator `iec_drive_ce` (`main.vhd:1485-1503`) is exactly what `c1581_multi` expects ("Input clock/ce 16MHz", `c1581_multi.sv:6`): its internal divider produces the 2 MHz CPU phi and the 8 MHz WD1772 enable matching `fdc1772.v`'s default `CLK_EN=8000` (`c1581_multi.sv:73-92`, `c1581_drv.sv:234-237`). **No clocking changes needed**, NTSC included (the CE is keyed off `clk_main_speed_i`) | — |

**And the closed list of what is missing** (each item detailed in sections 5–10):

1. The `c1581_multi` instantiation in `iec_drive.sv:140-182` is commented out **and stale** (references signals `rom_addr`/`rom_data`/`rom_wr`/`rom_std` that don't exist — real names carry `_i` suffixes).
2. `c1581_multi.sv:97`'s writable-ROM instance is a **guaranteed elaboration error**: `iecdrv_mem #(8,15,"./c1581_rom.mif")` passes 3 positional parameters to the MEGA65-modified 2-parameter `iecdrv_mem` (`iecdrv_misc.sv:37`).
3. **The single real engineering item:** `fdc1772.v`'s entire SD interface (sector FIFO, `sd_rd/sd_wr/sd_lba` generation, `sd_ack/sd_buff_wr` consumption) runs on the *core clock*, while our `vdrives` drives those signals in the *QNICE clock domain*. Upstream never hit this because MiSTer's `clk == clk_sys`. The c1541 was explicitly re-clocked by sy2002 (`c1541_track` runs on `clk_sys`); `fdc1772.v` was not (`c1581_drv.sv:47` declares `clk_sys` but never uses it).
4. None of the 1581 source files are registered in **any of the four Vivado projects** (`grep c1581 CORE/CORE-R*.xpr` → no matches).
5. The QNICE device decode for the drive ROM masks address bits 15:14 to `"00"` (`mega65.vhd:874`), so the 1581 ROM window is unreachable from QNICE.
6. The mount buffer is a 256 KB BRAM that cannot hold a D81 (section 3).
7. The Shell's `PREP_LOAD_IMAGE` hardcodes `C64_IMGTYPE_D64` (`m2m-rom.asm:184`) and the file filter only admits `.D64` (`m2m-rom.asm:92-95`).
8. No JiffyDOS-1581 device, auto-load entry, or documentation.

---

## 3. The mount-buffer problem — why the D81 image must move to HyperRAM

### 3.1 Today's architecture

When the user mounts a D64, the Shell copies the **whole image** from SD card into a dedicated RAM, then serves the drive's block requests out of it (software byte-pump through vdrives registers 0x0005–0x0007) and flushes dirty contents back to SD (write-back cache, 2-second anti-thrash delay, `vdrives.vhd:347-383`). The buffer (`mega65.vhd:883-900`):

```vhdl
-- "This will work for D64 only. @TODO: Switch to HyperRAM at a later stage"
mount_buf_ram : entity work.dualport_2clk_ram
   generic map ( ADDR_WIDTH => 18, DATA_WIDTH => 8, MAXIMUM_SIZE => 197376, FALLING_A => true )
```

Two findings:

- **The `MAXIMUM_SIZE` generic is dead code.** Declared in `2port2clk_ram.vhd:17`, never forwarded to the inner `tdp_ram`, whose array is sized purely by `2**ADDR_WIDTH` (`tdp_ram.vhd:36`). Confirmed by the synthesis log: the buffer maps to a full "256 K x 8 | 64 RAMB36" (`CORE/CORE-R6.runs/synth_1/runme.log:3737`). Worth fixing independently of D81, but irrelevant once the buffer moves to HyperRAM.
- **Crucially, the buffer is QNICE-only staging RAM**: only port A (QNICE, falling edge) is connected; the C64 core *never reads it*. All sector traffic is Shell software. Therefore relocating the staging area is invisible to the core-side hardware — the make-or-break constraint most of section 7 builds on.

### 3.2 The BRAM calculation (measured, all four boards)

All four board revisions use the identical part **xc7a200tfbg484-2** (`CORE/CORE-R{3,4,5,6}.xpr:10`), so one budget applies everywhere. From the placed-design reports:

| Metric | R6 (2026-06-07) | R3 (2026-06-11) |
| --- | --- | --- |
| Slice LUTs | 24,677 / 133,800 (18.4 %) | 24,682 (18.5 %) |
| BRAM tiles | **212.5 / 365 (58.2 %)** | 212.5 / 365 |
| Bonded IOB | 243 / 285 (85.3 %) | — |
| Chip-level WNS | 0.252 ns (`hr_rwds` capture) | 0.369 ns |
| `qnice_clk` WNS | **0.504 ns** | 0.421 ns |
| `main_clk` WNS | 10.368 ns | 11.165 ns |

(`CORE/CORE-R6.runs/impl_1/mega65_r6_utilization_placed.rpt:35,106-110,132`, `mega65_r6_timing_summary_routed.rpt:152-212`)

A byte-wide RAM costs 4,096 bytes per RAMB36 tile. A standard D81 (819,200 B) = exactly **200 tiles**. The 1581 engine itself (DUALROM=1, required for JiffyDOS-1581) costs **18.5 tiles**: 2 × 32 KB ROM (16) + 8 KB drive RAM (2) + 1 KB WD1772 FIFO (0.5) — derived from `c1581_multi.sv:95-129`, `c1581_drv.sv:103`, `fdc1772.v:715`, with the measured c1541 baseline (10.5 tiles, `runme.log:3733-3736`) validating the method.

The arithmetic, replacing the existing 64-tile buffer:

| Scenario | Tiles | Verdict |
| --- | --- | --- |
| Naive (`ADDR_WIDTH=20` → 1 MB array): 212.5 − 64 + 256 + 18.5 | **423 / 365 (116 %)** | impossible |
| With `MAXIMUM_SIZE` fixed (200-tile buffer): 212.5 − 64 + 200 + 18.5 | **367 / 365 (100.5 %)** | **still impossible** |
| Two D81 buffers (drive 9) | 400 tiles for buffers alone | exceeds the empty device |

So once the 1581 engine's own BRAM is accounted for, even the single-drive BRAM option exceeds the device outright — and the chip already runs with 0.252 ns WNS on HyperRAM I/O capture and R6 needing a non-default "alternate algorithms" implementation strategy (`CORE-R6.xpr:1035`). **The BRAM option is dead. HyperRAM staging (section 7) is the committed design** — exactly what the original `@TODO` anticipated.

(SDRAM is *not* an alternative: since commit `54a72ba` ascal owns SDRAM on R4/R5/R6 as its only master, there is no QNICE→SDRAM bridge — `M2M$SDRAM=0x0005` is reserved, `CRTROM_TYPE_SDRAM` hits FATAL in the Shell (`crts-and-roms.asm:108-115`) — and R3 has no SDRAM at all. Bonus: on R4+ the HyperRAM is *less* contended than on R3 because ascal's traffic moved out.)

---

## 4. Target architecture overview

```
                 mount: SD → HyperRAM staging          serve: HyperRAM → drive buffer
┌──────────┐  f32_fread     ┌──────────────────┐  Shell byte-pump   ┌─────────────────────┐
│ SD card  ├───────────────►│ HyperRAM         ├───────────────────►│ vdrives.vhd          │
│ FAT32    │  (Shell        │ C_HMAP_VD0       │  via new byte-     │ sd_buff regs 5/6/7   │
│ .d81     │   LOAD_IMAGE)  │ 819,200 B exact  │  oriented QNICE    │ per-drive ack        │
└──────────┘                └──────────────────┘  device (sect. 7)  └─────────┬───────────┘
      ▲                                                                       │ QNICE clk
      │ flush: full-image write-back (FLUSH_CACHE, anti-thrash 2 s)           ▼
      └────────────────────────────────────────────────────────┐   ┌─────────────────────┐
                                                               │   │ iec_drive.sv         │
   img_type=10 latched per drive (dtype) ──────────────────────┼──►│  c1541_multi (D64)   │
   sd_lba<<1, blk_cnt=1 → 512-byte transfers                   │   │  c1581_multi (D81) ◄─── enable (sect. 5)
                                                               │   └─────────┬───────────┘
                                                               │             │ IEC bus (AND-wired)
                                                               └─────────────► C64 (fpga64_sid_iec)
```

---

## 5. Enabling the 1581 engine (RTL)

### 5.1 `c1581_multi.sv` — finish sy2002's half-done adaptation

`c1581_multi` exact interface (verified `c1581_multi.sv:11-60`): generics `PARPORT=1, DUALROM=1, DRIVES=2`; clk-domain ports `clk, reset[N:0], ce, pause, img_mounted[N:0], img_readonly, img_size[31:0], act_led[N:0], pwr_led[N:0], iec_atn_i, iec_data_i, iec_clk_i, iec_fclk_i, iec_data_o, iec_clk_o, iec_fclk_o, par_data_i[7:0], par_stb_i, par_data_o[7:0], par_stb_o`; clk_sys-domain ports `clk_sys, sd_lba[31:0][NDR], sd_rd[N:0], sd_wr[N:0], sd_ack[N:0], sd_buff_addr[8:0], sd_buff_dout[7:0], sd_buff_din[7:0][NDR], sd_buff_wr, rom_addr[14:0], rom_data[7:0], rom_wr, rom_std`. There is **no `rom_data_o`** and **no `sd_blk_cnt`**.

**Edit 1 — the writable (JiffyDOS) ROM instance** at `c1581_multi.sv:97`. Today: `iecdrv_mem #(8,15,"./c1581_rom.mif") rom` — an elaboration error (3 positional params vs. the 2-parameter MEGA65 `iecdrv_mem`, `iecdrv_misc.sv:37`), posedge port A (incompatible with QNICE's falling-edge single-cycle writes), Quartus `.mif`. Replace with the pattern proven at `c1541_multi.sv:156-171`, **but keep the upstream semantics of initializing the writable slot with the standard ROM** (upstream does exactly this — it is what makes a missing `jd-c1581.bin` degrade to standard 1581 DOS instead of a dead drive):

```systemverilog
// MEGA65: replaces broken `iecdrv_mem #(8,15,"./c1581_rom.mif") rom`
iecdrv_mem_rom #(.DATAWIDTH(8), .ADDRWIDTH(15),
                 .INITFILE("../../C64_MiSTerMEGA65/rtl/iec_drive/c1581_rom.mif.hex"),
                 .FALLING_A(1'b1)) rom        // FALLING_A: QNICE writes on the falling edge
(
    .clock_a(clk_sys), .address_a(rom_addr), .data_a(rom_data), .wren_a(rom_wr),
    .q_a(qnice_rom_do),                       // NEW: QNICE readback (see Edit 2)
    .clock_b(clk),     .address_b(mem_a),     .q_b(rom_do)
);
```

The standard-ROM instance at `c1581_multi.sv:115-129` is already correctly adapted — leave it.

**Edit 2 (recommended) — add a readback port**: `output [7:0] rom_data_o` driven from the writable slot's `q_a` (mirror `c1541_multi.sv:81`). Without it, QNICE reads of the new 1581 ROM device return *1541* custom-ROM bytes through the shared `qnice_c1541rom_data_from` path (`mega65.vhd:876`, `iec_drive.sv:114` is c1541-only) — harmless today (the auto-loader never reads back; no Shell consumer was found in `crts-and-roms.asm`), but a trap for future verify-after-write code. If added, mux `rom_data_o` in `iec_drive.sv` on a *registered* `rom_addr_i[15]`.

Notes: `c1581_multi` has **no ROM-size sniffer** (unlike c1541's `rom_32k_i/rom_16k_i` logic, `c1541_multi.sv:101-133`) — `mem_a` passes through unmasked (`c1581_multi.sv:142`); the 1581 DOS is always a flat 32 KB. ROM cost is independent of `DRIVES` (one time-multiplexed ROM server for up to 4 drives, `c1581_multi.sv:131-148`). `rom_std` semantics are identical to c1541: `1` = factory ROM, `0` = custom slot; it is a **global** (not per-drive) select (`c1581_multi.sv:71,146`).

### 5.2 `iec_drive.sv` — comment the 1581 back in, correctly

The commented block's *formal* port names are all valid (`.rom_addr/.rom_data/.rom_wr/.rom_std/.act_led/.iec_fclk_i/.pause` all exist on `c1581_multi`); only the *actual* signals are wrong. The corrected instantiation (cross-checked against the upstream-of-our-vintage wiring):

```systemverilog
c1581_multi #(.PARPORT(PARPORT), .DUALROM(DUALROM), .DRIVES(DRIVES)) c1581
(
   .clk(clk),
   .reset(reset | ~dtype[1]),                  // 1581 live only when dtype[1]=1 (D81)
   .ce(ce),
   .iec_atn_i (iec_atn_i),
   .iec_data_i(iec_data_i & c1541_iec_data),   // cross-feed, mirrors upstream
   .iec_clk_i (iec_clk_i  & c1541_iec_clk),
   .iec_fclk_i(1),                             // C64 has no fast serial — correct (see 14.6)
   .iec_data_o(c1581_iec_data),
   .iec_clk_o (c1581_iec_clk),
   // .iec_fclk_o, .pwr_led intentionally unconnected (upstream does the same)
   .act_led(c1581_led),
   .par_data_i(par_data_i), .par_stb_i(par_stb_i),
   .par_data_o(c1581_par_o), .par_stb_o(c1581_stb_o),
   .clk_sys(clk_sys),
   .pause(pause),
   .rom_addr(rom_addr_i[14:0]),                // FIX: was rom_addr (nonexistent)
   .rom_data(rom_data_i),                      // FIX: was rom_data
   .rom_wr(rom_addr_i[15] & rom_wr_i),         // FIX: bit15=1 selects the 1581 ROM window
   .rom_std(rom_std_i),                        // FIX: was rom_std
   .img_mounted(img_mounted), .img_size(img_size), .img_readonly(img_readonly),
   .sd_lba(c1581_sd_lba), .sd_rd(c1581_sd_rd), .sd_wr(c1581_sd_wr), .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr[8:0]), .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(c1581_sd_buff_dout), .sd_buff_wr(sd_buff_wr)
);
```

Plus, in the **active** code, restore the commented-out couplings *consistently*:

- `iec_drive.sv:66` — `assign led = c1581_led | c1541_led;`
- `iec_drive.sv:67-68` — `iec_data_o`/`iec_clk_o` become the AND of both engines
- `iec_drive.sv:97-98` — the c1541 instance's `iec_data_i`/`iec_clk_i` get their `& c1581_iec_data` / `& c1581_iec_clk` terms back

This AND-wiring is **safe by construction**: drives held in reset contribute `'1'` (released) to all IEC outputs — `iec_clk_o/iec_data_o = &{*_d | reset_drv}` (`c1581_multi.sv:150-153`, c1541 equivalent `c1541_multi.sv:216-218`) — and no combinational loop arises because every IEC input passes through a 2-FF + consensus `iecdrv_sync` before use (`iecdrv_misc.sv:17-31`). Per-drive reset gating (`reset | dtype[1]` vs. `reset | ~dtype[1]`) guarantees exactly one live engine per drive index.

Side note *(to be confirmed at first synthesis)*: today the *active* `par_stb_o/par_data_o` ANDs at `iec_drive.sv:69-70` already reference the undriven `c1581_par_o/c1581_stb_o` — benign in synthesis only because Vivado constant-folds undriven nets and `main.vhd:1462-1465` never consumes the outputs; it would X-poison any pre-change simulation. Self-heals with this change.

**Instantiation footprint with drive 8 only (decision #3):** keep `C_VDNUM = 1` and the generics do the simplification for you — `DRIVES => G_VDNUM` (`main.vhd:1424`) means exactly **one c1541 and one c1581 are instantiated**, both serving drive index 0 (= IEC device 8), with `dtype` deciding per mount which engine is live. Do not try to trim further: the two engines share nothing by design (different CPU clocking, FDC vs. GCR path), both must exist for the runtime type switch, and the permanent cost is known and small (the 1581 adds 18.5 BRAM tiles and an estimated 4–6 k LUTs, section 13). All `[N:0]` ports collapse to scalars at `DRIVES=1`, so the `c64_drive_led` widening that a second drive would have required does not apply.

**Optional hardening:** the `dtype` latch (`iec_drive.sv:63-64`) samples `img_mounted/img_size/img_type` — core-clock-domain outputs of vdrives — raw on `clk_sys` (= QNICE clock; wiring chain `mega65.vhd:649` → `main.vhd:1446`). This QNICE→core→QNICE round trip is benign **only because of the Shell contract**: `VD_STROBE_IM` writes type/size hundreds of ns before a ≥1 µs strobe (`vdrives.asm:413-450`; multi-instruction `VD_CAD_WRITE` per step). The existing D64 path double-crosses the same way but through a proper `iecdrv_sync` (`c1541_drv.sv:205-219`). Recommended: add an `iecdrv_sync` stage in front of the `dtype` latch, and document the Shell contract regardless (img_type/img_size stable before strobe; strobe held multiple cycles; never rewrite img_type until the previous strobe cleared + ~3 core clocks).

### 5.3 The fdc1772 clock-domain crossing — the highest-risk work item

`fdc1772.v` runs *everything* — the 512-byte sector FIFO (`fdc1772_dpram`, single clock, `fdc1772.v:715-728,1029-1064`), the SD request FSM (`fdc1772.v:739-785`), `sd_lba` generation, and the `sd_ack`/`sd_dout_strobe` consumption (FIFO `wren_a = sd_dout_strobe & sd_ack`, line 721) — on `clkcpu`, which `c1581_drv.sv:237` ties to `clk` (the 31.5 MHz core clock). Our vdrives presents the whole SD interface in the **QNICE domain** (`vdrives.vhd:153-166`, documented). `c1581_drv.sv:47` declares `clk_sys` but never uses it. Upstream never needed this because MiSTer's `clk == clk_sys`.

The proven fix pattern is the c1541 rework sy2002 already did: `c1541_track` is clocked on `clk_sys` (`c1541_drv.sv:205-222`), `c1541_gcr`'s SD side gets `sd_clk = clk_sys` (`c1541_drv.sv:164-170`), with an `iecdrv_sync` for `busy` (`c1541_drv.sv:141-142`).

Two implementation options, in increasing cleanliness:

1. **Minimum fix:** convert the FIFO to dual-clock (e.g., replace `fdc1772_dpram` with a `dualport_2clk_ram`/`iecdrv_mem_rom`-style wrapper) with the SD-facing port on `clk_sys` (falling edge per QNICE convention); add `iecdrv_sync` stages for `sd_ack` (and `sd_dout_strobe` if kept core-side) into `clkcpu`; treat `sd_rd/sd_wr/sd_lba` as quasi-static levels (they are set in `clkcpu` and held until ack, `fdc1772.v:747-760`; QNICE polls them at MMIO pace, ≥ ~80 ns between accesses vs. 31.7 ns core period) with explicit XDC `set_false_path` coverage.
2. **Clean fix:** re-clock fdc1772's whole SD FSM and FIFO port A onto `clk_sys`, fully mirroring the c1541 pattern.

A mitigating detail that keeps the crossing contained: for `SECTOR_SIZE_CODE==2` (the 1581 config, set at `c1581_drv.sv:234`) the FIFO's SD-side address is `{1'b0, sd_buff_addr}` with **no core-domain term** (`s_odd` applies only to `SECTOR_SIZE_CODE==3`, `fdc1772.v:703-713`).

**Also fix while in there** *(to be confirmed by a targeted sim)*: fdc1772's SD FSM has **no reset term** — `sd_rd/sd_wr` clear only on `sd_ack` (`fdc1772.v:747`), unlike `c1541_track` which clears on `reset_s` (`c1541_track.sv:77-84`). Unmounting a D81 mid-read leaves a zombie `sd_rd=1` that the Shell serves once as a bogus, self-limiting transaction (the Shell polls `VD_RD` regardless of mount state, `shell.asm:938-943`). One added reset clause.

Reassuring property (verified): fdc1772 **tolerates unlimited Shell latency** — the read/write command FSM only advances when its SD FSM is idle, data transfer to the drive CPU can't start before the ack falling edge (FIFO guaranteed full), and the only timeout (RNF, 1 s) fires solely for invalid sector numbers (`fdc1772.v:551-626`). OSM-open, flush pauses, or slow HyperRAM only slow the 1581 down, never corrupt it. *(Caveat: C64-side fastloaders with their own software timeouts are a separate, hardware-test question — see 14.9.)*

### 5.4 Project files and constraints

- **Add to all four Vivado projects** (`CORE/CORE-R{3,4,5,6}.xpr`, best via one Tcl `add_files` run): `c1581_multi.sv`, `c1581_drv.sv`, `fdc1772.v`, `iecdrv_mos8520.v` (+ `floppy.v` if not pulled in transitively). **`fdc1772.v` must be typed as SystemVerilog** — sy2002's own note at `fdc1772.v:24-25`. (`iecdrv_via6522.vhd` is already included; the `.hex` is read via `ROM_FILE`, not a project source.)
- **XDC**: add `set_false_path` entries for the new `iecdrv_sync` instances in `c1581_multi` (atn/dat/clk/fclk/rst syncs, `c1581_multi.sv:62-69`) and for the new fdc1772 crossings, following the existing c1541 pattern at `CORE/CORE.xdc:15-22`. The existing `dtype_reg[*][*]` false paths already cover the img_type latch. Check `M2M/common.xdc` clock-group declarations while at it (open question 17.7).

---

## 6. Sector protocol — verified end-to-end, zero vdrives changes

The full arithmetic was adversarially verified (claim 6, partially-true only on terminology):

- `fdc1772` (instantiated with `SECTOR_SIZE_CODE=2` → 512-byte **physical** sectors, `SECTOR_BASE=1`; `c1581_drv.sv:234`) computes, quoting the RTL since a side-mapping error would corrupt every other half-track *(verify in sim — the paraphrase below was not cross-checked against a real D81 dump)*:
  `sd_lba = ((fd_spt*track[6:0]) << fd_doubleside) + (floppy_side ? 0 : fd_spt) + sector[4:0] - 1` (`fdc1772.v:85`), with `floppy_side = ~side`, `side` = CIA `pa_out[0]` (`c1581_drv.sv:121,240`).
- Geometry is derived **purely from `img_size`** at the mount edge (`fdc1772.v:174-190`): 819,200 B → `image_sectors = img_size[20:9]` = 1600 → doubleside, `sps=800` → `spt=10` (`fdc1772.v:118-146`). LBA range 0–1599.
- `iec_drive.sv:74,77` doubles the LBA and forces `sd_blk_cnt = 6'd1`; vdrives (`BLKSZ=1` = 256-byte blocks, `main.vhd:1508`) corrects the MiSTer blocks-minus-1 convention to 2 blocks (`vdrives.vhd:293`) → byte offset `512 × c1581_lba`, length 512, max offset 818,688+512 = 819,200. Exact.
- `sd_buff_addr`: vdrives provides 14 bits (`AW=13`, `vdrives.vhd:103`), the 1581 uses `[8:0]` — QNICE pumps addresses 0…511. Fine.
- Per-drive ack gating prevents cross-*index* corruption (`fdc1772.v:721`; c1541: `c1541_drv.sv:169`); the Shell serializes all transfers anyway (all reads, then all writes, then one flush iteration per `HANDLE_IO` pass, `shell.asm:933-986`). Same-index cross-*engine* buffer pollution exists (neither engine's buffer wren is gated by dtype/reset) but is benign: each engine refills via `sd_rd` before consuming. **Document, don't fix.**
- The Shell serving loops are geometry-agnostic — `VD_SIZEB`/`VD_4K_WIN`/`VD_4K_OFFS` are computed in hardware (`vdrives.vhd:296-303`) — so 512-byte 1581 sectors need **zero changes** in `HANDLE_DRV_RD`/`HANDLE_DRV_WR` (`shell.asm:997-1156`); with the `G_BASE_ADDRESS` approach of section 7.4 the buffer relocation adds none either.

**The 819,200-byte rule (hard requirement and binding decision #4):** an 822,400-byte D81-with-error-info yields `image_sectors=1606` → `sps=803` → falls into fdc1772's *default* case → `spt=11` — silently wrong geometry for every sector (`fdc1772.v:121-136`). There is no validation anywhere in the RTL chain. **The Shell accepts exactly 819,200 bytes and rejects everything else with a clear message** (81/82/83-track variants 829,440/839,680/849,920 likewise produce garbage geometry in this fdc1772 vintage; upstream's HPS mounts them, our snapshot's geometry table does not support them). This mirrors how D64 is handled today: the existing table accepts only the error-info-free 174,848/196,608 variants (`m2m-rom.asm:441-447`) and stays exactly as it is. Hardcoded minimal tables are deliberate (decision #4): wrongly sized disks must not "sort of work", and every saved table entry and warning string counts against the 86 %-full Shell ROM (8.5). Should error-info D81s ever be wanted, the fix is Shell-side truncation (load only the first 819,200 bytes, report `img_size=819200`, and teach `FLUSH_CACHE` to write back the cache size instead of the file size, `shell.asm:1219-1228`) — explicitly *not* part of step one.

---

## 7. The HyperRAM mount buffer

### 7.1 Why this is cheap: the two key facts

1. The buffer is QNICE-only staging (section 3.1) — the core side needs nothing.
2. A **byte-oriented QNICE→HyperRAM device already exists in production** as the `.crt` loader: `sw_cartridge_csr.vhd:105-144` maps QNICE byte address `addr(27:1)+G_BASE_ADDRESS` to the HyperRAM word, uses `addr(0)` to select byteenable `"01"/"10"` and the read-byte mux, duplicates write data on both lanes — QNICE device windows behave as 4096-**byte** pages exactly like the BRAM buffer. It streams files into HyperRAM through a 16-deep `avm_fifo` (`sw_cartridge_wrapper.vhd:203-234`) **while ascal renders** — the existence proof. (The framework's own word-oriented device `M2M$HYPERRAM=0x0004` is *not* suitable: byteenable hardwired `"11"` (`qnice_wrapper.vhd:490`), so a byte-loop stores one byte per word = 1.6 MB per D81, forecloses the second drive — rejected.)

### 7.2 VHDL work (`mega65.vhd`, the one genuinely new block)

Clone `sw_cartridge_csr`'s byte-window bridge (minus the CSR/parser parts) as the new backing store for `C_DEV_C64_MOUNT`: QNICE side speaks the RAMROM 4k-window protocol with wait-states (`qnice_dev_wait_o` — the protocol plumbing already exists and is used by the CRT device, `mega65.vhd:863`; framework passes it at `qnice_wrapper.vhd:472-475`); HyperRAM side is an Avalon master behind an `avm_fifo` CDC. Widen the core-side HyperRAM arbiter at `mega65.vhd:453-489` from the 2-master `avm_arbit` (REU, CRT) to a 3-master `avm_arbit_general` (REU, CRT, MOUNT). Estimated 150–250 lines of heavily template-derived VHDL.

Timing notes: writes are posted (~zero wait, FIFO-absorbed); reads stall QNICE ~300–400 ns uncontended, worst ~1500 ns under full ascal load on R3 (`doc/developer.md:225-236`). Arbitration is fair round-robin at every level (`avm_arbit.vhd:6-12`); QNICE single-beat traffic is <1 % of the ~200 MB/s HyperRAM — it can neither starve ascal nor be starved (the REU already does real-time HyperRAM access during gameplay). **Register the read data of any new QNICE device** — `qnice_clk` WNS is only 0.504 ns and the worst path is precisely the MMIO device-read mux into the CPU PC (15 logic levels, `mega65_r6_timing_summary_routed.rpt:8065-8075`).

### 7.3 Memory map (proposed concrete revision of `globals.vhd:97-100`)

Units of 4 kW = 8 kB windows, 1024 windows total. With drive 8 only (decision #3) and the exact-size rule (decision #4), the D81 buffer is exactly 0x64 windows = 819,200 B, placed directly below the REU region:

| Constant | Value | Region | Windows | Size |
| --- | --- | --- | --- | --- |
| `C_HMAP_M2M` | x"0000" | M2M framework (ascal on R3) | 512 | 4 MB (unchanged) |
| `C_HMAP_CRT` | x"0200" | SIMCRT `.crt` staging | 347 | **2.71 MB (shrunk from ~3.49 MB)** |
| `C_HMAP_VD0` | x"035B" | Drive 8 image staging | 100 | 819,200 B (new, ends x"03BE") |
| `C_HMAP_REU` | x"03BF" | SIMREU | 64 | 512 kB (unchanged) |
| guard | x"03FF" | REU burst guard | 1 | 8 kB (unchanged) |

**The ≥ 2 MB cartridge-pool requirement (decision #5) is satisfied with ~0.7 MB margin.** The requirement is well-founded on both sides:

- *Our own RTL:* `cartridge.vhd`'s bank registers are 7 bits (`bank_lo_o/bank_hi_o : std_logic_vector(6 downto 0)`, `cartridge.vhd:34-35`), so the simulated-cartridge machinery's absolute ceiling is 128 banks. For 8 KB-bank types (Magic Desk, type 19: "up to 128 8k banks") that is 1 MB; for 16 KB-bank types (**MD2 / Magic Desk 16K, type 85: "up to 128 16k banks"**) it is **2 MB** — and type 85 is in our supported-cart list.
- *The market:* 2 MB MD2 cartridges are a real, current format (the MagicDesk2 open-hardware project explicitly targets 2 MB ROMs via 27C160 EPROMs; VICE added Magic Desk 16K support in 2025). EasyFlash is capped at 1 MB by its format (64 × 16 KB), GMod2 at 512 KB in our implementation (6-bit bank register). The only larger format, GMod3 (theoretically up to 16 MB), was never released as hardware, has no commercial software, and is not a supported cart ID (62) in this core — it bounds nothing.

**Odd base addresses are safe (verified):** every consumer of a `C_HMAP_*` base uses a full-width adder, never OR/concatenation tricks that would require power-of-two alignment — `sw_cartridge_csr.vhd:131-132` computes `qnice_hr_addr <= ("00000" & qnice_addr_i(27 downto 1)) + ("0000000000" & G_BASE_ADDRESS)`, `reu_mapper.vhd:100` computes `avm_address_s <= (... & reu_addr_i(18 downto 1)) + G_BASE_ADDRESS`, and `crt_parser` treats `req_address_i` as a free 22-bit word address it adds offsets to (`crt_parser.vhd:103-104,176`). Any window number 0x000–0x3FF works; bases are inherently 8 KB-aligned (window × 4096 words), so the byte-lane logic is unaffected. SIMCRT itself is doubly unaffected: its base stays x"0200" and nothing in the parser/cacher knows or cares where its pool *ends*. The one rule for the new mount bridge: **copy the `+` pattern** when applying `G_BASE_ADDRESS`.

So 2.71 MB covers every cartridge this core can address, with headroom. **Mandatory companion change:** nothing enforces the CRT pool boundary today — the Shell transmits the raw file size with no maximum check (`crts-and-roms.asm:548-559`), so an oversized `.crt` would now stream straight into the D81 buffer. Add a size check (file size ≤ 2,842,624 B) to the `.crt` mount path in the same commit that shrinks the pool.

### 7.4 Shell work: NONE (single drive makes the base address a hardware generic)

With one drive (decision #3), bake the HyperRAM base address into the bridge as a generic — exactly what the `.crt` loader already does: `sw_cartridge_wrapper` receives `G_BASE_ADDRESS` wired from `C_HMAP_CRT` (`mega65.vhd:1001`: `C_HMAP_CRT(9 downto 0) & X"000"`). The new mount bridge gets `G_BASE_ADDRESS` from `C_HMAP_VD0` the same way, so **QNICE device window 0 of `C_DEV_C64_MOUNT` = byte 0 of the image** — identical addressing semantics to today's BRAM. Consequences:

- `C_VD_BUFFER` in `globals.vhd:116-117` stays exactly as it is (`(C_DEV_C64_MOUNT, x"EEEE")`).
- `M2M/rom/vdrives.asm` and `M2M/rom/shell.asm` need **zero changes** for the buffer relocation — `LOAD_IMAGE`, `HANDLE_DRV_RD`, `HANDLE_DRV_WR`, and `FLUSH_CACHE` keep their window-0-based arithmetic (a D81 spans windows 0…199, a D64 windows 0…47). The only firmware-visible difference is read wait-states, which the RAMROM protocol already supports (`qnice_wrapper.vhd:472-475`).

(For the record, should multi-drive ever be revisited: the alternative is extending `C_VD_BUFFER` to (device, base-window) pairs plus a base-window `ADD` at the four buffer-touching Shell sites — `shell.asm:805-806, 1005-1033, 1098-1107, 1231-1279`. Not needed now.)

### 7.5 Performance projections (estimates — measure before tuning, see 16 phase 0)

Derived from QNICE ≈13 MIPS (`M2M/QNICE/doc/MIPS.md`) and loop instruction counts:

| Operation | Today (D64) | D81 projection |
| --- | --- | --- |
| Mount (full image SD→staging, f32_fread-bound, ~4–8 µs/byte) | ~0.7–1.4 s | **~3.5–8 s** behind the existing progress bar |
| Sector serve (Shell byte-pump, ~59 instr/byte) | ~1.2 ms / 256 B | **~2.2 ms / 512 B** (+ ≤0.8 ms worst-case HyperRAM-read stalls under ascal on R3) |
| Flush (full-image rewrite, 100 B per `HANDLE_IO` pass, `config.vhd:302`) | baseline | **4.69×** — likely tens of seconds; see risk 14.3 |

Optional optimization with precedent: block-wise `f32_fread` in `LOAD_IMAGE`'s `_LI_FREAD` (`shell.asm:823-834`) to cut mount delay (cf. the #228 browser speedup).

---

## 8. QNICE Shell changes (`CORE/m2m-rom/m2m-rom.asm`)

### 8.1 What does NOT need writing (verified — saves a week of imagined work)

The entire mount/serve/flush machinery is type-agnostic and multi-drive-generic: `VD_STROBE_IM` already writes img_type in the correct order before the strobe (`vdrives.asm:413-460`); the type flows `PREP_LOAD_IMAGE R9 → LOAD_IMAGE → HANDLE_MOUNTING R6→R12 → VD_STROBE_IM` (`shell.asm:539-557`); the serving loops use hardware-computed byte/window registers; all drive loops iterate `VDRIVES_NUM` with ascending per-drive windows (`vdrives.asm:506,524`); per-drive file handles and arrays are **auto-generated** by `make_rom.sh` from `C_VDNUM` (`make_rom.sh:64,79-93`). `M2M/rom/vdrives.asm` and the M2M framework need **zero changes** for D81 (the section 7.4 base-window work is the only framework-file touch, and it is additive).

### 8.2 `FILTER_FILES` (`m2m-rom.asm:92-95`) — trivial

Replace the single `.D64` check with a loop over a small table of extension-string pointers (`C64_IMGFILE_D64`, `C64_IMGFILE_D81`; **do not add `C64_IMGFILE_G64`** — section 12) using the register-preserving `M2M$CHK_EXT` helper (`tools.asm:22-50`). R11 carries the menu group ID (`m2m-rom.asm:74-79`) — useful later for per-drive filtering, ignore for now.

### 8.3 `PREP_LOAD_IMAGE` (`m2m-rom.asm:125-187`) — the one real routine

Contract (verified `shell.asm:717-722`): in R8 = FAT32 file handle (read pointer may be moved), R9 = context (`CTX_MOUNT_DISKIMG`), R10 = menu group ID; out R8 = 0/error, R9 = image type or error-string pointer. **The callback receives no filename** (the FAT32 FDH stores none, `dist_kit/sysdef.asm:325-339`), so detection is by size (passing the filename would change the M2M framework callback ABI shared with other cores — avoid). Replace the hardcode at line 184 with:

```
; pseudo-asm outline
;  R0 = file size (lo/hi from FDH, as the existing code already reads)
;  1) size in D64_STDSIZE table (174848 / 196608)?      -> R9 = C64_IMGTYPE_D64
;  2) size == 819200 (new D81_STDSIZE table, 1 entry)?  -> R9 = C64_IMGTYPE_D81
;  3) else -> R8 = error, R9 = WRN_WRONG_SIZE (updated message naming both formats,
;     explicitly: "D81 must be exactly 819200 bytes (no error-info variants)")
```

No seek games are needed for the size-only approach (the G64 magic-read + mandatory-seek-back-to-0 dance is shelved with G64 itself). Keep in mind `LOAD_IMAGE`'s copy loop has **no bounds check** (`shell.asm:805-870`) — this size table is the *only* overflow guard for the staging buffer; that is also why G64 (variable size) must not be enabled by just adding its extension.

### 8.4 Read-only flag — close an existing gap (decision recommended: yes)

`HANDLE_MOUNTING` hardcodes `XOR R11,R11` ("0 = read/write") before `VD_STROBE_IM` (`shell.asm:555`); the FAT32 read-only attribute is never honored. For the 1581 this matters doubly: fdc1772 *does* implement write protect (`wps_n` latched from `~img_readonly` at the mount edge, `c1581_drv.sv:61-66` → `fd_writeprot`, `fdc1772.v:301`), which would yield a clean DOS `26, WRITE PROTECT ON` — whereas today a write to a read-only-attributed file lands in the cache and the flush path treats `f32_fwrite` failure as **FATAL halting the whole core** (`ERR_FATAL_WRITE`, `shell.asm:~1290`). Recommended: read the FAT32 attribute at mount and pass it in R11 (one small, self-contained improvement that the 1581 makes visible).

### 8.5 Strings, messages, and the ROM budget ceiling

Update `WRN_WRONG_D64` (406–408), `WRN_NO_D64` (411–421; mention D64 *and* D81), and add the D81 size table + `WRN_JIFFY` extension (section 10). **Budget constraint discovered by the completeness pass:** the usable Shell ROM is 28,672 words, not 32 K (QNICE steals 0x7000–0x7FFF for MMIO: `qnice.vhd:519-523`), and the current `m2m-rom.rom` is **24,723 words = 86.2 % full** — < 4 K words remain for all D81 code, tables, and strings. The planned scope fits comfortably, but `make_rom.sh` performs **no size check** (an overflow fails obscurely at synthesis) — add a `wc -l` guard (fail if > 28672) to `make_rom.sh:127-135` as part of this work.

---

## 9. OSM / menu / C64MEGA65 config file

### 9.1 Minimal D81 (drive 8 only): almost nothing

Drive 8's existing `' 8:%s'` mount item (OPTM_GROUPS position 2, `config.vhd:395,538`) serves D81s unchanged — the browser, `%s` filename display, `<Saving>` indicator, and unmount/replace flows are all type-agnostic. Required edits are text-only: `HELP_1` "place your D64, CRT and PRG files there" (`config.vhd:116`), `HELP_2` (`config.vhd:147`). Help-text (WHS) changes do **not** affect `OPTM_SIZE`, so the minimal-D81 phase needs **no config-file version bump**.

### 9.2 Drive 9 — considered and decided against (sy2002, 2026-06-11)

No simulated drive 9 will be built; drive 8 is the only virtual drive. Beneficial side effects of this decision: the OSM needs **no menu changes at all** (no `OPTM_SIZE` change → no `CORE_VERSION`/config-file bump for the whole D81 effort), the hand-renumbering of ~35 positional `C_MENU_*` constants in `mega65.vhd:320-365` is avoided entirely, `HELP_3`'s IEC advice "Never run an external device that has the drive id #8. Always use #9 or higher" (`config.vhd:186-188`) **stays correct as-is**, and no hardware-IEC device-number collision policy is needed.

Compressed record for the future, should drive 9 ever be reconsidered (full analysis in the git history of this file): the OSM screen is full (31 visible rows + frame on a 33-row grid, no scrolling — a row must be freed or drives moved into a submenu); group ID 2 is pre-reserved (`OPTM_G_MOUNT_9`, `config.vhd:515`); drive numbering is ordinal over `OPTM_G_MOUNT_DRV` flags; `C_MENU_*` renumbering is silent-failure-prone; `OPTM_SIZE`/`CORE_VERSION`/`make_config.sh` must be bumped together; menu-heap margins are thin (`MENU_HEAP_SIZE`/`HEAP_SIZE` move in lockstep, `m2m-rom.asm:576-604`); menu line count vs. `C_VDNUM` vs. `C_VD_BUFFER` entries are runtime-FATAL-checked and must ship atomically; the only non-parametric VHDL spot is `c64_drive_led` (scalar at `main.vhd:259`, needs widening + OR-reduce); and the Shell needs the (device, base-window) pairs variant of 7.4.

---

## 10. JiffyDOS-1581 — the third ROM

### 10.1 Hardware path (decision: new device, not a widened window)

A separate device is **required**, not just preferred: the auto-load machinery forces the starting 4k window of `C_CRTROMTYPE_DEVICE` entries to 0 (`crts-and-roms.asm:180-184`), so a second file cannot be steered to offset 0x8000 inside device 0x0106 without modifying framework assembly. The decode also currently masks bits 15:14 (`mega65.vhd:874`). New decode case (clone of `mega65.vhd:873-877`):

```vhdl
when C_DEV_C64_KERNAL_C1581 =>                    -- x"0107", next free ID
   qnice_c1541rom_we      <= qnice_dev_we_i;
   qnice_c1541rom_addr    <= '1' & qnice_dev_addr_i(14 downto 0);  -- bit15=1 → 1581 ROM
   qnice_c1541rom_data_to <= qnice_dev_data_i(7 downto 0);
   qnice_dev_data_o       <= x"00" & qnice_c1541rom_data_from;
   -- readback only meaningful once iec_drive muxes rom_data_o on bit 15 (section 5.1);
   -- otherwise return x"EE". Either way: REGISTER new device read data (qnice_clk WNS 0.504 ns).
```

No port widening anywhere (all 16-bit already). 15 address bits cover the 32 KB ROM.

### 10.2 `globals.vhd` constants (exact mirror of the jd-c1541 entry, `globals.vhd:171-181`)

```vhdl
constant C_DEV_C64_KERNAL_C1581  : std_logic_vector(15 downto 0) := x"0107";
constant JIFFY_DOS_C1581         : string := "/c64/jd-c1581.bin" & ENDSTR;
constant JIFFY_DOS_C1581_START   : std_logic_vector(15 downto 0) :=
   std_logic_vector(to_unsigned(JIFFY_DOS_C64'length + JIFFY_DOS_C1541'length, 16));
-- C_CRTROMS_AUTO_NUM := 3;  append JIFFY_DOS_C1581 to C_CRTROMS_AUTO_NAMES;
-- APPEND (never insert!) the row (C_CRTROMTYPE_DEVICE, C_DEV_C64_KERNAL_C1581,
--                                 C_CRTROMTYPE_OPTIONAL, JIFFY_DOS_C1581_START)
```

Appending matters: `PREP_START` hardcodes `CRTROM_AUT_LDF` indices #0/#1 (`m2m-rom.asm:233-237`); the 1581 entry must be index #2. `CRTROM_AUT_MAX` auto-bumps via `make_rom.sh:66`.

### 10.3 Policy: graceful degradation (recommended)

`rom_std_i = c64_rom_i(0) or c64_rom_i(1)` (`main.vhd:1468`) — i.e. the single "JiffyDOS" Kernal radio item (`C_MENU_KERNAL_JIFFY=49` → `c64_rom="00"`, `mega65.vhd:497-501`) flips the C64 Kernal **and all drive DOSes together**, and `rom_std` is global per engine family (`c1581_multi.sv:71`). Keep this single-toggle UX (matches MiSTer; zero VHDL). The failure mode to design for: JiffyDOS selected but `jd-c1581.bin` missing → the 1581 would execute its custom slot. **The INITFILE'd custom slot from section 5.1 makes this safe**: the un-uploaded slot contains the standard 1581 DOS, so the 1581 silently falls back to stock while C64+1541 run JiffyDOS — mixed JD/stock on an IEC bus is protocol-compatible. Therefore keep `PREP_START`'s check requiring only LDF[0]+[1] (policy (a)), optionally logging a new debug-console warning when LDF[2] is absent. (Also note the pre-existing gap, unchanged by this work: *selecting* JiffyDOS mid-session with missing ROMs is unguarded until next boot, `m2m-rom.asm:320-331`; FAQ documents the black screen. A runtime guard would be a nice independent fix.)

### 10.4 File spec and docs

`jd-c1581.bin` = the commercial "JiffyDOS 1581 DOS ROM Overlay Image" (RETRO Innovations / Restore-Store), renamed, **exactly 32,768 bytes** (full replacement of the 1581's single 32 KB DOS ROM — unlike `jd-c64.bin`, no concatenation step) *(confirm the shipped file size before finalizing doc/jiffy.md — some JD packages ship multiple variants)*. Add a "C1581" section to `doc/jiffy.md` (pattern: lines 16–94). Guard worth adding: the auto-loader streams until EOF with no size check — a >32 KB file wraps `qnice_dev_addr_i(14 downto 0)` past window 7 and corrupts the image start; a ≠32768 size check in the Shell (or at minimum in the docs) prevents it.

---

## 11. Scope tiers for the drives

| Tier | Content | Status |
| --- | --- | --- |
| **A (the effort)** | Drive 8 mounts D64 (174,848/196,608) *or* D81 (exactly 819,200); 1581 engine enabled (one instance per drive type, section 5.2); HyperRAM staging; JiffyDOS-1581 | Specified, sections 5–10 |
| **B (decided against)** | Drive 9 / `C_VDNUM=2` | Rejected 2026-06-11; compressed record in section 9.2 |
| **C (explicitly out)** | G64 (section 12); error-info image variants — D64 175,531/197,376 and D81 822,400 (decision #4, section 6); CMD FD D2M/D4M images (rejected automatically by the exact-size rule — state in user docs); T64 (upstream handles it HPS-side; no equivalent here); 1581 burst mode (section 14.6); internal 3.5" drive as 1581 (section 15) | — |

---

## 12. G64: deliberately out of scope (and why)

`img_type=01` is **non-functional in our snapshot**: `c1541_direct_gcr` is commented out in `c1541_drv.sv:175-201` with sy2002's own note — "needs iecdrv_bitmem, which is currently commented-out in iecdrv_misc.sv; there are some CDC challenges inside: QNICE clock domain (sd_clk) to core (clk): track_len to buff_addr, and others" — `iecdrv_bitmem` is a half-finished wrapper inside `/* */` (`iecdrv_misc.sv:158-255`), `c1541_direct_gcr.sv` is in no project, and with `gcr_mode=1` the `dgcr_*` muxes select floating wires (`c1541_drv.sv:124-139`). The track-buffer side is ready (`c1541_track.sv` does 32-block/8 KB G64 track transfers), but the head-side CDC engineering is real, explicitly flagged by the original porter, and upstream has had post-snapshot G64 fixes (wraparound, weak bits) we are not taking. **Consequence for this effort: the Shell must not expose `.G64`** — the filter accepts `.D64`/`.D81` only. When G64 is eventually tackled, it inherits the D81 HyperRAM buffer for free (a fully-populated G64 exceeds 256 KB anyway) plus its own validation problem (no fixed size; `GCR-1541` magic + max-size bound, and `LOAD_IMAGE` gets its first real need for a bounds check).

---

## 13. Resource and timing budget (measured)

- 1581 engine, DRIVES=1: **+18.5 BRAM tiles** (58.2 % → 63.3 %), DRIVES=2: +21 total. LUT cost estimated 4–6 k against 109 k free *(estimate — no hierarchical report exists; confirm with `report_utilization -hierarchical` after first synth)*. The freed mount buffer returns 64 tiles when drive 8 moves to HyperRAM → **net BRAM change for Tier A is ≈ −45 tiles**.
- Drive-side logic is timing-benign (`main_clk` WNS 10.4 ns, everything behind the 16 MHz CE). The two watch-items: `qnice_clk` (0.504 ns — register new device read data) and `hr_rwds` (0.252 ns — don't crowd the I/O-locked HyperRAM placement; at 63 % BRAM the risk is low).
- R6 already uses a non-default timing-driven implementation strategy — preserve margin, re-check WNS on all four boards after each phase.

---

## 14. Risks, races, and runtime behavior (consolidated, with severity)

1. **SERIOUS / enable-blocker — fdc1772 SD CDC** (section 5.3). Naive enablement synthesizes but risks intermittent D81 corruption. Needs the re-clock/sync work plus a simulation testbench before hardware.
2. **BLOCKERS (compile/reach)** — `c1581_multi.sv:97` elaboration error; `mega65.vhd:874` 14-bit mask; 197 KB buffer; files missing from `.xpr` projects. All specified above; each is mechanical.
3. **SERIOUS / UX+data — flush window 4.69× longer.** During a D81 flush (819,200 B at 100 B/iteration): a soft reset is **silently dropped** (`prevent_reset`, `main.vhd:545,576` — not queued; button feels dead), a frustrated long-press hard reset **overrides** the protection and abandons a partially written image (`vdrives.vhd:331-345`); any new `sd_wr` **restarts the whole flush from byte 0** (`vdrives.vhd:364-374`) — a periodically-writing program (GEOS!) can starve completion indefinitely. Mitigations to evaluate: raise `VD_ITERATION_SIZE` (`config.vhd:302`) for D81-sized images, block-wise `f32_fwrite`, and a user-docs warning. Measure the real D64 flush time first (phase 0).
4. **SERIOUS — SD-card switch/eject during flush** (completeness-pass find): the browser allows F1/F3 SD switching at any time (`selectfile.asm:256-261,400-414`) and mid-flush `f32_fwrite`/`f32_fflush` failures are core-halting FATALs (`ERR_FATAL_WRITE`/`ERR_FATAL_FLUSH`). Recommended: refuse SD switch while any cache is dirty + docs warning.
5. **SERIOUS — JiffyDOS with missing `jd-c1581.bin`** → defused by the INITFILE'd custom slot (section 10.3). Without that edit, the 1581 executes zeroed BRAM.
6. **Fast serial / burst mode: not available, by physics.** The C64 lacks the C128's fast-serial CIA wiring; `.iec_fclk_i(1)` makes the 1581 DOS fall back to slow serial cleanly (CNT sees no edges, `c1581_drv.sv:124-127,158-161`). JiffyDOS-1581 (software protocol on CLK/DATA) is the speed path. The hardware IEC port's SRQ→CIA1 /FLAG wiring (`main.vhd:795-800`, issue #219) is unrelated and unaffected. State this in user docs — "will I get burst mode?" is the first question a 1581 user asks.
7. **Formatting:** fdc1772 **fakes WRITE TRACK** (instant IRQ, writes nothing — `fdc1772.v:643-647` "TODO: fake"); the 1581 DOS low-level `HEADER` format is a no-op at the media level. On an already-valid 819,200-byte image, the DOS's logical format (BAM/directory rewrite via normal sector writes) should still yield a usable disk — **needs an explicit test-plan entry**. Combined with the next point this defines the "new blank disk" story.
8. **Blank D81s cannot be created on-device**: the QNICE FAT32 library cannot create or grow files (no create API in `fat32_library.asm`; the reason `make_config.sh` exists). Users must bring a pre-made D81. Recommendation: ship/link a blank `empty.d81` with the release and say so in the user docs.
9. **Compatibility caveat to keep honest:** the ~2.2 ms/sector serve is safe for the *FDC* (timeout-free), but C64-side 1581 fastloaders/copiers with their own software timeouts are unexamined — hardware testing on R3 (worst HyperRAM contention) with HDMI + REU + CRT active is the gate, not the static analysis.
10. **Mount/reset semantics (existing behavior, document for testers):** every core reset — soft, hard, or QNICE-triggered (`.crt` mount, Kernal swap) — unmounts all virtual drives (`vdrives.vhd:308-326`, `options.asm:1023-1026`); the user remounts; the 1581 re-latches geometry on the mount edge and its disk-change line forces a BAM re-read (`fdc1772.v:174-190`, `c1581_drv.sv:223-227`). `dtype` staleness after unmount is benign (drive held in reset; relatch wins the race on remount, `iec_drive.sv:64` vs. `main.vhd:1416-1418`).
11. **1581 partitions/sub-directories work for free** (implemented by the 1581 DOS inside the image; the FAT32 browser never looks inside images) — one sentence for testers/users so it gets verified, not assumed.
12. **GEOS on D81** is the highest-value real-world test case (boot from D81, work disk via CONFIGURE, interaction of the shared Kernal menu bit with the GEOS RTC custom-Kernal path, `main.vhd:1468`); add to the test plan alongside `doc/GEOS_WITH_THE_C64_CORE.pdf`.
13. **NTSC:** PAL is currently hardcoded (`c64_ntsc <= '0'` @TODO, `mega65.vhd:495`) but NTSC work shares the V6 window. The 1581 is clock-agnostic by construction — `iec_drive_ce` is keyed off `clk_main_speed_i` with the explicit warning (issue #2) that it must use the vanilla `CORE_CLK_SPEED_PAL/NTSC`, never the flicker-free-adjusted speed (`main.vhd:1475-1503`). Add NTSC rows to the D81 test matrix when both land.

---

## 15. Relationship to sibling roadmap items

`ROADMAP.md:18-19` lists *two* 1581 features: "use the MEGA65's built-in 3.5″ drive as a C1581" and "simulated C1581 via *.d81". This document covers only the latter — but the architecture does not preclude the former: the 1581 engine consumes the MiSTer `sd_*` sector interface, so a future internal-floppy backend would replace **vdrives as the sector server**, not the drive engine. Enabling the engine now is a prerequisite investment for both.

---

## 16. Phased implementation plan

Phases 1 and 2 are independent and can proceed in parallel; 3 needs both; 4 needs 1.

**Phase 0 — baseline (half a day).** Build all four boards unchanged; archive utilization/timing reports. Measure on hardware: D64 mount wall time, D64 flush wall time (start a write, stopwatch the `<Saving>` indicator), to calibrate the section 7.5/14.3 projections. Run the existing D64 read/write regression (`tests/Disk-Write-Test.d64`).

**Phase 1 — 1581 RTL enablement (the engineering phase).**
Edits: `c1581_multi.sv` ROM rewrite + `rom_data_o` (5.1); `iec_drive.sv` comment-in + signal fixes + couplings + optional dtype sync (5.2); fdc1772 CDC work + SD-FSM reset clause (5.3); add files to 4 × `.xpr` (SystemVerilog type for `fdc1772.v`); XDC false paths (5.4).
Verification: simulation testbench for the fdc1772 CDC (sector read + write across the two-clock boundary — this is the one place simulation is non-negotiable); synthesize all 4 boards, confirm ~+18.5 BRAM tiles and clean WNS; **regression-test D64 on hardware** — with no D81 mounted the 1581 is permanently reset and the IEC AND-wiring must be transparent (this de-risks the core's most-used feature before any D81 exists). Note `synth_pre.tcl` auto-runs `make_rom.sh` at every synthesis — VHDL constants and asm regenerate together only if committed together.

**Phase 2 — HyperRAM staging (drive 8).**
Edits: byte-window bridge with `G_BASE_ADDRESS => C_HMAP_VD0` + `avm_arbit_general` in `mega65.vhd` (7.2/7.4); map constants in `globals.vhd` (7.3); `.crt` size bound (7.3); retire `mount_buf_ram`. **Zero firmware edits in this phase** — the window-0-based Shell arithmetic carries over unchanged (7.4).
Verification: QNICE-emulator headless test of the Shell window arithmetic where feasible (see memory: batch mode, `RUN` hex syntax); on hardware, D64 mount/run/write/flush through the *HyperRAM* path before D81 exists — same images, new plumbing, easy A/B against phase 0 baselines. Soak with HDMI + REU + `.crt` active on R3 (worst contention).

**Phase 3 — Shell D81 enablement (small).**
Edits: `FILTER_FILES` table (8.2); `PREP_LOAD_IMAGE` size detection, exactly-819200 rule (8.3); strings (8.5); `make_rom.sh` ROM-size guard (8.5); read-only flag if approved (8.4); help texts HELP_1/HELP_2 (9.1).
Build: `cd CORE/m2m-rom && ./make_rom.sh` (no config-file bump needed in this phase).
Verification: mount a D81, `LOAD"$",8` / load a program; write + flush + power-cycle + verify (a `Disk-Write-Test.d81` counterpart to the existing D64 asset should be created); wrong-size D81 rejection message; GEOS-from-D81; 1581 partition commands; JiffyDOS C64+1541 active with a stock 1581 (mixed-bus protocol check).

**Phase 4 — JiffyDOS-1581.**
Edits: `globals.vhd` constants (10.2); `mega65.vhd` 0x0107 decode with registered read data (10.1); optional readback mux in `iec_drive.sv`; `PREP_START` policy + optional warning (10.3); `doc/jiffy.md` (10.4).
Verification: boot with/without `jd-c1581.bin`; JiffyDOS toggle exercising all three ROMs; fallback-to-stock-1581 behavior; JD-1581 fastload benchmark vs. stock.

**Phase 5 — does not exist.** Drive 9 was decided against (decision #3, section 9.2).

**Phase 6 — docs & release.**
- `tests/README.md`: **prepend** a `Version X - TBD` section (append-only, newest-on-top convention) with the D81/1581/JiffyDOS-1581 test procedures from phases 3–4.
- `VERSIONS.md`: the feature bullet goes into the **existing unreleased "Version 6" section** (it already carries @TODOs), not a new one.
- `ROADMAP.md:19` moves from planned to shipped; `README.md:134-136` and `FAQ.md` gain the simulated-1581 (and burst-mode-expectations) entries.
- End-user docs at c64.mega65.org are maintained by Kugelblitz360 — explicit hand-off task with the user-visible behavior list (exact-size rule for D64/D81, flush durations, blank-D81 story, jd-c1581.bin spec).
- Release packaging: 4 × bitstream + `bit2core` per board (no CI exists — all four synths are manual).

---

## 17. Open questions for the maintainer

1. **Flush UX:** accept the projected D81 flush duration, or tune (`VD_ITERATION_SIZE`, block-wise `f32_fwrite`) first? (Measure in phase 0 before deciding.)
2. **Read-only flag** (8.4): adopt FAT32-attribute honoring in this effort? (Recommended: yes.)
3. **JD-1581 fallback policy**: graceful (recommended, 10.3) vs. strict all-three.
4. **`jd-c1581.bin` shipped size**: confirm exactly 32,768 bytes before `doc/jiffy.md` is finalized.
5. **XDC clock groups**: verify `qnice_clk`/`main_clk` asynchronous-group declarations cover the new crossings, or add explicit `set_false_path`/`ASYNC_REG`.
6. **c1541 symmetry**: retroactively give the 1541's custom slot `INITFILE=c1541_rom.mif.hex` too (same graceful-degradation property; makes `PREP_START`'s revert purely cosmetic)?

(Resolved since first draft: drive 9 → rejected, section 9.2; D81 error-info variant → rejected at step one, decision #4 in section 1.)

---

## Appendix A — upstream changes deliberately not taken (snapshot 2023-06-21)

Per the no-upstream-sync decision; the 1581 core logic upstream has been functionally stable since 2021-07-15 ("C1581: update fdc1772" — already in our snapshot), so nothing 1581-critical is being left behind. Post-snapshot upstream `rtl/iec_drive` commits, titles only: "C1541: adjust disk change signals" (2024-01-02); "Block keyboard and activate led while disk swapping" (2024-01-27); "IEC: fix for g64 buffer wraparound" (2025-08-15, G64-only); "Implement simple weak-bits feature" (2025-09-08, G64); "low level read logic from schematics and independent disk rotation" (2025-10-11, G64/1541); "Add mount read only, rpm and wobble options" (2025-10-14); "Full DDRAM Image Loading, DMA Engine & Drive OSD" (2026-05-11); "Fix: Disk Swap when Drives set to always enabled" (2026-05-13); "Hook up 1581 to OSD" (2026-05-16, MiSTer-OSD-only). Upstream also refactored `fdc1772.v`'s parameters (`SECTOR_SIZE_CODE/SECTOR_BASE` → `IMG_TYPE`); our local `c1581_drv.sv`/`fdc1772.v` pair is the matching pre-refactor version and is internally consistent.

## Appendix B — corrections made by adversarial verification (so they don't resurface)

- The Shell **does** write img_type (claim "never written" refuted): `VD_STROBE_IM`/`VD_TYPE` exist; only the C64 callback hardcodes D64.
- `MAXIMUM_SIZE` does not shrink BRAM (measured: 64 RAMB36 for the 256 KB buffer).
- "Plain uncommenting" of the 1581 fails on signal names *and* the `iecdrv_mem` parameter error *and* missing project registration — three independent blockers.
- The ROM path is 16-bit everywhere, but `mega65.vhd:874` masks bits 15:14 — reachability, not width, was the issue.
- The 512-byte transfer is one 1581 *physical* (MFM) sector = two 256-byte logical sectors.
- PR #228 was the file-browser mergesort, not file-handle work (per-drive persistent handles are older M2M infrastructure — and they exist, which is what matters).
- A D81 needs **200** 4k windows (819200/4096), not "~818".
- D81-in-BRAM: with the measured 18.5-tile engine cost, even the best single-drive BRAM scenario totals 367/365 tiles — infeasible outright, not merely impractical.
