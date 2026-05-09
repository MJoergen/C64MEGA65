# Issue 214: SIMREU Top-of-HyperRAM Regression

## Context

Issue #214 is a regression between the working WIP-V6-A9X4 build
(`70e4de7a8b40e9eb8a1b2cb5cb3e81f00f8ce6eb`) and Alpha 12
(`815779318683c700cd5de2f214af705aa5271743`).

The failing scenario uses the Final Cartridge III 101% SIMCRT together with
SIMREU on an R3 machine. Entering the FC3 freezer monitor works, but returning
to the frozen game corrupts execution. The same workflow works in WIP-V6-A9X4.

Alpha 12 added an important SIMREU address limit in `CORE/vhdl/reu_mapper.vhd`.
That change should remain: it makes the mapper use only the 512 kB REU address
range. However, it does not by itself protect against downstream HyperRAM burst
traffic crossing the physical top of HyperRAM.

## Root Cause

The FC3 101% freezer-monitor path uses high REU addresses deliberately. In its
REU save/restore command table it stores/restores state at addresses such as
`$FFF3D1..$FFFFFF`. On a 512 kB REU, that is legal: the REU address lines wrap,
so those addresses land at the top of the 512 kB REU window.

The MiSTer REU model already implements this semantic wrap:

- `CORE/C64_MiSTerMEGA65/rtl/reu.v` masks REU addresses with `24'h7FFFF` when
  `cfg = 1`, i.e. 512 kB mode.
- Alpha 12 made `CORE/vhdl/reu_mapper.vhd` explicitly map only
  `reu_addr_i(18 downto 1)`, i.e. the 512 kB byte range converted to 16-bit
  HyperRAM words.

The regression comes from where the 512 kB SIMREU backing store was placed.
After the Alpha 10/11 HyperRAM cleanup, `C_HMAP_REU` was moved to `x"03C0"`.
The HyperRAM map unit is 8 kB, so this placed SIMREU at the final 512 kB of the
8 MB HyperRAM device:

```text
C_HMAP_REU = x"03C0"
SIMREU byte range = 0x780000..0x7FFFFF
SIMREU word range = 0x3C0000..0x3FFFFF
```

That looks exact, but the REU path does not only issue the exact single word
requested by the C64-side REU model. The path includes `avm_cache` with
`G_CACHE_SIZE => 8` in `CORE/vhdl/main.vhd`. On a read miss, `avm_cache` issues
an 8-word burst starting at the requested word. It can also prefetch the next
half cache line. Separately, the HyperRAM write errata workaround turns a
single-word write into a two-word burst with a masked dummy beat.

Therefore a valid REU access to the final word of the 512 kB logical REU can
become an invalid physical HyperRAM access:

```text
logical REU byte address after 512 kB wrap = 0x7FFFF
mapped HyperRAM word at old Alpha 12 base  = 0x3FFFFF

8-word cache fill can touch                = 0x3FFFFF..0x400006
2-word errata write can touch              = 0x3FFFFF..0x400000
```

`0x400000` is one word beyond the 8 MB HyperRAM word address range. That is the
bad edge case. It is triggered by FC3 101% because its freezer-monitor support
uses the top of REU memory to preserve and restore the frozen machine state.

WIP-V6-A9X4 did not fail because its effective SIMREU mapping was not at the
physical end of HyperRAM. The old mapper/base combination put the 512 kB REU
window around word range `0x200000..0x23FFFF`, so cache fills and dummy write
beats stayed inside valid HyperRAM even when FC3 accessed the top of logical
REU memory.

## Workaround Applied

The short-term fix moves the SIMREU backing store down by one 8 kB map unit:

```vhdl
constant C_HMAP_REU : std_logic_vector(15 downto 0) := x"03BF";
```

The resulting map is:

```text
M2M/framework:  0x000000..0x3FFFFF  (4 MB)
SIMCRT:         0x400000..0x77DFFF  (~3.49 MB)
SIMREU:         0x77E000..0x7FDFFF  (512 kB)
guard:          0x7FE000..0x7FFFFF  (8 kB)
```

This preserves the C64-visible REU behavior:

- SIMREU is still a 512 kB REU.
- The REU register behavior and wrap semantics remain unchanged.
- Alpha 12's address limit in `reu_mapper.vhd` remains in place.

The only functional map change is that the SIMCRT staging pool is reduced by
exactly 8 kB, and the final 8 kB of HyperRAM becomes an intentional guard band
for SIMREU cache/errata bursts.

This is a workaround rather than a complete architectural fix. It prevents the
known bad physical access by reserving slack above SIMREU, but it does not make
the cache or HyperRAM write-errata logic inherently aware of region boundaries.

## Long-Term Fix Options

### 1. Add a Boundary-Aware REU Memory Path

The most targeted long-term fix is to make the REU HyperRAM path aware of the
512 kB backing-store boundary. Reads near the end of the region should not
cause cache prefetches beyond that region, and writes at the final word should
not generate dummy beats beyond it.

This keeps the fix local to the REU subsystem, where the bounded 512 kB region
is meaningful. It avoids changing shared infrastructure used by SIMCRT, QNICE,
and other HyperRAM clients.

This is the preferred architectural direction.

### 2. Make `avm_cache` Region-Aware

`M2M/vhdl/memory/avm_cache.vhd` could gain optional generics for a legal address
limit or window size. It could then shorten cache fills or suppress prefetches
when a burst would cross the configured boundary.

This is cleaner in the abstract because the component that creates the read
overfetch would also enforce the limit. The risk is that `avm_cache` is shared
infrastructure. A subtle Avalon handshake or latency regression here could
affect more than SIMREU.

This option is good if the same boundary problem appears in other clients, but
it needs broader simulation and hardware testing.

### 3. Make the HyperRAM Errata Workaround Boundary-Aware

`M2M/vhdl/controllers/hyperram/hyperram_errata.vhd` currently turns a one-word
write into a two-word burst. At the final physical word, a safer implementation
could avoid issuing the dummy beat outside HyperRAM. For example, it could use
a dummy beat before the target word instead of after it when the target is at a
boundary.

This fixes only the write side. It does not solve `avm_cache` read prefetches,
so it would need to be combined with another fix.

### 4. Add Boundary Assertions

Add simulation assertions around the HyperRAM-facing Avalon masters:

```text
address + burstcount - 1 must stay inside the legal HyperRAM range
```

For the REU path, also assert that bursts remain inside the SIMREU backing
window unless a guard band is intentionally configured.

Assertions would not fix the hardware by themselves, but they would make this
class of bug visible earlier and would protect future HyperRAM map changes.

## Recommendation

Keep the 8 kB guard-band workaround for the near-term Alpha/WIP fix. It is
small, preserves user-visible behavior, and directly addresses the observed
failure mode with minimal risk.

Also keep Michael's Alpha 12 mapper change. It is still correct and ensures
that the mapper itself implements 512 kB SIMREU semantics.

For a later cleanup, implement a local boundary-aware REU memory path and add
assertions for HyperRAM burst bounds. After that has been tested on the FC3
issue #214 workflow and with explicit top-of-REU read/write tests, the guard
band can either remain as cheap defensive slack or be reclaimed if the lost
8 kB of SIMCRT staging capacity matters.
