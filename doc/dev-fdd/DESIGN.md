# Physical 1581 READ path — architecture freeze (pragmatic milestone)

Authoritative design for the read-only milestone. Pragmatic (approach B): real WD1772 + real
DD-MFM decode + real mechanics + Image<->Internal switch; safety that prevents obvious harm;
NO epoch/generation/dual-ack/late-fault ceremony. Write/format is a later milestone.

## 0. Milestone scope
- OSM single-select "Use internal 1581 Off/On" below the `8:` mount line (flat index 3).
- When On + idle: drive 8 source = physical mechanism. `load"$",8` / `load"name",8` read from the
  real DD disk. Directory, LOAD work. Writes are blocked (disk presented write-protected).
- Type-I (Restore/Seek/Step) really moves the head; Read Sector / Read Address / Verify use real
  MFM/CRC from media; Force Interrupt cancels. Read Track = optional stretch, else stub-safe.
- `f_wgate_o`/`f_wdata_o` stay tied '1' at the top (never routed live this milestone).
- Capability true on all four boards (R3/R4/R5/R6); functional testing on R3.

## 1. Controller placement & clocking  (from recon §1)
- **Controller = new VHDL, instantiated in `main.vhd`, clocked on `c64_clk_sd_i` (exactly 50 MHz =
  QNICE clock).** Reset: new `c64_rst_sd_i` port on `main` <= `qnice_rst_i`.
- Rationale: keeps the SV<->VHDL boundary at the existing `main`<->`iec_drive` seam; VHDL controller
  stays fully GHDL-testable; no new PLL/MMCM/clock net (50 MHz already reaches the drive subsystem).
- fdc1772.v / c1581 run on `clkcpu` ~16 MHz (gated 31.528 MHz) with `clk8m_en`/`wd_ce` strobes.
- No PLL `locked` is exported anywhere -> use `rst_i` de-assertion as the "clock valid" proxy.

## 2. Where the ABI crosses languages / clocks
- The physical **f_* pins** thread as plain wires: `top_mega65-r*` -> `mega65.vhd`(MEGA65_Core) ->
  `main.vhd`. They connect ONLY to the controller (VHDL). No CDC (pins are async; controller
  synchronizes inputs internally with 2-FF + qualification).
- The **drive<->controller ABI** (mechanics requests, read requests, results, live state) crosses the
  SV(drive ~16 MHz) <-> VHDL(controller 50 MHz) boundary. Chosen discipline:
  - **The controller (VHDL, 50 MHz) owns all CDC.** Drive-domain signals arrive raw; the controller
    2-FF-synchronizes levels and uses toggle handshakes for events. Results/state cross back to the
    drive domain and are re-synchronized on the SV side with the existing `iecdrv_sync` (mirrors
    `fdc1772.v:783-802`).
  - **Read-byte stream** uses a dedicated dual-clock FIFO (`physical_1581_rdfifo`, ~32 bytes):
    write side 50 MHz (controller), read side drive-clock (fdc1772 drains it with its existing DRQ
    pacing `fd_dclk_en`). This is the elastic queue; it absorbs CDC latency only, never hides a DRQ.

