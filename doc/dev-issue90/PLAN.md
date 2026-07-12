# Physical 1581 (issue #90) — Implementation Plan & Checkpoint

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
- 2026-07-12: recon workflow + codec study DONE. Working notes relocated to doc/dev-issue90/
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
