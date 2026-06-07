PLA Equations
=============

## From V6 on we are using the following PLA Equations

Source: "The C64 PLA Dissected", Revision 1.1, December 24, 2012 by Thomas
'skoe' Giesel, sections 2.4 to 2.7. Reformatted into the notation already
used in this document. The product terms are reproduced verbatim from the
original 82S100 fuse map  that 'skoe' reverse-engineered.

### PLA inputs

The 82S100 PLA has 16 input pins. The names below use a high-active
interpretation throughout: `i_xxx = '1'` means the corresponding C64 signal is
asserted in the sense described.

* `i_cas`     — `'0'` while the VIC-II asserts /CAS to start a DRAM access in
                the current half-cycle; `'1'` otherwise.
* `i_loram`   — bit 0 of $0001 (LORAM). `'1'` means the bit is set.
* `i_hiram`   — bit 1 of $0001 (HIRAM). `'1'` means the bit is set.
* `i_charen`  — bit 2 of $0001 (CHAREN). `'1'` means the bit is set.
* `i_va14`    — the CIA U2 PA0 output, **before** the 74LS258 (U14)
                inverts it. `i_va14 = '1'` selects VIC banks 0 or 2 (the two
                banks in which the character-set ROM is mirrored into the
                VIC's address space at $1000-$1FFF and $9000-$9FFF
                respectively). `i_va14 = '0'` selects banks 1 or 3.
                Polarity note: the bus signal that ends up on the multiplexed
                address pins is the *inverted* version of `i_va14`, so a
                logic analyzer that probes the address bus reads the opposite
                value of what this `i_va14` indicates.
* `i_a15` .. `i_a12` — the four high-order CPU address bus bits. During CPU
                cycles (`!i_aec`) the CPU drives them. During VIC cycles
                (`i_aec`) they are pulled high by RP4 on the motherboard, so
                they read as "1111" unless a cartridge in Ultimax mode pulls
                them down (this is the so-called "Ultimax trick" that p23 in
                section 2.7 exploits).
* `i_ba`      — VIC-II's "bus available" line. `'1'` when the CPU may use the
                bus, `'0'` while the VIC-II is preparing to take it over for
                a bad line or a sprite fetch.
* `i_aec`     — `'1'` when the VIC-II controls the address bus (VIC cycle);
                `'0'` when the CPU controls it (CPU cycle). The PLA pin is
                /AEC, an inverted version of the VIC's AEC output; this
                `i_aec` notation matches its meaning, not its physical level.
* `i_rd`      — R/W. `'1'` for read, `'0'` for write.
* `i_exrom`   — `'1'` when the cartridge's /EXROM line is not pulled low.
* `i_game`    — `'1'` when the cartridge's /GAME line is not pulled low.
* `i_va13`    — VIC-II's own VA13 address output, read directly by the PLA
                (no inverter in between).
* `i_va12`    — VIC-II's own VA12 address output, read directly by the PLA.

### PLA outputs

The 82S100 has 8 outputs. The C64 names them as low-active pins — they are
`'0'` when asserted. Most equations below therefore negate the OR of selected
chip/strobe product terms. `/CASRAM` is the exception: its product terms
describe cases where DRAM must be hidden or /CAS is idle, so that OR directly
drives `/CASRAM` high.

* `o_casram`  — /CASRAM. Drives /CAS of the DRAM. `'0'` enables a DRAM cycle.
* `o_basic`   — /BASIC. Enables the BASIC ROM ($A000-$BFFF).
* `o_kernal`  — /KERNAL. Enables the KERNAL ROM ($E000-$FFFF).
* `o_charrom` — /CHARROM. Enables the character ROM ($D000-$DFFF for the CPU,
                or the VA14-gated mirror at $1000-$1FFF / $9000-$9FFF for
                the VIC-II).
* `o_grw`     — /GRW. A clean PHI2-aligned write strobe for the static color
                RAM (the color RAM lives at $D800-$DBFF in the IO area).
* `o_io`      — /IO. Asserted for the whole I/O window $D000-$DFFF when the
                I/O area is mapped (see §"#IO1 and #IO2 are not PLA outputs"
                below).
* `o_roml`    — /ROML. Cartridge ROML chip select at $8000-$9FFF.
* `o_romh`    — /ROMH. Cartridge ROMH chip select at $A000-$BFFF (normal
                modes) or $E000-$FFFF (Ultimax), plus the VIC-II ROMH window
                at $3000-$3FFF in Ultimax.

