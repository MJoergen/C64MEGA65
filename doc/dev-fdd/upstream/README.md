# Pinned upstream reference copies from mega65-core

The seven `.vhdl` files in this folder are **verbatim, unmodified copies** from
the [mega65-core](https://github.com/MEGA65/mega65-core) project
(`src/vhdl/`), pinned at commit `a9158930` (`development` branch, 2026-07-05):

| File | Role in mega65-core |
| --- | --- |
| `mfm_gaps.vhdl` | flux edges → gap intervals |
| `mfm_quantise_gaps.vhdl` | gap intervals → gap classes |
| `mfm_gaps_to_bits.vhdl` | gap classes → MFM bit/sync stream |
| `mfm_bits_to_bytes.vhdl` | MFM bits → decoded bytes |
| `mfm_decoder.vhdl` | sector-level MFM decode |
| `crc1581.vhdl` | CRC-16/CCITT as used on 1581 media |
| `mfm_bits_to_gaps.vhdl` | MFM **write** path (encoder) — reference for the upcoming write/format milestone |

**Author and license:** Paul Gardner-Stephen / the MEGA65 project, LGPLv3.
The upstream files carry no per-file headers, hence this note.

**Why they are here:** they are the adaptation source and review reference for
the `CORE/vhdl/physical_1581/` read-path modules (see the "Adapted from
mega65-core" headers there), kept pinned so any future upstream drift can be
diffed against exactly what was adapted. Since the MEGA65 has no oscilloscope
or logic analyzer, these sources also served as the de-facto datasheet for the
internal drive's pin-level behavior during hardware bring-up.

These copies are development reference material, not part of the synthesized
design.
