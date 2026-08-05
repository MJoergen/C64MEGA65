# Handover: branch `mh_dev_drives` — two simulated drives 8+9 (issues #93 and #90)

Session handover 2026-08-05. The multi-drive feature is implemented,
adversarially verified, built and partly hardware-tested; the Shell ROM was
slimmed down; `develop` (simulated RR-Net, issue #234) has been merged in and is
staged but **not committed**. The next instance picks up at: **finish the merge
commit, then hardware test round 2.** Read this file top to bottom before
acting; skim `tests/README.md` (section "Version WIP-V6-A20") for the test gates.

## 1. Branch state

* Branch `mh_dev_drives`, forked from `develop` (`b238057`), pushed to `origin`
  (MJoergen/C64MEGA65); `HEAD` = `26d6ad9` = `origin/mh_dev_drives`.
  The story in commits:
  * `ba886b4` — the feature: two drives, per-drive Drive Settings, HyperRAM
    map retune, dependency format 2, M2M multi-drive bug fixes.
  * `c18c6d7` — hardware-test fix round 1: Shell-freeze watchdog, per-drive
    idle-gate, keep-mounted dirty state, ghost-disk strobe, OSM height fix,
    linear HyperRAM map.
  * `8595d66`, `6d0e708` — impl strategy `Performance_ExplorePostRoutePhysOpt`
    for `CORE-R3.xpr` and `CORE-R4/R5.xpr` (this is what closed R3 timing).
  * `d9f3307`, `0145262`, `e29094e`, `f1d1600` — Shell ROM space: budget guard
    fix, shared strings, one shared SPACE prompt, and the C64-only polyphase
    filters moved out of the ROM into a BRAM (`CORE/vhdl/video_filters.vhd`,
    device `C_DEV_C64_VFILTERS`), with a ghdl testbench under
    `CORE/vhdl/test/tb_video_filters/`.
  * `c546c7c`, `5673e57` — silent disk-image corruption while a drive is
    saving; flush only one virtual drive at a time.
  * `1dd0ea2` — A20X2 default: one drive 8, drive 9 invisible.
* Submodule `CORE/C64_MiSTerMEGA65` on its `develop`, commit `60d758e`
  (pushed): `physical_mode` per-drive vector + phantom-free toggle
  re-encoders in `c1581_multi.sv`.
* **In-progress merge (staged, uncommitted):** `origin/develop` `c8f95e8` was
  merged in on 2026-08-05 — simulated RR-Net / CS8900A incl. both MK3 ROM
  variants (issue #234) and the removal of the never-wired VIC-II model submenu
  (issue #120). `MERGE_HEAD` is present, 47 paths staged, working tree clean.
  See section 4 for what the conflict resolutions decided. Beware: the local
  `develop` ref was three commits stale when this started — always compare
  against `origin/develop` before merging.
* `git stash` still holds `stash@{0}` "WIP RR-Net OSM radio group" from branch
  `mfj_issue_234`. It is **obsolete**: RR-Net landed on `develop` and came in
  with the merge. Do not pop it here; drop it once its owner agrees.
* `VERSIONS.md` has no RR-Net entry yet — release-note wording is the user's
  call, and per repo convention it is written at release time, not per alpha.

## 2. Immediate next steps

1. **Commit the merge** (the user asked for it to be left uncommitted, so this
   is theirs to trigger). Nothing is pending on the technical side: every local
   gate passes, see section 5.
2. **Hardware test round 2** (user tests in a new session). The build blocker
   is gone — R3 closed timing with the new strategy (`RESULT R3 OK
   WNS=0.374 WHS=0.054`, 03-Aug; R6 `WNS=0.378 WHS=0.052`). Highest value
   re-tests, in order:
   * The freeze scenario: OSM open, drive 8 mounted, "Unmount on reset"
     off, hammer the reset button during LOAD/SAVE. Must survive
     indefinitely now (fix: `qnice2hyperram` watchdog).
   * "Disk Image: Always" for drive 8 while drive 9 (Internal 1581) has
     motor/reset activity. Must be selectable now (fix: per-drive gate).
   * SAVE, then soft reset with keep-mounted; verify the yellow-LED flush
     completes afterwards and the file on SD is correct (fix: vdrives
     keeps dirty state).
   * Hard reset with a drive in "Always": must NOT serve a ghost disk
     (fix: size-0 unmount strobe).
   * Full A20 gate list: `tests/README.md`, incl. drive-steal stress and
     corrupt-config one-hot case; plus the A19 RR-Net gates that came in with
     the merge.
   * Config file: regenerate `/c64/c64mega65-<CORE_VERSION>.cfg` (currently
     `c64mega65-WIP-V6-A20X2.cfg`) via
     `M2M/tools/make_config.sh <name> auto`. `OPTM_SIZE` is **189** after the
     merge, so a `.cfg` generated before it is the wrong size and will be
     rejected.
3. Optional cleanup once the merge is committed: `doc/inofficial.md` lists
   `WIP-V6-A19` (08/04) above `WIP-V6-A20` (08/01) because develop's alpha
   landed after this branch forked. Order is the user's call.

## 3. What the feature is (user-visible)

* Main menu: `8:<Mount Drive>` / `9:<Mount Drive>` are dependent lines,
  visible only in the two Disk Image modes; `8:Internal 1581` /
  `9:Internal 1581` live-status TEXT lines (23-char fixed labels, states
  Motor/Head/Reading/Busy) visible only in Internal-1581 mode; nothing
  when Off. Then `PRG:<Load>`, then submenu **Drive Settings**: per drive
  a radio group (Disk Image: If mounted / Disk Image: Always /
  Internal 1581 / Off) + single-select "Unmount on reset".
* Defaults (A20X2): drive 8 = If mounted, drive 9 = **Off**, both unmount
  checkboxes ON (= pre-V6 behavior). Multi-drive is opt-in: with a second
  device on the IEC bus some fastloaders and demos stop working, so out of
  the box the bus carries exactly one drive and both drive-9 main-menu
  lines are hidden, just like in the single-drive builds up to A18X2. The
  user enables drive 9 consciously in `Drive Settings`.
* Semantics: "Always" = drive answers on IEC without a disk (MiSTer
  parity). Off = engine held in reset, IEC device number free for real
  hardware. Internal 1581 on at most one drive; selecting it on the other
  drive "steals" it (other drive falls back to If mounted,
  clear-before-set in `OSM_SEL_PRE`, `_OSM_PRE_STEAL`). Unmount-on-reset
  OFF keeps the image mounted across SOFT resets only; hard reset always
  unmounts. Mounts survive mode switches. Both drives take D64 + D81.
* From the merge, "Advanced Settings" additionally carries the `RR-Net` radio
  group (`Off` / `On: MK2` / `On: MK3 & Std ROM` / `On: MK3 & Custom ROM`) and
  no longer carries the `VIC-II: %s` submenu; the VIC-II RTL is untouched and
  stays hardcoded to old HMOS (`variant => "10"`, see `doc/vic_ii_variants.md`).
* Version `WIP-V6-A20X2`; `doc/inofficial.md` has the rows.

## 4. Architecture decisions and key facts

### HyperRAM map (globals.vhd) — linear, fully guarded, self-documenting

`M2M 0x0000 (384 win = 3 MB) | CRT 0x0180 (372 win = 2.90 MB) |
CRT_GUARD 0x02F4 | VD0 0x02F5 (drive 8, one D81) | VD0_GUARD 0x0359 |
VD1 0x035A (drive 9) | VD1_GUARD 0x03BE | REU 0x03BF (64 win) |
REU_GUARD 0x03FF | total 0x0400` (units: 8 kB windows).
* M2M shrank 4 MB -> 3 MB after adversarial validation: ascal's frame
  buffer is `RAMBASE 0`, `RAMSIZE = 2^ceil(log2(720*540*3)) = 2 MB`,
  write-clamped `AND (RAMSIZE-1)` — the ONLY framework HyperRAM consumer,
  and only on R3 (R4+ has ascal in SDRAM; `hr_core` masters are on
  HyperRAM on ALL boards). An elaboration assert in `mega65.vhd` guards
  the boundary. Read path is unmasked (theoretical, reads only).
* `.crt` ceiling derives from `C_HMAP_CRT_GUARD - C_HMAP_CRT` and is
  exported by `make_rom.sh` as `C64_CRT_MAX_SIZE_HI/LO` (0x2E8000).
* `C_VDNUM = 2`; 4-master core arbiter in `mega65.vhd` (REU, CRT, MOUNT,
  MOUNT2). Core device ids are now packed tight, so check `globals.vhd`
  before adding one: `C_DEV_C64_MOUNT2 = 0x0109`,
  `C_DEV_C64_VFILTERS = 0x010A`, `C_DEV_C64_RRNET_MK3 = 0x010B` (the last one
  was renumbered during the merge — develop had shipped it on `0x0109`, which
  this branch had already taken). `VFILTERS_DEV` in `m2m-rom.asm` hardcodes
  `0x010A`; it is the only device id duplicated into QNICE assembly.

### Dependency format 2 (menu "smart dependencies")

* Magic `0x2DEF`; raw word bits 11-8 are a 4-bit item MASK (was single
  index). `OPTM_DEP(m,i)` = mask `2^i`; new `OPTM_DEP2(m,a,b)`.
  Resolved word: {bit15 valid, mask 11-8, first-member flat index 7-0};
  `OPTM_DEP_OK` scans the mother group for the selected member's ordinal.
  Validator class 1 = mask checks; class 4 now ALLOWS dependent
  MOUNT_DRV and START lines (special = help|load_rom only, built in
  `options.asm` `_HLP_DEPVAL`). `OPTM_RUN` normalizes a hidden initial
  cursor (`_OPTM_RUN_INI*` in `menu.asm`).
* OSM height convention is dependency-AWARE: `OPTM_DY = 29` = max
  SIMULTANEOUSLY visible lines (31 structural − 1 twin per drive).
  `menu_test.py verify` enforces the exact per-view max; the boot-time
  serial warning uses `OPTM_DEPS_MINHID` (pure routine, end of
  `optm_deps.asm`) as a safe global under-approximation.
* Menu numbers: `OPTM_SIZE = 189`, 10 submenus, OPTM_ITEMS 1915 chars
  (count quote-aware — quotes inside VHDL comments fooled a naive count! — and
  note the budget comment counts each `\n` as TWO characters),
  `MENU_HEAP_SIZE = 3456` (peak 3098), `HEAP_SIZE` 3712 debug /
  26752 release. Key flat indices: mount8=2, stat8=3, mount9=4, stat9=5,
  drv8 items 10-13 (`IfM,Alw,1581,Off`), unmount8=14, drv9 items 18-22,
  RR-Net items 179-182, Close Menu=188. Group ids: DRV8_MODE=31,
  DRV8_UNMOUNT=32, DRV9_MODE=33, DRV9_UNMOUNT=34, SIM_RRNET=35 (30 is free —
  it belonged to the removed VIC-II submenu). `C_MENU_*` in `mega65.vhd` are
  the machine-checked flat indices; `osm_const.asm` etc. are REGENERATED by
  `make_rom.sh` — always re-run it after touching
  `config.vhd`/`mega65.vhd`/`globals.vhd`.
* The RR-Net group is the one menu block that is NOT a list of `C_MENU_*`
  constants: `mega65.vhd` decodes its three "On" items as the one-hot slice
  `subtype R_MENU_RRNET is natural range 182 downto 180` into
  `c64_exp_port_mode(3 downto 2)`, and "Off" (179) is "none of the three set".
  The slice is positional, so `rrnet_range()` in `menu_test.py` asserts the
  group's exact label order — reordering it would silently swap "standard MK3
  ROM" and "custom MK3 ROM".

### Drive-mode plumbing (VHDL)

* `mega65.vhd` decodes OSM bits -> `c64_drive_mode` (2 bit/drive: 00 IfM,
  01 Always, 10 Internal1581, 11 Off) + `c64_drive_unmount`; `main.vhd`
  ports `drive_mode_i`/`drive_unmount_i` (replaced `phys_1581_en_i`; develop
  still carried a `phys_1581_en` signal, which the merge dropped).
* `iec_drives_reset(i) = (not reset_core_n) or off(i) or (ifm(i) and not
  mounted(i))` — mirrors MiSTer c64.sv Enable-Drive semantics.
* Physical-1581 switching is protected 3-layer: (1) toggle re-encoders +
  un-gated inputs in `c1581_multi.sv` (submodule) — toggle LEVELS never
  jump on the select change (they are parity-persistent by design);
  (2) `main.vhd` `phys_switch_seq_proc` forces `phys_1581_en_q` through
  an all-zero gap (255 cycles) on every change (controller re-arms its
  disk-change latch on the en dip) + one-hot guard `phys_1581_en_oh`
  against corrupt configs; (3) Shell clear-before-set steal.
* M2M#57 mixed-language fix: SV unpacked-array outputs (`sd_lba`,
  `sd_blk_cnt`, `sd_buff_din`) bound to ASCENDING-range `iec_sd_*_sv`
  signals + per-element copies (`iec_sd_order_gen`) — downto actuals get
  cross-wired between drives otherwise (observed in MegaPET).
* `vdrives.vhd` (M2M, backward-compatible): optional ports
  `unmount_on_reset_i` (default all-1) + `reset_hard_core_i` (default 0);
  keep-mounted gating in `handle_drive_mounted`; QNICE-side dirty/flush
  bookkeeping survives soft resets for kept drives (CDC via packed
  `cdc_m2q_src/dst`); size-0 `img_mounted` strobe ~8 cycles after reset
  release for reset-unmounted drives (ghost-disk fix); #73 7-bit
  `sd_blk_cnt_i_corrected`.
* `qnice2hyperram.vhd` (M2M): self-healing watchdog (generic
  `G_TIMEOUT_CYCLES = 32768`): re-issues the latched read if a response
  is lost. THE fix for the total-OSM-freeze (reset button resets the
  hr clock domain — `hr_rst` includes core reset and bypasses
  `prevent_reset` — while QNICE keeps running; a dropped response used to
  stall the CPU forever via the wait line). Heals all four instances
  (2 mount buffers, .crt staging, framework bridge).
* Idle-gate scoping: `RM_IMG_DRIVE` (diag reg 0x28) is per-drive bits now
  (`img_drive_busy` vector in `main.vhd`, `physical_1581_diag.vhd` port
  2 bits). `_OSM_PRE_MODE` in `m2m-rom.asm`: physical mechanism only
  gates entering/leaving Internal 1581; image side only gates with the
  changed drive's own bit. Constants `P1581_IMGBSY_D8/D9/ANY`.

### Inherited from the RR-Net merge (develop's code, worth knowing)

Not defects of this branch, but they now live in our `main.vhd` and interact
with our features — check them before blaming multi-drive:
* The two MK3 ROM BRAMs use `wren_a => c64_ram_we and core_roml`, ungated by
  the RR-Net mode, so a SIMCRT or hardware-cart write into `\$8000-\$9FFF` can
  overwrite the baked-in standard MK3 ROM image until reconfiguration.
* `rrnet_mk3_enabled_proc` uses `reset_soft_i` DIRECTLY — a third exception to
  the RESET SEMANTICS block in `main.vhd`, which names only two.
* `M2M/vhdl/tdp_ram.vhd` had its read path rewritten (`q_a`/`q_b` moved inside
  the clocked process; they used to be driven concurrently from a registered
  address). That changes read-during-write behavior for every user, including
  the `.crt` bank cache in `sw_cartridge_wrapper.vhd`.
* The same commit added an `INIT_VAL` generic to `tdp_ram.vhd` **constrained to
  the full RAM size**, plus an unconditional `2**ADDR_WIDTH` slice loop in
  `InitRAM`. Only `rrnet.vhd` passes a pattern (2048 x 8), but every other
  instance still had to elaborate the constant and unroll the loop — for the
  32k x 16 `.crt` bank cache that is a 512 kbit constant and 32768 iterations,
  and it drove Vivado's `synth_design` into an out-of-memory kill on R3 and R6
  alike (`tcmalloc: allocation failed`, `Killed`, `RESULT <board> FAILED
  synth_1`). Fixed here by making the generic unconstrained with an empty
  default and guarding the loop on `INIT_VAL'length`, so only real users pay.
  This is an M2M framework change and belongs in the sy2002/MiSTer2MEGA65#63
  list. **Note the failure signature: the Vivado log contains no `ERROR` line
  at all — grep for `Killed` / `tcmalloc` / `FAILED synth_1` instead.**

### Upstream M2M bugs fixed locally (reliance-checked: nothing depended on them)

`#58` ROSM_SAVE R8-clobber loop (options.asm, counter now R1) — froze the
Shell with 2+ clean drives. `#52` `XOR 0,R9` no-op -> stuck track-buffer
WREN (shell.asm `_HDR_SEND_LOOP`) — corrupted last track byte; with 2
drives would have cross-corrupted. `#57` see above. `#73` blk-cnt widen.
Plus `gencfg.asm` `RP_SYSTEM_START` uninitialized R7 (CSR writes worked
by bank residue). An exhaustive "load-bearing bug" analysis confirmed all
consumers of `sd_buff_wr` are ack-gated idempotent RAM writes; safe.

## 5. Verification infrastructure (use it after every change)

All of the following pass on the staged merge:

* `python3 M2M/rom/tests/menu_test.py gen|verify|run|mutate` — golden
  model of menu/deps/height; run+verify after ANY menu or deps change.
  Current: `verify` OK (`OPTM_SIZE=189`, `OPTM_DY=29`, 10 regions, 62
  `C_MENU` constants, plus a ghdl testbench of the real `SEL_OPTM_DEPS`
  decoder), `run` 5/5, `mutate` 19/19 killed. Uses the QNICE emulator.
* `( cd CORE/m2m-rom && ./make_rom.sh )` — regenerates osm_const/globals/
  fhandles + assembles; last count 27066/28672 words. The guard trims the
  RAM padding off the image first (`d9f3307`), so the number is real headroom.
* macOS gotcha: the QNICE submodule tracks LINUX binaries; any submodule
  checkout reverts them. Rebuild: `cc M2M/QNICE/assembler/qasm.c -o
  M2M/QNICE/assembler/qasm && cc M2M/QNICE/assembler/qasm2rom.c -o
  M2M/QNICE/assembler/qasm2rom -std=c99 && (cd M2M/QNICE/emulator &&
  bash make.bash)`.
* ghdl (5.1.1 at `/usr/local/bin/ghdl`, VHDL-only) analysis: seed a workdir
  with every `package` file except `globals.vhd`/`config.vhd`, then
  `M2M/QNICE/vhdl/tools.vhd`, the package part of vdrives (lines ~94-105),
  `CORE/vhdl/globals.vhd` and `CORE/vhdl/config.vhd` in that order, plus an
  xpm stub for `xpm_cdc_array_single`; flags `--std=08 -frelaxed`.
  Strongest form: also extract the ENTITY declaration of every design file into
  its own stub and analyze those into the same library first — then `main.vhd`,
  `mega65.vhd` and all four `top_mega65-r*.vhd` compile with every port map
  resolved, which catches width and port-name breakage without Vivado.
  Expected noise: unit-not-found for the Verilog/SV sub-entities
  (`fpga64_sid_iec`, `iec_drive`, `keyboard`, `clk`, `audio`, ...); vdrives has
  6 pre-existing "locally static" errors (untouched CDC instances — avoid
  sliced formals in new port maps, ghdl can even crash on them; use packed
  src/dst vectors like `cdc_m2q_src`).
* iverilog (`-g2012 -t null`) parses the two changed SV files clean.
* No Vivado on this Mac; the user builds via a Parallels Linux VM ON THIS
  SAME working tree (`/media/psf/Home/...`). While a build runs: do not
  edit sources, the active board's `.xpr`, or regenerate `m2m-rom.rom`.
  `CORE/build_all.sh` (project mode, straight from the `.xpr`) writes
  `RESULT <board> OK|TIMING-FAILED WNS= WHS=` summaries into
  `CORE/build_*.backup.log`.
* If R3 timing ever regresses again: the knife-edge path is a single hold
  endpoint, `hr_d_io[4]` -> IBUF -> `IDDR` in
  `i_framework/i_hyperram/hyperram_rx_inst`, clocked by the IDELAY-delayed
  RWDS strobe. The durable fix is recentering the RWDS capture eye (+1-2
  IDELAY taps, ~78 ps each), but that value is MJoergen's silicon-calibrated
  number (issue #218 territory) — ask him, do NOT change it unilaterally.

## 6. Known open items (documented, NOT fixed — design decisions pending)

From the adversarial hunt (all pre-existing, exposed by reset storms; in
`tests/README.md` as test-gate notes):
* Soft reset while any cache is dirty is silently DROPPED (not deferred)
  — drives users into hard resets. Candidate: latch + execute when clean.
* Hard reset mid-flush bypasses `prevent_reset` and tears the image file
  on SD (escape-hatch by design; candidate: bounded grace period).
* Core reset during an in-flight `HANDLE_DRV_WR` transfer can put garbage
  in the (now kept-authoritative) cache.
* fdc1772 keeps stale phys state across a mid-op Internal-1581 mode
  excursion (low probability, bounded).
* No feedback when the idle-gate reverts a click (silent) — UX nicety.
* No testbench covers the c1581_multi re-encoders / two-drive steal /
  switch sequencer (static analysis + emulator-level only). Residuals:
  1541 engine wakes inertly for ~8 µs during the sequencer gap.
* Vivado utilization/BRAM growth of the doubled drive engines plus the merged
  RR-Net and ethernet blocks: R3 passed utilization fine before the merge;
  the first post-merge build is the one to watch.
* `tests/README.md`, section "Version WIP-V6-A19", still lists the removed
  `VIC-II model` among the items to regression-check after the volume change.
  It is identical on both merge parents and A19 has not shipped, so it was left
  alone rather than rewritten.
* Post-release: harmonize R6's impl strategy; consider framework-side
  memory-budget assert + ascal read-path masking (suggested in #63).

## 7. Upstream bookkeeping

* Feature issue: MJoergen/C64MEGA65#93 (user = sy2002; gh CLI is authed).
* Porting collection: sy2002/MiSTer2MEGA65#63 — TWO comments posted
  listing every M2M framework change (deps format 2 + validator relax +
  cursor normalization; vdrives ports + dirty-keep + ghost-disk strobe;
  qnice2hyperram watchdog; #52/#57/#58/#73 fixes; gencfg R7;
  OPTM_DEPS_MINHID + dep-aware height; framework-assert suggestion).
  ANY new M2M-side change must be added there (user's standing order). Still
  to add from this round: the shared-string/SPACE-prompt ROM savings and the
  `menu_test.py` `R_MENU_RRNET` range check.
* Commit style: no Claude co-author trailer (repo convention). VERSIONS.md
  and release docs are updated at release time, not per-alpha.

## 8. Memory pointers

Durable memories exist: `project_multidrive_feature.md` (summary + this
branch), `project_develop_merge_v6_rrnet.md` (the RR-Net merge resolutions),
`project_ghdl_local_analysis.md`, `project_qnice_emulator_testing.md`,
`project_osm_menu_resize_ripple.md`, `project_active_task_state.md`
(archived task log). The scratchpad of an old session (workflow outputs,
draft comments) may be gone — everything essential is in THIS file, the
commit messages, and `tests/README.md`.
