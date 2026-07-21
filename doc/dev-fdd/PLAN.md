# Physical 1581 (issue #90) — Implementation Plan & Checkpoint

> Integration note (2026-07-21): The completed read-only milestone is now
> integrated into `develop` for `WIP-V6-A19`, and these working notes live in
> `doc/dev-fdd/`. Feature-branch and no-commit statements below describe their
> historical checkpoints.

Living checkpoint. Update after every major step so work can resume after any interruption.

## Locked decisions (2026-07-12)
- **Approach: pragmatic-functional (B).** Same real behavior as the spec; trim its
  epoch/media-generation/request-id/dual-ack/late-fault/outer-writer-arm ceremony to
  what a single internal drive needs. Keep safety that prevents obvious harm:
  never WGATE on write-protect/eject, watchdogs so BUSY/WGATE can't hang, safe power-up levels.
- **First milestone: READ-ONLY.** OSM source toggle + Type-I mechanics (Restore/Seek/Step)
  + Read Sector/Read Address/Read Track/Verify/Force Interrupt. WGATE/WDATA stay clamped
  inactive. Write Sector + Write Track/format = the next milestone.
- **Boards: all four (R3/R4/R5/R6).** `G_PHYS1581_CAPABLE` set TRUE in all four board
  projects (user synthesizes all four). Functional testing happens on R3.
- **Source switch gated idle-only**, enforced in `CORE/m2m-rom/*.asm`: ignore an
  Image<->Internal toggle while any drive access is running. No cache-drain machinery.
- **QNICE diag device** `C_DEV_C64_PHYS1581 = 0x0108`, read-only + `doc/1581_dd_debug_device.md`.
- **CORE_VERSION -> `WIP-V6-A18X1`** (then X2, X3, ... as more features land); regenerate 160-byte config.
- **No commits** (user commits). Both repos (parent + `CORE/C64_MiSTerMEGA65` submodule) on `mh_implement_90`.
- **Licensing: mix-and-match freely.** MEGA65 code (LGPL/GPL) is reused without concern; keep
  only a light "adapted from mega65-core" one-line comment on adapted files. No provenance tables,
  no GPL-vs-LGPL compatibility work. (User: MEGA65 project are good friends.)
- No Vivado / no hardware instruments here. Bake spec's stated initial timing values as the
  real constants. `G_FDC_HZ = 50_000_000`. User runs Vivado build + flashes + functional-tests.
- Verification here: GHDL (VHDL controller/codec/CRC + VHDL behavioral mechanism model),
  iverilog (SV fdc1772 where it compiles). Full mixed-language chain + synthesis = user side.

## Environment facts (verified)
- GHDL 5.1.1, iverilog present; NO vivado/verilator/questa.
- #91 upper half present (c1581_drv.sv, c1581_multi.sv, fdc1772.v, iec_drive.sv, floppy.v).
- Bundled c1581_rom.mif.hex sha256 == spec anchor 8f689277... (318045-02), 32768 bytes.
- Adapted MFM/CRC helpers + spec's pinned commit a9158930 present in local ../mega65-core.
- config.vhd: OPTM_SIZE=159, OPTM_DY=27 (matches spec baseline). f_* pins default '1'.

## Phases (read-only milestone)
- **R0 recon + design freeze** — map hierarchy, freeze ABI + timing package + menu delta.  [IN PROGRESS]
- **R1 VHDL modules** — physical_1581_pkg / inputs / crc / mfm_decoder / controller(read) / diag
  + VHDL behavioral mechanism model + GHDL testbenches.
- **R2 fdc1772.v physical-read branch** — Type-I/ReadSector/ReadAddress/ReadTrack/Verify/Force,
  real status/CRC/DRQ/IRQ, drive-domain<->50MHz CDC + iverilog bench.
- **R3 thread ABI + plumbing** — main.vhd controller instance; iec_drive/c1581_multi/c1581_drv
  ports; gate sd_* off in physical mode; mega65.vhd + top_mega65-r3.vhd physical pins live (R3).
- **R4 menu + config** — config.vhd (OPTM_SIZE 159->160, OPTM_DY 27->28, OPTM_G_DRIVE8_SOURCE=31,
  item at flat idx 3, help), mega65.vhd C_MENU_INTERNAL_1581=3 + shift, m2m-rom idle-gate,
  CORE_VERSION bump, menu ROM rebuild, menu_test.py.
- **R5 QNICE diag device** — globals C_DEV, mega65 decode, diag register bank + doc.
- **R6 project files** — CORE-R*.xpr/.tcl source lists (all four), light upstream-attribution
  comments on adapted files, GHDL/iverilog compile checks.

