# Magic Formel — SIMCRT Support: status, implementation, next steps

Working brief for branch `mh_fix_issue_212` (issue #212). This file is intended to be loaded into a fresh Claude session **after** `CLAUDE.md` has been auto-loaded — it gives Claude the Magic-Formel-specific context that `CLAUDE.md` deliberately does not.

The earlier version of this file was a *planning* brief written before any code existed. This version is a *status* brief: what has been implemented, what has been tested on hardware, and what is still open.

---

## 1. TL;DR / current state

- Branch: `mh_fix_issue_212` (one WIP commit `0bdf067 "WIP SIMCRT: Support Magic Formel freezer cartridge (issue #212)"`, plus uncommitted refinements in the working tree).
- Files touched: `CORE/vhdl/cartridge.vhd`, `CORE/vhdl/sw_cartridge_wrapper.vhd`, `CORE/vhdl/main.vhd`, `CORE/vhdl/config.vhd`.
- A `when 14 =>` branch exists in `cartridge.vhd` with: a minimal MC6821 PIA model (PRA/DDRA/CRA + PRB/DDRB/CRB + CB2 + CB2state for STROBE_E), the `mf_kernal_enabled` / `mf_freeze_enabled` / `mf_io1_enabled` / `mf_ram_page` side-effect state, hwversion-derived bank mask (V1 / V2 / V2E), V2-only bank-12..15 → 8..11 mirror, NoCart-dormant mode, freeze-aware reset.
- 8 KB SRAM at IO1 (`$DE00–$DEFF` paged) is delivered through the existing `cartridge_ram` 32 KB block; on cart attach it is primed with the VICE `ramparam` pattern (4-byte FF/00/00/FF, XOR-flipped per 256 B block) by `mf_fill_active` in `sw_cartridge_wrapper.vhd`.
- **Latest hardware test (on real MEGA65), V2 `.crt`:**
  - **Cold-boot:** screen shows `READY.` with a blinking cursor — but the standard C64 BASIC banner (`**** COMMODORE 64 BASIC V2 **** / 64K RAM SYSTEM 38911 BASIC BYTES FREE`) is **missing**. Just `READY.` at the top of an otherwise empty screen, cursor on the line below.
  - **Soft reset (MEGA65 reset button) from that state:** the screen goes blue-on-blue (frame colour = background colour, no characters visible) and the system **locks up**.
  - User has **not** pressed RESTORE yet.
- This is progress over earlier black-screen / lockup, but it is **NOT clean**. The missing BASIC banner and the soft-reset lockup are both anomalies that point at remaining bugs in our `cartridge.vhd` `when 14 =>` implementation, not at "stealth cart, behaves correctly". See §5 for the working hypotheses and §6 for what to test next.
- One known unimplemented feature carried over from before the test: **mf-windows** passthrough (VICE's `mem_read_without_ultimax` in `magicformel_romh_read`). Most likely affects MF's "memory inspect" feature in the freezer menu but not the freeze→save→thaw flow itself. See §7.

---

## 2. What Magic Formel is (compressed background)

German freezer / utility cartridge by Roßmöller, late 1980s. Three known revisions covered by VICE: V1.2 (8 ROM chips = 64 KB), V2 (12 chips = 96 KB), V2.0E "Mini-Format" (16 chips = 128 KB). VICE's `magicformel_crt_attach` derives `hwversion` from the chip count: 8 → hw0 (bank mask `0x07`), 12 → hw1 (bank mask `0x0f`, plus a 12..15→8..11 mirror in raw ROM), 16 → hw2 (bank mask `0x0f`, no mirror).

CRT type ID: **14**.

### 2.1 Hardware (per VICE + c64-wiki schematic)

| Part        | Role                                                            |
| ----------- | --------------------------------------------------------------- |
| 27256 / 27512 / 271001 EPROM | 32 / 64 / 128 KB, 8 KB banks at $E000 (Ultimax) |
| MC6821 PIA  | Acts as bank/mode controller and freeze-button latch            |
| 8 KB SRAM   | Paged into `$DE00–$DEFF` via PA4 inverted (= mf_io1_enabled)    |
| 7430 + glue | Address decode and EXROM/GAME generation                        |

### 2.2 Address-as-data trick

PIA writes are at IO2 (`$DFxx`). The PIA byte is reconstructed from the address bus and one CPU data bit:

```
RS = addr(7..6)                     -- which PIA register
data = (addr & 0x3f) | ((D & 2) << 6)   -- D5..D0 from addr, D7 from CPU D1, D6=0
```

The cart firmware bank-switches by *executing* a load instruction whose *operand address* encodes the desired register/value. The CPU read of `$DFxx` strobes the PIA in our model too — see `mf_pia_window` in `cartridge.vhd`.

### 2.3 Freeze flop (VICE `freeze_flipflop`)

Three inputs: `reset`, `clear`, `freeze`. Truth table:

| reset | clear | freeze | freeze_enabled (out) |
| ----- | ----- | ------ | -------------------- |
| 1     | x     | x      | 1                    |
| 0     | 1     | x      | 0                    |
| 0     | 0     | 1      | 1                    |
| 0     | 0     | 0      | unchanged            |

`magicformel_freeze` calls `(reset=0, freeze=1, clear=CB2)`. CB2 must be 0 for freeze to actually latch. `magicformel_config_init` (after attach) calls `(reset=1)` → forces freeze=1. CPU reset path does **not** call `freeze_flipflop`, i.e. freeze survives a soft reset.

### 2.4 PA / PB bit assignments (VICE `mf_set_pa` / `mf_set_pb`)

PA write:
- bits 0..3 = ROM bank (`hwversion==0` masks to 3 bits, else 4 bits)
- bit 4 inverted = `io1_enabled` (= "8 KB SRAM paged at $DE00")
- bits 5..7 unused

PB write:
- bit 7 = `kernal_enabled` (cart visible in Ultimax)
- bits 0..4 mapped through `(B3, B2, B0, B1, B4)` → `ram_page[4..0]` (selects which 256 B page of SRAM is visible at $DE00)

(Our VHDL implements both maps verbatim — see `cartridge.vhd:367-413`.)

---

## 3. Current implementation — file-by-file

Branch state in working tree.

### 3.1 `CORE/vhdl/cartridge.vhd`

The bulk of the work. Around line 337 (`when 14 =>`):

**State signals** (lines ~74-108):

| Signal                | Purpose |
| --------------------- | ------- |
| `mf_pia_window`       | `iof_i and wr_en_i` — selects PIA latch on `$DFxx` writes |
| `mf_data`             | Reconstructed PIA byte: `D7=wr_data_i(1)`, `D6=0`, `D5..D0=addr_i(5..0)` |
| `mf_pra/ddra/cra`     | PIA Port A registers |
| `mf_prb/ddrb/crb`     | PIA Port B registers |
| `mf_cb2`              | PIA CB2 line (controls freeze) |
| `mf_cb2state`         | CRB STROBE_E mode armed → next PB write strobes CB2 0→1→0 |
| `mf_io1_enabled`      | PA4 inverted: 8 KB SRAM paged at `$DE00` |
| `mf_kernal_enabled`   | PB7: cart visible in Ultimax |
| `mf_freeze_enabled`   | Latched on freeze press, cleared on CB2=1 |
| `mf_ram_page`         | 5-bit page index into 8 KB SRAM (32 pages of 256 B) |
| `mf_bank_mask`        | 7-bit ROM-bank mask (`0x07` for V1, `0x0f` for V2 / V2E) |
| `mf_v2_mirror`        | V2 only: combinational remap of bank 12..15 → 8..11 |
| `mf_bank_remap`       | Combinational `mf_data(3:0)` after V2 mirror |

**Behaviour (per write to `$DFxx`)** dispatches on `addr(7..6)` (PIA register select):

- `00 = PRA / DDRA`: if `CRA(2)=1` latch `mf_pra` and update bank/io1 side-effects; else latch `mf_ddra`.
- `01 = CRA`: latch only.
- `10 = PRB / DDRB`: if `CRB(2)=1` latch `mf_prb`, update `mf_ram_page` (with bit-remap), update `mf_kernal_enabled`. If `mf_cb2state=1`, this PB write strobes CB2 0→1→0 and clears `mf_freeze_enabled`. Else latch `mf_ddrb`.
- `11 = CRB`: latch and decode CB2 control mode bits 5..3:
  - `1xx, 1` (immediate-update modes): drive CB2 to bit3, clear freeze if CB2=1, clear `mf_cb2state`.
  - `101` (STROBE_E / "set on next PB write"): arm `mf_cb2state`.

**Read of `$DFxx`** (lines 455-473): drives `io_ext_o='1'` and returns the PIA register selected by `addr(7..6)`. PIA reads return `(data & ddr) | (~ddr)` — VICE's `mc6821core_read` with no `get_pa/get_pb` callback returns `0xFF` on input bits, so unconnected bits read back as `'1'`. Returning `0` on input bits would cause the firmware's "is this Magic Formel?" probe to fail.

**Bank assignments to `bank_lo_o` / `bank_hi_o`** (lines 370-371): `mf_bank_mask AND ("000" & mf_bank_remap)`. The mask zeros high bits per hwversion; the remap zeros bit 2 when V2-mirror+bit3 forces bank 12..15 down to 8..11. `bank_lo_o` and `bank_hi_o` get the same value (Magic Formel banks the entire ROM window together).

**EXROM/GAME** (lines 483-489):
- `kernal_enabled OR freeze_enabled` → `exrom=1, game=0` = Ultimax.
- else → `exrom=1, game=1` = NoCart (dormant, BASIC + KERNAL ROMs intact).

**`cart_loading_i` block** (lines 491-543): replicates VICE's "attach + first machine reset" chain. Final state: `kernal=0`, `freeze=1`, `io1=1`, `CB2=0`, all PIA regs zero, Ultimax selected. The bank mask is set here from `cart_size_i`:

```
< 80 KiB   → V1  (mask 0x07, no mirror)    matches  65728 B / 8 chips
< 112 KiB  → V2  (mask 0x0f, mirror=1)     matches  98656 B / 12 chips
otherwise  → V2E (mask 0x0f, no mirror)    matches 131584 B / 16 chips
```

(Each 8 KB CHIP packet is `0x10 + 0x2000 = 0x2010` bytes; CRT header is `0x40` bytes. Thresholds at 80 / 112 KiB cleanly separate the three.)

**`freeze_crt = '1'` block** (lines 545-569): implements `magicformel_freeze`. Sets `io1_enabled=1`, `kernal_enabled=1`, `bank_lo/hi=1`, Ultimax. Latches `mf_freeze_enabled` only if `mf_cb2=0` (mirrors VICE's flop with `clear=CB2`). Does **not** touch any PIA register — VICE doesn't either.

**`rst_i` block** (lines 772-823): zero PIA, zero kernal/ram_page, set `io1_enabled=1`, `mf_cb2=0`. Crucially **does not clear `mf_freeze_enabled`** — this matches VICE's `magicformel_reset` (which never calls `freeze_flipflop`). For `cart_id_i=x"000E"` overrides the global `exrom=1, game=1` default with the freeze-aware mux.

### 3.2 `CORE/vhdl/sw_cartridge_wrapper.vhd`

Two additions vs. master:

1. **Magic Formel SRAM prime** (lines 459-498): on transition `main_resp_status` → `C_STAT_READY` and `main_id = x"000E"`, kick off `mf_fill_active`. Walks 8 KiB of `cart_ram` writing `0xFF` when `(addr(1) XOR addr(0) XOR addr(8)) = 0` else `0x00`. Collapses VICE's `ramparam {start=0xff, value_invert=2, value_offset=1, pattern_invert=0x100}` into a single XOR formula (verified against `/tmp/vice_mf/ram.c`). The fill pulses `main_reset_core_o` until done so the C64 can't sample the SRAM mid-prime.
2. **`mf_fill_*` write port** into `cart_ram` (port B at lines 620-622 of the `cart_ram` instantiation).

### 3.3 `CORE/vhdl/main.vhd`

Wires `cart_size_i` from the parser into `cartridge_inst`. No other functional changes for MF.

### 3.4 `CORE/vhdl/config.vhd`

(Touched, presumably for the OSM entry that lists Magic Formel as a supported `.crt` type. Not central to the runtime behaviour.)

---

## 4. Latest hardware-test result — full detail

**Test:** load the V2 Magic Formel `.crt` via the OSM's CRT mount on a real MEGA65, branch `mh_fix_issue_212` working tree.

**History of this test on the same branch:**
1. Initial code: machine **locked up** after CRT load.
2. After PIA fixes but before D4 (NoCart dormant mode): **black screen** after CRT load (BASIC ROM was hidden because the dormant state was incorrectly set to CMODE_16KGAME = `exrom=0/game=0`).
3. **Current state** (D1–D6 + threshold fix + V2-mirror): partial-but-imperfect cold boot, soft-reset lockup. Two observations:

**Observation 4.1 — cold boot ends at "READY." with no banner.** What we see on screen after the CRT loads:

```
                                       <- (blank top portion of screen)

READY.
█                                      <- (blinking cursor, line below)
```

What we should see on a normal C64 cold boot:

```
    **** COMMODORE 64 BASIC V2 ****

 64K RAM SYSTEM  38911 BASIC BYTES FREE

READY.
█
```

So the BASIC banner and the "BYTES FREE" line are **missing**. The cursor is responsive (it blinks) — this is not a hung CPU.

**Observation 4.2 — soft reset locks up.** Pressing the MEGA65 reset button (= soft reset of the C64) from the `READY.` state above produces a **blue-on-blue empty screen** (frame colour and background colour both blue, no characters) and the system is **wedged** — nothing on the keyboard responds.

**RESTORE has NOT been tested yet** — that test (per §7.2) is still the gating one.

---

## 5. Open question: what *should* we see after a SIMCRT load?

This is genuinely unresolved and the previous version of this file glossed over it. The user raised it during wrap-up and is right to flag it.

**The mechanics on our side:**

`sw_cartridge_wrapper.vhd` pulses a soft reset of the C64 once `main_resp_status = C_STAT_READY` (i.e. the `.crt` parsed successfully and the bank cache is being primed). For Magic Formel we *also* hold reset for the duration of the 8 KB SRAM prime (`mf_fill_active`). So when the C64 finally comes out of reset, it does so with:

- `mf_freeze_enabled = 1` (set by the `cart_loading_i` block — matches VICE's `magicformel_config_init`).
- `mf_kernal_enabled = 0`, banks=0, SRAM primed with the FF/00 pattern.
- EXROM=1, GAME=0 → **Ultimax**.
- → CPU's first instruction fetch at `$FFFC/$FFFD` lands in **MF cart bank 0 ROMH**, not the C64 KERNAL.

**So yes, we DO expect the cart to "start"** in the sense that bank 0 firmware runs at the very first cycle after reset release. That is what the post-load reset is for, and that is what our `cart_loading_i` setup is designed to produce. The question is **what the firmware does next**, and **what should be visible on screen as a result.**

**Plausible outcomes — we don't yet know which is right:**

| # | Outcome on screen                                          | What it would imply                                                                                              |
| - | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| A | Magic Formel shows its own splash / menu / banner         | MF firmware is "loud" on cold-boot, like AR or FC-III. Our partial `READY.` would then be a **clear bug** (bank 0 firmware running but mis-rendering its own output). |
| B | Full standard C64 BASIC banner + `BYTES FREE` + `READY.`  | MF firmware is "stealth": runs, hands off to BASIC's full reset path, then dies invisibly. Our partial `READY.` would still be a **bug** (banner suppressed). |
| C | Just `READY.` with no banner (what we currently see)      | MF firmware actively skips BASIC's banner-print on its way into the idle loop. Our impl might be correct or partly wrong. |
| D | Black screen / lockup                                     | Cart starts but firmware can't complete its handoff. (This was earlier branch state — we've moved past it.)      |

I previously asserted (C) was "correct stealth-cart behaviour" based on web research. **That was speculative.** The honest answer is: I don't know which of A / B / C is the documented Magic Formel cold-boot behaviour, and the public sources I found (c64-wiki, rr/pokefinder) don't make it explicit either. The earliest sentence to retract is "READY + blinking cursor is the correct cold-boot behaviour" — that should read **"is one of three plausible behaviours; we have not yet established which."**

**The only cheap way to settle this is VICE-on-PC with the same `.crt`** — see §7.1. If VICE shows (A), we have a banner-display bug. If VICE shows (B), we have a banner-suppress bug. If VICE shows (C), our cold-boot path is probably correct and we move on to the soft-reset lockup. If VICE shows (D), the `.crt` itself or our hwversion classification is suspect.

---

## 6. Working hypotheses for the two anomalies

These are *hypotheses* — not conclusions. The next session should treat them as starting points to investigate, not as a checklist of fixes to apply blindly.

### 6.1 Why no BASIC banner on cold boot?

On cold-boot, our `cart_loading_i` path leaves the cart in the same state VICE's `magicformel_config_init` produces: `freeze_enabled=1`, `kernal_enabled=0`, banks=0, **Ultimax**. The C64 then comes out of reset in Ultimax — which means the very first instruction fetch at `$FFFC/$FFFD` goes to **MF cart bank 0 ROMH**, *not* the C64 KERNAL.

So MF firmware bank 0 IS running at cold-boot before the C64 KERNAL. To then hand off to BASIC, MF firmware must:

1. Write the PIA to clear `freeze_enabled` (via a CB2 strobe — STROBE_E or SET_C2 mode on CRB) and clear `kernal_enabled` (PB7=0). This drops the cart to NoCart and uncovers BASIC + KERNAL ROMs.
2. Continue execution into the C64 startup.

If MF firmware skipped BASIC's banner-printing path on its way into BASIC's idle loop, that explains "no banner, just READY.". This is **plausible MF behaviour** (a "fast cold-start") but it is also **plausible that our impl is wrong** in a way that misleads MF firmware to skip the banner.

**Probable contributing impl issues to investigate first:**

- **Bank 0 ROML contents are garbage** in our setup. MF V2 `.crt` files declare CHIP packets at `$E000` (Ultimax), so `crt_cacher` only writes `hibanks[N]` and **never** writes `lobanks[N]`. Default `lobanks[0]=0` points to HyperRAM offset 0 — the .crt header bytes. If MF firmware ever reads `$8000–$9FFF` while in Ultimax (e.g. wild branch, stack push misalignment, or a deliberate sanity check), it gets `"C64 CARTRIDGE   "` ASCII as code. Should not happen on a clean firmware path, but worth eliminating: mirror `hibanks[N]` to `lobanks[N]` for cart_id=14 in `crt_cacher.vhd`, or assert that MF firmware never touches ROML.
- **CB2 strobe handling for non-STROBE_E modes is incomplete.** Our CRB-write code (`cartridge.vhd` ~lines 418-438) decodes only:
  - `CRB[5,4,3] = 1,1,1` (SET_C2)   → CB2=1, freeze cleared.
  - `CRB[5,4,3] = 1,1,0` (RESET_C2) → CB2=0.
  - `CRB[5,4,3] = 1,0,1` (STROBE_E) → arms `mf_cb2state`.
  - **Other CRB[5]=1 modes** (`1,0,0` STROBE_C) and **all CRB[5]=0 modes** (CB2 input modes) currently do nothing. Real MC6821 has well-defined CB2 transitions when entering / leaving these modes. If MF firmware uses STROBE_C, or relies on an automatic CB2 default when reconfiguring, our impl misses the CB2 edge that clears the freeze flop. Symptom: cart-stays-in-Ultimax-longer-than-expected during the cold-boot handoff. Worth a focused trace against `/tmp/vice_mf/mc6821core.c` (or its mirror).
- **DDR-mode side-effect updates.** Our PRA/PRB write code only updates side-effects (`bank_lo/hi`, `mf_io1_enabled`, `mf_ram_page`, `mf_kernal_enabled`) when `CR(2)=1` (PR-mode select). VICE matches this in `mc6821core_store`, but VICE *also* re-fires the `mf_set_pa/pb` callbacks on `mc6821core_reset()` — i.e. the side-effects are recomputed from `dataA/dataB` even after a CR-only write. We do this in `cart_loading_i` but **not** on a generic CR-only write. If MF firmware writes CRA before PRA ever lands, the bank/io1 derivation lags. Audit needed.

**Cross-check with VICE-on-PC:** load the same V2 `.crt` in VICE on PC. Does VICE show the full banner + BYTES FREE on cold-boot, or also just "READY."? **This is the single highest-value next experiment — it pins down whether the missing banner is "normal MF behaviour" or "our bug".**

### 6.2 Why does soft reset lock up?

After the cold-boot handoff, MF firmware has cleared `freeze_enabled` (so the cart is dormant — NoCart mode, BASIC + KERNAL visible, MF firmware *not* visible at `$E000+`). Our `rst_i` block in `cartridge.vhd` (lines 772-823) deliberately does **not** clear `mf_freeze_enabled` on soft reset — this matches VICE's `magicformel_reset` (which never calls `freeze_flipflop`).

So at the moment of soft reset, with our impl:
- `mf_freeze_enabled = 0` (was cleared by firmware after cold boot).
- `mf_kernal_enabled = 0` (zeroed by `rst_i`).
- Banks `= 0`.
- Cart-id=14 path in `rst_i` reads `mf_freeze_enabled=0` → selects NoCart (`exrom=1, game=1`).
- C64 KERNAL is visible at `$E000+`. CPU fetches `$FFFC/$FFFD` → KERNAL `RESET` routine runs.
- KERNAL clears RAM and walks through its standard reset chain.

That should boot to a normal BASIC banner + READY. It does not — it locks up to blue-on-blue.

**Probable causes to investigate:**

- **The `$0318/$0319` RAM-based RESET vector.** MF firmware almost certainly patches the C64's IRQ/NMI/RESET vectors in low RAM during cold-boot init (so a future freeze press jumps to MF code). When the user soft-resets *while the cart is dormant*, the C64 KERNAL's reset chain runs, and at some point it **JMPs through the RAM-patched `$0318` vector** — but the cart is now invisible (NoCart), so the JMP target is "wherever MF firmware was loaded into RAM" or worse, into open / MF-SRAM-shadowed I/O space. Garbage → BRK loop → blue-on-blue.
- **Our `rst_i` block forces `ioe_ena=1, ioe_wr_ena_o=1` for cart_id=14 unconditionally**, even when we just decided the cart is "NoCart" via the freeze-aware mux. So MF SRAM is **still paged into `$DE00`** after soft reset, presenting cart-state RAM where a real plug-pulled C64 would see open bus. KERNAL doesn't normally read `$DE00` during reset, but it is a divergence from "cart is gone" semantics. Worth re-checking.
- **8 KB SRAM contents survive soft reset** (correct per VICE). After cold-boot firmware ran, the SRAM holds whatever firmware put there. If firmware then patches a C64 RAM vector to point at SRAM, that vector now points at *cart SRAM* contents — which are invisible from `$0000-$BFFF/$C000-$CFFF` after soft reset (cart at `$DE00` only, not at the patched address). Same root cause as the first bullet, viewed from the SRAM side.
- **Hard reset would have handled it.** A hard reset (Ultimax + freeze=1 forced via `cart_loading_i`-equivalent) would re-arm the cart and the RAM vector chain would land back on cart code. That suggests one possible workaround: treat the MEGA65 reset button as hard-reset for cart_id=14. But that breaks "save-state and reset to thaw" workflows that rely on SRAM survival.

**Cross-check with VICE-on-PC:** in VICE, hit `Machine → Reset → Soft` after the same cold-boot. Does VICE behave the same (lock up) or boot cleanly? Again the highest-value experiment — distinguishes "intrinsic MF behaviour we have to live with" from "our bug".

---

## 7. What to test next (prioritised)

1. **VICE-on-PC parity check.** Mount the same V2 `.crt` in VICE (PC) and observe both cold-boot AND soft-reset behaviour on a known-good emulator. Two results to record: (a) which of §5's outcomes A/B/C/D appears at cold-boot, (b) what soft-reset from that state does. This is cheap, fast, and decides which §6 hypotheses are worth chasing. **Run this first** — it gates most of the work below.
2. **Press RESTORE on the MEGA65 from the partial `READY.` cold-boot state.** That is `freeze_key_i` for cart_id=14. On a 0→1 edge `cartridge.vhd` asserts `nmi_o`, the core takes an NMI, `freeze_crt='1'` latches `mf_freeze_enabled=1`, selects Ultimax, points at bank 1. The MF freezer menu should appear at `$E000+`.
   - **Pass:** an MF menu / monitor screen visible.
   - **Fail mode A:** nothing happens → `freeze_key_i` not edge-detecting, or `nmi_o` not propagating, or `mf_cb2 != 0` at freeze time so the flop doesn't latch.
   - **Fail mode B:** lockup similar to §4.2 → freeze latched but bank/Ultimax setup wrong.
3. **Investigate §6.1 anomalies in code** based on what VICE shows in step 1: ROML→ROMH mirror for MF, CB2 mode-decode coverage, DDR-mode side-effect refresh.
4. **Investigate §6.2 anomalies in code**: re-check `ioe_ena/ioe_wr_ena_o` semantics in NoCart mode for cart_id=14, audit the RAM-vector patching theory by reading bank 0 firmware (if a disassembly is available — check the rr/pokefinder wiki).
5. **Then resume the original plan** (exit-to-BASIC, freeze-save-thaw with SRAM, mf-windows menu features).

---

## 8. Known limitation: mf-windows passthrough

VICE's `magicformel_romh_read` (lines 481-487 in `/tmp/vice_mf/magicformel.c` or `temp_mh_fix_issue_212/magicformel.c`):

```c
uint8_t magicformel_romh_read(uint16_t addr)
{
    if (freeze_enabled && (addr >= 0xe000)) {
        return romh_banks[(romh_bank << 13) + (addr & 0x1fff)];
    }
    return mem_read_without_ultimax(addr);
}
```

When `kernal_enabled=1` AND `freeze_enabled=0` AND cart is in Ultimax (so the C64's KERNAL is normally hidden), reads from `$E000+` return **C64 RAM / KERNAL**, not cart ROM. This gives the MF menu a way to inspect the user's KERNAL ROM and pre-freeze RAM contents while still keeping cart ROM available everywhere else.

We currently do **not** implement this. The cart ROM bank is unconditionally returned via the bank cache when the C64 reads `$E000+` in Ultimax. Implementing it requires:

- a new signal `crt_ram_at_romh` (or similar) from `cartridge.vhd` to `main.vhd:cpu_data_in_proc`;
- the mux in `cpu_data_in_proc` would need a path that returns "what the C64 would see if Ultimax were *off*", i.e. KERNAL ROM at `$E000+` and C64 RAM where applicable. This is non-trivial because the MiSTer C64 PLA in `fpga64_buslogic.vhd` has already routed the access on the assumption that Ultimax is on.

Likely user-visible impact: the freezer's "view memory" / "monitor C64 RAM/KERNAL" feature shows wrong data. The freeze→save→thaw flow itself probably works fine because it operates on cart-internal SRAM, not on the mf-windows passthrough.

**Decision deferred** until §7.5 testing confirms whether this is actually felt in the menu.

---

## 9. Hallucination / bug-correction log (cumulative)

For honesty and to avoid re-introducing fixed bugs:

- ❌ **D1 — PIA touched on freeze.** Initially `freeze_crt` set `mf_pra <= x"01"`. VICE doesn't do that — it only updates side-effect state (`romh_bank`, `io1_enabled`, `kernal_enabled`). MF firmware reads PR back via `$DFxx` and would see garbage if we wrote it. Fixed.
- ❌ **D2 — PIA reads ignored DDR.** Initially returned `mf_pra` directly. Real 6821 returns `(data & ddr) | (input & ~ddr)`. MF doesn't register a `get_pa/pb`, so VICE substitutes `0xFF` on input bits — i.e. unconnected bits read as `'1'`. Returning `0` on input bits would break the cart's self-detection probe. Fixed: `(mf_pra and mf_ddra) or (not mf_ddra)` (and same for B).
- ❌ **D3 — CRB STROBE_E mode missing.** MF's freeze-clear path uses CRB[5,4,3]=`1,0,1` to arm a CB2 strobe that fires on the next PB write. We didn't implement the arming → freeze never cleared. Fixed: added `mf_cb2state` plus the strobe in the PB-DATA write branch.
- ❌ **D4 — Dormant mode hid BASIC ROM.** Initial dormant mode was `exrom=0, game=0` (CMODE_16KGAME), which hides BASIC at `$A000`. Result: black screen on cold boot. VICE's `change_config` "else" branch is mode `2 + (bank<<...)`, i.e. CMODE_RAM = `exrom=1, game=1` (NoCart). Fixed: dormant state is now NoCart; BASIC and KERNAL stay visible and cold boot reaches READY.
- ❌ **D5a — hwversion threshold off-by-one.** Initial threshold `cart_size_i <= 64*1024` (= 65536 B). V1 .crt is `0x40 + 8*0x2010 = 65728` bytes → just over 64 KiB → was misclassified as V2 and got the wrong bank mask. Fixed: thresholds at `< 80*1024` (V1) and `< 112*1024` (V2) match the actual file sizes (65728 / 98656 / 131584).
- ❌ **D5b — V2 bank-12..15 mirror missing.** VICE for hw1 (12 chips) does `memcpy(&rawcart[0x18000], &rawcart[0x10000], 0x8000)`, aliasing banks 12..15 to 8..11 in the raw ROM. Our HyperRAM staging doesn't replicate that copy; banks 12..15 would point to the .crt-header bytes (HyperRAM offset 0). Fixed via combinational `mf_bank_remap`: when `mf_v2_mirror=1` and `mf_data(3)=1`, force `mf_data(2)` to 0, collapsing 12..15 → 8..11.
- ❌ **D6 — `rst_i` block applied global default to cart_id=14.** The global default `exrom=1, game=1` (NoCart) was applied unconditionally at the bottom of the reset block, overriding any freeze-aware setup. Fixed: a `cart_id_i = x"000E"` override at the end re-applies Ultimax when `mf_freeze_enabled=1` (which survives soft reset, per VICE).
- ✅ **The original brief's claims about `m2m-rom`, the cart-id whitelist, and the framework-side NMI / freeze plumbing being missing are all *false*** (those were already in place; see prior version of this file in git for details). Only `cartridge.vhd` and `sw_cartridge_wrapper.vhd` (plus `main.vhd` for `cart_size_i` plumbing) needed code changes.

---

## 10. Open / unresolved (priority order)

1. **§5 — what's the expected on-screen result of the post-load reset?** This is now the most important open question. Resolve via the §7.1 VICE-on-PC parity test. Outcome decides whether §6.1 is even an "anomaly" or just MF behaving as designed.
2. **§7.2 RESTORE-press test.** Gating test for "cart works at all". Hardware test by user.
3. **§6.2 soft-reset lockup** root cause. Likely RAM-vector patching by bank 0 firmware while cart is dormant — but unconfirmed.
4. **§8 mf-windows.** Implement only if §7.5 testing shows broken menu behaviour that points at this path.
5. **DDR-mask side: should writes to PRA/PRB while `CRA(2)/CRB(2) = 0` (DDR mode) ALSO update side-effects?** VICE's mc6821core_store routes the byte to DDR or PR based on CR(2). Our implementation only updates side-effects in the PR-mode branch. Correct per VICE, but worth a sanity-check trace if MF firmware happens to write PR while CR(2)=0.
6. **CB2 mode-decode coverage** in CRB writes — currently STROBE_C and the CB2-input modes (`CRB[5]=0`) are no-ops. May be relevant to §6.1.
7. **CB2 reset behaviour during freeze.** VICE's flop has `clear=CB2`. We model this in `freeze_crt` but only sample `mf_cb2`, not edge-detect. If `mf_cb2` happens to be `1` *exactly* when RESTORE is pressed (rare but possible), the freeze won't latch. Probably benign because MF firmware drives CB2 low after every freeze handler completion. Watch for it on hardware.
8. **MF cart `.crt` files we don't have a sample for.** The VICE wiki page (https://rr.pokefinder.org/wiki/Magic_Formel) lists download links for V1 / V2 / V2E. Worth confirming all three classify correctly (especially V2E at 131 584 B).
9. **`cart_size_i` definition.** Currently used as the staged-file size to derive hwversion. Verify it includes the 0x40 CRT header. If it counts only CHIP-packet bytes the thresholds need shifting by 0x40.
10. **OSM "Magic Formel" label** in `config.vhd` — sanity check the user-visible string after the test passes.

---

## 11. Reference files (where to look)

- **VHDL implementation**: `CORE/vhdl/cartridge.vhd` (`when 14 =>` at line ~337, `rst_i` block ~772-823), `CORE/vhdl/sw_cartridge_wrapper.vhd` (`mf_fill_*` at ~459-498 and the `cart_ram` port B).
- **VICE source (authoritative spec)**: `temp_mh_fix_issue_212/magicformel.c` and `magicformel.h` (mirror of `/tmp/vice_mf/`). Also `/tmp/vice_mf/mc6821core.c` and `ram.c` for PIA core and RAM-pattern initialisation.
- **VICE upstream mirror (web)**: https://github.com/VICE-Team/svn-mirror/tree/main/vice/src/c64
- **C64-Wiki schematic / version overview**: https://www.c64-wiki.de/wiki/Magic_Formel
- **rr/pokefinder cart docs + .crt downloads**: https://rr.pokefinder.org/wiki/Magic_Formel
- **`temp_mh_fix_issue_212/Analyze deeper.md`**: pointer to the above three URLs.
- **CLAUDE.md**: project background, repository layout, SIMCRT pipeline overview (§4 in CLAUDE.md), reset semantics, debugging table.
