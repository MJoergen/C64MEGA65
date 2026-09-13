# Adversarial review of `mh_dev_drives`

Review date: 2026-08-01

This is a read-only implementation review of the two-drive work described in
`doc/mh_dev_drives.md`. The review covered the feature commit range from
`b238057` through `e9e8699`; the branch was then synchronized to `69a2793`,
whose only additional change was the WIP release entry in `doc/inofficial.md`.
All builds and tests used a disposable clone. No source changes were made as
part of this review.

## Executive conclusion

The ordinary, idle-state feature paths are internally coherent and are
expected to work:

* two independently mounted D64/D81 image drives;
* per-drive If mounted, Always, Internal 1581, and Off modes;
* dependency-controlled menu lines and hidden-cursor normalization;
* physical-1581 ownership transfer while both sides are idle;
* keep-mounted images and reset-driven size-zero unmount notifications; and
* the local M2M fixes for issues #52, #57, #58, and #73.

The branch should not yet be considered reset-storm/data-integrity safe. The
most serious new finding is that the `qnice2hyperram` watchdog cannot tell a
lost read from a read which is still queued in the clock-crossing FIFO. It can
therefore enqueue duplicate reads during an ordinary short reset. Unmatched
duplicate responses can subsequently satisfy a different QNICE read.

The write/reset integrity windows already recorded in `doc/mh_dev_drives.md`
are also real. In particular, surviving a reset without freezing is not the
same as preserving the exact cache and SD-card contents.

## Findings, ordered by severity

### F1 -- High: the HyperRAM watchdog can enqueue duplicate reads

`M2M/vhdl/qnice2hyperram.vhd:94-105` reissues a latched read after
`G_TIMEOUT_CYCLES` whenever `reading` is set but the bridge has no request
currently asserted at its immediate Avalon interface. The default interval is
about 0.65 ms at 50 MHz.

That condition does not prove that the read was lost:

1. `qnice2hyperram` presents the original request to `avm_fifo`.
2. `M2M/vhdl/memory/avm_fifo.vhd:64-70` reports readiness according to space
   in its command FIFO, rather than readiness of the downstream HyperRAM
   controller. The source-side request is consequently accepted and
   `m_avm_read_o` is cleared.
3. The command FIFO at `avm_fifo.vhd:80-105` is reset by `s_rst_i`, which is
   `qnice_rst`. Its contents are not reset by `hr_rst`.
4. The response FIFO at `avm_fifo.vhd:107-130` is independently reset by
   `m_rst_i`, which is `hr_rst`.
5. A short MEGA65 reset asserts `hr_rst` while QNICE remains running. The
   HyperRAM configuration layer holds downstream `waitrequest` high until it
   is ready again (`hyperram_config.vhd:136-144`). The original command can
   therefore remain queued throughout the reset.
6. The watchdog sees `reading=1` and no immediate source request, assumes the
   response was lost, and adds another copy of the same read. Repetition can
   fill the 16-entry command FIFO, with another retry held at its input.

The reset manager guarantees at least a 50 ms core reset
(`M2M/vhdl/reset_manager.vhd:37-40,65-86`), long enough for roughly 76
watchdog intervals. After `hr_rst` releases, the queued copies execute and
produce multiple untagged responses. The first response releases the original
QNICE bus cycle. A later duplicate can arrive after QNICE starts a new read;
`qnice2hyperram.vhd:89-92` accepts any `readdatavalid` and clears `reading`, so
the later access can complete with data from the old address.

The one-cycle `m_avm_readdatavalid_d` guard does not identify, count, or drain
duplicate responses. The entity-header statement that the CPU never observes
wrong data is therefore not guaranteed by the implementation.

This applies to all four uses of the bridge in this design: the framework
HyperRAM window, CRT staging, and the two mount-buffer wrappers.

This is a protocol-level finding from static analysis, not a hardware
reproduction. It nevertheless needs a targeted simulation before release. A
passing test must hold `hr_rst` for the real reset duration with an original
read already queued, then prove:

* exactly one downstream execution and one upstream completion for that read;
* no response remains after the QNICE cycle completes; and
* a following read from a distinct address returns the distinct value.

