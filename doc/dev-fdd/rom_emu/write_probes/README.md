# ROM write probes (issue #244 planning, 2026-10-15)

Scratch tooling produced while writing `doc/dev-fdd/WRITE-SPEC.md`: it re-executes the genuine
1581 DOS ROM 318045-02 against a rotationally timed, writable WD1772 model to measure how the DOS
writes and formats at the register level. Results and ROM addresses are in
`doc/dev-fdd/write_research_dos1581.md`.

* `wmachine.py` — the machine of `../machine.py` extended with an exact per-opcode 6502 cycle
  table (the stock emulator charges a flat 3 cycles per instruction) and a WD1772 model with
  Write Sector (datasheet sequence), Write Track (index to index, `F5`/`F6`/`F7` tokens), write
  protect, record-not-found, verify-mismatch and disk-change injection.
* `probe_flush.py`, `probe_flush2.py` — the side-cache write-back: command sequence, sector
  order, inter-command gaps, DRQ latencies.
* `probe_format.py` — the `N:` token stream and timing per side.
* `probe_replace.py` — cache replacement flush.
* `probe_errors.py`, `probe_wp.py`, `probe_change.py` — status decoding, retries, write protect
  and disk-change behaviour.

Run with `python3 -I probe_xxx.py` from this directory (the probes import `wmachine.py` and the
ROM via `../machine.py`; the disassembly listings they were developed against are regenerated
with `../dis65.py`). Milestone M2 of `doc/dev-fdd/WRITE-PLAN.md` grows this into the fixture
generator for the write testbenches. Not part of the synthesized design.