### Cartridge mode mnemonics

Used as shorthand inside the equations. All four are mutually exclusive and
together cover every (i_game, i_exrom) combination.

* `m_no_cart`  =  `i_game & i_exrom`        — no cartridge (both lines pulled
                                              high by RP4). `'1'` when no
                                              cart is plugged in.
* `m_cart8k`   =  `i_game & !i_exrom`       — cart pulls /EXROM low, leaves
                                              /GAME high. `'1'` in 8K cart
                                              mode.
* `m_cart16k`  =  `!i_game & !i_exrom`      — cart pulls both /EXROM and
                                              /GAME low. `'1'` in 16K cart
                                              mode.
* `m_ultimax`  =  `!i_game & i_exrom`       — cart pulls /GAME low, leaves
                                              /EXROM high. `'1'` in Ultimax
                                              mode.

The PDF often writes "cartridge: none or 8k" as a side comment on a product
term. That condition collapses to simply `i_game` (GAME line high) — both
`m_no_cart` and `m_cart8k` have `i_game = '1'`, while the other two modes do
not. The equations below use `i_game` directly when only the GAME line
matters, and the `m_xxx` shorthands when both lines matter together.

### Product terms

These are AND-of-inputs (plus AND-of-inverted-inputs) reproduced from
the JEDEC fuse map of the REV3 8411 PLA. The trailing comments mostly come
straight from the PDF — they are the original author's explanation of each
row. The p23 VADDR comment corrects a likely source typo based on the equation
and the PDF's own VADDR definition.

#### Product term for #BASIC

`p0` (BASIC ROM selected when `p0 = 1`):

```
p0 = addr:[a000..bfff] & i_loram & i_hiram & !i_aec & i_rd & i_game;
     -- LORAM=1, HIRAM=1, no VIC access (CPU has bus), read,
     -- cartridge: none or 8k
```

#### Product terms for #KERNAL

`p1`, `p2` (KERNAL ROM selected when `p1 # p2`):

```
p1 = addr:[e000..ffff] & i_hiram & !i_aec & i_rd & i_game;
     -- HIRAM=1, no VIC access, read, cartridge: none or 8k

p2 = addr:[e000..ffff] & i_hiram & !i_aec & i_rd & m_cart16k;
     -- HIRAM=1, no VIC access, read, cartridge: 16k
```

#### Product terms for #CHARROM

`p3` to `p7` (character ROM selected when any of them is `1`):

```
p3 = addr:[d000..dfff] & i_hiram & !i_charen & !i_aec & i_rd & i_game;
     -- HIRAM=1, CHAREN=0, no VIC access, read, cartridge: none or 8k

p4 = addr:[d000..dfff] & i_loram & !i_charen & !i_aec & i_rd & i_game;
     -- LORAM=1, CHAREN=0, no VIC access, read, cartridge: none or 8k

p5 = addr:[d000..dfff] & i_hiram & !i_charen & !i_aec & i_rd & m_cart16k;
     -- HIRAM=1, CHAREN=0, no VIC access, read, cartridge: 16k

p6 = i_va14 & !i_va13 & i_va12 & i_aec & i_game;
     -- VIC accesses vaddr $1000..$1FFF (bank 0) or $9000..$9FFF (bank 2),
     -- cartridge: none or 8k

p7 = i_va14 & !i_va13 & i_va12 & i_aec & m_cart16k;
     -- VIC accesses vaddr $1000..$1FFF or $9000..$9FFF, cartridge: 16k
```

#### Unused product term p8

`p8` is not used by any sum term. It is documented for completeness because
it is bit-identical to `p31` except that `i_cas` is inverted, which suggests
it is a leftover from an earlier C64 prototype design.

```
p8 = i_cas & addr:[d000..dfff] & !i_aec & !i_rd;
```

#### Product terms for #IO

`p9` to `p18` (any I/O chip or port at $D000-$DFFF selected when any of
them is `1`):