A robust solution needs a reset epoch/flush handshake or another way to know
whether the command is still queued. Periodic retry behind an opaque FIFO is
not sufficient.

### F2 -- High: reset and disk writes are not transactional

This finding confirms the severe open items already listed in
`doc/mh_dev_drives.md:214-225`.

#### In-flight drive write

`M2M/rom/shell.asm:1100-1176` implements `HANDLE_DRV_WR` as a byte-by-byte copy
from the drive transfer buffer into the HyperRAM image. The cache becomes
dirty only when the full transfer is acknowledged
(`M2M/vhdl/vdrives.vhd:518-526`). Before that ACK, `prevent_reset` can still be
clear.

If a core reset arrives in that interval, `vdrives.vhd:398-430` clears the
shared buffer address/data/ACK registers. The QNICE CPU is a separate domain
and can still be executing the Assembly copy loop. For a keep-mounted drive,
the partially changed HyperRAM cache remains the mounted image. There is no
transaction marker, rollback, full-block retry, or integrity check.

#### Short physical reset versus Shell soft reset

The two reset paths are materially different:

* `RESET_CORE` in `CORE/m2m-rom/m2m-rom.asm:652-674` resets the C64 only and
  deliberately leaves HyperRAM and the video pipeline alone.
* A short physical reset-button press drives the framework's raw
  `reset_core_n`, which is included in the `hr_rst` equation in
  `M2M/vhdl/clk_m2m.vhd:190-203`.

The dirty-cache guard in `CORE/vhdl/main.vhd:854-966` can suppress the reset
inside the C64 core, but it cannot prevent that framework-level HyperRAM
reset. Thus the engine and cache bookkeeping may continue while their memory
transport is reset underneath them. F1 then applies to in-flight reads.

HyperRAM writes are posted into the command FIFO and have no completion
response. A write which has already left that FIFO but has not completed when
`hr_rst` arrives cannot be detected or retried by the read watchdog.

#### Hard reset during flush

`FLUSH_CACHE` in `M2M/rom/shell.asm:1205-1371` seeks to byte zero and
progressively overwrites the live SD-card file. A hard reset deliberately
bypasses `prevent_reset`; if it interrupts this loop, the on-card file contains
an arbitrary completed prefix followed by old contents. There is no temporary
file, journal, rename-on-success, or recovery record.

The hardware test "hammer reset during LOAD/SAVE" may demonstrate that the
Shell no longer freezes, but it cannot establish data integrity unless every
resulting cache and SD image is also compared byte-for-byte.

### F3 -- Medium: live status uses global image activity

The mode-change gate is correctly scoped to the drive being changed:
`CORE/m2m-rom/m2m-rom.asm:1044-1099` selects `P1581_IMGBSY_D8` or
`P1581_IMGBSY_D9`.

The visible status classifier at `m2m-rom.asm:933-955` instead masks
`P1581_IMGBSY_ANY`. With the default setup (drive 8 image-backed, drive 9
Internal 1581), activity or dirty data on drive 8 can make the menu display
`9:Internal 1581 Busy` while the physical mechanism is idle.

This is a common diagnostic/UI error, not a drive-selection or data-integrity
error. Physical read/head/motor status still has precedence, and the actual
idle gate remains per-drive.

### F4 -- Medium framework ripple: the dependency-aware boot height is not a safe bound

The boot-time height check combines three operations:

1. `M2M/rom/menu_struct.asm:215-281` finds the structurally largest view.
2. `M2M/rom/optm_deps.asm:524-669` sums guaranteed-hidden dependent lines
   globally across all mothers and all views.
3. `M2M/rom/options.asm:658-695` subtracts that global sum from the one
   structurally largest view before deciding whether to warn.

This is explicitly described as an under-approximation, but an overflow
detector needs an upper bound. For example, if view A has 30 lines and no
dependencies while smaller view B has one guaranteed-hidden dependent line,
the calculation reports 29 for view A and can suppress a real overflow
warning.

The current C64 menu is protected by the exact per-view model in
`menu_test.py verify`, which confirms a maximum visible height of 29. The
runtime framework check is nevertheless unsafe for another core or a future
menu whose dependency placement differs. It should not be upstreamed as a
general safety check without per-view accounting.

### F5 -- Low: corrupt dual-Internal configuration is only physically normalized

