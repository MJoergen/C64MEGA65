# Resume prompt — Magic Formel SIMCRT (issue #212)

Copy-paste the block below into a fresh Claude Code session. `CLAUDE.md` is auto-loaded; this prompt instructs Claude to load `simcrt_magic_formel.md` next, summarises where we left off, and lays out the next investigation step.

---

```
Continue work on Magic Formel SIMCRT support, branch `mh_fix_issue_212`, issue #212.

CONTEXT
- CLAUDE.md is already loaded (project overview, SIMCRT pipeline, reset
  semantics — §4 of CLAUDE.md is the relevant section).
- Now ALSO load this file before doing anything else; it is the
  Magic-Formel-specific status brief and lists the eight fixes already
  applied (D1 through D6, plus D5a threshold and D5b V2-mirror), plus
  the open questions and hypotheses about the latest hardware test:
      temp_mh_fix_issue_212/simcrt_magic_formel.md
- VICE C reference (the authoritative spec we transcribed from):
      temp_mh_fix_issue_212/magicformel.c
      temp_mh_fix_issue_212/magicformel.h
  If you need the supporting VICE files (mc6821core.[ch], ram.c) and they
  are not in /tmp/vice_mf/ anymore, the upstream mirror is:
      https://github.com/VICE-Team/svn-mirror/tree/main/vice/src/c64

WHERE WE LEFT OFF (latest hardware test on real MEGA65, V2 .crt)
- Cold-boot reaches "READY." with a blinking cursor — BUT the standard
  C64 BASIC banner ("**** COMMODORE 64 BASIC V2 **** / 64K RAM SYSTEM
  38911 BASIC BYTES FREE") is MISSING. Just "READY." at the top of an
  otherwise empty screen, cursor on the line below.
- Pressing the MEGA65 reset button from that state produces a blue-on-
  blue empty screen and a hard lockup.
- RESTORE has NOT been tested yet.
- It is PROGRESS over earlier black-screen / lockup, but it is NOT
  clean. The previous wrap-up speculated that "READY without banner"
  is a stealth-cart feature; on reflection that was unfounded — see
  §5 of simcrt_magic_formel.md for the four plausible cold-boot
  outcomes (A/B/C/D) and why we cannot yet say which is correct.

OPEN QUESTION the user explicitly raised
  "Wouldn't we expect the cartridge to start? The CRT loader does a
   reset to start a cartridge after having loaded. What is the expected
   behaviour after the SIMCRT loading routines have completed?"

  The mechanics on our side: at the moment the C64 comes out of the
  post-load reset, our cart_loading_i path has set freeze_enabled=1,
  kernal_enabled=0, banks=0, EXROM=1/GAME=0 (Ultimax). So the very
  first $FFFC/$FFFD fetch goes to MF cart bank 0 ROMH — i.e. MF firmware
  IS running first, before the C64 KERNAL. What that firmware does
  next, and what should be visible on screen as a result, is what we
  don't know. §5 of simcrt_magic_formel.md lists the candidates.

NEXT STEPS — prioritised (from §7 of the brief)
1) HIGHEST VALUE: VICE-on-PC parity check. Mount the same V2 .crt in
   VICE on a PC. Record (a) what's on screen after VICE's auto-reset,
   (b) what soft-reset from that state does. This decides whether the
   cold-boot anomaly is a real bug, MF-intrinsic behaviour, or
   something else. Likely the user runs this — Claude can advise on
   command line / settings if asked.
2) Press RESTORE on the MEGA65 from the partial READY. state. RESTORE
   is wired as freeze_key_i for cart_id=14 (CORE/vhdl/main.vhd:~1124).
   On 0->1 edge cartridge.vhd's freeze_crt branch should:
     * latch mf_freeze_enabled=1 (gated by mf_cb2=0)
     * select Ultimax (exrom=1, game=0)
     * set bank_lo/hi=1
     * pulse nmi_o, OR'd into core_nmi_n at main.vhd:~965
   Expected: the MF freezer/menu screen appears at $E000+.
3) Once VICE results from (1) are in, work through §6.1 (no-banner)
   and §6.2 (soft-reset lockup) hypotheses in simcrt_magic_formel.md
   and decide what to fix. Likely candidates: ROML->ROMH bank-0 mirror
   in crt_cacher for MF, broader CB2 mode-decode in CRB writes, and
   audit of ioe_ena/ioe_wr_ena_o in NoCart mode.
4) Then resume the original plan: exit-to-BASIC, freeze-save-thaw with
   the 8 KB SRAM, mf-windows menu features.

GROUND RULES (carry over from the previous session)
- Use Read/Grep/Edit, not raw cat/grep/sed.
- "the C64MEGA65 config file" or "the config file" in user-facing text,
  never "Shell config".
- For GitHub comments / PR bodies, paragraphs as one long line — let
  the renderer flow.
- The user is a non-native English speaker; fine-tune English for any
  human-facing text while preserving tone and content.
- Do NOT modify CORE/vhdl files speculatively. Investigate first,
  propose, then code. The eight prior fixes (D1-D6 + threshold +
  V2-mirror) are documented in §9 of simcrt_magic_formel.md — do NOT
  re-introduce them and do NOT undo them.
- Be honest about uncertainty. The previous wrap-up was too eager to
  declare partial-READY a "stealth-cart correct" outcome; that was
  speculation. When in doubt, label hypotheses as hypotheses.

START BY
- Reading temp_mh_fix_issue_212/simcrt_magic_formel.md in full
  (especially §4, §5, §6, §7).
- Confirming the current cartridge.vhd `when 14 =>` branch and `rst_i`
  block on branch mh_fix_issue_212 still match what §3.1 of that brief
  describes. If anything has drifted, flag it.
- Then asking the user what they have learned since the wrap-up — at
  minimum: VICE-on-PC parity result, and RESTORE-press result if they
  ran it. Branch from there per §7 of the brief.
```

---

## How to use this file

1. Open a fresh Claude Code session in this repository (so `CLAUDE.md` auto-loads).
2. Paste the block above as the very first user message.
3. Claude will read `simcrt_magic_formel.md`, sanity-check the current branch, and ask for the latest test results before changing any code.