```
p9  = addr:[d000..dfff] & i_hiram & i_charen & !i_aec & i_ba & i_rd & i_game;
      -- HIRAM=1, CHAREN=1, no VIC access, bus available, read,
      -- cartridge: none or 8k

p10 = addr:[d000..dfff] & i_hiram & i_charen & !i_aec & !i_rd & i_game;
      -- HIRAM=1, CHAREN=1, no VIC access, write, cartridge: none or 8k

p11 = addr:[d000..dfff] & i_loram & i_charen & !i_aec & i_ba & i_rd & i_game;
      -- LORAM=1, CHAREN=1, no VIC access, bus available, read,
      -- cartridge: none or 8k

p12 = addr:[d000..dfff] & i_loram & i_charen & !i_aec & !i_rd & i_game;
      -- LORAM=1, CHAREN=1, no VIC access, write, cartridge: none or 8k

p13 = addr:[d000..dfff] & i_hiram & i_charen & !i_aec & i_ba & i_rd & m_cart16k;
      -- HIRAM=1, CHAREN=1, no VIC access, bus available, read,
      -- cartridge: 16k

p14 = addr:[d000..dfff] & i_hiram & i_charen & !i_aec & !i_rd & m_cart16k;
      -- HIRAM=1, CHAREN=1, no VIC access, write, cartridge: 16k

p15 = addr:[d000..dfff] & i_loram & i_charen & !i_aec & i_ba & i_rd & m_cart16k;
      -- LORAM=1, CHAREN=1, no VIC access, bus available, read,
      -- cartridge: 16k

p16 = addr:[d000..dfff] & i_loram & i_charen & !i_aec & !i_rd & m_cart16k;
      -- LORAM=1, CHAREN=1, no VIC access, write, cartridge: 16k

p17 = addr:[d000..dfff] & !i_aec & i_ba & i_rd & m_ultimax;
      -- no VIC access, bus available, read, cartridge: Ultimax

p18 = addr:[d000..dfff] & !i_aec & !i_rd & m_ultimax;
      -- no VIC access, write, cartridge: Ultimax
```

In Ultimax (p17, p18) the LORAM/HIRAM/CHAREN gates are intentionally absent
— the I/O area is always mapped in Ultimax. In every other mode the LORAM
and HIRAM gates together encode the C64's classic memory-map register: I/O
appears only when CHAREN=1 *and* either LORAM=1 or HIRAM=1.

#### Product terms for #ROML

`p19`, `p20` (cart ROML asserted when either is `1`):

```
p19 = addr:[8000..9fff] & i_loram & i_hiram & !i_aec & i_rd & !i_exrom;
      -- LORAM=1, HIRAM=1, no VIC access, read, cartridge: 8k or 16k

p20 = addr:[8000..9fff] & !i_aec & m_ultimax;
      -- no VIC access, cartridge: Ultimax
```

Note that `!i_exrom` in `p19` is the high-active equivalent of the older
`(m_cart8k # m_cart16k)` shorthand used in the V5.2 section below. Both
notations describe the same condition.

#### Product terms for #ROMH

`p21`, `p22`, `p23` (cart ROMH asserted when any is `1`):

```
p21 = addr:[a000..bfff] & i_hiram & !i_aec & i_rd & m_cart16k;
      -- HIRAM=1, no VIC access, read, cartridge: 16k

p22 = addr:[e000..ffff] & !i_aec & m_ultimax;
      -- no VIC access, cartridge: Ultimax (CPU access to ROMH)

p23 = i_va13 & i_va12 & i_aec & m_ultimax;
      -- VIC accesses vaddr $3000..$3FFF, $7000..$7FFF, $B000..$BFFF or
      -- $F000..$FFFF, cartridge: Ultimax (VIC fetch from ROMH)
```

#### Additional product terms for #CASRAM