The Shell prevents both drives from selecting Internal 1581, and
`CORE/vhdl/main.vhd:1912-1925` provides a one-hot hardware guard. This safely
prevents both engines from controlling the physical mechanism.

However, `iec_drives_reset` at `main.vhd:1894-1902` is computed from the raw
mode bits. In a corrupt configuration, both raw Internal bits therefore
release their drive engines. Only the winning drive receives
`physical_mode=1`. The losing engine can run as an unmounted 1541 or according
to its previously latched image type rather than being normalized to Off or If
mounted.

This is not physical-mechanism contention, and the versioned A20 config makes
it unlikely in normal use. It is still a mismatch between the recovery comment,
the displayed configuration, and actual IEC behavior.

### F6 -- Low/latent: the HyperRAM map assertion covers one framebuffer only

The new assertion in `CORE/vhdl/mega65.vhd:576-585` checks that
`2**ceil(log2(VGA_DX*VGA_DY*3))` fits below `C_HMAP_CRT`. ASCAL documents
`RAMSIZE` as the allocation for one framebuffer and says triple buffering
requires three times that amount (`M2M/vhdl/av_pipeline/ascal.vhd:88-98`).

Current C64 filter table entries write only ASCAL modes 0 through 4, leaving
the triple-buffer bit clear, so the present A20 configuration fits in the 3 MB
M2M region. A future triple-buffer option could overlap the CRT region while
the assertion still passes. The assertion should eventually include the
selected buffering mode or the framework should own a complete memory-budget
check.

### F7 -- Low/residual: idle detection partly relies on the emulated LED

`CORE/vhdl/main.vhd:871-889` defines image activity as the drive LED while not
in physical mode, OR the per-drive dirty flag. The SD transfer activity used by
the standard drive engines makes this conservative for ordinary DOS paths, and
dirty data remains protected after ACK.

The LED is partly software-controlled drive behavior, however. A custom drive
ROM or unusual fastloader can conceivably be active on IEC with its activity
LED off between transfers. A source-mode change in that window could abort an
operation even though no dirty data is lost. This is a residual compatibility
risk rather than a demonstrated failure.

### F8 -- Low: new physical-drive selection logic lacks dynamic coverage

The static structure of the physical path is sound:

* `c1581_multi.sv` updates every per-drive previous-toggle tracker continuously
  and flips the exported toggle only for a real event from the selected drive;
* `main.vhd` forces an all-zero physical-mode interval for 255 main-clock
  cycles on every selection change; and
* the controller is disabled and re-armed during that interval.

The existing `tb_fdc1772_physical.sv` tests the FDC delivery protocol, not the
two-drive selector, toggle re-encoders, one-hot recovery, or switch sequencer.
The documented stale FDC state after a mid-operation mode excursion therefore
remains, as does the approximately 8 microsecond inert 1541 wake-up during the
selection gap.

## Code paths traced and assessed

| Path | Result |
| --- | --- |
| Config text/groups/dependencies -> QNICE heap -> resolved selection | Correct for the current menu; raw/resolved format-2 masks, validator rules, and hidden initial-cursor normalization agree |
| `OSM_SEL_PRE` idle gate -> forced revert or clear-before-set steal -> framework CFM copy | Correctly ordered; the callback sees the old selection and can revert before hardware bits change |
| CFM bits -> `mega65.vhd` decode -> CDC -> `main.vhd drive_mode_i` | Correct two-bit-per-drive mapping |
| Mode decode -> per-drive reset -> `iec_drive` 1541/1581 selector | Correct for all four normal modes and both drives |
| Shell mount/file handles -> `vdrives` MMIO -> mount-buffer HyperRAM regions | Correct device indexing, handles, 4 KB windows, byte lanes, and serialized shared `img_size/img_type` strobes |
| `sd_lba/sd_blk_cnt/sd_buff` mixed-language arrays | Corrected ascending SV-bound signals plus per-element copies prevent drive 8/9 reversal |
| Physical 1581 owner -> selector -> controller/FIFO -> mechanism pins | Correct one-hot physical ownership in normal operation; toggle re-encoding is logically phantom-free |
| Reset-unmount -> size-zero `img_mounted` strobe -> drive engines | Correct; consumers latch the unmount notification even around their reset interval, so the ghost-disk fix is viable |
| QNICE read/write -> CDC FIFO -> HyperRAM | Normal path is coherent; reset recovery has F1/F2 hazards |
| HyperRAM map and four-master arbiter | Current regions are linear, guarded, and non-overlapping; request/response vector ordering is correct |

