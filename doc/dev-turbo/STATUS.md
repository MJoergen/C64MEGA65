# Turbo modes (issue #87, absorbing #242): status and running memory

Entry point for anyone, human or coding agent, who picks up this work. Read this file first, then `RESEARCH.md` (facts, sources and analysis), `recon_map.md` (every file and line the implementation touches) and `TEST-PLAN.md`. A design specification (`TURBO-SPEC.md`, in the style of `doc/dev-ntsc/NTSC-SPEC.md`) follows once the open decisions in section 1.2 are taken. All paths are relative to the repository root.

## 0. TL;DR

* **Phase:** implementation, simulation and independent reviews done (section 8); committed and pushed on branch `turbo-mode` in the main repo and in the submodule (2026-11-05); next: Vivado builds (the maintainer) and hardware tests.
* **Scope (locked):** exactly the turbo modes of the MiSTer C64 core: `Off`, `C128` and `Smart`, each at `2x`, `3x` or `4x`. The OSM items for this already exist in `config.vhd`; only the wiring is missing (`main.vhd` hardcodes `turbo_mode => "00"` and `turbo_speed => "00"`).
* **Branch and version (locked):** branch `turbo-mode`, created off `develop`; `CORE_VERSION` becomes `WIP-V6-A22X1`.
* **Baseline:** `develop` at `55918e6` (`WIP-V6-A22`), submodule `CORE/C64_MiSTerMEGA65` at `650c6b5`.
* **This folder** lives on branch `turbo-mode` (committed together with the implementation).

## 1. Decisions

### 1.1 Locked