## 3. Module list  (`CORE/vhdl/physical_1581/`)
| File | Role |
|---|---|
| `physical_1581_pkg.vhd` | constants (G_FDC_HZ, gap windows, timers), result codes, op codes, helper fns |
| `physical_1581_crc.vhd` | CRC-16/CCITT-FALSE (adapted crc1581.vhdl) |
| `physical_1581_mfm_gaps.vhd` | RDATA flux edge -> gap-cycle count (adapted) |
| `physical_1581_mfm_quantise.vhd` | gap -> short/med/long class, spec windows @50MHz (adapted, retuned) |
| `physical_1581_mfm_gaps_to_bits.vhd` | gap class -> data bits + A1 sync (adapted) |
| `physical_1581_mfm_bits_to_bytes.vhd` | bit stream -> byte framing (adapted) |
| `physical_1581_mfm_decoder.vhd` | top codec: 3xA1 gate, FE/FB/**F8**, CHRN, ID-vs-data CRC (adapted+extended) |
| `physical_1581_inputs.vhd` | 2-FF sync + qualify index/track0/wp/change; RDATA 2-FF sync |
| `physical_1581_controller.vhd` | operation/mechanics FSM: motor/select/side/step, read seq, watchdogs |
| `physical_1581_rdfifo.vhd` | dual-clock read-byte FIFO (50MHz write, drive-clk read) |
| `physical_1581_diag.vhd` | read-only QNICE diagnostic register bank (`C_DEV_C64_PHYS1581`) |

Codec sub-stages kept as separate entities (clean diff from upstream, independently GHDL-testable).

## 4. Controller ABI (drive domain <-> controller)  — final names in physical_1581_pkg.vhd
Requests INTO controller (from drive domain, ~16 MHz):
- mode: `phys_active` (level). mechanics: `cia_motor_on` (PA2 positive), `cia_side` (PA0: 0=side0/1=side1).
- step event: `step_req_tgl` + `step_outward` (1=toward track0) -> ack `step_ack_tgl`.
- read event: `rd_req_tgl` + `rd_op[2:0]` (READ_SECTOR/READ_ADDRESS/VERIFY/READ_TRACK) +
  `rd_track[7:0]` + `rd_side` + `rd_sector[7:0]`; cancel `rd_cancel_tgl`.
Results OUT of controller (to drive domain):
- `rd_done_tgl` + `rd_result[4:0]` (RES_* subset) + `rd_crc_err` + `rd_rnf` + `rd_deleted` +
  found `rd_c/h/r/n[7:0]`.
- byte stream: FIFO read port `byte_rd_en` (in) / `byte_data[7:0]` / `byte_empty` (out).
- live state (levels): `st_media_ready`, `st_index_q` (qualified), `st_track0`, `st_wprot`,
  `st_change` (sticky), `st_motor_on`.
Physical pins (controller drives, read-only): `f_motora_o` `f_selecta_o` `f_side1_o` `f_stepdir_o`
`f_step_o` `f_density_o`; reads `f_rdata_i` `f_index_i` `f_track0_i` `f_writeprotect_i` `f_diskchanged_i`.
Diagnostics: `diag_*` bus to `physical_1581_diag`.

## 5. Op set + status mapping (pragmatic, from spec §10.2)
- Type-I: Restore = step outward until track0 (bounded 255 + watchdog); Seek = step to Data-reg target;
  Step/In/Out. Each step: DIR setup 24us, 4us low pulse, >=3ms (>=4ms reversal) recovery, final 18ms settle.
- Read Sector: search ID (valid CRC, C=track, R=sector, ignore H); N must=2 else RNF+unsupported; wait
  FB/F8 DAM; stream 512 bytes at real cadence into rdfifo; check data CRC; bit5=deleted for F8.
- Read Address: return real C,H,R,N,CRC-hi,CRC-lo; set Sector reg = C.
- Verify: search valid ID with C=track; Seek Error on fail (+CRC if only bad-CRC IDs).
- Force: cancel current op at a byte-safe boundary, bounded.
- Status bits (fdc1772 `:971-979`): b3 CRC = real (un-hardwire `1'b0` at `:976`); b4 RNF = real from
  controller; b2 track0(type1); b1 index(type1); b7 motor; b5 spin-up(type1)/deleted(readsec).
- No-index / not-ready / RNF distinct via absolute watchdogs (spec §11.2 values baked as constants).

## 6. Timing constants (baked; spec initial values, 50 MHz)
G_FDC_HZ=50e6. MFM half-cell=100cy(2us); gaps 200/300/400cy(4/6/8us); gap windows short 160-240,
med 258-342, long 355-445 (spec §14.3). Motor ready >=505ms; ready deadline 1.10s; DIR setup 24us;
STEP low 4us; step interval >=3ms/>=4ms; settle 18ms; DAM within 43 byte-times(1.376ms); ID search
5 index edges + 1.300s; Restore 255 + 3.2s; index qualify width 1.5-5ms accepted, period 150-250ms
plausible. All in `physical_1581_pkg.vhd`, sim-acceleration generics allowed.

## 7. How the 12 recon risks are handled
1. **Step direction not exposed** -> add `step_outward` output to fdc1772 (from `step_dir` at `:490`); real `f_track0_i` closes Restore.
2. **Two-phase read handshake** -> physical read has no SD pre-fill; controller: search-ID -> DAM -> stream; fdc1772 waits on controller `rd_done`/byte stream, not a virtual header.
3. **ID timing granularity** -> controller latches decoded CHRN stable; fdc1772 uses controller result, not `fd_sector_hdr` sampling.
4. **Ready/spin-up coupling** -> `st_media_ready` gates on real index-based spin-up (>=505ms + 2 qualified edges), feeds PA1 + status b7/b5.
5. **img_mounted latches never fire** -> in physical mode re-source `fd_present=1`, `wps_n`, `disk_chng_n`, `floppy_ready` from controller `st_*`, not from mount.
6. **1581 engine held in reset w/o D81** -> `physical_mode` forces engine active (`iec_drive.sv:168` gate) and is treated as `img_type="10"`.
7. **Non-integer async CDC 50->16MHz** -> toggle handshakes + `iecdrv_sync`; watch generate-block undriven-net Vivado hazard.
8. **Write path inert** -> `sd_wr=0` (`iec_drive.sv:109`), disk presented WP, `f_wgate/f_wdata` tied '1', never pulse `sd_card_write`.
9. **Head/side & double-sided** -> `cia_side` (PA0) selects surface; controller drives `f_side1_o` with spec inversion; found H diagnostic only.
10. **Diag device** -> yes, build `C_DEV_C64_PHYS1581=0x0108` read-only BRAM (user has no instruments).
11. **NTSC clock** -> irrelevant; controller timing derives from exact 50 MHz, never main clock.
12. **OPTM_DY recount** -> trust `menu_test.py verify` as authority (27->28).

## 8. fdc1772.v physical-mode changes (concise)
- Add `phys_mode` + the ABI ports (§4). Latch source at command start.
- Type-I: emit `step_req_tgl`+`step_outward` per WD step; wait `step_ack_tgl` before next/settle.
- Type-II/III read: emit `rd_req_tgl`+op/track/side/sector; drain rdfifo via `fd_dclk_en` DRQ pacing;
  finalize status from `rd_result`/`rd_crc_err`/`rd_rnf`/`rd_deleted`/found CHRN.
- Status: un-hardwire b3 CRC (`:976`); RNF from controller; Read Address bytes from controller.
- Block writes: write-sector/write-track never reach the mechanism; present WP.
- Keep entire image path unchanged behind `~phys_mode`.

## 9. Threading summary (ports to add)
- `top_mega65-r*`: route 11 f_* pins into MEGA65_Core; drop them from the `<='1'` block (keep wgate/wdata/selectb/motorb '1').
- `mega65.vhd`: add 11 f_* ports; `C_MENU_INTERNAL_1581=3` (+shift all C_MENU_* >=3); decode -> `phys_1581_en`; pass f_* + `phys_1581_en` + `c64_rst_sd_i` to `main`.
- `main.vhd`: add `phys_1581_en_i`, `c64_rst_sd_i`, 11 f_*; instantiate controller + rdfifo + diag; thread ABI down to `iec_drive`.
- `iec_drive.sv`: add `physical_mode`; gate `sd_rd/sd_wr` (`:108-109`); force 1581 engine active (`:168`,`:116`); thread ABI to `c1581_multi`.
- `c1581_multi.sv` / `c1581_drv.sv`: thread ABI to `fdc1772`; re-source PA1/PA7/PB6; CIA PA2->`cia_motor_on`, PA0->`cia_side`.
- `config.vhd`: item at flat 3, `OPTM_G_INT1581=31`, `OPTM_SIZE 159->160`, `OPTM_DY 27->28`, `CORE_VERSION WIP-V6-A18X1`, help.
- `osm_const.asm`: `C64_OSM_*` flat >=3 shift +1; add `C64_OPTM_G_INT1581 .EQU 31`.
- `m2m-rom`: ignore Image<->Internal toggle while drive access is running (idle gate).
- `globals.vhd`: `C_DEV_C64_PHYS1581 x"0108"`.
- `CORE-R*.xpr/.tcl`: add new VHDL in dependency order.

Verification gates: GHDL for VHDL codec+controller (+ VHDL behavioral mechanism model); iverilog for
fdc1772 SV where it compiles; `menu_test.py verify`. Full mixed chain + synthesis = user (Vivado).