## Framework fixes reviewed

The following fixes are mechanically correct, and no consumer was found that
depends on the previous behavior:

* **#52:** clearing R9 with `XOR R9,R9` correctly deasserts the virtual-drive
  track-buffer WREN; the previous `XOR 0,R9` was a no-op.
* **#58:** moving the `ROSM_SAVE` loop counter out of clobbered R8 fixes the
  multi-drive save loop.
* **#57:** explicit per-element copies preserve unpacked-array indices across
  the VHDL/SystemVerilog boundary.
* **#73:** widening the corrected block count to seven bits represents the
  encoded maximum of 63 plus one, i.e. 64 blocks / 16 KiB.
* Initializing the `gencfg.asm` system-start register removes reliance on
  banked-register residue.
* All inspected `sd_buff_wr` consumers are ACK-scoped, idempotent RAM writes;
  deasserting the previously stuck WREN does not remove a required write.

The `vdrives` optional-port defaults preserve behavior for existing
single-drive framework users. The dependency format probe also preserves the
no-dependency/older configuration paths tested by the emulator suite. F1 and
F4 are the two framework changes which should be reconsidered before general
upstream adoption.

## Verification performed in the disposable clone

* `python3 M2M/rom/tests/menu_test.py verify`: passed; `OPTM_SIZE=190`,
  `OPTM_DY=29`, 11 regions, 65 generated C_MENU constants, and all 16 VHDL
  decoder vectors matched.
* `menu_test.py run`: all five emulator programs passed (`menu_struct`,
  `menu_equiv`, `menu_nav`, `optm_deps`, and `optm_live`).
* Mutation suite: all 19 mutants were rejected. On macOS the harness needed a
  harmless temporary `pbcopy` substitute because the assembler wrapper treats
  a failed final clipboard copy as a command failure.
* Full `CORE/m2m-rom/make_rom.sh`: assembled successfully, using 28,546 of
  28,672 ROM words and leaving 126 words free.
* The ROM build reports two C-preprocessor warnings from apostrophes in
  comments at `CORE/m2m-rom/m2m-rom.asm:1072` and `:1078`, contrary to the
  project Assembly-comment convention. They do not change the output.
* `tb_fdc1772_physical.sv`: all 13 CRC-gated physical-delivery checks passed.
  Its scope limitation is described in F8.
* A whole-module local Icarus parse could not reproduce the handover's clean
  result because the installed Icarus version rejects the pre-existing
  forward `N`/`NDR` localparams used in ANSI port dimensions. Vivado accepts
  this established source pattern, so this was not classified as an A20
  regression.
* No Vivado run was started or disturbed. R3 timing closure and the hardware
  tests remain external release gates.

## Recommended release gates

1. Add a reset-aware `qnice2hyperram` plus `avm_fifo` test which proves exactly
   one command/response across a realistic 50 ms `hr_rst`, including the
   queued-command, accepted-command, lost-response, and response-at-reset-edge
   cases.
2. Inject reset at every byte position of `HANDLE_DRV_WR`; after recovery,
   compare the complete mounted cache and the eventual SD image against the
   expected image.
3. Inject hard reset throughout `FLUSH_CACHE` and either define the resulting
   image loss as accepted behavior very visibly or add an atomic recovery
   mechanism.
4. Add a selector-level test covering opposite parked toggle parity, drive
   8-to-9 and 9-to-8 steals, a corrupt both-Internal configuration, no phantom
   read/step/cancel requests, and the all-zero controller re-arm interval.
5. Make the live status classifier use the selected physical drive's image
   busy bit, matching the already-correct idle gate.
6. Replace the global dependency-height subtraction with an exact per-view
   maximum before upstreaming it as a generic framework safety check.
7. Require the pending R3 implementation to close timing, then run the full
   WIP-V6-A20 hardware gate with byte-for-byte image validation after reset
   stress.