| # | Decision | Date | Source |
|---|---|---|---|
| L1 | Only the modes MiSTer supports: `Off` / `C128` / `Smart` at `2x` / `3x` / `4x`. Not planned: C64 Ultimate `$D031`, Turbo Chameleon `$D0F3`, SuperCPU registers, anything above 4x, a "badline off" mode. | 2026-11-05 | maintainer (sy2002) |
| L2 | Branch `turbo-mode` off `develop`; version `WIP-V6-A22X1`. | 2026-11-05 | maintainer |
| L3 | Real cartridges keep working in turbo: every access to the expansion port runs at 1 MHz; the cartridge always sees a 1 MHz PHI2. Turbo and hardware cartridges are not made mutually exclusive. | 2026-06-07 | #87 comment 3; commits `671a7fa` (main repo) and `b0ddbe6` (submodule) |
| L4 | Turbo is implemented after NTSC, so that drift and cartridge tests can run in both standards. NTSC shipped in A22; #181 was closed on 2026-11-03. | 2026-06-07 | #87 comment 4 |
| L5 | Porting upstream MiSTer fixes, the hardware-cartridge protection and a Smart disk-activity detector for our drive topology are part of the scope (they are not new modes). | 2026-11-05 | maintainer, follows from L1 |
| L6 | Real cartridges stay usable in turbo, with the fix for the timing gap (finding F2): real-cartridge accesses run only in clean 1 MHz cycles. No automatic turbo-off for hardware cartridges. | 2026-11-05 | maintainer (decision B) |
| L7 | The turbo setting is saved in the config file like every other setting; the end user sees an active turbo in the summary line of the Model submenu (for example `Model: PAL Smart 4x`). | 2026-11-05 | maintainer (decision C) |
| L8 | This work is `WIP-V6-A22X1`. Version numbers of other work (for example the #260 NTSC sprite fix) are decided later. | 2026-11-05 | maintainer (decision D) |
| L9 | #87 is the single issue; #242 is closed as a duplicate of #87 with the comment drafted in `~/Downloads/issue-242-closing-comment.md`. | 2026-11-05 | maintainer (decision E) |
| L10 | Games are tested by Boris and other community testers, not by the maintainer; they are asked on GitHub (#87) when `WIP-V6-A22X1` is ready. The game items in `TEST-PLAN.md` are marked **(community)**. | 2026-11-05 | maintainer |

### 1.2 Open

No scope decision is open. Details to settle in `TURBO-SPEC.md`:

* the exact form of the F2 fix: the clean-cycle rule in the `CPUC` term of `cpu_cyc`, and whether ROML/ROMH need `io_enable` gating in hardware-cartridge mode (`RESEARCH.md` 5.2, 5.3);
* hiding `Turbo speed` while turbo is `Off` with `OPTM_DEP2`, as MiSTer does (recommended);
* the effect of upstream `d6048db` on top of the `io_enable` rule (it gets ported in any case, L5).

### 1.3 Glossary (the three modes)

* **Off:** a standard 1 MHz C64.
* **C128:** software-controlled. Turbo is active only while a program sets bit 0 of `$D030`, the C128 2 MHz register; the selected speed (2x/3x/4x) replaces the C128 2 MHz. Ordinary C64 software never sets it and stays at 1 MHz. Not automatic: there is no slowdown for disk access, exactly like a real C128.
* **Smart:** automatic. Always fast, but the core falls back to 1 MHz for 0.5 s after every activity on the IEC (disk drive) bus, so loading keeps working. Timing-critical games and demos break in this mode.
* **Speed:** `2x` / `3x` / `4x` = up to 2 / 3 / 4 CPU memory accesses per 1 MHz cycle. I/O, badlines and sprite DMA still run at C64 speed, so the effective factor is lower and depends on the program.

## 2. Status by phase

| Phase | Content | Status |
|---|---|---|
| P0 | Read #87, #242 and every source they link; analyze the core | DONE 2026-11-05 |
| P1 | Scope decisions (DONE 2026-11-05, L1-L9); GitHub posts and messages (section 3) | IN PROGRESS: #242 closing comment drafted, the maintainer posts it |
| P2 | `TURBO-SPEC.md` | DONE 2026-11-05 |
| P3 | Branch `turbo-mode`, implementation (see `recon_map.md`) | DONE 2026-11-05 (uncommitted) |
| P4 | Simulation (`TEST-PLAN.md` section 2, `TURBO-SPEC.md` section 6) | DONE 2026-11-05: `CORE/vhdl/test/tb_turbo/run.sh all` PASS |
| P5 | Vivado builds: R3 and R6 first, then R4/R5 | TODO (the maintainer runs the builds; an agent uses at most 4 CPU cores while the maintainer works on this machine) |
| P6 | Hardware tests (`TEST-PLAN.md`), community test round | TODO |
| P7 | Docs (`VERSIONS.md`, `doc/inofficial.md`, `tests/README.md`, user docs), merge into `develop` | TODO |

## 3. GitHub and communication plan (nothing posted yet)

* **#87** stays the single issue. Its title "Implement MiSTer-supported turbo modes" already matches L1, so no rename. Subscriber update drafted 2026-11-05 in `~/Downloads/issue-87-whats-coming.md`: covers #242 (credit to Boris), the three modes and speeds, what stays the same (picture, clocks, DMA, real cartridges at 1 MHz incl. the F2 fix before release), what is not coming, and that testers get asked on GitHub when the alpha is ready. No version number in it.
* **#242** gets closed as a duplicate of #87, with thanks. State plainly: C128 `$D030` control and Smart are coming; C64 Ultimate and Turbo Chameleon registers and speeds above 4x are not planned. Closing comment drafted 2026-11-05 in `~/Downloads/issue-242-closing-comment.md` (answers the five questions, asks Boris to test and to add a Turbo section to the user docs).
* **Boris Schneider-Johne** (GitHub `Kugelblitz360`, lemon64 `docbobo`, author of #242, of both patched games and of the user docs at https://c64.mega65.org): his Rescue on Fractalus patch is covered by the C128 mode; the Koronis Rift speed-up needs the C64 Ultimate registers, so on our core that game runs as the normal C64 version (one exception to try, see `TEST-PLAN.md`); testing gets requested on GitHub (#87) when `WIP-V6-A22X1` is ready (L10); heads-up for a Turbo section in the user docs, including "use C128 mode for software that switches turbo itself; Smart breaks timing-critical software". The #242 closing comment covers all of this.
* **oe3gwu** (author of #87): V6 brings 2/3/4 MHz, not 40 MHz; asked together with the other testers on GitHub to try Test Drive II in Smart 4x when A22X1 is ready.
* **MJoergen:** review findings F1 and F2 (section 4); his SIMREU-on-R3 concern is an explicit test gate; his precondition from #87 (avoid regressions of #2) is covered by the drift and TOD tests; NTSC is done.
* **paich64:** the hardware test matrix of `TEST-PLAN.md`.
* **GitHub (#87)**, when A22X1 is ready (optionally also pointed to from Discord): call for testers with the **(community)** items of `TEST-PLAN.md`; name programs that use the C128 2 MHz mode; say clearly that A22X1 does not contain the REU work of A23 (A23 lives on branch `reu1764`, unmerged, but its zip is public in #232/#235).

## 4. Key findings (details in `RESEARCH.md`)

* **F1, missing upstream fix:** our fork lacks MiSTer commit `d6048db` (2025-08-27, "Disable turbo while I/O access for better compatibility"). It adds a `cs_io` term to the turbo decision in `fpga64_sid_iec.vhd`. This is the only turbo-related difference between our fork and upstream; the VIC `$D030` code is identical. Port it.
* **F2, hardware-cartridge gap (paper analysis, confirm in simulation):** the June protection keeps cartridge accesses out of the turbo slots, but a cartridge ROM read can still execute in the regular slot `CYCLE_CPUC` right after a turbo access in the same 1 MHz cycle. The cartridge then sees the new address only about 317 / 190 / 63 ns before the CPU samples the data (turbo access in `CPU0` / `CPU4` / `CPU8`, simulated), instead of the normal window of about 444 ns. Fix idea: treat hardware-cartridge accesses like I/O (only in a "clean" slot, the existing `io_enable` rule).
* **F3, safe by design:** every DMA (SIMREU transfers, `.crt` bank loading, hardware `/DMA`) forces turbo off; CIA, SID, TOD and the VIC keep running at 1 MHz; turbo never changes `clk_main`, so flicker-free, NTSC and the drift logic are untouched. Test anyway.
* **F4, Smart needs our own activity detector:** MiSTer watches the IEC clock lines of the C64 and of its drive. Ours: the C64 clock output, the clock of the simulated drives and the clock line of the physical IEC port.
* **F5, OSM is ready:** items, `C_MENU_TURBO_*` bits and the summary line exist. Hiding `Turbo speed` while turbo is `Off` (as MiSTer does) is possible with `OPTM_DEP2`.
* **F6, real-world software:** Boris's Rescue on Fractalus (switches turbo via `$D030`, only in the border) is a perfect C128-mode test; in an always-on mode its screen breaks already at 4 MHz.

## 5. Next steps

1. Done 2026-11-05: submodule commit on its branch `turbo-mode`, then the main-repo commit with the pointer bump, both pushed to `origin` (`git log -1 turbo-mode` in each repository).
2. Vivado builds R3 and R6 (then R4/R5); check the R3 timing report, because `cpu_deferred` adds one decode level in front of the cartridge-port R/W and data registers.
3. Hardware tests of the core team and QA per the `Version WIP-V6-A22X1 - TBD` section of `tests/README.md`; then the GitHub call for community testers in #87 (L10).
4. At release: date and commit of the `doc/inofficial.md` row; remove "Turbo mode" from `ROADMAP.md` (as done for NTSC in `12b201f`).

## 6. How to resume

* **Read order:** this file, `RESEARCH.md`, `recon_map.md`, `TEST-PLAN.md`; then `AGENTS.md` sections 3.3 (main.vhd reset semantics), 4.2 (hardware cartridges) and 3.7 (OSM).
* **Line numbers** in these notes refer to the baseline in section 0; identifiers are authoritative, numbers are orientation aids.
* **Simulation tools:** `ghdl` 5.1.1 (`/usr/local/bin/ghdl`) for plain analysis; `nvc` for VHDL-2008 external names (ghdl 5.1 crashes on them).
* **Menu changes:** run and verify `M2M/rom/tests/menu_test.py` after any change to `OPTM_ITEMS` / `OPTM_GROUPS`; turbo needs no new menu lines, so the `C_MENU_*` indices stay stable. `CORE/m2m-rom/make_rom.sh` regenerates `CORE/m2m-rom/osm_const.asm` from `config.vhd` and `mega65.vhd`.
* **lemon64.com** sits behind a Cloudflare browser check: `curl` and WebFetch get HTTP 403; read it through the Claude-in-Chrome extension.
* **Conventions:** `tests/README.md` is append-only, newest section on top; `doc/inofficial.md` lists oldest first, and released rows never move; no apostrophes in QNICE assembly comments; no `Co-Authored-By: Claude` trailer in this repo.

## 7. Log

* **2026-11-05:** issues #87 and #242 and all linked sources analyzed (`RESEARCH.md` section 1). Scope L1 and branch/version L2 decided. This folder created. Closing comment for #242 drafted.
* **2026-11-05:** decisions B, C, D and E taken (L6-L9): real cartridges stay usable with the F2 fix; the turbo setting is saved like every other setting; this work is `WIP-V6-A22X1`; #242 gets closed into #87.
* **2026-11-05:** game testing goes to Boris and other community testers, asked on GitHub when the alpha is ready (L10).
* **2026-11-05:** #87 subscriber update drafted (`~/Downloads/issue-87-whats-coming.md`).
* **2026-11-05:** #242 closed by the maintainer. `TURBO-SPEC.md` written. Branches `turbo-mode` created in the main repo (off `55918e6`) and in the submodule (off `650c6b5`). Implementation and simulation agents launched (section 8).
* **2026-11-05:** implementation, two independent adversarial reviews, RTL and docs fix round, re-review of the fix and the full simulation done; everything passes; waiting for the maintainer's review and commit approval.
* **2026-11-05:** committed and pushed on `turbo-mode` (submodule first, then the main repo with the pointer bump); the maintainer starts the Vivado builds.

## 8. Implementation run (live)

Nothing gets committed until the maintainer approves. Agents run with effort at most xhigh and at most 4 CPU cores in total.

| Step | Agent | Status |
|---|---|---|
| A: implement W1-W4 per `TURBO-SPEC.md` sections 2-5 | implementer | DONE: submodule 2 files (+37/-7), main repo 9 files (+190/-21); GHDL/nvc differential analysis clean, `menu_test.py` verify and run PASS, `osm_const.asm` regenerates identically |
| B: benches `CORE/vhdl/test/tb_turbo/` per section 6, baseline measurements first; must model the real RAM/ROM/SIMCRT data-path latencies of our port | simulation | DONE: `run.sh baseline` 240/240 checks PASS; F2, lost `$FF00` writes and EF3 misses reproduced on the baseline; `d6048db` proven without effect |
| C: run the benches against the implementation | simulation (continued) | waiting for A and B |
| D: adversarial review, RTL and hardware | reviewer 1 | DONE: 1 high (doubled Ultimax cartridge writes in turbo), 1 medium (EF3 detection, same as E/H1), 5 low; all memory data paths OK (1-clock reads, 2 clocks slack) |
| E: adversarial review, integration (OSM, docs, invariants) | reviewer 2 | DONE: 1 high (H1), 6 low; all must-check items OK (menu, config file, wiring, invariants, docs) |
| F1: RTL fix round (gating of cartridge strobes/R-W in cycles with turbo accesses, EF3 busy mask, `$FF00` never turbo-eligible, comment corrections) | RTL fixer | DONE: micro-bench 3 Ultimax writes give 3 pulses (was 6), EF3 detected at 2x/3x/4x, all `$FF00` writes visible at PHI2 fall; 20 turbo-Off traces identical to the baseline; GHDL/nvc diagnostics identical to the baseline |
| F2: docs and menu-test fix round (menu_test.py layout/navigation/verify, VERSIONS.md, tests/README.md, RESEARCH/SPEC/TEST-PLAN corrections) | docs fixer | DONE: `menu_test.py` verify (18 dependent lines, 191 decoder vectors) and run PASS; layout Model submenu 12 / 17 lines; toggle walk Off-C128-Smart-Off; spec 2.3 then aligned with the final RTL by the orchestrator |
| F3: re-run all benches on the fixed code (plus new cases: single cartridge writes, `$FF00` visibility, EF3 detection; I1 over all cartridge-facing signals and `exp_port_we`), final report | simulation + orchestrator | DONE: `run.sh all` 427/427 core checks + Smart bench + static PASS (re-run independently by the orchestrator: PASS, 251 s); `menu_test.py verify` OK |

Implementation notes (step A):

* `iec_clk_n_i` reaches `main.vhd` unsynchronized (straight from the pin in all four `top_mega65-r*.vhd`), so the Smart detector reads `hw_iec_clk_n_sync` from a new two-flip-flop synchronizer (`hw_iec_clk_sync_proc`, `ASYNC_REG`); existing IEC paths are untouched. Detector: `turbo_smart_iec_detector_proc` between the marker lines, state in variables, no reset.
* Menu: `OPTM_DEP2(OPTM_G_TURBO_MODE, 1, 2)` on lines 46-50 (separator, `Turbo speed` headline, `2x`/`3x`/`4x`). `Off` shows `Smart, separator, Back`; `C128`/`Smart` show the speed block. `menu_test.py` got matching `V6_DEPS` entries and three emulator fixtures. `OPTM_SIZE` unchanged (189).
* Upstream `d6048db` is probably a no-op in our fork (turbo states already require `cs_turbo_eligible`); the benches verify this (spec 6c).
* Open for the maintainer: `ROADMAP.md` still lists "Turbo mode" as planned; the new `CORE_VERSION` means a new config file name (`c64mega65-WIP-V6-A22X1.cfg`), as for every alpha.

Review findings (step E, integration):

* **H1 (high):** on R3/R3A/R4 the EF3 detection (`cartridge_heuristics.vhd`, one address sample per PHI2 falling edge, fingerprint `$0108`, `$0109`, `$0013`) misses in turbo because consecutive RAM accesses share one 1 MHz cycle; then the EF3 reset request is ignored and starting a game from the EF3 menu fails (Smart mode; C128 mode unaffected). Planned fix: the heuristics export a busy flag (state not idle) and `main.vhd` forces turbo off while it is set, only in hardware-cartridge mode on the boards that use the heuristics; plus a bench case.
* **L1:** `VERSIONS.md` says Smart reacts to any IEC activity; the detector (like MiSTer) watches the IEC clock line only. Reword.
* **L2:** `tests/README.md` config-file item must mention the new `c64mega65-WIP-V6-A22X1.cfg` (`make_config.sh`).
* **L3:** a copied A22 config file can carry a turbo setting (the items were selectable but inactive in A22); the summary line shows it. Mention in the test notes.
* **L4:** the `$D030` latch survives menu changes (cleared only by a C64 reset); in C128 mode, C128 detection by reading `$D030` succeeds (254). Upstream behavior; document in the test plan.
* **L5:** `menu_test.py` does not assert the intended layout (Model submenu: 12 visible lines with `Off`, 17 with `C128`/`Smart`, no double separators) and has no navigation scenario that toggles the radio mother `TURBO_MODE`; `verify` only probes the `V6_DEPS` lines. Strengthen.
* **L6:** `ROADMAP.md` line 12 still lists "Turbo mode" (NTSC precedent: removed in `12b201f`). Maintainer's call, at merge time.

Review findings (step D, RTL and hardware):

* **High:** in hardware-cartridge mode a pending cartridge-area write is visible on the port during a cycle in which the CPU already ran a turbo access (`cs_romL`/`cs_romH`/`cs_UMAXnomap` not gated by `io_enable`; R/W and data driven from the pending access), so Ultimax writes reach the cartridge twice (sim: 3 writes give 6 pulses at 2x and 4x). Flash command sequences run from RAM are at risk.
* **Medium:** EF3 detection fails in turbo (same as E/H1).
* **Low:** a `$FF00` write in a turbo slot is never present at a PHI2 falling edge (hardware REU trigger missed); `d6048db` is a no-op here and upstream (chip selects need `cpuHasBus = '1'`, which is '0' at EXT1/EXT5); the cartridge window is about 410 ns (CPU1..CPUD) as with turbo Off, not 0.9 µs; a DMA request raised mid-cycle takes effect at the next EXT1/EXT5 (up to 3 more CPU accesses, upstream identical); after a `$00`/`$01` write in a turbo slot the bank bits reach the eligibility decision one clock later.
* **Checked OK:** all turbo-eligible data paths (C64 RAM, BASIC/KERNAL/char ROM, custom Kernal, SIMCRT cache, cartridge RAM, IO RAMs, RR-Net ROM) have a 1-clock registered read with 2 clocks of slack; RAM writes in turbo states are correct; SIMCRT, SIMREU, RR-Net and `$DE0F` bus observers are gated to clean cycles; no starvation; transitions; synthesis concerns.
* The new two-flip-flop IEC synchronizer feeds only the Smart detector; all existing IEC paths are unchanged (verified in the diff).

Bench results (step B, `CORE/vhdl/test/tb_turbo/run.sh`, nvc 1.21, real `fpga64_sid_iec` with T65, VIC-II, PLA, ROMs and custom Kernal; Ultimax test cartridge; main.vhd cartridge glue; cartridge model with access time):

* Data-path latencies read from the RTL: C64 RAM, BASIC/KERNAL/char ROM, custom Kernal, SIMCRT cache, cartridge RAM, IO RAMs and RR-Net ROM all 1 clock; the turbo budget is 3 register stages (mutants with 4 stages produce thousands of stale reads, all detected).
* Baseline: normal cartridge pin time 444 ns (14 clocks); after a turbo access 317 / 190 / 63 ns (after `CPU0` / `CPU4` / `CPU8`); wrong cartridge reads at 2x with a 250 ns cartridge (2138), at 3x (757) and 4x (260); crashes when code runs from cartridge ROM; `$FF00` writes lost (2-3 of 4); EF3 never detected in turbo. S1-S5, S7, I5 pass.
* Pre-fix run of the implementation: F2 gone, I1 identical, but phantom cartridge writes (same as review D) and about 225 ROML/ROMH read pulses without a CPU read per run.
* Two nvc-only patches are applied identically to every source set (a guard around one enum `'succ`, an initial value for one register); the static GHDL target maps two incomplete case statements to `others` on both sides.

Fix-round design (step F1, final RTL):

* `fpga64_buslogic.vhd`: `cs_romL`/`cs_romH` gated with `(io_enable or sim_crt_i)` (CPU accesses only); `cs_UMAXromH` (VIC) and `cs_UMAXnomap` stay ungated (the unmapped area has no strobe, and main.vhd needs the select to keep its data driver off); a CPU write to `$FF00` is never turbo-eligible (all modes).
* `fpga64_sid_iec.vhd`: new output `cpu_deferred` (`cpuHasBus and not io_enable and not cs_turbo_eligible`): the pending access waits for the next clean cycle. With turbo `Off` it is always 0 (`io_enable` is 0 only in `EXT0`, where `cpuHasBus` is 0).
* `main.vhd`: `exp_port_we <= c64_ram_we and not core_cpu_deferred` feeds the port R/W, the data-direction/data terms and the SIMREU `cpu_we`, so every waiting write looks like a read on the port and the SIMREU trigger stays in step with the executed write; `core_turbo_mode` forces `"00"` while `turbo_ef3_pause` is active (EF3 heuristics `busy_o`, `G_BOARD` R3/R4, hardware-cartridge mode).
* `cartridge_heuristics.vhd`: new output `busy_o` (STAGE1..STAGE5).
* Accepted residuals: waiting accesses to the Ultimax unmapped area show their address as a read (no strobe exists there); in `C128` mode `$D030` reads `$FF` during the EF3 pause; the RR-Net MK3 enable flag (`$DE80`/`$DE88` decode without strobe) can be set about 1 µs early by a waiting write (idempotent).

Re-review of the fix delta (reviewer D, independent micro-bench with the real `cartridge_heuristics.vhd`): no high or medium findings. Confirmed at 2x/3x/4x: EF3 detected, each Ultimax write once at the pins, each `$FF00` write once at a PHI2 falling edge; by code reading: no bus contention or wrong data direction (cart reads/writes, unmapped area, IO1/IO2, hardware DMA, VIC/BA phases), SIMREU correct (trigger in step with the executed write, register access unchanged), EF3 pause cannot stick, `$FF00`/`cpu_deferred` safe under DMA and BA, I1 holds for every changed expression. Low notes: `$D030` quirk during the EF3 pause (documented); turbo gain reduced for bank-switch-heavy real cartridges on R3/R3A/R4 (documented in spec 3.3); a waiting access to the Ultimax unmapped area shows as a dummy read (before: phantom write; IDE64 stays a hardware test item), and a write strobe derived combinationally by a cartridge could see a glitch of a few ns when R/W and address change together; `cpu_deferred` adds one decode level to `exp_port_we` (check the R3 timing report of the first build).