In Ultimax the DRAM is almost entirely hidden — only $0000-$0FFF and the
window where the cart maps ROML/ROMH remain available to the C64. The PLA
needs the following extra terms to mask out the rest of the DRAM so it does
not contend with the cartridge. (`p24`-`p28` are *only* used in the
#CASRAM sum term; they do not contribute to any of the other outputs.)

```
p24 = addr:[1000..1fff,3000..3fff] & m_ultimax;
      -- CPU/VIC addresses $1000..$1FFF or $3000..$3FFF, Ultimax

p25 = addr:[2000..3fff] & m_ultimax;
      -- CPU/VIC addresses $2000..$3FFF, Ultimax
      -- (overlaps with p24; the two together cover $1000..$3FFF cleanly)

p26 = addr:[4000..7fff] & m_ultimax;
      -- CPU/VIC addresses $4000..$7FFF, Ultimax

p27 = addr:[a000..bfff] & m_ultimax;
      -- CPU/VIC addresses $A000..$BFFF, Ultimax

p28 = addr:[c000..cfff] & m_ultimax;
      -- CPU/VIC addresses $C000..$CFFF, Ultimax
```

The address ranges above are expressed against the four high-order PLA
address inputs only; the PLA does not see A0-A11. The `!i_aec` gate is
intentionally absent — both CPU and VIC accesses in those windows must keep
DRAM disabled in Ultimax mode.

#### Unused product term p29

`p29` is unused. It is bit-identical to `p30` except that `i_cas` is
inverted, suggesting it is another leftover from an early design.

```
p29 = !i_cas;
```

#### Product term to forward #CAS to #CASRAM (p30)

`p30` is the "default-high" carrier for the #CASRAM gate: whenever the
VIC-II is not asserting /CAS, the PLA must keep /CASRAM high too. Combined
with `p0`..`p23` (non-DRAM chip selects) and `p24`..`p28` (Ultimax
hide-DRAM windows), this completes the /CAS → /CASRAM gating mechanism.

```
p30 = i_cas;
      -- i.e. #CAS is HIGH at this moment, meaning no CAS-active VIC cycle
```

#### Product term for #GRW (p31)

The C64 uses static RAM for the color memory at $D800-$DBFF. Because the
SRAM needs its address lines settled before chip-select and write strobes,
the PLA generates a dedicated, PHI2-aligned write strobe `o_grw`. The
strobe gates on `!i_cas` (CAS active, address bus settled) and on
the same $D000-$DFFF window the I/O decoder uses.

```
p31 = !i_cas & addr:[d000..dfff] & !i_aec & !i_rd;
      -- CAS active, address $D000..$DFFF, no VIC access, write
```

Note that the actual write to the color SRAM requires the I/O decoding
elsewhere on the C64 motherboard to also enable color RAM (i.e. `o_io`
asserted and the external 74LS139 demux selecting the color RAM cell).

### Sum terms (final outputs)

These are the actual PLA outputs. `/CASRAM` is a positive OR of "DRAM
disabled" terms. The other outputs are low-active chip selects or strobes, so
their selected-device product terms are negated:

```
o_casram  = (p0  # p1  # p2  #
             p3  # p4  # p5  # p6  # p7  #
             p9  # p10 # p11 # p12 # p13 #
             p14 # p15 # p16 # p17 # p18 #
             p19 # p20 # p21 # p22 # p23 #
             p24 # p25 # p26 # p27 # p28 #
             p30);
o_basic   = ! p0;
o_kernal  = ! (p1 # p2);
o_charrom = ! (p3 # p4 # p5 # p6 # p7);
o_io      = ! (p9 # p10 # p11 # p12 # p13 # p14 # p15 # p16 # p17 # p18);
o_roml    = ! (p19 # p20);
o_romh    = ! (p21 # p22 # p23);
o_grw     = ! p31;
```

The o_casram OR-chain enumerates *every* situation in which DRAM should be
hidden: a BASIC / KERNAL / CHARROM / I/O / ROML / ROMH access elsewhere,
or one of the Ultimax hide-DRAM windows (p24..p28), or the default
"CAS not active" carrier (p30). The unused p8 and p29 do not appear in
any sum.

### Notation legend

* `#` means OR, `!` means NOT, `&` means AND.
* Internal product terms are written high-active. `o_casram` is high when
  DRAM is hidden or /CAS is high; the other final outputs are inverted by the
  `!` in their `o_xxx = !(...)` lines so the chip pin is the expected
  low-active /BASIC, /KERNAL, /CHARROM, /IO, /ROML, /ROMH, /GRW.
* `addr:[XXXX..YYYY]` is a shorthand for "the CPU address bus high nibble
  is in the range corresponding to $XXXX..$YYYY". The PLA only sees
  `i_a15` .. `i_a12`, so the address-range shorthand is at 4 KiB
  granularity. Multiple disjoint ranges are written
  `addr:[XXXX..YYYY,ZZZZ..WWWW]`.
* For the VIC-side address window seen via `i_va13`/`i_va12` (and
  `i_va14` for the bank-mirror gating), the "vaddr" text is included in
  the trailing comment for readability — those bits are listed
  independently in the equation itself.
* `i_loram` / `i_hiram` / `i_charen` follow the high-active polarity of the
  CPU port register at $0001 — writing a 1 to the bit asserts the
  corresponding `i_xxx`.
* `i_aec = '1'` ↔ VIC-II has the bus. `!i_aec` ↔ CPU has the bus.
* `i_rd = '1'` ↔ read. `!i_rd` ↔ write.
* `i_cas = '1'` ↔ /CAS is *not* active in this half-cycle (the VIC is
  idle on the DRAM bus); `!i_cas` ↔ /CAS is active.
* `i_ba` follows the VIC-II's BA pin: `'1'` = bus available to the CPU,
  `'0'` = the VIC is about to halt the CPU.
* `i_va14` follows the *CIA U2 PA0 output* (the bank-select bit
  *before* the 74LS258's inversion). `i_va14 = '1'` means the VIC is in
  bank 0 or bank 2 (the banks in which the character ROM mirror is
  available at $1000-$1FFF and $9000-$9FFF respectively).
* `i_va13`, `i_va12` follow the VIC-II's own VA13/VA12 outputs directly.
* Cartridge mode shorthands: `m_no_cart`, `m_cart8k`, `m_cart16k`,
  `m_ultimax`. See the "Cartridge mode mnemonics" subsection above for the
  Boolean definitions.
* In VIC cycles (`i_aec = '1'`) the CPU address bits `i_a15` .. `i_a12`
  are pulled high by RP4 on the motherboard, so the equations that use
  them during VIC cycles read those bits as `'1'` unless a cartridge in
  Ultimax mode pulls them down (the "Ultimax trick" exploited by `p23`).

### #IO1 and #IO2 are not PLA outputs

The cartridge-side chip selects /IO1 ($DE00-$DEFF) and /IO2 ($DF00-$DFFF)
do **not** come out of the PLA. The PLA produces a single /IO output for
the whole $D000-$DFFF I/O window. The C64 motherboard then demultiplexes
that /IO into eight chip selects using A11..A8 of the CPU address bus
(typically through a 74LS139 at U15):

| `cpuAddr(11:8)` | Chip select | Address window |
| --------------- | ----------- | -------------- |
| 0000-0011       | /VIC        | $D000-$D3FF    |
| 0100-0111       | /SID        | $D400-$D7FF    |
| 1000-1011       | /COLOR      | $D800-$DBFF    |
| 1100            | /CIA1       | $DC00-$DCFF    |
| 1101            | /CIA2       | $DD00-$DDFF    |
| 1110            | /IO1        | $DE00-$DEFF    |
| 1111            | /IO2        | $DF00-$DFFF    |


## Until V5.2 we used the following PLA Equations

Originally from "The C64 PLA Dissected", Revision 1.1, December 24, 2012
by Thomas ’skoe’ Giesel. Rewritten into CUPL and made them easier to read
by Daniel Mantione. Documented for C64MEGA65 by sy2002 in April 2023.


```
p19 = addr:[8000..9fff] & i_loram & i_hiram & !i_aec & i_rd & (m_cart8k # m_cart16k);
p20 = addr:[8000..9fff] & !i_aec & m_ultimax;

p21 = addr:[a000..bfff] & i_hiram & !i_aec & i_rd & m_cart16k;
p22 = addr:[e000..ffff] & !i_aec & m_ultimax;
p23 = i_aec & i_va13 & i_va12 & m_ultimax;

o_roml = ! (p19 # p20);
o_romh = ! (p21 # p22 # p23);

P19 describes the ROML line behaviour in 8K CRT and 16K CRT mode.
P20 describes the ROML line behaviour in Ultimax mode.

P21 describes the ROMH line behaviour in 16K CRT mode.
P22 describes the ROMH line behaviour in Ultimax mode for CPU reads/writes from/to the cartridge.
P23 describes the ROMH line behaviour in Ultimax mode for VIC-II reads from the cartridge.
```

* "#" means or and "!" means not and "&" means "and"
* The formulas are high active logic and then they are turned into the correct
  low active by the "!" in o_roml = ! ... and o_romh = ! ...
* loram and hiram are the loram and hiram lines from the CPU or register $0001.
  They have the same polarity as your write to the register.
* aec decides who has the bus: Low = 6510, High = VIC-II.
  Therefore !i_aec means that the CPU has the bus.
* rd = R/W. Low=Write, High=Read
* m_cart8k means 8K cartridge mode, active high when GAME = 1, EXROM = 0
* m_cart16k means 16K cartridge mode, active high when GAME = 0, EXROM = 0
* m_ultimax means Ultimax mode, active high when GAME = 0, EXROM = 1
* The VIC-II has its own address bus lines, the 6510 and VIC-II are each
  connected to the PLA with their own address bus lies. So va12, va13 means
  address lines a12 and a13 direct from the VIC-II.
