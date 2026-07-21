# The 1581 Book

*How the C64 for MEGA65 core reads Commodore 1581 disks — both as files and as real, spinning magnetic media.*

## About this book

The C64MEGA65 project gives the MEGA65 computer a faithful Commodore 64, and a
Commodore 64 is not complete without its disk drives. This book is about one of
them: the **Commodore 1581**, the 3.5-inch drive from 1987, and about the two
very different ways our core brings it to life. The first way is convenient and
familiar: you pick a `.d81` file from your SD card, and a simulated 1581 serves
it to the C64. The second way is something rarer: you flip a menu switch, and
the MEGA65's own built-in 3.5-inch mechanism — the physical drive under the
floppy slot — becomes the 1581's mechanism, reading real magnetized disks,
flux transition by flux transition.

Both ways share one drive. Inside the FPGA — the field-programmable gate
array, the reprogrammable logic chip the MEGA65 is built around — there is a
complete 1581: its 6502 processor, its original DOS ROM (DOS being the disk
operating system, the drive's built-in firmware), its interface chips, its
floppy disk controller. Only the answer to the question "where do the sector bytes come
from?" differs. That architectural split — one drive computer, two media
backends — is the spine of this book, and by the end of it you will understand
every vertebra: from the physics of a magnetized speck on a spinning disk, up
through clock recovery and disk formats, through the Western Digital floppy
controller protocol and the drive's own operating system, to the exact VHDL
and Verilog files — the two hardware description languages the implementation
is written in — that implement all of it, and the way they were verified.

This is a textbook, not a datasheet. It is meant to be read front to back, and
it promises not to throw an unexplained acronym at you: every term is built
before it is used, and the Glossary at the end catches anything you forget
along the way. It is also a reference: Section B walks through every source
file, and the Appendix tells the story of how this implementation came to be —
a story with more wrong turns, refuted theories, and hard-won measurements than
you might expect from the finished result.

The book describes the implementation at its **read-only milestone** (July
2026, integrated into `develop` for `WIP-V6-A19`): the physical drive reads
disks; it cannot yet write them, and the write signals are physically tied
inactive as a safety guarantee. Chapter 18 explains that boundary precisely.

## How to read it

There are three good paths through this book:

- **Cover to cover.** Section A builds everything up in order: Part I teaches
  how any floppy drive works, Part II the 1581 and its disk format
  specifically, Part III our implementation. Then Section B revisits the same
  machinery file by file, and the Appendix tells the history. If you have the
  time, this is the intended experience.
- **Architecture only.** Read Section A and stop. You will understand the whole
  system and can treat Section B as a lookup table for later.
- **Reference first.** If you are here to modify a specific file, jump straight
  to its entry in Section B; each entry points back to the Section A chapter
  that teaches its concepts, and forward to the tests that guard it.

## Conventions and notation

- **Hexadecimal** numbers are written `0x1234` in general prose. Addresses
  inside the 6502 world keep their traditional form in code spans, like
  `$C3F8`. Binary values are written like `10011001`.
- A **cycle**, when unqualified, means one tick of the 50 MHz clock that runs
  the physical-drive controller — 20 nanoseconds. Every other clock is always
  named explicitly ("the 2 MHz drive CPU clock", "the 31.5 MHz core clock").
- **Signal names** follow the repository convention: `_i` marks an input, `_o`
  an output, `_n` an active-low signal (asserted when it is 0). Many floppy
  signals are active-low by heritage; the text always says so where it
  matters.
- **File paths** are relative to the repository root. The physical-drive
  sources live in `CORE/vhdl/physical_1581/`; the drive computer lives in
  `CORE/C64_MiSTerMEGA65/rtl/iec_drive/`.
- Occasional `file.vhd:123` line references were correct at the milestone
  commit; entity, process, and constant names are the durable anchors.
- The decoder's timing classifier is spelled **quantiser** throughout,
  following the source file names (`physical_1581_mfm_quantise.vhd`);
  elsewhere the book uses American English spelling.

## Prerequisites

You should know what a Commodore 64 and a MEGA65 are, and it helps to have
typed `LOAD"$",8` at least once in your life. Everything else — magnetism,
encodings, controllers, buses, the drive's operating system, and the hardware
description languages the implementation is written in — is introduced as we
go. Where a chapter leans on an earlier one, it says so.

## Contents

**Section A — The Drive, Understood**

*Part I — How floppy disk drives work*

1. Magnetism, flux, and the impossibility of just storing bytes
2. From flux to bits: FM, MFM, and clock recovery
3. The track as a data structure
4. The floppy disk controller
5. The intelligent Commodore drive

*Part II — The Commodore 1581*

6. Anatomy of a 1581
7. The 1581 disk format
8. The DOS ROM 318045-02
9. Interlude: F011 media — the MEGA65's own dialect

*Part III — Our implementation: the whole stack*

10. The big picture
11. The image-backed path, end to end
12. The physical path, end to end
13. The adaptive MFM decoder
14. The controller: media state and motion
15. Delivery: the WD boundary
16. Clocks, domains, and resets
17. Observability: the diagnostic device
18. Boundaries and safety

**Section B — The Code, File by File**

- B1 — The decode chain: `physical_1581_pkg` · `mfm_gaps` · `mfm_quantise` · `mfm_gaps_to_bits` · `mfm_bits_to_bytes` · `mfm_decoder` · `crc`
- B2 — Controller and delivery: `physical_1581_controller` · `inputs` · `rdfifo` · `diag`
- B3 — The drive proper: `fdc1772.v` · `c1581_drv.sv` · `c1581_multi.sv` · `iec_drive.sv`
- B4 — Peripherals: `iecdrv_mos8520.v` · `iecdrv_via6522.vhd` · `floppy.v` · the 1541 side, briefly
- B5 — Integration glue: `main.vhd` · `mega65.vhd` · `globals.vhd` · board tops · `vdrives.vhd` · `config.vhd` and the Shell
- B6 — The test suites: the GHDL benches · the A/B quantiser harness · `tb_fdc1772_physical.sv` · the genuine-ROM emulator · running everything

**Appendix — The Road to the 1581**

- C1. Timeline · C2. The eras · C3. What the road taught · C4. Open ends

**Back matter** — Glossary · Document map

## Section A — The Drive, Understood

### Part I — How floppy disk drives work

### 1. Magnetism, flux, and the impossibility of just storing bytes

Strip away the case, the connector, and forty years of nostalgia, and a floppy
disk is a thin plastic ring coated with magnetic particles, spinning inside a
protective shell. A **head** — a tiny electromagnet on a movable arm — hovers
in contact with the coating. To write, the drive pushes current through the
head coil and magnetizes the particles under it in one direction or the other.
To read, the physics runs in reverse — but with a twist that shapes everything
else in this book.

A read head does not sense magnetization; it senses *change* in magnetization.
As the disk rotates under the head, a region magnetized steadily north-south
induces no signal at all. Only at the boundary where the magnetization flips —
called a **flux transition** — does the moving field induce a brief voltage
pulse in the coil. The drive's analog electronics amplify and sharpen these
pulses and hand the digital side exactly one thing: a wire that ticks every
time a transition passes under the head. Between ticks, silence.

So a floppy drive cannot store bytes. It cannot even store bits directly. All
it can store is a *sequence of transitions along a circular path*, and all it
can read back is the *time between consecutive transitions*. Everything a disk
holds — your program, the directory, the disk's own name — must be encoded
into carefully chosen transition spacings, and decoded back out of nothing but
measured time. Chapter 2 is about that encoding. First, the geometry.

The head arm does not sweep freely; a **stepper motor** moves it in fixed
increments between concentric circles called **tracks**. The set of tracks at
one arm position — one on the top surface, one on the bottom for a
double-sided disk — is a **cylinder**, and each surface is a **side** (or
**head**, since each surface has its own read/write head). Along a track, data
is divided into **sectors**, fixed-size records that are the unit of reading
and writing. A sector is found not by position sensors but by *reading*: each
sector announces itself with a small label — an idea Chapter 3 makes precise —
and the drive recognizes the one it wants as it flies past.

Three more sensors complete the picture. An **index** sensor fires once per
revolution, giving the electronics a fixed reference point on the otherwise
featureless circle — on a 3.5-inch disk it detects a notch in the metal hub.
A **track-0 switch** closes when the arm reaches the outermost cylinder, the
only absolute position the drive can sense; every other position is reached by
counting steps from there. And a **write-protect** sensor reads the little
sliding tab on the disk shell. The spindle motor turns the disk at a fixed
rate — 300 revolutions per minute for the drives in this book, one revolution
every 200 milliseconds.

Notice what is *not* in this list: there is no "you are now at sector 5" wire,
no bit clock, no byte boundary. The disk offers a spinning circle of timed
ticks, an index pulse once per revolution, and a switch at track 0. Everything
else is convention, encoding, and inference — which is to say, everything else
is the subject of the next chapters.

### 2. From flux to bits: FM, MFM, and clock recovery

Suppose you want to store the bit sequence `1 0 1 1 0 0 1`. The obvious idea —
transition for a 1, no transition for a 0 — fails quickly. The reader measures
*time* between transitions, and time only means something relative to a clock.
If the pattern contains a long run of zeros, the reader sees one long silence
and must divide it by the bit period to know how many zeros passed. But whose
bit period? The disk was written by a different drive, years ago, whose motor
turned at not-quite-300 revolutions per minute; the reading motor has its own
error; the plastic has expanded with temperature. With no transitions for
reference, small speed differences accumulate and the count is soon off by a
bit. The read becomes garbage.

The cure is to make the data stream *self-clocking*: guarantee transitions
often enough that the reader can continuously re-measure the writer's timing.
The first scheme, **FM** (frequency modulation), is brute force: every bit
cell begins with a clock transition, and a 1-bit adds a second transition in
the middle of the cell. The clock is always there — and half the disk's
capacity is spent on it.

**MFM** (modified frequency modulation), the scheme all our disks use, is the
elegant refinement. Its rule has two halves: a 1-bit always writes a
transition at the *center* of its bit cell; and a clock transition is written
at the *boundary* between two cells only if the bits on both sides are 0 —
just enough clock to fill the longest silences, and not a transition more.
MFM stores twice as much as FM on the same disk, which is why FM is also
called single density and MFM **double density (DD)**.

Rather than reason about the rule in the abstract, watch it store the very
sequence this chapter opened with — `1 0 1 1 0 0 1`. The numbers that fall
out are the ones the whole physical decoder of Part III lives inside. Our
disks record 250,000 bits per second, so each bit cell is 4 microseconds
wide. In the ruler below, `|` marks the cell boundaries and `+` marks the
cell centers:

```
data bits:     1     0     1     1     0     0     1
            |--+--|--+--|--+--|--+--|--+--|--+--|--+--|
flux:          ▲           ▲     ▲        ▲        ▲
gaps:          └───8 µs────┘     └──6 µs──┘
                           └─4µs─┘        └──6 µs──┘
```

Walk the flux row against the rule. Every 1 fired a transition at its cell
center — four of the five marks stand under a `+`. The zeros wrote nothing of
their own, except in one place: between the two *adjacent* 0s the boundary
half of the rule kicked in and produced the fifth mark, standing under a
`|` — a **boundary clock**. Now read off what a drive will see when this
passes under the head again: five transitions, spaced 8, 4, 6, and 6
microseconds apart. That spacing sequence *is* the recording; nothing else
survives on the disk.

And look where the marks stand: always on a center or on a boundary, never
in between. Centers and boundaries alternate every 2 microseconds, so every
transition lives on a single, uniform 2-microsecond grid. That grid unit is
worth naming: a **half-cell** is 2 microseconds — half a bit cell — and from
here on the book measures every flux interval in half-cells. In those units
the example's gaps are 4, 2, 3, and 3 half-cells, and that is no accident of
this particular bit string. Between two consecutive transitions there are
always exactly **2, 3, or 4 half-cells** — 4, 6, or 8 microseconds — and
every case traces back to one of five bit neighborhoods:

```
data bits      transition spacing
1 1            2 half-cells (4 µs)   cell center to cell center
0 0 0 ...      2 half-cells (4 µs)   boundary clock to boundary clock
1 0 0          3 half-cells (6 µs)   cell center to boundary clock
0 0 1          3 half-cells (6 µs)   boundary clock to cell center
1 0 1          4 half-cells (8 µs)   center, skipped middle, center
```

Four of the five rows appear in the worked example above; the remaining one
is just a longer run of zeros, which repeats its boundary clock once per bit
cell. And the two edges of this little alphabet are forced by the rule
itself, not decreed. Nothing *shorter* than 2 half-cells can ever occur: that
would take a cell center and an adjacent boundary firing together, but the
boundary only fires between two 0s, and a firing center *is* a 1. Nothing
*longer* than 4 can occur either: the only way to stay silent past one
skipped center (`1 0 1`) is a run of zeros — and a run of zeros clocks every
boundary it contains.

A decoder therefore has a beautifully small job description: measure each
**gap** (the time from one transition to the next), classify it as
2-, 3-, or 4-half-cells wide — **short**, **medium**, and **long**, the
class names the rest of this book uses — and unfold the classification back
into data bits. Three legal symbols. That's the entire alphabet of a double-density
floppy disk.

The job description is small; the job is not, because real gaps are not 4.000,
6.000, and 8.000 microseconds. Four things smear them:

- **Speed error and drift.** The writing and reading spindles each miss
  300 revolutions per minute by a fraction of a percent, and not by a constant
  fraction — motors wander. All gaps stretch or shrink together.
- **Jitter.** Electrical noise moves each detected transition slightly and
  independently.
- **Peak shift**, the physicist's name **inter-symbol interference (ISI)**:
  when two transitions sit close together, their magnetic fields overlap and
  push each other apart during writing and reading. Short gaps read longer
  than written, long gaps shorter — a *systematic*, data-dependent distortion,
  worst on inner tracks where the same bits occupy less physical space.
- **Damage and age**: weak magnetization, dropouts, and the write splice
  (Chapter 3's subject) produce gaps that were never legal MFM at all.

So classification needs windows, the windows need margins, and — as Part III
will show in detail — deciding *where the windows sit and whether they may
move* turns out to be one of the deepest design questions in this entire
project. For now, hold the essential picture: a floppy read chain is a clock
recovery problem wearing a storage costume.

One more consequence of MFM deserves its own paragraph, because Chapter 3
builds on it. Since the encoding rule is deterministic, every byte value
produces one fixed pattern of transitions. A decoder scanning mid-stream,
however, does not know where byte boundaries lie — any window of the
transition stream could be the middle of one byte or the start of another. To
give the decoder a foothold, disk formats deliberately write a pattern that
*violates* the MFM clock rule in a recognizable way — a pattern no legal data
stream can produce. That pattern is the sync mark, and it is the hero of the
next chapter.

### 3. The track as a data structure

A track is one continuous circle of MFM symbols with no beginning and no end —
the head lands wherever it lands, mid-something. Disk formats impose structure
on this circle with a small grammar of fields and separators, invented by IBM
for its 8-inch drives and inherited, nearly unchanged, by the Western Digital
controller family and every disk this book cares about. Learning this grammar
is learning to *read a track*, and later chapters — especially the decoder
chapters — assume it fluently.

The grammar has four elements:

**Gap bytes.** Stretches of a filler byte, `0x4E`, separate everything from
everything else. (An unfortunate name collision: these "gaps" are runs of
bytes in the format, unrelated to the flux-timing gaps of Chapter 2. The book
says **gap bytes** when it means the filler.) Gap bytes give the drive
mechanical and electronic breathing room: time for a write to switch off
cleanly, for a head change to settle, for a controller to think between
fields.

**Preamble.** Twelve bytes of `0x00` precede each field. In MFM a run of
zeros produces the maximally regular pattern — a boundary clock at every bit
cell, one shortest-legal 2-half-cell gap after another — the easiest possible
signal for a clock-recovery circuit to lock onto. The preamble is a runway: by the time the meaningful bytes arrive, the
reader's timing is synchronized.

**The sync mark.** After the preamble come three bytes of `0xA1` — but not
ordinary `0xA1`. To see the trick, write a byte the way the disk sees it:
sixteen **slots** on Chapter 2's half-cell grid, a clock slot then a data
slot for each bit, where a 1 in a slot means "a transition here". Here is
`0xA1` (data bits `1 0 1 0 0 0 0 1`, following a preamble zero) encoded
twice — once honestly, and once as the formatter actually writes it, with
one clock transition *deliberately omitted*:

```
data bits:    1    0    1    0    0    0    0    1
data 0xA1:   0 1  0 0  0 1  0 0  1 0  1 0  1 0  0 1   reads: L M S S M
sync 0xA1:   0 1  0 0  0 1  0 0  1 0  0 0  1 0  0 1   reads: L M L M
                                      ▲
                               the omitted clock
```

Read each slot row as flux — every 1 is a transition — and measure the gaps
between them. Honest `0xA1` (raw word `0x44A9`) reads long, medium, short,
short, medium. The doctored byte (raw word `0x4489`) reads **long, medium,
long, medium** — and that four-gap tail is the whole point, because legal
data can never produce it. Chapter 2's rule makes the argument short: a
long gap only ever runs cell center to cell center (`1 0 1`), and a medium
gap leaving a center always lands on a boundary clock (`1 0 0`) — so after
*long, medium* the stream is necessarily sitting on a cell boundary, and
from a boundary the very next transition is at most a medium away (`0 0 1`).
*Long, medium, long* is therefore impossible in data; the omitted clock is
precisely what manufactures it. This is the **A1 sync mark**: a
byte-aligned, unmistakable "a field starts here" flag, findable from cold,
mid-track, with no context. Three in a row (the **A1 train**) make the flag
robust; a reader demands all three before believing it. The next byte after
the train tells *what kind* of field follows; that byte is called the
**address mark**.

**Fields.** The grammar defines two. An **ID field** is the sector's label:
address mark `0xFE`, then four bytes — cylinder, head, sector number, and a
size code (**C, H, R, N** in Western Digital parlance; N is 2 for the
512-byte sectors of our disks) — then a two-byte checksum. A **data field**
is the payload: address mark `0xFB` (or `0xF8` for a "deleted" sector, a
mostly vestigial feature), 512 data bytes, checksum. Every sector on the disk
is an ID field followed, a moment later, by its data field. To read sector 7,
a controller reads ID fields as they fly past until one says "R equals 7" with
a valid checksum, then reads the very next data field.

The checksum is a **CRC** (cyclic redundancy check), 16 bits wide, of the
polynomial-division family — specifically the variant known as CRC-16/CCITT
with initial value `0xFFFF`, computed over everything from the first A1 of the
sync train through the last payload byte. The CRC's virtue is that the check
runs incrementally: feed it the received bytes *including* the two stored
checksum bytes, and a correct field leaves the register at exactly zero. One
flipped bit anywhere leaves it nonzero. The CRC decides, for every field, the
only question that matters: did this read survive intact?

Put together, one sector of a stock 1581 track looks like this on the
surface (the counts are what the 1581's own firmware writes; other formatters
vary the gap-byte counts slightly):

```
 ... 4E 4E (gap bytes)
 00 ×12          preamble
 A1 A1 A1        sync train (missing-clock A1s)
 FE  C H R N     ID address mark + sector label
 CRC CRC
 4E ×22          gap bytes ("Gap 2")
 00 ×12          preamble
 A1 A1 A1        sync train
 FB  <512 bytes> data address mark + payload
 CRC CRC
 4E ... (gap bytes, then the next sector's preamble)
```

Ten such sectors, plus the gaps and a lead-in after the index, fill the 6,250
bytes that fit on one double-density track at 300 revolutions per minute.

One last inhabitant of the track must be introduced, because it haunts half
the Appendix: the **write splice**. A drive never rewrites a whole track in
normal operation; it rewrites one data field, switching its write current on
just after the sector's ID field and off just after the checksum. At the
switch-off point, newly written flux meets old flux mid-stream — with
unrelated phase, arbitrary spacing, sometimes a half-formed transition. Every
track that has ever been written to has these scars, and the format
deliberately places them inside gap-byte regions where nothing needs to
decode. But a reader flying over a splice still *sees* flux, and that flux
can, by pure bad luck, imitate legal patterns — even a sync mark. A naive
decoder trusts it and derails; a robust one is designed, from the start, with
the splice as a first-class adversary. Chapter 13 shows how far that
principle had to be taken.

### 4. The floppy disk controller

Between the drive's raw signals and a computer's tidy world of "read me sector
7" sits the **floppy disk controller** — **FDC** from here on. An FDC is a
small, single-purpose processor: it steps the head, watches the index pulse,
decodes ID fields, matches sector numbers, checks CRCs, and moves sector bytes
one at a time to and from its host. Our case study is the controller the 1581
actually contains: the **Western Digital WD1772**, a 28-pin chip whose
protocol, quirks included, our implementation reproduces down to details you
would only notice when they break.

The host sees the WD1772 as four eight-bit registers:

- the **command/status register** — write a command byte, read live status;
- the **track register** — the controller's belief about the current cylinder;
- the **sector register** — which sector number the next command should find;
- the **data register** — the byte-at-a-time window through which all sector
  data flows.

Commands come in four types, and the type vocabulary is worth absorbing
because drive firmware, our RTL (register-transfer level code — the hardware
implementation sources Section B walks through), and the Appendix all speak
it:

- **Type I — positioning.** `Restore` steps outward until the track-0 switch
  closes (the only absolute calibration); `Seek` steps to a target cylinder;
  `Step` variants move one cylinder. Optional flags request spin-up waiting
  and a position verify.
- **Type II — sector transfer.** `Read Sector` and `Write Sector`: find a
  matching, CRC-valid ID field, then move the 512 payload bytes through the
  data register.
- **Type III — track-level.** `Read Address` delivers the *next* ID field
  that flies past — six bytes: C, H, R, N and the two CRC bytes — a way for
  firmware to ask "where am I?". `Read Track` and `Write Track` transfer a
  whole raw track (write track is how disks get formatted).
- **Type IV — Force Interrupt.** The abort hatch: terminate whatever is in
  progress.

Around these commands, three status signals define the controller's rhythm.
**BUSY** (status bit 0) is set while a command runs. **DRQ** — the **data
request** flag, with a companion chip pin — announces "the data register needs
service now": during a read, a fresh byte has arrived; during a write, the
register is empty. And **INTRQ**, the interrupt request, pulses when a command
completes. The rest of the status byte reports outcomes, and three of its
flags will matter enormously later: **record not found (RNF)** — no matching,
CRC-valid ID field turned up within the search budget (five index pulses);
**CRC error** — a field was found but arrived corrupted; and **LOST DATA** —
the harsh one, explained next.

Here is the property that makes an FDC unlike any polite peripheral: **the
disk does not wait.** Once a read is underway, bytes arrive every 32
microseconds — one per byte-time at double density — whether or not the host
is ready. The WD1772 gives the host exactly one byte-time to collect each
byte from the data register. Too slow, and the next byte overwrites it; the
controller raises LOST DATA and the transfer is ruined. There is no
flow control on a spinning disk. One Read Sector, as the drive's CPU
experiences it:

```
BUSY   ──╔═══ find the ID field ═══╦══════ 512 data bytes ══════╗─────
DRQ                                ╹     ╹     ╹     ╹  …  ╹
                                   └32 µs┘ collect each byte before
                                           the next one lands
INTRQ                                                           ╹
                                                     command complete
```

This single fact shapes drive firmware
(tight, disciplined polling loops), and it shaped our implementation more
than any other constraint: Chapter 15 is essentially the story of honoring
this timing contract from an FPGA.

Two smaller WD1772 behaviors complete the picture the later chapters need.
After a Type II command finds its ID field, the data field must begin within
a fixed window — 43 byte-times — or the controller abandons the attempt and
resumes searching (guarding against a sector whose data field was destroyed).
And on `Read Address`, the controller copies the found cylinder number into
the *sector* register — an odd little side effect that real firmware
exploits, and that our WD1772 model reproduces faithfully; drive firmware
misbehaves without it.

### 5. The intelligent Commodore drive

On most computers of the era, the FDC sat on the computer's own bus and the
computer's CPU ran the disk operating system. Commodore took a different
road: their drives are complete computers. A Commodore drive has its own
6502-family CPU, its own RAM, its own ROM containing the **DOS** (disk
operating system), and its own interface chips — and the computer merely
sends it requests over a serial cable. When a C64 says `LOAD"$",8`, it is not
reading the disk; it is asking *another computer* to read the disk and mail
back the results.

The cable is the **IEC bus** — Commodore's serial descendant of the IEEE-488
instrument bus. Three signal lines matter: **ATN** (attention), which the
computer pulls to open a command phase, **CLK** and **DATA**, which clock
bits across. Every line is **wired-AND**: electrically, any device on the bus
can pull a line low, and the line is high only when everyone releases it —
which is how several devices share the bus without bus fights, and why an
FPGA implementation models each line as "the AND of everyone's output":

```
  C64 output ────┐    drive 8 output ────┐    drive 9 output ────┐
                 └──────────┬────────────┴────────────────────────┘
                     one bus line = the AND of all outputs:
              low if anyone pulls low, high only when all release
```
Devices have numbers — drives conventionally start at **device 8** — and
within a device, communication runs over numbered **channels** (channel 0 is
"load a program", channel 15 is the command/error channel — the one you read
drive error messages from).

The practical upshot: the protocol between computer and drive is *high
level*. "Open the file named SHADES." "Give me the next byte." The entire
mechanical and magnetic reality — spinning up the motor, stepping the head,
finding sectors, retrying failures, walking the directory, following the
chain of a file's blocks — happens inside the drive, orchestrated by the
drive's own firmware against its own FDC. The drive DOS maintains its own
job model internally: high-level requests become **jobs** (read this block,
write that block) executed against the hardware, with a small numeric result
code per job — a structure you will meet in machine detail in Chapter 8.

This architecture is why our implementation contains a whole second computer,
and why that is a *feature*. The 1581's behavior — every quirk of its DOS,
its timing, its error messages, its interaction with fast loaders — lives in
its firmware. Emulate the drive's hardware faithfully and run the original
firmware on it, and all of that behavior comes along automatically, bug for
bug. Reimplement the DOS instead, and you inherit a lifetime of chasing
differences. Keeping the drive computer real, and swapping only what it reads
from, is the design decision this entire project stands on — Chapter 10 makes
it explicit.

### Part II — The Commodore 1581

### 6. Anatomy of a 1581

The 1581 (1987) was Commodore's last and most modern 8-bit drive: 3.5-inch
double-density disks, 800 kilobytes per disk — a giant next to the 1541's 170 —
and a conventional, industry-standard recording format in place of Commodore's
earlier custom encoding. Inside the beige case live four principals, and since
our implementation reproduces each of them as a distinct module, it pays to
meet them individually.

**The drive CPU** is a 6502 running at 2 MHz, twice the speed of a C64's
processor. It executes the DOS from a 32-kilobyte ROM mapped at `$8000` and
uses 8 kilobytes of RAM at `$0000` — enough to cache an entire track, a luxury
the 1541 never had and one the DOS uses aggressively.

**The interface chip** is an 8520 **CIA** (Complex Interface Adapter, the same
family as the C64's own I/O chips), mapped at `$4000`. Its two eight-bit ports
are the drive's nervous system. Port B faces the IEC bus: the CLK and DATA
lines in both directions, ATN in, plus an ATN-acknowledge line. Port A faces
the machine's body, one bit per bodily function — and because our
implementation must feed each of these bits convincingly, they are worth
listing precisely:

```
PA0  side select        out  which disk surface the head reads
PA1  /READY             in   mechanism reports stable rotation
PA2  /MOTOR             out  spindle motor on (active low)
PA3  device number      in   jumper: device 8..11
PA4  device number      in       "
PA5  power LED          out
PA6  activity LED       out
PA7  /DISK CHANGE       in   latched: a disk was removed
```

Two of these inputs carry contracts subtle enough to have earned their own
hardware war stories (Appendix, era 5). **/READY** is the mechanism's promise
that the disk is rotating at stable speed; the DOS samples it on a strict
budget after switching the motor on, and a drive that answers late is simply
declared "not ready". **/DISK CHANGE** is a latch, not a level: it is set the
moment a disk leaves the slot and stays set — even after a new disk is
inserted — until the CPU steps the head, which is the mechanical gesture the
drive uses to acknowledge "yes, I noticed the swap". The DOS performs a
deliberate little step-in, step-out wiggle exactly to clear this latch.

**The floppy disk controller** is the WD1772 of Chapter 4, mapped at `$6000`.
The CPU talks to its four registers; the WD1772 talks to the mechanism.

**The mechanism** — in the original 1581, a Chinon FB-354 — is the same
commodity 3.5-inch unit found in countless machines of the era, controlled
through the industry-standard floppy interface: a bundle of single-purpose,
active-low lines rather than any kind of bus. The signals, using the names our
RTL gives them: `f_motora` (spindle motor), `f_selecta` (drive select),
`f_step` and `f_stepdir` (one pulse per cylinder of head movement, direction
level), `f_side1` (which head), `f_density` (data-rate select, held at
double density), `f_index` (the once-per-revolution pulse),
`f_track0` (the calibration switch), `f_writeprotect`, `f_diskchanged`, the
read line `f_rdata` (one pulse per flux transition — the wire Chapter 1
promised), and the write pair `f_wgate`/`f_wdata` (write enable and write
transitions). The MEGA65's own internal 3.5-inch mechanism exposes exactly
this interface, which is the physical fact that makes this whole project
possible: the FPGA can drive these lines directly and *be* the 1581's
electronics.

Assembled, the four principals form a computer with a memory map — the
1581 as its own CPU sees it:

```
   IEC bus ◀──▶  8520 CIA    ($4000) ──┐
                                       │
                 8 KB RAM    ($0000) ──┤
                                       ├──  6502 CPU (2 MHz)
                 32 KB DOS ROM ($8000)─┤
                                       │
 mechanism ◀──▶  WD1772 FDC  ($6000) ──┘
```

One architectural footnote completes the anatomy. Our drive model also
contains a 6522 **VIA** (Versatile Interface Adapter) at `$2000` — a chip the
real 1581 does not have. It models an aftermarket parallel-port extension
inherited from the upstream MiSTer implementation (MiSTer being the
open-source FPGA-retrocomputing project our C64 core descends from; Chapter
10 introduces it properly), and it sits dormant in normal operation (Section B4.2 gives it a page).

### 7. The 1581 disk format

The 1581 stores 800 kilobytes as plain physical arithmetic: 80 cylinders × 2
sides × 10 sectors × 512 bytes — 819,200 bytes exactly. Physically, each
track is the IBM/Western Digital grammar of Chapter 3: ten ID fields numbered
**1 through 10** (the numbering starts at 1, an IBM-format convention),
each followed by its 512-byte data field, all double-density MFM at 300
revolutions per minute.

Commodore's DOS, however, predates this format and thinks in its own units:
**logical tracks 1 through 80**, each holding **40 logical sectors of 256
bytes, numbered 0 through 39**. The two views describe the same bytes through
a fixed mapping: logical track T is cylinder T−1; logical sectors 0–19 live
on side 0 and 20–39 on side 1; and each physical 512-byte sector carries two
consecutive logical sectors, first half and second half. One worked example
makes the whole translation concrete — here is the first directory block,
the single most-read block on any 1581 disk:

```
the DOS asks for:  logical track 40, sector 3
   cylinder 39            track − 1
   side 0                 sector 3 is in 0–19  (20–39 would be side 1)
   physical sector 2      two logical per physical: 0,1 → 1;  2,3 → 2; …
   second 256-byte half   odd logical sector number
```

(For sectors 20–39 the same arithmetic applies after subtracting 20, on
side 1.) The DOS never notices any of this — its job layer asks for logical
track and sector, and a thin translation in the firmware picks cylinder,
side, physical sector, and half.

A **D81 file** — the `.d81` disk image our image-backed drive mounts — is
nothing more than the logical view serialized: track 1 sector 0 through track
80 sector 39, 256 bytes each, 819,200 bytes total, no header, no metadata.
This identity matters practically: any file of exactly 819,200 bytes is a
plausible D81, and any file of a different size is not one (variants with
appended error tables exist in the emulator world; our implementation
requires the exact size and rejects the rest — a corrupted geometry serves
nobody).

The disk describes itself on **logical track 40** — the middle of the disk,
minimizing average head travel. Sector 0 holds the header: disk name, ID
bytes, format marker. Sectors 1 and 2 hold the **BAM** (block availability
map), one bit per sector, the DOS's ledger of what is free. Sector 3 starts
the directory: a chain of blocks, each holding eight file entries of 32
bytes — file type, start track and sector, name, block count. Files
themselves are singly linked chains: the first two bytes of every 256-byte
block point to the next block's track and sector. `LOAD` walks the directory
for the name, then follows the chain block by block — which is why, in the
hardware traces that fill the Appendix, every session begins with a burst of
activity at cylinder 39: that is logical track 40, the directory, and nothing
on a 1581 happens without consulting it first.

### 8. The DOS ROM 318045-02

The 1581's firmware — Commodore part number **318045-02**, the final revision
— is the 32-kilobyte program that turns a box of chips into a disk drive. Our
implementation runs this exact ROM, byte for byte, on its emulated 6502
(with **JiffyDOS**, the popular third-party replacement, loadable as an
option). That choice buys perfect behavioral fidelity, and it charges an
equally perfect price: the hardware underneath must satisfy every assumption
the firmware makes, documented or not, reasonable or not. Much of Part III
exists to satisfy this chapter.

Seen from above, the DOS is an event loop fed by the IEC bus: parse the
command, translate it into **jobs** — elemental requests like "read logical
track 40, sector 3" — and hand each job to the drive layer, which runs the
motor, positions the head, and drives the WD1772 through the transfer. Each
job returns a small numeric code: 0 for success, specific codes for specific
failures, which the error channel translates into the messages every
Commodore user knows (`23, READ ERROR` — a CRC failure; `74, DRIVE NOT
READY` — the motor/readiness contract broke; `62, FILE NOT FOUND`).

Four passages of this firmware are so load-bearing for our implementation
that they deserve individual introductions. All four were discovered the hard
way — by disassembling the ROM mid-debugging and, eventually, running it
inside a purpose-built emulator with controlled hardware models (Appendix,
era 2 and Section B6.4).

**The transfer loop** (at `$C969`): the innermost loop that moves sector
bytes. It polls the WD1772's status: BUSY first, then DRQ, then reads the
data register. Its worst-case latency from a byte's arrival to its pickup,
interrupts masked, is 34 CPU cycles — 17 microseconds at 2 MHz — against the
32-microsecond byte cadence. A 47%
margin: comfortable, but only if the hardware presents bytes at the honest
disk pace and never faster. Present two bytes 17 microseconds apart and the
loop drops one — with consequences described next.

**The status epilogue** (at `$CD3F`, indexing a table at `$CD5A`): when a job
finishes, this code maps the WD1772 status byte to a job result by table
lookup — it shifts and masks the status so that the CRC-error and
record-not-found bits become the low bits of a table index. Lay out the four
possible combinations and the hole becomes visible:

```
WD status flags            table verdict         what the DOS then does
neither CRC nor RNF        job OK                accepts the data
RNF only                   job error             read error, retries
CRC only                   job error 5           "23, READ ERROR", retries
CRC and RNF together       0x00 = job OK  (!)    accepts corrupt data
```

The last row is the hole: both failure flags at once index an entry the
table's authors left at zero — *success*. On a real drive that combination
is vanishingly rare — it takes a search that both stumbled over a corrupted
ID field and then exhausted its whole budget — so the hole never mattered in
practice. But an emulated controller that sets both flags on a failure — a
perfectly reasonable "belt and suspenders" instinct — sails through this
hole and delivers corrupt sectors as good ones, silently. Our controller
therefore enforces the invariant *CRC error and record-not-found are never
raised together* (Chapter 14).

**The LOST DATA stack bug** (a branch at `$CD49`, inside the status epilogue
that begins at `$CD3F`): one branch of the error epilogue,
taken when the LOST DATA flag is set, skips a `PLP` instruction — a pull from
the CPU stack — that its sibling paths execute. The routine then returns
through a misaligned stack: the CPU pops a flags byte where a return address
should be and leaps to a garbage address. On a real 1581 this bug sleeps
forever (the margin above makes genuine LOST DATA nearly impossible). Against
an imperfect reimplementation, one spurious LOST DATA flag doesn't produce a
retry — it derails the firmware entirely. The moral for our design: LOST
DATA must be *possible* (it is real WD1772 behavior) but must only ever
report the truth.

**The readiness check** (at `$CDBC`): before its first job on a stopped
drive, the DOS switches the motor on, waits a fixed spin-up allowance —
roughly 0.7 seconds — and then samples the CIA's /READY line in one short
burst of about 30 consecutive reads. Pass, and the job proceeds; fail, and
the command is rejected with error 74 without the WD1772 ever being touched.
There is no retry loop and no patience: readiness is a one-shot exam with a
hard deadline, scheduled by a firmware that knows exactly how fast a real
FB-354 mechanism spins up. Chapter 14 recounts what this exam does to a
synthesized readiness signal.

Beyond these four, the DOS's *style* of using the WD1772 matters everywhere:
it positions the head relatively, confirming location with Read Address
rather than trusting step counts; it caches whole tracks (one reason the
directory reads in a quick burst of ten sectors); and on errors it retries
jobs with a patience budget before surfacing a DOS error. Every one of these
habits shows up as a pattern in the hardware traces of the Appendix, and our
implementation had to be correct under all of them — not as they are
documented, but as they are actually written.

### 9. Interlude: F011 media — the MEGA65's own dialect

One more piece of background is needed before Part III, and it is the odd one
out: it concerns not the 1581 but the MEGA65 itself.

The MEGA65's native floppy controller — used by its C65 personality and its
utilities — is the **F011**, a reimplementation of the controller chip
designed for Commodore's unreleased C65. It drives the same internal
mechanism, writes the same double-density MFM, and follows the same
IBM/Western Digital grammar — *almost*. When the F011 formats a disk, its
track layout differs from the stock 1581 layout of Chapter 3 in three ways
that a decoder must care about:

- **ID fields have no preamble.** The stock 1581 formatter writes twelve
  `0x00` bytes before every sync train. The F011's formatter writes the ID
  field's A1 train *immediately* after the preceding gap bytes — no zero run
  at all. Data fields, by contrast, do get the twelve-zero preamble in both
  dialects. (Remember this asymmetry: it decides the exact shape of a
  qualification rule in Chapter 13.)
- **A Track Info Block (TIB).** At the start of each track the F011 writes a
  small extra field of its own invention — sync train, address mark `0x65`,
  then track number, data rate, encoding, and sector count, with a CRC. A
  stock WD1772 never looks for such a field, but it exists on the surface,
  and a decoder flies over it every revolution.
- **A truncated eleventh sector.** The F011's formatter has no sector
  counter; it writes sector after sector until the index pulse arrives, then
  simply switches off mid-write. Ten full sectors fit — and the beginning of
  an eleventh, cut off at the index by a write splice. On the disks that
  matter here, the truncation falls *after* the eleventh ID field is
  complete: the track genuinely contains a CRC-valid ID field announcing
  "sector 11" — a sector that has no data field and, per the format's
  ten-sector arithmetic, should not exist.

Side by side, one sector of each dialect (and the F011's two specials):

```
stock 1581:
 …4E gap │ 00 ×12 │ A1 A1 A1  FE id CRC │ 4E ×22 │ 00 ×12 │ A1 A1 A1  FB data CRC │…
           preamble before EVERY sync train                              (ten sectors)

F011:
 TIB │ …4E gap │ A1 A1 A1  FE id CRC │ 4E ×23 │ 00 ×12 │ A1 A1 A1  FB data CRC │…
  ▲              ▲ no preamble before ID fields — data fields keep theirs
  track info                    … │ A1 A1 A1  FE sector-11 id CRC │ ✂ index splice
  block                             the eleventh ID, its sector cut off mid-write
```

Why devote a chapter to another controller's formatting habits? Because
F011-formatted disks are the *native media* of the physical drive this
project reads. The disk in a MEGA65's slot was, in practice, formatted and
written by the MEGA65 itself — the natural way to move data onto real 3.5-inch
media today. Our physical 1581 must therefore read two dialects with equal
reliability: stock 1581/WD1772 media (the compatibility promise) and F011
media (the daily reality). The differences are small, but as the Appendix
documents at length, each one of them — the missing ID preamble, the
eleventh-sector ID, the extra splice at the index — independently broke a
plausible decoder design on real hardware, and the decoder that ships treats
both dialects as first-class. The rule it settled on is worth stating here in
one sentence, as a preview of Chapter 13: *qualify what both dialects
guarantee (the structure of the sync train itself, and the record grammar of
ID-before-data), and refuse to qualify anything only one dialect provides.*

### Part III — Our implementation: the whole stack

### 10. The big picture

Everything in Parts I and II now assembles into one diagram. Inside the
C64MEGA65 core lives a complete 1581 — the drive computer of Chapter 6 — and
beneath it, exchangeable, two answers to the question "what is the disk?":

```
                 C64 (the emulated computer)
                        │  IEC bus (wired-AND)
        ┌───────────────┴────────────────┐
        │        THE DRIVE COMPUTER      │
        │  6502 CPU (2 MHz) ── DOS ROM   │
        │  318045-02 (or JiffyDOS)       │
        │  8520 CIA ── IEC, motor, LEDs, │
        │              ready, disk change│
        │  WD1772 floppy disk controller │
        │        (register model)        │
        └───────┬───────────────┬────────┘
                │               │
       "image mode"          "physical mode"
                │               │
   ┌────────────┴─────┐   ┌─────┴──────────────────┐
   │ D81 file from SD │   │ real 3.5-inch mechanism│
   │ card, cached in  │   │ in the MEGA65: flux in,│
   │ HyperRAM, served │   │ MFM decoded, sectors   │
   │ sector by sector │   │ qualified and CRC-     │
   │ (Chapter 11)     │   │ checked (Chapter 12)   │
   └──────────────────┘   └────────────────────────┘
```

The upper half is inherited from the **MiSTer** project — the open-source
FPGA-retrocomputing platform whose C64 core ours is a port of. MiSTer's 1581
implementation (by Alexey Melnikov, building on a long lineage of FPGA floppy
work) provides the 6502 (as the well-proven T65 core), the 8520, the WD1772
register model, and the IEC plumbing, all in the `iec_drive` module family.
This drive computer boots the genuine 318045-02 ROM and has served D81 images
reliably for years across the MiSTer ecosystem. It is, in the truest sense,
*proven equipment* — and the founding architectural decision of the physical
drive project was to leave it untouched.

That decision has a precise formulation, worth stating because every chapter
that follows leans on it: **physical acquisition is a producer of validated
sectors, not a second drive implementation.** The physical side reads flux,
decodes it, qualifies it, CRC-checks it — and only then hands a complete,
verified sector to the same WD1772 model, through the same byte-paced
delivery, that the image path uses. The drive computer cannot tell the
backends apart, and that is the point: every firmware behavior, every timing
assumption, every quirk of Chapter 8 is honored *once*, in one place, for
both media.

Operationally, the C64 sees one drive, device 8. In image mode you mount a
`.d81` (or `.d64`, which routes to the sibling 1541 implementation — the
drive *type* follows the image type) from the on-screen menu. In physical
mode you enable **Use internal 1581** in the menu, and device 8 becomes the
real mechanism. The switch is exclusive and guarded: the menu firmware
refuses the toggle while either backend is mid-operation, and switching media
sources deliberately presents itself to the DOS as a disk change — because
from the firmware's point of view, that is exactly what happened.

The rest of Part III walks this picture in increasing depth: the image path
(Chapter 11), the physical path (Chapter 12), then the physical path's three
hard problems — decoding (13), media state and motion (14), delivery (15) —
and the cross-cutting concerns: clocking (16), observability (17), and
safety (18).

### 11. The image-backed path, end to end

The image path answers "what is the disk?" with: *a file, staged in memory,
served block by block on demand*. Its cast, in the order a mount proceeds:

**The Shell.** The MEGA65 core's menus are run by a small 16-bit helper CPU
called **QNICE**, which lives alongside the C64 in the FPGA and runs the
**Shell** — the firmware behind the on-screen menu (the overlay you open with
the Help key). The Shell owns the SD card: it browses the FAT32 filesystem,
filters the file list to `.d64` and `.d81`, and when you pick a D81 it first
checks the size — exactly 819,200 bytes, the identity from Chapter 7 —
rejecting anything else.

**The mount buffer.** The Shell then copies the entire image into a dedicated
819,200-byte window of **HyperRAM** (the MEGA65's external RAM chip), the
*mount buffer*. From this moment the SD card is out of the hot path: the
drive works against the RAM copy. Writes dirty the copy and are flushed back
to the SD card in the background after a couple of seconds of quiet — with a
safety interlock: while unflushed data exists, the core vetoes resets (and
turns the drive LED yellow) so a hasty reset cannot corrupt the filesystem.

**The virtual-drive engine.** Between QNICE's world and the drive sits
`vdrives` — a module of the MiSTer2MEGA65 framework (M2M for short, the
porting layer that carried the MiSTer C64 core to this board) — which speaks
the MiSTer ecosystem's standard mount protocol: it announces "an image of this size and type is now
mounted" (`img_mounted`, `img_size`, `img_type`) and then serves block
requests in 256-byte units — the drive asks for the two consecutive blocks
of a 512-byte sector by **LBA** (logical block address — the block's
position within the image), and the engine answers from the mount buffer.

**The WD1772 model.** Inside the drive computer, `fdc1772.v` implements the
controller of Chapter 4 — registers, command types, status, DRQ — against
the block interface instead of magnetics. From the image size it derives the
geometry (double-sided, ten 512-byte sectors per track), computes the LBA for
any cylinder/side/sector the firmware asks for, fetches the sector into an
internal buffer (two 256-byte blocks per 512-byte physical sector), and then
— the crucial subtlety — *plays it back at authentic disk pace*.

**The rotation model.** Authenticity is the job of `floppy.v`, a small module
that pretends to be a spinning disk: it turns at 300 revolutions per minute,
emits an index pulse every 200 milliseconds, reports ready when "spinning",
and ticks a byte clock every 32 microseconds. The WD1772 model presents
sector bytes on this clock and paces its failures like a spinning disk — a
record-not-found emerges only after about a second, the time five
revolutions take. The DOS, whose every timing assumption was tuned to real
rotation (Chapter 8), runs happily.

From there upward the story is Chapters 5 through 8 verbatim: the 6502 runs
the DOS, the CIA speaks IEC, the C64 loads its directory. The whole path,
in one line per hop:

```
SD card ──copy──▶ HyperRAM mount buffer ──256-byte blocks──▶ vdrives
  ──sector fetch──▶ fdc1772 sector buffer ──32 µs byte pace──▶
  drive CPU (DOS ROM) ──IEC──▶ C64
```

Two details complete the image story. First, the geometry derivation means a
D81 *must* be exactly the canonical size — the identity check in the Shell
and the geometry tables in the WD1772 model are two ends of one contract.
Second, in image mode the controller's CRC-error status bit is constant
zero: bytes from a file are never magnetically damaged. Keep that in mind as
a contrast for what comes next — in physical mode, that bit earns its
living.

### 12. The physical path, end to end

The physical path answers "what is the disk?" with: *whatever is actually in
the MEGA65's drive slot, read from flux upward*. It reuses the entire drive
computer unchanged and replaces everything below the WD1772's media
boundary. Walk it once, top to bottom, as a tour — each station gets its
deep chapter afterward.

**Enabling.** "Use internal 1581" in the on-screen menu sets a single
control bit. The Shell guards the toggle with an idle gate — it consults the
physical controller's state and the image drive's activity, and silently
reverts the switch unless both are quiet — because rewiring a drive's media
while the DOS is mid-job benefits nobody. When the bit flips, the drive
computer keeps running; only its world changes: the image path's block-transfer
machinery is masked off,
the mechanism's pins are routed in, and the DOS is shown a disk change
(true, in every sense that matters).

**The pins.** The mechanism interface of Chapter 6 — `f_motora`, `f_selecta`,
`f_step`, `f_stepdir`, `f_side1`, `f_density`, `f_index`, `f_track0`, `f_writeprotect`,
`f_diskchanged`, `f_rdata` — is wired at the FPGA's top level on all four
MEGA65 board revisions. The write lines `f_wgate` and `f_wdata` are tied
permanently inactive there: in this milestone the hardware is *incapable* of
writing, by construction, not by policy (Chapter 18).

**Input conditioning.** Raw pins enter the 50 MHz controller clock domain
through double-flip-flop synchronizers — two one-bit storage elements in a
row, the standard defense against metastability, the hazard that a circuit
sampling a signal mid-transition can hover between 0 and 1 for an arbitrary
time; the second stage gives the first a full clock cycle to settle.
The index pulse gets qualification: only a low level sustained for 200
microseconds counts as an index edge, filtering electrical noise from the
once-per-revolution heartbeat that the readiness logic (Chapter 14) depends
on. The module also measures the index period and pulse width — diagnostics
that turned out to be sensitive enough to detect a disk slipping on its
spindle clamp from timing alone.

**The decode chain.** `f_rdata` — the tick-per-transition wire of Chapter 1 —
feeds the four-stage MFM decoder: measure gaps, classify them against an
adaptive timing estimate, unfold classes into bits, assemble bytes; alongside
runs the CRC engine and, orchestrating everything, the field parser that
recognizes sync trains, applies the qualification rules, and walks the
ID-field/data-field grammar. This chain — the project's hardest-won
component — is Chapter 13 entire.

**The controller.** Above the decoder sits the physical controller: a state
machine that owns the mechanism (motor, stepping, side select), maintains
the media-state contracts (readiness, disk change, head position), executes
read operations — *find and deliver sector R on the current cylinder*, *report
the next ID field*, *verify position* — and reports each operation's outcome
with a result code. It is the component that speaks both languages: mechanism
signals below, sector transactions above. Chapter 14.

**The quarantine and the handoff.** Decoded sector bytes do not flow to the
drive computer as they arrive. They accumulate in the **quarantine FIFO** — a
first-in-first-out buffer of 512 bytes, exactly one sector — and are released only after the controller pronounces the sector
clean: CRC checked, correctly addressed, complete. Failed reads drain away
unseen. Released bytes then cross into the drive computer's clock domain and
are presented through the WD1772 model's data register at the authentic 32
microsecond pace, indistinguishable from the image path's delivery — or from
a real chip's. Chapter 15.

From the WD1772 model upward, the drive computer neither knows nor cares:
same registers, same status rhythm, same DOS, same IEC. The whole path:

```
diskette ──flux──▶ f_rdata ──▶ input conditioning (50 MHz domain)
  ──gaps──▶ adaptive MFM decoder ──qualified fields──▶ controller
  ──complete CRC-clean sector──▶ quarantine FIFO ──clock crossing──▶
  fdc1772 presentation (32 µs pace) ──▶ drive CPU (DOS ROM) ──IEC──▶ C64
```

Set the two paths side by side and the symmetry is the architecture: both
end at the same WD1772 data register, at the same pace, under the same
protocol. Everything unique to the physical path — and everything the next
three chapters must explain — exists to make real, imperfect, splice-scarred
magnetic media *earn* the same trust that bytes from a file get for free.

### 13. The adaptive MFM decoder

This chapter is the heart of the book. The decoder's job statement fits in
one sentence — classify each flux gap as 2, 3, or 4 half-cells and parse the
resulting symbol stream by the track grammar — and Chapter 2 already listed
its enemies: speed error, drift, jitter, peak shift, and splice junk. What
follows is the machine that survives them all, presented gate by gate, each
with the adversary that justifies it. (That every gate was *forced* by a
specific, measured failure on real disks is the Appendix's story; here the
design is presented whole.)

#### The stages

Four small modules form the pipeline, one concern each:

**Gap measurement** (`physical_1581_mfm_gaps`). A free-running counter at 50
MHz; each detected transition emits the elapsed count — the gap — and
restarts. One filter lives here: a gap shorter than 16 cycles (320
nanoseconds — physically impossible as flux; even the shortest gaps a disk
produces are an order of magnitude longer) is a **runt**, an electrical
double-fire. The runt's edge is
dropped but its time is *kept*, merging into the following gap: the stream
downstream stays clean and no time is ever lost. The threshold's tightness
matters — an earlier, looser filter merged *real* edges after noise and
silently manufactured wrong-length gaps; 16 cycles admits only true
electrical artifacts.

**Classification** (`physical_1581_mfm_quantise`) — the adaptive core,
detailed below.

**Bit recovery** (`physical_1581_mfm_gaps_to_bits`). Unfolds each classified
gap into data bits by the MFM rule, and watches the last four classes for
the fingerprint *long, medium, long, medium* — the tail of the raw pattern
`0x4489`, the missing-clock A1 of Chapter 3. On a match it pulses an **A1
candidate**: the first, weakest evidence of a sync mark.

**Byte assembly** (`physical_1581_mfm_bits_to_bytes`). Collects bits into
bytes, most significant first. An A1 candidate forcibly realigns the byte
boundary — that is what "sync" means operationally — and is announced as a
distinct sync event, not an ordinary data byte.

Alongside runs the CRC engine (`physical_1581_crc`): CRC-16/CCITT, fed most
significant bit (MSB) first, initialized to `0xFFFF` at each sync train, fed every field byte
including the stored checksum, judged by the residue-zero rule of Chapter 3.

#### The adaptive estimate

Classification needs a yardstick: how long is a half-cell *right now, on
this disk, at this track*? Call it **the estimate**. Nominal is 100 cycles
(2 microseconds); the decoder maintains the estimate live, in fixed-point
with 1/16-cycle resolution, clamped to ±10% of nominal (90 to 110 cycles).

A gap of length G is classified by nearest multiple: the class windows are
"is G closer to 2, 3, or 4 estimates?", with boundaries at 2.5 and 3.5
estimates, and an outer acceptance limit of half an estimate beyond each
class center. On a number line (everything in units of the estimate):

```
          │← short →│← medium →│←  long  →│
    ──────┼────┼────┼────┼─────┼────┼─────┼──────
         1.5   2   2.5   3    3.5   4    4.5
   invalid     ▲          ▲          ▲     invalid
             center     center     center
```

Critically, the windows *touch*: there are **no dead bands**,
no forbidden zones between classes. The first shipped decoder had classical
windows with guard bands between them, and real inner tracks refuted it:
peak shift parked gap after gap inside the guard bands, classification
failed for whole revolutions at a stretch, and sectors on the innermost
cylinders became persistently unreadable. On a disk, a gap *must* be one of three symbols;
refusing to answer is just failing slowly.

After each accepted gap, the estimate moves by a fixed 1/8 cycle *toward*
the observation — up if the gap ran long for its class, down if short. The
step is deliberately sign-based, not proportional. A proportional tracker (a
conventional averaging filter) seems more natural but was refuted by
measurement: peak shift is *asymmetric* — short gaps only ever lengthen,
long gaps only ever shrink — so the per-gap timing errors are not centered
noise. Picture their distribution:

```
per-gap error vs. the true half-cell length (strong peak shift):

   shifted long gaps      unshifted majority      shifted short gaps
   ●●●●●─────────────────────●●●●●●●●●●●●●●●─────────────────────●●●●●
   read short                exactly on time                  read long
                                    ▲                    ▲
                              median: here        mean: dragged right
```

An averaging filter chases the *mean* of that lopsided cloud — a biased
equilibrium; under strong peak shift it dragged the estimate to its clamp
and began misclassifying. The fixed sign-step chases the *median* instead:
each accepted gap moves the estimate one small step up or down regardless
of how far off it was, so the estimate settles where half the gaps read
fast and half slow — pinned to the unshifted majority, robust by
construction against exactly the distortion floppy media exhibit.

A gap that fits no class (outside every window) is declared **invalid** —
the pipeline's loud failure symbol, historically "class 11". It aborts any
field in progress, closes every qualification gate below, and re-seeds the
estimate to nominal: a full re-lock, on the grounds that whatever produced
an impossible gap has also invalidated the clock inference.

#### Qualifying the sync mark

An A1 candidate is cheap: four gap classes in the right order. On clean
preamble-led flux it is also sufficient. But the write splice manufactures
counterfeits — and the counterfeits that matter are not noise-like but
*coherent*: measured splice residue on real disks produced alternating
~446/~344-cycle gaps, each individually within tolerance of a long or
medium class, firing overlapping candidates every two gaps, indefinitely.
Worse, per-gap tolerance cannot separate them from truth: peak shift moves
the *genuine* A1 train's gaps by comparable amounts. Any window tight
enough to reject the splice also rejects legitimate marks on legitimate
disks. The decoder therefore stops asking "does this gap look right?" and
starts asking "does the *whole structure* look right?" — three escalating
checks:

**The span check.** Look back at the sync byte's slot diagram in Chapter 3:
its four defining gaps read long, medium, long, medium — 4+3+4+3 = **14
half-cells**, 1,400 cycles at the nominal 100 cycles per half-cell. Peak
shift largely *cancels* over that total, because every interior transition
ends one gap and begins the next: whatever its displacement adds to one gap
it subtracts from its neighbor, and only the two outermost transitions can
move the sum. The splice's counterfeit ran 446+344+446+344 = 1,580 cycles —
every single gap within tolerance of its class, the four-gap total
impossible. So each candidate must total 14 estimates within half an
estimate, judged on the raw gap lengths, not the classes.

**The spacing check.** Now string the three sync bytes of a real train
together and read their gap stream. Each byte contributes its
long-medium-long-medium signature, and the hop from one byte's final
transition to the next byte's first is a single short gap:

```
gaps:        L M L M   S L M L M   S L M L M
                   ▲           ▲           ▲
candidate fires    1           2           3
```

The detector fires a candidate whenever the last four gap classes read
long, medium, long, medium — that is, at the end of each sync byte — so in
a genuine train, consecutive candidates arrive exactly **five gaps apart**:
the bridging short plus the next byte's four. The first candidate is held
*provisional*; only candidates at exactly the five-gap cadence extend the
train; a wrong-spaced candidate restarts it. The splice's overlapping
counterfeits, firing every two gaps, can never assemble three in cadence.
Only a completed three-candidate train — the full `A1 A1 A1` — arms the
parser at all.

**The record grammar.** The deepest defense assumes the worst: splice flux
that passes both timing checks (the Appendix documents a disk that
manufactured two timing-perfect counterfeit trains per revolution). Timing
having been exhausted, the decoder enforces *meaning* — the grammar every
formatter on earth obeys, because the WD1772's own operation depends on it:

- An ID address mark (`0xFE` after a qualified train) is always honored: it
  opens an ID field. There is nothing an attacker gains by counterfeiting
  one — its CRC will fail.
- A data address mark (`0xFB`/`0xF8`) is honored only if **armed**: a
  CRC-valid ID field must have immediately preceded it. An unsolicited data
  field is a contradiction in terms — no formatter writes data without its
  label — so an unarmed data mark is parsed past and discarded. Arming is
  consumed by use: one valid ID licenses at most one data field.
- A data mark must additionally carry the **zero-run credential**: its sync
  train must have begun on the heels of a preamble run of zeros. The
  numbers are Chapter 2's arithmetic: in a run of `0x00` bytes every cell
  boundary clocks, so one byte is eight shortest-class gaps, and the
  demanded run of at least sixteen is two bytes' worth — a deliberately
  modest slice of the twelve bytes every formatter writes. The run must
  have ended within six gaps of the train's first candidate, which is
  exactly as far back as the sync byte itself reaches: one bridging gap
  into it plus its four signature gaps stand between the last preamble gap
  and the candidate, with one gap to spare. Here the F011 asymmetry
  of Chapter 9 becomes decisive: *both* dialects write twelve zero bytes
  before every data field, but F011 ID fields have no preamble at all — so
  the zero-run requirement applies to data marks *only*. Demanding it for
  ID fields was tried, and it blinded the decoder to every F011 ID on the
  disk; the asymmetric rule is the exact shape of what both dialects
  guarantee.
- A qualified train followed by `0xFE` **re-anchors unconditionally** — even
  mid-field. If the parser is consuming a counterfeit data field when a
  genuine sync train and ID mark arrive, the truth wins instantly: the
  bogus parse is abandoned, the ID field opens. A legal payload cannot
  contain the missing-clock train, so re-anchoring can never be tricked by
  data; and this rule bounds the damage of *any* upstream misjudgment to
  "wasted gap bytes", never "a swallowed real sector".

The layering deserves a closing observation, because it is the decoder's
deepest lesson. The timing checks are *availability* devices — they keep
junk from wasting the parser's attention. The grammar and the CRC are the
*integrity* devices — with them in place, a counterfeit that defeats every
timing check still delivers nothing: it either fails CRC, arrives unarmed,
lacks the zero-run credential, or gets preempted by the next real ID field.
Junk is not merely filtered; it is rendered *harmless*. (The MEGA65's own
F011 decoder, it turned out, embodies the same philosophy in an even purer
form — permissive acquisition, ruthless validation — a convergence the
Appendix savors.)

The decoder that ships also carries its own history: a set of generics
(compile-time switches) can reconstruct each superseded qualification
design — the no-qualification variant, the refuted tight tolerance, each
historical gate combination — and the original fixed-window classifier
survives verbatim as a test-only reference entity, because the regression
harness races them all against the production decoder to this day, proving
with every run both that the old failures stay failed and that the fixes
stay necessary (Section B6.2).

### 14. The controller: media state and motion

The decoder of Chapter 13 turns flux into qualified, CRC-judged fields. The
**physical controller** (`physical_1581_controller.vhd`) turns those fields
into finished transactions, and the mechanism's switches and sensors into
honest answers for the drive computer. It is the largest module of the
physical side, and its work divides into three concerns: executing read
operations, moving the head, and — subtlest of all — maintaining the media
state the DOS believes in.

#### Read operations

The WD1772 model requests operations over a small internal interface: an
operation code, target cylinder and sector, and a request signal, answered
by a completion signal, a five-bit result code, and (for reads) the sector
bytes into the quarantine of Chapter 15. Three operations exist:

**Read Sector** hunts for an ID field matching the requested cylinder and
sector number with a valid CRC — matching C and R only; the head/side byte
is deliberately ignored, since the surface is already chosen by the side
pin, and the size code must announce 512 bytes (the only size a 1581
uses — anything else completes as "unsupported size" rather than
pretending). After a match, the armed data field must begin within the
WD1772's canonical 43 byte-times, or the controller abandons that pass and
resumes searching — the same recovery a real chip performs when a sector's
data field is damaged.

**Read Address** delivers the six bytes of the next ID field that flies
past — including its CRC bytes, and completing (with a distinct result
code) even when that CRC is bad, because the real chip does the same and
the DOS's positioning logic depends on it. One deliberate filter applies:
only ID fields with sector numbers 1 through 10 are eligible. This is the
answer to Chapter 9's truncated eleventh sector: the F011's CRC-valid
"sector 11" ID is real on the surface, and a genuine WD1772 would happily
report it — but the 318045-02 firmware, written for media that cannot
contain it, can be derailed by the reply at exactly the wrong moment
(proven by running the actual ROM against a faithful rotational model of
the track; Appendix, era 5). The physical drive therefore presents F011
media to the DOS as what the DOS understands: clean ten-sector 1581 media.
The decoder still sees and counts every ID field; the filter is a
compatibility view at the Read Address boundary only.

**Verify** confirms head position after a seek by finding any CRC-valid ID
field on the expected cylinder.

Every operation runs under budgets copied from the real chip's behavior:
five index pulses of searching before record-not-found, plus absolute
watchdogs (1.3 seconds of search, 1.1 seconds awaiting readiness) so that
no hardware state, however pathological, can wedge an operation forever.
Completions carry one inviolable rule, inherited from Chapter 8's status
epilogue: **a CRC failure never reports record-not-found at the same
time.** Chapter 8's four-row status table shows where that combination
lands — the `$CD5A` hole that reads as success; the controller's result
codes are designed so the combination cannot be emitted.

#### Motion

Head movement is a pulse-and-settle discipline: direction set up 24
microseconds ahead, a 4 microsecond step pulse, a minimum interval between
steps (3 milliseconds same direction, 4 on reversal), and an 18 millisecond
settling time before reading resumes. A Restore walks outward until the
track-0 switch closes — driven step by step by the WD1772 model, which owns
the command's logic and its 255-step give-up bound, while the controller
executes each individual step. The controller keeps a
**position estimate** — its belief about the current cylinder — anchored
whenever the track-0 sensor confirms the outermost position. The estimate
never gates operations (the DOS positions itself by Read Address, as
Chapter 8 described, and the controller lets it — seeks are driven by the
WD1772 model's own track register, exactly as in a real drive); the
estimate's real customer is the diagnostic trace.

The side-select mapping is recorded with unusual candor in the source: the
polarity between the CIA's side bit and the mechanism's `f_side1` pin was
established *empirically* — the pin-low surface is the one carrying the
head-0 sector IDs, the first half of a D81 — after a confident derivation
from documentation shipped inverted and was refuted by reading actual
sector headers from both surfaces. The code comment warns future
maintainers not to re-derive it. This book relays the warning.

#### Media state: readiness and disk change

Now the delicate part. Two mechanism truths — *is the disk rotating
stably?* and *has the disk been swapped?* — reach the DOS through the CIA
bits of Chapter 6, and the DOS's use of them (the one-shot readiness exam;
the change latch cleared by stepping) leaves no room for approximation.
The controller synthesizes both, and each synthesis carries a contract
refined on hardware:

**Readiness** is motor-on plus *proven rotation*: the controller asserts
`/READY` only after it has witnessed index edges from an actually spinning
disk. The tension is between how much proof to demand and how long the DOS
will wait — Chapter 8's readiness exam samples once, roughly 0.7 seconds
after motor-on, with no retry. Put the two cases on a timeline against
that deadline:

```
cold, changed, or newly enabled medium — demand a full witnessed revolution:

  motor on ──spin-up──▶ edge 1 ──── one revolution ────▶ edge 2 ► READY
                                                     worst case: spin-up
                                                     + up to 2 revolutions

same medium again after an ordinary motor stop — one fresh edge suffices:

  motor on ──spin-up──▶ edge 1 ► READY

  DOS deadline: one /READY sample at ~0.7 s ─── miss it once = error 74
```

Two edges — one full revolution witnessed edge to edge — is the honest
proof for a disk the controller knows nothing about. But spin-up plus up
to two revolutions (an index edge can be anywhere on the circle, so the
first edge alone may cost a whole turn) brushes right against the DOS's
deadline; a drive that misses it doesn't get a second chance, and the
command fails with error 74 while the disk spins innocently underneath.
The controller therefore keeps a memory, `rotation_confirmed`: once an
unchanged medium has passed the full two-edge qualification, an ordinary
motor stop does not revoke it, and the next spin-up asserts readiness
after a *single* fresh index edge — one revolution saved, comfortably
inside the window.

That memory is guarded jealously, and each guard answers a specific
question:

- *What earns it?* The second clean index edge of a motor-on interval,
  with no disk-change indication — the full cold qualification.
- *What revokes it?* Reset or disabling the feature; any assertion of the
  disk-change line, ever; and a stalled index — no edge for half a
  second with the motor commanded on — once the current spin-up has
  produced at least one edge (a disk that rotated and went silent is a
  disk to distrust).
- *Why not a stall before the first edge?* Because spindle acceleration
  can legitimately take longer than the staleness deadline, and revoking
  there would demote an innocent slow start back to the two-edge path —
  the exact deadline-miss the memory exists to prevent. The eject case
  loses nothing: a real eject always asserts the disk-change line, which
  is authoritative at every moment, first edge or not.
- *And whatever the history says,* readiness itself always waits for a
  fresh edge from the current spin-up — remembered rotation is never a
  substitute for present rotation.

Every one of those clauses corresponds to a failure observed or
constructed; the Appendix (era 5) tells them in order.

**Disk change** is a latch, as the mechanism defines it: set by eject,
cleared only when a completed head step observes the sensor released. The
controller adds one deliberate extension: the latch also sets on reset and
on backend switches — mounting the physical drive where an image was, or
back — so that *any* change of media identity, mechanical or virtual,
presents to the DOS as the disk change it truly is, forcing the firmware
to revalidate the disk rather than trust a stale directory cache.
Critically, readiness is *independent* of the change latch: an early
design that gated `/READY` on "change acknowledged" deadlocked the DOS on
first contact — its acknowledgment gesture (the step wiggle) can involve a
Restore at track 0 that steps zero times, never clearing the latch that
readiness was waiting on. The shipped rule: the latch guards *data*
validity (through its CIA bit and by aborting in-flight reads on a live
change), never *readiness*.

### 15. Delivery: the WD boundary

Between the controller's world (a sector is a transaction with a verdict)
and the drive computer's world (a WD1772 hands over bytes one DRQ at a
time, at disk pace, with LOST DATA for the tardy) sits the delivery layer.
Its design principle is the project's second architectural pillar, stated
once in Chapter 10 and enforced here: **nothing unvalidated ever reaches
the drive computer.**

The instrument is the **quarantine**: the 512-byte first-in-first-out
buffer between the clock domains. During a Read Sector, decoded payload
bytes stream into it as they arrive off the disk — speculatively, because
the sector's CRC verdict lies milliseconds away, at the field's end. The WD1772 model's presentation logic holds back until the
controller's completion arrives, matched to the request by a sequence tag
(a two-bit label that pairs each completion with its request, so a stale
completion from an aborted past cannot masquerade as the current one). A
*clean* completion opens presentation: bytes leave the quarantine at the
authentic pace — one every 32 microseconds — raising DRQ each time,
exactly as the image path and the real chip do. Any *other* completion —
CRC failure, record-not-found, abort — closes the path instead, and the
buffer drains internally, unseen: no byte, no DRQ, no trace. The DOS
observes only the honest outcome: an error status with an empty transfer.

```
decoder ──bytes, as they arrive──▶ ┌──────────────────────┐
                                   │   quarantine FIFO    │
                                   │ 512 bytes = 1 sector │
controller verdict (tag-matched):  └──────────┬───────────┘
                                              │
  clean ──────────────────────────▶ present at 32 µs pace, one DRQ per byte
  CRC error / not found / abort ──▶ drain internally — no byte, no DRQ
```

The cost is latency: a full sector waits its own read time again — about
16 milliseconds — before replay begins. The trade was accepted with eyes
open. Chapter 8's transfer loop has no deadline between BUSY set and the
first DRQ (the ROM polls patiently); what it cannot survive is corruption
in disguise. Speculative streaming was, in fact, the first implementation
— it fed hundreds of LOST DATA events and the stack bug of Chapter 8 in a
single failing directory load, and the quarantine was its refutation.

Presentation itself honors the WD1772's harsh timing truthfully. Bytes are
presented on schedule *whether or not the previous one was collected*; an
overrun overwrites the data register and raises LOST DATA — because the
flag must tell the truth, and only the truth. Two narrow exclusions defer
a presentation by a bus cycle (never skipping it): while the drive CPU is
mid-read of the data register, and during the one-cycle acknowledgment
pulse that clears DRQ after a read — closing a race in which a byte
landing at exactly the wrong clock edge would have its DRQ swallowed and
be falsely counted lost. Completion is equally careful at the tail: BUSY
outlives the final DRQ by at least one byte-time, because the transfer
loop polls BUSY *before* DRQ and would otherwise abandon the final byte in
the register.

Two more provisions round out the boundary. **Type I minimum busy:** a
seek that needs zero steps completes, physically, in under a microsecond —
and the DOS's wait-for-busy poll, running at 6502 speed, can miss the
entire command. Positioning commands therefore hold BUSY for a minimum
1.5 milliseconds in physical mode: long enough that firmware polling at
any cadence observes the edge, short enough to be invisible in operation.
**Mode isolation:** every one of these behaviors is gated on physical
mode. In image mode the delivery logic is, expression for expression, the
code that served D81 images before the physical drive existed — a
guarantee established the hard way, after a single unconditionally applied
"fix" (making the data register read back the value just written, which
the 1581 ROM's power-on self-test requires of real hardware) subtly broke
image-mode loading. The register now reads back per mode, and the isolation
is the subject of a standing regression argument: with physical mode off,
the drive computer must be bit-for-bit the proven MiSTer original.

### 16. Clocks, domains, and resets

Three clock worlds meet in the 1581 implementation, and their borders
explain several designs that otherwise look ornamental.

**The 50 MHz domain** (the QNICE clock) runs everything from the mechanism
pins through the decoder, the controller, the diagnostic device, and the
quarantine's write side. One domain, deliberately: gap measurement, the
adaptive estimate, CRC, and qualification all share one timebase with no
synchronization seams inside the signal path.

**The core clock domain** (about 31.53 MHz — the C64's world) hosts the
drive computer. Inside it, a fractional accumulator derives a 16 MHz
enable for the drive logic, divided further into the 6502's 2 MHz phases
and an 8 MHz enable for the WD1772 model. These are *clock enables*, not
clocks — the flip-flops all tick at the core clock; they merely sit out
most edges. (One consequence worth knowing: the "8 MHz" WD1772 pace
counter counts enabled ticks, so its constants — like the 252 ticks that
make the 32 microsecond byte pace — are calibrated in that unit.)

**The QNICE/Shell side** also owns SD-card access and the mount buffer —
in image mode, the vdrives engine hands blocks across this same border.

```
50 MHz domain (QNICE clock)                     core clock domain (~31.53 MHz)
                                                (drive at a 16 MHz enable; CPU
  input conditioner                             2 MHz, WD1772 model 8 MHz)
  decode chain            ──── toggles ─────▶
  controller              ◀─── + 2-bit tags ──    WD1772 model · T65 6502
  diagnostic device       ─ quasi-static     ─    8520 CIA · ROM · RAM · IEC
                             levels (2-FF sync)
  quarantine write side   ══ Gray-coded FIFO ═▶   quarantine read side
```

Signals crossing between the 50 MHz and core domains use the standard
toolkit, chosen per signal. Levels and quasi-static values (operation
parameters, which change only while the interface is idle) cross through
double-flip-flop synchronizers. Events cross as **toggles** — a request is
"this wire changed", immune to width mismatches between domains — with
the two-bit sequence tags of Chapter 15 pairing requests to completions.
The quarantine itself is the textbook case: an asynchronous FIFO with
Gray-coded pointers (successive values differing in one bit, so a pointer
sampled mid-change is off by at most one position, never garbage). Its one
non-negotiable rule: both sides reset together, from the same event — the
write side natively, in the reset's home domain, and the read side through
a synchronized copy — because a one-sided reset would leave the pointers
disagreeing forever after.

Resets follow the machine's hierarchy. The controller and decoder reset
with the QNICE domain; the drive computer resets with the core; and the
drive-type selection adds its own discipline — never more than one drive
engine (1541 or 1581) is out of reset at a time, because both wire into the
same IEC lines and the wired-AND bus takes contributions from anything
awake.
One documented, accepted hole: a QNICE-domain-only reset landing mid
operation would idle the controller without answering the drive computer's
outstanding request — harmless in this framework, where the QNICE reset
never fires without the core reset alongside.

### 17. Observability: the diagnostic device

Every hardware claim in this book — every "proven on real disks" — traces
to one instrument. There was never an oscilloscope or logic analyzer on
the drive signals; there was, instead, a purpose-built **diagnostic
device**: a read-only register bank inside the FPGA that the QNICE CPU can
inspect from its monitor console, exposing the physical drive's inner
life as numbers.

The device occupies QNICE device ID `0x0108` and presents 64 scalar words
plus a 32-entry trace ring. The scalars are live values (controller state,
the adaptive estimate, index period and width, head estimate) and
saturating event counters: index edges raw and qualified, decoded ID
fields, CRC verdicts, gap classification failures, A1 candidates and
qualified trains and span rejections, address marks seen and refused,
delivery events — the decoder's and controller's every meaningful decision,
countable. The trace ring records the last 32 mechanism-level events —
each completed step, each read request, each completion with its result —
packed into two words each; position, not timestamps, carries the
chronology (the newest entry's slot follows from the event counter).

The design principle that made this modest window sufficient is **exact
accounting**. The instrumentation is built so that healthy sessions
balance to the last event: the trace count equals steps plus two entries
per operation; A1 candidates arrive in threes per qualified train; ID
fields per revolution match the format's arithmetic. Against that
bookkeeping, a single anomaly — one unexplained event, one counter off by
one revolution's worth — localizes a fault to a layer, often to a signal,
without any waveform. The Appendix is, in large part, a record of this
method working: readiness failures distinguished from decode failures from
delivery failures, on evidence of counters alone; even a disk slipping on
its spindle clamp was diagnosed from the index-period word.

The device's register map, access procedure from the QNICE monitor, and
per-word documentation live in the maintained reference,
[the debug-device reference](1581_dd_debug_device.md) — the authority on
addresses and encodings, at register-map version 7 (the `VERSION` word
reads `0x07FF`). This book deliberately does not duplicate its tables;
Section B2.4 describes the implementing module.

### 18. Boundaries and safety

Honest engineering states its edges. As of the read-only milestone this
book describes:

**The physical drive cannot write. Physically.** On every board revision,
the top-level FPGA design ties the mechanism's write-gate and write-data
lines inactive — constants, not signals. No register, no firmware
command, no bug below the top level can energize the write head. A
diskette in the MEGA65's slot is as safe under this core as under a
write-protect tab. (This is why the DOS reports "write protect on" if
asked to save: the WD1772 model surfaces the milestone as the drive-level
condition firmware already understands.) The write milestone, when it
opens, is planned as its own safety-scoped effort — a capability interlock
defaulting off, simulation-proven write and format paths, then sacrificial
media qualification — and nothing in it is entered lightly, because the
step from "cannot write" to "chooses not to write incorrectly" is the
step that risks user data.

**Double density only.** The DD data rate and geometry of Chapter 7 are
assumed throughout; high-density media are outside the milestone (the
density-select pin is held to the DD-safe level).

**One drive.** The core instantiates a single virtual drive, device 8;
the physical backend binds to it. (The 1541 coexists as device 8's
alternate personality for D64 images, selected by image type — a
different machine sharing only the IEC wiring and the mounting plumbing.)

**Read Track and Write Track are not implemented** (in either mode — an
inheritance from the upstream WD1772 model, which completes them as
no-operations). No mainstream DOS operation uses Read Track; Write Track
is formatting, which belongs to the write milestone.

**Qualification boundary.** The physical path is feature-complete on all
four board revisions but was hardware-qualified on R3, against
F011-written double-density media, across cold starts, warm and stopped
motor restarts, eject and reinsert cycles, and concurrent IEC load
stress. Stock media written by a genuine 1581 pass the same decode logic
in simulation byte-exactly — the formatter layouts differ only within
what the decoder explicitly accepts — but a community-tested pass on
genuine-1581-written physical disks remains the open acceptance gate, and
the project treats it as evidence to be collected, not assumed.

These are the boundaries. Within them stands the claim the previous eight
chapters have earned: a C64, a real DOS, a real mechanism, and a real
magnetized disk, connected end to end through logic that measures time,
qualifies structure, proves integrity, and only then — paced like 1987 —
hands the bytes up the stack.

## Section B — The Code, File by File

Section A told the story; this section opens the hood. Every source file
that implements the 1581 — the physical decode chain, the controller, the
drive computer, the peripherals, the integration glue, and the tests that
guard them all — gets a walk-through here: its role, its interface, how it
works, and the details a maintainer needs before touching it. Entries
assume Section A's concepts and point back to the chapters that teach
them; acronyms are nonetheless spelled out again on first use in this
section, because reference readers jump straight in.

This section is written to be readable *without the source code open*, and
three conventions serve that. First, nontrivial entries begin with an
**anatomy card** — a small diagram of the entity as a box, its connections
grouped by role, its clock domain named — so that when the prose later
says "the request toggle" or "the image path", you have already seen where
that lives. (The one exception is B1.1, a package of constants with no
ports; the B1 group's chain map additionally shows how its six stages
connect.) Second, the files with real machinery inside get a short
**walked example**: one concrete operation traced through the file, so the
mechanism is seen running once before it is described at rest. Third, the
entries are layered by altitude: each one moves from role to mechanism to
fine detail, and the finest stratum — exact constants, edge cases,
register quirks — is maintainer material. If you are reading cover to
cover, you have an explicit license to skim those passages; nothing later
in the book depends on them. Signal names in `backticks` are lookup keys
into the source for the day you open it; the prose around them is written
to survive without them. File groups follow
the architecture, bottom-up on the physical side first: the decode chain
(B1), the controller and delivery (B2), the MiSTer-heritage drive proper
(B3) and its peripherals (B4), the glue that wires everything into the
core (B5), and the test suites (B6).

### B1 — The decode chain (CORE/vhdl/physical_1581/)

The seven files in this group form the read side of the physical 1581 drive: raw flux pulses from the mechanism's read head go in, decoded and checksum-verified sector IDs and data bytes come out. Four small pipeline stages transform the signal step by step, a cyclic redundancy check (CRC) engine runs alongside, a decoder wraps all of them in the qualification logic that decides when a byte boundary can be trusted, and a shared package supplies every timing constant. Here is the whole group as one picture — the map that the seven entries below unfold, station by station:

```
flux from the mechanism: f_rdata, one pulse per transition (conditioned by B2.2)
     │
  ┌──┼──────────────────── B1.6  physical_1581_mfm_decoder ───────────────────┐
  │  ▼                                                                        │
  │  B1.2  mfm_gaps             measures the time between two transitions —   │
  │  │                          one gap; merges electrical runts away         │
  │  ▼                                                                        │
  │  B1.3  mfm_quantise         classifies each gap short / medium / long     │
  │  │                          against the adaptive half-cell estimate       │
  │  ▼                                                                        │
  │  B1.4  mfm_gaps_to_bits     unfolds classes into data bits; fires an      │
  │  │                          A1 candidate on the long-med-long-med tail    │
  │  ▼                                                                        │
  │  B1.5  mfm_bits_to_bytes    assembles bits into bytes, realigning the     │
  │  │                          byte boundary at every sync                   │
  │  ▼                                                                        │
  │  field parser (B1.6 itself) qualifies A1 trains, enforces the record      │
  │  │            ▲             grammar, walks the ID/data field states       │
  │  │            └─ B1.7  crc  renders the CRC-16 verdict on every field     │
  │  ▼                                                                        │
  └──┼────────────────────────────────────────────────────────────────────────┘
     ▼
qualified fields — ID bytes, data bytes, CRC verdicts — to the controller (B2.1)

      every stage reads its timing constants from B1.1  physical_1581_pkg
```

The outer box is literal: `physical_1581_mfm_decoder` instantiates the four stages and the CRC engine, which is why B1.6 is both a station in the chain and the roof over all of it — and why this group reads bottom-up so naturally, foundation first (B1.1), then the stations in signal order, then the roof. Everything in this group lives in a single clock domain, the 50 MHz QNICE-domain clock `c64_clk_sd_i` (QNICE is the 16-bit helper CPU of the MiSTer2MEGA65 (M2M) framework; its clock simply happens to be the convenient 50 MHz source). Section A Chapter 13, the adaptive MFM decoder, teaches the algorithm these files implement as one continuous story; the entries below describe what each file contributes to it. MFM — Modified Frequency Modulation, the line code that stores data in the spacing of flux transitions — and the rest of the magnetic vocabulary are developed from scratch in Section A Chapters 1 through 3.

#### B1.1 physical_1581_pkg.vhd

Every magnetic-timing figure of the physical 1581 read path lives in this one file: how long a legal interval between two flux transitions may be, how far the adaptive estimate may wander, how many clock cycles a decoded byte spans. The package exists so that a future profile freeze — re-tuning the drive's timing personality — touches one file only, as its header puts it. Every other file in the decode chain consumes it, and so do the controller and the diagnostic block one group over (B2.1, B2.4). It is a VHDL package (VHDL being the hardware description language most of this project is written in), so it has no entity and no ports: it declares constants, two subtypes of codes, and a package body with two helper functions, `cyc_us` (exact microseconds-to-cycles conversion) and `cyc_ns` (nanoseconds-to-cycles, rounded to nearest).

All timing derives from a single anchor: `C_FDC_HZ = 50_000_000`. One cycle is 20 ns (`C_PERIOD_NS`), and 50 cycles make a microsecond (`C_CYC_PER_US`). The header notes a deliberate non-choice: the MEGA65-native "0x51" clock divisor is not used, because it is specific to the MEGA65's 40.5 MHz domain and this path runs at exactly 50 MHz. From that anchor the double-density (DD) MFM figures follow — 250 kbit/s at 300 revolutions per minute (RPM):

| Constant | Value | Meaning |
| --- | --- | --- |
| `C_HALF_CELL_CYC` | 100 cycles (2 µs) | one MFM half-cell, the clock-or-data time slot |
| `C_GAP_SHORT_CYC` | 200 cycles (4 µs) | nominal short gap, two half-cells |
| `C_GAP_MED_CYC` | 300 cycles (6 µs) | nominal medium gap, three half-cells |
| `C_GAP_LONG_CYC` | 400 cycles (8 µs) | nominal long gap, four half-cells |
| `C_BYTE_CYC` | 1600 cycles (32 µs) | one decoded byte |

What makes this package worth a careful read, though, is not the arithmetic — it is the three large comment blocks that preserve the design's history as documentation of record. The first block keeps the legacy fixed classification windows (`C_GAP_SHORT_LO/HI = 160/240`, `C_GAP_MED_LO/HI = 258/342`, `C_GAP_LONG_LO/HI = 355/445` cycles). Production code has not used them since the adaptive quantiser arrived; they remain because they define the behavior of the test-only fixed-window classifier `ref_mfm_quantise_fixed.vhd` in the codec testbench, and because the reason for abandoning them deserves to stay visible: on inner cylinders (60 and up), peak shift pushed real gaps into the dead-bands between the windows (241..257 and 343..354 cycles) for whole revolutions at a time, causing loss of lock and persistent Record Not Found (RNF) errors.

The second block documents the write-splice sync qualification and the two refuted designs that preceded it. It records the hardware regression the first adaptive quantiser introduced — track 39, sector 1, the sector holding the D81 (1581 disk-image format) header and Block Availability Map (BAM), became deterministically unreadable, because splice garbage alternating roughly 446- and 344-cycle gaps reads exactly like the sync pattern under dead-band-free acceptance and opened bogus data fields that swallowed the following sector every revolution. It then records why two plausible fixes were rejected: a tight acquisition tolerance of a quarter-estimate fails because inter-symbol interference (ISI, also called peak shift) deviates every gap of a genuine sync train by twice the shift amount, so junk and legitimate deviations overlap and no per-gap tolerance can separate them; and a required run of preceding short gaps fails because the pinned MEGA65 F011 formatter (the F011 is the MEGA65's native floppy controller) writes sector IDs directly after 0x4E gap bytes with no zero preamble — on hardware that gate decoded zero IDs on every cylinder. Production instead qualifies structure both formatters must share: the three A1 sync marks themselves, via the constants `C_QUANT_A1_SPACING = 5` gap events, `C_QUANT_A1_CELLS = 14` half-cells, and `C_QUANT_A1_SPAN_TOL_SHR = 1` (a whole-word tolerance of half the estimate). The superseded preamble constants `C_QUANT_SYNC_RUN = 16` and `C_QUANT_SYNC_LAT = 6` remain declared — partly for the A/B harness's historical columns (B6.2), partly because the decoder still uses them for its data-field lock-up gate (B1.6).

The adaptive quantiser family sits between those stories: `C_QUANT_FRAC = 4` fraction bits (the estimate is Q8.4 fixed point — eight integer bits, four fraction bits, so sixteenths of a cycle), the clamp `C_QUANT_EST_MIN/MAX = 90/110` cycles (±10 %), the acceptance shift `C_QUANT_TOL_SHR = 1` (windows of half the estimate, touching at the midpoints), and the adaptation step `C_QUANT_STEP_Q = 2` (one eighth of a cycle). Its comment records why the update is sign-based rather than the originally drafted proportional form; B1.3 walks that argument in full. A separate note above `C_GAP_GLITCH = 16` cycles (320 ns) preserves the runt-threshold story: an earlier value of 120 could merge away a real edge when noise landed late in a gap, silently corrupting the stream instead of failing loudly.

The remainder is bookkeeping shared across the physical path: the 5-bit backend result codes (`RES_OK` through `RES_INTERNAL_FAULT`, including `RES_RECORD_NOT_FOUND` and `RES_MISSING_DAM`), the 3-bit read-operation codes (`RDOP_READ_SECTOR` and friends), the decoded address-mark values (`MARK_A1 = 0xA1`, raw word 0x4489; `MARK_C2 = 0xC2`, the index mark, raw 0x5224 — defined here but not decoded by this chain; `MARK_FE`, `MARK_FB`, `MARK_F8`), the CRC sanity anchor `C_CRC_AFTER_3XA1 = 0xCDB4`, and `C_SIZECODE_512 = 0x02`, the only sector size the 1581 uses. The three comment blocks compress several eras of the issue #90 effort into a few screens; Appendix C2, the eras, tells the same story chronologically with dates and commits. Section A Chapter 13 explains the algorithm these constants parameterize.

#### B1.2 physical_1581_mfm_gaps.vhd

```
 synchronized flux ─────▶ ┌─────────────────────────┐──▶ gap: one valid pulse +
 (active-low, from        │ physical_1581_mfm_gaps  │    16-bit length in cycles
 the B2.2 conditioner)    │  50 MHz (QNICE clock)   │──▶ runt: one pulse per
                          │  no generics            │    merged glitch (to diag)
                          └─────────────────────────┘
```

Stage one of the read pipeline turns the electrical view of the disk — a train of active-low pulses on the RDATA line, one per flux transition — into the decoder's raw datum: the gap, the measured interval between two successive transitions. This is the only stage that touches time directly; everything downstream reasons about gap lengths, never about the clock.

The card is nearly the whole interface. Two facts complete it: the flux input must arrive already two-flip-flop synchronized — the B2.2 conditioner guarantees that — and the runt pulse is pure bookkeeping, traveling up through the decoder to the diagnostics without influencing anything.

The mechanism is a free-running counter (integer, saturating at 65535 — about 1.31 ms — rather than wrapping) that increments every clock. A two-stage register pipeline on `f_rdata_i` detects the start of a pulse as `last_rdata = '0' and last_last_rdata = '1'`; on that edge the accumulated count is emitted as one gap and the counter restarts. The edge-detection timing is kept bit-for-bit from the file's ancestor, `mfm_gaps.vhdl` in mega65-core (the MEGA65 project's own code base for its system FPGA — field-programmable gate array), by Paul Gardner-Stephen, under the GNU Lesser General Public License v3 (LGPLv3), at commit `a9158930`.

Two refinements distinguish this stage from its ancestor. The first is the runt filter: a gap shorter than `C_GAP_GLITCH` (16 cycles, 320 ns) cannot be a legitimate DD flux interval — the shortest valid gap is an order of magnitude longer — so it is treated as an electrical glitch. Crucially, the runt's edge is dropped but its time is not: the counter keeps counting, so the runt's length merges into the following gap, and downstream stages see only clean, full-length gaps. Each merge pulses `runt_o` once. The hardware evidence that motivated the filter is memorable — the diagnostic device once reported a minimum gap of 0x0001, meaning two RDATA edges 40 ns apart had reached the decoder. The second refinement is the first-edge rule, tracked by the `seen_edge` flag: a gap is the interval between two edges, so the first edge after reset only starts the first gap and emits nothing — neither a gap nor a runt. Without this rule the first edge emitted a bogus reset-relative interval, harmless for decoding but polluting the runt and gap statistics, because the controller resets the decoder at every operation start, frequently within a few cycles of the next real edge.

The threshold's own history — introduced at 120 cycles, retuned to 16 after a silently corrupted sector traced back to a merged real edge — is preserved above `C_GAP_GLITCH` in the package (B1.1) and told in full in Appendix C2. Section A Chapter 2 explains why flux transitions, not levels, carry the data; Chapter 13 places this stage at the head of the decode chain.

#### B1.3 physical_1581_mfm_quantise.vhd

```
 gap stream (valid + ───▶ ┌────────────────────────────┐──▶ classified gap: valid
 16-bit length)           │ physical_1581_mfm_quantise │    + 2-bit class (short /
 in-field hint ─────────▶ │    50 MHz (QNICE clock)    │    medium / long, or the
 (inert in production)    │                            │    loud invalid, 11)
                          │  generics: two tolerance   │──▶ the live estimate,
                          │  tiers + adaptation switch │    Q8.4 — a diagnostic
                          │  — A/B-harness knobs       │    tap only
                          └────────────────────────────┘
```

Stage two answers the central question of MFM clock recovery: is this gap two, three, or four half-cells long? On paper the answer is a pair of comparisons; on a real disk, where motor speed drifts and peak shift smears every transition, it is the heart of the whole design. This file is the adaptive quantiser — the component that replaced the fixed windows of B1.1's legacy block and the single biggest reason the physical path reads far cylinders reliably. It plays the role a phase-locked loop (PLL) data separator plays in a classical floppy interface, implemented as pure digital arithmetic.

Beyond the card, four semantics matter. The generics set the acceptance tolerance while hunting for a sync, the tolerance inside a field, and whether every accepted gap adapts the estimate — at the production defaults the two tolerances are equal and adaptation is unconditional, which is exactly why the card calls the in-field hint inert. The reset re-seeds the estimate. Every incoming gap produces exactly one classification event downstream, accepted or not. And the estimate output is a one-way street: threaded through decoder and controller to the diagnostic device's word 0x36, never read back into any behavior.

The whole stage owns one register: `est_q`, the live half-cell length in Q8.4, seeded to nominal 100.0 cycles and clamped to 90.0..110.0. Per valid gap, all in sixteenths of a cycle: the gap is classified to the nearest class by comparing it against the midpoints `2.5*est` and `3.5*est` (an exact midpoint goes to the higher class); the error `e = G - n*est` against the chosen class center is then tested against a tolerance of `est/2` (the shift selected by `field_i`). With a half-estimate tolerance the acceptance windows touch at the midpoints: every gap between `1.5*est` and `4.5*est` — nominally 150 to 450 cycles, 3 to 9 µs — receives a class, and there are no dead-bands at all. On acceptance the estimate adapts by a fixed step of one eighth of a cycle in the sign of the error (zero error, no step) and is hard-clamped. On rejection the stage emits class 11, loss of lock, and re-seeds the estimate to nominal — as loud a failure as the old fixed windows ever produced. Since the decoder resets this stage at every operation start, idling and re-searching re-seed too.

The sign-based step is the file's quiet masterstroke, and its header explains why at length: under peak shift, short gaps only ever lengthen and long gaps only ever shrink, so a proportional estimator averaging magnitudes has a biased equilibrium (Chapter 13 draws the lopsided error distribution that makes the bias visible) — the A/B margin harness (the testbench that races algorithm variants over synthetic gap streams; B6.2) showed it dragged to the +10% clamp and then lost to the fixed windows it was meant to beat. A uniform step converges instead to the median of the per-gap error, which the unshifted majority of gaps anchors at the true motor speed. Convergence is quick: one eighth of a cycle per accepted gap reaches either clamp from nominal in 80 gaps.

Details worth knowing. First, a consequence the header states explicitly: with production generics — both tolerance generics equal and `G_HUNT_ADAPT_ALL` true — `field_i` has no behavioral effect whatsoever. The hunting-versus-in-field machinery is real, wired, and currently inert; it exists so the harness can instantiate the refuted tight-acquisition variant (`G_TOL_ACQ_SHR = 2`, a quarter-estimate window) and the superseded shorts-only adaptation rule as permanent regression columns. Second, the no-dead-band design still rejects genuine noise: a stable 126-cycle artifact measured on the test disk falls below `1.5*est` for every legal estimate (135 cycles at the lowest clamp) and classifies as a loud class 11. Third, lineage: this stage replaces a fixed-window classifier adapted from mega65-core's `mfm_quantise_gaps.vhdl` at `a9158930`; the old architecture survives verbatim as the reference entity `ref_mfm_quantise_fixed.vhd` in the codec testbench (B6.1).

The estimator bake-off and the refutation of the tight acquisition tier are two of the project's best stories; Appendix C2 tells both. Section A Chapter 13 develops the algorithm from first principles.

#### B1.4 physical_1581_mfm_gaps_to_bits.vhd

```
 classified gaps ─────▶ ┌────────────────────────────────┐──▶ data bits: bit value
 (valid + class)        │ physical_1581_mfm_gaps_to_bits │    + valid pulse
                        │     50 MHz (QNICE clock)       │──▶ sync pulse: the last
                        │     no generics                │    four classes matched
                        │                                │    the A1 fingerprint
                        └────────────────────────────────┘
```

Stage three converts classified gaps into two things the byte layer needs: decoded data bits, and the sync pulse that says "an A1 sync mark just ended here." It performs both jobs from the same input stream, independently, every time a new gap class arrives.

The card leaves only one routing fact untold: the bits feed stage four, but the sync pulse is consumed by the decoder directly for its train qualification (B1.6) — an A1 candidate bypasses the byte layer entirely.

Sync detection first. The last four gap classes are kept in an 8-bit shift history, `recent_gaps`, shifted left by two per gap; a candidate fires when the history equals the constant `sync_gaps = "10011001"` — reading oldest to newest, long, medium, long, medium. That is precisely the tail of the raw A1 word 0x4489: written out in binary as flux positions, its transitions sit 4, 3, 4, and 3 half-cells apart (the file's header phrases the same lengths as 2.0, 1.5, 2.0, 1.5 full cells — the same thing in different units). On a match the stage pulses `sync_o`, flushes any pending bits from the queue, and forces its `last_bit` state to '1', because an A1 ends in a one and the following bits are decoded relative to it.

Bit decoding is a lookup on the pair (previous emitted bit, gap class), and it emits one or two bits per gap:

| Previous bit | Gap class | Emitted bit(s) |
| --- | --- | --- |
| 0 | short | 0 |
| 1 | short | 1 |
| 0 | medium | 1 |
| 1 | medium | 0 0 |
| 0 | long | 0 1 |
| 1 | long | 0 1 |

Section A Chapter 2 derives this table from the MFM encoding rules; here it is simply cast as a case statement. Emitted bits enter a two-deep queue (`bit_queue`/`bits_queued`) and drain one per clock, so a two-bit gap occupies two consecutive cycles on `bit_valid_o`. The queue is always empty long before the next gap arrives — even the shortest acceptable gap is at least 135 cycles away.

One deliberate deviation from the upstream algorithm, called out in the header: an invalid class 11 now drops lock. It clears `recent_gaps`, the bit queue, and the pending-sync state instead of silently emitting nothing, so a loss of lock can never leave a stale partial sync pattern in the history for later gaps to complete into a phantom candidate. Everything else — the bit table and the sync comparison — is kept bit-for-bit from mega65-core's `mfm_gaps_to_bits.vhdl` at `a9158930` (Paul Gardner-Stephen, LGPLv3).

A candidate from this stage is necessary but not sufficient evidence of a real A1 — write-splice garbage can fake the four-class pattern — which is exactly why the decoder above subjects every `sync_o` pulse to the span and spacing gates described in B1.6. Section A Chapter 13 covers that division of labor.

#### B1.5 physical_1581_mfm_bits_to_bytes.vhd

```
 bits + valid ────────▶ ┌─────────────────────────────────┐──▶ assembled byte +
 sync pulse (realigns ─▶│ physical_1581_mfm_bits_to_bytes │    valid pulse
 the byte boundary)     │      50 MHz (QNICE clock)       │──▶ sync out: "an A1
                        │      no generics                │    stands here" — an
                        │                                 │    event, not a byte
                        └─────────────────────────────────┘
```

Stage four is the shortest file in the chain, and its brevity is the lesson: on floppy media, byte alignment is not something you compute — it is something the sync marks tell you. A raw bit stream has no self-evident byte boundaries; the only authority is the A1 sync mark, whose position defines where bytes begin. This stage does nothing more than obey that authority.

On the sync pulse the stage emits the literal byte 0xA1 on `byte_o` together with `sync_o`, and resets its bit counter to zero, re-aligning the byte boundary to the end of the sync mark. Note what it does not do: it does not assert `byte_valid_o` for a sync. Sync marks travel on their own strobe, deliberately kept apart from the data-byte stream — the decoder must never confuse a sync's 0xA1 with an ordinary data byte that happens to be 0xA1, because only the former carries the missing-clock violation that makes it unmistakable on the medium. (In practice the decoder does not even consume this stage's `sync_o`; its A1 accounting hangs off stage three's pulse directly, and the 0xA1 it feeds to the CRC engine is synthesized in the decoder itself. The mirrored strobe keeps the stage's interface complete and self-describing.)

Otherwise the stage shifts `bit_i` most-significant-bit-first (MSB-first) through the 7-bit `partial_byte` register; on the eighth bit it assembles the full byte and pulses `byte_valid_o` for one cycle. That is the whole mechanism. The framing logic is kept bit-for-bit from mega65-core's `mfm_bits_to_bytes.vhdl` at `a9158930` (Paul Gardner-Stephen, LGPLv3), with the project's usual adaptations: ports renamed to the `_i`/`_o` convention, simulation-only debug machinery removed, and an explicit synchronous reset added.

Section A Chapter 3 explains why the track format sprinkles sync marks before every field — precisely so that this trivial re-alignment is always possible; Chapter 13 shows the stage in context at the end of the pipeline.

#### B1.6 physical_1581_mfm_decoder.vhd

```
 synchronized flux ───▶ ┌───────────────────────────────┐──▶ ID group: valid pulse,
 (the whole chain       │  physical_1581_mfm_decoder    │    C/H/R/N, CRC-ok flag
 lives inside this      │     50 MHz (QNICE clock)      │──▶ data group: start,
 box — see the B1       │                               │    byte stream, end,
 chain map)             │  generics: six A/B-harness    │    CRC-ok, deleted flag
                        │  knobs that resurrect each    │──▶ status: lock, loud gap
                        │  superseded design;           │    error, A1/span/DAM
                        │  production runs defaults     │    event pulses, CRC and
                        │                               │    estimate taps
                        └───────────────────────────────┘
```

This file is where the pipeline becomes a decoder. It instantiates the four stages of B1.2 through B1.5 and the CRC engine of B1.7, and adds the two things the naive chain cannot provide on its own: proof that a sync is really a sync, and a field FSM (finite state machine) that parses the qualified byte stream into ID fields and data fields. It is deliberately ignorant of sectors and operations — matching a decoded ID against the wanted sector, budgeting revolutions, and reporting results are the controller's job (B2.1). The decoder's contract is simpler: every time a well-formed field passes under the head, report it, with its CRC verdict, exactly once.

The entity `physical_1581_mfm_decoder` takes six generics, all of them test-only knobs for the A/B margin harness; production instantiates the defaults everywhere. `G_SYNC_GATE` (default true) set false restores the original adaptive-quantiser behavior in which every stage-three sync pulse counts immediately. `G_SYNC_PREAMBLE_GATE` (default false) set true selects the superseded preceding-run-of-shorts rule as a permanent regression column. `G_SYNC_SPAN_GATE` (default true) set false preserves spacing-only acquisition (the behavior of commit `3803152`), and `G_RECORD_SEQUENCE_GATE` (default true) set false preserves pre-record-grammar behavior (commit `0ab9f92`). `G_QUANT_TOL_ACQ_SHR` and `G_QUANT_HUNT_ADAPT_ALL` pass through to the quantiser — note that the quantiser's field-tier tolerance generic is not passed through and always keeps its production default. These generics are how the refuted designs recorded in B1.1's comment blocks stay executable: the harness (B6.2) instantiates seven decoder variants side by side and races them, so every design claim in the comments remains a running experiment rather than folklore.

The ports fall into three groups — they are the pulses of the walk below, under their formal names. The decoded-ID group: `id_valid_o` pulses once per completed ID field, with `id_c_o`/`id_h_o`/`id_r_o`/`id_n_o` (Cylinder, Head, Record and size-code Number — the four bytes of an ID field), `id_crc_ok_o`, and `id_crc_stored_o`, the CRC as stored on disk, first byte in bits 15..8. The decoded-data group: `data_start_o` pulses when a data address mark (DAM) is accepted, `data_byte_o`/`data_byte_valid_o` stream each payload byte, and `data_end_o` closes the field with `data_crc_ok_o` and `data_deleted_o`. The status and diagnostics group: `locked_o` (separator locked), plus one-cycle event pulses — `gap_error_o`, `runt_o`, `a1_candidate_o`, `a1_span_reject_o`, `a1_train_o`, `mark_fe_o`, `mark_dam_o`, `dam_unarmed_o` — and the taps `last_gap_o` (raw length of the last gap), `crc_value_o` (the live CRC register), and `est_o` (the quantiser estimate). The diagnostic device counts the pulses and exposes the taps (B2.4; Section A Chapter 17).

Three qualification layers stand between a stage-three sync pulse and an open field. Layer one is the aggregate span check: alongside the quantiser's classes, the decoder retains the raw lengths of the last four gaps (`a1_gap_0..3`), because the class detector alone loses their combined timing. A combinational process compares their sum against the expected span of a complete raw A1 — 14 half-cells, `C_QUANT_A1_CELLS`, at the current estimate — within a tolerance of half the estimate. The tolerance is deliberately broad for individual jitter yet lethal to coherent junk: legitimate peak shift moves transitions substantially but its internal movements cancel end to end, whereas splice residue such as the 446/344/446/344 pattern passes every per-gap window and still totals 1580 cycles against a nominal 1400 — that is, 14 half-cells at the 100-cycle nominal estimate, with the half-estimate tolerance accepting 1350 to 1450, so 1580 misses by a wide margin and is rejected structurally (Chapter 13 draws the complete word). A failed span not only discards the candidate; it clears any provisional train and pulses `a1_span_reject_o`.

Layer two is exact train spacing. Consecutive A1 bytes in a genuine A1 A1 A1 train produce candidates exactly `C_QUANT_A1_SPACING = 5` quantised gap events apart — one short bridging gap plus the four gaps of the next A1's tail. The decoder counts gaps since the last candidate in `sync_gap_age` (saturating at 15, meaning "no preceding candidate"). The first surviving candidate is provisional: the CRC is preset and fed an A1 in the same cycle, `sync_cnt` becomes one, but `locked_o` stays low. Each following candidate joins the train only if it arrives at exactly five gaps; the third member raises `locked_o` and pulses `a1_train_o`. Any other spacing restarts the train with this candidate as a new provisional first A1. This is the gate that killed the write-splice failure mode: junk chains fire overlapping candidates two gaps apart and can never reach a count of three. And unlike a preamble requirement, it tests the address-mark train itself, so it is formatter-independent — stock 1581 tracks and MEGA65 F011-formatted tracks differ in their lead-ins but must both contain the same three A1s.

Layer three is the record grammar — the IBM-style ID-before-data sequencing rule that the WD1772 (the Western Digital floppy-disk controller in a real 1581) relies on, enforced here because a timing-valid splice can still contain a complete A1-like train. Two flags implement it. `data_armed` is set only when an ID field completes with CRC residue zero, and is consumed when a DAM opens a data field or an FE starts a new ID. `data_preamble_ok` is captured at the first A1 of each train and records whether the train began within `C_QUANT_SYNC_LAT = 6` gaps of a run of at least `C_QUANT_SYNC_RUN = 16` consecutive short-class gaps — two bytes of 0x00, the lock-up run both formatters write before every data field. The gate is deliberately DAM-only, because F011 ID fields do not always have a zero preamble. A DAM byte (0xFB normal, 0xF8 deleted) arriving with a complete train opens a data field only if both flags are set; otherwise it pulses `dam_unarmed_o` and is ignored. An FE after a complete train, by contrast, is trusted unconditionally — a legal MFM payload cannot contain the missing-clock A1-times-three-plus-FE sequence — and if the FSM is mid-field when one arrives, it re-anchors the parser outright, aborting the bogus parse and jumping straight into ID decoding.

The field FSM itself is plain by comparison. With a complete train, the next assembled byte is the mark: FE leads through `S_ID_C..S_ID_N` (latching C, H, R, N) and two stored-CRC states; FB or F8, if armed, latches the deleted flag and streams `data_len(last_n)` payload bytes — 512 for the 1581's universal size code two, with `last_n` remembering the most recent ID's N — through `S_DATA` and its CRC states. Every field byte, the three A1s (fed synthetically, since stage four signals syncs on a separate strobe), and the mark all pass through the CRC engine; after the second stored CRC byte, a CHECK state waits `chk_cnt = 12` clocks for the bit-serial engine to finish shifting, then publishes results in a single pulse. `sync_cnt` is cleared on every consumed byte, so a train must be immediately followed by its mark. A class 11 from the quantiser aborts everything, loudly: `gap_error_o` pulses, lock drops, the FSM returns to idle, and every gate closes.

**One ID field, walked.** Follow a single directory-track ID field through the gates, streaming in off a healthy disk. The twelve preamble bytes arrive first: ninety-six shortest-class gaps, marching the short-run counter far past its threshold of sixteen. The first sync byte's four defining gaps fire an A1 candidate; its raw lengths pass the span check; the train goes provisional at one. Five gaps later the second candidate lands exactly on cadence — two — and five more bring the third: the train is complete, lock is asserted, and the preamble credential is captured for whatever mark follows (the zero run ended five gaps before the first candidate, inside the window of six). The next assembled byte is 0xFE, so the FSM steps through the four label states — cylinder 39, head 0, record 3, size code 2 — then the two stored CRC bytes. Twelve clocks of CHECK while the bit-serial engine drains, the residue compares equal to zero, and the file speaks three pulses upward: an ID is valid, its CHRN is on the bus, and the data arm is set for the field about to follow.

Details worth knowing. `field_active`, the signal driving the quantiser's `field_i`, is true in production only when the FSM has left idle or a complete train is pending — a provisional first A1 does not switch adaptation tiers. `id_valid_o` pulses whether or not the CRC matched; interpreting a bad ID is the controller's decision. `data_deleted_o` is registered at data-end while the controller samples it at data-start, a one-field lag that is harmless on D81 media, where every DAM is FB. Unsupported mark bytes after a train are simply ignored. The generics' commit references and the round-by-round path to the three-layer design are the centerpiece of Appendix C2; Section A Chapter 13 explains the algorithm, and Chapter 14 what the controller builds on top of these pulses.

#### B1.7 physical_1581_crc.vhd

```
 byte + feed pulse ───▶ ┌──────────────────────────┐──▶ running CRC-16 value
 preset pulse ────────▶ │    physical_1581_crc     │    (residue 0x0000 = a
 (loads 0xFFFF at       │   50 MHz (QNICE clock)   │    good field, checked
 each sync train)       │   bit-serial: 8 clocks   │    after both stored bytes)
                        │   per byte, 1-byte queue │──▶ ready flag (idle; wired
                        └──────────────────────────┘    but unused by B1.6)
```

Every ID field and every data field on an MFM track ends in a 16-bit checksum, and this file is the engine that computes it: the variant commonly named CRC-16/CCITT-FALSE — polynomial 0x1021, initial value 0xFFFF, MSB-first, no bit reflection, no final inversion. It serves the decoder as a checker on the read path, and its design leans on the checksum's most elegant property: if you feed the engine the protected bytes and then the two stored CRC bytes as well, a correct field leaves the register at exactly 0x0000. "CRC good" is therefore a single compare against zero — no second computation, no byte-order pitfalls.

The card is the interface; the one ownership fact to add is that only the decoder drives this engine — one feed pulse delivers one byte, and the preset pulse belongs to the start of each sync train.

The implementation is bit-serial with a one-byte buffer. A fed byte lands in `buffered_byte`; when the engine is idle and a byte is pending, it loads the shift register and processes eight clocks, one bit per clock. Each shifting clock moves the register left and XORs the feedback — the incoming most significant bit XORed with the register's bit 15 — into bits 12, 5, and 0, which is precisely the polynomial `x^16 + x^12 + x^5 + 1` in hardware. `crc_ready_o` drops for the eight shift clocks. Both outputs are registered one cycle behind the internal state, mirroring the upstream original.

Two details are worth knowing. First, the reset-and-feed-same-cycle fix: on `crc_reset_i` the buffer flag is not cleared unconditionally but set to `crc_feed_i`, so a byte fed in the very same cycle as a reset survives it. The decoder exploits this on every first A1 candidate, presetting the register and feeding the first 0xA1 in one cycle; without the fix, every field's checksum would silently start one byte short. Second, pacing: the buffer is only one byte deep, but overrun is structurally impossible in this design — decoded bytes arrive every `C_BYTE_CYC = 1600` cycles against a processing time of eight, and even the synthetic A1 feeds during a sync train are spaced hundreds of cycles apart. Consistent with that, the decoder never polls `crc_ready_o`; it simply waits out a fixed counter (`chk_cnt = 12`) in its CHECK states before evaluating, which covers the final byte's shifting with margin. The package provides a sanity anchor for all of this: after feeding A1 A1 A1 the register must read 0xCDB4 (`C_CRC_AFTER_3XA1`), a value the testbenches assert (B6.1).

The engine was adapted from mega65-core's `crc1581.vhdl` at `a9158930` (Paul Gardner-Stephen, LGPLv3) with the tap logic kept bit-exact, the simulation-only machinery removed, and the ports renamed to the project convention. Section A Chapter 3 explains where the two CRC bytes sit in the track format, and Chapter 13 shows when the decoder resets and feeds this engine; the controller's use of the resulting verdicts is Chapter 14's subject.

### B2 — Controller and delivery (CORE/vhdl/physical_1581/)

Where the B1 files turn flux into decoded records, the four files in this group turn decoded records into a disk drive. The controller is the operations-and-mechanics brain of physical mode; the input conditioner is its safe front door for the raw connector pins; the read FIFO (first-in, first-out buffer) carries verified sector bytes across to the drive computer; and the diagnostic device makes the whole apparatus observable from the QNICE helper CPU. Section A Chapters 14 (media state and motion), 15 (delivery: the WD boundary), and 17 (observability: the diagnostic device) develop the concepts these files implement.

#### B2.1 physical_1581_controller.vhd

```
 mechanism pins           ┌───────────────────────────────┐
 (motor, select, step, ◀─▶│   physical_1581_controller    │──▶ byte stream to the
 dir, side out; index,    │      50 MHz (QNICE clock)     │    quarantine FIFO
 track-0, write-protect,  │                               │
 change, flux in — via    │  generics: the whole timing   │──▶ live levels to the
 the B2.2 conditioner)    │  table (step, settle, search  │    drive: ready, disk
                          │  budgets…) + G_CAPABLE        │    change, write-protect
 WD front end (B3.1)   ◀─▶│                               │
 step + read requests as  │                               │──▶ observation taps to
 toggles with a 2-bit     │                               │    the diagnostics
 tag; done + result back  └───────────────────────────────┘    (B2.4) — read-only
```

This file is the largest and most consequential piece of the physical path: the operation and mechanics finite state machine (FSM) for the internal 1581 drive, running entirely on the 50 MHz controller clock. Entity `physical_1581_controller` instantiates the input conditioner (`physical_1581_inputs`, B2.2) and the whole Modified Frequency Modulation (MFM) decode chain (`physical_1581_mfm_decoder`, B1.6), so from the outside it is the single component that owns the mechanism — the physical 3.5-inch unit. It drives the six output pins of the internal floppy connector, synthesizes the drive-status levels the drive computer reads through its 8520 CIA (Complex Interface Adapter), executes Type-I head steps, and runs read operations whose payload bytes it pushes into the quarantine FIFO (B2.3). This is the read-only milestone: `f_wgate` and `f_wdata` are never driven here and stay tied inactive at the board tops.

Everything time-shaped is a generic, with the production defaults expressed in 50 MHz cycles so testbenches can scale them down:

| Generic | Default | Meaning |
| --- | --- | --- |
| `G_READY_WD_CYC` | 55,000,000 (1.10 s) | readiness watchdog in `RD_WAIT` |
| `G_DIR_SETUP_CYC` | 1,200 (24 µs) | direction-to-STEP setup |
| `G_STEP_LOW_CYC` | 200 (4 µs) | STEP low pulse |
| `G_STEP_REC_CYC` / `G_STEP_REV_CYC` | 150,000 / 200,000 (3 / 4 ms) | step recovery, same-direction / reversal |
| `G_SETTLE_CYC` | 900,000 (18 ms) | final head settle |
| `G_SIDE_SETTLE_CYC` | 5,000 (100 µs) | side-change settle |
| `G_DAM_TIMEOUT_CYC` | 68,800 | ID-to-DAM window, 43 byte times of `C_BYTE_CYC = 1600` |
| `G_SEARCH_WD_CYC` | 65,000,000 (1.30 s) | absolute search watchdog |
| `G_SEARCH_EDGES` | 5 | index-edge search budget |
| `G_PERIOD_MAX_CYC` | 12,500,000 (250 ms) | index-staleness bound (used doubled) |

`G_CAPABLE` (a synthesis-time capability switch) is `true` on every board; the feature is gated at runtime by the On-Screen Menu (OSM) bit instead. The ports fall into seven groups. The *mechanism pins*: five inputs (`f_rdata_i`, `f_index_i`, `f_track0_i`, `f_writeprotect_i`, `f_diskchanged_i`) and six outputs (`f_motora_o`, `f_selecta_o`, `f_side1_o`, `f_stepdir_o`, `f_step_o`, `f_density_o`), all active-low at the pin; they connect only here. The *maintained levels* from the drive domain: `phys_active_i` (physical mode on), `cia_motor_on_i` (CIA PA2 — bit 2 of the drive CIA's port A), and `cia_side_i`. The *step handshake*: a request toggle plus direction in, an acknowledge toggle out. The *read-operation handshake*: a request toggle with quasi-static operation code, track, side, sector, and a two-bit sequence tag, plus a cancel toggle; back come a done toggle, the completing operation's tag, a five-bit result code (`RES_*` from `physical_1581_pkg.vhd`), the CRC-error and Record-Not-Found (RNF) flags, a deleted-data flag, and the found CHRN (cylinder, head, record, size code). The *byte stream*: `byte_data_o`/`byte_wr_o` into the FIFO's 50 MHz write side, with the FIFO's full flag looped back as `byte_ovf_i`. The *live state* `st_*` levels (media-ready, index, track 0, write protect, disk change, motor, head settled, head cylinder estimate, decoder lock). Finally, some 30 purely additive `diag_*` observation taps for B2.4 — mirrors of internal signals that are never read back into behavior.

**Enable and the pins.** `en` is `G_CAPABLE` and the synchronized `phys_active_i`; when disabled, every output drives the deasserted high level and the FSMs sit in the same cleared state as under reset. Enabled, drive select asserts unconditionally, the motor pin follows the CIA motor level, and `f_density_o` stays at the double-density-safe level. The side mapping was determined empirically from real media: `f_side1_o` equals PA0 of the drive computer's CIA (`not side_s`), exactly as the original 1581 wires PA0 straight to the mechanism's SIDE line — the surface selected by a low pin carries the sector IDs with `H = 0`, the D81 first half. A change of side loads the 100 µs side-settle timer and resets the decoder.

**Media readiness.** `media_ready` models the RDY line of the original mechanism (Chinon FB-354): the motor is on and real index pulses prove a disk is spinning plausibly. It is deliberately independent of the disk-change latch, because the stock 1581 ROM (read-only memory) waits for RDY on CIA PA1 *before* running the disk job whose seek steps would clear the change latch — gating one on the other deadlocks the Disk Operating System (DOS). Cold qualification demands two motor-on index edges. Once a medium has passed that test with no change indication, the sticky flag `rotation_confirmed` remembers it across motor-off intervals, and a restart may reassert RDY after a single fresh edge — Chapter 14's timelines show why: the cold worst case of spin-up plus up to two revolutions brushes the stock ROM's one-shot readiness deadline, and the remembered revolution buys the margin back. The history is revoked by reset or disable, by any raw disk-change assertion, or by index staleness: no edge for `2 * G_PERIOD_MAX_CYC` (500 ms) with the motor on drops readiness immediately. Staleness clears `rotation_confirmed` as well, but only once the current motor-on interval has produced an edge — before the first edge, spindle acceleration may legitimately be slow, and raw disk-change remains the authoritative eject signal there. The change latch itself, `change_latched`, is set by the raw pin and — importantly — on reset *and on plain disable*: while the controller is off, drive 8 is served from a disk image, so a switch back to physical mode must present as a disk change and force the DOS to revalidate. It clears only when a completed step's recovery ends with media present, matching how the latch clears in a real drive.

**The step engine** walks `SI_IDLE → SI_SETUP → SI_LOW → SI_REC`: latch the direction, wait the 24 µs direction setup, pulse STEP low for 4 µs, move the head-cylinder estimate at the trailing edge, start the 18 ms settle timer, then wait the 3 ms (or 4 ms reversal) recovery before toggling the acknowledge. Accepting a step clears `head_settled` and also kills any still-running settle timer from the previous step, which would otherwise expire mid-flight and reassert the flag early. If an outward step ends with the track 0 sensor active, the estimate anchors to zero and `head_valid` is set. Two subtleties matter: `head_settled` is `'1'` at rest and after reset or disable — starting at `'0'` would wedge the WD1772 (Western Digital floppy-disk controller) front end whenever a verify needs zero steps, such as Restore with the head already home — and the settle timer runs independently of the FSM, so it guards reads without delaying further step requests. On plain disable the head estimate survives; only a real reset clears it.

**The read engine** is a five-state machine. Sketched with its budgets and
exits:

```
request ──▶ RD_WAIT ──ready──▶ RD_SEARCH ──ID match──▶ RD_DAM ──DAM──▶ RD_STREAM ──▶ done
(RD_IDLE)   │ 1.10 s           │ 5 index edges         │ 43 byte-times        │
            ▼ RES_NOT_READY    ▼ or 1.30 s: RNF        ▼ RES_MISSING_DAM      ▼ RES_OK or
                                                                                RES_DATA_CRC_ERROR
            (a Read Address exits RD_SEARCH via RD_ADDR instead: six ID bytes)
     a cancel edge or a raw disk change aborts any non-idle state immediately
     (RES_CANCELLED, or RES_DISK_CHANGED with RNF)
```

`RD_IDLE` accepts a live request edge or serves the *pending latch*: a request that arrives while the engine is busy is latched with its parameters resampled at the edge — latest edge wins, a cancel clears it — instead of being lost, which once was the path's one silent-desynchronization channel (stale data delivered under a newer command's clean status). Every done toggle also writes `rd_done_seq_o` with the tag of the operation being completed, on that cycle only, so the tag is stable between dones by construction; and every done arms an eight-cycle spacing counter (`C_DONE_GAP = 8`) during which nothing is accepted into an abortable state, because two done toggles a couple of cycles apart could be swallowed whole by the drive-side synchronizer.

`RD_WAIT` holds until media-ready, head-settled, and side-settled, resets the decoder for a fresh start, and gives up after 1.10 s with `RES_NOT_READY`. `RD_SEARCH` then watches decoded ID fields against two budgets, five index edges or 1.30 s. Read Address takes the next ID whose record number lies in 1..10 — out-of-range IDs are ignored because the MEGA65's F011 auto-formatter can squeeze a CRC-valid sector-11 ID in front of the index splice, and exposing it can derail a login sequence (Commodore DOS jargon: the drive validating a newly inserted disk before its first job) — and completes even with a bad ID CRC (cyclic redundancy check), delivering the six reply bytes plus the error. Verify matches on cylinder alone and completes without bytes. Read Sector matches cylinder and record, rejects any size code other than `C_SIZECODE_512` (`RES_UNSUPPORTED_SIZE`), and arms the 43-byte-time DAM window; a matching cylinder with a bad CRC sets a flag and keeps searching.

On exhaustion the result is `RES_ID_CRC_ERROR` if such a flagged ID was seen, else `RES_RECORD_NOT_FOUND` — and the CRC and RNF flags are *never* reported together: Chapter 8's four-row status table shows the hole in the genuine DOS's `$CD5A` result lookup that the combination falls through. That rule is enforced at every error site in the file.

`RD_DAM` waits for the data field to open (sampling the deleted-data flag, which the decoder registered at the previous field's end — a one-field lag that is harmless on D81 media, where every data address mark (DAM) is the normal FB); another ID or the local timeout resumes the search inside the same budgets, and budget exhaustion yields `RES_MISSING_DAM`. `RD_STREAM` pushes each payload byte into the FIFO and keeps the absolute watchdog running so a flux dropout mid-field cannot park the FSM forever; on field end the result is `RES_OK` only if the data CRC checked out *and* no byte was ever dropped against a full FIFO — a truncated stream is reported as `RES_DATA_CRC_ERROR`, the analog of the real WD1772's LOST DATA. `RD_ADDR` streams the six Read Address bytes (C, H, R, N, stored CRC high and low) one per cycle with the same never-complete-silently discipline. One documented, accepted hole remains: a QNICE-domain-only reset mid-operation would idle the FSM without a done toggle, but in the M2M framework that reset never occurs without the core reset that also clears the drive side.

**One Read Sector, walked.** The WD front end flips the request toggle: operation read-sector, cylinder 39, record 3, tag 2. The engine leaves idle, latches the parameters, and parks in its wait state until the media-ready contract and the settle timers agree the mechanism is trustworthy — then resets the decoder for a fresh lock and begins the search with both budgets armed. Decoded ID fields flow past; one matches cylinder and record with a clean CRC and announces size code 2, so the engine arms the 43-byte-time window and waits for the data field. The DAM opens in time; 512 payload bytes stream into the quarantine FIFO, each pushed the cycle the decoder publishes it. The field's CRC residue is zero and no byte was dropped, so the engine flips the done toggle, publishes tag 2 and the all-clear result in that same cycle, and arms the eight-cycle spacing guard. In the diagnostic ring, two entries have appeared: the request with its parameters, and the clean completion — exactly the pair every hardware session audited first.

Nearly every rule in this file — the two-edge/one-edge readiness contract, the `$CD5A` flag discipline, the sector-11 filter, the pending latch, the done spacing — was forced by hardware sessions or by the genuine DOS ROM in the loop; Appendix C2 tells those stories in order. Section A Chapter 14 explains the media-state model, Chapter 15 the delivery contract, and Chapter 13 the decoder this file commands; B3.1 describes the `fdc1772.v` front end on the other side of the handshakes.

#### B2.2 physical_1581_inputs.vhd

```
 raw connector pins    ┌──────────────────────────┐──▶ synchronized flux
 (index, track-0,    ─▶│   physical_1581_inputs   │    (kept active-low)
 write-protect,        │   50 MHz (QNICE clock)   │──▶ index: filtered level,
 disk-change, flux —   │                          │    accepted edge, period,
 all asynchronous,     │  generics: clock rate,   │    pulse width
 all active-low)       │  200 µs index glitch     │──▶ clean levels: track-0,
                       │  floor                   │    write-protect, change
                       └──────────────────────────┘
```

This small file is the safe front door between the internal floppy connector and everything synchronous: the asynchronous input conditioner, entity `physical_1581_inputs`, on the 50 MHz controller clock. It exists so that exactly one block in the design touches raw, asynchronous, active-low connector signals, and everything downstream can assume clean synchronous levels with positive semantics. It is instantiated only by the controller (B2.1).

Its generics are `G_FDC_HZ` (50,000,000) and `G_INDEX_MIN_LOW_CYC`, the index glitch floor, defaulting to 10,000 cycles (200 µs — comfortably below the shortest valid index pulse of about 1.5 ms). The inputs are the five raw pins: index, track 0, write protect, disk change, and read data. The outputs are `rdata_sync_o` (the synchronized flux line, with its active-low sense deliberately *preserved*, because the gap stage of B1.2 detects the falling edge of an active-low flux pulse), the filtered index level `index_active_o`, a one-cycle `index_edge_o` per accepted index leading edge, two 32-bit measurements `index_period_o` and `index_width_o`, and the positive-sense status levels `track0_o`, `wprot_o`, and `change_o`.

Every pin passes through a two-flip-flop metastability synchronizer whose first stage carries the Xilinx `async_reg` attribute, so the tool places the pair tightly and does not absorb it into a shift-register primitive. The static status pins are then simply inverted into positive semantics. The interesting work is index qualification: the pin idles high and pulses low once per revolution (about 200 ms at 300 RPM — revolutions per minute). A leading edge is accepted only when the pin has been low *continuously* for `G_INDEX_MIN_LOW_CYC` cycles; at the exact cycle the low-run counter reaches the floor (a pre-increment compare against `G_INDEX_MIN_LOW_CYC - 1`), the block pulses `index_edge_o` once, latches `index_period_o` from a free-running interval counter, and restarts that counter at one. A shorter low run — an electrical glitch — never pulses, and the pin must return high before the next edge can be accepted. On that return to high, the width of an accepted pulse is latched into `index_width_o`. All counters saturate at the 32-bit maximum (`C_CNT_MAX`) rather than wrapping.

Two details are worth knowing. First, the accepted edge is *delayed* by the glitch floor — 200 µs after the physical edge — which is irrelevant at the time scales the controller cares about (readiness, search budgets) but explains why the measured period is edge-to-edge exact while the edge itself is late. Second, the header carries an explicit polarity caveat: `change_o` assumes the board presents disk-change active-low, to be confirmed against actual board wiring and inverted here if a sensor turns out active-high.

Section A Chapter 12 places this block at the start of the physical path; Chapter 16 covers the clock-domain-crossing (CDC) conventions it embodies, and B1.2 describes the gap stage that consumes `rdata_sync_o`.

#### B2.3 physical_1581_rdfifo.vhd

```
 50 MHz write side           ┌────────────────────────┐  drive-domain read side
 push one decoded byte ─────▶│  physical_1581_rdfifo  │◀─ pop (first-word-fall-
 full? (a push while full  ◀─│  two clocks, one       │   through: head byte
 is a known dropped byte)    │  storage array         │   always visible)
 occupancy tap (to diag)   ◀─│  depth 2^G_AW —        │─▶ head byte, empty?
                             │  production: 512 = one │
                             │  whole sector          │
                             └────────────────────────┘
```

Entity `physical_1581_rdfifo` is the dual-clock byte FIFO that carries decoded sector bytes from the 50 MHz controller domain to the drive computer's clock domain — and, just as importantly, it is the *quarantine FIFO* of Section A Chapter 15: deep enough to hold one complete 512-byte sector, so a whole data field can be captured and judged before the drive computer sees a single byte of it.

The single generic `G_AW` sets the depth to `2**G_AW` (default 5, i.e. 32, for the testbenches; it must be at least 2). The production instance in `CORE/vhdl/main.vhd` uses `G_AW => 9` — 512 bytes, exactly one physical sector. The write side (`wr_clk_i`, `wr_rst_i`, `wr_en_i`, `wr_data_i`, `wr_full_o`) belongs to the controller; `wr_full_o` loops back to the controller as `byte_ovf_i`, so a write attempted while full is known to have been dropped and poisons the operation's result. A ten-bit-wide occupancy tap, `wr_level_o`, feeds the diagnostics: the binary write pointer minus the Gray-synchronized read pointer, conservative-high (a pop shows up only after its pointer crosses the synchronizer), sized to hold the 0..512 range. The read side (`rd_clk_i`, `rd_rst_i`, `rd_en_i`, `rd_data_o`, `rd_empty_o`) belongs to the drive domain, where `fdc1772.v` drains it at its existing DRQ (data request) pacing — one presented byte per 32 µs byte time.

Mechanically this is the textbook Gray-code asynchronous FIFO from Cummings' SNUG 2002 paper. Binary and Gray read/write pointers are `G_AW + 1` bits wide — the extra top bit is what distinguishes full from empty. Each domain's Gray pointer crosses into the other through a two-flip-flop synchronizer (first flop `async_reg`); Gray code guarantees that only one bit changes per increment, so a synchronizer can never capture a torn multi-bit value. FULL asserts when the next write-Gray equals the synchronized read-Gray with the top two bits inverted; EMPTY when the next read-Gray equals the synchronized write-Gray. The storage is a shared dual-port array with a clocked write port and an asynchronous read of the current head — first-word-fall-through (FWFT): `rd_data_o` always shows the head byte, and `rd_en_i` pops it.

The reset discipline around the production instance deserves respect: both sides are reset by the *same* event — the QNICE reset, with the read side receiving a copy synchronized into the drive domain — and never by the core reset alone. A one-sided reset would zero one Gray pointer against a live one and permanently desynchronize the FIFO, yielding stale, shifted sector data that would still pass every CRC check. Leftover bytes after a core reset are instead drained by `fdc1772.v` while no operation is delivering. One reading note: the file header describes the read side as "the ~16 MHz drive clock"; the production read clock is in fact the core clock `clk_main_i` (≈31.53 MHz), on which the drive computer's logic advances at a roughly 16 MHz clock enable — the pointer logic only cares that the two clocks are asynchronous.

Section A Chapter 15 explains why quarantine — not streaming — is the right delivery model here, and Chapter 16 the CDC reasoning; B3.1 covers the consumer.

#### B2.4 physical_1581_diag.vhd

```
 controller state, results,  ┌──────────────────────────┐
 counters, decoder and     ─▶│    physical_1581_diag    │◀── QNICE reads:
 quantiser taps (same        │    50 MHz (QNICE clock)  │    device 0x0108,
 domain, purely additive)    │                          │    word N at 0x7000+N
                             │  writes: ignored         │
 fdc1772 event toggles     ─▶│  reads: combinational,   │──▶ one 16-bit word
 (pre-synchronized in        │  zero side effects       │
 main.vhd)                   └──────────────────────────┘
```

The MEGA65 has no logic analyzer on its internal floppy bus, so entity `physical_1581_diag` is the only on-hardware window into the physical read path: a strictly read-only diagnostic register bank that the QNICE helper CPU can inspect at any time, described conceptually in Section A Chapter 17. It drives nothing back into the controller, it has no write side (writes are simply ignored), and reads are a purely combinational multiplexer with no wait state — by construction it cannot perturb the machinery it observes.

Its shape is 128 sixteen-bit words: 64 scalar words at offsets `0x00`–`0x3F` — a signature (`0x1581`) and version word, live pin levels, controller state, the last completed result with its CHRN, CRC taps, index and gap measurements, and a battery of saturating event counters — followed by a 32-entry trace ring at `0x40`–`0x7F`, two words per entry. The register map has grown through seven versions, and the VERSION word encodes that: map version `0x07` in the high byte and the capability byte `0xFF` (all eight feature groups present) in the low byte, so a current device reads `0x07FF`. The authoritative word-by-word register map, bit layouts, and trace-entry encodings live in [the debug-device reference](1581_dd_debug_device.md); this chapter describes the machinery behind them rather than repeating the tables.

From QNICE the bank is device `C_DEV_C64_PHYS1581 = 0x0108` in the M2M RAMROM scheme: write `0x0108` to the device selector at `0xFFF4`, write `0x0000` to the window selector at `0xFFF5`, then read word offset N at address `0x7000 + N`. The decode sits in `CORE/vhdl/mega65.vhd`; the same recipe works from the interactive QNICE monitor over JTAG (Joint Test Action Group, the debug cable), which is how most bring-up sessions read it.

The file's central trick is clocking: it runs on the same 50 MHz clock as both the controller *and* the QNICE CPU, so no clock-domain crossing exists anywhere inside it. The exceptions arrive pre-conditioned from `main.vhd`: the image-drive busy level and the five `dbg_*` event toggles from `fdc1772.v` (LOST DATA, between-ops drains, stale dones, busy-command writes, operation finalize) are two-flip-flop-synchronized there, and the presented-byte count crosses as a quasi-static bus sampled only on the synchronized finalize edge. Internally, everything is either a saturating counter (32-bit via `sat_inc`, the newer forensic counters 16-bit via `sat_inc16` — saturation, not wraparound, so an overflowed counter reads as obviously pegged rather than misleadingly small), a latch captured on an event pulse (the last result and CHRN on the done toggle; ID and data CRC residues on the decoder's field-complete pulses; the last-RNF context word, race-free because the controller holds its request parameters stable for at least `C_DONE_GAP` cycles after every done), or a live level passed straight through.

The trace ring is the device's most valuable instrument: 32 entries of 32 bits recording the exact dialogue between the DOS and the WD boundary — one entry per completed step (with direction and head estimate), per accepted read request (operation, track, sector, side), and per completed operation (result, flags, found CHRN). A free-running 16-bit event counter indexes the ring, so the newest entry is always at `(TRC_CNT - 1) mod 32`. If two events coincide in one cycle, priority is done over request over step and the loser is dropped — noted for completeness, irrelevant in practice. This ring is what replaces an oscilloscope when a login sequence goes wrong on real hardware.

Beyond debugging, two words carry an operational duty: the Shell (the QNICE menu firmware) reads `CTRL_STATE` (whose FSM-phase and motor bits are nonzero only while the physical drive is genuinely mid-access) and `IMG_DRIVE` (set while the image-backed drive 8 is busy or holds unflushed writes) as the two halves of the symmetric idle gate that refuses to switch drive 8 between image mode and physical mode while either side is working — B5.6 covers that flow. How the bank accreted its seven map versions alongside each bring-up round is part of the Appendix C2 story. Section A Chapter 17 explains the observability philosophy; B5.1 and B5.2 show the instantiation and the QNICE decode.

### B3 — The drive proper (CORE/C64_MiSTerMEGA65/rtl/iec_drive/)

The four files in this chapter are the 1581 as the MiSTer project built it: a complete Commodore drive computer — CPU, memory, I/O chips, and a model of the floppy disk controller (FDC) — that we adopted, repaired, and then taught to talk to real magnetics. They form a strict hierarchy. `fdc1772.v` models the WD1772, the Western Digital floppy disk controller chip at the heart of the 1581; `c1581_drv.sv` assembles one whole drive around it; `c1581_multi.sv` replicates that drive up to four times around a shared ROM (read-only memory); and `iec_drive.sv` is the top of the stack, deciding whether the 1541 or the 1581 engine owns the bus. We read them bottom-up.

#### B3.1 fdc1772.v

```
 drive CPU (2 MHz):       ┌─────────────────────────────┐  image path (QNICE
 the four WD registers, ◀▶│           fdc1772           │◀▶ clock): mount info,
 DRQ and INTRQ            │  core clock; WD timebase =  │   block transfers via
                          │  the 8 MHz enable           │   vdrives (sd_*)
 drive control: side,     │                             │
 motor, step — to the   ◀▶│  parameters: sector size    │  physical path (50 MHz
 rotation model (image)   │  and base, drive count,     │◀▶ side): step + read
 or the controller        │  chip model, ext. motor     │   requests out as
 (physical)               │                             │   toggles + tags; done,
 busy → activity LED    ─▶│                             │   result, FIFO bytes in
                          └─────────────────────────────┘
```

This file is the register-level model of the WD1772 — the chip the 1581's drive computer programs to move the head and transfer sectors. Written by Till Harbaum in 2015 for the MiST Atari ST core and reused across many FPGA targets, it models the chip as software sees it: four registers, four command classes, a status byte, and two handshake lines. In our port it is the most heavily modified file of the drive stack. It gained a second clock domain so its storage interface could talk to the M2M framework's `vdrives.vhd`, and — for the physical internal drive of issue #90 — an entire second media backend that lets the same register machine command the real mechanism instead of a disk image. Chapter 4, the floppy disk controller, teaches what the real chip does; Chapter 15, delivery: the WD boundary, explains the design this file's physical half implements.

The file contains two modules. `fdc1772_dpram` is a small true dual-clock, dual-port RAM (random-access memory) used as the image-path sector buffer; upstream it was single-clock, and making it dual-clock is what carries sector data safely between clock domains. The main module `fdc1772` takes its configuration as parameters: `CLK_EN` (the millisecond timebase, 8000 kHz), `FD_NUM` (number of drives), `MODEL` (2 selects WD1772 behavior for step rates and status bit 7), `SECTOR_SIZE_CODE`, `SECTOR_BASE`, `EXT_MOTOR`, and `INVERT_HEAD_RA`. The 1581 instantiates it with 512-byte sectors, first sector 1, and an external motor (the motor line belongs to the drive's CIA, described in B3.2). The ports fall into five groups: clocks (`clkcpu`, the 16 MHz drive clock; `clk8m_en`, the 8 MHz enable that is the WD's timebase; and `clk_sys`, the QNICE clock — QNICE being the on-board helper CPU whose domain the storage interface lives in); drive control (`floppy_side/reset/motor/step/ready`, plus the MEGA65-added `fdc_busy` that feeds the activity LED); the host bus (`cpu_addr/sel/rw/din/dout` plus the `irq` and `drq` outputs); the image/storage group (`img_*` and `sd_*`, MiSTer's block-transfer convention — "SD" after the Secure Digital card of the original hardware — served here by `vdrives.vhd`); and the flat `phys_*` bundle of toggles and levels that connects to the 50 MHz `physical_1581_controller` (B2.1) and the external read FIFO — first-in, first-out buffer — of B2.3.

**The register and command model.** Address 0 is the command register on write and the status register on read; addresses 1, 2, 3 are track, sector, and data. Commands divide into the chip's four classes: Type I (bit 7 clear) covers Restore, Seek, and the Step family — head motion, with a step rate chosen by the two low command bits (6, 12, 2, or 3 ms for the WD1772); Type II (`10` in the top bits) is Read and Write Sector; Type III is Read Address, Read Track, and Write Track; Type IV is Force Interrupt. INTRQ (the interrupt request, output `irq`) sets when a command completes and clears on reset or on any access that opens register 0. DRQ (data request) is a clear-dominant set/clear flip-flop: set once per byte moved through the data register, cleared by reset, by a data-register read, or — in physical mode only — by command acceptance. `busy` spans a whole command; status bit meanings shift with the command class, the classic WD trait: bit 5 is spin-up-done during Type I but the deleted data address mark (DAM) after a read, bit 2 is track-zero during Type I but "lost data" otherwise, bit 1 is the index pulse during Type I but DRQ otherwise.

**The image-backed sector path.** In image mode a `floppy` instance (B4.3) per drive simulates the spinning disk: it produces index pulses, tracks head position, reports which sector is currently under the head, and emits `dclk_en`, the 32 µs byte-rate enable of a double-density (DD) disk. Geometry is derived from `img_size` when a mount pulse arrives: an 819,200-byte D81 (the 1581 disk-image format) yields 1600 sectors, hence double-sided, 800 per side, ten sectors per track, 107 gap bytes. A Read Sector then runs in two phases. First the storage phase: a request toggle crosses into the `clk_sys` domain, where a small state machine asserts `sd_rd`, latches the logical block address (LBA) — for 512-byte sectors, `((spt × track) << doubleside) + (side ? 0 : spt) + sector − 1` — and lets `vdrives.vhd` stream 512 bytes into the dual-clock buffer; a completion toggle crosses back. One worked example pins the formula down: on a D81 (ten sectors per track, double-sided), cylinder 39, sector 3 on the head whose ternary term contributes 0 gives `(10 × 39) << 1` = 780, plus 0, plus `3 − 1` — LBA 782. `iec_drive.sv` doubles that into 256-byte units, and blocks 1564 and 1565 are precisely where the image stores logical track 40's sectors 4 and 5 — the directory track of Chapter 7, arrived at from the other end. Then the rotation phase: the model waits until the simulated disk brings the requested sector under the head, and the transfer engine plays the buffer into the data register one byte per `dclk_en`, raising DRQ each time and setting "lost data" if the previous byte was never consumed. The transfer counter loads `SECTOR_SIZE + 1`, so busy outlives the last DRQ by one byte-time — a real-chip shape the DOS (Disk Operating System) relies on. Write Sector is the mirror image, with DRQ raised early to prefill the data register; the multi-sector flag increments the sector register and loops. Read Address returns track, side, sector, and size code followed by a genuine CRC — cyclic redundancy check, polynomial 0x1021 — seeded with 0xB230, the checksum state after the three `A1` sync marks plus the `FE` ID address mark.

Several behaviors of the real chip are faked here, and it is worth being plain about which. Type-I verify reads no ID field at all: it is a flat 3 ms delay. Read Track and Write Track complete immediately, transferring nothing. Status bit 3 (CRC error) is constant zero — a disk image is assumed clean. A request for a nonexistent sector waits a fixed second (five simulated revolutions) before reporting RNF, the record-not-found error. Spin-up is six index pulses; the motor stops after ten idle ones.

**The physical-mode additions.** With `phys_mode` set, the same register machine is kept but the media backend becomes the real mechanism, reached through the controller of B2.1; with `phys_mode` clear, every addition is inert and the image path is byte-identical. All controller levels are two-flip-flop synchronized into `clkcpu` (with `iecdrv_sync`'s agreement filter); outgoing requests are toggles that are deliberately never reset — resetting one would inject a phantom edge — and completion toggles are consumed by level comparison against a "serviced" copy, so no edge is ever lost across the clock-domain crossing (CDC). The read-done toggle is acted upon two `clkcpu` cycles after it resolves, because each result flag crosses through its own synchronizer and may settle a cycle apart.

Every issued read operation carries a two-bit sequence tag in `phys_rd_seq`; the controller echoes it in `phys_rd_done_seq`. A done whose tag mismatches, or that arrives with no operation pending, is consumed but ignored — a stale result can never pair with a newer command. Type I runs unconditionally, as on the real chip (the 177x family has no READY input); gating steps on media-ready would deadlock, since the disk-change latch clears only via a step. Each step becomes one request/acknowledge toggle pair; Restore gives up with a seek error after 255 steps without the TR00 (track-zero) sensor asserting. Verify, unlike in image mode, is real here: after head-settle it issues the controller operation `RDOP_VERIFY`. Read Sector and Read Address issue `RDOP_READ_SECTOR` and `RDOP_READ_ADDRESS` and complete *only* through the controller's done handshake — there is no unilateral WD-side timeout, because the controller already bounds every failure mode. Write Sector is blocked in this read-only milestone: it completes immediately and the status byte forces the write-protect bit. A command written while busy is dropped wholesale unless it is Force Interrupt — exactly the real chip's rule, replicated only in physical mode.

Physical bytes are speculative until the controller has verified the complete data-field CRC, so the external 512-byte buffer doubles as the quarantine FIFO. Presentation — handing a byte to the data register — begins only after a tag-matched clean done:

```verilog
wire phys_present_now = phys_mode && phys_reading
                        && phys_done_latched && !phys_rnf_l && !phys_crc_l
                        && (phys_pace_cnt == 8'd0) && !phys_byte_empty
                        && !phys_cpu_rd_data_open && !cpu_rw_data;
```

Once released, bytes present at disk pace: `PHYS_PACE_TICKS = 252` ticks of the nominally 8 MHz enable, one DD byte-time of 32 µs. Presentation never waits for consumption — if DRQ is still high, the old byte is overwritten and the real chip's LOST DATA flag sets. The last two terms are the presentation exclusion windows: never present into an open drive-CPU read of the data register, and never in the cycle where the registered read pulse clears DRQ. The reason lives in the bus timing — the T65 (the soft 6502 CPU core the drive computer runs on) holds its select for a whole 2 MHz bus cycle and takes the value only at the closing tick:

```
one drive-CPU read of the data register (a full 2 MHz bus cycle, ~500 ns):

  select      ──╔═══════ register open ═══════╗──
  CPU latch                                   ▲     value taken at the closing tick
  DRQ clear                                    ╔╗   registered pulse, one clock wide
  present?    ───────────── deferred ────────────▶  the byte lands after the window,
                                                    whole, and with a fresh DRQ
```

A byte presented inside that window would be read half-old, half-new by the closing latch, or have its fresh DRQ eaten by the clear pulse and then be counted as lost — so presentation simply defers past it. The deferral is bounded by the bus cycle — about 0.5 µs against a 32 µs pace — so completion stays disk-time-shaped, never consumption-coupled. On an error done the bytes drain: popped and discarded without ever raising DRQ; the drain also runs whenever no operation is delivering, which structurally removes a class of stuck-busy failures. Finalization requires done-and-tag-matched, FIFO empty, and the pace expired once more — busy outlives the last DRQ by at least one byte-time, which the DOS transfer loops depend on — the sector transfer loop at `$C969` (the loop Chapter 8 teaches) and the Read Address reply loop at `$CD17`, both of which poll busy first, DRQ second.

Two subtleties deserve their own sentences. `PHYS_T1_MIN_TICKS = 12000` ticks (≈1.5 ms) is the minimum Type-I busy time: a zero-step seek would otherwise clear busy in under 400 ns, invisible to the DOS's wait-for-busy poll at `$CBFA`, hanging the drive — observed on hardware. And on a data-register write, `data_out <= phys_mode ? cpu_din : data_in`: the real chip has one data register and the genuine 1581 ROM's startup test requires reading back the value just written, but image mode must keep the previous-value expression its proven engine depends on — the one time the two backends could not share a wire. In status, RNF is suppressed while the CRC bit is set, because the DOS job epilogue at `$CD3F` indexes its result table in a way that would silently accept a corrupt sector if both bits appeared together.

| Constant | Value | Meaning |
| --- | --- | --- |
| `PHYS_PACE_TICKS` | 252 ticks | 32 µs presentation pace (one DD byte-time) |
| `PHYS_T1_MIN_TICKS` | 12000 ticks | ≈1.5 ms minimum Type-I busy |
| `MOTOR_IDLE_COUNTER` | 10 index pulses | motor-off timeout |
| spin-up | 6 index pulses | status bit 5 during Type I |
| RNF wait (image) | 1 s | five simulated revolutions |
| Restore bound (physical) | 255 steps | then seek error |
| CRC polynomial / seed | 0x1021 / 0xB230 | Read Address reply checksum |

**The same Read Sector, seen from the registers.** The drive CPU writes `$80` — Read Sector — to the command register: busy sets, the data-request flag clears, and, in physical mode, the request toggle leaves for the controller carrying the current tag. Then nothing happens for many milliseconds, and that is the design: the WD model neither paces nor watches the search; it waits for a completion whose tag matches. When the done toggle crosses the synchronizer and settles, the result is clean, so presentation opens: one byte from the quarantine every 252 ticks of the 8 MHz enable — 32 microseconds — each raising the data-request flag, and the ROM's polling loop collects every one inside its 47 percent margin. After the last byte the FIFO reads empty, the pace timer runs one final byte-time — busy outliving the final data request, exactly as the busy-first polling loop requires — then busy falls, the interrupt line pulses, and the status byte assembles with no error bits set. The DOS reads it, runs it through the result table of Chapter 8, and files the sector as good.

How this delivery design was reached — and the regression that taught us to keep the two data-register expressions apart — is an Appendix C2 story. Chapter 11 walks the image path end to end, Chapter 12 the physical path; Chapter 14 describes the controller that answers these requests, and B2.3 the quarantine FIFO itself.

#### B3.2 c1581_drv.sv

```
 IEC bus: ATN, CLK,     ┌──────────────────────────────┐  image blocks (QNICE
 DATA (+ dormant      ◀▶│          c1581_drv           │◀▶ clock): sd_lba, rd/wr,
 fast-serial pair)      │  one complete 1581:          │   ack, buffer bytes
                        │  T65 6502 + 8 KB RAM +       │
 parallel port (VIA) ◀─▶│  8520 CIA + 6522 VIA +       │  physical bundle
 DOS ROM window:        │  WD1772 model + address      │◀▶ (1:1 pass-through
 15-bit address out,  ◀▶│  decoder                     │   from fdc1772, gated
 byte back              │                              │   on phys_mode)
 device number, LEDs,   │  clocks: 16 MHz ce → 2 MHz   │
 mount/write-protect  ─▶│  CPU phases, 8 MHz WD enable │
                        └──────────────────────────────┘
```

This file is one complete 1581: the drive computer of Chapter 5 rendered in SystemVerilog by Alexey Melnikov (2021), wired chip for chip like the real printed circuit board. Everything the DOS ROM expects to find — a 6502, 8 KB of RAM, an 8520 CIA (Complex Interface Adapter), a 6522 VIA (Versatile Interface Adapter), and the WD1772 — is instantiated and address-decoded here; the disk itself is elsewhere, behind the FDC's two media backends.

Its ports group naturally: the 16 MHz drive clock `clk` with the enables `ce`, `wd_ce`, `ph2_r`, and `ph2_f` generated by `c1581_multi`; the mount inputs (`img_mounted`, `img_readonly`, `img_size`); `drive_num`, the two device-number straps; the two LED outputs; the IEC bus pins — Commodore's serial bus to the computer — including the 1581's fast-serial pair; the parallel port of the VIA; a fetch-only ROM port (`rom_addr` out, `rom_data` back) served by the shared ROM upstream; the `clk_sys`-domain `sd_*` block; and the `phys_*` bundle, passed one-to-one through to `fdc1772`.

Address decoding follows the real hardware's LS193 decoder, and the signal is even named `ls193`: the top three address bits select 8 KB RAM at `$0000`, the VIA at `$2000`, the CIA at `$4000`, and the WD1772 at `$6000`, while address bit 15 maps the 32 KB DOS ROM at `$8000`–`$FFFF`. The CPU is the T65 core — the portable synthesizable 6502 used throughout MiSTer — in plain-6502 mode, clock-enabled on `ph2_r` (2 MHz), its interrupt line the combination of CIA and VIA interrupts. One instantiation detail is load-bearing: the WD1772's `cpu_rw` input is fed `cpu_rw | ~ph2_f`, so a CPU write becomes visible to the FDC only during the single-clock `ph2_f` pulse at the end of the 2 MHz cycle — a clean write strobe for `fdc1772`'s edge detector.

The CIA's ports are where the drive senses its world, and where image mode and physical mode diverge. On port A: bit 6 drives the activity LED — widened in our port to `pa_out[6] | fdc_busy`, so turbo loaders that never touch the LED bit still light it during WD activity; bit 5 is the power LED; bit 2 the (active-low) motor; bit 0 the side select; bits 4:3 read the device-number straps; bit 1 reads ready (`~floppy_ready`, already mode-aware inside `fdc1772`); and bit 7 is /DSKCHG, the disk-changed sense. In image mode /DSKCHG comes from the local latch `disk_chng_n`; in physical mode it is the controller's sticky change latch, synchronized here. On port B: bit 7 senses ATN (Attention, the C64's bus-attention line), bits 3/1 drive the IEC clock and data lines (inverted, with the ATN-acknowledge and fast-serial terms folded into data), bits 2/0 sense them, bit 5 selects fast-serial direction — the 8520's fast-serial machinery is fully wired here but dormant, because the C64 end is tied off (B3.4) — and bit 6 is /WPRT, the write-protect sense: the latched image read-only flag in image mode, the real tab in physical mode. Both port images are ANDed with the port outputs before entering the CIA, modeling the open-drain readback of the real chip. The TOD (time-of-day) input ticks on `ph2_f`, i.e. it counts the 2 MHz CPU clock rather than wall-clock time — faithful to the real 1581, and B4.1's story. The VIA carries only the parallel port.

The disk-change latch earns a close look. `disk_chng_n` asserts on a mount, on reset, and — a MEGA65 addition — on any edge of `phys_mode`. The mode edge is the source-switch disk change: switching from the physical drive back to a still-mounted image does not reset the drive, and without this term the DOS would keep the previous medium's cached BAM (block availability map) — a silent media swap. The DOS then clears the latch the way it always does, by stepping. The opposite switch is covered by the controller re-arming its own latch. Only two controller levels are synchronized in this file (`phys_change`, `phys_wprot`) — everything else crosses inside `fdc1772`.

**An ATN command, arriving.** The C64 pulls the attention line low. The CIA's FLAG input sees the falling edge, latches its interrupt bit, and the interrupt line drops the T65 into the ROM's bus handler within microseconds — the 2 MHz CPU's real-time job. The handler reads port B: attention asserted, clock and data in their handshake states. Bit by bit the drive clocks in the command bytes — LISTEN for device 8, OPEN channel 0, then the filename — acknowledging each through the wired-AND data line. The DOS parses the name, decides it needs the directory, and queues a job; the job layer translates logical track 40 into cylinder, side and record, and writes the WD1772's registers through the address decoder's `$6000` window — from where the story continues in B3.1's walk. Every chip on the card above has taken part: the CIA for the bus, CPU and ROM for the protocol, the address decoder for the chip selects, and the WD1772 only at the very end.

Why the CIA senses had to become mode-aware, and how the LED change was found, are Appendix C2 material. Chapter 6 gives the anatomy this file mirrors; Chapter 8 the ROM that runs on it; B4.1 and B4.2 cover the two I/O chips.

#### B3.3 c1581_multi.sv

```
 IEC lines of up to four  ┌───────────────────────────┐
 drives, wired-AND      ◀▶│        c1581_multi        │◀▶ per-drive image
 combined onto one bus    │  the fleet builder:       │   block buses (sd_*)
                          │  4 × c1581_drv around     │
 one shared DOS ROM     ◀▶│  one shared ROM (stock +  │◀▶ physical bundle —
 port (QNICE-writable     │  custom slots), time-     │   exported for drive 0
 custom-DOS slot)         │  multiplexed per CPU      │   only; drives 1..3
 drive numbers, LEDs,   ─▶│  cycle; makes ph2_r/f     │   are always virtual
 resets                   │  and wd_ce from 16 MHz ce │
                          └───────────────────────────┘
```

This file turns one drive into a fleet: up to four `c1581_drv` instances sharing a single DOS ROM, one clock-enable generator, and one set of open-collector bus wires. (The header comment still says "C1541 multi-drive" — an honest copy-paste trace of its origin.) Our core instantiates the stack with `DRIVES = 1`, so in practice one 1581 exists — device 8 — but the machinery is generic.

The module takes the parameters `PARPORT`, `DUALROM`, and `DRIVES` (clamped to 1–4); vectors of the per-drive ports (`reset`, `img_mounted`, LEDs, per-drive `sd_lba` and `sd_buff_din`); the shared IEC and parallel pins; the QNICE-side ROM write port (`rom_addr`, `rom_data`, `rom_data_o`, `rom_wr`, `rom_std`); and the `phys_*` bundle, exposed for drive 0 only.

From the 16 MHz `ce` a three-bit divider derives the drive's whole timebase: `ph2_r` and `ph2_f`, the rising and falling phases of the 2 MHz CPU clock, and `wd_ce`, the 8 MHz WD enable; `pause` gates all three between phases. The ROM arrangement is the part worth understanding. Two 32 KB ROM blocks exist, both preloaded from `c1581_rom.mif.hex` — the stock 1581 DOS 318045-02. Instance `rom` is the writable custom-DOS slot: QNICE writes it on the falling edge of `clk_sys` to install, for example, JiffyDOS-1581, and because it is *preloaded* with the standard DOS, a missing custom ROM file degrades to a stock drive rather than a dead one. Instance `romstd` is the never-written standard copy; `rom_std` selects which one the drives fetch from. Getting a Vivado-compatible, correctly-clocked writable slot here required replacing a Quartus-only construct — an Appendix C2 footnote.

Four drives share one ROM port by time multiplexing: a three-bit state counter, reset by `ph2_f`, places each drive's fetch address on the shared port in states 0–3 and captures the returned bytes in states 3–6 — all four fetches complete within a single 2 MHz CPU cycle, invisible to the CPUs. Bus combining is wired-AND with a safety twist: each drive's IEC and parallel contributions are OR-ed with its reset line, so a drive held in reset contributes a released ('1') bus; LEDs are masked to off in reset. The `phys_*` threading is asymmetric by design: outputs are collected per drive but only index 0 is exported, and drives beyond 0 get their physical inputs tied to zero — with `phys_byte_empty` tied to *one*, an empty FIFO — so only drive 0, the internal MEGA65 drive, can ever be physical.

Chapter 16 covers the clocking scheme this file's enable ladder belongs to; B5.2 and B5.3 describe the QNICE side of the ROM-loading path; B4.4 contrasts the 1541 equivalent.

#### B3.4 iec_drive.sv

```
 C64 core: IEC bus,       ┌────────────────────────────┐
 per-drive reset, mount ◀▶│         iec_drive          │◀▶ vdrives (QNICE clock):
 info, image type,        │  top of the drive stack:   │   doubled LBA, block
 physical-mode bit        │  a 1541 engine and a 1581  │   count, rd/wr strobes,
                          │  engine — never more than  │   buffer bytes
 QNICE ROM port         ◀▶│  one out of reset; image   │
 (address bit 15 picks    │  type picks the engine,    │◀▶ physical bundle
 1541 or 1581 ROM)        │  physical mode forces the  │   (threaded to drive 0)
                          │  1581                      │
                          └────────────────────────────┘
```

This is the top of the drive stack — the module `main.vhd` instantiates as `iec_drive_inst` — and its job is arbitration: per drive, decide whether the 1541 or the 1581 engine answers on the bus, adapt each engine's storage geometry to `vdrives.vhd`, split one ROM address space between two DOS ROMs, and thread the physical-mode bundle down to the 1581. It exists because a Commodore user does not mount "a 1541" or "a 1581"; they mount a file, and the file's type must pick the machine.

The type arrives as `img_type` alongside each mount: `00` for an emulated-GCR D64 (the 1541 disk-image format; GCR being the 1541's group-coded recording), `01` for real-GCR mode (G64, the raw GCR track-image format, or D64), `10` for a 1581 D81. A per-drive register `dtype` latches it on `img_mounted && img_size` — the size term means an unmount leaves the previous type in place — and the latch runs on `clk`, the core domain. That one clock choice is a MEGA65 correction with a story: upstream latched on `clk_sys`, valid on MiSTer where mounts originate in that domain, but in M2M the mount signals come from `vdrives.vhd` in the core domain, and sampling them on the wrong clock was an unsynchronized crossing that D64 survived only because `dtype` powers up to zero (equal to the 1541 encoding) while a D81 needed a real capture.

Both engines are always instantiated; safety comes from reset. The 1541's reset is `reset | dtype[1] | phys_mode_vec`, the 1581's is `reset | ~(dtype[1] | phys_mode_vec)`: the 1581 engine runs exactly when a D81 is mounted *or* physical mode is on — physical mode has no image but must still run the 1581 engine, backed by the mechanism — and the 1541 is held in reset in both cases. Because the IEC lines are AND-combined and a reset engine contributes '1', exactly one engine ever drives the bus; each engine's IEC inputs also include the other's outputs, preserving the wired-AND semantics of the real bus. `physical_mode` itself is a single bit, zero-extended onto drive 0 only (`phys_mode_vec`), and in physical mode drive 0's image transfers are masked off at the source: `sd_rd` and `sd_wr` are forced low, which is sufficient because `vdrives.vhd` acts only on those strobes.

The geometry adaptation is a small piece of translation the whole D81 path depends on: the FDC computes logical block addresses in 512-byte sectors, but the vdrives block unit is 256 bytes, so for a 1581 drive `sd_lba` is doubled and `sd_blk_cnt` is set to 1 — the field is count-minus-one, so each WD sector becomes two consecutive 256-byte blocks — while the 1581 engine sees only the low nine bits of the buffer address, a 512-byte window. The 1541 passes through untranslated with its own whole-track block counts. The ROM port is windowed by `rom_addr_i[15]`: low selects the 1541 ROM, high the 1581, and readback muxes the two with a select bit captured on the falling edge of `clk_sys` to stay aligned with the falling-edge ROM ports. Finally, the 1581's fast-serial input is tied to '1' and its fast-serial output left unconnected — the C64 has no fast serial, which is why that whole subsystem stays dormant (B3.2).

The `dtype` clock fix and the choice to gate engines by reset rather than multiplexers are Appendix C2 material. Chapter 10, the big picture, places this module in the whole stack; Chapters 11 and 12 trace the two media paths that fork here; B5.1 shows the `main.vhd` side of every port, and B5.5 the vdrives engine these blocks are served by.

### B4 — Peripherals (CORE/C64_MiSTerMEGA65/rtl/iec_drive/)

The B3 chapters covered the drive proper — the WD1772 (Western Digital floppy-disk controller) model and the 1581 structure built around it. This group covers the supporting cast: the 8520 CIA that is the drive computer's face to the outside world (B4.1), the 6522 VIA that exists only to host a parallel-port extension (B4.2), the virtual spindle that gives the image-backed drive its sense of rotation (B4.3), and finally a structural look across the aisle at the 1541, whose radically different anatomy explains, by contrast, why the 1581 model is shaped the way it is (B4.4). None of the three peripheral models carries MEGA65-specific modifications; every 1581-specific adaptation lives in the instantiating files of B3.

#### B4.1 iecdrv_mos8520.v

```
 drive-CPU bus: phi2,     ┌──────────────────────────┐
 register select, data, ◀▶│      iecdrv_mos8520      │◀▶ port A, 8 pins with
 chip select, R/W,        │  a generic 8520 CIA —    │   direction registers
 interrupt out            │  two ports, two timers,  │◀▶ port B, 8 pins
                          │  a 24-bit counter, a     │
 FLAG input             ─▶│  serial engine. What     │◀▶ CNT + SP: the fast-
 (edge → interrupt)       │  each pin MEANS is       │   serial pair (dormant
 TOD tick input         ─▶│  decided by the          │   in this core)
                          │  instantiation (B3.2)    │
                          └──────────────────────────┘
```

The 8520 CIA (Complex Interface Adapter) is the one general-purpose input/output chip in a real 1581, and so also in ours. Everything the drive computer says or hears passes through it: the IEC serial bus lines it senses and pulls, the ATN (Attention) edge that interrupts the drive's 6502, the motor and LED outputs, the media senses — ready, disk change, write protect — the device-number jumpers, and the timebase the DOS (Disk Operating System, the drive firmware) uses to measure time. Yet `iecdrv_mos8520.v` knows none of this: it is a **generic** model of the chip, and every 1581-specific meaning of a port bit is assigned by the instantiation in `c1581_drv.sv` (B3.2). The 8520 is the Amiga-family variant of the C64's 6526; the two differ in exactly one programmer-visible respect: the TOD (time-of-day) circuit is a 24-bit binary counter instead of a BCD (binary-coded-decimal) wall clock counting tenths, seconds, minutes and hours. The file header states its pedigree: a 6526 model by Rayne, timers and interrupts rewritten by slingshot ("Passes all Lorenz CIA Timer tests", and all VICE CIA tests except dd0dtest), converted to the 8520 by Sorgelig. We carry it unmodified from upstream MiSTer.

The module (`iecdrv_mos8520`, no parameters) presents four port groups. The CPU bus: `clk` plus `phi2_p`/`phi2_n`, the positive- and negative-phase enable pulses of the 2 MHz phi-2 (the 6502-family two-phase clock) — the model runs on the drive's core clock and advances only on these enables — with `res_n`, `cs_n`, `rw`, the four-bit register select `rs`, and `db_in`/`db_out`. In the 1581 the chip select decodes to `$4000` (the three-bit compare of the top address bits in `c1581_drv.sv`, named `ls193` after the equivalent decoder on the real board). The peripheral ports `pa_in`/`pa_out` and `pb_in`/`pb_out` have no direction pins at the boundary: the model drives a one on every bit configured as input (`pra | ~ddra`), and the instantiation closes the loop as `pa_in & pa_out` — which is exactly an open-drain pin with a pull-up: whoever pulls low wins. Then the handshake pair `flag_n` (edge-sensitive interrupt input) and `pc_n` (strobe output), the `tod` counting input, the serial pair SP (data) and CNT (clock) each as in/out, and `irq_n`, which the instantiation ANDs with the VIA's interrupt into the T65 (the drive's 6502 core).

The sixteen registers, selected by `rs`:

| Register | Read | Write |
| --- | --- | --- |
| `0`/`1` | port A / port B pin state | port output registers PRA / PRB |
| `2`/`3` | DDRA / DDRB | data-direction registers (1 = output) |
| `4`–`7` | running Timer A / B counter | timer reload latches |
| `8`–`A` | TOD latch, low/mid/high | TOD counter (or alarm, when CRB bit 7 is set) |
| `B` | always `0x00` | — |
| `C` | SDR (serial data register) | SDR (arms a transmit) |
| `D` | ICR flags; bit 7 mirrors the interrupt line | interrupt mask, set/clear protocol |
| `E`/`F` | CRA / CRB, unimplemented bits masked | control registers |

The two timers are 16-bit down-counters whose latches reset to `0xFFFF`. Timer A counts phi-2 or rising CNT edges (CRA bit 5); Timer B can additionally count Timer A underflows (CRB bit 6), optionally gated by CNT — the classic cascade into a 32-bit timer. A four-stage pipeline (`countA0`…`countA3`) reproduces the real chip's start and count latency, so a freshly started timer waits two phi-2 periods before its first decrement. Underflow raises the ICR (Interrupt Control Register) flag, reloads from the latch, drives PB6/PB7 in toggle or pulse mode if enabled, and in one-shot mode clears the start bit. Two authentic quirks are preserved: writing the high latch byte while the timer is stopped loads the counter (and in one-shot mode also starts it), and interrupt generation uses a shadow of the Timer B flag (`timer_b_int`, "for Timer B bug") separate from the readable bit — the hook that models the real chip's race in which an ICR read colliding with a Timer B underflow can eat the flag. Reading the ICR returns the flags and *schedules* a clear: at the next phi-2 enable all flags drop and `irq_n` releases — the CIA's read-clears-all semantics, in contrast to the VIA of B4.2. Writing the ICR is the set/clear protocol: data bit 7 decides whether the written bits set or clear mask bits.

The TOD is a free-running 24-bit binary counter that increments on each rising edge of the `tod` input while running; writing its low byte starts it, writing its high byte stops it (with CRB bit 7 those writes load the alarm instead), and reading the high byte freezes a latch that reading the low byte thaws, so a three-byte read is always coherent. The 1581 wiring is the point to remember: `c1581_drv.sv` connects `tod` to `ph2_f`, so **the TOD counts the drive CPU's own 2 MHz clock, not wall time** — the DOS gets a free-running 24-bit timebase that wraps every 8.4 s, not a clock. The FLAG input (falling edge sets ICR bit 4, with a catcher register for edges that fall between phi-2 enables) is wired to ATN: every ATN assertion by the C64 interrupts the drive computer, which is how the 1581 answers the bus within the IEC protocol deadline. The `pc_n` strobe, which pulses low for one phi-2 period after every port B access, is left unconnected — matching real 1581 usage.

Finally the serial engine, the hardware behind Commodore's fast-serial burst protocol. Direction is CRA bit 6. Receiving, each rising CNT edge shifts SP into a shift register most-significant-bit first; the falling edge that completes the eighth bit transfers the byte to the SDR and raises ICR bit 3. Transmitting, a write to the SDR arms the engine; the bit clock is derived from Timer A — CNT toggles once per underflow, so one bit spans two Timer A periods — and a fresh bit is placed on SP when CNT falls, stable for the receiver to sample on the rise; after eight pulses the flag fires and transmission stops. In the 1581 wiring SP listens on the IEC DATA line and CNT on the fast clock FCLK, with PB5 switching direction. And then the punchline: **the engine is dormant.** Only the C128, with its SRQ pin, has a fast-serial wire; the C64 does not, so at the top of the drive stack `iec_drive.sv` ties `iec_fclk_i` to a constant one and leaves `iec_fclk_o` unconnected ("C64 has no fast serial"), and FCLK is wire-ANDed only among the 1581 drives themselves inside `c1581_multi.sv`. The burst hardware is present, correct, and waiting for a host that can talk to it.

Worth knowing when reading DOS listings against this model: register `B` reads `0x00` (an 8520 has no fourth TOD byte); CRA reads mask bits 7 and 4 and CRB reads mask bit 4; port B reads show the timer output overrides on PB6/PB7, because the pin feedback includes `pb_out`; and dd0dtest is the one VICE CIA test the model is known not to pass. How the media senses this chip reads were re-pointed at the real mechanism in physical mode is `c1581_drv.sv`'s story (B3.2, and the Appendix). Section A Chapter 5 explains why an intelligent drive carries such a chip at all; Chapter 6 places it in the 1581's anatomy; Chapter 12 shows what flows through it in physical mode.

#### B4.2 iecdrv_via6522.vhd

```
 drive-CPU bus: clock    ┌───────────────────────────┐
 with phi-2 enables,   ◀▶│      iecdrv_via6522       │◀▶ port A and port B —
 4-bit register select,  │  a generic 6522 VIA:      │   each pin an explicit
 data, read/write        │  two ports, two timers,   │   driven-value /
 strobes, interrupt      │  shift register,          │   direction / sense
                         │  handshake pins           │   triple
                         │  (CA1/CA2, CB1/CB2)       │
                         │  — in the 1581: only the  │
                         │  parallel-port extension  │
                         └───────────────────────────┘
```

This file models the MOS 6522 VIA (Versatile Interface Adapter), the 6502-family input/output companion that predates the CIA. It is Gideon Zweijtzer's model — the header notes "A LOT OF REVERSE ENGINEERING", with refinements credited to gyurco, and the architecture is fittingly named `Gideon` — and we carry it unmodified. In this repository the VIA's real home is the 1541, which carries two of them (B4.4). Inside the 1581 model a single instance appears for one reason only: **to host a parallel-port extension that no stock 1581 ever had.** A real 1581 contains one 8520 and a WD1772 and no VIA at all.

The entity (`iecdrv_via6522`, no generics) takes `clock` with `rising`/`falling` phi-2 enables and `reset`; a four-bit `addr` with `wen`/`ren` and `data_in`/`data_out`; and a `phi2_ref` output mirroring the reconstructed phase. Its pin model differs instructively from the 8520 file: instead of the wired-AND convention, every port is an explicit triple — `_o` (driven value), `_t` (direction), `_i` (pin sense) — for ports A and B, and likewise for the handshake pins CA2, CB1 and CB2, with CA1 input-only. The `irq` output is active-high; `c1581_drv.sv` folds it into the CPU interrupt as `cia_irq_n & ~via_irq`.

Structurally the VIA is a different dialect of the same idea as the CIA, and the differences are what a reader of drive firmware needs. The register file puts B before A — ORB/ORA at addresses `0`/`1`, DDRB/DDRA at `2`/`3`, the reverse of the CIA's ordering — then Timer 1 at `4`–`7` (counter and reload latch separately addressable), Timer 2 at `8`/`9`, the shift register at `A`, ACR (Auxiliary Control Register) at `B`, PCR (Peripheral Control Register) at `C`, IFR/IER (interrupt flag and enable registers) at `D`/`E`, and ORA-without-handshake at `F`. Timer 1 can free-run (ACR bit 6) and toggle PB7 (bit 7); Timer 2 one-shots or counts PB6 falling edges (bit 5). The four handshake pins have programmable active edges, and CA2/CB2 offer handshake, pulse and fixed-level output modes via the PCR; the ports can latch their inputs on a CA1/CB1 event (ACR bits 0–1). An 8-bit shift register clocks data in or out on CB2 with CB1 as clock, in eight ACR-selected modes — Timer-2-paced, phi-2-paced, or externally clocked. And where the CIA clears every interrupt flag on one ICR read, the VIA clears flags per source on specific accesses: reading Timer 1's low counter byte clears the Timer 1 flag, reading or writing ORA clears the CA1/CA2 flags, and so on. One reverse-engineered detail deserves its own sentence: `latch_reset_pattern = X"5550"` — the timer latches and counters wake up as `0x5550`, not zero, matching observed silicon.

In the 1581 instantiation the VIA sits at `$2000` (`ls193` decode, one below the CIA). Port A carries the parallel data in both directions, CA2 drives the outgoing strobe, CB1 senses the incoming strobe, CA1 is tied high, and port B simply loops back on itself. This mirrors the DolphinDOS-style parallel cable of a modified 1541 — data plus two strobes — so the same fabric plumbing (`par_*`, wire-ANDed up through `c1581_multi.sv` and `iec_drive.sv`, B3.3/B3.4) serves both drive types, and software ecosystems built around parallel-cabled drives find the same hardware shape here. Section A Chapter 5 gives the background on drive-side I/O chips; B4.4 shows this same entity doing its original job, twice, in the 1541.

#### B4.3 floppy.v

```
 select, motor ─────────▶ ┌─────────────────────┐──▶ ready (spinning at rate)
 step pulses + direction  │       floppy        │──▶ index (active-low, 5 ms
 (from the WD model)    ─▶│  the virtual        │    pulse per 200 ms turn)
                          │  spindle: a 300 RPM │──▶ current track number
                          │  rotation and       │──▶ sector now under the head
                          │  geometry model for │──▶ dclk_en: the 32 µs
                          │  image mode only    │    byte tick
                          └─────────────────────┘
```

`floppy.v` is the virtual spindle of the image-backed drive: a model of rotation, index and track geometry, written by Till Harbaum in 2015 for the MiST project (an earlier FPGA — field-programmable gate array — retro platform; the commented-out Acorn Archimedes and Atari ST defaults are still in the file). It is best understood as **a clock, not a data path**. It never touches a byte of disk data; it continuously answers one question — *if this were a real spinning disk, what would be under the head right now?* — and the WD1772 model paces all of its data movement off the answers, which is why loading from a D81 (the 800 KB 1581 disk-image format) takes realistic time. It serves **image mode only**: in physical mode, `fdc1772.v` switches its ready and index sources over to the real mechanism (the `floppy_ready` and `fd_index_eff` multiplexers, B3.1), and the virtual spindle's answers go unused.

The module has one parameter, `CLK_EN = 8000`: the rate of the `clk8m_en` enable in kHz, from which every millisecond constant scales. The 1581 feeds it the 8 MHz `wd_ce` from `c1581_multi.sv`. Control inputs `select`, `motor_on`, `step_in`, `step_out` come from the floppy disk controller (FDC) model; the geometry inputs — `sector_len`, `sector_base` (a single-bit port: 0 for Archimedes-style images, 1 for DOS-style), `spt` (sectors per track), `sector_gap_len`, `hd`, `fm` — are latched per drive at mount time. (`fm` selects the single-density FM — frequency modulation — data rate versus double-density MFM, modified frequency modulation; only the *rate*: the encoding itself is fdc1772's business.) Outputs: the byte strobe `dclk_en`, the head position `track`, the passing `sector` with `sector_hdr`/`sector_data` window flags, `ready`, and `index`. `fdc1772.v` instantiates one `floppy` per drive and demultiplexes the selected drive's outputs.

The mechanism is four small machines sharing one timebase. First, spin-up: the spindle's speed *is* the register `rate`, ramped linearly by a fractional accumulator from zero to the nominal data rate when the motor turns on and back down when it stops — full speed in `SPINUP = 500` ms, spin-down in `SPINDOWN = 300` ms. The nominal rate follows density: `RATESD`/`RATEDD`/`RATEHD` are 125/250/500 kbit/s, and the D81 is double density at 250 kbit/s. Second, the byte clock: another accumulator adds `rate` on every `clk8m_en` tick and toggles a bit clock each time it crosses `CLK_EN*1000/2`; dividing by eight yields `dclk_en` — at full double-density speed exactly one strobe per 32 µs, one disk byte. Below full speed the strobe runs proportionally slower, so "no valid data until the disk is up to speed" is not a special case but an arithmetic consequence. Third, rotation: a byte counter wraps at `BPTDD = 6250` bytes per track (derived as rate × 60 ⁄ (8 × `RPM`), with `RPM = 300` — one revolution per 200 ms) and the wrap fires the index: the `index` output drops low for `INDEX_PULSE_LEN = 5` ms and idles high — **an active-low pulse**, whose falling edge the WD model watches for spin-up counting, motor idle timeout, and Force-Interrupt-on-index. Fourth, stepping: rising edges on `step_in`/`step_out` move `current_track` by one, clamped to 0…`TRACKS-1`, and arm `STEPBUSY = 18` ms of head-settle time. Layered over the byte clock, a three-state carousel walks the track as gap → header (`SECTOR_HDR_LEN = 6` bytes) → data (`sector_len` bytes) → gap, restarting at the index with sector one and wrapping after `sector_base + spt − 1`, at an interleave of one — so `sector` and its window flags tell the WD1772 which ID field or payload is passing the head, and a Read Sector command waits an authentic fraction of a revolution for its target. `ready` is simply: selected, at full speed, and not stepping; through fdc1772 it becomes the CIA's PA1 ready sense that the DOS polls before every command (B3.2, B4.1).

Who sets the dials for a D81 is `fdc1772.v` at mount: an 819,200-byte image is 1600 sectors of 512 bytes → double-sided, 800 per side → `image_spt = 10` and `image_gap_len = 107`; the arithmetic closes exactly, since 10 × (512 + 6 + 107) is 6250 bytes — one full track. `hd` and `fm` are 0, and `SECTOR_BASE = 1` numbers the physical sectors 1–10.

The constants deserve a table, because several are honest guesses and one is a trap:

| Constant | Value | In-source note |
| --- | --- | --- |
| `CLK_EN` | 8000 kHz | parameter; the 1581 feeds the 8 MHz `wd_ce` |
| `RATEDD` | 250,000 bit/s | the D81 rate (`RATESD` 125 k, `RATEHD` 500 k) |
| `RPM` | 300 | 200 ms per revolution |
| `SPINUP` | 500 ms | adjacent comment still says "800ms" — the constant governs |
| `SPINDOWN` | 300 ms | marked "GUESSED" |
| `INDEX_PULSE_LEN` | 5 ms | "fd1036 data sheet says 1~8ms" |
| `SECTOR_HDR_LEN` | 6 bytes | marked "GUESSED" |
| `STEPBUSY` | 18 ms | head-settle time |
| `TRACKS` | 85 | step clamp — see below |
| `BPTDD` | 6250 bytes/track | derived |

`TRACKS = 85` is the one to read correctly: it is a **lineage clamp** ("max allowed track") inherited from the Archimedes/ST ancestry, not D81 geometry. The D81 uses 80 tracks; it is the DOS, not this model, that decides where the head goes, and the clamp merely keeps a runaway seek on the rail. Two smaller quirks: the carousel's restart value (`start_sector`) is fixed at one regardless of `sector_base` — harmless for the 1581, whose sectors start at one anyway — and since the "guessed" header and gap lengths only shape *timing*, not data, their inaccuracy costs at most a little realism. Section A Chapter 3 explains the track structure this module paces out; Chapter 4 the controller that consumes it; Chapter 11 walks the whole image-backed path this spindle drives.

#### B4.4 The 1541 side, briefly (c1541_drv.sv / c1541_multi.sv, structural contrast)

Nothing clarifies the 1581 model's architecture like the drive next door. Both engines live in the same directory, share the IEC bus, the ROM-loading plumbing and the `sd_*` block interface (named after MiSTer's SD-card convention, served here by vdrives), and yet their middles could hardly differ more: where the 1581 is *chip-accurate around a sector-level floppy controller*, the 1541 is *chip-accurate around a bit-level GCR stream* — GCR being Group Coded Recording, Commodore's own four-bits-into-five flux encoding.

`c1541_drv.sv` contains one 1541. Its `c1541_logic` holds the 6502 and **two** 6522 VIAs (B4.2): instance `uc1` faces the world — it drives and senses the IEC lines, provides the hardware ATN-acknowledge, and carries the parallel cable on port A with CA2/CB1 strobes — while `uc3` runs the mechanism: the two stepper-phase bits, motor, activity output, and the density (`freq`) select. There is no floppy controller chip and no `floppy.v`. Instead, `c1541_gcr` synthesizes the rotating medium itself: it serves the DOS a continuous GCR byte stream with sync-mark detect (`sync_n`) and byte-ready (`byte_n`) handshakes, converting on the fly between D64 sector data (the 1541 disk-image format) and GCR. Behind it, `c1541_track` — in the QNICE clock domain, QNICE being the 16-bit helper CPU that fills the images — stages **one whole track per transfer** using multi-block `sd_blk_cnt` bursts, versus the 1581 path's one 512-byte sector at a time. Head position is a half-track counter, 0–84, stepped by delta-decoding `uc3`'s stepper phases (it resets to half-track 36, track 19 under the GCR model's `track[6:1]+1` mapping), and a `save_track` toggle flags a dirty track for write-back when the head moves or activity stops. Even media status is firmware-visible rather than controller-mediated: a mount arms a roughly two-second countdown during which the write-protect sense *flickers* (`wps_n = ~readonly ^ ch_timeout[23]`), so the DOS's photocell logic registers a disk swap — the 1541's analogue of the 1581's disk-change latch. Raw-GCR (G64) support exists but is disabled in this port: the `c1541_direct_gcr` instance is commented out with its outputs tied inert. The drive LED is `act | sd_busy`.

`c1541_multi.sv` is the counterpart of `c1581_multi.sv` (B3.3), with two instructive differences. Clocking: from the common 16 MHz enable, the 1541 wrapper derives a **1 MHz** phi-2 with a four-bit divider, where the 1581's uses a three-bit divider for **2 MHz** plus the 8 MHz `wd_ce` — the entire clock contrast between the two drive computers, visible in two divider registers. And the shared DOS ROM (read-only memory): one ROM — a 32 KB DolphinDOS image when the parallel port is enabled, with a stock-ROM fallback initialization so a missing JiffyDOS file degrades to a working standard drive — is time-multiplexed among up to four drives by a small state machine that, in the first few core-clock cycles after each phi-2 falling edge, presents the four drives' ROM addresses in turn and captures the four bytes. That is affordable because each drive's 6502 needs its byte only once per 1 µs. ROM-size heuristics are written on the falling edge of the QNICE clock (the QNICE convention) and cross into the drive clock domain through an `xpm_cdc_array_single` (a CDC — clock-domain-crossing — synchronizer), gating the parallel-port enable; IEC and parallel outputs are wire-ANDed, with a drive held in reset contributing a harmless one.

The structural moral, in one sentence each way: the 1541 is a CPU-plus-VIA *bit engine* over a soft-sectored GCR track cache — no index hole, sync marks living in the flux, the drive computer doing its own encoding; the 1581 is a CPU-plus-CIA *command engine* over a WD1772 MFM sector machine — index pulse, ID fields, CRCs (cyclic redundancy checks), sector-level transfers. That is exactly why the 1581 model needs `floppy.v` and the 1541 model does not: the WD1772 must be *told* what a spinning disk feels like, while `c1541_gcr` *is* the spinning disk. It is also why our physical path (Section A Chapter 12) attaches to the 1581 side and nowhere else — the WD boundary is a natural seam, and the 1541 has no such seam. `iec_drive.sv` (B3.4) arbitrates which of the two engines owns the bus.

### B5 — Integration glue

The chapters so far described the decode chain, the controller, and the drive proper as self-contained machines. This group walks the seams between them: the files that decide which clock each block runs on, which wires cross between domains, and how the QNICE helper CPU (the 16-bit soft processor that runs the Shell, the menu-and-file firmware) reaches into all of it. Section A Chapters 10 through 12 tell this story architecturally; here we follow the actual signals.

#### B5.1 CORE/vhdl/main.vhd (the 1581 portions)

`CORE/vhdl/main.vhd` is the machine room of the port: everything that must live in lockstep with the C64 — the MiSTer core itself, the simulated drives, and the glue that binds the physical-1581 stack to both — is instantiated here. This chapter covers only its drive-related portions.

The entity `main` runs on `clk_main_i` (about 31.53 MHz) and additionally receives the QNICE 50 MHz clock as `c64_clk_sd_i`. Its drive-related port groups are: the drive LED (`drive_led_o` plus a 24-bit RGB color), the QNICE register window for the virtual-drive engine (`c64_qnice_*`, forwarded from `mega65.vhd`), the hardware IEC port (the physical serial-bus connector), the physical-1581 group — the mode bit `phys_1581_en_i`, the 50 MHz reset `c64_rst_sd_i`, and the eleven mechanism pins `f_rdata_i`, `f_index_i`, `f_track0_i`, `f_writeprotect_i`, `f_diskchanged_i`, `f_motora_o`, `f_selecta_o`, `f_side1_o`, `f_stepdir_o`, `f_step_o`, `f_density_o` — the read-only diagnostic port (`phys_diag_*`), and the shared drive-ROM write carrier (`c1541rom_*`).

Five instances carry the drive stack. `iec_drive_inst` (Chapter B3.4) runs on `clk_main_i` with `DRIVES => G_VDNUM` and holds the drive computer. `vdrives_inst` (Chapter B5.5) bridges its MiSTer-style mount interface to QNICE, with `BLKSZ => 1` selecting 256-byte blocks — the Commodore sector size. `i_physical_1581_controller`, `i_physical_1581_rdfifo` and `i_physical_1581_diag` (Chapters B2.1, B2.3, B2.4) form the physical path; the controller and the diagnostic bank are clocked by `c64_clk_sd_i` and reset by `c64_rst_sd_i`, and the `f_*` pins connect only to the controller. The controller is instantiated with `G_CAPABLE => true` on every board: the feature is gated at run time by the On-Screen Menu (OSM) bit `phys_1581_en_i`, never by synthesis.

Three pieces of local logic do the actual binding. First, the drive-reset equation: `iec_drives_reset(0)` holds drive 8 in reset unless the core runs and either an image is mounted or `phys_1581_en_i` is set. The exception is essential — in physical mode there is no image to mount, and without it the drive computer would stay dead until the user mounted an unrelated image. Second, the interlock: `prevent_reset` is asserted whenever any `cache_dirty` bit from `vdrives_inst` is set; it vetoes soft resets (`reset_core_int_n <= prevent_reset and (not reset_hard_i)`), gates cartridge-driven resets, and turns the drive LED from green (`x"00FF00"`) to yellow (`x"FFFF00"`) while unwritten data awaits its flush to the SD card. Third, the busy word: `img_drive_busy <= (c64_drive_led and not phys_1581_en_i) or prevent_reset` — "the image drive is active or holds unsaved data" — is two-flip-flop-synchronized into the 50 MHz domain and handed to the diagnostic bank, where the Shell reads it as one half of the idle gate (Chapter B5.6). The LED is masked with the mode bit because in physical mode the LED shows physical activity (the 1581 DOS blink pattern, for instance), which would otherwise spuriously block a switch back to image mode.

Two clocking details are worth knowing. The 16 MHz clock enable for the drives comes from a fractional accumulator (`iec_drive_ce_proc`): every `clk_main_i` cycle adds 16,000,000, and when the sum reaches `clk_main_speed_i` it subtracts and pulses `iec_drive_ce` — an average of exactly 16 MHz from a clock that is not 32 MHz. The speed input is deliberately the vanilla `CORE_CLK_SPEED` even in HDMI flicker-free mode, preserving the C64-to-drive frequency ratio. And the read FIFO's two Gray-pointer sides both reset from one common event, the QNICE reset — the read side through the two-flip-flop synchronizer `p1581_fiforst_sync_proc` — never from `reset_core_n`, because a one-sided reset would desynchronize the pointers permanently; leftovers after a core reset are drained by the WD1772 front end instead. All request/acknowledge signalling across the `clk_main_i`/50 MHz boundary uses toggle handshakes, where one inverted level equals one event.

Section A Chapter 16 explains these domain and reset rules from first principles; Appendix C2 (era 2) tells how the FIFO reset rule was learned.

#### B5.2 CORE/vhdl/mega65.vhd

`CORE/vhdl/mega65.vhd` declares `MEGA65_Core`, the contract entity between the core and the MiSTer2MEGA65 framework. For the drive stack it plays three roles: it decodes QNICE device accesses, it arbitrates HyperRAM (the MEGA65's external 8 MB RAM), and it passes wires through — the `f_*` floppy pins and IEC pins travel from the board top to `main` untouched.

The framework hands the core the 256-bit OSM state twice, once per clock domain (`qnice_osm_control_i` and `main_osm_control_i`); the clock-domain crossing (CDC) lives in the framework. The flat menu index of "Use internal 1581" is `C_MENU_INTERNAL_1581 = 3`, and `phys_1581_en <= main_osm_control_i(C_MENU_INTERNAL_1581)` deliberately uses the main-clock copy, so `main` receives a clean main-domain level. The hardware IEC port is enabled the same way from `C_MENU_IEC`. Into `i_main` go `phys_1581_en_i => phys_1581_en`, `c64_rst_sd_i => qnice_rst_i` — the physical controller's reset is the QNICE reset — and the eleven `f_*` pins.

The combinational process `core_specific_devices` is the QNICE device switchboard: a case on `qnice_dev_id_i` with one arm per device ID from `globals.vhd`. The drive-related arms are: `C_VD_DEVICE` forwards chip-enable and write-enable into `vdrives_inst` inside `main`; `C_DEV_C64_MOUNT` forwards to the mount-buffer bridge including a wait-state; `C_DEV_C64_KERNAL_C1541` and `C_DEV_C64_KERNAL_C1581` share one physical ROM write carrier, with bit 15 of the address bus steering between the 1541's 16 KB window (`'0'`) and the 1581's 32 KB DOS ROM window (`'1'`); and `C_DEV_C64_PHYS1581` raises `phys_diag_ce` and returns `phys_diag_data` with no wait-state — writes are ignored, the bank is strictly observational. The diagnostic address is simply `qnice_dev_addr_i(7 downto 0)`, allowing up to 256 register words; the map is documented in [the debug-device reference](1581_dd_debug_device.md).

The mount buffer itself is `i_mount_buf_wrapper`, instantiated with `G_BASE_ADDRESS => C_HMAP_VD0(9 downto 0) & X"000"`. Its QNICE side speaks the same byte protocol as the old block-RAM (BRAM) buffer once did; its other side is an Avalon master into HyperRAM (Avalon being the memory-mapped bus protocol the framework's HyperRAM fabric speaks). This matters: a D81 image is 800 KB, far beyond the FPGA's BRAM budget, so the disk image is staged in HyperRAM at window `C_HMAP_VD0` — the buffer is HyperRAM-backed, not BRAM. Three masters share the HyperRAM through `i_avm_arbit` (`G_NUM_SLAVES => 3`): index 0 is the simulated REU (RAM Expansion Unit, the C64's memory-expansion cartridge), 1 the cartridge stager, 2 the mount buffer. The mount slave only touches HyperRAM during mount, block serving and flushing — QNICE-paced, under 1% of bandwidth — so it cannot starve the real-time REU.

One habit worth copying: the OSM indices in this file are machine-checked against the menu structure by `python3 M2M/rom/tests/menu_test.py verify`, so a menu edit cannot silently shift the hardware bits. Section A Chapter 10 places this file in the whole; Chapter 17 covers the diagnostic device it exposes.

#### B5.3 CORE/vhdl/globals.vhd

`CORE/vhdl/globals.vhd` is a pure constants package — no logic — but it is where the drive stack's address space is legislated: QNICE device IDs, the HyperRAM map, the virtual-drive roster, and the JiffyDOS auto-load list all live here, and both the VHDL and the Shell derive from it.

The drive-related device IDs are:

| Constant | ID | Purpose |
| --- | --- | --- |
| `C_DEV_C64_VDRIVES` | `0x0101` | the `vdrives.vhd` register bank |
| `C_DEV_C64_MOUNT` | `0x0102` | the disk-image mount buffer (HyperRAM-backed) |
| `C_DEV_C64_KERNAL_C1541` | `0x0106` | custom DOS ROM, simulated 1541 (16 KB) |
| `C_DEV_C64_KERNAL_C1581` | `0x0107` | custom DOS ROM, simulated 1581 (32 KB) |
| `C_DEV_C64_PHYS1581` | `0x0108` | physical-1581 read-only diagnostic bank |

The HyperRAM map is expressed in windows of 4 kilowords (8 kB):

```
window     region
0x0000 ─┬─ M2M framework           4 MB (ascal frame buffer, QNICE)
0x0200 ─┼─ cartridge staging       up to 2,834,432 bytes (C_CRT_MAX_SIZE)
0x035A ─┼─ D81 mount buffer        100 windows = 819,200 bytes: one D81
0x03BE ─┼─ guard                   8 kB, absorbs a one-past-the-end write
0x03BF ─┼─ simulated REU           512 KB
0x03FF ─┴─ guard                   final window of the 8 MB
```

`C_HMAP_M2M = 0x0000` reserves the framework region; `C_HMAP_CRT = 0x0200` stages software cartridges; `C_HMAP_VD0 = 0x035A` is the drive-8 image staging area, ending at `0x03BD`; `C_HMAP_VD0_GUARD = 0x03BE` and the final window are guards; `C_HMAP_REU = 0x03BF` holds the simulated REU. Each region is followed by slack or an explicit guard so a spurious write one window past a boundary cannot corrupt its neighbor (the guard concept traces to the open research issue #218). The maximum cartridge size is not a literal but derived — `C_CRT_MAX_SIZE` equals the CRT-to-VD0 distance in bytes (2,834,432) — and `make_rom.sh` exports it to the Shell, so an oversized cartridge can never stream into the D81 buffer and the two sides cannot drift apart on a map retune.

The virtual-drive roster is minimal: `C_VDNUM = 1` — exactly one virtual drive, C64 device 8 — with `C_VD_DEVICE = C_DEV_C64_VDRIVES` and a `C_VD_BUFFER` array of one buffer device (`C_DEV_C64_MOUNT`), terminated by `0xEEEE`. The Shell reads this roster at boot (`VD_INIT`), so adding a drive 9 one day is a constants-and-menu change, not a firmware rewrite.

Finally, the JiffyDOS auto-load list: `C_CRTROMS_AUTO_NUM = 3`, naming `/c64/jd-c64.bin`, `/c64/jd-c1541.bin` and `/c64/jd-c1581.bin`, each typed `C_CRTROMTYPE_DEVICE` with its target kernal device and marked `C_CRTROMTYPE_OPTIONAL`. The 1581 entry is a full 32 KB replacement of the DOS ROM (unlike the concatenated C64 file) and is appended as entry two so a missing file degrades gracefully — the drive then runs the stock DOS preloaded into its ROM by the synthesis-time `INITFILE` in `c1581_multi.sv`. Also defined here: `CORE_CLK_SPEED_PAL = 31_527_778` Hz and `QNICE_CLK_SPEED = 50_000_000` Hz, the two numbers behind every clock claim in this book. Section A Chapter 16 explains why they must be exact.

#### B5.4 M2M/vhdl/top_mega65-rX.vhd (the floppy pins)

The four board tops — `M2M/vhdl/top_mega65-r3.vhd` through `top_mega65-r6.vhd`, one per MEGA65 board revision — are where signal names become FPGA pins. For the 1581 they answer one question: which wires of the internal 3.5-inch mechanism reach the core, and which are nailed down.

Each top's port list carries fifteen floppy pins. Eleven form the read path and pass straight into `MEGA65_Core`: the inputs `f_rdata_i` (raw flux), `f_index_i`, `f_track0_i`, `f_writeprotect_i`, `f_diskchanged_i`, and the outputs `f_motora_o`, `f_selecta_o`, `f_side1_o`, `f_stepdir_o`, `f_step_o`, `f_density_o`. The remaining four never reach the core at all. In the tie-off section of every top:

```vhdl
f_motorb_o    <= '1';
f_selectb_o   <= '1';
f_wdata_o     <= '1';
f_wgate_o     <= '1';
```

Floppy control lines are low-active, so `'1'` means deasserted: drive B (the MEGA65's connector supports a second mechanism) is never selected, and the write gate and write data lines are held inactive. This is the hardware safety net of the read-only design: no matter what any logic upstream does, the FPGA is physically incapable of asserting a write onto a diskette. The tie-offs are identical on all four boards, as is the pass-through of the eleven read-path pins into the `CORE` instance.

That uniformity is the point worth stating plainly: the physical-1581 path is not board-gated. Every top routes the same pins, and `main.vhd` instantiates the controller with `G_CAPABLE => true` on every revision. What decides whether the feature is active is the OSM bit and the Shell's idle gate (Chapter B5.6), at run time, per user choice. The read path has been qualified against real hardware on R3; the other revisions synthesize the identical logic against the same pin contract.

One neighboring wire deserves a mention because readers often look for it here: the drive LED. `MEGA65_Core` outputs `main_drive_led` and its RGB color, the top hands both to the framework, and the framework drives the MEGA65 keyboard's floppy LED — so the green/yellow cache semantics described in Chapter B5.1 end at a real light above a real drive slot. Section A Chapter 12 describes the read-only milestone this pinout serves; Chapter 18 discusses the safety reasoning; the Appendix records when writing is expected to arrive.

#### B5.5 M2M/vhdl/vdrives.vhd

```
 QNICE (the Shell):        ┌────────────────────────┐  the drive (fdc1772 via
 register window — mount ◀▶│        vdrives         │◀▶ iec_drive): mount pulse
 strobes, image size and   │  the virtual-drive     │   + size + type out;
 type, block serving,      │  engine: MiSTer's      │   block requests (LBA,
 cache-dirty flags,        │  host protocol, played │   count, rd/wr) in;
 flush timing              │  by the Shell instead  │   buffer bytes both ways
                           │  of an ARM processor   │
                           └────────────────────────┘
```

`M2M/vhdl/vdrives.vhd` exists because MiSTer cores are written against a host they do not have here. On the DE10-Nano, an ARM processor (the "HPS") mounts disk images and serves blocks over a private protocol; the drive RTL (register-transfer level — its synthesizable hardware description) just raises `sd_rd` and expects sectors to appear. `vdrives` is the hardware half of that host, re-implemented as a register file that the QNICE Shell operates — the drive never learns that its "SD card" is firmware.

The entity takes two generics, `VDNUM` (number of drives; one here) and `BLKSZ` (block size; the C64 core passes 1, meaning 256 bytes), and two clocks. On the core clock it outputs the MiSTer mount interface: a strobed `img_mounted_o` per drive plus shared `img_readonly_o`, `img_size_o` and `img_type_o` (for us: `00` D64, `01` G64, `10` D81 — the value that makes `iec_drive.sv` activate its 1581 engine), the latched `drive_mounted_o`, and the cache flags. On the QNICE clock it accepts the block-serve interface — per-drive `sd_lba_i` (Logical Block Address, the linear block number into the image), `sd_blk_cnt_i`, `sd_rd_i`/`sd_wr_i`/`sd_ack_o` — plus the byte-level buffer port `sd_buff_addr_o`/`sd_buff_dout_o`/`sd_buff_din_i`/`sd_buff_wr_o`, and the 28-bit QNICE register window.

The Shell sees two kinds of 4k windows. Window 0 holds the control registers: mount strobe, read-only flag, image size and type, the buffer-pump registers, and the latched `drive_mounted`. Window `1 + n` is drive n's bank: the requested LBA, the block count, `sd_rd`/`sd_wr`/`sd_ack`, and — a firmware speed-up — hardware-precomputed conversions of the LBA into bytes and into 4k-window/offset form. Mounting follows the reverse-engineered MiSTer contract documented in the file header: write size, read-only flag and type first, then strobe the drive's `img_mounted` bit; strobing with size zero unmounts. `handle_drive_mounted` latches the strobe into `drive_mounted_reg`, which is what `main.vhd` uses in the drive-reset equation. Serving a read means: see `sd_rd_i` high, assert `sd_ack`, pump 256 bytes through the buffer port — the drive's internal RAM uses `sd_ack and sd_buff_wr` as its write enable — then drop the acknowledge.

Three `xpm_cdc_array_single` primitives carry everything across the clock boundary: mount/dirty/flushing and readonly/type/size travel QNICE-to-core, reset and `drive_mounted` travel core-to-QNICE. QNICE-side registers are written on the falling edge of `clk_qnice_i`, per the QNICE memory-mapped I/O convention.

The write-back machinery is the part users actually notice. Acknowledging a drive write sets `cache_dirty` — the image in HyperRAM now differs from the file on the SD card. A countdown restarts on every further write; only after the anti-thrashing delay (default 2000 ms, two full seconds of quiet) does the flush-start flag tell the Shell to write the buffer back to the FAT32 file. The Shell clears `cache_dirty` when done. On the core side, that same flag is what `main.vhd` turns into `prevent_reset` and the yellow LED (Chapter B5.1) — the whole "wait for the LED" discipline in the help text is this one register bit, seen end to end. Section A Chapter 11 walks a complete mount-and-serve sequence through this engine.

#### B5.6 CORE/vhdl/config.vhd and the Shell (mount flow, the idle gate)

The user-visible surface of everything above is two adjacent lines in the OSM, defined in `CORE/vhdl/config.vhd`. In `OPTM_ITEMS`, line `" 8:%s\n"` is the drive-8 mount item — the `%s` renders as `<Mount Drive>` or the mounted filename — and `" Use internal 1581\n"` is the media switch. Their entries in the parallel `OPTM_GROUPS` array give the first the group `OPTM_G_MOUNT_8 + OPTM_G_MOUNT_DRV + OPTM_G_START` (group one, a mount item, the cursor's home) and the second `OPTM_G_INT1581 + OPTM_G_SINGLESEL` (group 31, a single-select toggle, default off — image mode). A menu item's position is its flat OSM bit; "Use internal 1581" sits at index 3, which is exactly `C_MENU_INTERNAL_1581` in `mega65.vhd` and `C64_OSM_INTERNAL_1581` in the Shell's `osm_const.asm` — three files, one number, guarded by `menu_test.py`. Help page three carries the two operational warnings: never attach an external IEC device as number 8, and wait out the yellow LED before unmounting, resetting or powering off.

The mount flow, at summary level, is a relay race across four of the files in this group. Selecting the mount item opens the Shell's file browser in the disk-image context; the core's `FILTER_FILES` callback (`CORE/m2m-rom/m2m-rom.asm`) shows only `.D64` and `.D81` files — intentionally not `.G64`. `PREP_LOAD_IMAGE` validates the choice: a D81 must be exactly 819,200 bytes (`0x000C8000`), because error-info variants would feed the 1581 a wrong geometry; the accepted file is typed `C64_IMGTYPE_D81 = 0x0002`, matching the hardware's `img_type` legend. The Shell then streams the file through device `C_DEV_C64_MOUNT` into HyperRAM window `C_HMAP_VD0` and calls `VD_STROBE_IM` (`M2M/rom/vdrives.asm`), which writes size, read-only flag and type into `vdrives.vhd` and strobes the mount bit. From then on the Shell's main loop plays block server — answering `sd_rd`/`sd_wr` between the HyperRAM buffer and the drive's track buffer — and flushes dirty caches back to the SD card when the flush-start flag fires.

The idle gate is the Shell's half of the media switch. Flipping "Use internal 1581" lands in the `OSM_SEL_PRE` callback before the framework copies the menu state into the hardware OSM bit — a revert here keeps `phys_1581_en` untouched. The handler reads two words from the diagnostic device `C_DEV_C64_PHYS1581 = 0x0108`: `RM_CTRL_STATE` (offset four), masked with `P1581_BUSY_MASK = 0xFC08` — read-phase bits 15 through 12, step-phase bits 11 and 10, motor bit three — is nonzero only while the physical drive is actually reading, stepping or spinning; and `RM_IMG_DRIVE` (offset `0x28`), whose bit zero is the `img_drive_busy` level from Chapter B5.1. If either side is busy, the Shell calls `M2M$FORCE_MENU` with one minus the requested value, repainting the marker and rewriting the configuration data so neither the menu nor the core ever sees the flip. The gate is symmetric by design — the image drive can write, so switching away mid-access or with an unflushed cache would lose data — and each word naturally reads idle while the other source is active, so one code path gates both directions. Why the gate lives in firmware rather than RTL is a story; see Appendix C2. Section A Chapter 12 describes what happens after the toggle succeeds.

### B6 — The test suites

Everything in the physical-1581 stack that could be proven without hardware *was* proven without hardware, and the proofs were kept. This group of chapters walks through the four layers of that evidence: the GHDL benches that exercise the VHDL from single-module units up to a closed loop against a behavioral mechanism (B6.1), the A/B harness that races seven generations of the gap quantiser against each other on stress flux (B6.2), the SystemVerilog bench that drives the WD1772 model's physical branch with the genuine drive ROM's own polling idiom (B6.3), and the Python emulator that runs the genuine 1581 DOS ROM itself against a model of our contract (B6.4). B6.5 collects the mechanics of actually running it all.

Two habits of this suite are worth naming before the file-by-file tour, because they *are* the verification philosophy. First, every bench is self-checking: it asserts its expectations and terminates with a hard failure on any mismatch, so a run is a yes/no answer, not a waveform to eyeball. Second — and less commonly seen — the suite preserves its own negative controls. Where a design replaced a failed one, the failed design is kept as an executable reference and the bench *requires* it to fail its signature vector: a fixed-window quantiser that must lose the write-splice chain, a preamble-gate variant that must reproduce its F011 regression, a pre-fix status pairing that must turn a truncated sector into silent success. A test that has never been seen to catch the broken version proves little about its power to catch the next regression; this suite carries the broken versions along precisely so that proof never goes stale. Appendix C3 draws out why the project ended up working this way.

One invariant threads every layer of the suite and is checked at each of them: *a data CRC error must never be reported together with Record Not Found*. Chapter 15 explains the rule; it originates in the genuine DOS ROM's status-decoding table and reappears below in B6.1 (the overflow bench), B6.3 (a continuous monitor plus a forced violation), and B6.4 (the proofs that discovered it).

Throughout these chapters, an unqualified "cycle" is one 50 MHz controller-clock cycle (20 ns), and a "byte-time" is the 32 µs one byte occupies at double density (DD).

#### B6.1 The GHDL benches (tb_physical_1581_codec / _controller / _diag / _inputs)

The four directories under `CORE/vhdl/test/` — `tb_physical_1581_codec/`, `tb_physical_1581_controller/`, `tb_physical_1581_diag/`, and `tb_physical_1581_inputs/` — hold the VHDL-side test suite for the physical path, run under GHDL, the free simulator for VHDL (the hardware description language the decode chain and controller are written in). There is no Makefile and no runner script anywhere in these directories, by design: each bench that needs a nonobvious build carries its exact command line in its header comment, so the bench file is the complete, self-documenting unit of verification (B6.5 collects the recipes). The benches are arranged as an evidence chain from leaves to system: prove the smallest pieces exactly, then prove the fixtures, then prove the assemblies — so that when a higher-level test fails, the layers below it are already beyond suspicion.

**The shared fixtures.** `tb_physical_1581_codec/mfm_flux_gen_pkg.vhd` is the suite's signal generator: a simulation-only package that lays down synthetic DD flux in Modified Frequency Modulation (MFM) on an active-low RDATA line — one ~400 ns low pulse per MFM channel-bit `1`, half-cells 2 µs apart (`MFM_HALF_CELL`), so leading-edge gaps come out at the legal 4/6/8 µs spacings. It provides procedures for ordinary bytes, for the missing-clock A1 sync mark (raw word `0x4489`, `MFM_A1_RAW`), and for two kinds of deliberate imperfection: `mfm_byte_runt` splits a legitimate flux pulse with a 60 ns spike so a spurious second edge lands 8 cycles after the real one — below the glitch floor `C_GAP_GLITCH = 16` cycles, modeling double-edge behavior observed on real media — and three deterministic write-splice junk profiles, driven by a 16-bit linear-feedback shift register (LFSR), which B6.2 describes in detail. The package also exports `crc16_update`, a cyclic-redundancy-check function bit-identical to the RTL CRC engine, so every fixture computes its check bytes from an independent implementation of the same arithmetic.

In `tb_physical_1581_controller/`, `golden_1581_pkg.vhd` defines the disk that all controller-level tests read: two pure functions, `lba1581(cyl, side, sec)` and `golden_payload(cyl, side, sec, off)`, are the *single source of truth* for both the flux the mechanism model emits and the bytes the checks expect — no shared file, no state, so the emitter and the checker can only agree by actually being right. Each sector's payload opens with a self-describing identity (cylinder, side, sector, block number) followed by pseudo-random filler, so a wrong-sector read fails byte-for-byte rather than by coincidence. `mech_model_1581.vhd` is the behavioral model of the far side of the 34-pin connector: a PC-style DD mechanism plus a formatted disk, spinning at 300 RPM (`G_INDEX_PERIOD = 200 ms`, 2 ms index pulse, 80 cylinders), honoring the documented polarities — motor, select, and step active-low; `f_stepdir` high meaning toward track 0; `f_side1` low selecting side 0, the empirically confirmed wiring. While motor and select are asserted and a disk is configured present, it continuously emits the current track as ten standard records — twelve `00` preamble bytes, the three-A1 train, the `FE` ID address mark, C/H/R/N, CRC, gap bytes, then the data field — re-sampling head position once per revolution.

**Proving the fixture itself.** `tb_mech_model_1581.vhd` closes a loophole most suites leave open: how do you know the *model* is right? It wires the mechanism model to the real production decoder (`physical_1581_mfm_decoder` and its full chain) and proves that a spinning disk at cylinder 0 yields a well-formed record with the golden payload byte-exact, and that one step pulse toward higher cylinders moves the model's head so that subsequently decoded IDs read cylinder 1. Once this bench passes, a failure in any closed-loop test indicts the design under test, not the test equipment. Its header carries the full GHDL file list — the de-facto compile order for the whole codec.

**The unit leaves.** `tb_physical_1581_codec/tb_physical_1581_crc.vhd` pins the CRC engine (Section B chapter B1.7) to known vectors: the three-A1 preset `0xCDB4` (`C_CRC_AFTER_3XA1`), `0xB230` after appending `FE`, `0xE295` after `FB`, the standard CCITT-FALSE check value `0x29B1` for the string "123456789", and the zero-residue property — feeding a field plus its own stored CRC must leave `0x0000`. `tb_physical_1581_inputs/tb_physical_1581_inputs.vhd` tests the pin conditioner (B2.2) with the glitch floor overridden to 50 cycles and a scaled index period: five clean index pulses yield exactly five accepted edges with the period and width measured correctly; a 20-cycle glitch below the floor yields none; the active-low sensor lines convert to positive sense while `rdata_sync_o` deliberately keeps its active-low sense. `tb_physical_1581_rdfifo.vhd` — housed in `tb_physical_1581_inputs/` rather than a directory of its own — verifies the dual-clock Gray-pointer first-in-first-out buffer (FIFO, B2.3) under genuinely asynchronous clocks with relatively prime periods (20 ns write, 62 ns read): phase 1 proves the write-side occupancy tap rises to exactly five and falls back to zero only after the read pointer crosses the synchronizer; phase 2 streams 205 bytes through in order, respecting full and empty, with the level never exceeding the depth.

**The codec proof.** `tb_physical_1581_codec/tb_physical_1581_mfm_decoder.vhd` is the end-to-end decoder bench (B1.6): one canonical record — ID field `C/H/R/N = 05/01/03/02`, then a 512-byte data field — emitted as raw flux and required back byte-exact with both CRCs good. Its stimulus is quietly adversarial in four ways. The payload deliberately embeds the values `A1/FE/FB/F8/F5/F6/F7`, proving that data *bytes* can never fake a sync mark — only the missing-clock gap pattern can. A timing-valid but unsolicited data address mark (DAM) precedes the ID field, and a second, "armed" one sits inside Gap 2 after the CRC-valid ID; the record grammar must ignore both — `dam_unarmed_o` pulses exactly twice — without consuming the arm that the genuine data field then redeems. Two runts are injected, one inside the ID's H byte and one at payload byte 100; the input filter must merge both (`runt_o` pulses exactly twice) with `gap_error_o` never firing — without the filter, each split gap falls below the shortest valid window and kills its field.

**The controller assemblies.** `tb_physical_1581_controller/tb_physical_1581_controller.vhd` is the closed-loop functional test: the production controller (B2.1) plus the production FIFO plus the mechanism model, wired pin to pin, driven through the toggle-handshake request interface. It proves media readiness, a Read Sector returning `RES_OK` with all 512 bytes equal to the golden payload, Read Address, Verify, a step to cylinder 1 followed by a matching read there, and Record Not Found (RNF) for a nonexistent sector. Beyond the happy path it pins the delivery contract of Chapter 15: every completion carries the sequence tag of *its own* request; a request arriving while the engine is busy is latched and served afterward; an aborted operation and its pending successor both complete under their own tags with the two done-toggles spaced at least 8 cycles apart, so the two-flop synchronizer on the far side cannot swallow one; and a continuous monitor confirms the done-tag never changes except on a done-toggle. Timing generics are scaled so only index-paced waits cost simulation time — the flux itself always runs at the true 2 µs half-cell, which cannot be sped up.

`tb_physical_1581_media_contract.vhd` is a focused regression on readiness and Read Address, driving INDEX and RDATA directly: cold media requires two qualified index edges; a previously confirmed, unchanged medium becomes ready after a single edge on motor restart; a disk change, or disabling and re-enabling the physical source, clears that history; and physical Read Address hides the F011 formatter's CRC-valid sector-11 ID, returning the following stock-compatible sector 1 (Chapter 14 explains both behaviors).

`tb_physical_1581_ovf.vhd` is the suite's most instructive negative-control story. It reproduces a real bring-up bug: a Read Sector against a deliberately tiny four-entry FIFO whose consumer never drains — modeling the drive computer's 6502 stolen away by serial-bus interrupt work mid-sector. The unfixed RTL completed such a read as OK with a silently truncated stream; on hardware that produced shifted directory names and programs that loaded but did not run. The bench requires the controller to complete with `RES_DATA_CRC_ERROR`, CRC flag set and RNF flag *clear* — because CRC-only makes the DOS retry, while CRC together with RNF would fall into the genuine ROM's `$CD5A` status-table hole and be accepted as success (B6.4 tells that discovery).

**The register bank.** `tb_physical_1581_diag/tb_physical_1581_diag.vhd` unit-tests the diagnostic device (B2.4, Chapter 17): it drives known state levels and event strobes into `physical_1581_diag`, then reads every documented register word through the QNICE read interface — signature `0x1581`, version word, packed live-pin words, state and head packing, latched results and CRCs, index period and width, gap extrema, the adaptive estimate, the trace ring, and every saturating counter. Reads are purely combinational on the same clock, so the bench is exhaustive rather than subtle. Register-level meaning is documented in [the debug-device reference](1581_dd_debug_device.md).

The bring-up iterations these benches cite ("round 10", "round 11"…) are chronicled in [dev-fdd/PLAN.md](dev-fdd/PLAN.md) and retold as history in Appendix C2. Section A Chapters 12–15 teach the mechanisms these files verify.

#### B6.2 The A/B quantiser harness (seven decoders racing)

`tb_physical_1581_codec/tb_physical_1581_quantise_ab.vhd` answers a question none of the functional benches can: not "does the decoder work?" but "*how much better* is the shipped decoder than everything that was tried before it — and does it give anything back?" It elaborates **seven complete decode chains in parallel**, all fed the identical stress flux, so every trial reports one row of pass/fail columns: `old` (the pre-adaptive fixed-window classifier), `r12` (adaptive, no sync gate), `r13` (the superseded zero-preamble gate), `prod` (the production decoder: adaptive quantiser, complete-A1 span check, exact train spacing, ID-before-DAM record grammar), `tacq` (a refuted fix candidate with tightened acquisition tolerance), and `spanoff` / `seqoff` (production minus exactly one qualification each, pinned to the commits — `3803152`, `0ab9f92` — whose semantics they reproduce).

The mechanics of racing "the same entity, seven ways" are worth knowing. The historical fixed-window classifier lives in `ref_mfm_quantise_fixed.vhd`, which deliberately reuses the production entity name `physical_1581_mfm_quantise` so that the *unmodified* production decoder sources can be analyzed against it into a second GHDL library (`q_old`) while the real quantiser goes into `q_new`; the remaining columns are production instances with generics (`G_SYNC_GATE`, `G_QUANT_HUNT_ADAPT_ALL`, `G_QUANT_TOL_ACQ_SHR`) pinned to each generation's semantics. Because the entity names collide by design, the reference file must never be added to a Vivado project or analyzed into the production library — and the three libraries need three separate work directories (B6.5).

The stimulus sweeps nine vector classes over a canonical record: both formatter layouts (exact stock-ROM gaps and the pinned F011 layout, including F011's preamble-less first IDs); uniform speed offsets out to the ±12 % discriminators; end-to-end linear drift; per-edge random jitter; peak shift — inter-symbol interference (ISI), every transition displaced toward its longer neighboring gap — alone and combined with speed offsets as the inner-cylinder hardware model; the measured 126-cycle mid-gap artifact; an abrupt splice speed step; the three LFSR-driven write-splice junk profiles; and the armed splice DAM after a CRC-valid ID.

The acceptance block is where the philosophy shows. Alongside the expected positives (canonical decodes byte-exact everywhere; production decodes every must-pass row; at least one production-over-old win in each stress family, preserving the adaptive quantiser's reason to exist), the harness *demands the historical failures stay reproducible*: every stock-layout junk-chain trial must fail on the `r12` column by opening a bogus data field mid-junk — the confirmed false-sync mechanism behind a deterministic hardware regression; every F011-layout row must fail on `r13`, keeping its zero-ID regression alive; and the `tacq` candidate must fail at least one peak-shift row — if it ever stops failing, the bench itself fails with the message that the fix-selection rationale no longer holds and must be re-evaluated. Refuted designs are not deleted here; they are kept as executable columns so the *reasons* for the shipped design remain machine-checked. A global silent-corruption guard sits over all of it: any CRC-approved decode, in any column of any trial, whose ID or payload differs from the golden record is fatal — CRC-caught corruption is acceptable, silent wrong payload never is. A final probe phase documents single-gap accept/reject decisions of the old windows against two adaptive tolerance variants, preserving the dead-band analysis in runnable form.

One subtlety: the junk profiles were tuned *against* the harness. The naive `junk_splice_rand` profile turned out too tame — every classifier survives it — and is kept anyway, as documentation that realistic-looking garbage is not automatically a hard test; `junk_splice_chain` reproduces the hardware failure gap-exact, and `junk_splice_spaced` defeats candidate-spacing alone, isolating the complete-A1 span check as the necessary qualification. Chapter 13 teaches the algorithm being raced; B1.3 describes the production quantiser; Appendix C2 narrates the rounds that each column embalms, and Appendix C3 the lesson.

#### B6.3 tb_fdc1772_physical.sv

`CORE/C64_MiSTerMEGA65/rtl/iec_drive/tb_fdc1772_physical.sv` is the SystemVerilog complement to the VHDL suite: a self-checking Icarus Verilog bench for the physical-mode branch of `fdc1772.v` (B3.1), the WD1772 floppy-disk-controller model. Where the VHDL benches prove the controller side of the delivery contract, this bench proves the WD side — that the register interface the drive computer's 6502 sees behaves correctly when its media bytes arrive from the physical backend across a real clock-domain crossing (CDC).

The bench instantiates `fdc1772` with `phys_mode` tied high and surrounds it with four stand-ins: an inert stub for `floppy` (the image-mode mechanics must contribute nothing in physical mode — the stub drives all outputs low, so any image-path leakage becomes a visible failure); a mock backend on a separate ~50 MHz clock honoring the delivery discipline — sequence tags sampled at acceptance, a pending-request latch, cancellation completing under the aborted request's own tag; a SystemVerilog port of the Gray-code FIFO, so the data path genuinely crosses from the backend clock to the drive clock rather than being wished across; and the real `iecdrv_sync` synchronizers from `iecdrv_misc.sv` inside the device under test.

Its defining discipline is *driving the interface exactly the way the genuine ROM does*. Every transfer uses the DOS polling idiom shared by the sector transfer loop at `$C969` (Chapter 8) and the Read Address reply loop at `$CD17` — poll BUSY first, DRQ (data request) second, exit the moment busy reads 0 — with realistic multi-clock CPU access cycles. That fidelity is not cosmetic: two of the thirteen numbered checks only exist because the real ROM's timing found real bugs. Check 11 pins the round-11 repair in which a zero-step Type-I command (a Seek to the current track) must hold busy for the WD1772's minimum Type-I busy time of roughly 1.5 ms so the DOS wait-busy-set poll at `$CBFA`, cycling every ~3.5 µs, can observe it at all — before the fix, busy dropped after ~380 ns, invisible to the poll, and the DOS hung in error recovery. Check 9 requires a paced presentation that becomes due while the CPU holds an open read of the data register to be deferred until the access closes; check 13 tightens that to a register select visible for a single CPU clock.

The remaining checks cover the register self-test readback pattern the ROM performs at power-up (`$C343`); byte-exact Read Address — including the ROM's own software CRC over the six bytes, preset `$B230`, residue 0 — and byte-exact 512-byte Read Sector; a stalled CPU mid-sector producing LOST DATA with bounded completion and a clean next operation; FIFO residue drained rather than leaking into the next transfer; non-Force-Interrupt commands ignored while busy; a Force Interrupt mid-operation whose cancelled completion is discarded by sequence tag; the busy tail of at least one byte-time after the last DRQ; a Force Interrupt colliding with a deferred multi-sector reissue on the same internal tick producing no phantom operation; and the CRC quarantine — a complete 512-byte capture whose final result is a data CRC error must present zero bytes and zero DRQs to the ROM.

Three continuous monitors run across the entire session rather than inside any one check: the status register must never show CRC and RNF together (and a deliberately forced crc-plus-rnf completion from the backend proves the suppression belt actually engages — the negative control again); the data register must never change during an open CPU read of it; and no byte may be presented before a clean completion. The run ends with either a single PASS banner or `$fatal` and a nonzero exit code. Chapter 15 teaches the delivery contract this bench polices; B6.4 explains where the ROM idioms and the CRC/RNF rule were learned.

#### B6.4 The genuine-ROM emulator (doc/dev-fdd/rom_emu)

Everything described so far tests our RTL against our *understanding* of the 1581. `doc/dev-fdd/rom_emu/` tests that understanding against the one artifact that cannot be argued with: the genuine 1581 DOS ROM, revision 318045-02, executed instruction by instruction. It is a small Python package — `cpu6502.py` (a 6502 interpreter), `machine.py` (the drive machine: WD1772 front end, CIA senses, controller readiness, all mirroring the physical-mode RTL semantics), `dis65.py`, `run_boot.py`, `run_proofs.py`, and a README — which loads the ROM by converting `c1581_rom.mif.hex` from the drive engine's source tree on the fly.

One caveat must travel with every reference to this directory, because the directory says it about itself: these are *working notes, deletable; not part of the shipped feature*. The package lives under `doc/dev-fdd/` precisely because it is bring-up tooling, not product. And yet it is the only behavioral evidence in the whole suite that involves the genuine ROM — the RTL benches encode conclusions *about* the ROM; only this harness derives them. Both things are true, and the book cites it in that spirit: [the rom_emu README](dev-fdd/rom_emu/README.md).

`run_proofs.py` runs a lettered inventory of proofs against the genuine ROM and must end with `RESULT: ALL PROOFS PASS`. The constructive ones establish that the modeled contract satisfies the ROM: the power-up register self-test and boot (P-A); a full directory-track fill under disk-paced 32 µs presentation, byte-exact with zero LOST DATA (P-B); a truncated sector completing CRC-only producing job error 5, cache invalidation, and a healing retry (P-C); a corrupted Read Address reply caught by the ROM's software CRC with error 9 and retry (P-D2); the transfer-loop timing margin (P-T — worst-case consumption latency 34 of the 64 CPU cycles per byte-time, a 47 percent margin, with the emulator measuring 33 and a 66-cycle busy tail); WD unit semantics (P-U); and the media-state proofs (P-M), which reproduced the readiness windows, the one-index resume, and — under a source-derived F011 track rotation — the Read Address sequence that motivated hiding sector IDs outside 1..10 (Chapter 14).

The demonstrative ones are the suite's deepest negative controls. P-E replays the *pre-fix* status pairing — CRC and RNF asserted together — and shows the same truncated fill become a silent success with a stale cache marked valid: the exact failure the `$CD5A` table hole permits, kept runnable so the rule "CRC suppresses RNF" can never decay into folklore. P-D1 and P-D3 document a genuine defect in the shipped ROM itself: the LOST DATA branch at `$CD49` skips the `PLP` that balances the `PHP` at `$CD42`, so its `RTS` pops the flags byte as a return-address byte and misreturns into wild execution — latent on real hardware only because the P-T margin means LOST DATA never fires there. That finding shaped the RTL requirement that LOST DATA remain faithful to the real chip yet practically unreachable. P-D3 runs last by design: it leaves the emulated machine unusable.

The README also preserves the harness gotchas (boot needs a fixed ~3-million-step budget; Read Address replies need a true CCITT CRC or every job dies with error `$09`) and a list of ROM anchors — `$C343`, `$C900`, `$C969`, `$CD3F`/`$CD5A`, `$DA63`, and friends — that Chapter 8 uses as its map of the DOS. Appendix C2 narrates how this tool root-caused the failures that the RTL benches now regress; Appendix C3 counts ROM-in-the-loop proof among the road's lessons.

#### B6.5 Running everything

There is deliberately no Makefile, no `run.sh`, and no Python driver for the physical-1581 benches — a contrast with the older suites in the same tree (`tb_crt_parser/` and `tb_sw_cartridge_wrapper/` have GHDL Makefiles; `tb_reu/` is Questa-only). Each bench is the unit of documentation: where a build is nonobvious, the exact command line lives in the bench's own header comment, current by construction because it sits next to the code it builds.

The single-file units are two or three plain commands, quoting from their headers — for example the CRC bench:

```
ghdl -a --std=08 physical_1581_pkg.vhd physical_1581_crc.vhd tb_physical_1581_crc.vhd
ghdl -e --std=08 tb_physical_1581_crc
ghdl -r --std=08 tb_physical_1581_crc
```

and analogously for `tb_physical_1581_inputs` and `tb_physical_1581_rdfifo`, each of which lists its two or three source files. The multi-file benches analyze into a scratch work directory: `tb_physical_1581_mfm_decoder.vhd` gives the pattern (`ghdl -a --std=08 --workdir=B` over the package, CRC, the four decode stages, the decoder, the flux package, and the bench, then `ghdl --elab-run --std=08 --workdir=B tb_physical_1581_mfm_decoder --assert-level=error`). The authoritative compile order for the entire codec is spelled out, file by file with repo-relative paths, in the header of `tb_mech_model_1581.vhd`; the three closed-loop controller benches and the diagnostic bench follow the same recipe, extended with the controller, the FIFO, and (for the closed-loop tests) the fixtures `golden_1581_pkg.vhd` and `mech_model_1581.vhd`. The flag `--assert-level=error` is what makes the benches self-checking in the shell sense: any failed assertion of severity error aborts the simulation with a nonzero exit code.

The A/B harness is the one build with real structure: three GHDL libraries in three *separate* work directories, because the per-library object files share basenames —

```
ghdl -a --std=08 --work=q_new --workdir=B/new  <the seven production codec files>
ghdl -a --std=08 --work=q_old --workdir=B/old  <the same, with ref_mfm_quantise_fixed.vhd
                                                in place of physical_1581_mfm_quantise.vhd>
ghdl -a --std=08 --workdir=B/top -PB/new -PB/old  mfm_flux_gen_pkg.vhd tb_physical_1581_quantise_ab.vhd
ghdl --elab-run --std=08 --workdir=B/top -PB/new -PB/old tb_physical_1581_quantise_ab --assert-level=error
```

Expect it to run for a while — it simulates more than fifty full-record trials at true flux timing, under a two-second simulated-time guard.

The SystemVerilog bench builds with Icarus Verilog, from `CORE/C64_MiSTerMEGA65/rtl/iec_drive/`:

```
iverilog -g2012 -o tb.vvp tb_fdc1772_physical.sv fdc1772.v iecdrv_misc.sv
vvp tb.vvp
```

with `$fatal` producing a nonzero exit on any mismatch.

The ROM-in-the-loop proofs need only Python 3: `python3 run_proofs.py` works from any directory (it locates the ROM image relative to its own file) and must end with `RESULT: ALL PROOFS PASS`; `python3 run_boot.py`, which prints a boot trace and WD dialogue, expects to be started from inside `doc/dev-fdd/rom_emu/` itself.

Together these commands are the complete regression gate for the physical path: GHDL for every VHDL claim, Icarus for the WD boundary, Python for the genuine ROM. What the gates guard — and why each exists — is the subject of Appendix C3.

## Appendix — The Road to the 1581

The feature this book describes — the MEGA65's internal 3.5-inch mechanism serving as a real Commodore 1581 for the C64 core — was designed, built, brought up, broken, rebuilt, and qualified in a remarkably compressed arc: a research report in mid-June 2026, then thirty-four days later a frozen, hardware-qualified read-only milestone. This appendix tells that story. It is not a changelog; it is an engineering history, told era by era, because nearly every design decision documented in Sections A and B exists in its present form *because* an earlier form failed in a specific, instructive way. Dates and commit SHAs below are taken from the two repositories themselves (the main repository on branch `mh_implement_90`, and the `CORE/C64_MiSTerMEGA65` submodule); the day-by-day working notes live in `doc/dev-fdd/` — [PLAN.md](dev-fdd/PLAN.md), [HANDOVER.md](dev-fdd/HANDOVER.md), [handover_codex.md](dev-fdd/handover_codex.md), and [plan_codex.md](dev-fdd/plan_codex.md) — and reward reading in full.

### C1. Timeline

The work divides into a research prelude, one week of intense implementation and hardware bring-up, and a closure phase. Research happened on June 14, 2026; a month-long pause followed, during which the *simulated* D81 feature (a 1581 fed from a disk-image file) shipped separately and created the drive computer the physical path would later reuse. The physical-1581 effort proper ran from July 12 to July 18: specification and pragmatic descoping on day one, a complete simulation-verified implementation the same evening, hardware bring-up in numbered "rounds" through the following days, and a final qualification-and-isolation pass. Every commit was made by the maintainer; the table lists the main-repository SHA first and the submodule SHA (where one exists) second.

| Date (2026) | Commits | Milestone |
| --- | --- | --- |
| Jun 14 | `c22f158`, `118e29b` | Research report: how the MEGA65 uses its internal drive |
| Jul 3 | `f7b15df` | Simulated D81 support ships (Alpha 18) — the future drive computer |
| Jul 12 | `3f373f1` | The 5,190-line normative spec; "Approach B" pragmatic descope decided |
| Jul 12 | `00f5bb8` / `70ae1ee` | Read path implemented and simulation-verified in one session |
| Jul 13 | `87d65f0` / `88c09d2` | Timing closure; the no-disk deadlock set; the 43-agent review |
| Jul 13 | `3281b7f` / `b2bd629` | Bring-up rounds 1–3: media-ready fix, trace ring, ROM self-test readback fix |
| Jul 13 | `b9a2f1a` / `743a8d3` | "First sign of life": `LOAD"$",8` works, but not much more |
| Jul 13 | `33899a0` | Read milestone: directory and programs load and run from real media |
| Jul 14 | `3eb2039` / `e2a6a22` | Delivery v2: disk-paced presentation replaces consumption coupling |
| Jul 14 | `154ce26` / `8d3a6a1` | 1.5 ms minimum Type-I busy; runt-filter retune |
| Jul 14 | `79c19d3`, `2e2c852` | Round 12 adaptive quantiser; round 13 preamble sync gate |
| Jul 14 | `3803152`, `0ab9f92`, `47432c8` | A1 spacing → span check → the record grammar |
| Jul 16 | `ef272ef` / `b6bd8da` | The CRC quarantine; first unequivocal end-to-end hardware proof |
| Jul 16 | `b13d99e` | `rotation_confirmed` readiness; Read Address filtered to R = 1..10 |
| Jul 18 | `bdd457b` | Slow-spindle staleness refinement — the delayed-first-index hole |
| Jul 18 | `aa6b70f`, `95eae0f` | Final R3 qualification recorded; stock-media gate documented |
| Jul 18 | `d94fa73` / `71f4cd7` | Image-mode isolation restored |
| Jul 18 | `55bc986` | Version `WIP-V6-A18X2`: read-only milestone frozen |

### C2. The eras

#### Era 1 — Research and the spec (June 14–July 12)

The project began with a question, not a design: *can the MEGA65's internal drive be a 1581 at all?* The answer arrived as a thousand-line research report, `doc/how-MEGA65-uses-the-physical-disk-drive.md` (committed June 14 as `c22f158` and `118e29b`), which traced how the mega65-core firmware drives the internal 3.5-inch mechanism through the F011 — the floppy controller of the never-released Commodore 65, which the MEGA65 re-implements natively. The report established the two facts everything else stands on: the mega65-core codebase contains reusable, proven MFM (Modified Frequency Modulation) decode helpers and a CRC (cyclic redundancy check) stage; and the natural attachment point in our core is the existing seam between `main.vhd` and the `iec_drive` block, where the simulated 1581 already lives.

A month later, on July 12, commit `3f373f1` added `doc/issue_90_internal_mega65_drive_as_1581.md`: a 5,190-line *normative* specification in twenty-five sections, written in MUST/SHOULD language, complete with a "Prohibited shortcuts" section and a list of "Measurements that must be frozen." It specified everything — a 16-bit epoch/media-generation/request-id identity system, dual-acknowledge control broadcasts, cache-flush machinery for live media switching, a continuously clocked 100 MHz write-safety island, hardware-measured timing constants.

The same day, the maintainer made the decision that shaped the whole project: **Approach B, the pragmatic path**. The functional behavior of the spec would be implemented faithfully; its ceremony would not. One drive, one operation at a time, means no aliasing risk, so the identity system collapsed to simple toggle handshakes. Live switching collapsed to an idle gate (switch sources only when the drive is quiet). The write path — and with it the entire write-safety island — was deferred to a separate, explicitly-opened future milestone, with the write gate and write data pins tied inactive at every board top. Only 512-byte sectors would be supported. And, crucially: no oscilloscope and no logic analyzer would ever touch the hardware — the *only* instrument would be a small read-only diagnostic device on the QNICE bus (QNICE being the 16-bit helper processor that runs the core's menu firmware), readable over JTAG, the board's debug port. Every deviation was recorded in a table in [HANDOVER.md](dev-fdd/HANDOVER.md) so the trimming stayed honest and reversible. [dev-fdd/DESIGN.md](dev-fdd/DESIGN.md) then froze the architecture: the new controller written in VHDL (a hardware description language) on the 50 MHz clock, the SystemVerilog/VHDL boundary kept at the existing seam so all new VHDL stays testable in GHDL (an open-source VHDL simulator) without any vendor tools.

**What this taught.** Writing the maximal spec first and *then* consciously descoping is not wasted work: the spec became the checklist of what the pragmatic build must still do correctly, and the deviation table became the roadmap for what a shipped release must add back. And committing on day one to a counters-only debug philosophy — before any debugging existed — quietly dictated the shape of everything that followed.

#### Era 2 — Bring-up: rounds 1 through 11 (July 12–14)

The implementation itself took one evening. Commit `00f5bb8` (July 12) delivered phases R0 through R5: the design freeze, the complete decode chain in `CORE/vhdl/physical_1581/`, the physical branch inside `fdc1772.v` (the WD1772 model — the Western Digital floppy-disk controller at the heart of every 1581), the threading through four board tops, the On-Screen Menu (OSM) item, and the diagnostic device. All of it was verified in simulation — a GHDL closed-loop bench with a behavioral mechanism model, plus Icarus Verilog on the drive side — before the first synthesis. That first synthesis promptly failed timing by a worst negative slack of −5.051 ns across 83 endpoints, 71 of them the brand-new clock-domain crossings (CDC) with no timing exceptions declared; session 2 (`87d65f0`, July 13) closed timing, and then absorbed two waves of findings before the bring-up rounds proper.

The first wave came from the maintainer simply *enabling the feature with no disk image mounted*: five distinct root causes conspired to produce a dead drive, the deepest being a genuine deadlock — the WD1772 model rejected Type-I commands (seeks and restores) while the media was not ready, but becoming ready requires stepping, and steps *are* Type-I commands. The real WD1772 has no READY input at all; the model was made to match.

The second wave was a 43-agent adversarial review — seven review dimensions, each attacked by independent refuter agents — which confirmed eight further defects, headlined by the read FIFO's (first-in-first-out buffer's) one-sided reset, a Gray-pointer desynchronization that would have produced CRC-clean *shifted* sector data after any mid-read reset, and by an off-by-one-bus-phase bug: the WD model popped the next byte at the *start* of the drive CPU's data-register access while the T65 (the 6502 core of the FPGA — the field-programmable gate array the whole system lives in) latches at the *end*.

Then came the hardware, and with it the rounds. The loop was always the same: the maintainer flashes board revision R3, runs a load, hits a failure, dumps the diagnostic device; the dump is analyzed against the 1581's ROM (read-only memory — here the genuine Commodore DOS (Disk Operating System) ROM, 318045-02); a fix is designed, simulated, reviewed, rebuilt. Round 1 re-derived readiness from the drive's schematic behavior after the disk-change latch deadlocked the DOS's ready-before-job wait. Round 2 was pivotal in a quiet way: the diagnostics proved the entire magnetic stack healthy — 300 revolutions per minute, about 10.9 ID fields decoded per revolution, six of six read operations clean — *and yet the DOS never even seeked*. The instrument had run out of resolution, so the instrument grew: a 32-entry trace ring recording every WD1772 command and status handed across the boundary, precisely to reconstruct the DOS↔WD conversation (diagnostic map v3).

Two rounds became a cautionary pair. Round 2b "fixed" the side-select polarity by careful derivation from the mega65-core register model — and was *confidently wrong*. Round 6 reverted it on the only evidence that matters: the H bytes (head numbers) recorded inside ID fields on the disk itself, compared across rounds, proved logical side 0 drives the pin low. The controller source now carries a comment warning future readers not to re-derive that mapping from software.

Round 3 produced the bug with the longest shadow in the whole project. Disassembly of the genuine ROM's power-up sequence found a register self-test at `$C343`: the drive writes the WD track, sector, and data registers and verifies every readback. Our model's readback mirror was one write behind, the self-test failed, and initialization aborted — the fingerprint being a track register stuck at `0xFF`. The fix made the readback return the just-written value. It was necessary and correct — and, as Era 6 will show, it was applied one conditional too broadly.

Round 5 exposed the deepest architectural error by way of a subtle symptom: the WD model dropped its BUSY status flag when the last byte of a Read Address reply was *presented*, but the genuine ROM polls BUSY before draining the data register and then verifies the reply with a software CRC at `$DA63` — so it saw a truncated reply and reported error `$09`. Proving this required building a new instrument: **rom_emu**, a Python 6502 emulator with device models faithful enough to boot the *genuine* 318045-02 ROM and single-step its actual decisions (Section B6.4). The round-5 fix — hold BUSY until the drive CPU has consumed the last byte — cured the symptom while planting a wrong invariant. Round 7 patched a consequence (a silent FIFO overflow that corrupted a directory listing into "SHADESKD"; the FIFO grew from 32 to 512 bytes). `LOAD"$",8` became reliable; commit `b9a2f1a` records the mood: *"First sign of life: internal MEGA65 drive as 1581 — `LOAD "$",8` works, but not much more."* Round 8 reached the **read milestone** (`33899a0`): programs load and run from genuine double-density (DD) media, verified byte-for-byte against the "mother" D81 — the disk image from which the physical test disk had been written, giving ground truth down to the last byte. SHADES, with 20 of its 35 blocks on side 1, loaded and *played* — music from the C64's sound chip is an excellent checksum. Round 9 patched another consequence (a soft-reset busy wedge) with a pop cap and a 0.5-second watchdog.

Round 10 began with the worst kind of failure: intermittent, *silent* corruption. A directory entry's start-track byte had flipped from `0x3E` to `0x3F` — a single bit — steering the DOS to the wrong cylinder, where an early-terminated cache fill was marked valid and a garbage program "successfully" loaded. A six-agent forensic audit of the dumps and the ROM concluded that rounds 5, 7, and 9 were one causal chain of patches on a single inversion: WD busy release had been coupled to drive-CPU consumption, "which real silicon never does." **Delivery v2** (`3eb2039`/`e2a6a22`, July 14) replaced the whole seam with the real chip's model: one byte presented per DD byte time of 32 µs (constant `PHYS_PACE_TICKS`), a loud LOST DATA status on overrun, a sequence-tagged request/done handshake, completion defined by tag-matched done plus empty FIFO plus one byte-time tail — and the pop cap and watchdog *deleted*, so that no wall-clock bound remained anywhere in the delivery path. The same audit contributed a genuine-ROM discovery with teeth: the ROM's status-to-error table at `$CD5A` has a hole — a WD status with the CRC *and* Record Not Found (RNF) bits both set maps to job *success*. Any "honest" double-error status would silently corrupt data; from delivery v2 onward, error statuses are CRC-only.

Round 11, the first delivery-v2 hardware test, froze the drive — and uncovered a latent *day-one* bug that every earlier round had masked. A zero-step Type-I command dropped BUSY after roughly 380 ns, faster than the ROM's wait-busy-set poll loop at `$CBFA` can observe (about 3.5 µs per iteration); only the DOS's error-recovery job, which issues a zero-step re-positioning seek, ever exercised the path. The fix is disarmingly simple: a minimum Type-I busy time of about 1.5 ms (`PHYS_T1_MIN_TICKS`), matching the real chip's behavior. A companion fix retuned the runt filter (`C_GAP_GLITCH`) on RDATA — the mechanism's raw read-data line — from 120 cycles down to 16.

**What this taught.** Three lessons, all about evidence. Registers lie about themselves and source code lies about hardware: the readback bug was found by ROM disassembly and the side-select truth by bytes on a disk, not by any derivation. A chain of patches converging on caps and watchdogs is not robustness accumulating — it is a wrong invariant announcing itself. And when your consumer is a 40-year-old ROM, its disassembly — not the datasheet, not intuition — defines what "correct" means.

#### Era 3 — The adaptive quantiser (July 14)

With delivery sound, hardware failures finally localized *radially*: near cylinder 39–41 every load succeeded, while at cylinders 61–62 most loads failed with a handful of RNF errors each. The physics is classical: inner cylinders have shorter circumference, hence higher linear bit density at the fixed data rate, hence stronger peak shift — inter-symbol interference (ISI) — which smears the nominal 4/6/8 µs gap classes toward one another until whole revolutions of gaps fall into the fixed classifier's dead-bands. Round 12 (`79c19d3`) replaced the fixed windows with the adaptive quantiser described in Chapter 13: each gap classifies to the *nearest* class of two, three, or four half-cells around a tracked half-cell estimate (Q8.4 fixed point — eight integer bits, four fractional — nominally 100 cycles of the 50 MHz clock, hard-clamped to ±10%), with acceptance windows that touch at the midpoints so no dead-bands exist at all. The estimator has its own story: the planned proportional, mean-seeking tracker was **rejected by the project's own A/B harness** before ever reaching hardware. Peak shift only ever lengthens short gaps and shortens long ones, so a mean has a biased equilibrium — the harness showed it walking to the +10% clamp under a 20-cycle peak-shift stress and losing to the old fixed windows. What shipped instead is a fixed 1/8-cycle *sign step* toward each accepted gap: a median-seeking update, anchored by the unshifted majority of gaps, with residual bias of about one cycle under the same stress.

Round 12 won every far-cylinder stress class — and introduced a deterministic regression that is this history's best story. Cylinder 39 (logical track 40 in DOS numbering — the directory track), sector 1 — the sector physically right after the index **write splice**, and the one holding the D81 header and Block Availability Map (BAM) — became unreadable thirty times out of thirty. The splice, where the formatter's write current cut off mid-flux, leaves coherent garbage whose alternating gaps of roughly 446 and 344 cycles *are* the gap pattern of the A1 sync mark. Under no-dead-band nearest-class acceptance, the sync detector locked onto the junk, eight more junk gaps decoded to a fake `FB` data address mark (DAM), and the decoder opened a bogus 512-byte data field that swallowed the real sector's preamble, ID, and sync train — every revolution. The old fixed windows had survived the identical junk *by accident*: 446 lay just beyond the long-window edge and 344 sat in a dead-band, so every chain element failed loudly and reset the pipeline. In the words of the fix's commit message (`2e2c852`): "their loud resets were invisibly load-bearing."

Round 13's fix modeled what a real data separator's phase-locked loop does — it only locks during the 12×`00` "lock-up" preamble bytes written before every sync train: while hunting, an A1 is honored only if a run of at least 16 consecutive short-class gaps ended at most six gaps earlier. Splice junk cannot fake that; every *stock-formatted* record has it. A tight per-gap acquisition tolerance had been considered instead and was refuted in-harness — peak shift moves every transition of the A1 train, so junk deviations and legitimate peak-shifted deviations overlap; no per-gap width test separates them. The discriminator, the working notes concluded, "is STRUCTURE, not width."

Then hardware refuted round 13 in the most total way possible: **zero decoded IDs on every cylinder** — healthy flux, healthy estimate, `CNT_IDDEC` flat at zero. The test disk had been formatted not by a 1581 but by the MEGA65's own F011 controller, and the F011 auto-formatter, proven from the pinned mega65-core source (`FDCAutoFormatTrack` in `sdcardio.vhdl`), writes ID address marks with *no* `00` preamble at all. The stock 1581 formatter writes 12×`00` before both fields; the F011 does so only before data fields. Round 13 rejected every ID on the disk *by construction* — and simulation had never noticed, because the simulated media model reproduced only the stock layout.

**What this taught.** Adaptivity and permissiveness must be paid for with structural discrimination somewhere else in the pipeline — every rejection you delete was possibly load-bearing. And a test model is itself a hypothesis about the world: from this point on, both media dialects — stock 1581 and F011 — became permanent rows in every harness run.

#### Era 4 — The record grammar (July 14–16)

The zero-ID refutation ended one era of authorship and began another (Appendix C3 tells that part); technically it began a fast three-commit ladder toward a format-neutral invariant. Commit `3803152` replaced the preamble gate with **exact candidate spacing**: a complete A1 train qualifies by the precise five-gap spacing of its candidates, a property both formatters share. The five-way harness matrix passed; hardware said no — the same deterministic cylinder-39-sector-1 splice failure returned, with IDs abundant everywhere else and every last-failure context reading cylinder 39, sector 1. Commit `0ab9f92` added a second qualifier derived from first principles: the four splice gaps sum to about 1,580 cycles, while a genuine A1 raw word spans 14 half-cells — roughly 1,400 cycles — and real peak shift largely *cancels* over a complete word; so require each candidate's complete raw word to span within half an estimate of 14 estimates. Elegant, principled — and **disproved by hardware within hours**: the new map-v6 counters (`CNT_A1_*`) recorded 22 qualified trains per revolution where ten sectors' worth — 20 trains — was expected, and *zero* span rejections. The physical splice, it turns out, can supply timing-perfect A1 trains. No timing property would ever separate them.

Commit `47432c8` stopped trying to win on timing and enforced meaning instead: the **record grammar** of Chapter 13. A data address mark may be decoded only after a CRC-valid ID field has *armed* it; accepting or ignoring a DAM consumes the arm; and a qualified `A1 A1 A1 FE` (an ID mark) always re-anchors the parser, no matter what state it interrupts. This is the IBM/WD sector layout expressed as a grammar rather than as timing. Hardware moved the failure boundary — the requested ID was now found and paired — but two problems remained: a timing-perfect splice DAM could still slot itself between a valid ID and its genuine data field, turning a false-sync into a data CRC error; and the diagnostic dump showed 686 cumulative LOST DATA events, proof that unvalidated bytes were still flowing into the delivery seam with real consequences.

A first-principles audit — the 1986 Western Digital handbook on one screen, the genuine ROM disassembly on the other — produced the era's two closing insights. First, both formatters *do* write the 12×`00` lock-up before **data** fields, so a zero-run qualifier is valid there even though it is invalid for IDs — the DAM-only preamble gate of the present design. Second, the ROM's error epilogue is boobytrapped: beyond the `$CD5A` success-on-double-error hole already fixed in Era 2, a branch at `$CD49`, inside the status epilogue that begins at `$CD3F`, is taken when LOST DATA is set and skips the `PLP` instruction that balances an earlier `PHP`, so its `RTS` pops the flags byte as half of a return address and the drive firmware *misreturns into wild execution*. A single false LOST doesn't cause a retry; it can derail the drive computer entirely. The architectural conclusion, quoted from the working notes: stop streaming unvalidated bytes — "physical flux → qualified complete sector + result → existing WD/ROM path." Commit `ef272ef` made the 512-byte FIFO a **sector quarantine**: bytes are withheld until the controller reports a clean, CRC-valid completion, at a cost of about 16.4 ms of added latency per sector; error captures drain without ever raising a data request; and a registered presentation exclusion closed a one-cycle register-select collision that could fake LOST. The qualification run of that build produced the first unequivocal end-to-end hardware proof since the adaptive quantiser landed: a cold `LOAD"$",8` through the entire physical chain, every counter clean.

**What this taught.** When timing cannot discriminate, semantics can: the record grammar is the only qualifier in the pipeline that no physical process has ever forged. And latency is almost always cheaper than a false error bit — especially when the consumer's error path is itself defective.

#### Era 5 — Media state (July 16–18)

With sectors arriving intact, the remaining failures moved up a layer: not *what* the drive read, but *whether it believed it could*. The first symptom was error 74, `DRIVE NOT READY`, on the second load of a session — after a flawless first one. The investigation started with a scare: the mechanism began making unfamiliar heavy clicking noises mid-experiment, and for a day the project faced the possibility that its single test mechanism was dying. The response was methodical rather than heroic — pause the matrix, swap in a replacement DD medium, re-baseline from a clean insertion — and the noise resolved into a media problem, not a mechanism one. The experiment design that followed is the project's best example of one-variable discipline: an identical load performed with the motor still warm (success, with normal physical traffic) versus after motor stop (error 74, with *zero* physical traffic — the DOS never issued a single command). That zero is the proof: the failure lay entirely in the synthetic `/READY` line presented on PA1 — port A bit 1 of the drive computer's 8520 CIA (Complex Interface Adapter). Our `media_ready` demanded two fresh index pulses after motor-on; the genuine ROM grants the spindle roughly 0.7 seconds of spin-up and then performs one instantaneous 30-sample check of PA1. A real 1581's ready line is a mechanism status, present almost immediately; ours was a cautious media qualification that arrived too late.

The same investigation closed a second, fully independent defect with the genuine-ROM emulator: **R = 11**. The F011 auto-formatter has no ten-sector stop — it loops until the index pulse returns, so a track typically carries a complete, CRC-valid *eleventh* sector ID (and a truncated record) at the splice, plus the F011's own track information block (TIB); this is why the diagnostics had always counted about 10.9 IDs per revolution. Emulator proofs showed that when the DOS's login sequence performs Read Address and receives a reply with sector number 11, it aborts login — and that hiding out-of-range IDs heals it, while a forced-sequence control proved the ROM otherwise recovers from seeing sector 11. For a while the two failures were entangled in analysis — one reviewer initially called sector 11 the confirmed root cause, a claim the working notes explicitly downgraded to correlation until the stopped-motor experiment separated the two — and the record of that disagreement, preserved rather than smoothed over, is part of Appendix C3's story.

The fixes (`b13d99e`) were deliberately minimal, one narrow rule per proven failure. Readiness gained `rotation_confirmed` (Chapter 14): if a disk was once qualified and no disk-change assertion has occurred since, the same medium must still be present, so a *single* fresh index pulse re-arms readiness after a motor restart — cold or changed media still requires two. Read Address gained a compatibility filter to sectors 1 through 10. Both survived qualification — until a *repeated*-restart test on July 18 found the delayed-first-index hole: the controller's 500 ms index-staleness deadline, meant to catch a dead spindle, erased `rotation_confirmed` before a lazily spinning-up motor produced its first index. The refinement (`bdd457b`) splits staleness by phase: before the first index after motor-on, staleness resets the edge count but *preserves history*; after it, staleness — like reset, disable, and a raw disk-change edge — clears everything.

**What this taught.** Readiness is not a signal; it is a contract with the consumer's exact timing, and the consumer defines it. And in the endgame, the discipline that pays is almost boring: one observed failure, one narrow rule, one focused testbench, one hardware confirmation — then stop.

#### Era 6 — Closure (July 18)

The final day recorded formal qualification on R3 hardware: varied-pause motor restarts, eject-and-reinsert authority, cold boot with the disk pre-inserted, and a concurrent-load stress pass — every class green, with exact request/result trace pairing and zero error counters (`aa6b70f` and `95eae0f` recording the results and the remaining gates). And then the last defect surfaced — friendly fire. An *image-backed* simulated D81, the feature that had shipped weeks earlier and that the physical work had promised never to disturb, could hang forever at `SEARCHING FOR $`. A historical differential pinned it with satisfying precision: an image-mode register-contract bench built for the investigation was compiled against successive submodule commits, and the answer fell out — `88c09d2` passes, `b2bd629` fails. The breaking change was Era 2's round-3 self-test fix, `data_out <= cpu_din`, applied *unconditionally*: necessary in physical mode, where the genuine ROM verifies register readback, it had silently changed simulated-D81 register behavior too. One of the feature's earliest hardware fixes had become its last bug, five days later. The repair (`d94fa73`/`71f4cd7`) is one line with a worldview in it: `data_out <= phys_mode ? cpu_din : data_in;` — with `phys_mode` low, the *exact* pre-physical expression; with it high, the *exact* hardware-qualified physical expression. Image-mode and physical-mode regression transcripts were captured and pinned with SHA-256 checksums, byte-identical against their respective baselines. With that, version `WIP-V6-A18X2` (`55bc986`) froze the read-only milestone.

**What this taught.** Mode-gate every change to a shared path, however obviously correct it looks — and turn "the other mode is unchanged" from a review claim into an executable, checksum-pinned regression. A promise that is not a test is a wish.

### C3. What the road taught

Six eras produced six local lessons; stepping back, the road taught five methods.

**Counters-only hardware debugging works — if the instrument is allowed to grow.** No oscilloscope or logic analyzer touched the hardware at any point in this history. Every hardware fact in this appendix — spindle speed, IDs per revolution, the splice's 446/344-cycle signature, 22 A1 trains where 20 belonged, 686 LOST events, the zero-traffic proof of the PA1 bug — arrived through the diagnostic register map of Chapter 17 — 40 words at birth, 128 by the freeze — dumped over JTAG. The map's version number is effectively an era clock: v3 added the WD-dialogue trace ring when round 2 proved the stack healthy but couldn't say *why* the DOS stayed silent; v4 added delivery counters for the round-10 forensics; v5 exposed the live half-cell estimate and RNF context for the quantiser work; v6 added the A1-train counters that killed the span hypothesis; v7 froze with the record-grammar counters. Each extension was driven by a question the current map could not answer. The general lesson: a small, carefully versioned window of counters, co-designed with the questions being asked, substitutes for a logic analyzer far more often than intuition suggests.

**Refuted designs stay alive as executable columns.** The A/B quantiser harness (Section B6.2) began as a two-column race — old fixed windows versus round-12 adaptive — and grew a column every time a design was refuted, ending at seven decoders racing on identical synthetic flux: the old windows, round 12, round 13, production, `tacq` (the refuted tight-acquisition tolerance), `spanoff` (the exact `3803152` spacing-only design), and `seqoff` (the exact `0ab9f92` span-check design). The harness *asserts* that each refuted column keeps failing the row that refuted it — a control that would silently pass is itself a test failure. This inverts the usual fate of dead designs, which is to be deleted and then re-proposed by someone six months later. Here, every "why don't we just…" has a standing, executable answer, and every new fix must demonstrate that it beats not only the current design but every previous one on every historical failure. Twice in this history the harness refuted a design *before* hardware could — the mean-seeking estimator and the tight acquisition tolerance — which is the cheapest kind of refutation there is.

**Put the real consumer in the loop.** The single highest-leverage tool of the project was rom_emu (Section B6.4): a Python 6502 plus device models booting the genuine 318045-02 DOS ROM. It converted questions of the form "would the ROM tolerate this?" from speculation into experiment, and it found what no datasheet reading could: the `$CD5A` success-on-double-error hole, the stack defect at the `$CD49` branch inside the `$CD3F` epilogue that makes a false LOST catastrophic, the busy-first poll structure that made presentation-coupled completion fatal, the exact consumption-latency margins that make real LOST practically unreachable, and the R = 11 login abort with its forced-sequence control. Emulating your consumer is more work than reading its documentation, and repays it within days.

**Change one variable, even when the variable is a floppy disk.** The hardware experiments that closed the media-state era were designed like clinical trials: warm motor versus stopped motor with everything else identical; a replacement medium introduced *as a controlled substitution* during the mechanism-noise scare rather than as a shrug; maintainer observations ("had the motor audibly stopped, and for how long?") collected as first-class experimental data and queued in the working notes as explicit questions. Where a failure had two candidate causes — PA1 readiness and sector 11 — the experiments were deliberately structured to adjudicate them *independently*, and both turned out real.

**Structure the collaboration; let experiments arbitrate.** This feature was built by a human maintainer working with two AI assistants, and the working notes document the arrangement as deliberately as any decision in the RTL (the register-transfer-level hardware source). Each assistant owned its files: one (Fable) authored and maintained [HANDOVER.md](dev-fdd/HANDOVER.md) and [PLAN.md](dev-fdd/PLAN.md), covering the implementation phases and bring-up rounds 1 through 13 and the reference notes in [f011_reference_notes.md](dev-fdd/f011_reference_notes.md); the other (Codex) took the technical lead after the round-13 F011 refutation and carried it through final qualification, keeping its own [handover_codex.md](dev-fdd/handover_codex.md) and [plan_codex.md](dev-fdd/plan_codex.md). Neither edited the other's files; the maintainer relayed analyses between them. The exchanges were explicitly adversarial and the notes preserve the disagreements verbatim until an experiment resolved them: Codex's written qualifications of Fable's sector-11 root-cause claim (correlation, not verdict — settled by the forced-sequence control), Fable's acknowledged correction on pairing a free-running CRC diagnostic with a final result, and, in the other direction, Fable's `rotation_confirmed` readiness proposal, adopted into production after Codex's verification checklist. Larger review muscle was applied in bursts: multi-agent adversarial reviews of risky diffs, the largest being the 43-agent review of the session-2 changes that confirmed eight real defects before any of them reached hardware, and the six-agent forensic audit that named the delivery inversion. Above all of it sat one invariant that made the structure safe: the maintainer was the sole authority for hardware and for commits. Every bitstream was flashed, every disk inserted, every observation made, and every commit written by the same person — so every claim by any assistant, however confident, had to pass through a human-operated experiment before it could become part of the record.

### C4. Open ends

The milestone this book describes is deliberately read-only, and it was frozen with three doors intentionally left open.

**The community stock-media gate.** Every physical disk qualified so far was formatted and written by the MEGA65's own F011 controller. The genuine stock 1581 layout is exercised byte-exactly in simulation — derived from the formatter code at `$C3F8` in the genuine ROM — and confidence is high, because stock media is the *easier* dialect: its ID fields carry the conventional `00` preamble, its sectors stay within 1..10, and it shares the entire DD MFM, index, and readiness path. But a disk written by a physical Commodore 1581 has never been locally available, so this remains strong evidence rather than hardware proof. The gate is community testing, not new RTL. The protocol, recorded in the working notes for whoever runs it: use a backed-up or sacrificial disk formatted and written on a genuine 1581 and verified in that drive immediately beforehand; record the provenance (source drive, media, MEGA65 board revision); on the MEGA65, run a cold `LOAD"$",8`, load one known program, let the motor stop, and load again, capturing the BASIC result, the error channel, and the diagnostic dump before ejecting. A pass requires correct directory and program behavior, exact request/result trace pairing, a full 512-byte final presentation, and zero RNF/CRC/LOST/delivery counters. And one warning is explicit: do not retune the decoder from a single aged-disk failure — first prove the disk still reads on its genuine 1581, reproduce the failure, and compare independently written disks.

**The staged write and format roadmap.** Writing is a separate milestone that must be *explicitly opened*, in the maintainer's framing, because it changes the core "from magnetically incapable of writing to intentionally energizing WGATE" — today the write gate and write data pins are tied inactive at all four board tops (Chapter 18). The staging is fixed in advance: an explicit write-capability interlock that defaults off, preserving today's inactive pins on every build that does not opt in; WD1772 Write Sector first — drive-CPU byte ingestion, reverse-direction buffering, an MFM encoder, sync and address-mark generation, CRC, exact byte pacing, bounded abort — with read behavior provably unchanged whenever the capability is off; then adversarial simulation gates on a writable mechanism model (write-protect, starvation, reset and eject mid-command, byte-exact read-after-write) that must all pass *before* WGATE is ever driven on hardware; then qualification on sacrificial media with SAVE, overwrite, SCRATCH, VALIDATE, and power-cycle readback verified both in the MEGA65 and in an independent reader; and only after sector writes are safe, Write Track and stock-1581 formatting, verified for interoperability with a genuine 1581, followed by separate qualification of the other board revisions.

**Marginal-media research.** One genuinely open engineering question survived the freeze. The F011 succeeds on the same mechanism with a much more permissive fixed acceptance window — reaching down to roughly 100 cycles where the adaptive decoder's lower edge sits near 145 at the measured estimate — and one qualified session recorded a minimum gap of 126 cycles, tantalizingly inside the F011's window and outside ours. That observation is not motor- or record-qualified, so it proves nothing about rejected *records*; but it motivates a controlled true-F011-window A/B experiment, and a companion any-sync-re-anchor experiment, both explicitly deferred. They remain on a separate, evidence-driven branch with a hard entry condition: they may enter production only on the strength of hardware evidence from media that verifiably fails today's decoder while reading cleanly on a genuine drive. Until such a disk exists, the adaptive decoder of Chapter 13 — scarred, gated, and seven times raced against its own ancestors — stands as qualified.

## Glossary

Terms are defined here as this book uses them. Where a chapter teaches a concept in depth, the chapter is cited; the entry is a reminder, not a replacement.

**318045-02** — The revision of the genuine Commodore 1581 DOS ROM that this project treats as ground truth. The drive computer runs it unmodified, and its exact behavior — down to a status-table quirk in its job epilogue — shaped the delivery rules at the WD boundary (Chapter 8).

**6502** — The 8-bit MOS Technology CPU. One lives inside every intelligent Commodore drive; the 1581's runs the DOS ROM at 2 MHz (Chapter 5).

**6522 VIA** — The Versatile Interface Adapter, the I/O chip of the 1541 (which carries two of them). Named here mostly for contrast: the 1581 uses an 8520 CIA instead (Chapter 5).

**8520 CIA** — The Complex Interface Adapter used in the 1581, a sibling of the C64's own CIAs. It connects the drive computer to the IEC bus and to the mechanism's vital signs — side select, ready, motor, disk change all pass through its port A (Chapter 6). One quirk worth remembering: its time-of-day (TOD) counter in the 1581 counts the 2 MHz CPU clock, not wall-clock time.

**A1 sync mark** — See *sync mark*.

**A1 train** — The three consecutive A1 sync marks written before every address mark. The decoder accepts a train only when the three candidates arrive at exactly the right spacing and span the right total time — a timing qualification that rejects most write-splice garbage; what timing cannot reject, the record grammar and the CRC render harmless (Chapters 3 and 13).

**address mark** — A byte that announces what kind of record follows on the track: FE opens an ID field, FB a data field, F8 a deleted data field. Address marks are preceded by the A1 train, which is what makes them findable in a stream that has no byte boundaries of its own (Chapter 3).

**ATN** — The IEC bus's attention line: the computer pulls it low to open a command phase, and every drive must stop what it is doing and listen (Chapter 5).

**BAM** — Block Availability Map, the 1581 DOS's allocation bitmap recording which sectors are free. It lives with the directory on logical track 40 — physically adjacent to the index write splice on a freshly formatted disk, a location that made it the first casualty of splice-induced decode failures (Chapter 7).

**bit cell** — The time slot that carries one data bit: 4 µs at DD. MFM divides it into two half-cells, one for the clock position and one for the data position (Chapter 2).

**BRAM** — Block RAM, the dedicated on-chip memory of an FPGA. Fast but scarce — a full D81 image does not fit, which is why the mount buffer lives in HyperRAM instead.

**busy tail** — The short interval, at least one byte-time, for which the WD1772 model keeps its busy flag set after the last presentation, so the DOS's poll-busy-first loop reliably observes the end of an operation (Chapter 15).

**byte-time** — The time one byte occupies on a DD track: 16 half-cells, 32 µs, 1600 cycles. Presentation pace, the busy tail, and the DAM search window are all measured in byte-times (Chapter 15).

**CDC** — Clock-Domain Crossing: moving a signal between two unrelated clocks. Done carelessly it produces rare, unreproducible corruption; the physical path crosses domains only through two-flop synchronizers, toggle handshakes, and a Gray-pointer FIFO (Chapter 16).

**CHRN** — The four payload bytes of an ID field: Cylinder, Head, Record (the sector number), and Number (the size code; `N = 2` means 512 bytes) (Chapter 3).

**CIA** — Complex Interface Adapter; see *8520 CIA*.

**CRC** — Cyclic Redundancy Check, the 16-bit checksum guarding every ID field and data field: polynomial 0x1021, initial value 0xFFFF, fed most-significant-bit first — the variant known as CRC-16/CCITT-FALSE. It is self-checking: feeding the two stored check bytes after the field leaves residue 0x0000 exactly when everything was read correctly (Chapter 3).

**cycle** — Unqualified in this book: one 50 MHz controller clock cycle, 20 ns. Every other clock is always named explicitly.

**cylinder** — All tracks that sit under the heads at one head position — on a two-sided disk, the pair of same-numbered tracks on both surfaces. "Track" properly names one surface's circle; ID fields address cylinders (the C in CHRN), while Commodore DOS numbering speaks of logical tracks (Chapter 7).

**D81** — The byte-exact image-file format of a 1581 disk: 80 cylinders × 2 sides × 10 sectors × 512 bytes = 819,200 bytes, no more and no less. D64 and G64 are the 1541 equivalents — a sector dump and a GCR-level dump, respectively (Chapters 7 and 11).

**DAM (data address mark)** — The FB address mark that opens a data field; its F8 variant marks the field as deleted data. The decoder accepts a DAM only when the record grammar allows one (Chapter 3).

**data field** — The record that carries a sector's 512 payload bytes: A1 train, DAM, payload, CRC. Its identity is established only by the ID field read shortly before it — the data field itself does not know which sector it is (Chapter 3).

**data separator** — The classical name for the circuit that recovers clock and data from raw flux timing, historically an analog PLL. Our implementation is a fully digital adaptive quantiser (Chapters 2 and 13).

**DD / HD** — Double Density and High Density 3.5-inch media (720 KB and 1.44 MB formatted, in PC terms). The 1581 — and everything in this book — is DD only: 250 kbit/s, 300 RPM (Chapter 6).

**dead-band** — A range of gap lengths that a fixed-window classifier maps to nothing at all. The legacy fixed windows had two; peak shift on inner cylinders pushed real gaps into those no-man's-lands for revolutions at a time, which is why the production quantiser has none (Chapter 13).

**diagnostic device** — The read-only QNICE register bank (device 0x0108) that mirrors the physical path's internal state: live pins, counters, latched results, the estimate, and the trace ring. Reading it never disturbs the machinery it observes (Chapter 17).

**disk change** — The mechanism's latched line reporting that the disk was removed since the latch was last cleared; clearing requires a head step with a disk present. The 1581 DOS reads it on CIA port A bit 7 (Chapters 6 and 14).

**DOS** — Disk Operating System. In Commodore drives the DOS runs inside the drive itself, on the drive computer; the computer merely sends commands and file data over the IEC bus (Chapter 5).

**drive computer** — The 6502-plus-ROM-plus-CIA upper half of the 1581, the part that runs the DOS. We keep it unchanged in both media backends; only what it sees through the WD1772 differs (Chapter 5).

**DRQ** — Data ReQuest, the WD1772 status bit and handshake telling the drive computer that the data register holds a byte (when reading) or wants one (when writing). During a read it fires once per byte-time (Chapter 4).

**estimate, the** — The adaptive half-cell estimate of the quantiser: its live belief about how long a half-cell currently is, nudged by 1/8 cycle per accepted gap and clamped to ±10% of nominal (Chapter 13).

**F011** — The C65/MEGA65 native floppy-disk controller, with its own register model and its own on-disk habits. It is emphatically not a WD1772 — but F011-formatted media are what the internal drive usually holds, so our decoder tolerates the F011 formatter's layouts (Chapter 9).

**fast serial** — The accelerated Commodore serial protocol whose shift-register hardware lives in the 1581's 8520. It is dormant in this core: the C64 has no fast-serial wire, so the FCLK line is tied off and the burst engine never runs (Sections B3 and B4).

**FDC** — Floppy Disk Controller: the chip that turns "read sector 3 of track 40" into head movement, sync hunting, and byte delivery. The 1581's FDC is the WD1772 (Chapter 4).

**FIFO** — First-In, First-Out buffer: bytes come out in the order they went in. The physical path's read FIFO is dual-clock, written at 50 MHz and read in the drive's clock domain, with Gray-coded pointers (Chapter 16). See also *quarantine FIFO*.

**flux transition** — A reversal of the magnetization direction along the track: the only mark a floppy head can write and the only event it can sense. Everything on a floppy disk is encoded in *where* transitions sit, never in any "byte" the medium itself would know about (Chapter 1).

**FM** — Frequency Modulation, the original single-density floppy code: every bit cell opens with a clock transition, with data transitions in between. MFM halves the transition budget by making the clock transitions conditional (Chapter 2).

**Force Interrupt** — The WD1772's Type IV command: abort whatever is in progress. Our delivery layer pairs it with sequence tags so a cancelled operation's late completion can never be mistaken for the next operation's (Chapter 4).

**FPGA** — Field-Programmable Gate Array, a chip whose logic is configured after manufacture. The MEGA65's Xilinx Artix-7 FPGA hosts the entire C64, its drives, and everything else in this book.

**FSM** — Finite State Machine: logic that is always in exactly one named state and moves between states on defined events. The decoder, the controller, and the WD1772 model are each built around FSMs.

**gap** — Unqualified in this book: the time between two flux transitions — the decoder's raw datum. The track-format sense (filler between records) is always called "gap bytes" or named explicitly ("Gap 2") (Chapter 2; the format sense, Chapter 3).

**gap bytes** — The 0x4E filler written between records so that writes have room to land and readers have room to rest between fields. The F011 formatter writes ID fields directly after gap bytes with no zero preamble — a habit our sync qualification must tolerate (Chapter 3).

**GCR** — Group Coded Recording, the 1541's line code, mentioned only for contrast: code groups instead of clock bits. The 1581 is an MFM drive (Chapter 2).

**GHDL** — The open-source VHDL simulator in which the physical path's test suites run: the Section B6 benches, from single-module units to the closed-loop codec race, execute in it without any vendor tools (Section B6.1).

**glitch floor** — See *runt*.

**Gray code** — A counting order in which successive values differ in exactly one bit, which makes a counter safe to sample from another clock domain: however the sample lands, it is off by at most one step. Asynchronous FIFO pointers use it (Chapter 16).

**half-cell** — Half an MFM bit cell: 2 µs at DD, 100 cycles. The quantiser thinks entirely in half-cells — legal gaps are two, three, or four of them (Chapter 2).

**HDL** — Hardware Description Language, such as VHDL or Verilog: source code that describes circuits rather than instructions.

**head** — The electromagnetic transducer that reads and writes flux transitions, one per side of the disk. "Head" also names the ID-field byte (the H in CHRN) that says which side a sector belongs to (Chapter 6).

**HyperRAM** — The MEGA65's external low-pin-count RAM chip: large but comparatively slow, and shared among several subsystems. It holds the mount buffer, among other things (Chapter 11).

**ID field** — The record that names a sector: A1 train, FE address mark, CHRN, CRC. A sector is only ever found by reading ID fields and comparing — a track has no table of contents (Chapter 3).

**IDAM** — ID Address Mark: the FE address mark that opens an ID field (Chapter 3).

**IEC** — The Commodore serial bus connecting computer and drives: few wires, wired-AND signaling, and the reason a Commodore drive must be intelligent (Chapter 5).

**image mode** — One of the two media backends of drive 8: sectors are served from a mounted D81 disk-image file. Its sibling is physical mode (Chapter 10).

**index hole / index pulse** — The once-per-revolution reference: a sensor in the mechanism produces one pulse per revolution, every 200 ms at 300 RPM. It marks "the start" of a track and paces every rotational timeout (Chapter 3).

**INTRQ** — The WD1772's interrupt request output, raised when a command completes (Chapter 4).

**ISI** — Inter-symbol interference; see *peak shift*.

**JiffyDOS** — A commercial fast-loader ROM family that replaces the C64 Kernal and the drives' DOS ROMs with a faster serial protocol. The core can substitute JiffyDOS drive ROMs for the stock DOS (Chapter 11).

**JTAG** — The debug port through which a development bitstream, and the QNICE monitor connection, reach the board.

**LBA** — Logical Block Address: a sector's single linear number, counting through the whole disk in a fixed order, as opposed to its cylinder/head/sector coordinates (Chapter 11).

**login sequence** — Commodore DOS jargon for the validation a drive performs on a newly inserted disk before its first job: the DOS probes the medium and reads its header and BAM, and only a successful login makes the disk usable. The 1581's login leans on Read Address — the reason physical mode hides the F011's out-of-range sector-11 ID, which would otherwise abort it (Chapter 14).

**loss of lock** — The quantiser's loud failure: a gap that fits no acceptance window emits the invalid class, resets the estimate to nominal, and wipes the downstream parse. Loud beats silent — a wrong-but-plausible classification would corrupt data invisibly (Chapter 13).

**LOST DATA** — WD1772 status bit 2: a newly presented byte overwrote one the drive computer had not yet collected. Presentation never waits, because a spinning disk never does — a too-slow consumer loses bytes and is told so (Chapter 4).

**LSB / MSB** — Least and Most Significant Bit (or byte, by context). MFM bytes travel MSB-first, and the CRC is fed MSB-first.

**M2M** — MiSTer2MEGA65, the porting framework that hosts MiSTer cores on the MEGA65. It supplies QNICE, the Shell, vdrives, and the RAMROM window (Chapter 10).

**mechanism, the** — The physical 3.5-inch drive unit: spindle motor, stepper, heads, and sensors — everything behind the electrical connector. In the MEGA65 it is the built-in floppy drive (Chapter 6).

**media ready** — The synthesized "you may trust this disk" condition: motor on and real index pulses proving plausible rotation — two qualified index edges from cold, a single edge when the same unchanged medium resumes. The 1581 DOS reads it as the ready line on CIA PA1 (Chapter 14).

**MFM** — Modified Frequency Modulation, the DD floppy line code. A clock transition is written only between two zero data bits, so consecutive flux transitions are always two, three, or four half-cells apart — the data lives entirely in that spacing (Chapter 2).

**MiSTer** — The FPGA retro-computing platform whose C64 core, including the `iec_drive` 1541/1581 implementation, this project ports to the MEGA65 through the MiSTer2MEGA65 framework (Chapter 10).

**mount buffer** — The HyperRAM-backed staging area holding the currently mounted disk image; the Shell fills it from the SD card, and vdrives serves sectors out of it (Chapter 11).

**OSM** — On-Screen Menu: the overlay menu through which images are mounted and "Use internal 1581" is switched (Chapter 10).

**PA0–PA7, PB0–PB7** — The bit names of a CIA's or VIA's two 8-bit I/O ports A and B. In the 1581, port A carries the mechanism's vital signs: PA0 side select, PA1 ready, PA2 motor, PA7 disk change (Chapter 6).

**peak shift** — The dominant analog distortion of floppy readback, also called inter-symbol interference (ISI): neighboring flux transitions repel each other, so short gaps read back longer and long gaps shorter — worst on inner cylinders, where transitions crowd together. The adaptive quantiser exists to survive it (Chapters 1 and 13).

**physical mode** — The other media backend of drive 8: the same simulated 1581 drive computer, but sectors come from a real disk in the MEGA65's internal mechanism, decoded from real flux (Chapter 10).

**PLL** — Phase-Locked Loop, the analog control loop classical data separators used to track the bit rate. The physical path replaces it with a digital adaptive quantiser (Chapter 2).

**presentation** — Handing a byte to the WD1772 data register at disk pace: one byte per byte-time during a DD read. Presentation is relentless — it never waits for the consumer (Chapter 15).

**Q8.4** — A fixed-point number format: 8 integer bits and 4 fraction bits, counting in sixteenths. The estimate is kept and reported in Q8.4 — 0x0640 reads as 100.0 cycles.

**QNICE** — The 16-bit helper softcore CPU of the MiSTer2MEGA65 framework. It runs the Shell, fills the mount buffer, and its monitor is the window through which the diagnostic device is read; its 50 MHz clock is also the controller clock (Chapter 17).

**quantiser** — The decode stage that classifies each gap as short, medium, or long — two, three, or four half-cells — by comparing it against the estimate: adaptive, midpoint-touching, with no dead-bands (Chapter 13).

**quarantine FIFO** — The 512-byte first-in-first-out buffer between the controller and the WD1772 model. A whole data field lands in it before the drive computer sees anything; only a clean CRC verdict releases the bytes at presentation pace, and a failed field is drained unseen (Chapter 15).

**RAM** — Random-Access Memory; read-write working memory, whether on-chip (BRAM) or external (HyperRAM).

**RAMROM window** — The MiSTer2MEGA65 memory-mapped I/O scheme by which QNICE reaches core devices: select a device number, select a 4 K window, then read at address 0x7000 plus the word offset. It is how the diagnostic device appears at the monitor prompt (Chapter 17).

**Read Address** — The WD1772 Type III command that returns the next ID field's six bytes — CHRN plus the stored CRC — instead of sector data; the DOS uses it to learn where the head really is. In physical mode only sector IDs 1 through 10 are presented, hiding the extra CRC-valid sector-11 ID that F011-formatted tracks can carry (Chapter 14).

**record grammar** — The ID-before-data sequencing rule set: a DAM is only meaningful shortly after a CRC-valid ID field, and only when preceded by the zero-run its formatter always writes. Enforcing the grammar is what finally makes timing-valid write-splice garbage harmless (Chapter 13).

**RNF** — Record Not Found, WD1772 status bit 4: the requested sector's ID never turned up within the search budget. Our controller never reports RNF together with a CRC error — a pairing the genuine DOS ROM would misread as success (Chapters 4 and 15).

**ROM** — Read-Only Memory; here usually the DOS ROM inside the drive computer or the Kernal/BASIC ROMs inside the C64.

**RPM** — Revolutions Per Minute. A 3.5-inch DD disk spins at 300 RPM: one revolution every 200 ms.

**RTL** — Register-Transfer Level: the abstraction at which synthesizable HDL describes hardware, registers plus the logic between them. Loosely, "the RTL" means the source code of the hardware.

**runt** — An impossibly short gap, below the glitch floor of `C_GAP_GLITCH` = 16 cycles (320 ns), caused by electrical noise splitting one flux pulse into two edges. The gap stage drops the spurious edge but keeps counting, so the runt's time merges into the following gap (Chapter 13).

**sector** — The unit of disk allocation and transfer. Physically the 1581 has ten 512-byte sectors per track; the DOS then splits each into two 256-byte logical sectors, so software sees 80 logical tracks of 40 sectors (Chapter 7).

**sector interleave** — Deliberately spacing consecutively numbered sectors around a track so that a host needing think-time between sectors does not wait a whole revolution for the next one (Chapter 3).

**sequence tag** — A small label attached to each read request and echoed on its completion, so a completion can be matched to *its* request — and a stale one, from an operation that was cancelled or superseded, is provably ignorable (Chapter 15).

**Shell, the** — The QNICE menu firmware: the on-screen menu, the file browser, and the mounting machinery. It owns the "Use internal 1581" switch and the idle gate around it (Chapter 10).

**side** — One of the two recording surfaces of a disk, each served by its own head; the side is the H in CHRN. The 1581 is double-sided (Chapter 6).

**spin-up** — The interval between switching the motor on and the medium rotating at trustworthy speed. The real WD1772 counts index pulses for this; in our split design the controller owns spin-up through the media-ready qualification (Chapters 4 and 14).

**splice** — See *write splice*.

**sync mark** — A byte written with a deliberate violation of the MFM clock rule, so that its raw pattern — 0x4489 for the A1 sync mark — can never occur in ordinary data. It is the only trustworthy byte-alignment anchor on a track (Chapter 3).

**synchronizer (two-flop)** — Two cascaded flip-flops through which every asynchronous single-bit signal must pass before use in a clock domain, reducing metastability to negligible probability. The first flop carries an attribute that keeps the pair physically adjacent on the FPGA (Chapter 16).

**T65** — The VHDL implementation of the 65xx CPU family used throughout this core, for the C64's 6510 and for the drive computers' 6502s alike.

**TIB** — Track Information Block, a MEGA65/F011 extension storing per-track format metadata on the disk. Out of scope for the 1581 path; the adapted codec dropped it (Chapter 9).

**TOD** — The 8520 CIA's time-of-day circuit — in the 8520 a free-running 24-bit binary counter rather than a wall clock. The 1581 wires its input to the 2 MHz CPU clock, so it counts CPU cycles and wraps every 8.4 s; see *8520 CIA* (Section B4).

**toggle handshake** — Signaling an event across clock domains by flipping a level: the receiver synchronizes the level and reacts to the change. Unlike a pulse, a toggle cannot be missed (Chapter 16).

**trace ring** — The diagnostic device's 32-entry circular log of the DOS-to-WD dialogue — every step, every read request, every completion — reconstructing a drive conversation on real hardware without a logic analyzer (Chapter 17).

**track** — The circle a head sweeps on one surface at one head position; see *cylinder* for the distinction that matters in ID fields (Chapter 7).

**track 0 sensor** — The mechanical switch that closes when the head reaches the outermost cylinder. It is the only absolute position reference the mechanism has; everything else is dead reckoning by counted steps (Chapter 14).

**Type I–IV commands** — The WD1772's four command classes: Type I moves the head (Restore, Seek, Step), Type II transfers sectors (Read and Write Sector), Type III handles IDs and whole tracks (Read Address, Read Track, Write Track), and Type IV is Force Interrupt (Chapter 4).

**vdrives** — The MiSTer2MEGA65 virtual-drive engine that serves disk-image sectors to the drive in image mode. Physical mode bypasses it entirely (Chapter 11).

**VHDL** — One of the two main hardware description languages (the other being Verilog); most of the physical path is written in it.

**VIA** — Versatile Interface Adapter; see *6522 VIA*.

**WD1772** — The Western Digital floppy-disk controller inside every real 1581, modeled in this core by `fdc1772.v`. Four registers — Command/Status, Track, Sector, Data — and a command set the DOS ROM knows intimately; speaking its language convincingly is the whole point of the delivery layer (Chapter 4).

**wired-AND** — The IEC bus's electrical convention: every device can only pull a line low, so the line reads low whenever *any* device asserts it. It lets several drives share the bus without electrical conflict (Chapter 5).

**write protect** — The mechanical slider sensed by the mechanism and reported through the controller. In the read-only milestone the physical disk is always presented as write-protected, whatever the slider says (Chapter 18).

**write splice** — The discontinuity where a write began or ended, meeting older recording mid-flux. The medium there holds timing-plausible garbage that can mimic sync — the antagonist of Chapter 13's qualification layers (Chapters 3 and 13).

## Document map

This book keeps company with a small library of sibling documents, each authoritative for something the book deliberately does not duplicate. This map is the guided tour: what each document is, where it speaks with final authority, and how it has aged. All links are relative to `doc/`.

**[1581_dd_debug_device.md](1581_dd_debug_device.md)** — the user-facing reference for the diagnostic device: the full register map at version 7, every bit layout, the trace-ring encoding, a complete QNICE-monitor walkthrough, and triage playbooks for the common failure smells. It is the authority for everything register-level; this book never re-tabulates the map, and Chapter 17 teaches the concepts while deferring all detail here. It is also the one document in this list that is maintained in lockstep with the RTL rather than frozen at a point in time.

**[issue_90_internal_mega65_drive_as_1581.md](issue_90_internal_mega65_drive_as_1581.md)** — the normative specification for the physical 1581, written in requirements language: the media contract, the magnetic and timing model, the WD1772-visible behavior per command class, clock-domain and safety rules, and verification criteria all the way to read, write, and format. It is the project's constitution, and it remains authoritative for intent and for the write and format milestones still ahead. It has aged in one deliberate way: the read milestone was implemented pragmatically, per [dev-fdd/DESIGN.md](dev-fdd/DESIGN.md), rather than literally to this spec — and its diagnostics section (§18) was a draft of what the debug-device reference now documents as shipped.

**[dev-fdd/DESIGN.md](dev-fdd/DESIGN.md)** — the frozen architecture of the read milestone as actually built: the module list of `CORE/vhdl/physical_1581/`, the drive-to-controller ABI signal names, the CDC discipline, the baked timing constants, and how each reconnaissance risk was answered. Authoritative for the shape of the implementation and the handshake contracts. It has aged in the numbers: the decode chain evolved past it — the gap windows it tabulates are the legacy fixed windows, and the adaptive quantiser plus the sync and record-grammar qualifiers came later — so `CORE/vhdl/physical_1581/physical_1581_pkg.vhd`, not this file, is the authority for constants.

**[how-MEGA65-uses-the-physical-disk-drive.md](how-MEGA65-uses-the-physical-disk-drive.md)** — the research document that answered "how does the MEGA65 core itself drive the internal mechanism, and where should C64MEGA65 cut the interface". It is the provenance of the F011 codec extraction and still the best didactic background on the F011 register model, the MEGA65 firmware policy, and the pin semantics (Chapter 9's world). It is explicitly superseded for anything normative by the issue-90 specification, and its snapshots of "the current C64MEGA65 state" describe the tree as it stood before any of this work landed.

**[path-to-d81.md](path-to-d81.md)** — the implementation-ready specification of the image-backed 1581: the D81 geometry and the 819,200-byte rule, the block-RAM impossibility argument that forced the mount buffer into HyperRAM, the `fdc1772.v` clock-domain crossing, and JiffyDOS-1581. It is the rationale record for every image-mode decision Chapter 11 narrates. It describes the pre-implementation tree — its file-and-line anchors point at code as it stood before the feature was built — so read it for *why*, and the current source for *where*.

**[dev-fdd/PLAN.md](dev-fdd/PLAN.md), [dev-fdd/HANDOVER.md](dev-fdd/HANDOVER.md), [dev-fdd/plan_codex.md](dev-fdd/plan_codex.md), [dev-fdd/handover_codex.md](dev-fdd/handover_codex.md)** — the chronological working logs of the bring-up, in the "round" numbering that the testbench headers cite; the Appendix retells this history as narrative. They are authoritative only for what was believed and attempted *at the time*. Never trust them for present-tense claims: plans changed underneath them, and a few artifacts they mention were never committed to the tree.

**[dev-fdd/recon_map.md](dev-fdd/recon_map.md) and [dev-fdd/codec_adaptation.md](dev-fdd/codec_adaptation.md)** — the supporting studies behind DESIGN.md: a line-level reconnaissance of clocks, CDC boundaries, and the port-threading chain from the board tops down to `fdc1772.v`, and the stage-by-stage plan for adapting the MEGA65 codec — including the CRC identification and the LGPLv3 license-provenance table for the upstream sources, which live pinned in [dev-fdd/upstream/](dev-fdd/upstream/). The provenance keeps its value indefinitely; the line numbers have rotted with the tree.

**[dev-fdd/f011_reference_notes.md](dev-fdd/f011_reference_notes.md)** — a focused comparison of the MEGA65's own F011 decoder with ours, written after the control experiment in which the problem medium read flawlessly under the F011 — proof that a purely digital decoder suffices on that exact disk. Authoritative for the upstream-versus-ours delta at the pinned mega65-core commit; a working note in tone, and pinned to that commit rather than to upstream's tip.

**[dev-fdd/rom_emu/](dev-fdd/rom_emu/)** — the genuine-ROM-in-the-loop proof suite: a small Python 6502 running the real DOS ROM 318045-02 against models of the physical path's delivery contract (Section B6.4 shows how to run it). It is the only layer that can prove ROM-behavioral claims — the `$CD5A` status-table hole, the LOST DATA misreturn, the readiness windows — and its proofs are re-runnable at any time. Its own README states what it is: working notes, deletable, not part of the shipped feature. Treat its device models as evidence about the ROM, never as a second implementation of the hardware.

**[../tests/README.md](../tests/README.md)** — the append-only regression-test record of the whole core, one section per shipped version, newest on top; its current unreleased section is the hardware test checklist for the physical-1581 read milestone. The convention matters when reading it: past version sections record what was tested *then*, in the vocabulary of that release, and are deliberately never edited to match today's menus or feature names.