## Status log
- 2026-07-12: spec read end-to-end; env verified; 5 scoping decisions answered; decisions locked above.
- 2026-07-12: R0 recon workflow launched (writes scratchpad/recon_map.md).
- 2026-07-12: user updates: capability ON for all 4 boards (test on R3); version = WIP-V6-A18X1.
- 2026-07-12: codec-adaptation study launched (mega65-core @ a9158930 MFM/CRC helpers -> scratchpad/codec_adaptation.md).
- 2026-07-12: recon workflow + codec study DONE. Working notes relocated to doc/dev-fdd/
  (PLAN.md, recon_map.md, codec_adaptation.md, DESIGN.md, upstream/*). Maintained here now.
- 2026-07-12: **R0 DONE** — architecture frozen in DESIGN.md. Key facts: controller in main.vhd on
  c64_clk_sd_i (50 MHz, already in drive subsystem); CDC via iecdrv_sync toggles; read bytes via
  dual-clock rdfifo drained by fd_dclk_en; controller placed at the existing main<->iec_drive SV/VHDL
  seam so VHDL stays GHDL-testable. Add c64_rst_sd_i to main. 12 integration risks logged in recon_map.md.
- 2026-07-12: **R1 in progress**. CORE/vhdl/physical_1581/physical_1581_pkg.vhd (constants) +
  physical_1581_crc.vhd written. GHDL tb_physical_1581_crc PASSES all vectors (A1A1A1=CDB4, +FE=B230,
  +FB=E295, "123456789"=29B1, zero-residue=0000). Tb: CORE/vhdl/test/tb_physical_1581_codec/.
- 2026-07-12: R1 cont. — 4 MFM pipeline stages (gaps/quantise/gaps_to_bits/bits_to_bytes) delegated to a
  subagent (faithful port + retuned 50MHz windows + GHDL analyze). Next: write clean mfm_decoder top +
  synthetic-flux GHDL testbench (canonical sector round-trip) myself, then physical_1581_inputs.

- 2026-07-12: **R1 codec DONE & GHDL-verified.** Files in CORE/vhdl/physical_1581/: physical_1581_pkg,
  _crc, _mfm_gaps, _mfm_quantise, _mfm_gaps_to_bits, _mfm_bits_to_bytes, _mfm_decoder. Tests in
  CORE/vhdl/test/tb_physical_1581_codec/: tb_physical_1581_crc (5 vectors PASS),
  mfm_flux_gen_pkg (synthetic flux + crc16), tb_physical_1581_mfm_decoder (canonical sector: ID CHRN,
  512-byte payload byte-exact, ID+data CRC ok, F8-safe embedded values — PASS). Decoder streams every
  ID (C/H/R/N + crc_ok + stored CRC) and data field (bytes + deleted + crc_ok); the operation FSM does
  matching. CRC coverage: reset at 1st A1 sync, feed A1x3 synthetically (bits_to_bytes flags A1 via
  sync_o not a byte), then mark+fields+stored CRC -> residue 0.

## GHDL build recipe (codec)
B=<tmpdir>; ghdl -a --std=08 --workdir=$B CORE/vhdl/physical_1581/{physical_1581_pkg,_crc,_mfm_gaps,
_mfm_quantise,_mfm_gaps_to_bits,_mfm_bits_to_bytes,_mfm_decoder}.vhd \
CORE/vhdl/test/tb_physical_1581_codec/{mfm_flux_gen_pkg,tb_physical_1581_mfm_decoder}.vhd ;
ghdl --elab-run --std=08 --workdir=$B <tb> --assert-level=error   (no `timeout` on macOS; tbs self-bound)

- 2026-07-12: **R1 inputs + rdfifo DONE & GHDL-verified** (subagent). physical_1581_inputs.vhd
  (2FF sync + glitch-filtered index edge/period/width; index_period=300/width=100 exact in tb;
  glitch rejected; polarity correct). physical_1581_rdfifo.vhd (Cummings Gray-code async FIFO,
  first-word-fall-through; 200 bytes in-order across relatively-prime clocks). Tbs in
  CORE/vhdl/test/tb_physical_1581_inputs/. NOTE: change_o polarity assumed active-low; confirm on R3.
- 2026-07-12: **R1 controller WRITTEN & compiles** (physical_1581_controller.vhd, analyze rc=0).
  50MHz FSM: instantiates inputs+decoder; drives motor/select/side/step/dir/density; synthesizes
  media_ready (motor on + >=505ms + >=2 index edges + plausible period + no change), head-settle 18ms
  timer, sticky disk-change latch; toggle-handshake ABI (step_req/ack, rd_req/done, cancel); STEP
  engine (24us DIR setup, 4us pulse, 3/4ms recovery, 18ms settle, head-estimate, track0 anchor);
  READ engine (Read Sector match C+R ignore H, N=2 gate, DAM-within-43-bytes, stream to rdfifo,
  data CRC; Verify match C; Read Address = next ID's C/H/R/N+stored CRC; search 5 index edges +
  1.3s watchdog; RNF/ID-CRC/data-CRC/unsupported-size/not-ready/cancelled/disk-changed results).
  Pragmatic deviation: restore_required tracked (head_valid) but NOT hard-blocking reads (reads match
  decoded C; 1581 ROM seeks first). Writes never driven (read-only). Timers are generics (spec defaults).
- 2026-07-12: mechanism model + golden payload pkg + self-test delegated (drives f_* connector pins,
  step->head, index spin, per-track/side flux; verified through the real decoder). IN FLIGHT.

- 2026-07-12: **R1 COMPLETE & CLOSED-LOOP VERIFIED.** tb_physical_1581_controller.vhd (controller +
  rdfifo + mech_model_1581 + golden_1581_pkg) PASSES: Restore clears power-up change latch; media_ready
  ~398ms; Read Sector cyl0/sec1 OK + 512 payload bytes MATCH golden; Read Address C=00 N=02 (6 bytes);
  Verify OK; Type-I Step In moves head to cyl1 (model + estimate agree); Read Sector cyl1/sec1 OK + MATCH;
  absent sector -> RNF. Full path proven in sim: request -> motor spin/index -> real head stepping ->
  DD-MFM flux decode -> CRC -> payload. IMPORTANT design note surfaced & kept: controller conservatively
  latches disk-change at power-up (spec 13.4/16.3); media_ready stays false until a Type-I step clears it
  (spec 13.2 permits stepping while not-ready). The 1581 ROM's init Restore does this on real HW.

## R2 iverilog finding (2026-07-12)
fdc1772.v PARSES under `iverilog -g2012` but the existing MiSTer code has declaration-after-use
(parameter `W` used in ports before its line-75 declaration; floppy.v `sec_state`/`SECTOR_STATE_*`
localparams declared after use). iverilog rejects these; Vivado tolerates them. So R2 needs minimal,
safe declaration-order reorders to be iverilog-testable here; otherwise verification is on the user's
Vivado xsim + hardware. iecdrv_sync is in iecdrv_misc.sv. floppy is image-mode only (stub it for a
physical-mode tb). The controller (VHDL) does the real work; fdc1772 phys-mode is WD reg/DRQ/status
translation, so its ultimate proof is the user running DOS load/dir on real hardware.

## R1 STATUS: DONE (all read-side RTL written, compiles, GHDL-verified behind G_PHYS1581_CAPABLE)
Modules CORE/vhdl/physical_1581/: pkg, crc, mfm_gaps, mfm_quantise, mfm_gaps_to_bits, mfm_bits_to_bytes,
mfm_decoder, inputs, rdfifo, controller. Tests (all PASS) under CORE/vhdl/test/: tb_physical_1581_codec/
(crc, mfm_decoder + mfm_flux_gen_pkg), tb_physical_1581_inputs/ (inputs, rdfifo), tb_physical_1581_controller/
(controller + mech_model_1581 + golden_1581_pkg). GHDL recipe in this file (codec section).
Deferred (nice-to-have, spec MFM-R04..R07): codec edge tbs for F8-deleted, bad ID/data CRC, jitter corners.

- 2026-07-12: **R2 DONE & iverilog-verified.** fdc1772.v (submodule) got a phys_mode read branch
  (+441/-67): flat phys_* ABI matching the controller; iecdrv_sync CDC (level-compare edge detect on
  synced toggles); Type-I step handshake; Read Sector/Address/Verify -> phys_rd_req + rdfifo DRQ drain;
  status b3 CRC un-hardwired + RNF/deleted/track0/index/motor from physical state; writes blocked (WP);
  Force toggles phys_rd_cancel. Declaration-order reorg for iverilog (params->ANSI header incl W=FD_NUM-1;
  forward-decl block; wire->assign) -- param NAMES preserved so c1581_drv instantiation still binds.
  tb_fdc1772_physical.sv (mock backend + real async FIFO + iecdrv_sync + floppy stub) PASSES independently:
  Restore->track0/INTRQ, Seek(3)->cyl3, Read Sector->512 bytes + status 0x80. Subagent caught+fixed a real
  DRQ double-pop bug. NOTE: phys_mode floats in the current c1581_drv instantiation until R3 wires it (=0
  for image); if(phys_mode) with z reads false so image path is taken, but R3 must drive it explicitly.
- 2026-07-12: adversarial review of the fdc1772 diff IN FLIGHT (image-mode byte-identical? DRQ-pace change
  phys-only? decl-reorg neutral? status word unchanged for phys_mode=0?). Highest risk = the DRQ-pace fix.

- 2026-07-12: **R2 adversarial review PASS** (all 7 checks: phys logic fully gated on phys_mode; image
  DRQ pacing + status word byte-identical for phys_mode=0; decl-reorg neutral; build clean). Only finding
  = phys_mode floated in c1581_drv (expected WIP). FIXED: tied `.phys_mode(1'b0)` in c1581_drv.sv
  instantiation (R3 replaces with real threading). Tree now image-safe. **R1 + R2 DONE & VERIFIED.**
- 2026-07-12: R3 SV-threading (iec_drive/c1581_multi/c1581_drv) delegated + iverilog compile-check. IN FLIGHT.

## R3 threading map (controller lives in main.vhd; f_* pins are VHDL-only; the phys_* ABI bundle threads
## fdc1772(SV) <-> main controller(VHDL) THROUGH c1581_multi -> iec_drive):
- fdc1772 phys_* OUTPUTS (->controller in): phys_step_req_tgl, phys_step_outward, phys_rd_req_tgl,
  phys_rd_op[2:0], phys_rd_track[7:0], phys_rd_side, phys_rd_sector[7:0], phys_rd_cancel_tgl,
  phys_byte_rd_en, phys_active, phys_cia_motor_on(=floppy_motor), phys_cia_side(=floppy_side).
- fdc1772 phys_* INPUTS (<-controller out): phys_step_ack_tgl, phys_rd_done_tgl, phys_rd_result[4:0],
  phys_rd_crc_err, phys_rd_rnf, phys_rd_deleted, phys_rd_c/h/r/n[7:0], phys_byte_data[7:0],
  phys_byte_empty, phys_media_ready, phys_index, phys_track0, phys_wprot, phys_change, phys_motor_on,
  phys_head_settled. Plus phys_mode INPUT (from source manager, threaded down).
- R3-SV thread all of the above up to iec_drive top ports; add `physical_mode` input -> drive
  c1581_drv fdc1772.phys_mode (replace the tied 1'b0); gate sd_rd/sd_wr off in physical mode
  (iec_drive :108-109); force 1581 engine active (iec_drive :168/:116).
- R3-VHDL (main.vhd): instantiate physical_1581_controller + physical_1581_rdfifo on c64_clk_sd_i +
  new c64_rst_sd_i(=qnice_rst_i); connect controller ABI <-> iec_drive phys_* ports (rdfifo between
  controller byte_wr/data and fdc1772 phys_byte read side); route f_* pins; gate sd_*; add phys_1581_en_i.
  Then mega65.vhd (f_* ports, C_MENU_INTERNAL_1581=3+decode, pass through), top_mega65-r{3,4,5,6}
  (route f_* pins, drop static '1' for driven outputs, keep wgate/wdata/selectb/motorb '1',
  G_PHYS1581_CAPABLE=true all four). Verify: iverilog compile SV chain; GHDL syntax-check new VHDL;
  full elaboration + synth = user (Vivado, mixed-language).

- 2026-07-12: **R3-SV DONE & verified.** iec_drive/c1581_multi/c1581_drv thread the 33-signal phys_*
  bundle + physical_mode (drive-0). iec_drive top ports listed in the map above. Engine-select: 1541
  held reset in phys mode (iec_drive:175), 1581 forced active (:230); sd_rd/sd_wr gated off (:165-166).
  Per-file iverilog parse clean; c1581_drv->fdc1772 junction elaborates fully clean (all 33 ports match);
  c1581_multi/iec_drive full-elab blocked only by PRE-EXISTING upstream N/NDR-after-portlist strictness
  (Vivado-tolerated, not our change). Image path (physical_mode=0) byte-identical.
- 2026-07-12: **R4 DONE & menu_test.py ALL MODES PASS** (verify/run/ghdl/mutate 10/10). config.vhd:
  "Use internal 1581" item at flat 3, OPTM_G_INT1581=31, OPTM_SIZE 160, OPTM_DY 28, CORE_VERSION
  WIP-V6-A18X1. mega65.vhd: C_MENU_INTERNAL_1581=3 + all 57 C_MENU_* >=3 shifted +1 (incl 2 subtype
  ranges). osm_const.asm regenerated (build artifact). menu_test.py fixtures updated. Menu ROM rebuilt
  (27473/28672 words). 160-byte config at M2M/tools/c64mega65-WIP-V6-A18X1. QNICE toolchain rebuilt (macOS).
  Cleaned stray root ghdl executables. Still TODO (R4 tail): m2m-rom idle-gate switch callback (ignore
  Image<->Internal toggle while drive access running) + tests/README/FAQ/VERSIONS doc updates.
- 2026-07-12: R3-VHDL (main.vhd controller/rdfifo + f_* pins + mega65 + tops) delegated + ghdl -s. IN FLIGHT.
- 2026-07-12: **Upstream-drift check DONE (user-requested).** MEGA65 `development` HEAD == our pin
  a9158930 (2026-07-05); all 7 adapted helper files byte-identical (diff+hash). No drift, no decision
  needed. Re-run mega65-upstream-drift workflow if upstream advances later.

- 2026-07-12: **R3-VHDL DONE & verified -> CORE IS BUILDABLE.** main.vhd (13 new ports; controller +
  rdfifo instantiated on c64_clk_sd_i/c64_rst_sd_i; 33 p1581_* ABI signals; iec_drive phys_* connected).
  mega65.vhd (11 f_* ports; phys_1581_en <= main_osm_control_i(C_MENU_INTERNAL_1581); i_main wired).
  top_mega65-r{3,4,5,6} (11 f_* routed into CORE; 6 driven outputs freed from tie-off; wgate/wdata/
  selectb/motorb kept '1'). ALL 10 physical_1581/*.vhd registered in every CORE-R{3,4,5,6}.xpr (VHDL2008
  SFType) + .tcl (read_vhdl -vhdl2008). VERIFIED: main<->iec_drive phys ports = PERFECT name match (diff
  clean); top->mega65->main all 13/11 ports connected; rdfifo rd_clk=clk_main_i, rd_rst=not reset_core_n
  (avoids vdrives-mount wedge in physical mode). ghdl -s clean; controller/rdfifo instantiations
  bind-checked. Image mode (physical_mode=0) untouched. G_CAPABLE=true all boards; runtime OSM gate.
  --> A Vivado build of R3/R4/R5/R6 should now synthesize and the internal drive should READ a real 1581
  disk (dir/load). Remaining = polish: R5 diag (user debug tool), R4-tail idle-gate, docs.
- 2026-07-12: **R5 DONE & verified.** C_DEV_C64_PHYS1581=0x0108 read-only diag device (physical_1581_diag.vhd,
  40-word map: signature 0x1581, live pins/state, last result+CHRN+CRC, index period/width, gap last/min/max,
  10x 32-bit saturating counters). Controller+decoder got PURELY ADDITIVE diag output taps (FSM untouched);
  controller closed-loop test RE-RUN -> still PASS (no regression). diag tb PASS. Wired main(new ports
  phys_diag_ce_i/addr_i/data_o)->mega65 (C_DEV decode). Registered in all 4 .xpr/.tcl. doc/1581_dd_debug_device.md
  written (map + QNICE monitor read procedure). ghdl -s clean; bind harness clean.
- 2026-07-12: **FULL GHDL SUITE RE-RUN GREEN** (crc/decoder/inputs/rdfifo/diag all rc=0; controller+mech
  confirmed by R5 agent). R1-R5 coherent, no regressions. **Core buildable + diag-equipped.**
- 2026-07-12: **Docs DONE** (VERSIONS/ROADMAP/README/FAQ Q23/tests-README append/doc-models) — honest
  read-only/experimental framing; Marked-2 + append-only + no-wrap rules followed.
- 2026-07-12: **Idle-gate DONE** (m2m-rom.asm OSM_SEL_PRE, +57 lines; reverts INT1581 toggle via
  M2M$FORCE_MENU when diag 0x0108 word 0x04 & mask 0xFC08 shows physical drive busy). Shell ROM builds
  clean (27506/28672). ONE-DIRECTIONAL: gates Internal->Image while physical busy; Image->Internal is
  NOT gated (no QNICE-visible EMULATED-drive-busy signal without new RTL). Read-only => low risk.
  MAINTAINER DECISIONS: (1) **SYMMETRIC GATE = YES / REQUIRED (user decision 2026-07-12).** The IMAGE
  (simulated D64/D81) drive CAN WRITE (SD write-back), so switching Image->Internal while it is busy or
  has unsaved data must ALSO be blocked. Current gate only blocks Internal->Image. TODO: expose the
  emulated-drive busy (c1581_drv fdc_busy + vdrives cache_dirty) to QNICE (2FF-sync into the diag domain;
  add a spare bit to diag 0x0108 word 0x04 or a new word), then extend m2m-rom OSM_SEL_PRE to also block
  the Image->Internal direction on that bit. See HANDOVER.md sec 8.1. (2) busy includes motor spin-down
  tail = accepted; (3) silent revert = accepted.

- 2026-07-12 (session 2): **TIMING FIX APPLIED.** CORE/CORE.xdc now cuts qnice_clk<->main_clk in
  both directions (clock-to-clock set_false_path, same idiom as common.xdc qnice->hdmi; cannot
  exempt same-clock paths, so the fdc1772 busy hazard is unaffected). CORE-R{3,4,5,6}.tcl read_xdc
  reordered to MEGA65-Rx -> common -> CORE (CORE.xdc references qnice_clk, created in common.xdc;
  the .xpr fileset already had that order). Verify after the next impl run: WNS >= 0 + report_cdc.
- 2026-07-12 (session 2): **NO-D81 BUG SET FIXED (user report: enabling "Use internal 1581"
  without a mounted D81 left the drive dead; also failed WITH a mounted D81).** Root causes, all
  fixed: (1) main.vhd:~1673 held drive 0 in reset while unmounted -> exception when phys_1581_en_i
  is on; (2) c1581_drv.sv CIA PA7 /DSKCHG was the image-mode disk_chng_n, which in phys mode can
  NEVER clear (floppy_step only pulses in image mode) -> PA7 now muxed to ~synced(phys_change)
  (controller sticky latch, cleared by a real step with media present), PB6 /WPRT muxed to
  ~synced(phys_wprot); (3) fdc1772.v Type-I commands were rejected with RNF while media not ready
  -> DEADLOCK (media-ready needs the change latch cleared, only a step clears it, steps are
  Type-I; the real WD1772 has no READY input) -> Type-I now runs unconditionally in phys mode;
  (4) controller change_latched now re-arms while DISABLED too (not only on rst) so every
  image->internal switch presents as a disk change (no silent media swap; internal->image is
  covered by a new phys_mode-edge clear of disk_chng_n in c1581_drv.sv); (5) controller
  head_settled now initializes '1' (at rest = settled) -- the old '0' could wedge a zero-step
  Restore-with-Verify forever (only a step ever set it).
- 2026-07-12 (session 2): **SYMMETRIC IDLE-GATE DONE (HANDOVER 8.1).** main.vhd: img_drive_busy =
  c64_drive_led or prevent_reset, 2FF-synced (async_reg) into c64_clk_sd_i; physical_1581_diag.vhd:
  new word RM_IMG_DRIVE=0x28 bit0, map version 0x02, capability 0x0F; m2m-rom.asm _OSM_PRE_1581
  now checks BOTH words (phys busy 0x04&0xFC08, image busy 0x28&0x0001) and reverts via
  M2M$FORCE_MENU -> both switch directions gated with one code path (each side reads idle while
  the other is the active source). Shell ROM rebuilt: 27515/28672 words. Diag tb extended
  (version word + IMG_DRIVE) and PASSES (39 checks). doc/1581_dd_debug_device.md updated (41 words).
- 2026-07-12 (session 2): verification: ghdl analyze of all physical_1581 units clean;
  DIFFERENTIAL ghdl analyze of main.vhd vs HEAD -> identical error sets (zero new diagnostics) and
  with physical_1581 units seeded, zero errors mentioning the new instantiations; iverilog
  c1581_drv->fdc1772 junction elaborates with 0 errors (VHDL submodules stubbed); crc/decoder/
  inputs/rdfifo/mech/diag tbs all rc=0. Controller closed-loop tb is LONG (>10 min) -- re-run
  in background; adversarial multi-agent review of all diffs in flight.

- 2026-07-12 (session 2): **ADVERSARIAL REVIEW ROUND (43-agent workflow: 7 dimension finders,
  3 independent refuters per finding; 12 raw -> 8 confirmed -> ALL 8 FIXED):**
  (1) CRITICAL rdfifo one-sided reset (rd side on reset_core_n vs wr side on qnice rst ->
  permanent Gray-pointer desync after any core reset mid-read -> CRC-clean shifted sectors).
  Fix: rd side now resets from the SAME event (c64_rst_sd_i 2FF-synced into clk_main_i,
  p1581_fiforst_s); core resets no longer reset either side. (2) MAJOR residual FIFO bytes
  after cancel/disk-change/core-reset aborts shifted every later sector. Fix: fdc1772 now
  pop-and-discards whenever phys_mode and no op is delivering (drain can never eat live data:
  controller pushes only inside an op). (3) MAJOR fdc1772 popped the next FIFO byte at the
  START of the CPU data-register access, but the T65 latches at the CLOSING enable tick ->
  byte k+1 delivered whenever a byte was already buffered (DETERMINISTIC +1 shift for the
  6-byte Read Address reply; proven: with the old code and a realistic 16-clkcpu cpu_read the
  iverilog tb fails every byte shifted-by-one; with the fix it passes byte-exact). Fix:
  phys_drq_wait now clears at END of access (cpu_data_access_end); tb_fdc1772_physical.sv
  cpu_read now models the real multi-clkcpu cycle. (4) MAJOR unbounded phys RESTORE (broken
  TR00/absent mechanism -> busy stuck forever). Fix: real-WD1772 255-step bound -> Seek
  Error (RNF) + INTRQ (phys_step_tally). (5) MAJOR multi-signal CDC skew on the rd-done
  handshake could latch stale flags (worst case rnf=0 on a 0-byte result -> finalize never
  fires -> WD busy forever). Fix: consume done via a 2-clkcpu-delayed copy
  (phys_rd_done_c_d2) so all independently-synced flags are stable. (6) MINOR
  img_drive_busy included the LED in phys mode (1581 DOS blink -> spurious Internal->Image
  revert). Fix: LED masked with not phys_1581_en_i (prevent_reset kept). (7) MINOR stale
  settle timer could re-assert head_settled during a new step (18ms guard skipped). Fix:
  settle_cnt cleared at step acceptance. (8) MINOR RD_STREAM had no watchdog (decoder stall
  mid-data-field -> FSM parked forever). Fix: wd_cnt keeps counting in RD_STREAM ->
  RES_DATA_CRC_ERROR with crc=1 AND rnf=1 (rnf releases the WD finalize). 4 other findings
  refuted 0/3 (asm check-then-act race, xdc insufficiency, busy-cone CDC, byte_ovf unused).
  RE-VERIFIED after fixes: diag tb PASS, differential main.vhd identical, junction elab 0
  errors, fdc tb PASS byte-exact with realistic CPU timing, Shell ROM 27515/28672;
  closed-loop controller tb re-run in background (first run after the no-D81 fixes PASSED).

- 2026-07-13 (session 2, hardware bring-up round 1): **R3 build CLOSED TIMING (WNS +0.366 /
  WHS +0.050, all constraints met)** -- the CORE.xdc clock-pair cut worked; the framework
  half-cycle path recovered as predicted. First on-hardware test (maintainer): error channel
  returns 73 (CPU/IEC alive), but LOAD"$",8 fails with FILE NOT FOUND after motor sounds and
  WITHOUT the MEGA65 drive LED ever lighting => the 1581 DOS never issued a WD command; it
  gives up on CIA-visible state before any job. ROOT CAUSE (high confidence): media_ready
  (-> CIA PA1 /RDY) was gated on change_latched='0'; the latch only clears via a STEP, the
  mechanism DSKCHG latch likewise (mega65-core: "You can only clear the DISKCHANGE and
  re-assert RDY by stepping"); the head parks at track 0 so even a Restore steps zero times;
  and the stock 1581 ROM waits for RDY BEFORE running the job whose seeks would step =>
  deadlock, DOS timeout, no WD traffic (matches the dark LED). On a real 1581 the FB-354
  RDY line is independent of DSKCHG. FIX: media_ready now models the real RDY (motor >=505ms
  + >=2 index edges + plausible period), the change latch drives ONLY PA7 + the read-engine
  abort + diag; disk removal is detected by index-pulse loss (new idx_gap_cnt staleness
  reset, threshold 2x G_PERIOD_MAX_CYC). Companion fdc1772 fix: fd_index_eff (real index in
  phys mode) now feeds the WD index housekeeping (spin-up countdown -> status bit 5,
  Force-Interrupt-on-index, motor idle timeout) which was dead in phys mode (fd_index never
  pulses without an image). Pin polarities re-verified against mega65-core: stepdir '1' =
  toward track 0 (their $10 "step out" case), motor/select active-low, dskchg/index/track0
  active-low -- all match our RTL. REMAINING SUSPECT if the fix is not enough: DSKCHG pin
  polarity/wiring (change_c stuck 1 would still abort every read with RES_DISK_CHANGED,
  0x0A) -- discriminate on hardware via diag LIVE_IN bit 9 across an eject/insert, and the
  index health via CNT_IDX_QUAL/IDX_PERIOD. Re-verified: diag tb PASS, fdc tb PASS,
  controller tb re-run in background.

- 2026-07-13 (session 2, hardware bring-up round 2): retest with the ready-fix bitstream STILL
  fails LOAD"$",8 (FILE NOT FOUND, fast), but the diag dump after the failure shows the FULL
  HARDWARE STACK WORKING: index 199.65 ms (perfect 300 RPM, 3.05 ms pulse, 72 qualified revs),
  ~10.9 decoded IDs/rev (a genuine 10-sector 1581-format disk), change latch CLEARED by DOS
  steps, DSKCHG polarity PROVEN by the eject test (raw pin low + change_c=1 when ejected),
  6/6 read ops RES_OK (zero RNF, zero CRC err), last op found C=3 R=1 H=0 N=2. ANOMALIES:
  only 10 steps total since power-on (the DOS NEVER seeks toward cylinder 39 where the
  directory lives), head_valid=0 (no completed outward step ever ended on track 0 => the DOS
  apparently never restores; 1541-style, it likely locates itself via READ ADDRESS and steps
  relatively), and the FNF answer arrives while mechanics still run (answered from a stale
  DOS state). => The remaining divergence is in the DOS<->WD dialogue, not in the hardware
  path. ACTIONS: (1) added a READ ADDRESS test to tb_fdc1772_physical.sv (6 bytes DRQ-paced,
  byte-exact, sector-register update) -- PASSES, so the one uncovered delivery path is clean;
  (2) built a WD-DIALOGUE TRACE RING into the diag device (32 entries x 32 bit, offsets
  0x40-0x7F + TRC_CNT at 0x29, map version 0x03/cap 0x1F): records every STEP (dir + head
  estimate), READ REQUEST (op/track/sector/side) and RESULT (code/flags/C/R) -- the next
  failed LOAD hands us the exact command sequence the 1581 ROM issues. Controller got purely
  additive rd_req trace taps. Diag tb extended (50 checks PASS); main.vhd bind-check clean;
  controller tb re-run green. OPEN QUESTION to maintainer: what disk is being tested and how
  was it written (real-1581-formatted? MEGA65-written? PC-written D81 copy?).

- 2026-07-13 (session 2, bring-up round 2b): **SIDE INVERSION FOUND AND FIXED — the probable
  root cause of the round-2 failure.** Trigger: maintainer disclosed the test disk was
  formatted + written BY THE MEGA65 itself (C65 DOS BACKUP of a mounted D81 via the F011 real
  floppy path). Verified in mega65-core sdcardio.vhdl: (a) $D080 handler drives
  `f_side1 <= not side_bit`, so F011 SIDE 0 = pin HIGH = head 0; (b) the D81 offset math
  (`physical_sector = sector-1` for side 0, `sector+9` for side 1; offset = track*20 +
  physical_sector) proves F011 side 0 = the FIRST half of each cylinder (D81 logical sectors
  0-19). Our chain resolved to f_side1_o = PA0 (double negation: side=pa_out[0],
  floppy_side=~side, f_side1_o = not side_s), i.e. logical side 0 (PA0=0) selected pin LOW =
  head 1 — INVERTED vs the disk. Since the controller matches C+R and IGNORES H, every read
  succeeded CRC-clean but returned the OTHER side\'s data — matching the round-2 dump exactly
  (6/6 RES_OK, garbage content for the DOS, low-cylinder wandering, fast FILE NOT FOUND, and
  H=0 found while the DOS had its side 1 selected). FIX: physical_1581_controller.vhd
  `f_side1_o <= side_s` (inversion removed; PA0=0 -> pin HIGH -> head 0), cia_side_i port
  comment corrected (it receives ~PA0: \'1\' = logical side 0), closed-loop tb now drives
  cia_side/rd_side = \'1\' (the value fdc1772 really sends for logical side 0 — the old tb
  masked the bug by driving \'0\'). The mech model was already PC-convention (pin \'1\' =
  side 0) and needed no change. Closed-loop tb re-run in background (expect PASS).
  NOTE the interoperability argument: C65/F011 and the real 1581 read each other\'s disks,
  so pin-HIGH-for-logical-side-0 is also the real-1581 convention; the round-2 dump\'s
  successful reads with swapped sides were only possible because H is ignored.

- 2026-07-13 (session 2, bring-up round 3): **WD DATA-REGISTER READBACK BUG FOUND VIA ROM
  DISASSEMBLY + TRACE RING, PROVEN IN SIM, FIXED.** The round-3 trace (side fix + trace ring
  bitstream) showed: 5 step wiggle pairs, then LOAD"$" = SIX successful READ ADDRESS ops at
  the resting cylinder (C=3, R ascending 3..8), WD TRACK REGISTER = 0xFF on every request, no
  seek ever, instant FILE NOT FOUND. Disassembled the actual 318045-02 ROM
  (c1581_rom.mif.hex): the DOS power-up controller init at $C343 writes $FF..$01 to the WD
  track/sector/data registers and verifies EVERY readback ($C349-$C365); any mismatch ->
  error $0D, init aborted (leaving track=$FF -- the traces fingerprint). fdc1772.v mirrored
  writes into the readback register as `data_out <= data_in` while `data_in <= cpu_din`
  happens in the same clock edge -> DATA reads back ONE WRITE BEHIND. Reproduced in a new
  sim bench (scratchpad tb_regtest.sv replicating the ROM test: "wrote FF got xx, wrote FE
  got FF"). FIX: `data_out <= cpu_din` (real WD1772: one data register, readback returns the
  written value). Re-verified: register test PASSES, tb_fdc1772_physical PASSES (incl. Read
  Address + byte-exact sector), junction elab 0 errors. WHY IMAGE D81 SEEMED FINE: image-mode
  Read Address returns the virtual track that follows the WD registers, so the ROM position
  checks cannot disagree there even with init degraded; only the real mechanism exposes it.
  Also disassembled for reference: job read entry $C900 (RA, then found-C vs wanted-track
  check -> error path), seek stage $CE78 ($88 wanted vs $27 believed -> WD SEEK), sector spin
  loop $CAE4 (RA until wanted R passes, budget 60), ready check $CDBC (PA1 low, 30 stable
  samples). RECOMMENDED CONTROL TEST on the current bitstream: image-mode D81 LOAD"$",8
  (no reflash needed) to see whether the init failure degraded image mode too.

- 2026-07-13 (session 2, bring-up round 4): **RDY LATENCY — the register-test fix unmasked the
  next gate.** Round-4 trace (data-register fix in): 12 events = ONLY step wiggles, ZERO read
  ops (previously 6 read-addresses!), change latch cleared, disk spinning perfectly, fast
  FILE NOT FOUND after ~1 s of motor. ROM analysis: with init now PASSING its self test, the
  DOS runs a clean job flow: spin-up allowance of 80 dispatcher ticks (LDA #$50 -> $01D9 at
  $B095, ~0.7 s), ONE disk-change wiggle, then the INSTANT 30-sample PA1 check at $CDBC (no
  waiting loop!) -> error 3. Our media_ready needed an at-speed period measurement
  (~0.5-0.7 s after motor-on) plus the 505 ms floor -> lost the deadline. (Pre-fix, the
  broken init caused many more retry rounds, which is the only reason ready was eventually
  seen and the RAs ran.) FIX: media_ready = motor + >=2 index edges (rotation detection,
  like the real FB-354; ~200-450 ms). The at-speed protection is redundant: an off-speed
  disk does not decode -> RNF -> the DOS read-retry (budget 60) absorbs it; the eject
  detection (index staleness) and the change-latch read-abort stay. period_ok remains for
  diag. Closed-loop tb re-run in background. NEXT: rebuild + retest; if CNT_READOP is still
  0 afterwards, plan C = pre-spin qualification (assert ready during the wiggle phase).

- 2026-07-13 (session 2, bring-up round 5): **ROOT CAUSE PROVEN AGAINST THE REAL ROM AND
  FIXED: busy dropped at PRESENTATION instead of CONSUMPTION of the last streamed byte.**
  Round-5 hardware trace (rdy-fix bitstream): RDY gate PASSED (RAs back, init clean:
  track reg $01), six OK read-addresses (C=3, R ascending incl. the R=11 MEGA65
  track-info-block ID), still no seek -> FNF. Built a ROM-in-the-loop emulator
  (doc/dev-fdd/rom_emu/: python 6502 + device models mirroring our RTL) and BOOTED THE
  GENUINE 318045-02 ROM: reproduced ERROR $09 exactly (six RAs, no seek) with
  presentation-busy semantics; with consumption-busy semantics the same ROM restores,
  read-addresses, SEEKS to cyl 39 and reads the directory. Mechanism: the ROM transfer
  loops poll BUSY FIRST, DRQ second ($CD17: AND #$03/LSR/BCC done) -> busy=0 with the last
  byte still presented makes it exit one byte early; the ROM then SOFTWARE-CRC-checks the
  6-byte Read Address reply ($DA63, CCITT preset $B230 over C,H,R,N,CRC,CRC, residue must
  be 0) -> truncated reply -> error $09 per attempt -> FILE NOT FOUND. FIX (fdc1772.v
  finalize): busy holds until the drive CPU consumed the final byte
  (phys_bytes >= expected AND !phys_drq_wait). Same fix covers the last byte of sector
  reads (same ROM polling idiom). VERIFIED: tb_fdc1772_physical extended with the
  ROM-faithful busy-first drain -- catches the old RTL (loses byte 6, revert-proof) and
  passes the fixed RTL; register test still clean; junction elab 0 errors; ROM emulator
  boot login SUCCEEDS with the fix. Controller VHDL untouched this round. NEXT: rebuild +
  hardware retest -- with self-test, RDY, side mapping and byte pipeline all proven, the
  login has no remaining unverified gate.

- 2026-07-13 (session 2, bring-up round 6): **PHYSICAL STACK FULLY WORKING ON HARDWARE; the
  round-2b SIDE FIX was WRONG and is REVERTED (empirical proof from the medium).** Round-6
  trace (busy-consumption fix in): the ROM logs in end to end -- restore, 39-cyl seek (steps
  traced), verify RAs, then the 1581 track-cache fill: READ SECTOR x48, sectors cycling in
  physical order, C=39, ZERO RNF, ZERO CRC errors... and still FILE NOT FOUND, because the
  DOS rejects the CONTENT: CHRN_HN shows found H=1. Cross-round evidence on the SAME disk:
  original mapping (pin '0', rounds 1-2) read H=0 IDs; the round-2b mapping (pin '1',
  rounds 5-6) reads H=1 IDs. So the D81 first half (header/BAM/dir, H=0) lives on the
  f_side1='0' surface -- the DOS logical side 0 (PA0=0) must drive the pin LOW, exactly the
  ORIGINAL f_side1_o <= not side_s (= PA0, the real 1581 wiring). The round-2b re-derivation
  from mega65-core sdcardio was invalid: the C65 DOS sets the F011 side REGISTER and the
  side PIN bit independently during format, so the register model does not pin the pairing;
  the on-disk H bytes do. Under the wrong mapping the DOS track-cached 10 CRC-clean ZERO
  sectors (the empty second half) -> invalid header -> FNF. REVERTED controller mapping
  (comment now records the empirical truth + a warning against re-deriving from mega65-core);
  mech model + both tbs aligned (pin '0' = side 0); mech tb PASS; closed-loop tb re-running.
  With every layer now hardware-proven (self-test, RDY, steps/seek, RA pipeline, sector
  delivery) plus the correct surface, the login should complete on the next build.

- 2026-07-13 (session 2, bring-up round 7): **MILESTONE: LOAD"$",8 WORKS RELIABLY on hardware
  (side-reverted bitstream). Remaining defect: intermittent SILENT BYTE LOSS in file loads —
  diagnosed as READ-FIFO OVERFLOW, fixed two ways.** Symptoms: directory names with
  neighboring bytes pulled in ("SHADESKD" = name+shift = DROPPED bytes, not flipped),
  programs that load without error but do not run, occasional DOS hangs; the hang-time trace
  shows a functionally CLEAN WD dialogue in which the DOS wanders to absurd cylinders (~47)
  following corrupted track/sector chain links, re-caches the directory repeatedly, then goes
  silent. Mechanism: the controller streams sector bytes at disk pace (32 us/byte) into the
  32-deep rdfifo; when the drive CPU is stolen mid-sector (IEC ATN service / job IRQ — exactly
  what real file loads do between logical blocks, and what no prompt-draining testbench ever
  did), the FIFO fills and further controller writes were DROPPED SILENTLY (byte_ovf_i was
  wired but unread — the early review flagged it and the refuters dismissed it because "a
  real WD also loses data"; but the real WD sets LOST DATA and the DOS re-reads. Silence was
  the bug.) FIX 1: rdfifo depth 32 -> 512 (G_AW 9, one full physical sector — reads can no
  longer overflow even with a stalled CPU). FIX 2: controller latches write-while-full
  (ovf_l) per op and completes with RES_DATA_CRC_ERROR + crc + rnf (DOS re-reads; rnf
  releases the WD finalize) — a drop can never be silent again. New regression test
  tb_physical_1581_ovf.vhd (4-deep FIFO, consumer never drains): PASSES (error reported).
  main.vhd bind-check clean; closed-loop tb re-run in background. Diag notes from the hang
  dump: CNT_CHANGE=2 (one mid-session disk-change latch event — watch), head_valid never
  anchors (cosmetic only, nothing gates on it — possible TR00-assert-vs-SI_REC latency,
  investigate at leisure). NEXT: rebuild; then LOAD"$" + program loads incl. RUN.

- 2026-07-13 (session 2, bring-up round 8): **READ MILESTONE REACHED AND GROUND-TRUTH-VERIFIED.**
  On the overflow-fixed bitstream: LOAD"$",8 reliable; LOAD"SHADES",8,1 loads fully and RUNS
  (SID music plays = end-to-end byte-exact delivery proven). The mother D81 (~/Downloads/
  C64.D81, "MEGA65 C64 SIDE", 45 files, only 67 blocks free) confirms every observation:
  SHADES = 35 blocks at logical tracks 62-63 (cyls 61-62) with 20 of 35 blocks ON SIDE 1 --
  so the traced seek 39->62 and track-62/63 caching were a HEALTHY load (the perceived
  "stall" = normal stock-serial speed for a far-end file), and SIDE-1 READS ARE HARDWARE-
  PROVEN (last open coverage item). The earlier "wandering to cyl 47" = SHADOW SWITCHER
  territory (cyls 45-49) -- legitimate. KNOWN REMAINING IMPERFECTIONS (non-blocking):
  (1) intermittent ID-miss: a requested sector occasionally not found within the 5-index-edge
  search budget (caught live: trk62 s1 RNF after reading fine before/after; ~3 per 450 revs;
  self-heals via the DOS retry at ~2 s cost) -- suspected digital-decoder re-lock margin near
  the format splice; tune later with GAP/CNT_GAPERR statistics. (2) head_valid never anchors
  reliably (diagnostic only; fix queued: anchor on the TR00 LEVEL continuously). (3) Instant
  FILE NOT FOUND when loading while a program with custom IRQ (SID player) runs = C64-side
  IEC timing interference, NOT this core (trace shows zero drive activity for that command);
  same behavior expected in image mode. NEXT session: bundle (2) + investigate (1), then the
  write/format milestone (HANDOVER 8.3).

- 2026-07-13 (session 2, bring-up round 9): **HARD WEDGE AFTER SOFT RESET DIAGNOSED AND
  CLOSED (WD busy stuck forever).** Reproduced by the maintainer: C64 soft reset then
  LOAD"$",8 loads forever; two QNICE dumps 3+ min apart prove it: TRC_CNT FROZEN at 0x242
  while CNT_IDX climbed ~1000 revs (motor spinning under an idle controller) -- the 1581 DOS
  wedged in its wait-not-busy loop after a SUCCESSFUL Read Address. Mechanism: the
  busy-until-consumed finalize (round 5 fix) has a RACE when the FIFO holds one byte more
  than the operation expects (residue): the pop of the surplus byte and the finalize
  evaluation race at clock-phase granularity; losing it leaves the last byte presented-but-
  never-consumed -> phys_drq_wait stuck -> busy stuck -> DOS spins forever with the motor on
  (the bench originally missed it because it won the race; the revert-proof confirmed the
  non-determinism). Residue can slip in around reset/abort windows; a drain pop colliding
  with the phys_rd_start counter reset could also skew the count (same wedge). FIXES
  (fdc1772.v): (1) delivery pops CAPPED at phys_expected per op -- a surplus byte is never
  presented, the op terminates (with a shifted reply the DOS rejects via its own CRC and
  retries), and the between-ops drain eats the leftover -> at most ONE errored op, then
  clean; (2) drain pops no longer counted (phys_deliver_pop) -- no count skew; (3) 0.5 s
  finalize watchdog (phys_done_age) force-completes with RNF as the last-resort backstop.
  VERIFIED: new stray-byte wedge regression in tb_fdc1772_physical.sv (stray-poisoned RA
  must terminate shifted, follow-up RA must be byte-exact) PASSES; full bench + register
  test + junction elab green. Needs REBUILD.

- 2026-07-13 (session 3, round 10): **INVESTIGATION ONLY (maintainer request, no code changes): round-9
  bitstream fails intermittently — six-agent audit + hardware-dump forensics.** Evidence: LOAD"\$" ok then
  LOAD"SHADES" FNF (dump 1); retry: seek 39->62, 2 RA ok, RS t62 s5+s6 ok, then DOS silent forever, LED off
  (act_led includes fdc_busy, so the WD was IDLE), motor timed out, two dumps bit-identical; after a C64
  soft reset the larger C64ANABALT loads clean. Findings (full agent reports in the session scratchpad,
  `report_*.md`; D81 tooling `d81_analyze.py`; genuine-ROM experiments `dos_audit/job_test.py` T1-T5):
  (1) **GROUND TRUTH (proven from ~/Downloads/C64.D81):** SHADES starts at 62/8 = cyl 61 side 0 R5; the
  observed reads (cyl 62 side 0 s5/s6 = logical 63/8..11) are DREAMCARS 64 mid-chain blocks; no file starts
  there. The DOS was steered by a corrupted dir-entry start-track byte `0x3E -> 0x3F` (single LSB bit) with
  the name and sector byte intact. SHADES entry = dir sector 40/6 slot 2 = cyl 39 side 0 R4 half 0 byte 67.
  (2) **ROM-PROVEN `\$CD5A` HOLE (genuine 318045-02 ROM in the rom_emu):** a WD status with CRC(b3) and
  RNF(b4) BOTH set maps to job result 00 = SUCCESS (`\$CD3F` computes X=(status>>3) AND 0x0B, indexes
  `\$CD5A` = 00 05 02 00 ...; X=3 hits the hole). The round-7 ovf completion, the round-8 RD_STREAM
  watchdog, and the ID-CRC search-expiry ALL emit crc=1 AND rnf=1 on the false premise "the DOS re-reads":
  the ROM instead ACCEPTS the bad sector and (emu test T5) can terminate a track-cache fill early while
  marking the half-stale cache VALID. FIX NEXT ROUND: never emit crc and rnf together; CRC-only gives job
  error 5 (DOS 23, retried) as intended. Did not fire tonight (CNT_CRCERR=0) — it is a landmine, not the cause.
  (3) **DOS fingerprints (disassembly-proven), for reading future traces:** busy-wedge hangs keep the MOTOR
  ON (the unbounded waits `\$CBEC`/`\$CBFA` run in the IRQ/BRK job context with I set, which blocks the
  Timer-B motor timeout — the round-9 signature). Tonight's LED-off + motor-timeout + no-blink end state is
  reachable only via the all-channels-free idle path `\$B128`: the DOS believed the LOAD completed. Best
  reconstruction: corrupt entry -> wrong seek -> fill ended early-as-success -> cache mostly stale but
  marked valid -> chain walk served from cache (zero WD commands) -> stale link track byte 0 -> premature
  clean EOF -> the C64 loaded garbage at a garbage address (",8,1") and died (explains Run/Stop+Restore
  being dead and the reset button being needed).
  (4) **Controller EXONERATED:** push contract exact (512/6/0 bytes; CRC bytes never pushed; verify pushes
  none); every residue-capable abort completes loudly (rnf/crc/cancel/change flags + counters); tonight's
  counters (0 cancel, 0 crcerr, 3 zero-push search-expiry RNFs) rule out ALL controller residue sources.
  FIFO Gray pointers stay coherent across a core reset (both reset ports on the QNICE reset only);
  CNT_CHANGE=1 after the soft reset is the designed disable re-arm.
  (5) **fdc-side latent defects found (fix next round):** (a) DRQ is never cleared at command start (the
  real WD1772 clears it): an op ending with a presented-but-unconsumed byte (watchdog fire; RNF finalize
  bypasses drq_wait via the phys_rnf_l term) leaves a stale DRQ, the next read takes a phantom first byte,
  and the ROM (which exits on busy, not a count) stores 513 bytes — buffer shifted AND one byte overrun
  into adjacent drive RAM, silently; (b) unilateral not-ready completions (Type-II after a 6 ms ready dip,
  fdc1772.v ~833-841; Type-III instantly, ~971-974) end the WD command WITHOUT cancelling the controller;
  a retry rd_req toggled while the controller is busy is LOST (the controller samples req only in RD_IDLE,
  no pending latch) and the OLD op done/bytes pair with the NEW command — wrong-sector delivery with clean
  status, invisible to trace and counters; (c) the 0.5 s finalize watchdog fires with ZERO observability
  (no diag counter/trace: all taps are controller-side), and a fire during a multi-sector read (m=1) takes
  the REISSUE branch (checks the latched rnf/crc flags, both 0) -> busy stuck forever (latent; stock DOS
  never sets m); (d) a QNICE-only reset mid-op idles the controller without a done toggle while the WD
  stays busy forever (the watchdog only arms after done latches). The micro-mechanism of the observed
  single-bit `0x3E->0x3F` flip is NOT yet pinned (candidates: (a) overrun, (b), a silent watchdog fire);
  it needs the new observability below.
  (6) **DEFENSE-INVENTORY VERDICT (the maintainer's watchdog question):** ~20 mechanisms inventoried; 16
  are class A (faithful models of real, physically-bounded WD1772/FB-354 behavior: 5-index RNF budget,
  43-byte DAM window, 255-step restore bound, 6-rev spin-up, 10-rev motor idle, settle, RDY, DSKCHG latch)
  or class B (textbook CDC/FIFO necessities of our two-clock architecture). Exactly TWO are invariant-
  patches: the round-9 pop cap and the 0.5 s finalize watchdog — the only wall-clock-denominated bound in
  the design; both can mask errors silently. Root cause of the whole complex = the round-5 inversion (busy
  release coupled to drive-CPU CONSUMPTION instead of disk pace); rounds 5 -> 7 -> 9 are one causal patch
  chain. TARGET ARCHITECTURE (do before the write milestone — mandatory there, since flux is unpausable and
  a force-complete watchdog on writes corrupts media): disk-paced delivery reusing the proven image-path
  fd_dclk_en byte pacer fed from the FIFO head; overrun -> overwrite + LOST DATA reported as CRC-only (see
  (2)); busy release = controller done (data_end already trails the last payload byte by the two CRC
  byte-times, i.e. the real chip's tail). This deletes phys_drq_wait, the bytes-vs-expected finalize, the
  pop cap and phys_done_age structurally. Cost is small: the ROM runs its transfer loops with I set (no
  mid-loop CPU steals); the FIFO still absorbs loop-entry latency.
  (7) **Cleanup/observability queue:** RDATA minimum-low-width filter using the defined-but-UNUSED
  C_GAP_GLITCH=120 (GAP_MIN=0x0001 proves 40 ns runts reach the decoder; the s1-after-splice RNFs are the
  PLL-less fixed-window re-lock margin at the index write splice — self-healing but a 2 s hiccup each);
  dead code ready_cnt/G_MOTOR_READY_CYC and period_ok (write-only since the round-4 RDY redesign); diag
  additions: fdc-side event counters (watchdog fires, unilateral completions, cap/drain engagements), FIFO
  occupancy tap, per-op delivered-byte count (+ simple checksum) on the WD side, found-H in RESULT trace
  entries; latch-or-cancel semantics for rd_req while the controller is busy (or op sequence tags on the
  req/done handshake); ASYNC_REG on the fdc iecdrv_sync instances (methodology TIMING-10). HOUSEKEEPING:
  the rom_emu accidentally lives INSIDE the submodule (`CORE/C64_MiSTerMEGA65/rtl/iec_drive/doc/dev-fdd/
  rom_emu/`) — move to `doc/dev-fdd/rom_emu/` before any commit.
  (8) **Vivado logs (19:40 build): CLEAN.** Zero new-code warnings, no latches or trimmed registers, both
  controller FSMs encoded, rdfifo/trace-ring in distributed RAM (0 BRAM), WNS +0.292 on the pre-existing
  QNICE half-cycle path. Nothing in the build explains the failures — this is logic, not synthesis.

- 2026-07-14 (session 3, round 10 IMPLEMENTATION): **DELIVERY V2 IMPLEMENTED, VERIFIED, HARDENED
  (maintainer: "implement it all"; no commits).** The consumption-coupled WD delivery is replaced by
  the real-WD1772-faithful disk-paced model; the round-9 mechanisms are DELETED, not patched.
  AS BUILT: (1) fdc1772.v phys engine — presentation of one FIFO byte per DD byte-time
  (PHYS_PACE_TICKS=252 clk8m ticks ~32 us), never waiting for consumption; an unconsumed byte is
  overwritten with LOUD LOST DATA (status bit 2 + CNT_LOST); completion = tag-matched controller
  done AND FIFO empty AND one-byte-time tail (busy outlives the last DRQ >= 1 byte-time, like real
  silicon; bench-measured ~0.96 byte-time). DELETED: phys_drq_wait, phys_bytes/phys_expected
  counting, the round-9 pop cap and phys_done_age 0.5 s watchdog (zero wall-clock bounds remain in
  the delivery path; every bound is disk-time-denominated). (2) Unilateral not-ready completions
  (Type-II 6 ms / Type-III instant) deleted — the controller is the single completion source
  (RD_WAIT 1.1 s -> RES_NOT_READY, search 5 index edges / 1.3 s -> RNF). (3) Non-Force-Interrupt
  command writes while busy are IGNORED in phys mode (real WD semantics) + counted. (4) Request/done
  handshake carries a 2-bit sequence tag; the controller latches request edges arriving while busy
  (pending latch, cancel clears) — lost-edge/stale-done pairing structurally closed. (5) `\$CD5A`
  fix: RES_DATA_CRC_ERROR and RES_ID_CRC_ERROR completions are now CRC-only (rnf=0) + fdc status
  belt (RNF bit suppressed when CRC set) — proven LOAD-BEARING against the genuine ROM (emu proof:
  CRC-only -> job error 5 -> retry heals; legacy crc+rnf demo still reproduces the silent-success
  hole). (6) DRQ + LOST cleared at command start (real chip semantics). (7) RDATA runt filter in
  mfm_gaps: gaps < C_GAP_GLITCH(120) merge into the successor + runt_o counted; GAP stats are
  post-filter. (8) Dead code removed: ready_cnt/G_MOTOR_READY_CYC, period_ok/G_PERIOD_MIN_CYC
  (G_PERIOD_MAX_CYC stays for the eject bound). (9) Diag map v4 (VERSION 0x043F): 0x2A FIFO_LEVEL,
  0x2B LAST_PRESENT, 0x2C-0x35 CNT_LOST/CNT_DRAIN/CNT_STALEDONE/CNT_BUSYCMD/CNT_RUNT, trace RESULT
  w0 bit 8 = found-H; six fdc dbg signals threaded fdc1772 -> c1581_drv -> c1581_multi -> iec_drive
  -> main.vhd (2FF + async_reg) -> diag; rdfifo grew wr_level_o. (10) ASYNC_REG on iecdrv_sync
  (attribute only). (11) rom_emu MOVED out of the submodule to doc/dev-fdd/rom_emu/ (git rm
  staged submodule-side), updated to mirror v2, new run_proofs.py.
  VERIFIED (all green): 8 GHDL tbs incl. the ~28 min closed-loop controller run (with new
  pending-latch, done-tag and runt tests); iverilog 8-scenario delivery-v2 bench + junction elab 0
  errors; rom_emu ALL PROOFS PASS (`\$C343` self-test, paced directory login byte-exact with zero
  LOST, transfer-loop margin 33/64 cycles); differential ghdl of main.vhd vs HEAD identical.
  ADVERSARIAL REVIEWS (4 lenses): zero critical/major; all 8 round-10 audit defects closed (4 by
  structural deletion); image mode proven byte-identical hunk by hunk.
  ROUND-10b HARDENING (5 review fixes, applied + re-verified + adversarially rechecked CLEAN):
  F1 deferred reissue gated on !cmd_rx (FI-collision phantom op); F2 drain gate drops
  !phys_done_latched (verify-window wedge structurally removed); F3 presentation deferred while the
  drive CPU has an open data-register READ access (~<=0.5 us, bus-bounded — closes mid-read
  overwrite, same-cycle DRQ swallow and false LOST DATA with one mechanism); F4 rd_done_seq_o
  registered at the nine done-toggle sites (tag quasi-static by construction); F5 minimum done
  spacing C_DONE_GAP=8 (min 200 ns, live edges latched as pending). Bench extended (79 checks) with
  a NEGATIVE CONTROL run proving the new tests catch the unfixed RTL; closed-loop tb extended with
  the abort-with-pending spacing test + run-wide tag monitor. Recheck notes became code comments
  (fdc two-tick cmd_rx dependency; controller tag-attribution note).
  ACCEPTED/DOCUMENTED: QNICE-only-reset-mid-op hole (never fires without a core reset in M2M);
  Write Sector / Read+Write Track still WD-side fake-finish (read-only milestone; MUST move onto
  the done handshake at the write milestone); two razor-edge unreachable corners documented in
  comments. Menu/config untouched (config file stays c64mega65-WIP-V6-A18X1, 160 bytes).
  NEXT: maintainer REBUILDS R3 (bitstreams from before round 10 corrupt silently — treat as
  diagnostic-only), hardware-tests LOAD"\$" + SHADES + C64ANABALT + RUN, watches diag v4
  (CNT_LOST/LAST_PRESENT/FIFO_LEVEL discriminate every delivery anomaly in one dump). Then the
  write/format milestone (HANDOVER 8.3) inherits the time-paced discipline.

- 2026-07-14 (session 3, round 11): **FIRST DELIVERY-V2 HARDWARE TEST FROZE — ROOT CAUSE FOUND
  (latent day-one zero-step Type-I busy-visibility bug, exposed by a persistent RNF that the
  round-10 runt filter made more likely) — BOTH FIXED.** Hardware: LOAD"\$" -> eternal "searching",
  motor frozen ON ~2 min (542 revs), LED OFF, WD idle, dumps static. Trace decode (map v4 works;
  GAP_MIN now 126 = filter active): healthy wiggle/RA/steps to cyl 39, RS s3 OK, RA-spin saw R=6,
  RS s7 -> RNF after the full 5-edge search (last ID R=6)... then total silence: no retry command,
  no FI (CNT_CANCEL=0), no error blink. DIAGNOSIS CHAIN: (1) act_led = pa_out(6) OR fdc_busy and
  fdc_busy = busy, so LED OFF proves busy=0 -> the round-10 B2 while-busy ignore is EXONERATED (a
  swallowed write needs busy=1; an accepted write sets busy -> LED on). (2) rom_emu with the genuine
  ROM: dispatcher handles the s7-RNF cleanly (job error 02, busycmd=0) -> the wedge is above the
  dispatcher. (3) Motor frozen ON + LED frozen OFF = housekeeping dead = the CPU loops with I SET
  in dispatcher context, in a loop that never touches the WD. (4) Disassembly: the IP retry
  machinery (`\$94F8`/`\$9564`, budget \$30=2) interposes recovery job `\$C0` after persistent
  errors; its exec at `\$CB0F` does LDA `\$01DA` / JSR `\$CBF4` = write a RE-POSITIONING SEEK to
  the track the DOS already believes -> ZERO steps -> our phys Type-I completed in ~3 clk8m ticks
  (~380 ns busy: seek_state 0->2->3, spin-up gate bypassed by the round-3 phys fix) -> the ROM's
  `\$CBFA` wait-busy-SET poll (3.5 us/iteration) can NEVER see it -> spins forever with I set.
  The real WD1772 microcode keeps busy ~ms even for zero steps; rom_emu never hung because its
  model does max(1,n)*1.5 ms — the exact faithfulness gap. Never seen before because the recovery
  job only runs after PERSISTENT errors: rounds 8/9 misses healed in the budget-2 retries.
  FIX A (fdc1772.v): PHYS_T1_MIN_TICKS = 12000 clk8m (~1.5 ms) minimum Type-I busy in phys mode —
  armed at Type-I acceptance, gates seek_state-3 finish and the verify-branch finalize; FI stays
  immediate; image mode untouched (!phys_mode passthrough).
  WHY THE RNF WAS PERSISTENT (round-10 regression, mine): the runt filter merged on gap<120, so a
  noise edge landing LATE in a real gap (>120 after the previous edge, <120 before the next REAL
  edge) made the NEXT REAL EDGE merge away -> ONE wrong-length gap that can land in a VALID window
  (60+200=260=MED) -> silent decode corruption instead of the loud class-11 re-sync of round 9;
  CNT_GAPERR jumped ~42/rev -> ~204/rev on the same disk (decoder now stays locked through splice
  junk it previously idled past) and s7 became unreadable for 5 straight revs.
  FIX B: C_GAP_GLITCH 120 -> 16 cycles (only true electrical runts merge — the GAP_MIN=0x0001
  evidence class; everything longer is loud again); flux-gen runt vectors retuned to 8-cycle runts.
  VERIFICATION COMPLETE, ALL GREEN: new bench test 11 in tb_fdc1772_physical.sv — (11a) zero-step
  SEEK and (11b) zero-step RESTORE-at-track0, ROM-faithful `\$CBFA` poll cadence (~3.5 us/poll,
  bounded at 200 polls) — busy observed on the FIRST poll and held 1.44 ms in both variants;
  NEGATIVE CONTROL (fix A programmatically reverted in a scratch copy) fails exactly test 11
  ("busy never observed SET after 200 polls") while tests 1-10 still pass = the regression test
  provably catches the hardware freeze. Full bench 1-11 PASS (95 ok / 0 FAIL), junction elab 0
  errors, GHDL analyze clean, decoder tb with the retuned 8-cycle runt vectors PASS (2 runts
  merged, 0 gap errors, fields byte-exact), crc + inputs smoke PASS, and the ~22 min closed-loop
  controller tb PASS (rc=0, media_ready ~398 ms, payload matches, RNF, pending-latch/abort/
  recovery). Image-mode neutrality of fix A proven by inspection (all four hunks phys-gated or
  passthrough). READY FOR HARDWARE: rebuild R3 + retest. NOTE for future dumps: use MD 7000 7035
  (the round-10 words 0x2A-0x35 — FIFO_LEVEL/LAST_PRESENT/CNT_LOST/CNT_DRAIN/CNT_STALEDONE/
  CNT_BUSYCMD/CNT_RUNT — were missing from the 2026-07-14 morning dumps).

- 2026-07-14 (session 3, round 12): **ADAPTIVE MFM GAP QUANTISER — IMPLEMENTED AND FULLY
  SIM-VERIFIED (VHDL-only, no submodule delta).** Motivation, hardware-measured via a 6-test
  protocol on the round-11 bitstream: near cylinders (39-41) 100% reliable (C64ANABALT 4/4 loads,
  zero RNFs, all delivery counters zero; side-1 reads + the found-H trace bit verified live); far
  cylinders (61-62) fail most attempts with ~4 RNFs per load (SHADES stall reproduced with an
  identical fingerprint: recovery runs without freezing now, DOS retry budget exhausts, C64 hangs
  on the abandoned IEC transfer). Physics: higher linear density at inner cylinders -> peak shift
  (ISI) smears the 4/6/8 us gap classes into the fixed classifier dead-bands for whole
  revolutions. SEPARATE MINOR FINDING (logged, deferred): instant-FNF with CNT_READOP=0 when
  loading immediately after inserting a disk post-power-on = the DOS one-shot 30-sample PA1
  ready check races the settling mechanism (error class never retried); workaround: let the
  mechanism settle or read the directory first.
  DESIGN AS BUILT (physical_1581_mfm_quantise.vhd + C_QUANT_* in the pkg): each gap classifies
  to the NEAREST class n in {2,3,4} half-cells around a tracked half-cell estimate (Q8.4,
  nominal 100.0 cycles), acceptance |G - n*est| <= est/2 (windows touch at the midpoints
  2.5*est / 3.5*est -> NO dead-bands), outside -> class 11 + re-seed to nominal; the estimate
  adapts by a FIXED 1/8-cycle step toward each accepted gap (sign-based, median-seeking) with
  hard clamps 90..110 cycles. NOTE: the originally planned proportional/mean estimator was
  REJECTED BY THE A/B HARNESS — peak shift only ever lengthens short gaps and shortens long
  ones, so a mean-seeking tracker has a biased equilibrium and walked to the +10% clamp at
  S=20, losing to the old windows; the median-seeking update is anchored by the unshifted
  majority (residual bias ~+1 cycle at S=20). Legacy window constants kept as documentation +
  reference for the test-only fixed classifier. Diag map v5 (VERSION 0x053F): 0x36 EST (live
  half-cell estimate, Q8.4), 0x37 RNF_CTX (requested track/sector of the last RNF); doc updated.
  A/B MARGIN HARNESS (new tb_physical_1581_quantise_ab + ref_mfm_quantise_fixed, identical
  stress vectors through old and new): NO regressions (canonical, speed to +/-8%, drift +/-2%,
  jitter +/-12, peak S=20, the measured 126-cycle artifact, splice +2.5% step — both pass);
  new WINS every discriminating class: speed +/-12%, drift 0..+/-12%, jitter +/-22 (3/3 seeds),
  peak shift S=22 and S=24, combos S20+/-3% and S15+5% (family wins: speed=2 drift=2 jitter=4
  peak/combo=5); jitter +/-24 = the physical decodability cliff (2- and 3-cell gaps overlap),
  both mostly fail as they must. Payload equality asserted on every successful decode — no
  silently wrong sector possible. rc=0, ALL ACCEPTANCE CRITERIA MET.
  FULL VERIFICATION GREEN: GHDL analyze clean; decoder tb (canonical + runt vectors) byte-exact;
  diag tb v5; crc/inputs/rdfifo/mech tbs; ovf tb; A/B harness; the ~22 min closed-loop
  controller tb rc=0 (restore, media_ready ~398 ms, byte-exact payloads on cyl 0/1, Read
  Address, Verify, absent-sector RNF, pending-latch, abort spacing 200 ns, recovery);
  main.vhd differential vs HEAD identical. Files: mfm_quantise (rewrite), pkg, decoder +
  controller (est/RNF-ctx taps), diag (v5), main.vhd (3 lines), 1581_dd_debug_device.md,
  diag tb, 2 NEW test files (untracked: tb_physical_1581_quantise_ab.vhd,
  ref_mfm_quantise_fixed.vhd). NEXT: rebuild R3, retest SHADES (expect: reliable loads; watch
  0x36 EST near 0x64x and 0x37 RNF_CTX on any residual miss).

- 2026-07-14 (session 3, round 13): **ROUND-12 WRITE-SPLICE REGRESSION ROOT-CAUSED, REPRODUCED
  GAP-EXACT IN SIM, AND FIXED (preamble-qualified sync gate; VHDL only, all sim gates green).**
  Hardware evidence (round-12 bitstream, 3 sessions): t39 s1 -- the sector right after the index
  write-splice, holding the D81 header/BAM -- deterministically unreadable: 30/30 RNF with
  RNF_CTX 0x2701, CNT_IDDEC pinned (s1 ID never decoded), CNT_CRCERR 0, EST healthy 99.25-99.75,
  and CNT_GAPERR DROPPED to ~16/rev vs 20-29 under round-11 (splice junk that used to fail loudly
  was being ACCEPTED). MECHANISM (confirmed, not just hypothesized): the round-12 no-dead-band
  acceptance (est/2, span 1.5*est..4.5*est) swallows splice garbage; junk alternating
  ~446/~344-cycle gaps IS the A1 sync gap pattern (long,med,long,med) -- the sync detector fires
  overlapping FALSE A1s every 2 gaps (3 arm the decoder, sync_cnt=3), and 8 more junk gaps
  (S,S,S,S,S,L,S) decode to bits 11111011 = a fake FB data mark -> the decoder opens a BOGUS
  512-byte data field that consumes the next sectors real preamble+ID+A1 train every rev. That
  reproduces EVERY counter signature: no id_valid (IDDEC flat), bogus-field CRC garbage is a data
  crc fail not an ID crc error (CRCERR 0), junk accepted (GAPERR drop). The old windows survived
  the same junk because 446..450 lies beyond C_GAP_LONG_HI=445 and 344 sits in the 343..354
  dead-band: every chain element went class-11 and reset the pipeline before a field could open.
  WHY NOT THE PLANNED TWO-TIER TOLERANCE (tight est/4 acquisition + est/2 in-field): REFUTED BY
  THE HARNESS, kept as a live instance. ISI moves every transition of the A1 train (alternating
  long/med -> both neighbors differ) so each train gap deviates 2*S; est/4 = +/-25 rejects the
  sync train of any record with S>=13, and the tacq column fails peak S=15/S=20/S=22/S=24 and all
  3 combos (5 must-row refutations recorded) -- the exact far-cylinder wins round 12 exists for.
  Junk (+46..+48) and legit S=22/24 train deviations (+/-44..48) overlap, so NO per-gap tolerance
  separates them; the discriminator is STRUCTURE, not width.
  FIX AS BUILT (matches what a real data separator PLL does -- it only locks during the 00
  lock-up preamble, which the 1581/WD1772 writes 12x before every A1 train, including after every
  sector-write splice): (a) decoder physical_1581_mfm_decoder: while HUNTING, an A1 sync is
  honored only if a run of C_QUANT_SYNC_RUN=16 consecutive SHORT-class gaps ended at most
  C_QUANT_SYNC_LAT=6 gaps ago (A1 window = med entry gap + L,M,L,M = 5); class-11 hard-closes the
  gate; in-field syncs (A1 #2/#3, field_active = sync_cnt/=0 or state/=S_IDLE) bypass it;
  (b) quantiser gets field_i (threaded from the decoder): while hunting, est adapts from
  SHORT-class gaps only (junk cannot walk it; in-field adaptation unchanged); classification
  tolerance stays est/2 in BOTH phases. Test knobs (production defaults harmless): decoder
  G_SYNC_GATE=false + G_QUANT_HUNT_ADAPT_ALL=true restores exact round-12 semantics,
  G_QUANT_TOL_ACQ_SHR=2 instantiates the refuted two-tier candidate. No port/ABI change above the
  decoder; controller/main/mega65 untouched; no diag map change (locked bit now only blips on
  honored syncs -- strictly more truthful).
  VERIFICATION, ALL GREEN: (1) baseline: the UNMODIFIED round-12 harness re-run first (rc=0, same
  win table) proving the environment reproduces round 12. (2) A/B harness extended to FOUR
  decoders on identical flux (old fixed | r12-compat | r13 prod | tacq refuted; 44 trials + probe
  table; the 38-row round-12 result table is PRESERVED ROW-FOR-ROW on r13 incl. speed/drift +/-12%,
  jitter +/-22 3/3, peak S=22/24, combos, artifact-126, splice-step, jitter +/-24 parity with
  r12 (s1/s2 fail, s3 pass), payload-equality guard everywhere). NEW junk-splice trials:
  junk rand x3 (naive [130..480] LFSR junk + fluxless stretches) = too tame, all columns pass,
  kept as documented iteration evidence; junk chain x3 (mfm_flux_gen_pkg junk_splice_chain: the
  reconstructed splice profile) = old=PASS r12=FAIL r13=PASS deterministically, with mechanism
  instrumentation: r12 junk_lock=1 (false A1 in junk) and data_start ~5.8 us BEFORE the record
  even starts (bogus field), old/r13 lock 0; per-splice gap errors old 8-9 vs r12/r13 3-4
  (mirrors the hardware GAPERR drop) vs tacq 18-19. rc=0, ALL ACCEPTANCE CRITERIA MET (incl.
  hard asserts: chain rows must show r12 fail + bogus-field signature; r12-compat must pass every
  round-12 must-row; tacq must fail at least one peak/combo must-row). (3) decoder tb canonical +
  runt vectors byte-exact through the gate. (4) diag tb v5 green (no map change). (5) GHDL
  analyze clean for all 11 production units. (6) crc/inputs/rdfifo/mech/ovf tbs green; the long
  closed-loop controller tb re-run to completion rc=0. Mech-model junk case NOT added: the model
  emits mathematically clean MFM with exact index timing, and injecting splice junk would perturb
  sector positions the controller tb depends on -- codec-level coverage (4 decoders, gap-exact
  reproduction) is where the classifier lives; documented here instead. (7) main.vhd untouched
  (no differential needed). BUILD NOTE: GHDL 5.1.1 multi-library harness builds need SEPARATE
  workdirs per library (object files share basenames and silently overwrite in a shared dir;
  round-12s "one workdir" recipe linked stale objects) -- harness header updated.
  Files: physical_1581_pkg.vhd (C_QUANT_SYNC_RUN/LAT + full round-12/13 story),
  physical_1581_mfm_quantise.vhd (field_i, tier generics, hunt-adapt gating),
  physical_1581_mfm_decoder.vhd (sync gate + field_active + test generics),
  ref_mfm_quantise_fixed.vhd (shape compat), mfm_flux_gen_pkg.vhd (LFSR junk model:
  junk_splice_rand/chain + mfm_splice_junk), tb_physical_1581_quantise_ab.vhd (4-column harness,
  junk trials, mechanism instrumentation). NEXT: rebuild R3, retest -- expect t39 s1 readable
  again (LOAD"\$" works), no RNF_CTX 0x2701, CNT_GAPERR back to round-11-like levels at the
  splice, far-cylinder (61-62) reliability retained; watch EST 0x36 stays ~0x64x.

- 2026-07-12: **R3 TIMING NOT CLOSED (blocking next step, documented in HANDOVER.md sec 8.0).**
  Routed WNS -5.051 ns / 83 failing endpoints (setup; hold OK). 71 = physical_1581 CDC (qnice_clk<->main_clk)
  with NO timing exceptions; 12 = pre-existing framework qnice half-cycle path (QNICE ramrom->CPU SP,
  -0.281 ns, congestion). FIX (documented, NOT applied — maintainer will apply their way): 2 clock-to-clock
  false_paths qnice_clk<->main_clk in CORE/CORE.xdc (or granular per-sync). CORE.xdc left UNCHANGED. This is
  a constraints-only issue; no functional RTL change needed. Report:
  CORE/CORE-R3.runs/impl_1/mega65_r3_timing_summary_routed.rpt. Do FIRST, before any milestone.

## ===== IMPLEMENTATION COMPLETE (read-only milestone) — 2026-07-12 =====
R1(read path) R2(WD branch) R3(threading+integration) R4(menu) R5(diag) + docs + idle-gate ALL DONE.
Core is BUILDABLE (all 4 boards, VHDL2008-registered) + sim-verified (GHDL suite green, iverilog fdc PASS,
menu_test all modes, image mode byte-identical, adversarially reviewed). NO COMMITS (user commits).
Both repos on mh_implement_90; submodule needs commit+pointer bump when user is ready.
NOT DONE (by design / user scope): write + format (next milestone); hardware qualification (Q/H gates,
scope/LA) = user; full mixed-language elaboration + synthesis/timing/CDC for R3-R6 = user's Vivado;
symmetric idle-gate (pending decision). Working-tree cleanup: GHDL --elab-run drops executables in repo
root -> clean with `rm -f tb_physical_1581_* e~tb_*.o` after runs (or add per-test Makefiles like tb_crt_parser).

## Resume hint (if interrupted) -> R5 (diag), then R4-tail (idle-gate), then docs
CORE IS BUILDABLE now. R5 = QNICE read-only diag device C_DEV_C64_PHYS1581=0x0108 (globals + mega65
device decode + physical_1581_diag.vhd register bank on c64_clk_sd_i=QNICE clock, SAME clock as controller
so NO CDC) exposing live drive state + counters + last result/CHRN/CRC + index period/width; wire main->
mega65 QNICE read path; doc/1581_dd_debug_device.md (how to read via QNICE monitor). Then R4-tail: m2m-rom
idle-gate so Image<->Internal toggle is ignored while the drive is busy. Then docs: tests/README (append
Version WIP-V6-A18X1-TBD section), FAQ (ext dev-8 conflict, DD-only, safe switch), VERSIONS/ROADMAP/README.
Then a final consolidation pass. All verification of the integrated build/timing/hardware = user's Vivado.
After the adversarial review: fix any image-mode regression it finds (image path MUST be byte-identical),
then R3 = thread the phys ABI + f_* pins through the hierarchy: iec_drive.sv (add physical_mode, gate
sd_rd/sd_wr off :108-109, force 1581 engine active :168/:116) -> c1581_multi.sv -> c1581_drv.sv (drive
phys_* from CIA PA2/PA0, re-source PA1/PA7/PB6, wire phys_mode=0 for image) -> main.vhd (instantiate
physical_1581_controller + rdfifo on c64_clk_sd_i/new c64_rst_sd_i; ABI; gate sd_*) -> mega65.vhd (f_*
ports, C_MENU_INTERNAL_1581=3, decode) -> top_mega65-r{3,4,5,6}.vhd (route f_* pins, drop static '1',
G_PHYS1581_CAPABLE=true all boards). Then R4 (config.vhd menu item flat idx3, OPTM_SIZE 159->160, OPTM_DY
27->28, CORE_VERSION WIP-V6-A18X1, osm_const.asm shift, m2m-rom idle-gate, menu_test.py) and R5 (globals
C_DEV_C64_PHYS1581=0x0108 diag BRAM + doc/1581_dd_debug_device.md). Full-chain + synth = user (Vivado).

## R1 module inventory (all compile; codec fully verified, controller compile-only pending model)
CORE/vhdl/physical_1581/: physical_1581_pkg, _crc, _mfm_gaps, _mfm_quantise, _mfm_gaps_to_bits,
_mfm_bits_to_bytes, _mfm_decoder, _inputs, _rdfifo, _controller.
Tests: CORE/vhdl/test/tb_physical_1581_codec/ (crc, decoder — PASS), tb_physical_1581_inputs/ (inputs,
rdfifo — PASS), tb_physical_1581_controller/ (model + controller test — pending).
