# RR-Net on the MEGA65 — Research & Implementation Dossier

*Prepared for [MJoergen/C64MEGA65 issue #234](https://github.com/MJoergen/C64MEGA65/issues/234) — "Simulate RR-Net using the MEGA65's built-in Ethernet port."*

*This is a research document, not a code change. It answers the questions raised in the issue and gives everything needed to implement a VICE-equivalent simulated RR-Net inside the C64MEGA65 core. Every technical claim below is grounded in a primary source — the VICE source code, the Cirrus Logic CS8900A datasheet (DS271F3), the icomp.de / c64-wiki RR-Net pages, the official RR-Net MK3 manual, the real cc65/IP65 + Contiki C64 driver, and the MEGA65 `mega65-core` `ethernet.vhdl`. Source citations are inline; provenance is collected in Appendix G.*

---

## TL;DR (read this first)

**The single most important correction:** RR-Net does **not** emulate a phone-line modem, and it has **nothing to do with `AT` commands**. That is the SwiftLink / Turbo232 + external-modem world. **RR-Net is a Cirrus Logic CS8900A 10base-T Ethernet chip** wired onto the C64 expansion port's I/O-1 area (`$DE00–$DE0F`). It is a *dumb network card*: it moves **raw Ethernet frames** in and out, and **the entire TCP/IP stack (ARP, IP, ICMP, UDP, TCP, DHCP, DNS…) runs on the C64's 6510 in software** (Contiki, IP65/NetBoot65, WarpCopy64, etc.). There is **no text parser, no command interpreter, and no `AT` handler to write in VHDL.**

Consequently:

- **What you need to build** is a register-accurate **CS8900A emulation** (a 4 KB "PacketPage" register/buffer model behind 16 byte-wide I/O ports), plus a thin **bridge** that copies whole Ethernet frames between that emulation and the MEGA65's built-in Ethernet MAC. This is a *bounded, well-specified* piece of logic — VICE implements the whole chip in ~1 file.
- **Your existing VHDL IP stack is the wrong layer for the C64-facing side** and will go mostly **unused** for RR-Net: the C64 supplies ARP/IP/UDP itself. What *is* reusable is the *low half* of your work — the **MAC layer, FCS/CRC, and packet buffering** — for shuttling raw frames to/from the PHY. (Long answer in Part II, Q5.)
- It uses the **cartridge / expansion port**, not "some other port." Specifically the I/O-1 window `$DE00–$DE0F`, with a fixed register reshuffle (the "clockport XOR-8" described below), plus — for the MK3 variant — an optional 8 KB ROM at `$8000` toggled by `$DE80`/`$DE88`.

---

# PART I — What RR-Net Is

## 1. Philosophy and the big picture

RR-Net ("Retro Replay Net") is a 10 Mbit/s Ethernet network card for the Commodore 64, created by **Individual Computers (Jens Schönfeld)**, first released in 2003. Its design philosophy is deliberately minimal: it is a **link-layer-only Ethernet NIC** built around an off-the-shelf **Cirrus Logic CS8900A "Crystal LAN"** Ethernet controller, operated in **8-bit I/O mode**. The card does exactly two things: it transmits a buffer of bytes as one Ethernet frame, and it receives Ethernet frames into a buffer. Everything above the wire — address resolution, IP routing, transport, applications — is software running on the C64 itself.

This is the opposite of the other popular "C64 goes online" approach. A **SwiftLink / Turbo232** is a 6551-style UART cartridge; you attach a real (or virtual) **modem** to it and drive that modem with **`AT` commands** over a serial byte stream. RR-Net has **no UART, no modem, and no `AT` command set**. The confusion in the issue ("the cartridge emulates a phone-line modem, and you control it by sending text commands beginning with `AT`") conflates these two completely different cartridges. RR-Net is a LAN card; the bytes crossing its register interface are **Ethernet frames**, not modem command text.

**Primary-source confirmation that it carries raw frames and nothing more:**

- The chip is named on both [wiki.icomp.de/wiki/RR-Net](https://wiki.icomp.de/wiki/RR-Net) and [c64-wiki](https://www.c64-wiki.com/wiki/RR-Net) as the Cirrus Logic **CS8900A** (Crystal LAN); the icomp wiki adds, verbatim, that *"the chip is used in 8-bit mode, so the 8 registers of an NE2000 are spread over 16 registers."*
- VICE's emulation core is literally titled *"cs8900.c — CS8900 Ethernet Core"* and its only outbound/inbound operations are `rawnet_arch_transmit()` / `rawnet_arch_receive()` — *complete Ethernet frames* handed to the host's libpcap / TUN-TAP raw-socket backend (`src/core/cs8900.c`, `src/c64/cart/cs8900io.c`). VICE's own error text says it needs *"TUN/TAP support, or … permissions to use raw net (if using libpcap)"* — i.e. raw Ethernet, no protocol logic.
- VICE's generic Ethernet-cart file states the device family plainly and points you at the chip, not a command set: *"for register documentation refer to the cs8900a datasheet"* (`src/c64/cart/ethernetcart.c`). The family it lists: **TFE ("The Final Ethernet") / RR-Net / 64NIC / NET64 / FB-NET** — all the same CS8900A NIC with minor address differences.
- The software that runs on top is an on-CPU TCP/IP stack. IP65's Ethernet module describes itself as managing *"transmission and reception of ethernet frames"*, and IP65 implements *Ethernet driver, ARP, IP, ICMP, UDP, TCP, DHCP, DNS, TFTP* — all in 6502 assembly. Its README states it bluntly: *"IP65 requires Ethernet hardware. There's no support for TCP/IP over serial connections whatsoever."*

## 2. The chip: Cirrus Logic CS8900A

Everything an RR-Net implementer must reproduce is the behaviour of the **CS8900A** in **I/O Mode, 8-bit**. The relevant model (datasheet DS271F3, cross-checked against VICE):

- The chip's internal state — configuration, status, the MAC address, transmit/receive control, and the frame buffers themselves — lives in a **4 KB internal address space called "PacketPage"** (`$000–$FFF`).
- The host does **not** see those 4 KB directly in I/O mode. Instead it sees **8 sixteen-bit I/O ports** (16 byte locations, offsets `$00–$0F`) and reaches PacketPage **indirectly** through a *pointer + data* pair: write a 12-bit PacketPage address to the **PacketPage Pointer** port, then read/write the addressed register through the **PacketPage Data** port. There is an **auto-increment** mode for streaming.
- A few hot paths are exposed directly as I/O ports for speed: the **Receive/Transmit Data** port (the frame FIFO), and write-only **TxCMD** / **TxLength** shortcuts.
- It is a **10base-T, half-duplex** part. The IRQ pin exists but **is not wired on RR-Net** — all real software **polls** status registers.

The full register map and bit definitions are in Appendices A–D. The "I/O Mode" choice and 8-bit operation are the chip defaults; you do **not** need to implement Memory Mode or DMA.

## 3. Variants and history

| Variant | Released | Form factor / how it attaches | Notes |
|---|---|---|---|
| **RR-Net (MK1)** | 2003 | Small daughter-card on a **clockport** header of a carrier cartridge | Original. No per-unit MAC stored (CS8900A in 8-bit mode has no MAC storage); software assigns the MAC. |
| **RR-Net MK2** | July 2007 | Clockport daughter-card, redesigned (RoHS), optimized for the MMC Replay shape; also fits Turbo Chameleon 64 | Full software compatibility with MK1. |
| **RR-Net MK3** | February 2014 | Either on a **clockport** (like MK2) **or plugged directly into the C64 expansion port** as a standalone cartridge | Adds an **8 KB flash ROM** with a startup CodeNet server and a per-unit individual MAC. Direct-cartridge mode does **not** work on SX-64 / very old C64 boards. |

(Release dates from [c64-wiki.de/wiki/RR-Net](https://www.c64-wiki.de/wiki/RR-Net) and the © 2014 RR-Net MK3 manual.)

**The "clockport" concept.** MK1/MK2 are not cartridges by themselves; they are daughter-cards that plug into a **clockport** — a small expansion header exposed by certain *carrier* cartridges. The carriers that host RR-Net are **Retro Replay, Nordic Replay, MMC64, MMC Replay, and the Turbo Chameleon 64**. The clockport maps a 16-byte I/O window at `$DE00–$DE0F` to the daughter-card. On a Retro Replay, **the clockport must be enabled by setting bit 0 of `$DE01`** before the card is reachable. The MK3 keeps the clockport option but adds a direct expansion-port edge connector so it can run alone.

**Two ROMs that are easy to confuse — keep them separate:**

- **"The Final Ethernet" (TFE)** is a *different, generic* CS8900A Ethernet cartridge that RR-Net is register-compatible with. VICE models both as one device with two address layouts (`-tfe` vs `-rrnet`). It is *not* a ROM.
- **"The Final Replay"** is a *freezer-cartridge firmware ROM* (from oxyron.de) that you flash onto a Retro Replay / Nordic Replay / MMC Replay (and works on Chameleon) to get proper RR-Net support. The MK3 manual explicitly recommends it and links `http://www.oxyron.de/html/freplay.html`. This is the ROM most RR-Net-on-a-freezer setups use.

## 4. How it connects to the C64

**It uses the cartridge / expansion port — specifically the I/O-1 region `$DE00–$DEFF`.** The CS8900A's 16 I/O bytes appear at `$DE00–$DE0F`. There are two things that make RR-Net's mapping non-obvious, and both matter for emulation:

### 4.1 The "clockport XOR-8" register reshuffle

RR-Net wires the CS8900A behind the clockport, which **swaps the two 8-byte halves** of the `$DE0x` window. Concretely, every CS8900A access is done with the low nibble **XOR'd with `0x08`**, and offsets `0x00/0x01` are not used for the chip. VICE implements exactly this in three places (`clockport-rrnet.c`, `rrnetmk3.c`, `ethernetcart.c` RR-Net mode), all doing `if (address < 0x02) …; address ^= 0x08;`.

The result — and this is the **single most important table for an implementer** — is the C64-visible layout (identical in the icomp wiki table and in the real C64 driver's equates):

| C64 address | CS8900A native offset (`addr ^ 0x08`) | Register | R/W |
|---|---|---|---|
| `$DE00/$DE01` | `0x08/0x09` | Interrupt Status Queue (ISQ) — **blocked / "n/a" on RR-Net** (also the carrier's clockport-enable reg) | — |
| `$DE02/$DE03` | `0x0A/0x0B` | **PacketPage Pointer** | R/W |
| `$DE04/$DE05` | `0x0C/0x0D` | **PacketPage Data (Port 0)** | R/W |
| `$DE06/$DE07` | `0x0E/0x0F` | PacketPage Data (Port 1) — 32-bit only | R/W |
| `$DE08/$DE09` | `0x00/0x01` | **Receive/Transmit Data (Port 0)** — the frame FIFO | R/W |
| `$DE0A/$DE0B` | `0x02/0x03` | Receive/Transmit Data (Port 1) — 32-bit only | R/W |
| `$DE0C/$DE0D` | `0x04/0x05` | **TxCMD (Transmit Command)** | W |
| `$DE0E/$DE0F` | `0x06/0x07` | **TxLength (Transmit Length)** | W |

> All 16-bit register pairs are **little-endian: low byte at the even address, high byte at the odd address** (icomp wiki, verbatim; confirmed by VICE's `GET_PP_16`/`SET_PP_16`).

This table was independently verified two ways: (a) the icomp.de register table, and (b) `C64_offset ^ 0x08` applied to VICE's native `CS8900_ADDR_*` constants — both produce the identical mapping, 8/8 rows, no discrepancy.

### 4.2 The MK3 standalone cartridge extras (optional)

When an MK3 is plugged directly into the expansion port (no carrier card), it adds:

- An **8 KB flash ROM mapped at `$8000`** (ROML), holding a startup CodeNet server.
- **`$DE80` = ROM_ENABLE** (write any value → ROM visible at `$8000`), **`$DE88` = ROM_DISABLE** (write any value → ROM hidden). The manual warns: *"WRITING TO THE EEPROM MAY RENDER THE CARTRIDGE MODE UNUSEABLE."*
- An MK3-detection trick: in clockport mode the otherwise write-only `$DE0C–$DE0F` become *readable* and return the last 2 MAC bytes plus two checksums (see Appendix F). This lets software auto-discover the per-unit MAC.

For a first MEGA65 implementation, the ROM and `$DE80`/`$DE88` are **optional** — standard network software (IP65/Contiki) does not require the on-cart ROM; it only requires the CS8900A registers at `$DE02–$DE0F`.

## 5. How users actually use it (and what software expects)

People buy and use RR-Net for, roughly, three things, in descending order of everyday popularity:

1. **Fast disk transfer between a PC and the real C64 over the LAN** — **WarpCopy64** + **CodeNet**. This is the killer app, especially for the MK3: hold the **Commodore (C=) key** at power-on and the MK3's ROM starts a **CodeNet server**; on the PC you run WarpCopy64, point it at the C64's chosen IP, "send server," and then read/write whole **D64/D81** images at high speed. CodeNet solves the chicken-and-egg problem (you need a program on the C64 to receive programs — the ROM provides it). WarpCopy's wire protocol is a **custom command/ack protocol over UDP**, LAN-only (not routed internet).
2. **A full TCP/IP experience on the 8-bit CPU** — **Contiki** (bundles the **uIP** stack with a web browser, a personal web server, telnet, IRC, e-mail). This is the canonical "the whole stack runs on the 6510" demonstration.
3. **Networking utilities and clients** built on **IP65** (the cc65 assembly TCP/IP library): **NetBoot65** (DHCP → TFTP network-boot a program), **Telnet65**, **Wget65** (HTTP downloader), **HFS65** (HTTP server), IRC, plus terminals (GuruTerm, CGTerm), a web browser (Singular), and **geoLink** (IP65 under GEOS).

**What every one of these expects from the hardware is the same thing: a CS8900A at `$DE02–$DE0F` that it can drive with the register sequence below.** None of them expects a modem, a UART, or any command parser. If your emulation reproduces the CS8900A register behaviour faithfully, *all* of this software works unmodified — exactly as it does today under VICE.

### 5.1 The canonical software interface — the real C64 driver

The reference for "what software expects" is the **cc65/IP65 CS8900A driver** `drivers/cs8900a.s` — which shares its origin with Contiki's C64 driver `cpu/6502/net/cs8900a.S` (the IP65 file header credits the Contiki project; authors Adam Dunkels & Oliver Schmidt). The two use the **same access sequence**; they are not byte-identical (current Contiki master reaches the registers through runtime-fixed-up `$FFxx` equates, whereas IP65 hard-codes `$DE08`/`$DE0C`/… directly). It is 6502 assembly (there is no C driver). Its register equates *are* the table from §4.1:

```asm
        .if .defined (__C64__) .or .defined (__C128__)
rxtxreg         := $DE08        ; frame data FIFO  (chip offset 0x00)
txcmd           := $DE0C        ; TxCMD            (chip offset 0x04)
txlen           := $DE0E        ; TxLength         (chip offset 0x06)
isq             := $DE00        ; ISQ / clockport  (chip offset 0x08)
packetpp        := $DE02        ; PacketPage Ptr   (chip offset 0x0A)
ppdata          := $DE04        ; PacketPage Data  (chip offset 0x0C)
        .endif
```

Everything is **16-bit, little-endian, low byte first** — the driver always touches `xxx` then `xxx+1`. Accessing any PacketPage register is "write the 12-bit PP offset to `$DE02/$DE03`, then read/write the value at `$DE04/$DE05`." The full probe/init/transmit/receive sequences the chip must satisfy are reproduced verbatim in **Appendix C** — that appendix doubles as your **acceptance test vector**: if your VHDL reacts to exactly those accesses the way VICE does, real software will run.

The essential flow (details and source line numbers in Appendix C):

- **Detect:** enable the clockport (`$DE01 |= $01`), point PacketPage to `$0000`, read the **Product ID** and check it equals **`$630E`** (the Crystal Semiconductor EISA id; VICE seeds `$0900630E`, so `$0000`→`$630E`, `$0002`→`$0900`).
- **Init:** chip reset (PacketPage `$0114` ← `$0040`, then poll until the bit clears) → RxCTL (`$0104` ← `$0D05`, accept unicast+broadcast+good-CRC) → MAC address (`$0158/$015A/$015C` ← 6 bytes) → LineCTL (`$0112` ← `$00D3`, transmitter + receiver on).
- **Transmit:** write TxCMD (`$DE0C` ← `$00C9`) → TxLength (`$DE0E` ← len) → poll BusST high byte (PacketPage `$0138`) for the **Rdy4TxNOW** bit (`$0100`) → stream the frame, low byte then high byte, into `$DE08/$DE09`. The chip appends the FCS and sends.
- **Receive:** point PacketPage to `$0124` and read **RxEvent**; the act of reading it triggers reception. Then read **one word of RxStatus** (discarded), **one word of RxLength**, then the frame body — all out of `$DE08/$DE09`.

---

# PART II — MJoergen's Questions, Answered

> Quoted questions are from the issue.

### Q1 — *"As far as I can tell, the cartridge emulates a phone-line modem, and you control it by sending text commands beginning with `AT`."*

**No.** That description is a real thing, but it's a *different* product: SwiftLink/Turbo232 (a 6551 UART cartridge) plus a modem, controlled with `AT` commands. **RR-Net is a CS8900A Ethernet NIC.** Its register interface carries **raw Ethernet frames**, not text. There is no modem, no UART, and no `AT` command layer anywhere in the RR-Net path. (Proof: Part I §1; VICE `cs8900.c`/`cs8900io.c`; the CS8900A datasheet; the icomp.de and c64-wiki pages.)

### Q2 — *"I don't feel like implementing such a text parser in VHDL."*

**You don't have to — there is no text/`AT` parser anywhere in RR-Net.** What you implement instead is a **register state machine** for the CS8900A: 16 I/O ports, a 4 KB PacketPage register/buffer array reached through a pointer+data pair, and a handful of registers with side-effects (reset, RX/TX enable, the accept-filter, and the transmit handshake). This is a finite, well-specified piece of logic — the whole chip is one source file in VICE, and you only need a subset of it. See Part III and Appendix B for the exact subset.

### Q3 — *"Do you know anything more about the interface between C64 and RR-Net? Is it even using the Cartridge Port? Or is it using some other port?"*

**It uses the cartridge / expansion port, not another port.** Precisely:

- The CS8900A occupies the **I/O-1 window** at **`$DE00–$DE0F`**, with the RR-Net "XOR-8" register reshuffle (Part I §4.1, Appendix A). In practice the C64 touches `$DE02/$DE03` (PacketPage pointer), `$DE04/$DE05` (PacketPage data), `$DE08/$DE09` (frame data FIFO), and `$DE0C–$DE0F` (TxCMD/TxLength).
- On a carrier card (Retro Replay etc.) the clockport that exposes this window is gated by **bit 0 of `$DE01`**; the standard driver sets it before use. For a simulated direct-cartridge RR-Net you can simply **ignore writes to `$DE00/$DE01`** — the driver's `$DE01 |= 1` then becomes a harmless no-op and everything else still works.
- The **MK3 standalone variant** additionally uses **`$DE80`/`$DE88`** to map/unmap an **8 KB ROM at `$8000`** (optional for emulation).
- It does **not** use the IRQ line (not wired); software **polls**. It does **not** use any other C64 port (no userport, no serial, no SID, nothing).

### Q4 — *"And what software on the C64 does one use, and what does it expect?"*

**Software:** Contiki (full TCP/IP + browser/server/telnet/IRC), IP65 and its tools (NetBoot65, Telnet65, Wget65, HFS65, IRC), WarpCopy64 + CodeNet (PC↔C64 D64/D81 transfer — the most common real-world use), terminals (GuruTerm, CGTerm), Singular browser, geoLink (IP65 for GEOS). (Catalogue with what each does in Part I §5 and Appendix G.)

**What it expects:** a CS8900A at `$DE02–$DE0F` driven by the exact probe/init/TX/RX register sequence in Appendix C. The canonical driver is `cs8900a.s` (shared by cc65/IP65 and Contiki). The C64 software **runs its own ARP/IP/UDP/TCP**; it expects the hardware only to (a) report Product ID `$630E` so it knows the chip is present, (b) accept a MAC and RX-filter settings, (c) transmit a frame buffer it hands over, and (d) hand back received frames with a small RxStatus/RxLength header. Nothing more.

### Q5 — *"I have already a working IP network stack in VHDL (MAC layer, CRC calculation, packet buffering, ARP and UDP support, etc.). All the hard work is already done, and can 'just' be ported. But is that enough?"*

This is the most important question, and the honest answer has two halves.

**The bad news (and it's actually good news): your IP/ARP/UDP layer is the wrong layer for RR-Net and will go unused.** RR-Net is a *link-layer* device. The C64 software performs ARP, IP and UDP **itself**, on the 6510. If you inserted your own ARP/UDP between the C64 and the wire, you would not get "an RR-Net" — you would get an incompatible smart-NIC that none of the existing RR-Net software knows how to talk to (and worse, the C64's stack and yours would both try to answer ARP, fight over the MAC/IP, etc.). So for an RR-Net emulation, **do not** put your IP/ARP/UDP logic on the C64-facing path. The good news embedded here: the thing you *don't* want to do (build a protocol engine in VHDL) is the thing you were worried about — and you can skip it entirely.

**The good news: the *lower half* of your existing work is exactly what the bridge needs.** Your **MAC layer (RMII to the KSZ8081RNDCA PHY), your FCS/CRC engine, and your packet buffering** are precisely the components required to get raw frames on and off the wire. That's real, reusable work.

**So "is that enough?" →** No, not by itself, but you're well-positioned. The deliverable is not an IP offload; it's:

1. a **register-accurate CS8900A model** facing the C64 (new logic, but bounded — Part III §2, Appendix B), and
2. a **thin frame bridge** (Part III §4) that copies whole Ethernet frames between the CS8900A model's TX/RX buffers and your MAC, handling FCS reconciliation and mapping the CS8900A's accept-filter onto the MEGA65 MAC's filter/promiscuous controls.

Net assessment: the *physical* networking you've already solved is reused for the bridge; the *protocol* networking you've already solved is **not used** for RR-Net (it would break compatibility); and the genuinely new work — the CS8900A register state machine — is small, fully specified, and verifiable against VICE.

### Q6 — *"So I'm wondering how to implement such a solution … a kind of SIMCRT for the RR-Net."*

A SIMCRT-style internal device is exactly the right model. It splits cleanly into a C64-clock-domain CS8900A emulation that decodes `$DE0x`, and an Ethernet-clock-domain bridge to the MEGA65 MAC, joined by a small CDC. The complete blueprint — where it sits in `main.vhd`/`mega65.vhd`, the register subset, the bridge, reset/OSM integration, and a test plan — is **Part III**.

---

# PART III — Implementation Blueprint for C64MEGA65

## 1. Architecture overview

```
   C64 main clock domain (clk_main_i ~31.5 MHz, PHI2 ~1 MHz)        Ethernet clock domain (RMII 50 MHz)
   ────────────────────────────────────────────────────────        ──────────────────────────────────
   C64 6510  ──$DE0x I/O──►  ┌───────────────────────────┐          ┌──────────────────────────┐
   (core_ioe / addr)        │  CS8900A emulation         │   CDC    │  Raw-frame bridge        │
                            │  - 16 I/O ports ($DE02-0F) │◄───────►│  + MEGA65 Ethernet MAC   │──► KSZ8081
                            │  - 4 KB PacketPage (BRAM)  │  frame   │  (your MAC layer, or     │    RMII PHY
                            │  - TX buf @ PP $0A00       │  FIFOs   │   mega65-core eth MAC)   │◄── (LAN)
                            │  - RX buf @ PP $0400       │          │  - FCS append/strip      │
                            │  - RxCTL filter, LineCTL,  │          │  - MAC filter / promisc  │
                            │    SelfCTL, TxCMD/Len/BusST│          └──────────────────────────┘
                            └───────────────────────────┘
```

**Where it lives in the core.** Model it on the existing SIMCRT/SIMREU pattern (per `AGENTS.md` §4 and `CORE/vhdl/main.vhd`):

- Add a new expansion-port mode bit. Today `main.vhd` has `c64_exp_port_mode_i(1 downto 0)` with `C_SIM_CRT = 0` and `C_SIM_REU = 1` (`main.vhd:310-312`). Add `C_SIM_RRNET` (widen the vector, or use a dedicated control signal). Wire it from the OSM the way `C_MENU_SIM_CRT`/`C_MENU_SIM_REU` are wired in `mega65.vhd`.
- Decode the C64 address with the **I/O-1 strobe the core already exposes**. The MiSTer core / `fpga64_buslogic.vhd` produces `cs_ioE` (the `$DE00–$DEFF` access), surfaced in `main.vhd` as `core_ioe`. When `core_ioe = '1'` and the low byte is in `$02–$0F` (and the RR-Net mode bit is set), route the access to the CS8900A model. (For the MK3 ROM you would also decode `$DE80/$DE88` and the `$8000` ROML window.)
- Feed the CPU read result through the existing **`cpu_data_in_proc`** mux (`main.vhd:697-731`) — add an RR-Net branch alongside the hard-cart / SIMCRT / RAM branches, returning the CS8900A byte when an RR-Net I/O read is in progress.

**Clock domains.** The C64 side runs at `clk_main_i` (≈1 MHz effective PHI2). The wire side runs in the Ethernet/RMII domain (50 MHz for the KSZ8081RNDCA). Cross the two with the project's standard CDC building blocks (`M2M/vhdl/cdc_*.vhd`, `axi_fifo*`), exactly as HyperRAM/QNICE crossings are done. Frames are bursty and not latency-critical at the C64's pace, so a pair of frame FIFOs (TX C64→wire, RX wire→C64) with simple handshakes is sufficient.

## 2. The C64-facing CS8900A model — what to implement

Implement a **subset** of the chip. VICE's `cs8900.c` is the authoritative behavioural reference; the must-haves:

**State you need:**

- A **4 KB PacketPage byte array** (`$000–$FFF`) — a dual-port BRAM is ideal (C64 side + bridge side). The received frame lives at PP `$0400+`, the frame to transmit at PP `$0A00+`.
- The **16 I/O port bytes** and the **PacketPage Pointer** (16-bit). On pointer writes, force bits `0x3000` set (real HW reads them as `011b`) and honour the **auto-increment** flag `0x8000` (each Data-port access advances the pointer by one). VICE: `cs8900_store` does `word_value |= 0x3000`; `cs8900_auto_incr_pp_ptr` increments the low 12 bits.
- Small **TX and RX transfer state machines** for the frame FIFO port (`$DE08/$DE09`).

**Registers with live side-effects (the ones software actually drives — see Appendix B/D):**

- **SelfCTL `$0114`**, bit `0x0040` (RESET): on write, reset the chip model. Software polls it back to 0.
- **LineCTL `$0112`**, bit `0x0080` (SerTxON) / bit `0x0040` (SerRxON): enable transmitter / receiver. Map onto your MAC's enable + the accept-filter.
- **RxCTL `$0104`** accept bits: broadcast `0x0800`, individual/MAC `0x0400`, multicast `0x0200`, RxOK/correct `0x0100`, promiscuous `0x0080`, hash-filter `0x0040`. These decide which received frames the model hands to the C64; map them onto the MEGA65 MAC's `$D6E5` filter bits and/or filter in your bridge.
- **MAC / Individual Address `$0158–$015D`** (6 bytes): the station MAC the C64 chooses. Program it into the MEGA65 MAC (or use it for software filtering).
- **TxCMD `$0144`** (also reachable via the `$DE0C` shortcut) + **TxLength `$0146`** (`$DE0E` shortcut) + **BusST `$0138`** Rdy4TxNOW (`0x0100`) / TxBidErr (`0x0080`): the transmit handshake. Reproduce VICE's small state machine: a TxCMD write arms it, a valid TxLength sets Rdy4TxNOW, the C64 polls BusST, then streams the frame; when `count == length`, send.
- **RxEvent `$0124`** (reading it triggers reception in the model), **RxStatus `$0400`**, **RxLength `$0402`**: the receive path. When a frame arrives from the bridge, populate PP `$0400` (status), `$0402` (length), `$0404+` (bytes), and set the RxEvent accept bits so the C64's `poll` sees it.
- **Product ID `$0000` = `$630E`** (and `$0002 = $0900`): so the detect step passes.
- Optional but cheap: **hash filter `$0150`**, and the various reset default values (Appendix B) so reads look like a real chip.

**You do NOT need:** Memory Mode, DMA, the EEPROM command interface, interrupt generation (no IRQ on RR-Net), TxEvent/BufEvent niceties, or 32-bit port behaviour. Keep `$DE06/$DE07` and `$DE0A/$DE0B` (the Port-1 32-bit aliases) behaving like their Port-0 twins or inert; real C64 software uses only Port 0.

**Critical reproduce-or-software-hangs details (from VICE):**

1. **Side-effect reads.** Reading **RxEvent (`$0124`)** performs the actual frame reception (an "implied skip" if a prior frame wasn't drained). Reading **BusST (`$0138`)** high byte while the TX state is "got length" is what arms the data-write phase. If you make these pure registers, the real driver will spin forever.
2. **Byte/word order.** Everything is little-endian, low byte at even address. RxStatus/RxLength are read **high-then-low** as the driver does (`cs8900.c` documents this), then frame payload is **low-then-high**. The chip always transfers a 16-bit word per FIFO access; odd byte counts are rounded up to an even number of word accesses by the driver.
3. **TX length bounds / TxBidErr.** Reject TxLength `< 4`; raise TxBidErr for `> 1518`, or `> 1514` when CRC is not inhibited (the chip will add 4 FCS bytes). VICE: `MAX_TXLENGTH 1518`, `MIN_TXLENGTH 4`.

## 3. The `$DE0x` decode (and the optional MK3 ROM)

- Implement the **XOR-8** mapping: on a C64 access to `$DE00+n` (n = `0..0x0F`) with the RR-Net mode active, ignore `n < 2`, otherwise present `n ^ 0x08` to the CS8900A model (Appendix A). The simplest faithful target is **MK3-in-direct-cartridge mode**: the CS8900A is always present at `$DE02–$DE0F`; writes to `$DE00/$DE01` are ignored (so the driver's clockport-enable write is a harmless no-op).
- **MK3 ROM (optional, do later):** decode `$DE80` (ROM enable) / `$DE88` (ROM disable) and map an 8 KB image at `$8000` (ROML). This is only needed if you want the on-cart CodeNet-server-from-ROM experience; network software does not require it. If you implement it, mirror `rrnetmk3.c`: enable maps the 8K ROM as an 8K-game ROML at `$8000`; disable returns to RAM.
- **MK3 auto-MAC detection (optional):** make `$DE0C–$DE0F` readable returning `MAC_HI, MAC_LO, CHKSUM0, CHKSUM1` (Appendix F). Only needed if you want software to auto-discover a per-unit MAC; otherwise the C64 just programs whatever MAC it likes.

## 4. The raw-frame bridge to the MEGA65 Ethernet MAC

This is where your existing MAC/CRC/buffering work plugs in. The MEGA65 reference MAC is `mega65-core` `src/vhdl/ethernet.vhdl` (registers `$D6E0–$D6EF`); note the **C64MEGA65 core currently has the Ethernet PHY pins stubbed/tied off** in `M2M/vhdl/top_mega65-r*.vhd` — there is no MAC in the core today, so you will either port `ethernet.vhdl` or drop in your own MAC layer. Either works; the bridge contract is the same.

**Transmit (C64 → wire):** when the CS8900A model's TX state machine completes a frame (`count == length`) into PacketPage `$0A00+`, hand that buffer (length = TxLength) to the MAC's TX path and trigger send. With the MEGA65 reference MAC: copy the bytes to the TX buffer window, write the size to `$D6E2/$D6E3`, write `$01` to `$D6E4` (STARTTX), poll `$D6E0.7` (TXIDLE) for completion.

**Receive (wire → C64):** when the MAC reports a frame (MEGA65 ref: RX buffer ready, length+flags at buffer offsets `$000/$001`, body at `$002`), copy it into the CS8900A model's RX area: set RxLength (`$0402`), the RxStatus accept bits (`$0400`) per the matched type (broadcast/IA/multicast and CRC-OK), and the bytes at `$0404+`. Then advance the MEGA65 RX buffer by a **rising edge of `$D6E1` bit 1** (drive it 0 then 1 — the advance is edge-triggered, so a level-only write pops at most one frame). The C64's next `poll`/RxEvent read picks it up.

**FCS / CRC reconciliation — get this right or frames corrupt:**

- **TX:** the C64 hands you a frame **without FCS** (the CS8900A appends it, unless the rare INHIBITCRC bit is set). The MEGA65 MAC **always appends an FCS and has no inhibit control**. So: forward the C64 payload as-is and let the MEGA65 MAC add the FCS. Edge case: if the C64 set **INHIBITCRC** (`TxCMD` bit `0x1000`) it supplied its own 4 FCS bytes — strip those 4 bytes before handing to the MEGA65 MAC, or you'll double-FCS. (IP65/Contiki do **not** set INHIBITCRC, so the common path is "payload only, MAC adds FCS.")
- **RX:** the CS8900A presents received frames to the C64 **without** the trailing FCS by default. The MEGA65 MAC checks the FCS and reports a CRC-error flag (RX-buffer offset `$001` bit 7). Per `mega65-core` `ethernet.vhdl`, the delivered RX body at offset `$002+` **does include the trailing 4-byte FCS**, and the reported length **counts** those 4 bytes (the RX FSM stores every received byte and at end-of-frame subtracts only the 2 length-header bytes; the source comment reads *"max frame length = 2048 − 2 length bytes − 4 CRC bytes = 2042 bytes"*). So the bridge must **drop the last 4 bytes and subtract 4 from the length** before handing the frame to the C64. (The c65gs blog noted the early r1-PCB PHY path stripped the CRC; the current `ethernet.vhdl` MAC does not — sanity-check this if you adapt a *different* MAC for the bridge.) Map the MEGA65 CRC-error flag into the CS8900A RxStatus CRCerror bit (`0x1000`).

**MAC filtering / promiscuous:** the cleanest, most VICE-faithful approach is to run the MEGA65 MAC **promiscuous** (`$D6E5.0 NOPROM = 0` → accept all) and do the accept/reject in the CS8900A model using the RxCTL bits (this is exactly what VICE's `cs8900_should_accept` does). Alternatively, program the MEGA65 station MAC (`$D6E9–$D6EE`) to the C64-chosen MAC and enable broadcast (`$D6E5.4`) for hardware filtering — lower overhead, slightly less faithful (no per-frame hash filter). Recommended: promiscuous + model-side filter for first bring-up; optimize later if needed.

**Speed/duplex:** RR-Net is 10base-T half-duplex; the MEGA65 is 100 Mbit full-duplex RMII. **This is invisible above the frame layer** — you bridge *frames*, not bit timing; the PHY auto-negotiates line speed. No action needed.

## 5. Reusing your existing VHDL — concrete checklist

| Your existing block | Use it for RR-Net? | Notes |
|---|---|---|
| RMII / PHY interface to KSZ8081RNDCA | **Yes** | The wire side of the bridge. |
| MAC layer (framing, preamble, etc.) | **Yes** | Drives TX, captures RX frames. |
| FCS / CRC32 | **Yes** | TX append (unless INHIBITCRC), RX check/strip. |
| Packet buffering / FIFOs | **Yes** | Both TX and RX frame staging + CDC. |
| ARP responder | **No** | The C64 does ARP. Injecting yours breaks compatibility. |
| IP / UDP layer | **No** | The C64 does IP/UDP/TCP. Not used on the RR-Net path. |
| *(new)* CS8900A register/PacketPage model | **Build** | The C64-facing device — Part III §2, Appendix B. |
| *(new)* frame bridge + filter/FCS mapping | **Build** | Part III §4. |

## 6. Reset, OSM, and config integration

- **Reset semantics:** follow `main.vhd`'s rules (the `RESET SEMANTICS` block). The CS8900A model should reset on the C64 hard/soft reset path appropriately, but be careful not to drop a frame mid-DMA; an in-flight wire transfer is short, so a simple "finish current frame then reset" is fine. No vdrives-style dirty-cache interlock is needed (no SD writes involved).
- **OSM:** add a menu item (e.g. "Ethernet: RR-Net") that sets the `C_SIM_RRNET` mode bit, mirroring how `SIM CRT` / `SIM REU` are exposed (`CORE/vhdl/config.vhd` `OPTM_*`, decoded to a `C_MENU_*` bit in `mega65.vhd`). Optionally a sub-setting for the MAC address (or derive it from the MEGA65's own MAC, or use the icomp default `28:CD:4C:FF:FB:FF`).
- **No QNICE/Shell work is required** for the core data path — unlike SIMCRT (which streams a `.crt` from SD via QNICE), RR-Net has no file to load (the optional MK3 ROM is the only thing that would need loading, and that's a later nice-to-have).

## 7. Minimum viable product vs. full fidelity

- **MVP (gets WarpCopy64 / IP65 / Contiki working):** CS8900A model with Product ID, SelfCTL reset, RxCTL, LineCTL, MAC, TxCMD/TxLength/BusST handshake, RxEvent/RxStatus/RxLength, PacketPage pointer+data with auto-increment; XOR-8 decode at `$DE02–$DE0F`; bridge with promiscuous MAC + FCS handling. No ROM, no IRQ, no hash filter.
- **Full fidelity (later):** MK3 ROM at `$8000` + `$DE80/$DE88`, MK3 auto-MAC detection bytes, hash filter, TxEvent/BufEvent, and tighter reset-default register values.

## 8. Verification plan

1. **Use VICE as the golden reference.** Build VICE with `HAVE_RAWNET`, run x64 with `-rrnet` (RR-Net mode at base `$DE00`), bridged to a host TAP, and trace the `$DE0x` accesses (VICE has `CS8900_DEBUG_*` switches). Your VHDL should react identically.
2. **Unit-test against Appendix C** — feed your CS8900A model the exact probe/init/TX/RX access sequences (they're short and deterministic) and assert the register/bus responses match VICE. This catches the side-effect-read traps (RxEvent, BusST) early.
3. **On hardware, climb this ladder:** (a) Product-ID detect passes (software says "card found"); (b) IP65 `ip65_init` + DHCP gets a lease (proves ARP/IP TX+RX both directions through the bridge); (c) `ping65` / ICMP echo round-trips; (d) **WarpCopy64** directory read of a real disk (the canonical end-to-end milestone); (e) Contiki web browser fetches a page.
4. **Watch the two classic bugs:** double-FCS on TX (frames rejected by the switch / bad CRC at the peer) and FCS-in-RX-body (frames 4 bytes too long, IP length mismatch). Both are in Part III §4.

---

# Appendices

## Appendix A — CS8900A I/O port map: native (TFE) vs RR-Net (`$DE00` base)

The chip has 16 byte-wide I/O locations. "Native offset" is the datasheet/TFE layout; RR-Net applies `addr ^ 0x08` (and ignores offsets `0/1`). 16-bit pairs are little-endian (even = low byte, odd = high byte).

| Native offset | Register | R/W | RR-Net C64 address |
|---|---|---|---|
| `0x00/0x01` | Receive/Transmit Data, Port 0 (frame FIFO) | R/W | `$DE08/$DE09` |
| `0x02/0x03` | Receive/Transmit Data, Port 1 (32-bit) | R/W | `$DE0A/$DE0B` |
| `0x04/0x05` | TxCMD (Transmit Command) → PP `$0144` | W | `$DE0C/$DE0D` |
| `0x06/0x07` | TxLength → PP `$0146` | W | `$DE0E/$DE0F` |
| `0x08/0x09` | Interrupt Status Queue → PP `$0120` | R | `$DE00/$DE01` (blocked on RR-Net) |
| `0x0A/0x0B` | PacketPage Pointer | R/W | `$DE02/$DE03` |
| `0x0C/0x0D` | PacketPage Data, Port 0 | R/W | `$DE04/$DE05` |
| `0x0E/0x0F` | PacketPage Data, Port 1 (32-bit) | R/W | `$DE06/$DE07` |

PacketPage Pointer format: bits `0–11` = PacketPage address; bits `12–13` (mask `0x3000`) are forced to `1` on write and read back as `1`, while bit `14` reads `0` — so the high field `[14:12]` reads as the documented `011b` (you may write anything to it; VICE does `ptr |= 0x3000`); bit `15` (`0x8000`) = auto-increment.

## Appendix B — PacketPage register subset to implement (with reset values)

Addresses are PacketPage offsets (reached via the pointer+data ports). Reset values from the CS8900A datasheet, cross-checked against VICE `cs8900_reset()`.

| PP addr | Name | R/W | Reset value | Why you need it |
|---|---|---|---|---|
| `$0000` | Product ID (low word) | R | `$630E` | Detect (`$0002` = `$0900`) |
| `$0020` | I/O Base Address | R/W | `$0300` | Cosmetic; readback |
| `$0102` | RxCFG (Receiver Config) | R/W | `$0003` | Skip-frame bit `0x40`; (BufferCRC `0x0800` optional) |
| `$0104` | **RxCTL (Receiver Control)** | R/W | `$0005` | Accept-filter bits (Appendix D) |
| `$0106` | TxCFG | R/W | `$0007` | Cosmetic |
| `$0108` | TxCMD status (read-back) | R | `$0009` | Cosmetic |
| `$010A` | BufCFG | R/W | `$000B` | Cosmetic |
| `$0112` | **LineCTL** | R/W | `$0013` | SerTxON `0x80` / SerRxON `0x40` |
| `$0114` | **SelfCTL** | R/W | `$0015` | RESET bit `0x40` |
| `$0120` | ISQ (Interrupt Status Queue) | R | `$0000` | Optional (no IRQ on RR-Net) |
| `$0124` | **RxEvent** | R | `$0004` | Reading triggers RX; accept bits |
| `$0138` | **BusST (Bus Status)** | R | `$0018` | Rdy4TxNOW `0x100`, TxBidErr `0x080` |
| `$0144` | **TxCMD (initiate)** | W | — | Transmit command bits (Appendix D) |
| `$0146` | **TxLength** | W | — | Frame length (4…1518) |
| `$0150` | Logical Address (hash) Filter | R/W | `$0000` | Optional |
| `$0158`–`$015D` | **Individual Address (MAC)** | R/W | undefined | Station MAC (6 bytes, LE words) |
| `$0400` | **RxStatus** | R | — | Per-frame RX status |
| `$0402` | **RxLength** | R | — | Received length |
| `$0404`+ | Receive Frame Location (RX buffer) | R | — | RX frame bytes |
| `$0A00`+ | Transmit Frame Location (TX buffer) | W | — | TX frame bytes |

VICE also fakes "link up" at LineST `$0134 = $1294` and SelfST `$0136 = $0896` (INITD bit 7 set) so software sees the chip as ready — copy those if your software checks link status.

## Appendix C — The canonical driver access sequences (test vectors)

Source: cc65/IP65 `drivers/cs8900a.s` (same origin and access sequence as Contiki's C64 driver), cross-checked against VICE `cs8900.c`. These are the exact accesses your VHDL must satisfy. (`packetpp` = `$DE02`, `ppdata` = `$DE04`, `rxtxreg` = `$DE08`, `txcmd` = `$DE0C`, `txlen` = `$DE0E`, `isq` = `$DE00`.)

**Detect / probe:**
```asm
init:
        lda isq+1               ; $DE01: enable carrier clockport (harmless on a direct cart)
        ora #$01
        sta isq+1
        ; Product-ID probe: PacketPage $0000 must read $630E
        lda #$00
        tax
        jsr packetpp_ax         ; PP pointer = $0000  (write $DE02/$DE03)
        lda #$63^$0E
        eor ppdata              ; read $DE04 (low  = $0E)
        eor ppdata+1            ; read $DE05 (high = $63)
        beq ok                  ; $630E present -> chip found
        sec                     ; else "no card"
        rts
```

**Init (after probe):**
| Step | PacketPage write | Value (LE) | Register | Effect |
|---|---|---|---|---|
| 1 | `$0114` | `$0040` | SelfCTL | chip reset; then poll `$0114` until bit `$40` clears |
| 2 | `$0104` | `$0D05` | RxCTL | accept unicast (`$0400`) + broadcast (`$0800`) + correct-CRC (`$0100`) |
| 3 | `$0158`,`$015A`,`$015C` | MAC[0..5] | Individual Address | set station MAC |
| 4 | `$0112` | `$00D3` | LineCTL | SerTxON (`$80`) + SerRxON (`$40`) → TX+RX on |

Each "PacketPage write" = write the offset to `$DE02/$DE03`, then write the value low/high to `$DE04/$DE05`.

**Transmit (`send`):**
```
$DE0C/$DE0D <- $00C9          ; TxCMD (start-after-whole-frame)
$DE0E/$DE0F <- length         ; TxLength
loop: point PP=$0138, read $DE05 (BusST high); test bit $01 (Rdy4TxNOW); if clear, skip an RX frame & retry
then: write frame bytes to $DE08 (even/low) then $DE09 (odd/high), repeated; chip appends FCS and sends
```

**Receive (`poll`):**
```
point PP=$0124, read $DE05 (RxEvent high); test bits $0D (RxOK $01 | IA $04 | Broadcast $08)
  -> reading RxEvent is what makes the model load the next frame
if a frame: read one word ($DE09 then $DE08) = RxStatus (discarded), then one more word = RxLength
then read frame body from $DE08/$DE09 (low then high) for RxLength bytes (rounded up to a whole word)
```

## Appendix D — Key register bit fields

**RxCTL (`$0104`) — which received frames are accepted** (VICE `cs8900.c` decode, datasheet §4.4.8):
| Bit | Mask | Meaning |
|---|---|---|
| B | `$0800` | BroadcastA — accept broadcast (`FF:FF:FF:FF:FF:FF`) |
| A | `$0400` | IndividualA — accept frames matching the station MAC |
| 9 | `$0200` | MulticastA — accept multicast that passes the hash filter |
| 8 | `$0100` | RxOKA — accept frames with good CRC and valid length |
| 7 | `$0080` | PromiscuousA — accept all frames |
| 6 | `$0040` | IAHashA — accept IA that passes the hash filter |

**TxCMD (`$0144` initiate / `$0108` status) — transmit command** (datasheet §4.4.11/§4.5.1):
| Bit | Mask | Meaning |
|---|---|---|
| 8 | `$0100` | Force — delete waiting TX frames / abort current |
| 9 | `$0200` | Onecoll — terminate after one collision |
| C | `$1000` | InhibitCRC — do **not** append FCS (host supplies it) |
| D | `$2000` | TxPadDis — disable padding short frames to 60 bytes |
| 0–5 | `$003F` | identity `001001b` (read-back) |

**LineCTL (`$0112`):** SerRxON = bit 6 `$0040`, SerTxON = bit 7 `$0080`.
**SelfCTL (`$0114`):** RESET = bit 6 `$0040` (act-once; self-clears).
**BusST (`$0138`):** Rdy4TxNOW = bit 8 `$0100`, TxBidErr = bit 7 `$0080`.
**Frame limits:** min 64 / max 1518 bytes on the wire; reject TxLength `<4`; TxBidErr for `>1518` (or `>1514` with CRC not inhibited).

## Appendix E — MEGA65 Ethernet MAC register subset (`mega65-core` `ethernet.vhdl`)

For bridging to the MEGA65 reference MAC. (If you use your own MAC layer, the bridge contract is equivalent.)

| Address | Field | Use |
|---|---|---|
| `$D6E0.7` | TXIDLE (read) | TX complete / ready |
| `$D6E0.0` | RST (write 0 = hold reset) | controller reset |
| `$D6E1.1` | "access next RX frame" (write 0→1 **edge**) | pop/advance RX buffer (edge-triggered; drive low then high) |
| `$D6E1.5` | RXQ (read) | RX frame ready |
| `$D6E2` / `$D6E3.3-0` | TX size low / high | set TX length |
| `$D6E4` | COMMAND (write `$01` = STARTTX) | trigger transmit |
| `$D6E5.0` | NOPROM (0 = promiscuous/accept-all) | filtering mode |
| `$D6E5.1` | NOCRC (1 = deliver bad-FCS frames) | CRC handling |
| `$D6E5.4` / `.5` | accept broadcast / multicast | filtering |
| `$D6E9–$D6EE` | station MAC (MSB first) | hardware filter MAC |
| `$FFDE800–$FFDEFFF` | 2 KB TX buffer (write) / RX buffer (read) | frame staging |
| RX buf `$000/$001` | length lo / (length hi + flags: `.7`=CRC err, `.6`=for-me, `.5`=bcast, `.4`=mcast) | RX header |
| RX buf `$002+` | frame body | RX bytes |

**Note:** the MEGA65 MAC **always appends an FCS on TX** (no inhibit control) and checks FCS on RX. Per `ethernet.vhdl`, the delivered RX body **includes** the 4 FCS bytes and the reported length counts them — so strip the last 4 bytes (and subtract 4 from the length) in the bridge (Part III §4). The PHY on all production MEGA65 boards (R3–R6) is the **Microchip/SMSC KSZ8081RNDCA** (10/100 RMII), per this repo's `top_mega65-r*.vhd` / `MEGA65-R*.xdc`.

## Appendix F — MK3 auto-MAC detection bytes (optional)

In MK3 clockport mode the last four (normally write-only) registers become readable and expose the per-unit MAC tail + checksums (icomp wiki; VICE `clockport-rrnet.c`):

| C64 addr | Returns |
|---|---|
| `$DE0C` | `MAC_HI` (second-last MAC byte) |
| `$DE0D` | `MAC_LO` (last MAC byte) |
| `$DE0E` | `CHKSUM0 = MAC_HI ^ MAC_LO ^ $55` |
| `$DE0F` | `CHKSUM1 = (MAC_HI + MAC_LO + CHKSUM0) ^ $AA` |

If both checksums match, software uses MAC `28:CD:4C:FF:<HI>:<LO>` (Individual Computers' OUI `28:CD:4C`); otherwise the documented default **`28:CD:4C:FF:FB:FF`**. VICE serves `FB/FF` (plus the two derived checksums) for an emulated MK3 clockport. If you skip this, the C64 simply programs a MAC of its own choosing — fully compatible with IP65/Contiki.

## Appendix G — Sources & provenance

**Primary hardware/software references**
- VICE source (read in full): `src/core/cs8900.c` (the CS8900A core — register/PacketPage model, reset values, TX/RX state machines, side-effects), `src/c64/cart/cs8900io.c` (C64 I/O wrapper), `src/c64/cart/rrnetmk3.c` (MK3: `$DE02–$DE0F` XOR-8, `$DE80/$DE88` ROM, `$8000` mapping, MAC-tail reads), `src/c64/cart/clockport-rrnet.c` (clockport RR-Net + default MAC/checksums), `src/c64/cart/ethernetcart.c` (TFE vs RR-Net mode, device family). VICE Team `svn-mirror` (GitHub).
- The real C64 driver: cc65/IP65 `drivers/cs8900a.s` (authors Adam Dunkels & Oliver Schmidt; the IP65 file header credits the Contiki project) — same origin and identical access sequence as Contiki's `cpu/6502/net/cs8900a.S` (not byte-identical: Contiki master uses `$FFxx` runtime-fixed-up equates, IP65 hard-codes `$DE0x`). Equates and probe/init/TX/RX sequences in Appendix C.
- Cirrus Logic **CS8900A Product Data Sheet, DS271F3** (a.k.a. `cs8900a-4.pdf`) — I/O Mode mapping (Table 18), PacketPage pointer (Fig. 18), register reset values and bit fields (§4.3–4.5, §4.10), CRC/FCS and frame limits.
- [wiki.icomp.de/wiki/RR-Net](https://wiki.icomp.de/wiki/RR-Net) — register table, little-endian note, "IRQ not wired," MK3 detection bytes, `$DE80/$DE88` ROM control, clockport-enable (`$DE01` bit 0).
- RR-Net MK3 manual (© 2014 Individual Computers) — installation, carrier cards, direct-cartridge mode, CodeNet-server-from-ROM (hold C=), WarpCopy64 workflow, software list, "The Final Replay" ROM (oxyron).
- [c64-wiki.de](https://www.c64-wiki.de/wiki/RR-Net) / [c64-wiki.com](https://www.c64-wiki.com/wiki/RR-Net) — history (MK1 2003, MK2 Jul 2007, MK3 Feb 2014), chip, variants, software.
- IP65 ([cc65.github.io/ip65](https://cc65.github.io/ip65/), [github.com/cc65/ip65](https://github.com/cc65/ip65)) and NetBoot65 — confirm the full TCP/IP stack runs on the C64; tool catalogue.

**MEGA65 side**
- `mega65-core` `src/vhdl/ethernet.vhdl` — MEGA65 Ethernet MAC register map (`$D6E0–$D6EF`), TX/RX buffers, FCS behaviour, promiscuous/filter bits.
- This repo: `M2M/vhdl/top_mega65-r{3,4,5,6}.vhd` + `M2M/MEGA65-R*.xdc` (PHY = `KSZ8081RNDCA`, Ethernet pins currently stubbed); `CORE/vhdl/main.vhd` (`c64_exp_port_mode_i`, `C_SIM_CRT`/`C_SIM_REU`, `core_ioe`, `cpu_data_in_proc`); `AGENTS.md` (SIMCRT/SIMREU pattern).

**Items to sanity-check on the target board**
- `ethernet.vhdl` shows the RX body **includes** the 4-byte FCS (counted in the length) — strip it in the bridge (Part III §4). Confirm this still holds if you adapt a different MAC for the bridge.
- Exact reset-default values beyond those VICE seeds (use VICE/datasheet values in Appendix B; harmless if a few cosmetic registers differ).

---

*Bottom line: this is far more tractable than the issue feared. No `AT` parser, no modem, no IP stack to write for the C64 side. Build a register-accurate CS8900A (a bounded state machine fully specified by VICE + the datasheet) at `$DE02–$DE0F`, bridge raw frames to the MEGA65 MAC (reusing your existing MAC/CRC/buffering), and every piece of RR-Net software — from WarpCopy64 to Contiki — will run exactly as it does under VICE.*
